; skins_vehicles.asm: skin models of the vehicles (0.13 "looks"): the boat, the plane and its propeller. Data only:
; bones, parts and paint ops for skin.asm (art.inc, common.inc "0.13 looks"); nothing here runs.
;
;   m_boat         planked rowboat, 25 parts, prefix bt_ (51 atlas rows packed alone): a lapstrake hull on a slab
;                  floor, a stepped foredeck up to a raised stem post with an iron strap and mooring ring, gunwales
;                  with a red and cream sheer band, two thwarts, a lidded stern locker, ribs, oarlocks, a rope coil,
;                  a stern board with iron straps
;   m_plane        red and cream monoplane, 40 parts, prefix pl_ (142 rows): a radial engine behind an octagonal
;                  nose ring, gunmetal cowl with louvres and exhaust stubs, a four-section fuselage that narrows and
;                  rises towards the tail, an open cockpit (leather rim, instrument coaming, quilted headrest,
;                  windscreen frame with glass holes), a spine fairing, a roundelled wing, a tailplane and a
;                  tricolour fin, gunner stands, tyres on an axle with struts, a tail wheel, navigation lamps, a
;                  pitot tube
;   m_plane_prop   wooden propeller with brass tips and a stepped brass spinner, 12 parts, prefix pp_ (12 rows)
; All three are rigid (one BK_BODY bone, swing 0): the propeller spins by its caller's glRotatef(prop, 0, 0, 1).
; Rows are the atlas rows each model packs into alone; packed one after another (boat, plane, propeller) from a
; fresh shelf they take 185, as skin_build's shelf cursor carries on from one model to the next.
;
; Model space (texels, 32 a block, front = -Z):
;   m_boat        the old hull's: bottom y 0, bow -Z; every part lies within x -18..18, y 0..16, z -28..28. The slab
;                 floor (y 0..10, three 14 long segments sharing one skin) tops out at y 10 over the whole interior,
;                 so it covers the water surface (8 texels above a floating boat's bottom) as the old floor did. The
;                 rider's feet are at y 8 and his boots at z -6..4: the thwarts (z -12..-7 and 8..13) and the locker
;                 (z 20..25) keep clear of them.
;   m_plane       the old plane_model's: centre at the origin (0.6 blocks above the plane's bottom), nose -Z, the
;                 wheels' bottoms at y -19, the old boxes kept within 2 texels (the fuselage x +-11, y -9..11, z
;                 -38..35; the wing x +-48, y 2..6, z -20..10; the tailplane z 27..45; the wheels x +-(11..17), z
;                 -26..-16) except the fin, which stops at z 34 (see the seats). The cockpit top is y 11 and the
;                 seats are the contract's: the pilot (m_avatar, SKP_SEATED) stands at (seat_x, c_seat = -0.4,
;                 seat_z) = (0, -12.8, 0), so his torso rests on y 11.2 with x +-8.5, z +-4.5 clear of the rim (x
;                 +-(9..11)), the coaming (z -9..-6) and the seat back (z 6..8); the gunner stands (wing x
;                 +-(21..37), z -8..2; tail x +-8, z 33..44) top out at y 11 the same way, and the fin ends at z 34
;                 so it does not run through the tail gunner (seat z 38.4) as the old one did.
;   m_plane_prop  the origin is the hub: planes_render puts it at (0, 0, c_prop_z = -1.5 blocks = -48 texels), the
;                 nose ring's front being at z -47, so the flange (local z -1..1) touches it; the blades span +-22
;                 texels in the XY plane (as the old 1.4 block blade), the spinner reaches local z -6.
; Local helpers (private to this file): RAMP prefix, r, g, b defines prefix_1 .. prefix_4: highlight (base x 1.2,
; clamped), base, shade (x 0.75), deep (x 0.55), packed RGBO; PART name, x0, y0, z0, w, h, d, grow, flags and
; PART_AS name, k, x0, y0, z0, grow, flags are SKPART / SKPART_AS with the part's name becoming its index, so the
; paint ops name parts, not numbers.
; Conventions (as the other art files): one palette per model (<prefix>_pal; the comment above it lists the letters:
; lower case = base tone, upper case = highlight, then shade and deep); '_' is a transparent texel (PALT, cutouts),
; '.' keeps the texel. A part's ops run: SK_FILL (grain: noise 7 on paint, 15 on canvas, leather and wood, 0 on
; steel and rubber), SK_RECT where a region keeps the grain, details as SK_BMP of a face-sized bitmap (a face image
; is seen from outside, upright, (0, 0) top left), then SK_GRAD on the four vertical faces (272 -> 224). Light comes
; from the top left: seams are dark lines, their rivets and the lit edges bright. Mirrored halves share a skin
; (PART_AS) and are painted symmetric (the wing and tailplane about the middle of their image, so the right half
; reads the same as the left); the boat's gunwales, floor segments, thwarts and ribs share one skin each.
; Overlapping parts never share a coplanar face with the same normal (the nose ring's tall half is grown half a
; texel, the fin starts at z 28), so nothing z-fights. The parts are listed in the order skin_build packs best
; (next-fit shelves in record order, the three models shaken together for the fewest rows whatever shelf the cursor
; is on when the boat starts), not in reading order: the comment on each line says what it is, and the paint ops
; below follow the reading order.
; Ramps (RAMP: _1 highlight, _2 base, _3 shade, _4 deep; AC_* are the shared material ramps of art.inc):
;   m_boat           BT_RED (184,60,46), BT_CREAM (230,220,190), BT_PITCH (46,36,32), BT_HEMP (176,148,96)
;   m_plane          PL_RED (200,56,44), PL_CREAM (232,222,194), PL_RUBBER (50,50,56), PL_BLUE (40,78,160)
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
; m_boat
; ===================================================================================================
RAMP BT_RED, 184, 60, 46
RAMP BT_CREAM, 230, 220, 190
RAMP BT_PITCH, 46, 36, 32
RAMP BT_HEMP, 176, 148, 96

