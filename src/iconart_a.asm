; iconart_a.asm - the 32x32 item icons of the tools and weapons, part A of the 0.13 "looks" art: the 20 tools (wood,
; stone, iron, gold and diamond pickaxe, axe, shovel and sword), the bow, the arrow, the Celestial Bow, the staff,
; the Archmage Staff, the iron and diamond dagger, Shadow Fang, the King's Blade, the iron and diamond hammer and
; spear, and flint and steel: 34 icons. The armour, firearm, ammunition and attachment icons are drawn in
; iconart_c.asm, the food, materials, potions, coin, jewelry, boat and plane items in iconart_b.asm. The validated
; style samples ib_iron_sword, ib_iron_pickaxe and ib_bow are kept as they were signed off; the rest of the file
; follows them, one section per bitmap, with the conventions below.
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
;             the tier metal, planks, stone or diamond (AC_<TIER>_1..4), the steel of an arrow head, the blade of a
;             unique weapon (Shadow Fang: black violet, King's Blade: white gold, Celestial Bow: sky blue)
;   a b c d   wood, 1 highlight .. 4 deepest: handles, grips, shafts, bow limbs (AC_WOOD_1..4); a unique staff
;             maps it to its own shaft (the Archmage Staff: violet)
;   e f g h   leather: grip wraps (AC_LEATHER_1..4); a unique weapon maps it to its own wrap
;   i j k l   gold: brass fittings (AC_GOLD_1..4)
;   m n p     bone: caps (AC_BONE_1..3)
;   t u       bowstring, light and shade
;   v w x y   the accent ramp of the item, 1 highlight .. 4 deepest (also its selective outline): the trim of a
;             hammer, spear or dagger (iron tier: blackened steel, diamond tier: gold) and the gem, orb or ruby of
;             a staff and of the unique blades
;   s         the white glint of metal
;   o         AC_OUTLINE
;   A-Z       item-local roles of one bitmap, listed at its section: the arrow (F G H I feather, R Q N red
;             cock feather) and flint and steel (J K L M flint, S T U sparks)
; A bitmap only uses the roles it needs; take a new role from a free letter and list it here.
;
; Tiers. A tool or a sword is drawn once per shape (one SKROWS, roles above) and the tiers share it: one SKBMP line
; per item pairs the rows with the palette of its tier. TIER_PAL builds that palette: the tier ramp as 1..4, the glint
; colour of the tier's material, and the roles every tier shares (wood, leather, outline). TRIM_PAL adds the trim ramp
; v w x y for the shapes that carry one (hammer, spear, dagger: two tiers, told apart by the blade and by the trim).
; Copy the missing lines to add a tier, then one SKBMP per item, e.g.
; SKBMP ib_gold_sword, sword_rows, 32, 32, tier_gold_pal:
;   TIER_PAL tier_wood_pal,    RGBO(228,190,118), RGBO(196,152,86), RGBO(150,108,58), RGBO(100,70,36), RGBO(228,190,118)
;   TIER_PAL tier_stone_pal,   AC_STONE_1, AC_STONE_2, AC_STONE_3, AC_STONE_4, AC_STONE_1
;   TIER_PAL tier_iron_pal,    AC_IRON_1,  AC_IRON_2,  AC_IRON_3,  AC_IRON_4,  RGBO(255,255,255)
;   TIER_PAL tier_gold_pal,    AC_GOLD_1,  AC_GOLD_2,  AC_GOLD_3,  AC_GOLD_4,  RGBO(255,252,214)
;   TIER_PAL tier_diamond_pal, AC_DIAM_1,  AC_DIAM_2,  AC_DIAM_3,  AC_DIAM_4,  RGBO(240,255,254)
; (wood and stone have no specular: their glint is their highlight.) The wood tier's 1..4 are planks, lighter and
; yellower than the stick of the handle (a..d, AC_WOOD_1..4), so that a wood head or blade reads apart from its
; handle: a wood sword has a plank blade and a stick grip, told apart by the guard between them.
%include "common.inc"
%include "art.inc"
default rel

; TIER_ROLES ramp 1, ramp 2, ramp 3, ramp 4, glint: the roles every tier shares (no label, no terminator)
%macro TIER_ROLES 5
    PALC '1', %1
    PALC '2', %2
    PALC '3', %3
    PALC '4', %4
    PALC 'a', AC_WOOD_1
    PALC 'b', AC_WOOD_2
    PALC 'c', AC_WOOD_3
    PALC 'd', AC_WOOD_4
    PALC 'e', AC_LEATHER_1
    PALC 'f', AC_LEATHER_2
    PALC 'g', AC_LEATHER_3
    PALC 'h', AC_LEATHER_4
    PALC 's', %5
    PALC 'o', AC_OUTLINE
%endmacro

; TIER_PAL label, ramp 1, ramp 2, ramp 3, ramp 4, glint
%macro TIER_PAL 6
align 8
%1:
    TIER_ROLES %2, %3, %4, %5, %6
    dq 0
%endmacro

; TRIM_PAL label, ramp 1, ramp 2, ramp 3, ramp 4, glint, trim 1, trim 2, trim 3, trim 4
%macro TRIM_PAL 10
align 8
%1:
    TIER_ROLES %2, %3, %4, %5, %6
    PALC 'v', %7
    PALC 'w', %8
    PALC 'x', %9
    PALC 'y', %10
    dq 0
%endmacro


section .rodata

TIER_PAL tier_wood_pal, RGBO(228,190,118), RGBO(196,152,86), RGBO(150,108,58), RGBO(100,70,36), RGBO(228,190,118)
TIER_PAL tier_stone_pal, AC_STONE_1, AC_STONE_2, AC_STONE_3, AC_STONE_4, AC_STONE_1
TIER_PAL tier_iron_pal, AC_IRON_1, AC_IRON_2, AC_IRON_3, AC_IRON_4, RGBO(255,255,255)
TIER_PAL tier_gold_pal, AC_GOLD_1, AC_GOLD_2, AC_GOLD_3, AC_GOLD_4, RGBO(255,252,214)
TIER_PAL tier_diamond_pal, AC_DIAM_1, AC_DIAM_2, AC_DIAM_3, AC_DIAM_4, RGBO(240,255,254)
TRIM_PAL trim_iron_pal, AC_IRON_1, AC_IRON_2, AC_IRON_3, AC_IRON_4, RGBO(255,255,255), \
    RGBO(144,148,162), RGBO(106,110,124), RGBO(74,78,92), RGBO(50,52,66)
TRIM_PAL trim_diamond_pal, AC_DIAM_1, AC_DIAM_2, AC_DIAM_3, AC_DIAM_4, RGBO(240,255,254), \
    AC_GOLD_1, AC_GOLD_2, AC_GOLD_3, AC_GOLD_4

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
SKBMP ib_wood_sword, sword_rows, 32, 32, tier_wood_pal
align 8
SKBMP ib_stone_sword, sword_rows, 32, 32, tier_stone_pal
align 8
SKBMP ib_iron_sword, sword_rows, 32, 32, tier_iron_pal
align 8
SKBMP ib_gold_sword, sword_rows, 32, 32, tier_gold_pal
align 8
SKBMP ib_diamond_sword, sword_rows, 32, 32, tier_diamond_pal

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
SKBMP ib_wood_pickaxe, pickaxe_rows, 32, 32, tier_wood_pal
align 8
SKBMP ib_stone_pickaxe, pickaxe_rows, 32, 32, tier_stone_pal
align 8
SKBMP ib_iron_pickaxe, pickaxe_rows, 32, 32, tier_iron_pal
align 8
SKBMP ib_gold_pickaxe, pickaxe_rows, 32, 32, tier_gold_pal
align 8
SKBMP ib_diamond_pickaxe, pickaxe_rows, 32, 32, tier_diamond_pal

; --------------------------------------------------------------------------------------------------------------------
; axe: ib_<tier>_axe. axe_rows is the bitmap of every axe tier
;   A bearded head on the up-left side of the handle: the cutting edge faces the light (1 lit bevel, s glints), 2 the
;   blade, 3 the shaded eye and poll; the handle is the stick of the pickaxe (a lit edge, b body, c shaded edge, grain).
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS axe_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW ".....................44........."  ; 01
    SKROW "...................4412o........"  ; 02
    SKROW "..................41122o........"  ; 03
    SKROW ".................411222o........"  ; 04
    SKROW "................4s122222o......."  ; 05
    SKROW "...............4s12222233o......"  ; 06
    SKROW "..............411222223333o....."  ; 07
    SKROW "..............4122222333333o...."  ; 08
    SKROW ".............41222223333333o...."  ; 09
    SKROW "..............ooooo33333333o...."  ; 10
    SKROW "...................oo333333o...."  ; 11
    SKROW "...................dab3333o....."  ; 12
    SKROW "..................dabcoooo......"  ; 13
    SKROW ".................dacco.........."  ; 14
    SKROW "................dabco..........."  ; 15
    SKROW "...............dabco............"  ; 16
    SKROW "..............dabco............."  ; 17
    SKROW ".............dacco.............."  ; 18
    SKROW "............dabco..............."  ; 19
    SKROW "...........dabco................"  ; 20
    SKROW "..........dabco................."  ; 21
    SKROW ".........dacco.................."  ; 22
    SKROW "........dabco..................."  ; 23
    SKROW ".......dabco...................."  ; 24
    SKROW "......dabco....................."  ; 25
    SKROW ".....dacco......................"  ; 26
    SKROW "....dabco......................."  ; 27
    SKROW "....dbco........................"  ; 28
    SKROW ".....oo........................."  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_wood_axe, axe_rows, 32, 32, tier_wood_pal
align 8
SKBMP ib_stone_axe, axe_rows, 32, 32, tier_stone_pal
align 8
SKBMP ib_iron_axe, axe_rows, 32, 32, tier_iron_pal
align 8
SKBMP ib_gold_axe, axe_rows, 32, 32, tier_gold_pal
align 8
SKBMP ib_diamond_axe, axe_rows, 32, 32, tier_diamond_pal

; --------------------------------------------------------------------------------------------------------------------
; shovel: ib_<tier>_shovel. shovel_rows is the bitmap of every shovel tier
;   A spade blade on the stick of the pickaxe: 1 lit rim, 2 body, 3 shaded half, s glints on the rim and the tip.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS shovel_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW ".......................44444...."  ; 01
    SKROW "......................41ss12o..."  ; 02
    SKROW ".....................41111123o.."  ; 03
    SKROW "....................411222233o.."  ; 04
    SKROW "...................4s12222333o.."  ; 05
    SKROW "..................4s122223333o.."  ; 06
    SKROW "..................41122233333o.."  ; 07
    SKROW "..................4112233333o..."  ; 08
    SKROW "..................411233333o...."  ; 09
    SKROW "..................42233333o....."  ; 10
    SKROW ".................da233333o......"  ; 11
    SKROW "................dabcooooo......."  ; 12
    SKROW "...............dabco............"  ; 13
    SKROW "..............dacco............."  ; 14
    SKROW ".............dabco.............."  ; 15
    SKROW "............dabco..............."  ; 16
    SKROW "...........dabco................"  ; 17
    SKROW "..........dacco................."  ; 18
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
SKBMP ib_wood_shovel, shovel_rows, 32, 32, tier_wood_pal
align 8
SKBMP ib_stone_shovel, shovel_rows, 32, 32, tier_stone_pal
align 8
SKBMP ib_iron_shovel, shovel_rows, 32, 32, tier_iron_pal
align 8
SKBMP ib_gold_shovel, shovel_rows, 32, 32, tier_gold_pal
align 8
SKBMP ib_diamond_shovel, shovel_rows, 32, 32, tier_diamond_pal

; --------------------------------------------------------------------------------------------------------------------
; bow: ib_bow (BOW)
;   Belly up and to the right, the string the straight light/shade line on the main diagonal from nock to nock;
;   the grip is a leather wrap, the nocks are bone.
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
; celestial bow: ib_celestial_bow (CELESTIAL_BOW)
;   The bow in white and sky blue 1 2 3 4, a gold grip wrap and gold tips i j k l with a star gem v w x y, a glowing
;   string t u.
; --------------------------------------------------------------------------------------------------------------------
align 8
cbow_pal:
    PALC '1', RGBO(250,254,255)             ; limb, the white of the lit edge
    PALC '2', RGBO(176,232,255)             ; limb, pale blue
    PALC '3', RGBO(104,186,238)             ; limb, sky blue
    PALC '4', RGBO(48,110,184)              ; limb, deep blue; selective outline
    PALC 'i', AC_GOLD_1
    PALC 'j', AC_GOLD_2
    PALC 'k', AC_GOLD_3
    PALC 'l', AC_GOLD_4                     ; gold grip wrap and wing tips; selective outline
    PALC 'v', RGBO(255,255,255)             ; star gem, 1 highlight
    PALC 'w', RGBO(170,244,255)             ; star gem
    PALC 't', RGBO(226,252,255)             ; string, light
    PALC 'u', RGBO(110,190,236)             ; string, shade
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS cbow_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW ".............4444444444........."  ; 01
    SKROW "........l44441111111111o4......."  ; 02
    SKROW ".....llli1111112221111122ol....."  ; 03
    SKROW "....liii2333333333333321lijo...."  ; 04
    SKROW "...liooooooooooooooo322liwkio..."  ; 05
    SKROW "....out.............ooliwvwjo..."  ; 06
    SKROW "......ut..............ojkwjl3o.."  ; 07
    SKROW ".......ut..............oijl33o.."  ; 08
    SKROW "........ut..............ol2233o."  ; 09
    SKROW ".........ut..............o2233o."  ; 10
    SKROW "..........ut.............42233o."  ; 11
    SKROW "...........ut.............o133o."  ; 12
    SKROW "............ut............4133o."  ; 13
    SKROW ".............ut...........4123o."  ; 14
    SKROW "..............ut..........4123o."  ; 15
    SKROW "...............ut.........4123o."  ; 16
    SKROW "................ut........4133o."  ; 17
    SKROW ".................ut.......4133o."  ; 18
    SKROW "..................ut......413o.."  ; 19
    SKROW "...................ut.....413o.."  ; 20
    SKROW "....................ut....413o.."  ; 21
    SKROW ".....................ut...413o.."  ; 22
    SKROW "......................ut..42jo.."  ; 23
    SKROW ".......................ut.ljo..."  ; 24
    SKROW "........................utljo..."  ; 25
    SKROW ".........................uljo..."  ; 26
    SKROW ".........................ljo...."  ; 27
    SKROW "..........................o....."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_celestial_bow, cbow_rows, 32, 32, cbow_pal

; --------------------------------------------------------------------------------------------------------------------
; arrow: ib_arrow (ARROW)
;   Steel head 1 2 3 4, wood shaft a c, two fletching vanes that flare to the tail: a red cock feather R Q N and a
;   white feather F G H I.
; --------------------------------------------------------------------------------------------------------------------
align 8
arrow_pal:
    PALC '1', AC_IRON_1
    PALC '2', AC_IRON_2
    PALC '3', AC_IRON_3
    PALC '4', AC_IRON_4                     ; steel head; selective outline
    PALC 'a', AC_WOOD_1
    PALC 'c', AC_WOOD_3
    PALC 'd', AC_WOOD_4                     ; shaft; selective outline
    PALC 'F', RGBO(252,252,248)             ; feather, light
    PALC 'G', RGBO(224,226,232)             ; feather
    PALC 'H', RGBO(174,180,196)             ; feather, shade
    PALC 'R', RGBO(222,70,60)               ; cock feather, mid
    PALC 'Q', RGBO(160,40,46)               ; cock feather, shade
    PALC 'N', RGBO(100,24,32)               ; cock feather, darkest: its selective outline
    PALC 's', RGBO(255,255,255)             ; glint
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS arrow_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "............................4..."  ; 02
    SKROW "...........................41o.."  ; 03
    SKROW ".........................44s3o.."  ; 04
    SKROW "........................4s23o..."  ; 05
    SKROW "......................441233o..."  ; 06
    SKROW ".....................412233o...."  ; 07
    SKROW "....................4122333o...."  ; 08
    SKROW "...................4122333o....."  ; 09
    SKROW "..................41oaco3o......"  ; 10
    SKROW "...................oaco.o......."  ; 11
    SKROW "..................daco.........."  ; 12
    SKROW ".................daco..........."  ; 13
    SKROW "................daco............"  ; 14
    SKROW "...............daco............."  ; 15
    SKROW "..............daco.............."  ; 16
    SKROW ".............daco..............."  ; 17
    SKROW "............daco................"  ; 18
    SKROW "...........daco................."  ; 19
    SKROW ".........Ndaco.................."  ; 20
    SKROW "........NQacGo.................."  ; 21
    SKROW "......NNQacGo..................."  ; 22
    SKROW ".....NRQacGFo..................."  ; 23
    SKROW "...NNRQacGFo...................."  ; 24
    SKROW "..NRRQacGFFo...................."  ; 25
    SKROW ".NQQQacHHHo....................."  ; 26
    SKROW "..ooacoooo......................"  ; 27
    SKROW "....oo.........................."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_arrow, arrow_rows, 32, 32, arrow_pal

; --------------------------------------------------------------------------------------------------------------------
; staff: ib_staff (STAFF)
;   Wood shaft a b c with a leather wrap e f g h and a gold ferrule, a gold collar and cradle i j k l around a ruby
;   v w x y.
; --------------------------------------------------------------------------------------------------------------------
align 8
staff_pal:
    PALC 'a', AC_WOOD_1
    PALC 'b', AC_WOOD_2
    PALC 'c', AC_WOOD_3
    PALC 'd', AC_WOOD_4                     ; shaft; selective outline
    PALC 'e', AC_LEATHER_1
    PALC 'f', AC_LEATHER_2
    PALC 'g', AC_LEATHER_3
    PALC 'h', AC_LEATHER_4                  ; grip wrap
    PALC 'i', AC_GOLD_1
    PALC 'j', AC_GOLD_2
    PALC 'k', AC_GOLD_3
    PALC 'l', AC_GOLD_4                     ; ferrule, collar and cradle; selective outline
    PALC 'v', RGBO(255,214,214)             ; ruby, 1 highlight
    PALC 'w', RGBO(236,72,84)               ; ruby
    PALC 'x', RGBO(190,28,52)               ; ruby
    PALC 'y', RGBO(120,14,38)               ; ruby, deepest; selective outline
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS staff_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "......................yyyy......"  ; 01
    SKROW ".....................yvwwwo....."  ; 02
    SKROW "....................yvwwwwxo...."  ; 03
    SKROW "...................yvwwwwxxxo..."  ; 04
    SKROW "..................liwwwwxxxyko.."  ; 05
    SKROW "..................liwwwxxxyyko.."  ; 06
    SKROW "..................ljwwxxxyyyko.."  ; 07
    SKROW "..................ljjxxxyyykko.."  ; 08
    SKROW "..................lijjxyyykko..."  ; 09
    SKROW ".................ljijjjkkkko...."  ; 10
    SKROW ".................dakkkooooo....."  ; 11
    SKROW "................dabclo.........."  ; 12
    SKROW "...............dabcoo..........."  ; 13
    SKROW "..............dabco............."  ; 14
    SKROW ".............dabco.............."  ; 15
    SKROW "............dabco..............."  ; 16
    SKROW "...........dabco................"  ; 17
    SKROW "..........hffco................."  ; 18
    SKROW ".........hegho.................."  ; 19
    SKROW "........hffgo..................."  ; 20
    SKROW ".......hegho...................."  ; 21
    SKROW "......dafgo....................."  ; 22
    SKROW ".....dabco......................"  ; 23
    SKROW "....dabco......................."  ; 24
    SKROW "...dabco........................"  ; 25
    SKROW "..lijco........................."  ; 26
    SKROW "..ljko.........................."  ; 27
    SKROW "...oo..........................."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_staff, staff_rows, 32, 32, staff_pal

; --------------------------------------------------------------------------------------------------------------------
; archmage staff: ib_archmage_staff (ARCHMAGE_STAFF)
;   A twisted violet shaft a b c d with gold rings, a gold collar and three claws i j k l around a cyan orb v w x y.
; --------------------------------------------------------------------------------------------------------------------
align 8
astaff_pal:
    PALC 'a', RGBO(122,92,168)              ; shaft, violet: lit
    PALC 'b', RGBO(92,64,132)
    PALC 'c', RGBO(64,42,98)
    PALC 'd', RGBO(40,26,64)                ; shaft, deepest; selective outline
    PALC 'i', AC_GOLD_1
    PALC 'j', AC_GOLD_2
    PALC 'k', AC_GOLD_3
    PALC 'l', AC_GOLD_4                     ; rings, collar and claws; selective outline
    PALC 'v', RGBO(232,255,255)             ; orb, 1 highlight
    PALC 'w', RGBO(110,236,240)             ; orb
    PALC 'x', RGBO(48,178,206)              ; orb
    PALC 'y', RGBO(22,110,140)              ; orb, deepest; selective outline
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS astaff_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "......................yyy......."  ; 01
    SKROW "....................yyvwwoy....."  ; 02
    SKROW "...............w..lyvvwwwwxo...."  ; 03
    SKROW "..............wvwliivwwwwxxo...."  ; 04
    SKROW "...............w.livwwwwxxxyo..."  ; 05
    SKROW ".................liwwwwxxxyyo..."  ; 06
    SKROW ".................liwwwxxxyyyko.."  ; 07
    SKROW ".................ljwwxxxyyykko.."  ; 08
    SKROW "..................ooxxxyyyyko..."  ; 09
    SKROW ".................liioxyyyooko..."  ; 10
    SKROW ".................ljjkjkko..o...."  ; 11
    SKROW "................dbblkooo....w..."  ; 12
    SKROW "...............dbcdoo......wvw.."  ; 13
    SKROW "..............lijdo.........w..."  ; 14
    SKROW ".............dbbko.............."  ; 15
    SKROW "............dbcdo..............."  ; 16
    SKROW "...........dabdo................"  ; 17
    SKROW "..........dbbco................."  ; 18
    SKROW ".........ljkdo.................."  ; 19
    SKROW "........dablo..................."  ; 20
    SKROW ".......dbbco...................."  ; 21
    SKROW "......dbcdo....................."  ; 22
    SKROW ".....dabdo......................"  ; 23
    SKROW "....dbbco......................."  ; 24
    SKROW "...dbcdo........................"  ; 25
    SKROW "..libdo........................."  ; 26
    SKROW "..ljko.........................."  ; 27
    SKROW "...oo..........................."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_archmage_staff, astaff_rows, 32, 32, astaff_pal

; --------------------------------------------------------------------------------------------------------------------
; dagger: ib_iron_dagger, ib_diamond_dagger. dagger_rows is the bitmap of both tiers
;   A short broad leaf blade 1 lit edge, 2 lit facet, 3 shaded facet, s glints; a thick crossguard and a ball pommel in
;   the trim ramp v w x y (iron: blackened steel, diamond: gold); a leather grip wrap e f g h.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS dagger_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW "...........................4...."  ; 03
    SKROW "..........................41o..."  ; 04
    SKROW "........................4413o..."  ; 05
    SKROW ".......................4123o...."  ; 06
    SKROW ".....................441233o...."  ; 07
    SKROW "....................4s2233o....."  ; 08
    SKROW "..................44s22333o....."  ; 09
    SKROW ".................41222333o......"  ; 10
    SKROW "................41222333o......."  ; 11
    SKROW "...........yyyy41222333o........"  ; 12
    SKROW "..........yvwxy1222333o........."  ; 13
    SKROW "...........ovwxy22333o.........."  ; 14
    SKROW "............owxyyoooo..........."  ; 15
    SKROW ".............owxyyo............."  ; 16
    SKROW "............hhowxyyo............"  ; 17
    SKROW "...........hfghoxyyyo..........."  ; 18
    SKROW "..........hfgho.oxyyyo.........."  ; 19
    SKROW ".........hefgo...oooo..........."  ; 20
    SKROW "........hefgo..................."  ; 21
    SKROW ".......hfgho...................."  ; 22
    SKROW "...yyyhfgho....................."  ; 23
    SKROW "..ywwwoooo......................"  ; 24
    SKROW ".ywwwxxo........................"  ; 25
    SKROW ".ywwxxyo........................"  ; 26
    SKROW ".ywxxyyo........................"  ; 27
    SKROW "..oxyyo........................."  ; 28
    SKROW "...ooo.........................."  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_iron_dagger, dagger_rows, 32, 32, trim_iron_pal
align 8
SKBMP ib_diamond_dagger, dagger_rows, 32, 32, trim_diamond_pal

; --------------------------------------------------------------------------------------------------------------------
; shadow fang: ib_shadow_fang (SHADOW_FANG)
;   A curved black-violet blade, 1 the glowing violet edge, 2 lit, 3 shaded; a crescent guard with upturned tips and a
;   magenta gem v w x y, a dark violet grip wrap and pommel ball e f g h.
; --------------------------------------------------------------------------------------------------------------------
align 8
fang_pal:
    PALC '1', RGBO(196,128,255)             ; violet edge glow
    PALC '2', RGBO(104,62,156)              ; blade, lit
    PALC '3', RGBO(62,34,98)                ; blade, shaded
    PALC '4', RGBO(30,16,48)                ; blade, deepest; selective outline
    PALC 'e', RGBO(112,82,150)              ; grip wrap, dark violet
    PALC 'f', RGBO(86,58,122)
    PALC 'g', RGBO(62,40,90)
    PALC 'h', RGBO(38,24,58)
    PALC 'v', RGBO(255,190,250)             ; gem, 1 highlight
    PALC 'w', RGBO(240,80,228)              ; gem
    PALC 'x', RGBO(176,36,168)              ; gem
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS fang_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW ".........................4......"  ; 02
    SKROW "........................41o....."  ; 03
    SKROW "........................41o....."  ; 04
    SKROW ".......................412o....."  ; 05
    SKROW ".......................41o......"  ; 06
    SKROW "......................412o......"  ; 07
    SKROW ".....................4122o......"  ; 08
    SKROW "....................41132o......"  ; 09
    SKROW "...................41122o......."  ; 10
    SKROW "..................411232o......."  ; 11
    SKROW ".................4112232o......."  ; 12
    SKROW "................4112232o........"  ; 13
    SKROW "..............441222332o........"  ; 14
    SKROW "............4411222232o........."  ; 15
    SKROW "...........41oo2222332o........."  ; 16
    SKROW "..........41o..o22332o.........."  ; 17
    SKROW ".........4111o..o3332o.........."  ; 18
    SKROW "..........o122o..o32o..........."  ; 19
    SKROW "...........o3vwo..o2o..........."  ; 20
    SKROW "...........hfxx3o.4o............"  ; 21
    SKROW "..........hegh333o3o............"  ; 22
    SKROW "......hhhhffgoo333o............."  ; 23
    SKROW ".....heeefgho..o3o.............."  ; 24
    SKROW ".....heeffgo....o..............."  ; 25
    SKROW ".....heffgo....................."  ; 26
    SKROW ".....hffggo....................."  ; 27
    SKROW "......oooo......................"  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_shadow_fang, fang_rows, 32, 32, fang_pal

; --------------------------------------------------------------------------------------------------------------------
; king's blade: ib_kings_blade (KINGS_BLADE)
;   A white-gold blade 1 2 3 4 with a fuller, a gold horned guard i j k l around a ruby v w x y, a red grip wrap
;   e f g h, a gold pommel ball.
; --------------------------------------------------------------------------------------------------------------------
align 8
kblade_pal:
    PALC '1', RGBO(255,255,240)             ; blade, white gold: the lit edge
    PALC '2', RGBO(252,240,196)
    PALC '3', RGBO(232,200,110)
    PALC '4', RGBO(170,124,40)              ; blade, deepest; selective outline
    PALC 'e', RGBO(196,76,76)               ; grip wrap, red
    PALC 'f', RGBO(156,44,52)
    PALC 'g', RGBO(112,28,38)
    PALC 'h', RGBO(70,16,26)
    PALC 'i', AC_GOLD_1
    PALC 'j', AC_GOLD_2
    PALC 'k', AC_GOLD_3
    PALC 'l', AC_GOLD_4                     ; guard and pommel; selective outline
    PALC 'v', RGBO(255,214,214)             ; ruby, 1 highlight
    PALC 'x', RGBO(190,28,52)               ; ruby
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS kblade_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "............................4..."  ; 02
    SKROW "..........................442o.."  ; 03
    SKROW "........................4422o..."  ; 04
    SKROW "......................441223o..."  ; 05
    SKROW ".....................411223o...."  ; 06
    SKROW "....................4111333o...."  ; 07
    SKROW "...................4111333o....."  ; 08
    SKROW "..................41113333o....."  ; 09
    SKROW ".................41113333o......"  ; 10
    SKROW "................41113333o......."  ; 11
    SKROW "...............41113333o........"  ; 12
    SKROW "..............41113333o........."  ; 13
    SKROW "........l....41113333o.........."  ; 14
    SKROW ".......lio..41113333o..........."  ; 15
    SKROW "......liio.41113333o............"  ; 16
    SKROW ".....lkjio41123333o............."  ; 17
    SKROW "......okjio122333o.............."  ; 18
    SKROW ".......okjiii333o..............."  ; 19
    SKROW "........okvvi33o................"  ; 20
    SKROW "........kkxxioo................."  ; 21
    SKROW ".......hekkkjioii..............."  ; 22
    SKROW "...lllhffgookjiiio.............."  ; 23
    SKROW "..ljjjkgho..okjio..............."  ; 24
    SKROW "..ljjkkgo....oko................"  ; 25
    SKROW "..ljkklo......o................."  ; 26
    SKROW "..lkkllo........................"  ; 27
    SKROW "...oooo........................."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_kings_blade, kblade_rows, 32, 32, kblade_pal

; --------------------------------------------------------------------------------------------------------------------
; hammer: ib_iron_hammer, ib_diamond_hammer. hammer_rows is the bitmap of both tiers
;   A war hammer, 27 px across: a 12-tall block head (1 lit top, 2 body, 3 shaded underside, rivets and glints) between
;   two flanges in the trim ramp v w x y (iron: blackened steel, diamond: gold), a striking face on the right (a trim
;   rim around a 1 / 2 plate) and a tapering poll spike on the left; a trim collar, a thick stick handle with a leather
;   wrap e f g h and a trim butt cap, 29 px along the diagonal.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS hammer_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "..........yyy444444444444yyyyyo."  ; 02
    SKROW "..........yvv1ss111111111vvvvvo."  ; 03
    SKROW "..........ysv1s1111111111svws1o."  ; 04
    SKROW ".......444yvv222222222222vvws1o."  ; 05
    SKROW "......4111yww222222222222www11o."  ; 06
    SKROW "....41s222yww223222222322www11o."  ; 07
    SKROW "....o33333yww222222222222www22o."  ; 08
    SKROW ".....oo333yww333333333333www22o."  ; 09
    SKROW ".......oooyxx333333333333xxw22o."  ; 10
    SKROW "..........yyx333333333333xyw32o."  ; 11
    SKROW "..........yxx333333333333xxxxxo."  ; 12
    SKROW "..........ooooooooooooooooooooo."  ; 13
    SKROW "................yvwwwxxo........"  ; 14
    SKROW "...............ywwwxxyo........."  ; 15
    SKROW "...............dacbco..........."  ; 16
    SKROW "..............dabbco............"  ; 17
    SKROW ".............dacbco............."  ; 18
    SKROW "............hefffo.............."  ; 19
    SKROW "...........hfffgo..............."  ; 20
    SKROW "..........hhhhgo................"  ; 21
    SKROW ".........hfffgo................."  ; 22
    SKROW "........hefffo.................."  ; 23
    SKROW ".......hhhhgo..................."  ; 24
    SKROW "......hefffo...................."  ; 25
    SKROW ".....dabbco....................."  ; 26
    SKROW "...yvwwxyo......................"  ; 27
    SKROW "..ywwxxyo......................."  ; 28
    SKROW "..ywxxyo........................"  ; 29
    SKROW "...oooo........................."  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_iron_hammer, hammer_rows, 32, 32, trim_iron_pal
align 8
SKBMP ib_diamond_hammer, hammer_rows, 32, 32, trim_diamond_pal

; --------------------------------------------------------------------------------------------------------------------
; spear: ib_iron_spear, ib_diamond_spear. spear_rows is the bitmap of both tiers
;   A leaf head 1 lit half, 2 ridge, 3 shaded half on a trim collar with two lugs v w x y (iron: blackened steel,
;   diamond: gold), a thin stick a c with a leather wrap e f g h and a trim butt spike.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS spear_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "..........................44...."  ; 02
    SKROW ".......................44412o..."  ; 03
    SKROW ".....................4411123o..."  ; 04
    SKROW "....................4111123o...."  ; 05
    SKROW "...................41111233o...."  ; 06
    SKROW "...................41112333o...."  ; 07
    SKROW "..................41112333o....."  ; 08
    SKROW ".................yv1123333o....."  ; 09
    SKROW "................yvvw23333o......"  ; 10
    SKROW "................ywwww33oo......."  ; 11
    SKROW ".................oxwxxo........."  ; 12
    SKROW "................dacyxo.........."  ; 13
    SKROW "...............dacooo..........."  ; 14
    SKROW "..............daco.............."  ; 15
    SKROW ".............daco..............."  ; 16
    SKROW "............hego................"  ; 17
    SKROW "...........hfho................."  ; 18
    SKROW "..........hego.................."  ; 19
    SKROW ".........hfho..................."  ; 20
    SKROW "........hego...................."  ; 21
    SKROW ".......daco....................."  ; 22
    SKROW "......daco......................"  ; 23
    SKROW ".....daco......................."  ; 24
    SKROW "....daco........................"  ; 25
    SKROW "...ywco........................."  ; 26
    SKROW "..ywyo.........................."  ; 27
    SKROW "...oo..........................."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_iron_spear, spear_rows, 32, 32, trim_iron_pal
align 8
SKBMP ib_diamond_spear, spear_rows, 32, 32, trim_diamond_pal

; --------------------------------------------------------------------------------------------------------------------
; flint and steel: ib_flint_and_steel (FLINT_AND_STEEL)
;   A steel striker loop 1 2 3 4 at the grip end, a faceted flint J K L M at the tip, sparks S T U between them.
; --------------------------------------------------------------------------------------------------------------------
align 8
fns_pal:
    PALC '1', AC_IRON_1
    PALC '2', AC_IRON_2
    PALC '3', AC_IRON_3
    PALC '4', AC_IRON_4                     ; steel striker; selective outline
    PALC 'J', RGBO(166,168,182)             ; flint, lit facet
    PALC 'K', RGBO(108,110,126)             ; flint
    PALC 'L', RGBO(70,72,88)                ; flint, shaded facet
    PALC 'M', RGBO(40,42,54)                ; flint, deepest: its selective outline
    PALC 'S', RGBO(255,250,200)             ; spark, core
    PALC 'T', RGBO(255,190,60)              ; spark
    PALC 'U', RGBO(230,100,30)              ; spark, ember
    PALC 's', RGBO(255,255,255)             ; glint
    PALC 'o', AC_OUTLINE
    dq 0
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS fns_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW ".......................MM......."  ; 01
    SKROW "....................MMMJJo......"  ; 02
    SKROW "...................MJJJJJJoMM..."  ; 03
    SKROW "..................MJJsJJJKKKKo.."  ; 04
    SKROW ".................MJJsJJJKKKKKo.."  ; 05
    SKROW ".................MJJJJJKKKKKKo.."  ; 06
    SKROW ".................MJJJJKKKKKKKo.."  ; 07
    SKROW "................MJJJJLKKKKKKKo.."  ; 08
    SKROW "................MJJLLLLKKKKKo..."  ; 09
    SKROW "................MJLLLLLLLKKo...."  ; 10
    SKROW ".............U...oLLLLLLLLLo...."  ; 11
    SKROW "...............T..ooLLLLLLLo...."  ; 12
    SKROW "..............TST...oLLLooo....."  ; 13
    SKROW ".........4444U.T.....ooo........"  ; 14
    SKROW "........4s222o...U.............."  ; 15
    SKROW ".......4s22222o................."  ; 16
    SKROW "......4122oo223o................"  ; 17
    SKROW ".....4122o..o333o..............."  ; 18
    SKROW "....4122o....o334o.............."  ; 19
    SKROW "...4122o......o44o.............."  ; 20
    SKROW "...422o.......444o.............."  ; 21
    SKROW "...422o......4444o.............."  ; 22
    SKROW "...4222o....4444o..............."  ; 23
    SKROW "....o223o..4444o................"  ; 24
    SKROW ".....o333o4444o................."  ; 25
    SKROW "......o334444o.................."  ; 26
    SKROW ".......o4444o..................."  ; 27
    SKROW "........oooo...................."  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_flint_and_steel, fns_rows, 32, 32, fns_pal
