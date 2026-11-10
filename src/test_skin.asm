; test_skin.asm - the 0.13 skin engine (skin.asm): the unwrap and its texcoords (test_skin_uv); the packer
; (sorted shelves), the paint ops, the overflow guards and the skin_verify / skin_check proofs (test_skin_pack);
; and the shipped art itself: the registry skin_models of artreg.asm must fit and be fully painted, in the
; contracted order with the style guide's part counts (test_skin_models).
%include "common.inc"
%include "art.inc"
default rel

global test_skin_uv, test_skin_pack, test_skin_models

extern skin_face_rect, skin_face_uvs, skin_build, skin_check, skin_verify, skin_models
extern m_zombie, m_skeleton, m_creeper, m_spider, m_pig, m_chicken, m_boss
extern m_folk_villagers, m_folk_bandits, m_folk_cult, m_folk_beastfolk, m_folk_stonekin
extern m_villager_elder, m_villager_merchant, m_avatar
extern m_extra_hat, m_extra_helmet, m_extra_pack, m_extra_crown
extern m_hood_villagers, m_hood_bandits, m_hood_cult, m_hood_beastfolk, m_hood_stonekin
extern m_gun_pistol, m_gun_musket, m_gun_shotgun, m_gun_rifle, m_gun_launcher, m_gun_warhead
extern m_gun_revolver, m_gun_hrifle, m_boat, m_plane, m_plane_prop

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
; TSK_FILLS n: an opaque fill of every face of parts 0..n-1 (the parts of the bulk fixtures need no more)
%macro TSK_FILLS 1
%assign tsk_i 0
%rep %1
    SK_FILL tsk_i, SKM_ALL, RGBO(7, 7, 7), 0
%assign tsk_i tsk_i + 1
%endrep
%endmacro
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
; model B: a 120 x 8 x 8 part (footprint 256 x 16), a cutout part (12 x 4), a 4 x 7 x 1 part for the gradient
; edge cases (10 x 8), a tiny one (10 x 2), a 120 x 2 x 8 part (256 x 10) and a wide flat one (250 x 2)
SKMODEL_BEGIN tsk_model_b, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.0
    SKPART 0, 0, 0, 120, 8, 8, 0, 0
    SKPART 0, 8, 0, 4, 2, 2, 0, SKPF_CUTOUT
    SKPART 0, 16, 0, 4, 7, 1, 0, 0
    SKPART 0, 24, 0, 4, 1, 1, 0, 0
    SKPART 0, 0, 16, 120, 2, 8, 0, 0
    SKPART 0, 0, 32, 124, 1, 1, 0, 0
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
    SK_FILL 5, SKM_ALL, RGBO(15, 16, 17), 0
SKMODEL_END
; model C: 30 own-skin parts of 120 x 100 x 8 (footprint 256 x 108): 28 fit in the 3072 skin rows
SKMODEL_BEGIN tsk_model_c, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.0
%rep 30
    SKPART 0, 0, 0, 120, 100, 8, 0, 0
%endrep
SKMODEL_PAINT
    TSK_FILLS 30
SKMODEL_END
; model D: one part 100 x 4 x 100, a 400 texel wide footprint
SKMODEL_BEGIN tsk_model_d, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.0
    SKPART 0, 0, 0, 100, 4, 100, 0, 0
SKMODEL_PAINT
    SK_FILL 0, SKM_ALL, RGBO(7, 7, 7), 0
SKMODEL_END
; model E: 254 parts of 1 x 1 x 1 (the most a model holds): 4 x 2 footprints, listed 16 or 17 times in the
; registries below to reach and pass the 4096 own-skin parts the packer takes; E32 and E1 make up the difference
SKMODEL_BEGIN tsk_model_e, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.0
%rep 254
    SKPART 0, 0, 0, 1, 1, 1, 0, 0
%endrep
SKMODEL_PAINT
    TSK_FILLS 254
