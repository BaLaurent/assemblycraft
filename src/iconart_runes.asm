; iconart_runes.asm - the 16 Rune item icons (32x32), part C... of the runes art: one slate stone per rune, the same rounded
; stone for all (outline 'o', body 'b', lit top-left edge 'h', shaded bottom-right edge 'd') with the rune's glyph in
; the middle: 'g' the glyph, 'i' its highlight, 'G' its drop shadow. Deliveries are gold, elements take their own colour
; (fire orange, frost ice blue, shock yellow, poison green), modifiers are violet and boons green.
;
; Data only, like iconart_a.asm and iconart_b.asm: icons.asm paints every SKBMP into the atlas cell of its item
; (icon k = item id - FIRST_ITEM, the runes follow PLANE) and artreg.asm lists the labels, ib_rune_<name>, in rune order.
%include "common.inc"
%include "art.inc"
default rel

section .rodata


; --------------------------------------------------------------------------------------------------------------------
; ib_rune_ball: the Ball Rune (RUNE_FIRST + RUNE_BALL)
; --------------------------------------------------------------------------------------------------------------------
align 8
rune_ball_pal:
    PALC 'o', RGBO(40,44,60)
    PALC 'h', RGBO(140,150,176)
    PALC 'b', RGBO(96,104,128)
    PALC 'd', RGBO(70,76,100)
    PALC 'g', RGBO(240,200,80)
    PALC 'i', RGBO(255,240,170)
    PALC 'G', RGBO(108,90,36)
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS rune_ball_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".......oooooooooooooooooo......."  ; 03
    SKROW "......ohhhhhhhhhhhhhhhhhho......"  ; 04
    SKROW ".....ohbbbbbbbbbbbbbbbbbbho....."  ; 05
    SKROW "....ohbbbbbbbbbbbbbbbbbbbbdo...."  ; 06
    SKROW "...ohbbbbbbbbbbbbbbbbbbbbbbdo..."  ; 07
    SKROW "...ohbbbbbbbbbbbbbbbbbbbbbbdo..."  ; 08
    SKROW "...ohbbbbbbbbbbbbbbbbbbbbbbdo..."  ; 09
    SKROW "...ohbbbbbbbbggggggbbbbbbbbdo..."  ; 10
    SKROW "...ohbbbbbbggigggggggbbbbbbdo..."  ; 11
    SKROW "...ohbbbbbbgiiiggggggGbbbbbdo..."  ; 12
    SKROW "...ohbbbbbgiiiiiggggggbbbbbdo..."  ; 13
    SKROW "...ohbbbbbggiiigggggggGbbbbdo..."  ; 14
    SKROW "...ohbbbbbgggiggggggggGbbbbdo..."  ; 15
    SKROW "...ohbbbbbggggggggggggGbbbbdo..."  ; 16
    SKROW "...ohbbbbbggggggggggggGbbbbdo..."  ; 17
    SKROW "...ohbbbbbggggggggggggGbbbbdo..."  ; 18
    SKROW "...ohbbbbbbggggggggggGGbbbbdo..."  ; 19
    SKROW "...ohbbbbbbggggggggggGbbbbbdo..."  ; 20
    SKROW "...ohbbbbbbbGggggggGGGbbbbbdo..."  ; 21
    SKROW "...ohbbbbbbbbbGGGGGGbbbbbbbdo..."  ; 22
    SKROW "...ohbbbbbbbbbbbbbbbbbbbbbbdo..."  ; 23
    SKROW "...ohbbbbbbbbbbbbbbbbbbbbbbdo..."  ; 24
    SKROW "....ohbbbbbbbbbbbbbbbbbbbbdo...."  ; 25
    SKROW ".....odbbbbbbbbbbbbbbbbbbdo....."  ; 26
    SKROW "......oddddddddddddddddddo......"  ; 27
    SKROW ".......oooooooooooooooooo......."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_rune_ball, rune_ball_rows, 32, 32, rune_ball_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_rune_laser: the Laser Rune (RUNE_FIRST + RUNE_LASER)
; --------------------------------------------------------------------------------------------------------------------
align 8
rune_laser_pal:
    PALC 'o', RGBO(40,44,60)
    PALC 'h', RGBO(140,150,176)
    PALC 'b', RGBO(96,104,128)
    PALC 'd', RGBO(70,76,100)
    PALC 'g', RGBO(240,200,80)
    PALC 'i', RGBO(255,240,170)
    PALC 'G', RGBO(108,90,36)
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS rune_laser_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".......oooooooooooooooooo......."  ; 03
    SKROW "......ohhhhhhhhhhhhhhhhhho......"  ; 04
    SKROW ".....ohbbbbbbbbbbbbbbbbbbho....."  ; 05
    SKROW "....ohbbbbbbbbbbbbbbbbbbbbdo...."  ; 06
    SKROW "...ohbbbbbbbbbbbbbbbbbbbbbbdo..."  ; 07
    SKROW "...ohbbbbbbbbbbbbbbbbbbbbbbdo..."  ; 08
    SKROW "...ohbbbbbbbbbbbbbbbbbbbbbbdo..."  ; 09
    SKROW "...ohbbbbbbbbbbbbbbbbbbbbbbdo..."  ; 10
    SKROW "...ohbbbbbbbbbbbbbbbbbbbbbbdo..."  ; 11
    SKROW "...ohbbbbbbbbbbbbbbgbbbbbbbdo..."  ; 12
    SKROW "...ohbbbbbbbbbbbbbbgggbbbbbdo..."  ; 13
    SKROW "...ohbgggggggggggggggggbbbbdo..."  ; 14
    SKROW "...ohggiiiiiiiiiiiiigggggbbdo..."  ; 15
    SKROW "...ohggggggggggggggggggggGbdo..."  ; 16
    SKROW "...ohbgggggggggggggggggGGGbdo..."  ; 17
    SKROW "...ohbbGGGGGGGGGGGGgggGGbbbdo..."  ; 18
    SKROW "...ohbbbbbbbbbbbbbbgGGGbbbbdo..."  ; 19
    SKROW "...ohbbbbbbbbbbbbbbbGbbbbbbdo..."  ; 20
    SKROW "...ohbbbbbbbbbbbbbbbbbbbbbbdo..."  ; 21
    SKROW "...ohbbbbbbbbbbbbbbbbbbbbbbdo..."  ; 22
    SKROW "...ohbbbbbbbbbbbbbbbbbbbbbbdo..."  ; 23
    SKROW "...ohbbbbbbbbbbbbbbbbbbbbbbdo..."  ; 24
    SKROW "....ohbbbbbbbbbbbbbbbbbbbbdo...."  ; 25
    SKROW ".....odbbbbbbbbbbbbbbbbbbdo....."  ; 26
    SKROW "......oddddddddddddddddddo......"  ; 27
    SKROW ".......oooooooooooooooooo......."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_rune_laser, rune_laser_rows, 32, 32, rune_laser_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_rune_nova: the Nova Rune (RUNE_FIRST + RUNE_NOVA)
; --------------------------------------------------------------------------------------------------------------------
align 8
rune_nova_pal:
    PALC 'o', RGBO(40,44,60)
    PALC 'h', RGBO(140,150,176)
    PALC 'b', RGBO(96,104,128)
    PALC 'd', RGBO(70,76,100)
    PALC 'g', RGBO(240,200,80)
    PALC 'i', RGBO(255,240,170)
    PALC 'G', RGBO(108,90,36)
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS rune_nova_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".......oooooooooooooooooo......."  ; 03
    SKROW "......ohhhhhhhhhhhhhhhhhho......"  ; 04
    SKROW ".....ohbbbbbbbbbbbbbbbbbbho....."  ; 05
    SKROW "....ohbbbbbbbbbbbbbbbbbbbbdo...."  ; 06
    SKROW "...ohbbbbbbbbbbbbbbbbbbbbbbdo..."  ; 07
    SKROW "...ohbbbbbbbbbbggbbbbbbbbbbdo..."  ; 08
    SKROW "...ohbbbbbbbbbbggGbbbbbbbbbdo..."  ; 09
    SKROW "...ohbbbbbbbbbbggGbbbbbbbbbdo..."  ; 10
    SKROW "...ohbbbbbbbgbbggGbgbbbbbbbdo..."  ; 11
    SKROW "...ohbbbbbbgggbggGgggbbbbbbdo..."  ; 12
    SKROW "...ohbbbbbbbggggggggGGbbbbbdo..."  ; 13
    SKROW "...ohbbbbbbbbggggggGGbbbbbbdo..."  ; 14
    SKROW "...ohbbbgggggggiigggggggbbbdo..."  ; 15
    SKROW "...ohbbbgggggggiigggggggGbbdo..."  ; 16
    SKROW "...ohbbbbGGGGggggggGGGGGGbbdo..."  ; 17
    SKROW "...ohbbbbbbbggggggggbbbbbbbdo..."  ; 18
    SKROW "...ohbbbbbbgggGggGgggbbbbbbdo..."  ; 19
    SKROW "...ohbbbbbbbgGGggGbgGGbbbbbdo..."  ; 20
    SKROW "...ohbbbbbbbbGbggGbbGbbbbbbdo..."  ; 21
    SKROW "...ohbbbbbbbbbbggGbbbbbbbbbdo..."  ; 22
    SKROW "...ohbbbbbbbbbbggGbbbbbbbbbdo..."  ; 23
    SKROW "...ohbbbbbbbbbbbGGbbbbbbbbbdo..."  ; 24
    SKROW "....ohbbbbbbbbbbbbbbbbbbbbdo...."  ; 25
    SKROW ".....odbbbbbbbbbbbbbbbbbbdo....."  ; 26
    SKROW "......oddddddddddddddddddo......"  ; 27
    SKROW ".......oooooooooooooooooo......."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_rune_nova, rune_nova_rows, 32, 32, rune_nova_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_rune_phase: the Phase Rune (RUNE_FIRST + RUNE_PHASE)
; --------------------------------------------------------------------------------------------------------------------
align 8
rune_phase_pal:
    PALC 'o', RGBO(40,44,60)
    PALC 'h', RGBO(140,150,176)
    PALC 'b', RGBO(96,104,128)
    PALC 'd', RGBO(70,76,100)
    PALC 'g', RGBO(240,200,80)
    PALC 'i', RGBO(255,240,170)
    PALC 'G', RGBO(108,90,36)
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS rune_phase_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".......oooooooooooooooooo......."  ; 03
    SKROW "......ohhhhhhhhhhhhhhhhhho......"  ; 04
    SKROW ".....ohbbbbbbbbbbbbbbbbbbho....."  ; 05
    SKROW "....ohbbbbbbbbbbbbbbbbbbbbdo...."  ; 06
    SKROW "...ohbbbggggggbbbbbbbbbbbbbdo..."  ; 07
    SKROW "...ohbbggggggggbbbbbbbbbbbbdo..."  ; 08
    SKROW "...ohbgggGGGGgggbbbbbbbbbbbdo..."  ; 09
    SKROW "...ohbggGGbbbbggGbbbbbbbbbbdo..."  ; 10
    SKROW "...ohbggGbbbbbggGbbbbbbbbbbdo..."  ; 11
    SKROW "...ohbggGbbbbbggGbbbbbbbbbbdo..."  ; 12
    SKROW "...ohbggGbbbbbggGbbbbbbbbbbdo..."  ; 13
    SKROW "...ohbgggbbbbgggGbbbbbbbbbbdo..."  ; 14
    SKROW "...ohbbggggggggggbggggggbbbdo..."  ; 15
    SKROW "...ohbbbggggggGggggggggggbbdo..."  ; 16
    SKROW "...ohbbbbGGGGGGbgggGGGGgggbdo..."  ; 17
    SKROW "...ohbbbbbbbbbbbggGGbbbbggGdo..."  ; 18
    SKROW "...ohbbbbbbbbbbbggGbbbbbggGdo..."  ; 19
    SKROW "...ohbbbbbbbbbbbggGbbbbbggGdo..."  ; 20
    SKROW "...ohbbbbbbbbbbbggGbbbbbggGdo..."  ; 21
    SKROW "...ohbbbbbbbbbbbgggbbbbgggGdo..."  ; 22
    SKROW "...ohbbbbbbbbbbbbggggggggGGdo..."  ; 23
    SKROW "...ohbbbbbbbbbbbbbggggggGGbdo..."  ; 24
    SKROW "....ohbbbbbbbbbbbbbGGGGGGbdo...."  ; 25
    SKROW ".....odbbbbbbbbbbbbbbbbbbdo....."  ; 26
    SKROW "......oddddddddddddddddddo......"  ; 27
    SKROW ".......oooooooooooooooooo......."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_rune_phase, rune_phase_rows, 32, 32, rune_phase_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_rune_dash: the Dash Rune (RUNE_FIRST + RUNE_DASH)
