; texgen.asm - procedural 256x256 RGBA texture atlas (16x16 tiles plus the 8x8 font).
;
; texgen_build(rdi out): zero out[262144], then draw tiles in order using a single
; xorshift32 stream (state 0x12345678, x ^= x<<13; x ^= x>>17; x ^= x<<5; a "draw"
; returns the NEW state). Pixel = base*m >> 8 per channel, alpha 255. Tiles 13, 14,
; the crack stages (256 draws first) and 64..70 continue the stream after tile 12;
; then, in this order, the ores 26..29, furnaces 30/31, chest 43/44, gravel 45, TNT
; 46/47 and the mob tiles 71..79 follow tile 70; item icons (32..42, 80..128) and HUD
; icons (48..56) use no rng. The 0.6 RPG art (stone bricks 59/60, item icons 129..138, ability
; icons 139..150, class emblems 151..154, stat icons 155..172, villager/boss textures 173..179)
; is drawn after tile 128, so it never shifts an older rng draw: bricks and the 174..179
; textures are 16x16 bitmaps shaded by one draw per pixel (173 is plain noise), the icons are
; draw-free bitmaps. The font is painted last (white glyph texels) at atlas
; rows FONT_Y..FONT_Y+47.
;
; Register use inside texgen_build (leaf function, no external calls):
;   r12  = out base          r13d = rng state
;   rbx  = tile base pointer r14d = py, r15d = px
;   rdi  = current pixel pointer (set by TILE_BEGIN)
;   r8d  = per-pixel multiplier m
%include "common.inc"
default rel

global texgen_build

extern font8x8

; packed colour: R | G<<8 | B<<16 (little-endian dword = RGBA bytes, A in bits 24..31)
%define RGB(r, g, b) ((r) | ((g) << 8) | ((b) << 16))
; opaque packed colour for the icon tiles (alpha 255)
%define RGBO(r, g, b) ((r) | ((g) << 8) | ((b) << 16) | 0xFF000000)

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

; same as TILE_BEGIN but for a tile base already in rbx
%macro TILE_BEGIN_RBX 0
%push tile
    xor     r14d, r14d
%$row:
    xor     r15d, r15d
%$col:
    mov     edi, r14d
    shl     edi, 10
    add     rdi, rbx
    lea     rdi, [rdi + r15 * 4]
%endmacro

; icon tile: pixel routine returns the packed RGBA in eax
%macro ICON 2
    TILE_BEGIN %1
    call    %2
    mov     [rdi], eax
    TILE_END
%endmacro

; tool icon: r10d = main colour m, r11d = dark colour M
%macro ICONT 4
    TILE_BEGIN %1
    mov     r10d, %3
    mov     r11d, %4
    call    %2
    mov     [rdi], eax
    TILE_END
%endmacro

; HUD icon: bitmap, full palette, empty palette, split column
%macro HUD 5
    TILE_BEGIN %1
    lea     r9, [%2]
    lea     r10, [%3]
    lea     r11, [%4]
    mov     r8d, %5
    call    hud_px
    mov     [rdi], eax
    TILE_END
%endmacro

; 16x16 bitmap icon: tile, bitmap (256 chars), palette (PAL records, 0 terminated)
%macro BMP 3
    TILE_BEGIN %1
    lea     r9, [%2]
    lea     r10, [%3]
    call    bmp_px
    mov     [rdi], eax
    TILE_END
%endmacro

; noise-shaded 16x16 bitmap tile: tile, bitmap, palette, mbase, mask. One rng draw per pixel
; (m = mbase + (draw & mask)); every bitmap char, '.' included, must be in the palette.
%macro NBMP 5
    TILE_BEGIN %1
    call    rng
    and     eax, %5
    add     eax, %4
    mov     r8d, eax
    lea     r9, [%2]
    lea     r10, [%3]
    call    bmp_px
    mov     esi, eax
    mov     edx, r8d
    call    shade
    TILE_END
%endmacro

; porkchop-shaped icon: r9d = fat, r10d = meat, r11d = rim colours
%macro ICON3 5
    TILE_BEGIN %1
    mov     r9d, %3
    mov     r10d, %4
    mov     r11d, %5
    call    %2
    mov     [rdi], eax
    TILE_END
%endmacro

; rng-drawn tile: one draw per pixel, r9d = r, r8d = mbase + ((r >> shift) & mask),
; func returns the base colour in esi (r10d/r11d = variant parameters set by the caller)
%macro RNGTILE 5                        ; tile, mbase, mask, shift, func
    TILE_BEGIN %1
    call    rng
    mov     r9d, eax
    shr     eax, %4
    and     eax, %3
    add     eax, %2
    mov     r8d, eax
    call    %5
    mov     edx, r8d
    call    shade
    TILE_END
%endmacro

; jump to %1 when the pixel is on the tile border
%macro IF_BORDER 1
    test    r15d, r15d
    jz      %1
    cmp     r15d, 15
    je      %1
    test    r14d, r14d
    jz      %1
    cmp     r14d, 15
    je      %1
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
    sub     rsp, 280                    ; [rsp] 16 bytes of column depths, [rsp+16] 256 bytes of crack values (+8 pad)

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

    ; ---- 13 table_top (one draw per pixel) ----
    TILE_BEGIN 13
    DRAW_M  216, 31
    mov     esi, RGB(104,82,50)         ; border
    test    r15d, r15d
    jz      .t13_shade
    cmp     r15d, 15
    je      .t13_shade
    test    r14d, r14d
    jz      .t13_shade
    cmp     r14d, 15
    je      .t13_shade
    mov     esi, RGB(110,86,50)         ; cross seams
    cmp     r15d, 7
    je      .t13_shade
    cmp     r14d, 7
    je      .t13_shade
    mov     esi, RGB(162,130,78)
.t13_shade:
    mov     edx, r8d
    call    shade
    TILE_END

    ; ---- 14 table_side: planks rule plus top trim, saw and hammer ----
    TILE_BEGIN 14
    DRAW_M  216, 31
    mov     esi, RGB(110,86,50)
    mov     eax, r14d
    and     eax, 3
    cmp     eax, 3
    je      .t14_over
    mov     eax, r14d
    shr     eax, 2
    imul    eax, eax, 7
    add     eax, 3
    and     eax, 15
    cmp     eax, r15d
    je      .t14_over
    mov     esi, RGB(162,130,78)
.t14_over:
    cmp     r14d, 2
    ja      .t14_saw
    mov     esi, RGB(104,82,50)         ; py <= 2: trim
    jmp     .t14_shade
.t14_saw:
    lea     eax, [r15 - 2]
    cmp     eax, 4
    ja      .t14_handle                 ; px 2..6
    lea     eax, [r14 - 5]
    cmp     eax, 4
    ja      .t14_handle                 ; py 5..9
    cmp     r14d, 9
    jne     .t14_blade
    test    r15d, 1
    jz      .t14_shade                  ; py 9, px even: teeth gap keeps the planks
.t14_blade:
    mov     esi, RGB(150,150,150)
    jmp     .t14_shade
.t14_handle:
    lea     eax, [r15 - 10]
    cmp     eax, 1
    ja      .t14_head                   ; px 10..11
    lea     eax, [r14 - 7]
    cmp     eax, 6
    ja      .t14_head                   ; py 7..13
    mov     esi, RGB(78,60,36)
    jmp     .t14_shade
.t14_head:
    lea     eax, [r15 - 8]
    cmp     eax, 5
    ja      .t14_shade                  ; px 8..13
    lea     eax, [r14 - 5]
    cmp     eax, 1
    ja      .t14_shade                  ; py 5..6
    mov     esi, RGB(110,110,110)
.t14_shade:
    mov     edx, r8d
    call    shade
    TILE_END

    ; ---- crack values: 256 draws, v[py*16+px] = r & 255 (stack buffer at [rsp+16]) ----
    xor     r10d, r10d
.crk_draw:
    call    rng
    mov     [rsp + 16 + r10], al
    inc     r10d
    cmp     r10d, 256
    jb      .crk_draw

    ; ---- 16..25 crack stages: pixel is dark when v < 13*(k+1), else transparent ----
    xor     r10d, r10d                  ; k
.crk_stage:
    lea     r11d, [r10 + 1]
    imul    r11d, r11d, 13              ; threshold
    mov     rbx, r10
    shl     rbx, 6                      ; k * 16 px * 4 bytes
    lea     rbx, [r12 + rbx + 16 * 256 * 4]
    TILE_BEGIN_RBX
    mov     eax, r14d
    shl     eax, 4
    add     eax, r15d
    movzx   eax, byte [rsp + 16 + rax]
    xor     edx, edx
    cmp     eax, r11d
    jae     .crk_store
    mov     edx, RGBO(32,32,32)
.crk_store:
    mov     [rdi], edx
    TILE_END
    inc     r10d
    cmp     r10d, 10
    jb      .crk_stage

    ; ---- 32..42 item icons (no rng; opaque unshaded colours) ----
    ICON    32, icon_stick
    ICONT   33, icon_pick,   {RGBO(160,122,66)}, {RGBO(96,72,36)}
    ICONT   34, icon_axe,    {RGBO(160,122,66)}, {RGBO(96,72,36)}
    ICONT   35, icon_shovel, {RGBO(160,122,66)}, {RGBO(96,72,36)}
    ICONT   36, icon_sword,  {RGBO(160,122,66)}, {RGBO(96,72,36)}
    ICONT   37, icon_pick,   {RGBO(150,150,150)}, {RGBO(86,86,86)}
    ICONT   38, icon_axe,    {RGBO(150,150,150)}, {RGBO(86,86,86)}
    ICONT   39, icon_shovel, {RGBO(150,150,150)}, {RGBO(86,86,86)}
    ICONT   40, icon_sword,  {RGBO(150,150,150)}, {RGBO(86,86,86)}
    ICON    41, icon_apple
    ICON3   42, icon_pork, {RGBO(250,215,205)}, {RGBO(232,138,138)}, {RGBO(180,80,80)}

    ; ---- 48..53 HUD hearts and food (9x9 bitmaps, no rng) ----
    HUD     48, heart_bmp, heart_pal_full, heart_pal_empty, 9
    HUD     49, heart_bmp, heart_pal_full, heart_pal_empty, 5
    HUD     50, heart_bmp, heart_pal_full, heart_pal_empty, 0
    HUD     51, food_bmp, food_pal_full, food_pal_empty, 9
    HUD     52, food_bmp, food_pal_full, food_pal_empty, 5
    HUD     53, food_bmp, food_pal_full, food_pal_empty, 0
    HUD     54, armor_bmp, armor_pal_full, armor_pal_empty, 9
    HUD     55, armor_bmp, armor_pal_full, armor_pal_empty, 5
    HUD     56, armor_bmp, armor_pal_full, armor_pal_empty, 0

    ; ---- 57, 58 fire flames: two animation frames, transparent around the flames (no rng) ----
    BMP     57, fire0_bmp, pal_fire
    BMP     58, fire1_bmp, pal_fire

    ; ---- 64 zombie skin ----
    TILE_BEGIN 64
    NOISE_PIXEL RGB(74,128,64), 200, 55
    TILE_END

    ; ---- 65 zombie face: eyes at px {4,5,10,11}, py {6,7}; mouth py 11, px 5..10 ----
    TILE_BEGIN 65
    DRAW_M  200, 55
    mov     esi, RGB(74,128,64)
    lea     eax, [r14 - 6]
    cmp     eax, 1
    ja      .t65_mouth
    lea     eax, [r15 - 4]
    cmp     eax, 1
    jbe     .t65_eye
    lea     eax, [r15 - 10]
    cmp     eax, 1
    ja      .t65_shade
.t65_eye:
    mov     esi, RGB(24,24,24)
    jmp     .t65_shade
.t65_mouth:
    cmp     r14d, 11
    jne     .t65_shade
    lea     eax, [r15 - 5]
    cmp     eax, 5
    ja      .t65_shade
    mov     esi, RGB(40,72,34)
.t65_shade:
    mov     edx, r8d
    call    shade
    TILE_END

    ; ---- 66 zombie shirt ----
    TILE_BEGIN 66
    NOISE_PIXEL RGB(40,160,170), 200, 55
    TILE_END

    ; ---- 67 zombie pants ----
    TILE_BEGIN 67
    NOISE_PIXEL RGB(60,60,150), 200, 55
    TILE_END

    ; ---- 68 pig skin ----
    TILE_BEGIN 68
    NOISE_PIXEL RGB(240,160,160), 220, 35
    TILE_END

    ; ---- 69 pig face: eyes px {3,4,11,12} py {5,6}; snout px 5..10 py 8..11; nostrils ----
    TILE_BEGIN 69
    DRAW_M  220, 35
    mov     esi, RGB(240,160,160)
    lea     eax, [r14 - 5]
    cmp     eax, 1
    ja      .t69_snout
    lea     eax, [r15 - 3]
    cmp     eax, 1
    jbe     .t69_eye
    lea     eax, [r15 - 11]
    cmp     eax, 1
    ja      .t69_shade
.t69_eye:
    mov     esi, RGB(24,24,24)
    jmp     .t69_shade
.t69_snout:
    lea     eax, [r14 - 8]
    cmp     eax, 3
    ja      .t69_shade
    lea     eax, [r15 - 5]
    cmp     eax, 5
    ja      .t69_shade
    mov     esi, RGB(218,128,138)
    lea     eax, [r14 - 9]
    cmp     eax, 1
    ja      .t69_shade
    cmp     r15d, 6
    je      .t69_nostril
    cmp     r15d, 9
    jne     .t69_shade
