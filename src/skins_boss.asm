; skins_boss.asm: the skin model of the Fallen King, the crypt boss (0.13 "looks"). Data only: bones, parts and paint
; ops for skin.asm (art.inc, common.inc "0.13 looks"); nothing here runs.
;
;   m_boss     44 parts (25 own skins, the rest PART_AS), 160 packed atlas rows, held default KINGS_BLADE. A bleached
;              skull with scowling glowing red eyes, a heavy brow, cracks and a jutting fanged jaw with an ember glow in
;              the throat, under a gold crown (eight spikes, rubies, a crimson velvet top); an ermine collar and two
;              ermine shoulder mantles with gold studs; a ragged royal-purple robe, open at the chest on the ribcage
;              (ermine and gold edges, a crimson and gold panel, moth holes, a gold hem band, tatters), a crimson sash
;              with a gold ruby buckle and a ruby pendant; a crimson cape with a gold crown sigil; bony legs with
;              gilded kneecaps and torn crimson wraps; bony arms in torn sleeves with gold cuffs and an iron manacle at
;              each wrist, a clawed left hand and a right fist that closes on the held item (hand point (18, 45, -3)).
;              Prefix bs_.
;
; Model space (texels, origin = feet centre, front = -Z), the old boss boxes of mobrender.asm x 32 (the Fallen King is
; 3.3 blocks tall: 107 texels to the crown spikes):
;   legs   8 wide, 42 tall (femur, kneecap, shin, foot), pivot (42, 0), swing +1 / -1
;   robe   28 x 42 x 16 from y 35 to 77, rigid (collar, sash and cape hang on it)
;   arms   8 wide boxes at x +-14..22: bone y 50..75, sleeve y 59..73, mantle to y 79, hands to y 39; pivot (74, 0),
;          swing -0.5 / +0.5
;   head   22^3 from y 77 to 99, crown 24 wide from y 99 to 107, rigid
; Drawn like every mob (feet origin, uniform scale about the feet for the wind-up surge and the elite size, tint on
; every part): mobrender.asm has no boss-specific tint or scale rule, and MOB.wid is 0 for the boss, so the pose's
; held item falls back to KINGS_BLADE.
;
; Local helpers (private to this file):
;   RAMP prefix, r, g, b                defines prefix_1 .. prefix_4: highlight (base x 1.2, clamped), base,
;                                       shade (x 0.75), deep (x 0.55), packed RGBO.
;   PART name, x0, y0, z0, w, h, d, grow, flags
;   PART_AS name, k, x0, y0, z0, grow, flags
;                                       SKPART / SKPART_AS; `name` becomes the part's index, so the paint ops
;                                       name parts, not numbers. Names are bs_<part>.
; Conventions (those of skins_mobs.asm):
;   - one palette (bs_pal) holds every character its bitmaps use; a material takes a group of letters, lower case =
;     base tone, upper case = highlight, the next two letters = shade and deep (the comment above the palette lists
;     them). '_' is a transparent texel (PALT, cutouts), '.' keeps the texel.
;   - a part's ops run: SK_FILL (grain), SK_GRAD on the four vertical faces (272 -> 224; 272 -> 200 on the robe and
;     272 -> 204 on the cape, which end in a dirty hem; 264 -> 232 on the ermine, which stays white), then the
;     bitmaps, whose texels keep their full colour; '.' texels show the graded fill. Cutout parts (robe, collar,
;     cape, sleeves, rag wraps, crown spikes) are filled like any part and then punched with '_' bitmaps; every
;     face keeps at least one opaque texel.
;   - bitmaps have the size of the face they paint (a face image is seen from outside, upright, (0, 0) top left:
;     the unwrap table of the design doc); the light comes from the top left, so a face's left column is the lit one.
;   - left/right pairs share one skin (PART_AS): the legs, the sleeves, the mantles, the arm bones, the palms and the
;     eight crown spikes.
;   - grain: noise 15 on cloth and bone, 23 on fur, 7 on the small finger parts, 0 on gold, iron, gems and trims.
;   - skin_build packs the unwraps in record order with next-fit shelves (a part costs 2(w+d) x (d+h) atlas texels), so
;     the records are in packing order: the bones and the parts inside them are ordered for the fewest rows, an AS part
;     after its source. The bone order is therefore not the anatomical one; skin_model_draw draws any order.
; Ramps (RAMP: _1 highlight, _2 base, _3 shade, _4 deep; AC_* are the shared material ramps of art.inc):
;   m_boss             BS_BONE (222,214,192), BS_ROBE (92,48,120), BS_CRIM (150,28,54), BS_FUR (250,246,236)
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
; m_boss
; ===================================================================================================
RAMP BS_BONE, 222, 214, 192            ; bleached bone (the old boss face tile)
RAMP BS_ROBE, 92, 48, 120              ; royal purple (the old robe tile, lifted)
RAMP BS_CRIM, 150, 28, 54              ; crimson cape, sash and trim (the old robe stripes)
RAMP BS_FUR, 250, 246, 236             ; ermine