section .rodata
; The characters of every bt_ bitmap. Groups: base, highlight, shade, deep.
;   w W j J wood (w base, W lit lip, j shadow, J darkest)   a A weathered grey-brown planks
;   r R q Q red paint   c C k K cream paint   p P pitch   s S z Z iron (s base, S bright, z shade, Z dark)
;   g G o brass hinges and latch   h H e E hemp rope   _ transparent
align 8
bt_pal:
    PALC 'w', AC_WOOD_2
    PALC 'W', AC_WOOD_1
    PALC 'j', AC_WOOD_3
    PALC 'J', AC_WOOD_4
    PALC 'a', RGBO(138, 106, 76)
    PALC 'A', RGBO(170, 138, 100)
    PALC 'r', BT_RED_2
    PALC 'R', BT_RED_1
    PALC 'q', BT_RED_3
    PALC 'Q', BT_RED_4
    PALC 'c', BT_CREAM_2
    PALC 'C', BT_CREAM_1
    PALC 'k', BT_CREAM_3
    PALC 'K', BT_CREAM_4
    PALC 'p', BT_PITCH_2
    PALC 'P', BT_PITCH_1
    PALC 's', AC_IRON_2
    PALC 'S', AC_IRON_1
    PALC 'z', AC_IRON_3
    PALC 'Z', AC_IRON_4
    PALC 'g', AC_GOLD_2
    PALC 'G', AC_GOLD_1
    PALC 'o', AC_GOLD_3
    PALC 'h', BT_HEMP_2
    PALC 'H', BT_HEMP_1
    PALC 'e', BT_HEMP_3
    PALC 'E', BT_HEMP_4
    PALT '_'
    dq 0

    ; bt_floor1_right (14x10): bt_floor1 RIGHT
    SKROWS bt_floor1_right_rows, 14, 10
    SKROW "WWWWWWWWWJWWWW"
    SKROW "jjjjjjjjjjjjjj"
    SKROW "AAAAJAAAAAAAAA"
    SKROW "aaaaJaZaaaaaaZ"
    SKROW "jjjjjjjjjjjjjj"
    SKROW "WWWWWWWWWWWWWJ"
    SKROW "wwwZwwwwwwZwwJ"
    SKROW "jjjjjjjjjjjjjj"
    SKROW "PPPPPPPPPPPPPP"
    SKROW "pppppppppppppp"
    SKROWS_END
    align 8
    SKBMP bt_floor1_right, bt_floor1_right_rows, 14, 10, bt_pal
    ; bt_floor1_left (14x10): bt_floor1 LEFT
    SKROWS bt_floor1_left_rows, 14, 10
    SKROW "WWWWJWWWWWWWWW"
    SKROW "jjjjjjjjjjjjjj"
    SKROW "AAAAAAAAAJAAAA"
    SKROW "ZaaaaaaZaJaaaa"
    SKROW "jjjjjjjjjjjjjj"
    SKROW "JWWWWWWWWWWWWW"
    SKROW "JwwZwwwwwwZwww"
    SKROW "jjjjjjjjjjjjjj"
    SKROW "PPPPPPPPPPPPPP"
    SKROW "pppppppppppppp"
    SKROWS_END
    align 8
    SKBMP bt_floor1_left, bt_floor1_left_rows, 14, 10, bt_pal
    ; bt_floor1_top (36x14): bt_floor1 TOP
    SKROWS bt_floor1_top_rows, 36, 14
    SKROW "jjj....j....jJJJJj....j....j..Z..jjj"
    SKROW "jjj....j....j..Z.j....j....j.....jjj"
    SKROW "jjj....j....j....j...Wj....j.....jjj"
    SKROW "jjj...Aj....j....j....j..Z.j.....jjj"
    SKROW "jjj....j..Z.j....j....jJJJJj.....jjj"
    SKROW "jjj....jJJJJj....j....j..Z.j.....jjj"
    SKROW "jjj....j..Z.j....j....j....j...W.jjj"
    SKROW "jjj....j....j...Aj....j....j.....jjj"
    SKROW "jjj....j....j....j..Z.j....j.....jjj"
    SKROW "jjj..Z.j....j....jJJJJj....j.....jjj"
    SKROW "jjjJJJJj....j....j..Z.j....j.....jjj"
    SKROW "jjj..Z.j....j....j....j...Aj.....jjj"
    SKROW "jjj....j...Wj....j....j....j..Z..jjj"
    SKROW "jjj....j....j..Z.j....j....jJJJJJjjj"
    SKROWS_END
    align 8
    SKBMP bt_floor1_top, bt_floor1_top_rows, 36, 14, bt_pal
    ; bt_floor1_bottom (36x14): bt_floor1 BOTTOM
    SKROWS bt_floor1_bottom_rows, 36, 14
    SKROW "pppppPpppppPpppppPpppppPpppppPpppppP"
    SKROW "pppppPpppppPpppppPpppppPpppppPpppppP"
    SKROW "pppppPpppppPpppppPpppppPpppppPpppppP"
    SKROW "pppppPpppppPpppppPpppppPpppppPpppppP"
    SKROW "pppppPpppppPpppppPpppppPpppppPpppppP"
    SKROW "pppppPpppppPpppppPpppppPpppppPpppppP"
    SKROW "pppppPpppppPpppppPpppppPpppppPpppppP"
    SKROW "pppppPpppppPpppppPpppppPpppppPpppppP"
    SKROW "pppppPpppppPpppppPpppppPpppppPpppppP"
    SKROW "pppppPpppppPpppppPpppppPpppppPpppppP"
    SKROW "pppppPpppppPpppppPpppppPpppppPpppppP"
    SKROW "pppppPpppppPpppppPpppppPpppppPpppppP"
    SKROW "pppppPpppppPpppppPpppppPpppppPpppppP"
    SKROW "pppppPpppppPpppppPpppppPpppppPpppppP"
    SKROWS_END
    align 8
    SKBMP bt_floor1_bottom, bt_floor1_bottom_rows, 36, 14, bt_pal
    ; bt_floor1_back (36x10): bt_floor1 BACK
    SKROWS bt_floor1_back_rows, 36, 10
    SKROW "WWWWWJWWWWWWWWWWWWWJWWWWWWWWWWWWWJWW"
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjj"
    SKROW "AAAAAAAAAAJAAAAAAAAAAAAAJAAAAAAAAAAA"
    SKROW "aZaaaaaaZaJaaaaZaaaaaaZaJaaaaZaaaaaa"
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjj"
    SKROW "WJWWWWWWWWWWWWWJWWWWWWWWWWWWWJWWWWWW"
    SKROW "wJwwZwwwwwwZwwwJwwZwwwwwwZwwwJwwZwww"
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjj"
    SKROW "PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP"
    SKROW "pppppppppppppppppppppppppppppppppppp"
    SKROWS_END
    align 8
    SKBMP bt_floor1_back, bt_floor1_back_rows, 36, 10, bt_pal
    ; bt_floor1_front (36x10): bt_floor1 FRONT
    SKROWS bt_floor1_front_rows, 36, 10
    SKROW "WWJWWWWWWWWWWWWWJWWWWWWWWWWWWWJWWWWW"
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjj"
    SKROW "AAAAAAAAAAAJAAAAAAAAAAAAAJAAAAAAAAAA"
    SKROW "aaaaaaZaaaaJaZaaaaaaZaaaaJaZaaaaaaZa"
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjj"
    SKROW "WWWWWWJWWWWWWWWWWWWWJWWWWWWWWWWWWWJW"
    SKROW "wwwZwwJwwwZwwwwwwZwwJwwwZwwwwwwZwwJw"
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjj"
    SKROW "PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP"
    SKROW "pppppppppppppppppppppppppppppppppppp"
    SKROWS_END
    align 8
    SKBMP bt_floor1_front, bt_floor1_front_rows, 36, 10, bt_pal
    ; bt_bow_a_right (5x13): bt_bow_a RIGHT
    SKROWS bt_bow_a_right_rows, 5, 13
    SKROW "rrrrr"
    SKROW "ccccc"
    SKROW "wwwww"
    SKROW "WWWWW"
    SKROW "jjjjj"
    SKROW "AAAAJ"
    SKROW "aaaaJ"
    SKROW "jjjjj"
    SKROW "WWWWW"
    SKROW "wwwZw"
    SKROW "jjjjj"
    SKROW "PPPPP"
    SKROW "ppppp"
    SKROWS_END
    align 8
    SKBMP bt_bow_a_right, bt_bow_a_right_rows, 5, 13, bt_pal
    ; bt_bow_a_left (5x13): bt_bow_a LEFT
    SKROWS bt_bow_a_left_rows, 5, 13
    SKROW "rrrrr"
    SKROW "ccccc"
    SKROW "wwwww"
    SKROW "WWWWW"
    SKROW "jjjjj"
    SKROW "JAAAA"
    SKROW "Jaaaa"
    SKROW "jjjjj"
    SKROW "WWWWW"
    SKROW "wZwww"
    SKROW "jjjjj"
    SKROW "PPPPP"
    SKROW "ppppp"
    SKROWS_END
    align 8
    SKBMP bt_bow_a_left, bt_bow_a_left_rows, 5, 13, bt_pal
    ; bt_bow_a_top (30x5): bt_bow_a TOP
    SKROWS bt_bow_a_top_rows, 30, 5
    SKROW "AWAWAWAWAWAWAWAWAWAWAWAWAWAWAW"
    SKROW ".Z...Z..................Z...Z."
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjjjjjjjj"
    SKROW "AWAWAWAWAWAWAWAWAWAWAWAWAWAWAW"
    SKROW ".Z...Z..................Z...Z."
    SKROWS_END
    align 8
    SKBMP bt_bow_a_top, bt_bow_a_top_rows, 30, 5, bt_pal
    ; bt_bow_a_bottom (30x5): bt_bow_a BOTTOM
    SKROWS bt_bow_a_bottom_rows, 30, 5
    SKROW "pppppppppppppppppppppppppppppp"
    SKROW "pppppppppppppppppppppppppppppp"
    SKROW "pppppppppppppppppppppppppppppp"
    SKROW "pppppppppppppppppppppppppppppp"
    SKROW "pppppppppppppppppppppppppppppp"
    SKROWS_END
    align 8
    SKBMP bt_bow_a_bottom, bt_bow_a_bottom_rows, 30, 5, bt_pal
    ; bt_bow_a_back (30x13): bt_bow_a BACK
    SKROWS bt_bow_a_back_rows, 30, 13
    SKROW "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWW"
    SKROW "j..jaaj..jaaj..jaaj..jaaj..jaa"
    SKROW "j..jaaj..jaaj..jaaj..jaaj..jaa"
    SKROW "j..jaaj..jaaj..jaaj..jaaj..jaa"
    SKROW "j..jaaj..jaaj..jaaj..jaaj..jaa"
    SKROW "j..jaaj..jaaj..jaaj..jaaj..jaa"
    SKROW "j..jaaj..jaaj..jaaj..jaaj..jaa"
    SKROW "j..jaaj..jaaj..jaaj..jaaj..jaa"
    SKROW "j..jaaj..jaaj..jaaj..jaaj..jaa"
    SKROW "j..jaaj..jaaj..jaaj..jaaj..jaa"
    SKROW "j..jaaj..jaaj..jaaj..jaaj..jaa"
    SKROW "j..jaaj..jaaj..jaaj..jaaj..jaa"
    SKROW "j..jaaj..jaaj..jaaj..jaaj..jaa"
    SKROWS_END
    align 8
    SKBMP bt_bow_a_back, bt_bow_a_back_rows, 30, 13, bt_pal
    ; bt_bow_a_front (30x13): bt_bow_a FRONT
    SKROWS bt_bow_a_front_rows, 30, 13
    SKROW "rrrrrrrrrrrrrrrrrrrrrrrrrrrrrr"
    SKROW "cccccccccccccccccccccccccccccc"
    SKROW "wwwwwwwwwwwwwwwwwwwwwwwwwwwwww"
    SKROW "WWWWWWWWWWWWWJWWWWWWWWWWWWWJWW"
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjjjjjjjj"
    SKROW "AAAAAAAAJAAAAAAAAAAAAAJAAAAAAA"
    SKROW "aaaZaaaaJaZaaaaaaZaaaaJaZaaaaa"
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjjjjjjjj"
    SKROW "WWWJWWWWWWWWWWWWWJWWWWWWWWWWWW"
    SKROW "ZwwJwwwZwwwwwwZwwJwwwZwwwwwwZw"
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjjjjjjjj"
    SKROW "PPPPPPPPPPPPPPPPPPPPPPPPPPPPPP"
    SKROW "pppppppppppppppppppppppppppppp"
    SKROWS_END
    align 8
    SKBMP bt_bow_a_front, bt_bow_a_front_rows, 30, 13, bt_pal
    ; bt_bow_b_right (5x13): bt_bow_b RIGHT
    SKROWS bt_bow_b_right_rows, 5, 13
    SKROW "rrrrr"
    SKROW "ccccc"
    SKROW "wwwww"
    SKROW "WWWWJ"
    SKROW "jjjjj"
    SKROW "AAAAA"
    SKROW "aZaaa"
    SKROW "jjjjj"
    SKROW "WWWWW"
    SKROW "wwwww"
    SKROW "jjjjj"
    SKROW "PPPPP"
    SKROW "ppppp"
    SKROWS_END
    align 8
    SKBMP bt_bow_b_right, bt_bow_b_right_rows, 5, 13, bt_pal
    ; bt_bow_b_left (5x13): bt_bow_b LEFT
    SKROWS bt_bow_b_left_rows, 5, 13
    SKROW "rrrrr"
    SKROW "ccccc"
    SKROW "wwwww"
    SKROW "JWWWW"
    SKROW "jjjjj"
    SKROW "AAAAA"
    SKROW "aaaZa"
    SKROW "jjjjj"
    SKROW "WWWWW"
    SKROW "wwwww"
    SKROW "jjjjj"
    SKROW "PPPPP"
    SKROW "ppppp"
    SKROWS_END
    align 8
    SKBMP bt_bow_b_left, bt_bow_b_left_rows, 5, 13, bt_pal
    ; bt_bow_b_top (22x5): bt_bow_b TOP
    SKROWS bt_bow_b_top_rows, 22, 5
    SKROW "AWAWAWAWAWAWAWAWAWAWAW"
    SKROW ".Z..................Z."
    SKROW "jjjjjjjjjjjjjjjjjjjjjj"
    SKROW "AWAWAWAWAWAWAWAWAWAWAW"
    SKROW ".Z..................Z."
    SKROWS_END
    align 8
    SKBMP bt_bow_b_top, bt_bow_b_top_rows, 22, 5, bt_pal
    ; bt_bow_b_bottom (22x5): bt_bow_b BOTTOM
    SKROWS bt_bow_b_bottom_rows, 22, 5
    SKROW "pppppppppppppppppppppp"
    SKROW "pppppppppppppppppppppp"
    SKROW "pppppppppppppppppppppp"
    SKROW "pppppppppppppppppppppp"
    SKROW "pppppppppppppppppppppp"
    SKROWS_END
    align 8
    SKBMP bt_bow_b_bottom, bt_bow_b_bottom_rows, 22, 5, bt_pal
    ; bt_bow_b_back (22x13): bt_bow_b BACK
    SKROWS bt_bow_b_back_rows, 22, 13
    SKROW "WWWWWWWWWWWWWWWWWWWWWW"
    SKROW "aaj..jaaj..jaaj..jaaj."
    SKROW "aaj..jaaj..jaaj..jaaj."
    SKROW "aaj..jaaj..jaaj..jaaj."
    SKROW "aaj..jaaj..jaaj..jaaj."
    SKROW "aaj..jaaj..jaaj..jaaj."
    SKROW "aaj..jaaj..jaaj..jaaj."
    SKROW "aaj..jaaj..jaaj..jaaj."
    SKROW "aaj..jaaj..jaaj..jaaj."
    SKROW "aaj..jaaj..jaaj..jaaj."
    SKROW "aaj..jaaj..jaaj..jaaj."
    SKROW "aaj..jaaj..jaaj..jaaj."
    SKROW "aaj..jaaj..jaaj..jaaj."
    SKROWS_END
    align 8
    SKBMP bt_bow_b_back, bt_bow_b_back_rows, 22, 13, bt_pal
    ; bt_bow_b_front (22x13): bt_bow_b FRONT
    SKROWS bt_bow_b_front_rows, 22, 13
    SKROW "rrrrrrrrrrrrrrrrrrrrrr"
    SKROW "cccccccccccccccccccccc"
    SKROW "wwwwwwwwwwwwwwwwwwwwww"
    SKROW "WWWWWWWWWJWWWWWWWWWWWW"
    SKROW "jjjjjjjjjjjjjjjjjjjjjj"
    SKROW "AAAAJAAAAAAAAAAAAAJAAA"
    SKROW "aaaaJaZaaaaaaZaaaaJaZa"
    SKROW "jjjjjjjjjjjjjjjjjjjjjj"
    SKROW "WWWWWWWWWWWWWJWWWWWWWW"
    SKROW "wwwZwwwwwwZwwJwwwZwwww"
    SKROW "jjjjjjjjjjjjjjjjjjjjjj"
    SKROW "PPPPPPPPPPPPPPPPPPPPPP"
    SKROW "pppppppppppppppppppppp"
    SKROWS_END
    align 8
    SKBMP bt_bow_b_front, bt_bow_b_front_rows, 22, 13, bt_pal
    ; bt_stem_right (4x16): bt_stem RIGHT
    SKROWS bt_stem_right_rows, 4, 16
    SKROW "RRRR"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "cccc"
    SKROW "wwww"
    SKROW "WWWW"
    SKROW "jjjj"
    SKROW "AAAA"
    SKROW "aaaZ"
    SKROW "jjjj"
    SKROW "WWWJ"
    SKROW "ZwwJ"
    SKROW "jjjj"
    SKROW "PPPP"
    SKROW "pppp"
    SKROWS_END
    align 8
    SKBMP bt_stem_right, bt_stem_right_rows, 4, 16, bt_pal
    ; bt_stem_left (4x16): bt_stem LEFT
    SKROWS bt_stem_left_rows, 4, 16
    SKROW "RRRR"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "cccc"
    SKROW "wwww"
    SKROW "WWWW"
    SKROW "jjjj"
    SKROW "AAAA"
    SKROW "Zaaa"
    SKROW "jjjj"
    SKROW "JWWW"
    SKROW "JwwZ"
    SKROW "jjjj"
    SKROW "PPPP"
    SKROW "pppp"
    SKROWS_END
    align 8
    SKBMP bt_stem_left, bt_stem_left_rows, 4, 16, bt_pal
    ; bt_stem_top (12x4): bt_stem TOP
    SKROWS bt_stem_top_rows, 12, 4
    SKROW "RRRRRRRRRRRR"
    SKROW "rRrrrrrrrrRr"
    SKROW "RRRRRRRRRRRR"
    SKROW "rRrrrrrrrrRr"
    SKROWS_END
    align 8
    SKBMP bt_stem_top, bt_stem_top_rows, 12, 4, bt_pal
    ; bt_stem_bottom (12x4): bt_stem BOTTOM
    SKROWS bt_stem_bottom_rows, 12, 4
    SKROW "pppppppppppp"
    SKROW "pppppppppppp"
    SKROW "pppppppppppp"
    SKROW "pppppppppppp"
    SKROWS_END
    align 8
    SKBMP bt_stem_bottom, bt_stem_bottom_rows, 12, 4, bt_pal
    ; bt_stem_back (12x16): bt_stem BACK
    SKROWS bt_stem_back_rows, 12, 16
    SKROW "rrrrrrrrrrrr"
    SKROW "rrrrrrrrrrrr"
    SKROW "rrrrrrrrrrrr"
    SKROW "WWWWWWWWWWWW"
    SKROW "jaaj..jaaj.."
    SKROW "jaaj..jaaj.."
    SKROW "jaaj..jaaj.."
    SKROW "jaaj..jaaj.."
    SKROW "jaaj..jaaj.."
    SKROW "jaaj..jaaj.."
    SKROW "jaaj..jaaj.."
    SKROW "jaaj..jaaj.."
    SKROW "jaaj..jaaj.."
    SKROW "jaaj..jaaj.."
    SKROW "jaaj..jaaj.."
    SKROW "jaaj..jaaj.."
    SKROWS_END
    align 8
    SKBMP bt_stem_back, bt_stem_back_rows, 12, 16, bt_pal
    ; bt_stem_front (12x16): bt_stem FRONT
    SKROWS bt_stem_front_rows, 12, 16
    SKROW "RRRRRRRRRRRR"
    SKROW "rrrrrrrrrrrr"
    SKROW "rrrrrrrrrrrr"
    SKROW "rrrrrwWrrrrr"
    SKROW "cccccsSccccc"
    SKROW "wwwwssSSwwww"
    SKROW "WJWWsZZsWWWW"
    SKROW "ssssssssssss"
    SKROW "zzzzzsszzzzz"
    SKROW "aaaaawWaaaJa"
    SKROW "jjjjjwWjjjjj"
    SKROW "WWWWWwWWWWWW"
    SKROW "wwZwwwWwwZww"
    SKROW "jjjjjwWjjjjj"
    SKROW "PPPPPwWPPPPP"
    SKROW "pppppwWppppp"
    SKROWS_END
    align 8
    SKBMP bt_stem_front, bt_stem_front_rows, 12, 16, bt_pal
    ; bt_wall_l1_right (14x4): bt_wall_l1 RIGHT, bt_wall_r1 LEFT
    SKROWS bt_wall_l1_right_rows, 14, 4
    SKROW "WWWWWWWWWWWWWW"
    SKROW "aaaaaaaaaaaaaa"
    SKROW ".............."
    SKROW "jjjjjjjjjjjjjj"
    SKROWS_END
    align 8
    SKBMP bt_wall_l1_right, bt_wall_l1_right_rows, 14, 4, bt_pal
    ; bt_wall_l1_left (14x4): bt_wall_l1 LEFT, bt_wall_r1 RIGHT
    SKROWS bt_wall_l1_left_rows, 14, 4
    SKROW "RRRRRRRRRRRRRR"
    SKROW "rrrrrrrrrrrrrr"
    SKROW "cccccccccccccc"
    SKROW "wwwwwwwwwwwwww"
    SKROWS_END
    align 8
    SKBMP bt_wall_l1_left, bt_wall_l1_left_rows, 14, 4, bt_pal
    ; bt_wall_l1_top (3x14): bt_wall_l1 TOP, bt_wall_r1 TOP
    SKROWS bt_wall_l1_top_rows, 3, 14
    SKROW "AWw"
    SKROW "AWw"
    SKROW "AWw"
    SKROW "AWw"
    SKROW "AWw"
    SKROW "AWw"
    SKROW "AWw"
    SKROW "AWw"
    SKROW "AWw"
    SKROW "AWw"
    SKROW "AWw"
    SKROW "AWw"
    SKROW "AWw"
    SKROW "AWw"
    SKROWS_END
    align 8
    SKBMP bt_wall_l1_top, bt_wall_l1_top_rows, 3, 14, bt_pal
    ; bt_wall_l1_back (3x4): bt_wall_l1 BACK, bt_wall_l1 FRONT, bt_wall_r1 BACK, ...
    SKROWS bt_wall_l1_back_rows, 3, 4
    SKROW "WWW"
    SKROW "..."
    SKROW "..."
    SKROW "jjj"
    SKROWS_END
    align 8
    SKBMP bt_wall_l1_back, bt_wall_l1_back_rows, 3, 4, bt_pal
    ; bt_transom_right (3x5): bt_transom RIGHT, bt_transom LEFT
    SKROWS bt_transom_right_rows, 3, 5
    SKROW "rrr"
    SKROW "rrr"
    SKROW "jjj"
    SKROW "jjj"
    SKROW "jjj"
    SKROWS_END
    align 8
    SKBMP bt_transom_right, bt_transom_right_rows, 3, 5, bt_pal
    ; bt_transom_top (30x3): bt_transom TOP
    SKROWS bt_transom_top_rows, 30, 3
    SKROW "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    SKROW "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWW"
    SKROW "wwwwwwwwwwwwwwwwwwwwwwwwwwwwww"
    SKROWS_END
    align 8
    SKBMP bt_transom_top, bt_transom_top_rows, 30, 3, bt_pal
    ; bt_transom_bottom (30x3): bt_transom BOTTOM
    SKROWS bt_transom_bottom_rows, 30, 3
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjjjjjjjj"
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjjjjjjjj"
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjjjjjjjj"
    SKROWS_END
    align 8
    SKBMP bt_transom_bottom, bt_transom_bottom_rows, 30, 3, bt_pal
    ; bt_transom_back (30x5): bt_transom BACK
    SKROWS bt_transom_back_rows, 30, 5
    SKROW "RRRRRRRRRRRRRRRRRRRRRRRRRRRRRR"
    SKROW "rrrrrrrrrrrrrrrrrrrrrrrrrrrrrr"
    SKROW "jaaaazZ...jaaaaj....jaaZZj...."
    SKROW "jaaaaSZ...jaaaaj....jaazSj...."
    SKROW "jaaaazZ...jaaaaj....jaazZj...."
    SKROWS_END
    align 8
    SKBMP bt_transom_back, bt_transom_back_rows, 30, 5, bt_pal
    ; bt_transom_front (30x5): bt_transom FRONT
    SKROWS bt_transom_front_rows, 30, 5
    SKROW "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWW"
    SKROW "....jaaaaj....jaaaaj....jaaaaj"
    SKROW "....jaaaaj....jaaaaj....jaaaaj"
    SKROW "....jaaaaj....jaaaaj....jaaaaj"
    SKROW "....jaaaaj....jaaaaj....jaaaaj"
    SKROWS_END
    align 8
    SKBMP bt_transom_front, bt_transom_front_rows, 30, 5, bt_pal
    ; bt_bench_f_right (5x3): bt_bench_f RIGHT, bt_bench_f LEFT
    SKROWS bt_bench_f_right_rows, 5, 3
    SKROW "jwwjw"
    SKROW "wwjww"
    SKROW "wjwwj"
    SKROWS_END
    align 8
    SKBMP bt_bench_f_right, bt_bench_f_right_rows, 5, 3, bt_pal
    ; bt_bench_f_top (30x5): bt_bench_f TOP
    SKROWS bt_bench_f_top_rows, 30, 5
    SKROW "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    SKROW "wwWWWWWWwwwwWWWWWWwwwwWWWWWWww"
    SKROW "WWZWWWWWWWWWWWWWWWWWWWWWWWWZWW"
    SKROW "WWwwwwWWWWWWwwwwWWWWWWwwwwWWWW"
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjjjjjjjj"
    SKROWS_END
    align 8
    SKBMP bt_bench_f_top, bt_bench_f_top_rows, 30, 5, bt_pal
    ; bt_bench_f_bottom (30x5): bt_bench_f BOTTOM
    SKROWS bt_bench_f_bottom_rows, 30, 5
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjjjjjjjj"
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjjjjjjjj"
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjjjjjjjj"
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjjjjjjjj"
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjjjjjjjj"
    SKROWS_END
    align 8
    SKBMP bt_bench_f_bottom, bt_bench_f_bottom_rows, 30, 5, bt_pal
    ; bt_bench_f_back (30x3): bt_bench_f BACK, bt_bench_f FRONT
    SKROWS bt_bench_f_back_rows, 30, 3
    SKROW "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWW"
    SKROW "wwwwwwwwwwwwwwwwwwwwwwwwwwwwww"
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjjjjjjjj"
    SKROWS_END
    align 8
    SKBMP bt_bench_f_back, bt_bench_f_back_rows, 30, 3, bt_pal
    ; bt_locker_right (5x4): bt_locker RIGHT, bt_locker LEFT
    SKROWS bt_locker_right_rows, 5, 4
    SKROW "WWWWW"
    SKROW "jjjjj"
    SKROW ".hhh."
    SKROW ".eee."
    SKROWS_END
    align 8
    SKBMP bt_locker_right, bt_locker_right_rows, 5, 4, bt_pal
    ; bt_locker_top (24x5): bt_locker TOP
    SKROWS bt_locker_top_rows, 24, 5
    SKROW "AAAAggAzAAAAAAAAzAggAAAA"
    SKROW "WWwwwwWzWWWwwwwWzWWWwwww"
    SKROW "WWWWWWWzWWWWWWWWzWWWWWWW"
    SKROW "wWWWWWwzwwWWWWWwzwwWWWWW"
    SKROW "jjjjjjjjjjjggjjjjjjjjjjj"
    SKROWS_END
    align 8
    SKBMP bt_locker_top, bt_locker_top_rows, 24, 5, bt_pal
    ; bt_locker_bottom (24x5): bt_locker BOTTOM
    SKROWS bt_locker_bottom_rows, 24, 5
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjj"
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjj"
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjj"
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjj"
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjj"
    SKROWS_END
    align 8
    SKBMP bt_locker_bottom, bt_locker_bottom_rows, 24, 5, bt_pal
    ; bt_locker_back (24x4): bt_locker BACK
    SKROWS bt_locker_back_rows, 24, 4
    SKROW "WWWWWWWWWWWWWWWWWWWWWWWW"
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjj"
    SKROW "j.....jaaaaaj.....jaaaaa"
    SKROW "j.....jaaaaaj.....jaaaaa"
    SKROWS_END
    align 8
    SKBMP bt_locker_back, bt_locker_back_rows, 24, 4, bt_pal
    ; bt_locker_front (24x4): bt_locker FRONT
    SKROWS bt_locker_front_rows, 24, 4
    SKROW "WWWWWWWWWWWWWWWWWWWWWWWW"
    SKROW "jjjjjjjjjjjjjjjjjjjjjjjj"
    SKROW "j.....zZaaagg...zZjaaaaa"
    SKROW "j.....zZaaaaj...zZjaaaaa"
    SKROWS_END
    align 8
    SKBMP bt_locker_front, bt_locker_front_rows, 24, 4, bt_pal
    ; bt_rib_1_right (2x4): bt_rib_1 RIGHT, bt_rib_1 LEFT, bt_rib_1 BACK, ...
    SKROWS bt_rib_1_right_rows, 2, 4
    SKROW "w."
    SKROW "w."
    SKROW "w."
    SKROW "w."
    SKROWS_END
    align 8
    SKBMP bt_rib_1_right, bt_rib_1_right_rows, 2, 4, bt_pal
    ; bt_rib_1_top (2x2): bt_rib_1 TOP
    SKROWS bt_rib_1_top_rows, 2, 2
    SKROW "WW"
    SKROW "w."
    SKROWS_END
    align 8
    SKBMP bt_rib_1_top, bt_rib_1_top_rows, 2, 2, bt_pal
    ; bt_rib_1_bottom (2x2): bt_rib_1 BOTTOM
    SKROWS bt_rib_1_bottom_rows, 2, 2
    SKROW "w."
    SKROW "w."
    SKROWS_END
    align 8
    SKBMP bt_rib_1_bottom, bt_rib_1_bottom_rows, 2, 2, bt_pal
    ; bt_lock_l_right (3x2): bt_lock_l RIGHT, bt_lock_l LEFT
    SKROWS bt_lock_l_right_rows, 3, 2
    SKROW "zzz"
    SKROW "ZZZ"
    SKROWS_END
    align 8
    SKBMP bt_lock_l_right, bt_lock_l_right_rows, 3, 2, bt_pal
    ; bt_lock_l_top (2x3): bt_lock_l TOP
    SKROWS bt_lock_l_top_rows, 2, 3
    SKROW "zZ"
    SKROW "ZZ"
    SKROW "zZ"
    SKROWS_END
    align 8
    SKBMP bt_lock_l_top, bt_lock_l_top_rows, 2, 3, bt_pal
    ; bt_lock_l_bottom (2x3): bt_lock_l BOTTOM
    SKROWS bt_lock_l_bottom_rows, 2, 3
    SKROW "ZZ"
    SKROW "ZZ"
    SKROW "ZZ"
    SKROWS_END
    align 8
    SKBMP bt_lock_l_bottom, bt_lock_l_bottom_rows, 2, 3, bt_pal
    ; bt_lock_l_back (2x2): bt_lock_l BACK, bt_lock_l FRONT
    SKROWS bt_lock_l_back_rows, 2, 2
    SKROW "zz"
    SKROW "ZZ"
    SKROWS_END
    align 8
    SKBMP bt_lock_l_back, bt_lock_l_back_rows, 2, 2, bt_pal
    ; bt_coil_right (5x2): bt_coil RIGHT, bt_coil LEFT
    SKROWS bt_coil_right_rows, 5, 2
    SKROW "HhEHh"
    SKROW "eEeeE"
    SKROWS_END
    align 8
    SKBMP bt_coil_right, bt_coil_right_rows, 5, 2, bt_pal
    ; bt_coil_top (6x5): bt_coil TOP
    SKROWS bt_coil_top_rows, 6, 5
    SKROW "HhhHhh"
    SKROW "heeeeH"
    SKROW "heEEeh"
    SKROW "Heeeeh"
    SKROW "hhHhhH"
    SKROWS_END
    align 8
    SKBMP bt_coil_top, bt_coil_top_rows, 6, 5, bt_pal
    ; bt_coil_bottom (6x5): bt_coil BOTTOM
    SKROWS bt_coil_bottom_rows, 6, 5
    SKROW "EEEEEE"
    SKROW "EEEEEE"
    SKROW "EEEEEE"
    SKROW "EEEEEE"
    SKROW "EEEEEE"
    SKROWS_END
    align 8
    SKBMP bt_coil_bottom, bt_coil_bottom_rows, 6, 5, bt_pal
    ; bt_coil_back (6x2): bt_coil BACK, bt_coil FRONT
    SKROWS bt_coil_back_rows, 6, 2
    SKROW "HhEHhE"
    SKROW "eEeeEe"
    SKROWS_END
    align 8
    SKBMP bt_coil_back, bt_coil_back_rows, 6, 2, bt_pal

section .data
SKMODEL_BEGIN m_boat, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART bt_bow_a, -15, 0, -19, 30, 13, 5, 0, 0             ; foredeck, first step
    PART bt_floor1, -18, 0, -14, 36, 10, 14, 0, 0           ; hull slab, 3 segments, one skin; top y 10 covers water
    PART bt_bow_b, -11, 0, -24, 22, 13, 5, 0, 0             ; foredeck, second step
    PART bt_stem, -6, 0, -28, 12, 16, 4, 0, 0               ; raised stem post
    PART bt_wall_l1, -18, 10, -14, 3, 4, 14, 0, 0           ; left gunwale (three segments, one skin)
    PART bt_wall_r1, 15, 10, -14, 3, 4, 14, 0, 0            ; right gunwale (three segments, one skin)
    PART bt_coil, 5, 13, -19, 6, 2, 5, 0, 0                 ; rope coil on the foredeck
    PART bt_rib_1, -15, 10, -4, 2, 4, 2, 0, 0               ; ribs on the inner walls (one skin)
    PART_AS bt_rib_3, bt_rib_1, -15, 10, 16, 0, 0
    PART bt_lock_l, -17, 14, -1, 2, 2, 3, 0, 0              ; oarlock sockets (the right one shares its skin)
    PART_AS bt_rib_5, bt_rib_1, 13, 10, 3, 0, 0
    PART_AS bt_floor3, bt_floor1, -18, 0, 14, 0, 0
    PART bt_bench_f, -15, 10, -12, 30, 3, 5, 0, 0           ; thwarts, fore and aft of the rider (one skin)
    PART_AS bt_rib_2, bt_rib_1, -15, 10, 3, 0, 0
    PART_AS bt_rib_6, bt_rib_1, 13, 10, 16, 0, 0
    PART_AS bt_wall_l2, bt_wall_l1, -18, 10, 0, 0, 0
    PART_AS bt_bench_r, bt_bench_f, -15, 10, 8, 0, 0
    PART_AS bt_lock_r, bt_lock_l, 15, 14, -1, 0, 0
    PART bt_transom, -15, 10, 25, 30, 5, 3, 0, 0            ; stern board
    PART bt_locker, -12, 10, 20, 24, 4, 5, 0, 0             ; stern locker: a lidded chest with brass hinges and latch
    PART_AS bt_wall_l3, bt_wall_l1, -18, 10, 14, 0, 0
    PART_AS bt_rib_4, bt_rib_1, 13, 10, -4, 0, 0
    PART_AS bt_wall_r3, bt_wall_r1, 15, 10, 14, 0, 0
    PART_AS bt_wall_r2, bt_wall_r1, 15, 10, 0, 0, 0
    PART_AS bt_floor2, bt_floor1, -18, 0, 0, 0, 0
SKMODEL_PAINT
    ; --- bt_floor1
    SK_FILL bt_floor1, SKM_ALL, AC_WOOD_2, 15
    SK_RECT bt_floor1, SKF_TOP, 5, 0, 5, 14, RGBO(138, 106, 76), 15
    SK_RECT bt_floor1, SKF_TOP, 15, 0, 5, 14, RGBO(138, 106, 76), 15
    SK_RECT bt_floor1, SKF_TOP, 25, 0, 5, 14, RGBO(138, 106, 76), 15
    SK_BMP bt_floor1, SKF_RIGHT, 0, 0, bt_floor1_right
    SK_BMP bt_floor1, SKF_LEFT, 0, 0, bt_floor1_left
    SK_BMP bt_floor1, SKF_TOP, 0, 0, bt_floor1_top
    SK_BMP bt_floor1, SKF_BOTTOM, 0, 0, bt_floor1_bottom
    SK_BMP bt_floor1, SKF_BACK, 0, 0, bt_floor1_back
    SK_BMP bt_floor1, SKF_FRONT, 0, 0, bt_floor1_front
    SK_GRAD bt_floor1, SKM_SIDES, 272, 224
    ; --- bt_bow_a
    SK_FILL bt_bow_a, SKM_ALL, AC_WOOD_2, 15
    SK_BMP bt_bow_a, SKF_RIGHT, 0, 0, bt_bow_a_right
    SK_BMP bt_bow_a, SKF_LEFT, 0, 0, bt_bow_a_left
    SK_BMP bt_bow_a, SKF_TOP, 0, 0, bt_bow_a_top
    SK_BMP bt_bow_a, SKF_BOTTOM, 0, 0, bt_bow_a_bottom
    SK_BMP bt_bow_a, SKF_BACK, 0, 0, bt_bow_a_back
    SK_BMP bt_bow_a, SKF_FRONT, 0, 0, bt_bow_a_front
    SK_GRAD bt_bow_a, SKM_SIDES, 272, 224
    ; --- bt_bow_b
    SK_FILL bt_bow_b, SKM_ALL, AC_WOOD_2, 15
    SK_BMP bt_bow_b, SKF_RIGHT, 0, 0, bt_bow_b_right
    SK_BMP bt_bow_b, SKF_LEFT, 0, 0, bt_bow_b_left
    SK_BMP bt_bow_b, SKF_TOP, 0, 0, bt_bow_b_top
    SK_BMP bt_bow_b, SKF_BOTTOM, 0, 0, bt_bow_b_bottom
    SK_BMP bt_bow_b, SKF_BACK, 0, 0, bt_bow_b_back
    SK_BMP bt_bow_b, SKF_FRONT, 0, 0, bt_bow_b_front
    SK_GRAD bt_bow_b, SKM_SIDES, 272, 224
    ; --- bt_stem
    SK_FILL bt_stem, SKM_ALL, AC_WOOD_2, 15
    SK_BMP bt_stem, SKF_RIGHT, 0, 0, bt_stem_right
    SK_BMP bt_stem, SKF_LEFT, 0, 0, bt_stem_left
    SK_BMP bt_stem, SKF_TOP, 0, 0, bt_stem_top
    SK_BMP bt_stem, SKF_BOTTOM, 0, 0, bt_stem_bottom
    SK_BMP bt_stem, SKF_BACK, 0, 0, bt_stem_back
    SK_BMP bt_stem, SKF_FRONT, 0, 0, bt_stem_front
    SK_GRAD bt_stem, SKM_SIDES, 272, 224
    ; --- bt_wall_l1
    SK_FILL bt_wall_l1, SKM_ALL, AC_WOOD_2, 15
    SK_BMP bt_wall_l1, SKF_RIGHT, 0, 0, bt_wall_l1_right
    SK_BMP bt_wall_l1, SKF_LEFT, 0, 0, bt_wall_l1_left
    SK_BMP bt_wall_l1, SKF_TOP, 0, 0, bt_wall_l1_top
    SK_BMP bt_wall_l1, SKF_BACK, 0, 0, bt_wall_l1_back
    SK_BMP bt_wall_l1, SKF_FRONT, 0, 0, bt_wall_l1_back
    SK_GRAD bt_wall_l1, SKM_SIDES, 272, 224
    ; --- bt_wall_r1
    SK_FILL bt_wall_r1, SKM_ALL, AC_WOOD_2, 15
    SK_BMP bt_wall_r1, SKF_RIGHT, 0, 0, bt_wall_l1_left
    SK_BMP bt_wall_r1, SKF_LEFT, 0, 0, bt_wall_l1_right
    SK_BMP bt_wall_r1, SKF_TOP, 0, 0, bt_wall_l1_top
    SK_BMP bt_wall_r1, SKF_BACK, 0, 0, bt_wall_l1_back
    SK_BMP bt_wall_r1, SKF_FRONT, 0, 0, bt_wall_l1_back
    SK_GRAD bt_wall_r1, SKM_SIDES, 272, 224
    ; --- bt_transom
    SK_FILL bt_transom, SKM_ALL, AC_WOOD_2, 15
    SK_BMP bt_transom, SKF_RIGHT, 0, 0, bt_transom_right
    SK_BMP bt_transom, SKF_LEFT, 0, 0, bt_transom_right
    SK_BMP bt_transom, SKF_TOP, 0, 0, bt_transom_top
    SK_BMP bt_transom, SKF_BOTTOM, 0, 0, bt_transom_bottom
    SK_BMP bt_transom, SKF_BACK, 0, 0, bt_transom_back
    SK_BMP bt_transom, SKF_FRONT, 0, 0, bt_transom_front
    SK_GRAD bt_transom, SKM_SIDES, 272, 224
    ; --- bt_bench_f
    SK_FILL bt_bench_f, SKM_ALL, AC_WOOD_1, 15
    SK_BMP bt_bench_f, SKF_RIGHT, 0, 0, bt_bench_f_right
    SK_BMP bt_bench_f, SKF_LEFT, 0, 0, bt_bench_f_right
    SK_BMP bt_bench_f, SKF_TOP, 0, 0, bt_bench_f_top
    SK_BMP bt_bench_f, SKF_BOTTOM, 0, 0, bt_bench_f_bottom
    SK_BMP bt_bench_f, SKF_BACK, 0, 0, bt_bench_f_back
    SK_BMP bt_bench_f, SKF_FRONT, 0, 0, bt_bench_f_back
    SK_GRAD bt_bench_f, SKM_SIDES, 272, 224
    ; --- bt_locker
    SK_FILL bt_locker, SKM_ALL, AC_WOOD_2, 15
    SK_BMP bt_locker, SKF_RIGHT, 0, 0, bt_locker_right
    SK_BMP bt_locker, SKF_LEFT, 0, 0, bt_locker_right
    SK_BMP bt_locker, SKF_TOP, 0, 0, bt_locker_top
    SK_BMP bt_locker, SKF_BOTTOM, 0, 0, bt_locker_bottom
    SK_BMP bt_locker, SKF_BACK, 0, 0, bt_locker_back
    SK_BMP bt_locker, SKF_FRONT, 0, 0, bt_locker_front
    SK_GRAD bt_locker, SKM_SIDES, 272, 224
    ; --- bt_rib_1
    SK_FILL bt_rib_1, SKM_ALL, AC_WOOD_3, 15
    SK_BMP bt_rib_1, SKF_RIGHT, 0, 0, bt_rib_1_right
    SK_BMP bt_rib_1, SKF_LEFT, 0, 0, bt_rib_1_right
    SK_BMP bt_rib_1, SKF_TOP, 0, 0, bt_rib_1_top
    SK_BMP bt_rib_1, SKF_BOTTOM, 0, 0, bt_rib_1_bottom
    SK_BMP bt_rib_1, SKF_BACK, 0, 0, bt_rib_1_right
    SK_BMP bt_rib_1, SKF_FRONT, 0, 0, bt_rib_1_right
    SK_GRAD bt_rib_1, SKM_SIDES, 272, 224
    ; --- bt_lock_l
    SK_FILL bt_lock_l, SKM_ALL, AC_IRON_3, 0
    SK_BMP bt_lock_l, SKF_RIGHT, 0, 0, bt_lock_l_right
    SK_BMP bt_lock_l, SKF_LEFT, 0, 0, bt_lock_l_right
    SK_BMP bt_lock_l, SKF_TOP, 0, 0, bt_lock_l_top
    SK_BMP bt_lock_l, SKF_BOTTOM, 0, 0, bt_lock_l_bottom
    SK_BMP bt_lock_l, SKF_BACK, 0, 0, bt_lock_l_back
    SK_BMP bt_lock_l, SKF_FRONT, 0, 0, bt_lock_l_back
    SK_GRAD bt_lock_l, SKM_SIDES, 272, 224
    ; --- bt_coil
    SK_FILL bt_coil, SKM_ALL, BT_HEMP_3, 15
    SK_BMP bt_coil, SKF_RIGHT, 0, 0, bt_coil_right
    SK_BMP bt_coil, SKF_LEFT, 0, 0, bt_coil_right
    SK_BMP bt_coil, SKF_TOP, 0, 0, bt_coil_top
    SK_BMP bt_coil, SKF_BOTTOM, 0, 0, bt_coil_bottom
    SK_BMP bt_coil, SKF_BACK, 0, 0, bt_coil_back
    SK_BMP bt_coil, SKF_FRONT, 0, 0, bt_coil_back
    SK_GRAD bt_coil, SKM_SIDES, 272, 224
SKMODEL_END

; ===================================================================================================
; m_plane
; ===================================================================================================
RAMP PL_RED, 200, 56, 44
RAMP PL_CREAM, 232, 222, 194
RAMP PL_RUBBER, 50, 50, 56
RAMP PL_BLUE, 40, 78, 160

section .rodata
; The characters of every pl_ bitmap. Groups: base, highlight, shade, deep.
;   r R q Q red paint   c C k K cream canvas   s S z Z steel (s base, S bright, z shade, Z dark)
;   b B d D black rubber and dark iron   u U v V roundel blue   w white   l L m M leather
;   g G o O brass   y Y glass glints   f F h red lens   n N e green lens   a soot   _ transparent
align 8
pl_pal:
    PALC 'r', PL_RED_2
    PALC 'R', PL_RED_1
    PALC 'q', PL_RED_3
    PALC 'Q', PL_RED_4
    PALC 'c', PL_CREAM_2
    PALC 'C', PL_CREAM_1
    PALC 'k', PL_CREAM_3
    PALC 'K', PL_CREAM_4
    PALC 's', AC_IRON_2
    PALC 'S', AC_IRON_1
    PALC 'z', AC_IRON_3
    PALC 'Z', AC_IRON_4
    PALC 'b', PL_RUBBER_2
    PALC 'B', PL_RUBBER_1
    PALC 'd', PL_RUBBER_3
    PALC 'D', PL_RUBBER_4
    PALC 'u', PL_BLUE_2
    PALC 'U', PL_BLUE_1
    PALC 'v', PL_BLUE_3
    PALC 'V', PL_BLUE_4
    PALC 'w', RGBO(244, 244, 238)
    PALC 'l', AC_LEATHER_2
    PALC 'L', AC_LEATHER_1
    PALC 'm', AC_LEATHER_3
    PALC 'M', AC_LEATHER_4
    PALC 'g', AC_GOLD_2
    PALC 'G', AC_GOLD_1
    PALC 'o', AC_GOLD_3
    PALC 'O', AC_GOLD_4
    PALC 'y', RGBO(150, 206, 236)
    PALC 'Y', RGBO(226, 244, 255)
    PALC 'f', RGBO(236, 64, 56)
    PALC 'F', RGBO(255, 190, 170)
    PALC 'h', RGBO(140, 28, 30)
    PALC 'n', RGBO(60, 196, 90)
    PALC 'N', RGBO(180, 255, 196)
    PALC 'e', RGBO(30, 112, 56)
    PALC 'a', RGBO(26, 24, 26)
    PALT '_'
    dq 0

    ; pl_cowl_right (8x18): pl_cowl RIGHT
    SKROWS pl_cowl_right_rows, 8, 18
    SKROW "ssssssss"
    SKROW "........"
    SKROW "sZsZSZ.."
    SKROW "sZsZSZS."
    SKROW "sZsZSZ.."
    SKROW "sZsZSZ.."
    SKROW "sZsZSZ.."
    SKROW "sZsZSZS."
    SKROW "sZsZSZ.."
    SKROW "........"
    SKROW "........"
    SKROW "......S."
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW "......S."
    SKROW "........"
    SKROW "ZZZZZZZZ"
    SKROWS_END
    align 8
    SKBMP pl_cowl_right, pl_cowl_right_rows, 8, 18, pl_pal
    ; pl_cowl_left (8x18): pl_cowl LEFT
    SKROWS pl_cowl_left_rows, 8, 18
    SKROW "ssssssss"
    SKROW "........"
    SKROW "..ZSZsZs"
    SKROW ".SZSZsZs"
    SKROW "..ZSZsZs"
    SKROW "..ZSZsZs"
    SKROW "..ZSZsZs"
    SKROW ".SZSZsZs"
    SKROW "..ZSZsZs"
    SKROW "........"
    SKROW "........"
    SKROW ".S......"
    SKROW "........"
    SKROW "........"
    SKROW "........"
    SKROW ".S......"
    SKROW "........"
    SKROW "ZZZZZZZZ"
    SKROWS_END
    align 8
    SKBMP pl_cowl_left, pl_cowl_left_rows, 8, 18, pl_pal
    ; pl_cowl_top (20x8): pl_cowl TOP
    SKROWS pl_cowl_top_rows, 20, 8
    SKROW "SssSssSssSssSssSssSs"
    SKROW ".........ZZ........."
    SKROW ".........ZZ........."
    SKROW "..ZZZZZZ.ZZZZZZZZ..."
    SKROW "..ssssss.ZZssssss..."
    SKROW "..ZZZZZZ.ZZZZZZZZ..."
    SKROW ".........ZZ........."
    SKROW "SssSssSssSssSssSssSs"
    SKROWS_END
    align 8
    SKBMP pl_cowl_top, pl_cowl_top_rows, 20, 8, pl_pal
    ; pl_cowl_bottom (20x8): pl_cowl BOTTOM
    SKROWS pl_cowl_bottom_rows, 20, 8
    SKROW "zzzzzzzzzZZzzzzzzzzz"
    SKROW "zzzzzzzzzZZzzzzzzzzz"
    SKROW "zzzzzzzzzZZzzzzzzzzz"
    SKROW "zzzzzzzzzZZzzzzzzzzz"
    SKROW "zzzzzzzzzZZzzzzzzzzz"
    SKROW "zzzzzzzzzZZzzzzzzzzz"
    SKROW "zzzzzzzzzZZzzzzzzzzz"
    SKROW "zzzzzzzzzZZzzzzzzzzz"
    SKROWS_END
    align 8
    SKBMP pl_cowl_bottom, pl_cowl_bottom_rows, 20, 8, pl_pal
    ; pl_cowl_back (20x18): pl_cowl BACK
    SKROWS pl_cowl_back_rows, 20, 18
    SKROW "ZZZZZZZZZZZZZZZZZZZZ"
    SKROW "ZZZZZZZZZZZZZZZZZZZZ"
    SKROW "ZZZZZZZZZZZZZZZZZZZZ"
    SKROW "ZZZZZZZZZZZZZZZZZZZZ"
    SKROW "ZZZZZZZZZZZZZZZZZZZZ"
    SKROW "ZZZZZZZZZZZZZZZZZZZZ"
    SKROW "ZZZZZZZZZZZZZZZZZZZZ"
    SKROW "ZZZZZZZZZZZZZZZZZZZZ"
    SKROW "ZZZZZZZZZZZZZZZZZZZZ"
    SKROW "ZZZZZZZZZZZZZZZZZZZZ"
    SKROW "ZZZZZZZZZZZZZZZZZZZZ"
    SKROW "ZZZZZZZZZZZZZZZZZZZZ"
    SKROW "ZZZZZZZZZZZZZZZZZZZZ"
    SKROW "ZZZZZZZZZZZZZZZZZZZZ"
    SKROW "ZZZZZZZZZZZZZZZZZZZZ"
    SKROW "ZZZZZZZZZZZZZZZZZZZZ"
    SKROW "ZZZZZZZZZZZZZZZZZZZZ"
    SKROW "ZZZZZZZZZZZZZZZZZZZZ"
    SKROWS_END
    align 8
    SKBMP pl_cowl_back, pl_cowl_back_rows, 20, 18, pl_pal
    ; pl_cowl_front (20x18): pl_cowl FRONT
    SKROWS pl_cowl_front_rows, 20, 18
    SKROW "zzzzzzzzzaazzzzzzzzz"
    SKROW "zzzzzzaaaaaaaazzzzzz"
    SKROW "zzzzaaaaasSaaaaazzzz"
    SKROW "zzzaasSaassaasSaazzz"
    SKROW "zzzaasSSaaaassSaazzz"
    SKROW "zzaaassaaaaaassaaazz"
    SKROW "zzaaaaaassssaaaaaazz"
    SKROW "zzasSSassSSssassSazz"
    SKROW "zaasssasSSSSsasssaaz"
    SKROW "zaaaaaasSSSSsaaaaaaz"
    SKROW "zzaaaaassSSssaaaaazz"
    SKROW "zzaasSaassssaasSaazz"
    SKROW "zzaassaaaaaaaassaazz"
    SKROW "zzzaaaasSaasSaaaazzz"
    SKROW "zzzaaaasSaasSaaaazzz"
    SKROW "zzzzaaassaassaaazzzz"
    SKROW "zzzzzzaaaaaaaazzzzzz"
    SKROW "zzzzzzzzzaazzzzzzzzz"
    SKROWS_END
    align 8
    SKBMP pl_cowl_front, pl_cowl_front_rows, 20, 18, pl_pal
    ; pl_ring_h_right (2x14): pl_ring_h RIGHT
    SKROWS pl_ring_h_right_rows, 2, 14
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROWS_END
    align 8
    SKBMP pl_ring_h_right, pl_ring_h_right_rows, 2, 14, pl_pal
    ; pl_ring_h_left (2x14): pl_ring_h LEFT
    SKROWS pl_ring_h_left_rows, 2, 14
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROWS_END
    align 8
    SKBMP pl_ring_h_left, pl_ring_h_left_rows, 2, 14, pl_pal
    ; pl_ring_h_top (22x2): pl_ring_h TOP
    SKROWS pl_ring_h_top_rows, 22, 2
    SKROW "SSSSSSSSSSSSSSSSSSSSSS"
    SKROW "SSSSSSSSSSSSSSSSSSSSSS"
    SKROWS_END
    align 8
    SKBMP pl_ring_h_top, pl_ring_h_top_rows, 22, 2, pl_pal
    ; pl_ring_h_bottom (22x2): pl_ring_h BOTTOM
    SKROWS pl_ring_h_bottom_rows, 22, 2
    SKROW "zzzzzzzzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzzzzzzzz"
    SKROWS_END
    align 8
    SKBMP pl_ring_h_bottom, pl_ring_h_bottom_rows, 22, 2, pl_pal
    ; pl_ring_h_back (22x14): pl_ring_h BACK
    SKROWS pl_ring_h_back_rows, 22, 14
    SKROW "zzzzzzzzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzzzzzzzz"
    SKROWS_END
    align 8
    SKBMP pl_ring_h_back, pl_ring_h_back_rows, 22, 14, pl_pal
    ; pl_ring_h_front (22x14): pl_ring_h FRONT
    SKROWS pl_ring_h_front_rows, 22, 14
    SKROW "SSS.ssZ________sSSSSSS"
    SKROW "z..ssZ__________sSSSSS"
    SKROW "z..sZ____________sSSSS"
    SKROW "zZsZ______________sSZS"
    SKROW "z.zZ______________sSSS"
    SKROW "z.zZ______________sSSS"
    SKROW "zzzZ______________sSSS"
    SKROW "zzzZ______________sSSS"
    SKROW "z.zZ______________sSSS"
    SKROW "z.zZ______________sSSS"
    SKROW "zZzZ______________ZSZS"
    SKROW "z..zZ____________Zs..S"
    SKROW "z..zzZ__________Zss..S"
    SKROW "zzz.zzZ________Zss.zzS"
    SKROWS_END
    align 8
    SKBMP pl_ring_h_front, pl_ring_h_front_rows, 22, 14, pl_pal
    ; pl_ring_v_right (2x20): pl_ring_v RIGHT
    SKROWS pl_ring_v_right_rows, 2, 20
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROW "zz"
    SKROWS_END
    align 8
    SKBMP pl_ring_v_right, pl_ring_v_right_rows, 2, 20, pl_pal
    ; pl_ring_v_left (2x20): pl_ring_v LEFT
    SKROWS pl_ring_v_left_rows, 2, 20
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROW "SS"
    SKROWS_END
    align 8
    SKBMP pl_ring_v_left, pl_ring_v_left_rows, 2, 20, pl_pal
    ; pl_ring_v_top (16x2): pl_ring_v TOP
    SKROWS pl_ring_v_top_rows, 16, 2
    SKROW "SSSSSSSSSSSSSSSS"
    SKROW "SSSSSSSSSSSSSSSS"
    SKROWS_END
    align 8
    SKBMP pl_ring_v_top, pl_ring_v_top_rows, 16, 2, pl_pal
    ; pl_ring_v_bottom (16x2): pl_ring_v BOTTOM
    SKROWS pl_ring_v_bottom_rows, 16, 2
    SKROW "zzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzz"
    SKROWS_END
    align 8
    SKBMP pl_ring_v_bottom, pl_ring_v_bottom_rows, 16, 2, pl_pal
    ; pl_ring_v_back (16x20): pl_ring_v BACK
    SKROWS pl_ring_v_back_rows, 16, 20
    SKROW "zzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzz"
    SKROW "zzzzzzzzzzzzzzzz"
    SKROWS_END
    align 8
    SKBMP pl_ring_v_back, pl_ring_v_back_rows, 16, 20, pl_pal
    ; pl_ring_v_front (16x20): pl_ring_v FRONT
    SKROWS pl_ring_v_front_rows, 16, 20
    SKROW "SSSSSSSSSSSSSSSS"
    SKROW "z...SSSSSSSSSSSS"
    SKROW "z.ssZsssssssSSSS"
    SKROW ".ssZ________sSSS"
    SKROW "ssZ__________sSS"
    SKROW "sZ____________sS"
    SKROW "Z______________s"
    SKROW "Z______________s"
    SKROW "Z______________s"
    SKROW "Z______________s"
    SKROW "Z______________s"
    SKROW "Z______________s"
    SKROW "Z______________s"
    SKROW "Z______________Z"
    SKROW "zZ____________Zs"
    SKROW "zzZ__________Zss"
    SKROW ".zzZ________Zss."
    SKROW "z.zzZZZZZZZZss.S"
    SKROW "z...zzzzzzzs...S"
    SKROW "zzzzzzzzzzzzzzzS"
    SKROWS_END
    align 8
    SKBMP pl_ring_v_front, pl_ring_v_front_rows, 16, 20, pl_pal
    ; pl_stub_a_l_right (3x3): pl_stub_a_l RIGHT, pl_stub_a_l LEFT
    SKROWS pl_stub_a_l_right_rows, 3, 3
    SKROW "zzz"
    SKROW "zzz"
    SKROW "ZZZ"
    SKROWS_END
    align 8
    SKBMP pl_stub_a_l_right, pl_stub_a_l_right_rows, 3, 3, pl_pal
    ; pl_stub_a_l_top (3x3): pl_stub_a_l TOP
    SKROWS pl_stub_a_l_top_rows, 3, 3
    SKROW "zzs"
    SKROW "zzs"
    SKROW "zzs"
    SKROWS_END
    align 8
    SKBMP pl_stub_a_l_top, pl_stub_a_l_top_rows, 3, 3, pl_pal
    ; pl_stub_a_l_bottom (3x3): pl_stub_a_l BOTTOM
    SKROWS pl_stub_a_l_bottom_rows, 3, 3
    SKROW "ZZZ"
    SKROW "ZZZ"
    SKROW "ZZZ"
    SKROWS_END
    align 8
    SKBMP pl_stub_a_l_bottom, pl_stub_a_l_bottom_rows, 3, 3, pl_pal
    ; pl_stub_a_l_back (3x3): pl_stub_a_l BACK
    SKROWS pl_stub_a_l_back_rows, 3, 3
    SKROW "ZZZ"
    SKROW "ZaZ"
    SKROW "ZZZ"
    SKROWS_END
    align 8
    SKBMP pl_stub_a_l_back, pl_stub_a_l_back_rows, 3, 3, pl_pal
    ; pl_stub_a_l_front (3x3): pl_stub_a_l FRONT
    SKROWS pl_stub_a_l_front_rows, 3, 3
    SKROW "zzz"
    SKROW "zzz"
    SKROW "zzz"
    SKROWS_END
    align 8
    SKBMP pl_stub_a_l_front, pl_stub_a_l_front_rows, 3, 3, pl_pal
    ; pl_fus_a_right (18x19): pl_fus_a RIGHT
    SKROWS pl_fus_a_right_rows, 18, 19
    SKROW "QRRRRRRRRQRRRRRRRR"
    SKROW "Q........Q.QQQQQQ."
    SKROW "Q........Q.RRRRRR."
    SKROW "Q.......RQ.QQQQQQ."
    SKROW "Q........Q.RRRRRR."
    SKROW "Q........Q.QQQQQQ."
    SKROW "Q.......RQ........"
    SKROW "Q........Q........"
    SKROW "QqqqqqqqqQqqqqqqqq"
    SKROW "kcccccccckcccccccc"
    SKROW "kCCCCCCCCkCCCCCCCC"
    SKROW "QqqqqqqqqQqqqqqqqq"
    SKROW "Q.......RQ........"
    SKROW "Q........Qqq..QQ.."
    SKROW "Q.......qQ.qq..QQ."
    SKROW "Q.......RQ........"
    SKROW "Q........Q........"
    SKROW "Q........Q........"
    SKROW "QqqqqqqqqQqqqqqqqq"
    SKROWS_END
    align 8
    SKBMP pl_fus_a_right, pl_fus_a_right_rows, 18, 19, pl_pal
    ; pl_fus_a_left (18x19): pl_fus_a LEFT
    SKROWS pl_fus_a_left_rows, 18, 19
    SKROW "RRRRRRRRQRRRRRRRRQ"
    SKROW ".QQQQQQ.Q........Q"
    SKROW ".RRRRRR.Q........Q"
    SKROW ".QQQQQQ.QR.......Q"
    SKROW ".RRRRRR.Q........Q"
    SKROW ".QQQQQQ.Q........Q"
    SKROW "........QR.......Q"
    SKROW "........Q........Q"
    SKROW "qqqqqqqqQqqqqqqqqQ"
    SKROW "cccccccckcccccccck"
    SKROW "CCCCCCCCkCCCCCCCCk"
    SKROW "qqqqqqqqQqqqqqqqqQ"
    SKROW "........QR.......Q"
    SKROW "..QQ..qqQ........Q"
    SKROW ".QQ..qq.Qq.......Q"
    SKROW "........QR.......Q"
    SKROW "........Q........Q"
    SKROW "........Q........Q"
    SKROW "qqqqqqqqQqqqqqqqqQ"
    SKROWS_END
    align 8
    SKBMP pl_fus_a_left, pl_fus_a_left_rows, 18, 19, pl_pal
    ; pl_fus_a_top (22x18): pl_fus_a TOP
    SKROWS pl_fus_a_top_rows, 22, 18
    SKROW "q.........q.........q."
    SKROW "q.........q.........q."
    SKROW "q..zsz....q.........q."
    SKROW "q.zsssz...q.........q."
    SKROW "q.ssSSS...q.........q."
    SKROW "q.zsSSz...q.........q."
    SKROW "q..zSz....q.........q."
    SKROW "q.........q.........q."
    SKROW "qR..R..R..R..R..R..Rq."
    SKROW "QQQQQQQQQQQQQQQQQQQQQQ"
    SKROW "q...................q."
    SKROW "q...................q."
    SKROW "q...................q."
    SKROW "q...................q."
    SKROW "q...................q."
    SKROW "q...................q."
    SKROW "q...................q."
    SKROW "q...................q."
    SKROWS_END
    align 8
    SKBMP pl_fus_a_top, pl_fus_a_top_rows, 22, 18, pl_pal
    ; pl_fus_a_bottom (22x18): pl_fus_a BOTTOM
    SKROWS pl_fus_a_bottom_rows, 22, 18
    SKROW "qqqqqqqqqqqqqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqqqqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqqqqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqqqqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqqqqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqqqqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqqqqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqqqqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqqqqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROWS_END
    align 8
    SKBMP pl_fus_a_bottom, pl_fus_a_bottom_rows, 22, 18, pl_pal
    ; pl_fus_a_front (22x19): pl_fus_a FRONT
    SKROWS pl_fus_a_front_rows, 22, 19
    SKROW "QQQQQQQQQQQQQQQQQQQQQQ"
    SKROW "QQQQQQQQQQQQQQQQQQQQQQ"
    SKROW "QQQQQQQQQQQQQQQQQQQQQQ"
    SKROW "QQQQQQQQQQQQQQQQQQQQQQ"
    SKROW "QQQQQQQQQQQQQQQQQQQQQQ"
    SKROW "QQQQQQQQQQQQQQQQQQQQQQ"
    SKROW "QQQQQQQQQQQQQQQQQQQQQQ"
    SKROW "QQQQQQQQQQQQQQQQQQQQQQ"
    SKROW "QQQQQQQQQQQQQQQQQQQQQQ"
    SKROW "QQQQQQQQQQQQQQQQQQQQQQ"
    SKROW "QQQQQQQQQQQQQQQQQQQQQQ"
    SKROW "QQQQQQQQQQQQQQQQQQQQQQ"
    SKROW "QQQQQQQQQQQQQQQQQQQQQQ"
    SKROW "QQQQQQQQQQQQQQQQQQQQQQ"
    SKROW "QQQQQQQQQQQQQQQQQQQQQQ"
    SKROW "QQQQQQQQQQQQQQQQQQQQQQ"
    SKROW "QQQQQQQQQQQQQQQQQQQQQQ"
    SKROW "QQQQQQQQQQQQQQQQQQQQQQ"
    SKROW "QQQQQQQQQQQQQQQQQQQQQQ"
    SKROWS_END
    align 8
    SKBMP pl_fus_a_front, pl_fus_a_front_rows, 22, 19, pl_pal
    ; pl_fus_b_right (30x20): pl_fus_b RIGHT
    SKROWS pl_fus_b_right_rows, 30, 20
    SKROW "RmlllmlllmlllmlllmlRRQRRRRRRRQ"
    SKROW "....RQ..............RQ......RQ"
    SKROW ".....Q...............Q.......Q"
    SKROW ".....Q...............Q.......Q"
    SKROW "....RQ..............RQ......RQ"
    SKROW ".....Q...............Q.......Q"
    SKROW ".....Q...............Q.......Q"
    SKROW "....RQ..............RQ......RQ"
    SKROW ".....Q...............Q.......Q"
    SKROW "qqqqqQqqqqqqqqqqqqqqqQqqqqqqqQ"
    SKROW "ccccckccccccccccccccckccccccck"
    SKROW "CCCCCkCCCCCCCCCCCCCCCkCCCCCCCk"
    SKROW "qqqqqQqqqqqqqqqqqqqqqQqqqqqqqQ"
    SKROW "....RQ..............RQ......RQ"
    SKROW ".....Q...............QQQQQ...Q"
    SKROW ".SqqSQ..............QQ...RQ..Q"
    SKROW ".q..qQDDDDD.........QQS...Q.RQ"
    SKROW ".q..qQzzzzz.........QQ...RQ..Q"
    SKROW ".SqqSQ...............QQQQQ...Q"
    SKROW "qqqqqQqqqqqqqqqqqqqqqQqqqqqqqQ"
    SKROWS_END
    align 8
    SKBMP pl_fus_b_right, pl_fus_b_right_rows, 30, 20, pl_pal
    ; pl_fus_b_left (30x20): pl_fus_b LEFT
    SKROWS pl_fus_b_left_rows, 30, 20
    SKROW "QRRRRRRRQRRlmlllmlllmlllmlllmR"
    SKROW "QR......QR..............QR...."
    SKROW "Q.......Q...............Q....."
    SKROW "Q.......Q...............Q....."
    SKROW "QR......QR..............QR...."
    SKROW "Q.......Q...............Q....."
    SKROW "Q.......Q...............Q....."
    SKROW "QR......QR..............QR...."
    SKROW "Q.......Q...............Q....."
    SKROW "QqqqqqqqQqqqqqqqqqqqqqqqQqqqqq"
    SKROW "kccccccckccccccccccccccckccccc"
    SKROW "kCCCCCCCkCCCCCCCCCCCCCCCkCCCCC"
    SKROW "QqqqqqqqQqqqqqqqqqqqqqqqQqqqqq"
    SKROW "QR......QR..............QR...."
    SKROW "Q...QQQQQ...............Q....."
    SKROW "Q..QR...QQ..............QSqqS."
    SKROW "QR.Q...SQQ.........DDDDDQq..q."
    SKROW "Q..QR...QQ.........zzzzzQq..q."
    SKROW "Q...QQQQQ...............QSqqS."
    SKROW "QqqqqqqqQqqqqqqqqqqqqqqqQqqqqq"
    SKROWS_END
    align 8
    SKBMP pl_fus_b_left, pl_fus_b_left_rows, 30, 20, pl_pal
    ; pl_fus_b_top (22x30): pl_fus_b TOP
    SKROWS pl_fus_b_top_rows, 22, 30
    SKROW "qqqqqqqqqqqqqqqqqqqqqq"
    SKROW "q...................q."
    SKROW "q.DDDDDDDDDDDDDDDDDDq."
    SKROW "q.DddddddddddddddddDq."
    SKROW "q.DddddddddddddddddDq."
    SKROW "q.DddddddddddddddddDq."
    SKROW "q.DdddmMmMmMmMmMdddDq."
    SKROW "q.DdddMmmmmmmmLmdddDq."
    SKROW "q.DdddmmlMllMlLMdddDq."
    SKROW "q.DdddMmllMMllLmdddDq."
    SKROW "q.DdddmmlMllMlLMdddDq."
    SKROW "q.DdddMmllllllLmdddDq."
    SKROW "q.DdddmLLLLLLLLMdddDq."
    SKROW "q.DdddMmMmMmMmMmdddDq."
    SKROW "q.DddddddddddddddddDq."
    SKROW "q.DddddddddddddddddDq."
    SKROW "q.DdddsssddddsssdddDq."
    SKROW "q.DddddddddddddddddDq."
    SKROW "q.DDDDDDDDDDDDDDDDDDq."
    SKROW "q.........q.........q."
    SKROW "q.........q.........q."
    SKROW "q.........q.........q."
    SKROW "qR..R..R..R..R..R..Rq."
    SKROW "QQQQQQQQQQQQQQQQQQQQQQ"
    SKROW "q.........q.........q."
    SKROW "q.........q.........q."
    SKROW "q.........q.........q."
    SKROW "q.........q.........q."
    SKROW "q.........q.........q."
    SKROW "q.........q.........q."
    SKROWS_END
    align 8
    SKBMP pl_fus_b_top, pl_fus_b_top_rows, 22, 30, pl_pal
    ; pl_fus_b_bottom (22x30): pl_fus_b BOTTOM
    SKROWS pl_fus_b_bottom_rows, 22, 30
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "QQQQQQQQQQQQQQQQQQQQQQ"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "QQQQQQQQQQQQQQQQQQQQQQ"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "QQQQQQQQQQQQQQQQQQQQQQ"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROW "qqqqqqqqqqQQqqqqqqqqqq"
    SKROWS_END
    align 8
    SKBMP pl_fus_b_bottom, pl_fus_b_bottom_rows, 22, 30, pl_pal
    ; pl_fus_b_back (22x20): pl_fus_b BACK
    SKROWS pl_fus_b_back_rows, 22, 20
    SKROW "qQqqQqqQqqQqqQqqQqqQqq"
    SKROW "qqQqqQqqQqqQqqQqqQqqQq"
    SKROW "QqqQqqQqqQqqQqqQqqQqqQ"
    SKROW "qQqqQqqQqqQqqQqqQqqQqq"
    SKROW "qqQqqQqqQqqQqqQqqQqqQq"
    SKROW "QqqQqqQqqQqqQqqQqqQqqQ"
    SKROW "qQqqQqqQqqQqqQqqQqqQqq"
    SKROW "qqQqqQqqQqqQqqQqqQqqQq"
    SKROW "QqqQqqQqqQqqQqqQqqQqqQ"
    SKROW "qQqqQqqQqqQqqQqqQqqQqq"
    SKROW "qqQqqQqqQqqQqqQqqQqqQq"
    SKROW "QqqQqqQqqQqqQqqQqqQqqQ"
    SKROW "qQqqQqqQqqQqqQqqQqqQqq"
    SKROW "qqQqqQqqQqqQqqQqqQqqQq"
    SKROW "QqqQqqQqqQqqQqqQqqQqqQ"
    SKROW "qQqqQqqQqqQqqQqqQqqQqq"
    SKROW "qqQqqQqqQqqQqqQqqQqqQq"
    SKROW "QqqQqqQqqQqqQqqQqqQqqQ"
    SKROW "qQqqQqqQqqQqqQqqQqqQqq"
    SKROW "qqQqqQqqQqqQqqQqqQqqQq"
    SKROWS_END
    align 8
    SKBMP pl_fus_b_back, pl_fus_b_back_rows, 22, 20, pl_pal
    ; pl_fus_b_front (22x20): pl_fus_b FRONT
    SKROWS pl_fus_b_front_rows, 22, 20
    SKROW "qqQqqQqqQqqQqqQqqQqqQq"
    SKROW "qQqqQqqQqqQqqQqqQqqQqq"
    SKROW "QqqQqqQqqQqqQqqQqqQqqQ"
    SKROW "qqQqqQqqQqqQqqQqqQqqQq"
    SKROW "qQqqQqqQqqQqqQqqQqqQqq"
    SKROW "QqqQqqQqqQqqQqqQqqQqqQ"
    SKROW "qqQqqQqqQqqQqqQqqQqqQq"
    SKROW "qQqqQqqQqqQqqQqqQqqQqq"
    SKROW "QqqQqqQqqQqqQqqQqqQqqQ"
    SKROW "qqQqqQqqQqqQqqQqqQqqQq"
    SKROW "qQqqQqqQqqQqqQqqQqqQqq"
    SKROW "QqqQqqQqqQqqQqqQqqQqqQ"
    SKROW "qqQqqQqqQqqQqqQqqQqqQq"
    SKROW "qQqqQqqQqqQqqQqqQqqQqq"
    SKROW "QqqQqqQqqQqqQqqQqqQqqQ"
    SKROW "qqQqqQqqQqqQqqQqqQqqQq"
    SKROW "qQqqQqqQqqQqqQqqQqqQqq"
    SKROW "QqqQqqQqqQqqQqqQqqQqqQ"
    SKROW "qqQqqQqqQqqQqqQqqQqqQq"
    SKROW "qQqqQqqQqqQqqQqqQqqQqq"
    SKROWS_END
    align 8
    SKBMP pl_fus_b_front, pl_fus_b_front_rows, 22, 20, pl_pal
    ; pl_fus_c_right (12x16): pl_fus_c RIGHT
    SKROWS pl_fus_c_right_rows, 12, 16
    SKROW "QRRRRRRRRRRQ"
    SKROW "Q..........Q"
    SKROW "Q.........RQ"
    SKROW "Q...uuuu...Q"
    SKROW "Q..uuuuuu..Q"
    SKROW "Q.uuwwwwuuRQ"
    SKROW "QuuwwrrwwuuQ"
    SKROW "QuuwrrrrwuuQ"
    SKROW "kuuwrrrrwuuk"
    SKROW "kuuwwrrwwuuk"
    SKROW "QquuwwwwuuqQ"
    SKROW "Q..uuuuuu.RQ"
    SKROW "Q...uuuu...Q"
    SKROW "Q..........Q"
    SKROW "Q.........RQ"
    SKROW "QqqqqqqqqqqQ"
    SKROWS_END
    align 8
    SKBMP pl_fus_c_right, pl_fus_c_right_rows, 12, 16, pl_pal
    ; pl_fus_c_left (12x16): pl_fus_c LEFT
    SKROWS pl_fus_c_left_rows, 12, 16
    SKROW "QRRRRRRRRRRQ"
    SKROW "Q..........Q"
    SKROW "QR.........Q"
    SKROW "Q...uuuu...Q"
    SKROW "Q..uuuuuu..Q"
    SKROW "QRuuwwwwuu.Q"
    SKROW "QuuwwrrwwuuQ"
    SKROW "QuuwrrrrwuuQ"
    SKROW "kuuwrrrrwuuk"
    SKROW "kuuwwrrwwuuk"
    SKROW "QquuwwwwuuqQ"
    SKROW "QR.uuuuuu..Q"
    SKROW "Q...uuuu...Q"
    SKROW "Q..........Q"
    SKROW "QR.........Q"
    SKROW "QqqqqqqqqqqQ"
    SKROWS_END
    align 8
    SKBMP pl_fus_c_left, pl_fus_c_left_rows, 12, 16, pl_pal
    ; pl_fus_c_top (18x12): pl_fus_c TOP
    SKROWS pl_fus_c_top_rows, 18, 12
    SKROW "q...............q."
    SKROW "q...............q."
    SKROW "q...............q."
    SKROW "q...............q."
    SKROW "q...............q."
    SKROW "q...............q."
    SKROW "q...............q."
    SKROW "q...............q."
    SKROW "q...............q."
    SKROW "q...............q."
    SKROW "q.R..R..R..R..R.qR"
    SKROW "QQQQQQQQQQQQQQQQQQ"
    SKROWS_END
    align 8
    SKBMP pl_fus_c_top, pl_fus_c_top_rows, 18, 12, pl_pal
    ; pl_fus_c_bottom (18x12): pl_fus_c BOTTOM
    SKROWS pl_fus_c_bottom_rows, 18, 12
    SKROW "qqqqqqqqQQqqqqqqqq"
    SKROW "qqqqqqqqQQqqqqqqqq"
    SKROW "qqqqqqqqQQqqqqqqqq"
    SKROW "qqqqqqqqQQqqqqqqqq"
    SKROW "qqqqqqqqQQqqqqqqqq"
    SKROW "qqqqqqqqQQqqqqqqqq"
    SKROW "qqqqqqqqQQqqqqqqqq"
    SKROW "qqqqqqqqQQqqqqqqqq"
    SKROW "qqqqqqqqQQqqqqqqqq"
    SKROW "qqqqqqqqQQqqqqqqqq"
    SKROW "qqqqqqqqQQqqqqqqqq"
    SKROW "qqqqqqqqQQqqqqqqqq"
    SKROWS_END
    align 8
    SKBMP pl_fus_c_bottom, pl_fus_c_bottom_rows, 18, 12, pl_pal
    ; pl_fus_c_back (18x16): pl_fus_c BACK
    SKROWS pl_fus_c_back_rows, 18, 16
    SKROW "qQqqQqqQqqQqqQqqQq"
    SKROW "qqQqqQqqQqqQqqQqqQ"
    SKROW "QqqQqqQqqQqqQqqQqq"
    SKROW "qQqqQqqQqqQqqQqqQq"
    SKROW "qqQqqQqqQqqQqqQqqQ"
    SKROW "QqqQqqQqqQqqQqqQqq"
    SKROW "qQqqQqqQqqQqqQqqQq"
    SKROW "qqQqqQqqQqqQqqQqqQ"
    SKROW "QqqQqqQqqQqqQqqQqq"
    SKROW "qQqqQqqQqqQqqQqqQq"
    SKROW "qqQqqQqqQqqQqqQqqQ"
    SKROW "QqqQqqQqqQqqQqqQqq"
    SKROW "qQqqQqqQqqQqqQqqQq"
    SKROW "qqQqqQqqQqqQqqQqqQ"
    SKROW "QqqQqqQqqQqqQqqQqq"
    SKROW "qQqqQqqQqqQqqQqqQq"
    SKROWS_END
    align 8
    SKBMP pl_fus_c_back, pl_fus_c_back_rows, 18, 16, pl_pal
    ; pl_fus_c_front (18x16): pl_fus_c FRONT
    SKROWS pl_fus_c_front_rows, 18, 16
    SKROW "qQqqQqqQqqQqqQqqQq"
    SKROW "QqqQqqQqqQqqQqqQqq"
    SKROW "qqQqqQqqQqqQqqQqqQ"
    SKROW "qQqqQqqQqqQqqQqqQq"
    SKROW "QqqQqqQqqQqqQqqQqq"
    SKROW "qqQqqQqqQqqQqqQqqQ"
    SKROW "qQqqQqqQqqQqqQqqQq"
    SKROW "QqqQqqQqqQqqQqqQqq"
    SKROW "qqQqqQqqQqqQqqQqqQ"
    SKROW "qQqqQqqQqqQqqQqqQq"
    SKROW "QqqQqqQqqQqqQqqQqq"
    SKROW "qqQqqQqqQqqQqqQqqQ"
    SKROW "qQqqQqqQqqQqqQqqQq"
    SKROW "QqqQqqQqqQqqQqqQqq"
    SKROW "qqQqqQqqQqqQqqQqqQ"
    SKROW "qQqqQqqQqqQqqQqqQq"
    SKROWS_END
    align 8
    SKBMP pl_fus_c_front, pl_fus_c_front_rows, 18, 16, pl_pal
    ; pl_fus_d_right (13x12): pl_fus_d RIGHT
    SKROWS pl_fus_d_right_rows, 13, 12
    SKROW "RRRRRRQRRRRRQ"
    SKROW "......Q.....Q"
    SKROW "......Q.....Q"
    SKROW ".....RQ....RQ"
    SKROW "......Q.....Q"
    SKROW "qqqqqqQqqqqqQ"
    SKROW "cccccckccccck"
    SKROW "CCCCCCkCCCCCk"
    SKROW "qqqqqqQqqqqqQ"
    SKROW ".....RQ....RQ"
    SKROW "......Q.....Q"
    SKROW "qqqqqqQqqqqqQ"
    SKROWS_END
    align 8
    SKBMP pl_fus_d_right, pl_fus_d_right_rows, 13, 12, pl_pal
    ; pl_fus_d_left (13x12): pl_fus_d LEFT
    SKROWS pl_fus_d_left_rows, 13, 12
    SKROW "QRRRRRQRRRRRR"
    SKROW "Q.....Q......"
    SKROW "Q.....Q......"
    SKROW "QR....QR....."
    SKROW "Q.....Q......"
    SKROW "QqqqqqQqqqqqq"
    SKROW "kccccckcccccc"
    SKROW "kCCCCCkCCCCCC"
    SKROW "QqqqqqQqqqqqq"
    SKROW "QR....QR....."
    SKROW "Q.....Q......"
    SKROW "QqqqqqQqqqqqq"
    SKROWS_END
    align 8
    SKBMP pl_fus_d_left, pl_fus_d_left_rows, 13, 12, pl_pal
    ; pl_fus_d_top (12x13): pl_fus_d TOP
    SKROWS pl_fus_d_top_rows, 12, 13
    SKROW ".....qq....."
    SKROW ".....qq....."
    SKROW ".....qq....."
    SKROW ".....qq....."
    SKROW ".....qq....."
    SKROW ".....qq....."
    SKROW ".....qq....."
    SKROW ".....qq....."
    SKROW ".....qq....."
    SKROW ".....qq....."
    SKROW ".....qq....."
    SKROW "..R..R..R..R"
    SKROW "QQQQQQQQQQQQ"
    SKROWS_END
    align 8
    SKBMP pl_fus_d_top, pl_fus_d_top_rows, 12, 13, pl_pal
    ; pl_fus_d_bottom (12x13): pl_fus_d BOTTOM
    SKROWS pl_fus_d_bottom_rows, 12, 13
    SKROW "qqqqqQQqqqqq"
    SKROW "qqqqqQQqqqqq"
    SKROW "qqqqqQQqqqqq"
    SKROW "qqqqqQQqqqqq"
    SKROW "qqqqqQQqqqqq"
    SKROW "qqqqqQQqqqqq"
    SKROW "qqqqqQQqqqqq"
    SKROW "qqqqqQQqqqqq"
    SKROW "qqqqqQQqqqqq"
    SKROW "qqqqqQQqqqqq"
    SKROW "qqqqqQQqqqqq"
    SKROW "qqqqqQQqqqqq"
    SKROW "qqqqqQQqqqqq"
    SKROWS_END
    align 8
    SKBMP pl_fus_d_bottom, pl_fus_d_bottom_rows, 12, 13, pl_pal
    ; pl_fus_d_back (12x12): pl_fus_d BACK
    SKROWS pl_fus_d_back_rows, 12, 12
    SKROW "QQQQzzzzQQQQ"
    SKROW "Q...zwwz...Q"
    SKROW "Q...zCCz...Q"
    SKROW "Q.R.zzzz.R.Q"
    SKROW "Q..........Q"
    SKROW "Q..........Q"
    SKROW "Q..........Q"
    SKROW "Q..........Q"
    SKROW "Q..........Q"
    SKROW "Q.R......R.Q"
    SKROW "Q..........Q"
    SKROW "QQQQQQQQQQQQ"
    SKROWS_END
    align 8
    SKBMP pl_fus_d_back, pl_fus_d_back_rows, 12, 12, pl_pal
    ; pl_fus_d_front (12x12): pl_fus_d FRONT
    SKROWS pl_fus_d_front_rows, 12, 12
    SKROW "qqqqqqqqqqqq"
    SKROW "qqqqqqqqqqqq"
    SKROW "qqqqqqqqqqqq"
    SKROW "qqqqqqqqqqqq"
    SKROW "qqqqqqqqqqqq"
    SKROW "qqqqqqqqqqqq"
    SKROW "qqqqqqqqqqqq"
    SKROW "qqqqqqqqqqqq"
    SKROW "qqqqqqqqqqqq"
    SKROW "qqqqqqqqqqqq"
    SKROW "qqqqqqqqqqqq"
    SKROW "qqqqqqqqqqqq"
    SKROWS_END
    align 8
    SKBMP pl_fus_d_front, pl_fus_d_front_rows, 12, 12, pl_pal
    ; pl_spine_right (12x3): pl_spine RIGHT
    SKROWS pl_spine_right_rows, 12, 3
    SKROW "RRRRRRRRRRRR"
    SKROW ".q...q...q.."
    SKROW "qqqqqqqqqqqq"
    SKROWS_END
    align 8
    SKBMP pl_spine_right, pl_spine_right_rows, 12, 3, pl_pal
    ; pl_spine_left (12x3): pl_spine LEFT
    SKROWS pl_spine_left_rows, 12, 3
    SKROW "RRRRRRRRRRRR"
    SKROW "..q...q...q."
    SKROW "qqqqqqqqqqqq"
    SKROWS_END
    align 8
    SKBMP pl_spine_left, pl_spine_left_rows, 12, 3, pl_pal
    ; pl_spine_top (8x12): pl_spine TOP
    SKROWS pl_spine_top_rows, 8, 12
    SKROW "R..QQ..R"
    SKROW "R..QQ..R"
    SKROW "R..QQ..R"
    SKROW "R..QQ..R"
    SKROW "R..QQ..R"
    SKROW "R..QQ..R"
    SKROW "R..QQ..R"
    SKROW "R..QQ..R"
    SKROW "R..QQ..R"
    SKROW "R..QQ..R"
    SKROW "R..QQ..R"
    SKROW "R..QQ..R"
    SKROWS_END
    align 8
    SKBMP pl_spine_top, pl_spine_top_rows, 8, 12, pl_pal
    ; pl_spine_back (8x3): pl_spine BACK, pl_spine FRONT
    SKROWS pl_spine_back_rows, 8, 3
    SKROW "qqqqqqqq"
    SKROW "qqqqqqqq"
    SKROW "qqqqqqqq"
    SKROWS_END
    align 8
    SKBMP pl_spine_back, pl_spine_back_rows, 8, 3, pl_pal
    ; pl_rim_l_right (18x3): pl_rim_l RIGHT, pl_rim_l LEFT
    SKROWS pl_rim_l_right_rows, 18, 3
    SKROW "LLLLLLLLLLLLLLLLLL"
    SKROW "m...m...m...m...m."
    SKROW "MMMMMMMMMMMMMMMMMM"
    SKROWS_END
    align 8
    SKBMP pl_rim_l_right, pl_rim_l_right_rows, 18, 3, pl_pal
    ; pl_rim_l_top (2x18): pl_rim_l TOP
    SKROWS pl_rim_l_top_rows, 2, 18
    SKROW "Lm"
    SKROW "Lm"
    SKROW "Lm"
    SKROW "Lm"
    SKROW "Lm"
    SKROW "Lm"
    SKROW "Lm"
    SKROW "Lm"
    SKROW "Lm"
    SKROW "Lm"
    SKROW "Lm"
    SKROW "Lm"
    SKROW "Lm"
    SKROW "Lm"
    SKROW "Lm"
    SKROW "Lm"
    SKROW "Lm"
    SKROW "Lm"
    SKROWS_END
    align 8
    SKBMP pl_rim_l_top, pl_rim_l_top_rows, 2, 18, pl_pal
    ; pl_rim_l_back (2x3): pl_rim_l BACK, pl_rim_l FRONT
    SKROWS pl_rim_l_back_rows, 2, 3
    SKROW "LL"
    SKROW ".."
    SKROW "MM"
    SKROWS_END
    align 8
    SKBMP pl_rim_l_back, pl_rim_l_back_rows, 2, 3, pl_pal
    ; pl_rim_f_right (3x4): pl_rim_f RIGHT, pl_rim_f LEFT
    SKROWS pl_rim_f_right_rows, 3, 4
    SKROW "MMM"
    SKROW "MMM"
    SKROW "MMM"
    SKROW "MMM"
    SKROWS_END
    align 8
    SKBMP pl_rim_f_right, pl_rim_f_right_rows, 3, 4, pl_pal
    ; pl_rim_f_top (18x3): pl_rim_f TOP
    SKROWS pl_rim_f_top_rows, 18, 3
    SKROW "MMMMMMMMMMMMMMMMMM"
    SKROW "mL..L..L..L..L..Lm"
    SKROW "MMMMMMMMMMMMMMMMMM"
    SKROWS_END
    align 8
    SKBMP pl_rim_f_top, pl_rim_f_top_rows, 18, 3, pl_pal
    ; pl_rim_f_back (18x4): pl_rim_f BACK
    SKROWS pl_rim_f_back_rows, 18, 4
    SKROW "MMMMMMMMMMMMMMMMMM"
    SKROW "zzSSSzzzSSSzzSSSzz"
    SKROW "zzSDSzzzSDSzzSDSzz"
    SKROW "zzSSSzzzSSSzzSSSzz"
    SKROWS_END
    align 8
    SKBMP pl_rim_f_back, pl_rim_f_back_rows, 18, 4, pl_pal
    ; pl_rim_f_front (18x4): pl_rim_f FRONT
    SKROWS pl_rim_f_front_rows, 18, 4
    SKROW "LLLLLLLLLLLLLLLLLL"
    SKROW "m.....m.....m....."
    SKROW "m.....m.....m....."
    SKROW "MMMMMMMMMMMMMMMMMM"
    SKROWS_END
    align 8
    SKBMP pl_rim_f_front, pl_rim_f_front_rows, 18, 4, pl_pal
    ; pl_rim_b_top (18x3): pl_rim_b TOP
    SKROWS pl_rim_b_top_rows, 18, 3
    SKROW "LLLLLLLLLLLLLLLLLL"
    SKROW ".m..m..m..m..m..m."
    SKROW ".m..m..m..m..m..m."
    SKROWS_END
    align 8
    SKBMP pl_rim_b_top, pl_rim_b_top_rows, 18, 3, pl_pal
    ; pl_rim_b_back (18x5): pl_rim_b BACK
    SKROWS pl_rim_b_back_rows, 18, 5
    SKROW "LLLLLLLLLLLLLLLLLL"
    SKROW "...m...m...m...m.."
    SKROW "m.m.m.m.m.m.m.m.m."
    SKROW ".m...m...m...m...m"
    SKROW "MMMMMMMMMMMMMMMMMM"
    SKROWS_END
    align 8
    SKBMP pl_rim_b_back, pl_rim_b_back_rows, 18, 5, pl_pal
    ; pl_rim_b_front (18x5): pl_rim_b FRONT
    SKROWS pl_rim_b_front_rows, 18, 5
    SKROW ".................."
    SKROW ".................."
    SKROW ".................."
    SKROW ".................."
    SKROW "mmmmmmmmmmmmmmmmmm"
    SKROWS_END
    align 8
    SKBMP pl_rim_b_front, pl_rim_b_front_rows, 18, 5, pl_pal
    ; pl_screen_right (1x11): pl_screen RIGHT, pl_screen LEFT
    SKROWS pl_screen_right_rows, 1, 11
    SKROW "z"
    SKROW "z"
    SKROW "z"
    SKROW "z"
    SKROW "z"
    SKROW "z"
    SKROW "z"
    SKROW "z"
    SKROW "z"
    SKROW "z"
    SKROW "z"
    SKROWS_END
    align 8
    SKBMP pl_screen_right, pl_screen_right_rows, 1, 11, pl_pal
    ; pl_screen_top (18x1): pl_screen TOP
    SKROWS pl_screen_top_rows, 18, 1
    SKROW "ssssssssssssssssss"
    SKROWS_END
    align 8
    SKBMP pl_screen_top, pl_screen_top_rows, 18, 1, pl_pal
    ; pl_screen_bottom (18x1): pl_screen BOTTOM
    SKROWS pl_screen_bottom_rows, 18, 1
    SKROW "zzzzzzzzzzzzzzzzzz"
    SKROWS_END
    align 8
    SKBMP pl_screen_bottom, pl_screen_bottom_rows, 18, 1, pl_pal
    ; pl_screen_back (18x11): pl_screen BACK, pl_screen FRONT
    SKROWS pl_screen_back_rows, 18, 11
    SKROW "SSSSSSSSSSSSSSSSSS"
    SKROW "ssssssssssssssssss"
    SKROW "sz______sz______sz"
    SKROW "sz______sz______sz"
    SKROW "sz______sz______sz"
    SKROW "sz_yY___sz_yY___sz"
    SKROW "sz_Y____sz_Y____sz"
    SKROW "sz______sz______sz"
    SKROW "sz______sz______sz"
    SKROW "zzzzzzzzzzzzzzzzzz"
    SKROW "ZZZZZZZZZZZZZZZZZZ"
    SKROWS_END
    align 8
    SKBMP pl_screen_back, pl_screen_back_rows, 18, 11, pl_pal
    ; pl_seatback_top (10x2): pl_seatback TOP
    SKROWS pl_seatback_top_rows, 10, 2
    SKROW "LLLLLLLLLL"
    SKROW "LLLLLLLLLL"
    SKROWS_END
    align 8
    SKBMP pl_seatback_top, pl_seatback_top_rows, 10, 2, pl_pal
    ; pl_seatback_back (10x8): pl_seatback BACK
    SKROWS pl_seatback_back_rows, 10, 8
    SKROW "LLLLLLLLLL"
    SKROW "M...M...MM"
    SKROW "MM...M...M"
    SKROW "M.M...M..M"
    SKROW "M..M...M.M"
    SKROW "M...M...MM"
    SKROW "MM...M...M"
    SKROW "MMMMMMMMMM"
    SKROWS_END
    align 8
    SKBMP pl_seatback_back, pl_seatback_back_rows, 10, 8, pl_pal
    ; pl_seatback_front (10x8): pl_seatback FRONT
    SKROWS pl_seatback_front_rows, 10, 8
    SKROW "LLLLLLLLLL"
    SKROW "MM...M...M"
    SKROW "M...M...MM"
    SKROW "M..M...M.M"
    SKROW "M.M...M..M"
    SKROW "MM...M...M"
    SKROW "M...M...MM"
    SKROW "MMMMMMMMMM"
    SKROWS_END
    align 8
    SKBMP pl_seatback_front, pl_seatback_front_rows, 10, 8, pl_pal
    ; pl_wing_l_right (30x4): pl_wing_l RIGHT, pl_wing_l LEFT
    SKROWS pl_wing_l_right_rows, 30, 4
    SKROW "RRRRRRRRRRRRRRRRRRRRRRRRRRRRRR"
    SKROW "rrrrrrrrrrrrrrrrrrrrrrrrrrrrrr"
    SKROW "rrrrrrrrrrrrrrrrrrrrrrrrrrrrrr"
    SKROW "qqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"
    SKROWS_END
    align 8
    SKBMP pl_wing_l_right, pl_wing_l_right_rows, 30, 4, pl_pal
    ; pl_wing_l_top (37x30): pl_wing_l TOP
    SKROWS pl_wing_l_top_rows, 37, 30
    SKROW "rrqkkkkkkkkkkkkk.....kkkkkkkkkkkkkqrr"
    SKROW "rrqk.....k.....k.....k.....k.....kqrr"
    SKROW "rrqk.....K.....k.....k.....K.....kqrr"
    SKROW "rrqk.....k.....k.....k.....k.....kqrr"
    SKROW "rrqk.....k.....k.....k.....k.....kqrr"
    SKROW "rrqk.....K.....k.....k.....K.....kqrr"
    SKROW "rrqk.....k.....k.....k.....k.....kqrr"
    SKROW "rrqkC.C.CkC.C.Ck.....kC.C.CkC.C.Ckqrr"
    SKROW "rrqkkkkkkKkkkkkk.....kkkkkkKkkkkkkqrr"
    SKROW "rrq......k.................k......qrr"
    SKROW "rrq......k.................k......qrr"
    SKROW "rrq......K.................K......qrr"
    SKROW "rrq......k.................k......qrr"
    SKROW "rrq......k.................k......qrr"
    SKROW "rrq......K.................K......qrr"
    SKROW "rrq......k.................k......qrr"
    SKROW "rrq......k.................k......qrr"
    SKROW "rrq......K......uuuuu......K......qrr"
    SKROW "rrq......k.....uuuuuuu.....k......qrr"
    SKROW "rrq......k....uuuwwwuuu....k......qrr"
    SKROW "rrq......K...uuuwwwwwuuu...K......qrr"
    SKROW "rrq......k...uuwwrrrwwuu...k......qrr"
    SKROW "rrq......k...uuwwrrrwwuu...k......qrr"
    SKROW "rrq......K...uuwwrrrwwuu...K......qrr"
    SKROW "rrq......k...uuuwwwwwuuu...k......qrr"
    SKROW "rrq......k....uuuwwwuuu....k......qrr"
    SKROW "rrq......K.....uuuuuuu.....K......qrr"
    SKROW "qqqqqqqqqqqqqqqquuuuuqqqqqqqqqqqqqqqq"
    SKROW "rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr"
    SKROW "RRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR"
    SKROWS_END
    align 8
    SKBMP pl_wing_l_top, pl_wing_l_top_rows, 37, 30, pl_pal
    ; pl_wing_l_bottom (37x30): pl_wing_l BOTTOM
    SKROWS pl_wing_l_bottom_rows, 37, 30
    SKROW "RRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR"
    SKROW "rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr"
    SKROW "qqqqqqqqqqqqqqqquuuuuqqqqqqqqqqqqqqqq"
    SKROW "rrq......K.....uuuuuuu.....K......qrr"
    SKROW "rrq......k....uuuwwwuuu....k......qrr"
    SKROW "rrq......k...uuuwwwwwuuu...k......qrr"
    SKROW "rrq......K...uuwwrrrwwuu...K......qrr"
    SKROW "rrq......k...uuwwrrrwwuu...k......qrr"
    SKROW "rrq......k...uuwwrrrwwuu...k......qrr"
    SKROW "rrq......K...uuuwwwwwuuu...K......qrr"
    SKROW "rrq......k....uuuwwwuuu....k......qrr"
    SKROW "rrq......k.....uuuuuuu.....k......qrr"
    SKROW "rrq......K......uuuuu......K......qrr"
    SKROW "rrq......k.................k......qrr"
    SKROW "rrq......k.................k......qrr"
    SKROW "rrq......K.................K......qrr"
    SKROW "rrq......k.................k......qrr"
    SKROW "rrq......k.................k......qrr"
    SKROW "rrq......K.................K......qrr"
    SKROW "rrq......k.................k......qrr"
    SKROW "rrq......k.................k......qrr"
    SKROW "rrqkkkkkkKkkkkkk.....kkkkkkKkkkkkkqrr"
    SKROW "rrqkC.C.CkC.C.Ck.....kC.C.CkC.C.Ckqrr"
    SKROW "rrqk.....k.....k.....k.....k.....kqrr"
    SKROW "rrqk.....K.....k.....k.....K.....kqrr"
    SKROW "rrqk.....k.....k.....k.....k.....kqrr"
    SKROW "rrqk.....k.....k.....k.....k.....kqrr"
    SKROW "rrqk.....K.....k.....k.....K.....kqrr"
    SKROW "rrqk.....k.....k.....k.....k.....kqrr"
    SKROW "rrqkkkkkkkkkkkkk.....kkkkkkkkkkkkkqrr"
    SKROWS_END
    align 8
    SKBMP pl_wing_l_bottom, pl_wing_l_bottom_rows, 37, 30, pl_pal
    ; pl_wing_l_back (37x4): pl_wing_l BACK
    SKROWS pl_wing_l_back_rows, 37, 4
    SKROW "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC"
    SKROW "rrkk...........k.....k...........kkrr"
    SKROW "rrkk...........k.....k...........kkrr"
    SKROW "kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk"
    SKROWS_END
    align 8
    SKBMP pl_wing_l_back, pl_wing_l_back_rows, 37, 4, pl_pal
    ; pl_wing_l_front (37x4): pl_wing_l FRONT
    SKROWS pl_wing_l_front_rows, 37, 4
    SKROW "RRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR"
    SKROW "RrrRrrRrrRrrRrrRrrRrrRrrRrrRrrRrrRrrR"
    SKROW "rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr"
    SKROW "qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"
    SKROWS_END
    align 8
    SKBMP pl_wing_l_front, pl_wing_l_front_rows, 37, 4, pl_pal
    ; pl_tail_l_right (18x3): pl_tail_l RIGHT, pl_tail_l LEFT
    SKROWS pl_tail_l_right_rows, 18, 3
    SKROW "RRRRRRRRRRRRRRRRRR"
    SKROW "rrrrrrrrrrrrrrrrrr"
    SKROW "rrrrrrrrrrrrrrrrrr"
    SKROWS_END
    align 8
    SKBMP pl_tail_l_right, pl_tail_l_right_rows, 18, 3, pl_pal
    ; pl_tail_l_top (27x18): pl_tail_l TOP
    SKROWS pl_tail_l_top_rows, 27, 18
    SKROW "rrqkkkkkkkkkkkkkkkkkkkkkqrr"
    SKROW "rrq..........k..........qrr"
    SKROW "rrq..........k..........qrr"
    SKROW "rrq..........k..........qrr"
    SKROW "rrq..........k..........qrr"
    SKROW "rrq..........k..........qrr"
    SKROW "rrq..........k..........qrr"
    SKROW "rrqkkkkkkkkkkkkkkkkkkkkkqrr"
    SKROW "rrq....K...........K....qrr"
    SKROW "rrq....k...........k....qrr"
    SKROW "rrq....k...........k....qrr"
    SKROW "rrq....K...........K....qrr"
    SKROW "rrq....k...........k....qrr"
    SKROW "rrq....k...........k....qrr"
    SKROW "rrq....K...........K....qrr"
    SKROW "qqqqqqqqqqqqqqqqqqqqqqqqqqq"
    SKROW "rrrrrrrrrrrrrrrrrrrrrrrrrrr"
    SKROW "RRRRRRRRRRRRRRRRRRRRRRRRRRR"
    SKROWS_END
    align 8
    SKBMP pl_tail_l_top, pl_tail_l_top_rows, 27, 18, pl_pal
    ; pl_tail_l_bottom (27x18): pl_tail_l BOTTOM
    SKROWS pl_tail_l_bottom_rows, 27, 18
    SKROW "RRRRRRRRRRRRRRRRRRRRRRRRRRR"
    SKROW "rrrrrrrrrrrrrrrrrrrrrrrrrrr"
    SKROW "qqqqqqqqqqqqqqqqqqqqqqqqqqq"
    SKROW "rrq....K...........K....qrr"
    SKROW "rrq....k...........k....qrr"
    SKROW "rrq....k...........k....qrr"
    SKROW "rrq....K...........K....qrr"
    SKROW "rrq....k...........k....qrr"
    SKROW "rrq....k...........k....qrr"
    SKROW "rrq....K...........K....qrr"
    SKROW "rrqkkkkkkkkkkkkkkkkkkkkkqrr"
    SKROW "rrq..........k..........qrr"
    SKROW "rrq..........k..........qrr"
    SKROW "rrq..........k..........qrr"
    SKROW "rrq..........k..........qrr"
    SKROW "rrq..........k..........qrr"
    SKROW "rrq..........k..........qrr"
    SKROW "rrqkkkkkkkkkkkkkkkkkkkkkqrr"
    SKROWS_END
    align 8
    SKBMP pl_tail_l_bottom, pl_tail_l_bottom_rows, 27, 18, pl_pal
    ; pl_tail_l_back (27x3): pl_tail_l BACK
    SKROWS pl_tail_l_back_rows, 27, 3
    SKROW "CCCCCCCCCCCCCCCCCCCCCCCCCCC"
    SKROW "..k..........k..........k.."
    SKROW "kkkkkkkkkkkkkkkkkkkkkkkkkkk"
    SKROWS_END
    align 8
    SKBMP pl_tail_l_back, pl_tail_l_back_rows, 27, 3, pl_pal
    ; pl_tail_l_front (27x3): pl_tail_l FRONT
    SKROWS pl_tail_l_front_rows, 27, 3
    SKROW "RRRRRRRRRRRRRRRRRRRRRRRRRRR"
    SKROW "rrrrrrrrrrrrrrrrrrrrrrrrrrr"
    SKROW "qqqqqqqqqqqqqqqqqqqqqqqqqqq"
    SKROWS_END
    align 8
    SKBMP pl_tail_l_front, pl_tail_l_front_rows, 27, 3, pl_pal
    ; pl_fin_right (6x19): pl_fin RIGHT
    SKROWS pl_fin_right_rows, 6, 19
    SKROW "rrrrrr"
    SKROW "qqqqqq"
    SKROW "q....."
    SKROW "q....."
    SKROW "rrwwuu"
    SKROW "rrwwuu"
    SKROW "rrwwUU"
    SKROW "rrwwuu"
    SKROW "rrwwuu"
    SKROW "rrwwuu"
    SKROW "rrwwuu"
    SKROW "rrwwUU"
    SKROW "rrwwuu"
    SKROW "rrwwuu"
    SKROW "q....."
    SKROW "q....."
    SKROW "q....."
    SKROW "......"
    SKROW "......"
    SKROWS_END
    align 8
    SKBMP pl_fin_right, pl_fin_right_rows, 6, 19, pl_pal
    ; pl_fin_left (6x19): pl_fin LEFT
    SKROWS pl_fin_left_rows, 6, 19
    SKROW "rrrrrr"
    SKROW "qqqqqq"
    SKROW ".....q"
    SKROW ".....q"
    SKROW "uuwwrr"
    SKROW "uuwwrr"
    SKROW "UUwwrr"
    SKROW "uuwwrr"
    SKROW "uuwwrr"
    SKROW "uuwwrr"
    SKROW "uuwwrr"
    SKROW "UUwwrr"
    SKROW "uuwwrr"
    SKROW "uuwwrr"
    SKROW ".....q"
    SKROW ".....q"
    SKROW ".....q"
    SKROW "......"
    SKROW "......"
    SKROWS_END
    align 8
    SKBMP pl_fin_left, pl_fin_left_rows, 6, 19, pl_pal
    ; pl_fin_top (4x6): pl_fin TOP
    SKROWS pl_fin_top_rows, 4, 6
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROWS_END
    align 8
    SKBMP pl_fin_top, pl_fin_top_rows, 4, 6, pl_pal
    ; pl_fin_back (4x19): pl_fin BACK
    SKROWS pl_fin_back_rows, 4, 19
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "qqqq"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "qqqq"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "qqqq"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROWS_END
    align 8
    SKBMP pl_fin_back, pl_fin_back_rows, 4, 19, pl_pal
    ; pl_fin_front (4x19): pl_fin FRONT
    SKROWS pl_fin_front_rows, 4, 19
    SKROW "RRRR"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "RRRR"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "RRRR"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "RRRR"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "RRRR"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "RRRR"
    SKROW "rrrr"
    SKROW "rrrr"
    SKROW "RRRR"
    SKROWS_END
    align 8
    SKBMP pl_fin_front, pl_fin_front_rows, 4, 19, pl_pal
    ; pl_pod_l_right (10x5): pl_pod_l RIGHT, pl_pod_l LEFT
    SKROWS pl_pod_l_right_rows, 10, 5
    SKROW "SSSSSSSSSS"
    SKROW "rrrrrrrrrr"
    SKROW ".........."
    SKROW ".S..S..S.."
    SKROW "ZZZZZZZZZZ"
    SKROWS_END
    align 8
    SKBMP pl_pod_l_right, pl_pod_l_right_rows, 10, 5, pl_pal
    ; pl_pod_l_top (16x10): pl_pod_l TOP
    SKROWS pl_pod_l_top_rows, 16, 10
    SKROW "SSSSSSSSSSSSSSSS"
    SKROW "S....zzzzzz....s"
    SKROW "S.g.zzsssszZ.g.s"
    SKROW "S...zssssssZ...s"
    SKROW "S...zsszzssZ...s"
    SKROW "S...zsszzssZ...s"
    SKROW "S...zssssssZ...s"
    SKROW "S.g.zzssssZZ.g.s"
    SKROW "S....ZZZZZZ....s"
    SKROW "Ssssssssssssssss"
    SKROWS_END
    align 8
    SKBMP pl_pod_l_top, pl_pod_l_top_rows, 16, 10, pl_pal
    ; pl_pod_l_back (16x5): pl_pod_l BACK, pl_pod_l FRONT
    SKROWS pl_pod_l_back_rows, 16, 5
    SKROW "SSSSSSSSSSSSSSSS"
    SKROW "rrrrrrrrrrrrrrrr"
    SKROW "................"
    SKROW ".S..S..S..S..S.."
    SKROW "ZZZZZZZZZZZZZZZZ"
    SKROWS_END
    align 8
    SKBMP pl_pod_l_back, pl_pod_l_back_rows, 16, 5, pl_pal
    ; pl_pod_t_right (11x6): pl_pod_t RIGHT, pl_pod_t LEFT
    SKROWS pl_pod_t_right_rows, 11, 6
    SKROW "SSSSSSSSSSS"
    SKROW "rrrrrrrrrrr"
    SKROW "..........."
    SKROW ".S..S..S..S"
    SKROW "..........."
    SKROW "ZZZZZZZZZZZ"
    SKROWS_END
    align 8
    SKBMP pl_pod_t_right, pl_pod_t_right_rows, 11, 6, pl_pal
    ; pl_pod_t_top (16x11): pl_pod_t TOP
    SKROWS pl_pod_t_top_rows, 16, 11
    SKROW "SSSSSSSSSSSSSSSS"
    SKROW "S.....zzzz.....s"
    SKROW "S.g..zzzzzz..g.s"
    SKROW "S...zzssssZZ...s"
    SKROW "S...zsszzssZ...s"
    SKROW "S...zsszzssZ...s"
    SKROW "S...zsszzssZ...s"
    SKROW "S...zzssssZZ...s"
    SKROW "S.g..ZZZZZZ..g.s"
    SKROW "S.....ZZZZ.....s"
    SKROW "Ssssssssssssssss"
    SKROWS_END
    align 8
    SKBMP pl_pod_t_top, pl_pod_t_top_rows, 16, 11, pl_pal
    ; pl_pod_t_back (16x6): pl_pod_t BACK, pl_pod_t FRONT
    SKROWS pl_pod_t_back_rows, 16, 6
    SKROW "SSSSSSSSSSSSSSSS"
    SKROW "rrrrrrrrrrrrrrrr"
    SKROW "................"
    SKROW ".S..S..S..S..S.."
    SKROW "................"
    SKROW "ZZZZZZZZZZZZZZZZ"
    SKROWS_END
    align 8
    SKBMP pl_pod_t_back, pl_pod_t_back_rows, 16, 6, pl_pal
    ; pl_tyre_a_l_right (6x8): pl_tyre_a_l RIGHT, pl_tyre_a_l LEFT
    SKROWS pl_tyre_a_l_right_rows, 6, 8
    SKROW "bbbbbb"
    SKROW "bzzzzb"
    SKROW "zSSSSz"
    SKROW "zSggSz"
    SKROW "zsggsz"
    SKROW "zssssz"
    SKROW "bzzzzb"
    SKROW "bbbbbb"
    SKROWS_END
    align 8
    SKBMP pl_tyre_a_l_right, pl_tyre_a_l_right_rows, 6, 8, pl_pal
    ; pl_tyre_a_l_top (6x6): pl_tyre_a_l TOP, pl_tyre_a_l BOTTOM
    SKROWS pl_tyre_a_l_top_rows, 6, 6
    SKROW "dddddd"
    SKROW "......"
    SKROW "dddddd"
    SKROW "......"
    SKROW "dddddd"
    SKROW "......"
    SKROWS_END
    align 8
    SKBMP pl_tyre_a_l_top, pl_tyre_a_l_top_rows, 6, 6, pl_pal
    ; pl_tyre_b_l_right (10x4): pl_tyre_b_l RIGHT, pl_tyre_b_l LEFT
    SKROWS pl_tyre_b_l_right_rows, 10, 4
    SKROW "DbzSSSSzbD"
    SKROW "bbzSggSzbb"
    SKROW "bbzsggszbb"
    SKROW "DbzsssszbD"
    SKROWS_END
    align 8
    SKBMP pl_tyre_b_l_right, pl_tyre_b_l_right_rows, 10, 4, pl_pal
    ; pl_tyre_b_l_top (6x10): pl_tyre_b_l TOP, pl_tyre_b_l BOTTOM
    SKROWS pl_tyre_b_l_top_rows, 6, 10
    SKROW "dddddd"
    SKROW "......"
    SKROW "dddddd"
    SKROW "......"
    SKROW "dddddd"
    SKROW "......"
    SKROW "dddddd"
    SKROW "......"
    SKROW "dddddd"
    SKROW "......"
    SKROWS_END
    align 8
    SKBMP pl_tyre_b_l_top, pl_tyre_b_l_top_rows, 6, 10, pl_pal
    ; pl_hub_l_right (2x2): pl_hub_l RIGHT, pl_hub_l LEFT
    SKROWS pl_hub_l_right_rows, 2, 2
    SKROW "G."
    SKROW "oo"
    SKROWS_END
    align 8
    SKBMP pl_hub_l_right, pl_hub_l_right_rows, 2, 2, pl_pal
    ; pl_axle_right (2x2): pl_axle RIGHT, pl_axle LEFT
    SKROWS pl_axle_right_rows, 2, 2
    SKROW "gg"
    SKROW "gg"
    SKROWS_END
    align 8
    SKBMP pl_axle_right, pl_axle_right_rows, 2, 2, pl_pal
    ; pl_axle_top (22x2): pl_axle TOP
    SKROWS pl_axle_top_rows, 22, 2
    SKROW "SSSSSSSSSSSSSSSSSSSSSS"
    SKROW "ssssssssssssssssssssss"
    SKROWS_END
    align 8
    SKBMP pl_axle_top, pl_axle_top_rows, 22, 2, pl_pal
    ; pl_axle_bottom (22x2): pl_axle BOTTOM, pl_axle BACK, pl_axle FRONT
    SKROWS pl_axle_bottom_rows, 22, 2
    SKROW "ssssssssssssssssssssss"
    SKROW "zzzzzzzzzzzzzzzzzzzzzz"
    SKROWS_END
    align 8
    SKBMP pl_axle_bottom, pl_axle_bottom_rows, 22, 2, pl_pal
    ; pl_strut_l_right (2x5): pl_strut_l RIGHT, pl_strut_l LEFT, pl_strut_l BACK, ...
    SKROWS pl_strut_l_right_rows, 2, 5
    SKROW "sz"
    SKROW "sz"
    SKROW "sz"
    SKROW "sz"
    SKROW "sz"
    SKROWS_END
    align 8
    SKBMP pl_strut_l_right, pl_strut_l_right_rows, 2, 5, pl_pal
    ; pl_strut_l_top (2x2): pl_strut_l TOP, pl_strut_l BOTTOM, pl_tailstrut TOP, ...
    SKROWS pl_strut_l_top_rows, 2, 2
    SKROW "sz"
    SKROW "sz"
    SKROWS_END
    align 8
    SKBMP pl_strut_l_top, pl_strut_l_top_rows, 2, 2, pl_pal
    ; pl_tailwheel_right (5x6): pl_tailwheel RIGHT, pl_tailwheel LEFT
    SKROWS pl_tailwheel_right_rows, 5, 6
    SKROW "DbbbD"
    SKROW "bzzzb"
    SKROW "bzszb"
    SKROW "bzszb"
    SKROW "bzzzb"
    SKROW "DbbbD"
    SKROWS_END
    align 8
    SKBMP pl_tailwheel_right, pl_tailwheel_right_rows, 5, 6, pl_pal
    ; pl_tailwheel_top (4x5): pl_tailwheel TOP, pl_tailwheel BOTTOM
    SKROWS pl_tailwheel_top_rows, 4, 5
    SKROW "dddd"
    SKROW "...."
    SKROW "dddd"
    SKROW "...."
    SKROW "dddd"
    SKROWS_END
    align 8
    SKBMP pl_tailwheel_top, pl_tailwheel_top_rows, 4, 5, pl_pal
    ; pl_nav_l_right (4x2): pl_nav_l RIGHT, pl_nav_l LEFT
    SKROWS pl_nav_l_right_rows, 4, 2
    SKROW "Ffff"
    SKROW "hhhh"
    SKROWS_END
    align 8
    SKBMP pl_nav_l_right, pl_nav_l_right_rows, 4, 2, pl_pal
    ; pl_nav_l_top (2x4): pl_nav_l TOP, pl_nav_l BOTTOM
    SKROWS pl_nav_l_top_rows, 2, 4
    SKROW "Ff"
    SKROW "ff"
    SKROW "ff"
    SKROW "hh"
    SKROWS_END
    align 8
    SKBMP pl_nav_l_top, pl_nav_l_top_rows, 2, 4, pl_pal
    ; pl_nav_l_back (2x2): pl_nav_l BACK, pl_nav_l FRONT
    SKROWS pl_nav_l_back_rows, 2, 2
    SKROW "Ff"
    SKROW "hh"
    SKROWS_END
    align 8
    SKBMP pl_nav_l_back, pl_nav_l_back_rows, 2, 2, pl_pal
    ; pl_nav_r_right (4x2): pl_nav_r RIGHT, pl_nav_r LEFT
    SKROWS pl_nav_r_right_rows, 4, 2
    SKROW "Nnnn"
    SKROW "eeee"
    SKROWS_END
    align 8
    SKBMP pl_nav_r_right, pl_nav_r_right_rows, 4, 2, pl_pal
    ; pl_nav_r_top (2x4): pl_nav_r TOP, pl_nav_r BOTTOM
    SKROWS pl_nav_r_top_rows, 2, 4
    SKROW "Nn"
    SKROW "nn"
    SKROW "nn"
    SKROW "ee"
    SKROWS_END
    align 8
    SKBMP pl_nav_r_top, pl_nav_r_top_rows, 2, 4, pl_pal
    ; pl_nav_r_back (2x2): pl_nav_r BACK, pl_nav_r FRONT
    SKROWS pl_nav_r_back_rows, 2, 2
    SKROW "Nn"
    SKROW "ee"
    SKROWS_END
    align 8
    SKBMP pl_nav_r_back, pl_nav_r_back_rows, 2, 2, pl_pal
    ; pl_pitot_right (6x1): pl_pitot RIGHT, pl_pitot LEFT
    SKROWS pl_pitot_right_rows, 6, 1
    SKROW "zzzzzz"
    SKROWS_END
    align 8
    SKBMP pl_pitot_right, pl_pitot_right_rows, 6, 1, pl_pal
    ; pl_pitot_top (1x6): pl_pitot TOP
    SKROWS pl_pitot_top_rows, 1, 6
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROW "S"
    SKROWS_END
    align 8
    SKBMP pl_pitot_top, pl_pitot_top_rows, 1, 6, pl_pal
    ; pl_pitot_bottom (1x6): pl_pitot BOTTOM
    SKROWS pl_pitot_bottom_rows, 1, 6
    SKROW "z"
    SKROW "z"
    SKROW "z"
    SKROW "z"
    SKROW "z"
    SKROW "z"
    SKROWS_END
    align 8
    SKBMP pl_pitot_bottom, pl_pitot_bottom_rows, 1, 6, pl_pal
    ; pl_pitot_back (1x1): pl_pitot BACK, pl_pitot FRONT
    SKROWS pl_pitot_back_rows, 1, 1
    SKROW "z"
    SKROWS_END
    align 8
    SKBMP pl_pitot_back, pl_pitot_back_rows, 1, 1, pl_pal

section .data
SKMODEL_BEGIN m_plane, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART pl_tail_l, -27, 2, 27, 27, 3, 18, 0, 0             ; tailplane half (the other shares its skin)
    PART pl_tyre_b_l, -17, -17, -26, 6, 4, 10, 0, 0         ; tyre, wide half
    PART pl_rim_l, -11, 11, -9, 2, 3, 18, 0, 0              ; leather cockpit rim, left (the right shares its skin)
    PART_AS pl_tyre_b_r, pl_tyre_b_l, 11, -17, -26, 0, 0
    PART pl_ring_v, -8, -10, -47, 16, 20, 2, 4, SKPF_CUTOUT ; nose ring, tall half (grown 1/2 texel: no z-fight)
    PART pl_rim_b, -9, 11, 7, 18, 5, 3, 0, 0                ; headrest fairing
    PART pl_stub_a_l, -13, -6, -44, 3, 3, 3, 0, 0           ; exhaust stubs, two a side (one skin)
    PART pl_nav_l, -50, 3, -9, 2, 2, 4, 0, 0                ; red navigation lamp on the left tip
    PART pl_pitot, -35, 3, -26, 1, 1, 6, 0, 0               ; pitot tube on the left wing
    PART pl_axle, -11, -16, -22, 22, 2, 2, 0, 0             ; axle
    PART pl_rim_f, -9, 11, -9, 18, 4, 3, 0, 0               ; instrument coaming
    PART pl_strut_l, -7, -14, -22, 2, 5, 2, 0, 0            ; gear strut (the other shares its skin)
    PART pl_tailstrut, -1, -10, 33, 2, 5, 2, 0, 0           ; tail wheel leg
    PART pl_wing_l, -48, 2, -20, 37, 4, 30, 0, 0            ; wing, left; the right half shares its skin
    PART pl_cowl, -10, -9, -46, 20, 18, 8, 0, 0             ; engine cowl, gunmetal, between the nose ring and the bay
    PART pl_hub_l, -18, -16, -22, 1, 2, 2, 0, 0             ; hub cap
    PART pl_fus_c, -9, -7, 10, 18, 16, 12, 0, 0             ; rear fuselage
    PART_AS pl_stub_b_r, pl_stub_a_l, 10, -6, -40, 0, 0
    PART pl_fus_b, -11, -9, -20, 22, 20, 30, 0, 0           ; cockpit bay: its top is the seat level, y 11
    PART pl_fin, -2, 3, 28, 4, 19, 6, 0, 0                  ; fin with a tricolour flash, clear of the tail gunner
    PART_AS pl_rim_r, pl_rim_l, 9, 11, -9, 0, 0
    PART pl_fus_d, -6, -5, 22, 12, 12, 13, 0, 0             ; tail cone
    PART pl_fus_a, -11, -9, -38, 22, 19, 18, 0, 0           ; nose bay
    PART pl_tyre_a_l, -17, -19, -24, 6, 8, 6, 4, 0          ; tyre, tall half (the octagon is two crossed boxes)
    PART_AS pl_strut_r, pl_strut_l, 5, -14, -22, 0, 0
    PART pl_nav_r, 48, 3, -9, 2, 2, 4, 0, 0                 ; green navigation lamp on the right tip
    PART_AS pl_tyre_a_r, pl_tyre_a_l, 11, -19, -24, 4, 0
    PART_AS pl_stub_a_r, pl_stub_a_l, 10, -6, -44, 0, 0
    PART_AS pl_wing_r, pl_wing_l, 11, 2, -20, 0, 0
    PART pl_pod_l, -37, 6, -8, 16, 5, 10, 0, 0              ; gunner stand on the wing (the right one shares its skin)
    PART pl_pod_t, -8, 5, 33, 16, 6, 11, 0, 0               ; tail gunner stand
    PART pl_spine, -4, 9, 10, 8, 3, 12, 0, 0                ; dorsal spine fairing behind the headrest
    PART pl_seatback, -5, 11, 6, 10, 8, 2, 0, 0             ; seat back behind the open cockpit
    PART pl_ring_h, -11, -7, -47, 22, 14, 2, 0, SKPF_CUTOUT ; nose ring, wide half (octagon with the tall half)
    PART_AS pl_tail_r, pl_tail_l, 0, 2, 27, 0, 0
    PART_AS pl_pod_r, pl_pod_l, 21, 6, -8, 0, 0
    PART_AS pl_hub_r, pl_hub_l, 17, -16, -22, 0, 0
    PART pl_screen, -9, 15, -9, 18, 11, 1, 0, SKPF_CUTOUT   ; windscreen frame: the glass is a hole
    PART_AS pl_stub_b_l, pl_stub_a_l, -13, -6, -40, 0, 0
    PART pl_tailwheel, -2, -16, 32, 4, 6, 5, 0, 0           ; tail wheel
