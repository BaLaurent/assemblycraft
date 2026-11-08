; region.asm - region files: the saved columns of a streamed world.
;
; <world_dir>/regions/r.<arx>.<arz>.bin holds 32 x 32 columns (arx = acx sar 5). Layout:
;   0..7      "ACREG001"
;   8..8199   1024 entries { dd sector, dd length }, index ((acz & 31) << 5) | (acx & 31);
;             sector 0 = absent; a blob starts on a 4096-byte sector boundary
;   ..12287   padding (the header is 3 sectors)
; A column blob: dd "COL9", dw chunk_mask (bit cy = chunk has a non-AIR block), dw cont_count,
; then for every set bit in ascending cy: dw rle_len and rle_len bytes of {db run - 1, db id} pairs
; covering exactly 4096 cells in chunk order (FIRE is written as AIR); then cont_count CONTSAVE records
; of 120 bytes: db lx, db y, db lz, db kind, 27 x 4 slot bytes, dw burn, dw burn_max, dw cook, dw 0.
; Light is never saved. Up to 16 region tables are cached (least recently used goes first); a missing
; file or one with a bad header is cached as absent. Main thread only.
%include "common.inc"
default rel

global region_dir, region_set_dir, region_read_column, region_write_column, region_flush_cache
global region_has_column

extern conts, item_max_stack
extern file_pread, mkdir_p, str_append, str_copy, i32_to_str, sys_print

%define BLOB_MAX     262144             ; 16 * (2 + 8192) + 64 * 120 + 8 fits easily
%define HDR_SIZE     12288
%define RC_COUNT     16
%define RC_ARX       0                  ; cache entry: arx, arz, valid, absent, stamp, bad, pad, entries
%define RC_ARZ       4
%define RC_VALID     8
%define RC_ABSENT    12
%define RC_STAMP     16
%define RC_BAD       20
%define RC_ENT       32
%define RC_SIZE      (32 + 1024 * 8)
%define CONTSAVE_SIZE 120
%define COL_MAGIC    0x394C4F43         ; "COL9"
%define O_TRUNC      0x200

section .rodata
reg_magic:      db "ACREG001"
s_regions_dir:  db "/regions", 0
s_regions_r:    db "/regions/r.", 0
s_bin:          db ".bin", 0
s_m_region:     db "region r.", 0
s_m_badhdr:     db ".bin: bad header, ignored", 10, 0
s_m_col:        db ".bin: column (", 0
s_m_unread:     db ") unreadable, regenerated", 10, 0

section .bss
alignb 64
region_dir:     resb 4096               ; the world directory; "" = no saving
reg_path:       resb 4200
msg_buf:        resb 512
reg_cache:      resb RC_COUNT * RC_SIZE
reg_stamp:      resd 1
alignb 16
hdr_tmp:        resb HDR_SIZE           ; header read / header to create
stat_buf:       resb 144
alignb 64
blob_buf:       resb BLOB_MAX

section .text

; ---- directory and cache -------------------------------------------------------------------------------

; region_flush_cache(): forget every cached region table (session end, directory change).
region_flush_cache:
    lea     rdi, [reg_cache]
    mov     ecx, RC_COUNT * RC_SIZE / 8
    xor     eax, eax
    rep     stosq
    ret

; region_set_dir(rdi world_dir): saved columns go to <world_dir>/regions; creates that directory.
; 0 or "" disables saving and loading (panorama, tests). Flushes the cache.
region_set_dir:
    push    rbx
    mov     rbx, rdi
    call    region_flush_cache
    test    rbx, rbx
    jz      .off
    cmp     byte [rbx], 0
    je      .off
    lea     rdi, [region_dir]
    mov     rsi, rbx
    mov     edx, 3800
    call    str_copy
    lea     rdi, [reg_path]
    lea     rsi, [region_dir]
    call    str_append
    mov     rdi, rax
    lea     rsi, [s_regions_dir]
    call    str_append
    mov     byte [rax], 0
    lea     rdi, [reg_path]
    call    mkdir_p
    pop     rbx
    ret
.off:
    mov     byte [region_dir], 0
    pop     rbx
    ret