; --------------------------------------------------------------------------------------------------------------------
align 8
rune_dash_pal:
    PALC 'o', RGBO(40,44,60)
    PALC 'h', RGBO(140,150,176)
    PALC 'b', RGBO(96,104,128)
    PALC 'd', RGBO(70,76,100)
    PALC 'g', RGBO(240,200,80)
    PALC 'i', RGBO(255,240,170)
    PALC 'G', RGBO(108,90,36)
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS rune_dash_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".......oooooooooooooooooo......."  ; 03
    SKROW "......ohhhhhhhhhhhhhhhhhho......"  ; 04
    SKROW ".....ohbbbbbbbbbbbbbbbbbbho....."  ; 05
    SKROW "....ohbbbbbbbbbbbbbbbbbbbbdo...."  ; 06
    SKROW "...ohbbbbbbbbbbbbbbbbbbbbbbdo..."  ; 07
    SKROW "...ohggbbbbggbbbbggbbbbbbbbdo..."  ; 08
    SKROW "...ohgggbbbgggbbbgggbbbbbbbdo..."  ; 09
    SKROW "...ohbgggbbbgggbbbgggbbbbbbdo..."  ; 10
    SKROW "...ohbbgggbbbgggbbbgggbbbbbdo..."  ; 11
    SKROW "...ohbbbgggbbbgggbbbgggbbbbdo..."  ; 12
    SKROW "...ohbbbbgggbbbgggbbbgggbbbdo..."  ; 13
    SKROW "...ohbbbbbgggbbbgggbbbgggbbdo..."  ; 14
    SKROW "...ohbbbbbbgggbbbgggbbbgggbdo..."  ; 15
    SKROW "...ohbbbbbbgggGbbgggGbbgggGdo..."  ; 16
    SKROW "...ohbbbbbgggGGbgggGGbgggGGdo..."  ; 17
    SKROW "...ohbbbbgggGGbgggGGbgggGGbdo..."  ; 18
    SKROW "...ohbbbgggGGbgggGGbgggGGbbdo..."  ; 19
    SKROW "...ohbbgggGGbgggGGbgggGGbbbdo..."  ; 20
    SKROW "...ohbgggGGbgggGGbgggGGbbbbdo..."  ; 21
    SKROW "...ohgggGGbgggGGbgggGGbbbbbdo..."  ; 22
    SKROW "...ohggGGbbggGGbbggGGbbbbbbdo..."  ; 23
    SKROW "...ohbGGbbbbGGbbbbGGbbbbbbbdo..."  ; 24
    SKROW "....ohbbbbbbbbbbbbbbbbbbbbdo...."  ; 25
    SKROW ".....odbbbbbbbbbbbbbbbbbbdo....."  ; 26
    SKROW "......oddddddddddddddddddo......"  ; 27
    SKROW ".......oooooooooooooooooo......."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_rune_dash, rune_dash_rows, 32, 32, rune_dash_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_rune_fire: the Fire Rune (RUNE_FIRST + RUNE_FIRE)
; --------------------------------------------------------------------------------------------------------------------
align 8
rune_fire_pal:
    PALC 'o', RGBO(40,44,60)
    PALC 'h', RGBO(140,150,176)
    PALC 'b', RGBO(96,104,128)
    PALC 'd', RGBO(70,76,100)
    PALC 'g', RGBO(255,140,40)
    PALC 'i', RGBO(255,222,100)
    PALC 'G', RGBO(114,63,18)
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS rune_fire_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".......oooooooooooooooooo......."  ; 03
    SKROW "......ohhhhhhhhhhhhhhhhhho......"  ; 04
    SKROW ".....ohbbbbbbbbbbbbbbbbbbho....."  ; 05
    SKROW "....ohbbbbbbbbbbbbbbbbbbbbdo...."  ; 06
    SKROW "...ohbbbbbbbbbbbbbbbbbbbbbbdo..."  ; 07
    SKROW "...ohbbbbbbbbbbggbbbbbbbbbbdo..."  ; 08
    SKROW "...ohbbbbbbbbbbggGbbbbbbbbbdo..."  ; 09
    SKROW "...ohbbbbbbbbbggggbbbbbbbbbdo..."  ; 10
    SKROW "...ohbbbbbbbgbggggGbbbbbbbbdo..."  ; 11
    SKROW "...ohbbbbbbbgggggggbbbbbbbbdo..."  ; 12
    SKROW "...ohbbbbbbbggggggggbbbbbbbdo..."  ; 13
    SKROW "...ohbbbbbbgggggggggGbbbbbbdo..."  ; 14
    SKROW "...ohbbbbbbggggiiggggbbbbbbdo..."  ; 15
    SKROW "...ohbbbbbbggggiiggggGbbbbbdo..."  ; 16
    SKROW "...ohbbbbbbgggiiiigggGbbbbbdo..."  ; 17
    SKROW "...ohbbbbbbgggiiiigggGbbbbbdo..."  ; 18
    SKROW "...ohbbbbbbggiiiiiiggGbbbbbdo..."  ; 19
    SKROW "...ohbbbbbbggiiiiiiggGbbbbbdo..."  ; 20
    SKROW "...ohbbbbbbgggiiiigggGbbbbbdo..."  ; 21
    SKROW "...ohbbbbbbbgggiigggGGbbbbbdo..."  ; 22
    SKROW "...ohbbbbbbbbggggggGGbbbbbbdo..."  ; 23
    SKROW "...ohbbbbbbbbbGGGGGGbbbbbbbdo..."  ; 24
    SKROW "....ohbbbbbbbbbbbbbbbbbbbbdo...."  ; 25
    SKROW ".....odbbbbbbbbbbbbbbbbbbdo....."  ; 26
    SKROW "......oddddddddddddddddddo......"  ; 27
    SKROW ".......oooooooooooooooooo......."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_rune_fire, rune_fire_rows, 32, 32, rune_fire_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_rune_frost: the Frost Rune (RUNE_FIRST + RUNE_FROST)