section .rodata
; The characters of every bs_ bitmap. Groups: base, highlight, shade, deep.
;   s S k K bone   y Y aged bone   x X v void, socket rim
;   e E h H eye glow: halo, glow, hot, white-hot (e also the dim embers)   z Z bone lit by the glow
;   p P q Q royal purple   c C r R crimson   g G o O gold   f F u ermine fur   t T ermine tail spots
;   i I j J iron   m M w W ruby   _ transparent
align 8
bs_pal:
    PALC 's', BS_BONE_2
    PALC 'S', BS_BONE_1
    PALC 'k', BS_BONE_3
    PALC 'K', BS_BONE_4
    PALC 'y', RGBO(196, 176, 132)
    PALC 'Y', RGBO(150, 128, 92)
    PALC 'x', RGBO(22, 12, 26)
    PALC 'X', RGBO(64, 44, 60)
    PALC 'v', RGBO(10, 6, 14)
    PALC 'e', RGBO(150, 18, 22)
    PALC 'E', RGBO(236, 56, 28)
    PALC 'h', RGBO(255, 168, 56)
    PALC 'H', RGBO(255, 244, 190)
    PALC 'z', RGBO(204, 156, 138)
    PALC 'Z', RGBO(160, 104, 96)
    PALC 'p', BS_ROBE_2
    PALC 'P', BS_ROBE_1
    PALC 'q', BS_ROBE_3
    PALC 'Q', BS_ROBE_4
    PALC 'c', BS_CRIM_2
    PALC 'C', BS_CRIM_1
    PALC 'r', BS_CRIM_3
    PALC 'R', BS_CRIM_4
    PALC 'g', AC_GOLD_2
    PALC 'G', AC_GOLD_1
    PALC 'o', AC_GOLD_3
    PALC 'O', AC_GOLD_4
    PALC 'f', BS_FUR_2
    PALC 'F', BS_FUR_1
    PALC 'u', BS_FUR_3
    PALC 't', RGBO(30, 24, 36)
    PALC 'T', RGBO(70, 60, 78)
    PALC 'i', AC_IRON_2
    PALC 'I', AC_IRON_1
    PALC 'j', AC_IRON_3
    PALC 'J', AC_IRON_4
    PALC 'm', RGBO(214, 28, 52)
    PALC 'M', RGBO(255, 160, 170)
    PALC 'w', RGBO(150, 16, 36)
    PALC 'W', RGBO(92, 8, 24)
    PALT '_'
    dq 0

    ; bs_core_front (18x32): bs_core FRONT
    SKROWS bs_core_front_rows, 18, 32
    SKROW ".................."
    SKROW ".SSSSSSSSSSSSSSSS."
    SKROW "kssssssssssssssssk"
    SKROW "vvvvvvSSSSSSvvvvvv"
    SKROW "vvvvssssskssssvvvv"
    SKROW "vvvSkkkkSkkkkkSvvv"
    SKROW "vvvkvvvvSkvvvvkvvv"
    SKROW "vvvvvsssSksssvvvvv"
    SKROW "vvssskkkskkkksssvv"
    SKROW "vSkkkvevSkvevkkkSv"
    SKROW "vkvvvvssSkssvvvvkv"
    SKROW "vvvssskkeekksssvvv"
    SKROW "vsskkkveskevkkkssv"
    SKROW "SkkvvvssSkssvvvkkS"
    SKROW "kvvvsskkSkkkssvvvk"
    SKROW "vvsskevvSkvvekssvv"
    SKROW "vSkkvvvssksvvvkkSv"
    SKROW "vkvvvsskskkssvvvkv"
    SKROW "vvvsskkvkvvkkssvvv"
    SKROW "vvSkkvvvskvvvkkSvv"
    SKROW "vvkvvvvvkkvvvvvkvv"
    SKROW "vvvvvvvvskvvvvvvvv"
    SKROW "vvvvvvvvkkvvvvvvvv"
    SKROW "vvvvvvvvskvvvvvvvv"
    SKROW "vvvvvvvvkkvvvvvvvv"
    SKROW "vvvvvvvvskvvvvvvvv"
    SKROW "vvvssssssssssssvvv"
    SKROW "vvkkkkkxxxxkkkkkvv"
    SKROW "vvvvkkkxxxxkkkvvvv"
    SKROW "vvvvvvvxxxxvvvvvvv"
    SKROW "vvvvvvvvvvvvvvvvvv"
    SKROW "vvvvvvvvvvvvvvvvvv"
    SKROWS_END
    align 8
    SKBMP bs_core_front, bs_core_front_rows, 18, 32, bs_pal
    ; bs_core_back (18x32): bs_core BACK
    SKROWS bs_core_back_rows, 18, 32
    SKROW "........Sk........"
    SKROW "........sk........"
    SKROW "........sk........"
    SKROW "........Sk........"
    SKROW "..kkkkkkskkkkkkk.."
    SKROW "....S...sk...S...."
    SKROW "...SSS..Sk.SSSS..."
    SKROW "..SSSSSkskkSSSSS.."
    SKROW "..SSSSS.sk.SSSSS.."
    SKROW "..SSSSS.Sk.SSSSS.."
    SKROW "..kSSSkkskkSSSSk.."
    SKROW ".....S..sk...S...."
    SKROW "........Sk........"
    SKROW "..kkkkkkskkkkkkk.."
    SKROW "........sk........"
    SKROW "........Sk........"
    SKROW "..kkkkkkskkkkkkk.."
    SKROW "........sk........"
    SKROW "........Sk........"
    SKROW "..kkkkkkskkkkkkk.."
    SKROW "........sk........"
    SKROW "........Sk........"
    SKROW "..kkkkkkskkkkkkk.."
    SKROW "........sk........"
    SKROW "........Sk........"
    SKROW "........sk........"
    SKROW "...ssssssssssss..."
    SKROW "..kkkkkkkkkkkkkk.."
    SKROW "........sk........"
    SKROW "........sk........"
    SKROW "........Sk........"
    SKROW "........sk........"
    SKROWS_END
    align 8
    SKBMP bs_core_back, bs_core_back_rows, 18, 32, bs_pal
    ; bs_core_side (10x32): bs_core RIGHT, bs_core LEFT
    SKROWS bs_core_side_rows, 10, 32
    SKROW ".........."
    SKROW ".........."
    SKROW ".........."
    SKROW ".kkkkkkkk."
    SKROW ".........."
    SKROW ".........."
    SKROW ".kkkkkkkk."
    SKROW ".........."
    SKROW ".........."
    SKROW ".kkkkkkkk."
    SKROW ".........."
    SKROW ".........."
    SKROW ".kkkkkkkk."
    SKROW ".........."
    SKROW ".........."
    SKROW ".kkkkkkkk."
    SKROW ".........."
    SKROW ".........."
    SKROW ".kkkkkkkk."
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
    SKROW ".........."
    SKROW ".........."
    SKROWS_END
    align 8
    SKBMP bs_core_side, bs_core_side_rows, 10, 32, bs_pal
    ; bs_robe_front (28x42): bs_robe FRONT
    SKROWS bs_robe_front_rows, 28, 42
    SKROW "Gc........................ro"
    SKROW "Gc........................ro"
    SKROW "Gc........................ro"
    SKROW "Gc........................ro"
    SKROW "Gc........................ro"
    SKROW "Gc......QQQQQQQQQQQQ......ro"
    SKROW "Gc..gffQ____________Qtfo..ro"
    SKROW "Gc..gufQ____________uufo..ro"
    SKROW "GcPq.gftQ__________QFFoPq.ro"
    SKROW "GcPq.gfTQ__________QffoPq.ro"
    SKROW "GcPq..gffQ________QtFo.Pq.ro"
    SKROW "GcPq..gffu________QTfo.Pq.ro"
    SKROW "GcPq.PqgftQ______QffoPqPq.ro"
    SKROW "GcPq.PqgfFF______QufoPqPq.ro"
    SKROW "GcPq.Pq.gfFQ____Qtfo.PqPq.ro"
    SKROW "GcPq.Pq.gffQ____FTfo.PqPq.ro"
    SKROW "GcPq.Pq..gFtQ__QfFo..PqPq.ro"
    SKROW "GcPq.Pq..gfFQ__Qffo..PqPq.ro"
    SKROW "GcPq.Pq..gftfQQfffo..PqPq.ro"
    SKROW "GcPq.Pq..gCccccccro..PqPq.ro"
    SKROW "GcPq.PqPqgCccccccroq.PqPq.ro"
    SKROW "GcPq.PqPqgCccccccroq.PqPq.ro"
    SKROW "GcPq.PqPqgCccccccroq.PqPq.ro"
    SKROW "GcPq.PqPqgCccccccroq.PqPq.ro"
    SKROW "GcPq.PqPqgCccccccroq.QQQq.ro"
    SKROW "GcPqQPqPqgCccccccroqQ___Q.ro"
    SKROW "GcPQ__QPqgCccccccroq.Q_Qq.ro"
    SKROW "GcPQ___QqgCccccccroq.PQPq.ro"
    SKROW "GcPqQ_QPqgCccggccroq.PqPq.ro"
    SKROW "GcPq.QqPqgCcgGGgcroq.PqPq.ro"
    SKROW "GcPq.PqPqgCccggccroq.PqPq.ro"
    SKROW "Gcggggggggggggggggggggggggro"
    SKROW "Gcooooooooooooooooooooooooro"
    SKROW "GcrrrrrrrgCccccccrorrrrrrrro"
    SKROW "Gc......qgCccccccro.QQQ...ro"
    SKROW "Gc....QQ.gCccccccroQ___Q..ro"
    SKROW "Gc...Q__QgCccccccroQ___Q..ro"
    SKROW "Gc..Q__Q.gCccggccro.Q_Qq..ro"
    SKROW "QcQQQQ_Q.gQcgGGgcro..Q.QQQQQ"
    SKROW "_Q______QQ_QcgQQcrQQ..Q_____"
    SKROW "____________QQ__QQ__QQ______"
    SKROW "____________________________"
    SKROWS_END
    align 8
    SKBMP bs_robe_front, bs_robe_front_rows, 28, 42, bs_pal
    ; bs_robe_back (28x42): bs_robe BACK
    SKROWS bs_robe_back_rows, 28, 42
    SKROW "Gc........................ro"
    SKROW "Gc........................ro"
    SKROW "Gc........................ro"
    SKROW "Gc...........qq...........ro"
    SKROW "Gc..Pq.......qQ.q....Pq.q.ro"
    SKROW "Gc..Pq.......qq......Pq...ro"
    SKROW "Gc..Pq.......qq......Pq..qro"
    SKROW "Gc..Pq.......qq......Pq.q.ro"
    SKROW "Gc..Pq..Pq...qQ..Pq..Pq...ro"
    SKROW "Gc..Pq..Pq...qq..Pq..Pq...ro"
    SKROW "Gc..Pq..Pq...qq..Pq..Pq...ro"
    SKROW "Gc..Pq..Pq...qq..Pq..Pq...ro"
    SKROW "Gc..Pq..Pq...qQ..Pq..Pq...ro"
    SKROW "Gc..Pq..Pq...qq..Pqqqqqq..ro"
    SKROW "Gc..Pq..Pq...qq..PqPPPPq..ro"
    SKROW "Gc..Pq..Pq...qq..PqPPPPq..ro"
    SKROW "Gc..Pq..Pq...qQ..PqPPPPq..ro"
    SKROW "Gc..Pqq.Pq...qq..Pqqqqqq..ro"
    SKROW "Gc..Pq..Pq...qq..Pq.qPq...ro"
    SKROW "Gc..Pq..Pq...qq..Pq..Pq...ro"
    SKROW "Gc..Pq..Pq...qQ..Pq..Pq...ro"
    SKROW "Gc..Pq..Pq...qq..Pq..Pq...ro"
    SKROW "Gc..Pq..Pq...qq..Pq..Pq...ro"
    SKROW "Gc..Pq..Pq...qq..Pq..Pq...ro"
    SKROW "Gc..PQ.QPq...qQ..Pq..Pq...ro"
    SKROW "Gc..Q___Qq...qq..Pq.QPq...ro"
    SKROW "Gc..Q___Qq...qq..PqQ_Qq...ro"
    SKROW "Gc..P__QPq...qq..Pq___Q...ro"
    SKROW "Gc..PQQ.Pq...qQ..PqQ_Pq...ro"
    SKROW "Gc..Pq..Pq...qq..Pq.QPq...ro"
    SKROW "Gc..Pq..Pq...qq..Pq..Pq...ro"
    SKROW "Gcggggggggggggggggggggggggro"
    SKROW "Gcooooooooooooooooooooooooro"
    SKROW "Gcrrrrrrrrrrrrrrrrrrrrrrrrro"
    SKROW "Gc.QQ.....................ro"
    SKROW "GcQ__Q......QQ.......q....ro"
    SKROW "GcQ___Q....Q__Q.....q.....ro"
    SKROW "Gc.._Q....Q___Q...........ro"
    SKROW "QQQ.Q......Q_Q....Q..Q....ro"
    SKROW "___Q.QQQQ..QQ..QQQ_QQ_Q.QQQQ"
    SKROW "____.____QQ__QQ________Q____"
    SKROW "____Q_______________________"
    SKROWS_END
    align 8
    SKBMP bs_robe_back, bs_robe_back_rows, 28, 42, bs_pal
    ; bs_robe_side_r (16x42): bs_robe RIGHT
    SKROWS bs_robe_side_r_rows, 16, 42
    SKROW "p.............ro"
    SKROW "p.............ro"
    SKROW "p.............ro"
    SKROW "p..Pq.........ro"
    SKROW "p..Pq.....Pq..ro"
    SKROW "p..Pq.....Pq..ro"
    SKROW "p..Pq.....Pq..ro"
    SKROW "p..Pq.....Pq..ro"
    SKROW "p..Pq..Pq.Pq..ro"
    SKROW "p..Pq..Pq.Pq..ro"
    SKROW "p..Pq..Pq.Pq.qro"
    SKROW "p..Pq..Pq.Pq..ro"
    SKROW "p..Pq..Pq.Pq..ro"
    SKROW "pq.Pq..Pq.Pq..ro"
    SKROW "p..Pq..Pq.Pq..ro"
    SKROW "p..Pq..Pq.Pq..ro"
    SKROW "p..Pq..Pq.Pq..ro"
    SKROW "p..Pq..Pq.Pq..ro"
    SKROW "p..Pq..Pq.Pq..ro"
    SKROW "p..Pq..Pq.Pq..ro"
    SKROW "p..Pq..Pq.Pq..ro"
    SKROW "p..Pqq.Pq.Pq..ro"
    SKROW "p..PQQQPq.Pq..ro"
    SKROW "p..Q___QqqPq..ro"
    SKROW "p..P___Qq.Pq..ro"
    SKROW "p..PQ__Qq.Pq..ro"
    SKROW "p..PqQQPq.Pq..ro"
    SKROW "p..Pq..Pq.Pq..ro"
    SKROW "p..Pq..Pq.Pq..ro"
    SKROW "p..Pq..Pq.Pq..ro"
    SKROW "p..Pq..Pq.Pq..ro"
    SKROW "pggggggggggggggg"
    SKROW "pooooooooooooooo"
    SKROW "prrrrrrrrrrrrrrr"
    SKROW "p.............ro"
    SKROW "p.............ro"
    SKROW "p.............ro"
    SKROW "p.............ro"
    SKROW "QQQQQ..Q...q..rQ"
    SKROW "_____QQ_Q.QQ..Q_"
    SKROW "_________.__QQ__"
    SKROW "_________Q______"
    SKROWS_END
    align 8
    SKBMP bs_robe_side_r, bs_robe_side_r_rows, 16, 42, bs_pal
    ; bs_robe_side_l (16x42): bs_robe LEFT
    SKROWS bs_robe_side_l_rows, 16, 42
    SKROW "or.............p"
    SKROW "or.............p"
    SKROW "or.............p"
    SKROW "or.........qP..p"
    SKROW "or..qP.....qP..p"
    SKROW "or..qP.....qP..p"
    SKROW "or..qP.....qP..p"
    SKROW "or..qP.....qP..p"
    SKROW "or..qP.qP..qP..p"
    SKROW "or..qP.qP..qP..p"
    SKROW "orq.qP.qP..qP..p"
    SKROW "or..qP.qP..qP..p"
    SKROW "or..qP.qP..qP..p"
    SKROW "or..qP.qP..qP.qp"
    SKROW "or..qP.qP..qP..p"
    SKROW "or..qP.qP..qP..p"
    SKROW "or..qP.qP..qP..p"
    SKROW "or..qP.qP..qP..p"
    SKROW "or..qP.qP..qP..p"
    SKROW "or..qP.qP..qP..p"
    SKROW "or..qP.qP..qP..p"
    SKROW "or..qP.qP.qqP..p"
    SKROW "or..qP.qPQQQP..p"
    SKROW "or..qPqqQ___Q..p"
    SKROW "or..qP.qQ___P..p"
    SKROW "or..qP.qQ__QP..p"
    SKROW "or..qP.qPQQqP..p"
    SKROW "or..qP.qP..qP..p"
    SKROW "or..qP.qP..qP..p"
    SKROW "or..qP.qP..qP..p"
    SKROW "or..qP.qP..qP..p"
    SKROW "gggggggggggggggp"
    SKROW "ooooooooooooooop"
    SKROW "rrrrrrrrrrrrrrrp"
    SKROW "or.............p"
    SKROW "or.............p"
    SKROW "or.............p"
    SKROW "or.............p"
    SKROW "Qr..q...Q..QQQQQ"
    SKROW "_Q..QQ.Q_QQ_____"
    SKROW "__QQ__._________"
    SKROW "______Q_________"
    SKROWS_END
    align 8
    SKBMP bs_robe_side_l, bs_robe_side_l_rows, 16, 42, bs_pal
    ; bs_belt_front (30x5): bs_belt FRONT
    SKROWS bs_belt_front_rows, 30, 5
    SKROW "GGGGGGGGGGGGGGGGGGGGGGGGGGGGGG"
    SKROW "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCC"
    SKROW ".g..g..g..g..g..g..g..g..g..g."
    SKROW ".............................."
    SKROW "oooooooooooooooooooooooooooooo"
    SKROWS_END
    align 8
    SKBMP bs_belt_front, bs_belt_front_rows, 30, 5, bs_pal
    ; bs_belt_back (30x5): bs_belt BACK
    SKROWS bs_belt_back_rows, 30, 5
    SKROW "GGGGGGGGGGGGGGGGGGGGGGGGGGGGGG"
    SKROW "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCC"
    SKROW ".g..g..g..g..g..g..g..g..g..g."
    SKROW ".............................."
    SKROW "oooooooooooooooooooooooooooooo"
    SKROWS_END
    align 8
    SKBMP bs_belt_back, bs_belt_back_rows, 30, 5, bs_pal
    ; bs_belt_side (19x5): bs_belt RIGHT, bs_belt LEFT
    SKROWS bs_belt_side_rows, 19, 5
    SKROW "GGGGGGGGGGGGGGGGGGG"
    SKROW "CCCCCCCCCCCCCCCCCCC"
    SKROW ".g..g..g..g..g..g.."
    SKROW "..................."
    SKROW "ooooooooooooooooooo"
    SKROWS_END
    align 8
    SKBMP bs_belt_side, bs_belt_side_rows, 19, 5, bs_pal
    ; bs_buckle_front (8x7): bs_buckle FRONT
    SKROWS bs_buckle_front_rows, 8, 7
    SKROW "GGGGGGGg"
    SKROW "Gggggggo"
    SKROW "GgMmmwgo"
    SKROW "Ggmmwwgo"
    SKROW "GgwwWWgo"
    SKROW "Gggggggo"
    SKROW "ooooooOO"
    SKROWS_END
    align 8
    SKBMP bs_buckle_front, bs_buckle_front_rows, 8, 7, bs_pal
    ; bs_pendant_front (4x4): bs_pendant FRONT
    SKROWS bs_pendant_front_rows, 4, 4
    SKROW "Gggo"
    SKROW "gMmo"
    SKROW "gwWo"
    SKROW "oooO"
    SKROWS_END
    align 8
    SKBMP bs_pendant_front, bs_pendant_front_rows, 4, 4, bs_pal
    ; bs_collar_front (30x7): bs_collar FRONT
    SKROWS bs_collar_front_rows, 30, 7
    SKROW "F.u..Fu.......F......u....u..u"
    SKROW "F.t..Fu.t...F.t...u.tu...Ftu.u"
    SKROW "F.Tu...FT...F.T..Fu.T..u.FTu.u"
    SKROW "FFFu...F.........FF....u.F.F.u"
    SKROW "FFF..T..u..T.....TF..F.T.F.F.u"
    SKROW "F..___..___Fu.__.u.F__.._._F._"
    SKROW "F.____._________.u____________"
    SKROWS_END
    align 8
    SKBMP bs_collar_front, bs_collar_front_rows, 30, 7, bs_pal
    ; bs_collar_back (30x7): bs_collar BACK
    SKROWS bs_collar_back_rows, 30, 7
    SKROW "F...u..............u.........u"
    SKROW "F.t.u...t...u.t....Ft.u..Ft.uu"
    SKROW "F.T.....T...u.T....FT.u.uFT.uu"
    SKROW "F........F..F....u.u....u.F..u"
    SKROW "F.F..T...F.TF.uF.T.u..FT..Fu.u"
    SKROW "_F_._u...__FF___..__F.F____u._"
    SKROW "_____.__________.___F_._______"
    SKROWS_END
    align 8
    SKBMP bs_collar_back, bs_collar_back_rows, 30, 7, bs_pal
    ; bs_collar_side_r (20x7): bs_collar RIGHT
    SKROWS bs_collar_side_r_rows, 20, 7
    SKROW "F.......F..........u"
    SKROW "F.t.F...t..u.ut....u"
    SKROW "F.T.F...T..u.uT.F..u"
    SKROW "F..F........u...F..u"
    SKROW "F..F.Tuu...Tu.F..TFF"
    SKROW "F__F._u_F._..uF...F_"
    SKROW "______F____._uu_____"
    SKROWS_END
    align 8
    SKBMP bs_collar_side_r, bs_collar_side_r_rows, 20, 7, bs_pal
    ; bs_collar_side_l (20x7): bs_collar LEFT
    SKROWS bs_collar_side_l_rows, 20, 7
    SKROW "F...u.F............u"
    SKROW "u.tFu.F.t.....t....u"
    SKROW "u.TFu...T.u..uT....u"
    SKROW "F......F.Fu..u...F.u"
    SKROW "Fu...TFF.FFT..F..T.u"
    SKROW "F_________Fu..F.._.u"
    SKROW "___________.._._.___"
    SKROWS_END
    align 8
    SKBMP bs_collar_side_l, bs_collar_side_l_rows, 20, 7, bs_pal
    ; bs_collar_top (30x20): bs_collar TOP
    SKROWS bs_collar_top_rows, 30, 20
    SKROW "...u...F...u.......F........F."
    SKROW "..tu...Ft..u..t....Ft.....t.F."
    SKROW ".uT....uTF.F..T..u..Tu....T..."
    SKROW ".uF....u.F.F..uF.u..uu........"
    SKROW "F.F..T....FT...F.T.....T....u."
    SKROW "F....F....F....F.FF.........u."
    SKROW "..F....F.......F.FFF.....u...."
    SKROW "..T..F.FT.u.F.T...FFT....uT..."
    SKROW ".....F....u.F............F...."
    SKROW "....F......F............FF...."
    SKROW "...uFT.....T.....TF....TF....."
    SKROW "...u.uF.u...FuF...F....u.....u"
    SKROW "...u.uFFu...FuF.....F.....u..u"
    SKROW "..T...FFT...F.TF.u..T.....T..."
    SKROW "..F.......F....F.u........F..."
    SKROW "...F..uFu.Fu...F..........FF.."
    SKROW "...FuTuFFF.T.....T.....TF..F.F"
    SKROW "....u.F.FF.......u....u.F..F.F"
    SKROW ".F.....u.u.F..u..uF...u....F.."
    SKROW ".F.....u.u.F..u...F..........."
    SKROWS_END
    align 8
    SKBMP bs_collar_top, bs_collar_top_rows, 30, 20, bs_pal
    ; bs_cape_back (26x44): bs_cape BACK
    SKROWS bs_cape_back_rows, 26, 44
    SKROW "Gc......................ro"
    SKROW "Gc......................ro"
    SKROW "Gc......................ro"
    SKROW "Gc......................ro"
    SKROW "Gc......................ro"
    SKROW "Gc......................ro"
    SKROW "Gc..Cr.............Cr...ro"
    SKROW "Gc..Cr.............Cr...ro"
    SKROW "Gc..Cr.............Cr...ro"
    SKROW "Gc..Cr.G....GG....RCr...ro"
    SKROW "Gc..Cr.g....gg....RCr...ro"
    SKROW "Gc..Crggg..gggg..gggr...ro"
    SKROW "Gc..Crggggggggggggggr...ro"
    SKROW "Gc..CrggmgggMmgRgmggr...ro"
    SKROW "Gc..CrooooooooooRooOr...ro"
    SKROW "Gc..Cr..Cr.....Cr..Cr...ro"
    SKROW "Gc..Cr..Cr.....Cr..Cr...ro"
    SKROW "Gc..Cr..Cr.....Cr..Cr...ro"
    SKROW "Gc..Cr..Cr.....Cr.rCrr..ro"
    SKROW "Gcr.Cr..Cr.....Cr..Cr...ro"
    SKROW "Gc..Cr..Cr.....Cr..Cr...ro"
    SKROW "Gc..Cr..Cr.....Cr..Cr...ro"
    SKROW "Gc..RR..Cr.....Cr..Cr...ro"
    SKROW "Gc.R__R.Cr.....Cr..Cr...ro"
    SKROW "Gc.R___RCr.r...Crr.Cr...ro"
    SKROW "Gc..C_R.Cr.....Cr..Cr...ro"
    SKROW "Gc..CR..Cr.....Cr..Cr...ro"
    SKROW "Gc..Crr.Cr.....Cr..Cr...ro"
    SKROW "Gc..Cr..Cr.....Cr.rCrRR.ro"
    SKROW "Gc..Cr..Cr.....Crr.CR__Rro"
    SKROW "Gc..Cr..Cr.....Cr..R___Rro"
    SKROW "Gc..Cr..Cr.....Cr..R__R.ro"
    SKROW "Gc..Cr..Cr.....Cr..CRR..ro"
    SKROW "Gc..Cr..Cr.....Cr..Cr...ro"
    SKROW "GggggggggggggRgggggggggggo"
    SKROW "GoooooooooooR_Rooooooooooo"
    SKROW "Gc..Cr..Cr..R__Rr..Cr...ro"
    SKROW "Gc..Cr..Cr...RRCr..Cr...ro"
    SKROW "Gc......................ro"
    SKROW "Gc......................ro"
    SKROW "Gc..RRRRRRR.RRRR.....R..rR"
    SKROW "Gc.R_______R____RRR.R_RRR_"
    SKROW "RRRR_______________.______"
    SKROW "___________________R______"
    SKROWS_END
    align 8
    SKBMP bs_cape_back, bs_cape_back_rows, 26, 44, bs_pal
    ; bs_cape_front (26x44): bs_cape FRONT
    SKROWS bs_cape_front_rows, 26, 44
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrRRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrR__RrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrR___RrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrr_RrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrRRrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRr__Rrr"
    SKROW "rrrrrRrrrrrrRrrrrrrR___rrr"
    SKROW "rrrrrRrrrrrrRrrrrrrR__Rrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRRRrrrr"
    SKROW "rrrrrRrrrrrrRrrrrrrRrrrrrr"
    SKROW "rooooooooooooRooooooooooor"
    SKROW "rOOOOOOOOOOOR_ROOOOOOOOOOr"
    SKROW "rrrrrRrrrrrrR__RrrrRrrrrrr"
    SKROW "rrrrrRrrrrrrRrRrrrrRrrrrrr"
    SKROW "rrrrrrrrrrrrrrrrrrrrrrrrrr"
    SKROW "rrrrrrrrrrrrrrrrrrrrrrrrrr"
    SKROW "rrrrRRRRRRRrRRRRrrrrrRrrrR"
    SKROW "rrrR_______R____RRRrR_RRR_"
    SKROW "RRRR_______________R______"
    SKROW "___________________R______"
    SKROWS_END
    align 8
    SKBMP bs_cape_front, bs_cape_front_rows, 26, 44, bs_pal
    ; bs_cape_side (1x44): bs_cape RIGHT, bs_cape LEFT
    SKROWS bs_cape_side_rows, 1, 44
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "o"
    SKROW "_"
    SKROW "_"
    SKROW "_"
    SKROW "_"
    SKROW "_"
    SKROW "_"
    SKROW "_"
    SKROW "_"
    SKROWS_END
    align 8
    SKBMP bs_cape_side, bs_cape_side_rows, 1, 44, bs_pal
    ; bs_skull_front (22x22): bs_skull FRONT
    SKROWS bs_skull_front_rows, 22, 22
    SKROW "S.......k....k.k.....k"
    SKROW "S.......k....k.k.....k"
    SKROW "S......k.k..k.k......k"
    SKROW "S........K..K.K......k"
    SKROW "S....................k"
    SKROW "S....................k"
    SKROW "S....................k"
    SKROW "S..XXXXXXX..XXXXXXX..k"
    SKROW "S..xeEEXXX..XXXEEex..k"
    SKROW "S..xEhHEXX..XXEHhEx..k"
    SKROW "S..xeEhHEx..xEHhEex..k"
    SKROW "S..XxeEEekxxkeEEexX..k"
    SKROW "SS.XXxeekxxxxkeexXX.Sk"
    SKROW "SkSSSSSS.kxxk.SSSSSSkk"
    SKROW "SkkkSskSskSskSskSskkkk"
    SKROW "S..kSkkSkkSkkSkkSkk..k"
    SKROW "S..xskxskxskxskxskx..k"
    SKROW "S..xSkxeexeexeexSkx..k"
    SKROW "S..xxxxxxxxxxxxxxxx..k"
    SKROW "kkkxxxxxxxxxxxxxxxxkkk"
    SKROW "kkkxxxxxxxxxxxxxxxxkkk"
    SKROW "KKKxxxxxxxxxxxxxxxxKKK"
    SKROWS_END
    align 8
    SKBMP bs_skull_front, bs_skull_front_rows, 22, 22, bs_pal
    ; bs_skull_side_r (22x22): bs_skull RIGHT
    SKROWS bs_skull_side_r_rows, 22, 22
    SKROW "S...k.......k........k"
    SKROW "S...k.......k........k"
    SKROW "S....k.....k.........k"
    SKROW "S..k.k.....k.........k"
    SKROW "S..y..k.....k........k"
    SKROW "S..y..k.....k...SSSS.k"
    SKROW "S......K.....kSSkkkkSk"
    SKROW "S...........SSkk....zZ"
    SKROW "S..........Skk......zZ"
    SKROW "S.........Sk........zZ"
    SKROW "S.......SSSS........zZ"
    SKROW "S.......kxxk......SSkZ"
    SKROW "S........xx.......SSkZ"
    SKROW "S.....SskkkkSSSSSSSSkk"
    SKROW "S.....Ss....kkkkkkSSkk"
    SKROW "S.....Ss...kkkkkkkkkkk"
    SKROW "S.....kk...........Skk"
    SKROW "kkkkkkkkkkkkkkkkkkkSkk"
    SKROW "kkkkkkkkkkSSSkkkkkkkkk"
    SKROW "kkkkkkkkkkSSSkkkkkkkkk"
    SKROW "KKKKKKKKKKkkkKKKKKKKKK"
    SKROW "KKKKKKKKKKKKKKKKKKKKKK"
    SKROWS_END
    align 8
    SKBMP bs_skull_side_r, bs_skull_side_r_rows, 22, 22, bs_pal
    ; bs_skull_side_l (22x22): bs_skull LEFT
    SKROWS bs_skull_side_l_rows, 22, 22
    SKROW "k........k.......k...S"
    SKROW "k........k.......k...S"
    SKROW "k.........k.....k....S"
    SKROW "k.........k.....k.k..S"
    SKROW "k........k.....k..y..S"
    SKROW "k.SSSS...k.....k..y..S"
    SKROW "kSkkkkSSk.....K......S"
    SKROW "Zz....kkSS...........S"
    SKROW "Zz......kkS..........S"
    SKROW "Zz........kS.........S"
    SKROW "Zz........SSSS.......S"
    SKROW "ZkSS......kxxk.......S"
    SKROW "ZkSS.......xx........S"
    SKROW "kkSSSSSSSSkkkksS.....S"
    SKROW "kkSSkkkkkk....sS.....S"
    SKROW "kkkkkkkkkkk...sS.....S"
    SKROW "kkS...........kk.....S"
    SKROW "kkSkkkkkkkkkkkkkkkkkkk"
    SKROW "kkkkkkkkkSSSkkkkkkkkkk"
    SKROW "kkkkkkkkkSSSkkkkkkkkkk"
    SKROW "KKKKKKKKKkkkKKKKKKKKKK"
    SKROW "KKKKKKKKKKKKKKKKKKKKKK"
    SKROWS_END
    align 8
    SKBMP bs_skull_side_l, bs_skull_side_l_rows, 22, 22, bs_pal
    ; bs_skull_back (22x22): bs_skull BACK
    SKROWS bs_skull_back_rows, 22, 22
    SKROW "S....................k"
    SKROW "S....................k"
    SKROW "S....................k"
    SKROW "S.........kk.........k"
    SKROW "S.......kk..kk.......k"
    SKROW "S......k......k......k"
    SKROW "S.....k...k....k.....k"
    SKROW "S....k....k.....k....k"
    SKROW "S...k......k.....k...k"
    SKROW "S..k.......k......k..k"
    SKROW "S.k.......k........k.k"
    SKROW "S.........K..........k"
    SKROW "S....................k"
    SKROW "S....y...............k"
    SKROW "S..k.k.k.k.k.k.k.k...k"
    SKROW "S....................k"
    SKROW "kkkkkkkkkkkkkkkkkkkkkk"
    SKROW "kkkkkkkkkKKKKkkkkkkkkk"
    SKROW "kkkkkkkkkKKKKkkkkkkkkk"
    SKROW "KKKKKKKKKKKKKKKKKKKKKK"
    SKROW "KKKKKKKKKKKKKKKKKKKKKK"
    SKROW "KKKKKKKKKKKKKKKKKKKKKK"
    SKROWS_END
    align 8
    SKBMP bs_skull_back, bs_skull_back_rows, 22, 22, bs_pal
    ; bs_skull_top (22x22): bs_skull TOP
    SKROWS bs_skull_top_rows, 22, 22
    SKROW "S.........k..........k"
    SKROW "S..........k.........k"
    SKROW "S........k...........k"
    SKROW "S.........k..........k"
    SKROW "S..........k.........k"
    SKROW "S........k...........k"
    SKROW "S...kk....k.....kk...k"
    SKROW "S..k..k....k...k..k..k"
    SKROW "S.k....k.k....k....k.k"
    SKROW "S.........k..........k"
    SKROW "S..........k.........k"
    SKROW "S........k...........k"
    SKROW "S.........k..........k"
    SKROW "S..........k.........k"
    SKROW "S........k..yyyyy....k"
    SKROW "S.........k.yyyyy....k"
    SKROW "S..........k.yyy.....k"
    SKROW "S........k...........k"
    SKROW "S.........k..........k"
    SKROW "S..........k.........k"
    SKROW "S........k...........k"
    SKROW "S.........k..........k"
    SKROWS_END
    align 8
    SKBMP bs_skull_top, bs_skull_top_rows, 22, 22, bs_pal
    ; bs_jaw_front (16x5): bs_jaw FRONT
    SKROWS bs_jaw_front_rows, 16, 5
    SKROW "xSkxeexeexeexSkx"
    SKROW "xSkxSkxSkxSkxSkx"
    SKROW "kSskSskSskSskSsk"
    SKROW "kkkkkkkkkkkkkkkk"
    SKROW "KKKKKKKKKKKKKKKK"
    SKROWS_END
    align 8
    SKBMP bs_jaw_front, bs_jaw_front_rows, 16, 5, bs_pal
    ; bs_jaw_top (16x3): bs_jaw TOP
    SKROWS bs_jaw_top_rows, 16, 3
    SKROW "xxxxxxxxxxxxxxxx"
    SKROW "xxxxxxxxxxxxxxxx"
    SKROW "xSsxSsxSsxSsxSsx"
    SKROWS_END
    align 8
    SKBMP bs_jaw_top, bs_jaw_top_rows, 16, 3, bs_pal
    ; bs_jaw_side_r (3x5): bs_jaw RIGHT
    SKROWS bs_jaw_side_r_rows, 3, 5
    SKROW "xxx"
    SKROW "S.k"
    SKROW "S.k"
    SKROW "S.k"
    SKROW "KKK"
    SKROWS_END
    align 8
    SKBMP bs_jaw_side_r, bs_jaw_side_r_rows, 3, 5, bs_pal
    ; bs_jaw_side_l (3x5): bs_jaw LEFT
    SKROWS bs_jaw_side_l_rows, 3, 5
    SKROW "xxx"
    SKROW "k.S"
    SKROW "k.S"
    SKROW "k.S"
    SKROW "KKK"
    SKROWS_END
    align 8
    SKBMP bs_jaw_side_l, bs_jaw_side_l_rows, 3, 5, bs_pal
    ; bs_brow_front (20x3): bs_brow FRONT
    SKROWS bs_brow_front_rows, 20, 3
    SKROW "SSSSSSsskKKkssSSSSSS"
    SKROW "sssskkkKKKKKKkkkssss"
    SKROW "kkkKKKKKKKKKKKKKKkkk"
    SKROWS_END
    align 8
    SKBMP bs_brow_front, bs_brow_front_rows, 20, 3, bs_pal
    ; bs_crown_front (24x4): bs_crown FRONT
    SKROWS bs_crown_front_rows, 24, 4
    SKROW "GGGGGGGGGGGGGGGGGGGGGGGo"
    SKROW ".oMm.o...o...o...o..Mm.o"
    SKROW ".Gmw.G...G...G...G..mw.o"
    SKROW "OOOOOOOOOOOOOOOOOOOOOOOO"
    SKROWS_END
    align 8
    SKBMP bs_crown_front, bs_crown_front_rows, 24, 4, bs_pal
    ; bs_crown_back (24x4): bs_crown BACK
    SKROWS bs_crown_back_rows, 24, 4
    SKROW "GGGGGGGGGGGGGGGGGGGGGGGo"
    SKROW ".o..Gg...o...o...oGg.o.o"
    SKROW ".G..go...G...G...Ggo.G.o"
    SKROW "OOOOOOOOOOOOOOOOOOOOOOOO"
    SKROWS_END
    align 8
    SKBMP bs_crown_back, bs_crown_back_rows, 24, 4, bs_pal
    ; bs_crown_side (24x4): bs_crown RIGHT, bs_crown LEFT
    SKROWS bs_crown_side_rows, 24, 4
    SKROW "GGGGGGGGGGGGGGGGGGGGGGGo"
    SKROW ".o...o...o.Mmo...o...o.o"
    SKROW ".G...G...G.mwG...G...G.o"
    SKROW "OOOOOOOOOOOOOOOOOOOOOOOO"
    SKROWS_END
    align 8
    SKBMP bs_crown_side, bs_crown_side_rows, 24, 4, bs_pal
    ; bs_crown_top (24x24): bs_crown TOP
    SKROWS bs_crown_top_rows, 24, 24
    SKROW "GgGGGGGGGGGGGGGGGGGGGGgo"
    SKROW "Gggggggggggggggggggggggo"
    SKROW "GgrrrrrrrrrrrrrrrrrrrCgo"
    SKROW "GgrccccccccccccccccccCgo"
    SKROW "GgrccccccccccccccccccCgo"
    SKROW "GgrccccccccccccccccccCgo"
    SKROW "GgrcccrccccccccccrcccCgo"
    SKROW "GgrccccccccccccccccccCgo"
    SKROW "GgrccccccccccccccccccCgo"
    SKROW "GgrccccccrccccrccccccCgo"
    SKROW "GgrccccccccccccccccccCgo"
    SKROW "GgrccccccccCCccccccccCgo"
    SKROW "GgrccccccccrrccccccccCgo"
    SKROW "GgrccccccccccccccccccCgo"
    SKROW "GgrccccccccccccccccccCgo"
    SKROW "GgrcccccrccccccrcccccCgo"
    SKROW "GgrccccccccccccccccccCgo"
    SKROW "GgrcccCccccccccccCcccCgo"
    SKROW "GgrccrccccccccccccrccCgo"
    SKROW "GgrccccccccccccccccccCgo"
    SKROW "GgrccccccccccccccccccCgo"
    SKROW "GgrCCCCCCCCCCCCCCCCCCCgo"
    SKROW "gggggggggggggggggggggggo"
    SKROW "oooooooooooooooooooooogo"
    SKROWS_END
    align 8
    SKBMP bs_crown_top, bs_crown_top_rows, 24, 24, bs_pal
    ; bs_gem_front (4x3): bs_gem FRONT
    SKROWS bs_gem_front_rows, 4, 3
    SKROW "Mmmw"
    SKROW "mmww"
    SKROW "wwWW"
    SKROWS_END
    align 8
    SKBMP bs_gem_front, bs_gem_front_rows, 4, 3, bs_pal
    ; bs_spike_side (5x4): bs_spike_a FRONT, bs_spike_a BACK, bs_spike_a RIGHT, bs_spike_a LEFT
    SKROWS bs_spike_side_rows, 5, 4
    SKROW "__G__"
    SKROW "_GGg_"
    SKROW "_Ggo_"
    SKROW "GGgoo"
    SKROWS_END
    align 8
    SKBMP bs_spike_side, bs_spike_side_rows, 5, 4, bs_pal
    ; bs_spike_top (5x5): bs_spike_a TOP
    SKROWS bs_spike_top_rows, 5, 5
    SKROW "_____"
    SKROW "_____"
    SKROW "__G__"
    SKROW "_____"
    SKROW "_____"
    SKROWS_END
    align 8
    SKBMP bs_spike_top, bs_spike_top_rows, 5, 5, bs_pal
    ; bs_spike_bottom (5x5): bs_spike_a BOTTOM
    SKROWS bs_spike_bottom_rows, 5, 5
    SKROW "OOOOO"
    SKROW "OOOOO"
    SKROW "OOOOO"
    SKROW "OOOOO"
    SKROW "OOOOO"
    SKROWS_END
    align 8
    SKBMP bs_spike_bottom, bs_spike_bottom_rows, 5, 5, bs_pal
    ; bs_femur_front (6x20): bs_femur_l FRONT
    SKROWS bs_femur_front_rows, 6, 20
    SKROW "SSSSSS"
    SKROW "S.S.kk"
    SKROW "S.S..k"
    SKROW "S.k..k"
    SKROW "S.kk.k"
    SKROW "S.S..k"
    SKROW "S....k"
    SKROW "S.S.kk"
    SKROW "S.S..k"
    SKROW "S.S.kk"
    SKROW "S.S..k"
    SKROW "S.S.kK"
    SKROW "S....k"
    SKROW "S.S.kk"
    SKROW "yyS..k"
    SKROW "S.S.kk"
    SKROW "S.S..k"
    SKROW "S.S..k"
    SKROW "S....k"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP bs_femur_front, bs_femur_front_rows, 6, 20, bs_pal
    ; bs_femur_back (6x20): bs_femur_l BACK
    SKROWS bs_femur_back_rows, 6, 20
    SKROW "SSSSSS"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "Skyy.k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "Sk...k"
    SKROW "S..k.k"
    SKROW "S....k"
    SKROW "S..k.k"
    SKROW "S.k.kk"
    SKROW "S..k.k"
    SKROW "Sk..kk"
    SKROW "S...Kk"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP bs_femur_back, bs_femur_back_rows, 6, 20, bs_pal
    ; bs_femur_side (6x20): bs_femur_l RIGHT, bs_femur_l LEFT
    SKROWS bs_femur_side_rows, 6, 20
    SKROW "SSSSSS"
    SKROW "S.S..k"
    SKROW "S.S..k"
    SKROW "S.S.kk"
    SKROW "S.S..k"
    SKROW "S.S..k"
    SKROW "S....k"
    SKROW "S.k..k"
    SKROW "S.S..k"
    SKROW "S.Sykk"
    SKROW "S.S..k"
    SKROW "S.S.kk"
    SKROW "S.k..k"
    SKROW "S.S.kK"
    SKROW "S.S..k"
    SKROW "S.S..k"
    SKROW "SkS..k"
    SKROW "S.S..k"
    SKROW "S.kk.k"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP bs_femur_side, bs_femur_side_rows, 6, 20, bs_pal
    ; bs_knee_front (8x8): bs_knee_l FRONT
    SKROWS bs_knee_front_rows, 8, 8
    SKROW "S......k"
    SKROW "SIGGGGik"
    SKROW "SGggggok"
    SKROW "SGgGGgok"
    SKROW "SGggogok"
    SKROW "SGggggok"
    SKROW "Sioooojk"
    SKROW "S......k"
    SKROWS_END
    align 8
    SKBMP bs_knee_front, bs_knee_front_rows, 8, 8, bs_pal
    ; bs_knee_side_r (8x8): bs_knee_l RIGHT
    SKROWS bs_knee_side_r_rows, 8, 8
    SKROW "SSSSSSSk"
    SKROW "S.....go"
    SKROW "S.....go"
    SKROW "S.....go"
    SKROW "S.....go"
    SKROW "S.....go"
    SKROW "S.....go"
    SKROW "Skkkkkkk"
    SKROWS_END
    align 8
    SKBMP bs_knee_side_r, bs_knee_side_r_rows, 8, 8, bs_pal
    ; bs_knee_side_l (8x8): bs_knee_l LEFT
    SKROWS bs_knee_side_l_rows, 8, 8
    SKROW "kSSSSSSS"
    SKROW "og.....S"
    SKROW "og.....S"
    SKROW "og.....S"
    SKROW "og.....S"
    SKROW "og.....S"
    SKROW "og.....S"
    SKROW "kkkkkkkS"
    SKROWS_END
    align 8
    SKBMP bs_knee_side_l, bs_knee_side_l_rows, 8, 8, bs_pal
    ; bs_shin_front (6x12): bs_shin_l FRONT
    SKROWS bs_shin_front_rows, 6, 12
    SKROW "SSSSSS"
    SKROW "SkS..k"
    SKROW "S.k..k"
    SKROW "SkS.kk"
    SKROW "S.S..k"
    SKROW "S.K..k"
    SKROW "S....k"
    SKROW "SkSyyk"
    SKROW "S.S..k"
    SKROW "S.S..k"
    SKROW "S.S..k"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP bs_shin_front, bs_shin_front_rows, 6, 12, bs_pal
    ; bs_shin_back (6x12): bs_shin_l BACK
    SKROWS bs_shin_back_rows, 6, 12
    SKROW "SSSSSS"
    SKROW "S.k..k"
    SKROW "S..k.k"
    SKROW "S.k..k"
    SKROW "S..k.k"
    SKROW "S..K.k"
    SKROW "S..k.k"
    SKROW "S....k"
    SKROW "Sk...k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP bs_shin_back, bs_shin_back_rows, 6, 12, bs_pal
    ; bs_shin_side (6x12): bs_shin_l RIGHT, bs_shin_l LEFT
    SKROWS bs_shin_side_rows, 6, 12
    SKROW "SSSSSS"
    SKROW "S..k.k"
    SKROW "S..S.k"
    SKROW "Sk.Skk"
    SKROW "S..S.k"
    SKROW "yy.Skk"
    SKROW "S....k"
    SKROW "S..S.K"
    SKROW "Sk.S.k"
    SKROW "S..S.k"
    SKROW "S..S.k"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP bs_shin_side, bs_shin_side_rows, 6, 12, bs_pal
    ; bs_foot_front (8x4): bs_foot_l FRONT
    SKROWS bs_foot_front_rows, 8, 4
    SKROW "SsSsSsSs"
    SKROW "sYsksksY"
    SKROW "kkkkkkkk"
    SKROW "KKKKKKKK"
    SKROWS_END
    align 8
    SKBMP bs_foot_front, bs_foot_front_rows, 8, 4, bs_pal
    ; bs_foot_top (8x12): bs_foot_l TOP
    SKROWS bs_foot_top_rows, 8, 12
    SKROW "S......."
    SKROW "S......."
    SKROW "S......."
    SKROW "S......."
    SKROW "S......."
    SKROW "kkkkkkkk"
    SKROW "SkSkSkSk"
    SKROW "SkSkSkSk"
    SKROW "SkSkSkSk"
    SKROW "kkkkkkkk"
    SKROW "SkSkSkSk"
    SKROW "YyYyYyYy"
    SKROWS_END
    align 8
    SKBMP bs_foot_top, bs_foot_top_rows, 8, 12, bs_pal
    ; bs_foot_side_r (12x4): bs_foot_l RIGHT
    SKROWS bs_foot_side_r_rows, 12, 4
    SKROW "...k...k...."
    SKROW "........kkkk"
    SKROW "............"
    SKROW "KKKKKKKKKKKK"
    SKROWS_END
    align 8
    SKBMP bs_foot_side_r, bs_foot_side_r_rows, 12, 4, bs_pal
    ; bs_foot_side_l (12x4): bs_foot_l LEFT
    SKROWS bs_foot_side_l_rows, 12, 4
    SKROW "....k...k..."
    SKROW "kkkk........"
    SKROW "............"
    SKROW "KKKKKKKKKKKK"
    SKROWS_END
    align 8
    SKBMP bs_foot_side_l, bs_foot_side_l_rows, 12, 4, bs_pal
    ; bs_foot_sole (8x12): bs_foot_l BOTTOM
    SKROWS bs_foot_sole_rows, 8, 12
    SKROW "........"
    SKROW "........"
    SKROW ".kkkkkk."
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW ".kkkkkk."
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW ".kkkkkk."
    SKROW "........"
    SKROWS_END
    align 8
    SKBMP bs_foot_sole, bs_foot_sole_rows, 8, 12, bs_pal
    ; bs_wrap_front (8x9): bs_wrap_l FRONT
    SKROWS bs_wrap_front_rows, 8, 9
    SKROW "gggggggg"
    SKROW "oooooooo"
    SKROW "C.r.Rr.."
    SKROW "C.rR_R.."
    SKROW "C.rR_R.."
    SKROW "C.rR_R.."
    SKROW "R.RRRr.."
    SKROW "_R___R.R"
    SKROW "______R_"
    SKROWS_END
    align 8
    SKBMP bs_wrap_front, bs_wrap_front_rows, 8, 9, bs_pal
    ; bs_wrap_back (8x9): bs_wrap_l BACK
    SKROWS bs_wrap_back_rows, 8, 9
    SKROW "gggggggg"
    SKROW "oooooooo"
    SKROW "C.r.Rr.."
    SKROW "C.rR_R.."
    SKROW "C.rR_R.."
    SKROW "C.rR_R.."
    SKROW "RRRRRRR."
    SKROW "_______R"
    SKROW "________"
    SKROWS_END
    align 8
    SKBMP bs_wrap_back, bs_wrap_back_rows, 8, 9, bs_pal
    ; bs_wrap_side (8x9): bs_wrap_l RIGHT, bs_wrap_l LEFT
    SKROWS bs_wrap_side_rows, 8, 9
    SKROW "gggggggg"
    SKROW "oooooooo"
    SKROW "C.r.Rr.."
    SKROW "C.rR_R.."
    SKROW "C.rR_R.."
    SKROW "C.rR_R.."
    SKROW "C.r.Rr.."
    SKROW "RRRRR.RR"
    SKROW "_____R__"
    SKROWS_END
    align 8
    SKBMP bs_wrap_side, bs_wrap_side_rows, 8, 9, bs_pal
    ; bs_pauld_front (10x6): bs_pauld_l FRONT
    SKROWS bs_pauld_front_rows, 10, 6
    SKROW "F.F......u"
    SKROW "F.t.....tF"
    SKROW "F.T.....TF"
    SKROW "F......Fuu"
    SKROW "u....T.uuu"
    SKROW "uuuuuuuuuu"
    SKROWS_END
    align 8
    SKBMP bs_pauld_front, bs_pauld_front_rows, 10, 6, bs_pal
    ; bs_pauld_back (10x6): bs_pauld_l BACK
    SKROWS bs_pauld_back_rows, 10, 6
    SKROW "F..F.....u"
    SKROW "F.tF.F..tu"
    SKROW "F.T..F.FTu"
    SKROW "F....F.F.u"
    SKROW "F....T.F.u"
    SKROW "uuuuuuuuuu"
    SKROWS_END
    align 8
    SKBMP bs_pauld_back, bs_pauld_back_rows, 10, 6, bs_pal
    ; bs_pauld_right (12x6): bs_pauld_l RIGHT
    SKROWS bs_pauld_right_rows, 12, 6
    SKROW "F..........u"
    SKROW "F.t.F...t.Fu"
    SKROW "F.T.F...T.Fu"
    SKROW "F.F.u......u"
    SKROW "F...uT....uu"
    SKROW "uuuuuuuuuuuu"
    SKROWS_END
    align 8
    SKBMP bs_pauld_right, bs_pauld_right_rows, 12, 6, bs_pal
    ; bs_pauld_left (12x6): bs_pauld_l LEFT
    SKROWS bs_pauld_left_rows, 12, 6
    SKROW "F.........Fu"
    SKROW "F.t.....t.Fu"
    SKROW "FFT.Fu..T..u"
    SKROW "FF..Fu..F.Fu"
    SKROW "FF...T....Fu"
    SKROW "uuuuuuuuuuuu"
    SKROWS_END
    align 8
    SKBMP bs_pauld_left, bs_pauld_left_rows, 12, 6, bs_pal
    ; bs_pauld_top (10x12): bs_pauld_l TOP
    SKROWS bs_pauld_top_rows, 10, 12
    SKROW "...F......"
    SKROW "..tF....t."
    SKROW "u.T.....T."
    SKROW "F..u.F...."
    SKROW "F..u.T...."
    SKROW "F.F.Gg...."
    SKROW "..F.go.uF."
    SKROW ".uT.Fu.uT."
    SKROW ".u...u...."
    SKROW "..u....F.."
    SKROW "..u..T.F.."
    SKROW ".........."
    SKROWS_END
    align 8
    SKBMP bs_pauld_top, bs_pauld_top_rows, 10, 12, bs_pal
    ; bs_sleeve_front (10x14): bs_sleeve_l FRONT
    SKROWS bs_sleeve_front_rows, 10, 14
    SKROW "PPPPPPPPPP"
    SKROW "..q...q..."
    SKROW "..qQQ.q..."
    SKROW "..Q__Qq..."
    SKROW "..qQ__Q..."
    SKROW "..q.Q__Q.."
    SKROW "..q..Q__Q."
    SKROW "..q...QQ.."
    SKROW "..q...q..."
    SKROW "gggggggggg"
    SKROW "oooooooooo"
    SKROW "QQQQQ....."
    SKROW "_____QQQQQ"
    SKROW "__________"
    SKROWS_END
    align 8
    SKBMP bs_sleeve_front, bs_sleeve_front_rows, 10, 14, bs_pal
    ; bs_sleeve_back (10x14): bs_sleeve_l BACK
    SKROWS bs_sleeve_back_rows, 10, 14
    SKROW "PPPPPPPPPP"
    SKROW "..q...q..."
    SKROW "..q...q..."
    SKROW "..q...q..."
    SKROW "..q...q..."
    SKROW "..q...q..."
    SKROW "..q...q..."
    SKROW "..q...q..."
    SKROW "..q...q..."
    SKROW "gggggggggg"
    SKROW "oooooooooo"
    SKROW "QQ..QQQ..Q"
    SKROW "__QQ___QQ_"
    SKROW "__________"
    SKROWS_END
    align 8
    SKBMP bs_sleeve_back, bs_sleeve_back_rows, 10, 14, bs_pal
    ; bs_sleeve_side (10x14): bs_sleeve_l RIGHT, bs_sleeve_l LEFT
    SKROWS bs_sleeve_side_rows, 10, 14
    SKROW "PPPPPPPPPP"
    SKROW "..q...q..."
    SKROW "..q...q..."
    SKROW "..q...q..."
    SKROW "..q...q..."
    SKROW "..q...q..."
    SKROW "..q...q..."
    SKROW "..q...q..."
    SKROW "..q...q..."
    SKROW "gggggggggg"
    SKROW "oooooooooo"
    SKROW "QQQ..Q.Q.."
    SKROW "___QQ_Q_Q."
    SKROW "_________Q"
    SKROWS_END
    align 8
    SKBMP bs_sleeve_side, bs_sleeve_side_rows, 10, 14, bs_pal
    ; bs_arm_front (6x25): bs_arm_l FRONT
    SKROWS bs_arm_front_rows, 6, 25
    SKROW "SSSSSS"
    SKROW "S.S..k"
    SKROW "S.S..k"
    SKROW "S.S..k"
    SKROW "S.S..k"
    SKROW "S.S..k"
    SKROW "S....k"
    SKROW "S.S..k"
    SKROW "S.k..k"
    SKROW "S.S..k"
    SKROW "S.S..k"
    SKROW "S.S..k"
    SKROW "S....k"
    SKROW "S.Sk.k"
    SKROW "S.S..k"
    SKROW "S.S..k"
    SKROW "S.S..k"
    SKROW "S.k..k"
    SKROW "IIIIII"
    SKROW "iJiiJi"
    SKROW "jjjjjj"
    SKROW "S.S..k"
    SKROW "S.S..k"
    SKROW "S.S.kk"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP bs_arm_front, bs_arm_front_rows, 6, 25, bs_pal
    ; bs_arm_back (6x25): bs_arm_l BACK
    SKROWS bs_arm_back_rows, 6, 25
    SKROW "SSSSSS"
    SKROW "S....k"
    SKROW "Sk.kkk"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S.k.kk"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S...kk"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S..k.k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "IIIIII"
    SKROW "iJiiJi"
    SKROW "jjjjjj"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "S....k"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP bs_arm_back, bs_arm_back_rows, 6, 25, bs_pal
    ; bs_arm_side (6x25): bs_arm_l RIGHT, bs_arm_l LEFT
    SKROWS bs_arm_side_rows, 6, 25
    SKROW "SSSSSS"
    SKROW "S.S..k"
    SKROW "SkS..k"
    SKROW "S.S..k"
    SKROW "S.S..k"
    SKROW "S.S..k"
    SKROW "Sk...k"
    SKROW "S.S..k"
    SKROW "S.S..k"
    SKROW "S.k..k"
    SKROW "S.S..k"
    SKROW "S.S..k"
    SKROW "S.k..k"
    SKROW "S.S..k"
    SKROW "S.S..k"
    SKROW "S.kk.k"
    SKROW "S.S..k"
    SKROW "S.S..k"
    SKROW "IIIIII"
    SKROW "iJiiJi"
    SKROW "jjjjjj"
    SKROW "S.S..k"
    SKROW "S.S..k"
    SKROW "S.S.kk"
    SKROW "kkkkkk"
    SKROWS_END
    align 8
    SKBMP bs_arm_side, bs_arm_side_rows, 6, 25, bs_pal
    ; bs_palm_front (8x5): bs_palm_l FRONT
    SKROWS bs_palm_front_rows, 8, 5
    SKROW "SSSSSSSS"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "kkkkkkkk"
    SKROWS_END
    align 8
    SKBMP bs_palm_front, bs_palm_front_rows, 8, 5, bs_pal
    ; bs_palm_back (8x5): bs_palm_l BACK
    SKROWS bs_palm_back_rows, 8, 5
    SKROW "SSSSSSSS"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "kkkkkkkk"
    SKROWS_END
    align 8
    SKBMP bs_palm_back, bs_palm_back_rows, 8, 5, bs_pal
    ; bs_palm_side (4x5): bs_palm_l RIGHT, bs_palm_l LEFT
    SKROWS bs_palm_side_rows, 4, 5
    SKROW "Skkk"
    SKROW "Skkk"
    SKROW "Skkk"
    SKROW "Skkk"
    SKROW "KKKK"
    SKROWS_END
    align 8
    SKBMP bs_palm_side, bs_palm_side_rows, 4, 5, bs_pal
    ; bs_finger_front (2x6): bs_finger_a FRONT, bs_finger_a BACK, bs_finger_a RIGHT, bs_finger_a LEFT
    SKROWS bs_finger_front_rows, 2, 6
    SKROW "Sk"
    SKROW "Sk"
    SKROW "kk"
    SKROW "Sk"
    SKROW "kk"
    SKROW "Yy"
    SKROWS_END
    align 8
    SKBMP bs_finger_front, bs_finger_front_rows, 2, 6, bs_pal
    ; bs_thumb_front (2x4): bs_thumb_l FRONT
    SKROWS bs_thumb_front_rows, 2, 4
    SKROW "Sk"
    SKROW "Sk"
    SKROW "kk"
    SKROW "Sy"
    SKROWS_END
    align 8
    SKBMP bs_thumb_front, bs_thumb_front_rows, 2, 4, bs_pal
    ; bs_curl_front (8x4): bs_curl_r FRONT
    SKROWS bs_curl_front_rows, 8, 4
    SKROW "SsSsSsSs"
    SKROW "sksksksk"
    SKROW "kkkkkkkk"
    SKROW "KKKKKKKK"
    SKROWS_END
    align 8
    SKBMP bs_curl_front, bs_curl_front_rows, 8, 4, bs_pal
    ; bs_curl_top (8x3): bs_curl_r TOP
    SKROWS bs_curl_top_rows, 8, 3
    SKROW "SkSkSkSk"
    SKROW "........"
    SKROW "........"
    SKROWS_END
    align 8
    SKBMP bs_curl_top, bs_curl_top_rows, 8, 3, bs_pal

