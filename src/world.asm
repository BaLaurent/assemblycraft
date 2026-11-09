; world.asm - the streamed world: a table of 16 x 256 x 16 columns, each holding up to 16 chunk pointers
; into a static pool (4096 block bytes, then 4096 packed-light bytes per chunk).
;
; Coordinates: every caller outside the world/streaming modules works in LOCAL coordinates;
; absolute = local + world_origin (multiples of 512, so local and absolute share their low 4 bits).
; The columns are MAX_COLUMNS records found through a hashed index: col_index holds a record's slot + 1
; (0 = empty) at the bucket ((acx * 0x9E3779B1) xor (acz * 0x85EBCA6B)) >> 19, probed linearly and
; deleted by shifting the cluster back. A record keeps its slot for as long as it is in use (render.asm
; keys its chunk buffers by it): world_column_claim hands out a released slot first, else the next one never
; used, and world_column_release gives it back. A column is valid while it is in the index and its state is
; not COL_FREE. A null chunk pointer means all AIR with light 0xF0. Chunks 0..top>>4 of an installed
; column are always allocated.
;
; Register contract of the leaf queries (world_get, world_is_solid, world_is_opaque, world_top_y,
; world_column_ready, world_biome_at): every register except eax is preserved. world_set preserves
; rdi, rbx, rbp, r12-r15 and every xmm register. Main thread only.
%include "common.inc"
default rel

global world_header, columns, world_origin_x, world_origin_z, chunk_pool_used, world_install_err
global world_get, world_set, world_set_raw, world_is_solid, world_is_opaque, world_top_y
global world_column_ready, world_biome_at, world_mark_cell_dirty
global world_clear, world_drop_all, world_rebase, world_column, world_column_claim, world_chunk
global world_column_release, world_column_slot, col_index
global world_chunk_alloc, world_locate, world_install, world_unload, world_save_dirty

extern block_flags, block_light
extern light_mark, light_fill_sky
extern conts, conts_free_column, structures_fill_chest
extern game_unload_box, render_column_freed
extern region_dir, region_set_dir, region_write_column
extern sys_print
extern net_role, net_applying, net_block_out

%define COL_HASH_A      0x9E3779B1      ; col_index bucket = ((acx * A) xor (acz * B)) >> 19
%define COL_HASH_B      0x85EBCA6B
%define COL_INV51       0xFAFAFAFB      ; 51 * COL_INV51 = 1 (mod 2^32); COLUMN_size = 8 * 51
%if COL_INDEX != 8192 || COLUMN_size != 408
%error "the column hash and the slot arithmetic are written for COL_INDEX 8192 and COLUMN_size 408"
%endif

section .rodata
s_pool_full:    db "chunk pool full", 10, 0

section .bss
alignb 64
world_header:   resb WORLD_HDR_SIZE
alignb 64
columns:        resb MAX_COLUMNS * COLUMN_size
world_origin_x: resd 1                  ; absolute = local + origin; multiples of 512
world_origin_z: resd 1
chunk_pool_used: resd 1                 ; chunks in use
pool_next:      resd 1                  ; first pool index never handed out
pool_free_n:    resd 1                  ; entries on the free-index stack
pool_msg:       resd 1                  ; "chunk pool full" already printed
world_install_err: resd 1               ; why world_install returned -1: 1 chunk pool, 2 container table
col_index:      resw COL_INDEX          ; hashed index: a record's slot + 1 at the bucket of its key, 0 = empty
col_free_stack: resw MAX_COLUMNS        ; slots world_column_release gave back, the last one on top
col_free_n:     resd 1                  ; entries on col_free_stack
col_next:       resd 1                  ; first record slot never handed out
col_cache_cx:   resd 1                  ; col_find's one-entry cache: the column found last ...
col_cache_cz:   resd 1
alignb 8
col_cache_ptr:  resq 1                  ; ... and its record; 0 = nothing cached
alignb 4096
chunk_pool:     resb POOL_CHUNKS * CHUNK_BYTES
pool_free:      resd POOL_CHUNKS

section .text

; ---- the column index ---------------------------------------------------------------------------------

; COLPROBE acx, acz, bucket, bucket64, entry, entry64, miss: look the column (acx, acz) up in col_index.
; acx and acz are 32-bit registers holding the key; bucket and entry are scratch registers (the 32-bit
; name, then its 64-bit twin for addressing). On a hit - a record in the index with that cx/cz whose state
; is not COL_FREE - `entry` is (slot + 1) * COLUMN_size, so the record is at columns + entry - COLUMN_size;
; on a miss control goes to `miss`. A probe ends at the first empty bucket: the index is at most half full.
%macro COLPROBE 7
    imul    %3, %1, COL_HASH_A
    imul    %5, %2, COL_HASH_B
    xor     %3, %5
    shr     %3, 19                      ; the home bucket
%%probe:
    movzx   %5, word [col_index + %4*2]
    test    %5, %5
    jz      %7
    imul    %5, %5, COLUMN_size
    cmp     [columns + %6 - COLUMN_size + COLUMN.cx], %1
    jne     %%next
    cmp     [columns + %6 - COLUMN_size + COLUMN.cz], %2
    jne     %%next
    cmp     dword [columns + %6 - COLUMN_size + COLUMN.state], COL_FREE
    jne     %%hit