SKMODEL_END
SKMODEL_BEGIN tsk_model_e32, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.0
%rep 32
    SKPART 0, 0, 0, 1, 1, 1, 0, 0
%endrep
SKMODEL_PAINT
    TSK_FILLS 32
SKMODEL_END
SKMODEL_BEGIN tsk_model_e1, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.0
    SKPART 0, 0, 0, 1, 1, 1, 0, 0
SKMODEL_PAINT
    TSK_FILLS 1
SKMODEL_END
; models F and F2: tall and short footprints alternating in record order: T1 (128 x 100), S1 (128 x 8), T2, S2.
; In that order the shelves would be T1 + S1, T2 + S2 (100 rows each); sorted they are T1 + T2, S1 + S2 (108)
%macro TSK_FMODEL 1
SKMODEL_BEGIN %1, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.0
    SKPART 0, 0, 0, 60, 96, 4, 0, 0
    SKPART 0, 0, 0, 60, 4, 4, 0, 0
    SKPART 0, 0, 0, 60, 96, 4, 0, 0
    SKPART 0, 0, 0, 60, 4, 4, 0, 0
SKMODEL_PAINT
    SK_FILL 0, SKM_ALL, RGBO(30, 31, 32), 0
    SK_FILL 1, SKM_ALL, RGBO(33, 34, 35), 0
    SK_FILL 2, SKM_ALL, RGBO(36, 37, 38), 0
    SK_FILL 3, SKM_ALL, RGBO(39, 40, 41), 0
SKMODEL_END
%endmacro
TSK_FMODEL tsk_model_f
TSK_FMODEL tsk_model_f2
; models G and G1: 24 (25) parts of 120 x 120 x 8, footprint 256 x 128: 24 fill the 3072 skin rows exactly
SKMODEL_BEGIN tsk_model_g, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.0
%rep 24
    SKPART 0, 0, 0, 120, 120, 8, 0, 0
%endrep
SKMODEL_PAINT
    TSK_FILLS 24
SKMODEL_END
SKMODEL_BEGIN tsk_model_g1, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.0
%rep 25
    SKPART 0, 0, 0, 120, 120, 8, 0, 0
%endrep
SKMODEL_PAINT
    TSK_FILLS 25
SKMODEL_END
align 8
tsk_reg_a:    dq tsk_model_a, 0
tsk_reg_ab:   dq tsk_model_a, tsk_model_b, 0
tsk_reg_c:    dq tsk_model_c, 0
tsk_reg_d:    dq tsk_model_d, 0
tsk_reg_e17:  times 17 dq tsk_model_e           ; 4318 own-skin parts: more than the packer takes
              dq 0
tsk_reg_cap:  times 16 dq tsk_model_e           ; 4064 + 32 = 4096: exactly what it takes
              dq tsk_model_e32, 0
tsk_reg_cap1: times 16 dq tsk_model_e           ; 4097: one too many
              dq tsk_model_e32, tsk_model_e1, 0
tsk_reg_f:    dq tsk_model_f, tsk_model_f2, 0
tsk_reg_g:    dq tsk_model_g, 0
tsk_reg_g1:   dq tsk_model_g1, 0
tsk_reg_det:  dq tsk_model_a, tsk_model_b, tsk_model_f, tsk_model_f2, 0

