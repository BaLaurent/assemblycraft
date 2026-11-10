; art.inc: the data language of the 0.13 "looks" art: pixel palettes and bitmaps (item icons, skin
; decals) and skin models (bones, boxes, paint ops). Included by texgen.asm and by every art file.
; Records and constants: common.inc ("0.13 looks"). The engines: skin.asm, icons.asm, art.asm.
%ifndef ART_INC
%define ART_INC

; packed colour: R | G<<8 | B<<16 (little-endian dword = RGBA bytes, A in bits 24..31)
%define RGB(r, g, b) ((r) | ((g) << 8) | ((b) << 16))
; opaque packed colour for the icon tiles (alpha 255)
%define RGBO(r, g, b) ((r) | ((g) << 8) | ((b) << 16) | 0xFF000000)

; ---- palettes: 8-byte records, a zero qword ends the list -------------------------------------------
; HUD palettes: db char, 0, 0, 0 ; dd colour
%macro PAL 4
    db %1, 0, 0, 0
    dd RGBO(%2, %3, %4)
%endmacro
; GBMP palette entry: PALN char, r, g, b, noise mask [, alpha 255]; db char, mask, 0, 0 ; dd RGBA;
; char 0 ends the palette
%macro PALN 5-6 255
    db %1, %5, 0, 0
    dd (%2) | ((%3) << 8) | ((%4) << 16) | ((%6) << 24)
%endmacro
; PALC char, packed colour (an RGBO(...) or an AC_* ramp entry)
%macro PALC 2
    db %1, 0, 0, 0
    dd %2
%endmacro
; PALT char: a transparent texel (writes alpha 0, unlike '.', which leaves the texel as it is)
%macro PALT 1
    db %1, 0, 0, 0
    dd 0
%endmacro

; ---- bitmaps (section .rodata) ---------------------------------------------------------------------
; SKROWS label, w, h / h x SKROW "<w chars>" / SKROWS_END
%macro SKROWS 3
%push skrows
%define %$w %2
%define %$h %3
%assign %$n 0
%1:
%endmacro
%macro SKROW 1
%strlen %%len %1
%if %%len != %$w
%error "SKROW: row length differs from the SKROWS width"
%endif
    db %1
%assign %$n %$n + 1
%endmacro
%macro SKROWS_END 0
%if %$n != %$h
%error "SKROWS_END: row count differs from the SKROWS height"
%endif
%pop
%endmacro
; SKBMP label, rows label, w, h, palette label: a global SKBMP header
%macro SKBMP 5
global %1
%1:
    dq %5
    dq %2
    db %3, %4
    times 6 db 0
%endmacro

; ---- skin models (section .data: skin_build writes SKR_U/SKR_V and the sizes of SKPART_AS parts) -----
; SKMODEL_BEGIN label, tpb, held, hand_x, hand_y, hand_z [, held item size multiplier]
%macro SKMODEL_BEGIN 6-7 0
%push skmodel
%define %$name %1
%assign %$bones 0
%assign %$parts 0
global %1
align 8
%1:
    dq %1 %+ _recs
    dq %1 %+ _ops
    dw %2, %3, %4, %5, %6, %7
%1 %+ _recs:
%endmacro
; SKBONE kind, pivot_y, pivot_z, swing (a float literal, 0.0 for rigid)
%macro SKBONE 4
    db SKR_BONE, %1, 0, 0
    dw %2, %3
    dd %4
    times (SKREC_SIZE - 12) db 0
%assign %$bones %$bones + 1
%endmacro
; SKPART x0, y0, z0, w, h, d, grow, flags
%macro SKPART 8
%if %$bones == 0
%error "SKPART before the first SKBONE"
%endif
%if %$parts >= 254
%error "a skin model holds at most 254 parts"
%endif
    db SKR_PART, %8, %7, SKAS_NONE
    dw %1, %2, %3
    db %4, %5, %6, 0
    dw 0, 0, 0
%assign %$parts %$parts + 1
%endmacro
; SKPART_AS k, x0, y0, z0, grow, flags: shares part k's size and skin
%macro SKPART_AS 6
%if %$bones == 0
%error "SKPART_AS before the first SKBONE"
%endif
%if %$parts >= 254
%error "a skin model holds at most 254 parts"
%endif
%if %1 >= %$parts
%error "SKPART_AS: k must name an earlier part"
%endif
    db SKR_PART, %6, %5, %1
    dw %2, %3, %4
    db 0, 0, 0, 0
    dw 0, 0, 0
