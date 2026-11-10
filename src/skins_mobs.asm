; skins_mobs.asm: skin models of the mobs (0.13 "looks"): zombie, skeleton, creeper, spider, pig, chicken and
; the Fallen King. Data only: bones, parts and paint ops for skin.asm (art.inc, common.inc "0.13 looks");
; nothing here runs.
;
; The zombie and the pig are the validated style samples, the other mobs follow the same structure:
;   m_zombie   arms forward, green rotting skin, sunken eyes, a torn blue shirt and ripped trousers as cutout
;              overlays, a bandaged forearm, clawed hands (prefix zb_)
;   m_pig      barrel body, head with a snout and floppy ears, a curly tail, cloven hooves (prefix pg_)
;   m_skeleton ivory bones with joint knobs (4-wide limbs), a ribcage cutout over a dark core, a leather
;              bandolier and quiver, a skull with dark sockets, a cold glint, teeth and a patch of moss;
;              holds a BOW in the right hand (prefix sk_)
;   m_creeper  mottled green with leafy darker patches and leaf clumps, the classic dark face, a tuft of leaves
;              on the head, four stubby legs ending in toed feet (prefix cr_)
;   m_chicken  scalloped white feathers, a chest puff and a tail fan, a three-bump comb, beak, wattle and ear lobes,
;              wings that sway (BK_LIMB), thin scaly legs with feathered thighs and toes (prefix ch_)
;   m_spider   dark hairy abdomen with a red-orange diamond marking, thorax, a head with eight glowing red eyes,
;              fangs and palps; eight legs of an upper run, a high knee and a lower stilt each (prefix sp_)
; One section per model, in file order: ramps, then palette and bitmaps (section .rodata), then the model
; (section .data), so a model reads top to bottom.
;
; Model space (texels, origin = feet centre, front = -Z). The old boxes of mobrender.asm x 32 give the sizes
; (zombie: legs 8x24x8, body 16x24x8, head 16^3, arms 8x8x24 pointing forward, arm pivot (44, 0) swinging
; -0.25 / +0.25; pig: body 20x16x32, head 16x16x12, four 8x12x8 legs pivoting at (12, +-10), swing +1 / -1 /
; -1 / +1 front left, front right, back left, back right).
; skeleton: legs 4x24x4 at x +-2..6, body 16x24x8, head 16^3, arms 4x24x4 at x +-8..12 hanging, arm pivot (46, 0)
; swinging -1 / +1, leg pivot (24, 0) swinging +1 / -1; the hand point (10, 26, 0) is the centre of the right hand.
; creeper: body 16x24x8 at y 12..36, head 16^3, four 8x12x8 legs (8x8x8 and an 8x4x8 foot) at z +-4..12 pivoting at
; (12, +-8), swing +1 / -1 / -1 / +1 front left, front right, back left, back right.
; chicken: body 12x14x16 at y 10..24, head 8^3 on a 6x6x5 neck, wings 2x11x10 hinged at (22, 0) swinging +0.3, legs
; 2x9x2 pivoting at (10, 0), swing +1 / -1 (the beak reaches z -16, the tail z 9).
; spider: abdomen 24x18x24, thorax 12x12x8, head 16^3 (z -24..-8), eight legs 4 thick at z +-4 / +-12 pivoting at
; (18, z), swing +0.5 / -0.5 alternating front to back, left side first (the old legs: 26x4x4 at y 14..18, +-0.5).
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
;     zombie's legs have different rips, so each has its own skin). Mirrored limbs that need a different image
;     per side (the spider's legs run along X) get one skin per side, shared by the four legs of that side.
;   - grain: noise 15 on cloth and skin, 31 on hair and bristles, 0 on trims.
;   - skin_build packs the unwraps on shelves, tallest first, so the record order does not matter: a part costs
;     2(w+d) x (d+h) atlas texels (a cutout overlay as much as a solid part), an AS part nothing.
;     The six models here take 229 atlas rows together (of 3072); alone: skeleton 42, creeper 32,
;     chicken 34, spider 58 (zombie and pig 119 together).
; Ramps (RAMP: _1 highlight, _2 base, _3 shade, _4 deep; AC_* are the shared material ramps of art.inc):
;   m_zombie           ZB_SKIN (74,128,64), ZB_SHIRT (50,120,176), ZB_PANTS (70,68,150), ZB_HAIR (58,50,36)
;   m_pig              PG_SKIN (240,160,160), PG_SNOUT (218,128,138), PG_HOOF (78,66,64)
;   m_skeleton         SK_BONE (214,208,186)
;   m_creeper          CR_SKIN (80,180,70)
;   m_chicken          CH_FEATHER (240,238,228), CH_RED (210,38,40), CH_BEAK (240,180,40)
;   m_spider           SP_BODY (64,52,46), SP_FUR (112,92,76)
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


; ===================================================================================================
; m_skeleton
; ===================================================================================================
RAMP SK_BONE, 214, 208, 186             ; ivory bone (the old skeleton tile was a flat grey)

section .rodata
; The characters of every sk_ bitmap. Groups: base, highlight, shade, deep.
;   b B k K bone   d D dirt stains   c C x ribcage core, socket black   e E eye glint   m M moss
;   l L a A quiver and strap leather   i I buckle iron   o O arrow shaft   r R fletching   _ transparent
align 8
sk_pal:
    PALC 'b', SK_BONE_2
    PALC 'B', SK_BONE_1
    PALC 'k', SK_BONE_3
    PALC 'K', SK_BONE_4
    PALC 'd', RGBO(176, 154, 118)
    PALC 'D', RGBO(128, 108, 80)
    PALC 'c', RGBO(34, 30, 38)
    PALC 'C', RGBO(60, 54, 66)
    PALC 'x', RGBO(10, 8, 12)
    PALC 'e', RGBO(150, 200, 255)
    PALC 'E', RGBO(84, 120, 196)
    PALC 'm', RGBO(92, 122, 70)
    PALC 'M', RGBO(128, 158, 90)
    PALC 'l', AC_LEATHER_2
    PALC 'L', AC_LEATHER_1
    PALC 'a', AC_LEATHER_3
    PALC 'A', AC_LEATHER_4
    PALC 'i', AC_IRON_3
    PALC 'I', AC_IRON_1
    PALC 'o', AC_WOOD_2
    PALC 'O', AC_WOOD_4
    PALC 'r', RGBO(200, 52, 46)
    PALC 'R', RGBO(240, 96, 80)
    PALT '_'
    dq 0

    ; sk_core_front (12x22): sk_core FRONT
    SKROWS sk_core_front_rows, 12, 22
    SKROW "............"
    SKROW ".....CC....."
    SKROW "....CCCC...."
    SKROW ".....CC....."
    SKROW ".....CC....."
    SKROW "....CCCC...."
    SKROW ".....CC....."
    SKROW ".....CC....."
    SKROW "....CCCC...."
    SKROW ".....CC....."
    SKROW ".....CC....."
    SKROW "....CCCC...."
    SKROW ".....CC....."
    SKROW ".....CC....."
    SKROW "....CCCC...."
    SKROW ".....CC....."
    SKROW ".....CC....."
    SKROW "....CCCC...."
    SKROW ".....CC....."
    SKROW ".....CC....."
    SKROW "....CCCC...."
    SKROW "............"
    SKROWS_END
    align 8
    SKBMP sk_core_front, sk_core_front_rows, 12, 22, sk_pal
    ; sk_core_back (12x22): sk_core BACK
    SKROWS sk_core_back_rows, 12, 22
    SKROW ".....CC....."
    SKROW "....CCCC...."
    SKROW ".....CC....."
    SKROW "....CCCC...."
    SKROW ".....CC....."
    SKROW "....CCCC...."
    SKROW ".....CC....."
    SKROW "....CCCC...."
    SKROW ".....CC....."
    SKROW "....CCCC...."
    SKROW ".....CC....."
    SKROW "....CCCC...."
    SKROW ".....CC....."
    SKROW "....CCCC...."
    SKROW ".....CC....."
    SKROW "....CCCC...."
    SKROW ".....CC....."
    SKROW "....CCCC...."
    SKROW ".....CC....."
    SKROW "....CCCC...."
    SKROW ".....CC....."
    SKROW "....CCCC...."
    SKROWS_END
    align 8
    SKBMP sk_core_back, sk_core_back_rows, 12, 22, sk_pal
    ; sk_ribs_front (16x20): sk_ribs FRONT
    SKROWS sk_ribs_front_rows, 16, 20
    SKROW "LllaBBBBBBBBBBBB"
    SKROW "kLllabbbbbbbbbbk"
    SKROW "_LlAa_bBkk______"
    SKROW "_BLllaBbkBBBBBB_"
    SKROW "_KkLllabkKkkkkK_"
    SKROW "___Lllabk_______"
    SKROW "_BBBLlAakBBBBBB_"
    SKROW "_KkkkLIiaKkkkkK_"
    SKROW "_____Lika_______"
    SKROW "_____BLllaBBBB__"
    SKROW "__K__KKLlAakkK__"
    SKROW "_______Llla_____"
    SKROW "___BBBBbLllaB___"
    SKROW "___KkkKbkLlla___"
    SKROW "_______bkLlAa___"
    SKROW "____BBBbkBLlla__"
    SKROW "____KkKbkKkLlla_"
    SKROW "___________Llla_"
    SKROW "____________LlAa"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP sk_ribs_front, sk_ribs_front_rows, 16, 20, sk_pal
    ; sk_ribs_back (16x20): sk_ribs BACK
    SKROWS sk_ribs_back_rows, 16, 20
    SKROW "BBBBBBBBBBBBallL"
    SKROW "kbbbbbbbbbballLk"
    SKROW "_______bk__alAL_"
    SKROW "_BBBBBBkKBallLB_"
    SKROW "_KkkkkKbkallLkK_"
    SKROW "_______kKallL___"
    SKROW "_BBBBBBbalALBBB_"
    SKROW "_KkkkkKallLkkkK_"
    SKROW "_______allL_____"
    SKROW "__BBBBallLBBBB__"
    SKROW "__KkkalALKkkkK__"
    SKROW "_____allL_______"
    SKROW "___BallLkBBBB___"
    SKROW "___allLkKKkkK___"
    SKROW "___alALbk_______"
    SKROW "__allLBkKBBB____"
    SKROW "_allLkKbkKkK____"
    SKROW "_allL__kK_______"
    SKROW "alAL___bk_______"
    SKROW "________________"
    SKROWS_END
    align 8
    SKBMP sk_ribs_back, sk_ribs_back_rows, 16, 20, sk_pal
    ; sk_ribs_side_r (8x20): sk_ribs RIGHT
    SKROWS sk_ribs_side_r_rows, 8, 20
    SKROW "BBBBBBBB"
    SKROW "bbbbbbbb"
    SKROW "________"
    SKROW "BBBBBBBB"
    SKROW "KkkkkkkK"
    SKROW "________"
    SKROW "BBBBBBBB"
    SKROW "KkkkkkkK"
    SKROW "________"
    SKROW "BBBBBBBB"
    SKROW "KkkkkkkK"
    SKROW "________"
    SKROW "BBBBBBBB"
    SKROW "KkkkkkkK"
    SKROW "________"
    SKROW "BBBBBBBB"
    SKROW "KkkkkkkK"
    SKROW "________"
    SKROW "________"
    SKROW "________"
    SKROWS_END
    align 8
    SKBMP sk_ribs_side_r, sk_ribs_side_r_rows, 8, 20, sk_pal
    ; sk_ribs_side_l (8x20): sk_ribs LEFT
    SKROWS sk_ribs_side_l_rows, 8, 20
    SKROW "BBBBBBBB"
    SKROW "bbbbbbbb"
    SKROW "________"
    SKROW "BBBBBBBB"
    SKROW "KkkkkkkK"
    SKROW "________"
    SKROW "BBBBBBBB"
    SKROW "KkkkkkkK"
    SKROW "________"
    SKROW "BBBBBBBB"
    SKROW "KkkkkkkK"
    SKROW "________"
    SKROW "BBBBBBBB"
    SKROW "KkkkkkkK"
    SKROW "________"
    SKROW "llllllll"
    SKROW "llAllAll"
    SKROW "aaaaaaaa"
    SKROW "________"
    SKROW "________"
    SKROWS_END
    align 8
    SKBMP sk_ribs_side_l, sk_ribs_side_l_rows, 8, 20, sk_pal
    ; sk_ribs_top (16x8): sk_ribs TOP
    SKROWS sk_ribs_top_rows, 16, 8
    SKROW "Llla............"
    SKROW "Llla............"
    SKROW "LAla............"
    SKROW "Llla............"
    SKROW "Llla............"
    SKROW "LlAa............"
    SKROW "Llla............"
    SKROW "Llla............"
    SKROWS_END
    align 8
    SKBMP sk_ribs_top, sk_ribs_top_rows, 16, 8, sk_pal
    ; sk_spine_back (2x18): sk_spine BACK
    SKROWS sk_spine_back_rows, 2, 18
    SKROW "BK"
    SKROW "bk"
    SKROW "bk"
    SKROW "BK"
    SKROW "bk"
    SKROW "bk"
    SKROW "BK"
    SKROW "bk"
    SKROW "bk"
    SKROW "BK"
    SKROW "bk"
    SKROW "bk"
    SKROW "BK"
    SKROW "bk"
    SKROW "bk"
    SKROW "BK"
    SKROW "bk"
    SKROW "bk"
    SKROWS_END
    align 8
    SKBMP sk_spine_back, sk_spine_back_rows, 2, 18, sk_pal
    ; sk_spine_side (2x18): sk_spine RIGHT/LEFT
    SKROWS sk_spine_side_rows, 2, 18
    SKROW "bk"
    SKROW "bk"
    SKROW "bk"
    SKROW "bk"
    SKROW "bk"
    SKROW "bk"
    SKROW "bk"
    SKROW "bk"
    SKROW "bk"
    SKROW "bk"
    SKROW "bk"
    SKROW "bk"
    SKROW "bk"
    SKROW "bk"
    SKROW "bk"
    SKROW "bk"
    SKROW "bk"
    SKROW "bk"
    SKROWS_END
    align 8
    SKBMP sk_spine_side, sk_spine_side_rows, 2, 18, sk_pal
    ; sk_pelvis_front (14x4): sk_pelvis FRONT
    SKROWS sk_pelvis_front_rows, 14, 4
    SKROW "BBBBBBBBBBBBBk"
    SKROW "B.bbbkk.kbbbbk"
    SKROW "B....kKKk....k"
    SKROW "BkkkkkKKkkkkkk"
    SKROWS_END
    align 8
    SKBMP sk_pelvis_front, sk_pelvis_front_rows, 14, 4, sk_pal
    ; sk_pelvis_back (14x4): sk_pelvis BACK
    SKROWS sk_pelvis_back_rows, 14, 4
    SKROW "BBBBBBBBBBBBBB"
    SKROW ".....kKKk....."
    SKROW ".....kKKk....."
    SKROW "kkkkkkkkkkkkkk"
    SKROWS_END
    align 8
    SKBMP sk_pelvis_back, sk_pelvis_back_rows, 14, 4, sk_pal
    ; sk_pelvis_side (8x4): sk_pelvis RIGHT/LEFT
    SKROWS sk_pelvis_side_rows, 8, 4
    SKROW "BBBBBBBB"
    SKROW "...kK..."
    SKROW "...KK..."
    SKROW "kkkkkkkk"
    SKROWS_END
    align 8
    SKBMP sk_pelvis_side, sk_pelvis_side_rows, 8, 4, sk_pal
    ; sk_quiver_back (4x16): sk_quiver BACK
    SKROWS sk_quiver_back_rows, 4, 16
    SKROW "AAAA"
    SKROW "aaaa"
    SKROW "L..a"
    SKROW "LA.a"
    SKROW "L.Aa"
    SKROW "L..a"
    SKROW "LA.a"
    SKROW "LIia"
    SKROW "Liia"
    SKROW "LA.a"
    SKROW "L.Aa"
    SKROW "L..a"
    SKROW "LA.a"
    SKROW "L.Aa"
    SKROW "L..a"
    SKROW "AAAA"
    SKROWS_END
    align 8
    SKBMP sk_quiver_back, sk_quiver_back_rows, 4, 16, sk_pal
    ; sk_quiver_side (4x16): sk_quiver RIGHT/LEFT
    SKROWS sk_quiver_side_rows, 4, 16
    SKROW "AAAa"
    SKROW "aaaa"
    SKROW "...a"
    SKROW "...a"
    SKROW "...a"
    SKROW "AAAA"
    SKROW "...a"
    SKROW "...a"
    SKROW "...a"
    SKROW "...a"
    SKROW "...a"
    SKROW "...a"
    SKROW "...a"
    SKROW "...a"
    SKROW "...a"
    SKROW "AAAA"
    SKROWS_END
    align 8
    SKBMP sk_quiver_side, sk_quiver_side_rows, 4, 16, sk_pal
    ; sk_fletch_back (4x5): sk_fletch BACK
    SKROWS sk_fletch_back_rows, 4, 5
    SKROW "xRrx"
    SKROW "RrRr"
    SKROW "rRrR"
    SKROW "RrRr"
    SKROW "oOoO"
    SKROWS_END
    align 8
    SKBMP sk_fletch_back, sk_fletch_back_rows, 4, 5, sk_pal
    ; sk_fletch_front (4x5): sk_fletch FRONT
    SKROWS sk_fletch_front_rows, 4, 5
    SKROW "xrRx"
    SKROW "rRrR"
    SKROW "RrRr"
    SKROW "rRrR"
    SKROW "OoOo"
    SKROWS_END
    align 8
    SKBMP sk_fletch_front, sk_fletch_front_rows, 4, 5, sk_pal
    ; sk_fletch_side (2x5): sk_fletch RIGHT/LEFT
    SKROWS sk_fletch_side_rows, 2, 5
    SKROW "rR"
    SKROW "rR"
    SKROW "rR"
    SKROW "rR"
    SKROW "oO"
    SKROWS_END
    align 8
    SKBMP sk_fletch_side, sk_fletch_side_rows, 2, 5, sk_pal
    ; sk_skull_front (16x16): sk_skull FRONT
    SKROWS sk_skull_front_rows, 16, 16
    SKROW "BBBBBBBBBBKBBBBk"
    SKROW "BBBBBBBBBBKBBBBk"
    SKROW "B........K.....k"
    SKROW "B........k.....k"
    SKROW "B..............k"
    SKROW "B.kxxkB..kkxxk.k"
    SKROW "B.xxexB..kxexx.k"
    SKROW "B.xxExB..kxExx.k"
    SKROW "B.kxxkB..kkxxk.k"
    SKROW "B.kkkk.xx.kkkk.k"
    SKROW "B.dd..kxxk..d..k"
    SKROW "Bk...........dKk"
    SKROW "BkBxBBxBBxBBxBKk"
    SKROW "BkxxxxxxxxxxxxKk"
    SKROW "BkbxbbxbbxbbxbKk"
    SKROW "kkkkkkkkkkkkkkkk"
    SKROWS_END
    align 8
    SKBMP sk_skull_front, sk_skull_front_rows, 16, 16, sk_pal
    ; sk_skull_top (16x16): sk_skull TOP
    SKROWS sk_skull_top_rows, 16, 16
    SKROW ".......K........"
    SKROW ".......K........"
    SKROW "...mMm..K......."
    SKROW "..mmmmm.K......."
    SKROW "...mMm.K........"
    SKROW ".......K........"
    SKROW "........K......."
    SKROW "........K......."
    SKROW ".......K........"
    SKROW ".......K........"
    SKROW "...kkkkkKkkkk..."
    SKROW "........K...mmm."
    SKROW ".......K....mmm."
    SKROW ".......K.....M.."
    SKROW "........K......."
    SKROW "........K......."
    SKROWS_END
    align 8
    SKBMP sk_skull_top, sk_skull_top_rows, 16, 16, sk_pal
    ; sk_skull_back (16x16): sk_skull BACK
    SKROWS sk_skull_back_rows, 16, 16
    SKROW "................"
    SKROW "................"
    SKROW ".....K.........."
    SKROW ".....K.........."
    SKROW "......k........."
    SKROW "......K.....d..."
    SKROW ".......k........"
    SKROW "................"
    SKROW "................"
    SKROW "................"
    SKROW ".d...d.........."
    SKROW "................"
    SKROW "........d......."
    SKROW ".......kk....d.."
    SKROW ".d.....KK......."
    SKROW ".......KK......."
    SKROWS_END
    align 8
    SKBMP sk_skull_back, sk_skull_back_rows, 16, 16, sk_pal
    ; sk_skull_side_r (16x16): sk_skull RIGHT
    SKROWS sk_skull_side_r_rows, 16, 16
    SKROW "B..............k"
    SKROW "B..............k"
    SKROW "B..K...........k"
    SKROW "B...K..........k"
    SKROW "B...k..........k"
    SKROW "B..............k"
    SKROW "B......kkkk....k"
    SKROW "B.......xx.....k"
    SKROW "B.......xx.....k"
    SKROW "B......kkkk....k"
    SKROW "B.......BBBBBBBk"
    SKROW "B.......kkkkkkkk"
    SKROW "B..............k"
    SKROW "B..............k"
    SKROW "B..............k"
    SKROW "B..............k"
    SKROWS_END
    align 8
    SKBMP sk_skull_side_r, sk_skull_side_r_rows, 16, 16, sk_pal
    ; sk_skull_side_l (16x16): sk_skull LEFT
    SKROWS sk_skull_side_l_rows, 16, 16
    SKROW "k..............B"
    SKROW "k..............B"
    SKROW "k...........K..B"
    SKROW "k..........K...B"
    SKROW "k..........k...B"
    SKROW "k..............B"
    SKROW "k....kkkk......B"
    SKROW "k.....xx.......B"
    SKROW "k.....xx.......B"
    SKROW "k....kkkk......B"
    SKROW "kBBBBBBB.......B"
    SKROW "kkkkkkkk.......B"
    SKROW "k..............B"
    SKROW "k..............B"
    SKROW "k..............B"
    SKROW "k..............B"
    SKROWS_END
    align 8
    SKBMP sk_skull_side_l, sk_skull_side_l_rows, 16, 16, sk_pal
    ; sk_teeth_front (12x3): sk_teeth FRONT
    SKROWS sk_teeth_front_rows, 12, 3
    SKROW "BBxBBxxBBxxB"
    SKROW "kxxxxxxxxxxk"
    SKROW "bbxbbbbbbxbb"
    SKROWS_END
    align 8
    SKBMP sk_teeth_front, sk_teeth_front_rows, 12, 3, sk_pal
    ; sk_cheek_front (3x2): sk_cheek_r FRONT
    SKROWS sk_cheek_front_rows, 3, 2
    SKROW "BBb"
    SKROW "bkk"
    SKROWS_END
    align 8
    SKBMP sk_cheek_front, sk_cheek_front_rows, 3, 2, sk_pal
    ; sk_leg_front (4x19): sk_leg_l FRONT
    SKROWS sk_leg_front_rows, 4, 19
    SKROW "kkkk"
    SKROW "bbbb"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "Bk.k"
    SKROW "B..k"
    SKROW "BkBk"
    SKROW "B..k"
    SKROW "BK.k"
    SKROW "Bk.k"
    SKROW "B..k"
    SKROW "B.Bk"
    SKROW "BBBk"
    SKROW "BB.k"
    SKROW "B..k"
    SKROW "Bd.k"
    SKROW "B..k"
    SKROW "kkkk"
    SKROWS_END
    align 8
    SKBMP sk_leg_front, sk_leg_front_rows, 4, 19, sk_pal
    ; sk_leg_back (4x19): sk_leg_l BACK
    SKROWS sk_leg_back_rows, 4, 19
    SKROW "kkkk"
    SKROW "bbbb"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "BB.k"
    SKROW "BB.k"
    SKROW "BB.k"
    SKROW "BBkk"
    SKROW "Bkkk"
    SKROW "Bk.k"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "B.kk"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "Bddk"
    SKROW "kkkk"
    SKROWS_END
    align 8
    SKBMP sk_leg_back, sk_leg_back_rows, 4, 19, sk_pal
    ; sk_leg_side (4x19): sk_leg_l RIGHT/LEFT
    SKROWS sk_leg_side_rows, 4, 19
    SKROW "kkkk"
    SKROW "bbbb"
    SKROW "B.kk"
    SKROW "B.kk"
    SKROW "B.kk"
    SKROW "B.kk"
    SKROW "B..k"
    SKROW "B.kk"
    SKROW "B..k"
    SKROW "BB.k"
    SKROW "BB.k"
    SKROW "BBBk"
    SKROW "B.Bk"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "B.dk"
    SKROW "kkkk"
    SKROWS_END
    align 8
    SKBMP sk_leg_side, sk_leg_side_rows, 4, 19, sk_pal
    ; sk_knob_side (6x4): sk_hip_l FRONT/BACK/RIGHT/LEFT, sk_knee_l FRONT/BACK/RIGHT/LEFT, ...
    SKROWS sk_knob_side_rows, 6, 4
    SKROW "BBBBBb"
    SKROW "B....k"
    SKROW "B....k"
    SKROW "bkkkkK"
    SKROWS_END
    align 8
    SKBMP sk_knob_side, sk_knob_side_rows, 6, 4, sk_pal
    ; sk_foot_front (6x3): sk_foot_l FRONT
    SKROWS sk_foot_front_rows, 6, 3
    SKROW "BbBbBb"
    SKROW "bkbkbk"
    SKROW "kkkkkK"
    SKROWS_END
    align 8
    SKBMP sk_foot_front, sk_foot_front_rows, 6, 3, sk_pal
    ; sk_foot_top (6x7): sk_foot_l TOP
    SKROWS sk_foot_top_rows, 6, 7
    SKROW ".kdk.d"
    SKROW ".k.k.."
    SKROW ".k.k.."
    SKROW "dk.k.d"
    SKROW ".k.k.."
    SKROW "kkkkkk"
    SKROW "KKKKKK"
    SKROWS_END
    align 8
    SKBMP sk_foot_top, sk_foot_top_rows, 6, 7, sk_pal
    ; sk_foot_side (7x3): sk_foot_l RIGHT
    SKROWS sk_foot_side_rows, 7, 3
    SKROW "kbbbbBB"
    SKROW "kkbbbbb"
    SKROW "kkkkkkk"
    SKROWS_END
    align 8
    SKBMP sk_foot_side, sk_foot_side_rows, 7, 3, sk_pal
    ; sk_foot_side_l (7x3): sk_foot_l LEFT
    SKROWS sk_foot_side_l_rows, 7, 3
    SKROW "BBbbbbk"
    SKROW "bbbbbkk"
    SKROW "kkkkkkk"
    SKROWS_END
    align 8
    SKBMP sk_foot_side_l, sk_foot_side_l_rows, 7, 3, sk_pal
    ; sk_arm_front (4x17): sk_arm_l FRONT
    SKROWS sk_arm_front_rows, 4, 17
    SKROW "kkkk"
    SKROW "bbbb"
    SKROW "B..k"
    SKROW "BBBk"
    SKROW "BBkk"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "B.Kk"
    SKROW "B.kk"
    SKROW "B.kk"
    SKROW "B..k"
    SKROW "Bk.k"
    SKROW "BkBk"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "kkkk"
    SKROWS_END
    align 8
    SKBMP sk_arm_front, sk_arm_front_rows, 4, 17, sk_pal
    ; sk_arm_back (4x17): sk_arm_l BACK
    SKROWS sk_arm_back_rows, 4, 17
    SKROW "kkkk"
    SKROW "bbbb"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "BB.k"
    SKROW "B..k"
    SKROW "B.kk"
    SKROW "B.kk"
    SKROW "B.kk"
    SKROW "B.kk"
    SKROW "Bk.k"
    SKROW "B..k"
    SKROW "BB.k"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "kkkk"
    SKROWS_END
    align 8
    SKBMP sk_arm_back, sk_arm_back_rows, 4, 17, sk_pal
    ; sk_arm_side (4x17): sk_arm_l RIGHT/LEFT
    SKROWS sk_arm_side_rows, 4, 17
    SKROW "kkkk"
    SKROW "bbbb"
    SKROW "B..k"
    SKROW "Bk.k"
    SKROW "BB.k"
    SKROW "BB.k"
    SKROW "B.kk"
    SKROW "B.Bk"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "B.kk"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "kkkk"
    SKROWS_END
    align 8
    SKBMP sk_arm_side, sk_arm_side_rows, 4, 17, sk_pal
    ; sk_hand_front (4x4): sk_hand_l FRONT
    SKROWS sk_hand_front_rows, 4, 4
    SKROW "BbBb"
    SKROW "bkbk"
    SKROW "bbbb"
    SKROW "kkkK"
    SKROWS_END
    align 8
    SKBMP sk_hand_front, sk_hand_front_rows, 4, 4, sk_pal
    ; sk_hand_back (4x4): sk_hand_l BACK
    SKROWS sk_hand_back_rows, 4, 4
    SKROW "BbBb"
    SKROW "bbbb"
    SKROW "bkbk"
    SKROW "kkkK"
    SKROWS_END
    align 8
    SKBMP sk_hand_back, sk_hand_back_rows, 4, 4, sk_pal
    ; sk_hand_side (4x4): sk_hand_l RIGHT/LEFT
    SKROWS sk_hand_side_rows, 4, 4
    SKROW "Bbbk"
    SKROW "bbbk"
    SKROW "bbkk"
    SKROW "kkkK"
    SKROWS_END
    align 8
    SKBMP sk_hand_side, sk_hand_side_rows, 4, 4, sk_pal

section .data
SKMODEL_BEGIN m_skeleton, 32, BOW, 10, 26, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART sk_core, -6, 26, -3, 12, 22, 6, 0, 0               ; dark core of the chest, seen between the ribs
    PART sk_ribs, -8, 28, -4, 16, 20, 8, 4, SKPF_CUTOUT     ; ribcage overlay: clavicle, sternum, five ribs, a bandolier
    PART sk_spine, -1, 28, 4, 2, 18, 2, 0, 0                ; spine: vertebrae ridge down the back
    PART sk_pelvis, -7, 24, -4, 14, 4, 8, 0, 0              ; pelvis: hip bone
    PART sk_quiver, 2, 27, 5, 4, 16, 4, 0, 0                ; leather quiver on the right shoulder blade
    PART sk_fletch, 2, 43, 6, 4, 5, 2, 0, 0                 ; arrow ends sticking out of the quiver
    SKBONE BK_HEAD, 0, 0, 0.00
    PART sk_skull, -8, 48, -8, 16, 16, 16, 0, 0             ; skull: sockets with a cold glint, nose hole, cracks, moss
    PART sk_brow, -6, 59, -9, 12, 2, 1, 0, 0                ; brow ridge over the sockets
    PART sk_teeth, -6, 49, -9, 12, 3, 1, 0, 0               ; teeth: two rows with a dark grin between, one chipped
    PART sk_cheek_r, 4, 52, -9, 3, 2, 1, 0, 0               ; cheekbones
    PART_AS sk_cheek_l, sk_cheek_r, -7, 52, -9, 0, 0
    SKBONE BK_LLEG, 24, 0, 1.00
    PART sk_leg_l, -6, 3, -2, 4, 19, 4, 0, 0                ; shin and thigh bone
    PART sk_hip_l, -7, 20, -3, 6, 4, 6, 0, 0                ; hip joint knob
    PART sk_knee_l, -7, 10, -3, 6, 4, 6, 0, 0               ; knee joint knob
    PART sk_foot_l, -7, 0, -5, 6, 3, 7, 0, 0                ; foot bones
    SKBONE BK_RLEG, 24, 0, -1.00
    PART_AS sk_leg_r, sk_leg_l, 2, 3, -2, 0, 0
    PART_AS sk_hip_r, sk_hip_l, 1, 20, -3, 0, 0
    PART_AS sk_knee_r, sk_knee_l, 1, 10, -3, 0, 0
    PART_AS sk_foot_r, sk_foot_l, 1, 0, -5, 0, 0
    SKBONE BK_LARM, 46, 0, -1.00
    PART sk_arm_l, -12, 28, -2, 4, 17, 4, 0, 0              ; arm bone
    PART sk_shoulder_l, -13, 43, -3, 6, 4, 6, 0, 0          ; shoulder joint knob
    PART sk_elbow_l, -13, 34, -3, 6, 4, 6, 0, 0             ; elbow joint knob
    PART sk_hand_l, -12, 24, -2, 4, 4, 4, 0, 0              ; bony hand
    SKBONE BK_RARM, 46, 0, 1.00
    PART_AS sk_arm_r, sk_arm_l, 8, 28, -2, 0, 0
    PART_AS sk_shoulder_r, sk_shoulder_l, 7, 43, -3, 0, 0
    PART_AS sk_elbow_r, sk_elbow_l, 7, 34, -3, 0, 0
    PART_AS sk_hand_r, sk_hand_l, 8, 24, -2, 0, 0
SKMODEL_PAINT
    ; --- sk_core: the dark chest behind the ribs; a faint spine and sternum shadow
    SK_FILL sk_core, SKM_ALL, RGBO(34, 30, 38), 7
    SK_BMP sk_core, SKF_FRONT, 0, 0, sk_core_front
    SK_BMP sk_core, SKF_BACK, 0, 0, sk_core_back
    SK_GRAD sk_core, SKM_SIDES, 272, 224
    ; --- sk_ribs: bone cutout over the core; the bandolier crosses front and back, the sides show the rib ends
    SK_FILL sk_ribs, SKM_ALL, SK_BONE_2, 15
    SK_BMP sk_ribs, SKF_FRONT, 0, 0, sk_ribs_front
    SK_BMP sk_ribs, SKF_BACK, 0, 0, sk_ribs_back
    SK_BMP sk_ribs, SKF_RIGHT, 0, 0, sk_ribs_side_r
    SK_BMP sk_ribs, SKF_LEFT, 0, 0, sk_ribs_side_l
    SK_BMP sk_ribs, SKF_TOP, 0, 0, sk_ribs_top
    SK_RECT sk_ribs, SKF_BOTTOM, 0, 0, 16, 8, SK_BONE_4, 0
    SK_GRAD sk_ribs, SKM_SIDES, 272, 224
    ; --- sk_spine, sk_pelvis
    SK_FILL sk_spine, SKM_ALL, SK_BONE_2, 15
    SK_BMP sk_spine, SKF_BACK, 0, 0, sk_spine_back
    SK_BMP sk_spine, SKF_RIGHT, 0, 0, sk_spine_side
    SK_BMP sk_spine, SKF_LEFT, 0, 0, sk_spine_side
    SK_RECT sk_spine, SKF_FRONT, 0, 0, 2, 18, SK_BONE_3, 0
    SK_RECT sk_spine, SKF_TOP, 0, 0, 2, 2, SK_BONE_1, 0
    SK_RECT sk_spine, SKF_BOTTOM, 0, 0, 2, 2, SK_BONE_4, 0
    SK_FILL sk_pelvis, SKM_ALL, SK_BONE_2, 15
    SK_BMP sk_pelvis, SKF_FRONT, 0, 0, sk_pelvis_front
    SK_BMP sk_pelvis, SKF_BACK, 0, 0, sk_pelvis_back
    SK_GRAD sk_pelvis, SKM_SIDES, 272, 224
    SK_BMP sk_pelvis, SKF_RIGHT, 0, 0, sk_pelvis_side
    SK_BMP sk_pelvis, SKF_LEFT, 0, 0, sk_pelvis_side
    SK_RECT sk_pelvis, SKF_BOTTOM, 0, 0, 14, 8, SK_BONE_4, 0
    ; --- sk_quiver: stitched leather with a rim and a buckle; sk_fletch: the arrow ends
    SK_FILL sk_quiver, SKM_ALL, AC_LEATHER_2, 15
    SK_BMP sk_quiver, SKF_BACK, 0, 0, sk_quiver_back
    SK_BMP sk_quiver, SKF_RIGHT, 0, 0, sk_quiver_side
    SK_BMP sk_quiver, SKF_LEFT, 0, 0, sk_quiver_side
    SK_RECT sk_quiver, SKF_TOP, 0, 0, 4, 4, RGBO(24, 16, 12), 0
    SK_RECT sk_quiver, SKF_BOTTOM, 0, 0, 4, 4, AC_LEATHER_4, 0
    SK_GRAD sk_quiver, SKM_SIDES, 272, 224
    SK_FILL sk_fletch, SKM_ALL, RGBO(24, 16, 12), 0
    SK_BMP sk_fletch, SKF_BACK, 0, 0, sk_fletch_back
    SK_BMP sk_fletch, SKF_FRONT, 0, 0, sk_fletch_front
    SK_BMP sk_fletch, SKF_RIGHT, 0, 0, sk_fletch_side
    SK_BMP sk_fletch, SKF_LEFT, 0, 0, sk_fletch_side
    SK_RECT sk_fletch, SKF_TOP, 0, 0, 4, 2, RGBO(240, 96, 80), 0
    SK_RECT sk_fletch, SKF_BOTTOM, 0, 0, 4, 2, AC_WOOD_4, 0
    ; --- sk_skull
    SK_FILL sk_skull, SKM_ALL, SK_BONE_2, 15
    SK_GRAD sk_skull, SKM_SIDES, 272, 224
    SK_BMP sk_skull, SKF_FRONT, 0, 0, sk_skull_front
    SK_BMP sk_skull, SKF_TOP, 0, 0, sk_skull_top
    SK_BMP sk_skull, SKF_BACK, 0, 0, sk_skull_back
    SK_BMP sk_skull, SKF_RIGHT, 0, 0, sk_skull_side_r
    SK_BMP sk_skull, SKF_LEFT, 0, 0, sk_skull_side_l
    SK_RECT sk_skull, SKF_BOTTOM, 0, 0, 16, 16, SK_BONE_4, 0
    SK_RECT sk_skull, SKF_BOTTOM, 6, 4, 4, 6, RGBO(10, 8, 12), 0
    ; --- sk_brow, sk_teeth, sk_cheek_r (shared with sk_cheek_l)
    SK_FILL sk_brow, SKM_ALL, SK_BONE_2, 15
    SK_RECT sk_brow, SKF_FRONT, 0, 0, 12, 1, SK_BONE_1, 0
    SK_RECT sk_brow, SKF_FRONT, 0, 1, 12, 1, SK_BONE_4, 0
    SK_RECT sk_brow, SKF_TOP, 0, 0, 12, 1, SK_BONE_1, 0
    SK_RECT sk_brow, SKF_BOTTOM, 0, 0, 12, 1, SK_BONE_4, 0
    SK_FILL sk_teeth, SKM_ALL, SK_BONE_2, 7
    SK_BMP sk_teeth, SKF_FRONT, 0, 0, sk_teeth_front
    SK_RECT sk_teeth, SKF_TOP, 0, 0, 12, 1, SK_BONE_3, 0
    SK_RECT sk_teeth, SKF_BOTTOM, 0, 0, 12, 1, SK_BONE_4, 0
    SK_FILL sk_cheek_r, SKM_ALL, SK_BONE_2, 7
    SK_BMP sk_cheek_r, SKF_FRONT, 0, 0, sk_cheek_front
    SK_RECT sk_cheek_r, SKF_TOP, 0, 0, 3, 1, SK_BONE_1, 0
    SK_RECT sk_cheek_r, SKF_BOTTOM, 0, 0, 3, 1, SK_BONE_4, 0
    ; --- sk_leg_l (shared with sk_leg_r): bone shaft; sk_hip_l / sk_knee_l: joint knobs; sk_foot_l: foot bones
    SK_FILL sk_leg_l, SKM_ALL, SK_BONE_2, 15
    SK_BMP sk_leg_l, SKF_FRONT, 0, 0, sk_leg_front
    SK_BMP sk_leg_l, SKF_BACK, 0, 0, sk_leg_back
    SK_BMP sk_leg_l, SKF_RIGHT, 0, 0, sk_leg_side
    SK_BMP sk_leg_l, SKF_LEFT, 0, 0, sk_leg_side
    SK_RECT sk_leg_l, SKF_TOP, 0, 0, 4, 4, SK_BONE_3, 0
    SK_RECT sk_leg_l, SKF_BOTTOM, 0, 0, 4, 4, SK_BONE_4, 0
    SK_GRAD sk_leg_l, SKM_SIDES, 272, 224
    SK_FILL sk_hip_l, SKM_ALL, SK_BONE_2, 15
    SK_BMP sk_hip_l, SKF_FRONT, 0, 0, sk_knob_side
    SK_BMP sk_hip_l, SKF_BACK, 0, 0, sk_knob_side
    SK_BMP sk_hip_l, SKF_RIGHT, 0, 0, sk_knob_side
    SK_BMP sk_hip_l, SKF_LEFT, 0, 0, sk_knob_side
    SK_RECT sk_hip_l, SKF_TOP, 0, 0, 6, 6, SK_BONE_2, 15
    SK_RECT sk_hip_l, SKF_TOP, 0, 0, 6, 1, SK_BONE_1, 0
    SK_RECT sk_hip_l, SKF_BOTTOM, 0, 0, 6, 6, SK_BONE_4, 0
    SK_GRAD sk_hip_l, SKM_SIDES, 272, 224
    SK_FILL sk_knee_l, SKM_ALL, SK_BONE_2, 15
    SK_BMP sk_knee_l, SKF_FRONT, 0, 0, sk_knob_side
    SK_BMP sk_knee_l, SKF_BACK, 0, 0, sk_knob_side
    SK_BMP sk_knee_l, SKF_RIGHT, 0, 0, sk_knob_side
    SK_BMP sk_knee_l, SKF_LEFT, 0, 0, sk_knob_side
    SK_RECT sk_knee_l, SKF_TOP, 0, 0, 6, 6, SK_BONE_2, 15
    SK_RECT sk_knee_l, SKF_TOP, 0, 0, 6, 1, SK_BONE_1, 0
    SK_RECT sk_knee_l, SKF_BOTTOM, 0, 0, 6, 6, SK_BONE_4, 0
    SK_GRAD sk_knee_l, SKM_SIDES, 272, 224
    SK_FILL sk_foot_l, SKM_ALL, SK_BONE_2, 15
    SK_BMP sk_foot_l, SKF_FRONT, 0, 0, sk_foot_front
    SK_BMP sk_foot_l, SKF_TOP, 0, 0, sk_foot_top
    SK_BMP sk_foot_l, SKF_RIGHT, 0, 0, sk_foot_side
    SK_BMP sk_foot_l, SKF_LEFT, 0, 0, sk_foot_side_l
    SK_RECT sk_foot_l, SKF_BACK, 0, 0, 6, 3, SK_BONE_3, 0
    SK_RECT sk_foot_l, SKF_BOTTOM, 0, 0, 6, 7, SK_BONE_4, 0
    ; --- sk_arm_l (shared with sk_arm_r): bone; sk_shoulder_l / sk_elbow_l: knobs; sk_hand_l: finger bones
    SK_FILL sk_arm_l, SKM_ALL, SK_BONE_2, 15
    SK_BMP sk_arm_l, SKF_FRONT, 0, 0, sk_arm_front
    SK_BMP sk_arm_l, SKF_BACK, 0, 0, sk_arm_back
    SK_BMP sk_arm_l, SKF_RIGHT, 0, 0, sk_arm_side
    SK_BMP sk_arm_l, SKF_LEFT, 0, 0, sk_arm_side
    SK_RECT sk_arm_l, SKF_TOP, 0, 0, 4, 4, SK_BONE_3, 0
    SK_RECT sk_arm_l, SKF_BOTTOM, 0, 0, 4, 4, SK_BONE_4, 0
    SK_GRAD sk_arm_l, SKM_SIDES, 272, 224
    SK_FILL sk_shoulder_l, SKM_ALL, SK_BONE_2, 15
    SK_BMP sk_shoulder_l, SKF_FRONT, 0, 0, sk_knob_side
    SK_BMP sk_shoulder_l, SKF_BACK, 0, 0, sk_knob_side
    SK_BMP sk_shoulder_l, SKF_RIGHT, 0, 0, sk_knob_side
    SK_BMP sk_shoulder_l, SKF_LEFT, 0, 0, sk_knob_side
    SK_RECT sk_shoulder_l, SKF_TOP, 0, 0, 6, 6, SK_BONE_2, 15
    SK_RECT sk_shoulder_l, SKF_TOP, 0, 0, 6, 1, SK_BONE_1, 0
    SK_RECT sk_shoulder_l, SKF_BOTTOM, 0, 0, 6, 6, SK_BONE_4, 0
    SK_GRAD sk_shoulder_l, SKM_SIDES, 272, 224
    SK_FILL sk_elbow_l, SKM_ALL, SK_BONE_2, 15
    SK_BMP sk_elbow_l, SKF_FRONT, 0, 0, sk_knob_side
    SK_BMP sk_elbow_l, SKF_BACK, 0, 0, sk_knob_side
    SK_BMP sk_elbow_l, SKF_RIGHT, 0, 0, sk_knob_side
    SK_BMP sk_elbow_l, SKF_LEFT, 0, 0, sk_knob_side
    SK_RECT sk_elbow_l, SKF_TOP, 0, 0, 6, 6, SK_BONE_2, 15
    SK_RECT sk_elbow_l, SKF_TOP, 0, 0, 6, 1, SK_BONE_1, 0
    SK_RECT sk_elbow_l, SKF_BOTTOM, 0, 0, 6, 6, SK_BONE_4, 0
    SK_GRAD sk_elbow_l, SKM_SIDES, 272, 224
    SK_FILL sk_hand_l, SKM_ALL, SK_BONE_2, 15
    SK_BMP sk_hand_l, SKF_FRONT, 0, 0, sk_hand_front
    SK_BMP sk_hand_l, SKF_BACK, 0, 0, sk_hand_back
    SK_BMP sk_hand_l, SKF_RIGHT, 0, 0, sk_hand_side
    SK_BMP sk_hand_l, SKF_LEFT, 0, 0, sk_hand_side
    SK_RECT sk_hand_l, SKF_TOP, 0, 0, 4, 4, SK_BONE_3, 0
    SK_RECT sk_hand_l, SKF_BOTTOM, 0, 0, 4, 4, SK_BONE_4, 0
SKMODEL_END

; ===================================================================================================
; m_creeper
; ===================================================================================================
RAMP CR_SKIN, 80, 180, 70               ; creeper green (the old creeper tile)

section .rodata
; The characters of every cr_ bitmap. Groups: base, highlight, shade, deep.
;   g G h H creeper green   l L dark leaves   y Y light leaves   x X face black and its shadow rim   _ transparent
align 8
cr_pal:
    PALC 'g', CR_SKIN_2
    PALC 'G', CR_SKIN_1
    PALC 'h', CR_SKIN_3
    PALC 'H', CR_SKIN_4
    PALC 'l', RGBO(38, 102, 42)
    PALC 'L', RGBO(24, 72, 30)
    PALC 'y', RGBO(150, 218, 104)
    PALC 'Y', RGBO(196, 240, 138)
    PALC 'x', RGBO(14, 18, 14)
    PALC 'X', RGBO(30, 50, 32)
    PALT '_'
    dq 0

    ; cr_body_front (16x24): cr_body FRONT
    SKROWS cr_body_front_rows, 16, 24
    SKROW "GGGGGGGGGGGGGGGG"
    SKROW "................"
    SKROW "......lll......."
    SKROW "......lLl..l...."
    SKROW "..l...ll..lLl..."
    SKROW ".lLl......lLl.l."
    SKROW "..l.......lLl.Ll"
    SKROW "...........lYlLl"
    SKROW "............ylL."
    SKROW "llll........llll"
    SKROW "..lLl...l..llLl."
    SKROW "...l..LLl..lLl.."
    SKROW ".......lll......"
    SKROW "........lLL....."
    SKROW "................"
    SKROW "...............l"
    SKROW "..yLl.........ll"
    SKROW ".yyyLlll......ll"
    SKROW "..y.lLl..l......"
    SKROW "........lLlyyy.."
    SKROW ".........lyyy..."
    SKROW ".l.........yy.ll"
    SKROW "hhhhhhhhhhhhhhhh"
    SKROW "HHHHHHHHHHHHHHHH"
    SKROWS_END
    align 8
    SKBMP cr_body_front, cr_body_front_rows, 16, 24, cr_pal
    ; cr_body_back (16x24): cr_body BACK
    SKROWS cr_body_back_rows, 16, 24
    SKROW "GGGGGGGGGGGGGGGG"
    SKROW "...........lll.."
    SKROW "................"
    SKROW "Yy....lll......."
    SKROW "yYy..lllll......"
    SKROW ".yY...lll......."
    SKROW "................"
    SKROW "........l.l....."
    SKROW "..ll....llLl.Yy."
    SKROW ".lllylL...l..yYy"
    SKROW ".lllYyl.......yY"
    SKROW "..lyyl.........."
    SKROW ".lLl............"
    SKROW "..l.y..........."
    SKROW "....y........yyy"
    SKROW "..Yyy..........."
    SKROW "..yYy..........."
    SKROW "l..yY..........."
    SKROW "Ll.....lllLll..."
    SKROW "l.....lLlllLl..."
    SKROW ".l.....ll.llLl.."
    SKROW ".Ll............."
    SKROW "hhhhhhhhhhhhhhhh"
    SKROW "HHHHHHHHHHHHHHHH"
    SKROWS_END
    align 8
    SKBMP cr_body_back, cr_body_back_rows, 16, 24, cr_pal
    ; cr_body_right (8x24): cr_body RIGHT
    SKROWS cr_body_right_rows, 8, 24
    SKROW "GGGGGGGG"
    SKROW "Llyyy..."
    SKROW "ll......"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "....l..."
    SKROW ".lLll..."
    SKROW "llllllLl"
    SKROW "LllllllL"
    SKROW "..llLl.l"
    SKROW "....ll.."
    SKROW "........"
    SKROW "........"
    SKROW ".yyy...."
    SKROW "........"
    SKROW "........"
    SKROW "hhhhhhhh"
    SKROW "HHHHHHHH"
    SKROWS_END
    align 8
    SKBMP cr_body_right, cr_body_right_rows, 8, 24, cr_pal
    ; cr_body_left (8x24): cr_body LEFT
    SKROWS cr_body_left_rows, 8, 24
    SKROW "GGGGGGGG"
    SKROW "...lll.."
    SKROW "....l..."
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "....ll.."
    SKROW "Ll.lLl.."
    SKROW "lLllll.."
    SKROW ".lL....."
    SKROW "..L....."
    SKROW ".lLll.ly"
    SKROW "lLllllyY"
    SKROW "Ll.lllyy"
    SKROW "L.....Ll"
    SKROW "l..l..l."
    SKROW "lllLl..."
    SKROW "l..l...."
    SKROW "........"
    SKROW "hhhhhhhh"
    SKROW "HHHHHHHH"
    SKROWS_END
    align 8
    SKBMP cr_body_left, cr_body_left_rows, 8, 24, cr_pal
    ; cr_body_top (16x8): cr_body TOP
    SKROWS cr_body_top_rows, 16, 8
    SKROW "y.......lL......"
    SKROW "yLLl....lLl....."
    SKROW "lllLl.lllll....."
    SKROW "lLllLL..lLlLL..."
    SKROW "lll......lLl.l.."
    SKROW "......yyLLl..l.."
    SKROW "......yYy....l.."
    SKROW "......yyy......."
    SKROWS_END
    align 8
    SKBMP cr_body_top, cr_body_top_rows, 16, 8, cr_pal
    ; cr_clump_a_front (5x5): cr_clump_a FRONT
    SKROWS cr_clump_a_front_rows, 5, 5
    SKROW "_..Y_"
    SKROW "LyyyY"
    SKROW ".ly.."
    SKROW "..Yl."
    SKROW "_..._"
    SKROWS_END
    align 8
    SKBMP cr_clump_a_front, cr_clump_a_front_rows, 5, 5, cr_pal
    ; cr_clump_a_back (5x5): cr_clump_a BACK
    SKROWS cr_clump_a_back_rows, 5, 5
    SKROW "_Y.._"
    SKROW "YyyyL"
    SKROW "..yl."
    SKROW ".lY.."
    SKROW "_..._"
    SKROWS_END
    align 8
    SKBMP cr_clump_a_back, cr_clump_a_back_rows, 5, 5, cr_pal
    ; cr_clump_a_side (2x5): cr_clump_a RIGHT/LEFT
    SKROWS cr_clump_a_side_rows, 2, 5
    SKROW "yy"
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROW "LL"
    SKROWS_END
    align 8
    SKBMP cr_clump_a_side, cr_clump_a_side_rows, 2, 5, cr_pal
    ; cr_clump_b_front (4x4): cr_clump_b FRONT
    SKROWS cr_clump_b_front_rows, 4, 4
    SKROW "_.Y_"
    SKROW ".yy."
    SKROW "lyy."
    SKROW "_yL_"
    SKROWS_END
    align 8
    SKBMP cr_clump_b_front, cr_clump_b_front_rows, 4, 4, cr_pal
    ; cr_clump_b_back (4x4): cr_clump_b BACK
    SKROWS cr_clump_b_back_rows, 4, 4
    SKROW "_Y._"
    SKROW ".yy."
    SKROW ".yyl"
    SKROW "_Ly_"
    SKROWS_END
    align 8
    SKBMP cr_clump_b_back, cr_clump_b_back_rows, 4, 4, cr_pal
    ; cr_clump_b_side (2x4): cr_clump_b RIGHT/LEFT
    SKROWS cr_clump_b_side_rows, 2, 4
    SKROW "yy"
    SKROW ".."
    SKROW ".."
    SKROW "LL"
    SKROWS_END
    align 8
    SKBMP cr_clump_b_side, cr_clump_b_side_rows, 2, 4, cr_pal
    ; cr_face (16x16): cr_head FRONT
    SKROWS cr_face_rows, 16, 16
    SKROW "GGGGGGGGGGGGGGGG"
    SKROW "............llll"
    SKROW "y...........lllL"
    SKROW "y.XXXXXhhXXXXXlL"
    SKROW "y.XxxxXhhXxxxXyl"
    SKROW "..XxxxXhhXxxxXyy"
    SKROW ".lXxxxXXXXxxxXh."
    SKROW ".lXXXXxxxxXXXX.."
    SKROW ".hhhhXxxxxXhhhy."
    SKROW "..hhXXxxxxXXhh.."
    SKROW "...hXxxxxxxXh..."
    SKROW "...hXxxXXxxXh..."
    SKROW "...lXxxXXxxX...."
    SKROW ".lLlXXXXXXXX...."
    SKROW ".lLl.ll........."
    SKROW "hhhhhhhhhhhhhhhh"
    SKROWS_END
    align 8
    SKBMP cr_face, cr_face_rows, 16, 16, cr_pal
    ; cr_head_top (16x16): cr_head TOP
    SKROWS cr_head_top_rows, 16, 16
    SKROW "...........llllL"
    SKROW "...........lllll"
    SKROW "..........llll.."
    SKROW ".y........lll..."
    SKROW "yYy.......lll..l"
    SKROW ".y...yyy..lLl.ll"
    SKROW "..Ll.......l...l"
    SKROW "..lLl..........y"
    SKROW "...lL...lL.....y"
    SKROW "........lL.....y"
    SKROW "........lyl....."
    SKROW "........yyl....."
    SKROW ".........yl....."
    SKROW "L....l.........."
    SKROW "Ll..ll.lll......"
    SKROW "Ll...l.lLl......"
    SKROWS_END
    align 8
    SKBMP cr_head_top, cr_head_top_rows, 16, 16, cr_pal
    ; cr_head_back (16x16): cr_head BACK
    SKROWS cr_head_back_rows, 16, 16
    SKROW ".....lll........"
    SKROW "................"
    SKROW "..............l."
    SKROW "...l.....y...lll"
    SKROW "..lll...yY...lll"
    SKROW ".lLl..YyYy...lLl"
    SKROW "lLllLyYyy...ylll"
    SKROW "Ll.lLlyyy..YlLly"
    SKROW "...lLlYyy..yYlyY"
    SKROW "...lLlYyyy..yY.."
    SKROW "....Ll..y......."
    SKROW "..y.......l....."
    SKROW ".yll.....lLl...."
    SKROW "..lll.....l....."
    SKROW "...l............"
    SKROW "................"
    SKROWS_END
    align 8
    SKBMP cr_head_back, cr_head_back_rows, 16, 16, cr_pal
    ; cr_head_side_r (16x16): cr_head RIGHT
    SKROWS cr_head_side_r_rows, 16, 16
    SKROW "......lLl......."
    SKROW ".....lLl........"
    SKROW "....ll.lll......"
    SKROW "....llllLl......"
    SKROW ".....Lllllllll.."
    SKROW ".....l......l..."
    SKROW "..........hhhhlL"
    SKROW ".lll......hhhlLl"
    SKROW ".lLl...y..hhLLl."
    SKROW "ylll..yyy...h..."
    SKROW "Yy.....y.y....y."
    SKROW ".........y...yyy"
    SKROW ".........lll..yy"
    SKROW "....yY....lLl..."
    SKROW ".l.yYy.....lLl.."
    SKROW "lllYy..........."
    SKROWS_END
    align 8
    SKBMP cr_head_side_r, cr_head_side_r_rows, 16, 16, cr_pal
    ; cr_head_side_l (16x16): cr_head LEFT
    SKROWS cr_head_side_l_rows, 16, 16
    SKROW ".......lLl......"
    SKROW "........lLl....."
    SKROW "......lll.ll...."
    SKROW "......lLllll...."
    SKROW "..llllllllL....."
    SKROW "...l......l....."
    SKROW "Llhhhh.........."
    SKROW "lLlhhh......lll."
    SKROW ".lLLhh..y...lLl."
    SKROW "...h...yyy..llly"
    SKROW ".y....y.y.....yY"
    SKROW "yyy...y........."
    SKROW "yy..lll........."
    SKROW "...lLl....Yy...."
    SKROW "..lLl.....yYy.l."
    SKROW "...........yYlll"
    SKROWS_END
    align 8
    SKBMP cr_head_side_l, cr_head_side_l_rows, 16, 16, cr_pal
    ; cr_tuft_a_front (3x3): cr_tuft_a FRONT
    SKROWS cr_tuft_a_front_rows, 3, 3
    SKROW "yyy"
    SKROW "..."
    SKROW "..L"
    SKROWS_END
    align 8
    SKBMP cr_tuft_a_front, cr_tuft_a_front_rows, 3, 3, cr_pal
    ; cr_tuft_a_back (3x3): cr_tuft_a BACK
    SKROWS cr_tuft_a_back_rows, 3, 3
    SKROW "yyy"
    SKROW "..."
    SKROW "..L"
    SKROWS_END
    align 8
    SKBMP cr_tuft_a_back, cr_tuft_a_back_rows, 3, 3, cr_pal
    ; cr_tuft_a_side (3x3): cr_tuft_a RIGHT/LEFT
    SKROWS cr_tuft_a_side_rows, 3, 3
    SKROW "yyy"
    SKROW "..."
    SKROW "..L"
    SKROWS_END
    align 8
    SKBMP cr_tuft_a_side, cr_tuft_a_side_rows, 3, 3, cr_pal
    ; cr_tuft_b_front (2x2): cr_tuft_b FRONT
    SKROWS cr_tuft_b_front_rows, 2, 2
    SKROW "yy"
    SKROW ".L"
    SKROWS_END
    align 8
    SKBMP cr_tuft_b_front, cr_tuft_b_front_rows, 2, 2, cr_pal
    ; cr_tuft_b_back (2x2): cr_tuft_b BACK
    SKROWS cr_tuft_b_back_rows, 2, 2
    SKROW "yy"
    SKROW ".L"
    SKROWS_END
    align 8
    SKBMP cr_tuft_b_back, cr_tuft_b_back_rows, 2, 2, cr_pal
    ; cr_tuft_b_side (2x2): cr_tuft_b RIGHT/LEFT
    SKROWS cr_tuft_b_side_rows, 2, 2
    SKROW "yy"
    SKROW ".L"
    SKROWS_END
    align 8
    SKBMP cr_tuft_b_side, cr_tuft_b_side_rows, 2, 2, cr_pal
    ; cr_tuft_c_front (2x3): cr_tuft_c FRONT
    SKROWS cr_tuft_c_front_rows, 2, 3
    SKROW "yy"
    SKROW ".."
    SKROW ".L"
    SKROWS_END
    align 8
    SKBMP cr_tuft_c_front, cr_tuft_c_front_rows, 2, 3, cr_pal
    ; cr_tuft_c_back (2x3): cr_tuft_c BACK
    SKROWS cr_tuft_c_back_rows, 2, 3
    SKROW "yy"
    SKROW ".."
    SKROW ".L"
    SKROWS_END
    align 8
    SKBMP cr_tuft_c_back, cr_tuft_c_back_rows, 2, 3, cr_pal
    ; cr_tuft_c_side (2x3): cr_tuft_c RIGHT/LEFT
    SKROWS cr_tuft_c_side_rows, 2, 3
    SKROW "yy"
    SKROW ".."
    SKROW ".L"
    SKROWS_END
    align 8
    SKBMP cr_tuft_c_side, cr_tuft_c_side_rows, 2, 3, cr_pal
    ; cr_leg_front (8x8): cr_leg_fl FRONT
    SKROWS cr_leg_front_rows, 8, 8
    SKROW "GGGGGGGG"
    SKROW ".......l"
    SKROW "..ll..lL"
    SKROW ".lllyyyL"
    SKROW ".lll.lll"
    SKROW ".....lLl"
    SKROW ".....lll"
    SKROW ".....lL."
    SKROWS_END
    align 8
    SKBMP cr_leg_front, cr_leg_front_rows, 8, 8, cr_pal
    ; cr_leg_back (8x8): cr_leg_fl BACK
    SKROWS cr_leg_back_rows, 8, 8
    SKROW "GGGGGGGG"
    SKROW "lL...l.."
    SKROW "Ll.l...."
    SKROW "l.lLl..."
    SKROW "..lLl..."
    SKROW "y.lLl..."
    SKROW "yy.l...."
    SKROW "y...lll."
    SKROWS_END
    align 8
    SKBMP cr_leg_back, cr_leg_back_rows, 8, 8, cr_pal
    ; cr_leg_right (8x8): cr_leg_fl RIGHT
    SKROWS cr_leg_right_rows, 8, 8
    SKROW "GGGGGGGG"
    SKROW "llLl..l."
    SKROW "..lLl..l"
    SKROW "...lL..l"
    SKROW "........"
    SKROW "....y..."
    SKROW "....y..."
    SKROW "....y..."
    SKROWS_END
    align 8
    SKBMP cr_leg_right, cr_leg_right_rows, 8, 8, cr_pal
    ; cr_leg_left (8x8): cr_leg_fl LEFT
    SKROWS cr_leg_left_rows, 8, 8
    SKROW "GGGGGGGG"
    SKROW "........"
    SKROW ".y....y."
    SKROW "yY....Yy"
    SKROW "yYy..yYy"
    SKROW ".Yyy.yY."
    SKROW ".y....l."
    SKROW "...lllll"
    SKROWS_END
    align 8
    SKBMP cr_leg_left, cr_leg_left_rows, 8, 8, cr_pal
    ; cr_foot_front (8x4): cr_foot_fl FRONT
    SKROWS cr_foot_front_rows, 8, 4
    SKROW "hhhhhhhh"
    SKROW "hhHhhHhh"
    SKROW "hhHhhHhh"
    SKROW "HHHHHHHH"
    SKROWS_END
    align 8
    SKBMP cr_foot_front, cr_foot_front_rows, 8, 4, cr_pal
    ; cr_foot_back (8x4): cr_foot_fl BACK
    SKROWS cr_foot_back_rows, 8, 4
    SKROW "hhhhhhhh"
    SKROW "hhhhhhhh"
    SKROW "hhhhhhhh"
    SKROW "HHHHHHHH"
    SKROWS_END
    align 8
    SKBMP cr_foot_back, cr_foot_back_rows, 8, 4, cr_pal
    ; cr_foot_side (8x4): cr_foot_fl RIGHT/LEFT
    SKROWS cr_foot_side_rows, 8, 4
    SKROW "hhhhhhhh"
    SKROW "hhhhhhhh"
    SKROW "hhHhhHhh"
    SKROW "HHHHHHHH"
    SKROWS_END
    align 8
    SKBMP cr_foot_side, cr_foot_side_rows, 8, 4, cr_pal

section .data
SKMODEL_BEGIN m_creeper, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART cr_body, -8, 12, -4, 16, 24, 8, 0, 0               ; mottled body with dark leafy patches and a darker hem
    PART cr_clump_a, 1, 25, 4, 5, 5, 2, 0, SKPF_CUTOUT      ; a leaf clump growing on the back
    PART cr_clump_b, -6, 17, 4, 4, 4, 2, 0, SKPF_CUTOUT     ; a smaller leaf clump
    PART_AS cr_clump_c, cr_clump_b, 2, 28, -6, 0, SKPF_CUTOUT
    SKBONE BK_HEAD, 0, 0, 0.00
    PART cr_head, -8, 36, -8, 16, 16, 16, 0, 0              ; classic dark face in a shadowed green mask, leafy top
    PART cr_tuft_a, -5, 52, -3, 3, 3, 3, 0, 0               ; a tuft of leaves on top of the head
    PART cr_tuft_b, 2, 52, 1, 2, 2, 2, 0, 0
    PART cr_tuft_c, -1, 52, -6, 2, 3, 2, 0, 0
    SKBONE BK_LIMB, 12, -8, 1.00
    PART cr_leg_fl, -8, 4, -12, 8, 8, 8, 0, 0               ; stubby front left leg (shared by the four legs)
    PART cr_foot_fl, -8, 0, -12, 8, 4, 8, 0, 0              ; foot with three toes (shared)
    SKBONE BK_LIMB, 12, -8, -1.00
    PART_AS cr_leg_fr, cr_leg_fl, 0, 4, -12, 0, 0
    PART_AS cr_foot_fr, cr_foot_fl, 0, 0, -12, 0, 0
    SKBONE BK_LIMB, 12, 8, -1.00
    PART_AS cr_leg_bl, cr_leg_fl, -8, 4, 4, 0, 0
    PART_AS cr_foot_bl, cr_foot_fl, -8, 0, 4, 0, 0
    SKBONE BK_LIMB, 12, 8, 1.00
    PART_AS cr_leg_br, cr_leg_fl, 0, 4, 4, 0, 0
    PART_AS cr_foot_br, cr_foot_fl, 0, 0, 4, 0, 0
SKMODEL_PAINT
    ; --- cr_body: mottled green; leaf blobs and glyphs on every side, a darker hem and a lit shoulder line
    SK_FILL cr_body, SKM_ALL, CR_SKIN_2, 15
    SK_BMP cr_body, SKF_FRONT, 0, 0, cr_body_front
    SK_BMP cr_body, SKF_BACK, 0, 0, cr_body_back
    SK_BMP cr_body, SKF_RIGHT, 0, 0, cr_body_right
    SK_BMP cr_body, SKF_LEFT, 0, 0, cr_body_left
    SK_GRAD cr_body, SKM_SIDES, 272, 224
    SK_BMP cr_body, SKF_TOP, 0, 0, cr_body_top
    SK_RECT cr_body, SKF_BOTTOM, 0, 0, 16, 8, CR_SKIN_4, 0
    ; --- cr_clump_a / cr_clump_b (shared with cr_clump_c): leaf clumps with ragged corners
    SK_FILL cr_clump_a, SKM_ALL, RGBO(38, 102, 42), 15
    SK_BMP cr_clump_a, SKF_FRONT, 0, 0, cr_clump_a_front
    SK_BMP cr_clump_a, SKF_BACK, 0, 0, cr_clump_a_back
    SK_BMP cr_clump_a, SKF_RIGHT, 0, 0, cr_clump_a_side
    SK_BMP cr_clump_a, SKF_LEFT, 0, 0, cr_clump_a_side
    SK_RECT cr_clump_a, SKF_TOP, 0, 0, 5, 2, RGBO(150, 218, 104), 15
    SK_RECT cr_clump_a, SKF_BOTTOM, 0, 0, 5, 2, RGBO(24, 72, 30), 0
    SK_FILL cr_clump_b, SKM_ALL, RGBO(38, 102, 42), 15
    SK_BMP cr_clump_b, SKF_FRONT, 0, 0, cr_clump_b_front
    SK_BMP cr_clump_b, SKF_BACK, 0, 0, cr_clump_b_back
    SK_BMP cr_clump_b, SKF_RIGHT, 0, 0, cr_clump_b_side
    SK_BMP cr_clump_b, SKF_LEFT, 0, 0, cr_clump_b_side
    SK_RECT cr_clump_b, SKF_TOP, 0, 0, 4, 2, RGBO(150, 218, 104), 15
    SK_RECT cr_clump_b, SKF_BOTTOM, 0, 0, 4, 2, RGBO(24, 72, 30), 0
    ; --- cr_head: a shadowed mask around the black face (eyes, nose-mouth, jaw legs), leaves on top and sides
    SK_FILL cr_head, SKM_ALL, CR_SKIN_2, 15
    SK_GRAD cr_head, SKM_SIDES, 272, 224
    SK_BMP cr_head, SKF_FRONT, 0, 0, cr_face
    SK_BMP cr_head, SKF_TOP, 0, 0, cr_head_top
    SK_BMP cr_head, SKF_BACK, 0, 0, cr_head_back
    SK_BMP cr_head, SKF_RIGHT, 0, 0, cr_head_side_r
    SK_BMP cr_head, SKF_LEFT, 0, 0, cr_head_side_l
    SK_RECT cr_head, SKF_BOTTOM, 0, 0, 16, 16, CR_SKIN_4, 0
    ; --- the leaf tufts on the head
    SK_FILL cr_tuft_a, SKM_ALL, RGBO(38, 102, 42), 31
    SK_RECT cr_tuft_a, SKF_TOP, 0, 0, 3, 3, RGBO(150, 218, 104), 15
    SK_GRAD cr_tuft_a, SKM_SIDES, 272, 224
    SK_BMP cr_tuft_a, SKF_FRONT, 0, 0, cr_tuft_a_front
    SK_BMP cr_tuft_a, SKF_BACK, 0, 0, cr_tuft_a_back
    SK_BMP cr_tuft_a, SKF_RIGHT, 0, 0, cr_tuft_a_side
    SK_BMP cr_tuft_a, SKF_LEFT, 0, 0, cr_tuft_a_side
    SK_RECT cr_tuft_a, SKF_BOTTOM, 0, 0, 3, 3, RGBO(24, 72, 30), 0
    SK_FILL cr_tuft_b, SKM_ALL, RGBO(38, 102, 42), 31
    SK_RECT cr_tuft_b, SKF_TOP, 0, 0, 2, 2, RGBO(150, 218, 104), 15
    SK_GRAD cr_tuft_b, SKM_SIDES, 272, 224
    SK_BMP cr_tuft_b, SKF_FRONT, 0, 0, cr_tuft_b_front
    SK_BMP cr_tuft_b, SKF_BACK, 0, 0, cr_tuft_b_back
    SK_BMP cr_tuft_b, SKF_RIGHT, 0, 0, cr_tuft_b_side
    SK_BMP cr_tuft_b, SKF_LEFT, 0, 0, cr_tuft_b_side
    SK_RECT cr_tuft_b, SKF_BOTTOM, 0, 0, 2, 2, RGBO(24, 72, 30), 0
    SK_FILL cr_tuft_c, SKM_ALL, RGBO(38, 102, 42), 31
    SK_RECT cr_tuft_c, SKF_TOP, 0, 0, 2, 2, RGBO(150, 218, 104), 15
    SK_GRAD cr_tuft_c, SKM_SIDES, 272, 224
    SK_BMP cr_tuft_c, SKF_FRONT, 0, 0, cr_tuft_c_front
    SK_BMP cr_tuft_c, SKF_BACK, 0, 0, cr_tuft_c_back
    SK_BMP cr_tuft_c, SKF_RIGHT, 0, 0, cr_tuft_c_side
    SK_BMP cr_tuft_c, SKF_LEFT, 0, 0, cr_tuft_c_side
    SK_RECT cr_tuft_c, SKF_BOTTOM, 0, 0, 2, 2, RGBO(24, 72, 30), 0
    ; --- cr_leg_fl (shared by the four legs): mottled stub; cr_foot_fl (shared): a darker foot with three toes
    SK_FILL cr_leg_fl, SKM_ALL, CR_SKIN_2, 15
    SK_BMP cr_leg_fl, SKF_FRONT, 0, 0, cr_leg_front
    SK_BMP cr_leg_fl, SKF_BACK, 0, 0, cr_leg_back
    SK_BMP cr_leg_fl, SKF_RIGHT, 0, 0, cr_leg_right
    SK_BMP cr_leg_fl, SKF_LEFT, 0, 0, cr_leg_left
    SK_GRAD cr_leg_fl, SKM_SIDES, 272, 224
    SK_RECT cr_leg_fl, SKF_TOP, 0, 0, 8, 8, CR_SKIN_3, 15
    SK_RECT cr_leg_fl, SKF_BOTTOM, 0, 0, 8, 8, CR_SKIN_4, 0
    SK_FILL cr_foot_fl, SKM_ALL, CR_SKIN_3, 15
    SK_BMP cr_foot_fl, SKF_FRONT, 0, 0, cr_foot_front
    SK_BMP cr_foot_fl, SKF_BACK, 0, 0, cr_foot_back
    SK_BMP cr_foot_fl, SKF_RIGHT, 0, 0, cr_foot_side
    SK_BMP cr_foot_fl, SKF_LEFT, 0, 0, cr_foot_side
    SK_RECT cr_foot_fl, SKF_TOP, 0, 0, 8, 8, CR_SKIN_3, 15
    SK_RECT cr_foot_fl, SKF_BOTTOM, 0, 0, 8, 8, CR_SKIN_4, 0
SKMODEL_END

; ===================================================================================================
; m_chicken
; ===================================================================================================
RAMP CH_FEATHER, 240, 238, 228          ; white feathers (the old chicken tile was (240,240,240))
RAMP CH_RED, 210, 38, 40                ; comb, wattle and ear lobes
RAMP CH_BEAK, 240, 180, 40              ; beak and legs (the old chicken leg tile)

section .rodata
; The characters of every ch_ bitmap. Groups: base, highlight, shade, deep.
;   w W v V white feathers   u soft shade   f F tan feather tips   r R q Q red comb, wattle, lobe   y Y z Z beak, legs
;   x eye   e glint   _ transparent
align 8
ch_pal:
    PALC 'w', CH_FEATHER_2
    PALC 'W', CH_FEATHER_1
    PALC 'v', CH_FEATHER_3
    PALC 'V', CH_FEATHER_4
    PALC 'u', RGBO(216, 214, 206)
    PALC 'f', RGBO(238, 218, 176)
    PALC 'F', RGBO(214, 186, 138)
    PALC 'r', CH_RED_2
    PALC 'R', CH_RED_1
    PALC 'q', CH_RED_3
    PALC 'Q', CH_RED_4
    PALC 'y', CH_BEAK_2
    PALC 'Y', CH_BEAK_1
    PALC 'z', CH_BEAK_3
    PALC 'Z', CH_BEAK_4
    PALC 'x', RGBO(26, 20, 22)
    PALC 'e', RGBO(255, 255, 255)
    PALT '_'
    dq 0

    ; ch_body_front (12x14): ch_body FRONT
    SKROWS ch_body_front_rows, 12, 14
    SKROW "WWWWWWWWWWWW"
    SKROW "u..uu..uu..u"
    SKROW "uuuuuuuuuuuu"
    SKROW "WWWWWWWWWWWW"
    SKROW ".uu..uu..uu."
    SKROW "uuuuuuuuuuuu"
    SKROW "WWWWWWWWWWWW"
    SKROW "u..uu..uu..u"
    SKROW "uuuuuuuuuuuu"
    SKROW "WWWWWWWWWWWW"
    SKROW ".uu..uu..uu."
    SKROW "uuuuuuuuuuuu"
    SKROW "WWWWWWWWWWWW"
    SKROW "u..uu..uu..u"
    SKROWS_END
    align 8
    SKBMP ch_body_front, ch_body_front_rows, 12, 14, ch_pal
    ; ch_body_back (12x14): ch_body BACK
    SKROWS ch_body_back_rows, 12, 14
    SKROW "WWWWWWWWWWWW"
    SKROW "u..uu..uu..u"
    SKROW "uuuuuuuuuuuu"
    SKROW "WWWWWWWWWWWW"
    SKROW ".uu..uu..uu."
    SKROW "uuuuuuuuuuuu"
    SKROW "WWWWWWWWWWWW"
    SKROW "u..uu..uu..u"
    SKROW "uuuuuuuuuuuu"
    SKROW "WWWWWWWWWWWW"
    SKROW ".uu..uu..uu."
    SKROW "uuuuuuuuuuuu"
    SKROW "WWWWWWWWWWWW"
    SKROW "u..uu..uu..u"
    SKROWS_END
    align 8
    SKBMP ch_body_back, ch_body_back_rows, 12, 14, ch_pal
    ; ch_body_right (16x14): ch_body RIGHT
    SKROWS ch_body_right_rows, 16, 14
    SKROW "WWWWWWWWWWWWWWWW"
    SKROW "f..uu..uu..uu..u"
    SKROW "uuuuuuuuuuuuuuuu"
    SKROW "WWWWWWWWWWWWWWWW"
    SKROW ".uu..uu..uu..fu."
    SKROW "uuuuuuuuuuuuuuuu"
    SKROW "WWWWWWWWWWWWWWWW"
    SKROW "u..uu..uu..uu..u"
    SKROW "uuuuuuuuuuuuuuuu"
    SKROW "WWWWWWWWWWWWWWWW"
    SKROW ".uu..uu..uu..uu."
    SKROW "uuuuuuuuuuuuuuuu"
    SKROW "WWWWWWWWWWWWWWWW"
    SKROW "u..uu..uu..uu..u"
    SKROWS_END
    align 8
    SKBMP ch_body_right, ch_body_right_rows, 16, 14, ch_pal
    ; ch_body_left (16x14): ch_body LEFT
    SKROWS ch_body_left_rows, 16, 14
    SKROW "WWWWWWWWWWWWWWWW"
    SKROW "u..uu..uu..uu..u"
    SKROW "uufuuuuuuuuuuuuu"
    SKROW "WWWWWWWWWWWWWWWW"
    SKROW ".uu..uu..uu..uuf"
    SKROW "uuuuuuuuuuuuuuuu"
    SKROW "WWWWWWWWWWWWWWWW"
    SKROW "u..uu..uu..uu..u"
    SKROW "uuuuuuuuuuuuuuuu"
    SKROW "WWWWWWWWWWWWWWWW"
    SKROW ".uu..uu..uu..uu."
    SKROW "uuuuuuuuuuuuuuuu"
    SKROW "WWWWWWWWWWWWWWWW"
    SKROW "u..uu..uu..uu..u"
    SKROWS_END
    align 8
    SKBMP ch_body_left, ch_body_left_rows, 16, 14, ch_pal
    ; ch_body_top (12x16): ch_body TOP
    SKROWS ch_body_top_rows, 12, 16
    SKROW ".......F...."
    SKROW "u..uu..uv..u"
    SKROW "uffuuffuuffu"
    SKROW "............"
    SKROW ".uu..uu..uu."
    SKROW "fuuffuuffuuf"
    SKROW "............"
    SKROW "u..uu..uu..u"
    SKROW "uffuuffuuffu"
    SKROW "F..........."
    SKROW "Fuu..uu..uu."
    SKROW "fuuffvuffuuf"
    SKROW "............"
    SKROW "u..uu..uu..u"
    SKROW "uffuuffuuffu"
    SKROW "............"
    SKROWS_END
    align 8
    SKBMP ch_body_top, ch_body_top_rows, 12, 16, ch_pal
    ; ch_body_bottom (12x16): ch_body BOTTOM
    SKROWS ch_body_bottom_rows, 12, 16
    SKROW "WWWWWWWWWWWW"
    SKROW "WWWWWWWWWWWW"
    SKROW "uWWuuWWuuWWu"
    SKROW "uuuuuuuuuuuu"
    SKROW "WWWWWWWWWWWW"
    SKROW "WWWWWWWWWWWW"
    SKROW "WuuWWuuWWuuW"
    SKROW "uuuuuuuuuuuu"
    SKROW "WWWWWWWWWWWW"
    SKROW "WWWWWWWWWWWW"
    SKROW "uWWuuWWuuWWu"
    SKROW "uuuuuuuuuuuu"
    SKROW "WWWWWWWWWWWW"
    SKROW "WWWWWWWWWWWW"
    SKROW "WuuWWuuWWuuW"
    SKROW "uuuuuuuuuuuu"
    SKROWS_END
    align 8
    SKBMP ch_body_bottom, ch_body_bottom_rows, 12, 16, ch_pal
    ; ch_chest_front (8x8): ch_chest FRONT
    SKROWS ch_chest_front_rows, 8, 8
    SKROW "uWWuuWWu"
    SKROW "uuuuuuuu"
    SKROW "WuuWWuuW"
    SKROW "uuuuuuuu"
    SKROW "uWWuuWWu"
    SKROW "uuuuuuuu"
    SKROW "WuuWWuuW"
    SKROW "uuuuuuuu"
    SKROWS_END
    align 8
    SKBMP ch_chest_front, ch_chest_front_rows, 8, 8, ch_pal
    ; ch_neck_front (6x6): ch_neck FRONT/BACK
    SKROWS ch_neck_front_rows, 6, 6
    SKROW "uWuuWu"
    SKROW "uuuuuu"
    SKROW "WuuWuu"
    SKROW "uuuuuu"
    SKROW "uWuuWu"
    SKROW "uuuuuu"
    SKROWS_END
    align 8
    SKBMP ch_neck_front, ch_neck_front_rows, 6, 6, ch_pal
    ; ch_neck_side (5x6): ch_neck RIGHT/LEFT
    SKROWS ch_neck_side_rows, 5, 6
    SKROW "uWuuW"
    SKROW "uuuuu"
    SKROW "WuuWu"
    SKROW "uuuuu"
    SKROW "uWuuW"
    SKROW "uuuuu"
    SKROWS_END
    align 8
    SKBMP ch_neck_side, ch_neck_side_rows, 5, 6, ch_pal
    ; ch_tail_a_back (2x9): ch_tail_a BACK
    SKROWS ch_tail_a_back_rows, 2, 9
    SKROW "ff"
    SKROW "Ww"
    SKROW "Wv"
    SKROW "Ww"
    SKROW "Wv"
    SKROW "Ww"
    SKROW "Wv"
    SKROW "Ww"
    SKROW "Wv"
    SKROWS_END
    align 8
    SKBMP ch_tail_a_back, ch_tail_a_back_rows, 2, 9, ch_pal
    ; ch_tail_a_front (2x9): ch_tail_a FRONT
    SKROWS ch_tail_a_front_rows, 2, 9
    SKROW "ff"
    SKROW "wW"
    SKROW "vW"
    SKROW "wW"
    SKROW "vW"
    SKROW "wW"
    SKROW "vW"
    SKROW "wW"
    SKROW "vW"
    SKROWS_END
    align 8
    SKBMP ch_tail_a_front, ch_tail_a_front_rows, 2, 9, ch_pal
    ; ch_tail_b_back (2x7): ch_tail_b BACK
    SKROWS ch_tail_b_back_rows, 2, 7
    SKROW "vv"
    SKROW "Ww"
    SKROW "Wv"
    SKROW "Ww"
    SKROW "Wv"
    SKROW "Ww"
    SKROW "Wv"
    SKROWS_END
    align 8
    SKBMP ch_tail_b_back, ch_tail_b_back_rows, 2, 7, ch_pal
    ; ch_tail_b_front (2x7): ch_tail_b FRONT
    SKROWS ch_tail_b_front_rows, 2, 7
    SKROW "vv"
    SKROW "wW"
    SKROW "vW"
    SKROW "wW"
    SKROW "vW"
    SKROW "wW"
    SKROW "vW"
    SKROWS_END
    align 8
    SKBMP ch_tail_b_front, ch_tail_b_front_rows, 2, 7, ch_pal
    ; ch_head_front (8x8): ch_head FRONT
    SKROWS ch_head_front_rows, 8, 8
    SKROW "WWWWWWWW"
    SKROW "........"
    SKROW "........"
    SKROW "x.yyyy.x"
    SKROW "x.yyyy.x"
    SKROW "..yyyy.."
    SKROW ".vvvvvv."
    SKROW "........"
    SKROWS_END
    align 8
    SKBMP ch_head_front, ch_head_front_rows, 8, 8, ch_pal
    ; ch_head_side_r (8x8): ch_head RIGHT
    SKROWS ch_head_side_r_rows, 8, 8
    SKROW "WWWWWWWW"
    SKROW "........"
    SKROW "....vv.."
    SKROW "...vex.."
    SKROW "...vxx.."
    SKROW "..Rr...."
    SKROW "..rq...."
    SKROW "vvvvvvvv"
    SKROWS_END
    align 8
    SKBMP ch_head_side_r, ch_head_side_r_rows, 8, 8, ch_pal
    ; ch_head_side_l (8x8): ch_head LEFT
    SKROWS ch_head_side_l_rows, 8, 8
    SKROW "WWWWWWWW"
    SKROW "........"
    SKROW "..vv...."
    SKROW "..xev..."
    SKROW "..xxv..."
    SKROW "....rR.."
    SKROW "....qr.."
    SKROW "vvvvvvvv"
    SKROWS_END
    align 8
    SKBMP ch_head_side_l, ch_head_side_l_rows, 8, 8, ch_pal
    ; ch_head_back (8x8): ch_head BACK
    SKROWS ch_head_back_rows, 8, 8
    SKROW "uWWuuWWu"
    SKROW "uuuuuuuu"
    SKROW "WuuWWuuW"
    SKROW "uuuuuuuu"
    SKROW "uWWuuWWu"
    SKROW "uuuuuuuu"
    SKROW "WuuWWuuW"
    SKROW "uuuuuuuu"
    SKROWS_END
    align 8
    SKBMP ch_head_back, ch_head_back_rows, 8, 8, ch_pal
    ; ch_head_top (8x8): ch_head TOP
    SKROWS ch_head_top_rows, 8, 8
    SKROW "...qq..."
    SKROW "...qq..."
    SKROW "...qq..."
    SKROW "...qq..."
    SKROW "...qq..."
    SKROW "...qq..."
    SKROW "........"
    SKROW "........"
    SKROWS_END
    align 8
    SKBMP ch_head_top, ch_head_top_rows, 8, 8, ch_pal
    ; ch_comb_a_front (2x2): ch_comb_a FRONT/BACK
    SKROWS ch_comb_a_front_rows, 2, 2
    SKROW "RR"
    SKROW "Rq"
    SKROWS_END
    align 8
    SKBMP ch_comb_a_front, ch_comb_a_front_rows, 2, 2, ch_pal
    ; ch_comb_a_side (2x2): ch_comb_a RIGHT/LEFT
    SKROWS ch_comb_a_side_rows, 2, 2
    SKROW "Rq"
    SKROW "QQ"
    SKROWS_END
    align 8
    SKBMP ch_comb_a_side, ch_comb_a_side_rows, 2, 2, ch_pal
    ; ch_comb_b_front (2x4): ch_comb_b FRONT/BACK
    SKROWS ch_comb_b_front_rows, 2, 4
    SKROW "RR"
    SKROW "Rq"
    SKROW "Rq"
    SKROW "Rq"
    SKROWS_END
    align 8
    SKBMP ch_comb_b_front, ch_comb_b_front_rows, 2, 4, ch_pal
    ; ch_comb_b_side (2x4): ch_comb_b RIGHT/LEFT
    SKROWS ch_comb_b_side_rows, 2, 4
    SKROW "Rq"
    SKROW "Rq"
    SKROW "Rq"
    SKROW "QQ"
    SKROWS_END
    align 8
    SKBMP ch_comb_b_side, ch_comb_b_side_rows, 2, 4, ch_pal
    ; ch_comb_c_front (2x3): ch_comb_c FRONT/BACK
    SKROWS ch_comb_c_front_rows, 2, 3
    SKROW "RR"
    SKROW "Rq"
    SKROW "Rq"
    SKROWS_END
    align 8
    SKBMP ch_comb_c_front, ch_comb_c_front_rows, 2, 3, ch_pal
    ; ch_comb_c_side (2x3): ch_comb_c RIGHT/LEFT
    SKROWS ch_comb_c_side_rows, 2, 3
    SKROW "Rq"
    SKROW "Rq"
    SKROW "QQ"
    SKROWS_END
    align 8
    SKBMP ch_comb_c_side, ch_comb_c_side_rows, 2, 3, ch_pal
    ; ch_beak_front (4x2): ch_beak_u FRONT
    SKROWS ch_beak_front_rows, 4, 2
    SKROW "YyyY"
    SKROW "zzzz"
    SKROWS_END
    align 8
    SKBMP ch_beak_front, ch_beak_front_rows, 4, 2, ch_pal
    ; ch_beak_top (4x2): ch_beak_u TOP
    SKROWS ch_beak_top_rows, 4, 2
    SKROW "YYYY"
    SKROW "YzzY"
    SKROWS_END
    align 8
    SKBMP ch_beak_top, ch_beak_top_rows, 4, 2, ch_pal
    ; ch_wattle_front (2x4): ch_wattle FRONT
    SKROWS ch_wattle_front_rows, 2, 4
    SKROW "RR"
    SKROW "rr"
    SKROW "rq"
    SKROW "qQ"
    SKROWS_END
    align 8
    SKBMP ch_wattle_front, ch_wattle_front_rows, 2, 4, ch_pal
    ; ch_wattle_back (2x4): ch_wattle BACK
    SKROWS ch_wattle_back_rows, 2, 4
    SKROW "RR"
    SKROW "rr"
    SKROW "qr"
    SKROW "Qq"
    SKROWS_END
    align 8
    SKBMP ch_wattle_back, ch_wattle_back_rows, 2, 4, ch_pal
    ; ch_wing_l_side_r (10x11): ch_wing_l RIGHT
    SKROWS ch_wing_l_side_r_rows, 10, 11
    SKROW "WWWWWWWWWW"
    SKROW "W...uu...u"
    SKROW "Wu.uuuu.uu"
    SKROW "WWWWWWWWWW"
    SKROW "W.uu...uu."
    SKROW "Wuuuu.uuuu"
    SKROW "WWWWWWWWWW"
    SKROW "Wuuuuuuuuu"
    SKROW "WFFFFFFFFF"
    SKROW "Wfffffffff"
    SKROW "WFFFFFFFFF"
    SKROWS_END
    align 8
    SKBMP ch_wing_l_side_r, ch_wing_l_side_r_rows, 10, 11, ch_pal
    ; ch_wing_l_side_l (10x11): ch_wing_l LEFT
    SKROWS ch_wing_l_side_l_rows, 10, 11
    SKROW "WWWWWWWWWW"
    SKROW "u...uu...W"
    SKROW "uu.uuuu.uW"
    SKROW "WWWWWWWWWW"
    SKROW ".uu...uu.W"
    SKROW "uuuu.uuuuW"
    SKROW "WWWWWWWWWW"
    SKROW "uuuuuuuuuW"
    SKROW "FFFFFFFFFW"
    SKROW "fffffffffW"
    SKROW "FFFFFFFFFW"
    SKROWS_END
    align 8
    SKBMP ch_wing_l_side_l, ch_wing_l_side_l_rows, 10, 11, ch_pal
    ; ch_wing_l_edge (2x11): ch_wing_l FRONT/BACK
    SKROWS ch_wing_l_edge_rows, 2, 11
    SKROW "WW"
    SKROW "uu"
    SKROW "uu"
    SKROW "uu"
    SKROW "uu"
    SKROW "uu"
    SKROW "uu"
    SKROW "ff"
    SKROW "FF"
    SKROW "ff"
    SKROW "FF"
    SKROWS_END
    align 8
    SKBMP ch_wing_l_edge, ch_wing_l_edge_rows, 2, 11, ch_pal
    ; ch_tip_l_side_r (4x7): ch_tip_l RIGHT
    SKROWS ch_tip_l_side_r_rows, 4, 7
    SKROW "ffff"
    SKROW "FFFF"
    SKROW "ffff"
    SKROW "FFFF"
    SKROW "ffff"
    SKROW "FFFF"
    SKROW "FFFF"
    SKROWS_END
    align 8
    SKBMP ch_tip_l_side_r, ch_tip_l_side_r_rows, 4, 7, ch_pal
    ; ch_tip_l_side_l (4x7): ch_tip_l LEFT
    SKROWS ch_tip_l_side_l_rows, 4, 7
    SKROW "ffff"
    SKROW "FFFF"
    SKROW "ffff"
    SKROW "FFFF"
    SKROW "ffff"
    SKROW "FFFF"
    SKROW "FFFF"
    SKROWS_END
    align 8
    SKBMP ch_tip_l_side_l, ch_tip_l_side_l_rows, 4, 7, ch_pal
    ; ch_tip_l_edge (2x7): ch_tip_l FRONT/BACK
    SKROWS ch_tip_l_edge_rows, 2, 7
    SKROW "ff"
    SKROW "FF"
    SKROW "ff"
    SKROW "FF"
    SKROW "ff"
    SKROW "FF"
    SKROW "ff"
    SKROWS_END
    align 8
    SKBMP ch_tip_l_edge, ch_tip_l_edge_rows, 2, 7, ch_pal
    ; ch_leg_front (2x9): ch_leg_l FRONT/BACK
    SKROWS ch_leg_front_rows, 2, 9
    SKROW "Yz"
    SKROW "zz"
    SKROW "Yz"
    SKROW "zz"
    SKROW "Yz"
    SKROW "zz"
    SKROW "Yz"
    SKROW "zz"
    SKROW "Yz"
    SKROWS_END
    align 8
    SKBMP ch_leg_front, ch_leg_front_rows, 2, 9, ch_pal
    ; ch_leg_side (2x9): ch_leg_l RIGHT/LEFT
    SKROWS ch_leg_side_rows, 2, 9
    SKROW "Yz"
    SKROW "zz"
    SKROW "Yz"
    SKROW "zz"
    SKROW "Yz"
    SKROW "zz"
    SKROW "Yz"
    SKROW "zz"
    SKROW "Yz"
    SKROWS_END
    align 8
    SKBMP ch_leg_side, ch_leg_side_rows, 2, 9, ch_pal
    ; ch_thigh_front (4x4): ch_thigh_l FRONT/BACK
    SKROWS ch_thigh_front_rows, 4, 4
    SKROW "uWWu"
    SKROW "uuuu"
    SKROW "WuuW"
    SKROW "uuuu"
    SKROWS_END
    align 8
    SKBMP ch_thigh_front, ch_thigh_front_rows, 4, 4, ch_pal
    ; ch_thigh_side (4x4): ch_thigh_l RIGHT/LEFT
    SKROWS ch_thigh_side_rows, 4, 4
    SKROW "uWWu"
    SKROW "uuuu"
    SKROW "WuuW"
    SKROW "uuuu"
    SKROWS_END
    align 8
    SKBMP ch_thigh_side, ch_thigh_side_rows, 4, 4, ch_pal

section .data
SKMODEL_BEGIN m_chicken, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART ch_body, -6, 10, -8, 12, 14, 16, 0, 0              ; plump body: scalloped white feathers, a darker back
    PART ch_chest, -4, 12, -10, 8, 8, 2, 0, 0               ; puffed chest
    PART ch_tail_a, -1, 21, 8, 2, 9, 1, 0, 0                ; tail fan: tall middle feather
    PART ch_tail_b, -3, 21, 8, 2, 7, 1, 0, 0                ; left tail feather
    PART_AS ch_tail_c, ch_tail_b, 1, 21, 8, 0, 0
    SKBONE BK_HEAD, 0, 0, 0.00
    PART ch_head, -4, 22, -14, 8, 8, 8, 0, 0                ; head: eyes on the sides, ear lobes, a pale face
    PART ch_neck, -3, 17, -12, 6, 6, 5, 0, 0                ; neck with a ruff of feathers
    PART ch_comb_a, -1, 30, -12, 2, 2, 2, 0, 0              ; comb: three bumps
    PART ch_comb_b, -1, 30, -10, 2, 4, 2, 0, 0
    PART ch_comb_c, -1, 30, -8, 2, 3, 2, 0, 0
    PART ch_beak_u, -2, 25, -16, 4, 2, 2, 0, 0              ; upper beak
    PART ch_beak_l, -1, 24, -16, 2, 1, 2, 0, 0              ; lower beak
    PART ch_wattle, -1, 20, -15, 2, 4, 1, 0, 0              ; red wattle under the beak
    SKBONE BK_LIMB, 22, 0, 0.30
    PART ch_wing_l, -8, 11, -6, 2, 11, 10, 0, 0             ; left wing: feather rows with tan tips
    PART ch_tip_l, -8, 9, 4, 2, 7, 4, 0, 0                  ; its long rear feathers
    SKBONE BK_LIMB, 22, 0, 0.30
    PART_AS ch_wing_r, ch_wing_l, 6, 11, -6, 0, 0
    PART_AS ch_tip_r, ch_tip_l, 6, 9, 4, 0, 0
    SKBONE BK_LLEG, 10, 0, 1.00
    PART ch_leg_l, -4, 1, -1, 2, 9, 2, 0, 0                 ; scaly yellow leg (shared with the right one)
    PART ch_thigh_l, -5, 7, -2, 4, 4, 4, 0, 0               ; feathered thigh
    PART ch_toe_a, -5, 0, -4, 1, 1, 4, 0, 0                 ; toes: two side toes, a middle toe and a back toe
    PART ch_toe_m, -4, 0, -5, 2, 1, 5, 0, 0
    PART_AS ch_toe_b, ch_toe_a, -2, 0, -4, 0, 0
    PART ch_toe_c, -4, 0, 1, 2, 1, 2, 0, 0
    SKBONE BK_RLEG, 10, 0, -1.00
    PART_AS ch_leg_r, ch_leg_l, 2, 1, -1, 0, 0
    PART_AS ch_thigh_r, ch_thigh_l, 1, 7, -2, 0, 0
    PART_AS ch_toe_d, ch_toe_a, 1, 0, -4, 0, 0
    PART_AS ch_toe_n, ch_toe_m, 2, 0, -5, 0, 0
    PART_AS ch_toe_e, ch_toe_a, 4, 0, -4, 0, 0
    PART_AS ch_toe_f, ch_toe_c, 2, 0, 1, 0, 0
SKMODEL_PAINT
    ; --- ch_body: rows of scalloped feathers; the back is a touch darker; the belly is soft white
    SK_FILL ch_body, SKM_ALL, CH_FEATHER_2, 15
    SK_BMP ch_body, SKF_FRONT, 0, 0, ch_body_front
    SK_BMP ch_body, SKF_BACK, 0, 0, ch_body_back
    SK_BMP ch_body, SKF_RIGHT, 0, 0, ch_body_right
    SK_BMP ch_body, SKF_LEFT, 0, 0, ch_body_left
    SK_GRAD ch_body, SKM_SIDES, 272, 224
    SK_BMP ch_body, SKF_TOP, 0, 0, ch_body_top
    SK_BMP ch_body, SKF_BOTTOM, 0, 0, ch_body_bottom
    ; --- ch_chest, ch_neck, the tail feathers
    SK_FILL ch_chest, SKM_ALL, CH_FEATHER_1, 15
    SK_BMP ch_chest, SKF_FRONT, 0, 0, ch_chest_front
    SK_GRAD ch_chest, SKM_SIDES, 272, 224
    SK_FILL ch_neck, SKM_ALL, CH_FEATHER_2, 15
    SK_BMP ch_neck, SKF_FRONT, 0, 0, ch_neck_front
    SK_BMP ch_neck, SKF_BACK, 0, 0, ch_neck_front
    SK_BMP ch_neck, SKF_RIGHT, 0, 0, ch_neck_side
    SK_BMP ch_neck, SKF_LEFT, 0, 0, ch_neck_side
    SK_GRAD ch_neck, SKM_SIDES, 272, 224
    SK_RECT ch_neck, SKF_TOP, 0, 0, 6, 5, CH_FEATHER_2, 15
    SK_RECT ch_neck, SKF_BOTTOM, 0, 0, 6, 5, CH_FEATHER_3, 0
    SK_FILL ch_tail_a, SKM_ALL, CH_FEATHER_2, 15
    SK_BMP ch_tail_a, SKF_BACK, 0, 0, ch_tail_a_back
    SK_BMP ch_tail_a, SKF_FRONT, 0, 0, ch_tail_a_front
    SK_RECT ch_tail_a, SKF_RIGHT, 0, 0, 1, 9, CH_FEATHER_3, 0
    SK_RECT ch_tail_a, SKF_LEFT, 0, 0, 1, 9, CH_FEATHER_3, 0
    SK_RECT ch_tail_a, SKF_TOP, 0, 0, 2, 1, CH_FEATHER_1, 0
    SK_RECT ch_tail_a, SKF_BOTTOM, 0, 0, 2, 1, CH_FEATHER_4, 0
    SK_FILL ch_tail_b, SKM_ALL, CH_FEATHER_2, 15
    SK_BMP ch_tail_b, SKF_BACK, 0, 0, ch_tail_b_back
    SK_BMP ch_tail_b, SKF_FRONT, 0, 0, ch_tail_b_front
    SK_RECT ch_tail_b, SKF_RIGHT, 0, 0, 1, 7, CH_FEATHER_3, 0
    SK_RECT ch_tail_b, SKF_LEFT, 0, 0, 1, 7, CH_FEATHER_3, 0
    SK_RECT ch_tail_b, SKF_TOP, 0, 0, 2, 1, CH_FEATHER_1, 0
    SK_RECT ch_tail_b, SKF_BOTTOM, 0, 0, 2, 1, CH_FEATHER_4, 0
    ; --- ch_head: white face, a dark eye on each side with a glint, red ear lobes, the eye edge wraps to the front
    SK_FILL ch_head, SKM_ALL, CH_FEATHER_2, 15
    SK_GRAD ch_head, SKM_SIDES, 272, 224
    SK_BMP ch_head, SKF_FRONT, 0, 0, ch_head_front
    SK_BMP ch_head, SKF_RIGHT, 0, 0, ch_head_side_r
    SK_BMP ch_head, SKF_LEFT, 0, 0, ch_head_side_l
    SK_BMP ch_head, SKF_BACK, 0, 0, ch_head_back
    SK_BMP ch_head, SKF_TOP, 0, 0, ch_head_top
    SK_RECT ch_head, SKF_BOTTOM, 0, 0, 8, 8, CH_FEATHER_3, 0
    ; --- the comb (three red bumps), beak, wattle
    SK_FILL ch_comb_a, SKM_ALL, CH_RED_2, 15
    SK_BMP ch_comb_a, SKF_FRONT, 0, 0, ch_comb_a_front
    SK_BMP ch_comb_a, SKF_BACK, 0, 0, ch_comb_a_front
    SK_BMP ch_comb_a, SKF_RIGHT, 0, 0, ch_comb_a_side
    SK_BMP ch_comb_a, SKF_LEFT, 0, 0, ch_comb_a_side
    SK_RECT ch_comb_a, SKF_TOP, 0, 0, 2, 2, CH_RED_1, 0
    SK_RECT ch_comb_a, SKF_BOTTOM, 0, 0, 2, 2, CH_RED_4, 0
    SK_FILL ch_comb_b, SKM_ALL, CH_RED_2, 15
    SK_BMP ch_comb_b, SKF_FRONT, 0, 0, ch_comb_b_front
    SK_BMP ch_comb_b, SKF_BACK, 0, 0, ch_comb_b_front
    SK_BMP ch_comb_b, SKF_RIGHT, 0, 0, ch_comb_b_side
    SK_BMP ch_comb_b, SKF_LEFT, 0, 0, ch_comb_b_side
    SK_RECT ch_comb_b, SKF_TOP, 0, 0, 2, 2, CH_RED_1, 0
    SK_RECT ch_comb_b, SKF_BOTTOM, 0, 0, 2, 2, CH_RED_4, 0
    SK_FILL ch_comb_c, SKM_ALL, CH_RED_2, 15
    SK_BMP ch_comb_c, SKF_FRONT, 0, 0, ch_comb_c_front
    SK_BMP ch_comb_c, SKF_BACK, 0, 0, ch_comb_c_front
    SK_BMP ch_comb_c, SKF_RIGHT, 0, 0, ch_comb_c_side
    SK_BMP ch_comb_c, SKF_LEFT, 0, 0, ch_comb_c_side
    SK_RECT ch_comb_c, SKF_TOP, 0, 0, 2, 2, CH_RED_1, 0
    SK_RECT ch_comb_c, SKF_BOTTOM, 0, 0, 2, 2, CH_RED_4, 0
    SK_FILL ch_beak_u, SKM_ALL, CH_BEAK_2, 7
    SK_BMP ch_beak_u, SKF_FRONT, 0, 0, ch_beak_front
    SK_BMP ch_beak_u, SKF_TOP, 0, 0, ch_beak_top
    SK_RECT ch_beak_u, SKF_BOTTOM, 0, 0, 4, 2, CH_BEAK_4, 0
    SK_RECT ch_beak_u, SKF_RIGHT, 0, 0, 2, 2, CH_BEAK_3, 0
    SK_RECT ch_beak_u, SKF_LEFT, 0, 0, 2, 2, CH_BEAK_3, 0
    SK_RECT ch_beak_u, SKF_BACK, 0, 0, 4, 2, CH_BEAK_3, 0
    SK_FILL ch_beak_l, SKM_ALL, CH_BEAK_3, 7
    SK_RECT ch_beak_l, SKF_FRONT, 0, 0, 2, 1, CH_BEAK_4, 0
    SK_RECT ch_beak_l, SKF_TOP, 0, 0, 2, 2, CH_BEAK_4, 0
    SK_FILL ch_wattle, SKM_ALL, CH_RED_2, 15
    SK_BMP ch_wattle, SKF_FRONT, 0, 0, ch_wattle_front
    SK_BMP ch_wattle, SKF_BACK, 0, 0, ch_wattle_back
    SK_RECT ch_wattle, SKF_RIGHT, 0, 0, 1, 4, CH_RED_3, 0
    SK_RECT ch_wattle, SKF_LEFT, 0, 0, 1, 4, CH_RED_3, 0
    ; --- ch_wing_l (shared with the right wing): feather rows, tan tips; ch_tip_l (shared): the long rear feathers
    SK_FILL ch_wing_l, SKM_ALL, CH_FEATHER_2, 15
    SK_BMP ch_wing_l, SKF_RIGHT, 0, 0, ch_wing_l_side_r
    SK_BMP ch_wing_l, SKF_LEFT, 0, 0, ch_wing_l_side_l
    SK_GRAD ch_wing_l, SKM_SIDES, 272, 224
    SK_RECT ch_wing_l, SKF_TOP, 0, 0, 2, 10, CH_FEATHER_1, 15
    SK_RECT ch_wing_l, SKF_BOTTOM, 0, 0, 2, 10, CH_FEATHER_4, 0
    SK_BMP ch_wing_l, SKF_FRONT, 0, 0, ch_wing_l_edge
    SK_BMP ch_wing_l, SKF_BACK, 0, 0, ch_wing_l_edge
    SK_FILL ch_tip_l, SKM_ALL, CH_FEATHER_2, 15
    SK_BMP ch_tip_l, SKF_RIGHT, 0, 0, ch_tip_l_side_r
    SK_BMP ch_tip_l, SKF_LEFT, 0, 0, ch_tip_l_side_l
    SK_GRAD ch_tip_l, SKM_SIDES, 272, 224
    SK_RECT ch_tip_l, SKF_TOP, 0, 0, 2, 4, CH_FEATHER_1, 15
    SK_RECT ch_tip_l, SKF_BOTTOM, 0, 0, 2, 4, CH_FEATHER_4, 0
    SK_BMP ch_tip_l, SKF_FRONT, 0, 0, ch_tip_l_edge
    SK_BMP ch_tip_l, SKF_BACK, 0, 0, ch_tip_l_edge
    ; --- ch_leg_l (shared): yellow scales; ch_thigh_l (shared): a feathered thigh; the toes
    SK_FILL ch_leg_l, SKM_ALL, CH_BEAK_2, 15
    SK_BMP ch_leg_l, SKF_FRONT, 0, 0, ch_leg_front
    SK_BMP ch_leg_l, SKF_BACK, 0, 0, ch_leg_front
    SK_BMP ch_leg_l, SKF_RIGHT, 0, 0, ch_leg_side
    SK_BMP ch_leg_l, SKF_LEFT, 0, 0, ch_leg_side
    SK_RECT ch_leg_l, SKF_TOP, 0, 0, 2, 2, CH_BEAK_3, 0
    SK_RECT ch_leg_l, SKF_BOTTOM, 0, 0, 2, 2, CH_BEAK_4, 0
    SK_FILL ch_thigh_l, SKM_ALL, CH_FEATHER_2, 15
    SK_BMP ch_thigh_l, SKF_FRONT, 0, 0, ch_thigh_front
    SK_BMP ch_thigh_l, SKF_BACK, 0, 0, ch_thigh_front
    SK_BMP ch_thigh_l, SKF_RIGHT, 0, 0, ch_thigh_side
    SK_BMP ch_thigh_l, SKF_LEFT, 0, 0, ch_thigh_side
    SK_GRAD ch_thigh_l, SKM_SIDES, 272, 224
    SK_RECT ch_thigh_l, SKF_TOP, 0, 0, 4, 4, CH_FEATHER_2, 15
    SK_RECT ch_thigh_l, SKF_BOTTOM, 0, 0, 4, 4, CH_FEATHER_4, 0
    SK_FILL ch_toe_a, SKM_ALL, CH_BEAK_2, 15
    SK_RECT ch_toe_a, SKF_TOP, 0, 0, 1, 4, CH_BEAK_1, 0
    SK_RECT ch_toe_a, SKF_BOTTOM, 0, 0, 1, 4, CH_BEAK_4, 0
    SK_RECT ch_toe_a, SKF_FRONT, 0, 0, 1, 1, CH_BEAK_4, 0
    SK_RECT ch_toe_a, SKF_BACK, 0, 0, 1, 1, CH_BEAK_3, 0
    SK_RECT ch_toe_a, SKF_RIGHT, 0, 0, 4, 1, CH_BEAK_3, 0
    SK_RECT ch_toe_a, SKF_LEFT, 0, 0, 4, 1, CH_BEAK_3, 0
    SK_FILL ch_toe_m, SKM_ALL, CH_BEAK_2, 15
    SK_RECT ch_toe_m, SKF_TOP, 0, 0, 2, 5, CH_BEAK_1, 0
    SK_RECT ch_toe_m, SKF_BOTTOM, 0, 0, 2, 5, CH_BEAK_4, 0
    SK_RECT ch_toe_m, SKF_FRONT, 0, 0, 2, 1, CH_BEAK_4, 0
    SK_RECT ch_toe_m, SKF_BACK, 0, 0, 2, 1, CH_BEAK_3, 0
    SK_RECT ch_toe_m, SKF_RIGHT, 0, 0, 5, 1, CH_BEAK_3, 0
    SK_RECT ch_toe_m, SKF_LEFT, 0, 0, 5, 1, CH_BEAK_3, 0
    SK_FILL ch_toe_c, SKM_ALL, CH_BEAK_2, 15
    SK_RECT ch_toe_c, SKF_TOP, 0, 0, 2, 2, CH_BEAK_1, 0
    SK_RECT ch_toe_c, SKF_BOTTOM, 0, 0, 2, 2, CH_BEAK_4, 0
    SK_RECT ch_toe_c, SKF_FRONT, 0, 0, 2, 1, CH_BEAK_4, 0
    SK_RECT ch_toe_c, SKF_BACK, 0, 0, 2, 1, CH_BEAK_3, 0
    SK_RECT ch_toe_c, SKF_RIGHT, 0, 0, 2, 1, CH_BEAK_3, 0
    SK_RECT ch_toe_c, SKF_LEFT, 0, 0, 2, 1, CH_BEAK_3, 0
SKMODEL_END

; ===================================================================================================
; m_spider
; ===================================================================================================
RAMP SP_BODY, 64, 52, 46                ; dark brown hide (the old spider tile was (52,44,40))
RAMP SP_FUR, 112, 92, 76                ; lighter bristles, the leg rings

section .rodata
; The characters of every sp_ bitmap. Groups: base, highlight, shade, deep.
;   b B k K dark hide   f F t T bristles and tan leg rings   r R n red eyes (n the rim)   m M u red-orange marking
;   w W z fangs and claws   _ transparent
align 8
sp_pal:
    PALC 'b', SP_BODY_2
    PALC 'B', SP_BODY_1
    PALC 'k', SP_BODY_3
    PALC 'K', SP_BODY_4
    PALC 'f', SP_FUR_2
    PALC 'F', SP_FUR_1
    PALC 't', RGBO(150, 116, 78)
    PALC 'T', RGBO(190, 152, 106)
    PALC 'r', RGBO(240, 52, 44)
    PALC 'R', RGBO(255, 176, 136)
    PALC 'n', RGBO(104, 14, 22)
    PALC 'm', RGBO(214, 72, 38)
    PALC 'M', RGBO(255, 132, 64)
    PALC 'u', RGBO(148, 40, 30)
    PALC 'w', RGBO(232, 224, 196)
    PALC 'W', RGBO(255, 250, 226)
    PALC 'z', RGBO(170, 160, 130)
    PALT '_'
    dq 0

    ; sp_abdomen_top (24x24): sp_abdomen TOP
    SKROWS sp_abdomen_top_rows, 24, 24
    SKROW ".............B.........."
    SKROW "...B.f....tttt........f."
    SKROW "..fB.f..ttTTTTtt.f....f."
    SKROW "..fB.f..f.ttttf..f....ff"
    SKROW "........f.ummuf..f....ff"
    SKROW "........fummmmu.fff....."
    SKROW "B.......ummmmmmufff.f..."
    SKROW "B...f.uummmMMmmmuuf.f..."
    SKROW "....fuummmMuuMmmmuu.f..."
    SKROW "....uummmMuuuuMmmmuuf..."
    SKROW "...uummmMuukkuuMmmmuu..."
    SKROW "...uummmMuukkuuMmmmuu.f."
    SKROW "....uummmMuuuuMmmmuu..f."
    SKROW ".f..BuummmMuuMmmmuu...f."
    SKROW ".f....uummmMMmmmuu......"
    SKROW "..f.....ummmmmmu........"
    SKROW "..f......ummmmu........."
    SKROW "..........ummu.f........"
    SKROW "........Bf.uu..f........"
    SKROW "...B....Bftttt.f..f....."
    SKROW "...B....tttttttt..f....."
    SKROW "...B......tttt....B....."
    SKROW "......B................."
    SKROW "......B..............f.."
    SKROWS_END
    align 8
    SKBMP sp_abdomen_top, sp_abdomen_top_rows, 24, 24, sp_pal
    ; sp_abdomen_right (24x18): sp_abdomen RIGHT
    SKROWS sp_abdomen_right_rows, 24, 18
    SKROW "ffffff.......ff.......kk"
    SKROW "...BBBfff..............."
    SKROW "........................"
    SKROW "..kkk.ff........ff......"
    SKROW ".....ffff........kk....f"
    SKROW ".......ff..............."
    SKROW "...........fff.........."
    SKROW "...ff............BB....."
    SKROW "kkk..BTt....Ttf...Tt.kk."
    SKROW "......ttB...ttkkk.ttkk.."
    SKROW "....................fff."
    SKROW "ff......ffk....ffff....."
    SKROW ".....kBBB.......ff..ffBB"
    SKROW "...BB...BBB......ff..BBB"
    SKROW "......................ff"
    SKROW "...ff......fff.........."
    SKROW "..fff.BBB......fff......"
    SKROW ".......................f"
    SKROWS_END
    align 8
    SKBMP sp_abdomen_right, sp_abdomen_right_rows, 24, 18, sp_pal
    ; sp_abdomen_left (24x18): sp_abdomen LEFT
    SKROWS sp_abdomen_left_rows, 24, 18
    SKROW "....ff.........ff......."
    SKROW "..........fff...kk......"
    SKROW "...............kkk......"
    SKROW "..kk........BBB..BBB..kk"
    SKROW ".......ff.......BBB.BBB."
    SKROW "...BBff................."
    SKROW "fff.............kkk....."
    SKROW "............fff........."
    SKROW "....ffTt..ffTt....Tt...."
    SKROW "......ttf..ftt...ftt...."
    SKROW ".......ff..............."
    SKROW "......fff..........fffBB"
    SKROW "....ffBB..kfff.....ff..."
    SKROW ".......ffffffff........."
    SKROW "..fff.ff........ff.fffBB"
    SKROW "................kkk...ff"
    SKROW "........fff....fff...BB."
    SKROW "...ff.....kk...BBB...fff"
    SKROWS_END
    align 8
    SKBMP sp_abdomen_left, sp_abdomen_left_rows, 24, 18, sp_pal
    ; sp_abdomen_front (24x18): sp_abdomen FRONT
    SKROWS sp_abdomen_front_rows, 24, 18
    SKROW "f..f.f...f..........f..."
    SKROW "f..f.f...f.k........f..."
    SKROW "...f.f...f.k.........ff."
    SKROW "...........k.........ffB"
    SKROW "...k.......k.........ffB"
    SKROW "..fk..B....k.........B.."
    SKROW "..ff..B..f....f......B.."
    SKROW ".kff.....f....f.f....k.f"
    SKROW ".k.f.....f....f.ff...k.f"
    SKROW ".k.f.f.......B...f......"
    SKROW ".....f.f..B..B...f.....B"
    SKROW "f......f..B..B..B..B...B"
    SKROW "ff.B...f.......fB..B...B"
    SKROW "Bf.B..f........f..fk...."
    SKROW "Bf.B..f......f....f....."
    SKROW "...k..f.f..f.f....f.f..."
    SKROW "..k...f.f..f...f....f..."
    SKROW "..f...f.f..f...f..B.f..."
    SKROWS_END
    align 8
    SKBMP sp_abdomen_front, sp_abdomen_front_rows, 24, 18, sp_pal
    ; sp_abdomen_back (24x18): sp_abdomen BACK
    SKROWS sp_abdomen_back_rows, 24, 18
    SKROW ".f.....k.f........k..f.f"
    SKROW ".f.....k.f........k..f.f"
    SKROW ".......k..f...k...k....f"
    SKROW ".f........f...k........f"
    SKROW ".fB...B.....f.f........f"
    SKROW ".fB...B.....fBf........."
    SKROW "k.B...B.k..kkBf.f......f"
    SKROW "f...k...k.kkkk..f......f"
    SKROW "f...k...kkkKKkk.f.....k."
    SKROW "....k..kkkKKKKkkk..f..k."
    SKROW ".........kkKKkkB..ff..f."
    SKROW ".f.k.B..kBkkkk....ff..f."
    SKROW ".f.k.B..kB.kk.f...ff..f."
    SKROW ".f.k....kB.f..f....f...."
    SKROW ".....B.....f...f.......f"
    SKROW ".....B..B..f...f.f.....f"
    SKROW "........B..f...f.f..f..f"
    SKROW "........B.Bf.....f.ff..."
    SKROWS_END
    align 8
    SKBMP sp_abdomen_back, sp_abdomen_back_rows, 24, 18, sp_pal
    ; sp_abdomen_bottom (24x24): sp_abdomen BOTTOM
    SKROWS sp_abdomen_bottom_rows, 24, 24
    SKROW "ttttttttttttttttfttttttf"
    SKROW "ttttttttttttttttfttttttf"
    SKROW "ttkttttttttrrtttftkfttkt"
    SKROW "ttftttttttrrrrttttkfttkt"
    SKROW "ttftttttfrrrrrrkttkfttkt"
    SKROW "tftttttfrrrRRrrrtttttttt"
    SKROW "tftttttrrRRRRRRrrktttttf"
    SKROW "tftttttfrrrRRrrrtftttttf"
    SKROW "tttttttttrrrrrrtfftttftf"
    SKROW "ttttttttttrrrrttftfttftf"
    SKROW "tttttttttttrrtttftfttftt"
    SKROW "tttttttttttrrfttftfttftt"
    SKROW "ttfttttttttrrftttttttftt"
    SKROW "ttfttttttttrrfttttkftttt"
    SKROW "ttftttttttrrrrttttkftttt"
    SKROW "tttttttttrrrrrrttttttttt"
    SKROW "tttfttttrrrRRrrrtttttttt"
    SKROW "tttftttrrRRRRRRrrttftttf"
    SKROW "tttfttftrrrRRrrrttfftttf"
    SKROW "ktttttfttrrrrrrtttfttttf"
    SKROW "ktttktftttrrrrttftttfttt"
    SKROW "ttttkttttttrrfttftttfttt"
    SKROW "ttttktttttfttfttftttfttt"
    SKROW "ttkttttfttfftttkfttttttt"
    SKROWS_END
    align 8
    SKBMP sp_abdomen_bottom, sp_abdomen_bottom_rows, 24, 24, sp_pal
    ; sp_thorax_top (12x8): sp_thorax TOP
    SKROWS sp_thorax_top_rows, 12, 8
    SKROW "......f....."
    SKROW ".....tt....."
    SKROW "...ttTTtt..."
    SKROW "..ttTTTTtt.."
    SKROW "..ttTTTTtt.."
    SKROW "...ttTTtt..."
    SKROW "..f..tt..f.."
    SKROW ".kkkkkkkkkk."
    SKROWS_END
    align 8
    SKBMP sp_thorax_top, sp_thorax_top_rows, 12, 8, sp_pal
    ; sp_thorax_front (12x12): sp_thorax FRONT
    SKROWS sp_thorax_front_rows, 12, 12
    SKROW "...........f"
    SKROW "...f.......f"
    SKROW "f..f.......f"
    SKROW "f..B........"
    SKROW "f.B........."
    SKROW "f.B.....B..."
    SKROW "..B..f..B..."
    SKROW ".....f...f.."
    SKROW ".........f.."
    SKROW "..B......f.f"
    SKROW "..B......f.f"
    SKROW "..B.....f.f."
    SKROWS_END
    align 8
    SKBMP sp_thorax_front, sp_thorax_front_rows, 12, 12, sp_pal
    ; sp_thorax_back (12x12): sp_thorax BACK
    SKROWS sp_thorax_back_rows, 12, 12
    SKROW "............"
    SKROW "..........ff"
    SKROW "........f.ff"
    SKROW "...f....f.ff"
    SKROW "...f..f....."
    SKROW "......f....."
    SKROW "............"
    SKROW ".........B.."
    SKROW ".........B.."
    SKROW "f....B.f..B."
    SKROW "f....B.f.fB."
    SKROW "f....f...fB."
    SKROWS_END
    align 8
    SKBMP sp_thorax_back, sp_thorax_back_rows, 12, 12, sp_pal
    ; sp_thorax_right (8x12): sp_thorax RIGHT
    SKROWS sp_thorax_right_rows, 8, 12
    SKROW ".......f"
    SKROW "fff.fff."
    SKROW "...BBff."
    SKROW "........"
    SKROW "....ffBB"
    SKROW "........"
    SKROW "........"
    SKROW "......ff"
    SKROW ".......f"
    SKROW "...BfffB"
    SKROW "fff..BB."
    SKROW "........"
    SKROWS_END
    align 8
    SKBMP sp_thorax_right, sp_thorax_right_rows, 8, 12, sp_pal
    ; sp_thorax_left (8x12): sp_thorax LEFT
    SKROWS sp_thorax_left_rows, 8, 12
    SKROW "...BB..."
    SKROW ".BBB..BB"
    SKROW "........"
    SKROW "........"
    SKROW "BBB.fff."
    SKROW "..ffff.."
    SKROW ".ffffff."
    SKROW ".......B"
    SKROW "........"
    SKROW "..ff...."
    SKROW "........"
    SKROW "..fff..f"
    SKROWS_END
    align 8
    SKBMP sp_thorax_left, sp_thorax_left_rows, 8, 12, sp_pal
    ; sp_head_front (16x16): sp_head FRONT
    SKROWS sp_head_front_rows, 16, 16
    SKROW "BBBBBBBBBBBBBBBB"
    SKROW "..f..........fB."
    SKROW "..f............."
    SKROW ".kkkKkkKkkkKkKk."
    SKROW ".kkrKkrKkrKkrKk."
    SKROW ".KkKKnKKnKKkKKk."
    SKROW ".kRrKRrKnRrKRrK."
    SKROW ".kKKKrrKnrrKKKK."
    SKROW "BkkkkKKKkKKKkkK."
    SKROW "Bf............f."
    SKROW "B.....KKKK.....B"
    SKROW ".....KKKKKKf..BB"
    SKROW "....kKKKKKKk..B."
    SKROW "....fKKKKKKf...."
    SKROW "..B.fkkkkkkf...."
    SKROW "..B..B.....f...f"
    SKROWS_END
    align 8
    SKBMP sp_head_front, sp_head_front_rows, 16, 16, sp_pal
    ; sp_head_top (16x16): sp_head TOP
    SKROWS sp_head_top_rows, 16, 16
    SKROW ".......kk......."
    SKROW ".......kk.B..f.."
    SKROW ".B.....kkfB..f.."
    SKROW ".B.B...kkff..f.."
    SKROW ".B.B...kk.f.f..."
    SKROW "...f...kkff.f..."
    SKROW "...f...kkf.Bf..."
    SKROW "f..f...ttf.B...f"
    SKROW "f.....tttt.....f"
    SKROW "f.....tttt......"
    SKROW ".....tttttt....."
    SKROW "..f.B.tttt.....f"
    SKROW "..f.B.tttt.f.f.f"
    SKROW "f.f....tt..f.f.."
    SKROW "f......kk..B...."
    SKROW "..f...fkk......."
    SKROWS_END
    align 8
    SKBMP sp_head_top, sp_head_top_rows, 16, 16, sp_pal
    ; sp_head_back (16x16): sp_head BACK
    SKROWS sp_head_back_rows, 16, 16
    SKROW "..........f....."
    SKROW "..........f.f..."
    SKROW ".k........fff..k"
    SKROW "fk.........ff..k"
    SKROW "fk.k.......f...."
    SKROW "f..k...f........"
    SKROW ".......f........"
    SKROW ".......f......f."
    SKROW "....f....ff...f."
    SKROW "....f...fff...f."
    SKROW "....f...f.f....."
    SKROW "....k..........."
    SKROW "....k...f......."
    SKROW "......fff.....f."
    SKROW "......fff.....f."
    SKROW "...kk.fff.....f."
    SKROWS_END
    align 8
    SKBMP sp_head_back, sp_head_back_rows, 16, 16, sp_pal
    ; sp_head_side_r (16x16): sp_head RIGHT
    SKROWS sp_head_side_r_rows, 16, 16
    SKROW "..............ff"
    SKROW "....ff.........k"
    SKROW "................"
    SKROW "...fff.........."
    SKROW "............r..."
    SKROW "..........ffkRBB"
    SKROW "...BBff......r.B"
    SKROW "..kkk......fff.."
    SKROW "............kkk."
    SKROW "..........ff...."
    SKROW ".ff..fff.....fff"
    SKROW "....ff.BBB......"
    SKROW "...........fff.."
    SKROW ".ff...ff...kk..."
    SKROW "...............k"
    SKROW "..........BB...."
    SKROWS_END
    align 8
    SKBMP sp_head_side_r, sp_head_side_r_rows, 16, 16, sp_pal
    ; sp_head_side_l (16x16): sp_head LEFT
    SKROWS sp_head_side_l_rows, 16, 16
    SKROW "ff.............."
    SKROW "k.........ff...."
    SKROW "................"
    SKROW "..........fff..."
    SKROW "...r............"
    SKROW "BBRkff.........."
    SKROW "B.r......ffBB..."
    SKROW "..fff......kkk.."
    SKROW ".kkk............"
    SKROW "....ff.........."
    SKROW "fff.....fff..ff."
    SKROW "......BBB.ff...."
    SKROW "..fff..........."
    SKROW "...kk...ff...ff."
    SKROW "k..............."
    SKROW "....BB.........."
    SKROWS_END
    align 8
    SKBMP sp_head_side_l, sp_head_side_l_rows, 16, 16, sp_pal
    ; sp_fang_front (2x5): sp_fang_r FRONT
    SKROWS sp_fang_front_rows, 2, 5
    SKROW "kk"
    SKROW "WW"
    SKROW "ww"
    SKROW "wz"
    SKROW "KK"
    SKROWS_END
    align 8
    SKBMP sp_fang_front, sp_fang_front_rows, 2, 5, sp_pal
    ; sp_fang_back (2x5): sp_fang_r BACK
    SKROWS sp_fang_back_rows, 2, 5
    SKROW "kk"
    SKROW "Ww"
    SKROW "wz"
    SKROW "zz"
    SKROW "KK"
    SKROWS_END
    align 8
    SKBMP sp_fang_back, sp_fang_back_rows, 2, 5, sp_pal
    ; sp_fang_side (2x5): sp_fang_r RIGHT/LEFT
    SKROWS sp_fang_side_rows, 2, 5
    SKROW "kk"
    SKROW "Ww"
    SKROW "wz"
    SKROW "zz"
    SKROW "KK"
    SKROWS_END
    align 8
    SKBMP sp_fang_side, sp_fang_side_rows, 2, 5, sp_pal
    ; sp_palp_front (3x3): sp_palp_r FRONT
    SKROWS sp_palp_front_rows, 3, 3
    SKROW "fBf"
    SKROW "bbb"
    SKROW "kkk"
    SKROWS_END
    align 8
    SKBMP sp_palp_front, sp_palp_front_rows, 3, 3, sp_pal
    ; sp_ru_l0_front (16x4): sp_ru_l0 FRONT
    SKROWS sp_ru_l0_front_rows, 16, 4
    SKROW "kBBBBBBBBBBBBBtT"
    SKROW "kffff.fff.....tT"
    SKROW "k.fff..ff..kkktT"
    SKROW "kkkkkkkkkkkkkktT"
    SKROWS_END
    align 8
    SKBMP sp_ru_l0_front, sp_ru_l0_front_rows, 16, 4, sp_pal
    ; sp_ru_l0_back (16x4): sp_ru_l0 BACK
    SKROWS sp_ru_l0_back_rows, 16, 4
    SKROW "TtBBBBBBBBBBBBBk"
    SKROW "Tt.........fff.k"
    SKROW "Tt...ffffff...fk"
    SKROW "Ttkkkkkkkkkkkkkk"
    SKROWS_END
    align 8
    SKBMP sp_ru_l0_back, sp_ru_l0_back_rows, 16, 4, sp_pal
    ; sp_ru_l0_top (16x4): sp_ru_l0 TOP
    SKROWS sp_ru_l0_top_rows, 16, 4
    SKROW ".fff.....fff...."
    SKROW "...fffff.......f"
    SKROW "...BfffBBBfff..."
    SKROW ".BB............B"
    SKROWS_END
    align 8
    SKBMP sp_ru_l0_top, sp_ru_l0_top_rows, 16, 4, sp_pal
    ; sp_kn_l0_front (6x10): sp_kn_l0 FRONT
    SKROWS sp_kn_l0_front_rows, 6, 10
    SKROW "TTTTTT"
    SKROW "tttttt"
    SKROW "Bf.k.k"
    SKROW "B..k.k"
    SKROW "B....k"
    SKROW "Bk...k"
    SKROW "Bk...k"
    SKROW "B.f.kk"
    SKROW "kkkkkk"
    SKROW "KKKKKK"
    SKROWS_END
    align 8
    SKBMP sp_kn_l0_front, sp_kn_l0_front_rows, 6, 10, sp_pal
    ; sp_kn_l0_back (6x10): sp_kn_l0 BACK
    SKROWS sp_kn_l0_back_rows, 6, 10
    SKROW "TTTTTT"
    SKROW "tttttt"
    SKROW "k.k.fB"
    SKROW "k.k..B"
    SKROW "k....B"
    SKROW "k...kB"
    SKROW "k...kB"
    SKROW "kk.f.B"
    SKROW "kkkkkk"
    SKROW "KKKKKK"
    SKROWS_END
    align 8
    SKBMP sp_kn_l0_back, sp_kn_l0_back_rows, 6, 10, sp_pal
    ; sp_kn_l0_side (4x10): sp_kn_l0 RIGHT/LEFT
    SKROWS sp_kn_l0_side_rows, 4, 10
    SKROW "TTTT"
    SKROW "tttt"
    SKROW "k.k."
    SKROW "k.k."
    SKROW "k..."
    SKROW "..f."
    SKROW "..f."
    SKROW "..f."
    SKROW "..f."
    SKROW "KKKK"
    SKROWS_END
    align 8
    SKBMP sp_kn_l0_side, sp_kn_l0_side_rows, 4, 10, sp_pal
    ; sp_kn_l0_top (6x4): sp_kn_l0 TOP
    SKROWS sp_kn_l0_top_rows, 6, 4
    SKROW "B....."
    SKROW "Bf.f.."
    SKROW ".f.f.."
    SKROW "...f.."
    SKROWS_END
    align 8
    SKBMP sp_kn_l0_top, sp_kn_l0_top_rows, 6, 4, sp_pal
    ; sp_t1_l0_front (4x14): sp_t1_l0 FRONT
    SKROWS sp_t1_l0_front_rows, 4, 14
    SKROW "tttt"
    SKROW "Bffk"
    SKROW "B.fk"
    SKROW "B.fk"
    SKROW "B.fk"
    SKROW "B.fk"
    SKROW "Bkfk"
    SKROW "Bkfk"
    SKROW "Bk.k"
    SKROW "B.fk"
    SKROW "B.fk"
    SKROW "B.fk"
    SKROW "B..k"
    SKROW "tttt"
    SKROWS_END
    align 8
    SKBMP sp_t1_l0_front, sp_t1_l0_front_rows, 4, 14, sp_pal
    ; sp_t1_l0_back (4x14): sp_t1_l0 BACK
    SKROWS sp_t1_l0_back_rows, 4, 14
    SKROW "tttt"
    SKROW "kffB"
    SKROW "kf.B"
    SKROW "kf.B"
    SKROW "kf.B"
    SKROW "kf.B"
    SKROW "kfkB"
    SKROW "kfkB"
    SKROW "k.kB"
    SKROW "kf.B"
    SKROW "kf.B"
    SKROW "kf.B"
    SKROW "k..B"
    SKROW "tttt"
    SKROWS_END
    align 8
    SKBMP sp_t1_l0_back, sp_t1_l0_back_rows, 4, 14, sp_pal
    ; sp_t1_l0_side (4x14): sp_t1_l0 RIGHT/LEFT
    SKROWS sp_t1_l0_side_rows, 4, 14
    SKROW "tttt"
    SKROW "Bf.k"
    SKROW "Bfkk"
    SKROW "Bfkk"
    SKROW "B.kk"
    SKROW "Bf.k"
    SKROW "Bf.k"
    SKROW "Bf.k"
    SKROW "Bkfk"
    SKROW "Bkfk"
    SKROW "Bkfk"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "tttt"
    SKROWS_END
    align 8
    SKBMP sp_t1_l0_side, sp_t1_l0_side_rows, 4, 14, sp_pal
    ; sp_t2_l0_front (4x12): sp_t2_l0 FRONT
    SKROWS sp_t2_l0_front_rows, 4, 12
    SKROW "tttt"
    SKROW "B..k"
    SKROW "Bf.k"
    SKROW "Bfkk"
    SKROW "B.kk"
    SKROW "B..k"
    SKROW "Bf.k"
    SKROW "Bfff"
    SKROW "BFFF"
    SKROW "Bfff"
    SKROW "WWWW"
    SKROW "zzzz"
    SKROWS_END
    align 8
    SKBMP sp_t2_l0_front, sp_t2_l0_front_rows, 4, 12, sp_pal
    ; sp_t2_l0_back (4x12): sp_t2_l0 BACK
    SKROWS sp_t2_l0_back_rows, 4, 12
    SKROW "tttt"
    SKROW "k..B"
    SKROW "k.fB"
    SKROW "kkfB"
    SKROW "kk.B"
    SKROW "k..B"
    SKROW "k.fB"
    SKROW "fffB"
    SKROW "FFFB"
    SKROW "fffB"
    SKROW "WWWW"
    SKROW "zzzz"
    SKROWS_END
    align 8
    SKBMP sp_t2_l0_back, sp_t2_l0_back_rows, 4, 12, sp_pal
    ; sp_t2_l0_side (4x12): sp_t2_l0 RIGHT/LEFT
    SKROWS sp_t2_l0_side_rows, 4, 12
    SKROW "tttt"
    SKROW "B..k"
    SKROW "Bffk"
    SKROW "Bffk"
    SKROW "Bf.k"
    SKROW "Bf.k"
    SKROW "B.fk"
    SKROW "Bfff"
    SKROW "BFFF"
    SKROW "Bfff"
    SKROW "WWWW"
    SKROW "zzzz"
    SKROWS_END
    align 8
    SKBMP sp_t2_l0_side, sp_t2_l0_side_rows, 4, 12, sp_pal
    ; sp_ru_r0_front (16x4): sp_ru_r0 FRONT
    SKROWS sp_ru_r0_front_rows, 16, 4
    SKROW "TtBBBBBBBBBBBBBk"
    SKROW "Ttf.......fff..k"
    SKROW "Tt......fffkfffk"
    SKROW "Ttkkkkkkkkkkkkkk"
    SKROWS_END
    align 8
    SKBMP sp_ru_r0_front, sp_ru_r0_front_rows, 16, 4, sp_pal
    ; sp_ru_r0_back (16x4): sp_ru_r0 BACK
    SKROWS sp_ru_r0_back_rows, 16, 4
    SKROW "kBBBBBBBBBBBBBtT"
    SKROW "kkff.kkk.ff...tT"
    SKROW "k......kff..kktT"
    SKROW "kkkkkkkkkkkkkktT"
    SKROWS_END
    align 8
    SKBMP sp_ru_r0_back, sp_ru_r0_back_rows, 16, 4, sp_pal
    ; sp_ru_r0_top (16x4): sp_ru_r0 TOP
    SKROWS sp_ru_r0_top_rows, 16, 4
    SKROW ".............fff"
    SKROW "...ff...fffB..Bf"
    SKROW "..........fffff."
    SKROW "...BBffff...BB.."
    SKROWS_END
    align 8
    SKBMP sp_ru_r0_top, sp_ru_r0_top_rows, 16, 4, sp_pal
    ; sp_kn_r0_front (6x10): sp_kn_r0 FRONT
    SKROWS sp_kn_r0_front_rows, 6, 10
    SKROW "TTTTTT"
    SKROW "tttttt"
    SKROW "Bf.f.k"
    SKROW "Bf.k.k"
    SKROW "Bf.kfk"
    SKROW "B..kfk"
    SKROW "Bf.ffk"
    SKROW "Bf.f.k"
    SKROW "kkkkkk"
    SKROW "KKKKKK"
    SKROWS_END
    align 8
    SKBMP sp_kn_r0_front, sp_kn_r0_front_rows, 6, 10, sp_pal
    ; sp_kn_r0_back (6x10): sp_kn_r0 BACK
    SKROWS sp_kn_r0_back_rows, 6, 10
    SKROW "TTTTTT"
    SKROW "tttttt"
    SKROW "k.f.fB"
    SKROW "k.k.fB"
    SKROW "kfk.fB"
    SKROW "kfk..B"
    SKROW "kff.fB"
    SKROW "k.f.fB"
    SKROW "kkkkkk"
    SKROW "KKKKKK"
    SKROWS_END
    align 8
    SKBMP sp_kn_r0_back, sp_kn_r0_back_rows, 6, 10, sp_pal
    ; sp_kn_r0_side (4x10): sp_kn_r0 RIGHT/LEFT
    SKROWS sp_kn_r0_side_rows, 4, 10
    SKROW "TTTT"
    SKROW "tttt"
    SKROW "f..."
    SKROW "...f"
    SKROW "...f"
    SKROW "...f"
    SKROW "f.ff"
    SKROW "fkff"
    SKROW ".kf."
    SKROW "KKKK"
    SKROWS_END
    align 8
    SKBMP sp_kn_r0_side, sp_kn_r0_side_rows, 4, 10, sp_pal
    ; sp_kn_r0_top (6x4): sp_kn_r0 TOP
    SKROWS sp_kn_r0_top_rows, 6, 4
    SKROW "...f.."
    SKROW ".f.ff."
    SKROW ".f.ff."
    SKROW ".ffBfB"
    SKROWS_END
    align 8
    SKBMP sp_kn_r0_top, sp_kn_r0_top_rows, 6, 4, sp_pal
    ; sp_t1_r0_front (4x14): sp_t1_r0 FRONT
    SKROWS sp_t1_r0_front_rows, 4, 14
    SKROW "tttt"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "B.kk"
    SKROW "B.kk"
    SKROW "B..k"
    SKROW "B.kk"
    SKROW "B.kk"
    SKROW "B.kk"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "tttt"
    SKROWS_END
    align 8
    SKBMP sp_t1_r0_front, sp_t1_r0_front_rows, 4, 14, sp_pal
    ; sp_t1_r0_back (4x14): sp_t1_r0 BACK
    SKROWS sp_t1_r0_back_rows, 4, 14
    SKROW "tttt"
    SKROW "k..B"
    SKROW "k..B"
    SKROW "kk.B"
    SKROW "kk.B"
    SKROW "k..B"
    SKROW "kk.B"
    SKROW "kk.B"
    SKROW "kk.B"
    SKROW "k..B"
    SKROW "k..B"
    SKROW "k..B"
    SKROW "k..B"
    SKROW "tttt"
    SKROWS_END
    align 8
    SKBMP sp_t1_r0_back, sp_t1_r0_back_rows, 4, 14, sp_pal
    ; sp_t1_r0_side (4x14): sp_t1_r0 RIGHT/LEFT
    SKROWS sp_t1_r0_side_rows, 4, 14
    SKROW "tttt"
    SKROW "B.fk"
    SKROW "Bkfk"
    SKROW "Bk.k"
    SKROW "B..k"
    SKROW "Bf.k"
    SKROW "Bf.k"
    SKROW "Bf.k"
    SKROW "Bffk"
    SKROW "Bffk"
    SKROW "B..k"
    SKROW "B.fk"
    SKROW "B.fk"
    SKROW "tttt"
    SKROWS_END
    align 8
    SKBMP sp_t1_r0_side, sp_t1_r0_side_rows, 4, 14, sp_pal
    ; sp_t2_r0_front (4x12): sp_t2_r0 FRONT
    SKROWS sp_t2_r0_front_rows, 4, 12
    SKROW "tttt"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "Bfff"
    SKROW "BFFF"
    SKROW "Bfff"
    SKROW "WWWW"
    SKROW "zzzz"
    SKROWS_END
    align 8
    SKBMP sp_t2_r0_front, sp_t2_r0_front_rows, 4, 12, sp_pal
    ; sp_t2_r0_back (4x12): sp_t2_r0 BACK
    SKROWS sp_t2_r0_back_rows, 4, 12
    SKROW "tttt"
    SKROW "k..B"
    SKROW "k..B"
    SKROW "k..B"
    SKROW "k..B"
    SKROW "k..B"
    SKROW "k..B"
    SKROW "fffB"
    SKROW "FFFB"
    SKROW "fffB"
    SKROW "WWWW"
    SKROW "zzzz"
    SKROWS_END
    align 8
    SKBMP sp_t2_r0_back, sp_t2_r0_back_rows, 4, 12, sp_pal
    ; sp_t2_r0_side (4x12): sp_t2_r0 RIGHT/LEFT
    SKROWS sp_t2_r0_side_rows, 4, 12
    SKROW "tttt"
    SKROW "Bf.k"
    SKROW "Bffk"
    SKROW "Bffk"
    SKROW "Bffk"
    SKROW "B..k"
    SKROW "B..k"
    SKROW "Bfff"
    SKROW "BFFF"
    SKROW "Bfff"
    SKROW "WWWW"
    SKROW "zzzz"
    SKROWS_END
    align 8
    SKBMP sp_t2_r0_side, sp_t2_r0_side_rows, 4, 12, sp_pal

section .data
SKMODEL_BEGIN m_spider, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART sp_abdomen, -12, 8, 0, 24, 18, 24, 0, 0            ; abdomen: red-orange diamond above, red hourglass below
    PART sp_spinneret, -3, 10, 24, 6, 6, 3, 0, 0            ; spinneret behind the abdomen
    PART sp_thorax, -6, 10, -8, 12, 12, 8, 0, 0             ; thorax with a tan saddle
    SKBONE BK_HEAD, 0, 0, 0.00
    PART sp_head, -8, 8, -24, 16, 16, 16, 0, 0              ; head: eight red eyes in three rows, a dark mouth
    PART sp_fang_r, 2, 3, -24, 2, 5, 2, 0, 0                ; fangs hanging from the mouth
    PART_AS sp_fang_l, sp_fang_r, -4, 3, -24, 0, 0
    PART sp_palp_r, 5, 5, -27, 3, 3, 4, 0, 0                ; palps beside the mouth
    PART_AS sp_palp_l, sp_palp_r, -8, 5, -27, 0, 0
    SKBONE BK_LIMB, 18, -12, 0.50
    PART sp_ru_l0, -22, 16, -14, 16, 4, 4, 0, 0             ; upper run out of the body (skins shared by the left legs)
    PART sp_kn_l0, -26, 18, -16, 6, 10, 4, 4, 0             ; knee block, the highest point, a knob wider than the leg
    PART sp_t1_l0, -29, 10, -19, 4, 14, 4, 0, 0             ; upper stilt, leaning outward
    PART sp_t2_l0, -32, 0, -19, 4, 12, 4, 4, 0              ; foot stilt down to the ground, slightly flared
    SKBONE BK_LIMB, 18, -4, -0.50
    PART_AS sp_ru_l1, sp_ru_l0, -22, 16, -6, 0, 0
    PART_AS sp_kn_l1, sp_kn_l0, -26, 18, -7, 4, 0
    PART_AS sp_t1_l1, sp_t1_l0, -29, 10, -8, 0, 0
    PART_AS sp_t2_l1, sp_t2_l0, -32, 0, -8, 4, 0
    SKBONE BK_LIMB, 18, 4, 0.50
    PART_AS sp_ru_l2, sp_ru_l0, -22, 16, 2, 0, 0
    PART_AS sp_kn_l2, sp_kn_l0, -26, 18, 3, 4, 0
    PART_AS sp_t1_l2, sp_t1_l0, -29, 10, 4, 0, 0
    PART_AS sp_t2_l2, sp_t2_l0, -32, 0, 4, 4, 0
    SKBONE BK_LIMB, 18, 12, -0.50
    PART_AS sp_ru_l3, sp_ru_l0, -22, 16, 10, 0, 0
    PART_AS sp_kn_l3, sp_kn_l0, -26, 18, 12, 4, 0
    PART_AS sp_t1_l3, sp_t1_l0, -29, 10, 15, 0, 0
    PART_AS sp_t2_l3, sp_t2_l0, -32, 0, 15, 4, 0
    SKBONE BK_LIMB, 18, -12, -0.50
    PART sp_ru_r0, 6, 16, -14, 16, 4, 4, 0, 0
    PART sp_kn_r0, 20, 18, -16, 6, 10, 4, 4, 0
    PART sp_t1_r0, 25, 10, -19, 4, 14, 4, 0, 0
    PART sp_t2_r0, 28, 0, -19, 4, 12, 4, 4, 0
    SKBONE BK_LIMB, 18, -4, 0.50
    PART_AS sp_ru_r1, sp_ru_r0, 6, 16, -6, 0, 0
    PART_AS sp_kn_r1, sp_kn_r0, 20, 18, -7, 4, 0
    PART_AS sp_t1_r1, sp_t1_r0, 25, 10, -8, 0, 0
    PART_AS sp_t2_r1, sp_t2_r0, 28, 0, -8, 4, 0
    SKBONE BK_LIMB, 18, 4, -0.50
    PART_AS sp_ru_r2, sp_ru_r0, 6, 16, 2, 0, 0
    PART_AS sp_kn_r2, sp_kn_r0, 20, 18, 3, 4, 0
    PART_AS sp_t1_r2, sp_t1_r0, 25, 10, 4, 0, 0
    PART_AS sp_t2_r2, sp_t2_r0, 28, 0, 4, 4, 0
    SKBONE BK_LIMB, 18, 12, 0.50
    PART_AS sp_ru_r3, sp_ru_r0, 6, 16, 10, 0, 0
    PART_AS sp_kn_r3, sp_kn_r0, 20, 18, 12, 4, 0
    PART_AS sp_t1_r3, sp_t1_r0, 25, 10, 15, 0, 0
    PART_AS sp_t2_r3, sp_t2_r0, 28, 0, 15, 4, 0
SKMODEL_PAINT
    ; --- sp_abdomen: dark bristly hide; red-orange diamond with a dark heart on top, red hourglass underneath
    SK_FILL sp_abdomen, SKM_ALL, SP_BODY_2, 31
    SK_BMP sp_abdomen, SKF_TOP, 0, 0, sp_abdomen_top
    SK_BMP sp_abdomen, SKF_RIGHT, 0, 0, sp_abdomen_right
    SK_BMP sp_abdomen, SKF_LEFT, 0, 0, sp_abdomen_left
    SK_BMP sp_abdomen, SKF_FRONT, 0, 0, sp_abdomen_front
    SK_BMP sp_abdomen, SKF_BACK, 0, 0, sp_abdomen_back
    SK_GRAD sp_abdomen, SKM_SIDES, 272, 224
    SK_BMP sp_abdomen, SKF_BOTTOM, 0, 0, sp_abdomen_bottom
    ; --- sp_spinneret, sp_thorax
    SK_FILL sp_spinneret, SKM_ALL, SP_BODY_3, 15
    SK_RECT sp_spinneret, SKF_BACK, 1, 1, 4, 4, SP_BODY_4, 0
    SK_RECT sp_spinneret, SKF_BACK, 2, 2, 2, 2, SP_FUR_2, 0
    SK_RECT sp_spinneret, SKF_TOP, 0, 0, 6, 3, SP_BODY_2, 15
    SK_GRAD sp_spinneret, SKM_SIDES, 272, 232
    SK_FILL sp_thorax, SKM_ALL, SP_BODY_2, 31
    SK_BMP sp_thorax, SKF_TOP, 0, 0, sp_thorax_top
    SK_BMP sp_thorax, SKF_FRONT, 0, 0, sp_thorax_front
    SK_BMP sp_thorax, SKF_BACK, 0, 0, sp_thorax_back
    SK_BMP sp_thorax, SKF_RIGHT, 0, 0, sp_thorax_right
    SK_BMP sp_thorax, SKF_LEFT, 0, 0, sp_thorax_left
    SK_GRAD sp_thorax, SKM_SIDES, 272, 224
    SK_RECT sp_thorax, SKF_BOTTOM, 0, 0, 12, 8, SP_BODY_4, 0
    ; --- sp_head: eight red eyes (two big, two medium, four small), a dark mouth under them, bristles
    SK_FILL sp_head, SKM_ALL, SP_BODY_2, 31
    SK_GRAD sp_head, SKM_SIDES, 272, 224
    SK_BMP sp_head, SKF_FRONT, 0, 0, sp_head_front
    SK_BMP sp_head, SKF_TOP, 0, 0, sp_head_top
    SK_BMP sp_head, SKF_BACK, 0, 0, sp_head_back
    SK_BMP sp_head, SKF_RIGHT, 0, 0, sp_head_side_r
    SK_BMP sp_head, SKF_LEFT, 0, 0, sp_head_side_l
    SK_RECT sp_head, SKF_BOTTOM, 0, 0, 16, 16, SP_BODY_4, 0
    ; --- sp_fang_r (shared with sp_fang_l): a pale curved fang; sp_palp_r (shared): hairy palps
    SK_FILL sp_fang_r, SKM_ALL, RGBO(232, 224, 196), 7
    SK_BMP sp_fang_r, SKF_FRONT, 0, 0, sp_fang_front
    SK_BMP sp_fang_r, SKF_BACK, 0, 0, sp_fang_back
    SK_BMP sp_fang_r, SKF_RIGHT, 0, 0, sp_fang_side
    SK_BMP sp_fang_r, SKF_LEFT, 0, 0, sp_fang_side
    SK_RECT sp_fang_r, SKF_TOP, 0, 0, 2, 2, SP_BODY_4, 0
    SK_RECT sp_fang_r, SKF_BOTTOM, 0, 0, 2, 2, SP_BODY_4, 0
    SK_FILL sp_palp_r, SKM_ALL, SP_BODY_2, 31
    SK_BMP sp_palp_r, SKF_FRONT, 0, 0, sp_palp_front
    SK_RECT sp_palp_r, SKF_TOP, 0, 0, 3, 4, SP_FUR_2, 15
    SK_RECT sp_palp_r, SKF_BOTTOM, 0, 0, 3, 4, SP_BODY_4, 0
    SK_GRAD sp_palp_r, SKM_SIDES, 272, 224
    ; --- the left legs (skins shared by the four legs of the side): upper run, knee block, two stilt steps
    SK_FILL sp_ru_l0, SKM_ALL, SP_BODY_2, 31
    SK_BMP sp_ru_l0, SKF_FRONT, 0, 0, sp_ru_l0_front
    SK_BMP sp_ru_l0, SKF_BACK, 0, 0, sp_ru_l0_back
    SK_BMP sp_ru_l0, SKF_TOP, 0, 0, sp_ru_l0_top
    SK_RECT sp_ru_l0, SKF_BOTTOM, 0, 0, 16, 4, SP_BODY_4, 0
    SK_RECT sp_ru_l0, SKF_RIGHT, 0, 0, 4, 4, SP_BODY_3, 0
    SK_RECT sp_ru_l0, SKF_LEFT, 0, 0, 4, 4, SP_BODY_3, 0
    SK_FILL sp_kn_l0, SKM_ALL, SP_BODY_2, 31
    SK_BMP sp_kn_l0, SKF_FRONT, 0, 0, sp_kn_l0_front
    SK_BMP sp_kn_l0, SKF_BACK, 0, 0, sp_kn_l0_back
    SK_BMP sp_kn_l0, SKF_RIGHT, 0, 0, sp_kn_l0_side
    SK_BMP sp_kn_l0, SKF_LEFT, 0, 0, sp_kn_l0_side
    SK_BMP sp_kn_l0, SKF_TOP, 0, 0, sp_kn_l0_top
    SK_RECT sp_kn_l0, SKF_BOTTOM, 0, 0, 6, 4, SP_BODY_4, 0
    SK_FILL sp_t1_l0, SKM_ALL, SP_BODY_2, 31
    SK_BMP sp_t1_l0, SKF_FRONT, 0, 0, sp_t1_l0_front
    SK_BMP sp_t1_l0, SKF_BACK, 0, 0, sp_t1_l0_back
    SK_BMP sp_t1_l0, SKF_RIGHT, 0, 0, sp_t1_l0_side
    SK_BMP sp_t1_l0, SKF_LEFT, 0, 0, sp_t1_l0_side
    SK_RECT sp_t1_l0, SKF_TOP, 0, 0, 4, 4, SP_BODY_3, 15
    SK_RECT sp_t1_l0, SKF_BOTTOM, 0, 0, 4, 4, SP_BODY_4, 0
    SK_FILL sp_t2_l0, SKM_ALL, SP_BODY_2, 31
    SK_BMP sp_t2_l0, SKF_FRONT, 0, 0, sp_t2_l0_front
    SK_BMP sp_t2_l0, SKF_BACK, 0, 0, sp_t2_l0_back
    SK_BMP sp_t2_l0, SKF_RIGHT, 0, 0, sp_t2_l0_side
    SK_BMP sp_t2_l0, SKF_LEFT, 0, 0, sp_t2_l0_side
    SK_RECT sp_t2_l0, SKF_TOP, 0, 0, 4, 4, SP_BODY_3, 15
    SK_RECT sp_t2_l0, SKF_BOTTOM, 0, 0, 4, 4, SP_BODY_4, 0
    ; --- the right legs (skins shared by the four legs of the side): upper run, knee block, two stilt steps
    SK_FILL sp_ru_r0, SKM_ALL, SP_BODY_2, 31
    SK_BMP sp_ru_r0, SKF_FRONT, 0, 0, sp_ru_r0_front
    SK_BMP sp_ru_r0, SKF_BACK, 0, 0, sp_ru_r0_back
    SK_BMP sp_ru_r0, SKF_TOP, 0, 0, sp_ru_r0_top
    SK_RECT sp_ru_r0, SKF_BOTTOM, 0, 0, 16, 4, SP_BODY_4, 0
    SK_RECT sp_ru_r0, SKF_RIGHT, 0, 0, 4, 4, SP_BODY_3, 0
    SK_RECT sp_ru_r0, SKF_LEFT, 0, 0, 4, 4, SP_BODY_3, 0
    SK_FILL sp_kn_r0, SKM_ALL, SP_BODY_2, 31
    SK_BMP sp_kn_r0, SKF_FRONT, 0, 0, sp_kn_r0_front
    SK_BMP sp_kn_r0, SKF_BACK, 0, 0, sp_kn_r0_back
    SK_BMP sp_kn_r0, SKF_RIGHT, 0, 0, sp_kn_r0_side
    SK_BMP sp_kn_r0, SKF_LEFT, 0, 0, sp_kn_r0_side
    SK_BMP sp_kn_r0, SKF_TOP, 0, 0, sp_kn_r0_top
    SK_RECT sp_kn_r0, SKF_BOTTOM, 0, 0, 6, 4, SP_BODY_4, 0
    SK_FILL sp_t1_r0, SKM_ALL, SP_BODY_2, 31
    SK_BMP sp_t1_r0, SKF_FRONT, 0, 0, sp_t1_r0_front
    SK_BMP sp_t1_r0, SKF_BACK, 0, 0, sp_t1_r0_back
    SK_BMP sp_t1_r0, SKF_RIGHT, 0, 0, sp_t1_r0_side
    SK_BMP sp_t1_r0, SKF_LEFT, 0, 0, sp_t1_r0_side
    SK_RECT sp_t1_r0, SKF_TOP, 0, 0, 4, 4, SP_BODY_3, 15
    SK_RECT sp_t1_r0, SKF_BOTTOM, 0, 0, 4, 4, SP_BODY_4, 0
    SK_FILL sp_t2_r0, SKM_ALL, SP_BODY_2, 31
    SK_BMP sp_t2_r0, SKF_FRONT, 0, 0, sp_t2_r0_front
    SK_BMP sp_t2_r0, SKF_BACK, 0, 0, sp_t2_r0_back
    SK_BMP sp_t2_r0, SKF_RIGHT, 0, 0, sp_t2_r0_side
    SK_BMP sp_t2_r0, SKF_LEFT, 0, 0, sp_t2_r0_side
    SK_RECT sp_t2_r0, SKF_TOP, 0, 0, 4, 4, SP_BODY_3, 15
    SK_RECT sp_t2_r0, SKF_BOTTOM, 0, 0, 4, 4, SP_BODY_4, 0
SKMODEL_END
