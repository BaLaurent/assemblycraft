# AssemblyCraft 0.10.1 Terrain — climate-ordered biomes with transition biomes, roofed ravines, smaller caves with pools, lava and exposed ore

## Context

**What the user asked for.** The user finds two things wrong with the terrain:
- biome transitions make no sense (a desert right next to snow);
- the underground is bad: big holes you fall into from the surface, and big empty caves.

**Measured on seed 42** over 4096 × 4096 blocks at HEAD `112dee0`:
- desert borders plains, forest, mountains and rivers, and snow borders swamp, plains and forest;
- 5.8 % of desert cells have a snowy surface within 128 blocks;
- 79,862 land block columns are open from the surface down 60 or more blocks (ravines);
- underground air is 8.21 % of land rock between y 5 and h − 5.

**Fixed by the user (do not revisit):**
- add all four transition biomes: snowy taiga, savanna, stony shore and birch forest;
- ravines are underground only, never open to the sky;
- caves become smaller, with contents including a new LAVA block;
- existing 0.9/0.10 worlds keep loading, and visible seams between old and new terrain are accepted.

**End state:**
- biomes follow a temperature ladder, so a desert never meets snow, and surface materials blend over the borders;
- no surface opening deeper than a hillside mouth;
- caverns are smaller and flatter, with pillars, gravel and moss floors, one-deep water and lava pools, and ore exposed on the walls;
- standing in lava burns;
- `make test` passes (172 + 5 new tests = 177), and the build is warning-free.

**Repo:** `/run/media/octopusman/Games/Experiences/assemblycraft` (x86-64 NASM). The master branch has no remote.

## Conventions (all waves)

**Assembly:**
- each file has `%include "common.inc"`, `default rel`, explicit sections and its own `extern`/`global` lines;
- SysV ABI: rsp is 16-aligned at every call, rbx/rbp/r12–r15 are callee-saved, SSE is scalar;
- every function has a header comment giving its signature and contract;
- byte ids are loaded with `movzx`, and floats are floored with `roundss 9` + `cvttss2si`.

**Tests:**
- a test is `test_<name>() → eax`, where 0 is a pass;
- it starts with `call world_clear`, sets every global it uses, and cleans up after itself;
- register it in `src/selftest.asm` (`extern`, `TEST` row and `TESTNAME` row, appended in the order of this plan);
- prove every new assertion with a negative control: break the code once in a scratch copy and watch the test fail.

**Workers:**
- Each worker gets a scratch copy:
  `REPO=…; rm -rf /tmp/ac101-<w> /tmp/ac101-<w>-base && mkdir -p /tmp/ac101-<w> && rsync -a --exclude build --exclude .git --exclude .omp $REPO/ /tmp/ac101-<w>/ && rsync -a $REPO/src/ /tmp/ac101-<w>-base/`
- Use absolute paths, never run git, and edit with the edit tool (never sed/python rewrites).
- Workers write only their owned files. Fakes for sibling symbols go in `src/zz_stub.asm`, never copied back.
- **Report:** owned files, `selftest.asm` lines, the `make test` tail, stubs, deviations, negative controls, and every unowned call site that needs wiring.
- **Integration:** the integrator copies back only owned files, after a `cmp` against the base.

**Git:** only the integrator runs git, with one commit per step. Never add `.omp/` or `.asm-lsp.toml`.

**Live checks (omabox, from `$HOME`):**
1. `omabox up --audio`.
2. `H=$(omabox -b default path --home); cp build/assemblycraft "$H/.ac.new" && mv -f "$H/.ac.new" "$H/assemblycraft"`.
3. Launch with `omabox -b default run -d --wait -- /home/sbx/assemblycraft --data-dir /home/sbx/acv101 --play NAME [--creative --seed N]`.
4. The throwaway patcher `/tmp/acpatch9.py` takes `pos=x:y:z yaw= pitch= fly=1 time= origin=0:0 mode=`. `/tmp/acview10.sh` closes, patches, relaunches, presses F3 and prints the shot path. Copy it to `/tmp/acview101.sh` with `acv10` replaced by `acv101`.
5. Mouse look does not work in the box: aim with patched yaw/pitch.
6. Always patch `origin=0:0` together with absolute positions.

## Contracts (wave 0 writes these; every worker codes against them)

### `src/common.inc`

- **Biomes:** `BIOME_TAIGA 8`, `BIOME_SAVANNA 9`, `BIOME_SHORE 10`, `BIOME_BIRCH 11`, and `NUM_BIOMES 12`.
- **Spawn biomes:** `SPAWN_BIOMES` = `(1<<BIOME_PLAINS)|(1<<BIOME_FOREST)|(1<<BIOME_DESERT)|(1<<BIOME_SNOW)|(1<<BIOME_SWAMP)|(1<<BIOME_TAIGA)|(1<<BIOME_SAVANNA)|(1<<BIOME_BIRCH)`.
- **Blocks:**
  - `DRY_GRASS 135`, `LAVA 136`, `NUM_BLOCKS 137`;
  - comment: "ids 137..143 unused".
