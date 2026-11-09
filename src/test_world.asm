; test_world.asm - world storage tests: columns, chunks, the origin, region files.
%include "common.inc"
default rel

global test_world_bounds, test_world_set_marks_dirty, test_world_save_load
global test_world_rebase, test_region_roundtrip, test_world_column_hash, test_region_encode_roundtrip

extern world_header, world_clear, world_get, world_set, world_is_solid, world_is_opaque
extern world_top_y, world_column, world_column_claim, world_install, world_origin_x, world_origin_z
extern world_rebase, world_save_dirty, world_install_err, light_column, conts
extern region_set_dir, region_read_column
extern dir_remove_tree, file_stat_mtime, file_pread, file_patch
extern world_drop_all, world_column_release, world_column_slot, world_chunk, col_index, columns, world_chunk_alloc
extern region_encode_column, decode_blob, blob_buf
extern gen_column, worldgen_set_seed, gen_seed, cont_create, cont_at

%define HASH_INV_A  0x0E8B2F51          ; the inverse of the bucket hash's multiplier 0x9E3779B1 modulo 2^32

section .rodata
dir_wsl:        db "/tmp/ac9t-wsl", 0
dir_region:     db "/tmp/ac9t-region", 0
file_r00:       db "/tmp/ac9t-region/regions/r.0.0.bin", 0
file_rm10:      db "/tmp/ac9t-region/regions/r.-1.0.bin", 0
flip_byte:      db "X"
hkeys:          dd 0, 0,  64, 0,  0, 64,  64, 64,  -64, -64,  8191, -8191      ; (acx, acz): once the same toroidal slot
hm_buckets:     dd 8189, 8190, 8191, 0, 1, 2                                  ; home buckets of the mixed cluster
hm_order:       db 17, 3, 22, 8, 29, 0, 14, 25, 6, 11, 19, 2, 27, 9, 21, 4, 13, 28, 7, 16, 1, 24, 10, 20, 5, 26, 12, 18, 23, 15

section .bss
alignb 16
gb:             resb GENBUF_size
entry:          resd 2
gb2:            resb GENBUF_size
zeros:          resb 4096
alignb 8
hrec:           resq 6
halive:         resb 30
seed_keep:      resd 1

section .text

; expect eax == value, else fail
%macro EXPECT 1
    cmp     eax, %1
    jne     .fail
%endmacro

; GET x, y, z -> eax = world_get
%macro GET 3
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    call    world_get
%endmacro
; SOLID / OPAQUE x, y, z -> eax
%macro SOLID 3
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    call    world_is_solid
%endmacro
%macro OPAQUE 3
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    call    world_is_opaque
%endmacro
; SET x, y, z, id -> world_set
%macro SET 4
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    call    world_set
%endmacro
; TOPY x, z -> eax = world_top_y
%macro TOPY 2
    mov     edi, %1
    mov     esi, %2
    call    world_top_y
%endmacro
; DIRTY acx, acz -> eax = the column's dirty bits (-1 when the column is not loaded)
%macro DIRTY 2
    mov     edi, %1
    mov     esi, %2
    call    world_column
    mov     edx, -1
    test    rax, rax
    jz      %%none
    mov     edx, [rax + COLUMN.dirty]
%%none:
    mov     eax, edx
%endmacro
; GBLOCK x, y, z -> eax = the block of the decoded column in gb
%macro GBLOCK 3
    movzx   eax, byte [gb + GENBUF.blocks + (((%2) << 8) | ((%3) << 4) | (%1))]
%endmacro

; ---- bounds ------------------------------------------------------------------------------------------------

; Columns outside the arena (cells -16..271) are not loaded, and the world is 256 tall: reads there are
; AIR, "solid" below the world and in unloaded columns, not above it; edits there are ignored. Removing a
; column's top block lowers its top only past the whole layer (another block on it keeps the top).
test_world_bounds:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    GET     1000, 10, 1000
    EXPECT  AIR
    GET     272, 10, 10                 ; the first cell past the arena
    EXPECT  AIR
    GET     -17, 10, 10
    EXPECT  AIR
    GET     5, -1, 5
    EXPECT  AIR
    GET     5, 256, 5
    EXPECT  AIR
    SOLID   1000, 10, 1000
    EXPECT  1
    SOLID   -17, 10, 5
    EXPECT  1
    SOLID   5, -1, 5
    EXPECT  1
    SOLID   5, 300, 5
    EXPECT  0
    SOLID   -1, 10, 10                  ; inside the arena margin: empty air
    EXPECT  0
    SOLID   271, 255, 271
    EXPECT  0
    OPAQUE  1000, 10, 1000
    EXPECT  0
    OPAQUE  5, 300, 5
    EXPECT  0
    SET     1000, 10, 1000, STONE       ; unloaded: ignored
    GET     1000, 10, 1000
    EXPECT  AIR
    SET     5, -1, 5, STONE             ; outside 0..255: ignored
    SET     5, 256, 5, STONE
    GET     5, 0, 5
    EXPECT  AIR
    SET     10, 20, 10, STONE
    GET     10, 20, 10
    EXPECT  STONE
    SOLID   10, 20, 10
    EXPECT  1
    OPAQUE  10, 20, 10
    EXPECT  1
    TOPY    10, 10
    EXPECT  20
    TOPY    11, 11                      ; per cell: a neighbour in the same column stays empty
    EXPECT  -1
    SET     10, 255, 10, GLASS          ; the top layer
    GET     10, 255, 10
    EXPECT  GLASS
    OPAQUE  10, 255, 10                 ; glass is solid but not opaque
    EXPECT  0
    TOPY    10, 10
    EXPECT  255
    SET     -5, 30, -7, BRICK           ; the arena's margin columns work too
    GET     -5, 30, -7
    EXPECT  BRICK
    SET     10, 255, 10, AIR            ; removing the top block lowers the column's top
    TOPY    10, 10
    EXPECT  20
    SET     10, 20, 10, AIR
    TOPY    10, 10
    EXPECT  -1
    TOPY    1000, 10                    ; not loaded
    EXPECT  -1
    TOPY    11, 11                      ; an empty column
    EXPECT  -1
    call    world_clear                 ; two blocks on the top layer: removing one keeps that layer the top
    SET     3, 99, 3, STONE
    SET     1, 100, 1, STONE
    SET     2, 100, 2, STONE
    SET     1, 100, 1, AIR
    TOPY    2, 2
    EXPECT  100
    xor     edi, edi
    xor     esi, esi
    call    world_column
    mov     eax, [rax + COLUMN.top]
    EXPECT  100
    SET     2, 100, 2, AIR              ; the last block of the layer goes: the top falls to the block below
    TOPY    3, 3
    EXPECT  99
    xor     edi, edi
    xor     esi, esi
    call    world_column
    mov     eax, [rax + COLUMN.top]
    EXPECT  99
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- dirty marks -----------------------------------------------------------------------------------------

