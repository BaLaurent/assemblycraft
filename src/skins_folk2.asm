; skins_folk2.asm: skin models of the Villagers' elder and merchant and of the role extras (0.13 "looks"): the two
; robed humanoids with folded arms, and the overlays drawn on top of a faction body (hat, helmet, pack, crown and one hood per
; faction). Data only: bones, parts and paint ops for skin.asm (art.inc, common.inc "0.13 looks"); nothing here runs.
;
;   m_villager_elder     the Villagers' leader: long silver beard, bald crown with side hair, purple robe with gold trim (ve_)
;   m_villager_merchant  the Villagers' trader: handlebar moustache, tweed flat cap, russet robe, linen apron, coin pouch (vm_)
;   m_extra_hat          the leader's hat: black felt, a braided gold band and buckle, a crimson plume (xh_)
;   m_extra_helmet       a riveted iron helmet with a nose guard, the face open between two cheek strips (xm_)
;   m_extra_pack         a wooden-frame pack: canvas bag, buckled flap, a strapped bedroll, chest straps (xp_)
;   m_extra_crown        the champion's gold spiked crown with a ruby and sapphires (xc_)
;   m_hood_villagers, m_hood_bandits, m_hood_cult, m_hood_beastfolk, m_hood_stonekin
;                        a faction hood with a framed face opening: green cloth, dark leather, ash grey with a peak, fur, chain
;                        mail (hv_ hb_ hc_ hf_ hs_)
; One section per model, in file order: ramps, then palette and bitmaps (section .rodata), then the model (section .data).
;
; Elder and merchant are built on the humanoid skeleton of skins_folk.asm (texels, origin = feet centre, front = -Z): BK_LLEG
; x -6..0 and BK_RLEG x 0..6 (y 0..24, z -3..3, pivot (24, 0), swing +1 / -1), torso x -8..8 y 24..46 z -4..4, head x -8..8
; y 46..62 z -8..8. They keep the folded-arms look: no BK_LARM / BK_RARM, the arms are rigid parts of the BK_BODY bone (an upper
; sleeve at each side, x +-(8..12) y 31..46, the crossed forearms x -11..11 y 31..37 z -8..-3 and a hand at each end), and the
; robes are painted on the torso and the legs (no skirt box; the legs swing under the painted hem). Both pairs of legs are two
; separate skins, mirrored, so the robe opening and the apron run down the middle of the pair.
;
; The extras are single BK_BODY models on the same origin, drawn after the body (folk_model: crown for a champion; hat for the
; leader of a non-Villagers faction; the faction hood for an acolyte guard or patrol, the helmet for any other guard or patrol;
; pack for a traveller, a caravan merchant and the trader of another faction). Fits: hat y >= 61, helmet x -9..9 y 52..64 z -9..9
; with the front open from y 52 to 58, hood x -9..9 y 44..64 z -9..9 with the face opening, crown y 62..68, pack z 4..10 y 28..44.
; Overlays must not z-fight the body: the bodies' overlays use even grows (0, 4, 6, 8, 10: planes on multiples of 1/4 texel),
; so every extra plane that can lie over a body sits on an odd eighth (grow 1, 3, 5, 7), at least 1/8 texel from any of them,
; and the shells stand 0.4 .. 1.4 texel clear of the head (x +-8) and the hair (+-8.5). Hat parts also avoid the beastfolk
; ears (x +-3..7), the hoods leave the snout and the ears of the beastfolk body free (they poke through).
; A hood is a shell (grow 3, SKPF_CUTOUT: the face opening is the cols 3..14, rows 4..16 hole of its front image) framed by a lip
; of four bars (brow, two cheeks, chin), so the opening has inner walls; back faces are culled, so a hole in a single box alone
; would show no depth. The faction tones of the hoods and the bodies come from the factions design doc ("Blocks and art").
;
; Local helpers (private to this file):
;   RAMP prefix, r, g, b                defines prefix_1 .. prefix_4: highlight (base x 1.2, clamped), base, shade (x 0.75),
;                                       deep (x 0.55), packed RGBO
;   PART name, x0, y0, z0, w, h, d, grow, flags
;   PART_AS name, k, x0, y0, z0, grow, flags
;                                       SKPART / SKPART_AS; `name` becomes the part's index, so the paint ops name parts
;                                       (names are <model prefix>_<part>)
; Conventions (as skins_folk.asm):
;   - one palette per model (<prefix>_pal); a material takes a group of letters: lower case = base tone, upper case =
;     highlight, then two more letters for shade and deep (the comment above each palette lists them). '_' is a transparent
;     texel (PALT, cutouts), '.' keeps the texel.
;   - a part's ops run: SK_FILL (grain), details, SK_GRAD on the four vertical faces, then the features that keep their colour.
;   - bitmaps have the size of the face they paint (the unwrap table of the design doc); the light comes from the top left.
;   - grain: noise 15 on cloth, skin and leather, 31 on hair, fur and wood, 0 on metal, gold and eyes.
;   - skin_build packs the unwraps in record order with next-fit shelves: a part costs 2(w+d) x (d+h) atlas texels (a cutout
;     overlay as much as a solid part), an AS part nothing.
;   - The 11 models of this file take about 437 atlas rows together (of 3072), packed in this order; packed alone:
;     elder 72, merchant 73, hat 22, helmet 30, pack 18, crown 22, hood villagers 38, hood bandits 38, hood cult
;     42, hood beastfolk 38, hood stonekin 38.
; Ramps (RAMP: _1 highlight, _2 base, _3 shade, _4 deep; AC_* are the shared material ramps of art.inc):
;   m_villager_elder       VE_SKIN (225,180,140), VE_HAIR (226,226,234), VE_ROBE (108,60,138)
;   m_villager_merchant    VM_SKIN (225,180,140), VM_HAIR (96,62,36), VM_ROBE (140,88,52), VM_APRON (230,220,192), VM_CAP (118,104,86), VM_SACK (176,146,92)
;   m_extra_hat            XH_FELT (70,54,56)
;   m_extra_helmet         AC_* only
;   m_extra_pack           XP_CANVAS (158,144,102), XP_WOOL (152,70,60)
;   m_extra_crown          AC_* only
;   m_hood_villagers       HV_CLOTH (90,140,60), HV_LINING (60,96,44)
;   m_hood_bandits         HB_LEATHER (80,55,35), HB_CLOTH (48,44,46), HB_RED (150,30,30)
;   m_hood_cult            HC_ASH (74,68,74), HC_RED (120,26,38)
;   m_hood_beastfolk       HF_FUR (150,130,100), HF_PELT (205,188,150)
;   m_hood_stonekin        HS_MAIL (140,140,150), HS_LEATHER (80,60,45)
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
; m_villager_elder
; ===================================================================================================
RAMP VE_SKIN, 225, 180, 140             ; head and hands (the Villagers skin)
RAMP VE_HAIR, 226, 226, 234             ; silver-white hair, beard and brows
RAMP VE_ROBE, 108, 60, 138              ; the elder robe: purple

section .rodata
; The characters of every ve_ bitmap. Groups: base, highlight, shade, deep.
;   s S k K skin (b blush)   h H j J silver hair   r R o O purple robe   y Y u U gold (AC)
;   l L e E leather (AC)   c cream shirt   g G ruby   w sclera   W glint   i I iris   x pupil   m M mouth
;   _ transparent
align 8
ve_pal:
    PALC 's', VE_SKIN_2
    PALC 'S', VE_SKIN_1
    PALC 'k', VE_SKIN_3
    PALC 'K', VE_SKIN_4
    PALC 'b', RGBO(232, 140, 120)
    PALC 'h', VE_HAIR_2
    PALC 'H', VE_HAIR_1
    PALC 'j', VE_HAIR_3
    PALC 'J', VE_HAIR_4
    PALC 'r', VE_ROBE_2
    PALC 'R', VE_ROBE_1
    PALC 'o', VE_ROBE_3
    PALC 'O', VE_ROBE_4
    PALC 'y', AC_GOLD_2
    PALC 'Y', AC_GOLD_1
    PALC 'u', AC_GOLD_3
    PALC 'U', AC_GOLD_4
    PALC 'l', AC_LEATHER_2
    PALC 'L', AC_LEATHER_1
    PALC 'e', AC_LEATHER_3
    PALC 'E', AC_LEATHER_4
    PALC 'c', RGBO(232, 220, 190)
    PALC 'g', RGBO(190, 40, 64)
    PALC 'G', RGBO(255, 150, 150)
    PALC 'w', RGBO(246, 246, 240)
    PALC 'W', RGBO(255, 255, 255)
    PALC 'i', RGBO(98, 128, 164)
    PALC 'I', RGBO(170, 198, 226)
    PALC 'x', RGBO(28, 30, 44)
    PALC 'm', RGBO(176, 108, 92)
    PALC 'M', RGBO(112, 56, 48)
    PALT '_'
    dq 0

    ; ve_torso_front (16x22): ve_torso FRONT
    SKROWS ve_torso_front_rows, 16, 22
    SKROW "RoYyo......oyYo."
    SKROW "RoYyo......oyYo."
    SKROW "RoYyo......oyYo."
    SKROW "RoYyo.o....oyYo."
    SKROW "RoYyo.o....oyYo."
    SKROW "RoYyo..oRo.oyYo."
    SKROW "RoYyo..oRo.oyYo."
    SKROW "RoYyo.ooR..oyYo."
    SKROW "RoYyo.ooR..oyYo."
    SKROW "RoYyo..oRo.oyYo."
    SKROW "RoYyo..oRo.oyYo."
    SKROW "RoYyo.ooR..oyYo."
    SKROW "RoYyo.ooR..oyYo."
    SKROW "RoYyo..oRo.oyYo."
    SKROW "RoYyo..oRo.oyYo."
    SKROW "RoYyo.ooR..oyYo."
    SKROW "RoYyo.ooR..oyYo."
    SKROW "RoYyo....o.oyYo."
    SKROW "RoYyo....o.oyYo."
    SKROW "oooooooooooooooo"
    SKROW "rrrrrrrrrrrrrrrr"
    SKROW "oooooooooooooooo"
    SKROWS_END
    align 8
    SKBMP ve_torso_front, ve_torso_front_rows, 16, 22, ve_pal
    ; ve_torso_back (16x22): ve_torso BACK
    SKROWS ve_torso_back_rows, 16, 22
    SKROW "R..............."
    SKROW "R..............."
    SKROW "R..............."
    SKROW "R..............."
    SKROW "R..............."
    SKROW "R..............."
    SKROW "R..............."
    SKROW "R..............."
    SKROW "R..............."
    SKROW "R......oR......."
    SKROW "R......yY......."
    SKROW "R.....yYYy......"
    SKROW "R.o..yYuuYyo...."
    SKROW "R.oo.yYuuYyoo..."
    SKROW "R.oo..yYYy.oo..."
    SKROW "R.oo...yY..oo..."
    SKROW "R......oR......."
    SKROW "R......oR......."
    SKROW "R......oR......."
    SKROW "oooooooooooooooo"
    SKROW "R......oR......."
    SKROW "oooooooooooooooo"
    SKROWS_END
    align 8
    SKBMP ve_torso_back, ve_torso_back_rows, 16, 22, ve_pal
    ; ve_torso_side (8x22): ve_torso RIGHT, ve_torso LEFT
    SKROWS ve_torso_side_rows, 8, 22
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "...o...."
    SKROW "...o.o.."
    SKROW "...o...."
    SKROW "...o...."
    SKROW "...o.o.."
    SKROW "...o...."
    SKROW "...o...."
    SKROW "...o.o.."
    SKROW "...o...."
    SKROW "...o...."
    SKROW "oooooooo"
    SKROW "........"
    SKROW "oooooooo"
    SKROWS_END
    align 8
    SKBMP ve_torso_side, ve_torso_side_rows, 8, 22, ve_pal
    ; ve_mantle_front (16x9): ve_mantle FRONT
    SKROWS ve_mantle_front_rows, 16, 9
    SKROW "YYYYYYYYYYYYYYYY"
    SKROW "yyyyyyyyyyyyyyyy"
    SKROW "Rr...r...r...r.."
    SKROW "Rr...r...r...r.."
    SKROW "Rr...r...r...r.."
    SKROW "Rr...r...r...r.."
    SKROW "YYYYYYYYYYYYYYYY"
    SKROW "yyuuyyuuyyuuyyuu"
    SKROW "uuUUuuUUuuUUuuUU"
    SKROWS_END
    align 8
    SKBMP ve_mantle_front, ve_mantle_front_rows, 16, 9, ve_pal
    ; ve_mantle_back (16x9): ve_mantle BACK
    SKROWS ve_mantle_back_rows, 16, 9
    SKROW "YYYYYYYYYYYYYYYY"
    SKROW "yyyyyyyyyyyyyyyy"
    SKROW "R..r...r...r...r"
    SKROW "R..r...r...r...r"
    SKROW "R..r...r...r...r"
    SKROW "R..r...r...r...r"
    SKROW "YYYYYYYYYYYYYYYY"
    SKROW "yyuuyyuuyyuuyyuu"
    SKROW "uuUUuuUUuuUUuuUU"
    SKROWS_END
    align 8
    SKBMP ve_mantle_back, ve_mantle_back_rows, 16, 9, ve_pal
    ; ve_mantle_side (8x9): ve_mantle RIGHT, ve_mantle LEFT
    SKROWS ve_mantle_side_rows, 8, 9
    SKROW "YYYYYYYY"
    SKROW "yyyyyyyy"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "YYYYYYYY"
    SKROW "yyuuyyuu"
    SKROW "uuUUuuUU"
    SKROWS_END
    align 8
    SKBMP ve_mantle_side, ve_mantle_side_rows, 8, 9, ve_pal
    ; ve_mantle_top (16x8): ve_mantle TOP
    SKROWS ve_mantle_top_rows, 16, 8
    SKROW "y.y.y.y.y.y.y.yy"
    SKROW "................"
    SKROW "y..............y"
    SKROW "................"
    SKROW "y..............y"
    SKROW "................"
    SKROW "y..............y"
    SKROW "y.y.y.y.y.y.y.y."
    SKROWS_END
    align 8
    SKBMP ve_mantle_top, ve_mantle_top_rows, 16, 8, ve_pal
    ; ve_sash_band (16x3): ve_sash FRONT, ve_sash BACK
    SKROWS ve_sash_band_rows, 16, 3
    SKROW "yuyuyuyuyuyuyuyu"
    SKROW "uyuyuyuyuyuyuyuy"
    SKROW "uUuUuUuUuUuUuUuU"
    SKROWS_END
    align 8
    SKBMP ve_sash_band, ve_sash_band_rows, 16, 3, ve_pal
    ; ve_sash_side (8x3): ve_sash LEFT, ve_sash RIGHT
    SKROWS ve_sash_side_rows, 8, 3
    SKROW "yuyuyuyu"
    SKROW "uyuyuyuy"
    SKROW "uUuUuUuU"
    SKROWS_END
    align 8
    SKBMP ve_sash_side, ve_sash_side_rows, 8, 3, ve_pal
    ; ve_clasp_front (4x3): ve_clasp FRONT
    SKROWS ve_clasp_front_rows, 4, 3
    SKROW "YYYY"
    SKROW "uGgu"
    SKROW "uuUU"
    SKROWS_END
    align 8
    SKBMP ve_clasp_front, ve_clasp_front_rows, 4, 3, ve_pal
    ; ve_sleeve_front (4x15): ve_sleeve_l FRONT
    SKROWS ve_sleeve_front_rows, 4, 15
    SKROW "RRRR"
    SKROW "R..o"
    SKROW "R.oo"
    SKROW "R..o"
    SKROW "R..o"
    SKROW "R.oo"
    SKROW "R..o"
    SKROW "R..o"
    SKROW "R.oo"
    SKROW "R..o"
    SKROW "R..o"
    SKROW "R.oo"
    SKROW "YYYY"
    SKROW "yyyy"
    SKROW "uuuu"
    SKROWS_END
    align 8
    SKBMP ve_sleeve_front, ve_sleeve_front_rows, 4, 15, ve_pal
    ; ve_sleeve_back (4x15): ve_sleeve_l BACK
    SKROWS ve_sleeve_back_rows, 4, 15
    SKROW "RRRR"
    SKROW "R..o"
    SKROW "R.oo"
    SKROW "R..o"
    SKROW "R..o"
    SKROW "R.oo"
    SKROW "R..o"
    SKROW "R..o"
    SKROW "R.oo"
    SKROW "R..o"
    SKROW "R..o"
    SKROW "R.oo"
    SKROW "YYYY"
    SKROW "yyyy"
    SKROW "uuuu"
    SKROWS_END
    align 8
    SKBMP ve_sleeve_back, ve_sleeve_back_rows, 4, 15, ve_pal
    ; ve_sleeve_left (6x15): ve_sleeve_l LEFT
    SKROWS ve_sleeve_left_rows, 6, 15
    SKROW "RRRRRR"
    SKROW "R....o"
    SKROW "R..o.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R..o.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R..o.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R..o.o"
    SKROW "YYYYYY"
    SKROW "yyyyyy"
    SKROW "uuuuuu"
    SKROWS_END
    align 8
    SKBMP ve_sleeve_left, ve_sleeve_left_rows, 6, 15, ve_pal
    ; ve_sleeve_right (6x15): ve_sleeve_l RIGHT
    SKROWS ve_sleeve_right_rows, 6, 15
    SKROW "RRRRRR"
    SKROW "R....o"
    SKROW "R..o.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R..o.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R..o.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R..o.o"
    SKROW "YYYYYY"
    SKROW "yyyyyy"
    SKROW "uuuuuu"
    SKROWS_END
    align 8
    SKBMP ve_sleeve_right, ve_sleeve_right_rows, 6, 15, ve_pal
    ; ve_fore_front (22x6): ve_fore FRONT
    SKROWS ve_fore_front_rows, 22, 6
    SKROW "RRRRRYuRRRRRRRRYuRRRRR"
    SKROW "..o..Yuo....o..Yuo...."
    SKROW "..o..Yuo....o..Yuo...."
    SKROW "..o..Yuo....o..Yuo...."
    SKROW "..o..Yuo....o..Yuo...."
    SKROW "oooooooooooooooooooooo"
    SKROWS_END
    align 8
    SKBMP ve_fore_front, ve_fore_front_rows, 22, 6, ve_pal
    ; ve_hand_front (4x4): ve_hand_l FRONT
    SKROWS ve_hand_front_rows, 4, 4
    SKROW "SSss"
    SKROW "sKsK"
    SKROW "sKsK"
    SKROW "kkkk"
    SKROWS_END
    align 8
    SKBMP ve_hand_front, ve_hand_front_rows, 4, 4, ve_pal
    ; ve_face (16x16): ve_head FRONT
    SKROWS ve_face_rows, 16, 16
    SKROW "................"
    SKROW ".....SSSSSS....."
    SKROW "...kkkk..kkkk..."
    SKROW ".....kk..kk....."
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "...WI......WI..."
    SKROW "..wxx......xxw.."
    SKROW ".k.ii......ii.k."
    SKROW ".k.k........k.k."
    SKROW "Hh............hh"
    SKROW "Hh....mmmm....hh"
    SKROW "Hh...MMMMMM...hh"
    SKROW "Hh............hh"
    SKROW "Hh............hh"
    SKROWS_END
    align 8
    SKBMP ve_face, ve_face_rows, 16, 16, ve_pal
    ; ve_head_back (16x16): ve_head BACK
    SKROWS ve_head_back_rows, 16, 16
    SKROW "ssssssssssssssss"
    SKROW "ssssssssssssssss"
    SKROW "ssssssssssssssss"
    SKROW "ssssssssssssssss"
    SKROW "ssssssssssssssss"
    SKROW "ssssssssssssssss"
    SKROW "ssssssssssssssss"
    SKROW "ssssssssssssssss"
    SKROW "ssssssssssssssss"
    SKROW "ssssssssssssssss"
    SKROW "ssssssssssssssss"
    SKROW "ssssssssssssssss"
    SKROW "kssksskssksskssk"
    SKROW "ssssssssssssssss"
    SKROW "kkkkkkkkkkkkkkkk"
    SKROW "ssssssssssssssss"
    SKROWS_END
    align 8
    SKBMP ve_head_back, ve_head_back_rows, 16, 16, ve_pal
    ; ve_head_right (16x16): ve_head RIGHT
    SKROWS ve_head_right_rows, 16, 16
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "........jHHHHHHH"
    SKROW "........jhhhjhhh"
    SKROW "........jhhhjhhh"
    SKROW "........jhhhjhhh"
    SKROW "........jhhhjhhh"
    SKROW "kkkkkkkkkkkkkkkk"
    SKROWS_END
    align 8
    SKBMP ve_head_right, ve_head_right_rows, 16, 16, ve_pal
    ; ve_head_left (16x16): ve_head LEFT
    SKROWS ve_head_left_rows, 16, 16
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "HHHHHHHj........"
    SKROW "hhhjhhhj........"
    SKROW "hhhjhhhj........"
    SKROW "hhhjhhhj........"
    SKROW "hhhjhhhj........"
    SKROW "kkkkkkkkkkkkkkkk"
    SKROWS_END
    align 8
    SKBMP ve_head_left, ve_head_left_rows, 16, 16, ve_pal
    ; ve_hair_front (16x16): ve_hair FRONT
    SKROWS ve_hair_front_rows, 16, 16
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW ".______________."
    SKROW "H______________H"
    SKROW "H______________H"
    SKROW "H______________H"
    SKROW "j______________J"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP ve_hair_front, ve_hair_front_rows, 16, 16, ve_pal
    ; ve_hair_back (16x16): ve_hair BACK
    SKROWS ve_hair_back_rows, 16, 16
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "_.............._"
    SKROW "..j.H.j.H.j.H.j."
    SKROW "H.j.H.j.H.j.H.j."
    SKROW "H.j.H.j.H.j.H.j."
    SKROW "H.j.H.j.H.j.H.j."
    SKROW "H.j.H.j.H.j.H.j."
    SKROW "j.j.H.j.H.j.H.jJ"
    SKROW "_.j.H.j.H.j.H.j_"
    SKROW "_JjJH.j.j.jJHJj_"
    SKROW "__j_HJ_J_.j_j___"
    SKROW "____j____J______"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP ve_hair_back, ve_hair_back_rows, 16, 16, ve_pal
    ; ve_hair_right (16x16): ve_hair RIGHT
    SKROWS ve_hair_right_rows, 16, 16
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "_.......________"
    SKROW "..j.H.j.....____"
    SKROW "H.j.H.j___j...__"
    SKROW "H.j.H.j___j.jJ__"
    SKROW "H.j.H.j___jJ____"
    SKROW "H.j.H.j_________"
    SKROW "H.j.H.j_________"
    SKROW "H.j.j.jJ________"
    SKROW "j.j._J__________"
    SKROW "_J_J____________"
    SKROW "________________"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP ve_hair_right, ve_hair_right_rows, 16, 16, ve_pal
    ; ve_hair_left (16x16): ve_hair LEFT
    SKROWS ve_hair_left_rows, 16, 16
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________......._"
    SKROW "____.....j.H.j.."
    SKROW "__...j___j.H.j.H"
    SKROW "__Jj.j___j.H.j.H"
    SKROW "____Jj___j.H.j.H"
    SKROW "_________j.H.j.H"
    SKROW "_________j.H.j.H"
    SKROW "________Jj.j.j.H"
    SKROW "__________J_.j.j"
    SKROW "____________J_J_"
    SKROW "________________"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP ve_hair_left, ve_hair_left_rows, 16, 16, ve_pal
    ; ve_hair_top (16x16): ve_hair TOP
    SKROWS ve_hair_top_rows, 16, 16
    SKROW "________________"
    SKROW "________________"
    SKROW "____hH__________"
    SKROW "_____h__________"
    SKROW "__________hH____"
    SKROW "___________h____"
    SKROW "________________"
    SKROW "________H_______"
    SKROW "_______Hh_______"
    SKROW "________________"
    SKROW "___H____________"
    SKROW "____________H___"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP ve_hair_top, ve_hair_top_rows, 16, 16, ve_pal
    ; ve_hair_bottom (16x16): ve_hair BOTTOM
    SKROWS ve_hair_bottom_rows, 16, 16
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
    SKROW "__............__"
    SKROW "__............__"
    SKROW "__............__"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP ve_hair_bottom, ve_hair_bottom_rows, 16, 16, ve_pal
    ; ve_nose_front (2x3): ve_nose FRONT
    SKROWS ve_nose_front_rows, 2, 3
    SKROW "SS"
    SKROW "ss"
    SKROW "bk"
    SKROWS_END
    align 8
    SKBMP ve_nose_front, ve_nose_front_rows, 2, 3, ve_pal
    ; ve_ear (2x4): ve_ear_l LEFT, ve_ear_l RIGHT
    SKROWS ve_ear_rows, 2, 4
    SKROW "ss"
    SKROW "kk"
    SKROW "sk"
    SKROW "kk"
    SKROWS_END
    align 8
    SKBMP ve_ear, ve_ear_rows, 2, 4, ve_pal
    ; ve_brow_front (5x2): ve_brow_l FRONT
    SKROWS ve_brow_front_rows, 5, 2
    SKROW "jHHHj"
    SKROW "hhhhh"
    SKROWS_END
    align 8
    SKBMP ve_brow_front, ve_brow_front_rows, 5, 2, ve_pal
    ; ve_stache_front (10x3): ve_stache FRONT
    SKROWS ve_stache_front_rows, 10, 3
    SKROW "_HHhhhhHH_"
    SKROW "HhhhhhhhhH"
    SKROW "hj______jh"
    SKROWS_END
    align 8
    SKBMP ve_stache_front, ve_stache_front_rows, 10, 3, ve_pal
    ; ve_stache_back (10x3): ve_stache BACK
    SKROWS ve_stache_back_rows, 10, 3
    SKROW "_jjjjjjjj_"
    SKROW "jjjjjjjjjj"
    SKROW "jj______jj"
    SKROWS_END
    align 8
    SKBMP ve_stache_back, ve_stache_back_rows, 10, 3, ve_pal
    ; ve_beard_a_front (14x5): ve_beard_a FRONT
    SKROWS ve_beard_a_front_rows, 14, 5
    SKROW "........H.j.H."
    SKROW "........H.j.H."
    SKROW "H.j.H.j.H.j.H."
    SKROW "H.j.....H...H."
    SKROW "_...........H_"
    SKROWS_END
    align 8
    SKBMP ve_beard_a_front, ve_beard_a_front_rows, 14, 5, ve_pal
    ; ve_beard_a_back (14x5): ve_beard_a BACK
    SKROWS ve_beard_a_back_rows, 14, 5
    SKROW "H.j...j.H....."
    SKROW "H.j.H.j.H.j.H."
    SKROW "H.j.H.j.H.j.H."
    SKROW "H...H.j.H...H."
    SKROW "_.....j.H...H_"
    SKROWS_END
    align 8
    SKBMP ve_beard_a_back, ve_beard_a_back_rows, 14, 5, ve_pal
    ; ve_beard_a_left (7x5): ve_beard_a LEFT
    SKROWS ve_beard_a_left_rows, 7, 5
    SKROW "H.j...j"
    SKROW "H.j.H.j"
    SKROW "H.j.H.j"
    SKROW "H...H.j"
    SKROW "_....._"
    SKROWS_END
    align 8
    SKBMP ve_beard_a_left, ve_beard_a_left_rows, 7, 5, ve_pal
    ; ve_beard_a_right (7x5): ve_beard_a RIGHT
    SKROWS ve_beard_a_right_rows, 7, 5
    SKROW "......."
    SKROW "......."
    SKROW "H.j.H.j"
    SKROW "H.j...."
    SKROW "_....._"
    SKROWS_END
    align 8
    SKBMP ve_beard_a_right, ve_beard_a_right_rows, 7, 5, ve_pal
    ; ve_beard_a_top (14x7): ve_beard_a TOP
    SKROWS ve_beard_a_top_rows, 14, 7
    SKROW "H.j.H.j.H.j.H."
    SKROW "H.j.H.j.H.j.H."
    SKROW "H.j.H.j.H.j.H."
    SKROW "H.j.H.j.H.j.H."
    SKROW "H.j.H.j.H.j.H."
    SKROW "H.j.H.j.H.j.H."
    SKROW "H.j.H.j.H.j.H."
    SKROWS_END
    align 8
    SKBMP ve_beard_a_top, ve_beard_a_top_rows, 14, 7, ve_pal
    ; ve_beard_b_front (12x4): ve_beard_b FRONT
    SKROWS ve_beard_b_front_rows, 12, 4
    SKROW "H...H.j.H..."
    SKROW "H.j.H.j.H..."
    SKROW "H.j...j.H.j."
    SKROW "_.j...j.H.j_"
    SKROWS_END
    align 8
    SKBMP ve_beard_b_front, ve_beard_b_front_rows, 12, 4, ve_pal
    ; ve_beard_b_back (12x4): ve_beard_b BACK
    SKROWS ve_beard_b_back_rows, 12, 4
    SKROW "....H.....j."
    SKROW "H.j.H...H.j."
    SKROW "H...H.j....."
    SKROW "_...H.j...._"
    SKROWS_END
    align 8
    SKBMP ve_beard_b_back, ve_beard_b_back_rows, 12, 4, ve_pal
    ; ve_beard_b_left (6x4): ve_beard_b LEFT
    SKROWS ve_beard_b_left_rows, 6, 4
    SKROW "....H."
    SKROW "H.j.H."
    SKROW "H...H."
    SKROW "_...H_"
    SKROWS_END
    align 8
    SKBMP ve_beard_b_left, ve_beard_b_left_rows, 6, 4, ve_pal
    ; ve_beard_b_right (6x4): ve_beard_b RIGHT
    SKROWS ve_beard_b_right_rows, 6, 4
    SKROW "H...H."
    SKROW "H.j.H."
    SKROW "H.j..."
    SKROW "_.j.._"
    SKROWS_END
    align 8
    SKBMP ve_beard_b_right, ve_beard_b_right_rows, 6, 4, ve_pal
    ; ve_beard_b_top (12x6): ve_beard_b TOP
    SKROWS ve_beard_b_top_rows, 12, 6
    SKROW "H.j.H.j.H.j."
    SKROW "H.j.H.j.H.j."
    SKROW "H.j.H.j.H.j."
    SKROW "H.j.H.j.H.j."
    SKROW "H.j.H.j.H.j."
    SKROW "H.j.H.j.H.j."
    SKROWS_END
    align 8
    SKBMP ve_beard_b_top, ve_beard_b_top_rows, 12, 6, ve_pal
    ; ve_beard_c_front (10x4): ve_beard_c FRONT
    SKROWS ve_beard_c_front_rows, 10, 4
    SKROW "......j..."
    SKROW "H.j...j..."
    SKROW "..j...j.H."
    SKROW "_.....j.._"
    SKROWS_END
    align 8
    SKBMP ve_beard_c_front, ve_beard_c_front_rows, 10, 4, ve_pal
    ; ve_beard_c_back (10x4): ve_beard_c BACK
    SKROWS ve_beard_c_back_rows, 10, 4
    SKROW "......j..."
    SKROW "..j...j.H."
    SKROW "H.j.H.j.H."
    SKROW "_...H...._"
    SKROWS_END
    align 8
    SKBMP ve_beard_c_back, ve_beard_c_back_rows, 10, 4, ve_pal
    ; ve_beard_c_left (5x4): ve_beard_c LEFT
    SKROWS ve_beard_c_left_rows, 5, 4
    SKROW "....."
    SKROW "..j.."
    SKROW "H.j.H"
    SKROW "_..._"
    SKROWS_END
    align 8
    SKBMP ve_beard_c_left, ve_beard_c_left_rows, 5, 4, ve_pal
    ; ve_beard_c_right (5x4): ve_beard_c RIGHT
    SKROWS ve_beard_c_right_rows, 5, 4
    SKROW "....."
    SKROW "H.j.."
    SKROW "..j.."
    SKROW "_..._"
    SKROWS_END
    align 8
    SKBMP ve_beard_c_right, ve_beard_c_right_rows, 5, 4, ve_pal
    ; ve_beard_c_top (10x5): ve_beard_c TOP
    SKROWS ve_beard_c_top_rows, 10, 5
    SKROW "H.j.H.j.H."
    SKROW "H.j.H.j.H."
    SKROW "H.j.H.j.H."
    SKROW "H.j.H.j.H."
    SKROW "H.j.H.j.H."
    SKROWS_END
    align 8
    SKBMP ve_beard_c_top, ve_beard_c_top_rows, 10, 5, ve_pal
    ; ve_beard_d_front (8x3): ve_beard_d FRONT
    SKROWS ve_beard_d_front_rows, 8, 3
    SKROW "H......."
    SKROW "........"
    SKROW "_...H.._"
    SKROWS_END
    align 8
    SKBMP ve_beard_d_front, ve_beard_d_front_rows, 8, 3, ve_pal
    ; ve_beard_d_back (8x3): ve_beard_d BACK
    SKROWS ve_beard_d_back_rows, 8, 3
    SKROW "....H.j."
    SKROW "H......."
    SKROW "_......_"
    SKROWS_END
    align 8
    SKBMP ve_beard_d_back, ve_beard_d_back_rows, 8, 3, ve_pal
    ; ve_beard_d_left (5x3): ve_beard_d LEFT
    SKROWS ve_beard_d_left_rows, 5, 3
    SKROW "....H"
    SKROW "H...."
    SKROW "_..._"
    SKROWS_END
    align 8
    SKBMP ve_beard_d_left, ve_beard_d_left_rows, 5, 3, ve_pal
    ; ve_beard_d_right (5x3): ve_beard_d RIGHT
    SKROWS ve_beard_d_right_rows, 5, 3
    SKROW "H...."
    SKROW "....."
    SKROW "_..._"
    SKROWS_END
    align 8
    SKBMP ve_beard_d_right, ve_beard_d_right_rows, 5, 3, ve_pal
    ; ve_beard_d_top (8x5): ve_beard_d TOP
    SKROWS ve_beard_d_top_rows, 8, 5
    SKROW "H.j.H.j."
    SKROW "H.j.H.j."
    SKROW "H.j.H.j."
    SKROW "H.j.H.j."
    SKROW "H.j.H.j."
    SKROWS_END
    align 8
    SKBMP ve_beard_d_top, ve_beard_d_top_rows, 8, 5, ve_pal
    ; ve_beard_e_front (6x2): ve_beard_e FRONT
    SKROWS ve_beard_e_front_rows, 6, 2
    SKROW "......"
    SKROW "_jjjj_"
    SKROWS_END
    align 8
    SKBMP ve_beard_e_front, ve_beard_e_front_rows, 6, 2, ve_pal
    ; ve_beard_e_back (6x2): ve_beard_e BACK
    SKROWS ve_beard_e_back_rows, 6, 2
    SKROW "......"
    SKROW "_jjjj_"
    SKROWS_END
    align 8
    SKBMP ve_beard_e_back, ve_beard_e_back_rows, 6, 2, ve_pal
    ; ve_beard_e_left (5x2): ve_beard_e LEFT
    SKROWS ve_beard_e_left_rows, 5, 2
    SKROW "....."
    SKROW "_jjj_"
    SKROWS_END
    align 8
    SKBMP ve_beard_e_left, ve_beard_e_left_rows, 5, 2, ve_pal
    ; ve_beard_e_right (5x2): ve_beard_e RIGHT
    SKROWS ve_beard_e_right_rows, 5, 2
    SKROW "....."
    SKROW "_jjj_"
    SKROWS_END
    align 8
    SKBMP ve_beard_e_right, ve_beard_e_right_rows, 5, 2, ve_pal
    ; ve_beard_e_top (6x5): ve_beard_e TOP
    SKROWS ve_beard_e_top_rows, 6, 5
    SKROW "H.j.H."
    SKROW "H.j.H."
    SKROW "H.j.H."
    SKROW "H.j.H."
    SKROW "H.j.H."
    SKROWS_END
    align 8
    SKBMP ve_beard_e_top, ve_beard_e_top_rows, 6, 5, ve_pal
    ; ve_leg_l_front (6x24): ve_leg_l FRONT
    SKROWS ve_leg_l_front_rows, 6, 24
    SKROW "uo...o"
    SKROW "uo...o"
    SKROW "uoRo.o"
    SKROW "uo.o.o"
    SKROW "uo...o"
    SKROW "uo...o"
    SKROW "uo...o"
    SKROW "uoRo.o"
    SKROW "uo.o.o"
    SKROW "uo...o"
    SKROW "uo...o"
    SKROW "uo...o"
    SKROW "uoRo.o"
    SKROW "uo.o.o"
    SKROW "uo...o"
    SKROW "uo...o"
    SKROW "uo...o"
    SKROW "uo...o"
    SKROW "uou.uo"
    SKROW "......"
    SKROW "yyyyyy"
    SKROW "uuuuuu"
    SKROW "......"
    SKROW "......"
    SKROWS_END
    align 8
    SKBMP ve_leg_l_front, ve_leg_l_front_rows, 6, 24, ve_pal
    ; ve_leg_l_back (6x24): ve_leg_l BACK
    SKROWS ve_leg_l_back_rows, 6, 24
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R.Ro.o"
    SKROW "R..o.o"
    SKROW "R..oRo"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R.Ro.o"
    SKROW "R..o.o"
    SKROW "R..oRo"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "Ru.u.u"
    SKROW "......"
    SKROW "yyyyyy"
    SKROW "uuuuuu"
    SKROW "......"
    SKROW "......"
    SKROWS_END
    align 8
    SKBMP ve_leg_l_back, ve_leg_l_back_rows, 6, 24, ve_pal
    ; ve_leg_l_side (6x24): ve_leg_l LEFT, ve_leg_l RIGHT
    SKROWS ve_leg_l_side_rows, 6, 24
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R.oo.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R.oo.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R.oo.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R.oo.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "u.u.uo"
    SKROW "......"
    SKROW "yyyyyy"
    SKROW "uuuuuu"
    SKROW "......"
    SKROW "......"
    SKROWS_END
    align 8
    SKBMP ve_leg_l_side, ve_leg_l_side_rows, 6, 24, ve_pal
    ; ve_leg_r_front (6x24): ve_leg_r FRONT
    SKROWS ve_leg_r_front_rows, 6, 24
    SKROW "o...ou"
    SKROW "o...ou"
    SKROW "o.Roou"
    SKROW "o..oou"
    SKROW "o...ou"
    SKROW "o...ou"
    SKROW "o...ou"
    SKROW "o.Roou"
    SKROW "o..oou"
    SKROW "o...ou"
    SKROW "o...ou"
    SKROW "o...ou"
    SKROW "o.Roou"
    SKROW "o..oou"
    SKROW "o...ou"
    SKROW "o...ou"
    SKROW "o...ou"
    SKROW "o...ou"
    SKROW "u.u.uu"
    SKROW "......"
    SKROW "yyyyyy"
    SKROW "uuuuuu"
    SKROW "......"
    SKROW "......"
    SKROWS_END
    align 8
    SKBMP ve_leg_r_front, ve_leg_r_front_rows, 6, 24, ve_pal
    ; ve_leg_r_back (6x24): ve_leg_r BACK
    SKROWS ve_leg_r_back_rows, 6, 24
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R.Ro.o"
    SKROW "R..o.o"
    SKROW "R..oRo"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R.Ro.o"
    SKROW "R..o.o"
    SKROW "R..oRo"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "Ru.u.u"
    SKROW "......"
    SKROW "yyyyyy"
    SKROW "uuuuuu"
    SKROW "......"
    SKROW "......"
    SKROWS_END
    align 8
    SKBMP ve_leg_r_back, ve_leg_r_back_rows, 6, 24, ve_pal
    ; ve_leg_r_side (6x24): ve_leg_r LEFT, ve_leg_r RIGHT
    SKROWS ve_leg_r_side_rows, 6, 24
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R.oo.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R.oo.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R.oo.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R.oo.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "u.u.uo"
    SKROW "......"
    SKROW "yyyyyy"
    SKROW "uuuuuu"
    SKROW "......"
    SKROW "......"
    SKROWS_END
    align 8
    SKBMP ve_leg_r_side, ve_leg_r_side_rows, 6, 24, ve_pal
    ; ve_foot_top (7x10): ve_foot_l TOP
    SKROWS ve_foot_top_rows, 7, 10
    SKROW "eeeeeee"
    SKROW "e.....L"
    SKROW "e.....L"
    SKROW "e.....L"
    SKROW "e.....L"
    SKROW "e.....L"
    SKROW "e.....L"
    SKROW "e.....L"
    SKROW "eeeeeee"
    SKROW "LLLLLLL"
    SKROWS_END
    align 8
    SKBMP ve_foot_top, ve_foot_top_rows, 7, 10, ve_pal