.t69_nostril:
    mov     esi, RGB(110,50,60)
.t69_shade:
    mov     edx, r8d
    call    shade
    TILE_END

    ; ---- 70 player skin (the first-person arm) ----
    TILE_BEGIN TILE_PLAYER_SKIN
    NOISE_PIXEL RGB(198,150,112), 224, 31
    TILE_END

    ; ---- 26..29 ores: stone with a shared vein mask; r10d = ore colour, r11d = highlight ----
    mov     r10d, RGB(30,30,30)
    mov     r11d, RGB(60,60,60)
    RNGTILE 26, 200, 55, 0, px_ore
    mov     r10d, RGB(216,175,147)
    mov     r11d, RGB(240,210,180)
    RNGTILE 27, 200, 55, 0, px_ore
    mov     r10d, RGB(252,238,75)
    mov     r11d, RGB(255,255,180)
    RNGTILE 28, 200, 55, 0, px_ore
    mov     r10d, RGB(93,236,245)
    mov     r11d, RGB(200,255,255)
    RNGTILE 29, 200, 55, 0, px_ore

    ; ---- 30 furnace front, 31 lit ----
    xor     r10d, r10d
    RNGTILE 30, 200, 55, 0, px_furnace
    mov     r10d, 1
    RNGTILE 31, 200, 55, 0, px_furnace

    ; ---- 43 chest top, 44 chest side, 45 gravel, 46 TNT side, 47 TNT top ----
    RNGTILE 43, 216, 31, 0, px_chest_top
    RNGTILE 44, 216, 31, 0, px_chest_side
    RNGTILE 45, 216, 39, 8, px_gravel
    RNGTILE 46, 216, 31, 0, px_tnt_side
    RNGTILE 47, 216, 31, 0, px_tnt_top

    ; ---- 71 creeper skin, 72 face, 73 skeleton bone, 74 face, 75 spider body, 76 face,
    ;      77 chicken body, 78 face, 79 leg ----
    xor     r10d, r10d
    RNGTILE 71, 200, 55, 0, px_creeper
    mov     r10d, 1
    RNGTILE 72, 200, 55, 0, px_creeper
    xor     r10d, r10d
    RNGTILE 73, 200, 55, 0, px_skeleton
    mov     r10d, 1
    RNGTILE 74, 200, 55, 0, px_skeleton
    xor     r10d, r10d
    RNGTILE 75, 200, 55, 0, px_spider
    mov     r10d, 1
    RNGTILE 76, 200, 55, 0, px_spider
    xor     r10d, r10d
    RNGTILE 77, 220, 35, 0, px_chicken
    mov     r10d, 1
    RNGTILE 78, 220, 35, 0, px_chicken
    TILE_BEGIN 79
    NOISE_PIXEL RGB(240,180,40), 220, 35
    TILE_END

    ; ---- 80..118 item icons (no rng): materials, tools, bow and misc, armor (119..128: firearms below) ----
    BMP     80, coal_bmp, pal_coal
    BMP     81, ingot_bmp, pal_ingot_iron
    BMP     82, ingot_bmp, pal_ingot_gold
    BMP     83, diamond_bmp, pal_diamond
    ICONT   84, icon_pick,   {RGBO(220,220,220)}, {RGBO(130,130,130)}
    ICONT   85, icon_axe,    {RGBO(220,220,220)}, {RGBO(130,130,130)}
    ICONT   86, icon_shovel, {RGBO(220,220,220)}, {RGBO(130,130,130)}
    ICONT   87, icon_sword,  {RGBO(220,220,220)}, {RGBO(130,130,130)}
    ICONT   88, icon_pick,   {RGBO(250,220,60)}, {RGBO(180,130,10)}
    ICONT   89, icon_axe,    {RGBO(250,220,60)}, {RGBO(180,130,10)}
    ICONT   90, icon_shovel, {RGBO(250,220,60)}, {RGBO(180,130,10)}
    ICONT   91, icon_sword,  {RGBO(250,220,60)}, {RGBO(180,130,10)}
    ICONT   92, icon_pick,   {RGBO(90,230,230)}, {RGBO(25,140,140)}
    ICONT   93, icon_axe,    {RGBO(90,230,230)}, {RGBO(25,140,140)}
    ICONT   94, icon_shovel, {RGBO(90,230,230)}, {RGBO(25,140,140)}
    ICONT   95, icon_sword,  {RGBO(90,230,230)}, {RGBO(25,140,140)}
    BMP     96, bow_bmp, pal_bow
    BMP     97, arrow_bmp, pal_arrow
    BMP     98, string_bmp, pal_string
    BMP     99, gunpowder_bmp, pal_gunpowder
    BMP     100, flint_bmp, pal_flint
    BMP     101, flintsteel_bmp, pal_flintsteel
    BMP     102, rotten_bmp, pal_rotten
    ICON3   103, icon_pork, {RGBO(225,190,150)}, {RGBO(165,95,50)}, {RGBO(110,60,30)}
    BMP     104, feather_bmp, pal_feather
    BMP     105, drumstick_bmp, pal_drum_raw
    BMP     106, drumstick_bmp, pal_drum_cooked
    BMP     107, helmet_bmp, pal_armor_iron
    BMP     108, chestplate_bmp, pal_armor_iron
    BMP     109, leggings_bmp, pal_armor_iron
    BMP     110, boots_bmp, pal_armor_iron
    BMP     111, helmet_bmp, pal_armor_gold
    BMP     112, chestplate_bmp, pal_armor_gold
    BMP     113, leggings_bmp, pal_armor_gold
    BMP     114, boots_bmp, pal_armor_gold
    BMP     115, helmet_bmp, pal_armor_diamond
    BMP     116, chestplate_bmp, pal_armor_diamond
    BMP     117, leggings_bmp, pal_armor_diamond
    BMP     118, boots_bmp, pal_armor_diamond
    ; ---- 119..128 firearm icons: pistol, musket, shotgun, kalashnikov, rocket launcher,
    ;      then the pistol round, musket ball, shotgun shell, rifle round and rocket ----
    BMP     119, pistol_bmp, pal_pistol
    BMP     120, musket_bmp, pal_musket
    BMP     121, shotgun_bmp, pal_shotgun
    BMP     122, kalash_bmp, pal_kalash
    BMP     123, launcher_bmp, pal_launcher
    BMP     124, round_pistol_bmp, pal_brass
    BMP     125, musket_ball_bmp, pal_ball
    BMP     126, shell_bmp, pal_shell
    BMP     127, round_rifle_bmp, pal_brass
    BMP     128, rocket_bmp, pal_rocket

    ; ---- 59, 60 .. 179: RPG art (all drawn after every older rng draw, so tiles 0..128 and the
    ;      font are unchanged) ----
    ; ---- 59, 60 stone bricks, mossy: bitmaps over a light rng noise (after every older rng draw) ----
    NBMP    59, brick_bmp, pal_brick, 232, 23
    NBMP    60, mossy_bmp, pal_mossy, 232, 23
    ; ---- 129..138 weapon and consumable icons: staff, archmage staff, iron dagger, diamond dagger,
    ; Shadow Fang, King's Blade, Celestial Bow, health potion, mana potion, gold coin ----
    BMP     129, staff_bmp, pal_staff
    BMP     130, archstaff_bmp, pal_archstaff
    BMP     131, dagger_bmp, pal_dagger_iron
    BMP     132, dagger_bmp, pal_dagger_diamond
    BMP     133, fang_bmp, pal_fang
    BMP     134, kings_bmp, pal_kings
    BMP     135, celestial_bmp, pal_celestial
    BMP     136, potion_bmp, pal_potion_red
    BMP     137, potion_bmp, pal_potion_blue
    BMP     138, coin_bmp, pal_coin
    ; ---- 139..150 ability icons: Warrior Charge/War Cry/Whirlwind, Mage Fireball/Blink/Meteor Storm,
    ; Archer Volley/Explosive Arrow/Arrow Rain, Rogue Shadowstep/Smoke Bomb/Blade Dance ----
    BMP     139, charge_bmp, pal_charge
    BMP     140, warcry_bmp, pal_warcry
    BMP     141, whirl_bmp, pal_whirl
    BMP     142, fireball_bmp, pal_fireball
    BMP     143, blink_bmp, pal_blink
    BMP     144, meteor_bmp, pal_meteor
    BMP     145, volley_bmp, pal_volley
    BMP     146, explarrow_bmp, pal_explarrow
    BMP     147, arrowrain_bmp, pal_arrowrain
    BMP     148, shadowstep_bmp, pal_shadowstep
    BMP     149, smoke_bmp, pal_smoke
    BMP     150, bladedance_bmp, pal_bladedance
    ; ---- 151..154 class emblems: Warrior, Mage, Archer, Rogue ----
    BMP     151, emb_warrior_bmp, pal_emb_warrior
    BMP     152, emb_mage_bmp, pal_emb_mage
    BMP     153, emb_archer_bmp, pal_emb_archer
    BMP     154, emb_rogue_bmp, pal_emb_rogue
    ; ---- 155..172 stat icons, one per stat id (health, melee, ranged, spell, crit chance, crit dmg, mana,
    ; mana regen, stamina, stamina regen, armor, move speed, backstab, parry, lifesteal, cooldown,
    ; arrow save, dodge cost) ----
    BMP     155, st_health_bmp, pal_st_health
    BMP     156, st_melee_bmp, pal_st_melee
    BMP     157, st_ranged_bmp, pal_st_ranged
    BMP     158, st_spell_bmp, pal_st_spell
    BMP     159, st_critchance_bmp, pal_st_critchance
    BMP     160, st_critdmg_bmp, pal_st_critdmg
    BMP     161, st_mana_bmp, pal_st_mana
    BMP     162, st_manaregen_bmp, pal_st_manaregen
    BMP     163, st_stamina_bmp, pal_st_stamina
    BMP     164, st_staminaregen_bmp, pal_st_staminaregen
    BMP     165, st_armor_bmp, pal_st_armor
    BMP     166, st_speed_bmp, pal_st_speed
    BMP     167, st_backstab_bmp, pal_st_backstab
    BMP     168, st_parry_bmp, pal_st_parry
    BMP     169, st_lifesteal_bmp, pal_st_lifesteal
    BMP     170, st_cooldown_bmp, pal_st_cooldown
    BMP     171, st_arrowsave_bmp, pal_st_arrowsave
    BMP     172, st_wind_bmp, pal_st_wind
    ; ---- 173..179 villager and boss textures (noise-shaded; 174..179 carry a bitmap overlay) ----
    TILE_BEGIN 173
    NOISE_PIXEL RGB(225,180,140), 224, 31
    TILE_END
    NBMP    174, npc_face_bmp, pal_npc_face, 224, 31
    NBMP    175, npc_merchant_bmp, pal_npc_merchant, 224, 31
    NBMP    176, npc_elder_bmp, pal_npc_elder, 224, 31
    NBMP    177, npc_bossrobe_bmp, pal_npc_bossrobe, 224, 31
    NBMP    178, npc_bossface_bmp, pal_npc_bossface, 224, 31
    NBMP    179, npc_crown_bmp, pal_npc_crown, 224, 31

    ; ---- font (no rng; always last): glyph c-32 at ((c-32)&15)*8, FONT_Y + ((c-32)>>4)*8
    xor     r9d, r9d                    ; glyph index 0..95
.font_glyph:
    xor     r14d, r14d                  ; row y
.font_row:
    mov     eax, r9d
    lea     eax, [r14 + rax * 8]
    lea     rcx, [font8x8]
    movzx   r10d, byte [rcx + rax]      ; row bits, bit 0 = leftmost
    xor     r15d, r15d                  ; column x
.font_col:
    bt      r10d, r15d
    jnc     .font_next
    mov     eax, r9d                    ; atlas y = FONT_Y + (g>>4)*8 + y
    shr     eax, 4
    lea     eax, [r14 + rax * 8 + FONT_Y]
    shl     eax, 8
    mov     ecx, r9d                    ; atlas x = (g&15)*8 + x
    and     ecx, 15
    lea     ecx, [r15 + rcx * 8]
    add     eax, ecx
    mov     dword [r12 + rax * 4], 0xFFFFFFFF
.font_next:
    inc     r15d
    cmp     r15d, 8
    jb      .font_col
    inc     r14d
    cmp     r14d, 8
    jb      .font_row
    inc     r9d
    cmp     r9d, 96
    jb      .font_glyph

    add     rsp, 280
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---------------------------------------------------------------------------
; Per-pixel icon routines. In: r15d = px, r14d = py (r10d/r11d = m/M colours for
; the tool heads). Out: eax = packed RGBA (0 = transparent). They never touch
; rdi, rbx, r12-r15, so TILE_BEGIN's loop survives the call.
; ---------------------------------------------------------------------------

; stick: h on px+py==15 (3..12), H on px+py==16 (4..13)
icon_stick:
    lea     ecx, [r15 + r14]
    cmp     ecx, 15
    jne     .shadow
    lea     edx, [r15 - 3]
    cmp     edx, 9
    ja      .none
    mov     eax, RGBO(137,103,39)
    ret
.shadow:
    cmp     ecx, 16
    jne     .none
    lea     edx, [r15 - 4]
    cmp     edx, 9
    ja      .none
    mov     eax, RGBO(84,62,22)
    ret
.none:
    xor     eax, eax
    ret

; tool handle: h on px+py==15 (2..9), H on px+py==16 (3..10)
tool_handle:
    lea     ecx, [r15 + r14]
    cmp     ecx, 15
    jne     .shadow
    lea     edx, [r15 - 2]
    cmp     edx, 7
    ja      .none
    mov     eax, RGBO(137,103,39)
    ret