; the part records of the fixtures (a bone record comes first in each model)
%define TA0 (tsk_model_a_recs + 1 * SKREC_SIZE)
%define TA1 (tsk_model_a_recs + 2 * SKREC_SIZE)
%define TA2 (tsk_model_a_recs + 3 * SKREC_SIZE)
%define TB0 (tsk_model_b_recs + 1 * SKREC_SIZE)
%define TB1 (tsk_model_b_recs + 2 * SKREC_SIZE)
%define TB2 (tsk_model_b_recs + 3 * SKREC_SIZE)
%define TB3 (tsk_model_b_recs + 4 * SKREC_SIZE)
%define TB4 (tsk_model_b_recs + 5 * SKREC_SIZE)
%define TB5 (tsk_model_b_recs + 6 * SKREC_SIZE)
%define TF1 (tsk_model_f_recs + 1 * SKREC_SIZE)         ; T1, S1, T2, S2 of F
%define TF2 (tsk_model_f_recs + 2 * SKREC_SIZE)
%define TF3 (tsk_model_f_recs + 3 * SKREC_SIZE)
%define TF4 (tsk_model_f_recs + 4 * SKREC_SIZE)
%define TH1 (tsk_model_f2_recs + 1 * SKREC_SIZE)        ; and of F2
%define TH2 (tsk_model_f2_recs + 2 * SKREC_SIZE)
%define TH3 (tsk_model_f2_recs + 3 * SKREC_SIZE)
%define TH4 (tsk_model_f2_recs + 4 * SKREC_SIZE)
%define TG0 (tsk_model_g_recs + 1 * SKREC_SIZE)         ; the first and the last part of G
%define TG23 (tsk_model_g_recs + 24 * SKREC_SIZE)
; where skin_build must put them (the unwrap footprints of every own-skin part of every model, tallest first,
; wider first among equal heights, then registry and record order, on shelves of the tallest one):
; registry [A, B]: B0 256 x 16, B4 256 x 10, then a shelf of 8 rows: A2 24 x 8, A0 12 x 8, B2 10 x 8,
; B1 12 x 4, then B5 250 x 2 and B3 10 x 2 on a shelf each (38 rows; next-fit in record order: 44)
%define B0_U 0
%define B0_V 1024
%define B4_U 0
%define B4_V 1040
%define A2_U 0
%define A2_V 1050
%define A0_U 24
%define A0_V 1050
%define B2_U 36
%define B2_V 1050
%define B1_U 46
%define B1_V 1050
%define B5_U 0
%define B5_V 1058
%define B3_U 0
%define B3_V 1060
section .bss
align 16
tsk_atlas:  resb ATLAS_W * ATLAS_H * 4
tsk_canary: resb 64                     ; right behind the atlas
tsk_guard:  resb 262144                 ; so that a broken packer's overrun hurts nothing else
tsk_snap:   resb ATLAS_W * ATLAS_H * 4  ; a copy of an atlas, for the determinism check

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

; BARE part: fail unless the texel at the part's unwrap origin (the corner no face covers) is still bare
%macro BARE 1
    movzx   edi, word [%1 + SKR_U]
    movzx   esi, word [%1 + SKR_V]
    call    tsk_texel
    test    eax, eax
    jnz     .fail
%endmacro

; BUILD_OK registry: skin_build on a cleared test atlas must fit
%macro BUILD_OK 1
    call    tsk_atlas_clear
    lea     rdi, [tsk_atlas]
    lea     rsi, [%1]
    call    skin_build
    test    eax, eax
    jnz     .fail
%endmacro

; BUILD_REFUSED registry: skin_build on a cleared test atlas must return 1, paint nothing and leave the canary
%macro BUILD_REFUSED 1
    call    tsk_atlas_clear
    lea     rdi, [tsk_atlas]
    lea     rsi, [%1]
    call    skin_build
    EXPECT  eax, 1
    call    tsk_atlas_blank
    test    eax, eax
    jnz     .fail
    call    tsk_canary_ok
    test    eax, eax
    jnz     .fail
%endmacro

; ROWS_ARE registry, n: the registry's parts cover exactly n rows of the skin region
%macro ROWS_ARE 2
    lea     rsi, [%1]
    call    tsk_rows_used
    EXPECT  eax, %2
%endmacro

; tsk_rows_used(rsi registry) -> eax the rows of the skin region the registry's parts cover: the greatest
; v + d + h of its parts, less SKIN_Y0. Leaf.
tsk_rows_used:
    xor     eax, eax