; --------------------------------------------------------------------------------------------------------------------
align 8
rune_frost_pal:
    PALC 'o', RGBO(40,44,60)
    PALC 'h', RGBO(140,150,176)
    PALC 'b', RGBO(96,104,128)
    PALC 'd', RGBO(70,76,100)
    PALC 'g', RGBO(150,210,255)
    PALC 'i', RGBO(225,245,255)
    PALC 'G', RGBO(67,94,114)
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS rune_frost_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".......oooooooooooooooooo......."  ; 03
    SKROW "......ohhhhhhhhhhhhhhhhhho......"  ; 04
    SKROW ".....ohbbbbbbbbbbbbbbbbbbho....."  ; 05
    SKROW "....ohbbbbbbbbbbbbbbbbbbbbdo...."  ; 06
    SKROW "...ohbbbbbbbbbbbbbbbbbbbbbbdo..."  ; 07
    SKROW "...ohbbbbbbgggbbbbgggbbbbbbdo..."  ; 08
    SKROW "...ohbbbbbbgggGbbbgggGbbbbbdo..."  ; 09
    SKROW "...ohbbbbbggggGbbbggggbbbbbdo..."  ; 10
    SKROW "...ohbbbbbbGggGbbbggGGGbbbbdo..."  ; 11
    SKROW "...ohbbbbbbbbggbbggGGbbbbbbdo..."  ; 12
    SKROW "...ohbbbbbbbbbgGbgGGbbbbbbbdo..."  ; 13
    SKROW "...ohbbbgbbbbbgiigGbbbbgbbbdo..."  ; 14
    SKROW "...ohbbgggggggiiiigggggggbbdo..."  ; 15
    SKROW "...ohbbgggggggiiiigggggggGbdo..."  ; 16
    SKROW "...ohbbbgGGGGGgiigGGGGGgGGbdo..."  ; 17
    SKROW "...ohbbbbGbbbbgGGgGbbbbbGbbdo..."  ; 18
    SKROW "...ohbbbbbbbbggGbggbbbbbbbbdo..."  ; 19
    SKROW "...ohbbbbbbbggGGbbggbbbbbbbdo..."  ; 20
    SKROW "...ohbbbbbggggGbbbggggbbbbbdo..."  ; 21
    SKROW "...ohbbbbbbgggGbbbgggGGbbbbdo..."  ; 22
    SKROW "...ohbbbbbbgggGbbbgggGbbbbbdo..."  ; 23
    SKROW "...ohbbbbbbbGGGbbbbGGGbbbbbdo..."  ; 24
    SKROW "....ohbbbbbbbbbbbbbbbbbbbbdo...."  ; 25
    SKROW ".....odbbbbbbbbbbbbbbbbbbdo....."  ; 26
    SKROW "......oddddddddddddddddddo......"  ; 27
    SKROW ".......oooooooooooooooooo......."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_rune_frost, rune_frost_rows, 32, 32, rune_frost_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_rune_shock: the Shock Rune (RUNE_FIRST + RUNE_SHOCK)
; --------------------------------------------------------------------------------------------------------------------
align 8
rune_shock_pal:
    PALC 'o', RGBO(40,44,60)
    PALC 'h', RGBO(140,150,176)
    PALC 'b', RGBO(96,104,128)
    PALC 'd', RGBO(70,76,100)
    PALC 'g', RGBO(255,240,90)
    PALC 'i', RGBO(255,255,200)
    PALC 'G', RGBO(114,108,40)
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS rune_shock_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".......oooooooooooooooooo......."  ; 03
    SKROW "......ohhhhhhhhhhhhhhhhhho......"  ; 04
    SKROW ".....ohbbbbbbbbbbbbbbbbbbho....."  ; 05
    SKROW "....ohbbbbbbbbbbbbbbbbbbbbdo...."  ; 06
    SKROW "...ohbbbbbbbbbbbbbbggbbbbbbdo..."  ; 07
    SKROW "...ohbbbbbbbbbbbbbggGGbbbbbdo..."  ; 08
    SKROW "...ohbbbbbbbbbbbbgggGbbbbbbdo..."  ; 09
    SKROW "...ohbbbbbbbbbbbgigGGbbbbbbdo..."  ; 10
    SKROW "...ohbbbbbbbbbbgiiGGbbbbbbbdo..."  ; 11
    SKROW "...ohbbbbbbbbbggiiibbbbbbbbdo..."  ; 12
    SKROW "...ohbbbbbbbbggiiiiGbbbbbbbdo..."  ; 13
    SKROW "...ohbbbbbbbbgiiiiigggbbbbbdo..."  ; 14
    SKROW "...ohbbbbbbbggggiigggGGbbbbdo..."  ; 15
    SKROW "...ohbbbbbbgggggigggGGbbbbbdo..."  ; 16
    SKROW "...ohbbbbbbbGGGgiggGGbbbbbbdo..."  ; 17
    SKROW "...ohbbbbbbbbbbgggGGbbbbbbbdo..."  ; 18
    SKROW "...ohbbbbbbbbbbggGGbbbbbbbbdo..."  ; 19
    SKROW "...ohbbbbbbbbbgggGbbbbbbbbbdo..."  ; 20
    SKROW "...ohbbbbbbbbbggGGbbbbbbbbbdo..."  ; 21
    SKROW "...ohbbbbbbbbggGGbbbbbbbbbbdo..."  ; 22
    SKROW "...ohbbbbbbbbgGGbbbbbbbbbbbdo..."  ; 23
    SKROW "...ohbbbbbbbbbGbbbbbbbbbbbbdo..."  ; 24
    SKROW "....ohbbbbbbbbbbbbbbbbbbbbdo...."  ; 25
    SKROW ".....odbbbbbbbbbbbbbbbbbbdo....."  ; 26
    SKROW "......oddddddddddddddddddo......"  ; 27
    SKROW ".......oooooooooooooooooo......."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_rune_shock, rune_shock_rows, 32, 32, rune_shock_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_rune_poison: the Poison Rune (RUNE_FIRST + RUNE_POISON)