; world_set marks the chunks that contain a cell of the 3x3x3 neighbourhood: the chunk itself and, on a
; chunk boundary, its neighbours (across columns too)
test_world_set_marks_dirty:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    SET     16, 5, 5, STONE             ; on the x boundary between column 0 and column 1
    DIRTY   0, 0
    EXPECT  1
    DIRTY   1, 0
    EXPECT  1
    DIRTY   2, 0
    EXPECT  0
    DIRTY   0, 1
    EXPECT  0
    call    world_clear
    SET     8, 8, 8, STONE              ; an interior cell marks its own chunk only
    DIRTY   0, 0
    EXPECT  1
    DIRTY   1, 0
    EXPECT  0
    call    world_clear
    SET     5, 15, 5, GLASS             ; y = 15: rows 14..16 touch chunks 0 and 1
    DIRTY   0, 0
    EXPECT  3
    call    world_clear
    SET     -1, 5, 5, STONE             ; negative cells: columns -1 and 0
    DIRTY   -1, 0
    EXPECT  1
    DIRTY   0, 0
    EXPECT  1
    DIRTY   -2, 0
    EXPECT  -1                          ; not loaded
    call    world_clear
    SET     8, 8, 8, STONE
    mov     edi, 0
    mov     esi, 0
    call    world_column
    mov     dword [rax + COLUMN.dirty], 0
    SET     8, 8, 8, STONE              ; the same block again changes nothing: nothing is marked
    DIRTY   0, 0
    EXPECT  0
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- save and load -------------------------------------------------------------------------------------

; reload_column(r12d acx, r13d acz) -> eax 0 ok / 1: free the arena column's slot, read the column
; back from the region files, install it and light it
reload_column:
    push    rbx
    mov     edi, r12d
    mov     esi, r13d
    call    world_column
    test    rax, rax
    jz      .fail
    mov     rdi, rax
    call    world_column_release
    mov     edi, r12d
    mov     esi, r13d
    lea     rdx, [gb]
    call    region_read_column
    cmp     eax, 1
    jne     .fail
    mov     edi, r12d
    mov     esi, r13d
    call    world_column_claim
    mov     rbx, rax
    lea     rdi, [gb]
    call    world_install
    test    eax, eax
    jnz     .fail
    mov     rdi, rbx
    call    light_column
    xor     eax, eax
    pop     rbx
    ret
.fail:
    mov     eax, 1
    pop     rbx
    ret

; prepare_gb(r12d acx, r13d acz): a clean GENBUF for a column that is free again and claimed
; (rax = the claimed COLUMN on return)
prepare_gb:
    sub     rsp, 8
    mov     edi, r12d
    mov     esi, r13d
    call    world_column
    test    rax, rax
    jz      .claim
    mov     rdi, rax
    call    world_column_release
.claim:
    lea     rdi, [gb]
    xor     eax, eax
    mov     ecx, GENBUF_size / 8
    rep     stosq
    mov     [gb + GENBUF.cx], r12d
    mov     [gb + GENBUF.cz], r13d
    mov     edi, r12d
    mov     esi, r13d
    call    world_column_claim
    add     rsp, 8
    ret

; the v6 header layout; a world_save_dirty / region round trip of two modified columns; world_install of
; a generated column with a chest, of a stale one, and into a full container table
test_world_save_load:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
%if WORLDHDR_size != 32768 || WORLDHDR.armor != 944 || WORLDHDR.rpg != 960 || CONTAINER_size != 136
    jmp     .fail
%endif
%if WORLDHDR.jewelry != 16384 || WORLDHDR.rpgx != 16400 || RPGEXT_size != 256
    jmp     .fail
%endif
%if MOB_size != 264 || INVENTORY_size != 216 || SITE_size != 56 || COLUMN_size != 408
    jmp     .fail
%endif
%if WORLDHDR.standing != 588 || WORLDHDR.champions != 604
    jmp     .fail
%endif
%if WORLDHDR.player != 68 || WORLDHDR.health != 136 || WORLDHDR.inventory != 156 || WORLDHDR.origin_x != 300
    jmp     .fail
