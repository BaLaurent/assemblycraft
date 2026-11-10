# AssemblyCraft "Looks": detailed cartoon-blocky characters, 32×32 item icons, held items, guns and vehicles

## Context

Players say the graphics are far too simple. Characters are 6 boxes (11 for the spider). Each box face stretches one 16×16 atlas tile, whatever its size, and only the head's front tile has a face. Items are 16×16 icons drawn by code; the pork chop is one three-tint ellipse (`icon_pork`, `src/texgen.asm:1468`). NPCs and players hold nothing. The boat is 5 plank boxes and the plane 8 boxes in iron, wool and coal block tiles.

The user wants much more detail in the same cartoon, blocky style: faces, clothes and accessories on characters, and more worked items.

Scope chosen by the user:
- characters: every mob, the 5 faction folk and their roles, the boss, other players' avatars, the first-person arm;
- all 93 item icons, redrawn at **32×32**. The user accepted that icon texels are half a GUI unit;
- held items shown in the hands of folk, mobs and other players;
- detailed 3D firearms;
- the boat and the plane.

Out of scope: block textures (a separate later pass, see the GitHub issue step), per-NPC variants, and 3D block icons.

End state:
- Every entity is a skinned box model: an unwrapped skin at 32 texels per block (64 for guns) packed into a 256×4096 atlas, with bones, overlays and many detail parts.
- Every item has a 32×32 pixel-art icon used by the UI, by drops and by the hand.
- Characters hold their weapon or item.
- The old tile-per-face model code and tiles are gone.
- `make test` is green at 319 tests, the Windows build passes its selftest under Wine, and live omabox screenshots match the validated mockups.

Repo: `/run/media/octopusman/Games/Experiences/assemblycraft`, x86-64 NASM, branch `master`, HEAD `f822e92` when this was written, 314 selftests.

## Conventions (all waves)

- Parallel agents share this tree. Before Wave 0, run `git status` and `git pull --ff-only`.
  - When this plan was written, `src/common.inc`, `options.asm`, `render.asm`, `settings.asm` and `stream.asm` carried someone else's uncommitted `MAX_RENDER_DIST 24` hunks.
  - Never revert or commit foreign hunks. Commit only this work's hunks with `git add -p`, and never add `.omp/`, `.asm-lsp.toml` or `feature-requests.md`.
- Each `.asm` file follows the house rules:
  - `%include "common.inc"` (art files also `%include "art.inc"`), then `default rel`;
  - explicit sections and its own `global`/`extern` lines;
  - the SysV ABI: rsp 16-aligned at every call, rbx/rbp/r12–r15 callee-saved;
  - a header comment with signature and contract on every function;
  - byte ids loaded with `movzx`.
- A test is `test_<name>() → eax` (0 = pass). Register it in `src/selftest.asm` with an `extern`, a `TEST` row and a `TESTNAME` row, appended in plan order.
- Every new assertion gets a negative control: break the code once in a scratch copy, see the test fail, restore.
- Workers work in scratch copies:

  ```
  REPO=/run/media/octopusman/Games/Experiences/assemblycraft
  rm -rf /tmp/aclk-<w> /tmp/aclk-<w>-base
  mkdir -p /tmp/aclk-<w>
  rsync -a --exclude build --exclude .git --exclude .omp $REPO/ /tmp/aclk-<w>/
  rsync -a $REPO/src/ /tmp/aclk-<w>-base/
  ```

  - Workers never run git and edit only the files they own.
  - They put fakes of sibling symbols in `src/zz_stub.asm`. It is never copied back.
  - Each worker reports: owned files, `selftest.asm` lines, the `make test` tail, stubs, deviations, negative controls, and unowned call sites that need wiring.
- The integrator copies back owned files only, after a `cmp` against the base. Only the integrator runs git: one commit per step named below, and `git push` at the end of each wave.
- Live checks use omabox from `$HOME` (read skill `omabox` first):
  - `omabox up --audio`;
  - install: `H=$(omabox -b default path --home); cp build/assemblycraft "$H/.ac.new" && mv -f "$H/.ac.new" "$H/assemblycraft"`;
  - launch: `omabox -b default run -d --wait -- /home/sbx/assemblycraft --data-dir /home/sbx/aclooks --play LOOKS --creative --seed 4242`;
  - capture: `omabox -b default shot --window assemblycraft --fit 960`.

  Mouse look does not reach the game, so aim, teleport and freeze through skill `assemblycraft-gdb-live-driver`. The debug menu (F12 ×3) spawns mobs (Enemies tab: `debug_spawn(type, level, elite, count)`), gives items and sets the time of day.

## Contracts (Wave 0 writes these; every worker codes against them)

### Atlas layout

- `ATLAS_H` goes from 512 to **4096** (`ATLAS_W` stays 256). Tiles 0..511 and the font keep their places.
- Rows 512..1023 hold the item icons. Icon `k = id − FIRST_ITEM` is 32×32 texels at x `(k & 7)·32`, y `ICON32_Y0 + (k >> 3)·32`. 93 icons fill 12 rows of icons, and 128 fit.
- Rows 1024..4095 are the skin region. `skin_build` shelf-packs model unwraps there at run time.
- Texcoords stay in 1/16-texel units (`glTexCoord2i`). The v scale of the texture matrix becomes `1/65536`:
  - `f_texscale_v: dd 0.0000152587890625`, in both `src/render.asm:36` and `src/ui.asm:33`;
  - each site gets `%if ATLAS_H != 4096` / `%error "f_texscale_v assumes ATLAS_H 4096"` / `%endif`.
- Chunk `VERTEX.v` (int16) only addresses block tiles below row 512 (v ≤ 8192), so it is unaffected.
- `face_corners` (`src/render.asm:64`) becomes `global`. `skin.asm` reuses it (same CCW winding as `box_draw`).

### `src/common.inc` additions

Added after the `TILE_*` block, with these exact names and values:

```
%define ICON32_Y0      512              ; atlas rows 512..1023: item icon k = id - FIRST_ITEM, 32x32,
%define ICON32_PX      32               ; at x (k & 7) * 32, y ICON32_Y0 + (k >> 3) * 32
%define ICON32_COUNT   (NUM_ITEMS - FIRST_ITEM)
%define SKIN_Y0        1024             ; atlas rows 1024..ATLAS_H-1: model skins (skin_build packs them)
; skin model records: SKREC_SIZE bytes each, a bone or a part, the stream ends with SKR_END
%define SKREC_SIZE     20
%define SKR_END        0
%define SKR_BONE       1
%define SKR_PART       2
%define SKR_TYPE       0                ; byte SKR_*
%define SKR_KIND       1                ; bone: byte BK_*
%define SKR_PIVY       4                ; bone: int16 pivot y, texels
%define SKR_PIVZ       6                ; bone: int16 pivot z
%define SKR_SWING      8                ; bone: float, limb angle = swing * walk swing degrees
%define SKR_FLAGS      1                ; part: byte SKPF_*
%define SKR_GROW       2                ; part: byte, inflation in 1/8 texel per side (geometry only)
%define SKR_AS         3                ; part: byte, index of the part whose size and skin it shares
%define SKAS_NONE      255              ;       (SKAS_NONE: its own)
%define SKR_X0         4                ; part: int16 low corner, texels, model space
%define SKR_Y0         6
%define SKR_Z0         8
%define SKR_W          10               ; part: byte sizes, texels
%define SKR_H          11
%define SKR_D          12
%define SKR_U          14               ; part: uint16 unwrap origin, atlas texels (skin_build writes)
%define SKR_V          16
%define BK_BODY        0                ; bone kinds: the rigid root
%define BK_HEAD        1
%define BK_LLEG        2
%define BK_RLEG        3
%define BK_LARM        4
%define BK_RARM        5                ; carries the held item at SKMODEL.hand
%define BK_LIMB        6                ; any other swinging limb (quadruped legs, spider legs)
%define SKPF_ACCENT    1                ; part also multiplied by SKPOSE.accent
%define SKPF_CUTOUT    2                ; part may hold transparent texels (hair, hoods, frames)
%define SKF_RIGHT      0                ; faces, box_draw order: +X = the model's right
%define SKF_LEFT       1                ; -X
%define SKF_TOP        2                ; +Y
%define SKF_BOTTOM     3                ; -Y
%define SKF_BACK       4                ; +Z
%define SKF_FRONT      5                ; -Z (models face -Z)
%define SKM_RIGHT      1
%define SKM_LEFT       2
%define SKM_TOP        4
%define SKM_BOTTOM     8
%define SKM_BACK       16
%define SKM_FRONT      32
%define SKM_SIDES      51               ; right, left, back, front
%define SKM_ALL        63
; paint ops: SKOP_SIZE bytes each, the list ends with SKO_END
%define SKOP_SIZE      24
%define SKO_END        0
%define SKO_FILL       1
%define SKO_RECT       2
%define SKO_BMP        3
%define SKO_GRAD       4
%define SKOP_OP        0                ; byte SKO_*
%define SKOP_PART      1                ; byte part index
%define SKOP_FACES     2                ; byte: SKM_* mask (FILL, GRAD) or SKF_* face (RECT, BMP)
%define SKOP_NOISE     3                ; byte noise mask: m = 256 - (hash & noise)
%define SKOP_X         4                ; bytes: face-local rect (RECT) or position (BMP)
%define SKOP_Y         5
%define SKOP_W         6
%define SKOP_H         7
%define SKOP_COLOUR    8                ; dword RGBO (FILL, RECT)
%define SKOP_TOP       8                ; GRAD: uint16 multiplier at the top row, 256 = unchanged
%define SKOP_BOTTOM    10               ; GRAD: uint16 multiplier at the bottom row
%define SKOP_BMP       16               ; qword SKBMP* (BMP)
%define SKP_ARM_UP     1                ; SKPOSE.flags: right arm raised by .arm_deg
%define SKP_SEATED     2                ; only the BK_BODY and BK_HEAD bones
%define SKP_ARM_ONLY   4                ; only the BK_RARM bone, unrotated, no held item
struc SKMODEL
    .recs:  resq 1                      ; bone/part record stream
    .ops:   resq 1                      ; paint op list
    .tpb:   resw 1                      ; texels per block: 32 characters and vehicles, 64 guns
    .held:  resw 1                      ; default held item id, 0 none
    .hand:  resw 3                      ; held item origin (x, y, z), texels, in the BK_RARM bone
    .pad:   resw 1
endstruc                                ; 32
struc SKPOSE
    .flags:   resd 1                    ; SKP_*
    .arm_deg: resd 1                    ; float, the extra right-arm angle with SKP_ARM_UP
    .held:    resd 1                    ; item id in the right hand; 0 = SKMODEL.held
    .accent:  resd 3                    ; float rgb for SKPF_ACCENT parts
endstruc                                ; 24
struc SKBMP
    .pal:   resq 1                      ; palette: 8-byte PAL records, a zero qword ends it
    .rows:  resq 1                      ; w * h chars, row-major; '.' and chars missing from
    .w:     resb 1                      ; the palette are skipped (left as they are)
    .h:     resb 1
    .pad:   resb 6
endstruc                                ; 24
```

Face images use the Minecraft box unwrap. For a part with origin (u, v) and size w, h, d, each face rect is `(u_f, v_f, width × height)`, all in atlas texels:

|Face|Rect|Image x, left → right|Image y, top → bottom|
|---|---|---|---|
|`SKF_TOP`|`(u+d, v)`, w×d|x1 → x0|z1 (back) → z0 (front)|
|`SKF_BOTTOM`|`(u+d+w, v)`, w×d|x1 → x0|z0 (front) → z1 (back)|
|`SKF_RIGHT` (+X)|`(u, v+d)`, d×h|z1 → z0|y1 → y0|
|`SKF_FRONT` (−Z)|`(u+d, v+d)`, w×h|x1 → x0|y1 → y0|
|`SKF_LEFT` (−X)|`(u+d+w, v+d)`, d×h|z0 → z1|y1 → y0|
|`SKF_BACK` (+Z)|`(u+2d+w, v+d)`, w×h|x0 → x1|y1 → y0|

- The footprint is (2d + 2w) × (d + h). Every face image is the face as seen from outside, upright, with (0, 0) at its top-left.
- Paint ops address face-local (x, y) in that image.
- A corner with face_corners bits (bx, by, bz) maps to image coordinates:

  |Face|ix|iy|
  |---|---|---|
  |RIGHT|`bz ? 0 : d`|`by ? 0 : h`|
  |LEFT|`bz ? d : 0`|`by ? 0 : h`|
  |TOP|`bx ? 0 : w`|`bz ? 0 : d`|
  |BOTTOM|`bx ? 0 : w`|`bz ? d : 0`|
  |BACK|`bx ? w : 0`|`by ? 0 : h`|
  |FRONT|`bx ? 0 : w`|`by ? 0 : h`|

- Its texcoord is `((u_f + ix)·16 + (ix == 0 ? 1 : −1), (v_f + iy)·16 + (iy == 0 ? 1 : −1))`, a 1-unit inset as `box_draw` uses.

### `src/art.inc` (new, included by `texgen.asm` and every art file)

- **Moved verbatim from `texgen.asm`:** `RGB`, `RGBO`, `PAL ch, r, g, b` and `PALN`. Delete them from `texgen.asm`, which gains `%include "art.inc"`.
- **New palette entries:**
  - `PALC ch, colour`: `db ch,0,0,0` then `dd colour`, where colour is a packed `RGBO`;
  - `PALT ch`: `db ch,0,0,0` then `dd 0`, which writes a transparent texel.
  - A palette ends with `dq 0`.
- **Bitmaps:**
  - `SKROWS label, w, h`, then exactly h × `SKROW "<w chars>"`, then `SKROWS_END`. `SKROW` raises `%error` when `%strlen` ≠ w; `SKROWS_END` does when the row count ≠ h.
  - `SKBMP label, rows, w, h, pal` emits a `global label` `SKBMP` header.
- **Models** (emit into `section .data`: `skin_build` writes `SKR_U`/`SKR_V` and the sizes of `SKPART_AS` parts):
  - `SKMODEL_BEGIN label, tpb, held, hand_x, hand_y, hand_z` opens a context, makes `label` global and emits the `SKMODEL` header (`.recs` → the records that follow, `.ops` → the ops after `SKMODEL_PAINT`).
  - `SKBONE kind, pivot_y, pivot_z, swing` emits a bone record; `swing` is a float literal, `0.0` for rigid.
  - `SKPART x0, y0, z0, w, h, d, grow, flags` emits a part with `SKR_AS = SKAS_NONE`.
  - `SKPART_AS k, x0, y0, z0, grow, flags` emits a part with `SKR_AS = k` and sizes 0. It raises `%error` unless k < the parts so far.
  - Before the first `SKBONE`, `SKPART` raises `%error`. A model has at most 254 parts.
  - `SKMODEL_PAINT` emits the `SKR_END` record and starts the op list.
  - The ops (k is a part index, and each raises `%error` when k ≥ the part count):
    - `SK_FILL k, faces, colour, noise`
    - `SK_RECT k, face, x, y, w, h, colour, noise`
    - `SK_BMP k, face, x, y, bmp`
    - `SK_GRAD k, faces, top, bottom`
  - `SKMODEL_END` emits `SKO_END` and closes the context.