section .data
SKMODEL_BEGIN m_villager_elder, 32, 0, 11, 26, 0
    SKBONE BK_LLEG, 24, 0, 1.00
    PART ve_foot_l, -7, 0, -6, 7, 2, 10, 0, 0               ; slipper (the other shares its skin)
    PART ve_leg_l, -6, 0, -3, 6, 24, 6, 0, 0                ; robe
    SKBONE BK_BODY, 0, 0, 0.00
    PART ve_fore, -11, 31, -8, 22, 6, 5, 0, 0               ; the crossed forearms, gold cuffs
    PART ve_sash, -8, 27, -4, 16, 3, 8, 4, 0                ; braided gold sash
    PART ve_sleeve_l, -12, 31, -3, 4, 15, 6, 0, 0           ; folded arms: upper sleeve (the right one shares its skin)
    PART ve_mantle, -8, 37, -4, 16, 9, 8, 8, 0              ; shoulder mantle, gold hem
    PART ve_clasp, -2, 27, -5, 4, 3, 1, 0, 0                ; ruby clasp
    PART ve_hand_l, -10, 32, -10, 4, 4, 2, 0, 0             ; a hand (the other shares its skin)
    PART_AS ve_hand_r, ve_hand_l, 6, 32, -10, 0, 0
    PART_AS ve_sleeve_r, ve_sleeve_l, 8, 31, -3, 0, 0
    PART ve_torso, -8, 24, -4, 16, 22, 8, 0, 0              ; purple robe
    SKBONE BK_RLEG, 24, 0, -1.00
    PART ve_leg_r, 0, 0, -3, 6, 24, 6, 0, 0                 ; robe, mirrored
    PART_AS ve_foot_r, ve_foot_l, 0, 0, -6, 0, 0
    SKBONE BK_HEAD, 0, 0, 0.00
    PART ve_hair, -8, 46, -8, 16, 16, 16, 4, SKPF_CUTOUT    ; hair overlay: temples, sides and nape, bald top
    PART ve_ear_l, -9, 51, -1, 1, 4, 2, 0, 0                ; ear (the right one shares its skin)
    PART ve_nose, -1, 51, -10, 2, 3, 2, 0, 0                ; nose
    PART ve_head, -8, 46, -8, 16, 16, 16, 0, 0              ; the 16 texel head, bald
    PART ve_beard_a, -7, 43, -11, 14, 5, 7, 0, SKPF_CUTOUT  ; beard: chin and whiskers
    PART ve_beard_e, -3, 30, -9, 6, 2, 5, 0, SKPF_CUTOUT    ; beard: tip
    PART ve_beard_b, -6, 39, -10, 12, 4, 6, 0, SKPF_CUTOUT  ; beard: chest
    PART ve_stache, -5, 48, -10, 10, 3, 2, 0, SKPF_CUTOUT   ; walrus moustache
    PART_AS ve_ear_r, ve_ear_l, 8, 51, -1, 0, 0
    PART ve_brow_l, -6, 55, -9, 5, 2, 1, 0, 0               ; bushy brow (the other shares its skin)
    PART ve_beard_d, -4, 32, -9, 8, 3, 5, 0, SKPF_CUTOUT    ; beard: waist
    PART_AS ve_brow_r, ve_brow_l, 1, 55, -9, 0, 0
    PART ve_beard_c, -5, 35, -9, 10, 4, 5, 0, SKPF_CUTOUT   ; beard: belly
SKMODEL_PAINT
    ; --- ve_torso: purple robe, gold stole bands beside the beard, sun emblem on the back, folds
    SK_FILL ve_torso, SKM_ALL, VE_ROBE_2, 15
    SK_BMP ve_torso, SKF_FRONT, 0, 0, ve_torso_front
    SK_BMP ve_torso, SKF_BACK, 0, 0, ve_torso_back
    SK_BMP ve_torso, SKF_RIGHT, 0, 0, ve_torso_side
    SK_BMP ve_torso, SKF_LEFT, 0, 0, ve_torso_side
    SK_RECT ve_torso, SKF_BOTTOM, 0, 0, 16, 8, VE_ROBE_4, 0
    SK_GRAD ve_torso, SKM_SIDES, 272, 224
    ; --- ve_mantle: a lighter cape with a scalloped gold hem and a gold neck ring
    SK_FILL ve_mantle, SKM_ALL, VE_ROBE_1, 15
    SK_BMP ve_mantle, SKF_FRONT, 0, 0, ve_mantle_front
    SK_BMP ve_mantle, SKF_BACK, 0, 0, ve_mantle_back
    SK_BMP ve_mantle, SKF_RIGHT, 0, 0, ve_mantle_side
    SK_BMP ve_mantle, SKF_LEFT, 0, 0, ve_mantle_side
    SK_BMP ve_mantle, SKF_TOP, 0, 0, ve_mantle_top
    SK_RECT ve_mantle, SKF_BOTTOM, 0, 0, 16, 8, VE_ROBE_4, 0
    SK_GRAD ve_mantle, SKM_SIDES, 272, 224
    ; --- ve_sash: braided gold cord; ve_clasp: a ruby in a gold frame
    SK_FILL ve_sash, SKM_ALL, AC_GOLD_2, 0
    SK_BMP ve_sash, SKF_FRONT, 0, 0, ve_sash_band
    SK_BMP ve_sash, SKF_BACK, 0, 0, ve_sash_band
    SK_BMP ve_sash, SKF_LEFT, 0, 0, ve_sash_side
    SK_BMP ve_sash, SKF_RIGHT, 0, 0, ve_sash_side
    SK_RECT ve_sash, SKF_TOP, 0, 0, 16, 8, AC_GOLD_2, 0
    SK_RECT ve_sash, SKF_BOTTOM, 0, 0, 16, 8, AC_GOLD_4, 0
    SK_FILL ve_clasp, SKM_ALL, AC_GOLD_3, 0
    SK_BMP ve_clasp, SKF_FRONT, 0, 0, ve_clasp_front
    ; --- ve_sleeve_l (shared with ve_sleeve_r): purple, folds, gold trim at the elbow
    SK_FILL ve_sleeve_l, SKM_ALL, VE_ROBE_2, 15
    SK_BMP ve_sleeve_l, SKF_FRONT, 0, 0, ve_sleeve_front
    SK_BMP ve_sleeve_l, SKF_BACK, 0, 0, ve_sleeve_back
    SK_BMP ve_sleeve_l, SKF_LEFT, 0, 0, ve_sleeve_left
    SK_BMP ve_sleeve_l, SKF_RIGHT, 0, 0, ve_sleeve_right
    SK_RECT ve_sleeve_l, SKF_TOP, 0, 0, 4, 6, VE_ROBE_1, 15
    SK_RECT ve_sleeve_l, SKF_BOTTOM, 0, 0, 4, 6, VE_ROBE_4, 0
    SK_GRAD ve_sleeve_l, SKM_SIDES, 272, 224
    ; --- ve_fore: the crossed forearms: sleeve front with gold cuffs where the hands rest
    SK_FILL ve_fore, SKM_ALL, VE_ROBE_2, 15
    SK_BMP ve_fore, SKF_FRONT, 0, 0, ve_fore_front
    SK_RECT ve_fore, SKF_TOP, 0, 0, 22, 5, VE_ROBE_1, 15
    SK_RECT ve_fore, SKF_BOTTOM, 0, 0, 22, 5, VE_ROBE_4, 0
    SK_GRAD ve_fore, SKM_SIDES, 272, 224
    ; --- ve_hand_l (shared with ve_hand_r): the back of a hand, finger lines
    SK_FILL ve_hand_l, SKM_ALL, VE_SKIN_2, 7
    SK_BMP ve_hand_l, SKF_FRONT, 0, 0, ve_hand_front
    SK_RECT ve_hand_l, SKF_TOP, 0, 0, 4, 2, VE_SKIN_1, 0
    SK_RECT ve_hand_l, SKF_BOTTOM, 0, 0, 4, 2, VE_SKIN_4, 0
    SK_GRAD ve_hand_l, SKM_SIDES, 272, 224
    ; --- ve_head: bald, a deep-set face: wrinkles, bags, sagging eyes; whiskers on the lower sides
    SK_FILL ve_head, SKM_ALL, VE_SKIN_2, 15
    SK_GRAD ve_head, SKM_SIDES, 272, 224
    SK_RECT ve_head, SKF_TOP, 0, 0, 16, 16, VE_SKIN_2, 15
    SK_RECT ve_head, SKF_BOTTOM, 0, 0, 16, 16, VE_SKIN_4, 0
    SK_BMP ve_head, SKF_FRONT, 0, 0, ve_face
    SK_BMP ve_head, SKF_BACK, 0, 0, ve_head_back
    SK_BMP ve_head, SKF_RIGHT, 0, 0, ve_head_right
    SK_BMP ve_head, SKF_LEFT, 0, 0, ve_head_left
    ; --- ve_hair: silver cutout overlay: temples, side hair, nape; the top and the forehead stay bald
    SK_FILL ve_hair, SKM_ALL, VE_HAIR_2, 31
    SK_GRAD ve_hair, SKM_SIDES, 272, 224
    SK_BMP ve_hair, SKF_FRONT, 0, 0, ve_hair_front
    SK_BMP ve_hair, SKF_BACK, 0, 0, ve_hair_back
    SK_BMP ve_hair, SKF_RIGHT, 0, 0, ve_hair_right
    SK_BMP ve_hair, SKF_LEFT, 0, 0, ve_hair_left
    SK_BMP ve_hair, SKF_TOP, 0, 0, ve_hair_top
    SK_BMP ve_hair, SKF_BOTTOM, 0, 0, ve_hair_bottom
    ; --- ve_nose, ve_ear_l (shared with ve_ear_r), ve_brow_l (shared with ve_brow_r), ve_stache
    SK_FILL ve_nose, SKM_ALL, VE_SKIN_2, 7
    SK_BMP ve_nose, SKF_FRONT, 0, 0, ve_nose_front
    SK_RECT ve_nose, SKF_TOP, 0, 0, 2, 2, VE_SKIN_1, 0
    SK_RECT ve_nose, SKF_BOTTOM, 0, 0, 2, 2, VE_SKIN_4, 0
    SK_FILL ve_ear_l, SKM_ALL, VE_SKIN_2, 7
    SK_BMP ve_ear_l, SKF_LEFT, 0, 0, ve_ear
    SK_BMP ve_ear_l, SKF_RIGHT, 0, 0, ve_ear
    SK_FILL ve_brow_l, SKM_ALL, VE_HAIR_1, 15
    SK_BMP ve_brow_l, SKF_FRONT, 0, 0, ve_brow_front
    SK_RECT ve_brow_l, SKF_BOTTOM, 0, 0, 5, 1, VE_HAIR_4, 0
    SK_FILL ve_stache, SKM_ALL, VE_HAIR_2, 15
    SK_BMP ve_stache, SKF_FRONT, 0, 0, ve_stache_front
    SK_BMP ve_stache, SKF_BACK, 0, 0, ve_stache_back
    ; --- ve_beard_a .. ve_beard_e: silver strands; the lower corners of every piece are cut so the steps read as a taper
    SK_FILL ve_beard_a, SKM_ALL, VE_HAIR_2, 15
    SK_BMP ve_beard_a, SKF_FRONT, 0, 0, ve_beard_a_front
    SK_BMP ve_beard_a, SKF_BACK, 0, 0, ve_beard_a_back
    SK_BMP ve_beard_a, SKF_LEFT, 0, 0, ve_beard_a_left
    SK_BMP ve_beard_a, SKF_RIGHT, 0, 0, ve_beard_a_right
    SK_BMP ve_beard_a, SKF_TOP, 0, 0, ve_beard_a_top
    SK_RECT ve_beard_a, SKF_BOTTOM, 0, 0, 14, 7, VE_HAIR_3, 0
    SK_GRAD ve_beard_a, SKM_SIDES, 264, 258
    SK_FILL ve_beard_b, SKM_ALL, VE_HAIR_2, 15
    SK_BMP ve_beard_b, SKF_FRONT, 0, 0, ve_beard_b_front
    SK_BMP ve_beard_b, SKF_BACK, 0, 0, ve_beard_b_back
    SK_BMP ve_beard_b, SKF_LEFT, 0, 0, ve_beard_b_left
    SK_BMP ve_beard_b, SKF_RIGHT, 0, 0, ve_beard_b_right
    SK_BMP ve_beard_b, SKF_TOP, 0, 0, ve_beard_b_top
    SK_RECT ve_beard_b, SKF_BOTTOM, 0, 0, 12, 6, VE_HAIR_3, 0
    SK_GRAD ve_beard_b, SKM_SIDES, 258, 252
    SK_FILL ve_beard_c, SKM_ALL, VE_HAIR_2, 15
    SK_BMP ve_beard_c, SKF_FRONT, 0, 0, ve_beard_c_front
    SK_BMP ve_beard_c, SKF_BACK, 0, 0, ve_beard_c_back
    SK_BMP ve_beard_c, SKF_LEFT, 0, 0, ve_beard_c_left
    SK_BMP ve_beard_c, SKF_RIGHT, 0, 0, ve_beard_c_right
    SK_BMP ve_beard_c, SKF_TOP, 0, 0, ve_beard_c_top
    SK_RECT ve_beard_c, SKF_BOTTOM, 0, 0, 10, 5, VE_HAIR_3, 0
    SK_GRAD ve_beard_c, SKM_SIDES, 252, 246
    SK_FILL ve_beard_d, SKM_ALL, VE_HAIR_2, 15
    SK_BMP ve_beard_d, SKF_FRONT, 0, 0, ve_beard_d_front
    SK_BMP ve_beard_d, SKF_BACK, 0, 0, ve_beard_d_back
    SK_BMP ve_beard_d, SKF_LEFT, 0, 0, ve_beard_d_left
    SK_BMP ve_beard_d, SKF_RIGHT, 0, 0, ve_beard_d_right
    SK_BMP ve_beard_d, SKF_TOP, 0, 0, ve_beard_d_top
    SK_RECT ve_beard_d, SKF_BOTTOM, 0, 0, 8, 5, VE_HAIR_3, 0
    SK_GRAD ve_beard_d, SKM_SIDES, 246, 240
    SK_FILL ve_beard_e, SKM_ALL, VE_HAIR_2, 15
    SK_BMP ve_beard_e, SKF_FRONT, 0, 0, ve_beard_e_front
    SK_BMP ve_beard_e, SKF_BACK, 0, 0, ve_beard_e_back
    SK_BMP ve_beard_e, SKF_LEFT, 0, 0, ve_beard_e_left
    SK_BMP ve_beard_e, SKF_RIGHT, 0, 0, ve_beard_e_right
    SK_BMP ve_beard_e, SKF_TOP, 0, 0, ve_beard_e_top
    SK_RECT ve_beard_e, SKF_BOTTOM, 0, 0, 6, 5, VE_HAIR_3, 0
    SK_GRAD ve_beard_e, SKM_SIDES, 240, 232
    ; --- ve_leg_l / ve_leg_r (mirrored): purple robe split at the front, gold edge, gold hem
    SK_FILL ve_leg_l, SKM_ALL, VE_ROBE_2, 15
    SK_BMP ve_leg_l, SKF_FRONT, 0, 0, ve_leg_l_front
    SK_BMP ve_leg_l, SKF_BACK, 0, 0, ve_leg_l_back
    SK_BMP ve_leg_l, SKF_LEFT, 0, 0, ve_leg_l_side
    SK_BMP ve_leg_l, SKF_RIGHT, 0, 0, ve_leg_l_side
    SK_RECT ve_leg_l, SKF_BOTTOM, 0, 0, 6, 6, AC_LEATHER_4, 0
    SK_GRAD ve_leg_l, SKM_SIDES, 272, 224
    SK_FILL ve_leg_r, SKM_ALL, VE_ROBE_2, 15
    SK_BMP ve_leg_r, SKF_FRONT, 0, 0, ve_leg_r_front
    SK_BMP ve_leg_r, SKF_BACK, 0, 0, ve_leg_r_back
    SK_BMP ve_leg_r, SKF_LEFT, 0, 0, ve_leg_r_side
    SK_BMP ve_leg_r, SKF_RIGHT, 0, 0, ve_leg_r_side
    SK_RECT ve_leg_r, SKF_BOTTOM, 0, 0, 6, 6, AC_LEATHER_4, 0
    SK_GRAD ve_leg_r, SKM_SIDES, 272, 224
    ; --- ve_foot_l (shared with ve_foot_r): a soft slipper with a toe seam
    SK_FILL ve_foot_l, SKM_ALL, AC_LEATHER_2, 15
    SK_RECT ve_foot_l, SKF_FRONT, 0, 0, 7, 1, AC_LEATHER_1, 0
    SK_RECT ve_foot_l, SKF_FRONT, 0, 1, 7, 1, AC_LEATHER_4, 0
    SK_RECT ve_foot_l, SKF_BACK, 0, 0, 7, 1, AC_LEATHER_3, 0
    SK_RECT ve_foot_l, SKF_BACK, 0, 1, 7, 1, AC_LEATHER_4, 0
    SK_RECT ve_foot_l, SKF_LEFT, 0, 0, 10, 1, AC_LEATHER_1, 0
    SK_RECT ve_foot_l, SKF_LEFT, 0, 1, 10, 1, AC_LEATHER_4, 0
    SK_RECT ve_foot_l, SKF_RIGHT, 0, 0, 10, 1, AC_LEATHER_2, 0
    SK_RECT ve_foot_l, SKF_RIGHT, 0, 1, 10, 1, AC_LEATHER_4, 0
    SK_BMP ve_foot_l, SKF_TOP, 0, 0, ve_foot_top
    SK_RECT ve_foot_l, SKF_BOTTOM, 0, 0, 7, 10, AC_LEATHER_4, 0
SKMODEL_END