%endif
%if WORLDHDR.bed_set != 320 || WORLDHDR.boats != 332 || WORLDHDR.mob_count != 1024 || WORLDHDR.mobs != 1028 || WORLDHDR.sites != 2312
    jmp     .fail
%endif
    xor     ebx, ebx                    ; 0 = pass
    call    world_clear
    SET     1, 2, 3, BRICK
    SET     255, 63, 255, GLASS
    lea     rdi, [dir_wsl]
    call    world_save_dirty
    test    eax, eax
    jnz     .bad
    mov     edi, 0
    mov     esi, 0
    call    world_column
    test    rax, rax
    jz      .bad
    test    dword [rax + COLUMN.flags], CF_MODIFIED
    jnz     .bad                        ; written: no longer modified
    call    world_clear                 ; every column goes; the region files stay
    xor     r12d, r12d
    xor     r13d, r13d
    call    reload_column
    test    eax, eax
    jnz     .bad
    mov     r12d, 15
    mov     r13d, 15
    call    reload_column
    test    eax, eax
    jnz     .bad
    GET     1, 2, 3
    cmp     eax, BRICK
    jne     .bad
    GET     255, 63, 255
    cmp     eax, GLASS
    jne     .bad
    GET     2, 2, 3
    test    eax, eax
    jnz     .bad
    TOPY    255, 255
    cmp     eax, 63
    jne     .bad
    ; a generated column with a chest: absolute cell (35, 10, 35), column (2, 2)
    mov     r12d, 2
    mov     r13d, 2
    call    prepare_gb
    mov     r13, rax                    ; the claimed column
    mov     dword [gb + GENBUF.top], 10
    mov     byte [gb + GENBUF.blocks + (10 << 8) + (3 << 4) + 3], CHEST
    mov     dword [gb + GENBUF.nchests], 1
    mov     dword [gb + GENBUF.chests + GENCHEST.x], 35
    mov     dword [gb + GENBUF.chests + GENCHEST.y], 10
    mov     dword [gb + GENBUF.chests + GENCHEST.z], 35
    lea     rdi, [gb]
    call    world_install
    test    eax, eax
    jnz     .bad
    cmp     dword [r13 + COLUMN.state], COL_BLOCKS
    jne     .bad
    cmp     dword [r13 + COLUMN.flags], CF_CONTS
    jne     .bad
    cmp     dword [r13 + COLUMN.top], 10
    jne     .bad
    cmp     dword [r13 + COLUMN.dirty], 0xFFFF
    jne     .bad
    lea     rax, [conts]                ; the chest is in the container table
    mov     ecx, MAX_CONTAINERS
.find:
    cmp     byte [rax + CONTAINER.kind], CONT_CHEST
    jne     .next
    cmp     dword [rax + CONTAINER.x], 35
    jne     .next
    cmp     dword [rax + CONTAINER.y], 10
    jne     .next
    cmp     dword [rax + CONTAINER.z], 35
    je      .found
.next:
    add     rax, CONTAINER_size
    dec     ecx
    jnz     .find
    jmp     .bad
.found:
    lea     rdi, [gb]                   ; the column is installed: a second install is stale and does nothing
    call    world_install
    test    eax, eax
    jnz     .bad
    ; a full container table refuses a column with a chest and changes nothing
    lea     rax, [conts]
    mov     ecx, MAX_CONTAINERS
.fill:
    mov     byte [rax + CONTAINER.kind], CONT_CHEST
    add     rax, CONTAINER_size
    dec     ecx
    jnz     .fill
    mov     r12d, 3
    mov     r13d, 3
    call    prepare_gb
    mov     r13, rax
    mov     dword [gb + GENBUF.top], 10
    mov     dword [gb + GENBUF.nchests], 1
    mov     dword [gb + GENBUF.chests + GENCHEST.x], 51
    mov     dword [gb + GENBUF.chests + GENCHEST.y], 10
    mov     dword [gb + GENBUF.chests + GENCHEST.z], 51
    lea     rdi, [gb]
    call    world_install
    cmp     eax, -1
    jne     .bad
    cmp     dword [world_install_err], 2
    jne     .bad
    cmp     dword [r13 + COLUMN.state], COL_PENDING
    jne     .bad
    jmp     .done
.bad:
    mov     ebx, 1
.done:
    lea     rdi, [dir_wsl]
    call    dir_remove_tree
    xor     edi, edi
    call    region_set_dir
    mov     eax, ebx
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- the floating origin ----------------------------------------------------------------------------------

; the origin shifts local coordinates without moving any data: a cell keeps its absolute place
test_world_rebase:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    SET     3, 20, 4, GLASS
    SET     -5, 10, -7, BRICK
    mov     edi, 512
    mov     esi, -512
    call    world_rebase
    cmp     dword [world_origin_x], 512
    jne     .fail
    cmp     dword [world_origin_z], -512
    jne     .fail
    GET     3 - 512, 20, 4 + 512
    EXPECT  GLASS
    GET     3, 20, 4                    ; the old local cell is now far outside the arena
    EXPECT  AIR
    mov     edi, -512
    mov     esi, 512
    call    world_rebase
    GET     -5, 10, -7
    EXPECT  BRICK
    GET     3, 20, 4
    EXPECT  GLASS
    SOLID   1000, 10, 1000
    EXPECT  1
    GET     1000, 10, 1000
    EXPECT  AIR
    SOLID   5, -1, 5
    EXPECT  1
    SOLID   5, 300, 5
    EXPECT  0
    SET     12, 255, 12, STONE
    GET     12, 255, 12
    EXPECT  STONE
    mov     edi, 512                    ; edits made after a rebase land on the same absolute cell
    xor     esi, esi
    call    world_rebase
    SET     12 - 512, 40, 9, BRICK
    mov     edi, -512
    xor     esi, esi
    call    world_rebase
    GET     12, 40, 9
    EXPECT  BRICK
    GET     12, 255, 12
    EXPECT  STONE
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- region files --------------------------------------------------------------------------------------------