.model:
    mov     rdx, [rsi]
    test    rdx, rdx
    jz      .done
    mov     rdx, [rdx + SKMODEL.recs]
.rec:
    cmp     byte [rdx + SKR_TYPE], SKR_PART
    jne     .not_part
    movzx   ecx, word [rdx + SKR_V]
    movzx   edi, byte [rdx + SKR_D]
    add     ecx, edi
    movzx   edi, byte [rdx + SKR_H]
    add     ecx, edi
    cmp     eax, ecx
    cmovb   eax, ecx
    jmp     .next
.not_part:
    cmp     byte [rdx + SKR_TYPE], SKR_BONE
    jne     .model_done
.next:
    add     rdx, SKREC_SIZE
    jmp     .rec
.model_done:
    add     rsi, 8
    jmp     .model
.done:
    sub     eax, SKIN_Y0
    ret

; tsk_atlas_clear(): zero the test atlas. Leaf.
tsk_atlas_clear:
    lea     rdi, [tsk_atlas]
    mov     ecx, ATLAS_W * ATLAS_H
    xor     eax, eax
    rep     stosd
    ret

; tsk_atlas_blank() -> eax 0 when every texel of the test atlas is 0. Leaf.
tsk_atlas_blank:
    lea     rdi, [tsk_atlas]
    mov     ecx, ATLAS_W * ATLAS_H
    xor     eax, eax
    repe    scasd
    jne     .painted
    xor     eax, eax
    ret
.painted:
    mov     eax, 1
    ret

; tsk_snap_save(): copy the test atlas to tsk_snap. Leaf.
tsk_snap_save:
    lea     rsi, [tsk_atlas]
    lea     rdi, [tsk_snap]
    mov     ecx, ATLAS_W * ATLAS_H
    rep     movsd
    ret

; tsk_snap_same() -> eax 0 when the test atlas is, byte for byte, tsk_snap. Leaf.
tsk_snap_same:
    lea     rsi, [tsk_atlas]
    lea     rdi, [tsk_snap]
    mov     ecx, ATLAS_W * ATLAS_H
    repe    cmpsd
    jne     .differs
    xor     eax, eax
    ret
