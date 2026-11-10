; test_icons.asm - the 32x32 item icons (icons.asm): icon_paint clears the cell of its icon and draws the
; bitmap there, and touches nothing else (test_icons_paint); and the shipped art, the icon registry
; item_icons32 of artreg.asm: a clean, painted and distinct bitmap for every item (test_icons_art).
%include "common.inc"
%include "art.inc"
default rel

global test_icons_paint, test_icons_art

extern icon_paint, icons_build, art_pal_find, item_icons32

%define TI_REGION_ROWS (SKIN_Y0 - ICON32_Y0)    ; the icon cells of the atlas: 512 rows, 128 cells
%define TI_A           RGBO(200, 40, 40)
%define TI_B           RGBO(30, 90, 220)
%define TI_FILL        0xAAAAAAAA               ; what the whole icon region holds before the paint

; SPOT x, y, colour: a texel of a cell checked by value, independently of the fixture rows
%macro SPOT 3
    dw %1, %2
    dd %3
%endmacro

section .rodata
align 4
; the fixture palette has two entries; '?' is not in it and '.' is skipped
ti_pal:
    PALC 'a', TI_A
    PALC 'b', TI_B
    dq 0
; top-right quadrant 'a', bottom-left quadrant 'b' (a transposed or mirrored paint swaps them), 'b' and 'a'
; in opposite corners, '?' texels inside painted areas and on the last row and column
SKROWS ti_rows, 32, 32
    SKROW "b?..............aaaaaaaaaaaaaaaa"
    SKROW "................aaaaaaaaaaaaaaaa"
    SKROW "................aaaaaaaaaaaaaaaa"
    SKROW "................aaaaaaaaaaaaaaaa"
    SKROW "................aaaa?aaaaaaaaaaa"
    SKROW "................aaaaaaaaaaaaaaaa"
    SKROW "................aaaaaaaaaaaaaaaa"
    SKROW "................aaaaaaaaaaaaaaaa"
    SKROW "................aaaaaaaaaaaaaaaa"
    SKROW "................aaaaaaaaaaaaaaaa"
    SKROW "................aaaaaaaaaaaaaaaa"
    SKROW "................aaaaaaaaaaaaaaaa"
    SKROW "................aaaaaaaaaaaaaaaa"
    SKROW "................aaaaaaaaaaaaaaaa"
    SKROW "................aaaaaaaaaaaaaaaa"
    SKROW "................aaaaaaaaaaaaaaaa"
    SKROW "bbbbbbbbbbbbbbbb................"
    SKROW "bbbbbbbbbbbbbbbb................"
    SKROW "bbbbbbbbbbbbbbbb................"
    SKROW "bbbbbbbbbbbbbbbb................"
    SKROW "bbb?bbbbbbbbbbbb................"
    SKROW "bbbbbbbbbbbbbbbb................"
    SKROW "bbbbbbbbbbbbbbbb................"
    SKROW "bbbbbbbbbbbbbbbb................"
    SKROW "bbbbbbbbbbbbbbbb................"
    SKROW "bbbbbbbbbbbbbbbb................"
    SKROW "bbbbbbbbbbbbbbbb................"
    SKROW "bbbbbbbbbbbbbbbb................"
    SKROW "bbbbbbbbbbbbbbbb................"
    SKROW "bbbbbbbbbbbbbbbb................"
    SKROW "bbbbbbbbbbbbbbbb...............?"
    SKROW "bbbbbbbbbbbbbbbb..............?a"
SKROWS_END
align 8
SKBMP ti_bmp, ti_rows, 32, 32, ti_pal

; the cell's corners, the quadrant edges and the missing-char texels, by value (0 = cleared)
ti_spots:
    SPOT 0, 0, TI_B
    SPOT 1, 0, 0                                ; '?'
    SPOT 16, 0, TI_A
    SPOT 31, 0, TI_A
    SPOT 15, 15, 0                              ; '.'
    SPOT 16, 15, TI_A
    SPOT 0, 16, TI_B
    SPOT 15, 31, TI_B
    SPOT 16, 31, 0
    SPOT 30, 31, 0                              ; '?'
    SPOT 31, 31, TI_A
    SPOT 31, 30, 0                              ; '?'
    SPOT 20, 4, 0                               ; '?' inside the 'a' quadrant
    SPOT 3, 20, 0                               ; '?' inside the 'b' quadrant
ti_spots_end:

; the icons painted: k, then the cell's atlas x and y (ICON32_Y0 + (k >> 3) * 32), written out by hand
align 4
ti_cells:
    dd 9, 32, 544                               ; icon 8, the cell at x 0, lies beside it
    dd 90, 64, 864                              ; column 2, row 11: a swapped column / row index lands elsewhere