; fill_cells(edi y_first, esi y_last, edx mode): over x, z in 0..15 and y in y_first..y_last, world_set
; mode 0: a pseudo-random id 1..8 (noise that does not compress), 1: AIR, 2: STONE
fill_cells:
    push    rbp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r12d, edi                   ; y
    mov     r13d, esi
    mov     r14d, edx
    mov     r15d, 12345                 ; lcg state
.y:
    xor     ebx, ebx                    ; z * 16 + x
.cell:
    xor     ecx, ecx                    ; mode 1: AIR
    cmp     r14d, 1
    je      .set
    mov     ecx, STONE
    cmp     r14d, 2
    je      .set
    imul    r15d, r15d, 1103515245
    add     r15d, 12345
    mov     ecx, r15d
    shr     ecx, 16
    and     ecx, 7
    inc     ecx
.set:
    mov     edi, ebx
    and     edi, 15
    mov     edx, ebx
    shr     edx, 4
    mov     esi, r12d
    call    world_set
    inc     ebx
    cmp     ebx, 256
    jb      .cell
    inc     r12d
    cmp     r12d, r13d
    jle     .y
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; read_entry(rdi path) -> eax 0 ok: the region's entry of column (0, 0) (sector, length) into `entry`
read_entry:
    sub     rsp, 8
    lea     rsi, [entry]
    mov     edx, 8
    mov     ecx, 8
    call    file_pread
    cmp     rax, 8
    setne   al
    movzx   eax, al
    add     rsp, 8
    ret

; save a lit world with two modified columns, read both back from their region files (FIRE comes back as
; AIR, the chest container with its item), then rewrite column (0, 0) bigger (its blob moves to the end of
; the file) and smaller again (it stays in place), and corrupt its magic (it reads as absent)
test_region_roundtrip:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    xor     ebx, ebx                    ; 0 = pass
    call    world_clear
    lea     rax, [conts]                ; a chest at (4, 10, 4) holding 3 diamonds
    mov     dword [rax + CONTAINER.x], 4
    mov     dword [rax + CONTAINER.y], 10
    mov     dword [rax + CONTAINER.z], 4
    mov     byte [rax + CONTAINER.kind], CONT_CHEST
    mov     byte [rax + CONTAINER.slots], DIAMOND
    mov     byte [rax + CONTAINER.slots + 1], 3
    xor     edi, edi
    mov     esi, 9
    mov     edx, 2
    call    fill_cells                  ; STONE over y 0..9 of column (0, 0)
    SET     2, 200, 3, GLASS
    SET     1, 10, 1, FIRE
    SET     4, 10, 4, CHEST
    SET     -3, 40, 5, BRICK            ; column (-1, 0)
    GET     1, 10, 1
    cmp     eax, FIRE
    jne     .bad
    lea     rdi, [dir_region]
    call    world_save_dirty
    test    eax, eax
    jnz     .bad
    lea     rdi, [file_r00]
    call    file_stat_mtime
    test    rax, rax
    js      .bad
    lea     rdi, [file_rm10]
    call    file_stat_mtime
    test    rax, rax
    js      .bad
    xor     edi, edi
    xor     esi, esi
    lea     rdx, [gb]
    call    region_read_column
    cmp     eax, 1
    jne     .bad
    cmp     dword [gb + GENBUF.top], 200
    jne     .bad
    cmp     dword [gb + GENBUF.nconts], 1
    jne     .bad
    cmp     dword [gb + GENBUF.nchests], 0
    jne     .bad
    GBLOCK  0, 0, 0
    cmp     eax, STONE
    jne     .bad
    GBLOCK  15, 9, 15
    cmp     eax, STONE
    jne     .bad
    GBLOCK  2, 200, 3
    cmp     eax, GLASS
    jne     .bad
    GBLOCK  1, 10, 1                    ; FIRE is never saved
    test    eax, eax
    jnz     .bad
    GBLOCK  4, 10, 4
    cmp     eax, CHEST
    jne     .bad
    GBLOCK  7, 10, 7
    test    eax, eax
    jnz     .bad
    cmp     dword [gb + GENBUF.conts + CONTAINER.x], 4
    jne     .bad
    cmp     dword [gb + GENBUF.conts + CONTAINER.y], 10
    jne     .bad
    cmp     dword [gb + GENBUF.conts + CONTAINER.z], 4
    jne     .bad
    cmp     byte [gb + GENBUF.conts + CONTAINER.kind], CONT_CHEST
    jne     .bad
    cmp     byte [gb + GENBUF.conts + CONTAINER.slots], DIAMOND
    jne     .bad
    cmp     byte [gb + GENBUF.conts + CONTAINER.slots + 1], 3
    jne     .bad
    mov     edi, -1
    xor     esi, esi
    lea     rdx, [gb]
    call    region_read_column
    cmp     eax, 1
    jne     .bad
    cmp     dword [gb + GENBUF.top], 40
    jne     .bad
    cmp     dword [gb + GENBUF.nconts], 0
    jne     .bad
    GBLOCK  13, 40, 5                   ; local x -3 is cell 13 of column -1
    cmp     eax, BRICK
    jne     .bad
    ; bigger: 6 more chunks of noise move the blob to a new sector at the end of the file
    lea     rdi, [file_r00]
    call    read_entry
    test    eax, eax
    jnz     .bad
    mov     r12d, [entry]               ; sector
    mov     r13d, [entry + 4]           ; length
    cmp     r12d, 3
    jne     .bad                        ; the first blob follows the 3-sector header
    mov     edi, 16
    mov     esi, 111
    xor     edx, edx
    call    fill_cells
    lea     rdi, [dir_region]
    call    world_save_dirty
    test    eax, eax
    jnz     .bad
    lea     rdi, [file_r00]
    call    read_entry
    test    eax, eax
    jnz     .bad
    mov     r14d, [entry]               ; the new sector
    cmp     r14d, r12d
    jbe     .bad
    mov     eax, [entry + 4]
    cmp     eax, r13d
    jbe     .bad
    cmp     eax, 6 * 4096
    jb      .bad                        ; noise does not compress
    xor     edi, edi                    ; and it reads back
    xor     esi, esi
    lea     rdx, [gb]
    call    region_read_column
    cmp     eax, 1
    jne     .bad
    ; smaller again: the blob fits its sector run, so it is written in place
    mov     edi, 16
    mov     esi, 111
    mov     edx, 1
    call    fill_cells
    lea     rdi, [dir_region]
    call    world_save_dirty
    test    eax, eax
    jnz     .bad
    lea     rdi, [file_r00]
    call    read_entry
    test    eax, eax
    jnz     .bad
    cmp     [entry], r14d
    jne     .bad
    cmp     dword [entry + 4], 4096
    jae     .bad
    xor     edi, edi
    xor     esi, esi
    lea     rdx, [gb]
    call    region_read_column
    cmp     eax, 1
    jne     .bad
    GBLOCK  3, 20, 3                    ; the noise is gone
    test    eax, eax
    jnz     .bad
    GBLOCK  2, 200, 3
    cmp     eax, GLASS
    jne     .bad
    ; a flipped magic byte: the column is unreadable, the reader says absent
    mov     eax, r14d
    shl     rax, 12
    lea     rdi, [file_r00]
    mov     rsi, rax
    lea     rdx, [flip_byte]
    mov     ecx, 1
    call    file_patch
    test    eax, eax
    jnz     .bad
    xor     edi, edi
    xor     esi, esi
    lea     rdx, [gb]
    call    region_read_column
    test    eax, eax
    jnz     .bad
    jmp     .done