%%next:
    inc     %3
    and     %3, COL_INDEX - 1
    jmp     %%probe
%%hit:
%endmacro

; XMM_SAVE / XMM_LOAD: xmm0-15 to / from the 256 bytes at [rsp]
%macro XMM_SAVE 0
%assign i 0
%rep 16
    movups  [rsp + i * 16], xmm %+ i
%assign i i + 1
%endrep
%endmacro
%macro XMM_LOAD 0
%assign i 0
%rep 16
    movups  xmm %+ i, [rsp + i * 16]
%assign i i + 1
%endrep
%endmacro

; ---- locating cells ---------------------------------------------------------------------------

; col_find: edi = local x, ecx = local z -> r10 = the COLUMN holding that cell's column (any state but
; COL_FREE), or 0. The column found last is remembered and answers without a probe until a column is
; released. Clobbers eax, r8d, r9d.
col_find:
    mov     r8d, edi
    add     r8d, [world_origin_x]
    sar     r8d, 4                      ; acx
    mov     r9d, ecx
    add     r9d, [world_origin_z]
    sar     r9d, 4                      ; acz
    cmp     r8d, [col_cache_cx]
    jne     .look
    cmp     r9d, [col_cache_cz]
    jne     .look
    mov     r10, [col_cache_ptr]
    test    r10, r10
    jz      .look                       ; nothing cached (or released since)
    ret
.look:
    COLPROBE r8d, r9d, eax, rax, r10d, r10, .no
    lea     r10, [columns + r10 - COLUMN_size]
    mov     [col_cache_cx], r8d
    mov     [col_cache_cz], r9d
    mov     [col_cache_ptr], r10
    ret
.no:
    xor     r10d, r10d
    ret

; world_locate: edi x, esi y, edx z (local; all preserved) -> r9 = the cell's COL_LIT column or 0
; (also 0 when y is outside 0..255), r10 = its chunk or 0 (null chunk), eax = the cell's byte index in
; the chunk, (y & 15) << 8 | (z & 15) << 4 | (x & 15). Clobbers ecx, r8d. Also used by light.asm.
world_locate:
    cmp     esi, 255
    ja      .none
    mov     ecx, edx
    call    col_find
    test    r10, r10
    jz      .none
    cmp     dword [r10 + COLUMN.state], COL_LIT
    jne     .none
    mov     r9, r10
    mov     eax, esi
    shr     eax, 4
    mov     r10, [r9 + COLUMN.chunks + rax*8]
    mov     eax, esi
    and     eax, 15
    shl     eax, 8
    mov     ecx, edx
    and     ecx, 15
    shl     ecx, 4
    or      eax, ecx
    mov     ecx, edi
    and     ecx, 15
    or      eax, ecx
    ret
.none:
    xor     r9d, r9d
    xor     r10d, r10d
    ret

; world_get(edi x, esi y, edx z) -> eax id; a column that is not lit or y outside 0..255 -> AIR.
world_get:
    push    rcx
    push    r8
    push    r9
    push    r10
    call    world_locate
    test    r10, r10
    jz      .air
    movzx   eax, byte [r10 + rax]
    jmp     .done
.air:
    xor     eax, eax
.done:
    pop     r10
    pop     r9
    pop     r8
    pop     rcx
    ret

; world_is_solid(edi x, esi y, edx z) -> eax 0/1. Below the world and in a column that is not lit it
; is solid; above the world it is not.
world_is_solid:
    test    esi, esi
    js      .solid
    cmp     esi, 255
    jg      .air
    push    rcx
    push    r8
    push    r9
    push    r10
    call    world_locate
    test    r9, r9
    jz      .unloaded
    test    r10, r10
    jz      .empty
    movzx   eax, byte [r10 + rax]
    movzx   eax, byte [block_flags + rax]
    and     eax, FLAG_SOLID
    jmp     .done
.unloaded:
    mov     eax, 1
    jmp     .done
.empty:
    xor     eax, eax
.done:
    pop     r10
    pop     r9
    pop     r8
    pop     rcx
    ret
.solid:
    mov     eax, 1
    ret
.air:
    xor     eax, eax
    ret

; world_is_opaque(edi x, esi y, edx z) -> eax 0/1; unloaded or outside 0..255 -> 0
world_is_opaque:
    push    rcx
    push    r8
    push    r9
    push    r10
    call    world_locate
    test    r10, r10
    jz      .no
    movzx   eax, byte [r10 + rax]
    movzx   eax, byte [block_flags + rax]
    shr     eax, 1
    and     eax, 1
    jmp     .done
.no:
    xor     eax, eax
.done:
    pop     r10
    pop     r9
    pop     r8
    pop     rcx
    ret