ti_cells_end:

section .bss
align 16
ti_atlas: resb ATLAS_W * ATLAS_H * 4

section .text

; test_icons_paint() -> eax 0 pass / 1 a texel of a painted cell differs from its bitmap char /
;   2 a spot texel differs / 3 a texel outside the painted cells changed
;   The icon region (atlas rows 512..1023) is filled with 0xAA bytes, then icon_paint(atlas, k, bitmap) runs
;   for icons 9 (x 32, y 544..575) and 90. Every texel of each cell must equal the palette colour of its
;   bitmap char, 0 for '.' and for the char missing from the palette (the cell was cleared first), and every
;   texel of the region outside the two cells, icon 8's cell beside the first included, must still hold 0xAA.
test_icons_paint:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    lea     rbx, [ti_atlas]
    lea     rdi, [rbx + ICON32_Y0 * ATLAS_W * 4]
    mov     ecx, TI_REGION_ROWS * ATLAS_W * 4 / 8
    mov     rax, 0xAAAAAAAAAAAAAAAA
    rep stosq
    lea     r15, [ti_cells]
.paint:
    mov     rdi, rbx
    mov     esi, [r15]
    lea     rdx, [ti_bmp]
    call    icon_paint
    add     r15, 12
    lea     rax, [ti_cells_end]
    cmp     r15, rax
    jb      .paint

    ; every texel of each cell against its fixture char
    lea     r15, [ti_cells]
.cell:
    xor     r12d, r12d                  ; py
.py:
    xor     r13d, r13d                  ; px
.px:
    mov     eax, r12d
    shl     eax, 5
    add     eax, r13d
    lea     rcx, [ti_rows]
    movzx   ecx, byte [rcx + rax]       ; the fixture char
    xor     edx, edx                    ; expected colour: 0 unless the char is in the palette
    cmp     ecx, 'a'
    jne     .not_a
    mov     edx, TI_A
.not_a:
    cmp     ecx, 'b'
    jne     .not_b
    mov     edx, TI_B
.not_b:
    mov     eax, [r15 + 8]
    add     eax, r12d
    imul    eax, eax, ATLAS_W
    add     eax, [r15 + 4]
    add     eax, r13d
    cmp     [rbx + rax*4], edx
    jne     .fail1
    inc     r13d
    cmp     r13d, ICON32_PX
    jb      .px
    inc     r12d
    cmp     r12d, ICON32_PX
    jb      .py

    ; the spot texels of the cell by value
    lea     r14, [ti_spots]
.spot:
    movzx   eax, word [r14 + 2]
    add     eax, [r15 + 8]
    imul    eax, eax, ATLAS_W
    movzx   ecx, word [r14]
    add     eax, ecx
    add     eax, [r15 + 4]
    mov     ecx, [r14 + 4]
    cmp     [rbx + rax*4], ecx
    jne     .fail2
    add     r14, 8
    lea     rax, [ti_spots_end]
    cmp     r14, rax
    jb      .spot
    add     r15, 12
    lea     rax, [ti_cells_end]
    cmp     r15, rax
    jb      .cell

    ; nothing else in the icon region moved: for every texel, its cell index (y / 32) * 8 + x / 32 must be
    ; a painted icon, or the texel still holds 0xAA
    xor     r12d, r12d                  ; y, relative to the region
.gy:
    xor     r13d, r13d                  ; x
.gx:
    mov     eax, r12d
    shr     eax, 5
    lea     eax, [rax*8]
    mov     ecx, r13d
    shr     ecx, 5
    add     eax, ecx                    ; the cell the texel belongs to
    lea     r15, [ti_cells]
.is_painted:
    cmp     eax, [r15]
    je      .gnext                      ; inside a painted cell: checked above
    add     r15, 12
    lea     rcx, [ti_cells_end]
    cmp     r15, rcx
    jb      .is_painted
    mov     eax, r12d
    imul    eax, eax, ATLAS_W
    add     eax, r13d
    cmp     dword [rbx + ICON32_Y0 * ATLAS_W * 4 + rax*4], TI_FILL
    jne     .fail3
.gnext:
    inc     r13d
    cmp     r13d, ATLAS_W
    jb      .gx
    inc     r12d
    cmp     r12d, TI_REGION_ROWS
    jb      .gy
    xor     eax, eax
    jmp     .out
.fail1:
    mov     eax, 1
    jmp     .out
.fail2:
    mov     eax, 2
    jmp     .out
.fail3:
    mov     eax, 3
