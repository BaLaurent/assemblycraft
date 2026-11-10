; art.asm: the shared pixel blitter of the 0.13 "looks" art. skin_build (SK_BMP decals) and icons_build
; (32x32 item icons) both draw their SKBMP bitmaps through art_blit, so there is one palette rule:
; '.' and any char missing from the palette are skipped (the destination texel is left as it is), any
; other char writes its palette entry's dword (alpha included; PALT writes a transparent texel).
%include "common.inc"
default rel

global art_pal_find
global art_blit

section .text

; art_pal_find(edi char, rsi palette) -> eax colour, edx 1 found / 0 missing
; Walks the 8-byte records (db char, 3 pad ; dd colour) until a zero qword. Leaf; clobbers rsi.
art_pal_find:
.next:
    mov     rax, [rsi]
    test    rax, rax
    jz      .miss
    cmp     al, dil
    je      .hit
    add     rsi, 8
    jmp     .next
.hit:
    mov     eax, [rsi + 4]
    mov     edx, 1
    ret
.miss:
    xor     eax, eax
    xor     edx, edx
    ret

; art_blit(rdi first destination texel, esi destination stride in texels, rdx SKBMP*,
;          ecx clip_w, r8d clip_h)
; Writes min(w, clip_w) x min(h, clip_h) texels of the bitmap, row-major, to the RGBA destination.
; Clobbers the caller-saved registers only.
art_blit:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8                      ; [rsp] = clipped width, [rsp + 4] = source width
    movzx   eax, byte [rdx + SKBMP.w]
    mov     [rsp + 4], eax
    cmp     ecx, eax
    cmovb   eax, ecx
    mov     [rsp], eax
    movzx   ebp, byte [rdx + SKBMP.h]
    cmp     r8d, ebp
    cmovb   ebp, r8d                    ; ebp = rows left
    mov     rbx, rdi                    ; destination row
    mov     eax, esi
    lea     r12, [rax * 4]              ; destination stride, bytes
    mov     r13, [rdx + SKBMP.rows]     ; source row
    mov     r14, [rdx + SKBMP.pal]
    cmp     dword [rsp], 0
    je      .done
    test    ebp, ebp
    jz      .done
.row:
    xor     r15d, r15d
.col:
    movzx   edi, byte [r13 + r15]
    cmp     edi, '.'
    je      .skip
    mov     rsi, r14
    call    art_pal_find
    test    edx, edx
    jz      .skip
    mov     [rbx + r15 * 4], eax
.skip:
    inc     r15d
    cmp     r15d, [rsp]
    jb      .col
    mov     eax, [rsp + 4]
    add     r13, rax
    add     rbx, r12
    dec     ebp
    jnz     .row
.done:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret
