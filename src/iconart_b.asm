; iconart_b.asm - the 32x32 item icons that are not equipment, part B of the 0.13 "looks" art: the stick, food,
; coal, ingots, the diamond, string, gunpowder, flint, feathers, potions, the coin, jewelry, the boat and the plane
; items (31 icons; iconart_a.asm holds the 62 equipment icons). The file starts with the five validated style
; samples ib_porkchop, ib_cooked_porkchop, ib_apple, ib_health_potion and ib_gold_coin, followed by the other 26 icons
; in item id order (STICK .. PLANE), one section per bitmap, with the conventions below.
;
; Data only. icons.asm paints every SKBMP into the 32x32 atlas cell of its item (icon k = item id - FIRST_ITEM)
; through art_blit (art.asm): '.' and every char missing from the palette stay transparent. Palette colours are
; opaque (RGBO or an AC_* ramp entry from art.inc). The labels artreg.asm lists are ib_<lower-case item
; constant of common.inc>; they are global, the rows and palette labels of this file are local.
;
; Style (design doc, "Art style guide" and "Icons (32x32)"):
;   - the silhouette spans 24-30 texels on its long axis, is centred, and keeps a transparent margin of >= 1 texel
;   - light from the top-left, >= 3 tones per material, 1-3 white glints ('s') on metal, glass and gems, no noise,
;     every texel opaque or transparent (no alpha blending)
;   - selective outline, 1 texel: the darkest tone of the adjacent material on the top and left outer edge,
;     AC_OUTLINE ('o') on the bottom and right outer edge
;   - tools and weapons run diagonally, handle bottom-left, head or tip top-right (held_item_draw and the
;     first-person pose rely on it)
;
; Palettes. Every icon here has its own palette (<icon>_pal), so a char only means something inside its icon. The
; habits shared by all of them: 1 2 3 4 is the main material from highlight to deepest (4 doubles as the
; selective outline on the top and left edge), a b c d is a second material from highlight to deepest (wood in the
; samples, a gem or red paint in the jewelry and plane icons), s is the white glint, o is AC_OUTLINE. A variant of
; an icon (a colour, a cooked state) keeps the silhouette and the roles of the original and changes the palette, or
; the few texels that differ: see the raw and cooked pork chop and chicken, the iron and gold ingot (one set of rows,
; two palettes) and the health and mana potion, whose blue liquid is 1..4 = RGBO(150,196,255), RGBO(56,112,232),
; RGBO(34,70,186), RGBO(22,40,128) and whose rows differ by the sparkles that replace the bubbles.
; A material without an AC_* ramp (twine, powder, flint, flesh, gems, red paint, cream fabric) spells its ramp out in
; the icon's palette. The six plane items share one look: red paint (200,56,44), cream fabric (252,244,216), silver
; (AC_IRON_*), blue roundels (62,104,208) and blue-grey glass.
%include "common.inc"
%include "art.inc"
default rel

section .rodata

; --------------------------------------------------------------------------------------------------------------------
; ib_porkchop: raw pork chop (PORKCHOP)
;   A plump chop of pink-red meat, a cream fat rim along the top and right edge, three cream marbling streaks and a
;   cream bone with a round knob sticking out at the bottom-left. The cooked chop below keeps the silhouette.
; --------------------------------------------------------------------------------------------------------------------
align 8
porkchop_pal:
    PALC '1', AC_MEAT_1                     ; AC_MEAT_1: lit rim of the lean meat
    PALC '2', AC_MEAT_2                     ; lean meat
    PALC '3', AC_MEAT_3                     ; shaded rim, the seam against the bone
    PALC '4', AC_MEAT_4                     ; deepest: the meat's selective outline on the top and left edge
    PALC 'm', AC_FAT_1                      ; marbling streak
    PALC 'f', AC_FAT_1                      ; fat rim, lit
    PALC 'F', AC_FAT_2                      ; fat rim, shaded
    PALC 'e', RGBO(206,140,130)             ; the fat's selective outline (top and left edge)
    PALC 'b', AC_BONE_1                     ; bone, lit
    PALC 'B', AC_BONE_2                     ; bone
    PALC 'c', AC_BONE_3                     ; bone, shaded; also its selective outline
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS porkchop_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".............eeeeee............."  ; 03
    SKROW "...........eeffffffoee.........."  ; 04
    SKROW "..........efffffffffffoe........"  ; 05
    SKROW "........eeff1111111fffffo......."  ; 06
    SKROW ".......eff11122222122ffffo......"  ; 07
    SKROW ".......411122222222222ffffo....."  ; 08
    SKROW "......411222222222mm2222fffo...."  ; 09
    SKROW ".....ef122222222222mmm222Ffo...."  ; 10
    SKROW ".....411222222222222222222ffo..."  ; 11
    SKROW ".....4122222mmmm2222222223FFFo.."  ; 12
    SKROW ".....41222mmm22222222222233FFo.."  ; 13
    SKROW ".....4122m2222222222m222223FFo.."  ; 14
    SKROW ".....422222222222mmm22222233Fo.."  ; 15
    SKROW "......o22222222mmm2222222223Fo.."  ; 16
    SKROW ".......o23333222222222222233Fo.."  ; 17
    SKROW "........o333332222222222223Fo..."  ; 18
    SKROW ".......cbbb3332222222222333o...."  ; 19
    SKROW "......cbbbBBB333333333333oo....."  ; 20
    SKROW "...cccbbbBBBcoooooooooooo......."  ; 21
    SKROW "..cbbbbbBBBco..................."  ; 22
    SKROW "..cbbbbbBBco...................."  ; 23
    SKROW "..cbbbbBBBo....................."  ; 24
    SKROW "..cbbbBBBBco...................."  ; 25
    SKROW "...obBBBBcco...................."  ; 26
    SKROW "....ooBBccco...................."  ; 27
    SKROW ".....cBccco....................."  ; 28
    SKROW "......oooo......................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_porkchop, porkchop_rows, 32, 32, porkchop_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_cooked_porkchop: cooked pork chop (COOKED_PORKCHOP)
;   The raw chop browned: two darker diagonal grill lines (g) instead of the marbling, golden crisp fat and a darker bone.
;   Same roles as the raw chop, other colours.
; --------------------------------------------------------------------------------------------------------------------
align 8
cooked_porkchop_pal:
    PALC '1', AC_COOKED_1                   ; AC_COOKED_1: lit rim of the meat
    PALC '2', AC_COOKED_2                   ; meat
    PALC '3', AC_COOKED_3                   ; shaded rim, the seam against the bone
    PALC '4', AC_COOKED_4                   ; deepest: the meat's selective outline on the top and left edge
    PALC 'g', AC_COOKED_4                   ; grill line
    PALC 'f', RGBO(246,200,112)             ; crisp fat, lit
    PALC 'F', RGBO(224,160,72)              ; crisp fat, shaded
    PALC 'e', RGBO(168,104,40)              ; the fat's selective outline (top and left edge)
    PALC 'b', AC_BONE_2                     ; bone, lit
    PALC 'B', AC_BONE_3                     ; bone
    PALC 'c', RGBO(112,98,74)               ; bone, shaded; also its selective outline
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS cooked_porkchop_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".............eeeeee............."  ; 03
    SKROW "...........eeffffffoee.........."  ; 04
    SKROW "..........efffffffffffoe........"  ; 05
    SKROW "........eeff11gg111fffffo......."  ; 06
    SKROW ".......effg1122gg2122ffffo......"  ; 07
    SKROW ".......411gg2222gg2222ffffo....."  ; 08
    SKROW "......41122gg2222gg22222fffo...."  ; 09
    SKROW ".....ef12222gg2222gg22222Ffo...."  ; 10
    SKROW ".....41122222gg2222gg22222ffo..."  ; 11
    SKROW ".....412222222gg2222gg2223FFFo.."  ; 12
    SKROW ".....4122222222gg2222gg2233FFo.."  ; 13
    SKROW ".....41222222222gg2222gg223FFo.."  ; 14
    SKROW ".....422222222222gg2222gg233Fo.."  ; 15
    SKROW "......o22222222222gg2222gg23Fo.."  ; 16
    SKROW ".......o23333222222gg2222gg3Fo.."  ; 17
    SKROW "........o33333222222gg2222gFo..."  ; 18
    SKROW ".......cbbb3332222222gg2333o...."  ; 19
    SKROW "......cbbbBBB333333333gg3oo....."  ; 20
    SKROW "...cccbbbBBBcoooooooooooo......."  ; 21
    SKROW "..cbbbbbBBBco..................."  ; 22
    SKROW "..cbbbbbBBco...................."  ; 23
    SKROW "..cbbbbBBBo....................."  ; 24
    SKROW "..cbbbBBBBco...................."  ; 25
    SKROW "...obBBBBcco...................."  ; 26
    SKROW "....ooBBccco...................."  ; 27
    SKROW ".....cBccco....................."  ; 28
    SKROW "......oooo......................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_cooked_porkchop, cooked_porkchop_rows, 32, 32, cooked_porkchop_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_apple: apple (APPLE)
;   A round red apple with a dimple, a wooden stem and a green leaf; the glint sits on the lit shoulder.
; --------------------------------------------------------------------------------------------------------------------
align 8
apple_pal:
    PALC '1', RGBO(255,128,108)             ; red, highlight
    PALC '2', RGBO(226,44,48)               ; red, lit
    PALC '3', RGBO(172,26,44)               ; red, shaded
    PALC '4', RGBO(118,16,38)               ; red, deepest: selective outline
    PALC 's', RGBO(255,226,214)             ; glint
    PALC 'l', RGBO(156,220,88)              ; leaf, lit
    PALC 'L', RGBO(86,168,48)               ; leaf
    PALC 'k', RGBO(44,112,40)               ; leaf, deepest: selective outline and rib
    PALC 'b', AC_WOOD_2                     ; stem, AC_WOOD_2
    PALC 'c', AC_WOOD_3                     ; stem, shaded
    PALC 'd', AC_WOOD_4                     ; stem, deepest: selective outline
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS apple_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW ".....................kkk........"  ; 02
    SKROW "....................klllok......"  ; 03
    SKROW "...................kllllllo....."  ; 04
    SKROW ".................dkllllLkko....."  ; 05
    SKROW "................dcclLkkkLo......"  ; 06
    SKROW "...............dbcokkLLLo......."  ; 07
    SKROW "...............dbcoooooo........"  ; 08
    SKROW "..........4444.dbco444.........."  ; 09
    SKROW "........441223o.oo3223o4........"  ; 10
    SKROW ".......41111133o43322333o......."  ; 11
    SKROW "......4111111333333222333o......"  ; 12
    SKROW ".....4111ss111333322223333o....."  ; 13
    SKROW "....4221ss11111122222233334o...."  ; 14
    SKROW "....4221s111111122222233344o...."  ; 15
    SKROW "...4222111111112222222333444o..."  ; 16
    SKROW "...4221111111122222223333444o..."  ; 17
    SKROW "...4222111112222222223333444o..."  ; 18
    SKROW "...4222211222222222233333444o..."  ; 19
    SKROW "...4222222222222222333334444o..."  ; 20
    SKROW "....o2222222222222333333444o...."  ; 21
    SKROW "....42222222222223333334444o...."  ; 22
    SKROW ".....o32222222233333334444o....."  ; 23
    SKROW "......o322222333333334444o......"  ; 24
    SKROW ".......o3333333333334444o......."  ; 25
    SKROW "........o33333333344444o........"  ; 26
    SKROW ".........o333333444444o........."  ; 27
    SKROW "..........oo444oo444oo.........."  ; 28
    SKROW "............ooo..ooo............"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_apple, apple_rows, 32, 32, apple_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_health_potion: health potion (HEALTH_POTION); the mana potion further down starts from these rows