%assign %$parts %$parts + 1
%endmacro
%macro SKMODEL_PAINT 0
    db SKR_END
    times (SKREC_SIZE - 1) db 0
align 8
%$name %+ _ops:
%endmacro
; paint ops (k = part index)
%macro SK_FILL 4                        ; k, faces (SKM_*), colour, noise
%if %1 >= %$parts
%error "SK_FILL: part index out of range"
%endif
    db SKO_FILL, %1, %2, %4, 0, 0, 0, 0
    dd %3
    dd 0
    dq 0
%endmacro
%macro SK_RECT 8                        ; k, face (SKF_*), x, y, w, h, colour, noise
%if %1 >= %$parts
%error "SK_RECT: part index out of range"
%endif
    db SKO_RECT, %1, %2, %8, %3, %4, %5, %6
    dd %7
    dd 0
    dq 0
%endmacro
%macro SK_BMP 5                         ; k, face (SKF_*), x, y, SKBMP label
%if %1 >= %$parts
%error "SK_BMP: part index out of range"
%endif
    db SKO_BMP, %1, %2, 0, %3, %4, 0, 0
    dd 0
    dd 0
    dq %5
%endmacro
%macro SK_GRAD 4                        ; k, faces (SKM_*), top multiplier, bottom multiplier (256 = unchanged)
%if %1 >= %$parts
%error "SK_GRAD: part index out of range"
%endif
    db SKO_GRAD, %1, %2, 0, 0, 0, 0, 0
    dw %3, %4
    dd 0
    dq 0
%endmacro
%macro SKMODEL_END 0
    db SKO_END
    times (SKOP_SIZE - 1) db 0
%pop
%endmacro

; ---- material ramps (packed RGBO; 1 = highlight .. 4 = deepest), shared by icons, guns and vehicles ---
%define AC_WOOD_1    RGBO(196,150,92)
%define AC_WOOD_2    RGBO(156,112,62)
%define AC_WOOD_3    RGBO(112,78,42)
%define AC_WOOD_4    RGBO(72,48,26)
%define AC_STONE_1   RGBO(170,170,166)
%define AC_STONE_2   RGBO(128,128,124)
%define AC_STONE_3   RGBO(92,92,90)
%define AC_STONE_4   RGBO(60,60,60)
%define AC_IRON_1    RGBO(236,236,240)
%define AC_IRON_2    RGBO(196,198,204)
%define AC_IRON_3    RGBO(140,144,152)
%define AC_IRON_4    RGBO(84,88,96)
%define AC_GOLD_1    RGBO(255,240,140)
%define AC_GOLD_2    RGBO(240,196,56)
%define AC_GOLD_3    RGBO(190,138,24)
%define AC_GOLD_4    RGBO(120,80,16)
%define AC_DIAM_1    RGBO(200,255,250)
%define AC_DIAM_2    RGBO(90,220,210)
%define AC_DIAM_3    RGBO(40,160,160)
%define AC_DIAM_4    RGBO(20,96,104)
%define AC_LEATHER_1 RGBO(176,118,72)
%define AC_LEATHER_2 RGBO(134,84,48)
%define AC_LEATHER_3 RGBO(96,58,32)
%define AC_LEATHER_4 RGBO(62,36,20)
%define AC_MEAT_1    RGBO(250,170,170)
%define AC_MEAT_2    RGBO(226,112,112)
%define AC_MEAT_3    RGBO(176,64,72)
%define AC_MEAT_4    RGBO(120,36,48)
%define AC_COOKED_1  RGBO(214,140,80)
%define AC_COOKED_2  RGBO(170,96,48)
%define AC_COOKED_3  RGBO(120,60,30)
%define AC_COOKED_4  RGBO(80,38,20)
%define AC_FAT_1     RGBO(255,240,230)
%define AC_FAT_2     RGBO(240,214,200)
%define AC_BONE_1    RGBO(246,240,220)
%define AC_BONE_2    RGBO(214,204,176)
%define AC_BONE_3    RGBO(160,148,120)
%define AC_SKIN_1    RGBO(240,200,164)
%define AC_SKIN_2    RGBO(214,168,130)
%define AC_SKIN_3    RGBO(176,128,96)
%define AC_OUTLINE   RGBO(40,28,20)

%endif