- Bitmaps, palettes and `SKBMP` headers go in `section .rodata`.
- **Material ramps** (packed `RGBO`, 1 = highlight, 4 = deepest), shared by icons, guns and vehicles:

  |Ramp|1|2|3|4|
  |---|---|---|---|---|
  |`AC_WOOD_1..4`|196,150,92|156,112,62|112,78,42|72,48,26|
  |`AC_STONE_1..4`|170,170,166|128,128,124|92,92,90|60,60,60|
  |`AC_IRON_1..4`|236,236,240|196,198,204|140,144,152|84,88,96|
  |`AC_GOLD_1..4`|255,240,140|240,196,56|190,138,24|120,80,16|
  |`AC_DIAM_1..4`|200,255,250|90,220,210|40,160,160|20,96,104|
  |`AC_LEATHER_1..4`|176,118,72|134,84,48|96,58,32|62,36,20|
  |`AC_MEAT_1..4`|250,170,170|226,112,112|176,64,72|120,36,48|
  |`AC_COOKED_1..4`|214,140,80|170,96,48|120,60,30|80,38,20|
  |`AC_FAT_1..2`|255,240,230|240,214,200|||
  |`AC_BONE_1..3`|246,240,220|214,204,176|160,148,120||
  |`AC_SKIN_1..3`|240,200,164|214,168,130|176,128,96||

  Plus `AC_OUTLINE` (40,28,20).

### `src/art.asm` (new, Wave 0): the shared blitter

- `art_pal_find(edi char, rsi pal) -> eax colour, edx 1 found / 0 missing` (leaf). It walks the 8-byte records until a zero qword.
- `art_blit(rdi first texel of the destination in the atlas, esi destination stride in texels, rdx SKBMP*, ecx clip_w, r8d clip_h)`:
  - it writes `min(w, clip_w) × min(h, clip_h)` texels;
  - each char found in the palette writes that entry's dword (alpha included);
  - every other char is skipped.
- `skin.asm` (SK_BMP) and `icons.asm` both use it. That is one routine with one rule.

### Engine APIs

#### `src/skin.asm` (W-SKIN)

**`skin_build(rdi atlas, rsi registry: SKMODEL* array, 0-terminated) -> eax 0 fits / 1 overflow`**

It first packs:
- registry order, record order;
- a cursor (cu, cv) starting at (0, `SKIN_Y0`), with shelf height sh;
- for each part with `SKR_AS = SKAS_NONE`: fw = 2(w+d), fh = d+h.
  - If fw > `ATLAS_W`, return 1 without painting.
  - If cu + fw > `ATLAS_W`: cu = 0, cv += sh, sh = 0.
  - If cv + fh > `ATLAS_H`, return 1 without painting.
  - Store u = cu, v = cv, then cu += fw, sh = max(sh, fh).
- For an AS part: copy w, h, d, u, v from part k of the same model.

It then runs every model's ops in order:
- **FILL:** every texel of each face in the mask = colour × m >> 8 per channel, alpha 255. m = 256 − (hash(ax, ay) & noise), where (ax, ay) is the atlas texel and the hash is: `h = ax·0x27d4eb2d ^ ay·0x165667b1; h ^= h >> 15; h *= 0x85ebca6b; h ^= h >> 13` (32-bit).
- **RECT:** the same, on the face-local rect clipped to the face.
- **BMP:** `art_blit` at the face origin + (x, y), clipped to the face.
- **GRAD:** rgb of each texel of each masked face × m(iy)/256, clamped to 255, alpha kept. m(iy) = top + (bottom − top)·iy/(fh − 1), and top when fh = 1.
- Paint ops on an AS part paint the shared region.

**`skin_face_rect(rdi part record, esi face) -> eax u, edx v, ecx fw, r8d fh`** (leaf, the table above)

**`skin_face_uvs(rdi part record, esi face, rdx out dd[8])`** writes the 4 corners' (u, v) texcoords, in `face_corners` order, using the inset rule.

**`skin_model_draw(rdi SKMODEL*, rsi SKPOSE* or 0, xmm0 swing_deg, xmm1 r, xmm2 g, xmm3 b)`**
- It draws in the current modelview: origin at the feet or model centre, front −Z, units blocks, atlas bound.
- It does `glPushMatrix`, then `glScalef(1/tpb)` on all three axes.
- A null pose means flags 0, held 0 and accent (1, 1, 1). held = `pose.held`, or `SKMODEL.held` when that is 0.
- Record by record:
  - **Bone:**
    - Close the previous bone: `glEnd` if its quads were begun, then its held item if it is `BK_RARM` (see below), then `glPopMatrix` if it pushed one. The `SKR_END` record closes the last bone the same way, then the final `glPopMatrix` follows.
    - Skip it under `SKP_SEATED` unless it is `BK_BODY` or `BK_HEAD`. Skip it under `SKP_ARM_ONLY` unless it is `BK_RARM`.
    - angle = 0 under `SKP_ARM_ONLY`. Otherwise angle = swing·swing_deg; for `BK_RARM` add `pose.arm_deg` with `SKP_ARM_UP`, else add `20.0` (`held_arm_deg`) when held ≠ 0.
    - When angle ≠ 0: `glPushMatrix`, `glTranslatef(0, py, pz)`, `glRotatef(angle, 1, 0, 0)`, `glTranslatef(0, −py, −pz)`.
    - Draw the bone's parts inside one `glBegin(GL_QUADS)`…`glEnd`, begun at its first drawn part. A skipped bone draws nothing and pushes nothing.
  - **Part:** for each face, `glColor4f(tint × skin_shades[face] × (accent if SKPF_ACCENT), 1)`, then 4 × (`glTexCoord2i`, `glVertex3f`). Corners are lo − g / hi + g with g = grow/8 texel, and texcoords come from `skin_face_uvs`.
  - **Closing `BK_RARM`** (held ≠ 0, no `SKP_ARM_ONLY`): after `glEnd`, `glPushMatrix`, `glTranslatef(hand)`, `glScalef(tpb)`, `held_item_draw(held, 1.0)`, `glPopMatrix`.
- `skin_shades` is `dd 0.6, 0.6, 1.0, 0.5, 0.8, 0.8` and is owned by `skin.asm`.

#### `src/icons.asm` (W-ICON)

- `icon_paint(rdi atlas, esi k, rdx SKBMP*)` clears the 32×32 cell of icon k to 0, then `art_blit`s the bitmap (clip 32×32).
- `icons_build(rdi atlas, rsi table: ICON32_COUNT SKBMP* entries)` calls `icon_paint` for k = 0..ICON32_COUNT−1.

#### `src/itemmodel.asm` (W-ICON in Wave 1, WIRE in Wave 3)

- The sprite path takes a source: atlas x0, y0 and size n (16 or 32), kept in module variables `spr_x0`, `spr_y0`, `spr_n` and `spr_px` (float 1/n).
- `texel_alpha` reads `atlas[(y0 + py)·ATLAS_W + x0 + px]` with bounds 0..n−1.
- The front and back quads span the source rect, inset 1 unit. The pixel boxes are 1/n wide. The half-thickness `f_h` stays 1/32.
- **`held_item_draw(edi id, xmm0 light)`** draws id for a holder's hand, with origin at the hand, units blocks, holder's front −Z, +Y up:
  - gun (`gun_index` ≥ 0): `glScalef(0.6)`, then `gun_model_draw(id, 1, light, 0.0)`;
  - block (`item_model_is_block`): `glTranslatef(0, −0.05, −0.12)`, `glRotatef(45, 0, 1, 0)`, `glScalef(0.3)`, `item_model_draw`;
  - anything else: `glRotatef(90, 0, 1, 0)`, `glScalef(0.55)`, `glTranslatef(0.3, 0.3, 0)`, `item_model_draw`. The icon's lower-left grip lands on the hand and its top-right tip points forward and up.
  - Each branch is bracketed by `glPushMatrix`/`glPopMatrix`.

