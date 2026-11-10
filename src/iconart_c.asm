; iconart_c.asm - the 32x32 item icons of the armour, the firearms, the ammunition and the gun attachments: part C of
; the 0.13 "looks" art (28 icons: the 12 armour pieces, the 7 firearms, the 5 ammunition items and the 4 attachments;
; iconart_a.asm holds the tools and the other weapons, iconart_b.asm the remaining items). The file holds the validated
; style samples ib_iron_chestplate and ib_revolver and draws the rest of the set in the same style.
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
;   - armour is a front view (the boots a side view) of plates bevelled the same way: a lit rim 1 on the top and left,
;     the body 2, a shaded rim 3, and 4 where two plates meet; the left half of a symmetrical piece is lit (1 2), the
;     right half shaded (3 4). Firearms are side views, muzzle to the right, grip at the bottom left; ammunition
;     stands upright (the rocket too), the scope, the barrel and the compensator lie like the guns they fit and the
;     magazine stands upright
;
; Role chars. One char means the same role in every bitmap of this file, so that a tier is a palette, not a bitmap:
;   1 2 3 4   the primary material, 1 highlight, 2 lit, 3 shaded, 4 deepest (also its selective outline):
;             the tier metal of a piece of armour (AC_<TIER>_1..4), the steel of a gun (AC_IRON_1..4)
;   a b c d   wood: gun stocks, fore-ends (AC_WOOD_1..4)
;   e f g h   leather: belts, cuffs, linings, soles, magazines (AC_LEATHER_1..4)
;   i j k l   gold: brass fittings and cartridge cases (AC_GOLD_1..4)
;   v w x y   blued steel: receivers, grips, scope tubes, the dark mass of a gun (RGBO, gear_pal only)
;   A B C D   olive: the launcher tube and the rocket body
;   R S T U   red: the rocket nose, the shotgun hulls
;   K P Q W   copper: bullet jackets
;   L M N     glass: the scope lens
;   s         the white glint of metal
;   o         AC_OUTLINE
; A bitmap only uses the roles it needs; take a new role from a free letter and list it here.
;
; Tiers. The 12 armour pieces are drawn once per piece kind (helmet_rows, chestplate_rows, leggings_rows, boots_rows)
; and share it across iron, gold and diamond: one SKBMP line per item pairs the rows with the palette of its tier.
; TIER_PAL builds that palette: the tier ramp as 1..4, the glint colour of the tier's material, and the roles every
; tier shares (wood, leather, outline). A fourth tier is one more TIER_PAL line and three more SKBMP lines.
; Everything else (guns, ammunition, attachments) draws from gear_pal, the palette of the roles above.
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

TIER_PAL tier_iron_pal,    AC_IRON_1, AC_IRON_2, AC_IRON_3, AC_IRON_4, RGBO(255,255,255)
TIER_PAL tier_gold_pal,    AC_GOLD_1, AC_GOLD_2, AC_GOLD_3, AC_GOLD_4, RGBO(255,252,214)
TIER_PAL tier_diamond_pal, AC_DIAM_1, AC_DIAM_2, AC_DIAM_3, AC_DIAM_4, RGBO(240,255,254)

align 8
gear_pal:
    PALC '1', AC_IRON_1                         ; steel: highlight, glints on barrels and slides
    PALC '2', AC_IRON_2                         ; steel: lit
    PALC '3', AC_IRON_3                         ; steel: shaded
    PALC '4', AC_IRON_4                         ; steel: deepest, selective outline
    PALC 'a', AC_WOOD_1                         ; wood: highlight
    PALC 'b', AC_WOOD_2                         ; wood: lit
    PALC 'c', AC_WOOD_3                         ; wood: shaded, grain
    PALC 'd', AC_WOOD_4                         ; wood: deepest, selective outline
    PALC 'e', AC_LEATHER_1                      ; leather: highlight
    PALC 'f', AC_LEATHER_2                      ; leather: lit
    PALC 'g', AC_LEATHER_3                      ; leather: shaded
    PALC 'h', AC_LEATHER_4                      ; leather: deepest, seams, selective outline
    PALC 'i', AC_GOLD_1                         ; brass: highlight
    PALC 'j', AC_GOLD_2                         ; brass: lit
    PALC 'k', AC_GOLD_3                         ; brass: shaded
    PALC 'l', AC_GOLD_4                         ; brass: deepest, selective outline
    PALC 'v', RGBO(134,140,158)                 ; blued steel (receivers, grips, scope tubes): highlight
    PALC 'w', RGBO(100,106,124)                 ; blued steel: lit
    PALC 'x', RGBO(70,74,90)                    ; blued steel: shaded
    PALC 'y', RGBO(44,46,58)                    ; blued steel: deepest, selective outline
    PALC 'A', RGBO(170,190,112)                 ; olive: highlight
    PALC 'B', RGBO(122,150,78)                  ; olive: lit
    PALC 'C', RGBO(84,108,54)                   ; olive: shaded
    PALC 'D', RGBO(52,70,38)                    ; olive: deepest, selective outline
    PALC 'R', RGBO(255,150,120)                 ; red: highlight
    PALC 'S', RGBO(226,70,60)                   ; red: lit
    PALC 'T', RGBO(170,36,40)                   ; red: shaded
    PALC 'U', RGBO(110,22,32)                   ; red: deepest, selective outline
    PALC 'K', RGBO(255,205,150)                 ; copper: highlight
    PALC 'P', RGBO(226,138,76)                  ; copper: lit
    PALC 'Q', RGBO(172,88,48)                   ; copper: shaded
    PALC 'W', RGBO(112,52,32)                   ; copper: deepest, selective outline
    PALC 'L', RGBO(120,200,240)                 ; glass: highlight
    PALC 'M', RGBO(60,130,190)                  ; glass: lit
    PALC 'N', RGBO(28,70,120)                   ; glass: deepest, selective outline
    PALC 's', RGBO(255,255,255)                 ; glint
    PALC 'o', AC_OUTLINE                        ; outline
    dq 0