; --------------------------------------------------------------------------------------------------------------------
align 8
rune_poison_pal:
    PALC 'o', RGBO(40,44,60)
    PALC 'h', RGBO(140,150,176)
    PALC 'b', RGBO(96,104,128)
    PALC 'd', RGBO(70,76,100)
    PALC 'g', RGBO(110,230,80)
    PALC 'i', RGBO(190,255,150)
    PALC 'G', RGBO(49,103,36)
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS rune_poison_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".......oooooooooooooooooo......."  ; 03
    SKROW "......ohhhhhhhhhhhhhhhhhho......"  ; 04
    SKROW ".....ohbbbbbbbbbbbbbbbbbbho....."  ; 05
    SKROW "....ohbbbbbbbbbbbbbbbbbbbbdo...."  ; 06
    SKROW "...ohbbbbbbbbbbbbbbbbbbbbbbdo..."  ; 07
    SKROW "...ohbbbbbbbbbbggbbbbbbbbbbdo..."  ; 08
    SKROW "...ohbbbbbbbbbbggGbbbbbbbbbdo..."  ; 09
    SKROW "...ohbbbbbbbbbggggbbbbbbbbbdo..."  ; 10
    SKROW "...ohbbbbbbbbbggggGbbbbbbbbdo..."  ; 11
    SKROW "...ohbbbbbbbbggggggbbbbbbbbdo..."  ; 12
    SKROW "...ohbbbbbbbbggggggGbbbbbbbdo..."  ; 13
    SKROW "...ohbbbbbbbggggggggbbbbbbbdo..."  ; 14
    SKROW "...ohbbbbbbbggggggggGbbbbbbdo..."  ; 15
    SKROW "...ohbbbbbbggiiggggggbbbbbbdo..."  ; 16
    SKROW "...ohbbbbbbgiiiigggggGbbbbbdo..."  ; 17
    SKROW "...ohbbbbbbgiiiigggggGbbbbbdo..."  ; 18
    SKROW "...ohbbbbbbggiiggggggGbbbbbdo..."  ; 19
    SKROW "...ohbbbbbbggggggggggGbbbbbdo..."  ; 20
    SKROW "...ohbbbbbbggggggggggGbbbbbdo..."  ; 21
    SKROW "...ohbbbbbbbggggggggGGbbbbbdo..."  ; 22
    SKROW "...ohbbbbbbbbggggggGGbbbbbbdo..."  ; 23
    SKROW "...ohbbbbbbbbbGGGGGGbbbbbbbdo..."  ; 24
    SKROW "....ohbbbbbbbbbbbbbbbbbbbbdo...."  ; 25
    SKROW ".....odbbbbbbbbbbbbbbbbbbdo....."  ; 26
    SKROW "......oddddddddddddddddddo......"  ; 27
    SKROW ".......oooooooooooooooooo......."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_rune_poison, rune_poison_rows, 32, 32, rune_poison_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_rune_burst: the Burst Rune (RUNE_FIRST + RUNE_BURST)
; --------------------------------------------------------------------------------------------------------------------
align 8
rune_burst_pal:
    PALC 'o', RGBO(40,44,60)
    PALC 'h', RGBO(140,150,176)
    PALC 'b', RGBO(96,104,128)
    PALC 'd', RGBO(70,76,100)
    PALC 'g', RGBO(190,120,255)
    PALC 'i', RGBO(225,190,255)
    PALC 'G', RGBO(85,54,114)
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS rune_burst_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".......oooooooooooooooooo......."  ; 03
    SKROW "......ohhhhhhhhhhhhhhhhhho......"  ; 04
    SKROW ".....ohbbbbbbbbbbbbbbbbbbho....."  ; 05
    SKROW "....ohbbbbbbbbbggbbbbbbbbbdo...."  ; 06
    SKROW "...ohbbbbbbbbbbggGbbbbbbbbbdo..."  ; 07
    SKROW "...ohbbbbbbbbbbggGbbbbbbbbbdo..."  ; 08
    SKROW "...ohbbbbggbbbbggGbbbggbbbbdo..."  ; 09
    SKROW "...ohbbbbgggbbbggGbbgggGbbbdo..."  ; 10
    SKROW "...ohbbbbbggGggggggbggGGbbbdo..."  ; 11
    SKROW "...ohbbbbbbGggggggggbGGbbbbdo..."  ; 12
    SKROW "...ohbbbbbbgggGGGGgggbbbbbbdo..."  ; 13
    SKROW "...ohbbbbbbggGGbbbbggGbbbbbdo..."  ; 14
    SKROW "...ohbgggggggGbiibbgggggggbdo..."  ; 15
    SKROW "...ohbgggggggGbiiGbgggggggGdo..."  ; 16
    SKROW "...ohbbGGGGggGbbGGbggGGGGGGdo..."  ; 17
    SKROW "...ohbbbbbbgggbbbbgggGbbbbbdo..."  ; 18
    SKROW "...ohbbbbbbbggggggggGGbbbbbdo..."  ; 19
    SKROW "...ohbbbbbggbggggggGggbbbbbdo..."  ; 20
    SKROW "...ohbbbbgggGbGggGGGgggbbbbdo..."  ; 21
    SKROW "...ohbbbbggGGbbggGbbbggGbbbdo..."  ; 22
    SKROW "...ohbbbbbGGbbbggGbbbbGGbbbdo..."  ; 23
    SKROW "...ohbbbbbbbbbbggGbbbbbbbbbdo..."  ; 24
    SKROW "....ohbbbbbbbbbggGbbbbbbbbdo...."  ; 25
    SKROW ".....odbbbbbbbbbGGbbbbbbbdo....."  ; 26
    SKROW "......oddddddddddddddddddo......"  ; 27
    SKROW ".......oooooooooooooooooo......."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_rune_burst, rune_burst_rows, 32, 32, rune_burst_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_rune_pierce: the Pierce Rune (RUNE_FIRST + RUNE_PIERCE)