.bad:
    mov     ebx, 1
.done:
    lea     rdi, [dir_region]
    call    dir_remove_tree
    xor     edi, edi
    call    region_set_dir
    mov     eax, ebx
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- the hashed column table -------------------------------------------------------------------------------

; h_key(edi H, esi i) -> eax acx: with acz = 0 the key (acx, 0) has the bucket hash H. The hash is
; (acx * A) >> 19 there, so ((H << 19) | i) times the inverse of A is an acx that lands on H: i tells the keys apart
h_key:
    shl     edi, 19
    or      edi, esi
    imul    eax, edi, HASH_INV_A
    ret

; ch_claim(edi acx, esi acz) -> rax the claimed COLUMN (pending, top -1, its key set, and world_column finds
; it), 0 when the claim failed or one of that is not so
ch_claim:
    push    rbx
    push    r12
    push    r13
    mov     r12d, edi
    mov     r13d, esi
    call    world_column_claim
    test    rax, rax
    jz      .out
    mov     rbx, rax
    cmp     [rbx + COLUMN.cx], r12d
    jne     .bad
    cmp     [rbx + COLUMN.cz], r13d
    jne     .bad
    cmp     dword [rbx + COLUMN.state], COL_PENDING
    jne     .bad
    cmp     dword [rbx + COLUMN.top], -1
    jne     .bad
    mov     edi, r12d
    mov     esi, r13d
    call    world_column
    cmp     rax, rbx
    je      .out
.bad:
    xor     eax, eax
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; h_corners(edi skip) -> eax 0 when the six corner keys are found as the records hrec holds - all but key `skip`,
; which is not found at all
h_corners:
    push    rbx
    push    r13
    sub     rsp, 8
    mov     r13d, edi
    xor     ebx, ebx
.next:
    mov     edi, [hkeys + rbx*8]
    mov     esi, [hkeys + rbx*8 + 4]
    call    world_column
    cmp     ebx, r13d
    je      .gone
    cmp     rax, [hrec + rbx*8]
    jne     .bad
    jmp     .step
.gone:
    test    rax, rax
    jnz     .bad
.step:
    inc     ebx
    cmp     ebx, 6
    jb      .next
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     r13
    pop     rbx
    ret

; h_index_empty() -> eax 1 when no word of col_index is set
h_index_empty:
    lea     rdi, [col_index]
    mov     ecx, COL_INDEX / 4
    xor     eax, eax
    repe    scasd
    sete    al
    movzx   eax, al
    ret

; h_count_index() -> eax the words of col_index that are set
h_count_index:
    lea     rsi, [col_index]
    xor     eax, eax
    mov     ecx, COL_INDEX
.l:
    cmp     word [rsi], 0
    je      .z
    inc     eax
.z:
    add     rsi, 2
    dec     ecx
    jnz     .l
    ret