.shadow:
    cmp     ecx, 16
    jne     .none
    lea     edx, [r15 - 3]
    cmp     edx, 7
    ja      .none
    mov     eax, RGBO(84,62,22)
    ret
.none:
    xor     eax, eax
    ret

; pickaxe head: arc 9.5 <= r < 12.0 around (2.5, 13.5) within the NE quadrant
icon_pick:
    cvtsi2ss xmm0, r15d
    subss   xmm0, [f2_5]                ; dx
    movss   xmm1, [f13_5]
    cvtsi2ss xmm2, r14d
    subss   xmm1, xmm2                  ; dy
    movaps  xmm2, xmm0
    addss   xmm2, xmm1                  ; dx + dy
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    addss   xmm0, xmm1                  ; r^2
    comiss  xmm0, [f90_25]
    jb      tool_handle
    comiss  xmm0, [f144_0]
    jae     tool_handle
    movaps  xmm3, xmm0
    sqrtss  xmm0, xmm0                  ; r
    mulss   xmm0, [f_sqrt2]
    mulss   xmm0, [f0_8]                ; 0.8 * sqrt2 * r  (c >= 0.8)
    comiss  xmm2, xmm0
    jb      tool_handle
    mov     eax, r10d
    comiss  xmm3, [f121_0]
    jb      .done                       ; r < 11.0 -> m
    mov     eax, r11d
.done:
    ret

; axe blade: 5<=px<=10, 1<=py<=6, 8<=px+py<=14; M on its px==5, py==1, px+py==8 edges
icon_axe:
    lea     eax, [r15 - 5]
    cmp     eax, 5
    ja      tool_handle
    lea     eax, [r14 - 1]
    cmp     eax, 5
    ja      tool_handle
    lea     ecx, [r15 + r14]
    lea     eax, [rcx - 8]
    cmp     eax, 6
    ja      tool_handle
    mov     eax, r11d
    cmp     r15d, 5
    je      .done
    cmp     r14d, 1
    je      .done
    cmp     ecx, 8
    je      .done
    mov     eax, r10d
.done:
    ret

; shovel blade: diamond |px-11|+|py-4| <= 2 is m, == 3 is M
icon_shovel:
    mov     eax, r15d
    sub     eax, 11
    cdq
    xor     eax, edx
    sub     eax, edx
    mov     ecx, eax
    mov     eax, r14d
    sub     eax, 4
    cdq
    xor     eax, edx
    sub     eax, edx
    add     eax, ecx
    cmp     eax, 2
    jbe     .m
    cmp     eax, 3
    je      .M
    jmp     tool_handle
.m:
    mov     eax, r10d
    ret
.M:
    mov     eax, r11d
    ret

; sword: blade m on px+py==15, M on 14/16 (px 6..13) and (14,1); guard H; grip h; pommel H
icon_sword:
    lea     ecx, [r15 + r14]
    lea     edx, [r15 - 6]
    cmp     edx, 7
    ja      .notblade
    cmp     ecx, 15
    je      .m
    cmp     ecx, 14
    je      .M
    cmp     ecx, 16
    je      .M
.notblade:
    cmp     r15d, 14
    jne     .guard
    cmp     r14d, 1
    je      .M
.guard:
    mov     eax, r15d
    sub     eax, r14d
    cmp     eax, -5
    jne     .grip
    lea     edx, [r15 - 3]
    cmp     edx, 4
    ja      .grip
    mov     eax, RGBO(84,62,22)
    ret
.grip:
    cmp     ecx, 15
    jne     .pommel
    lea     edx, [r15 - 2]
    cmp     edx, 2
    ja      .pommel
    mov     eax, RGBO(137,103,39)
    ret
.pommel:
    xor     eax, eax
    cmp     r15d, 1
    jne     .done
    cmp     r14d, 14
    jne     .done
    mov     eax, RGBO(84,62,22)
.done:
    ret
.m:
    mov     eax, r10d
    ret
.M:
    mov     eax, r11d
    ret

; apple: specials (highlight, stem, leaf) over a disc around (7.5, 8.5)
icon_apple:
    lea     rsi, [apple_pts]
.pt:
    movzx   eax, byte [rsi]
    cmp     eax, 0xFF
    je      .body
    cmp     eax, r15d
    jne     .next
    movzx   eax, byte [rsi + 1]
    cmp     eax, r14d
    jne     .next
    mov     eax, [rsi + 4]
    ret
.next:
    add     rsi, 8
    jmp     .pt
.body:
    cvtsi2ss xmm0, r15d
    subss   xmm0, [f7_5]
    mulss   xmm0, xmm0
    cvtsi2ss xmm1, r14d
    subss   xmm1, [f8_5]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1                  ; d^2
    xor     eax, eax
    comiss  xmm0, [f30_25]
    ja      .done                       ; d > 5.5
    mov     eax, RGBO(128,12,12)
    comiss  xmm0, [f21_16]
    ja      .done                       ; 4.6 < d <= 5.5
    mov     eax, RGBO(196,24,24)
.done:
    ret

; porkchop: ellipse v = ((px-7.5)/6.5)^2 + ((py-8)/4.5)^2 <= 1
icon_pork:
    cvtsi2ss xmm0, r15d
    subss   xmm0, [f7_5]
    divss   xmm0, [f6_5]
    mulss   xmm0, xmm0
    cvtsi2ss xmm1, r14d
    subss   xmm1, [f8_0]
    divss   xmm1, [f4_5]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1                  ; v
    xor     eax, eax
    comiss  xmm0, [f1_0]
    ja      .done                       ; outside
    mov     eax, r11d                   ; rim
    comiss  xmm0, [f0_72]
    ja      .done                       ; rim
    mov     eax, r10d                   ; meat
    comiss  xmm0, [f0_45]
    jbe     .done                       ; core
    cmp     r15d, 7
    jg      .done
    mov     eax, r9d                    ; fat highlight (left part of the mid ring)
.done:
    ret

; HUD 9x9 bitmap pixel. In: r9 = bitmap (81 chars), r10 = full palette, r11 = empty
; palette, r8d = split column (px < split uses the full palette). Out: eax.
hud_px:
    xor     eax, eax
    cmp     r15d, 8
    ja      .done
    cmp     r14d, 8
    ja      .done
    lea     eax, [r14 + r14 * 8]
    add     eax, r15d
    movzx   ecx, byte [r9 + rax]
    mov     rdx, r10
    cmp     r15d, r8d
    jb      .search
    mov     rdx, r11
.search:
    xor     eax, eax
.entry:
    movzx   esi, byte [rdx]
    test    esi, esi
    jz      .done                       ; not in palette -> transparent
    cmp     esi, ecx
    je      .found
    add     rdx, 8
    jmp     .entry
.found:
    mov     eax, [rdx + 4]
.done:
    ret

; 16x16 bitmap pixel. In: r9 = bitmap (256 chars), r10 = palette (PAL records). A char
; that is not in the palette is transparent. Out: eax.
bmp_px:
    mov     eax, r14d
    shl     eax, 4
    add     eax, r15d
    movzx   ecx, byte [r9 + rax]
    mov     rdx, r10
.entry:
    movzx   esi, byte [rdx]
    test    esi, esi
    jz      .none
    cmp     esi, ecx
    je      .found
    add     rdx, 8
    jmp     .entry
.found:
    mov     eax, [rdx + 4]
    ret
.none:
    xor     eax, eax
    ret

; ---------------------------------------------------------------------------
; Base-colour routines for the rng tiles. In: r15d = px, r14d = py, r9d = the pixel's
; rng draw, r10d (and r11d for the ores) = variant parameters. Out: esi = base colour
; (before the m multiplier). They clobber eax, ecx, edx only.
; ---------------------------------------------------------------------------

; ores: stone, ore colour r10d on 'o', highlight r11d on 'O' of ore_mask
px_ore:
    lea     rax, [ore_mask]
    mov     ecx, r14d
    shl     ecx, 4
    add     ecx, r15d
    movzx   ecx, byte [rax + rcx]
    mov     esi, RGB(128,128,128)
    cmp     ecx, 'o'
    cmove   esi, r10d
    cmp     ecx, 'O'
    cmove   esi, r11d
    ret

; furnace front (r10d = 1: lit)
px_furnace:
    mov     esi, RGB(80,80,80)
    IF_BORDER .done
    mov     esi, RGB(60,60,60)
    lea     eax, [r15 - 3]
    cmp     eax, 9
    ja      .open
    lea     eax, [r14 - 3]
    cmp     eax, 1
    jbe     .done                       ; top slot 3<=px<=12, 3<=py<=4
.open:
    mov     esi, RGB(120,120,120)
    lea     eax, [r15 - 4]
    cmp     eax, 7
    ja      .done
    lea     eax, [r14 - 8]
    cmp     eax, 4
    ja      .done                       ; opening 4<=px<=11, 8<=py<=12
    mov     esi, RGB(24,24,24)
    test    r10d, r10d
    jz      .done
    mov     esi, RGB(255,170,40)
    cmp     r14d, 11
    jae     .done
    mov     esi, RGB(250,110,20)
    cmp     r14d, 10
    je      .done
    mov     esi, RGB(190,50,10)
.done:
    ret

px_chest_top:
    mov     esi, RGB(92,64,32)
    IF_BORDER .done
    mov     esi, RGB(162,130,78)
.done:
    ret

px_chest_side:
    mov     esi, RGB(162,130,78)
    IF_BORDER .dark
    lea     eax, [r14 - 5]
    cmp     eax, 1
    ja      .latch
.dark:
    mov     esi, RGB(92,64,32)          ; border and the lid seam py 5..6
.latch:
    lea     eax, [r15 - 7]
    cmp     eax, 1
    ja      .done
    lea     eax, [r14 - 4]
    cmp     eax, 4
    ja      .done
    mov     esi, RGB(210,210,210)       ; latch 7..8 x 4..8
.done:
    ret

; gravel: colour by r & 3
px_gravel:
    mov     eax, r9d
    and     eax, 3
    lea     rcx, [gravel_cols]
    mov     esi, [rcx + rax * 4]
    ret

; TNT side: red bands py <= 3 / >= 12 (dark every px%4 == 3), white label with "TNT"
px_tnt_side:
    cmp     r14d, 3
    jbe     .band
    cmp     r14d, 12
    jae     .band
    mov     esi, RGB(230,230,230)
    lea     eax, [r14 - 6]
    cmp     eax, 4
    ja      .done
    shl     eax, 4
    add     eax, r15d
    lea     rcx, [tnt_mask]
    cmp     byte [rcx + rax], '#'
    jne     .done
    mov     esi, RGB(30,30,30)
    ret
.band:
    mov     esi, RGB(200,40,30)
    mov     eax, r15d
    and     eax, 3
    cmp     eax, 3
    jne     .done
    mov     esi, RGB(150,25,20)
.done:
    ret

px_tnt_top:
    mov     esi, RGB(200,40,30)
    lea     eax, [r15 - 6]
    cmp     eax, 3
    ja      .done
    lea     eax, [r14 - 6]
    cmp     eax, 3
    ja      .done
    mov     esi, RGB(230,230,230)
    lea     eax, [r15 - 7]
    cmp     eax, 1
    ja      .done
    lea     eax, [r14 - 7]
    cmp     eax, 1
    ja      .done
    mov     esi, RGB(40,40,40)
.done:
    ret

; creeper skin (r10d = 1: face)
px_creeper:
    mov     esi, RGB(80,180,70)
    mov     eax, r9d
    shr     eax, 8
    and     eax, 7
    jnz     .light
    mov     esi, RGB(50,120,45)
.light:
    mov     eax, r9d
    shr     eax, 11
    and     eax, 7
    cmp     eax, 1
    jne     .face
    mov     esi, RGB(140,220,120)
.face:
    test    r10d, r10d
    jz      .done
    lea     eax, [r14 - 4]
    cmp     eax, 2
    ja      .mouth
    lea     eax, [r15 - 3]
    cmp     eax, 2
    jbe     .black                      ; eyes 3..5, 10..12 x 4..6
    lea     eax, [r15 - 10]
    cmp     eax, 2
    jbe     .black
.mouth:
    lea     eax, [r15 - 6]
    cmp     eax, 3
    ja      .sides
    lea     eax, [r14 - 7]
    cmp     eax, 3
    jbe     .black                      ; mouth 6..9 x 7..10
.sides:
    lea     eax, [r14 - 10]
    cmp     eax, 2
    ja      .done
    lea     eax, [r15 - 5]
    cmp     eax, 5
    ja      .done
    cmp     eax, 1
    jbe     .black                      ; px 5, 6
    cmp     eax, 4
    jb      .done                       ; px 7, 8
.black:
    mov     esi, RGB(20,20,20)          ; px 9, 10 fall through
.done:
    ret

; skeleton bone (r10d = 1: face)
px_skeleton:
    mov     esi, RGB(200,200,200)
    test    r10d, r10d
    jz      .done
    lea     eax, [r14 - 5]
    cmp     eax, 2
    ja      .nose
    lea     eax, [r15 - 3]
    cmp     eax, 3
    jbe     .socket                     ; sockets 3..6, 9..12 x 5..7
    lea     eax, [r15 - 9]
    cmp     eax, 3
    ja      .nose
.socket:
    mov     esi, RGB(40,40,40)
    ret
.nose:
    cmp     r14d, 9
    jne     .teeth
    lea     eax, [r15 - 7]
    cmp     eax, 1
    ja      .teeth
    mov     esi, RGB(60,60,60)
    ret