; --------------------------------------------------------------------------------------------------------------------
; helmet: ib_iron_helmet, ib_gold_helmet, ib_diamond_helmet. helmet_rows is the bitmap of every helmet tier
;   Front view of an open-face helmet: a stepped crest on a faceted dome (a short s streak glints on the lit facet),
;   a riveted brow band, a leather lining (g h) showing through the face opening under the brow, the nose guard
;   down the middle, cheek guards curving in to the jaw and a neck plate closing the bottom.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS helmet_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW "..............412o.............."  ; 03
    SKROW ".............41232o............."  ; 04
    SKROW "...........411123222o..........."  ; 05
    SKROW ".........4111222333222o........."  ; 06
    SKROW "........4111s2223333222o........"  ; 07
    SKROW ".......4112s222233333322o......."  ; 08
    SKROW "......4112s22222333333322o......"  ; 09
    SKROW ".....411222222223333333322o....."  ; 10
    SKROW ".....412222222223333333332o....."  ; 11
    SKROW "....41222222222233333333332o...."  ; 12
    SKROW "....43333333333344444444444o...."  ; 13
    SKROW "....41111111111122222222222o...."  ; 14
    SKROW "....422s2222222233333333s33o...."  ; 15
    SKROW "....43333333333344444444444o...."  ; 16
    SKROW "....412223ggggg13ggggg43332o...."  ; 17
    SKROW "....412223hhhhh134hhhh43332o...."  ; 18
    SKROW "....4122223hhhh134hhh433332o...."  ; 19
    SKROW "....4122223hhhh134hhh433332o...."  ; 20
    SKROW ".....412223hhhh134hhh43332o....."  ; 21
    SKROW ".....4122223hhh134hh433332o....."  ; 22
    SKROW "......412223hhh134hh43332o......"  ; 23
    SKROW "......4122223hhoohh433332o......"  ; 24
    SKROW ".......41233333434444432o......."  ; 25
    SKROW "........434444444444444o........"  ; 26
    SKROW ".........oooooooooooooo........."  ; 27
    SKROW "................................"  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_iron_helmet, helmet_rows, 32, 32, tier_iron_pal
align 8
SKBMP ib_gold_helmet, helmet_rows, 32, 32, tier_gold_pal
align 8
SKBMP ib_diamond_helmet, helmet_rows, 32, 32, tier_diamond_pal

; --------------------------------------------------------------------------------------------------------------------
; chestplate: ib_iron_chestplate, ib_gold_chestplate, ib_diamond_chestplate. chestplate_rows is the bitmap of every
;   chestplate tier
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
align 8
SKBMP ib_gold_chestplate, chestplate_rows, 32, 32, tier_gold_pal
align 8
SKBMP ib_diamond_chestplate, chestplate_rows, 32, 32, tier_diamond_pal

; --------------------------------------------------------------------------------------------------------------------
; leggings: ib_iron_leggings, ib_gold_leggings, ib_diamond_leggings. leggings_rows is the bitmap of every leggings tier
;   Front view: a leather belt with the buckle of the chestplate across the top, a riveted hip plate, then two legs,
;   each a thigh plate, a rounded knee cop with an s rivet and a shin guard flaring at the ankle; the gap between
;   the legs shows the background.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS leggings_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW ".....hhhhhhhhh1122hhhhhhhhh....."  ; 03
    SKROW ".....heeeeeeee1442eeeeeeeeo....."  ; 04
    SKROW ".....hffffffff2442ffffffffo....."  ; 05
    SKROW ".....hgggggggg2443ggggggggo....."  ; 06
    SKROW "...4444444444422334444444444o..."  ; 07
    SKROW "...4111111111111222222222222o..."  ; 08
    SKROW "...411s222222222333333333s22o..."  ; 09
    SKROW "...4112222222222333333333322o..."  ; 10
    SKROW "...4112222222222333333333322o..."  ; 11
    SKROW "...4233333333333444444444443o..."  ; 12
    SKROW "...44444444444o..44444444444o..."  ; 13
    SKROW "...41222222223o..44333333332o..."  ; 14
    SKROW "...41222222223o..44333333332o..."  ; 15
    SKROW "...41222222223o..44333333332o..."  ; 16
    SKROW "...41111111113o..44222222222o..."  ; 17
    SKROW "...41122222223o..44333333322o..."  ; 18
    SKROW "..41122s222223o..4433333s3322o.."  ; 19
    SKROW "..411222222223o..443333333322o.."  ; 20
    SKROW "...42333333333o..44444444443o..."  ; 21
    SKROW "....412222223o....443333332o...."  ; 22
    SKROW "....412222223o....443333332o...."  ; 23
    SKROW "....412222223o....443333332o...."  ; 24
    SKROW "...41222222223o..44333333332o..."  ; 25
    SKROW "...42333333333o..44444444443o..."  ; 26
    SKROW "....oooooooooo....oooooooooo...."  ; 27
    SKROW "................................"  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_iron_leggings, leggings_rows, 32, 32, tier_iron_pal
align 8
SKBMP ib_gold_leggings, leggings_rows, 32, 32, tier_gold_pal
align 8
SKBMP ib_diamond_leggings, leggings_rows, 32, 32, tier_diamond_pal

