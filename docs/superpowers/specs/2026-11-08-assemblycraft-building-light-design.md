# AssemblyCraft 0.7 — doors, stairs, building blocks, light, recipe book

## Context

AssemblyCraft is a Minecraft-like game written in x86-64 NASM. It lives at `/run/media/octopusman/Games/Experiences/assemblycraft` on git `master`, HEAD `297050c` "0.6: RPG". Today `make test` passes 95/95.

The user asked for:
- doors and stairs;
- "a lot of missing blocks";
- lighting, chosen as "Full light (Minecraft-like)": torches, lit furnaces and fire emit light, caves and buildings are dark;
- a recipe book in the crafting screens. It lists every recipe, filters to recipes craftable from the current inventory, and auto-fills the grid on click. The furnace gets the same book for smelting and fuels.

For blocks the user picked two families:
- **Shaped blocks:** slabs, stairs, fences, ladders, trapdoors, glass panes and torches.
- **Crafted cubes.**

The natural-world family (worldgen changes) was not picked.

Game text stays in English.

## Conventions (same as 0.6)

- **Assembly:**
  - Each file has `%include "common.inc"`, `default rel`, explicit sections and its own `extern`/`global`.
  - SysV ABI: rsp is 16-aligned at every call; rbx, rbp and r12–r15 are callee-saved; SSE is scalar only.
  - Every function gets a header comment with its signature and contract.
  - `round()` means `cvtss2si`.
- **Tests:**
  - A test is `test_<name>() → eax`, where 0 means pass.
  - It starts with `call world_clear`, sets every global it relies on, and cleans up after itself.
  - Register it in `src/selftest.asm` with `extern` + `TEST` + `TESTNAME`.
  - The Makefile globs `src/*.asm`.
- **Workers:**
  - Each worker works in a scratch copy: `rm -rf /tmp/ac-<name> && mkdir -p /tmp/ac-<name> && rsync -a --exclude build --exclude .git $REPO/ /tmp/ac-<name>/`. Keep a baseline copy as well: `rsync -a --exclude build --exclude .git $REPO/src/ /tmp/ac-<name>-base/`.
  - Use absolute /tmp paths only, and never run git in the repo.
  - Stubs and fakes for sibling symbols go in `/tmp/ac-<name>/src/zz_stub.asm` and are never copied back. Fakes needed by a test must follow this plan's contract faithfully.
  - When green, `diff -q` each owned file against the baseline, then copy back only the owned files.
  - Report the `selftest.asm` registration lines, the `make test` tail and any deviations.
- **Edits:** use the edit tool, never sed/perl/python rewrites.
- **Git:** the integrator only, with one commit per wave.
- **Live checks:**
  - Use the omabox box: `omabox up --audio` from `$HOME`.
  - Install with `H=$(omabox -b default path --home); cp build/assemblycraft "$H/.ac.new" && mv -f "$H/.ac.new" "$H/assemblycraft"`.
  - Set the US layout with `omabox -b default lua 'hl.config({input={kb_layout="us", kb_variant=""}}); return "ok"'`.
  - Close the game (which saves) with `omabox -b default lua 'hl.dispatch(hl.dsp.window.close())'`.
  - Throwaway `/tmp/acpatch.py` (ops `slot`, `pos`, `rpg`, `ranks`, `block`, `mob`, `time`, `yaw`, `pitch`, `mode`, …) must accept magic `ACRAFT03` **or** `ACRAFT04`. Its `slot=` ids use the new numbering: item id = old id + 96 for old ids ≥ 32. Examples: DIAMOND_SWORD 154, IRON_SWORD 146, STICK 128, COAL 139.

## Contracts (wave 0 writes all of these; every worker codes against them)

### Id space (`src/common.inc`)

Block ids stay 0..24. New blocks take 25..110 (`NUM_BLOCKS 111`). Ids 111..127 are unused. Items move to `FIRST_ITEM 128`.

- **Items:** each item keeps its old relative order, written as `%define STICK (FIRST_ITEM + 0)` … `%define GOLD_COIN (FIRST_ITEM + 69)`, with `NUM_ITEMS (FIRST_ITEM + 70)` = 198. `NUM_GUNS` and the PISTOL..ROCKET_LAUNCHER contiguity are unchanged.
- **Migration constants:** `%define V3_NUM_BLOCKS 25`, `%define V3_FIRST_ITEM 32`, `%define V3_NUM_ITEMS 102`.

New block ids. A variant is `base + param`, where `param = id − block_base[id]`.

|id|constant|param meaning|
|---|---|---|
|25|`SANDSTONE`||
|26|`SMOOTH_STONE`||
|27|`MOSSY_COBBLESTONE`||
|28|`CRACKED_STONE_BRICK`||
|29|`BOOKSHELF`||
|30|`WOOL`||
|31|`IRON_BLOCK`||
|32|`GOLD_BLOCK`||
|33|`DIAMOND_BLOCK`||
|34|`COAL_BLOCK`||
|35..39|`PLANK_SLAB`, `COBBLE_SLAB`, `STONE_BRICK_SLAB`, `BRICK_SLAB`, `SANDSTONE_SLAB`|bottom half only|
|40, 44, 48, 52, 56|`PLANK_STAIRS`, `COBBLE_STAIRS`, `STONE_BRICK_STAIRS`, `BRICK_STAIRS`, `SANDSTONE_STAIRS` (4 ids each)|facing 0..3|
|60..75|`WOOD_DOOR` (16 ids)|facing·4 + open·2 + upper|
|76..91|`IRON_DOOR` (16 ids)|same as WOOD_DOOR|
|92..99|`TRAPDOOR` (8 ids)|facing·2 + open|
|100..103|`LADDER` (4 ids)|support side|
|104|`TORCH`|standing, param 0|
|105..108|`TORCH_WALL` = 105|param = 1 + support side|
|109|`FENCE`||
|110|`GLASS_PANE`||

Other `common.inc` constants:
- **Directions:** `DIR_N 0` (−z), `DIR_E 1` (+x), `DIR_S 2` (+z), `DIR_W 3` (−x).
- **Shapes:** `SHAPE_NONE 0`, `SHAPE_CUBE 1`, `SHAPE_SLAB 2`, `SHAPE_STAIRS 3`, `SHAPE_DOOR 4`, `SHAPE_TRAPDOOR 5`, `SHAPE_LADDER 6`, `SHAPE_TORCH 7`, `SHAPE_FENCE 8`, `SHAPE_PANE 9`.
- **Box purposes:** `BOXES_RENDER 0`, `BOXES_COLLIDE 1`, `BOXES_SELECT 2`; `MAX_SHAPE_BOXES 9`.
- **Mesh and recipes:** `RECIPE_SIZE 13` (moved from items.asm); `MAX_CHUNK_VERTS 196608`.
- **Sounds:** `SND_DOOR_OPEN 53`, `SND_DOOR_CLOSE 54`, `NUM_SOUNDS 55`.
- **Light:** `LIGHT_SKY_FULL 0xF0` (packed sky 15 / block 0).
- **Tiles:** these 33 are all free in today's atlas, so the atlas stays 256×256 and every tile index stays a byte:
  - `TILE_DOOR_IRON_UPPER 15`
  - `TILE_SANDSTONE_TOP 61`, `TILE_SANDSTONE_SIDE 62`, `TILE_SANDSTONE_BOTTOM 63`
  - `TILE_SMOOTH_STONE 180`, `TILE_MOSSY_COBBLE 181`, `TILE_CRACKED_BRICK 182`, `TILE_BOOKSHELF 183`, `TILE_WOOL 184`
  - `TILE_IRON_BLOCK 185`, `TILE_GOLD_BLOCK 186`, `TILE_DIAMOND_BLOCK 187`, `TILE_COAL_BLOCK 188`
  - `TILE_DOOR_WOOD_LOWER 189`, `TILE_DOOR_WOOD_UPPER 190`, `TILE_DOOR_IRON_LOWER 191`
  - `TILE_TRAPDOOR 200`, `TILE_LADDER 201`, `TILE_TORCH 202`
  - `TILE_ICON_STAIRS0 240` (240..244, in material order planks, cobble, stone brick, brick, sandstone)
  - `TILE_ICON_SLAB0 245` (245..249, same order)
  - `TILE_ICON_WOOD_DOOR 250`, `TILE_ICON_IRON_DOOR 251`, `TILE_ICON_FENCE 252`, `TILE_ICON_GLASS_PANE 253`