; hk_claim(edi H, esi n) -> eax 0 when the keys i = 0 .. n - 1 of bucket H were all claimed (and do hash to H)
hk_claim:
    push    rbx
    push    r12
    push    r13
    mov     r12d, edi
    mov     r13d, esi
    xor     ebx, ebx
.next:
    cmp     ebx, r13d
    jae     .ok
    mov     edi, r12d
    mov     esi, ebx
    call    h_key
    imul    ecx, eax, 0x9E3779B1
    shr     ecx, 19
    cmp     ecx, r12d
    jne     .bad                        ; the constant is wrong: these keys would not collide
    mov     edi, eax
    xor     esi, esi
    call    ch_claim
    test    rax, rax
    jz      .bad
    inc     ebx
    jmp     .next
.ok:
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; hk_found(edi H, esi from, edx to) -> eax 0 when the keys i = from .. to - 1 of bucket H are all found
hk_found:
    push    rbx
    push    r12
    push    r13
    mov     r12d, edi
    mov     ebx, esi
    mov     r13d, edx
.next:
    cmp     ebx, r13d
    jae     .ok
    mov     edi, r12d
    mov     esi, ebx
    call    h_key
    mov     edi, eax
    xor     esi, esi
    call    world_column
    test    rax, rax
    jz      .bad
    cmp     [rax + COLUMN.cx], edi
    jne     .bad
    cmp     dword [rax + COLUMN.cz], 0
    jne     .bad
    inc     ebx
    jmp     .next
.ok:
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; hk_release(edi H, esi i) -> eax 0 when key i of bucket H was found, released (COL_FREE) and is not found any more
hk_release:
    push    rbx
    push    r12
    push    r13
    call    h_key
    mov     r12d, eax
    mov     edi, eax
    xor     esi, esi
    call    world_column
    test    rax, rax
    jz      .bad
    mov     rbx, rax
    mov     rdi, rax
    call    world_column_release
    cmp     dword [rbx + COLUMN.state], COL_FREE
    jne     .bad
    mov     edi, r12d
    xor     esi, esi
    call    world_column
    test    rax, rax
    jnz     .bad
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; hm_key(edi j) -> eax the acx of key j of the mixed cluster: 6 buckets in a row across the end of the index, 5 keys each
hm_key:
    mov     eax, edi
    xor     edx, edx
    mov     ecx, 5
    div     ecx                         ; eax = the bucket's number, edx = the key within it
    mov     edi, [hm_buckets + rax*4]
    mov     esi, edx
    jmp     h_key

; hm_check() -> eax 0 when exactly the keys marked in halive are found
hm_check:
    push    rbx
    push    r12
    push    r13
    xor     ebx, ebx
.next:
    mov     edi, ebx
    call    hm_key
    mov     r12d, eax
    mov     edi, eax
    xor     esi, esi
    call    world_column
    cmp     byte [halive + rbx], 0
    je      .dead
    test    rax, rax
    jz      .bad
    cmp     [rax + COLUMN.cx], r12d
    jne     .bad
    jmp     .step
.dead:
    test    rax, rax
    jnz     .bad
.step:
    inc     ebx
    cmp     ebx, 30
    jb      .next
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; the hashed column table. Six keys that shared a toroidal slot before - (0,0) (64,0) (0,64) (64,64) (-64,-64)
; (8191,-8191) - are all in the table at once, and releasing (64,0) leaves the others found. 3000 keys with the
; same home bucket are claimed, found and released in reverse; 200 more released from the head of their
; cluster; 30 keys of six neighbouring buckets across the end of the index, interleaved, released in a scrambled
; order, are found exactly while they are in the table. col_index is empty after each. MAX_COLUMNS claims fit,
; the next one fails, and a release makes room for one. -> eax 0 = pass
test_world_column_hash:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    xor     ebx, ebx                    ; 0 = pass
    call    world_clear                 ; origin 0
    call    world_drop_all
    call    h_index_empty
    cmp     eax, 1
    jne     .bad
    xor     r12d, r12d                  ; the six corner keys
.corner:
    mov     edi, [hkeys + r12*8]
    mov     esi, [hkeys + r12*8 + 4]
    call    ch_claim
    test    rax, rax
    jz      .bad
    mov     [hrec + r12*8], rax
    xor     ecx, ecx                    ; a record of its own
.own:
    cmp     ecx, r12d
    jae     .owned
    cmp     rax, [hrec + rcx*8]
    je      .bad
    inc     ecx
    jmp     .own
.owned:
    mov     rdi, rax                    ; world_column_slot and columns[] agree
    call    world_column_slot
    cmp     eax, MAX_COLUMNS
    jae     .bad
    imul    eax, eax, COLUMN_size
    lea     rdx, [columns]
    add     rdx, rax
    cmp     rdx, [hrec + r12*8]
    jne     .bad
    inc     r12d
    cmp     r12d, 6
    jb      .corner
    mov     edi, -1
    call    h_corners                   ; all six are found
    test    eax, eax
    jnz     .bad
    mov     rdi, [hrec + 8]             ; release (64, 0)
    call    world_column_release
    mov     edi, 1
    call    h_corners                   ; the others are, it is not
    test    eax, eax
    jnz     .bad
    mov     edi, 64                     ; claimed again, it is found again
    xor     esi, esi
    call    ch_claim
    test    rax, rax
    jz      .bad
    mov     [hrec + 8], rax
    mov     edi, -1
    call    h_corners
    test    eax, eax
    jnz     .bad
    xor     r12d, r12d                  ; all six go