SKMODEL_PAINT
    ; --- pl_cowl
    SK_FILL pl_cowl, SKM_ALL, AC_IRON_3, 0
    SK_BMP pl_cowl, SKF_RIGHT, 0, 0, pl_cowl_right
    SK_BMP pl_cowl, SKF_LEFT, 0, 0, pl_cowl_left
    SK_BMP pl_cowl, SKF_TOP, 0, 0, pl_cowl_top
    SK_BMP pl_cowl, SKF_BOTTOM, 0, 0, pl_cowl_bottom
    SK_BMP pl_cowl, SKF_BACK, 0, 0, pl_cowl_back
    SK_BMP pl_cowl, SKF_FRONT, 0, 0, pl_cowl_front
    SK_GRAD pl_cowl, SKM_SIDES, 272, 224
    ; --- pl_ring_h
    SK_FILL pl_ring_h, SKM_ALL, AC_IRON_2, 0
    SK_BMP pl_ring_h, SKF_RIGHT, 0, 0, pl_ring_h_right
    SK_BMP pl_ring_h, SKF_LEFT, 0, 0, pl_ring_h_left
    SK_BMP pl_ring_h, SKF_TOP, 0, 0, pl_ring_h_top
    SK_BMP pl_ring_h, SKF_BOTTOM, 0, 0, pl_ring_h_bottom
    SK_BMP pl_ring_h, SKF_BACK, 0, 0, pl_ring_h_back
    SK_BMP pl_ring_h, SKF_FRONT, 0, 0, pl_ring_h_front
    SK_GRAD pl_ring_h, SKM_SIDES, 272, 224
    ; --- pl_ring_v
    SK_FILL pl_ring_v, SKM_ALL, AC_IRON_2, 0
    SK_BMP pl_ring_v, SKF_RIGHT, 0, 0, pl_ring_v_right
    SK_BMP pl_ring_v, SKF_LEFT, 0, 0, pl_ring_v_left
    SK_BMP pl_ring_v, SKF_TOP, 0, 0, pl_ring_v_top
    SK_BMP pl_ring_v, SKF_BOTTOM, 0, 0, pl_ring_v_bottom
    SK_BMP pl_ring_v, SKF_BACK, 0, 0, pl_ring_v_back
    SK_BMP pl_ring_v, SKF_FRONT, 0, 0, pl_ring_v_front
    SK_GRAD pl_ring_v, SKM_SIDES, 272, 224
    ; --- pl_stub_a_l
    SK_FILL pl_stub_a_l, SKM_ALL, AC_IRON_3, 0
    SK_BMP pl_stub_a_l, SKF_RIGHT, 0, 0, pl_stub_a_l_right
    SK_BMP pl_stub_a_l, SKF_LEFT, 0, 0, pl_stub_a_l_right
    SK_BMP pl_stub_a_l, SKF_TOP, 0, 0, pl_stub_a_l_top
    SK_BMP pl_stub_a_l, SKF_BOTTOM, 0, 0, pl_stub_a_l_bottom
    SK_BMP pl_stub_a_l, SKF_BACK, 0, 0, pl_stub_a_l_back
    SK_BMP pl_stub_a_l, SKF_FRONT, 0, 0, pl_stub_a_l_front
    SK_GRAD pl_stub_a_l, SKM_SIDES, 272, 224
    ; --- pl_fus_a
    SK_FILL pl_fus_a, SKM_ALL, PL_RED_2, 7
    SK_BMP pl_fus_a, SKF_RIGHT, 0, 0, pl_fus_a_right
    SK_BMP pl_fus_a, SKF_LEFT, 0, 0, pl_fus_a_left
    SK_BMP pl_fus_a, SKF_TOP, 0, 0, pl_fus_a_top
    SK_BMP pl_fus_a, SKF_BOTTOM, 0, 0, pl_fus_a_bottom
    SK_BMP pl_fus_a, SKF_FRONT, 0, 0, pl_fus_a_front
    SK_GRAD pl_fus_a, SKM_SIDES, 272, 224
    ; --- pl_fus_b
    SK_FILL pl_fus_b, SKM_ALL, PL_RED_2, 7
    SK_BMP pl_fus_b, SKF_RIGHT, 0, 0, pl_fus_b_right
    SK_BMP pl_fus_b, SKF_LEFT, 0, 0, pl_fus_b_left
    SK_BMP pl_fus_b, SKF_TOP, 0, 0, pl_fus_b_top
    SK_BMP pl_fus_b, SKF_BOTTOM, 0, 0, pl_fus_b_bottom
    SK_BMP pl_fus_b, SKF_BACK, 0, 0, pl_fus_b_back
    SK_BMP pl_fus_b, SKF_FRONT, 0, 0, pl_fus_b_front
    SK_GRAD pl_fus_b, SKM_SIDES, 272, 224
    ; --- pl_fus_c
    SK_FILL pl_fus_c, SKM_ALL, PL_RED_2, 7
    SK_BMP pl_fus_c, SKF_RIGHT, 0, 0, pl_fus_c_right
    SK_BMP pl_fus_c, SKF_LEFT, 0, 0, pl_fus_c_left
    SK_BMP pl_fus_c, SKF_TOP, 0, 0, pl_fus_c_top
    SK_BMP pl_fus_c, SKF_BOTTOM, 0, 0, pl_fus_c_bottom
    SK_BMP pl_fus_c, SKF_BACK, 0, 0, pl_fus_c_back
    SK_BMP pl_fus_c, SKF_FRONT, 0, 0, pl_fus_c_front
    SK_GRAD pl_fus_c, SKM_SIDES, 272, 224
    ; --- pl_fus_d
    SK_FILL pl_fus_d, SKM_ALL, PL_RED_2, 7
    SK_BMP pl_fus_d, SKF_RIGHT, 0, 0, pl_fus_d_right
    SK_BMP pl_fus_d, SKF_LEFT, 0, 0, pl_fus_d_left
    SK_BMP pl_fus_d, SKF_TOP, 0, 0, pl_fus_d_top
    SK_BMP pl_fus_d, SKF_BOTTOM, 0, 0, pl_fus_d_bottom
    SK_BMP pl_fus_d, SKF_BACK, 0, 0, pl_fus_d_back
    SK_BMP pl_fus_d, SKF_FRONT, 0, 0, pl_fus_d_front
    SK_GRAD pl_fus_d, SKM_SIDES, 272, 224
    ; --- pl_spine
    SK_FILL pl_spine, SKM_ALL, PL_RED_2, 7
    SK_BMP pl_spine, SKF_RIGHT, 0, 0, pl_spine_right
    SK_BMP pl_spine, SKF_LEFT, 0, 0, pl_spine_left
    SK_BMP pl_spine, SKF_TOP, 0, 0, pl_spine_top
    SK_BMP pl_spine, SKF_BACK, 0, 0, pl_spine_back
    SK_BMP pl_spine, SKF_FRONT, 0, 0, pl_spine_back
    SK_GRAD pl_spine, SKM_SIDES, 272, 224
    ; --- pl_rim_l
    SK_FILL pl_rim_l, SKM_ALL, AC_LEATHER_2, 15
    SK_BMP pl_rim_l, SKF_RIGHT, 0, 0, pl_rim_l_right
    SK_BMP pl_rim_l, SKF_LEFT, 0, 0, pl_rim_l_right
    SK_BMP pl_rim_l, SKF_TOP, 0, 0, pl_rim_l_top
    SK_BMP pl_rim_l, SKF_BACK, 0, 0, pl_rim_l_back
    SK_BMP pl_rim_l, SKF_FRONT, 0, 0, pl_rim_l_back
    SK_GRAD pl_rim_l, SKM_SIDES, 272, 224
    ; --- pl_rim_f
    SK_FILL pl_rim_f, SKM_ALL, AC_LEATHER_2, 15
    SK_BMP pl_rim_f, SKF_RIGHT, 0, 0, pl_rim_f_right
    SK_BMP pl_rim_f, SKF_LEFT, 0, 0, pl_rim_f_right
    SK_BMP pl_rim_f, SKF_TOP, 0, 0, pl_rim_f_top
    SK_BMP pl_rim_f, SKF_BACK, 0, 0, pl_rim_f_back
    SK_BMP pl_rim_f, SKF_FRONT, 0, 0, pl_rim_f_front
    SK_GRAD pl_rim_f, SKM_SIDES, 272, 224
    ; --- pl_rim_b
    SK_FILL pl_rim_b, SKM_ALL, AC_LEATHER_2, 15
    SK_BMP pl_rim_b, SKF_TOP, 0, 0, pl_rim_b_top
    SK_BMP pl_rim_b, SKF_BACK, 0, 0, pl_rim_b_back
    SK_BMP pl_rim_b, SKF_FRONT, 0, 0, pl_rim_b_front
    SK_GRAD pl_rim_b, SKM_SIDES, 272, 224
    ; --- pl_screen
    SK_FILL pl_screen, SKM_ALL, AC_IRON_2, 0
    SK_BMP pl_screen, SKF_RIGHT, 0, 0, pl_screen_right
    SK_BMP pl_screen, SKF_LEFT, 0, 0, pl_screen_right
    SK_BMP pl_screen, SKF_TOP, 0, 0, pl_screen_top
    SK_BMP pl_screen, SKF_BOTTOM, 0, 0, pl_screen_bottom
    SK_BMP pl_screen, SKF_BACK, 0, 0, pl_screen_back
    SK_BMP pl_screen, SKF_FRONT, 0, 0, pl_screen_back
    SK_GRAD pl_screen, SKM_SIDES, 272, 224
    ; --- pl_seatback
    SK_FILL pl_seatback, SKM_ALL, AC_LEATHER_2, 15
    SK_BMP pl_seatback, SKF_TOP, 0, 0, pl_seatback_top
    SK_BMP pl_seatback, SKF_BACK, 0, 0, pl_seatback_back
    SK_BMP pl_seatback, SKF_FRONT, 0, 0, pl_seatback_front
    SK_GRAD pl_seatback, SKM_SIDES, 272, 224
    ; --- pl_wing_l
    SK_FILL pl_wing_l, SKM_ALL, PL_CREAM_2, 15
    SK_BMP pl_wing_l, SKF_RIGHT, 0, 0, pl_wing_l_right
    SK_BMP pl_wing_l, SKF_LEFT, 0, 0, pl_wing_l_right
    SK_BMP pl_wing_l, SKF_TOP, 0, 0, pl_wing_l_top
    SK_BMP pl_wing_l, SKF_BOTTOM, 0, 0, pl_wing_l_bottom
    SK_BMP pl_wing_l, SKF_BACK, 0, 0, pl_wing_l_back
    SK_BMP pl_wing_l, SKF_FRONT, 0, 0, pl_wing_l_front
    SK_GRAD pl_wing_l, SKM_SIDES, 272, 224
    ; --- pl_tail_l
    SK_FILL pl_tail_l, SKM_ALL, PL_CREAM_2, 15
    SK_BMP pl_tail_l, SKF_RIGHT, 0, 0, pl_tail_l_right
    SK_BMP pl_tail_l, SKF_LEFT, 0, 0, pl_tail_l_right
    SK_BMP pl_tail_l, SKF_TOP, 0, 0, pl_tail_l_top
    SK_BMP pl_tail_l, SKF_BOTTOM, 0, 0, pl_tail_l_bottom
    SK_BMP pl_tail_l, SKF_BACK, 0, 0, pl_tail_l_back
    SK_BMP pl_tail_l, SKF_FRONT, 0, 0, pl_tail_l_front
    SK_GRAD pl_tail_l, SKM_SIDES, 272, 224
    ; --- pl_fin
    SK_FILL pl_fin, SKM_ALL, PL_CREAM_2, 15
    SK_BMP pl_fin, SKF_RIGHT, 0, 0, pl_fin_right
    SK_BMP pl_fin, SKF_LEFT, 0, 0, pl_fin_left
    SK_BMP pl_fin, SKF_TOP, 0, 0, pl_fin_top
    SK_BMP pl_fin, SKF_BACK, 0, 0, pl_fin_back
    SK_BMP pl_fin, SKF_FRONT, 0, 0, pl_fin_front
    SK_GRAD pl_fin, SKM_SIDES, 272, 224
    ; --- pl_pod_l
    SK_FILL pl_pod_l, SKM_ALL, AC_IRON_3, 0
    SK_BMP pl_pod_l, SKF_RIGHT, 0, 0, pl_pod_l_right
    SK_BMP pl_pod_l, SKF_LEFT, 0, 0, pl_pod_l_right
    SK_BMP pl_pod_l, SKF_TOP, 0, 0, pl_pod_l_top
    SK_BMP pl_pod_l, SKF_BACK, 0, 0, pl_pod_l_back
    SK_BMP pl_pod_l, SKF_FRONT, 0, 0, pl_pod_l_back
    SK_GRAD pl_pod_l, SKM_SIDES, 272, 224
    ; --- pl_pod_t
    SK_FILL pl_pod_t, SKM_ALL, AC_IRON_3, 0
    SK_BMP pl_pod_t, SKF_RIGHT, 0, 0, pl_pod_t_right
    SK_BMP pl_pod_t, SKF_LEFT, 0, 0, pl_pod_t_right
    SK_BMP pl_pod_t, SKF_TOP, 0, 0, pl_pod_t_top
    SK_BMP pl_pod_t, SKF_BACK, 0, 0, pl_pod_t_back
    SK_BMP pl_pod_t, SKF_FRONT, 0, 0, pl_pod_t_back
    SK_GRAD pl_pod_t, SKM_SIDES, 272, 224
    ; --- pl_tyre_a_l
    SK_FILL pl_tyre_a_l, SKM_ALL, PL_RUBBER_2, 0
    SK_BMP pl_tyre_a_l, SKF_RIGHT, 0, 0, pl_tyre_a_l_right
    SK_BMP pl_tyre_a_l, SKF_LEFT, 0, 0, pl_tyre_a_l_right
    SK_BMP pl_tyre_a_l, SKF_TOP, 0, 0, pl_tyre_a_l_top
    SK_BMP pl_tyre_a_l, SKF_BOTTOM, 0, 0, pl_tyre_a_l_top
    SK_GRAD pl_tyre_a_l, SKM_SIDES, 272, 224
    ; --- pl_tyre_b_l
    SK_FILL pl_tyre_b_l, SKM_ALL, PL_RUBBER_2, 0
    SK_BMP pl_tyre_b_l, SKF_RIGHT, 0, 0, pl_tyre_b_l_right
    SK_BMP pl_tyre_b_l, SKF_LEFT, 0, 0, pl_tyre_b_l_right
    SK_BMP pl_tyre_b_l, SKF_TOP, 0, 0, pl_tyre_b_l_top
    SK_BMP pl_tyre_b_l, SKF_BOTTOM, 0, 0, pl_tyre_b_l_top
    SK_GRAD pl_tyre_b_l, SKM_SIDES, 272, 224
    ; --- pl_hub_l
    SK_FILL pl_hub_l, SKM_ALL, AC_GOLD_2, 0
    SK_BMP pl_hub_l, SKF_RIGHT, 0, 0, pl_hub_l_right
    SK_BMP pl_hub_l, SKF_LEFT, 0, 0, pl_hub_l_right
    SK_GRAD pl_hub_l, SKM_SIDES, 272, 224
    ; --- pl_axle
    SK_FILL pl_axle, SKM_ALL, AC_IRON_3, 0
    SK_BMP pl_axle, SKF_RIGHT, 0, 0, pl_axle_right
    SK_BMP pl_axle, SKF_LEFT, 0, 0, pl_axle_right
    SK_BMP pl_axle, SKF_TOP, 0, 0, pl_axle_top
    SK_BMP pl_axle, SKF_BOTTOM, 0, 0, pl_axle_bottom
    SK_BMP pl_axle, SKF_BACK, 0, 0, pl_axle_bottom
    SK_BMP pl_axle, SKF_FRONT, 0, 0, pl_axle_bottom
    SK_GRAD pl_axle, SKM_SIDES, 272, 224
    ; --- pl_strut_l
    SK_FILL pl_strut_l, SKM_ALL, AC_IRON_3, 0
    SK_BMP pl_strut_l, SKF_RIGHT, 0, 0, pl_strut_l_right
    SK_BMP pl_strut_l, SKF_LEFT, 0, 0, pl_strut_l_right
    SK_BMP pl_strut_l, SKF_TOP, 0, 0, pl_strut_l_top
    SK_BMP pl_strut_l, SKF_BOTTOM, 0, 0, pl_strut_l_top
    SK_BMP pl_strut_l, SKF_BACK, 0, 0, pl_strut_l_right
    SK_BMP pl_strut_l, SKF_FRONT, 0, 0, pl_strut_l_right
    SK_GRAD pl_strut_l, SKM_SIDES, 272, 224
    ; --- pl_tailwheel
    SK_FILL pl_tailwheel, SKM_ALL, PL_RUBBER_2, 0
    SK_BMP pl_tailwheel, SKF_RIGHT, 0, 0, pl_tailwheel_right
    SK_BMP pl_tailwheel, SKF_LEFT, 0, 0, pl_tailwheel_right
    SK_BMP pl_tailwheel, SKF_TOP, 0, 0, pl_tailwheel_top
    SK_BMP pl_tailwheel, SKF_BOTTOM, 0, 0, pl_tailwheel_top
    SK_GRAD pl_tailwheel, SKM_SIDES, 272, 224
    ; --- pl_tailstrut
    SK_FILL pl_tailstrut, SKM_ALL, AC_IRON_3, 0
    SK_BMP pl_tailstrut, SKF_RIGHT, 0, 0, pl_strut_l_right
    SK_BMP pl_tailstrut, SKF_LEFT, 0, 0, pl_strut_l_right
    SK_BMP pl_tailstrut, SKF_TOP, 0, 0, pl_strut_l_top
    SK_BMP pl_tailstrut, SKF_BOTTOM, 0, 0, pl_strut_l_top
    SK_BMP pl_tailstrut, SKF_BACK, 0, 0, pl_strut_l_right
    SK_BMP pl_tailstrut, SKF_FRONT, 0, 0, pl_strut_l_right
    SK_GRAD pl_tailstrut, SKM_SIDES, 272, 224
    ; --- pl_nav_l
    SK_FILL pl_nav_l, SKM_ALL, RGBO(236, 64, 56), 0
    SK_BMP pl_nav_l, SKF_RIGHT, 0, 0, pl_nav_l_right
    SK_BMP pl_nav_l, SKF_LEFT, 0, 0, pl_nav_l_right
    SK_BMP pl_nav_l, SKF_TOP, 0, 0, pl_nav_l_top
    SK_BMP pl_nav_l, SKF_BOTTOM, 0, 0, pl_nav_l_top
    SK_BMP pl_nav_l, SKF_BACK, 0, 0, pl_nav_l_back
    SK_BMP pl_nav_l, SKF_FRONT, 0, 0, pl_nav_l_back
    SK_GRAD pl_nav_l, SKM_SIDES, 272, 224
    ; --- pl_nav_r
    SK_FILL pl_nav_r, SKM_ALL, RGBO(60, 196, 90), 0
    SK_BMP pl_nav_r, SKF_RIGHT, 0, 0, pl_nav_r_right
    SK_BMP pl_nav_r, SKF_LEFT, 0, 0, pl_nav_r_right
    SK_BMP pl_nav_r, SKF_TOP, 0, 0, pl_nav_r_top
    SK_BMP pl_nav_r, SKF_BOTTOM, 0, 0, pl_nav_r_top
    SK_BMP pl_nav_r, SKF_BACK, 0, 0, pl_nav_r_back
    SK_BMP pl_nav_r, SKF_FRONT, 0, 0, pl_nav_r_back
    SK_GRAD pl_nav_r, SKM_SIDES, 272, 224
    ; --- pl_pitot
    SK_FILL pl_pitot, SKM_ALL, AC_IRON_2, 0
    SK_BMP pl_pitot, SKF_RIGHT, 0, 0, pl_pitot_right
    SK_BMP pl_pitot, SKF_LEFT, 0, 0, pl_pitot_right
    SK_BMP pl_pitot, SKF_TOP, 0, 0, pl_pitot_top
    SK_BMP pl_pitot, SKF_BOTTOM, 0, 0, pl_pitot_bottom
    SK_BMP pl_pitot, SKF_BACK, 0, 0, pl_pitot_back
    SK_BMP pl_pitot, SKF_FRONT, 0, 0, pl_pitot_back
    SK_GRAD pl_pitot, SKM_SIDES, 272, 224