### Block table rows (`src/blockdefs.asm`)

Every table becomes exactly `NUM_BLOCKS` entries (tiles ×3) and ends with `%if $ - <table> != NUM_BLOCKS*<size>` → `%error`. Three new tables join them:
- `block_shape` (db): `SHAPE_NONE` for AIR and FIRE, `SHAPE_CUBE` for every other old block.
- `block_base` (db): the id itself, except `FURNACE_LIT` → `FURNACE`, FIRE → 0 and AIR → 0.
- `block_light` (db) emission: FIRE 15, FURNACE_LIT 13, TORCH and TORCH_WALL variants 14, others 0.

Variant groups are emitted with `%rep`. New rows:

|ids|flags|tiles top/side/bottom|hardness|tool|harvest|drop|dig / step sound|flammable|shape|
|---|---|---|---|---|---|---|---|---|---|
|SANDSTONE|3|61/62/63|0.8|PICKAXE|1|self|STONE/STONE|0|CUBE|
|SMOOTH_STONE|3|180|2.0|PICKAXE|1|self|STONE/STONE|0|CUBE|
|MOSSY_COBBLESTONE|3|181|2.0|PICKAXE|1|self|STONE/STONE|0|CUBE|
|CRACKED_STONE_BRICK|3|182|1.5|PICKAXE|1|self|STONE/STONE|0|CUBE|
|BOOKSHELF|3|5/183/5|1.5|AXE|0|self|WOOD/WOOD|30|CUBE|
|WOOL|3|184|0.8|0|0|self|SOFT/SOFT|30|CUBE|
|IRON_BLOCK|3|185|5.0|PICKAXE|2|self|STONE/STONE|0|CUBE|
|GOLD_BLOCK|3|186|3.0|PICKAXE|3|self|STONE/STONE|0|CUBE|
|DIAMOND_BLOCK|3|187|5.0|PICKAXE|3|self|STONE/STONE|0|CUBE|
|COAL_BLOCK|3|188|5.0|PICKAXE|1|self|STONE/STONE|5|CUBE|
|slabs, stairs|1|the material's tiles (planks 5, cobble 4, stone brick 59, brick 11, sandstone 61/62/63)|the material's|the material's|the material's|the base|the material's|planks 20, others 0|SLAB / STAIRS|
|WOOD_DOOR group|0|189 for lower variants (param bit 0 = 0), 190 for upper|3.0|AXE|0|WOOD_DOOR|WOOD/WOOD|20|DOOR|
|IRON_DOOR group|0|191 lower, 15 upper|5.0|PICKAXE|1|IRON_DOOR|STONE/STONE|0|DOOR|
|TRAPDOOR group|0|200|3.0|AXE|0|TRAPDOOR|WOOD/WOOD|20|TRAPDOOR|
|LADDER group|0|201|0.4|AXE|0|LADDER|WOOD/WOOD|20|LADDER|
|TORCH, TORCH_WALL|0|202|0.0|0|0|TORCH|WOOD/WOOD|0|TORCH|
|FENCE|1|5|2.0|AXE|0|FENCE|WOOD/WOOD|20|FENCE|
|GLASS_PANE|1|10|0.3|0|0|0|GLASS/STONE|0|PANE|

The material values are:
- planks: 2.0, AXE, 0, wood sounds;
- cobble: 2.0, PICKAXE, 1;
- stone brick: 1.5, PICKAXE, 1;
- brick: 2.0, PICKAXE, 1;
- sandstone: 0.8, PICKAXE, 1.

`FLAG_SOLID` is only the coarse "full cell" answer used by `world_is_solid` (drops, particles, blink, placement support). Body collision uses shape boxes. `FLAG_OPAQUE` is set only on full opaque cubes, and it is what blocks light and culls faces.

### Item tables (`src/itemdefs.asm`, rewritten)

Every table is written with one padding macro: `PAD_TO table, id, elemsize, default` emits `default` up to entry `id`. Entries go in ascending id order, padding runs to `NUM_ITEMS`, and each table ends with the same `%if … %error` size check. This removes every literal offset (33, 41, 43, 59, 70, 82).

- **`item_names`:** the new names are "Sandstone", "Smooth Stone", "Mossy Cobblestone", "Cracked Stone Bricks", "Bookshelf", "Wool", "Block of Iron", "Block of Gold", "Block of Diamond", "Block of Coal", "Wooden Slab", "Cobblestone Slab", "Stone Brick Slab", "Brick Slab", "Sandstone Slab", "Wooden Stairs", "Cobblestone Stairs", "Stone Brick Stairs", "Brick Stairs", "Sandstone Stairs", "Wooden Door", "Iron Door", "Trapdoor", "Ladder", "Torch", "Fence", "Glass Pane".
  - Every variant id points at its base's name.
  - Ids 111..127 point at "?".
- **`item_icon`:**
  - new cubes use their side tile (62, 180..188, bookshelf 183);
  - slabs 245..249, stairs 240..244, doors 250/251, trapdoor 200, ladder 201, torch 202, fence 252, pane 253;
  - variants 0;
  - items STICK..PORKCHOP use `32 + (id − STICK)`;
  - items COAL..GOLD_COIN use `TILE_ITEM0 + (id − COAL)`.
- **`item_max_stack`:**
  - 64 for every new base id (doors and torches too);
  - 0 for non-base variants, FURNACE_LIT, FIRE, AIR and 111..127;
  - items as before.
- **`item_burn`** (steps): PLANK_SLAB 150, PLANK_STAIRS 300, WOOD_DOOR 200, TRAPDOOR 300, LADDER 300, FENCE 300, BOOKSHELF 300, WOOL 100, COAL_BLOCK 16000, plus the old entries.
- **`item_smelt`** adds STONE → SMOOTH_STONE and STONE_BRICK → CRACKED_STONE_BRICK.
- **Other tables:** tool, tier, food, attack, durability, armor and saturation are 0 for new ids; items keep their values.

### Recipes (`src/items.asm`, appended after MANA_POTION, in this order)

`recipes` and `recipes_end` become `global`. The rule: **records with the same output must be adjacent**, which already holds for axes, BOW and FLINT_AND_STEEL.

|Output|Shape|
|---|---|
|SANDSTONE ×1|2×2 SAND|
|MOSSY_COBBLESTONE ×1|2×1 `COBBLE LEAVES`|
|MOSSY_STONE_BRICK ×1|2×1 `STONE_BRICK LEAVES`|
|BOOKSHELF ×1|3×3 `P P P / S S S / P P P` (P planks, S stick)|
|WOOL ×1|2×2 STRING|
|IRON_BLOCK, GOLD_BLOCK, DIAMOND_BLOCK, COAL_BLOCK|3×3 of the ingot/gem/coal; each followed by its 1×1 reverse giving 9|
|PLANK_SLAB, COBBLE_SLAB, STONE_BRICK_SLAB, BRICK_SLAB, SANDSTONE_SLAB ×6|3×1 of the material|
|each STAIRS ×4|two adjacent records: 3×3 `M 0 0 / M M 0 / M M M`, then the mirror `0 0 M / 0 M M / M M M`|
|WOOD_DOOR ×3 / IRON_DOOR ×3|2×3 planks / iron ingot|
|TRAPDOOR ×2|3×2 planks|
|LADDER ×3|3×3 `S 0 S / S S S / S 0 S`|
|TORCH ×4|1×2 `COAL / STICK`|
|FENCE ×3|3×2 `P S P / P S P`|
|GLASS_PANE ×16|3×2 GLASS|

