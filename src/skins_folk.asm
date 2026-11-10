; skins_folk.asm: skin models of the folk (0.13 "looks"): humanoids that walk on two legs, wear clothes and
; carry things in the right hand. Data only: bones, parts and paint ops for skin.asm (art.inc, common.inc
; "0.13 looks"); nothing here runs.
;
; Holds the style samples (the farmer and the avatar) and the folk of the four other factions; the
; Villagers' elder and merchant and the extras (hat, helmet, pack, crown, hoods) follow the same structure:
;   m_folk_villagers   the farmer: brown fringe, green tunic with a round collar, rope belt, rolled sleeves,
;                      patched trousers, laced boots (prefix fv_)
;   m_avatar           the adventurer other players show as, and the first-person arm (prefix av_)
;   m_folk_bandits     red bandana knotted at the back, black cloth mask, dark leather jerkin with crossed straps,
;                      pouch, a blade across the back, wrapped boots (prefix fb_)
;   m_folk_cult        pale, glowing red eyes, ash hood and cowl, charcoal robe with red trim, rope sash, pendant,
;                      bell sleeves (prefix fc_)
;   m_folk_beastfolk   fur head with ears, snout and fangs, white war paint, fur vest with crossed straps,
;                      bone necklace, tail, fur-wrapped shins (prefix ff_)
;   m_folk_stonekin    stocky: cracked stony skin, two braids in a copper beard, mail tunic, pauldrons, belt,
;                      heavy boots (prefix fs_)
; One section per model, in file order: ramps, then palette and bitmaps (section .rodata), then the model
; (section .data), so a model reads top to bottom.
;
; Humanoid skeleton (texels, origin = feet centre, front = -Z; the contract of the folk, elder, merchant and
; avatar, so the extras, the pilot and the first-person arm fit): BK_LLEG x -6..0 and BK_RLEG x 0..6 (y 0..24,
; z -3..3, pivot (24, 0), swing +1 / -1); BK_BODY torso x -8..8, y 24..46, z -4..4; BK_LARM x -14..-8 and
; BK_RARM x 8..14 (y 24..46, z -3..3, pivot (44, 0), swing -1 / +1; the held item sits at (11, 26, 0));
; BK_HEAD x -8..8, y 46..62, z -8..8. Detail parts are free around these base boxes. Boots are a painted shaft
; on the leg plus a foot box, so the leg stays slim and no two boxes of the pair overlap (coplanar faces would
; z-fight); a shared-skin pair (PART_AS) mirrors its images, so only details symmetric about the body's centre
; plane go on a shared skin.
;
; Local helpers (private to this file):
;   RAMP prefix, r, g, b                defines prefix_1 .. prefix_4: highlight (base x 1.2, clamped), base,
;                                       shade (x 0.75), deep (x 0.55), packed RGBO. The faction ramps derive
;                                       from the base tones of the factions design
;                                       (docs/superpowers/specs/2026-11-08-assemblycraft-factions-design.md,
;                                       "Blocks and art").
;   PART name, x0, y0, z0, w, h, d, grow, flags
;   PART_AS name, k, x0, y0, z0, grow, flags
;                                       SKPART / SKPART_AS; `name` becomes the part's index, so the paint ops
;                                       name parts, not numbers. Names are <model prefix>_<part>.
; Conventions, for the models that extend this file:
;   - one palette per model (<prefix>_pal) holds every character its bitmaps use; a material takes a group of
;     letters, lower case = base tone, upper case = highlight, the next two letters = shade and deep (the
;     comment above the palette lists them). '_' is a transparent texel (PALT, cutouts), '.' keeps the texel.
;   - a part's ops run: SK_FILL (grain), cloth details, SK_GRAD on the four vertical faces (272 -> 224), then the
;     face features (eyes, glints, trims) that keep their full colour. Cutout overlays (hair) are filled like any
;     part and then punched with '_' bitmaps; every face keeps at least one opaque texel.
;   - bitmaps have the size of the face they paint (a face image is seen from outside, upright, (0, 0) top left:
;     the unwrap table of the design doc); the light comes from the top left, so a face's left column is the lit one.
;   - left/right pairs share one skin (PART_AS); a detail that exists on one side only is a part of its own.
;   - grain: noise 15 on cloth, leather and skin, 31 on hair, 0 on metal, eyes and trims.
;   - overlays that cover the same area differ by at least 2 in grow (a quarter texel), so their faces never
;     z-fight; dark cloth (the cult robes, the bandit mask) keeps one rim-light tone outside the four ramp steps
;     so its folds stay readable.
;   - skin_build packs the unwraps in record order with next-fit shelves: a part costs 2(w+d) x (d+h) atlas
;     texels (a cutout overlay as much as a solid part), an AS part nothing; neighbouring parts of similar height
;     waste less. The six models here take about 432 atlas rows together (of 3072).
;   - the avatar's tunic, scarf and sleeves are SKPF_ACCENT parts painted in light greys: the peer slot colour
;     multiplies them (a grey of 208 keeps the slot colour vivid and the deep greys keep the seams visible).
; Ramps (RAMP: _1 highlight, _2 base, _3 shade, _4 deep; AC_* are the shared material ramps of art.inc):
;   m_folk_villagers   FV_SKIN (225,180,140), FV_HAIR (104,68,38), FV_TUNIC (90,140,60), FV_PANTS (110,80,50), FV_ROPE (178,148,96)
;   m_avatar           AV_HAIR (92,58,32), AV_GREY (208,208,208), AV_LINEN (226,216,192), AV_PANTS (64,68,96)
;   m_folk_bandits     FB_SKIN (200,150,110), FB_HAIR (64,46,36), FB_RED (150,30,30), FB_LEATHER (80,55,35), FB_PANTS (60,60,60), FB_CLOTH (34,32,38), FB_SHIRT (118,50,46), FB_WRAP (170,152,120)
;   m_folk_cult        FC_SKIN (190,185,180), FC_ASH (70,65,70), FC_ROBE (50,45,50), FC_SKIRT (45,40,45), FC_RED (168,28,32), FC_ROPE (122,96,66)
;   m_folk_beastfolk   FF_FUR (130,110,90), FF_VEST (150,130,100), FF_DARK (90,75,60), FF_CREAM (214,196,164)
;   m_folk_stonekin    FS_SKIN (150,130,115), FS_BEARD (170,120,70), FS_MAIL (140,140,150), FS_PANTS (80,60,45)
%include "common.inc"
%include "art.inc"
default rel

%macro RAMP 4
%assign %%r1 (%2 * 6) / 5
%assign %%g1 (%3 * 6) / 5
%assign %%b1 (%4 * 6) / 5
%if %%r1 > 255
%assign %%r1 255
%endif
%if %%g1 > 255
%assign %%g1 255
%endif
%if %%b1 > 255
%assign %%b1 255
%endif
%xdefine %1_1 RGBO(%%r1, %%g1, %%b1)
%xdefine %1_2 RGBO(%2, %3, %4)
%xdefine %1_3 RGBO((%2 * 3) / 4, (%3 * 3) / 4, (%4 * 3) / 4)
%xdefine %1_4 RGBO((%2 * 11) / 20, (%3 * 11) / 20, (%4 * 11) / 20)
%endmacro
%macro PART 9
%assign %1 %$parts
    SKPART %2, %3, %4, %5, %6, %7, %8, %9
%endmacro
%macro PART_AS 7
%assign %1 %$parts
    SKPART_AS %2, %3, %4, %5, %6, %7
%endmacro

; ===================================================================================================
; m_folk_villagers
; ===================================================================================================
RAMP FV_SKIN, 225, 180, 140             ; head and hands
RAMP FV_HAIR, 104, 68, 38
RAMP FV_TUNIC, 90, 140, 60              ; the factions table: green tunic
RAMP FV_PANTS, 110, 80, 50              ; brown pants
RAMP FV_ROPE, 178, 148, 96              ; the belt

section .rodata
; The characters of every fv_ bitmap. Groups: base, highlight, shade, deep.
;   s S k K skin (b blush)   h H j J hair   g G d D tunic   p P q Q trousers   r R o O rope
;   l L e E leather (AC)   y Y u U brass (AC gold)   c cream   w sclera   W glint   i I iris   x pupil
;   m M mouth   _ transparent
align 8
fv_pal:
    PALC 's', FV_SKIN_2
    PALC 'S', FV_SKIN_1
    PALC 'k', FV_SKIN_3
    PALC 'K', FV_SKIN_4
    PALC 'b', RGBO(238, 150, 128)
    PALC 'h', FV_HAIR_2
    PALC 'H', FV_HAIR_1
    PALC 'j', FV_HAIR_3
    PALC 'J', FV_HAIR_4
    PALC 'g', FV_TUNIC_2
    PALC 'G', FV_TUNIC_1
    PALC 'd', FV_TUNIC_3
    PALC 'D', FV_TUNIC_4
    PALC 'p', FV_PANTS_2
    PALC 'P', FV_PANTS_1
    PALC 'q', FV_PANTS_3
    PALC 'Q', FV_PANTS_4
    PALC 'l', AC_LEATHER_2
    PALC 'L', AC_LEATHER_1
    PALC 'e', AC_LEATHER_3
    PALC 'E', AC_LEATHER_4
    PALC 'r', FV_ROPE_2
    PALC 'R', FV_ROPE_1
    PALC 'o', FV_ROPE_3
    PALC 'O', FV_ROPE_4
    PALC 'y', AC_GOLD_2
    PALC 'Y', AC_GOLD_1
    PALC 'u', AC_GOLD_3
    PALC 'U', AC_GOLD_4
    PALC 'c', RGBO(232, 220, 190)
    PALC 'w', RGBO(246, 246, 240)
    PALC 'W', RGBO(255, 255, 255)
    PALC 'i', RGBO(72, 140, 84)
    PALC 'I', RGBO(128, 190, 110)
    PALC 'x', RGBO(26, 38, 30)
    PALC 'm', RGBO(176, 108, 92)
    PALC 'M', RGBO(112, 56, 48)
    PALT '_'
    dq 0

    ; fv_torso_front (16x22): fv_torso FRONT
    SKROWS fv_torso_front_rows, 16, 22
    SKROW "G..............."
    SKROW "G..............."
    SKROW "G..............."
    SKROW "Gd............d."
    SKROW "Gd....dcDd....d."
    SKROW "Gd....dDcd....d."
    SKROW "Gd....dcDd....d."
    SKROW "Gd....dDcd.GGGG."
    SKROW "Gd....dcDd.d..d."
    SKROW "Gd....dDcd.dG.d."
    SKROW "Gd....dcDd.d..d."
    SKROW "Gd.........dddd."
    SKROW "Gd............d."
    SKROW "Gd............d."
    SKROW "Gd.dd......dd.d."
    SKROW "Gd..d.......d.d."
    SKROW "G..............."
    SKROW "G..............."
    SKROW "G..............."
    SKROW "G..............."
    SKROW "GgGgGgGgGgGgGgGg"
    SKROW "dddddddddddddddd"
    SKROWS_END
    align 8
    SKBMP fv_torso_front, fv_torso_front_rows, 16, 22, fv_pal
    ; fv_torso_back (16x22): fv_torso BACK
    SKROWS fv_torso_back_rows, 16, 22
    SKROW "G..............."
    SKROW "G..............."
    SKROW "G..............."
    SKROW "G..............."
    SKROW "Gddddddddddddddd"
    SKROW "G......dG......."
    SKROW "G......dG......."
    SKROW "G......dG......."
    SKROW "G......dG......."
    SKROW "G......dG..oooo."
    SKROW "G......dG..oRRo."
    SKROW "G......dG..oRRo."
    SKROW "G......dG..oooo."
    SKROW "G......dG......."
    SKROW "G..dd..dG..dd..."
    SKROW "G...d..dG...d..."
    SKROW "G..............."
    SKROW "G..............."
    SKROW "G..............."
    SKROW "G..............."
    SKROW "GgGgGgGgGgGgGgGg"
    SKROW "dddddddddddddddd"
    SKROWS_END
    align 8
    SKBMP fv_torso_back, fv_torso_back_rows, 16, 22, fv_pal
    ; fv_torso_side (8x22): fv_torso RIGHT, fv_torso LEFT
    SKROWS fv_torso_side_rows, 8, 22
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "...d...."
    SKROW "........"
    SKROW "...d...."
    SKROW "........"
    SKROW "...d...."
    SKROW "........"
    SKROW "...d...."
    SKROW "........"
    SKROW "...d...."
    SKROW "........"
    SKROW "...d...."
    SKROW "........"
    SKROW "...d...."
    SKROW "........"
    SKROW "...d...."
    SKROW "........"
    SKROW "GGGGGGGG"
    SKROW "dddddddd"
    SKROWS_END
    align 8
    SKBMP fv_torso_side, fv_torso_side_rows, 8, 22, fv_pal
    ; fv_rope (16x2): fv_belt FRONT, fv_belt BACK
    SKROWS fv_rope_rows, 16, 2
    SKROW "RrorRrorRrorRror"
    SKROW "rRrorRrorRrorRro"
    SKROWS_END
    align 8
    SKBMP fv_rope, fv_rope_rows, 16, 2, fv_pal
    ; fv_rope_side (8x2): fv_belt LEFT, fv_belt RIGHT
    SKROWS fv_rope_side_rows, 8, 2
    SKROW "RrorRror"
    SKROW "rRrorRro"
    SKROWS_END
    align 8
    SKBMP fv_rope_side, fv_rope_side_rows, 8, 2, fv_pal
    ; fv_buckle_front (2x2): fv_buckle FRONT
    SKROWS fv_buckle_front_rows, 2, 2
    SKROW "YY"
    SKROW "uU"
    SKROWS_END
    align 8
    SKBMP fv_buckle_front, fv_buckle_front_rows, 2, 2, fv_pal
    ; fv_face (16x16): fv_head FRONT
    SKROWS fv_face_rows, 16, 16
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "..JJJ......JJJ.."
    SKROW "...WI......WI..."
    SKROW "..wxx......xxw.."
    SKROW "...ii......ii..."
    SKROW "....k......k...."
    SKROW "..bb........bb.."
    SKROW "................"
    SKROW ".....M....M....."
    SKROW "......MmmM......"
    SKROW ".......kk......."
    SKROW "................"
    SKROWS_END
    align 8
    SKBMP fv_face, fv_face_rows, 16, 16, fv_pal
    ; fv_hair_front (16x16): fv_hair FRONT
    SKROWS fv_hair_front_rows, 16, 16
    SKROW "................"
    SKROW "H..HHH.jjHHHH..j"
    SKROW "H..jH.JJ__.jjj.j"
    SKROW "H.JJjj____JJ__.j"
    SKROW "H.____________.j"
    SKROW "H.____________.j"
    SKROW "jj____________JJ"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP fv_hair_front, fv_hair_front_rows, 16, 16, fv_pal
    ; fv_hair_back (16x16): fv_hair BACK
    SKROWS fv_hair_back_rows, 16, 16
    SKROW "................"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "jj.jjj.jH..jjj.j"
    SKROW "__JJ__.jjj.j__JJ"
    SKROW "______JJ__JJ____"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP fv_hair_back, fv_hair_back_rows, 16, 16, fv_pal
    ; fv_hair_right (16x16): fv_hair RIGHT
    SKROWS fv_hair_right_rows, 16, 16
    SKROW "................"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jjjJJH..j"
    SKROW "H..jH..j____H.JJ"
    SKROW "H..jH.JJ____H.__"
    SKROW "H..jH.______jj__"
    SKROW "H..jjj__________"
    SKROW "H.JJ____________"
    SKROW "jj______________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP fv_hair_right, fv_hair_right_rows, 16, 16, fv_pal
    ; fv_hair_left (16x16): fv_hair LEFT
    SKROWS fv_hair_left_rows, 16, 16
    SKROW "................"
    SKROW "j..Hj..Hj..Hj..H"
    SKROW "j..Hj..Hj..Hj..H"
    SKROW "j..Hj..Hj..Hj..H"
    SKROW "j..Hj..Hj..Hj..H"
    SKROW "j..HJJjjj..Hj..H"
    SKROW "JJ.H____j..Hj..H"
    SKROW "__.H____JJ.Hj..H"
    SKROW "__jj______.Hj..H"
    SKROW "__________jjj..H"
    SKROW "____________JJ.H"
    SKROW "______________jj"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP fv_hair_left, fv_hair_left_rows, 16, 16, fv_pal
    ; fv_hair_top (16x16): fv_hair TOP
    SKROWS fv_hair_top_rows, 16, 16
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH.JjH..j"
    SKROW "H..jH..jH.JjH..j"
    SKROW "H..jH..jH.JjH..j"
    SKROW "H..jH..jH.JjH..j"
    SKROW "H..jH..jH.JjH..j"
    SKROW "H..jH..jH.JjH..j"
    SKROW "H..jH..jH.JjH..j"
    SKROW "H..jH..jH.JjH..j"
    SKROW "H..jH..jH.JjH..j"
    SKROWS_END
    align 8
    SKBMP fv_hair_top, fv_hair_top_rows, 16, 16, fv_pal
    ; fv_hair_bottom (16x16): fv_hair BOTTOM
    SKROWS fv_hair_bottom_rows, 16, 16
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "_.............._"
    SKROW "_.............._"
    SKROW "_.............._"
    SKROW "_.............._"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP fv_hair_bottom, fv_hair_bottom_rows, 16, 16, fv_pal
    ; fv_nose_front (2x3): fv_nose FRONT
    SKROWS fv_nose_front_rows, 2, 3
    SKROW "SS"
    SKROW "ss"
    SKROW "kk"
    SKROWS_END
    align 8
    SKBMP fv_nose_front, fv_nose_front_rows, 2, 3, fv_pal
    ; fv_ear (2x3): fv_ear_l LEFT, fv_ear_l RIGHT
    SKROWS fv_ear_rows, 2, 3
    SKROW "ss"
    SKROW "kk"
    SKROW "ss"
    SKROWS_END
    align 8
    SKBMP fv_ear, fv_ear_rows, 2, 3, fv_pal
    ; fv_leg_front (6x24): fv_leg_l FRONT
    SKROWS fv_leg_front_rows, 6, 24
    SKROW "qqqqqq"
    SKROW "P....q"
    SKROW "P....q"
    SKROW "P..q.q"
    SKROW "P..q.q"
    SKROW "P..q.q"
    SKROW "P..q.q"
    SKROW "P..q.q"
    SKROW "Pqq..q"
    SKROW "P...qq"
    SKROW "P....q"
    SKROW "P....q"
    SKROW "P....q"
    SKROW "P....q"
    SKROW "P....q"
    SKROW "P..q.q"
    SKROW "P..q.q"
    SKROW "P....q"
    SKROW "eeeeee"
    SKROW "leLcel"
    SKROW "lecLel"
    SKROW "leLcel"
    SKROW "EEEEEE"
    SKROW "EEEEEE"
    SKROWS_END
    align 8
    SKBMP fv_leg_front, fv_leg_front_rows, 6, 24, fv_pal
    ; fv_leg_back (6x24): fv_leg_l BACK
    SKROWS fv_leg_back_rows, 6, 24
    SKROW "qqqqqq"
    SKROW "P..q.q"
    SKROW "P..q.q"
    SKROW "P..q.q"
    SKROW "P..q.q"
    SKROW "P..q.q"
    SKROW "P..q.q"
    SKROW "P..q.q"
    SKROW "P..q.q"
    SKROW "Pqqqqq"
    SKROW "P..q.q"
    SKROW "P..q.q"
    SKROW "P..q.q"
    SKROW "P..q.q"
    SKROW "P..q.q"
    SKROW "P..q.q"
    SKROW "P....q"
    SKROW "P....q"
    SKROW "eeeeee"
    SKROW "lllell"
    SKROW "lllell"
    SKROW "lllell"
    SKROW "EEEEEE"
    SKROW "EEEEEE"
    SKROWS_END
    align 8
    SKBMP fv_leg_back, fv_leg_back_rows, 6, 24, fv_pal
    ; fv_leg_side (6x24): fv_leg_l LEFT, fv_leg_l RIGHT
    SKROWS fv_leg_side_rows, 6, 24
    SKROW "P....q"
    SKROW "P....q"
    SKROW "P.q..q"
    SKROW "P....q"
    SKROW "P.q..q"
    SKROW "P....q"
    SKROW "P.q..q"
    SKROW "P....q"
    SKROW "P.q..q"
    SKROW "P....q"
    SKROW "P.q..q"
    SKROW "P....q"
    SKROW "P.q..q"
    SKROW "P....q"
    SKROW "P.q..q"
    SKROW "P....q"
    SKROW "P.q..q"
    SKROW "P....q"
    SKROW "eeeeee"
    SKROW "Llllll"
    SKROW "Llllll"
    SKROW "Llllll"
    SKROW "EEEEEE"
    SKROW "EEEEEE"
    SKROWS_END
    align 8
    SKBMP fv_leg_side, fv_leg_side_rows, 6, 24, fv_pal
    ; fv_patch_front (4x4): fv_patch FRONT
    SKROWS fv_patch_front_rows, 4, 4
    SKROW "oRRo"
    SKROW "Rrrr"
    SKROW "Rrrr"
    SKROW "oRRo"
    SKROWS_END
    align 8
    SKBMP fv_patch_front, fv_patch_front_rows, 4, 4, fv_pal
    ; fv_foot_top (7x10): fv_foot_l TOP
    SKROWS fv_foot_top_rows, 7, 10
    SKROW "eeeeeee"
    SKROW "......L"
    SKROW "......L"
    SKROW "......L"
    SKROW "......L"
    SKROW "......L"
    SKROW "......L"
    SKROW "......L"
    SKROW "eeeeeee"
    SKROW "LLLLLLL"
    SKROWS_END
    align 8
    SKBMP fv_foot_top, fv_foot_top_rows, 7, 10, fv_pal
    ; fv_foot_sole (7x10): fv_foot_l BOTTOM
    SKROWS fv_foot_sole_rows, 7, 10
    SKROW "......."
    SKROW "eeeeeee"
    SKROW "......."
    SKROW "......."
    SKROW "eeeeeee"
    SKROW "......."
    SKROW "......."
    SKROW "eeeeeee"
    SKROW "......."
    SKROW "......."
    SKROWS_END
    align 8
    SKBMP fv_foot_sole, fv_foot_sole_rows, 7, 10, fv_pal
    ; fv_hand_front (6x22): fv_arm_l FRONT
    SKROWS fv_hand_front_rows, 6, 22
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "kkkkkk"
    SKROW "S....k"
    SKROW "Sk..kk"
    SKROW "Sk..kk"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP fv_hand_front, fv_hand_front_rows, 6, 22, fv_pal
    ; fv_hand_back (6x22): fv_arm_l BACK
    SKROWS fv_hand_back_rows, 6, 22
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "kkkkkk"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP fv_hand_back, fv_hand_back_rows, 6, 22, fv_pal

section .data
SKMODEL_BEGIN m_folk_villagers, 32, 0, 11, 26, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART fv_torso, -8, 24, -4, 16, 22, 8, 0, 0              ; green tunic
    PART fv_collar, -5, 42, -4, 10, 4, 8, 8, 0              ; round collar ring
    PART fv_belt, -8, 28, -4, 16, 2, 8, 4, 0                ; two-row rope belt overlay
    PART fv_buckle, -1, 28, -5, 2, 2, 1, 0, 0               ; brass buckle (2x2)
    SKBONE BK_HEAD, 0, 0, 0.00
    PART fv_head, -8, 46, -8, 16, 16, 16, 0, 0              ; the 16 texel head
    PART fv_hair, -8, 46, -8, 16, 16, 16, 4, SKPF_CUTOUT    ; hair overlay: fringe, sideburns, nape
    PART fv_nose, -1, 50, -10, 2, 3, 2, 0, 0                ; nose
    PART fv_ear_l, -9, 52, -1, 1, 3, 2, 0, 0                ; ear (the right one shares its skin)
    PART_AS fv_ear_r, fv_ear_l, 8, 52, -1, 0, 0
    SKBONE BK_LLEG, 24, 0, 1.00
    PART fv_leg_l, -6, 0, -3, 6, 24, 6, 0, 0                ; brown trousers
    PART fv_patch, -5, 9, -4, 4, 4, 1, 0, 0                 ; the knee patch (left leg only)
    PART fv_roll_l, -7, 6, -4, 7, 3, 8, 0, 0                ; trouser roll over the boot top
    PART fv_foot_l, -7, 0, -6, 7, 2, 10, 0, 0               ; the boot foot: toe cap, sole (the laced shaft is painted on the leg)
    SKBONE BK_RLEG, 24, 0, -1.00
    PART_AS fv_leg_r, fv_leg_l, 0, 0, -3, 0, 0
    PART_AS fv_roll_r, fv_roll_l, 0, 6, -4, 0, 0
    PART_AS fv_foot_r, fv_foot_l, 0, 0, -6, 0, 0
    SKBONE BK_LARM, 44, 0, -1.00
    PART fv_arm_l, -14, 24, -3, 6, 22, 6, 0, 0              ; sleeve at the top, bare forearm and hand
    PART fv_sleeve_l, -14, 36, -3, 6, 9, 6, 6, 0            ; rolled sleeve
    PART fv_cuff_l, -14, 34, -3, 6, 3, 6, 10, 0             ; the roll
    SKBONE BK_RARM, 44, 0, 1.00
    PART_AS fv_arm_r, fv_arm_l, 8, 24, -3, 0, 0
    PART_AS fv_sleeve_r, fv_sleeve_l, 8, 36, -3, 6, 0
    PART_AS fv_cuff_r, fv_cuff_l, 8, 34, -3, 10, 0
SKMODEL_PAINT
    ; --- fv_torso: green tunic, lace-up placket, patch pocket, shoulder seams, yoke and centre seam, hem
    SK_FILL fv_torso, SKM_ALL, FV_TUNIC_2, 15
    SK_BMP fv_torso, SKF_FRONT, 0, 0, fv_torso_front
    SK_BMP fv_torso, SKF_BACK, 0, 0, fv_torso_back
    SK_BMP fv_torso, SKF_RIGHT, 0, 0, fv_torso_side
    SK_BMP fv_torso, SKF_LEFT, 0, 0, fv_torso_side
    SK_RECT fv_torso, SKF_BOTTOM, 0, 0, 16, 8, FV_TUNIC_4, 0
    SK_GRAD fv_torso, SKM_SIDES, 272, 224
    ; --- fv_collar: a lighter ring with a stitched lower edge
    SK_FILL fv_collar, SKM_ALL, FV_TUNIC_1, 15
    SK_RECT fv_collar, SKF_FRONT, 0, 2, 10, 1, FV_TUNIC_2, 0
    SK_RECT fv_collar, SKF_FRONT, 0, 3, 10, 1, FV_TUNIC_3, 0
    SK_RECT fv_collar, SKF_BACK, 0, 2, 10, 1, FV_TUNIC_2, 0
    SK_RECT fv_collar, SKF_BACK, 0, 3, 10, 1, FV_TUNIC_3, 0
    SK_RECT fv_collar, SKF_LEFT, 0, 2, 8, 1, FV_TUNIC_2, 0
    SK_RECT fv_collar, SKF_LEFT, 0, 3, 8, 1, FV_TUNIC_3, 0
    SK_RECT fv_collar, SKF_RIGHT, 0, 2, 8, 1, FV_TUNIC_2, 0
    SK_RECT fv_collar, SKF_RIGHT, 0, 3, 8, 1, FV_TUNIC_3, 0
    SK_RECT fv_collar, SKF_BOTTOM, 0, 0, 10, 8, FV_TUNIC_4, 0
    ; --- fv_belt: two rows of twisted rope; fv_buckle: a 2x2 brass buckle
    SK_FILL fv_belt, SKM_ALL, FV_ROPE_2, 0
    SK_BMP fv_belt, SKF_FRONT, 0, 0, fv_rope
    SK_BMP fv_belt, SKF_BACK, 0, 0, fv_rope
    SK_BMP fv_belt, SKF_LEFT, 0, 0, fv_rope_side
    SK_BMP fv_belt, SKF_RIGHT, 0, 0, fv_rope_side
    SK_RECT fv_belt, SKF_TOP, 0, 0, 16, 8, FV_ROPE_1, 0
    SK_RECT fv_belt, SKF_BOTTOM, 0, 0, 16, 8, FV_ROPE_4, 0
    SK_FILL fv_buckle, SKM_ALL, AC_GOLD_3, 0
    SK_BMP fv_buckle, SKF_FRONT, 0, 0, fv_buckle_front
    ; --- fv_head: the face (brows, eyes with a glint and a sclera texel, freckles, blush, smile)
    SK_FILL fv_head, SKM_ALL, FV_SKIN_2, 15
    SK_GRAD fv_head, SKM_SIDES, 272, 224
    SK_RECT fv_head, SKF_TOP, 0, 0, 16, 16, FV_HAIR_2, 15
    SK_RECT fv_head, SKF_BACK, 0, 0, 16, 11, FV_HAIR_2, 15
    SK_RECT fv_head, SKF_RIGHT, 0, 0, 16, 6, FV_HAIR_2, 15
    SK_RECT fv_head, SKF_LEFT, 0, 0, 16, 6, FV_HAIR_2, 15
    SK_RECT fv_head, SKF_BOTTOM, 0, 0, 16, 16, FV_SKIN_4, 0
    SK_BMP fv_head, SKF_FRONT, 0, 0, fv_face
    ; --- fv_hair: a cutout overlay: grain first, then the locks (highlight / shade columns) and the holes
    SK_FILL fv_hair, SKM_ALL, FV_HAIR_2, 31
    SK_GRAD fv_hair, SKM_SIDES, 272, 224
    SK_BMP fv_hair, SKF_FRONT, 0, 0, fv_hair_front
    SK_BMP fv_hair, SKF_BACK, 0, 0, fv_hair_back
    SK_BMP fv_hair, SKF_RIGHT, 0, 0, fv_hair_right
    SK_BMP fv_hair, SKF_LEFT, 0, 0, fv_hair_left
    SK_BMP fv_hair, SKF_TOP, 0, 0, fv_hair_top
    SK_BMP fv_hair, SKF_BOTTOM, 0, 0, fv_hair_bottom
    ; --- fv_nose, fv_ear_l (shared with fv_ear_r)
    SK_FILL fv_nose, SKM_ALL, FV_SKIN_2, 7
    SK_BMP fv_nose, SKF_FRONT, 0, 0, fv_nose_front
    SK_RECT fv_nose, SKF_TOP, 0, 0, 2, 2, FV_SKIN_1, 0
    SK_RECT fv_nose, SKF_BOTTOM, 0, 0, 2, 2, FV_SKIN_4, 0
    SK_FILL fv_ear_l, SKM_ALL, FV_SKIN_2, 7
    SK_BMP fv_ear_l, SKF_LEFT, 0, 0, fv_ear
    SK_BMP fv_ear_l, SKF_RIGHT, 0, 0, fv_ear
    ; --- fv_leg_l (shared with fv_leg_r): trousers to row 17, the laced boot shaft below; fv_patch; fv_roll_l; fv_foot_l
    SK_FILL fv_leg_l, SKM_ALL, FV_PANTS_2, 15
    SK_RECT fv_leg_l, SKF_FRONT, 0, 18, 6, 6, AC_LEATHER_2, 15
    SK_RECT fv_leg_l, SKF_BACK, 0, 18, 6, 6, AC_LEATHER_2, 15
    SK_RECT fv_leg_l, SKF_LEFT, 0, 18, 6, 6, AC_LEATHER_2, 15
    SK_RECT fv_leg_l, SKF_RIGHT, 0, 18, 6, 6, AC_LEATHER_2, 15
    SK_BMP fv_leg_l, SKF_FRONT, 0, 0, fv_leg_front
    SK_BMP fv_leg_l, SKF_BACK, 0, 0, fv_leg_back
    SK_BMP fv_leg_l, SKF_LEFT, 0, 0, fv_leg_side
    SK_BMP fv_leg_l, SKF_RIGHT, 0, 0, fv_leg_side
    SK_RECT fv_leg_l, SKF_BOTTOM, 0, 0, 6, 6, AC_LEATHER_4, 0
    SK_GRAD fv_leg_l, SKM_SIDES, 272, 224
    SK_FILL fv_patch, SKM_ALL, FV_PANTS_3, 0
    SK_BMP fv_patch, SKF_FRONT, 0, 0, fv_patch_front
    SK_FILL fv_roll_l, SKM_ALL, FV_PANTS_1, 15
    SK_RECT fv_roll_l, SKF_FRONT, 0, 2, 7, 1, FV_PANTS_3, 0
    SK_RECT fv_roll_l, SKF_FRONT, 0, 0, 7, 1, FV_PANTS_1, 0
    SK_RECT fv_roll_l, SKF_BACK, 0, 2, 7, 1, FV_PANTS_3, 0
    SK_RECT fv_roll_l, SKF_BACK, 0, 0, 7, 1, FV_PANTS_1, 0
    SK_RECT fv_roll_l, SKF_LEFT, 0, 2, 8, 1, FV_PANTS_3, 0
    SK_RECT fv_roll_l, SKF_LEFT, 0, 0, 8, 1, FV_PANTS_1, 0
    SK_RECT fv_roll_l, SKF_RIGHT, 0, 2, 8, 1, FV_PANTS_3, 0
    SK_RECT fv_roll_l, SKF_RIGHT, 0, 0, 8, 1, FV_PANTS_1, 0
    SK_RECT fv_roll_l, SKF_TOP, 0, 0, 7, 8, FV_PANTS_1, 15
    SK_RECT fv_roll_l, SKF_BOTTOM, 0, 0, 7, 8, FV_PANTS_4, 0
    SK_FILL fv_foot_l, SKM_ALL, AC_LEATHER_2, 15
    SK_RECT fv_foot_l, SKF_FRONT, 0, 0, 7, 1, AC_LEATHER_1, 0
    SK_RECT fv_foot_l, SKF_FRONT, 0, 1, 7, 1, AC_LEATHER_4, 0
    SK_RECT fv_foot_l, SKF_BACK, 0, 0, 7, 1, AC_LEATHER_3, 0
    SK_RECT fv_foot_l, SKF_BACK, 0, 1, 7, 1, AC_LEATHER_4, 0
    SK_RECT fv_foot_l, SKF_LEFT, 0, 0, 10, 1, AC_LEATHER_1, 0
    SK_RECT fv_foot_l, SKF_LEFT, 0, 1, 10, 1, AC_LEATHER_4, 0
    SK_RECT fv_foot_l, SKF_RIGHT, 0, 0, 10, 1, AC_LEATHER_2, 0
    SK_RECT fv_foot_l, SKF_RIGHT, 0, 1, 10, 1, AC_LEATHER_4, 0
    SK_BMP fv_foot_l, SKF_TOP, 0, 0, fv_foot_top
    SK_RECT fv_foot_l, SKF_BOTTOM, 0, 0, 7, 10, AC_LEATHER_4, 0
    SK_BMP fv_foot_l, SKF_BOTTOM, 0, 0, fv_foot_sole
    ; --- fv_arm_l (shared with fv_arm_r): sleeve green to row 11, bare forearm, a hand with knuckle lines
    SK_FILL fv_arm_l, SKM_ALL, FV_SKIN_2, 15
    SK_RECT fv_arm_l, SKF_FRONT, 0, 0, 6, 12, FV_TUNIC_2, 15
    SK_RECT fv_arm_l, SKF_BACK, 0, 0, 6, 12, FV_TUNIC_2, 15
    SK_RECT fv_arm_l, SKF_LEFT, 0, 0, 6, 12, FV_TUNIC_2, 15
    SK_RECT fv_arm_l, SKF_RIGHT, 0, 0, 6, 12, FV_TUNIC_2, 15
    SK_RECT fv_arm_l, SKF_TOP, 0, 0, 6, 6, FV_TUNIC_2, 15
    SK_BMP fv_arm_l, SKF_FRONT, 0, 0, fv_hand_front
    SK_BMP fv_arm_l, SKF_BACK, 0, 0, fv_hand_back
    SK_RECT fv_arm_l, SKF_BOTTOM, 0, 0, 6, 6, FV_SKIN_3, 0
    SK_GRAD fv_arm_l, SKM_SIDES, 272, 224
    SK_FILL fv_sleeve_l, SKM_ALL, FV_TUNIC_2, 15
    SK_RECT fv_sleeve_l, SKF_TOP, 0, 0, 6, 6, FV_TUNIC_1, 15
    SK_RECT fv_sleeve_l, SKF_FRONT, 0, 0, 6, 1, FV_TUNIC_1, 0
    SK_RECT fv_sleeve_l, SKF_FRONT, 0, 0, 1, 9, FV_TUNIC_1, 0
    SK_RECT fv_sleeve_l, SKF_FRONT, 5, 0, 1, 9, FV_TUNIC_3, 0
    SK_RECT fv_sleeve_l, SKF_BACK, 0, 0, 6, 1, FV_TUNIC_1, 0
    SK_RECT fv_sleeve_l, SKF_BACK, 0, 0, 1, 9, FV_TUNIC_1, 0
    SK_RECT fv_sleeve_l, SKF_BACK, 5, 0, 1, 9, FV_TUNIC_3, 0
    SK_RECT fv_sleeve_l, SKF_LEFT, 0, 0, 6, 1, FV_TUNIC_1, 0
    SK_RECT fv_sleeve_l, SKF_LEFT, 0, 0, 1, 9, FV_TUNIC_1, 0
    SK_RECT fv_sleeve_l, SKF_LEFT, 5, 0, 1, 9, FV_TUNIC_3, 0
    SK_RECT fv_sleeve_l, SKF_RIGHT, 0, 0, 6, 1, FV_TUNIC_1, 0
    SK_RECT fv_sleeve_l, SKF_RIGHT, 0, 0, 1, 9, FV_TUNIC_1, 0
    SK_RECT fv_sleeve_l, SKF_RIGHT, 5, 0, 1, 9, FV_TUNIC_3, 0
    SK_GRAD fv_sleeve_l, SKM_SIDES, 272, 224
    SK_FILL fv_cuff_l, SKM_ALL, FV_TUNIC_1, 15
    SK_RECT fv_cuff_l, SKF_FRONT, 0, 2, 6, 1, FV_TUNIC_3, 0
    SK_RECT fv_cuff_l, SKF_BACK, 0, 2, 6, 1, FV_TUNIC_3, 0
    SK_RECT fv_cuff_l, SKF_LEFT, 0, 2, 6, 1, FV_TUNIC_3, 0
    SK_RECT fv_cuff_l, SKF_RIGHT, 0, 2, 6, 1, FV_TUNIC_3, 0
    SK_RECT fv_cuff_l, SKF_BOTTOM, 0, 0, 6, 6, FV_TUNIC_4, 0