.out:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ti_cell(edi k) -> rax the address of the first texel of icon k's cell in ti_atlas. Leaf.
ti_cell:
    mov     eax, edi
    shr     eax, 3
    imul    eax, eax, ICON32_PX
    add     eax, ICON32_Y0              ; the cell's atlas row
    imul    eax, eax, ATLAS_W
    and     edi, 7
    imul    edi, edi, ICON32_PX         ; its atlas column
    add     eax, edi
    lea     rdx, [ti_atlas]
    lea     rax, [rdx + rax * 4]
    ret

; ti_cells_equal(rdi cell a, rsi cell b) -> eax 1 when the two 32x32 cells of the atlas hold the same texels.
; Leaf; clobbers rcx, rdx, rsi, rdi, r8, r9.
ti_cells_equal:
    mov     edx, ICON32_PX              ; rows left
.row:
    mov     r8, rdi
    mov     r9, rsi
    mov     ecx, ICON32_PX
    repe cmpsd
    jne     .differ
    lea     rdi, [r8 + ATLAS_W * 4]
    lea     rsi, [r9 + ATLAS_W * 4]
    dec     edx
    jnz     .row
    mov     eax, 1
    ret
.differ:
    xor     eax, eax
    ret

; test_icons_art() -> eax 0 pass / 1 an item_icons32 entry is null, has no rows or palette, or is not 32 x 32 /
;   2 a bitmap char is neither '.' nor in its palette / 3 an icon cell has fewer than 64 opaque texels (alpha > 127)
;   after icons_build / 4 two icon cells are byte-identical
;   Every one of the ICON32_COUNT entries of the registry (checks 1 and 2 on the bitmaps), then icons_build on the
;   test atlas and checks 3 and 4 on the painted cells (the pairs: every cell against every later one).
test_icons_art:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    xor     ebx, ebx                    ; k
.entry:
    lea     rax, [item_icons32]
    mov     r12, [rax + rbx * 8]        ; the bitmap
    test    r12, r12
    jz      .fail1
    cmp     qword [r12 + SKBMP.rows], 0
    je      .fail1
    cmp     qword [r12 + SKBMP.pal], 0
    je      .fail1
    cmp     byte [r12 + SKBMP.w], ICON32_PX
    jne     .fail1
    cmp     byte [r12 + SKBMP.h], ICON32_PX
    jne     .fail1
    mov     r13, [r12 + SKBMP.rows]
    xor     r14d, r14d                  ; char index
.char:
    movzx   edi, byte [r13 + r14]
    cmp     edi, '.'
    je      .char_next
    mov     rsi, [r12 + SKBMP.pal]
    call    art_pal_find                ; edx = 1 when the palette has the char
    test    edx, edx
    jz      .fail2
.char_next:
    inc     r14d
    cmp     r14d, ICON32_PX * ICON32_PX
    jb      .char
    inc     ebx
    cmp     ebx, ICON32_COUNT
    jb      .entry
    lea     rdi, [ti_atlas]
    lea     rsi, [item_icons32]
    call    icons_build
    xor     ebx, ebx
.cell:
    mov     edi, ebx
    call    ti_cell
    mov     r12, rax                    ; the cell's row 0
    xor     r14d, r14d                  ; opaque texels
    mov     r15d, ICON32_PX             ; rows left
.opaque_row:
    xor     ecx, ecx
.opaque_texel:
    cmp     byte [r12 + rcx * 4 + 3], 127
    seta    al
    movzx   eax, al
    add     r14d, eax
    inc     ecx
    cmp     ecx, ICON32_PX
    jb      .opaque_texel
    add     r12, ATLAS_W * 4
    dec     r15d
    jnz     .opaque_row
    cmp     r14d, 64
    jb      .fail3
    inc     ebx
    cmp     ebx, ICON32_COUNT
    jb      .cell
    xor     ebx, ebx                    ; i
.pair_i:
    lea     r13d, [rbx + 1]             ; j
.pair_j:
    cmp     r13d, ICON32_COUNT
    jae     .pair_next
    mov     edi, ebx
    call    ti_cell
    mov     r12, rax
    mov     edi, r13d
    call    ti_cell
    mov     rdi, r12
    mov     rsi, rax
    call    ti_cells_equal
    test    eax, eax
    jnz     .fail4
    inc     r13d
    jmp     .pair_j
.pair_next:
    inc     ebx
    cmp     ebx, ICON32_COUNT - 1
    jb      .pair_i
    xor     eax, eax
    jmp     .out
.fail1:
    mov     eax, 1
    jmp     .out
.fail2:
    mov     eax, 2
    jmp     .out
.fail3:
    mov     eax, 3
    jmp     .out
.fail4:
    mov     eax, 4
.out:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