LEAVES becomes obtainable in W3, which makes the mossy recipes craftable in survival.

### Shapes (`src/shapes.asm`, new, wave 0)

```
; shape_boxes(edi id, esi x, edx y, ecx z, r8 out byte[6*MAX_SHAPE_BOXES], r9d purpose) -> eax count
;   boxes of block `id` standing in cell (x,y,z), as x0,y0,z0,x1,y1,z1 in 1/16 block units relative to the
;   cell's minimum corner (y1 may reach 24 for fence collision). Fence and pane read their 4 neighbours.
; cell_boxes(edi x, esi y, edx z, rcx out float[6*MAX_SHAPE_BOXES], r8d purpose) -> eax count
;   the boxes of the block in the cell, in world floats. For BOXES_COLLIDE, a cell with x or z
;   outside the world, or y < 0, is one full solid box; y >= 64 is empty.
; block_sel_bounds(edi x, esi y, edx z, rcx out float[6]) -> eax 0/1: world-float union of the SELECT boxes
; block_facing_from_yaw(xmm0 yaw degrees) -> eax DIR_*: ((int)((yaw + 45) / 90)) & 3
; dir_dx / dir_dz: global db tables {0,1,0,-1} / {-1,0,1,0}
```

Box rules, with `param = id − block_base[id]` and a 16-unit cell:
- **NONE:** 0 boxes.
- **CUBE:** `0,0,0,16,16,16`, except that COLLIDE returns 0 boxes when `FLAG_SOLID` is clear.
- **SLAB:** `0,0,0,16,8,16`.
- **STAIRS:** the slab box plus a top half by facing:
  - N `0,8,0,16,16,8`
  - E `8,8,0,16,16,16`
  - S `0,8,8,16,16,16`
  - W `0,8,0,8,16,16`
- **Panel(side), 3 thick:**
  - N `0,0,0,16,16,3`
  - E `13,0,0,16,16,16`
  - S `0,0,13,16,16,16`
  - W `0,0,0,3,16,16`
- **DOOR:** facing = param>>2, open = (param>>1)&1. One panel on side `facing` when closed, or on side `(facing+3)&3` when open.
- **TRAPDOOR:** facing = param>>1, open = param&1. `0,0,0,16,3,16` when closed; panel(facing) when open.
- **LADDER:** a panel 2 thick on side param:
  - N `0,0,0,16,16,2`
  - E `14,0,0,16,16,16`
  - S `0,0,14,16,16,16`
  - W `0,0,0,2,16,16`
- **TORCH:**
  - param 0: `7,0,7,9,10,9`.
  - Wall side s = param−1:
    - N `7,3,0,9,13,2`
    - E `14,3,7,16,13,9`
    - S `7,3,14,9,13,16`
    - W `0,3,7,2,13,9`
  - COLLIDE returns 0 boxes.
- **FENCE:** a side connects when the neighbour's shape is FENCE, or it is a CUBE with `FLAG_OPAQUE`.
  - RENDER: the post `6,0,6,10,16,10`, plus 2 rails per connected side:
    - N `7,6,0,9,9,6` + `7,12,0,9,15,6`
    - E `10,6,7,16,9,9` + `10,12,7,16,15,9`
    - S `7,6,10,9,9,16` + `7,12,10,9,15,16`
    - W `0,6,7,6,9,9` + `0,12,7,6,15,9`
  - COLLIDE: the post `6,0,6,10,24,10`, plus per connected side N `6,0,0,10,24,6`, E `10,0,6,16,24,10`, S `6,0,10,10,24,16`, W `0,0,6,6,24,10`.
  - SELECT: the same as COLLIDE with 24 → 16.
- **PANE:** a side connects when the neighbour is PANE or GLASS, or an opaque CUBE.
  - The post is `7,0,7,9,16,9`, plus arms N `7,0,0,9,16,7`, E `9,0,7,16,16,9`, S `7,0,9,9,16,16`, W `0,0,7,7,16,9`.
  - With no connection, all 4 arms are present.
  - All purposes use the same boxes.

### Save format v4 (`src/world.asm`, `src/saves.asm`)

**Magics.** `world_magic` becomes "ACRAFT04" and a new `world_magic_v3` holds "ACRAFT03". The file size is unchanged (`WORLD_FILE_SIZE` 4210688).

**`world_load`:**
- Size `WORLD_FILE_SIZE`:
  - magic v4 → ok;
  - magic v3 → `migrate_items_v3`, then ok;
  - otherwise invalid.
- v2: `convert_v2` (which stamps the v4 magic), then `migrate_items_v3`.
- v1: `convert_v1` validates hotbar ids against `V3_NUM_BLOCKS` instead of `NUM_BLOCKS`, and needs no migration.

**`migrate_items_v3()`.** It walks every ITEMSTACK in the 36 inventory slots, the 4 armor slots, and the 27 slots of every container whose kind ≠ 0:
- If `count == 0`, leave it.
- Else if `id < V3_NUM_BLOCKS`, keep it.
- Else if `V3_FIRST_ITEM ≤ id < V3_NUM_ITEMS`, add `FIRST_ITEM − V3_FIRST_ITEM` (96).
- Else zero the stack.

**`saves.asm`** accepts `m_v4` ("ACRAFT04") alongside v3 and v2 in the world list.

### Light API (`src/light.asm`, W2)

```
light_cells: resb WORLD_VOLUME (global; byte per cell = sky<<4 | block, index as blocks)
light_get(edi x, esi y, edx z) -> eax packed; y >= 64 or x/z outside -> LIGHT_SKY_FULL; y < 0 -> 0
light_fill_sky()                 ; every cell = LIGHT_SKY_FULL, dirty list emptied (world_clear calls it)
light_compute_all()              ; whole world from scratch, dirty list emptied
light_mark(edi x, esi y, edx z)  ; a cell changed opacity or emission
light_update()                   ; recompute the dirty regions, mark changed chunks dirty
light_lut_build(xmm0 bright, rdi out byte[1024])  ; 256 RGBA entries, index = packed light
light_brightness_at(xmm0 x, xmm1 y, xmm2 z) -> xmm0 scalar (hand model)
light_bind_index(edi idx)        ; glMultiTexCoord2f(GL_TEXTURE1, idx, 0.0)
light_bind_at(xmm0 x, xmm1 y, xmm2 z) ; light_bind_index(light_get(floor x, y, z))
```

### Placement API (`src/placement.asm`, W3)

```
place_block(edi item, rsi RAYHIT*) -> eax 1 placed / 0 refused
block_use(edi x, esi y, edx z) -> eax 1 if the block reacted (door, trapdoor)
block_removed(edi x, esi y, edx z, ecx old_id)   ; after the cell became AIR: door partner, support pops
block_is_usable(edi id) -> eax                   ; table, furnace (lit), chest, door, trapdoor
```

### Recipe book API (W4)

items.asm:
```
recipe_sets(rdi rec) -> eax   ; times craftable from inventory slots + current grid; 0 if anything is missing
recipe_fits(rdi rec) -> eax   ; w <= craft_size and h <= craft_size
recipe_fill(rdi rec, esi max_sets) -> eax sets placed
```

containers.asm:
```
cont_fill_from_inv(edi cell, esi id) -> eax moved
```

recipebook.asm:
```
book_reset()
book_draw(edi x, esi y, edx kind)       ; BOOK_CRAFT 0 / BOOK_FURNACE 1
book_ghost_draw(edi grid_x, esi grid_y)
book_tip: resb 192                       ; tooltip text, [0] = 0 when none
```

## Approach

### Wave 0 — contracts and the id migration (integrator, inline; commit "0.7 contracts")

