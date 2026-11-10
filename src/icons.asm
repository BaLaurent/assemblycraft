; icons.asm - the 32x32 item icons of the 0.13 "looks" art. Icon k (item id FIRST_ITEM + k) owns the 32x32
; texel cell at x (k & 7) * 32, y ICON32_Y0 + (k >> 3) * 32 of the atlas (common.inc). An icon is a 32x32
; SKBMP bitmap (art.inc) drawn by the shared blitter art_blit (art.asm), so the palette rule is the skins':
; '.' and a char missing from the palette are skipped and, the cell being cleared first, stay transparent.
%include "common.inc"
default rel

global icon_paint, icons_build

extern art_blit

%if ATLAS_W != 8 * ICON32_PX
%error "icon cells: k & 7 and k >> 3 assume 8 icons per atlas row"
%endif
%if ICON32_COUNT > (SKIN_Y0 - ICON32_Y0) / ICON32_PX * (ATLAS_W / ICON32_PX)
%error "icons_build: the icon rows of the atlas hold fewer cells than there are item icons"
%endif

section .text

; icon_paint(rdi atlas, esi k, rdx SKBMP* bitmap)
; Clears the 32x32 cell of icon k to 0 (transparent), then draws the bitmap into it through art_blit,
; clipped to 32x32. The atlas is ATLAS_W x ATLAS_H RGBA texels.
icon_paint:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     r12, rdx                    ; the bitmap
    mov     eax, esi
    shr     eax, 3                      ; the cell's row of icons
    imul    eax, eax, ICON32_PX
    add     eax, ICON32_Y0              ; atlas row of the cell
    imul    eax, eax, ATLAS_W
    and     esi, 7
    imul    esi, esi, ICON32_PX         ; atlas column of the cell
    add     eax, esi
    lea     rbx, [rdi + rax*4]          ; the cell's first texel
    mov     rdi, rbx
    mov     edx, ICON32_PX              ; rows left to clear
.clear:
    mov     ecx, ICON32_PX
    xor     eax, eax
    rep stosd                           ; one row of the cell; rdi ends just past it
    lea     rdi, [rdi + (ATLAS_W - ICON32_PX) * 4]
    dec     edx
    jnz     .clear
    mov     rdi, rbx
    mov     esi, ATLAS_W
    mov     rdx, r12
    mov     ecx, ICON32_PX
    mov     r8d, ICON32_PX
    call    art_blit
    pop     r12
    pop     rbx
    pop     rbp
    ret

; icons_build(rdi atlas, rsi table)
; Paints every item icon: icon_paint(atlas, k, table[k]) for k = 0..ICON32_COUNT-1, the table being
; ICON32_COUNT SKBMP* qwords in item id order from STICK.
icons_build:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rdi                    ; atlas
    mov     r12, rsi                    ; table
    xor     r13d, r13d                  ; k
.icon:
    mov     rdi, rbx
    mov     esi, r13d
    mov     rdx, [r12 + r13*8]
    call    icon_paint
    inc     r13d
    cmp     r13d, ICON32_COUNT
    jb      .icon
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
