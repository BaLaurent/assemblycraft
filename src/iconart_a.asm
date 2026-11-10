; iconart_a.asm - the 32x32 item icons of the equipment, part A of the 0.13 "looks" art: tools, weapons, bows,
; armour, firearms, ammunition, staffs, daggers, hammers, spears, flint and steel and the gun attachments (62
; icons when complete; iconart_b.asm holds the other 31). The file holds the validated style samples
; ib_iron_sword, ib_iron_pickaxe, ib_bow, ib_iron_chestplate and ib_revolver; the Wave 3 workers extend it, one
; section per bitmap, with the conventions below.
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
; Role chars. One char means the same role in every bitmap of this file, so that a tier is a palette, not a bitmap:
;   1 2 3 4   the item's primary material, 1 highlight, 2 lit, 3 shaded, 4 deepest (also its selective outline):
;             the tier metal, wood, stone or diamond (AC_<TIER>_1..4), the steel of a gun (AC_IRON_1..4)
;   a b c d   wood, 1 highlight .. 4 deepest: handles, grips, bow limbs, gun stocks (AC_WOOD_1..4)
;   e f g h   leather: armour lining, grip wraps (AC_LEATHER_1..4)
;   i j k l   gold: brass fittings (AC_GOLD_1..4)
;   m n p     bone: caps (AC_BONE_1..3)
;   t u       bowstring, light and shade
;   s         the white glint of metal
;   o         AC_OUTLINE
; A bitmap only uses the roles it needs; take a new role from a free letter and list it here.
;
; Tiers. A tool, a sword or a piece of armour is drawn once per shape (one SKROWS, roles above) and the tiers
; share it: one SKBMP line per item pairs the rows with the palette of its tier. TIER_PAL builds that palette: the
; tier ramp as 1..4, the glint colour of the tier's material, and the roles every tier shares (wood, leather,
; outline). Copy the missing lines to add a tier, then one SKBMP per item, e.g.
; SKBMP ib_gold_sword, sword_rows, 32, 32, tier_gold_pal:
;   TIER_PAL tier_wood_pal,    AC_WOOD_1,  AC_WOOD_2,  AC_WOOD_3,  AC_WOOD_4,  AC_WOOD_1
;   TIER_PAL tier_stone_pal,   AC_STONE_1, AC_STONE_2, AC_STONE_3, AC_STONE_4, AC_STONE_1
;   TIER_PAL tier_iron_pal,    AC_IRON_1,  AC_IRON_2,  AC_IRON_3,  AC_IRON_4,  RGBO(255,255,255)     (below)
;   TIER_PAL tier_gold_pal,    AC_GOLD_1,  AC_GOLD_2,  AC_GOLD_3,  AC_GOLD_4,  RGBO(255,252,214)
;   TIER_PAL tier_diamond_pal, AC_DIAM_1,  AC_DIAM_2,  AC_DIAM_3,  AC_DIAM_4,  RGBO(240,255,254)
; (wood and stone have no specular: their glint is their highlight.) Mind the roles when a tier is also a handle
; material: a wood sword has a wood blade (1..4) and a wood grip (a..d), told apart by the guard between them.
%include "common.inc"
%include "art.inc"
default rel

; TIER_PAL label, ramp 1, ramp 2, ramp 3, ramp 4, glint
%macro TIER_PAL 6
align 8
%1:
    PALC '1', %2
    PALC '2', %3
    PALC '3', %4
    PALC '4', %5
    PALC 'a', AC_WOOD_1
    PALC 'b', AC_WOOD_2
    PALC 'c', AC_WOOD_3
    PALC 'd', AC_WOOD_4
    PALC 'e', AC_LEATHER_1
    PALC 'f', AC_LEATHER_2
    PALC 'g', AC_LEATHER_3
    PALC 'h', AC_LEATHER_4
    PALC 's', %6
    PALC 'o', AC_OUTLINE
    dq 0
%endmacro

section .rodata