SKMODEL_END

; ===================================================================================================
; m_plane_prop
; ===================================================================================================

section .rodata
; The characters of every pp_ bitmap. Groups: base, highlight, shade, deep.
;   w W j J wood   g G o O brass   _ transparent
align 8
pp_pal:
    PALC 'w', AC_WOOD_2
    PALC 'W', AC_WOOD_1
    PALC 'j', AC_WOOD_3
    PALC 'J', AC_WOOD_4
    PALC 'g', AC_GOLD_2
    PALC 'G', AC_GOLD_1
    PALC 'o', AC_GOLD_3
    PALC 'O', AC_GOLD_4
    PALT '_'
    dq 0

    ; pp_hub_right (2x8): pp_hub RIGHT, pp_hub LEFT
    SKROWS pp_hub_right_rows, 2, 8
    SKROW "GG"
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROW "oo"
    SKROWS_END
    align 8
    SKBMP pp_hub_right, pp_hub_right_rows, 2, 8, pp_pal
    ; pp_hub_top (8x2): pp_hub TOP, pp_hub BOTTOM
    SKROWS pp_hub_top_rows, 8, 2
    SKROW "GGGGGGGG"
    SKROW "oooooooo"
    SKROWS_END
    align 8
    SKBMP pp_hub_top, pp_hub_top_rows, 8, 2, pp_pal
    ; pp_hub_back (8x8): pp_hub BACK, pp_hub FRONT
    SKROWS pp_hub_back_rows, 8, 8
    SKROW "oooooooo"
    SKROW "oO....Oo"
    SKROW "o......o"
    SKROW "o..GG..o"
    SKROW "o..GG..o"
    SKROW "o......o"
    SKROW "oO....Oo"
    SKROW "oooooooo"
    SKROWS_END
    align 8
    SKBMP pp_hub_back, pp_hub_back_rows, 8, 8, pp_pal
    ; pp_cone1_right (2x6): pp_cone1 RIGHT, pp_cone1 LEFT
    SKROWS pp_cone1_right_rows, 2, 6
    SKROW "G."
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROW "oo"
    SKROWS_END
    align 8
    SKBMP pp_cone1_right, pp_cone1_right_rows, 2, 6, pp_pal
    ; pp_cone1_top (6x2): pp_cone1 TOP, pp_cone1 BOTTOM
    SKROWS pp_cone1_top_rows, 6, 2
    SKROW "G....."
    SKROW "oooooo"
    SKROWS_END
    align 8
    SKBMP pp_cone1_top, pp_cone1_top_rows, 6, 2, pp_pal
    ; pp_cone1_back (6x6): pp_cone1 BACK, pp_cone1 FRONT
    SKROWS pp_cone1_back_rows, 6, 6
    SKROW "G....."
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "......"
    SKROW "oooooo"
    SKROWS_END
    align 8
    SKBMP pp_cone1_back, pp_cone1_back_rows, 6, 6, pp_pal
    ; pp_cone2_right (2x4): pp_cone2 RIGHT, pp_cone2 LEFT
    SKROWS pp_cone2_right_rows, 2, 4
    SKROW "G."
    SKROW ".."
    SKROW ".."
    SKROW "oo"
    SKROWS_END
    align 8
    SKBMP pp_cone2_right, pp_cone2_right_rows, 2, 4, pp_pal
    ; pp_cone2_top (4x2): pp_cone2 TOP, pp_cone2 BOTTOM
    SKROWS pp_cone2_top_rows, 4, 2
    SKROW "G..."
    SKROW "oooo"
    SKROWS_END
    align 8
    SKBMP pp_cone2_top, pp_cone2_top_rows, 4, 2, pp_pal
    ; pp_cone2_back (4x4): pp_cone2 BACK, pp_cone2 FRONT
    SKROWS pp_cone2_back_rows, 4, 4
    SKROW "G..."
    SKROW "...."
    SKROW "...."
    SKROW "oooo"
    SKROWS_END
    align 8
    SKBMP pp_cone2_back, pp_cone2_back_rows, 4, 4, pp_pal
    ; pp_cone3_right (1x2): pp_cone3 RIGHT, pp_cone3 LEFT
    SKROWS pp_cone3_right_rows, 1, 2
    SKROW "G"
    SKROW "o"
    SKROWS_END
    align 8
    SKBMP pp_cone3_right, pp_cone3_right_rows, 1, 2, pp_pal
    ; pp_cone3_top (2x1): pp_cone3 TOP, pp_cone3 BOTTOM
    SKROWS pp_cone3_top_rows, 2, 1
    SKROW "Go"
    SKROWS_END
    align 8
    SKBMP pp_cone3_top, pp_cone3_top_rows, 2, 1, pp_pal
    ; pp_cone3_back (2x2): pp_cone3 BACK, pp_cone3 FRONT
    SKROWS pp_cone3_back_rows, 2, 2
    SKROW "G."
    SKROW "oo"
    SKROWS_END
    align 8
    SKBMP pp_cone3_back, pp_cone3_back_rows, 2, 2, pp_pal
    ; pp_root_xp_back (10x6): pp_root_xp BACK, pp_root_xn FRONT
    SKROWS pp_root_xp_back_rows, 10, 6
    SKROW "WWWWWWWWWW"
    SKROW ".........."
    SKROW ".........."
    SKROW ".........."
    SKROW "WWW.....WW"
    SKROW "jjjjjjjjjj"
    SKROWS_END
    align 8
    SKBMP pp_root_xp_back, pp_root_xp_back_rows, 10, 6, pp_pal
    ; pp_root_xp_front (10x6): pp_root_xp FRONT, pp_root_xn BACK
    SKROWS pp_root_xp_front_rows, 10, 6
    SKROW "WWWWWWWWWW"
    SKROW ".........."
    SKROW ".........."
    SKROW ".........."
    SKROW "WW.....WWW"
    SKROW "jjjjjjjjjj"
    SKROWS_END
    align 8
    SKBMP pp_root_xp_front, pp_root_xp_front_rows, 10, 6, pp_pal
    ; pp_tip_xp_right (2x4): pp_tip_xp RIGHT, pp_tip_xn LEFT
    SKROWS pp_tip_xp_right_rows, 2, 4
    SKROW "oo"
    SKROW "oo"
    SKROW "oo"
    SKROW "oo"
    SKROWS_END
    align 8
    SKBMP pp_tip_xp_right, pp_tip_xp_right_rows, 2, 4, pp_pal
    ; pp_tip_xp_top (8x2): pp_tip_xp TOP, pp_tip_xp BOTTOM
    SKROWS pp_tip_xp_top_rows, 8, 2
    SKROW "ogg....."
    SKROW "ogg....."
    SKROWS_END
    align 8
    SKBMP pp_tip_xp_top, pp_tip_xp_top_rows, 8, 2, pp_pal
    ; pp_tip_xp_back (8x4): pp_tip_xp BACK, pp_tip_xn FRONT
    SKROWS pp_tip_xp_back_rows, 8, 4
    SKROW "WWWWWggo"
    SKROW ".....ggo"
    SKROW ".....ggo"
    SKROW "jjjjjggo"
    SKROWS_END
    align 8
    SKBMP pp_tip_xp_back, pp_tip_xp_back_rows, 8, 4, pp_pal
    ; pp_tip_xp_front (8x4): pp_tip_xp FRONT, pp_tip_xn BACK
    SKROWS pp_tip_xp_front_rows, 8, 4
    SKROW "oggWWWWW"
    SKROW "ogg....."
    SKROW "ogg....."
    SKROW "oggjjjjj"
    SKROWS_END
    align 8
    SKBMP pp_tip_xp_front, pp_tip_xp_front_rows, 8, 4, pp_pal
    ; pp_tip_xn_top (8x2): pp_tip_xn TOP, pp_tip_xn BOTTOM
    SKROWS pp_tip_xn_top_rows, 8, 2
    SKROW ".....ggo"
    SKROW ".....ggo"
    SKROWS_END
    align 8
    SKBMP pp_tip_xn_top, pp_tip_xn_top_rows, 8, 2, pp_pal
    ; pp_root_yp_back (6x10): pp_root_yp BACK
    SKROWS pp_root_yp_back_rows, 6, 10
    SKROW "WW...j"
    SKROW "WW...j"
    SKROW "W....j"
    SKROW "W....j"
    SKROW "W....j"
    SKROW "W....j"
    SKROW "W....j"
    SKROW "WW...j"
    SKROW "WW...j"
    SKROW "WW...j"
    SKROWS_END
    align 8
    SKBMP pp_root_yp_back, pp_root_yp_back_rows, 6, 10, pp_pal
    ; pp_root_yp_front (6x10): pp_root_yp FRONT
    SKROWS pp_root_yp_front_rows, 6, 10
    SKROW "j...WW"
    SKROW "j...WW"
    SKROW "j....W"
    SKROW "j....W"
    SKROW "j....W"
    SKROW "j....W"
    SKROW "j....W"
    SKROW "j...WW"
    SKROW "j...WW"
    SKROW "j...WW"
    SKROWS_END
    align 8
    SKBMP pp_root_yp_front, pp_root_yp_front_rows, 6, 10, pp_pal
    ; pp_root_yn_back (6x10): pp_root_yn BACK
    SKROWS pp_root_yn_back_rows, 6, 10
    SKROW "WW...j"
    SKROW "WW...j"
    SKROW "WW...j"
    SKROW "W....j"
    SKROW "W....j"
    SKROW "W....j"
    SKROW "W....j"
    SKROW "W....j"
    SKROW "WW...j"
    SKROW "WW...j"
    SKROWS_END
    align 8
    SKBMP pp_root_yn_back, pp_root_yn_back_rows, 6, 10, pp_pal
    ; pp_root_yn_front (6x10): pp_root_yn FRONT
    SKROWS pp_root_yn_front_rows, 6, 10
    SKROW "j...WW"
    SKROW "j...WW"
    SKROW "j...WW"
    SKROW "j....W"
    SKROW "j....W"
    SKROW "j....W"
    SKROW "j....W"
    SKROW "j....W"
    SKROW "j...WW"
    SKROW "j...WW"
    SKROWS_END
    align 8
    SKBMP pp_root_yn_front, pp_root_yn_front_rows, 6, 10, pp_pal
    ; pp_tip_yp_right (2x8): pp_tip_yp RIGHT, pp_tip_yp LEFT
    SKROWS pp_tip_yp_right_rows, 2, 8
    SKROW "oo"
    SKROW "gg"
    SKROW "gg"
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROWS_END
    align 8
    SKBMP pp_tip_yp_right, pp_tip_yp_right_rows, 2, 8, pp_pal
    ; pp_tip_yp_top (4x2): pp_tip_yp TOP, pp_tip_yn BOTTOM
    SKROWS pp_tip_yp_top_rows, 4, 2
    SKROW "oooo"
    SKROW "oooo"
    SKROWS_END
    align 8
    SKBMP pp_tip_yp_top, pp_tip_yp_top_rows, 4, 2, pp_pal
    ; pp_tip_yp_back (4x8): pp_tip_yp BACK
    SKROWS pp_tip_yp_back_rows, 4, 8
    SKROW "oooo"
    SKROW "gggg"
    SKROW "gggg"
    SKROW "W..j"
    SKROW "W..j"
    SKROW "W..j"
    SKROW "W..j"
    SKROW "W..j"
    SKROWS_END
    align 8
    SKBMP pp_tip_yp_back, pp_tip_yp_back_rows, 4, 8, pp_pal
    ; pp_tip_yp_front (4x8): pp_tip_yp FRONT
    SKROWS pp_tip_yp_front_rows, 4, 8
    SKROW "oooo"
    SKROW "gggg"
    SKROW "gggg"
    SKROW "j..W"
    SKROW "j..W"
    SKROW "j..W"
    SKROW "j..W"
    SKROW "j..W"
    SKROWS_END
    align 8
    SKBMP pp_tip_yp_front, pp_tip_yp_front_rows, 4, 8, pp_pal
    ; pp_tip_yn_right (2x8): pp_tip_yn RIGHT, pp_tip_yn LEFT
    SKROWS pp_tip_yn_right_rows, 2, 8
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROW ".."
    SKROW "gg"
    SKROW "gg"
    SKROW "oo"
    SKROWS_END
    align 8
    SKBMP pp_tip_yn_right, pp_tip_yn_right_rows, 2, 8, pp_pal
    ; pp_tip_yn_back (4x8): pp_tip_yn BACK
    SKROWS pp_tip_yn_back_rows, 4, 8
    SKROW "W..j"
    SKROW "W..j"
    SKROW "W..j"
    SKROW "W..j"
    SKROW "W..j"
    SKROW "gggg"
    SKROW "gggg"
    SKROW "oooo"
    SKROWS_END
    align 8
    SKBMP pp_tip_yn_back, pp_tip_yn_back_rows, 4, 8, pp_pal
    ; pp_tip_yn_front (4x8): pp_tip_yn FRONT
    SKROWS pp_tip_yn_front_rows, 4, 8
    SKROW "j..W"
    SKROW "j..W"
    SKROW "j..W"
    SKROW "j..W"
    SKROW "j..W"
    SKROW "gggg"
    SKROW "gggg"
    SKROW "oooo"
    SKROWS_END
    align 8
    SKBMP pp_tip_yn_front, pp_tip_yn_front_rows, 4, 8, pp_pal

