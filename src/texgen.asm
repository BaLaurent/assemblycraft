; texgen.asm - procedural 256x256 RGBA texture atlas (13 tiles of 16x16).
;
; texgen_build(rdi out): zero out[262144], then draw tiles 0..12 in order using a
; single xorshift32 stream (state 0x12345678, x ^= x<<13; x ^= x>>17; x ^= x<<5;
; a "draw" returns the NEW state). Pixel = base*m >> 8 per channel, alpha 255.
;
; Register use inside texgen_build (leaf function, no external calls):
;   r12  = out base          r13d = rng state
;   rbx  = tile base pointer r14d = py, r15d = px
;   rdi  = current pixel pointer (set by TILE_BEGIN)
;   r8d  = per-pixel multiplier m
%include "common.inc"
default rel

global texgen_build

; packed colour: R | G<<8 | B<<16 (little-endian dword = RGBA bytes, A in bits 24..31)
%define RGB(r, g, b) ((r) | ((g) << 8) | ((b) << 16))

section .rodata
half:   dd 0.5

section .text

; rng: advance state, return it in eax. Clobbers ecx.
rng:
    mov     eax, r13d
    mov     ecx, eax
    shl     ecx, 13
    xor     eax, ecx
    mov     ecx, eax
    shr     ecx, 17
    xor     eax, ecx
    mov     ecx, eax
    shl     ecx, 5
    xor     eax, ecx
    mov     r13d, eax
    ret

; shade: write pixel at [rdi] = (esi.R*edx>>8, esi.G*edx>>8, esi.B*edx>>8, 255).
; Clobbers eax.
shade:
    movzx   eax, sil
    imul    eax, edx
    shr     eax, 8
    mov     [rdi], al
    mov     eax, esi
    shr     eax, 8
    movzx   eax, al
    imul    eax, edx
    shr     eax, 8
    mov     [rdi + 1], al
    mov     eax, esi
    shr     eax, 16
    movzx   eax, al
    imul    eax, edx
    shr     eax, 8
    mov     [rdi + 2], al
    mov     byte [rdi + 3], 255
    ret

; Open a tile: rbx = tile base, loop py (r14d) / px (r15d), rdi = pixel pointer.
%macro TILE_BEGIN 1
%push tile
    lea     rbx, [r12 + ((((%1) >> 4) * 16 * 256 + ((%1) & 15) * 16) * 4)]
    xor     r14d, r14d
%$row:
    xor     r15d, r15d
%$col:
    mov     edi, r14d
    shl     edi, 10
    add     rdi, rbx
    lea     rdi, [rdi + r15 * 4]
%endmacro

%macro TILE_END 0
    inc     r15d
    cmp     r15d, 16
    jb      %$col
    inc     r14d
    cmp     r14d, 16
    jb      %$row
%pop
%endmacro

; m = mbase + (rng & mask) -> r8d (one draw)
%macro DRAW_M 2
    call    rng
    and     eax, %2
    add     eax, %1
    mov     r8d, eax
%endmacro

; shade pixel with base colour (immediate) and m in r8d
%macro SHADE_IMM 1
    mov     esi, %1
    mov     edx, r8d
    call    shade
%endmacro

; plain noise pixel: draw, shade with immediate base
%macro NOISE_PIXEL 3                    ; base, mbase, mask
    DRAW_M  %2, %3
    SHADE_IMM %1
%endmacro

texgen_build:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24                     ; 16 bytes of per-column depths (+8 pad)

    mov     r12, rdi
    xor     eax, eax
    mov     ecx, 262144 / 8
    rep stosq                           ; rdi advances; r12 keeps the base
    mov     r13d, 0x12345678

    ; ---- 0 stone ----
    TILE_BEGIN 0
    NOISE_PIXEL RGB(128,128,128), 200, 55
    TILE_END

    ; ---- 1 grass_top ----
    TILE_BEGIN 1
    NOISE_PIXEL RGB(106,170,64), 192, 63
    TILE_END

    ; ---- 2 grass_side ----
    ; column depths first: d = 3 + (r&1), +2 more if (r&7)==0
    xor     r15d, r15d
.t2_depth:
    call    rng
    mov     edx, eax
    and     edx, 1
    add     edx, 3
    test    eax, 7
    jnz     .t2_store
    add     edx, 2
.t2_store:
    mov     [rsp + r15], dl
    inc     r15d
    cmp     r15d, 16
    jb      .t2_depth
    TILE_BEGIN 2
    DRAW_M  192, 63
    movzx   eax, byte [rsp + r15]
    mov     esi, RGB(150,108,74)
    cmp     r14d, eax
    jae     .t2_shade
    mov     esi, RGB(106,170,64)