1. **`common.inc`.** Add every constant in "Id space". Delete the "25..31 unused" comments. Add the `TILE_ITEM0` comment update.
2. **`blockdefs.asm`.** Rewrite the tables per "Block table rows", including the three new tables and the size checks.
3. **`itemdefs.asm`.** Rewrite with `PAD_TO` per "Item tables".
4. **`items.asm`.**
   - Append the recipes.
   - Use `RECIPE_SIZE` from common.inc.
   - Export `recipes` and `recipes_end`.
5. **`invscreen.asm`: build the creative palette at run time.**
   - `palette_build()` fills `palette: resb 256` and `palette_n` with every id from 1 to NUM_ITEMS−1 whose `item_max_stack` ≠ 0. It runs once, on the first `screen_inventory`.
   - Replace `PALETTE_N` and `PAL_ROWS` with `[palette_n]` and `(palette_n + 8) / 9` in the scroll maths.
   - Delete the static palette and its `%error`.
6. **`world.asm` / `saves.asm`.** Do the v4 magic and `migrate_items_v3` as in "Save format v4".
   - In `test_world.asm`, the existing magic checks expect "ACRAFT04" after a save or conversion.
   - Add `test_world_load_v3_migrates_items`. It writes a v3 image (magic "ACRAFT03"):
     - slot 0 = {32 (old STICK), 5};
     - slot 1 = {24, 3};
     - armor 1 = {79 (old DIAMOND_CHESTPLATE), 1};
     - container 0 = chest at a CHEST cell, cell 0 = {44 (old IRON_INGOT), 7}, cell 1 = {27, 1}.

     It saves the image with `file_write_atomic`, loads it, and expects:
     - STICK×5;
     - MOSSY_STONE_BRICK×3;
     - armor DIAMOND_CHESTPLATE;
     - container cell 0 IRON_INGOT×7 and cell 1 empty;
     - magic "ACRAFT04" after `world_save`.
7. **`structures.asm`: widen the BOX record** to `db dx0,y0,dz0,dx1,y1,dz1,id,flags`.
   - `id` is a block id 0..254, with `OP_SHELL 255` as the sentinel.
   - `flags` holds `OP_IFAIR 1` and `OP_IFSOLID 2`.
   - `run_boxes` passes `eax = id | flags<<8`. `box_fill` decodes `ebx = eax & 255` and the flags from `eax >> 8`.
   - Update every table, for example `OP_SHELL | OP_IFSOLID` → `id OP_SHELL, flags OP_IFSOLID`.
   - This step changes no behaviour.
8. **`shapes.asm` + `test_shapes.asm`.** Write `test_shapes_boxes`:
   - PLANK_STAIRS+DIR_E collide gives 2 boxes, the second `8,8,0,16,16,16`.
   - WOOD_DOOR closed N (param 0) gives the panel `0,0,0,16,16,3`; open (param 2) gives `0,0,0,3,16,16`.
   - A fence with stone at +x gives 2 collide boxes, the second `10,0,6,16,24,10`.
   - A lone pane gives 5 boxes.
   - TORCH collide gives 0 boxes and select gives 1.
   - `cell_boxes(−1,5,0,COLLIDE)` gives 1 full box.
   - `block_facing_from_yaw(91)` = DIR_E and `(359)` = DIR_N.
9. **`gl.inc`:** add `extern glMultiTexCoord2f, glClientActiveTexture`.
10. **Audit, then build.**
    - Run `grep -nE "cmp\s+[a-z0-9]+,\s*(32|43|59|70|82|101|102)\b" src/*.asm`. Every hit must be unrelated to ids; today's hits are string lengths and masks.
    - `make 2>&1 | grep -iE "warn|error"` prints nothing, and `make test` = 97/97.
    - The new shapes still render as cubes at this point.
    - Commit.

### Wave 1 — six parallel workers (one `task` batch, each owning only its files)

|Worker|Owns|
|---|---|
|W1 Render|`mesher.asm`, `render.asm`, `itemmodel.asm`, `hand.asm`, `drops.asm`, `mobrender.asm`, `test_mesher.asm`|
|W2 Light|new `light.asm`, `test_light.asm`; `world.asm`, `worldgen.asm`, `hud.asm`, `app.asm`|
|W3 Blocks|new `placement.asm`, `test_blocks.asm`; `player.asm`, `raycast.asm`, `arrows.asm`, `mobs.asm`, `game.asm`, `explode.asm`, `fire.asm`, `test_physics.asm`|
|W4 Book|new `recipebook.asm`; `items.asm`, `invscreen.asm`, `containers.asm`, `test_items.asm`|
|W5 Art + sound|`texgen.asm`, `sfx.asm`|
|W6 Structures|`structures.asm`, `test_structures.asm`|

#### W1 Render

**Mesher, full cubes.**
- Vertex positions become 1/16 block. In `mesh_chunk` every corner coordinate is `block*16 + corner_bit*16`.
- After the AO probes, each corner gets a smooth light. Average `light_get` over PV, side1, side2 and the corner cell, including side1, side2 and the corner only when non-opaque. The corner is excluded when both sides are opaque.
- Average sky and block separately and truncate. Store `sky<<4 | block` in `VERTEX.pad`.

**Mesher, shaped blocks.**
- `block_shape[id]` == NONE → skip, replacing the FIRE test.
- Shapes other than CUBE go through a new `emit_shape`:
  - Call `shape_boxes(id, x, y, z, buf, BOXES_RENDER)`.
  - Before emitting, require room for `MAX_SHAPE_BOXES*24` vertices left in `mesh_scratch`. Otherwise skip the block.
  - For each box, emit its 6 faces as quads using `face_corners` with min/max substituted.
  - Skip a face lying on the cell boundary (for example +X with x1 == 16) when that neighbour is `FLAG_OPAQUE`.
  - Shade is `face_shade[face*4+3]`.
  - Light is `light_get` of the boundary neighbour for boundary faces, otherwise of the cell itself, on all 4 corners.
- Texcoords: tile from `block_tiles[id*3 + slot]` (top, side or bottom). Pixel coordinates are in 1/16 cell units (+Z means the face whose normal is +Z):
  - +X: u = 16−z, v = 16−y
  - −X: u = z, v = 16−y
  - +Y: u = x, v = z
  - −Y: u = 16−x, v = z
  - +Z: u = x, v = 16−y
  - −Z: u = 16−x, v = 16−y

  Then `tex = tilecol*256 + u*16` (and the same for v), clamped to `[base+1, base+255]`. For a full box this reproduces today's mapping.

**Render.**
- The chunk pass is wrapped in `glPushMatrix` / `glScalef(0.0625,0.0625,0.0625)` / `glPopMatrix`.
- Unit 1 changes:
  - `white_tex`, `white_px`, `env_rgba` and the constant-colour combiner are deleted.
  - Unit 1 binds a 256×1 RGBA `lightmap_tex` (`GL_NEAREST`, clamp) with combine `MODULATE(PREVIOUS, TEXTURE)`. Alpha stays `REPLACE(PREVIOUS)`.
  - The unit-1 texture matrix is `translate(1/512, 0.5, 0) · scale(1/256, 1, 1)`, set in `render_init`.
- Each frame where the old night block ran:
  - `light_lut_build(bright, lut_buf)`;
  - re-upload with `TEXIMAGE 256, 1, lut_buf` on unit 1.
- Chunk loop:
  - `glClientActiveTexture(GL_TEXTURE1)`, enable `GL_TEXTURE_COORD_ARRAY`, `glTexCoordPointer(1, GL_SHORT, VERTEX_SIZE, VERTEX.pad)` per chunk.
  - Then `glClientActiveTexture(GL_TEXTURE0)` for the existing pointer.
  - Disable the unit-1 array after the loop, then `light_bind_index(LIGHT_SKY_FULL)` before the entity passes.