SKMODEL_END

; ===================================================================================================
; m_avatar
; ===================================================================================================
RAMP AV_HAIR, 92, 58, 32               ; chestnut
RAMP AV_GREY, 208, 208, 208            ; the accent greys: the slot colour multiplies them
RAMP AV_LINEN, 226, 216, 192           ; undershirt
RAMP AV_PANTS, 64, 68, 96              ; dark trousers

section .rodata
; The characters of every av_ bitmap. Groups: base, highlight, shade, deep.
;   s S k K skin (b blush)   h H j J hair   a A z Z accent grey (the slot colour multiplies it)
;   f F v V linen   t T u U trousers   l L e E leather (AC)   o O i iron (AC)   y Y gold (AC)
;   w sclera   W glint   n N iris   x pupil   m M mouth   _ transparent
align 8
av_pal:
    PALC 's', AC_SKIN_2
    PALC 'S', AC_SKIN_1
    PALC 'k', AC_SKIN_3
    PALC 'K', RGBO(124, 90, 66)
    PALC 'b', RGBO(232, 140, 120)
    PALC 'h', AV_HAIR_2
    PALC 'H', AV_HAIR_1
    PALC 'j', AV_HAIR_3
    PALC 'J', AV_HAIR_4
    PALC 'a', AV_GREY_2
    PALC 'A', AV_GREY_1
    PALC 'z', AV_GREY_3
    PALC 'Z', AV_GREY_4
    PALC 'f', AV_LINEN_2
    PALC 'F', AV_LINEN_1
    PALC 'v', AV_LINEN_3
    PALC 'V', AV_LINEN_4
    PALC 't', AV_PANTS_2
    PALC 'T', AV_PANTS_1
    PALC 'u', AV_PANTS_3
    PALC 'U', AV_PANTS_4
    PALC 'l', AC_LEATHER_2
    PALC 'L', AC_LEATHER_1
    PALC 'e', AC_LEATHER_3
    PALC 'E', AC_LEATHER_4
    PALC 'o', AC_IRON_3
    PALC 'O', AC_IRON_1
    PALC 'i', AC_IRON_2
    PALC 'y', AC_GOLD_2
    PALC 'Y', AC_GOLD_1
    PALC 'w', RGBO(246, 246, 240)
    PALC 'W', RGBO(255, 255, 255)
    PALC 'n', RGBO(70, 112, 176)
    PALC 'N', RGBO(150, 190, 236)
    PALC 'x', RGBO(24, 30, 44)
    PALC 'm', RGBO(186, 112, 96)
    PALC 'M', RGBO(118, 58, 52)
    PALT '_'
    dq 0

    ; av_tunic_front (16x21): av_tunic FRONT
    SKROWS av_tunic_front_rows, 16, 21
    SKROW "AAAAAAAAAAAAAAAz"
    SKROW "Aaaaaaaaaaaaaaaz"
    SKROW "Az............zz"
    SKROW "Az.....zA.....zz"
    SKROW "Az.....zA.....zz"
    SKROW "Az.....ZZ.....zz"
    SKROW "Az.....zA.....zz"
    SKROW "Az.....zA.....zz"
    SKROW "Az.....zA.....zz"
    SKROW "Az.....ZZ.....zz"
    SKROW "Az.....zA.....zz"
    SKROW "Az.....zA.....zz"
    SKROW "Az.....zA.....zz"
    SKROW "Az.....ZZ.....zz"
    SKROW "Az.....zA.....zz"
    SKROW "Azzzz..zA..zzzzz"
    SKROW "A......zA......z"
    SKROW "A..............z"
    SKROW "A..............z"
    SKROW "AAAAAAA__AAAAAAA"
    SKROW "__zzzz____zzzz__"
    SKROWS_END
    align 8
    SKBMP av_tunic_front, av_tunic_front_rows, 16, 21, av_pal
    ; av_tunic_back (16x21): av_tunic BACK
    SKROWS av_tunic_back_rows, 16, 21
    SKROW "AAAAAAAAAAAAAAAz"
    SKROW "Aaaaaaaaaaaaaaaz"
    SKROW "A..............z"
    SKROW "A..............z"
    SKROW "zzzzzzzzzzzzzzzz"
    SKROW "A......zA......z"
    SKROW "A......zA......z"
    SKROW "A......zA......z"
    SKROW "A......zA......z"
    SKROW "A......zA......z"
    SKROW "A......zA......z"
    SKROW "A......zA......z"
    SKROW "A......zA......z"
    SKROW "A......zA......z"
    SKROW "A......zA......z"
    SKROW "A......zA......z"
    SKROW "A......zA......z"
    SKROW "A..............z"
    SKROW "A..............z"
    SKROW "AAAAAAA__AAAAAAA"
    SKROW "__zzzz____zzzz__"
    SKROWS_END
    align 8
    SKBMP av_tunic_back, av_tunic_back_rows, 16, 21, av_pal
    ; av_tunic_side (8x21): av_tunic LEFT, av_tunic RIGHT
    SKROWS av_tunic_side_rows, 8, 21
    SKROW "AAAAAAAA"
    SKROW "........"
    SKROW "........"
    SKROW "...z...."
    SKROW "...z...."
    SKROW "...z...."
    SKROW "...z...."
    SKROW "...z...."
    SKROW "...z...."
    SKROW "...z...."
    SKROW "...z...."
    SKROW "...z...."
    SKROW "...z...."
    SKROW "...z...."
    SKROW "...z...."
    SKROW "...z...."
    SKROW "...z...."
    SKROW "........"
    SKROW "........"
    SKROW "AAAAAAAA"
    SKROW "zz____zz"
    SKROWS_END
    align 8
    SKBMP av_tunic_side, av_tunic_side_rows, 8, 21, av_pal
    ; av_strap_front (16x14): av_strap FRONT
    SKROWS av_strap_front_rows, 16, 14
    SKROW "__Lll___________"
    SKROW "___Lle__________"
    SKROW "____Lll_________"
    SKROW "_____Lll________"
    SKROW "______Lle_______"
    SKROW "_______Lll______"
    SKROW "________Lll_____"
    SKROW "_________Lle____"
    SKROW "__________Lll___"
    SKROW "___________Lll__"
    SKROW "____________Lle_"
    SKROW "_____________Lll"
    SKROW "______________Ll"
    SKROW "_______________L"
    SKROWS_END
    align 8
    SKBMP av_strap_front, av_strap_front_rows, 16, 14, av_pal
    ; av_strap_back (16x14): av_strap BACK
    SKROWS av_strap_back_rows, 16, 14
    SKROW "_____________Lll"
    SKROW "____________Lle_"
    SKROW "___________Lll__"
    SKROW "__________Lll___"
    SKROW "_________Lle____"
    SKROW "________Lll_____"
    SKROW "_______Lll______"
    SKROW "______Lle_______"
    SKROW "_____Lll________"
    SKROW "____Lll_________"
    SKROW "___Lle__________"
    SKROW "__Lll___________"
    SKROW "_Lll____________"
    SKROW "Lle_____________"
    SKROWS_END
    align 8
    SKBMP av_strap_back, av_strap_back_rows, 16, 14, av_pal
    ; av_strap_left (8x14): av_strap LEFT
    SKROWS av_strap_left_rows, 8, 14
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "LLLLLLLL"
    SKROW "llllllll"
    SKROW "eeeeeeee"
    SKROWS_END
    align 8
    SKBMP av_strap_left, av_strap_left_rows, 8, 14, av_pal
    ; av_strap_right (8x14): av_strap RIGHT
    SKROWS av_strap_right_rows, 8, 14
    SKROW "___yy___"
    SKROW "___yy___"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROWS_END
    align 8
    SKBMP av_strap_right, av_strap_right_rows, 8, 14, av_pal
    ; av_strap_top (16x8): av_strap TOP
    SKROWS av_strap_top_rows, 16, 8
    SKROW "___Lle__________"
    SKROW "___Lle__________"
    SKROW "___Lle__________"
    SKROW "___Lle__________"
    SKROW "___Lle__________"
    SKROW "___Lle__________"
    SKROW "___Lle__________"
    SKROW "___Lle__________"
    SKROWS_END
    align 8
    SKBMP av_strap_top, av_strap_top_rows, 16, 8, av_pal
    ; av_strap_bottom (16x8): av_strap BOTTOM
    SKROWS av_strap_bottom_rows, 16, 8
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "__eee___________"
    SKROW "__eee___________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP av_strap_bottom, av_strap_bottom_rows, 16, 8, av_pal
    ; av_belt_img (16x2): av_belt FRONT, av_belt BACK
    SKROWS av_belt_img_rows, 16, 2
    SKROW "LLLLLLLLLLLLLLLL"
    SKROW "eeeeEeeeeEeeeeEe"
    SKROWS_END
    align 8
    SKBMP av_belt_img, av_belt_img_rows, 16, 2, av_pal
    ; av_belt_side (8x2): av_belt LEFT, av_belt RIGHT
    SKROWS av_belt_side_rows, 8, 2
    SKROW "LLLLLLLL"
    SKROW "eeeeEeee"
    SKROWS_END
    align 8
    SKBMP av_belt_side, av_belt_side_rows, 8, 2, av_pal
    ; av_buckle_front (2x2): av_buckle FRONT
    SKROWS av_buckle_front_rows, 2, 2
    SKROW "OO"
    SKROW "oE"
    SKROWS_END
    align 8
    SKBMP av_buckle_front, av_buckle_front_rows, 2, 2, av_pal
    ; av_scarf_stripes (14x4): av_scarf FRONT, av_scarf BACK
    SKROWS av_scarf_stripes_rows, 14, 4
    SKROW "AAAAAAAAAAAAAA"
    SKROW "aaaaaaaaaaaaaa"
    SKROW "zzzzzzzzzzzzzz"
    SKROW "ZZZZZZZZZZZZZZ"
    SKROWS_END
    align 8
    SKBMP av_scarf_stripes, av_scarf_stripes_rows, 14, 4, av_pal
    ; av_scarf_stripes_side (10x4): av_scarf LEFT, av_scarf RIGHT
    SKROWS av_scarf_stripes_side_rows, 10, 4
    SKROW "AAAAAAAAAA"
    SKROW "aaaaaaaaaa"
    SKROW "zzzzzzzzzz"
    SKROW "ZZZZZZZZZZ"
    SKROWS_END
    align 8
    SKBMP av_scarf_stripes_side, av_scarf_stripes_side_rows, 10, 4, av_pal
    ; av_scarf_tail_front (4x11): av_scarf_tail FRONT, av_scarf_tail BACK
    SKROWS av_scarf_tail_front_rows, 4, 11
    SKROW "...."
    SKROW "...."
    SKROW "zzzz"
    SKROW "zzzz"
    SKROW "...."
    SKROW "...."
    SKROW "zzzz"
    SKROW "zzzz"
    SKROW "...."
    SKROW "...."
    SKROW "ZzZz"
    SKROWS_END
    align 8
    SKBMP av_scarf_tail_front, av_scarf_tail_front_rows, 4, 11, av_pal
    ; av_satchel_back (6x9): av_satchel BACK
    SKROWS av_satchel_back_rows, 6, 9
    SKROW "llllll"
    SKROW "eeeeee"
    SKROW "l....E"
    SKROW "l....E"
    SKROW "l....E"
    SKROW "l....E"
    SKROW "lEEEEE"
    SKROW "l.ii.E"
    SKROW "l....E"
    SKROWS_END
    align 8
    SKBMP av_satchel_back, av_satchel_back_rows, 6, 9, av_pal
    ; av_flap_back (6x4): av_flap BACK
    SKROWS av_flap_back_rows, 6, 4
    SKROW "LLLLLL"
    SKROW "lllllL"
    SKROW "lleeel"
    SKROW "eeOOee"
    SKROWS_END
    align 8
    SKBMP av_flap_back, av_flap_back_rows, 6, 4, av_pal
    ; av_face (16x16): av_head FRONT
    SKROWS av_face_rows, 16, 16
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW ".............J.."
    SKROW "..JJJ......JJ..."
    SKROW "...WN......WN..."
    SKROW "..wxx......xxw.."
    SKROW "...nn......nn..."
    SKROW "................"
    SKROW "..bb........bb.."
    SKROW "................"
    SKROW ".....M....M....."
    SKROW "......MmmM......"
    SKROW ".......kk......."
    SKROW "................"
    SKROWS_END
    align 8
    SKBMP av_face, av_face_rows, 16, 16, av_pal
    ; av_hair_front (16x16): av_hair FRONT
    SKROWS av_hair_front_rows, 16, 16
    SKROW "................"
    SKROW "H..HHH.jHHHHjj.j"
    SKROW "H..jH..jjjJJ__.j"
    SKROW "H..jjjJJ______.j"
    SKROW "H.JJ__________.j"
    SKROW "H.____________JJ"
    SKROW "jj______________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP av_hair_front, av_hair_front_rows, 16, 16, av_pal
    ; av_hair_back (16x16): av_hair BACK
    SKROWS av_hair_back_rows, 16, 16
    SKROW "................"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "jj.jjj.jH.JJH.JJ"
    SKROW "__JJ__JJjj__jj__"
    SKROW "________________"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP av_hair_back, av_hair_back_rows, 16, 16, av_pal
    ; av_hair_right (16x16): av_hair RIGHT
    SKROWS av_hair_right_rows, 16, 16
    SKROW "................"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jH..jH..j"
    SKROW "H..jH..jjjJJH..j"
    SKROW "H..jH..j____H.JJ"
    SKROW "H..jH.JJ____jj__"
    SKROW "H..jH.__________"
    SKROW "H..jH.__________"
    SKROW "H..jjj__________"
    SKROW "H.JJ____________"
    SKROW "H.______________"
    SKROW "jj______________"
    SKROW "________________"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP av_hair_right, av_hair_right_rows, 16, 16, av_pal
    ; av_hair_left (16x16): av_hair LEFT
    SKROWS av_hair_left_rows, 16, 16
    SKROW "................"
    SKROW "j..Hj..Hj..Hj..H"
    SKROW "j..Hj..Hj..Hj..H"
    SKROW "j..Hj..Hj..Hj..H"
    SKROW "j..Hj..Hj..Hj..H"
    SKROW "j..HJJjjj..Hj..H"
    SKROW "JJ.H____j..Hj..H"
    SKROW "__jj____JJ.Hj..H"
    SKROW "__________.Hj..H"
    SKROW "__________.Hj..H"
    SKROW "__________jjj..H"
    SKROW "____________JJ.H"
    SKROW "______________.H"
    SKROW "______________jj"
    SKROW "________________"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP av_hair_left, av_hair_left_rows, 16, 16, av_pal
    ; av_hair_top (16x16): av_hair TOP
    SKROWS av_hair_top_rows, 16, 16
    SKROW "jH..jH..jH..jH.."
    SKROW "jH..jH..jH..jH.."
    SKROW "jH..jH..jH..jH.."
    SKROW "jH..jH..jH..jH.."
    SKROW "jH..jH..jH..jH.."
    SKROW "jH..jH..jH..jH.."
    SKROW "jH..JH..jH..jH.."
    SKROW "jH..JH..jH..jH.."
    SKROW "jH..JH..jH..jH.."
    SKROW "jH..JH..jH..jH.."
    SKROW "jH..JH..jH..jH.."
    SKROW "jH..JH..jH..jH.."
    SKROW "jH..JH..jH..jH.."
    SKROW "jH..JH..jH..jH.."
    SKROW "jH..JH..jH..jH.."
    SKROW "jH..JH..jH..jH.."
    SKROWS_END
    align 8
    SKBMP av_hair_top, av_hair_top_rows, 16, 16, av_pal
    ; av_hair_bottom (16x16): av_hair BOTTOM
    SKROWS av_hair_bottom_rows, 16, 16
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "_.............._"
    SKROW "_.............._"
    SKROW "_.............._"
    SKROW "_.............._"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP av_hair_bottom, av_hair_bottom_rows, 16, 16, av_pal
    ; av_nose_front (2x3): av_nose FRONT
    SKROWS av_nose_front_rows, 2, 3
    SKROW "SS"
    SKROW "ss"
    SKROW "kk"
    SKROWS_END
    align 8
    SKBMP av_nose_front, av_nose_front_rows, 2, 3, av_pal
    ; av_ear (2x3): av_ear_l LEFT, av_ear_l RIGHT
    SKROWS av_ear_rows, 2, 3
    SKROW "ss"
    SKROW "kk"
    SKROW "ss"
    SKROWS_END
    align 8
    SKBMP av_ear, av_ear_rows, 2, 3, av_pal
    ; av_leg_front (6x24): av_leg_l FRONT
    SKROWS av_leg_front_rows, 6, 24
    SKROW "uuuuuu"
    SKROW "T....u"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "Tuuu.u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "eeeeee"
    SKROW "LlllLl"
    SKROW "LeeeeE"
    SKROW "LlOllE"
    SKROW "LllllE"
    SKROW "eeeeee"
    SKROW "EEEEEE"
    SKROWS_END
    align 8
    SKBMP av_leg_front, av_leg_front_rows, 6, 24, av_pal
    ; av_leg_back (6x24): av_leg_l BACK
    SKROWS av_leg_back_rows, 6, 24
    SKROW "uuuuuu"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T....u"
    SKROW "eeeeee"
    SKROW "Llllle"
    SKROW "Leeeee"
    SKROW "Llllle"
    SKROW "Llllle"
    SKROW "eeeeee"
    SKROW "EEEEEE"
    SKROWS_END
    align 8
    SKBMP av_leg_back, av_leg_back_rows, 6, 24, av_pal
    ; av_leg_side (6x24): av_leg_l LEFT, av_leg_l RIGHT
    SKROWS av_leg_side_rows, 6, 24
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T.u..u"
    SKROW "T....u"
    SKROW "T.u..u"
    SKROW "T....u"
    SKROW "T.u..u"
    SKROW "T....u"
    SKROW "T.u..u"
    SKROW "T....u"
    SKROW "T.u..u"
    SKROW "T....u"
    SKROW "T.u..u"
    SKROW "T....u"
    SKROW "T.u..u"
    SKROW "T....u"
    SKROW "T.u..u"
    SKROW "eeeeee"
    SKROW "Llllle"
    SKROW "Leeeee"
    SKROW "Llllle"
    SKROW "Llllle"
    SKROW "eeeeee"
    SKROW "EEEEEE"
    SKROWS_END
    align 8
    SKBMP av_leg_side, av_leg_side_rows, 6, 24, av_pal
    ; av_knee_front (4x4): av_knee_l FRONT
    SKROWS av_knee_front_rows, 4, 4
    SKROW "LLLL"
    SKROW "lleE"
    SKROW "lleE"
    SKROW "EEEE"
    SKROWS_END
    align 8
    SKBMP av_knee_front, av_knee_front_rows, 4, 4, av_pal
    ; av_foot_top (7x10): av_foot_l TOP
    SKROWS av_foot_top_rows, 7, 10
    SKROW "eeeeeee"
    SKROW "......L"
    SKROW "......L"
    SKROW "......L"
    SKROW "......L"
    SKROW "......L"
    SKROW "......L"
    SKROW "......L"
    SKROW "eeeeeee"
    SKROW "LLLLLLL"
    SKROWS_END
    align 8
    SKBMP av_foot_top, av_foot_top_rows, 7, 10, av_pal
    ; av_foot_sole (7x10): av_foot_l BOTTOM
    SKROWS av_foot_sole_rows, 7, 10
    SKROW "......."
    SKROW "eeeeeee"
    SKROW "......."
    SKROW "......."
    SKROW "eeeeeee"
    SKROW "......."
    SKROW "......."
    SKROW "eeeeeee"
    SKROW "......."
    SKROW "......."
    SKROWS_END
    align 8
    SKBMP av_foot_sole, av_foot_sole_rows, 7, 10, av_pal
    ; av_hand_front (6x22): av_arm_l FRONT
    SKROWS av_hand_front_rows, 6, 22
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "vvvvvv"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "kkkkkk"
    SKROW "S....k"
    SKROW "Sk..kk"
    SKROW "Sk..kk"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP av_hand_front, av_hand_front_rows, 6, 22, av_pal
    ; av_hand_back (6x22): av_arm_l BACK
    SKROWS av_hand_back_rows, 6, 22
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "vvvvvv"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "kkkkkk"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP av_hand_back, av_hand_back_rows, 6, 22, av_pal
    ; av_hand_side (6x22): av_arm_l LEFT, av_arm_l RIGHT
    SKROWS av_hand_side_rows, 6, 22
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "vvvvvv"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "kkkkkk"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP av_hand_side, av_hand_side_rows, 6, 22, av_pal

section .data
SKMODEL_BEGIN m_avatar, 32, 0, 11, 26, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART av_torso, -8, 24, -4, 16, 22, 8, 0, 0              ; linen undershirt
    PART av_tunic, -8, 25, -4, 16, 21, 8, 4, SKPF_ACCENT | SKPF_CUTOUT; tunic overlay, notched hem (accent)
    PART av_strap, -8, 32, -4, 16, 14, 8, 6, SKPF_CUTOUT    ; satchel strap: shoulder to left hip, round the side
    PART av_belt, -8, 28, -4, 16, 2, 8, 8, 0                ; leather belt
    PART av_buckle, -1, 28, -6, 2, 2, 1, 0, 0               ; iron buckle
    PART av_scarf, -7, 42, -5, 14, 4, 10, 4, SKPF_ACCENT    ; scarf round the neck (accent)
    PART av_scarf_tail, 3, 31, -5, 4, 11, 1, 4, SKPF_ACCENT ; scarf end down the chest (accent)
    SKBONE BK_HEAD, 0, 0, 0.00
    PART av_head, -8, 46, -8, 16, 16, 16, 0, 0              ; the 16 texel head
    PART av_hair, -8, 46, -8, 16, 16, 16, 4, SKPF_CUTOUT    ; hair overlay: swept fringe, sideburns, long nape
    PART av_nose, -1, 50, -10, 2, 3, 2, 0, 0                ; nose
    PART av_ear_l, -9, 52, -1, 1, 3, 2, 0, 0                ; ear (the right one shares its skin)
    PART_AS av_ear_r, av_ear_l, 8, 52, -1, 0, 0
    PART av_ponytail, -1, 49, 8, 2, 7, 2, 0, 0              ; ponytail
    PART av_tie, -2, 55, 7, 4, 2, 4, 0, SKPF_ACCENT         ; its tie (accent)
    SKBONE BK_LLEG, 24, 0, 1.00
    PART av_leg_l, -6, 0, -3, 6, 24, 6, 0, 0                ; dark trousers
    PART av_knee_l, -5, 11, -4, 4, 4, 1, 0, 0               ; leather knee guard
    PART av_cuff_l, -7, 7, -4, 7, 3, 8, 0, 0                ; folded boot cuff
    PART av_foot_l, -7, 0, -6, 7, 3, 10, 0, 0               ; the boot foot: toe cap, sole (the shaft is painted on the leg)
    SKBONE BK_RLEG, 24, 0, -1.00
    PART_AS av_leg_r, av_leg_l, 0, 0, -3, 0, 0
    PART_AS av_knee_r, av_knee_l, 1, 11, -4, 0, 0
    PART_AS av_cuff_r, av_cuff_l, 0, 7, -4, 0, 0
    PART_AS av_foot_r, av_foot_l, 0, 0, -6, 0, 0
    SKBONE BK_LARM, 44, 0, -1.00
    PART av_arm_l, -14, 24, -3, 6, 22, 6, 0, 0              ; undershirt at the top, bare forearm and hand
    PART av_sleeve_l, -14, 35, -3, 6, 11, 6, 6, SKPF_ACCENT ; upper sleeve (accent)
    SKBONE BK_RARM, 44, 0, 1.00
    PART_AS av_arm_r, av_arm_l, 8, 24, -3, 0, 0
    PART_AS av_sleeve_r, av_sleeve_l, 8, 35, -3, 6, SKPF_ACCENT
    SKBONE BK_LIMB, 0, 0, 0.00                      ; rigid (swing 0): a seated pilot does not draw it, his back is on the seat
    PART av_satchel, -7, 24, 4, 6, 9, 4, 0, 0               ; satchel at the left hip, behind
    PART av_flap, -7, 29, 8, 6, 4, 1, 0, 0                  ; its flap
SKMODEL_PAINT
    ; --- av_torso: the linen undershirt (shows at the notched hem and under the tunic)
    SK_FILL av_torso, SKM_ALL, AV_LINEN_2, 15
    SK_GRAD av_torso, SKM_SIDES, 272, 224
    SK_RECT av_torso, SKF_FRONT, 0, 21, 16, 1, AV_LINEN_3, 0
    SK_RECT av_torso, SKF_BACK, 0, 21, 16, 1, AV_LINEN_3, 0
    SK_RECT av_torso, SKF_BOTTOM, 0, 0, 16, 8, AV_LINEN_4, 0
    ; --- av_tunic (accent): light greys carry the slot colour; seams and buttons are the deep grey
    SK_FILL av_tunic, SKM_ALL, AV_GREY_2, 15
    SK_BMP av_tunic, SKF_FRONT, 0, 0, av_tunic_front
    SK_BMP av_tunic, SKF_BACK, 0, 0, av_tunic_back
    SK_BMP av_tunic, SKF_LEFT, 0, 0, av_tunic_side
    SK_BMP av_tunic, SKF_RIGHT, 0, 0, av_tunic_side
    SK_RECT av_tunic, SKF_BOTTOM, 0, 0, 16, 8, AV_GREY_4, 0
    SK_GRAD av_tunic, SKM_SIDES, 272, 224
    ; --- av_strap: leather, diagonal over the right shoulder to the left hip (45 degrees), round the side and back
    SK_FILL av_strap, SKM_ALL, AC_LEATHER_2, 7
    SK_BMP av_strap, SKF_FRONT, 0, 0, av_strap_front
    SK_BMP av_strap, SKF_BACK, 0, 0, av_strap_back
    SK_BMP av_strap, SKF_LEFT, 0, 0, av_strap_left
    SK_BMP av_strap, SKF_RIGHT, 0, 0, av_strap_right
    SK_BMP av_strap, SKF_TOP, 0, 0, av_strap_top
    SK_BMP av_strap, SKF_BOTTOM, 0, 0, av_strap_bottom
    ; --- av_belt (two rows) and av_buckle (2x2)
    SK_FILL av_belt, SKM_ALL, AC_LEATHER_2, 7
    SK_BMP av_belt, SKF_FRONT, 0, 0, av_belt_img
    SK_BMP av_belt, SKF_BACK, 0, 0, av_belt_img
    SK_BMP av_belt, SKF_LEFT, 0, 0, av_belt_side
    SK_BMP av_belt, SKF_RIGHT, 0, 0, av_belt_side
    SK_RECT av_belt, SKF_TOP, 0, 0, 16, 8, AC_LEATHER_1, 0
    SK_RECT av_belt, SKF_BOTTOM, 0, 0, 16, 8, AC_LEATHER_4, 0
    SK_FILL av_buckle, SKM_ALL, AC_IRON_3, 0
    SK_BMP av_buckle, SKF_FRONT, 0, 0, av_buckle_front
    ; --- av_scarf and av_scarf_tail (accent): knit stripes in light greys
    SK_FILL av_scarf, SKM_ALL, AV_GREY_2, 15
    SK_BMP av_scarf, SKF_FRONT, 0, 0, av_scarf_stripes
    SK_BMP av_scarf, SKF_BACK, 0, 0, av_scarf_stripes
    SK_BMP av_scarf, SKF_LEFT, 0, 0, av_scarf_stripes_side
    SK_BMP av_scarf, SKF_RIGHT, 0, 0, av_scarf_stripes_side
    SK_RECT av_scarf, SKF_TOP, 0, 0, 14, 10, AV_GREY_1, 0
    SK_RECT av_scarf, SKF_BOTTOM, 0, 0, 14, 10, AV_GREY_4, 0
    SK_FILL av_scarf_tail, SKM_ALL, AV_GREY_2, 15
    SK_BMP av_scarf_tail, SKF_FRONT, 0, 0, av_scarf_tail_front
    SK_BMP av_scarf_tail, SKF_BACK, 0, 0, av_scarf_tail_front
    ; --- av_satchel and av_flap: leather, stitched, an iron buckle
    SK_FILL av_satchel, SKM_ALL, AC_LEATHER_3, 15
    SK_BMP av_satchel, SKF_BACK, 0, 0, av_satchel_back
    SK_RECT av_satchel, SKF_TOP, 0, 0, 6, 4, AC_LEATHER_1, 0
    SK_RECT av_satchel, SKF_BOTTOM, 0, 0, 6, 4, AC_LEATHER_4, 0
    SK_GRAD av_satchel, SKM_SIDES, 272, 224
    SK_FILL av_flap, SKM_ALL, AC_LEATHER_2, 7
    SK_BMP av_flap, SKF_BACK, 0, 0, av_flap_back
    SK_RECT av_flap, SKF_TOP, 0, 0, 6, 1, AC_LEATHER_1, 0
    SK_RECT av_flap, SKF_BOTTOM, 0, 0, 6, 1, AC_LEATHER_4, 0
    ; --- av_head: blue eyes (glint, pupil, sclera texel), one raised brow, blush, a smirk
    SK_FILL av_head, SKM_ALL, AC_SKIN_2, 15
    SK_GRAD av_head, SKM_SIDES, 272, 224
    SK_RECT av_head, SKF_TOP, 0, 0, 16, 16, AV_HAIR_2, 15
    SK_RECT av_head, SKF_BACK, 0, 0, 16, 12, AV_HAIR_2, 15
    SK_RECT av_head, SKF_RIGHT, 0, 0, 16, 6, AV_HAIR_2, 15
    SK_RECT av_head, SKF_LEFT, 0, 0, 16, 6, AV_HAIR_2, 15
    SK_RECT av_head, SKF_BOTTOM, 0, 0, 16, 16, RGBO(124, 90, 66), 0
    SK_BMP av_head, SKF_FRONT, 0, 0, av_face
    ; --- av_hair: cutout overlay, the fringe sweeps to the left, a longer nape
    SK_FILL av_hair, SKM_ALL, AV_HAIR_2, 31
    SK_GRAD av_hair, SKM_SIDES, 272, 224
    SK_BMP av_hair, SKF_FRONT, 0, 0, av_hair_front
    SK_BMP av_hair, SKF_BACK, 0, 0, av_hair_back
    SK_BMP av_hair, SKF_RIGHT, 0, 0, av_hair_right
    SK_BMP av_hair, SKF_LEFT, 0, 0, av_hair_left
    SK_BMP av_hair, SKF_TOP, 0, 0, av_hair_top
    SK_BMP av_hair, SKF_BOTTOM, 0, 0, av_hair_bottom
    SK_FILL av_ponytail, SKM_ALL, AV_HAIR_2, 31
    SK_RECT av_ponytail, SKF_BACK, 0, 5, 2, 2, AV_HAIR_4, 0
    SK_RECT av_ponytail, SKF_BOTTOM, 0, 0, 2, 2, AV_HAIR_4, 0
    SK_GRAD av_ponytail, SKM_SIDES, 272, 224
    SK_FILL av_tie, SKM_ALL, AV_GREY_2, 7
    SK_RECT av_tie, SKF_FRONT, 0, 0, 4, 1, AV_GREY_1, 0
    SK_RECT av_tie, SKF_TOP, 0, 0, 4, 4, AV_GREY_1, 0
    ; --- av_nose, av_ear_l (shared with av_ear_r)
    SK_FILL av_nose, SKM_ALL, AC_SKIN_2, 7
    SK_BMP av_nose, SKF_FRONT, 0, 0, av_nose_front
    SK_RECT av_nose, SKF_TOP, 0, 0, 2, 2, AC_SKIN_1, 0
    SK_RECT av_nose, SKF_BOTTOM, 0, 0, 2, 2, RGBO(124, 90, 66), 0
    SK_FILL av_ear_l, SKM_ALL, AC_SKIN_2, 7
    SK_BMP av_ear_l, SKF_LEFT, 0, 0, av_ear
    SK_BMP av_ear_l, SKF_RIGHT, 0, 0, av_ear
    ; --- av_leg_l (shared with av_leg_r): dark trousers to row 16, the leather boot shaft below; av_knee_l; av_cuff_l; av_foot_l
    SK_FILL av_leg_l, SKM_ALL, AV_PANTS_2, 15
    SK_RECT av_leg_l, SKF_FRONT, 0, 17, 6, 7, AC_LEATHER_2, 15
    SK_RECT av_leg_l, SKF_BACK, 0, 17, 6, 7, AC_LEATHER_2, 15
    SK_RECT av_leg_l, SKF_LEFT, 0, 17, 6, 7, AC_LEATHER_2, 15
    SK_RECT av_leg_l, SKF_RIGHT, 0, 17, 6, 7, AC_LEATHER_2, 15
    SK_BMP av_leg_l, SKF_FRONT, 0, 0, av_leg_front
    SK_BMP av_leg_l, SKF_BACK, 0, 0, av_leg_back
    SK_BMP av_leg_l, SKF_LEFT, 0, 0, av_leg_side
    SK_BMP av_leg_l, SKF_RIGHT, 0, 0, av_leg_side
    SK_RECT av_leg_l, SKF_BOTTOM, 0, 0, 6, 6, AC_LEATHER_4, 0
    SK_GRAD av_leg_l, SKM_SIDES, 272, 224
    SK_FILL av_knee_l, SKM_ALL, AC_LEATHER_3, 7
    SK_BMP av_knee_l, SKF_FRONT, 0, 0, av_knee_front
    SK_FILL av_cuff_l, SKM_ALL, AC_LEATHER_1, 15
    SK_RECT av_cuff_l, SKF_FRONT, 0, 0, 7, 1, AC_LEATHER_1, 0
    SK_RECT av_cuff_l, SKF_FRONT, 0, 2, 7, 1, AC_LEATHER_3, 0
    SK_RECT av_cuff_l, SKF_BACK, 0, 0, 7, 1, AC_LEATHER_1, 0
    SK_RECT av_cuff_l, SKF_BACK, 0, 2, 7, 1, AC_LEATHER_3, 0
    SK_RECT av_cuff_l, SKF_LEFT, 0, 0, 8, 1, AC_LEATHER_1, 0
    SK_RECT av_cuff_l, SKF_LEFT, 0, 2, 8, 1, AC_LEATHER_3, 0
    SK_RECT av_cuff_l, SKF_RIGHT, 0, 0, 8, 1, AC_LEATHER_1, 0
    SK_RECT av_cuff_l, SKF_RIGHT, 0, 2, 8, 1, AC_LEATHER_3, 0
    SK_RECT av_cuff_l, SKF_TOP, 0, 0, 7, 8, AC_LEATHER_1, 15
    SK_RECT av_cuff_l, SKF_BOTTOM, 0, 0, 7, 8, AC_LEATHER_4, 0
    SK_FILL av_foot_l, SKM_ALL, AC_LEATHER_2, 15
    SK_RECT av_foot_l, SKF_FRONT, 0, 0, 7, 1, AC_LEATHER_1, 0
    SK_RECT av_foot_l, SKF_FRONT, 0, 2, 7, 1, AC_LEATHER_4, 0
    SK_RECT av_foot_l, SKF_BACK, 0, 0, 7, 1, AC_LEATHER_3, 0
    SK_RECT av_foot_l, SKF_BACK, 0, 2, 7, 1, AC_LEATHER_4, 0
    SK_RECT av_foot_l, SKF_LEFT, 0, 0, 10, 1, AC_LEATHER_1, 0
    SK_RECT av_foot_l, SKF_LEFT, 0, 2, 10, 1, AC_LEATHER_4, 0
    SK_RECT av_foot_l, SKF_RIGHT, 0, 0, 10, 1, AC_LEATHER_2, 0
    SK_RECT av_foot_l, SKF_RIGHT, 0, 2, 10, 1, AC_LEATHER_4, 0
    SK_BMP av_foot_l, SKF_TOP, 0, 0, av_foot_top
    SK_RECT av_foot_l, SKF_BOTTOM, 0, 0, 7, 10, AC_LEATHER_4, 0
    SK_BMP av_foot_l, SKF_BOTTOM, 0, 0, av_foot_sole
    ; --- av_arm_l (shared with av_arm_r): linen at the top (under the sleeve), bare skin from row 12, a hand
    SK_FILL av_arm_l, SKM_ALL, AC_SKIN_2, 15
    SK_RECT av_arm_l, SKF_FRONT, 0, 0, 6, 11, AV_LINEN_2, 15
    SK_RECT av_arm_l, SKF_BACK, 0, 0, 6, 11, AV_LINEN_2, 15
    SK_RECT av_arm_l, SKF_LEFT, 0, 0, 6, 11, AV_LINEN_2, 15
    SK_RECT av_arm_l, SKF_RIGHT, 0, 0, 6, 11, AV_LINEN_2, 15
    SK_RECT av_arm_l, SKF_TOP, 0, 0, 6, 6, AV_LINEN_2, 15
    SK_BMP av_arm_l, SKF_FRONT, 0, 0, av_hand_front
    SK_BMP av_arm_l, SKF_BACK, 0, 0, av_hand_back
    SK_BMP av_arm_l, SKF_LEFT, 0, 0, av_hand_side
    SK_BMP av_arm_l, SKF_RIGHT, 0, 0, av_hand_side
    SK_RECT av_arm_l, SKF_BOTTOM, 0, 0, 6, 6, AC_SKIN_3, 0
    SK_GRAD av_arm_l, SKM_SIDES, 272, 224
    SK_FILL av_sleeve_l, SKM_ALL, AV_GREY_2, 15
    SK_RECT av_sleeve_l, SKF_TOP, 0, 0, 6, 6, AV_GREY_1, 15
    SK_RECT av_sleeve_l, SKF_FRONT, 0, 0, 6, 1, AV_GREY_1, 0
    SK_RECT av_sleeve_l, SKF_FRONT, 0, 0, 1, 11, AV_GREY_1, 0
    SK_RECT av_sleeve_l, SKF_FRONT, 5, 0, 1, 11, AV_GREY_3, 0
    SK_RECT av_sleeve_l, SKF_FRONT, 0, 9, 6, 1, AV_GREY_1, 0
    SK_RECT av_sleeve_l, SKF_FRONT, 0, 10, 6, 1, AV_GREY_3, 0
    SK_RECT av_sleeve_l, SKF_BACK, 0, 0, 6, 1, AV_GREY_1, 0
    SK_RECT av_sleeve_l, SKF_BACK, 0, 0, 1, 11, AV_GREY_1, 0
    SK_RECT av_sleeve_l, SKF_BACK, 5, 0, 1, 11, AV_GREY_3, 0
    SK_RECT av_sleeve_l, SKF_BACK, 0, 9, 6, 1, AV_GREY_1, 0
    SK_RECT av_sleeve_l, SKF_BACK, 0, 10, 6, 1, AV_GREY_3, 0
    SK_RECT av_sleeve_l, SKF_LEFT, 0, 0, 6, 1, AV_GREY_1, 0
    SK_RECT av_sleeve_l, SKF_LEFT, 0, 0, 1, 11, AV_GREY_1, 0
    SK_RECT av_sleeve_l, SKF_LEFT, 5, 0, 1, 11, AV_GREY_3, 0
    SK_RECT av_sleeve_l, SKF_LEFT, 0, 9, 6, 1, AV_GREY_1, 0
    SK_RECT av_sleeve_l, SKF_LEFT, 0, 10, 6, 1, AV_GREY_3, 0
    SK_RECT av_sleeve_l, SKF_RIGHT, 0, 0, 6, 1, AV_GREY_1, 0
    SK_RECT av_sleeve_l, SKF_RIGHT, 0, 0, 1, 11, AV_GREY_1, 0
    SK_RECT av_sleeve_l, SKF_RIGHT, 5, 0, 1, 11, AV_GREY_3, 0
    SK_RECT av_sleeve_l, SKF_RIGHT, 0, 9, 6, 1, AV_GREY_1, 0
    SK_RECT av_sleeve_l, SKF_RIGHT, 0, 10, 6, 1, AV_GREY_3, 0
    SK_GRAD av_sleeve_l, SKM_SIDES, 272, 224
    SK_RECT av_sleeve_l, SKF_BOTTOM, 0, 0, 6, 6, AV_GREY_4, 0