.teeth:
    cmp     r14d, 12
    jne     .done
    lea     eax, [r15 - 3]
    cmp     eax, 9
    ja      .done
    test    r15d, 1
    jnz     .done
    mov     esi, RGB(60,60,60)
.done:
    ret

; spider body (r10d = 1: face, with the spider_pts specials)
px_spider:
    mov     esi, RGB(52,44,40)
    mov     eax, r9d
    shr     eax, 8
    and     eax, 7
    jnz     .face
    mov     esi, RGB(80,66,58)
.face:
    test    r10d, r10d
    jz      .done
    lea     rdx, [spider_pts]
.pt:
    movzx   eax, byte [rdx]
    cmp     eax, 0xFF
    je      .done
    cmp     eax, r15d
    jne     .next
    movzx   eax, byte [rdx + 1]
    cmp     eax, r14d
    jne     .next
    mov     esi, [rdx + 4]
    ret
.next:
    add     rdx, 8
    jmp     .pt
.done:
    ret

; chicken body (r10d = 1: face)
px_chicken:
    mov     esi, RGB(240,240,240)
    test    r10d, r10d
    jz      .done
    cmp     r14d, 5
    jne     .beak
    cmp     r15d, 3
    je      .eye
    cmp     r15d, 12
    jne     .beak
.eye:
    mov     esi, RGB(24,24,24)
    ret
.beak:
    lea     eax, [r15 - 6]
    cmp     eax, 3
    ja      .wattle
    lea     eax, [r14 - 7]
    cmp     eax, 2
    ja      .wattle
    mov     esi, RGB(240,180,40)        ; beak 6..9 x 7..9
    ret
.wattle:
    lea     eax, [r15 - 7]
    cmp     eax, 1
    ja      .done
    lea     eax, [r14 - 10]
    cmp     eax, 2
    ja      .done
    mov     esi, RGB(200,30,30)         ; wattle 7..8 x 10..12
.done:
    ret

section .rodata
f2_5:       dd 2.5
f13_5:      dd 13.5
f90_25:     dd 90.25
f144_0:     dd 144.0
f121_0:     dd 121.0
f_sqrt2:    dd 1.41421356
f0_8:       dd 0.80
f7_5:       dd 7.5
f8_5:       dd 8.5
f8_0:       dd 8.0
f6_5:       dd 6.5
f4_5:       dd 4.5
f30_25:     dd 30.25
f21_16:     dd 21.16
f1_0:       dd 1.0
f0_72:      dd 0.72
f0_45:      dd 0.45

; apple specials: db px, py, 0, 0 ; dd colour; px == 0xFF ends the list
%macro PT 3+
    db %1, %2, 0, 0
    dd %3
%endmacro
apple_pts:
    PT 5, 6, RGBO(240,120,120)
    PT 5, 7, RGBO(240,120,120)
    PT 6, 6, RGBO(240,120,120)
    PT 8, 2, RGBO(90,60,20)
    PT 8, 3, RGBO(90,60,20)
    PT 9, 2, RGBO(60,140,40)
    PT 10, 2, RGBO(60,140,40)
    PT 10, 1, RGBO(60,140,40)
    PT 0xFF, 0, 0

; HUD palettes: db char, 0, 0, 0 ; dd colour; char 0 ends
%macro PAL 4
    db %1, 0, 0, 0
    dd RGBO(%2, %3, %4)
%endmacro
heart_pal_full:
    PAL 'K', 24, 24, 24
    PAL 'r', 214, 28, 28
    PAL 'w', 255, 150, 150
    dq 0
heart_pal_empty:
    PAL 'K', 24, 24, 24
    PAL 'r', 52, 20, 20
    PAL 'w', 52, 20, 20
    dq 0
food_pal_full:
    PAL 'K', 40, 26, 14
    PAL 'm', 186, 108, 48
    PAL 'w', 226, 168, 108
    PAL 'b', 236, 232, 220
    dq 0
food_pal_empty:
    PAL 'K', 40, 26, 14
    PAL 'm', 58, 40, 28
    PAL 'w', 58, 40, 28
    PAL 'b', 96, 96, 96
    dq 0

heart_bmp:
    db ".KKK.KKK."
    db "KrrrKrrrK"
    db "KrwrrrrrK"
    db "KrrrrrrrK"
    db ".KrrrrrK."
    db "..KrrrK.."
    db "...KrK..."
    db "....K...."
    db "........."
food_bmp:
    db "....KKK.."
    db "...KmmmK."
    db "..KmmwmmK"
    db "..KmmmmmK"
    db "...KmmmK."
    db "..KbKKK.."
    db ".KbK....."
    db "KbbK....."
    db ".KK......"

armor_pal_full:
    PAL 'K', 30, 30, 30
    PAL 'm', 190, 190, 200
    PAL 'L', 255, 255, 255
    dq 0
armor_pal_empty:
    PAL 'K', 30, 30, 30
    PAL 'm', 60, 60, 60
    PAL 'L', 60, 60, 60
    dq 0
armor_bmp:
    db ".KK...KK."
    db "KmLK.KmmK"
    db "KmmmKmmmK"
    db ".KmmmmmK."
    db ".KmmmmmK."
    db ".KmmmmmK."
    db ".KKKKKKK."
    db "........."
    db "........."

; ---- 16x16 icon palettes ----
pal_coal:
    PAL 'K', 24, 24, 24
    PAL 'k', 48, 48, 52
    PAL 'g', 96, 96, 100
    dq 0
pal_ingot_iron:
    PAL 'L', 245, 245, 245
    PAL 'm', 206, 206, 206
    PAL 'D', 120, 120, 120
    dq 0
pal_ingot_gold:
    PAL 'L', 255, 250, 160
    PAL 'm', 250, 215, 60
    PAL 'D', 175, 125, 10
    dq 0
pal_diamond:
    PAL 'K', 18, 90, 90
    PAL 'm', 90, 230, 230
    PAL 'L', 220, 255, 255
    dq 0
pal_bow:
    PAL 'w', 150, 112, 50
    PAL 'W', 84, 62, 22
    PAL 's', 230, 230, 230
    dq 0
pal_arrow:
    PAL 'h', 137, 103, 39
    PAL 'G', 220, 220, 220
    PAL 'g', 120, 120, 120
    PAL 'f', 245, 245, 245
    dq 0
pal_string:
    PAL 's', 235, 235, 235
    dq 0
pal_fire:
    PAL 'Y', 255, 230, 90
    PAL 'O', 250, 140, 30
    PAL 'R', 200, 50, 20
    dq 0
pal_gunpowder:
    PAL 'k', 60, 60, 60
    PAL 'g', 110, 110, 110
    PAL 'l', 160, 160, 160
    dq 0
pal_flint:
    PAL 'K', 20, 20, 22
    PAL 'd', 60, 60, 66
    PAL 'l', 120, 120, 130
    dq 0
pal_flintsteel:
    PAL 'D', 110, 110, 110
    PAL 'L', 210, 210, 210
    PAL 'K', 20, 20, 22
    PAL 'd', 60, 60, 66
    PAL 'l', 120, 120, 130
    dq 0
pal_rotten:
    PAL 'd', 90, 50, 30
    PAL 'm', 150, 90, 55
    PAL 'g', 100, 130, 60
    dq 0
pal_feather:
    PAL 'W', 180, 180, 180
    PAL 'w', 245, 245, 245
    PAL 'q', 150, 150, 150
    dq 0
pal_drum_raw:
    PAL 'm', 236, 170, 160
    PAL 'w', 255, 215, 205
    PAL 'b', 240, 236, 224
    dq 0
pal_drum_cooked:
    PAL 'm', 176, 98, 40
    PAL 'w', 212, 140, 72
    PAL 'b', 240, 236, 224
    dq 0
pal_armor_iron:
    PAL 'D', 90, 90, 90
    PAL 'm', 200, 200, 205
    PAL 'L', 245, 245, 245
    dq 0
pal_armor_gold:
    PAL 'D', 160, 110, 10
    PAL 'm', 245, 205, 50
    PAL 'L', 255, 245, 150
    dq 0
pal_armor_diamond:
    PAL 'D', 20, 100, 100
    PAL 'm', 90, 225, 225
    PAL 'L', 215, 255, 255
    dq 0

gravel_cols:
    dd RGB(118,110,106), RGB(146,138,134), RGB(92,88,86), RGB(166,156,146)

; spider face specials: db px, py, 0, 0 ; dd colour; px == 0xFF ends the list
%macro SPT 3
    db %1, %2, 0, 0
    dd %3
%endmacro
spider_pts:
    SPT 4, 6, RGB(200,30,30)
    SPT 5, 6, RGB(200,30,30)
    SPT 10, 6, RGB(200,30,30)
    SPT 11, 6, RGB(200,30,30)
    SPT 6, 4, RGB(200,30,30)
    SPT 9, 4, RGB(200,30,30)
    SPT 3, 8, RGB(200,30,30)
    SPT 12, 8, RGB(200,30,30)
    SPT 6, 12, RGB(30,24,22)
    SPT 9, 12, RGB(30,24,22)
    SPT 6, 13, RGB(30,24,22)
    SPT 9, 13, RGB(30,24,22)
    SPT 0xFF, 0, 0

ore_mask:
    db "................"
    db "..oo........O..."
    db ".oOo.......ooo.."
    db "..o.........o..."
    db "......oo........"
    db ".....oOoo......."
    db "......oo........"
    db ".............o.."
    db "..o.........oOo."
    db ".ooo.........o.."
    db "..O............."
    db ".......oo......."
    db "......oOoo....o."
    db ".......o.....oo."
    db "................"
    db "................"

; TNT label rows (py 6..10)
tnt_mask:
    db "..###.#..#.###.."
    db "...#..##.#..#..."
    db "...#..#.##..#..."
    db "...#..#..#..#..."
    db "...#..#..#..#..."

coal_bmp:
    db "................"
    db "................"
    db "......KKKK......"
    db "....KKkkkkKK...."
    db "...KkkggkkkkK..."
    db "...KkgkkkkkkK..."
    db "..KkkkkkkgkkkK.."
    db "..KkkkkkkkkkkK.."
    db "..KkkgkkkkkkkK.."
    db "..KkkkkkkkkgkkK."
    db "...KkkkkkkkkK..."
    db "...KKkkgkkkKK..."
    db ".....KKkkKKK...."
    db ".......KKK......"
    db "................"
    db "................"
ingot_bmp:
    db "................"
    db "................"
    db "................"
    db "................"
    db "................"
    db "......LLLLLLL..."
    db ".....LmmmmmmLD.."
    db "....LmmmmmmmLDD."
    db "...LLLLLLLLLDDD."
    db "...LmmmmmmmmLDD."
    db "...LmmmmmmmmLD.."
    db "...DDDDDDDDDDD.."
    db "................"
    db "................"
    db "................"
    db "................"
diamond_bmp:
    db "................"
    db "................"
    db ".....KKKKKK....."
    db "....KLLmmmmK...."
    db "...KLLmmmmmmK..."
    db "..KmmmmmmmmmmK.."
    db "..KKKKKKKKKKKK.."
    db "...KmmmmmmmmK..."
    db "....KmmmmmmK...."
    db ".....KmmmmK....."
    db "......KmmK......"
    db ".......KK......."
    db "................"
    db "................"
    db "................"
    db "................"
bow_bmp:
    db "................"
    db "............wW.."
    db "............wW.."
    db "...........swW.."
    db "..........swwW.."
    db ".........s.wWW.."
    db "........s..wW..."
    db ".......s..wwW..."
    db "......s..wwWW..."
    db ".....s..wwWW...."
    db "....s..wwWW....."
    db "...swwwwWW......"
    db ".wwwwWWWW......."
    db ".WWWWW.........."
    db "................"
    db "................"
arrow_bmp:
    db "................"
    db "............GGG."
    db "...........gGGG."
    db "..........hgGG.."
    db ".........h..g..."
    db "........h......."
    db ".......h........"
    db "......h........."
    db ".....h.........."
    db "....h..........."
    db "...h............"
    db ".ffh............"
    db ".fff............"
    db "..ff............"
    db "................"
    db "................"
fire0_bmp:
    db "................"
    db "......R........."
    db "......R....R...."
    db ".....RO....R...."
    db ".R...RO...RO.R.."
    db ".R..RROR..RO.RR."
    db ".RR.ROOR.RROORO."
    db ".RO.ROYOR.ROOOR."
    db ".ROR.ROYOR.ROYOR"
    db "RROORROYYORROYOR"
    db "ROOOROOYYOOROYOR"
    db "ROYOROYYYYOOOYOR"
    db "ROYYOOYYYYYOYYOR"
    db "ROYYYOYYYYYYYYOR"
    db ".ROYYYYYYYYYYOR."
    db "..RROOYYYYOORR.."
fire1_bmp:
    db "................"
    db ".........R......"
    db ".........R...R.."
    db "....R...RO...R.."
    db "....R...RO..RO.."
    db "...RO..RROR.RO.."
    db "..RRO..ROOR.ROR."
    db "..ROOR.ROYOR.ROR"
    db ".RROYOR.ROYOR.RR"
    db "RROOYOROROYYOORR"
    db "ROOYYOOOOOYYYOOR"
    db "ROYYYOOYYYYYYOOR"
    db "ROYYYYYYYYYYYYOR"
    db "ROYYYYYYYYYYYYOR"
    db ".ROYYYYYYYYYYOR."
    db "..RROOYYYYOORR.."