.differs:
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
;   skin_build packs the unwrap footprints of every own-skin part of every model together: tallest first, wider
;   first among equal heights, then registry and record order, on shelves of the tallest footprint.
;   - [A, B] lands where the reference packer puts it (A2 24 x 8, A0 12 x 8 and B2 10 x 8 share a shelf, B5
;     250 x 2 and B3 10 x 2 wrap), 38 rows, and the SKPART_AS part copies size and place of its source;
;   - [F, F2], tall (128 x 100) and short (128 x 8) footprints alternating in record order, takes 216 rows where
;     next-fit in record order takes 400 (128 + 128 also fills a shelf exactly);
;   - 24 footprints of 256 x 128 fill the 3072 skin rows exactly, a 25th is refused;
;   - the same registry built again on a clean atlas, after a bigger one went through the packer, gives a
;     byte-identical atlas;
;   - 4096 own-skin parts fit, 4097 do not.
;   On A alone (the texels around it are then bare) every paint op lands as specified: FILL (face masks; with
;   noise: hash values worked out apart from the engine; an unwrap corner no face covers stays bare), RECT and BMP
;   (palette colours; '.' and a char missing from the palette leave the texel; an op that overhangs a face is
;   clipped to it, one that starts outside it paints nothing), GRAD (a 6 row face filled with 200: row 0 stays
;   200, row 5 is 100, the rows between fall; a multiplier above 256 clamps at 255; a one row face takes the top
;   multiplier; unmasked faces stay) and an op on an AS part (it paints the shared rect).
;   skin_verify passes on a built registry, and fails with the right number when a footprint leaves the region
;   (2), an AS part differs in size or place (3), footprints overlap (4), a texel is bare in a solid part or a
;   whole face of a cutout part is (5; a hole in a cutout part is fine), or there are more own-skin footprints
;   than it compares (6; skin_check says 1 there, the packer refuses them). The overflow fixtures (30 parts of
;   256 x 108 where 28 fit, a 400 texel wide footprint, 25 x 128 rows, 4097 parts) make skin_build and
;   skin_check return 1, paint nothing and leave the 64 byte canary behind the atlas intact.
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
    ; ---- packing across models: registry [A, B]
    BUILD_OK tsk_reg_ab
    EXPECT  word [TB0 + SKR_U], B0_U
    EXPECT  word [TB0 + SKR_V], B0_V
    EXPECT  word [TB4 + SKR_U], B4_U
    EXPECT  word [TB4 + SKR_V], B4_V
    EXPECT  word [TA2 + SKR_U], A2_U
    EXPECT  word [TA2 + SKR_V], A2_V
    EXPECT  word [TA0 + SKR_U], A0_U
    EXPECT  word [TA0 + SKR_V], A0_V
    EXPECT  word [TB2 + SKR_U], B2_U
    EXPECT  word [TB2 + SKR_V], B2_V
    EXPECT  word [TB1 + SKR_U], B1_U
    EXPECT  word [TB1 + SKR_V], B1_V
    EXPECT  word [TB5 + SKR_U], B5_U
    EXPECT  word [TB5 + SKR_V], B5_V
    EXPECT  word [TB3 + SKR_U], B3_U
    EXPECT  word [TB3 + SKR_V], B3_V
    ROWS_ARE tsk_reg_ab, 38
    ; the AS part: size and place of part 0
    EXPECT  byte [TA1 + SKR_W], 4
    EXPECT  byte [TA1 + SKR_H], 6
    EXPECT  byte [TA1 + SKR_D], 2
    EXPECT  word [TA1 + SKR_U], A0_U
    EXPECT  word [TA1 + SKR_V], A0_V
    lea     rdi, [tsk_atlas]
    lea     rsi, [tsk_reg_ab]
    call    skin_verify
    test    eax, eax
    jnz     .fail
    ; B0 (120 x 8 x 8): the corner at its unwrap origin is no face; B1: SKM_SIDES, then SKM_TOP | SKM_BOTTOM
    TEXEL   TB0, SKF_FRONT, 0, 0, RGBO(1, 2, 3)
    BARE    TB0
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
    ; skin_verify fails with its own number for each kind of damage
    mov     word [TA0 + SKR_V], 100             ; a footprint above the skin region
    call    .check
    EXPECT  eax, 2
    mov     word [TA0 + SKR_V], A0_V
    mov     byte [TA1 + SKR_W], 5               ; an AS part that differs from its source
    call    .check
    EXPECT  eax, 3
    mov     byte [TA1 + SKR_W], 4
    mov     word [TA1 + SKR_U], 1               ; an AS part placed elsewhere than its source (u, then v)
    call    .check
    EXPECT  eax, 3
    mov     word [TA1 + SKR_U], A0_U
    mov     word [TA1 + SKR_V], A0_V + 1
    call    .check
    EXPECT  eax, 3
    mov     word [TA1 + SKR_V], A0_V
    mov     word [TB0 + SKR_V], B4_V            ; B0's 256 x 16 footprint over B4 and the shelf below
    call    .check
    EXPECT  eax, 4
    mov     word [TB0 + SKR_V], B0_V
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
    ; ---- the paint ops, on A alone (the texels around it are then bare): A2 (24 x 8) comes before A0 (12 x 8)
    BUILD_OK tsk_reg_a
    EXPECT  word [TA2 + SKR_U], 0
    EXPECT  word [TA2 + SKR_V], 1024
    EXPECT  word [TA0 + SKR_U], 24
    EXPECT  word [TA0 + SKR_V], 1024
    EXPECT  word [TA1 + SKR_U], 24
    EXPECT  word [TA1 + SKR_V], 1024
    ROWS_ARE tsk_reg_a, 8
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
    TEXEL   TA0, SKF_RIGHT, 1, 6, 0                      ; nor did its third row fall below the face
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
    ; FILL with noise on A2 (8 x 4 x 4 at (0, 1024)): hash values worked out apart from the engine
    mov     edi, 4
    mov     esi, 1028
    call    tsk_texel
    EXPECT  eax, RGBO(196, 147, 98)
    mov     edi, 7
    mov     esi, 1030
    call    tsk_texel
    EXPECT  eax, RGBO(181, 135, 90)
    mov     edi, 11
    mov     esi, 1031
    call    tsk_texel
    EXPECT  eax, RGBO(191, 143, 95)
    mov     edi, 8
    mov     esi, 1025
    call    tsk_texel
    EXPECT  eax, RGBO(192, 144, 96)
    mov     edi, 23
    mov     esi, 1031
    call    tsk_texel
    EXPECT  eax, RGBO(193, 145, 96)
    mov     edi, 16
    mov     esi, 1028
    call    tsk_texel
    EXPECT  eax, RGBO(195, 146, 97)
    mov     edi, 20
    mov     esi, 1029
    call    tsk_texel
    EXPECT  eax, RGBO(178, 133, 89)
    BARE    TA2                                 ; the unwrap corner above the RIGHT face: no face
    mov     edi, 23                             ; and the one above the LEFT/BACK end
    mov     esi, 1024
    call    tsk_texel
    EXPECT  eax, 0
    lea     rdi, [tsk_atlas]
    lea     rsi, [tsk_reg_a]
    call    skin_verify
    test    eax, eax
    jnz     .fail
    ; ---- tall before short: F and F2 hold T (128 x 100) and S (128 x 8) footprints alternating
    BUILD_OK tsk_reg_f
    EXPECT  word [TF1 + SKR_U], 0               ; the tall ones first, in registry then record order
    EXPECT  word [TF1 + SKR_V], 1024
    EXPECT  word [TF3 + SKR_U], 128             ; 128 + 128 fill the shelf exactly
    EXPECT  word [TF3 + SKR_V], 1024
    EXPECT  word [TH1 + SKR_U], 0
    EXPECT  word [TH1 + SKR_V], 1124
    EXPECT  word [TH3 + SKR_U], 128
    EXPECT  word [TH3 + SKR_V], 1124
    EXPECT  word [TF2 + SKR_U], 0               ; then the short ones, in the same order
    EXPECT  word [TF2 + SKR_V], 1224
    EXPECT  word [TF4 + SKR_U], 128
    EXPECT  word [TF4 + SKR_V], 1224
    EXPECT  word [TH2 + SKR_U], 0
    EXPECT  word [TH2 + SKR_V], 1232
    EXPECT  word [TH4 + SKR_U], 128
    EXPECT  word [TH4 + SKR_V], 1232
    ROWS_ARE tsk_reg_f, 216                     ; next-fit in record order: 400
    lea     rdi, [tsk_atlas]
    lea     rsi, [tsk_reg_f]
    call    skin_verify
    test    eax, eax
    jnz     .fail
    ; ---- the last shelf may end exactly at the bottom of the atlas, one more may not
    BUILD_OK tsk_reg_g
    EXPECT  word [TG0 + SKR_V], 1024
    EXPECT  word [TG23 + SKR_V], 3968
    ROWS_ARE tsk_reg_g, 3072
    lea     rdi, [tsk_atlas]
    lea     rsi, [tsk_reg_g]
    call    skin_verify
    test    eax, eax
    jnz     .fail
    BUILD_REFUSED tsk_reg_g1
    ; ---- deterministic: the same registry gives the same atlas, after a different one went through the packer
    BUILD_OK tsk_reg_det                        ; [A, B, F, F2]: 254 rows, the tall F parts first
    EXPECT  word [TF1 + SKR_V], 1024
    EXPECT  word [TB0 + SKR_V], 1224
    EXPECT  word [TB4 + SKR_V], 1240
    EXPECT  word [TH2 + SKR_V], 1258
    EXPECT  word [TA2 + SKR_V], 1266
    EXPECT  word [TB3 + SKR_V], 1276
    ROWS_ARE tsk_reg_det, 254
    call    tsk_snap_save
    BUILD_OK tsk_reg_cap                        ; 4096 footprints dirty every buffer of the packer
    BUILD_OK tsk_reg_det
    call    tsk_snap_same
    test    eax, eax
    jnz     .fail
    ; ---- at most 4096 own-skin parts (E: 4064 + E32: 32 is exactly that), skin_verify compares as many
    BUILD_OK tsk_reg_cap
    BUILD_REFUSED tsk_reg_cap1                  ; one more
    lea     rdi, [tsk_atlas]                    ; E's records still hold the cap build's places
    lea     rsi, [tsk_reg_e17]
    call    skin_verify
    EXPECT  eax, 6
    call    tsk_atlas_clear
    lea     rdi, [tsk_atlas]
    lea     rsi, [tsk_reg_e17]
    call    skin_check                          ; the packer refuses it first
    EXPECT  eax, 1
    call    tsk_atlas_blank
    test    eax, eax
    jnz     .fail
    call    tsk_canary_ok
    test    eax, eax
    jnz     .fail
    ; ---- overflow: too many shelves, then a footprint wider than the atlas
    BUILD_REFUSED tsk_reg_c
    BUILD_REFUSED tsk_reg_d
    ; skin_check is skin_build then skin_verify: 0 on the fixture, 1 on the two that do not fit
    call    tsk_atlas_clear
    lea     rdi, [tsk_atlas]
    lea     rsi, [tsk_reg_ab]
    call    skin_check
    EXPECT  eax, 0
    call    tsk_atlas_clear
    lea     rdi, [tsk_atlas]
    lea     rsi, [tsk_reg_c]
    call    skin_check
    EXPECT  eax, 1
    call    tsk_canary_ok
    test    eax, eax
    jnz     .fail
    call    tsk_atlas_clear
    lea     rdi, [tsk_atlas]
    lea     rsi, [tsk_reg_d]
    call    skin_check
    EXPECT  eax, 1
    call    tsk_canary_ok
    test    eax, eax
    jnz     .fail
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