; world_top_y(edi x, esi z) -> eax highest non-AIR y of the cell (x, z), -1 when that cell column is
; empty or its column is not lit. Scans down from COLUMN.top (null chunks skip 16 rows at once).
world_top_y:
    push    rcx
    push    rdx
    push    r8
    push    r9
    push    r10
    mov     ecx, esi
    call    col_find
    mov     eax, -1
    test    r10, r10
    jz      .done
    cmp     dword [r10 + COLUMN.state], COL_LIT
    jne     .done
    mov     edx, edi
    and     edx, 15
    mov     ecx, esi
    and     ecx, 15
    shl     ecx, 4
    or      edx, ecx                    ; edx = (z & 15) << 4 | (x & 15)
    mov     eax, [r10 + COLUMN.top]
.row:
    test    eax, eax
    js      .done                       ; -1: nothing in this cell column
    mov     ecx, eax
    shr     ecx, 4
    mov     r9, [r10 + COLUMN.chunks + rcx*8]
    test    r9, r9
    jz      .skip_chunk
    mov     ecx, eax
    and     ecx, 15
    shl     ecx, 8
    or      ecx, edx
    cmp     byte [r9 + rcx], AIR
    jne     .done
    dec     eax
    jmp     .row
.skip_chunk:
    or      eax, 15                     ; the null chunk's top row, then one below it
    sub     eax, 16
    jmp     .row
.done:
    pop     r10
    pop     r9
    pop     r8
    pop     rdx
    pop     rcx
    ret

; world_column_ready(edi x, esi z) -> eax 1 when the column holding (x, z) is COL_LIT
world_column_ready:
    push    rcx
    push    r8
    push    r9
    push    r10
    mov     ecx, esi
    call    col_find
    xor     eax, eax
    test    r10, r10
    jz      .done
    cmp     dword [r10 + COLUMN.state], COL_LIT
    sete    al
.done:
    pop     r10
    pop     r9
    pop     r8
    pop     rcx
    ret

; world_biome_at(edi x, esi z) -> eax BIOME_*, -1 when the column holds no blocks yet
world_biome_at:
    push    rcx
    push    r8
    push    r9
    push    r10
    mov     ecx, esi
    call    col_find
    mov     eax, -1
    test    r10, r10
    jz      .done
    cmp     dword [r10 + COLUMN.state], COL_BLOCKS
    jb      .done
    mov     eax, esi
    and     eax, 15
    shl     eax, 4
    mov     ecx, edi
    and     ecx, 15
    or      eax, ecx
    movzx   eax, byte [r10 + COLUMN.biome + rax]
.done:
    pop     r10
    pop     r9
    pop     r8
    pop     rcx
    ret

; ---- the chunk pool ------------------------------------------------------------------------------

; world_chunk_alloc(rdi COLUMN*, esi cy) -> rax a fresh chunk now installed in column.chunks[cy]
; (4096 block bytes AIR, 4096 light bytes 0xF0), or 0 when the pool is empty ("chunk pool full" is
; printed once). Preserves rdi, rsi; clobbers rax, rcx, rdx, r8-r11 (the message path is a syscall).
world_chunk_alloc:
    mov     eax, [pool_free_n]
    test    eax, eax
    jz      .bump
    dec     eax
    mov     [pool_free_n], eax
    mov     eax, [pool_free + rax*4]
    jmp     .got
.bump:
    mov     eax, [pool_next]
    cmp     eax, POOL_CHUNKS
    jae     .full
    lea     ecx, [rax + 1]
    mov     [pool_next], ecx
.got:
    inc     dword [chunk_pool_used]
    shl     rax, 13                     ; * CHUNK_BYTES
    lea     rdx, [chunk_pool]
    add     rax, rdx
    mov     edx, esi                    ; cy (rdx is free: the column pointer is in rdi)
    mov     [rdi + COLUMN.chunks + rdx*8], rax
    mov     rdx, rdi
    mov     r8, rax                     ; the chunk, kept across rep stosq
    mov     rdi, rax
    xor     eax, eax
    mov     ecx, CHUNK_BYTES / 16
    rep     stosq                       ; 4096 block bytes
    mov     rax, 0xF0F0F0F0F0F0F0F0
    mov     ecx, CHUNK_BYTES / 16
    rep     stosq                       ; 4096 light bytes: full sky
    mov     rdi, rdx
    mov     rax, r8
    ret
.full:
    cmp     dword [pool_msg], 0
    jne     .quiet
    mov     dword [pool_msg], 1
    push    rdi
    push    rsi
    mov     edi, 2
    lea     rsi, [s_pool_full]
    call    sys_print
    pop     rsi
    pop     rdi
.quiet:
    xor     eax, eax
    ret

; chunk_free: rax = a chunk handed out by world_chunk_alloc, back to the pool. Clobbers rax, rcx, rdx.
chunk_free:
    lea     rdx, [chunk_pool]
    sub     rax, rdx
    shr     rax, 13
    mov     ecx, [pool_free_n]
    mov     [pool_free + rcx*4], eax
    inc     ecx
    mov     [pool_free_n], ecx
    dec     dword [chunk_pool_used]
    ret

; pool_reset: every chunk is free again (no per-chunk work). Clobbers eax.
pool_reset:
    xor     eax, eax
    mov     [chunk_pool_used], eax
    mov     [pool_next], eax
    mov     [pool_free_n], eax
    mov     [pool_msg], eax
    mov     [world_install_err], eax
    ret