; --------------------------------------------------------------------------------------------------------------------
; boots: ib_iron_boots, ib_gold_boots, ib_diamond_boots. boots_rows is the bitmap of every boots tier
;   One boot in side view, toe to the right: a rolled leather cuff, a greave plate with s rivets and a leather
;   strap with a buckle of the tier metal, a foot plate with a raised toe cap, a leather heel and sole.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS boots_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW "................................"  ; 03
    SKROW ".....hhhhhhhhhh................."  ; 04
    SKROW "....heeeeeeeeeeo................"  ; 05
    SKROW "....hffffffffffo................"  ; 06
    SKROW "....hggggggggggo................"  ; 07
    SKROW "....hhhhhhhhhhho................"  ; 08
    SKROW ".....o11111122o................."  ; 09
    SKROW ".....41s2222s3o................."  ; 10
    SKROW ".....412222223o................."  ; 11
    SKROW ".....412211123o................."  ; 12
    SKROW ".....hfff242ffo................."  ; 13
    SKROW ".....hggg333ggo................."  ; 14
    SKROW ".....412222223o................."  ; 15
    SKROW ".....41s222223o................."  ; 16
    SKROW ".....412222223o4................"  ; 17
    SKROW ".....42222222322o444444........."  ; 18
    SKROW ".....433333334211114111o........"  ; 19
    SKROW ".....4111111222222241212o......."  ; 20
    SKROW ".....41222222222222412222o......"  ; 21
    SKROW ".....hgggggg22222224122223o....."  ; 22
    SKROW ".....hgggggg222222242222233o...."  ; 23
    SKROW ".....hgggggg333333342333333o...."  ; 24
    SKROW ".....hgggggggggggggggggggggo...."  ; 25
    SKROW ".....hhhhhhhhhhhhhhhhhhhhho....."  ; 26
    SKROW "......oooooooooooooooooooo......"  ; 27
    SKROW "................................"  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_iron_boots, boots_rows, 32, 32, tier_iron_pal
align 8
SKBMP ib_gold_boots, boots_rows, 32, 32, tier_gold_pal
align 8
SKBMP ib_diamond_boots, boots_rows, 32, 32, tier_diamond_pal

; --------------------------------------------------------------------------------------------------------------------
; pistol: ib_pistol (PISTOL). The guns are drawn in side view, muzzle to the right, grip at the bottom left
;   A steel slide (lit top edge, rear serrations, an ejection port with a brass case, two sights) on a short frame
;   with a trigger guard loop and a brass trigger; the grip is blued steel (v w x y) with a checkered panel and a
;   brass base plate.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS pistol_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW "................................"  ; 03
    SKROW "................................"  ; 04
    SKROW ".....4444..............444......"  ; 05
    SKROW "....41242o4444444444444122o....."  ; 06
    SKROW "....41111111111111111111111o4..."  ; 07
    SKROW "....4223232322333333322222221o.."  ; 08
    SKROW "....422424242244ijj442ss22333o.."  ; 09
    SKROW "....4224242422444444422222333o.."  ; 10
    SKROW "....4334343433333333333333444o.."  ; 11
    SKROW "....4444444444444444444444ooo..."  ; 12
    SKROW ".....ovwwwwwxy3333333333oo......"  ; 13
    SKROW ".....yvwwwwwxy4444444444o......."  ; 14
    SKROW ".....yvxwxwxxy33333333oo........"  ; 15
    SKROW ".....yvwxwxwxyooioooo4o........."  ; 16
    SKROW ".....yvxwxwxxyoljo..44o........."  ; 17
    SKROW ".....yvwxwxwxyolko..44o........."  ; 18
    SKROW "....yvwxwxwxyo44o44444o........."  ; 19
    SKROW "....yvxwxwxxy444444444o........."  ; 20
    SKROW "....yvwxwxwxyooooooooo.........."  ; 21
    SKROW "....yvxwxwxxyo.................."  ; 22
    SKROW "....yvwxwxwxyo.................."  ; 23
    SKROW "...liijjjjjjjo.................."  ; 24
    SKROW "...lkkkkkkkkko.................."  ; 25
    SKROW "....ooooooooo..................."  ; 26
    SKROW "................................"  ; 27
    SKROW "................................"  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_pistol, pistol_rows, 32, 32, gear_pal

; --------------------------------------------------------------------------------------------------------------------
; musket: ib_musket (MUSKET). The flintlock: a long steel barrel (3 rows, a glint on the top) with two brass bands over a
;   wooden fore-stock, the lock (a steel plate with the cock, frizzen and a brass pan) at the breech, a wooden stock
;   with grain, a brass butt plate and trigger guard.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS musket_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW "................................"  ; 03
    SKROW "................................"  ; 04
    SKROW "................................"  ; 05
    SKROW "................................"  ; 06
    SKROW "................................"  ; 07
    SKROW ".........444................4..."  ; 08
    SKROW "........4222o4.............41o.."  ; 09
    SKROW "....ll..43o4o4o444l44444l4442o.."  ; 10
    SKROW "...lijo.42o4311111i111ssi11112o."  ; 11
    SKROW "..liooddda2akj2222i22222i22223o."  ; 12
    SKROW "..ljaaaa2222233333j33333j33334o."  ; 13
    SKROW "..ljaabb2344344444j44444j44444o."  ; 14
    SKROW "..lkbaab2s333aaaaakaaaaakaajoo.."  ; 15
    SKROW "..lkbbba44444bbbbbkbbbbbkbbko..."  ; 16
    SKROW "..lkbccccccddccccckccccckccko..."  ; 17
    SKROW "..lkbccccdiokookoooooooooooo...."  ; 18
    SKROW "..lkcccdoojokolko..............."  ; 19
    SKROW "..lkdooo.ljoollko..............."  ; 20
    SKROW "..lko....lkkkkkko..............."  ; 21
    SKROW "...o......oooooo................"  ; 22
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
SKBMP ib_musket, musket_rows, 32, 32, gear_pal