SKMODEL_END

; ===================================================================================================
; m_folk_bandits
; ===================================================================================================
RAMP FB_SKIN, 200, 150, 110             ; tan skin (the factions table)
RAMP FB_HAIR, 64, 46, 36
RAMP FB_RED, 150, 30, 30                ; the bandana
RAMP FB_LEATHER, 80, 55, 35             ; dark leather jerkin
RAMP FB_PANTS, 60, 60, 60               ; dark grey trousers
RAMP FB_CLOTH, 34, 32, 38               ; the black mask
RAMP FB_SHIRT, 118, 50, 46              ; the faded red shirt
RAMP FB_WRAP, 170, 152, 120             ; boot wraps

section .rodata
; The characters of every fb_ bitmap. Groups: base, highlight, shade, deep.
;   s S k K skin (b scar)   h H j J hair   r R d D bandana red   l L e E jerkin leather (dark)
;   o O p P strap leather (AC)   t T q Q trousers   f F v V faded red shirt   a A z Z black cloth (the mask)
;   g G n N boot wraps   i I u U iron (AC)   y Y brass (AC gold)   c cream thread   C grey print   w sclera   W glint
;   x pupil   m M iris   _ transparent
align 8
fb_pal:
    PALC 's', FB_SKIN_2
    PALC 'S', FB_SKIN_1
    PALC 'k', FB_SKIN_3
    PALC 'K', FB_SKIN_4
    PALC 'b', RGBO(214, 120, 104)
    PALC 'h', FB_HAIR_2
    PALC 'H', FB_HAIR_1
    PALC 'j', FB_HAIR_3
    PALC 'J', FB_HAIR_4
    PALC 'r', FB_RED_2
    PALC 'R', FB_RED_1
    PALC 'd', FB_RED_3
    PALC 'D', FB_RED_4
    PALC 'l', FB_LEATHER_2
    PALC 'L', FB_LEATHER_1
    PALC 'e', FB_LEATHER_3
    PALC 'E', FB_LEATHER_4
    PALC 'o', AC_LEATHER_2
    PALC 'O', AC_LEATHER_1
    PALC 'p', AC_LEATHER_3
    PALC 'P', AC_LEATHER_4
    PALC 't', FB_PANTS_2
    PALC 'T', FB_PANTS_1
    PALC 'q', FB_PANTS_3
    PALC 'Q', FB_PANTS_4
    PALC 'f', FB_SHIRT_2
    PALC 'F', FB_SHIRT_1
    PALC 'v', FB_SHIRT_3
    PALC 'V', FB_SHIRT_4
    PALC 'a', FB_CLOTH_2
    PALC 'A', RGBO(84, 82, 104)
    PALC 'z', FB_CLOTH_3
    PALC 'Z', FB_CLOTH_4
    PALC 'C', RGBO(150, 148, 168)
    PALC 'g', FB_WRAP_2
    PALC 'G', FB_WRAP_1
    PALC 'n', FB_WRAP_3
    PALC 'N', FB_WRAP_4
    PALC 'i', AC_IRON_3
    PALC 'I', AC_IRON_1
    PALC 'u', AC_IRON_4
    PALC 'U', AC_IRON_2
    PALC 'y', AC_GOLD_2
    PALC 'Y', AC_GOLD_1
    PALC 'c', RGBO(232, 220, 190)
    PALC 'w', RGBO(246, 246, 240)
    PALC 'W', RGBO(255, 255, 255)
    PALC 'x', RGBO(28, 20, 16)
    PALC 'm', RGBO(96, 60, 36)
    PALC 'M', RGBO(150, 100, 60)
    PALT '_'
    dq 0

    ; fb_torso_front (16x22): fb_torso FRONT
    SKROWS fb_torso_front_rows, 16, 22
    SKROW "L..LFffffffve..."
    SKROW "L...LFffffve...."
    SKROW "L....LFffve....."
    SKROW "L.....LFve......"
    SKROW "L.....LFve......"
    SKROW "L......Ee......."
    SKROW "L..e..cEec..e..."
    SKROW "L..e...Ee...e..."
    SKROW "L.....cEec......"
    SKROW "L..e...Ee...e..."
    SKROW "L..e..cEec..e..."
    SKROW "L......Ee......."
    SKROW "L..e...Ee...e..."
    SKROW "L..e...Ee...e..."
    SKROW "L......Ee......."
    SKROW "L..e...Ee...e..."
    SKROW "L..e...Ee...e..."
    SKROW "L......Ee......."
    SKROW "eeeeeeeeeeeeeeee"
    SKROW "LllElllElllElllE"
    SKROW "FfffFfffFfffFfff"
    SKROW "vvVvvvVvvvVvvvVv"
    SKROWS_END
    align 8
    SKBMP fb_torso_front, fb_torso_front_rows, 16, 22, fb_pal
    ; fb_torso_back (16x22): fb_torso BACK
    SKROWS fb_torso_back_rows, 16, 22
    SKROW "L..............."
    SKROW "L..............."
    SKROW "L..............."
    SKROW "L..............."
    SKROW "eeeeeeeeeeeeeeee"
    SKROW "LLLLLLLLLLLLLLLL"
    SKROW "L......eL......."
    SKROW "L......eL...L..."
    SKROW "L.eeee.eL....L.."
    SKROW "L.cLle.eL......."
    SKROW "L.elle.eL......."
    SKROW "L.ceee.eL.eeee.."
    SKROW "L......eL.cLle.."
    SKROW "L......eL.elle.."
    SKROW "L......eL.ceee.."
    SKROW "L..L...eL......."
    SKROW "L...L..eL......."
    SKROW "L......eL......."
    SKROW "eeeeeeeeeeeeeeee"
    SKROW "LllElllElllElllE"
    SKROW "FfffFfffFfffFfff"
    SKROW "vvVvvvVvvvVvvvVv"
    SKROWS_END
    align 8
    SKBMP fb_torso_back, fb_torso_back_rows, 16, 22, fb_pal
    ; fb_torso_side (8x22): fb_torso RIGHT, fb_torso LEFT
    SKROWS fb_torso_side_rows, 8, 22
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "...EE..."
    SKROW "...cc..."
    SKROW "...EE..."
    SKROW "...cc..."
    SKROW "...EE..."
    SKROW "...cc..."
    SKROW "...EE..."
    SKROW "...cc..."
    SKROW "...EE..."
    SKROW "...cc..."
    SKROW "...EE..."
    SKROW "...cc..."
    SKROW "...EE..."
    SKROW "...cc..."
    SKROW "........"
    SKROW "eeeeeeee"
    SKROW "lllElllE"
    SKROW "FfffFfff"
    SKROW "vvVvvvVv"
    SKROWS_END
    align 8
    SKBMP fb_torso_side, fb_torso_side_rows, 8, 22, fb_pal
    ; fb_harness_front (16x15): fb_harness FRONT
    SKROWS fb_harness_front_rows, 16, 15
    SKROW "_Ooop______Ooop_"
    SKROW "__Ooop____Ooop__"
    SKROW "__Ooop____Ooop__"
    SKROW "___Ooop__Ooop___"
    SKROW "____OoopOoop____"
    SKROW "_____OoOoop_____"
    SKROW "_____OUiiop_____"
    SKROW "______iPup______"
    SKROW "_____Oiuuop_____"
    SKROW "_____Ooopop_____"
    SKROW "____OoopOoop____"
    SKROW "___Ooop__Ooop___"
    SKROW "__Ooop____Ooop__"
    SKROW "__Ooop____Ooop__"
    SKROW "_Ooop______Ooop_"
    SKROWS_END
    align 8
    SKBMP fb_harness_front, fb_harness_front_rows, 16, 15, fb_pal
    ; fb_harness_back (16x15): fb_harness BACK
    SKROWS fb_harness_back_rows, 16, 15
    SKROW "_Ooop______Ooop_"
    SKROW "__Ooop____Ooop__"
    SKROW "__Ooop____Ooop__"
    SKROW "___Ooop__Ooop___"
    SKROW "____OoopOoop____"
    SKROW "_____OoOoop_____"
    SKROW "_____OUiiop_____"
    SKROW "______iPup______"
    SKROW "_____Oiuuop_____"
    SKROW "_____Ooopop_____"
    SKROW "____OoopOoop____"
    SKROW "___Ooop__Ooop___"
    SKROW "__Ooop____Ooop__"
    SKROW "__Ooop____Ooop__"
    SKROW "_Ooop______Ooop_"
    SKROWS_END
    align 8
    SKBMP fb_harness_back, fb_harness_back_rows, 16, 15, fb_pal
    ; fb_harness_right (8x15): fb_harness RIGHT
    SKROWS fb_harness_right_rows, 8, 15
    SKROW "_______o"
    SKROW "_______p"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROWS_END
    align 8
    SKBMP fb_harness_right, fb_harness_right_rows, 8, 15, fb_pal
    ; fb_harness_left (8x15): fb_harness LEFT
    SKROWS fb_harness_left_rows, 8, 15
    SKROW "o_______"
    SKROW "p_______"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROWS_END
    align 8
    SKBMP fb_harness_left, fb_harness_left_rows, 8, 15, fb_pal
    ; fb_harness_top (16x8): fb_harness TOP
    SKROWS fb_harness_top_rows, 16, 8
    SKROW "_ooo________ooo_"
    SKROW "_ooo________ooo_"
    SKROW "_ooo________ooo_"
    SKROW "_ooo________ooo_"
    SKROW "_ooo________ooo_"
    SKROW "_ooo________ooo_"
    SKROW "_ooo________ooo_"
    SKROW "_ooo________ooo_"
    SKROWS_END
    align 8
    SKBMP fb_harness_top, fb_harness_top_rows, 16, 8, fb_pal
    ; fb_harness_bottom (16x8): fb_harness BOTTOM
    SKROWS fb_harness_bottom_rows, 16, 8
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "_PPP________PPP_"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP fb_harness_bottom, fb_harness_bottom_rows, 16, 8, fb_pal
    ; fb_belt_front (16x2): fb_belt FRONT, fb_belt BACK
    SKROWS fb_belt_front_rows, 16, 2
    SKROW "OiOOiOOOOOOiOOiO"
    SKROW "pppppppppppppppp"
    SKROWS_END
    align 8
    SKBMP fb_belt_front, fb_belt_front_rows, 16, 2, fb_pal
    ; fb_belt_side (8x2): fb_belt LEFT, fb_belt RIGHT
    SKROWS fb_belt_side_rows, 8, 2
    SKROW "OOOOOOOO"
    SKROW "pppppppp"
    SKROWS_END
    align 8
    SKBMP fb_belt_side, fb_belt_side_rows, 8, 2, fb_pal
    ; fb_buckle_front (4x2): fb_buckle FRONT
    SKROWS fb_buckle_front_rows, 4, 2
    SKROW "UiiU"
    SKROW "iPPu"
    SKROWS_END
    align 8
    SKBMP fb_buckle_front, fb_buckle_front_rows, 4, 2, fb_pal
    ; fb_pouch_front (5x6): fb_pouch FRONT
    SKROWS fb_pouch_front_rows, 5, 6
    SKROW "o...P"
    SKROW "o...P"
    SKROW "o...P"
    SKROW "o...P"
    SKROW "o...P"
    SKROW "PPPPP"
    SKROWS_END
    align 8
    SKBMP fb_pouch_front, fb_pouch_front_rows, 5, 6, fb_pal
    ; fb_flap_front (5x5): fb_flap FRONT
    SKROWS fb_flap_front_rows, 5, 5
    SKROW "OOPOp"
    SKROW "O.P.p"
    SKROW "O.P.p"
    SKROW "O.I.p"
    SKROW "ppppp"
    SKROWS_END
    align 8
    SKBMP fb_flap_front, fb_flap_front_rows, 5, 5, fb_pal
    ; fb_sheath_back (11x3): fb_sheath BACK
    SKROWS fb_sheath_back_rows, 11, 3
    SKROW "IUOOOIOOYpI"
    SKROW "iioooiooyPi"
    SKROW "uupppuppypu"
    SKROWS_END
    align 8
    SKBMP fb_sheath_back, fb_sheath_back_rows, 11, 3, fb_pal
    ; fb_sheath_front (11x3): fb_sheath FRONT
    SKROWS fb_sheath_front_rows, 11, 3
    SKROW "IpYOOIOOOUI"
    SKROW "iPyooioooii"
    SKROW "upyppupppuu"
    SKROWS_END
    align 8
    SKBMP fb_sheath_front, fb_sheath_front_rows, 11, 3, fb_pal
    ; fb_sheath_top (11x2): fb_sheath TOP
    SKROWS fb_sheath_top_rows, 11, 2
    SKROW "IIOOOOOOYOI"
    SKROW "IIooooooYoI"
    SKROWS_END
    align 8
    SKBMP fb_sheath_top, fb_sheath_top_rows, 11, 2, fb_pal
    ; fb_face (16x16): fb_head FRONT
    SKROWS fb_face_rows, 16, 16
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "..JJ........bJ.."
    SKROW "....JJ....JJ.b.."
    SKROW "...WM......WMb.."
    SKROW "..wxxk....kxxwb."
    SKROW "...kk......kk.b."
    SKROW "..bb..........b."
    SKROW ".............k.."
    SKROW "....k..........."
    SKROW "...........k...."
    SKROW "...k........k..."
    SKROW "................"
    SKROWS_END
    align 8
    SKBMP fb_face, fb_face_rows, 16, 16, fb_pal
    ; fb_bandana_front (16x12): fb_bandana FRONT
    SKROWS fb_bandana_front_rows, 16, 12
    SKROW "RRRRRRRRRRRRRRRR"
    SKROW "rrrrdrrrdrrdrrrr"
    SKROW "RRRRRRRRRRRRRRRR"
    SKROW "rdrrrrdrrrrdrrrr"
    SKROW "DDDDDDDDDDDDDDDD"
    SKROW "Hh____DDDD____hH"
    SKROW "hj_____DD_____jh"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP fb_bandana_front, fb_bandana_front_rows, 16, 12, fb_pal
    ; fb_bandana_back (16x12): fb_bandana BACK
    SKROWS fb_bandana_back_rows, 16, 12
    SKROW "RRRRRRRRRRRRRRRR"
    SKROW "rrrdrrrdrrrrdrrr"
    SKROW "RRRRRRRRRRRRRRRR"
    SKROW "rrrrrrrrrrrrrrrr"
    SKROW "DDDDDDDDDDDDDDDD"
    SKROW "DDDDDDDDDDDDDDDD"
    SKROW "jjjjjjjjjjjjjjjj"
    SKROW "HhjhHjhhHhhjHhjh"
    SKROW "HjhhHhhjHhjhHjhh"
    SKROW "HJhjHhjhHjhhHhhJ"
    SKROW "J_Jh_jhJ_Jhj_Jj_"
    SKROW "___J_hJ___jJ__J_"
    SKROWS_END
    align 8
    SKBMP fb_bandana_back, fb_bandana_back_rows, 16, 12, fb_pal
    ; fb_bandana_right (16x12): fb_bandana RIGHT
    SKROWS fb_bandana_right_rows, 16, 12
    SKROW "RRRRRRRRRRRRRRRR"
    SKROW "rrrrdrrrrdrrrdrr"
    SKROW "RRRRRRRRRRRRRRRR"
    SKROW "rrrrrrrrrrrrrrrr"
    SKROW "DDDDDDDDDDDDDDDD"
    SKROW "DDDDDDDDDDDDDDDD"
    SKROW "jhhjhhjjjjjhjhjh"
    SKROW "hhjhhj______hjhj"
    SKROW "hjJhjJ_________h"
    SKROW "jJhjJh__________"
    SKROW "Jh_Jh___________"
    SKROW "h__h____________"
    SKROWS_END
    align 8
    SKBMP fb_bandana_right, fb_bandana_right_rows, 16, 12, fb_pal
    ; fb_bandana_left (16x12): fb_bandana LEFT
    SKROWS fb_bandana_left_rows, 16, 12
    SKROW "RRRRRRRRRRRRRRRR"
    SKROW "rrdrrrdrrrrdrrrr"
    SKROW "RRRRRRRRRRRRRRRR"
    SKROW "rrrrrrrrrrrrrrrr"
    SKROW "DDDDDDDDDDDDDDDD"
    SKROW "DDDDDDDDDDDDDDDD"
    SKROW "hjhjhjjjjjhhjhhj"
    SKROW "jhjh______jhhjhh"
    SKROW "h_________JjhJjh"
    SKROW "__________hJjhJj"
    SKROW "___________hJ_hJ"
    SKROW "____________h__h"
    SKROWS_END
    align 8
    SKBMP fb_bandana_left, fb_bandana_left_rows, 16, 12, fb_pal
    ; fb_bandana_top (16x16): fb_bandana TOP
    SKROWS fb_bandana_top_rows, 16, 16
    SKROW "RRRRRRRRRRRRRRRR"
    SKROW "R..............."
    SKROW "R..............."
    SKROW "R.......R......."
    SKROW "R......R........"
    SKROW "R...d......d...."
    SKROW "R....d....d....."
    SKROW "R.....d..d......"
    SKROW "R..............."
    SKROW "R..R........R..."
    SKROW "R......d........"
    SKROW "R.......d......."
    SKROW "R..............."
    SKROW "R..............."
    SKROW "R..............."
    SKROW "R..............."
    SKROWS_END
    align 8
    SKBMP fb_bandana_top, fb_bandana_top_rows, 16, 16, fb_pal
    ; fb_bandana_bottom (16x16): fb_bandana BOTTOM
    SKROWS fb_bandana_bottom_rows, 16, 16
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "_.............._"
    SKROW "_.............._"
    SKROW "_.............._"
    SKROW "_.............._"
    SKROW "_.............._"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP fb_bandana_bottom, fb_bandana_bottom_rows, 16, 16, fb_pal
    ; fb_mask_front (16x7): fb_mask FRONT
    SKROWS fb_mask_front_rows, 16, 7
    SKROW "______AAzz______"
    SKROW "____AAaaaazz____"
    SKROW "__AAaaaaaaaazz__"
    SKROW "AAaaaAazAazaaazz"
    SKROW "aaaaCaCzCaCzaaaa"
    SKROW "aaaACaCzCaCazaaa"
    SKROW "zzzzzzzzzzzzzzzz"
    SKROWS_END
    align 8
    SKBMP fb_mask_front, fb_mask_front_rows, 16, 7, fb_pal
    ; fb_mask_back (16x7): fb_mask BACK
    SKROWS fb_mask_back_rows, 16, 7
    SKROW "________________"
    SKROW "aaaaaaaazaaaaaaa"
    SKROW "_______az_______"
    SKROW "______zazz______"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP fb_mask_back, fb_mask_back_rows, 16, 7, fb_pal
    ; fb_mask_right (16x7): fb_mask RIGHT
    SKROWS fb_mask_right_rows, 16, 7
    SKROW "________________"
    SKROW "aaaaaaaaaaa__aaa"
    SKROW "___________Aaaaa"
    SKROW "___________Aaaaa"
    SKROW "___________Aaaaa"
    SKROW "___________Aaaaa"
    SKROW "___________Azzzz"
    SKROWS_END
    align 8
    SKBMP fb_mask_right, fb_mask_right_rows, 16, 7, fb_pal
    ; fb_mask_left (16x7): fb_mask LEFT
    SKROWS fb_mask_left_rows, 16, 7
    SKROW "________________"
    SKROW "aaa__aaaaaaaaaaa"
    SKROW "aaaaA___________"
    SKROW "aaaaA___________"
    SKROW "aaaaA___________"
    SKROW "aaaaA___________"
    SKROW "zzzzA___________"
    SKROWS_END
    align 8
    SKBMP fb_mask_left, fb_mask_left_rows, 16, 7, fb_pal
    ; fb_mask_top (16x16): fb_mask TOP
    SKROWS fb_mask_top_rows, 16, 16
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "a______________a"
    SKROW "a______________a"
    SKROW "a______________a"
    SKROW "aa____aaaa____aa"
    SKROWS_END
    align 8
    SKBMP fb_mask_top, fb_mask_top_rows, 16, 16, fb_pal
    ; fb_mask_bottom (16x16): fb_mask BOTTOM
    SKROWS fb_mask_bottom_rows, 16, 16
    SKROW "_zzzzzzzzzzzzzz_"
    SKROW "_zzzzzzzzzzzzzz_"
    SKROW "_zzzzzzzzzzzzzz_"
    SKROW "_zzzzzzzzzzzzzz_"
    SKROW "_zzzzzzzzzzzzzz_"
    SKROW "_zzzzzzzzzzzzzz_"
    SKROW "_zzzzzzzzzzzzzz_"
    SKROW "_zzzzzzzzzzzzzz_"
    SKROW "_zzzzzzzzzzzzzz_"
    SKROW "_zzzzzzzzzzzzzz_"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP fb_mask_bottom, fb_mask_bottom_rows, 16, 16, fb_pal
    ; fb_nose_front (2x3): fb_nose FRONT
    SKROWS fb_nose_front_rows, 2, 3
    SKROW "Ss"
    SKROW "Aa"
    SKROW "zz"
    SKROWS_END
    align 8
    SKBMP fb_nose_front, fb_nose_front_rows, 2, 3, fb_pal
    ; fb_ear (2x3): fb_ear_l LEFT, fb_ear_l RIGHT
    SKROWS fb_ear_rows, 2, 3
    SKROW "ss"
    SKROW "kk"
    SKROW "sY"
    SKROWS_END
    align 8
    SKBMP fb_ear, fb_ear_rows, 2, 3, fb_pal
    ; fb_knot_back (4x3): fb_knot BACK
    SKROWS fb_knot_back_rows, 4, 3
    SKROW "RRRR"
    SKROW ".dD."
    SKROW "dddd"
    SKROWS_END
    align 8
    SKBMP fb_knot_back, fb_knot_back_rows, 4, 3, fb_pal
    ; fb_knot_front (4x3): fb_knot FRONT
    SKROWS fb_knot_front_rows, 4, 3
    SKROW "RRRR"
    SKROW ".dD."
    SKROW "dddd"
    SKROWS_END
    align 8
    SKBMP fb_knot_front, fb_knot_front_rows, 4, 3, fb_pal
    ; fb_tail_a_back (2x8): fb_tail_a BACK
    SKROWS fb_tail_a_back_rows, 2, 8
    SKROW "Rr"
    SKROW "Rr"
    SKROW "Rr"
    SKROW "Rd"
    SKROW "Rr"
    SKROW "dr"
    SKROW "d_"
    SKROW "D_"
    SKROWS_END
    align 8
    SKBMP fb_tail_a_back, fb_tail_a_back_rows, 2, 8, fb_pal
    ; fb_tail_a_front (2x8): fb_tail_a FRONT
    SKROWS fb_tail_a_front_rows, 2, 8
    SKROW "rR"
    SKROW "rR"
    SKROW "rR"
    SKROW "dR"
    SKROW "rR"
    SKROW "rd"
    SKROW "_d"
    SKROW "_D"
    SKROWS_END
    align 8
    SKBMP fb_tail_a_front, fb_tail_a_front_rows, 2, 8, fb_pal
    ; fb_tail_b_back (3x6): fb_tail_b BACK
    SKROWS fb_tail_b_back_rows, 3, 6
    SKROW "Rrd"
    SKROW "Rrd"
    SKROW "Rrd"
    SKROW "Rrd"
    SKROW "Rd_"
    SKROW "D__"
    SKROWS_END
    align 8
    SKBMP fb_tail_b_back, fb_tail_b_back_rows, 3, 6, fb_pal
    ; fb_tail_b_front (3x6): fb_tail_b FRONT
    SKROWS fb_tail_b_front_rows, 3, 6
    SKROW "drR"
    SKROW "drR"
    SKROW "drR"
    SKROW "drR"
    SKROW "_dR"
    SKROW "__D"
    SKROWS_END
    align 8
    SKBMP fb_tail_b_front, fb_tail_b_front_rows, 3, 6, fb_pal
    ; fb_leg_front (6x24): fb_leg_l FRONT
    SKROWS fb_leg_front_rows, 6, 24
    SKROW "qqqqqq"
    SKROW "T....q"
    SKROW "T.q..q"
    SKROW "Tqqqqq"
    SKROW "TqtTqq"
    SKROW "TqTtqq"
    SKROW "Tqqqqq"
    SKROW "T....q"
    SKROW "T.q..q"
    SKROW "T..q.q"
    SKROW "qqqqqq"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROWS_END
    align 8
    SKBMP fb_leg_front, fb_leg_front_rows, 6, 24, fb_pal
    ; fb_leg_back (6x24): fb_leg_l BACK
    SKROWS fb_leg_back_rows, 6, 24
    SKROW "qqqqqq"
    SKROW "T..q.q"
    SKROW "T..q.q"
    SKROW "T..q.q"
    SKROW "T..q.q"
    SKROW "T..q.q"
    SKROW "Tqqq.q"
    SKROW "T..q.q"
    SKROW "T..q.q"
    SKROW "T....q"
    SKROW "qqqqqq"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROWS_END
    align 8
    SKBMP fb_leg_back, fb_leg_back_rows, 6, 24, fb_pal
    ; fb_leg_side (6x24): fb_leg_l LEFT, fb_leg_l RIGHT
    SKROWS fb_leg_side_rows, 6, 24
    SKROW "qqqqqq"
    SKROW "T....q"
    SKROW "T.q..q"
    SKROW "T....q"
    SKROW "T.q..q"
    SKROW "T....q"
    SKROW "T.q..q"
    SKROW "T....q"
    SKROW "T.q..q"
    SKROW "T....q"
    SKROW "qqqqqq"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROW "T....q"
    SKROWS_END
    align 8
    SKBMP fb_leg_side, fb_leg_side_rows, 6, 24, fb_pal
    ; fb_wrap_front (7x8): fb_wrap_l FRONT
    SKROWS fb_wrap_front_rows, 7, 8
    SKROW "GGGGGGG"
    SKROW "ggggggg"
    SKROW "gnnnGgg"
    SKROW "nnnGggn"
    SKROW "nnGggnn"
    SKROW "nGggnnn"
    SKROW "GggnnnG"
    SKROW "NNNNNNN"
    SKROWS_END
    align 8
    SKBMP fb_wrap_front, fb_wrap_front_rows, 7, 8, fb_pal
    ; fb_wrap_back (7x8): fb_wrap_l BACK
    SKROWS fb_wrap_back_rows, 7, 8
    SKROW "GGGGGGG"
    SKROW "ggggggg"
    SKROW "nGggnnn"
    SKROW "GggnnnG"
    SKROW "ggnnnGg"
    SKROW "gnnnGgg"
    SKROW "nnnGggn"
    SKROW "NNNNNNN"
    SKROWS_END
    align 8
    SKBMP fb_wrap_back, fb_wrap_back_rows, 7, 8, fb_pal
    ; fb_wrap_left (8x8): fb_wrap_l LEFT
    SKROWS fb_wrap_left_rows, 8, 8
    SKROW "GGGGGGGG"
    SKROW "gggggggg"
    SKROW "nnnGggnn"
    SKROW "nnGggnnn"
    SKROW "nGggnnnG"
    SKROW "GggnnnGg"
    SKROW "ggnnnGgg"
    SKROW "NNNNNNNN"
    SKROWS_END
    align 8
    SKBMP fb_wrap_left, fb_wrap_left_rows, 8, 8, fb_pal
    ; fb_wrap_right (8x8): fb_wrap_l RIGHT
    SKROWS fb_wrap_right_rows, 8, 8
    SKROW "GGGGGGGG"
    SKROW "gggggggg"
    SKROW "ggnnnGgg"
    SKROW "gnnnGggn"
    SKROW "nnnGggnn"
    SKROW "nnGggnnn"
    SKROW "nGggnnnG"
    SKROW "NNNNNNNN"
    SKROWS_END
    align 8
    SKBMP fb_wrap_right, fb_wrap_right_rows, 8, 8, fb_pal
    ; fb_foot_top (7x10): fb_foot_l TOP
    SKROWS fb_foot_top_rows, 7, 10
    SKROW "ppppppp"
    SKROW "......O"
    SKROW "......O"
    SKROW "......O"
    SKROW "......O"
    SKROW "......O"
    SKROW "......O"
    SKROW "ppppppp"
    SKROW "ooooooo"
    SKROW "OOOOOOO"
    SKROWS_END
    align 8
    SKBMP fb_foot_top, fb_foot_top_rows, 7, 10, fb_pal
    ; fb_foot_sole (7x10): fb_foot_l BOTTOM
    SKROWS fb_foot_sole_rows, 7, 10
    SKROW "......."
    SKROW "PPPPPPP"
    SKROW "......."
    SKROW "......."
    SKROW "PPPPPPP"
    SKROW "......."
    SKROW "......."
    SKROW "PPPPPPP"
    SKROW "......."
    SKROW "......."
    SKROWS_END
    align 8
    SKBMP fb_foot_sole, fb_foot_sole_rows, 7, 10, fb_pal
    ; fb_hand_front (6x22): fb_arm_l FRONT
    SKROWS fb_hand_front_rows, 6, 22
    SKROW "FFFFFF"
    SKROW "F....v"
    SKROW "F....v"
    SKROW "Fv...v"
    SKROW "F.v..v"
    SKROW "F..v.v"
    SKROW "F....v"
    SKROW "F....v"
    SKROW "F....v"
    SKROW "F....v"
    SKROW "kkkkkk"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "PPPPPP"
    SKROW "OoOOop"
    SKROW "Ooooop"
    SKROW "pppppp"
    SKROW "SSsksk"
    SKROWS_END
    align 8
    SKBMP fb_hand_front, fb_hand_front_rows, 6, 22, fb_pal
    ; fb_hand_back (6x22): fb_arm_l BACK
    SKROWS fb_hand_back_rows, 6, 22
    SKROW "FFFFFF"
    SKROW "F....v"
    SKROW "F....v"
    SKROW "F....v"
    SKROW "Fv...v"
    SKROW "F.v..v"
    SKROW "F..v.v"
    SKROW "F....v"
    SKROW "F....v"
    SKROW "F....v"
    SKROW "kkkkkk"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "PPPPPP"
    SKROW "Ooooop"
    SKROW "Ooooop"
    SKROW "pppppp"
    SKROW "SSsksk"
    SKROWS_END
    align 8
    SKBMP fb_hand_back, fb_hand_back_rows, 6, 22, fb_pal
    ; fb_hand_side (6x22): fb_arm_l LEFT, fb_arm_l RIGHT
    SKROWS fb_hand_side_rows, 6, 22
    SKROW "FFFFFF"
    SKROW "F....v"
    SKROW "F....v"
    SKROW "F....v"
    SKROW "F.v..v"
    SKROW "F....v"
    SKROW "F....v"
    SKROW "F....v"
    SKROW "F....v"
    SKROW "F....v"
    SKROW "kkkkkk"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "PPPPPP"
    SKROW "Ooooop"
    SKROW "Ooooop"
    SKROW "pppppp"
    SKROW "SSsksk"
    SKROWS_END
    align 8
    SKBMP fb_hand_side, fb_hand_side_rows, 6, 22, fb_pal
    ; fb_bracer_front (6x4): fb_bracer_l FRONT
    SKROWS fb_bracer_front_rows, 6, 4
    SKROW "OOOOOp"
    SKROW "Ooooip"
    SKROW "Oppppp"
    SKROW "OPPPPp"
    SKROWS_END
    align 8
    SKBMP fb_bracer_front, fb_bracer_front_rows, 6, 4, fb_pal
    ; fb_bracer_back (6x4): fb_bracer_l BACK
    SKROWS fb_bracer_back_rows, 6, 4
    SKROW "OOOOOp"
    SKROW "Ooooop"
    SKROW "Oppppp"
    SKROW "OPPPPp"
    SKROWS_END
    align 8
    SKBMP fb_bracer_back, fb_bracer_back_rows, 6, 4, fb_pal
    ; fb_bracer_left (6x4): fb_bracer_l LEFT
    SKROWS fb_bracer_left_rows, 6, 4
    SKROW "OOOOOp"
    SKROW "Ooooop"
    SKROW "Oppppp"
    SKROW "OPPPPp"
    SKROWS_END
    align 8
    SKBMP fb_bracer_left, fb_bracer_left_rows, 6, 4, fb_pal
    ; fb_bracer_right (6x4): fb_bracer_l RIGHT
    SKROWS fb_bracer_right_rows, 6, 4
    SKROW "OOOOOp"
    SKROW "Ooooop"
    SKROW "Oppppp"
    SKROW "OPPPPp"
    SKROWS_END
    align 8
    SKBMP fb_bracer_right, fb_bracer_right_rows, 6, 4, fb_pal
    ; fb_fist_front (6x5): fb_fist_l FRONT
    SKROWS fb_fist_front_rows, 6, 5
    SKROW "PPPPPP"
    SKROW "OOoOop"
    SKROW "Opopop"
    SKROW "opopop"
    SKROW "SkSksk"
    SKROWS_END
    align 8
    SKBMP fb_fist_front, fb_fist_front_rows, 6, 5, fb_pal
    ; fb_fist_back (6x5): fb_fist_l BACK
    SKROWS fb_fist_back_rows, 6, 5
    SKROW "PPPPPP"
    SKROW "OOoooo"
    SKROW "Opoopo"
    SKROW "opoppo"
    SKROW "SksksK"
    SKROWS_END
    align 8
    SKBMP fb_fist_back, fb_fist_back_rows, 6, 5, fb_pal
    ; fb_fist_right (6x5): fb_fist_l RIGHT
    SKROWS fb_fist_right_rows, 6, 5
    SKROW "PPPPPP"
    SKROW "OooopS"
    SKROW "OooopS"
    SKROW "oooppk"
    SKROW "SkSkkk"
    SKROWS_END
    align 8
    SKBMP fb_fist_right, fb_fist_right_rows, 6, 5, fb_pal
    ; fb_fist_left (6x5): fb_fist_l LEFT
    SKROWS fb_fist_left_rows, 6, 5
    SKROW "PPPPPP"
    SKROW "SpoooO"
    SKROW "SpoooO"
    SKROW "kpoooo"
    SKROW "kkkSkS"
    SKROWS_END
    align 8
    SKBMP fb_fist_left, fb_fist_left_rows, 6, 5, fb_pal

