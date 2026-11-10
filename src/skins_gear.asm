; skins_gear.asm: skin models of the firearms (0.13 "looks"): the pistol, musket, shotgun, Kalashnikov rifle, rocket launcher,
; the launcher's rocket, revolver and hunting rifle, at 64 texels per block. Data only: bones, parts and paint ops for skin.asm
; (art.inc, common.inc "0.13 looks"); nothing here runs. gunmodel.asm draws them: gun_model_draw = skin_model_draw of the gun,
; the rocket (m_gun_warhead) on top of the launcher only while it is loaded, then the muzzle flash.
;
; Models (global labels, bitmap prefix): m_gun_pistol gp_, m_gun_musket gm_, m_gun_shotgun gs_, m_gun_rifle gr_, m_gun_launcher
; gl_, m_gun_warhead gw_, m_gun_revolver gv_, m_gun_hrifle gh_. Every model is one rigid BK_BODY bone, no pose, no held item.
;
; Model space (texels, 64 per block): the origin and the muzzle are those of the old boxes of gunmodel.asm (x 64): the grip near
; the origin, the muzzle towards -Z at (0, muzzle_y * 64, muzzle_z * 64), +Y up, +X the shooter's right. The extents stay within
; 2 texels of the old boxes everywhere (table at the end of this header), so the aim, the muzzle flash and the hip / aimed
; poses of hand.asm keep their meaning. The rocket sits in front of the launcher's muzzle collar, on the tube axis.
;
; What the player sees: the camera is behind the gun, so the TOP, BACK and (hip) LEFT faces carry most of the detail; the RIGHT
; face is the other players' side view. All six faces of every part are painted (skin_check).
;
; Local helpers (private to this file):
;   PART name, x0, y0, z0, w, h, d, grow, flags         SKPART; `name` becomes the part's index, so the paint ops name parts
;   PART_AS name, k, x0, y0, z0, grow, flags            SKPART_AS; shares the size and the skin of part k
; Conventions, shared with the other art files:
;   - one section per model, in file order: the palette and the bitmaps (section .rodata), then the model (section .data).
;   - one palette per model (<prefix>_pal); a material takes a group of letters, upper case = highlight, lower case = base, then
;     shade and deep (the comment above each palette is the legend): steel s S k K and glint g, dark steel d D e E, iron
;     (sights, guards, triggers) j i J and I, oak w W v V, walnut a A n N, brass b B c C, leather l L m M, olive paint o O q Q,
;     red r R p P, bakelite t T u U, plus x bore, z white, y hazard yellow, f F flint, G h H scope glass. '.' keeps the texel.
;   - colours: oak, iron, leather and brass come from the shared ramps of art.inc (AC_WOOD, AC_IRON, AC_LEATHER, and AC_GOLD_2..4 for
;     brass, one step darker than gold: it is a fitting, not an ingot); the GUN_* defines below are the guns' own ramps: blued
;     and dark steel, walnut (its base is the old guns' wood, 0.55 0.33 0.16), olive drab, the warhead red, bakelite, glass.
;   - a part's ops run: SK_FILL (the base letter of each group of faces: grain noise 15 on wood, 7 on leather, olive paint and
;     bakelite, 0 on metal), then SK_BMP overlays that hold only the texels that differ from the base (cropped to their bounding
;     box, '.' = base), then SK_GRAD on wood and on the launcher tube (vertical faces only, tops unchanged).
;   - the light comes from the top and from -X: a highlight row on top of every side face, a shade row at the bottom, the lit
;     column on the -X edge of TOP, BACK and FRONT faces. Metal has no noise.
;   - a long part is painted as one object and cut along Z into segments (<part>_a, _b, ...): the unwrap of a part costs
;     2(w+d) x (d+h) atlas texels, so a barrel of length 60 cut in three costs a third of the rows; details run across the cuts.
;   - mirrored pairs (left/right barrels, grip panels, sight posts, hammers, mounts, bands) share one skin (PART_AS); the outer
;     face of the source's LEFT side is the mirror image of its RIGHT side, so both twins show the same pattern.
;   - skin_build sorts the unwrap footprints by height (then width) before it shelf-packs them, so the order of the records
;     carries no meaning for the packing: they follow the logical order of the parts, which the paint ops and the comments use
;     too. The eight models take about 200 atlas rows of the 3072 together.
; Extents of the models in texels, grow counted, against the old boxes of gunmodel.asm x 64 (in brackets); the model never
; leaves them by more than 2 texels, nor stops short of them by more than 2:
;   m_gun_pistol    x -3..3 [-2.24..2.24]  y -11..6 [-10.24..4.48]  z -19..4 [-17.92..2.56]
;   m_gun_musket    x -4..5 [-3.2..3.2]  y -9..7 [-10.24..5.76]  z -68..23 [-67.2..22.4]
;   m_gun_shotgun   x -3.38..3.38 [-2.88..2.88]  y -8..6 [-8.32..4.16]  z -52..30 [-51.2..28.8]
;   m_gun_rifle     x -3..4 [-2.88..2.88]  y -16..7 [-17.92..6.4]  z -45.5..30 [-44.8..28.8]
;   m_gun_launcher  x -4.5..4.5 [-4.16..4.16]  y -11..8 [-11.52..7.04]  z -35.38..12.5 [-35.2..12.8]
;   m_gun_warhead   x -3.38..3.38 [-3.2..3.2]  y -0.38..6.38 [0..5.76]  z -44..-35 [-42.24..-35.2]
;   m_gun_revolver  x -3..3 [-2.88..2.88]  y -11..6 [-10.88..4.48]  z -20..5 [-19.2..3.84]
;   m_gun_hrifle    x -3..4 [-2.88..2.88]  y -9..9 [-9.6..7.36]  z -64..27 [-64..26.88]
; The muzzle flash starts at (0, muzzle_y * 64, muzzle_z * 64) and runs forward: the barrel fronts are the old muzzle_z * 64
; to within 1 texel (the barrel is in front of or inside the flash start, never behind it by more than 1).
%include "common.inc"
%include "art.inc"
default rel

%define GUN_STEEL_0    RGBO(206, 218, 240)           ; blued steel: glint
%define GUN_STEEL_1    RGBO(146, 160, 190)           ; edge highlight
%define GUN_STEEL_2    RGBO( 92, 104, 132)           ; base
%define GUN_STEEL_3    RGBO( 62,  72,  96)           ; shade
%define GUN_STEEL_4    RGBO( 36,  42,  60)           ; deep
%define GUN_DARK_1     RGBO(112, 118, 138)           ; dark steel (black oxide): highlight
%define GUN_DARK_2     RGBO( 74,  79,  96)           ; base
%define GUN_DARK_3     RGBO( 52,  56,  70)           ; shade
%define GUN_DARK_4     RGBO( 30,  32,  42)           ; deep
%define GUN_WALNUT_1   RGBO(178, 118,  64)           ; walnut: highlight
%define GUN_WALNUT_2   RGBO(138,  84,  42)           ; base
%define GUN_WALNUT_3   RGBO(100,  58,  30)           ; shade
%define GUN_WALNUT_4   RGBO( 64,  36,  20)           ; deep
%define GUN_OLIVE_1    RGBO(138, 160,  88)           ; olive drab: highlight
%define GUN_OLIVE_2    RGBO( 98, 122,  62)           ; base
%define GUN_OLIVE_3    RGBO( 70,  90,  46)           ; shade
%define GUN_OLIVE_4    RGBO( 46,  60,  32)           ; deep
%define GUN_RED_1      RGBO(244,  96,  72)           ; warhead red: highlight
%define GUN_RED_2      RGBO(196,  36,  30)           ; base
%define GUN_RED_3      RGBO(146,  24,  24)           ; shade
%define GUN_RED_4      RGBO( 92,  14,  18)           ; deep
%define GUN_BAKE_1     RGBO(186, 108,  52)           ; bakelite magazine: highlight
%define GUN_BAKE_2     RGBO(138,  74,  34)           ; base
%define GUN_BAKE_3     RGBO(100,  52,  24)           ; shade
%define GUN_BAKE_4     RGBO( 64,  32,  16)           ; deep
%define GUN_BRASS_DEEP RGBO( 84,  56,  14)           ; brass deep
%define GUN_BORE       RGBO( 12,  12,  16)           ; bores and slots
%define GUN_WHITE      RGBO(232, 232, 224)           ; white stencil paint
%define GUN_YELLOW     RGBO(232, 190,  40)           ; hazard yellow
%define GUN_FLINT      RGBO(132, 130, 124)           ; flint
%define GUN_FLINT_HI   RGBO(190, 188, 178)           ; flint highlight
%define GUN_LENS_1     RGBO(214, 240, 255)           ; scope glass: highlight
%define GUN_LENS_2     RGBO( 86, 140, 190)           ; glass
%define GUN_LENS_3     RGBO( 36,  66, 104)           ; glass deep

%macro PART 9
%assign %1 %$parts
    SKPART %2, %3, %4, %5, %6, %7, %8, %9
%endmacro
%macro PART_AS 7
%assign %1 %$parts
    SKPART_AS %2, %3, %4, %5, %6, %7
%endmacro

; ===================================================================================================
; m_gun_pistol
; ===================================================================================================
; The pistol: a blued slide with rear serrations, an ejection port and three-dot sights, a polished barrel tip, a dark
; frame with an accessory rail and a slide stop, a raked grip (steel backbone, walnut panels with checkering and brass
; screws, a steel base plate), a trigger guard with a trigger, a knurled hammer, a grip safety and a thumb safety.
; Model space (texels, 64 per block, muzzle -Z): the old boxes x 64 give the extents (slide 4.5 x 4.5 x 20, grip
; 4 x 10 x 5, muzzle at (0, 2.2, -18.6)); this model stays within 2 texels of them (x -3..3, y -11..6, z -19..4).
section .rodata
; The characters of every gp_ bitmap:
;  A walnut highlight, B brass highlight, D dark steel highlight, E dark steel deep, K steel deep, N walnut deep
;  S steel edge highlight, a walnut, b brass, c brass shade, d dark steel, e dark steel shade, i iron highlight
;  j iron, k steel shade, n walnut shade, s blued steel
align 8
gp_pal:
    PALC 'A', GUN_WALNUT_1
    PALC 'B', AC_GOLD_2
    PALC 'D', GUN_DARK_1
    PALC 'E', GUN_DARK_4
    PALC 'K', GUN_STEEL_4
    PALC 'N', GUN_WALNUT_4
    PALC 'S', GUN_STEEL_1
    PALC 'a', GUN_WALNUT_2
    PALC 'b', AC_GOLD_3
    PALC 'c', AC_GOLD_4
    PALC 'd', GUN_DARK_2
    PALC 'e', GUN_DARK_3
    PALC 'i', AC_IRON_2
    PALC 'j', AC_IRON_3
    PALC 'k', GUN_STEEL_3
    PALC 'n', GUN_WALNUT_3
    PALC 's', GUN_STEEL_2
    dq 0

    ; gp_slide_right (18x4 at 0,1 of the 18x5 RIGHT face)
    SKROWS gp_slide_right_rows, 18, 4
    SKROW "sK.K.KssKKKKKKskss"
    SKROW "sK.K.KssKbbKKKskss"
    SKROW "sK.K.Kss......skss"
    SKROW "kkkkkkkkkkkkkkkkkk"
    SKROWS_END
    align 8
    SKBMP gp_slide_right, gp_slide_right_rows, 18, 4, gp_pal
    ; gp_slide_left (18x4 at 0,0 of the 18x5 LEFT face)
    SKROWS gp_slide_left_rows, 18, 4
    SKROW "SSSSSSSSSSSSSSSSSS"
    SKROW "ss.sssssssssKSKSKs"
    SKROW "ss.sssssssssKSKSKs"
    SKROW "ss.s........KSKSKs"
    SKROWS_END
    align 8
    SKBMP gp_slide_left, gp_slide_left_rows, 18, 4, gp_pal
    ; gp_slide_top (4x18 at 0,0 of the 4x18 TOP face)
    SKROWS gp_slide_top_rows, 4, 18
    SKROW "KKKK"
    SKROW ".ssS"
    SKROW "...."
    SKROW ".ssS"
    SKROW "...."
    SKROW ".ssS"
    SKROW ".sSS"
    SKROW ".sSS"
    SKROW ".sSS"
    SKROW ".sSS"
    SKROW ".sSS"
    SKROW ".sSS"
    SKROW ".sSS"
    SKROW ".sSS"
    SKROW ".sSS"
    SKROW "...."
    SKROW ".ssS"
    SKROW "KKKK"
    SKROWS_END
    align 8
    SKBMP gp_slide_top, gp_slide_top_rows, 4, 18, gp_pal
    ; gp_slide_back (4x4 at 0,1 of the 4x5 BACK face)
    SKROWS gp_slide_back_rows, 4, 4
    SKROW ".ssk"
    SKROW ".ssk"
    SKROW ".KKk"
    SKROW "kkkk"
    SKROWS_END
    align 8
    SKBMP gp_slide_back, gp_slide_back_rows, 4, 4, gp_pal
    ; gp_slide_front (4x4 at 0,0 of the 4x5 FRONT face)
    SKROWS gp_slide_front_rows, 4, 4
    SKROW "SSSS"
    SKROW "...S"
    SKROW ".ssS"
    SKROW ".ssS"
    SKROWS_END
    align 8
    SKBMP gp_slide_front, gp_slide_front_rows, 4, 4, gp_pal
    ; gp_barrel_right (3x1 at 0,1 of the 3x2 RIGHT face)
    SKROWS gp_barrel_right_rows, 3, 1
    SKROW "sss"
    SKROWS_END
    align 8
    SKBMP gp_barrel_right, gp_barrel_right_rows, 3, 1, gp_pal
    ; gp_barrel_left (3x1 at 0,1 of the 3x2 LEFT face)
    SKROWS gp_barrel_left_rows, 3, 1
    SKROW "sss"
    SKROWS_END
    align 8
    SKBMP gp_barrel_left, gp_barrel_left_rows, 3, 1, gp_pal
    ; gp_barrel_top (1x3 at 0,0 of the 2x3 TOP face)
    SKROWS gp_barrel_top_rows, 1, 3
    SKROW "s"
    SKROW "s"
    SKROW "s"
    SKROWS_END
    align 8
    SKBMP gp_barrel_top, gp_barrel_top_rows, 1, 3, gp_pal
    ; gp_barrel_back (2x1 at 0,1 of the 2x2 BACK face)
    SKROWS gp_barrel_back_rows, 2, 1
    SKROW "ss"
    SKROWS_END
    align 8
    SKBMP gp_barrel_back, gp_barrel_back_rows, 2, 1, gp_pal
    ; gp_barrel_front (1x1 at 0,0 of the 2x2 FRONT face)
    SKROWS gp_barrel_front_rows, 1, 1
    SKROW "k"
    SKROWS_END
    align 8
    SKBMP gp_barrel_front, gp_barrel_front_rows, 1, 1, gp_pal
    ; gp_frame_right (15x2 at 0,1 of the 15x3 RIGHT face)
    SKROWS gp_frame_right_rows, 15, 2
    SKROW "ddkSSSdddEdEdEd"
    SKROW "eeeeeeeeeeeeeee"
    SKROWS_END
    align 8
    SKBMP gp_frame_right, gp_frame_right_rows, 15, 2, gp_pal
    ; gp_frame_left (15x2 at 0,1 of the 15x3 LEFT face)
    SKROWS gp_frame_left_rows, 15, 2
    SKROW "dEdEdEdddSSSkdd"
    SKROW "eeeeeeeeeeeeeee"
    SKROWS_END
    align 8
    SKBMP gp_frame_left, gp_frame_left_rows, 15, 2, gp_pal
    ; gp_frame_top (4x15 at 0,0 of the 4x15 TOP face)
    SKROWS gp_frame_top_rows, 4, 15
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROWS_END
    align 8
    SKBMP gp_frame_top, gp_frame_top_rows, 4, 15, gp_pal
    ; gp_frame_bottom (4x10 at 0,3 of the 4x15 BOTTOM face)
    SKROWS gp_frame_bottom_rows, 4, 10
    SKROW "eeee"
    SKROW "...."
    SKROW "...."
    SKROW "eeee"
    SKROW "...."
    SKROW "...."
    SKROW "eeee"
    SKROW "...."
    SKROW "...."
    SKROW "eeee"
    SKROWS_END
    align 8
    SKBMP gp_frame_bottom, gp_frame_bottom_rows, 4, 10, gp_pal
    ; gp_frame_back (4x2 at 0,1 of the 4x3 BACK face)
    SKROWS gp_frame_back_rows, 4, 2
    SKROW ".dde"
    SKROW "eeee"
    SKROWS_END
    align 8
    SKBMP gp_frame_back, gp_frame_back_rows, 4, 2, gp_pal
    ; gp_frame_front (4x2 at 0,1 of the 4x3 FRONT face)
    SKROWS gp_frame_front_rows, 4, 2
    SKROW "eEE."
    SKROW "eeee"
    SKROWS_END
    align 8
    SKBMP gp_frame_front, gp_frame_front_rows, 4, 2, gp_pal
    ; gp_core_u_right (6x2 at 0,1 of the 6x3 RIGHT face)
    SKROWS gp_core_u_right_rows, 6, 2
    SKROW "dddddd"
    SKROW "eeeeee"
    SKROWS_END
    align 8
    SKBMP gp_core_u_right, gp_core_u_right_rows, 6, 2, gp_pal
    ; gp_core_u_left (6x2 at 0,1 of the 6x3 LEFT face)
    SKROWS gp_core_u_left_rows, 6, 2
    SKROW "dddddd"
    SKROW "eeeeee"
    SKROWS_END
    align 8
    SKBMP gp_core_u_left, gp_core_u_left_rows, 6, 2, gp_pal
    ; gp_core_u_top (1x6 at 0,0 of the 2x6 TOP face)
    SKROWS gp_core_u_top_rows, 1, 6
    SKROW "e"
    SKROW "e"
    SKROW "e"
    SKROW "e"
    SKROW "e"
    SKROW "e"
    SKROWS_END
    align 8
    SKBMP gp_core_u_top, gp_core_u_top_rows, 1, 6, gp_pal
    ; gp_core_u_back (2x2 at 0,1 of the 2x3 BACK face)
    SKROWS gp_core_u_back_rows, 2, 2
    SKROW ".d"
    SKROW "ee"
    SKROWS_END
    align 8
    SKBMP gp_core_u_back, gp_core_u_back_rows, 2, 2, gp_pal
    ; gp_core_u_front (2x1 at 0,1 of the 2x3 FRONT face)
    SKROWS gp_core_u_front_rows, 2, 1
    SKROW "dd"
    SKROWS_END
    align 8
    SKBMP gp_core_u_front, gp_core_u_front_rows, 2, 1, gp_pal
    ; gp_core_l_right (6x4 at 0,0 of the 6x4 RIGHT face)
    SKROWS gp_core_l_right_rows, 6, 4
    SKROW "DDDDDD"
    SKROW "......"
    SKROW "......"
    SKROW "eeeeee"
    SKROWS_END
    align 8
    SKBMP gp_core_l_right, gp_core_l_right_rows, 6, 4, gp_pal
    ; gp_core_l_left (6x4 at 0,0 of the 6x4 LEFT face)
    SKROWS gp_core_l_left_rows, 6, 4
    SKROW "DDDDDD"
    SKROW "......"
    SKROW "......"
    SKROW "eeeeee"
    SKROWS_END
    align 8
    SKBMP gp_core_l_left, gp_core_l_left_rows, 6, 4, gp_pal
    ; gp_core_l_top (1x6 at 0,0 of the 2x6 TOP face)
    SKROWS gp_core_l_top_rows, 1, 6
    SKROW "e"
    SKROW "e"
    SKROW "e"
    SKROW "e"
    SKROW "e"
    SKROW "e"
    SKROWS_END
    align 8
    SKBMP gp_core_l_top, gp_core_l_top_rows, 1, 6, gp_pal
    ; gp_core_l_back (2x3 at 0,1 of the 2x4 BACK face)
    SKROWS gp_core_l_back_rows, 2, 3
    SKROW ".d"
    SKROW ".d"
    SKROW "ee"
    SKROWS_END
    align 8
    SKBMP gp_core_l_back, gp_core_l_back_rows, 2, 3, gp_pal
    ; gp_core_l_front (2x3 at 0,0 of the 2x4 FRONT face)
    SKROWS gp_core_l_front_rows, 2, 3
    SKROW "ee"
    SKROW ".."
    SKROW "ee"
    SKROWS_END
    align 8
    SKBMP gp_core_l_front, gp_core_l_front_rows, 2, 3, gp_pal
    ; gp_scale_ul_right (5x2 at 0,1 of the 6x3 RIGHT face)
    SKROWS gp_scale_ul_right_rows, 5, 2
    SKROW "nanan"
    SKROW "nnana"
    SKROWS_END
    align 8
    SKBMP gp_scale_ul_right, gp_scale_ul_right_rows, 5, 2, gp_pal
    ; gp_scale_ul_left (5x2 at 1,1 of the 6x3 LEFT face)
    SKROWS gp_scale_ul_left_rows, 5, 2
    SKROW "nanan"
    SKROW "anann"
    SKROWS_END
    align 8
    SKBMP gp_scale_ul_left, gp_scale_ul_left_rows, 5, 2, gp_pal
    ; gp_scale_ul_bottom (1x5 at 0,1 of the 2x6 BOTTOM face)
    SKROWS gp_scale_ul_bottom_rows, 1, 5
    SKROW "N"
    SKROW "N"
    SKROW "N"
    SKROW "N"
    SKROW "N"
    SKROWS_END
    align 8
    SKBMP gp_scale_ul_bottom, gp_scale_ul_bottom_rows, 1, 5, gp_pal
    ; gp_scale_ul_back (2x1 at 0,1 of the 2x3 BACK face)
    SKROWS gp_scale_ul_back_rows, 2, 1
    SKROW "aa"
    SKROWS_END
    align 8
    SKBMP gp_scale_ul_back, gp_scale_ul_back_rows, 2, 1, gp_pal
    ; gp_scale_ul_front (2x1 at 0,1 of the 2x3 FRONT face)
    SKROWS gp_scale_ul_front_rows, 2, 1
    SKROW "aa"
    SKROWS_END
    align 8
    SKBMP gp_scale_ul_front, gp_scale_ul_front_rows, 2, 1, gp_pal
    ; gp_scale_ll_right (5x3 at 1,0 of the 6x4 RIGHT face)
    SKROWS gp_scale_ll_right_rows, 5, 3
    SKROW "abB.A"
    SKROW ".cbaA"
    SKROW "a.a.A"
    SKROWS_END
    align 8
    SKBMP gp_scale_ll_right, gp_scale_ll_right_rows, 5, 3, gp_pal
    ; gp_scale_ll_left (5x3 at 0,0 of the 6x4 LEFT face)
    SKROWS gp_scale_ll_left_rows, 5, 3
    SKROW "A.Bba"
    SKROW "Aabc."
    SKROW "A.a.a"
    SKROWS_END
    align 8
    SKBMP gp_scale_ll_left, gp_scale_ll_left_rows, 5, 3, gp_pal
    ; gp_scale_ll_back (2x4 at 0,0 of the 2x4 BACK face)
    SKROWS gp_scale_ll_back_rows, 2, 4
    SKROW "nn"
    SKROW ".."
    SKROW ".."
    SKROW "nn"
    SKROWS_END
    align 8
    SKBMP gp_scale_ll_back, gp_scale_ll_back_rows, 2, 4, gp_pal
    ; gp_scale_ll_front (2x4 at 0,0 of the 2x4 FRONT face)
    SKROWS gp_scale_ll_front_rows, 2, 4
    SKROW "nn"
    SKROW ".."
    SKROW ".."
    SKROW "nn"
    SKROWS_END
    align 8
    SKBMP gp_scale_ll_front, gp_scale_ll_front_rows, 2, 4, gp_pal
    ; gp_plate_top (6x6 at 0,0 of the 6x6 TOP face)
    SKROWS gp_plate_top_rows, 6, 6
    SKROW "k....S"
    SKROW "k....S"
    SKROW "k....S"
    SKROW "k....S"
    SKROW "k....S"
    SKROW "k....S"
    SKROWS_END
    align 8
    SKBMP gp_plate_top, gp_plate_top_rows, 6, 6, gp_pal
    ; gp_plate_bottom (6x6 at 0,0 of the 6x6 BOTTOM face)
    SKROWS gp_plate_bottom_rows, 6, 6
    SKROW "kkkkkk"
    SKROW "......"
    SKROW "..Bb.."
    SKROW "..bc.."
    SKROW "......"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP gp_plate_bottom, gp_plate_bottom_rows, 6, 6, gp_pal
    ; gp_guard_f_right (1x2 at 0,0 of the 1x3 RIGHT face)
    SKROWS gp_guard_f_right_rows, 1, 2
    SKROW "i"
    SKROW "j"
    SKROWS_END
    align 8
    SKBMP gp_guard_f_right, gp_guard_f_right_rows, 1, 2, gp_pal
    ; gp_guard_f_left (1x2 at 0,0 of the 1x3 LEFT face)
    SKROWS gp_guard_f_left_rows, 1, 2
    SKROW "i"
    SKROW "j"
    SKROWS_END
    align 8
    SKBMP gp_guard_f_left, gp_guard_f_left_rows, 1, 2, gp_pal
    ; gp_guard_f_top (1x1 at 1,0 of the 2x1 TOP face)
    SKROWS gp_guard_f_top_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gp_guard_f_top, gp_guard_f_top_rows, 1, 1, gp_pal
    ; gp_guard_f_back (2x2 at 0,0 of the 2x3 BACK face)
    SKROWS gp_guard_f_back_rows, 2, 2
    SKROW "ii"
    SKROW "jj"
    SKROWS_END
    align 8
    SKBMP gp_guard_f_back, gp_guard_f_back_rows, 2, 2, gp_pal
    ; gp_guard_f_front (2x2 at 0,0 of the 2x3 FRONT face)
    SKROWS gp_guard_f_front_rows, 2, 2
    SKROW "ii"
    SKROW "jj"
    SKROWS_END
    align 8
    SKBMP gp_guard_f_front, gp_guard_f_front_rows, 2, 2, gp_pal
    ; gp_guard_b_top (1x4 at 0,0 of the 2x4 TOP face)
    SKROWS gp_guard_b_top_rows, 1, 4
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROWS_END
    align 8
    SKBMP gp_guard_b_top, gp_guard_b_top_rows, 1, 4, gp_pal
    ; gp_trigger_right (1x1 at 0,0 of the 1x2 RIGHT face)
    SKROWS gp_trigger_right_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gp_trigger_right, gp_trigger_right_rows, 1, 1, gp_pal
    ; gp_trigger_left (1x1 at 0,0 of the 1x2 LEFT face)
    SKROWS gp_trigger_left_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gp_trigger_left, gp_trigger_left_rows, 1, 1, gp_pal
    ; gp_trigger_top (1x1 at 1,0 of the 2x1 TOP face)
    SKROWS gp_trigger_top_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gp_trigger_top, gp_trigger_top_rows, 1, 1, gp_pal
    ; gp_trigger_back (2x1 at 0,0 of the 2x2 BACK face)
    SKROWS gp_trigger_back_rows, 2, 1
    SKROW "ii"
    SKROWS_END
    align 8
    SKBMP gp_trigger_back, gp_trigger_back_rows, 2, 1, gp_pal
    ; gp_trigger_front (2x1 at 0,1 of the 2x2 FRONT face)
    SKROWS gp_trigger_front_rows, 2, 1
    SKROW "jj"
    SKROWS_END
    align 8
    SKBMP gp_trigger_front, gp_trigger_front_rows, 2, 1, gp_pal
    ; gp_hammer_right (1x2 at 0,1 of the 1x3 RIGHT face)
    SKROWS gp_hammer_right_rows, 1, 2
    SKROW "s"
    SKROW "k"
    SKROWS_END
    align 8
    SKBMP gp_hammer_right, gp_hammer_right_rows, 1, 2, gp_pal
    ; gp_hammer_left (1x2 at 0,1 of the 1x3 LEFT face)
    SKROWS gp_hammer_left_rows, 1, 2
    SKROW "s"
    SKROW "k"
    SKROWS_END
    align 8
    SKBMP gp_hammer_left, gp_hammer_left_rows, 1, 2, gp_pal
    ; gp_hammer_top (1x1 at 0,0 of the 2x1 TOP face)
    SKROWS gp_hammer_top_rows, 1, 1
    SKROW "k"
    SKROWS_END
    align 8
    SKBMP gp_hammer_top, gp_hammer_top_rows, 1, 1, gp_pal
    ; gp_hammer_back (2x3 at 0,0 of the 2x3 BACK face)
    SKROWS gp_hammer_back_rows, 2, 3
    SKROW "s."
    SKROW ".s"
    SKROW "s."
    SKROWS_END
    align 8
    SKBMP gp_hammer_back, gp_hammer_back_rows, 2, 3, gp_pal
    ; gp_hammer_front (2x2 at 0,1 of the 2x3 FRONT face)
    SKROWS gp_hammer_front_rows, 2, 2
    SKROW "ss"
    SKROW "kk"
    SKROWS_END
    align 8
    SKBMP gp_hammer_front, gp_hammer_front_rows, 2, 2, gp_pal
    ; gp_beavertail_right (2x2 at 0,1 of the 2x3 RIGHT face)
    SKROWS gp_beavertail_right_rows, 2, 2
    SKROW "dd"
    SKROW "ee"
    SKROWS_END
    align 8
    SKBMP gp_beavertail_right, gp_beavertail_right_rows, 2, 2, gp_pal
    ; gp_beavertail_left (2x2 at 0,1 of the 2x3 LEFT face)
    SKROWS gp_beavertail_left_rows, 2, 2
    SKROW "dd"
    SKROW "ee"
    SKROWS_END
    align 8
    SKBMP gp_beavertail_left, gp_beavertail_left_rows, 2, 2, gp_pal
    ; gp_beavertail_top (1x2 at 1,0 of the 2x2 TOP face)
    SKROWS gp_beavertail_top_rows, 1, 2
    SKROW "d"
    SKROW "d"
    SKROWS_END
    align 8
    SKBMP gp_beavertail_top, gp_beavertail_top_rows, 1, 2, gp_pal
    ; gp_beavertail_back (2x3 at 0,0 of the 2x3 BACK face)
    SKROWS gp_beavertail_back_rows, 2, 3
    SKROW ".e"
    SKROW "d."
    SKROW "ed"
    SKROWS_END
    align 8
    SKBMP gp_beavertail_back, gp_beavertail_back_rows, 2, 3, gp_pal
    ; gp_beavertail_front (2x2 at 0,1 of the 2x3 FRONT face)
    SKROWS gp_beavertail_front_rows, 2, 2
    SKROW "dd"
    SKROW "ee"
    SKROWS_END
    align 8
    SKBMP gp_beavertail_front, gp_beavertail_front_rows, 2, 2, gp_pal
    ; gp_safety_right (3x1 at 0,1 of the 3x2 RIGHT face)
    SKROWS gp_safety_right_rows, 3, 1
    SKROW "kkk"
    SKROWS_END
    align 8
    SKBMP gp_safety_right, gp_safety_right_rows, 3, 1, gp_pal
    ; gp_safety_left (3x2 at 0,0 of the 3x2 LEFT face)
    SKROWS gp_safety_left_rows, 3, 2
    SKROW "S.S"
    SKROW "k.k"
    SKROWS_END
    align 8
    SKBMP gp_safety_left, gp_safety_left_rows, 3, 2, gp_pal
    ; gp_safety_back (1x1 at 0,1 of the 1x2 BACK face)
    SKROWS gp_safety_back_rows, 1, 1
    SKROW "k"
    SKROWS_END
    align 8
    SKBMP gp_safety_back, gp_safety_back_rows, 1, 1, gp_pal
    ; gp_safety_front (1x1 at 0,1 of the 1x2 FRONT face)
    SKROWS gp_safety_front_rows, 1, 1
    SKROW "k"
    SKROWS_END
    align 8
    SKBMP gp_safety_front, gp_safety_front_rows, 1, 1, gp_pal
    ; gp_sight_f_top (1x2 at 1,0 of the 2x2 TOP face)
    SKROWS gp_sight_f_top_rows, 1, 2
    SKROW "i"
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gp_sight_f_top, gp_sight_f_top_rows, 1, 2, gp_pal

section .data
SKMODEL_BEGIN m_gun_pistol, 64, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART gp_slide, -2, 0, -16, 4, 5, 18, 0, 0                     ; blued slide: serrations, ejection port, engraving
    PART gp_barrel, -1, 1, -19, 2, 2, 3, 0, 0                     ; polished barrel tip with the bore
    PART gp_frame, -2, -3, -13, 4, 3, 15, 0, 0                    ; dark frame with the accessory rail and the slide stop
    PART gp_core_u, -1, -6, -4, 2, 3, 6, 0, 0                     ; grip backbone, upper
    PART gp_core_l, -1, -10, -2, 2, 4, 6, 0, 0                    ; grip backbone, lower
    PART gp_scale_ul, -3, -6, -4, 2, 3, 6, 0, 0                   ; walnut grip panel: checkering
    PART_AS gp_scale_ur, gp_scale_ul, 1, -6, -4, 0, 0             ; mirrored twin of scale_ul
    PART gp_scale_ll, -3, -10, -2, 2, 4, 6, 0, 0                  ; walnut grip panel: checkering and a brass screw
    PART_AS gp_scale_lr, gp_scale_ll, 1, -10, -2, 0, 0            ; mirrored twin of scale_ll
    PART gp_plate, -3, -11, -2, 6, 1, 6, 0, 0                     ; steel base plate with a lanyard ring
    PART gp_guard_f, -1, -6, -9, 2, 3, 1, 0, 0                    ; trigger guard, front post
    PART gp_guard_b, -1, -6, -8, 2, 1, 4, 0, 0                    ; trigger guard, bottom bar
    PART gp_trigger, -1, -5, -6, 2, 2, 1, 0, 0                    ; trigger
    PART gp_hammer, -1, 3, 2, 2, 3, 1, 0, 0                       ; hammer spur, knurled
    PART gp_beavertail, -1, -3, 2, 2, 3, 2, 0, 0                  ; grip safety (beavertail) under the hammer
    PART gp_safety, -3, -1, -2, 1, 2, 3, 0, 0                     ; thumb safety lever, serrated
    PART gp_sight_f, -1, 5, -15, 2, 1, 2, 0, 0                    ; front sight with a white dot
    PART gp_sight_rl, -2, 5, 0, 1, 1, 2, 0, 0                     ; rear sight post with a white dot
    PART_AS gp_sight_rr, gp_sight_rl, 1, 5, 0, 0, 0               ; mirrored twin of sight_rl
SKMODEL_PAINT
    ; --- gp_slide  (blued slide: serrations, ejection port, engraving)
    SK_FILL gp_slide, SKM_LEFT | SKM_TOP | SKM_FRONT, GUN_STEEL_3, 0
    SK_FILL gp_slide, SKM_RIGHT | SKM_BACK, GUN_STEEL_1, 0
    SK_FILL gp_slide, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gp_slide, SKF_RIGHT, 0, 1, gp_slide_right
    SK_BMP gp_slide, SKF_LEFT, 0, 0, gp_slide_left
    SK_BMP gp_slide, SKF_TOP, 0, 0, gp_slide_top
    SK_BMP gp_slide, SKF_BACK, 0, 1, gp_slide_back
    SK_BMP gp_slide, SKF_FRONT, 0, 0, gp_slide_front
    ; --- gp_barrel  (polished barrel tip with the bore)
    SK_FILL gp_barrel, SKM_FRONT, GUN_BORE, 0
    SK_FILL gp_barrel, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK, GUN_STEEL_0, 0
    SK_FILL gp_barrel, SKM_BOTTOM, GUN_STEEL_3, 0
    SK_BMP gp_barrel, SKF_RIGHT, 0, 1, gp_barrel_right
    SK_BMP gp_barrel, SKF_LEFT, 0, 1, gp_barrel_left
    SK_BMP gp_barrel, SKF_TOP, 0, 0, gp_barrel_top
    SK_BMP gp_barrel, SKF_BACK, 0, 1, gp_barrel_back
    SK_BMP gp_barrel, SKF_FRONT, 0, 0, gp_barrel_front
    ; --- gp_frame  (dark frame with the accessory rail and the slide stop)
    SK_FILL gp_frame, SKM_RIGHT | SKM_LEFT | SKM_BACK | SKM_FRONT, GUN_DARK_1, 0
    SK_FILL gp_frame, SKM_BOTTOM, GUN_DARK_4, 0
    SK_FILL gp_frame, SKM_TOP, GUN_DARK_2, 0
    SK_BMP gp_frame, SKF_RIGHT, 0, 1, gp_frame_right
    SK_BMP gp_frame, SKF_LEFT, 0, 1, gp_frame_left
    SK_BMP gp_frame, SKF_TOP, 0, 0, gp_frame_top
    SK_BMP gp_frame, SKF_BOTTOM, 0, 3, gp_frame_bottom
    SK_BMP gp_frame, SKF_BACK, 0, 1, gp_frame_back
    SK_BMP gp_frame, SKF_FRONT, 0, 1, gp_frame_front
    ; --- gp_core_u  (grip backbone, upper)
    SK_FILL gp_core_u, SKM_FRONT, GUN_DARK_3, 0
    SK_FILL gp_core_u, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK, GUN_DARK_1, 0
    SK_FILL gp_core_u, SKM_BOTTOM, GUN_DARK_4, 0
    SK_BMP gp_core_u, SKF_RIGHT, 0, 1, gp_core_u_right
    SK_BMP gp_core_u, SKF_LEFT, 0, 1, gp_core_u_left
    SK_BMP gp_core_u, SKF_TOP, 0, 0, gp_core_u_top
    SK_BMP gp_core_u, SKF_BACK, 0, 1, gp_core_u_back
    SK_BMP gp_core_u, SKF_FRONT, 0, 1, gp_core_u_front
    ; --- gp_core_l  (grip backbone, lower)
    SK_FILL gp_core_l, SKM_RIGHT | SKM_LEFT | SKM_FRONT, GUN_DARK_2, 0
    SK_FILL gp_core_l, SKM_TOP | SKM_BACK, GUN_DARK_1, 0
    SK_FILL gp_core_l, SKM_BOTTOM, GUN_DARK_4, 0
    SK_BMP gp_core_l, SKF_RIGHT, 0, 0, gp_core_l_right
    SK_BMP gp_core_l, SKF_LEFT, 0, 0, gp_core_l_left
    SK_BMP gp_core_l, SKF_TOP, 0, 0, gp_core_l_top
    SK_BMP gp_core_l, SKF_BACK, 0, 1, gp_core_l_back
    SK_BMP gp_core_l, SKF_FRONT, 0, 0, gp_core_l_front
    ; --- gp_scale_ul  (walnut grip panel: checkering)
    SK_FILL gp_scale_ul, SKM_BOTTOM | SKM_BACK | SKM_FRONT, GUN_WALNUT_3, 0
    SK_FILL gp_scale_ul, SKM_TOP, GUN_WALNUT_2, 15
    SK_FILL gp_scale_ul, SKM_RIGHT | SKM_LEFT, GUN_WALNUT_1, 0
    SK_BMP gp_scale_ul, SKF_RIGHT, 0, 1, gp_scale_ul_right
    SK_BMP gp_scale_ul, SKF_LEFT, 1, 1, gp_scale_ul_left
    SK_BMP gp_scale_ul, SKF_BOTTOM, 0, 1, gp_scale_ul_bottom
    SK_BMP gp_scale_ul, SKF_BACK, 0, 1, gp_scale_ul_back
    SK_BMP gp_scale_ul, SKF_FRONT, 0, 1, gp_scale_ul_front
    SK_GRAD gp_scale_ul, SKM_RIGHT | SKM_LEFT, 256, 228
    ; --- gp_scale_ll  (walnut grip panel: checkering and a brass screw)
    SK_FILL gp_scale_ll, SKM_TOP | SKM_BACK | SKM_FRONT, GUN_WALNUT_2, 15
    SK_FILL gp_scale_ll, SKM_RIGHT | SKM_LEFT | SKM_BOTTOM, GUN_WALNUT_3, 0
    SK_BMP gp_scale_ll, SKF_RIGHT, 1, 0, gp_scale_ll_right
    SK_BMP gp_scale_ll, SKF_LEFT, 0, 0, gp_scale_ll_left
    SK_BMP gp_scale_ll, SKF_BACK, 0, 0, gp_scale_ll_back
    SK_BMP gp_scale_ll, SKF_FRONT, 0, 0, gp_scale_ll_front
    SK_GRAD gp_scale_ll, SKM_RIGHT | SKM_LEFT, 256, 228
    ; --- gp_plate  (steel base plate with a lanyard ring)
    SK_FILL gp_plate, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, GUN_STEEL_2, 0
    SK_FILL gp_plate, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gp_plate, SKF_TOP, 0, 0, gp_plate_top
    SK_BMP gp_plate, SKF_BOTTOM, 0, 0, gp_plate_bottom
    ; --- gp_guard_f  (trigger guard, front post)
    SK_FILL gp_guard_f, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, AC_IRON_4, 0
    SK_FILL gp_guard_f, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gp_guard_f, SKF_RIGHT, 0, 0, gp_guard_f_right
    SK_BMP gp_guard_f, SKF_LEFT, 0, 0, gp_guard_f_left
    SK_BMP gp_guard_f, SKF_TOP, 1, 0, gp_guard_f_top
    SK_BMP gp_guard_f, SKF_BACK, 0, 0, gp_guard_f_back
    SK_BMP gp_guard_f, SKF_FRONT, 0, 0, gp_guard_f_front
    ; --- gp_guard_b  (trigger guard, bottom bar)
    SK_FILL gp_guard_b, SKM_RIGHT | SKM_LEFT | SKM_BACK | SKM_FRONT, AC_IRON_3, 0
    SK_FILL gp_guard_b, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gp_guard_b, SKM_TOP, AC_IRON_2, 0
    SK_BMP gp_guard_b, SKF_TOP, 0, 0, gp_guard_b_top
    ; --- gp_trigger  (trigger)
    SK_FILL gp_trigger, SKM_FRONT, AC_IRON_1, 0
    SK_FILL gp_trigger, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK, AC_IRON_4, 0
    SK_FILL gp_trigger, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gp_trigger, SKF_RIGHT, 0, 0, gp_trigger_right
    SK_BMP gp_trigger, SKF_LEFT, 0, 0, gp_trigger_left
    SK_BMP gp_trigger, SKF_TOP, 1, 0, gp_trigger_top
    SK_BMP gp_trigger, SKF_BACK, 0, 0, gp_trigger_back
    SK_BMP gp_trigger, SKF_FRONT, 0, 1, gp_trigger_front
    ; --- gp_hammer  (hammer spur, knurled)
    SK_FILL gp_hammer, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_FRONT, GUN_STEEL_1, 0
    SK_FILL gp_hammer, SKM_BACK, GUN_STEEL_3, 0
    SK_FILL gp_hammer, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gp_hammer, SKF_RIGHT, 0, 1, gp_hammer_right
    SK_BMP gp_hammer, SKF_LEFT, 0, 1, gp_hammer_left
    SK_BMP gp_hammer, SKF_TOP, 0, 0, gp_hammer_top
    SK_BMP gp_hammer, SKF_BACK, 0, 0, gp_hammer_back
    SK_BMP gp_hammer, SKF_FRONT, 0, 1, gp_hammer_front
    ; --- gp_beavertail  (grip safety (beavertail) under the hammer)
    SK_FILL gp_beavertail, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, GUN_DARK_1, 0
    SK_FILL gp_beavertail, SKM_BOTTOM, GUN_DARK_4, 0
    SK_BMP gp_beavertail, SKF_RIGHT, 0, 1, gp_beavertail_right
    SK_BMP gp_beavertail, SKF_LEFT, 0, 1, gp_beavertail_left
    SK_BMP gp_beavertail, SKF_TOP, 1, 0, gp_beavertail_top
    SK_BMP gp_beavertail, SKF_BACK, 0, 0, gp_beavertail_back
    SK_BMP gp_beavertail, SKF_FRONT, 0, 1, gp_beavertail_front
    ; --- gp_safety  (thumb safety lever, serrated)
    SK_FILL gp_safety, SKM_RIGHT | SKM_TOP | SKM_BACK | SKM_FRONT, GUN_STEEL_1, 0
    SK_FILL gp_safety, SKM_LEFT | SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gp_safety, SKF_RIGHT, 0, 1, gp_safety_right
    SK_BMP gp_safety, SKF_LEFT, 0, 0, gp_safety_left
    SK_BMP gp_safety, SKF_BACK, 0, 1, gp_safety_back
    SK_BMP gp_safety, SKF_FRONT, 0, 1, gp_safety_front
    ; --- gp_sight_f  (front sight with a white dot)
    SK_FILL gp_sight_f, SKM_RIGHT | SKM_LEFT | SKM_FRONT, AC_IRON_3, 0
    SK_FILL gp_sight_f, SKM_BACK, GUN_WHITE, 0
    SK_FILL gp_sight_f, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gp_sight_f, SKM_TOP, AC_IRON_4, 0
    SK_BMP gp_sight_f, SKF_TOP, 1, 0, gp_sight_f_top
    ; --- gp_sight_rl  (rear sight post with a white dot)
    SK_FILL gp_sight_rl, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_FRONT, AC_IRON_3, 0
    SK_FILL gp_sight_rl, SKM_BACK, GUN_WHITE, 0
    SK_FILL gp_sight_rl, SKM_BOTTOM, GUN_STEEL_4, 0
SKMODEL_END

; ===================================================================================================
; m_gun_musket
; ===================================================================================================
; The musket: a long blued barrel with a polished muzzle, a vent and brass bands, a walnut stock stepped down to the butt
; (carved lock mortise, barrel pins, a brass tang strip), a ramrod with a brass tip, a flintlock on the right (plate, pan,
; cock and flint), a brass side plate on the left, a brass trigger guard and butt plate.
; Model space (texels, 64 per block, muzzle -Z): the old boxes x 64 give the extents (barrel 2.6 x 2.6 x 51, stock
; 5.8 x 8.6 x 61 .. 19, muzzle at (0, 2.6, -67.8)); this model stays within 2 texels of them (x -3..5, y -9..7,
; z -68..23). The barrel and the stock are cut along Z (unwrap area grows with the square of the length).
section .rodata
; The characters of every gm_ bitmap:
;  A walnut highlight, B brass highlight, C brass deep, J iron shade, K steel deep, N walnut deep
;  S steel edge highlight, a walnut, b brass, c brass shade, f flint stone, g steel glint, i iron highlight
;  k steel shade, n walnut shade, s blued steel, x bore, pure dark
align 8
gm_pal:
    PALC 'A', GUN_WALNUT_1
    PALC 'B', AC_GOLD_2
    PALC 'C', GUN_BRASS_DEEP
    PALC 'J', AC_IRON_4
    PALC 'K', GUN_STEEL_4
    PALC 'N', GUN_WALNUT_4
    PALC 'S', GUN_STEEL_1
    PALC 'a', GUN_WALNUT_2
    PALC 'b', AC_GOLD_3
    PALC 'c', AC_GOLD_4
    PALC 'f', GUN_FLINT
    PALC 'g', GUN_STEEL_0
    PALC 'i', AC_IRON_2
    PALC 'k', GUN_STEEL_3
    PALC 'n', GUN_WALNUT_3
    PALC 's', GUN_STEEL_2
    PALC 'x', GUN_BORE
    dq 0

    ; gm_barrel_a_right (21x4 at 0,0 of the 21x4 RIGHT face)
    SKROWS gm_barrel_a_right_rows, 21, 4
    SKROW "SSSSSSSSSSSSSSSSSKggg"
    SKROW ".................KSSS"
    SKROW ".................KSSS"
    SKROW "kkkkkkkkkkkkkkkkkKSSS"
    SKROWS_END
    align 8
    SKBMP gm_barrel_a_right, gm_barrel_a_right_rows, 21, 4, gm_pal
    ; gm_barrel_a_left (21x4 at 0,0 of the 21x4 LEFT face)
    SKROWS gm_barrel_a_left_rows, 21, 4
    SKROW "gggKSSSSSSSSSSSSSSSSS"
    SKROW "SSSK................."
    SKROW "SSSK................."
    SKROW "SSSKkkkkkkkkkkkkkkkkk"
    SKROWS_END
    align 8
    SKBMP gm_barrel_a_left, gm_barrel_a_left_rows, 21, 4, gm_pal
    ; gm_barrel_a_top (4x21 at 0,0 of the 4x21 TOP face)
    SKROWS gm_barrel_a_top_rows, 4, 21
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.g."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "KKKK"
    SKROW "SSSg"
    SKROW "SSSg"
    SKROW "SSSg"
    SKROWS_END
    align 8
    SKBMP gm_barrel_a_top, gm_barrel_a_top_rows, 4, 21, gm_pal
    ; gm_barrel_a_front (4x3 at 0,1 of the 4x4 FRONT face)
    SKROWS gm_barrel_a_front_rows, 4, 3
    SKROW ".Kxk"
    SKROW ".Kxk"
    SKROW "kkkk"
    SKROWS_END
    align 8
    SKBMP gm_barrel_a_front, gm_barrel_a_front_rows, 4, 3, gm_pal
    ; gm_barrel_b_right (21x3 at 0,0 of the 21x4 RIGHT face)
    SKROWS gm_barrel_b_right_rows, 21, 3
    SKROW "SSSSSSSSSSSSSSSSSSSSS"
    SKROW "sssssssssssssssssssss"
    SKROW "....................s"
    SKROWS_END
    align 8
    SKBMP gm_barrel_b_right, gm_barrel_b_right_rows, 21, 3, gm_pal
    ; gm_barrel_b_left (21x3 at 0,0 of the 21x4 LEFT face)
    SKROWS gm_barrel_b_left_rows, 21, 3
    SKROW "SSSSSSSSSSSSSSSSSSSSS"
    SKROW "sssssssssssssssssssss"
    SKROW "s...................."
    SKROWS_END
    align 8
    SKBMP gm_barrel_b_left, gm_barrel_b_left_rows, 21, 3, gm_pal
    ; gm_barrel_b_top (3x21 at 0,0 of the 4x21 TOP face)
    SKROWS gm_barrel_b_top_rows, 3, 21
    SKROW "k.S"
    SKROW "k.S"
    SKROW "k.S"
    SKROW "k.S"
    SKROW "k.S"
    SKROW "k.S"
    SKROW "k.S"
    SKROW "k.g"
    SKROW "k.S"
    SKROW "k.S"
    SKROW "k.S"
    SKROW "k.S"
    SKROW "k.S"
    SKROW "k.S"
    SKROW "k.S"
    SKROW "k.S"
    SKROW "k.S"
    SKROW "k.S"
    SKROW "k.S"
    SKROW "k.S"
    SKROW "k.S"
    SKROWS_END
    align 8
    SKBMP gm_barrel_b_top, gm_barrel_b_top_rows, 3, 21, gm_pal
    ; gm_barrel_c_right (20x2 at 0,0 of the 20x4 RIGHT face)
    SKROWS gm_barrel_c_right_rows, 20, 2
    SKROW "SKSSSSSSSSSSSSSSSSSS"
    SKROW "........ssssssssssss"
    SKROWS_END
    align 8
    SKBMP gm_barrel_c_right, gm_barrel_c_right_rows, 20, 2, gm_pal
    ; gm_barrel_c_left (20x2 at 0,0 of the 20x4 LEFT face)
    SKROWS gm_barrel_c_left_rows, 20, 2
    SKROW "SSSSSSSSSSSSSSSSSSSS"
    SKROW "ssssssssssss........"
    SKROWS_END
    align 8
    SKBMP gm_barrel_c_left, gm_barrel_c_left_rows, 20, 2, gm_pal
    ; gm_barrel_c_top (4x20 at 0,0 of the 4x20 TOP face)
    SKROWS gm_barrel_c_top_rows, 4, 20
    SKROW "k.S."
    SKROW "kkkk"
    SKROW "kSS."
    SKROW "kkkk"
    SKROW "k.S."
    SKROW "kKK."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.S."
    SKROW "k.S."
    SKROWS_END
    align 8
    SKBMP gm_barrel_c_top, gm_barrel_c_top_rows, 4, 20, gm_pal
    ; gm_band_a_right (2x9 at 0,0 of the 2x9 RIGHT face)
    SKROWS gm_band_a_right_rows, 2, 9
    SKROW "c."
    SKROW "c."
    SKROW "c."
    SKROW "CC"
    SKROW "c."
    SKROW "c."
    SKROW "c."
    SKROW "c."
    SKROW "c."
    SKROWS_END
    align 8
    SKBMP gm_band_a_right, gm_band_a_right_rows, 2, 9, gm_pal
    ; gm_band_a_left (2x9 at 0,0 of the 2x9 LEFT face)
    SKROWS gm_band_a_left_rows, 2, 9
    SKROW ".c"
    SKROW ".c"
    SKROW ".c"
    SKROW "CC"
    SKROW ".c"
    SKROW ".c"
    SKROW ".c"
    SKROW ".c"
    SKROW ".c"
    SKROWS_END
    align 8
    SKBMP gm_band_a_left, gm_band_a_left_rows, 2, 9, gm_pal
    ; gm_band_a_top (6x1 at 0,0 of the 6x2 TOP face)
    SKROWS gm_band_a_top_rows, 6, 1
    SKROW "cccccc"
    SKROWS_END
    align 8
    SKBMP gm_band_a_top, gm_band_a_top_rows, 6, 1, gm_pal
    ; gm_band_a_back (6x9 at 0,0 of the 6x9 BACK face)
    SKROWS gm_band_a_back_rows, 6, 9
    SKROW "BBBBBB"
    SKROW "B....c"
    SKROW "B....c"
    SKROW "B....c"
    SKROW "B....c"
    SKROW "B....c"
    SKROW "B....c"
    SKROW "B....c"
    SKROW "cccccc"
    SKROWS_END
    align 8
    SKBMP gm_band_a_back, gm_band_a_back_rows, 6, 9, gm_pal
    ; gm_band_a_front (6x9 at 0,0 of the 6x9 FRONT face)
    SKROWS gm_band_a_front_rows, 6, 9
    SKROW "BBBBBB"
    SKROW "c....B"
    SKROW "c....B"
    SKROW "c....B"
    SKROW "c....B"
    SKROW "c....B"
    SKROW "c....B"
    SKROW "c....B"
    SKROW "cccccc"
    SKROWS_END
    align 8
    SKBMP gm_band_a_front, gm_band_a_front_rows, 6, 9, gm_pal
    ; gm_fore_a_right (18x6 at 0,0 of the 18x6 RIGHT face)
    SKROWS gm_fore_a_right_rows, 18, 6
    SKROW "nnnnnnnnnnnnnnnnnn"
    SKROW ".................."
    SKROW "nnnnb.........b..."
    SKROW "....C.....nnnnC..."
    SKROW "......nnnnnn......"
    SKROW "nnnnnnnnnnnnnnnnnn"
    SKROWS_END
    align 8
    SKBMP gm_fore_a_right, gm_fore_a_right_rows, 18, 6, gm_pal
    ; gm_fore_a_left (18x4 at 0,1 of the 18x6 LEFT face)
    SKROWS gm_fore_a_left_rows, 18, 4
    SKROW "..........aaaaaaaa"
    SKROW "aaabaaaaaaaaabaaaa"
    SKROW "aaaC...aaaaaaCaaaa"
    SKROW ".....aaaaaaaaaaaaa"
    SKROWS_END
    align 8
    SKBMP gm_fore_a_left, gm_fore_a_left_rows, 18, 4, gm_pal
    ; gm_fore_a_top (6x18 at 0,0 of the 6x18 TOP face)
    SKROWS gm_fore_a_top_rows, 6, 18
    SKROW "n..A.A"
    SKROW "n..A.A"
    SKROW "n..A.A"
    SKROW "n..A.A"
    SKROW "n..A.A"
    SKROW "n..A.A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n..n.A"
    SKROW "n..n.A"
    SKROW "n..n.A"
    SKROW "n..n.A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROWS_END
    align 8
    SKBMP gm_fore_a_top, gm_fore_a_top_rows, 6, 18, gm_pal
    ; gm_fore_a_bottom (6x18 at 0,0 of the 6x18 BOTTOM face)
    SKROWS gm_fore_a_bottom_rows, 6, 18
    SKROW ".....N"
    SKROW ".....N"
    SKROW ".....N"
    SKROW "aa...N"
    SKROW "aa...N"
    SKROW "aa...."
    SKROW "aa...."
    SKROW "aa...."
    SKROW "aa...."
    SKROW "aa...."
    SKROW "aa...."
    SKROW "aa...."
    SKROW "a....."
    SKROW "a....."
    SKROW ".N...."
    SKROW ".N...."
    SKROW ".N...."
    SKROW ".N..N."
    SKROWS_END
    align 8
    SKBMP gm_fore_a_bottom, gm_fore_a_bottom_rows, 6, 18, gm_pal
    ; gm_fore_a_front (4x4 at 1,1 of the 6x6 FRONT face)
    SKROWS gm_fore_a_front_rows, 4, 4
    SKROW "Aaaa"
    SKROW "a..a"
    SKROW "a..a"
    SKROW "aaaa"
    SKROWS_END
    align 8
    SKBMP gm_fore_a_front, gm_fore_a_front_rows, 4, 4, gm_pal
    ; gm_fore_b_right (18x6 at 0,0 of the 18x6 RIGHT face)
    SKROWS gm_fore_b_right_rows, 18, 6
    SKROW "nnnnnnnnnnnnnnnnnn"
    SKROW ".................."
    SKROW "..b...b..........n"
    SKROW "..C...C..........."
    SKROW ".................."
    SKROW "nnnnnnnnnnnnnnnnnn"
    SKROWS_END
    align 8
    SKBMP gm_fore_b_right, gm_fore_b_right_rows, 18, 6, gm_pal
    ; gm_fore_b_left (18x6 at 0,0 of the 18x6 LEFT face)
    SKROWS gm_fore_b_left_rows, 18, 6
    SKROW "nnnnnnnnnnnnnnnnnn"
    SKROW ".................."
    SKROW "...........b.AAbA."
    SKROW "...........C...C.."
    SKROW ".............nnnn."
    SKROW "nnnnnnnnnnnnnnnnnn"
    SKROWS_END
    align 8
    SKBMP gm_fore_b_left, gm_fore_b_left_rows, 18, 6, gm_pal
    ; gm_fore_b_top (6x18 at 0,0 of the 6x18 TOP face)
    SKROWS gm_fore_b_top_rows, 6, 18
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n..n.A"
    SKROW "n..nnA"
    SKROW "n..nnA"
    SKROW "n..nnA"
    SKROW "n..nnA"
    SKROW "n..nnA"
    SKROW "n..n.A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n..A.A"
    SKROW "n..A.A"
    SKROW "n..A.A"
    SKROWS_END
    align 8
    SKBMP gm_fore_b_top, gm_fore_b_top_rows, 6, 18, gm_pal
    ; gm_fore_b_bottom (6x18 at 0,0 of the 6x18 BOTTOM face)
    SKROWS gm_fore_b_bottom_rows, 6, 18
    SKROW "....N."
    SKROW "a...N."
    SKROW "a...N."
    SKROW "a...N."
    SKROW ".N..N."
    SKROW ".N...."
    SKROW ".N...."
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "..N..."
    SKROW "..N..."
    SKROW "..N..."
    SKROW "..N..."
    SKROW "..N..N"
    SKROWS_END
    align 8
    SKBMP gm_fore_b_bottom, gm_fore_b_bottom_rows, 6, 18, gm_pal
    ; gm_fore_b_back (4x4 at 1,1 of the 6x6 BACK face)
    SKROWS gm_fore_b_back_rows, 4, 4
    SKROW "Aaaa"
    SKROW "a..a"
    SKROW "a..a"
    SKROW "aaaa"
    SKROWS_END
    align 8
    SKBMP gm_fore_b_back, gm_fore_b_back_rows, 4, 4, gm_pal
    ; gm_cap_right (2x6 at 0,0 of the 2x6 RIGHT face)
    SKROWS gm_cap_right_rows, 2, 6
    SKROW "BB"
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROW "cc"
    SKROWS_END
    align 8
    SKBMP gm_cap_right, gm_cap_right_rows, 2, 6, gm_pal
    ; gm_cap_left (2x6 at 0,0 of the 2x6 LEFT face)
    SKROWS gm_cap_left_rows, 2, 6
    SKROW "BB"
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROW "cc"
    SKROWS_END
    align 8
    SKBMP gm_cap_left, gm_cap_left_rows, 2, 6, gm_pal
    ; gm_cap_top (6x2 at 0,0 of the 6x2 TOP face)
    SKROWS gm_cap_top_rows, 6, 2
    SKROW "c....B"
    SKROW "c....B"
    SKROWS_END
    align 8
    SKBMP gm_cap_top, gm_cap_top_rows, 6, 2, gm_pal
    ; gm_cap_back (6x6 at 0,0 of the 6x6 BACK face)
    SKROWS gm_cap_back_rows, 6, 6
    SKROW "BBBBBB"
    SKROW "B....c"
    SKROW "B....c"
    SKROW "B....c"
    SKROW "B....c"
    SKROW "cccccc"
    SKROWS_END
    align 8
    SKBMP gm_cap_back, gm_cap_back_rows, 6, 6, gm_pal
    ; gm_cap_front (6x6 at 0,0 of the 6x6 FRONT face)
    SKROWS gm_cap_front_rows, 6, 6
    SKROW "BBBBBB"
    SKROW "c....B"
    SKROW "c....B"
    SKROW "c....B"
    SKROW "c....B"
    SKROW "cccccc"
    SKROWS_END
    align 8
    SKBMP gm_cap_front, gm_cap_front_rows, 6, 6, gm_pal
    ; gm_ramrod_right (13x2 at 0,0 of the 13x2 RIGHT face)
    SKROWS gm_ramrod_right_rows, 13, 2
    SKROW "iiiiiiiiii.BB"
    SKROW "...........bb"
    SKROWS_END
    align 8
    SKBMP gm_ramrod_right, gm_ramrod_right_rows, 13, 2, gm_pal
    ; gm_ramrod_left (13x2 at 0,0 of the 13x2 LEFT face)
    SKROWS gm_ramrod_left_rows, 13, 2
    SKROW "BB.iiiiiiiiii"
    SKROW "bb..........."
    SKROWS_END
    align 8
    SKBMP gm_ramrod_left, gm_ramrod_left_rows, 13, 2, gm_pal
    ; gm_ramrod_top (2x13 at 0,0 of the 2x13 TOP face)
    SKROWS gm_ramrod_top_rows, 2, 13
    SKROW ".i"
    SKROW ".i"
    SKROW ".i"
    SKROW ".i"
    SKROW ".i"
    SKROW ".i"
    SKROW ".i"
    SKROW ".i"
    SKROW ".i"
    SKROW ".i"
    SKROW ".i"
    SKROW "bb"
    SKROW "bb"
    SKROWS_END
    align 8
    SKBMP gm_ramrod_top, gm_ramrod_top_rows, 2, 13, gm_pal
    ; gm_ramrod_back (2x1 at 0,0 of the 2x2 BACK face)
    SKROWS gm_ramrod_back_rows, 2, 1
    SKROW "ii"
    SKROWS_END
    align 8
    SKBMP gm_ramrod_back, gm_ramrod_back_rows, 2, 1, gm_pal
    ; gm_ramrod_front (1x1 at 1,0 of the 2x2 FRONT face)
    SKROWS gm_ramrod_front_rows, 1, 1
    SKROW "B"
    SKROWS_END
    align 8
    SKBMP gm_ramrod_front, gm_ramrod_front_rows, 1, 1, gm_pal
    ; gm_wrist_right (18x7 at 0,0 of the 18x7 RIGHT face)
    SKROWS gm_wrist_right_rows, 18, 7
    SKROW "AAAAAnAAAAAAAAAAnA"
    SKROW ".....n..........n."
    SKROW ".nnnnnnnn.......n."
    SKROW "...nnnnnnnnnnnnnnn"
    SKROW ".................."
    SKROW "AAA..............."
    SKROW "nnnnnnnnnnnnnnnnnn"
    SKROWS_END
    align 8
    SKBMP gm_wrist_right, gm_wrist_right_rows, 18, 7, gm_pal
    ; gm_wrist_left (18x7 at 0,0 of the 18x7 LEFT face)
    SKROWS gm_wrist_left_rows, 18, 7
    SKROW "AAAAAAAAAAAAAAAAAA"
    SKROW ".................."
    SKROW ".................."
    SKROW ".................."
    SKROW ".................."
    SKROW "nnnnnn............"
    SKROW "nnnnnnnnnnnnnnnnnn"
    SKROWS_END
    align 8
    SKBMP gm_wrist_left, gm_wrist_left_rows, 18, 7, gm_pal
    ; gm_wrist_top (6x18 at 0,0 of the 6x18 TOP face)
    SKROWS gm_wrist_top_rows, 6, 18
    SKROW "n....A"
    SKROW "n...AA"
    SKROW "n.cBAA"
    SKROW "n.cBAA"
    SKROW "n.cBAA"
    SKROW "n.CCAA"
    SKROW "n.CCAA"
    SKROW "n.cBAA"
    SKROW "n.cB.A"
    SKROW "n.cB.A"
    SKROW "n.cB.A"
    SKROW "n.cB.A"
    SKROW "n.cB.A"
    SKROW "n.cB.A"
    SKROW "n..A.A"
    SKROW "n..A.A"
    SKROW "n..A.A"
    SKROW "n..A.A"
    SKROWS_END
    align 8
    SKBMP gm_wrist_top, gm_wrist_top_rows, 6, 18, gm_pal
    ; gm_wrist_bottom (6x17 at 0,1 of the 6x18 BOTTOM face)
    SKROWS gm_wrist_bottom_rows, 6, 17
    SKROW "....N."
    SKROW ".N..N."
    SKROW ".N..N."
    SKROW ".N..N."
    SKROW ".N..N."
    SKROW ".N..N."
    SKROW ".N..N."
    SKROW "....N."
    SKROW "....N."
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "N....N"
    SKROW "N....N"
    SKROWS_END
    align 8
    SKBMP gm_wrist_bottom, gm_wrist_bottom_rows, 6, 17, gm_pal
    ; gm_wrist_back (4x5 at 1,1 of the 6x7 BACK face)
    SKROWS gm_wrist_back_rows, 4, 5
    SKROW "Aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROWS_END
    align 8
    SKBMP gm_wrist_back, gm_wrist_back_rows, 4, 5, gm_pal
    ; gm_wrist_front (4x5 at 1,1 of the 6x7 FRONT face)
    SKROWS gm_wrist_front_rows, 4, 5
    SKROW "Aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROWS_END
    align 8
    SKBMP gm_wrist_front, gm_wrist_front_rows, 4, 5, gm_pal
    ; gm_butt_a_right (8x8 at 0,0 of the 8x8 RIGHT face)
    SKROWS gm_butt_a_right_rows, 8, 8
    SKROW "AAAAAAAA"
    SKROW "nnnnnn.."
    SKROW "........"
    SKROW "........"
    SKROW "..nnnnnn"
    SKROW "........"
    SKROW "nnnn...."
    SKROW "nnnnnnnn"
    SKROWS_END
    align 8
    SKBMP gm_butt_a_right, gm_butt_a_right_rows, 8, 8, gm_pal
    ; gm_butt_a_left (8x8 at 0,0 of the 8x8 LEFT face)
    SKROWS gm_butt_a_left_rows, 8, 8
    SKROW "AAAAAAAA"
    SKROW "........"
    SKROW ".nnnnnnn"
    SKROW "...nnnn."
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "nnnnnnnn"
    SKROWS_END
    align 8
    SKBMP gm_butt_a_left, gm_butt_a_left_rows, 8, 8, gm_pal
    ; gm_butt_a_top (6x8 at 0,0 of the 6x8 TOP face)
    SKROWS gm_butt_a_top_rows, 6, 8
    SKROW "n....A"
    SKROW "n.n..A"
    SKROW "n.n..A"
    SKROW "n.nn.A"
    SKROW "n.nn.A"
    SKROW "n.nn.A"
    SKROW "n.nn.A"
    SKROW "n.nn.A"
    SKROWS_END
    align 8
    SKBMP gm_butt_a_top, gm_butt_a_top_rows, 6, 8, gm_pal
    ; gm_butt_a_bottom (3x6 at 2,2 of the 6x8 BOTTOM face)
    SKROWS gm_butt_a_bottom_rows, 3, 6
    SKROW "N.."
    SKROW "N.N"
    SKROW "N.N"
    SKROW "N.N"
    SKROW "N.N"
    SKROW "N.N"
    SKROWS_END
    align 8
    SKBMP gm_butt_a_bottom, gm_butt_a_bottom_rows, 3, 6, gm_pal
    ; gm_butt_a_back (4x6 at 1,1 of the 6x8 BACK face)
    SKROWS gm_butt_a_back_rows, 4, 6
    SKROW "Aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROW "aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROWS_END
    align 8
    SKBMP gm_butt_a_back, gm_butt_a_back_rows, 4, 6, gm_pal
    ; gm_butt_a_front (4x6 at 1,1 of the 6x8 FRONT face)
    SKROWS gm_butt_a_front_rows, 4, 6
    SKROW "Aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROW "aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROWS_END
    align 8
    SKBMP gm_butt_a_front, gm_butt_a_front_rows, 4, 6, gm_pal
    ; gm_butt_b_right (6x9 at 0,0 of the 6x9 RIGHT face)
    SKROWS gm_butt_b_right_rows, 6, 9
    SKROW "AAAAAA"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "AAAAAA"
    SKROW "......"
    SKROW "nnnnnn"
    SKROW "......"
    SKROW "nnnnnn"
    SKROWS_END
    align 8
    SKBMP gm_butt_b_right, gm_butt_b_right_rows, 6, 9, gm_pal
    ; gm_butt_b_left (6x9 at 0,0 of the 6x9 LEFT face)
    SKROWS gm_butt_b_left_rows, 6, 9
    SKROW "AAAAAA"
    SKROW ".AAAAA"
    SKROW "......"
    SKROW "...AAA"
    SKROW "......"
    SKROW "......"
    SKROW "...nnn"
    SKROW "...nnn"
    SKROW "nnnnnn"
    SKROWS_END
    align 8
    SKBMP gm_butt_b_left, gm_butt_b_left_rows, 6, 9, gm_pal
    ; gm_butt_b_top (6x6 at 0,0 of the 6x6 TOP face)
    SKROWS gm_butt_b_top_rows, 6, 6
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROWS_END
    align 8
    SKBMP gm_butt_b_top, gm_butt_b_top_rows, 6, 6, gm_pal
    ; gm_butt_b_bottom (4x4 at 2,2 of the 6x6 BOTTOM face)
    SKROWS gm_butt_b_bottom_rows, 4, 4
    SKROW "NN.."
    SKROW "NN.N"
    SKROW "NN.N"
    SKROW "NN.N"
    SKROWS_END
    align 8
    SKBMP gm_butt_b_bottom, gm_butt_b_bottom_rows, 4, 4, gm_pal
    ; gm_butt_b_back (4x7 at 1,1 of the 6x9 BACK face)
    SKROWS gm_butt_b_back_rows, 4, 7
    SKROW "Aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROW "aaaa"
    SKROW "aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROWS_END
    align 8
    SKBMP gm_butt_b_back, gm_butt_b_back_rows, 4, 7, gm_pal
    ; gm_butt_b_front (4x7 at 1,1 of the 6x9 FRONT face)
    SKROWS gm_butt_b_front_rows, 4, 7
    SKROW "Aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROW "aaaa"
    SKROW "aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROWS_END
    align 8
    SKBMP gm_butt_b_front, gm_butt_b_front_rows, 4, 7, gm_pal
    ; gm_plate_right (1x9 at 0,0 of the 1x9 RIGHT face)
    SKROWS gm_plate_right_rows, 1, 9
    SKROW "B"
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "c"
    SKROWS_END
    align 8
    SKBMP gm_plate_right, gm_plate_right_rows, 1, 9, gm_pal
    ; gm_plate_left (1x9 at 0,0 of the 1x9 LEFT face)
    SKROWS gm_plate_left_rows, 1, 9
    SKROW "B"
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "c"
    SKROWS_END
    align 8
    SKBMP gm_plate_left, gm_plate_left_rows, 1, 9, gm_pal
    ; gm_plate_top (6x1 at 0,0 of the 6x1 TOP face)
    SKROWS gm_plate_top_rows, 6, 1
    SKROW "c....B"
    SKROWS_END
    align 8
    SKBMP gm_plate_top, gm_plate_top_rows, 6, 1, gm_pal
    ; gm_plate_back (5x8 at 0,0 of the 6x9 BACK face)
    SKROWS gm_plate_back_rows, 5, 8
    SKROW "BBBBB"
    SKROW "BCbbC"
    SKROW "BbB.b"
    SKROW "BbB.b"
    SKROW "BbB.b"
    SKROW "BbB.b"
    SKROW "BbB.b"
    SKROW "BCbbC"
    SKROWS_END
    align 8
    SKBMP gm_plate_back, gm_plate_back_rows, 5, 8, gm_pal
    ; gm_plate_front (6x9 at 0,0 of the 6x9 FRONT face)
    SKROWS gm_plate_front_rows, 6, 9
    SKROW "BBBBBB"
    SKROW "c....B"
    SKROW "c....B"
    SKROW "c....B"
    SKROW "c....B"
    SKROW "c....B"
    SKROW "c....B"
    SKROW "c....B"
    SKROW "cccccc"
    SKROWS_END
    align 8
    SKBMP gm_plate_front, gm_plate_front_rows, 6, 9, gm_pal
    ; gm_lock_right (10x4 at 0,1 of the 10x5 RIGHT face)
    SKROWS gm_lock_right_rows, 10, 4
    SKROW "s.......ks"
    SKROW "s.KsBcsKks"
    SKROW "s.kkkkkkks"
    SKROW "kkkkkkkkkk"
    SKROWS_END
    align 8
    SKBMP gm_lock_right, gm_lock_right_rows, 10, 4, gm_pal
    ; gm_lock_left (10x5 at 0,0 of the 10x5 LEFT face)
    SKROWS gm_lock_left_rows, 10, 5
    SKROW "SSSSSSSSSS"
    SKROW ".........."
    SKROW ".........."
    SKROW ".........."
    SKROW "kkkkkkkkkk"
    SKROWS_END
    align 8
    SKBMP gm_lock_left, gm_lock_left_rows, 10, 5, gm_pal
    ; gm_lock_back (1x5 at 0,0 of the 1x5 BACK face)
    SKROWS gm_lock_back_rows, 1, 5
    SKROW "S"
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "k"
    SKROWS_END
    align 8
    SKBMP gm_lock_back, gm_lock_back_rows, 1, 5, gm_pal
    ; gm_lock_front (1x5 at 0,0 of the 1x5 FRONT face)
    SKROWS gm_lock_front_rows, 1, 5
    SKROW "S"
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "k"
    SKROWS_END
    align 8
    SKBMP gm_lock_front, gm_lock_front_rows, 1, 5, gm_pal
    ; gm_pan_top (1x3 at 0,0 of the 2x3 TOP face)
    SKROWS gm_pan_top_rows, 1, 3
    SKROW "c"
    SKROW "c"
    SKROW "c"
    SKROWS_END
    align 8
    SKBMP gm_pan_top, gm_pan_top_rows, 1, 3, gm_pal
    ; gm_flint_right (3x2 at 0,0 of the 3x2 RIGHT face)
    SKROWS gm_flint_right_rows, 3, 2
    SKROW "J.."
    SKROW "Jff"
    SKROWS_END
    align 8
    SKBMP gm_flint_right, gm_flint_right_rows, 3, 2, gm_pal
    ; gm_flint_left (3x2 at 0,0 of the 3x2 LEFT face)
    SKROWS gm_flint_left_rows, 3, 2
    SKROW "..J"
    SKROW "ffJ"
    SKROWS_END
    align 8
    SKBMP gm_flint_left, gm_flint_left_rows, 3, 2, gm_pal
    ; gm_flint_top (1x3 at 1,0 of the 2x3 TOP face)
    SKROWS gm_flint_top_rows, 1, 3
    SKROW "i"
    SKROW "i"
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gm_flint_top, gm_flint_top_rows, 1, 3, gm_pal
    ; gm_flint_back (2x1 at 0,0 of the 2x2 BACK face)
    SKROWS gm_flint_back_rows, 2, 1
    SKROW "ii"
    SKROWS_END
    align 8
    SKBMP gm_flint_back, gm_flint_back_rows, 2, 1, gm_pal
    ; gm_cock_right (2x2 at 0,1 of the 2x3 RIGHT face)
    SKROWS gm_cock_right_rows, 2, 2
    SKROW "s."
    SKROW "Kk"
    SKROWS_END
    align 8
    SKBMP gm_cock_right, gm_cock_right_rows, 2, 2, gm_pal
    ; gm_cock_left (2x2 at 0,1 of the 2x3 LEFT face)
    SKROWS gm_cock_left_rows, 2, 2
    SKROW "ss"
    SKROW "kk"
    SKROWS_END
    align 8
    SKBMP gm_cock_left, gm_cock_left_rows, 2, 2, gm_pal
    ; gm_cock_top (1x2 at 0,0 of the 2x2 TOP face)
    SKROWS gm_cock_top_rows, 1, 2
    SKROW "k"
    SKROW "k"
    SKROWS_END
    align 8
    SKBMP gm_cock_top, gm_cock_top_rows, 1, 2, gm_pal
    ; gm_cock_back (2x2 at 0,1 of the 2x3 BACK face)
    SKROWS gm_cock_back_rows, 2, 2
    SKROW "ss"
    SKROW "kk"
    SKROWS_END
    align 8
    SKBMP gm_cock_back, gm_cock_back_rows, 2, 2, gm_pal
    ; gm_cock_front (2x2 at 0,1 of the 2x3 FRONT face)
    SKROWS gm_cock_front_rows, 2, 2
    SKROW "ss"
    SKROW "kk"
    SKROWS_END
    align 8
    SKBMP gm_cock_front, gm_cock_front_rows, 2, 2, gm_pal
    ; gm_sideplate_right (6x2 at 0,1 of the 6x3 RIGHT face)
    SKROWS gm_sideplate_right_rows, 6, 2
    SKROW "bbbbbb"
    SKROW "cccccc"
    SKROWS_END
    align 8
    SKBMP gm_sideplate_right, gm_sideplate_right_rows, 6, 2, gm_pal
    ; gm_sideplate_left (6x2 at 0,1 of the 6x3 LEFT face)
    SKROWS gm_sideplate_left_rows, 6, 2
    SKROW "cCCbCC"
    SKROW "cCcCcc"
    SKROWS_END
    align 8
    SKBMP gm_sideplate_left, gm_sideplate_left_rows, 6, 2, gm_pal
    ; gm_sideplate_back (1x2 at 0,1 of the 1x3 BACK face)
    SKROWS gm_sideplate_back_rows, 1, 2
    SKROW "b"
    SKROW "c"
    SKROWS_END
    align 8
    SKBMP gm_sideplate_back, gm_sideplate_back_rows, 1, 2, gm_pal
    ; gm_sideplate_front (1x2 at 0,1 of the 1x3 FRONT face)
    SKROWS gm_sideplate_front_rows, 1, 2
    SKROW "b"
    SKROW "c"
    SKROWS_END
    align 8
    SKBMP gm_sideplate_front, gm_sideplate_front_rows, 1, 2, gm_pal
    ; gm_guard_f_right (1x1 at 0,1 of the 1x2 RIGHT face)
    SKROWS gm_guard_f_right_rows, 1, 1
    SKROW "c"
    SKROWS_END
    align 8
    SKBMP gm_guard_f_right, gm_guard_f_right_rows, 1, 1, gm_pal
    ; gm_guard_f_left (1x1 at 0,1 of the 1x2 LEFT face)
    SKROWS gm_guard_f_left_rows, 1, 1
    SKROW "c"
    SKROWS_END
    align 8
    SKBMP gm_guard_f_left, gm_guard_f_left_rows, 1, 1, gm_pal
    ; gm_guard_f_top (1x1 at 0,0 of the 2x1 TOP face)
    SKROWS gm_guard_f_top_rows, 1, 1
    SKROW "c"
    SKROWS_END
    align 8
    SKBMP gm_guard_f_top, gm_guard_f_top_rows, 1, 1, gm_pal
    ; gm_guard_f_back (2x1 at 0,1 of the 2x2 BACK face)
    SKROWS gm_guard_f_back_rows, 2, 1
    SKROW "cc"
    SKROWS_END
    align 8
    SKBMP gm_guard_f_back, gm_guard_f_back_rows, 2, 1, gm_pal
    ; gm_guard_f_front (2x1 at 0,1 of the 2x2 FRONT face)
    SKROWS gm_guard_f_front_rows, 2, 1
    SKROW "cc"
    SKROWS_END
    align 8
    SKBMP gm_guard_f_front, gm_guard_f_front_rows, 2, 1, gm_pal
    ; gm_guard_b_top (1x9 at 0,0 of the 2x9 TOP face)
    SKROWS gm_guard_b_top_rows, 1, 9
    SKROW "b"
    SKROW "b"
    SKROW "b"
    SKROW "b"
    SKROW "b"
    SKROW "b"
    SKROW "b"
    SKROW "b"
    SKROW "b"
    SKROWS_END
    align 8
    SKBMP gm_guard_b_top, gm_guard_b_top_rows, 1, 9, gm_pal
    ; gm_trigger_right (1x1 at 0,0 of the 1x2 RIGHT face)
    SKROWS gm_trigger_right_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gm_trigger_right, gm_trigger_right_rows, 1, 1, gm_pal
    ; gm_trigger_left (1x1 at 0,0 of the 1x2 LEFT face)
    SKROWS gm_trigger_left_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gm_trigger_left, gm_trigger_left_rows, 1, 1, gm_pal
    ; gm_trigger_top (1x1 at 1,0 of the 2x1 TOP face)
    SKROWS gm_trigger_top_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gm_trigger_top, gm_trigger_top_rows, 1, 1, gm_pal
    ; gm_trigger_back (2x1 at 0,0 of the 2x2 BACK face)
    SKROWS gm_trigger_back_rows, 2, 1
    SKROW "ii"
    SKROWS_END
    align 8
    SKBMP gm_trigger_back, gm_trigger_back_rows, 2, 1, gm_pal
    ; gm_trigger_front (2x1 at 0,0 of the 2x2 FRONT face)
    SKROWS gm_trigger_front_rows, 2, 1
    SKROW "ii"
    SKROWS_END
    align 8
    SKBMP gm_trigger_front, gm_trigger_front_rows, 2, 1, gm_pal

section .data
SKMODEL_BEGIN m_gun_musket, 64, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART gm_barrel_a, -2, 1, -68, 4, 4, 21, 0, 0                  ; blued barrel, polished muzzle, breech with a vent
    PART gm_barrel_b, -2, 1, -47, 4, 4, 21, 0, 0                  ; blued barrel, polished muzzle, breech with a vent
    PART gm_barrel_c, -2, 1, -26, 4, 4, 20, 0, 0                  ; blued barrel, polished muzzle, breech with a vent
    PART gm_band_a, -3, -4, -38, 6, 9, 2, 3, 0                    ; brass barrel band
    PART_AS gm_band_b, gm_band_a, -3, -4, -22, 3, 0               ; mirrored twin of band_a
    PART gm_fore_a, -3, -4, -46, 6, 6, 18, 0, 0                   ; walnut fore-end with barrel pins
    PART gm_fore_b, -3, -4, -28, 6, 6, 18, 0, 0                   ; walnut fore-end with barrel pins
    PART gm_cap, -3, -4, -48, 6, 6, 2, 0, 0                       ; brass nose cap
    PART gm_ramrod, -1, -1, -60, 2, 2, 13, 0, 0                   ; iron ramrod with a brass tip
    PART gm_wrist, -3, -5, -10, 6, 7, 18, 0, 0                    ; walnut wrist: the lock mortise, a brass tang strip
    PART gm_butt_a, -3, -7, 8, 6, 8, 8, 0, 0                      ; walnut butt, upper step
    PART gm_butt_b, -3, -9, 16, 6, 9, 6, 0, 0                     ; walnut butt, lower step
    PART gm_plate, -3, -9, 22, 6, 9, 1, 0, 0                      ; brass butt plate
    PART gm_lock, 3, -1, -8, 1, 5, 10, 0, 0                       ; lock plate, engraved
    PART gm_pan, 3, 4, -6, 2, 1, 3, 0, 0                          ; priming pan
    PART gm_flint, 3, 5, -6, 2, 2, 3, 0, 0                        ; flint in the jaws
    PART gm_cock, 3, 4, -3, 2, 3, 2, 0, 0                         ; cock
    PART gm_sideplate, -4, 0, -4, 1, 3, 6, 0, 0                   ; brass side plate with a serpent
    PART gm_guard_f, -1, -7, -9, 2, 2, 1, 0, 0                    ; trigger guard, front post
    PART gm_guard_b, -1, -8, -9, 2, 1, 9, 0, 0                    ; trigger guard, bar
    PART_AS gm_guard_r, gm_guard_f, -1, -7, -1, 0, 0              ; trigger guard, rear post
    PART gm_trigger, -1, -7, -5, 2, 2, 1, 0, 0                    ; trigger
    PART gm_bead, -1, 5, -67, 2, 1, 1, 0, 0                       ; bead sight
SKMODEL_PAINT
    ; --- gm_barrel_a  (blued barrel, polished muzzle, breech with a vent)
    SK_FILL gm_barrel_a, SKM_FRONT, GUN_STEEL_1, 0
    SK_FILL gm_barrel_a, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK, GUN_STEEL_2, 0
    SK_FILL gm_barrel_a, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gm_barrel_a, SKF_RIGHT, 0, 0, gm_barrel_a_right
    SK_BMP gm_barrel_a, SKF_LEFT, 0, 0, gm_barrel_a_left
    SK_BMP gm_barrel_a, SKF_TOP, 0, 0, gm_barrel_a_top
    SK_BMP gm_barrel_a, SKF_FRONT, 0, 1, gm_barrel_a_front
    ; --- gm_barrel_b  (blued barrel, polished muzzle, breech with a vent)
    SK_FILL gm_barrel_b, SKM_RIGHT | SKM_LEFT | SKM_BACK | SKM_FRONT, GUN_STEEL_3, 0
    SK_FILL gm_barrel_b, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gm_barrel_b, SKM_TOP, GUN_STEEL_2, 0
    SK_BMP gm_barrel_b, SKF_RIGHT, 0, 0, gm_barrel_b_right
    SK_BMP gm_barrel_b, SKF_LEFT, 0, 0, gm_barrel_b_left
    SK_BMP gm_barrel_b, SKF_TOP, 0, 0, gm_barrel_b_top
    ; --- gm_barrel_c  (blued barrel, polished muzzle, breech with a vent)
    SK_FILL gm_barrel_c, SKM_RIGHT | SKM_LEFT | SKM_BACK | SKM_FRONT, GUN_STEEL_3, 0
    SK_FILL gm_barrel_c, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gm_barrel_c, SKM_TOP, GUN_STEEL_2, 0
    SK_BMP gm_barrel_c, SKF_RIGHT, 0, 0, gm_barrel_c_right
    SK_BMP gm_barrel_c, SKF_LEFT, 0, 0, gm_barrel_c_left
    SK_BMP gm_barrel_c, SKF_TOP, 0, 0, gm_barrel_c_top
    ; --- gm_band_a  (brass barrel band)
    SK_FILL gm_band_a, SKM_BACK | SKM_FRONT, AC_GOLD_3, 0
    SK_FILL gm_band_a, SKM_BOTTOM, GUN_BRASS_DEEP, 0
    SK_FILL gm_band_a, SKM_RIGHT | SKM_LEFT | SKM_TOP, AC_GOLD_2, 0
    SK_BMP gm_band_a, SKF_RIGHT, 0, 0, gm_band_a_right
    SK_BMP gm_band_a, SKF_LEFT, 0, 0, gm_band_a_left
    SK_BMP gm_band_a, SKF_TOP, 0, 0, gm_band_a_top
    SK_BMP gm_band_a, SKF_BACK, 0, 0, gm_band_a_back
    SK_BMP gm_band_a, SKF_FRONT, 0, 0, gm_band_a_front
    ; --- gm_fore_a  (walnut fore-end with barrel pins)
    SK_FILL gm_fore_a, SKM_LEFT | SKM_BOTTOM | SKM_BACK | SKM_FRONT, GUN_WALNUT_3, 0
    SK_FILL gm_fore_a, SKM_RIGHT | SKM_TOP, GUN_WALNUT_2, 15
    SK_BMP gm_fore_a, SKF_RIGHT, 0, 0, gm_fore_a_right
    SK_BMP gm_fore_a, SKF_LEFT, 0, 1, gm_fore_a_left
    SK_BMP gm_fore_a, SKF_TOP, 0, 0, gm_fore_a_top
    SK_BMP gm_fore_a, SKF_BOTTOM, 0, 0, gm_fore_a_bottom
    SK_BMP gm_fore_a, SKF_FRONT, 1, 1, gm_fore_a_front
    SK_GRAD gm_fore_a, SKM_RIGHT | SKM_LEFT, 256, 228
    ; --- gm_fore_b  (walnut fore-end with barrel pins)
    SK_FILL gm_fore_b, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_FRONT, GUN_WALNUT_2, 15
    SK_FILL gm_fore_b, SKM_BOTTOM | SKM_BACK, GUN_WALNUT_3, 0
    SK_BMP gm_fore_b, SKF_RIGHT, 0, 0, gm_fore_b_right
    SK_BMP gm_fore_b, SKF_LEFT, 0, 0, gm_fore_b_left
    SK_BMP gm_fore_b, SKF_TOP, 0, 0, gm_fore_b_top
    SK_BMP gm_fore_b, SKF_BOTTOM, 0, 0, gm_fore_b_bottom
    SK_BMP gm_fore_b, SKF_BACK, 1, 1, gm_fore_b_back
    SK_GRAD gm_fore_b, SKM_RIGHT | SKM_LEFT, 256, 228
    ; --- gm_cap  (brass nose cap)
    SK_FILL gm_cap, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, AC_GOLD_3, 0
    SK_FILL gm_cap, SKM_BOTTOM, GUN_BRASS_DEEP, 0
    SK_BMP gm_cap, SKF_RIGHT, 0, 0, gm_cap_right
    SK_BMP gm_cap, SKF_LEFT, 0, 0, gm_cap_left
    SK_BMP gm_cap, SKF_TOP, 0, 0, gm_cap_top
    SK_BMP gm_cap, SKF_BACK, 0, 0, gm_cap_back
    SK_BMP gm_cap, SKF_FRONT, 0, 0, gm_cap_front
    ; --- gm_ramrod  (iron ramrod with a brass tip)
    SK_FILL gm_ramrod, SKM_FRONT, AC_GOLD_3, 0
    SK_FILL gm_ramrod, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK, AC_IRON_4, 0
    SK_FILL gm_ramrod, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gm_ramrod, SKF_RIGHT, 0, 0, gm_ramrod_right
    SK_BMP gm_ramrod, SKF_LEFT, 0, 0, gm_ramrod_left
    SK_BMP gm_ramrod, SKF_TOP, 0, 0, gm_ramrod_top
    SK_BMP gm_ramrod, SKF_BACK, 0, 0, gm_ramrod_back
    SK_BMP gm_ramrod, SKF_FRONT, 1, 0, gm_ramrod_front
    ; --- gm_wrist  (walnut wrist: the lock mortise, a brass tang strip)
    SK_FILL gm_wrist, SKM_BOTTOM | SKM_BACK | SKM_FRONT, GUN_WALNUT_3, 0
    SK_FILL gm_wrist, SKM_RIGHT | SKM_LEFT | SKM_TOP, GUN_WALNUT_2, 15
    SK_BMP gm_wrist, SKF_RIGHT, 0, 0, gm_wrist_right
    SK_BMP gm_wrist, SKF_LEFT, 0, 0, gm_wrist_left
    SK_BMP gm_wrist, SKF_TOP, 0, 0, gm_wrist_top
    SK_BMP gm_wrist, SKF_BOTTOM, 0, 1, gm_wrist_bottom
    SK_BMP gm_wrist, SKF_BACK, 1, 1, gm_wrist_back
    SK_BMP gm_wrist, SKF_FRONT, 1, 1, gm_wrist_front
    SK_GRAD gm_wrist, SKM_RIGHT | SKM_LEFT, 256, 228
    ; --- gm_butt_a  (walnut butt, upper step)
    SK_FILL gm_butt_a, SKM_BOTTOM | SKM_BACK | SKM_FRONT, GUN_WALNUT_3, 0
    SK_FILL gm_butt_a, SKM_RIGHT | SKM_LEFT | SKM_TOP, GUN_WALNUT_2, 15
    SK_BMP gm_butt_a, SKF_RIGHT, 0, 0, gm_butt_a_right
    SK_BMP gm_butt_a, SKF_LEFT, 0, 0, gm_butt_a_left
    SK_BMP gm_butt_a, SKF_TOP, 0, 0, gm_butt_a_top
    SK_BMP gm_butt_a, SKF_BOTTOM, 2, 2, gm_butt_a_bottom
    SK_BMP gm_butt_a, SKF_BACK, 1, 1, gm_butt_a_back
    SK_BMP gm_butt_a, SKF_FRONT, 1, 1, gm_butt_a_front
    SK_GRAD gm_butt_a, SKM_RIGHT | SKM_LEFT, 256, 228
    ; --- gm_butt_b  (walnut butt, lower step)
    SK_FILL gm_butt_b, SKM_BOTTOM | SKM_BACK | SKM_FRONT, GUN_WALNUT_3, 0
    SK_FILL gm_butt_b, SKM_RIGHT | SKM_LEFT | SKM_TOP, GUN_WALNUT_2, 15
    SK_BMP gm_butt_b, SKF_RIGHT, 0, 0, gm_butt_b_right
    SK_BMP gm_butt_b, SKF_LEFT, 0, 0, gm_butt_b_left
    SK_BMP gm_butt_b, SKF_TOP, 0, 0, gm_butt_b_top
    SK_BMP gm_butt_b, SKF_BOTTOM, 2, 2, gm_butt_b_bottom
    SK_BMP gm_butt_b, SKF_BACK, 1, 1, gm_butt_b_back
    SK_BMP gm_butt_b, SKF_FRONT, 1, 1, gm_butt_b_front
    SK_GRAD gm_butt_b, SKM_RIGHT | SKM_LEFT, 256, 228
    ; --- gm_plate  (brass butt plate)
    SK_FILL gm_plate, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_FRONT, AC_GOLD_3, 0
    SK_FILL gm_plate, SKM_BACK, AC_GOLD_4, 0
    SK_FILL gm_plate, SKM_BOTTOM, GUN_BRASS_DEEP, 0
    SK_BMP gm_plate, SKF_RIGHT, 0, 0, gm_plate_right
    SK_BMP gm_plate, SKF_LEFT, 0, 0, gm_plate_left
    SK_BMP gm_plate, SKF_TOP, 0, 0, gm_plate_top
    SK_BMP gm_plate, SKF_BACK, 0, 0, gm_plate_back
    SK_BMP gm_plate, SKF_FRONT, 0, 0, gm_plate_front
    ; --- gm_lock  (lock plate, engraved)
    SK_FILL gm_lock, SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, GUN_STEEL_2, 0
    SK_FILL gm_lock, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gm_lock, SKM_RIGHT, GUN_STEEL_1, 0
    SK_BMP gm_lock, SKF_RIGHT, 0, 1, gm_lock_right
    SK_BMP gm_lock, SKF_LEFT, 0, 0, gm_lock_left
    SK_BMP gm_lock, SKF_BACK, 0, 0, gm_lock_back
    SK_BMP gm_lock, SKF_FRONT, 0, 0, gm_lock_front
    ; --- gm_pan  (priming pan)
    SK_FILL gm_pan, SKM_RIGHT | SKM_LEFT | SKM_BACK | SKM_FRONT, AC_GOLD_3, 0
    SK_FILL gm_pan, SKM_BOTTOM, GUN_BRASS_DEEP, 0
    SK_FILL gm_pan, SKM_TOP, AC_GOLD_2, 0
    SK_BMP gm_pan, SKF_TOP, 0, 0, gm_pan_top
    ; --- gm_flint  (flint in the jaws)
    SK_FILL gm_flint, SKM_FRONT, GUN_FLINT, 0
    SK_FILL gm_flint, SKM_TOP | SKM_BACK, AC_IRON_4, 0
    SK_FILL gm_flint, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gm_flint, SKM_RIGHT | SKM_LEFT, GUN_FLINT_HI, 0
    SK_BMP gm_flint, SKF_RIGHT, 0, 0, gm_flint_right
    SK_BMP gm_flint, SKF_LEFT, 0, 0, gm_flint_left
    SK_BMP gm_flint, SKF_TOP, 1, 0, gm_flint_top
    SK_BMP gm_flint, SKF_BACK, 0, 0, gm_flint_back
    ; --- gm_cock  (cock)
    SK_FILL gm_cock, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, GUN_STEEL_1, 0
    SK_FILL gm_cock, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gm_cock, SKF_RIGHT, 0, 1, gm_cock_right
    SK_BMP gm_cock, SKF_LEFT, 0, 1, gm_cock_left
    SK_BMP gm_cock, SKF_TOP, 0, 0, gm_cock_top
    SK_BMP gm_cock, SKF_BACK, 0, 1, gm_cock_back
    SK_BMP gm_cock, SKF_FRONT, 0, 1, gm_cock_front
    ; --- gm_sideplate  (brass side plate with a serpent)
    SK_FILL gm_sideplate, SKM_RIGHT | SKM_LEFT | SKM_BACK | SKM_FRONT, AC_GOLD_2, 0
    SK_FILL gm_sideplate, SKM_BOTTOM, GUN_BRASS_DEEP, 0
    SK_FILL gm_sideplate, SKM_TOP, AC_GOLD_3, 0
    SK_BMP gm_sideplate, SKF_RIGHT, 0, 1, gm_sideplate_right
    SK_BMP gm_sideplate, SKF_LEFT, 0, 1, gm_sideplate_left
    SK_BMP gm_sideplate, SKF_BACK, 0, 1, gm_sideplate_back
    SK_BMP gm_sideplate, SKF_FRONT, 0, 1, gm_sideplate_front
    ; --- gm_guard_f  (trigger guard, front post)
    SK_FILL gm_guard_f, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, AC_GOLD_2, 0
    SK_FILL gm_guard_f, SKM_BOTTOM, GUN_BRASS_DEEP, 0
    SK_BMP gm_guard_f, SKF_RIGHT, 0, 1, gm_guard_f_right
    SK_BMP gm_guard_f, SKF_LEFT, 0, 1, gm_guard_f_left
    SK_BMP gm_guard_f, SKF_TOP, 0, 0, gm_guard_f_top
    SK_BMP gm_guard_f, SKF_BACK, 0, 1, gm_guard_f_back
    SK_BMP gm_guard_f, SKF_FRONT, 0, 1, gm_guard_f_front
    ; --- gm_guard_b  (trigger guard, bar)
    SK_FILL gm_guard_b, SKM_RIGHT | SKM_LEFT | SKM_BACK | SKM_FRONT, AC_GOLD_3, 0
    SK_FILL gm_guard_b, SKM_BOTTOM, GUN_BRASS_DEEP, 0
    SK_FILL gm_guard_b, SKM_TOP, AC_GOLD_2, 0
    SK_BMP gm_guard_b, SKF_TOP, 0, 0, gm_guard_b_top
    ; --- gm_trigger  (trigger)
    SK_FILL gm_trigger, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, AC_IRON_4, 0
    SK_FILL gm_trigger, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gm_trigger, SKF_RIGHT, 0, 0, gm_trigger_right
    SK_BMP gm_trigger, SKF_LEFT, 0, 0, gm_trigger_left
    SK_BMP gm_trigger, SKF_TOP, 1, 0, gm_trigger_top
    SK_BMP gm_trigger, SKF_BACK, 0, 0, gm_trigger_back
    SK_BMP gm_trigger, SKF_FRONT, 0, 0, gm_trigger_front
    ; --- gm_bead  (bead sight)
    SK_FILL gm_bead, SKM_RIGHT | SKM_LEFT | SKM_FRONT, AC_GOLD_3, 0
    SK_FILL gm_bead, SKM_TOP | SKM_BACK, AC_GOLD_2, 0
    SK_FILL gm_bead, SKM_BOTTOM, GUN_BRASS_DEEP, 0
SKMODEL_END

; ===================================================================================================
; m_gun_shotgun
; ===================================================================================================
; The shotgun: two blued barrels under a ventilated rib with a brass bead, a steel band, a walnut pump forend with grip
; grooves, a dark engraved receiver with a brass inlay, two hammers and a top lever, a stepped walnut stock with wrist
; checkering and a ribbed rubber pad, an iron trigger guard and trigger.
; Model space (texels, 64 per block, muzzle -Z): the old boxes x 64 give the extents (barrels 2 x 2.9 x 2.9 x 44,
; receiver 5.8 x 6.4 x 15, stock 5.1 x 10.2 x 22, muzzle at (0, 2.7, -51.8)); this model stays within 2 texels of them
; (x -3..3, y -8..6, z -52..30). The barrels and the rib are cut along Z.
section .rodata
; The characters of every gs_ bitmap:
;  A walnut highlight, B brass highlight, C brass deep, D dark steel highlight, E dark steel deep, J iron shade
;  K steel deep, N walnut deep, S steel edge highlight, a walnut, b brass, c brass shade, d dark steel
;  e dark steel shade, g steel glint, i iron highlight, j iron, k steel shade, n walnut shade, s blued steel
;  x bore, pure dark
align 8
gs_pal:
    PALC 'A', GUN_WALNUT_1
    PALC 'B', AC_GOLD_2
    PALC 'C', GUN_BRASS_DEEP
    PALC 'D', GUN_DARK_1
    PALC 'E', GUN_DARK_4
    PALC 'J', AC_IRON_4
    PALC 'K', GUN_STEEL_4
    PALC 'N', GUN_WALNUT_4
    PALC 'S', GUN_STEEL_1
    PALC 'a', GUN_WALNUT_2
    PALC 'b', AC_GOLD_3
    PALC 'c', AC_GOLD_4
    PALC 'd', GUN_DARK_2
    PALC 'e', GUN_DARK_3
    PALC 'g', GUN_STEEL_0
    PALC 'i', AC_IRON_2
    PALC 'j', AC_IRON_3
    PALC 'k', GUN_STEEL_3
    PALC 'n', GUN_WALNUT_3
    PALC 's', GUN_STEEL_2
    PALC 'x', GUN_BORE
    dq 0

    ; gs_barrel_l_a_right (22x3 at 0,0 of the 22x3 RIGHT face)
    SKROWS gs_barrel_l_a_right_rows, 22, 3
    SKROW "...........g......Kggg"
    SKROW "skksssssssssssssssK..."
    SKROW "kkkkkkkkkkkkkkkkkkK..."
    SKROWS_END
    align 8
    SKBMP gs_barrel_l_a_right, gs_barrel_l_a_right_rows, 22, 3, gs_pal
    ; gs_barrel_l_a_left (22x3 at 0,0 of the 22x3 LEFT face)
    SKROWS gs_barrel_l_a_left_rows, 22, 3
    SKROW "gggK......g..........."
    SKROW "...Kssssssssssssssskks"
    SKROW "...Kkkkkkkkkkkkkkkkkkk"
    SKROWS_END
    align 8
    SKBMP gs_barrel_l_a_left, gs_barrel_l_a_left_rows, 22, 3, gs_pal
    ; gs_barrel_l_a_top (3x19 at 0,0 of the 3x22 TOP face)
    SKROWS gs_barrel_l_a_top_rows, 3, 19
    SKROW ".s."
    SKROW ".s."
    SKROW ".s."
    SKROW ".s."
    SKROW ".s."
    SKROW ".s."
    SKROW ".s."
    SKROW ".s."
    SKROW ".s."
    SKROW ".s."
    SKROW ".s."
    SKROW ".s."
    SKROW ".s."
    SKROW ".s."
    SKROW ".s."
    SKROW ".s."
    SKROW ".s."
    SKROW ".s."
    SKROW "KKK"
    SKROWS_END
    align 8
    SKBMP gs_barrel_l_a_top, gs_barrel_l_a_top_rows, 3, 19, gs_pal
    ; gs_barrel_l_a_front (3x2 at 0,1 of the 3x3 FRONT face)
    SKROWS gs_barrel_l_a_front_rows, 3, 2
    SKROW ".xk"
    SKROW "kkk"
    SKROWS_END
    align 8
    SKBMP gs_barrel_l_a_front, gs_barrel_l_a_front_rows, 3, 2, gs_pal
    ; gs_barrel_l_b_right (22x3 at 0,0 of the 22x3 RIGHT face)
    SKROWS gs_barrel_l_b_right_rows, 22, 3
    SKROW "KSSSSS.SSSSSgSSSSSSSSS"
    SKROW "Ksssss.sssssssssssssss"
    SKROW "K....................."
    SKROWS_END
    align 8
    SKBMP gs_barrel_l_b_right, gs_barrel_l_b_right_rows, 22, 3, gs_pal
    ; gs_barrel_l_b_left (22x3 at 0,0 of the 22x3 LEFT face)
    SKROWS gs_barrel_l_b_left_rows, 22, 3
    SKROW "SSSSSSSSSgSSSSS.SSSSSK"
    SKROW "sssssssssssssss.sssssK"
    SKROW ".....................K"
    SKROWS_END
    align 8
    SKBMP gs_barrel_l_b_left, gs_barrel_l_b_left_rows, 22, 3, gs_pal
    ; gs_barrel_l_b_top (1x22 at 1,0 of the 3x22 TOP face)
    SKROWS gs_barrel_l_b_top_rows, 1, 22
    SKROW "s"
    SKROW "s"
    SKROW "s"
    SKROW "s"
    SKROW "s"
    SKROW "s"
    SKROW "s"
    SKROW "s"
    SKROW "s"
    SKROW "s"
    SKROW "s"
    SKROW "s"
    SKROW "s"
    SKROW "s"
    SKROW "s"
    SKROW "s"
    SKROW "s"
    SKROW "s"
    SKROW "s"
    SKROW "s"
    SKROW "s"
    SKROW "s"
    SKROWS_END
    align 8
    SKBMP gs_barrel_l_b_top, gs_barrel_l_b_top_rows, 1, 22, gs_pal
    ; gs_rib_a_right (19x1 at 0,0 of the 21x1 RIGHT face)
    SKROWS gs_rib_a_right_rows, 19, 1
    SKROW "J..J..J..J..J..J..J"
    SKROWS_END
    align 8
    SKBMP gs_rib_a_right, gs_rib_a_right_rows, 19, 1, gs_pal
    ; gs_rib_a_left (19x1 at 0,0 of the 21x1 LEFT face)
    SKROWS gs_rib_a_left_rows, 19, 1
    SKROW "J..J..J..J..J..J..J"
    SKROWS_END
    align 8
    SKBMP gs_rib_a_left, gs_rib_a_left_rows, 19, 1, gs_pal
    ; gs_rib_a_top (2x21 at 0,0 of the 2x21 TOP face)
    SKROWS gs_rib_a_top_rows, 2, 21
    SKROW "ji"
    SKROW ".."
    SKROW "ji"
    SKROW "ji"
    SKROW ".."
    SKROW "ji"
    SKROW "ji"
    SKROW ".."
    SKROW "ji"
    SKROW "ji"
    SKROW ".."
    SKROW "ji"
    SKROW "ji"
    SKROW ".."
    SKROW "ji"
    SKROW "ji"
    SKROW ".."
    SKROW "ji"
    SKROW "ji"
    SKROW ".."
    SKROW "ji"
    SKROWS_END
    align 8
    SKBMP gs_rib_a_top, gs_rib_a_top_rows, 2, 21, gs_pal
    ; gs_rib_b_right (19x1 at 0,0 of the 21x1 RIGHT face)
    SKROWS gs_rib_b_right_rows, 19, 1
    SKROW "J..J..J..J..J..J..J"
    SKROWS_END
    align 8
    SKBMP gs_rib_b_right, gs_rib_b_right_rows, 19, 1, gs_pal
    ; gs_rib_b_left (19x1 at 0,0 of the 21x1 LEFT face)
    SKROWS gs_rib_b_left_rows, 19, 1
    SKROW "J..J..J..J..J..J..J"
    SKROWS_END
    align 8
    SKBMP gs_rib_b_left, gs_rib_b_left_rows, 19, 1, gs_pal
    ; gs_rib_b_top (2x21 at 0,0 of the 2x21 TOP face)
    SKROWS gs_rib_b_top_rows, 2, 21
    SKROW "ji"
    SKROW ".."
    SKROW "ji"
    SKROW "ji"
    SKROW ".."
    SKROW "ji"
    SKROW "ji"
    SKROW ".."
    SKROW "ji"
    SKROW "ji"
    SKROW ".."
    SKROW "ji"
    SKROW "ji"
    SKROW ".."
    SKROW "ji"
    SKROW "ji"
    SKROW ".."
    SKROW "ji"
    SKROW "ji"
    SKROW ".."
    SKROW "ji"
    SKROWS_END
    align 8
    SKBMP gs_rib_b_top, gs_rib_b_top_rows, 2, 21, gs_pal
    ; gs_band_right (1x4 at 0,0 of the 2x4 RIGHT face)
    SKROWS gs_band_right_rows, 1, 4
    SKROW "S"
    SKROW "b"
    SKROW "c"
    SKROW "S"
    SKROWS_END
    align 8
    SKBMP gs_band_right, gs_band_right_rows, 1, 4, gs_pal
    ; gs_band_left (1x4 at 1,0 of the 2x4 LEFT face)
    SKROWS gs_band_left_rows, 1, 4
    SKROW "k"
    SKROW "b"
    SKROW "c"
    SKROW "k"
    SKROWS_END
    align 8
    SKBMP gs_band_left, gs_band_left_rows, 1, 4, gs_pal
    ; gs_band_top (6x1 at 0,1 of the 6x2 TOP face)
    SKROWS gs_band_top_rows, 6, 1
    SKROW "ssssss"
    SKROWS_END
    align 8
    SKBMP gs_band_top, gs_band_top_rows, 6, 1, gs_pal
    ; gs_band_back (6x3 at 0,1 of the 6x4 BACK face)
    SKROWS gs_band_back_rows, 6, 3
    SKROW ".ssssk"
    SKROW ".ssssk"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP gs_band_back, gs_band_back_rows, 6, 3, gs_pal
    ; gs_band_front (6x3 at 0,1 of the 6x4 FRONT face)
    SKROWS gs_band_front_rows, 6, 3
    SKROW "kssss."
    SKROW "kssss."
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP gs_band_front, gs_band_front_rows, 6, 3, gs_pal
    ; gs_pump_right (16x3 at 0,1 of the 16x4 RIGHT face)
    SKROWS gs_pump_right_rows, 16, 3
    SKROW "aaaN.N.N.N.N.aaa"
    SKROW "aaaN.N.N.N.N.aaa"
    SKROW "nnnnnnnnnnnnnnnn"
    SKROWS_END
    align 8
    SKBMP gs_pump_right, gs_pump_right_rows, 16, 3, gs_pal
    ; gs_pump_left (16x3 at 0,1 of the 16x4 LEFT face)
    SKROWS gs_pump_left_rows, 16, 3
    SKROW "nnnN.N.N.N.N.aaa"
    SKROW "aaaN.N.N.N.N.ann"
    SKROW "nnnnnnnnnnnnnnnn"
    SKROWS_END
    align 8
    SKBMP gs_pump_left, gs_pump_left_rows, 16, 3, gs_pal
    ; gs_pump_top (5x16 at 1,0 of the 6x16 TOP face)
    SKROWS gs_pump_top_rows, 5, 16
    SKROW "aaaaA"
    SKROW "aa..A"
    SKROW ".a..A"
    SKROW ".a..A"
    SKROW ".a..A"
    SKROW ".a..A"
    SKROW ".a..A"
    SKROW ".a..A"
    SKROW ".a..A"
    SKROW ".a..A"
    SKROW "aaaaA"
    SKROW "aa.aA"
    SKROW "aa.aA"
    SKROW "aa.aA"
    SKROW "aa.aA"
    SKROW "aa.aA"
    SKROWS_END
    align 8
    SKBMP gs_pump_top, gs_pump_top_rows, 5, 16, gs_pal
    ; gs_pump_bottom (6x14 at 0,2 of the 6x16 BOTTOM face)
    SKROWS gs_pump_bottom_rows, 6, 14
    SKROW "N..N.."
    SKROW "NNNNNN"
    SKROW "N..N.N"
    SKROW "NNNNNN"
    SKROW "N..N.N"
    SKROW "NNNNNN"
    SKROW ".....N"
    SKROW "NNNNNN"
    SKROW ".....N"
    SKROW "NNNNNN"
    SKROW "N....."
    SKROW "N....."
    SKROW "N....."
    SKROW "N....."
    SKROWS_END
    align 8
    SKBMP gs_pump_bottom, gs_pump_bottom_rows, 6, 14, gs_pal
    ; gs_pump_back (4x2 at 1,1 of the 6x4 BACK face)
    SKROWS gs_pump_back_rows, 4, 2
    SKROW "A..a"
    SKROW "a..a"
    SKROWS_END
    align 8
    SKBMP gs_pump_back, gs_pump_back_rows, 4, 2, gs_pal
    ; gs_pump_front (6x4 at 0,0 of the 6x4 FRONT face)
    SKROWS gs_pump_front_rows, 6, 4
    SKROW "AAAAAA"
    SKROW "..NN.."
    SKROW "..NN.."
    SKROW "nnnnnn"
    SKROWS_END
    align 8
    SKBMP gs_pump_front, gs_pump_front_rows, 6, 4, gs_pal
    ; gs_receiver_right (16x6 at 0,0 of the 16x7 RIGHT face)
    SKROWS gs_receiver_right_rows, 16, 6
    SKROW "DDDDDDDDDDDDDDDD"
    SKROW "d..............d"
    SKROW "d.ddDddddddDdd.d"
    SKROW "d.dDdDdBbdDdDd.d"
    SKROW "d.dddddbcddddd.d"
    SKROW "d..............d"
    SKROWS_END
    align 8
    SKBMP gs_receiver_right, gs_receiver_right_rows, 16, 6, gs_pal
    ; gs_receiver_left (16x6 at 0,0 of the 16x7 LEFT face)
    SKROWS gs_receiver_left_rows, 16, 6
    SKROW "DDDDDDDDDDDDDDDD"
    SKROW "d..............d"
    SKROW "d.ddDddddddDdd.d"
    SKROW "d.dDdDdBbdDdDd.d"
    SKROW "d.dddddbcddddd.d"
    SKROW "d..............d"
    SKROWS_END
    align 8
    SKBMP gs_receiver_left, gs_receiver_left_rows, 16, 6, gs_pal
    ; gs_receiver_top (6x16 at 0,0 of the 6x16 TOP face)
    SKROWS gs_receiver_top_rows, 6, 16
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e.EE.D"
    SKROW "e.EE.D"
    SKROW "e.EE.D"
    SKROW "e.EE.D"
    SKROW "e.EE.D"
    SKROW "e.EE.D"
    SKROW "e.EE.D"
    SKROW "e.EE.D"
    SKROW "e....D"
    SKROW "eeeeeD"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROWS_END
    align 8
    SKBMP gs_receiver_top, gs_receiver_top_rows, 6, 16, gs_pal
    ; gs_receiver_back (6x7 at 0,0 of the 6x7 BACK face)
    SKROWS gs_receiver_back_rows, 6, 7
    SKROW "DDDDDD"
    SKROW "......"
    SKROW "..EE.."
    SKROW "..EE.."
    SKROW "......"
    SKROW "......"
    SKROW "eeeeee"
    SKROWS_END
    align 8
    SKBMP gs_receiver_back, gs_receiver_back_rows, 6, 7, gs_pal
    ; gs_receiver_front (6x7 at 0,0 of the 6x7 FRONT face)
    SKROWS gs_receiver_front_rows, 6, 7
    SKROW "DDDDDD"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "eeeeee"
    SKROWS_END
    align 8
    SKBMP gs_receiver_front, gs_receiver_front_rows, 6, 7, gs_pal
    ; gs_hammer_l_right (2x1 at 0,1 of the 2x2 RIGHT face)
    SKROWS gs_hammer_l_right_rows, 2, 1
    SKROW "kk"
    SKROWS_END
    align 8
    SKBMP gs_hammer_l_right, gs_hammer_l_right_rows, 2, 1, gs_pal
    ; gs_hammer_l_left (2x1 at 0,1 of the 2x2 LEFT face)
    SKROWS gs_hammer_l_left_rows, 2, 1
    SKROW "kk"
    SKROWS_END
    align 8
    SKBMP gs_hammer_l_left, gs_hammer_l_left_rows, 2, 1, gs_pal
    ; gs_hammer_l_back (1x1 at 0,1 of the 1x2 BACK face)
    SKROWS gs_hammer_l_back_rows, 1, 1
    SKROW "k"
    SKROWS_END
    align 8
    SKBMP gs_hammer_l_back, gs_hammer_l_back_rows, 1, 1, gs_pal
    ; gs_hammer_l_front (1x1 at 0,1 of the 1x2 FRONT face)
    SKROWS gs_hammer_l_front_rows, 1, 1
    SKROW "k"
    SKROWS_END
    align 8
    SKBMP gs_hammer_l_front, gs_hammer_l_front_rows, 1, 1, gs_pal
    ; gs_lever_top (1x4 at 1,0 of the 2x4 TOP face)
    SKROWS gs_lever_top_rows, 1, 4
    SKROW "b"
    SKROW "b"
    SKROW "b"
    SKROW "C"
    SKROWS_END
    align 8
    SKBMP gs_lever_top, gs_lever_top_rows, 1, 4, gs_pal
    ; gs_wrist_right (8x6 at 0,0 of the 8x7 RIGHT face)
    SKROWS gs_wrist_right_rows, 8, 6
    SKROW "AAAAAAAA"
    SKROW "A.a.a.a."
    SKROW "Aa.a.a.."
    SKROW "A.a.a.a."
    SKROW "Aa.a.a.."
    SKROW "A.a.a.a."
    SKROWS_END
    align 8
    SKBMP gs_wrist_right, gs_wrist_right_rows, 8, 6, gs_pal
    ; gs_wrist_left (8x6 at 0,0 of the 8x7 LEFT face)
    SKROWS gs_wrist_left_rows, 8, 6
    SKROW "AAAAAAAA"
    SKROW "A.a.a.a."
    SKROW "Aa.a.a.."
    SKROW "A.a.a.a."
    SKROW "Aa.a.a.."
    SKROW "A.a.a.a."
    SKROWS_END
    align 8
    SKBMP gs_wrist_left, gs_wrist_left_rows, 8, 6, gs_pal
    ; gs_wrist_top (6x8 at 0,0 of the 6x8 TOP face)
    SKROWS gs_wrist_top_rows, 6, 8
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "nAA..A"
    SKROW "nAA..A"
    SKROW "nAA..A"
    SKROW "nAA..A"
    SKROW "nAA..A"
    SKROWS_END
    align 8
    SKBMP gs_wrist_top, gs_wrist_top_rows, 6, 8, gs_pal
    ; gs_wrist_bottom (5x8 at 0,0 of the 6x8 BOTTOM face)
    SKROWS gs_wrist_bottom_rows, 5, 8
    SKROW "....N"
    SKROW "N...N"
    SKROW "N.N.N"
    SKROW "NNN.N"
    SKROW "NNN.N"
    SKROW ".NN.N"
    SKROW ".NN.N"
    SKROW ".NN.."
    SKROWS_END
    align 8
    SKBMP gs_wrist_bottom, gs_wrist_bottom_rows, 5, 8, gs_pal
    ; gs_wrist_back (4x5 at 1,1 of the 6x7 BACK face)
    SKROWS gs_wrist_back_rows, 4, 5
    SKROW "Aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROWS_END
    align 8
    SKBMP gs_wrist_back, gs_wrist_back_rows, 4, 5, gs_pal
    ; gs_wrist_front (4x5 at 1,1 of the 6x7 FRONT face)
    SKROWS gs_wrist_front_rows, 4, 5
    SKROW "Aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROWS_END
    align 8
    SKBMP gs_wrist_front, gs_wrist_front_rows, 4, 5, gs_pal
    ; gs_stock_a_right (7x8 at 0,0 of the 7x8 RIGHT face)
    SKROWS gs_stock_a_right_rows, 7, 8
    SKROW "AAAAAAA"
    SKROW "...nnnn"
    SKROW ".AAAAAA"
    SKROW "......."
    SKROW ".nnnnnn"
    SKROW "......."
    SKROW "......."
    SKROW "nnnnnnn"
    SKROWS_END
    align 8
    SKBMP gs_stock_a_right, gs_stock_a_right_rows, 7, 8, gs_pal
    ; gs_stock_a_left (7x8 at 0,0 of the 7x8 LEFT face)
    SKROWS gs_stock_a_left_rows, 7, 8
    SKROW "AAAAAAA"
    SKROW "......."
    SKROW "......."
    SKROW "......."
    SKROW "......."
    SKROW "......."
    SKROW "......."
    SKROW "nnnnnnn"
    SKROWS_END
    align 8
    SKBMP gs_stock_a_left, gs_stock_a_left_rows, 7, 8, gs_pal
    ; gs_stock_a_top (6x7 at 0,0 of the 6x7 TOP face)
    SKROWS gs_stock_a_top_rows, 6, 7
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROWS_END
    align 8
    SKBMP gs_stock_a_top, gs_stock_a_top_rows, 6, 7, gs_pal
    ; gs_stock_a_bottom (1x1 at 2,6 of the 6x7 BOTTOM face)
    SKROWS gs_stock_a_bottom_rows, 1, 1
    SKROW "N"
    SKROWS_END
    align 8
    SKBMP gs_stock_a_bottom, gs_stock_a_bottom_rows, 1, 1, gs_pal
    ; gs_stock_a_back (4x6 at 1,1 of the 6x8 BACK face)
    SKROWS gs_stock_a_back_rows, 4, 6
    SKROW "Aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROW "aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROWS_END
    align 8
    SKBMP gs_stock_a_back, gs_stock_a_back_rows, 4, 6, gs_pal
    ; gs_stock_a_front (4x6 at 1,1 of the 6x8 FRONT face)
    SKROWS gs_stock_a_front_rows, 4, 6
    SKROW "Aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROW "aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROWS_END
    align 8
    SKBMP gs_stock_a_front, gs_stock_a_front_rows, 4, 6, gs_pal
    ; gs_stock_b_right (6x9 at 0,0 of the 6x9 RIGHT face)
    SKROWS gs_stock_b_right_rows, 6, 9
    SKROW "AAAAAA"
    SKROW "......"
    SKROW "......"
    SKROW "..AAAA"
    SKROW "..nnnn"
    SKROW "...AAA"
    SKROW "...nnn"
    SKROW "...nnn"
    SKROW "nnnnnn"
    SKROWS_END
    align 8
    SKBMP gs_stock_b_right, gs_stock_b_right_rows, 6, 9, gs_pal
    ; gs_stock_b_left (6x9 at 0,0 of the 6x9 LEFT face)
    SKROWS gs_stock_b_left_rows, 6, 9
    SKROW "AAAAAA"
    SKROW "...AAA"
    SKROW "...nnn"
    SKROW ".nnnnn"
    SKROW ".AAAAA"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "nnnnnn"
    SKROWS_END
    align 8
    SKBMP gs_stock_b_left, gs_stock_b_left_rows, 6, 9, gs_pal
    ; gs_stock_b_top (6x6 at 0,0 of the 6x6 TOP face)
    SKROWS gs_stock_b_top_rows, 6, 6
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROWS_END
    align 8
    SKBMP gs_stock_b_top, gs_stock_b_top_rows, 6, 6, gs_pal
    ; gs_stock_b_bottom (1x5 at 0,1 of the 6x6 BOTTOM face)
    SKROWS gs_stock_b_bottom_rows, 1, 5
    SKROW "N"
    SKROW "N"
    SKROW "N"
    SKROW "N"
    SKROW "N"
    SKROWS_END
    align 8
    SKBMP gs_stock_b_bottom, gs_stock_b_bottom_rows, 1, 5, gs_pal
    ; gs_stock_b_back (4x7 at 1,1 of the 6x9 BACK face)
    SKROWS gs_stock_b_back_rows, 4, 7
    SKROW "Aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROW "aaaa"
    SKROW "aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROWS_END
    align 8
    SKBMP gs_stock_b_back, gs_stock_b_back_rows, 4, 7, gs_pal
    ; gs_stock_b_front (4x7 at 1,1 of the 6x9 FRONT face)
    SKROWS gs_stock_b_front_rows, 4, 7
    SKROW "Aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROW "aaaa"
    SKROW "aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROWS_END
    align 8
    SKBMP gs_stock_b_front, gs_stock_b_front_rows, 4, 7, gs_pal
    ; gs_pad_right (1x9 at 0,0 of the 1x9 RIGHT face)
    SKROWS gs_pad_right_rows, 1, 9
    SKROW "D"
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "e"
    SKROWS_END
    align 8
    SKBMP gs_pad_right, gs_pad_right_rows, 1, 9, gs_pal
    ; gs_pad_left (1x9 at 0,0 of the 1x9 LEFT face)
    SKROWS gs_pad_left_rows, 1, 9
    SKROW "D"
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "e"
    SKROWS_END
    align 8
    SKBMP gs_pad_left, gs_pad_left_rows, 1, 9, gs_pal
    ; gs_pad_top (6x1 at 0,0 of the 6x1 TOP face)
    SKROWS gs_pad_top_rows, 6, 1
    SKROW "e....D"
    SKROWS_END
    align 8
    SKBMP gs_pad_top, gs_pad_top_rows, 6, 1, gs_pal
    ; gs_pad_back (6x9 at 0,0 of the 6x9 BACK face)
    SKROWS gs_pad_back_rows, 6, 9
    SKROW "DDDDDD"
    SKROW "Deeeee"
    SKROW "D....."
    SKROW "Deeeee"
    SKROW "D....."
    SKROW "Deeeee"
    SKROW "D....."
    SKROW "Deeeee"
    SKROW "D....."
    SKROWS_END
    align 8
    SKBMP gs_pad_back, gs_pad_back_rows, 6, 9, gs_pal
    ; gs_pad_front (6x9 at 0,0 of the 6x9 FRONT face)
    SKROWS gs_pad_front_rows, 6, 9
    SKROW "DDDDDD"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "eeeeee"
    SKROWS_END
    align 8
    SKBMP gs_pad_front, gs_pad_front_rows, 6, 9, gs_pal
    ; gs_guard_f_right (1x1 at 0,0 of the 1x2 RIGHT face)
    SKROWS gs_guard_f_right_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gs_guard_f_right, gs_guard_f_right_rows, 1, 1, gs_pal
    ; gs_guard_f_left (1x1 at 0,0 of the 1x2 LEFT face)
    SKROWS gs_guard_f_left_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gs_guard_f_left, gs_guard_f_left_rows, 1, 1, gs_pal
    ; gs_guard_f_top (1x1 at 1,0 of the 2x1 TOP face)
    SKROWS gs_guard_f_top_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gs_guard_f_top, gs_guard_f_top_rows, 1, 1, gs_pal
    ; gs_guard_f_back (2x1 at 0,0 of the 2x2 BACK face)
    SKROWS gs_guard_f_back_rows, 2, 1
    SKROW "ii"
    SKROWS_END
    align 8
    SKBMP gs_guard_f_back, gs_guard_f_back_rows, 2, 1, gs_pal
    ; gs_guard_f_front (2x1 at 0,0 of the 2x2 FRONT face)
    SKROWS gs_guard_f_front_rows, 2, 1
    SKROW "ii"
    SKROWS_END
    align 8
    SKBMP gs_guard_f_front, gs_guard_f_front_rows, 2, 1, gs_pal
    ; gs_guard_b_top (1x8 at 0,0 of the 2x8 TOP face)
    SKROWS gs_guard_b_top_rows, 1, 8
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROWS_END
    align 8
    SKBMP gs_guard_b_top, gs_guard_b_top_rows, 1, 8, gs_pal
    ; gs_trigger_right (1x1 at 0,0 of the 1x2 RIGHT face)
    SKROWS gs_trigger_right_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gs_trigger_right, gs_trigger_right_rows, 1, 1, gs_pal
    ; gs_trigger_left (1x1 at 0,0 of the 1x2 LEFT face)
    SKROWS gs_trigger_left_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gs_trigger_left, gs_trigger_left_rows, 1, 1, gs_pal
    ; gs_trigger_top (1x1 at 1,0 of the 2x1 TOP face)
    SKROWS gs_trigger_top_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gs_trigger_top, gs_trigger_top_rows, 1, 1, gs_pal
    ; gs_trigger_back (2x1 at 0,0 of the 2x2 BACK face)
    SKROWS gs_trigger_back_rows, 2, 1
    SKROW "ii"
    SKROWS_END
    align 8
    SKBMP gs_trigger_back, gs_trigger_back_rows, 2, 1, gs_pal
    ; gs_trigger_front (2x1 at 0,0 of the 2x2 FRONT face)
    SKROWS gs_trigger_front_rows, 2, 1
    SKROW "ii"
    SKROWS_END
    align 8
    SKBMP gs_trigger_front, gs_trigger_front_rows, 2, 1, gs_pal

section .data
SKMODEL_BEGIN m_gun_shotgun, 64, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART gs_barrel_l_a, -3, 1, -52, 3, 3, 22, 0, 0                ; blued barrel, the right one is its mirrored twin
    PART gs_barrel_l_b, -3, 1, -30, 3, 3, 22, 0, 0                ; blued barrel, the right one is its mirrored twin
    PART_AS gs_barrel_r_a, gs_barrel_l_a, 0, 1, -52, 0, 0         ; mirrored twin of barrel_l
    PART_AS gs_barrel_r_b, gs_barrel_l_b, 0, 1, -30, 0, 0         ; mirrored twin of barrel_l
    PART gs_rib_a, -1, 4, -50, 2, 1, 21, 0, 0                     ; ventilated rib
    PART gs_rib_b, -1, 4, -29, 2, 1, 21, 0, 0                     ; ventilated rib
    PART gs_bead, -1, 5, -52, 2, 1, 1, 0, 0                       ; brass bead sight
    PART gs_band, -3, 0, -30, 6, 4, 2, 3, 0                       ; steel barrel band with a screw
    PART gs_pump, -3, -3, -38, 6, 4, 16, 0, 0                     ; walnut pump forend with grip grooves
    PART gs_receiver, -3, -3, -8, 6, 7, 16, 0, 0                  ; dark engraved receiver with a brass inlay
    PART gs_hammer_l, -2, 4, 5, 1, 2, 2, 0, 0                     ; hammer, the right one is its twin
    PART_AS gs_hammer_r, gs_hammer_l, 1, 4, 5, 0, 0               ; mirrored twin of hammer_l
    PART gs_lever, -1, 4, 2, 2, 1, 4, 0, 0                        ; brass top lever
    PART gs_wrist, -3, -4, 8, 6, 7, 8, 0, 0                       ; walnut wrist with checkering
    PART gs_stock_a, -3, -6, 16, 6, 8, 7, 0, 0                    ; walnut stock, middle
    PART gs_stock_b, -3, -8, 23, 6, 9, 6, 0, 0                    ; walnut stock, heel
    PART gs_pad, -3, -8, 29, 6, 9, 1, 0, 0                        ; ribbed rubber butt pad
    PART gs_guard_f, -1, -5, -6, 2, 2, 1, 0, 0                    ; trigger guard, front post
    PART gs_guard_b, -1, -6, -6, 2, 1, 8, 0, 0                    ; trigger guard, bar
    PART gs_trigger, -1, -5, -2, 2, 2, 1, 0, 0                    ; trigger
SKMODEL_PAINT
    ; --- gs_barrel_l_a  (blued barrel, the right one is its mirrored twin)
    SK_FILL gs_barrel_l_a, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, GUN_STEEL_1, 0
    SK_FILL gs_barrel_l_a, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gs_barrel_l_a, SKF_RIGHT, 0, 0, gs_barrel_l_a_right
    SK_BMP gs_barrel_l_a, SKF_LEFT, 0, 0, gs_barrel_l_a_left
    SK_BMP gs_barrel_l_a, SKF_TOP, 0, 0, gs_barrel_l_a_top
    SK_BMP gs_barrel_l_a, SKF_FRONT, 0, 1, gs_barrel_l_a_front
    ; --- gs_barrel_l_b  (blued barrel, the right one is its mirrored twin)
    SK_FILL gs_barrel_l_b, SKM_RIGHT | SKM_LEFT | SKM_BACK | SKM_FRONT, GUN_STEEL_3, 0
    SK_FILL gs_barrel_l_b, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gs_barrel_l_b, SKM_TOP, GUN_STEEL_1, 0
    SK_BMP gs_barrel_l_b, SKF_RIGHT, 0, 0, gs_barrel_l_b_right
    SK_BMP gs_barrel_l_b, SKF_LEFT, 0, 0, gs_barrel_l_b_left
    SK_BMP gs_barrel_l_b, SKF_TOP, 1, 0, gs_barrel_l_b_top
    ; --- gs_rib_a  (ventilated rib)
    SK_FILL gs_rib_a, SKM_RIGHT | SKM_LEFT | SKM_BACK | SKM_FRONT, AC_IRON_3, 0
    SK_FILL gs_rib_a, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gs_rib_a, SKM_TOP, AC_IRON_4, 0
    SK_BMP gs_rib_a, SKF_RIGHT, 0, 0, gs_rib_a_right
    SK_BMP gs_rib_a, SKF_LEFT, 0, 0, gs_rib_a_left
    SK_BMP gs_rib_a, SKF_TOP, 0, 0, gs_rib_a_top
    ; --- gs_rib_b  (ventilated rib)
    SK_FILL gs_rib_b, SKM_RIGHT | SKM_LEFT | SKM_BACK | SKM_FRONT, AC_IRON_3, 0
    SK_FILL gs_rib_b, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gs_rib_b, SKM_TOP, AC_IRON_4, 0
    SK_BMP gs_rib_b, SKF_RIGHT, 0, 0, gs_rib_b_right
    SK_BMP gs_rib_b, SKF_LEFT, 0, 0, gs_rib_b_left
    SK_BMP gs_rib_b, SKF_TOP, 0, 0, gs_rib_b_top
    ; --- gs_bead  (brass bead sight)
    SK_FILL gs_bead, SKM_RIGHT | SKM_LEFT | SKM_FRONT, AC_GOLD_3, 0
    SK_FILL gs_bead, SKM_TOP | SKM_BACK, AC_GOLD_2, 0
    SK_FILL gs_bead, SKM_BOTTOM, GUN_BRASS_DEEP, 0
    ; --- gs_band  (steel barrel band with a screw)
    SK_FILL gs_band, SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, GUN_STEEL_1, 0
    SK_FILL gs_band, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gs_band, SKM_RIGHT, GUN_STEEL_3, 0
    SK_BMP gs_band, SKF_RIGHT, 0, 0, gs_band_right
    SK_BMP gs_band, SKF_LEFT, 1, 0, gs_band_left
    SK_BMP gs_band, SKF_TOP, 0, 1, gs_band_top
    SK_BMP gs_band, SKF_BACK, 0, 1, gs_band_back
    SK_BMP gs_band, SKF_FRONT, 0, 1, gs_band_front
    ; --- gs_pump  (walnut pump forend with grip grooves)
    SK_FILL gs_pump, SKM_FRONT, GUN_WALNUT_2, 15
    SK_FILL gs_pump, SKM_TOP | SKM_BOTTOM | SKM_BACK, GUN_WALNUT_3, 0
    SK_FILL gs_pump, SKM_RIGHT | SKM_LEFT, GUN_WALNUT_1, 0
    SK_BMP gs_pump, SKF_RIGHT, 0, 1, gs_pump_right
    SK_BMP gs_pump, SKF_LEFT, 0, 1, gs_pump_left
    SK_BMP gs_pump, SKF_TOP, 1, 0, gs_pump_top
    SK_BMP gs_pump, SKF_BOTTOM, 0, 2, gs_pump_bottom
    SK_BMP gs_pump, SKF_BACK, 1, 1, gs_pump_back
    SK_BMP gs_pump, SKF_FRONT, 0, 0, gs_pump_front
    SK_GRAD gs_pump, SKM_RIGHT | SKM_LEFT, 256, 228
    ; --- gs_receiver  (dark engraved receiver with a brass inlay)
    SK_FILL gs_receiver, SKM_TOP | SKM_BACK | SKM_FRONT, GUN_DARK_2, 0
    SK_FILL gs_receiver, SKM_BOTTOM, GUN_DARK_4, 0
    SK_FILL gs_receiver, SKM_RIGHT | SKM_LEFT, GUN_DARK_3, 0
    SK_BMP gs_receiver, SKF_RIGHT, 0, 0, gs_receiver_right
    SK_BMP gs_receiver, SKF_LEFT, 0, 0, gs_receiver_left
    SK_BMP gs_receiver, SKF_TOP, 0, 0, gs_receiver_top
    SK_BMP gs_receiver, SKF_BACK, 0, 0, gs_receiver_back
    SK_BMP gs_receiver, SKF_FRONT, 0, 0, gs_receiver_front
    ; --- gs_hammer_l  (hammer, the right one is its twin)
    SK_FILL gs_hammer_l, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, GUN_STEEL_1, 0
    SK_FILL gs_hammer_l, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gs_hammer_l, SKF_RIGHT, 0, 1, gs_hammer_l_right
    SK_BMP gs_hammer_l, SKF_LEFT, 0, 1, gs_hammer_l_left
    SK_BMP gs_hammer_l, SKF_BACK, 0, 1, gs_hammer_l_back
    SK_BMP gs_hammer_l, SKF_FRONT, 0, 1, gs_hammer_l_front
    ; --- gs_lever  (brass top lever)
    SK_FILL gs_lever, SKM_RIGHT | SKM_LEFT | SKM_BACK | SKM_FRONT, AC_GOLD_3, 0
    SK_FILL gs_lever, SKM_BOTTOM, GUN_BRASS_DEEP, 0
    SK_FILL gs_lever, SKM_TOP, AC_GOLD_2, 0
    SK_BMP gs_lever, SKF_TOP, 1, 0, gs_lever_top
    ; --- gs_wrist  (walnut wrist with checkering)
    SK_FILL gs_wrist, SKM_RIGHT | SKM_LEFT | SKM_BOTTOM | SKM_BACK | SKM_FRONT, GUN_WALNUT_3, 0
    SK_FILL gs_wrist, SKM_TOP, GUN_WALNUT_2, 15
    SK_BMP gs_wrist, SKF_RIGHT, 0, 0, gs_wrist_right
    SK_BMP gs_wrist, SKF_LEFT, 0, 0, gs_wrist_left
    SK_BMP gs_wrist, SKF_TOP, 0, 0, gs_wrist_top
    SK_BMP gs_wrist, SKF_BOTTOM, 0, 0, gs_wrist_bottom
    SK_BMP gs_wrist, SKF_BACK, 1, 1, gs_wrist_back
    SK_BMP gs_wrist, SKF_FRONT, 1, 1, gs_wrist_front
    SK_GRAD gs_wrist, SKM_RIGHT | SKM_LEFT, 256, 228
    ; --- gs_stock_a  (walnut stock, middle)
    SK_FILL gs_stock_a, SKM_BOTTOM | SKM_BACK | SKM_FRONT, GUN_WALNUT_3, 0
    SK_FILL gs_stock_a, SKM_RIGHT | SKM_LEFT | SKM_TOP, GUN_WALNUT_2, 15
    SK_BMP gs_stock_a, SKF_RIGHT, 0, 0, gs_stock_a_right
    SK_BMP gs_stock_a, SKF_LEFT, 0, 0, gs_stock_a_left
    SK_BMP gs_stock_a, SKF_TOP, 0, 0, gs_stock_a_top
    SK_BMP gs_stock_a, SKF_BOTTOM, 2, 6, gs_stock_a_bottom
    SK_BMP gs_stock_a, SKF_BACK, 1, 1, gs_stock_a_back
    SK_BMP gs_stock_a, SKF_FRONT, 1, 1, gs_stock_a_front
    SK_GRAD gs_stock_a, SKM_RIGHT | SKM_LEFT, 256, 228
    ; --- gs_stock_b  (walnut stock, heel)
    SK_FILL gs_stock_b, SKM_BOTTOM | SKM_BACK | SKM_FRONT, GUN_WALNUT_3, 0
    SK_FILL gs_stock_b, SKM_RIGHT | SKM_LEFT | SKM_TOP, GUN_WALNUT_2, 15
    SK_BMP gs_stock_b, SKF_RIGHT, 0, 0, gs_stock_b_right
    SK_BMP gs_stock_b, SKF_LEFT, 0, 0, gs_stock_b_left
    SK_BMP gs_stock_b, SKF_TOP, 0, 0, gs_stock_b_top
    SK_BMP gs_stock_b, SKF_BOTTOM, 0, 1, gs_stock_b_bottom
    SK_BMP gs_stock_b, SKF_BACK, 1, 1, gs_stock_b_back
    SK_BMP gs_stock_b, SKF_FRONT, 1, 1, gs_stock_b_front
    SK_GRAD gs_stock_b, SKM_RIGHT | SKM_LEFT, 256, 228
    ; --- gs_pad  (ribbed rubber butt pad)
    SK_FILL gs_pad, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, GUN_DARK_2, 0
    SK_FILL gs_pad, SKM_BOTTOM, GUN_DARK_4, 0
    SK_BMP gs_pad, SKF_RIGHT, 0, 0, gs_pad_right
    SK_BMP gs_pad, SKF_LEFT, 0, 0, gs_pad_left
    SK_BMP gs_pad, SKF_TOP, 0, 0, gs_pad_top
    SK_BMP gs_pad, SKF_BACK, 0, 0, gs_pad_back
    SK_BMP gs_pad, SKF_FRONT, 0, 0, gs_pad_front
    ; --- gs_guard_f  (trigger guard, front post)
    SK_FILL gs_guard_f, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, AC_IRON_4, 0
    SK_FILL gs_guard_f, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gs_guard_f, SKF_RIGHT, 0, 0, gs_guard_f_right
    SK_BMP gs_guard_f, SKF_LEFT, 0, 0, gs_guard_f_left
    SK_BMP gs_guard_f, SKF_TOP, 1, 0, gs_guard_f_top
    SK_BMP gs_guard_f, SKF_BACK, 0, 0, gs_guard_f_back
    SK_BMP gs_guard_f, SKF_FRONT, 0, 0, gs_guard_f_front
    ; --- gs_guard_b  (trigger guard, bar)
    SK_FILL gs_guard_b, SKM_RIGHT | SKM_LEFT | SKM_BACK | SKM_FRONT, AC_IRON_3, 0
    SK_FILL gs_guard_b, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gs_guard_b, SKM_TOP, AC_IRON_2, 0
    SK_BMP gs_guard_b, SKF_TOP, 0, 0, gs_guard_b_top
    ; --- gs_trigger  (trigger)
    SK_FILL gs_trigger, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, AC_IRON_4, 0
    SK_FILL gs_trigger, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gs_trigger, SKF_RIGHT, 0, 0, gs_trigger_right
    SK_BMP gs_trigger, SKF_LEFT, 0, 0, gs_trigger_left
    SK_BMP gs_trigger, SKF_TOP, 1, 0, gs_trigger_top
    SK_BMP gs_trigger, SKF_BACK, 0, 0, gs_trigger_back
    SK_BMP gs_trigger, SKF_FRONT, 0, 0, gs_trigger_front
SKMODEL_END

; ===================================================================================================
; m_gun_rifle
; ===================================================================================================
; The assault rifle (Kalashnikov): a slotted muzzle brake, a blued barrel under a dark gas tube and a front sight post, a
; walnut handguard with vent slots, a stamped dust cover with ribs and a rear sight leaf over a lined receiver (selector
; lever, ejection port, charging handle), a banana magazine in three ribbed bakelite steps, a raked pistol grip, a trigger guard with a
; trigger, and a stepped walnut stock with a steel butt plate and a trap door.
; Model space (texels, 64 per block, muzzle -Z): the old boxes x 64 give the extents (barrel 1.9 x 1.9 x 26, receiver
; 5.8 x 5.8 x 26, magazine 3.8 x 17.9 x 6.4, stock 4.5 x 7.7 x 19, muzzle at (0, 2.9, -45.4)); this model stays within
; 2 texels of them (x -3..3, y -16..7, z -47..30).
section .rodata
; The characters of every gr_ bitmap:
;  A walnut highlight, D dark steel highlight, E dark steel deep, N walnut deep, S steel edge highlight
;  T bakelite highlight, a walnut, b brass, d dark steel, e dark steel shade, g steel glint, i iron highlight
;  j iron, k steel shade, n walnut shade, u bakelite shade, x bore, pure dark, z white paint, stencil
align 8
gr_pal:
    PALC 'A', GUN_WALNUT_1
    PALC 'D', GUN_DARK_1
    PALC 'E', GUN_DARK_4
    PALC 'N', GUN_WALNUT_4
    PALC 'S', GUN_STEEL_1
    PALC 'T', GUN_BAKE_1
    PALC 'a', GUN_WALNUT_2
    PALC 'b', AC_GOLD_3
    PALC 'd', GUN_DARK_2
    PALC 'e', GUN_DARK_3
    PALC 'g', GUN_STEEL_0
    PALC 'i', AC_IRON_2
    PALC 'j', AC_IRON_3
    PALC 'k', GUN_STEEL_3
    PALC 'n', GUN_WALNUT_3
    PALC 'u', GUN_BAKE_3
    PALC 'x', GUN_BORE
    PALC 'z', GUN_WHITE
    dq 0

    ; gr_barrel_a_right (7x1 at 0,0 of the 7x2 RIGHT face)
    SKROWS gr_barrel_a_right_rows, 7, 1
    SKROW "SgSSSSS"
    SKROWS_END
    align 8
    SKBMP gr_barrel_a_right, gr_barrel_a_right_rows, 7, 1, gr_pal
    ; gr_barrel_a_left (7x1 at 0,0 of the 7x2 LEFT face)
    SKROWS gr_barrel_a_left_rows, 7, 1
    SKROW "SSSSSgS"
    SKROWS_END
    align 8
    SKBMP gr_barrel_a_left, gr_barrel_a_left_rows, 7, 1, gr_pal
    ; gr_barrel_a_top (1x7 at 0,0 of the 2x7 TOP face)
    SKROWS gr_barrel_a_top_rows, 1, 7
    SKROW "k"
    SKROW "k"
    SKROW "k"
    SKROW "k"
    SKROW "k"
    SKROW "k"
    SKROW "k"
    SKROWS_END
    align 8
    SKBMP gr_barrel_a_top, gr_barrel_a_top_rows, 1, 7, gr_pal
    ; gr_barrel_a_front (2x1 at 0,1 of the 2x2 FRONT face)
    SKROWS gr_barrel_a_front_rows, 2, 1
    SKROW "kk"
    SKROWS_END
    align 8
    SKBMP gr_barrel_a_front, gr_barrel_a_front_rows, 2, 1, gr_pal
    ; gr_barrel_b_right (8x1 at 0,1 of the 8x2 RIGHT face)
    SKROWS gr_barrel_b_right_rows, 8, 1
    SKROW "kkkkkkkk"
    SKROWS_END
    align 8
    SKBMP gr_barrel_b_right, gr_barrel_b_right_rows, 8, 1, gr_pal
    ; gr_barrel_b_left (8x1 at 0,1 of the 8x2 LEFT face)
    SKROWS gr_barrel_b_left_rows, 8, 1
    SKROW "kkkkkkkk"
    SKROWS_END
    align 8
    SKBMP gr_barrel_b_left, gr_barrel_b_left_rows, 8, 1, gr_pal
    ; gr_barrel_b_top (1x8 at 1,0 of the 2x8 TOP face)
    SKROWS gr_barrel_b_top_rows, 1, 8
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROW "g"
    SKROWS_END
    align 8
    SKBMP gr_barrel_b_top, gr_barrel_b_top_rows, 1, 8, gr_pal
    ; gr_barrel_b_back (2x1 at 0,1 of the 2x2 BACK face)
    SKROWS gr_barrel_b_back_rows, 2, 1
    SKROW "kk"
    SKROWS_END
    align 8
    SKBMP gr_barrel_b_back, gr_barrel_b_back_rows, 2, 1, gr_pal
    ; gr_brake_right (3x2 at 1,0 of the 4x2 RIGHT face)
    SKROWS gr_brake_right_rows, 3, 2
    SKROW "D.D"
    SKROW "e.e"
    SKROWS_END
    align 8
    SKBMP gr_brake_right, gr_brake_right_rows, 3, 2, gr_pal
    ; gr_brake_left (3x2 at 0,0 of the 4x2 LEFT face)
    SKROWS gr_brake_left_rows, 3, 2
    SKROW "D.D"
    SKROW "e.e"
    SKROWS_END
    align 8
    SKBMP gr_brake_left, gr_brake_left_rows, 3, 2, gr_pal
    ; gr_brake_top (2x3 at 0,1 of the 2x4 TOP face)
    SKROWS gr_brake_top_rows, 2, 3
    SKROW "eD"
    SKROW ".."
    SKROW "eD"
    SKROWS_END
    align 8
    SKBMP gr_brake_top, gr_brake_top_rows, 2, 3, gr_pal
    ; gr_brake_back (2x1 at 0,1 of the 2x2 BACK face)
    SKROWS gr_brake_back_rows, 2, 1
    SKROW "ee"
    SKROWS_END
    align 8
    SKBMP gr_brake_back, gr_brake_back_rows, 2, 1, gr_pal
    ; gr_brake_front (1x1 at 0,0 of the 2x2 FRONT face)
    SKROWS gr_brake_front_rows, 1, 1
    SKROW "E"
    SKROWS_END
    align 8
    SKBMP gr_brake_front, gr_brake_front_rows, 1, 1, gr_pal
    ; gr_gas_right (7x1 at 0,0 of the 8x2 RIGHT face)
    SKROWS gr_gas_right_rows, 7, 1
    SKROW "DDDDDDx"
    SKROWS_END
    align 8
    SKBMP gr_gas_right, gr_gas_right_rows, 7, 1, gr_pal
    ; gr_gas_left (7x1 at 1,0 of the 8x2 LEFT face)
    SKROWS gr_gas_left_rows, 7, 1
    SKROW "xDDDDDD"
    SKROWS_END
    align 8
    SKBMP gr_gas_left, gr_gas_left_rows, 7, 1, gr_pal
    ; gr_gas_top (1x8 at 0,0 of the 2x8 TOP face)
    SKROWS gr_gas_top_rows, 1, 8
    SKROW "d"
    SKROW "d"
    SKROW "d"
    SKROW "d"
    SKROW "d"
    SKROW "d"
    SKROW "d"
    SKROW "d"
    SKROWS_END
    align 8
    SKBMP gr_gas_top, gr_gas_top_rows, 1, 8, gr_pal
    ; gr_gas_back (2x1 at 0,1 of the 2x2 BACK face)
    SKROWS gr_gas_back_rows, 2, 1
    SKROW "ee"
    SKROWS_END
    align 8
    SKBMP gr_gas_back, gr_gas_back_rows, 2, 1, gr_pal
    ; gr_gas_front (2x1 at 0,1 of the 2x2 FRONT face)
    SKROWS gr_gas_front_rows, 2, 1
    SKROW "ee"
    SKROWS_END
    align 8
    SKBMP gr_gas_front, gr_gas_front_rows, 2, 1, gr_pal
    ; gr_fsight_right (2x3 at 0,0 of the 2x3 RIGHT face)
    SKROWS gr_fsight_right_rows, 2, 3
    SKROW "jj"
    SKROW ".."
    SKROW "ee"
    SKROWS_END
    align 8
    SKBMP gr_fsight_right, gr_fsight_right_rows, 2, 3, gr_pal
    ; gr_fsight_left (2x3 at 0,0 of the 2x3 LEFT face)
    SKROWS gr_fsight_left_rows, 2, 3
    SKROW "jj"
    SKROW ".."
    SKROW "ee"
    SKROWS_END
    align 8
    SKBMP gr_fsight_left, gr_fsight_left_rows, 2, 3, gr_pal
    ; gr_fsight_back (2x1 at 0,0 of the 2x3 BACK face)
    SKROWS gr_fsight_back_rows, 2, 1
    SKROW "zz"
    SKROWS_END
    align 8
    SKBMP gr_fsight_back, gr_fsight_back_rows, 2, 1, gr_pal
    ; gr_fsight_front (2x2 at 0,1 of the 2x3 FRONT face)
    SKROWS gr_fsight_front_rows, 2, 2
    SKROW "dd"
    SKROW "ee"
    SKROWS_END
    align 8
    SKBMP gr_fsight_front, gr_fsight_front_rows, 2, 2, gr_pal
    ; gr_hg_low_right (14x5 at 0,0 of the 14x5 RIGHT face)
    SKROWS gr_hg_low_right_rows, 14, 5
    SKROW "AAAAAAAAAAAAAA"
    SKROW "..NN.NN.NN...."
    SKROW "..NN.NN.NN...."
    SKROW "...........AAA"
    SKROW "nnnnnnnnnnnnnn"
    SKROWS_END
    align 8
    SKBMP gr_hg_low_right, gr_hg_low_right_rows, 14, 5, gr_pal
    ; gr_hg_low_left (14x4 at 0,0 of the 14x5 LEFT face)
    SKROWS gr_hg_low_left_rows, 14, 4
    SKROW "AAAAAAAAAAAAAA"
    SKROW "aaNNaNNaNNaaaA"
    SKROW "aaNN.NN.NN..aa"
    SKROW "a........aaaaa"
    SKROWS_END
    align 8
    SKBMP gr_hg_low_left, gr_hg_low_left_rows, 14, 4, gr_pal
    ; gr_hg_low_top (6x14 at 0,0 of the 6x14 TOP face)
    SKROWS gr_hg_low_top_rows, 6, 14
    SKROW "nA...A"
    SKROW "nA...A"
    SKROW "nA...A"
    SKROW "nA...A"
    SKROW "nA...A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n....A"
    SKROW "n.n..A"
    SKROW "n.n..A"
    SKROW "n.n..A"
    SKROW "n.n.nA"
    SKROWS_END
    align 8
    SKBMP gr_hg_low_top, gr_hg_low_top_rows, 6, 14, gr_pal
    ; gr_hg_low_bottom (2x13 at 3,1 of the 6x14 BOTTOM face)
    SKROWS gr_hg_low_bottom_rows, 2, 13
    SKROW ".a"
    SKROW ".a"
    SKROW ".a"
    SKROW ".a"
    SKROW ".a"
    SKROW ".a"
    SKROW ".a"
    SKROW ".a"
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROW "a."
    SKROWS_END
    align 8
    SKBMP gr_hg_low_bottom, gr_hg_low_bottom_rows, 2, 13, gr_pal
    ; gr_hg_low_back (4x3 at 1,1 of the 6x5 BACK face)
    SKROWS gr_hg_low_back_rows, 4, 3
    SKROW "Aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROWS_END
    align 8
    SKBMP gr_hg_low_back, gr_hg_low_back_rows, 4, 3, gr_pal
    ; gr_hg_low_front (4x3 at 1,1 of the 6x5 FRONT face)
    SKROWS gr_hg_low_front_rows, 4, 3
    SKROW "Aaaa"
    SKROW "a..a"
    SKROW "aaaa"
    SKROWS_END
    align 8
    SKBMP gr_hg_low_front, gr_hg_low_front_rows, 4, 3, gr_pal
    ; gr_hg_up_right (8x1 at 0,1 of the 8x2 RIGHT face)
    SKROWS gr_hg_up_right_rows, 8, 1
    SKROW "nnnnnnnn"
    SKROWS_END
    align 8
    SKBMP gr_hg_up_right, gr_hg_up_right_rows, 8, 1, gr_pal
    ; gr_hg_up_left (8x1 at 0,1 of the 8x2 LEFT face)
    SKROWS gr_hg_up_left_rows, 8, 1
    SKROW "nnnnnnnn"
    SKROWS_END
    align 8
    SKBMP gr_hg_up_left, gr_hg_up_left_rows, 8, 1, gr_pal
    ; gr_hg_up_top (2x8 at 0,0 of the 4x8 TOP face)
    SKROWS gr_hg_up_top_rows, 2, 8
    SKROW "na"
    SKROW "na"
    SKROW "na"
    SKROW "na"
    SKROW "na"
    SKROW "na"
    SKROW "na"
    SKROW "na"
    SKROWS_END
    align 8
    SKBMP gr_hg_up_top, gr_hg_up_top_rows, 2, 8, gr_pal
    ; gr_hg_up_back (4x2 at 0,0 of the 4x2 BACK face)
    SKROWS gr_hg_up_back_rows, 4, 2
    SKROW "n..n"
    SKROW "n..n"
    SKROWS_END
    align 8
    SKBMP gr_hg_up_back, gr_hg_up_back_rows, 4, 2, gr_pal
    ; gr_recv_low_right (26x2 at 0,0 of the 26x3 RIGHT face)
    SKROWS gr_recv_low_right_rows, 26, 2
    SKROW "DDDDDDDDDDDDDDDDDDDDDDDDDD"
    SKROW "ddddd.ddSSSSSSSSkddddd.ddd"
    SKROWS_END
    align 8
    SKBMP gr_recv_low_right, gr_recv_low_right_rows, 26, 2, gr_pal
    ; gr_recv_low_left (26x2 at 0,1 of the 26x3 LEFT face)
    SKROWS gr_recv_low_left_rows, 26, 2
    SKROW "ddddeddddddd.dddddEEdddddd"
    SKROW "eeeeeeeeeeeeeeeeeeeeeeeeee"
    SKROWS_END
    align 8
    SKBMP gr_recv_low_left, gr_recv_low_left_rows, 26, 2, gr_pal
    ; gr_recv_low_top (6x26 at 0,0 of the 6x26 TOP face)
    SKROWS gr_recv_low_top_rows, 6, 26
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROWS_END
    align 8
    SKBMP gr_recv_low_top, gr_recv_low_top_rows, 6, 26, gr_pal
    ; gr_recv_low_bottom (4x8 at 1,9 of the 6x26 BOTTOM face)
    SKROWS gr_recv_low_bottom_rows, 4, 8
    SKROW "eeee"
    SKROW "eeee"
    SKROW "eeee"
    SKROW "eeee"
    SKROW "eeee"
    SKROW "eeee"
    SKROW "eeee"
    SKROW "eeee"
    SKROWS_END
    align 8
    SKBMP gr_recv_low_bottom, gr_recv_low_bottom_rows, 4, 8, gr_pal
    ; gr_recv_low_back (6x2 at 0,1 of the 6x3 BACK face)
    SKROWS gr_recv_low_back_rows, 6, 2
    SKROW ".dddde"
    SKROW "eeeeee"
    SKROWS_END
    align 8
    SKBMP gr_recv_low_back, gr_recv_low_back_rows, 6, 2, gr_pal
    ; gr_recv_low_front (6x2 at 0,1 of the 6x3 FRONT face)
    SKROWS gr_recv_low_front_rows, 6, 2
    SKROW "edddd."
    SKROW "eeeeee"
    SKROWS_END
    align 8
    SKBMP gr_recv_low_front, gr_recv_low_front_rows, 6, 2, gr_pal
    ; gr_cover_right (24x2 at 0,1 of the 24x3 RIGHT face)
    SKROWS gr_cover_right_rows, 24, 2
    SKROW "dddedxxxxxxxkddeddeddedd"
    SKROW "eeeeeEEEEEEEkeeeeeeeeeee"
    SKROWS_END
    align 8
    SKBMP gr_cover_right, gr_cover_right_rows, 24, 2, gr_pal
    ; gr_cover_left (24x2 at 0,0 of the 24x3 LEFT face)
    SKROWS gr_cover_left_rows, 24, 2
    SKROW "DDDDDDDDDDDDDDDDDDDDDDDD"
    SKROW "dd.dd.dd.dd.dd.dd.dd.ddd"
    SKROWS_END
    align 8
    SKBMP gr_cover_left, gr_cover_left_rows, 24, 2, gr_pal
    ; gr_cover_top (6x24 at 0,0 of the 6x24 TOP face)
    SKROWS gr_cover_top_rows, 6, 24
    SKROW "e....D"
    SKROW "e....D"
    SKROW "ee..eD"
    SKROW "e.DD.D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "ee..eD"
    SKROW "e.DD.D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "ee..eD"
    SKROW "e.DD.D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "ee..eD"
    SKROW "e.DD.D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "ee..eD"
    SKROW "e.DD.D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROWS_END
    align 8
    SKBMP gr_cover_top, gr_cover_top_rows, 6, 24, gr_pal
    ; gr_cover_back (5x2 at 1,1 of the 6x3 BACK face)
    SKROWS gr_cover_back_rows, 5, 2
    SKROW "eEEee"
    SKROW "EeeEe"
    SKROWS_END
    align 8
    SKBMP gr_cover_back, gr_cover_back_rows, 5, 2, gr_pal
    ; gr_cover_front (6x2 at 0,1 of the 6x3 FRONT face)
    SKROWS gr_cover_front_rows, 6, 2
    SKROW "edddd."
    SKROW "eeeeee"
    SKROWS_END
    align 8
    SKBMP gr_cover_front, gr_cover_front_rows, 6, 2, gr_pal
    ; gr_charging_right (4x1 at 1,1 of the 5x2 RIGHT face)
    SKROWS gr_charging_right_rows, 4, 1
    SKROW "kkkk"
    SKROWS_END
    align 8
    SKBMP gr_charging_right, gr_charging_right_rows, 4, 1, gr_pal
    ; gr_charging_left (5x1 at 0,1 of the 5x2 LEFT face)
    SKROWS gr_charging_left_rows, 5, 1
    SKROW "kkkkk"
    SKROWS_END
    align 8
    SKBMP gr_charging_left, gr_charging_left_rows, 5, 1, gr_pal
    ; gr_charging_back (1x1 at 0,1 of the 1x2 BACK face)
    SKROWS gr_charging_back_rows, 1, 1
    SKROW "k"
    SKROWS_END
    align 8
    SKBMP gr_charging_back, gr_charging_back_rows, 1, 1, gr_pal
    ; gr_charging_front (1x1 at 0,1 of the 1x2 FRONT face)
    SKROWS gr_charging_front_rows, 1, 1
    SKROW "k"
    SKROWS_END
    align 8
    SKBMP gr_charging_front, gr_charging_front_rows, 1, 1, gr_pal
    ; gr_rsight_top (2x2 at 0,1 of the 2x4 TOP face)
    SKROWS gr_rsight_top_rows, 2, 2
    SKROW "ii"
    SKROW "ii"
    SKROWS_END
    align 8
    SKBMP gr_rsight_top, gr_rsight_top_rows, 2, 2, gr_pal
    ; gr_mag_a_right (7x5 at 0,0 of the 7x5 RIGHT face)
    SKROWS gr_mag_a_right_rows, 7, 5
    SKROW "TTTTTTT"
    SKROW "......."
    SKROW "uuuuuuu"
    SKROW "......."
    SKROW "uuuuuuu"
    SKROWS_END
    align 8
    SKBMP gr_mag_a_right, gr_mag_a_right_rows, 7, 5, gr_pal
    ; gr_mag_a_left (7x5 at 0,0 of the 7x5 LEFT face)
    SKROWS gr_mag_a_left_rows, 7, 5
    SKROW "TTTTTTT"
    SKROW "......."
    SKROW "uuuuuuu"
    SKROW "......."
    SKROW "uuuuuuu"
    SKROWS_END
    align 8
    SKBMP gr_mag_a_left, gr_mag_a_left_rows, 7, 5, gr_pal
    ; gr_mag_a_top (4x7 at 0,0 of the 4x7 TOP face)
    SKROWS gr_mag_a_top_rows, 4, 7
    SKROW "u..T"
    SKROW "u..T"
    SKROW "u..T"
    SKROW "u..T"
    SKROW "u..T"
    SKROW "u..T"
    SKROW "u..T"
    SKROWS_END
    align 8
    SKBMP gr_mag_a_top, gr_mag_a_top_rows, 4, 7, gr_pal
    ; gr_mag_a_back (4x5 at 0,0 of the 4x5 BACK face)
    SKROWS gr_mag_a_back_rows, 4, 5
    SKROW "TTTu"
    SKROW "...u"
    SKROW "...u"
    SKROW "...u"
    SKROW "...u"
    SKROWS_END
    align 8
    SKBMP gr_mag_a_back, gr_mag_a_back_rows, 4, 5, gr_pal
    ; gr_mag_a_front (3x3 at 1,1 of the 4x5 FRONT face)
    SKROWS gr_mag_a_front_rows, 3, 3
    SKROW "uuu"
    SKROW "..."
    SKROW "uuu"
    SKROWS_END
    align 8
    SKBMP gr_mag_a_front, gr_mag_a_front_rows, 3, 3, gr_pal
    ; gr_mag_b_right (7x5 at 0,0 of the 7x5 RIGHT face)
    SKROWS gr_mag_b_right_rows, 7, 5
    SKROW "TTTTTTT"
    SKROW "......."
    SKROW "uuuuuuu"
    SKROW "......."
    SKROW "uuuuuuu"
    SKROWS_END
    align 8
    SKBMP gr_mag_b_right, gr_mag_b_right_rows, 7, 5, gr_pal
    ; gr_mag_b_left (7x5 at 0,0 of the 7x5 LEFT face)
    SKROWS gr_mag_b_left_rows, 7, 5
    SKROW "TTTTTTT"
    SKROW "......."
    SKROW "uuuuuuu"
    SKROW "......."
    SKROW "uuuuuuu"
    SKROWS_END
    align 8
    SKBMP gr_mag_b_left, gr_mag_b_left_rows, 7, 5, gr_pal
    ; gr_mag_b_top (4x7 at 0,0 of the 4x7 TOP face)
    SKROWS gr_mag_b_top_rows, 4, 7
    SKROW "u..T"
    SKROW "u..T"
    SKROW "u..T"
    SKROW "u..T"
    SKROW "u..T"
    SKROW "u..T"
    SKROW "u..T"
    SKROWS_END
    align 8
    SKBMP gr_mag_b_top, gr_mag_b_top_rows, 4, 7, gr_pal
    ; gr_mag_b_back (4x5 at 0,0 of the 4x5 BACK face)
    SKROWS gr_mag_b_back_rows, 4, 5
    SKROW "TTTu"
    SKROW "...u"
    SKROW "...u"
    SKROW "...u"
    SKROW "...u"
    SKROWS_END
    align 8
    SKBMP gr_mag_b_back, gr_mag_b_back_rows, 4, 5, gr_pal
    ; gr_mag_b_front (3x3 at 1,1 of the 4x5 FRONT face)
    SKROWS gr_mag_b_front_rows, 3, 3
    SKROW "uuu"
    SKROW "..."
    SKROW "uuu"
    SKROWS_END
    align 8
    SKBMP gr_mag_b_front, gr_mag_b_front_rows, 3, 3, gr_pal
    ; gr_mag_c_right (7x5 at 0,0 of the 7x5 RIGHT face)
    SKROWS gr_mag_c_right_rows, 7, 5
    SKROW "TTTTTTT"
    SKROW "......."
    SKROW "uuuuuuu"
    SKROW "......."
    SKROW "uuuuuuu"
    SKROWS_END
    align 8
    SKBMP gr_mag_c_right, gr_mag_c_right_rows, 7, 5, gr_pal
    ; gr_mag_c_left (7x5 at 0,0 of the 7x5 LEFT face)
    SKROWS gr_mag_c_left_rows, 7, 5
    SKROW "TTTTTTT"
    SKROW "......."
    SKROW "uuuuuuu"
    SKROW "......."
    SKROW "uuuuuuu"
    SKROWS_END
    align 8
    SKBMP gr_mag_c_left, gr_mag_c_left_rows, 7, 5, gr_pal
    ; gr_mag_c_top (4x7 at 0,0 of the 4x7 TOP face)
    SKROWS gr_mag_c_top_rows, 4, 7
    SKROW "u..T"
    SKROW "u..T"
    SKROW "u..T"
    SKROW "u..T"
    SKROW "u..T"
    SKROW "u..T"
    SKROW "u..T"
    SKROWS_END
    align 8
    SKBMP gr_mag_c_top, gr_mag_c_top_rows, 4, 7, gr_pal
    ; gr_mag_c_bottom (4x7 at 0,0 of the 4x7 BOTTOM face)
    SKROWS gr_mag_c_bottom_rows, 4, 7
    SKROW "eeee"
    SKROW "...."
    SKROW ".dd."
    SKROW ".dd."
    SKROW ".dd."
    SKROW "...."
    SKROW "eeee"
    SKROWS_END
    align 8
    SKBMP gr_mag_c_bottom, gr_mag_c_bottom_rows, 4, 7, gr_pal
    ; gr_mag_c_back (4x5 at 0,0 of the 4x5 BACK face)
    SKROWS gr_mag_c_back_rows, 4, 5
    SKROW "TTTu"
    SKROW "...u"
    SKROW "...u"
    SKROW "...u"
    SKROW "...u"
    SKROWS_END
    align 8
    SKBMP gr_mag_c_back, gr_mag_c_back_rows, 4, 5, gr_pal
    ; gr_mag_c_front (3x3 at 1,1 of the 4x5 FRONT face)
    SKROWS gr_mag_c_front_rows, 3, 3
    SKROW "uuu"
    SKROW "..."
    SKROW "uuu"
    SKROWS_END
    align 8
    SKBMP gr_mag_c_front, gr_mag_c_front_rows, 3, 3, gr_pal
    ; gr_grip_a_right (4x4 at 0,0 of the 4x4 RIGHT face)
    SKROWS gr_grip_a_right_rows, 4, 4
    SKROW "TTTT"
    SKROW ".u.u"
    SKROW ".u.u"
    SKROW ".u.u"
    SKROWS_END
    align 8
    SKBMP gr_grip_a_right, gr_grip_a_right_rows, 4, 4, gr_pal
    ; gr_grip_a_left (4x4 at 0,0 of the 4x4 LEFT face)
    SKROWS gr_grip_a_left_rows, 4, 4
    SKROW "TTTT"
    SKROW ".u.u"
    SKROW ".u.u"
    SKROW ".u.u"
    SKROWS_END
    align 8
    SKBMP gr_grip_a_left, gr_grip_a_left_rows, 4, 4, gr_pal
    ; gr_grip_a_top (4x4 at 0,0 of the 4x4 TOP face)
    SKROWS gr_grip_a_top_rows, 4, 4
    SKROW "u..T"
    SKROW "u..T"
    SKROW "u..T"
    SKROW "u..T"
    SKROWS_END
    align 8
    SKBMP gr_grip_a_top, gr_grip_a_top_rows, 4, 4, gr_pal
    ; gr_grip_a_back (4x4 at 0,0 of the 4x4 BACK face)
    SKROWS gr_grip_a_back_rows, 4, 4
    SKROW "TTTu"
    SKROW "...u"
    SKROW "...u"
    SKROW "...u"
    SKROWS_END
    align 8
    SKBMP gr_grip_a_back, gr_grip_a_back_rows, 4, 4, gr_pal
    ; gr_grip_a_front (4x3 at 0,0 of the 4x4 FRONT face)
    SKROWS gr_grip_a_front_rows, 4, 3
    SKROW "uuuu"
    SKROW "...."
    SKROW "uuuu"
    SKROWS_END
    align 8
    SKBMP gr_grip_a_front, gr_grip_a_front_rows, 4, 3, gr_pal
    ; gr_grip_b_right (4x4 at 0,0 of the 4x4 RIGHT face)
    SKROWS gr_grip_b_right_rows, 4, 4
    SKROW "TTTT"
    SKROW ".u.u"
    SKROW ".u.u"
    SKROW ".u.u"
    SKROWS_END
    align 8
    SKBMP gr_grip_b_right, gr_grip_b_right_rows, 4, 4, gr_pal
    ; gr_grip_b_left (4x4 at 0,0 of the 4x4 LEFT face)
    SKROWS gr_grip_b_left_rows, 4, 4
    SKROW "TTTT"
    SKROW ".u.u"
    SKROW ".u.u"
    SKROW ".u.u"
    SKROWS_END
    align 8
    SKBMP gr_grip_b_left, gr_grip_b_left_rows, 4, 4, gr_pal
    ; gr_grip_b_top (4x4 at 0,0 of the 4x4 TOP face)
    SKROWS gr_grip_b_top_rows, 4, 4
    SKROW "u..T"
    SKROW "u..T"
    SKROW "u..T"
    SKROW "u..T"
    SKROWS_END
    align 8
    SKBMP gr_grip_b_top, gr_grip_b_top_rows, 4, 4, gr_pal
    ; gr_grip_b_back (4x4 at 0,0 of the 4x4 BACK face)
    SKROWS gr_grip_b_back_rows, 4, 4
    SKROW "TTTu"
    SKROW "...u"
    SKROW "...u"
    SKROW "...u"
    SKROWS_END
    align 8
    SKBMP gr_grip_b_back, gr_grip_b_back_rows, 4, 4, gr_pal
    ; gr_grip_b_front (4x3 at 0,0 of the 4x4 FRONT face)
    SKROWS gr_grip_b_front_rows, 4, 3
    SKROW "uuuu"
    SKROW "...."
    SKROW "uuuu"
    SKROWS_END
    align 8
    SKBMP gr_grip_b_front, gr_grip_b_front_rows, 4, 3, gr_pal
    ; gr_guard_f_right (1x2 at 0,0 of the 1x3 RIGHT face)
    SKROWS gr_guard_f_right_rows, 1, 2
    SKROW "i"
    SKROW "j"
    SKROWS_END
    align 8
    SKBMP gr_guard_f_right, gr_guard_f_right_rows, 1, 2, gr_pal
    ; gr_guard_f_left (1x2 at 0,0 of the 1x3 LEFT face)
    SKROWS gr_guard_f_left_rows, 1, 2
    SKROW "i"
    SKROW "j"
    SKROWS_END
    align 8
    SKBMP gr_guard_f_left, gr_guard_f_left_rows, 1, 2, gr_pal
    ; gr_guard_f_top (1x1 at 1,0 of the 2x1 TOP face)
    SKROWS gr_guard_f_top_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gr_guard_f_top, gr_guard_f_top_rows, 1, 1, gr_pal
    ; gr_guard_f_back (2x2 at 0,0 of the 2x3 BACK face)
    SKROWS gr_guard_f_back_rows, 2, 2
    SKROW "ii"
    SKROW "jj"
    SKROWS_END
    align 8
    SKBMP gr_guard_f_back, gr_guard_f_back_rows, 2, 2, gr_pal
    ; gr_guard_f_front (2x2 at 0,0 of the 2x3 FRONT face)
    SKROWS gr_guard_f_front_rows, 2, 2
    SKROW "ii"
    SKROW "jj"
    SKROWS_END
    align 8
    SKBMP gr_guard_f_front, gr_guard_f_front_rows, 2, 2, gr_pal
    ; gr_guard_b_top (1x5 at 0,0 of the 2x5 TOP face)
    SKROWS gr_guard_b_top_rows, 1, 5
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROWS_END
    align 8
    SKBMP gr_guard_b_top, gr_guard_b_top_rows, 1, 5, gr_pal
    ; gr_trigger_right (1x1 at 0,0 of the 1x2 RIGHT face)
    SKROWS gr_trigger_right_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gr_trigger_right, gr_trigger_right_rows, 1, 1, gr_pal
    ; gr_trigger_left (1x1 at 0,0 of the 1x2 LEFT face)
    SKROWS gr_trigger_left_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gr_trigger_left, gr_trigger_left_rows, 1, 1, gr_pal
    ; gr_trigger_top (1x1 at 1,0 of the 2x1 TOP face)
    SKROWS gr_trigger_top_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gr_trigger_top, gr_trigger_top_rows, 1, 1, gr_pal
    ; gr_trigger_back (2x1 at 0,0 of the 2x2 BACK face)
    SKROWS gr_trigger_back_rows, 2, 1
    SKROW "ii"
    SKROWS_END
    align 8
    SKBMP gr_trigger_back, gr_trigger_back_rows, 2, 1, gr_pal
    ; gr_trigger_front (2x1 at 0,0 of the 2x2 FRONT face)
    SKROWS gr_trigger_front_rows, 2, 1
    SKROW "ii"
    SKROWS_END
    align 8
    SKBMP gr_trigger_front, gr_trigger_front_rows, 2, 1, gr_pal
    ; gr_stock_a_right (8x5 at 0,0 of the 8x5 RIGHT face)
    SKROWS gr_stock_a_right_rows, 8, 5
    SKROW "AAAAAAAA"
    SKROW "........"
    SKROW "nnnnnnnn"
    SKROW "........"
    SKROW "nnnnnnnn"
    SKROWS_END
    align 8
    SKBMP gr_stock_a_right, gr_stock_a_right_rows, 8, 5, gr_pal
    ; gr_stock_a_left (8x5 at 0,0 of the 8x5 LEFT face)
    SKROWS gr_stock_a_left_rows, 8, 5
    SKROW "AAAAAAAA"
    SKROW ".AAAAAAA"
    SKROW "........"
    SKROW "........"
    SKROW "nnnnnnnn"
    SKROWS_END
    align 8
    SKBMP gr_stock_a_left, gr_stock_a_left_rows, 8, 5, gr_pal
    ; gr_stock_a_top (3x8 at 1,0 of the 4x8 TOP face)
    SKROWS gr_stock_a_top_rows, 3, 8
    SKROW "aaA"
    SKROW ".aA"
    SKROW ".aA"
    SKROW ".AA"
    SKROW ".AA"
    SKROW ".AA"
    SKROW ".AA"
    SKROW ".AA"
    SKROWS_END
    align 8
    SKBMP gr_stock_a_top, gr_stock_a_top_rows, 3, 8, gr_pal
    ; gr_stock_a_bottom (2x6 at 0,2 of the 4x8 BOTTOM face)
    SKROWS gr_stock_a_bottom_rows, 2, 6
    SKROW "N."
    SKROW "NN"
    SKROW "NN"
    SKROW "NN"
    SKROW "NN"
    SKROW "NN"
    SKROWS_END
    align 8
    SKBMP gr_stock_a_bottom, gr_stock_a_bottom_rows, 2, 6, gr_pal
    ; gr_stock_a_back (2x3 at 1,1 of the 4x5 BACK face)
    SKROWS gr_stock_a_back_rows, 2, 3
    SKROW "Aa"
    SKROW ".."
    SKROW "aa"
    SKROWS_END
    align 8
    SKBMP gr_stock_a_back, gr_stock_a_back_rows, 2, 3, gr_pal
    ; gr_stock_a_front (2x3 at 1,1 of the 4x5 FRONT face)
    SKROWS gr_stock_a_front_rows, 2, 3
    SKROW "Aa"
    SKROW ".."
    SKROW "aa"
    SKROWS_END
    align 8
    SKBMP gr_stock_a_front, gr_stock_a_front_rows, 2, 3, gr_pal
    ; gr_stock_b_right (6x6 at 0,0 of the 6x7 RIGHT face)
    SKROWS gr_stock_b_right_rows, 6, 6
    SKROW "AAAAAA"
    SKROW "a....."
    SKROW "a....."
    SKROW "AAAAAA"
    SKROW "aaaaaa"
    SKROW "aaaaaa"
    SKROWS_END
    align 8
    SKBMP gr_stock_b_right, gr_stock_b_right_rows, 6, 6, gr_pal
    ; gr_stock_b_left (6x7 at 0,0 of the 6x7 LEFT face)
    SKROWS gr_stock_b_left_rows, 6, 7
    SKROW "AAAAAA"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "..nnnn"
    SKROW "......"
    SKROW "nnnnnn"
    SKROWS_END
    align 8
    SKBMP gr_stock_b_left, gr_stock_b_left_rows, 6, 7, gr_pal
    ; gr_stock_b_top (3x6 at 1,0 of the 4x6 TOP face)
    SKROWS gr_stock_b_top_rows, 3, 6
    SKROW "aaA"
    SKROW ".aA"
    SKROW "..A"
    SKROW "..A"
    SKROW "..A"
    SKROW "..A"
    SKROWS_END
    align 8
    SKBMP gr_stock_b_top, gr_stock_b_top_rows, 3, 6, gr_pal
    ; gr_stock_b_bottom (4x6 at 0,0 of the 4x6 BOTTOM face)
    SKROWS gr_stock_b_bottom_rows, 4, 6
    SKROW "na.n"
    SKROW "na.n"
    SKROW ".a.n"
    SKROW ".a.n"
    SKROW ".a.n"
    SKROW ".a.n"
    SKROWS_END
    align 8
    SKBMP gr_stock_b_bottom, gr_stock_b_bottom_rows, 4, 6, gr_pal
    ; gr_stock_b_back (2x5 at 1,1 of the 4x7 BACK face)
    SKROWS gr_stock_b_back_rows, 2, 5
    SKROW "Aa"
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROW "aa"
    SKROWS_END
    align 8
    SKBMP gr_stock_b_back, gr_stock_b_back_rows, 2, 5, gr_pal
    ; gr_stock_b_front (2x5 at 1,1 of the 4x7 FRONT face)
    SKROWS gr_stock_b_front_rows, 2, 5
    SKROW "Aa"
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROW "aa"
    SKROWS_END
    align 8
    SKBMP gr_stock_b_front, gr_stock_b_front_rows, 2, 5, gr_pal
    ; gr_stock_c_right (5x8 at 0,0 of the 5x8 RIGHT face)
    SKROWS gr_stock_c_right_rows, 5, 8
    SKROW "AAAAA"
    SKROW "....."
    SKROW "....."
    SKROW "....."
    SKROW "....."
    SKROW "....."
    SKROW "....."
    SKROW "nnnnn"
    SKROWS_END
    align 8
    SKBMP gr_stock_c_right, gr_stock_c_right_rows, 5, 8, gr_pal
    ; gr_stock_c_left (5x8 at 0,0 of the 5x8 LEFT face)
    SKROWS gr_stock_c_left_rows, 5, 8
    SKROW "AAAAA"
    SKROW "..AAA"
    SKROW "..nnn"
    SKROW "..nnn"
    SKROW "....."
    SKROW "....."
    SKROW ".nnnn"
    SKROW "nnnnn"
    SKROWS_END
    align 8
    SKBMP gr_stock_c_left, gr_stock_c_left_rows, 5, 8, gr_pal
    ; gr_stock_c_top (4x5 at 0,0 of the 4x5 TOP face)
    SKROWS gr_stock_c_top_rows, 4, 5
    SKROW "n..A"
    SKROW "n..A"
    SKROW "n..A"
    SKROW "n..A"
    SKROW "n..A"
    SKROWS_END
    align 8
    SKBMP gr_stock_c_top, gr_stock_c_top_rows, 4, 5, gr_pal
    ; gr_stock_c_bottom (1x5 at 3,0 of the 4x5 BOTTOM face)
    SKROWS gr_stock_c_bottom_rows, 1, 5
    SKROW "N"
    SKROW "N"
    SKROW "N"
    SKROW "N"
    SKROW "N"
    SKROWS_END
    align 8
    SKBMP gr_stock_c_bottom, gr_stock_c_bottom_rows, 1, 5, gr_pal
    ; gr_stock_c_back (2x6 at 1,1 of the 4x8 BACK face)
    SKROWS gr_stock_c_back_rows, 2, 6
    SKROW "Aa"
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROW "aa"
    SKROWS_END
    align 8
    SKBMP gr_stock_c_back, gr_stock_c_back_rows, 2, 6, gr_pal
    ; gr_stock_c_front (2x6 at 1,1 of the 4x8 FRONT face)
    SKROWS gr_stock_c_front_rows, 2, 6
    SKROW "Aa"
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROW "aa"
    SKROWS_END
    align 8
    SKBMP gr_stock_c_front, gr_stock_c_front_rows, 2, 6, gr_pal
    ; gr_plate_right (1x8 at 0,0 of the 1x8 RIGHT face)
    SKROWS gr_plate_right_rows, 1, 8
    SKROW "D"
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "e"
    SKROWS_END
    align 8
    SKBMP gr_plate_right, gr_plate_right_rows, 1, 8, gr_pal
    ; gr_plate_left (1x8 at 0,0 of the 1x8 LEFT face)
    SKROWS gr_plate_left_rows, 1, 8
    SKROW "D"
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "e"
    SKROWS_END
    align 8
    SKBMP gr_plate_left, gr_plate_left_rows, 1, 8, gr_pal
    ; gr_plate_top (4x1 at 0,0 of the 4x1 TOP face)
    SKROWS gr_plate_top_rows, 4, 1
    SKROW "e..D"
    SKROWS_END
    align 8
    SKBMP gr_plate_top, gr_plate_top_rows, 4, 1, gr_pal
    ; gr_plate_back (3x7 at 0,0 of the 4x8 BACK face)
    SKROWS gr_plate_back_rows, 3, 7
    SKROW "DDD"
    SKROW "Ddd"
    SKROW "DDD"
    SKROW "D.."
    SKROW "Db."
    SKROW "D.."
    SKROW "Ddd"
    SKROWS_END
    align 8
    SKBMP gr_plate_back, gr_plate_back_rows, 3, 7, gr_pal
    ; gr_plate_front (4x8 at 0,0 of the 4x8 FRONT face)
    SKROWS gr_plate_front_rows, 4, 8
    SKROW "DDDD"
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROW "eeee"
    SKROWS_END
    align 8
    SKBMP gr_plate_front, gr_plate_front_rows, 4, 8, gr_pal

section .data
SKMODEL_BEGIN m_gun_rifle, 64, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART gr_barrel_a, -1, 2, -45, 2, 2, 7, 0, 0                   ; blued barrel
    PART gr_barrel_b, -1, 2, -38, 2, 2, 8, 0, 0                   ; blued barrel
    PART gr_brake, -1, 2, -45, 2, 2, 4, 4, 0                      ; slotted muzzle brake
    PART gr_gas, -1, 4, -32, 2, 2, 8, 0, 0                        ; gas tube
    PART gr_fsight, -1, 4, -44, 2, 3, 2, 0, 0                     ; front sight block and post
    PART gr_hg_low, -3, -1, -30, 6, 5, 14, 0, 0                   ; walnut lower handguard with vent slots
    PART gr_hg_up, -2, 4, -24, 4, 2, 8, 0, 0                      ; walnut upper handguard
    PART gr_recv_low, -3, -1, -16, 6, 3, 26, 0, 0                 ; receiver body: selector lever, magazine well
    PART gr_cover, -3, 2, -16, 6, 3, 24, 0, 0                     ; stamped dust cover with ribs and the ejection port
    PART gr_charging, 3, 1, -7, 1, 2, 5, 0, 0                     ; charging handle on the right, with a knob
    PART gr_rsight, -1, 5, -12, 2, 1, 4, 0, 0                     ; rear sight leaf
    PART gr_mag_a, -2, -6, -13, 4, 5, 7, 0, 0                     ; bakelite magazine, ribbed
    PART gr_mag_b, -2, -11, -14, 4, 5, 7, 0, 0                    ; bakelite magazine, ribbed
    PART gr_mag_c, -2, -16, -16, 4, 5, 7, 0, 0                    ; bakelite magazine, ribbed
    PART gr_grip_a, -2, -5, 1, 4, 4, 4, 0, 0                      ; bakelite pistol grip, grooved
    PART gr_grip_b, -2, -9, 2, 4, 4, 4, 0, 0                      ; bakelite pistol grip, grooved
    PART gr_guard_f, -1, -4, -5, 2, 3, 1, 0, 0                    ; trigger guard, front post
    PART gr_guard_b, -1, -4, -4, 2, 1, 5, 0, 0                    ; trigger guard, bar
    PART gr_trigger, -1, -3, -2, 2, 2, 1, 0, 0                    ; trigger
    PART gr_stock_a, -2, -3, 10, 4, 5, 8, 0, 0                    ; walnut stock, wrist
    PART gr_stock_b, -2, -5, 18, 4, 7, 6, 0, 0                    ; walnut stock, middle
    PART gr_stock_c, -2, -7, 24, 4, 8, 5, 0, 0                    ; walnut stock, heel
    PART gr_plate, -2, -7, 29, 4, 8, 1, 0, 0                      ; steel butt plate with a trap door
SKMODEL_PAINT
    ; --- gr_barrel_a  (blued barrel)
    SK_FILL gr_barrel_a, SKM_TOP | SKM_BACK | SKM_FRONT, GUN_STEEL_1, 0
    SK_FILL gr_barrel_a, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gr_barrel_a, SKM_RIGHT | SKM_LEFT, GUN_STEEL_3, 0
    SK_BMP gr_barrel_a, SKF_RIGHT, 0, 0, gr_barrel_a_right
    SK_BMP gr_barrel_a, SKF_LEFT, 0, 0, gr_barrel_a_left
    SK_BMP gr_barrel_a, SKF_TOP, 0, 0, gr_barrel_a_top
    SK_BMP gr_barrel_a, SKF_FRONT, 0, 1, gr_barrel_a_front
    ; --- gr_barrel_b  (blued barrel)
    SK_FILL gr_barrel_b, SKM_RIGHT | SKM_LEFT | SKM_BACK | SKM_FRONT, GUN_STEEL_1, 0
    SK_FILL gr_barrel_b, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gr_barrel_b, SKM_TOP, GUN_STEEL_3, 0
    SK_BMP gr_barrel_b, SKF_RIGHT, 0, 1, gr_barrel_b_right
    SK_BMP gr_barrel_b, SKF_LEFT, 0, 1, gr_barrel_b_left
    SK_BMP gr_barrel_b, SKF_TOP, 1, 0, gr_barrel_b_top
    SK_BMP gr_barrel_b, SKF_BACK, 0, 1, gr_barrel_b_back
    ; --- gr_brake  (slotted muzzle brake)
    SK_FILL gr_brake, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_FRONT, GUN_BORE, 0
    SK_FILL gr_brake, SKM_BACK, GUN_DARK_1, 0
    SK_FILL gr_brake, SKM_BOTTOM, GUN_DARK_4, 0
    SK_BMP gr_brake, SKF_RIGHT, 1, 0, gr_brake_right
    SK_BMP gr_brake, SKF_LEFT, 0, 0, gr_brake_left
    SK_BMP gr_brake, SKF_TOP, 0, 1, gr_brake_top
    SK_BMP gr_brake, SKF_BACK, 0, 1, gr_brake_back
    SK_BMP gr_brake, SKF_FRONT, 0, 0, gr_brake_front
    ; --- gr_gas  (gas tube)
    SK_FILL gr_gas, SKM_TOP | SKM_BACK | SKM_FRONT, GUN_DARK_1, 0
    SK_FILL gr_gas, SKM_BOTTOM, GUN_DARK_4, 0
    SK_FILL gr_gas, SKM_RIGHT | SKM_LEFT, GUN_DARK_3, 0
    SK_BMP gr_gas, SKF_RIGHT, 0, 0, gr_gas_right
    SK_BMP gr_gas, SKF_LEFT, 1, 0, gr_gas_left
    SK_BMP gr_gas, SKF_TOP, 0, 0, gr_gas_top
    SK_BMP gr_gas, SKF_BACK, 0, 1, gr_gas_back
    SK_BMP gr_gas, SKF_FRONT, 0, 1, gr_gas_front
    ; --- gr_fsight  (front sight block and post)
    SK_FILL gr_fsight, SKM_FRONT, GUN_DARK_1, 0
    SK_FILL gr_fsight, SKM_RIGHT | SKM_LEFT | SKM_BACK, GUN_DARK_2, 0
    SK_FILL gr_fsight, SKM_BOTTOM, GUN_DARK_4, 0
    SK_FILL gr_fsight, SKM_TOP, AC_IRON_3, 0
    SK_BMP gr_fsight, SKF_RIGHT, 0, 0, gr_fsight_right
    SK_BMP gr_fsight, SKF_LEFT, 0, 0, gr_fsight_left
    SK_BMP gr_fsight, SKF_BACK, 0, 0, gr_fsight_back
    SK_BMP gr_fsight, SKF_FRONT, 0, 1, gr_fsight_front
    ; --- gr_hg_low  (walnut lower handguard with vent slots)
    SK_FILL gr_hg_low, SKM_LEFT | SKM_BOTTOM | SKM_BACK | SKM_FRONT, GUN_WALNUT_3, 0
    SK_FILL gr_hg_low, SKM_RIGHT | SKM_TOP, GUN_WALNUT_2, 15
    SK_BMP gr_hg_low, SKF_RIGHT, 0, 0, gr_hg_low_right
    SK_BMP gr_hg_low, SKF_LEFT, 0, 0, gr_hg_low_left
    SK_BMP gr_hg_low, SKF_TOP, 0, 0, gr_hg_low_top
    SK_BMP gr_hg_low, SKF_BOTTOM, 3, 1, gr_hg_low_bottom
    SK_BMP gr_hg_low, SKF_BACK, 1, 1, gr_hg_low_back
    SK_BMP gr_hg_low, SKF_FRONT, 1, 1, gr_hg_low_front
    SK_GRAD gr_hg_low, SKM_RIGHT | SKM_LEFT, 256, 228
    ; --- gr_hg_up  (walnut upper handguard)
    SK_FILL gr_hg_up, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_FRONT, GUN_WALNUT_1, 0
    SK_FILL gr_hg_up, SKM_BACK, GUN_WALNUT_2, 15
    SK_FILL gr_hg_up, SKM_BOTTOM, GUN_WALNUT_3, 0
    SK_BMP gr_hg_up, SKF_RIGHT, 0, 1, gr_hg_up_right
    SK_BMP gr_hg_up, SKF_LEFT, 0, 1, gr_hg_up_left
    SK_BMP gr_hg_up, SKF_TOP, 0, 0, gr_hg_up_top
    SK_BMP gr_hg_up, SKF_BACK, 0, 0, gr_hg_up_back
    SK_GRAD gr_hg_up, SKM_RIGHT | SKM_LEFT, 256, 228
    ; --- gr_recv_low  (receiver body: selector lever, magazine well)
    SK_FILL gr_recv_low, SKM_LEFT | SKM_BACK | SKM_FRONT, GUN_DARK_1, 0
    SK_FILL gr_recv_low, SKM_BOTTOM, GUN_DARK_4, 0
    SK_FILL gr_recv_low, SKM_TOP, GUN_DARK_2, 0
    SK_FILL gr_recv_low, SKM_RIGHT, GUN_DARK_3, 0
    SK_BMP gr_recv_low, SKF_RIGHT, 0, 0, gr_recv_low_right
    SK_BMP gr_recv_low, SKF_LEFT, 0, 1, gr_recv_low_left
    SK_BMP gr_recv_low, SKF_TOP, 0, 0, gr_recv_low_top
    SK_BMP gr_recv_low, SKF_BOTTOM, 1, 9, gr_recv_low_bottom
    SK_BMP gr_recv_low, SKF_BACK, 0, 1, gr_recv_low_back
    SK_BMP gr_recv_low, SKF_FRONT, 0, 1, gr_recv_low_front
    ; --- gr_cover  (stamped dust cover with ribs and the ejection port)
    SK_FILL gr_cover, SKM_RIGHT | SKM_BACK | SKM_FRONT, GUN_DARK_1, 0
    SK_FILL gr_cover, SKM_BOTTOM, GUN_DARK_4, 0
    SK_FILL gr_cover, SKM_TOP, GUN_DARK_2, 0
    SK_FILL gr_cover, SKM_LEFT, GUN_DARK_3, 0
    SK_BMP gr_cover, SKF_RIGHT, 0, 1, gr_cover_right
    SK_BMP gr_cover, SKF_LEFT, 0, 0, gr_cover_left
    SK_BMP gr_cover, SKF_TOP, 0, 0, gr_cover_top
    SK_BMP gr_cover, SKF_BACK, 1, 1, gr_cover_back
    SK_BMP gr_cover, SKF_FRONT, 0, 1, gr_cover_front
    ; --- gr_charging  (charging handle on the right, with a knob)
    SK_FILL gr_charging, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, GUN_STEEL_1, 0
    SK_FILL gr_charging, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gr_charging, SKF_RIGHT, 1, 1, gr_charging_right
    SK_BMP gr_charging, SKF_LEFT, 0, 1, gr_charging_left
    SK_BMP gr_charging, SKF_BACK, 0, 1, gr_charging_back
    SK_BMP gr_charging, SKF_FRONT, 0, 1, gr_charging_front
    ; --- gr_rsight  (rear sight leaf)
    SK_FILL gr_rsight, SKM_RIGHT | SKM_LEFT | SKM_FRONT, AC_IRON_3, 0
    SK_FILL gr_rsight, SKM_BACK, GUN_BORE, 0
    SK_FILL gr_rsight, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gr_rsight, SKM_TOP, AC_IRON_4, 0
    SK_BMP gr_rsight, SKF_TOP, 0, 1, gr_rsight_top
    ; --- gr_mag_a  (bakelite magazine, ribbed)
    SK_FILL gr_mag_a, SKM_FRONT, GUN_BAKE_1, 0
    SK_FILL gr_mag_a, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK, GUN_BAKE_2, 7
    SK_FILL gr_mag_a, SKM_BOTTOM, GUN_BAKE_4, 0
    SK_BMP gr_mag_a, SKF_RIGHT, 0, 0, gr_mag_a_right
    SK_BMP gr_mag_a, SKF_LEFT, 0, 0, gr_mag_a_left
    SK_BMP gr_mag_a, SKF_TOP, 0, 0, gr_mag_a_top
    SK_BMP gr_mag_a, SKF_BACK, 0, 0, gr_mag_a_back
    SK_BMP gr_mag_a, SKF_FRONT, 1, 1, gr_mag_a_front
    ; --- gr_mag_b  (bakelite magazine, ribbed)
    SK_FILL gr_mag_b, SKM_FRONT, GUN_BAKE_1, 0
    SK_FILL gr_mag_b, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK, GUN_BAKE_2, 7
    SK_FILL gr_mag_b, SKM_BOTTOM, GUN_BAKE_4, 0
    SK_BMP gr_mag_b, SKF_RIGHT, 0, 0, gr_mag_b_right
    SK_BMP gr_mag_b, SKF_LEFT, 0, 0, gr_mag_b_left
    SK_BMP gr_mag_b, SKF_TOP, 0, 0, gr_mag_b_top
    SK_BMP gr_mag_b, SKF_BACK, 0, 0, gr_mag_b_back
    SK_BMP gr_mag_b, SKF_FRONT, 1, 1, gr_mag_b_front
    ; --- gr_mag_c  (bakelite magazine, ribbed)
    SK_FILL gr_mag_c, SKM_FRONT, GUN_BAKE_1, 0
    SK_FILL gr_mag_c, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK, GUN_BAKE_2, 7
    SK_FILL gr_mag_c, SKM_BOTTOM, GUN_DARK_4, 0
    SK_BMP gr_mag_c, SKF_RIGHT, 0, 0, gr_mag_c_right
    SK_BMP gr_mag_c, SKF_LEFT, 0, 0, gr_mag_c_left
    SK_BMP gr_mag_c, SKF_TOP, 0, 0, gr_mag_c_top
    SK_BMP gr_mag_c, SKF_BOTTOM, 0, 0, gr_mag_c_bottom
    SK_BMP gr_mag_c, SKF_BACK, 0, 0, gr_mag_c_back
    SK_BMP gr_mag_c, SKF_FRONT, 1, 1, gr_mag_c_front
    ; --- gr_grip_a  (bakelite pistol grip, grooved)
    SK_FILL gr_grip_a, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, GUN_BAKE_2, 7
    SK_FILL gr_grip_a, SKM_BOTTOM, GUN_BAKE_4, 0
    SK_BMP gr_grip_a, SKF_RIGHT, 0, 0, gr_grip_a_right
    SK_BMP gr_grip_a, SKF_LEFT, 0, 0, gr_grip_a_left
    SK_BMP gr_grip_a, SKF_TOP, 0, 0, gr_grip_a_top
    SK_BMP gr_grip_a, SKF_BACK, 0, 0, gr_grip_a_back
    SK_BMP gr_grip_a, SKF_FRONT, 0, 0, gr_grip_a_front
    ; --- gr_grip_b  (bakelite pistol grip, grooved)
    SK_FILL gr_grip_b, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, GUN_BAKE_2, 7
    SK_FILL gr_grip_b, SKM_BOTTOM, GUN_BAKE_4, 0
    SK_BMP gr_grip_b, SKF_RIGHT, 0, 0, gr_grip_b_right
    SK_BMP gr_grip_b, SKF_LEFT, 0, 0, gr_grip_b_left
    SK_BMP gr_grip_b, SKF_TOP, 0, 0, gr_grip_b_top
    SK_BMP gr_grip_b, SKF_BACK, 0, 0, gr_grip_b_back
    SK_BMP gr_grip_b, SKF_FRONT, 0, 0, gr_grip_b_front
    ; --- gr_guard_f  (trigger guard, front post)
    SK_FILL gr_guard_f, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, AC_IRON_4, 0
    SK_FILL gr_guard_f, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gr_guard_f, SKF_RIGHT, 0, 0, gr_guard_f_right
    SK_BMP gr_guard_f, SKF_LEFT, 0, 0, gr_guard_f_left
    SK_BMP gr_guard_f, SKF_TOP, 1, 0, gr_guard_f_top
    SK_BMP gr_guard_f, SKF_BACK, 0, 0, gr_guard_f_back
    SK_BMP gr_guard_f, SKF_FRONT, 0, 0, gr_guard_f_front
    ; --- gr_guard_b  (trigger guard, bar)
    SK_FILL gr_guard_b, SKM_RIGHT | SKM_LEFT | SKM_BACK | SKM_FRONT, AC_IRON_3, 0
    SK_FILL gr_guard_b, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gr_guard_b, SKM_TOP, AC_IRON_2, 0
    SK_BMP gr_guard_b, SKF_TOP, 0, 0, gr_guard_b_top
    ; --- gr_trigger  (trigger)
    SK_FILL gr_trigger, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, AC_IRON_4, 0
    SK_FILL gr_trigger, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gr_trigger, SKF_RIGHT, 0, 0, gr_trigger_right
    SK_BMP gr_trigger, SKF_LEFT, 0, 0, gr_trigger_left
    SK_BMP gr_trigger, SKF_TOP, 1, 0, gr_trigger_top
    SK_BMP gr_trigger, SKF_BACK, 0, 0, gr_trigger_back
    SK_BMP gr_trigger, SKF_FRONT, 0, 0, gr_trigger_front
    ; --- gr_stock_a  (walnut stock, wrist)
    SK_FILL gr_stock_a, SKM_TOP | SKM_BOTTOM | SKM_BACK | SKM_FRONT, GUN_WALNUT_3, 0
    SK_FILL gr_stock_a, SKM_RIGHT | SKM_LEFT, GUN_WALNUT_2, 15
    SK_BMP gr_stock_a, SKF_RIGHT, 0, 0, gr_stock_a_right
    SK_BMP gr_stock_a, SKF_LEFT, 0, 0, gr_stock_a_left
    SK_BMP gr_stock_a, SKF_TOP, 1, 0, gr_stock_a_top
    SK_BMP gr_stock_a, SKF_BOTTOM, 0, 2, gr_stock_a_bottom
    SK_BMP gr_stock_a, SKF_BACK, 1, 1, gr_stock_a_back
    SK_BMP gr_stock_a, SKF_FRONT, 1, 1, gr_stock_a_front
    SK_GRAD gr_stock_a, SKM_RIGHT | SKM_LEFT, 256, 228
    ; --- gr_stock_b  (walnut stock, middle)
    SK_FILL gr_stock_b, SKM_RIGHT | SKM_TOP | SKM_BACK | SKM_FRONT, GUN_WALNUT_3, 0
    SK_FILL gr_stock_b, SKM_BOTTOM, GUN_WALNUT_4, 0
    SK_FILL gr_stock_b, SKM_LEFT, GUN_WALNUT_2, 15
    SK_BMP gr_stock_b, SKF_RIGHT, 0, 0, gr_stock_b_right
    SK_BMP gr_stock_b, SKF_LEFT, 0, 0, gr_stock_b_left
    SK_BMP gr_stock_b, SKF_TOP, 1, 0, gr_stock_b_top
    SK_BMP gr_stock_b, SKF_BOTTOM, 0, 0, gr_stock_b_bottom
    SK_BMP gr_stock_b, SKF_BACK, 1, 1, gr_stock_b_back
    SK_BMP gr_stock_b, SKF_FRONT, 1, 1, gr_stock_b_front
    SK_GRAD gr_stock_b, SKM_RIGHT | SKM_LEFT, 256, 228
    ; --- gr_stock_c  (walnut stock, heel)
    SK_FILL gr_stock_c, SKM_BOTTOM | SKM_BACK | SKM_FRONT, GUN_WALNUT_3, 0
    SK_FILL gr_stock_c, SKM_RIGHT | SKM_LEFT | SKM_TOP, GUN_WALNUT_2, 15
    SK_BMP gr_stock_c, SKF_RIGHT, 0, 0, gr_stock_c_right
    SK_BMP gr_stock_c, SKF_LEFT, 0, 0, gr_stock_c_left
    SK_BMP gr_stock_c, SKF_TOP, 0, 0, gr_stock_c_top
    SK_BMP gr_stock_c, SKF_BOTTOM, 3, 0, gr_stock_c_bottom
    SK_BMP gr_stock_c, SKF_BACK, 1, 1, gr_stock_c_back
    SK_BMP gr_stock_c, SKF_FRONT, 1, 1, gr_stock_c_front
    SK_GRAD gr_stock_c, SKM_RIGHT | SKM_LEFT, 256, 228
    ; --- gr_plate  (steel butt plate with a trap door)
    SK_FILL gr_plate, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_FRONT, GUN_DARK_2, 0
    SK_FILL gr_plate, SKM_BACK, GUN_DARK_3, 0
    SK_FILL gr_plate, SKM_BOTTOM, GUN_DARK_4, 0
    SK_BMP gr_plate, SKF_RIGHT, 0, 0, gr_plate_right
    SK_BMP gr_plate, SKF_LEFT, 0, 0, gr_plate_left
    SK_BMP gr_plate, SKF_TOP, 0, 0, gr_plate_top
    SK_BMP gr_plate, SKF_BACK, 0, 0, gr_plate_back
    SK_BMP gr_plate, SKF_FRONT, 0, 0, gr_plate_front
SKMODEL_END

; ===================================================================================================
; m_gun_launcher
; ===================================================================================================
; The rocket launcher: an olive-drab tube with a flared muzzle collar (a dark bore, so that it reads empty without the
; rocket), panel lines, rivets, white stencils and a blast cone with thin hazard chevrons and a dark tail pipe, two clamp bands, a
; leather shoulder pad with stitching, two ribbed grips, a trigger guard with a trigger, and iron sights.
; Model space (texels, 64 per block, muzzle -Z): the old boxes x 64 give the extents (tube 8.3 x 8.3 x 48, grips to
; 11.5 below, muzzle at (0, 3.8, -35.8), the rocket 6.4 x 5.8 x 7 in front); this model stays within 2 texels of them
; (x -5..5, y -11..8, z -35..13).
section .rodata
; The characters of every gl_ bitmap:
;  D dark steel highlight, E dark steel deep, L leather highlight, M leather deep, O olive highlight, Q olive deep
;  b brass, c brass shade, d dark steel, e dark steel shade, i iron highlight, j iron, m leather shade, o olive drab
;  q olive shade, x bore, pure dark, y hazard yellow, z white paint, stencil
align 8
gl_pal:
    PALC 'D', GUN_DARK_1
    PALC 'E', GUN_DARK_4
    PALC 'L', AC_LEATHER_1
    PALC 'M', AC_LEATHER_4
    PALC 'O', GUN_OLIVE_1
    PALC 'Q', GUN_OLIVE_4
    PALC 'b', AC_GOLD_3
    PALC 'c', AC_GOLD_4
    PALC 'd', GUN_DARK_2
    PALC 'e', GUN_DARK_3
    PALC 'i', AC_IRON_2
    PALC 'j', AC_IRON_3
    PALC 'm', AC_LEATHER_3
    PALC 'o', GUN_OLIVE_2
    PALC 'q', GUN_OLIVE_3
    PALC 'x', GUN_BORE
    PALC 'y', GUN_YELLOW
    PALC 'z', GUN_WHITE
    dq 0

    ; gl_tube_a_right (11x8 at 0,0 of the 11x8 RIGHT face)
    SKROWS gl_tube_a_right_rows, 11, 8
    SKROW "OOOOOOOOOOO"
    SKROW "Q..Qq...QQ."
    SKROW "q...q......"
    SKROW "....q......"
    SKROW "q...q......"
    SKROW "....q......"
    SKROW "qqqqqqqqqqq"
    SKROW "qqqqqqqqqqq"
    SKROWS_END
    align 8
    SKBMP gl_tube_a_right, gl_tube_a_right_rows, 11, 8, gl_pal
    ; gl_tube_a_left (11x8 at 0,0 of the 11x8 LEFT face)
    SKROWS gl_tube_a_left_rows, 11, 8
    SKROW "OOOOOOOOOOO"
    SKROW "..Q...q...Q"
    SKROW "......q...."
    SKROW ".Q....q...."
    SKROW "......q...."
    SKROW "......q...."
    SKROW "qqqqqqqqqqq"
    SKROW "qqqqqqqqqqq"
    SKROWS_END
    align 8
    SKBMP gl_tube_a_left, gl_tube_a_left_rows, 11, 8, gl_pal
    ; gl_tube_a_top (8x11 at 0,0 of the 8x11 TOP face)
    SKROWS gl_tube_a_top_rows, 8, 11
    SKROW "qQ.q..QO"
    SKROW "q..q...O"
    SKROW "q..q...O"
    SKROW "q..q...O"
    SKROW "qqqqqqqq"
    SKROW "q..q...O"
    SKROW "q..q...O"
    SKROW "q..q...O"
    SKROW "qQ.q..QO"
    SKROW "q..q...O"
    SKROW "q..q...O"
    SKROWS_END
    align 8
    SKBMP gl_tube_a_top, gl_tube_a_top_rows, 8, 11, gl_pal
    ; gl_tube_a_bottom (8x1 at 0,6 of the 8x11 BOTTOM face)
    SKROWS gl_tube_a_bottom_rows, 8, 1
    SKROW "qqqqqqqq"
    SKROWS_END
    align 8
    SKBMP gl_tube_a_bottom, gl_tube_a_bottom_rows, 8, 1, gl_pal
    ; gl_tube_b_right (11x8 at 0,0 of the 11x8 RIGHT face)
    SKROWS gl_tube_b_right_rows, 11, 8
    SKROW "OOOOOOOOOOO"
    SKROW "..Q.q......"
    SKROW "zz.zz.zzz.."
    SKROW "..Q.q......"
    SKROW "zzz.zzzzz.."
    SKROW "....q....Q."
    SKROW "qqqqqqqqqqq"
    SKROW "qqqqqqqqqqq"
    SKROWS_END
    align 8
    SKBMP gl_tube_b_right, gl_tube_b_right_rows, 11, 8, gl_pal
    ; gl_tube_b_left (11x8 at 0,0 of the 11x8 LEFT face)
    SKROWS gl_tube_b_left_rows, 11, 8
    SKROW "OOOOOOOOOOO"
    SKROW ".Qq...q.Q.Q"
    SKROW "..zzz.zz.zz"
    SKROW "......qQ..."
    SKROW "..zzzzz.zzz"
    SKROW "......q...."
    SKROW "qqqqqqqqqqq"
    SKROW "qqqqqqqqqqq"
    SKROWS_END
    align 8
    SKBMP gl_tube_b_left, gl_tube_b_left_rows, 11, 8, gl_pal
    ; gl_tube_b_top (8x11 at 0,0 of the 8x11 TOP face)
    SKROWS gl_tube_b_top_rows, 8, 11
    SKROW "q..q...O"
    SKROW "q..q...O"
    SKROW "qQ.q..QO"
    SKROW "q..q...O"
    SKROW "qqqqqqqq"
    SKROW "q..q...O"
    SKROW "q..q...O"
    SKROW "q..q...O"
    SKROW "q..q...O"
    SKROW "q..q...O"
    SKROW "q..q...O"
    SKROWS_END
    align 8
    SKBMP gl_tube_b_top, gl_tube_b_top_rows, 8, 11, gl_pal
    ; gl_tube_b_bottom (8x1 at 0,6 of the 8x11 BOTTOM face)
    SKROWS gl_tube_b_bottom_rows, 8, 1
    SKROW "qqqqqqqq"
    SKROWS_END
    align 8
    SKBMP gl_tube_b_bottom, gl_tube_b_bottom_rows, 8, 1, gl_pal
    ; gl_tube_c_right (11x8 at 0,0 of the 11x8 RIGHT face)
    SKROWS gl_tube_c_right_rows, 11, 8
    SKROW "OOOOOOOOOOO"
    SKROW "...q.Q....."
    SKROW "...q.yxy.Qz"
    SKROW "...q.yxy..."
    SKROW "...q.yxy..z"
    SKROW "...q...q.Q."
    SKROW "qqqqqqqqqqq"
    SKROW "qqqqqqqqqqq"
    SKROWS_END
    align 8
    SKBMP gl_tube_c_right, gl_tube_c_right_rows, 11, 8, gl_pal
    ; gl_tube_c_left (11x8 at 0,0 of the 11x8 LEFT face)
    SKROWS gl_tube_c_left_rows, 11, 8
    SKROW "OOOOOOOOOOO"
    SKROW ".....Q.qQ.Q"
    SKROW "z..yxyQq..."
    SKROW "..Qyxy.q..."
    SKROW "z..yxy.q..."
    SKROW ".......q..."
    SKROW "qqqqqqqqqqq"
    SKROW "qqqqqqqqqqq"
    SKROWS_END
    align 8
    SKBMP gl_tube_c_left, gl_tube_c_left_rows, 11, 8, gl_pal
    ; gl_tube_c_top (8x11 at 0,0 of the 8x11 TOP face)
    SKROWS gl_tube_c_top_rows, 8, 11
    SKROW "q..q...O"
    SKROW "q..q...O"
    SKROW "q..q...O"
    SKROW "qqqqqqqq"
    SKROW "q..q...O"
    SKROW "qQ.q..QO"
    SKROW "q..q...O"
    SKROW "q..q...O"
    SKROW "q..q...O"
    SKROW "q..q...O"
    SKROW "q..q...O"
    SKROWS_END
    align 8
    SKBMP gl_tube_c_top, gl_tube_c_top_rows, 8, 11, gl_pal
    ; gl_tube_c_bottom (8x1 at 0,7 of the 8x11 BOTTOM face)
    SKROWS gl_tube_c_bottom_rows, 8, 1
    SKROW "qqqqqqqq"
    SKROWS_END
    align 8
    SKBMP gl_tube_c_bottom, gl_tube_c_bottom_rows, 8, 1, gl_pal
    ; gl_tube_d_right (8x8 at 0,0 of the 8x8 RIGHT face)
    SKROWS gl_tube_d_right_rows, 8, 8
    SKROW "OOOOOOOO"
    SKROW ".Q.q...."
    SKROW "...q.q.."
    SKROW "...q.Q.."
    SKROW "...q...."
    SKROW "...q...."
    SKROW "qqqqqqqq"
    SKROW "qqqqqqqq"
    SKROWS_END
    align 8
    SKBMP gl_tube_d_right, gl_tube_d_right_rows, 8, 8, gl_pal
    ; gl_tube_d_left (8x8 at 0,0 of the 8x8 LEFT face)
    SKROWS gl_tube_d_left_rows, 8, 8
    SKROW "OOOOOOOO"
    SKROW ".QQ...Q."
    SKROW "........"
    SKROW "....Q..."
    SKROW "....q..."
    SKROW "....q..."
    SKROW "qqqqqqqq"
    SKROW "qqqqqqqq"
    SKROWS_END
    align 8
    SKBMP gl_tube_d_left, gl_tube_d_left_rows, 8, 8, gl_pal
    ; gl_tube_d_top (8x8 at 0,0 of the 8x8 TOP face)
    SKROWS gl_tube_d_top_rows, 8, 8
    SKROW "q..q...O"
    SKROW "qQ.q..QO"
    SKROW "q..q...O"
    SKROW "qqqqqqqq"
    SKROW "q..q...O"
    SKROW "qQ.q..QO"
    SKROW "q..q...O"
    SKROW "q..q...O"
    SKROWS_END
    align 8
    SKBMP gl_tube_d_top, gl_tube_d_top_rows, 8, 8, gl_pal
    ; gl_tube_d_bottom (8x1 at 0,4 of the 8x8 BOTTOM face)
    SKROWS gl_tube_d_bottom_rows, 8, 1
    SKROW "qqqqqqqq"
    SKROWS_END
    align 8
    SKBMP gl_tube_d_bottom, gl_tube_d_bottom_rows, 8, 1, gl_pal
    ; gl_ring_right (3x8 at 0,0 of the 3x8 RIGHT face)
    SKROWS gl_ring_right_rows, 3, 8
    SKROW "OOO"
    SKROW "q.."
    SKROW "q.."
    SKROW "q.."
    SKROW "q.."
    SKROW "q.."
    SKROW "q.."
    SKROW "qqq"
    SKROWS_END
    align 8
    SKBMP gl_ring_right, gl_ring_right_rows, 3, 8, gl_pal
    ; gl_ring_left (3x8 at 0,0 of the 3x8 LEFT face)
    SKROWS gl_ring_left_rows, 3, 8
    SKROW "OOO"
    SKROW "..q"
    SKROW "..q"
    SKROW "..q"
    SKROW "..q"
    SKROW "..q"
    SKROW "..q"
    SKROW "qqq"
    SKROWS_END
    align 8
    SKBMP gl_ring_left, gl_ring_left_rows, 3, 8, gl_pal
    ; gl_ring_top (8x2 at 0,0 of the 8x3 TOP face)
    SKROWS gl_ring_top_rows, 8, 2
    SKROW "qqqqqqqq"
    SKROW "oooooooo"
    SKROWS_END
    align 8
    SKBMP gl_ring_top, gl_ring_top_rows, 8, 2, gl_pal
    ; gl_ring_back (8x8 at 0,0 of the 8x8 BACK face)
    SKROWS gl_ring_back_rows, 8, 8
    SKROW "OOOOOOOO"
    SKROW "O......q"
    SKROW "O......q"
    SKROW "O......q"
    SKROW "O......q"
    SKROW "O......q"
    SKROW "O......q"
    SKROW "qqqqqqqq"
    SKROWS_END
    align 8
    SKBMP gl_ring_back, gl_ring_back_rows, 8, 8, gl_pal
    ; gl_ring_front (7x7 at 0,0 of the 8x8 FRONT face)
    SKROWS gl_ring_front_rows, 7, 7
    SKROW "OOOOOOO"
    SKROW "O......"
    SKROW "O.xxxxQ"
    SKROW "O.xxxxQ"
    SKROW "O.xxxxQ"
    SKROW "O.xxxxQ"
    SKROW "O.QQQQQ"
    SKROWS_END
    align 8
    SKBMP gl_ring_front, gl_ring_front_rows, 7, 7, gl_pal
    ; gl_cone_right (3x7 at 0,0 of the 3x8 RIGHT face)
    SKROWS gl_cone_right_rows, 3, 7
    SKROW "yy."
    SKROW "y.."
    SKROW "..."
    SKROW "..y"
    SKROW ".yy"
    SKROW "yy."
    SKROW "y.."
    SKROWS_END
    align 8
    SKBMP gl_cone_right, gl_cone_right_rows, 3, 7, gl_pal
    ; gl_cone_left (3x7 at 0,0 of the 3x8 LEFT face)
    SKROWS gl_cone_left_rows, 3, 7
    SKROW "yy."
    SKROW "y.."
    SKROW "..."
    SKROW "..y"
    SKROW ".yy"
    SKROW "yy."
    SKROW "y.."
    SKROWS_END
    align 8
    SKBMP gl_cone_left, gl_cone_left_rows, 3, 7, gl_pal
    ; gl_cone_top (7x3 at 0,0 of the 8x3 TOP face)
    SKROWS gl_cone_top_rows, 7, 3
    SKROW "yy...yy"
    SKROW "y...yy."
    SKROW "...yy.."
    SKROWS_END
    align 8
    SKBMP gl_cone_top, gl_cone_top_rows, 7, 3, gl_pal
    ; gl_cone_bottom (7x3 at 0,0 of the 8x3 BOTTOM face)
    SKROWS gl_cone_bottom_rows, 7, 3
    SKROW "yy...yy"
    SKROW "y...yy."
    SKROW "...yy.."
    SKROWS_END
    align 8
    SKBMP gl_cone_bottom, gl_cone_bottom_rows, 7, 3, gl_pal
    ; gl_cone_back (7x7 at 0,0 of the 8x8 BACK face)
    SKROWS gl_cone_back_rows, 7, 7
    SKROW "OOOOOOO"
    SKROW "O......"
    SKROW "OQeeeeQ"
    SKROW "OQxxxxQ"
    SKROW "OQxxxxQ"
    SKROW "OQxxxxQ"
    SKROW "OQQQQQQ"
    SKROWS_END
    align 8
    SKBMP gl_cone_back, gl_cone_back_rows, 7, 7, gl_pal
    ; gl_band_a_right (2x8 at 0,0 of the 2x8 RIGHT face)
    SKROWS gl_band_a_right_rows, 2, 8
    SKROW "e."
    SKROW "e."
    SKROW "e."
    SKROW "EE"
    SKROW "e."
    SKROW "e."
    SKROW "e."
    SKROW "e."
    SKROWS_END
    align 8
    SKBMP gl_band_a_right, gl_band_a_right_rows, 2, 8, gl_pal
    ; gl_band_a_left (2x8 at 0,0 of the 2x8 LEFT face)
    SKROWS gl_band_a_left_rows, 2, 8
    SKROW ".e"
    SKROW ".e"
    SKROW ".e"
    SKROW "EE"
    SKROW ".e"
    SKROW ".e"
    SKROW ".e"
    SKROW ".e"
    SKROWS_END
    align 8
    SKBMP gl_band_a_left, gl_band_a_left_rows, 2, 8, gl_pal
    ; gl_band_a_top (8x1 at 0,1 of the 8x2 TOP face)
    SKROWS gl_band_a_top_rows, 8, 1
    SKROW "DDcbDDDD"
    SKROWS_END
    align 8
    SKBMP gl_band_a_top, gl_band_a_top_rows, 8, 1, gl_pal
    ; gl_band_a_back (8x8 at 0,0 of the 8x8 BACK face)
    SKROWS gl_band_a_back_rows, 8, 8
    SKROW "DDDDDDDD"
    SKROW "D......e"
    SKROW "D......e"
    SKROW "D......e"
    SKROW "D......e"
    SKROW "D......e"
    SKROW "D......e"
    SKROW "eeeeeeee"
    SKROWS_END
    align 8
    SKBMP gl_band_a_back, gl_band_a_back_rows, 8, 8, gl_pal
    ; gl_band_a_front (8x8 at 0,0 of the 8x8 FRONT face)
    SKROWS gl_band_a_front_rows, 8, 8
    SKROW "DDDDDDDD"
    SKROW "e......D"
    SKROW "e......D"
    SKROW "e......D"
    SKROW "e......D"
    SKROW "e......D"
    SKROW "e......D"
    SKROW "eeeeeeee"
    SKROWS_END
    align 8
    SKBMP gl_band_a_front, gl_band_a_front_rows, 8, 8, gl_pal
    ; gl_pad_right (10x1 at 0,0 of the 10x2 RIGHT face)
    SKROWS gl_pad_right_rows, 10, 1
    SKROW "MLMLMLMLML"
    SKROWS_END
    align 8
    SKBMP gl_pad_right, gl_pad_right_rows, 10, 1, gl_pal
    ; gl_pad_left (10x1 at 0,0 of the 10x2 LEFT face)
    SKROWS gl_pad_left_rows, 10, 1
    SKROW "LMLMLMLMLM"
    SKROWS_END
    align 8
    SKBMP gl_pad_left, gl_pad_left_rows, 10, 1, gl_pal
    ; gl_pad_bottom (6x10 at 0,0 of the 6x10 BOTTOM face)
    SKROWS gl_pad_bottom_rows, 6, 10
    SKROW "MMMMMM"
    SKROW "......"
    SKROW ".M..M."
    SKROW "......"
    SKROW ".M..M."
    SKROW "......"
    SKROW ".M..M."
    SKROW "......"
    SKROW ".M..M."
    SKROW "MMMMMM"
    SKROWS_END
    align 8
    SKBMP gl_pad_bottom, gl_pad_bottom_rows, 6, 10, gl_pal
    ; gl_pad_back (6x1 at 0,1 of the 6x2 BACK face)
    SKROWS gl_pad_back_rows, 6, 1
    SKROW "mmmmmm"
    SKROWS_END
    align 8
    SKBMP gl_pad_back, gl_pad_back_rows, 6, 1, gl_pal
    ; gl_pad_front (6x1 at 0,1 of the 6x2 FRONT face)
    SKROWS gl_pad_front_rows, 6, 1
    SKROW "mmmmmm"
    SKROWS_END
    align 8
    SKBMP gl_pad_front, gl_pad_front_rows, 6, 1, gl_pal
    ; gl_grip_right (5x11 at 0,0 of the 5x11 RIGHT face)
    SKROWS gl_grip_right_rows, 5, 11
    SKROW "DDDDD"
    SKROW "....."
    SKROW "eeeee"
    SKROW "....."
    SKROW "eeeee"
    SKROW "....."
    SKROW "eeeee"
    SKROW "....."
    SKROW "eeeee"
    SKROW "....."
    SKROW "eeeee"
    SKROWS_END
    align 8
    SKBMP gl_grip_right, gl_grip_right_rows, 5, 11, gl_pal
    ; gl_grip_left (5x11 at 0,0 of the 5x11 LEFT face)
    SKROWS gl_grip_left_rows, 5, 11
    SKROW "DDDDD"
    SKROW "....."
    SKROW "eeeee"
    SKROW "....."
    SKROW "eeeee"
    SKROW "....."
    SKROW "eeeee"
    SKROW "....."
    SKROW "eeeee"
    SKROW "....."
    SKROW "eeeee"
    SKROWS_END
    align 8
    SKBMP gl_grip_left, gl_grip_left_rows, 5, 11, gl_pal
    ; gl_grip_top (4x5 at 0,0 of the 4x5 TOP face)
    SKROWS gl_grip_top_rows, 4, 5
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROWS_END
    align 8
    SKBMP gl_grip_top, gl_grip_top_rows, 4, 5, gl_pal
    ; gl_grip_bottom (2x3 at 1,1 of the 4x5 BOTTOM face)
    SKROWS gl_grip_bottom_rows, 2, 3
    SKROW "ee"
    SKROW "ee"
    SKROW "ee"
    SKROWS_END
    align 8
    SKBMP gl_grip_bottom, gl_grip_bottom_rows, 2, 3, gl_pal
    ; gl_grip_back (4x11 at 0,0 of the 4x11 BACK face)
    SKROWS gl_grip_back_rows, 4, 11
    SKROW "DDDe"
    SKROW "D..e"
    SKROW "D..e"
    SKROW "D..e"
    SKROW "D..e"
    SKROW "D..e"
    SKROW "D..e"
    SKROW "D..e"
    SKROW "D..e"
    SKROW "D..e"
    SKROW "D..e"
    SKROWS_END
    align 8
    SKBMP gl_grip_back, gl_grip_back_rows, 4, 11, gl_pal
    ; gl_grip_front (4x11 at 0,0 of the 4x11 FRONT face)
    SKROWS gl_grip_front_rows, 4, 11
    SKROW "DDDD"
    SKROW "...."
    SKROW "eeee"
    SKROW "...."
    SKROW "eeee"
    SKROW "...."
    SKROW "eeee"
    SKROW "...."
    SKROW "eeee"
    SKROW "...."
    SKROW "eeee"
    SKROWS_END
    align 8
    SKBMP gl_grip_front, gl_grip_front_rows, 4, 11, gl_pal
    ; gl_fgrip_right (4x8 at 0,0 of the 4x10 RIGHT face)
    SKROWS gl_fgrip_right_rows, 4, 8
    SKROW "DDDD"
    SKROW "dddd"
    SKROW "...."
    SKROW "dddd"
    SKROW "...."
    SKROW "dddd"
    SKROW "...."
    SKROW "dddd"
    SKROWS_END
    align 8
    SKBMP gl_fgrip_right, gl_fgrip_right_rows, 4, 8, gl_pal
    ; gl_fgrip_left (4x8 at 0,0 of the 4x10 LEFT face)
    SKROWS gl_fgrip_left_rows, 4, 8
    SKROW "DDDD"
    SKROW "dddd"
    SKROW "...."
    SKROW "dddd"
    SKROW "...."
    SKROW "dddd"
    SKROW "...."
    SKROW "dddd"
    SKROWS_END
    align 8
    SKBMP gl_fgrip_left, gl_fgrip_left_rows, 4, 8, gl_pal
    ; gl_fgrip_top (4x4 at 0,0 of the 4x4 TOP face)
    SKROWS gl_fgrip_top_rows, 4, 4
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROWS_END
    align 8
    SKBMP gl_fgrip_top, gl_fgrip_top_rows, 4, 4, gl_pal
    ; gl_fgrip_bottom (2x2 at 1,1 of the 4x4 BOTTOM face)
    SKROWS gl_fgrip_bottom_rows, 2, 2
    SKROW "ee"
    SKROW "ee"
    SKROWS_END
    align 8
    SKBMP gl_fgrip_bottom, gl_fgrip_bottom_rows, 2, 2, gl_pal
    ; gl_fgrip_back (4x10 at 0,0 of the 4x10 BACK face)
    SKROWS gl_fgrip_back_rows, 4, 10
    SKROW "DDDe"
    SKROW "D..e"
    SKROW "D..e"
    SKROW "D..e"
    SKROW "D..e"
    SKROW "D..e"
    SKROW "D..e"
    SKROW "D..e"
    SKROW "D..e"
    SKROW "D..e"
    SKROWS_END
    align 8
    SKBMP gl_fgrip_back, gl_fgrip_back_rows, 4, 10, gl_pal
    ; gl_fgrip_front (4x9 at 0,0 of the 4x10 FRONT face)
    SKROWS gl_fgrip_front_rows, 4, 9
    SKROW "DDDD"
    SKROW "...."
    SKROW "eeee"
    SKROW "...."
    SKROW "eeee"
    SKROW "...."
    SKROW "eeee"
    SKROW "...."
    SKROW "eeee"
    SKROWS_END
    align 8
    SKBMP gl_fgrip_front, gl_fgrip_front_rows, 4, 9, gl_pal
    ; gl_guard_f_right (1x2 at 0,0 of the 1x3 RIGHT face)
    SKROWS gl_guard_f_right_rows, 1, 2
    SKROW "i"
    SKROW "j"
    SKROWS_END
    align 8
    SKBMP gl_guard_f_right, gl_guard_f_right_rows, 1, 2, gl_pal
    ; gl_guard_f_left (1x2 at 0,0 of the 1x3 LEFT face)
    SKROWS gl_guard_f_left_rows, 1, 2
    SKROW "i"
    SKROW "j"
    SKROWS_END
    align 8
    SKBMP gl_guard_f_left, gl_guard_f_left_rows, 1, 2, gl_pal
    ; gl_guard_f_top (1x1 at 1,0 of the 2x1 TOP face)
    SKROWS gl_guard_f_top_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gl_guard_f_top, gl_guard_f_top_rows, 1, 1, gl_pal
    ; gl_guard_f_back (2x2 at 0,0 of the 2x3 BACK face)
    SKROWS gl_guard_f_back_rows, 2, 2
    SKROW "ii"
    SKROW "jj"
    SKROWS_END
    align 8
    SKBMP gl_guard_f_back, gl_guard_f_back_rows, 2, 2, gl_pal
    ; gl_guard_f_front (2x2 at 0,0 of the 2x3 FRONT face)
    SKROWS gl_guard_f_front_rows, 2, 2
    SKROW "ii"
    SKROW "jj"
    SKROWS_END
    align 8
    SKBMP gl_guard_f_front, gl_guard_f_front_rows, 2, 2, gl_pal
    ; gl_guard_b_top (1x7 at 0,0 of the 2x7 TOP face)
    SKROWS gl_guard_b_top_rows, 1, 7
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROWS_END
    align 8
    SKBMP gl_guard_b_top, gl_guard_b_top_rows, 1, 7, gl_pal
    ; gl_trigger_right (1x2 at 0,0 of the 1x3 RIGHT face)
    SKROWS gl_trigger_right_rows, 1, 2
    SKROW "i"
    SKROW "j"
    SKROWS_END
    align 8
    SKBMP gl_trigger_right, gl_trigger_right_rows, 1, 2, gl_pal
    ; gl_trigger_left (1x2 at 0,0 of the 1x3 LEFT face)
    SKROWS gl_trigger_left_rows, 1, 2
    SKROW "i"
    SKROW "j"
    SKROWS_END
    align 8
    SKBMP gl_trigger_left, gl_trigger_left_rows, 1, 2, gl_pal
    ; gl_trigger_top (1x1 at 1,0 of the 2x1 TOP face)
    SKROWS gl_trigger_top_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gl_trigger_top, gl_trigger_top_rows, 1, 1, gl_pal
    ; gl_trigger_back (2x2 at 0,0 of the 2x3 BACK face)
    SKROWS gl_trigger_back_rows, 2, 2
    SKROW "ii"
    SKROW "jj"
    SKROWS_END
    align 8
    SKBMP gl_trigger_back, gl_trigger_back_rows, 2, 2, gl_pal
    ; gl_trigger_front (2x2 at 0,0 of the 2x3 FRONT face)
    SKROWS gl_trigger_front_rows, 2, 2
    SKROW "ii"
    SKROW "jj"
    SKROWS_END
    align 8
    SKBMP gl_trigger_front, gl_trigger_front_rows, 2, 2, gl_pal
    ; gl_rsight_top (1x1 at 1,0 of the 2x1 TOP face)
    SKROWS gl_rsight_top_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gl_rsight_top, gl_rsight_top_rows, 1, 1, gl_pal
    ; gl_rsight_back (1x1 at 0,0 of the 2x1 BACK face)
    SKROWS gl_rsight_back_rows, 1, 1
    SKROW "x"
    SKROWS_END
    align 8
    SKBMP gl_rsight_back, gl_rsight_back_rows, 1, 1, gl_pal
    ; gl_fsight_top (1x1 at 1,0 of the 2x1 TOP face)
    SKROWS gl_fsight_top_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gl_fsight_top, gl_fsight_top_rows, 1, 1, gl_pal

section .data
SKMODEL_BEGIN m_gun_launcher, 64, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART gl_tube_a, -4, -1, -32, 8, 8, 11, 0, 0                   ; olive drab tube with panel lines, rivets and stencils
    PART gl_tube_b, -4, -1, -21, 8, 8, 11, 0, 0                   ; olive drab tube with panel lines, rivets and stencils
    PART gl_tube_c, -4, -1, -10, 8, 8, 11, 0, 0                   ; olive drab tube with panel lines, rivets and stencils
    PART gl_tube_d, -4, -1, 1, 8, 8, 8, 0, 0                      ; olive drab tube with panel lines, rivets and stencils
    PART gl_ring, -4, -1, -35, 8, 8, 3, 3, 0                      ; flared muzzle collar, dark bore
    PART gl_cone, -4, -1, 9, 8, 8, 3, 4, 0                        ; hazard-striped blast cone with a dark tail pipe
    PART gl_band_a, -4, -1, -27, 8, 8, 2, 3, 0                    ; dark steel clamp band
    PART_AS gl_band_b, gl_band_a, -4, -1, -4, 3, 0                ; mirrored twin of band_a
    PART gl_pad, -3, -3, -2, 6, 2, 10, 0, 0                       ; leather shoulder pad with stitching
    PART gl_grip, -2, -11, -3, 4, 11, 5, 0, 0                     ; ribbed polymer grip
    PART gl_fgrip, -2, -10, -19, 4, 10, 4, 0, 0                   ; ribbed polymer grip
    PART gl_guard_f, -1, -4, -10, 2, 3, 1, 0, 0                   ; trigger guard, front post
    PART gl_guard_b, -1, -5, -10, 2, 1, 7, 0, 0                   ; trigger guard, bar
    PART gl_trigger, -1, -4, -6, 2, 3, 1, 0, 0                    ; trigger
    PART gl_rsight, -1, 7, -6, 2, 1, 1, 0, 0                      ; rear sight
    PART gl_fsight, -1, 7, -31, 2, 1, 1, 0, 0                     ; front sight with a white dot
SKMODEL_PAINT
    ; --- gl_tube_a  (olive drab tube with panel lines, rivets and stencils)
    SK_FILL gl_tube_a, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, GUN_OLIVE_2, 7
    SK_FILL gl_tube_a, SKM_BOTTOM, GUN_OLIVE_4, 0
    SK_BMP gl_tube_a, SKF_RIGHT, 0, 0, gl_tube_a_right
    SK_BMP gl_tube_a, SKF_LEFT, 0, 0, gl_tube_a_left
    SK_BMP gl_tube_a, SKF_TOP, 0, 0, gl_tube_a_top
    SK_BMP gl_tube_a, SKF_BOTTOM, 0, 6, gl_tube_a_bottom
    SK_GRAD gl_tube_a, SKM_RIGHT | SKM_LEFT, 268, 224
    ; --- gl_tube_b  (olive drab tube with panel lines, rivets and stencils)
    SK_FILL gl_tube_b, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, GUN_OLIVE_2, 7
    SK_FILL gl_tube_b, SKM_BOTTOM, GUN_OLIVE_4, 0
    SK_BMP gl_tube_b, SKF_RIGHT, 0, 0, gl_tube_b_right
    SK_BMP gl_tube_b, SKF_LEFT, 0, 0, gl_tube_b_left
    SK_BMP gl_tube_b, SKF_TOP, 0, 0, gl_tube_b_top
    SK_BMP gl_tube_b, SKF_BOTTOM, 0, 6, gl_tube_b_bottom
    SK_GRAD gl_tube_b, SKM_RIGHT | SKM_LEFT, 268, 224
    ; --- gl_tube_c  (olive drab tube with panel lines, rivets and stencils)
    SK_FILL gl_tube_c, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, GUN_OLIVE_2, 7
    SK_FILL gl_tube_c, SKM_BOTTOM, GUN_OLIVE_4, 0
    SK_BMP gl_tube_c, SKF_RIGHT, 0, 0, gl_tube_c_right
    SK_BMP gl_tube_c, SKF_LEFT, 0, 0, gl_tube_c_left
    SK_BMP gl_tube_c, SKF_TOP, 0, 0, gl_tube_c_top
    SK_BMP gl_tube_c, SKF_BOTTOM, 0, 7, gl_tube_c_bottom
    SK_GRAD gl_tube_c, SKM_RIGHT | SKM_LEFT, 268, 224
    ; --- gl_tube_d  (olive drab tube with panel lines, rivets and stencils)
    SK_FILL gl_tube_d, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, GUN_OLIVE_2, 7
    SK_FILL gl_tube_d, SKM_BOTTOM, GUN_OLIVE_4, 0
    SK_BMP gl_tube_d, SKF_RIGHT, 0, 0, gl_tube_d_right
    SK_BMP gl_tube_d, SKF_LEFT, 0, 0, gl_tube_d_left
    SK_BMP gl_tube_d, SKF_TOP, 0, 0, gl_tube_d_top
    SK_BMP gl_tube_d, SKF_BOTTOM, 0, 4, gl_tube_d_bottom
    SK_GRAD gl_tube_d, SKM_RIGHT | SKM_LEFT, 268, 224
    ; --- gl_ring  (flared muzzle collar, dark bore)
    SK_FILL gl_ring, SKM_FRONT, GUN_OLIVE_3, 0
    SK_FILL gl_ring, SKM_RIGHT | SKM_LEFT | SKM_BOTTOM | SKM_BACK, GUN_OLIVE_2, 7
    SK_FILL gl_ring, SKM_TOP, GUN_OLIVE_1, 0
    SK_BMP gl_ring, SKF_RIGHT, 0, 0, gl_ring_right
    SK_BMP gl_ring, SKF_LEFT, 0, 0, gl_ring_left
    SK_BMP gl_ring, SKF_TOP, 0, 0, gl_ring_top
    SK_BMP gl_ring, SKF_BACK, 0, 0, gl_ring_back
    SK_BMP gl_ring, SKF_FRONT, 0, 0, gl_ring_front
    SK_GRAD gl_ring, SKM_RIGHT | SKM_LEFT, 268, 224
    ; --- gl_cone  (hazard-striped blast cone with a dark tail pipe)
    SK_FILL gl_cone, SKM_FRONT, GUN_OLIVE_2, 7
    SK_FILL gl_cone, SKM_BACK, GUN_OLIVE_3, 0
    SK_FILL gl_cone, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BOTTOM, GUN_OLIVE_4, 0
    SK_BMP gl_cone, SKF_RIGHT, 0, 0, gl_cone_right
    SK_BMP gl_cone, SKF_LEFT, 0, 0, gl_cone_left
    SK_BMP gl_cone, SKF_TOP, 0, 0, gl_cone_top
    SK_BMP gl_cone, SKF_BOTTOM, 0, 0, gl_cone_bottom
    SK_BMP gl_cone, SKF_BACK, 0, 0, gl_cone_back
    ; --- gl_band_a  (dark steel clamp band)
    SK_FILL gl_band_a, SKM_BACK | SKM_FRONT, GUN_DARK_2, 0
    SK_FILL gl_band_a, SKM_BOTTOM, GUN_DARK_4, 0
    SK_FILL gl_band_a, SKM_TOP, GUN_DARK_3, 0
    SK_FILL gl_band_a, SKM_RIGHT | SKM_LEFT, GUN_DARK_1, 0
    SK_BMP gl_band_a, SKF_RIGHT, 0, 0, gl_band_a_right
    SK_BMP gl_band_a, SKF_LEFT, 0, 0, gl_band_a_left
    SK_BMP gl_band_a, SKF_TOP, 0, 1, gl_band_a_top
    SK_BMP gl_band_a, SKF_BACK, 0, 0, gl_band_a_back
    SK_BMP gl_band_a, SKF_FRONT, 0, 0, gl_band_a_front
    ; --- gl_pad  (leather shoulder pad with stitching)
    SK_FILL gl_pad, SKM_BACK | SKM_FRONT, AC_LEATHER_1, 0
    SK_FILL gl_pad, SKM_RIGHT | SKM_LEFT | SKM_BOTTOM, AC_LEATHER_3, 0
    SK_FILL gl_pad, SKM_TOP, AC_LEATHER_2, 7
    SK_BMP gl_pad, SKF_RIGHT, 0, 0, gl_pad_right
    SK_BMP gl_pad, SKF_LEFT, 0, 0, gl_pad_left
    SK_BMP gl_pad, SKF_BOTTOM, 0, 0, gl_pad_bottom
    SK_BMP gl_pad, SKF_BACK, 0, 1, gl_pad_back
    SK_BMP gl_pad, SKF_FRONT, 0, 1, gl_pad_front
    ; --- gl_grip  (ribbed polymer grip)
    SK_FILL gl_grip, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, GUN_DARK_2, 0
    SK_FILL gl_grip, SKM_BOTTOM, GUN_DARK_4, 0
    SK_BMP gl_grip, SKF_RIGHT, 0, 0, gl_grip_right
    SK_BMP gl_grip, SKF_LEFT, 0, 0, gl_grip_left
    SK_BMP gl_grip, SKF_TOP, 0, 0, gl_grip_top
    SK_BMP gl_grip, SKF_BOTTOM, 1, 1, gl_grip_bottom
    SK_BMP gl_grip, SKF_BACK, 0, 0, gl_grip_back
    SK_BMP gl_grip, SKF_FRONT, 0, 0, gl_grip_front
    ; --- gl_fgrip  (ribbed polymer grip)
    SK_FILL gl_fgrip, SKM_TOP | SKM_BACK | SKM_FRONT, GUN_DARK_2, 0
    SK_FILL gl_fgrip, SKM_BOTTOM, GUN_DARK_4, 0
    SK_FILL gl_fgrip, SKM_RIGHT | SKM_LEFT, GUN_DARK_3, 0
    SK_BMP gl_fgrip, SKF_RIGHT, 0, 0, gl_fgrip_right
    SK_BMP gl_fgrip, SKF_LEFT, 0, 0, gl_fgrip_left
    SK_BMP gl_fgrip, SKF_TOP, 0, 0, gl_fgrip_top
    SK_BMP gl_fgrip, SKF_BOTTOM, 1, 1, gl_fgrip_bottom
    SK_BMP gl_fgrip, SKF_BACK, 0, 0, gl_fgrip_back
    SK_BMP gl_fgrip, SKF_FRONT, 0, 0, gl_fgrip_front
    ; --- gl_guard_f  (trigger guard, front post)
    SK_FILL gl_guard_f, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, AC_IRON_4, 0
    SK_FILL gl_guard_f, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gl_guard_f, SKF_RIGHT, 0, 0, gl_guard_f_right
    SK_BMP gl_guard_f, SKF_LEFT, 0, 0, gl_guard_f_left
    SK_BMP gl_guard_f, SKF_TOP, 1, 0, gl_guard_f_top
    SK_BMP gl_guard_f, SKF_BACK, 0, 0, gl_guard_f_back
    SK_BMP gl_guard_f, SKF_FRONT, 0, 0, gl_guard_f_front
    ; --- gl_guard_b  (trigger guard, bar)
    SK_FILL gl_guard_b, SKM_RIGHT | SKM_LEFT | SKM_BACK | SKM_FRONT, AC_IRON_3, 0
    SK_FILL gl_guard_b, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gl_guard_b, SKM_TOP, AC_IRON_2, 0
    SK_BMP gl_guard_b, SKF_TOP, 0, 0, gl_guard_b_top
    ; --- gl_trigger  (trigger)
    SK_FILL gl_trigger, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, AC_IRON_4, 0
    SK_FILL gl_trigger, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gl_trigger, SKF_RIGHT, 0, 0, gl_trigger_right
    SK_BMP gl_trigger, SKF_LEFT, 0, 0, gl_trigger_left
    SK_BMP gl_trigger, SKF_TOP, 1, 0, gl_trigger_top
    SK_BMP gl_trigger, SKF_BACK, 0, 0, gl_trigger_back
    SK_BMP gl_trigger, SKF_FRONT, 0, 0, gl_trigger_front
    ; --- gl_rsight  (rear sight)
    SK_FILL gl_rsight, SKM_RIGHT | SKM_LEFT | SKM_FRONT, AC_IRON_3, 0
    SK_FILL gl_rsight, SKM_TOP | SKM_BACK, AC_IRON_4, 0
    SK_FILL gl_rsight, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gl_rsight, SKF_TOP, 1, 0, gl_rsight_top
    SK_BMP gl_rsight, SKF_BACK, 0, 0, gl_rsight_back
    ; --- gl_fsight  (front sight with a white dot)
    SK_FILL gl_fsight, SKM_RIGHT | SKM_LEFT | SKM_FRONT, AC_IRON_3, 0
    SK_FILL gl_fsight, SKM_BACK, GUN_WHITE, 0
    SK_FILL gl_fsight, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gl_fsight, SKM_TOP, AC_IRON_4, 0
    SK_BMP gl_fsight, SKF_TOP, 1, 0, gl_fsight_top
SKMODEL_END

; ===================================================================================================
; m_gun_warhead
; ===================================================================================================
; The rocket that sticks out of the loaded launcher (drawn only while a rocket is in the tube): a red warhead body with a
; brass band, a tapered nose and an iron fuse tip. Origin and orientation of the launcher; z -44..-35 in front of the
; tube collar, centred on the tube axis (y 3).
section .rodata
; The characters of every gw_ bitmap:
;  B brass highlight, I iron glint, R red highlight, c brass shade, i iron highlight, j iron, p red shade, r red
align 8
gw_pal:
    PALC 'B', AC_GOLD_2
    PALC 'I', AC_IRON_1
    PALC 'R', GUN_RED_1
    PALC 'c', AC_GOLD_4
    PALC 'i', AC_IRON_2
    PALC 'j', AC_IRON_3
    PALC 'p', GUN_RED_3
    PALC 'r', GUN_RED_2
    dq 0

    ; gw_body_right (4x5 at 0,1 of the 4x6 RIGHT face)
    SKROWS gw_body_right_rows, 4, 5
    SKROW "RRRR"
    SKROW "..R."
    SKROW "...."
    SKROW "...."
    SKROW "pppp"
    SKROWS_END
    align 8
    SKBMP gw_body_right, gw_body_right_rows, 4, 5, gw_pal
    ; gw_body_left (4x5 at 0,1 of the 4x6 LEFT face)
    SKROWS gw_body_left_rows, 4, 5
    SKROW "RRRR"
    SKROW ".R.."
    SKROW "...."
    SKROW "...."
    SKROW "pppp"
    SKROWS_END
    align 8
    SKBMP gw_body_left, gw_body_left_rows, 4, 5, gw_pal
    ; gw_body_top (6x4 at 0,0 of the 6x4 TOP face)
    SKROWS gw_body_top_rows, 6, 4
    SKROW "p....R"
    SKROW "p....R"
    SKROW "p....R"
    SKROW "p....R"
    SKROWS_END
    align 8
    SKBMP gw_body_top, gw_body_top_rows, 6, 4, gw_pal
    ; gw_band_right (1x6 at 0,0 of the 1x6 RIGHT face)
    SKROWS gw_band_right_rows, 1, 6
    SKROW "B"
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "c"
    SKROWS_END
    align 8
    SKBMP gw_band_right, gw_band_right_rows, 1, 6, gw_pal
    ; gw_band_left (1x6 at 0,0 of the 1x6 LEFT face)
    SKROWS gw_band_left_rows, 1, 6
    SKROW "B"
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "c"
    SKROWS_END
    align 8
    SKBMP gw_band_left, gw_band_left_rows, 1, 6, gw_pal
    ; gw_band_top (6x1 at 0,0 of the 6x1 TOP face)
    SKROWS gw_band_top_rows, 6, 1
    SKROW "c....B"
    SKROWS_END
    align 8
    SKBMP gw_band_top, gw_band_top_rows, 6, 1, gw_pal
    ; gw_band_back (6x6 at 0,0 of the 6x6 BACK face)
    SKROWS gw_band_back_rows, 6, 6
    SKROW "BBBBBB"
    SKROW "B....c"
    SKROW "B....c"
    SKROW "B....c"
    SKROW "B....c"
    SKROW "cccccc"
    SKROWS_END
    align 8
    SKBMP gw_band_back, gw_band_back_rows, 6, 6, gw_pal
    ; gw_band_front (6x6 at 0,0 of the 6x6 FRONT face)
    SKROWS gw_band_front_rows, 6, 6
    SKROW "BBBBBB"
    SKROW "c....B"
    SKROW "c....B"
    SKROW "c....B"
    SKROW "c....B"
    SKROW "cccccc"
    SKROWS_END
    align 8
    SKBMP gw_band_front, gw_band_front_rows, 6, 6, gw_pal
    ; gw_taper_right (3x2 at 0,2 of the 3x4 RIGHT face)
    SKROWS gw_taper_right_rows, 3, 2
    SKROW "r.r"
    SKROW "ppp"
    SKROWS_END
    align 8
    SKBMP gw_taper_right, gw_taper_right_rows, 3, 2, gw_pal
    ; gw_taper_left (3x2 at 0,2 of the 3x4 LEFT face)
    SKROWS gw_taper_left_rows, 3, 2
    SKROW "r.r"
    SKROW "ppp"
    SKROWS_END
    align 8
    SKBMP gw_taper_left, gw_taper_left_rows, 3, 2, gw_pal
    ; gw_taper_top (4x3 at 0,0 of the 4x3 TOP face)
    SKROWS gw_taper_top_rows, 4, 3
    SKROW "p..R"
    SKROW "p..R"
    SKROW "p..R"
    SKROWS_END
    align 8
    SKBMP gw_taper_top, gw_taper_top_rows, 4, 3, gw_pal
    ; gw_taper_back (4x3 at 0,1 of the 4x4 BACK face)
    SKROWS gw_taper_back_rows, 4, 3
    SKROW ".rrp"
    SKROW ".rrp"
    SKROW "pppp"
    SKROWS_END
    align 8
    SKBMP gw_taper_back, gw_taper_back_rows, 4, 3, gw_pal
    ; gw_taper_front (3x3 at 0,0 of the 4x4 FRONT face)
    SKROWS gw_taper_front_rows, 3, 3
    SKROW "RRR"
    SKROW "Rrr"
    SKROW "Rrr"
    SKROWS_END
    align 8
    SKBMP gw_taper_front, gw_taper_front_rows, 3, 3, gw_pal
    ; gw_tip_right (2x1 at 0,0 of the 2x2 RIGHT face)
    SKROWS gw_tip_right_rows, 2, 1
    SKROW "ii"
    SKROWS_END
    align 8
    SKBMP gw_tip_right, gw_tip_right_rows, 2, 1, gw_pal
    ; gw_tip_left (2x1 at 0,0 of the 2x2 LEFT face)
    SKROWS gw_tip_left_rows, 2, 1
    SKROW "ii"
    SKROWS_END
    align 8
    SKBMP gw_tip_left, gw_tip_left_rows, 2, 1, gw_pal
    ; gw_tip_top (1x2 at 1,0 of the 2x2 TOP face)
    SKROWS gw_tip_top_rows, 1, 2
    SKROW "i"
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gw_tip_top, gw_tip_top_rows, 1, 2, gw_pal
    ; gw_tip_back (2x1 at 0,0 of the 2x2 BACK face)
    SKROWS gw_tip_back_rows, 2, 1
    SKROW "ii"
    SKROWS_END
    align 8
    SKBMP gw_tip_back, gw_tip_back_rows, 2, 1, gw_pal
    ; gw_tip_front (2x2 at 0,0 of the 2x2 FRONT face)
    SKROWS gw_tip_front_rows, 2, 2
    SKROW "I."
    SKROW ".j"
    SKROWS_END
    align 8
    SKBMP gw_tip_front, gw_tip_front_rows, 2, 2, gw_pal

section .data
SKMODEL_BEGIN m_gun_warhead, 64, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART gw_body, -3, 0, -39, 6, 6, 4, 0, 0                       ; red warhead body
    PART gw_band, -3, 0, -37, 6, 6, 1, 3, 0                       ; brass warning band
    PART gw_taper, -2, 1, -42, 4, 4, 3, 0, 0                      ; nose taper
    PART gw_tip, -1, 2, -44, 2, 2, 2, 0, 0                        ; iron fuse tip
SKMODEL_PAINT
    ; --- gw_body  (red warhead body)
    SK_FILL gw_body, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_FRONT, GUN_RED_2, 0
    SK_FILL gw_body, SKM_BACK, GUN_RED_3, 0
    SK_FILL gw_body, SKM_BOTTOM, GUN_RED_4, 0
    SK_BMP gw_body, SKF_RIGHT, 0, 1, gw_body_right
    SK_BMP gw_body, SKF_LEFT, 0, 1, gw_body_left
    SK_BMP gw_body, SKF_TOP, 0, 0, gw_body_top
    ; --- gw_band  (brass warning band)
    SK_FILL gw_band, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, AC_GOLD_3, 0
    SK_FILL gw_band, SKM_BOTTOM, GUN_BRASS_DEEP, 0
    SK_BMP gw_band, SKF_RIGHT, 0, 0, gw_band_right
    SK_BMP gw_band, SKF_LEFT, 0, 0, gw_band_left
    SK_BMP gw_band, SKF_TOP, 0, 0, gw_band_top
    SK_BMP gw_band, SKF_BACK, 0, 0, gw_band_back
    SK_BMP gw_band, SKF_FRONT, 0, 0, gw_band_front
    ; --- gw_taper  (nose taper)
    SK_FILL gw_taper, SKM_FRONT, GUN_RED_3, 0
    SK_FILL gw_taper, SKM_RIGHT | SKM_LEFT | SKM_BACK, GUN_RED_1, 0
    SK_FILL gw_taper, SKM_BOTTOM, GUN_RED_4, 0
    SK_FILL gw_taper, SKM_TOP, GUN_RED_2, 0
    SK_BMP gw_taper, SKF_RIGHT, 0, 2, gw_taper_right
    SK_BMP gw_taper, SKF_LEFT, 0, 2, gw_taper_left
    SK_BMP gw_taper, SKF_TOP, 0, 0, gw_taper_top
    SK_BMP gw_taper, SKF_BACK, 0, 1, gw_taper_back
    SK_BMP gw_taper, SKF_FRONT, 0, 0, gw_taper_front
    ; --- gw_tip  (iron fuse tip)
    SK_FILL gw_tip, SKM_FRONT, AC_IRON_2, 0
    SK_FILL gw_tip, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK, AC_IRON_4, 0
    SK_FILL gw_tip, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gw_tip, SKF_RIGHT, 0, 0, gw_tip_right
    SK_BMP gw_tip, SKF_LEFT, 0, 0, gw_tip_left
    SK_BMP gw_tip, SKF_TOP, 1, 0, gw_tip_top
    SK_BMP gw_tip, SKF_BACK, 0, 0, gw_tip_back
    SK_BMP gw_tip, SKF_FRONT, 0, 0, gw_tip_front
SKMODEL_END

; ===================================================================================================
; m_gun_revolver
; ===================================================================================================
; The revolver: a blued barrel with a front sight, an ejector rod under it with a brass tip, a fluted dark cylinder with
; chamber holes, an engraved steel frame with a loading gate, a hammer, a raked walnut grip with a brass medallion and a
; brass butt cap, a trigger guard and a trigger.
; Model space (texels, 64 per block, muzzle -Z): the old boxes x 64 give the extents (barrel 3.8 x 3.2 x 11.5, cylinder
; 5.8 x 5.1 x 7.7, grip 3.8 x 10.9 x 3.8, muzzle at (0, 2.2, -19.8)); this model stays within 2 texels of them
; (x -3..3, y -11..6, z -20..5).
section .rodata
; The characters of every gv_ bitmap:
;  A walnut highlight, B brass highlight, C brass deep, D dark steel highlight, E dark steel deep, J iron shade
;  K steel deep, N walnut deep, S steel edge highlight, a walnut, b brass, c brass shade, d dark steel
;  e dark steel shade, g steel glint, i iron highlight, j iron, k steel shade, n walnut shade, s blued steel
;  x bore, pure dark
align 8
gv_pal:
    PALC 'A', GUN_WALNUT_1
    PALC 'B', AC_GOLD_2
    PALC 'C', GUN_BRASS_DEEP
    PALC 'D', GUN_DARK_1
    PALC 'E', GUN_DARK_4
    PALC 'J', AC_IRON_4
    PALC 'K', GUN_STEEL_4
    PALC 'N', GUN_WALNUT_4
    PALC 'S', GUN_STEEL_1
    PALC 'a', GUN_WALNUT_2
    PALC 'b', AC_GOLD_3
    PALC 'c', AC_GOLD_4
    PALC 'd', GUN_DARK_2
    PALC 'e', GUN_DARK_3
    PALC 'g', GUN_STEEL_0
    PALC 'i', AC_IRON_2
    PALC 'j', AC_IRON_3
    PALC 'k', GUN_STEEL_3
    PALC 'n', GUN_WALNUT_3
    PALC 's', GUN_STEEL_2
    PALC 'x', GUN_BORE
    dq 0

    ; gv_barrel_right (12x3 at 0,0 of the 12x3 RIGHT face)
    SKROWS gv_barrel_right_rows, 12, 3
    SKROW "SSSgSSSSKggg"
    SKROW "ssssssssKsss"
    SKROW "........K..."
    SKROWS_END
    align 8
    SKBMP gv_barrel_right, gv_barrel_right_rows, 12, 3, gv_pal
    ; gv_barrel_left (12x3 at 0,0 of the 12x3 LEFT face)
    SKROWS gv_barrel_left_rows, 12, 3
    SKROW "gggKSSSSgSSS"
    SKROW "sssKssssssss"
    SKROW "...K........"
    SKROWS_END
    align 8
    SKBMP gv_barrel_left, gv_barrel_left_rows, 12, 3, gv_pal
    ; gv_barrel_top (4x9 at 0,0 of the 4x12 TOP face)
    SKROWS gv_barrel_top_rows, 4, 9
    SKROW "kkkk"
    SKROW "ks.s"
    SKROW "ks.s"
    SKROW "ks.s"
    SKROW "ks.s"
    SKROW "ks.s"
    SKROW "ks.s"
    SKROW "ks.s"
    SKROW "KKKK"
    SKROWS_END
    align 8
    SKBMP gv_barrel_top, gv_barrel_top_rows, 4, 9, gv_pal
    ; gv_barrel_back (4x2 at 0,1 of the 4x3 BACK face)
    SKROWS gv_barrel_back_rows, 4, 2
    SKROW ".ssk"
    SKROW "kkkk"
    SKROWS_END
    align 8
    SKBMP gv_barrel_back, gv_barrel_back_rows, 4, 2, gv_pal
    ; gv_barrel_front (4x2 at 0,1 of the 4x3 FRONT face)
    SKROWS gv_barrel_front_rows, 4, 2
    SKROW ".xxk"
    SKROW "kkkk"
    SKROWS_END
    align 8
    SKBMP gv_barrel_front, gv_barrel_front_rows, 4, 2, gv_pal
    ; gv_housing_right (10x1 at 0,1 of the 10x2 RIGHT face)
    SKROWS gv_housing_right_rows, 10, 1
    SKROW "eeeeeeeeee"
    SKROWS_END
    align 8
    SKBMP gv_housing_right, gv_housing_right_rows, 10, 1, gv_pal
    ; gv_housing_left (10x1 at 0,1 of the 10x2 LEFT face)
    SKROWS gv_housing_left_rows, 10, 1
    SKROW "eeeeeeeeee"
    SKROWS_END
    align 8
    SKBMP gv_housing_left, gv_housing_left_rows, 10, 1, gv_pal
    ; gv_housing_back (2x1 at 0,1 of the 2x2 BACK face)
    SKROWS gv_housing_back_rows, 2, 1
    SKROW "ee"
    SKROWS_END
    align 8
    SKBMP gv_housing_back, gv_housing_back_rows, 2, 1, gv_pal
    ; gv_rodtip_right (1x1 at 0,1 of the 1x2 RIGHT face)
    SKROWS gv_rodtip_right_rows, 1, 1
    SKROW "c"
    SKROWS_END
    align 8
    SKBMP gv_rodtip_right, gv_rodtip_right_rows, 1, 1, gv_pal
    ; gv_rodtip_left (1x1 at 0,1 of the 1x2 LEFT face)
    SKROWS gv_rodtip_left_rows, 1, 1
    SKROW "c"
    SKROWS_END
    align 8
    SKBMP gv_rodtip_left, gv_rodtip_left_rows, 1, 1, gv_pal
    ; gv_rodtip_top (1x1 at 0,0 of the 2x1 TOP face)
    SKROWS gv_rodtip_top_rows, 1, 1
    SKROW "c"
    SKROWS_END
    align 8
    SKBMP gv_rodtip_top, gv_rodtip_top_rows, 1, 1, gv_pal
    ; gv_rodtip_back (2x1 at 0,1 of the 2x2 BACK face)
    SKROWS gv_rodtip_back_rows, 2, 1
    SKROW "cc"
    SKROWS_END
    align 8
    SKBMP gv_rodtip_back, gv_rodtip_back_rows, 2, 1, gv_pal
    ; gv_rodtip_front (2x1 at 0,1 of the 2x2 FRONT face)
    SKROWS gv_rodtip_front_rows, 2, 1
    SKROW "bb"
    SKROWS_END
    align 8
    SKBMP gv_rodtip_front, gv_rodtip_front_rows, 2, 1, gv_pal
    ; gv_cylinder_right (8x4 at 0,1 of the 8x5 RIGHT face)
    SKROWS gv_cylinder_right_rows, 8, 4
    SKROW "dE.dE.dE"
    SKROW "dE.dE.dE"
    SKROW "dEedE.dE"
    SKROW "eeeeeeee"
    SKROWS_END
    align 8
    SKBMP gv_cylinder_right, gv_cylinder_right_rows, 8, 4, gv_pal
    ; gv_cylinder_left (8x4 at 0,1 of the 8x5 LEFT face)
    SKROWS gv_cylinder_left_rows, 8, 4
    SKROW "E.dE.dE."
    SKROW "E.dE.dE."
    SKROW "E.dE.eE."
    SKROW "eeeeeeee"
    SKROWS_END
    align 8
    SKBMP gv_cylinder_left, gv_cylinder_left_rows, 8, 4, gv_pal
    ; gv_cylinder_top (5x8 at 1,0 of the 6x8 TOP face)
    SKROWS gv_cylinder_top_rows, 5, 8
    SKROW "ddddD"
    SKROW "....D"
    SKROW "ddddD"
    SKROW "....D"
    SKROW "ddddD"
    SKROW "....D"
    SKROW "ddddD"
    SKROW "....D"
    SKROWS_END
    align 8
    SKBMP gv_cylinder_top, gv_cylinder_top_rows, 5, 8, gv_pal
    ; gv_cylinder_back (4x3 at 1,1 of the 6x5 BACK face)
    SKROWS gv_cylinder_back_rows, 4, 3
    SKROW "eeee"
    SKROW "exxe"
    SKROW "eeee"
    SKROWS_END
    align 8
    SKBMP gv_cylinder_back, gv_cylinder_back_rows, 4, 3, gv_pal
    ; gv_cylinder_front (5x4 at 0,0 of the 6x5 FRONT face)
    SKROWS gv_cylinder_front_rows, 5, 4
    SKROW "DDDDD"
    SKROW "Dxddx"
    SKROW "DdBbd"
    SKROW "Dxddx"
    SKROWS_END
    align 8
    SKBMP gv_cylinder_front, gv_cylinder_front_rows, 5, 4, gv_pal
    ; gv_frame_right (4x5 at 0,0 of the 4x6 RIGHT face)
    SKROWS gv_frame_right_rows, 4, 5
    SKROW "SSSS"
    SKROW "sSSs"
    SKROW "K..s"
    SKROW "s..s"
    SKROW "sKss"
    SKROWS_END
    align 8
    SKBMP gv_frame_right, gv_frame_right_rows, 4, 5, gv_pal
    ; gv_frame_left (4x6 at 0,0 of the 4x6 LEFT face)
    SKROWS gv_frame_left_rows, 4, 6
    SKROW "SSSS"
    SKROW ".SS."
    SKROW "...."
    SKROW ".K.."
    SKROW ".S.."
    SKROW "kkkk"
    SKROWS_END
    align 8
    SKBMP gv_frame_left, gv_frame_left_rows, 4, 6, gv_pal
    ; gv_frame_top (3x3 at 1,0 of the 4x4 TOP face)
    SKROWS gv_frame_top_rows, 3, 3
    SKROW "SsS"
    SKROW "SsS"
    SKROW "SsS"
    SKROWS_END
    align 8
    SKBMP gv_frame_top, gv_frame_top_rows, 3, 3, gv_pal
    ; gv_frame_back (3x5 at 1,1 of the 4x6 BACK face)
    SKROWS gv_frame_back_rows, 3, 5
    SKROW "KKk"
    SKROW "KKk"
    SKROW "ssk"
    SKROW "ssk"
    SKROW "ssk"
    SKROWS_END
    align 8
    SKBMP gv_frame_back, gv_frame_back_rows, 3, 5, gv_pal
    ; gv_frame_front (4x5 at 0,1 of the 4x6 FRONT face)
    SKROWS gv_frame_front_rows, 4, 5
    SKROW "kss."
    SKROW "kss."
    SKROW "kss."
    SKROW "kss."
    SKROW "kkkk"
    SKROWS_END
    align 8
    SKBMP gv_frame_front, gv_frame_front_rows, 4, 5, gv_pal
    ; gv_gate_right (3x2 at 0,1 of the 3x3 RIGHT face)
    SKROWS gv_gate_right_rows, 3, 2
    SKROW "bsK"
    SKROW "kkk"
    SKROWS_END
    align 8
    SKBMP gv_gate_right, gv_gate_right_rows, 3, 2, gv_pal
    ; gv_gate_left (3x2 at 0,1 of the 3x3 LEFT face)
    SKROWS gv_gate_left_rows, 3, 2
    SKROW "sss"
    SKROW "kkk"
    SKROWS_END
    align 8
    SKBMP gv_gate_left, gv_gate_left_rows, 3, 2, gv_pal
    ; gv_gate_back (1x2 at 0,1 of the 1x3 BACK face)
    SKROWS gv_gate_back_rows, 1, 2
    SKROW "s"
    SKROW "k"
    SKROWS_END
    align 8
    SKBMP gv_gate_back, gv_gate_back_rows, 1, 2, gv_pal
    ; gv_gate_front (1x2 at 0,1 of the 1x3 FRONT face)
    SKROWS gv_gate_front_rows, 1, 2
    SKROW "s"
    SKROW "k"
    SKROWS_END
    align 8
    SKBMP gv_gate_front, gv_gate_front_rows, 1, 2, gv_pal
    ; gv_hammer_right (3x1 at 0,1 of the 3x2 RIGHT face)
    SKROWS gv_hammer_right_rows, 3, 1
    SKROW "kkk"
    SKROWS_END
    align 8
    SKBMP gv_hammer_right, gv_hammer_right_rows, 3, 1, gv_pal
    ; gv_hammer_left (3x1 at 0,1 of the 3x2 LEFT face)
    SKROWS gv_hammer_left_rows, 3, 1
    SKROW "kkk"
    SKROWS_END
    align 8
    SKBMP gv_hammer_left, gv_hammer_left_rows, 3, 1, gv_pal
    ; gv_hammer_top (2x3 at 0,0 of the 2x3 TOP face)
    SKROWS gv_hammer_top_rows, 2, 3
    SKROW "s."
    SKROW ".s"
    SKROW "s."
    SKROWS_END
    align 8
    SKBMP gv_hammer_top, gv_hammer_top_rows, 2, 3, gv_pal
    ; gv_hammer_back (2x2 at 0,0 of the 2x2 BACK face)
    SKROWS gv_hammer_back_rows, 2, 2
    SKROW "s."
    SKROW ".s"
    SKROWS_END
    align 8
    SKBMP gv_hammer_back, gv_hammer_back_rows, 2, 2, gv_pal
    ; gv_hammer_front (2x1 at 0,1 of the 2x2 FRONT face)
    SKROWS gv_hammer_front_rows, 2, 1
    SKROW "kk"
    SKROWS_END
    align 8
    SKBMP gv_hammer_front, gv_hammer_front_rows, 2, 1, gv_pal
    ; gv_grip_a_right (4x3 at 0,1 of the 4x4 RIGHT face)
    SKROWS gv_grip_a_right_rows, 4, 3
    SKROW ".Bba"
    SKROW ".bca"
    SKROW "nnnn"
    SKROWS_END
    align 8
    SKBMP gv_grip_a_right, gv_grip_a_right_rows, 4, 3, gv_pal
    ; gv_grip_a_left (4x3 at 0,1 of the 4x4 LEFT face)
    SKROWS gv_grip_a_left_rows, 4, 3
    SKROW ".Bba"
    SKROW ".bca"
    SKROW "nnnn"
    SKROWS_END
    align 8
    SKBMP gv_grip_a_left, gv_grip_a_left_rows, 4, 3, gv_pal
    ; gv_grip_a_top (4x4 at 0,0 of the 4x4 TOP face)
    SKROWS gv_grip_a_top_rows, 4, 4
    SKROW "n..A"
    SKROW "n..A"
    SKROW "n..A"
    SKROW "n..A"
    SKROWS_END
    align 8
    SKBMP gv_grip_a_top, gv_grip_a_top_rows, 4, 4, gv_pal
    ; gv_grip_a_back (2x2 at 1,1 of the 4x4 BACK face)
    SKROWS gv_grip_a_back_rows, 2, 2
    SKROW "Aa"
    SKROW "aa"
    SKROWS_END
    align 8
    SKBMP gv_grip_a_back, gv_grip_a_back_rows, 2, 2, gv_pal
    ; gv_grip_a_front (2x2 at 1,1 of the 4x4 FRONT face)
    SKROWS gv_grip_a_front_rows, 2, 2
    SKROW "Aa"
    SKROW "aa"
    SKROWS_END
    align 8
    SKBMP gv_grip_a_front, gv_grip_a_front_rows, 2, 2, gv_pal
    ; gv_grip_b_right (4x3 at 0,1 of the 4x4 RIGHT face)
    SKROWS gv_grip_b_right_rows, 4, 3
    SKROW ".naa"
    SKROW ".naa"
    SKROW "nnnn"
    SKROWS_END
    align 8
    SKBMP gv_grip_b_right, gv_grip_b_right_rows, 4, 3, gv_pal
    ; gv_grip_b_left (4x3 at 0,1 of the 4x4 LEFT face)
    SKROWS gv_grip_b_left_rows, 4, 3
    SKROW ".aaa"
    SKROW ".nna"
    SKROW "nnnn"
    SKROWS_END
    align 8
    SKBMP gv_grip_b_left, gv_grip_b_left_rows, 4, 3, gv_pal
    ; gv_grip_b_top (4x4 at 0,0 of the 4x4 TOP face)
    SKROWS gv_grip_b_top_rows, 4, 4
    SKROW "n..A"
    SKROW "n..A"
    SKROW "n..A"
    SKROW "n.AA"
    SKROWS_END
    align 8
    SKBMP gv_grip_b_top, gv_grip_b_top_rows, 4, 4, gv_pal
    ; gv_grip_b_bottom (1x3 at 0,1 of the 4x4 BOTTOM face)
    SKROWS gv_grip_b_bottom_rows, 1, 3
    SKROW "N"
    SKROW "N"
    SKROW "N"
    SKROWS_END
    align 8
    SKBMP gv_grip_b_bottom, gv_grip_b_bottom_rows, 1, 3, gv_pal
    ; gv_grip_b_back (2x2 at 1,1 of the 4x4 BACK face)
    SKROWS gv_grip_b_back_rows, 2, 2
    SKROW "Aa"
    SKROW "aa"
    SKROWS_END
    align 8
    SKBMP gv_grip_b_back, gv_grip_b_back_rows, 2, 2, gv_pal
    ; gv_grip_b_front (2x2 at 1,1 of the 4x4 FRONT face)
    SKROWS gv_grip_b_front_rows, 2, 2
    SKROW "Aa"
    SKROW "aa"
    SKROWS_END
    align 8
    SKBMP gv_grip_b_front, gv_grip_b_front_rows, 2, 2, gv_pal
    ; gv_cap_top (4x4 at 0,0 of the 4x4 TOP face)
    SKROWS gv_cap_top_rows, 4, 4
    SKROW "c..B"
    SKROW "c..B"
    SKROW "c..B"
    SKROW "c..B"
    SKROWS_END
    align 8
    SKBMP gv_cap_top, gv_cap_top_rows, 4, 4, gv_pal
    ; gv_cap_bottom (4x3 at 0,0 of the 4x4 BOTTOM face)
    SKROWS gv_cap_bottom_rows, 4, 3
    SKROW "bbbb"
    SKROW ".xC."
    SKROW ".CC."
    SKROWS_END
    align 8
    SKBMP gv_cap_bottom, gv_cap_bottom_rows, 4, 3, gv_pal
    ; gv_guard_f_right (1x4 at 0,0 of the 1x4 RIGHT face)
    SKROWS gv_guard_f_right_rows, 1, 4
    SKROW "i"
    SKROW "."
    SKROW "."
    SKROW "J"
    SKROWS_END
    align 8
    SKBMP gv_guard_f_right, gv_guard_f_right_rows, 1, 4, gv_pal
    ; gv_guard_f_left (1x4 at 0,0 of the 1x4 LEFT face)
    SKROWS gv_guard_f_left_rows, 1, 4
    SKROW "i"
    SKROW "."
    SKROW "."
    SKROW "J"
    SKROWS_END
    align 8
    SKBMP gv_guard_f_left, gv_guard_f_left_rows, 1, 4, gv_pal
    ; gv_guard_f_top (1x1 at 1,0 of the 2x1 TOP face)
    SKROWS gv_guard_f_top_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gv_guard_f_top, gv_guard_f_top_rows, 1, 1, gv_pal
    ; gv_guard_f_back (2x4 at 0,0 of the 2x4 BACK face)
    SKROWS gv_guard_f_back_rows, 2, 4
    SKROW "ii"
    SKROW ".."
    SKROW ".."
    SKROW "JJ"
    SKROWS_END
    align 8
    SKBMP gv_guard_f_back, gv_guard_f_back_rows, 2, 4, gv_pal
    ; gv_guard_f_front (2x4 at 0,0 of the 2x4 FRONT face)
    SKROWS gv_guard_f_front_rows, 2, 4
    SKROW "ii"
    SKROW ".."
    SKROW ".."
    SKROW "JJ"
    SKROWS_END
    align 8
    SKBMP gv_guard_f_front, gv_guard_f_front_rows, 2, 4, gv_pal
    ; gv_guard_b_top (1x6 at 0,0 of the 2x6 TOP face)
    SKROWS gv_guard_b_top_rows, 1, 6
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROWS_END
    align 8
    SKBMP gv_guard_b_top, gv_guard_b_top_rows, 1, 6, gv_pal
    ; gv_trigger_right (1x2 at 0,0 of the 1x3 RIGHT face)
    SKROWS gv_trigger_right_rows, 1, 2
    SKROW "i"
    SKROW "j"
    SKROWS_END
    align 8
    SKBMP gv_trigger_right, gv_trigger_right_rows, 1, 2, gv_pal
    ; gv_trigger_left (1x2 at 0,0 of the 1x3 LEFT face)
    SKROWS gv_trigger_left_rows, 1, 2
    SKROW "i"
    SKROW "j"
    SKROWS_END
    align 8
    SKBMP gv_trigger_left, gv_trigger_left_rows, 1, 2, gv_pal
    ; gv_trigger_top (1x1 at 1,0 of the 2x1 TOP face)
    SKROWS gv_trigger_top_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gv_trigger_top, gv_trigger_top_rows, 1, 1, gv_pal
    ; gv_trigger_back (2x2 at 0,0 of the 2x3 BACK face)
    SKROWS gv_trigger_back_rows, 2, 2
    SKROW "ii"
    SKROW "jj"
    SKROWS_END
    align 8
    SKBMP gv_trigger_back, gv_trigger_back_rows, 2, 2, gv_pal
    ; gv_trigger_front (2x2 at 0,0 of the 2x3 FRONT face)
    SKROWS gv_trigger_front_rows, 2, 2
    SKROW "ii"
    SKROW "jj"
    SKROWS_END
    align 8
    SKBMP gv_trigger_front, gv_trigger_front_rows, 2, 2, gv_pal

section .data
SKMODEL_BEGIN m_gun_revolver, 64, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART gv_barrel, -2, 0, -20, 4, 3, 12, 0, 0                    ; blued barrel
    PART gv_housing, -1, -2, -18, 2, 2, 10, 0, 0                  ; ejector rod housing
    PART gv_rodtip, -1, -2, -19, 2, 2, 1, 0, 0                    ; brass ejector rod tip
    PART gv_fsight, -1, 3, -20, 2, 1, 2, 0, 0                     ; front sight blade
    PART gv_cylinder, -3, -1, -8, 6, 5, 8, 0, 0                   ; fluted cylinder with chamber holes
    PART gv_frame, -2, -2, 0, 4, 6, 4, 0, 0                       ; engraved steel frame with a loading gate
    PART gv_gate, 2, 0, 0, 1, 3, 3, 0, 0                          ; loading gate with a brass hinge pin
    PART gv_hammer, -1, 4, 2, 2, 2, 3, 0, 0                       ; hammer with a knurled spur
    PART gv_grip_a, -2, -6, 0, 4, 4, 4, 0, 0                      ; walnut grip, upper: brass medallion
    PART gv_grip_b, -2, -10, 1, 4, 4, 4, 0, 0                     ; walnut grip, lower
    PART gv_cap, -2, -11, 1, 4, 1, 4, 0, 0                        ; brass butt cap
    PART gv_guard_f, -1, -5, -6, 2, 4, 1, 0, 0                    ; trigger guard, front post
    PART gv_guard_b, -1, -6, -6, 2, 1, 6, 0, 0                    ; trigger guard, bar
    PART gv_trigger, -1, -4, -2, 2, 3, 1, 0, 0                    ; trigger
SKMODEL_PAINT
    ; --- gv_barrel  (blued barrel)
    SK_FILL gv_barrel, SKM_TOP | SKM_BACK | SKM_FRONT, GUN_STEEL_1, 0
    SK_FILL gv_barrel, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gv_barrel, SKM_RIGHT | SKM_LEFT, GUN_STEEL_3, 0
    SK_BMP gv_barrel, SKF_RIGHT, 0, 0, gv_barrel_right
    SK_BMP gv_barrel, SKF_LEFT, 0, 0, gv_barrel_left
    SK_BMP gv_barrel, SKF_TOP, 0, 0, gv_barrel_top
    SK_BMP gv_barrel, SKF_BACK, 0, 1, gv_barrel_back
    SK_BMP gv_barrel, SKF_FRONT, 0, 1, gv_barrel_front
    ; --- gv_housing  (ejector rod housing)
    SK_FILL gv_housing, SKM_BOTTOM | SKM_FRONT, GUN_DARK_4, 0
    SK_FILL gv_housing, SKM_RIGHT | SKM_LEFT | SKM_BACK, GUN_DARK_1, 0
    SK_FILL gv_housing, SKM_TOP, GUN_DARK_2, 0
    SK_BMP gv_housing, SKF_RIGHT, 0, 1, gv_housing_right
    SK_BMP gv_housing, SKF_LEFT, 0, 1, gv_housing_left
    SK_BMP gv_housing, SKF_BACK, 0, 1, gv_housing_back
    ; --- gv_rodtip  (brass ejector rod tip)
    SK_FILL gv_rodtip, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, AC_GOLD_2, 0
    SK_FILL gv_rodtip, SKM_BOTTOM, GUN_BRASS_DEEP, 0
    SK_BMP gv_rodtip, SKF_RIGHT, 0, 1, gv_rodtip_right
    SK_BMP gv_rodtip, SKF_LEFT, 0, 1, gv_rodtip_left
    SK_BMP gv_rodtip, SKF_TOP, 0, 0, gv_rodtip_top
    SK_BMP gv_rodtip, SKF_BACK, 0, 1, gv_rodtip_back
    SK_BMP gv_rodtip, SKF_FRONT, 0, 1, gv_rodtip_front
    ; --- gv_fsight  (front sight blade)
    SK_FILL gv_fsight, SKM_RIGHT | SKM_LEFT | SKM_FRONT, AC_IRON_3, 0
    SK_FILL gv_fsight, SKM_BACK, GUN_WHITE, 0
    SK_FILL gv_fsight, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gv_fsight, SKM_TOP, AC_IRON_2, 0
    ; --- gv_cylinder  (fluted cylinder with chamber holes)
    SK_FILL gv_cylinder, SKM_TOP | SKM_FRONT, GUN_DARK_3, 0
    SK_FILL gv_cylinder, SKM_BOTTOM | SKM_BACK, GUN_DARK_4, 0
    SK_FILL gv_cylinder, SKM_RIGHT | SKM_LEFT, GUN_DARK_1, 0
    SK_BMP gv_cylinder, SKF_RIGHT, 0, 1, gv_cylinder_right
    SK_BMP gv_cylinder, SKF_LEFT, 0, 1, gv_cylinder_left
    SK_BMP gv_cylinder, SKF_TOP, 1, 0, gv_cylinder_top
    SK_BMP gv_cylinder, SKF_BACK, 1, 1, gv_cylinder_back
    SK_BMP gv_cylinder, SKF_FRONT, 0, 0, gv_cylinder_front
    ; --- gv_frame  (engraved steel frame with a loading gate)
    SK_FILL gv_frame, SKM_BACK | SKM_FRONT, GUN_STEEL_1, 0
    SK_FILL gv_frame, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gv_frame, SKM_RIGHT | SKM_TOP, GUN_STEEL_3, 0
    SK_FILL gv_frame, SKM_LEFT, GUN_STEEL_2, 0
    SK_BMP gv_frame, SKF_RIGHT, 0, 0, gv_frame_right
    SK_BMP gv_frame, SKF_LEFT, 0, 0, gv_frame_left
    SK_BMP gv_frame, SKF_TOP, 1, 0, gv_frame_top
    SK_BMP gv_frame, SKF_BACK, 1, 1, gv_frame_back
    SK_BMP gv_frame, SKF_FRONT, 0, 1, gv_frame_front
    ; --- gv_gate  (loading gate with a brass hinge pin)
    SK_FILL gv_gate, SKM_RIGHT | SKM_LEFT | SKM_BACK | SKM_FRONT, GUN_STEEL_1, 0
    SK_FILL gv_gate, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gv_gate, SKM_TOP, GUN_STEEL_2, 0
    SK_BMP gv_gate, SKF_RIGHT, 0, 1, gv_gate_right
    SK_BMP gv_gate, SKF_LEFT, 0, 1, gv_gate_left
    SK_BMP gv_gate, SKF_BACK, 0, 1, gv_gate_back
    SK_BMP gv_gate, SKF_FRONT, 0, 1, gv_gate_front
    ; --- gv_hammer  (hammer with a knurled spur)
    SK_FILL gv_hammer, SKM_RIGHT | SKM_LEFT | SKM_FRONT, GUN_STEEL_1, 0
    SK_FILL gv_hammer, SKM_TOP | SKM_BACK, GUN_STEEL_3, 0
    SK_FILL gv_hammer, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gv_hammer, SKF_RIGHT, 0, 1, gv_hammer_right
    SK_BMP gv_hammer, SKF_LEFT, 0, 1, gv_hammer_left
    SK_BMP gv_hammer, SKF_TOP, 0, 0, gv_hammer_top
    SK_BMP gv_hammer, SKF_BACK, 0, 0, gv_hammer_back
    SK_BMP gv_hammer, SKF_FRONT, 0, 1, gv_hammer_front
    ; --- gv_grip_a  (walnut grip, upper: brass medallion)
    SK_FILL gv_grip_a, SKM_BOTTOM | SKM_BACK | SKM_FRONT, GUN_WALNUT_3, 0
    SK_FILL gv_grip_a, SKM_TOP, GUN_WALNUT_2, 15
    SK_FILL gv_grip_a, SKM_RIGHT | SKM_LEFT, GUN_WALNUT_1, 0
    SK_BMP gv_grip_a, SKF_RIGHT, 0, 1, gv_grip_a_right
    SK_BMP gv_grip_a, SKF_LEFT, 0, 1, gv_grip_a_left
    SK_BMP gv_grip_a, SKF_TOP, 0, 0, gv_grip_a_top
    SK_BMP gv_grip_a, SKF_BACK, 1, 1, gv_grip_a_back
    SK_BMP gv_grip_a, SKF_FRONT, 1, 1, gv_grip_a_front
    SK_GRAD gv_grip_a, SKM_RIGHT | SKM_LEFT, 256, 228
    ; --- gv_grip_b  (walnut grip, lower)
    SK_FILL gv_grip_b, SKM_BOTTOM | SKM_BACK | SKM_FRONT, GUN_WALNUT_3, 0
    SK_FILL gv_grip_b, SKM_TOP, GUN_WALNUT_2, 15
    SK_FILL gv_grip_b, SKM_RIGHT | SKM_LEFT, GUN_WALNUT_1, 0
    SK_BMP gv_grip_b, SKF_RIGHT, 0, 1, gv_grip_b_right
    SK_BMP gv_grip_b, SKF_LEFT, 0, 1, gv_grip_b_left
    SK_BMP gv_grip_b, SKF_TOP, 0, 0, gv_grip_b_top
    SK_BMP gv_grip_b, SKF_BOTTOM, 0, 1, gv_grip_b_bottom
    SK_BMP gv_grip_b, SKF_BACK, 1, 1, gv_grip_b_back
    SK_BMP gv_grip_b, SKF_FRONT, 1, 1, gv_grip_b_front
    SK_GRAD gv_grip_b, SKM_RIGHT | SKM_LEFT, 256, 228
    ; --- gv_cap  (brass butt cap)
    SK_FILL gv_cap, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, AC_GOLD_3, 0
    SK_FILL gv_cap, SKM_BOTTOM, AC_GOLD_4, 0
    SK_BMP gv_cap, SKF_TOP, 0, 0, gv_cap_top
    SK_BMP gv_cap, SKF_BOTTOM, 0, 0, gv_cap_bottom
    ; --- gv_guard_f  (trigger guard, front post)
    SK_FILL gv_guard_f, SKM_RIGHT | SKM_LEFT | SKM_BACK | SKM_FRONT, AC_IRON_3, 0
    SK_FILL gv_guard_f, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gv_guard_f, SKM_TOP, AC_IRON_4, 0
    SK_BMP gv_guard_f, SKF_RIGHT, 0, 0, gv_guard_f_right
    SK_BMP gv_guard_f, SKF_LEFT, 0, 0, gv_guard_f_left
    SK_BMP gv_guard_f, SKF_TOP, 1, 0, gv_guard_f_top
    SK_BMP gv_guard_f, SKF_BACK, 0, 0, gv_guard_f_back
    SK_BMP gv_guard_f, SKF_FRONT, 0, 0, gv_guard_f_front
    ; --- gv_guard_b  (trigger guard, bar)
    SK_FILL gv_guard_b, SKM_RIGHT | SKM_LEFT | SKM_BACK | SKM_FRONT, AC_IRON_3, 0
    SK_FILL gv_guard_b, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gv_guard_b, SKM_TOP, AC_IRON_2, 0
    SK_BMP gv_guard_b, SKF_TOP, 0, 0, gv_guard_b_top
    ; --- gv_trigger  (trigger)
    SK_FILL gv_trigger, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, AC_IRON_4, 0
    SK_FILL gv_trigger, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gv_trigger, SKF_RIGHT, 0, 0, gv_trigger_right
    SK_BMP gv_trigger, SKF_LEFT, 0, 0, gv_trigger_left
    SK_BMP gv_trigger, SKF_TOP, 1, 0, gv_trigger_top
    SK_BMP gv_trigger, SKF_BACK, 0, 0, gv_trigger_back
    SK_BMP gv_trigger, SKF_FRONT, 0, 0, gv_trigger_front
SKMODEL_END

; ===================================================================================================
; m_gun_hrifle
; ===================================================================================================
; The hunting rifle: a long blued barrel with a polished muzzle and a front sight, an oak fore-end with a dark tip and a
; white line spacer, a dark receiver with an ejection port and a bolt (shroud, handle and knob), a scope with glass lenses
; at both ends, a brass turret and two iron mounts, an oak stock stepped down to a ribbed recoil pad, a trigger guard
; with a trigger.
; Model space (texels, 64 per block, muzzle -Z): the old boxes x 64 give the extents (barrel 2 x 2.2 x 45, forestock
; 5.1 x 3.8 x 32, receiver 5.1 x 5.8 x 19, scope 2.8 x 2.6 x 19, butt 5.8 x 12.2 x 22, muzzle at (0, 3, -64.6)); this
; model stays within 2 texels of them (x -3..4, y -9..9, z -64..27). The barrel and the fore-end are cut along Z.
section .rodata
; The characters of every gh_ bitmap:
;  B brass highlight, C brass deep, D dark steel highlight, E dark steel deep, G lens highlight, H lens deep
;  K steel deep, S steel edge highlight, V oak deep, W oak highlight, d dark steel, e dark steel shade
;  g steel glint, h lens glass, i iron highlight, j iron, k steel shade, s blued steel, v oak shade, w oak
;  x bore, pure dark, z white paint, stencil
align 8
gh_pal:
    PALC 'B', AC_GOLD_2
    PALC 'C', GUN_BRASS_DEEP
    PALC 'D', GUN_DARK_1
    PALC 'E', GUN_DARK_4
    PALC 'G', GUN_LENS_1
    PALC 'H', GUN_LENS_3
    PALC 'K', GUN_STEEL_4
    PALC 'S', GUN_STEEL_1
    PALC 'V', AC_WOOD_4
    PALC 'W', AC_WOOD_1
    PALC 'd', GUN_DARK_2
    PALC 'e', GUN_DARK_3
    PALC 'g', GUN_STEEL_0
    PALC 'h', GUN_LENS_2
    PALC 'i', AC_IRON_2
    PALC 'j', AC_IRON_3
    PALC 'k', GUN_STEEL_3
    PALC 's', GUN_STEEL_2
    PALC 'v', AC_WOOD_3
    PALC 'w', AC_WOOD_2
    PALC 'x', GUN_BORE
    PALC 'z', GUN_WHITE
    dq 0

    ; gh_barrel_a_right (20x2 at 0,0 of the 23x2 RIGHT face)
    SKROWS gh_barrel_a_right_rows, 20, 2
    SKROW "........g..........K"
    SKROW "kkkkkkkkkkkkkkkkkkkK"
    SKROWS_END
    align 8
    SKBMP gh_barrel_a_right, gh_barrel_a_right_rows, 20, 2, gh_pal
    ; gh_barrel_a_left (20x2 at 3,0 of the 23x2 LEFT face)
    SKROWS gh_barrel_a_left_rows, 20, 2
    SKROW "K..........g........"
    SKROW "Kkkkkkkkkkkkkkkkkkkk"
    SKROWS_END
    align 8
    SKBMP gh_barrel_a_left, gh_barrel_a_left_rows, 20, 2, gh_pal
    ; gh_barrel_a_top (2x20 at 0,0 of the 2x23 TOP face)
    SKROWS gh_barrel_a_top_rows, 2, 20
    SKROW "k."
    SKROW "k."
    SKROW "k."
    SKROW "k."
    SKROW "k."
    SKROW "k."
    SKROW "k."
    SKROW "k."
    SKROW "k."
    SKROW "k."
    SKROW "k."
    SKROW "k."
    SKROW "k."
    SKROW "k."
    SKROW "k."
    SKROW "k."
    SKROW "k."
    SKROW "k."
    SKROW "k."
    SKROW "KK"
    SKROWS_END
    align 8
    SKBMP gh_barrel_a_top, gh_barrel_a_top_rows, 2, 20, gh_pal
    ; gh_barrel_a_front (1x1 at 0,0 of the 2x2 FRONT face)
    SKROWS gh_barrel_a_front_rows, 1, 1
    SKROW "K"
    SKROWS_END
    align 8
    SKBMP gh_barrel_a_front, gh_barrel_a_front_rows, 1, 1, gh_pal
    ; gh_barrel_b_right (23x1 at 0,0 of the 23x2 RIGHT face)
    SKROWS gh_barrel_b_right_rows, 23, 1
    SKROW "ssssSSSSSSSgSSSSSSSSSSS"
    SKROWS_END
    align 8
    SKBMP gh_barrel_b_right, gh_barrel_b_right_rows, 23, 1, gh_pal
    ; gh_barrel_b_left (23x1 at 0,0 of the 23x2 LEFT face)
    SKROWS gh_barrel_b_left_rows, 23, 1
    SKROW "SSSSSSSSSSSgSSSSSSSssss"
    SKROWS_END
    align 8
    SKBMP gh_barrel_b_left, gh_barrel_b_left_rows, 23, 1, gh_pal
    ; gh_barrel_b_top (1x19 at 1,4 of the 2x23 TOP face)
    SKROWS gh_barrel_b_top_rows, 1, 19
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROWS_END
    align 8
    SKBMP gh_barrel_b_top, gh_barrel_b_top_rows, 1, 19, gh_pal
    ; gh_barrel_b_back (2x1 at 0,1 of the 2x2 BACK face)
    SKROWS gh_barrel_b_back_rows, 2, 1
    SKROW "kk"
    SKROWS_END
    align 8
    SKBMP gh_barrel_b_back, gh_barrel_b_back_rows, 2, 1, gh_pal
    ; gh_fore_a_right (17x4 at 0,0 of the 17x4 RIGHT face)
    SKROWS gh_fore_a_right_rows, 17, 4
    SKROW "..............zDD"
    SKROW "...........wwwzdd"
    SKROW "wwwwwwwwwwwwwwzdd"
    SKROW "..............zee"
    SKROWS_END
    align 8
    SKBMP gh_fore_a_right, gh_fore_a_right_rows, 17, 4, gh_pal
    ; gh_fore_a_left (17x4 at 0,0 of the 17x4 LEFT face)
    SKROWS gh_fore_a_left_rows, 17, 4
    SKROW "DDz.............."
    SKROW "ddzwwwwwwwwwwwwww"
    SKROW "ddzwwwwwwwwwWWWw."
    SKROW "eez.............."
    SKROWS_END
    align 8
    SKBMP gh_fore_a_left, gh_fore_a_left_rows, 17, 4, gh_pal
    ; gh_fore_a_top (6x17 at 0,0 of the 6x17 TOP face)
    SKROWS gh_fore_a_top_rows, 6, 17
    SKROW "v....W"
    SKROW "v....W"
    SKROW "v....W"
    SKROW "v....W"
    SKROW "v....W"
    SKROW "v....W"
    SKROW "v....W"
    SKROW "v....W"
    SKROW "v....W"
    SKROW "v..v.W"
    SKROW "v..v.W"
    SKROW "v..v.W"
    SKROW "v..v.W"
    SKROW "v..v.W"
    SKROW "zzzzzz"
    SKROW "dddddd"
    SKROW "DDDDDD"
    SKROWS_END
    align 8
    SKBMP gh_fore_a_top, gh_fore_a_top_rows, 6, 17, gh_pal
    ; gh_fore_a_bottom (6x17 at 0,0 of the 6x17 BOTTOM face)
    SKROWS gh_fore_a_bottom_rows, 6, 17
    SKROW "eeeeee"
    SKROW "eeeeee"
    SKROW ".w...."
    SKROW "VwV..."
    SKROW "VwV..."
    SKROW "VwV..."
    SKROW "VwV..."
    SKROW "VwV..."
    SKROW "V.V..."
    SKROW "V.V..."
    SKROW "..V..."
    SKROW "..V..."
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW ".....V"
    SKROW ".....V"
    SKROWS_END
    align 8
    SKBMP gh_fore_a_bottom, gh_fore_a_bottom_rows, 6, 17, gh_pal
    ; gh_fore_a_front (5x3 at 0,0 of the 6x4 FRONT face)
    SKROWS gh_fore_a_front_rows, 5, 3
    SKROW "DDDDD"
    SKROW "Ddddd"
    SKROW "Ddddd"
    SKROWS_END
    align 8
    SKBMP gh_fore_a_front, gh_fore_a_front_rows, 5, 3, gh_pal
    ; gh_fore_b_right (17x2 at 0,1 of the 17x4 RIGHT face)
    SKROWS gh_fore_b_right_rows, 17, 2
    SKROW "wwwwwwwwwwwwwwwww"
    SKROW "wwwwwwwwwwwwwwwww"
    SKROWS_END
    align 8
    SKBMP gh_fore_b_right, gh_fore_b_right_rows, 17, 2, gh_pal
    ; gh_fore_b_left (17x2 at 0,1 of the 17x4 LEFT face)
    SKROWS gh_fore_b_left_rows, 17, 2
    SKROW "wwwwwwwwwwwwwwwww"
    SKROW "...www..........w"
    SKROWS_END
    align 8
    SKBMP gh_fore_b_left, gh_fore_b_left_rows, 17, 2, gh_pal
    ; gh_fore_b_top (6x17 at 0,0 of the 6x17 TOP face)
    SKROWS gh_fore_b_top_rows, 6, 17
    SKROW "v....W"
    SKROW "v....W"
    SKROW "vW...W"
    SKROW "vW...W"
    SKROW "vW...W"
    SKROW "vW...W"
    SKROW "v....W"
    SKROW "v....W"
    SKROW "vW...W"
    SKROW "vW...W"
    SKROW "vW...W"
    SKROW "vW...W"
    SKROW "vW...W"
    SKROW "vW...W"
    SKROW "v....W"
    SKROW "v....W"
    SKROW "v....W"
    SKROWS_END
    align 8
    SKBMP gh_fore_b_top, gh_fore_b_top_rows, 6, 17, gh_pal
    ; gh_fore_b_bottom (6x17 at 0,0 of the 6x17 BOTTOM face)
    SKROWS gh_fore_b_bottom_rows, 6, 17
    SKROW ".....V"
    SKROW ".....V"
    SKROW ".....V"
    SKROW "......"
    SKROW "......"
    SKROW "....V."
    SKROW "....V."
    SKROW "....V."
    SKROW "....V."
    SKROW "....V."
    SKROW "....V."
    SKROW "....V."
    SKROW "V...V."
    SKROW "V...V."
    SKROW "V....."
    SKROW "V....."
    SKROW "V....."
    SKROWS_END
    align 8
    SKBMP gh_fore_b_bottom, gh_fore_b_bottom_rows, 6, 17, gh_pal
    ; gh_fore_b_back (4x2 at 1,1 of the 6x4 BACK face)
    SKROWS gh_fore_b_back_rows, 4, 2
    SKROW "W..w"
    SKROW "w..w"
    SKROWS_END
    align 8
    SKBMP gh_fore_b_back, gh_fore_b_back_rows, 4, 2, gh_pal
    ; gh_receiver_right (19x6 at 0,0 of the 19x6 RIGHT face)
    SKROWS gh_receiver_right_rows, 19, 6
    SKROW "DDDDDDDDDDDDDDDDDDD"
    SKROW "....kEEEEEEEEk....."
    SKROW "....kxxxxxxxxk.DE.."
    SKROW ".....SSSSSSSS......"
    SKROW ".eee..............."
    SKROW "eeeeeeeeeeeeeeeeeee"
    SKROWS_END
    align 8
    SKBMP gh_receiver_right, gh_receiver_right_rows, 19, 6, gh_pal
    ; gh_receiver_left (19x6 at 0,0 of the 19x6 LEFT face)
    SKROWS gh_receiver_left_rows, 19, 6
    SKROW "DDDDDDDDDDDDDDDDDDD"
    SKROW "......EEEEE........"
    SKROW "..eD...........eD.."
    SKROW "......eeeee........"
    SKROW "..................."
    SKROW "eeeeeeeeeeeeeeeeeee"
    SKROWS_END
    align 8
    SKBMP gh_receiver_left, gh_receiver_left_rows, 19, 6, gh_pal
    ; gh_receiver_top (6x19 at 0,0 of the 6x19 TOP face)
    SKROWS gh_receiver_top_rows, 6, 19
    SKROW "e.ee.D"
    SKROW "e.ee.D"
    SKROW "e.EE.D"
    SKROW "e.EE.D"
    SKROW "D.EE.D"
    SKROW "e.EE.D"
    SKROW "e.EE.D"
    SKROW "e.EE.D"
    SKROW "e.EE.D"
    SKROW "e.EE.D"
    SKROW "e.EE.D"
    SKROW "e.EE.D"
    SKROW "e.ee.D"
    SKROW "e.ee.D"
    SKROW "e.ee.D"
    SKROW "D.ee.D"
    SKROW "e.ee.D"
    SKROW "e.ee.D"
    SKROW "e.ee.D"
    SKROWS_END
    align 8
    SKBMP gh_receiver_top, gh_receiver_top_rows, 6, 19, gh_pal
    ; gh_receiver_back (6x4 at 0,0 of the 6x6 BACK face)
    SKROWS gh_receiver_back_rows, 6, 4
    SKROW "DDDDDD"
    SKROW "......"
    SKROW "..EE.."
    SKROW "..EE.."
    SKROWS_END
    align 8
    SKBMP gh_receiver_back, gh_receiver_back_rows, 6, 4, gh_pal
    ; gh_receiver_front (6x1 at 0,0 of the 6x6 FRONT face)
    SKROWS gh_receiver_front_rows, 6, 1
    SKROW "DDDDDD"
    SKROWS_END
    align 8
    SKBMP gh_receiver_front, gh_receiver_front_rows, 6, 1, gh_pal
    ; gh_belly_right (19x2 at 0,1 of the 19x3 RIGHT face)
    SKROWS gh_belly_right_rows, 19, 2
    SKROW "www.....wwwwwwwwvvv"
    SKROW "vvvvvvvvvvvvvvvvvvv"
    SKROWS_END
    align 8
    SKBMP gh_belly_right, gh_belly_right_rows, 19, 2, gh_pal
    ; gh_belly_left (19x2 at 0,0 of the 19x3 LEFT face)
    SKROWS gh_belly_left_rows, 19, 2
    SKROW "WWWWWWWWWWWWWWWWWWW"
    SKROW "w.....wwwwwwwwwwwww"
    SKROWS_END
    align 8
    SKBMP gh_belly_left, gh_belly_left_rows, 19, 2, gh_pal
    ; gh_belly_top (6x19 at 0,0 of the 6x19 TOP face)
    SKROWS gh_belly_top_rows, 6, 19
    SKROW "vv...W"
    SKROW "vv...W"
    SKROW "vv...W"
    SKROW "vv...W"
    SKROW "vv...W"
    SKROW "vv...W"
    SKROW "vv...W"
    SKROW "vv...W"
    SKROW "v....W"
    SKROW "v....W"
    SKROW "v....W"
    SKROW "v....W"
    SKROW "vv...W"
    SKROW "vv...W"
    SKROW "vv..vW"
    SKROW "vv..vW"
    SKROW "vv.WvW"
    SKROW "vv.WvW"
    SKROW "vv.WvW"
    SKROWS_END
    align 8
    SKBMP gh_belly_top, gh_belly_top_rows, 6, 19, gh_pal
    ; gh_belly_bottom (6x19 at 0,0 of the 6x19 BOTTOM face)
    SKROWS gh_belly_bottom_rows, 6, 19
    SKROW ".....V"
    SKROW "w....V"
    SKROW "w...wV"
    SKROW "w...wV"
    SKROW "w...wV"
    SKROW "w...wV"
    SKROW "w....V"
    SKROW "w....V"
    SKROW "w...wV"
    SKROW "w...w."
    SKROW "....w."
    SKROW "....w."
    SKROW "..w..."
    SKROW "w.w..."
    SKROW "w.w..."
    SKROW "w.w..V"
    SKROW "w.w..V"
    SKROW "w.w..V"
    SKROW "w.w..V"
    SKROWS_END
    align 8
    SKBMP gh_belly_bottom, gh_belly_bottom_rows, 6, 19, gh_pal
    ; gh_belly_back (4x1 at 1,1 of the 6x3 BACK face)
    SKROWS gh_belly_back_rows, 4, 1
    SKROW "Wwww"
    SKROWS_END
    align 8
    SKBMP gh_belly_back, gh_belly_back_rows, 4, 1, gh_pal
    ; gh_belly_front (4x1 at 1,1 of the 6x3 FRONT face)
    SKROWS gh_belly_front_rows, 4, 1
    SKROW "Wwww"
    SKROWS_END
    align 8
    SKBMP gh_belly_front, gh_belly_front_rows, 4, 1, gh_pal
    ; gh_shroud_right (2x1 at 0,1 of the 2x2 RIGHT face)
    SKROWS gh_shroud_right_rows, 2, 1
    SKROW "kk"
    SKROWS_END
    align 8
    SKBMP gh_shroud_right, gh_shroud_right_rows, 2, 1, gh_pal
    ; gh_shroud_left (2x1 at 0,1 of the 2x2 LEFT face)
    SKROWS gh_shroud_left_rows, 2, 1
    SKROW "kk"
    SKROWS_END
    align 8
    SKBMP gh_shroud_left, gh_shroud_left_rows, 2, 1, gh_pal
    ; gh_shroud_top (1x2 at 0,0 of the 2x2 TOP face)
    SKROWS gh_shroud_top_rows, 1, 2
    SKROW "k"
    SKROW "k"
    SKROWS_END
    align 8
    SKBMP gh_shroud_top, gh_shroud_top_rows, 1, 2, gh_pal
    ; gh_shroud_back (2x2 at 0,0 of the 2x2 BACK face)
    SKROWS gh_shroud_back_rows, 2, 2
    SKROW ".k"
    SKROW "k."
    SKROWS_END
    align 8
    SKBMP gh_shroud_back, gh_shroud_back_rows, 2, 2, gh_pal
    ; gh_shroud_front (2x1 at 0,1 of the 2x2 FRONT face)
    SKROWS gh_shroud_front_rows, 2, 1
    SKROW "kk"
    SKROWS_END
    align 8
    SKBMP gh_shroud_front, gh_shroud_front_rows, 2, 1, gh_pal
    ; gh_knob_right (1x2 at 0,0 of the 2x2 RIGHT face)
    SKROWS gh_knob_right_rows, 1, 2
    SKROW "g"
    SKROW "S"
    SKROWS_END
    align 8
    SKBMP gh_knob_right, gh_knob_right_rows, 1, 2, gh_pal
    ; gh_knob_left (2x1 at 0,1 of the 2x2 LEFT face)
    SKROWS gh_knob_left_rows, 2, 1
    SKROW "kk"
    SKROWS_END
    align 8
    SKBMP gh_knob_left, gh_knob_left_rows, 2, 1, gh_pal
    ; gh_knob_back (1x1 at 0,1 of the 1x2 BACK face)
    SKROWS gh_knob_back_rows, 1, 1
    SKROW "k"
    SKROWS_END
    align 8
    SKBMP gh_knob_back, gh_knob_back_rows, 1, 1, gh_pal
    ; gh_knob_front (1x1 at 0,1 of the 1x2 FRONT face)
    SKROWS gh_knob_front_rows, 1, 1
    SKROW "k"
    SKROWS_END
    align 8
    SKBMP gh_knob_front, gh_knob_front_rows, 1, 1, gh_pal
    ; gh_scope_right (14x1 at 0,1 of the 14x2 RIGHT face)
    SKROWS gh_scope_right_rows, 14, 1
    SKROW "eeeeeeeeeeeeee"
    SKROWS_END
    align 8
    SKBMP gh_scope_right, gh_scope_right_rows, 14, 1, gh_pal
    ; gh_scope_left (14x1 at 0,1 of the 14x2 LEFT face)
    SKROWS gh_scope_left_rows, 14, 1
    SKROW "eeeeeeeeeeeeee"
    SKROWS_END
    align 8
    SKBMP gh_scope_left, gh_scope_left_rows, 14, 1, gh_pal
    ; gh_scope_top (1x14 at 0,0 of the 2x14 TOP face)
    SKROWS gh_scope_top_rows, 1, 14
    SKROW "d"
    SKROW "d"
    SKROW "d"
    SKROW "d"
    SKROW "d"
    SKROW "d"
    SKROW "d"
    SKROW "d"
    SKROW "d"
    SKROW "d"
    SKROW "d"
    SKROW "d"
    SKROW "d"
    SKROW "d"
    SKROWS_END
    align 8
    SKBMP gh_scope_top, gh_scope_top_rows, 1, 14, gh_pal
    ; gh_scope_back (2x1 at 0,1 of the 2x2 BACK face)
    SKROWS gh_scope_back_rows, 2, 1
    SKROW "ee"
    SKROWS_END
    align 8
    SKBMP gh_scope_back, gh_scope_back_rows, 2, 1, gh_pal
    ; gh_scope_front (2x1 at 0,1 of the 2x2 FRONT face)
    SKROWS gh_scope_front_rows, 2, 1
    SKROW "ee"
    SKROWS_END
    align 8
    SKBMP gh_scope_front, gh_scope_front_rows, 2, 1, gh_pal
    ; gh_bell_right (5x4 at 0,0 of the 5x4 RIGHT face)
    SKROWS gh_bell_right_rows, 5, 4
    SKROW "DEDDD"
    SKROW ".E..."
    SKROW ".E..."
    SKROW "eEeee"
    SKROWS_END
    align 8
    SKBMP gh_bell_right, gh_bell_right_rows, 5, 4, gh_pal
    ; gh_bell_left (5x4 at 0,0 of the 5x4 LEFT face)
    SKROWS gh_bell_left_rows, 5, 4
    SKROW "DDDED"
    SKROW "...E."
    SKROW "...E."
    SKROW "eeeEe"
    SKROWS_END
    align 8
    SKBMP gh_bell_left, gh_bell_left_rows, 5, 4, gh_pal
    ; gh_bell_top (4x5 at 0,0 of the 4x5 TOP face)
    SKROWS gh_bell_top_rows, 4, 5
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROW "EEEE"
    SKROW "e..D"
    SKROWS_END
    align 8
    SKBMP gh_bell_top, gh_bell_top_rows, 4, 5, gh_pal
    ; gh_bell_back (4x3 at 0,1 of the 4x4 BACK face)
    SKROWS gh_bell_back_rows, 4, 3
    SKROW ".dde"
    SKROW ".dde"
    SKROW "eeee"
    SKROWS_END
    align 8
    SKBMP gh_bell_back, gh_bell_back_rows, 4, 3, gh_pal
    ; gh_bell_front (4x3 at 0,0 of the 4x4 FRONT face)
    SKROWS gh_bell_front_rows, 4, 3
    SKROW "DDDD"
    SKROW ".Gh."
    SKROW ".hH."
    SKROWS_END
    align 8
    SKBMP gh_bell_front, gh_bell_front_rows, 4, 3, gh_pal
    ; gh_eyepiece_right (4x4 at 0,0 of the 4x4 RIGHT face)
    SKROWS gh_eyepiece_right_rows, 4, 4
    SKROW "DEDD"
    SKROW ".E.."
    SKROW ".E.."
    SKROW "eEee"
    SKROWS_END
    align 8
    SKBMP gh_eyepiece_right, gh_eyepiece_right_rows, 4, 4, gh_pal
    ; gh_eyepiece_left (4x4 at 0,0 of the 4x4 LEFT face)
    SKROWS gh_eyepiece_left_rows, 4, 4
    SKROW "DDED"
    SKROW "..E."
    SKROW "..E."
    SKROW "eeEe"
    SKROWS_END
    align 8
    SKBMP gh_eyepiece_left, gh_eyepiece_left_rows, 4, 4, gh_pal
    ; gh_eyepiece_top (4x4 at 0,0 of the 4x4 TOP face)
    SKROWS gh_eyepiece_top_rows, 4, 4
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROW "e..D"
    SKROWS_END
    align 8
    SKBMP gh_eyepiece_top, gh_eyepiece_top_rows, 4, 4, gh_pal
    ; gh_eyepiece_back (3x3 at 1,1 of the 4x4 BACK face)
    SKROWS gh_eyepiece_back_rows, 3, 3
    SKROW "HGe"
    SKROW "HHe"
    SKROW "eee"
    SKROWS_END
    align 8
    SKBMP gh_eyepiece_back, gh_eyepiece_back_rows, 3, 3, gh_pal
    ; gh_eyepiece_front (4x3 at 0,1 of the 4x4 FRONT face)
    SKROWS gh_eyepiece_front_rows, 4, 3
    SKROW "edd."
    SKROW "edd."
    SKROW "eeee"
    SKROWS_END
    align 8
    SKBMP gh_eyepiece_front, gh_eyepiece_front_rows, 4, 3, gh_pal
    ; gh_turret_top (2x2 at 0,0 of the 2x2 TOP face)
    SKROWS gh_turret_top_rows, 2, 2
    SKROW "B."
    SKROW ".C"
    SKROWS_END
    align 8
    SKBMP gh_turret_top, gh_turret_top_rows, 2, 2, gh_pal
    ; gh_mount_f_top (1x2 at 1,0 of the 2x2 TOP face)
    SKROWS gh_mount_f_top_rows, 1, 2
    SKROW "i"
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gh_mount_f_top, gh_mount_f_top_rows, 1, 2, gh_pal
    ; gh_wrist_right (6x7 at 0,0 of the 6x7 RIGHT face)
    SKROWS gh_wrist_right_rows, 6, 7
    SKROW "WWWWWW"
    SKROW "......"
    SKROW "......"
    SKROW "..WWWW"
    SKROW "......"
    SKROW "...WWW"
    SKROW "vvvvvv"
    SKROWS_END
    align 8
    SKBMP gh_wrist_right, gh_wrist_right_rows, 6, 7, gh_pal
    ; gh_wrist_left (6x7 at 0,0 of the 6x7 LEFT face)
    SKROWS gh_wrist_left_rows, 6, 7
    SKROW "WWWWWW"
    SKROW "......"
    SKROW "..vvvv"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "vvvvvv"
    SKROWS_END
    align 8
    SKBMP gh_wrist_left, gh_wrist_left_rows, 6, 7, gh_pal
    ; gh_wrist_top (6x6 at 0,0 of the 6x6 TOP face)
    SKROWS gh_wrist_top_rows, 6, 6
    SKROW "v....W"
    SKROW "v...WW"
    SKROW "v...WW"
    SKROW "vv..WW"
    SKROW "vv..WW"
    SKROW "vv..WW"
    SKROWS_END
    align 8
    SKBMP gh_wrist_top, gh_wrist_top_rows, 6, 6, gh_pal
    ; gh_wrist_bottom (1x4 at 0,2 of the 6x6 BOTTOM face)
    SKROWS gh_wrist_bottom_rows, 1, 4
    SKROW "V"
    SKROW "V"
    SKROW "V"
    SKROW "V"
    SKROWS_END
    align 8
    SKBMP gh_wrist_bottom, gh_wrist_bottom_rows, 1, 4, gh_pal
    ; gh_wrist_back (4x5 at 1,1 of the 6x7 BACK face)
    SKROWS gh_wrist_back_rows, 4, 5
    SKROW "Wwww"
    SKROW "w..w"
    SKROW "wwww"
    SKROW "w..w"
    SKROW "wwww"
    SKROWS_END
    align 8
    SKBMP gh_wrist_back, gh_wrist_back_rows, 4, 5, gh_pal
    ; gh_wrist_front (4x5 at 1,1 of the 6x7 FRONT face)
    SKROWS gh_wrist_front_rows, 4, 5
    SKROW "Wwww"
    SKROW "w..w"
    SKROW "wwww"
    SKROW "w..w"
    SKROW "wwww"
    SKROWS_END
    align 8
    SKBMP gh_wrist_front, gh_wrist_front_rows, 4, 5, gh_pal
    ; gh_butt_a_right (7x9 at 0,0 of the 7x9 RIGHT face)
    SKROWS gh_butt_a_right_rows, 7, 9
    SKROW "vvvvvvv"
    SKROW ".vvvvvv"
    SKROW ".....vv"
    SKROW "WWWWWWW"
    SKROW "......."
    SKROW "......."
    SKROW ".WWWWWW"
    SKROW "......."
    SKROW "vvvvvvv"
    SKROWS_END
    align 8
    SKBMP gh_butt_a_right, gh_butt_a_right_rows, 7, 9, gh_pal
    ; gh_butt_a_left (7x9 at 0,0 of the 7x9 LEFT face)
    SKROWS gh_butt_a_left_rows, 7, 9
    SKROW "vvvvvvv"
    SKROW "......."
    SKROW "vvvvvvv"
    SKROW "......."
    SKROW "......."
    SKROW "...vvvv"
    SKROW "WWWWWWW"
    SKROW ".....vv"
    SKROW "vvvvvvv"
    SKROWS_END
    align 8
    SKBMP gh_butt_a_left, gh_butt_a_left_rows, 7, 9, gh_pal
    ; gh_butt_a_top (6x7 at 0,0 of the 6x7 TOP face)
    SKROWS gh_butt_a_top_rows, 6, 7
    SKROW "v....W"
    SKROW "v.W..W"
    SKROW "v.W..W"
    SKROW "v.Wv.W"
    SKROW "v.Wv.W"
    SKROW "v.Wv.W"
    SKROW "v.Wv.W"
    SKROWS_END
    align 8
    SKBMP gh_butt_a_top, gh_butt_a_top_rows, 6, 7, gh_pal
    ; gh_butt_a_bottom (3x7 at 2,0 of the 6x7 BOTTOM face)
    SKROWS gh_butt_a_bottom_rows, 3, 7
    SKROW "V.."
    SKROW "VwV"
    SKROW "VwV"
    SKROW "VwV"
    SKROW "Vw."
    SKROW "V.."
    SKROW "V.."
    SKROWS_END
    align 8
    SKBMP gh_butt_a_bottom, gh_butt_a_bottom_rows, 3, 7, gh_pal
    ; gh_butt_a_back (4x7 at 1,1 of the 6x9 BACK face)
    SKROWS gh_butt_a_back_rows, 4, 7
    SKROW "Wwww"
    SKROW "w..w"
    SKROW "wwww"
    SKROW "wwww"
    SKROW "wwww"
    SKROW "w..w"
    SKROW "wwww"
    SKROWS_END
    align 8
    SKBMP gh_butt_a_back, gh_butt_a_back_rows, 4, 7, gh_pal
    ; gh_butt_a_front (4x7 at 1,1 of the 6x9 FRONT face)
    SKROWS gh_butt_a_front_rows, 4, 7
    SKROW "Wwww"
    SKROW "w..w"
    SKROW "wwww"
    SKROW "wwww"
    SKROW "wwww"
    SKROW "w..w"
    SKROW "wwww"
    SKROWS_END
    align 8
    SKBMP gh_butt_a_front, gh_butt_a_front_rows, 4, 7, gh_pal
    ; gh_butt_b_right (7x11 at 0,0 of the 7x11 RIGHT face)
    SKROWS gh_butt_b_right_rows, 7, 11
    SKROW "WWWWWWW"
    SKROW "......."
    SKROW "......."
    SKROW "......."
    SKROW "......."
    SKROW "......."
    SKROW "......."
    SKROW "......."
    SKROW "...vvvv"
    SKROW "..vvvvv"
    SKROW "vvvvvvv"
    SKROWS_END
    align 8
    SKBMP gh_butt_b_right, gh_butt_b_right_rows, 7, 11, gh_pal
    ; gh_butt_b_left (7x11 at 0,0 of the 7x11 LEFT face)
    SKROWS gh_butt_b_left_rows, 7, 11
    SKROW "WWWWWWW"
    SKROW "......."
    SKROW "......."
    SKROW "......."
    SKROW "......."
    SKROW ".vvvvvv"
    SKROW "......."
    SKROW "......."
    SKROW "...vvvv"
    SKROW ".vvvvv."
    SKROW "vvvvvvv"
    SKROWS_END
    align 8
    SKBMP gh_butt_b_left, gh_butt_b_left_rows, 7, 11, gh_pal
    ; gh_butt_b_top (5x7 at 1,0 of the 6x7 TOP face)
    SKROWS gh_butt_b_top_rows, 5, 7
    SKROW "w.wwW"
    SKROW "w.wwW"
    SKROW "w.w.W"
    SKROW "w.w.W"
    SKROW "w.w.W"
    SKROW "w.w.W"
    SKROW "www.W"
    SKROWS_END
    align 8
    SKBMP gh_butt_b_top, gh_butt_b_top_rows, 5, 7, gh_pal
    ; gh_butt_b_back (4x9 at 1,1 of the 6x11 BACK face)
    SKROWS gh_butt_b_back_rows, 4, 9
    SKROW "Wwww"
    SKROW "w..w"
    SKROW "wwww"
    SKROW "wwww"
    SKROW "wwww"
    SKROW "wwww"
    SKROW "wwww"
    SKROW "w..w"
    SKROW "wwww"
    SKROWS_END
    align 8
    SKBMP gh_butt_b_back, gh_butt_b_back_rows, 4, 9, gh_pal
    ; gh_butt_b_front (4x9 at 1,1 of the 6x11 FRONT face)
    SKROWS gh_butt_b_front_rows, 4, 9
    SKROW "Wwww"
    SKROW "w..w"
    SKROW "wwww"
    SKROW "wwww"
    SKROW "wwww"
    SKROW "wwww"
    SKROW "wwww"
    SKROW "w..w"
    SKROW "wwww"
    SKROWS_END
    align 8
    SKBMP gh_butt_b_front, gh_butt_b_front_rows, 4, 9, gh_pal
    ; gh_pad_right (1x11 at 0,0 of the 1x11 RIGHT face)
    SKROWS gh_pad_right_rows, 1, 11
    SKROW "D"
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "e"
    SKROWS_END
    align 8
    SKBMP gh_pad_right, gh_pad_right_rows, 1, 11, gh_pal
    ; gh_pad_left (1x11 at 0,0 of the 1x11 LEFT face)
    SKROWS gh_pad_left_rows, 1, 11
    SKROW "D"
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "."
    SKROW "e"
    SKROWS_END
    align 8
    SKBMP gh_pad_left, gh_pad_left_rows, 1, 11, gh_pal
    ; gh_pad_top (6x1 at 0,0 of the 6x1 TOP face)
    SKROWS gh_pad_top_rows, 6, 1
    SKROW "e....D"
    SKROWS_END
    align 8
    SKBMP gh_pad_top, gh_pad_top_rows, 6, 1, gh_pal
    ; gh_pad_back (6x11 at 0,0 of the 6x11 BACK face)
    SKROWS gh_pad_back_rows, 6, 11
    SKROW "DDDDDE"
    SKROW "DeeeeE"
    SKROW "D....E"
    SKROW "DeeeeE"
    SKROW "D....E"
    SKROW "DeeeeE"
    SKROW "D....E"
    SKROW "DeeeeE"
    SKROW "D....E"
    SKROW "DeeeeE"
    SKROW "D....E"
    SKROWS_END
    align 8
    SKBMP gh_pad_back, gh_pad_back_rows, 6, 11, gh_pal
    ; gh_pad_front (6x11 at 0,0 of the 6x11 FRONT face)
    SKROWS gh_pad_front_rows, 6, 11
    SKROW "DDDDDD"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "e....D"
    SKROW "eeeeee"
    SKROWS_END
    align 8
    SKBMP gh_pad_front, gh_pad_front_rows, 6, 11, gh_pal
    ; gh_guard_f_right (1x2 at 0,0 of the 1x3 RIGHT face)
    SKROWS gh_guard_f_right_rows, 1, 2
    SKROW "i"
    SKROW "j"
    SKROWS_END
    align 8
    SKBMP gh_guard_f_right, gh_guard_f_right_rows, 1, 2, gh_pal
    ; gh_guard_f_left (1x2 at 0,0 of the 1x3 LEFT face)
    SKROWS gh_guard_f_left_rows, 1, 2
    SKROW "i"
    SKROW "j"
    SKROWS_END
    align 8
    SKBMP gh_guard_f_left, gh_guard_f_left_rows, 1, 2, gh_pal
    ; gh_guard_f_top (1x1 at 1,0 of the 2x1 TOP face)
    SKROWS gh_guard_f_top_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gh_guard_f_top, gh_guard_f_top_rows, 1, 1, gh_pal
    ; gh_guard_f_back (2x2 at 0,0 of the 2x3 BACK face)
    SKROWS gh_guard_f_back_rows, 2, 2
    SKROW "ii"
    SKROW "jj"
    SKROWS_END
    align 8
    SKBMP gh_guard_f_back, gh_guard_f_back_rows, 2, 2, gh_pal
    ; gh_guard_f_front (2x2 at 0,0 of the 2x3 FRONT face)
    SKROWS gh_guard_f_front_rows, 2, 2
    SKROW "ii"
    SKROW "jj"
    SKROWS_END
    align 8
    SKBMP gh_guard_f_front, gh_guard_f_front_rows, 2, 2, gh_pal
    ; gh_guard_b_top (1x7 at 0,0 of the 2x7 TOP face)
    SKROWS gh_guard_b_top_rows, 1, 7
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROW "j"
    SKROWS_END
    align 8
    SKBMP gh_guard_b_top, gh_guard_b_top_rows, 1, 7, gh_pal
    ; gh_trigger_right (1x1 at 0,0 of the 1x2 RIGHT face)
    SKROWS gh_trigger_right_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gh_trigger_right, gh_trigger_right_rows, 1, 1, gh_pal
    ; gh_trigger_left (1x1 at 0,0 of the 1x2 LEFT face)
    SKROWS gh_trigger_left_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gh_trigger_left, gh_trigger_left_rows, 1, 1, gh_pal
    ; gh_trigger_top (1x1 at 1,0 of the 2x1 TOP face)
    SKROWS gh_trigger_top_rows, 1, 1
    SKROW "i"
    SKROWS_END
    align 8
    SKBMP gh_trigger_top, gh_trigger_top_rows, 1, 1, gh_pal
    ; gh_trigger_back (2x1 at 0,0 of the 2x2 BACK face)
    SKROWS gh_trigger_back_rows, 2, 1
    SKROW "ii"
    SKROWS_END
    align 8
    SKBMP gh_trigger_back, gh_trigger_back_rows, 2, 1, gh_pal
    ; gh_trigger_front (2x1 at 0,0 of the 2x2 FRONT face)
    SKROWS gh_trigger_front_rows, 2, 1
    SKROW "ii"
    SKROWS_END
    align 8
    SKBMP gh_trigger_front, gh_trigger_front_rows, 2, 1, gh_pal

section .data
SKMODEL_BEGIN m_gun_hrifle, 64, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART gh_barrel_a, -1, 2, -64, 2, 2, 23, 0, 0                  ; blued barrel with a polished muzzle
    PART gh_barrel_b, -1, 2, -41, 2, 2, 23, 0, 0                  ; blued barrel with a polished muzzle
    PART gh_fsight, -1, 4, -62, 2, 1, 2, 0, 0                     ; front sight with a white bead
    PART gh_fore_a, -3, -2, -47, 6, 4, 17, 0, 0                   ; oak fore-end with a dark tip and a white line spacer
    PART gh_fore_b, -3, -2, -30, 6, 4, 17, 0, 0                   ; oak fore-end with a dark tip and a white line spacer
    PART gh_receiver, -3, -1, -13, 6, 6, 19, 0, 0                 ; dark receiver with an ejection port and scope-base screws
    PART gh_belly, -3, -4, -13, 6, 3, 19, 0, 0                    ; oak stock under the receiver
    PART gh_shroud, -1, 3, 6, 2, 2, 2, 0, 0                       ; bolt shroud
    PART gh_handle, 3, 2, 0, 1, 1, 3, 0, 0                        ; bolt handle
    PART gh_knob, 3, 0, 1, 1, 2, 2, 0, 0                          ; bolt knob
    PART gh_scope, -1, 6, -17, 2, 2, 14, 0, 0                     ; scope tube
    PART gh_bell, -2, 5, -22, 4, 4, 5, 0, 0                       ; objective bell with a glass lens
    PART gh_eyepiece, -2, 5, -3, 4, 4, 4, 0, 0                    ; eyepiece with a glass lens
    PART gh_turret, -1, 8, -11, 2, 1, 2, 0, 0                     ; brass elevation turret
    PART gh_mount_f, -1, 5, -14, 2, 1, 2, 0, 0                    ; iron scope mount
    PART_AS gh_mount_r, gh_mount_f, -1, 5, -7, 0, 0               ; mirrored twin of mount_f
    PART gh_wrist, -3, -4, 6, 6, 7, 6, 0, 0                       ; oak wrist
    PART gh_butt_a, -3, -6, 12, 6, 9, 7, 0, 0                     ; oak butt, upper step with the cheek line
    PART gh_butt_b, -3, -9, 19, 6, 11, 7, 0, 0                    ; oak butt, lower step
    PART gh_pad, -3, -9, 26, 6, 11, 1, 0, 0                       ; ribbed recoil pad
    PART gh_guard_f, -1, -7, -6, 2, 3, 1, 0, 0                    ; trigger guard, front post
    PART gh_guard_b, -1, -7, -5, 2, 1, 7, 0, 0                    ; trigger guard, bar
    PART_AS gh_guard_r, gh_guard_f, -1, -7, 2, 0, 0               ; trigger guard, rear post
    PART gh_trigger, -1, -6, -1, 2, 2, 1, 0, 0                    ; trigger
SKMODEL_PAINT
    ; --- gh_barrel_a  (blued barrel with a polished muzzle)
    SK_FILL gh_barrel_a, SKM_FRONT, GUN_BORE, 0
    SK_FILL gh_barrel_a, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK, GUN_STEEL_1, 0
    SK_FILL gh_barrel_a, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gh_barrel_a, SKF_RIGHT, 0, 0, gh_barrel_a_right
    SK_BMP gh_barrel_a, SKF_LEFT, 3, 0, gh_barrel_a_left
    SK_BMP gh_barrel_a, SKF_TOP, 0, 0, gh_barrel_a_top
    SK_BMP gh_barrel_a, SKF_FRONT, 0, 0, gh_barrel_a_front
    ; --- gh_barrel_b  (blued barrel with a polished muzzle)
    SK_FILL gh_barrel_b, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_FRONT, GUN_STEEL_3, 0
    SK_FILL gh_barrel_b, SKM_BACK, GUN_STEEL_1, 0
    SK_FILL gh_barrel_b, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gh_barrel_b, SKF_RIGHT, 0, 0, gh_barrel_b_right
    SK_BMP gh_barrel_b, SKF_LEFT, 0, 0, gh_barrel_b_left
    SK_BMP gh_barrel_b, SKF_TOP, 1, 4, gh_barrel_b_top
    SK_BMP gh_barrel_b, SKF_BACK, 0, 1, gh_barrel_b_back
    ; --- gh_fsight  (front sight with a white bead)
    SK_FILL gh_fsight, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_FRONT, AC_IRON_3, 0
    SK_FILL gh_fsight, SKM_BACK, GUN_WHITE, 0
    SK_FILL gh_fsight, SKM_BOTTOM, GUN_STEEL_4, 0
    ; --- gh_fore_a  (oak fore-end with a dark tip and a white line spacer)
    SK_FILL gh_fore_a, SKM_FRONT, GUN_DARK_3, 0
    SK_FILL gh_fore_a, SKM_RIGHT | SKM_LEFT | SKM_BOTTOM | SKM_BACK, AC_WOOD_3, 0
    SK_FILL gh_fore_a, SKM_TOP, AC_WOOD_2, 15
    SK_BMP gh_fore_a, SKF_RIGHT, 0, 0, gh_fore_a_right
    SK_BMP gh_fore_a, SKF_LEFT, 0, 0, gh_fore_a_left
    SK_BMP gh_fore_a, SKF_TOP, 0, 0, gh_fore_a_top
    SK_BMP gh_fore_a, SKF_BOTTOM, 0, 0, gh_fore_a_bottom
    SK_BMP gh_fore_a, SKF_FRONT, 0, 0, gh_fore_a_front
    SK_GRAD gh_fore_a, SKM_RIGHT | SKM_LEFT, 256, 228
    ; --- gh_fore_b  (oak fore-end with a dark tip and a white line spacer)
    SK_FILL gh_fore_b, SKM_RIGHT | SKM_LEFT | SKM_BOTTOM | SKM_BACK | SKM_FRONT, AC_WOOD_3, 0
    SK_FILL gh_fore_b, SKM_TOP, AC_WOOD_2, 15
    SK_BMP gh_fore_b, SKF_RIGHT, 0, 1, gh_fore_b_right
    SK_BMP gh_fore_b, SKF_LEFT, 0, 1, gh_fore_b_left
    SK_BMP gh_fore_b, SKF_TOP, 0, 0, gh_fore_b_top
    SK_BMP gh_fore_b, SKF_BOTTOM, 0, 0, gh_fore_b_bottom
    SK_BMP gh_fore_b, SKF_BACK, 1, 1, gh_fore_b_back
    SK_GRAD gh_fore_b, SKM_RIGHT | SKM_LEFT, 256, 228
    ; --- gh_receiver  (dark receiver with an ejection port and scope-base screws)
    SK_FILL gh_receiver, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, GUN_DARK_2, 0
    SK_FILL gh_receiver, SKM_BOTTOM, GUN_DARK_4, 0
    SK_BMP gh_receiver, SKF_RIGHT, 0, 0, gh_receiver_right
    SK_BMP gh_receiver, SKF_LEFT, 0, 0, gh_receiver_left
    SK_BMP gh_receiver, SKF_TOP, 0, 0, gh_receiver_top
    SK_BMP gh_receiver, SKF_BACK, 0, 0, gh_receiver_back
    SK_BMP gh_receiver, SKF_FRONT, 0, 0, gh_receiver_front
    ; --- gh_belly  (oak stock under the receiver)
    SK_FILL gh_belly, SKM_LEFT | SKM_BOTTOM | SKM_BACK | SKM_FRONT, AC_WOOD_3, 0
    SK_FILL gh_belly, SKM_TOP, AC_WOOD_2, 15
    SK_FILL gh_belly, SKM_RIGHT, AC_WOOD_1, 0
    SK_BMP gh_belly, SKF_RIGHT, 0, 1, gh_belly_right
    SK_BMP gh_belly, SKF_LEFT, 0, 0, gh_belly_left
    SK_BMP gh_belly, SKF_TOP, 0, 0, gh_belly_top
    SK_BMP gh_belly, SKF_BOTTOM, 0, 0, gh_belly_bottom
    SK_BMP gh_belly, SKF_BACK, 1, 1, gh_belly_back
    SK_BMP gh_belly, SKF_FRONT, 1, 1, gh_belly_front
    SK_GRAD gh_belly, SKM_RIGHT | SKM_LEFT, 256, 228
    ; --- gh_shroud  (bolt shroud)
    SK_FILL gh_shroud, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, GUN_STEEL_1, 0
    SK_FILL gh_shroud, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gh_shroud, SKF_RIGHT, 0, 1, gh_shroud_right
    SK_BMP gh_shroud, SKF_LEFT, 0, 1, gh_shroud_left
    SK_BMP gh_shroud, SKF_TOP, 0, 0, gh_shroud_top
    SK_BMP gh_shroud, SKF_BACK, 0, 0, gh_shroud_back
    SK_BMP gh_shroud, SKF_FRONT, 0, 1, gh_shroud_front
    ; --- gh_handle  (bolt handle)
    SK_FILL gh_handle, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, GUN_STEEL_2, 0
    SK_FILL gh_handle, SKM_BOTTOM, GUN_STEEL_4, 0
    ; --- gh_knob  (bolt knob)
    SK_FILL gh_knob, SKM_LEFT | SKM_BACK | SKM_FRONT, GUN_STEEL_1, 0
    SK_FILL gh_knob, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gh_knob, SKM_RIGHT | SKM_TOP, GUN_STEEL_2, 0
    SK_BMP gh_knob, SKF_RIGHT, 0, 0, gh_knob_right
    SK_BMP gh_knob, SKF_LEFT, 0, 1, gh_knob_left
    SK_BMP gh_knob, SKF_BACK, 0, 1, gh_knob_back
    SK_BMP gh_knob, SKF_FRONT, 0, 1, gh_knob_front
    ; --- gh_scope  (scope tube)
    SK_FILL gh_scope, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, GUN_DARK_1, 0
    SK_FILL gh_scope, SKM_BOTTOM, GUN_DARK_4, 0
    SK_BMP gh_scope, SKF_RIGHT, 0, 1, gh_scope_right
    SK_BMP gh_scope, SKF_LEFT, 0, 1, gh_scope_left
    SK_BMP gh_scope, SKF_TOP, 0, 0, gh_scope_top
    SK_BMP gh_scope, SKF_BACK, 0, 1, gh_scope_back
    SK_BMP gh_scope, SKF_FRONT, 0, 1, gh_scope_front
    ; --- gh_bell  (objective bell with a glass lens)
    SK_FILL gh_bell, SKM_FRONT, GUN_DARK_3, 0
    SK_FILL gh_bell, SKM_BACK, GUN_DARK_1, 0
    SK_FILL gh_bell, SKM_BOTTOM, GUN_DARK_4, 0
    SK_FILL gh_bell, SKM_RIGHT | SKM_LEFT | SKM_TOP, GUN_DARK_2, 0
    SK_BMP gh_bell, SKF_RIGHT, 0, 0, gh_bell_right
    SK_BMP gh_bell, SKF_LEFT, 0, 0, gh_bell_left
    SK_BMP gh_bell, SKF_TOP, 0, 0, gh_bell_top
    SK_BMP gh_bell, SKF_BACK, 0, 1, gh_bell_back
    SK_BMP gh_bell, SKF_FRONT, 0, 0, gh_bell_front
    ; --- gh_eyepiece  (eyepiece with a glass lens)
    SK_FILL gh_eyepiece, SKM_BACK | SKM_FRONT, GUN_DARK_1, 0
    SK_FILL gh_eyepiece, SKM_BOTTOM, GUN_DARK_4, 0
    SK_FILL gh_eyepiece, SKM_RIGHT | SKM_LEFT | SKM_TOP, GUN_DARK_2, 0
    SK_BMP gh_eyepiece, SKF_RIGHT, 0, 0, gh_eyepiece_right
    SK_BMP gh_eyepiece, SKF_LEFT, 0, 0, gh_eyepiece_left
    SK_BMP gh_eyepiece, SKF_TOP, 0, 0, gh_eyepiece_top
    SK_BMP gh_eyepiece, SKF_BACK, 1, 1, gh_eyepiece_back
    SK_BMP gh_eyepiece, SKF_FRONT, 0, 1, gh_eyepiece_front
    ; --- gh_turret  (brass elevation turret)
    SK_FILL gh_turret, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, AC_GOLD_3, 0
    SK_FILL gh_turret, SKM_BOTTOM, GUN_BRASS_DEEP, 0
    SK_BMP gh_turret, SKF_TOP, 0, 0, gh_turret_top
    ; --- gh_mount_f  (iron scope mount)
    SK_FILL gh_mount_f, SKM_RIGHT | SKM_LEFT | SKM_BACK | SKM_FRONT, AC_IRON_3, 0
    SK_FILL gh_mount_f, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gh_mount_f, SKM_TOP, AC_IRON_4, 0
    SK_BMP gh_mount_f, SKF_TOP, 1, 0, gh_mount_f_top
    ; --- gh_wrist  (oak wrist)
    SK_FILL gh_wrist, SKM_BOTTOM | SKM_BACK | SKM_FRONT, AC_WOOD_3, 0
    SK_FILL gh_wrist, SKM_RIGHT | SKM_LEFT | SKM_TOP, AC_WOOD_2, 15
    SK_BMP gh_wrist, SKF_RIGHT, 0, 0, gh_wrist_right
    SK_BMP gh_wrist, SKF_LEFT, 0, 0, gh_wrist_left
    SK_BMP gh_wrist, SKF_TOP, 0, 0, gh_wrist_top
    SK_BMP gh_wrist, SKF_BOTTOM, 0, 2, gh_wrist_bottom
    SK_BMP gh_wrist, SKF_BACK, 1, 1, gh_wrist_back
    SK_BMP gh_wrist, SKF_FRONT, 1, 1, gh_wrist_front
    SK_GRAD gh_wrist, SKM_RIGHT | SKM_LEFT, 256, 228
    ; --- gh_butt_a  (oak butt, upper step with the cheek line)
    SK_FILL gh_butt_a, SKM_BOTTOM | SKM_BACK | SKM_FRONT, AC_WOOD_3, 0
    SK_FILL gh_butt_a, SKM_RIGHT | SKM_LEFT | SKM_TOP, AC_WOOD_2, 15
    SK_BMP gh_butt_a, SKF_RIGHT, 0, 0, gh_butt_a_right
    SK_BMP gh_butt_a, SKF_LEFT, 0, 0, gh_butt_a_left
    SK_BMP gh_butt_a, SKF_TOP, 0, 0, gh_butt_a_top
    SK_BMP gh_butt_a, SKF_BOTTOM, 2, 0, gh_butt_a_bottom
    SK_BMP gh_butt_a, SKF_BACK, 1, 1, gh_butt_a_back
    SK_BMP gh_butt_a, SKF_FRONT, 1, 1, gh_butt_a_front
    SK_GRAD gh_butt_a, SKM_RIGHT | SKM_LEFT, 256, 228
    ; --- gh_butt_b  (oak butt, lower step)
    SK_FILL gh_butt_b, SKM_TOP | SKM_BOTTOM | SKM_BACK | SKM_FRONT, AC_WOOD_3, 0
    SK_FILL gh_butt_b, SKM_RIGHT | SKM_LEFT, AC_WOOD_2, 15
    SK_BMP gh_butt_b, SKF_RIGHT, 0, 0, gh_butt_b_right
    SK_BMP gh_butt_b, SKF_LEFT, 0, 0, gh_butt_b_left
    SK_BMP gh_butt_b, SKF_TOP, 1, 0, gh_butt_b_top
    SK_BMP gh_butt_b, SKF_BACK, 1, 1, gh_butt_b_back
    SK_BMP gh_butt_b, SKF_FRONT, 1, 1, gh_butt_b_front
    SK_GRAD gh_butt_b, SKM_RIGHT | SKM_LEFT, 256, 228
    ; --- gh_pad  (ribbed recoil pad)
    SK_FILL gh_pad, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, GUN_DARK_2, 0
    SK_FILL gh_pad, SKM_BOTTOM, GUN_DARK_4, 0
    SK_BMP gh_pad, SKF_RIGHT, 0, 0, gh_pad_right
    SK_BMP gh_pad, SKF_LEFT, 0, 0, gh_pad_left
    SK_BMP gh_pad, SKF_TOP, 0, 0, gh_pad_top
    SK_BMP gh_pad, SKF_BACK, 0, 0, gh_pad_back
    SK_BMP gh_pad, SKF_FRONT, 0, 0, gh_pad_front
    ; --- gh_guard_f  (trigger guard, front post)
    SK_FILL gh_guard_f, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, AC_IRON_4, 0
    SK_FILL gh_guard_f, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gh_guard_f, SKF_RIGHT, 0, 0, gh_guard_f_right
    SK_BMP gh_guard_f, SKF_LEFT, 0, 0, gh_guard_f_left
    SK_BMP gh_guard_f, SKF_TOP, 1, 0, gh_guard_f_top
    SK_BMP gh_guard_f, SKF_BACK, 0, 0, gh_guard_f_back
    SK_BMP gh_guard_f, SKF_FRONT, 0, 0, gh_guard_f_front
    ; --- gh_guard_b  (trigger guard, bar)
    SK_FILL gh_guard_b, SKM_RIGHT | SKM_LEFT | SKM_BACK | SKM_FRONT, AC_IRON_3, 0
    SK_FILL gh_guard_b, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_FILL gh_guard_b, SKM_TOP, AC_IRON_2, 0
    SK_BMP gh_guard_b, SKF_TOP, 0, 0, gh_guard_b_top
    ; --- gh_trigger  (trigger)
    SK_FILL gh_trigger, SKM_RIGHT | SKM_LEFT | SKM_TOP | SKM_BACK | SKM_FRONT, AC_IRON_4, 0
    SK_FILL gh_trigger, SKM_BOTTOM, GUN_STEEL_4, 0
    SK_BMP gh_trigger, SKF_RIGHT, 0, 0, gh_trigger_right
    SK_BMP gh_trigger, SKF_LEFT, 0, 0, gh_trigger_left
    SK_BMP gh_trigger, SKF_TOP, 1, 0, gh_trigger_top
    SK_BMP gh_trigger, SKF_BACK, 0, 0, gh_trigger_back
    SK_BMP gh_trigger, SKF_FRONT, 0, 0, gh_trigger_front
SKMODEL_END