;   A round glass flask with a cork, a short neck and red liquid. 1..4 is the liquid ramp: the mana potion swaps it for
;   the blue one (see the header) and replaces the bubbles by sparkles.
; --------------------------------------------------------------------------------------------------------------------
align 8
health_potion_pal:
    PALC '1', RGBO(255,150,160)             ; liquid: the pale surface line
    PALC '2', RGBO(232,56,76)               ; liquid, lit
    PALC '3', RGBO(182,30,58)               ; liquid, shaded
    PALC '4', RGBO(124,18,46)               ; liquid, deepest
    PALC 'g', RGBO(226,244,250)             ; glass, the air above the liquid
    PALC 'G', RGBO(172,208,226)             ; glass shell
    PALC 'k', RGBO(66,104,132)              ; glass, deepest: selective outline
    PALC 's', RGBO(255,255,255)             ; glint on the glass
    PALC 'a', AC_WOOD_1                     ; cork, AC_WOOD_1
    PALC 'b', AC_WOOD_2                     ; cork
    PALC 'c', AC_WOOD_3                     ; cork, shaded
    PALC 'd', AC_WOOD_4                     ; cork, deepest: selective outline
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS potion_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW ".............dddddd............."  ; 02
    SKROW "............daaaacco............"  ; 03
    SKROW "............dabbbcco............"  ; 04
    SKROW "............dabbbcco............"  ; 05
    SKROW "............dabbbcco............"  ; 06
    SKROW "...........dcccccccco..........."  ; 07
    SKROW "...........kGGGGGGGGo..........."  ; 08
    SKROW "...........kGggggggGo..........."  ; 09
    SKROW "..........kGggggggggGo.........."  ; 10
    SKROW ".........kGgggggggggGGo........."  ; 11
    SKROW "........kGggggsgggggGGGo........"  ; 12
    SKROW ".......kGgggggggggggGGGGo......."  ; 13
    SKROW "......kGggggggggggggGGGGGo......"  ; 14
    SKROW "......kGggggggggggggGGGGGo......"  ; 15
    SKROW ".....kG111111111111111111Go....."  ; 16
    SKROW ".....kG22s222222222222233Go....."  ; 17
    SKROW ".....kG2s2222222222222233Go....."  ; 18
    SKROW ".....kG2s2222222222212233Go....."  ; 19
    SKROW ".....kG222222222222222333Go....."  ; 20
    SKROW ".....kG222222222222222333Go....."  ; 21
    SKROW ".....kG222222222122223334Go....."  ; 22
    SKROW "......oG2222222222223333Go......"  ; 23
    SKROW "......kG2222222222233334Go......"  ; 24
    SKROW ".......oG22222222233334Go......."  ; 25
    SKROW "........oG222222333334Go........"  ; 26
    SKROW ".........oGG23333333GGo........."  ; 27
    SKROW "..........ooGGGGGGGGoo.........."  ; 28
    SKROW "............oooooooo............"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_health_potion, potion_rows, 32, 32, health_potion_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_gold_coin: gold coin (GOLD_COIN)
;   A thick coin seen at a slant: a raised rim, a flat field with a stamped star, a reeded edge at the lower right.
; --------------------------------------------------------------------------------------------------------------------
align 8
gold_coin_pal:
    PALC '1', AC_GOLD_1                     ; AC_GOLD_1: the star, the lit rim
    PALC '2', AC_GOLD_2                     ; field
    PALC '3', AC_GOLD_3                     ; rim shade, the star's shadow, reeding
    PALC '4', AC_GOLD_4                     ; deepest: selective outline, reeding
    PALC 's', RGBO(255,252,222)             ; sparkle
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS gold_coin_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW ".............4444..............."  ; 02
    SKROW "..........4441111o44............"  ; 03
    SKROW "........441111111122o4.........."  ; 04
    SKROW ".......411111111112222o........."  ; 05
    SKROW "......41111333333332222o........"  ; 06
    SKROW ".....41ss132222222232222o......."  ; 07
    SKROW "....411s33222222222231222o......"  ; 08
    SKROW "....4111322222222222212223o....."  ; 09
    SKROW "...411132222222222222212234o...."  ; 10
    SKROW "...411322222222132222221333o...."  ; 11
    SKROW "...4113222222211132222213333o..."  ; 12
    SKROW "..41113222222211132222213334o..."  ; 13
    SKROW "..411132222111111111322133343o.."  ; 14
    SKROW "..411132222311111113322133333o.."  ; 15
    SKROW "..411132222231111133222133333o.."  ; 16
    SKROW "...o1132222211131113222133334o.."  ; 17
    SKROW "...42232222211333113222133344o.."  ; 18
    SKROW "...42223222213322313221333443o.."  ; 19
    SKROW "....o222322233222233213334433o.."  ; 20
    SKROW "....4222112222222222113334333o.."  ; 21
    SKROW ".....o2222122222222133334333o..."  ; 22
    SKROW "......o222211111111333343334o..."  ; 23
    SKROW ".......o2223333333333343334o...."  ; 24
    SKROW "........o33333333333443334o....."  ; 25
    SKROW ".........o433333333443334o......"  ; 26
    SKROW "..........oo344333443334o......."  ; 27
    SKROW "............oo33344333oo........"  ; 28
    SKROW "..............oooooooo.........."  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_gold_coin, gold_coin_rows, 32, 32, gold_coin_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_stick: stick (STICK)
;   A thick, slightly bent branch on the diagonal, foot at the bottom-left and tip at the top-right, with bark
;   grain, two broken twig stubs and pale end grain (p, q) on both cut ends.
; --------------------------------------------------------------------------------------------------------------------
align 8
stick_pal:
    PALC '1', AC_WOOD_1                     ; wood, lit
    PALC '2', AC_WOOD_2                     ; wood
    PALC '3', AC_WOOD_3                     ; wood, shaded
    PALC '4', AC_WOOD_4                     ; wood, deepest: selective outline on the top and left edge
    PALC 'p', RGBO(226,190,138)             ; pale end grain
    PALC 'q', RGBO(178,134,84)              ; end grain ring
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS stick_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "..........................q....."  ; 01
    SKROW ".........................qpo...."  ; 02
    SKROW "........................qppqo..."  ; 03
    SKROW ".......................412qqo..."  ; 04
    SKROW "......................41233o...."  ; 05
    SKROW "......................4123o....."  ; 06
    SKROW ".....................4224o......"  ; 07
    SKROW "....................41333o......"  ; 08
    SKROW "...................41233o......."  ; 09
    SKROW "..................41233o........"  ; 10
    SKROW ".........qq......4123323o......."  ; 11
    SKROW "........qpqo....41234oo23o......"  ; 12
    SKROW ".........o12o..41233o..opqo....."  ; 13
    SKROW "..........o12o41233o....oo......"  ; 14
    SKROW "...........o121233o............."  ; 15
    SKROW "...........411233o.............."  ; 16
    SKROW "..........412334o..............."  ; 17
    SKROW ".........412333o................"  ; 18
    SKROW ".......4422333o................."  ; 19
    SKROW "......411233oo.................."  ; 20
    SKROW ".....411243o...................."  ; 21
    SKROW "....412233o....................."  ; 22
    SKROW "...412233o......................"  ; 23
    SKROW "..411233o......................."  ; 24
    SKROW "..qp333o........................"  ; 25
    SKROW ".qppq3o........................."  ; 26
    SKROW "..oqqo.........................."  ; 27
    SKROW "...oqo.........................."  ; 28
    SKROW "....o..........................."  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_stick, stick_rows, 32, 32, stick_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_coal: coal (COAL)
;   A big lump and a chip of coal drawn as flat-shaded facets: lit planes with a rim light (h) at the top-left, deep
;   planes below and to the right, two glints.
; --------------------------------------------------------------------------------------------------------------------
align 8
coal_pal:
    PALC '1', RGBO(104,108,126)             ; coal, lit facet
    PALC '2', RGBO(72,74,90)                ; coal
    PALC '3', RGBO(50,52,66)                ; coal, shaded facet
    PALC '4', RGBO(30,30,40)                ; coal, deepest: selective outline on the top and left edge
    PALC 'h', RGBO(146,152,176)             ; facet edge highlight
    PALC 's', RGBO(214,224,246)             ; glint
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS coal_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW "................4444............"  ; 03
    SKROW "............44442222o4.........."  ; 04
    SKROW "..........44hh22222222o........."  ; 05
    SKROW ".........4hh11222222222o........"  ; 06
    SKROW ".......44h111h122222222o........"  ; 07
    SKROW "......4hh111s1111122222o........"  ; 08
    SKROW "....44h1111h111111112222o......."  ; 09
    SKROW "...4hh111112211111111122o......."  ; 10
    SKROW "..4h11111222222222222221o......."  ; 11
    SKROW "..4h11112222222222222224o......."  ; 12
    SKROW ".4h11122222222222222244o........"  ; 13
    SKROW ".4h1122222222222222444o........."  ; 14
    SKROW ".4h3333333222222244444o........."  ; 15
    SKROW ".433hh333333333244444o.........."  ; 16
    SKROW ".4333333333333344444oo444......."  ; 17
    SKROW "..oo33333333334444oo44hhho4....."  ; 18
    SKROW "....o333333333444o4hsh11222o...."  ; 19
    SKROW ".....o33333334444oh11112222o...."  ; 20
    SKROW "......o333333444o.o111122222o..."  ; 21
    SKROW ".......o333344oo...o11222234o..."  ; 22
    SKROW "........oo334o......o1233334o..."  ; 23
    SKROW "..........ooo........oo33344o..."  ; 24
    SKROW ".......................o3444o..."  ; 25
    SKROW "........................oo4o...."  ; 26
    SKROW "..........................o....."  ; 27
    SKROW "................................"  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_coal, coal_rows, 32, 32, coal_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_iron_ingot: iron ingot (IRON_INGOT); the rows also serve GOLD_INGOT