section .data
SKMODEL_BEGIN m_folk_bandits, 32, 0, 11, 26, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART fb_torso, -8, 24, -4, 16, 22, 8, 0, 0              ; dark leather jerkin over a faded red shirt
    PART fb_harness, -8, 31, -4, 16, 15, 8, 6, SKPF_CUTOUT  ; crossed leather straps over the shoulders
    PART fb_belt, -8, 28, -4, 16, 2, 8, 4, 0                ; two-row belt overlay
    PART fb_buckle, -2, 28, -5, 4, 2, 1, 0, 0               ; iron buckle
    PART fb_pouch, -7, 23, -7, 5, 6, 3, 0, 0                ; belt pouch at the left hip
    PART fb_flap, -7, 25, -8, 5, 5, 1, 0, 0                 ; its flap with a strap
    PART fb_sheath, -5, 25, 4, 11, 3, 2, 0, 0               ; short blade across the small of the back
    SKBONE BK_HEAD, 0, 0, 0.00
    PART fb_head, -8, 46, -8, 16, 16, 16, 0, 0              ; the 16 texel head
    PART fb_bandana, -8, 50, -8, 16, 12, 16, 4, SKPF_CUTOUT ; red bandana over the crown, hair below it
    PART fb_mask, -8, 46, -8, 16, 7, 16, 6, SKPF_CUTOUT     ; black cloth mask over the lower face, ear loops
    PART fb_nose, -1, 50, -10, 2, 3, 2, 0, 0                ; nose under the cloth
    PART fb_ear_l, -9, 52, -1, 1, 3, 2, 0, 0                ; ear with a ring (the right one shares its skin)
    PART_AS fb_ear_r, fb_ear_l, 8, 52, -1, 0, 0
    PART fb_knot, -2, 56, 8, 4, 3, 2, 0, 0                  ; bandana knot at the back
    PART fb_tail_a, -3, 49, 9, 2, 8, 1, 0, SKPF_CUTOUT      ; left knot tail (pointed)
    PART fb_tail_b, 0, 51, 9, 3, 6, 1, 0, SKPF_CUTOUT       ; right knot tail (pointed)
    SKBONE BK_LLEG, 24, 0, 1.00
    PART fb_leg_l, -6, 0, -3, 6, 24, 6, 0, 0                ; grey trousers
    PART fb_wrap_l, -7, 3, -4, 7, 8, 8, 0, 0                ; cloth wraps up the calf
    PART fb_foot_l, -7, 0, -6, 7, 3, 10, 0, 0               ; boot foot: toe cap, sole
    SKBONE BK_RLEG, 24, 0, -1.00
    PART_AS fb_leg_r, fb_leg_l, 0, 0, -3, 0, 0
    PART_AS fb_wrap_r, fb_wrap_l, 0, 3, -4, 0, 0
    PART_AS fb_foot_r, fb_foot_l, 0, 0, -6, 0, 0
    SKBONE BK_LARM, 44, 0, -1.00
    PART fb_arm_l, -14, 24, -3, 6, 22, 6, 0, 0              ; red shirt sleeve, bare forearm, fingerless glove
    PART fb_cuff_l, -14, 36, -3, 6, 3, 6, 10, 0             ; rolled shirt cuff at the elbow
    PART fb_bracer_l, -14, 29, -3, 6, 4, 6, 6, 0            ; leather bracer
    PART fb_fist_l, -14, 24, -3, 6, 5, 6, 8, 0              ; fingerless glove: a clenched fist
    SKBONE BK_RARM, 44, 0, 1.00
    PART_AS fb_arm_r, fb_arm_l, 8, 24, -3, 0, 0
    PART_AS fb_cuff_r, fb_cuff_l, 8, 36, -3, 10, 0
    PART_AS fb_bracer_r, fb_bracer_l, 8, 29, -3, 6, 0
    PART_AS fb_fist_r, fb_fist_l, 8, 24, -3, 8, 0
SKMODEL_PAINT
    ; --- fb_torso: dark leather jerkin, V neck showing the shirt, lace-up, panel seams, mends, hem
    SK_FILL fb_torso, SKM_ALL, FB_LEATHER_2, 7
    SK_BMP fb_torso, SKF_FRONT, 0, 0, fb_torso_front
    SK_BMP fb_torso, SKF_BACK, 0, 0, fb_torso_back
    SK_BMP fb_torso, SKF_RIGHT, 0, 0, fb_torso_side
    SK_BMP fb_torso, SKF_LEFT, 0, 0, fb_torso_side
    SK_RECT fb_torso, SKF_BOTTOM, 0, 0, 16, 8, FB_SHIRT_4, 0
    SK_GRAD fb_torso, SKM_SIDES, 272, 224
    ; --- fb_harness: two crossed leather straps over the shoulders and an iron ring (cutout overlay)
    SK_FILL fb_harness, SKM_ALL, AC_LEATHER_2, 7
    SK_BMP fb_harness, SKF_FRONT, 0, 0, fb_harness_front
    SK_BMP fb_harness, SKF_BACK, 0, 0, fb_harness_back
    SK_BMP fb_harness, SKF_RIGHT, 0, 0, fb_harness_right
    SK_BMP fb_harness, SKF_LEFT, 0, 0, fb_harness_left
    SK_BMP fb_harness, SKF_TOP, 0, 0, fb_harness_top
    SK_BMP fb_harness, SKF_BOTTOM, 0, 0, fb_harness_bottom
    ; --- fb_belt: strap leather with rivets; fb_buckle: an iron frame
    SK_FILL fb_belt, SKM_ALL, AC_LEATHER_2, 7
    SK_BMP fb_belt, SKF_FRONT, 0, 0, fb_belt_front
    SK_BMP fb_belt, SKF_BACK, 0, 0, fb_belt_front
    SK_BMP fb_belt, SKF_LEFT, 0, 0, fb_belt_side
    SK_BMP fb_belt, SKF_RIGHT, 0, 0, fb_belt_side
    SK_RECT fb_belt, SKF_TOP, 0, 0, 16, 8, AC_LEATHER_1, 0
    SK_RECT fb_belt, SKF_BOTTOM, 0, 0, 16, 8, AC_LEATHER_4, 0
    SK_FILL fb_buckle, SKM_ALL, AC_IRON_3, 0
    SK_BMP fb_buckle, SKF_FRONT, 0, 0, fb_buckle_front
    ; --- fb_pouch and fb_flap: stitched leather, a strap and buckle; fb_sheath: scabbard, guard and grip (back view, hilt to the right)
    SK_FILL fb_pouch, SKM_ALL, AC_LEATHER_3, 15
    SK_BMP fb_pouch, SKF_FRONT, 0, 0, fb_pouch_front
    SK_RECT fb_pouch, SKF_TOP, 0, 0, 5, 3, AC_LEATHER_2, 0
    SK_RECT fb_pouch, SKF_BOTTOM, 0, 0, 5, 3, AC_LEATHER_4, 0
    SK_GRAD fb_pouch, SKM_SIDES, 272, 224
    SK_FILL fb_flap, SKM_ALL, AC_LEATHER_2, 7
    SK_BMP fb_flap, SKF_FRONT, 0, 0, fb_flap_front
    SK_RECT fb_flap, SKF_TOP, 0, 0, 5, 1, AC_LEATHER_1, 0
    SK_RECT fb_flap, SKF_BOTTOM, 0, 0, 5, 1, AC_LEATHER_4, 0
    SK_FILL fb_sheath, SKM_ALL, AC_LEATHER_2, 7
    SK_BMP fb_sheath, SKF_BACK, 0, 0, fb_sheath_back
    SK_BMP fb_sheath, SKF_FRONT, 0, 0, fb_sheath_front
    SK_BMP fb_sheath, SKF_TOP, 0, 0, fb_sheath_top
    SK_RECT fb_sheath, SKF_BOTTOM, 0, 0, 11, 2, AC_LEATHER_4, 0
    SK_RECT fb_sheath, SKF_LEFT, 0, 0, 2, 3, AC_IRON_2, 0
    SK_RECT fb_sheath, SKF_RIGHT, 0, 0, 2, 3, AC_IRON_3, 0
    ; --- fb_head: narrow hard eyes under heavy brows, a scar, stubble (the mask and the bandana cover the rest)
    SK_FILL fb_head, SKM_ALL, FB_SKIN_2, 15
    SK_GRAD fb_head, SKM_SIDES, 272, 224
    SK_RECT fb_head, SKF_TOP, 0, 0, 16, 16, FB_RED_2, 15
    SK_RECT fb_head, SKF_BACK, 0, 0, 16, 5, FB_RED_2, 15
    SK_RECT fb_head, SKF_BACK, 0, 5, 16, 9, FB_HAIR_2, 15
    SK_RECT fb_head, SKF_RIGHT, 0, 0, 16, 5, FB_RED_2, 15
    SK_RECT fb_head, SKF_LEFT, 0, 0, 16, 5, FB_RED_2, 15
    SK_RECT fb_head, SKF_BOTTOM, 0, 0, 16, 16, FB_SKIN_4, 0
    SK_BMP fb_head, SKF_FRONT, 0, 0, fb_face
    ; --- fb_bandana: red cloth over the crown (a fold, creases), a darker lower edge, hair spilling below (cutout)
    SK_FILL fb_bandana, SKM_ALL, FB_RED_2, 15
    SK_GRAD fb_bandana, SKM_SIDES, 272, 224
    SK_BMP fb_bandana, SKF_FRONT, 0, 0, fb_bandana_front
    SK_BMP fb_bandana, SKF_BACK, 0, 0, fb_bandana_back
    SK_BMP fb_bandana, SKF_RIGHT, 0, 0, fb_bandana_right
    SK_BMP fb_bandana, SKF_LEFT, 0, 0, fb_bandana_left
    SK_BMP fb_bandana, SKF_TOP, 0, 0, fb_bandana_top
    SK_BMP fb_bandana, SKF_BOTTOM, 0, 0, fb_bandana_bottom
    ; --- fb_mask: black cloth over the lower face, a V over the nose, folds, a stitched grin; a strap round the ears (cutout)
    SK_FILL fb_mask, SKM_ALL, FB_CLOTH_2, 7
    SK_BMP fb_mask, SKF_FRONT, 0, 0, fb_mask_front
    SK_BMP fb_mask, SKF_BACK, 0, 0, fb_mask_back
    SK_BMP fb_mask, SKF_RIGHT, 0, 0, fb_mask_right
    SK_BMP fb_mask, SKF_LEFT, 0, 0, fb_mask_left
    SK_BMP fb_mask, SKF_TOP, 0, 0, fb_mask_top
    SK_BMP fb_mask, SKF_BOTTOM, 0, 0, fb_mask_bottom
    ; --- fb_nose (the cloth tents over it), fb_ear_l (shared with fb_ear_r)
    SK_FILL fb_nose, SKM_ALL, FB_CLOTH_2, 7
    SK_BMP fb_nose, SKF_FRONT, 0, 0, fb_nose_front
    SK_RECT fb_nose, SKF_TOP, 0, 0, 2, 2, FB_SKIN_1, 0
    SK_RECT fb_nose, SKF_BOTTOM, 0, 0, 2, 2, FB_CLOTH_4, 0
    SK_RECT fb_nose, SKF_LEFT, 0, 0, 2, 1, FB_SKIN_2, 0
    SK_RECT fb_nose, SKF_RIGHT, 0, 0, 2, 1, FB_SKIN_2, 0
    SK_FILL fb_ear_l, SKM_ALL, FB_SKIN_2, 7
    SK_BMP fb_ear_l, SKF_LEFT, 0, 0, fb_ear
    SK_BMP fb_ear_l, SKF_RIGHT, 0, 0, fb_ear
    ; --- fb_knot, fb_tail_a, fb_tail_b: the knotted ends of the bandana
    SK_FILL fb_knot, SKM_ALL, FB_RED_2, 7
    SK_BMP fb_knot, SKF_BACK, 0, 0, fb_knot_back
    SK_BMP fb_knot, SKF_FRONT, 0, 0, fb_knot_front
    SK_RECT fb_knot, SKF_TOP, 0, 0, 4, 2, FB_RED_1, 0
    SK_RECT fb_knot, SKF_BOTTOM, 0, 0, 4, 2, FB_RED_4, 0
    SK_GRAD fb_knot, SKM_SIDES, 272, 224
    SK_FILL fb_tail_a, SKM_ALL, FB_RED_2, 7
    SK_BMP fb_tail_a, SKF_BACK, 0, 0, fb_tail_a_back
    SK_BMP fb_tail_a, SKF_FRONT, 0, 0, fb_tail_a_front
    SK_RECT fb_tail_a, SKF_LEFT, 0, 0, 1, 7, FB_RED_3, 0
    SK_RECT fb_tail_a, SKF_RIGHT, 0, 0, 1, 7, FB_RED_3, 0
    SK_FILL fb_tail_b, SKM_ALL, FB_RED_2, 7
    SK_BMP fb_tail_b, SKF_BACK, 0, 0, fb_tail_b_back
    SK_BMP fb_tail_b, SKF_FRONT, 0, 0, fb_tail_b_front
    SK_RECT fb_tail_b, SKF_LEFT, 0, 0, 1, 5, FB_RED_3, 0
    SK_RECT fb_tail_b, SKF_RIGHT, 0, 0, 1, 5, FB_RED_3, 0
    ; --- fb_leg_l (shared with fb_leg_r): grey trousers (the wraps cover the calf); fb_wrap_l; fb_foot_l
    SK_FILL fb_leg_l, SKM_ALL, FB_PANTS_2, 15
    SK_BMP fb_leg_l, SKF_FRONT, 0, 0, fb_leg_front
    SK_BMP fb_leg_l, SKF_BACK, 0, 0, fb_leg_back
    SK_BMP fb_leg_l, SKF_LEFT, 0, 0, fb_leg_side
    SK_BMP fb_leg_l, SKF_RIGHT, 0, 0, fb_leg_side
    SK_RECT fb_leg_l, SKF_BOTTOM, 0, 0, 6, 6, FB_PANTS_4, 0
    SK_GRAD fb_leg_l, SKM_SIDES, 272, 224
    ;     fb_wrap_l: cloth strips wound up the calf in slanting bands
    SK_FILL fb_wrap_l, SKM_ALL, FB_WRAP_2, 15
    SK_BMP fb_wrap_l, SKF_FRONT, 0, 0, fb_wrap_front
    SK_BMP fb_wrap_l, SKF_BACK, 0, 0, fb_wrap_back
    SK_BMP fb_wrap_l, SKF_LEFT, 0, 0, fb_wrap_left
    SK_BMP fb_wrap_l, SKF_RIGHT, 0, 0, fb_wrap_right
    SK_RECT fb_wrap_l, SKF_TOP, 0, 0, 7, 8, FB_WRAP_1, 15
    SK_RECT fb_wrap_l, SKF_BOTTOM, 0, 0, 7, 8, FB_WRAP_4, 0
    SK_GRAD fb_wrap_l, SKM_SIDES, 272, 224
    SK_FILL fb_foot_l, SKM_ALL, AC_LEATHER_2, 15
    SK_BMP fb_foot_l, SKF_TOP, 0, 0, fb_foot_top
    SK_RECT fb_foot_l, SKF_FRONT, 0, 0, 7, 1, AC_LEATHER_1, 0
    SK_RECT fb_foot_l, SKF_FRONT, 0, 2, 7, 1, AC_LEATHER_4, 0
    SK_RECT fb_foot_l, SKF_BACK, 0, 0, 7, 1, AC_LEATHER_3, 0
    SK_RECT fb_foot_l, SKF_BACK, 0, 2, 7, 1, AC_LEATHER_4, 0
    SK_RECT fb_foot_l, SKF_LEFT, 0, 0, 10, 1, AC_LEATHER_1, 0
    SK_RECT fb_foot_l, SKF_LEFT, 0, 2, 10, 1, AC_LEATHER_4, 0
    SK_RECT fb_foot_l, SKF_RIGHT, 0, 0, 10, 1, AC_LEATHER_2, 0
    SK_RECT fb_foot_l, SKF_RIGHT, 0, 2, 10, 1, AC_LEATHER_4, 0
    SK_RECT fb_foot_l, SKF_BOTTOM, 0, 0, 7, 10, AC_LEATHER_4, 0
    SK_BMP fb_foot_l, SKF_BOTTOM, 0, 0, fb_foot_sole
    ; --- fb_arm_l (shared with fb_arm_r): shirt sleeve to row 9, bare forearm, a fingerless glove and knuckles
    SK_FILL fb_arm_l, SKM_ALL, FB_SKIN_2, 15
    SK_RECT fb_arm_l, SKF_FRONT, 0, 0, 6, 10, FB_SHIRT_2, 15
    SK_RECT fb_arm_l, SKF_BACK, 0, 0, 6, 10, FB_SHIRT_2, 15
    SK_RECT fb_arm_l, SKF_LEFT, 0, 0, 6, 10, FB_SHIRT_2, 15
    SK_RECT fb_arm_l, SKF_RIGHT, 0, 0, 6, 10, FB_SHIRT_2, 15
    SK_RECT fb_arm_l, SKF_TOP, 0, 0, 6, 6, FB_SHIRT_2, 15
    SK_BMP fb_arm_l, SKF_FRONT, 0, 0, fb_hand_front
    SK_BMP fb_arm_l, SKF_BACK, 0, 0, fb_hand_back
    SK_BMP fb_arm_l, SKF_LEFT, 0, 0, fb_hand_side
    SK_BMP fb_arm_l, SKF_RIGHT, 0, 0, fb_hand_side
    SK_RECT fb_arm_l, SKF_BOTTOM, 0, 0, 6, 6, FB_SKIN_3, 0
    SK_GRAD fb_arm_l, SKM_SIDES, 272, 224
    SK_FILL fb_cuff_l, SKM_ALL, FB_SHIRT_1, 15
    SK_RECT fb_cuff_l, SKF_FRONT, 0, 2, 6, 1, FB_SHIRT_3, 0
    SK_RECT fb_cuff_l, SKF_FRONT, 0, 0, 6, 1, FB_SHIRT_1, 0
    SK_RECT fb_cuff_l, SKF_FRONT, 0, 1, 1, 1, FB_SHIRT_1, 0
    SK_RECT fb_cuff_l, SKF_BACK, 0, 2, 6, 1, FB_SHIRT_3, 0
    SK_RECT fb_cuff_l, SKF_BACK, 0, 0, 6, 1, FB_SHIRT_1, 0
    SK_RECT fb_cuff_l, SKF_BACK, 0, 1, 1, 1, FB_SHIRT_1, 0
    SK_RECT fb_cuff_l, SKF_LEFT, 0, 2, 6, 1, FB_SHIRT_3, 0
    SK_RECT fb_cuff_l, SKF_LEFT, 0, 0, 6, 1, FB_SHIRT_1, 0
    SK_RECT fb_cuff_l, SKF_LEFT, 0, 1, 1, 1, FB_SHIRT_1, 0
    SK_RECT fb_cuff_l, SKF_RIGHT, 0, 2, 6, 1, FB_SHIRT_3, 0
    SK_RECT fb_cuff_l, SKF_RIGHT, 0, 0, 6, 1, FB_SHIRT_1, 0
    SK_RECT fb_cuff_l, SKF_RIGHT, 0, 1, 1, 1, FB_SHIRT_1, 0
    SK_RECT fb_cuff_l, SKF_BOTTOM, 0, 0, 6, 6, FB_SHIRT_4, 0
    SK_FILL fb_bracer_l, SKM_ALL, AC_LEATHER_2, 15
    SK_BMP fb_bracer_l, SKF_FRONT, 0, 0, fb_bracer_front
    SK_BMP fb_bracer_l, SKF_BACK, 0, 0, fb_bracer_back
    SK_BMP fb_bracer_l, SKF_LEFT, 0, 0, fb_bracer_left
    SK_BMP fb_bracer_l, SKF_RIGHT, 0, 0, fb_bracer_right
    SK_RECT fb_bracer_l, SKF_TOP, 0, 0, 6, 6, AC_LEATHER_1, 0
    SK_RECT fb_bracer_l, SKF_BOTTOM, 0, 0, 6, 6, AC_LEATHER_4, 0
    ; --- fb_fist_l (shared with fb_fist_r): the glove as a fist: a strap, knuckles, finger gaps, bare fingertips, a thumb on each side
    SK_FILL fb_fist_l, SKM_ALL, AC_LEATHER_2, 7
    SK_BMP fb_fist_l, SKF_FRONT, 0, 0, fb_fist_front
    SK_BMP fb_fist_l, SKF_BACK, 0, 0, fb_fist_back
    SK_BMP fb_fist_l, SKF_RIGHT, 0, 0, fb_fist_right
    SK_BMP fb_fist_l, SKF_LEFT, 0, 0, fb_fist_left
    SK_RECT fb_fist_l, SKF_TOP, 0, 0, 6, 6, AC_LEATHER_1, 0
    SK_RECT fb_fist_l, SKF_BOTTOM, 0, 0, 6, 6, FB_SKIN_3, 0
    SK_GRAD fb_fist_l, SKM_SIDES, 272, 224
SKMODEL_END

; ===================================================================================================
; m_folk_cult
; ===================================================================================================
RAMP FC_SKIN, 190, 185, 180             ; pale skin (the factions table)
RAMP FC_ASH, 70, 65, 70                 ; ash hood, mantle, stole
RAMP FC_ROBE, 50, 45, 50                ; charcoal robe
RAMP FC_SKIRT, 45, 40, 45               ; charcoal skirt
RAMP FC_RED, 168, 28, 32                ; ritual red trim
RAMP FC_ROPE, 122, 96, 66               ; hemp sash

section .rodata
; The characters of every fc_ bitmap. Groups: base, highlight, shade, deep.
;   s S k K pale skin (q ash smudge)   a A z Z ash grey (hood, mantle, stole)   r R d D charcoal robe
;   t T u U charcoal skirt (legs)   e E f F ritual red   p P o O rope (hemp)   g G h H gold (AC)
;   l L m M glowing eyes: l core, L hot, m ring, M socket   j glow halo   n ember   B W rim lights (ash, robe)
;   x dark   c cream   _ transparent
align 8
fc_pal:
    PALC 's', FC_SKIN_2
    PALC 'S', FC_SKIN_1
    PALC 'k', FC_SKIN_3
    PALC 'K', FC_SKIN_4
    PALC 'q', RGBO(98, 92, 98)
    PALC 'a', FC_ASH_2
    PALC 'A', FC_ASH_1
    PALC 'z', FC_ASH_3
    PALC 'Z', FC_ASH_4
    PALC 'r', FC_ROBE_2
    PALC 'R', FC_ROBE_1
    PALC 'd', FC_ROBE_3
    PALC 'D', FC_ROBE_4
    PALC 't', FC_SKIRT_2
    PALC 'T', FC_SKIRT_1
    PALC 'u', FC_SKIRT_3
    PALC 'U', FC_SKIRT_4
    PALC 'e', FC_RED_2
    PALC 'E', FC_RED_1
    PALC 'f', FC_RED_3
    PALC 'F', FC_RED_4
    PALC 'p', FC_ROPE_2
    PALC 'P', FC_ROPE_1
    PALC 'o', FC_ROPE_3
    PALC 'O', FC_ROPE_4
    PALC 'g', AC_GOLD_2
    PALC 'G', AC_GOLD_1
    PALC 'h', AC_GOLD_3
    PALC 'H', AC_GOLD_4
    PALC 'l', RGBO(255, 84, 56)
    PALC 'L', RGBO(255, 206, 110)
    PALC 'm', RGBO(188, 30, 36)
    PALC 'M', RGBO(54, 14, 24)
    PALC 'x', RGBO(24, 16, 22)
    PALC 'c', RGBO(220, 212, 200)
    PALC 'B', RGBO(124, 116, 128)
    PALC 'W', RGBO(98, 90, 102)
    PALC 'j', RGBO(214, 128, 124)
    PALC 'n', RGBO(255, 132, 52)
    PALT '_'
    dq 0

    ; fc_torso_front (16x22): fc_torso FRONT
    SKROWS fc_torso_front_rows, 16, 22
    SKROW "R..............."
    SKROW "R..............."
    SKROW "R..............."
    SKROW "R.d..........d.."
    SKROW "R.d..........dW."
    SKROW "RWd..........d.."
    SKROW "RWd..........d.W"
    SKROW "R.d..........d.."
    SKROW "RWd..........d.."
    SKROW "RWd..........dW."
    SKROW "R.d..........d.."
    SKROW "RWd........W.d.."
    SKROW "RWd..........d.."
    SKROW "RWd..........d.."
    SKROW "RWdW..W......dW."
    SKROW "RWd..........d.."
    SKROW "R.d..........d.."
    SKROW "RWd..........d.."
    SKROW "RWd.....W....d.."
    SKROW "R.d..........d.."
    SKROW "R..............."
    SKROW "R..............."
    SKROWS_END
    align 8
    SKBMP fc_torso_front, fc_torso_front_rows, 16, 22, fc_pal
    ; fc_torso_back (16x22): fc_torso BACK
    SKROWS fc_torso_back_rows, 16, 22
    SKROW "R..............."
    SKROW "R..............."
    SKROW "R..............."
    SKROW "R.d....d.....d.."
    SKROW "R.d....dW....d.."
    SKROW "R.dW...d.....d.."
    SKROW "R.d....dW....d.."
    SKROW "R.d..W.d...W.dW."
    SKROW "R.d....dW....d.."
    SKROW "R.dW...d.....d.."
    SKROW "R.d....d.....dW."
    SKROW "R.d....d.....d.."
    SKROW "R.d....dW....d.."
    SKROW "R.dW...d.....dW."
    SKROW "R.d....d.....d.."
    SKROW "R.d....d.....d.."
    SKROW "R.d....dW.W..dW."
    SKROW "R.dW...d.....d.."
    SKROW "R.d....d....Wd.."
    SKROW "R.d.W..d.....dW."
    SKROW "R..............."
    SKROW "R..............."
    SKROWS_END
    align 8
    SKBMP fc_torso_back, fc_torso_back_rows, 16, 22, fc_pal
    ; fc_torso_side (8x22): fc_torso RIGHT, fc_torso LEFT
    SKROWS fc_torso_side_rows, 8, 22
    SKROW "........"
    SKROW "........"
    SKROW "..d..R.."
    SKROW "..d..R.."
    SKROW "..d..R.."
    SKROW "..d..R.."
    SKROW "..d..R.."
    SKROW "..d..R.."
    SKROW "..d..R.."
    SKROW "..d..R.."
    SKROW "..d..R.."
    SKROW "..d..R.."
    SKROW "..d..R.."
    SKROW "..d..R.."
    SKROW "..d..R.."
    SKROW "..d..R.."
    SKROW "..d..R.."
    SKROW "..d..R.."
    SKROW "..d..R.."
    SKROW "..d..R.."
    SKROW "..d..R.."
    SKROW "..d..R.."
    SKROWS_END
    align 8
    SKBMP fc_torso_side, fc_torso_side_rows, 8, 22, fc_pal
    ; fc_stole_front (8x22): fc_stole FRONT
    SKROWS fc_stole_front_rows, 8, 22
    SKROW "eB.....f"
    SKROW "eB.....f"
    SKROW "eB.....f"
    SKROW "eB.....f"
    SKROW "eg....gf"
    SKROW "eg....gf"
    SKROW "eBg..g.f"
    SKROW "eBg..g.f"
    SKROW "eBgggg.f"
    SKROW "eB.....f"
    SKROW "eB.....f"
    SKROW "eB.....f"
    SKROW "eB..z..f"
    SKROW "eB.....f"
    SKROW "eB.....f"
    SKROW "eB..z..f"
    SKROW "eB.....f"
    SKROW "eB.....f"
    SKROW "eB..z..f"
    SKROW "ez.z.z.f"
    SKROW "eeeeeeee"
    SKROW "FFFFFFFF"
    SKROWS_END
    align 8
    SKBMP fc_stole_front, fc_stole_front_rows, 8, 22, fc_pal
    ; fc_stole_back (8x22): fc_stole BACK
    SKROWS fc_stole_back_rows, 8, 22
    SKROW "eB.....f"
    SKROW "eB.....f"
    SKROW "eB.....f"
    SKROW "eB.....f"
    SKROW "eB.....f"
    SKROW "eB.z...f"
    SKROW "eB.....f"
    SKROW "eB.e...f"
    SKROW "eB.eE..f"
    SKROW "eB.eEe.f"
    SKROW "eBeELe.f"
    SKROW "eBeELe.f"
    SKROW "eBeEEz.f"
    SKROW "eB.ee..f"
    SKROW "eB.....f"
    SKROW "eB..z..f"
    SKROW "eB.....f"
    SKROW "eBz....f"
    SKROW "eB.....f"
    SKROW "ez.z.z.f"
    SKROW "eeeeeeee"
    SKROW "FFFFFFFF"
    SKROWS_END
    align 8
    SKBMP fc_stole_back, fc_stole_back_rows, 8, 22, fc_pal
    ; fc_stole_side (8x22): fc_stole RIGHT, fc_stole LEFT
    SKROWS fc_stole_side_rows, 8, 22
    SKROW "a______a"
    SKROW "a______a"
    SKROW "a______a"
    SKROW "a______a"
    SKROW "a______a"
    SKROW "a______a"
    SKROW "a______a"
    SKROW "a______a"
    SKROW "a______a"
    SKROW "a______a"
    SKROW "a______a"
    SKROW "a______a"
    SKROW "a______a"
    SKROW "a______a"
    SKROW "a______a"
    SKROW "a______a"
    SKROW "a______a"
    SKROW "a______a"
    SKROW "a______a"
    SKROW "a______a"
    SKROW "ae____ea"
    SKROW "a______a"
    SKROWS_END
    align 8
    SKBMP fc_stole_side, fc_stole_side_rows, 8, 22, fc_pal
    ; fc_drape_back (10x8): fc_drape BACK
    SKROWS fc_drape_back_rows, 10, 8
    SKROW "AAAAAAAAAA"
    SKROW "A.z..z...z"
    SKROW "A.z..z.z.z"
    SKROW "A.z..z.z.z"
    SKROW "A.z..z.z.z"
    SKROW "A....z.z.z"
    SKROW "__eeeeee__"
    SKROW "___FFFF___"
    SKROWS_END
    align 8
    SKBMP fc_drape_back, fc_drape_back_rows, 10, 8, fc_pal
    ; fc_drape_front (10x8): fc_drape FRONT
    SKROWS fc_drape_front_rows, 10, 8
    SKROW "AAAAAAAAAA"
    SKROW "z...z..z.A"
    SKROW "z.z.z..z.A"
    SKROW "z.z.z..z.A"
    SKROW "z.z.z..z.A"
    SKROW "z.z.z....A"
    SKROW "__eeeeee__"
    SKROW "___FFFF___"
    SKROWS_END
    align 8
    SKBMP fc_drape_front, fc_drape_front_rows, 10, 8, fc_pal
    ; fc_rope (16x2): fc_sash FRONT, fc_sash BACK
    SKROWS fc_rope_rows, 16, 2
    SKROW "PpoOPpoOPpoOPpoO"
    SKROW "pPpoOPpoOPpoOPpo"
    SKROWS_END
    align 8
    SKBMP fc_rope, fc_rope_rows, 16, 2, fc_pal
    ; fc_rope_side (8x2): fc_sash LEFT, fc_sash RIGHT
    SKROWS fc_rope_side_rows, 8, 2
    SKROW "PpoOPpoO"
    SKROW "pPpoOPpo"
    SKROWS_END
    align 8
    SKBMP fc_rope_side, fc_rope_side_rows, 8, 2, fc_pal
    ; fc_knot_front (3x3): fc_knot FRONT
    SKROWS fc_knot_front_rows, 3, 3
    SKROW "PpP"
    SKROW "pOp"
    SKROW "oOo"
    SKROWS_END
    align 8
    SKBMP fc_knot_front, fc_knot_front_rows, 3, 3, fc_pal
    ; fc_tail_a_front (1x5): fc_tail_a FRONT
    SKROWS fc_tail_a_front_rows, 1, 5
    SKROW "P"
    SKROW "p"
    SKROW "o"
    SKROW "p"
    SKROW "O"
    SKROWS_END
    align 8
    SKBMP fc_tail_a_front, fc_tail_a_front_rows, 1, 5, fc_pal
    ; fc_tail_b_front (1x4): fc_tail_b FRONT
    SKROWS fc_tail_b_front_rows, 1, 4
    SKROW "p"
    SKROW "o"
    SKROW "p"
    SKROW "O"
    SKROWS_END
    align 8
    SKBMP fc_tail_b_front, fc_tail_b_front_rows, 1, 4, fc_pal
    ; fc_pendant_front (4x5): fc_pendant FRONT
    SKROWS fc_pendant_front_rows, 4, 5
    SKROW "hGGh"
    SKROW "GEeG"
    SKROW "GefG"
    SKROW "gfFg"
    SKROW "hggh"
    SKROWS_END
    align 8
    SKBMP fc_pendant_front, fc_pendant_front_rows, 4, 5, fc_pal
    ; fc_face (16x16): fc_head FRONT
    SKROWS fc_face_rows, 16, 16
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "......kkkk......"
    SKROW ".......ee......."
    SKROW "...jjj.ff.jjj..."
    SKROW "..jLllj..jLllj.."
    SKROW "..jllmj..jllmj.."
    SKROW "...jkj....jkj..."
    SKROW "...q........q..."
    SKROW "..kq........qk.."
    SKROW "..kkq......qkk.."
    SKROW "......MMMM......"
    SKROW ".....k.kk.k....."
    SKROW "................"
    SKROWS_END
    align 8
    SKBMP fc_face, fc_face_rows, 16, 16, fc_pal
    ; fc_hood_front (16x16): fc_hood FRONT
    SKROWS fc_hood_front_rows, 16, 16
    SKROW "BBBBBBBBBBBBBBBB"
    SKROW "BAAAAAAAAAAAAAAz"
    SKROW "Baaaaazaazaaaaaz"
    SKROW "BzzzZZZZZZZZzzzz"
    SKROW "BaaaZ______Zaaaz"
    SKROW "BazZ________Zzaz"
    SKROW "BaZ__________Zaz"
    SKROW "BZ____________Zz"
    SKROW "BZ____________Zz"
    SKROW "Bz____________zz"
    SKROW "BZ____________Zz"
    SKROW "BZ____________Zz"
    SKROW "BZ____________Zz"
    SKROW "Bz____________zz"
    SKROW "zz____________zz"
    SKROW "ZZZZZZZZZZZZZZZZ"
    SKROWS_END
    align 8
    SKBMP fc_hood_front, fc_hood_front_rows, 16, 16, fc_pal
    ; fc_hood_back (16x16): fc_hood BACK
    SKROWS fc_hood_back_rows, 16, 16
    SKROW "BBBBBBBBBBBBBBBB"
    SKROW "B......zA......."
    SKROW "B......zA......."
    SKROW "B..zA..zA..Az..."
    SKROW "B..zA..zA..Az..."
    SKROW "B..zA..zA..Az..."
    SKROW "B..zA..zA..Az..."
    SKROW "B..zA..zA..Az..."
    SKROW "B..zA..zA..Az..."
    SKROW "B..zA..zA..Az..."
    SKROW "B..zA..zA..Az..."
    SKROW "B..zA..zA..Az..."
    SKROW "B..zA..zA..Az..."
    SKROW "B......zA......."
    SKROW "_zzzzzzzzzzzzzz_"
    SKROW "___ZZZZZZZZZZ___"
    SKROWS_END
    align 8
    SKBMP fc_hood_back, fc_hood_back_rows, 16, 16, fc_pal
    ; fc_hood_right (16x16): fc_hood RIGHT
    SKROWS fc_hood_right_rows, 16, 16
    SKROW "BBBBBBBBBBBBBBBB"
    SKROW "B..............."
    SKROW "B..............."
    SKROW "B...zA...zA....."
    SKROW "B...zA...zA...zZ"
    SKROW "B...zA...zA...zZ"
    SKROW "B...zA...zA...zZ"
    SKROW "B...zA...zA...zZ"
    SKROW "B...zA...zA...zZ"
    SKROW "B...zA...zA...zZ"
    SKROW "B...zA...zA...zZ"
    SKROW "B...zA...zA...zZ"
    SKROW "B...zA...zA...zZ"
    SKROW "_...zA...zA...zZ"
    SKROW "_zzzzzzzzzzzzzzz"
    SKROW "___ZZZZZZZZZZZZZ"
    SKROWS_END
    align 8
    SKBMP fc_hood_right, fc_hood_right_rows, 16, 16, fc_pal
    ; fc_hood_left (16x16): fc_hood LEFT
    SKROWS fc_hood_left_rows, 16, 16
    SKROW "BBBBBBBBBBBBBBBB"
    SKROW "...............B"
    SKROW "...............B"
    SKROW ".....Az...Az...B"
    SKROW "Zz...Az...Az...B"
    SKROW "Zz...Az...Az...B"
    SKROW "Zz...Az...Az...B"
    SKROW "Zz...Az...Az...B"
    SKROW "Zz...Az...Az...B"
    SKROW "Zz...Az...Az...B"
    SKROW "Zz...Az...Az...B"
    SKROW "Zz...Az...Az...B"
    SKROW "Zz...Az...Az...B"
    SKROW "Zz...Az...Az..._"
    SKROW "zzzzzzzzzzzzzzz_"
    SKROW "ZZZZZZZZZZZZZ___"
    SKROWS_END
    align 8
    SKBMP fc_hood_left, fc_hood_left_rows, 16, 16, fc_pal
    ; fc_hood_top (16x16): fc_hood TOP
    SKROWS fc_hood_top_rows, 16, 16
    SKROW "BBBBBBBBBBBBBBBB"
    SKROW "B......zA......."
    SKROW "B......zA......."
    SKROW "B..zA..zA..Az..."
    SKROW "B..z.A.zA.A.z..."
    SKROW "B...z..zA..z...."
    SKROW "B......zA......."
    SKROW "B......zA......."
    SKROW "B......zA......."
    SKROW "B......zA......."
    SKROW "B......zA......."
    SKROW "B...z..zA..z...."
    SKROW "B....z.zA.z....."
    SKROW "B......zA......."
    SKROW "B......zA......."
    SKROW "B......zA......."
    SKROWS_END
    align 8
    SKBMP fc_hood_top, fc_hood_top_rows, 16, 16, fc_pal
    ; fc_hood_bottom (16x16): fc_hood BOTTOM
    SKROWS fc_hood_bottom_rows, 16, 16
    SKROW "ZZZZZZZZZZZZZZZZ"
    SKROW "ZZZZZZZZZZZZZZZZ"
    SKROW "ZZ____________ZZ"
    SKROW "ZZ____________ZZ"
    SKROW "ZZ____________ZZ"
    SKROW "ZZ____________ZZ"
    SKROW "ZZ____________ZZ"
    SKROW "ZZ____________ZZ"
    SKROW "ZZ____________ZZ"
    SKROW "ZZ____________ZZ"
    SKROW "ZZ____________ZZ"
    SKROW "ZZ____________ZZ"
    SKROW "ZZ____________ZZ"
    SKROW "ZZ____________ZZ"
    SKROW "ZZZZZZZZZZZZZZZZ"
    SKROW "ZZZZZZZZZZZZZZZZ"
    SKROWS_END
    align 8
    SKBMP fc_hood_bottom, fc_hood_bottom_rows, 16, 16, fc_pal
    ; fc_nose_front (2x3): fc_nose FRONT
    SKROWS fc_nose_front_rows, 2, 3
    SKROW "ss"
    SKROW "ss"
    SKROW "kk"
    SKROWS_END
    align 8
    SKBMP fc_nose_front, fc_nose_front_rows, 2, 3, fc_pal
    ; fc_leg_front (6x24): fc_leg_l FRONT
    SKROWS fc_leg_front_rows, 6, 24
    SKROW "T....u"
    SKROW "T..u.u"
    SKROW "T.Tu.u"
    SKROW "T.Tu.u"
    SKROW "T..uTu"
    SKROW "T..u.u"
    SKROW "T.Tu.u"
    SKROW "T.Tu.u"
    SKROW "T..uTu"
    SKROW "T..u.u"
    SKROW "T.Tu.u"
    SKROW "T.Tu.u"
    SKROW "T..uTu"
    SKROW "T..u.u"
    SKROW "T.Tu.u"
    SKROW "T.Tu.u"
    SKROW "T..uTu"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROWS_END
    align 8
    SKBMP fc_leg_front, fc_leg_front_rows, 6, 24, fc_pal
    ; fc_leg_back (6x24): fc_leg_l BACK
    SKROWS fc_leg_back_rows, 6, 24
    SKROW "T....u"
    SKROW "T.u..u"
    SKROW "T.u..u"
    SKROW "T.u..u"
    SKROW "T.u..u"
    SKROW "T.u..u"
    SKROW "T.u..u"
    SKROW "T.u..u"
    SKROW "T.u..u"
    SKROW "T.u..u"
    SKROW "T.u..u"
    SKROW "T.u..u"
    SKROW "T.u..u"
    SKROW "T.u..u"
    SKROW "T.u..u"
    SKROW "T.u..u"
    SKROW "T.u..u"
    SKROW "T.u..u"
    SKROW "T.u..u"
    SKROW "T.u..u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROWS_END
    align 8
    SKBMP fc_leg_back, fc_leg_back_rows, 6, 24, fc_pal
    ; fc_leg_side (6x24): fc_leg_l LEFT, fc_leg_l RIGHT
    SKROWS fc_leg_side_rows, 6, 24
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T..u.u"
    SKROW "T....u"
    SKROW "T..u.u"
    SKROW "T....u"
    SKROW "T..u.u"
    SKROW "T....u"
    SKROW "T..u.u"
    SKROW "T....u"
    SKROW "T..u.u"
    SKROW "T....u"
    SKROW "T..u.u"
    SKROW "T....u"
    SKROW "T..u.u"
    SKROW "T....u"
    SKROW "T..u.u"
    SKROW "T....u"
    SKROW "T..u.u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROWS_END
    align 8
    SKBMP fc_leg_side, fc_leg_side_rows, 6, 24, fc_pal
    ; fc_hand_front (6x22): fc_arm_l FRONT
    SKROWS fc_hand_front_rows, 6, 22
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "Rd...d"
    SKROW "Rd...d"
    SKROW "Rd...d"
    SKROW "R.d..d"
    SKROW "R.d..d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "kkkkkk"
    SKROW "Sssssk"
    SKROW "Skkskk"
    SKROW "Sskskk"
    SKROWS_END
    align 8
    SKBMP fc_hand_front, fc_hand_front_rows, 6, 22, fc_pal
    ; fc_hand_back (6x22): fc_arm_l BACK
    SKROWS fc_hand_back_rows, 6, 22
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "Rd...d"
    SKROW "Rd...d"
    SKROW "Rd...d"
    SKROW "R.d..d"
    SKROW "R.d..d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "kkkkkk"
    SKROW "Sssssk"
    SKROW "Sskksk"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP fc_hand_back, fc_hand_back_rows, 6, 22, fc_pal
    ; fc_hand_side (6x22): fc_arm_l LEFT, fc_arm_l RIGHT
    SKROWS fc_hand_side_rows, 6, 22
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "R....d"
    SKROW "kkkkkk"
    SKROW "Sssssk"
    SKROW "Sskksk"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP fc_hand_side, fc_hand_side_rows, 6, 22, fc_pal
    ; fc_fist_front (6x5): fc_fist_l FRONT
    SKROWS fc_fist_front_rows, 6, 5
    SKROW "kkkkkk"
    SKROW "SSsksk"
    SKROW "Ssskss"
    SKROW "Ssskss"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP fc_fist_front, fc_fist_front_rows, 6, 5, fc_pal
    ; fc_fist_back (6x5): fc_fist_l BACK
    SKROWS fc_fist_back_rows, 6, 5
    SKROW "kkkkkk"
    SKROW "SsssSk"
    SKROW "Ssksss"
    SKROW "Ssssss"
    SKROW "kskkkk"
    SKROWS_END
    align 8
    SKBMP fc_fist_back, fc_fist_back_rows, 6, 5, fc_pal
    ; fc_fist_right (6x5): fc_fist_l RIGHT
    SKROWS fc_fist_right_rows, 6, 5
    SKROW "kkkkkk"
    SKROW "SssskS"
    SKROW "SssskS"
    SKROW "Sssskk"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP fc_fist_right, fc_fist_right_rows, 6, 5, fc_pal
    ; fc_fist_left (6x5): fc_fist_l LEFT
    SKROWS fc_fist_left_rows, 6, 5
    SKROW "kkkkkk"
    SKROW "Skssss"
    SKROW "Skssss"
    SKROW "kkssss"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP fc_fist_left, fc_fist_left_rows, 6, 5, fc_pal