### Model labels (art files define them, `src/artreg.asm` lists them)

- **`src/skins_mobs.asm`:** `m_zombie`, `m_skeleton`, `m_creeper`, `m_spider`, `m_pig`, `m_chicken`, `m_boss`.
- **`src/skins_folk.asm`:**
  - `m_folk_villagers`, `m_folk_bandits`, `m_folk_cult`, `m_folk_beastfolk`, `m_folk_stonekin`;
  - `m_villager_elder`, `m_villager_merchant`, `m_avatar`;
  - `m_extra_hat`, `m_extra_helmet`, `m_extra_pack`, `m_extra_crown`;
  - `m_hood_villagers`, `m_hood_bandits`, `m_hood_cult`, `m_hood_beastfolk`, `m_hood_stonekin`.
- **`src/skins_gear.asm`:** `m_gun_pistol`, `m_gun_musket`, `m_gun_shotgun`, `m_gun_rifle`, `m_gun_launcher`, `m_gun_warhead`, `m_gun_revolver`, `m_gun_hrifle`. Guns are at tpb 64.
- **`src/skins_vehicles.asm`:** `m_boat`, `m_plane`, `m_plane_prop`.
- **Icon bitmaps:** label `ib_` + the lower-case item constant (`ib_stick`, `ib_wood_pickaxe`, …, `ib_porkchop`, `ib_cooked_porkchop`, …, `ib_plane`). They are global `SKBMP`s of 32×32.
  - `src/iconart_a.asm` holds the 62 equipment icons: the 20 tools from wood to diamond, `BOW`, `ARROW`, `CELESTIAL_BOW`, the 12 armour pieces, the 7 firearms (`PISTOL`..`ROCKET_LAUNCHER`, `REVOLVER`, `HUNTING_RIFLE`), the 5 ammo items, `STAFF`, `ARCHMAGE_STAFF`, `IRON_DAGGER`, `DIAMOND_DAGGER`, `SHADOW_FANG`, `KINGS_BLADE`, the 2 hammers, the 2 spears, `FLINT_AND_STEEL` and the 4 attachments.
  - `src/iconart_b.asm` holds the other 31: `STICK`, `APPLE`, `PORKCHOP`, `COOKED_PORKCHOP`, `COAL`, the 2 ingots, `DIAMOND`, `STRING`, `GUNPOWDER`, `FLINT`, `ROTTEN_FLESH`, `FEATHER`, `RAW_CHICKEN`, `COOKED_CHICKEN`, the 2 potions, `GOLD_COIN`, the 6 jewelry items, `BOAT`, and the 6 plane items.
  - Tier variants share one `SKROWS` with per-tier palettes, using the same chars per role.
- **`src/artreg.asm` (Wave 3, WIRE):**
  - `global skin_models`: `dq` every model above in the order listed, then `dq 0`;
  - `global item_icons32`: one `dq ib_*` per item id from `STICK` to `PLANE` in id order, followed by `%if $ - item_icons32 != ICON32_COUNT * 8` / `%error` / `%endif`.

### Geometry contracts (texels, origin at the feet centre unless stated, front −Z)

**Humanoid skeleton**, shared by the 5 folk, elder, merchant and avatar so that extras, pilot and first-person arm fit. Base boxes only; detail parts are free:

|Bone|Pivot (y, z)|Swing|Base box|
|---|---|---|---|
|`BK_LLEG`|(24, 0)|+1.0|x −6..0, y 0..24, z −3..3|
|`BK_RLEG`|(24, 0)|−1.0|x 0..6, y 0..24, z −3..3|
|`BK_BODY`|—|rigid|torso x −8..8, y 24..46, z −4..4|
|`BK_LARM`|(44, 0)|−1.0|x −14..−8, y 24..46, z −3..3|
|`BK_RARM`|(44, 0)|+1.0|x 8..14, y 24..46, z −3..3; hand point (11, 26, 0)|
|`BK_HEAD`|—|rigid|x −8..8, y 46..62, z −8..8|

- The elder and merchant keep the folded-arms look: rigid arms in `BK_BODY`, with no `BK_LARM`/`BK_RARM`. Their robes are painted on torso and legs, with no skirt box.
- Extras are single `BK_BODY` models on the same origin:

  |Extra|Fits|
  |---|---|
  |hat|y ≥ 61|
  |helmet|grows over the head, x −9..9, y 52..64, z −9..9, front face open from y 52 to 58 (cutout)|
  |hood|x −9..9, y 44..64, z −9..9, face opening cutout|
  |crown|y 62..68|
  |pack|z 4..10, y 28..44|

- **Boat (`m_boat`):** origin as today's hull model space: bottom y 0, bow −Z.
  - Every part lies within x −18..18, y 0..16, z −28..28.
  - The floor runs from y 0 to at least y 10, so it covers the water surface as `hull` does today (`src/boats.asm:56`).
- **Plane (`m_plane`):** origin as today's `plane_model` (model centre, nose −Z).
  - Keep each of today's 8 boxes (`src/planes.asm:116-123`) within ±2 texels of its extent ×32, then add detail around them. That keeps the seats (`seat_x`, `seat_z`, `c_seat`) valid.
  - The cockpit around x −6..6, z −6..6 stays open above the fuselage top, y 11.
- **Propeller (`m_plane_prop`):** origin at the hub, which `planes_render` puts at (0, 0, `c_prop_z`). Both crossed blades and a hub cone in one model, blades in the XY plane, about 44 texels from the hub.
- **Guns:** origin and muzzle as today: grip near the origin, muzzle at (0, `muzzle_y`·64, `muzzle_z`·64) from `src/gunmodel.asm:99-100`.
  - The overall extents stay within ±2 texels of today's parts ×64. Keep the `models`/`muzzle_z`/`muzzle_y` order `pistol, musket, shotgun, rifle, launcher, revolver, hrifle`.
  - `m_gun_warhead` is the launcher's rocket, drawn only while loaded.

### Art style guide (all art workers)

**Skins**
- Cartoon blocky: chunky shapes, a big 16³ head, clean colour zones with 3–4 tone shading.
- Noise mask ≤ 15 on cloth and skin, ≤ 31 on fur, bark and stone, 0 on metal, eyes and trims.
- **Every face of every part is painted.** The opacity test fails on bare texels.
- Torso and head front, back and sides all carry detail.
- Side faces of heads, torsos and limbs get `SK_GRAD …, 272, 224`. Hems, cuffs and soles end with a 1-texel darker row.
- **Faces** (head front 16×16):
  - eyes 2 wide × 2–3 tall with a 1-texel white glint and a sclera texel;
  - eyebrows 3×1, darker than the hair;
  - a mouth 3–5 wide;
  - 1–2 blush texels on humans.
- **Humans:**
  - a nose part (2×2×1 to 2×3×2);
  - ears (1×3×2) on the head sides;
  - hair as a cutout overlay (grow 4) with a fringe on the front face, or as rigid hair boxes.
- **Clothes:**
  - a collar, seams, a 2-row belt with a 2×2 buckle, buttons or laces;
  - sleeves ending in a cuff, then 4–5 rows of hand or glove;
  - trousers with a fold or patch;
  - boots 6 rows high with the darkest row as sole.