section .data
SKMODEL_BEGIN m_boss, 32, KINGS_BLADE, 18, 45, -3
    SKBONE BK_BODY, 0, 0, 0.00
    PART bs_belt, -15, 51, -9, 30, 5, 19, 0, 0              ; crimson sash
    PART bs_pendant, -2, 65, -7, 4, 4, 1, 0, 0              ; ruby pendant on the ribs
    PART bs_collar, -15, 71, -10, 30, 7, 20, 0, SKPF_CUTOUT ; ermine collar, tufted lower edge
    PART bs_core, -9, 44, -5, 18, 32, 10, 0, 0              ; ribcage and spine, seen through the open chest
    PART bs_robe, -14, 35, -8, 28, 42, 16, 0, SKPF_CUTOUT   ; ragged purple robe: chest opening, trims, tatters
    PART bs_cape, -13, 33, 8, 26, 44, 1, 0, SKPF_CUTOUT     ; crimson cape, gold crown sigil, ragged hem
    PART bs_buckle, -4, 50, -11, 8, 7, 2, 0, 0              ; gold buckle with a ruby
    SKBONE BK_LLEG, 42, 0, 1.00
    PART bs_femur_l, -10, 22, -3, 6, 20, 6, 0, 0            ; thigh bone
    PART bs_shin_l, -10, 4, -3, 6, 12, 6, 0, 0              ; shin bone
    PART bs_wrap_l, -11, 6, -4, 8, 9, 8, 0, SKPF_CUTOUT     ; torn cloth wrap
    PART bs_knee_l, -11, 16, -4, 8, 8, 8, 0, 0              ; kneecap with a gilded plate
    PART bs_foot_l, -11, 0, -9, 8, 4, 12, 0, 0              ; bony foot, toes
    SKBONE BK_LARM, 74, 0, -0.50
    PART bs_finger_a, -22, 39, -1, 2, 6, 2, 0, 0            ; claw fingers
    PART bs_sleeve_l, -23, 59, -5, 10, 14, 10, 0, SKPF_CUTOUT ; torn purple sleeve, gold cuff
    PART bs_thumb_l, -16, 46, -5, 2, 4, 3, 0, 0             ; thumb
    PART bs_palm_l, -22, 45, -2, 8, 5, 4, 0, 0              ; bony hand
    PART bs_pauld_l, -23, 73, -6, 10, 6, 12, 0, 0           ; ermine shoulder mantle with a gold stud
    PART_AS bs_finger_b, bs_finger_a, -19, 39, -1, 0, 0
    PART_AS bs_finger_c, bs_finger_a, -16, 39, -1, 0, 0
    PART bs_arm_l, -21, 50, -3, 6, 25, 6, 0, 0              ; arm bone, an iron manacle at the wrist
    SKBONE BK_RARM, 74, 0, 0.50
    PART_AS bs_pauld_r, bs_pauld_l, 13, 73, -6, 0, 0
    PART_AS bs_sleeve_r, bs_sleeve_l, 13, 59, -5, 0, SKPF_CUTOUT
    PART_AS bs_thumb_r, bs_thumb_l, 14, 46, -5, 0, 0
    PART_AS bs_palm_r, bs_palm_l, 14, 45, -2, 0, 0
    PART_AS bs_arm_r, bs_arm_l, 15, 50, -3, 0, 0
    PART bs_curl_r, 14, 41, -5, 8, 4, 3, 0, 0               ; curled fingers: the fist that holds the blade
    SKBONE BK_RLEG, 42, 0, -1.00
    PART_AS bs_foot_r, bs_foot_l, 3, 0, -9, 0, 0
    PART_AS bs_shin_r, bs_shin_l, 4, 4, -3, 0, 0
    PART_AS bs_wrap_r, bs_wrap_l, 3, 6, -4, 0, SKPF_CUTOUT
    PART_AS bs_knee_r, bs_knee_l, 3, 16, -4, 0, 0
    PART_AS bs_femur_r, bs_femur_l, 4, 22, -3, 0, 0
    SKBONE BK_HEAD, 0, 0, 0.00
    PART bs_skull, -11, 77, -11, 22, 22, 22, 0, 0           ; bleached skull: sockets with glowing eyes, nose, cracks
    PART bs_spike_a, -12, 103, -12, 5, 4, 5, 0, SKPF_CUTOUT ; crown spike (front left corner)
    PART_AS bs_spike_f, bs_spike_a, -12, 103, 7, 0, SKPF_CUTOUT
    PART_AS bs_spike_d, bs_spike_a, -12, 103, -2, 0, SKPF_CUTOUT
    PART_AS bs_spike_c, bs_spike_a, 7, 103, -12, 0, SKPF_CUTOUT
    PART_AS bs_spike_g, bs_spike_a, -2, 103, 7, 0, SKPF_CUTOUT
    PART bs_crown, -12, 99, -12, 24, 4, 24, 0, 0            ; gold crown band with rubies, a velvet top
    PART_AS bs_spike_b, bs_spike_a, -2, 103, -12, 0, SKPF_CUTOUT
    PART_AS bs_spike_e, bs_spike_a, 7, 103, -2, 0, SKPF_CUTOUT
    PART_AS bs_spike_h, bs_spike_a, 7, 103, 7, 0, SKPF_CUTOUT
    PART bs_gem, -2, 100, -13, 4, 3, 1, 0, 0                ; front ruby
    PART bs_jaw, -8, 77, -14, 16, 4, 3, 0, 0                ; jutting lower jaw with fangs
    PART bs_brow, -10, 92, -13, 20, 3, 2, 0, 0              ; heavy angry brow ridge