section .data
SKMODEL_BEGIN m_folk_cult, 32, 0, 11, 26, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART fc_torso, -8, 24, -4, 16, 22, 8, 0, 0              ; charcoal robe
    PART fc_stole, -4, 24, -4, 8, 22, 8, 4, SKPF_CUTOUT     ; ash stole front and back, red borders and sigils
    PART fc_collar, -6, 42, -5, 12, 5, 10, 4, 0             ; ash cowl ring round the neck, red edge
    PART fc_drape, -5, 38, 4, 10, 8, 2, 0, SKPF_CUTOUT      ; cowl drape on the back, pointed
    PART fc_sash, -8, 28, -4, 16, 2, 8, 6, 0                ; rope sash
    PART fc_knot, -5, 27, -6, 3, 3, 2, 0, 0                 ; sash knot at the left hip
    PART fc_tail_a, -5, 22, -6, 1, 5, 1, 0, 0               ; sash tail
    PART fc_tail_b, -3, 23, -6, 1, 4, 1, 0, 0               ; sash tail
    PART fc_pendant, -2, 34, -6, 4, 5, 2, 0, 0              ; gold pendant with a red gem
    SKBONE BK_HEAD, 0, 0, 0.00
    PART fc_head, -8, 46, -8, 16, 16, 16, 0, 0              ; the 16 texel head
    PART fc_hood, -8, 46, -8, 16, 16, 16, 6, SKPF_CUTOUT    ; ash hood overlay, face opening
    PART fc_nose, -1, 50, -10, 2, 3, 2, 0, 0                ; nose
    SKBONE BK_LLEG, 24, 0, 1.00
    PART fc_leg_l, -6, 0, -3, 6, 24, 6, 0, 0                ; robe skirt
    PART fc_hem_l, -7, 3, -4, 7, 6, 8, 0, 0                 ; flared hem with red trim
    PART fc_foot_l, -7, 0, -5, 7, 3, 9, 0, 0                ; soft slipper
    SKBONE BK_RLEG, 24, 0, -1.00
    PART_AS fc_leg_r, fc_leg_l, 0, 0, -3, 0, 0
    PART_AS fc_hem_r, fc_hem_l, 0, 3, -4, 0, 0
    PART_AS fc_foot_r, fc_foot_l, 0, 0, -5, 0, 0
    SKBONE BK_LARM, 44, 0, -1.00
    PART fc_arm_l, -14, 24, -3, 6, 22, 6, 0, 0              ; long sleeve, pale hand
    PART fc_sleeve_l, -14, 36, -3, 6, 10, 6, 6, 0           ; ash shoulder mantle
    PART fc_cuff_l, -14, 28, -3, 6, 8, 6, 12, 0             ; bell cuff with a red trim
    PART fc_fist_l, -14, 24, -3, 6, 5, 6, 8, 0              ; pale fist
    SKBONE BK_RARM, 44, 0, 1.00
    PART_AS fc_arm_r, fc_arm_l, 8, 24, -3, 0, 0
    PART_AS fc_sleeve_r, fc_sleeve_l, 8, 36, -3, 6, 0
    PART_AS fc_cuff_r, fc_cuff_l, 8, 28, -3, 12, 0
    PART_AS fc_fist_r, fc_fist_l, 8, 24, -3, 8, 0
SKMODEL_PAINT
    ; --- fc_torso: charcoal robe, soft folds (the stole and the sash cover the middle)
    SK_FILL fc_torso, SKM_ALL, FC_ROBE_2, 15
    SK_BMP fc_torso, SKF_FRONT, 0, 0, fc_torso_front
    SK_BMP fc_torso, SKF_BACK, 0, 0, fc_torso_back
    SK_BMP fc_torso, SKF_RIGHT, 0, 0, fc_torso_side
    SK_BMP fc_torso, SKF_LEFT, 0, 0, fc_torso_side
    SK_RECT fc_torso, SKF_BOTTOM, 0, 0, 16, 8, FC_ROBE_4, 0
    SK_GRAD fc_torso, SKM_SIDES, 272, 224
    ; --- fc_stole: ash panel hanging from the cowl, red borders; a chain and a flame sigil on the front, a large sigil on the back (cutout)
    SK_FILL fc_stole, SKM_ALL, FC_ASH_2, 15
    SK_BMP fc_stole, SKF_FRONT, 0, 0, fc_stole_front
    SK_BMP fc_stole, SKF_BACK, 0, 0, fc_stole_back
    SK_BMP fc_stole, SKF_RIGHT, 0, 0, fc_stole_side
    SK_BMP fc_stole, SKF_LEFT, 0, 0, fc_stole_side
    SK_RECT fc_stole, SKF_TOP, 0, 0, 8, 8, FC_ASH_1, 0
    SK_RECT fc_stole, SKF_BOTTOM, 0, 0, 8, 8, FC_RED_4, 0
    ; --- fc_collar: ash cowl ring with a red lower edge; fc_drape: the cowl falling down the back (cutout)
    SK_FILL fc_collar, SKM_ALL, FC_ASH_2, 15
    SK_RECT fc_collar, SKF_FRONT, 0, 0, 12, 1, FC_ASH_1, 0
    SK_RECT fc_collar, SKF_FRONT, 0, 3, 12, 1, FC_RED_2, 0
    SK_RECT fc_collar, SKF_FRONT, 0, 4, 12, 1, FC_RED_4, 0
    SK_RECT fc_collar, SKF_FRONT, 0, 1, 1, 2, FC_ASH_1, 0
    SK_RECT fc_collar, SKF_BACK, 0, 0, 12, 1, FC_ASH_1, 0
    SK_RECT fc_collar, SKF_BACK, 0, 3, 12, 1, FC_RED_2, 0
    SK_RECT fc_collar, SKF_BACK, 0, 4, 12, 1, FC_RED_4, 0
    SK_RECT fc_collar, SKF_BACK, 0, 1, 1, 2, FC_ASH_1, 0
    SK_RECT fc_collar, SKF_LEFT, 0, 0, 10, 1, FC_ASH_1, 0
    SK_RECT fc_collar, SKF_LEFT, 0, 3, 10, 1, FC_RED_2, 0
    SK_RECT fc_collar, SKF_LEFT, 0, 4, 10, 1, FC_RED_4, 0
    SK_RECT fc_collar, SKF_LEFT, 0, 1, 1, 2, FC_ASH_1, 0
    SK_RECT fc_collar, SKF_RIGHT, 0, 0, 10, 1, FC_ASH_1, 0
    SK_RECT fc_collar, SKF_RIGHT, 0, 3, 10, 1, FC_RED_2, 0
    SK_RECT fc_collar, SKF_RIGHT, 0, 4, 10, 1, FC_RED_4, 0
    SK_RECT fc_collar, SKF_RIGHT, 0, 1, 1, 2, FC_ASH_1, 0
    SK_GRAD fc_collar, SKM_SIDES, 272, 224
    SK_RECT fc_collar, SKF_TOP, 0, 0, 12, 10, FC_ASH_1, 15
    SK_RECT fc_collar, SKF_BOTTOM, 0, 0, 12, 10, FC_ASH_4, 0
    SK_FILL fc_drape, SKM_ALL, FC_ASH_2, 15
    SK_BMP fc_drape, SKF_BACK, 0, 0, fc_drape_back
    SK_BMP fc_drape, SKF_FRONT, 0, 0, fc_drape_front
    SK_RECT fc_drape, SKF_LEFT, 0, 0, 2, 6, FC_ASH_3, 0
    SK_RECT fc_drape, SKF_RIGHT, 0, 0, 2, 6, FC_ASH_3, 0
    SK_RECT fc_drape, SKF_TOP, 0, 0, 10, 2, FC_ASH_1, 0
    SK_RECT fc_drape, SKF_BOTTOM, 0, 0, 10, 2, FC_RED_4, 0
    ; --- fc_sash: twisted hemp rope; fc_knot and its tails; fc_pendant: a gold frame round a red gem
    SK_FILL fc_sash, SKM_ALL, FC_ROPE_2, 0
    SK_BMP fc_sash, SKF_FRONT, 0, 0, fc_rope
    SK_BMP fc_sash, SKF_BACK, 0, 0, fc_rope
    SK_BMP fc_sash, SKF_LEFT, 0, 0, fc_rope_side
    SK_BMP fc_sash, SKF_RIGHT, 0, 0, fc_rope_side
    SK_RECT fc_sash, SKF_TOP, 0, 0, 16, 8, FC_ROPE_1, 0
    SK_RECT fc_sash, SKF_BOTTOM, 0, 0, 16, 8, FC_ROPE_4, 0
    SK_FILL fc_knot, SKM_ALL, FC_ROPE_2, 7
    SK_BMP fc_knot, SKF_FRONT, 0, 0, fc_knot_front
    SK_RECT fc_knot, SKF_TOP, 0, 0, 3, 2, FC_ROPE_1, 0
    SK_RECT fc_knot, SKF_BOTTOM, 0, 0, 3, 2, FC_ROPE_4, 0
    SK_FILL fc_tail_a, SKM_ALL, FC_ROPE_2, 7
    SK_BMP fc_tail_a, SKF_FRONT, 0, 0, fc_tail_a_front
    SK_FILL fc_tail_b, SKM_ALL, FC_ROPE_3, 7
    SK_BMP fc_tail_b, SKF_FRONT, 0, 0, fc_tail_b_front
    SK_FILL fc_pendant, SKM_ALL, AC_GOLD_3, 0
    SK_BMP fc_pendant, SKF_FRONT, 0, 0, fc_pendant_front
    SK_RECT fc_pendant, SKF_TOP, 0, 0, 4, 2, AC_GOLD_1, 0
    SK_RECT fc_pendant, SKF_BOTTOM, 0, 0, 4, 2, AC_GOLD_4, 0
    ; --- fc_head: pale gaunt face, glowing red eyes in dark sockets, ash tear tracks, a thin mouth (the hood frames it)
    SK_FILL fc_head, SKM_ALL, FC_SKIN_2, 15
    SK_GRAD fc_head, SKM_SIDES, 272, 224
    SK_RECT fc_head, SKF_TOP, 0, 0, 16, 16, FC_ASH_3, 15
    SK_RECT fc_head, SKF_BACK, 0, 0, 16, 16, FC_ASH_3, 15
    SK_RECT fc_head, SKF_RIGHT, 0, 0, 16, 16, FC_ASH_3, 15
    SK_RECT fc_head, SKF_LEFT, 0, 0, 16, 16, FC_ASH_3, 15
    SK_RECT fc_head, SKF_BOTTOM, 0, 0, 16, 16, FC_SKIN_4, 0
    SK_BMP fc_head, SKF_FRONT, 0, 0, fc_face
    ; --- fc_hood: ash hood framing the face: a brim, deep shadow under it, lining; seam and folds (cutout)
    SK_FILL fc_hood, SKM_ALL, FC_ASH_2, 15
    SK_GRAD fc_hood, SKM_SIDES, 272, 224
    SK_BMP fc_hood, SKF_FRONT, 0, 0, fc_hood_front
    SK_BMP fc_hood, SKF_BACK, 0, 0, fc_hood_back
    SK_BMP fc_hood, SKF_RIGHT, 0, 0, fc_hood_right
    SK_BMP fc_hood, SKF_LEFT, 0, 0, fc_hood_left
    SK_BMP fc_hood, SKF_TOP, 0, 0, fc_hood_top
    SK_BMP fc_hood, SKF_BOTTOM, 0, 0, fc_hood_bottom
    ; --- fc_nose: pale and thin
    SK_FILL fc_nose, SKM_ALL, FC_SKIN_2, 7
    SK_BMP fc_nose, SKF_FRONT, 0, 0, fc_nose_front
    SK_RECT fc_nose, SKF_TOP, 0, 0, 2, 2, FC_SKIN_2, 0
    SK_RECT fc_nose, SKF_BOTTOM, 0, 0, 2, 2, FC_SKIN_4, 0
    ; --- fc_leg_l (shared with fc_leg_r): the robe to the ankle, folds; fc_hem_l: flared hem with red trim; fc_foot_l: slipper
    SK_FILL fc_leg_l, SKM_ALL, FC_SKIRT_2, 15
    SK_BMP fc_leg_l, SKF_FRONT, 0, 0, fc_leg_front
    SK_BMP fc_leg_l, SKF_BACK, 0, 0, fc_leg_back
    SK_BMP fc_leg_l, SKF_LEFT, 0, 0, fc_leg_side
    SK_BMP fc_leg_l, SKF_RIGHT, 0, 0, fc_leg_side
    SK_RECT fc_leg_l, SKF_BOTTOM, 0, 0, 6, 6, FC_SKIRT_4, 0
    SK_GRAD fc_leg_l, SKM_SIDES, 272, 224
    SK_FILL fc_hem_l, SKM_ALL, FC_SKIRT_2, 15
    SK_RECT fc_hem_l, SKF_FRONT, 0, 3, 7, 2, FC_RED_2, 0
    SK_RECT fc_hem_l, SKF_FRONT, 0, 5, 7, 1, FC_RED_4, 0
    SK_RECT fc_hem_l, SKF_FRONT, 0, 0, 7, 1, FC_SKIRT_1, 0
    SK_RECT fc_hem_l, SKF_FRONT, 0, 3, 1, 2, FC_RED_1, 0
    SK_RECT fc_hem_l, SKF_BACK, 0, 3, 7, 2, FC_RED_2, 0
    SK_RECT fc_hem_l, SKF_BACK, 0, 5, 7, 1, FC_RED_4, 0
    SK_RECT fc_hem_l, SKF_BACK, 0, 0, 7, 1, FC_SKIRT_1, 0
    SK_RECT fc_hem_l, SKF_BACK, 0, 3, 1, 2, FC_RED_1, 0
    SK_RECT fc_hem_l, SKF_LEFT, 0, 3, 8, 2, FC_RED_2, 0
    SK_RECT fc_hem_l, SKF_LEFT, 0, 5, 8, 1, FC_RED_4, 0
    SK_RECT fc_hem_l, SKF_LEFT, 0, 0, 8, 1, FC_SKIRT_1, 0
    SK_RECT fc_hem_l, SKF_LEFT, 0, 3, 1, 2, FC_RED_1, 0
    SK_RECT fc_hem_l, SKF_RIGHT, 0, 3, 8, 2, FC_RED_2, 0
    SK_RECT fc_hem_l, SKF_RIGHT, 0, 5, 8, 1, FC_RED_4, 0
    SK_RECT fc_hem_l, SKF_RIGHT, 0, 0, 8, 1, FC_SKIRT_1, 0
    SK_RECT fc_hem_l, SKF_RIGHT, 0, 3, 1, 2, FC_RED_1, 0
    SK_RECT fc_hem_l, SKF_TOP, 0, 0, 7, 8, FC_SKIRT_1, 15
    SK_RECT fc_hem_l, SKF_BOTTOM, 0, 0, 7, 8, FC_RED_4, 0
    SK_GRAD fc_hem_l, SKM_SIDES, 272, 224
    SK_FILL fc_foot_l, SKM_ALL, FC_SKIRT_3, 15
    SK_RECT fc_foot_l, SKF_FRONT, 0, 0, 7, 1, FC_SKIRT_1, 0
    SK_RECT fc_foot_l, SKF_FRONT, 0, 2, 7, 1, FC_SKIRT_4, 0
    SK_RECT fc_foot_l, SKF_LEFT, 0, 0, 9, 1, FC_SKIRT_1, 0
    SK_RECT fc_foot_l, SKF_LEFT, 0, 2, 9, 1, FC_SKIRT_4, 0
    SK_RECT fc_foot_l, SKF_RIGHT, 0, 2, 9, 1, FC_SKIRT_4, 0
    SK_RECT fc_foot_l, SKF_BACK, 0, 2, 7, 1, FC_SKIRT_4, 0
    SK_RECT fc_foot_l, SKF_TOP, 0, 0, 7, 9, FC_SKIRT_2, 15
    SK_RECT fc_foot_l, SKF_BOTTOM, 0, 0, 7, 9, FC_SKIRT_4, 0
    ; --- fc_arm_l (shared with fc_arm_r): charcoal sleeve to row 17, a pale hand with long fingers
    SK_FILL fc_arm_l, SKM_ALL, FC_ROBE_2, 15
    SK_BMP fc_arm_l, SKF_FRONT, 0, 0, fc_hand_front
    SK_BMP fc_arm_l, SKF_BACK, 0, 0, fc_hand_back
    SK_BMP fc_arm_l, SKF_LEFT, 0, 0, fc_hand_side
    SK_BMP fc_arm_l, SKF_RIGHT, 0, 0, fc_hand_side
    SK_RECT fc_arm_l, SKF_TOP, 0, 0, 6, 6, FC_ROBE_2, 15
    SK_RECT fc_arm_l, SKF_BOTTOM, 0, 0, 6, 6, FC_SKIN_3, 0
    SK_GRAD fc_arm_l, SKM_SIDES, 272, 224
    SK_FILL fc_sleeve_l, SKM_ALL, FC_ASH_2, 15
    SK_RECT fc_sleeve_l, SKF_TOP, 0, 0, 6, 6, FC_ASH_1, 15
    SK_RECT fc_sleeve_l, SKF_FRONT, 0, 0, 6, 1, FC_ASH_1, 0
    SK_RECT fc_sleeve_l, SKF_FRONT, 0, 0, 1, 8, FC_ASH_1, 0
    SK_RECT fc_sleeve_l, SKF_FRONT, 5, 0, 1, 8, FC_ASH_3, 0
    SK_RECT fc_sleeve_l, SKF_FRONT, 0, 8, 6, 1, FC_RED_2, 0
    SK_RECT fc_sleeve_l, SKF_FRONT, 0, 9, 6, 1, FC_RED_4, 0
    SK_RECT fc_sleeve_l, SKF_BACK, 0, 0, 6, 1, FC_ASH_1, 0
    SK_RECT fc_sleeve_l, SKF_BACK, 0, 0, 1, 8, FC_ASH_1, 0
    SK_RECT fc_sleeve_l, SKF_BACK, 5, 0, 1, 8, FC_ASH_3, 0
    SK_RECT fc_sleeve_l, SKF_BACK, 0, 8, 6, 1, FC_RED_2, 0
    SK_RECT fc_sleeve_l, SKF_BACK, 0, 9, 6, 1, FC_RED_4, 0
    SK_RECT fc_sleeve_l, SKF_LEFT, 0, 0, 6, 1, FC_ASH_1, 0
    SK_RECT fc_sleeve_l, SKF_LEFT, 0, 0, 1, 8, FC_ASH_1, 0
    SK_RECT fc_sleeve_l, SKF_LEFT, 5, 0, 1, 8, FC_ASH_3, 0
    SK_RECT fc_sleeve_l, SKF_LEFT, 0, 8, 6, 1, FC_RED_2, 0
    SK_RECT fc_sleeve_l, SKF_LEFT, 0, 9, 6, 1, FC_RED_4, 0
    SK_RECT fc_sleeve_l, SKF_RIGHT, 0, 0, 6, 1, FC_ASH_1, 0
    SK_RECT fc_sleeve_l, SKF_RIGHT, 0, 0, 1, 8, FC_ASH_1, 0
    SK_RECT fc_sleeve_l, SKF_RIGHT, 5, 0, 1, 8, FC_ASH_3, 0
    SK_RECT fc_sleeve_l, SKF_RIGHT, 0, 8, 6, 1, FC_RED_2, 0
    SK_RECT fc_sleeve_l, SKF_RIGHT, 0, 9, 6, 1, FC_RED_4, 0
    SK_GRAD fc_sleeve_l, SKM_SIDES, 272, 224
    SK_RECT fc_sleeve_l, SKF_BOTTOM, 0, 0, 6, 6, FC_RED_4, 0
    SK_FILL fc_cuff_l, SKM_ALL, FC_ROBE_2, 15
    SK_RECT fc_cuff_l, SKF_FRONT, 0, 0, 6, 1, FC_ROBE_1, 0
    SK_RECT fc_cuff_l, SKF_FRONT, 0, 0, 1, 6, FC_ROBE_1, 0
    SK_RECT fc_cuff_l, SKF_FRONT, 5, 0, 1, 6, FC_ROBE_3, 0
    SK_RECT fc_cuff_l, SKF_FRONT, 0, 6, 6, 1, FC_RED_2, 0
    SK_RECT fc_cuff_l, SKF_FRONT, 0, 7, 6, 1, FC_RED_4, 0
    SK_RECT fc_cuff_l, SKF_BACK, 0, 0, 6, 1, FC_ROBE_1, 0
    SK_RECT fc_cuff_l, SKF_BACK, 0, 0, 1, 6, FC_ROBE_1, 0
    SK_RECT fc_cuff_l, SKF_BACK, 5, 0, 1, 6, FC_ROBE_3, 0
    SK_RECT fc_cuff_l, SKF_BACK, 0, 6, 6, 1, FC_RED_2, 0
    SK_RECT fc_cuff_l, SKF_BACK, 0, 7, 6, 1, FC_RED_4, 0
    SK_RECT fc_cuff_l, SKF_LEFT, 0, 0, 6, 1, FC_ROBE_1, 0
    SK_RECT fc_cuff_l, SKF_LEFT, 0, 0, 1, 6, FC_ROBE_1, 0
    SK_RECT fc_cuff_l, SKF_LEFT, 5, 0, 1, 6, FC_ROBE_3, 0
    SK_RECT fc_cuff_l, SKF_LEFT, 0, 6, 6, 1, FC_RED_2, 0
    SK_RECT fc_cuff_l, SKF_LEFT, 0, 7, 6, 1, FC_RED_4, 0
    SK_RECT fc_cuff_l, SKF_RIGHT, 0, 0, 6, 1, FC_ROBE_1, 0
    SK_RECT fc_cuff_l, SKF_RIGHT, 0, 0, 1, 6, FC_ROBE_1, 0
    SK_RECT fc_cuff_l, SKF_RIGHT, 5, 0, 1, 6, FC_ROBE_3, 0
    SK_RECT fc_cuff_l, SKF_RIGHT, 0, 6, 6, 1, FC_RED_2, 0
    SK_RECT fc_cuff_l, SKF_RIGHT, 0, 7, 6, 1, FC_RED_4, 0
    SK_GRAD fc_cuff_l, SKM_SIDES, 272, 224
    SK_RECT fc_cuff_l, SKF_TOP, 0, 0, 6, 6, FC_ROBE_1, 15
    SK_RECT fc_cuff_l, SKF_BOTTOM, 0, 0, 6, 6, FC_RED_4, 0
    ; --- fc_fist_l (shared with fc_fist_r): a pale clenched fist, long finger gaps, a thumb on each side
    SK_FILL fc_fist_l, SKM_ALL, FC_SKIN_2, 7
    SK_BMP fc_fist_l, SKF_FRONT, 0, 0, fc_fist_front
    SK_BMP fc_fist_l, SKF_BACK, 0, 0, fc_fist_back
    SK_BMP fc_fist_l, SKF_RIGHT, 0, 0, fc_fist_right
    SK_BMP fc_fist_l, SKF_LEFT, 0, 0, fc_fist_left
    SK_RECT fc_fist_l, SKF_TOP, 0, 0, 6, 6, FC_SKIN_2, 0
    SK_RECT fc_fist_l, SKF_BOTTOM, 0, 0, 6, 6, FC_SKIN_3, 0
    SK_GRAD fc_fist_l, SKM_SIDES, 272, 224
SKMODEL_END

; ===================================================================================================
; m_folk_beastfolk
; ===================================================================================================
RAMP FF_FUR, 130, 110, 90               ; brown-grey head and arm fur (the factions table)
RAMP FF_VEST, 150, 130, 100             ; vest fur
RAMP FF_DARK, 90, 75, 60                ; dark leg fur
RAMP FF_CREAM, 214, 196, 164            ; muzzle, chest and tail-tip fur