; --------------------------------------------------------------------------------------------------------------------
align 8
rune_pierce_pal:
    PALC 'o', RGBO(40,44,60)
    PALC 'h', RGBO(140,150,176)
    PALC 'b', RGBO(96,104,128)
    PALC 'd', RGBO(70,76,100)
    PALC 'g', RGBO(190,120,255)
    PALC 'i', RGBO(225,190,255)
    PALC 'G', RGBO(85,54,114)
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS rune_pierce_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".......oooooooooooooooooo......."  ; 03
    SKROW "......ohhhhhhhhhhhhhhhhhho......"  ; 04
    SKROW ".....ohbbbbbbbbbbbbbbbbbbho....."  ; 05
    SKROW "....ohbbbbbbbbbbbbgggbbbbbdo...."  ; 06
    SKROW "...ohbbbbbbbbbbbbbgggGbbbbbdo..."  ; 07
    SKROW "...ohbbbbbbbbbbbbbgggGbbbbbdo..."  ; 08
    SKROW "...ohbbbbbbbbbbbbbgggGbbbbbdo..."  ; 09
    SKROW "...ohbbbbbbbbbbbbbgggGbbbbbdo..."  ; 10
    SKROW "...ohbbbbbbbbbbbbbgggGbbbbbdo..."  ; 11
    SKROW "...ohbbbbbbbbbbbbbggggbbbbbdo..."  ; 12
    SKROW "...ohbbbbbbbbbbbbbgggggbbbbdo..."  ; 13
    SKROW "...ohbbbbbbbbbbbbbgggggggbbdo..."  ; 14
    SKROW "...oggiiiiiiiiiiiiggggggggbdo..."  ; 15
    SKROW "...oggggggggggggggggggggggGdo..."  ; 16
    SKROW "...ohGGGGGGGGGGGGGgggggggGGdo..."  ; 17
    SKROW "...ohbbbbbbbbbbbbbgggggGGGbdo..."  ; 18
    SKROW "...ohbbbbbbbbbbbbbggggGGbbbdo..."  ; 19
    SKROW "...ohbbbbbbbbbbbbbgggGGbbbbdo..."  ; 20
    SKROW "...ohbbbbbbbbbbbbbgggGbbbbbdo..."  ; 21
    SKROW "...ohbbbbbbbbbbbbbgggGbbbbbdo..."  ; 22
    SKROW "...ohbbbbbbbbbbbbbgggGbbbbbdo..."  ; 23
    SKROW "...ohbbbbbbbbbbbbbgggGbbbbbdo..."  ; 24
    SKROW "....ohbbbbbbbbbbbbgggGbbbbdo...."  ; 25
    SKROW ".....odbbbbbbbbbbbbGGGbbbdo....."  ; 26
    SKROW "......oddddddddddddddddddo......"  ; 27
    SKROW ".......oooooooooooooooooo......."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_rune_pierce, rune_pierce_rows, 32, 32, rune_pierce_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_rune_seek: the Seek Rune (RUNE_FIRST + RUNE_SEEK)
; --------------------------------------------------------------------------------------------------------------------
align 8
rune_seek_pal:
    PALC 'o', RGBO(40,44,60)
    PALC 'h', RGBO(140,150,176)
    PALC 'b', RGBO(96,104,128)
    PALC 'd', RGBO(70,76,100)
    PALC 'g', RGBO(190,120,255)
    PALC 'i', RGBO(225,190,255)
    PALC 'G', RGBO(85,54,114)
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS rune_seek_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".......oooooooooooooooooo......."  ; 03
    SKROW "......ohhhhhhhhhhhhhhhhhho......"  ; 04
    SKROW ".....ohbbbbbbbbbbbbbbbbbbho....."  ; 05
    SKROW "....ohbbbbbbbbbbbbbbggbbbbdo...."  ; 06
    SKROW "...ohbbbbbbbbbbbbbbbgggbbbbdo..."  ; 07
    SKROW "...ohbbbbbbbbbbbbbbbggggbbbdo..."  ; 08
    SKROW "...ohbbbbbbbbbgggggggggggbbdo..."  ; 09
    SKROW "...ohbbbbbbbgggggggggggggGbdo..."  ; 10
    SKROW "...ohbbbbbgggggGGGGggggGGGbdo..."  ; 11
    SKROW "...ohbbbbggggGGGbbbggGGGbbbdo..."  ; 12
    SKROW "...ohbbbbgggGGbbbbbbGGbbbbbdo..."  ; 13
    SKROW "...ohbbbgggGGbbbbbbbbbbbbbbdo..."  ; 14
    SKROW "...ohbbbggGGbbbbbbbbbbbbbbbdo..."  ; 15
    SKROW "...ohbbgggGbbbbbbbbbbbbbbbbdo..."  ; 16
    SKROW "...ohbbggGGbbbbbbbbbbbbbbbbdo..."  ; 17
    SKROW "...ohbbggGbbbbbbbbbbbbbbbbbdo..."  ; 18
    SKROW "...ohbgggGbbbbbbbbbbbbbbbbbdo..."  ; 19
    SKROW "...ohbggGGbbbbbbbbbbbbbbbbbdo..."  ; 20
    SKROW "...ohbggGbbbbbbbbbbbbbbbbbbdo..."  ; 21
    SKROW "...ohbiiGbbbbbbbbbbbbbbbbbbdo..."  ; 22
    SKROW "...ohbiiGbbbbbbbbbbbbbbbbbbdo..."  ; 23
    SKROW "...ohbbGGbbbbbbbbbbbbbbbbbbdo..."  ; 24
    SKROW "....ohbbbbbbbbbbbbbbbbbbbbdo...."  ; 25
    SKROW ".....odbbbbbbbbbbbbbbbbbbdo....."  ; 26
    SKROW "......oddddddddddddddddddo......"  ; 27
    SKROW ".......oooooooooooooooooo......."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_rune_seek, rune_seek_rows, 32, 32, rune_seek_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_rune_chain: the Chain Rune (RUNE_FIRST + RUNE_CHAIN)
