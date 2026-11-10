; skins_mobs.asm: skin models of the mobs (0.13 "looks"): zombie, skeleton, creeper, spider, pig, chicken and
; the Fallen King. Data only: bones, parts and paint ops for skin.asm (art.inc, common.inc "0.13 looks");
; nothing here runs.
;
; Holds the style samples; the other mobs follow the same structure:
;   m_zombie   arms forward, green rotting skin, sunken eyes, a torn blue shirt and ripped trousers as cutout
;              overlays, a bandaged forearm, clawed hands (prefix zb_)
;   m_pig      barrel body, head with a snout and floppy ears, a curly tail, cloven hooves (prefix pg_)
; One section per model, in file order: ramps, then palette and bitmaps (section .rodata), then the model
; (section .data), so a model reads top to bottom.
;
; Model space (texels, origin = feet centre, front = -Z). The old boxes of mobrender.asm x 32 give the sizes
; (zombie: legs 8x24x8, body 16x24x8, head 16^3, arms 8x8x24 pointing forward, arm pivot (44, 0) swinging
; -0.25 / +0.25; pig: body 20x16x32, head 16x16x12, four 8x12x8 legs pivoting at (12, +-10), swing +1 / -1 /
; -1 / +1 front left, front right, back left, back right).
;
; Local helpers (private to this file):
;   RAMP prefix, r, g, b                defines prefix_1 .. prefix_4: highlight (base x 1.2, clamped), base,
;                                       shade (x 0.75), deep (x 0.55), packed RGBO.
;   PART name, x0, y0, z0, w, h, d, grow, flags
;   PART_AS name, k, x0, y0, z0, grow, flags
;                                       SKPART / SKPART_AS; `name` becomes the part's index, so the paint ops
;                                       name parts, not numbers. Names are <model prefix>_<part>.
; Conventions, for the models that extend this file:
;   - one palette per model (<prefix>_pal) holds every character its bitmaps use; a material takes a group of
;     letters, lower case = base tone, upper case = highlight, the next two letters = shade and deep (the
;     comment above the palette lists them). '_' is a transparent texel (PALT, cutouts), '.' keeps the texel.
;   - a part's ops run: SK_FILL (grain), details, SK_GRAD on the four vertical faces (272 -> 224), then the face
;     features (eyes, glints, trims) that keep their full colour. Cutout overlays (torn cloth, hair, ears) are
;     filled like any part and then punched with '_' bitmaps; every face keeps at least one opaque texel.
;   - bitmaps have the size of the face they paint (a face image is seen from outside, upright, (0, 0) top left:
;     the unwrap table of the design doc); the light comes from the top left, so a face's left column is the lit one.
;   - left/right pairs share one skin (PART_AS); a detail that exists on one side only is a part of its own (the
;     zombie's legs have different rips, so each has its own skin).
;   - grain: noise 15 on cloth and skin, 31 on hair and bristles, 0 on trims.
;   - skin_build packs the unwraps in record order with next-fit shelves: a part costs 2(w+d) x (d+h) atlas
;     texels (a cutout overlay as much as a solid part), an AS part nothing; neighbouring parts of similar height
;     waste less. The two models here take about 140 atlas rows together (of 3072).
; Ramps (RAMP: _1 highlight, _2 base, _3 shade, _4 deep; AC_* are the shared material ramps of art.inc):
;   m_zombie           ZB_SKIN (74,128,64), ZB_SHIRT (50,120,176), ZB_PANTS (70,68,150), ZB_HAIR (58,50,36)
;   m_pig              PG_SKIN (240,160,160), PG_SNOUT (218,128,138), PG_HOOF (78,66,64)
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
; m_zombie
; ===================================================================================================
RAMP ZB_SKIN, 74, 128, 64              ; rotting green (the old zombie tile)
RAMP ZB_SHIRT, 50, 120, 176            ; torn blue shirt
RAMP ZB_PANTS, 70, 68, 150             ; ripped trousers
RAMP ZB_HAIR, 58, 50, 36               ; matted, dirty hair

section .rodata
; The characters of every zb_ bitmap. Groups: base, highlight, shade, deep.
;   s S k K green skin   r rot   R bruise   w W wound   c C teeth and bandage   b B d D shirt   p P q Q trousers
;   h H j J hair   x X eye socket   e eye glint   m mouth   n nail   _ transparent
align 8
zb_pal:
    PALC 's', ZB_SKIN_2
    PALC 'S', ZB_SKIN_1
    PALC 'k', ZB_SKIN_3
    PALC 'K', ZB_SKIN_4
    PALC 'r', RGBO(120, 152, 78)
    PALC 'R', RGBO(50, 82, 70)
    PALC 'w', RGBO(112, 30, 34)
    PALC 'W', RGBO(172, 58, 54)
    PALC 'c', RGBO(224, 216, 176)
    PALC 'C', RGBO(156, 148, 112)
    PALC 'b', ZB_SHIRT_2
    PALC 'B', ZB_SHIRT_1
    PALC 'd', ZB_SHIRT_3
    PALC 'D', ZB_SHIRT_4
    PALC 'p', ZB_PANTS_2
    PALC 'P', ZB_PANTS_1
    PALC 'q', ZB_PANTS_3
    PALC 'Q', ZB_PANTS_4
    PALC 'h', ZB_HAIR_2
    PALC 'H', ZB_HAIR_1
    PALC 'j', ZB_HAIR_3
    PALC 'J', ZB_HAIR_4
    PALC 'x', RGBO(8, 18, 12)
    PALC 'X', RGBO(24, 42, 28)
    PALC 'e', RGBO(236, 240, 124)
    PALC 'm', RGBO(44, 10, 12)
    PALC 'n', RGBO(104, 90, 54)
    PALT '_'
    dq 0

    ; zb_torso_front (16x24): zb_torso FRONT
    SKROWS zb_torso_front_rows, 16, 24
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "...........rr..."
    SKROW ".......Sk..rrr.."
    SKROW ".......Sk...r..."
    SKROW "..kkkkkSkkkkkk.."
    SKROW "..KKKKKSkKKKKK.."
    SKROW ".......Sk......."
    SKROW "..kkkkkSkkkkkk.."
    SKROW "..KKKKKSkKKKKK.."
    SKROW ".......Sk......."
    SKROW "..kkkkkSkkkkkk.."
    SKROW "..KKKKKSkKKKKK.."
    SKROW ".......Sk......."
    SKROW "...........ww..."
    SKROW "...RRRR...wWww.."
    SKROW "..RRRRR..wwWW..."
    SKROW "...RRR....www..."
    SKROW "..........ww...."
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROWS_END
    align 8
    SKBMP zb_torso_front, zb_torso_front_rows, 16, 24, zb_pal
    ; zb_torso_back (16x24): zb_torso BACK
    SKROWS zb_torso_back_rows, 16, 24
    SKROW "................"
    SKROW ".......kS......."
    SKROW ".......kS......."
    SKROW ".......KK......."
    SKROW ".......kS......."
    SKROW ".......kS......."
    SKROW "..kkkk.KK.kkkk.."
    SKROW "...KKK.kS.KKK..."
    SKROW ".......kS......."
    SKROW ".......KK......."
    SKROW "...RRR.kS......."
    SKROW "..RRRRRkS......."
    SKROW "...RRR.KK......."
    SKROW ".......kS...r..."
    SKROW ".......kS.rrrrr."
    SKROW ".......KK.rrrrr."
    SKROW ".......kS.rrrrr."
    SKROW ".......kS...rr.."
    SKROW ".......KK......."
    SKROW ".......kS......."
    SKROW ".......kS......."
    SKROW ".......KK......."
    SKROW ".......kS......."
    SKROW "................"
    SKROWS_END
    align 8
    SKBMP zb_torso_back, zb_torso_back_rows, 16, 24, zb_pal
    ; zb_shirt_front (16x24): zb_shirt FRONT
    SKROWS zb_shirt_front_rows, 16, 24
    SKROW "BBBBBBBBBBBBBBBd"
    SKROW "B....DDDDDD.DD.d"
    SKROW "B..........D__Dd"
    SKROW "B......dd.D___Dd"
    SKROW "B..DDDDdd..__D.d"
    SKROW "B.D____Dd..DD..d"
    SKROW "BD_____Dd......d"
    SKROW "B._____Dd......d"
    SKROW "BD_____Dd..ddd.d"
    SKROW "BD____Ddd......d"
    SKROW "B.DD__.dd...D..d"
    SKROW "B......dd.D__D.d"
    SKROW "B......ddD___D.d"
    SKROW "BDD....dD____D.d"
    SKROW "D__Dd..ddD____.d"
    SKROW "D___D..dd_____Dd"
    SKROW "D___D..dD____D.d"
    SKROW "BDDD...ddDD.D..d"
    SKROW "D..D...dd..D..Dd"
    SKROW "_D._D.Ddd.D_DD_D"
    SKROW "_D._D___D.D_DD_D"
    SKROW "_D______D.D_D__D"
    SKROW "_______________d"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP zb_shirt_front, zb_shirt_front_rows, 16, 24, zb_pal
    ; zb_shirt_back (16x24): zb_shirt BACK
    SKROWS zb_shirt_back_rows, 16, 24
    SKROW "BBBBBBBBBBBBBBBd"
    SKROW "B..............d"
    SKROW "B..............d"
    SKROW "B..............d"
    SKROW "dddddddddddddddd"
    SKROW "B........DDD...d"
    SKROW "B.......D___D..d"
    SKROW "B.......D____D.d"
    SKROW "B......D______Dd"
    SKROW "B......D______Dd"
    SKROW "B......D______Dd"
    SKROW "B.......D____D.d"
    SKROW "B.D.......DDD..d"
    SKROW "B._DD..........d"
    SKROW "D____D.........d"
    SKROW "B____DDDD......d"
    SKROW "BD___D___D.....d"
    SKROW "B.__DD___D.....d"
    SKROW "BD.D.D__DD.....d"
    SKROW "B_DD..DD__DD...D"
    SKROW "D_D_DDDD__D_D.D_"
    SKROW "D_._.__D__D__D._"
    SKROW "__D__________D__"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP zb_shirt_back, zb_shirt_back_rows, 16, 24, zb_pal
    ; zb_shirt_side_r (8x24): zb_shirt RIGHT
    SKROWS zb_shirt_side_r_rows, 8, 24
    SKROW "BBBBBBBB"
    SKROW "........"
    SKROW "........"
    SKROW "...d...."
    SKROW "...d...."
    SKROW "...d...."
    SKROW "...d...."
    SKROW "...d...."
    SKROW "...d...."
    SKROW "...d...."
    SKROW "...d...."
    SKROW "...d...."
    SKROW "...DD..."
    SKROW "..D__D.."
    SKROW ".D____D."
    SKROW ".D___D.."
    SKROW ".D__D..."
    SKROW "..DD...."
    SKROW "...d...."
    SKROW "D_Dd.D.."
    SKROW "__D.._DD"
    SKROW "___D__D_"
    SKROW "______D_"
    SKROW "________"
    SKROWS_END
    align 8
    SKBMP zb_shirt_side_r, zb_shirt_side_r_rows, 8, 24, zb_pal
    ; zb_shirt_side_l (8x24): zb_shirt LEFT
    SKROWS zb_shirt_side_l_rows, 8, 24
    SKROW "BBBBBBBB"
    SKROW "........"
    SKROW "........"
    SKROW "....d..."
    SKROW "....d..."
    SKROW "....d..."
    SKROW "....d..."
    SKROW "....d..."
    SKROW "....d..."
    SKROW "....d..."
    SKROW "....d..."
    SKROW "....d..."
    SKROW "...DD..."
    SKROW "..D__D.."
    SKROW ".D____D."
    SKROW "..D___D."
    SKROW "...D__D."
    SKROW "....DD.."
    SKROW "....d..."
    SKROW "..D.dD_D"
    SKROW "DD_..D__"
    SKROW "_D__D___"
    SKROW "_D______"
    SKROW "________"
    SKROWS_END
    align 8
    SKBMP zb_shirt_side_l, zb_shirt_side_l_rows, 8, 24, zb_pal
    ; zb_face (16x16): zb_head FRONT
    SKROWS zb_face_rows, 16, 16
    SKROW "................"
    SKROW ".rrr........k..."
    SKROW ".rrrr......kkk.."
    SKROW ".rrr............"
    SKROW "................"
    SKROW "................"
    SKROW "..XXXX....XXXX.."
    SKROW "..XXex....XexX.."
    SKROW "..XXxx....XxxXR."
    SKROW ".w.kk......kkRRR"
    SKROW "CCC.........RRR."
    SKROW ".w.cCcCcCcCcC..."
    SKROW "CCCmmmmmmmmmm..."
    SKROW ".w..c.c..c.c...."
    SKROW "................"
    SKROW "................"
    SKROWS_END
    align 8
    SKBMP zb_face, zb_face_rows, 16, 16, zb_pal
    ; zb_head_top (16x16): zb_head TOP
    SKROWS zb_head_top_rows, 16, 16
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "..........rrr..."
    SKROW ".........rrrrr.."
    SKROW "..........rrr..."
    SKROW "....kkk....r...."
    SKROW "...kkkkk........"
    SKROW "...kkkkkk......."
    SKROW "...kkkkk........"
    SKROW "....kkkk........"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROWS_END
    align 8
    SKBMP zb_head_top, zb_head_top_rows, 16, 16, zb_pal
    ; zb_head_back (16x16): zb_head BACK
    SKROWS zb_head_back_rows, 16, 16
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "...w............"
    SKROW "..CCC..........."
    SKROW "...w............"
    SKROW "...w.....k......"
    SKROW "..CCC.kkkk......"
    SKROW "...w..kkkkkk...."
    SKROW "..CCCkkkkkkk...."
    SKROW "......kkkkk....."
    SKROW ".......kkkk....."
    SKROW ".........k......"
    SKROW "................"
    SKROW "................"
    SKROWS_END
    align 8
    SKBMP zb_head_back, zb_head_back_rows, 16, 16, zb_pal
    ; zb_head_side_r (16x16): zb_head RIGHT
    SKROWS zb_head_side_r_rows, 16, 16
    SKROW "................"
    SKROW "................"
    SKROW ".........rrrr..."
    SKROW "..........rrr..."
    SKROW "..........rrr..."
    SKROW "...........r...."
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "...RRRRR........"
    SKROW "...RRRRR........"
    SKROW "...RRRR........."
    SKROW "....RRR........."
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROWS_END
    align 8
    SKBMP zb_head_side_r, zb_head_side_r_rows, 16, 16, zb_pal
    ; zb_head_side_l (16x16): zb_head LEFT
    SKROWS zb_head_side_l_rows, 16, 16
    SKROW "................"
    SKROW "................"
    SKROW "...rrrr........."
    SKROW "...rrr.........."
    SKROW "...rrr.........."
    SKROW "....r..........."
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "........RRRRR..."
    SKROW "........RRRRR..."
    SKROW ".........RRRR..."
    SKROW ".........RRR...."
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROWS_END
    align 8
    SKBMP zb_head_side_l, zb_head_side_l_rows, 16, 16, zb_pal
    ; zb_nose_front (3x3): zb_nose FRONT
    SKROWS zb_nose_front_rows, 3, 3
    SKROW "SSs"
    SKROW "sss"
    SKROW "KsK"
    SKROWS_END
    align 8
    SKBMP zb_nose_front, zb_nose_front_rows, 3, 3, zb_pal
    ; zb_ear (2x3): zb_ear_l LEFT, zb_ear_l RIGHT
    SKROWS zb_ear_rows, 2, 3
    SKROW "ss"
    SKROW "kK"
    SKROW "ss"
    SKROWS_END
    align 8
    SKBMP zb_ear, zb_ear_rows, 2, 3, zb_pal
    ; zb_ear_stub (2x2): zb_ear_r LEFT, zb_ear_r RIGHT
    SKROWS zb_ear_stub_rows, 2, 2
    SKROW "sK"
    SKROW "Kw"
    SKROWS_END
    align 8
    SKBMP zb_ear_stub, zb_ear_stub_rows, 2, 2, zb_pal
    ; zb_hair_front (16x16): zb_hair FRONT
    SKROWS zb_hair_front_rows, 16, 16
    SKROW "...H..H..H..H..."
    SKROW ".__.__.__....._."
    SKROW ".__.______.____."
    SKROW ".______________."
    SKROW ".______________."
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
    SKROWS_END
    align 8
    SKBMP zb_hair_front, zb_hair_front_rows, 16, 16, zb_pal
    ; zb_hair_back (16x16): zb_hair BACK
    SKROWS zb_hair_back_rows, 16, 16
    SKROW "j..j..j..j..j..j"
    SKROW "j..j..j..j..j..j"
    SKROW "j..j..j..j..j..j"
    SKROW "j..j..j..j..j..j"
    SKROW "j..j..j..j..j..j"
    SKROW "j..j..j..j..j..j"
    SKROW "................"
    SKROW "_....__......_.."
    SKROW "_._..__.._...__."
    SKROW "___..__.._._.___"
    SKROW "__________._____"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP zb_hair_back, zb_hair_back_rows, 16, 16, zb_pal
    ; zb_hair_side_r (16x16): zb_hair RIGHT
    SKROWS zb_hair_side_r_rows, 16, 16
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "......._________"
    SKROW ".._...._________"
    SKROW "..__..._________"
    SKROW "..__..._________"
    SKROW ".____.._________"
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
    SKBMP zb_hair_side_r, zb_hair_side_r_rows, 16, 16, zb_pal
    ; zb_hair_side_l (16x16): zb_hair LEFT
    SKROWS zb_hair_side_l_rows, 16, 16
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "_________......."
    SKROW "_________...._.."
    SKROW "_________...__.."
    SKROW "_________...__.."
    SKROW "_________..____."
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
    SKBMP zb_hair_side_l, zb_hair_side_l_rows, 16, 16, zb_pal
    ; zb_hair_top (16x16): zb_hair TOP
    SKROWS zb_hair_top_rows, 16, 16
    SKROW "j...j...j...j..."
    SKROW "j...j...j...j..."
    SKROW "j.H.j.H.j.H.j.H."
    SKROW "j.H.j.H.j.H.j.H."
    SKROW "j.H_j_H.j.H.j.H."
    SKROW "j.H_j_H.j.H.j.H."
    SKROW "j.H_j_H.j.H.j.H."
    SKROW "j.H_j.H.j.H.j.H."
    SKROW "j.H.j.H.j.H.j.H."
    SKROW "j.H.j.H.j.H_j_H."
    SKROW "j.H.j.H.j.H_j_H."
    SKROW "j.H.j.H.j.H_j_H."
    SKROW "j.H.j.H.j.H_j_H."
    SKROW "j.H.j.H.j.H_j_H."
    SKROW "j...j...j...j..."
    SKROW "j...j...j...j..."
    SKROWS_END
    align 8
    SKBMP zb_hair_top, zb_hair_top_rows, 16, 16, zb_pal
    ; zb_hair_bottom (16x16): zb_hair BOTTOM
    SKROWS zb_hair_bottom_rows, 16, 16
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
    SKROW "__............__"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP zb_hair_bottom, zb_hair_bottom_rows, 16, 16, zb_pal
    ; zb_leg_l_front (8x24): zb_leg_l FRONT
    SKROWS zb_leg_l_front_rows, 8, 24
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S..R...k"
    SKROW "S.RRR..k"
    SKROW "SRRRRR.k"
    SKROW "SRRRRR.k"
    SKROW "S.RRRR.k"
    SKROW "S.kkkk.k"
    SKROW "S..R...k"
    SKROW "S......k"
    SKROW "S......k"
    SKROWS_END
    align 8
    SKBMP zb_leg_l_front, zb_leg_l_front_rows, 8, 24, zb_pal
    ; zb_leg_l_side (8x24): zb_leg_l RIGHT, zb_leg_l LEFT
    SKROWS zb_leg_l_side_rows, 8, 24
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "...RRR.."
    SKROW "...RRR.."
    SKROW "..RRRR.."
    SKROW "..RRRRR."
    SKROW "...RRR.."
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROWS_END
    align 8
    SKBMP zb_leg_l_side, zb_leg_l_side_rows, 8, 24, zb_pal
    ; zb_leg_r_front (8x24): zb_leg_r FRONT
    SKROWS zb_leg_r_front_rows, 8, 24
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S.rrr..k"
    SKROW "S.rrr..k"
    SKROW "S.rrrr.k"
    SKROW "S.rrrr.k"
    SKROW "S.rrrr.k"
    SKROW "S.kkkk.k"
    SKROW "S..rr..k"
    SKROW "S......k"
    SKROW "S......k"
    SKROWS_END
    align 8
    SKBMP zb_leg_r_front, zb_leg_r_front_rows, 8, 24, zb_pal
    ; zb_leg_r_side (8x24): zb_leg_r RIGHT, zb_leg_r LEFT
    SKROWS zb_leg_r_side_rows, 8, 24
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "....R..."
    SKROW "...RRR.."
    SKROW "...RRR.."
    SKROW "..RRRR.."
    SKROW "..RRRRR."
    SKROW "...RRR.."
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROWS_END
    align 8
    SKBMP zb_leg_r_side, zb_leg_r_side_rows, 8, 24, zb_pal
    ; zb_pants_l_front (8x20): zb_pants_l FRONT
    SKROWS zb_pants_l_front_rows, 8, 20
    SKROW "qqqqqqqq"
    SKROW "P......q"
    SKROW "P..q...q"
    SKROW "P..q...q"
    SKROW "P..qQ..q"
    SKROW "P.Q__Q.q"
    SKROW "P.Q__..q"
    SKROW "P.____Qq"
    SKROW "PQ____Qq"
    SKROW "P.Q__..q"
    SKROW "P...Q..q"
    SKROW "P......q"
    SKROW "P......q"
    SKROW "P......q"
    SKROW "PQQ....Q"
    SKROW "Q__...Q_"
    SKROW "Q__Q.Q__"
    SKROW "Q____Q__"
    SKROW "_____Q__"
    SKROW "________"
    SKROWS_END
    align 8
    SKBMP zb_pants_l_front, zb_pants_l_front_rows, 8, 20, zb_pal
    ; zb_pants_l_back (8x20): zb_pants_l BACK
    SKROWS zb_pants_l_back_rows, 8, 20
    SKROW "qqqqqqqq"
    SKROW "P..q...q"
    SKROW "P..q...q"
    SKROW "P..q...q"
    SKROW "P..q...q"
    SKROW "P..q...q"
    SKROW "P..qQQ.q"
    SKROW "P..Q__Qq"
    SKROW "P.Q___.q"
    SKROW "P.Q___.q"
    SKROW "P..Q.Q.q"
    SKROW "P......q"
    SKROW "P......q"
    SKROW "P......q"
    SKROW "P....Q.q"
    SKROW "P..QQ_Qq"
    SKROW "Q.Q___.q"
    SKROW "_..____Q"
    SKROW "_______Q"
    SKROW "________"
    SKROWS_END
    align 8
    SKBMP zb_pants_l_back, zb_pants_l_back_rows, 8, 20, zb_pal
    ; zb_pants_l_right (8x20): zb_pants_l RIGHT
    SKROWS zb_pants_l_right_rows, 8, 20
    SKROW "qqqqqqqq"
    SKROW "P......q"
    SKROW "P..q...q"
    SKROW "P..q...q"
    SKROW "P.QQQ..q"
    SKROW "PQ___Q.q"
    SKROW "PQ___Q.q"
    SKROW "PQ___Q.q"
    SKROW "P.Q__Q.q"
    SKROW "P..QQ..q"
    SKROW "P..q...q"
    SKROW "P......q"
    SKROW "P......q"
    SKROW "P......q"
    SKROW "P.Q....q"
    SKROW "Q__Q.Q.Q"
    SKROW "P__.Q_Q_"
    SKROW "Q__QQ___"
    SKROW "________"
    SKROW "________"
    SKROWS_END
    align 8
    SKBMP zb_pants_l_right, zb_pants_l_right_rows, 8, 20, zb_pal
    ; zb_pants_l_left (8x20): zb_pants_l LEFT
    SKROWS zb_pants_l_left_rows, 8, 20
    SKROW "qqqqqqqq"
    SKROW "P......q"
    SKROW "P..q...q"
    SKROW "P..q...q"
    SKROW "P.QQQ..q"
    SKROW "PQ___..q"
    SKROW "PQ___Q.q"
    SKROW "PQ___Q.q"
    SKROW "PQ__Q..q"
    SKROW "P.QQ...q"
    SKROW "P..q...q"
    SKROW "P......q"
    SKROW "P......q"
    SKROW "P......q"
    SKROW "P......Q"
    SKROW "Q......_"
    SKROW "_Q..Q.._"
    SKROW "__.Q_.Q_"
    SKROW "___.__Q_"
    SKROW "________"
    SKROWS_END
    align 8
    SKBMP zb_pants_l_left, zb_pants_l_left_rows, 8, 20, zb_pal
    ; zb_pants_r_front (8x18): zb_pants_r FRONT
    SKROWS zb_pants_r_front_rows, 8, 18
    SKROW "qqqqqqqq"
    SKROW "P......q"
    SKROW "P..q...q"
    SKROW "P..q...q"
    SKROW "P..q...q"
    SKROW "P..q...q"
    SKROW "P..q...q"
    SKROW "P..q...q"
    SKROW "P.QQ...q"
    SKROW "PQ__Q..q"
    SKROW "Q___...q"
    SKROW "Q___Q..q"
    SKROW "PQ__Q..q"
    SKROW "P.._Q.QQ"
    SKROW "P.Q__.__"
    SKROW "QQ______"
    SKROW "________"
    SKROW "________"
    SKROWS_END
    align 8
    SKBMP zb_pants_r_front, zb_pants_r_front_rows, 8, 18, zb_pal
    ; zb_pants_r_back (8x18): zb_pants_r BACK
    SKROWS zb_pants_r_back_rows, 8, 18
    SKROW "qqqqqqqq"
    SKROW "P..q...q"
    SKROW "P..q...q"
    SKROW "P..q...q"
    SKROW "P..q...q"
    SKROW "P..q...q"
    SKROW "P..QQQ.q"
    SKROW "P.Q___.q"
    SKROW "P.Q___Qq"
    SKROW "P.Q___Qq"
    SKROW "P..QQQ.q"
    SKROW "P......q"
    SKROW "P......q"
    SKROW "P......q"
    SKROW "PQQ.Q..q"
    SKROW "Q____Q.q"
    SKROW "______.q"
    SKROW "________"
    SKROWS_END
    align 8
    SKBMP zb_pants_r_back, zb_pants_r_back_rows, 8, 18, zb_pal
    ; zb_pants_r_right (8x18): zb_pants_r RIGHT
    SKROWS zb_pants_r_right_rows, 8, 18
    SKROW "qqqqqqqq"
    SKROW "P......q"
    SKROW "P..q...q"
    SKROW "P..q...q"
    SKROW "P..Q...q"
    SKROW "PQ__Q..q"
    SKROW "PQ___Q.q"
    SKROW "PQ___Q.q"
    SKROW "P.Q_Q..q"
    SKROW "P..Q...q"
    SKROW "P..q...q"
    SKROW "P......q"
    SKROW "P......q"
    SKROW "P.Q...Qq"
    SKROW "P._QQQ_Q"
    SKROW "PQ_Q_Q_q"
    SKROW "P__Q_Q_Q"
    SKROW "________"
    SKROWS_END
    align 8
    SKBMP zb_pants_r_right, zb_pants_r_right_rows, 8, 18, zb_pal
    ; zb_pants_r_left (8x18): zb_pants_r LEFT
    SKROWS zb_pants_r_left_rows, 8, 18
    SKROW "qqqqqqqq"
    SKROW "P......q"
    SKROW "P..q...q"
    SKROW "P..q...q"
    SKROW "P..q...q"
    SKROW "P.Q_Q..q"
    SKROW "PQ___Q.q"
    SKROW "PQ___Q.q"
    SKROW "P.._Q..q"
    SKROW "P..Q...q"
    SKROW "P..q...q"
    SKROW "P......q"
    SKROW "Q......q"
    SKROW "_Q..Q..q"
    SKROW "__QQ_QQq"
    SKROW "__QQ_Q_Q"
    SKROW "___Q____"
    SKROW "________"
    SKROWS_END
    align 8
    SKBMP zb_pants_r_left, zb_pants_r_left_rows, 8, 18, zb_pal
    ; zb_foot_front (8x3): zb_foot_l FRONT
    SKROWS zb_foot_front_rows, 8, 3
    SKROW "ssKssKss"
    SKROW "sSKssKSs"
    SKROW "kkKkkKkk"
    SKROWS_END
    align 8
    SKBMP zb_foot_front, zb_foot_front_rows, 8, 3, zb_pal
    ; zb_foot_top (8x3): zb_foot_l TOP
    SKROWS zb_foot_top_rows, 8, 3
    SKROW "ssssssss"
    SKROW "sSssssSs"
    SKROW "nsnsnsns"
    SKROWS_END
    align 8
    SKBMP zb_foot_top, zb_foot_top_rows, 8, 3, zb_pal
    ; zb_arm_side_r (24x8): zb_arm_l RIGHT
    SKROWS zb_arm_side_r_rows, 24, 8
    SKROW "..........CcCccC........"
    SKROW "..........CccCcC...r...."
    SKROW "....R.....CcccCC..rrr..."
    SKROW "...RRRR...CCcccC.rrrr..."
    SKROW "...RRRRR..CcCccC..rrr..."
    SKROW "...RRRRR..CccCcC........"
    SKROW ".....R....CcccCC........"
    SKROW "kkkkkkkkkkkkkkkkkkkkkkkk"
    SKROWS_END
    align 8
    SKBMP zb_arm_side_r, zb_arm_side_r_rows, 24, 8, zb_pal
    ; zb_arm_side_l (24x8): zb_arm_l LEFT
    SKROWS zb_arm_side_l_rows, 24, 8
    SKROW "........CccCcC.........."
    SKROW "....r...CcCccC.........."
    SKROW "...rrr..CCcccC.....R...."
    SKROW "...rrrr.CcccCC...RRRR..."
    SKROW "...rrr..CccCcC..RRRRR..."
    SKROW "........CcCccC..RRRRR..."
    SKROW "........CCcccC....R....."
    SKROW "kkkkkkkkkkkkkkkkkkkkkkkk"
    SKROWS_END
    align 8
    SKBMP zb_arm_side_l, zb_arm_side_l_rows, 24, 8, zb_pal
    ; zb_arm_top (8x24): zb_arm_l TOP
    SKROWS zb_arm_top_rows, 8, 24
    SKROW "........"
    SKROW "........"
    SKROW "..kkk..."
    SKROW "..kkkk.."
    SKROW "..kkkk.."
    SKROW "..kkk..."
    SKROW "..kk...."
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "CCCCCCCC"
    SKROW "cccCcccC"
    SKROW "CcccCccc"
    SKROW "cCcccCcc"
    SKROW "ccCcccCc"
    SKROW "CCCCCCCC"
    SKROW "........"
    SKROW "........"
    SKROW ".....R.."
    SKROW "....RRR."
    SKROW "....RRR."
    SKROW "....RRR."
    SKROW "........"
    SKROW "........"
    SKROWS_END
    align 8
    SKBMP zb_arm_top, zb_arm_top_rows, 8, 24, zb_pal
    ; zb_arm_bottom (8x24): zb_arm_l BOTTOM
    SKROWS zb_arm_bottom_rows, 8, 24
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "CCCCCCCC"
    SKROW "cCcccCcc"
    SKROW "ccCcccCc"
    SKROW "cccCcccC"
    SKROW "CcccCccc"
    SKROW "CCCCCCCC"
    SKROW "........"
    SKROW "........"
    SKROW "...kk..."
    SKROW "..kkk..."
    SKROW "..kkkk.."
    SKROW "..kkk..."
    SKROW "...k...."
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROWS_END
    align 8
    SKBMP zb_arm_bottom, zb_arm_bottom_rows, 8, 24, zb_pal
    ; zb_arm_end (8x8): zb_arm_l FRONT
    SKROWS zb_arm_end_rows, 8, 8
    SKROW "kkkkkkkk"
    SKROW "kssssssk"
    SKROW "kssKKssk"
    SKROW "ksKKKKsk"
    SKROW "ksKKKKsk"
    SKROW "kssKKssk"
    SKROW "kssssssk"
    SKROW "kkkkkkkk"
    SKROWS_END
    align 8
    SKBMP zb_arm_end, zb_arm_end_rows, 8, 8, zb_pal
    ; zb_sleeve_side_r (12x8): zb_sleeve_l RIGHT
    SKROWS zb_sleeve_side_r_rows, 12, 8
    SKROW "BBBBBBBBD___"
    SKROW "B...DD..D___"
    SKROW "B..D__D..D__"
    SKROW "B.D____D..DD"
    SKROW "B..____D..._"
    SKROW "B..D_DD...D_"
    SKROW "B...D.....D_"
    SKROW "Bddddddddddd"
    SKROWS_END
    align 8
    SKBMP zb_sleeve_side_r, zb_sleeve_side_r_rows, 12, 8, zb_pal
    ; zb_sleeve_side_l (12x8): zb_sleeve_l LEFT
    SKROWS zb_sleeve_side_l_rows, 12, 8
    SKROW "___DBBBBBBBB"
    SKROW "___D..DD...B"
    SKROW "__D..D__D..B"
    SKROW "DD..D____D.B"
    SKROW "_...D____..B"
    SKROW "_D...DD_D..B"
    SKROW "_D.....D...B"
    SKROW "dddddddddddB"
    SKROWS_END
    align 8
    SKBMP zb_sleeve_side_l, zb_sleeve_side_l_rows, 12, 8, zb_pal
    ; zb_sleeve_top (8x12): zb_sleeve_l TOP
    SKROWS zb_sleeve_top_rows, 8, 12
    SKROW "BBBBBBBd"
    SKROW "B......d"
    SKROW "B......d"
    SKROW "B......d"
    SKROW "B......d"
    SKROW "B......d"
    SKROW "B......d"
    SKROW "B......d"
    SKROW "BDD..D.d"
    SKROW "D__DD_.d"
    SKROW "D__DD_.D"
    SKROW "B_____D_"
    SKROWS_END
    align 8
    SKBMP zb_sleeve_top, zb_sleeve_top_rows, 8, 12, zb_pal
    ; zb_sleeve_bottom (8x12): zb_sleeve_l BOTTOM
    SKROWS zb_sleeve_bottom_rows, 8, 12
    SKROW "B_____D_"
    SKROW "D__DD_.D"
    SKROW "D__DD_.d"
    SKROW "BDD..D.d"
    SKROW "B......d"
    SKROW "B......d"
    SKROW "B......d"
    SKROW "B......d"
    SKROW "B......d"
    SKROW "B......d"
    SKROW "B......d"
    SKROW "BBBBBBBd"
    SKROWS_END
    align 8
    SKBMP zb_sleeve_bottom, zb_sleeve_bottom_rows, 8, 12, zb_pal
    ; zb_sleeve_end (8x8): zb_sleeve_l FRONT
    SKROWS zb_sleeve_end_rows, 8, 8
    SKROW "DDDDDDDD"
    SKROW "D______D"
    SKROW "D______D"
    SKROW "D______D"
    SKROW "D______D"
    SKROW "D______D"
    SKROW "D______D"
    SKROW "DDDDDDDD"
    SKROWS_END
    align 8
    SKBMP zb_sleeve_end, zb_sleeve_end_rows, 8, 8, zb_pal
    ; zb_finger_top (2x4): zb_finger_a TOP
    SKROWS zb_finger_top_rows, 2, 4
    SKROW "ss"
    SKROW "sS"
    SKROW "ss"
    SKROW "nn"
    SKROWS_END
    align 8
    SKBMP zb_finger_top, zb_finger_top_rows, 2, 4, zb_pal
    ; zb_thumb_top (2x3): zb_thumb TOP
    SKROWS zb_thumb_top_rows, 2, 3
    SKROW "sS"
    SKROW "ss"
    SKROW "nn"
    SKROWS_END
    align 8
    SKBMP zb_thumb_top, zb_thumb_top_rows, 2, 3, zb_pal

section .data
SKMODEL_BEGIN m_zombie, 32, 0, 12, 44, -22
    SKBONE BK_BODY, 0, 0, 0.00
    PART zb_torso, -8, 24, -4, 16, 24, 8, 0, 0              ; bare green torso, ribs showing through the rips
    PART zb_shirt, -8, 24, -4, 16, 24, 8, 4, SKPF_CUTOUT    ; torn blue shirt: holes and a ragged hem
    SKBONE BK_HEAD, 0, 0, 0.00
    PART zb_head, -8, 48, -8, 16, 16, 16, 0, 0              ; sunken eyes, a gaping mouth with teeth, stitches
    PART zb_brow, -6, 58, -10, 12, 2, 2, 0, 0               ; heavy brow ridge
    PART zb_nose, -1, 52, -9, 3, 3, 1, 0, 0                 ; broken nose, off centre
    PART zb_ear_l, -9, 54, -1, 1, 3, 2, 0, 0                ; left ear
    PART zb_ear_r, 8, 55, -1, 1, 2, 2, 0, 0                 ; torn ear stub
    PART zb_hair, -8, 48, -8, 16, 16, 16, 4, SKPF_CUTOUT    ; matted hair overlay: a ragged hairline, bald patches
    PART zb_tuft_a, -5, 64, -3, 2, 3, 2, 0, 0               ; two spikes of hair
    PART_AS zb_tuft_b, zb_tuft_a, 3, 64, 2, 0, 0
    SKBONE BK_LLEG, 24, 0, 1.00
    PART zb_leg_l, -8, 0, -4, 8, 24, 8, 0, 0                ; bare green leg
    PART zb_pants_l, -8, 4, -4, 8, 20, 8, 4, SKPF_CUTOUT    ; ripped trousers, hem torn off above the ankle
    PART zb_foot_l, -8, 0, -7, 8, 3, 3, 0, 0                ; bare foot, toenails
    SKBONE BK_RLEG, 24, 0, -1.00
    PART zb_leg_r, 0, 0, -4, 8, 24, 8, 0, 0
    PART zb_pants_r, 0, 6, -4, 8, 18, 8, 4, SKPF_CUTOUT     ; the right trouser leg is shorter
    PART_AS zb_foot_r, zb_foot_l, 0, 0, -7, 0, 0
    SKBONE BK_LARM, 44, 0, -0.25
    PART zb_arm_l, -16, 40, -24, 8, 8, 24, 0, 0             ; arm pointing forward, a dirty bandage on the forearm
    PART zb_sleeve_l, -16, 40, -12, 8, 8, 12, 4, SKPF_CUTOUT; shirt sleeve, ragged end
    PART zb_finger_a, -16, 43, -28, 2, 2, 4, 0, 0           ; claws
    PART_AS zb_finger_b, zb_finger_a, -13, 43, -28, 0, 0
    PART_AS zb_finger_c, zb_finger_a, -10, 43, -28, 0, 0
    PART zb_thumb, -8, 41, -24, 2, 2, 3, 0, 0               ; thumb
    SKBONE BK_RARM, 44, 0, 0.25
    PART_AS zb_arm_r, zb_arm_l, 8, 40, -24, 0, 0
    PART_AS zb_sleeve_r, zb_sleeve_l, 8, 40, -12, 4, SKPF_CUTOUT
    PART_AS zb_finger_d, zb_finger_a, 8, 43, -28, 0, 0
    PART_AS zb_finger_e, zb_finger_a, 11, 43, -28, 0, 0
    PART_AS zb_finger_f, zb_finger_a, 14, 43, -28, 0, 0
    PART_AS zb_thumb_r, zb_thumb, 6, 41, -24, 0, 0
SKMODEL_PAINT
    ; --- zb_torso: green skin, ribs, a bruise and a bite wound; shows through the holes of zb_shirt
    SK_FILL zb_torso, SKM_ALL, ZB_SKIN_2, 15
    SK_BMP zb_torso, SKF_FRONT, 0, 0, zb_torso_front
    SK_BMP zb_torso, SKF_BACK, 0, 0, zb_torso_back
    SK_GRAD zb_torso, SKM_SIDES, 272, 224
    SK_RECT zb_torso, SKF_BOTTOM, 0, 0, 16, 8, ZB_SKIN_4, 0
    ; --- zb_shirt: blue cutout; rips show the torso, the hem is ragged, tears are shadowed
    SK_FILL zb_shirt, SKM_ALL, ZB_SHIRT_2, 15
    SK_GRAD zb_shirt, SKM_SIDES, 272, 224
    SK_BMP zb_shirt, SKF_FRONT, 0, 0, zb_shirt_front
    SK_BMP zb_shirt, SKF_BACK, 0, 0, zb_shirt_back
    SK_BMP zb_shirt, SKF_RIGHT, 0, 0, zb_shirt_side_r
    SK_BMP zb_shirt, SKF_LEFT, 0, 0, zb_shirt_side_l
    SK_RECT zb_shirt, SKF_BOTTOM, 0, 0, 16, 8, ZB_SHIRT_4, 0
    ; --- zb_head: dark sunken eye sockets with a pale glint, bags, a gaping mouth, stitches, rot and a bruise
    SK_FILL zb_head, SKM_ALL, ZB_SKIN_2, 15
    SK_GRAD zb_head, SKM_SIDES, 272, 224
    SK_BMP zb_head, SKF_FRONT, 0, 0, zb_face
    SK_BMP zb_head, SKF_TOP, 0, 0, zb_head_top
    SK_BMP zb_head, SKF_BACK, 0, 0, zb_head_back
    SK_BMP zb_head, SKF_RIGHT, 0, 0, zb_head_side_r
    SK_BMP zb_head, SKF_LEFT, 0, 0, zb_head_side_l
    SK_RECT zb_head, SKF_BOTTOM, 0, 0, 16, 16, ZB_SKIN_4, 0
    ; --- zb_brow, zb_nose, the ears and the hair patches
    SK_FILL zb_brow, SKM_ALL, ZB_SKIN_2, 15
    SK_RECT zb_brow, SKF_FRONT, 0, 0, 12, 1, ZB_SKIN_1, 0
    SK_RECT zb_brow, SKF_FRONT, 0, 1, 12, 1, ZB_SKIN_4, 0
    SK_RECT zb_brow, SKF_TOP, 0, 0, 12, 2, ZB_SKIN_1, 15
    SK_RECT zb_brow, SKF_BOTTOM, 0, 0, 12, 2, ZB_SKIN_4, 0
    SK_FILL zb_nose, SKM_ALL, ZB_SKIN_2, 7
    SK_BMP zb_nose, SKF_FRONT, 0, 0, zb_nose_front
    SK_FILL zb_ear_l, SKM_ALL, ZB_SKIN_2, 7
    SK_BMP zb_ear_l, SKF_LEFT, 0, 0, zb_ear
    SK_BMP zb_ear_l, SKF_RIGHT, 0, 0, zb_ear
    SK_FILL zb_ear_r, SKM_ALL, ZB_SKIN_2, 7
    SK_BMP zb_ear_r, SKF_LEFT, 0, 0, zb_ear_stub
    SK_BMP zb_ear_r, SKF_RIGHT, 0, 0, zb_ear_stub
    SK_FILL zb_hair, SKM_ALL, ZB_HAIR_2, 31
    SK_GRAD zb_hair, SKM_SIDES, 272, 224
    SK_BMP zb_hair, SKF_FRONT, 0, 0, zb_hair_front
    SK_BMP zb_hair, SKF_BACK, 0, 0, zb_hair_back
    SK_BMP zb_hair, SKF_RIGHT, 0, 0, zb_hair_side_r
    SK_BMP zb_hair, SKF_LEFT, 0, 0, zb_hair_side_l
    SK_BMP zb_hair, SKF_TOP, 0, 0, zb_hair_top
    SK_BMP zb_hair, SKF_BOTTOM, 0, 0, zb_hair_bottom
    SK_FILL zb_tuft_a, SKM_ALL, ZB_HAIR_2, 31
    SK_RECT zb_tuft_a, SKF_TOP, 0, 0, 2, 2, ZB_HAIR_1, 0
    SK_GRAD zb_tuft_a, SKM_SIDES, 272, 224
    ; --- zb_leg_l / zb_leg_r: bare green legs; zb_pants_l / zb_pants_r: blue trousers with rips, ragged hems
    SK_FILL zb_leg_l, SKM_ALL, ZB_SKIN_2, 15
    SK_BMP zb_leg_l, SKF_FRONT, 0, 0, zb_leg_l_front
    SK_BMP zb_leg_l, SKF_RIGHT, 0, 0, zb_leg_l_side
    SK_BMP zb_leg_l, SKF_LEFT, 0, 0, zb_leg_l_side
    SK_GRAD zb_leg_l, SKM_SIDES, 272, 224
    SK_RECT zb_leg_l, SKF_BOTTOM, 0, 0, 8, 8, ZB_SKIN_4, 0
    SK_FILL zb_leg_r, SKM_ALL, ZB_SKIN_2, 15
    SK_BMP zb_leg_r, SKF_FRONT, 0, 0, zb_leg_r_front
    SK_BMP zb_leg_r, SKF_RIGHT, 0, 0, zb_leg_r_side
    SK_BMP zb_leg_r, SKF_LEFT, 0, 0, zb_leg_r_side
    SK_GRAD zb_leg_r, SKM_SIDES, 272, 224
    SK_RECT zb_leg_r, SKF_BOTTOM, 0, 0, 8, 8, ZB_SKIN_4, 0
    SK_FILL zb_pants_l, SKM_ALL, ZB_PANTS_2, 15
    SK_FILL zb_pants_r, SKM_ALL, ZB_PANTS_2, 15
    SK_GRAD zb_pants_l, SKM_SIDES, 272, 224
    SK_GRAD zb_pants_r, SKM_SIDES, 272, 224
    SK_BMP zb_pants_l, SKF_FRONT, 0, 0, zb_pants_l_front
    SK_BMP zb_pants_l, SKF_BACK, 0, 0, zb_pants_l_back
    SK_BMP zb_pants_l, SKF_RIGHT, 0, 0, zb_pants_l_right
    SK_BMP zb_pants_l, SKF_LEFT, 0, 0, zb_pants_l_left
    SK_RECT zb_pants_l, SKF_TOP, 0, 0, 8, 8, ZB_PANTS_1, 0
    SK_RECT zb_pants_l, SKF_BOTTOM, 0, 0, 8, 8, ZB_PANTS_4, 0
    SK_BMP zb_pants_r, SKF_FRONT, 0, 0, zb_pants_r_front
    SK_BMP zb_pants_r, SKF_BACK, 0, 0, zb_pants_r_back
    SK_BMP zb_pants_r, SKF_RIGHT, 0, 0, zb_pants_r_right
    SK_BMP zb_pants_r, SKF_LEFT, 0, 0, zb_pants_r_left
    SK_RECT zb_pants_r, SKF_TOP, 0, 0, 8, 8, ZB_PANTS_1, 0
    SK_RECT zb_pants_r, SKF_BOTTOM, 0, 0, 8, 8, ZB_PANTS_4, 0
    SK_FILL zb_foot_l, SKM_ALL, ZB_SKIN_2, 15
    SK_BMP zb_foot_l, SKF_FRONT, 0, 0, zb_foot_front
    SK_BMP zb_foot_l, SKF_TOP, 0, 0, zb_foot_top
    SK_RECT zb_foot_l, SKF_BOTTOM, 0, 0, 8, 3, ZB_SKIN_4, 0
    ; --- zb_arm_l (shared with zb_arm_r): bare arm, a dirty bandage, a bruise and a rot patch; zb_sleeve_l: ragged
    SK_FILL zb_arm_l, SKM_ALL, ZB_SKIN_2, 15
    SK_BMP zb_arm_l, SKF_RIGHT, 0, 0, zb_arm_side_r
    SK_BMP zb_arm_l, SKF_LEFT, 0, 0, zb_arm_side_l
    SK_BMP zb_arm_l, SKF_TOP, 0, 0, zb_arm_top
    SK_BMP zb_arm_l, SKF_BOTTOM, 0, 0, zb_arm_bottom
    SK_BMP zb_arm_l, SKF_FRONT, 0, 0, zb_arm_end
    SK_RECT zb_arm_l, SKF_BACK, 0, 0, 8, 8, ZB_SKIN_3, 0
    SK_GRAD zb_arm_l, SKM_SIDES, 272, 224
    SK_FILL zb_sleeve_l, SKM_ALL, ZB_SHIRT_2, 15
    SK_GRAD zb_sleeve_l, SKM_SIDES, 272, 224
    SK_BMP zb_sleeve_l, SKF_RIGHT, 0, 0, zb_sleeve_side_r
    SK_BMP zb_sleeve_l, SKF_LEFT, 0, 0, zb_sleeve_side_l
    SK_BMP zb_sleeve_l, SKF_TOP, 0, 0, zb_sleeve_top
    SK_BMP zb_sleeve_l, SKF_BOTTOM, 0, 0, zb_sleeve_bottom
    SK_BMP zb_sleeve_l, SKF_FRONT, 0, 0, zb_sleeve_end
    SK_RECT zb_sleeve_l, SKF_BACK, 0, 0, 8, 8, ZB_SHIRT_4, 0
    SK_FILL zb_finger_a, SKM_ALL, ZB_SKIN_2, 7
    SK_BMP zb_finger_a, SKF_TOP, 0, 0, zb_finger_top
    SK_RECT zb_finger_a, SKF_FRONT, 0, 0, 2, 2, ZB_SKIN_4, 0
    SK_RECT zb_finger_a, SKF_BOTTOM, 0, 0, 2, 4, ZB_SKIN_3, 0
    SK_GRAD zb_finger_a, SKM_SIDES, 272, 224
    SK_FILL zb_thumb, SKM_ALL, ZB_SKIN_2, 7
    SK_BMP zb_thumb, SKF_TOP, 0, 0, zb_thumb_top
    SK_RECT zb_thumb, SKF_FRONT, 0, 0, 2, 2, ZB_SKIN_4, 0
SKMODEL_END

; ===================================================================================================
; m_pig
; ===================================================================================================
RAMP PG_SKIN, 240, 160, 160            ; pink (the old pig tile)
RAMP PG_SNOUT, 218, 128, 138           ; snout
RAMP PG_HOOF, 78, 66, 64               ; dark hooves

section .rodata
; The characters of every pg_ bitmap. Groups: base, highlight, shade, deep.
;   s S k K pink skin   n N o O snout (O the nostrils)   h H j J hoof   i inner ear   b blush   m mud
;   x eye   W glint   _ transparent
align 8
pg_pal:
    PALC 's', PG_SKIN_2
    PALC 'S', PG_SKIN_1
    PALC 'k', PG_SKIN_3
    PALC 'K', PG_SKIN_4
    PALC 'n', PG_SNOUT_2
    PALC 'N', PG_SNOUT_1
    PALC 'o', PG_SNOUT_3
    PALC 'O', PG_SNOUT_4
    PALC 'i', RGBO(208, 106, 122)
    PALC 'b', RGBO(255, 132, 142)
    PALC 'r', RGBO(196, 116, 124)
    PALC 'm', RGBO(150, 110, 86)
    PALC 'h', PG_HOOF_2
    PALC 'H', PG_HOOF_1
    PALC 'j', PG_HOOF_3
    PALC 'J', PG_HOOF_4
    PALC 'x', RGBO(22, 18, 24)
    PALC 'W', RGBO(255, 255, 255)
    PALT '_'
    dq 0

    ; pg_body_top (20x32): pg_body TOP
    SKROWS pg_body_top_rows, 20, 32
    SKROW ".......kkkkkk......."
    SKROW ".......kkkkkk......."
    SKROW ".......kkkkkk......."
    SKROW "...mmm.kkkkkk......."
    SKROW ".......kkkkkk......."
    SKROW ".......kkkkkk......."
    SKROW ".......kkkkkk......."
    SKROW ".......kkkkkk......."
    SKROW ".......kkkkkk......."
    SKROW ".......kkkkkk......."
    SKROW ".......kkkkkk......."
    SKROW ".......kkkkkk......."
    SKROW ".......kkkkkk......."
    SKROW ".......kkkkkk......."
    SKROW ".....K.kkkkkk...K..."
    SKROW "....KKKkkkkkk..mmm.."
    SKROW "....KKKkkkkkk..KKKK."
    SKROW "....KKKkkkkkk..KKKK."
    SKROW ".....Kmmmkkkk..KK..."
    SKROW ".....KKkkkkkk......."
    SKROW ".....KKkkkkkk......."
    SKROW ".....KKkkkkkk......."
    SKROW ".......kkkkkk......."
    SKROW ".......kkkkkk......."
    SKROW ".......kkkkkk......."
    SKROW ".......kkkkkk......."
    SKROW ".......kkkkkk....K.."
    SKROW ".......kkkkkk..KKK.."
    SKROW ".......kkkkkk.KKKKK."
    SKROW ".......kkkkkk.KKKKK."
    SKROW ".......kkkkkk.KKKKK."
    SKROW ".......kkkkkk..KKK.."
    SKROWS_END
    align 8
    SKBMP pg_body_top, pg_body_top_rows, 20, 32, pg_pal
    ; pg_body_side_r (32x16): pg_body RIGHT
    SKROWS pg_body_side_r_rows, 32, 16
    SKROW "................................"
    SKROW "................................"
    SKROW "........k.k..KKK................"
    SKROW "......kkkkk.KKKKK..............."
    SKROW ".....kkkkkkkkKKK....kk.........."
    SKROW "....kkkkkkkkk......kkkkk........"
    SKROW ".....kkkkkkkk......kkkkk........"
    SKROW "......kkkk........kkkkkkk......."
    SKROW ".......k...........kkkkk........"
    SKROW ".........mmmmm.....kkkkk........"
    SKROW ".mmmmm..............kkkk........"
    SKROW "..............mmmmm............."
    SKROW "S.S.S.S.S.S.S.S.S.S.S.S.S.S.S.S."
    SKROW "SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS"
    SKROW "SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS"
    SKROW "SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS"
    SKROWS_END
    align 8
    SKBMP pg_body_side_r, pg_body_side_r_rows, 32, 16, pg_pal
    ; pg_body_side_l (32x16): pg_body LEFT
    SKROWS pg_body_side_l_rows, 32, 16
    SKROW "................................"
    SKROW "................................"
    SKROW "................KKK..k.k........"
    SKROW "...............KKKKK.kkkkk......"
    SKROW "..........kk....KKKkkkkkkkk....."
    SKROW "........kkkkk......kkkkkkkkk...."
    SKROW "........kkkkk......kkkkkkkk....."
    SKROW ".......kkkkkkk........kkkk......"
    SKROW "........kkkkk...........k......."
    SKROW "........kkkkk.....mmmmm........."
    SKROW "........kkkk..............mmmmm."
    SKROW ".............mmmmm.............."
    SKROW ".S.S.S.S.S.S.S.S.S.S.S.S.S.S.S.S"
    SKROW "SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS"
    SKROW "SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS"
    SKROW "SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS"
    SKROWS_END
    align 8
    SKBMP pg_body_side_l, pg_body_side_l_rows, 32, 16, pg_pal
    ; pg_body_back (20x16): pg_body BACK
    SKROWS pg_body_back_rows, 20, 16
    SKROW "...................."
    SKROW "...................."
    SKROW "...................."
    SKROW "...................."
    SKROW "....k.k..KK...kk...."
    SKROW "....kkkk.KK..kkkk..."
    SKROW "...kkkkkk..kkkkkkk.."
    SKROW "..kkkkkk...kkkkkk..."
    SKROW "..kkkkkkk..kkkkkk..."
    SKROW "..kkkkkkk...kkkkk..."
    SKROW "...kkkkkk...kkkkkk.."
    SKROW "...kkkkk....kkkkk..."
    SKROW "....kk.............."
    SKROW "...................."
    SKROW "SSSSSSSSSSSSSSSSSSSS"
    SKROW "SSSSSSSSSSSSSSSSSSSS"
    SKROWS_END
    align 8
    SKBMP pg_body_back, pg_body_back_rows, 20, 16, pg_pal
    ; pg_spine_top (2x20): pg_spine TOP
    SKROWS pg_spine_top_rows, 2, 20
    SKROW "K."
    SKROW ".."
    SKROW ".K"
    SKROW ".."
    SKROW "K."
    SKROW ".."
    SKROW ".K"
    SKROW ".."
    SKROW "K."
    SKROW ".."
    SKROW ".K"
    SKROW ".."
    SKROW "K."
    SKROW ".."
    SKROW ".K"
    SKROW ".."
    SKROW "K."
    SKROW ".."
    SKROW ".K"
    SKROW ".."
    SKROWS_END
    align 8
    SKBMP pg_spine_top, pg_spine_top_rows, 2, 20, pg_pal
    ; pg_face (16x16): pg_head FRONT
    SKROWS pg_face_rows, 16, 16
    SKROW "................"
    SKROW "....kkkkkkkk...."
    SKROW "......kkkk......"
    SKROW "................"
    SKROW "..KK........KK.."
    SKROW "..Wx........Wx.."
    SKROW "..xx........xx.."
    SKROW "................"
    SKROW "..bb........bb.."
    SKROW ".bb..........bb."
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW ".....KKKKKK....."
    SKROW "....kkkkkkkk...."
    SKROWS_END
    align 8
    SKBMP pg_face, pg_face_rows, 16, 16, pg_pal
    ; pg_head_side_r (12x16): pg_head RIGHT
    SKROWS pg_head_side_r_rows, 12, 16
    SKROW "............"
    SKROW "............"
    SKROW "............"
    SKROW "............"
    SKROW "............"
    SKROW "............"
    SKROW "............"
    SKROW "............"
    SKROW ".........bb."
    SKROW "............"
    SKROW "............"
    SKROW "............"
    SKROW "............"
    SKROW "............"
    SKROW "kkkkkkkkkkkk"
    SKROW "KKKKKKKKKKKK"
    SKROWS_END
    align 8
    SKBMP pg_head_side_r, pg_head_side_r_rows, 12, 16, pg_pal
    ; pg_head_side_l (12x16): pg_head LEFT
    SKROWS pg_head_side_l_rows, 12, 16
    SKROW "............"
    SKROW "............"
    SKROW "............"
    SKROW "............"
    SKROW "............"
    SKROW "............"
    SKROW "............"
    SKROW "............"
    SKROW ".bb........."
    SKROW "............"
    SKROW "............"
    SKROW "............"
    SKROW "............"
    SKROW "............"
    SKROW "kkkkkkkkkkkk"
    SKROW "KKKKKKKKKKKK"
    SKROWS_END
    align 8
    SKBMP pg_head_side_l, pg_head_side_l_rows, 12, 16, pg_pal
    ; pg_snout_front (8x6): pg_snout FRONT
    SKROWS pg_snout_front_rows, 8, 6
    SKROW "NNNNNNNN"
    SKROW "NnnnnnnN"
    SKROW "nOOnnOOn"
    SKROW "nOOnnOOn"
    SKROW "nnnnnnnn"
    SKROW "oooooooo"
    SKROWS_END
    align 8
    SKBMP pg_snout_front, pg_snout_front_rows, 8, 6, pg_pal
    ; pg_ear_front (5x5): pg_ear_l FRONT
    SKROWS pg_ear_front_rows, 5, 5
    SKROW "kkkkk"
    SKROW "kiiik"
    SKROW "kiiik"
    SKROW "kiiik"
    SKROW "_kkk_"
    SKROWS_END
    align 8
    SKBMP pg_ear_front, pg_ear_front_rows, 5, 5, pg_pal
    ; pg_ear_back (5x5): pg_ear_l BACK
    SKROWS pg_ear_back_rows, 5, 5
    SKROW "sssss"
    SKROW "sssss"
    SKROW "sssss"
    SKROW "sssss"
    SKROW "_sss_"
    SKROWS_END
    align 8
    SKBMP pg_ear_back, pg_ear_back_rows, 5, 5, pg_pal
    ; pg_leg_front (8x12): pg_leg_fl FRONT, pg_leg_fl BACK
    SKROWS pg_leg_front_rows, 8, 12
    SKROW "kkkkkkkk"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S......k"
    SKROW "S..mmmmk"
    SKROW "S.mmmmmk"
    SKROW "S..mmmmk"
    SKROW "S......k"
    SKROW "S......k"
    SKROWS_END
    align 8
    SKBMP pg_leg_front, pg_leg_front_rows, 8, 12, pg_pal
    ; pg_leg_side (8x12): pg_leg_fl RIGHT, pg_leg_fl LEFT
    SKROWS pg_leg_side_rows, 8, 12
    SKROW "kkkkkkkk"
    SKROW ".......k"
    SKROW ".......k"
    SKROW ".......k"
    SKROW ".......k"
    SKROW ".......k"
    SKROW ".......k"
    SKROW "...mmm.k"
    SKROW "..mmmmmk"
    SKROW "...mmm.k"
    SKROW ".......k"
    SKROW ".......k"
    SKROWS_END
    align 8
    SKBMP pg_leg_side, pg_leg_side_rows, 8, 12, pg_pal
    ; pg_hoof_front (8x3): pg_hoof_fl FRONT, pg_hoof_fl BACK
    SKROWS pg_hoof_front_rows, 8, 3
    SKROW "HHHHHHHH"
    SKROW "hhhJJhhh"
    SKROW "jjjJJjjj"
    SKROWS_END
    align 8
    SKBMP pg_hoof_front, pg_hoof_front_rows, 8, 3, pg_pal
    ; pg_hoof_side (8x3): pg_hoof_fl RIGHT, pg_hoof_fl LEFT
    SKROWS pg_hoof_side_rows, 8, 3
    SKROW "HHHHHHHH"
    SKROW "hhhhhhhh"
    SKROW "jjjjjjjj"
    SKROWS_END
    align 8
    SKBMP pg_hoof_side, pg_hoof_side_rows, 8, 3, pg_pal
    ; pg_hoof_sole (8x8): pg_hoof_fl BOTTOM
    SKROWS pg_hoof_sole_rows, 8, 8
    SKROW "...JJ..."
    SKROW "...JJ..."
    SKROW "...JJ..."
    SKROW "...JJ..."
    SKROW "...JJ..."
    SKROW "...JJ..."
    SKROW "...JJ..."
    SKROW "...JJ..."
    SKROWS_END
    align 8
    SKBMP pg_hoof_sole, pg_hoof_sole_rows, 8, 8, pg_pal

section .data
SKMODEL_BEGIN m_pig, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART pg_body, -10, 12, -16, 20, 16, 32, 0, 0            ; barrel body, darker back, lighter belly, blotches
    PART pg_spine, -1, 28, -12, 2, 1, 20, 0, 0              ; bristle ridge along the spine
    PART pg_tail1, -1, 21, 16, 2, 2, 3, 0, 0                ; curly tail: back, up, over
    PART pg_tail2, -1, 23, 17, 2, 4, 2, 0, 0
    PART pg_tail3, -1, 27, 16, 2, 2, 2, 0, 0
    PART pg_head, -8, 16, -28, 16, 16, 12, 0, 0             ; head: small eyes with a glint, blush, brows, a mouth line
    PART pg_snout, -4, 18, -31, 8, 6, 3, 0, 0               ; protruding snout with two nostrils
    PART pg_ear_l, -13, 27, -24, 5, 5, 2, 0, SKPF_CUTOUT    ; floppy ear hanging at the side, rounded by cutout corners
    PART_AS pg_ear_r, pg_ear_l, 8, 27, -24, 0, SKPF_CUTOUT
    SKBONE BK_LIMB, 12, -10, 1.00
    PART pg_leg_fl, -10, 0, -14, 8, 12, 8, 0, 0             ; front left leg
    PART pg_hoof_fl, -10, 0, -14, 8, 3, 8, 4, 0             ; cloven hoof (dark)
    SKBONE BK_LIMB, 12, -10, -1.00
    PART_AS pg_leg_fr, pg_leg_fl, 2, 0, -14, 0, 0
    PART_AS pg_hoof_fr, pg_hoof_fl, 2, 0, -14, 4, 0
    SKBONE BK_LIMB, 12, 10, -1.00
    PART_AS pg_leg_bl, pg_leg_fl, -10, 0, 6, 0, 0
    PART_AS pg_hoof_bl, pg_hoof_fl, -10, 0, 6, 4, 0
    SKBONE BK_LIMB, 12, 10, 1.00
    PART_AS pg_leg_br, pg_leg_fl, 2, 0, 6, 0, 0
    PART_AS pg_hoof_br, pg_hoof_fl, 2, 0, 6, 4, 0
SKMODEL_PAINT
    ; --- pg_body: pink barrel; top: a darker stripe along the spine and blotches; belly lighter; mud smudges
    SK_FILL pg_body, SKM_ALL, PG_SKIN_2, 15
    SK_BMP pg_body, SKF_TOP, 0, 0, pg_body_top
    SK_RECT pg_body, SKF_BOTTOM, 0, 0, 20, 32, PG_SKIN_1, 15
    SK_RECT pg_body, SKF_BOTTOM, 9, 0, 2, 32, PG_SKIN_2, 0
    SK_BMP pg_body, SKF_RIGHT, 0, 0, pg_body_side_r
    SK_BMP pg_body, SKF_LEFT, 0, 0, pg_body_side_l
    SK_BMP pg_body, SKF_BACK, 0, 0, pg_body_back
    SK_RECT pg_body, SKF_FRONT, 0, 14, 20, 2, PG_SKIN_1, 15
    SK_GRAD pg_body, SKM_SIDES, 272, 224
    ; --- pg_spine and the tail
    SK_FILL pg_spine, SKM_ALL, PG_SKIN_2, 31
    SK_BMP pg_spine, SKF_TOP, 0, 0, pg_spine_top
    SK_FILL pg_tail1, SKM_ALL, PG_SKIN_1, 15
    SK_GRAD pg_tail1, SKM_SIDES, 272, 232
    SK_FILL pg_tail2, SKM_ALL, PG_SKIN_1, 15
    SK_GRAD pg_tail2, SKM_SIDES, 272, 232
    SK_FILL pg_tail3, SKM_ALL, PG_SKIN_1, 15
    SK_GRAD pg_tail3, SKM_SIDES, 272, 232
    SK_RECT pg_tail3, SKF_TOP, 0, 0, 2, 2, PG_SKIN_2, 0
    SK_RECT pg_tail3, SKF_FRONT, 0, 0, 2, 2, PG_SKIN_2, 0
    ; --- pg_head: little eyes with a glint, blush, brows, a mouth line under the snout, wrinkles on the forehead
    SK_FILL pg_head, SKM_ALL, PG_SKIN_2, 15
    SK_BMP pg_head, SKF_FRONT, 0, 0, pg_face
    SK_RECT pg_head, SKF_TOP, 7, 0, 2, 12, PG_SKIN_3, 15
    SK_RECT pg_head, SKF_BOTTOM, 0, 0, 16, 12, PG_SKIN_1, 15
    SK_BMP pg_head, SKF_RIGHT, 0, 0, pg_head_side_r
    SK_BMP pg_head, SKF_LEFT, 0, 0, pg_head_side_l
    SK_GRAD pg_head, SKM_SIDES, 272, 224
    ; --- pg_snout: lighter, two nostrils; pg_ear_l (shared): inner ear and rim
    SK_FILL pg_snout, SKM_ALL, PG_SNOUT_2, 7
    SK_BMP pg_snout, SKF_FRONT, 0, 0, pg_snout_front
    SK_RECT pg_snout, SKF_TOP, 0, 0, 8, 3, PG_SNOUT_1, 0
    SK_RECT pg_snout, SKF_BOTTOM, 0, 0, 8, 3, PG_SNOUT_4, 0
    SK_GRAD pg_snout, SKM_SIDES, 272, 232
    SK_FILL pg_ear_l, SKM_ALL, PG_SKIN_2, 15
    SK_BMP pg_ear_l, SKF_FRONT, 0, 0, pg_ear_front
    SK_BMP pg_ear_l, SKF_BACK, 0, 0, pg_ear_back
    SK_RECT pg_ear_l, SKF_TOP, 0, 0, 5, 2, PG_SKIN_1, 0
    SK_RECT pg_ear_l, SKF_BOTTOM, 0, 0, 5, 2, PG_SKIN_3, 0
    SK_RECT pg_ear_l, SKF_RIGHT, 0, 0, 2, 5, PG_SKIN_3, 15
    SK_RECT pg_ear_l, SKF_LEFT, 0, 0, 2, 5, PG_SKIN_3, 15
    ; --- pg_leg_fl (shared by the four legs): pink, a mud smudge; pg_hoof_fl (shared): dark, split
    SK_FILL pg_leg_fl, SKM_ALL, PG_SKIN_2, 15
    SK_BMP pg_leg_fl, SKF_FRONT, 0, 0, pg_leg_front
    SK_BMP pg_leg_fl, SKF_BACK, 0, 0, pg_leg_front
    SK_BMP pg_leg_fl, SKF_RIGHT, 0, 0, pg_leg_side
    SK_BMP pg_leg_fl, SKF_LEFT, 0, 0, pg_leg_side
    SK_RECT pg_leg_fl, SKF_BOTTOM, 0, 0, 8, 8, PG_HOOF_4, 0
    SK_GRAD pg_leg_fl, SKM_SIDES, 272, 224
    SK_FILL pg_hoof_fl, SKM_ALL, PG_HOOF_2, 15
    SK_BMP pg_hoof_fl, SKF_FRONT, 0, 0, pg_hoof_front
    SK_BMP pg_hoof_fl, SKF_BACK, 0, 0, pg_hoof_front
    SK_BMP pg_hoof_fl, SKF_RIGHT, 0, 0, pg_hoof_side
    SK_BMP pg_hoof_fl, SKF_LEFT, 0, 0, pg_hoof_side
    SK_RECT pg_hoof_fl, SKF_TOP, 0, 0, 8, 8, PG_HOOF_2, 0
    SK_RECT pg_hoof_fl, SKF_BOTTOM, 0, 0, 8, 8, PG_HOOF_4, 0
    SK_BMP pg_hoof_fl, SKF_BOTTOM, 0, 0, pg_hoof_sole
SKMODEL_END