; --------------------------------------------------------------------------------------------------------------------
; shotgun: ib_shotgun (SHOTGUN). Two steel barrels side by side (seen from slightly above, the lit one on top) with a
;   brass bead sight, a wooden fore-end with a brass cap, a blued-steel break-action receiver with a brass top lever
;   and inlay, a wooden stock with a sloping comb and a dark butt pad, a brass trigger guard with two triggers.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS shotgun_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW "................................"  ; 03
    SKROW "................................"  ; 04
    SKROW "................................"  ; 05
    SKROW "................................"  ; 06
    SKROW "........ll..................l..."  ; 07
    SKROW ".......lijolll.............lio.."  ; 08
    SKROW ".......doijjjjo444444444444ljo.."  ; 09
    SKROW ".....ddaovvvvvv1111111s1111112o."  ; 10
    SKROW "...ddaabovswwww222222222222223o."  ; 11
    SKROW "..daababovwikww343334333433344o."  ; 12
    SKROW ".ywbaabbovxklxx222222222222223o."  ; 13
    SKROW ".ywabbbcovxklxx333333333333334o."  ; 14
    SKROW ".yxbcccbovxxxxx444444444444444o."  ; 15
    SKROW ".yxbbbbboyyyyyyoaaaaaaaaajoooo.."  ; 16
    SKROW ".yxbbbbboyyyyyyobbbbbbbbbko....."  ; 17
    SKROW ".yxbccccoojojojokccccccccko....."  ; 18
    SKROW ".yxbbcdcaojokokokooooooooo......"  ; 19
    SKROW ".yxbcdoddojoololko.............."  ; 20
    SKROW ".yxcdo.oolkkkkkkko.............."  ; 21
    SKROW ".yxdo.....ooooooo..............."  ; 22
    SKROW "..oo............................"  ; 23
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
SKBMP ib_shotgun, shotgun_rows, 32, 32, gear_pal

; --------------------------------------------------------------------------------------------------------------------
; kalashnikov: ib_kalashnikov (KALASHNIKOV). Wooden stock with a dark butt plate, a flat-shaded dark receiver with a
;   rear sight and a charging handle, a steel gas tube and block over the wooden handguards, a front sight post
;   and muzzle, a wooden pistol grip with a trigger guard, a curved brown magazine with ribs.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS kalashnikov_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW "................................"  ; 03
    SKROW "................................"  ; 04
    SKROW "................................"  ; 05
    SKROW "...............444..........44.."  ; 06
    SKROW "..............4122o.....44.412o."  ; 07
    SKROW "..........yyyy4123oy444422o423o."  ; 08
    SKROW ".........yvvvvvvvvvv21s133o433o."  ; 09
    SKROW "......dddywsvwwwwwww333333o433o."  ; 10
    SKROW "..yyddaaaawwwwwwwwwwaaaaa21112o."  ; 11
    SKROW ".ywwaabbbbxxxxx13xxxbbbbb32223o."  ; 12
    SKROW ".yxwbbbbccxxxxx34xxxbbbbb33334o."  ; 13
    SKROW ".yxwbbbcbcyyyyyyyyyyccccc3oooo.."  ; 14
    SKROW ".yxwcccccdoabcdo3wwwwwddd4o....."  ; 15
    SKROW ".yxwcccddodabcdo4effghoooo......"  ; 16
    SKROW ".yxwdccoo.dabcdooeffgho........."  ; 17
    SKROW ".yxxooo..dabcd3333ghhhho........"  ; 18
    SKROW ".yxxo....dabcdooooeffgho........"  ; 19
    SKROW "..oo.....dabcdo...oeffgho......."  ; 20
    SKROW "........dabcdo.....oghhhho......"  ; 21
    SKROW ".........oooo.......oeffgho....."  ; 22
    SKROW ".....................oeffgho...."  ; 23
    SKROW "......................ooooo....."  ; 24
    SKROW "................................"  ; 25
    SKROW "................................"  ; 26
    SKROW "................................"  ; 27
    SKROW "................................"  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_kalashnikov, kalashnikov_rows, 32, 32, gear_pal

; --------------------------------------------------------------------------------------------------------------------
; rocket_launcher: ib_rocket_launcher (ROCKET_LAUNCHER). An olive tube (A B C D, cylinder shading) with two riveted steel
;   bands, a flared steel nozzle at the back, the red warhead nose out of the front (as in the 3D model), iron sights
;   on top and two dark grips with a trigger guard below.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS rocket_launcher_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW "................................"  ; 03
    SKROW "................................"  ; 04
    SKROW "................................"  ; 05
    SKROW ".............4444..............."  ; 06
    SKROW "...4444.....41122o......44......"  ; 07
    SKROW "..42111o..4442442o...44412o....."  ; 08
    SKROW "..41211oD412o2243oDD412o23oU...."  ; 09
    SKROW "..yw222AAA23AAAAAAAAA23AAARRo..."  ; 10
    SKROW "..yw222BBB23ABBBBBBBB23BBBRsRo.."  ; 11
    SKROW "..yx222BBBs3BBBBBBBBBs3BBBSSRRo."  ; 12
    SKROW "..yx222BBB33BBBBBBBBB33BBBSSSRo."  ; 13
    SKROW "..yx333CCC34CCCCCCCCC34CCCSSSTo."  ; 14
    SKROW "..yx333CCC34CCCCCCCCC34CCCTSTUo."  ; 15
    SKROW "..yx333DDD44DDDDDDDDD44DDDTTUo.."  ; 16
    SKROW "..yx333DDD44DDDDDDDDD44DDDTUo..."  ; 17
    SKROW "..44344ooo44ovwxy3oo44vwxooo...."  ; 18
    SKROW "..44444o..ooyvwxy4o44ovwxo......"  ; 19
    SKROW "..44444o....yvwxyo444ovwxo......"  ; 20
    SKROW "...oooo.....yvwx33333ovwxo......"  ; 21
    SKROW "...........yvwxyoooooyyyyo......"  ; 22
    SKROW "...........yvwxyo.....ooo......."  ; 23
    SKROW "...........yvwxyo..............."  ; 24
    SKROW "............oooo................"  ; 25
    SKROW "................................"  ; 26
    SKROW "................................"  ; 27
    SKROW "................................"  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_rocket_launcher, rocket_launcher_rows, 32, 32, gear_pal