section .rodata
align 8
; TSM_ROW model, minimum parts, texels per block: the registry in the contracted order with the style guide's
; part counts (the humanoids 14, the mobs 9..19, the boss 16, the guns 8, the boat 10, the plane 20, the
; propeller 3; the extras and the launcher's rocket are small by design) and the contracted scale: 32 texels per
; block for characters and vehicles, 64 for the guns
%macro TSM_ROW 3
    dq %1
    dd %2, %3
%endmacro
tsm_rows:
    TSM_ROW m_zombie, 10, 32
    TSM_ROW m_skeleton, 10, 32
    TSM_ROW m_creeper, 10, 32
    TSM_ROW m_spider, 19, 32
    TSM_ROW m_pig, 10, 32
    TSM_ROW m_chicken, 9, 32
    TSM_ROW m_boss, 16, 32
    TSM_ROW m_folk_villagers, 14, 32
    TSM_ROW m_folk_bandits, 14, 32
    TSM_ROW m_folk_cult, 14, 32
    TSM_ROW m_folk_beastfolk, 14, 32
    TSM_ROW m_folk_stonekin, 14, 32
    TSM_ROW m_villager_elder, 14, 32
    TSM_ROW m_villager_merchant, 14, 32
    TSM_ROW m_avatar, 14, 32
    TSM_ROW m_extra_hat, 3, 32
    TSM_ROW m_extra_helmet, 4, 32
    TSM_ROW m_extra_pack, 4, 32
    TSM_ROW m_extra_crown, 3, 32
    TSM_ROW m_hood_villagers, 4, 32
    TSM_ROW m_hood_bandits, 4, 32
    TSM_ROW m_hood_cult, 4, 32
    TSM_ROW m_hood_beastfolk, 4, 32
    TSM_ROW m_hood_stonekin, 4, 32
    TSM_ROW m_gun_pistol, 8, 64
    TSM_ROW m_gun_musket, 8, 64
    TSM_ROW m_gun_shotgun, 8, 64
    TSM_ROW m_gun_rifle, 8, 64
    TSM_ROW m_gun_launcher, 8, 64
    TSM_ROW m_gun_warhead, 3, 64
    TSM_ROW m_gun_revolver, 8, 64
    TSM_ROW m_gun_hrifle, 8, 64
    TSM_ROW m_boat, 10, 32
    TSM_ROW m_plane, 20, 32
    TSM_ROW m_plane_prop, 3, 32
tsm_rows_end:

section .text

; test_skin_models() -> eax 0 pass / 10 + n skin_check returned n (1 the unwraps do not fit, 2 a footprint
;   leaves the skin region, 3 a SKPART_AS part differs from its source, 4 two footprints overlap, 5 a bare texel,
;   6 too many own-skin parts) / 2 the canary behind the atlas changed / 3 the registry is not tsm_rows (a model
;   missing, extra or out of order) / 4 a model without a bone / 5 a model with fewer parts than the minimum /
;   6 a model's texels per block differ from the contract
;   The shipped registry skin_models goes through skin_check on a zeroed atlas of the test's own (skin_build,
;   then every texel of every face opaque), then every registry model is walked against tsm_rows.
test_skin_models:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    lea     rdi, [tsk_atlas]
    mov     ecx, ATLAS_W * ATLAS_H * 4 / 8
    xor     eax, eax
    rep stosq                           ; test_skin_pack left its fixtures in the atlas
    lea     rdi, [tsk_canary]
    mov     ecx, 64
    mov     eax, 0xAA
    rep stosb
    lea     rdi, [tsk_atlas]
    lea     rsi, [skin_models]
    call    skin_check
    test    eax, eax
    jnz     .check_failed
    call    tsk_canary_ok
    test    eax, eax
    jnz     .canary
    lea     rbx, [tsm_rows]
    lea     r13, [skin_models]
