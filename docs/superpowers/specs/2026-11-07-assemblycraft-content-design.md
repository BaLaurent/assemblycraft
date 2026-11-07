# AssemblyCraft 0.3 — ores, furnace & chest, iron/gold/diamond gear, bow, armor, TNT, creeper/skeleton/spider/chicken

## Context

AssemblyCraft (`/run/media/octopusman/Games/Experiences/assemblycraft`, branch `master`, HEAD `2228df3`) is a Minecraft-like game written entirely in x86-64 NASM (GLFW, legacy GL, libpulse-simple, no libc calls). `make test` passes 40/40. The user reports that there is too little to craft: no ores, no advanced crafting, no better weapons such as a bow, and no real monsters such as creepers. They chose this scope:
- **Monsters:** creeper, skeleton and spider.
- **Containers:** a persistent furnace and a chest. This needs a v3 save format, and existing worlds convert automatically.
- **Armor:** iron, gold and diamond.
- **Extras:** TNT with flint and steel and gravel, chickens with feathers, cooked porkchop and rotten flesh.

When this is done, every item below can be obtained in Survival and has a use, and every feature is proven by unit tests plus a live check in an omabox desktop.

## Conventions (every file)

- **File layout:**
  - `%include "common.inc"` first, then `default rel`. Files that touch GL or GLFW also `%include "gl.inc"`.
  - Select `section .text/.data/.rodata/.bss` explicitly before emitting anything.
  - Build with NASM `-f elf64 -g -F dwarf -Isrc/` and `gcc -no-pie`. The Makefile already globs `src/*.asm`, so new files need no Makefile change.
- **Calling convention:** SysV for every function, internal ones included.
  - Callee-saved registers are rbx, rbp, r12–r15. Every xmm register is caller-saved.
  - `rsp` is 16-aligned at every call. Arguments 7 and up go at `[rsp]`.
- **Floats:** scalar SSE only (floor is `roundss 9`). x87 is used only in `mathf.asm`.
- **Symbols:** each file declares its own `extern`/`global`. NEVER put cross-module externs in `common.inc`.
- **Tests:**
  - A test is `test_<name>() → eax`, 0 = pass, and its first call is `call world_clear`.
  - Register it in `src/selftest.asm` with `TEST`/`TESTNAME` plus an `extern`. The printed name is the function name without `test_`.
  - A test sets every global it relies on (`game_mode`, `settings.difficulty`, `game_time`, `rng_seed`, `inv`, `inv_container`, `surv`), and resets `inv`, `drops`, `arrows` and primed TNT when done.
- **If a test expectation fails while the code matches this plan,** re-derive the value from the formulas here (gdb on the build) before touching the test.
- **Parallel agents:** run `git status --short && git log --oneline -3` before starting and before each commit.
- **GUI checks (omabox):**
  - Run `omabox up --audio` with cwd `$HOME`; from the repo it refuses.
  - Copy the binary with `H=$(omabox -b default path --home); cp build/assemblycraft "$H/.ac.new" && mv -f "$H/.ac.new" "$H/assemblycraft"`.
  - Switch to a US layout once: `omabox -b default lua 'hl.config({input={kb_layout="us", kb_variant=""}}); return "ok"'`.
  - Close the window with `omabox -b default lua 'hl.dispatch(hl.dsp.window.close({window="class:assemblycraft"})); return "sent"'`.
  - Mouse look cannot be tested in a box.
  - Click with `omabox -b default click --in <fresh shot> X Y`, and only on a shot of the current window.
- **Header patcher:** `/tmp/acpatch.py` (a throwaway tool; recreate it if it is gone) patches world headers at the offsets in **Contracts → save format**:
  - `slot=N:id:count` → 4 bytes `<BBH>` at `156 + 4N`;
  - `sel` → int32 at 152; `time` → u32 at 16; `health` → int32 at 136; `food` → int32 at 140;
  - `rise=DY` → player x/y/z floats at 68/72/76 set to `spawn + (0.5, DY, 0.5)`, with spawn being the int32s at 56/60/64.
  - Mob records are 20 bytes at `304 + 20i` (`<iifff>`: type, health, x, y, z); the mob count is an int32 at 300.

## Contracts (write these first; everything else is coded against them)

### `src/common.inc` — constants

- **Blocks:**
  - `COAL_ORE 13`, `IRON_ORE 14`, `GOLD_ORE 15`, `DIAMOND_ORE 16`, `FURNACE 17`, `FURNACE_LIT 18`, `CHEST 19`, `GRAVEL 20`, `TNT 21`.
  - `NUM_BLOCKS 22`. Ids 22–31 are unused.
- **Items** (`NUM_ITEMS 82`):
  - `COAL 43`, `IRON_INGOT 44`, `GOLD_INGOT 45`, `DIAMOND 46`.
  - Iron tools: `IRON_PICKAXE 47`, `IRON_AXE 48`, `IRON_SHOVEL 49`, `IRON_SWORD 50`.
  - Gold tools: `GOLD_PICKAXE 51`, `GOLD_AXE 52`, `GOLD_SHOVEL 53`, `GOLD_SWORD 54`.
  - Diamond tools: `DIAMOND_PICKAXE 55`, `DIAMOND_AXE 56`, `DIAMOND_SHOVEL 57`, `DIAMOND_SWORD 58`.
  - `BOW 59`, `ARROW 60`, `STRING 61`, `GUNPOWDER 62`, `FLINT 63`, `FLINT_AND_STEEL 64`.
  - Food and drops: `ROTTEN_FLESH 65`, `COOKED_PORKCHOP 66`, `FEATHER 67`, `RAW_CHICKEN 68`, `COOKED_CHICKEN 69`.
  - Iron armor: `IRON_HELMET 70`, `IRON_CHESTPLATE 71`, `IRON_LEGGINGS 72`, `IRON_BOOTS 73`.
  - Gold armor: `GOLD_HELMET 74`, `GOLD_CHESTPLATE 75`, `GOLD_LEGGINGS 76`, `GOLD_BOOTS 77`.
  - Diamond armor: `DIAMOND_HELMET 78`, `DIAMOND_CHESTPLATE 79`, `DIAMOND_LEGGINGS 80`, `DIAMOND_BOOTS 81`.
- **Tiers:** `TIER_IRON 3`, `TIER_DIAMOND 4`, `TIER_GOLD 5`. Wood is 1 and stone is 2, as now.
- **Armor slots:** `ARMOR_HEAD 1`, `ARMOR_CHEST 2`, `ARMOR_LEGS 3`, `ARMOR_FEET 4`.
- **Mobs:** `MOB_CREEPER 3`, `MOB_SKELETON 4`, `MOB_SPIDER 5`, `MOB_CHICKEN 6`, `NUM_MOB_TYPES 6`.
- **Causes:** `CAUSE_SKELETON 5`, `CAUSE_EXPLOSION 6`, `CAUSE_SPIDER 7`.
- **Sounds:** `SND_EXPLODE 17`, `SND_FUSE 18`, `SND_BOW 19`, `SND_ARROW_HIT 20`, `SND_SKELETON_SAY 21`, `SND_SKELETON_HURT 22`, `SND_SPIDER_SAY 23`, `SND_SPIDER_HURT 24`, `SND_CREEPER_HURT 25`, `SND_CHICKEN_SAY 26`, `SND_CHICKEN_HURT 27`. `NUM_SOUNDS 28`.
- **App states:** `ST_FURNACE 13`, `ST_CHEST 14`. `ST_QUIT` stays 12.
- **Atlas tiles:**
  - Ores: `TILE_COAL_ORE 26`, `TILE_IRON_ORE 27`, `TILE_GOLD_ORE 28`, `TILE_DIAMOND_ORE 29`.
  - Furnace, chest, gravel, TNT: `TILE_FURNACE_FRONT 30`, `TILE_FURNACE_LIT 31`, `TILE_CHEST_TOP 43`, `TILE_CHEST_SIDE 44`, `TILE_GRAVEL 45`, `TILE_TNT_SIDE 46`, `TILE_TNT_TOP 47`.
  - HUD armor: `TILE_ARMOR_FULL 54`, `TILE_ARMOR_HALF 55`, `TILE_ARMOR_EMPTY 56`.
  - Mobs: `TILE_CREEPER_SKIN 71`, `TILE_CREEPER_FACE 72`, `TILE_SKELETON_BONE 73`, `TILE_SKELETON_FACE 74`, `TILE_SPIDER_BODY 75`, `TILE_SPIDER_FACE 76`, `TILE_CHICKEN_BODY 77`, `TILE_CHICKEN_FACE 78`, `TILE_CHICKEN_LEG 79`.
  - Items: `TILE_ITEM0 80`. The icon tile of item id `i ≥ 43` is `TILE_ITEM0 + i − 43`, i.e. tiles 80–118.
- **Inventory refs:** `SLOTREF_ARMOR 47` (refs 47–50: head, chest, legs, feet) and `SLOTREF_CONTAINER 51` (refs 51–77).
- **Containers:** `CONT_FURNACE 1`, `CONT_CHEST 2`, `MAX_CONTAINERS 120`, `SMELT_STEPS 200`.
- **Entities:** `MAX_ARROWS 48`, `MAX_PRIMED 32`.
- **Save format:**
  - `WORLD_HDR_SIZE 16384`, `WORLD_FILE_SIZE 4210688` (= 16384 + 4194304).
  - `WORLD_BASE_HDR 1024`, `WORLD_V2_SIZE 4195328`.

### `src/common.inc` — structs

- **`INVENTORY`:** append `.armor: resb 4*4` after `.cursor`. Ref r ≤ 50 then addresses `inv + 4r`; the cursor is r = 46 and is never clickable.
- **`MOB`:** append `.fuse: resd 1` (creeper fuse, in steps) after `.panic`.
- **`WORLDHDR`:** keep offsets 0–943 exactly as now. Replace `.pad: resb 80` with:
  - `.armor: resb 16` at 944;
  - `.pad: resb 64` at 960;
  - `.containers: resb MAX_CONTAINERS * CONTAINER_size` at 1024.

  `WORLDHDR_size` becomes 16384. The magic is now `"ACRAFT03"`.