; region_path(edi arx, esi arz) -> rax reg_path = "<dir>/regions/r.<arx>.<arz>.bin"
region_path:
    push    rbx
    push    r12
    push    r13
    mov     r12d, edi
    mov     r13d, esi
    lea     rdi, [reg_path]
    lea     rsi, [region_dir]
    call    str_append
    mov     rdi, rax
    lea     rsi, [s_regions_r]
    call    str_append
    mov     rsi, rax
    mov     edi, r12d
    call    i32_to_str
    mov     byte [rax], '.'
    lea     rsi, [rax + 1]
    mov     edi, r13d
    call    i32_to_str
    mov     rdi, rax
    lea     rsi, [s_bin]
    call    str_append
    mov     byte [rax], 0
    lea     rax, [reg_path]
    pop     r13
    pop     r12
    pop     rbx
    ret

; region_msg(edi arx, esi arz, edx kind, ecx acx, r8d acz): one stderr line about a region file.
; kind 0: "region r.X.Z.bin: bad header, ignored"; 1: "region r.X.Z.bin: column (cx,cz) unreadable,
; regenerated".
region_msg:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12d, edx
    mov     r13d, ecx
    mov     r14d, r8d
    mov     r15d, esi
    mov     ebx, edi
    lea     rdi, [msg_buf]
    lea     rsi, [s_m_region]
    call    str_append
    mov     rsi, rax
    mov     edi, ebx
    call    i32_to_str
    mov     byte [rax], '.'
    lea     rsi, [rax + 1]
    mov     edi, r15d
    call    i32_to_str
    mov     rdi, rax
    test    r12d, r12d
    jnz     .col
    lea     rsi, [s_m_badhdr]
    call    str_append
    jmp     .print
.col:
    lea     rsi, [s_m_col]
    call    str_append
    mov     rsi, rax
    mov     edi, r13d
    call    i32_to_str
    mov     byte [rax], ','
    lea     rsi, [rax + 1]
    mov     edi, r14d
    call    i32_to_str
    mov     rdi, rax
    lea     rsi, [s_m_unread]
    call    str_append
.print:
    mov     byte [rax], 0
    mov     edi, 2
    lea     rsi, [msg_buf]
    call    sys_print
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; reg_get(edi arx, esi arz) -> rax the cache entry of that region (loaded on a miss: a missing file
; is cached as absent, a short file or a wrong magic as absent with a stderr line).
reg_get:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12d, edi
    mov     r13d, esi
    inc     dword [reg_stamp]
    mov     r14d, [reg_stamp]
    lea     rbx, [reg_cache]
    xor     r15d, r15d                  ; victim: the entry with the lowest stamp (invalid ones count 0)
    mov     r9d, 0xFFFFFFFF             ; its stamp
    mov     ecx, RC_COUNT
.scan:
    cmp     dword [rbx + RC_VALID], 0
    je      .invalid
    cmp     [rbx + RC_ARX], r12d
    jne     .stamp
    cmp     [rbx + RC_ARZ], r13d
    jne     .stamp
    mov     [rbx + RC_STAMP], r14d
    mov     rax, rbx
    jmp     .ret
.invalid:
    xor     eax, eax
    jmp     .cand
.stamp:
    mov     eax, [rbx + RC_STAMP]
.cand:
    cmp     eax, r9d
    jae     .next
    mov     r9d, eax
    mov     r15, rbx
.next:
    add     rbx, RC_SIZE
    dec     ecx
    jnz     .scan
    mov     rbx, r15                    ; load into the victim
    mov     edi, r12d
    mov     esi, r13d
    call    region_path
    mov     rdi, rax
    lea     rsi, [hdr_tmp]
    mov     edx, 8200
    xor     ecx, ecx
    call    file_pread
    mov     dword [rbx + RC_BAD], 0
    cmp     rax, -ENOENT
    je      .absent
    cmp     rax, 8200
    jne     .bad
    mov     rax, [reg_magic]
    cmp     [hdr_tmp], rax
    jne     .bad
    lea     rdi, [rbx + RC_ENT]
    lea     rsi, [hdr_tmp + 8]
    mov     ecx, 1024
    rep     movsq
    mov     dword [rbx + RC_ABSENT], 0
    jmp     .fill
.bad:
    mov     edi, r12d
    mov     esi, r13d
    xor     edx, edx
    xor     ecx, ecx
    xor     r8d, r8d
    call    region_msg
    mov     dword [rbx + RC_BAD], 1