;   A bevelled bar at a 2:1 angle: a lit top face with a stamped panel, a long side in two tones, a dark end face.
;   The gold ingot below uses the same rows with the gold ramp.
; --------------------------------------------------------------------------------------------------------------------
align 8
iron_ingot_pal:
    PALC '1', AC_IRON_1                     ; iron, lit: the top face rim
    PALC '2', AC_IRON_2                     ; iron: the stamped top, the upper edge of the long side
    PALC '3', AC_IRON_3                     ; iron, shaded: the long side, the end face
    PALC '4', AC_IRON_4                     ; iron, deepest: the end face; selective outline on the top and left edge
    PALC 's', RGBO(255,255,255)             ; glint
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS iron_ingot_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW "................................"  ; 03
    SKROW "................................"  ; 04
    SKROW "................................"  ; 05
    SKROW ".........444...................."  ; 06
    SKROW "........41s1o4.................."  ; 07
    SKROW ".......41s2111o4................"  ; 08
    SKROW "......4112222111o4.............."  ; 09
    SKROW ".....4112222222111o4............"  ; 10
    SKROW "....4221112222222111o4.........."  ; 11
    SKROW "....422221112222222111o4........"  ; 12
    SKROW "...423322221112222222111o4......"  ; 13
    SKROW "...4s333322221112222222113o....."  ; 14
    SKROW "..423223333222211122211133o....."  ; 15
    SKROW "..4233333333322221111133343o...."  ; 16
    SKROW "..4443333333333222211333443o...."  ; 17
    SKROW "...oo44333333333322223444443o..."  ; 18
    SKROW ".....oo443333333333224444443o..."  ; 19
    SKROW ".......oo4433333333334444444o..."  ; 20
    SKROW ".........oo4433333333444444o...."  ; 21
    SKROW "...........oo4433333344444o....."  ; 22
    SKROW ".............oo443333444oo......"  ; 23
    SKROW "...............oo443344o........"  ; 24
    SKROW ".................oo444o........."  ; 25
    SKROW "...................ooo.........."  ; 26
    SKROW "................................"  ; 27
    SKROW "................................"  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_iron_ingot, iron_ingot_rows, 32, 32, iron_ingot_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_gold_ingot: gold ingot (GOLD_INGOT)
;   Same roles as the iron ingot: 1..4 is the gold ramp, s a warm glint.
; --------------------------------------------------------------------------------------------------------------------
align 8
gold_ingot_pal:
    PALC '1', AC_GOLD_1                     ; gold, lit
    PALC '2', AC_GOLD_2                     ; gold
    PALC '3', AC_GOLD_3                     ; gold, shaded
    PALC '4', AC_GOLD_4                     ; gold, deepest: selective outline on the top and left edge
    PALC 's', RGBO(255,252,222)             ; glint
    PALC 'o', AC_OUTLINE
    dq 0
align 8
SKBMP ib_gold_ingot, iron_ingot_rows, 32, 32, gold_ingot_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_diamond: diamond (DIAMOND)
;   A brilliant-cut gem seen from the side: a lit table, seven crown facets, a girdle band and four pavilion facets
;   that meet at the culet, plus a four-point sparkle (s) at the top-left.
; --------------------------------------------------------------------------------------------------------------------
align 8
diamond_pal:
    PALC '1', AC_DIAM_1                     ; diamond, highlight: the table, the lit facets
    PALC '2', AC_DIAM_2                     ; diamond, lit
    PALC '3', AC_DIAM_3                     ; diamond, shaded
    PALC '4', AC_DIAM_4                     ; diamond, deepest: selective outline on the top and left edge
    PALC 's', RGBO(255,255,255)             ; glint, the sparkle star
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS diamond_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".....1.........................."  ; 03
    SKROW ".....s....444444444444.........."  ; 04
    SKROW "...1sss1.4111111111111o........."  ; 05
    SKROW ".....s..4221ss111111144o........"  ; 06
    SKROW ".....1.42222111111114444o......."  ; 07
    SKROW "......42s2223333333344444o......"  ; 08
    SKROW ".....42s222113333332244444o....."  ; 09
    SKROW "....42222211113333222244444o...."  ; 10
    SKROW "...4222222111113322222444444o..."  ; 11
    SKROW "..422222222233333333333333333o.."  ; 12
    SKROW "..433333333333333334444444444o.."  ; 13
    SKROW "..432222231111113333333444443o.."  ; 14
    SKROW "...o222221111111333333444444o..."  ; 15
    SKROW "....o2222211111133333344444o...."  ; 16
    SKROW ".....o22221111113333344444o....."  ; 17
    SKROW "......o222211111333334444o......"  ; 18
    SKROW ".......o2222111133334444o......."  ; 19
    SKROW "........o22211113333444o........"  ; 20
    SKROW ".........o222111333444o........."  ; 21
    SKROW "..........o2211133344o.........."  ; 22
    SKROW "...........o22113344o..........."  ; 23
    SKROW "............o211334o............"  ; 24
    SKROW ".............o2134o............."  ; 25
    SKROW "..............o13o.............."  ; 26
    SKROW "...............oo..............."  ; 27
    SKROW "................................"  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_diamond, diamond_rows, 32, 32, diamond_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_string: string (STRING)
;   A ball of twine: a sphere wound with curved bands (1..4), a dark outline (k) and a loose thread with a frayed
;   end.
; --------------------------------------------------------------------------------------------------------------------
align 8
string_pal:
    PALC '1', RGBO(255,253,246)             ; twine, lit
    PALC '2', RGBO(236,230,212)             ; twine
    PALC '3', RGBO(200,190,166)             ; twine, shaded
    PALC '4', RGBO(148,134,108)             ; twine, deepest: the shaded side of the ball
    PALC 'k', RGBO(108,94,72)               ; twine, darkest: selective outline on the top and left edge
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS string_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "...........kkk.................."  ; 02
    SKROW "........kkk122okk..............."  ; 03
    SKROW ".......k211221122o.............."  ; 04
    SKROW "......k12112211333o............."  ; 05
    SKROW ".....k1121122112333o............"  ; 06
    SKROW "....k211211221123334o..........."  ; 07
    SKROW "...k22212212221223343o.........."  ; 08
    SKROW "...k21212211223222343o.........."  ; 09
    SKROW "...k212112211233223334o........."  ; 10
    SKROW "..k2212212211233323334o........."  ; 11
    SKROW "..k2221211222223344334o........."  ; 12
    SKROW "..k3121121233222344444o........."  ; 13
    SKROW "...o312133223332333444o........."  ; 14
    SKROW "...k32332332233433334o.........."  ; 15
    SKROW "...k23233233233444444o.........."  ; 16
    SKROW "....o232332244333444o..........."  ; 17
    SKROW ".....o43344334443444okk........."  ; 18
    SKROW "......o3434433344441212ok......."  ; 19
    SKROW ".......o343344444ooooo121o......"  ; 20
    SKROW "........oo44444oo.....oo21o....."  ; 21
    SKROW "..........ooooo.........o2o....."  ; 22
    SKROW "........................k1o....."  ; 23
    SKROW ".........................o2o...."  ; 24
    SKROW ".........................k1o...."  ; 25
    SKROW "........................k2o....."  ; 26
    SKROW "........................k1o....."  ; 27
    SKROW "........................k2o....."  ; 28
    SKROW ".......................k2o2o...."  ; 29
    SKROW "........................o.o....."  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_string, string_rows, 32, 32, string_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_gunpowder: gunpowder (GUNPOWDER)
;   A heap of dark grey powder with a smaller heap in front of it: grain-sized texels, bright grains (s) and a dark
;   rim (k).
; --------------------------------------------------------------------------------------------------------------------
align 8
gunpowder_pal:
    PALC '1', RGBO(156,156,170)             ; powder, lit
    PALC '2', RGBO(114,114,128)             ; powder
    PALC '3', RGBO(80,80,94)                ; powder, shaded
    PALC '4', RGBO(52,52,64)                ; powder, deep
    PALC 'k', RGBO(30,30,40)                ; powder, darkest: selective outline on the top and left edge
    PALC 's', RGBO(222,226,240)             ; bright grain
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS gunpowder_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW "................................"  ; 03
    SKROW "................................"  ; 04
    SKROW "................................"  ; 05
    SKROW "................................"  ; 06
    SKROW "................................"  ; 07
    SKROW "............kkkkk..............."  ; 08
    SKROW "...........k21233o.............."  ; 09
    SKROW "..........kk112233o............."  ; 10
    SKROW ".........k112123323o............"  ; 11
    SKROW ".......kks22123333kko..........."  ; 12
    SKROW "......k1111s122323k43o.........."  ; 13
    SKROW ".....k1s1121213333344o.........."  ; 14
    SKROW ".....k1111111122233444o........."  ; 15
    SKROW "....k121111s1312k43334ko........"  ; 16
    SKROW "....k11s111111132344444o........"  ; 17
    SKROW "...k1s111211ss223k4344kko......."  ; 18
    SKROW "...ks2112212211444444444o......."  ; 19
    SKROW "..k21212111212232k344444o......."  ; 20
    SKROW "..k22s111211233234ksk1ss3o......"  ; 21
    SKROW "..k11122111113124411113443o....."  ; 22
    SKROW "..k211212122s2233411122333ko...."  ; 23
    SKROW "..k112211111233334112133344o...."  ; 24
    SKROW "..k11111122232323112113344kko..."  ; 25
    SKROW "...oooooooooooooo11121134444o..."  ; 26
    SKROW "................k122211344k4o..."  ; 27
    SKROW ".................ooooooooooo...."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_gunpowder, gunpowder_rows, 32, 32, gunpowder_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_flint: flint (FLINT)