- Target outline and crack: use `block_sel_bounds`, with margins −0.002/+0.002, and skip when it returns 0.
- Add `render_box_px(rdi box float[6], rsi tiles byte[6], rdx shades float[6], xmm0-2 rgb, rcx px byte[6])`. It is `render_box` with texcoords from the cell-relative px box, using the mesher's formula.

**Item models.**
- Add `item_model_is_block(edi id) -> eax` in `itemmodel.asm`: 1 when `id < NUM_BLOCKS` and the shape is CUBE, SLAB or STAIRS.
- `item_model_draw`:
  - CUBE: as today.
  - SLAB and STAIRS (the item is the N-facing base): draw the RENDER boxes with `render_box_px`, the box mapped to model space as px/16 − 0.5.
  - Every other block id: the sprite path from `item_icon`.
- `hand.asm` and `drops.asm` use `item_model_is_block` instead of `cmp NUM_BLOCKS`.

**Entity light.**
- `mobs_render` calls `light_bind_at(x, y + height/2, z)` per mob.
- `drops_render` calls `light_bind_at(x, y+0.25, z)` per drop.
- Both restore `light_bind_index(LIGHT_SKY_FULL)` afterwards.
- `hand.asm` replaces `sky_brightness` with `light_brightness_at(eye)`.

**Tests.** Use a faithful fake `light_get` reading `light_cells`.
- The existing mesher counts stay.
- `test_mesh_slab_half_height`: a lone PLANK_SLAB gives 24 vertices, max vertex y = y*16+8.
- `test_mesh_stairs_quads`: lone stairs give 48 vertices.
- `test_mesh_light_packed`: stone at (5,5,5), with every `light_cells` cell set to 0x00 except (5,6,5) = 0xE7 and its 8 horizontal neighbours at y=6 = 0xE7. All 4 +Y vertices then have pad 0xE7.

#### W2 Light

**`light.asm`, per the API.** Bss:
- `light_cells` (4 MB);
- `light_prev` (4 MB, for change detection);
- a ring queue of `1<<22` dwords (a full queue skips the push);
- `light_dirty` with up to 16 regions `{x0,x1,z0,z1}` covering full height.

Opaque means `block_flags & FLAG_OPAQUE`; emission is `block_light[id]`.

**`recompute(region)`:**
1. Columns top-down: `s = 15`. At the first opaque cell `s = 0`. Each cell's sky = (opaque ? 0 : s). Block = emission, which an opaque emitter (FURNACE_LIT) keeps too.
2. Seeds:
   - region cells with sky 15 that have a non-opaque 6-neighbour with sky ≤ 13;
   - region cells with block ≥ 2;
   - for partial regions, every non-opaque cell just outside the 4 horizontal faces with sky ≥ 2 or block ≥ 2. These outside cells are read-only sources.
3. BFS: pop c. For each 6-neighbour n inside the region that is non-opaque, compute `sky' = sky(c)−1` and `block' = block(c)−1` (floored at 0). If either beats n, raise that channel and push n.
4. Partial regions only: compare each cell with `light_prev` (copied before step 1). For every changed cell, call `world_mark_cell_dirty`.

`light_compute_all` = recompute(whole world), with no boundary seeds and no comparison.

**`light_mark`** expands the cell to `[x−16,x+16]×[z−16,z+16]` (clamped). It unions the result into the first overlapping or touching dirty region, else appends it, else unions it into region 0 when all 16 are used. **`light_update`** recomputes every region in turn and empties the list.

**`light_lut_build`:**
- `curve[16] = {0.04, 0.0565, 0.0867, 0.126, 0.172, 0.224, 0.283, 0.346, 0.414, 0.486, 0.562, 0.643, 0.727, 0.815, 0.905, 1.0}`.
- For index i = s<<4 | b: rgb = max per channel of (`curve[s]·bright` on each of r, g, b) and (`curve[b]·(1.0, 0.93, 0.80)`). The byte is round(·255) and alpha is 255.
- `light_brightness_at` = max(`curve[s]·bright`, `curve[b]`), where `bright = sky_brightness(game_time)`.

**`world.asm` hooks.**
- `world_set` reads the old id first. When `(flags_old ^ flags_new) & FLAG_OPAQUE` or `block_light[old] != block_light[new]`, it calls `light_mark`.
- Factor the 3×3×3 chunk marking out of `world_set` into a global `world_mark_cell_dirty(edi x, esi y, edx z)`, and make `world_set` call it.
- `world_clear` calls `light_fill_sky`.
- `world_load` calls `light_compute_all` before `world_mark_all_dirty`.

**Other files.**
- `worldgen.asm`: `world_generate` calls `light_compute_all` right before `world_mark_all_dirty`, after `structures_generate`.
- `hud.asm`: the F3 "Light:" line becomes "Light: sky S block B (D%)", with S and B from `light_get` at the player's feet cell and D = sky brightness ×100.
- `app.asm`: call `light_update` right before `render_update_chunks` in the main loop.

**Tests (`test_light.asm`):**
- `test_light_sky_and_shadow`:
  - World: stone floor y 10, a 5×5 stone roof at y 20 centred on (40,40).
  - After `light_compute_all`: (40,25,40) sky 15, (40,19,40) sky 12, (43,19,40) sky 15.
- `test_torch_light_falloff`:
  - World: a hollow stone cube from (20,10,20) to (30,20,30), shell 1 thick, TORCH at (25,15,25).
  - Block light is 14 at the torch, 13 at (26,15,25), 10 at (29,15,25), and 0 at (32,15,25) outside.
- `test_light_update_on_change`:
  1. World: a stone plate at y 10 over x 30..70, z 30..70; then `light_compute_all`.
  2. `world_set` a STONE at (40,30,40), zero all of `chunk_dirty`, then `light_update`.
     - (40,29,40) has sky 14.
     - (40,11,40) has sky 14.
     - `chunk_dirty[34]` (chunk cx 2, cy 0, cz 2) is set. Only the light change can mark it, since `world_set` marks chunks around y 30.
  3. Then a TORCH at (60,11,60) with `light_update`: block 14.
  4. Then remove it with `light_update`: block 0.
- `test_light_lut`:
  - With bright 0.25: entry 0xF0 = (64,64,64,255), entry 0x0E = (231,215,185,255), entry 0x00 = (10,9,8,255).

#### W3 Blocks

**`player.asm`.**
- `body_intersects_block(rdi body, esi x, edx y, ecx z, r8d id)` tests the body box against `shape_boxes(id, …, BOXES_COLLIDE)`.
- `move_axis(body, axis, d)` is rewritten as a swept clip:
  - Scan cells overlapping the body box extended by d on the axis, with the y lower bound lowered by 1 for tall fence boxes.
  - For every `cell_boxes(…, BOXES_COLLIDE)` box that strictly overlaps the body on the two other axes:
    - if d > 0 and `box.min ≥ body.max − c_eps`: `d = min(d, box.min − body.max − c_eps)`;
    - if d < 0 and `box.max ≤ body.min + c_eps`: `d = max(d, box.max − body.min (+ c_eps on x and z; exactly 0 extra on y))`.
  - Apply d. If clipped: velocity on that axis = 0; y moving down sets `on_ground`; x or z sets `blocked`.
- **Step-up in `body_step`.** It needs `dx = vx·dt` and `dz = vz·dt` kept from before the horizontal moves. If not flying, `on_ground` after the y move, and `blocked` after x/z:
  1. save x, y, z, vx, vz;
  2. reset x and z to their pre-move values;
  3. `move_axis(y, +0.6)`, then x by dx, then z by dz, then `move_axis(y, −raised)`;
  4. keep the result only if the horizontal distance covered beats the unstepped one by > 1e-4, and then set `blocked = 0`; otherwise restore.
- **Ladders.** Before the y move, if not flying and any cell overlapped by the body has shape LADDER:
  - `fall = 0`;
  - `vy = 2.4` when `INPUT.fwd ≠ 0` or `jump`;
  - `vy = 0` when `INPUT.down`;
  - otherwise `vy = max(vy, −2.4)`.