- Overlays use grow 4 at least. `SKPF_CUTOUT` only where holes exist.
- Faction base tones come from `docs/superpowers/specs/2026-11-08-assemblycraft-factions-design.md:528-534`. Derive the ramps as highlight = base × 1.2 (clamped), shade = × 0.75, deep = × 0.55.
- Minimum parts:

  |Model|Minimum parts|
  |---|---|
  |folk, elder, merchant, avatar|14|
  |zombie, skeleton, creeper, pig|10|
  |chicken|9|
  |spider|19 (8 two-segment legs)|
  |boss|16|
  |each gun|8|
  |boat|10|
  |plane|20|
  |propeller|3|

**Icons (32×32)**
- The silhouette spans 24–30 px on its long axis, centred, with at least a 1 px transparent margin.
- 1 px selective outline: the darkest tone of the adjacent material, `AC_OUTLINE` on the bottom and right outer edge.
- Light from the top-left, at least 3 tones per material, and 1–3 highlight texels on metal, gems and glass. No noise.
- Tools and weapons are diagonal: handle bottom-left, head or tip top-right. `held_item_draw` and the first-person pose rely on it.

**Model briefs**

|Model|Brief|
|---|---|
|`m_folk_villagers`|Farmer: brown hair with a fringe, green tunic with a round collar, rope belt with a buckle, rolled sleeves showing forearms, brown trousers with a knee patch, laced boots.|
|`m_folk_bandits`|Red bandana knotted at the back (tails as parts), black cloth mask over the lower face, dark leather jerkin with a crossed strap and pouch, grey trousers, wrapped boots.|
|`m_folk_cult`|Pale skin, ash hood overlay, glowing red eyes, ash smudges, charcoal robe with red trim and rope sash, a pendant part.|
|`m_folk_beastfolk`|Fur head with ear parts on top, snout part, white war paint, fangs, fur vest with crossed straps, bone necklace, fur-wrapped shins.|
|`m_folk_stonekin`|Stocky stony skin with cracks, braided beard parts (two braids), chain-mail tunic with a leather belt, heavy boots.|
|`m_villager_elder`|Long grey beard part, bald top with side hair, purple robe with gold trim, folded arms.|
|`m_villager_merchant`|Moustache, flat cap part, brown robe with an apron and coin pouch, folded arms.|
|`m_avatar`|Adventurer: brown hair, scarf part and tunic body overlay plus upper sleeves flagged `SKPF_ACCENT` and painted in light greys, leather belt with a satchel strap, dark trousers, boots. The lower arm is skin, since the first-person arm shows it.|
|`m_zombie`|Humanoid with arms forward (`BK_LARM`/`BK_RARM` pivot (44, 0), swing −0.25/+0.25, boxes pointing to −Z), green rotting skin, sunken eyes, torn blue shirt with holes (cutout overlay), ripped trousers.|
|`m_skeleton`|4-wide bone limbs, ribcage torso (cutout overlay over a dark core), skull with dark sockets and teeth, held default `BOW`.|
|`m_creeper`|16×24×8 body and 16³ head, mottled green with leafy darker patches, classic dark face, 4 stubby feet.|
|`m_pig`|Body, head with a protruding snout part and nostrils, floppy ears, curly tail part, 4 legs with dark hooves.|
|`m_chicken`|Body, head, beak, red wattle, comb, wings (`BK_LIMB`, swing 0.3), thin legs with toe parts.|
|`m_spider`|Abdomen with a marking, thorax, head with 8 red eyes and fangs, 8 legs each with an upper segment rising to a knee and a lower segment to the ground, in the same bone.|
|`m_boss`|The Fallen King, about 107 texels tall, same layout as today's `boss_parts` ×32: crowned skull with glowing eyes, ragged royal robe with fur collar and gold trim, a cape part, bony hands, held default `KINGS_BLADE`.|
|Extras|Gold-banded leader hat, riveted iron helmet with a nose guard, wooden-frame pack with a bedroll, gold spiked crown with gems, faction-coloured hoods with a face opening.|
|Guns|Wood grain, blued steel with a highlight edge, brass parts, iron sights, triggers and guards. The launcher tube is olive.|
|`m_boat`|Planked hull with visible strakes and ribs, two benches, oarlocks, a raised bow piece.|
|`m_plane`|Riveted panels, open cockpit rim with a windscreen frame (cutout), engine cowl with exhaust stubs, wing roundels and stripes, wheel struts, tyres with hubs.|

**Icon briefs**
- **Raw pork chop:** a rounded chop of pink-red meat with 2–3 white marbling streaks, a cream fat rim along the top and right edge, and a cream bone with a round knob sticking out at the bottom-left.
- **Cooked pork chop:** the same shape, browned, with 2 darker diagonal grill lines, golden crisp fat and a darker bone.
- **Every other icon** reads as its name at 16 GUI units: ingots bevelled, gems faceted, potions in glass with liquid and a cork, coins stamped, jewelry with set stones, plane parts recognisable (engine block with cylinders, wing panel with a roundel, …).

## Approach

### Wave 0: contracts (integrator, serial)

1. **Baseline**
   - Run `git status` and `git pull --ff-only`, then `make && make test`, and expect 314 passing.
   - Keep this build as the baseline binary: `mkdir -p /tmp/aclooks && cp build/assemblycraft /tmp/aclooks/ac-baseline`.
   - Copy this plan to `docs/superpowers/specs/2026-11-10-assemblycraft-looks-design.md` and commit it as "looks design doc".
2. **Contracts**
   - Write the additions to `common.inc` above.
   - Create `src/art.inc` and `src/art.asm`.
   - Move `RGB`/`RGBO`/`PAL`/`PALN` out of `texgen.asm`.
   - Set `ATLAS_H 4096`.
   - Change `f_texscale_v` in `render.asm` and `ui.asm`, with their guards.
   - Make `face_corners` global.
   - Run `make test`: 314 pass.
3. **Live sanity and baseline**
   - In omabox, run the baseline binary, then the new build, each in a copy of the same LOOKS world (creative, seed 4242). Use the same position and view (set through the gdb driver), noon, the same hotbar, F3 on.
   - Take one shot of each. Blocks, text, hotbar icons and the HUD must be pixel-identical apart from moving entities and clouds. Any shifted or garbled texture means a texture-matrix site was missed: fix it before committing.
   - Record a baseline FPS with the baseline binary:
     - set the time to midnight (debug menu, World tab) so that zombies do not burn;
     - spawn 15 zombies (Enemies tab: zombie, count 15) and face them;
     - read the F3 fps after 10 s and note it in the design doc.
     - If the reading sits at the vsync cap, spawn 15 more and read again.
4. Commit "looks contracts: 256x4096 atlas, skin and icon32 formats" and push.

### Wave 1: engines (2 parallel workers)

**W-SKIN** owns `src/skin.asm` and `src/test_skin.asm` (new) plus the tooling in `/tmp/aclooks/`.

1. **Implement the engine.** `skin_build`, `skin_face_rect`, `skin_face_uvs` and `skin_model_draw` exactly as in the contract, plus `skin_shades`. `held_item_draw` is a stub in scratch.
2. **`test_skin_uv`.** Use a fixture part record (w 4, h 6, d 2, u 10, v 1100).
   - `skin_face_rect` returns TOP (12, 1100, 4, 2), BOTTOM (16, 1100, 4, 2), RIGHT (10, 1102, 2, 6), FRONT (12, 1102, 4, 6), LEFT (16, 1102, 2, 6) and BACK (18, 1102, 4, 6).
   - `skin_face_uvs(FRONT)` gives, in `face_corners` order (bits (1,0,0), (0,0,0), (0,1,0), (1,1,0)): (193, 17727), (255, 17727), (255, 17633), (193, 17633). That is u = 12·16+1 = 193 and (12+4)·16−1 = 255, v = (1102+6)·16−1 = 17727 and 1102·16+1 = 17633.
   - `skin_face_uvs(TOP)` gives, for the corner bits (0,1,1), (1,1,1), (1,1,0), (0,1,0): (255, 17601), (193, 17601), (193, 17631), (255, 17631).