.t2_shade:
    mov     edx, r8d
    call    shade
    TILE_END

    ; ---- 3 dirt ----
    TILE_BEGIN 3
    NOISE_PIXEL RGB(150,108,74), 192, 63
    TILE_END

    ; ---- 4 cobble ----
    TILE_BEGIN 4
    DRAW_M  176, 63
    mov     esi, RGB(70,70,70)
    mov     eax, r14d
    and     eax, 3
    cmp     eax, 3
    je      .t4_shade
    mov     eax, r14d
    shr     eax, 2
    lea     eax, [rax + rax * 2]        ; (py>>2)*3
    add     eax, r15d
    xor     edx, edx
    mov     ecx, 5
    div     ecx
    cmp     edx, 4
    je      .t4_shade
    mov     esi, RGB(130,130,130)
.t4_shade:
    mov     edx, r8d
    call    shade
    TILE_END

    ; ---- 5 planks ----
    TILE_BEGIN 5
    DRAW_M  216, 31
    mov     esi, RGB(110,86,50)
    mov     eax, r14d
    and     eax, 3
    cmp     eax, 3
    je      .t5_shade
    mov     eax, r14d
    shr     eax, 2
    imul    eax, eax, 7
    add     eax, 3
    and     eax, 15
    cmp     eax, r15d
    je      .t5_shade
    mov     esi, RGB(162,130,78)
.t5_shade:
    mov     edx, r8d
    call    shade
    TILE_END

    ; ---- 6 log_side ----
    TILE_BEGIN 6
    call    rng
    mov     r9d, eax                    ; r9d = r
    and     eax, 47
    add     eax, 208
    mov     r8d, eax
    mov     eax, r9d
    and     eax, 1
    add     eax, r15d
    and     eax, 3
    mov     esi, RGB(78,60,36)
    jz      .t6_shade
    mov     esi, RGB(104,82,50)
.t6_shade:
    mov     edx, r8d
    call    shade
    TILE_END

    ; ---- 7 log_top ----
    TILE_BEGIN 7
    DRAW_M  224, 31
    mov     esi, RGB(104,82,50)
    test    r15d, r15d
    jz      .t7_shade
    cmp     r15d, 15
    je      .t7_shade
    test    r14d, r14d
    jz      .t7_shade
    cmp     r14d, 15
    je      .t7_shade
    lea     eax, [r15 * 2 - 15]         ; dx
    lea     ecx, [r14 * 2 - 15]         ; dy
    imul    eax, eax
    imul    ecx, ecx
    add     eax, ecx
    cvtsi2ss xmm0, eax
    sqrtss  xmm0, xmm0
    mulss   xmm0, [half]
    cvttss2si eax, xmm0
    shr     eax, 1
    and     eax, 1
    mov     esi, RGB(176,140,88)
    jz      .t7_shade
    mov     esi, RGB(150,118,70)
.t7_shade:
    mov     edx, r8d
    call    shade
    TILE_END

    ; ---- 8 leaves ----
    TILE_BEGIN 8
    call    rng
    test    eax, 3
    jnz     .t8_solid
    mov     dword [rdi], 0
    jmp     .t8_next
.t8_solid:
    and     eax, 95
    add     eax, 160
    mov     r8d, eax
    SHADE_IMM RGB(60,140,40)
.t8_next:
    TILE_END

    ; ---- 9 sand ----
    TILE_BEGIN 9
    NOISE_PIXEL RGB(222,210,160), 224, 31
    TILE_END

    ; ---- 10 glass (no rng) ----
    TILE_BEGIN 10
    xor     edx, edx                    ; default transparent
    test    r15d, r15d
    jz      .t10_border
    cmp     r15d, 15
    je      .t10_border
    test    r14d, r14d
    jz      .t10_border
    cmp     r14d, 15
    je      .t10_border
    lea     eax, [r15 - 3]
    cmp     eax, 5                      ; 3 <= px <= 8
    ja      .t10_store
    lea     eax, [r15 + r14]
    sub     eax, 10
    cmp     eax, 1                      ; px+py in {10,11}
    ja      .t10_store
    mov     edx, 0xFFFFFFFF
    jmp     .t10_store
.t10_border:
    mov     edx, 0xFFF5F0DC             ; (220,240,245,255)
.t10_store:
    mov     [rdi], edx
    TILE_END

    ; ---- 11 brick ----
    TILE_BEGIN 11
    DRAW_M  200, 55
    mov     esi, RGB(180,180,170)
    mov     eax, r14d
    and     eax, 3
    cmp     eax, 3
    je      .t11_shade
    mov     eax, r14d
    shr     eax, 2
    and     eax, 1
    shl     eax, 2
    add     eax, r15d
    and     eax, 7
    cmp     eax, 7
    je      .t11_shade
    mov     esi, RGB(156,72,56)
.t11_shade:
    mov     edx, r8d
    call    shade
    TILE_END

    ; ---- 12 bedrock ----
    TILE_BEGIN 12
    NOISE_PIXEL RGB(80,80,80), 64, 191
    TILE_END

    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