.absent:
    lea     rdi, [rbx + RC_ENT]
    mov     ecx, 1024
    xor     eax, eax
    rep     stosq
    mov     dword [rbx + RC_ABSENT], 1
.fill:
    mov     [rbx + RC_ARX], r12d
    mov     [rbx + RC_ARZ], r13d
    mov     dword [rbx + RC_VALID], 1
    mov     [rbx + RC_STAMP], r14d
    mov     rax, rbx
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- reading ----------------------------------------------------------------------------------------------

; region_read_column(edi acx, esi acz, rdx GENBUF*) -> eax 1 found and decoded into the buffer
; (blocks, top, nconts/conts with absolute coordinates, nchests 0, cx/cz), 0 absent or corrupt (a
; corrupt blob prints "region r.X.Z.bin: column (cx,cz) unreadable, regenerated" and is forgotten).
; The biome map is not stored: the caller fills it.
region_read_column:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    cmp     byte [region_dir], 0
    je      .absent
    mov     r12d, edi                   ; acx
    mov     r13d, esi                   ; acz
    mov     r14, rdx                    ; the buffer
    mov     edi, r12d
    sar     edi, 5
    mov     esi, r13d
    sar     esi, 5
    call    reg_get
    mov     rbx, rax
    cmp     dword [rbx + RC_ABSENT], 0
    jne     .absent
    mov     eax, r13d
    and     eax, 31
    shl     eax, 5
    mov     ecx, r12d
    and     ecx, 31
    or      eax, ecx
    mov     r15d, eax                   ; entry index
    mov     ecx, [rbx + RC_ENT + r15*8]     ; sector
    mov     edx, [rbx + RC_ENT + r15*8 + 4] ; length
    test    ecx, ecx
    jz      .absent
    cmp     edx, 8
    jb      .corrupt
    cmp     edx, BLOB_MAX
    ja      .corrupt
    mov     [rsp], edx                  ; length
    mov     edi, r12d
    sar     edi, 5
    mov     esi, r13d
    sar     esi, 5
    push    rcx
    call    region_path
    pop     rcx
    mov     rdi, rax
    lea     rsi, [blob_buf]
    mov     edx, [rsp]
    shl     rcx, 12                     ; sector * 4096
    call    file_pread
    mov     edx, [rsp]
    cmp     rax, rdx
    jne     .corrupt
    lea     rdi, [blob_buf]
    mov     esi, edx
    mov     rdx, r14
    mov     ecx, r12d
    mov     r8d, r13d
    call    decode_blob
    test    eax, eax
    jnz     .ret
.corrupt:
    mov     edi, r12d
    sar     edi, 5
    mov     esi, r13d
    sar     esi, 5
    mov     edx, 1
    mov     ecx, r12d
    mov     r8d, r13d
    call    region_msg
    mov     dword [rbx + RC_ENT + r15*8], 0     ; forget the entry: the column is regenerated
.absent:
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; decode_blob(rdi blob, esi length, rdx GENBUF*, ecx acx, r8d acz) -> eax 1 ok / 0 corrupt.
; Corrupt: wrong magic, a chunk whose runs do not cover exactly 4096 cells, an id >= NUM_BLOCKS, a
; length running past the blob, more than MAX_COL_CONTS containers. A container whose cell does not
; hold a chest (kind chest) or furnace (kind furnace) is dropped, unknown or impossible item stacks are
; cleared, as conts_validate did.
decode_blob:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40                     ; [rsp] end, [rsp + 8] acx, [rsp + 12] acz, [rsp + 16] buffer
    mov     rbx, rdx                    ; the GENBUF
    mov     [rsp + 8], ecx
    mov     [rsp + 12], r8d
    mov     [rsp + 16], rdx
    mov     eax, esi
    add     rax, rdi
    mov     [rsp], rax                  ; the blob's end
    cmp     esi, 8
    jb      .bad
    cmp     dword [rdi], COL_MAGIC
    jne     .bad
    movzx   r12d, word [rdi + 4]        ; chunk mask
    movzx   r13d, word [rdi + 6]        ; container count
    cmp     r13d, MAX_COL_CONTS
    ja      .bad
    mov     [rbx + GENBUF.cx], ecx
    mov     [rbx + GENBUF.cz], r8d
    push    rdi
    lea     rdi, [rbx + GENBUF.blocks]
    mov     ecx, 65536 / 8
    xor     eax, eax
    rep     stosq
    pop     rdi
    lea     r14, [rdi + 8]              ; the cursor
    xor     r15d, r15d                  ; cy