section .rodata
; The characters of every ff_ bitmap. Groups: base, highlight, shade, deep.
;   s S k K head and arm fur   v V w W vest fur   d D n N leg fur   c C j J cream fur (muzzle, chest, tail tip)
;   p P q war paint   b B u bone (AC)   l L e E leather (AC)   y Y amber eye   x X nose and slit
;   m M pink (ears, mouth)   i I claw   _ transparent
align 8
ff_pal:
    PALC 's', FF_FUR_2
    PALC 'S', FF_FUR_1
    PALC 'k', FF_FUR_3
    PALC 'K', FF_FUR_4
    PALC 'v', FF_VEST_2
    PALC 'V', FF_VEST_1
    PALC 'w', FF_VEST_3
    PALC 'W', FF_VEST_4
    PALC 'd', FF_DARK_2
    PALC 'D', FF_DARK_1
    PALC 'n', FF_DARK_3
    PALC 'N', FF_DARK_4
    PALC 'c', FF_CREAM_2
    PALC 'C', FF_CREAM_1
    PALC 'j', FF_CREAM_3
    PALC 'J', FF_CREAM_4
    PALC 'p', RGBO(236, 232, 222)
    PALC 'P', RGBO(252, 250, 246)
    PALC 'q', RGBO(184, 180, 172)
    PALC 'b', AC_BONE_2
    PALC 'B', AC_BONE_1
    PALC 'u', AC_BONE_3
    PALC 'l', AC_LEATHER_2
    PALC 'L', AC_LEATHER_1
    PALC 'e', AC_LEATHER_3
    PALC 'E', AC_LEATHER_4
    PALC 'y', RGBO(236, 168, 36)
    PALC 'Y', RGBO(255, 228, 120)
    PALC 'x', RGBO(26, 18, 18)
    PALC 'X', RGBO(72, 52, 48)
    PALC 'm', RGBO(196, 124, 120)
    PALC 'M', RGBO(122, 56, 60)
    PALC 'i', RGBO(66, 62, 62)
    PALC 'I', RGBO(150, 146, 140)
    PALT '_'
    dq 0

    ; ff_torso_front (16x22): ff_torso FRONT
    SKROWS ff_torso_front_rows, 16, 22
    SKROW "V..V...V.w......"
    SKROW "V.wWwV.V.w.....w"
    SKROW "V.w.wVwV.WV.wV.W"
    SKROW "VLlewVwW..V.Lle."
    SKROW "V.LleWW...VLle.."
    SKROW "V..Lle....Lle..."
    SKROW "V..VLle..Llew..."
    SKROW "V.wV.LleLle.wV.w"
    SKROW "V.wVwVLLleV.wV.w"
    SKROW "V.w.ccLleeccW..w"
    SKROW "V...cCLleecC...."
    SKROW "V..VwLleLle....."
    SKROW "V..VLleccLle.V.w"
    SKROW "V.wLleccCcLleV.w"
    SKROW "V.LleccCccCLle.W"
    SKROW "VLlewcCccCc.Lle."
    SKROW "LLLLLLBuuBLLLLLL"
    SKROW "eeeeeeuuuueeeeee"
    SKROW "wwwwwwwwwwwwwwww"
    SKROW "wwwwwwwwwwwwwwww"
    SKROW "wWwWwWwWwWwWwWwW"
    SKROW "WNNWNNWNNWNNWNNW"
    SKROWS_END
    align 8
    SKBMP ff_torso_front, ff_torso_front_rows, 16, 22, ff_pal
    ; ff_torso_back (16x22): ff_torso BACK
    SKROWS ff_torso_back_rows, 16, 22
    SKROW "V.wV.w...w...w.w"
    SKROW "V.wV.W.wVw.wVw.w"
    SKROW "V.....VwVwVwVWVw"
    SKROW "VLle..V.VWVwLle."
    SKROW "V.Lle.W...WLleV."
    SKROW "V.wLle.w..Lle..."
    SKROW "V.w.LlewVLle...w"
    SKROW "V.w..LleLlewVwVw"
    SKROW "V.WV..LBBeVwVwV."
    SKROW "V..V..LuueVw.wV."
    SKROW "V..V..LleeV..WVw"
    SKROW "V.wW.LleLle....w"
    SKROW "V.w.Llew.Lle...w"
    SKROW "V.wLle.wVwLlewV."
    SKROW "V.LleWV.Vw.LleV."
    SKROW "VLle..V.VwVWLle."
    SKROW "LLLLLLLLLLLLLLLL"
    SKROW "eeeeeeeeeeeeeeee"
    SKROW "wwwwwwwwwwwwwwww"
    SKROW "wwwwwwwwwwwwwwww"
    SKROW "wWwWwWwWwWwWwWwW"
    SKROW "WNNWNNWNNWNNWNNW"
    SKROWS_END
    align 8
    SKBMP ff_torso_back, ff_torso_back_rows, 16, 22, ff_pal
    ; ff_torso_side (8x22): ff_torso RIGHT, ff_torso LEFT
    SKROWS ff_torso_side_rows, 8, 22
    SKROW "...V.w.w"
    SKROW "...V.wVW"
    SKROW "V.w...V."
    SKROW "V.we..V."
    SKROW "V..e.wV."
    SKROW "...e.w.."
    SKROW "...e.w.w"
    SKROW "V..e.wVw"
    SKROW "V.we..Vw"
    SKROW "V.we...w"
    SKROW "W..e.w.."
    SKROW "...e.w.."
    SKROW "...e.w.."
    SKROW "..we..Vw"
    SKROW "..we..WW"
    SKROW "V....w.."
    SKROW "LLLLLLLL"
    SKROW "eeeeeeee"
    SKROW "wwwwwwww"
    SKROW "wwwwwwww"
    SKROW "wWwWwWwW"
    SKROW "WNNWNNWN"
    SKROWS_END
    align 8
    SKBMP ff_torso_side, ff_torso_side_rows, 8, 22, ff_pal
    ; ff_ruff_front (14x5): ff_ruff FRONT
    SKROWS ff_ruff_front_rows, 14, 5
    SKROW ".....j.j.....C"
    SKROW "C..C.JCJ.jC.jC"
    SKROW "J.jC..CjCJC.jJ"
    SKROW "C.j..jJJC.C.j."
    SKROW "jjjjjjjjjjjjjj"
    SKROWS_END
    align 8
    SKBMP ff_ruff_front, ff_ruff_front_rows, 14, 5, ff_pal
    ; ff_ruff_back (14x5): ff_ruff BACK
    SKROWS ff_ruff_back_rows, 14, 5
    SKROW "C.........j..."
    SKROW "C.....C.j.jC.j"
    SKROW "C.jC.jC.JC.C.J"
    SKROW "..jC.jJ.jCjC.."
    SKROW "jjjjjjjjjjjjjj"
    SKROWS_END
    align 8
    SKBMP ff_ruff_back, ff_ruff_back_rows, 14, 5, ff_pal
    ; ff_ruff_left (10x5): ff_ruff LEFT
    SKROWS ff_ruff_left_rows, 10, 5
    SKROW "..j......C"
    SKROW "..j...jCjC"
    SKROW "C.jCjCjCjC"
    SKROW "C.jCJC.JjC"
    SKROW "jjjjjjjjjj"
    SKROWS_END
    align 8
    SKBMP ff_ruff_left, ff_ruff_left_rows, 10, 5, ff_pal
    ; ff_ruff_right (10x5): ff_ruff RIGHT
    SKROWS ff_ruff_right_rows, 10, 5
    SKROW ".....C..C."
    SKROW "C...jC..J."
    SKROW "J.jCJC.jCj"
    SKROW "..JCj..jCj"
    SKROW "jjjjjjjjjj"
    SKROWS_END
    align 8
    SKBMP ff_ruff_right, ff_ruff_right_rows, 10, 5, ff_pal
    ; ff_necklace_front (10x4): ff_necklace FRONT
    SKROWS ff_necklace_front_rows, 10, 4
    SKROW "ee______ee"
    SKROW "__B____B__"
    SKROW "___B__B___"
    SKROW "____uB____"
    SKROWS_END
    align 8
    SKBMP ff_necklace_front, ff_necklace_front_rows, 10, 4, ff_pal
    ; ff_fang_p_front (2x5): ff_fang_p FRONT
    SKROWS ff_fang_p_front_rows, 2, 5
    SKROW "BB"
    SKROW "bb"
    SKROW "bb"
    SKROW "bu"
    SKROW "u_"
    SKROWS_END
    align 8
    SKBMP ff_fang_p_front, ff_fang_p_front_rows, 2, 5, ff_pal
    ; ff_fang_p_back (2x5): ff_fang_p BACK
    SKROWS ff_fang_p_back_rows, 2, 5
    SKROW "BB"
    SKROW "bb"
    SKROW "bb"
    SKROW "ub"
    SKROW "_u"
    SKROWS_END
    align 8
    SKBMP ff_fang_p_back, ff_fang_p_back_rows, 2, 5, ff_pal
    ; ff_tail1_front (4x6): ff_tail1 FRONT
    SKROWS ff_tail1_front_rows, 4, 6
    SKROW "V.w."
    SKROW "V.w."
    SKROW ".VWV"
    SKROW ".V.V"
    SKROW "...V"
    SKROW "V.w."
    SKROWS_END
    align 8
    SKBMP ff_tail1_front, ff_tail1_front_rows, 4, 6, ff_pal
    ; ff_tail1_back (4x6): ff_tail1 BACK
    SKROWS ff_tail1_back_rows, 4, 6
    SKROW "...."
    SKROW "...."
    SKROW "VVVw"
    SKROW "WVVw"
    SKROW "..Vw"
    SKROW "..VW"
    SKROWS_END
    align 8
    SKBMP ff_tail1_back, ff_tail1_back_rows, 4, 6, ff_pal
    ; ff_tail1_left (4x6): ff_tail1 LEFT
    SKROWS ff_tail1_left_rows, 4, 6
    SKROW "...."
    SKROW "VV.V"
    SKROW "VVwV"
    SKROW "V.w."
    SKROW "W.W."
    SKROW ".V.V"
    SKROWS_END
    align 8
    SKBMP ff_tail1_left, ff_tail1_left_rows, 4, 6, ff_pal
    ; ff_tail1_right (4x6): ff_tail1 RIGHT
    SKROWS ff_tail1_right_rows, 4, 6
    SKROW ".w.."
    SKROW ".w.w"
    SKROW "VwVw"
    SKROW "VWVw"
    SKROW "W.V."
    SKROW "..V."
    SKROWS_END
    align 8
    SKBMP ff_tail1_right, ff_tail1_right_rows, 4, 6, ff_pal
    ; ff_tail2_front (6x6): ff_tail2 FRONT
    SKROWS ff_tail2_front_rows, 6, 6
    SKROW "..V.Vw"
    SKROW "VVVwVw"
    SKROW "WWVwWw"
    SKROW "..W..."
    SKROW "......"
    SKROW "....Vw"
    SKROWS_END
    align 8
    SKBMP ff_tail2_front, ff_tail2_front_rows, 6, 6, ff_pal
    ; ff_tail2_back (6x6): ff_tail2 BACK
    SKROWS ff_tail2_back_rows, 6, 6
    SKROW "VV.VwV"
    SKROW "VV.VwV"
    SKROW "VVw.wW"
    SKROW ".Ww.w."
    SKROW "..w..."
    SKROW "V.w..V"
    SKROWS_END
    align 8
    SKBMP ff_tail2_back, ff_tail2_back_rows, 6, 6, ff_pal
    ; ff_tail2_left (4x6): ff_tail2 LEFT
    SKROWS ff_tail2_left_rows, 4, 6
    SKROW "V..."
    SKROW "VwVV"
    SKROW "VwVV"
    SKROW ".wVW"
    SKROW ".wV."
    SKROW "V..."
    SKROWS_END
    align 8
    SKBMP ff_tail2_left, ff_tail2_left_rows, 4, 6, ff_pal
    ; ff_tail2_right (4x6): ff_tail2 RIGHT
    SKROWS ff_tail2_right_rows, 4, 6
    SKROW "V..V"
    SKROW "VV.V"
    SKROW "VVVW"
    SKROW "VVV."
    SKROW ".WV."
    SKROW "..WV"
    SKROWS_END
    align 8
    SKBMP ff_tail2_right, ff_tail2_right_rows, 4, 6, ff_pal
    ; ff_tail3_front (4x6): ff_tail3 FRONT
    SKROWS ff_tail3_front_rows, 4, 6
    SKROW "C..."
    SKROW "Cj.."
    SKROW "JjCj"
    SKROW ".jCj"
    SKROW ".j.j"
    SKROW "C..j"
    SKROWS_END
    align 8
    SKBMP ff_tail3_front, ff_tail3_front_rows, 4, 6, ff_pal
    ; ff_tail3_back (4x6): ff_tail3 BACK
    SKROWS ff_tail3_back_rows, 4, 6
    SKROW "CjCj"
    SKROW "CjCj"
    SKROW "CjCj"
    SKROW "JJJJ"
    SKROW "...."
    SKROW "...."
    SKROWS_END
    align 8
    SKBMP ff_tail3_back, ff_tail3_back_rows, 4, 6, ff_pal
    ; ff_tail3_left (3x6): ff_tail3 LEFT
    SKROWS ff_tail3_left_rows, 3, 6
    SKROW "..j"
    SKROW "C.j"
    SKROW "CC."
    SKROW "CJ."
    SKROW "..."
    SKROW "..j"
    SKROWS_END
    align 8
    SKBMP ff_tail3_left, ff_tail3_left_rows, 3, 6, ff_pal
    ; ff_tail3_right (3x6): ff_tail3 RIGHT
    SKROWS ff_tail3_right_rows, 3, 6
    SKROW "..."
    SKROW ".C."
    SKROW "CCj"
    SKROW "CCJ"
    SKROW "..."
    SKROW "..."
    SKROWS_END
    align 8
    SKBMP ff_tail3_right, ff_tail3_right_rows, 3, 6, ff_pal
    ; ff_head_top (16x16): ff_head TOP
    SKROWS ff_head_top_rows, 16, 16
    SKROW "..S....S..S.k.kS"
    SKROW "S.S.S..S.kS.k.kS"
    SKROW "SkSkS.kS.kS.kS.."
    SKROW ".k.k..k......S.."
    SKROW ".k.............."
    SKROW "...............S"
    SKROW "S...........k..S"
    SKROW "S.........S.k.kS"
    SKROW "..S.S..S.kS...k."
    SKROW "..SkS.kS.k...Sk."
    SKROW ".kSkS.k......S.."
    SKROW ".k..........kS.."
    SKROW "S...........k..S"
    SKROW "S..............S"
    SKROW "...k..k..kS...kS"
    SKROW "...kS.kS.kS...k."
    SKROWS_END
    align 8
    SKBMP ff_head_top, ff_head_top_rows, 16, 16, ff_pal
    ; ff_head_back (16x16): ff_head BACK
    SKROWS ff_head_back_rows, 16, 16
    SKROW "..k...S....k...."
    SKROW "S.kS.kS.k..k...S"
    SKROW "S..S.k..kS..S.kS"
    SKROW "S.......kS..S.k."
    SKROW "..............k."
    SKROW "...........k...."
    SKROW "..k...S....k...."
    SKROW "..kS.kS........S"
    SKROW "S.kS.kS.kS..S.kS"
    SKROW "S..S....kS..S.k."
    SKROW "...........k..k."
    SKROW "...........k...."
    SKROW "..k........k...."
    SKROW "..k..k.........."
    SKROW "...S.kS..S..S.kS"
    SKROW "S..S.kS.kS..S.kS"
    SKROWS_END
    align 8
    SKBMP ff_head_back, ff_head_back_rows, 16, 16, ff_pal
    ; ff_head_right (16x16): ff_head RIGHT
    SKROWS ff_head_right_rows, 16, 16
    SKROW "S.k.kS.....S...k"
    SKROW "S.kSkSkSk.kSk..k"
    SKROW "...Sk.kSkSk.kS.."
    SKROW ".........S...S.."
    SKROW "................"
    SKROW "S.k..S.........."
    SKROW "S.k..S.Sk..S...."
    SKROW ".....S.Sk.kS...k"
    SKROW "...Sk.kS..k.kS.k"
    SKROW "...Sk.k..S..kS.."
    SKROW "S.kS.....S......"
    SKROW "S.k......S.S...."
    SKROW "S....S..k.kS...k"
    SKROW ".....S..k.kS.S.k"
    SKROW ".....SkS....kS.."
    SKROW "..kSk.kS....kS.."
    SKROWS_END
    align 8
    SKBMP ff_head_right, ff_head_right_rows, 16, 16, ff_pal
    ; ff_head_left (16x16): ff_head LEFT
    SKROWS ff_head_left_rows, 16, 16
    SKROW "S.SkSk..k.....S."
    SKROW "SkSkSkS.k..k..Sk"
    SKROW ".k.kS.S.kS.kSkSk"
    SKROW ".k.......S..Sk.."
    SKROW "............S..."
    SKROW "S.S............."
    SKROW "S.Sk..S........k"
    SKROW "Sk.k.kS.kS...kSk"
    SKROW ".k..Sk..kS.kSkS."
    SKROW ".k..S...kS.kS.S."
    SKROW "................"
    SKROW "..Sk..S........k"
    SKROW "S.Sk.kS........k"
    SKROW "S....k..kS...kS."
    SKROW "........kS.k.kS."
    SKROW ".k..S....S.kS..."
    SKROWS_END
    align 8
    SKBMP ff_head_left, ff_head_left_rows, 16, 16, ff_pal
    ; ff_face (16x16): ff_head FRONT
    SKROWS ff_face_rows, 16, 16
    SKROW "..kS.S.PqS....Sk"
    SKROW "S.kSkSkpqSk..kSk"
    SKROW "S...k.kpq.kS.k.."
    SKROW "......kpq..S.k.."
    SKROW ".......pq......."
    SKROW "..KKK..p...KKK.."
    SKROW "..kSkK...SK...S."
    SKROW "...Yxy..kSYxy.Sk"
    SKROW "S..yxykSk.yxy..k"
    SKROW "jccyxykS..yxyccj"
    SKROW "cckkkkkS.kkkkkjc"
    SKROW "cjccP....S.Pcjcc"
    SKROW "jccjp....S.pjccj"
    SKROW "ccjcpS...Skpccjc"
    SKROW "cjccjS..k.kccjcc"
    SKROW "jccjcSk.k..cjccj"
    SKROWS_END
    align 8
    SKBMP ff_face, ff_face_rows, 16, 16, ff_pal
    ; ff_snout_front (6x5): ff_snout FRONT
    SKROWS ff_snout_front_rows, 6, 5
    SKROW "CxXXx."
    SKROW "Cxxxx."
    SKROW "c.jj.."
    SKROW "MMMMMM"
    SKROW "jccccj"
    SKROWS_END
    align 8
    SKBMP ff_snout_front, ff_snout_front_rows, 6, 5, ff_pal
    ; ff_fang_front (1x2): ff_fang_l FRONT
    SKROWS ff_fang_front_rows, 1, 2
    SKROW "B"
    SKROW "u"
    SKROWS_END
    align 8
    SKBMP ff_fang_front, ff_fang_front_rows, 1, 2, ff_pal
    ; ff_ear_front (5x6): ff_ear_l FRONT
    SKROWS ff_ear_front_rows, 5, 6
    SKROW "__s__"
    SKROW "_Ssk_"
    SKROW "_Smk_"
    SKROW "Smmmk"
    SKROW "Smmmk"
    SKROW "SmMmk"
    SKROWS_END
    align 8
    SKBMP ff_ear_front, ff_ear_front_rows, 5, 6, ff_pal
    ; ff_ear_back (5x6): ff_ear_l BACK
    SKROWS ff_ear_back_rows, 5, 6
    SKROW "__s__"
    SKROW "_ksK_"
    SKROW "_ksK_"
    SKROW "ksssK"
    SKROW "ksssK"
    SKROW "ksssK"
    SKROWS_END
    align 8
    SKBMP ff_ear_back, ff_ear_back_rows, 5, 6, ff_pal
    ; ff_ear_side (2x6): ff_ear_l LEFT, ff_ear_l RIGHT
    SKROWS ff_ear_side_rows, 2, 6
    SKROW "Ss"
    SKROW "Ss"
    SKROW "Ss"
    SKROW "Ss"
    SKROW "Ss"
    SKROW "kk"
    SKROWS_END
    align 8
    SKBMP ff_ear_side, ff_ear_side_rows, 2, 6, ff_pal
    ; ff_ear_top (5x2): ff_ear_l TOP
    SKROWS ff_ear_top_rows, 5, 2
    SKROW "__s__"
    SKROW "__s__"
    SKROWS_END
    align 8
    SKBMP ff_ear_top, ff_ear_top_rows, 5, 2, ff_pal
    ; ff_tuft_left (6x5): ff_tuft_l LEFT
    SKROWS ff_tuft_left_rows, 6, 5
    SKROW "CccCcj"
    SKROW "ccCcj_"
    SKROW "cCccCj"
    SKROW "Cccj__"
    SKROW "ccCcj_"
    SKROWS_END
    align 8
    SKBMP ff_tuft_left, ff_tuft_left_rows, 6, 5, ff_pal
    ; ff_tuft_right (6x5): ff_tuft_l RIGHT
    SKROWS ff_tuft_right_rows, 6, 5
    SKROW "jcCccC"
    SKROW "_jcCcc"
    SKROW "jCccCc"
    SKROW "__jccC"
    SKROW "_jcCcc"
    SKROWS_END
    align 8
    SKBMP ff_tuft_right, ff_tuft_right_rows, 6, 5, ff_pal
    ; ff_tuft_front (1x5): ff_tuft_l FRONT
    SKROWS ff_tuft_front_rows, 1, 5
    SKROW "c"
    SKROW "c"
    SKROW "c"
    SKROW "c"
    SKROW "_"
    SKROWS_END
    align 8
    SKBMP ff_tuft_front, ff_tuft_front_rows, 1, 5, ff_pal
    ; ff_tuft_back (1x5): ff_tuft_l BACK
    SKROWS ff_tuft_back_rows, 1, 5
    SKROW "c"
    SKROW "c"
    SKROW "c"
    SKROW "c"
    SKROW "_"
    SKROWS_END
    align 8
    SKBMP ff_tuft_back, ff_tuft_back_rows, 1, 5, ff_pal
    ; ff_leg_front (6x24): ff_leg_l FRONT
    SKROWS ff_leg_front_rows, 6, 24
    SKROW "Dn...."
    SKROW "Dn...."
    SKROW "DnD.nD"
    SKROW "DnD.nD"
    SKROW "D.D..."
    SKROW "D....."
    SKROW "Dn..nD"
    SKROW "Dn..ND"
    SKROW "DnD..."
    SKROW "D.N..."
    SKROW "D....."
    SKROW "D...nD"
    SKROW "D...nD"
    SKROW "DnD.nD"
    SKROW "DnD.n."
    SKROW "DnN..."
    SKROW "D....D"
    SKROW "D....D"
    SKROW "D....."
    SKROW "DnD.n."
    SKROW "DnD.n."
    SKROW "D.N.n."
    SKROW "D....D"
    SKROW "D....N"
    SKROWS_END
    align 8
    SKBMP ff_leg_front, ff_leg_front_rows, 6, 24, ff_pal
    ; ff_leg_back (6x24): ff_leg_l BACK
    SKROWS ff_leg_back_rows, 6, 24
    SKROW "D...Dn"
    SKROW "D.DnDn"
    SKROW "DnDnD."
    SKROW "DNDnD."
    SKROW "D.Dn.."
    SKROW "D....."
    SKROW "Dn...n"
    SKROW "DN.n.n"
    SKROW "D..nDN"
    SKROW "D.DND."
    SKROW "DnD.D."
    SKROW "Dn..Dn"
    SKROW "D..n.n"
    SKROW "D..n.n"
    SKROW "D.DNDn"
    SKROW "D.D.D."
    SKROW "DnD.D."
    SKROW "Dn...n"
    SKROW "Dn.n.n"
    SKROW "DnDn.n"
    SKROW "D.DN.n"
    SKROW "D...D."
    SKROW "D...D."
    SKROW "D...Dn"
    SKROWS_END
    align 8
    SKBMP ff_leg_back, ff_leg_back_rows, 6, 24, ff_pal
    ; ff_leg_left (6x24): ff_leg_l LEFT
    SKROWS ff_leg_left_rows, 6, 24
    SKROW "D.D.n."
    SKROW "D.D.nD"
    SKROW "Dn...N"
    SKROW "DN...."
    SKROW "D.D..."
    SKROW "D.D..."
    SKROW "D.N.nD"
    SKROW "D...nD"
    SKROW "Dn..n."
    SKROW "Dn..N."
    SKROW "Dn...."
    SKROW "DnD..."
    SKROW "D.D..D"
    SKROW "D...nD"
    SKROW "D...nD"
    SKROW "DnD.n."
    SKROW "DnD.n."
    SKROW "DnD..."
    SKROW "Dn...."
    SKROW "D....D"
    SKROW "D.D.nN"
    SKROW "D.D.N."
    SKROW "D.D..."
    SKROW "Dn...D"
    SKROWS_END
    align 8
    SKBMP ff_leg_left, ff_leg_left_rows, 6, 24, ff_pal
    ; ff_leg_right (6x24): ff_leg_l RIGHT
    SKROWS ff_leg_right_rows, 6, 24
    SKROW "...D.n"
    SKROW "D.nD.n"
    SKROW "D.nD.n"
    SKROW "N....."
    SKROW "......"
    SKROW ".....n"
    SKROW "..nD.N"
    SKROW "..nD.."
    SKROW "D.nD.."
    SKROW "D....."
    SKROW "......"
    SKROW ".....n"
    SKROW "D....n"
    SKROW "N.nD.n"
    SKROW "..nD.n"
    SKROW "...D.."
    SKROW "...D.."
    SKROW ".....n"
    SKROW "D....n"
    SKROW "D.nD.."
    SKROW "D.nD.."
    SKROW "..ND.n"
    SKROW ".....n"
    SKROW ".....n"
    SKROWS_END
    align 8
    SKBMP ff_leg_right, ff_leg_right_rows, 6, 24, ff_pal
    ; ff_wrap_front (7x9): ff_wrap_l FRONT
    SKROWS ff_wrap_front_rows, 7, 9
    SKROW "V.V.VVV"
    SKROW "V....Vw"
    SKROW "VwV.wVw"
    SKROW "eeeeeee"
    SKROW "lllllll"
    SKROW "eeeeeee"
    SKROW "VwV.WVw"
    SKROW "VwV.wVW"
    SKROW "WWWWWWW"
    SKROWS_END
    align 8
    SKBMP ff_wrap_front, ff_wrap_front_rows, 7, 9, ff_pal
    ; ff_wrap_back (7x9): ff_wrap_l BACK
    SKROWS ff_wrap_back_rows, 7, 9
    SKROW "V.V.V.V"
    SKROW "V.W...w"
    SKROW "V.wVwVw"
    SKROW "eeeeeee"
    SKROW "lllllll"
    SKROW "eeeeeee"
    SKROW "V.wVwVw"
    SKROW "V.WVwVW"
    SKROW "WWWWWWW"
    SKROWS_END
    align 8
    SKBMP ff_wrap_back, ff_wrap_back_rows, 7, 9, ff_pal
    ; ff_wrap_left (8x9): ff_wrap_l LEFT
    SKROWS ff_wrap_left_rows, 8, 9
    SKROW "V.V.V.V."
    SKROW "V.....w."
    SKROW "VwV.wVWV"
    SKROW "eeeeeeee"
    SKROW "llllllll"
    SKROW "eeeeeeee"
    SKROW "VwV.wVw."
    SKROW ".WV.wWwV"
    SKROW "WWWWWWWW"
    SKROWS_END
    align 8
    SKBMP ff_wrap_left, ff_wrap_left_rows, 8, 9, ff_pal
    ; ff_wrap_right (8x9): ff_wrap_l RIGHT
    SKROWS ff_wrap_right_rows, 8, 9
    SKROW "V.V.V.V."
    SKROW "V...w.wV"
    SKROW "VwV.wV.W"
    SKROW "eeeeeeee"
    SKROW "llllllll"
    SKROW "eeeeeeee"
    SKROW "WwV.WVwV"
    SKROW ".WV..VwV"
    SKROW "WWWWWWWW"
    SKROWS_END
    align 8
    SKBMP ff_wrap_right, ff_wrap_right_rows, 8, 9, ff_pal
    ; ff_foot_front (7x4): ff_foot_l FRONT
    SKROWS ff_foot_front_rows, 7, 4
    SKROW "..NDNn."
    SKROW "..NNNnD"
    SKROW "D.N.NnD"
    SKROW "NINININ"
    SKROWS_END
    align 8
    SKBMP ff_foot_front, ff_foot_front_rows, 7, 4, ff_pal
    ; ff_foot_back (7x4): ff_foot_l BACK
    SKROWS ff_foot_back_rows, 7, 4
    SKROW "...Dn.."
    SKROW "D.nDn.."
    SKROW "D.n.nDn"
    SKROW "N.n..NN"
    SKROWS_END
    align 8
    SKBMP ff_foot_back, ff_foot_back_rows, 7, 4, ff_pal
    ; ff_foot_left (10x4): ff_foot_l LEFT
    SKROWS ff_foot_left_rows, 10, 4
    SKROW "D....D...."
    SKROW "DnD..D.n.."
    SKROW ".nD.n..nDn"
    SKROW ".nN.n...Dn"
    SKROWS_END
    align 8
    SKBMP ff_foot_left, ff_foot_left_rows, 10, 4, ff_pal
    ; ff_foot_right (10x4): ff_foot_l RIGHT
    SKROWS ff_foot_right_rows, 10, 4
    SKROW "D.n......n"
    SKROW "D.nD.D...n"
    SKROW "D.nNnDnD.n"
    SKROW "....nNnD.."
    SKROWS_END
    align 8
    SKBMP ff_foot_right, ff_foot_right_rows, 10, 4, ff_pal
    ; ff_foot_top (7x10): ff_foot_l TOP
    SKROWS ff_foot_top_rows, 7, 10
    SKROW "......."
    SKROW "D......"
    SKROW "NnDnD.n"
    SKROW ".nDnD.n"
    SKROW "..Dn..."
    SKROW "...N..."
    SKROW "......n"
    SKROW "D.N.N.n"
    SKROW "NnNnN.n"
    SKROW ".nNnN.n"
    SKROWS_END
    align 8
    SKBMP ff_foot_top, ff_foot_top_rows, 7, 10, ff_pal
    ; ff_hand_front (6x22): ff_arm_l FRONT
    SKROWS ff_hand_front_rows, 6, 22
    SKROW "S..S.S"
    SKROW "S.kKkK"
    SKROW "S.k.K."
    SKROW "S.k..."
    SKROW "S..S.S"
    SKROW "S..S.S"
    SKROW "S.kK.K"
    SKROW "S.K.k."
    SKROW "S...k."
    SKROW "S...K."
    SKROW "S.kS.."
    SKROW "S.kS.S"
    SKROW "S.kK.S"
    SKROW "pppppp"
    SKROW "qqqqqq"
    SKROW "S..Sk."
    SKROW "pppp.."
    SKROW "KKKKKK"
    SKROW "Sssssk"
    SKROW "Sskssk"
    SKROW "Sssksk"
    SKROW "IkIkIk"
    SKROWS_END
    align 8
    SKBMP ff_hand_front, ff_hand_front_rows, 6, 22, ff_pal
    ; ff_hand_back (6x22): ff_arm_l BACK
    SKROWS ff_hand_back_rows, 6, 22
    SKROW "S.kSk."
    SKROW "S.kSkS"
    SKROW "S.kS.S"
    SKROW "S.kS.S"
    SKROW "S....S"
    SKROW "S...k."
    SKROW "S..Sk."
    SKROW "S..S.S"
    SKROW "S.kS.S"
    SKROW "S.kK.K"
    SKROW "S...k."
    SKROW "S...k."
    SKROW "S.k.k."
    SKROW "pppppp"
    SKROW "qqqqqq"
    SKROW "S.k..S"
    SKROW "pppp.S"
    SKROW "KKKKKK"
    SKROW "Sssssk"
    SKROW "Sssssk"
    SKROW "Sssssk"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP ff_hand_back, ff_hand_back_rows, 6, 22, ff_pal
    ; ff_hand_left (6x22): ff_arm_l LEFT
    SKROWS ff_hand_left_rows, 6, 22
    SKROW "S.S..."
    SKROW "SkS..."
    SKROW "Sk..kS"
    SKROW "Sk..kS"
    SKROW "S...KS"
    SKROW "S....."
    SKROW "S.S..."
    SKROW "SkS..."
    SKROW "Sk...."
    SKROW "Sk..kS"
    SKROW "S...kS"
    SKROW "S...k."
    SKROW "SkS..."
    SKROW "pppppp"
    SKROW "qqqqqq"
    SKROW "SK...S"
    SKROW "ppppkS"
    SKROW "KKKKKK"
    SKROW "Sssssk"
    SKROW "Sssssk"
    SKROW "Sssssk"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP ff_hand_left, ff_hand_left_rows, 6, 22, ff_pal
    ; ff_hand_right (6x22): ff_arm_l RIGHT
    SKROWS ff_hand_right_rows, 6, 22
    SKROW "S....S"
    SKROW "S..S.S"
    SKROW "S.kSkK"
    SKROW "S.kSk."
    SKROW "S.kS.."
    SKROW "S....."
    SKROW "S....S"
    SKROW "S.k..S"
    SKROW "S.k.kS"
    SKROW "S.kSkK"
    SKROW "S.KSk."
    SKROW "S....."
    SKROW "S....S"
    SKROW "pppppp"
    SKROW "qqqqqq"
    SKROW "S.kS.K"
    SKROW "pppp.."
    SKROW "KKKKKK"
    SKROW "Sssssk"
    SKROW "Sssssk"
    SKROW "Sssssk"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP ff_hand_right, ff_hand_right_rows, 6, 22, ff_pal
    ; ff_pelt_front (6x8): ff_pelt_l FRONT
    SKROWS ff_pelt_front_rows, 6, 8
    SKROW "......"
    SKROW "VwV..."
    SKROW "VwV.wV"
    SKROW "VWV.wW"
    SKROW ".wV.wV"
    SKROW "VwV.wV"
    SKROW "www.wW"
    SKROW "WWWWWW"
    SKROWS_END
    align 8
    SKBMP ff_pelt_front, ff_pelt_front_rows, 6, 8, ff_pal
    ; ff_pelt_back (6x8): ff_pelt_l BACK
    SKROWS ff_pelt_back_rows, 6, 8
    SKROW "...V.V"
    SKROW "V.wVwV"
    SKROW "V.wVwV"
    SKROW "W.wVwW"
    SKROW "V.wVw."
    SKROW "W....V"
    SKROW "w.wVwV"
    SKROW "WWWWWW"
    SKROWS_END
    align 8
    SKBMP ff_pelt_back, ff_pelt_back_rows, 6, 8, ff_pal
    ; ff_pelt_left (6x8): ff_pelt_l LEFT
    SKROWS ff_pelt_left_rows, 6, 8
    SKROW "Vw...V"
    SKROW "Vw...V"
    SKROW "VwV.wV"
    SKROW "VWV.WW"
    SKROW "V.W.wV"
    SKROW "VwV.wV"
    SKROW "wWw.w."
    SKROW "WWWWWW"
    SKROWS_END
    align 8
    SKBMP ff_pelt_left, ff_pelt_left_rows, 6, 8, ff_pal
    ; ff_pelt_right (6x8): ff_pelt_l RIGHT
    SKROWS ff_pelt_right_rows, 6, 8
    SKROW "..Vw.w"
    SKROW "V.VW.w"
    SKROW "Vw.wVw"
    SKROW "VWVwVw"
    SKROW "V.VwVw"
    SKROW "VwVwVw"
    SKROW "wwwwww"
    SKROW "WWWWWW"
    SKROWS_END
    align 8
    SKBMP ff_pelt_right, ff_pelt_right_rows, 6, 8, ff_pal
    ; ff_band_front (6x3): ff_band_l FRONT
    SKROWS ff_band_front_rows, 6, 3
    SKROW "LLLLLL"
    SKROW "..BB.."
    SKROW "eeeeee"
    SKROWS_END
    align 8
    SKBMP ff_band_front, ff_band_front_rows, 6, 3, ff_pal
    ; ff_band_back (6x3): ff_band_l BACK
    SKROWS ff_band_back_rows, 6, 3
    SKROW "LLLLLL"
    SKROW "......"
    SKROW "eeeeee"
    SKROWS_END
    align 8
    SKBMP ff_band_back, ff_band_back_rows, 6, 3, ff_pal
    ; ff_band_left (6x3): ff_band_l LEFT
    SKROWS ff_band_left_rows, 6, 3
    SKROW "LLLLLL"
    SKROW "......"
    SKROW "eeeeee"
    SKROWS_END
    align 8
    SKBMP ff_band_left, ff_band_left_rows, 6, 3, ff_pal
    ; ff_band_right (6x3): ff_band_l RIGHT
    SKROWS ff_band_right_rows, 6, 3
    SKROW "LLLLLL"
    SKROW "......"
    SKROW "eeeeee"
    SKROWS_END
    align 8
    SKBMP ff_band_right, ff_band_right_rows, 6, 3, ff_pal
    ; ff_fist_front (6x5): ff_fist_l FRONT
    SKROWS ff_fist_front_rows, 6, 5
    SKROW "KKKKKK"
    SKROW "SkSkSK"
    SKROW "SkSkS."
    SKROW ".kSk.."
    SKROW "IKIKIK"
    SKROWS_END
    align 8
    SKBMP ff_fist_front, ff_fist_front_rows, 6, 5, ff_pal
    ; ff_fist_back (6x5): ff_fist_l BACK
    SKROWS ff_fist_back_rows, 6, 5
    SKROW "KKKKKK"
    SKROW ".kS.k."
    SKROW "SkS.kS"
    SKROW "S...KK"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP ff_fist_back, ff_fist_back_rows, 6, 5, ff_pal
    ; ff_fist_right (6x5): ff_fist_l RIGHT
    SKROWS ff_fist_right_rows, 6, 5
    SKROW "KKKKKK"
    SKROW ".kS.Ss"
    SKROW "S.Skss"
    SKROW "SkKkKK"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP ff_fist_right, ff_fist_right_rows, 6, 5, ff_pal
    ; ff_fist_left (6x5): ff_fist_l LEFT
    SKROWS ff_fist_left_rows, 6, 5
    SKROW "KKKKKK"
    SKROW "SsSk.K"
    SKROW "ssSKS."
    SKROW ".K..S."
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP ff_fist_left, ff_fist_left_rows, 6, 5, ff_pal