; ---- storing blocks ----------------------------------------------------------------------------

; col_rescan(rdi COLUMN*, esi y): the highest non-AIR cell at or below y goes into column.top
; (-1 when there is none). Clobbers eax, ecx, r8, r9.
col_rescan:
    mov     r8d, esi
.next:
    test    r8d, r8d
    js      .none
    mov     eax, r8d
    shr     eax, 4
    mov     r9, [rdi + COLUMN.chunks + rax*8]
    test    r9, r9
    jnz     .layer
    and     r8d, -16
    dec     r8d                         ; the whole chunk is air: continue below it
    jmp     .next
.layer:
    mov     eax, r8d
    and     eax, 15
    shl     eax, 8
    add     r9, rax                     ; the 256 bytes of layer y
    mov     ecx, 32
.q:
    cmp     qword [r9 + rcx*8 - 8], 0
    jne     .found
    dec     ecx
    jnz     .q
    dec     r8d
    jmp     .next
.found:
    mov     [rdi + COLUMN.top], r8d
    ret
.none:
    mov     dword [rdi + COLUMN.top], -1
    ret

; ws_store: the shared body of world_set and world_set_raw. In: r12d x, r13d y, r14d z, r15d id
; (callee-saved copies made by the entry points). Stores the block when the cell's column is lit and
; the id differs, allocating a chunk for a non-AIR block in a null chunk, and keeps column.top (and
; the invariant that chunks 0..top>>4 are allocated) right.
; Out: eax = 1 changed (r9 = the column, ebx = the old id) / 0 nothing happened.
ws_store:
    sub     rsp, 24                     ; [rsp] column, [rsp + 16] cell index
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    call    world_locate
    test    r9, r9
    jz      .no
    mov     [rsp], r9
    mov     [rsp + 16], rax
    test    r10, r10
    jnz     .have
    test    r15d, r15d
    jz      .no                         ; AIR into an empty chunk: nothing to do
    mov     rdi, r9
    mov     esi, r13d
    shr     esi, 4
    call    world_chunk_alloc
    test    rax, rax
    jz      .no                         ; the pool is empty: the edit is dropped
    mov     r10, rax
    xor     ebx, ebx                    ; the old id: AIR
    jmp     .store
.have:
    mov     rax, [rsp + 16]
    movzx   ebx, byte [r10 + rax]
    cmp     ebx, r15d
    je      .no
.store:
    mov     rax, [rsp + 16]
    mov     [r10 + rax], r15b
    mov     rdi, [rsp]
    test    r15d, r15d
    jz      .lower
    cmp     r13d, [rdi + COLUMN.top]
    jle     .done
    mov     [rdi + COLUMN.top], r13d    ; the column grows: allocate every chunk up to y
    mov     r8d, r13d
    shr     r8d, 4
    xor     esi, esi
.fill:
    cmp     qword [rdi + COLUMN.chunks + rsi*8], 0
    jne     .filled
    push    r8
    push    rsi
    call    world_chunk_alloc           ; may fail on an empty pool: the chunk then stays null (all AIR)
    pop     rsi
    pop     r8
.filled:
    inc     esi
    cmp     esi, r8d
    jbe     .fill
    jmp     .done
.lower:
    cmp     r13d, [rdi + COLUMN.top]
    jne     .done
    mov     esi, r13d                   ; the top cell went: look from its own layer down (the cell is AIR
                                        ; now, but other blocks may remain on that layer)
    call    col_rescan
.done:
    mov     r9, [rsp]
    mov     eax, 1
    add     rsp, 24
    ret
.no:
    xor     eax, eax
    add     rsp, 24
    ret

; world_set(edi x, esi y, edx z, ecx id): store the block in a lit column (anything else is ignored,
; including y outside 0..255; an empty pool drops an edit that needs a new chunk). A changed cell
; sets CF_MODIFIED (and CF_CONTS for chests and furnaces), queues its light recompute when its
; opacity, translucency or light emission changed, and marks the chunks around it dirty. While a session is
; open (net_role) and the edit is not one being applied from the network (net_applying), the change is also
; reported: net_block_out(x, y, z, id, old id), with the xmm registers saved around it.
; Preserves rdi, rbx and every xmm register.
world_set:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rdi                         ; the caller's rdi comes back
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edx
    movzx   r15d, cl
    call    ws_store
    test    eax, eax
    jz      .out
    or      dword [r9 + COLUMN.flags], CF_MODIFIED
    lea     eax, [r15 - FURNACE]
    cmp     eax, CHEST - FURNACE
    ja      .plain
    or      dword [r9 + COLUMN.flags], CF_CONTS
.plain:
    movzx   eax, byte [block_flags + rbx]
    movzx   ecx, byte [block_flags + r15]
    xor     eax, ecx
    test    eax, FLAG_OPAQUE | FLAG_TRANSLUCENT
    jnz     .light
    mov     al, [block_light + rbx]
    cmp     al, [block_light + r15]
    je      .dirty