- **Tiles:** `TILE_DRY_GRASS_TOP 324`, `TILE_DRY_GRASS_SIDE 325`, `TILE_LAVA 326`. These are 16-bit tile ids; byte tiles 230 and 231 stay free and unused.
- **Moved from worldgen.asm:** `struc TCELL` (`.h .biome .top .f1 .f2 .f3 .deep .cover .cold`, 9 dwords), `%define TC_W 22` and `%define TC_CELLS 484`. Index is `(lz+3)*22 + lx+3`.
- **Cave column flags:** `CF_RAVINE 1`, `CF_PILLAR 2`, `CF_CAVERN 4`, `CF_MOUTH 8`.

### Block rows (blockdefs.asm / itemdefs.asm; same tables the SHRINE rows use)

| Table | DRY_GRASS (135) | LAVA (136) |
|---|---|---|
| flags | 3 (SOLID\|OPAQUE) | 8 (TRANSLUCENT only) |
| tiles top / side / bottom (words) | 324 / 325 / 3 (dirt) | 326 / 326 / 326 |
| hardness | 0.6 | −1.0 |
| tool | TOOL_SHOVEL | 0 |
| harvest level | 0 | 0 |
| drop | DIRT | 0 |
| dig / step sound | SND_DIG_SOFT / SND_STEP_SOFT | 0 / 0 |
| flammable | 0 | 0 |
| shape | SHAPE_CUBE | SHAPE_LIQUID |
| block_base | 0 (no item form) | 0 |
| light | 0 | 15 |
| item_names | "Dry Grass" | "Lava" |
| item_icon | 0 | 0 |
| item_max_stack | 0 | 0 |

### Module APIs

**`src/caves.asm`** (new in prep; W2 completes it):
```
gen_underground(rdi GENBUF*, rsi TCELL* tc, edx ax0, ecx az0)   ; caves, ores, gravel pockets, cave dressing, in that order
carved_at(edi ax, esi y, edx az, ecx h) -> eax 0/1             ; point query, bit-identical to gen_underground's carving
gen_carved(edi ax, esi y, edx az) -> eax 0/1                    ; gen_height + carved_at
gen_cave_flags(edi ax, esi az) -> eax CF_*                      ; for tests
```

**`src/worldgen.asm`** (W1): `gen_surface(edi ax, esi az) -> eax top, edx filler, ecx cover`. These are `TCELL.top`, `.f1` and `.cover`. The function is reentrant.

**`src/player.asm`** (W4): `body_in_liquid(rdi BODY*) -> eax` returns 0, WATER or LAVA. It replaces `body_in_water` (deleted). It probes the same two cells; WATER wins over LAVA when both are hit.

**`src/render.asm`** (prep): `render_box_px16` is `render_box_px` with word tiles. `mov eax, 1` then the same entry into `box_draw` that `render_box_px` uses.

## Design data

### Temperature ladder (W1, `terrain_cell` in worldgen.asm)

**Fields.**
- Replace T (`FBMC 9, 3, 1100`) with `FBMC 10, 2, 1700, TF_T`, which is smoother.
- M (`9, 3, 1200`), C, D, Rg and Rv are unchanged.
- Wobbles: `T' = T + 0.015·noise2(ax, az, 3, 1710)` and `M' = M + 0.015·noise2(ax, az, 3, 1711)`. These are computed for land cells only.

