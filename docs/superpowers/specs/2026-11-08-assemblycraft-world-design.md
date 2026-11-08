# AssemblyCraft 0.9 — World: an infinite streamed world with a floating origin, biomes, caves, water and boats, per-region sites, and beds

## Context

AssemblyCraft is an x86-64 NASM Minecraft-like game at `/run/media/octopusman/Games/Experiences/assemblycraft` (git `master`, HEAD `c2ebb98` = the V1 roadmap commit on top of 0.8 `626bc8b`; `make test` = 129/129 in 0.45 s; no git remote). Today the world is a fixed 256×64×256 flat `blocks` array (`world.asm`, index `(y<<16)|(z<<8)|x`), one `.acw` file per world (32768-byte header + blocks), light in two flat 4 MiB arrays, 1024 fixed render chunks, and every entity position is an absolute float32.

Milestone 0.9 of `docs/superpowers/specs/2026-11-08-assemblycraft-v1-roadmap.md` replaces that with:
- an infinite world: 16³ chunks, 256 tall, streamed around the player, generated on a worker thread, saved in region files;
- a floating origin, so there is no world border;
- 6 biomes plus oceans and rivers, two cave layers and ravines;
- water with swimming, breath and drowning, and a craftable boat;
- a per-region site planner (villages, dungeons, crypts, reserved faction-camp clearings).

The user also asked for **beds**: sleeping skips the night, and a bed sets the respawn point.

The user decided:
- **Sleep:** Minecraft-like (only at night, refused with a hostile within 8 blocks, any bed use sets the respawn point).
- **World size:** truly infinite, through a floating origin rather than a border.
- **Old saves:** 0.6–0.8 worlds are dropped.

End state: every 0.8 system keeps working on the new world. `make test` = 154/154, and the build is warning-free. The omabox live checks in Verification pass. A design doc with an "As built" section is committed.

## Conventions (as 0.8, with these changes)

- **Assembly:**
  - Each file has `%include "common.inc"`, `default rel`, explicit sections and its own `extern`/`global`.
  - SysV ABI: rsp is 16-aligned at every call; rbx, rbp and r12–r15 are callee-saved; SSE is scalar. Every function has a header comment with its signature and contract.
  - Zero-extend ids before indexing (`movzx`). Block ids, ITEMSTACK, DROP and recipe ids are bytes and are never `movsx`'d.
  - Coordinates are signed: use `sar` (never `shr`) to get chunk or region coordinates, and floor floats with `roundss 9` + `cvttss2si`.
- **Tests:**
  - A test is `test_<name>() → eax` (0 = pass). It starts with `call world_clear`, sets every global it relies on, and cleans up after itself, including temp files and dirs under `/tmp`.
  - Register it in `src/selftest.asm` with an `extern`, a `TEST` row and a `TESTNAME` row, in the order this plan lists.
  - Expectations come from the formulas here. The owner of a test file rewrites any expectation this plan changes.
- **Workers:**
  - Each worker gets a scratch copy: `rm -rf /tmp/ac9-<name> /tmp/ac9-<name>-base && mkdir -p /tmp/ac9-<name> && rsync -a --exclude build --exclude .git --exclude .omp $REPO/ /tmp/ac9-<name>/ && rsync -a $REPO/src/ /tmp/ac9-<name>-base/`.
  - Use absolute /tmp paths only and never run git.
  - Symbols that a sibling owns go in `/tmp/ac9-<name>/src/zz_stub.asm` as stubs, or as faithful fakes when the worker's tests depend on their behaviour.
  - A minimal scratch-only patch to a file the worker does not own is allowed to emulate a sibling's contract. It is reported and never copied back.
  - When green, the worker diffs against its base. It reports its `selftest.asm` lines, the `make test` tail, its stubs and patches, and any deviations.
  - The integrator copies back only owned files, after a `cmp` against the base to catch drift.
- **Edits:** use the edit tool, never sed/perl/python rewrites. Git is for the integrator only: one commit per wave. Never add `.omp/` or `.asm-lsp.toml`.
- **Live checks** (omabox, as in 0.8):
  - Start with `omabox up --audio` from `$HOME`.
  - Install with `H=$(omabox -b default path --home); cp build/assemblycraft "$H/.ac.new" && mv -f "$H/.ac.new" "$H/assemblycraft"`.
  - Set the US layout with `omabox -b default lua 'hl.config({input={kb_layout="us", kb_variant=""}}); return "ok"'`.
  - Launch with `omabox -b default run -d --wait -- /home/sbx/assemblycraft --data-dir /home/sbx/acv9 --play NAME [--creative --seed N]`.
  - Close (which saves) with `omabox -b default lua 'hl.dispatch(hl.dsp.window.close())'`.
  - For FPS and frame-time checks, launch with `env PULSE_SERVER=unix:/nonexistent` and `vsync=0` in `settings.cfg`. Otherwise the audio pacing caps the game at ~47 FPS.
  - The user does gameplay testing. The agent runs the mechanical and visual checks listed in Verification.
- **Throwaway patcher `/tmp/acpatch9.py`** (never committed; written in wave 2):
  - It edits `<data>/worlds/NAME/world.hdr`, magic "ACRAFT06", with the WORLDHDR v6 offsets below.
  - Ops:
    - `slot=N:id:count[:dmg]` (156+4N), `time` (16), `health` (136), `sel` (152), `mode` (12);
    - `pos=x:y:z` (68, local floats), `origin=ox:oz` (300, 304);
    - `bed=x:y:z` (308..320, sets `bed_set` 1);
    - `boat=i:x:y:z:yaw` (332+16i, `boat_count` 328 = max(i+1, old));
    - `mobs=N` (1024), `mob=i:typeword:hp:dx:dy:dz` (1028+20i, relative to the player);
    - `rpg=class:level` (960, 961).
  - Item ids are those of the new `common.inc` (STICK 144 … DIAMOND_SPEAR 223, BOAT 224).
- **Deferred items:** the repo has no remote, so AGENTS.md's GitHub-issue rule cannot be applied. List deferred items in the final report.

## Decisions (fixed; workers do not revisit them)

1. **Floating origin.**
   - `world_origin_x`/`world_origin_z` (int32, multiples of 512) map the local frame to absolute block coordinates: absolute = local + origin.
   - Everything outside `world.asm`, `region.asm`, `stream.asm`, `worldgen.asm`, `noise.asm` and `structures.asm` (planning and stamping) works in local coordinates: every float position, every int cell passed to `world_*`, raycast results, sites in the runtime cache.
   - When the player's local |x| or |z| reaches 1024, `game_rebase` shifts by `dx = (floor(x) sar 9) shl 9` (and dz alike). It calls `world_rebase(dx, dz)` and every module's `*_shift(dx, dz)`, which subtract dx/dz from their stored positions. Floats subtract `cvtsi2ss(dx)`; multiples of 512 below 2^24 are exact.
   - Absolute coordinates are int32 and wrap at ±2^31 blocks. That is about 15 years of walking, so it is left unhandled.
2. **Storage.**
   - A 64×64 toroidal column table `columns[(acz & 63)·64 + (acx & 63)]`. A slot is valid only if its `cx`/`cz` match.
   - The keep radius is at most 18 < 32, so two loaded columns never share a slot.
   - Each column holds 16 chunk pointers into a static `.bss` pool of `POOL_CHUNKS` = 24576 chunks of 8192 bytes: 4096 block bytes, then 4096 packed-light bytes, both indexed `(ly<<8)|(lz<<4)|lx`. The pool is 192 MiB virtual; Linux only commits touched pages.
   - Chunks `0..top>>4` of an installed column are always allocated.
   - A null pointer means all AIR with light 0xF0. It is allocated on the first non-AIR `world_set`, or the first light write ≠ 0xF0.
3. **Threads.**
   - One generator thread (glibc `pthread_create`; glibc ≥ 2.34 has it in `libc.so.6`, and the Makefile adds `-pthread` to the link line) runs only `gen_column` into one of 8 private `GENBUF`s.
   - The main thread owns the column table, the pool, light, meshing, GL, region I/O and containers.
   - Generation code (`worldgen.asm`, `noise.asm`, `structures_stamp`) may keep file statics, because exactly one thread runs it at a time: the worker during a session, or the main thread in selftests where no worker exists.
   - Functions the main thread calls during a session (`gen_height`, `gen_biome`, `region_plan`, `hash32`, `noise2`, `noise3`, `fbm2`) are reentrant: stack only, read-only `gen_seed`.