;   A pointed flint chip on the diagonal: lit facets with a chipped-edge highlight (h) and glints on the upper-left,
;   a deep underside, and a pale chalky crust (a, b, c) at the heel.
; --------------------------------------------------------------------------------------------------------------------
align 8
flint_pal:
    PALC '1', RGBO(140,142,160)             ; flint, lit facet
    PALC '2', RGBO(98,100,120)              ; flint
    PALC '3', RGBO(66,68,88)                ; flint, shaded facet
    PALC '4', RGBO(38,40,56)                ; flint, deepest: selective outline on the top and left edge
    PALC 'h', RGBO(184,188,208)             ; chipped edge highlight
    PALC 's', RGBO(240,244,255)             ; glint
    PALC 'a', RGBO(216,206,180)             ; cortex: the pale chalky crust at the heel
    PALC 'b', RGBO(178,166,140)             ; cortex, shaded
    PALC 'c', RGBO(132,120,98)              ; cortex, darkest: its selective outline
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS flint_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW "..........................4....."  ; 03
    SKROW ".......................4443o...."  ; 04
    SKROW ".....................44hsh3o...."  ; 05
    SKROW "..................444hh1133o...."  ; 06
    SKROW "................44hhh111333o...."  ; 07
    SKROW "..............44hh111113333o...."  ; 08
    SKROW "............44sh22111133333o...."  ; 09
    SKROW "...........4hs1122213222333o...."  ; 10
    SKROW "..........4h11112222233333o....."  ; 11
    SKROW ".........4h111111222333333o....."  ; 12
    SKROW "........431111122222333333o....."  ; 13
    SKROW ".......431112222222233333o......"  ; 14
    SKROW "......4322222222222333333o......"  ; 15
    SKROW ".....43222222222233333333o......"  ; 16
    SKROW "....43aa22222222333333333o......"  ; 17
    SKROW "....caaaaa22222333333333o......."  ; 18
    SKROW "....caaaaab224433333344o........"  ; 19
    SKROW "....caaaabb44444333444o........."  ; 20
    SKROW ".....oaabbbb444444444o.........."  ; 21
    SKROW ".....caaaabbb44444444o.........."  ; 22
    SKROW ".....caaaaabb4444444o..........."  ; 23
    SKROW "......oaaaab4444444o............"  ; 24
    SKROW "......caab44444444o............."  ; 25
    SKROW ".......ob44444444o.............."  ; 26
    SKROW "........ooooooooo..............."  ; 27
    SKROW "................................"  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_flint, flint_rows, 32, 32, flint_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_rotten_flesh: rotten flesh (ROTTEN_FLESH)
;   A torn slab of meat with muscle grain, pale sinew (p), mould patches (g, G, h), dark holes (k), maggots (w) and
;   three hanging tendrils.
; --------------------------------------------------------------------------------------------------------------------
align 8
rotten_flesh_pal:
    PALC '1', RGBO(206,132,128)             ; flesh, lit
    PALC '2', RGBO(162,90,94)               ; flesh
    PALC '3', RGBO(116,62,74)               ; flesh, shaded; also the muscle grain
    PALC '4', RGBO(76,40,54)                ; flesh, deepest
    PALC 'g', RGBO(170,196,92)              ; mould, lit
    PALC 'G', RGBO(112,150,66)              ; mould
    PALC 'h', RGBO(64,98,50)                ; mould, shaded
    PALC 'p', RGBO(232,214,176)             ; sinew
    PALC 'w', RGBO(246,240,206)             ; maggot
    PALC 'k', RGBO(50,22,40)                ; the holes; selective outline on the top and left edge
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS rotten_flesh_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "..............kk................"  ; 02
    SKROW "............kk12o..............."  ; 03
    SKROW "...........k11123o.............."  ; 04
    SKROW "..........k1111223o............."  ; 05
    SKROW ".........k11111234okkk.........."  ; 06
    SKROW "........k1111122221123o........."  ; 07
    SKROW "........k1111222222GGhokkkkk...."  ; 08
    SKROW "........k111222233ggGGg11222o..."  ; 09
    SKROW ".......k1111kk33ggGGGGg221234o.."  ; 10
    SKROW ".....kkk1111kk232GgGghG11234o..."  ; 11
    SKROW "....k1111123222222ghhGgg2334o..."  ; 12
    SKROW "....k111111p22222332GgGGww4o...."  ; 13
    SKROW "....k1111ppGw2233222222hhh4o...."  ; 14
    SKROW "...k1112pgGGw332222p223hhho....."  ; 15
    SKROW "...k32222GGhhGg22pp23kkhho......"  ; 16
    SKROW "....o3222hhGGG22p23333234o......"  ; 17
    SKROW ".....o122GGGG222333333234o......"  ; 18
    SKROW "....k1111G223333333442234o......"  ; 19
    SKROW "....k111223333333wwoo2334o......"  ; 20
    SKROW "....k1122333344224o.k144o......."  ; 21
    SKROW "....k12233344oo224o.k2oo........"  ; 22
    SKROW "....k342334oo.k134o.k4o........."  ; 23
    SKROW ".....oo344o...k14o...o.........."  ; 24
    SKROW ".......oo4o...k14o.............."  ; 25
    SKROW ".........o....k2o..............."  ; 26
    SKROW "..............k4o..............."  ; 27
    SKROW "...............o................"  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_rotten_flesh, rotten_flesh_rows, 32, 32, rotten_flesh_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_feather: feather (FEATHER)
;   A white feather curved on the diagonal: a lit vane with barb grooves (3), a rachis, notches along the lower edge
;   and a cream quill (q, r) at the bottom-left.
; --------------------------------------------------------------------------------------------------------------------
align 8
feather_pal:
    PALC '1', RGBO(255,255,255)             ; feather, white
    PALC '2', RGBO(234,238,248)             ; vane
    PALC '3', RGBO(192,200,224)             ; vane, shaded: the rachis and the barb grooves
    PALC 'k', RGBO(98,108,148)              ; feather, darkest: selective outline on the top and left edge
    PALC 'q', RGBO(240,230,204)             ; quill, lit
    PALC 'r', RGBO(198,184,152)             ; quill, shaded; also its selective outline
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS feather_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW "................................"  ; 03
    SKROW ".............................k.."  ; 04
    SKROW "...........................kk3o."  ; 05
    SKROW "..........................k133o."  ; 06
    SKROW ".........................k1332o."  ; 07
    SKROW "......................kkk2333o.."  ; 08
    SKROW ".....................k121332o..."  ; 09
    SKROW "..................kkk11233223o.."  ; 10
    SKROW ".................k11o1133222o..."  ; 11
    SKROW "...............kk1111133222o...."  ; 12
    SKROW "..............k111111333333o...."  ; 13
    SKROW ".............k111113322222o....."  ; 14
    SKROW "............k1111133222223o....."  ; 15
    SKROW "...........k1111132333oooo......"  ; 16
    SKROW "..........k1111333222222o......."  ; 17
    SKROW "..........k111332222223o........"  ; 18
    SKROW "..........k13322233322o........."  ; 19
    SKROW ".........rq333332222oo.........."  ; 20
    SKROW ".......rrqrr22222ooo............"  ; 21
    SKROW "......rqqrooooooo..............."  ; 22
    SKROW "....rrqroo......................"  ; 23
    SKROW "...rqqro........................"  ; 24
    SKROW "..rqrro........................."  ; 25
    SKROW "...ooo.........................."  ; 26
    SKROW "................................"  ; 27
    SKROW "................................"  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_feather, feather_rows, 32, 32, feather_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_raw_chicken: raw chicken (RAW_CHICKEN)
;   A raw drumstick: a pink bulb with skin dimples, a yellow fat patch (f, F) where the leg narrows, and a bone with
;   two knobs sticking out at the bottom-left. The cooked drumstick below keeps the silhouette.
; --------------------------------------------------------------------------------------------------------------------
align 8
raw_chicken_pal:
    PALC '1', RGBO(255,224,208)             ; raw skin, lit
    PALC '2', RGBO(246,182,168)             ; raw skin
    PALC '3', RGBO(214,128,124)             ; raw skin, shaded; also the skin dimples
    PALC '4', RGBO(156,78,90)               ; raw skin, deepest
    PALC 'e', RGBO(196,124,104)             ; the skin's selective outline (top and left edge)
    PALC 'f', RGBO(252,236,178)             ; yellow fat, lit
    PALC 'F', RGBO(232,200,130)             ; yellow fat, shaded
    PALC 'b', AC_BONE_1                     ; bone, lit
    PALC 'B', AC_BONE_2                     ; bone
    PALC 'c', AC_BONE_3                     ; bone, shaded
    PALC 'd', RGBO(112,98,74)               ; the bone's selective outline
    PALC 's', RGBO(255,255,255)             ; glint
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS raw_chicken_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".................eeeeeee........"  ; 03
    SKROW "...............ee1112112oe......"  ; 04
    SKROW "..............e11111112213o....."  ; 05
    SKROW ".............e11s111212234o....."  ; 06
    SKROW "............e11s11111222323o...."  ; 07
    SKROW "............e1s121123222334o...."  ; 08
    SKROW "...........e111111222222334o...."  ; 09
    SKROW "...........e211122223222333o...."  ; 10
    SKROW "...........e111122222223334o...."  ; 11
    SKROW "...........e211132223223344o...."  ; 12
    SKROW "...........e111122222233344o...."  ; 13
    SKROW "..........ef21113222333344o....."  ; 14
    SKROW "..........eff1122223333444o....."  ; 15
    SKROW "..........efff23333333444o......"  ; 16
    SKROW "..........efffF333334444o......."  ; 17
    SKROW ".........effFFF4444444oo........"  ; 18
    SKROW ".........dbFF4444ooooo.........."  ; 19
    SKROW "....dd..dbbc4oooo..............."  ; 20
    SKROW "...dbBodbbcoo..................."  ; 21
    SKROW "..dbbbbbbco....................."  ; 22
    SKROW "..dBbBbbco......................"  ; 23
    SKROW "...oBcBBco......................"  ; 24
    SKROW "....oobbBBo....................."  ; 25
    SKROW ".....dBBBco....................."  ; 26
    SKROW "......oBco......................"  ; 27
    SKROW ".......oo......................."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_raw_chicken, raw_chicken_rows, 32, 32, raw_chicken_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_cooked_chicken: cooked chicken (COOKED_CHICKEN)
