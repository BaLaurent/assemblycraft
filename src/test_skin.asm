; test_skin.asm - the 0.13 skin engine (skin.asm): the unwrap and its texcoords (test_skin_uv); the packer,
; the paint ops, the overflow guard and the skin_verify / skin_check proofs (test_skin_pack).
%include "common.inc"
%include "art.inc"
default rel

global test_skin_uv, test_skin_pack

extern skin_face_rect, skin_face_uvs, skin_build, skin_check, skin_verify

section .rodata
align 4
; fixture parts for the unwrap: A is w 4, h 6, d 2 at (10, 1100); B is w 3, h 5, d 7 at (100, 2000)
uv_part_a:
    db SKR_PART, 0, 0, SKAS_NONE
    dw 0, 0, 0
    db 4, 6, 2, 0
    dw 10, 1100, 0
uv_part_b:
    db SKR_PART, 0, 0, SKAS_NONE
    dw 0, 0, 0
    db 3, 5, 7, 0
    dw 100, 2000, 0
; rows: part (0 A, 1 B), face (SKF_*), the face rectangle u, v, width, height, then the four corner
; texcoords (u, v) in face_corners order. Worked out from the unwrap and corner tables of the plan
; (a separate Python implementation of them, not the engine's tables); A FRONT and A TOP are the plan's numbers.
UV_ROWS equ 12
uv_rows:
    dd 0, 0, 10, 1102, 2, 6, 161, 17727, 191, 17727, 191, 17633, 161, 17633     ; A RIGHT
    dd 0, 1, 16, 1102, 2, 6, 257, 17727, 287, 17727, 287, 17633, 257, 17633     ; A LEFT
    dd 0, 2, 12, 1100, 4, 2, 255, 17601, 193, 17601, 193, 17631, 255, 17631     ; A TOP
    dd 0, 3, 16, 1100, 4, 2, 257, 17631, 319, 17631, 319, 17601, 257, 17601     ; A BOTTOM
    dd 0, 4, 18, 1102, 4, 6, 289, 17727, 351, 17727, 351, 17633, 289, 17633     ; A BACK
    dd 0, 5, 12, 1102, 4, 6, 193, 17727, 255, 17727, 255, 17633, 193, 17633     ; A FRONT
    dd 1, 0, 100, 2007, 7, 5, 1601, 32191, 1711, 32191, 1711, 32113, 1601, 32113 ; B RIGHT
    dd 1, 1, 110, 2007, 7, 5, 1761, 32191, 1871, 32191, 1871, 32113, 1761, 32113 ; B LEFT
    dd 1, 2, 107, 2000, 3, 7, 1759, 32001, 1713, 32001, 1713, 32111, 1759, 32111 ; B TOP
    dd 1, 3, 110, 2000, 3, 7, 1761, 32111, 1807, 32111, 1807, 32001, 1761, 32001 ; B BOTTOM
    dd 1, 4, 117, 2007, 3, 5, 1873, 32191, 1919, 32191, 1919, 32113, 1873, 32113 ; B BACK
    dd 1, 5, 107, 2007, 3, 5, 1713, 32191, 1759, 32191, 1759, 32113, 1713, 32113 ; B FRONT

; the SK_BMP fixture: 'A' red, 'B' green, '.' and 'C' (not in the palette) leave the texel as it is
tsk_pal:
    PAL 'A', 255, 0, 0
    PAL 'B', 0, 255, 0
    dq 0
    SKROWS tsk_rows, 2, 3
    SKROW "AB"
    SKROW ".A"
    SKROW "BC"
    SKROWS_END
    SKBMP tsk_bmp, tsk_rows, 2, 3, tsk_pal

section .data
align 8
; model A: a 4 x 6 x 2 part (footprint 12 x 8), a part sharing its skin, an 8 x 4 x 4 part (24 x 8)
SKMODEL_BEGIN tsk_model_a, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.0
    SKPART 0, 0, 0, 4, 6, 2, 0, 0
    SKPART_AS 0, 10, 0, 0, 0, 0
    SKPART 0, 10, 0, 8, 4, 4, 0, 0
SKMODEL_PAINT
    SK_FILL 0, SKM_ALL, RGBO(200, 200, 200), 0
    SK_GRAD 0, SKM_FRONT, 256, 128
    SK_RECT 0, SKF_TOP, 1, 0, 2, 1, RGBO(10, 20, 30), 0
    SK_BMP 0, SKF_RIGHT, 0, 1, tsk_bmp
    SK_RECT 1, SKF_BACK, 3, 5, 1, 1, RGBO(9, 8, 7), 0
    SK_RECT 0, SKF_TOP, 3, 1, 5, 5, RGBO(70, 80, 90), 0   ; hangs over the face: clipped to its last texel
    SK_RECT 0, SKF_TOP, 5, 0, 2, 2, RGBO(70, 80, 90), 0   ; starts right of the face: nothing
    SK_RECT 0, SKF_TOP, 0, 3, 2, 2, RGBO(70, 80, 90), 0   ; starts below the face: nothing
    SK_BMP 0, SKF_RIGHT, 1, 4, tsk_bmp                    ; hangs over the face: its first column, two rows
    SK_BMP 0, SKF_TOP, 5, 0, tsk_bmp                      ; starts right of the face: nothing
    SK_BMP 0, SKF_TOP, 0, 3, tsk_bmp                      ; starts below the face: nothing
    SK_FILL 2, SKM_ALL, RGBO(200, 150, 100), 31
SKMODEL_END
; model B: a 120 x 8 x 8 part (footprint 256 x 16, wider than what is left of the shelf), then a cutout part
; (12 x 4) that does not fit on that shelf either, a 4 x 7 x 1 part for the gradient edge cases and a tiny one
; on the same shelf (so the tallest footprint is not the last), and a wide part that wraps to the next shelf
SKMODEL_BEGIN tsk_model_b, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.0
    SKPART 0, 0, 0, 120, 8, 8, 0, 0
    SKPART 0, 8, 0, 4, 2, 2, 0, SKPF_CUTOUT
    SKPART 0, 16, 0, 4, 7, 1, 0, 0
    SKPART 0, 24, 0, 4, 1, 1, 0, 0
    SKPART 0, 0, 16, 120, 2, 8, 0, 0
SKMODEL_PAINT
    SK_FILL 0, SKM_ALL, RGBO(1, 2, 3), 0
    SK_FILL 1, SKM_SIDES, RGBO(4, 5, 6), 0
    SK_FILL 1, SKM_TOP | SKM_BOTTOM, RGBO(14, 15, 16), 0
    SK_FILL 2, SKM_ALL, RGBO(250, 250, 250), 0
    SK_GRAD 2, SKM_FRONT, 272, 224                        ; brighter at the top: the channels clamp at 255
    SK_GRAD 2, SKM_TOP, 128, 64                           ; a one row face takes the top multiplier
    SK_GRAD 2, SKM_LEFT | SKM_RIGHT, 256, 128             ; two faces in one mask
    SK_FILL 3, SKM_ALL, RGBO(8, 9, 10), 0
    SK_FILL 4, SKM_ALL, RGBO(11, 12, 13), 0
SKMODEL_END
; model C: 30 own-skin parts of 120 x 100 x 8 (footprint 256 x 108): 28 fit in the 3072 skin rows
SKMODEL_BEGIN tsk_model_c, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.0
%rep 30
    SKPART 0, 0, 0, 120, 100, 8, 0, 0
%endrep
SKMODEL_PAINT
%assign tsk_i 0
%rep 30
    SK_FILL tsk_i, SKM_ALL, RGBO(7, 7, 7), 0
%assign tsk_i tsk_i + 1
%endrep
SKMODEL_END
; model D: one part 100 x 4 x 100, a 400 texel wide footprint
SKMODEL_BEGIN tsk_model_d, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.0
    SKPART 0, 0, 0, 100, 4, 100, 0, 0
SKMODEL_PAINT
    SK_FILL 0, SKM_ALL, RGBO(7, 7, 7), 0
SKMODEL_END
; model E: 254 parts of 1 x 1 x 1 (the most a model holds), listed 17 times in tsk_reg_e: 4318 own-skin footprints
SKMODEL_BEGIN tsk_model_e, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.0
%rep 254
    SKPART 0, 0, 0, 1, 1, 1, 0, 0
%endrep
SKMODEL_PAINT
%assign tsk_i 0
%rep 254
    SK_FILL tsk_i, SKM_ALL, RGBO(7, 7, 7), 0
%assign tsk_i tsk_i + 1
%endrep
SKMODEL_END
align 8
tsk_reg_ab: dq tsk_model_a, tsk_model_b, 0
tsk_reg_c:  dq tsk_model_c, 0
tsk_reg_d:  dq tsk_model_d, 0
tsk_reg_e:  times 17 dq tsk_model_e
            dq 0

; the part records of the fixtures (a bone record comes first in each model)
%define TA0 (tsk_model_a_recs + 1 * SKREC_SIZE)
%define TA1 (tsk_model_a_recs + 2 * SKREC_SIZE)
%define TA2 (tsk_model_a_recs + 3 * SKREC_SIZE)
%define TB0 (tsk_model_b_recs + 1 * SKREC_SIZE)
%define TB1 (tsk_model_b_recs + 2 * SKREC_SIZE)
%define TB2 (tsk_model_b_recs + 3 * SKREC_SIZE)
%define TB3 (tsk_model_b_recs + 4 * SKREC_SIZE)
%define TB4 (tsk_model_b_recs + 5 * SKREC_SIZE)

section .bss
align 16
tsk_atlas:  resb ATLAS_W * ATLAS_H * 4
tsk_canary: resb 64                     ; right behind the atlas
tsk_guard:  resb 262144                 ; so that a broken packer's overrun hurts nothing else

section .text

; fail unless the dword/word/byte operand %1 equals %2
%macro EXPECT 2
    cmp     %1, %2
    jne     .fail
%endmacro

; tsk_texel(edi atlas x, esi atlas y) -> eax the texel (RGBA dword) of the test atlas. Leaf.
tsk_texel:
    imul    esi, esi, ATLAS_W
    add     esi, edi
    lea     rax, [tsk_atlas]
    mov     eax, [rax + rsi*4]
    ret

; tsk_face_addr(rdi part record, esi face, edx x, ecx y) -> rax address of the face-local texel (x, y) in
; the test atlas. Keeps rbx and r12.
tsk_face_addr:
    push    rbx
    push    r12
    mov     ebx, edx
    mov     r12d, ecx
    call    skin_face_rect                      ; eax u, edx v
    add     eax, ebx
    add     edx, r12d
    imul    edx, edx, ATLAS_W
    add     edx, eax
    lea     rax, [tsk_atlas]
    lea     rax, [rax + rdx*4]
    pop     r12
    pop     rbx
    ret

; TEXEL part, face, x, y, rgba: fail unless the face-local texel has that colour
%macro TEXEL 5
    lea     rdi, [%1]
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    call    tsk_face_addr
    mov     r13d, [rax]
    cmp     r13d, %5
    jne     .fail
%endmacro

; GREY part, face, x, y: fail unless the face-local texel is a grey (r = g = b)
%macro GREY 4
    lea     rdi, [%1]
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    call    tsk_face_addr
    mov     eax, [rax]
    call    tsk_grey
    test    eax, eax
    jnz     .fail
%endmacro

; tsk_grey(eax rgba) -> eax 0 when r = g = b, else 1. Leaf.
tsk_grey:
    movzx   ecx, al
    movzx   edx, ah
    cmp     ecx, edx
    jne     .no
    shr     eax, 16
    movzx   eax, al
    cmp     eax, ecx
    jne     .no
    xor     eax, eax
    ret
.no:
    mov     eax, 1
    ret

; the 64 byte canary behind the atlas is still 0xAA -> eax 0
tsk_canary_ok:
    lea     rdx, [tsk_canary]
    xor     ecx, ecx
.byte:
    cmp     byte [rdx + rcx], 0xAA
    jne     .bad
    inc     ecx
    cmp     ecx, 64
    jb      .byte
    xor     eax, eax
    ret
.bad:
    mov     eax, 1
    ret

; test_skin_uv() -> eax 0 pass
;   skin_face_rect gives each face's image rectangle and skin_face_uvs the four corner texcoords in
;   face_corners order (one unit inside the rectangle), for two parts with distinct w, h, d: the plan's
;   part (4, 6, 2) at (10, 1100) and a second one (3, 5, 7) at (100, 2000). Part A FRONT and TOP are the
;   numbers worked out in the plan, the rest follow the same tables.
test_skin_uv:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 40                             ; [rsp] the 8 texcoords
    lea     rbx, [uv_rows]
    mov     r12d, UV_ROWS
.row:
    lea     r13, [uv_part_a]
    cmp     dword [rbx], 0
    je      .part
    lea     r13, [uv_part_b]
.part:
    mov     rdi, r13
    mov     esi, [rbx + 4]
    call    skin_face_rect
    cmp     eax, [rbx + 8]
    jne     .fail
    cmp     edx, [rbx + 12]
    jne     .fail
    cmp     ecx, [rbx + 16]
    jne     .fail
    cmp     r8d, [rbx + 20]
    jne     .fail
    mov     rdi, r13
    mov     esi, [rbx + 4]
    mov     rdx, rsp
    call    skin_face_uvs
    xor     ecx, ecx
.uv:
    mov     eax, [rsp + rcx*4]
    cmp     eax, [rbx + 24 + rcx*4]
    jne     .fail
    inc     ecx
    cmp     ecx, 8
    jb      .uv
    add     rbx, 56
    dec     r12d
    jnz     .row
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    add     rsp, 40
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; test_skin_pack() -> eax 0 pass
;   skin_build packs and paints two fixture models into a zero atlas: the own-skin footprints sit where the
;   shelf rule puts them (shelf height = the tallest footprint, reset when a shelf is left), the SKPART_AS part
;   copies size and place, and every paint op lands as specified: FILL (face masks; with noise: hash values
;   worked out apart from the engine, and an unwrap corner no face covers stays bare), RECT and BMP (palette
;   colours; '.' and a char missing from the palette leave the texel; an op that overhangs a face is clipped to
;   it, one that starts outside it paints nothing), GRAD (a 6 row face filled with 200: row 0 stays 200, row 5
;   is 100, the rows between fall; a multiplier above 256 clamps at 255; a one row face takes the top
;   multiplier; unmasked faces stay) and an op on an AS part (it paints the shared rect).
;   skin_verify passes on it, and fails with the right number when a footprint leaves the region (2), an AS
;   part differs in size or place (3), footprints overlap (4) or a texel is bare in a solid part or a whole face
;   of a cutout part is (5; a hole in a cutout part is fine). Two overflow fixtures (30 parts of 256 x 108
;   where 28 fit, a part with a 400 texel wide footprint) make skin_build and skin_check (check 1) return 1,
;   paint nothing and leave the 64 byte canary behind the atlas intact; 17 x 254 own-skin parts make
;   skin_check return 6 (more footprints than skin_verify compares).
test_skin_pack:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    lea     rdi, [tsk_canary]
    mov     ecx, 64
    mov     al, 0xAA
    rep     stosb
    lea     rdi, [tsk_atlas]
    lea     rsi, [tsk_reg_ab]
    call    skin_build
    test    eax, eax
    jnz     .fail
    ; packing: registry order, record order, shelves of the tallest footprint
    EXPECT  word [TA0 + SKR_U], 0
    EXPECT  word [TA0 + SKR_V], 1024
    EXPECT  word [TA2 + SKR_U], 12
    EXPECT  word [TA2 + SKR_V], 1024
    EXPECT  word [TB0 + SKR_U], 0
    EXPECT  word [TB0 + SKR_V], 1032
    EXPECT  word [TB1 + SKR_U], 0
    EXPECT  word [TB1 + SKR_V], 1048
    EXPECT  word [TB2 + SKR_U], 12
    EXPECT  word [TB2 + SKR_V], 1048
    EXPECT  word [TB3 + SKR_U], 22
    EXPECT  word [TB3 + SKR_V], 1048
    EXPECT  word [TB4 + SKR_U], 0               ; the shelf of B1..B3 is 8 high (B2), B3 is the last on it
    EXPECT  word [TB4 + SKR_V], 1056
    ; the AS part: size and place of part 0
    EXPECT  byte [TA1 + SKR_W], 4
    EXPECT  byte [TA1 + SKR_H], 6
    EXPECT  byte [TA1 + SKR_D], 2
    EXPECT  word [TA1 + SKR_U], 0
    EXPECT  word [TA1 + SKR_V], 1024
    lea     rdi, [tsk_atlas]
    lea     rsi, [tsk_reg_ab]
    call    skin_verify
    test    eax, eax
    jnz     .fail
    ; BMP on A0 RIGHT (2 x 6): rows 1..3, nothing above
    TEXEL   TA0, SKF_RIGHT, 0, 0, RGBO(200, 200, 200)
    TEXEL   TA0, SKF_RIGHT, 1, 0, RGBO(200, 200, 200)
    TEXEL   TA0, SKF_RIGHT, 0, 1, RGBO(255, 0, 0)
    TEXEL   TA0, SKF_RIGHT, 1, 1, RGBO(0, 255, 0)
    TEXEL   TA0, SKF_RIGHT, 0, 2, RGBO(200, 200, 200)  ; '.'
    TEXEL   TA0, SKF_RIGHT, 1, 2, RGBO(255, 0, 0)
    TEXEL   TA0, SKF_RIGHT, 0, 3, RGBO(0, 255, 0)
    TEXEL   TA0, SKF_RIGHT, 1, 3, RGBO(200, 200, 200)  ; 'C', not in the palette
    TEXEL   TA0, SKF_RIGHT, 0, 4, RGBO(200, 200, 200)
    ; RECT on A0 TOP (4 x 2)
    TEXEL   TA0, SKF_TOP, 0, 0, RGBO(200, 200, 200)
    TEXEL   TA0, SKF_TOP, 1, 0, RGBO(10, 20, 30)
    TEXEL   TA0, SKF_TOP, 2, 0, RGBO(10, 20, 30)
    TEXEL   TA0, SKF_TOP, 3, 0, RGBO(200, 200, 200)
    TEXEL   TA0, SKF_TOP, 1, 1, RGBO(200, 200, 200)
    ; the op on the AS part A1 painted A0's BACK (4 x 6) at (3, 5)
    TEXEL   TA0, SKF_BACK, 3, 5, RGBO(9, 8, 7)
    TEXEL   TA0, SKF_BACK, 2, 5, RGBO(200, 200, 200)
    TEXEL   TA0, SKF_BACK, 3, 4, RGBO(200, 200, 200)
    ; clipping: the rect and the bitmap that overhang (or start outside) a face leave its neighbours alone
    TEXEL   TA0, SKF_TOP, 3, 1, RGBO(70, 80, 90)
    TEXEL   TA0, SKF_BOTTOM, 0, 0, RGBO(200, 200, 200)
    TEXEL   TA0, SKF_BOTTOM, 0, 1, RGBO(200, 200, 200)
    TEXEL   TA0, SKF_BOTTOM, 1, 0, RGBO(200, 200, 200)   ; what the ops at x = 5 would hit
    TEXEL   TA0, SKF_RIGHT, 1, 4, RGBO(255, 0, 0)
    GREY    TA0, SKF_FRONT, 0, 1                         ; what the ops at y = 3 would hit
    GREY    TA0, SKF_FRONT, 1, 1
    GREY    TA0, SKF_FRONT, 0, 4                         ; the 'B' of the overhanging bitmap
    mov     edi, 1                                       ; nor did its third row fall below the face
    mov     esi, 1032
    call    tsk_texel
    EXPECT  eax, 0
    ; GRAD on A0 FRONT (4 x 6): 200 at the top, 100 at the bottom, falling in between
    TEXEL   TA0, SKF_FRONT, 0, 0, RGBO(200, 200, 200)
    TEXEL   TA0, SKF_FRONT, 3, 0, RGBO(200, 200, 200)
    TEXEL   TA0, SKF_FRONT, 0, 5, RGBO(100, 100, 100)
    TEXEL   TA0, SKF_FRONT, 3, 5, RGBO(100, 100, 100)
    mov     r12d, 200                           ; the red value of the row above
    mov     ebx, 1
.grad_row:
    lea     rdi, [TA0]
    mov     esi, SKF_FRONT
    mov     edx, 1
    mov     ecx, ebx
    call    tsk_face_addr
    movzx   eax, byte [rax]
    cmp     eax, r12d
    jae     .fail                               ; it must fall
    cmp     eax, 100
    jbe     .fail                               ; and stay above the bottom row
    mov     r12d, eax
    inc     ebx
    cmp     ebx, 5
    jb      .grad_row
    ; B1: SKM_SIDES, then SKM_TOP | SKM_BOTTOM
    TEXEL   TB1, SKF_FRONT, 0, 0, RGBO(4, 5, 6)
    TEXEL   TB1, SKF_LEFT, 1, 1, RGBO(4, 5, 6)
    TEXEL   TB1, SKF_TOP, 0, 0, RGBO(14, 15, 16)
    TEXEL   TB1, SKF_BOTTOM, 3, 1, RGBO(14, 15, 16)
    ; B2 (4 x 7 x 1, filled with 250): a multiplier above 256 clamps at 255, a one row face takes the top
    ; multiplier, a mask of two faces grades both, the faces outside the mask stay
    TEXEL   TB2, SKF_FRONT, 0, 0, RGBO(255, 255, 255)
    TEXEL   TB2, SKF_FRONT, 3, 6, RGBO(218, 218, 218)
    TEXEL   TB2, SKF_TOP, 0, 0, RGBO(125, 125, 125)
    TEXEL   TB2, SKF_TOP, 3, 0, RGBO(125, 125, 125)
    TEXEL   TB2, SKF_RIGHT, 0, 0, RGBO(250, 250, 250)
    TEXEL   TB2, SKF_RIGHT, 0, 6, RGBO(125, 125, 125)
    TEXEL   TB2, SKF_LEFT, 0, 0, RGBO(250, 250, 250)
    TEXEL   TB2, SKF_LEFT, 0, 6, RGBO(125, 125, 125)
    TEXEL   TB2, SKF_BACK, 0, 6, RGBO(250, 250, 250)
    TEXEL   TB2, SKF_BOTTOM, 0, 0, RGBO(250, 250, 250)
    ; FILL with noise on A2 (8 x 4 x 4 at (12, 1024)): hash values worked out apart from the engine
    mov     edi, 16
    mov     esi, 1028
    call    tsk_texel
    EXPECT  eax, RGBO(195, 146, 97)
    mov     edi, 19
    mov     esi, 1030
    call    tsk_texel
    EXPECT  eax, RGBO(190, 142, 95)
    mov     edi, 23
    mov     esi, 1031
    call    tsk_texel
    EXPECT  eax, RGBO(193, 145, 96)
    mov     edi, 20
    mov     esi, 1025
    call    tsk_texel
    EXPECT  eax, RGBO(196, 147, 98)
    mov     edi, 35
    mov     esi, 1031
    call    tsk_texel
    EXPECT  eax, RGBO(185, 138, 92)
    mov     edi, 28
    mov     esi, 1028
    call    tsk_texel
    EXPECT  eax, RGBO(192, 144, 96)
    mov     edi, 12                             ; the unwrap corner above the RIGHT face: no face
    mov     esi, 1024
    call    tsk_texel
    EXPECT  eax, 0
    mov     edi, 35
    mov     esi, 1024
    call    tsk_texel
    EXPECT  eax, 0
    ; B0 (120 x 8 x 8 at (0, 1032)): its FRONT face starts at (8, 1040), the corner (0, 1032) is no face
    mov     edi, 8
    mov     esi, 1040
    call    tsk_texel
    EXPECT  eax, RGBO(1, 2, 3)
    mov     edi, 0
    mov     esi, 1032
    call    tsk_texel
    EXPECT  eax, 0
    ; skin_verify fails with its own number for each kind of damage
    mov     word [TA0 + SKR_V], 100             ; a footprint above the skin region
    call    .check
    EXPECT  eax, 2
    mov     word [TA0 + SKR_V], 1024
    mov     byte [TA1 + SKR_W], 5               ; an AS part that differs from its source
    call    .check
    EXPECT  eax, 3
    mov     byte [TA1 + SKR_W], 4
    mov     word [TA1 + SKR_U], 1               ; an AS part placed elsewhere than its source (u, then v)
    call    .check
    EXPECT  eax, 3
    mov     word [TA1 + SKR_U], 0
    mov     word [TA1 + SKR_V], 1025
    call    .check
    EXPECT  eax, 3
    mov     word [TA1 + SKR_V], 1024
    mov     word [TB0 + SKR_V], 1024            ; B0's 256 x 16 footprint over A0 and A2
    call    .check
    EXPECT  eax, 4
    mov     word [TB0 + SKR_V], 1032
    lea     rdi, [TA0]                          ; a bare texel in a solid part
    mov     esi, SKF_FRONT
    mov     edx, 2
    mov     ecx, 3
    call    tsk_face_addr
    mov     r12, rax
    mov     r13d, [r12]
    mov     dword [r12], 0
    call    .check
    EXPECT  eax, 5
    mov     [r12], r13d
    lea     rdi, [TB1]                          ; a hole in a cutout part is fine ...
    mov     esi, SKF_FRONT
    mov     edx, 1
    mov     ecx, 1
    call    tsk_face_addr
    mov     r12, rax
    mov     r13d, [r12]
    mov     dword [r12], 0
    call    .check
    EXPECT  eax, 0
    mov     [r12], r13d
    lea     rdi, [TB1]                          ; ... a cutout face with nothing opaque is not
    mov     esi, SKF_TOP
    xor     edx, edx
    xor     ecx, ecx
    call    tsk_face_addr                       ; the face is 4 x 2: its two rows start 256 texels apart
    mov     r12, rax
    mov     dword [r12], 0
    mov     dword [r12 + 4], 0
    mov     dword [r12 + 8], 0
    mov     dword [r12 + 12], 0
    mov     dword [r12 + ATLAS_W * 4], 0
    mov     dword [r12 + ATLAS_W * 4 + 4], 0
    mov     dword [r12 + ATLAS_W * 4 + 8], 0
    mov     dword [r12 + ATLAS_W * 4 + 12], 0
    call    .check
    EXPECT  eax, 5
    mov     dword [r12], RGBO(14, 15, 16)
    mov     dword [r12 + 4], RGBO(14, 15, 16)
    mov     dword [r12 + 8], RGBO(14, 15, 16)
    mov     dword [r12 + 12], RGBO(14, 15, 16)
    mov     dword [r12 + ATLAS_W * 4], RGBO(14, 15, 16)
    mov     dword [r12 + ATLAS_W * 4 + 4], RGBO(14, 15, 16)
    mov     dword [r12 + ATLAS_W * 4 + 8], RGBO(14, 15, 16)
    mov     dword [r12 + ATLAS_W * 4 + 12], RGBO(14, 15, 16)
    call    .check                              ; everything restored
    EXPECT  eax, 0
    ; overflow: too many shelves, then a footprint wider than the atlas
    lea     rdi, [tsk_atlas]
    lea     rsi, [tsk_reg_c]
    call    skin_build
    EXPECT  eax, 1
    call    tsk_canary_ok
    test    eax, eax
    jnz     .fail
    mov     edi, 0                              ; nothing was painted: B0's bare corner is still bare
    mov     esi, 1032
    call    tsk_texel
    EXPECT  eax, 0
    lea     rdi, [tsk_atlas]
    lea     rsi, [tsk_reg_d]
    call    skin_build
    EXPECT  eax, 1
    call    tsk_canary_ok
    test    eax, eax
    jnz     .fail
    mov     edi, 100                            ; D's TOP face would start here
    mov     esi, 1024
    call    tsk_texel
    EXPECT  eax, 0
    ; skin_check is skin_build then skin_verify: 0 on the fixture, 1 on the two that do not fit
    lea     rdi, [tsk_atlas]
    lea     rsi, [tsk_reg_ab]
    call    skin_check
    EXPECT  eax, 0
    lea     rdi, [tsk_atlas]
    lea     rsi, [tsk_reg_c]
    call    skin_check
    EXPECT  eax, 1
    call    tsk_canary_ok
    test    eax, eax
    jnz     .fail
    lea     rdi, [tsk_atlas]
    lea     rsi, [tsk_reg_d]
    call    skin_check
    EXPECT  eax, 1
    call    tsk_canary_ok
    test    eax, eax
    jnz     .fail
    ; more own-skin footprints than skin_verify can compare (17 x 254 = 4318 > 4096): check 6, no overrun
    lea     rdi, [tsk_atlas]
    lea     rsi, [tsk_reg_e]
    call    skin_check
    EXPECT  eax, 6
    xor     eax, eax
    jmp     .out
.check:                                         ; skin_verify on the fixture registry -> eax
    sub     rsp, 8
    lea     rdi, [tsk_atlas]
    lea     rsi, [tsk_reg_ab]
    call    skin_verify
    add     rsp, 8
    ret
.fail:
    mov     eax, 1
.out:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
