; test_world.asm - world storage tests: columns, chunks, the origin, region files.
%include "common.inc"
default rel

global test_world_bounds, test_world_set_marks_dirty, test_world_save_load
global test_world_rebase, test_region_roundtrip

extern world_header, world_clear, world_get, world_set, world_is_solid, world_is_opaque
extern world_top_y, world_column, world_column_claim, world_install, world_origin_x, world_origin_z
extern world_rebase, world_save_dirty, world_install_err, light_column, conts
extern region_set_dir, region_read_column
extern dir_remove_tree, file_stat_mtime, file_pread, file_patch

section .rodata
dir_wsl:        db "/tmp/ac9t-wsl", 0
dir_region:     db "/tmp/ac9t-region", 0
file_r00:       db "/tmp/ac9t-region/regions/r.0.0.bin", 0
file_rm10:      db "/tmp/ac9t-region/regions/r.-1.0.bin", 0
flip_byte:      db "X"

section .bss
alignb 16
gb:             resb GENBUF_size
entry:          resd 2

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
    mov     dword [rax + COLUMN.state], COL_FREE
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
    mov     dword [rax + COLUMN.state], COL_FREE
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
%if MOB_size != 260 || INVENTORY_size != 216 || SITE_size != 56 || COLUMN_size != 408
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