; --------------------------------------------------------------------------------------------------------------------
; revolver: ib_revolver (REVOLVER). Gun steel in 1..4 (the AC_IRON ramp), a wooden grip (a..d), brass trigger guard and
;   butt cap (i..l).
; --------------------------------------------------------------------------------------------------------------------
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
SKBMP ib_revolver, revolver_rows, 32, 32, gear_pal

; --------------------------------------------------------------------------------------------------------------------
; hunting_rifle: ib_hunting_rifle (HUNTING_RIFLE). A long steel barrel over a wooden fore-stock, a dark bolt-action
;   receiver with a brass bolt knob, a slim scope on two brass rings (a blue lens in the objective), a
;   wooden stock with a cheek piece and a dark butt pad, a brass trigger guard.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS hunting_rifle_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW "................................"  ; 03
    SKROW "................................"  ; 04
    SKROW "................................"  ; 05
    SKROW "................................"  ; 06
    SKROW "......................yyy......."  ; 07
    SKROW "......yy......ll.....yvvvo......"  ; 08
    SKROW ".....yvvoyyllljkollyyyvvvso....."  ; 09
    SKROW ".....ywwvvvijvklvijvvvwwwMo....."  ; 10
    SKROW ".....yxxwswijwwwwijwwwwwwMo....."  ; 11
    SKROW ".....yxxxxxjkxxxxjkxxxxxxNo....."  ; 12
    SKROW "..yydyyyavvjkvvvvjkoooyyyo.44..."  ; 13
    SKROW ".ywwaaaabwswwwwwwoo444ooo4412o.."  ; 14
    SKROW ".yxwbbbbcwwwwikw3111111s111112o."  ; 15
    SKROW ".yxwbbbccxxxxklx32222222222223o."  ; 16
    SKROW ".yxwcccbcxxxxxxxx3333333333334o."  ; 17
    SKROW ".yxwbbcccyyyyyyyyaaaaaaaa2oooo.."  ; 18
    SKROW ".yxwbcdddoooojbkkbbbbbbbb3o....."  ; 19
    SKROW ".yxwccooo...ljckkcccccccc3o....."  ; 20
    SKROW ".yxwdo.....lljookooooooooo......"  ; 21
    SKROW ".yxxo.....lkkkkkko.............."  ; 22
    SKROW ".yxxo......oooooo..............."  ; 23
    SKROW "..oo............................"  ; 24
    SKROW "................................"  ; 25
    SKROW "................................"  ; 26
    SKROW "................................"  ; 27
    SKROW "................................"  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_hunting_rifle, hunting_rifle_rows, 32, 32, gear_pal

; --------------------------------------------------------------------------------------------------------------------
; pistol_round: ib_pistol_round (PISTOL_ROUND). Ammunition stands upright. Three short brass cases with an extractor
;   groove and a rim under round-nosed steel bullets, the middle one behind and higher.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS pistol_round_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................4..............."  ; 02
    SKROW "...............42o.............."  ; 03
    SKROW "..............4123o............."  ; 04
    SKROW ".............412234o............"  ; 05
    SKROW ".............4s2234o............"  ; 06
    SKROW ".............4s2234o............"  ; 07
    SKROW "..........4..412234o..4........."  ; 08
    SKROW ".........42o.412234o.42o........"  ; 09
    SKROW "........4123oiijjkkl4123o......."  ; 10
    SKROW ".......412234oijjkk412234o......"  ; 11
    SKROW ".......4s2234oijjkk4s2234o......"  ; 12
    SKROW ".......4s2234oijjkk4s2234o......"  ; 13
    SKROW ".......412234oijjkk412234o......"  ; 14
    SKROW ".......412234oijjkk412234o......"  ; 15
    SKROW "......liijjkklojjkliijjkklo....."  ; 16
    SKROW "......liijjkklojjkliijjkklo....."  ; 17
    SKROW "......liijjkklojjkliijjkklo....."  ; 18
    SKROW "......liijjkklojjkliijjkklo....."  ; 19
    SKROW "......liijjkklolllliijjkklo....."  ; 20
    SKROW "......liijjkklokkkliijjkklo....."  ; 21
    SKROW "......liijjkklokklliijjkklo....."  ; 22
    SKROW "......liijjkklooooliijjkklo....."  ; 23
    SKROW "......liijjkklo...liijjkklo....."  ; 24
    SKROW "......liijjkklo...liijjkklo....."  ; 25
    SKROW "......llllllllo...llllllllo....."  ; 26
    SKROW ".....ljjkkkkkklo.ljjkkkkkklo...."  ; 27
    SKROW ".....lkkkkkllllo.lkkkkkllllo...."  ; 28
    SKROW "......ooooooooo...ooooooooo....."  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_pistol_round, pistol_round_rows, 32, 32, gear_pal