.model:
    mov     r12, [r13]                  ; the registry's model at this index ...
    cmp     r12, [rbx]                  ; ... is the contracted one
    jne     .order
    mov     rsi, [r12 + SKMODEL.recs]
    xor     ecx, ecx                    ; bone records
    xor     edx, edx                    ; part records
.rec:
    movzx   eax, byte [rsi + SKR_TYPE]
    cmp     eax, SKR_END
    je      .counted
    cmp     eax, SKR_BONE
    jne     .part
    inc     ecx
    jmp     .rec_next
.part:
    inc     edx
.rec_next:
    add     rsi, SKREC_SIZE
    jmp     .rec
.counted:
    test    ecx, ecx
    jz      .no_bone
    cmp     edx, [rbx + 8]
    jb      .few_parts
    movzx   eax, word [r12 + SKMODEL.tpb]
    cmp     eax, [rbx + 12]
    jne     .bad_tpb
    add     rbx, 16
    add     r13, 8
    lea     rax, [tsm_rows_end]
    cmp     rbx, rax
    jb      .model
    cmp     qword [r13], 0              ; and the registry ends with the last row
    jne     .order
    xor     eax, eax
    jmp     .out
.check_failed:
    add     eax, 10
    jmp     .out
.canary:
    mov     eax, 2
    jmp     .out
.order:
    mov     eax, 3
    jmp     .out
.no_bone:
    mov     eax, 4
    jmp     .out
.few_parts:
    mov     eax, 5
    jmp     .out
.bad_tpb:
    mov     eax, 6
.out:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