string_bmp:
    db "................"
    db "................"
    db "............ss.."
    db "...........s..s."
    db "..........s....."
    db ".........s......"
    db "........s......."
    db ".......s........"
    db "......s........."
    db ".....s.........."
    db "....s..........."
    db "...s............"
    db "..s............."
    db "..s............."
    db "...ss..........."
    db "................"
gunpowder_bmp:
    db "................"
    db "................"
    db "................"
    db "................"
    db "................"
    db "................"
    db "........g......."
    db "......gkkgl....."
    db ".....kkgkklk...."
    db "....kglkkgkkk..."
    db "...kkkkglkkgkk.."
    db "..kglkkkkkklkkk."
    db "..kkkkglkkkkgkk."
    db "...kkkkkkgkkkk.."
    db "................"
    db "................"
flint_bmp:
    db "................"
    db "................"
    db "................"
    db ".......KK......."
    db "......KllK......"
    db ".....KlddK......"
    db "....KlddddK....."
    db "....KdddddK....."
    db "...KlddddddK...."
    db "...KddddddddK..."
    db "...KddddddddK..."
    db "....KdddddddK..."
    db ".....KddddKK...."
    db "......KKKK......"
    db "................"
    db "................"
flintsteel_bmp:
    db "................"
    db "................"
    db "...DDDDD........"
    db "..DLLLLLD......."
    db "..DL...LD......."
    db "..DL...LD......."
    db "..DLLLLLD......."
    db "...DDDLD........"
    db "......LD........"
    db "......LD..KK...."
    db ".......D.KllK..."
    db "........KlddK..."
    db ".......KddddK..."
    db ".......KdddK...."
    db "........KKK....."
    db "................"
rotten_bmp:
    db "................"
    db "................"
    db "................"
    db "......dd........"
    db "....ddmmd......."
    db "...dmmgmmd......"
    db "...dmmmmmmdd...."
    db "..dmgmmmmmmmd..."
    db "..dmmmmmgmmmmd.."
    db "...dmmmmmmmgmd.."
    db "....ddmmgmmmmd.."
    db "......ddmmmmd..."
    db "........dddd...."
    db "................"
    db "................"
    db "................"
feather_bmp:
    db "................"
    db "............WW.."
    db "..........WWww.."
    db ".........Wwwww.."
    db "........Wwwww..."
    db ".......Wwwwq...."
    db "......Wwwwq....."
    db ".....Wwwwq......"
    db "....Wwwwq......."
    db "....wwwq........"
    db "....wwq........."
    db "....wq.........."
    db "...q............"
    db "..q............."
    db "................"
    db "................"
drumstick_bmp:
    db "................"
    db "................"
    db "................"
    db "........mmmm...."
    db ".......mwmmmm..."
    db "......mwmmmmmm.."
    db "......mmmmmmmm.."
    db "......mmmmmmmm.."
    db ".......mmmmmmm.."
    db "......bmmmmmm..."
    db ".....bbbmmmm...."
    db "....bb.........."
    db "...bb..........."
    db "..bbb..........."
    db "..bb............"
    db "................"
helmet_bmp:
    db "................"
    db "................"
    db "................"
    db "....DDDDDDDD...."
    db "...DLLLmmmmmD..."
    db "..DLmmmmmmmmmD.."
    db "..DmmmmmmmmmmD.."
    db "..DmmDDDDDDmmD.."
    db "..DmmD....DmmD.."
    db "..DmmD....DmmD.."
    db "..DDDD....DDDD.."
    db "................"
    db "................"
    db "................"
    db "................"
    db "................"
chestplate_bmp:
    db "................"
    db "..DDDD....DDDD.."
    db "..DLmD....DmmD.."
    db "..DmmDDDDDDmmD.."
    db "..DmmmmmmmmmmD.."
    db "...DLmmmmmmmD..."
    db "....DmmmmmmD...."
    db "....DmmmmmmD...."
    db "....DmmmmmmD...."
    db "....DmmmmmmD...."
    db "....DmmmmmmD...."
    db "....DmmmmmmD...."
    db "....DDDDDDDD...."
    db "................"
    db "................"
    db "................"
leggings_bmp:
    db "................"
    db "................"
    db "....DDDDDDDD...."
    db "....DLmmmmmD...."
    db "....DmmmmmmD...."
    db "....DmmDDmmD...."
    db "....DmmDDmmD...."
    db "....DmmDDmmD...."
    db "....DmmDDmmD...."
    db "....DmmDDmmD...."
    db "....DmmDDmmD...."
    db "....DDDDDDDD...."
    db "................"
    db "................"
    db "................"
    db "................"
boots_bmp:
    db "................"
    db "................"
    db "................"
    db "................"
    db "................"
    db "................"
    db "...DDDD..DDDD..."
    db "...DLmD..DLmD..."
    db "...DmmD..DmmD..."
    db "...DmmD..DmmD..."
    db "..DDmmD..DmmDD.."
    db ".DLmmmD..DmmmmD."
    db ".DDDDDD..DDDDDD."
    db "................"
    db "................"
    db "................"

; ---- firearm icons (tiles 119..128) ----
pal_pistol:
    PAL 'K', 22, 22, 24
    PAL 'S', 205, 205, 212
    PAL 's', 150, 150, 160
    PAL 'd', 78, 78, 86
    PAL 'g', 62, 44, 34
    dq 0
pal_musket:
    PAL 'K', 36, 24, 14
    PAL 'I', 205, 205, 212
    PAL 'i', 140, 140, 150
    PAL 'b', 200, 160, 50
    PAL 'B', 140, 105, 25
    PAL 'w', 170, 110, 50
    PAL 'W', 110, 68, 28
    dq 0
pal_shotgun:
    PAL 'K', 28, 24, 22
    PAL 'I', 205, 205, 212
    PAL 'i', 130, 130, 140
    PAL 'w', 176, 116, 54
    PAL 'W', 112, 70, 30
    dq 0
pal_kalash:
    PAL 'K', 20, 20, 22
    PAL 'B', 105, 105, 116
    PAL 'b', 54, 54, 60
    PAL 'o', 210, 124, 46
    PAL 'O', 140, 78, 28
    PAL 'w', 170, 112, 52
    PAL 'W', 110, 70, 30
    dq 0
pal_launcher:
    PAL 'K', 20, 30, 20
    PAL 'G', 124, 174, 96
    PAL 'g', 76, 120, 62
    PAL 'd', 44, 78, 38
    PAL 'k', 66, 50, 38
    dq 0
pal_brass:
    PAL 'K', 54, 36, 10
    PAL 'c', 196, 100, 52
    PAL 'C', 232, 150, 90
    PAL 'B', 255, 226, 130
    PAL 'b', 224, 176, 62
    PAL 'D', 150, 108, 28
    dq 0
pal_ball:
    PAL 'K', 28, 28, 34
    PAL 'L', 228, 228, 236
    PAL 'm', 150, 150, 160
    PAL 'D', 84, 84, 94
    dq 0
pal_shell:
    PAL 'K', 50, 12, 10
    PAL 'R', 245, 96, 76
    PAL 'r', 205, 38, 32
    PAL 'd', 134, 22, 22
    PAL 'B', 255, 226, 130
    PAL 'b', 224, 176, 62
    PAL 'D', 150, 108, 28
    dq 0
pal_rocket:
    PAL 'K', 30, 24, 24
    PAL 'R', 250, 110, 86
    PAL 'r', 212, 40, 32
    PAL 'd', 138, 24, 22
    PAL 'S', 222, 222, 230
    PAL 's', 160, 160, 170
    PAL 'e', 104, 104, 114
    dq 0

pistol_bmp:
    db "................"
    db "................"
    db "................"
    db ".KKKKKKKKKKKKKK."
    db ".KSSSSSSSSSSSsK."
    db ".KsssssssssssdK."
    db ".KsssdsssssssdK."
    db ".KKKKKKKKKKKKKK."
    db "..KgggKKKKK....."
    db "..KgggK...K....."
    db "..KgggKKKKK....."
    db "..KgggK........."
    db "..KgggK........."
    db "..KKKKK........."
    db "................"
    db "................"
musket_bmp:
    db "............KKKK"
    db "............KIiK"
    db "...........KIiK."
    db "..........KIiK.."
    db ".........KIiK..."
    db "........KbBK...."
    db ".......KIiK....."
    db "......KIiK......"
    db ".....KwwWK......"
    db "....KwwwWK......"
    db "...KwwwWK......."
    db "..KwwwWK........"
    db ".KwwwWK........."
    db "KwwwWK.........."
    db "KKKKK..........."
    db "................"
shotgun_bmp:
    db ".........KKKKKKK"
    db ".........KIiKIiK"
    db "........KIiKIiK."
    db ".......KIiKIiK.."
    db "......KIiKIiK..."
    db ".....KIiKIiK...."
    db "...KwwwwwwwK...."
    db "..KWWWWWWWK....."
    db "..KIiKIiK......."
    db ".KwwwwwK........"
    db "KwwWwwK........."
    db "KwwWwK.........."
    db "KKKKK..........."
    db "................"
    db "................"
    db "................"
kalash_bmp:
    db "............KKKK"
    db "............KBbK"
    db "...........KBbK."
    db "..........KBbK.."
    db "........KwwWK..."
    db ".......KwwWK...."
    db "......KBbbK....."
    db ".....KBbbbK....."
    db "....KBbbbbK....."
    db "...KwwwwKKoOK..."
    db "..KwWwwK.KoOK..."
    db ".KwWwwK...KoOK.."
    db "KwWwwK.....KoOK."
    db "KKKKKK.....KoOK."
    db "...........KKKK."
    db "................"
launcher_bmp:
    db "..........KKKKKK"
    db ".........KGGggdK"
    db "........KGGggdK."
    db ".......KGGggdK.."
    db "......KGGggdK..."
    db ".....KGGggdK...."
    db "....KGGggdK....."
    db "...KGGggdK......"
    db "..KGGggdK......."
    db ".KGGggdKkkK....."
    db ".KKKKKKKkkK....."
    db ".......KkkK....."
    db ".......KkkK....."
    db ".......KKKK....."
    db "................"
    db "................"
round_pistol_bmp:
    db "................"
    db "................"
    db "................"
    db "......KKKK......"
    db ".....KcCccK....."
    db ".....KcCccK....."
    db ".....KBBbDK....."
    db ".....KBbbDK....."
    db ".....KBbbDK....."
    db ".....KBbbDK....."
    db ".....KBbbDK....."
    db "....KBBbbbDK...."
    db "....KKKKKKKK...."
    db "................"
    db "................"
    db "................"
musket_ball_bmp:
    db "................"
    db "................"
    db "................"
    db "................"
    db ".....KKKKKK....."
    db "...KKLLmmmmKK..."
    db "...KLLLmmmmDK..."
    db "...KLLmmmmmDK..."
    db "...KLmmmmmmDK..."
    db "...KmmmmmmDDK..."
    db "...KmmmmmDDDK..."
    db "...KKmmmDDDKK..."
    db ".....KKKKKK....."
    db "................"
    db "................"
    db "................"
shell_bmp:
    db "................"
    db "................"
    db "....KKKKKKKK...."
    db "....KRrrrrdK...."
    db "....KRrrrrdK...."
    db "....KRrrrrdK...."
    db "....KRrrrrdK...."
    db "....KRrrrrdK...."
    db "....KRrrrrdK...."
    db "....KBbbbbDK...."
    db "....KBbbbbDK...."
    db "....KBbbbbDK...."
    db "....KKKKKKKK...."
    db "................"
    db "................"
    db "................"
round_rifle_bmp:
    db "................"
    db ".......KK......."
    db "......KccK......"
    db "......KcCK......"
    db "......KccK......"
    db "......KccK......"
    db "......KccK......"
    db ".....KBBbDK....."
    db ".....KBbbDK....."
    db ".....KBbbDK....."
    db ".....KBbbDK....."
    db ".....KBbbDK....."
    db ".....KBbbDK....."
    db "....KBBbbbDK...."
    db "....KKKKKKKK...."
    db "................"
rocket_bmp:
    db "................"
    db ".......KK......."
    db "......KRrK......"
    db ".....KRRrdK....."
    db ".....KRrrdK....."
    db ".....KRrrdK....."
    db ".....KKKKKK....."
    db ".....KSssdK....."
    db ".....KSssdK....."
    db ".....KSssdK....."
    db ".....KSssdK....."
    db "...KKKSssdKKK..."
    db "..KssKSssdKssK.."
    db "..KKKKKKKKKKKK.."
    db "................"
    db "................"

; ---- RPG art (tiles 59, 60 and 129..179): 16x16 bitmaps, palettes as for the icons above ----
brick_bmp:
    db "hhhhhhhDhhhhhhhD"
    db "caaaabaDacbaaacD"
    db "baaabcbDcaaacaaD"
    db "ccaabaaDaaaacbbD"
    db "acaacaaDaacbaccD"
    db "baababcDbaaacaaD"
    db "lllllllDlllllllD"
    db "DDDDDDDDDDDDDDDD"
    db "hhhDhhhhhhhDhhhh"
    db "babDbbbbaaaDcaca"
    db "aaaDbaabacbDcabc"
    db "aaaDaaaaaabDacba"
    db "bcbDacbabaaDcaab"
    db "cacDcaaaabaDbaca"
    db "lllDlllllllDllll"
    db "DDDDDDDDDDDDDDDD"
pal_brick:
    PAL 'D', 66, 66, 70
    PAL 'a', 132, 132, 134
    PAL 'b', 120, 120, 124
    PAL 'c', 144, 144, 146
    PAL 'h', 160, 160, 162
    PAL 'l', 108, 108, 112
    dq 0