3. **`test_skin_pack`** runs on a fixture registry in the test file.
   - The fixture: two models; one with a bone, 3 parts (one `SKPART_AS 0`) and FILL, RECT, BMP and GRAD ops; one with a part 120×8×8.
   - It runs `skin_build` on a test atlas and asserts:
     - it returns 0;
     - the AS part copied w, h, d, u, v;
     - no two own-skin rects overlap;
     - every rect lies in `[SKIN_Y0, ATLAS_H)` × `[0, ATLAS_W)`;
     - every texel of every face is opaque;
     - the BMP texels equal their palette colours;
     - a `SK_GRAD 256, 128` over a 6-row face filled with channel value 200 leaves row 0 at 200 and turns row 5 into 100.
   - An overflow fixture (one model with 30 own-skin parts of w 120, h 100, d 8: each a 256-wide, 108-tall unwrap, and 28 fit in the 3072 skin rows) makes `skin_build` return 1.
   - A second overflow fixture (one part of w 100, d 100: 400 texels wide) also returns 1.
   - A 64-byte 0xAA canary placed after the test atlas stays intact in both cases.
   - Put the checks in `skin_check(rdi atlas, rsi registry) -> eax 0 / failing check number`, which Wave 3 reuses for the real registry.
4. **Tooling** (throwaway, `/tmp/aclooks/`):
   - **`dump.c`** calls `texgen_build(buf)`, `icon_paint` for the icons of its list, then `skin_build(buf, registry)` on a 256×4096×4 buffer. W-SKIN stubs `icon_paint` in its scratch copy until W-ICON's `icons.asm` is integrated.
     - It writes `atlas.rgba`, plus `models.json`: per model, name, tpb, and the walked records with bone kind, pivot, swing, part box, grow, w/h/d, u/v and flags.
     - Its registry is a C array of `extern` model labels and its icon list a C array of (k, `extern` `ib_*` label) pairs. An art worker edits both lists to name its own labels. From Wave 3 it uses `skin_models` and `item_icons32` instead.
     - Link: `gcc -O1 -no-pie -pthread -o dump dump.c $(ls build/*.o | grep -v '/main.o') -lglfw -lGL -lpulse-simple -lm`.
   - **`render.py`** (Python 3, PIL and numpy) draws every model in 4 views: yaw 0 (front), 35 (three-quarter right), 90 (side) and 180 (back), pitch 20° down.
     - Orthographic projection, 6 px per texel at tpb 32 (scaled by 32/tpb), a z-buffer, nearest texel sampling with the contract's corner UVs, texels with alpha < 128 skipped (the game's alpha test), and face colour × `skin_shades`.
     - A two-tone sky and grass background, and a name label per model.
     - It writes `models.png` (one row per model).

**W-ICON** owns `src/icons.asm`, `src/itemmodel.asm` and `src/test_icons.asm` (new) plus `/tmp/aclooks/icons.py`.

1. **Implement `icon_paint` and `icons_build`.**
2. **Generalise the `itemmodel.asm` sprite path** to a source rect (`spr_x0`, `spr_y0`, `spr_n`, `spr_px`). The item path still feeds it the 16×16 tile from `item_icon` (n = 16), so behaviour is unchanged until Wave 3.
3. **Add `held_item_draw`** as specified and export it.
4. **`test_icons_paint`** uses a fixture 32×32 `SKBMP` with a palette of 2 entries plus a char missing from the palette.
   - Before the call, fill the cells of icons 8 and 9 (x 0 and x 32, y 544..575) with 0xAA bytes.
   - After `icon_paint(atlas, 9, bmp)`, the texels at x 32 + px, y 544 + py equal the palette colours.
   - The missing char and '.' are 0: the cell was cleared.
   - The cell of icon 8 still holds 0xAA.
5. **`icons.py`** reads `atlas.rgba` plus an item-name list taken from `itemdefs.asm` `n_*` strings in id order.
   - Per item, it draws the icon at ×4 on a parchment slot (fill 214,196,160 with a 2 px rim 58,38,24).
   - It also draws it at 16 GUI units for GUI scale 2, 3 and 4, nearest-resized to 32, 48 and 64 px.
   - It writes `icons.png`.

The integrator copies back both workers' files, runs `make test` (317 pass), and commits "looks engines: skin models and 32x32 icons".

### Wave 2: sample art and the style checkpoint

1. **A-SAMPLE-CHARS** creates `src/skins_folk.asm` (`m_folk_villagers`, `m_avatar`) and `src/skins_mobs.asm` (`m_zombie`, `m_pig`) following the style guide and briefs. It iterates with `dump` and `render.py` until its own review against the guide passes.
2. **A-SAMPLE-ICONS** creates `src/iconart_b.asm` (`ib_porkchop`, `ib_cooked_porkchop`, `ib_apple`, `ib_health_potion`, `ib_gold_coin`) and `src/iconart_a.asm` (`ib_iron_sword`, `ib_iron_pickaxe`, `ib_bow`, `ib_iron_chestplate`, `ib_revolver`). It iterates with `icons.py`.
3. **Checkpoint.** The integrator renders `models.png` and `icons.png` (samples only) and copies them to `docs/superpowers/specs/looks-mockup/`. It then asks the user with `ask`, showing both images (`<img src="docs/superpowers/specs/looks-mockup/models.png">` and the same for `icons.png`) with the two choices "Valider le style" / "Modifier (décris)".
   - On "Modifier", the same workers revise, the integrator re-renders and asks again.
   - No Wave 3 art starts before "Valider".
   - Then commit "looks art: validated style samples" with the PNGs and the art files. The art files are data only and nothing references them yet.

### Wave 3: full art and wiring (6 parallel workers)

The art workers keep the validated samples and extend their files.

- **A-MOBS** owns `src/skins_mobs.asm`: all 7 mob models.
- **A-FOLK** owns `src/skins_folk.asm`: the folk, elder, merchant, avatar and the 9 extras.
- **A-GEAR** owns `src/skins_gear.asm`, `src/skins_vehicles.asm` and `src/gunmodel.asm`.
  - It rewrites `gun_model_draw` (signature unchanged) so each gun is `skin_model_draw(models[g], 0, 0.0, light, light, light)`, plus `m_gun_warhead` for the launcher while loaded.
  - It keeps the muzzle flash exactly as today (untextured `render_box` with `tiles`, `flash_shade`).
  - It deletes `PART`, the colours and the part tables.
- **A-ICONS-1** owns `src/iconart_a.asm`: all 62 equipment icons.
- **A-ICONS-2** owns `src/iconart_b.asm`: all 31 others.
- **WIRE** owns `src/artreg.asm` (new), `render.asm`, `mobrender.asm`, `peerrender.asm`, `planes.asm`, `boats.asm`, `hand.asm`, `ui.asm`, `recipebook.asm`, `itemmodel.asm`, `itemdefs.asm`, `texgen.asm`, `common.inc`, `test_items.asm`, `test_planeitems.asm`, `test_skin.asm`, `test_icons.asm` and `selftest.asm`, and wires the game. It uses stubs for every art label.