.six:
    mov     rdi, [hrec + r12*8]
    call    world_column_release
    inc     r12d
    cmp     r12d, 6
    jb      .six
    call    h_index_empty
    cmp     eax, 1
    jne     .bad
    mov     edi, 2000                   ; 3000 keys of one home bucket
    mov     esi, 3000
    call    hk_claim
    test    eax, eax
    jnz     .bad
    mov     edi, 2000
    xor     esi, esi
    mov     edx, 3000
    call    hk_found
    test    eax, eax
    jnz     .bad
    call    h_count_index
    cmp     eax, 3000
    jne     .bad
    mov     r14d, 2999                  ; released in reverse
.rev:
    mov     edi, 2000
    mov     esi, r14d
    call    hk_release
    test    eax, eax
    jnz     .bad
    mov     eax, r14d
    xor     edx, edx
    mov     ecx, 250
    div     ecx
    test    edx, edx
    jnz     .rev_next
    mov     edi, 2000                   ; now and then: the ones before the hole are all still found
    xor     esi, esi
    mov     edx, r14d
    call    hk_found
    test    eax, eax
    jnz     .bad
.rev_next:
    dec     r14d
    jns     .rev
    call    h_index_empty
    cmp     eax, 1
    jne     .bad
    mov     edi, 7777                   ; 200 keys of another bucket, released from the head of the cluster
    mov     esi, 200
    call    hk_claim
    test    eax, eax
    jnz     .bad
    xor     r14d, r14d
.head:
    mov     edi, 7777
    mov     esi, r14d
    call    hk_release
    test    eax, eax
    jnz     .bad
    mov     edi, 7777                   ; every key behind it moved up and is still found
    lea     esi, [r14 + 1]
    mov     edx, 200
    call    hk_found
    test    eax, eax
    jnz     .bad
    inc     r14d
    cmp     r14d, 200
    jb      .head
    call    h_index_empty
    cmp     eax, 1
    jne     .bad
    lea     rdi, [halive]               ; the mixed cluster: 5 keys in each of 6 buckets, interleaved
    mov     ecx, 30
    xor     eax, eax
    rep     stosb
    xor     r14d, r14d                  ; i
.mix_i:
    xor     r15d, r15d                  ; bucket
.mix_b:
    lea     eax, [r15 + r15*4]
    add     eax, r14d                   ; j = bucket * 5 + i
    mov     r13d, eax
    mov     edi, eax
    call    hm_key
    mov     edi, eax
    xor     esi, esi
    call    ch_claim
    test    rax, rax
    jz      .bad
    mov     byte [halive + r13], 1
    inc     r15d
    cmp     r15d, 6
    jb      .mix_b
    inc     r14d
    cmp     r14d, 5
    jb      .mix_i
    call    hm_check
    test    eax, eax
    jnz     .bad
    call    h_count_index
    cmp     eax, 30
    jne     .bad
    xor     r14d, r14d
.mix_rel:
    movzx   r13d, byte [hm_order + r14]
    mov     edi, r13d
    call    hm_key
    mov     r12d, eax
    mov     edi, eax
    xor     esi, esi
    call    world_column
    test    rax, rax
    jz      .bad
    mov     rdi, rax
    call    world_column_release
    mov     byte [halive + r13], 0
    call    hm_check
    test    eax, eax
    jnz     .bad
    inc     r14d
    cmp     r14d, 30
    jb      .mix_rel
    call    h_index_empty
    cmp     eax, 1
    jne     .bad
    xor     edi, edi                    ; col_find remembers the column it found last: not a released one
    xor     esi, esi
    call    ch_claim                    ; column (0, 0), lit
    test    rax, rax
    jz      .bad
    mov     dword [rax + COLUMN.state], COL_LIT
    mov     r12, rax
    GET     1, 1, 1                     ; remembered now
    mov     rdi, r12
    call    world_column_release
    mov     edi, 64
    xor     esi, esi
    call    ch_claim                    ; column (64, 0) takes the slot that was just given back
    test    rax, rax
    jz      .bad
    cmp     rax, r12
    jne     .bad
    mov     dword [rax + COLUMN.state], COL_LIT
    mov     rdi, rax
    xor     esi, esi
    call    world_chunk_alloc           ; a chunk of its own with a block at (1, 1, 1) of the column
    test    rax, rax
    jz      .bad
    mov     byte [rax + (1 << 8) + (1 << 4) + 1], STONE
    GET     1, 1, 1                     ; column (0, 0) is gone
    test    eax, eax
    jnz     .bad
    GET     64 * 16 + 1, 1, 1           ; column (64, 0) is there
    cmp     eax, STONE
    jne     .bad
    mov     edi, 64
    xor     esi, esi
    call    world_column
    test    rax, rax
    jz      .bad
    mov     rdi, rax
    call    world_column_release
    call    h_index_empty
    cmp     eax, 1
    jne     .bad
    xor     r12d, r12d                  ; MAX_COLUMNS keys fit
.cap:
    mov     edi, r12d
    imul    esi, r12d, 31
    and     esi, 255
    call    ch_claim
    test    rax, rax
    jz      .bad
    inc     r12d
    cmp     r12d, MAX_COLUMNS
    jb      .cap
    mov     edi, 100000                 ; the next one does not
    xor     esi, esi
    call    world_column_claim
    test    rax, rax
    jnz     .bad
    mov     edi, 1234                   ; a release makes room for exactly one
    mov     esi, (1234 * 31) & 255
    call    world_column
    test    rax, rax
    jz      .bad
    mov     rdi, rax
    call    world_column_release
    mov     edi, 100000
    xor     esi, esi
    call    ch_claim
    test    rax, rax
    jz      .bad
    mov     edi, 100001
    xor     esi, esi
    call    world_column_claim
    test    rax, rax
    jnz     .bad
    mov     edi, 100000
    xor     esi, esi
    call    world_column
    mov     rdi, rax
    call    world_column_release
    xor     r12d, r12d                  ; and every other one goes