; --------------------------------------------------------------------------------------------------------------------
; musket_ball: ib_musket_ball (MUSKET_BALL). A pyramid of three lead balls, each outlined on its own, lit in 2, shaded through 3 and 4
;   to a blued x rim, with an s glint.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS musket_ball_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW "................................"  ; 03
    SKROW "..............4444.............."  ; 04
    SKROW "............443334o4............"  ; 05
    SKROW "...........432233344o..........."  ; 06
    SKROW "...........42ss23344o..........."  ; 07
    SKROW "..........43222233344o.........."  ; 08
    SKROW "..........432s2233344o.........."  ; 09
    SKROW "..........43322333444o.........."  ; 10
    SKROW "..........4333333344xo.........."  ; 11
    SKROW "..........4433334444xo.........."  ; 12
    SKROW "...........o4444444xo..........."  ; 13
    SKROW "........4444444444x44444........"  ; 14
    SKROW "......4433334o4xxx433334o4......"  ; 15
    SKROW ".....432223344ooo432233344o....."  ; 16
    SKROW ".....42s2s33344o432ss23344o....."  ; 17
    SKROW "....432s2223344o432s2233444o...."  ; 18
    SKROW "....43222233344433222233444o...."  ; 19
    SKROW "....4333233344443332333344xo...."  ; 20
    SKROW "....4333333444xoo333333444xo...."  ; 21
    SKROW "....4443334444xo443333444xxo...."  ; 22
    SKROW ".....o4444444xo..o444444xxo....."  ; 23
    SKROW "......o4444xxo....o4444xxo......"  ; 24
    SKROW ".......ooxxoo......ooxxoo......."  ; 25
    SKROW ".........oo..........oo........."  ; 26
    SKROW "................................"  ; 27
    SKROW "................................"  ; 28
    SKROW "................................"  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_musket_ball, musket_ball_rows, 32, 32, gear_pal

; --------------------------------------------------------------------------------------------------------------------
; shotgun_shell: ib_shotgun_shell (SHOTGUN_SHELL). Two fat shells, red hulls (R S T U) crimped at the top over brass
;   heads with a rim; the back one is higher.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS shotgun_shell_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW ".................UUUUUU........."  ; 02
    SKROW "................USTUUUUo........"  ; 03
    SKROW "...............USSTTUUUUo......."  ; 04
    SKROW "..............URRSSSTTTUUo......"  ; 05
    SKROW "........UUUUUUURRSSSTTTUUo......"  ; 06
    SKROW ".......USTUUUUoRRSSSTTTUUo......"  ; 07
    SKROW "......USSTTUUUUoRSSSTTTUUo......"  ; 08
    SKROW ".....URRSSSTTTUUoSSSTTTUUo......"  ; 09
    SKROW ".....URRSSSTTTUUoSSSTTTUUo......"  ; 10
    SKROW ".....URRSSSTTTUUoSSSTTTUUo......"  ; 11
    SKROW ".....URRSSSTTTUUoSSSTTTUUo......"  ; 12
    SKROW ".....URRSSSTTTUUoSSSTTTUUo......"  ; 13
    SKROW ".....URRSSSTTTUUoSSSTTTUUo......"  ; 14
    SKROW ".....URRSSSTTTUUoSSSTTTUUo......"  ; 15
    SKROW ".....URRSSSTTTUUoSSSTTTUUo......"  ; 16
    SKROW ".....URRSSSTTTUUoUUUUUUUUo......"  ; 17
    SKROW ".....URRSSSTTTUUojjjkkkllo......"  ; 18
    SKROW ".....URRSSSTTTUUojjjkkkllo......"  ; 19
    SKROW ".....URRSSSTTTUUojjjkkkllo......"  ; 20
    SKROW ".....UUUUUUUUUUUojjjkkkllo......"  ; 21
    SKROW ".....liijjjkkkllollllllllo......"  ; 22
    SKROW ".....liijjjkkkllokkkkkkkllo....."  ; 23
    SKROW ".....liijjjkkkllokkkklllllo....."  ; 24
    SKROW ".....liijjjkkklloooooooooo......"  ; 25
    SKROW ".....lllllllllllo..............."  ; 26
    SKROW "....ljjjkkkkkkkllo.............."  ; 27
    SKROW "....lkkkkkkklllllo.............."  ; 28
    SKROW ".....oooooooooooo..............."  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_shotgun_shell, shotgun_shell_rows, 32, 32, gear_pal

