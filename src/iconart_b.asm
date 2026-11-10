; iconart_b.asm - the 32x32 item icons that are not equipment, part B of the 0.13 "looks" art: the stick, food,
; coal, ingots, the diamond, string, gunpowder, flint, feathers, potions, the coin, jewelry, the boat and the plane
; items (31 icons when complete; iconart_a.asm holds the 62 equipment icons). The file holds the validated style
; samples ib_porkchop, ib_cooked_porkchop, ib_apple, ib_health_potion and ib_gold_coin; the Wave 3 worker extends
; it, one section per icon, with the conventions below.
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
; selective outline on the top and left edge), a b c d is wood, s is the white glint, o is AC_OUTLINE. A variant of an
; icon (a colour, a cooked state) keeps the silhouette and the roles of the original and changes the palette, or the
; few texels that differ: see the raw and cooked pork chop, and the health potion, whose rows serve the mana
; potion with a blue liquid in 1..4 (RGBO(150,196,255), RGBO(56,112,232), RGBO(34,70,186), RGBO(22,40,128)).
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
; ib_health_potion: health potion (HEALTH_POTION); the rows also serve MANA_POTION
;   A round glass flask with a cork, a short neck and red liquid. 1..4 is the liquid ramp: swap it for the blue one
;   (see the header) to get the mana potion from the same rows.
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