WIRE's changes:

1. **`src/artreg.asm`** (new): `skin_models` and `item_icons32` as contracted.
2. **`render.asm` `render_init`**: after `texgen_build(atlas)`, call `icons_build(atlas, item_icons32)` and `skin_build(atlas, skin_models)`, then upload. The return value is ignored; `test_skin_models` guarantees the fit.
3. **`mobrender.asm`**
   - Delete the `PART` macro, all part tables, `models`, `folk_tables`, `mob_shades`, `DRAW_PART` and `mob_parts_draw`.
   - Add `mob_models: dq m_zombie, m_pig, m_creeper, m_skeleton, m_spider, m_chicken, m_boss, 0`, indexed by type − 1. Folk use `folk_model`.
   - `folk_model(rdi mob) -> rax body SKMODEL*, rdx extra SKMODEL* or 0` keeps today's selection rules, with labels swapped in:
     - `m_villager_elder` and `m_villager_merchant` for the Villagers' leader and trader;
     - otherwise `m_folk_<faction>` from a `folk_models` table;
     - extras `m_extra_crown`, `m_extra_hat`, `m_hood_<faction>` (acolyte guard/patrol), `m_extra_helmet`, `m_extra_pack`.
   - `mobs_render` keeps every tint, scale and flash rule. It builds a stack `SKPOSE` {0, 0.0, `MOB.wid`, 1, 1, 1}, calls `skin_model_draw(body, pose, swing, tint)`, then `skin_model_draw(extra, 0, 0.0, tint)` when there is one.
   - Update the header comment.
4. **`peerrender.asm`**
   - Draw `m_avatar` with tint (1, 1, 1), or (1, 0.4, 0.4) while `PS_HURT`.
   - Pose: flags `SKP_ARM_UP` while `PS_SWING`, arm_deg 60.0 (`f_arm_up`), held = `PSTATE.held`, accent = `peer_colors[slot]`.
   - The seat rule is unchanged (swing 0 while seated).
   - Make `peer_colors` global.
   - Delete `PARTS_ARGS` and the three-call attack path.
   - Rewrite the header comment: avatars now show the held item, and the slot colour is on the accent parts, no longer a whole-body tint.
5. **`planes.asm`**
   - Inside the existing transform, draw `skin_model_draw(m_plane, 0, 0.0, 1, 1, 1)`.
   - The pilot is `m_avatar` with pose {`SKP_SEATED`, 0, 0, accent}, where accent = `peer_colors[net_role == NET_ROLE_OFF ? 0 : net_self]`.
   - The propeller is one `skin_model_draw(m_plane_prop, …)` after the existing `glTranslatef(0, 0, c_prop_z)` and `glRotatef(prop, 0, 0, 1)`.
   - Delete `plane_model`, `PLANE_BOXES`, `blade`, `plane_blocks`, `plane_tiles`, `plane_shades`, the `.set` loop, and `c_90` if it becomes unused. Remove the `folk_tables`/`mob_parts_draw` externs.
6. **`boats.asm`**: draw `skin_model_draw(m_boat, 0, 0.0, 1, 1, 1)` in place of the 5 `render_box` calls. Delete `hull`, `hull_shades`, `plank_tiles` and its fill loop. (`hull` has no collision use: `grep -n "\[hull\]" src/boats.asm` shows only the render loop.)
7. **`hand.asm`**: the bare arm becomes `glTranslatef(−0.34375, 0, −1.05)`, `glRotatef(90, 1, 0, 0)`, then `skin_model_draw(m_avatar, pose{SKP_ARM_ONLY, 0, 0, accent as planes}, 0.0, light, light, light)`, after the existing `pose_arm`. Delete `arm_box`, `arm_tiles`, `arm_shade` and `shades`.
8. **Icons switch**
   - `ui.asm`:
     - `ui_item_icon_tint(edi id, esi x, edx y, ecx size, r8d rgba)` draws ids ≥ `FIRST_ITEM` from icon cell k with u0 = (k&7)·512 + 1, u1 = u0 + 510, v0 = (`ICON32_Y0` + (k>>3)·32)·16 + 1, v1 = v0 + 510, through `quad_uv`. Blocks keep `ui_tile_icon(item_icon[id])`.
     - `ui_item_icon` becomes `r8d = WHITE` and then a fall-through into `ui_item_icon_tint`. It is exported.
   - `recipebook.asm:918` calls `ui_item_icon_tint` with the id in place of `item_icon` + `ui_tile_icon`.
   - `itemmodel.asm`: ids ≥ `FIRST_ITEM` feed the sprite source (k&7)·32, `ICON32_Y0` + (k>>3)·32, n 32.
   - `itemdefs.asm`:
     - `item_icon` ends at `PAD_TO item_icon, FIRST_ITEM, 2, 0` with `%if $ - item_icon != FIRST_ITEM * 2` / `%error item_icon covers block ids only` / `%endif`;
     - delete the item entries, `TILE_ITEM0` users and the `TILE_ICON_PLANE0` define;
     - fix the header comment.
9. **Obsolete art**, in `texgen.asm` and `common.inc`.
   - Delete the draw calls for every tile that was an item's icon:
     - 32..42;
     - 80..138;
     - `TILE_RING`, `TILE_AMULET`;
     - the hammer and spear tiles;
     - `TILE_ICON_BOAT`;
     - `TILE_ICON_REVOLVER`..`TILE_ICON_COMP`;
     - the plane icons 368..373.
   - Delete the mob skin tiles 64..72, 74..76 and 78 (zombie ×4, pig ×2, player skin, creeper ×2, skeleton face, spider ×2, chicken face), 173..179 (villager, robes, boss) and 304..323 (faction skins).
   - Keep `TILE_CHICKEN_BODY`, `TILE_CHICKEN_LEG` and `TILE_SKELETON_BONE`: `src/arrows.asm:83-94` uses them.
   - For each removed constant, first `grep -n` it over `src/`.
     - A remaining user that depicts an item switches to `ui_item_icon`/`ui_item_icon_tint` with that item id.
     - A remaining user that depicts something else keeps the tile.
   - Delete a generator, bitmap, palette or float constant only when no remaining draw uses it (`icon_pork`, `ICON3`, `f6_5`, …).
   - Delete `FOLK_PART_SIZE`, `FOLK_PARTS`, `FOLK_BODY`, `FOLK_ARM_R`, `FOLK_HEAD` and `TILE_FOLK*`.
   - Update the free-tile comments and the texgen header to list the freed ids.
   - Removing rng-drawing mob tiles shifts the noise of every later rng tile. That is accepted: same generators, different random grain.
10. **Tests**
    - `test_items.asm`: drop the 20 faction-skin entries from `art_tiles` (keep 228, 229), and delete the `item_icon + BOAT*2` assertion (keep BED).
    - `test_planeitems.asm`: delete the icon half of `test_plane_item_tables` (the `texgen_build` call, `pi_atlas`, the pixel loop), since `test_icons_art` covers every item. Update its header.
    - Add **`test_skin_models`** to `test_skin.asm`: `skin_check(atlas, skin_models)` returns 0, and every registry model has at least one bone and the minimum part count of the style guide (a table of minimums in the test).
    - Add **`test_icons_art`** to `test_icons.asm`. For each of the 93 `item_icons32` entries:
      - the entry is non-null, with w = h = 32;
      - every row char is '.' or in its palette;
      - after `icons_build` on a test atlas, the cell has at least 64 opaque texels;
      - no two items' 32×32 cells are byte-identical.