; --------------------------------------------------------------------------------------------------------------------
; rifle_round: ib_rifle_round (RIFLE_ROUND). Three long slim brass cases with a rim and a bottleneck shoulder under
;   pointed copper-jacketed bullets, the middle one behind and higher.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS rifle_round_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................W..............."  ; 02
    SKROW "...............WPo.............."  ; 03
    SKROW "..............WPQo.............."  ; 04
    SKROW ".........W....WKPQo....W........"  ; 05
    SKROW "........WPo...WKPQo...WPo......."  ; 06
    SKROW ".......WPQo...WKPQo..WPQo......."  ; 07
    SKROW ".......WKPQo..WsPQo..WKPQo......"  ; 08
    SKROW ".......WKsQo..WKPQo..WKsQo......"  ; 09
    SKROW ".......WKPQo..WKPQo..WKPQo......"  ; 10
    SKROW ".......WKPQo..lijko..WKPQo......"  ; 11
    SKROW ".......WKPQo.lijjklo.WKPQo......"  ; 12
    SKROW ".......WKPQo.lijjklo.WKPQo......"  ; 13
    SKROW ".......lijko.lijjklo.lijko......"  ; 14
    SKROW "......lijjklolijjklolijjklo....."  ; 15
    SKROW "......lijjklolijjklolijjklo....."  ; 16
    SKROW "......lijjklolijjklolijjklo....."  ; 17
    SKROW "......lijjklolijjklolijjklo....."  ; 18
    SKROW "......lijjklolijjklolijjklo....."  ; 19
    SKROW "......lijjklolijjklolijjklo....."  ; 20
    SKROW "......lijjklolijjklolijjklo....."  ; 21
    SKROW "......lijjklolijjklolijjklo....."  ; 22
    SKROW "......lijjklolijjklolijjklo....."  ; 23
    SKROW "......lijjklollllllolijjklo....."  ; 24
    SKROW "......lijjklojjkkkkllijjklo....."  ; 25
    SKROW "......lijjklokkkkllllijjklo....."  ; 26
    SKROW "......lllllloooooooollllllo....."  ; 27
    SKROW ".....ljjkkkklo.....ljjkkkklo...."  ; 28
    SKROW ".....lkkkklllo.....lkkkklllo...."  ; 29
    SKROW "......ooooooo.......ooooooo....."  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_rifle_round, rifle_round_rows, 32, 32, gear_pal

; --------------------------------------------------------------------------------------------------------------------
; rocket: ib_rocket (ROCKET). Upright like the other ammunition: a red ogive nose (R S T U) over an olive body with a
;   yellow band, two steel fins and a dark nozzle; s marks the nose.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS rocket_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................UU.............."  ; 02
    SKROW "...............USTo............."  ; 03
    SKROW "..............USSTTo............"  ; 04
    SKROW ".............USSSsTo............"  ; 05
    SKROW "............URSSsTTTo..........."  ; 06
    SKROW "............URSSSTTTo..........."  ; 07
    SKROW "...........URRSSSTTTUo.........."  ; 08
    SKROW "...........URRSSSTTTUo.........."  ; 09
    SKROW "...........URRSSSTTTUo.........."  ; 10
    SKROW "...........URRSSSTTTUo.........."  ; 11
    SKROW "...........DCCCCCDDDDo.........."  ; 12
    SKROW "...........DAABBBCCCDo.........."  ; 13
    SKROW "...........DAABBBCCCDo.........."  ; 14
    SKROW "...........DAABBBCCCDo.........."  ; 15
    SKROW "...........liijjjkkklo.........."  ; 16
    SKROW "...........liijjjkkklo.........."  ; 17
    SKROW "...........DAABBBCCCDo.........."  ; 18
    SKROW "...........DAABBBCCCDo.........."  ; 19
    SKROW "..........41AABBBCCCD4o........."  ; 20
    SKROW ".........412AABBBCCCD34o........"  ; 21
    SKROW ".........412AABBBCCCD34o........"  ; 22
    SKROW "........4122AABBBCCCD334o......."  ; 23
    SKROW ".......41222AABBBCCCD3334o......"  ; 24
    SKROW ".......41222AABBBCCCD3334o......"  ; 25
    SKROW "......412222ovvwwxxyo33334o....."  ; 26
    SKROW "......412222vvwwwxxxy33334o....."  ; 27
    SKROW ".......ooooowwxxxyyyyooooo......"  ; 28
    SKROW "............ooooooooo..........."  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_rocket, rocket_rows, 32, 32, gear_pal

; --------------------------------------------------------------------------------------------------------------------
; scope: ib_scope (SCOPE). The scope lies horizontally like the guns it fits. A blued tube between a rubber
;   eyecup and a wider objective bell with a blue lens (L M N, glints), two brass mount rings and a brass
;   elevation turret.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS scope_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW "................................"  ; 03
    SKROW "................................"  ; 04
    SKROW "................................"  ; 05
    SKROW "................................"  ; 06
    SKROW "................................"  ; 07
    SKROW "................................"  ; 08
    SKROW "..............lll..............."  ; 09
    SKROW ".............ljjko.............."  ; 10
    SKROW ".............lijko....yyyyyy...."  ; 11
    SKROW "...yyyyyy..lllkkloll.yvvvvvxo..."  ; 12
    SKROW "..yxwvvvvolikoijkoikoyvsvvvxwo.."  ; 13
    SKROW "..yyxwwwwvvikvvvvvikvvwwwwwxsLo."  ; 14
    SKROW "..yyxwwwwssjkwwwwwjkwwwwwwwxsMo."  ; 15
    SKROW "..yyxwwwwwwjkwwwwwjkwwwwwwwxMMo."  ; 16
    SKROW "..yyxxxxxxxjkxxxxxjkxxxxxxxxMNo."  ; 17
    SKROW "..yyxxxxxxxjkxxxxxjkxxxxxxxxNNo."  ; 18
    SKROW "..yyxxxxxyyjkyyyyyjkyyyyyyyyNNo."  ; 19
    SKROW "..yyxyyyyoojkooooojkooyyyyyyyo.."  ; 20
    SKROW "...oooooo..oo.....oo.yyyyyyyo..."  ; 21
    SKROW "......................oooooo...."  ; 22
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
SKBMP ib_scope, scope_rows, 32, 32, gear_pal