; --------------------------------------------------------------------------------------------------------------------
align 8
rune_chain_pal:
    PALC 'o', RGBO(40,44,60)
    PALC 'h', RGBO(140,150,176)
    PALC 'b', RGBO(96,104,128)
    PALC 'd', RGBO(70,76,100)
    PALC 'g', RGBO(190,120,255)
    PALC 'i', RGBO(225,190,255)
    PALC 'G', RGBO(85,54,114)
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS rune_chain_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".......oooooooooooooooooo......."  ; 03
    SKROW "......ohhhhhhhhhhhhhhhhhho......"  ; 04
    SKROW ".....ohbbbbbbbbbbbbbbbbbbho....."  ; 05
    SKROW "....ohbbbbbbbbbbbbbbbbbbbbdo...."  ; 06
    SKROW "...ohbbbbbbbbbbbbbbbbbbbbbbdo..."  ; 07
    SKROW "...ohbbbbbbbbbggggbbbbbbbbbdo..."  ; 08
    SKROW "...ohbbbbbbbbggggggbbbbbbbbdo..."  ; 09
    SKROW "...ohbbbbbbbgggGGgggbbbbbbbdo..."  ; 10
    SKROW "...ohbbbbbbbggGiibggGbbbbbbdo..."  ; 11
    SKROW "...ohbbbbbbbggGiiGggGbbbbbbdo..."  ; 12
    SKROW "...ohbbbbbbbgggbGgggGbbbbbbdo..."  ; 13
    SKROW "...ohbbbbbbbbggggggGGbbbbbbdo..."  ; 14
    SKROW "...ohbbbbbbbggggggggbbbbbbbdo..."  ; 15
    SKROW "...ohbbggggggGGGGGGggggggbbdo..."  ; 16
    SKROW "...ohbggggggGGbbbbbbggggggbdo..."  ; 17
    SKROW "...ohgggGGgggbbbbbbgggGGgggdo..."  ; 18
    SKROW "...ohggGiibggGbbbbbggGiibggGo..."  ; 19
    SKROW "...ohggGiiGggGbbbbbggGiiGggGo..."  ; 20
    SKROW "...ohgggbGgggGbbbbbgggbGgggGo..."  ; 21
    SKROW "...ohbggggggGGbbbbbbggggggGGo..."  ; 22
    SKROW "...ohbbggggGGbbbbbbbbggggGGdo..."  ; 23
    SKROW "...ohbbbGGGGbbbbbbbbbbGGGGbdo..."  ; 24
    SKROW "....ohbbbbbbbbbbbbbbbbbbbbdo...."  ; 25
    SKROW ".....odbbbbbbbbbbbbbbbbbbdo....."  ; 26
    SKROW "......oddddddddddddddddddo......"  ; 27
    SKROW ".......oooooooooooooooooo......."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_rune_chain, rune_chain_rows, 32, 32, rune_chain_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_rune_heal: the Heal Rune (RUNE_FIRST + RUNE_HEAL)
; --------------------------------------------------------------------------------------------------------------------
align 8
rune_heal_pal:
    PALC 'o', RGBO(40,44,60)
    PALC 'h', RGBO(140,150,176)
    PALC 'b', RGBO(96,104,128)
    PALC 'd', RGBO(70,76,100)
    PALC 'g', RGBO(120,230,140)
    PALC 'i', RGBO(200,255,210)
    PALC 'G', RGBO(54,103,63)
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS rune_heal_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".......oooooooooooooooooo......."  ; 03
    SKROW "......ohhhhhhhhhhhhhhhhhho......"  ; 04
    SKROW ".....ohbbbbbbbbbbbbbbbbbbho....."  ; 05
    SKROW "....ohbbbbbbbbggggbbbbbbbbdo...."  ; 06
    SKROW "...ohbbbbbbbbbggggGbbbbbbbbdo..."  ; 07
    SKROW "...ohbbbbbbbbbggggGbbbbbbbbdo..."  ; 08
    SKROW "...ohbbbbbbbbbgiigGbbbbbbbbdo..."  ; 09
    SKROW "...ohbbbbbbbbbgiigGbbbbbbbbdo..."  ; 10
    SKROW "...ohbbbbbbbbbgiigGbbbbbbbbdo..."  ; 11
    SKROW "...ohbbbbbbbbbgiigGbbbbbbbbdo..."  ; 12
    SKROW "...ohbbbbbbbbbgiigGbbbbbbbbdo..."  ; 13
    SKROW "...ohbgggggggggiigggggggggbdo..."  ; 14
    SKROW "...ohbggggggggggggggggggggGdo..."  ; 15
    SKROW "...ohbggggggggggggggggggggGdo..."  ; 16
    SKROW "...ohbggggggggggggggggggggGdo..."  ; 17
    SKROW "...ohbbGGGGGGGggggGGGGGGGGGdo..."  ; 18
    SKROW "...ohbbbbbbbbbggggGbbbbbbbbdo..."  ; 19
    SKROW "...ohbbbbbbbbbggggGbbbbbbbbdo..."  ; 20
    SKROW "...ohbbbbbbbbbggggGbbbbbbbbdo..."  ; 21
    SKROW "...ohbbbbbbbbbggggGbbbbbbbbdo..."  ; 22
    SKROW "...ohbbbbbbbbbggggGbbbbbbbbdo..."  ; 23
    SKROW "...ohbbbbbbbbbggggGbbbbbbbbdo..."  ; 24
    SKROW "....ohbbbbbbbbggggGbbbbbbbdo...."  ; 25
    SKROW ".....odbbbbbbbbGGGGbbbbbbdo....."  ; 26
    SKROW "......oddddddddddddddddddo......"  ; 27
    SKROW ".......oooooooooooooooooo......."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_rune_heal, rune_heal_rows, 32, 32, rune_heal_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_rune_haste: the Haste Rune (RUNE_FIRST + RUNE_HASTE)