section .data
SKMODEL_BEGIN m_plane_prop, 32, 0, 0, 0, 0
    SKBONE BK_BODY, 0, 0, 0.00
    PART pp_cone3, -1, -1, -6, 2, 2, 1, 0, 0
    PART pp_root_yp, -3, 4, -1, 6, 10, 2, 0, 0              ; blade roots, vertical pair
    PART pp_tip_yp, -2, 14, -1, 4, 8, 2, 0, 0               ; blade tips with brass caps, vertical pair
    PART pp_tip_yn, -2, -22, -2, 4, 8, 2, 0, 0
    PART pp_hub, -4, -4, -1, 8, 8, 2, 0, 0                  ; hub flange
    PART pp_cone2, -2, -2, -5, 4, 4, 2, 0, 0
    PART pp_tip_xp, 14, -2, -1, 8, 4, 2, 0, 0               ; blade tips, brass caps, 1 texel forward (twist)
    PART pp_root_yn, -3, -14, -1, 6, 10, 2, 0, 0
    PART pp_tip_xn, -22, -2, -2, 8, 4, 2, 0, 0
    PART pp_cone1, -3, -3, -3, 6, 6, 2, 0, 0                ; spinner, a stepped cone
    PART pp_root_xn, -14, -3, -1, 10, 6, 2, 0, 0
    PART pp_root_xp, 4, -3, -1, 10, 6, 2, 0, 0              ; blade roots, horizontal pair
SKMODEL_PAINT
    ; --- pp_hub
    SK_FILL pp_hub, SKM_ALL, AC_GOLD_2, 0
    SK_BMP pp_hub, SKF_RIGHT, 0, 0, pp_hub_right
    SK_BMP pp_hub, SKF_LEFT, 0, 0, pp_hub_right
    SK_BMP pp_hub, SKF_TOP, 0, 0, pp_hub_top
    SK_BMP pp_hub, SKF_BOTTOM, 0, 0, pp_hub_top
    SK_BMP pp_hub, SKF_BACK, 0, 0, pp_hub_back
    SK_BMP pp_hub, SKF_FRONT, 0, 0, pp_hub_back
    SK_GRAD pp_hub, SKM_SIDES, 272, 224
    ; --- pp_cone1
    SK_FILL pp_cone1, SKM_ALL, AC_GOLD_2, 0
    SK_BMP pp_cone1, SKF_RIGHT, 0, 0, pp_cone1_right
    SK_BMP pp_cone1, SKF_LEFT, 0, 0, pp_cone1_right
    SK_BMP pp_cone1, SKF_TOP, 0, 0, pp_cone1_top
    SK_BMP pp_cone1, SKF_BOTTOM, 0, 0, pp_cone1_top
    SK_BMP pp_cone1, SKF_BACK, 0, 0, pp_cone1_back
    SK_BMP pp_cone1, SKF_FRONT, 0, 0, pp_cone1_back
    SK_GRAD pp_cone1, SKM_SIDES, 272, 224
    ; --- pp_cone2
    SK_FILL pp_cone2, SKM_ALL, AC_GOLD_2, 0
    SK_BMP pp_cone2, SKF_RIGHT, 0, 0, pp_cone2_right
    SK_BMP pp_cone2, SKF_LEFT, 0, 0, pp_cone2_right
    SK_BMP pp_cone2, SKF_TOP, 0, 0, pp_cone2_top
    SK_BMP pp_cone2, SKF_BOTTOM, 0, 0, pp_cone2_top
    SK_BMP pp_cone2, SKF_BACK, 0, 0, pp_cone2_back
    SK_BMP pp_cone2, SKF_FRONT, 0, 0, pp_cone2_back
    SK_GRAD pp_cone2, SKM_SIDES, 272, 224
    ; --- pp_cone3
    SK_FILL pp_cone3, SKM_ALL, AC_GOLD_2, 0
    SK_BMP pp_cone3, SKF_RIGHT, 0, 0, pp_cone3_right
    SK_BMP pp_cone3, SKF_LEFT, 0, 0, pp_cone3_right
    SK_BMP pp_cone3, SKF_TOP, 0, 0, pp_cone3_top
    SK_BMP pp_cone3, SKF_BOTTOM, 0, 0, pp_cone3_top
    SK_BMP pp_cone3, SKF_BACK, 0, 0, pp_cone3_back
    SK_BMP pp_cone3, SKF_FRONT, 0, 0, pp_cone3_back
    SK_GRAD pp_cone3, SKM_SIDES, 272, 224
    ; --- pp_root_xp
    SK_FILL pp_root_xp, SKM_ALL, AC_WOOD_2, 15
    SK_BMP pp_root_xp, SKF_BACK, 0, 0, pp_root_xp_back
    SK_BMP pp_root_xp, SKF_FRONT, 0, 0, pp_root_xp_front
    SK_GRAD pp_root_xp, SKM_SIDES, 272, 224
    ; --- pp_root_xn
    SK_FILL pp_root_xn, SKM_ALL, AC_WOOD_2, 15
    SK_BMP pp_root_xn, SKF_BACK, 0, 0, pp_root_xp_front
    SK_BMP pp_root_xn, SKF_FRONT, 0, 0, pp_root_xp_back
    SK_GRAD pp_root_xn, SKM_SIDES, 272, 224
    ; --- pp_tip_xp
    SK_FILL pp_tip_xp, SKM_ALL, AC_WOOD_2, 15
    SK_BMP pp_tip_xp, SKF_RIGHT, 0, 0, pp_tip_xp_right
    SK_BMP pp_tip_xp, SKF_TOP, 0, 0, pp_tip_xp_top
    SK_BMP pp_tip_xp, SKF_BOTTOM, 0, 0, pp_tip_xp_top
    SK_BMP pp_tip_xp, SKF_BACK, 0, 0, pp_tip_xp_back
    SK_BMP pp_tip_xp, SKF_FRONT, 0, 0, pp_tip_xp_front
    SK_GRAD pp_tip_xp, SKM_SIDES, 272, 224
    ; --- pp_tip_xn
    SK_FILL pp_tip_xn, SKM_ALL, AC_WOOD_2, 15
    SK_BMP pp_tip_xn, SKF_LEFT, 0, 0, pp_tip_xp_right
    SK_BMP pp_tip_xn, SKF_TOP, 0, 0, pp_tip_xn_top
    SK_BMP pp_tip_xn, SKF_BOTTOM, 0, 0, pp_tip_xn_top
    SK_BMP pp_tip_xn, SKF_BACK, 0, 0, pp_tip_xp_front
    SK_BMP pp_tip_xn, SKF_FRONT, 0, 0, pp_tip_xp_back
    SK_GRAD pp_tip_xn, SKM_SIDES, 272, 224
    ; --- pp_root_yp
    SK_FILL pp_root_yp, SKM_ALL, AC_WOOD_2, 15
    SK_BMP pp_root_yp, SKF_BACK, 0, 0, pp_root_yp_back
    SK_BMP pp_root_yp, SKF_FRONT, 0, 0, pp_root_yp_front
    SK_GRAD pp_root_yp, SKM_SIDES, 272, 224
    ; --- pp_root_yn
    SK_FILL pp_root_yn, SKM_ALL, AC_WOOD_2, 15
    SK_BMP pp_root_yn, SKF_BACK, 0, 0, pp_root_yn_back
    SK_BMP pp_root_yn, SKF_FRONT, 0, 0, pp_root_yn_front
    SK_GRAD pp_root_yn, SKM_SIDES, 272, 224
    ; --- pp_tip_yp
    SK_FILL pp_tip_yp, SKM_ALL, AC_WOOD_2, 15
    SK_BMP pp_tip_yp, SKF_RIGHT, 0, 0, pp_tip_yp_right
    SK_BMP pp_tip_yp, SKF_LEFT, 0, 0, pp_tip_yp_right
    SK_BMP pp_tip_yp, SKF_TOP, 0, 0, pp_tip_yp_top
    SK_BMP pp_tip_yp, SKF_BACK, 0, 0, pp_tip_yp_back
    SK_BMP pp_tip_yp, SKF_FRONT, 0, 0, pp_tip_yp_front
    SK_GRAD pp_tip_yp, SKM_SIDES, 272, 224
    ; --- pp_tip_yn
    SK_FILL pp_tip_yn, SKM_ALL, AC_WOOD_2, 15
    SK_BMP pp_tip_yn, SKF_RIGHT, 0, 0, pp_tip_yn_right
    SK_BMP pp_tip_yn, SKF_LEFT, 0, 0, pp_tip_yn_right
    SK_BMP pp_tip_yn, SKF_BOTTOM, 0, 0, pp_tip_yp_top
    SK_BMP pp_tip_yn, SKF_BACK, 0, 0, pp_tip_yn_back
    SK_BMP pp_tip_yn, SKF_FRONT, 0, 0, pp_tip_yn_front
    SK_GRAD pp_tip_yn, SKM_SIDES, 272, 224
SKMODEL_END