; ===================================================================================================
; m_villager_merchant
; ===================================================================================================
RAMP VM_SKIN, 225, 180, 140             ; head and hands (the Villagers skin)
RAMP VM_HAIR, 96, 62, 36                ; brown hair and moustache
RAMP VM_ROBE, 140, 88, 52               ; the merchant robe: russet brown
RAMP VM_APRON, 230, 220, 192            ; linen apron, shirt cuffs
RAMP VM_CAP, 118, 104, 86               ; tweed flat cap
RAMP VM_SACK, 176, 146, 92              ; burlap coin pouch

section .rodata
; The characters of every vm_ bitmap. Groups: base, highlight, shade, deep.
;   s S k K skin (b blush)   h H j J brown hair   r R o O russet robe   a A v V linen apron
;   t T p P tweed cap   z Z q Q burlap sack   y Y u U brass (AC gold)   l L e E leather (AC)   c cream shirt
;   w sclera   W glint   i I iris   x pupil   m M mouth   _ transparent
align 8
vm_pal:
    PALC 's', VM_SKIN_2
    PALC 'S', VM_SKIN_1
    PALC 'k', VM_SKIN_3
    PALC 'K', VM_SKIN_4
    PALC 'b', RGBO(238, 150, 128)
    PALC 'h', VM_HAIR_2
    PALC 'H', VM_HAIR_1
    PALC 'j', VM_HAIR_3
    PALC 'J', VM_HAIR_4
    PALC 'r', VM_ROBE_2
    PALC 'R', VM_ROBE_1
    PALC 'o', VM_ROBE_3
    PALC 'O', VM_ROBE_4
    PALC 'a', VM_APRON_2
    PALC 'A', VM_APRON_1
    PALC 'v', VM_APRON_3
    PALC 'V', VM_APRON_4
    PALC 't', VM_CAP_2
    PALC 'T', VM_CAP_1
    PALC 'p', VM_CAP_3
    PALC 'P', VM_CAP_4
    PALC 'z', VM_SACK_2
    PALC 'Z', VM_SACK_1
    PALC 'q', VM_SACK_3
    PALC 'Q', VM_SACK_4
    PALC 'y', AC_GOLD_2
    PALC 'Y', AC_GOLD_1
    PALC 'u', AC_GOLD_3
    PALC 'U', AC_GOLD_4
    PALC 'l', AC_LEATHER_2
    PALC 'L', AC_LEATHER_1
    PALC 'e', AC_LEATHER_3
    PALC 'E', AC_LEATHER_4
    PALC 'c', RGBO(232, 220, 190)
    PALC 'w', RGBO(246, 246, 240)
    PALC 'W', RGBO(255, 255, 255)
    PALC 'i', RGBO(120, 80, 40)
    PALC 'I', RGBO(176, 130, 70)
    PALC 'x', RGBO(34, 24, 18)
    PALC 'm', RGBO(176, 108, 92)
    PALC 'M', RGBO(112, 56, 48)
    PALT '_'
    dq 0

    ; vm_torso_front (16x22): vm_torso FRONT
    SKROWS vm_torso_front_rows, 16, 22
    SKROW "R...cccccccc...."
    SKROW "R...occcccco...."
    SKROW "R.....cccc......"
    SKROW "Ro...occcco...o."
    SKROW "Ro.....cc.....o."
    SKROW "Ro............o."
    SKROW "Ro.o..........o."
    SKROW "Ro.o..........o."
    SKROW "Ro..........o.o."
    SKROW "Ro..........o.o."
    SKROW "Ro.o..........o."
    SKROW "Ro.o..........o."
    SKROW "Ro..........o.o."
    SKROW "Ro..........o.o."
    SKROW "Ro.o..........o."
    SKROW "Ro.o..........o."
    SKROW "Ro..........o.o."
    SKROW "Ro..........o.o."
    SKROW "Ro.o..........o."
    SKROW "oooooooooooooooo"
    SKROW "rrrrrrrrrrrrrrrr"
    SKROW "oooooooooooooooo"
    SKROWS_END
    align 8
    SKBMP vm_torso_front, vm_torso_front_rows, 16, 22, vm_pal
    ; vm_torso_back (16x22): vm_torso BACK
    SKROWS vm_torso_back_rows, 16, 22
    SKROW "R..............."
    SKROW "R..............."
    SKROW "R..............."
    SKROW "R..............."
    SKROW "oooooooooooooooo"
    SKROW "R......oR......."
    SKROW "R......oR......."
    SKROW "R......oR......."
    SKROW "R......oR......."
    SKROW "R......oR......."
    SKROW "R......oR......."
    SKROW "R......oR.oooo.."
    SKROW "R......oR.oRRo.."
    SKROW "R......oR.oRRo.."
    SKROW "R......oR.oRRo.."
    SKROW "R......oR.oooo.."
    SKROW "R......oR......."
    SKROW "R..oo......oo..."
    SKROW "R..............."
    SKROW "oooooooooooooooo"
    SKROW "rrrrrrrrrrrrrrrr"
    SKROW "oooooooooooooooo"
    SKROWS_END
    align 8
    SKBMP vm_torso_back, vm_torso_back_rows, 16, 22, vm_pal
    ; vm_torso_side (8x22): vm_torso RIGHT, vm_torso LEFT
    SKROWS vm_torso_side_rows, 8, 22
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "...o...."
    SKROW "........"
    SKROW "........"
    SKROW "...o...."
    SKROW "........"
    SKROW "........"
    SKROW "...o...."
    SKROW "........"
    SKROW "........"
    SKROW "...o...."
    SKROW "........"
    SKROW "........"
    SKROW "...o...."
    SKROW "........"
    SKROW "........"
    SKROW "oooooooo"
    SKROW "........"
    SKROW "oooooooo"
    SKROWS_END
    align 8
    SKBMP vm_torso_side, vm_torso_side_rows, 8, 22, vm_pal
    ; vm_apron_front (10x22): vm_apron FRONT
    SKROWS vm_apron_front_rows, 10, 22
    SKROW "__AAAAAA__"
    SKROW "__v....v__"
    SKROW "__v....v__"
    SKROW "__v.vv.v__"
    SKROW "__v....v__"
    SKROW "__vvvvvv__"
    SKROW "__vvvvvv__"
    SKROW "__v....v__"
    SKROW "__v....v__"
    SKROW "__v.vv.v__"
    SKROW "Av......vv"
    SKROW "Av......vv"
    SKROW "Aa......av"
    SKROW "Av......vv"
    SKROW "EEEEEEEEEE"
    SKROW "eleeeeeeEe"
    SKROW "AaVVV...av"
    SKROW "AvVvv...vv"
    SKROW "Aa......av"
    SKROW "Av......vv"
    SKROW "Avvvvvvvvv"
    SKROW "VVVVVVVVVV"
    SKROWS_END
    align 8
    SKBMP vm_apron_front, vm_apron_front_rows, 10, 22, vm_pal
    ; vm_apron_back (10x22): vm_apron BACK
    SKROWS vm_apron_back_rows, 10, 22
    SKROW "__......__"
    SKROW "__......__"
    SKROW "__......__"
    SKROW "__......__"
    SKROW "__......__"
    SKROW "__......__"
    SKROW "__......__"
    SKROW "__......__"
    SKROW "__......__"
    SKROW "__......__"
    SKROW ".........."
    SKROW ".........."
    SKROW ".........."
    SKROW ".........."
    SKROW ".........."
    SKROW ".........."
    SKROW ".........."
    SKROW ".........."
    SKROW ".........."
    SKROW ".........."
    SKROW ".........."
    SKROW "VVVVVVVVVV"
    SKROWS_END
    align 8
    SKBMP vm_apron_back, vm_apron_back_rows, 10, 22, vm_pal
    ; vm_buckle_front (2x2): vm_buckle FRONT
    SKROWS vm_buckle_front_rows, 2, 2
    SKROW "YY"
    SKROW "uU"
    SKROWS_END
    align 8
    SKBMP vm_buckle_front, vm_buckle_front_rows, 2, 2, vm_pal
    ; vm_pouch_front (3x8): vm_pouch FRONT
    SKROWS vm_pouch_front_rows, 3, 8
    SKROW "Z.q"
    SKROW "ZYy"
    SKROW "Zuq"
    SKROW "Z.q"
    SKROW "q.q"
    SKROW "Zqq"
    SKROW "Z.q"
    SKROW "QQQ"
    SKROWS_END
    align 8
    SKBMP vm_pouch_front, vm_pouch_front_rows, 3, 8, vm_pal
    ; vm_pouch_side (5x8): vm_pouch LEFT, vm_pouch RIGHT
    SKROWS vm_pouch_side_rows, 5, 8
    SKROW "Z...q"
    SKROW "Z...q"
    SKROW "Z...q"
    SKROW "Z...q"
    SKROW "Z.q.q"
    SKROW "Z..qq"
    SKROW "Z...q"
    SKROW "QQQQQ"
    SKROWS_END
    align 8
    SKBMP vm_pouch_side, vm_pouch_side_rows, 5, 8, vm_pal
    ; vm_pouch_back (3x8): vm_pouch BACK
    SKROWS vm_pouch_back_rows, 3, 8
    SKROW "Z.q"
    SKROW "Z.q"
    SKROW "Z.q"
    SKROW "Z.q"
    SKROW "Z.q"
    SKROW "Z.q"
    SKROW "Z.q"
    SKROW "QQQ"
    SKROWS_END
    align 8
    SKBMP vm_pouch_back, vm_pouch_back_rows, 3, 8, vm_pal
    ; vm_tie_front (3x2): vm_tie FRONT
    SKROWS vm_tie_front_rows, 3, 2
    SKROW "ele"
    SKROW "EeE"
    SKROWS_END
    align 8
    SKBMP vm_tie_front, vm_tie_front_rows, 3, 2, vm_pal
    ; vm_tie_back (3x2): vm_tie BACK
    SKROWS vm_tie_back_rows, 3, 2
    SKROW "ele"
    SKROW "EeE"
    SKROWS_END
    align 8
    SKBMP vm_tie_back, vm_tie_back_rows, 3, 2, vm_pal
    ; vm_tie_left (5x2): vm_tie LEFT
    SKROWS vm_tie_left_rows, 5, 2
    SKROW "elele"
    SKROW "EeEeE"
    SKROWS_END
    align 8
    SKBMP vm_tie_left, vm_tie_left_rows, 5, 2, vm_pal
    ; vm_tie_right (5x2): vm_tie RIGHT
    SKROWS vm_tie_right_rows, 5, 2
    SKROW "elele"
    SKROW "EeEeE"
    SKROWS_END
    align 8
    SKBMP vm_tie_right, vm_tie_right_rows, 5, 2, vm_pal
    ; vm_sleeve_front (4x15): vm_sleeve_l FRONT
    SKROWS vm_sleeve_front_rows, 4, 15
    SKROW "RRRR"
    SKROW "R..o"
    SKROW "R.oo"
    SKROW "R..o"
    SKROW "R..o"
    SKROW "R.oo"
    SKROW "R..o"
    SKROW "R..o"
    SKROW "R.oo"
    SKROW "R..o"
    SKROW "R..o"
    SKROW "oooo"
    SKROW "AAAA"
    SKROW "aaaa"
    SKROW "vvvv"
    SKROWS_END
    align 8
    SKBMP vm_sleeve_front, vm_sleeve_front_rows, 4, 15, vm_pal
    ; vm_sleeve_back (4x15): vm_sleeve_l BACK
    SKROWS vm_sleeve_back_rows, 4, 15
    SKROW "RRRR"
    SKROW "R..o"
    SKROW "R.oo"
    SKROW "R..o"
    SKROW "R..o"
    SKROW "R.oo"
    SKROW "R..o"
    SKROW "R..o"
    SKROW "R.oo"
    SKROW "R..o"
    SKROW "R..o"
    SKROW "oooo"
    SKROW "AAAA"
    SKROW "aaaa"
    SKROW "vvvv"
    SKROWS_END
    align 8
    SKBMP vm_sleeve_back, vm_sleeve_back_rows, 4, 15, vm_pal
    ; vm_sleeve_left (6x15): vm_sleeve_l LEFT
    SKROWS vm_sleeve_left_rows, 6, 15
    SKROW "RRRRRR"
    SKROW "R....o"
    SKROW "R..o.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R..o.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R..o.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "oooooo"
    SKROW "AAAAAA"
    SKROW "aaaaaa"
    SKROW "vvvvvv"
    SKROWS_END
    align 8
    SKBMP vm_sleeve_left, vm_sleeve_left_rows, 6, 15, vm_pal
    ; vm_sleeve_right (6x15): vm_sleeve_l RIGHT
    SKROWS vm_sleeve_right_rows, 6, 15
    SKROW "RRRRRR"
    SKROW "R....o"
    SKROW "R..o.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R..o.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R..o.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "oooooo"
    SKROW "AAAAAA"
    SKROW "aaaaaa"
    SKROW "vvvvvv"
    SKROWS_END
    align 8
    SKBMP vm_sleeve_right, vm_sleeve_right_rows, 6, 15, vm_pal
    ; vm_fore_front (22x6): vm_fore FRONT
    SKROWS vm_fore_front_rows, 22, 6
    SKROW "RRRRRAvRRRRRRRRAvRRRRR"
    SKROW "..o..Avo....o..Avo...."
    SKROW "..o..Avo....o..Avo...."
    SKROW "..o..Avo....o..Avo...."
    SKROW "..o..Avo....o..Avo...."
    SKROW "oooooooooooooooooooooo"
    SKROWS_END
    align 8
    SKBMP vm_fore_front, vm_fore_front_rows, 22, 6, vm_pal
    ; vm_hand_front (4x4): vm_hand_l FRONT
    SKROWS vm_hand_front_rows, 4, 4
    SKROW "SSss"
    SKROW "sKsK"
    SKROW "sKsK"
    SKROW "kkkk"
    SKROWS_END
    align 8
    SKBMP vm_hand_front, vm_hand_front_rows, 4, 4, vm_pal
    ; vm_face (16x16): vm_head FRONT
    SKROWS vm_face_rows, 16, 16
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
    SKROW ".bb..........bb."
    SKROW ".bb..........bb."
    SKROW "................"
    SKROW ".....M....M....."
    SKROW "......MmmM......"
    SKROW ".......kk......."
    SKROWS_END
    align 8
    SKBMP vm_face, vm_face_rows, 16, 16, vm_pal
    ; vm_hair_front (16x16): vm_hair FRONT
    SKROWS vm_hair_front_rows, 16, 16
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "...JjJjJjJjJj..."
    SKROW "H.j__________.j."
    SKROW "H.j__________.j."
    SKROW "H.j__________.j."
    SKROW "H.j__________Jj."
    SKROW "H.____________j."
    SKROW "HJ____________j."
    SKROW "H______________."
    SKROW "j______________J"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP vm_hair_front, vm_hair_front_rows, 16, 16, vm_pal
    ; vm_hair_back (16x16): vm_hair BACK
    SKROWS vm_hair_back_rows, 16, 16
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "................"
    SKROW "H.j.H.j.H.j.H.j."
    SKROW "H.j.H.j.H.j.H.j."
    SKROW "H.j.H.j.H.j.H.j."
    SKROW "H.j.H.j.H.j.H.j."
    SKROW "H.j.H.j.H.j.H.j."
    SKROW "j.j.H.j.H.j.H.jJ"
    SKROW "_Jj.j.j.HJjJHJj_"
    SKROW "___J_J_Jj_j_j___"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP vm_hair_back, vm_hair_back_rows, 16, 16, vm_pal
    ; vm_hair_right (16x16): vm_hair RIGHT
    SKROWS vm_hair_right_rows, 16, 16
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "..............__"
    SKROW "H.j.H.j.H.j.H.__"
    SKROW "H.j.H.j.H.j.H.__"
    SKROW "H.j.H.j___j.H.__"
    SKROW "H.j.H.j___j.jJ__"
    SKROW "H.j.H.j___jJ____"
    SKROW "H.j.H.j_________"
    SKROW "j.j.jJj_________"
    SKROW "_J_J____________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP vm_hair_right, vm_hair_right_rows, 16, 16, vm_pal
    ; vm_hair_left (16x16): vm_hair LEFT
    SKROWS vm_hair_left_rows, 16, 16
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "__.............."
    SKROW "__.H.j.H.j.H.j.H"
    SKROW "__.H.j.H.j.H.j.H"
    SKROW "__.H.j___j.H.j.H"
    SKROW "__Jj.j___j.H.j.H"
    SKROW "____Jj___j.H.j.H"
    SKROW "_________j.H.j.H"
    SKROW "_________jJj.j.j"
    SKROW "____________J_J_"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP vm_hair_left, vm_hair_left_rows, 16, 16, vm_pal
    ; vm_hair_top (16x16): vm_hair TOP
    SKROWS vm_hair_top_rows, 16, 16
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROWS_END
    align 8
    SKBMP vm_hair_top, vm_hair_top_rows, 16, 16, vm_pal
    ; vm_hair_bottom (16x16): vm_hair BOTTOM
    SKROWS vm_hair_bottom_rows, 16, 16
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
    SKROW "__............__"
    SKROW "__............__"
    SKROW "__............__"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP vm_hair_bottom, vm_hair_bottom_rows, 16, 16, vm_pal
    ; vm_nose_front (2x3): vm_nose FRONT
    SKROWS vm_nose_front_rows, 2, 3
    SKROW "SS"
    SKROW "ss"
    SKROW "kk"
    SKROWS_END
    align 8
    SKBMP vm_nose_front, vm_nose_front_rows, 2, 3, vm_pal
    ; vm_ear (2x3): vm_ear_l LEFT, vm_ear_l RIGHT
    SKROWS vm_ear_rows, 2, 3
    SKROW "ss"
    SKROW "kk"
    SKROW "ss"
    SKROWS_END
    align 8
    SKBMP vm_ear, vm_ear_rows, 2, 3, vm_pal
    ; vm_stache_front (12x2): vm_stache FRONT
    SKROWS vm_stache_front_rows, 12, 2
    SKROW "hH__HhhH__Hh"
    SKROW "_hhhjjjjhhh_"
    SKROWS_END
    align 8
    SKBMP vm_stache_front, vm_stache_front_rows, 12, 2, vm_pal
    ; vm_stache_back (12x2): vm_stache BACK
    SKROWS vm_stache_back_rows, 12, 2
    SKROW "jj__jjjj__jj"
    SKROW "_jjjjjjjjjj_"
    SKROWS_END
    align 8
    SKBMP vm_stache_back, vm_stache_back_rows, 12, 2, vm_pal
    ; vm_cap_front (16x3): vm_cap FRONT
    SKROWS vm_cap_front_rows, 16, 3
    SKROW "T..T..T..T..T..T"
    SKROW "..T..T..T..T..T."
    SKROW "pppppppppppppppp"
    SKROWS_END
    align 8
    SKBMP vm_cap_front, vm_cap_front_rows, 16, 3, vm_pal
    ; vm_cap_back (16x3): vm_cap BACK
    SKROWS vm_cap_back_rows, 16, 3
    SKROW "T..T..T..T..T..T"
    SKROW "..T..T..T..T..T."
    SKROW "pppppppppppppppp"
    SKROWS_END
    align 8
    SKBMP vm_cap_back, vm_cap_back_rows, 16, 3, vm_pal
    ; vm_cap_left (16x3): vm_cap LEFT
    SKROWS vm_cap_left_rows, 16, 3
    SKROW "T..T..T..T..T..T"
    SKROW "..T..T..T..T..T."
    SKROW "pppppppppppppppp"
    SKROWS_END
    align 8
    SKBMP vm_cap_left, vm_cap_left_rows, 16, 3, vm_pal
    ; vm_cap_right (16x3): vm_cap RIGHT
    SKROWS vm_cap_right_rows, 16, 3
    SKROW "T..T..T..T..T..T"
    SKROW "..T..T..T..T..T."
    SKROW "pppppppppppppppp"
    SKROWS_END
    align 8
    SKBMP vm_cap_right, vm_cap_right_rows, 16, 3, vm_pal
    ; vm_cap_top (16x16): vm_cap TOP
    SKROWS vm_cap_top_rows, 16, 16
    SKROW "pppppppppppppppp"
    SKROW "p.T..T..T..T..Tp"
    SKROW "pT..T..T..T..T.p"
    SKROW "p..T..T..T..T..p"
    SKROW "p.T..T..T..T..Tp"
    SKROW "pT..T..T..T..T.p"
    SKROW "p..T..T..T..T..p"
    SKROW "p.T..T..T..T..Tp"
    SKROW "pT..T..T..T..T.p"
    SKROW "p..T..T..T..T..p"
    SKROW "p.T..T..T..T..Tp"
    SKROW "pT..T..T..T..T.p"
    SKROW "p..T..T..T..T..p"
    SKROW "p.T..T..T..T..Tp"
    SKROW "pT..T..T..T..T.p"
    SKROW "pppppppppppppppp"
    SKROWS_END
    align 8
    SKBMP vm_cap_top, vm_cap_top_rows, 16, 16, vm_pal
    ; vm_puff_front (14x2): vm_puff FRONT
    SKROWS vm_puff_front_rows, 14, 2
    SKROW "..T..T..T..T.."
    SKROW "pppppppppppppp"
    SKROWS_END
    align 8
    SKBMP vm_puff_front, vm_puff_front_rows, 14, 2, vm_pal
    ; vm_puff_back (14x2): vm_puff BACK
    SKROWS vm_puff_back_rows, 14, 2
    SKROW "..T..T..T..T.."
    SKROW "pppppppppppppp"
    SKROWS_END
    align 8
    SKBMP vm_puff_back, vm_puff_back_rows, 14, 2, vm_pal
    ; vm_puff_left (14x2): vm_puff LEFT
    SKROWS vm_puff_left_rows, 14, 2
    SKROW "..T..T..T..T.."
    SKROW "pppppppppppppp"
    SKROWS_END
    align 8
    SKBMP vm_puff_left, vm_puff_left_rows, 14, 2, vm_pal
    ; vm_puff_right (14x2): vm_puff RIGHT
    SKROWS vm_puff_right_rows, 14, 2
    SKROW "..T..T..T..T.."
    SKROW "pppppppppppppp"
    SKROWS_END
    align 8
    SKBMP vm_puff_right, vm_puff_right_rows, 14, 2, vm_pal
    ; vm_puff_top (14x14): vm_puff TOP
    SKROWS vm_puff_top_rows, 14, 14
    SKROW "pppppppppppppp"
    SKROW "pT..T..p..T..p"
    SKROW "p..T..Tp.T..Tp"
    SKROW "p.T..T.pT..T.p"
    SKROW "pT..T..p..T..p"
    SKROW "p..T..Tp.T..Tp"
    SKROW "p.T..T.pT..T.p"
    SKROW "pT..T..p..T..p"
    SKROW "p..T..Tp.T..Tp"
    SKROW "p.T..T.pT..T.p"
    SKROW "pT..T..p..T..p"
    SKROW "p..T..Tp.T..Tp"
    SKROW "p.T..T.pT..T.p"
    SKROW "pppppppppppppp"
    SKROWS_END
    align 8
    SKBMP vm_puff_top, vm_puff_top_rows, 14, 14, vm_pal
    ; vm_leg_l_front (6x24): vm_leg_l FRONT
    SKROWS vm_leg_l_front_rows, 6, 24
    SKROW "Aaaaao"
    SKROW "Aaaaao"
    SKROW "Aavvao"
    SKROW "Aaaaao"
    SKROW "Aaaaao"
    SKROW "Aaaaao"
    SKROW "Aavvao"
    SKROW "Aaaaao"
    SKROW "Aaaaao"
    SKROW "Aaaaao"
    SKROW "Aavvao"
    SKROW "Aaaaao"
    SKROW "Aaaaao"
    SKROW "vvvvvo"
    SKROW ".....o"
    SKROW ".....o"
    SKROW ".....o"
    SKROW ".....o"
    SKROW ".....o"
    SKROW "EEEEEE"
    SKROW "eEelEe"
    SKROW "eEcLEe"
    SKROW "eElcEe"
    SKROW "EEEEEE"
    SKROWS_END
    align 8
    SKBMP vm_leg_l_front, vm_leg_l_front_rows, 6, 24, vm_pal
    ; vm_leg_l_back (6x24): vm_leg_l BACK
    SKROWS vm_leg_l_back_rows, 6, 24
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "oooooo"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "EEEEEE"
    SKROW "eeeEee"
    SKROW "eeeEee"
    SKROW "eeeEee"
    SKROW "EEEEEE"
    SKROWS_END
    align 8
    SKBMP vm_leg_l_back, vm_leg_l_back_rows, 6, 24, vm_pal
    ; vm_leg_l_side (6x24): vm_leg_l LEFT, vm_leg_l RIGHT
    SKROWS vm_leg_l_side_rows, 6, 24
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R.oo.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R.oo.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R.oo.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R.oo.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "EEEEEE"
    SKROW "leeeee"
    SKROW "leeeee"
    SKROW "leeeee"
    SKROW "EEEEEE"
    SKROWS_END
    align 8
    SKBMP vm_leg_l_side, vm_leg_l_side_rows, 6, 24, vm_pal
    ; vm_leg_r_front (6x24): vm_leg_r FRONT
    SKROWS vm_leg_r_front_rows, 6, 24
    SKROW "oaaaaA"
    SKROW "oaaaaA"
    SKROW "oavvaA"
    SKROW "oaaaaA"
    SKROW "oaaaaA"
    SKROW "oaaaaA"
    SKROW "oavvaA"
    SKROW "oaaaaA"
    SKROW "oaaaaA"
    SKROW "oaaaaA"
    SKROW "oavvaA"
    SKROW "oaaaaA"
    SKROW "oaaaaA"
    SKROW "ovvvvv"
    SKROW "o....."
    SKROW "o....."
    SKROW "o....."
    SKROW "o....."
    SKROW "o....."
    SKROW "EEEEEE"
    SKROW "eEelEe"
    SKROW "eEcLEe"
    SKROW "eElcEe"
    SKROW "EEEEEE"
    SKROWS_END
    align 8
    SKBMP vm_leg_r_front, vm_leg_r_front_rows, 6, 24, vm_pal
    ; vm_leg_r_back (6x24): vm_leg_r BACK
    SKROWS vm_leg_r_back_rows, 6, 24
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "oooooo"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "R..o.o"
    SKROW "EEEEEE"
    SKROW "eeeEee"
    SKROW "eeeEee"
    SKROW "eeeEee"
    SKROW "EEEEEE"
    SKROWS_END
    align 8
    SKBMP vm_leg_r_back, vm_leg_r_back_rows, 6, 24, vm_pal
    ; vm_leg_r_side (6x24): vm_leg_r LEFT, vm_leg_r RIGHT
    SKROWS vm_leg_r_side_rows, 6, 24
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R.oo.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R.oo.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R.oo.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R.oo.o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "R....o"
    SKROW "EEEEEE"
    SKROW "leeeee"
    SKROW "leeeee"
    SKROW "leeeee"
    SKROW "EEEEEE"
    SKROWS_END
    align 8
    SKBMP vm_leg_r_side, vm_leg_r_side_rows, 6, 24, vm_pal
    ; vm_foot_top (7x10): vm_foot_l TOP
    SKROWS vm_foot_top_rows, 7, 10
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
    SKBMP vm_foot_top, vm_foot_top_rows, 7, 10, vm_pal

section .data
SKMODEL_BEGIN m_villager_merchant, 32, 0, 11, 26, 0
    SKBONE BK_LLEG, 24, 0, 1.00
    PART vm_leg_l, -6, 0, -3, 6, 24, 6, 0, 0                ; robe, apron down the front, boot shafts
    PART vm_foot_l, -7, 0, -6, 7, 2, 10, 0, 0               ; boot foot (the other shares its skin)
    SKBONE BK_RLEG, 24, 0, -1.00
    PART vm_leg_r, 0, 0, -3, 6, 24, 6, 0, 0                 ; robe, mirrored
    PART_AS vm_foot_r, vm_foot_l, 0, 0, -6, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART vm_collar, -5, 42, -4, 10, 4, 8, 4, 0              ; cream shirt collar
    PART vm_sleeve_l, -12, 31, -3, 4, 15, 6, 0, 0           ; folded arms: upper sleeve (the right one shares its skin)
    PART vm_hand_l, -10, 32, -10, 4, 4, 2, 0, 0             ; a hand (the other shares its skin)
    PART vm_apron, -5, 22, -5, 10, 22, 1, 0, SKPF_CUTOUT    ; linen apron with a bib (notched top corners)
    PART vm_torso, -8, 24, -4, 16, 22, 8, 0, 0              ; russet robe
    PART vm_buckle, -1, 27, -6, 2, 2, 1, 0, 0               ; brass buckle
    PART vm_pouch, 8, 19, -3, 3, 8, 5, 0, 0                 ; coin pouch at the right hip
    PART vm_belt, -8, 27, -4, 16, 2, 8, 4, 0                ; dark leather belt (the front is under the apron)
    PART vm_tie, 8, 25, -3, 3, 2, 5, 3, 0                   ; its drawstring
    PART_AS vm_sleeve_r, vm_sleeve_l, 8, 31, -3, 0, 0
    PART vm_fore, -11, 31, -8, 22, 6, 5, 0, 0               ; the crossed forearms, rolled linen cuffs
    PART_AS vm_hand_r, vm_hand_l, 6, 32, -10, 0, 0
    SKBONE BK_HEAD, 0, 0, 0.00
    PART vm_ear_l, -9, 52, -1, 1, 3, 2, 0, 0                ; ear (the right one shares its skin)
    PART vm_brim, -7, 59, -13, 14, 2, 4, 0, 0               ; its short peak
    PART vm_button, -1, 65, -3, 2, 1, 2, 0, 0               ; cap button
    PART vm_nose, -1, 50, -10, 2, 3, 2, 0, 0                ; nose
    PART vm_stache, -6, 48, -10, 12, 2, 2, 0, SKPF_CUTOUT   ; handlebar moustache
    PART vm_cap, -8, 60, -8, 16, 3, 16, 8, 0                ; flat tweed cap: the band round the head
    PART vm_hair, -8, 46, -8, 16, 16, 16, 4, SKPF_CUTOUT    ; hair overlay under the cap: sideburns and nape
    PART vm_head, -8, 46, -8, 16, 16, 16, 0, 0              ; the 16 texel head
    PART vm_puff, -7, 63, -8, 14, 2, 14, 4, 0               ; its puffed crown, leaning forward
    PART_AS vm_ear_r, vm_ear_l, 8, 52, -1, 0, 0