section .data
SKMODEL_BEGIN m_folk_beastfolk, 32, 0, 11, 26, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART ff_torso, -8, 24, -4, 16, 22, 8, 0, 0              ; fur vest, crossed leather straps, belt
    PART ff_ruff, -7, 42, -5, 14, 5, 10, 4, 0               ; shaggy fur collar
    PART ff_necklace, -5, 38, -5, 10, 4, 1, 0, SKPF_CUTOUT  ; bone necklace on the chest
    PART ff_fang_p, -1, 33, -5, 2, 5, 1, 0, SKPF_CUTOUT     ; big fang hanging from the necklace
    PART ff_tail1, -2, 22, 4, 4, 6, 4, 0, 0                 ; tail, root
    PART ff_tail2, -3, 26, 7, 6, 6, 4, 0, 0                 ; tail, bushy middle
    PART ff_tail3, -2, 31, 10, 4, 6, 3, 0, 0                ; tail, pale tip
    SKBONE BK_HEAD, 0, 0, 0.00
    PART ff_head, -8, 46, -8, 16, 16, 16, 0, 0              ; the 16 texel head
    PART ff_snout, -3, 47, -13, 6, 5, 5, 0, 0               ; muzzle with a black nose
    PART ff_fang_l, -3, 45, -13, 1, 2, 1, 0, 0              ; fang (the right one shares its skin)
    PART_AS ff_fang_r, ff_fang_l, 2, 45, -13, 0, 0
    PART ff_ear_l, -8, 62, -3, 5, 6, 2, 0, SKPF_CUTOUT      ; pointed ear (the right one shares its skin)
    PART_AS ff_ear_r, ff_ear_l, 3, 62, -3, 0, SKPF_CUTOUT
    PART ff_tuft_l, -9, 47, -4, 1, 5, 6, 0, SKPF_CUTOUT     ; cheek fur (the right one shares its skin)
    PART_AS ff_tuft_r, ff_tuft_l, 8, 47, -4, 0, SKPF_CUTOUT
    SKBONE BK_LLEG, 24, 0, 1.00
    PART ff_leg_l, -6, 0, -3, 6, 24, 6, 0, 0                ; dark fur legs
    PART ff_wrap_l, -7, 4, -4, 7, 9, 8, 0, 0                ; fur wrapped round the shin, lashed with cord
    PART ff_foot_l, -7, 0, -6, 7, 4, 10, 0, 0               ; paw with claws
    SKBONE BK_RLEG, 24, 0, -1.00
    PART_AS ff_leg_r, ff_leg_l, 0, 0, -3, 0, 0
    PART_AS ff_wrap_r, ff_wrap_l, 0, 4, -4, 0, 0
    PART_AS ff_foot_r, ff_foot_l, 0, 0, -6, 0, 0
    SKBONE BK_LARM, 44, 0, -1.00
    PART ff_arm_l, -14, 24, -3, 6, 22, 6, 0, 0              ; fur arm, war paint, clawed hand
    PART ff_pelt_l, -14, 39, -3, 6, 8, 6, 10, 0             ; shaggy shoulder pelt
    PART ff_band_l, -14, 33, -3, 6, 3, 6, 8, 0              ; leather armband with a bone stud
    PART ff_fist_l, -14, 24, -3, 6, 5, 6, 10, 0             ; clawed fist
    SKBONE BK_RARM, 44, 0, 1.00
    PART_AS ff_arm_r, ff_arm_l, 8, 24, -3, 0, 0
    PART_AS ff_pelt_r, ff_pelt_l, 8, 39, -3, 10, 0
    PART_AS ff_band_r, ff_band_l, 8, 33, -3, 8, 0
    PART_AS ff_fist_r, ff_fist_l, 8, 24, -3, 10, 0
SKMODEL_PAINT
    ; --- ff_torso: fur vest, pale belly fur between crossed leather straps, a belt with a bone buckle, a darker hem
    SK_FILL ff_torso, SKM_ALL, FF_VEST_2, 15
    SK_BMP ff_torso, SKF_FRONT, 0, 0, ff_torso_front
    SK_BMP ff_torso, SKF_BACK, 0, 0, ff_torso_back
    SK_BMP ff_torso, SKF_RIGHT, 0, 0, ff_torso_side
    SK_BMP ff_torso, SKF_LEFT, 0, 0, ff_torso_side
    SK_RECT ff_torso, SKF_BOTTOM, 0, 0, 16, 8, FF_VEST_4, 0
    SK_GRAD ff_torso, SKM_SIDES, 272, 224
    ; --- ff_ruff: shaggy collar fur; ff_necklace: bone beads on a cord; ff_fang_p: a big fang
    SK_FILL ff_ruff, SKM_ALL, FF_CREAM_2, 15
    SK_BMP ff_ruff, SKF_FRONT, 0, 0, ff_ruff_front
    SK_BMP ff_ruff, SKF_BACK, 0, 0, ff_ruff_back
    SK_BMP ff_ruff, SKF_LEFT, 0, 0, ff_ruff_left
    SK_BMP ff_ruff, SKF_RIGHT, 0, 0, ff_ruff_right
    SK_RECT ff_ruff, SKF_TOP, 0, 0, 14, 10, FF_CREAM_1, 15
    SK_RECT ff_ruff, SKF_BOTTOM, 0, 0, 14, 10, FF_CREAM_4, 0
    SK_GRAD ff_ruff, SKM_SIDES, 272, 224
    SK_FILL ff_necklace, SKM_ALL, AC_LEATHER_3, 0
    SK_BMP ff_necklace, SKF_FRONT, 0, 0, ff_necklace_front
    SK_RECT ff_necklace, SKF_TOP, 0, 0, 10, 1, AC_LEATHER_2, 0
    SK_RECT ff_necklace, SKF_BOTTOM, 0, 0, 10, 1, AC_LEATHER_4, 0
    SK_FILL ff_fang_p, SKM_ALL, AC_BONE_2, 0
    SK_BMP ff_fang_p, SKF_FRONT, 0, 0, ff_fang_p_front
    SK_BMP ff_fang_p, SKF_BACK, 0, 0, ff_fang_p_back
    SK_RECT ff_fang_p, SKF_LEFT, 0, 0, 1, 4, AC_BONE_3, 0
    SK_RECT ff_fang_p, SKF_RIGHT, 0, 0, 1, 4, AC_BONE_3, 0
    SK_RECT ff_fang_p, SKF_TOP, 0, 0, 2, 1, AC_BONE_1, 0
    SK_RECT ff_fang_p, SKF_BOTTOM, 0, 0, 2, 1, AC_BONE_3, 0
    ; --- ff_tail1..3: fur, a pale tip
    SK_FILL ff_tail1, SKM_ALL, FF_VEST_2, 15
    SK_BMP ff_tail1, SKF_FRONT, 0, 0, ff_tail1_front
    SK_BMP ff_tail1, SKF_BACK, 0, 0, ff_tail1_back
    SK_BMP ff_tail1, SKF_LEFT, 0, 0, ff_tail1_left
    SK_BMP ff_tail1, SKF_RIGHT, 0, 0, ff_tail1_right
    SK_RECT ff_tail1, SKF_TOP, 0, 0, 4, 4, FF_VEST_1, 15
    SK_RECT ff_tail1, SKF_BOTTOM, 0, 0, 4, 4, FF_VEST_4, 0
    SK_GRAD ff_tail1, SKM_SIDES, 272, 224
    SK_FILL ff_tail2, SKM_ALL, FF_VEST_2, 15
    SK_BMP ff_tail2, SKF_FRONT, 0, 0, ff_tail2_front
    SK_BMP ff_tail2, SKF_BACK, 0, 0, ff_tail2_back
    SK_BMP ff_tail2, SKF_LEFT, 0, 0, ff_tail2_left
    SK_BMP ff_tail2, SKF_RIGHT, 0, 0, ff_tail2_right
    SK_RECT ff_tail2, SKF_TOP, 0, 0, 6, 4, FF_VEST_1, 15
    SK_RECT ff_tail2, SKF_BOTTOM, 0, 0, 6, 4, FF_VEST_4, 0
    SK_GRAD ff_tail2, SKM_SIDES, 272, 224
    SK_FILL ff_tail3, SKM_ALL, FF_CREAM_2, 15
    SK_BMP ff_tail3, SKF_FRONT, 0, 0, ff_tail3_front
    SK_BMP ff_tail3, SKF_BACK, 0, 0, ff_tail3_back
    SK_BMP ff_tail3, SKF_LEFT, 0, 0, ff_tail3_left
    SK_BMP ff_tail3, SKF_RIGHT, 0, 0, ff_tail3_right
    SK_RECT ff_tail3, SKF_TOP, 0, 0, 4, 3, FF_CREAM_1, 15
    SK_RECT ff_tail3, SKF_BOTTOM, 0, 0, 4, 3, FF_CREAM_4, 0
    SK_GRAD ff_tail3, SKM_SIDES, 272, 224
    ; --- ff_head: brown-grey fur, amber slit eyes under heavy brows, pale cheeks, white war paint (the snout covers the middle)
    SK_FILL ff_head, SKM_ALL, FF_FUR_2, 15
    SK_GRAD ff_head, SKM_SIDES, 272, 224
    SK_BMP ff_head, SKF_TOP, 0, 0, ff_head_top
    SK_BMP ff_head, SKF_BACK, 0, 0, ff_head_back
    SK_BMP ff_head, SKF_RIGHT, 0, 0, ff_head_right
    SK_BMP ff_head, SKF_LEFT, 0, 0, ff_head_left
    SK_RECT ff_head, SKF_BOTTOM, 0, 0, 16, 16, FF_FUR_4, 0
    SK_BMP ff_head, SKF_FRONT, 0, 0, ff_face
    ; --- ff_snout: muzzle: a black nose, a mouth line with fangs; ff_fang_l (shared with ff_fang_r)
    SK_FILL ff_snout, SKM_ALL, FF_CREAM_2, 7
    SK_BMP ff_snout, SKF_FRONT, 0, 0, ff_snout_front
    SK_RECT ff_snout, SKF_TOP, 0, 0, 6, 5, FF_CREAM_1, 7
    SK_RECT ff_snout, SKF_TOP, 2, 0, 2, 5, FF_CREAM_2, 0
    SK_RECT ff_snout, SKF_BOTTOM, 0, 0, 6, 5, FF_CREAM_4, 0
    SK_RECT ff_snout, SKF_LEFT, 0, 3, 5, 1, RGBO(122, 56, 60), 0
    SK_RECT ff_snout, SKF_LEFT, 0, 4, 5, 1, FF_CREAM_3, 0
    SK_RECT ff_snout, SKF_RIGHT, 0, 3, 5, 1, RGBO(122, 56, 60), 0
    SK_RECT ff_snout, SKF_RIGHT, 0, 4, 5, 1, FF_CREAM_3, 0
    SK_GRAD ff_snout, SKM_SIDES, 272, 224
    SK_FILL ff_fang_l, SKM_ALL, AC_BONE_2, 0
    SK_BMP ff_fang_l, SKF_FRONT, 0, 0, ff_fang_front
    SK_RECT ff_fang_l, SKF_LEFT, 0, 0, 1, 2, AC_BONE_3, 0
    SK_RECT ff_fang_l, SKF_RIGHT, 0, 0, 1, 2, AC_BONE_3, 0
    ; --- ff_ear_l (shared with ff_ear_r): pointed, pink inside; ff_tuft_l: cheek fur
    SK_FILL ff_ear_l, SKM_ALL, FF_FUR_2, 15
    SK_BMP ff_ear_l, SKF_FRONT, 0, 0, ff_ear_front
    SK_BMP ff_ear_l, SKF_BACK, 0, 0, ff_ear_back
    SK_BMP ff_ear_l, SKF_LEFT, 0, 0, ff_ear_side
    SK_BMP ff_ear_l, SKF_RIGHT, 0, 0, ff_ear_side
    SK_BMP ff_ear_l, SKF_TOP, 0, 0, ff_ear_top
    SK_RECT ff_ear_l, SKF_BOTTOM, 0, 0, 5, 2, FF_FUR_4, 0
    SK_FILL ff_tuft_l, SKM_ALL, FF_CREAM_2, 15
    SK_BMP ff_tuft_l, SKF_LEFT, 0, 0, ff_tuft_left
    SK_BMP ff_tuft_l, SKF_RIGHT, 0, 0, ff_tuft_right
    SK_BMP ff_tuft_l, SKF_FRONT, 0, 0, ff_tuft_front
    SK_BMP ff_tuft_l, SKF_BACK, 0, 0, ff_tuft_back
    SK_RECT ff_tuft_l, SKF_TOP, 0, 0, 1, 6, FF_CREAM_1, 0
    SK_RECT ff_tuft_l, SKF_BOTTOM, 0, 0, 1, 6, FF_CREAM_4, 0
    ; --- ff_leg_l (shared with ff_leg_r): dark fur; ff_wrap_l: fur lashed round the shin; ff_foot_l: clawed paw
    SK_FILL ff_leg_l, SKM_ALL, FF_DARK_2, 15
    SK_BMP ff_leg_l, SKF_FRONT, 0, 0, ff_leg_front
    SK_BMP ff_leg_l, SKF_BACK, 0, 0, ff_leg_back
    SK_BMP ff_leg_l, SKF_LEFT, 0, 0, ff_leg_left
    SK_BMP ff_leg_l, SKF_RIGHT, 0, 0, ff_leg_right
    SK_RECT ff_leg_l, SKF_BOTTOM, 0, 0, 6, 6, FF_DARK_4, 0
    SK_GRAD ff_leg_l, SKM_SIDES, 272, 224
    SK_FILL ff_wrap_l, SKM_ALL, FF_VEST_2, 15
    SK_BMP ff_wrap_l, SKF_FRONT, 0, 0, ff_wrap_front
    SK_BMP ff_wrap_l, SKF_BACK, 0, 0, ff_wrap_back
    SK_BMP ff_wrap_l, SKF_LEFT, 0, 0, ff_wrap_left
    SK_BMP ff_wrap_l, SKF_RIGHT, 0, 0, ff_wrap_right
    SK_RECT ff_wrap_l, SKF_TOP, 0, 0, 7, 8, FF_VEST_1, 15
    SK_RECT ff_wrap_l, SKF_BOTTOM, 0, 0, 7, 8, FF_VEST_4, 0
    SK_GRAD ff_wrap_l, SKM_SIDES, 272, 224
    SK_FILL ff_foot_l, SKM_ALL, FF_DARK_2, 15
    SK_BMP ff_foot_l, SKF_FRONT, 0, 0, ff_foot_front
    SK_BMP ff_foot_l, SKF_BACK, 0, 0, ff_foot_back
    SK_BMP ff_foot_l, SKF_LEFT, 0, 0, ff_foot_left
    SK_BMP ff_foot_l, SKF_RIGHT, 0, 0, ff_foot_right
    SK_BMP ff_foot_l, SKF_TOP, 0, 0, ff_foot_top
    SK_RECT ff_foot_l, SKF_BOTTOM, 0, 0, 7, 10, FF_DARK_4, 0
    ; --- ff_arm_l (shared with ff_arm_r): fur arm, two white war-paint bands on the forearm, a fist with claws
    SK_FILL ff_arm_l, SKM_ALL, FF_FUR_2, 15
    SK_BMP ff_arm_l, SKF_FRONT, 0, 0, ff_hand_front
    SK_BMP ff_arm_l, SKF_BACK, 0, 0, ff_hand_back
    SK_BMP ff_arm_l, SKF_LEFT, 0, 0, ff_hand_left
    SK_BMP ff_arm_l, SKF_RIGHT, 0, 0, ff_hand_right
    SK_RECT ff_arm_l, SKF_TOP, 0, 0, 6, 6, FF_VEST_2, 15
    SK_RECT ff_arm_l, SKF_BOTTOM, 0, 0, 6, 6, FF_FUR_3, 0
    SK_GRAD ff_arm_l, SKM_SIDES, 272, 224
    SK_FILL ff_pelt_l, SKM_ALL, FF_VEST_2, 15
    SK_BMP ff_pelt_l, SKF_FRONT, 0, 0, ff_pelt_front
    SK_BMP ff_pelt_l, SKF_BACK, 0, 0, ff_pelt_back
    SK_BMP ff_pelt_l, SKF_LEFT, 0, 0, ff_pelt_left
    SK_BMP ff_pelt_l, SKF_RIGHT, 0, 0, ff_pelt_right
    SK_RECT ff_pelt_l, SKF_TOP, 0, 0, 6, 6, FF_VEST_1, 15
    SK_RECT ff_pelt_l, SKF_BOTTOM, 0, 0, 6, 6, FF_VEST_4, 0
    SK_GRAD ff_pelt_l, SKM_SIDES, 272, 224
    SK_FILL ff_band_l, SKM_ALL, AC_LEATHER_2, 7
    SK_BMP ff_band_l, SKF_FRONT, 0, 0, ff_band_front
    SK_BMP ff_band_l, SKF_BACK, 0, 0, ff_band_back
    SK_BMP ff_band_l, SKF_LEFT, 0, 0, ff_band_left
    SK_BMP ff_band_l, SKF_RIGHT, 0, 0, ff_band_right
    SK_RECT ff_band_l, SKF_TOP, 0, 0, 6, 6, AC_LEATHER_1, 0
    SK_RECT ff_band_l, SKF_BOTTOM, 0, 0, 6, 6, AC_LEATHER_4, 0
    ; --- ff_fist_l (shared with ff_fist_r): a furred fist, finger gaps, black claws, a thumb on each side
    SK_FILL ff_fist_l, SKM_ALL, FF_FUR_2, 15
    SK_BMP ff_fist_l, SKF_FRONT, 0, 0, ff_fist_front
    SK_BMP ff_fist_l, SKF_BACK, 0, 0, ff_fist_back
    SK_BMP ff_fist_l, SKF_RIGHT, 0, 0, ff_fist_right
    SK_BMP ff_fist_l, SKF_LEFT, 0, 0, ff_fist_left
    SK_RECT ff_fist_l, SKF_TOP, 0, 0, 6, 6, FF_FUR_1, 15
    SK_RECT ff_fist_l, SKF_BOTTOM, 0, 0, 6, 6, FF_FUR_3, 0
    SK_GRAD ff_fist_l, SKM_SIDES, 272, 224
SKMODEL_END

; ===================================================================================================
; m_folk_stonekin
; ===================================================================================================
RAMP FS_SKIN, 150, 130, 115             ; grey-brown stone skin (the factions table)
RAMP FS_BEARD, 170, 120, 70             ; copper beard
RAMP FS_MAIL, 140, 140, 150             ; chain mail
RAMP FS_PANTS, 80, 60, 45               ; dark brown trousers

section .rodata
; The characters of every fs_ bitmap. Groups: base, highlight, shade, deep.
;   s S k K stone skin (x crack, n N moss)   h H j J copper beard   m M q Q chain mail   t T u U trousers
;   l L e E leather (AC)   i I a A iron (AC)   y Y g brass (AC gold)   o O pale blue iris, W glint, z pupil
;   r nose flush   _ transparent
align 8
fs_pal:
    PALC 's', FS_SKIN_2
    PALC 'S', FS_SKIN_1
    PALC 'k', FS_SKIN_3
    PALC 'K', FS_SKIN_4
    PALC 'x', RGBO(56, 46, 42)
    PALC 'n', RGBO(98, 116, 72)
    PALC 'N', RGBO(68, 84, 52)
    PALC 'h', FS_BEARD_2
    PALC 'H', FS_BEARD_1
    PALC 'j', FS_BEARD_3
    PALC 'J', FS_BEARD_4
    PALC 'm', FS_MAIL_2
    PALC 'M', FS_MAIL_1
    PALC 'q', FS_MAIL_3
    PALC 'Q', FS_MAIL_4
    PALC 't', FS_PANTS_2
    PALC 'T', FS_PANTS_1
    PALC 'u', FS_PANTS_3
    PALC 'U', FS_PANTS_4
    PALC 'l', AC_LEATHER_2
    PALC 'L', AC_LEATHER_1
    PALC 'e', AC_LEATHER_3
    PALC 'E', AC_LEATHER_4
    PALC 'i', AC_IRON_3
    PALC 'I', AC_IRON_1
    PALC 'a', AC_IRON_4
    PALC 'A', AC_IRON_2
    PALC 'y', AC_GOLD_2
    PALC 'Y', AC_GOLD_1
    PALC 'g', AC_GOLD_3
    PALC 'o', RGBO(104, 160, 204)
    PALC 'O', RGBO(168, 210, 236)
    PALC 'W', RGBO(255, 255, 255)
    PALC 'z', RGBO(24, 24, 30)
    PALC 'r', RGBO(178, 112, 100)
    PALT '_'
    dq 0

    ; fs_torso_front (16x22): fs_torso FRONT
    SKROWS fs_torso_front_rows, 16, 22
    SKROW "Mqqqqqqqqqqqqqqq"
    SKROW "MQQQQQQQQQQQQQQQ"
    SKROW "MqMmqmMmqmMmqmqm"
    SKROW "Mqmmmmmmmmmmmmqm"
    SKROW "MqqmMmqmMmqmMmqm"
    SKROW "Mqmmmmmmmmmmmmqm"
    SKROW "MqMmqmMmqmMmqmqm"
    SKROW "Mqmmmmmmmmmmmmqm"
    SKROW "MqqmMmqmMmqmMmqm"
    SKROW "Mqmmmmmmmmmmmmqm"
    SKROW "MqMmqmMmqmMmqmqm"
    SKROW "Mqmmmmmmmmmmmmqm"
    SKROW "MqqmMmqmMmqmMmqm"
    SKROW "Mqmmmmmmmmmmmmqm"
    SKROW "MqMmqmMmqmMmqmqm"
    SKROW "Mqmmmmmmmmmmmmqm"
    SKROW "MqqmMmqmMmqmMmqm"
    SKROW "Mqmmmmmmmmmmmmqm"
    SKROW "MmMmqmMmqmMmqmMm"
    SKROW "Mmmmmmmmmmmmmmmm"
    SKROW "Mqqqqqqqqqqqqqqq"
    SKROW "MQqQqQqQqQqQqQqQ"
    SKROWS_END
    align 8
    SKBMP fs_torso_front, fs_torso_front_rows, 16, 22, fs_pal
    ; fs_torso_back (16x22): fs_torso BACK
    SKROWS fs_torso_back_rows, 16, 22
    SKROW "Mqqqqqqqqqqqqqqq"
    SKROW "MQQQQQQQQQQQQQQQ"
    SKROW "MMmqmMmqmMmqmMmq"
    SKROW "Mmmmmmmmmmmmmmmm"
    SKROW "MqmMmqmMmqmMmqmM"
    SKROW "qqqqqqqqqqqqqqqq"
    SKROW "MMMMMMMMMMMMMMMM"
    SKROW "Mmmmmmmmmmmmmmmm"
    SKROW "MqmMmqYYYgmMmqmM"
    SKROW "MmmmmmYzzgmmmmmm"
    SKROW "MMmqmMYzygmqmMmq"
    SKROW "MmmmmmYyzgmmmmmm"
    SKROW "MqmMmqggggmMmqmM"
    SKROW "Mmmmmmmmmmmmmmmm"
    SKROW "MMmqmMmqmMmqmMmq"
    SKROW "Mmmmmmmmmmmmmmmm"
    SKROW "MqmMmqmMmqmMmqmM"
    SKROW "Mmmmmmmmmmmmmmmm"
    SKROW "MMmqmMmqmMmqmMmq"
    SKROW "Mmmmmmmmmmmmmmmm"
    SKROW "Mqqqqqqqqqqqqqqq"
    SKROW "MQqQqQqQqQqQqQqQ"
    SKROWS_END
    align 8
    SKBMP fs_torso_back, fs_torso_back_rows, 16, 22, fs_pal
    ; fs_torso_side (8x22): fs_torso RIGHT, fs_torso LEFT
    SKROWS fs_torso_side_rows, 8, 22
    SKROW "qqqqqqqq"
    SKROW "QQQQQQQQ"
    SKROW "mMmqmMmq"
    SKROW "mmmmmmmm"
    SKROW "mqmMmqmM"
    SKROW "mmmmmmmm"
    SKROW "mMmqmMmq"
    SKROW "mmmmmmmm"
    SKROW "mqmMmqmM"
    SKROW "mmmmmmmm"
    SKROW "mMmqmMmq"
    SKROW "mmmmmmmm"
    SKROW "mqmMmqmM"
    SKROW "mmmmmmmm"
    SKROW "mMmqmMmq"
    SKROW "mmmmmmmm"
    SKROW "mqmMmqmM"
    SKROW "mmmmmmmm"
    SKROW "mMmqmMmq"
    SKROW "mmmmmmmm"
    SKROW "qqqqqqqq"
    SKROW "qQqQqQqQ"
    SKROWS_END
    align 8
    SKBMP fs_torso_side, fs_torso_side_rows, 8, 22, fs_pal
    ; fs_belt_front (16x3): fs_belt FRONT, fs_belt BACK
    SKROWS fs_belt_front_rows, 16, 3
    SKROW "LLLLLLLLLLLLLLLL"
    SKROW "lAllAllllllAllAl"
    SKROW "eeeeeeeeeeeeeeee"
    SKROWS_END
    align 8
    SKBMP fs_belt_front, fs_belt_front_rows, 16, 3, fs_pal
    ; fs_belt_side (8x3): fs_belt LEFT, fs_belt RIGHT
    SKROWS fs_belt_side_rows, 8, 3
    SKROW "LLLLLLLL"
    SKROW "llllllll"
    SKROW "eeeeeeee"
    SKROWS_END
    align 8
    SKBMP fs_belt_side, fs_belt_side_rows, 8, 3, fs_pal
    ; fs_buckle_front (6x3): fs_buckle FRONT
    SKROWS fs_buckle_front_rows, 6, 3
    SKROW "YYyYYg"
    SKROW "Y.gg.g"
    SKROW "Yggygg"
    SKROWS_END
    align 8
    SKBMP fs_buckle_front, fs_buckle_front_rows, 6, 3, fs_pal
    ; fs_head_top (16x16): fs_head TOP
    SKROWS fs_head_top_rows, 16, 16
    SKROW ".n..S......k...."
    SKROW "..n.k...k...xxx."
    SKROW "............k.xx"
    SKROW ".............n.x"
    SKROW ".............n.x"
    SKROW "....k..........x"
    SKROW "...............x"
    SKROW "....S..........."
    SKROW "..n.......N....."
    SKROW ".S.............."
    SKROW "n...N...k......."
    SKROW "......N..S......"
    SKROW ".............S.k"
    SKROW "...S....kS......"
    SKROW "..n.k...k......."
    SKROW "..k...kk...k...."
    SKROWS_END
    align 8
    SKBMP fs_head_top, fs_head_top_rows, 16, 16, fs_pal
    ; fs_head_back (16x16): fs_head BACK
    SKROWS fs_head_back_rows, 16, 16
    SKROW ".k..xx...k......"
    SKROW ".....x......S..."
    SKROW ".....xx.k......."
    SKROW "......x...k....."
    SKROW "....kx.........."
    SKROW ".....x.........."
    SKROW "....x....k.....S"
    SKROW "k..Sk..........."
    SKROW "................"
    SKROW ".SS.....k......."
    SKROW "S..............k"
    SKROW "..............k."
    SKROW ".....k....k.S..."
    SKROW "................"
    SKROW ".........k....k."
    SKROW "SS.............."
    SKROWS_END
    align 8
    SKBMP fs_head_back, fs_head_back_rows, 16, 16, fs_pal
    ; fs_head_right (16x16): fs_head RIGHT
    SKROWS fs_head_right_rows, 16, 16
    SKROW "...k...xxx......"
    SKROW ".........xxk...."
    SKROW "..........x..k.."
    SKROW "....k....xxx..kk"
    SKROW "................"
    SKROW "kS....k..Sk....."
    SKROW "................"
    SKROW "........k......."
    SKROW "k......S.....k.."
    SKROW "................"
    SKROW ".........k......"
    SKROW "................"
    SKROW "................"
    SKROW "........k......."
    SKROW "......k......kk."
    SKROW "..S..k.........."
    SKROWS_END
    align 8
    SKBMP fs_head_right, fs_head_right_rows, 16, 16, fs_pal
    ; fs_head_left (16x16): fs_head LEFT
    SKROWS fs_head_left_rows, 16, 16
    SKROW "....S..........."
    SKROW ".....k.........."
    SKROW "........S..k.S.."
    SKROW "...S.k.x.kS....."
    SKROW ".......x........"
    SKROW "....k.x........S"
    SKROW ".....xk.kk......"
    SKROW "k...Sx.........."
    SKROW "..k.kx.........."
    SKROW "k...x.....S....."
    SKROW "....x..........."
    SKROW "...x.....S.....k"
    SKROW ".......k..k....."
    SKROW "..............k."
    SKROW "................"
    SKROW "..k............."
    SKROWS_END
    align 8
    SKBMP fs_head_left, fs_head_left_rows, 16, 16, fs_pal
    ; fs_face (16x16): fs_head FRONT
    SKROWS fs_face_rows, 16, 16
    SKROW ".........x....S."
    SKROW ".....S.kx...S..."
    SKROW "....S...x..S...."
    SKROW "........x......."
    SKROW "k.......x.S....."
    SKROW "...KKK..xxKKK..."
    SKROW "..KWOo....WOoK.."
    SKROW ".SKozz....ozzK.."
    SKROW "..xkkk....kkk..."
    SKROW "..x........k.xxx"
    SKROW "..xx..kkkk.....x"
    SKROW "..kx.......k...."
    SKROW "...x........Sk.S"
    SKROW ".......S...k...."
    SKROW ".k.....S.......S"
    SKROW "k........k......"
    SKROWS_END
    align 8
    SKBMP fs_face, fs_face_rows, 16, 16, fs_pal
    ; fs_brow_front (14x2): fs_brow FRONT
    SKROWS fs_brow_front_rows, 14, 2
    SKROW "HhhHhhHhhHhhHh"
    SKROW "JjJJjJJjJJjJJj"
    SKROWS_END
    align 8
    SKBMP fs_brow_front, fs_brow_front_rows, 14, 2, fs_pal
    ; fs_nose_front (4x4): fs_nose FRONT
    SKROWS fs_nose_front_rows, 4, 4
    SKROW "SSss"
    SKROW "ssrS"
    SKROW "srrk"
    SKROW "kKKk"
    SKROWS_END
    align 8
    SKBMP fs_nose_front, fs_nose_front_rows, 4, 4, fs_pal
    ; fs_ear (2x3): fs_ear_l LEFT, fs_ear_l RIGHT
    SKROWS fs_ear_rows, 2, 3
    SKROW "sk"
    SKROW "kK"
    SKROW "sx"
    SKROWS_END
    align 8
    SKBMP fs_ear, fs_ear_rows, 2, 3, fs_pal
    ; fs_beard_front (14x10): fs_beard FRONT
    SKROWS fs_beard_front_rows, 14, 10
    SKROW "HhHhHhHhHhHhHh"
    SKROW "hjhjhjhjhjhjhj"
    SKROW "hjhjhJJJJjhjhj"
    SKROW "jhj..JJJJ..hjh"
    SKROW "HhhjHhhjHhhjHh"
    SKROW "HYhjHhhjHhhjYh"
    SKROW "hghjhhhjhhhjgh"
    SKROW "HhhHjjhjHjjjHh"
    SKROW "HhhjHjhjjHjjHh"
    SKROW "jJjjjHjJjjHJjJ"
    SKROWS_END
    align 8
    SKBMP fs_beard_front, fs_beard_front_rows, 14, 10, fs_pal
    ; fs_beard_left (6x10): fs_beard LEFT
    SKROWS fs_beard_left_rows, 6, 10
    SKROW "hjhjhj"
    SKROW "HjHjHj"
    SKROW "HjHjHj"
    SKROW "HjHjHj"
    SKROW "hjhjhj"
    SKROW "HjHjHj"
    SKROW "HjHjHj"
    SKROW "HjHjHj"
    SKROW "hjhjhj"
    SKROW "JJJJJJ"
    SKROWS_END
    align 8
    SKBMP fs_beard_left, fs_beard_left_rows, 6, 10, fs_pal
    ; fs_beard_right (6x10): fs_beard RIGHT
    SKROWS fs_beard_right_rows, 6, 10
    SKROW "hjhjhj"
    SKROW "HjHjHj"
    SKROW "HjHjHj"
    SKROW "HjHjHj"
    SKROW "hjhjhj"
    SKROW "HjHjHj"
    SKROW "HjHjHj"
    SKROW "HjHjHj"
    SKROW "hjhjhj"
    SKROW "JJJJJJ"
    SKROWS_END
    align 8
    SKBMP fs_beard_right, fs_beard_right_rows, 6, 10, fs_pal
    ; fs_beard_back (14x10): fs_beard BACK
    SKROWS fs_beard_back_rows, 14, 10
    SKROW "hjhjhjhjhjhjhj"
    SKROW "hjhjhjhjhjhjhj"
    SKROW "hjhjhjhjhjhjhj"
    SKROW "hjhjhjhjhjhjhj"
    SKROW "hjhjhjhjhjhjhj"
    SKROW "hjhjhjhjhjhjhj"
    SKROW "hjhjhjhjhjhjhj"
    SKROW "hjhjhjhjhjhjhj"
    SKROW "hjhjhjhjhjhjhj"
    SKROW "JJJJJJJJJJJJJJ"
    SKROWS_END
    align 8
    SKBMP fs_beard_back, fs_beard_back_rows, 14, 10, fs_pal
    ; fs_braid_front (3x10): fs_braid_l FRONT
    SKROWS fs_braid_front_rows, 3, 10
    SKROW "Hhj"
    SKROW "jHh"
    SKROW "hjH"
    SKROW "Hhj"
    SKROW "jHh"
    SKROW "hjH"
    SKROW "Hhj"
    SKROW "Ygg"
    SKROW "yyy"
    SKROW "JJJ"
    SKROWS_END
    align 8
    SKBMP fs_braid_front, fs_braid_front_rows, 3, 10, fs_pal
    ; fs_braid_back (3x10): fs_braid_l BACK
    SKROWS fs_braid_back_rows, 3, 10
    SKROW "jhH"
    SKROW "hHj"
    SKROW "Hjh"
    SKROW "jhH"
    SKROW "hHj"
    SKROW "Hjh"
    SKROW "jhH"
    SKROW "ggY"
    SKROW "yyy"
    SKROW "JJJ"
    SKROWS_END
    align 8
    SKBMP fs_braid_back, fs_braid_back_rows, 3, 10, fs_pal
    ; fs_braid_left (3x10): fs_braid_l LEFT
    SKROWS fs_braid_left_rows, 3, 10
    SKROW "Hhj"
    SKROW "jHh"
    SKROW "hjH"
    SKROW "Hhj"
    SKROW "jHh"
    SKROW "hjH"
    SKROW "Hhj"
    SKROW "Ygg"
    SKROW "yyy"
    SKROW "JJJ"
    SKROWS_END
    align 8
    SKBMP fs_braid_left, fs_braid_left_rows, 3, 10, fs_pal
    ; fs_braid_right (3x10): fs_braid_l RIGHT
    SKROWS fs_braid_right_rows, 3, 10
    SKROW "jhH"
    SKROW "hHj"
    SKROW "Hjh"
    SKROW "jhH"
    SKROW "hHj"
    SKROW "Hjh"
    SKROW "jhH"
    SKROW "ggY"
    SKROW "yyy"
    SKROW "JJJ"
    SKROWS_END
    align 8
    SKBMP fs_braid_right, fs_braid_right_rows, 3, 10, fs_pal
    ; fs_queue_back (2x13): fs_queue BACK
    SKROWS fs_queue_back_rows, 2, 13
    SKROW "Hh"
    SKROW "gg"
    SKROW "yy"
    SKROW "Hh"
    SKROW "jH"
    SKROW "hj"
    SKROW "Hh"
    SKROW "jH"
    SKROW "hj"
    SKROW "gg"
    SKROW "yy"
    SKROW "hj"
    SKROW "JJ"
    SKROWS_END
    align 8
    SKBMP fs_queue_back, fs_queue_back_rows, 2, 13, fs_pal
    ; fs_queue_front (2x13): fs_queue FRONT
    SKROWS fs_queue_front_rows, 2, 13
    SKROW "hH"
    SKROW "gg"
    SKROW "yy"
    SKROW "hH"
    SKROW "Hj"
    SKROW "jh"
    SKROW "hH"
    SKROW "Hj"
    SKROW "jh"
    SKROW "gg"
    SKROW "yy"
    SKROW "jh"
    SKROW "JJ"
    SKROWS_END
    align 8
    SKBMP fs_queue_front, fs_queue_front_rows, 2, 13, fs_pal
    ; fs_queue_left (2x13): fs_queue LEFT
    SKROWS fs_queue_left_rows, 2, 13
    SKROW "Hh"
    SKROW "gg"
    SKROW "yy"
    SKROW "Hh"
    SKROW "jH"
    SKROW "hj"
    SKROW "Hh"
    SKROW "jH"
    SKROW "hj"
    SKROW "gg"
    SKROW "yy"
    SKROW "hj"
    SKROW "JJ"
    SKROWS_END
    align 8
    SKBMP fs_queue_left, fs_queue_left_rows, 2, 13, fs_pal
    ; fs_queue_right (2x13): fs_queue RIGHT
    SKROWS fs_queue_right_rows, 2, 13
    SKROW "hH"
    SKROW "gg"
    SKROW "yy"
    SKROW "hH"
    SKROW "Hj"
    SKROW "jh"
    SKROW "hH"
    SKROW "Hj"
    SKROW "jh"
    SKROW "gg"
    SKROW "yy"
    SKROW "jh"
    SKROW "JJ"
    SKROWS_END
    align 8
    SKBMP fs_queue_right, fs_queue_right_rows, 2, 13, fs_pal
    ; fs_leg_front (6x24): fs_leg_l FRONT
    SKROWS fs_leg_front_rows, 6, 24
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T.u..u"
    SKROW "T.u..u"
    SKROW "T.uu.u"
    SKROW "T.u..u"
    SKROW "T.u..u"
    SKROW "Tuuu.u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROWS_END
    align 8
    SKBMP fs_leg_front, fs_leg_front_rows, 6, 24, fs_pal
    ; fs_leg_back (6x24): fs_leg_l BACK
    SKROWS fs_leg_back_rows, 6, 24
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T..u.u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROWS_END
    align 8
    SKBMP fs_leg_back, fs_leg_back_rows, 6, 24, fs_pal
    ; fs_leg_side (6x24): fs_leg_l LEFT, fs_leg_l RIGHT
    SKROWS fs_leg_side_rows, 6, 24
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T.u..u"
    SKROW "T....u"
    SKROW "T.u..u"
    SKROW "T....u"
    SKROW "T.u..u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROW "T....u"
    SKROWS_END
    align 8
    SKBMP fs_leg_side, fs_leg_side_rows, 6, 24, fs_pal
    ; fs_tasset_front (7x6): fs_tasset_l FRONT
    SKROWS fs_tasset_front_rows, 7, 6
    SKROW "MmqmMmq"
    SKROW "Mmmmmmm"
    SKROW "MmMmqmM"
    SKROW "Mmmmmmm"
    SKROW "MmqmMmq"
    SKROW "MQqQqQq"
    SKROWS_END
    align 8
    SKBMP fs_tasset_front, fs_tasset_front_rows, 7, 6, fs_pal
    ; fs_tasset_back (7x6): fs_tasset_l BACK
    SKROWS fs_tasset_back_rows, 7, 6
    SKROW "MqmMmqm"
    SKROW "Mmmmmmm"
    SKROW "MMmqmMm"
    SKROW "Mmmmmmm"
    SKROW "MqmMmqm"
    SKROW "MQqQqQq"
    SKROWS_END
    align 8
    SKBMP fs_tasset_back, fs_tasset_back_rows, 7, 6, fs_pal
    ; fs_tasset_left (8x6): fs_tasset_l LEFT
    SKROWS fs_tasset_left_rows, 8, 6
    SKROW "MmqmMmqm"
    SKROW "Mmmmmmmm"
    SKROW "MmMmqmMm"
    SKROW "Mmmmmmmm"
    SKROW "MmqmMmqm"
    SKROW "MQqQqQqQ"
    SKROWS_END
    align 8
    SKBMP fs_tasset_left, fs_tasset_left_rows, 8, 6, fs_pal
    ; fs_tasset_right (8x6): fs_tasset_l RIGHT
    SKROWS fs_tasset_right_rows, 8, 6
    SKROW "MqmMmqmM"
    SKROW "Mmmmmmmm"
    SKROW "MMmqmMmq"
    SKROW "Mmmmmmmm"
    SKROW "MqmMmqmM"
    SKROW "MQqQqQqQ"
    SKROWS_END
    align 8
    SKBMP fs_tasset_right, fs_tasset_right_rows, 8, 6, fs_pal
    ; fs_boot_front (7x9): fs_boot_l FRONT
    SKROWS fs_boot_front_rows, 7, 9
    SKROW "LLLLLLL"
    SKROW "lllllll"
    SKROW "eeeeeee"
    SKROW "l......"
    SKROW "eeeIeee"
    SKROW "LLLiLLL"
    SKROW "l......"
    SKROW "l......"
    SKROW "EEEEEEE"
    SKROWS_END
    align 8
    SKBMP fs_boot_front, fs_boot_front_rows, 7, 9, fs_pal
    ; fs_boot_back (7x9): fs_boot_l BACK
    SKROWS fs_boot_back_rows, 7, 9
    SKROW "LLLLLLL"
    SKROW "lllllll"
    SKROW "eeeeeee"
    SKROW "l......"
    SKROW "l......"
    SKROW "l......"
    SKROW "l......"
    SKROW "l......"
    SKROW "EEEEEEE"
    SKROWS_END
    align 8
    SKBMP fs_boot_back, fs_boot_back_rows, 7, 9, fs_pal
    ; fs_boot_left (8x9): fs_boot_l LEFT
    SKROWS fs_boot_left_rows, 8, 9
    SKROW "LLLLLLLL"
    SKROW "llllllll"
    SKROW "eeeeeeee"
    SKROW "l......."
    SKROW "eeeeeeee"
    SKROW "LLLLLLLL"
    SKROW "l......."
    SKROW "l......."
    SKROW "EEEEEEEE"
    SKROWS_END
    align 8
    SKBMP fs_boot_left, fs_boot_left_rows, 8, 9, fs_pal
    ; fs_boot_right (8x9): fs_boot_l RIGHT
    SKROWS fs_boot_right_rows, 8, 9
    SKROW "LLLLLLLL"
    SKROW "llllllll"
    SKROW "eeeeeeee"
    SKROW "l......."
    SKROW "eeeeeeee"
    SKROW "LLLLLLLL"
    SKROW "l......."
    SKROW "l......."
    SKROW "EEEEEEEE"
    SKROWS_END
    align 8
    SKBMP fs_boot_right, fs_boot_right_rows, 8, 9, fs_pal
    ; fs_foot_front (8x3): fs_foot_l FRONT
    SKROWS fs_foot_front_rows, 8, 3
    SKROW "AAAAAAAa"
    SKROW "Aiiiiiia"
    SKROW "EEEEEEEE"
    SKROWS_END
    align 8
    SKBMP fs_foot_front, fs_foot_front_rows, 8, 3, fs_pal
    ; fs_foot_back (8x3): fs_foot_l BACK
    SKROWS fs_foot_back_rows, 8, 3
    SKROW "llllllll"
    SKROW "eeeeeeee"
    SKROW "EEEEEEEE"
    SKROWS_END
    align 8
    SKBMP fs_foot_back, fs_foot_back_rows, 8, 3, fs_pal
    ; fs_foot_left (11x3): fs_foot_l LEFT
    SKROWS fs_foot_left_rows, 11, 3
    SKROW "AAAllllllll"
    SKROW "iiieeeeeeee"
    SKROW "EEEEEEEEEEE"
    SKROWS_END
    align 8
    SKBMP fs_foot_left, fs_foot_left_rows, 11, 3, fs_pal
    ; fs_foot_right (11x3): fs_foot_l RIGHT
    SKROWS fs_foot_right_rows, 11, 3
    SKROW "llllllllAAA"
    SKROW "eeeeeeeeiii"
    SKROW "EEEEEEEEEEE"
    SKROWS_END
    align 8
    SKBMP fs_foot_right, fs_foot_right_rows, 11, 3, fs_pal
    ; fs_foot_top (8x11): fs_foot_l TOP
    SKROWS fs_foot_top_rows, 8, 11
    SKROW "AAAAAAAA"
    SKROW "iiiiiiii"
    SKROW "iiiiiiii"
    SKROW "aaaaaaaa"
    SKROW "Llllllll"
    SKROW "Llllllll"
    SKROW "Llllllll"
    SKROW "Llllllll"
    SKROW "Llllllll"
    SKROW "Llllllll"
    SKROW "eeeeeeee"
    SKROWS_END
    align 8
    SKBMP fs_foot_top, fs_foot_top_rows, 8, 11, fs_pal
    ; fs_foot_sole (8x11): fs_foot_l BOTTOM
    SKROWS fs_foot_sole_rows, 8, 11
    SKROW "EEEEEEEE"
    SKROW "........"
    SKROW "EEEEEEEE"
    SKROW "........"
    SKROW "EEEEEEEE"
    SKROW "........"
    SKROW "EEEEEEEE"
    SKROW "........"
    SKROW "EEEEEEEE"
    SKROW "........"
    SKROW "EEEEEEEE"
    SKROWS_END
    align 8
    SKBMP fs_foot_sole, fs_foot_sole_rows, 8, 11, fs_pal
    ; fs_hand_front (6x22): fs_arm_l FRONT
    SKROWS fs_hand_front_rows, 6, 22
    SKROW "MmqmMm"
    SKROW "Mmmmmm"
    SKROW "MmMmqm"
    SKROW "Mmmmmm"
    SKROW "MmqmMm"
    SKROW "Mmmmmm"
    SKROW "MmMmqm"
    SKROW "Mmmmmm"
    SKROW "MmqmMm"
    SKROW "MQQQQQ"
    SKROW "S....k"
    SKROW "S.x..k"
    SKROW "S.xxxk"
    SKROW "S...kk"
    SKROW "S....k"
    SKROW "SSk.Sk"
    SKROW "S....k"
    SKROW "KKKKKK"
    SKROW "S....k"
    SKROW "S.k.Kk"
    SKROW "SkSk.k"
    SKROW "KKKKKK"
    SKROWS_END
    align 8
    SKBMP fs_hand_front, fs_hand_front_rows, 6, 22, fs_pal
    ; fs_hand_back (6x22): fs_arm_l BACK
    SKROWS fs_hand_back_rows, 6, 22
    SKROW "MqmMmq"
    SKROW "Mmmmmm"
    SKROW "MMmqmM"
    SKROW "Mmmmmm"
    SKROW "MqmMmq"
    SKROW "Mmmmmm"
    SKROW "MMmqmM"
    SKROW "Mmmmmm"
    SKROW "MqmMmq"
    SKROW "MQQQQQ"
    SKROW "S....k"
    SKROW "S..x.k"
    SKROW "S.xxxk"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "KKKKKK"
    SKROW "S.S..k"
    SKROW "SS...k"
    SKROW "Sk...k"
    SKROW "KKKKKK"
    SKROWS_END
    align 8
    SKBMP fs_hand_back, fs_hand_back_rows, 6, 22, fs_pal
    ; fs_hand_left (6x22): fs_arm_l LEFT
    SKROWS fs_hand_left_rows, 6, 22
    SKROW "MqmMmq"
    SKROW "Mmmmmm"
    SKROW "MMmqmM"
    SKROW "Mmmmmm"
    SKROW "MqmMmq"
    SKROW "Mmmmmm"
    SKROW "MMmqmM"
    SKROW "Mmmmmm"
    SKROW "MqmMmq"
    SKROW "MQQQQQ"
    SKROW "S....k"
    SKROW "S..xxk"
    SKROW "S...xk"
    SKROW "S...xk"
    SKROW "S....k"
    SKROW "S.S..k"
    SKROW "S.k..k"
    SKROW "KKKKKK"
    SKROW "Sk...k"
    SKROW "S..k.k"
    SKROW "S....k"
    SKROW "KKKKKK"
    SKROWS_END
    align 8
    SKBMP fs_hand_left, fs_hand_left_rows, 6, 22, fs_pal
    ; fs_hand_right (6x22): fs_arm_l RIGHT
    SKROWS fs_hand_right_rows, 6, 22
    SKROW "MqmMmq"
    SKROW "Mmmmmm"
    SKROW "MMmqmM"
    SKROW "Mmmmmm"
    SKROW "MqmMmq"
    SKROW "Mmmmmm"
    SKROW "MMmqmM"
    SKROW "Mmmmmm"
    SKROW "MqmMmq"
    SKROW "MQQQQQ"
    SKROW "S..k.k"
    SKROW "S..x.k"
    SKROW "S..xkk"
    SKROW "SS.xxk"
    SKROW "S....k"
    SKROW "S.S..k"
    SKROW "S....k"
    SKROW "KKKKKK"
    SKROW "S....k"
    SKROW "S.k..k"
    SKROW "S....k"
    SKROW "KKKKKK"
    SKROWS_END
    align 8
    SKBMP fs_hand_right, fs_hand_right_rows, 6, 22, fs_pal
    ; fs_pauld_front (7x6): fs_pauld_l FRONT
    SKROWS fs_pauld_front_rows, 7, 6
    SKROW "AAAAAAa"
    SKROW "Aiiiiia"
    SKROW "A..A..a"
    SKROW "Aaaaaaa"
    SKROW "A..y..a"
    SKROW "aaaaaaa"
    SKROWS_END
    align 8
    SKBMP fs_pauld_front, fs_pauld_front_rows, 7, 6, fs_pal
    ; fs_pauld_back (7x6): fs_pauld_l BACK
    SKROWS fs_pauld_back_rows, 7, 6
    SKROW "AAAAAAa"
    SKROW "A.....a"
    SKROW "Aaaaaaa"
    SKROW "A.....a"
    SKROW "A.....a"
    SKROW "aaaaaaa"
    SKROWS_END
    align 8
    SKBMP fs_pauld_back, fs_pauld_back_rows, 7, 6, fs_pal
    ; fs_pauld_left (8x6): fs_pauld_l LEFT
    SKROWS fs_pauld_left_rows, 8, 6
    SKROW "AAAAAAAA"
    SKROW "........"
    SKROW "iiiiiiii"
    SKROW "...A.A.."
    SKROW "........"
    SKROW "aaaaaaaa"
    SKROWS_END
    align 8
    SKBMP fs_pauld_left, fs_pauld_left_rows, 8, 6, fs_pal
    ; fs_pauld_right (8x6): fs_pauld_l RIGHT
    SKROWS fs_pauld_right_rows, 8, 6
    SKROW "AAAAAAAA"
    SKROW "........"
    SKROW "iiiiiiii"
    SKROW "...A.A.."
    SKROW "........"
    SKROW "aaaaaaaa"
    SKROWS_END
    align 8
    SKBMP fs_pauld_right, fs_pauld_right_rows, 8, 6, fs_pal
    ; fs_vamb_front (6x6): fs_vamb_l FRONT
    SKROWS fs_vamb_front_rows, 6, 6
    SKROW "AAAAAA"
    SKROW "aaaaaa"
    SKROW "LLLLLL"
    SKROW "eeeeee"
    SKROW "AAAAAA"
    SKROW "aaaaaa"
    SKROWS_END
    align 8
    SKBMP fs_vamb_front, fs_vamb_front_rows, 6, 6, fs_pal
    ; fs_vamb_back (6x6): fs_vamb_l BACK
    SKROWS fs_vamb_back_rows, 6, 6
    SKROW "AAAAAA"
    SKROW "aaaaaa"
    SKROW "LLLLLL"
    SKROW "eeeeee"
    SKROW "AAAAAA"
    SKROW "aaaaaa"
    SKROWS_END
    align 8
    SKBMP fs_vamb_back, fs_vamb_back_rows, 6, 6, fs_pal
    ; fs_vamb_left (6x6): fs_vamb_l LEFT
    SKROWS fs_vamb_left_rows, 6, 6
    SKROW "AAAAAA"
    SKROW "aaaaaa"
    SKROW "LLLLLL"
    SKROW "eeeeee"
    SKROW "AAAAAA"
    SKROW "aaaaaa"
    SKROWS_END
    align 8
    SKBMP fs_vamb_left, fs_vamb_left_rows, 6, 6, fs_pal
    ; fs_vamb_right (6x6): fs_vamb_l RIGHT
    SKROWS fs_vamb_right_rows, 6, 6
    SKROW "AAAAAA"
    SKROW "aaaaaa"
    SKROW "LLLLLL"
    SKROW "eeeeee"
    SKROW "AAAAAA"
    SKROW "aaaaaa"
    SKROWS_END
    align 8
    SKBMP fs_vamb_right, fs_vamb_right_rows, 6, 6, fs_pal
    ; fs_fist_front (6x5): fs_fist_l FRONT
    SKROWS fs_fist_front_rows, 6, 5
    SKROW "KKKKKK"
    SKROW "SSsSxk"
    SKROW "SsxsKk"
    SKROW "SsxsKk"
    SKROW "KkKkKK"
    SKROWS_END
    align 8
    SKBMP fs_fist_front, fs_fist_front_rows, 6, 5, fs_pal
    ; fs_fist_back (6x5): fs_fist_l BACK
    SKROWS fs_fist_back_rows, 6, 5
    SKROW "KKKKKK"
    SKROW "SsssSk"
    SKROW "Ssxsss"
    SKROW "Ssxssk"
    SKROW "KkKkKK"
    SKROWS_END
    align 8
    SKBMP fs_fist_back, fs_fist_back_rows, 6, 5, fs_pal
    ; fs_fist_right (6x5): fs_fist_l RIGHT
    SKROWS fs_fist_right_rows, 6, 5
    SKROW "KKKKKK"
    SKROW "SssSSk"
    SKROW "SssSsk"
    SKROW "Ssxssk"
    SKROW "KkKkKK"
    SKROWS_END
    align 8
    SKBMP fs_fist_right, fs_fist_right_rows, 6, 5, fs_pal
    ; fs_fist_left (6x5): fs_fist_l LEFT
    SKROWS fs_fist_left_rows, 6, 5
    SKROW "KKKKKK"
    SKROW "kSSssS"
    SKROW "kSssSS"
    SKROW "kssxsS"
    SKROW "KKkKkK"
    SKROWS_END
    align 8
    SKBMP fs_fist_left, fs_fist_left_rows, 6, 5, fs_pal