SKMODEL_PAINT
    ; --- bs_core: the ribcage and spine behind the robe: a hollow chest with a few dim embers
    SK_FILL bs_core, SKM_ALL, BS_BONE_2, 15
    SK_GRAD bs_core, SKM_SIDES, 272, 224
    SK_BMP bs_core, SKF_FRONT, 0, 0, bs_core_front
    SK_BMP bs_core, SKF_BACK, 0, 0, bs_core_back
    SK_BMP bs_core, SKF_RIGHT, 0, 0, bs_core_side
    SK_BMP bs_core, SKF_LEFT, 0, 0, bs_core_side
    SK_RECT bs_core, SKF_TOP, 0, 0, 18, 10, BS_BONE_1, 15
    SK_RECT bs_core, SKF_BOTTOM, 0, 0, 18, 10, BS_BONE_4, 0
    ; --- bs_robe: royal purple, cutout: an open chest with ermine edges and a gold V, a crimson and gold panel,
    ;     folds, patches, moth holes, a gold hem band and ragged tatters
    SK_FILL bs_robe, SKM_ALL, BS_ROBE_2, 15
    SK_GRAD bs_robe, SKM_SIDES, 272, 200
    SK_BMP bs_robe, SKF_FRONT, 0, 0, bs_robe_front
    SK_BMP bs_robe, SKF_BACK, 0, 0, bs_robe_back
    SK_BMP bs_robe, SKF_RIGHT, 0, 0, bs_robe_side_r
    SK_BMP bs_robe, SKF_LEFT, 0, 0, bs_robe_side_l
    SK_RECT bs_robe, SKF_TOP, 0, 0, 28, 16, BS_ROBE_1, 0
    SK_RECT bs_robe, SKF_BOTTOM, 0, 0, 28, 16, BS_ROBE_4, 0
    ; --- bs_belt: a crimson sash with gold edges and stitching; bs_buckle: a gold plate with a ruby; bs_pendant
    SK_FILL bs_belt, SKM_ALL, BS_CRIM_2, 15
    SK_GRAD bs_belt, SKM_SIDES, 272, 224
    SK_BMP bs_belt, SKF_FRONT, 0, 0, bs_belt_front
    SK_BMP bs_belt, SKF_BACK, 0, 0, bs_belt_back
    SK_BMP bs_belt, SKF_RIGHT, 0, 0, bs_belt_side
    SK_BMP bs_belt, SKF_LEFT, 0, 0, bs_belt_side
    SK_RECT bs_belt, SKF_TOP, 0, 0, 30, 19, BS_CRIM_1, 15
    SK_RECT bs_belt, SKF_BOTTOM, 0, 0, 30, 19, BS_CRIM_4, 0
    SK_FILL bs_buckle, SKM_ALL, AC_GOLD_2, 0
    SK_BMP bs_buckle, SKF_FRONT, 0, 0, bs_buckle_front
    SK_RECT bs_buckle, SKF_BACK, 0, 0, 8, 7, AC_GOLD_4, 0
    SK_RECT bs_buckle, SKF_TOP, 0, 0, 8, 2, AC_GOLD_1, 0
    SK_RECT bs_buckle, SKF_BOTTOM, 0, 0, 8, 2, AC_GOLD_4, 0
    SK_FILL bs_pendant, SKM_ALL, AC_GOLD_2, 0
    SK_BMP bs_pendant, SKF_FRONT, 0, 0, bs_pendant_front
    ; --- bs_collar: ermine fur with black tail spots, cutout: tufts along the lower edge
    SK_FILL bs_collar, SKM_ALL, BS_FUR_2, 23
    SK_GRAD bs_collar, SKM_SIDES, 264, 232
    SK_BMP bs_collar, SKF_FRONT, 0, 0, bs_collar_front
    SK_BMP bs_collar, SKF_BACK, 0, 0, bs_collar_back
    SK_BMP bs_collar, SKF_RIGHT, 0, 0, bs_collar_side_r
    SK_BMP bs_collar, SKF_LEFT, 0, 0, bs_collar_side_l
    SK_BMP bs_collar, SKF_TOP, 0, 0, bs_collar_top
    SK_RECT bs_collar, SKF_BOTTOM, 0, 0, 30, 20, BS_FUR_4, 15
    ; --- bs_cape: crimson, cutout: a gold crown sigil with a crack, folds, a gold hem line and tatters; a dark lining
    SK_FILL bs_cape, SKM_ALL, BS_CRIM_2, 15
    SK_GRAD bs_cape, SKM_SIDES, 272, 204
    SK_BMP bs_cape, SKF_BACK, 0, 0, bs_cape_back
    SK_BMP bs_cape, SKF_FRONT, 0, 0, bs_cape_front
    SK_BMP bs_cape, SKF_RIGHT, 0, 0, bs_cape_side
    SK_BMP bs_cape, SKF_LEFT, 0, 0, bs_cape_side
    SK_RECT bs_cape, SKF_TOP, 0, 0, 26, 1, AC_GOLD_3, 0
    SK_RECT bs_cape, SKF_BOTTOM, 0, 0, 26, 1, BS_CRIM_4, 0
    ; --- bs_skull: bleached bone; sockets with glowing eyes, a nose, fangs, cracks and stains
    SK_FILL bs_skull, SKM_ALL, BS_BONE_2, 15
    SK_GRAD bs_skull, SKM_SIDES, 272, 224
    SK_BMP bs_skull, SKF_FRONT, 0, 0, bs_skull_front
    SK_BMP bs_skull, SKF_RIGHT, 0, 0, bs_skull_side_r
    SK_BMP bs_skull, SKF_LEFT, 0, 0, bs_skull_side_l
    SK_BMP bs_skull, SKF_BACK, 0, 0, bs_skull_back
    SK_BMP bs_skull, SKF_TOP, 0, 0, bs_skull_top
    SK_RECT bs_skull, SKF_BOTTOM, 0, 0, 22, 22, BS_BONE_4, 0
    ; --- bs_jaw: the jutting lower jaw: fangs pointing up, a dark gum line, a chin
    SK_FILL bs_jaw, SKM_ALL, BS_BONE_2, 15
    SK_GRAD bs_jaw, SKM_SIDES, 272, 224
    SK_BMP bs_jaw, SKF_FRONT, 0, 0, bs_jaw_front
    SK_BMP bs_jaw, SKF_TOP, 0, 0, bs_jaw_top
    SK_RECT bs_jaw, SKF_BOTTOM, 0, 0, 16, 3, BS_BONE_3, 0
    SK_RECT bs_jaw, SKF_BACK, 0, 0, 16, 5, BS_BONE_4, 0
    SK_BMP bs_jaw, SKF_RIGHT, 0, 0, bs_jaw_side_r
    SK_BMP bs_jaw, SKF_LEFT, 0, 0, bs_jaw_side_l
    ; --- bs_brow: a heavy ridge, darker towards the nose so the eyes look angry
    SK_FILL bs_brow, SKM_ALL, BS_BONE_2, 15
    SK_GRAD bs_brow, SKM_SIDES, 272, 224
    SK_BMP bs_brow, SKF_FRONT, 0, 0, bs_brow_front
    SK_RECT bs_brow, SKF_TOP, 0, 0, 20, 2, BS_BONE_1, 15
    SK_RECT bs_brow, SKF_BOTTOM, 0, 0, 20, 2, BS_BONE_4, 0
    SK_RECT bs_brow, SKF_BACK, 0, 0, 20, 3, BS_BONE_3, 0
    ; --- bs_crown: gold band with engraved chevrons and rubies; the top is a crimson velvet cushion in a gold rim
    SK_FILL bs_crown, SKM_ALL, AC_GOLD_2, 0
    SK_GRAD bs_crown, SKM_SIDES, 272, 224
    SK_BMP bs_crown, SKF_FRONT, 0, 0, bs_crown_front
    SK_BMP bs_crown, SKF_BACK, 0, 0, bs_crown_back
    SK_BMP bs_crown, SKF_RIGHT, 0, 0, bs_crown_side
    SK_BMP bs_crown, SKF_LEFT, 0, 0, bs_crown_side
    SK_BMP bs_crown, SKF_TOP, 0, 0, bs_crown_top
    SK_RECT bs_crown, SKF_BOTTOM, 0, 0, 24, 24, AC_GOLD_4, 0
    ; --- bs_gem: the front ruby
    SK_FILL bs_gem, SKM_ALL, RGBO(214, 28, 52), 0
    SK_BMP bs_gem, SKF_FRONT, 0, 0, bs_gem_front
    SK_RECT bs_gem, SKF_TOP, 0, 0, 4, 1, RGBO(255, 160, 170), 0
    ; --- bs_spike_a (shared by the eight spikes): a stepped point; transparent corners
    SK_FILL bs_spike_a, SKM_ALL, AC_GOLD_2, 0
    SK_BMP bs_spike_a, SKF_FRONT, 0, 0, bs_spike_side
    SK_BMP bs_spike_a, SKF_BACK, 0, 0, bs_spike_side
    SK_BMP bs_spike_a, SKF_RIGHT, 0, 0, bs_spike_side
    SK_BMP bs_spike_a, SKF_LEFT, 0, 0, bs_spike_side
    SK_BMP bs_spike_a, SKF_TOP, 0, 0, bs_spike_top
    SK_BMP bs_spike_a, SKF_BOTTOM, 0, 0, bs_spike_bottom
    ; --- legs (the right leg shares these skins): bone shafts, a gilded kneecap, a bony foot with toes,
    ;     a torn crimson wrap
    SK_FILL bs_femur_l, SKM_ALL, BS_BONE_2, 15
    SK_GRAD bs_femur_l, SKM_SIDES, 272, 224
    SK_BMP bs_femur_l, SKF_FRONT, 0, 0, bs_femur_front
    SK_BMP bs_femur_l, SKF_BACK, 0, 0, bs_femur_back
    SK_BMP bs_femur_l, SKF_RIGHT, 0, 0, bs_femur_side
    SK_BMP bs_femur_l, SKF_LEFT, 0, 0, bs_femur_side
    SK_RECT bs_femur_l, SKF_TOP, 0, 0, 6, 6, BS_BONE_1, 15
    SK_RECT bs_femur_l, SKF_BOTTOM, 0, 0, 6, 6, BS_BONE_4, 0
    SK_FILL bs_knee_l, SKM_ALL, BS_BONE_2, 15
    SK_GRAD bs_knee_l, SKM_SIDES, 272, 224
    SK_BMP bs_knee_l, SKF_FRONT, 0, 0, bs_knee_front
    SK_BMP bs_knee_l, SKF_RIGHT, 0, 0, bs_knee_side_r
    SK_BMP bs_knee_l, SKF_LEFT, 0, 0, bs_knee_side_l
    SK_RECT bs_knee_l, SKF_TOP, 0, 0, 8, 8, BS_BONE_1, 15
    SK_RECT bs_knee_l, SKF_BOTTOM, 0, 0, 8, 8, BS_BONE_4, 0
    SK_RECT bs_knee_l, SKF_BACK, 0, 0, 8, 8, BS_BONE_3, 0
    SK_FILL bs_shin_l, SKM_ALL, BS_BONE_2, 15
    SK_GRAD bs_shin_l, SKM_SIDES, 272, 224
    SK_BMP bs_shin_l, SKF_FRONT, 0, 0, bs_shin_front
    SK_BMP bs_shin_l, SKF_BACK, 0, 0, bs_shin_back
    SK_BMP bs_shin_l, SKF_RIGHT, 0, 0, bs_shin_side
    SK_BMP bs_shin_l, SKF_LEFT, 0, 0, bs_shin_side
    SK_RECT bs_shin_l, SKF_TOP, 0, 0, 6, 6, BS_BONE_1, 15
    SK_RECT bs_shin_l, SKF_BOTTOM, 0, 0, 6, 6, BS_BONE_4, 0
    SK_FILL bs_foot_l, SKM_ALL, BS_BONE_2, 15
    SK_GRAD bs_foot_l, SKM_SIDES, 272, 224
    SK_BMP bs_foot_l, SKF_FRONT, 0, 0, bs_foot_front
    SK_BMP bs_foot_l, SKF_TOP, 0, 0, bs_foot_top
    SK_BMP bs_foot_l, SKF_RIGHT, 0, 0, bs_foot_side_r
    SK_BMP bs_foot_l, SKF_LEFT, 0, 0, bs_foot_side_l
    SK_RECT bs_foot_l, SKF_BOTTOM, 0, 0, 8, 12, BS_BONE_4, 0
    SK_BMP bs_foot_l, SKF_BOTTOM, 0, 0, bs_foot_sole
    SK_RECT bs_foot_l, SKF_BACK, 0, 0, 8, 4, BS_BONE_3, 0
    SK_FILL bs_wrap_l, SKM_ALL, BS_CRIM_2, 15
    SK_GRAD bs_wrap_l, SKM_SIDES, 272, 224
    SK_BMP bs_wrap_l, SKF_FRONT, 0, 0, bs_wrap_front
    SK_BMP bs_wrap_l, SKF_BACK, 0, 0, bs_wrap_back
    SK_BMP bs_wrap_l, SKF_RIGHT, 0, 0, bs_wrap_side
    SK_BMP bs_wrap_l, SKF_LEFT, 0, 0, bs_wrap_side
    SK_RECT bs_wrap_l, SKF_TOP, 0, 0, 8, 8, BS_CRIM_1, 0
    SK_RECT bs_wrap_l, SKF_BOTTOM, 0, 0, 8, 8, BS_CRIM_4, 0
    ; --- arms (the right arm shares these skins): an ermine mantle with a gold stud, a torn sleeve with a gold cuff,
    ;     the arm bone with an iron manacle, a bony hand (fingers and thumb as parts); bs_curl_r: the closed fist
    SK_FILL bs_pauld_l, SKM_ALL, BS_FUR_2, 23
    SK_GRAD bs_pauld_l, SKM_SIDES, 264, 232
    SK_BMP bs_pauld_l, SKF_FRONT, 0, 0, bs_pauld_front
    SK_BMP bs_pauld_l, SKF_BACK, 0, 0, bs_pauld_back
    SK_BMP bs_pauld_l, SKF_RIGHT, 0, 0, bs_pauld_right
    SK_BMP bs_pauld_l, SKF_LEFT, 0, 0, bs_pauld_left
    SK_BMP bs_pauld_l, SKF_TOP, 0, 0, bs_pauld_top
    SK_RECT bs_pauld_l, SKF_BOTTOM, 0, 0, 10, 12, BS_FUR_4, 15
    SK_FILL bs_sleeve_l, SKM_ALL, BS_ROBE_2, 15
    SK_GRAD bs_sleeve_l, SKM_SIDES, 272, 224
    SK_BMP bs_sleeve_l, SKF_FRONT, 0, 0, bs_sleeve_front
    SK_BMP bs_sleeve_l, SKF_BACK, 0, 0, bs_sleeve_back
    SK_BMP bs_sleeve_l, SKF_RIGHT, 0, 0, bs_sleeve_side
    SK_BMP bs_sleeve_l, SKF_LEFT, 0, 0, bs_sleeve_side
    SK_RECT bs_sleeve_l, SKF_TOP, 0, 0, 10, 10, BS_ROBE_1, 0
    SK_RECT bs_sleeve_l, SKF_BOTTOM, 0, 0, 10, 10, BS_ROBE_4, 0
    SK_FILL bs_arm_l, SKM_ALL, BS_BONE_2, 15
    SK_GRAD bs_arm_l, SKM_SIDES, 272, 224
    SK_BMP bs_arm_l, SKF_FRONT, 0, 0, bs_arm_front
    SK_BMP bs_arm_l, SKF_BACK, 0, 0, bs_arm_back
    SK_BMP bs_arm_l, SKF_RIGHT, 0, 0, bs_arm_side
    SK_BMP bs_arm_l, SKF_LEFT, 0, 0, bs_arm_side
    SK_RECT bs_arm_l, SKF_TOP, 0, 0, 6, 6, BS_BONE_1, 15
    SK_RECT bs_arm_l, SKF_BOTTOM, 0, 0, 6, 6, BS_BONE_4, 0
    SK_FILL bs_palm_l, SKM_ALL, BS_BONE_2, 15
    SK_GRAD bs_palm_l, SKM_SIDES, 272, 224
    SK_BMP bs_palm_l, SKF_FRONT, 0, 0, bs_palm_front
    SK_BMP bs_palm_l, SKF_BACK, 0, 0, bs_palm_back
    SK_BMP bs_palm_l, SKF_RIGHT, 0, 0, bs_palm_side
    SK_BMP bs_palm_l, SKF_LEFT, 0, 0, bs_palm_side
    SK_RECT bs_palm_l, SKF_TOP, 0, 0, 8, 4, BS_BONE_1, 15
    SK_RECT bs_palm_l, SKF_BOTTOM, 0, 0, 8, 4, BS_BONE_4, 0
    SK_FILL bs_finger_a, SKM_ALL, BS_BONE_2, 7
    SK_GRAD bs_finger_a, SKM_SIDES, 272, 224
    SK_BMP bs_finger_a, SKF_FRONT, 0, 0, bs_finger_front
    SK_BMP bs_finger_a, SKF_BACK, 0, 0, bs_finger_front
    SK_BMP bs_finger_a, SKF_RIGHT, 0, 0, bs_finger_front
    SK_BMP bs_finger_a, SKF_LEFT, 0, 0, bs_finger_front
    SK_RECT bs_finger_a, SKF_TOP, 0, 0, 2, 2, BS_BONE_1, 0
    SK_RECT bs_finger_a, SKF_BOTTOM, 0, 0, 2, 2, BS_BONE_4, 0
    SK_FILL bs_thumb_l, SKM_ALL, BS_BONE_2, 7
    SK_GRAD bs_thumb_l, SKM_SIDES, 272, 224
    SK_BMP bs_thumb_l, SKF_FRONT, 0, 0, bs_thumb_front
    SK_RECT bs_thumb_l, SKF_TOP, 0, 0, 2, 3, BS_BONE_1, 0
    SK_RECT bs_thumb_l, SKF_BOTTOM, 0, 0, 2, 3, BS_BONE_4, 0
    SK_FILL bs_curl_r, SKM_ALL, BS_BONE_2, 15
    SK_GRAD bs_curl_r, SKM_SIDES, 272, 224
    SK_BMP bs_curl_r, SKF_FRONT, 0, 0, bs_curl_front
    SK_BMP bs_curl_r, SKF_TOP, 0, 0, bs_curl_top
    SK_RECT bs_curl_r, SKF_BOTTOM, 0, 0, 8, 3, BS_BONE_4, 0
SKMODEL_END