- **`CONTAINER`** (128 B):
  - `.x .y .z .kind` are `resb 1` each (kind 0 = free);
  - `.slots: resb 27*4` — a chest uses all 27; a furnace uses 0 = input, 1 = fuel, 2 = output;
  - `.burn: resw 1` (steps left), `.burn_max: resw 1`, `.cook: resw 1`, `.pad: resb 10`.
- **`ARROWENT`** (48 B; named so because `ARROW` is the item id 60):
  - `.x .y .z .vx .vy .vz` (float);
  - `.age`, `.stuck` (0 = flying, else steps stuck), `.owner` (0 player, 1 mob), `.damage`, `.pickup` (0/1), `.live` (0/1), all `resd 1`.
- **`PRIMED`** (16 B): `.x .y .z` (float, block centre) and `.fuse` (`resd`, steps).

### Module API (new and changed globals)

|File|Symbol|Contract|
|---|---|---|
|`containers.asm` (new)|`cont_at`|`(edi x, esi y, edx z)→rax CONTAINER*` or 0. It scans `world_header + WORLDHDR.containers`|
||`cont_create`|`(edi x, esi y, edx z, ecx kind)→rax` or 0 when all 120 are used. It reuses a record already at that position, zeroes it, then sets x, y, z and kind|
||`cont_block_removed`|`(edi x, esi y, edx z)`. If a record is there, every non-empty stack is passed to `drops_spawn(id, count, dmg, x+0.5, y+0.5, z+0.5)` and the record is zeroed. Otherwise it is a no-op|
||`conts_step`|`()`, once per fixed step: furnace smelting|
||`conts_validate`|`()`, after load. It zeroes records whose kind is not 1 or 2, whose block does not match (FURNACE/FURNACE_LIT for kind 1, CHEST for kind 2), or whose coordinates are out of the world. In the surviving records it clears stacks with an invalid id (`item_max_stack == 0`), count 0, or count > max|
|`items.asm`|`inv_container` (dq)|The open CONTAINER*, or 0|
||`inv_add_dmg`, `inv_add`|unchanged|
||`inv_count`|`(edi id)→eax` total count of that id in slots 0–35|
||`inv_remove_one`|`(edi id)→eax` 1 if one was removed (first slot 0–35 holding it)|
||`armor_points`|`()→eax` sum of `item_armor_points` over non-empty armor slots|
||`armor_wear`|`()`: each non-empty armor slot gets `dmg += 1`. When `dmg ≥ item_durability` the slot is cleared and `audio_play(SND_TOOL_BREAK, 0.9)` plays|
||`inv_close_screen`|also sets `inv_container = 0`|
|`arrows.asm` (new)|`arrows`, `arrows_clear`, `arrows_step`, `arrows_render`|state and per-step logic|
||`arrows_spawn`|`(xmm0 x, xmm1 y, xmm2 z, xmm3 vx, xmm4 vy, xmm5 vz, edi owner, esi damage, edx pickup)→eax` index or −1. It fills the first entry with `live == 0`, zeroes `age` and `stuck`, and sets `live = 1`. A full table → −1 and nothing is spawned|
|`explode.asm` (new)|`explode_at`|`(xmm0 x, xmm1 y, xmm2 z, xmm3 radius)`|
||`primed`|`MAX_PRIMED × PRIMED` state|
||`tnt_prime`|`(edi x, esi y, edx z, ecx fuse)`: sets the block to AIR and fills the first free entry (`fuse == 0`) at the cell centre. A full table → the entry with the smallest fuse is replaced|
||`tnt_clear`, `tnt_step`, `tnt_render`|state and per-step logic|
|`mobs.asm`|`ray_aabb` (made global)|unchanged signature: `(rdi origin[3], rsi dir[3], rdx lo[3], rcx hi[3], xmm0 tmax)→eax`, xmm0 = t|
||`mob_count_kind`|`(edi hostile 0/1)→eax` live mobs whose `t_hostile` equals edi|
|`game.asm`|`game_open_screen` (dd)|0, ST_CRAFTING, ST_FURNACE or ST_CHEST. Replaces `game_open_table`|
||`game_open_cont` (dq)|CONTAINER* for furnace/chest|
||`game_bow_charge` (float)|seconds the bow has been drawn, 0 = not drawing|
|`invscreen.asm`|`screen_furnace`, `screen_chest`|`()`|

## Approach

The steps are ordered by dependency, and the tree builds after each one.
- Steps 2, 4, 5, 6 and 7 touch disjoint files and may be run by parallel workers. Each works in a scratch copy (`rm -rf /tmp/ac-<name> && mkdir -p /tmp/ac-<name> && git archive HEAD | tar -x -C /tmp/ac-<name>`), with throwaway stub files for symbols from sibling steps.
- Step 3 needs step 2.
- Steps 8 and 9 share `mobs.asm` and `test_combat.asm`, so one worker does 8 then 9.
- The integrator does step 1 first, then steps 10–12, and registers every test.

### 1. Contracts, block and item tables, save format v3 (integrator)

1. **`common.inc`:** write every constant and struct in **Contracts**.
2. **`blockdefs.asm`:** extend every table to 22 entries, and replace `block_needs_tool` with `block_harvest_level db`. Old blocks keep their values, except that STONE, COBBLE and BRICK now get level 1.

   |id|flags|tiles t/s/b|hardness|tool|level|drop|dig|step|
   |---|---|---|---|---|---|---|---|---|
   |COAL_ORE|3|26,26,26|3.0|1|1|COAL|DIG_STONE|STEP_STONE|
   |IRON_ORE|3|27,27,27|3.0|1|2|IRON_ORE|DIG_STONE|STEP_STONE|
   |GOLD_ORE|3|28,28,28|3.0|1|3|GOLD_ORE|DIG_STONE|STEP_STONE|
   |DIAMOND_ORE|3|29,29,29|3.0|1|3|DIAMOND|DIG_STONE|STEP_STONE|
   |FURNACE|3|0,30,0|3.5|1|1|FURNACE|DIG_STONE|STEP_STONE|
   |FURNACE_LIT|3|0,31,0|3.5|1|1|FURNACE|DIG_STONE|STEP_STONE|
   |CHEST|3|43,44,43|2.5|2|0|CHEST|DIG_WOOD|STEP_WOOD|
   |GRAVEL|3|45,45,45|0.6|3|0|GRAVEL|DIG_SOFT|STEP_SOFT|
   |TNT|3|47,46,47|0.0|0|0|TNT|DIG_SOFT|STEP_SOFT|

3. **`itemdefs.asm`:** extend every table to 82 entries and add five new tables.
   - **`item_names`:**
     - Blocks 13–21: "Coal Ore", "Iron Ore", "Gold Ore", "Diamond Ore", "Furnace", "Furnace", "Chest", "Gravel", "TNT". Ids 22–31 are "?".
     - Basics: "Coal", "Iron Ingot", "Gold Ingot", "Diamond".
     - Iron tools: "Iron Pickaxe", "Iron Axe", "Iron Shovel", "Iron Sword".
     - Gold tools: "Golden Pickaxe", "Golden Axe", "Golden Shovel", "Golden Sword".
     - Diamond tools: "Diamond Pickaxe", "Diamond Axe", "Diamond Shovel", "Diamond Sword".
     - Bow and materials: "Bow", "Arrow", "String", "Gunpowder", "Flint", "Flint and Steel".
     - Food and drops: "Rotten Flesh", "Cooked Porkchop", "Feather", "Raw Chicken", "Cooked Chicken".
     - Armor:
       - "Iron Helmet", "Iron Chestplate", "Iron Leggings", "Iron Boots";
       - "Golden Helmet", "Golden Chestplate", "Golden Leggings", "Golden Boots";
       - "Diamond Helmet", "Diamond Chestplate", "Diamond Leggings", "Diamond Boots".
   - **`item_icon`:**
     - Blocks 13–21: 26, 27, 28, 29, 30, 31, 44, 45, 46.
     - Ids 22–31: 0.
     - Ids 43–81: `80 + id − 43`.
   - **`item_max_stack`:**
     - Blocks 13–17 and 19–21 are 64; FURNACE_LIT is 0; ids 22–31 are 0.
     - 64: coal, ingots, diamond, arrow, string, gunpowder, flint, feather, all foods.
     - 1: tools, bow, flint and steel, armor.
   - **`item_tool` / `item_tier`:**
     - Pickaxe 1, axe 2, shovel 3, sword 4, in each group of four.
     - Tier: 47–50 iron (3), 51–54 gold (5), 55–58 diamond (4).
   - **`item_durability` (dw):**
     - Tools: iron 250, gold 32, diamond 1561.
     - Bow 384; flint and steel 64.
     - Armor (helmet, chest, legs, boots): iron 165, 240, 225, 195; gold 77, 112, 105, 91; diamond 363, 528, 495, 429.
   - **`item_attack`** (pickaxe, axe, shovel, sword): iron 5, 6, 4, 7; gold 3, 4, 2, 5; diamond 6, 7, 5, 8. Every other id is 1.
   - **`item_food` / `item_saturation`:** rotten flesh 4 / 0.8; cooked porkchop 8 / 12.8; raw chicken 2 / 1.2; cooked chicken 6 / 7.2.
   - **New `item_burn dw`** (fuel steps): PLANKS 300, LOG 300, CRAFTING_TABLE 300, CHEST 300, STICK 100, 33–36 (wood tools) 200, COAL 1600, BOW 300. Every other id is 0.
   - **New `item_smelt db`** (result id): IRON_ORE→IRON_INGOT, GOLD_ORE→GOLD_INGOT, SAND→GLASS, COBBLE→STONE, LOG→COAL, PORKCHOP→COOKED_PORKCHOP, RAW_CHICKEN→COOKED_CHICKEN. Every other id is 0.
   - **New `item_armor_slot db`:** 70/74/78 → 1, 71/75/79 → 2, 72/76/80 → 3, 73/77/81 → 4. Every other id is 0.
   - **New `item_armor_points db`** (helmet, chest, legs, boots): iron 2, 6, 5, 2; gold 2, 5, 3, 1; diamond 3, 8, 6, 3.