; --------------------------------------------------------------------------------------------------------------------
align 8
rune_haste_pal:
    PALC 'o', RGBO(40,44,60)
    PALC 'h', RGBO(140,150,176)
    PALC 'b', RGBO(96,104,128)
    PALC 'd', RGBO(70,76,100)
    PALC 'g', RGBO(120,230,140)
    PALC 'i', RGBO(200,255,210)
    PALC 'G', RGBO(54,103,63)
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS rune_haste_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".......oooooooooooooooooo......."  ; 03
    SKROW "......ohhhhhhhhhhhhhhhhhho......"  ; 04
    SKROW ".....ohbbbbbbbbbbbbbbbbbbho....."  ; 05
    SKROW "....ohbbbbbbbbbbbbbbbbbbbbdo...."  ; 06
    SKROW "...ggbbbbbbbbbbbbbbbbbbbbbbdo..."  ; 07
    SKROW "...gggbbbbbbgggggbbbbbbbbbbdo..."  ; 08
    SKROW "...oGgggbbbbiiiiiGbbbbbbbbbdo..."  ; 09
    SKROW "...ohbGgggbbiiiiiGbbbbbbbbbdo..."  ; 10
    SKROW "...ohbbbGggggggggGbbbbbbbbbdo..."  ; 11
    SKROW "...ggbbbbbgggggggGbbbbbbbbbdo..."  ; 12
    SKROW "...gggggbbbGgggggGbbbbbbbbbdo..."  ; 13
    SKROW "...oGGgggggggggggGbbbbbbbbbdo..."  ; 14
    SKROW "...ohbbGGGgggggggGbbbbbbbbbdo..."  ; 15
    SKROW "...ohbbbbbbGgggggGbbbbbbbbbdo..."  ; 16
    SKROW "...ohbbgggggggggggbbbbbbbbbdo..."  ; 17
    SKROW "...ogggggggggggggggggbbbbbbdo..."  ; 18
    SKROW "...ohGGGGGGGggggggggggggbbbdo..."  ; 19
    SKROW "...ohbbbbbbbggggggggggggGbbdo..."  ; 20
    SKROW "...ohbbbbbbbggggggggggggGbbdo..."  ; 21
    SKROW "...ohbbbbbbbggggggggggggGbbdo..."  ; 22
    SKROW "...ohbbbbbbbggggggggggggGbbdo..."  ; 23
    SKROW "...ohbbbbbbbbGGGGGGGGGGGGbbdo..."  ; 24
    SKROW "....ohbbbbbbbbbbbbbbbbbbbbdo...."  ; 25
    SKROW ".....odbbbbbbbbbbbbbbbbbbdo....."  ; 26
    SKROW "......oddddddddddddddddddo......"  ; 27
    SKROW ".......oooooooooooooooooo......."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_rune_haste, rune_haste_rows, 32, 32, rune_haste_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_rune_feather: the Feather Rune (RUNE_FIRST + RUNE_FEATHER)
; --------------------------------------------------------------------------------------------------------------------
align 8
rune_feather_pal:
    PALC 'o', RGBO(40,44,60)
    PALC 'h', RGBO(140,150,176)
    PALC 'b', RGBO(96,104,128)
    PALC 'd', RGBO(70,76,100)
    PALC 'g', RGBO(120,230,140)
    PALC 'i', RGBO(200,255,210)
    PALC 'G', RGBO(54,103,63)
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS rune_feather_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".......oooooooooooooooooo......."  ; 03
    SKROW "......ohhhhhhhhhhhhhhhhhho......"  ; 04
    SKROW ".....ohbbbbbbbbbbbbbbbbbbho....."  ; 05
    SKROW "....ohbbbbbbbbbbbbbbbbbbbbdo...."  ; 06
    SKROW "...ohbbbbbbbbbbbbbbbbbbbbbbdo..."  ; 07
    SKROW "...ohbbbbbbbbbbbbbbbbgbbbbbdo..."  ; 08
    SKROW "...ohbbbbbbbbbbbbbbgggibbbbdo..."  ; 09
    SKROW "...ohbbbbbbbbbbbbggggiggbbbdo..."  ; 10
    SKROW "...ohbbbbbbbbbbbggggiggGGbbdo..."  ; 11
    SKROW "...ohbbbbbbbbbgggggigggGbbbdo..."  ; 12
    SKROW "...ohbbbbbbbbgggggigggGGbbbdo..."  ; 13
    SKROW "...ohbbbbbbbgggggiggggGbbbbdo..."  ; 14
    SKROW "...ohbbbbbbbggggiggggGGbbbbdo..."  ; 15
    SKROW "...ohbbbbbbggggiggggGGbbbbbdo..."  ; 16
    SKROW "...ohbbbbbggggigggggGbbbbbbdo..."  ; 17
    SKROW "...ohbbbbbgggigggggGGbbbbbbdo..."  ; 18
    SKROW "...ohbbbbgggigggggGGbbbbbbbdo..."  ; 19
    SKROW "...ohbbbbggiggggGGGbbbbbbbbdo..."  ; 20
    SKROW "...ohbbbggiggggGGbbbbbbbbbbdo..."  ; 21
    SKROW "...ohbbbgigggGGGbbbbbbbbbbbdo..."  ; 22
    SKROW "...ohbbgiggGGGbbbbbbbbbbbbbdo..."  ; 23
    SKROW "...ohbgigGGGbbbbbbbbbbbbbbbdo..."  ; 24
    SKROW "....ogggGGbbbbbbbbbbbbbbbbdo...."  ; 25
    SKROW ".....ggGGbbbbbbbbbbbbbbbbdo....."  ; 26
    SKROW "......GGdddddddddddddddddo......"  ; 27
    SKROW ".......oooooooooooooooooo......."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_rune_feather, rune_feather_rows, 32, 32, rune_feather_pal