.light:
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    call    light_mark
.dirty:
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    call    world_mark_cell_dirty
    cmp     byte [net_role], NET_ROLE_OFF
    je      .out                        ; offline: nobody to tell
    cmp     byte [net_applying], 0
    jne     .out                        ; a remote edit being applied is never echoed
    sub     rsp, 264                    ; net_block_out may use xmm0-15, which world_set's callers keep
    XMM_SAVE
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, r15d
    mov     r8d, ebx                    ; the old id
    call    net_block_out
    XMM_LOAD
    add     rsp, 264
.out:
    pop     rdi
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; world_set_raw(edi x, esi y, edx z, ecx id): world_set without any hook - no light queue, no dirty
; marks, no CF_MODIFIED. For tests that build a scene and then call light_compute_all.
world_set_raw:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rdi
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edx
    movzx   r15d, cl
    call    ws_store
    pop     rdi
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; world_mark_cell_dirty(edi x, esi y, edx z): set the dirty bit of every chunk (in columns that hold
; blocks) containing a cell of the 3x3x3 neighbourhood of the cell - the chunk itself and, on a chunk
; boundary, its neighbours. Also the mesher's hook for light changes.
; Preserves rdi and rbx; clobbers eax, ecx, edx, esi, r8-r11.
world_mark_cell_dirty:
    lea     eax, [rsi - 1]
    xor     ecx, ecx
    test    eax, eax
    cmovs   eax, ecx
    shr     eax, 4                      ; first chunk row
    lea     r9d, [rsi + 1]
    mov     ecx, 255
    cmp     r9d, ecx
    cmova   r9d, ecx
    shr     r9d, 4                      ; last chunk row
    mov     ecx, r9d
    mov     r8d, 2
    shl     r8d, cl
    dec     r8d                         ; bits 0..last
    mov     ecx, eax
    mov     r9d, 1
    shl     r9d, cl
    dec     r9d
    not     r9d
    and     r8d, r9d                    ; r8d = dirty bits first..last
    lea     eax, [rdi - 1]
    add     eax, [world_origin_x]
    sar     eax, 4                      ; first column x
    lea     ecx, [rdi + 1]
    add     ecx, [world_origin_x]
    sar     ecx, 4                      ; last column x
    lea     r9d, [rdx - 1]
    add     r9d, [world_origin_z]
    sar     r9d, 4                      ; first column z
    lea     r10d, [rdx + 1]
    add     r10d, [world_origin_z]
    sar     r10d, 4                     ; last column z
.z:
    mov     r11d, eax
.x:
    COLPROBE r11d, r9d, esi, rsi, edx, rdx, .skip
    cmp     dword [columns + rdx - COLUMN_size + COLUMN.state], COL_BLOCKS
    jb      .skip
    or      [columns + rdx - COLUMN_size + COLUMN.dirty], r8d
.skip:
    inc     r11d
    cmp     r11d, ecx
    jle     .x
    inc     r9d
    cmp     r9d, r10d
    jle     .z
    ret

; ---- the column table ------------------------------------------------------------------------------

; world_rebase(edi dx, esi dz): the origin moves by (dx, dz); no data moves - local coordinates shift
; by -(dx, dz), the caller (game_rebase) shifts every stored local position.
world_rebase:
    add     [world_origin_x], edi
    add     [world_origin_z], esi
    ret

; world_column(edi acx, esi acz) -> rax the COLUMN of that column when it is in the table in any state but
; COL_FREE, else 0. Clobbers rcx.
world_column:
    COLPROBE edi, esi, eax, rax, ecx, rcx, .no
    lea     rax, [columns + rcx - COLUMN_size]
    ret
.no:
    xor     eax, eax
    ret

; world_column_slot(rdi COLUMN*) -> eax the record's slot, its index in columns[] (render.asm keys its chunk
; buffers by it). COLUMN_size is 8 * 51: the offset shifted right by 3 is slot * 51, and times the inverse
; of 51 modulo 2^32 that is the slot. Clobbers nothing else.
world_column_slot:
    mov     eax, edi
    sub     eax, columns
    shr     eax, 3
    imul    eax, eax, COL_INV51
    ret

; world_column_claim(edi acx, esi acz) -> rax the COLUMN now holding (acx, acz), zeroed and set to
; COL_PENDING with top -1; 0 when all MAX_COLUMNS records are in use (callers treat that like a full pool and
; back off). A free slot is taken - a released one first, else the next never used - and entered in
; col_index. A column that is in the table already is reset in place (callers claim columns they found
; missing). Clobbers rcx, rdx, rdi, r8; preserves rsi.
world_column_claim:
    imul    eax, edi, COL_HASH_A
    imul    ecx, esi, COL_HASH_B
    xor     eax, ecx
    shr     eax, 19                     ; the home bucket
.probe:
    movzx   ecx, word [col_index + rax*2]
    test    ecx, ecx
    jz      .insert
    imul    ecx, ecx, COLUMN_size
    cmp     [columns + rcx - COLUMN_size + COLUMN.cx], edi
    jne     .next
    cmp     [columns + rcx - COLUMN_size + COLUMN.cz], esi
    je      .reuse