;   The drumstick roasted: golden skin, crisp spots (3), an oil sheen (f, s) on the shoulder and a greyer bone.
; --------------------------------------------------------------------------------------------------------------------
align 8
cooked_chicken_pal:
    PALC '1', RGBO(255,224,140)             ; roast skin, lit
    PALC '2', RGBO(230,164,72)              ; roast skin
    PALC '3', RGBO(178,106,42)              ; roast skin, shaded; also the crisp spots
    PALC '4', RGBO(112,62,26)               ; roast skin, deepest
    PALC 'e', RGBO(96,52,22)                ; the skin's selective outline (top and left edge)
    PALC 'f', RGBO(255,240,176)             ; oil sheen
    PALC 'b', AC_BONE_2                     ; bone, lit
    PALC 'B', AC_BONE_3                     ; bone
    PALC 'c', RGBO(122,108,82)              ; bone, shaded
    PALC 'd', RGBO(88,76,56)                ; the bone's selective outline
    PALC 's', RGBO(255,248,206)             ; glint
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS cooked_chicken_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".................eeeeeee........"  ; 03
    SKROW "...............ee1111112oe......"  ; 04
    SKROW "..............e11111112213o....."  ; 05
    SKROW ".............e11sf11112234o....."  ; 06
    SKROW "............e11sf1111222343o...."  ; 07
    SKROW "............e1ss11123222344o...."  ; 08
    SKROW "...........e1ff111222222334o...."  ; 09
    SKROW "...........e111114224224333o...."  ; 10
    SKROW "...........e111122222223334o...."  ; 11
    SKROW "...........e111132223243344o...."  ; 12
    SKROW "...........e111144222233344o...."  ; 13
    SKROW "..........e111113222433344o....."  ; 14
    SKROW "..........e111122223333444o....."  ; 15
    SKROW "..........e11123333433444o......"  ; 16
    SKROW "..........e1143333334444o......."  ; 17
    SKROW ".........e114334444444oo........"  ; 18
    SKROW ".........db334444ooooo.........."  ; 19
    SKROW "....dd..dbbc4oooo..............."  ; 20
    SKROW "...dbBodbbcoo..................."  ; 21
    SKROW "..dbbbbbbco....................."  ; 22
    SKROW "..dBbBbbco......................"  ; 23
    SKROW "...oBcBBco......................"  ; 24
    SKROW "....oobbBBo....................."  ; 25
    SKROW ".....dBBBco....................."  ; 26
    SKROW "......oBco......................"  ; 27
    SKROW ".......oo......................."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_cooked_chicken, cooked_chicken_rows, 32, 32, cooked_chicken_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_mana_potion: mana potion (MANA_POTION)
;   The health potion flask with the blue liquid ramp (see the header): the bubbles are replaced by two four-point
;   sparkles (1, s).
; --------------------------------------------------------------------------------------------------------------------
align 8
mana_potion_pal:
    PALC '1', RGBO(150,196,255)             ; liquid: the pale surface line, the sparkles
    PALC '2', RGBO(56,112,232)              ; liquid, lit
    PALC '3', RGBO(34,70,186)               ; liquid, shaded
    PALC '4', RGBO(22,40,128)               ; liquid, deepest
    PALC 'g', RGBO(226,244,250)             ; glass, the air above the liquid
    PALC 'G', RGBO(172,208,226)             ; glass shell
    PALC 'k', RGBO(66,104,132)              ; glass, deepest: selective outline
    PALC 's', RGBO(255,255,255)             ; glint on the glass, the sparkle cores
    PALC 'a', AC_WOOD_1                     ; cork
    PALC 'b', AC_WOOD_2                     ; cork
    PALC 'c', AC_WOOD_3                     ; cork, shaded
    PALC 'd', AC_WOOD_4                     ; cork, deepest
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS mana_potion_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW ".............dddddd............."  ; 02
    SKROW "............daaaacco............"  ; 03
    SKROW "............dabbbcco............"  ; 04
    SKROW "............dabbbcco............"  ; 05
    SKROW "............dabbbcco............"  ; 06
    SKROW "...........dcccccccco..........."  ; 07
    SKROW "...........kGGGGGGGGo..........."  ; 08
    SKROW "...........kGggggggGo..........."  ; 09
    SKROW "..........kGggggggggGo.........."  ; 10
    SKROW ".........kGgggggggggGGo........."  ; 11
    SKROW "........kGggggsgggggGGGo........"  ; 12
    SKROW ".......kGgggggggggggGGGGo......."  ; 13
    SKROW "......kGggggggggggggGGGGGo......"  ; 14
    SKROW "......kGggggggggggggGGGGGo......"  ; 15
    SKROW ".....kG111111111111111111Go....."  ; 16
    SKROW ".....kG22s222222221222233Go....."  ; 17
    SKROW ".....kG2s2222222222222233Go....."  ; 18
    SKROW ".....kG2s2222221222222233Go....."  ; 19
    SKROW ".....kG22222221s122222333Go....."  ; 20
    SKROW ".....kG222222221222222333Go....."  ; 21
    SKROW ".....kG222222222222223334Go....."  ; 22
    SKROW "......oG2222222222221333Go......"  ; 23
    SKROW "......kG222212222221s134Go......"  ; 24
    SKROW ".......oG22222222233134Go......."  ; 25
    SKROW "........oG222222333334Go........"  ; 26
    SKROW ".........oGG23333333GGo........."  ; 27
    SKROW "..........ooGGGGGGGGoo.........."  ; 28
    SKROW "............oooooooo............"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_mana_potion, mana_potion_rows, 32, 32, mana_potion_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_ring: ring (RING)
;   A gold band shaded as a torus, a gold cup with two claws and a ruby cabochon (a..d) on top.
; --------------------------------------------------------------------------------------------------------------------
align 8
ring_pal:
    PALC '1', AC_GOLD_1                     ; gold, lit
    PALC '2', AC_GOLD_2                     ; gold
    PALC '3', AC_GOLD_3                     ; gold, shaded
    PALC '4', AC_GOLD_4                     ; gold, deepest: the setting; selective outline on the top and left edge
    PALC 'a', RGBO(255,176,186)             ; ruby, highlight
    PALC 'b', RGBO(226,36,56)               ; ruby
    PALC 'c', RGBO(160,18,42)               ; ruby, shaded
    PALC 'd', RGBO(104,10,32)               ; ruby, deepest
    PALC 's', RGBO(255,255,255)             ; glint
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS ring_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW "................................"  ; 03
    SKROW ".............dddddd............."  ; 04
    SKROW "............daaaaabo............"  ; 05
    SKROW "...........daaaaaabbo4.........."  ; 06
    SKROW "..........41aasaabbdo3o........."  ; 07
    SKROW "..........41assbbbcdo3o........."  ; 08
    SKROW "..........41abbbbccdo3o........."  ; 09
    SKROW "..........41bdbbccddo3o........."  ; 10
    SKROW "..........4o22cddd33oo.........."  ; 11
    SKROW ".........4112222233312o........."  ; 12
    SKROW "........411122222333223o........"  ; 13
    SKROW "........411342222334223o........"  ; 14
    SKROW ".......41124oooooooo1223o......."  ; 15
    SKROW ".......41134o......43223o......."  ; 16
    SKROW "......41s24o........o1223o......"  ; 17
    SKROW "......4s124o........41124o......"  ; 18
    SKROW "......41124o........41124o......"  ; 19
    SKROW "......41123o........41124o......"  ; 20
    SKROW "......412223o......411234o......"  ; 21
    SKROW "......432223o4....4411234o......"  ; 22
    SKROW ".......o122212o444111234o......."  ; 23
    SKROW ".......43222221111112334o......."  ; 24
    SKROW "........o32222111122334o........"  ; 25
    SKROW ".........o342222223344o........."  ; 26
    SKROW "..........oo34223344oo.........."  ; 27
    SKROW "............oo3444oo............"  ; 28
    SKROW "..............oooo.............."  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_ring, ring_rows, 32, 32, ring_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_amulet: amulet (AMULET)
;   A thin gold chain, a bail and an oval gold pendant with a sapphire cabochon (a..d).
; --------------------------------------------------------------------------------------------------------------------
align 8
amulet_pal:
    PALC '1', AC_GOLD_1                     ; gold, lit
    PALC '2', AC_GOLD_2                     ; gold
    PALC '3', AC_GOLD_3                     ; gold, shaded
    PALC '4', AC_GOLD_4                     ; gold, deepest: the setting; selective outline on the top and left edge
    PALC 'a', RGBO(190,218,255)             ; sapphire, highlight
    PALC 'b', RGBO(62,112,238)              ; sapphire
    PALC 'c', RGBO(30,64,182)               ; sapphire, shaded
    PALC 'd', RGBO(16,32,110)               ; sapphire, deepest
    PALC 's', RGBO(255,255,255)             ; glint
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS amulet_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".....1....................21...."  ; 03
    SKROW ".....2....................3....."  ; 04
    SKROW ".....3....................3....."  ; 05
    SKROW ".....12..................21....."  ; 06
    SKROW "......2..................2......"  ; 07
    SKROW "......31......4444......13......"  ; 08
    SKROW ".......22....42213o....21......."  ; 09
    SKROW ".........331.42oo3o.223........."  ; 10
    SKROW "...........2342o43133..........."  ; 11
    SKROW ".............42213o............."  ; 12
    SKROW "............441112o4............"  ; 13
    SKROW "...........411333312o..........."  ; 14
    SKROW "..........41244444222o.........."  ; 15
    SKROW ".........4124aaaaab222o........."  ; 16
    SKROW ".........414asaaaabc23o........."  ; 17
    SKROW "........4s34saaaabbd412o........"  ; 18
    SKROW "........4134aaaabbcd413o........"  ; 19
    SKROW "........413aaaaabbbbc13o........"  ; 20
    SKROW "........413aaaaabbbbd13o........"  ; 21
    SKROW "........413aaaabbbccd13o........"  ; 22
    SKROW "........413bbbabbcccd13o........"  ; 23
    SKROW "........4234abbbbccd414o........"  ; 24
    SKROW ".........o12bbcccccd13o........."  ; 25
    SKROW ".........4222cdbcdd124o........."  ; 26
    SKROW "..........o2224cd4124o.........."  ; 27
    SKROW "...........o22111124o..........."  ; 28
    SKROW "............o233334o............"  ; 29
    SKROW ".............oooooo............."  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_amulet, amulet_rows, 32, 32, amulet_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_phoenix_ring: Phoenix Ring (PHOENIX_RING)