.chunk:
    bt      r12d, r15d
    jnc     .next_chunk
    lea     rax, [r14 + 2]
    cmp     rax, [rsp]
    ja      .bad
    movzx   ecx, word [r14]             ; rle_len
    mov     r14, rax
    lea     rax, [r14 + rcx]
    cmp     rax, [rsp]
    ja      .bad
    test    ecx, 1
    jnz     .bad                        ; whole pairs only
    mov     r10, rax                    ; the run list's end
    mov     rdx, r15
    shl     rdx, 12
    lea     rdi, [rbx + rdx + GENBUF.blocks]
    xor     r8d, r8d                    ; cells written
.run:
    cmp     r14, r10
    jae     .runs_done
    movzx   eax, byte [r14]
    inc     eax                         ; the run length
    movzx   edx, byte [r14 + 1]         ; the block id
    add     r14, 2
    cmp     edx, NUM_BLOCKS
    jae     .bad
    lea     r9d, [r8 + rax]
    cmp     r9d, 4096
    ja      .bad
    mov     ecx, eax
    mov     eax, edx
    mov     r11, rdi
    lea     rdi, [rdi + r8]
    rep     stosb
    mov     rdi, r11
    mov     r8d, r9d
    jmp     .run
.runs_done:
    cmp     r8d, 4096
    jne     .bad
.next_chunk:
    inc     r15d
    cmp     r15d, COL_CHUNKS
    jb      .chunk
    xor     r15d, r15d                  ; kept containers
.cont:
    test    r13d, r13d
    jz     .conts_done
    lea     rax, [r14 + CONTSAVE_SIZE]
    cmp     rax, [rsp]
    ja      .bad
    mov     rsi, r14
    mov     r14, rax
    dec     r13d
    movzx   eax, byte [rsi]             ; lx
    movzx   ecx, byte [rsi + 1]         ; y
    movzx   edx, byte [rsi + 2]         ; lz
    movzx   r9d, byte [rsi + 3]         ; kind
    cmp     eax, 16
    jae     .cont
    cmp     edx, 16
    jae     .cont
    mov     r10d, ecx
    shl     r10d, 8
    mov     r11d, edx
    shl     r11d, 4
    or      r10d, r11d
    or      r10d, eax
    movzx   r10d, byte [rbx + r10 + GENBUF.blocks]   ; the block there
    cmp     r9d, CONT_CHEST
    je      .want_chest
    cmp     r9d, CONT_FURNACE
    jne     .cont
    cmp     r10d, FURNACE
    je      .good
    cmp     r10d, FURNACE_LIT
    je      .good
    jmp     .cont
.want_chest:
    cmp     r10d, CHEST
    jne     .cont
.good:
    mov     r10d, r15d
    imul    r10d, r10d, CONTAINER_size
    lea     rdi, [rbx + r10 + GENBUF.conts]
    push    rax
    push    rcx
    push    rdx
    xor     eax, eax
    mov     ecx, CONTAINER_size / 8
    rep     stosq                       ; a clean record
    pop     rdx
    pop     rcx
    pop     rax
    lea     rdi, [rbx + r10 + GENBUF.conts]
    mov     r8d, [rsp + 8]
    shl     r8d, 4
    add     r8d, eax
    mov     [rdi + CONTAINER.x], r8d    ; absolute cell
    mov     [rdi + CONTAINER.y], ecx
    mov     r8d, [rsp + 12]
    shl     r8d, 4
    add     r8d, edx
    mov     [rdi + CONTAINER.z], r8d
    mov     [rdi + CONTAINER.kind], r9b
    xor     ecx, ecx                    ; the stacks