mossy_bmp:
    db "hGhhhhhDhhhGhhgD"
    db "babcGaaDaagbGbaD"
    db "cccabgaDbababcaD"
    db "caababbDccaaaaaD"
    db "baGaaacDcabacaaD"
    db "babaaaaDabbccaaD"
    db "glgglllDlllllllM"
    db "DMMMDDDDDDDDDDDM"
    db "gGgDhhhhhhhDhhhh"
    db "bgaMbgaacbaDacca"
    db "bbcDGaacaabDacac"
    db "bbGMaabbbaaDbaaa"
    db "baaDabaaaabDaaaa"
    db "GgaDbbbbaaaDaaag"
    db "lllDlllllllDllll"
    db "MMDDDDDDDDDDMMDg"
pal_mossy:
    PAL 'D', 66, 66, 70
    PAL 'G', 66, 108, 42
    PAL 'M', 44, 66, 30
    PAL 'a', 132, 132, 134
    PAL 'b', 120, 120, 124
    PAL 'c', 144, 144, 146
    PAL 'g', 94, 136, 56
    PAL 'h', 160, 160, 162
    PAL 'l', 108, 108, 112
    dq 0
staff_bmp:
    db "................"
    db "...........YYY.."
    db "..........YRRRY."
    db "..........YRrRY."
    db "..........YRRRY."
    db "...........YDY.."
    db "..........wW...."
    db ".........wW....."
    db "........wW......"
    db ".......YD......."
    db "......wW........"
    db ".....wW........."
    db "....wW.........."
    db "...wW..........."
    db "..wW............"
    db ".wW............."
pal_staff:
    PAL 'D', 176, 124, 10
    PAL 'R', 230, 40, 52
    PAL 'W', 96, 64, 28
    PAL 'Y', 252, 216, 64
    PAL 'r', 255, 160, 160
    PAL 'w', 170, 122, 66
    dq 0
archstaff_bmp:
    db ".........L......"
    db "...........TTT.L"
    db "..........TLLCT."
    db "..........TLCCT."
    db "..........TCCCB."
    db "..........YTTB.."
    db "........YYYY...Y"
    db "........YYW....."
    db "........wW......"
    db ".......wW......."
    db "......wW........"
    db ".....wW........."
    db "....wW.........."
    db "...wW..........."
    db "..wW............"
    db ".wW............."
pal_archstaff:
    PAL 'B', 48, 170, 200
    PAL 'C', 96, 232, 238
    PAL 'L', 236, 255, 255
    PAL 'T', 20, 112, 124
    PAL 'W', 44, 30, 64
    PAL 'Y', 252, 216, 64
    PAL 'w', 86, 60, 112
    dq 0
dagger_bmp:
    db "................"
    db "................"
    db ".............L.."
    db "............L..."
    db "...........L...."
    db "..........Lm...."
    db ".........Lm....."
    db "........Lm......"
    db "...kG..Lm......."
    db "....gG.........."
    db ".....gG........."
    db "....HhgG........"
    db "...Hh..gG......."
    db "..Hh....k......."
    db ".pp............."
    db "ppp............."
pal_dagger_iron:
    PAL 'G', 226, 190, 60
    PAL 'H', 86, 52, 26
    PAL 'L', 248, 248, 252
    PAL 'g', 250, 222, 90
    PAL 'h', 142, 88, 44
    PAL 'k', 150, 112, 20
    PAL 'm', 168, 174, 188
    PAL 'p', 212, 182, 70
    dq 0
pal_dagger_diamond:
    PAL 'G', 226, 190, 60
    PAL 'H', 86, 52, 26
    PAL 'L', 226, 255, 255
    PAL 'g', 250, 222, 90
    PAL 'h', 142, 88, 44
    PAL 'k', 150, 112, 20
    PAL 'm', 64, 200, 212
    PAL 'p', 212, 182, 70
    dq 0
fang_bmp:
    db "................"
    db "...............V"
    db ".............VV."
    db "...........VV.KK"
    db ".........VV.KB.."
    db "........V.KB...."
    db ".......V.B......"
    db ".......VB......."
    db "......VBK......."
    db "...gg.VKK......."
    db "....gg.K........"
    db ".....eg........."
    db "......gg........"
    db "....hH.g........"
    db "..phH..........."
    db ".pp............."
pal_fang:
    PAL 'B', 72, 38, 112
    PAL 'H', 34, 22, 48
    PAL 'K', 26, 12, 40
    PAL 'V', 204, 124, 255
    PAL 'e', 240, 70, 226
    PAL 'g', 84, 60, 120
    PAL 'h', 60, 40, 76
    PAL 'p', 134, 80, 196
    dq 0
kings_bmp:
    db "..............LL"
    db ".............LL."
    db "............LWm."
    db "...........LW..."
    db ".GG.......LWm..."
    db "..G......LWm...."
    db "...G....LWm....."
    db "....Y...Wm......"
    db ".....Y.Wm......."
    db "......R........."
    db "....Hh.Y........"
    db "...Hh...Y......."
    db "..Hh.....G......"
    db ".YG......GG....."
    db "GGG............."
    db "................"
pal_kings:
    PAL 'G', 232, 182, 32
    PAL 'H', 72, 22, 26
    PAL 'L', 255, 255, 240
    PAL 'R', 224, 32, 52
    PAL 'W', 255, 246, 206
    PAL 'Y', 255, 238, 120
    PAL 'h', 124, 44, 44
    PAL 'm', 230, 196, 108
    dq 0
celestial_bmp:
    db "................"
    db "..............wc"
    db "............csw."
    db "............sw.."
    db "...........scw.."
    db "..........sccw.."
    db ".........s.cww.."
    db "........s.ccw..."
    db ".......s..cww..."
    db "......s..cww...."
    db ".....s.ccwgg...."
    db "....scccwwgg...."
    db "..csccwww...c..."
    db "..swwww........."
    db ".ww...........c."
    db ".c.............."
pal_celestial:
    PAL 'c', 100, 222, 250
    PAL 'g', 255, 226, 96
    PAL 's', 200, 244, 255
    PAL 'w', 252, 254, 255
    dq 0
potion_bmp:
    db "................"
    db "......KkkK......"
    db "......kkkk......"
    db "......oooo......"
    db "......owoo......"
    db "......owoo......"
    db ".....oooooo....."
    db "....oooooooo...."
    db "...oLLLLLLLLo..."
    db "...olwwlllllo..."
    db "...olwllllllo..."
    db "...ollllllllo..."
    db "....oddddddo...."
    db "....ooddddoo...."
    db ".....oooooo....."
    db "................"
pal_potion_red:
    PAL 'K', 100, 64, 30
    PAL 'L', 255, 120, 120
    PAL 'd', 150, 22, 38
    PAL 'k', 156, 104, 54
    PAL 'l', 232, 52, 62
    PAL 'o', 48, 40, 56
    PAL 'w', 255, 255, 255
    dq 0
pal_potion_blue:
    PAL 'K', 100, 64, 30
    PAL 'L', 140, 176, 255
    PAL 'd', 30, 52, 172
    PAL 'k', 156, 104, 54
    PAL 'l', 64, 104, 255
    PAL 'o', 48, 40, 56
    PAL 'w', 255, 255, 255
    dq 0
coin_bmp:
    db "................"
    db "................"
    db ".....RRRRRR....."
    db "...RLLYYYYYRR..."
    db "...LYYDDDDYYS..."
    db "..RLYDYDDYDYYS.."
    db "..LYDYYDDYYDYS.."
    db "..LYDYYDDYYDYS.."
    db "..RYDYYDDYYDYS.."
    db "..RYDYYDDYYDYS.."
    db "..RYYDYDDYDYYS.."
    db "...RYYDDDDYYS..."
    db "...RSYYYYYYSS..."
    db ".....SSSSSS....."
    db "................"
    db "................"
pal_coin:
    PAL 'D', 212, 156, 18
    PAL 'L', 255, 246, 170
    PAL 'R', 204, 144, 12
    PAL 'S', 150, 98, 6
    PAL 'Y', 252, 214, 60
    dq 0
charge_bmp:
    db "................"
    db ".RR...YO........"
    db "..RR...YO......."
    db "...RR...YO......"
    db "....RR...YO....."
    db "SS...RR...YO...."
    db "......RR...YO..."
    db ".......RRR..YYO."
    db "SS.....RRR..YYO."
    db "......RR...YO..."
    db ".....RR...YO...."
    db "SS..RR...YO....."
    db "...RR...YO......"
    db "..RR...YO......."
    db ".RR...YO........"
    db "................"
pal_charge:
    PAL 'O', 255, 146, 34
    PAL 'R', 214, 44, 28
    PAL 'S', 200, 200, 214
    PAL 'Y', 255, 226, 90
    dq 0
warcry_bmp:
    db "................"
    db "................"
    db "................"
    db ".......DD...O.R."
    db ".....LLDD....O.."
    db "....LYYDD..O.O.R"
    db ".YYLYYYDD.....O."
    db ".YLYYYYDD...O.O."
    db ".YYYYYYDD...O.O."
    db "..DYYYYDD.....O."
    db "...DYYYDD..O.O.."
    db "....DYYDD....O.R"
    db ".....DDDD...O..."
    db "..............R."
    db "................"
    db "................"
pal_warcry:
    PAL 'D', 168, 112, 14
    PAL 'L', 255, 248, 190
    PAL 'O', 255, 150, 40
    PAL 'R', 230, 60, 30
    PAL 'Y', 252, 212, 60
    dq 0
whirl_bmp:
    db ".......S........"
    db "...LSSSSSSS....."
    db "..LLLWWWWWSS...."
    db ".LSSW.....WSS..."
    db ".SSW.......WSS.."
    db ".SW..........S.."
    db ".SW............."
    db "SSW....YY...WSS."
    db ".SW....YY...WS.."
    db ".S..........WS.."
    db ".SS........WSS.."
    db "..SSW.....WSS.L."
    db "...SSWWWWWLLLLL."
    db "....SSSSSSSLLL.."
    db ".......S....L..."
    db "................"
pal_whirl:
    PAL 'L', 255, 255, 255
    PAL 'S', 196, 206, 226
    PAL 'W', 120, 140, 180
    PAL 'Y', 255, 226, 90
    dq 0
fireball_bmp:
    db "..........r....."
    db ".......rrrOrrr.."
    db "......rrOOOOOrr."
    db "......rOOYYYOOr."
    db "......rOYLLYYOr."
    db ".....rOOYLLYYOOr"
    db "......rOYYYYYOr."
    db ".....rrOOYYYOOr."
    db "...rrOrrOOOOOrr."
    db "..rrOOOrrrOrrr.."
    db "..rOOOOrr.r....."
    db ".rrOOOOr........"
    db ".rOOOOr........."
    db ".rOOOr.........."
    db "rO.............."
    db "................"
pal_fireball:
    PAL 'L', 255, 250, 210
    PAL 'O', 255, 138, 28
    PAL 'Y', 255, 214, 70
    PAL 'r', 204, 40, 20
    dq 0
blink_bmp:
    db "................"
    db "........PPPPC..."
    db ".......CP..P...."
    db "..C....PPCCPP..."
    db ".......P.CC.P..."
    db ".......PCCCCP..."
    db ".......PC..CP..."
    db "..pppppPC..CPL.."
    db "ppppppLLLL.CP.LL"
    db "..pppppPC..CPL.."
    db ".......PCCCCP..."
    db ".......P.CC.P..."
    db ".......PPCCPP..."
    db "....C...P..P...."
    db "......C.PPPP...."
    db "............C..."
pal_blink:
    PAL 'C', 110, 232, 255
    PAL 'L', 250, 250, 255
    PAL 'P', 176, 100, 255
    PAL 'p', 112, 60, 196
    dq 0
meteor_bmp:
    db "................"
    db "................"
    db ".....O.........."
    db "....O..........."
    db ".RRO............"
    db ".RR.......OO...."
    db "........OOO....."
    db ".......OOO......"
    db "....RRROOO......"
    db "...RYYYROL......"
    db "...RYYYR........"
    db "...RYYYR......O."
    db "...RRYRR....OOL."
    db "....RRR...RRR..."
    db "..........RRR..."
    db "................"
pal_meteor:
    PAL 'L', 255, 252, 220
    PAL 'O', 255, 142, 30
    PAL 'R', 214, 44, 24
    PAL 'Y', 255, 222, 80
    dq 0
volley_bmp:
    db "................"
    db "................"
    db ".......G........"
    db ".......GW......."
    db "......GGG......."
    db "GG....GGG....GG."
    db "GGG.....W...GGG."
    db ".GW.....W....G.."
    db "...W....W...W..."
    db "....W...W..W...."
    db "....W...W..W...."
    db ".....W..W.W....."
    db "......W.WW......"
    db "......W.WW......"
    db "......FFF......."
    db "......F..F......"
pal_volley:
    PAL 'F', 240, 240, 240
    PAL 'G', 210, 216, 228
    PAL 'W', 170, 120, 70
    dq 0
explarrow_bmp:
    db "................"
    db "..........OO...."
    db ".......OOOOOOOO."
    db "........OYYYYO.."
    db "........OOLLOO.."
    db "........OOOOOO.."
    db ".......O.WOO..O."
    db "........W.OO...."
    db ".......W........"
    db "......W........."
    db ".....W.........."
    db "....W..........."
    db "...W............"
    db ".FF............."
    db "FF.............."
    db ".FF............."
