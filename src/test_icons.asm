; test_icons.asm - the 32x32 item icons (icons.asm): icon_paint clears the cell of its icon and draws the
; bitmap there, and touches nothing else.
%include "common.inc"
%include "art.inc"
default rel

global test_icons_paint

extern icon_paint

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