.next:
    inc     eax
    and     eax, COL_INDEX - 1
    jmp     .probe
.insert:
    mov     edx, [col_free_n]
    test    edx, edx
    jz      .fresh
    dec     edx
    mov     [col_free_n], edx
    movzx   edx, word [col_free_stack + rdx*2]
    jmp     .have
.fresh:
    mov     edx, [col_next]
    cmp     edx, MAX_COLUMNS
    jae     .full
    lea     ecx, [rdx + 1]
    mov     [col_next], ecx
.have:
    lea     ecx, [rdx + 1]
    mov     [col_index + rax*2], cx     ; the empty bucket the probe ended on
    imul    ecx, edx, COLUMN_size
    lea     r8, [columns + rcx]
    jmp     .init
.reuse:
    lea     r8, [columns + rcx - COLUMN_size]
.init:
    mov     edx, edi                    ; acx survives the clear
    mov     rdi, r8
    xor     eax, eax
    mov     ecx, COLUMN_size / 8
    rep     stosq
    mov     [r8 + COLUMN.cx], edx
    mov     [r8 + COLUMN.cz], esi
    mov     dword [r8 + COLUMN.state], COL_PENDING
    mov     dword [r8 + COLUMN.top], -1
    mov     rax, r8
    ret
.full:
    xor     eax, eax
    ret

; world_column_release(rdi COLUMN*): the column leaves the table. Its record is taken out of col_index (the
; entries after it that sat past their bucket because of it move back), its state becomes COL_FREE and its
; slot goes on the free stack. The caller has returned the chunks. A record that is not in the index (it was
; released already) only gets COL_FREE. Clobbers rax, rcx, rdx, rsi, r8, r9, r10; preserves rdi.
world_column_release:
    mov     qword [col_cache_ptr], 0
    mov     r9d, edi
    sub     r9d, columns
    shr     r9d, 3
    imul    r9d, r9d, COL_INV51
    inc     r9d                         ; slot + 1: what the index holds
    mov     eax, [rdi + COLUMN.cx]
    mov     ecx, [rdi + COLUMN.cz]
    imul    eax, eax, COL_HASH_A
    imul    ecx, ecx, COL_HASH_B
    xor     eax, ecx
    shr     eax, 19                     ; the home bucket
.find:
    movzx   ecx, word [col_index + rax*2]
    test    ecx, ecx
    jz      .gone
    cmp     ecx, r9d
    je      .found
    inc     eax
    and     eax, COL_INDEX - 1
    jmp     .find
.found:
    mov     r8d, eax                    ; i: the hole
    mov     edx, eax                    ; j: the entry being looked at
.shift:
    inc     edx
    and     edx, COL_INDEX - 1
    movzx   ecx, word [col_index + rdx*2]
    test    ecx, ecx
    jz      .close
    imul    ecx, ecx, COLUMN_size
    mov     esi, [columns + rcx - COLUMN_size + COLUMN.cx]
    mov     eax, [columns + rcx - COLUMN_size + COLUMN.cz]
    imul    esi, esi, COL_HASH_A
    imul    eax, eax, COL_HASH_B
    xor     eax, esi
    shr     eax, 19                     ; k: the home bucket of the entry at j
    mov     esi, edx
    sub     esi, eax
    and     esi, COL_INDEX - 1          ; how far j is past its home
    mov     r10d, edx
    sub     r10d, r8d
    and     r10d, COL_INDEX - 1         ; how far j is past the hole
    cmp     esi, r10d
    jb      .shift                      ; its home lies after the hole: it stays
    movzx   ecx, word [col_index + rdx*2]
    mov     [col_index + r8*2], cx      ; it moves into the hole
    mov     r8d, edx                    ; and the hole moves to j
    jmp     .shift
.close:
    mov     word [col_index + r8*2], 0
    mov     ecx, [col_free_n]
    lea     eax, [r9 - 1]
    mov     [col_free_stack + rcx*2], ax
    inc     ecx
    mov     [col_free_n], ecx
.gone:
    mov     dword [rdi + COLUMN.state], COL_FREE
    ret

; world_chunk(edi acx, esi acy, edx acz) -> rax the chunk data (blocks, then light) of column
; (acx, acz) at chunk row acy, or 0 when the column holds no blocks yet (state below COL_BLOCKS),
; is not loaded, or the chunk is null (all AIR, light 0xF0). Clobbers rcx.
world_chunk:
    cmp     esi, 15
    ja      .none
    COLPROBE edi, edx, eax, rax, ecx, rcx, .none
    cmp     dword [columns + rcx - COLUMN_size + COLUMN.state], COL_BLOCKS
    jb      .none
    lea     rax, [columns + rcx - COLUMN_size]
    mov     ecx, esi
    mov     rax, [rax + COLUMN.chunks + rcx*8]
    ret
.none:
    xor     eax, eax
    ret

; ---- installing and unloading ------------------------------------------------------------------------