pal_explarrow:
    PAL 'F', 240, 240, 240
    PAL 'L', 255, 252, 220
    PAL 'O', 240, 90, 24
    PAL 'W', 170, 120, 70
    PAL 'Y', 255, 214, 70
    dq 0
arrowrain_bmp:
    db ".......NN......."
    db "..NNN.NNNN.NNN.."
    db "..NNNNNNNNNNNN.."
    db "..NNNNNNNNNNNN.."
    db "..nnnnnnnnnnFFF."
    db "..FFF........W.."
    db "...W...FFF...W.."
    db "...W....W....W.."
    db "...W....W....W.."
    db "...W....W....W.."
    db "...W....W..GGGG."
    db ".GGGG...W...GG.."
    db "..GG..GGGG..GG.."
    db "..GG...GG....W.."
    db "...W...GG......."
    db "........W......."
pal_arrowrain:
    PAL 'F', 250, 250, 250
    PAL 'G', 226, 230, 240
    PAL 'N', 184, 190, 208
    PAL 'W', 170, 120, 70
    PAL 'n', 120, 126, 150
    dq 0
shadowstep_bmp:
    db "................"
    db "..........VVV..."
    db "...p..p.pVKKKV.."
    db "..p.pp.pVKKKKKV."
    db ".p.p.pp.pKKKKKV."
    db "..p.pp.pVKEKEKV."
    db "...p..p.pVKKKV.."
    db "..p.pp.pVKKKKKV."
    db ".p.p.pp.pKKKKKV."
    db "p.p.ppppKKKKKKKV"
    db ".p.ppppVKKKKKKKV"
    db "p.p.ppppKKKKKKKV"
    db ".p.ppppVKKKKKKKV"
    db "p.p.ppppKKKKKKKV"
    db ".p.ppppVKKKKKKKV"
    db "........VVVVVVV."
pal_shadowstep:
    PAL 'E', 240, 80, 255
    PAL 'K', 30, 18, 50
    PAL 'V', 150, 90, 230
    PAL 'p', 120, 64, 200
    dq 0
smoke_bmp:
    db ".........O.O...."
    db "..........Y....."
    db ".........f.O...."
    db ".........f......"
    db "......kkf......."
    db "......kk..NNN..."
    db "....KKKKK.NNNN.."
    db "...KKgKKKKNNNnn."
    db "..KKggKKKKK..nn."
    db "..KKgKKKKKKNNNn."
    db "..KKKKKKKKNNNN.."
    db "..KKKKKKKKNNNN.."
    db "..KKKKKKKKK.Nnnn"
    db "...KKKKKKK...nnn"
    db ".....KKK........"
    db "................"
pal_smoke:
    PAL 'K', 40, 40, 52
    PAL 'N', 206, 210, 222
    PAL 'O', 255, 140, 30
    PAL 'Y', 255, 226, 90
    PAL 'f', 210, 170, 110
    PAL 'g', 120, 120, 140
    PAL 'k', 110, 84, 64
    PAL 'n', 144, 150, 168
    dq 0
bladedance_bmp:
    db ".........PP....."
    db "..........PP...."
    db "............PP.."
    db "..mL........LP.."
    db "...mL......LmPP."
    db "....mL....Lm..P."
    db ".....mL..Lm....."
    db "......mYYm......"
    db ".......YY......."
    db "P.....LmmL......"
    db "PP...Lm..mL...G."
    db ".PG.Lm....mL.G.."
    db ".PPGm......mG..."
    db "..hPP......G.h.."
    db ".h..PP........h."
    db "................"
pal_bladedance:
    PAL 'G', 236, 196, 64
    PAL 'L', 250, 250, 255
    PAL 'P', 190, 110, 255
    PAL 'Y', 255, 226, 90
    PAL 'h', 130, 84, 44
    PAL 'm', 170, 176, 192
    dq 0
emb_warrior_bmp:
    db ".K............K."
    db "KLK..........KLK"
    db ".KLK........KLK."
    db ".KmLK......KLmK."
    db "..KmLK....KLmK.."
    db "...KmLK..KLmK..."
    db "....KmLKKLmK...."
    db "...KKKmLLmKKK..."
    db "..KGGKKLLKKGGK.."
    db "...KGK.KK.KGK..."
    db "....KGK..KGK...."
    db "....KhGKKGhK...."
    db "..KKhKKGGKKhKK.."
    db ".KYhK..KK..KhYK."
    db ".KYK........KYK."
    db "KYK..........KYK"
pal_emb_warrior:
    PAL 'G', 232, 182, 32
    PAL 'K', 40, 34, 40
    PAL 'L', 250, 250, 255
    PAL 'Y', 255, 230, 100
    PAL 'h', 142, 88, 44
    PAL 'm', 170, 176, 192
    dq 0
emb_mage_bmp:
    db ".........KrK..K."
    db "........KrrrKKYK"
    db "........KrOrK.K."
    db ".....K.KrrOOrK.."
    db "....KYKrrOOOrrK."
    db ".....KKrOOYOOrK."
    db "..K...KrOYYYOrK."
    db ".KYK..KrOYLOOrK."
    db "..K....KrOLOrK.."
    db ".......KYrrrK..."
    db "......KwWKKK...."
    db ".....KwWK......."
    db "....KwWK........"
    db "...KwWK........."
    db "..KwWK.........."
    db ".KwWK..........."
pal_emb_mage:
    PAL 'K', 44, 24, 20
    PAL 'L', 255, 250, 210
    PAL 'O', 255, 140, 30
    PAL 'W', 98, 66, 30
    PAL 'Y', 255, 226, 90
    PAL 'r', 210, 44, 22
    PAL 'w', 172, 124, 68
    dq 0
emb_archer_bmp:
    db "........KK......"
    db "......KKwsK....."
    db ".....KwwsWK....."
    db ".....KwWsK......"
    db "....KwwsK......."
    db "....KwWsK...K..."
    db "...KFwsK...KGKK."
    db "..KFwFsKKKKKGGGK"
    db "...KFFaaaaaaGGGK"
    db "..KFwFsKKKKKGKK."
    db "...KFwsK....K..."
    db "....KwwsK......."
    db ".....KwsWK......"
    db ".....KwwsWK....."
    db "......KKsK......"
    db "........KsK....."
pal_emb_archer:
    PAL 'F', 240, 240, 244
    PAL 'G', 210, 216, 228
    PAL 'K', 36, 28, 22
    PAL 'W', 104, 70, 32
    PAL 'a', 196, 150, 90
    PAL 's', 230, 230, 236
    PAL 'w', 178, 126, 66
    dq 0
emb_rogue_bmp:
    db "................"
    db "....KKKKK......."
    db "...KHHHHHK...LL."
    db "..KHHHHHHHK..Lm."
    db ".KHHHHHHHHHK.Lm."
    db "KHHHHFFFHHHHKLm."
    db "KHHHFFFFFHHHKLm."
    db "KHHFFFFFFFHHKLm."
    db "KHHFFEFFEFHHHLm."
    db "KHHFFFFFFFHHHLm."
    db "KHhHFFFFFFHhHLm."
    db "KHHHFFFFFFHHGGGG"
    db "KHHHHHHHHHHHHkk."
    db ".hHHHHHHHHHHhkk."
    db "KHHHHHHHHHHHHGG."
    db ".KKKKKKKKKKKK..."
pal_emb_rogue:
    PAL 'E', 150, 255, 120
    PAL 'F', 14, 8, 20
    PAL 'G', 232, 182, 32
    PAL 'H', 72, 48, 110
    PAL 'K', 30, 18, 46
    PAL 'L', 250, 250, 255
    PAL 'h', 104, 74, 150
    PAL 'k', 110, 70, 40
    PAL 'm', 170, 176, 192
    dq 0
st_health_bmp:
    db "................"
    db "....KKK..KKK...."
    db "...KRRRKKRRRK..."
    db "..KRwRRRRRRRRK.."
    db ".KRwRRRRRRRRRRK."
    db ".KRwRRRRRRRRRRK."
    db ".KRRRRRRRRRRRRK."
    db ".KRRRRRRRRRRRRK."
    db "..KRRRRRRRRRRK.."
    db "...KRRRRRRRRK..."
    db "....KRRRRRRK...."
    db ".....KRRRRK....."
    db ".....KRRRdK....."
    db "......KRdK......"
    db ".......KK......."
    db "................"
pal_st_health:
    PAL 'K', 60, 14, 22
    PAL 'R', 226, 40, 52
    PAL 'd', 160, 24, 40
    PAL 'w', 255, 170, 170
    dq 0
st_melee_bmp:
    db "..............KK"
    db ".............KLL"
    db ".............KLK"
    db "............KLK."
    db "...........KLmK."
    db "..........KLmK.."
    db "..KK.....KLmK..."
    db ".KGGK...KLmK...."
    db "..KGK..KLmK....."
    db "...KGKKLmK......"
    db "...KhGLmK......."
    db "..KhKLGK........"
    db ".KhK.KKGK......."
    db "KhK....K........"
    db "ppK............."
    db "pK.............."
pal_st_melee:
    PAL 'G', 232, 182, 32
    PAL 'K', 36, 36, 44
    PAL 'L', 250, 250, 255
    PAL 'h', 150, 60, 50
    PAL 'm', 170, 176, 192
    PAL 'p', 232, 182, 32
    dq 0
st_ranged_bmp:
    db "............KKK."
    db "...........KGGGK"
    db "..........KGGGWK"
    db "...........KGGK."
    db "...........KWGK."
    db "..........KWKK.."
    db ".........KWK...."
    db "........KWK....."
    db ".......KWK......"
    db "....K.KWK......."
    db "...KFKWK........"
    db "....KFFK........"
    db ".....KK........."
    db "................"
    db "................"
    db "................"
pal_st_ranged:
    PAL 'F', 250, 250, 250
    PAL 'G', 226, 230, 240
    PAL 'K', 40, 34, 30
    PAL 'W', 176, 124, 72
    dq 0
st_spell_bmp:
    db "................"
    db ".......KK......."
    db "......KPPK......"
    db "......KPPK......"
    db "......KPPK......"
    db ".KKKKKPQQPKKKKK."
    db "KPPPPPPQLPPPPPPK"
    db ".KPPQQQLLQQQPPK."
    db "..KKPQQQQQQPKK.."
    db "....KPQQQQPK...."
    db "....KPQQQQPK...."
    db "...KPQQPPQQPK..."
    db "...KPPPKKPPPK..."
    db "...KPKK..KKPK..."
    db "....K......K...."
    db "................"
pal_st_spell:
    PAL 'K', 40, 20, 72
    PAL 'L', 255, 250, 255
    PAL 'P', 150, 84, 240
    PAL 'Q', 208, 160, 255
    dq 0
st_critchance_bmp:
    db "......KRRK......"
    db "......KRRK......"
    db "....KKRRRKK....."
    db "...KRRRRRRRK...."
    db "..KRRKKRRKRRK..."
    db "..KRK..KK.KRK..."
    db "KKRRK.....KRRKKK"
    db "RRRRRK.YY.KRRRRR"
    db "RRRRRK.YY.KRRRRR"
    db "KKKRK.....KRKKKK"
    db "..KRRKKKKKRRK..."
    db "...KRRRRRRRK...."
    db "....KKRRRKK....."
    db "......KRRK......"
    db "......KRRK......"
    db "......KRRK......"
pal_st_critchance:
    PAL 'K', 50, 14, 12
    PAL 'R', 230, 56, 40
    PAL 'Y', 255, 222, 80
    dq 0
st_critdmg_bmp:
    db "................"
    db "..K....KK....K.."
    db ".KOK..KOOK..KOK."
    db "..KOKKKOOKKKOK.."
    db "...KYOKOOKOYK..."
    db "...KOYYYYYYOK..."
    db "..KKKYYYYYYKKK.."
    db ".KOOOYYLLYYOOOK."
    db ".KOOOYYLLYYOOOK."
    db "..KKKYYYYYYKKK.."
    db "...KOYYYYYYOK..."
    db "...KYOKOOKOYK..."
    db "..KOKKKOOKKKOK.."
    db ".KOK..KOOK..KOK."
    db "..K....KK....K.."
    db "................"
pal_st_critdmg:
    PAL 'K', 70, 20, 8
    PAL 'L', 255, 252, 220
    PAL 'O', 240, 100, 24
    PAL 'Y', 255, 214, 70
    dq 0
st_mana_bmp:
    db "................"
    db ".......KK......."
    db "......KBBK......"
    db "......KBBK......"
    db ".....KBBBBK....."
    db ".....KBBBBK....."
    db "....KBBBBBBK...."
    db "....KBBBBBBK...."
    db "...KBBBBBBBBK..."
    db "..KBBBBBBBBBBK.."
    db "..KBBwBBBBBBBK.."
    db "..KBBwBBBBBBBK.."
    db "..KBBBBBBBBBBK.."
    db "..KBBBBBBBBBdK.."
    db "...KBBBBBBBdK..."
    db "....KBBBBBdK...."
pal_st_mana:
    PAL 'B', 64, 110, 255
    PAL 'K', 14, 24, 80
    PAL 'd', 34, 60, 190
    PAL 'w', 200, 222, 255
    dq 0
st_manaregen_bmp:
    db "...........KK..."
    db "..........KAAK.."
    db "....K....KAAAAK."
    db "...KBK...KAAAAK."
    db "...KBK..KAAAAAAK"
    db "..KBBBK..KKAAKK."
    db "..KBBBK...KAAK.."
    db ".KBBBBBK..KAAK.."
    db "KBwBBBBBK.KAAK.."
    db "KBwBBBBBK.KAAK.."
    db "KBBBBBBdK.KAAK.."
    db ".KBBBBdK..KAAK.."
    db "..KKBKK...KAAK.."
    db "....K.....KAAK.."
    db "..........KAAK.."
    db "...........KK..."