; --------------------------------------------------------------------------------------------------------------------
; extended_mag: ib_extended_mag (EXTENDED_MAG). A tall blued-steel magazine (rib grooves, a column of round-count
;   slots) on a brass base plate, with two brass-cased rounds with copper bullets peeking out of the feed lips.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS extended_mag_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................WWW............."  ; 01
    SKROW "............WWWWPPQo............"  ; 02
    SKROW "...........WPPQoKPPo............"  ; 03
    SKROW "...........WKPPoijko............"  ; 04
    SKROW "...........lijkojjko............"  ; 05
    SKROW "...........ljjkojjko............"  ; 06
    SKROW "...........ljjkwwwwwo..........."  ; 07
    SKROW "..........yvwwxxxxxyyo.........."  ; 08
    SKROW "..........yswwxxxxxyyo.........."  ; 09
    SKROW "..........yswwxxxxxyyo.........."  ; 10
    SKROW "..........yvwwxxxxxyyo.........."  ; 11
    SKROW "..........yxyyyyyyyyyo.........."  ; 12
    SKROW "..........yvwwxxxxxyyo.........."  ; 13
    SKROW "..........yvwwxyyxxyyo.........."  ; 14
    SKROW "..........yvwwxxxxxyyo.........."  ; 15
    SKROW "..........yvwwxyyxxyyo.........."  ; 16
    SKROW "..........yvwwxxxxxyyo.........."  ; 17
    SKROW "..........yvwwxyyxxyyo.........."  ; 18
    SKROW "..........yvwwxxxxxyyo.........."  ; 19
    SKROW "..........yxyyyyyyyyyo.........."  ; 20
    SKROW "..........yvwwxxxxxyyo.........."  ; 21
    SKROW "..........yvwwxyyxxyyo.........."  ; 22
    SKROW "..........yvwwxxxxxyyo.........."  ; 23
    SKROW "..........yxyyyyyyyyyo.........."  ; 24
    SKROW "..........yvwwxxxxxyyo.........."  ; 25
    SKROW "..........yvwwxxxxxyyo.........."  ; 26
    SKROW ".........liijjjlljjjjjo........."  ; 27
    SKROW ".........lkkkkkkkkkkkko........."  ; 28
    SKROW "..........oooooooooooo.........."  ; 29
    SKROW "................................"  ; 30
    SKROW "................................"  ; 31
SKROWS_END
align 8
SKBMP ib_extended_mag, extended_mag_rows, 32, 32, gear_pal

; --------------------------------------------------------------------------------------------------------------------
; rifled_barrel: ib_rifled_barrel (RIFLED_BARREL). A steel barrel with a barber-pole of rifling grooves (4 groove, 1 land),
;   a brass breech flange with a thread ring, a front sight base on top and a muzzle crown showing the dark bore with
;   the spiral inside.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS rifled_barrel_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW "................................"  ; 03
    SKROW "................................"  ; 04
    SKROW "................................"  ; 05
    SKROW "................................"  ; 06
    SKROW "................................"  ; 07
    SKROW "................................"  ; 08
    SKROW "...llll..............4444.444..."  ; 09
    SKROW "..ljikko............41122o111o.."  ; 10
    SKROW "..liikk3o4444444444442233o1112o."  ; 11
    SKROW "..ljjkk3111s113111s113111122yxo."  ; 12
    SKROW "..ljjkk322222312222231222222ywo."  ; 13
    SKROW "..ljjkk322223122222312222222xxo."  ; 14
    SKROW "..lkkll433342333334233333433ywo."  ; 15
    SKROW "..lkkll433423333342333334233xyo."  ; 16
    SKROW "..lkkll434333333433333343333ywo."  ; 17
    SKROW "..lkkll444444444444444444433yyo."  ; 18
    SKROW "..lllll4oooooooooooooooooo4443o."  ; 19
    SKROW "..lllllo.................4444o.."  ; 20
    SKROW "...oooo...................ooo..."  ; 21
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
SKBMP ib_rifled_barrel, rifled_barrel_rows, 32, 32, gear_pal

; --------------------------------------------------------------------------------------------------------------------
; compensator: ib_compensator (COMPENSATOR). A steel muzzle brake: a brass threaded collar, a body with three
;   gas slots (notches through the top, dark slits below) and a flange with the dark bore at the front.
; --------------------------------------------------------------------------------------------------------------------
;          0         1         2         3
;          01234567890123456789012345678901
SKROWS compensator_rows, 32, 32
    SKROW "................................"  ; 00
    SKROW "................................"  ; 01
    SKROW "................................"  ; 02
    SKROW "................................"  ; 03
    SKROW "................................"  ; 04
    SKROW "................................"  ; 05
    SKROW "................................"  ; 06
    SKROW "................................"  ; 07
    SKROW ".........................44....."  ; 08
    SKROW ".........44..44..44..444411o...."  ; 09
    SKROW "........41so411o411o4111111o...."  ; 10
    SKROW "....llll422o412o422o4222222o4..."  ; 11
    SKROW "...likiki22o422o422o422222222o.."  ; 12
    SKROW "...ljkjkj22yx22yx22yx222222yxo.."  ; 13
    SKROW "...ljkjkj33yx33yx33yx333322yxo.."  ; 14
    SKROW "...ljkjkj33yx33yx33yx333333yxo.."  ; 15
    SKROW "...lklklk33yx33yx33yx333333yyo.."  ; 16
    SKROW "...lklklk33yx33yx33yx333333yyo.."  ; 17
    SKROW "...lklklk44yx44yx44yx444433yyo.."  ; 18
    SKROW "...llllll44444444444444444434o.."  ; 19
    SKROW "....ooooo444444444444444444oo..."  ; 20
    SKROW "........4444444444444444444o...."  ; 21
    SKROW ".........oooooooooooooooo44o...."  ; 22
    SKROW ".........................oo....."  ; 23
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
SKBMP ib_compensator, compensator_rows, 32, 32, gear_pal