SKMODEL_PAINT
    ; --- vm_torso: russet robe, cream shirt V at the neck, rolled shoulder patches, folds
    SK_FILL vm_torso, SKM_ALL, VM_ROBE_2, 15
    SK_BMP vm_torso, SKF_FRONT, 0, 0, vm_torso_front
    SK_BMP vm_torso, SKF_BACK, 0, 0, vm_torso_back
    SK_BMP vm_torso, SKF_RIGHT, 0, 0, vm_torso_side
    SK_BMP vm_torso, SKF_LEFT, 0, 0, vm_torso_side
    SK_RECT vm_torso, SKF_BOTTOM, 0, 0, 16, 8, VM_ROBE_4, 0
    SK_GRAD vm_torso, SKM_SIDES, 272, 224
    ; --- vm_collar: a cream shirt collar with a stitched edge
    SK_FILL vm_collar, SKM_ALL, VM_APRON_1, 15
    SK_RECT vm_collar, SKF_FRONT, 0, 2, 10, 1, VM_APRON_2, 0
    SK_RECT vm_collar, SKF_FRONT, 0, 3, 10, 1, VM_APRON_3, 0
    SK_RECT vm_collar, SKF_BACK, 0, 2, 10, 1, VM_APRON_2, 0
    SK_RECT vm_collar, SKF_BACK, 0, 3, 10, 1, VM_APRON_3, 0
    SK_RECT vm_collar, SKF_LEFT, 0, 2, 8, 1, VM_APRON_2, 0
    SK_RECT vm_collar, SKF_LEFT, 0, 3, 8, 1, VM_APRON_3, 0
    SK_RECT vm_collar, SKF_RIGHT, 0, 2, 8, 1, VM_APRON_2, 0
    SK_RECT vm_collar, SKF_RIGHT, 0, 3, 8, 1, VM_APRON_3, 0
    SK_RECT vm_collar, SKF_BOTTOM, 0, 0, 10, 8, VM_APRON_4, 0
    ; --- vm_apron: linen, stitched border, patch pocket, tie line at the waist, hem; the top corners are cut for the bib
    SK_FILL vm_apron, SKM_ALL, VM_APRON_2, 15
    SK_BMP vm_apron, SKF_FRONT, 0, 0, vm_apron_front
    SK_BMP vm_apron, SKF_BACK, 0, 0, vm_apron_back
    SK_FILL vm_apron, SKM_LEFT | SKM_RIGHT | SKM_TOP | SKM_BOTTOM, VM_APRON_3, 0
    ; --- vm_belt / vm_buckle / vm_pouch / vm_tie
    SK_FILL vm_belt, SKM_ALL, AC_LEATHER_3, 7
    SK_RECT vm_belt, SKF_FRONT, 0, 0, 16, 1, AC_LEATHER_2, 0
    SK_RECT vm_belt, SKF_FRONT, 0, 1, 16, 1, AC_LEATHER_4, 0
    SK_RECT vm_belt, SKF_BACK, 0, 0, 16, 1, AC_LEATHER_2, 0
    SK_RECT vm_belt, SKF_BACK, 0, 1, 16, 1, AC_LEATHER_4, 0
    SK_RECT vm_belt, SKF_LEFT, 0, 0, 8, 1, AC_LEATHER_2, 0
    SK_RECT vm_belt, SKF_LEFT, 0, 1, 8, 1, AC_LEATHER_4, 0
    SK_RECT vm_belt, SKF_RIGHT, 0, 0, 8, 1, AC_LEATHER_2, 0
    SK_RECT vm_belt, SKF_RIGHT, 0, 1, 8, 1, AC_LEATHER_4, 0
    SK_RECT vm_belt, SKF_TOP, 0, 0, 16, 8, AC_LEATHER_2, 7
    SK_RECT vm_belt, SKF_BOTTOM, 0, 0, 16, 8, AC_LEATHER_4, 0
    SK_FILL vm_buckle, SKM_ALL, AC_GOLD_3, 0
    SK_BMP vm_buckle, SKF_FRONT, 0, 0, vm_buckle_front
    SK_FILL vm_pouch, SKM_ALL, VM_SACK_2, 15
    SK_BMP vm_pouch, SKF_FRONT, 0, 0, vm_pouch_front
    SK_BMP vm_pouch, SKF_LEFT, 0, 0, vm_pouch_side
    SK_BMP vm_pouch, SKF_RIGHT, 0, 0, vm_pouch_side
    SK_BMP vm_pouch, SKF_BACK, 0, 0, vm_pouch_back
    SK_RECT vm_pouch, SKF_TOP, 0, 0, 3, 5, VM_SACK_1, 0
    SK_RECT vm_pouch, SKF_BOTTOM, 0, 0, 3, 5, VM_SACK_4, 0
    SK_GRAD vm_pouch, SKM_SIDES, 272, 224
    SK_FILL vm_tie, SKM_ALL, AC_LEATHER_3, 0
    SK_BMP vm_tie, SKF_FRONT, 0, 0, vm_tie_front
    SK_BMP vm_tie, SKF_BACK, 0, 0, vm_tie_back
    SK_BMP vm_tie, SKF_LEFT, 0, 0, vm_tie_left
    SK_BMP vm_tie, SKF_RIGHT, 0, 0, vm_tie_right
    SK_RECT vm_tie, SKF_TOP, 0, 0, 3, 5, AC_LEATHER_2, 0
    SK_RECT vm_tie, SKF_BOTTOM, 0, 0, 3, 5, AC_LEATHER_4, 0
    ; --- vm_sleeve_l (shared): russet sleeve, folds, a rolled linen cuff at the elbow
    SK_FILL vm_sleeve_l, SKM_ALL, VM_ROBE_2, 15
    SK_BMP vm_sleeve_l, SKF_FRONT, 0, 0, vm_sleeve_front
    SK_BMP vm_sleeve_l, SKF_BACK, 0, 0, vm_sleeve_back
    SK_BMP vm_sleeve_l, SKF_LEFT, 0, 0, vm_sleeve_left
    SK_BMP vm_sleeve_l, SKF_RIGHT, 0, 0, vm_sleeve_right
    SK_RECT vm_sleeve_l, SKF_TOP, 0, 0, 4, 6, VM_ROBE_1, 15
    SK_RECT vm_sleeve_l, SKF_BOTTOM, 0, 0, 4, 6, VM_APRON_4, 0
    SK_GRAD vm_sleeve_l, SKM_SIDES, 272, 224
    ; --- vm_fore: the crossed forearms: linen rolled cuffs either side of the beard-less chest
    SK_FILL vm_fore, SKM_ALL, VM_ROBE_2, 15
    SK_BMP vm_fore, SKF_FRONT, 0, 0, vm_fore_front
    SK_RECT vm_fore, SKF_TOP, 0, 0, 22, 5, VM_ROBE_1, 15
    SK_RECT vm_fore, SKF_BOTTOM, 0, 0, 22, 5, VM_ROBE_4, 0
    SK_GRAD vm_fore, SKM_SIDES, 272, 224
    SK_FILL vm_hand_l, SKM_ALL, VM_SKIN_2, 7
    SK_BMP vm_hand_l, SKF_FRONT, 0, 0, vm_hand_front
    SK_RECT vm_hand_l, SKF_TOP, 0, 0, 4, 2, VM_SKIN_1, 0
    SK_RECT vm_hand_l, SKF_BOTTOM, 0, 0, 4, 2, VM_SKIN_4, 0
    SK_GRAD vm_hand_l, SKM_SIDES, 272, 224
    ; --- vm_head: a friendly face: brows, brown eyes, blush, a smile under the moustache
    SK_FILL vm_head, SKM_ALL, VM_SKIN_2, 15
    SK_GRAD vm_head, SKM_SIDES, 272, 224
    SK_RECT vm_head, SKF_TOP, 0, 0, 16, 16, VM_HAIR_2, 15
    SK_RECT vm_head, SKF_BOTTOM, 0, 0, 16, 16, VM_SKIN_4, 0
    SK_RECT vm_head, SKF_BACK, 0, 0, 16, 11, VM_HAIR_2, 15
    SK_RECT vm_head, SKF_RIGHT, 0, 0, 16, 6, VM_HAIR_2, 15
    SK_RECT vm_head, SKF_LEFT, 0, 0, 16, 6, VM_HAIR_2, 15
    SK_BMP vm_head, SKF_FRONT, 0, 0, vm_face
    ; --- vm_hair: a cutout overlay: short sideburns and the nape; the cap covers the rest
    SK_FILL vm_hair, SKM_ALL, VM_HAIR_2, 31
    SK_GRAD vm_hair, SKM_SIDES, 272, 224
    SK_BMP vm_hair, SKF_FRONT, 0, 0, vm_hair_front
    SK_BMP vm_hair, SKF_BACK, 0, 0, vm_hair_back
    SK_BMP vm_hair, SKF_RIGHT, 0, 0, vm_hair_right
    SK_BMP vm_hair, SKF_LEFT, 0, 0, vm_hair_left
    SK_BMP vm_hair, SKF_TOP, 0, 0, vm_hair_top
    SK_BMP vm_hair, SKF_BOTTOM, 0, 0, vm_hair_bottom
    ; --- vm_nose, vm_ear_l (shared with vm_ear_r), vm_stache
    SK_FILL vm_nose, SKM_ALL, VM_SKIN_2, 7
    SK_BMP vm_nose, SKF_FRONT, 0, 0, vm_nose_front
    SK_RECT vm_nose, SKF_TOP, 0, 0, 2, 2, VM_SKIN_1, 0
    SK_RECT vm_nose, SKF_BOTTOM, 0, 0, 2, 2, VM_SKIN_4, 0
    SK_FILL vm_ear_l, SKM_ALL, VM_SKIN_2, 7
    SK_BMP vm_ear_l, SKF_LEFT, 0, 0, vm_ear
    SK_BMP vm_ear_l, SKF_RIGHT, 0, 0, vm_ear
    SK_FILL vm_stache, SKM_ALL, VM_HAIR_2, 15
    SK_BMP vm_stache, SKF_FRONT, 0, 0, vm_stache_front
    SK_BMP vm_stache, SKF_BACK, 0, 0, vm_stache_back
    ; --- vm_cap / vm_puff: tweed weave, a seam, a button; vm_brim: its darker peak
    SK_FILL vm_cap, SKM_ALL, VM_CAP_2, 15
    SK_BMP vm_cap, SKF_FRONT, 0, 0, vm_cap_front
    SK_BMP vm_cap, SKF_BACK, 0, 0, vm_cap_back
    SK_BMP vm_cap, SKF_LEFT, 0, 0, vm_cap_left
    SK_BMP vm_cap, SKF_RIGHT, 0, 0, vm_cap_right
    SK_BMP vm_cap, SKF_TOP, 0, 0, vm_cap_top
    SK_RECT vm_cap, SKF_BOTTOM, 0, 0, 16, 16, VM_CAP_4, 0
    SK_GRAD vm_cap, SKM_SIDES, 272, 224
    SK_FILL vm_puff, SKM_ALL, VM_CAP_2, 15
    SK_BMP vm_puff, SKF_FRONT, 0, 0, vm_puff_front
    SK_BMP vm_puff, SKF_BACK, 0, 0, vm_puff_back
    SK_BMP vm_puff, SKF_LEFT, 0, 0, vm_puff_left
    SK_BMP vm_puff, SKF_RIGHT, 0, 0, vm_puff_right
    SK_BMP vm_puff, SKF_TOP, 0, 0, vm_puff_top
    SK_RECT vm_puff, SKF_BOTTOM, 0, 0, 14, 14, VM_CAP_4, 0
    SK_GRAD vm_puff, SKM_SIDES, 272, 224
    SK_FILL vm_brim, SKM_ALL, VM_CAP_3, 7
    SK_RECT vm_brim, SKF_TOP, 0, 0, 14, 4, VM_CAP_2, 7
    SK_RECT vm_brim, SKF_FRONT, 0, 0, 14, 1, VM_CAP_4, 0
    SK_RECT vm_brim, SKF_FRONT, 0, 1, 14, 1, VM_CAP_3, 0
    SK_RECT vm_brim, SKF_BOTTOM, 0, 0, 14, 4, VM_CAP_4, 0
    SK_FILL vm_button, SKM_ALL, VM_CAP_3, 0
    SK_RECT vm_button, SKF_TOP, 0, 0, 2, 2, VM_CAP_1, 0
    ; --- vm_leg_l / vm_leg_r (mirrored): russet robe, the linen apron down the front, a boot shaft
    SK_FILL vm_leg_l, SKM_ALL, VM_ROBE_2, 15
    SK_RECT vm_leg_l, SKF_FRONT, 0, 19, 6, 5, AC_LEATHER_3, 15
    SK_RECT vm_leg_l, SKF_BACK, 0, 19, 6, 5, AC_LEATHER_3, 15
    SK_RECT vm_leg_l, SKF_LEFT, 0, 19, 6, 5, AC_LEATHER_3, 15
    SK_RECT vm_leg_l, SKF_RIGHT, 0, 19, 6, 5, AC_LEATHER_3, 15
    SK_BMP vm_leg_l, SKF_FRONT, 0, 0, vm_leg_l_front
    SK_BMP vm_leg_l, SKF_BACK, 0, 0, vm_leg_l_back
    SK_BMP vm_leg_l, SKF_LEFT, 0, 0, vm_leg_l_side
    SK_BMP vm_leg_l, SKF_RIGHT, 0, 0, vm_leg_l_side
    SK_RECT vm_leg_l, SKF_BOTTOM, 0, 0, 6, 6, AC_LEATHER_4, 0
    SK_GRAD vm_leg_l, SKM_SIDES, 272, 224
    SK_FILL vm_leg_r, SKM_ALL, VM_ROBE_2, 15
    SK_RECT vm_leg_r, SKF_FRONT, 0, 19, 6, 5, AC_LEATHER_3, 15
    SK_RECT vm_leg_r, SKF_BACK, 0, 19, 6, 5, AC_LEATHER_3, 15
    SK_RECT vm_leg_r, SKF_LEFT, 0, 19, 6, 5, AC_LEATHER_3, 15
    SK_RECT vm_leg_r, SKF_RIGHT, 0, 19, 6, 5, AC_LEATHER_3, 15
    SK_BMP vm_leg_r, SKF_FRONT, 0, 0, vm_leg_r_front
    SK_BMP vm_leg_r, SKF_BACK, 0, 0, vm_leg_r_back
    SK_BMP vm_leg_r, SKF_LEFT, 0, 0, vm_leg_r_side
    SK_BMP vm_leg_r, SKF_RIGHT, 0, 0, vm_leg_r_side
    SK_RECT vm_leg_r, SKF_BOTTOM, 0, 0, 6, 6, AC_LEATHER_4, 0
    SK_GRAD vm_leg_r, SKM_SIDES, 272, 224
    ; --- vm_foot_l (shared with vm_foot_r): the boot foot
    SK_FILL vm_foot_l, SKM_ALL, AC_LEATHER_3, 15
    SK_RECT vm_foot_l, SKF_FRONT, 0, 0, 7, 1, AC_LEATHER_2, 0
    SK_RECT vm_foot_l, SKF_FRONT, 0, 1, 7, 1, AC_LEATHER_4, 0
    SK_RECT vm_foot_l, SKF_BACK, 0, 0, 7, 1, AC_LEATHER_3, 0
    SK_RECT vm_foot_l, SKF_BACK, 0, 1, 7, 1, AC_LEATHER_4, 0
    SK_RECT vm_foot_l, SKF_LEFT, 0, 0, 10, 1, AC_LEATHER_1, 0
    SK_RECT vm_foot_l, SKF_LEFT, 0, 1, 10, 1, AC_LEATHER_4, 0
    SK_RECT vm_foot_l, SKF_RIGHT, 0, 0, 10, 1, AC_LEATHER_2, 0
    SK_RECT vm_foot_l, SKF_RIGHT, 0, 1, 10, 1, AC_LEATHER_4, 0
    SK_BMP vm_foot_l, SKF_TOP, 0, 0, vm_foot_top
    SK_RECT vm_foot_l, SKF_BOTTOM, 0, 0, 7, 10, AC_LEATHER_4, 0
SKMODEL_END

; ===================================================================================================
; m_extra_hat
; ===================================================================================================
RAMP XH_FELT, 70, 54, 56                ; black-brown felt

section .rodata
; The characters of every xh_ bitmap. Groups: base, highlight, shade, deep.
;   f F p P black felt   y Y u U gold (AC)   g G d crimson feather   c quill cream   x dark slot   _ transparent
align 8
xh_pal:
    PALC 'f', XH_FELT_2
    PALC 'F', XH_FELT_1
    PALC 'p', XH_FELT_3
    PALC 'P', XH_FELT_4
    PALC 'y', AC_GOLD_2
    PALC 'Y', AC_GOLD_1
    PALC 'u', AC_GOLD_3
    PALC 'U', AC_GOLD_4
    PALC 'g', RGBO(184, 40, 52)
    PALC 'G', RGBO(236, 96, 96)
    PALC 'd', RGBO(112, 22, 36)
    PALC 'c', RGBO(240, 230, 200)
    PALC 'x', RGBO(26, 20, 22)
    PALT '_'
    dq 0

    ; xh_brim_top (20x20): xh_brim TOP
    SKROWS xh_brim_top_rows, 20, 20
    SKROW "FpF.F.F.F.F.F.F.F.FF"
    SKROW "pppppppppppppppppppp"
    SKROW "Fp................pF"
    SKROW ".p.FFFFFF.........p."
    SKROW "Fp.FFFFFF.........pF"
    SKROW ".p................p."
    SKROW "Fp................pF"
    SKROW ".p................p."
    SKROW "Fp................pF"
    SKROW ".p................p."
    SKROW "Fp................pF"
    SKROW ".p................p."
    SKROW "Fp................pF"
    SKROW ".p................p."
    SKROW "Fp................pF"
    SKROW ".p................p."
    SKROW "Fp................pF"
    SKROW ".p................p."
    SKROW "FppppppppppppppppppF"
    SKROW "FpF.F.F.F.F.F.F.F.F."
    SKROWS_END
    align 8
    SKBMP xh_brim_top, xh_brim_top_rows, 20, 20, xh_pal
    ; xh_top_top (10x10): xh_top TOP
    SKROWS xh_top_top_rows, 10, 10
    SKROW "pppppppppp"
    SKROW "p.FFPpff.p"
    SKROW "p.FFPpff.p"
    SKROW "p.FFPpff.p"
    SKROW "p.FFPpff.p"
    SKROW "p.FFPpff.p"
    SKROW "p.FFPpff.p"
    SKROW "p.FFPpff.p"
    SKROW "p.FFPpff.p"
    SKROW "pppppppppp"
    SKROWS_END
    align 8
    SKBMP xh_top_top, xh_top_top_rows, 10, 10, xh_pal
    ; xh_band_front (14x3): xh_band FRONT
    SKROWS xh_band_front_rows, 14, 3
    SKROW "yYyyYyyYyyYyyY"
    SKROW "uyyuyyuyyuyyuy"
    SKROW "UuuUuuUuuUuuUu"
    SKROWS_END
    align 8
    SKBMP xh_band_front, xh_band_front_rows, 14, 3, xh_pal
    ; xh_band_back (14x3): xh_band BACK
    SKROWS xh_band_back_rows, 14, 3
    SKROW "yYyyYyyYyyYyyY"
    SKROW "uyyuyyuyyuyyuy"
    SKROW "UuuUuuUuuUuuUu"
    SKROWS_END
    align 8
    SKBMP xh_band_back, xh_band_back_rows, 14, 3, xh_pal
    ; xh_band_left (14x3): xh_band LEFT
    SKROWS xh_band_left_rows, 14, 3
    SKROW "yYyyYyyYyyYyyY"
    SKROW "uyyuyyuyyuyyuy"
    SKROW "UuuUuuUuuUuuUu"
    SKROWS_END
    align 8
    SKBMP xh_band_left, xh_band_left_rows, 14, 3, xh_pal
    ; xh_band_right (14x3): xh_band RIGHT
    SKROWS xh_band_right_rows, 14, 3
    SKROW "yYyyYyyYyyYyyY"
    SKROW "uyyuyyuyyuyyuy"
    SKROW "UuuUuuUuuUuuUu"
    SKROWS_END
    align 8
    SKBMP xh_band_right, xh_band_right_rows, 14, 3, xh_pal
    ; xh_buckle_front (4x3): xh_buckle FRONT
    SKROWS xh_buckle_front_rows, 4, 3
    SKROW "YYYY"
    SKROW "YxxU"
    SKROW "uUUU"
    SKROWS_END
    align 8
    SKBMP xh_buckle_front, xh_buckle_front_rows, 4, 3, xh_pal
    ; xh_feather_right (6x8): xh_feather RIGHT
    SKROWS xh_feather_right_rows, 6, 8
    SKROW "GG____"
    SKROW "gGGG__"
    SKROW "ddgGG_"
    SKROW "_ddgGG"
    SKROW "__ddgG"
    SKROW "___ddg"
    SKROW "____dc"
    SKROW "_____c"
    SKROWS_END
    align 8
    SKBMP xh_feather_right, xh_feather_right_rows, 6, 8, xh_pal
    ; xh_feather_left (6x8): xh_feather LEFT
    SKROWS xh_feather_left_rows, 6, 8
    SKROW "____GG"
    SKROW "__GGGg"
    SKROW "_GGgdd"
    SKROW "GGgdd_"
    SKROW "Ggdd__"
    SKROW "gdd___"
    SKROW "cd____"
    SKROW "c_____"
    SKROWS_END
    align 8
    SKBMP xh_feather_left, xh_feather_left_rows, 6, 8, xh_pal

section .data
SKMODEL_BEGIN m_extra_hat, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART xh_brim, -10, 61, -10, 20, 2, 20, 3, 0             ; wide brim
    PART xh_crown, -7, 63, -7, 14, 5, 14, 1, 0              ; crown
    PART xh_top, -5, 68, -5, 10, 3, 10, 1, 0                ; pinched top
    PART xh_band, -7, 63, -7, 14, 3, 14, 5, 0               ; gold band
    PART xh_buckle, -2, 63, -8, 4, 3, 1, 1, 0               ; gold buckle
    PART xh_feather, 7, 64, -3, 1, 8, 6, 3, SKPF_CUTOUT     ; crimson plume on the right
SKMODEL_PAINT
    ; --- xh_brim: felt, a stitched rim, a darker underside
    SK_FILL xh_brim, SKM_ALL, XH_FELT_2, 15
    SK_RECT xh_brim, SKF_FRONT, 0, 0, 20, 1, XH_FELT_1, 0
    SK_RECT xh_brim, SKF_FRONT, 0, 1, 20, 1, XH_FELT_3, 0
    SK_RECT xh_brim, SKF_BACK, 0, 0, 20, 1, XH_FELT_1, 0
    SK_RECT xh_brim, SKF_BACK, 0, 1, 20, 1, XH_FELT_3, 0
    SK_RECT xh_brim, SKF_LEFT, 0, 0, 20, 1, XH_FELT_1, 0
    SK_RECT xh_brim, SKF_LEFT, 0, 1, 20, 1, XH_FELT_3, 0
    SK_RECT xh_brim, SKF_RIGHT, 0, 0, 20, 1, XH_FELT_1, 0
    SK_RECT xh_brim, SKF_RIGHT, 0, 1, 20, 1, XH_FELT_3, 0
    SK_BMP xh_brim, SKF_TOP, 0, 0, xh_brim_top
    SK_RECT xh_brim, SKF_BOTTOM, 0, 0, 20, 20, XH_FELT_4, 0
    SK_GRAD xh_brim, SKM_SIDES, 272, 224
    ; --- xh_crown / xh_top: the tall crown with a pinch crease
    SK_FILL xh_crown, SKM_ALL, XH_FELT_2, 15
    SK_RECT xh_crown, SKF_FRONT, 0, 0, 1, 5, XH_FELT_1, 0
    SK_RECT xh_crown, SKF_FRONT, 13, 0, 1, 5, XH_FELT_3, 0
    SK_RECT xh_crown, SKF_BACK, 0, 0, 1, 5, XH_FELT_1, 0
    SK_RECT xh_crown, SKF_BACK, 13, 0, 1, 5, XH_FELT_3, 0
    SK_RECT xh_crown, SKF_LEFT, 0, 0, 1, 5, XH_FELT_1, 0
    SK_RECT xh_crown, SKF_LEFT, 13, 0, 1, 5, XH_FELT_3, 0
    SK_RECT xh_crown, SKF_RIGHT, 0, 0, 1, 5, XH_FELT_1, 0
    SK_RECT xh_crown, SKF_RIGHT, 13, 0, 1, 5, XH_FELT_3, 0
    SK_RECT xh_crown, SKF_TOP, 0, 0, 14, 14, XH_FELT_2, 15
    SK_RECT xh_crown, SKF_BOTTOM, 0, 0, 14, 14, XH_FELT_4, 0
    SK_GRAD xh_crown, SKM_SIDES, 272, 224
    SK_FILL xh_top, SKM_ALL, XH_FELT_2, 15
    SK_RECT xh_top, SKF_FRONT, 0, 0, 1, 3, XH_FELT_1, 0
    SK_RECT xh_top, SKF_FRONT, 9, 0, 1, 3, XH_FELT_3, 0
    SK_RECT xh_top, SKF_FRONT, 4, 0, 2, 1, XH_FELT_4, 0
    SK_RECT xh_top, SKF_BACK, 0, 0, 1, 3, XH_FELT_1, 0
    SK_RECT xh_top, SKF_BACK, 9, 0, 1, 3, XH_FELT_3, 0
    SK_RECT xh_top, SKF_BACK, 4, 0, 2, 1, XH_FELT_4, 0
    SK_RECT xh_top, SKF_LEFT, 0, 0, 1, 3, XH_FELT_1, 0
    SK_RECT xh_top, SKF_LEFT, 9, 0, 1, 3, XH_FELT_3, 0
    SK_RECT xh_top, SKF_LEFT, 4, 0, 2, 1, XH_FELT_4, 0
    SK_RECT xh_top, SKF_RIGHT, 0, 0, 1, 3, XH_FELT_1, 0
    SK_RECT xh_top, SKF_RIGHT, 9, 0, 1, 3, XH_FELT_3, 0
    SK_RECT xh_top, SKF_RIGHT, 4, 0, 2, 1, XH_FELT_4, 0
    SK_BMP xh_top, SKF_TOP, 0, 0, xh_top_top
    SK_RECT xh_top, SKF_BOTTOM, 0, 0, 10, 10, XH_FELT_4, 0
    SK_GRAD xh_top, SKM_SIDES, 272, 224
    ; --- xh_band: a braided gold band; xh_buckle: a gold buckle with a dark slot
    SK_FILL xh_band, SKM_ALL, AC_GOLD_2, 0
    SK_BMP xh_band, SKF_FRONT, 0, 0, xh_band_front
    SK_BMP xh_band, SKF_BACK, 0, 0, xh_band_back
    SK_BMP xh_band, SKF_LEFT, 0, 0, xh_band_left
    SK_BMP xh_band, SKF_RIGHT, 0, 0, xh_band_right
    SK_RECT xh_band, SKF_TOP, 0, 0, 14, 14, AC_GOLD_2, 0
    SK_RECT xh_band, SKF_BOTTOM, 0, 0, 14, 14, AC_GOLD_4, 0
    SK_FILL xh_buckle, SKM_ALL, AC_GOLD_3, 0
    SK_BMP xh_buckle, SKF_FRONT, 0, 0, xh_buckle_front
    ; --- xh_feather: a crimson plume, cutout silhouette sweeping up and back; both flat faces carry it
    SK_FILL xh_feather, SKM_ALL, RGBO(184, 40, 52), 0
    SK_BMP xh_feather, SKF_RIGHT, 0, 0, xh_feather_right
    SK_BMP xh_feather, SKF_LEFT, 0, 0, xh_feather_left
    SK_RECT xh_feather, SKF_FRONT, 0, 0, 1, 8, RGBO(150, 30, 44), 0
    SK_RECT xh_feather, SKF_BACK, 0, 0, 1, 8, RGBO(150, 30, 44), 0
    SK_RECT xh_feather, SKF_TOP, 0, 0, 1, 6, RGBO(150, 30, 44), 0
    SK_RECT xh_feather, SKF_BOTTOM, 0, 0, 1, 6, RGBO(150, 30, 44), 0