TIER_PAL tier_iron_pal, AC_IRON_1, AC_IRON_2, AC_IRON_3, AC_IRON_4, RGBO(255,255,255)

; --------------------------------------------------------------------------------------------------------------------
; sword: ib_iron_sword. sword_rows is the bitmap of every sword tier (wood, stone, iron, gold, diamond)
;   blade 1 lit edge, 2 lit facet, 3 shaded facet, ending in a sharp point; guard 2 lit end, 3 body, 4 shaded end,
;   with a 1 gem; grip a b c wrapped with the darker d; pommel 2 3 4; s glints on the blade.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS sword_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "...........................44..."  ; 02
    SKROW ".........................4413o.."  ; 03
    SKROW ".......................441s33o.."  ; 04
    SKROW "......................412233o..."  ; 05
    SKROW ".....................4122333o..."  ; 06
    SKROW "....................4122333o...."  ; 07
    SKROW "...................41222333o...."  ; 08
    SKROW "..................41212333o....."  ; 09
    SKROW ".................412s2333o......"  ; 10
    SKROW "................41212333o......."  ; 11
    SKROW "...............41222333o........"  ; 12
    SKROW "..............41222333o........."  ; 13
    SKROW ".............41222333o.........."  ; 14
    SKROW "........44..41222333o..........."  ; 15
    SKROW ".......422o41222333o............"  ; 16
    SKROW "......422221222333o............."  ; 17
    SKROW ".......o222212233o.............."  ; 18
    SKROW "........o4421123o..............."  ; 19
    SKROW ".........o44221o................"  ; 20
    SKROW "........dbb4424o................"  ; 21
    SKROW ".......dacdo4444o..............."  ; 22
    SKROW "......dbbco.o444o..............."  ; 23
    SKROW ".....dacdo...o4o................"  ; 24
    SKROW "...44dbco.....o................."  ; 25
    SKROW "..4223oo........................"  ; 26
    SKROW "..4233o........................."  ; 27
    SKROW "..4334o........................."  ; 28
    SKROW "...ooo.........................."  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_iron_sword, sword_rows, 32, 32, tier_iron_pal

; --------------------------------------------------------------------------------------------------------------------
; pickaxe: ib_iron_pickaxe. pickaxe_rows is the bitmap of every pickaxe tier
;   The head is an arch of the tier material: 1 lit top, 2 body, 3 shaded underside, s glints; the handle is a stick,
;   a lit edge, b body, c shaded edge and grain.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS pickaxe_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................444444444......."  ; 01
    SKROW "..............44111ss1111o4....."  ; 02
    SKROW ".............41111111111122o...."  ; 03
    SKROW "............4122333322221232o..."  ; 04
    SKROW ".............oooooo322222333o..."  ; 05
    SKROW "...................oo22233333o.."  ; 06
    SKROW ".....................o2332233o.."  ; 07
    SKROW "....................dab222233o.."  ; 08
    SKROW "...................dabco22233o.."  ; 09
    SKROW "..................dabco.o2233o.."  ; 10
    SKROW ".................dabco..42233o.."  ; 11
    SKROW "................dabco....o133o.."  ; 12
    SKROW "...............dabco.....4133o.."  ; 13
    SKROW "..............dacco......4133o.."  ; 14
    SKROW ".............dabco.......423o..."  ; 15
    SKROW "............dabco........423o..."  ; 16
    SKROW "...........dabco.........43o...."  ; 17
    SKROW "..........dacco...........o....."  ; 18
    SKROW ".........dabco.................."  ; 19
    SKROW "........dabco..................."  ; 20
    SKROW ".......dabco...................."  ; 21
    SKROW "......dacco....................."  ; 22
    SKROW ".....dabco......................"  ; 23
    SKROW "....dabco......................."  ; 24
    SKROW "...dabco........................"  ; 25
    SKROW "..dacco........................."  ; 26
    SKROW ".dabco.........................."  ; 27
    SKROW ".dbco..........................."  ; 28
    SKROW "..oo............................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_iron_pickaxe, pickaxe_rows, 32, 32, tier_iron_pal