**`raycast.asm`.** Save origin and dir in callee-saved registers and track `t_enter` (0 for the origin cell, otherwise the tMax value used to step into the cell).
- Cell shape NONE → pass. CUBE → hit at `t_enter`.
- Other shapes → `ray_aabb` against each SELECT box (world floats, `tmax = maxdist`). The nearest hit is the hit; with no hit, pass.
- Return xmm0 = hit t (unchanged for callers that ignore it).

**`arrows.asm`.** Replace the cell-box `ray_aabb` with `S_TMAX = raycast's xmm0`.

**`mobs.asm`.**
- `mobs_intersect_block(edi x, esi y, edx z, ecx id)` passes id to `body_intersects_block`.
- `spawn_at_ground` fails for hostile types when `light_get(x, top+1, z) & 15 ≥ 8`.

**`placement.asm`.**
- **`place_block`:**
  1. Refuse if item ≥ NUM_BLOCKS or `max_stack` is 0.
  2. b = target.b, p = target.p.
  3. **Slab merge:** if the item's shape is SLAB, `world_get(b) == item` and `p == b + up`, set b to the material's full block. The table is PLANK_SLAB→PLANKS, COBBLE_SLAB→COBBLE, STONE_BRICK_SLAB→STONE_BRICK, BRICK_SLAB→BRICK, SANDSTONE_SLAB→SANDSTONE. Refuse instead if the player or a mob intersects the full block.
  4. Otherwise cell c = p, which must be in the world and AIR.
  5. Choose the variant, with `f = block_facing_from_yaw(player yaw)`:
     - STAIRS: base+f.
     - TRAPDOOR: base+f·2.
     - DOOR: base+f·4. Also needs u = c+up in the world and AIR, and `world_is_solid(c−up)`.
     - LADDER: needs `n = p−b` horizontal and b `FLAG_OPAQUE`; base + dir(b−p).
     - TORCH: n = +y with `world_is_solid(b)` → TORCH; n horizontal with b opaque → TORCH_WALL + dir(b−p); otherwise refuse.
     - Anything else: the item itself.
  6. Entity checks: `body_intersects_block(player, c, v)` and `mobs_intersect_block(c, v)`, and for doors also u with v+1.
  7. FURNACE and CHEST create their container (moved here from game.asm).
  8. `world_set` c (and u = v+1 for doors).
  9. Play `block_dig_sound[v]` at volume 0.8 with `audio_play`.
- **`block_use`:**
  - DOOR: XOR 2 on this half and on the partner (y−1 if upper, else y+1, when it shares the same `block_base`). Play `SND_DOOR_OPEN` if now open, else `SND_DOOR_CLOSE` (`audio_play_at` the cell centre, 0.8).
  - TRAPDOOR: XOR 1, same sounds.
- **`block_removed`:**
  - For a DOOR, clear the partner half to AIR.
  - Then pop unsupported neighbours:
    - (x,y+1,z) when it is a standing TORCH or a DOOR lower half;
    - each horizontal neighbour that is a LADDER or TORCH_WALL whose support side points back at (x,y,z).
  - A pop sets AIR, recurses `block_removed` on that cell, and in survival calls `drops_spawn(block_drop[popped], 1)` at the cell centre.

**`game.asm`.**
- `.not_use` calls `place_block(held, &game_target)` in place of its inline placement. On success: `hand_swing`, plus `inv_consume_held(1)` in survival.
- The `.use` chain calls `block_use(b)` first. On 1, `hand_swing` and go to `.pick`.
- `want_guard` uses `block_is_usable`.
- `remove_target_block` calls `block_removed` after `world_set` AIR.
- Pick-block uses `block_base[id]` (0 → nothing), replacing the FURNACE_LIT special case.
- Survival break of LEAVES with `item_tool` == TOOL_AXE drops LEAVES and skips the apple roll.

**`explode.asm` and `fire.asm`.**
- Both call `block_removed` after their AIR writes.
- `tnt_render` and `fire_render` call `light_bind_at` per entity or fire, then restore `LIGHT_SKY_FULL`.

**Tests.** `test_physics.asm`: the `body_intersects_block` call passes STONE. New file `test_blocks.asm`:
- `test_step_up_slab_not_block`:
  - World: a stone floor at y 10 over x 15..30, z 15..25. The player is at (20.5,11,20.5), yaw 90, holding fwd.
  - A row of PLANK_SLAB at (21..25,11,20): after 40 steps x > 21.3 and y = 11.5.
  - A STONE at (21,11,20) instead: x stays < 21.
- `test_stairs_then_block`:
  - Same floor, with PLANK_STAIRS+DIR_E at (21,11,20) and a STONE row at (22..27,11,20).
  - Walking +x for 60 steps ends with y = 12 and x > 22.3.
- `test_door_blocks_until_opened`:
  - WOOD_DOOR+DIR_E·4 lower at (22,11,20), plus the upper half (+1) at (22,12,20).
  - Walking +x for 40 steps keeps x < 22.8.
  - After `block_use(22,11,20)`, both halves have the open bit set. The open panel is on side N at z 20..20.1875, clear of the player box at z 20.2..20.8, and 40 more steps reach x > 23.5.
- `test_ladder_climb`:
  - A LADDER+DIR_E column at (21,11..14,20) against a stone column at (22,11..15,20).
  - The player is at (21.5,11,20.5), yaw 90, holding fwd. After 40 steps y ≥ 12.0.
- `test_fence_cannot_jump`: a FENCE row at x 22, z 18..22. Fwd + jump held for 60 steps keeps x < 22.1.
- `test_place_variants`:
  - stairs with yaw 90 → PLANK_STAIRS+1;
  - door with yaw 0 → 60 at c and 61 above;
  - slab on a slab's top → PLANKS;
  - torch on a wall face → TORCH_WALL + dir;
  - torch on a top face → TORCH;
  - ladder on a top face refused (returns 0).
- `test_door_break_removes_pair_and_support`:
  - Breaking a door's lower half via `block_removed` clears the upper.
  - TORCH_WALL+DIR_E supported by stone at +x: removing the stone and calling `block_removed` sets the torch to AIR and spawns one TORCH drop (survival).
- `test_raycast_shapes`:
  - A ray from (20.5, 11.75, 20.5) along +x passes over a PLANK_SLAB at (21,11,20) and hits STONE at (22,11,20), with t = 1.5.
  - The same ray from (20.5, 11.25, 20.5) hits the slab cell, with t = 0.5 and p = (20,11,20).

#### W4 Book

**`items.asm`.**
- **`recipe_sets`:** for each distinct ingredient id, `floor((inv_count(id) + grid count of id) / uses)`. Take the minimum, capped by the smallest `item_max_stack` among the ingredients.
- **`recipe_fill`:**
  1. Return 0 if `!recipe_fits` or `recipe_sets == 0`.
  2. `return_stack` each of the 9 grid cells.
  3. n = min(max_sets, `recipe_sets` from the inventory alone).
  4. Each shape cell (r,c) with id ≠ 0 becomes `grid[3r+c] = {id, n}`. Items come from slots 0..35 in order; an ingredient with `max_stack` 1 moves its slot stack as is, keeping dmg.
  5. `craft_update`, then return n.

**`containers.asm`.** `cont_fill_from_inv`: when the open container's cell is empty, or holds the same id with dmg 0, move `min(max_stack − count, inv_count(id))` items, one at a time with `inv_remove_one`.

**Layout constants:** `BOOK_W 124`, `BOOK_GAP 2`.