;   An ember-gold band with three feathers (wings) on each side of a flame gem (a..d, white-hot core), and drifting
;   sparks (y).
; --------------------------------------------------------------------------------------------------------------------
align 8
phoenix_ring_pal:
    PALC '1', RGBO(255,238,150)             ; ember gold, lit
    PALC '2', RGBO(255,186,52)              ; ember gold
    PALC '3', RGBO(226,116,26)              ; ember gold, shaded
    PALC '4', RGBO(142,58,14)               ; ember gold, deepest: selective outline on the top and left edge
    PALC 'a', RGBO(255,250,206)             ; flame gem: the white-hot core
    PALC 'b', RGBO(255,206,64)              ; flame gem, yellow
    PALC 'c', RGBO(240,100,24)              ; flame gem, orange
    PALC 'd', RGBO(170,36,24)               ; flame gem, red rim
    PALC 'y', RGBO(255,168,44)              ; spark
    PALC 's', RGBO(255,255,255)             ; glint
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS phoenix_ring_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................d..y............"  ; 02
    SKROW "...............dco.............."  ; 03
    SKROW "..............dcbo.............."  ; 04
    SKROW "..............dcbbo...y........."  ; 05
    SKROW "..........y..dcccbo............."  ; 06
    SKROW "......44..4..ddcbbdo.4..44......"  ; 07
    SKROW ".....421o42oddcbbbcdo2o412o....."  ; 08
    SKROW "......o21142odcbaabd24112o......"  ; 09
    SKROW "...444444114dcbaaabbd1144o444..."  ; 10
    SKROW "..4221111441dcbaaaabd44111122o.."  ; 11
    SKROW "...o32211114dcbbaabbd1111223o..."  ; 12
    SKROW "....o3322211dccbbbbcd122233o...."  ; 13
    SKROW ".....oo333222ddccccd22333oo....."  ; 14
    SKROW ".......oo33322223333333oo......."  ; 15
    SKROW "........444432223332444o........"  ; 16
    SKROW ".......411234oooooo32223o......."  ; 17
    SKROW ".......41134o......o1224o......."  ; 18
    SKROW ".......41234o......43223o......."  ; 19
    SKROW "......41124o........o1223o......"  ; 20
    SKROW "......4s123o........41124o......"  ; 21
    SKROW "......4s2223o......411234o......"  ; 22
    SKROW ".......o1223o......41124o......."  ; 23
    SKROW ".......412223o....411234o......."  ; 24
    SKROW ".......4322223o444111334o......."  ; 25
    SKROW "........o32222111111334o........"  ; 26
    SKROW ".........o322211112334o........."  ; 27
    SKROW "..........o3422223344o.........."  ; 28
    SKROW "...........oo344444oo..........."  ; 29
    SKROW ".............oooooo............."  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_phoenix_ring, phoenix_ring_rows, 32, 32, phoenix_ring_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_storm_band: Band of Storms (STORM_BAND)
;   A steel-blue band with a blue gem (a..d) cut with a yellow lightning bolt (y) and two white and two yellow spark
;   arcs.
; --------------------------------------------------------------------------------------------------------------------
align 8
storm_band_pal:
    PALC '1', RGBO(230,240,255)             ; storm steel, lit
    PALC '2', RGBO(158,186,232)             ; storm steel
    PALC '3', RGBO(100,126,190)             ; storm steel, shaded
    PALC '4', RGBO(52,68,128)               ; storm steel, deepest: selective outline on the top and left edge
    PALC 'a', RGBO(206,255,255)             ; storm gem, highlight
    PALC 'b', RGBO(74,204,255)              ; storm gem
    PALC 'c', RGBO(30,122,232)              ; storm gem, shaded
    PALC 'd', RGBO(16,60,150)               ; storm gem, deepest
    PALC 'y', RGBO(255,244,150)             ; lightning bolt, sparks
    PALC 's', RGBO(255,255,255)             ; sparks
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS storm_band_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW "...............dd..............."  ; 03
    SKROW "........s....ddacod....s........"  ; 04
    SKROW ".......s....daaayyco....s......."  ; 05
    SKROW "........s.4daaayybbco4.s........"  ; 06
    SKROW ".......s.41aaayyyyybc3o.s......."  ; 07
    SKROW ".........41bbbbbyybcd3o........."  ; 08
    SKROW ".........41cbbbyycccd3o........."  ; 09
    SKROW ".....y...41ocbyycccdo3o...y....."  ; 10
    SKROW "....y.....o42cdccdd3oo.....y...."  ; 11
    SKROW ".....y....41222cd3333o....y....."  ; 12
    SKROW ".........4112222233323o........."  ; 13
    SKROW "........411222222333223o........"  ; 14
    SKROW ".......41124oooooooo1223o......."  ; 15
    SKROW ".......41134o......43223o......."  ; 16
    SKROW "......41124o........o1223o......"  ; 17
    SKROW "......41124o........41124o......"  ; 18
    SKROW "......41124o........41124o......"  ; 19
    SKROW "......41124o........41124o......"  ; 20
    SKROW "......41223o........41134o......"  ; 21
    SKROW "......432223o......411234o......"  ; 22
    SKROW ".......o12223o4444411134o......."  ; 23
    SKROW ".......43222211111111334o......."  ; 24
    SKROW "........o32221111112334o........"  ; 25
    SKROW ".........o322222223334o........."  ; 26
    SKROW "..........o3442233444o.........."  ; 27
    SKROW "...........ooo3444ooo..........."  ; 28
    SKROW "..............oooo.............."  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_storm_band, storm_band_rows, 32, 32, storm_band_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_ember_amulet: Ember Amulet (EMBER_AMULET)
;   A blackened-iron chain and a diamond-shaped pendant around a glowing ember stone (a..d, cracks k), sparks (y)
;   floating around it.
; --------------------------------------------------------------------------------------------------------------------
align 8
ember_amulet_pal:
    PALC '1', RGBO(156,152,168)             ; blackened iron, lit
    PALC '2', RGBO(108,104,122)             ; blackened iron
    PALC '3', RGBO(72,68,86)                ; blackened iron, shaded
    PALC '4', RGBO(40,36,50)                ; blackened iron, deepest: selective outline on the top and left edge
    PALC 'a', RGBO(255,246,170)             ; ember: the white-hot core
    PALC 'b', RGBO(255,172,44)              ; ember, yellow-orange
    PALC 'c', RGBO(232,86,22)               ; ember, orange; the glow on the metal
    PALC 'd', RGBO(142,34,20)               ; ember, red: the rim of the stone
    PALC 'k', RGBO(66,18,14)                ; ember, the cracks; selective outline of the stone
    PALC 'y', RGBO(255,214,96)              ; floating sparks
    PALC 's', RGBO(255,255,255)             ; glint
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS ember_amulet_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".....1....................21...."  ; 03
    SKROW ".....2....................3....."  ; 04
    SKROW ".....3....................3....."  ; 05
    SKROW ".....12..................21....."  ; 06
    SKROW "......23................32......"  ; 07
    SKROW ".......12..............11.b....."  ; 08
    SKROW "........231..........232........"  ; 09
    SKROW "..........123314443132.........."  ; 10
    SKROW "..............4213o............."  ; 11
    SKROW "..............42o3o............."  ; 12
    SKROW "....b.........412o.............."  ; 13
    SKROW ".............41222o............."  ; 14
    SKROW "............4s2dd22o............"  ; 15
    SKROW "...........412dddd22o..........."  ; 16
    SKROW "..........412ddccdd22o......y..."  ; 17
    SKROW ".........4s2ddcbcdkd22o........."  ; 18
    SKROW "........412ddcbbbcddd22o........"  ; 19
    SKROW ".......412ddcbbabbcddc22o......."  ; 20
    SKROW ".......422dcbbaaabbcdc24o......."  ; 21
    SKROW "........o1ddcbbabbcddc3o........"  ; 22
    SKROW "........422cdckbbccdc24o........"  ; 23
    SKROW ".........o32ckcbccdc24o....y...."  ; 24
    SKROW "..........o32cccckc24o.........."  ; 25
    SKROW "......b....o32ccdc24o..........."  ; 26
    SKROW "............o32cc24o............"  ; 27
    SKROW ".............o3224o............."  ; 28
    SKROW "..............o34o.............."  ; 29
    SKROW "...............oo..............."  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_ember_amulet, ember_amulet_rows, 32, 32, ember_amulet_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_viper_amulet: Viper Amulet (VIPER_AMULET)
;   A gold chain and a bail holding a fanged viper head: green scales (1..4), yellow slit eyes (y, k), fangs (w, W),
;   a forked tongue (r).
; --------------------------------------------------------------------------------------------------------------------
align 8
viper_amulet_pal:
    PALC '1', RGBO(188,244,120)             ; scales, lit
    PALC '2', RGBO(104,196,70)              ; scales
    PALC '3', RGBO(56,140,58)               ; scales, shaded
    PALC '4', RGBO(28,84,46)                ; scales, deepest
    PALC 'k', RGBO(16,50,36)                ; darkest green: slits, brows, nostrils; selective outline on the top and left edge
    PALC 'y', RGBO(252,226,80)              ; eye
    PALC 'Y', RGBO(196,160,40)              ; eye, shaded
    PALC 'r', RGBO(228,52,56)               ; forked tongue
    PALC 'w', RGBO(250,248,232)             ; fang
    PALC 'W', RGBO(206,200,176)             ; fang, shaded
    PALC 'e', AC_GOLD_1                     ; gold chain, lit
    PALC 'f', AC_GOLD_2                     ; gold chain, bail
    PALC 'g', AC_GOLD_3                     ; gold chain, shaded
    PALC 's', RGBO(255,255,255)             ; glint
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS viper_amulet_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".....e....................fe...."  ; 03
    SKROW ".....f....................g....."  ; 04
    SKROW ".....ge..................eg....."  ; 05
    SKROW "......ff................fe......"  ; 06
    SKROW ".......gee............geg......."  ; 07
    SKROW ".........fgeeff44gffeeg........."  ; 08
    SKROW "..............geeg.............."  ; 09
    SKROW "..........kkkk4fggokkk.........."  ; 10
    SKROW ".........k111111111112o........."  ; 11
    SKROW "........k11121112111223o........"  ; 12
    SKROW "........k1111kk111kk224o........"  ; 13
    SKROW ".......k112kk2322232kk33o......."  ; 14
    SKROW ".......k1111Yky222Yky234o......."  ; 15
    SKROW ".......k211syky232yky234o......."  ; 16
    SKROW ".......k12s2ykY222ykY334o......."  ; 17
    SKROW ".......k3232223222322344o......."  ; 18
    SKROW "........o12222222222334o........"  ; 19
    SKROW "........k32232k232k2434o........"  ; 20
    SKROW ".........o122222222334o........."  ; 21
    SKROW ".........k422232224334o........."  ; 22
    SKROW "..........o12kkkkkkk4o.........."  ; 23
    SKROW "..........k34ww243ww4o.........."  ; 24
    SKROW "...........oowW333Wwo..........."  ; 25
    SKROW "............kw3444owo..........."  ; 26
    SKROW ".............ooooo.o............"  ; 27
    SKROW "................r..............."  ; 28
    SKROW "...............r.r.............."  ; 29
    SKROW "...............r.r.............."  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_viper_amulet, viper_amulet_rows, 32, 32, viper_amulet_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_boat: boat (BOAT)