**Integration**
1. The integrator copies back all six workers' files, builds and runs `make test` (319 pass).
2. It renders the full `models.png` and `icons.png`, copies them over the ones in `docs/superpowers/specs/looks-mockup/`, and asks the user with both images: "Valider l'ensemble" / "Modifier (décris)".
3. On changes, the owning art worker revises; then re-render and ask again.
4. Commit "looks: every model and icon redrawn, skinned renderer wired" and push.

### Wave 4: live verification, Windows, docs (integrator)

1. **omabox live shots**, in LOOKS (creative, seed 4242), each with a screenshot:
   1. A village at noon: Villagers folk with a leader, a trader and a guard.
   2. Debug-spawned zombie, skeleton (bow in hand), creeper, spider, pig, chicken and boss, lit, framed with the gdb driver.
   3. Folk of the four other factions, using the debug menu events or the World tab to find camps.
   4. Inventory and hotbar full of varied items (debug give) at GUI scales 4 and 3.
   5. Dropped items on the ground.
   6. First person: bare arm, held iron sword, held raw pork chop, held revolver.
   7. A boat on water.
   8. A plane on the ground in third person (V), propeller spinning.
   9. A two-instance multiplayer session (skill `assemblycraft-multiplayer-omabox-verify`) where the guest sees the host's avatar with its accent colour and its held item, raising the arm on attack.
2. **FPS check:** the same midnight 15-zombie scene (or 30, if the baseline was read at 30) with the new build. It must reach at least 70 % of the baseline FPS. If both readings sit at the vsync cap, the check passes.
3. **Windows:** `make windows`, then `WINEPREFIX=$HOME/.cache/x WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=d" wine build/win/assemblycraft.exe --selftest`, which must show 319 pass.
4. **Docs and tracking**
   - Add an "As built" section to the design doc and copy the final PNGs to `docs/superpowers/specs/looks-mockup/`.
   - Update README and the release notes.
   - Open the GitHub issue "Passe de détail des textures de blocs du monde (herbe, pierre, bois…)" with labels `need-triage` and `ready-for-human`, using `gh label create` first for any label that is missing.
   - Commit "looks: live check, docs" and push.

## Critical files & anchors

- `src/mobrender.asm`:
  - `PART` (`:28`), the tables (`:64-186`), `folk_model` (`:222`), `mob_parts_draw` (`:280`), `mobs_render` (`:344`);
  - the tint and scale rules to keep (`:362-513`).
- `src/render.asm`:
  - `box_draw` (`:970`) is the winding and colour model `skin_model_draw` copies;
  - `face_corners` (`:64`), `f_texscale_v` (`:36`), `render_init` (`:135-151`).
- `src/itemmodel.asm`: the sprite extrusion (`:152-311`) generalised to n×n sources; `texel_alpha` (`:292`).
- `src/texgen.asm`:
  - the header rng-order rules (`:1-36`);
  - the item icon calls (`:686-697`, `:859-905`) and mob tiles (`:714-852`, `:964-973`, `:1083-1091`) to delete;
  - `PAL`/`PALN` (`:2037`, `:2043`) to move.
- `src/ui.asm`: `ui_item_icon` (`:1054`), `ui_tile_icon` (`:1068`) and `quad_uv`, for the icon32 path.

## Verification

- **After each wave**, from the repo root: `make && make test`. Expect 314 (Wave 0), 317 (Wave 1) and 319 (Wave 3, Wave 4) pass, and no NASM warnings.
- **New behaviour checks**
  - `test_skin_uv` proves the unwrap orientation. Negative control: swap FRONT's ix rule and the test fails.
  - `test_skin_pack` proves packing, AS sharing, the paint ops and the overflow guard. Negative control: remove the overflow check and the canary or return value fails.
  - `test_skin_models` proves every shipped face is painted. Negative control: delete one `SK_FILL` from a model and the test fails.
  - `test_icons_paint` and `test_icons_art`: a typo char in a bitmap row fails, and giving two tiers the same palette fails the identical-cells check.
- **Visual checks**
  - `/tmp/aclooks/dump` + `render.py` + `icons.py` produce `models.png` and `icons.png`, reviewed by the user at both checkpoints.
  - The raw pork chop at ×4 shows meat, marbling, a fat rim and a bone knob.
- **Live omabox:** the 9 shots of Wave 4. Each named model, held item and icon must be visible and match the validated sheets, with no missing or inside-out faces and no z-fighting overlays at 10 blocks.
- **Performance:** at least 70 % of the Wave 0 FPS with 15 zombies in view.
- **Windows:** the Wine selftest passes 319.

## Assumptions & contingencies

- **Icons at 32×32** in 16-unit slots: at GUI scale 3 a texel is 1.5 px. The user accepted this; nothing compensates for it.
- **Noise grain:** removing the rng-drawn mob tiles changes the random grain of later noise tiles (ores, furnaces, chest, gravel, TNT and the 0.6+ art). It is accepted as invisible in practice.
  - If a test fails only because it pinned an exact noise-derived colour, that test pinned incidental noise. Rewrite it to assert opacity or structure.
- **Packing overflow:** if `skin_build` overflows when the real registry first runs (`test_skin_models` fails at the fit check), lower the largest unwraps first: the plane wing and the boss robe. Never grow the atlas beyond 4096 rows.
- **Performance fallback:** if FPS < 70 % of baseline, add:
  - `SKPF_DETAIL 4` (part flag) and `SKP_FAR 8` (pose flag);
  - `mobs_render` sets `SKP_FAR` when the mob is farther than 24 blocks from the camera (squared distance > 576);
  - `skin_model_draw` skips `SKPF_DETAIL` parts under `SKP_FAR`;
  - the art owners mark ears, noses, buckles, braids and similar parts `SKPF_DETAIL`.

  Re-measure afterwards.
- **Held item pose:** if `held_item_draw`'s third-person constants show the item inside the arm or floating in the Wave 4 shots, adjust only the translate values of that branch until the grip touches the fist in the front and side views, and record the values in "As built".
- **First-person arm:** if the first-person arm sits visibly off the old position, adjust only the two `hand.asm` translate values (`−0.34375`, `−1.05`) until the fist appears where the old arm box did.

## As built (0.13 looks)

- **Result:** 35 skin models (`src/skins_*.asm`, registry `src/artreg.asm`) and 93 icons (`src/iconart_a/b/c.asm`), engines `src/skin.asm` and `src/icons.asm`, 319 selftests (also under Wine). Style and the full set were validated by the user from the renders in `looks-mockup/`; the user then played it and found it very pretty.
- **Deviations from the plan:** the art was split over more files and workers (`skins_boss.asm`, `skins_folk2.asm`, `iconart_c.asm`); `skin_build` packs by shelf height descending (the four samples took 209 rows instead of 290; the whole roster uses 1229 of 3072); `test_skin_models` also pins the registry order and tpb; `TILE_STAT_COIN` (tile 138) is kept for the stat glyph; `SKMODEL.pad` became `.hscale` (held item size multiplier, the boss wields a double-size King's Blade).
- **Baseline FPS (omabox, vsync cap):** 62 for the previous build and 62 for this one, same box, fresh world, 30 zombies at about 6 blocks at midnight, read 12 s after spawning (one earlier baseline reading of 47 was a transient GPU clock state; a repeat gave 62).
- **Held items:** tools are held with the head up and forward, except the axe, which is turned so its head hangs toward the ground (`hold_orient` for other holders, `item_fp_orient` for the first-person hand).
- **Known leftovers:** the revolver in a third-person hand is mostly hidden by the fist (0.6 scale); a peer that stops walking keeps its mid-stride legs (netsync walk phase never returns to 0, pre-existing); the airplane item did nothing when placed on a snow layer (pre-existing, not investigated).