**`invscreen.asm`.**
- `screen_begin(edi show_counts, esi with_book)`. With a book, `s_px = max(BOOK_W+BOOK_GAP, (ui_w − (BOOK_W+BOOK_GAP+PANEL_W))/2 + BOOK_W+BOOK_GAP)`, and the book sits at `(s_px − BOOK_W − BOOK_GAP, s_py)`.
- `container_begin(edi with_book)`.
- Books appear in the survival inventory (2×2), `screen_crafting` (3×3, both modes) and `screen_furnace` (kind FURNACE). The chest and the creative inventory have none.
- On `app_entered`, call `book_reset` before `check_close`.
- After `draw_grid`, call `book_ghost_draw(grid x, grid y)`.
- `draw_overlay`, with an empty cursor, shows `book_tip` when non-empty, else the old hover tooltip.

**`recipebook.asm`.**
- **Entries** are built once:
  - craft: the first record of each run of adjacent records with the same output, plus the run length;
  - smelt: every id with `item_smelt` ≠ 0;
  - fuel: every id with `item_burn` ≠ 0 and `max_stack` ≠ 0.
- **Panel** (`PANEL_COL` + `EDGE_COL` frame):
  - label "Recipes" at (6,6);
  - `ui_button` at (4,16, w 116) toggling `book_filter`. Its label is "Show: All" / "Show: Craftable" for craft, "Show: All" / "Show: In inventory" for the furnace.
  - Furnace only: a second `ui_button` at (4,38, w 116) toggling "Smelting" / "Fuel".
  - A 6-column grid of 18×18 cells from (6, top), with top = 40 for craft and 62 for the furnace. It shows `(166 − top − 6)/18` rows.
  - A scrollbar track at x 116 like the creative palette's.
  - The wheel scrolls only while the mouse is over the panel, and scroll resets on `book_reset`.
- **Cells:** `ui_item_icon(output)` plus a count when > 1.
  - Overlay `RGBA(150,30,30,90)` when not craftable or not owned, and `RGBA(0,0,0,140)` when the recipe does not fit 2×2.
  - The "Craftable" filter hides both kinds.
  - A hovered cell gets a frame `RGBA(255,255,255,120)`.
- **Tooltip** in `book_tip`:
  - craft: `"<Name>[ x<cnt>]: <n> <Ing>, <n> <Ing>"`, plus `" - needs a Crafting Table"` or `" - missing items"`;
  - smelt: `"<In> -> <Out>"`, plus `" - none in inventory"`;
  - fuel: `"<Fuel>: smelts <a.b> items"`, where a.b = burn·10/SMELT_STEPS shown in tenths.
- **Clicks:**
  - craft cell that fits with `recipe_sets` ≥ 1 → `recipe_fill(first craftable record of the run, shift ? 64 : 1)`, play `SND_CLICK` and clear the ghost;
  - craft cell that fits but is not craftable → ghost = the first record;
  - smelt or fuel cell with the item owned → `cont_fill_from_inv(0 or 1, id)`.
- **`book_ghost_draw`:**
  - For each ghost shape cell with id ≠ 0 whose grid cell is empty: `ui_tile_icon(item_icon[id], x+1, y+1, 16, RGBA(255,255,255,90))`, plus `ui_rect RGBA(200,40,40,70)` when inventory + grid hold fewer than the recipe uses.
  - The ghost clears when `inv.result` ≠ 0, on `book_reset`, or when another book cell is clicked.

**Tests (`test_items.asm`):**
- Add a `CASE` row to `test_craft_advanced_recipes` for every new recipe, including both stair mirrors, both directions of the storage blocks and the mossy pair.
- `test_recipe_fill_and_sets`:
  - With `craft_size` 3 and 4 IRON_INGOT + 3 STICK in slots: the IRON_PICKAXE record has `recipe_sets` = 1.
  - `recipe_fill(…, 1)` gives the pickaxe pattern in the grid, result IRON_PICKAXE, 1 ingot and 1 stick left.
  - With 10 LOG: `recipe_fill(planks record, 64)` gives grid cell 0 = LOG×10 and result PLANKS×4.
- `test_recipe_fits_grid`: with `craft_size` 2, the CRAFTING_TABLE record fits, the IRON_PICKAXE record does not, and `recipe_fill` on it returns 0 and leaves the grid untouched.
- `test_furnace_book_fill`: an open furnace container and 70 IRON_ORE in the inventory. `cont_fill_from_inv(0, IRON_ORE)` moves 64 and leaves 6. A COAL fill into cell 0 then moves 0.

#### W5 Art and sound

**`texgen.asm`: the 33 tiles.** Draw them after the 0.6 RPG tiles and before the font. The atlas must stay byte-identical outside these tiles; prove it with a dump harness, as in 0.6. Contents, by tile:

|Tile|Content|
|---|---|
|61, 62, 63 (sandstone top, side, bottom)|Pale tan. The side has horizontal strata and a darker band at the top.|
|180 (smooth stone)|Light grey with a faint outline.|
|181 (mossy cobble)|Cobble with green moss.|
|182 (cracked stone bricks)|Stone bricks (tile 59 pattern) with dark cracks.|
|183 (bookshelf side)|Planks frame with 2 shelves of coloured book spines.|
|184 (wool)|Off-white with a soft knit noise.|
|185 (block of iron)|Light grey plates with bevel.|
|186 (block of gold)|Bright yellow plates with bevel.|
|187 (block of diamond)|Cyan plates with bevel.|
|188 (block of coal)|Near-black noise.|
|189, 190 (wooden door lower, upper)|Plank door. Lower: 2 panels and a handle at the right, rows 1..2. Upper: 2×2 transparent window panes (alpha 0) in a wood frame.|
|191, 15 (iron door lower, upper)|Riveted grey plates; the upper has a barred window.|
|200 (trapdoor)|Plank frame with 4 transparent holes.|
|201 (ladder)|Rails at columns 2–3 and 12–13, rungs every 4 rows, everything else transparent.|
|202 (torch)|Transparent except columns 7–8: rows 6–7 flame (255,230,120)/(255,160,40), rows 8–15 wood (120,85,45).|
|240..244 (stair icons)|The material's texture masked to a stair silhouette: rows 8–15 full width, rows 0–7 right half.|
|245..249 (slab icons)|Rows 8–15 of the material texture, the rest transparent.|
|250, 251 (door icons)|Each door's art squeezed into columns 4–11.|
|252 (fence icon)|Two plank posts and two rails.|
|253 (glass pane icon)|A thin glass frame.|

Report a 6× crop PNG path.

**`sfx.asm`: 2 sounds.**
- `SND_DOOR_OPEN`: a creak, low saw 220 → 180 Hz over 0.25 s, plus a click.
- `SND_DOOR_CLOSE`: a thud, low-passed noise burst plus square 90 Hz over 0.15 s.
- Peaks must be in [−18, −0.1] dBFS. Report a peak table.

#### W6 Structures

**Houses** (`build_village`).
- Replace the AIR door carve with a closed door: lower `WOOD_DOOR + f·4` at `(door x, vy+1, door z)` and upper `+1` at vy+2.
- f is the direction of the door offset from the house centre: dx −2 → W, +2 → E, dz −2 → N, +2 → S.
- Add a wall torch inside, against the wall opposite the door and one cell aside from its window (the window sits mid-wall at vy+2).
  - For a door on the x axis (dx ≠ 0) the torch goes at `(hx − dx/2, vy+2, hz+1)`.
  - For a door on the z axis it goes at `(hx+1, vy+2, hz − dz/2)`.
  - The id is `TORCH_WALL + opposite(f)`, where `opposite(d) = (d+2)&3`.

**Dungeon tunnel** (`stair_step`).
- The floor box becomes `STONE_BRICK_STAIRS + DIR_W` (3 wide).
- The exit column also gets `STONE_BRICK_STAIRS + DIR_W` at `(X, Yf, z−1..z+1)` with flag `OP_IFSOLID` before `stair_exit`.

**Torches.**
- Dungeon rooms: `TORCH_WALL+DIR_N` at (ox, 10, oz−4) and (ox+14, 10, oz−4), and `TORCH_WALL+DIR_S` at (ox+14, 10, oz+18).
- Crypt: `TORCH_WALL+DIR_E` at (cx+3, 9, cz−4) and (cx+3, 9, cz+4), and `TORCH_WALL+DIR_W` at (cx−3, 9, cz−4) and (cx−3, 9, cz+4).