;   A planked rowboat seen from above on the diagonal, bow at the top-right: a lit gunwale (q, 1), a dark floor with
;   a keel seam, a flat transom, two thwarts (q, 1), the planked hull side below the near gunwale and an oar lying
;   across the boat (p, q).
; --------------------------------------------------------------------------------------------------------------------
align 8
boat_pal:
    PALC '1', AC_WOOD_1                     ; planks, lit: the thwarts, the gunwale
    PALC '2', AC_WOOD_2                     ; planks
    PALC '3', AC_WOOD_3                     ; planks, shaded: the hull side, the floor
    PALC '4', AC_WOOD_4                     ; planks, deepest: the seams; selective outline on the top and left edge
    PALC 'q', RGBO(226,188,130)             ; pale planks: the lit gunwale, the thwart tops, the oar blade
    PALC 'p', RGBO(176,128,74)              ; the oar shaft
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS boat_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "..........................44...."  ; 01
    SKROW ".......................444q1o..."  ; 02
    SKROW "....................444qqq13o..."  ; 03
    SKROW ".........4........44qqqqq132o..."  ; 04
    SKROW "........4po.....44qqqq442331o..."  ; 05
    SKROW "........4ppo..44qqqq44342333o..."  ; 06
    SKROW ".........oppo4qq11qq3343232o...."  ; 07
    SKROW "..........oppqq4411qq432331o...."  ; 08
    SKROW "..........4qpp434411qq32333o...."  ; 09
    SKROW ".........4qqqpp334411qq332o....."  ; 10
    SKROW "........4qqq43pp334411qq31o....."  ; 11
    SKROW ".......4q1qqq33pp434411q23o....."  ; 12
    SKROW "......4qq11qqq33pp3342131o......"  ; 13
    SKROW "......4qq411qqq43pp332323o......"  ; 14
    SKROW ".....4qq44411qqq33pp2331o......."  ; 15
    SKROW "....4qq4334411qqq33pp323o......."  ; 16
    SKROW "...4qq433334411qqq23pp1o........"  ; 17
    SKROW "...4qq4333344411qqq33p11o......."  ; 18
    SKROW "...4q433334334411qq321q11o......"  ; 19
    SKROW "...4123334333342113213oq11o....."  ; 20
    SKROW "...411234333332333213o.oq11o...."  ; 21
    SKROW "...42222333332333213o...oq1o...."  ; 22
    SKROW "...4122223322332213o.....oo....."  ; 23
    SKROW "...431222223332113o............."  ; 24
    SKROW "....o312333332133o.............."  ; 25
    SKROW ".....o312222213oo..............."  ; 26
    SKROW "......o3111113o................."  ; 27
    SKROW ".......o33333o.................."  ; 28
    SKROW "........ooooo..................."  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_boat, boat_rows, 32, 32, boat_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_plane_engine: airplane engine (PLANE_ENGINE)
;   Three finned cylinders with blackened valve covers and spark plugs (s) on an iron crankcase, with a glowing
;   exhaust port (O, y) under each cylinder.
; --------------------------------------------------------------------------------------------------------------------
align 8
plane_engine_pal:
    PALC '1', AC_IRON_1                     ; iron, lit
    PALC '2', AC_IRON_2                     ; iron
    PALC '3', AC_IRON_3                     ; iron, shaded: the cooling fins
    PALC '4', AC_IRON_4                     ; iron, deepest: the base; selective outline on the top and left edge
    PALC 'K', RGBO(70,66,80)                ; blackened iron, lit: the valve covers
    PALC 'k', RGBO(44,40,52)                ; blackened iron: the valve covers, the exhaust ports
    PALC 'O', RGBO(242,140,36)              ; exhaust glow
    PALC 'y', RGBO(255,214,96)              ; exhaust glow, hot
    PALC 's', RGBO(255,255,255)             ; spark plug ceramic
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS plane_engine_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW ".....44.......44.......44......."  ; 01
    SKROW "....4s1o.....4s1o.....4s1o......"  ; 02
    SKROW "....423o.....423o.....423o......"  ; 03
    SKROW "..kk434okk.kk434okk.kk434okk...."  ; 04
    SKROW ".kKKKKKkkkoKKKKKkkkoKKKKKkkko..."  ; 05
    SKROW ".kKkkkkkkkoKkkkkkkkoKkkkkkkko..."  ; 06
    SKROW ".kkkkkkkkkokkkkkkkkokkkkkkkko..."  ; 07
    SKROW "..o122233o.o122233o.o122233o...."  ; 08
    SKROW "..4122233o.4122233o.4122233o...."  ; 09
    SKROW "..4233344o.4233344o.4233344o...."  ; 10
    SKROW "..4112233o.4112233o.4112233o...."  ; 11
    SKROW "..4122233o.4122233o.4122233o...."  ; 12
    SKROW "..4233344o.4233344o.4233344o...."  ; 13
    SKROW "..4112233o.4112233o.4112233o...."  ; 14
    SKROW "..4122233o.4122233o.4122233o...."  ; 15
    SKROW "..4233344o.4233344o.4233344o...."  ; 16
    SKROW "..4112233o44112233o44112233o44.."  ; 17
    SKROW ".41222222211222222211222222212o."  ; 18
    SKROW ".43333333313333333313333333322o."  ; 19
    SKROW "..o111111111111111111111111222o."  ; 20
    SKROW ".41111111111111111111111111223o."  ; 21
    SKROW ".41111111111111111111111111333o."  ; 22
    SKROW ".43kkkkk2232kkkkk2322kkkkk3333o."  ; 23
    SKROW ".42kyyOk2222kyyOk2222kyyOk2333o."  ; 24
    SKROW ".42kkkOk2222kkkOk2222kkkOk233o.."  ; 25
    SKROW ".433333333333333333333333333o..."  ; 26
    SKROW ".44444444444444444444444444o...."  ; 27
    SKROW "..ooooooooooooooooooooooooo....."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_plane_engine, plane_engine_rows, 32, 32, plane_engine_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_plane_wing: wing panel (PLANE_WING)
;   A tapered wing panel on the diagonal, root at the bottom-left: cream fabric with ribs (x) and an aileron hinge
;   (X), a silver leading edge, a root fitting and a tip cap, and a blue roundel (u) with a red centre (r).
; --------------------------------------------------------------------------------------------------------------------
align 8
plane_wing_pal:
    PALC '1', AC_IRON_1                     ; silver, lit: the leading edge
    PALC '2', AC_IRON_2                     ; silver
    PALC '3', AC_IRON_3                     ; silver, shaded: the root fitting and the tip cap
    PALC '4', AC_IRON_4                     ; silver, deepest: selective outline on the top and left edge
    PALC 'w', RGBO(252,244,216)             ; cream fabric, lit
    PALC 'W', RGBO(232,218,184)             ; cream fabric, shaded
    PALC 'x', RGBO(196,176,140)             ; cream fabric: the ribs, the trailing edge
    PALC 'X', RGBO(126,104,74)              ; cream fabric: the aileron hinge
    PALC 'u', RGBO(62,104,208)              ; blue: the roundel ring
    PALC 'r', RGBO(210,60,48)               ; red: the roundel centre
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS plane_wing_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW "................................"  ; 03
    SKROW ".......................4444....."  ; 04
    SKROW ".....................441133o...."  ; 05
    SKROW "....................41122X33o..."  ; 06
    SKROW "..................44122WXWx3o..."  ; 07
    SKROW "................44112wWXxWxxo..."  ; 08
    SKROW "...............41122wxXWWxxo...."  ; 09
    SKROW ".............44122wxWXxWWxo....."  ; 10
    SKROW "...........44122wwwWxWWxxo......"  ; 11
    SKROW "..........41uuuuwxwWXxWxo......."  ; 12
    SKROW "........441uwwwwuwxXWWxo........"  ; 13
    SKROW "......44122uwrrwuWXxWxo........."  ; 14
    SKROW ".....41122wuwrrwuXWWxxo........."  ; 15
    SKROW "...44122wwxuwwwwuxXxxo.........."  ; 16
    SKROW "..43322xwwwxuuuuWWxxo..........."  ; 17
    SKROW "..4333wwxwwwxWWWxWxo............"  ; 18
    SKROW "...o333wwxwwWxWWWxo............."  ; 19
    SKROW "....o333wwxwWWxWxo.............."  ; 20
    SKROW ".....o333wwxWWWxo..............."  ; 21
    SKROW "......o333WWxWxo................"  ; 22
    SKROW ".......o333WWxxo................"  ; 23
    SKROW "........o333xxo................."  ; 24
    SKROW ".........o333o.................."  ; 25
    SKROW "..........o3o..................."  ; 26
    SKROW "...........o...................."  ; 27
    SKROW "................................"  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_plane_wing, plane_wing_rows, 32, 32, plane_wing_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_plane_fuselage: fuselage (PLANE_FUSELAGE)
;   A red-painted tube with an upswept tail, panel seams with rivets (a), three glass windows (g, G, H) and a silver
;   nose cowl (1..4).
; --------------------------------------------------------------------------------------------------------------------
align 8
plane_fuselage_pal:
    PALC '1', AC_IRON_1                     ; silver, lit: the nose cowl
    PALC '2', AC_IRON_2                     ; silver
    PALC '3', AC_IRON_3                     ; silver, shaded: the cowl rings
    PALC '4', AC_IRON_4                     ; silver, deepest: the cowl outline
    PALC 'a', RGBO(244,120,98)              ; red paint, lit; also the rivets
    PALC 'b', RGBO(200,56,44)               ; red paint
    PALC 'c', RGBO(150,36,38)               ; red paint, shaded: the panel seams, the window frames
    PALC 'd', RGBO(96,22,32)                ; red paint, deepest; selective outline on the top and left edge
    PALC 'w', RGBO(252,244,216)             ; cream tail band, lit
    PALC 'W', RGBO(232,218,184)             ; cream tail band, shaded
    PALC 'g', RGBO(178,226,250)             ; glass, lit
    PALC 'G', RGBO(108,172,218)             ; glass
    PALC 'H', RGBO(58,114,166)              ; glass, shaded
    PALC 's', RGBO(255,255,255)             ; glint on the glass and the cowl
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS plane_fuselage_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW "................................"  ; 03
    SKROW "................................"  ; 04
    SKROW "................................"  ; 05
    SKROW "................................"  ; 06
    SKROW "................................"  ; 07
    SKROW "................................"  ; 08
    SKROW "................................"  ; 09
    SKROW "..d....dddddddddddddddd44......."  ; 10
    SKROW ".daodddaccccaccccaccccas3o4....."  ; 11
    SKROW ".daawwabcsGGccgGGccsGGc2332o...."  ; 12
    SKROW ".daawwabcGGHccGGHccGGHc23323o..."  ; 13
    SKROW ".dcbwwabddddddddddddddd233223o.."  ; 14
    SKROW "..ocWwbcbbbbcbbbbcbbbbc233231o.."  ; 15
    SKROW "...ooWbdcbbbcbbbbcbbbbc2332122o."  ; 16
    SKROW ".....ocdbbbcdccccdccccd334332o.."  ; 17
    SKROW "......oocbccdccccdccccd344334o.."  ; 18
    SKROW "........ocddddddddddddd44444o..."  ; 19
    SKROW ".........ooooooooooooooo4ooo...."  ; 20
    SKROW "........................o......."  ; 21
    SKROW "................................"  ; 22
    SKROW "................................"  ; 23
    SKROW "................................"  ; 24
    SKROW "................................"  ; 25
    SKROW "................................"  ; 26
    SKROW "................................"  ; 27
    SKROW "................................"  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_plane_fuselage, plane_fuselage_rows, 32, 32, plane_fuselage_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_plane_prop: propeller (PLANE_PROP)