; --------------------------------------------------------------------------------------------------------------------
; bow: ib_bow (BOW)
;   Belly up and to the right, the string the straight light/shade line on the main diagonal from nock to nock;
;   the grip is a leather wrap, the nocks are bone. ib_celestial_bow can reuse the rows with its own palette.
; --------------------------------------------------------------------------------------------------------------------
align 8
bow_pal:
    PALC 'a', AC_WOOD_1
    PALC 'b', AC_WOOD_2
    PALC 'c', AC_WOOD_3
    PALC 'd', AC_WOOD_4                     ; AC_WOOD_4: selective outline
    PALC 'e', AC_LEATHER_1
    PALC 'f', AC_LEATHER_2
    PALC 'g', AC_LEATHER_3
    PALC 'h', AC_LEATHER_4                  ; AC_LEATHER_4: wrap seams, selective outline
    PALC 'm', AC_BONE_1
    PALC 'n', AC_BONE_2
    PALC 'p', AC_BONE_3                     ; AC_BONE_3: selective outline of the nocks
    PALC 't', RGBO(240,236,222)             ; string, light
    PALC 'u', RGBO(120,110,96)              ; string, shade
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS bow_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "..............dddddd............"  ; 02
    SKROW "........pdddddaaaaaaoddd........"  ; 03
    SKROW ".....pppmaaaaaaaaaaaaaabo......."  ; 04
    SKROW "....pmmmcccccccccccbaaaheo......"  ; 05
    SKROW "...ptmmoooooooocccccbbhefgo....."  ; 06
    SKROW "....oto........oooobbhefgefo...."  ; 07
    SKROW ".....ut............ohefgefhco..."  ; 08
    SKROW "......ut............oogefhcco..."  ; 09
    SKROW ".......ut.............ofhbcco..."  ; 10
    SKROW "........ut............hhbbcco..."  ; 11
    SKROW ".........ut............obbbcco.."  ; 12
    SKROW "..........ut............oaacco.."  ; 13
    SKROW "...........ut...........daacco.."  ; 14
    SKROW "............ut..........daacco.."  ; 15
    SKROW ".............ut.........dabcco.."  ; 16
    SKROW "..............ut.........obcco.."  ; 17
    SKROW "...............ut........dbco..."  ; 18
    SKROW "................ut.......daco..."  ; 19
    SKROW ".................ut......daco..."  ; 20
    SKROW "..................ut.....daco..."  ; 21
    SKROW "...................ut....daco..."  ; 22
    SKROW "....................ut...dano..."  ; 23
    SKROW ".....................ut..pno...."  ; 24
    SKROW "......................utpnno...."  ; 25
    SKROW ".......................utnno...."  ; 26
    SKROW "........................pto....."  ; 27
    SKROW ".........................o......"  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_bow, bow_rows, 32, 32, bow_pal