4. **`world.asm`:**
   - `world_magic` becomes `"ACRAFT03"`; add `world_magic_v2 "ACRAFT02"`.
   - `world_load`:
     - size == `WORLD_FILE_SIZE` with magic v3 → ok.
     - size == `WORLD_V2_SIZE` with magic v2 → `convert_v2`:
       1. Copy `WORLD_VOLUME` bytes from `world_header + 1024` to `blocks`, backwards (`std`/`rep movsb`/`cld`), because dest > src.
       2. Zero `world_header[944 .. 16383]`.
       3. Store the v3 magic.
     - The v1 path stays as is. It works unchanged because it moves the blocks to `blocks` and zeroes `WORLD_HDR_SIZE` bytes.
     - Anything else → 2. Update the comment: "Accepts v3, converts v2 and 0.1 files".
5. **`saves.asm`:**
   - `hdr_buf` becomes `resb WORLD_BASE_HDR`. Both the `file_read` cap and the following length check use `WORLD_BASE_HDR`.
   - Add `m_v3 "ACRAFT03"`. A v3 or v2 magic with mode 0/1 is a valid entry (same fields as now).
   - `saves_rename` keeps patching offset 20.
6. **`src/test_world.asm`:**
   - In `test_world_save_load`, replace the `%if WORLDHDR_size != 1024` block with runtime checks: `WORLDHDR_size == 16384`, `WORLDHDR.armor == 944`, `WORLDHDR.containers == 1024`, `CONTAINER_size == 128`, plus the existing player/health/inventory/mobs offsets.
   - Add **`test_world_load_v2_converts`**:
     1. `world_clear`; set (1,2,3) = BRICK and (3,0,0) = STONE.
     2. Zero `world_header[0..1023]`. Write magic "ACRAFT02", seed 55, mode 0, and inventory slot 0 = {DIRT,5}.
     3. Copy `blocks` forward to `world_header + 1024`.
     4. `file_write_atomic("/tmp/assemblycraft-selftest-v2.acw", world_header, WORLD_V2_SIZE)`.
     5. `world_clear`, then `world_load` → 0.
     6. Check: magic "ACRAFT03", seed 55, slot 0 {3,5}, (1,2,3) = BRICK, the `.kind` of containers record 0 == 0, and the armor dword at 944 == 0.
     7. Unlink the file.

   File (3,0,0) lands on record 0's `.kind` before conversion, so the last check proves the zeroing.
7. **Rename symbols:**
   - `block_needs_tool` → `block_harvest_level` in `items.asm`'s extern and in `harvest_info`. Until step 2 lands, keep the boolean meaning: "needs a tool" ⇔ `block_harvest_level ≠ 0`. After this, `grep -n block_needs_tool src` must be empty.
   - Remove `game_open_table` in step 10.

**Done when:** `make && make test` prints 41 ok lines.

### 2. Items logic: tiers, recipes, containers, armor in `items.asm` (+ `test_items.asm`)

1. **Tiers in `harvest_info` / `item_break_time`:**
   - Speed table by tier (`f_speed dd 1.0, 2.0, 4.0, 6.0, 8.0, 12.0`, index = tier).
   - `tier_level db 0, 1, 2, 3, 4, 1`.
   - `can = level == 0 || (match && tier_level[tier] ≥ level)`, with `level = block_harvest_level[block]`.
   - `time = hardness × (can ? 1.5 : 5.0) / speed`, where speed = `f_speed[tier]` when the tool matches, else 1.0.
   - A hardness of 0 gives time 0 (TNT breaks instantly).
2. **Replace `add_range` with `add_cells(rdi base, esi ncells, edx id, ecx count, r8d dmg) → eax leftover`.**
   - It does the same two passes over `base[0..n)`: merge into stacks of the same id with dmg 0 (only when dmg == 0), then fill empty cells, each capped at `item_max_stack`.
   - Callers:
     - `inv_add_dmg` → (inv, 36);
     - shift hotbar → main: (inv + 36, 27);
     - shift main → hotbar: (inv, 9);
     - grid → (inv, 36);
     - result shift: (inv, 36).
3. **`inv_click` ref decoding:**
   - ≤ 45: as now. 46: none.
   - 47–50: `rbx = inv + 4·ref`.
   - 51–77: none if `inv_container == 0`. Otherwise k = ref − 51; none if the kind is furnace and k > 2; else `rbx = inv_container + CONTAINER.slots + 4k`.
   - Call `craft_update` after a change only for refs 36–44.
4. **Non-shift rules:**
   - **Armor ref:** if the cursor is non-empty and `item_armor_slot[cursor.id] ≠ ref − 46` → none. Otherwise left or right swaps the cursor and the slot; an empty cursor takes the piece.
   - **Furnace k = 2 (output):** it is take-only.
     - Empty cursor → the cursor takes the whole stack.
     - Cursor with the same id, dmg 0 and `cursor + out ≤ max` → merge everything into the cursor.
     - Else none. Right click behaves the same.
   - **Furnace k = 1 (fuel):** if the cursor is non-empty and `item_burn[cursor.id] == 0` → none; else the normal rules.
   - Every other ref keeps the existing rules.
5. **Shift rules:**
   - **Ref 0–35 with `inv_container ≠ 0`:**
     - Chest → `add_cells(slots, 27)`.
     - Furnace: `item_smelt[id] ≠ 0` → `add_cells(&slot0, 1)`; else `item_burn[id] > 0` → `add_cells(&slot1, 1)`; else the normal hotbar ↔ main move.
   - **Ref 0–35 with no container:** if `item_armor_slot[id] = s > 0` and armor slot s−1 is empty → move the stack there. Else the normal move.
   - **Armor ref, or container ref 51+:** `add_cells(inv, 36)`; any leftover stays in place.
6. **New functions:**
   - `inv_count`, `inv_remove_one`, `armor_points`, `armor_wear`, with the contracts from **Contracts → Module API**.
   - `inv_close_screen` sets `inv_container = 0`.
   - The non-tool test in `inv_damage_held` becomes `item_durability[id] == 0 → return 0`, so bow and flint and steel wear.
7. **Recipes** (append to `recipes`; records are `w, h, out, count, cells[9]`). M = material, S = STICK.

   |Output|Shape|
   |---|---|
   |FURNACE ×1|3×3 ring of COBBLE (centre empty)|
   |CHEST ×1|3×3 ring of PLANKS|
   |`TOOLS IRON_INGOT …`, `TOOLS GOLD_INGOT …`, `TOOLS DIAMOND …`|existing macro|
   |BOW|3×3 `0 S STRING / S 0 STRING / 0 S STRING`, plus the mirror `STRING S 0 / STRING 0 S / STRING S 0`|
   |ARROW ×4|1×3 `FLINT / S / FEATHER`|
   |FLINT_AND_STEEL|2×2 `IRON_INGOT 0 / 0 FLINT`, 2×2 `0 IRON_INGOT / FLINT 0`, and 2×1 `IRON_INGOT FLINT`|
   |TNT|3×3 `GUNPOWDER SAND GUNPOWDER / SAND GUNPOWDER SAND / GUNPOWDER SAND GUNPOWDER`|
   |New `ARMOR M, H, C, L, B` per material|helmet 3×2 `M M M / M 0 M`; chestplate 3×3 `M 0 M / M M M / M M M`; leggings 3×3 `M M M / M 0 M / M 0 M`; boots 3×2 `M 0 M / M 0 M`. For IRON_INGOT, GOLD_INGOT, DIAMOND|

8. **Tests** (append to `test_items.asm`; register after `break_time_rules`):
   - **`[craft_advanced_recipes]`** (`craft_size = 3`, grid cell = row·3 + col):
     - COBBLE ring (cells 0,1,2,3,5,6,7,8) → FURNACE; PLANKS ring → CHEST.
     - STICK 1,3,7 + STRING 2,5,8 → BOW; STRING 0,3,6 + STICK 1,5,7 → BOW.
     - FLINT 1, STICK 4, FEATHER 7 → {ARROW,4}.
     - IRON_INGOT 0 + FLINT 4 → FLINT_AND_STEEL; IRON_INGOT 1 + FLINT 3 → FLINT_AND_STEEL; IRON_INGOT 0 + FLINT 1 → FLINT_AND_STEEL.
     - GUNPOWDER 0,2,4,6,8 + SAND 1,3,5,7 → TNT.
     - IRON_INGOT 0,1,2 + STICK 4,7 → IRON_PICKAXE; GOLD_INGOT 1,4 + STICK 7 → GOLD_SWORD.
     - DIAMOND 0,1,2,3,5 → DIAMOND_HELMET; IRON_INGOT 0,2,3,5 → IRON_BOOTS; DIAMOND 0,2,3,4,5,6,7,8 → DIAMOND_CHESTPLATE; GOLD_INGOT 0,1,2,3,5,6,8 → GOLD_LEGGINGS.
   - **`[break_tiers]`** (±0.001):
     - IRON_ORE/WOOD_PICKAXE: time 7.5, drop 0. IRON_ORE/STONE_PICKAXE: time 1.125, drop IRON_ORE.
     - DIAMOND_ORE/STONE_PICKAXE: drop 0. DIAMOND_ORE/IRON_PICKAXE: drop DIAMOND, time 0.75.
     - GOLD_ORE/IRON_PICKAXE → GOLD_ORE; GOLD_ORE/GOLD_PICKAXE → 0.
     - STONE/GOLD_PICKAXE: time 0.1875, drop COBBLE. STONE/DIAMOND_PICKAXE: time 0.28125.
     - COAL_ORE/WOOD_PICKAXE → COAL. CHEST/0: time 3.75, drop CHEST. GRAVEL/0: time 0.9, drop GRAVEL.
     - TNT/0: time 0.0, drop TNT. FURNACE_LIT/STONE_PICKAXE → FURNACE.

**Done when:** tests pass (43 ok so far). Step 3 adds the inventory-click test that needs containers.

### 3. Containers: `containers.asm` (+ new `test_containers.asm`)

1. **`conts_step` per furnace record** (kind 1), in this order:
   1. `can` = input non-empty, `r = item_smelt[input.id] ≠ 0`, and output is empty or (`output.id == r`, `output.count < item_max_stack[r]`).
   2. If `burn == 0`, `can`, fuel non-empty and `item_burn[fuel.id] > 0` → `burn = burn_max = item_burn[fuel.id]`, `fuel.count−−` (clear at 0).
   3. If `burn > 0`: `burn−−`; if `can`: `cook++`, and at `cook ≥ SMELT_STEPS`: `cook = 0`, `input.count−−` (clear at 0), output = {r, output.count + 1, 0}.
   4. If `!can`: `cook = 0`.
   5. Block at (x,y,z): `burn > 0` and block == FURNACE → `world_set(FURNACE_LIT)`; `burn == 0` and block == FURNACE_LIT → `world_set(FURNACE)`.