pal_st_manaregen:
    PAL 'A', 120, 235, 110
    PAL 'B', 64, 110, 255
    PAL 'K', 14, 24, 70
    PAL 'd', 34, 60, 190
    PAL 'w', 200, 222, 255
    dq 0
st_stamina_bmp:
    db "........KYYK...."
    db ".......KYLK....."
    db "......KYLYK....."
    db "......KLYK......"
    db ".....KYYYK......"
    db "....KYLYKKKK...."
    db "...KYYYYYYYYK..."
    db "...KYYYYYYYK...."
    db "....KKKYYYK....."
    db "......KYYK......"
    db ".....KYYYK......"
    db ".....KYYK......."
    db ".....KYK........"
    db ".....KK........."
    db "....KYK........."
    db ".....K.........."
pal_st_stamina:
    PAL 'K', 100, 64, 0
    PAL 'L', 255, 250, 190
    PAL 'Y', 255, 214, 40
    dq 0
st_staminaregen_bmp:
    db ".....KYYK..KK..."
    db "....KYYK..KAAK.."
    db "...KYYYK.KAAAAK."
    db "...KYYK..KAAAAK."
    db "..KYYKKKKAAAAAAK"
    db ".KYYYYYYKKKAAKK."
    db ".KYYYYYK..KAAK.."
    db "..KKYYYK..KAAK.."
    db "...KYYK...KAAK.."
    db "...KYYK...KAAK.."
    db "...KYK....KAAK.."
    db "..KYK.....KAAK.."
    db "..KYK.....KAAK.."
    db "...K......KAAK.."
    db "..........KAAK.."
    db "...........KK..."
pal_st_staminaregen:
    PAL 'A', 120, 235, 110
    PAL 'K', 100, 64, 0
    PAL 'Y', 255, 214, 40
    dq 0
st_armor_bmp:
    db ".KKKKKKKKKKKKK.."
    db "KSSSSSSSSSSSSSK."
    db "KSSSSSSSSSSSSSK."
    db "KSSBBBBLLBBBBSK."
    db "KSSBwwBLLBBBBSK."
    db "KSSBwBBLLBBBBDK."
    db "KSSLLLLLLLLLLDK."
    db "KSSLLLLLLLLLLDK."
    db ".KSSBBBLLBBBDDK."
    db "..KSSBBLLBBDDK.."
    db "...KSSBLLBDDK..."
    db "....KSBLLBDK...."
    db "....KSDLLDDK...."
    db ".....KDDDDK....."
    db "......KDDK......"
    db ".......KK......."
pal_st_armor:
    PAL 'B', 58, 98, 190
    PAL 'D', 120, 126, 150
    PAL 'K', 24, 28, 44
    PAL 'L', 214, 224, 250
    PAL 'S', 190, 196, 212
    PAL 'w', 255, 255, 255
    dq 0
st_speed_bmp:
    db "....KKKKK......."
    db "...KUUUUUK......"
    db "...KUUUUUK......"
    db "...KTlTTTK......"
    db "...KTlTTTK......"
    db "ZZ.KTlTTTK......"
    db "...KTlTTTK......"
    db "...KTTTTTK......"
    db "ZZZKTTTTTK......"
    db "...KlTTTTK......"
    db "...KTlTTKKKKKK.."
    db "ZZ.KTTTTTTTTTTK."
    db "...KTTTTTTTTTTK."
    db "...KTTTTTTTTTTK."
    db "...KDDDDDDDDDDDK"
    db "...KDDDDDDDDDDDK"
pal_st_speed:
    PAL 'D', 90, 56, 28
    PAL 'K', 40, 24, 12
    PAL 'T', 160, 100, 52
    PAL 'U', 200, 170, 110
    PAL 'Z', 200, 230, 255
    PAL 'l', 204, 140, 84
    dq 0
st_backstab_bmp:
    db ".......pp......."
    db ".......hh......."
    db ".......hh......."
    db ".......hh......."
    db ".......hh......."
    db "......gggg......"
    db ".......Lm......."
    db ".......Lm......."
    db "...KKKKLmKKK...."
    db "..KHHHHLmHHHK..."
    db ".KHHjHHLmHHHHK.."
    db "KHHjHHHLmHHHHHK."
    db "HHjHHHHLRRHHHHHK"
    db "HHHHHHHRHRHHHHHK"
    db "HHHHHHHHHHHHHHHK"
    db "HHHHHHHHHHHHHHHH"
pal_st_backstab:
    PAL 'H', 78, 52, 120
    PAL 'K', 24, 14, 40
    PAL 'L', 250, 250, 255
    PAL 'R', 230, 40, 48
    PAL 'g', 232, 182, 32
    PAL 'h', 142, 88, 44
    PAL 'j', 112, 84, 160
    PAL 'm', 170, 176, 192
    PAL 'p', 232, 182, 32
    dq 0
st_parry_bmp:
    db "................"
    db "................"
    db "...K........K..."
    db "..KLK......KLK.."
    db "...KLK....KLmK.."
    db "....KLKK.KLmK..."
    db ".....KLYKLmK...."
    db ".....KYLYmK....."
    db "..K...KYLYK..K.."
    db ".KGK.KLmYLK.KGK."
    db "..KGKLmKKKLKGK.."
    db "...KGmK...KGK..."
    db "..KLmGK..KGKLK.."
    db ".KLmKK....K.KLK."
    db "KhhK........KhhK"
    db ".KK..........KK."
pal_st_parry:
    PAL 'G', 232, 182, 32
    PAL 'K', 36, 36, 48
    PAL 'L', 250, 250, 255
    PAL 'Y', 255, 214, 70
    PAL 'h', 150, 90, 50
    PAL 'm', 170, 176, 192
    dq 0
st_lifesteal_bmp:
    db "................"
    db ".......KK......."
    db "......KRRK......"
    db "......KRRK......"
    db ".....KRRRRK....."
    db ".....KRRRRK....."
    db "....KRRRRRRK...."
    db "....KRRRRRRK...."
    db "...KRRRRRRRRK..."
    db "..KRRRRRRRRRRK.."
    db "..KRRwRRRRRRRK.."
    db "..KRRwRRRRRRRK.."
    db "..KRRRRRRRRRRK.."
    db "..KRRRRRRRRRdK.."
    db "...KRRRRRRRdK..."
    db "....KRRRRRdK...."
pal_st_lifesteal:
    PAL 'K', 60, 10, 20
    PAL 'R', 214, 26, 44
    PAL 'd', 140, 14, 30
    PAL 'w', 255, 170, 170
    dq 0
st_cooldown_bmp:
    db ".KGGGGGGGGGGGGK."
    db ".KGGGGGGGGGGGGK."
    db "..KDVVVVVVVVDK.."
    db "...KwwVVVVV.K..."
    db "......VVVV......"
    db "......VVVV......"
    db ".......VV......."
    db "........Y......."
    db "........Y......."
    db ".......VY......."
    db "......VVVV......"
    db "......VYYV......"
    db "...K.VYYYYV.K..."
    db "..KDVVVVVVVVDK.."
    db ".KGGGGGGGGGGGGK."
    db ".KGGGGGGGGGGGGK."
pal_st_cooldown:
    PAL 'D', 140, 92, 20
    PAL 'G', 204, 150, 50
    PAL 'K', 50, 30, 8
    PAL 'V', 150, 200, 230
    PAL 'Y', 255, 214, 70
    PAL 'w', 255, 255, 255
    dq 0
st_arrowsave_bmp:
    db ".....W.W.W......"
    db "....FWFWFWF....."
    db ".....W.W.W......"
    db ".....W.W.W......"
    db ".....W.W.W......"
    db "...RRRRRRRRR...."
    db "...UTTTTTTTu...."
    db "...UTTTTTTTu...."
    db "...UTTTTTTTu...."
    db "...UTTTTTTTu...."
    db "...UTTTTTTTu...."
    db "...UTTTTTTTu...."
    db "...UTTTTTTTu...."
    db "...UTTTTTTTu...."
    db "....uTTTTTu....."
    db ".....uuuuu......"
pal_st_arrowsave:
    PAL 'F', 245, 245, 245
    PAL 'R', 120, 70, 30
    PAL 'T', 168, 102, 50
    PAL 'U', 212, 160, 100
    PAL 'W', 190, 140, 90
    PAL 'u', 104, 62, 28
    dq 0
st_wind_bmp:
    db "................"
    db "................"
    db "..........WWW..."
    db ".WWWWWWWWWWWW..."
    db "............W..."
    db "............W..."
    db "..ww............"
    db ".............WW."
    db "WWWWWWWWWWWWWWWW"
    db "...............W"
    db ".ww...........WW"
    db "..........WW..W."
    db "...WWWWWWWW.W..."
    db "............W..."
    db "...........W...."
    db "................"
pal_st_wind:
    PAL 'W', 196, 230, 255
    PAL 'w', 120, 190, 240
    dq 0
npc_face_bmp:
    db "................"
    db "................"
    db "................"
    db "................"
    db "................"
    db "..BBBBBBBBBBBB.."
    db "................"
    db "...WWW....WWW..."
    db "...WGG....GGW..."
    db "................"
    db "................"
    db "................"
    db ".....MMMMMM....."
    db "................"
    db "................"
    db "................"
pal_npc_face:
    PAL '.', 225, 180, 140
    PAL 'B', 96, 62, 36
    PAL 'G', 64, 120, 70
    PAL 'M', 150, 98, 76
    PAL 'W', 240, 240, 240
    dq 0
npc_merchant_bmp:
    db "..........f....."
    db ".....f.........."
    db "..........f....."
    db ".....f.........."
    db "..........f....."
    db ".....f.........."
    db "..........f....."
    db ".....f.........."
    db "..........f....."
    db "BBBBBBBYYBBBBBBB"
    db "BBBBBBByyBBBBBBB"
    db ".....f.........."
    db "..........f....."
    db ".....f.........."
    db "dddddddddddddddd"
    db "dddddddddddddddd"
pal_npc_merchant:
    PAL '.', 60, 130, 60
    PAL 'B', 112, 72, 32
    PAL 'Y', 250, 214, 70
    PAL 'd', 44, 100, 44
    PAL 'f', 78, 152, 76
    PAL 'y', 184, 140, 30
    dq 0
npc_elder_bmp:
    db "D......Yy......D"
    db "D..f...Yy...f..D"
    db "D......Yy......D"
    db "D......Yy......D"
    db "D......Yy......D"
    db "D..f...Yy...f..D"
    db "D......Yy......D"
    db "D......Yy......D"
    db "D......Yy......D"
    db "D..f...Yy...f..D"
    db "D......Yy......D"
    db "D......Yy......D"
    db "YYYyYYYyYYYyYYYy"
    db "YYYyYYYyYYYyYYYy"
    db "yyyyyyyyyyyyyyyy"
    db "yyyyyyyyyyyyyyyy"
pal_npc_elder:
    PAL '.', 100, 60, 140
    PAL 'D', 72, 40, 104
    PAL 'Y', 250, 214, 70
    PAL 'f', 124, 80, 168
    PAL 'y', 184, 140, 30
    dq 0
npc_bossrobe_bmp:
    db "...r...ff...r..."
    db "...r........r..."
    db "................"
    db "...r........r..."
    db "...r...ff...r..."
    db "................"
    db "...r........r..."
    db "...r........r..."
    db ".......ff......."
    db "...r........r..."
    db "...r........r..."
    db "....d....d....d."
    db "...k...kd.k..d.."
    db ".kdk..kk..k.k..k"
    db "kk.kk.kk.kkdk.kk"
    db "kkkkkdkkkkk.kkkk"
pal_npc_bossrobe:
    PAL '.', 52, 28, 72
    PAL 'd', 36, 18, 52
    PAL 'f', 84, 46, 110
    PAL 'k', 14, 6, 20
    PAL 'r', 130, 24, 52
    dq 0
npc_bossface_bmp:
    db "................"
    db "................"
    db "......c........."
    db ".......c........"
    db ".......c........"
    db "..KKKK....KKKK.."
    db "..KRRK....KRRK.."
    db "..KRRK....KRRK.."
    db "..KKKK....KKKK.."
    db ".......KK......."
    db ".......KK......."
    db "................"
    db "...KKKKKKKKKK..."
    db "...KK.K.K.K.KK.."
    db "....K.K.K.K.K..."
    db "................"
pal_npc_bossface:
    PAL '.', 222, 214, 192
    PAL 'K', 18, 8, 12
    PAL 'R', 255, 50, 36
    PAL 'c', 150, 142, 118
    dq 0
npc_crown_bmp:
    db "LLLLLLLLLLLLLLLL"
    db "................"
    db "................"
    db ".D...D...D...D.."
    db "................"
    db "................"
    db "...WR..WR..WR..."
    db "...RR..RR..RR..."
    db "................"
    db "................"
    db "................"
    db "................"
    db "LLLLLLLLLLLLLLLL"
    db "DDDDDDDDDDDDDDDD"
    db "DDDDDDDDDDDDDDDD"
    db "DDDDDDDDDDDDDDDD"
pal_npc_crown:
    PAL '.', 240, 190, 40
    PAL 'D', 176, 126, 16
    PAL 'L', 255, 236, 140
    PAL 'R', 220, 30, 50
    PAL 'W', 255, 170, 170
    dq 0

section .text