section .data
SKMODEL_BEGIN m_folk_stonekin, 32, 0, 11, 26, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART fs_torso, -8, 24, -4, 16, 22, 8, 0, 0              ; chain-mail tunic
    PART fs_collar, -6, 42, -5, 12, 5, 10, 4, 0             ; iron gorget
    PART fs_belt, -8, 27, -4, 16, 3, 8, 6, 0                ; wide leather belt
    PART fs_buckle, -3, 27, -6, 6, 3, 2, 0, 0               ; big brass buckle with a rune
    SKBONE BK_HEAD, 0, 0, 0.00
    PART fs_head, -8, 46, -8, 16, 16, 16, 0, 0              ; the 16 texel head: cracked stone
    PART fs_brow, -7, 57, -10, 14, 2, 2, 0, 0               ; heavy brow ridge with bushy copper brows
    PART fs_nose, -2, 52, -11, 4, 4, 3, 0, 0                ; broad nose
    PART fs_ear_l, -9, 52, -1, 1, 3, 2, 0, 0                ; ear (the right one shares its skin)
    PART_AS fs_ear_r, fs_ear_l, 8, 52, -1, 0, 0
    PART fs_beard, -7, 42, -10, 14, 10, 6, 0, 0             ; copper beard and moustache
    PART fs_braid_l, -5, 32, -8, 3, 10, 3, 0, 0             ; braid (the right one shares its skin)
    PART_AS fs_braid_r, fs_braid_l, 2, 32, -8, 0, 0
    PART fs_queue, -1, 43, 8, 2, 13, 2, 0, 0                ; braided ponytail down the back of the head
    SKBONE BK_LLEG, 24, 0, 1.00
    PART fs_leg_l, -6, 0, -3, 6, 24, 6, 0, 0                ; dark brown trousers
    PART fs_tasset_l, -7, 18, -4, 7, 6, 8, 0, 0             ; mail skirt over the thigh
    PART fs_boot_l, -7, 3, -4, 7, 9, 8, 0, 0                ; boot shaft with a folded cuff and a strap
    PART fs_foot_l, -8, 0, -7, 8, 3, 11, 0, 0               ; heavy boot: iron toe cap, thick sole
    SKBONE BK_RLEG, 24, 0, -1.00
    PART_AS fs_leg_r, fs_leg_l, 0, 0, -3, 0, 0
    PART_AS fs_tasset_r, fs_tasset_l, 0, 18, -4, 0, 0
    PART_AS fs_boot_r, fs_boot_l, 0, 3, -4, 0, 0
    PART_AS fs_foot_r, fs_foot_l, 0, 0, -7, 0, 0
    SKBONE BK_LARM, 44, 0, -1.00
    PART fs_arm_l, -14, 24, -3, 6, 22, 6, 0, 0              ; mail sleeve, stone forearm and fist
    PART fs_pauld_l, -15, 41, -4, 7, 6, 8, 0, 0             ; iron pauldron
    PART fs_vamb_l, -14, 29, -3, 6, 6, 6, 6, 0              ; vambrace
    PART fs_fist_l, -14, 24, -3, 6, 5, 6, 8, 0              ; stone fist
    SKBONE BK_RARM, 44, 0, 1.00
    PART_AS fs_arm_r, fs_arm_l, 8, 24, -3, 0, 0
    PART_AS fs_pauld_r, fs_pauld_l, 8, 41, -4, 0, 0
    PART_AS fs_vamb_r, fs_vamb_l, 8, 29, -3, 6, 0
    PART_AS fs_fist_r, fs_fist_l, 8, 24, -3, 8, 0
SKMODEL_PAINT
    ; --- fs_torso: chain mail with lit rings, a padded neckline, shoulder seams, a ragged hem
    SK_FILL fs_torso, SKM_ALL, FS_MAIL_2, 0
    SK_BMP fs_torso, SKF_FRONT, 0, 0, fs_torso_front
    SK_BMP fs_torso, SKF_BACK, 0, 0, fs_torso_back
    SK_BMP fs_torso, SKF_RIGHT, 0, 0, fs_torso_side
    SK_BMP fs_torso, SKF_LEFT, 0, 0, fs_torso_side
    SK_RECT fs_torso, SKF_BOTTOM, 0, 0, 16, 8, FS_MAIL_4, 0
    SK_GRAD fs_torso, SKM_SIDES, 272, 224
    ; --- fs_collar: an iron gorget in two plates; fs_belt: wide studded leather; fs_buckle: a brass plate with a rune
    SK_FILL fs_collar, SKM_ALL, AC_IRON_3, 0
    SK_RECT fs_collar, SKF_FRONT, 0, 0, 12, 1, AC_IRON_2, 0
    SK_RECT fs_collar, SKF_FRONT, 0, 2, 12, 1, AC_IRON_4, 0
    SK_RECT fs_collar, SKF_FRONT, 0, 3, 12, 1, AC_IRON_2, 0
    SK_RECT fs_collar, SKF_FRONT, 0, 4, 12, 1, AC_IRON_4, 0
    SK_RECT fs_collar, SKF_FRONT, 0, 0, 1, 5, AC_IRON_2, 0
    SK_RECT fs_collar, SKF_BACK, 0, 0, 12, 1, AC_IRON_2, 0
    SK_RECT fs_collar, SKF_BACK, 0, 2, 12, 1, AC_IRON_4, 0
    SK_RECT fs_collar, SKF_BACK, 0, 3, 12, 1, AC_IRON_2, 0
    SK_RECT fs_collar, SKF_BACK, 0, 4, 12, 1, AC_IRON_4, 0
    SK_RECT fs_collar, SKF_BACK, 0, 0, 1, 5, AC_IRON_2, 0
    SK_RECT fs_collar, SKF_LEFT, 0, 0, 10, 1, AC_IRON_2, 0
    SK_RECT fs_collar, SKF_LEFT, 0, 2, 10, 1, AC_IRON_4, 0
    SK_RECT fs_collar, SKF_LEFT, 0, 3, 10, 1, AC_IRON_2, 0
    SK_RECT fs_collar, SKF_LEFT, 0, 4, 10, 1, AC_IRON_4, 0
    SK_RECT fs_collar, SKF_LEFT, 0, 0, 1, 5, AC_IRON_2, 0
    SK_RECT fs_collar, SKF_RIGHT, 0, 0, 10, 1, AC_IRON_2, 0
    SK_RECT fs_collar, SKF_RIGHT, 0, 2, 10, 1, AC_IRON_4, 0
    SK_RECT fs_collar, SKF_RIGHT, 0, 3, 10, 1, AC_IRON_2, 0
    SK_RECT fs_collar, SKF_RIGHT, 0, 4, 10, 1, AC_IRON_4, 0
    SK_RECT fs_collar, SKF_RIGHT, 0, 0, 1, 5, AC_IRON_2, 0
    SK_GRAD fs_collar, SKM_SIDES, 272, 224
    SK_RECT fs_collar, SKF_TOP, 0, 0, 12, 10, AC_IRON_2, 0
    SK_RECT fs_collar, SKF_BOTTOM, 0, 0, 12, 10, AC_IRON_4, 0
    SK_FILL fs_belt, SKM_ALL, AC_LEATHER_3, 7
    SK_BMP fs_belt, SKF_FRONT, 0, 0, fs_belt_front
    SK_BMP fs_belt, SKF_BACK, 0, 0, fs_belt_front
    SK_BMP fs_belt, SKF_LEFT, 0, 0, fs_belt_side
    SK_BMP fs_belt, SKF_RIGHT, 0, 0, fs_belt_side
    SK_RECT fs_belt, SKF_TOP, 0, 0, 16, 8, AC_LEATHER_1, 0
    SK_RECT fs_belt, SKF_BOTTOM, 0, 0, 16, 8, AC_LEATHER_4, 0
    SK_FILL fs_buckle, SKM_ALL, AC_GOLD_3, 0
    SK_BMP fs_buckle, SKF_FRONT, 0, 0, fs_buckle_front
    SK_RECT fs_buckle, SKF_TOP, 0, 0, 6, 2, AC_GOLD_1, 0
    SK_RECT fs_buckle, SKF_BOTTOM, 0, 0, 6, 2, AC_GOLD_4, 0
    ; --- fs_head: cracked stone, small pale-blue eyes under the ridge, moss on the crown (the beard covers the lower face)
    SK_FILL fs_head, SKM_ALL, FS_SKIN_2, 31
    SK_GRAD fs_head, SKM_SIDES, 272, 224
    SK_BMP fs_head, SKF_TOP, 0, 0, fs_head_top
    SK_BMP fs_head, SKF_BACK, 0, 0, fs_head_back
    SK_BMP fs_head, SKF_RIGHT, 0, 0, fs_head_right
    SK_BMP fs_head, SKF_LEFT, 0, 0, fs_head_left
    SK_RECT fs_head, SKF_BOTTOM, 0, 0, 16, 16, FS_SKIN_4, 0
    SK_BMP fs_head, SKF_FRONT, 0, 0, fs_face
    ; --- fs_brow: a stone ridge under bushy copper brows; fs_nose: broad, a flushed tip; fs_ear_l (shared with fs_ear_r)
    SK_FILL fs_brow, SKM_ALL, FS_SKIN_2, 15
    SK_BMP fs_brow, SKF_FRONT, 0, 0, fs_brow_front
    SK_RECT fs_brow, SKF_TOP, 0, 0, 14, 2, FS_SKIN_1, 15
    SK_RECT fs_brow, SKF_BOTTOM, 0, 0, 14, 2, FS_SKIN_4, 0
    SK_RECT fs_brow, SKF_LEFT, 0, 0, 2, 1, FS_BEARD_2, 0
    SK_RECT fs_brow, SKF_RIGHT, 0, 0, 2, 1, FS_BEARD_2, 0
    SK_FILL fs_nose, SKM_ALL, FS_SKIN_2, 15
    SK_BMP fs_nose, SKF_FRONT, 0, 0, fs_nose_front
    SK_RECT fs_nose, SKF_TOP, 0, 0, 4, 3, FS_SKIN_1, 0
    SK_RECT fs_nose, SKF_BOTTOM, 0, 0, 4, 3, FS_SKIN_4, 0
    SK_GRAD fs_nose, SKM_SIDES, 272, 224
    SK_FILL fs_ear_l, SKM_ALL, FS_SKIN_2, 15
    SK_BMP fs_ear_l, SKF_LEFT, 0, 0, fs_ear
    SK_BMP fs_ear_l, SKF_RIGHT, 0, 0, fs_ear
    ; --- fs_beard: a swept moustache over thick locks, tied braid starts; fs_braid_l (shared with fs_braid_r): a plaited braid with a brass ring
    SK_FILL fs_beard, SKM_ALL, FS_BEARD_2, 31
    SK_BMP fs_beard, SKF_FRONT, 0, 0, fs_beard_front
    SK_BMP fs_beard, SKF_LEFT, 0, 0, fs_beard_left
    SK_BMP fs_beard, SKF_RIGHT, 0, 0, fs_beard_right
    SK_BMP fs_beard, SKF_BACK, 0, 0, fs_beard_back
    SK_RECT fs_beard, SKF_TOP, 0, 0, 14, 6, FS_BEARD_1, 31
    SK_RECT fs_beard, SKF_BOTTOM, 0, 0, 14, 6, FS_BEARD_4, 0
    SK_FILL fs_braid_l, SKM_ALL, FS_BEARD_2, 15
    SK_BMP fs_braid_l, SKF_FRONT, 0, 0, fs_braid_front
    SK_BMP fs_braid_l, SKF_BACK, 0, 0, fs_braid_back
    SK_BMP fs_braid_l, SKF_LEFT, 0, 0, fs_braid_left
    SK_BMP fs_braid_l, SKF_RIGHT, 0, 0, fs_braid_right
    SK_RECT fs_braid_l, SKF_TOP, 0, 0, 3, 3, FS_BEARD_1, 0
    SK_RECT fs_braid_l, SKF_BOTTOM, 0, 0, 3, 3, FS_BEARD_4, 0
    ; --- fs_queue: the ponytail, plaited like the beard braids, tied with brass rings
    SK_FILL fs_queue, SKM_ALL, FS_BEARD_2, 15
    SK_BMP fs_queue, SKF_BACK, 0, 0, fs_queue_back
    SK_BMP fs_queue, SKF_FRONT, 0, 0, fs_queue_front
    SK_BMP fs_queue, SKF_LEFT, 0, 0, fs_queue_left
    SK_BMP fs_queue, SKF_RIGHT, 0, 0, fs_queue_right
    SK_RECT fs_queue, SKF_TOP, 0, 0, 2, 2, FS_BEARD_1, 0
    SK_RECT fs_queue, SKF_BOTTOM, 0, 0, 2, 2, FS_BEARD_4, 0
    ; --- fs_leg_l (shared with fs_leg_r): dark brown trousers; fs_tasset_l: mail skirt; fs_boot_l: shaft; fs_foot_l: heavy boot
    SK_FILL fs_leg_l, SKM_ALL, FS_PANTS_2, 15
    SK_BMP fs_leg_l, SKF_FRONT, 0, 0, fs_leg_front
    SK_BMP fs_leg_l, SKF_BACK, 0, 0, fs_leg_back
    SK_BMP fs_leg_l, SKF_LEFT, 0, 0, fs_leg_side
    SK_BMP fs_leg_l, SKF_RIGHT, 0, 0, fs_leg_side
    SK_RECT fs_leg_l, SKF_BOTTOM, 0, 0, 6, 6, FS_PANTS_4, 0
    SK_GRAD fs_leg_l, SKM_SIDES, 272, 224
    SK_FILL fs_tasset_l, SKM_ALL, FS_MAIL_2, 0
    SK_BMP fs_tasset_l, SKF_FRONT, 0, 0, fs_tasset_front
    SK_BMP fs_tasset_l, SKF_BACK, 0, 0, fs_tasset_back
    SK_BMP fs_tasset_l, SKF_LEFT, 0, 0, fs_tasset_left
    SK_BMP fs_tasset_l, SKF_RIGHT, 0, 0, fs_tasset_right
    SK_RECT fs_tasset_l, SKF_TOP, 0, 0, 7, 8, FS_MAIL_1, 0
    SK_RECT fs_tasset_l, SKF_BOTTOM, 0, 0, 7, 8, FS_MAIL_4, 0
    SK_GRAD fs_tasset_l, SKM_SIDES, 272, 224
    SK_FILL fs_boot_l, SKM_ALL, AC_LEATHER_3, 15
    SK_BMP fs_boot_l, SKF_FRONT, 0, 0, fs_boot_front
    SK_BMP fs_boot_l, SKF_BACK, 0, 0, fs_boot_back
    SK_BMP fs_boot_l, SKF_LEFT, 0, 0, fs_boot_left
    SK_BMP fs_boot_l, SKF_RIGHT, 0, 0, fs_boot_right
    SK_RECT fs_boot_l, SKF_TOP, 0, 0, 7, 8, AC_LEATHER_1, 15
    SK_RECT fs_boot_l, SKF_BOTTOM, 0, 0, 7, 8, AC_LEATHER_4, 0
    SK_GRAD fs_boot_l, SKM_SIDES, 272, 224
    SK_FILL fs_foot_l, SKM_ALL, AC_LEATHER_3, 15
    SK_BMP fs_foot_l, SKF_FRONT, 0, 0, fs_foot_front
    SK_BMP fs_foot_l, SKF_BACK, 0, 0, fs_foot_back
    SK_BMP fs_foot_l, SKF_LEFT, 0, 0, fs_foot_left
    SK_BMP fs_foot_l, SKF_RIGHT, 0, 0, fs_foot_right
    SK_BMP fs_foot_l, SKF_TOP, 0, 0, fs_foot_top
    SK_RECT fs_foot_l, SKF_BOTTOM, 0, 0, 8, 11, AC_LEATHER_4, 0
    SK_BMP fs_foot_l, SKF_BOTTOM, 0, 0, fs_foot_sole
    ; --- fs_arm_l (shared with fs_arm_r): mail sleeve to row 9, stone forearm with cracks, a knuckled fist
    SK_FILL fs_arm_l, SKM_ALL, FS_SKIN_2, 31
    SK_BMP fs_arm_l, SKF_FRONT, 0, 0, fs_hand_front
    SK_BMP fs_arm_l, SKF_BACK, 0, 0, fs_hand_back
    SK_BMP fs_arm_l, SKF_LEFT, 0, 0, fs_hand_left
    SK_BMP fs_arm_l, SKF_RIGHT, 0, 0, fs_hand_right
    SK_RECT fs_arm_l, SKF_TOP, 0, 0, 6, 6, FS_MAIL_2, 0
    SK_RECT fs_arm_l, SKF_BOTTOM, 0, 0, 6, 6, FS_SKIN_3, 0
    SK_GRAD fs_arm_l, SKM_SIDES, 272, 224
    SK_FILL fs_pauld_l, SKM_ALL, AC_IRON_3, 0
    SK_BMP fs_pauld_l, SKF_FRONT, 0, 0, fs_pauld_front
    SK_BMP fs_pauld_l, SKF_BACK, 0, 0, fs_pauld_back
    SK_BMP fs_pauld_l, SKF_LEFT, 0, 0, fs_pauld_left
    SK_BMP fs_pauld_l, SKF_RIGHT, 0, 0, fs_pauld_right
    SK_RECT fs_pauld_l, SKF_TOP, 0, 0, 7, 8, AC_IRON_2, 0
    SK_RECT fs_pauld_l, SKF_TOP, 1, 1, 5, 6, AC_IRON_3, 0
    SK_RECT fs_pauld_l, SKF_BOTTOM, 0, 0, 7, 8, AC_IRON_4, 0
    SK_FILL fs_vamb_l, SKM_ALL, AC_LEATHER_2, 7
    SK_BMP fs_vamb_l, SKF_FRONT, 0, 0, fs_vamb_front
    SK_BMP fs_vamb_l, SKF_BACK, 0, 0, fs_vamb_back
    SK_BMP fs_vamb_l, SKF_LEFT, 0, 0, fs_vamb_left
    SK_BMP fs_vamb_l, SKF_RIGHT, 0, 0, fs_vamb_right
    SK_RECT fs_vamb_l, SKF_TOP, 0, 0, 6, 6, AC_IRON_2, 0
    SK_RECT fs_vamb_l, SKF_BOTTOM, 0, 0, 6, 6, AC_IRON_4, 0
    ; --- fs_fist_l (shared with fs_fist_r): a heavy stone fist, cracked knuckles, a thumb on each side
    SK_FILL fs_fist_l, SKM_ALL, FS_SKIN_2, 31
    SK_BMP fs_fist_l, SKF_FRONT, 0, 0, fs_fist_front
    SK_BMP fs_fist_l, SKF_BACK, 0, 0, fs_fist_back
    SK_BMP fs_fist_l, SKF_RIGHT, 0, 0, fs_fist_right
    SK_BMP fs_fist_l, SKF_LEFT, 0, 0, fs_fist_left
    SK_RECT fs_fist_l, SKF_TOP, 0, 0, 6, 6, FS_SKIN_1, 15
    SK_RECT fs_fist_l, SKF_BOTTOM, 0, 0, 6, 6, FS_SKIN_4, 0
    SK_GRAD fs_fist_l, SKM_SIDES, 272, 224
SKMODEL_END