4. **Light runs on the main thread** (a deviation from the roadmap's "light on the worker").
   - A newly installed column is lit with its own 16×16×256 region. Seeds come from LIT neighbours; missing or unlit neighbours count as dark.
   - Increases are then propagated into LIT neighbours.
   - Light only ever increases while loading, so the result is the same in any lighting order (`test_light_column_order` proves it).
   - Edits keep 0.7's region recompute (`light_mark`/`light_update`).
   - Light is never saved. It is recomputed on load, as today.
5. **Saves.**
   - A world is a directory `<base>/worlds/<Stem>/` holding `world.hdr` (WORLDHDR v6, magic "ACRAFT06") and `regions/r.<arx>.<arz>.bin` (32×32 columns per region).
   - Only columns that are modified (`CF_MODIFIED`) or hold containers (`CF_CONTS`) are written. Every other column regenerates identically from the seed.
   - Region writes are in place or appended, and are not crash-atomic. That is deferred to 1.0 per the roadmap. The header write stays atomic (tmp + rename).
   - Pre-0.9 `.acw` files are listed as "0.8 world (can't open)", can be deleted, and are never opened or modified.
6. **Ids.** Block ids must stay below `FIRST_ITEM` and items below 256 (byte ids). 0.9 needs 19 new block ids and 17 are free, so `FIRST_ITEM` moves from 128 to 144. That leaves blocks 130..143 and items 225..255 free for 0.10.
7. **Atlas.** The atlas becomes 256×512 px. The font moves from y 192 to y 256 (`FONT_Y`). That frees tiles 192–199, 208–215 and 224–231 (24 tiles, all below 256) for the new art, so tile ids stay bytes everywhere. Texcoords stay in 1/16-px units, and only the texture matrix's v scale changes, from 1/4096 to 1/8192 (`render.asm` and `ui.asm`).
8. **Mobs and entities under streaming.**
   - When a column unloads, the mobs, drops, primed TNT and fires inside it are removed. Arrows, particles and damage numbers expire on their own.
   - Village NPCs are not saved (as in 0.8). `structures_step` re-creates a missing merchant or elder while its village centre column is ready and near the player. Mobs in columns that are not LIT are frozen (no AI or physics).
   - Boats persist in the header (max 16) and are frozen while their column is not LIT.
9. **Containers** move from the header to a runtime table `conts[MAX_CONTAINERS=256]` with absolute int32 coordinates. They are written into their column's region blob, and a column holds at most `MAX_COL_CONTS` = 64 of them. Fires are never saved: FIRE is written as AIR.
10. **Sites.**
    - `region_plan(arx, arz)` is pure.
    - The runtime cache `sites[]` holds the 3×3 regions around the player in local coordinates. It is rebuilt when the player's region changes and after a rebase.
    - Persistent site state (dungeon kills, cleared, crypt boss defeated) lives in `WORLDHDR.sites`, as `SITESTATE` records keyed by (region, slot). `RPGSAVE.cleared` and `RPGSAVE.flags` bit 0 are retired.
    - `MOB.origin` = SITESTATE index + 1; `ORIGIN_CRYPT` is removed.

## Contracts (wave 0 writes `common.inc`; every worker codes against all of this)

### `src/common.inc`

**Removed (final state; wave 0 step 3.1 keeps the first nine until the wave-1 integration):**
- `WORLD_X`, `WORLD_Y`, `WORLD_Z`, `WORLD_VOLUME`, `CHUNKS_X`, `CHUNKS_Y`, `CHUNKS_Z`, `NUM_CHUNKS`, `WORLD_FILE_SIZE`;
- `WORLD_V4_HDR`, `WORLD_V4_SIZE`, `WORLD_BASE_HDR`, `WORLD_V2_SIZE`, `WORLD_V1_SIZE`, `WORLD_V1_HDR`, `V1_*`, `V3_*`;
- `ORIGIN_CRYPT` (wherever it is defined), `ATLAS_PX`.

**World and streaming:**

```
WORLD_H 256            CHUNK 16 (kept)        COL_CHUNKS 16
COL_GRID 64            MAX_COLUMNS 4096       CHUNK_BYTES 8192   ; light at +4096
POOL_CHUNKS 24576      REGION_COLS 32         SEA_LEVEL 96
REBASE_AT 1024         REBASE_STEP 512        MAX_RENDER_DIST 16
COL_FREE 0  COL_PENDING 1  COL_BLOCKS 2  COL_LIT 3
CF_MODIFIED 1  CF_CONTS 2
GEN_SLOTS 8            GB_FREE 0  GB_REQ 1  GB_BUSY 2  GB_DONE 3
MAX_GEN_CHESTS 16      MAX_COL_CONTS 64       MAX_CONTAINERS 256
BIOME_OCEAN 0 PLAINS 1 FOREST 2 DESERT 3 SNOW 4 SWAMP 5 MOUNTAINS 6 RIVER 7, NUM_BIOMES 8
SITE_CAMP 4            MAX_REGION_SITES 9     MAX_SITES 81       MAX_SITESTATES 1024
SS_CLEARED 1           FAC_VILLAGERS 0 BANDITS 1 CULT 2 BEASTFOLK 3 STONEKIN 4, NUM_FACTIONS 5
MAX_BOATS 16           MAX_MOBS 64            MAX_BREATH 600     CAUSE_DROWN 11
FLAG_TRANSLUCENT 8     ; drawn in the blended pass (WATER, ICE)
SHAPE_BED 10  SHAPE_CROSS 11  SHAPE_LIQUID 12  SHAPE_SNOW 13  SHAPE_CACTUS 14
ATLAS_W 256  ATLAS_H 512  FONT_Y 256
SYS_PREAD64 17  SYS_FSTAT 5  SYS_RMDIR 84  O_RDWR 2  O_CREAT 0x40  SEEK_END 2  DT_DIR 4  DT_REG 8
```

**Structs:**

```
struc COLUMN                    ; 408 bytes
  .cx: .cz: resd 1 each         ; absolute chunk coordinates
  .state: resd 1                ; COL_*
  .flags: resd 1                ; CF_*
  .dirty: resd 1                ; bit cy = chunk cy needs a remesh
  .top:   resd 1                ; highest non-AIR y, -1 if none
  .chunks: resq COL_CHUNKS      ; 0 = all AIR, light 0xF0
  .biome: resb 256              ; BIOME_* at (lz<<4)|lx
endstruc
struc GENCHEST                  ; 16 bytes: a chest the generator placed; loot is rolled on install
  .x: .y: .z: resd 1 each       ; absolute cell
  .table: resd 1                ; 0 dungeon, 1 crypt (place_chest's loot tables)
endstruc
struc GENBUF
  .cx: .cz: resd 1 each         ; absolute chunk coordinates
  .state: resd 1                ; GB_*
  .session: resd 1
  .top: resd 1
  .nchests: resd 1
  .nconts: resd 1               ; containers decoded from a region blob
  .pad: resd 1
  .blocks: resb 65536           ; (y<<8)|(lz<<4)|lx
  .biome: resb 256
  .chests: resb MAX_GEN_CHESTS * GENCHEST_size
  .conts: resb MAX_COL_CONTS * CONTAINER_size
endstruc
struc CONTAINER                 ; 136 bytes, runtime table conts[], absolute coordinates
  .x: .y: .z: resd 1 each
  .kind: resb 1                 ; 0 free, CONT_FURNACE, CONT_CHEST
  .pad0: resb 3
  .slots: resb 27*4
  .burn: .burn_max: .cook: resw 1 each
  .pad: resb 6
endstruc
struc SITE                      ; 56 bytes; absolute in region_plan output, local in sites[]
  .kind .index .x .y .z .lo_x .lo_y .lo_z .hi_x .hi_y .hi_z (as today) ; index = faction for camps
  .rx: .rz: resd 1 each         ; its region
  .slot: resd 1                 ; its index in region_plan's output
endstruc
struc SITESTATE                 ; 12 bytes
  .rx: .rz: resd 1 each
  .slot: .kind: .kills: .flags: resb 1 each   ; flags SS_CLEARED
endstruc
struc BOAT                      ; 76 bytes; boats[MAX_BOATS] in boats.asm
  .body: resb BODY_size         ; local; y = bottom; yaw = heading
  .used: resd 1
  .speed: resd 1                ; float, blocks/s along yaw
endstruc
struc BOATSAVE                  ; 16 bytes: x, y, z, yaw floats (local)
SURVIVAL: append .breath (steps, 0..MAX_BREATH) and .drown_timer
```

**WORLDHDR v6** (32768 bytes; `%error` checks the size; every offset is load-bearing for the patcher and `saves_rename`):

|offset|field|notes|
|---|---|---|
|0|magic[8]|"ACRAFT06"|
|8 / 12 / 16|seed, mode, time||
|20|name[33], pad0[3]||
|56 / 60 / 64|spawn_x / spawn_y / spawn_z|world spawn cell, **absolute**|
|68|player (BODY)|**local**|
|136..152|health, food, saturation, exhaustion, sel|as today|
|156|inventory (144)|as today|
|300 / 304|origin_x / origin_z||
|308..316|bed_x / bed_y / bed_z|absolute foot cell|
|320|bed_set|0/1|
|324|breath||
|328|boat_count||
|332|boats (16 × BOATSAVE = 256)||
|588|pad_a → 944||
|944|armor (16)|as today|
|960|rpg (RPGSAVE 64)|as today; `.cleared` and `.flags` bit 0 are no longer used|
|1024|mob_count||
|1028|mobs (64 × MOBSAVE = 1280)|local floats|
|2308|site_count|number of used SITESTATEs|
|2312|sites (1024 × 12 = 12288)||
|14600|pad1 → 16384||
|16384|jewelry (16)|as today|
|16400|rpgx (256)|as today|
|16656|pad2 → 32768||

**Block ids:**
- New: WATER 111, ICE 112, SNOW_LAYER 113, SNOW_BLOCK 114, MUD 115, TALL_GRASS 116, CACTUS 117, PINE_LOG 118, PINE_LEAVES 119, BIRCH_LOG 120, BIRCH_LEAVES 121.
- BED 122..129 is one variant group with `block_base` 122 and param = id − 122: bit 2 = head half, bits 0–1 = facing (the direction from foot to head, `DIR_*`). Feet are 122..125 and heads 126..129. The item is BED (122).
- `NUM_BLOCKS` 130.

**Item ids:** `FIRST_ITEM` 144 (every item keeps its offset: STICK 144 … DIAMOND_SPEAR 223). BOAT = `FIRST_ITEM + 80` = 224, and `NUM_ITEMS` = `FIRST_ITEM + 81`.

**Tiles** (bytes):

|tile|id|tile|id|
|---|---|---|---|
|TILE_WATER|192|TILE_BIRCH_LOG|210|
|TILE_ICE|193|TILE_BIRCH_LEAVES|211|
|TILE_SNOW|194|TILE_BED_HEAD_TOP|212|
|TILE_MUD|195|TILE_BED_FOOT_TOP|213|
|TILE_TALL_GRASS|196|TILE_BED_HEAD_SIDE|214|
|TILE_CACTUS_SIDE|197|TILE_BED_FOOT_SIDE|215|
|TILE_CACTUS_TOP|198|TILE_ICON_BED|224|
|TILE_PINE_LOG|199|TILE_ICON_BOAT|225|
|TILE_PINE_LOG_TOP|208|TILE_BUBBLE|226|
|TILE_PINE_LEAVES|209|TILE_BUBBLE_POP|227|

Tiles 228–231 stay free.

### Module APIs (owner in brackets; coordinates are local unless marked absolute)

**world.asm [W1]**

```
world_get(edi x, esi y, edx z) -> eax id            ; column not LIT or y outside 0..255 -> AIR
world_set(edi x, esi y, edx z, ecx id)              ; ignored unless LIT and 0<=y<256; allocates a null chunk
                                                    ; (pool empty -> ignored, stderr "chunk pool full" once);
                                                    ; light_mark on opacity/emission/translucency change; dirty
                                                    ; marks; CF_MODIFIED. Preserves rdi, rbx
world_is_solid(x,y,z) -> eax                        ; y<0 -> 1, y>255 -> 0, column not LIT -> 1
world_is_opaque(x,y,z) -> eax                       ; not LIT or out -> 0
world_top_y(edi x, esi z) -> eax                    ; highest non-AIR y; -1 if none or not LIT
world_column_ready(edi x, esi z) -> eax 0/1         ; the column holding (x, z) is LIT
world_biome_at(edi x, esi z) -> eax BIOME_* or -1
world_mark_cell_dirty(edi x, esi y, edx z)          ; dirty bits of the 3x3x3 chunk neighbourhood in loaded columns
world_clear()                                       ; tests: drop every column without saving, origin 0, then LIT empty
                                                    ; columns for acx, acz in [-1, 16] (x, z -16..271)
world_origin_x, world_origin_z (dd, global)
world_rebase(edi dx, esi dz)                        ; origin += (dx, dz); no data moves
world_column(edi acx, esi acz) -> rax COLUMN* / 0   ; slot holds exactly that column (any non-FREE state)
world_chunk(edi acx, esi acy, edx acz) -> rax ptr/0 ; chunk data of a column in state >= BLOCKS
world_install(rdi GENBUF*) -> eax 0 / -1            ; -1: pool or container table cannot take it (nothing changed)
world_unload(rdi COLUMN*)                           ; the caller already saved it; game_unload_box(x0,z0,x1,z1),
                                                    ; containers freed, render_column_freed(slot), chunks freed, FREE
world_save_dirty(rdi world_dir) -> eax 0 / -errno   ; region_write_column for LIT columns with CF_MODIFIED|CF_CONTS;
                                                    ; clears CF_MODIFIED
world_header (WORLDHDR, global), columns (global table), chunk_pool_used (dd)
```

**light.asm [W1]** — `light_get(x,y,z)` returns 0xF0 for a column that is not LIT or y > 255, and 0 for y < 0.
- New: `light_column(rdi COLUMN*)` (→ COL_LIT) and `light_compute_all()`, which recomputes every LIT column from zero.
- `light_mark`, `light_update`, `light_bind_at`, `light_bind_index`, `light_brightness_at` and `light_lut_build` keep their signatures.

**region.asm [W1, new]**

```
region_set_dir(rdi world_dir)                        ; "" or 0 = no saving (panorama, tests)
region_read_column(edi acx, esi acz, rdx GENBUF*) -> eax 1 found+decoded / 0 absent or corrupt
region_write_column(rdi COLUMN*) -> eax 0 / -errno   ; encodes blocks + its containers from conts[]
region_flush_cache()                                 ; forget cached region tables (session end)
```

**stream.asm [W1, new]**

```
stream_begin(edi seed, rsi world_dir or 0)          ; drop all columns (no save), worldgen_set_seed, session++,
                                                    ; region_set_dir
stream_end(edi save)                                ; save -> world_save_dirty; unload everything
stream_update(edi cx, esi cz, xmm0 budget_s)        ; one frame around local (cx, cz): unload, collect, dispatch,
                                                    ; install, light
stream_area_ready(edi x, esi z, edx r) -> eax 0/1   ; every column within Chebyshev r of (x, z) is LIT with dirty == 0
stream_thread_start() / stream_thread_stop()        ; app init / exit; without a thread stream_update generates inline
stream_spiral (dd pairs dx, dz), stream_spiral_n    ; offsets for radius <= 18, nearest first
stream_stats(rdi out dd[4])                         ; loaded, pending, lit, pool chunks used
```

**worldgen.asm [W3]** and **noise.asm [W3, new]**

```
worldgen_set_seed(edi seed)                          ; read-only during a session
gen_column(rdi GENBUF*)                              ; generator thread / tests only; calls structures_stamp
gen_height(edi ax, esi az) -> eax                    ; reentrant; terrain surface y (before caves, trees, sites)
gen_biome(edi ax, esi az) -> eax BIOME_*             ; reentrant
gen_find_spawn(rdi out dd[3])                        ; absolute spawn cell (y = gen_height + 1)
gen_carved(edi ax, esi y, edx az) -> eax 0/1         ; reentrant; the cave/ravine carve decision
hash32 (moved from worldgen.asm), noise2(edi x, esi z, edx shift, ecx salt) -> xmm0,
noise3(edi x, esi y, edx z, ecx shift, r8d salt) -> xmm0, fbm2(edi x, esi z, edx shift, ecx octaves, r8d salt) -> xmm0
```

**structures.asm [W4]**

```
region_plan(edi arx, esi arz, rdx SITE* out) -> eax count     ; reentrant, absolute, at most MAX_REGION_SITES
structures_stamp(rdi GENBUF*)                                  ; generator thread only
structures_fill_chest(rdi CONTAINER*, rsi GENCHEST*)           ; main thread, deterministic loot
structures_refresh()                                           ; rebuild sites[] around the player
(no column hook: structures_step re-creates missing village NPCs, see Sites)
structures_step(), structures_reset(), structures_nearest(edi kind, esi uncleared_only) -> rax SITE*
structures_on_mob_killed(edi origin), structures_on_boss_killed(edi origin), structures_shift(edi dx, esi dz)
site_state(rdi SITE*) -> rax SITESTATE* / 0
```

**mesher.asm, render.asm [W2]**

```
mesh_chunk(edi acx, esi acy, edx acz, rcx out) -> eax total vertices, edx first translucent vertex
render_update_chunks(xmm0 budget_s)                  ; meshes dirty chunks of meshable columns, nearest first
render_column_freed(edi slot)                        ; drops the slot's GL buffers
frustum_setup(rdi BODY* cam, xmm0 fov_deg, xmm1 aspect), frustum_test(xmm0 x, xmm1 y, xmm2 z) -> eax visible
```

**Entities [W5]** — each takes `(edi dx, esi dz)`:
- `mobs_shift`, `drops_shift`, `arrows_shift`, `tnt_shift`, `fire_shift`, `fx_shift`, `dmgnum_shift`, `abilities_shift`.

Each of these takes `(edi x0, esi z0, edx x1, ecx z1)`, an inclusive local cell box:
- `mobs_remove_box`, `drops_remove_box`, `tnt_remove_box`, `fire_remove_box`.

Container functions:
- `cont_at(x,y,z) -> rax`; `cont_create(x,y,z,kind) -> rax`. `cont_create` refuses (returns 0) at `MAX_COL_CONTS` in the column or with a full table.
- `cont_block_removed`, `conts_step`, `conts_validate` keep their signatures with local coordinates.
- `conts` (global table) and `conts_free_column(edi acx, esi acz)`.

**Gameplay [W6]**

```
body_in_water(rdi BODY*) -> eax       player_eye_in_water() -> eax       player_shift(edi dx, esi dz)
sleep_use_bed(edi x, esi y, edx z) -> eax 1    sleep_step()    sleep_cancel()    sleep_fade (dd float 0..1)
sleep_respawn_target(rdi out dd[3]) -> eax 1 if a bed is set (local foot cell)
sleep_place_at_bed() -> eax 1 placed / 0 bed missing or obstructed (clears bed_set, banner)
boats_clear  boats_step(rdi INPUT*)  boats_render  boats_place(rdi eye, rsi dir) -> eax
boats_raycast(rdi origin, rsi dir, xmm0 max) -> eax idx/-1, xmm0 t   boats_mount(edi idx)
boats_dismount  boats_break(edi idx)  boats_save(rdi WORLDHDR*)  boats_load(rdi WORLDHDR*)
boats_shift(edi dx, esi dz)  boat_riding (dd: 0 or index + 1)  hud_bubble_tiles(edi breath, rsi out db[10])
```

**game.asm / app.asm / saves.asm [W8]** — `game_rebase()`, `game_shift_origin(edi dx, esi dz)`, `game_unload_box(edi x0, esi z0, edx x1, ecx z1)`, `game_on_area_ready() -> eax 1 if another wait is needed`, `app_wait_area(rdi text, rsi BODY* centre)`. `WORLDENTRY.valid`: 0 unreadable, 1 ok, 2 old version.

**sys.asm [W1]** — `time_mono() -> xmm0` float seconds since the first call (`SYS_CLOCK_GETTIME` 228, `CLOCK_MONOTONIC` 1; add `SYS_CLOCK_GETTIME` to common.inc). `file_pread(rdi path, rsi buf, rdx len, rcx offset) -> rax bytes / -errno`. `dir_remove_tree(rdi path) -> eax 0 / -errno` (unlinks every entry of `path/regions`, rmdirs it, unlinks the files of `path`, rmdirs `path`; one level of subdirectory only). `mkdir_p` moves here from saves.asm (same contract).

## Design data

### Floating origin and rebase (W8 trigger; every listed module shifts its own state)

- `game_rebase()` runs in `sim_step` right after the player's `body_step` (and after `boats_step` while riding). If `|player.x| >= 1024.0` or `|player.z| >= 1024.0`:
  1. `dx = (floor(player.x) sar 9) shl 9` and `dz` likewise; an axis below the threshold gets 0.
  2. `world_rebase(dx, dz)`.
  3. Shift calls in this order: `player_shift`, `mobs_shift`, `drops_shift`, `arrows_shift`, `tnt_shift`, `fire_shift`, `fx_shift`, `dmgnum_shift`, `abilities_shift`, `boats_shift`.
  4. Shift game.asm's own state: `game_target.bx/.bz/.px/.pz`, and `brk_x`/`brk_z` when `brk_y != -1`.
  5. Call `structures_shift(dx, dz)`, which calls `structures_refresh`.
- What each shift moves:
  - `player_shift`: `player.x/z`.
  - `mobs_shift`: `MOB.body.x/z` and `home_x/home_z` of every used slot.
  - `drops_shift`: `DROP.x/z`.
  - `arrows_shift`: `ARROWENT.x/z`.
  - `tnt_shift`: `PRIMED.body.x/z`.
  - `fire_shift`: `FIREENT.x/z` (ints) of used slots.
  - `fx_shift`: `PARTICLE.x/z`.
  - `dmgnum_shift`: `DMGNUM.x/z`.
  - `abilities_shift`: `meteor_tgt` and `rain_tgt` x/z.
  - `boats_shift`: `BOAT.body.x/z`.
- `render.asm`'s `eye` and `fx.asm`'s `cull_eye` are rebuilt every frame and need nothing.
- The title panorama never rebases.

### Columns, pool and install (W1)

- **Pool:**
  - `chunk_pool: resb POOL_CHUNKS * CHUNK_BYTES` (`.bss`, `alignb 64`).
  - A free-index stack `pool_free: resd POOL_CHUNKS`, filled at first use.
  - `chunk_pool_used` is the count of chunks in use.
  - Allocating a chunk zeroes its 4096 block bytes and fills its 4096 light bytes with 0xF0.
- **world_get fast path:**
  - `acx = (x + origin_x) sar 4`, `acz` alike. `slot = ((acz & 63) << 6) | (acx & 63)`.
  - Check `COLUMN.cx/cz` and `state == COL_LIT`, then the chunk pointer for `y >> 4` (0 → AIR), then byte `((y&15)<<8)|((z&15)<<4)|(x&15)`.
  - The origin is a multiple of 512, so local and absolute share their low 4 bits.
- **world_install(GENBUF):** the slot must hold this column in state `COL_PENDING`. Otherwise the result is stale: return 0 and do nothing.
  1. Allocate chunks `0..top>>4` (none if top = −1).
  2. Copy each chunk's 4096 blocks from `GENBUF.blocks + cy*4096`. The layout `(y<<8)|(lz<<4)|lx` makes that a straight copy. Light bytes stay 0xF0 until `light_column`.
  3. Copy `biome` and `top`.
  4. Insert containers into `conts[]` with absolute coordinates: every `GENBUF.conts` record as-is, and every `GENBUF.chests` entry as `CONT_CHEST` filled by `structures_fill_chest`.
  5. If the pool or the table cannot hold everything, release what was taken and return −1. `stream_update` then backs off for 60 frames and prints "chunk pool full" or "container table full" once per session.
  6. Set `flags = CF_CONTS` if any container exists, else 0. Set `dirty = 0xFFFF` and `state = COL_BLOCKS`.
- **world_unload(COLUMN):**
  1. `game_unload_box(ax0 − origin_x, az0 − origin_z, ax0 + 15 − origin_x, az0 + 15 − origin_z)`.
  2. `conts_free_column(acx, acz)`.
  3. `render_column_freed(slot)`.
  4. Push its chunks onto the free stack and set `state = COL_FREE`.
- **world_set:**
  - It marks light with `light_mark` when OPAQUE, emission (`block_light`) or `FLAG_TRANSLUCENT` differ between the old and new id.
  - It sets `CF_MODIFIED` and raises `top` when y > top.
  - It lowers `top` (rescanning down) when the top cell becomes AIR.
  - It allocates any chunk between the old top chunk and y so that chunks `0..top>>4` stay allocated.
- **world_clear (tests):**
  - Drop every column without saving (no unload hooks).
  - Reset the pool, `conts[]` and origin.
  - Create 18×18 LIT columns (acx, acz −1..16) with null chunks, `top = −1`, biome PLAINS and `dirty = 0`.
  - Reset light's pending edit regions (`dirty_n = 0`).

### Streaming and the generator thread (W1)

- **Radii:** R = `settings.render_dist` (2..16). The load radius is L = R + 1 (Chebyshev, in columns around the centre column) and the keep radius is K = R + 2.
- **Spiral:** `stream_spiral` holds every (dx, dz) with |dx|, |dz| ≤ 18, sorted by dx² + dz², then by dz, then by dx. That is 1369 entries, built once.
- **`stream_update(cx, cz, budget)`** runs these steps in order. "Budget" is `time_mono()` measured from entry.
  1. **Unload:** every non-FREE slot farther than K from the centre column.
     - A `PENDING` column just becomes FREE; a stale worker result is discarded at install.
     - A `BLOCKS` or `LIT` column is first written with `region_write_column` when the world has a directory and `flags & (CF_MODIFIED|CF_CONTS)`, then passed to `world_unload`.
  2. **Collect:** under the mutex, every `GB_DONE` GENBUF goes to `world_install` when `session` matches, then to `GB_FREE`.
  3. **Dispatch** (spiral order up to L, while the budget is left): for each FREE slot, choose one of three paths.
     - **Region read:** if `region_read_column` finds the column (at most 4 reads per call), decode it into the main-thread `load_buf` (a GENBUF), set `biome` with `gen_biome` per cell, mark it PENDING and install it. A column read from disk is rewritten only when it changes or holds containers.
     - **Worker:** else if a GENBUF is `GB_FREE`, fill in cx, cz, session and `GB_REQ`, mark the column PENDING, and signal the condition variable.
     - **No thread (selftests):** call `gen_column` inline on a free GENBUF and collect it, at most 4 columns per call.
  4. **Light:** in spiral order, for every `COL_BLOCKS` column (at most 6 per call while the budget is left), run `light_column`.
  - Every step stops early when `time_mono()` passes the budget. Unload and collect always run fully.
- **Thread protocol:**
  - `gen_mutex` and `gen_cond` are zeroed `.bss` (`resb 64` each; zero is the glibc static initializer).
  - The worker loop:
    1. Lock. While there is no `GB_REQ` and no `gen_quit`, `pthread_cond_wait`.
    2. Take the lowest-index `GB_REQ` and set it `GB_BUSY`. Unlock.
    3. `gen_column(buf)`.
    4. Lock. Set it `GB_DONE`. Unlock.
  - `stream_thread_stop` sets `gen_quit` under the lock, broadcasts and calls `pthread_join`.
  - `stream_begin` waits (lock, then a spin with `pthread_cond_wait` on the same cond, signalled by the worker after each job) until no buffer is `GB_BUSY`, then sets every buffer `GB_FREE`. The worker therefore never writes a buffer of an old session.
- **Area ready:** `stream_area_ready(x, z, r)` = every column within Chebyshev r of (x, z)'s column is `COL_LIT` with `dirty == 0`. `render_update_chunks` clears dirty bits as it meshes, so "ready" means lit and meshed.

### Light (W1, light.asm)

- **Storage:**
  - Light lives in each chunk's second 4096 bytes. `light_cells`, `light_prev` (as 4 MiB arrays) and `col_state[65536]` are deleted.
  - New statics:
    - `lp_prev: resb 64*64*256`, a region snapshot. Regions are capped at 64×64 columns of cells.
    - `l_att: resb 256`: 1 for WATER and ICE, else 0. It is an extra decrement per cell entered, applied to both channels in the flood. In the column pass the sky value drops by 1 per WATER/ICE cell going down.
    - `col_sky: resb 64*64`, the region's per-(x,z) sky state.
  - The queue keeps `LQ_SIZE` = 1<<22 dwords. An entry is packed relative to the region base: `dx | dz<<7 | y<<14`, with dx and dz in 0..127.
- **`light_column(COLUMN* C)`:**
  1. The region is C's 16×16 cells × y 0..ycap, where `ycap = min(255, top + 16)`. Cells above ycap keep 0xF0.
  2. Column pass top-down per (x, z): `sky = 15`; for each y from ycap down, `sky = 0` on an opaque cell, else `sky −= l_att`; the cell = `sky<<4 | emit`.
  3. Seeds: as `light_seeds` today.
  4. Read-only sources: the cells just outside C's 4 faces that are in LIT columns (sky ≥ 2 or block ≥ 2), and the top face at ycap+1 when ycap < 255.
  5. Flood inside C.
  6. Outward increase pass: queue every boundary cell of C, then BFS outward into LIT columns only. Raise a neighbour cell when `relaxed > current` in either channel, and push it. Stop at 15 cells of travel (the values die out on their own). Each raised cell calls `world_mark_cell_dirty`.
  7. `state = COL_LIT`.
- **`light_mark`/`light_update`** (edits) work as today, with these differences:
  - Rectangles are in absolute coordinates.
  - A merged rectangle that would exceed 64 cells in x or z is not merged; it gets its own slot.
  - The recompute region's y range is `0..min(255, max top in the region + 16)`, and its top face is a source face.
  - Cells in columns that are not LIT are outside the region. They are neither recomputed nor used as sources.
  - `light_compare` marks dirty through `world_mark_cell_dirty` (local coordinates) as today.
- **`light_compute_all`:** set every LIT column to `COL_BLOCKS` and reset its light chunks to 0xF0, then `light_column` each in table order. The monotone increase rule makes the order irrelevant.

### Meshing and rendering (W2)

- **Padded copy:**
  - `mesh_chunk` first copies blocks and light of the chunk and its 26 neighbours into `pad_blocks[18*18*18]` and `pad_light[18*18*18]`, index `(py*18+pz)*18+px` with p = local + 1.
  - It uses `world_chunk`. A null chunk reads as AIR/0xF0, and a missing column reads as AIR/0xF0, which never happens for meshable columns.
  - Every read inside the mesher (`world_get`, `world_is_opaque`, `light_get`, the `PROBE` AO) becomes an array read of the pads.
  - `shape_boxes` still gets world coordinates for its neighbour-aware shapes (fence, pane), as today.
- **Vertices:** positions are chunk-local ×16 (0..256 fit the `resw` fields). The renderer translates each chunk.
- **Two ranges:** opaque and alpha-tested faces are written first, then translucent faces. `mesh_chunk` returns eax = total vertices and edx = first translucent vertex.
  - Translucent ids are `FLAG_TRANSLUCENT` (WATER, ICE).
  - A translucent cell's face is culled when the neighbour is `FLAG_OPAQUE` or `FLAG_TRANSLUCENT`.
  - A WATER cell whose cell above is not WATER or ICE gets its top face, and the top edge of its side faces, at y + 14/16.
  - Faces use the flat light of the cell they face, and colour 0xFFFFFFFF.
  - The tile comes from `block_tiles` (TILE_WATER, TILE_ICE). Their texel alpha is 180 for water and 200 for ice.
- **SHAPE_CROSS (TALL_GRASS):**
  - Two vertical diagonal quads through the cell, from (0,0)–(16,16) and (16,0)–(0,16), height 16. Each is emitted in both windings, so 4 quads (16 vertices).
  - Flat light of the own cell, tile `block_tiles` side, in the opaque (alpha-tested) range. No culling against neighbours.
  - SHAPE_LIQUID is not used by the shaped path; the water path above handles WATER.
- **GL buffers:**
  - `glGenBuffers(MAX_COLUMNS*COL_CHUNKS)` once (65536 names). `slot_vbo`, `slot_count` (opaque vertices) and `slot_tcount` (translucent vertices) are `resd 65536`, indexed `slot*16 + cy`.
  - `render_column_freed(slot)` calls `glBufferData(size 0)` on the slot's 16 buffers and zeroes its counts.
- **`render_update_chunks(budget)`:**
  - A column is meshable when it is `COL_LIT` and its 8 neighbours are `COL_LIT`.
  - Walk `stream_spiral` up to R+1 from the player's column, and remesh every dirty chunk of each meshable column (clearing its bit) until `time_mono()` passes the budget.
  - A chunk with 0 vertices uploads nothing and gets count 0.
- **Draw:**
  - After the sky, `glTranslatef(-eye)` stays for entities. Chunks draw in spiral order (near first) up to R.
  - Skip a chunk whose `slot_count + slot_tcount == 0`. Skip it when its horizontal centre distance is beyond `lim2` (as today). Skip it when `frustum_test(centre)` is 0.
  - Each drawn chunk: `glPushMatrix; glTranslatef(lcx*16, cy*16, lcz*16)` (local chunk origin = `acx*16 − origin_x`, an exact small int); `glScalef(1/16)`; the pointer setup as today; `glDrawArrays(GL_QUADS, 0, slot_count)`; `glPopMatrix`.
  - After entities and the target outline, a translucent pass draws the same chunks in reverse spiral order with `glDrawArrays(GL_QUADS, slot_count, slot_tcount)`. It runs with `GL_BLEND` on (`SRC_ALPHA, ONE_MINUS_SRC_ALPHA`), `glDepthMask(0)`, `GL_CULL_FACE` off and `GL_ALPHA_TEST` off, and restores them after.
- **Frustum:** `frustum_setup` builds 4 side planes from yaw, pitch, the vertical FOV (the aim-adjusted FOV render_world already computes) and the aspect. `frustum_test` returns 0 when the chunk centre is more than 14.0 (the chunk's bounding radius, 8√3 rounded up) outside any plane.
- **Underwater:** when `player_eye_in_water()` and not on the title, the fog colour and clear colour are (0.05, 0.15, 0.45), fog start 0, fog end 20, and the sun and moon are skipped.
- **Atlas:** `atlas: resb ATLAS_W * ATLAS_H * 4`, `TEXIMAGE ATLAS_W, ATLAS_H`, and a texture matrix of `glScalef(1/4096, 1/8192, 1)`. `ui.asm` mirrors it in `ui_begin`; that line belongs to wave 0.
- `boats_render` is called right after `mobs_render`.

### Region files and world directory (W1, region.asm)

- **Paths:** `<world_dir>/regions/r.<arx>.<arz>.bin`, with signed decimals from `i32_to_str` and `arx = acx sar 5`. `region_set_dir` creates `regions/` with `mkdir_p`.
- **File layout:**
  - bytes 0..7: magic "ACREG001";
  - bytes 8..8199: 1024 entries `{dd sector, dd length}`, index `((acz & 31) << 5) | (acx & 31)`;
  - the rest pads to 12288 (3 sectors of 4096).
  - Sector 0 means absent. Blobs start on 4096-byte sector boundaries.
- **Cache:**
  - 16 cached tables `{arx, arz, valid, absent, entries[1024]}`, evicted least-recently-used.
  - A missing file is cached as `absent` (every entry 0). A file with a bad magic is also cached as absent, after the stderr line "region r.X.Z.bin: bad header, ignored".
  - Writes keep the cache in sync. `region_flush_cache` empties it.
- **Write:**
  1. Encode into `blob_buf` (256 KiB, enough for the worst case: 16 × (2 + 8192) + 64 × 120 + 8).
  2. If the file is absent, create it with `O_RDWR|O_CREAT` and mode 0644, write the 12288-byte header, and mark the cache entry present.
  3. Placement: let `n = ceil(len/4096)` and the old size `ceil(old_len/4096)`. If the old entry has sector ≠ 0 and its size ≥ n, write in place. Else append at `ceil(fstat size/4096)·4096`.
  4. pwrite the blob, then pwrite the 8-byte entry, then close.
- **Column blob:**
  - `dd 0x394C4F43`: the bytes "COL9".
  - `dw chunk_mask`: bit cy set = chunk has any non-AIR block.
  - `dw cont_count`.
  - Per set bit, in ascending cy: `dw rle_len`, then `rle_len` bytes of pairs `{db run−1, db id}` covering exactly 4096 cells in chunk order. FIRE is written as AIR.
  - `cont_count` × CONTSAVE (120 bytes): `db lx, db y, db lz, db kind, 27×4 slots, dw burn, dw burn_max, dw cook, dw 0`.
- **Read / decode:**
  - A wrong magic, a run overflowing 4096, a `rle_len` past the blob end, `cont_count > MAX_COL_CONTS` or an id ≥ `NUM_BLOCKS` makes the column "absent" with the stderr line "region r.X.Z.bin: column (cx,cz) unreadable, regenerated". It returns 0.
  - Otherwise it fills `GENBUF.blocks` (missing chunks = AIR), sets `top`, sets `nconts`/`conts` (absolute coordinates rebuilt from `acx*16+lx`) and sets `nchests = 0`. It returns 1.

### Terrain (W3, worldgen.asm + noise.asm)

- **Noise** (noise.asm, all reentrant; `gen_seed` read-only):
  - `hash32` moves here unchanged.
  - `noise2` is today's value noise with the cell index taken by `sar`, so it is continuous across 0.
  - `noise3` is trilinear value noise with smoothstep. Its lattice value is `lattice(hash32(ix ^ (iy * 0x27D4EB2D), iz, salt))`.
  - `fbm2(x, z, shift, oct, salt)` = Σ_{o<oct} noise2(x, z, shift−o, salt+o)·0.5^o / Σ 0.5^o.
- **Column fields:**
  - Continentalness `C = fbm2(x,z,10,4,1000)`.
  - Temperature `T = fbm2(x,z,9,3,1100)`.
  - Moisture `M = fbm2(x,z,9,3,1200)`.
  - Ruggedness `Rg = fbm2(x,z,9,3,1300)`.
  - Detail `D = fbm2(x,z,6,4,1400)`.
  - River `Rv = |fbm2(x,z,9,3,1500)|`.
  - `clamp01` clamps to [0,1].
- **Height (`gen_height`):**
  - If `C < −0.10` (ocean): `h = 91 − 36·clamp01((−0.10 − C)/0.25) + 3·D`.
  - Else:
    - `land = clamp01((C + 0.10)/0.20)`
    - `mtn = clamp01((Rg − 0.20)/0.35)² · land`
    - `h = 98 + 10·land + 8·D + mtn·(70 + 30·D)`
    - `sw = clamp01((M − 0.25)/0.10) · (T ≥ −0.25) · (1 − mtn)`, then `h = lerp(h, 96 + 2·D, sw)`.
    - If `Rv < 0.06` and `h < 160`: `h = lerp(93, h, smoothstep(Rv/0.06))`.
  - Round to int and clamp to [8, 240].
- **Biome (`gen_biome`)**, in this order:
  1. OCEAN if `C < −0.10`.
  2. RIVER if `Rv < 0.025` and the pre-river h < 160.
  3. MOUNTAINS if `mtn > 0.35`.
  4. SNOW if `T < −0.25`.
  5. DESERT if `T > 0.25` and `M < 0`.
  6. SWAMP if `sw > 0.5`.
  7. FOREST if `M > −0.05`.
  8. Else PLAINS.
  - Thresholds may be tuned by up to ±50% (one constant at a time) only to pass `test_worldgen_biomes`. Record any change in As built.
- **Materials** (y = h is the top; filler is the 3 cells below; stone below that; BEDROCK at y 0):

|biome|top|filler|
|---|---|---|
|PLAINS, FOREST|GRASS|DIRT|
|DESERT|SAND|SAND, then 3 more SANDSTONE below the filler|
|SNOW|GRASS + SNOW_LAYER at h+1|DIRT|
|SWAMP|MUD where `noise2(x,z,3,1600) > 0.3`, else GRASS|DIRT|
|MOUNTAINS|GRASS if h < 150; STONE if 150 ≤ h < 195; SNOW_BLOCK if h ≥ 195; SNOW_LAYER at h+1 if h ≥ 175 and top ≠ SNOW_BLOCK|DIRT if h < 150, else STONE|
|OCEAN|SAND if h ≥ 80, else GRAVEL|same as top|
|RIVER|SAND|SAND, SAND, DIRT|
|beach: land with h ≤ 98 and C < −0.06|SAND|SAND|

- **Water:**
  - Cells with `h < y ≤ 96` are WATER.
  - In cold columns (`T < −0.25`, whatever their biome id, so cold oceans and rivers too), the y = 96 cell is ICE instead of WATER.
- **Caves** (after materials and water). Noise is sampled on a 4-block lattice of absolute coordinates (x, z multiples of 4, y multiples of 4) and trilinearly interpolated.
  - **Tunnels (y 12..72):** carve when `|noise3(x, 2y, z, 5, 2000)| < 0.07` and `|noise3(x, 2y, z, 5, 2001)| < 0.07`.
  - **Caverns (y 30..80):** carve when `noise3(x, 2y, z, 6, 2002) > 0.45`.
  - **Ravines:** when `|fbm2(x,z,7,2,2003)| < 0.012` and `fbm2(x,z,8,1,2004) > 0.30`, carve y 25..h.
  - Never carve below y 5, WATER, ICE or BEDROCK.
  - Never carve within 4 cells below the top in columns with h < 97 (oceans, rivers, swamps), so no air sits under water.
  - A carved top cell makes a surface opening. The SNOW_LAYER above it goes too.
- **Ores and gravel:**
  - The ore walks are today's random walks, replacing STONE only. They are clipped to the column and seeded by `hash32(acx*16+attempt, acz, salt)`.
  - Attempts per column:

|ore|attempts|y range|vein size|
|---|---|---|---|
|COAL|20|40..130|8|
|IRON|12|15..80|6|
|GOLD|3|5..40|5|
|DIAMOND|1|2..18|4|

  - Gravel: 2 pockets of 3×2×3 at y 5..90.
- **Vegetation:** a candidate per (x, z) in the column expanded by 3 cells, so trees crossing column borders are stamped consistently and clipped to the column.
  - The decision is pure: `t = hash32(x, z, 99)`, biome and top from `gen_biome`/`gen_height`/materials of that (x, z), and no cave carved at the top cell (`gen_carved(x, h, z) == 0`).
  - The carve decision is one pure function, `gen_carved(ax, y, az) -> eax`, which both the cave pass and this check use. The cave pass may cache lattice samples per column but must give identical results.
  - Trees need top = GRASS and h ≥ 97.
  - Chances (`t & 255 <` value):
    - PLAINS 1 (oak), FOREST 7 (oak if `t & 256`, else birch), SNOW 3 (pine), MOUNTAINS 2 (pine, only h < 150), SWAMP 3 (oak).
    - DESERT 2: CACTUS on SAND, height `1 + (t >> 9) % 3`.
  - Oak: today's shape. The trunk is `4 + (t>>8)%3`, the ground cell becomes DIRT, and the leaves use today's `place_layer` pattern.
  - Birch: the oak shape with BIRCH_LOG/BIRCH_LEAVES and a trunk of `5 + (t>>8)%3`.
  - Pine: a PINE_LOG trunk of `6 + (t>>8)%4`. PINE_LEAVES layers run from the trunk top down to trunk base + 2 with radius alternating 1, 2, 1, 2… (corners of radius-2 layers cut), plus one leaf above the top.
  - TALL_GRASS on GRASS with no tree there and the cell above AIR: `(hash32(x,z,98) & 255) <` PLAINS 26, FOREST 13, SWAMP 38, MOUNTAINS (h < 150) 8.
- **Order in `gen_column`:**
  1. Materials and water.
  2. Caves.
  3. Ores and gravel.
  4. Vegetation.
  5. `structures_stamp`.
  6. Biome map (per cell `gen_biome`).
  7. `top` (scan).
  - `nchests` is filled by stamping and `nconts = 0`.
- **Spawn (`gen_find_spawn`):**
  - Rings k = 0..256 of column centres `(16i+8, 16j+8)` with `max(|i|,|j|) == k`. Within a ring, j goes ascending, then i ascending.
  - Return the first centre whose biome is PLAINS, FOREST, DESERT, SNOW or SWAMP and whose `gen_height` ≥ 97, as (x, h+1, z).
  - If there is none, return (8, max(gen_height(8,8), 96) + 1, 8).
- **Removed:** `world_generate`, `heightmap`, `worldgen_height` (callers use `gen_height`), and the 256-bound loops. The generator never calls `world_*`.

### Sites (W4, structures.asm)

- **`region_plan(arx, arz, out)`:** pure; uses `gen_height`, `gen_biome` and `hash32`. Coordinates are absolute. The region's blocks are `[arx·512, arx·512 + 511]`. It emits, in this order:
  - **Village (0 or 1):**
    - Only if `hash32(arx, arz, 700) % 100 < 70`.
    - 16 candidates: `x = arx·512 + 48 + hash32(k, arx ^ (arz<<16), 701) % 416`, and z alike with salt 702.
    - The biome must be PLAINS or FOREST, or DESERT or SNOW when `hash32(k, arz, 703) & 1`.
    - 25 `gen_height` samples on a 5-step grid over ±10 must be within ±4 of the centre, with centre h ≥ 98.
    - The site y is the centre h.
  - **Dungeons (1 or 2):**
    - 32 candidates (salts 711/712), with a margin of 80 on every side.
    - The biome is not OCEAN or RIVER.
    - The floor is `y = clamp(gen_height − 24, 20, 80)`.
    - `gen_height` ≥ y + 12 at offsets (0,0), (14,0) and (14,14).
    - At least 48 from the village and the other dungeon.
    - The first valid candidate is dungeon 1. A second is kept only when `hash32(arx, arz, 713) & 1`.
  - **Crypt (0 or 1):**
    - Only when `(arx & 1) == 0 && (arz & 1) == 0`, so one per 2×2 regions.
    - 32 candidates (salts 721/722), with a margin of 80.
    - The floor is `y = clamp(gen_height − 30, 15, 70)`.
    - `gen_height` ≥ y + 14 at the centre and at (±8, ±8).
    - At least 48 from the other sites.
  - **Camps:**
    - Camps belong to the super-region `(sx, sz) = (arx sdiv 3, arz sdiv 3)` (floor division). `camp_plan(sx, sz)` places, for each faction f = 0..4, up to 24 candidates over the 1536×1536 super-region with a margin of 64 (salts 800+f, 810+f).
    - Accept the first candidate meeting all of these:
      - biome in f's home set: Villagers {PLAINS, FOREST}, Bandits {FOREST, MOUNTAINS}, Cult {SWAMP}, Beastfolk {SNOW, MOUNTAINS}, Stonekin {MOUNTAINS};
      - 9 samples over ±10 within ±5 of the centre;
      - ≥ 96 from the village of the region it falls in (`region_village` = the village rule above alone, so there is no recursion);
      - ≥ 128 from the camps accepted before it.
    - A faction with no valid candidate has no camp in that super-region.
    - `region_plan` includes the camps whose centre lies in this region, as `SITE_CAMP` with `index` = faction, in faction order.
  - `.slot` is the output index and `.rx/.rz` the region.
  - Trigger boxes:
    - village: as today;
    - dungeon: x −5..19, y −1..+5 relative to the floor, z −5..19;
    - crypt: ±7, y +0..+7 relative to the floor;
    - camp: ±10, y −2..+8 relative to the ground.
- **Stamping (`structures_stamp(GENBUF)`, generator thread):**
  - Region plans for the column's region ±1 come from a 9-entry generator-private cache keyed by (arx, arz).
  - Every site whose footprint box meets the column is built by its builder, clipped to the column:
    - village ±16;
    - dungeon x −66..+20, z −6..+20;
    - crypt x −69..+9, z −9..+9;
    - camp ±11.
  - Builders write and read only through `gb_set`/`gb_get`:
    - Inside the column they write or read `GENBUF.blocks`. Outside, `gb_set` drops the write and `gb_get` returns AIR.
    - `box_fill` keeps its op flags (`OP_SHELL`, `OP_IFAIR`, `OP_IFSOLID`) over `gb_get`/`gb_set`.
    - `stair_tunnel` uses `gen_height` instead of `world_top_y`.
    - Dungeon and crypt BOX rows keep their shapes with y relative to the site's floor (today's absolute y − 8 for dungeons and − 6 for the crypt, plus the floor).
  - `place_chest` no longer touches containers: it sets CHEST and appends a `GENCHEST {x, y, z, table}` when the cell is inside the column (at most `MAX_GEN_CHESTS`).
  - The camp builder flattens ±10 around the centre to the centre h:
    - the biome top block at h and the filler below, down to h − 3 where lower;
    - AIR from h+1 to h+12;
    - a FENCE at (0, h+1, 0) with a TORCH at (0, h+2, 0).
    - This is the flagged clearing; the camp buildings are 0.10's.
- **`structures_fill_chest(CONTAINER, GENCHEST)`:** today's loot rolls from `place_chest` (`hash32` of the absolute cell, so it is deterministic) and its gear.
  - Dungeon tables use LOOT_CHEST at tier `max(2, gear_tier_for_level(rpg_level))`, 1 piece.
  - Crypt tables use LOOT_BOSS tier 13, 2 pieces.
- **Runtime:**
  - `sites[MAX_SITES]` and `site_count` hold the 3×3 regions around the player's region (absolute `(floor(player.x) + origin_x) sar 9`), converted to local by subtracting the origin from every x/z field.
  - `structures_refresh` rebuilds them. `game.asm` calls it when the player's region changes, `structures_shift` after a rebase, and `game_load`/`game_on_area_ready` once.
- **Site state:**
  - `site_state(SITE)` finds the record with the same (rx, rz, slot) in `world_header.sites[0..site_count)`.
  - If there is none, it appends one (kind, kills 0, flags 0).
  - If the table is full, it evicts the record whose region is farthest (Chebyshev) from the player's region and is not referenced by a live mob's `origin`.
  - It returns 0 when nothing can be evicted.
  - `structures_nearest(kind, uncleared_only)` reads `flags` without creating records.
- **Dungeons:** `structures_step` works as today (Survival, difficulty > Peaceful, every 90 steps), with these changes:
  - Inside a dungeon box (grown by 2) whose state is not `SS_CLEARED`, `dungeon_spawn` gives each mob `origin = state index + 1`.
  - Kills are counted in `SITESTATE.kills`. The 8th kill sets `SS_CLEARED` and pays as today.
  - `structures_on_mob_killed(origin)` ignores origins whose record is not a dungeon.
- **Crypt:**
  - The boss wakes as today when the player is in a crypt box whose state is not cleared and `mob_count_type(MOB_BOSS) == 0`. It gets `origin = index + 1`.
  - `structures_on_boss_killed(origin)` sets `SS_CLEARED` on that record. `mobs.asm` `boss_death` calls it instead of `rpg_state.flags |= 1`.
- **Village NPCs:** every 60 steps, `structures_step` checks each cached village whose centre column `world_column_ready` and that lies within 96 blocks of the player.
  - If no live MERCHANT has `home_x == x + 6.5` (± 0.01) and the matching `home_z`, it spawns one at (x + 6.5, y + 1, z + 0.5).
  - The ELDER at (x − 5.5, y + 1, z + 0.5) works the same way.
  - `structures_spawn_npcs` is deleted.
- **Retired:** `RPGSAVE.cleared` and `RPGSAVE.flags` bit 0 (`rpg.asm` load masking, `structures.asm`, `mobs.asm`, tests), `st_kills`, `ORIGIN_CRYPT`, `structures_plan`, `structures_generate`, and the 0..255 candidate ranges with `D2C`.

### Water, swimming and breath (W6)

- **Water tests:**
  - `body_in_water(BODY)` = the cell at `(floor x, floor(y + 0.4), floor z)` or at `(floor x, floor(y + 0.05), floor z)` is WATER.
  - `player_eye_in_water()` = the cell at the player's eye `(x, y + 1.62, z)` is WATER.
- **`body_step` when not flying and `body_in_water`:**
  - Horizontal wish speed ×0.5 (sprint still ×1.3).
  - `vy += −10·dt`, then `vy = max(vy, −2.5)`.
  - If `INPUT.jump`: `vy = 3.0`. If also `BODY.blocked` from the previous step: `vy = 7.0`, which climbs a one-block ledge out of the water.
  - `BODY.fall = 0`, and the landed-distance return is 0.
  - Mobs share `body_step`, so the same rules apply to them.
- **Breath** (`survival_step`, Survival only):
  - If `player_eye_in_water()`: `breath = max(0, breath − 1)`. At 0, `drown_timer++`; every 60th step it calls `survival_damage(1, CAUSE_DROWN)`.
  - Otherwise `breath = min(MAX_BREATH, breath + 5)` and `drown_timer = 0`.
  - `survival_damage` treats `CAUSE_DROWN` as environmental (`env_scale`).
  - `survival_reset` sets breath to `MAX_BREATH`.
  - Creative never loses breath.
- **HUD bubbles:** `hud_bubble_tiles(breath, out[10])` gives, for bubble i (drawn at `x0 + 173 − 8i`, y0 − 31):
  - TILE_BUBBLE if `breath ≥ 60(i+1)`;
  - TILE_BUBBLE_POP if `60i < breath < 60(i+1)`;
  - otherwise 0 (nothing drawn).
  - Bubbles show in Survival while `breath < MAX_BREATH`, and status pips then move from y0 − 29 to y0 − 39.

### Boats (W6, boats.asm)

- **Item:** BOAT, `max_stack 1`, recipe `3×2: PLANKS,0,PLANKS / PLANKS,PLANKS,PLANKS`.
- **`boats_place(eye, dir)`:**
  - A DDA over cells for up to 5 blocks.
  - The first cell with a SOLID block → return 0.
  - The first WATER cell whose cell above is not solid → a boat at (cx + 0.5, cy + 0.625, cz + 0.5), yaw = player yaw, body `half_w 0.6`, `height 0.5`. Return 1, and the caller consumes the item in Survival.
  - A full table → banner "Too many boats" and return 0.
- **`boats_step(INPUT)`:** every used boat whose column `world_column_ready`:
  - **Floating:** when the cell at `floor(y + 0.3)` or `floor(y)` is WATER, let wy be the highest WATER y among `floor(y) − 1 .. floor(y) + 1` at the boat's x/z. Then `vy = clamp((wy + 0.625 − y)·4, −2, 2)`.
  - **Not floating:** `vy −= 20·dt` (min −20), and `speed ×= 0.9` per step.
  - **Ridden boat** (`boat_riding == i+1`):
    - `INPUT.fwd` +1 targets 5.0 b/s and −1 targets −1.5, with acceleration 4.0 b/s². No input decelerates at 2.0 b/s².
    - `INPUT.strafe` turns at 90°/s, D = +1 turning the same way as moving the mouse right.
    - `INPUT.down` dismounts: the player goes to the boat position + (0, 0.6, 0) with vy 0.
  - **Unridden boat:** the speed decays at 2.0 b/s².
  - **Movement:** `move_axis` (exported from player.asm) on X, then Z, using `speed·dt` along the same forward vector as `body_step`'s wish vector for that yaw, then Y. A blocked X/Z sets the speed to 0.
  - **Rider:** `player.x/z` = the boat's, `player.y = boat.y + 0.25`, velocities 0, `fall 0`, `on_ground 1`. The player's yaw stays free.
- **`boats_raycast`:** a ray against each used boat's AABB (`half_w`, `height`). It returns the nearest index within max.
- **Breaking:** `boats_break(i)` frees the boat. In Survival it also calls `drops_spawn(BOAT, 1, 0, x, y + 0.3, z)`. `boats_mount(i)` sets `boat_riding`.
- **Render:** `boats_render` draws 5 boxes with the PLANKS tiles, in model space (blocks, front −Z), under `glTranslatef(x, y, z)` and `glRotatef(−yaw, 0, 1, 0)` with `light_bind_at` at the centre:
  - floor (−0.55, 0, −0.85)–(0.55, 0.125, 0.85);
  - left wall (−0.55, 0.125, −0.85)–(−0.45, 0.5, 0.85), right wall (0.45, 0.125, −0.85)–(0.55, 0.5, 0.85);
  - bow (−0.45, 0.125, −0.85)–(0.45, 0.5, −0.75);
  - stern mirrored at +z.
  - Only boats in meshable columns are drawn.
- **Save:** `boats_save`/`boats_load` use `WORLDHDR.boat_count` and `.boats` (BOATSAVE). Load skips non-finite values and |x| or |z| ≥ 65536. After load nobody rides.

### Beds and sleep (W6: placement.asm, sleep.asm; W8: dispatch)

- **Placement (`place_block`, SHAPE_BED, item BED):**
  - `f = facing()`. The foot is the placement cell; the head is the foot + `(dir_dx[f], 0, dir_dz[f])`.
  - Both cells must be free (see the replaceable rule), in ready columns, with `world_is_solid` below.
  - The entity checks cover both cells.
  - It sets the foot to `BED + f` and the head to `BED + 4 + f`.
- **Replaceable rule (all placements):**
  - A cell is free when it holds AIR, WATER, TALL_GRASS or SNOW_LAYER.
  - When the targeted block `b` is TALL_GRASS or SNOW_LAYER, the placement cell is `b` itself.
  - Literal `WORLD_*` bounds are replaced by `0 ≤ y ≤ 255` plus `world_column_ready`.
- **Removal:**
  - `block_removed` on a bed half removes the partner (the head at foot + dir, the foot at head − dir) when that cell holds the matching other half. It sets AIR with no drop.
  - `block_drop` of all 8 ids is BED, so exactly one bed drops.
  - `block_is_usable` is true for SHAPE_BED.
- **`sleep_use_bed(x, y, z)`** (game.asm calls it for a right-click on a bed cell when `block_use` did not react):
  1. Resolve the foot. A head is param bit 2, so the foot is the cell − dir.
  2. Store `bed_x/y/z` = foot + origin and `bed_set = 1`.
  3. Not `sky_is_night(game_time)`: banner "Respawn set. You can only sleep at night".
  4. Else, any used mob with `mob_is_hostile(type)`, horizontal distance² ≤ 64 from the foot centre and |dy| ≤ 5: banner "Respawn set. Monsters are nearby".
  5. Else start sleeping: `sleep_active = 1`, timer 0, the player at (foot.x + 0.5, foot.y + 0.5625, foot.z + 0.5) with zero velocity, banner "Respawn set. Sleeping...".
  - It returns 1 in every case.
- **`sleep_step()`:**
  - While active: `timer++`, `sleep_fade = min(1, timer/90)`.
  - At timer 120: `game_time = (game_time / DAY_LENGTH + 1)·DAY_LENGTH` (06:00), `sleep_active = 0`, then `sleep_fade` falls by 1/30 per step to 0.
  - `sleep_cancel()` sets `sleep_active = 0` and `sleep_fade = 0`, and leaves the time alone.
  - `survival_damage` (when it applies damage) calls `sleep_cancel`. `game.asm` calls it when any movement, jump or sneak input is held during sleep; otherwise it zeroes the movement input while `sleep_active`.
  - The rules are the same in Creative.
- **Respawn:** `sleep_respawn_target` gives the bed foot in local coordinates. `sleep_place_at_bed()` runs after the area around it is ready:
  - The foot must hold `BED..BED+3`.
  - It stands the player on the first of the 4 horizontal neighbours of the foot, then of the head, in N, E, S, W order, where the cell and the cell above are not solid and the cell below is solid.
  - Failing that, on top of the foot (y + 0.5625) when the 2 cells above are not solid.
  - Otherwise, and when the bed is missing: `bed_set = 0`, banner "Your bed was missing or obstructed", return 0.

### Entities, containers and fire under streaming (W5)

- **Freeze:** `mobs_step` skips AI and physics for a slot whose `world_column_ready(floor x, floor z)` is 0. `boats_step` does the same (W6).
- **Spawning:**
  - `spawn_at_ground(edi type, esi x, edx z, ecx kind)`, where kind is 0 hostile or 1 passive. It requires `world_column_ready` and `top ≤ 254`.
  - If the top block is TALL_GRASS or SNOW_LAYER, the spawn cell is that cell and the ground is below it. Otherwise the ground is the top block and the spawn cell is above it.
  - The spawn cell must not be WATER.
  - Hostile ground: `block_flags & (FLAG_SOLID|FLAG_OPAQUE)` both set, and the block is not BEDROCK, LEAVES, PINE_LEAVES or BIRCH_LEAVES. The light rule is unchanged.
  - Passive ground: GRASS.
  - The 1..254 bounds and the `id < 32` bitmask are deleted.
  - `mobs_populate` scatters around the player (x, z ± 48) instead of (128, 128).
- **Load:** `mobs_load` accepts types 1..6 with finite floats, |x| and |z| < 65536, and 0 ≤ y < 256. `c_256` and `c_64` are deleted. `MAX_MOBS` 64 grows the arrays.
- **Water AI:**
  - When a mob is not `body_in_water` and either the cell 0.7 blocks ahead along its heading at feet level, or the cell below that, is WATER: a wandering mob turns to `yaw + 180 ± (hash of the slot) 45°`, and a hunting mob sets `fwd 0`.
  - When `body_in_water`, it holds `jump`, so it floats and drifts.
- **Unload:**
  - `mobs_remove_box`, `drops_remove_box`, `tnt_remove_box` and `fire_remove_box` free every slot whose floored position lies in the box.
  - `fire_remove_box` does not touch blocks; the column is going away.
  - If `game_open_npc` is a removed mob, that is W8's concern: `game_unload_box` closes an open NPC screen first.
- **Fire:**
  - A free `FIREENT` slot is `y = −1`; the `.data` initializer becomes `times MAX_FIRES dd 0, -1, 0, 0, 0`.
  - `fire_rebuild` is deleted: saved columns never contain FIRE, and fires don't persist.
- **Containers (containers.asm):**
  - `conts: resb MAX_CONTAINERS * CONTAINER_size` (global), with absolute dword coordinates.
  - `cont_at` and `cont_create` take local coordinates and add the origin.
  - `cont_create` refuses when the table is full or 64 containers already have the same `(x sar 4, z sar 4)`.
  - `conts_free_column(acx, acz)` zeroes the records in that column.
  - `furnace_step` converts to local coordinates and skips a furnace whose column is not ready.
  - `conts_validate` is deleted: decode-time checks replace it.
  - `game_open_cont` points into `conts`.
- **Shifts:** as listed under Floating origin.
- **Boss death:** `structures_on_boss_killed(MOB.origin)` replaces the `rpg_state.flags` write.

### Saves, world list and app flows (W8)

- **`saves_scan`:** `getdents64` on `worlds_dir`. Two kinds of entry are listed; everything else is skipped.
  - A directory (`d_type` DT_DIR, or DT_UNKNOWN resolved with stat) other than `.`/`..` whose `world.hdr` reads at least 1024 bytes with magic "ACRAFT06" and mode ≤ 1: valid 1. Name, mode and seed come from the header, and the mtime from `world.hdr`.
  - A regular file named `*.acw` (5–63 chars): valid 2. The display name is the stem, and the mtime comes from stat.
  - The list stays capped at 64, newest first. `WORLDENTRY.file` = the directory or file name.
- **`saves_new_world_dir(rdi name, rsi out) -> eax 0/-1`** (replaces `saves_new_file_path`):
  - Sanitize as today.
  - Try `<stem>`, then `<stem>-2` .. `<stem>-99`, rejecting a candidate when the directory or `<stem>.acw` exists.
  - `mkdir_p` the directory and its `regions/`. `out` = the directory path.
- **Delete:** `saves_delete` uses `dir_remove_tree` for valid 1, `file_unlink` for valid 2, and refuses valid 0.
- **Rename:** `saves_rename` handles valid 1 only, with `file_patch(<dir>/world.hdr, WORLDHDR.name, buf, 33)`.
- **`game_new(edi seed, esi mode, rdx name, rcx dir)`:**
  1. Zero the header; set magic, seed, mode, name and `time = NEW_WORLD_TIME`.
  2. `gen_find_spawn` → `spawn_*`; origin = `(spawn sar 9) shl 9` on each axis.
  3. The player at spawn local (x + 0.5, y, z + 0.5).
  4. `survival_reset`, `inv_clear`, the creative kit, `rpg_reset`, and clear mobs, drops, arrows, tnt, fire, fx and boats. `site_count = 0`.
  5. `stream_begin(seed, dir)`, `structures_reset`, `reset_session`, `pending_new = 1`.
- **`game_load(rdi dir)`:** `file_read(<dir>/world.hdr, header, 32769)`.
  - Missing → 1. Not exactly 32768 bytes, or magic ≠ "ACRAFT06" → 2. I/O error → 3.
  - Otherwise restore what is restored today, plus origin, breath, `bed_*`, `boats_load` and `mobs_load`.
  - Then `stream_begin(seed, dir)`, `structures_reset`, `reset_session`.
  - Health 0 → the respawn path below with `pending_respawn = 1`.
- **`game_save(rdi dir)`:**
  1. Fill the header (player, survival, breath, inventory, armor, jewelry, time, mode, origin; `boats_save`, `mobs_save`, `rpg_save`).
  2. `file_write_atomic(<dir>/world.hdr, header, 32768)`.
  3. `world_save_dirty(dir)`.
  - It returns the first error.
- **`game_shift_origin(edi dx, esi dz)`:** the shift sequence of the Floating origin section. `game_rebase` calls it on the threshold.
- **`game_respawn`:**
  1. `survival_reset`, `rpg_on_death`, `reset_session`, `sleep_cancel`, and dismount any boat.
  2. The target is the bed (`sleep_respawn_target`) if set, else the world spawn.
  3. `game_shift_origin` by `((target_abs sar 9) shl 9) − origin`. The old surroundings unload naturally, beyond K.
  4. Put the player at the target and set `pending_respawn = 1 | (bed ? 2 : 0)`.
  - The app then waits (`app_wait_area`).
- **`game_on_area_ready()`:**
  - If `pending_respawn & 2`: if `sleep_place_at_bed()` is 0, retarget the world spawn as above and return 1 (wait again).
  - If `pending_new`, or `pending_respawn` without a bed: `player.y = world_top_y(floor x, floor z) + 1`.
  - If `pending_new`: `mobs_populate`.
  - Clear the flags, `structures_refresh`, return 0.
- **`game_unload_box(x0, z0, x1, z1)`:** close the trade/dialog screen if `game_open_npc` lies in the box, then `mobs_remove_box`, `drops_remove_box`, `tnt_remove_box`, `fire_remove_box`.
- **`sim_step` additions:**
  - Sleep input handling before physics.
  - `boats_step(&input)` instead of the player's `body_step` while `boat_riding`, and for unridden boats always.
  - `game_rebase` after movement.
  - A region-change check that calls `structures_refresh`.
  - `sleep_step`.
- **Right-click dispatch, in this order:**
  1. With BOAT held: `boats_place` → consume the item in Survival.
  2. Else, if not riding and `boats_raycast` (reach 4.5) is nearer than the block hit: `boats_mount`.
  3. Else the block path. After `block_use`, `block_base == BED` → `sleep_use_bed` → `hand_swing`.
- **Left-click dispatch:** a `boats_raycast` hit nearer than the block and mob hits, other than the ridden boat, → `boats_break`.
- **`app_wait_area(rdi text, rsi BODY* centre)`:** loop until `stream_area_ready(centre, 2)`:
  1. `glfwPollEvents`. Window close → leave and run the quit path.
  2. `stream_update(centre, 0.030)`, `light_update`, `render_update_chunks(0.030)`.
  3. `show_loading("<text> N%")`, where N = lit and meshed columns within radius 2 × 4.
  - When the centre is the player, it then calls `game_on_area_ready()` and loops again while that returns 1.
- **Flows:**
  - **Create:** `saves_new_world_dir`, `game_new`, wait "Generating terrain", `game_save`, enter.
  - **Play:** valid 1 only; `game_load`, wait "Loading world", enter.
  - **Panorama:** `stream_begin(PANORAMA_SEED, 0)`, `gen_find_spawn`, origin as for a new world, the camera at the spawn local + (0.5, 12, 0.5), wait around the camera "Generating".
  - **Quit to title:** "Saving", `inv_close_screen`, `game_save`, `stream_end(1)`, panorama, `saves_scan`, title.
  - **Window close in a world:** `game_save`, `stream_end(1)`.
  - **Process exit:** `stream_thread_stop`.
  - **Autosave:** every 120 s, `game_save`.
  - **Respawn:** `game_respawn`, then wait "Respawning".
  - **In play:** every frame `stream_update(player, 0.004)`, `light_update` and `render_update_chunks(0.006)` replace the old `light_update` + `render_update_chunks` pair.
  - `stream_thread_start` runs in `run_game` after GL init; `--selftest` never starts it.
  - The F3 coordinates (`app.asm` ~428) add the origin.
- **`main.asm --play NAME`:**
  - If `worlds/<sanitized>/world.hdr` exists: `game_load`.
  - Else if `worlds/<sanitized>.acw` exists: stderr "NAME is a world from 0.8 or earlier; this version cannot open it", exit 2.
  - Else create it as today (seed or rdtsc, `--creative`) with `game_new` + `game_save`.
  - The app enters through `app_wait_area`.

### New blocks, items and art (W7; wave 0 writes the table rows)

|id|name|flags|shape|tiles (top, side, bottom)|hardness|tool|drop|max stack|notes|
|---|---|---|---|---|---|---|---|---|---|
|WATER|Water|TRANSLUCENT|LIQUID|WATER×3|−1|—|0|0|`l_att` 1|
|ICE|Ice|SOLID, TRANSLUCENT|CUBE|ICE×3|0.5|pickaxe|0|64|`l_att` 1|
|SNOW_LAYER|Snow|0|SNOW (box 0,0,0,16,2,16 render/select; no collide)|SNOW×3|0.1|—|0|0||
|SNOW_BLOCK|Snow Block|SOLID, OPAQUE|CUBE|SNOW×3|0.4|shovel|SNOW_BLOCK|64||
|MUD|Mud|SOLID, OPAQUE|CUBE|MUD×3|0.6|shovel|MUD|64||
|TALL_GRASS|Tall Grass|0|CROSS (select box 2,0,2,14,13,14; no collide)|TALL_GRASS×3|0|—|0|0|replaceable|
|CACTUS|Cactus|SOLID|CACTUS (box 1,0,1,15,16,15 all purposes)|CACTUS_TOP, CACTUS_SIDE, CACTUS_TOP|0.4|—|CACTUS|64|decorative, no contact damage|
|PINE_LOG|Pine Log|as LOG|CUBE|PINE_LOG_TOP, PINE_LOG, PINE_LOG_TOP|as LOG|axe|PINE_LOG|64|burns as LOG|
|PINE_LEAVES|Pine Leaves|as LEAVES|as LEAVES|PINE_LEAVES×3|as LEAVES|as LEAVES|as LEAVES|64||
|BIRCH_LOG|Birch Log|as LOG|CUBE|LOG's top tile, BIRCH_LOG, LOG's top tile|as LOG|axe|BIRCH_LOG|64|burns as LOG|
|BIRCH_LEAVES|Birch Leaves|as LEAVES|as LEAVES|BIRCH_LEAVES×3|as LEAVES|as LEAVES|as LEAVES|64||
|BED+0..3|Bed (foot)|SOLID|BED (box 0,0,0,16,9,16 all purposes)|BED_FOOT_TOP, BED_FOOT_SIDE, PLANKS' tile|0.2|—|BED|1 for id BED only|flammable 20; icon TILE_ICON_BED|
|BED+4..7|Bed (head)|SOLID|BED|BED_HEAD_TOP, BED_HEAD_SIDE, PLANKS' tile|0.2|—|BED|0||

- The dig and step sounds mirror the nearest existing block: WATER none; ICE and SNOW_BLOCK stone; SNOW_LAYER, MUD and TALL_GRASS soft; logs and leaves as LOG and LEAVES; bed wood.
- `block_flammable` matches LOG and LEAVES for the new logs and leaves, 0 elsewhere except the bed.
- **Item BOAT:** "Boat", icon TILE_ICON_BOAT, max stack 1.
- **Recipes:**
  - Next to the LOG → PLANKS row: `1,1, PLANKS, 4, PINE_LOG` and `1,1, PLANKS, 4, BIRCH_LOG`.
  - Appended: `3,2, BED, 1, WOOL, WOOL, WOOL, PLANKS, PLANKS, PLANKS` and `3,2, BOAT, 1, PLANKS, 0, PLANKS, PLANKS, PLANKS, PLANKS`.
- **Shapes:**
  - `shapes.asm` raises the jump-table bound to SHAPE_CACTUS and adds `.bed` (one box per purpose), `.cross` (COLLIDE 0, SELECT 1 box, RENDER 0: the mesher draws it), `.liquid` (0 for every purpose), `.snow` and `.cactus`.
  - `cell_boxes` COLLIDE drops its 0..255 x/z wall: a cell is one solid box when `world_column_ready` is 0 or y < 0, and empty at y > 255.
- **Art** (`texgen.asm`): the tiles of the Contracts table, drawn after the 0.8 icons and before the font, in tile order. Noise tiles use `NFUNC`/one rng draw per pixel; the others are draw-free bitmaps.
  - **WATER:** blue (40, 90, 200) with brighter ripples (70, 130, 230). Alpha 180 on every texel.
  - **ICE:** pale blue (160, 200, 240) with white cracks. Alpha 200.
  - **SNOW:** white (240, 245, 250) with light grey speckle.
  - **MUD:** dark brown (70, 50, 35) noise.
  - **TALL_GRASS:** green blades (60..110, 150..190, 40..60) on alpha 0. Each blade is a 1-px column of height 6–14, 7 blades.
  - **CACTUS_SIDE:** green (40, 130, 50) with darker vertical ribs and 1-px light spines.
  - **CACTUS_TOP:** green with a lighter ring.
  - **PINE_LOG:** dark bark (60, 40, 25) with vertical streaks. **PINE_LOG_TOP:** rings in (150, 110, 70).
  - **PINE_LEAVES:** dark green (30, 80, 40) noise with alpha 0 holes, as LEAVES.
  - **BIRCH_LOG:** white (220, 220, 210) with black horizontal dashes.
  - **BIRCH_LEAVES:** light green (110, 170, 70) noise with holes.
  - **BED_FOOT_TOP:** red (170, 30, 30) with a darker fold line 3 px from each edge.
  - **BED_HEAD_TOP:** white sheet (235, 235, 235) with a 2-px red border.
  - **BED_FOOT_SIDE / BED_HEAD_SIDE:** the top 9 px red or white over 7 px of the planks pattern.
  - **ICON_BED:** a side-on bed, red blanket and white pillow on plank legs, alpha 0 background.
  - **ICON_BOAT:** a side-on plank hull, alpha 0 background.
  - **BUBBLE:** a 9×9-area light-blue ring with a white highlight. **BUBBLE_POP:** the same, broken into 4 dots.
  - Prove with a dump harness (as in 0.7 and 0.8) that the atlas is byte-identical outside the 20 tiles and the moved font rows.

### HUD and menus (W6)

- **HUD:**
  - Bubbles, as described under Water.
  - Sleep fade: a full-screen `RGBA(0, 0, 0, sleep_fade·255)` rect drawn after the world-space overlays and before banners and screens.
  - F3 lines (`hud_debug`), added under the existing coordinates:
    - `Biome: <name>` via `world_biome_at`; names Ocean, Plains, Forest, Desert, Snow, Swamp, Mountains, River.
    - `Columns: <loaded> lit <lit> pending <pending> pool <used>/24576` via `stream_stats`.
    - Site lines print absolute coordinates (SITE.x + origin) and add `Camp: <faction> x z` for the nearest `SITE_CAMP`, with faction names Villagers, Bandits, Ashen Cult, Beastfolk, Stonekin.
- **Menus:**
  - `t_version` = "AssemblyCraft 0.9".
  - `death_causes` gets "Drowned" for `CAUSE_DROWN`, and the clamp moves to `CAUSE_DROWN`.
  - World list: valid 2 shows red "(0.8 world - can't open)" with Play and Rename disabled and Delete enabled.

## Approach

### Wave 0 — design doc, prep and contracts (integrator, inline; three commits)

0. Run `git status` and `git log -1`. The tree must be clean except `.omp/` and `.asm-lsp.toml`, with HEAD `c2ebb98` or a descendant that only you made.
1. **Design doc.** Copy this plan verbatim to `docs/superpowers/specs/2026-11-08-assemblycraft-world-design.md` and commit "0.9 design: infinite streamed world, floating origin, biomes, water and boats, region sites, beds".
2. **Prep** (behaviour-preserving; commit "0.9 prep: item ids from 144, 256x512 atlas"):
   - **Item ids:**
     - `FIRST_ITEM` 144. Update the `itemdefs.asm` header comment: blocks 0..110, 111..143 unused, items 144..223.
     - Run `grep -nE "\b(1(2[89]|[3-9][0-9])|20[0-7])\b" src/*.asm`. Replace every hit that is an item id (tests, tables) with its symbolic name; leave colours, sizes and offsets alone.
     - `world_load_v3_migrates_items` and the converters stay working here; they use symbolic ids. They are deleted in step 3.
   - **Atlas:**
     - Replace `ATLAS_PX` with `ATLAS_W 256` and `ATLAS_H 512`, and set `FONT_Y 256`.
     - `render.asm`: `atlas: resb ATLAS_W*ATLAS_H*4`, `TEXIMAGE ATLAS_W, ATLAS_H`, and the texture matrix `glScalef(1/4096, 1/8192, 1)` through a new `f_texscale_v: dd 0.0001220703125`.
     - `ui.asm` `ui_begin`: the same v scale.
     - `texgen.asm`: zero `ATLAS_W*ATLAS_H*4` bytes, and update the header comment ("font at FONT_Y = 256").
   - **Check:** the build is warning-free and `make test` is 129/129.
   - **Atlas proof:** a throwaway harness dumps the atlas before and after the change. Rows 0..255 must be byte-identical except the old font texels (rows 192..239, x 0..127, now zero). Rows 256..303 must equal the old font rows.
   - **Omabox:** screenshots of the title screen and the creative inventory show identical text and icons to HEAD's. Commit.
3. **Contracts** (commit "0.9 contracts: v6 header, item and block ids, layouts"):
   1. **`common.inc`:** everything under Contracts.
      - Keep `WORLD_X`, `WORLD_Y`, `WORLD_Z`, `WORLD_VOLUME`, `CHUNKS_X/Y/Z`, `NUM_CHUNKS` and `WORLD_FILE_SIZE`, each marked "; removed at wave-1 integration".
      - Give WORLDHDR v6 `.containers_v5: resb MAX_CONTAINERS_V5 * CONTAINER_size` at offset 16656, inside pad2, with `MAX_CONTAINERS_V5 118` (118 × 136 = 16048 ≤ 16112), marked the same way.
      - `MAX_CONTAINERS` is 256 from now on, but only W5's runtime table uses it.
   2. **Containers on the v2 record** (old engine):
      - `containers.asm` `cont_at`, `cont_create`, `conts_validate` and `furnace_step` compare and read dword x/y/z.
      - The table is `world_header + WORLDHDR.containers_v5` with `MAX_CONTAINERS_V5` records.
      - `structures.asm` zeroes `.containers_v5`.
      - `test_containers.asm` and `test_structures.asm` read dword coordinates.
      - Confirm `grep -nE "WORLDHDR\.containers\b" src/*.asm` is empty.
   3. **Old formats:**
      - `world.asm`: the magic is "ACRAFT06" only. Delete `convert_v1`, `convert_v2`, `convert_v4`, `migrate_gear_v4`, `gear_unroll`, `v1_scratch`, the old magics and the `WORLD_V*`/`V1_*` defines. `world_load` accepts exactly `WORLD_FILE_SIZE` with magic "ACRAFT06", else 2.
      - `saves.asm`: the accepted magic list is "ACRAFT06". Delete the ACRAFT01 legacy branch.
      - `app.asm`: delete the legacy name copy for `WORLDENTRY.mode == 2`.
      - `test_world.asm`: delete `test_world_load_v1_converts`, `_v2_converts`, `_v3_migrates_items` and `_v4_converts`, with their `selftest.asm` rows.
      - Layout asserts: `WORLDHDR_size 32768`, `.player 68`, `.health 136`, `.inventory 156`, `.origin_x 300`, `.bed_set 320`, `.boats 332`, `.armor 944`, `.rpg 960`, `.mob_count 1024`, `.mobs 1028`, `.sites 2312`, `.jewelry 16384`, `.rpgx 16400`, `CONTAINER_size 136`, `SITE_size 56`, `COLUMN_size 408`, `MOB_size 228`, `INVENTORY_size 216`.
      - The magic checks expect "ACRAFT06".
   4. **Tables:** rows for blocks 111..129 and item BOAT in `blockdefs.asm` and `itemdefs.asm`, per the New blocks table. The tile ids point at the new tiles, which stay blank until W7. `NUM_BLOCKS` 130, `NUM_ITEMS` `FIRST_ITEM+81`.
   5. **Check:** warning-free build; `make test` = 125/125. Omabox: create a world, place a chest with an item, quit, reopen: the chest keeps the item. Commit.

### Wave 1 — eight parallel workers (one `task` batch; commit "0.9 core")

Every worker starts from the wave-0 commit, follows Conventions, and implements its sections of Design data.

|worker|owns (only these files)|implements|new tests|
|---|---|---|---|
|W1 Storage|`world.asm`, `light.asm`, new `region.asm`, new `stream.asm`, `sys.asm`, `Makefile`, `test_world.asm`, `test_light.asm`, new `test_stream.asm`|Columns and pool, `world_*` API on local coordinates, light, region files and blobs, streaming and the generator thread, `time_mono`/`file_pread`/`dir_remove_tree`/`mkdir_p`, `-pthread`. Rewrites `world_bounds`, `world_set_marks_dirty`, `world_save_load` and the light tests (out-of-world probes become unloaded-column probes at x = 1000)|`world_rebase`, `region_roundtrip`, `light_column_order`, `light_water`, `stream_sync`, `stream_thread`|
|W2 Render|`mesher.asm`, `render.asm`, `test_mesher.asm`|Meshing and rendering: padded copy, chunk-local vertices, translucent range, water, cross, per-chunk translate, frustum, translucent pass, underwater fog, `render_column_freed`, `boats_render` call. Rewrites the `mesh_*` tests for chunk-local positions|`mesher_water`, `mesher_cross`, `render_frustum`|
|W3 Terrain|new `noise.asm`, `worldgen.asm`, `test_worldgen.asm`|Terrain section. Rewrites `worldgen_deterministic`/`_shape`/`_ores` on `gen_column`|`worldgen_biomes`, `worldgen_column_independence`, `worldgen_spawn`, `worldgen_water_ice`|
|W4 Sites|`structures.asm`, `rpg.asm`, `test_structures.asm`, `test_rpg.asm`|Sites section; retiring `RPGSAVE.cleared`/`flags` bit 0. Rewrites the 5 structure tests|`sitestate_eviction`, `region_plan_camps`|
|W5 Entities|`mobs.asm`, `drops.asm`, `arrows.asm`, `explode.asm`, `fire.asm`, `fx.asm`, `dmgnum.asm`, `abilities.asm`, `containers.asm`, `test_mobs.asm`, `test_containers.asm`, `test_fire.asm`, `test_drops.asm`, `test_fx.asm`|Entities section, shift hooks, runtime `conts[]`. Rewrites `mob_spawn_rules` and the direct `blocks`/`light_cells` writes in `test_mobs.asm`|`entities_rebase`, `entities_remove_box`, `containers_signed`, `mob_water_ai`|
|W6 Gameplay|`player.asm`, `survival.asm`, `placement.asm`, new `sleep.asm`, new `boats.asm`, `hud.asm`, `menus.asm`, `test_physics.asm`, `test_survival.asm`, `test_blocks.asm`, `test_hud.asm`|Water/swimming/breath, Boats, Beds and sleep, HUD and menus, `player_shift`, `move_axis` export, replaceable placement rule|`swim_physics`, `breath_and_drowning`, `bed_place_and_break`, `sleep_rules`, `bed_respawn`, `boats`|
|W7 Blocks and art|`texgen.asm`, `blockdefs.asm`, `itemdefs.asm`, `items.asm`, `shapes.asm`, `test_items.asm`, `test_shapes.asm`|New blocks, items and art: the 20 tiles, the shape cases, `cell_boxes` on `world_column_ready`, recipes, final table values. `CASE` rows for the 4 new recipes in `craft_advanced_recipes`|`new_blocks_tables`, `shapes_new`|
|W8 Flow|`game.asm`, `app.asm`, `saves.asm`, `main.asm`, `test_saves.asm`, `test_game.asm`|Saves, world list and app flows; Floating origin trigger and `game_shift_origin`; dispatch. Rewrites `saves_scan_rename_delete` and `game_save_load_roundtrip` for v6 directories|`game_rebase_trigger`, `saves_old_world_incompatible`|

**Stubs and fakes** (each faithful to Contracts; scratch only):
- **W1:**
  - `gen_column` fake: y 0 BEDROCK, 1..59 STONE, 60 GRASS, top 60, biome PLAINS. For column (0,0) only, a CHEST at (3, 61, 3) and a matching `GENCHEST` table 0.
  - `gen_biome` → PLAINS.
  - `structures_fill_chest` puts 1 STICK in cell 0.
  - `render_column_freed` and `game_unload_box` are `ret`.
  - `conts` (`resb MAX_CONTAINERS*CONTAINER_size`), `cont_create` (first free record), `conts_free_column`.
- **W2:**
  - A fake world: `columns`, `world_column`, `world_chunk` over 3×3 columns of real `CHUNK_BYTES` buffers that the tests fill.
  - `world_origin_x/z` dd 0, `stream_spiral`/`stream_spiral_n` (3×3 order), `time_mono` (returns 0), `player_eye_in_water` (0), `boats_render` (`ret`).
- **W3:** `structures_stamp` is `ret`.
- **W4:**
  - `gen_height` = `100 + ((x sar 4) & 3)`.
  - `gen_biome` = `((x sar 9) + 3·(z sar 9)) mod 6 + 1`, so every land biome occurs.
  - `world_column_ready` returns 1 for x, z in −16..271.
  - W4's tests must be written as properties that also hold on the real terrain, for example "each camp's centre biome is in its home set". They are re-run after integration.
- **W5:**
  - `world_column_ready` as for W4.
  - `body_in_water` = the feet cell is WATER.
  - `structures_on_boss_killed` is `ret`.
  - `world_origin_x/z` dd.
- **W6:**
  - `world_column_ready` as for W4, `world_origin_x/z` dd 0.
  - `drops_spawn` exists. `mob_is_hostile` and `sky_is_night` exist.
- **W7:** `world_column_ready` as for W4.
- **W8:** `ret`/constant fakes for every new API it calls:
  - `stream_*` (`area_ready` → 1), `world_save_dirty` → 0, `gen_find_spawn` → (8, 61, 8);
  - `boats_*`, `sleep_*`, `structures_refresh`, `structures_shift`, the eight `*_shift`, `player_shift`, the four `*_remove_box`;
  - `dir_remove_tree` (a real recursive delete in scratch), `mkdir_p`, `time_mono`, `world_rebase`.

**Test contents** (inputs fixed here; expectations follow Design data):
- **`world_rebase` (W1):**
  - `world_set(3,20,4,GLASS)` and `world_set(−5,10,−7,BRICK)`.
  - `world_rebase(512,−512)` → origin (512, −512), `world_get(3−512, 20, 4+512)` = GLASS.
  - `world_rebase(−512, 512)` → `world_get(−5,10,−7)` = BRICK.
  - Also: `world_is_solid(1000,10,1000)` = 1 (unloaded), `world_get(1000,10,1000)` = AIR, `world_is_solid(5,−1,5)` = 1, `world_is_solid(5,300,5)` = 0, and a set/get at y = 255.
- **`region_roundtrip` (W1):** a temp world dir `/tmp/ac9t-region`.
  - Column (0,0): STONE at y 0..9, GLASS at (2,200,3), FIRE at (1,10,1), a chest at (4,10,4) holding DIAMOND×3.
  - Column (−1,0): BRICK at (−3,40,5).
  - Mark both `CF_MODIFIED`. `world_save_dirty`.
  - The files `r.0.0.bin` and `r.-1.0.bin` exist.
  - `region_read_column` of each matches every block, with FIRE read back as AIR and the chest container restored with its item.
  - Rewriting (0,0) with 6 more chunks of noise blocks moves its entry to a new sector at EOF. Rewriting it small again stays in place.
  - A blob with its magic byte flipped (via `file_patch`) reads as absent.
- **`light_column_order` (W1):** a 3-column test layout with a stone roof spanning columns (0,0) and (1,0) at y 20, a torch under it at (15,15,8), and a wall.
  - Lighting the columns in order A, B, C and then (after a light reset) C, B, A gives byte-identical light in all three.
  - Both equal `light_compute_all`.
- **`light_water` (W1):** WATER fills x 5..7, z 5..7, y 10..14 over a stone floor at y 9, inside a stone ring (x 4..8, z 4..8 border, y 9..14) with open sky above. Sky light at (6, y, 6) for y = 14..10 is 14, 13, 12, 11, 10.
- **`stream_sync` (W1, no thread):**
  - `render_dist` 2 and `stream_begin(42, /tmp/ac9t-stream)`.
  - `stream_update(8, 8, 1.0)` up to 50 times, until every column within Chebyshev 3 of column (0,0) has `state == COL_LIT` (checked directly; meshing is render's).
  - Column (1,1)'s blocks equal a direct `gen_column` of (1,1).
  - `world_set(20,70,20,GLASS)`. Move the centre to (3000, 8): column (1,1) unloads (`world_column(1,1)` = 0).
  - Move back: GLASS is at (20,70,20) again, read from the region.
- **`stream_thread` (W1):** `stream_thread_start`, `stream_begin(7, 0)`, `stream_update` around (−40, 72) until column (−3, 4) is LIT (bounded by 5 s of `time_mono`). Its blocks equal a sync `gen_column(−3, 4)`. Then `stream_thread_stop`; `pthread_join` returns 0.
- **`mesher_water` (W2):** a stone floor y 9, x 0..4, z 0..4, and WATER at y 10, x 1..3, z 1..3.
  - The translucent range holds exactly 21 quads (84 vertices): 9 tops at y = 10·16+14, and 12 sides facing air.
  - The opaque range holds no WATER faces.
- **`mesher_cross` (W2):** a TALL_GRASS at (5,10,5) on stone. The opaque range has exactly 16 vertices from that cell, with TILE_TALL_GRASS uv. The stone top under it is still emitted.
- **`render_frustum` (W2):** a camera at (0,1.62,0) with yaw 0, pitch 0, fov 70, aspect 16/9.
  - A centre 20 ahead is visible, 20 behind is culled, and 40 to the side at 90° is culled.
  - A centre 10 behind is visible, since it is within the 14 margin.
- **`worldgen_biomes` (W3):** seed 42, `gen_biome` on a 16-block grid over |x|, |z| ≤ 3072.
  - All 8 biome ids occur.
  - OCEAN covers 10–45%, and each of PLAINS, FOREST, DESERT, SNOW, SWAMP, MOUNTAINS covers ≥ 2%.
- **`worldgen_column_independence` (W3):**
  - FNV of column (0,0) generated first equals FNV after generating 10 other columns, then (0,0) again.
  - Every LEAVES, PINE_LEAVES or BIRCH_LEAVES cell of column (1,0) with x in 16..18 has a LOG, PINE_LOG or BIRCH_LOG within 3 cells horizontally and 6 vertically, in the union of both columns' outputs. So no leaf floats where its trunk was clipped away.
- **`worldgen_spawn` (W3):** seed 42 gives a cell whose biome is not OCEAN, RIVER or MOUNTAINS, with y − 1 = `gen_height` ≥ 97. No centre of a smaller ring qualifies, and the result is deterministic.
- **`worldgen_water_ice` (W3):**
  - The first OCEAN column centre on the 16-grid from (0,0) has WATER or ICE in every cell from h+1 to 96.
  - Over the OCEAN and RIVER 16-grid centres within 3072 (the first 64), at least one column has ICE at y 96 and at least one has WATER at y 96.
- **Rewritten worldgen tests (W3):**
  - `deterministic`: column hashes for seed 42 at (0,0) and (−3,5); seed 43 differs.
  - `shape`: over 16 columns, y 0 is all BEDROCK, every id < `NUM_BLOCKS`, WATER only at y ≤ 96, and top in [8, 240].
  - `ores`: over 8×8 columns from the spawn column, COAL ≥ 200, IRON ≥ 100, GOLD ≥ 10, DIAMOND ≥ 2, with ceilings diamond ≤ 18, gold ≤ 40, iron ≤ 80.
- **`sitestate_eviction` (W4):**
  - Fill 1024 records with regions (100+i, 0).
  - With the player near region (0,0), `site_state` of a new site evicts the record of region (1123, 0).
  - A record referenced by a live mob's origin is never evicted.
- **`region_plan_camps` (W4):** seed 42, super-region (0,0):
  - Every camp's centre biome is in its faction's home set.
  - Camps are ≥ 128 apart and ≥ 96 from their region's village.
  - Each faction appears at most once.
  - Only regions with even rx and rz have a crypt, and at least 5 of the 9 such regions in −2..2 have one.
  - No region has more than 2 dungeons, and at least 20 of the 25 regions in −2..2 have at least 1.
- **Rewritten structure tests (W4):**
  - `structure_sites_deterministic`: `region_plan` twice gives identical output; seed 43 differs.
  - `dungeon_built_with_chests`: `gen_column` of every column under dungeon 1 of region (0,0) gives open rooms, walls, 4 GENCHESTs in total, and a stair tunnel cell at the surface.
  - `village_built_with_npcs`: stream the village's 3×3 columns (sync), then step 60 → one merchant and one elder at their homes; stepping again spawns no duplicates.
  - `dungeon_clears_after_kills`: 8 kills → `SS_CLEARED` and XP paid once.
  - `crypt_spawns_boss_once`: as before, with the state in SITESTATE.
- **`entities_rebase` (W5):**
  - A mob at (1000.5, 20, −1000.5) with home (1001, −999), a drop, an arrow, a primed TNT, a fire at cell (1000, 20, −1000), a particle and a dmgnum.
  - Each `*_shift(512, −512)` gives exact positions minus (512, −512), and the fire cell (488, 20, −488).
- **`entities_remove_box` (W5):** the items inside box (0,0)–(15,15) are removed and the ones at x = 16 stay, for mobs, drops, tnt and fires.
- **`containers_signed` (W5):**
  - `cont_create(−5, 200, −300, CONT_CHEST)` → `cont_at(−5, 200, −300)` returns it.
  - After `world_rebase(512, 0)`, `cont_at(−517, 200, −300)` returns the same record.
  - The 65th container in one column is refused.
  - `conts_free_column` frees them.
- **`mob_water_ai` (W5):**
  - A pig on a grass strip heading toward a WATER pool 3 cells ahead: after 300 steps it has never stood in WATER.
  - A zombie spawned in 4-deep water holds `jump`.
- **`swim_physics` (W6):** a pool of WATER 5 deep.
  - Falling from 20 above the surface into it never calls `survival_land` with damage (health unchanged in Survival).
  - Sinking settles at vy ≥ −2.5. Holding jump gives vy = 3.0.
  - Horizontal speed in water is half the speed on land over 60 steps (±5%).
- **`breath_and_drowning` (W6):**
  - Eye in water: breath 600 → 0 after 600 steps. Then 1 damage every 60 steps (`env_scale` at max health 20 → 1) with cause `CAUSE_DROWN`.
  - Out of the water it refills by 5 per step.
  - `hud_bubble_tiles(330)` → 5 full, 1 pop, 4 none.
- **`bed_place_and_break` (W6):**
  - Yaw facing E on a stone floor gives BED+1 at (5,10,5) and BED+5 at (6,10,5).
  - Breaking the head removes the foot and spawns exactly one BED drop.
  - A solid head cell refuses the placement.
- **`sleep_rules` (W6):**
  - At time 6000: refused with the day banner, and the respawn is set.
  - At time 54000 with a zombie at 5 blocks: refused with the monsters banner.
  - With the zombie at 12 blocks: sleeping. After 120 steps the time is 72000 (and 144000 from 126000).
  - Damage at step 60 cancels with the time unchanged.
- **`bed_respawn` (W6):**
  - Bed set → `sleep_respawn_target` = the foot. `sleep_place_at_bed` stands the player on a free neighbour.
  - The bed removed → it returns 0, `bed_set` = 0.
  - A bed walled in on all 8 neighbour cells with stone 2 above → obstructed, 0.
- **`boats` (W6):** water at y 10 on a 20×20 pool.
  - `boats_place` from the shore gives 1 boat at y 10.625.
  - Mount; W for 90 steps moves 3.5..5.0 blocks along the yaw; y stays within 10.625 ± 0.1.
  - Sneak dismounts.
  - Break → 1 BOAT drop in Survival.
  - A save/load round trip keeps x/y/z/yaw. `boats_shift` moves it.
- **`new_blocks_tables` (W7):** every row of the New blocks table matches flags, shape, tiles, hardness, drop and max stack. Names are "Bed", "Boat", "Pine Log", "Birch Log", "Snow Block", "Mud", "Cactus", "Ice".
- **`shapes_new` (W7):**
  - BED gives 1 box (0,0,0,16,9,16) for each purpose.
  - LIQUID gives 0 boxes for every purpose.
  - CROSS gives COLLIDE 0, SELECT 1 (2,0,2,14,13,14) and RENDER 0.
  - SNOW gives RENDER/SELECT (0,0,0,16,2,16) and COLLIDE 0.
  - CACTUS gives (1,0,1,15,16,15) for every purpose.
  - `cell_boxes` COLLIDE at an unloaded column gives 1 full box.
- **`game_rebase_trigger` (W8):** `player.x = 1030.25`, `player.z = −2050.5`, then one `game_rebase`. Origin (1024, −2560) (`floor(−2050.5) sar 9 shl 9`), player at (6.25, 509.5), and `game_target.bx` shifted by −1024.
- **`saves_old_world_incompatible` (W8):** a temp `worlds/` with a v6 dir world "A", a file `Old.acw` and a file `note.txt`.
  - `saves_scan` gives 2 entries: "A" valid 1 and "Old" valid 2.
  - `saves_delete` of "Old" removes the file. Of "A", it removes the directory and its `regions/` tree.

**Integration** (integrator), in this order:
1. Copy the owned files back worker by worker in the order W1, W2, W3, W4, W5, W6, W7, W8, each after a `cmp` against its base.
2. Delete `WORLD_X`, `WORLD_Y`, `WORLD_Z`, `WORLD_VOLUME`, `CHUNKS_*`, `NUM_CHUNKS`, `WORLD_FILE_SIZE`, `MAX_CONTAINERS_V5` and `.containers_v5` (it becomes pad2 again). `grep -nE "\bWORLD_[XYZ]\b|WORLD_VOLUME|NUM_CHUNKS|CHUNKS_[XYZ]|WORLD_FILE_SIZE|containers_v5|_V5\b" src/*.asm src/*.inc` must print nothing.
3. Register the 29 new tests in the table's order.
4. The build is warning-free; `make test` = 154/154.
5. Fix integration breaks in the owners' style. Expected seams:
   - leftover callers of deleted symbols (`world_generate`, `worldgen_height`, `structures_plan`, `structures_generate`, `structures_spawn_npcs`, `conts_validate`, `fire_rebuild`, `light_cells`, `chunk_dirty`, `mesh_chunk`'s old return);
   - the `spawn_at_ground` signature;
   - `render_update_chunks`/`light_update` call sites in `app.asm`;
   - unowned tests that relied on x or z outside −16..271 (`test_guns`, `test_combat`, `test_melee`, `test_status`, `test_abilities`, `test_gear`, `test_settings`).
6. Omabox smoke: create a world, see terrain, walk to water, quit, reopen. Commit.

### Wave 2 — live verification and tuning (integrator)

1. Write `/tmp/acpatch9.py` (Conventions).
2. Write a throwaway scratch-only selftest helper that prints, for seed 42, the first 16-grid cell of each biome around (0,0), and the nearest village, dungeon, crypt and camp from `region_plan`. These are teleport targets for the patcher.
3. Run the live checks of Verification in order. Fix bugs in the owners' style, with a regression test where a unit test can catch it.
4. Performance and memory runs (Verification 4–5). If a target is missed, adjust only these knobs, in this order, re-running after each:
   - the play mesh budget, 6 → 3 ms;
   - stream installs per frame, 4 → 2;
   - light columns per frame, 6 → 3;
   - the contingency below.
5. Commit "0.9 tuning from live checks" if anything changed.

### Wave 3 — V1 readiness sweep (commit "0.9 V1 sweep")

1. Spawn 4 read-only `reviewer` subagents on disjoint areas. Each returns findings as file:line, a reproduction, and a severity: crash, save corruption, softlock, broken feature, or cosmetic.
   - R1 storage: `world.asm`, `light.asm`, `region.asm`, `stream.asm`, `sys.asm`: thread races, pool and table exhaustion, the region writer.
   - R2 render and flows: `mesher.asm`, `render.asm`, `app.asm`, `game.asm` load/save/respawn, `saves.asm`, `menus.asm`.
   - R3 generation: `worldgen.asm`, `noise.asm`, `structures.asm`, `rpg.asm`: determinism, seams, site state.
   - R4 gameplay: `player.asm`, `survival.asm`, `placement.asm`, `sleep.asm`, `boats.asm`, `mobs.asm`, `containers.asm`, `fire.asm`, and every `*_shift`.
2. Fix every crash, save-corruption, softlock and broken-feature finding, each with a regression test. Re-run `make test` and the Verification 3g/3h live checks.
3. Append "As built (deviations from this plan)" to the design doc. Commit.

## Critical files & anchors

- `src/world.asm`: `world_get`/`world_set`/`world_is_solid` (0.8 lines 33–160) become the column fast path. `world_load`/`world_save` and the converters (224–524) disappear by integration. Every module's notion of "outside the world" changes here.
- `src/light.asm`: `light_recompute` → `light_columns`, `light_seeds`, `light_sources`, `light_flood`, `light_compare` (341–806). The algorithm is kept and retargeted to chunk storage, absolute regions, a y cap, the top face as a source, `l_att`, and the `light_column` increase pass.
- `src/mesher.asm`: `mesh_chunk` (143–459), `emit_face` (522–533, the absolute ×16 positions become chunk-local) and the `PROBE` macro (112–127, which becomes pad reads).
- `src/structures.asm`: `place_chest` (708), `box_fill` (518), `stair_tunnel` (643), the builders (871/909/949), `structures_step` (1299) and `structures_nearest` (1441). The builders keep their BOX tables but write through `gb_set`.
- `src/game.asm`: `game_new`/`game_load`/`game_save`/`game_respawn` (131–420), the `sim_step` order (1561–1689), and the right-click (1205–1330) and left-click (881–1031) dispatch.

## Verification

1. **Build and tests:** `make clean && make 2>&1 | grep -iE "warn|error"` prints nothing. `make test` ends with `selftest: 154 passed, 0 failed`.
2. **Data checks:**
   - `git status --short` shows only `.asm-lsp.toml` and `.omp/` untracked.
   - `grep -nE "\bWORLD_[XYZ]\b|WORLD_VOLUME|NUM_CHUNKS|world_generate|worldgen_height|structures_plan|ORIGIN_CRYPT|RPGSAVE\.cleared" src` prints nothing.
3. **Live checks** in the omabox box (Conventions), each proven by a screenshot (`omabox shot --window assemblycraft --fit 960`) or a file check:
   - a. `--play v9a --seed 42`, Survival: terrain with water and trees at spawn. F3 shows `Biome:`, `Columns:` and the four site lines, including `Camp:`.
   - b. **Biomes:** for each of the 8 biome targets from wave 2's helper, patch `origin`/`pos` there. The screenshot shows F3 `Biome: <name>` and the matching look: sand/cactus, snow layer/ice, pine, birch, mud/water, peaks with snow, ocean, river.
   - c. **Water:** walk into a lake. Underwater, the fog is blue and the bubble row shows. Hold still underwater for 12 s: health drops. Leaving long enough kills: the death screen says "Drowned".
   - d. **Boat:** with `slot=0:224:1` at a river from the helper, right-click the water (a boat appears), right-click it (mounted), hold W for 5 s: F3 XYZ moved ≥ 15 blocks along the river, and the boat floats at the surface. Repeat over ocean water ≥ 64 blocks wide. Sneak dismounts.
   - e. **Beds:** `slot=0:122:1` with `time=54000`: place the bed, right-click it → fade, then F3 shows the next day at 06:00. With `mob=0:1:20:3:0:0` (a zombie 3 blocks away) the banner says "Respawn set. Monsters are nearby".
     - Die (`health=1` and a fall): respawn next to the bed.
     - Break the bed and die again: the banner "Your bed was missing or obstructed" shows and the player is at the world spawn.
   - f. **Dungeon and crypt:** teleport into the nearest dungeon (helper coordinates). The rooms are visible, the chests open with loot, and elites spawn within 10 s (Survival). Teleport into the crypt: the boss banner shows.
   - g. **Far travel and persistence:** `origin=20480:-30720`, `pos=100:120:100`, Creative. F3 shows absolute ≈ (20580, …, −30620). Place GLASS and a chest with a DIAMOND, then quit to title. `ls <data>/worlds/v9a/regions/` shows `r.40.-60.bin`. Reopen: the same coordinates, GLASS and the chest with its DIAMOND.
   - h. **Rebase:** Creative flight from local x 1000 toward +x for 5 s. Two screenshots across the 1024 crossing show continuous F3 absolute coordinates and no visual jump. After a save, the patcher reads `origin_x` = old + 1024.
   - i. **Old save:** copy the repo's ignored `world.acw` (an ACRAFT02 file; any `*.acw` is listed as old) into `worlds/Old.acw`. The list shows "(0.8 world - can't open)" with Play disabled. `sha256sum` is unchanged after listing and clicking Play. Delete removes it.
   - j. **Title:** the panorama shows streamed terrain.
4. **Performance** (a scratch-only patch, never committed): `render_dist` 16, `vsync=0`, `PULSE_SERVER=unix:/nonexistent`, Creative flight at 16 blocks/s along +x for 2,000 blocks, logging every frame's dt to stderr.
   - Target: 0 frames over 50 ms after the initial load.
   - Report the max and the p99.
   - At `render_dist` 8 in a village, ≥ 60 FPS.
5. **Memory:** after that flight, VmRSS (`omabox run -- grep VmRSS /proc/<pid>/status`) < 1.5 GB, and the F3 pool count stays ≤ 24576 with no "pool full" line on stderr.

## Assumptions & contingencies

- **User decisions:** Minecraft-like sleep; true infinite world through a floating origin (int32 absolute coordinates wrap at ±2^31, left unhandled); no pre-0.9 save compatibility. Faction names, camp home biomes and sea level 96 come from the roadmap; 0.10's brainstorm can still change them.
- **Deviations from the roadmap, chosen here:**
  - Light runs on the main thread, with exact incremental column lighting. The roadmap put it on the worker.
  - Light is not stored in region files; the roadmap said packed light. It is recomputed as in 0.7.
  - A column holds at most 64 containers (the roadmap said 32) in a global runtime table of 256.
  - Only modified or container-holding columns are saved.
- **Thread fallback:** if `pthread_create` fails at runtime, print "generator thread unavailable; generating on the main thread" and use the inline path with the frame budget.
- **Performance fallback:** if frames over 50 ms remain after the wave-2 knobs, cap `render_dist` at 12 for 0.9 (the options slider max and the clamp). Record it in As built; the 1.0 performance pass revisits it.
- **Pool:** if the mountain flight hits "chunk pool full", raise `POOL_CHUNKS` to 32768.
- **Biome tuning:** thresholds may move by ±50% to meet `worldgen_biomes`. Changes are recorded in As built.
- **Scope (roadmap):** if wave 1 slips, boats move to 0.10. Water, swimming and beds stay in 0.9.

## As built (deviations from this plan)

Recorded at the end of milestone 0.9. Everything not listed here was built as specified.

### Contracts and ids
- **`BOATENT`, not `BOAT`.** The boat struct is named `BOATENT` (like `ARROWENT`), because `BOAT` is the item-id `%define`.
- **Gear rolls keep their 0.8 values.** `gear.asm`'s affix hash uses `id' = id - FIRST_ITEM + 128`, so moving `FIRST_ITEM` from 128 to 144 left every gear roll (and its golden tests) unchanged.
- **Retired fields.** `RPGSAVE.cleared`/`.flags` became one `.retired` word (layout unchanged); `NUM_DUNGEONS`, `player_spawn` and `world_mark_all_dirty` were deleted once nothing used them.

### Storage, light and streaming
- **Pool:** a bump allocator plus a free stack instead of a pre-filled stack (O(1) reset).
- **`world_install`** writes containers straight into `conts[]`; `world_install_err` says why it refused (1 pool, 2 container table). `world_set` also sets `CF_CONTS` for CHEST/FURNACE blocks.
- **`world_top_y`** scans the cell's own column down from `COLUMN.top` (the column-wide top is only a bound). Found at integration: the first version returned the column-wide top, which broke mob spawning beside taller blocks.
- **Edit regions** are whole columns (3×3 around the edit, merged up to 4×4), and their y cap is the highest top of the 3×3 window + 16, which keeps lighting order-independent next to taller neighbours.
- **Region files:** blobs never land below sector 3; a file with a bad header is recreated when written; `world_save_dirty(dir)` resets the region cache through `region_set_dir`.
- **`stream_update`** starts and lights at least one column per call, even with a spent budget. Budgets run on `time_mono_ns` (64-bit nanoseconds); `render_update_chunks` too, after review found the float deadline stopped working after ~36 h of uptime.
- **`render_update_chunks`** centres its spiral on the camera of the last `render_world` and falls back to scanning the whole table when that finds nothing (a load wait draws no frame).
- **Extra exports:** `world_set_raw`, `world_column_claim`, `world_drop_all`, `world_chunk_alloc`, `world_locate`, `region_dir`, `region_has_column`, `time_mono_ns`, `gen_seed`, `spawn_at_ground`, `meteor_tgt`/`rain_tgt`, `sleep_active`/`sleep_timer`, `banner_text`.

### Terrain
- **Continentalness salt 1001, not 1000.** With 1000, seed 42's ±3072 window is 53% ocean, beyond what the ±50% threshold tuning can fix; no threshold was changed. Coverage for seed 42: ocean 39.2%, plains 13.6%, forest 16.9%, desert 5.5%, snow 10.3%, swamp 7.2%, mountains 3.9%, river 3.5%. Seed 42 spawns at (8, 103, 8) in snow.
- **Ores:** walks are seeded with `acx*32 + attempt` (with `*16`, coal attempt 16 repeated the next column's attempt 0) and clipped to each ore's y range.
- **Cave protection** under shallow water is `y >= h - 4`.
- **`gen_column`** costs about 0.2 ms per column without sites.
- **Rivers** are 1–3 blocks deep at their centre (the plan's `lerp(93, h, …)`) and their RIVER-biome edges are often dry sand; cold rivers freeze over.

### Sites
- **Plan caches:** 16 entries each (one for the generator thread, one for the main thread), keyed through the seed, so nothing is flushed when the seed changes.
- **Dungeon and boss levels** are computed in `structures.asm` (player level + 2; + 3 with a floor of 20 for the boss).
- **Village NPCs** are re-created in every mode, when both the village centre column and the NPC's cell column are ready.

### Gameplay and flows
- **Boats:** a right-click boards the boat in front before trying to place one (the plan's order made boarding impossible with a boat in hand, e.g. in Creative). The hull floor is 5/16 thick so it hides the water surface inside the boat. Saved boats are accepted up to ±2^24 (exact floats), so a boat left 65,536+ blocks behind by rebases is no longer dropped on load.
- **Swimming:** water is checked at the start and the end of a step, so a fall into 1-deep water is soft too.
- **F3:** XYZ, Target and the site lines show absolute coordinates; the quest tracker moved down 3 lines.
- **Placement:** a torch aimed at tall grass or snow replaces it and stands on the block below; a ladder cannot hang on a plant.
- **Containers:** `abilities.asm`'s charge/slam hit masks became 64-bit for `MAX_MOBS` 64; `fire_place` refuses unready columns; furnaces in unloaded columns pause entirely.
- **`game_new`** calls `stream_begin` before `gen_find_spawn` (the spawn search needs the seed). **`game_load`** validates into a private buffer first, masks the origin, clamps counts, and treats a non-finite or far position like a dead player.
- **`app_wait_area`** returns 1 when the window closes; closing during "Generating terrain" removes the half-made world directory.
- **`--play NAME`** on an old `.acw` prints exactly "NAME is a world from 0.8 or earlier; this version cannot open it" (no prefix) and exits 2.

### Verification results (wave 2)
- `make test`: 154/154, warning-free.
- Live checks a–j passed in omabox (biomes, drowning with "Drowned", boats on a river 18.9 blocks and on the ocean 23 blocks in 5 s, sleep to 06:00 and the monsters banner, bed respawn and the missing-bed banner, dungeon rooms/loot/elites, crypt boss, far travel to r.40.-60.bin with glass and a chest kept, rebase continuity with `origin_x` +1024, the old-world list entry with an unchanged sha256 and Delete, the streamed panorama).
- Performance at render distance 16, vsync off, no audio, 2,194 blocks of flight at 16 b/s: 0 frames over 50 ms, max 26.4 ms, p99 5.5 ms, median 1.5 ms. Village at render distance 8: ~1,400 FPS. No performance knob or fallback was needed.
- Memory after the flight: VmRSS 495 MB, pool 8,821/24,576 chunks, no "pool full".

### Wave 3 review fixes
Four read-only reviewers found no crash. Every fix below has a regression assertion inside an existing test (the count stays 154), each proven to fail on the unfixed code.
- **Column top after a dig** (storage): removing a block from a column's top layer rescanned from the layer below, so `COLUMN.top`, `world_top_y` and the light cap dropped while other blocks stayed on that layer (mobs spawned inside the ground, platforms lost their light). The rescan now starts at the cleared layer.
- **Full container table froze streaming** (softlock): one column that `world_install` refused blocked every collect and dispatch. Now only that column waits 60 frames (`fail_until` per slot); every other column carries on.
- **Mesh budget after long uptime:** see Storage above (`time_mono_ns`).
- **Far moored boats were dropped on load** (save loss): the load bound is now ±2^24.
- **Sites:** about a third of crypts sat under oceans or rivers with the entrance on the seabed, and ~2% of dungeon tunnels dead-ended in rock under mountains. A pure `tunnel_exit` walk (shared with `stair_tunnel`) now lets the planner reject a dungeon or crypt whose tunnel has no exit within 60 columns or exits at or below sea level, and crypts reject OCEAN/RIVER centres. Seed 42 over regions −6..6: 207 dungeons (was 211), 39 crypts (was 49); 8 of the 9 even regions in −2..2 keep a crypt.
- **Sleep:** a bed with a solid block in either of the 2 cells above refuses ("Respawn set. The bed is obstructed"); the sleeper gets up beside the bed in the morning; sleeping starts by leaving a ridden boat.
- **Mobs left outside the streamed area** (after a respawn far away, or saved in the outer ring) stayed frozen forever and filled the spawn caps; a frozen mob more than render distance + 2 columns from the player is now forgotten.
- **Boats:** a boat put in next to a bank is nudged 0.11 away from solid sides (refused when hemmed in on an axis), so it can no longer be driven through walls; while ridden its box is 2.05 high, so it stops at a ceiling the rider's head would hit.
- **Plants:** tall grass and snow layers pop when the block under them goes.
- **Leaves:** pine and birch leaves roll the axe/apple drop like oak leaves.

### Deferred (no GitHub remote: listed here)
- Region writes are not crash-atomic (planned for 1.0); absolute coordinates wrap at ±2^31 (not handled, per the plan).
- Rivers are shallow and their biome edges dry; cold rivers freeze.
- Explosions destroy WATER cells like any other block (no flowing water exists to refill them).
- If 8 freshly generated chest columns fail to install at once (container table full), no generator buffer is free that frame; it resolves as soon as the table has room.
- The breath bubbles share their row with the held-item name for the few seconds that name shows.
- No unit test covers the right-click order "board the boat in front before placing one"; it was verified live.