;   Two curved silver blades with red tips (a..d) round a ringed hub with a bolt (k).
; --------------------------------------------------------------------------------------------------------------------
align 8
plane_prop_pal:
    PALC '1', AC_IRON_1                     ; iron, lit
    PALC '2', AC_IRON_2                     ; iron
    PALC '3', AC_IRON_3                     ; iron, shaded
    PALC '4', AC_IRON_4                     ; iron, deepest: the hub ring; selective outline on the top and left edge
    PALC 'a', RGBO(244,120,98)              ; red paint, lit: the blade tips
    PALC 'b', RGBO(200,56,44)               ; red paint
    PALC 'c', RGBO(150,36,38)               ; red paint, shaded
    PALC 'd', RGBO(96,22,32)                ; red paint, deepest: the outline of the tips
    PALC 'k', RGBO(40,36,48)                ; the hub bolt
    PALC 's', RGBO(255,255,255)             ; glint
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS plane_prop_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW ".....................dd........."  ; 02
    SKROW "....................dabo........"  ; 03
    SKROW "....................dabo........"  ; 04
    SKROW "...................daabco......."  ; 05
    SKROW "..................411abco......."  ; 06
    SKROW "..................4112bco......."  ; 07
    SKROW ".................411122co......."  ; 08
    SKROW "................41112223o......."  ; 09
    SKROW "...............441112233o......."  ; 10
    SKROW ".............444o1122233o......."  ; 11
    SKROW "............444144222333o......."  ; 12
    SKROW "...........44ss11242333o........"  ; 13
    SKROW "..........444s11234333o........."  ; 14
    SKROW ".........434111kk2343o.........."  ; 15
    SKROW "........4333412kk34oo..........."  ; 16
    SKROW ".......433324232344o............"  ; 17
    SKROW "......433322244344o............."  ; 18
    SKROW "......43322211o4oo.............."  ; 19
    SKROW "......43322111oo................"  ; 20
    SKROW "......43222111o................."  ; 21
    SKROW "......dc22111o.................."  ; 22
    SKROW "......dcb211o..................."  ; 23
    SKROW "......dcba11o..................."  ; 24
    SKROW "......dcbaao...................."  ; 25
    SKROW ".......obao....................."  ; 26
    SKROW ".......dbao....................."  ; 27
    SKROW "........oo......................"  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_plane_prop, plane_prop_rows, 32, 32, plane_prop_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_plane_tail: tail unit (PLANE_TAIL)
;   A red fin with a cream stripe, cream stabilisers (w, W, x) and a red cone ending in a silver joint flange (2,
;   3).
; --------------------------------------------------------------------------------------------------------------------
align 8
plane_tail_pal:
    PALC '1', AC_IRON_1                     ; silver, lit
    PALC '2', AC_IRON_2                     ; silver: the joint flange, the fin cap
    PALC '3', AC_IRON_3                     ; silver, shaded
    PALC '4', AC_IRON_4                     ; silver, deepest
    PALC 'a', RGBO(244,120,98)              ; red paint, lit
    PALC 'b', RGBO(200,56,44)               ; red paint
    PALC 'c', RGBO(150,36,38)               ; red paint, shaded
    PALC 'd', RGBO(96,22,32)                ; red paint, deepest; selective outline on the top and left edge
    PALC 'w', RGBO(252,244,216)             ; cream, lit: the stripe, the stabilisers
    PALC 'W', RGBO(232,218,184)             ; cream, shaded
    PALC 'x', RGBO(196,176,140)             ; cream: the ribs; its outline
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS plane_tail_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "......44444....................."  ; 02
    SKROW ".....422222o...................."  ; 03
    SKROW ".....dbbbcbco..................."  ; 04
    SKROW ".....dbbbcbbco.................."  ; 05
    SKROW ".....dbbbcbbcdo................."  ; 06
    SKROW ".....xwwwcwwwwdo................"  ; 07
    SKROW ".....xwwwcwwwwwdo44444444......."  ; 08
    SKROW "......oWWWWWWWWWd22222222o......"  ; 09
    SKROW "......dbbcbbbbbbcWWWWWWWo......."  ; 10
    SKROW "......dbbcbbbbbbbcWWWWWo........"  ; 11
    SKROW "......dbbcbbbbbbbbdWWWo........."  ; 12
    SKROW "......dbbbcbbbbbbbcdoo.........."  ; 13
    SKROW "......dbbbcbbbbbbbbcdo..ddd44..."  ; 14
    SKROW "......dbbbcbbbbbbbbbcdodaaa13o.."  ; 15
    SKROW "......dbbbcbbbbbcccaaabaaaa13o.."  ; 16
    SKROW "......dbbbccaaaaabaaaabaaab23o.."  ; 17
    SKROW ".....daaaaaaaaaaabaaaabaabb23o.."  ; 18
    SKROW ".....daabaabbbbbbcbbbbcbbbc23o.."  ; 19
    SKROW ".....dc111111111111cccdbbbc23o.."  ; 20
    SKROW ".....xwwwwwwxwwxwwccccdcbcc23o.."  ; 21
    SKROW ".....xwwxwwxwwxwwwdddddbccc23o.."  ; 22
    SKROW "....xwwxwwxwwwwwwoooooocddd23o.."  ; 23
    SKROW "...xwwxwwwxwwxwwwo.....oooooo..."  ; 24
    SKROW "..xWWWWWWWWWWWWWo..............."  ; 25
    SKROW "..xWWWWWWWWWWWWo................"  ; 26
    SKROW "...oooooWWWWWWo................."  ; 27
    SKROW "........oooooo.................."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_plane_tail, plane_tail_rows, 32, 32, plane_tail_pal

; --------------------------------------------------------------------------------------------------------------------
; ib_plane: airplane (PLANE)
;   The whole plane from above, nose at the top-right: a red fuselage with a silver cowl, glass canopy (g, G), cream
;   wings with silver leading edges and blue roundels (u), cream stabilisers and a propeller bar with red tips.
; --------------------------------------------------------------------------------------------------------------------
align 8
plane_pal:
    PALC '1', AC_IRON_1                     ; silver, lit: the nose cowl
    PALC '2', AC_IRON_2                     ; silver: the cowl, the leading edges
    PALC '3', AC_IRON_3                     ; silver, shaded: the propeller
    PALC '4', AC_IRON_4                     ; silver, deepest: the cowl outline
    PALC 'a', RGBO(244,120,98)              ; red paint, lit
    PALC 'b', RGBO(200,56,44)               ; red paint: the fuselage, the stabiliser tips, the propeller tips
    PALC 'c', RGBO(150,36,38)               ; red paint, shaded
    PALC 'd', RGBO(96,22,32)                ; red paint, deepest; selective outline of the fuselage
    PALC 'w', RGBO(252,244,216)             ; cream fabric, lit
    PALC 'W', RGBO(232,218,184)             ; cream fabric, shaded
    PALC 'x', RGBO(196,176,140)             ; cream fabric: the ribs
    PALC 'X', RGBO(126,104,74)              ; cream fabric, deepest: its selective outline
    PALC 'u', RGBO(62,104,208)              ; blue: the roundels
    PALC 'g', RGBO(178,226,250)             ; glass, lit
    PALC 'G', RGBO(108,172,218)             ; glass
    PALC 's', RGBO(255,255,255)             ; glint on the glass and the cowl
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS plane_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW ".....................d.........."  ; 01
    SKROW "....................dbo........."  ; 02
    SKROW ".....................o3o........"  ; 03
    SKROW "......................o3o......."  ; 04
    SKROW "........X44..........44o3o......"  ; 05
    SKROW ".......Xw22o........411s23o....."  ; 06
    SKROW "......Xwwwuuo......da1123o3o...."  ; 07
    SKROW "......XWWuuuuo4...daaa223oo3o..."  ; 08
    SKROW ".......ouuwwuu2o.daaabb34o.obo.."  ; 09
    SKROW ".......Xuuwwuu22oaaabbcdo...o..."  ; 10
    SKROW "........ouuuuxwwaaGGbcdo........"  ; 11
    SKROW "........XWuuxwwaasGGcdo........."  ; 12
    SKROW ".........oWxWwaaggGcdo.........."  ; 13
    SKROW "..........oWWaaggGcdo..........."  ; 14
    SKROW "..........XWWaaGGcdw2o.........."  ; 15
    SKROW "...........oaabbcdww22o........."  ; 16
    SKROW "..........daabcddwwxuuo........."  ; 17
    SKROW "...44....daabcdWWWxuuuuo........"  ; 18
    SKROW "..422o..daabcdoWWxuuwwuuo......."  ; 19
    SKROW ".Xww22odaabcdo.ooWuuwwuu2o......"  ; 20
    SKROW ".dbbww2oabcdo....oWuuuuw2o......"  ; 21
    SKROW "..obwwwabddo......oouuWwwo......"  ; 22
    SKROW "...owwabdoo.........ooWwo......."  ; 23
    SKROW "....oabdw2o...........oo........"  ; 24
    SKROW "....dbdwww2o...................."  ; 25
    SKROW ".....oowww22o..................."  ; 26
    SKROW ".......obbw2o..................."  ; 27
    SKROW "........obwo...................."  ; 28
    SKROW ".........oo....................."  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_plane, plane_rows, 32, 32, plane_pal