.free:
    cmp     r12d, 1234
    je      .free_next
    mov     edi, r12d
    imul    esi, r12d, 31
    and     esi, 255
    call    world_column
    test    rax, rax
    jz      .bad
    mov     rdi, rax
    call    world_column_release
.free_next:
    inc     r12d
    cmp     r12d, MAX_COLUMNS
    jb      .free
    call    h_index_empty
    cmp     eax, 1
    jne     .bad
    jmp     .done
.bad:
    mov     ebx, 1
.done:
    call    world_clear                 ; the arena the other tests start from
    mov     eax, ebx
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; region_encode_column puts a column in blob_buf without a file, decode_blob reads it back: a generated column
; (3, 2) with three placed blocks and a chest holding 3 diamonds is encoded and installed as column (40, -9)
; (the blob holds no coordinates): the same blocks are there, and the chest, with its item, at the shifted cell.
; -> eax 0 = pass
test_region_encode_roundtrip:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    xor     ebx, ebx                    ; 0 = pass
    mov     eax, [gen_seed]
    mov     [seed_keep], eax
    call    world_clear
    mov     edi, 42
    call    worldgen_set_seed
    mov     dword [gb + GENBUF.cx], 3
    mov     dword [gb + GENBUF.cz], 2
    lea     rdi, [gb]
    call    gen_column
    mov     edi, 3                      ; the arena's empty column makes room for the generated one
    mov     esi, 2
    call    world_column
    test    rax, rax
    jz      .bad
    mov     rdi, rax
    call    world_column_release
    mov     edi, 3
    mov     esi, 2
    call    world_column_claim
    test    rax, rax
    jz      .bad
    mov     r12, rax
    lea     rdi, [gb]
    call    world_install
    test    eax, eax
    jnz     .bad
    mov     rdi, r12
    call    light_column                ; lit, so that world_set takes the edits
    SET     50, 90, 40, BRICK
    SET     51, 91, 41, GLASS
    SET     52, 92, 42, STONE
    SET     53, 93, 43, CHEST
    mov     edi, 53
    mov     esi, 93
    mov     edx, 43
    mov     ecx, CONT_CHEST
    call    cont_create
    test    rax, rax
    jz      .bad
    mov     byte [rax + CONTAINER.slots], DIAMOND
    mov     byte [rax + CONTAINER.slots + 1], 3
    mov     rdi, r12
    call    region_encode_column
    cmp     eax, 8
    jbe     .bad
    mov     r13d, eax                   ; the blob's length
    cmp     word [blob_buf + 6], 1
    jb      .bad                        ; at least the chest is in it
    lea     rdi, [blob_buf]
    mov     esi, r13d
    lea     rdx, [gb2]
    mov     ecx, 40
    mov     r8d, -9
    call    decode_blob
    cmp     eax, 1
    jne     .bad
    mov     edi, 40
    mov     esi, -9
    call    world_column_claim
    test    rax, rax
    jz      .bad
    mov     r14, rax
    lea     rdi, [gb2]
    call    world_install
    test    eax, eax
    jnz     .bad
    xor     r12d, r12d                  ; cy: every chunk of the column is the same as at its new place
.cy:
    mov     edi, 3
    mov     esi, r12d
    mov     edx, 2
    call    world_chunk
    mov     r13, rax
    mov     edi, 40
    mov     esi, r12d
    mov     edx, -9
    call    world_chunk
    lea     rsi, [zeros]                ; a null chunk is all AIR
    test    r13, r13
    cmovnz  rsi, r13
    lea     rdi, [zeros]
    test    rax, rax
    cmovnz  rdi, rax
    mov     ecx, 4096 / 8
    repe    cmpsq
    jne     .bad
    inc     r12d
    cmp     r12d, COL_CHUNKS
    jb      .cy
    mov     rdi, r14
    call    light_column
    GET     642, 90, -136               ; the placed blocks, 592 cells east and 176 north of where they were put
    EXPECT  BRICK
    GET     643, 91, -135
    EXPECT  GLASS
    GET     644, 92, -134
    EXPECT  STONE
    GET     645, 93, -133
    EXPECT  CHEST
    mov     edi, 645                    ; the chest's container: its item and its kind
    mov     esi, 93
    mov     edx, -133
    call    cont_at
    test    rax, rax
    jz      .bad
    cmp     byte [rax + CONTAINER.kind], CONT_CHEST
    jne     .bad
    cmp     byte [rax + CONTAINER.slots], DIAMOND
    jne     .bad
    cmp     byte [rax + CONTAINER.slots + 1], 3
    jne     .bad
    mov     edi, 53                     ; the original is untouched
    mov     esi, 93
    mov     edx, 43
    call    cont_at
    test    rax, rax
    jz      .bad
    cmp     byte [rax + CONTAINER.slots], DIAMOND
    jne     .bad
    jmp     .done
.fail:
.bad:
    mov     ebx, 1
.done:
    call    world_clear
    mov     edi, [seed_keep]
    call    worldgen_set_seed
    mov     eax, ebx
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