.stack:
    movzx   eax, byte [rsi + 4 + rcx*4]
    cmp     eax, NUM_ITEMS
    jae     .skip_stack
    lea     rdx, [item_max_stack]
    movzx   edx, byte [rdx + rax]
    test    edx, edx
    jz      .skip_stack                 ; not an item
    movzx   eax, byte [rsi + 5 + rcx*4]
    test    eax, eax
    jz      .skip_stack                 ; an empty stack: no stray id or damage
    cmp     eax, edx
    ja      .skip_stack
    mov     eax, [rsi + 4 + rcx*4]
    mov     [rdi + CONTAINER.slots + rcx*4], eax
.skip_stack:
    inc     ecx
    cmp     ecx, 27
    jb      .stack
    movzx   eax, word [rsi + 112]
    mov     [rdi + CONTAINER.burn], ax
    movzx   eax, word [rsi + 114]
    mov     [rdi + CONTAINER.burn_max], ax
    movzx   eax, word [rsi + 116]
    mov     [rdi + CONTAINER.cook], ax
    inc     r15d
    jmp     .cont
.conts_done:
    mov     [rbx + GENBUF.nconts], r15d
    mov     dword [rbx + GENBUF.nchests], 0
    mov     dword [rbx + GENBUF.top], -1    ; the highest non-AIR cell
    mov     ecx, 255
.top:
    mov     eax, ecx
    shl     eax, 8
    lea     rsi, [rbx + rax + GENBUF.blocks]
    xor     edx, edx
.layer:
    cmp     qword [rsi + rdx*8], 0
    jne     .found
    inc     edx
    cmp     edx, 32
    jb      .layer
    dec     ecx
    jns     .top
    jmp     .ok
.found:
    mov     [rbx + GENBUF.top], ecx
.ok:
    mov     eax, 1
    jmp     .ret
.bad:
    xor     eax, eax
.ret:
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- writing ---------------------------------------------------------------------------------------------------

; chunk_nonempty(rsi chunk) -> eax 1 when a byte is neither AIR nor FIRE (fire is never saved)
chunk_nonempty:
    xor     ecx, ecx
.q:
    mov     rax, [rsi + rcx*8]
    test    rax, rax
    jz      .nq
    mov     edx, 8
.b:
    test    al, al
    jz      .nb
    cmp     al, FIRE
    jne     .yes
.nb:
    shr     rax, 8
    dec     edx
    jnz     .b
.nq:
    inc     ecx
    cmp     ecx, 512
    jb      .q
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; rle_encode(rsi chunk, rdi out) -> rax the end of the written {run - 1, id} pairs (FIRE -> AIR).
rle_encode:
    xor     ecx, ecx
    mov     edx, -1                     ; the id of the current run (none yet)
    xor     r8d, r8d                    ; its length
.cell:
    movzx   eax, byte [rsi + rcx]
    cmp     eax, FIRE
    jne     .mapped
    xor     eax, eax
.mapped:
    cmp     eax, edx
    jne     .flush
    cmp     r8d, 256
    jb      .extend
.flush:
    test    r8d, r8d
    jz      .start
    lea     r9d, [r8 - 1]
    mov     [rdi], r9b
    mov     [rdi + 1], dl
    add     rdi, 2
.start:
    mov     edx, eax
    xor     r8d, r8d
.extend:
    inc     r8d
    inc     ecx
    cmp     ecx, 4096
    jb      .cell
    lea     r9d, [r8 - 1]
    mov     [rdi], r9b
    mov     [rdi + 1], dl
    add     rdi, 2
    mov     rax, rdi
    ret

; pwrite_all(edi fd, rsi buf, rdx len, rcx offset) -> rax 0 / -errno. Clobbers rcx, rdx, rsi, rdi, r8-r11.
pwrite_all:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     ebx, edi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx
.loop:
    test    r13, r13
    jz      .ok
    mov     eax, SYS_PWRITE64
    mov     edi, ebx
    mov     rsi, r12
    mov     rdx, r13
    mov     r10, r14
    syscall
    cmp     rax, -EINTR
    je      .loop
    test    rax, rax
    js      .ret
    jnz     .progress
    mov     rax, -5                     ; -EIO: no progress
    jmp     .ret
.progress:
    add     r12, rax
    add     r14, rax
    sub     r13, rax
    jmp     .loop