; --------------------------------------------------------------------------------------------------------------------
; chestplate: ib_iron_chestplate. chestplate_rows is the bitmap of every chestplate tier (iron, gold, diamond)
;   Front view: pauldrons and sleeves, a keel down the breast, a leather belt with a buckle of the tier metal, two
;   tassets; the left half is lit (1 2), the right half shaded (3 4). The neck shows the leather lining (e f g h);
;   s marks the pauldron rivets.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS chestplate_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW "................................"  ; 03
    SKROW ".....444444..........444444....."  ; 04
    SKROW "....4111122o........4222223o...."  ; 05
    SKROW "...41111123ohhhhhhhh42222233o..."  ; 06
    SKROW "..4112222341hhhhhhhh242333344o.."  ; 07
    SKROW "..4112s22341ffffffff24233s344o.."  ; 08
    SKROW "..4112222342gggggggg342333344o.."  ; 09
    SKROW "..411222234222212333342333344o.."  ; 10
    SKROW "..422222234222212333342333444o.."  ; 11
    SKROW "...o443333422221233334344444o..."  ; 12
    SKROW "...4114444122221233334444433o..."  ; 13
    SKROW "...4122241122221233344o23334o..."  ; 14
    SKROW "...412223o112221233344o23334o..."  ; 15
    SKROW "...412223o112221233344o23334o..."  ; 16
    SKROW "...444444o112221233344o44444o..."  ; 17
    SKROW "...422223o112221233344o33344o..."  ; 18
    SKROW "....o3333o112211223344o3444o...."  ; 19
    SKROW ".....ooooheeee1442eeeeooooo....."  ; 20
    SKROW ".........hffff2442ffffo........."  ; 21
    SKROW ".........hgggg2443ggggo........."  ; 22
    SKROW "........44233322334444o4........"  ; 23
    SKROW ".......41144444444444433o......."  ; 24
    SKROW ".......41222222343333334o......."  ; 25
    SKROW ".......42333333344444444o......."  ; 26
    SKROW "........o33333334444444o........"  ; 27
    SKROW ".........oooooooooooooo........."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_iron_chestplate, chestplate_rows, 32, 32, tier_iron_pal

; --------------------------------------------------------------------------------------------------------------------
; revolver: ib_revolver (REVOLVER). The guns are drawn in side view, muzzle to the right and top, grip bottom-left
;   Gun steel in 1..4 (the AC_IRON ramp), a wooden grip (a..d), brass trigger guard and butt cap (i..l).
; --------------------------------------------------------------------------------------------------------------------
align 8
revolver_pal:
    PALC '1', AC_IRON_1                     ; AC_IRON_1: glints on the cylinder and barrel
    PALC '2', AC_IRON_2                     ; steel, lit edges
    PALC '3', AC_IRON_3                     ; steel
    PALC '4', AC_IRON_4                     ; steel, shaded; selective outline
    PALC 'a', AC_WOOD_1
    PALC 'b', AC_WOOD_2
    PALC 'c', AC_WOOD_3
    PALC 'd', AC_WOOD_4                     ; AC_WOOD_4: selective outline
    PALC 'i', AC_GOLD_1
    PALC 'j', AC_GOLD_2
    PALC 'k', AC_GOLD_3
    PALC 'l', AC_GOLD_4                     ; AC_GOLD_4: selective outline
    PALC 'o', AC_OUTLINE
    PALC 's', RGBO(255,255,255)             ; glint
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS revolver_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW "................................"  ; 03
    SKROW "....44.........................."  ; 04
    SKROW "...422o....................44..."  ; 05
    SKROW "...4234o..................422o.."  ; 06
    SKROW "....o334o44444444444444444433o.."  ; 07
    SKROW "....4222222222222222221s122223o."  ; 08
    SKROW "....42333342141341433333333334o."  ; 09
    SKROW "....42333342342342444444444444o."  ; 10
    SKROW "....423333423423424ooooooooooo.."  ; 11
    SKROW "....423243423423424333333333o..."  ; 12
    SKROW "....423433423423424444444444o..."  ; 13
    SKROW "....423333423423424ooooooooo...."  ; 14
    SKROW "....424444423423424o............"  ; 15
    SKROW "....daabbcdo444444o............."  ; 16
    SKROW "...daabbbcdio3oojo.............."  ; 17
    SKROW "...daacbbcdio4oljo.............."  ; 18
    SKROW "...daacbcdojkkkkko.............."  ; 19
    SKROW "..daabbbcdooooooo..............."  ; 20
    SKROW "..daabijcdo....................."  ; 21
    SKROW "..daabjkcdo....................."  ; 22
    SKROW ".daabcbcdo......................"  ; 23
    SKROW ".daabcbcdo......................"  ; 24
    SKROW ".daabbbcdo......................"  ; 25
    SKROW ".liijjjjjo......................"  ; 26
    SKROW ".lkkkkkkko......................"  ; 27
    SKROW "..ooooooo......................."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_revolver, revolver_rows, 32, 32, revolver_pal