SKMODEL_END

; ===================================================================================================
; m_extra_helmet
; ===================================================================================================

section .rodata
; The characters of every xm_ bitmap. Groups: base, highlight, shade, deep.
;   i I o O iron (AC)   k dark iron seam   r rivet   R rivet glint   _ transparent
align 8
xm_pal:
    PALC 'i', AC_IRON_2
    PALC 'I', AC_IRON_1
    PALC 'o', AC_IRON_3
    PALC 'O', AC_IRON_4
    PALC 'k', RGBO(60, 62, 70)
    PALC 'r', RGBO(112, 116, 126)
    PALC 'R', RGBO(255, 255, 255)
    PALT '_'
    dq 0

    ; xm_shell_front (18x12): xm_shell FRONT
    SKROWS xm_shell_front_rows, 18, 12
    SKROW "Iiiiiiiiiiiiiiiiio"
    SKROW "I................o"
    SKROW "I.r...r...r...r..o"
    SKROW "I.k...k...k...k..o"
    SKROW "I................o"
    SKROW "Iooooooooooooooooo"
    SKROW "Io______________ko"
    SKROW "Io______________ko"
    SKROW "ro______________kr"
    SKROW "Io______________ko"
    SKROW "ro______________kr"
    SKROW "Io______________ko"
    SKROWS_END
    align 8
    SKBMP xm_shell_front, xm_shell_front_rows, 18, 12, xm_pal
    ; xm_shell_back (18x12): xm_shell BACK
    SKROWS xm_shell_back_rows, 18, 12
    SKROW "iiiiiiiiiiiiiiiiii"
    SKROW "........kI........"
    SKROW "........kI........"
    SKROW "........kI........"
    SKROW "........kI........"
    SKROW "ooooooookIoooooooo"
    SKROW "........kI........"
    SKROW "........kI........"
    SKROW "..r..r..kI..r..r.."
    SKROW "..k..k..kI..k..k.."
    SKROW "........kI........"
    SKROW "oooooooooooooooooo"
    SKROWS_END
    align 8
    SKBMP xm_shell_back, xm_shell_back_rows, 18, 12, xm_pal
    ; xm_shell_side (18x12): xm_shell LEFT, xm_shell RIGHT
    SKROWS xm_shell_side_rows, 18, 12
    SKROW "iiiiiiiiiiiiiiiiii"
    SKROW ".................."
    SKROW "..r...r...r...r..."
    SKROW "..k...k...k...k..."
    SKROW ".................."
    SKROW "oooooooooooooooooo"
    SKROW ".................."
    SKROW ".................."
    SKROW "...O..O..O..O..O.."
    SKROW ".................."
    SKROW ".................."
    SKROW "kkkkkkkkkkkkkkkkkk"
    SKROWS_END
    align 8
    SKBMP xm_shell_side, xm_shell_side_rows, 18, 12, xm_pal
    ; xm_shell_top (18x18): xm_shell TOP
    SKROWS xm_shell_top_rows, 18, 18
    SKROW "iooooooooooooooooo"
    SKROW "i.......ki.......o"
    SKROW "i.IIII..ki.......o"
    SKROW "i.Ir....ki....r..o"
    SKROW "i.I.....ki.......o"
    SKROW "i.I.....ki.......o"
    SKROW "i.......ki.......o"
    SKROW "i.......ki.......o"
    SKROW "i.......ki.......o"
    SKROW "i.......ki.......o"
    SKROW "i.......ki.......o"
    SKROW "i.......ki.......o"
    SKROW "i.......ki.......o"
    SKROW "i.......ki.......o"
    SKROW "i..r....ki....r..o"
    SKROW "i.......ki.......o"
    SKROW "i.......ki.......o"
    SKROW "iooooooooooooooooo"
    SKROWS_END
    align 8
    SKBMP xm_shell_top, xm_shell_top_rows, 18, 18, xm_pal
    ; xm_band_front (18x3): xm_band FRONT
    SKROWS xm_band_front_rows, 18, 3
    SKROW "IIIIIIIIIIIIIIIIII"
    SKROW ".R..r..R..r..R..r."
    SKROW "oooooooooooooooooo"
    SKROWS_END
    align 8
    SKBMP xm_band_front, xm_band_front_rows, 18, 3, xm_pal
    ; xm_band_back (18x3): xm_band BACK
    SKROWS xm_band_back_rows, 18, 3
    SKROW "IIIIIIIIIIIIIIIIII"
    SKROW ".R..r..R..r..R..r."
    SKROW "oooooooooooooooooo"
    SKROWS_END
    align 8
    SKBMP xm_band_back, xm_band_back_rows, 18, 3, xm_pal
    ; xm_band_left (18x3): xm_band LEFT
    SKROWS xm_band_left_rows, 18, 3
    SKROW "IIIIIIIIIIIIIIIIII"
    SKROW ".R..r..R..r..R..r."
    SKROW "oooooooooooooooooo"
    SKROWS_END
    align 8
    SKBMP xm_band_left, xm_band_left_rows, 18, 3, xm_pal
    ; xm_band_right (18x3): xm_band RIGHT
    SKROWS xm_band_right_rows, 18, 3
    SKROW "IIIIIIIIIIIIIIIIII"
    SKROW ".R..r..R..r..R..r."
    SKROW "oooooooooooooooooo"
    SKROWS_END
    align 8
    SKBMP xm_band_right, xm_band_right_rows, 18, 3, xm_pal
    ; xm_nose_front (2x9): xm_nose FRONT
    SKROWS xm_nose_front_rows, 2, 9
    SKROW "ir"
    SKROW "Io"
    SKROW "Io"
    SKROW "Io"
    SKROW "Io"
    SKROW "Io"
    SKROW "Io"
    SKROW "Io"
    SKROW "Ik"
    SKROWS_END
    align 8
    SKBMP xm_nose_front, xm_nose_front_rows, 2, 9, xm_pal
    ; xm_crest_side (16x3): xm_crest LEFT, xm_crest RIGHT
    SKROWS xm_crest_side_rows, 16, 3
    SKROW "iiiiiiiiiiiiiiii"
    SKROW ".r...r...r...r.."
    SKROW "oooooooooooooooo"
    SKROWS_END
    align 8
    SKBMP xm_crest_side, xm_crest_side_rows, 16, 3, xm_pal
    ; xm_neck_back (16x7): xm_neck BACK
    SKROWS xm_neck_back_rows, 16, 7
    SKROW "IIIIIIIIIIIIIIIo"
    SKROW "I.r...r...r...ro"
    SKROW "I..............o"
    SKROW "Ikkkkkkkkkkkkkko"
    SKROW "I.r...r...r...ro"
    SKROW "I..............o"
    SKROW "Iooooooooooooooo"
    SKROWS_END
    align 8
    SKBMP xm_neck_back, xm_neck_back_rows, 16, 7, xm_pal

section .data
SKMODEL_BEGIN m_extra_helmet, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART xm_shell, -9, 52, -9, 18, 12, 18, 3, SKPF_CUTOUT   ; dome with the open face
    PART xm_band, -9, 58, -9, 18, 3, 18, 11, 0              ; riveted brow band round the helmet
    PART xm_nose, -1, 49, -11, 2, 9, 1, 3, 0                ; nose guard
    PART xm_crest, -1, 64, -8, 2, 3, 16, 1, 0               ; crest ridge
    PART xm_neck, -8, 46, 9, 16, 7, 2, 3, 0                 ; neck guard behind
SKMODEL_PAINT
    ; --- xm_shell: hammered iron dome; the front is open from y 52 to 58 between two cheek strips
    SK_FILL xm_shell, SKM_ALL, AC_IRON_2, 0
    SK_BMP xm_shell, SKF_FRONT, 0, 0, xm_shell_front
    SK_BMP xm_shell, SKF_BACK, 0, 0, xm_shell_back
    SK_BMP xm_shell, SKF_LEFT, 0, 0, xm_shell_side
    SK_BMP xm_shell, SKF_RIGHT, 0, 0, xm_shell_side
    SK_BMP xm_shell, SKF_TOP, 0, 0, xm_shell_top
    SK_RECT xm_shell, SKF_BOTTOM, 0, 0, 18, 18, AC_IRON_4, 0
    SK_GRAD xm_shell, SKM_SIDES, 272, 224
    ; --- xm_band: a thick iron band with a rivet every third texel
    SK_FILL xm_band, SKM_ALL, AC_IRON_2, 0
    SK_BMP xm_band, SKF_FRONT, 0, 0, xm_band_front
    SK_BMP xm_band, SKF_BACK, 0, 0, xm_band_back
    SK_BMP xm_band, SKF_LEFT, 0, 0, xm_band_left
    SK_BMP xm_band, SKF_RIGHT, 0, 0, xm_band_right
    SK_RECT xm_band, SKF_TOP, 0, 0, 18, 18, AC_IRON_2, 0
    SK_RECT xm_band, SKF_BOTTOM, 0, 0, 18, 18, AC_IRON_4, 0
    SK_GRAD xm_band, SKM_SIDES, 272, 224
    ; --- xm_nose, xm_crest, xm_neck
    SK_FILL xm_nose, SKM_ALL, AC_IRON_2, 0
    SK_BMP xm_nose, SKF_FRONT, 0, 0, xm_nose_front
    SK_RECT xm_nose, SKF_LEFT, 0, 0, 1, 9, AC_IRON_1, 0
    SK_RECT xm_nose, SKF_RIGHT, 0, 0, 1, 9, AC_IRON_3, 0
    SK_RECT xm_nose, SKF_TOP, 0, 0, 2, 1, AC_IRON_1, 0
    SK_RECT xm_nose, SKF_BOTTOM, 0, 0, 2, 1, AC_IRON_4, 0
    SK_FILL xm_crest, SKM_ALL, AC_IRON_2, 0
    SK_BMP xm_crest, SKF_LEFT, 0, 0, xm_crest_side
    SK_BMP xm_crest, SKF_RIGHT, 0, 0, xm_crest_side
    SK_RECT xm_crest, SKF_FRONT, 0, 0, 2, 3, AC_IRON_3, 0
    SK_RECT xm_crest, SKF_BACK, 0, 0, 2, 3, AC_IRON_3, 0
    SK_RECT xm_crest, SKF_TOP, 0, 0, 2, 16, AC_IRON_2, 0
    SK_RECT xm_crest, SKF_BOTTOM, 0, 0, 2, 16, AC_IRON_4, 0
    SK_FILL xm_neck, SKM_ALL, AC_IRON_2, 0
    SK_BMP xm_neck, SKF_BACK, 0, 0, xm_neck_back
    SK_RECT xm_neck, SKF_FRONT, 0, 0, 16, 7, AC_IRON_4, 0
    SK_RECT xm_neck, SKF_TOP, 0, 0, 16, 2, AC_IRON_2, 0
    SK_RECT xm_neck, SKF_BOTTOM, 0, 0, 16, 2, AC_IRON_4, 0
    SK_GRAD xm_neck, SKM_SIDES, 272, 224
SKMODEL_END

; ===================================================================================================
; m_extra_pack
; ===================================================================================================
RAMP XP_CANVAS, 158, 144, 102           ; khaki canvas
RAMP XP_WOOL, 152, 70, 60               ; the bedroll wool

section .rodata
; The characters of every xp_ bitmap. Groups: base, highlight, shade, deep.
;   w W d D wood (AC)   c C v V canvas   r R o O red wool   q cream stripe   l L e E leather (AC)
;   y Y u U brass (AC gold)   _ transparent
align 8
xp_pal:
    PALC 'w', AC_WOOD_2
    PALC 'W', AC_WOOD_1
    PALC 'd', AC_WOOD_3
    PALC 'D', AC_WOOD_4
    PALC 'c', XP_CANVAS_2
    PALC 'C', XP_CANVAS_1
    PALC 'v', XP_CANVAS_3
    PALC 'V', XP_CANVAS_4
    PALC 'r', XP_WOOL_2
    PALC 'R', XP_WOOL_1
    PALC 'o', XP_WOOL_3
    PALC 'O', XP_WOOL_4
    PALC 'q', RGBO(232, 220, 190)
    PALC 'l', AC_LEATHER_2
    PALC 'L', AC_LEATHER_1
    PALC 'e', AC_LEATHER_3
    PALC 'E', AC_LEATHER_4
    PALC 'y', AC_GOLD_2
    PALC 'Y', AC_GOLD_1
    PALC 'u', AC_GOLD_3
    PALC 'U', AC_GOLD_4
    PALT '_'
    dq 0

    ; xp_post_front (2x16): xp_post_l FRONT
    SKROWS xp_post_front_rows, 2, 16
    SKROW "Wd"
    SKROW "ee"
    SKROW "Wd"
    SKROW "Wd"
    SKROW "Wd"
    SKROW "ee"
    SKROW "Wd"
    SKROW "Wd"
    SKROW "Wd"
    SKROW "ee"
    SKROW "Wd"
    SKROW "Wd"
    SKROW "Wd"
    SKROW "ee"
    SKROW "Wd"
    SKROW "Wd"
    SKROWS_END
    align 8
    SKBMP xp_post_front, xp_post_front_rows, 2, 16, xp_pal
    ; xp_post_back (2x16): xp_post_l BACK
    SKROWS xp_post_back_rows, 2, 16
    SKROW "Wd"
    SKROW "ee"
    SKROW "Wd"
    SKROW "Wd"
    SKROW "Wd"
    SKROW "ee"
    SKROW "Wd"
    SKROW "Wd"
    SKROW "Wd"
    SKROW "ee"
    SKROW "Wd"
    SKROW "Wd"
    SKROW "Wd"
    SKROW "ee"
    SKROW "Wd"
    SKROW "Wd"
    SKROWS_END
    align 8
    SKBMP xp_post_back, xp_post_back_rows, 2, 16, xp_pal
    ; xp_post_left (2x16): xp_post_l LEFT
    SKROWS xp_post_left_rows, 2, 16
    SKROW "Wd"
    SKROW "ee"
    SKROW "Wd"
    SKROW "Wd"
    SKROW "Wd"
    SKROW "ee"
    SKROW "Wd"
    SKROW "Wd"
    SKROW "Wd"
    SKROW "ee"
    SKROW "Wd"
    SKROW "Wd"
    SKROW "Wd"
    SKROW "ee"
    SKROW "Wd"
    SKROW "Wd"
    SKROWS_END
    align 8
    SKBMP xp_post_left, xp_post_left_rows, 2, 16, xp_pal
    ; xp_post_right (2x16): xp_post_l RIGHT
    SKROWS xp_post_right_rows, 2, 16
    SKROW "Wd"
    SKROW "ee"
    SKROW "Wd"
    SKROW "Wd"
    SKROW "Wd"
    SKROW "ee"
    SKROW "Wd"
    SKROW "Wd"
    SKROW "Wd"
    SKROW "ee"
    SKROW "Wd"
    SKROW "Wd"
    SKROW "Wd"
    SKROW "ee"
    SKROW "Wd"
    SKROW "Wd"
    SKROWS_END
    align 8
    SKBMP xp_post_right, xp_post_right_rows, 2, 16, xp_pal
    ; xp_bag_back (10x12): xp_bag BACK
    SKROWS xp_bag_back_rows, 10, 12
    SKROW "C........v"
    SKROW "C........v"
    SKROW "C........v"
    SKROW "C....VVVVv"
    SKROW "C....Vccvv"
    SKROW "C....Vccvv"
    SKROW "C....Vvvvv"
    SKROW "C........v"
    SKROW "CV.V.V.V.v"
    SKROW "C........v"
    SKROW "llllllllll"
    SKROW "eeeeeeeeee"
    SKROWS_END
    align 8
    SKBMP xp_bag_back, xp_bag_back_rows, 10, 12, xp_pal
    ; xp_bag_side (4x12): xp_bag LEFT, xp_bag RIGHT
    SKROWS xp_bag_side_rows, 4, 12
    SKROW "C..v"
    SKROW "C..v"
    SKROW "C..v"
    SKROW "C..v"
    SKROW "C..v"
    SKROW "C..v"
    SKROW "C..v"
    SKROW "C..v"
    SKROW "C..v"
    SKROW "C..v"
    SKROW "llll"
    SKROW "eeee"
    SKROWS_END
    align 8
    SKBMP xp_bag_side, xp_bag_side_rows, 4, 12, xp_pal
    ; xp_flap_back (12x10): xp_flap BACK
    SKROWS xp_flap_back_rows, 12, 10
    SKROW "LLLLLLLLLLLe"
    SKROW "L.e.e.e.e..e"
    SKROW "L...E..E...e"
    SKROW "L...E..E...e"
    SKROW "L...E..E...e"
    SKROW "L...E..E...e"
    SKROW "L...YYYY...e"
    SKROW "L...yEEy...e"
    SKROW "L.e.yyyye..e"
    SKROW "Leeeeeeeeeee"
    SKROWS_END
    align 8
    SKBMP xp_flap_back, xp_flap_back_rows, 12, 10, xp_pal
    ; xp_roll_band (16x5): xp_roll BACK, xp_roll FRONT
    SKROWS xp_roll_band_rows, 16, 5
    SKROW "RRRLeRRRRRRLeRRR"
    SKROW "R..Le......Le..."
    SKROW "RqqYyqqqqqqYyqqq"
    SKROW "R..Le......Le..."
    SKROW "RooLeooooooLeooo"
    SKROWS_END
    align 8
    SKBMP xp_roll_band, xp_roll_band_rows, 16, 5, xp_pal
    ; xp_roll_end (5x5): xp_roll LEFT, xp_roll RIGHT
    SKROWS xp_roll_end_rows, 5, 5
    SKROW "RRRRo"
    SKROW "RqqRo"
    SKROW "RqoRo"
    SKROW "RRRRo"
    SKROW "ooooO"
    SKROWS_END
    align 8
    SKBMP xp_roll_end, xp_roll_end_rows, 5, 5, xp_pal
    ; xp_roll_top (16x5): xp_roll TOP
    SKROWS xp_roll_top_rows, 16, 5
    SKROW "RRRLlRRRRRRLlRRR"
    SKROW "...Ll......Ll..."
    SKROW "qqqLlqqqqqqLlqqq"
    SKROW "...Ll......Ll..."
    SKROW "...Ll......Ll..."
    SKROWS_END
    align 8
    SKBMP xp_roll_top, xp_roll_top_rows, 16, 5, xp_pal
    ; xp_strap_front (2x16): xp_strap_l FRONT
    SKROWS xp_strap_front_rows, 2, 16
    SKROW "Le"
    SKROW "le"
    SKROW "Le"
    SKROW "Le"
    SKROW "le"
    SKROW "Le"
    SKROW "Le"
    SKROW "le"
    SKROW "Le"
    SKROW "Le"
    SKROW "le"
    SKROW "Le"
    SKROW "Le"
    SKROW "le"
    SKROW "Yy"
    SKROW "uU"
    SKROWS_END
    align 8
    SKBMP xp_strap_front, xp_strap_front_rows, 2, 16, xp_pal

section .data
SKMODEL_BEGIN m_extra_pack, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART xp_post_l, -7, 28, 4, 2, 16, 2, 3, 0               ; frame post (the right one shares its skin)
    PART_AS xp_post_r, xp_post_l, 5, 28, 4, 3, 0
    PART xp_bar_t, -5, 42, 4, 10, 2, 2, 1, 0                ; top crossbar
    PART_AS xp_bar_b, xp_bar_t, -5, 28, 4, 1, 0
    PART xp_bag, -5, 30, 5, 10, 12, 4, 1, 0                 ; canvas bag between the posts
    PART xp_flap, -6, 33, 9, 12, 10, 1, 1, 0                ; leather flap with a buckle strap
    PART xp_roll, -8, 41, 5, 16, 5, 5, 3, 0                 ; the bedroll on top, strapped
    PART xp_strap_l, -5, 30, -5, 2, 16, 1, 3, 0             ; shoulder strap down the chest (the right one shares its skin)
    PART_AS xp_strap_r, xp_strap_l, 3, 30, -5, 3, 0
SKMODEL_PAINT
    ; --- xp_post_l (shared with xp_post_r), xp_bar_t (shared with xp_bar_b): the wooden frame, lashed
    SK_FILL xp_post_l, SKM_ALL, AC_WOOD_2, 31
    SK_BMP xp_post_l, SKF_FRONT, 0, 0, xp_post_front
    SK_BMP xp_post_l, SKF_BACK, 0, 0, xp_post_back
    SK_BMP xp_post_l, SKF_LEFT, 0, 0, xp_post_left
    SK_BMP xp_post_l, SKF_RIGHT, 0, 0, xp_post_right
    SK_RECT xp_post_l, SKF_TOP, 0, 0, 2, 2, AC_WOOD_1, 0
    SK_RECT xp_post_l, SKF_BOTTOM, 0, 0, 2, 2, AC_WOOD_4, 0
    SK_GRAD xp_post_l, SKM_SIDES, 272, 224
    SK_FILL xp_bar_t, SKM_ALL, AC_WOOD_2, 31
    SK_RECT xp_bar_t, SKF_FRONT, 0, 0, 10, 1, AC_WOOD_1, 0
    SK_RECT xp_bar_t, SKF_FRONT, 0, 1, 10, 1, AC_WOOD_3, 0
    SK_RECT xp_bar_t, SKF_BACK, 0, 0, 10, 1, AC_WOOD_1, 0
    SK_RECT xp_bar_t, SKF_BACK, 0, 1, 10, 1, AC_WOOD_3, 0
    SK_RECT xp_bar_t, SKF_LEFT, 0, 0, 2, 1, AC_WOOD_1, 0
    SK_RECT xp_bar_t, SKF_LEFT, 0, 1, 2, 1, AC_WOOD_3, 0
    SK_RECT xp_bar_t, SKF_RIGHT, 0, 0, 2, 1, AC_WOOD_1, 0
    SK_RECT xp_bar_t, SKF_RIGHT, 0, 1, 2, 1, AC_WOOD_3, 0
    SK_RECT xp_bar_t, SKF_TOP, 0, 0, 10, 2, AC_WOOD_1, 7
    SK_RECT xp_bar_t, SKF_BOTTOM, 0, 0, 10, 2, AC_WOOD_4, 0
    ; --- xp_bag: canvas with a stitched seam, a patch and a leather bottom
    SK_FILL xp_bag, SKM_ALL, XP_CANVAS_2, 15
    SK_BMP xp_bag, SKF_BACK, 0, 0, xp_bag_back
    SK_BMP xp_bag, SKF_LEFT, 0, 0, xp_bag_side
    SK_BMP xp_bag, SKF_RIGHT, 0, 0, xp_bag_side
    SK_RECT xp_bag, SKF_FRONT, 0, 0, 10, 12, XP_CANVAS_3, 0
    SK_RECT xp_bag, SKF_TOP, 0, 0, 10, 4, XP_CANVAS_1, 15
    SK_RECT xp_bag, SKF_BOTTOM, 0, 0, 10, 4, AC_LEATHER_4, 0
    SK_GRAD xp_bag, SKM_SIDES, 272, 224
    ; --- xp_flap: leather, stitched edge, a strap with a brass buckle
    SK_FILL xp_flap, SKM_ALL, AC_LEATHER_2, 15
    SK_BMP xp_flap, SKF_BACK, 0, 0, xp_flap_back
    SK_RECT xp_flap, SKF_FRONT, 0, 0, 12, 10, AC_LEATHER_4, 0
    SK_RECT xp_flap, SKF_TOP, 0, 0, 12, 1, AC_LEATHER_1, 0
    SK_RECT xp_flap, SKF_BOTTOM, 0, 0, 12, 1, AC_LEATHER_4, 0
    SK_GRAD xp_flap, SKM_SIDES, 272, 224
    ; --- xp_roll: a red wool bedroll, cream stripes, two leather straps; the ends show the spiral
    SK_FILL xp_roll, SKM_ALL, XP_WOOL_2, 15
    SK_BMP xp_roll, SKF_BACK, 0, 0, xp_roll_band
    SK_BMP xp_roll, SKF_FRONT, 0, 0, xp_roll_band
    SK_BMP xp_roll, SKF_LEFT, 0, 0, xp_roll_end
    SK_BMP xp_roll, SKF_RIGHT, 0, 0, xp_roll_end
    SK_BMP xp_roll, SKF_TOP, 0, 0, xp_roll_top
    SK_RECT xp_roll, SKF_BOTTOM, 0, 0, 16, 5, XP_WOOL_4, 0
    SK_GRAD xp_roll, SKM_SIDES, 272, 224
    ; --- xp_strap_l (shared with xp_strap_r): a stitched leather strap with a brass ring at the foot
    SK_FILL xp_strap_l, SKM_ALL, AC_LEATHER_2, 7
    SK_BMP xp_strap_l, SKF_FRONT, 0, 0, xp_strap_front
    SK_RECT xp_strap_l, SKF_BACK, 0, 0, 2, 16, AC_LEATHER_4, 0
    SK_RECT xp_strap_l, SKF_LEFT, 0, 0, 1, 16, AC_LEATHER_3, 0
    SK_RECT xp_strap_l, SKF_RIGHT, 0, 0, 1, 16, AC_LEATHER_3, 0
    SK_RECT xp_strap_l, SKF_TOP, 0, 0, 2, 1, AC_LEATHER_1, 0
    SK_RECT xp_strap_l, SKF_BOTTOM, 0, 0, 2, 1, AC_LEATHER_4, 0
SKMODEL_END

; ===================================================================================================
; m_extra_crown
; ===================================================================================================

section .rodata
; The characters of every xc_ bitmap. Groups: base, highlight, shade, deep.
;   y Y u U gold (AC)   r R d ruby (base, glint, deep)   b B n sapphire (base, glint, deep)   _ transparent
align 8
xc_pal:
    PALC 'y', AC_GOLD_2
    PALC 'Y', AC_GOLD_1
    PALC 'u', AC_GOLD_3
    PALC 'U', AC_GOLD_4
    PALC 'r', RGBO(200, 36, 60)
    PALC 'R', RGBO(255, 170, 170)
    PALC 'd', RGBO(120, 16, 40)
    PALC 'b', RGBO(48, 96, 214)
    PALC 'B', RGBO(168, 204, 255)
    PALC 'n', RGBO(24, 52, 140)
    PALT '_'
    dq 0

    ; xc_wall_front (18x6): xc_wall_f FRONT, xc_wall_f BACK
    SKROWS xc_wall_front_rows, 18, 6
    SKROW "__Y_____Yu_____Y__"
    SKROW "_Yyu___Yyyu___Yyu_"
    SKROW "Yyyyu_Yyyyyu_Yyyyu"
    SKROW "YYYYYYYYYYYYYYYYYY"
    SKROW "yyyyyyyyyyyyyyyyyy"
    SKROW "uuuuuuuuuuuuuuuuuu"
    SKROWS_END
    align 8
    SKBMP xc_wall_front, xc_wall_front_rows, 18, 6, xc_pal
    ; xc_wall_top (18x1): xc_wall_f TOP
    SKROWS xc_wall_top_rows, 18, 1
    SKROW "__y_____yy_____y__"
    SKROWS_END
    align 8
    SKBMP xc_wall_top, xc_wall_top_rows, 18, 1, xc_pal
    ; xc_wall_side (16x6): xc_wall_l LEFT, xc_wall_l RIGHT
    SKROWS xc_wall_side_rows, 16, 6
    SKROW "_Yu____Yu____Yu_"
    SKROW "_Yu____Yu____Yu_"
    SKROW "Yyyu__Yyyu__Yyyu"
    SKROW "YYYYYYYYYYYYYYYY"
    SKROW "yyyyyyyyyyyyyyyy"
    SKROW "uuuuuuuuuuuuuuuu"
    SKROWS_END
    align 8
    SKBMP xc_wall_side, xc_wall_side_rows, 16, 6, xc_pal
    ; xc_wall_side_top (1x16): xc_wall_l TOP
    SKROWS xc_wall_side_top_rows, 1, 16
    SKROW "_"
    SKROW "y"
    SKROW "y"
    SKROW "_"
    SKROW "_"
    SKROW "_"
    SKROW "_"
    SKROW "y"
    SKROW "y"
    SKROW "_"
    SKROW "_"
    SKROW "_"
    SKROW "_"
    SKROW "y"
    SKROW "y"
    SKROW "_"
    SKROWS_END
    align 8
    SKBMP xc_wall_side_top, xc_wall_side_top_rows, 1, 16, xc_pal
    ; xc_gem_f_front (4x3): xc_gem_f FRONT
    SKROWS xc_gem_f_front_rows, 4, 3
    SKROW "RRrr"
    SKROW "Rrrd"
    SKROW "rrdd"
    SKROWS_END
    align 8
    SKBMP xc_gem_f_front, xc_gem_f_front_rows, 4, 3, xc_pal
    ; xc_gem_f_back (4x3): xc_gem_f BACK
    SKROWS xc_gem_f_back_rows, 4, 3
    SKROW "dddd"
    SKROW "dddd"
    SKROW "dddd"
    SKROWS_END
    align 8
    SKBMP xc_gem_f_back, xc_gem_f_back_rows, 4, 3, xc_pal
    ; xc_gem_l_left (4x3): xc_gem_l LEFT
    SKROWS xc_gem_l_left_rows, 4, 3
    SKROW "BBbb"
    SKROW "Bbbn"
    SKROW "bbnn"
    SKROWS_END
    align 8
    SKBMP xc_gem_l_left, xc_gem_l_left_rows, 4, 3, xc_pal
    ; xc_gem_l_right (4x3): xc_gem_l RIGHT
    SKROWS xc_gem_l_right_rows, 4, 3
    SKROW "bbBB"
    SKROW "nbbB"
    SKROW "nnbb"
    SKROWS_END
    align 8
    SKBMP xc_gem_l_right, xc_gem_l_right_rows, 4, 3, xc_pal

section .data
SKMODEL_BEGIN m_extra_crown, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART xc_wall_f, -9, 62, -9, 18, 6, 1, 3, SKPF_CUTOUT    ; front wall: band and three spikes (the back one shares its skin)
    PART_AS xc_wall_b, xc_wall_f, -9, 62, 8, 3, SKPF_CUTOUT
    PART xc_wall_l, -9, 62, -8, 1, 6, 16, 7, SKPF_CUTOUT    ; side wall (the right one shares its skin)
    PART_AS xc_wall_r, xc_wall_l, 8, 62, -8, 7, SKPF_CUTOUT
    PART xc_gem_f, -2, 62, -10, 4, 3, 1, 0, 0               ; ruby on the front band (the back one shares its skin)
    PART_AS xc_gem_b, xc_gem_f, -2, 62, 9, 0, 0
    PART xc_gem_l, -11, 62, -2, 2, 3, 4, 0, 0               ; sapphire on the side band (the other shares its skin)
    PART_AS xc_gem_r, xc_gem_l, 9, 62, -2, 0, 0
SKMODEL_PAINT
    ; --- xc_wall_f / xc_wall_l: a gold band with spikes cut into the face; the top edge is opaque only at the spike tips
    SK_FILL xc_wall_f, SKM_ALL, AC_GOLD_2, 0
    SK_BMP xc_wall_f, SKF_FRONT, 0, 0, xc_wall_front
    SK_BMP xc_wall_f, SKF_BACK, 0, 0, xc_wall_front
    SK_BMP xc_wall_f, SKF_TOP, 0, 0, xc_wall_top
    SK_RECT xc_wall_f, SKF_BOTTOM, 0, 0, 18, 1, AC_GOLD_4, 0
    SK_RECT xc_wall_f, SKF_LEFT, 0, 0, 1, 6, AC_GOLD_3, 0
    SK_RECT xc_wall_f, SKF_RIGHT, 0, 0, 1, 6, AC_GOLD_3, 0
    SK_FILL xc_wall_l, SKM_ALL, AC_GOLD_2, 0
    SK_BMP xc_wall_l, SKF_LEFT, 0, 0, xc_wall_side
    SK_BMP xc_wall_l, SKF_RIGHT, 0, 0, xc_wall_side
    SK_BMP xc_wall_l, SKF_TOP, 0, 0, xc_wall_side_top
    SK_RECT xc_wall_l, SKF_BOTTOM, 0, 0, 1, 16, AC_GOLD_4, 0
    SK_RECT xc_wall_l, SKF_FRONT, 0, 0, 1, 6, AC_GOLD_3, 0
    SK_RECT xc_wall_l, SKF_BACK, 0, 0, 1, 6, AC_GOLD_3, 0
    ; --- xc_gem_f (ruby) and xc_gem_l (sapphire): faceted, set in gold prongs
    SK_FILL xc_gem_f, SKM_ALL, AC_GOLD_3, 0
    SK_BMP xc_gem_f, SKF_FRONT, 0, 0, xc_gem_f_front
    SK_BMP xc_gem_f, SKF_BACK, 0, 0, xc_gem_f_back
    SK_FILL xc_gem_l, SKM_ALL, AC_GOLD_3, 0
    SK_BMP xc_gem_l, SKF_LEFT, 0, 0, xc_gem_l_left
    SK_BMP xc_gem_l, SKF_RIGHT, 0, 0, xc_gem_l_right
SKMODEL_END

; ===================================================================================================
; m_hood_villagers
; ===================================================================================================
RAMP HV_CLOTH, 90, 140, 60              ; the Villagers tunic green
RAMP HV_LINING, 60, 96, 44              ; deeper green lining

section .rodata
; The characters of every hv_ bitmap. Groups: base, highlight, shade, deep.
;   c C d D green cloth   t T u U deep green lining   y Y l brass pin   _ transparent
align 8
hv_pal:
    PALC 'c', HV_CLOTH_2
    PALC 'C', HV_CLOTH_1
    PALC 'd', HV_CLOTH_3
    PALC 'D', HV_CLOTH_4
    PALC 't', HV_LINING_2
    PALC 'T', HV_LINING_1
    PALC 'u', HV_LINING_3
    PALC 'U', HV_LINING_4
    PALC 'y', AC_GOLD_2
    PALC 'Y', AC_GOLD_1
    PALC 'l', AC_GOLD_3
    PALT '_'
    dq 0

    ; hv_shell_front (18x20): hv_shell FRONT
    SKROWS hv_shell_front_rows, 18, 20
    SKROW "CCCCCCCCCCCCCCCCCC"
    SKROW "C.Cd.Cd..........d"
    SKROW "C.Cd.Cd..........d"
    SKROW "C..dd.d...Cd.....d"
    SKROW "C.C____________..d"
    SKROW "C.C____________..d"
    SKROW "C..____________..d"
    SKROW "C.C____________..d"
    SKROW "C.C____________..d"
    SKROW "C..____________..d"
    SKROW "C..____________..d"
    SKROW "C..____________..d"
    SKROW "C.C____________..d"
    SKROW "C.C____________..d"
    SKROW "C..____________..d"
    SKROW "C..____________..d"
    SKROW "C..____________..d"
    SKROW "C................d"
    SKROW "dddddddddddddddddd"
    SKROW "DDDDDDDDDDDDDDDDDD"
    SKROWS_END
    align 8
    SKBMP hv_shell_front, hv_shell_front_rows, 18, 20, hv_pal
    ; hv_shell_back (18x20): hv_shell BACK
    SKROWS hv_shell_back_rows, 18, 20
    SKROW "CCCCCCCCCCCCCCCCCC"
    SKROW "C....dd.dC.d.....d"
    SKROW "C...Cdd.dCCd.....d"
    SKROW "C...Cdd.dCCd.....d"
    SKROW "C....dd.dC.dCd...d"
    SKROW "C...Cdd.dCCd.d...d"
    SKROW "C...Cdd.dCCdCd...d"
    SKROW "C....dd.dC.dCd...d"
    SKROW "C...Cdd.dCCd.d...d"
    SKROW "C...Cdd.dCCdCd...d"
    SKROW "C...dd..dCd.Cd...d"
    SKROW "C..Cdd..dCd..d...d"
    SKROW "C..Cdd..dCd.Cd...d"
    SKROW "C...dd..dCdCd....d"
    SKROW "C..Cdd..dCd......d"
    SKROW "C....d..dCd......d"
    SKROW "C...Cd..dC.......d"
    SKROW "C.......dC.......d"
    SKROW "dddddddddddddddddd"
    SKROW "DDDDDDDDDDDDDDDDDD"
    SKROWS_END
    align 8
    SKBMP hv_shell_back, hv_shell_back_rows, 18, 20, hv_pal
    ; hv_shell_side (18x20): hv_shell LEFT, hv_shell RIGHT
    SKROWS hv_shell_side_rows, 18, 20
    SKROW "CCCCCCCCCCCCCCCCCC"
    SKROW "C.....CdCd.......d"
    SKROW "C......dCd.Cd....d"
    SKROW "C...CdCd.d..d....d"
    SKROW "C....dCdCd.Cd.d..d"
    SKROW "C...Cd.dCd.CdCd..d"
    SKROW "C...Cd.Cd.d.dCd..d"
    SKROW "C....d.CdCdCd.d..d"
    SKROW "C....Cd.dCd.Cdd..d"
    SKROW "C....CdCd.d..dd..d"
    SKROW "C.....dCdCd.Cd.d.d"
    SKROW "C....Cd.dCd.CdCd.d"
    SKROW "C....CdCd.d..dCd.d"
    SKROW "C.....dCdCd.Cd...d"
    SKROW "C....Cd.dCd.Cd...d"
    SKROW "C....CdCd........d"
    SKROW "C.....d..........d"
    SKROW "C................d"
    SKROW "dddddddddddddddddd"
    SKROW "DDDDDDDDDDDDDDDDDD"
    SKROWS_END
    align 8
    SKBMP hv_shell_side, hv_shell_side_rows, 18, 20, hv_pal
    ; hv_shell_top (18x18): hv_shell TOP
    SKROWS hv_shell_top_rows, 18, 18
    SKROW "CCCCCCCCCCCCCCCCCC"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C..ddd..dC..ddd..d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C..ddd..dC..ddd..d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C..ddd..dC..ddd..d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "Cddddddddddddddddd"
    SKROWS_END
    align 8
    SKBMP hv_shell_top, hv_shell_top_rows, 18, 18, hv_pal
    ; hv_brow_front (16x3): hv_brow FRONT
    SKROWS hv_brow_front_rows, 16, 3
    SKROW "TTTTTTTTTTTTTTTu"
    SKROW "T.C...C...C...Cu"
    SKROW "Tuuuuuuuuuuuuuuu"
    SKROWS_END
    align 8
    SKBMP hv_brow_front, hv_brow_front_rows, 16, 3, hv_pal
    ; hv_cheek_front_left (2x12): hv_cheek_l FRONT
    SKROWS hv_cheek_front_left_rows, 2, 12
    SKROW "Tu"
    SKROW "Tu"
    SKROW "TC"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "TC"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "TC"
    SKROW "Tu"
    SKROWS_END
    align 8
    SKBMP hv_cheek_front_left, hv_cheek_front_left_rows, 2, 12, hv_pal
    ; hv_cheek_front_right (2x12): hv_cheek_r FRONT
    SKROWS hv_cheek_front_right_rows, 2, 12
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Cu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Cu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Cu"
    SKROW "Tu"
    SKROWS_END
    align 8
    SKBMP hv_cheek_front_right, hv_cheek_front_right_rows, 2, 12, hv_pal
    ; hv_chin_front (16x2): hv_chin FRONT
    SKROWS hv_chin_front_rows, 16, 2
    SKROW "TTCTTTCTTTCTTTCT"
    SKROW "uuuuuuuuuuuuuuuu"
    SKROWS_END
    align 8
    SKBMP hv_chin_front, hv_chin_front_rows, 16, 2, hv_pal
    ; hv_cap_front (14x2): hv_cap FRONT
    SKROWS hv_cap_front_rows, 14, 2
    SKROW "C............d"
    SKROW "dddddddddddddd"
    SKROWS_END
    align 8
    SKBMP hv_cap_front, hv_cap_front_rows, 14, 2, hv_pal
    ; hv_cap_back (14x2): hv_cap BACK
    SKROWS hv_cap_back_rows, 14, 2
    SKROW "C............d"
    SKROW "dddddddddddddd"
    SKROWS_END
    align 8
    SKBMP hv_cap_back, hv_cap_back_rows, 14, 2, hv_pal
    ; hv_cap_left (14x2): hv_cap LEFT
    SKROWS hv_cap_left_rows, 14, 2
    SKROW "C............d"
    SKROW "dddddddddddddd"
    SKROWS_END
    align 8
    SKBMP hv_cap_left, hv_cap_left_rows, 14, 2, hv_pal
    ; hv_cap_right (14x2): hv_cap RIGHT
    SKROWS hv_cap_right_rows, 14, 2
    SKROW "C............d"
    SKROW "dddddddddddddd"
    SKROWS_END
    align 8
    SKBMP hv_cap_right, hv_cap_right_rows, 14, 2, hv_pal
    ; hv_cap_top (14x14): hv_cap TOP
    SKROWS hv_cap_top_rows, 14, 14
    SKROW "CCCCCCCCCCCCCC"
    SKROW "C.....dC.....d"
    SKROW "C.....dC.....d"
    SKROW "C.....dC.....d"
    SKROW "C.....dC.....d"
    SKROW "C.....dC.....d"
    SKROW "C.....dC.....d"
    SKROW "C.....dC.....d"
    SKROW "C.....dC.....d"
    SKROW "C.....dC.....d"
    SKROW "C.....dC.....d"
    SKROW "C.....dC.....d"
    SKROW "C.....dC.....d"
    SKROW "Cddddddddddddd"
    SKROWS_END
    align 8
    SKBMP hv_cap_top, hv_cap_top_rows, 14, 14, hv_pal
    ; hv_tail_front (4x11): hv_tail FRONT
    SKROWS hv_tail_front_rows, 4, 11
    SKROW "C..d"
    SKROW "C.dd"
    SKROW "C.dd"
    SKROW "C.dd"
    SKROW "C.dd"
    SKROW "C.dd"
    SKROW "C.dd"
    SKROW "C.dd"
    SKROW "C.dd"
    SKROW "dddd"
    SKROW "DDDD"
    SKROWS_END
    align 8
    SKBMP hv_tail_front, hv_tail_front_rows, 4, 11, hv_pal
    ; hv_tail_back (4x11): hv_tail BACK
    SKROWS hv_tail_back_rows, 4, 11
    SKROW "C..d"
    SKROW "C.dd"
    SKROW "C.dd"
    SKROW "C.dd"
    SKROW "C.dd"
    SKROW "C.dd"
    SKROW "C.dd"
    SKROW "C.dd"
    SKROW "C.dd"
    SKROW "dddd"
    SKROW "DDDD"
    SKROWS_END
    align 8
    SKBMP hv_tail_back, hv_tail_back_rows, 4, 11, hv_pal
    ; hv_tail_left (2x11): hv_tail LEFT
    SKROWS hv_tail_left_rows, 2, 11
    SKROW "Cd"
    SKROW "Cd"
    SKROW "Cd"
    SKROW "Cd"
    SKROW "Cd"
    SKROW "Cd"
    SKROW "Cd"
    SKROW "Cd"
    SKROW "Cd"
    SKROW "dd"
    SKROW "DD"
    SKROWS_END
    align 8
    SKBMP hv_tail_left, hv_tail_left_rows, 2, 11, hv_pal
    ; hv_tail_right (2x11): hv_tail RIGHT
    SKROWS hv_tail_right_rows, 2, 11
    SKROW "Cd"
    SKROW "Cd"
    SKROW "Cd"
    SKROW "Cd"
    SKROW "Cd"
    SKROW "Cd"
    SKROW "Cd"
    SKROW "Cd"
    SKROW "Cd"
    SKROW "dd"
    SKROW "DD"
    SKROWS_END
    align 8
    SKBMP hv_tail_right, hv_tail_right_rows, 2, 11, hv_pal
    ; hv_pin_front (2x2): hv_pin FRONT
    SKROWS hv_pin_front_rows, 2, 2
    SKROW "Yy"
    SKROW "ly"
    SKROWS_END
    align 8
    SKBMP hv_pin_front, hv_pin_front_rows, 2, 2, hv_pal

section .data
SKMODEL_BEGIN m_hood_villagers, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART hv_shell, -9, 44, -9, 18, 20, 18, 3, SKPF_CUTOUT   ; hood shell with the face opening
    PART hv_brow, -8, 59, -11, 16, 3, 2, 7, 0               ; lip: brow
    PART hv_cheek_l, -8, 47, -11, 2, 12, 2, 3, 0            ; lip: left cheek
    PART hv_cheek_r, 6, 47, -11, 2, 12, 2, 3, 0             ; lip: right cheek
    PART hv_chin, -8, 45, -11, 16, 2, 2, 7, 0               ; lip: chin
    PART hv_cap, -7, 64, -7, 14, 2, 14, 3, 0                ; rounded crown of the hood
    PART hv_tail, -2, 51, 9, 4, 11, 2, 3, 0                 ; its tail down the back
    PART hv_pin, -1, 45, -12, 2, 2, 1, 3, 0                 ; brass leaf pin at the throat
SKMODEL_PAINT
    ; --- hv_shell: the shell; the face opening is a cutout (cols 3..14, rows 4..16 of the front image)
    SK_FILL hv_shell, SKM_ALL, HV_CLOTH_2, 15
    SK_BMP hv_shell, SKF_FRONT, 0, 0, hv_shell_front
    SK_BMP hv_shell, SKF_BACK, 0, 0, hv_shell_back
    SK_BMP hv_shell, SKF_LEFT, 0, 0, hv_shell_side
    SK_BMP hv_shell, SKF_RIGHT, 0, 0, hv_shell_side
    SK_BMP hv_shell, SKF_TOP, 0, 0, hv_shell_top
    SK_RECT hv_shell, SKF_BOTTOM, 0, 0, 18, 18, HV_CLOTH_4, 0
    SK_GRAD hv_shell, SKM_SIDES, 272, 224
    ; --- the lip: brow, cheeks and chin are bars, so the opening has real inner walls (darker lining)
    SK_FILL hv_brow, SKM_ALL, HV_LINING_2, 7
    SK_BMP hv_brow, SKF_FRONT, 0, 0, hv_brow_front
    SK_RECT hv_brow, SKF_BOTTOM, 0, 0, 16, 2, HV_LINING_4, 0
    SK_RECT hv_brow, SKF_TOP, 0, 0, 16, 2, HV_LINING_1, 7
    SK_RECT hv_brow, SKF_BACK, 0, 0, 16, 3, HV_LINING_4, 0
    SK_GRAD hv_brow, SKM_LEFT | SKM_RIGHT, 272, 224
    SK_FILL hv_cheek_l, SKM_ALL, HV_LINING_2, 7
    SK_BMP hv_cheek_l, SKF_FRONT, 0, 0, hv_cheek_front_left
    SK_RECT hv_cheek_l, SKF_RIGHT, 0, 0, 2, 12, HV_LINING_4, 0
    SK_RECT hv_cheek_l, SKF_LEFT, 0, 0, 2, 12, HV_LINING_3, 0
    SK_RECT hv_cheek_l, SKF_BACK, 0, 0, 2, 12, HV_LINING_4, 0
    SK_RECT hv_cheek_l, SKF_TOP, 0, 0, 2, 2, HV_LINING_1, 0
    SK_RECT hv_cheek_l, SKF_BOTTOM, 0, 0, 2, 2, HV_LINING_4, 0
    SK_FILL hv_cheek_r, SKM_ALL, HV_LINING_2, 7
    SK_BMP hv_cheek_r, SKF_FRONT, 0, 0, hv_cheek_front_right
    SK_RECT hv_cheek_r, SKF_LEFT, 0, 0, 2, 12, HV_LINING_4, 0
    SK_RECT hv_cheek_r, SKF_RIGHT, 0, 0, 2, 12, HV_LINING_3, 0
    SK_RECT hv_cheek_r, SKF_BACK, 0, 0, 2, 12, HV_LINING_4, 0
    SK_RECT hv_cheek_r, SKF_TOP, 0, 0, 2, 2, HV_LINING_1, 0
    SK_RECT hv_cheek_r, SKF_BOTTOM, 0, 0, 2, 2, HV_LINING_4, 0
    SK_FILL hv_chin, SKM_ALL, HV_LINING_2, 7
    SK_BMP hv_chin, SKF_FRONT, 0, 0, hv_chin_front
    SK_RECT hv_chin, SKF_TOP, 0, 0, 16, 2, HV_LINING_4, 0
    SK_RECT hv_chin, SKF_BOTTOM, 0, 0, 16, 2, HV_LINING_4, 0
    SK_RECT hv_chin, SKF_BACK, 0, 0, 16, 2, HV_LINING_4, 0
    SK_RECT hv_chin, SKF_LEFT, 0, 0, 2, 2, HV_LINING_3, 0
    SK_RECT hv_chin, SKF_RIGHT, 0, 0, 2, 2, HV_LINING_3, 0
    SK_FILL hv_cap, SKM_ALL, HV_CLOTH_2, 15
    SK_BMP hv_cap, SKF_FRONT, 0, 0, hv_cap_front
    SK_BMP hv_cap, SKF_BACK, 0, 0, hv_cap_back
    SK_BMP hv_cap, SKF_LEFT, 0, 0, hv_cap_left
    SK_BMP hv_cap, SKF_RIGHT, 0, 0, hv_cap_right
    SK_BMP hv_cap, SKF_TOP, 0, 0, hv_cap_top
    SK_RECT hv_cap, SKF_BOTTOM, 0, 0, 14, 14, HV_CLOTH_4, 0
    SK_GRAD hv_cap, SKM_SIDES, 272, 224
    SK_FILL hv_tail, SKM_ALL, HV_CLOTH_2, 15
    SK_BMP hv_tail, SKF_FRONT, 0, 0, hv_tail_front
    SK_BMP hv_tail, SKF_BACK, 0, 0, hv_tail_back
    SK_BMP hv_tail, SKF_LEFT, 0, 0, hv_tail_left
    SK_BMP hv_tail, SKF_RIGHT, 0, 0, hv_tail_right
    SK_RECT hv_tail, SKF_TOP, 0, 0, 4, 2, HV_CLOTH_1, 15
    SK_RECT hv_tail, SKF_BOTTOM, 0, 0, 4, 2, HV_CLOTH_4, 0
    SK_GRAD hv_tail, SKM_SIDES, 272, 224
    SK_FILL hv_pin, SKM_ALL, AC_GOLD_3, 0
    SK_BMP hv_pin, SKF_FRONT, 0, 0, hv_pin_front
SKMODEL_END

; ===================================================================================================
; m_hood_bandits
; ===================================================================================================
RAMP HB_LEATHER, 80, 55, 35             ; dark leather
RAMP HB_CLOTH, 48, 44, 46               ; black cloth lining
RAMP HB_RED, 150, 30, 30                ; the bandana red

section .rodata
; The characters of every hb_ bitmap. Groups: base, highlight, shade, deep.
;   c C d D dark leather   t T u U black cloth lining   g G h H bandana red   i I o r iron   _ transparent
align 8
hb_pal:
    PALC 'c', HB_LEATHER_2
    PALC 'C', HB_LEATHER_1
    PALC 'd', HB_LEATHER_3
    PALC 'D', HB_LEATHER_4
    PALC 't', HB_CLOTH_2
    PALC 'T', HB_CLOTH_1
    PALC 'u', HB_CLOTH_3
    PALC 'U', HB_CLOTH_4
    PALC 'g', HB_RED_2
    PALC 'G', HB_RED_1
    PALC 'h', HB_RED_3
    PALC 'H', HB_RED_4
    PALC 'i', AC_IRON_2
    PALC 'I', AC_IRON_1
    PALC 'o', AC_IRON_3
    PALC 'r', RGBO(112, 116, 126)
    PALT '_'
    dq 0

    ; hb_shell_front (18x20): hb_shell FRONT
    SKROWS hb_shell_front_rows, 18, 20
    SKROW "CCCCCCCCCCCCCCCCCC"
    SKROW "C...........Cd...d"
    SKROW "CCrd..r...r..dr..d"
    SKROW "CCDd..D...D.CdDd.d"
    SKROW "C.d____________d.d"
    SKROW "CCd____________d.d"
    SKROW "CCd____________d.d"
    SKROW "C.d____________d.d"
    SKROW "CCd____________d.d"
    SKROW "CCd____________d.d"
    SKROW "C.d____________d.d"
    SKROW "CCd____________d.d"
    SKROW "C.d____________.dd"
    SKROW "CCd____________Cdd"
    SKROW "C.C____________Cdd"
    SKROW "C.C____________..d"
    SKROW "C..____________..d"
    SKROW "C................d"
    SKROW "dddddddddddddddddd"
    SKROW "DDDDDDDDDDDDDDDDDD"
    SKROWS_END
    align 8
    SKBMP hb_shell_front, hb_shell_front_rows, 18, 20, hb_pal
    ; hb_shell_back (18x20): hb_shell BACK
    SKROWS hb_shell_back_rows, 18, 20
    SKROW "CCCCCCCCCCCCCCCCCC"
    SKROW "C.d.....dC.......d"
    SKROW "CCr...r.dCr...rd.d"
    SKROW "CCD...D.dCD...Dd.d"
    SKROW "C.d..Cd.dCd...Cd.d"
    SKROW "CCd..Cd.dCd...Cd.d"
    SKROW "CCd...d.dCd....d.d"
    SKROW "C.d..Cd.dCd...Cd.d"
    SKROW "CCd..Cd.dCd...Cd.d"
    SKROW "CCd...d.dCd....d.d"
    SKROW "C..d.Cd.dCd...Cd.d"
    SKROW "C.Cd.CdCdC...Cd..d"
    SKROW "C.Cd...ddC....d..d"
    SKROW "C..d..CddC...Cd..d"
    SKROW "C.Cd....dC...Cd..d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "dddddddddddddddddd"
    SKROW "DDDDDDDDDDDDDDDDDD"
    SKROWS_END
    align 8
    SKBMP hb_shell_back, hb_shell_back_rows, 18, 20, hb_pal
    ; hb_shell_side (18x20): hb_shell LEFT, hb_shell RIGHT
    SKROWS hb_shell_side_rows, 18, 20
    SKROW "CCCCCCCCCCCCCCCCCC"
    SKROW "C................d"
    SKROW "C.r.d.r...r...r..d"
    SKROW "C.DCd.Dd.CD...D..d"
    SKROW "C..Cd.Cd.Cd.Cdd..d"
    SKROW "C...d..d..d..dd..d"
    SKROW "C..Cd.Cd.Cd.Cdd..d"
    SKROW "C..Cd.Cd.Cd.Cdd..d"
    SKROW "C....d..d.d..dd..d"
    SKROW "C...Cd.Cdd.CdCd..d"
    SKROW "C...Cd.Cdd.Cd..d.d"
    SKROW "C....d..dd..d.Cd.d"
    SKROW "C...Cd.Cdd.Cd.Cd.d"
    SKROW "C...Cd..Cd.Cd..d.d"
    SKROW "C.............Cd.d"
    SKROW "C................d"
    SKROW "C................d"
    SKROW "C................d"
    SKROW "dddddddddddddddddd"
    SKROW "DDDDDDDDDDDDDDDDDD"
    SKROWS_END
    align 8
    SKBMP hb_shell_side, hb_shell_side_rows, 18, 20, hb_pal
    ; hb_shell_top (18x18): hb_shell TOP
    SKROWS hb_shell_top_rows, 18, 18
    SKROW "CCCCCCCCCCCCCCCCCC"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C..ddd..dC..ddd..d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C..ddd..dC..ddd..d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C..ddd..dC..ddd..d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "Cddddddddddddddddd"
    SKROWS_END
    align 8
    SKBMP hb_shell_top, hb_shell_top_rows, 18, 18, hb_pal
    ; hb_brow_front (16x3): hb_brow FRONT
    SKROWS hb_brow_front_rows, 16, 3
    SKROW "TTTTTTTTTTTTTTTu"
    SKROW "T.h...h...h...hu"
    SKROW "Tuuuuuuuuuuuuuuu"
    SKROWS_END
    align 8
    SKBMP hb_brow_front, hb_brow_front_rows, 16, 3, hb_pal
    ; hb_cheek_front_left (2x12): hb_cheek_l FRONT
    SKROWS hb_cheek_front_left_rows, 2, 12
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Th"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Th"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Th"
    SKROW "Tu"
    SKROWS_END
    align 8
    SKBMP hb_cheek_front_left, hb_cheek_front_left_rows, 2, 12, hb_pal
    ; hb_cheek_front_right (2x12): hb_cheek_r FRONT
    SKROWS hb_cheek_front_right_rows, 2, 12
    SKROW "Tu"
    SKROW "Tu"
    SKROW "hu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "hu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "hu"
    SKROW "Tu"
    SKROWS_END
    align 8
    SKBMP hb_cheek_front_right, hb_cheek_front_right_rows, 2, 12, hb_pal
    ; hb_chin_front (16x2): hb_chin FRONT
    SKROWS hb_chin_front_rows, 16, 2
    SKROW "TThTTThTTThTTThT"
    SKROW "uuuuuuuuuuuuuuuu"
    SKROWS_END
    align 8
    SKBMP hb_chin_front, hb_chin_front_rows, 16, 2, hb_pal
    ; hb_cap_front (14x2): hb_cap FRONT
    SKROWS hb_cap_front_rows, 14, 2
    SKROW "C.r...r...r..d"
    SKROW "DDDDDDDDDDDDDD"
    SKROWS_END
    align 8
    SKBMP hb_cap_front, hb_cap_front_rows, 14, 2, hb_pal
    ; hb_cap_back (14x2): hb_cap BACK
    SKROWS hb_cap_back_rows, 14, 2
    SKROW "C.r...r...r..d"
    SKROW "DDDDDDDDDDDDDD"
    SKROWS_END
    align 8
    SKBMP hb_cap_back, hb_cap_back_rows, 14, 2, hb_pal
    ; hb_cap_left (14x2): hb_cap LEFT
    SKROWS hb_cap_left_rows, 14, 2
    SKROW "C.r...r...r..d"
    SKROW "DDDDDDDDDDDDDD"
    SKROWS_END
    align 8
    SKBMP hb_cap_left, hb_cap_left_rows, 14, 2, hb_pal
    ; hb_cap_right (14x2): hb_cap RIGHT
    SKROWS hb_cap_right_rows, 14, 2
    SKROW "C.r...r...r..d"
    SKROW "DDDDDDDDDDDDDD"
    SKROWS_END
    align 8
    SKBMP hb_cap_right, hb_cap_right_rows, 14, 2, hb_pal
    ; hb_cap_top (14x14): hb_cap TOP
    SKROWS hb_cap_top_rows, 14, 14
    SKROW "CCCCCCCCCCCCCC"
    SKROW "C......d.....d"
    SKROW "C......d.....d"
    SKROW "C..r...d..r..d"
    SKROW "C......d.....d"
    SKROW "C......d.....d"
    SKROW "C......d.....d"
    SKROW "C......d.....d"
    SKROW "C......d.....d"
    SKROW "C......d.....d"
    SKROW "C..r...d..r..d"
    SKROW "C......d.....d"
    SKROW "C......d.....d"
    SKROW "Cddddddddddddd"
    SKROWS_END
    align 8
    SKBMP hb_cap_top, hb_cap_top_rows, 14, 14, hb_pal
    ; hb_tail_front (4x12): hb_tail FRONT
    SKROWS hb_tail_front_rows, 4, 12
    SKROW "G..h"
    SKROW "G..h"
    SKROW "G..h"
    SKROW "G..h"
    SKROW "Gh.h"
    SKROW "G..h"
    SKROW "G..h"
    SKROW "G.hh"
    SKROW "G..h"
    SKROW "G..h"
    SKROW "_.._"
    SKROW "_h__"
    SKROWS_END
    align 8
    SKBMP hb_tail_front, hb_tail_front_rows, 4, 12, hb_pal
    ; hb_tail_back (4x12): hb_tail BACK
    SKROWS hb_tail_back_rows, 4, 12
    SKROW "h..G"
    SKROW "h..G"
    SKROW "h..G"
    SKROW "h..G"
    SKROW "h.hG"
    SKROW "h..G"
    SKROW "h..G"
    SKROW "hh.G"
    SKROW "h..G"
    SKROW "h..G"
    SKROW "_.._"
    SKROW "__h_"
    SKROWS_END
    align 8
    SKBMP hb_tail_back, hb_tail_back_rows, 4, 12, hb_pal
    ; hb_buckle_front (4x2): hb_buckle FRONT
    SKROWS hb_buckle_front_rows, 4, 2
    SKROW "IiiI"
    SKROW "ioDo"
    SKROWS_END
    align 8
    SKBMP hb_buckle_front, hb_buckle_front_rows, 4, 2, hb_pal