.ok:
    xor     eax, eax
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; region_write_column(rdi COLUMN*) -> eax 0 / -errno.
; Encodes the column's chunks and the containers of conts[] inside it, then stores the blob in its
; region file: in place when the old blob's sector count is at least the new one, else appended at the
; end (the entry then points there). A world without a directory has nothing to write (returns 0).
; Sets CF_CONTS in the column's flags when it holds containers, clears it when it does not.
region_write_column:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40                     ; [rsp] blob length, [rsp + 8] region entry, [rsp + 16] index,
                                        ; [rsp + 24] fd, [rsp + 32] entry bytes
    cmp     byte [region_dir], 0
    je      .none
    mov     rbx, rdi
    lea     r12, [blob_buf]
    mov     dword [r12], COL_MAGIC
    lea     r13, [r12 + 8]              ; the write cursor
    xor     r14d, r14d                  ; chunk mask
    xor     r15d, r15d                  ; cy
.chunk:
    mov     rsi, [rbx + COLUMN.chunks + r15*8]
    test    rsi, rsi
    jz      .next_chunk
    call    chunk_nonempty
    test    eax, eax
    jz      .next_chunk
    mov     rsi, [rbx + COLUMN.chunks + r15*8]
    bts     r14d, r15d
    lea     rdi, [r13 + 2]
    call    rle_encode
    mov     rcx, rax
    sub     rcx, r13
    sub     rcx, 2
    mov     [r13], cx                   ; rle_len
    mov     r13, rax
.next_chunk:
    inc     r15d
    cmp     r15d, COL_CHUNKS
    jb      .chunk
    mov     [r12 + 4], r14w
    xor     r15d, r15d                  ; containers written
    lea     rsi, [conts]
    mov     ecx, MAX_CONTAINERS
.cont:
    cmp     byte [rsi + CONTAINER.kind], 0
    je      .next_cont
    mov     eax, [rsi + CONTAINER.x]
    sar     eax, 4
    cmp     eax, [rbx + COLUMN.cx]
    jne     .next_cont
    mov     eax, [rsi + CONTAINER.z]
    sar     eax, 4
    cmp     eax, [rbx + COLUMN.cz]
    jne     .next_cont
    cmp     r15d, MAX_COL_CONTS
    jae     .next_cont
    mov     eax, [rsi + CONTAINER.x]
    mov     [r13], al                   ; lx (the low nibble of the absolute cell)
    and     byte [r13], 15
    mov     eax, [rsi + CONTAINER.y]
    mov     [r13 + 1], al
    mov     eax, [rsi + CONTAINER.z]
    mov     [r13 + 2], al
    and     byte [r13 + 2], 15
    mov     al, [rsi + CONTAINER.kind]
    mov     [r13 + 3], al
    xor     edx, edx
.slot:
    mov     eax, [rsi + CONTAINER.slots + rdx*4]
    mov     [r13 + 4 + rdx*4], eax
    inc     edx
    cmp     edx, 27
    jb      .slot
    movzx   eax, word [rsi + CONTAINER.burn]
    mov     [r13 + 112], ax
    movzx   eax, word [rsi + CONTAINER.burn_max]
    mov     [r13 + 114], ax
    movzx   eax, word [rsi + CONTAINER.cook]
    mov     [r13 + 116], ax
    mov     word [r13 + 118], 0
    add     r13, CONTSAVE_SIZE
    inc     r15d
.next_cont:
    add     rsi, CONTAINER_size
    dec     ecx
    jnz     .cont
    mov     [r12 + 6], r15w
    and     dword [rbx + COLUMN.flags], ~CF_CONTS
    test    r15d, r15d
    jz      .nocont
    or      dword [rbx + COLUMN.flags], CF_CONTS
.nocont:
    sub     r13, r12
    mov     [rsp], r13d                 ; the blob length
    mov     edi, [rbx + COLUMN.cx]
    sar     edi, 5
    mov     esi, [rbx + COLUMN.cz]
    sar     esi, 5
    call    reg_get
    mov     [rsp + 8], rax
    mov     eax, [rbx + COLUMN.cz]
    and     eax, 31
    shl     eax, 5
    mov     ecx, [rbx + COLUMN.cx]
    and     ecx, 31
    or      eax, ecx
    mov     [rsp + 16], eax
    mov     edi, [rbx + COLUMN.cx]
    sar     edi, 5
    mov     esi, [rbx + COLUMN.cz]
    sar     esi, 5
    call    region_path
    mov     rdi, rax
    mov     rbx, [rsp + 8]              ; the cache entry
    mov     esi, O_RDWR
    cmp     dword [rbx + RC_ABSENT], 0
    je      .open
    mov     esi, O_RDWR | O_CREAT | O_TRUNC