2. **Other functions:** `cont_at`, `cont_create`, `cont_block_removed` and `conts_validate` as in **Contracts → Module API**.
3. **Tests:**
   - **`[furnace_smelts]`:**
     1. `world_clear`, `world_set(5,10,5,FURNACE)`, `cont_create(5,10,5,1)` → p. Input {IRON_ORE,2}, fuel {COAL,1}.
     2. 1 × `conts_step` → burn 1599, cook 1, fuel empty, block (5,10,5) = FURNACE_LIT.
     3. 199 more → output {44,1}, input count 1. 200 more → output {44,2}, input empty. 1 more → cook 0, burn 1199.
     4. Set burn = 1, 1 step → block = FURNACE.
     5. Zero the record.
   - **`[chest_spills_on_break]`:**
     1. `drops_clear`. `world_set(5,11,5,CHEST)`, `cont_create(5,11,5,2)`. Slot 0 = {DIRT,10}, slot 26 = {IRON_SWORD,1,dmg 7}.
     2. `cont_block_removed(5,11,5)` → `cont_at(5,11,5) == 0`, `drops[0]` = {DIRT,10}, `drops[1]` = {IRON_SWORD,1,7}.
     3. `drops_clear`.
   - **`[inv_click_armor_containers]`** (in `test_items.asm`; it exercises step 2's `inv_click` against real containers):
     1. `inv_clear`, `inv_container = 0`. Slot 0 = {IRON_HELMET,1}, slot 1 = {DIRT,5}.
     2. Shift-click 0 → armor[0] = 70 and slot 0 is empty.
     3. Left-click 1 (the cursor takes the dirt), then left-click 48 → returns 0, armor[1] stays empty and the cursor keeps the dirt. Left-click 1 puts it back.
     4. `world_set(5,11,5,CHEST)` + `cont_create(5,11,5,CONT_CHEST)` → c, `inv_container = c`. Shift-click 1 → chest cell 0 = {DIRT,5}. Shift-click ref 51 → slot 0 = {DIRT,5}, and chest cell 0 is empty.
     5. Furnace `cont_create(6,11,5,CONT_FURNACE)` → f, `inv_container = f`. Slot 2 = {IRON_ORE,3}, slot 3 = {COAL,2}, slot 4 = {DIRT,1}.
     6. Shift-click 2 → f input {14,3}. Shift-click 3 → f fuel {43,2}.
     7. Set f output = {IRON_INGOT,4}. Left-click 53 → cursor {44,4}. Left-click 53 again → returns 0, output still empty.
     8. Left-click 2 puts the ingots in slot 2. Left-click 4 → cursor {DIRT,1}. Left-click 52 → returns 0.
     9. Clean up: `inv_clear`, `inv_container = 0`, zero the containers region.

**Done when:** tests pass (46 ok so far).

### 4. Armor damage in `survival.asm` (+ `test_survival.asm`)

- **In `survival_damage`,** before applying, for causes ZOMBIE (2), SKELETON (5), EXPLOSION (6) and SPIDER (7):
  - `p = armor_points()`. If p > 0 → `amount = max(1, (amount·(25−p) + 12) / 25)` (unsigned integer division), then `armor_wear()`.
  - Every other cause is unchanged.
- **Test `[armor_reduces_damage]`:**
  1. `game_mode = 0`, `difficulty = 2`, `survival_reset`, `inv_clear`. Armor slots = {78..81, 1, 0} → `armor_points() == 20`.
  2. `survival_damage(3, CAUSE_ZOMBIE)` → health 19, and every armor dmg == 1.
  3. `invuln = 0`; `damage(5, CAUSE_FALL)` → 14.
  4. Armor = iron 70..73 (points 15); `invuln = 0`; `damage(10, CAUSE_EXPLOSION)` → 10.
  5. `inv_clear`.

### 5. World generation: ores and gravel (`worldgen.asm`, `test_worldgen.asm`)

1. **Beach gravel**, in the column loop: when the column is sand (`h ≤ 22`) and `hash32(x>>2, z>>2, 78) & 7 == 0`, the top two cells (y = h and h−1) are GRAVEL instead of SAND.
2. **Ore pass,** after the terrain loop and before the trees. For every column (x, z in 0–255) and each ore `(salt, id, y_min, y_max, chance, size)`:

   |Ore|salt|y_min|y_max|chance|size|
   |---|---|---|---|---|---|
   |COAL_ORE|1|5|52|3932|8|
   |IRON_ORE|2|5|40|2294|6|
   |GOLD_ORE|3|5|28|524|5|
   |DIAMOND_ORE|4|2|14|262|4|

   1. `r = hash32(x, z, 500+salt)`; continue only if `(r & 0xFFFF) < chance`.
   2. Start at `(x, y_min + (r>>16) % (y_max−y_min+1), z)`.
   3. Random walk for i in 0..size−1:
      1. `h = hash32(x, z, salt·64 + i)`.
      2. If the cell is in bounds and is STONE → write the ore.
      3. Then step by `dx = h%3 − 1`, `dy = (h>>8)%3 − 1`, `dz = (h>>16)%3 − 1`.
3. **Underground gravel**, after the ores: per column, `r = hash32(x, z, 520)`, `(r & 0xFFFF) < 262` → centre y = `5 + (r>>16) % 30`. Every cell of the 3×2×3 box (dx, dz ∈ −1..1, dy ∈ 0..1) that is STONE becomes GRAVEL.
4. **Test `[worldgen_ores]`** (`world_generate(42)`):
   - Counts: COAL_ORE > 1000, IRON_ORE > 500, GOLD_ORE > 100, DIAMOND_ORE > 30, GRAVEL > 100.
   - Highest y: DIAMOND_ORE ≤ 17, GOLD_ORE ≤ 32, IRON_ORE ≤ 45.
   - The counts are sanity floors. If one fails while the generator matches this spec, measure it with gdb and set that floor to half the measured value.

### 6. Atlas art (`texgen.asm`)

1. **RNG-drawn tiles.** Append them after tile 70 in this exact order, each with one draw per pixel: 26, 27, 28, 29, 30, 31, 43, 44, 45, 46, 47, 71…79. "m" and `shade` are used as for the existing tiles.
   - **Ores 26–29:** m = 200+(r&55).
     - Colour by the shared mask below (row = py): `o` → ore colour, `O` → ore highlight, else stone (128,128,128).
     - Coal: o (30,30,30), O (60,60,60). Iron: (216,175,147) / (240,210,180). Gold: (252,238,75) / (255,255,180). Diamond: (93,236,245) / (200,255,255).
     ```
     ................
     ..oo........O...
     .oOo.......ooo..
     ..o.........o...
     ......oo........
     .....oOoo.......
     ......oo........
     .............o..
     ..o.........oOo.
     .ooo.........o..
     ..O.............
     .......oo.......
     ......oOoo....o.
     .......o.....oo.
     ................
     ................
     ```
   - **30 furnace front:** m = 200+(r&55).
     - Border (px or py ∈ {0,15}) → (80,80,80).
     - 3≤px≤12 and 3≤py≤4 → (60,60,60).
     - 4≤px≤11 and 8≤py≤12 → (24,24,24).
     - Else (120,120,120).
   - **31 furnace lit:** the same rules, except inside 4≤px≤11, 8≤py≤12: py ≥ 11 → (255,170,40), py == 10 → (250,110,20), py ≤ 9 → (190,50,10).
   - **43 chest top:** m = 216+(r&31); border → (92,64,32); else (162,130,78).
   - **44 chest side:** m = 216+(r&31); border or py ∈ {5,6} → (92,64,32); then 7≤px≤8 and 4≤py≤8 → (210,210,210); else (162,130,78).
   - **45 gravel:** m = 216+((r>>8)&39); colour by r&3: 0 (118,110,106), 1 (146,138,134), 2 (92,88,86), 3 (166,156,146).
   - **46 TNT side:** m = 216+(r&31).
     - py ≤ 3 or py ≥ 12 → (200,40,30), or (150,25,20) when px%4 == 3.
     - Rows 4–11 → (230,230,230), except `#` cells of this mask at py 6–10, which are (30,30,30):
     ```
     ..###.#..#.###..
     ...#..##.#..#...
     ...#..#.##..#...
     ...#..#..#..#...
     ...#..#..#..#...
     ```
   - **47 TNT top:** m = 216+(r&31); (200,40,30); 6≤px≤9 and 6≤py≤9 → (230,230,230); 7≤px≤8 and 7≤py≤8 → (40,40,40).
   - **71 creeper skin:** m = 200+(r&55); (80,180,70); (r>>8)&7 == 0 → (50,120,45); (r>>11)&7 == 1 → (140,220,120).
   - **72 creeper face:** the skin rule, then black (20,20,20) at:
     - eyes 3≤px≤5 or 10≤px≤12 with 4≤py≤6;
     - mouth 6≤px≤9 with 7≤py≤10;
     - mouth sides px ∈ {5,6,9,10} with 10≤py≤12.
   - **73 skeleton bone:** m = 200+(r&55); (200,200,200).
   - **74 skeleton face:** bone, with:
     - sockets (40,40,40) at 3≤px≤6 or 9≤px≤12 with 5≤py≤7;
     - (60,60,60) at px ∈ {7,8} with py == 9;
     - (60,60,60) at even px with 3≤px≤12 and py == 12.
   - **75 spider body:** m = 200+(r&55); (52,44,40); (r>>8)&7 == 0 → (80,66,58).
   - **76 spider face:** the body rule; red (200,30,30) at (4,6), (5,6), (10,6), (11,6), (6,4), (9,4), (3,8), (12,8); (30,24,22) at (6,12), (9,12), (6,13), (9,13).
   - **77 chicken body:** m = 220+(r&35); (240,240,240).
   - **78 chicken face:** body rule; (24,24,24) at (3,5), (12,5); (240,180,40) at 6≤px≤9, 7≤py≤9; (200,30,30) at 7≤px≤8, 10≤py≤12.
   - **79 chicken leg:** m = 220+(r&35); (240,180,40).
2. **No-RNG icons,** drawn after the mob tiles and before the font.
   - Add `bmp_px` (a copy of `hud_px` for 16×16 bitmaps: r9 = 256-char bitmap, r10 = palette in the `PAL` format; a char not in the palette → transparent) and the macro `BMP tile, bitmap, palette`.
   - Parametrize `icon_pork`: r9d fat, r10d meat, r11d rim. Use macro `ICON3`. Tile 42 keeps its colours (fat (250,215,205), meat (232,138,138), rim (180,80,80)).
   - **Assignments:**
     - 80 coal; 81 ingot/iron pal; 82 ingot/gold pal; 83 diamond.
     - 84–87 iron tools: ICONT pick, axe, shovel, sword with m (220,220,220), M (130,130,130).
     - 88–91 gold tools: m (250,220,60), M (180,130,10).
     - 92–95 diamond tools: m (90,230,230), M (25,140,140).
     - 96 bow; 97 arrow; 98 string; 99 gunpowder; 100 flint; 101 flint and steel; 102 rotten flesh.
     - 103 cooked porkchop = `ICON3 icon_pork` with fat (225,190,150), meat (165,95,50), rim (110,60,30).
     - 104 feather; 105 drumstick/raw; 106 drumstick/cooked.
     - 107–110 iron helmet, chestplate, leggings, boots; 111–114 gold; 115–118 diamond.
   - **Palettes:**
     - Ingot iron: L (245,245,245), m (206,206,206), D (120,120,120). Ingot gold: L (255,250,160), m (250,215,60), D (175,125,10).
     - Armor iron: D (90,90,90), m (200,200,205), L (245,245,245). Armor gold: D (160,110,10), m (245,205,50), L (255,245,150). Armor diamond: D (20,100,100), m (90,225,225), L (215,255,255).
     - Drumstick raw: m (236,170,160), w (255,215,205), b (240,236,224). Cooked: m (176,98,40), w (212,140,72), b (240,236,224).
   - **Bitmaps.** `.` is transparent. Each is shown with its palette:
     - **coal** — K (24,24,24), k (48,48,52), g (96,96,100):
       ```
       ................
       ................
       ......KKKK......
       ....KKkkkkKK....
       ...KkkggkkkkK...
       ...KkgkkkkkkK...
       ..KkkkkkkgkkkK..
       ..KkkkkkkkkkkK..
       ..KkkgkkkkkkkK..
       ..KkkkkkkkgkkK..
       ...KkkkkkkkkK...
       ...KKkkgkkkKK...
       .....KKkkKKK....
       .......KKK......
       ................
       ................
       ```
     - **ingot:**
       ```
       ................
       ................
       ................
       ................
       ................
       ......LLLLLLL...
       .....LmmmmmmLD..
       ....LmmmmmmmLDD.
       ...LLLLLLLLLDDD.
       ...LmmmmmmmmLDD.
       ...LmmmmmmmmLD..
       ...DDDDDDDDDDD..
       ................
       ................
       ................
       ................
       ```
     - **diamond** — K (18,90,90), m (90,230,230), L (220,255,255):
       ```
       ................
       ................
       .....KKKKKK.....
       ....KLLmmmmK....
       ...KLLmmmmmmK...
       ..KmmmmmmmmmmK..
       ..KKKKKKKKKKKK..
       ...KmmmmmmmmK...
       ....KmmmmmmK....
       .....KmmmmK.....
       ......KmmK......
       .......KK.......
       ................
       ................
       ................
       ................
       ```
     - **bow** — w (150,112,50), W (84,62,22), s (230,230,230):
       ```
       ................
       ............wW..
       ............wW..
       ...........swW..
       ..........swwW..
       .........s.wWW..
       ........s..wW...
       .......s..wwW...
       ......s..wwWW...
       .....s..wwWW....
       ....s..wwWW.....
       ...swwwwWW......
       .wwwwWWWW.......
       .WWWWW..........
       ................
       ................
       ```
     - **arrow** — h (137,103,39), G (220,220,220), g (120,120,120), f (245,245,245):
       ```
       ................
       ............GGG.
       ...........gGGG.
       ..........hgGG..
       .........h..g...
       ........h.......
       .......h........
       ......h.........
       .....h..........
       ....h...........
       ...h............
       .ffh............
       .fff............
       ..ff............
       ................
       ................
       ```
     - **string** — s (235,235,235):
       ```
       ................
       ................
       ............ss..
       ...........s..s.
       ..........s.....
       .........s......
       ........s.......
       .......s........
       ......s.........
       .....s..........
       ....s...........
       ...s............
       ..s.............
       ..s.............
       ...ss...........
       ................
       ```
     - **gunpowder** — k (60,60,60), g (110,110,110), l (160,160,160):
       ```
       ................
       ................
       ................
       ................
       ................
       ................
       ........g.......
       ......gkkgl.....
       .....kkgkklk....
       ....kglkkgkkk...
       ...kkkkglkkgkk..
       ..kglkkkkkklkkk.
       ..kkkkglkkkkgkk.
       ...kkkkkkgkkkk..
       ................
       ................
       ```
     - **flint** — K (20,20,22), d (60,60,66), l (120,120,130):
       ```
       ................
       ................
       ................
       .......KK.......
       ......KllK......
       .....KlddK......
       ....KlddddK.....
       ....KdddddK.....
       ...KlddddddK....
       ...KddddddddK...
       ...KddddddddK...
       ....KdddddddK...
       .....KddddKK....
       ......KKKK......
       ................
       ................
       ```
     - **flint and steel** — D (110,110,110), L (210,210,210), plus the flint colours K, d, l:
       ```
       ................
       ................
       ...DDDDD........
       ..DLLLLLD.......
       ..DL...LD.......
       ..DL...LD.......
       ..DLLLLLD.......
       ...DDDLD........
       ......LD........
       ......LD..KK....
       .......D.KllK...
       ........KlddK...
       .......KddddK...
       .......KdddK....
       ........KKK.....
       ................
       ```
     - **rotten flesh** — d (90,50,30), m (150,90,55), g (100,130,60):
       ```
       ................
       ................
       ................
       ......dd........
       ....ddmmd.......
       ...dmmgmmd......
       ...dmmmmmmdd....
       ..dmgmmmmmmmd...
       ..dmmmmmgmmmmd..
       ...dmmmmmmmgmd..
       ....ddmmgmmmmd..
       ......ddmmmmd...
       ........dddd....
       ................
       ................
       ................
       ```
     - **feather** — W (180,180,180), w (245,245,245), q (150,150,150):
       ```
       ................
       ............WW..
       ..........WWww..
       .........Wwwww..
       ........Wwwww...
       .......Wwwwq....
       ......Wwwwq.....
       .....Wwwwq......
       ....Wwwwq.......
       ....wwwq........
       ....wwq.........
       ....wq..........
       ...q............
       ..q.............
       ................
       ................
       ```
     - **drumstick:**
       ```
       ................
       ................
       ................
       ........mmmm....
       .......mwmmmm...
       ......mwmmmmmm..
       ......mmmmmmmm..
       ......mmmmmmmm..
       .......mmmmmmm..
       ......bmmmmmm...
       .....bbbmmmm....
       ....bb..........
       ...bb...........
       ..bbb...........
       ..bb............
       ................
       ```
     - **helmet:**
       ```
       ................
       ................
       ................
       ....DDDDDDDD....
       ...DLLLmmmmmD...
       ..DLmmmmmmmmmD..
       ..DmmmmmmmmmmD..
       ..DmmDDDDDDmmD..
       ..DmmD....DmmD..
       ..DmmD....DmmD..
       ..DDDD....DDDD..
       ................
       ................
       ................
       ................
       ................
       ```
     - **chestplate:**
       ```
       ................
       ..DDDD....DDDD..
       ..DLmD....DmmD..
       ..DmmDDDDDDmmD..
       ..DmmmmmmmmmmD..
       ...DLmmmmmmmD...
       ....DmmmmmmD....
       ....DmmmmmmD....
       ....DmmmmmmD....
       ....DmmmmmmD....
       ....DmmmmmmD....
       ....DmmmmmmD....
       ....DDDDDDDD....
       ................
       ................
       ................
       ```
     - **leggings:**
       ```
       ................
       ................
       ....DDDDDDDD....
       ....DLmmmmmD....
       ....DmmmmmmD....
       ....DmmDDmmD....
       ....DmmDDmmD....
       ....DmmDDmmD....
       ....DmmDDmmD....
       ....DmmDDmmD....
       ....DmmDDmmD....
       ....DDDDDDDD....
       ................
       ................
       ................
       ................
       ```
     - **boots:**
       ```
       ................
       ................
       ................
       ................
       ................
       ................
       ...DDDD..DDDD...
       ...DLmD..DLmD...
       ...DmmD..DmmD...
       ...DmmD..DmmD...
       ..DDmmD..DmmDD..
       .DLmmmD..DmmmmD.
       .DDDDDD..DDDDDD.
       ................
       ................
       ................
       ```
   - **HUD 54–56** with `HUD` and the 9×9 bitmap below. Full palette: K (30,30,30), m (190,190,200), L (255,255,255). Empty: K, then m/L → (60,60,60). Split columns 9 / 5 / 0.
     ```
     .KK...KK.
     KmLK.KmmK
     KmmmKmmmK
     .KmmmmmK.
     .KmmmmmK.
     .KmmmmmK.
     .KKKKKKK.
     .........
     .........
     ```
3. **Proof:** dump the atlas as W2 did (a throwaway C harness calling `texgen_build`; `magick -size 256x256 -depth 8 rgba:… -scale 300%`). Read it and confirm:
   - tiles 0–25, 32–42, 48–53 and 64–70 are byte-identical to HEAD;
   - the font rows are untouched.

### 7. Sounds (`sfx.asm`)

- Set `POOL_SAMPLES 524288`. Append these layers with the existing `LAYER` macro.
- Column order is wave, f0, f1, lp, hp, env, half, attack, start, dur, amp, vdepth, vrate. Fields not listed are 0.

|Sound|Layers|
|---|---|
|EXPLODE|NOISE lp .12 E_EXP .25 dur 1.2 amp 1.0 · NOISE lp .6 hp 1 E_EXP .05 dur .3 amp .6|
|FUSE|NOISE lp .7 hp 1 E_LIN attack .3 dur 1.5 amp .45|
|BOW|NOISE lp .5 hp 1 E_EXP .03 dur .12 amp .45 · SQUARE 220→110 lp .2 E_LIN dur .15 amp .3|
|ARROW_HIT|NOISE lp .35 E_EXP .02 dur .08 amp .7 · SQUARE 900→600 lp .5 E_EXP .02 dur .06 amp .12|
|SKELETON_SAY|three × SQUARE 1100→900 lp .5 E_LIN dur .05 amp .35, starts 0 / .08 / .16|
|SKELETON_HURT|SQUARE 800→400 lp .5 E_LIN dur .2 amp .4 · NOISE lp .5 E_EXP .03 dur .1 amp .35|
|SPIDER_SAY|NOISE lp .15 E_LIN attack .05 dur .45 amp .6 · SAW 70→60 lp .1 E_LIN dur .45 amp .35 vdepth 8 vrate 9|
|SPIDER_HURT|SAW 220→120 lp .3 E_LIN dur .25 amp .5|
|CREEPER_HURT|NOISE lp .5 hp 1 E_EXP .06 dur .25 amp .5 · SAW 160→110 lp .2 E_LIN dur .2 amp .35|
|CHICKEN_SAY|SQUARE 1500→1700 lp .5 E_LIN dur .06 amp .3 · SQUARE 1700→1300 lp .5 E_LIN start .1 dur .08 amp .3|
|CHICKEN_HURT|SQUARE 1900→1000 lp .5 E_LIN dur .15 amp .35|

- **Level check:** a throwaway WAV harness, then `ffmpeg -i X -af volumedetect -f null -` per new sound.
  - Every peak must be between −18 and −0.1 dB.
  - A sound outside that range gets all of its layer amps multiplied by `10^((−6 − peak)/20)`; then remeasure.

### 8. Projectiles and explosions (`arrows.asm`, `explode.asm`; `mobs.asm` exports `ray_aabb`)

1. **`arrows_step`**, for each live arrow:
   - **Stuck arrows:**
     - `stuck++`.
     - owner 1 and stuck > 60 → remove. owner 0 and stuck > 1200 → remove.
     - **Pickup:** owner 0, pickup 1, survival, player alive, horizontal dist² to the player < 1.0 and `0 ≤ arrow.y − player.y ≤ 2.0` → `inv_add(ARROW,1) == 0` → `audio_play(SND_POP, 0.35)`, remove.
     - Skip the rest.
   - **Flying arrows:**
     1. `age++`; age > 600 → remove.
     2. `vy −= 0.33333334` (20 b/s² per step). seg = v/60, len = |seg|, dir = seg/len.
     3. **Block:** `raycast(pos, dir, &hit, len)`. On a hit, t_block = `ray_aabb(pos, dir, cell, cell+1, len)`'s t (len if it misses).
     4. **Entity:**
        - owner 0 → `mobs_raycast(pos, dir, best)`.
        - owner 1 → `ray_aabb` against the player box (x±0.3, y..y+1.8, z±0.3), only in survival with the player alive.
     5. **The nearest hit wins:**
        - **Mob:** `mob_hurt(idx, damage, unit(vx,vz))`, remove, `audio_play_at(SND_ARROW_HIT, pos, 0.8)`.
        - **Player:** `survival_damage(damage, CAUSE_SKELETON)`. If it applied, set the player's kbx/kbz to `unit(vx,vz)·4`. Remove, sound.
        - **Block:** `pos += dir·(t − 0.05)`, `stuck = 1` (velocity kept for orientation), sound at 0.5.
        - **None:** `pos += seg`; y < −8 → remove.
2. **`arrows_render`:**
   - Per arrow: `glPushMatrix`, translate to pos, then `glRotatef(−yaw, 0,1,0)` with `yaw = atan2_deg(vx, −vz)`, then `glRotatef(pitch, 1,0,0)` with `pitch = atan2_deg(vy, √(vx²+vz²))`.
   - Draw `render_box` three times with shades (0.6,0.6,1.0,0.5,0.8,0.8) and colour 1:
     - shaft (−0.03,−0.03,−0.25)–(0.03,0.03,0.25), tiles all 5;
     - tip (−0.04,−0.04,−0.30)–(0.04,0.04,−0.22), tiles all 0;
     - fletching (−0.06,−0.01,0.15)–(0.06,0.01,0.27), tiles all 77.
   - `glPopMatrix`.
3. **`explode_at(c, r)`:**
   1. `audio_play_at(SND_EXPLODE, c, 1.0)`.
   2. **Blocks:** every cell (bx,by,bz) with |d| ≤ ceil(r) whose centre is within r of c:
      - AIR → skip; BEDROCK → skip.
      - TNT → `tnt_prime(cell, 10 + rng%20)`.
      - Else `cont_block_removed(cell)`, `world_set(cell, AIR)`, and when `rng%10 < 3` with `block_drop[id] ≠ 0` → `drops_spawn(block_drop[id], 1, 0, centre)`.
   3. **Player:**
      - d = distance from c to (px, py+0.9, pz). If d < 2r: `f = 1 − d/(2r)`, `dmg = ceil(f · base[difficulty] · r/3)` with `base = {8, 12, 22, 33}`.
      - If `survival_damage(dmg, CAUSE_EXPLOSION)` applied: `kbx/kbz = unit(player−c).xz · 12f`, and when on the ground, `vy = 6f`.
   4. **Mobs:** each live mob with its centre (y + height/2) at d < 2r → `mob_hurt(i, ceil(f·24·r/3), unit(mob−c).xz)`.
4. **`tnt_step`:**
   - `fuse−−`. At 0, mark the entry free first, then `explode_at(centre, 4.0)`. Entries primed during that call have fuse ≥ 10.
   - Primed TNT does not fall.
5. **`tnt_render`:** per entry, translate to the centre; `item_model_draw(TNT, 1.0)`. When `(fuse>>3)&1`, call `glDisable(GL_TEXTURE_2D)` around the draw (white flash).
6. **Tests** (new `test_combat.asm`):
   - **`[arrow_hits_mob]`:**
     1. `rng_seed(1234)`, `mobs_clear`, `arrows_clear`, floor fixture (STONE y=10, x/z 0–31), `game_mode` 0, `game_time` 6000.
     2. Pig at (16.5,11,10.5). `arrows_spawn((16.5,11.5,16.5), (0,0,−30), 0, 5, 1)`.
     3. 30 × `arrows_step` → pig health 5, `hurt > 0`, `arrows[0].live == 0`.
   - **`[explosion_breaks_blocks]`:**
     1. `world_clear`, `drops_clear`, `tnt_clear`, `mobs_clear`. STONE fills x,y,z 2–14; (8,8,8) = BEDROCK, (8,8,11) = TNT.
     2. Player `body_init` at (11.5, 7.6, 8.5), `game_mode` 0, `difficulty` 2, `survival_reset`, `inv_clear`.
     3. `explode_at(8.5,8.5,8.5, 3.0)`.
     4. Check:
        - (8,8,8) is BEDROCK, (8,8,5) AIR, (8,8,4) STONE, (10,10,8) AIR, (10,10,10) STONE;
        - (8,8,11) is AIR and `primed[0].fuse` is in 10..29;
        - health 9.
     5. `tnt_clear`, `drops_clear`.

### 9. Mobs: creeper, skeleton, spider, chicken (`mobs.asm`, `mobrender.asm`, `test_mobs.asm`)

1. **Per-type tables** (index type−1; order zombie, pig, creeper, skeleton, spider, chicken):

   |table|values|
   |---|---|
   |`t_half_w`|0.3, 0.45, 0.3, 0.3, 0.7, 0.2|
   |`t_height`|1.8, 0.9, 1.7, 1.8, 0.9, 0.7|
   |`t_speed`|2.6, 1.6, 2.4, 2.5, 3.0, 1.4|
   |`t_health`|20, 10, 20, 20, 16, 4|
   |`t_hostile`|1, 0, 1, 1, 1, 0|
   |`t_burns`|1, 0, 0, 1, 0, 0|
   |`t_run`|0, 3.2, 0, 0, 0, 2.4 (panic speed)|
   |`t_say`|ZOMBIE_SAY, PIG_SAY, 0xFF (silent), SKELETON_SAY, SPIDER_SAY, CHICKEN_SAY|
   |`t_hurt`|ZOMBIE_HURT, PIG_HURT, CREEPER_HURT, SKELETON_HURT, SPIDER_HURT, CHICKEN_HURT|
   |drops (item, base, range)|zombie (ROTTEN_FLESH, 0, 3); pig (PORKCHOP, 1, 3); creeper (GUNPOWDER, 0, 3); skeleton (ARROW, 0, 3); spider (STRING, 0, 3); chicken (FEATHER, 0, 3) + (RAW_CHICKEN, 1, 1)|

   Damage by difficulty: zombie and skeleton {0,2,3,4}; spider {0,2,2,3}.

   - **Type checks:** `mob_spawn` and `mobs_load` accept types 1..`NUM_MOB_TYPES`.
   - **Death drops:** `count = base + rng%range` (one `rng_next` per entry). Count > 0 → `drops_spawn(item, count, 0, x, y + height/2, z)`. The pig keeps today's exact behaviour.
   - **Panic:** `mob_hurt` applies it to every non-hostile type (speed `t_run`, then back to `t_speed`).
2. **Hunting** (creeper, skeleton, spider) needs survival, difficulty > 0, a living player and horizontal dist² < 256. The zombie keeps 576 and its existing code. Not hunting → wander. Every hunter faces the player (`yaw_from`).
   - **Creeper** (`d3` = distance between centres, creeper y + 0.85, player y + 0.9):
     - When `fuse == 0`: `fwd = 1`. If `d3 < 3.0` → `fuse = 1` and `audio_play_at(SND_FUSE, creeper, 1.0)`.
     - When `fuse > 0`: `fwd = d3 > 2.0`. `fuse++` if `d3 < 7.0`, else `fuse−−`.
     - At `fuse ≥ 90`: set type NONE, then `explode_at(x, y+0.85, z, 3.0)`, then return.
     - Not hunting → `fuse = max(0, fuse−1)`.
   - **Skeleton** (horizontal distance d):
     - `fwd = d > 10 ? 1 : (d < 5 ? −1 : 0)`.
     - Shoot when `cooldown == 0`, `d < 15` and there is line of sight. LoS = `raycast((x, y+1.62, z), unit(eye − origin), &scratch, |eye − origin|)` returns 0, with eye = `player_eye`.
     - **Shot:**
       - Origin `o + dir·0.6`, `t = dist/24`, `v = dir·24 + (sx, 10t, sz)`.
       - Spread: `sx, sz = ((rng%201) − 100)/100 · {0, 1.5, 1.0, 0.5}[difficulty]`.
       - `arrows_spawn(…, owner 1, damage {0,2,3,4}[difficulty], pickup 0)`.
       - `audio_play_at(SND_BOW, skeleton, 0.8)`, `cooldown = 40 + rng%30`.
   - **Spider:**
     - `fwd = 1`. If `BODY.blocked` → set `BODY.vy = 3.0` before `body_step` (climb).
     - **Bite:** `cooldown == 0`, horizontal dist² < 1.96 and |dy| < 1.5 → `survival_damage({0,2,2,3}[diff], CAUSE_SPIDER)`. If it applied: player knockback as the zombie's but ×5.0, the same lift; `cooldown = 20`.
     - **Else leap:** `cooldown == 0`, on ground, `4 ≤ dist² ≤ 16` → `vy = 5.5`, own `kbx/kbz = unit·5.0`, `cooldown = 30`.
   - **Chicken:** after `body_step`, `vy < −3.0` → `vy = −3.0` (glide).
3. **`mob_update`:**
   - The sunburn branch tests `t_burns` instead of MOB_ZOMBIE.
   - The despawn and peaceful removal test `t_hostile` instead of MOB_ZOMBIE.
   - Ambient sound is skipped when `t_say == 0xFF`.
4. **Spawner:**
   - **Hostiles:** every 60 steps at night in survival with difficulty > 0, while `mob_count_kind(1) < 12`. Type = `{ZOMBIE, SKELETON, CREEPER, SPIDER}[rng%4]`, via `spawn_near_player(type, 24, 17, HOSTILE_GROUND)`. `HOSTILE_GROUND` = STONE, GRASS, DIRT, COBBLE, SAND, GRAVEL. Rename ZOMBIE_CAP/ZOMBIE_GROUND.
   - **Passives:** every 1800 steps by day: pig if < 10, then chicken if < 8 (ground GRASS, distance 24 + rng%25).
   - **`mobs_populate`:** after the pigs, 200 tries until 6 chickens.
5. **`mobrender.asm`:**
   - Add the part tables (`PART x0,y0,z0, x1,y1,z1, tile, front tile, pivot y, pivot z, swing`); `models` gets 6 entries; the type check uses `NUM_MOB_TYPES−1`.
   - **Creeper:**
     - body ±0.25, 0.375–1.125, ±0.125, 71/71;
     - head ±0.25, 1.125–1.625, ±0.25, 71/72;
     - legs at y 0–0.375, pivot y 0.375, with x [−0.25,0] or [0,0.25]:
       - front z [−0.375,−0.125], pivot z −0.25, swing FL +1, FR −1;
       - back z [0.125,0.375], pivot z 0.25, swing BL −1, BR +1.
   - **Skeleton:**
     - legs x [−0.1875,−0.0625] (+1) and [0.0625,0.1875] (−1), y 0–0.75, z ±0.0625, tile 73, pivot y 0.75;
     - body ±0.25, 0.75–1.5, ±0.125, 73;
     - arms x [−0.375,−0.25] (−1) and [0.25,0.375] (+1), y 0.75–1.5, z ±0.0625, 73, pivot y 1.4375;
     - head ±0.25, 1.5–2.0, ±0.25, 73/74.
   - **Spider:**
     - abdomen ±0.375, 0.25–0.8125, z 0–0.75, 75;
     - thorax ±0.1875, 0.3125–0.6875, z −0.25–0, 75;
     - head ±0.25, 0.25–0.75, z −0.75–−0.25, 75/76;
     - 8 legs y 0.4375–0.5625, z zc±0.0625 for zc ∈ {−0.375, −0.125, 0.125, 0.375}, pivot y 0.5, pivot z zc:
       - left legs x [−1.0,−0.1875], swing +0.5, −0.5, +0.5, −0.5;
       - right legs x [0.1875,1.0], swing −0.5, +0.5, −0.5, +0.5.
   - **Chicken:**
     - body ±0.1875, 0.3125–0.75, z ±0.25, 77;
     - head ±0.125, 0.5625–0.9375, z −0.4375–−0.1875, 77/78;
     - wings x [−0.25,−0.1875] and [0.1875,0.25], y 0.375–0.6875, z ±0.1875, 77, rigid;
     - legs x [−0.125,−0.0625] (+1) and [0.0625,0.125] (−1), y 0–0.3125, z ±0.03125, 79, pivot y 0.3125.
   - **Creeper fuse visuals:** with `fuse > 0`, after the yaw rotation `glScalef(s,s,s)` with `s = 1 + 0.2·min(fuse,90)/90`. When `(fuse>>2)&1`, disable `GL_TEXTURE_2D` for its parts (white flash).
6. **Tests:**
   - **`test_mobs.asm` `[mob_spawn_rules]`:** replace both zombie counts with `mob_count_kind(1)`: `1 ≤ n ≤ 12` after the night run; 0 after the peaceful run. Call `arrows_clear`, `tnt_clear` and `drops_clear` at the end.
   - **`test_combat.asm`:**
     - **`[creeper_explodes]`:**
       1. The fixture, `game_time` 40000, `difficulty` 2, `survival_reset`. Player `body_init` at (16.5,11,16.5); creeper at (18.5,11,16.5).
       2. 95 × (`mobs_step`; `arrows_step`; `tnt_step`).
       3. Check: `mob_count_type(MOB_CREEPER) == 0`, health < 20, block (18,10,16) is AIR.
     - **`[skeleton_shoots_player]`:**
       1. The fixture, `game_time` 40000; skeleton at (16.5,11,8.5); player at (16.5,11,16.5).
       2. 240 × (`mobs_step`; `arrows_step`).
       3. Check: health ≤ 17.
     - **`[mob_drops_by_type]`:**
       1. For each of zombie, creeper, skeleton and spider, 10 rounds of: spawn at (8.5,11,8.5), `mob_hurt(idx, 100, 0, 1)`.
       2. Then `drops` must contain at least one entry with ROTTEN_FLESH, GUNPOWDER, ARROW and STRING respectively.
       3. One chicken killed → an entry with RAW_CHICKEN.
       4. `drops_clear` between types.

### 10. Game integration (`game.asm`)

1. **State and renames:**
   - Rename `game_open_table` → `game_open_screen` everywhere (game.asm global/bss/`reset_session`/RMB code; app.asm extern and `update_state`). Add `game_open_cont` and `game_bow_charge`.
   - `reset_session` zeroes all three.
2. **Clearing and loading:**
   - `game_new` and `game_load`: call `arrows_clear` and `tnt_clear` next to `drops_clear`, and set `inv_container = 0`.
   - `game_load`: copy `header.armor` → `inv.armor`, keeping slot i only if `item_armor_slot[id] == i+1` and count == 1; then `conts_validate`.
   - `game_save`: copy `inv.armor` → `header.armor`.
3. **`sim_step` order after `drops_step`:** `arrows_step`, `tnt_step`, `conts_step`, then `game_time++`.
4. **Breaking:**
   - In both the survival and creative break paths, call `cont_block_removed(b)` before `world_set(b, AIR)`.
   - In the survival drop special-case next to LEAVES/APPLE: GRAVEL → FLINT when `rng%10 == 0`.
5. **RMB on press** (`rmb_pressed`, not sneaking), checked before placement:
   - **Open a block:**
     - CRAFTING_TABLE → `game_open_screen = ST_CRAFTING`.
     - FURNACE or FURNACE_LIT → c = `cont_at(b)` or `cont_create(b, CONT_FURNACE)`. Non-null → `game_open_screen = ST_FURNACE`, `game_open_cont = c`.
     - CHEST → the same with `CONT_CHEST` / `ST_CHEST`.
   - **Ignite TNT:** held FLINT_AND_STEEL and target TNT → `tnt_prime(b, 80)`, `audio_play_at(SND_FUSE, centre, 1.0)`, `hand_swing`, and in survival `inv_damage_held(1)`.
   - **Place FURNACE or CHEST:** after the placement checks pass, call `cont_create(p, kind)` first. If it returns 0, do not place.
6. **Pick block (MMB):** FURNACE_LIT counts as FURNACE.
7. **Bow,** a new block after pick block. Redirect every jump to `.ret` in the pick section to `.bow`.
   - held ≠ BOW → `game_bow_charge = 0`.
   - Else if `rmb_pressed`, `game_open_screen == 0`, `game_bow_charge == 0` and (creative or `inv_count(ARROW) > 0`) → `game_bow_charge = 0.001`.
   - Else if `game_bow_charge > 0`:
     - `rmb_held` → `+= dt`.
     - Released, with `input_captured == 1`:
       1. `f = min(charge, 1)`, `power = (f² + 2f)/3`. If `power ≥ 0.1`:
          1. `arrows_spawn(eye + fwd·0.3, fwd·45·power, owner 0, damage = 1 + cvtss2si(8·power), pickup = survival)`.
          2. In survival: `inv_remove_one(ARROW)` and `inv_damage_held(1)`.
          3. `audio_play(SND_BOW, 0.8)`.
       2. Charge = 0.
     - Released without capture → charge = 0.

### 11. App, screens, HUD, rendering glue

1. **`app.asm`:**
   - **`update_state`:**
     - The `.screen` branch also covers ST_FURNACE and ST_CHEST.
     - After `game_frame` in PLAYING: when `game_open_screen ≠ 0`:
       - ST_CRAFTING → `craft_size = 3`;
       - ST_FURNACE or ST_CHEST → `inv_container = game_open_cont`;
       - then `app_goto(game_open_screen)` and clear the flag.
   - **Drawing:**
     - The `screens` table gets `screen_furnace` and `screen_chest` after ST_QUIT's 0, and the bound check becomes `cmp eax, ST_CHEST`.
     - The hand/HUD state list in `draw_frame` adds ST_FURNACE and ST_CHEST.
   - **`load_panorama`:** add `arrows_clear` and `tnt_clear`.
2. **`invscreen.asm`:**
   - **`do_close` / `check_close`** take the screen kind: 0 inventory, 1 crafting, 2 container. Container screens call `inv_close_screen`.
   - **Furnace and chest screens:** if `[inv_container + CONTAINER.kind] == 0` (destroyed while open), close.
   - **`screen_furnace`** (panel origin px, py):
     - "Furnace" label at (px+8, py+6).
     - Input cell at (px+56, py+17), ref 51.
     - Flame: background `ui_rect(px+57, py+37, 14, 14, RGBA(0,0,0,90))`, fill height `h = 14·burn/burn_max` at (px+57, py+51−h, 14, h) in RGBA(255,140,20,255).
     - Fuel cell at (px+56, py+53), ref 52.
     - Progress: background (px+80, py+39, 24, 6) in RGBA(0,0,0,90); fill width `24·cook/200` in RGBA(255,255,255,200).
     - Output cell at (px+116, py+35), ref 53.
     - Then `draw_player_inv` and `draw_overlay`.
   - **`screen_chest`:** "Chest" label at (px+8, py+6); cells at (px+8+18c, py+17+18r), ref 51 + 9r + c; then the player inventory and overlay.
   - **Survival inventory:** "Armor" label at (px+8, py+6); armor cells at (px+8+18i, py+17), refs 47+i.
   - **Creative palette:**
     - `palette` = blocks 1–17, 19, 20, 21 then items 32–81 (70 entries).
     - 6 visible rows; `pal_scroll` row offset, reset when `app_entered`.
     - `ui_input.scroll` (+1 = wheel up) → `pal_scroll −= scroll`, clamped to [0, 8−6].
     - Scrollbar track `ui_rect(px+170, py+18, 2, 108, RGBA(255,255,255,40))`; thumb height `108·6/8`, y = `py+18 + 108·pal_scroll/8`, RGBA(255,255,255,160).
3. **`hud.asm`:**
   - **Armor row:** when `armor_points() > 0`, 10 icons `bar_tile(points − 2i, TILE_ARMOR_FULL)` at (x0+8i, y0−20). The survival held-name y becomes y0−34 when armor is shown, else y0−24.
   - **Debug line:** `Mobs: <mob_count_kind(1)> hostile, <mob_count_kind(0)> passive` (strings `" hostile, "`, `" passive"`).
   - **Durability bars** (`hud_durability` here and `ui_slot` in `ui.asm`): test `item_durability ≠ 0` instead of `item_tool ≠ 0`.
4. **`menus.asm`:** death causes 5–7: "You were shot by a Skeleton", "You blew up", "You were slain by a Spider". The bound check becomes 7.
5. **`render.asm`:** after `drops_render` call `arrows_render`, then `tnt_render`.
6. **`hand.asm`:** when the held id is BOW and `game_bow_charge > 0`, apply `glTranslatef(0, 0, 0.18·min(1, charge))` right after the swing rotation, before `apply_pose`.

### 12. Round-trip test and registration

- **`test_game.asm` `[game_save_load_roundtrip]`** also sets:
  - armor[1] = {IRON_CHESTPLATE,1,3};
  - `world_set(128,60,128,CHEST)` + `cont_create(128,60,128,CONT_CHEST)` with slot 5 = {COAL,7}.

  After the load it checks armor[1] == {71,1,3}, and that `cont_at(128,60,128)` exists with slot 5 == {43,7}.
- **Register the new tests in `selftest.asm`:**
  - `world_load_v2_converts` after `world_load_v1_converts`;
  - `worldgen_ores` after `worldgen_shape`;
  - `craft_advanced_recipes`, `break_tiers`, `inv_click_armor_containers` after `break_time_rules`;
  - `armor_reduces_damage` after `sky_day_cycle`;
  - `furnace_smelts`, `chest_spills_on_break` after `settings_clamps_bad_values`;
  - `arrow_hits_mob`, `explosion_breaks_blocks`, `creeper_explodes`, `skeleton_shoots_player`, `mob_drops_by_type` after `mob_spawn_rules`.
- The total is **53**.

## Critical files & anchors

- **`src/common.inc` WORLDHDR:** offsets 0–943 must stay identical (save patches and the v2 conversion rely on them). `.containers` must start at 1024 and `WORLDHDR_size` must be 16384.
- **`src/world.asm` `world_load`/`convert_v1`:** the v2 path moves blocks with a backward copy because `blocks` (= `world_header + 16384`) overlaps the v2 data. The read cap is `WORLD_FILE_SIZE + 1`, absorbed by `world_slack`.
- **`src/items.asm` `inv_click`:**
  - Every stack address is now computed from the ref: armor 47–50 sit after the cursor; container 51+ go through `inv_container`.
  - `add_range` is gone; every shift path uses `add_cells`.
- **`src/mobs.asm` `mob_update`:** the creeper's explosion happens inside `mobs_step`'s loop. Set the creeper's type to NONE before calling `explode_at`, so its `mob_hurt` loop never touches it.
- **`src/game.asm` `game_frame` RMB/pick/bow ordering:**
  - The bow may start drawing only on a frame that did not open a screen.
  - A release seen while the cursor is not captured (a screen is open) must not fire.

## Verification

Run from the repo root, with GUI steps per **Conventions**.

1. `make clean && make 2>&1 | grep -iE "warn|error"` prints nothing. `make test` prints 53 `ok` lines and `selftest: 53 passed, 0 failed`. `readelf -lW build/assemblycraft | grep STACK` shows RW.
2. **Old saves convert:**
   1. `cp -r ~/.local/share/assemblycraft/worlds /tmp/acv3/worlds` (the user's v2 worlds).
   2. Launch in the box with `--data-dir /home/sbx/acv3`, after copying that folder into the box home.
   3. Both worlds are listed and load with their inventories. After "Save and Quit", `ls -l` shows 4210688 bytes.
3. **Creative palette:** a creative world, E → the palette scrolls with the wheel and shows all 70 entries. Take a shot of each scroll position. Place one of each new block in a row (ores, furnace, chest, gravel, TNT) and take a shot: the textures match step 6.
4. **Survival furnace and chest:**
   1. Patch a survival world: slot 0 {17,1} furnace, slot 1 {19,1} chest, slot 2 {14,3} iron ore, slot 3 {43,2} coal, slot 4 {65,4} rotten flesh.
   2. Place the furnace, RMB → furnace screen. Shift-click the ore and the coal. The flame gauge fills and the front shows fire in the world; after 10 s the output shows Iron Ingot ×1.
   3. Close (E), wait 10 s, reopen → ×2.
   4. Save and Quit, reopen → still there.
   5. Place the chest, put the flesh in, Save and Quit, reopen → the flesh is in the chest. Break the chest → a flesh stack drops.
5. **Crafting chain:** patch ingots, diamonds, sticks, string, flint and feathers.
   - Craft an iron pickaxe, a diamond sword, a bow, arrows ×4, flint and steel, and an iron helmet.
   - Mining: an iron pickaxe on placed diamond ore drops Diamond. A stone pickaxe on diamond ore drops nothing.
6. **Armor:** shift-click the iron helmet and chestplate from the inventory → they sit in the armor row, and the HUD shows an armor bar (4 icons: 8 points = 4 full). Taking a zombie hit at night shows less damage in F3 `Health` than the 3 a naked hit does.
7. **Bow:**
   1. Patch a pig 6 blocks in front (mob record at 304) and a bow with arrows ×5 into slots 0–1.
   2. Hold RMB 1 s (`pointer --window assemblycraft -- move 960 525 down right sleep 1s up right`) → the hand pulls the bow; an arrow flies and the pig is hit (red tint, knockback).
   3. A missed arrow stays stuck in the ground. Walking over it gives it back (hotbar arrow count + 1).
8. **Monsters at night:**
   1. Patch `time=40000` and mob records near the player: creeper (type 3) 5 blocks ahead, skeleton (4) 9 blocks ahead, spider (5) 6 blocks ahead, chicken (6) 3 blocks ahead.
   2. Shot: four distinct models.
   3. The skeleton's arrows lower F3 `Health`. The spider leaps.
   4. The creeper swells, flashes and explodes → a crater around it, and health drops.
   5. F3 shows `Mobs: N hostile, M passive`.
9. **TNT:** patch TNT ×1 and flint and steel. Place the TNT, then RMB on it with the flint and steel → a flashing cube; after 4 s there is a crater of radius 4 and nearby blocks drop items.
10. **Sound:** with `omabox run -- sh /home/sbx/cap.sh` (recreate it if missing) during the creeper or TNT explosion → `max_volume` > −20 dB. The new WAV dumps are in range per step 7.
11. **Performance:** with render distance 8, VSync off, and 10+ mobs, 20 arrows and a primed TNT in view, the title FPS ≥ 150 in the box.
12. **Close:** `omabox down`.

## Assumptions & contingencies

- **Skeletons drop only arrows.** Bones are left out: without crops, bone meal has no use.
- **Furnaces and chests have no orientation.** The furnace shows its front texture on all four sides and the chest has no opening lid.
- **No gravity for TNT or gravel.** Primed TNT and gravel do not fall. Flint and steel only lights TNT (there is no fire).
- **Explosion block drops:** a destroyed block drops its item with a 30% chance. Drops lying in the blast are not pushed.
- **Armor is not drawn on the player body.** There is no third-person view.
- **Not saved:** arrows and primed TNT are not saved with the world (drops are not either).
- **Capacities:** a world holds up to 120 furnaces and chests. Beyond that, placing one does nothing.
- **Contingency — palette scroll:** if `ui_input.scroll` is never non-zero in the creative screen (the cursor is released there), read the wheel the same way the worlds list does in `menus.asm`.
- **Contingency — spider spawning:** if spider spawns put it into walls (it is 1.4 wide), require the 3×1×3 cells above the ground to be AIR in `spawn_at_ground` for type SPIDER.
- **Contingency — FPS:** if FPS with 32 mobs drops below 60 in the box, skip `mobs_render` for mobs farther than the render distance (`(render_dist·16)²` horizontal).