section .data
SKMODEL_BEGIN m_hood_bandits, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART hb_shell, -9, 44, -9, 18, 20, 18, 3, SKPF_CUTOUT   ; hood shell with the face opening
    PART hb_brow, -8, 59, -12, 16, 3, 3, 7, 0               ; lip: brow
    PART hb_cheek_l, -8, 47, -11, 2, 12, 2, 3, 0            ; lip: left cheek
    PART hb_cheek_r, 6, 47, -11, 2, 12, 2, 3, 0             ; lip: right cheek
    PART hb_chin, -8, 45, -11, 16, 2, 2, 7, 0               ; lip: chin
    PART hb_cap, -7, 64, -7, 14, 2, 14, 3, 0                ; flat leather crown
    PART hb_tail, -2, 46, 9, 4, 12, 1, 5, SKPF_CUTOUT       ; a red cloth tail down the back
    PART hb_buckle, -2, 45, -12, 4, 2, 1, 3, 0              ; iron buckle at the throat
SKMODEL_PAINT
    ; --- hb_shell: the shell; the face opening is a cutout (cols 3..14, rows 4..16 of the front image)
    SK_FILL hb_shell, SKM_ALL, HB_LEATHER_2, 15
    SK_BMP hb_shell, SKF_FRONT, 0, 0, hb_shell_front
    SK_BMP hb_shell, SKF_BACK, 0, 0, hb_shell_back
    SK_BMP hb_shell, SKF_LEFT, 0, 0, hb_shell_side
    SK_BMP hb_shell, SKF_RIGHT, 0, 0, hb_shell_side
    SK_BMP hb_shell, SKF_TOP, 0, 0, hb_shell_top
    SK_RECT hb_shell, SKF_BOTTOM, 0, 0, 18, 18, HB_LEATHER_4, 0
    SK_GRAD hb_shell, SKM_SIDES, 272, 224
    ; --- the lip: brow, cheeks and chin are bars, so the opening has real inner walls (darker lining)
    SK_FILL hb_brow, SKM_ALL, HB_CLOTH_2, 7
    SK_BMP hb_brow, SKF_FRONT, 0, 0, hb_brow_front
    SK_RECT hb_brow, SKF_BOTTOM, 0, 0, 16, 3, HB_CLOTH_4, 0
    SK_RECT hb_brow, SKF_TOP, 0, 0, 16, 3, HB_CLOTH_1, 7
    SK_RECT hb_brow, SKF_BACK, 0, 0, 16, 3, HB_CLOTH_4, 0
    SK_GRAD hb_brow, SKM_LEFT | SKM_RIGHT, 272, 224
    SK_FILL hb_cheek_l, SKM_ALL, HB_CLOTH_2, 7
    SK_BMP hb_cheek_l, SKF_FRONT, 0, 0, hb_cheek_front_left
    SK_RECT hb_cheek_l, SKF_RIGHT, 0, 0, 2, 12, HB_CLOTH_4, 0
    SK_RECT hb_cheek_l, SKF_LEFT, 0, 0, 2, 12, HB_CLOTH_3, 0
    SK_RECT hb_cheek_l, SKF_BACK, 0, 0, 2, 12, HB_CLOTH_4, 0
    SK_RECT hb_cheek_l, SKF_TOP, 0, 0, 2, 2, HB_CLOTH_1, 0
    SK_RECT hb_cheek_l, SKF_BOTTOM, 0, 0, 2, 2, HB_CLOTH_4, 0
    SK_FILL hb_cheek_r, SKM_ALL, HB_CLOTH_2, 7
    SK_BMP hb_cheek_r, SKF_FRONT, 0, 0, hb_cheek_front_right
    SK_RECT hb_cheek_r, SKF_LEFT, 0, 0, 2, 12, HB_CLOTH_4, 0
    SK_RECT hb_cheek_r, SKF_RIGHT, 0, 0, 2, 12, HB_CLOTH_3, 0
    SK_RECT hb_cheek_r, SKF_BACK, 0, 0, 2, 12, HB_CLOTH_4, 0
    SK_RECT hb_cheek_r, SKF_TOP, 0, 0, 2, 2, HB_CLOTH_1, 0
    SK_RECT hb_cheek_r, SKF_BOTTOM, 0, 0, 2, 2, HB_CLOTH_4, 0
    SK_FILL hb_chin, SKM_ALL, HB_CLOTH_2, 7
    SK_BMP hb_chin, SKF_FRONT, 0, 0, hb_chin_front
    SK_RECT hb_chin, SKF_TOP, 0, 0, 16, 2, HB_CLOTH_4, 0
    SK_RECT hb_chin, SKF_BOTTOM, 0, 0, 16, 2, HB_CLOTH_4, 0
    SK_RECT hb_chin, SKF_BACK, 0, 0, 16, 2, HB_CLOTH_4, 0
    SK_RECT hb_chin, SKF_LEFT, 0, 0, 2, 2, HB_CLOTH_3, 0
    SK_RECT hb_chin, SKF_RIGHT, 0, 0, 2, 2, HB_CLOTH_3, 0
    SK_FILL hb_cap, SKM_ALL, HB_LEATHER_2, 15
    SK_BMP hb_cap, SKF_FRONT, 0, 0, hb_cap_front
    SK_BMP hb_cap, SKF_BACK, 0, 0, hb_cap_back
    SK_BMP hb_cap, SKF_LEFT, 0, 0, hb_cap_left
    SK_BMP hb_cap, SKF_RIGHT, 0, 0, hb_cap_right
    SK_BMP hb_cap, SKF_TOP, 0, 0, hb_cap_top
    SK_RECT hb_cap, SKF_BOTTOM, 0, 0, 14, 14, HB_LEATHER_4, 0
    SK_GRAD hb_cap, SKM_SIDES, 272, 224
    SK_FILL hb_tail, SKM_ALL, HB_RED_2, 15
    SK_BMP hb_tail, SKF_FRONT, 0, 0, hb_tail_front
    SK_BMP hb_tail, SKF_BACK, 0, 0, hb_tail_back
    SK_RECT hb_tail, SKF_LEFT, 0, 0, 1, 12, HB_RED_3, 0
    SK_RECT hb_tail, SKF_RIGHT, 0, 0, 1, 12, HB_RED_3, 0
    SK_RECT hb_tail, SKF_TOP, 0, 0, 4, 1, HB_RED_1, 0
    SK_RECT hb_tail, SKF_BOTTOM, 0, 0, 4, 1, HB_RED_4, 0
    SK_FILL hb_buckle, SKM_ALL, AC_IRON_3, 0
    SK_BMP hb_buckle, SKF_FRONT, 0, 0, hb_buckle_front
SKMODEL_END

; ===================================================================================================
; m_hood_cult
; ===================================================================================================
RAMP HC_ASH, 74, 68, 74                 ; the ash hood
RAMP HC_RED, 120, 26, 38                ; crimson lining and trim

section .rodata
; The characters of every hc_ bitmap. Groups: base, highlight, shade, deep.
;   c C d D ash grey cloth   t T u U crimson lining and trim   y Y l gold   g G glowing rune   _ transparent
align 8
hc_pal:
    PALC 'c', HC_ASH_2
    PALC 'C', HC_ASH_1
    PALC 'd', HC_ASH_3
    PALC 'D', HC_ASH_4
    PALC 't', HC_RED_2
    PALC 'T', HC_RED_1
    PALC 'u', HC_RED_3
    PALC 'U', HC_RED_4
    PALC 'y', AC_GOLD_2
    PALC 'Y', AC_GOLD_1
    PALC 'l', AC_GOLD_3
    PALC 'g', RGBO(255, 60, 60)
    PALC 'G', RGBO(255, 190, 150)
    PALT '_'
    dq 0

    ; hc_shell_front (18x20): hc_shell FRONT
    SKROWS hc_shell_front_rows, 18, 20
    SKROW "CCCCCCCCCCCCCCCCCC"
    SKROW "C....d.....d.....d"
    SKROW "C...dd....Cd.....d"
    SKROW "C..Cdd...Cdd.....d"
    SKROW "C..____________..d"
    SKROW "C..____________..d"
    SKROW "C..____________..d"
    SKROW "C..____________..d"
    SKROW "C..____________..d"
    SKROW "C..____________..d"
    SKROW "C..____________..d"
    SKROW "C..____________..d"
    SKROW "C..____________..d"
    SKROW "C..____________..d"
    SKROW "C..____________..d"
    SKROW "C..____________..d"
    SKROW "C..____________..d"
    SKROW "tttttttttttttttttt"
    SKROW "dddddddddddddddddd"
    SKROW "DDDDDDDDDDDDDDDDDD"
    SKROWS_END
    align 8
    SKBMP hc_shell_front, hc_shell_front_rows, 18, 20, hc_pal
    ; hc_shell_back (18x20): hc_shell BACK
    SKROWS hc_shell_back_rows, 18, 20
    SKROW "CCCCCCCCCCCCCCCCCC"
    SKROW "C.......dC.......d"
    SKROW "C...Cd..dC.......d"
    SKROW "C...Cd.CdC.......d"
    SKROW "C..Cdd..dC.Cdd...d"
    SKROW "C...dd.CdC.Cdd...d"
    SKROW "C..Cdd.CdC..dd...d"
    SKROW "C..Cdd..dC.Cdd...d"
    SKROW "C...dd.CdC.Cdd...d"
    SKROW "C..Cdd.CdC..dd...d"
    SKROW "C..Cdd..dC.Cdd...d"
    SKROW "C..Cd..CdC.Cdd...d"
    SKROW "C..Cd...dC..dd...d"
    SKROW "C.Cd....dC...Cd..d"
    SKROW "C..d....dC.......d"
    SKROW "C.Cd....dC.......d"
    SKROW "C.Cd....dC.......d"
    SKROW "tttttttttttttttttt"
    SKROW "dddddddddddddddddd"
    SKROW "DDDDDDDDDDDDDDDDDD"
    SKROWS_END
    align 8
    SKBMP hc_shell_back, hc_shell_back_rows, 18, 20, hc_pal
    ; hc_shell_side (18x20): hc_shell LEFT, hc_shell RIGHT
    SKROWS hc_shell_side_rows, 18, 20
    SKROW "CCCCCCCCCCCCCCCCCC"
    SKROW "C................d"
    SKROW "C................d"
    SKROW "C..............d.d"
    SKROW "C.ddd.Cd......Cd.d"
    SKROW "CCddd..d......Cd.d"
    SKROW "CCddd.Cd.......d.d"
    SKROW "C.ddd.Cd......Cd.d"
    SKROW "CCddd..d.......Cdd"
    SKROW "CCdCdCd.........dd"
    SKROW "C..dddd........Cdd"
    SKROW "C.Cdddd........Cdd"
    SKROW "C.Cdddd.........dd"
    SKROW "C..dd..........Cdd"
    SKROW "C.Cdd..........Cdd"
    SKROW "C.Cd............dd"
    SKROW "C..............Cdd"
    SKROW "tttttttttttttttttt"
    SKROW "dddddddddddddddddd"
    SKROW "DDDDDDDDDDDDDDDDDD"
    SKROWS_END
    align 8
    SKBMP hc_shell_side, hc_shell_side_rows, 18, 20, hc_pal
    ; hc_shell_top (18x18): hc_shell TOP
    SKROWS hc_shell_top_rows, 18, 18
    SKROW "CCCCCCCCCCCCCCCCCC"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C..ddd..dC..ddd..d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C..ddd..dC..ddd..d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C..ddd..dC..ddd..d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "C.......dC.......d"
    SKROW "Cddddddddddddddddd"
    SKROWS_END
    align 8
    SKBMP hc_shell_top, hc_shell_top_rows, 18, 18, hc_pal
    ; hc_brow_front (16x3): hc_brow FRONT
    SKROWS hc_brow_front_rows, 16, 3
    SKROW "TTTTTTTTTTTTTTTu"
    SKROW "T..............u"
    SKROW "Tuuuuuuuuuuuuuuu"
    SKROWS_END
    align 8
    SKBMP hc_brow_front, hc_brow_front_rows, 16, 3, hc_pal
    ; hc_cheek_front_left (2x12): hc_cheek_l FRONT
    SKROWS hc_cheek_front_left_rows, 2, 12
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROWS_END
    align 8
    SKBMP hc_cheek_front_left, hc_cheek_front_left_rows, 2, 12, hc_pal
    ; hc_cheek_front_right (2x12): hc_cheek_r FRONT
    SKROWS hc_cheek_front_right_rows, 2, 12
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROWS_END
    align 8
    SKBMP hc_cheek_front_right, hc_cheek_front_right_rows, 2, 12, hc_pal
    ; hc_chin_front (16x2): hc_chin FRONT
    SKROWS hc_chin_front_rows, 16, 2
    SKROW "TTTTTTTTTTTTTTTT"
    SKROW "uuuuuuuuuuuuuuuu"
    SKROWS_END
    align 8
    SKBMP hc_chin_front, hc_chin_front_rows, 16, 2, hc_pal
    ; hc_peak_a_front (14x2): hc_peak_a FRONT
    SKROWS hc_peak_a_front_rows, 14, 2
    SKROW "C............d"
    SKROW "tttttttttttttt"
    SKROWS_END
    align 8
    SKBMP hc_peak_a_front, hc_peak_a_front_rows, 14, 2, hc_pal
    ; hc_peak_a_back (14x2): hc_peak_a BACK
    SKROWS hc_peak_a_back_rows, 14, 2
    SKROW "C............d"
    SKROW "tttttttttttttt"
    SKROWS_END
    align 8
    SKBMP hc_peak_a_back, hc_peak_a_back_rows, 14, 2, hc_pal
    ; hc_peak_a_left (14x2): hc_peak_a LEFT
    SKROWS hc_peak_a_left_rows, 14, 2
    SKROW "C............d"
    SKROW "tttttttttttttt"
    SKROWS_END
    align 8
    SKBMP hc_peak_a_left, hc_peak_a_left_rows, 14, 2, hc_pal
    ; hc_peak_a_right (14x2): hc_peak_a RIGHT
    SKROWS hc_peak_a_right_rows, 14, 2
    SKROW "C............d"
    SKROW "tttttttttttttt"
    SKROWS_END
    align 8
    SKBMP hc_peak_a_right, hc_peak_a_right_rows, 14, 2, hc_pal
    ; hc_peak_b_front (10x2): hc_peak_b FRONT
    SKROWS hc_peak_b_front_rows, 10, 2
    SKROW "C........d"
    SKROW "dddddddddd"
    SKROWS_END
    align 8
    SKBMP hc_peak_b_front, hc_peak_b_front_rows, 10, 2, hc_pal
    ; hc_peak_b_back (10x2): hc_peak_b BACK
    SKROWS hc_peak_b_back_rows, 10, 2
    SKROW "C........d"
    SKROW "dddddddddd"
    SKROWS_END
    align 8
    SKBMP hc_peak_b_back, hc_peak_b_back_rows, 10, 2, hc_pal
    ; hc_peak_b_left (10x2): hc_peak_b LEFT
    SKROWS hc_peak_b_left_rows, 10, 2
    SKROW "C........d"
    SKROW "dddddddddd"
    SKROWS_END
    align 8
    SKBMP hc_peak_b_left, hc_peak_b_left_rows, 10, 2, hc_pal
    ; hc_peak_b_right (10x2): hc_peak_b RIGHT
    SKROWS hc_peak_b_right_rows, 10, 2
    SKROW "C........d"
    SKROW "dddddddddd"
    SKROWS_END
    align 8
    SKBMP hc_peak_b_right, hc_peak_b_right_rows, 10, 2, hc_pal
    ; hc_peak_c_front (6x2): hc_peak_c FRONT
    SKROWS hc_peak_c_front_rows, 6, 2
    SKROW "C....d"
    SKROW "dddddd"
    SKROWS_END
    align 8
    SKBMP hc_peak_c_front, hc_peak_c_front_rows, 6, 2, hc_pal
    ; hc_peak_c_back (6x2): hc_peak_c BACK
    SKROWS hc_peak_c_back_rows, 6, 2
    SKROW "C....d"
    SKROW "dddddd"
    SKROWS_END
    align 8
    SKBMP hc_peak_c_back, hc_peak_c_back_rows, 6, 2, hc_pal
    ; hc_peak_c_left (6x2): hc_peak_c LEFT
    SKROWS hc_peak_c_left_rows, 6, 2
    SKROW "C....d"
    SKROW "dddddd"
    SKROWS_END
    align 8
    SKBMP hc_peak_c_left, hc_peak_c_left_rows, 6, 2, hc_pal
    ; hc_peak_c_right (6x2): hc_peak_c RIGHT
    SKROWS hc_peak_c_right_rows, 6, 2
    SKROW "C....d"
    SKROW "dddddd"
    SKROWS_END
    align 8
    SKBMP hc_peak_c_right, hc_peak_c_right_rows, 6, 2, hc_pal
    ; hc_peak_d_front (2x2): hc_peak_d FRONT
    SKROWS hc_peak_d_front_rows, 2, 2
    SKROW "Cd"
    SKROW "dd"
    SKROWS_END
    align 8
    SKBMP hc_peak_d_front, hc_peak_d_front_rows, 2, 2, hc_pal
    ; hc_peak_d_back (2x2): hc_peak_d BACK
    SKROWS hc_peak_d_back_rows, 2, 2
    SKROW "Cd"
    SKROW "dd"
    SKROWS_END
    align 8
    SKBMP hc_peak_d_back, hc_peak_d_back_rows, 2, 2, hc_pal
    ; hc_peak_d_left (2x2): hc_peak_d LEFT
    SKROWS hc_peak_d_left_rows, 2, 2
    SKROW "Cd"
    SKROW "dd"
    SKROWS_END
    align 8
    SKBMP hc_peak_d_left, hc_peak_d_left_rows, 2, 2, hc_pal
    ; hc_peak_d_right (2x2): hc_peak_d RIGHT
    SKROWS hc_peak_d_right_rows, 2, 2
    SKROW "Cd"
    SKROW "dd"
    SKROWS_END
    align 8
    SKBMP hc_peak_d_right, hc_peak_d_right_rows, 2, 2, hc_pal
    ; hc_rune_front (2x2): hc_rune FRONT
    SKROWS hc_rune_front_rows, 2, 2
    SKROW "gG"
    SKROW "gg"
    SKROWS_END
    align 8
    SKBMP hc_rune_front, hc_rune_front_rows, 2, 2, hc_pal

section .data
SKMODEL_BEGIN m_hood_cult, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART hc_peak_c, -3, 68, -3, 6, 2, 6, 3, 0               ; the pointed peak: peak_c
    PART hc_peak_b, -5, 66, -5, 10, 2, 10, 3, 0             ; the pointed peak: peak_b
    PART hc_cheek_l, -8, 47, -11, 2, 12, 2, 3, 0            ; lip: left cheek
    PART hc_cheek_r, 6, 47, -11, 2, 12, 2, 3, 0             ; lip: right cheek
    PART hc_shell, -9, 44, -9, 18, 20, 18, 3, SKPF_CUTOUT   ; hood shell with the face opening
    PART hc_peak_a, -7, 64, -7, 14, 2, 14, 3, 0             ; the pointed peak: peak_a
    PART hc_peak_d, -1, 70, -1, 2, 2, 2, 3, 0               ; the pointed peak: peak_d
    PART hc_brow, -8, 59, -11, 16, 3, 2, 7, 0               ; lip: brow
    PART hc_rune, -1, 60, -12, 2, 2, 1, 3, 0                ; a glowing rune on the brow
    PART hc_chin, -8, 45, -11, 16, 2, 2, 7, 0               ; lip: chin
SKMODEL_PAINT
    ; --- hc_shell: the shell; the face opening is a cutout (cols 3..14, rows 4..16 of the front image)
    SK_FILL hc_shell, SKM_ALL, HC_ASH_2, 15
    SK_BMP hc_shell, SKF_FRONT, 0, 0, hc_shell_front
    SK_BMP hc_shell, SKF_BACK, 0, 0, hc_shell_back
    SK_BMP hc_shell, SKF_LEFT, 0, 0, hc_shell_side
    SK_BMP hc_shell, SKF_RIGHT, 0, 0, hc_shell_side
    SK_BMP hc_shell, SKF_TOP, 0, 0, hc_shell_top
    SK_RECT hc_shell, SKF_BOTTOM, 0, 0, 18, 18, HC_ASH_4, 0
    SK_GRAD hc_shell, SKM_SIDES, 272, 224
    ; --- the lip: brow, cheeks and chin are bars, so the opening has real inner walls (darker lining)
    SK_FILL hc_brow, SKM_ALL, HC_RED_2, 7
    SK_BMP hc_brow, SKF_FRONT, 0, 0, hc_brow_front
    SK_RECT hc_brow, SKF_BOTTOM, 0, 0, 16, 2, HC_RED_4, 0
    SK_RECT hc_brow, SKF_TOP, 0, 0, 16, 2, HC_RED_1, 7
    SK_RECT hc_brow, SKF_BACK, 0, 0, 16, 3, HC_RED_4, 0
    SK_GRAD hc_brow, SKM_LEFT | SKM_RIGHT, 272, 224
    SK_FILL hc_cheek_l, SKM_ALL, HC_RED_2, 7
    SK_BMP hc_cheek_l, SKF_FRONT, 0, 0, hc_cheek_front_left
    SK_RECT hc_cheek_l, SKF_RIGHT, 0, 0, 2, 12, HC_RED_4, 0
    SK_RECT hc_cheek_l, SKF_LEFT, 0, 0, 2, 12, HC_RED_3, 0
    SK_RECT hc_cheek_l, SKF_BACK, 0, 0, 2, 12, HC_RED_4, 0
    SK_RECT hc_cheek_l, SKF_TOP, 0, 0, 2, 2, HC_RED_1, 0
    SK_RECT hc_cheek_l, SKF_BOTTOM, 0, 0, 2, 2, HC_RED_4, 0
    SK_FILL hc_cheek_r, SKM_ALL, HC_RED_2, 7
    SK_BMP hc_cheek_r, SKF_FRONT, 0, 0, hc_cheek_front_right
    SK_RECT hc_cheek_r, SKF_LEFT, 0, 0, 2, 12, HC_RED_4, 0
    SK_RECT hc_cheek_r, SKF_RIGHT, 0, 0, 2, 12, HC_RED_3, 0
    SK_RECT hc_cheek_r, SKF_BACK, 0, 0, 2, 12, HC_RED_4, 0
    SK_RECT hc_cheek_r, SKF_TOP, 0, 0, 2, 2, HC_RED_1, 0
    SK_RECT hc_cheek_r, SKF_BOTTOM, 0, 0, 2, 2, HC_RED_4, 0
    SK_FILL hc_chin, SKM_ALL, HC_RED_2, 7
    SK_BMP hc_chin, SKF_FRONT, 0, 0, hc_chin_front
    SK_RECT hc_chin, SKF_TOP, 0, 0, 16, 2, HC_RED_4, 0
    SK_RECT hc_chin, SKF_BOTTOM, 0, 0, 16, 2, HC_RED_4, 0
    SK_RECT hc_chin, SKF_BACK, 0, 0, 16, 2, HC_RED_4, 0
    SK_RECT hc_chin, SKF_LEFT, 0, 0, 2, 2, HC_RED_3, 0
    SK_RECT hc_chin, SKF_RIGHT, 0, 0, 2, 2, HC_RED_3, 0
    SK_FILL hc_peak_a, SKM_ALL, HC_ASH_2, 15
    SK_BMP hc_peak_a, SKF_FRONT, 0, 0, hc_peak_a_front
    SK_BMP hc_peak_a, SKF_BACK, 0, 0, hc_peak_a_back
    SK_BMP hc_peak_a, SKF_LEFT, 0, 0, hc_peak_a_left
    SK_BMP hc_peak_a, SKF_RIGHT, 0, 0, hc_peak_a_right
    SK_RECT hc_peak_a, SKF_TOP, 0, 0, 14, 14, HC_ASH_1, 15
    SK_RECT hc_peak_a, SKF_BOTTOM, 0, 0, 14, 14, HC_ASH_4, 0
    SK_GRAD hc_peak_a, SKM_SIDES, 272, 224
    SK_FILL hc_peak_b, SKM_ALL, HC_ASH_2, 15
    SK_BMP hc_peak_b, SKF_FRONT, 0, 0, hc_peak_b_front
    SK_BMP hc_peak_b, SKF_BACK, 0, 0, hc_peak_b_back
    SK_BMP hc_peak_b, SKF_LEFT, 0, 0, hc_peak_b_left
    SK_BMP hc_peak_b, SKF_RIGHT, 0, 0, hc_peak_b_right
    SK_RECT hc_peak_b, SKF_TOP, 0, 0, 10, 10, HC_ASH_1, 15
    SK_RECT hc_peak_b, SKF_BOTTOM, 0, 0, 10, 10, HC_ASH_4, 0
    SK_GRAD hc_peak_b, SKM_SIDES, 272, 224
    SK_FILL hc_peak_c, SKM_ALL, HC_ASH_2, 15
    SK_BMP hc_peak_c, SKF_FRONT, 0, 0, hc_peak_c_front
    SK_BMP hc_peak_c, SKF_BACK, 0, 0, hc_peak_c_back
    SK_BMP hc_peak_c, SKF_LEFT, 0, 0, hc_peak_c_left
    SK_BMP hc_peak_c, SKF_RIGHT, 0, 0, hc_peak_c_right
    SK_RECT hc_peak_c, SKF_TOP, 0, 0, 6, 6, HC_ASH_1, 15
    SK_RECT hc_peak_c, SKF_BOTTOM, 0, 0, 6, 6, HC_ASH_4, 0
    SK_GRAD hc_peak_c, SKM_SIDES, 272, 224
    SK_FILL hc_peak_d, SKM_ALL, HC_ASH_2, 15
    SK_BMP hc_peak_d, SKF_FRONT, 0, 0, hc_peak_d_front
    SK_BMP hc_peak_d, SKF_BACK, 0, 0, hc_peak_d_back
    SK_BMP hc_peak_d, SKF_LEFT, 0, 0, hc_peak_d_left
    SK_BMP hc_peak_d, SKF_RIGHT, 0, 0, hc_peak_d_right
    SK_RECT hc_peak_d, SKF_TOP, 0, 0, 2, 2, HC_ASH_1, 15
    SK_RECT hc_peak_d, SKF_BOTTOM, 0, 0, 2, 2, HC_ASH_4, 0
    SK_GRAD hc_peak_d, SKM_SIDES, 272, 224
    SK_FILL hc_rune, SKM_ALL, AC_GOLD_3, 0
    SK_BMP hc_rune, SKF_FRONT, 0, 0, hc_rune_front
SKMODEL_END

; ===================================================================================================
; m_hood_beastfolk
; ===================================================================================================
RAMP HF_FUR, 150, 130, 100              ; the Beastfolk fur
RAMP HF_PELT, 205, 188, 150             ; pale pelt lining

section .rodata
; The characters of every hf_ bitmap. Groups: base, highlight, shade, deep.
;   c C d D brown-grey fur   t T u U pale pelt lip   w b k bone (AC)   _ transparent
align 8
hf_pal:
    PALC 'c', HF_FUR_2
    PALC 'C', HF_FUR_1
    PALC 'd', HF_FUR_3
    PALC 'D', HF_FUR_4
    PALC 't', HF_PELT_2
    PALC 'T', HF_PELT_1
    PALC 'u', HF_PELT_3
    PALC 'U', HF_PELT_4
    PALC 'w', AC_BONE_1
    PALC 'b', AC_BONE_2
    PALC 'k', AC_BONE_3
    PALT '_'
    dq 0

    ; hf_shell_front (18x20): hf_shell FRONT
    SKROWS hf_shell_front_rows, 18, 20
    SKROW ".................."
    SKROW ".C................"
    SKROW ".C.......dd.....C."
    SKROW ".C.......dd....dC."
    SKROW ".C.____________dC."
    SKROW ".C.____________dC."
    SKROW ".C.____________dC."
    SKROW ".C.____________dC."
    SKROW ".C.____________dC."
    SKROW ".C.____________dC."
    SKROW ".C.____________dC."
    SKROW ".C.____________dC."
    SKROW ".C.____________dC."
    SKROW ".C.____________dC."
    SKROW ".C.____________dC."
    SKROW ".C.____________dC."
    SKROW ".C.____________dC."
    SKROW ".C........._._.dC."
    SKROW ".d.._._...__._..d."
    SKROW "___D____________DD"
    SKROWS_END
    align 8
    SKBMP hf_shell_front, hf_shell_front_rows, 18, 20, hf_pal
    ; hf_shell_back (18x20): hf_shell BACK
    SKROWS hf_shell_back_rows, 18, 20
    SKROW "............d..C.."
    SKROW "dd........CCd.dCdd"
    SKROW "dd........CCdCdCdd"
    SKROW "dd........CCdCdCdd"
    SKROW "dd........CCdCdCdd"
    SKROW "dd.....C..CCdCdCdd"
    SKROW "dd.....C..CCdCdCdd"
    SKROW "dd.....C..CCdCdCdd"
    SKROW "dd.....C..CCdCdCdd"
    SKROW "dd.....C..CCdCdCdd"
    SKROW "dd.....C..CCdCdCdd"
    SKROW "dd.....C..CCdCdCdd"
    SKROW "dd.....C..CCdCdCdd"
    SKROW "dd.....C..CCdCdCdd"
    SKROW "dd.....C..CCdCdCdd"
    SKROW "dd.....d..CCdCdC.."
    SKROW "dd........dd.d.C.."
    SKROW "_._._...._.....C.."
    SKROW "_.___...._._._.d__"
    SKROW "_D_____DD_________"
    SKROWS_END
    align 8
    SKBMP hf_shell_back, hf_shell_back_rows, 18, 20, hf_pal
    ; hf_shell_side (18x20): hf_shell LEFT, hf_shell RIGHT
    SKROWS hf_shell_side_rows, 18, 20
    SKROW ".....C..d........."
    SKROW ".dC..C..d........."
    SKROW ".dCd.C..d........."
    SKROW ".dCddC..d........."
    SKROW ".dCddC..d........."
    SKROW ".dCddC..d.......CC"
    SKROW ".dCddC..d.......CC"
    SKROW ".dCddC..d.......CC"
    SKROW ".dCddC..d.......CC"
    SKROW ".dCddC..d.......CC"
    SKROW ".dCddC..d.......CC"
    SKROW ".dCddC..d.......CC"
    SKROW ".dCddC..d.......CC"
    SKROW ".dCddC..d.......CC"
    SKROW ".dCddC..d.......CC"
    SKROW ".dCddC..d.......CC"
    SKROW "..Cddd..........CC"
    SKROW "._Cd..._........_d"
    SKROW "__d..._____....._."
    SKROW "____D_______D__D__"
    SKROWS_END
    align 8
    SKBMP hf_shell_side, hf_shell_side_rows, 18, 20, hf_pal
    ; hf_shell_top (18x18): hf_shell TOP
    SKROWS hf_shell_top_rows, 18, 18
    SKROW ".dd...........C..."
    SKROW ".dd...........C..."
    SKROW ".dd......CC...C..."
    SKROW "ddd..CC..CCdd.C..."
    SKROW "ddd..CC.dCCdd.C..."
    SKROW "ddd..CCCdCCdd.C..C"
    SKROW "ddd..CCCdCCdd.C..C"
    SKROW "ddd..CCCdCCdd.C..C"
    SKROW "ddd..CCCdCCdd.C..C"
    SKROW "ddd..CCCdCCdd.C..C"
    SKROW "ddd..CCCdCCdd.C..C"
    SKROW "ddd..CCCdCCdd.C..C"
    SKROW "ddd..CCddCCdd.C..C"
    SKROW "ddd..CC.dCCdd.C..d"
    SKROW ".dd..CC.dCC...C..."
    SKROW ".dd.._C..CC...C_.."
    SKROW "..__._d..dd._.d_.."
    SKROW "____D___________D_"
    SKROWS_END
    align 8
    SKBMP hf_shell_top, hf_shell_top_rows, 18, 18, hf_pal
    ; hf_brow_front (16x3): hf_brow FRONT
    SKROWS hf_brow_front_rows, 16, 3
    SKROW "TTTTTTTTTTTTTTTu"
    SKROW "T..............u"
    SKROW "Tuuuuuuuuuuuuuuu"
    SKROWS_END
    align 8
    SKBMP hf_brow_front, hf_brow_front_rows, 16, 3, hf_pal
    ; hf_cheek_front_left (2x12): hf_cheek_l FRONT
    SKROWS hf_cheek_front_left_rows, 2, 12
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROWS_END
    align 8
    SKBMP hf_cheek_front_left, hf_cheek_front_left_rows, 2, 12, hf_pal
    ; hf_cheek_front_right (2x12): hf_cheek_r FRONT
    SKROWS hf_cheek_front_right_rows, 2, 12
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROWS_END
    align 8
    SKBMP hf_cheek_front_right, hf_cheek_front_right_rows, 2, 12, hf_pal
    ; hf_chin_front (16x2): hf_chin FRONT
    SKROWS hf_chin_front_rows, 16, 2
    SKROW "TTTTTTTTTTTTTTTT"
    SKROW "uuuuuuuuuuuuuuuu"
    SKROWS_END
    align 8
    SKBMP hf_chin_front, hf_chin_front_rows, 16, 2, hf_pal
    ; hf_mane_front (4x2): hf_mane FRONT
    SKROWS hf_mane_front_rows, 4, 2
    SKROW "...."
    SKROW "...."
    SKROWS_END
    align 8
    SKBMP hf_mane_front, hf_mane_front_rows, 4, 2, hf_pal
    ; hf_mane_back (4x2): hf_mane BACK
    SKROWS hf_mane_back_rows, 4, 2
    SKROW "...."
    SKROW "...."
    SKROWS_END
    align 8
    SKBMP hf_mane_back, hf_mane_back_rows, 4, 2, hf_pal
    ; hf_mane_left (12x2): hf_mane LEFT
    SKROWS hf_mane_left_rows, 12, 2
    SKROW "....C......."
    SKROW "....C......."
    SKROWS_END
    align 8
    SKBMP hf_mane_left, hf_mane_left_rows, 12, 2, hf_pal
    ; hf_mane_right (12x2): hf_mane RIGHT
    SKROWS hf_mane_right_rows, 12, 2
    SKROW "......D....."
    SKROW "............"
    SKROWS_END
    align 8
    SKBMP hf_mane_right, hf_mane_right_rows, 12, 2, hf_pal
    ; hf_tooth_front (2x4): hf_tooth FRONT
    SKROWS hf_tooth_front_rows, 2, 4
    SKROW "wb"
    SKROW "wb"
    SKROW "bk"
    SKROW "_k"
    SKROWS_END
    align 8
    SKBMP hf_tooth_front, hf_tooth_front_rows, 2, 4, hf_pal
    ; hf_tooth_back (2x4): hf_tooth BACK
    SKROWS hf_tooth_back_rows, 2, 4
    SKROW "bk"
    SKROW "bk"
    SKROW "kk"
    SKROW "_k"
    SKROWS_END
    align 8
    SKBMP hf_tooth_back, hf_tooth_back_rows, 2, 4, hf_pal

section .data
SKMODEL_BEGIN m_hood_beastfolk, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART hf_shell, -9, 44, -9, 18, 20, 18, 3, SKPF_CUTOUT   ; hood shell with the face opening
    PART hf_brow, -8, 59, -11, 16, 3, 2, 7, 0               ; lip: brow
    PART hf_cheek_l, -8, 47, -11, 2, 12, 2, 3, 0            ; lip: left cheek
    PART hf_cheek_r, 6, 47, -11, 2, 12, 2, 3, 0             ; lip: right cheek
    PART hf_chin, -8, 45, -11, 16, 2, 2, 7, 0               ; lip: chin
    PART hf_mane, -2, 64, -8, 4, 2, 12, 3, 0                ; a fur ridge along the crown
    PART hf_tooth, -1, 42, -12, 2, 4, 1, 3, SKPF_CUTOUT     ; a bone fang on the chin lip
SKMODEL_PAINT
    ; --- hf_shell: the shell; the face opening is a cutout (cols 3..14, rows 4..16 of the front image)
    SK_FILL hf_shell, SKM_ALL, HF_FUR_2, 31
    SK_BMP hf_shell, SKF_FRONT, 0, 0, hf_shell_front
    SK_BMP hf_shell, SKF_BACK, 0, 0, hf_shell_back
    SK_BMP hf_shell, SKF_LEFT, 0, 0, hf_shell_side
    SK_BMP hf_shell, SKF_RIGHT, 0, 0, hf_shell_side
    SK_BMP hf_shell, SKF_TOP, 0, 0, hf_shell_top
    SK_RECT hf_shell, SKF_BOTTOM, 0, 0, 18, 18, HF_FUR_4, 0
    SK_GRAD hf_shell, SKM_SIDES, 272, 224
    ; --- the lip: brow, cheeks and chin are bars, so the opening has real inner walls (darker lining)
    SK_FILL hf_brow, SKM_ALL, HF_PELT_2, 7
    SK_BMP hf_brow, SKF_FRONT, 0, 0, hf_brow_front
    SK_RECT hf_brow, SKF_BOTTOM, 0, 0, 16, 2, HF_PELT_4, 0
    SK_RECT hf_brow, SKF_TOP, 0, 0, 16, 2, HF_PELT_1, 7
    SK_RECT hf_brow, SKF_BACK, 0, 0, 16, 3, HF_PELT_4, 0
    SK_GRAD hf_brow, SKM_LEFT | SKM_RIGHT, 272, 224
    SK_FILL hf_cheek_l, SKM_ALL, HF_PELT_2, 7
    SK_BMP hf_cheek_l, SKF_FRONT, 0, 0, hf_cheek_front_left
    SK_RECT hf_cheek_l, SKF_RIGHT, 0, 0, 2, 12, HF_PELT_4, 0
    SK_RECT hf_cheek_l, SKF_LEFT, 0, 0, 2, 12, HF_PELT_3, 0
    SK_RECT hf_cheek_l, SKF_BACK, 0, 0, 2, 12, HF_PELT_4, 0
    SK_RECT hf_cheek_l, SKF_TOP, 0, 0, 2, 2, HF_PELT_1, 0
    SK_RECT hf_cheek_l, SKF_BOTTOM, 0, 0, 2, 2, HF_PELT_4, 0
    SK_FILL hf_cheek_r, SKM_ALL, HF_PELT_2, 7
    SK_BMP hf_cheek_r, SKF_FRONT, 0, 0, hf_cheek_front_right
    SK_RECT hf_cheek_r, SKF_LEFT, 0, 0, 2, 12, HF_PELT_4, 0
    SK_RECT hf_cheek_r, SKF_RIGHT, 0, 0, 2, 12, HF_PELT_3, 0
    SK_RECT hf_cheek_r, SKF_BACK, 0, 0, 2, 12, HF_PELT_4, 0
    SK_RECT hf_cheek_r, SKF_TOP, 0, 0, 2, 2, HF_PELT_1, 0
    SK_RECT hf_cheek_r, SKF_BOTTOM, 0, 0, 2, 2, HF_PELT_4, 0
    SK_FILL hf_chin, SKM_ALL, HF_PELT_2, 7
    SK_BMP hf_chin, SKF_FRONT, 0, 0, hf_chin_front
    SK_RECT hf_chin, SKF_TOP, 0, 0, 16, 2, HF_PELT_4, 0
    SK_RECT hf_chin, SKF_BOTTOM, 0, 0, 16, 2, HF_PELT_4, 0
    SK_RECT hf_chin, SKF_BACK, 0, 0, 16, 2, HF_PELT_4, 0
    SK_RECT hf_chin, SKF_LEFT, 0, 0, 2, 2, HF_PELT_3, 0
    SK_RECT hf_chin, SKF_RIGHT, 0, 0, 2, 2, HF_PELT_3, 0
    SK_FILL hf_mane, SKM_ALL, HF_FUR_3, 31
    SK_BMP hf_mane, SKF_FRONT, 0, 0, hf_mane_front
    SK_BMP hf_mane, SKF_BACK, 0, 0, hf_mane_back
    SK_BMP hf_mane, SKF_LEFT, 0, 0, hf_mane_left
    SK_BMP hf_mane, SKF_RIGHT, 0, 0, hf_mane_right
    SK_RECT hf_mane, SKF_TOP, 0, 0, 4, 12, HF_FUR_1, 31
    SK_RECT hf_mane, SKF_BOTTOM, 0, 0, 4, 12, HF_FUR_4, 0
    SK_FILL hf_tooth, SKM_ALL, AC_BONE_2, 0
    SK_BMP hf_tooth, SKF_FRONT, 0, 0, hf_tooth_front
    SK_BMP hf_tooth, SKF_BACK, 0, 0, hf_tooth_back
SKMODEL_END

; ===================================================================================================
; m_hood_stonekin
; ===================================================================================================
RAMP HS_MAIL, 140, 140, 150             ; chain grey
RAMP HS_LEATHER, 80, 60, 45             ; dark brown leather

section .rodata
; The characters of every hs_ bitmap. Groups: base, highlight, shade, deep.
;   c C d D chain mail   t T u U leather binding   i I o O r iron plate and rivets   _ transparent
align 8
hs_pal:
    PALC 'c', HS_MAIL_2
    PALC 'C', HS_MAIL_1
    PALC 'd', HS_MAIL_3
    PALC 'D', HS_MAIL_4
    PALC 't', HS_LEATHER_2
    PALC 'T', HS_LEATHER_1
    PALC 'u', HS_LEATHER_3
    PALC 'U', HS_LEATHER_4
    PALC 'i', AC_IRON_2
    PALC 'I', AC_IRON_1
    PALC 'o', AC_IRON_3
    PALC 'O', AC_IRON_4
    PALC 'r', RGBO(112, 116, 126)
    PALT '_'
    dq 0

    ; hs_shell_front (18x20): hs_shell FRONT
    SKROWS hs_shell_front_rows, 18, 20
    SKROW "CCddCCddCCddCCddCC"
    SKROW "ccDDccDDccDDccDDcc"
    SKROW "ddCCddCCddCCddCCdd"
    SKROW "DDccDDccDDccDDccDD"
    SKROW "CCd____________dCC"
    SKROW "ccD____________Dcc"
    SKROW "ddC____________Cdd"
    SKROW "DDc____________cDD"
    SKROW "CCd____________dCC"
    SKROW "ccD____________Dcc"
    SKROW "ddC____________Cdd"
    SKROW "DDc____________cDD"
    SKROW "CCd____________dCC"
    SKROW "ccD____________Dcc"
    SKROW "ddC____________Cdd"
    SKROW "DDc____________cDD"
    SKROW "CCd____________dCC"
    SKROW "ccDDccDDccDDccDDcc"
    SKROW "dddddddddddddddddd"
    SKROW "DDDDDDDDDDDDDDDDDD"
    SKROWS_END
    align 8
    SKBMP hs_shell_front, hs_shell_front_rows, 18, 20, hs_pal
    ; hs_shell_back (18x20): hs_shell BACK
    SKROWS hs_shell_back_rows, 18, 20
    SKROW "CddCCddCDddCCddCCd"
    SKROW "cDDccDDcDdDccDDccD"
    SKROW "dCCddCCdDdCddCCddC"
    SKROW "DccDDccDDdcDDccDDc"
    SKROW "CddCCddCDddCCddCCd"
    SKROW "cDDccDDcDdDccDDccD"
    SKROW "dCCddCCdDdCddCCddC"
    SKROW "DccDDccDDdcDDccDDc"
    SKROW "CddCCddCDddCCddCCd"
    SKROW "cDDccDDcDdDccDDccD"
    SKROW "dCCddCCdDdCddCCddC"
    SKROW "DccDDccDDdcDDccDDc"
    SKROW "CddCCddCDddCCddCCd"
    SKROW "cDDccDDcDdDccDDccD"
    SKROW "dCCddCCdDdCddCCddC"
    SKROW "DccDDccDDdcDDccDDc"
    SKROW "CddCCddCDddCCddCCd"
    SKROW "cDDccDDcDdDccDDccD"
    SKROW "dddddddddddddddddd"
    SKROW "DDDDDDDDDDDDDDDDDD"
    SKROWS_END
    align 8
    SKBMP hs_shell_back, hs_shell_back_rows, 18, 20, hs_pal
    ; hs_shell_side (18x20): hs_shell LEFT, hs_shell RIGHT
    SKROWS hs_shell_side_rows, 18, 20
    SKROW "ddCCddCCddCCddCCdd"
    SKROW "DDccDDccDDccDDccDD"
    SKROW "CCddCCddCCddCCddCC"
    SKROW "ccDDccDDccDDccDDcc"
    SKROW "ddCCddCCddCCddCCdd"
    SKROW "DDccDDccDDccDDccDD"
    SKROW "CCddCCddCCddCCddCC"
    SKROW "ccDDccDDccDDccDDcc"
    SKROW "ddCCddCCddCCddCCdd"
    SKROW "DDccDDccDDccDDccDD"
    SKROW "CCddCCddCCddCCddCC"
    SKROW "ccDDccDDccDDccDDcc"
    SKROW "ddCCddCCddCCddCCdd"
    SKROW "DDccDDccDDccDDccDD"
    SKROW "CCddCCddCCddCCddCC"
    SKROW "ccDDccDDccDDccDDcc"
    SKROW "ddCCddCCddCCddCCdd"
    SKROW "DDccDDccDDccDDccDD"
    SKROW "dddddddddddddddddd"
    SKROW "DDDDDDDDDDDDDDDDDD"
    SKROWS_END
    align 8
    SKBMP hs_shell_side, hs_shell_side_rows, 18, 20, hs_pal
    ; hs_shell_top (18x18): hs_shell TOP
    SKROWS hs_shell_top_rows, 18, 18
    SKROW "dCCddCCddCCddCCddC"
    SKROW "DccDDccDDccDDccDDc"
    SKROW "CddCCddCCddCCddCCd"
    SKROW "cDDccDDccDDccDDccD"
    SKROW "dCCddCCddCCddCCddC"
    SKROW "DccDDccDDccDDccDDc"
    SKROW "CddCCddCCddCCddCCd"
    SKROW "cDDccDDccDDccDDccD"
    SKROW "dCCddCCddCCddCCddC"
    SKROW "DccDDccDDccDDccDDc"
    SKROW "CddCCddCCddCCddCCd"
    SKROW "cDDccDDccDDccDDccD"
    SKROW "dCCddCCddCCddCCddC"
    SKROW "DccDDccDDccDDccDDc"
    SKROW "CddCCddCCddCCddCCd"
    SKROW "cDDccDDccDDccDDccD"
    SKROW "dCCddCCddCCddCCddC"
    SKROW "DccDDccDDccDDccDDc"
    SKROWS_END
    align 8
    SKBMP hs_shell_top, hs_shell_top_rows, 18, 18, hs_pal
    ; hs_brow_front (16x3): hs_brow FRONT
    SKROWS hs_brow_front_rows, 16, 3
    SKROW "TTTTTTTTTTTTTTTu"
    SKROW "T.r...r...r...ru"
    SKROW "Tuuuuuuuuuuuuuuu"
    SKROWS_END
    align 8
    SKBMP hs_brow_front, hs_brow_front_rows, 16, 3, hs_pal
    ; hs_cheek_front_left (2x12): hs_cheek_l FRONT
    SKROWS hs_cheek_front_left_rows, 2, 12
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tr"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tr"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tr"
    SKROW "Tu"
    SKROWS_END
    align 8
    SKBMP hs_cheek_front_left, hs_cheek_front_left_rows, 2, 12, hs_pal
    ; hs_cheek_front_right (2x12): hs_cheek_r FRONT
    SKROWS hs_cheek_front_right_rows, 2, 12
    SKROW "Tu"
    SKROW "Tu"
    SKROW "ru"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "ru"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "Tu"
    SKROW "ru"
    SKROW "Tu"
    SKROWS_END
    align 8
    SKBMP hs_cheek_front_right, hs_cheek_front_right_rows, 2, 12, hs_pal
    ; hs_chin_front (16x2): hs_chin FRONT
    SKROWS hs_chin_front_rows, 16, 2
    SKROW "TTrTTTrTTTrTTTrT"
    SKROW "uuuuuuuuuuuuuuuu"
    SKROWS_END
    align 8
    SKBMP hs_chin_front, hs_chin_front_rows, 16, 2, hs_pal
    ; hs_plate_front (12x2): hs_plate FRONT
    SKROWS hs_plate_front_rows, 12, 2
    SKROW "iriiriiriiri"
    SKROW "oooooooooooo"
    SKROWS_END
    align 8
    SKBMP hs_plate_front, hs_plate_front_rows, 12, 2, hs_pal
    ; hs_plate_back (12x2): hs_plate BACK
    SKROWS hs_plate_back_rows, 12, 2
    SKROW "iriiriiriiri"
    SKROW "oooooooooooo"
    SKROWS_END
    align 8
    SKBMP hs_plate_back, hs_plate_back_rows, 12, 2, hs_pal
    ; hs_plate_left (12x2): hs_plate LEFT
    SKROWS hs_plate_left_rows, 12, 2
    SKROW "iriiriiriiri"
    SKROW "oooooooooooo"
    SKROWS_END
    align 8
    SKBMP hs_plate_left, hs_plate_left_rows, 12, 2, hs_pal
    ; hs_plate_right (12x2): hs_plate RIGHT
    SKROWS hs_plate_right_rows, 12, 2
    SKROW "iriiriiriiri"
    SKROW "oooooooooooo"
    SKROWS_END
    align 8
    SKBMP hs_plate_right, hs_plate_right_rows, 12, 2, hs_pal
    ; hs_plate_top (12x12): hs_plate TOP
    SKROWS hs_plate_top_rows, 12, 12
    SKROW "iooooooooooo"
    SKROW "i..........o"
    SKROW "i.r......r.o"
    SKROW "i..III.....o"
    SKROW "i..........o"
    SKROW "i..........o"
    SKROW "i..........o"
    SKROW "i..........o"
    SKROW "i..........o"
    SKROW "i.r......r.o"
    SKROW "i..........o"
    SKROW "iooooooooooo"
    SKROWS_END
    align 8
    SKBMP hs_plate_top, hs_plate_top_rows, 12, 12, hs_pal
    ; hs_buckle_front (4x2): hs_buckle FRONT
    SKROWS hs_buckle_front_rows, 4, 2
    SKROW "IiiI"
    SKROW "ioOo"
    SKROWS_END
    align 8
    SKBMP hs_buckle_front, hs_buckle_front_rows, 4, 2, hs_pal

section .data
SKMODEL_BEGIN m_hood_stonekin, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART hs_shell, -9, 44, -9, 18, 20, 18, 3, SKPF_CUTOUT   ; hood shell with the face opening
    PART hs_brow, -8, 59, -11, 16, 3, 2, 7, 0               ; lip: brow
    PART hs_cheek_l, -8, 47, -11, 2, 12, 2, 3, 0            ; lip: left cheek
    PART hs_cheek_r, 6, 47, -11, 2, 12, 2, 3, 0             ; lip: right cheek
    PART hs_chin, -8, 45, -11, 16, 2, 2, 7, 0               ; lip: chin
    PART hs_plate, -6, 64, -6, 12, 2, 12, 3, 0              ; a riveted iron skull plate
    PART hs_buckle, -2, 45, -12, 4, 2, 1, 3, 0              ; iron buckle on the chin lip
SKMODEL_PAINT
    ; --- hs_shell: the shell; the face opening is a cutout (cols 3..14, rows 4..16 of the front image)
    SK_FILL hs_shell, SKM_ALL, HS_MAIL_2, 15
    SK_BMP hs_shell, SKF_FRONT, 0, 0, hs_shell_front
    SK_BMP hs_shell, SKF_BACK, 0, 0, hs_shell_back
    SK_BMP hs_shell, SKF_LEFT, 0, 0, hs_shell_side
    SK_BMP hs_shell, SKF_RIGHT, 0, 0, hs_shell_side
    SK_BMP hs_shell, SKF_TOP, 0, 0, hs_shell_top
    SK_RECT hs_shell, SKF_BOTTOM, 0, 0, 18, 18, HS_MAIL_4, 0
    SK_GRAD hs_shell, SKM_SIDES, 272, 224
    ; --- the lip: brow, cheeks and chin are bars, so the opening has real inner walls (darker lining)
    SK_FILL hs_brow, SKM_ALL, HS_LEATHER_2, 7
    SK_BMP hs_brow, SKF_FRONT, 0, 0, hs_brow_front
    SK_RECT hs_brow, SKF_BOTTOM, 0, 0, 16, 2, HS_LEATHER_4, 0
    SK_RECT hs_brow, SKF_TOP, 0, 0, 16, 2, HS_LEATHER_1, 7
    SK_RECT hs_brow, SKF_BACK, 0, 0, 16, 3, HS_LEATHER_4, 0
    SK_GRAD hs_brow, SKM_LEFT | SKM_RIGHT, 272, 224
    SK_FILL hs_cheek_l, SKM_ALL, HS_LEATHER_2, 7
    SK_BMP hs_cheek_l, SKF_FRONT, 0, 0, hs_cheek_front_left
    SK_RECT hs_cheek_l, SKF_RIGHT, 0, 0, 2, 12, HS_LEATHER_4, 0
    SK_RECT hs_cheek_l, SKF_LEFT, 0, 0, 2, 12, HS_LEATHER_3, 0
    SK_RECT hs_cheek_l, SKF_BACK, 0, 0, 2, 12, HS_LEATHER_4, 0
    SK_RECT hs_cheek_l, SKF_TOP, 0, 0, 2, 2, HS_LEATHER_1, 0
    SK_RECT hs_cheek_l, SKF_BOTTOM, 0, 0, 2, 2, HS_LEATHER_4, 0
    SK_FILL hs_cheek_r, SKM_ALL, HS_LEATHER_2, 7
    SK_BMP hs_cheek_r, SKF_FRONT, 0, 0, hs_cheek_front_right
    SK_RECT hs_cheek_r, SKF_LEFT, 0, 0, 2, 12, HS_LEATHER_4, 0
    SK_RECT hs_cheek_r, SKF_RIGHT, 0, 0, 2, 12, HS_LEATHER_3, 0
    SK_RECT hs_cheek_r, SKF_BACK, 0, 0, 2, 12, HS_LEATHER_4, 0
    SK_RECT hs_cheek_r, SKF_TOP, 0, 0, 2, 2, HS_LEATHER_1, 0
    SK_RECT hs_cheek_r, SKF_BOTTOM, 0, 0, 2, 2, HS_LEATHER_4, 0
    SK_FILL hs_chin, SKM_ALL, HS_LEATHER_2, 7
    SK_BMP hs_chin, SKF_FRONT, 0, 0, hs_chin_front
    SK_RECT hs_chin, SKF_TOP, 0, 0, 16, 2, HS_LEATHER_4, 0
    SK_RECT hs_chin, SKF_BOTTOM, 0, 0, 16, 2, HS_LEATHER_4, 0
    SK_RECT hs_chin, SKF_BACK, 0, 0, 16, 2, HS_LEATHER_4, 0
    SK_RECT hs_chin, SKF_LEFT, 0, 0, 2, 2, HS_LEATHER_3, 0
    SK_RECT hs_chin, SKF_RIGHT, 0, 0, 2, 2, HS_LEATHER_3, 0
    SK_FILL hs_plate, SKM_ALL, AC_IRON_2, 0
    SK_BMP hs_plate, SKF_FRONT, 0, 0, hs_plate_front
    SK_BMP hs_plate, SKF_BACK, 0, 0, hs_plate_back
    SK_BMP hs_plate, SKF_LEFT, 0, 0, hs_plate_left
    SK_BMP hs_plate, SKF_RIGHT, 0, 0, hs_plate_right
    SK_BMP hs_plate, SKF_TOP, 0, 0, hs_plate_top
    SK_RECT hs_plate, SKF_BOTTOM, 0, 0, 12, 12, AC_IRON_4, 0
    SK_GRAD hs_plate, SKM_SIDES, 272, 224
    SK_FILL hs_buckle, SKM_ALL, AC_IRON_3, 0
    SK_BMP hs_buckle, SKF_FRONT, 0, 0, hs_buckle_front
SKMODEL_END