; world_install(rdi GENBUF*) -> eax 0 installed or stale (nothing done), -1 the pool or the container
; table cannot take the column (nothing changed; world_install_err says which: 1 pool, 2 containers).
; The slot of (buf.cx, buf.cz) must be COL_PENDING, else the result is stale: a column unloaded or a
; session ended while it was generated. Copies chunks 0..top>>4 and the biome map, inserts the
; column's containers into conts[] (decoded records as they are, generated chests as CONT_CHEST
; filled by structures_fill_chest), then sets flags, dirty = 0xFFFF and state = COL_BLOCKS.
world_install:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     rbx, rdi
    mov     edi, [rbx + GENBUF.cx]
    mov     esi, [rbx + GENBUF.cz]
    call    world_column
    test    rax, rax
    jz      .stale
    cmp     dword [rax + COLUMN.state], COL_PENDING
    jne     .stale
    mov     r12, rax                    ; the column
    mov     eax, [rbx + GENBUF.top]
    cmp     eax, 255
    jle     .top_ok
    mov     eax, 255                    ; a generator bug must not overrun the 16 chunk slots
    mov     [rbx + GENBUF.top], eax
.top_ok:
    xor     r13d, r13d                  ; chunks to take: 0 for an empty column, else top>>4 + 1
    test    eax, eax
    js      .counted
    shr     eax, 4
    lea     r13d, [rax + 1]
.counted:
    mov     eax, POOL_CHUNKS
    sub     eax, [chunk_pool_used]
    cmp     eax, r13d
    jb      .pool_full
    mov     r14d, [rbx + GENBUF.nconts]
    add     r14d, [rbx + GENBUF.nchests]
    jz      .allocate
    lea     rdx, [conts]                ; enough free records?
    mov     ecx, MAX_CONTAINERS
    xor     eax, eax
.count:
    cmp     byte [rdx + CONTAINER.kind], 0
    jne     .used
    inc     eax
.used:
    add     rdx, CONTAINER_size
    dec     ecx
    jnz     .count
    cmp     eax, r14d
    jb      .conts_full
.allocate:
    xor     r15d, r15d                  ; cy
.chunk:
    cmp     r15d, r13d
    jae     .chunks_done
    mov     rdi, r12
    mov     esi, r15d
    call    world_chunk_alloc
    mov     rdi, rax                    ; (never 0: the capacity was checked)
    mov     rsi, r15
    shl     rsi, 12
    lea     rsi, [rbx + rsi + GENBUF.blocks]
    mov     ecx, 4096 / 8
    rep     movsq
    inc     r15d
    jmp     .chunk
.chunks_done:
    lea     rdi, [r12 + COLUMN.biome]
    lea     rsi, [rbx + GENBUF.biome]
    mov     ecx, 256 / 8
    rep     movsq
    mov     eax, [rbx + GENBUF.top]
    mov     [r12 + COLUMN.top], eax
    xor     eax, eax
    test    r14d, r14d
    jz      .flags
    mov     eax, CF_CONTS
.flags:
    mov     [r12 + COLUMN.flags], eax
    test    r14d, r14d
    jz      .done
    lea     r14, [conts]                ; r14 = the next free record
    xor     r15d, r15d                  ; i
.dec:
    cmp     r15d, [rbx + GENBUF.nconts]
    jae     .chests
.find1:
    cmp     byte [r14 + CONTAINER.kind], 0
    je      .got1
    add     r14, CONTAINER_size
    jmp     .find1
.got1:
    mov     rdi, r14
    mov     eax, r15d
    imul    eax, eax, CONTAINER_size
    lea     rsi, [rbx + rax + GENBUF.conts]
    mov     ecx, CONTAINER_size / 8
    rep     movsq
    inc     r15d
    jmp     .dec
.chests:
    xor     r15d, r15d                  ; j
.chest:
    cmp     r15d, [rbx + GENBUF.nchests]
    jae     .done
.find2:
    cmp     byte [r14 + CONTAINER.kind], 0
    je      .got2
    add     r14, CONTAINER_size
    jmp     .find2
.got2:
    mov     rdi, r14
    xor     eax, eax
    mov     ecx, CONTAINER_size / 8
    rep     stosq                       ; a clean record
    mov     eax, r15d
    shl     eax, 4                      ; GENCHEST_size = 16
    lea     rsi, [rbx + rax + GENBUF.chests]
    mov     eax, [rsi + GENCHEST.x]
    mov     [r14 + CONTAINER.x], eax
    mov     eax, [rsi + GENCHEST.y]
    mov     [r14 + CONTAINER.y], eax
    mov     eax, [rsi + GENCHEST.z]
    mov     [r14 + CONTAINER.z], eax
    mov     byte [r14 + CONTAINER.kind], CONT_CHEST
    mov     rdi, r14
    call    structures_fill_chest       ; rsi = the GENCHEST
    inc     r15d
    jmp     .chest
.done:
    mov     dword [r12 + COLUMN.dirty], 0xFFFF
    mov     dword [r12 + COLUMN.state], COL_BLOCKS
.stale:
    xor     eax, eax
    jmp     .ret
.pool_full:
    mov     dword [world_install_err], 1
    jmp     .fail
.conts_full:
    mov     dword [world_install_err], 2