**Tests.**
- `test_village_built_with_npcs`: expect the door lower variant at house 0's door cell `(vx+7, vy+1, vz)`, which is `WOOD_DOOR + DIR_W*4`, and the upper above it.
- Add a check in that same test for the torch at `(vx+10, vy+2, vz+1)`, which is `TORCH_WALL+DIR_E` (supported by the plank wall at vx+11).
- `test_dungeon_built_with_chests`:
  - The tunnel floor cell at column 1 is `STONE_BRICK_STAIRS+DIR_W`.
  - The room torch is present.
  - The existing tunnel-walk check stays green.

### Wave 2 — integration (integrator)

1. **Merge.** Register every wave-1 test, build, and run `make test`: expect 115 passed, 0 failed. Fix integration breaks in the owners' style.
2. **Live verification** (below), then fix what it shows.
3. Commit "0.7: doors, stairs, building blocks, light, recipe book".

## Critical files & anchors

- **`src/world.asm`:** `world_set`, `world_load` (`.v3`), `convert_v1:330`. This is the light hook and the v4 migration; old 0.5/0.6 saves depend on it.
- **`src/mesher.asm`:** `mesh_chunk` — the FIRE skip at :123 becomes the shape dispatch, and the corner/texcoord emit runs at 1/16 precision with light in `VERTEX.pad`.
- **`src/render.asm`:** `render_init` (unit-1 combiner), the night block at :475 and the chunk loop at :515. The lightmap replaces the night constant there; the UI pass already turns unit 1 off (`ui.asm:169`).
- **`src/player.asm`:** `move_axis`/`body_step` — the box collision, step-up and ladder. Every mob and the primed TNT share this code.
- **`src/game.asm`:** section 9 `.use`/`.not_use` (≈968–1128), `want_guard`, `remove_target_block`, pick-block (≈1139). Placement moves into `placement.asm`.

## Verification

1. **Build and tests.** `make clean && make 2>&1 | grep -iE "warn|error"` prints nothing, and `make test` ends `selftest: 115 passed, 0 failed`.
2. **Old saves.**
   - Copy `/tmp/rpg06_crypt.acw` (a 0.6 world, magic "ACRAFT03") into the box as `rpg06.acw` and play it.
   - The hotbar still shows Diamond Sword, Health Potion, Cooked Porkchop and Gold Coin.
   - A crypt chest opened with RMB lists coins, diamonds and potions by their right names.
   - After closing, the file is 4210688 bytes with magic "ACRAFT04".
3. **Blocks**, in creative on a fresh world `--play b07 --creative --seed 42`:
   - Every new block is in the palette, with distinct icons and names.
   - Stairs face the way the player looks, and walking into them climbs without jumping.
   - Slab on slab becomes a full block.
   - A door is placed 2 tall, toggles with RMB (with sound), and breaking it drops one Wooden Door in survival.
   - A trapdoor toggles.
   - In survival, holding forward on a ladder climbs it.
   - A fence row cannot be jumped.
   - A pane joins to glass and to other panes.
   - Torches stand on floors and lean on walls, and a wall torch drops when its wall is mined.
   - The hand and dropped items show stairs and slabs in 3D, and doors, torches and ladders as sprites.
4. **Light.**
   - At night (`time=50000`) on open ground, a torch lights a warm circle. Standing in the cell next to it, F3 shows "block 13", and 7 cells away it shows "block 7".
   - By day, a dug 1×2 tunnel 6 blocks into a hill is dark at its end and lit around a placed torch.
   - A lit furnace and fire glow.
   - Dungeon rooms and the crypt are lit by their torches.
   - Mobs near a torch at night are lit.
   - No zombie spawns within the circle of a torch-lit area at night: watch 2 game-minutes on a torch grid.
5. **Recipe book.**
   - In survival with 4 planks + 2 sticks: the 2×2 book shows the crafting table as craftable, and the pickaxe dimmed with "needs a Crafting Table".
   - "Show: Craftable" hides the non-craftable recipes.
   - At a table, clicking Wooden Pickaxe fills the 3×3 grid; shift-click on Planks with 10 logs fills 10.
   - A missing recipe shows a red ghost.
   - The furnace book lists Iron Ore → Iron Ingot, and its Fuel tab lists Coal "smelts 8.0 items". Clicking Iron Ore moves ore into the input slot.
6. **Structures** (seed 42, coordinates from the F3 "Sites" line):
   - Village houses have closed doors and a lit interior.
   - The dungeon tunnel is walkable to the bottom and back up without pressing jump.
7. **Performance**, with audio off (`PULSE_SERVER=unix:/nonexistent`) and `vsync=0` in `acv3/settings.cfg`:
   - FPS ≥ 150 in the village.
   - Timed with a throwaway `glfwGetTime` print, `light_compute_all` on seed 42 takes ≤ 400 ms.
   - Placing or removing a torch takes ≤ 5 ms in `light_update`.

## Assumptions & contingencies

- **GL names.** If `glMultiTexCoord2f` or `glClientActiveTexture` fails to link, use the ARB names `glMultiTexCoord2fARB` and `glClientActiveTextureARB`, which the Linux GL ABI always exports.
- **Light timing.** If `light_compute_all` exceeds 400 ms, seed sky BFS only from columns whose height differs from a neighbour column's, plus cells under overhangs found in pass 1 (same results). If `light_update` exceeds 5 ms, shrink the per-change region from ±16 to ±15. The light cannot travel farther.
- **Bookshelf recipe** uses sticks, because books need paper, which does not exist.
- **Mossy recipes** use LEAVES. Leaves broken with an axe drop as an item, and every other tool keeps the 1-in-16 apple roll.
- **Slabs** are bottom-half only and stairs are never upside down; placement never picks the upper half.
- **Light is not saved.** It is recomputed on every load and generation.
- **Mesh capacity.** If a chunk ever needs more than `MAX_CHUNK_VERTS`, the shaped blocks that do not fit are skipped. Full cubes always fit, at most 98304 vertices.

## As built (deviations from this plan)

- **Recipe records** keep the 0.6 layout `w, h, out id, out count, cells[9]`; only the size moved to `RECIPE_SIZE` in common.inc.
- **Wall torches** have `block_base` TORCH, so `param = id − TORCH` is 0 standing or 1 + support side, and `TORCH_WALL + dir` = 105 + dir.
- **`block_facing_from_yaw`** adds 1485 (45 + 16·90) before dividing, so negative yaws map correctly too.
- **Sky light is uniform per face.** The vertex carries one packed `sky<<4 | block` index into a 1-D lightmap, and interpolating an index whose sky differs between corners would sweep through unrelated block levels. Block light stays smooth per corner; each face's sky is the truncated average of its corners.
- **`light_mark` merges regions transitively,** so queued regions never touch. Cells just outside a partial region feed it even when opaque (a lit furnace is opaque and emits 13). Measured on seed 42: `light_compute_all` takes 8.7 ms, and a torch `light_update` under 0.6 ms.
- **Ladders climb** only when moving forward (`INPUT.fwd > 0`) or jumping, so holding back does not climb.
- **`RAYHIT.p` for shaped blocks** is the neighbour across the selection-box face the ray entered, so aiming at a slab top from the side places on top. Cube hits are unchanged.
- **Book widgets:** `screen_begin`/`container_begin` take `with_book` = 0 for none or 1 + `BOOK_CRAFT`/`BOOK_FURNACE`. The filter choice survives `book_reset`.
- **Tooltips** wider than the screen wrap onto a second line, preferring the break before a " - " suffix.
- **Hostile spawning in light** is covered by an extra phase of `test_mob_spawn_rules`: block light 8 everywhere means no hostile spawns at night.