.open:
    mov     eax, SYS_OPEN
    mov     edx, MODE_644
    syscall
    test    rax, rax
    js      .ret
    mov     [rsp + 24], rax             ; fd
    cmp     dword [rbx + RC_ABSENT], 0
    je      .header_ok
    lea     rdi, [hdr_tmp]              ; a new file: magic and an empty entry table
    mov     ecx, HDR_SIZE / 8
    xor     eax, eax
    rep     stosq
    mov     rax, [reg_magic]
    mov     [hdr_tmp], rax
    mov     rdi, [rsp + 24]
    lea     rsi, [hdr_tmp]
    mov     edx, HDR_SIZE
    xor     ecx, ecx
    call    pwrite_all
    test    rax, rax
    js      .close_err
    lea     rdi, [rbx + RC_ENT]
    mov     ecx, 1024
    xor     eax, eax
    rep     stosq
    mov     dword [rbx + RC_ABSENT], 0
    mov     dword [rbx + RC_BAD], 0
.header_ok:
    mov     eax, [rsp]                  ; sectors needed
    add     eax, 4095
    shr     eax, 12
    mov     r12d, eax
    mov     ecx, [rsp + 16]
    mov     r13d, [rbx + RC_ENT + rcx*8]        ; the old sector
    mov     r14d, [rbx + RC_ENT + rcx*8 + 4]    ; and length
    test    r13d, r13d
    jz      .append
    add     r14d, 4095
    shr     r14d, 12
    cmp     r14d, r12d
    jae     .place                      ; the old blob has room: write in place
.append:
    mov     eax, SYS_FSTAT
    mov     rdi, [rsp + 24]
    lea     rsi, [stat_buf]
    syscall
    test    rax, rax
    js      .close_err
    mov     rax, [stat_buf + 48]        ; st_size
    add     rax, 4095
    shr     rax, 12
    mov     r13d, 3
    cmp     eax, r13d
    cmova   r13d, eax                   ; after the header, at the first sector past the end
.place:
    mov     rdi, [rsp + 24]
    lea     rsi, [blob_buf]
    mov     edx, [rsp]
    mov     ecx, r13d
    shl     rcx, 12
    call    pwrite_all
    test    rax, rax
    js      .close_err
    mov     [rsp + 32], r13d            ; the entry: sector, length
    mov     eax, [rsp]
    mov     [rsp + 36], eax
    mov     rdi, [rsp + 24]
    lea     rsi, [rsp + 32]
    mov     edx, 8
    mov     ecx, [rsp + 16]
    shl     ecx, 3
    add     ecx, 8
    call    pwrite_all
    test    rax, rax
    js      .close_err
    mov     ecx, [rsp + 16]
    mov     [rbx + RC_ENT + rcx*8], r13d
    mov     eax, [rsp]
    mov     [rbx + RC_ENT + rcx*8 + 4], eax
    mov     eax, SYS_CLOSE
    mov     rdi, [rsp + 24]
    syscall
    xor     eax, eax
    jmp     .ret
.close_err:
    mov     rbx, rax                    ; the error survives the close
    mov     eax, SYS_CLOSE
    mov     rdi, [rsp + 24]
    syscall
    mov     rax, rbx
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; region_has_column(edi acx, esi acz) -> eax 1 when the region file holds a saved blob for that column
; (a table lookup only: no blob is read or decoded).
region_has_column:
    push    rbx
    push    r12
    push    r13
    cmp     byte [region_dir], 0
    je      .no
    mov     r12d, edi
    mov     r13d, esi
    sar     edi, 5
    sar     esi, 5
    call    reg_get
    cmp     dword [rax + RC_ABSENT], 0
    jne     .no
    mov     ecx, r13d
    and     ecx, 31
    shl     ecx, 5
    mov     edx, r12d
    and     edx, 31
    or      ecx, edx
    xor     edx, edx
    cmp     dword [rax + RC_ENT + rcx*8], 0
    setne   dl
    mov     eax, edx
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret
