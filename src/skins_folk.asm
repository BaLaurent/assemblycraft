; skins_folk.asm: skin models of the folk (0.13 "looks"): humanoids that walk on two legs, wear clothes and
; carry things in the right hand. Data only: bones, parts and paint ops for skin.asm (art.inc, common.inc
; "0.13 looks"); nothing here runs.
;
; Holds the style samples; the other folk (bandits, cult, beastfolk, stonekin, the Villagers' elder and
; merchant) and the extras (hat, helmet, pack, crown, hoods) follow the same structure:
;   m_folk_villagers   the farmer: brown fringe, green tunic with a round collar, rope belt, rolled sleeves,
;                      patched trousers, laced boots (prefix fv_)
;   m_avatar           the adventurer other players show as, and the first-person arm (prefix av_)
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
;   - skin_build packs the unwraps in record order with next-fit shelves: a part costs 2(w+d) x (d+h) atlas
;     texels (a cutout overlay as much as a solid part), an AS part nothing; neighbouring parts of similar height
;     waste less. The two models here take about 154 atlas rows together (of 3072).
;   - the avatar's tunic, scarf and sleeves are SKPF_ACCENT parts painted in light greys: the peer slot colour
;     multiplies them (a grey of 208 keeps the slot colour vivid and the deep greys keep the seams visible).
; Ramps (RAMP: _1 highlight, _2 base, _3 shade, _4 deep; AC_* are the shared material ramps of art.inc):
;   m_folk_villagers   FV_SKIN (225,180,140), FV_HAIR (104,68,38), FV_TUNIC (90,140,60), FV_PANTS (110,80,50), FV_ROPE (178,148,96)
;   m_avatar           AV_HAIR (92,58,32), AV_GREY (208,208,208), AV_LINEN (226,216,192), AV_PANTS (64,68,96)
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