**Calibration** (W1's first task). Write a throwaway C helper in `/tmp/ac101-w1/cal.c`, linked like the 0.10 helpers:
```
gcc -O1 -no-pie -pthread -o cal cal.c $(ls build/*.o | grep -v '/main.o') -lglfw -lGL -lpulse-simple -lm
```
- Declare `float fbm2(int,int,int,int,int)` and `void worldgen_set_seed(int)`.
- For seed 42, sample the grid ±3072 at step 16 (the `test_worldgen_biomes` grid).
- Take the percentiles of T = fbm2(x,z,10,2,1700) and M = fbm2(x,z,9,3,1200) over **all** samples.
- Hard-code them as rodata floats rounded to 3 decimals, each with a comment naming its percentile:
  - `k_t_snow` = P14(T), `k_t_taiga` = P28(T), `k_t_swamp_lo` = P38(T), `k_t_swamp_hi` = P66(T), `k_t_savanna` = P74(T), `k_t_desert` = P86(T);
  - `k_m_plains` = P35(M), `k_m_birch` = P55(M), `k_m_desert` = P60(M).
- Also print the same percentiles for seeds 7 and 1234. Report them; they are only a check.
- Delete the old `k_snow_t`, `k_desert_t`, `k_forest_t` and `k_swamp_t` if they become unused.

**Height.** The formula is unchanged except the swamp weight:
- `bT = clamp01((T − k_t_swamp_lo)/0.02) · clamp01((k_t_swamp_hi − T)/0.02)`;
- `sw = clamp01((M − 0.25)/0.10) · bT · (1 − mtn)`;
- this replaces the "0 when T < −0.25" rule.

**Biome order.** The first rule that matches wins:
1. OCEAN: `C < −0.10`. Unchanged.
2. RIVER: unchanged.
3. MOUNTAINS: `mtn > 0.35`. Unchanged.
4. SHORE: `C < −0.05` and `Rg > 0.10`.
5. SNOW if `T < k_t_snow`; TAIGA if `T < k_t_taiga`.
6. If `T ≥ k_t_desert`: DESERT when `M < k_m_desert`, else SAVANNA. SAVANNA if `T ≥ k_t_savanna`.
7. SWAMP if `sw > 0.5`.
8. PLAINS if `M < k_m_plains`; BIRCH if `M < k_m_birch`; otherwise FOREST.

**Materials** (`.materials`; `deep` is STONE except in a desert).
- **Snow line.** For mountains: `S = 165 + 80·clamp01((T − k_t_taiga)/(k_t_desert − k_t_taiga))`. Heights are at most 240, so warm mountains never get snow.
- **cold** (water freezes at sea level) = `T' < k_t_taiga`.
- **Temperate dither**, used for PLAINS, BIRCH, FOREST, SWAMP non-mud and MOUNTAINS h < 150:
  - GRASS/DIRT;
  - top DRY_GRASS if `T' ≥ k_t_savanna`;
  - cover SNOW_LAYER if `T' < k_t_taiga`.
- **Per biome:**
  - SNOW and TAIGA: GRASS/DIRT, cover SNOW_LAYER.
  - SAVANNA: DRY_GRASS/DIRT; top SAND and fillers SAND when `T' ≥ k_t_desert` and `M' < k_m_desert`.
  - DESERT: SAND/SAND, `deep` SANDSTONE; top DRY_GRASS (fillers SAND) when `T' < k_t_desert` or `M' ≥ k_m_desert`.
  - SWAMP mud: the existing `noise2(…,3,1600) > 0.3` rule.
  - MOUNTAINS h ≥ 150: STONE/STONE; cover SNOW_LAYER if `h ≥ S`; top SNOW_BLOCK if `h ≥ S + 20`. This replaces the fixed 175/195.
  - SHORE: STONE/STONE, top GRAVEL where `noise2(ax,az,2,1720) > 0.2`; cover SNOW_LAYER if `T' < k_t_taiga`.
- **Beach:** the existing rule (`h ≤ 98` and `C < −0.06` gives SAND/SAND) applies to every land biome except SHORE. It also gets cover SNOW_LAYER when `T' < k_t_taiga`.
- **OCEAN and RIVER:** unchanged.

### Vegetation (W1)

**`veg_kind(edi biome, esi h, edx top, ecx t)`.** With `r = t & 255`:
- `h < 97`: none.
- DESERT: top SAND and `r < 2` gives cactus (4).
- SAVANNA: top DRY_GRASS and `r < 2` gives acacia (6).
- Otherwise the top must be GRASS:

  | Biome | Rule | Tree |
  |---|---|---|
  | PLAINS | `r < 1` | oak (1) |
  | FOREST | `r < 7` | oak if `t & 256`, else birch |
  | BIRCH | `r < 7` | birch (2) |
  | SNOW | `r < 3` | snowy pine (5) |
  | TAIGA | `r < 8` | snowy pine (5) |
  | MOUNTAINS | `h < 150` and `r < 2` | pine (3) |
  | SWAMP | `r < 3` | oak (1) |
  | SHORE, others | — | none |

**`plant_tree`:**
- **Kind 5:** plant the pine of kind 3, then `put_cell(lx, y_top + 1, lz, SNOW_LAYER, only_air=1)`, where `y_top` is the highest PINE_LEAVES cell the pine branch wrote on the trunk axis.
- **Kind 6 (acacia):**
  - trunk LOG over `h+1 .. h+tr` with `tr = 4 + ((t >> 8) & 1)`;
  - ground cell set to DIRT, as the other kinds do;
  - `leaf_layer(lx, h+tr, lz, r=2, skipcorners=1, LEAVES)`;
  - `leaf_layer(lx, h+tr+1, lz, r=1, skipcorners=0, LEAVES)`.

**`grass_chance`:**
- requires a top of GRASS or DRY_GRASS;
- chance by biome: PLAINS 26, FOREST 13, BIRCH 18, SWAMP 38, MOUNTAINS h<150 8, TAIGA 4, SAVANNA 40, all others 0.

**Spawn.** `gen_find_spawn` replaces `dec eax; cmp eax, 4; ja .next` with a test of the biome bit against `SPAWN_BIOMES`.

### Underground (W2, caves.asm)

**`cave_flags(edi ax, esi az, edx h, ecx slope) -> eax CF_*`** (internal):
- `CF_RAVINE`: `ravine_at(ax, az)`.
- `CF_PILLAR`: `noise2(ax, az, 2, 1750) > 0.82`.
- `CF_CAVERN`: `noise2(ax, az, 7, 1740) > −0.25`.
- `CF_MOUTH`: `noise2(ax, az, 6, 1730) > 0.55` and `h ≥ 97` and `slope ≥ 4`.
  - slope = `h − min(h(ax±3, az), h(ax, az±3))`, the four neighbours at distance 3.
  - `gen_underground` passes the slope computed from `tc`; the margin of 3 covers the neighbours.
  - `carved_at` passes `slope = −1`, which means "compute it with 4 `gen_height` calls, only once the mouth noise has passed".

**`carve_test(edi y, esi h, edx flags, xmm0 A, xmm1 B, xmm2 V) -> eax`.** Rules in order:
1. `y < 5` or `y > h`: 0.
2. `h < 97` and `y ≥ h − 4`: 0.
3. Tunnel: (`12 ≤ y ≤ 72`, or `CF_MOUTH` and `73 ≤ y ≤ h`) and `|A| < 0.07` and `|B| < 0.07`: 1.
4. Cavern: `20 ≤ y ≤ 56`, `CF_CAVERN`, not `CF_PILLAR`, and `V > k_cav_t` (start at 0.52): 1.
5. Ravine: `CF_RAVINE` and `25 ≤ y ≤ min(70, h − 10)`: 1.
6. Otherwise 0.

**Fields:**
- `cave_fields` gains a `ymul` column: tunnel A `(5, 2000, 8)`, tunnel B `(5, 2001, 8)`, cavern V `(5, 2005, 12)`.
- The lattice samples `noise3(ax0+4i, ymul·j, az0+4k, shift, salt)`.
- `cave_field` takes the new arg `r9d ymul`.

**Lattice:**
- Levels are allocated 0..61 (y up to 244). `LAT_F = 62·LAT_J`.
- The `g_cp` stride becomes `62*4` (replace every hard-coded 88/176).
- Levels `LAT_JLO..21` are always computed.
- Levels 22..`(hmax>>2)+1` are computed for tunnels A and B only when some own cell of the column has `CF_MOUTH`; `hmax` is the column's max h.
- The `gen_underground` top-y bound per cell is `h` if the cell has `CF_MOUTH`, else 72. Ravines end at 70 and caverns at 56.

**Dressing pass** (`cave_dress`, after ores and gravel pockets; three steps per column, in order):
- **Floors.** For every STONE cell with `6 ≤ y ≤ min(h − 8, 80)` and AIR directly above it in the column:
  - `f = noise3(ax, y, az, 3, 1760)`;
  - `f > 0.30` gives GRAVEL, `f < −0.30` gives MOSSY_COBBLESTONE.
- **Exposed ore.** For every STONE cell with `2 ≤ y ≤ min(h − 6, 130)` and an AIR cell among its 6 neighbours (inside the column only):
  - `r = hash32(ax, az, 4000 + y)`; if `(r & 1023) < 20`, the cell becomes an ore;
  - the ore is picked among the `ore_tab` rows whose `[ymin, ymax]` contains y, with weights coal 40, iron 30, gold 20 and diamond 10;
  - the pick is `((r >> 10) % total_weight)` walked through the eligible rows in table order.
- **Pools.**
  - `Cand(x, y, z)` holds when all of these hold:
    - `6 ≤ y ≤ 80` and `y ≤ h(x,z) − 8`;
    - the cell is carved and the cell below is not carved;
    - `noise2(x, z, 4, 1770) > 0.40`.
  - "Carved" means AIR after the cave step for in-column cells. For the 4 neighbours outside the column, use `carved_at(nx, y, nz, tc[n].h)`; the tc margin gives h.
  - `Pool = Cand ∧ every 4-neighbour n: ¬carved(n, y) ∨ Cand(n, y)`.
  - A pool cell becomes LAVA if `y ≤ 30`, else WATER.

### Liquids, burning and consumers (W4)

**`body_in_liquid` callers:**
- `player.asm:702` and `player.asm:853` treat any non-zero result as in water (swim, and the fall reset);
- `mobs.asm:855` holds jump in either liquid.

**Lava movement (`body_step`):**
- horizontal speed ×0.3 instead of ×0.5 (`c_lava_slow 0.3`);
- swim-up speed 1.5 instead of 3.0 (`c_lava_up 1.5`).

**Player burning (`survival_step`, after the breath section):**
- if `body_in_liquid(player) == LAVA`, call `combat_player_status(STS_BURN, 24)`;
- additionally, when `game_time % 10 == 0`, call `survival_damage(4, CAUSE_FIRE)`;
- `survival_step` runs in Survival only (its header comment at `survival.asm:286` says so; it is called from `game.asm:2291`), so Creative never burns;
- no lava fog; drowning is unchanged.

**Mobs:**
- At the `mob_ai` site that calls the liquid check (`mobs.asm:855`, where rbx is the mob): if the result is LAVA, compute the slot `idx = (rbx − mobs) / MOB_size`, call `status_apply(edi idx, esi STS_BURN, xmm0 24.0)`, and when `game_time % 10 == 0` call `mob_strike(edi idx, esi 4, xmm0 0, xmm1 0)`. Re-read the mob's type afterwards: a death removes it (`MOB_NONE`), and the AI then returns.
- `mob_water_ahead` treats LAVA like WATER.
- `spawn_at_ground` fails on a LAVA stand cell, next to the WATER check (`mobs.asm:2141`).
- The passive ground accepts GRASS or DRY_GRASS (`mobs.asm:2161`).

**Other blocks:**
- `placement.asm` `placeable_cell` (line ~105) treats LAVA as replaceable, like WATER.
- `mesher.asm` `.water` 14/16 top: lower the top when (id == WATER and above ∉ {WATER, ICE}) or (id == LAVA and above ≠ LAVA). This is a W3 change.

**`structures.asm`:**
- `camp_homes`:

  | Faction | Home biomes |
  |---|---|
  | villagers | plains, forest, birch |
  | bandits | forest, mountains, savanna |
  | cult | swamp |
  | beastfolk | snow, taiga, mountains |
  | stonekin | mountains |

- `village_find`: PLAINS, FOREST and BIRCH go to `.biome_ok`; DESERT, SNOW, SAVANNA and TAIGA go to `.alt`.
- Delete `camp_ground`. `build_camp` calls `gen_surface(cx, cz)` and uses eax as the top and edx as the filler of the clearing.

**`hud.asm` `biome_names`:** append "Snowy Taiga", "Savanna", "Stony Shore", "Birch Forest".

**`menus.asm` `t_version`:** "AssemblyCraft 0.10.1" (integrator).

## Approach

### Wave 0 — integrator, inline (four commits)

0. **Check the tree.** `git status` must be clean apart from `.omp/` and `.asm-lsp.toml`, at HEAD `112dee0` or later.
1. **Design doc.** Copy this plan to `docs/superpowers/specs/2026-11-08-assemblycraft-terrain-design.md` and commit "0.10.1 design: climate ladder biomes, roofed ravines, smaller dressed caves, lava".
2. **Prep A: 16-bit block tiles** (behaviour-preserving; commit "0.10.1 prep: block tiles are 16-bit").
   - `block_tiles` becomes `dw`: every `db` row becomes `dw`, `times N db` becomes `times N dw`, and the `T_*` defines are used under `dw`. The check becomes `SIZECHECK block_tiles, 6`.
   - Readers:
     - `mesher.asm` `face_tile`: `movzx eax, word [block_tiles + rcx*2]`;
     - `mesher.asm` `emit_cross`: `word [block_tiles + rdx*2 + 2]`;
     - `itemmodel.asm:84-93`: `tiles` becomes `resw 6`, word loads and stores, and calls go to `render_box16` / the new `render_box_px16`;
     - `fx.asm:496-499`: word load. The debris draw becomes `render_box16` with 6 words built by `imul rax, 0x0001000100010001` plus a 4-byte store; `zero_tiles` becomes `times 6 dw 0`, and every branch through `.call` uses `render_box16`;
     - `boats.asm:906`: `movzx eax, word [block_tiles + (PLANKS*3+1)*2]`, keeping its byte splat (the planks tile is 5);
     - `test_items.asm:1194-1204` and `1306-1316`: word loads.
   - Add `render_box_px16` to `render.asm` next to `render_box16`.
   - **Check:** `grep -n "byte \[block_tiles" src/*.asm` prints nothing; the build is warning-free; `make test` is 172/172; a live screenshot of the seed-42 village (`pos=-77.5:106:-160.5 yaw=0 pitch=20`) looks identical to the 0.10 shot (blocks, item in hand, breaking particles).
3. **Prep B: split the underground into `src/caves.asm`** (behaviour-preserving; commit "0.10.1 prep: the underground moves to caves.asm").
   - Move from `worldgen.asm` to the new `caves.asm`: `ravine_at`, `carve_test`, `BILERP`, `cave_field`, `carved_at`, `gen_carved`, `gen_caves`, `gen_ores`, `gen_gravel`, `cave_fields`, `ore_tab`, the `LAT_*` defines, `g_lat`, `g_cp`, and the cave constants they use.
   - `gen_caves`, `gen_ores` and `gen_gravel` take `(rdi GENBUF*, rsi TCELL* tc, edx ax0, ecx az0)` through the new `gen_underground`, which calls them in that order. They no longer read worldgen statics.
   - `struc TCELL`, `TC_W` and `TC_CELLS` move to `common.inc`.
   - `gen_column` calls `gen_underground(buf, g_tc, g_ax0, g_az0)` where it called the three passes.
   - `gen_vegetation` calls `carved_at` as an extern.
   - `worldgen.asm` keeps `gen_height` and `gen_biome` exported; `caves.asm` needs `gen_height`.
   - **Check:** `test_worldgen_deterministic` and the whole suite pass (172/172). Also run a throwaway C helper that FNV-hashes `gen_column` for seed 42 over columns (−8..7, −8..7) before and after the move; the hashes must be identical.
4. **Contracts** (commit "0.10.1 contracts: new biome ids, DRY_GRASS and LAVA, cave flags").
   - Write every `common.inc` item from Contracts.
   - Add the DRY_GRASS and LAVA rows to every `blockdefs.asm` / `itemdefs.asm` table.
   - Update the header comments ("0..136").
   - In `test_items.asm` (around 1344), change the "not a block / not usable" probe from `SHRINE + 5` to `NUM_BLOCKS`.
   - Tiles 324..326 stay undrawn until W3.
   - **Check:** warning-free build; `make test` 172/172.

### Wave 1 — four parallel workers (one `task` batch; commit "0.10.1 core")

| Worker | Owns | Implements | New tests (in order) |
|---|---|---|---|
| W1 Biomes | `worldgen.asm`, `test_worldgen.asm` | Calibration, the ladder, height swamp band, materials and dither, snow line, vegetation kinds 5/6, `grass_chance`, `SPAWN_BIOMES` spawn, `gen_surface`. In `test_worldgen.asm`: `biomes` (TAIGA, SAVANNA and BIRCH ≥ 2 %; SHORE and RIVER occur; land loop over 1..6, 8, 9, 11); `col_ok` uses `SPAWN_BIOMES`. | `biome_ladder` |
| W2 Caves | `caves.asm`, new `test_caves.asm` | Everything in "Underground" | `caves_reworked` |
| W3 Blocks & art | `blockdefs.asm`, `itemdefs.asm`, `texgen.asm`, `mesher.asm`, `test_items.asm`, `test_mesher.asm` | Draw tiles 324..326 after `NBMP 323` and before the font (rng order of older tiles unchanged); the lava top in the mesher; checks the contract rows | `terrain_blocks_tables` |
| W4 Liquids & consumers | `player.asm`, `survival.asm`, `mobs.asm`, `placement.asm`, `structures.asm`, `hud.asm`, `test_structures.asm`, new `test_lava.asm`, and every test file calling `body_in_water` (`grep -ln body_in_water src/test_*.asm` gives the list) | Everything in "Liquids, burning and consumers", except the mesher | `lava_burns`, `new_biome_consumers` |

**Fakes:**
- W4: `gen_surface` returns GRASS/DIRT/0.
- W2: none.
- W3: none.
- W1: none.

**Tiles (W3).** `texgen.asm` uses the existing macros:
- 324: `NOISE_PIXEL RGB(170,160,82), 192, 63` (dry grass top).
- 325: the grass-side generator of tile 2 with top colour `RGB(170,160,82)` over dirt `RGB(150,108,74)` (dry grass side).
- 326: `NOISE_PIXEL RGB(214,96,26), 160, 95`, fully opaque (lava).
- Prove the atlas is byte-identical outside 324..326 with the 0.10 dump approach (`/tmp/w5h/` harness), and save an 8× PNG of the three tiles in `/tmp`.

**Test contents** (inputs fixed; expectations from Design data):
- **`biome_ladder` (W1):**
  - Seeds 42 and 7; `gen_biome` on a 1024 × 1024 window centred on (0,0) at step 4.
  - No 4-neighbour sample pair is forbidden. The forbidden pairs are:
    - SNOW with PLAINS, BIRCH, FOREST, SWAMP, SAVANNA or DESERT;
    - TAIGA with SWAMP, SAVANNA or DESERT;
    - SWAMP with SAVANNA or DESERT;
    - DESERT with PLAINS, BIRCH or FOREST.
  - On seed 42's ±3072 step-16 grid with `gen_surface`:
    - no sample whose surface is snowy (cover SNOW_LAYER or top SNOW_BLOCK) lies within 32 blocks (2 steps) of a DESERT sample;
    - at least one PLAINS/BIRCH/FOREST sample has a DRY_GRASS top, and each such sample has a SAVANNA sample within 48 blocks;
    - at least one PLAINS/BIRCH/FOREST sample has SNOW_LAYER cover, and each has a TAIGA or SNOW sample within 48;
    - at least one SAVANNA sample has a SAND top, and each has a DESERT sample within 48.
- **`caves_reworked` (W2):** seed 42, 20 × 20 columns starting at the `gen_find_spawn` column.
  - (a) Every land cell (h ≥ 97) without `CF_MOUTH` has `gen_carved == 0` for y in 73..h.
  - (b) Every column's run of carved cells from y = h downward (through `gen_carved`) is shorter than 20.
  - (c) Generated underground air (land, y 5..h−5, after `gen_column`) is between 3.5 % and 6.5 %.
  - (d) Liquid placement: every WATER/LAVA cell with y ≤ h − 8 has a non-AIR cell below; LAVA occurs only at y ≤ 30; such WATER occurs only at 31..80. Fewer than 5 % of these pool cells have an in-column horizontal AIR neighbour at the same y.
  - (e) The window holds ≥ 1 such LAVA cell, ≥ 1 such WATER cell, ≥ 10 ore cells with an AIR 6-neighbour, ≥ 1 GRAVEL and ≥ 1 MOSSY_COBBLESTONE with AIR above at y ≤ h − 8.
  - (f) In the first window column that has a `CF_MOUTH` cell (via `gen_cave_flags`), every cell y 5..h satisfies `gen_carved` == (the block is AIR, WATER or LAVA, or it is a GRAVEL/MOSSY_COBBLESTONE floor cell; floors are not carved).
  - (g) Seed 42 columns (0,0) and (−3,5) generate identically twice.
- **`terrain_blocks_tables` (W3):**
  - the two rows of the Contracts table, field by field, including `block_tiles` words;
  - atlas tiles 324..326 are fully opaque and not black (the shrine test's check);
  - `block_light[LAVA] == 15`.
- **`lava_burns` (W4):** flat arena, Survival, the player standing in a 1 × 1 LAVA cell (feet y in the lava cell).
  - After 1 step: `combat_burn_t > 0`. After 40 steps: health < 20.
  - Creative: no burn after 40 steps.
  - `body_in_liquid` returns LAVA, WATER or 0 for three probes.
  - Forward input for 30 steps: displacement in lava is less than in water.
  - A zombie in lava: `MOB.burn_t > 0` and health below max within 40 steps.
  - `spawn_at_ground` refuses a LAVA stand cell.
  - `placeable_cell` accepts a LAVA cell.
- **`new_biome_consumers` (W4):**
  - The `hud.asm` biome name of ids 8..11.
  - A fabricated SAVANNA-centred camp (fake `gen_surface` returning DRY_GRASS/DIRT) builds its clearing top with DRY_GRASS.
  - `spawn_at_ground(MOB_PIG, …, GROUND_PASSIVE)` succeeds on DRY_GRASS.
  - `t_homes` in `test_structures.asm` mirrors the new `camp_homes`.
  - The top-block whitelist at `test_structures.asm:2790-2797` is replaced by "camp top == `gen_surface` top at the centre".

**Integration** (integrator):
1. Copy back W1–W4 in that order after a `cmp` against each base, and register the 5 new tests.
2. Build warning-free; `make test` 177/177.
3. Re-derive the hard-coded seed-42 road at `test_structures.asm:4868-4893` from the new terrain:
   - print `first_road`'s ROADEDGE (A = `ax, az`) with a throwaway gdb break or C helper;
   - set `world_origin_x = ax & ~255` and `world_origin_z = az & ~255`;
   - the claimed chunk is `(ax >> 4, az >> 4)`;
   - the stone cell's local x/z is `(ax − origin_x, az − origin_z)`;
   - the player is at `local_x − 60 + 0.5`, `local_z + 0.5`;
   - the asserted `ROADEDGE.ax/.az` are the new values.
4. Set `t_version` to "AssemblyCraft 0.10.1".
5. Run an omabox smoke on a new seed-42 world, then commit.

### Wave 2 — live verification and tuning (integrator)

1. **Helpers.** Rebuild the throwaway helpers `/tmp/ac11-helper/wgstat.c` and `/tmp/ac11-helper/snowy.c` against the new objects, and add a gen_column timing over 64 columns. Run `wgstat 42 -2048 -2048 4096` and `snowy 42 -2048 -2048 4096`.
   - **Targets:**
     - desert with a snowy surface within 64 blocks: 0.00 %;
     - within 128: ≤ 0.5 %;
     - no land column open from the surface ≥ 20 deep;
     - underground air 3.5–6.5 %;
     - mean `gen_column` ≤ 0.5 ms.
2. **Live checks**, each proven by a screenshot, on a new world `v101a`, seed 42, Creative. Find coordinates with a helper that prints the nearest sample of each biome and the nearest lava pool, water pool and mouth.
   - a. F3 shows each of "Snowy Taiga", "Savanna", "Stony Shore" and "Birch Forest" at its sample.
   - b. A savanna–desert border shows sand patches fading into dry grass, and a forest–taiga border shows patchy snow.
   - c. Snowy pines in taiga have a snow tip; acacia trees stand in savanna.
   - d. A lava pool glows in a dark cavern, with pillars and a gravel/moss floor visible.
   - e. A tunnel mouth opens into a hillside.
   - f. In Survival, stepping into lava burns: the burn pip shows and health drops; the death screen says the fire cause text.
   - g. Old world `v10a` (copied from `acv10`) still opens. A seam is visible at the old/new terrain edge; no crash.
3. Fix bugs with a regression assertion where a unit test can catch them. Commit "0.10.1 tuning from live checks" if anything changed.

### Wave 3 — review sweep (commit "0.10.1 sweep")

- **Reviewers.** Spawn 2 read-only `reviewer` subagents:
  - R1: `worldgen.asm`, `caves.asm` (bit-identity of `carved_at` vs the lattice, generator-thread statics, lattice bounds, stack alignment);
  - R2: the tile conversion files, `player.asm`, `survival.asm`, `mobs.asm`, `placement.asm`, `structures.asm`, `mesher.asm`.
- Fix every crash, corruption, softlock or broken-feature finding with a regression assertion.
- Append "As built (deviations from this plan)" and "Deferred" to the design doc, and commit.

## Critical files & anchors

- `src/worldgen.asm`:
  - `terrain_cell` (180–425): ladder, materials, `FBMC` fields;
  - `veg_kind` (1652), `grass_chance` (1713), `plant_tree` (1491);
  - `gen_find_spawn` (789–796, `dec eax; cmp eax, 4`).
- `src/caves.asm` (from worldgen 451–1393):
  - `carve_test` (489) and `carved_at` (640) must agree bit-for-bit with the `gen_caves` lattice (1011–1204);
  - the hard-coded 88/176 `g_cp` strides.
- `src/blockdefs.asm` `block_tiles` (51–145) and its readers: `mesher.asm:754-781`, `itemmodel.asm:84-93`, `fx.asm:496-499, 920-932`, `boats.asm:906`.
- `src/structures.asm`: `camp_homes` (124–131), `village_find` biome chain (566–581), `camp_ground` (2073–2095), `build_camp` (2118).
- `src/test_structures.asm`: `t_homes` (82–88), top whitelist (2790–2797), hard-coded seed-42 road (4868–4893).

## Verification

1. **Build and tests:**
   - `cd $REPO && make clean && make 2>&1 | grep -iE "warn|error"` prints nothing;
   - `make test` ends with `selftest: 177 passed, 0 failed`, three runs in a row.
2. **Greps print nothing:**
   - `grep -nE "body_in_water|camp_ground|byte \[block_tiles" src/*.asm`;
   - `grep -n "k_snow_t\|k_desert_t" src/worldgen.asm`.
3. **Terrain metrics:** the helper targets in Wave 2 step 1 are all met, and the before/after numbers are reported in a table.
4. **Live checks:** Wave 2 step 2 a–g, each with a screenshot.
5. **Determinism and threads:**
   - `test_worldgen_deterministic` and `test_caves`'s (g) pass;
   - a 2,000-block flight at render distance 16 (the 0.10 perf hook in `/tmp/ac10-perf`, re-applied to a scratch copy) has 0 frames over 50 ms after the initial load; report the max and p99.

## Assumptions & contingencies

- **Version.** This ships as "0.10.1"; the roadmap's 0.11 remains Quests. The user may rename it.
- **A biome share below 2 %** in `test_worldgen_biomes`: move that biome's percentile boundary 2 points toward giving it area (for example desert P86 → P84), recalibrate, and re-run (at most 3 times). Record the final percentiles in As built.
- **Edge-blend width.** Measure with the helper the 95th-percentile distance from a dithered column to the neighbouring biome.
  - If it is above 40 blocks, halve the wobble amplitude (0.015). If it is below 6, double it. At most two iterations.
- **Underground air outside 3.5–6.5 %:** step `k_cav_t` by ±0.02 (higher means less air) until inside; then record it.
- **Open surface drop ≥ 20** in `wgstat` or test (b):
  - first raise the mouth noise threshold 0.55 → 0.65;
  - then require `|A|, |B| < 0.05` above y 72;
  - if it still fails, drop `CF_MOUTH` carving above y 72 entirely (no mouths) and record it in As built.
- **Exposed liquid faces ≥ 5 %:** also require each candidate neighbour's own 4-neighbours to be rock or candidates (ring 2).
- **Seed-42 aggregate site tests** (≥ 5/9 crypts, ≥ 20/25 dungeons, camp coverage) failing only because terrain moved:
  - confirm the site rule itself still holds;
  - then lower the threshold to the observed value and record it in As built.
- **`gen_column` above 0.5 ms average:**
  - first compute the pool neighbours' `carved_at` only for candidates on the column border;
  - then skip `cave_dress` floors above y 56.