.fail:
    mov     eax, -1
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; world_unload(rdi COLUMN*): the caller already saved the column. Removes its entities (game_unload_box
; over its local cells), frees its containers and its render buffers, returns its chunks to the pool
; and releases its record (world_column_release).
world_unload:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     edx, [rbx + COLUMN.cx]
    shl     edx, 4
    sub     edx, [world_origin_x]       ; local x of the column's first cell
    mov     ecx, [rbx + COLUMN.cz]
    shl     ecx, 4
    sub     ecx, [world_origin_z]       ; local z
    mov     edi, edx
    mov     esi, ecx
    add     edx, 15
    add     ecx, 15
    call    game_unload_box
    mov     edi, [rbx + COLUMN.cx]
    mov     esi, [rbx + COLUMN.cz]
    call    conts_free_column
    mov     rdi, rbx
    call    world_column_slot
    mov     edi, eax                    ; the slot index
    call    render_column_freed
    xor     r12d, r12d
.loop:
    mov     rax, [rbx + COLUMN.chunks + r12*8]
    test    rax, rax
    jz      .next
    mov     qword [rbx + COLUMN.chunks + r12*8], 0
    call    chunk_free
.next:
    inc     r12d
    cmp     r12d, COL_CHUNKS
    jb      .loop
    mov     rdi, rbx
    call    world_column_release        ; out of the index, COL_FREE, its slot free again
    pop     r13
    pop     r12
    pop     rbx
    ret

; world_save_dirty(rdi world_dir) -> eax 0 / the first -errno.
; Writes every lit column with CF_MODIFIED or CF_CONTS to its region file and clears CF_MODIFIED of
; the ones written. A world without a directory (panorama) has nothing to save.
world_save_dirty:
    push    rbx
    push    r12
    push    r13
    call    region_set_dir
    xor     r13d, r13d                  ; first error
    cmp     byte [region_dir], 0
    je      .ret
    lea     rbx, [columns]
    mov     r12d, MAX_COLUMNS
.col:
    cmp     dword [rbx + COLUMN.state], COL_LIT
    jne     .next
    test    dword [rbx + COLUMN.flags], CF_MODIFIED | CF_CONTS
    jz      .next
    mov     rdi, rbx
    call    region_write_column
    test    eax, eax
    jz      .written
    test    r13d, r13d
    jnz     .next
    mov     r13d, eax
    jmp     .next
.written:
    and     dword [rbx + COLUMN.flags], ~CF_MODIFIED
.next:
    add     rbx, COLUMN_size
    dec     r12d
    jnz     .col
.ret:
    mov     eax, r13d
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- resets ---------------------------------------------------------------------------------------------

; world_drop_all(): a new session starts - every column goes without being saved. Render buffers of
; the loaded columns are dropped; the pool, conts[] and the column table are reset. The origin stays.
world_drop_all:
    push    rbx
    push    r12
    sub     rsp, 8
    lea     rbx, [columns]
    xor     r12d, r12d                  ; slot
.col:
    cmp     dword [rbx + COLUMN.state], COL_FREE
    je      .next
    mov     edi, r12d
    call    render_column_freed
.next:
    add     rbx, COLUMN_size
    inc     r12d
    cmp     r12d, MAX_COLUMNS
    jb      .col
    call    clear_tables
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; clear_tables: zero the column table, its index and conts[]; the pool is empty again. Clobbers rax, rcx, rdi.
clear_tables:
    lea     rdi, [columns]
    mov     ecx, MAX_COLUMNS * COLUMN_size / 8
    xor     eax, eax
    rep     stosq
    lea     rdi, [col_index]            ; no column is in the index, every slot is unused again
    mov     ecx, COL_INDEX * 2 / 8
    rep     stosq                       ; (rax is 0)
    mov     [col_free_n], eax
    mov     [col_next], eax
    mov     [col_cache_ptr], rax
    lea     rdi, [conts]
    mov     ecx, MAX_CONTAINERS * CONTAINER_size / 8
    xor     eax, eax
    rep     stosq
    jmp     pool_reset

; world_clear(): for the tests - drop every column without saving or running unload hooks, reset the
; pool, conts[] and the origin, then make an arena of empty (all-sky) lit columns for acx and acz in
; [-1, 16], i.e. cells -16..271 in x and z. Returns eax = 0.
world_clear:
    push    rbx
    push    r12
    sub     rsp, 8
    call    clear_tables
    mov     dword [world_origin_x], 0
    mov     dword [world_origin_z], 0
    mov     ebx, -1                     ; acz
.z:
    mov     r12d, -1                    ; acx
.x:
    mov     edi, r12d
    mov     esi, ebx
    call    world_column_claim
    mov     dword [rax + COLUMN.state], COL_LIT
    lea     rdi, [rax + COLUMN.biome]
    mov     rax, 0x0101010101010101     ; BIOME_PLAINS everywhere
    mov     ecx, 256 / 8
    rep     stosq
    inc     r12d
    cmp     r12d, 16
    jle     .x
    inc     ebx
    cmp     ebx, 16
    jle     .z
    call    light_fill_sky              ; nothing queued
    xor     eax, eax
    add     rsp, 8
    pop     r12
    pop     rbx
    ret
