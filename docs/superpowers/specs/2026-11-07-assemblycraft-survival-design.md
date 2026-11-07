# AssemblyCraft 0.2 — survival, menus, save management, settings, day/night, mobs, sound

## Context

AssemblyCraft (repo `/run/media/octopusman/Games/Experiences/assemblycraft`) is a Minecraft-Classic creative clone written entirely in x86-64 NASM.
- It links GLFW, legacy GL and libc (crt1 only).
- `make test` passes 17/17.
- There are 3 commits; the last is `step 3: playable classic creative`.
- `.omp/` is untracked and must never be committed.

The user asked for everything that makes it a real game:
1. **Game modes:** Survival as a per-world mode. Creative stays as it plays today.
2. **Survival gameplay:**
   - health and fall, suffocation, starvation and mob damage;
   - death screen and respawn;
   - timed breaking with a crack overlay;
   - drops into a 36-slot inventory;
   - an inventory screen with 2×2 crafting, plus a 3×3 crafting table;
   - sticks and wood/stone tools with durability;
   - tool-gated drops, hunger and food.
3. **World:** a day/night cycle, and mobs (zombies at night, pigs).
4. **Sound:** procedural sound effects through libpulse-simple.
5. **Menus:** a main menu over a rotating world panorama in a minimal flat style, a pause menu, and a settings screen with key rebinding.
6. **Save management:** a world list with create, rename and delete, stored under `~/.local/share/assemblycraft`.

The end state is one binary. It opens on a title screen and plays both modes, and every one of those features is verified live in an omabox desktop.

## Conventions (unchanged from 0.1 — every file, every worker)

- **File layout:**
  - `%include "common.inc"` first, then `default rel`.
  - Files that touch GLFW or GL also `%include "gl.inc"`.
  - `common.inc` ends in `.note.GNU-stack`, so every file selects `section .text/.data/.rodata/.bss` explicitly before emitting.
- **Build:** NASM `-f elf64 -g -F dwarf -Isrc/`, linked with `gcc -no-pie`.
  - `-no-pie` allows absolute `[sym + reg*scale]` addressing and lets `call extern` resolve through the PLT.
  - The Makefile from 0.1 globs `src/*.asm`.
- **Calling convention:** SysV for ALL functions, internal ones included.
  - Callee-saved registers are `rbx, rbp, r12–r15`. Every `xmm` register is caller-saved.
  - `rsp` is 16-aligned at every `call`. In non-leaf functions, `push rbp; mov rbp,rsp`, pushes, then `sub rsp,N` with `8*pushes + N ≡ 0 (mod 16)`.
  - Stack arguments 7+ go at `[rsp]`, `[rsp+8]`, … at call time.
- **Symbols:** each file declares its own `extern`s and `global`s. NEVER put cross-module externs in `common.inc`.
- **Floats:**
  - Scalar SSE single precision. Floor is `roundss x,x,9`; ceil is `roundss x,x,10`.
  - x87 only inside `mathf.asm` (`sincos_deg`, `atan2_deg`) and the `sfx.asm` envelope constant (`f2xm1`). Always leave the x87 stack empty.
- **No libc calls.** Use raw syscalls through `sys.asm` or local `syscall`s. Allowed libraries: GLFW, GL, and libpulse-simple (`pa_simple_*` only).
- **Tests:**
  - A test is `()→eax`: 0 = pass.
  - It is named `test_<name>` and starts with `call world_clear`.
  - It is registered in `src/selftest.asm` with the `TEST`/`TESTNAME` macros plus an `extern`. The printed name is the function name without `test_`.
  - Tests that change globals (`settings`, `game_mode`, `inv`, `surv`, `mobs`, `game_time`, `rng` state) set every value they rely on themselves.
- **Worker isolation:**
  - Workers write only their owned files.
  - They build in a private scratch copy (`rm -rf /tmp/ac-<name> && mkdir -p /tmp/ac-<name> && git -C <repo> archive HEAD | tar -x -C /tmp/ac-<name>`), copy their files in, register their tests in the scratch `selftest.asm`, and run `make -C /tmp/ac-<name> test`.
  - Symbols owned by other workers in the same wave may be satisfied by a throwaway stub file in the scratch copy only.
  - Workers never commit. The integrator registers tests, merges, builds and commits.
  - If a test expectation fails while the code matches this spec, re-derive the value from the spec formulas with gdb before changing anything; never loosen a test.
- **omabox (GUI checks):**
  1. Load `skill://omabox` first.
  2. Run `omabox up --audio` with cwd `$HOME`. From the repo it refuses with a mount error.
  3. Copy the binary in with `cp build/assemblycraft "$H/.ac.new" && mv -f "$H/.ac.new" "$H/assemblycraft"`, where `H=$(omabox -b default path --home)`. A plain `cp` onto a running binary fails with "Text file busy".
  4. Switch the box to a US layout once: `omabox -b default lua 'hl.config({input={kb_layout="us", kb_variant=""}}); return "ok"'`.
  5. Close the window with `omabox -b default lua 'hl.dispatch(hl.dsp.window.close({window="class:assemblycraft"})); return "sent"'`. `hyprctl dispatch closewindow` is a no-op there.
  6. Mouse look cannot be tested in a box: a locked cursor gets no relative motion.
  7. Hold keys and buttons with `keys --window assemblycraft down:X -s 1s up:X`, and hold the mouse with `pointer --window assemblycraft -- move X Y down sleep 1500ms up`.
- **Parallel agents:** before starting, and before each commit, run `git status --short` and `git log --oneline -3`. Integrate around changes you did not make.

## Contracts (frozen in Wave 0; all later work is written against them)

### `src/common.inc` — constants (add these; existing ones stay unless stated)

- **Blocks:**
  - `CRAFTING_TABLE 12`. `NUM_BLOCKS` becomes `13`.
  - Item ids are `STICK 32`, `WOOD_PICKAXE 33`, `WOOD_AXE 34`, `WOOD_SHOVEL 35`, `WOOD_SWORD 36`, `STONE_PICKAXE 37`, `STONE_AXE 38`, `STONE_SHOVEL 39`, `STONE_SWORD 40`, `APPLE 41`, `PORKCHOP 42`.
  - `NUM_ITEMS 43`. Item tables have 43 entries; ids 13–31 are unused.
- **Tools:**
  - Kinds: `TOOL_NONE 0`, `TOOL_PICKAXE 1`, `TOOL_AXE 2`, `TOOL_SHOVEL 3`, `TOOL_SWORD 4`.
  - Tiers: `TIER_WOOD 1`, `TIER_STONE 2`.
- **Header and file:**
  - `WORLD_HDR_SIZE 1024` (was 48).
  - `WORLD_FILE_SIZE 4195328` (= 1024 + 4194304).
  - `WORLD_V1_SIZE 4194352` and `WORLD_V1_HDR 48`, for legacy files.
- **Modes and time:**
  - `MODE_SURVIVAL 0`, `MODE_CREATIVE 1`.
  - `DAY_LENGTH 72000` (fixed 1/60 s steps, a 20-minute day). `NEW_WORLD_TIME 6000`.
  - `PANORAMA_SEED 20261107`.
- **Difficulty:** `DIFF_PEACEFUL 0`, `DIFF_EASY 1`, `DIFF_NORMAL 2`, `DIFF_HARD 3`.
- **Death causes:** `CAUSE_FALL 1`, `CAUSE_ZOMBIE 2`, `CAUSE_STARVE 3`, `CAUSE_SUFFOCATE 4`.
- **Mobs:** `MOB_NONE 0`, `MOB_ZOMBIE 1`, `MOB_PIG 2`, `MAX_MOBS 32`.
- **Inventory:**
  - `INV_SLOTS 36` (0–8 hotbar, 9–35 main).
  - Slot references for `inv_click`: `SLOTREF_GRID 36` (grid cell c is 36+c, c 0–8, row-major 3 wide) and `SLOTREF_RESULT 45`.
- **App states:**
  - `ST_TITLE 0`, `ST_WORLDS 1`, `ST_CREATE 2`, `ST_RENAME 3`, `ST_DELETE 4`, `ST_SETTINGS 5`, `ST_CONTROLS 6`;
  - `ST_PLAYING 7`, `ST_PAUSED 8`, `ST_INVENTORY 9`, `ST_CRAFTING 10`, `ST_DEATH 11`, `ST_QUIT 12`.
- **Key bindings:**
  - Indices and defaults: `BIND_FORWARD 0` (W 87), `BIND_BACK 1` (S 83), `BIND_LEFT 2` (A 65), `BIND_RIGHT 3` (D 68), `BIND_JUMP 4` (Space 32), `BIND_SNEAK 5` (LShift 340), `BIND_SPRINT 6` (LCtrl 341), `BIND_INVENTORY 7` (E 69), `BIND_FLY 8` (F 70). `NUM_BINDINGS 9`.
  - Fixed keys: Esc, 1–9, F3, F11.
- **Sounds:**
  - `SND_CLICK 0`, `SND_DIG_STONE 1`, `SND_DIG_WOOD 2`, `SND_DIG_SOFT 3`, `SND_DIG_GLASS 4`, `SND_STEP_STONE 5`, `SND_STEP_WOOD 6`, `SND_STEP_SOFT 7`, `SND_HURT 8`;
  - `SND_EAT 9`, `SND_BURP 10`, `SND_ZOMBIE_SAY 11`, `SND_ZOMBIE_HURT 12`, `SND_PIG_SAY 13`, `SND_PIG_HURT 14`, `SND_TOOL_BREAK 15`, `SND_POP 16`.
  - `NUM_SOUNDS 17`.
- **Atlas tiles:**
  - Blocks: `TILE_TABLE_TOP 13`, `TILE_TABLE_SIDE 14`.
  - Cracks: `TILE_CRACK0 16` (stages 16–25). Item icons use tiles 32–42, equal to their item id.
  - HUD: `TILE_HEART_FULL 48`, `TILE_HEART_HALF 49`, `TILE_HEART_EMPTY 50`, `TILE_FOOD_FULL 51`, `TILE_FOOD_HALF 52`, `TILE_FOOD_EMPTY 53`.
  - Mobs: `TILE_ZOMBIE_SKIN 64`, `TILE_ZOMBIE_FACE 65`, `TILE_ZOMBIE_SHIRT 66`, `TILE_ZOMBIE_PANTS 67`, `TILE_PIG_SKIN 68`, `TILE_PIG_FACE 69`.
  - Font: `FONT_Y 192` (glyph rows at atlas y 192–239, x 0–127).
- **Syscalls:**
  - `SYS_STAT 4`, `SYS_LSEEK 8`, `SYS_PWRITE64 18`, `SYS_MKDIR 83`, `SYS_TIME 201`, `SYS_GETDENTS64 217`.
  - Flags and errors: `O_WRONLY 1`, `O_DIRECTORY 0x10000`, `EEXIST 17`.
- **Colours:** `%define RGBA(r,g,b,a) ((r)|((g)<<8)|((b)<<16)|((a)<<24))`. This packing is passed to `glColor4ub` as four bytes.

### `src/common.inc` — structs

- **`PLAYER` is renamed to `BODY`, with fields added at the end. The existing offsets are unchanged.**

  ```nasm
  struc BODY
      .x: resd 1   .y: resd 1   .z: resd 1        ; float, .y = feet
      .vx: resd 1  .vy: resd 1  .vz: resd 1
      .yaw: resd 1 .pitch: resd 1
      .on_ground: resd 1  .flying: resd 1          ; int32
      .half_w: resd 1  .height: resd 1  .speed: resd 1   ; float: box half width, box height, walk speed
      .kbx: resd 1  .kbz: resd 1                   ; float knockback velocity (decays)
      .fall: resd 1                                ; float distance fallen since last on ground
      .blocked: resd 1                             ; int32: 1 if an X or Z collision happened this step
  endstruc                                         ; 68 bytes
  ```

  (In the real file, write one field per line.)
- **`ITEMSTACK` (4 B):** `.id resb 1`, `.count resb 1`, `.dmg resw 1` (tool damage taken). Empty means id 0 / count 0.
- **`INVENTORY`:** `.slots resb 36*4`, `.grid resb 9*4`, `.result resb 4`, `.cursor resb 4`.
- **`SURVIVAL`:** int32 fields unless marked.
  - `.health`, `.food`, `.saturation` (float), `.exhaustion` (float);
  - `.regen_timer`, `.starve_timer`, `.invuln`, `.hurt_flash`, `.suffocate_timer`, `.eat_timer`, `.eat_sound`;
  - `.dead`, `.death_cause`.
- **`MOB`:**
  - `.body resb BODY_size`, `.type`, `.health`, `.hurt` (steps), `.cooldown` (steps), `.ai_timer` (steps), `.panic` (steps);
  - `.walk` (float, degrees of walk-cycle phase), `.input resb INPUT_size`.
- **`MOBSAVE` (20 B):** `.type`, `.health` (int32), `.x .y .z` (float).
- **`WORLDHDR` (1024 B; offsets fixed — the verification patches files at these offsets):**

  |off|field|size|
  |---|---|---|
  |0|`.magic` `"ACRAFT02"`|8|
  |8|`.seed` u32|4|
  |12|`.mode` int32|4|
  |16|`.time` u32|4|
  |20|`.name` NUL-terminated, ≤32 chars|33|
  |53|`.pad0`|3|
  |56|`.spawn_x .spawn_y .spawn_z` int32|12|
  |68|`.player` (raw `BODY`)|68|
  |136|`.health` `.food` int32|8|
  |144|`.saturation` `.exhaustion` float|8|
  |152|`.sel` int32|4|
  |156|`.inventory` (36 `ITEMSTACK`)|144|
  |300|`.mob_count` int32|4|
  |304|`.mobs` (32 `MOBSAVE`)|640|
  |944|`.pad`|80|

  The legacy v1 header (48 B, magic `"ACRAFT01"`) is: magic 0, seed 8, px/py/pz/yaw/pitch floats at 12–31, flying byte at 32, sel byte at 33, hotbar ids at 34–42.
- **`SETTINGS`:**
  - `.fov` (50–110, default 70), `.sensitivity` (10–300 %, 100), `.render_dist` (2–16 chunks, 8), `.volume` (0–100, 100), `.difficulty` (0–3, 2);
  - `.invert_mouse` (0/1, 0), `.vsync` (0/1, 1), `.fullscreen` (0/1, 0), `.gui_scale` (0 = auto, 1–4; 0);
  - `.keys resd NUM_BINDINGS` (GLFW key codes, valid 32–348).
- **`FRAMEINPUT` (replaces 0.1's).** `.save` and `.captured` are removed:
  - `.move resb INPUT_size`, `.look_dx .look_dy` (float);
  - `.lmb_held .lmb_pressed .rmb_held .rmb_pressed .mmb_pressed`, `.slot` (−1 or 0–8), `.scroll` (+1 = wheel up);
  - `.toggle_fly`, `.inventory`, `.debug` (F3), `.fullscreen` (F11).
- **`UIINPUT`:**
  - `.mouse_px .mouse_py` (int framebuffer pixels);
  - `.lmb_pressed .lmb_held .rmb_pressed .shift .scroll .double_click`;
  - `.enter .escape .backspace` (counts or edges), `.key_pressed` (last key code pressed this frame, or −1);
  - `.typed_len`, `.typed resb 32`.
- **`TEXTFIELD`:** `.buf resb 33`, `.pad resb 3`, `.len resd 1`, `.max resd 1`.
- **`SLIDERDEF`:** `.value resq 1` (int32*), `.prefix resq 1` (zstr), `.suffix resq 1` (zstr), `.min resd 1`, `.max resd 1`.
- **`WORLDENTRY` (128 B):** `.file resb 64` (file name only), `.name resb 33`, `.pad resb 7`, `.mtime resq 1`, `.mode resd 1` (0, 1, or 2 = legacy v1), `.seed resd 1`, `.valid resd 1`, `.pad2 resd 1`.
- **`SFXLAYER` (60 B):**
  - `.sound .wave` (int32: 0 noise, 1 square, 2 saw);
  - `.f0 .f1 .lp` (float), `.hp` (int32), `.env` (int32: 0 exp, 1 linear);
  - `.half .attack .start .dur .amp .vdepth .vrate` (float).

### Data tables (Wave 0)

**`blockdefs.asm`** — `block_names` is removed (replaced by `item_names`). Per block id 0–12:

|id|flags|tiles t/s/b|hardness (dd)|tool|needs tool|drop|dig sound|step sound|
|---|---|---|---|---|---|---|---|---|
|AIR|0|0,0,0|0.0|0|0|0|0|0|
|STONE|3|0,0,0|1.5|1|1|COBBLE|DIG_STONE|STEP_STONE|
|GRASS|3|1,2,3|0.6|3|0|DIRT|DIG_SOFT|STEP_SOFT|
|DIRT|3|3,3,3|0.5|3|0|DIRT|DIG_SOFT|STEP_SOFT|
|COBBLE|3|4,4,4|2.0|1|1|COBBLE|DIG_STONE|STEP_STONE|
|PLANKS|3|5,5,5|2.0|2|0|PLANKS|DIG_WOOD|STEP_WOOD|
|LOG|3|7,6,7|2.0|2|0|LOG|DIG_WOOD|STEP_WOOD|
|LEAVES|1|8,8,8|0.2|0|0|0 (apple chance)|DIG_SOFT|STEP_SOFT|
|SAND|3|9,9,9|0.5|3|0|SAND|DIG_SOFT|STEP_SOFT|
|GLASS|5|10,10,10|0.3|0|0|0|DIG_GLASS|STEP_STONE|
|BRICK|3|11,11,11|2.0|1|1|BRICK|DIG_STONE|STEP_STONE|
|BEDROCK|3|12,12,12|−1.0 (unbreakable)|0|0|0|DIG_STONE|STEP_STONE|
|CRAFTING_TABLE|3|13,14,5|2.5|2|0|CRAFTING_TABLE|DIG_WOOD|STEP_WOOD|

The symbols are `block_flags`, `block_tiles`, `block_hardness`, `block_tool`, `block_needs_tool`, `block_drop`, `block_dig_sound` and `block_step_sound`.

**New `itemdefs.asm`** (data only). Per item id 0–42, unused ids are 0 or `"?"`:
- `item_names dq`:
  - Blocks: "Air", "Stone", "Grass", "Dirt", "Cobblestone", "Planks", "Log", "Leaves", "Sand", "Glass", "Bricks", "Bedrock", "Crafting Table".
  - Items: "Stick", "Wooden Pickaxe", "Wooden Axe", "Wooden Shovel", "Wooden Sword", "Stone Pickaxe", "Stone Axe", "Stone Shovel", "Stone Sword", "Apple", "Raw Porkchop".
- `item_icon db`: for blocks, their side tile (the `block_tiles` side column); for items 32–42, the id itself.
- `item_max_stack db`: blocks 1–12 are 64, AIR is 0, sticks/apple/porkchop are 64, tools are 1, unused ids are 0.
- `item_tool db` and `item_tier db`:
  - Pickaxe 33/37 → 1; axe 34/38 → 2; shovel 35/39 → 3; sword 36/40 → 4.
  - Tier: 33–36 → 1, 37–40 → 2.
- `item_durability dw`: wood tools 59, stone tools 131.
- `item_food db` / `item_saturation dd`: apple 4 / 2.4, porkchop 3 / 1.8.
- `item_attack db`: default 1; wood sword 5, stone sword 6, wood axe 4, stone axe 5, wood pickaxe 3, stone pickaxe 4, wood shovel 2, stone shovel 3.

### Module API (every global; argument registers in order)

|File (owner)|Symbol|Contract|
|---|---|---|
|`sys.asm` (W0)|existing + `fnv1a`|`(rdi ptr, rsi len)→eax`. It moves here from `test_world.asm`|
||`str_copy`|`(rdi dst, rsi src, rdx max)→rax` = end. Copies ≤ max chars and writes a NUL|
||`f32_to_str`|`(xmm0 v, rdi buf, esi decimals)→rax` end. Signed, rounds half away from zero, no NUL|
||`file_stat_mtime`|`(rdi path)→rax` mtime seconds, or −errno (`SYS_STAT`, `st_mtime` at offset 88 of a 144-byte buffer)|
||`file_patch`|`(rdi path, rsi offset, rdx buf, rcx len)→eax` 0/−errno: open `O_WRONLY`, `pwrite64`, close|
||`file_unlink`|`(rdi path)→eax` 0/−errno|
||`time_now`|`()→rax` epoch seconds (`SYS_TIME`)|
|`mathf.asm` (W0)|existing + `atan2_deg`|`(xmm0 y, xmm1 x)→xmm0` degrees (x87 `fpatan`)|
||`rng_seed` / `rng_next`|`(edi)` / `()→eax`. xorshift32 (`x^=x<<13; x^=x>>17; x^=x<<5`); a zero seed becomes 0x9E3779B9|
|`world.asm` (W0)|as 0.1, header v2|`world_load` also accepts v1 files (see Wave 0). `world_save` writes `"ACRAFT02"`|
|`player.asm` (W0)|`player` (`BODY`), `body_init`|`(rdi body, xmm0 half_w, xmm1 height, xmm2 speed)`: zeroes the body, then sets those three|
||`body_step`|`(rdi body, rsi INPUT*)→xmm0` fall distance that ended on this step (0 if none)|
||`body_intersects_block`|`(rdi body, esi x, edx y, ecx z)→eax` (replaces `player_intersects_block`)|
||`player_spawn`, `player_look`, `player_eye`, `player_forward`|`player_spawn` → `body_init(&player, 0.3, 1.8, 4.317)`, position `(spawn_x+0.5, spawn_y, spawn_z+0.5)` from `world_header`, yaw 0, pitch 30. Others as 0.1|
|`items.asm` (W1)|`inv` (`INVENTORY`), `inv_sel` (dd), `craft_size` (dd, 2 or 3)|state|
||`inv_clear`, `inv_set_creative_default`|the default is slots 0–8 = STONE, DIRT, GRASS, COBBLE, PLANKS, LOG, LEAVES, GLASS, BRICK, each count 1|
||`inv_add`|`(edi id, esi count)→eax` leftover|
||`inv_room_for`|`(edi id)→eax` how many fit|
||`inv_held`|`()→rax` `&inv.slots[inv_sel]`|
||`inv_consume_held`|`(edi n)`|
||`inv_damage_held`|`(edi amount)→eax` 1 if the tool broke|
||`inv_find_hotbar`|`(edi id)→eax` slot 0–8 or −1|
||`inv_click`|`(edi slotref, esi button 0 left/1 right, edx shift)→eax` changed|
||`inv_close_screen`|returns grid and cursor items to the inventory (survival); overflow is discarded|
||`craft_update`|recomputes `inv.result`|
||`item_break_time`|`(edi block, esi held_id)→xmm0` seconds|
||`item_harvest_drop`|`(edi block, esi held_id)→eax` item id or 0|
||`item_attack_damage`|`(edi id)→eax`|
|`survival.asm` (W5)|`surv` (`SURVIVAL`)|state|
||`survival_reset`, `survival_damage`|`survival_damage(edi amount, esi cause)→eax` applied 0/1|
||`survival_land`, `survival_exhaust`|`(xmm0 dist)`, `(xmm0 amount)`|
||`survival_step`|`(rdi INPUT*, xmm0 horiz_dist, esi jumped)`: once per fixed step, survival mode only|
||`survival_eat_step`|`(edi rmb_held)→eax` 1 on the step an item is eaten|
||`survival_can_sprint`|`()→eax`|
|`sky.asm` (W5)|`sky_brightness`|`(edi time)→xmm0`|
||`sky_color`|`(edi time, rsi out float[3])`|
||`sky_angle`|`(edi time)→xmm0` degrees|
||`sky_is_night`|`(edi time)→eax`|
|`mobs.asm` (W6)|`mobs` (`MAX_MOBS×MOB`), `mob_count_type`|`(edi type)→eax`|
||`mobs_clear`, `mobs_step`, `mobs_populate`|state changes|
||`mob_spawn`|`(edi type, xmm0 x, xmm1 y, xmm2 z)→eax` index or −1|
||`mobs_raycast`|`(rdi origin[3], rsi dir[3], xmm0 max)→eax` index/−1, with xmm0 = t|
||`mob_hurt`|`(edi idx, esi dmg, xmm0 dirx, xmm1 dirz)→eax` applied|
||`mobs_intersect_block`|`(edi x, esi y, edx z)→eax`|
||`mobs_save` / `mobs_load`|`(rdi WORLDHDR*)`|
|`mobrender.asm` (W11)|`mobs_render`|`()`: GL state set by `render_world`|
|`audio.asm` (W4)|`audio_init`|`()→eax` 1 ok / 0 disabled|
||`audio_update`|`(xmm0 dt)`|
||`audio_play`|`(edi snd, xmm0 vol)`|
||`audio_play_at`|`(edi snd, xmm0 x, xmm1 y, xmm2 z, xmm3 vol)`|
||`audio_shutdown`|`()`. Every call is a no-op while disabled or before init|
|`sfx.asm` (W4)|`sfx_build`, `sfx_table` (dd offset, length ×17), `sfx_pool` (int16)|state|
|`texgen.asm` (W0 font, W2 tiles)|`texgen_build`|as 0.1, more tiles|
|`font.asm` (W0)|`font8x8`|96×8 bytes, chars 32–127|
|`saves.asm` (W3)|`data_dir`, `worlds_dir`, `settings_path` (zstr buffers, 4096 each), `world_list` (64×`WORLDENTRY`), `world_count`|state|
||`saves_init`|`(rdi envp or 0, rsi override_dir or 0)→eax` 0/−errno|
||`saves_scan`|`()→eax` count|
||`saves_entry_path`|`(edi idx, rsi out)`|
||`saves_name_to_file`|`(rdi name, rsi out)→rax` end. Sanitised stem with no extension and no NUL|
||`saves_new_file_path`|`(rdi name, rsi out)→eax` 0 / −1|
||`saves_delete`|`(edi idx)→eax`|
||`saves_rename`|`(edi idx, rsi new_name)→eax`|
||`fmt_ago`|`(rdi out, rsi mtime)→rax` end|
|`settings.asm` (W3)|`settings` (`SETTINGS` in `.data`, initialised to the defaults)|state|
||`settings_defaults`, `settings_reset_keys`, `settings_load`, `settings_save`|`settings_load(rdi)→eax` 0/1 missing/2 had bad lines; `settings_save(rdi)→eax`|
||`settings_apply`|`(rdi window)`|
|`ui.asm` (W7)|`ui_w ui_h ui_scale ui_mx ui_my` (dd), `ui_focus` (dq)|state|
||`ui_init`, `ui_begin`|`ui_begin(edi fb_w, esi fb_h)`|
||`ui_rect`, `ui_frame`, `ui_panel`|`(edi x, esi y, edx w, ecx h, r8d rgba)`; `ui_panel` takes no colour|
||`ui_text`|`(rdi s, esi x, edx y, ecx rgba, r8d scale)→eax` width|
||`ui_text_width`|`(rdi s, esi scale)→eax`|
||`ui_text_centered`|`(rdi s, esi cx, edx y, ecx rgba, r8d scale)`|
||`ui_button`|`(rdi label, esi x, edx y, ecx w, r8d enabled)→eax` clicked|
||`ui_slider`|`(rdi SLIDERDEF*, esi x, edx y, ecx w)→eax` changed|
||`ui_textfield`|`(rdi TEXTFIELD*, esi x, edx y, ecx w)→eax` 1 on Enter|
||`ui_slot`|`(rdi ITEMSTACK*, esi x, edx y, ecx show_count)→eax` hover|
||`ui_item_icon`|`(edi id, esi x, edx y, ecx size)`|
||`ui_icon9`|`(edi tile, esi x, edx y)`|
||`ui_tooltip`|`(rdi s)`|
|`input.asm` (integrator)|`frame_input`, `ui_input`, `input_captured` (dd)|state|
||`input_init`, `input_poll`|`(rdi win)`|
||`input_set_captured`|`(rdi win, esi on)`|
|`game.asm` (integrator)|`game_mode`, `game_time`, `game_target` (`RAYHIT`), `game_has_target`, `game_break_progress` (float), `game_open_table` (dd)|state|
||`game_new`|`(edi seed, esi mode, rdx name)`|
||`game_load` / `game_save`|`(rdi path)→eax` (codes as `world_load` / `world_save`)|
||`game_frame`, `game_respawn`|`game_frame(xmm0 dt)`|
|`app.asm` (integrator)|`app_state`, `app_entered` (dd: 1 after a state change, cleared by the new state's screen), `app_settings_parent`, `app_selected` (−1 or index), `app_in_world`, `app_fps`, `app_show_debug`, `app_window` (dq), `app_message` (zstr buffer 128), `app_message_timer` (float)|state|
||`app_run`|`(rdi play_path or 0)→eax` exit code|
||`app_goto`|`(edi state)`|
||`app_play_world`|`(edi idx)`|
||`app_create_world`|`(rdi name, esi mode, edx seed)`|
||`app_quit_to_title`|`()`|
||`app_respawn`|`(edi to_title)`|
||`app_request_quit`|`()`|
|`menus.asm` (W8)|`screen_title/worlds/create/rename/delete/pause/death`, `screen_loading`|`screen_*()`; `screen_loading(rdi text)`|
|`options.asm` (W9)|`screen_settings`, `screen_controls`, `key_name`|`key_name(edi key, rsi out)→rax` end|
|`invscreen.asm` (W10)|`screen_inventory`, `screen_crafting`|`()`|
|`hud.asm` (W11)|`hud_draw`, `hud_dt` (float, written by the app each frame)|`hud_draw()`, after `ui_begin`|
|`render.asm` (W11)|`render_init`, `render_update_chunks`, `render_world`|`render_world(rdi cam BODY*, esi fb_w, edx fb_h)`. `render_frame` is removed|

## Approach

### Wave 0 — contracts and refactors (integrator, sequential; tree builds and tests pass at the end)

1. **Spec and Makefile.**
   - Copy this plan to `docs/superpowers/specs/2026-11-07-assemblycraft-survival-design.md`. Workers read it there.
   - In the `Makefile`, change the link line to `gcc -no-pie -o $@ $(OBJS) -lglfw -lGL -lpulse-simple`.
2. **Write the constants and structs above** into `src/common.inc`, and delete `PLAYER`.
   - Replace `PLAYER.` with `BODY.` everywhere (`grep -n "PLAYER\." src/*.asm` must be empty afterwards).
   - Replace `WORLDHDR` with the v2 layout.
3. **Extend `src/gl.inc`.**
   - Externs: `glActiveTexture glTexEnvi glTexEnvfv glPushMatrix glPopMatrix glColor3f glColor4ub glDepthMask glfwSetKeyCallback glfwSetCharCallback glfwGetKeyName glfwGetWindowSize glfwGetWindowPos glfwGetWindowAttrib glfwGetPrimaryMonitor glfwGetVideoMode glfwSetWindowMonitor glfwSetWindowShouldClose`.
   - Enums (values verified in headers):
     - Texture units and environment: `GL_TEXTURE0 0x84C0`, `GL_TEXTURE1 0x84C1`, `GL_TEXTURE_ENV 0x2300`, `GL_TEXTURE_ENV_MODE 0x2200`, `GL_TEXTURE_ENV_COLOR 0x2201`.
     - Combiner: `GL_COMBINE 0x8570`, `GL_COMBINE_RGB 0x8571`, `GL_COMBINE_ALPHA 0x8572`, `GL_SOURCE0_RGB 0x8580`, `GL_SOURCE1_RGB 0x8581`, `GL_SOURCE0_ALPHA 0x8588`, `GL_OPERAND0_RGB 0x8590`, `GL_OPERAND1_RGB 0x8591`, `GL_OPERAND0_ALPHA 0x8598`.
     - Sources and modes: `GL_PREVIOUS 0x8578`, `GL_CONSTANT 0x8576`, `GL_MODULATE 0x2100`, `GL_REPLACE 0x1E01`, `GL_SRC_COLOR 0x0300`.
     - GLFW actions and attributes: `GLFW_RELEASE 0`, `GLFW_REPEAT 2`, `GLFW_FOCUSED 0x20001`, `GLFW_DONT_CARE -1`, `GLFW_STICKY_KEYS 0x33002`, `GLFW_STICKY_MOUSE_BUTTONS 0x33003`.
     - Keys: `KEY_E 69`, `KEY_ENTER 257`, `KEY_BACKSPACE 259`, `KEY_KP_ENTER 335`, `KEY_F3 292`, `KEY_F11 300`, `KEY_RIGHT_SHIFT 344`.
   - Remove `KEY_F5` and `KEY_F` (both now come from bindings).
4. **Write the block and item tables** into `blockdefs.asm` and the new `itemdefs.asm` exactly as specified.
   - In `main.asm`, `block_names` becomes `item_names`.
5. **`sys.asm`.**
   - Move `fnv1a` out of `test_world.asm` and into `sys.asm`, then delete it from `test_world.asm`.
   - Add `str_copy`, `f32_to_str`, `file_stat_mtime`, `file_patch`, `file_unlink` and `time_now`.
6. **`mathf.asm`.** Add `atan2_deg`, `rng_seed` and `rng_next`. The state lives in `.data`, initialised to 0x12345678.
   - `main` seeds it from `rdtsc` in game mode. Tests seed it explicitly.
7. **Turn `player.asm` into body physics.**
   - `move_axis(rdi body, esi axis, xmm0 d)` builds its box from the body: lo = (−half_w, 0, −half_w), hi = (half_w, height, half_w). The snap formulas are as 0.1 with 0.3/1.8 replaced by `half_w`/`height`. An X or Z hit sets `.blocked = 1`.
   - `body_step(body, INPUT*)`:
     1. Record `y0` and `.blocked = 0`.
     2. Compute the wish vector and speed as 0.1: `flying ? 10.89 : (sprint ? 5.612 : body.speed)`.
     3. Set `vx = mx*speed + kbx` and `vz = mz*speed + kbz`.
     4. Decay knockback: `kbx *= 0.8`, `kbz *= 0.8`; each is set to 0 when `|kb| < 0.05`.
     5. Set `vy` as 0.1, set `on_ground = 0`, and move Y, X, Z.
     6. Fall tracking:
        - flying → `fall = 0`, return 0;
        - else if on_ground → `landed = fall + max(0, y0 − y)`, `fall = 0`, return `landed`;
        - else if `y < y0` → `fall += y0 − y`; return 0.
   - `body_intersects_block` uses the body's own box.
   - Delete `player_step` and `player_intersects_block`.
   - `player_look(dx, dy)` keeps its 0.15 deg/px scale. The caller pre-scales for the sensitivity setting and inversion.
8. **`world.asm`.** Lay out `.bss` as `world_header resb WORLD_HDR_SIZE`, `blocks`, `world_slack resb 16`, `chunk_dirty` (still contiguous).
   - `world_load` reads with cap `WORLD_FILE_SIZE+1`:
     - size == `WORLD_FILE_SIZE` with magic `ACRAFT02` → ok.
     - size == `WORLD_V1_SIZE` with magic `ACRAFT01` → convert, then ok:
       1. Copy the 48 v1 bytes to a 48-byte scratch.
       2. Move 4194304 bytes from `world_header+48` to `blocks`, copying backwards (`std`/`rep movsb`/`cld`) because the regions overlap with dest > src.
       3. Zero the 1024-byte header.
       4. Write magic `ACRAFT02`, the v1 seed, `mode = MODE_CREATIVE`, `time = NEW_WORLD_TIME`, and an empty name.
       5. Set the spawn to `(128, world_top_y(128,128)+1, 128)`.
       6. Write player x/y/z/yaw/pitch and `flying = v1 byte 32` into `.player`.
       7. Set health 20, food 20, saturation 5.0, and `sel = v1 sel` if < 9, else 0.
       8. Set inventory slots 0–8 to `{v1 hotbar id, 1, 0}`, using that slot's creative default for ids 0 or ≥ `NUM_BLOCKS`.
       9. Set `mob_count = 0`.
     - Anything else → 2.
   - `world_save` is unchanged apart from the magic `"ACRAFT02"` and the new size.
9. **Font.**
   - New `font.asm`: `font8x8` is rows U+0020–U+007F of `font8x8_basic` (Daniel Hepper, Public Domain, `https://raw.githubusercontent.com/dhepper/font8x8/master/font8x8_basic.h`).
     - Use one `db` line per glyph, 8 bytes, in file order, with the source and licence in the header comment.
     - Bit order: byte = row, top first; bit 0 = leftmost pixel.
     - A throwaway converter outside the repo is allowed; the committed file is NASM.
   - In `texgen.asm`, after all tiles (no RNG involved), paint the font: for c in 32–127 and each set bit (x, y), write RGBA (255,255,255,255) at atlas `(((c−32)&15)*8 + x, FONT_Y + ((c−32)>>4)*8 + y)`.
10. **Minimal edits so the current game still builds and runs.**
    - `game.asm`: `hotbar` stays in this wave. `game_load`/`game_save` map `hotbar[i]` ↔ `inventory[i].id` (count 1), `hotbar_sel` ↔ `.sel`, and the `player` fields ↔ `.player`. `player_step` becomes `body_step(&player, …)`; the place check uses `body_intersects_block(&player, …)`.
    - `input.asm` and `main.asm`: remove the F5 `.save` path, and replace `.captured` with an `input_captured` global.
    - Symbols that Wave 1 modules link against must exist before Wave 1 merges. They are storage only; Wave 2 rewrites these files.
      - `game.asm` exports `game_mode` (`.data`, initialised to `MODE_CREATIVE`) and `game_time` (`.data`, initialised to `NEW_WORLD_TIME`).
      - `render.asm` makes `tex_id` global.
      - `input.asm` exports `ui_input` (`resb UIINPUT_size`, zeroed).
11. **Tests.**
    - `test_physics.asm`:
      - `reset_player` calls `body_init(&player, 0.3, 1.8, 4.317)`;
      - `player_step` becomes `body_step(&player, &inp)`;
      - `test_player_intersects_block` is renamed `test_body_intersects_block`, with the same expectations, via `body_intersects_block(&player, …)`.
    - `test_world_save_load`: also assert `WORLDHDR_size == 1024`.
    - New `test_world_load_v1_converts` in `test_world.asm`:
      1. `world_clear`, then set (1,2,3) = BRICK.
      2. Write v1 bytes into `world_header[0..47]`: magic `ACRAFT01`, seed 77, sel 2, hotbar `1,3,2,4,5,6,7,9,10`.
      3. Copy `blocks` forward to `world_header+48`.
      4. `file_write_atomic("/tmp/assemblycraft-selftest-v1.acw", world_header, WORLD_V1_SIZE)`.
      5. `world_clear`, then `world_load` → 0.
      6. Check: magic `ACRAFT02`, seed 77, mode 1, (1,2,3) = BRICK, inventory slot 2 id = GRASS (2), sel 2.
      7. Unlink the file.
12. **Done when:**
    - `make && make test` prints 18 `ok` lines;
    - `./build/assemblycraft --world /tmp/x.acw` still plays (the old CLI is untouched in this wave);
    - the build has no exec-stack warning.

    Commit `0.2 wave 0: contracts, body physics, header v2, font`.

### Wave 1 — seven parallel workers (spawn in one `task` batch; each prompt says "read `docs/superpowers/specs/2026-11-07-assemblycraft-survival-design.md` sections Conventions, Contracts and your Wave 1 section")

**W1 Items — `items.asm`, `test_items.asm`**

- **`inv_add(id, count)`:**
  1. If `item_max_stack[id] == 0`, return count.
  2. Merge into slots of the same id with `dmg == 0` and `count < max`, hotbar 0–8 first, then 9–35.
  3. Then fill empty slots in the same order, each up to max.
  4. Return what did not fit.
- **`inv_room_for`** computes the same capacity without writing.
- **`inv_click(ref, button, shift)`.** `ref` 0–35 is a slot, 36–44 a grid cell, 45 the result.
  - **Result, left or right:**
    - Shift: loop while the result is non-empty and `inv_room_for(result.id) ≥ result.count`: `inv_add`, then consume.
    - No shift: if the cursor is empty → `cursor = result`, then consume; else if `cursor.id == result.id`, `cursor.dmg == 0` and `cursor.count + result.count ≤ max` → add the count, then consume.
    - "Consume" removes 1 from every non-empty cell of the active `craft_size × craft_size` grid, then calls `craft_update`.
    - Play `SND_POP` (vol 0.5) once per click that crafted.
  - **Shift on a slot:**
    - Hotbar 0–8 moves to main 9–35; main moves to the hotbar. Merge into same-id stacks first, then empties, within the target region; the leftover stays.
    - A grid cell goes to `inv_add`; the leftover stays, then `craft_update`.
  - **Left, no shift:**
    - cursor empty → take the whole stack;
    - slot empty → put all down;
    - same id, both `dmg == 0`, max > 1 → move `min(cursor.count, max − slot.count)`;
    - otherwise swap.
  - **Right:**
    - cursor empty, slot non-empty → the cursor takes `ceil(n/2)` and the slot keeps `floor(n/2)`;
    - cursor non-empty and slot empty → place 1;
    - same id, `dmg == 0`, count < max → +1;
    - otherwise swap.
  - Any change to a grid cell calls `craft_update`.
- **`inv_close_screen`:** `inv_add` each grid cell, then the cursor, and clear them; `craft_update`; set `craft_size = 2`.
- **Recipes** (`.rodata`): records `db w, h, out_id, out_count, cells[9]` (row-major in w×h, 0 = empty). P = 5, C = 4, S = 32, L = 6. In order:
  1. 1×1 `L` → PLANKS ×4.
  2. 1×2 `P/P` → STICK ×4.
  3. 2×2 `PP/PP` → CRAFTING_TABLE ×1.
  4. For M ∈ {P → wood ids, C → stone ids}:
     - pickaxe 3×3 `MMM/0S0/0S0`;
     - axe 2×3 `MM/MS/0S`;
     - axe mirrored 2×3 `MM/SM/S0`;
     - shovel 1×3 `M/S/S`;
     - sword 1×3 `M/M/S`.
- **`craft_update`:**
  1. Take the bounding box of the non-empty cells in the active `craft_size × craft_size` region (cell index `r*3 + c`).
  2. Find the first recipe with an equal w×h whose cells match by id.
  3. Set `result = {out_id, out_count, 0}`, or empty when there is no match.
- **`item_break_time(block, held)`:**
  - hardness < 0 → 1e30;
  - `match = block_tool[block] ≠ 0 && item_tool[held] == block_tool[block]`;
  - `speed = match ? (tier 1 → 2.0, tier 2 → 4.0) : 1.0`;
  - `can = !block_needs_tool[block] || match`;
  - time = `can ? h*1.5/speed : h*5.0/speed`.
- **`item_harvest_drop`** = `can ? block_drop[block] : 0`.
- **`item_attack_damage(id)`** = `item_attack[id]`, with 1 for id 0.
- **`inv_damage_held(amount)`:**
  - non-tool → 0;
  - `dmg += amount`;
  - if `dmg ≥ durability` → clear the slot, play `SND_TOOL_BREAK` (0.9), return 1.
- **Tests** (registered names in brackets):
  - **`[inv_add_merges]`:**
    1. `inv_add(DIRT,70)` → slot 0 `{3,64}`, slot 1 `{3,6}`.
    2. Add WOOD_PICKAXE twice → slots 2 and 3, each `{33,1}`.
    3. `inv_add(COBBLE, 2304)` → returns 256.
  - **`[inv_right_click_split]`:**
    1. Slot 5 = `{DIRT,5}`.
    2. Right-click 5 → cursor 3, slot 2.
    3. Right-click empty 6 → slot 6 = 1, cursor 2.
    4. Left-click 6 → slot 6 = 3, cursor empty.
  - **`[craft_planks_from_log]`:**
    1. `craft_size = 2`, grid cell 4 = `{LOG,1}`, `craft_update` → result `{PLANKS,4}`.
    2. Left-click 45 → cursor `{5,4}`; cell 4 and the result are empty.
  - **`[craft_tool_shapes]`** (`craft_size = 3`):
    - cells 0,1,2 = C and 4,7 = S → STONE_PICKAXE;
    - cells 0,1,4 = P and 3,6 = S → WOOD_AXE;
    - the same shape shifted one column right → WOOD_AXE;
    - P in cells 0 and 4 only → empty;
    - `craft_size = 2` with P in cells 0,1,3,4 → CRAFTING_TABLE.
  - **`[craft_shift_click_all]`:** `craft_size = 2`, cell 0 = `{LOG,3}`; shift-click 45 → slot 0 `{5,12}`; the grid and result are empty.
  - **`[break_time_rules]`** (±0.001):
    - `item_break_time`: DIRT/0 = 0.75, STONE/0 = 7.5, STONE/WOOD_PICKAXE = 1.125, LOG/STONE_AXE = 0.75, BEDROCK/0 ≥ 1e29.
    - `item_harvest_drop`: STONE/0 = 0, STONE/WOOD_PICKAXE = COBBLE, GRASS/0 = DIRT, GLASS/0 = 0.

**W2 Art — `texgen.asm` (new tiles only)**

- Keep tiles 0–12 byte-identical. Continue the same RNG stream in this order: 13, 14, cracks, 64–69. Items and HUD use no RNG; the font comes last.
- "m" is the per-pixel multiplier drawn as in 0.1, and colours are shaded `base*m>>8`.
- **13 `table_top`:** one draw per pixel, m = 216+(r&31); colour:
  - border (px or py ∈ {0,15}) → (104,82,50);
  - else px == 7 or py == 7 → (110,86,50);
  - else (162,130,78).
- **14 `table_side`:** one draw, m = 216+(r&31). Start from tile 5's colour rule, then apply overrides in order:
  1. py ≤ 2 → (104,82,50).
  2. Saw: 2 ≤ px ≤ 6 and 5 ≤ py ≤ 9, except (py == 9 and px even) → (150,150,150).
  3. Hammer handle: px ∈ {10,11}, 7 ≤ py ≤ 13 → (78,60,36).
  4. Hammer head: 8 ≤ px ≤ 13, 5 ≤ py ≤ 6 → (110,110,110).
- **Cracks 16–25:** first 256 draws `v[i] = r & 255` (i = py*16 + px). Stage k pixel = `v < 13*(k+1)` → (32,32,32,255), else (0,0,0,0).
- **Item icons 32–42:** drawn pixels are opaque, unshaded colours; all others transparent.
  - Palette:
    - handle `h` (137,103,39), `H` (84,62,22);
    - wood `m` (160,122,66), `M` (96,72,36);
    - stone `m` (150,150,150), `M` (86,86,86).
  - **Stick (32):** `h` where px+py == 15, 3 ≤ px ≤ 12; `H` where px+py == 16, 4 ≤ px ≤ 13.
  - **Tool handle (pickaxe, axe, shovel):** `h` where px+py == 15, 2 ≤ px ≤ 9; `H` where px+py == 16, 3 ≤ px ≤ 10. The head is drawn over it.
  - **Pickaxe (33, 37):** `dx = px−2.5`, `dy = 13.5−py`, `r = √(dx²+dy²)`, `c = (dx+dy)/(1.41421356·r)`. Head where 9.5 ≤ r < 12.0 and c ≥ 0.80: `m` if r < 11.0, else `M`.
  - **Axe (34, 38):** blade where 5 ≤ px ≤ 10, 1 ≤ py ≤ 6 and 8 ≤ px+py ≤ 14: `M` if px == 5, py == 1 or px+py == 8; else `m`.
  - **Shovel (35, 39):** `m` where |px−11|+|py−4| ≤ 2; `M` where it equals 3.
  - **Sword (36, 40):**
    - blade `m` where px+py == 15, 6 ≤ px ≤ 13; `M` where px+py ∈ {14,16}, 6 ≤ px ≤ 13, plus (14,1);
    - guard `H` where px−py == −5, 3 ≤ px ≤ 7;
    - grip `h` where px+py == 15, 2 ≤ px ≤ 4; `H` at (1,14).
  - **Apple (41):** d = distance from (7.5,8.5):
    - d ≤ 4.6 → (196,24,24); 4.6 < d ≤ 5.5 → (128,12,12);
    - highlight (240,120,120) at (5,6), (5,7), (6,6);
    - stem (90,60,20) at (8,2), (8,3); leaf (60,140,40) at (9,2), (10,2), (10,1).
  - **Porkchop (42):** `v = ((px−7.5)/6.5)² + ((py−8)/4.5)²`, for v ≤ 1:
    - v > 0.72 → (180,80,80);
    - 0.45 < v ≤ 0.72 and px ≤ 7 → (250,215,205);
    - else (232,138,138).
- **HUD 48–53:** 9×9 at the tile's top-left; the rest transparent.
  - Heart bitmap (rows top→bottom):
    ```
    .KKK.KKK.
    KrrrKrrrK
    KrwrrrrrK
    KrrrrrrrK
    .KrrrrrK.
    ..KrrrK..
    ...KrK...
    ....K....
    .........
    ```
    - K (24,24,24), r (214,28,28), w (255,150,150).
    - Empty: r and w → (52,20,20).
    - Half: columns 0–4 use full colours, 5–8 empty colours.
  - Food bitmap:
    ```
    ....KKK..
    ...KmmmK.
    ..KmmwmmK
    ..KmmmmmK
    ...KmmmK.
    ..KbKKK..
    .KbK.....
    KbbK.....
    .KK......
    ```
    - K (40,26,14), m (186,108,48), w (226,168,108), b (236,232,220).
    - Empty: m and w → (58,40,28), b → (96,96,96).
    - Half: columns 0–4 full.
- **Mob tiles 64–69:** one draw per pixel, m = 200+(r&55), except pig tiles, which use 220+(r&35).
  - 64 zombie skin: (74,128,64).
  - 65 zombie face: skin, with eyes (24,24,24) at px ∈ {4,5,10,11}, py ∈ {6,7}, and mouth (40,72,34) at py == 11, 5 ≤ px ≤ 10.
  - 66 shirt: (40,160,170).
  - 67 pants: (60,60,150).
  - 68 pig skin: (240,160,160).
  - 69 pig face: skin, with eyes (24,24,24) at px ∈ {3,4,11,12}, py ∈ {5,6}; snout (218,128,138) at 5 ≤ px ≤ 10, 8 ≤ py ≤ 11; nostrils (110,50,60) at px ∈ {6,9}, py ∈ {9,10}.
- **Proof:**
  1. A scratch harness dumps the atlas to RGBA. Convert it with `magick -size 256x256 -depth 8 rgba:… -scale 300% atlas.png`.
  2. Read the PNG, and describe tiles 13–69 and the font rows in the final answer.
  3. Confirm tiles 0–12 are byte-identical to `git show HEAD:src/texgen.asm`'s output, by comparing dumps.

**W3 Storage — `saves.asm`, `settings.asm`, `test_saves.asm`, `test_settings.asm`**

- **`saves_init(envp, override)`:**
  1. Choose the base:
     - `override` if non-zero;
     - else `$XDG_DATA_HOME/assemblycraft` if set and non-empty;
     - else `$HOME/.local/share/assemblycraft` if HOME is non-empty;
     - else `./assemblycraft-data`.
     - The environment is scanned from `envp` (NULL-terminated array of `KEY=VALUE`). `envp = 0` means none.
  2. Create every prefix of `base` and of `base/worlds` with `SYS_MKDIR` mode 0755, ignoring `-EEXIST`.
  3. Fill `data_dir`, `worlds_dir` and `settings_path` (`base/settings.cfg`).
  4. Return 0, or the first other error.
- **`saves_scan`:**
  1. Open `worlds_dir` with `O_RDONLY|O_DIRECTORY` and loop `SYS_GETDENTS64` into a 32 KiB buffer.
  2. Keep names ending in `.acw` with length ≤ 63, up to 64 entries.
  3. For each, set `mtime` with `file_stat_mtime`.
  4. `file_read(path, buf, 1024)`:
     - magic `ACRAFT02` → name (an empty name falls back to the file stem), mode, seed, `valid = 1`;
     - `ACRAFT01` → name = stem, mode 2, seed from offset 8, `valid = 1`;
     - otherwise `valid = 0`, name = stem.
  5. Insertion-sort by `mtime`, newest first.
- **`saves_name_to_file`:**
  1. Trim leading and trailing spaces.
  2. Map each char: `[A-Za-z0-9_-]` is kept, space → `_`, others are dropped.
  3. Keep at most 40 chars; an empty result → `World`.
- **`saves_new_file_path(name, out)`:** `worlds_dir/<stem>.acw`. If it exists (`file_stat_mtime ≥ 0`), try `<stem>-2.acw` … `<stem>-99.acw`. Return −1 if all exist.
- **`saves_delete`** → `file_unlink`.
- **`saves_rename`:**
  - Only for valid v2 entries; otherwise return −1.
  - Write the new name zero-padded into a 33-byte buffer, then `file_patch(path, 20, buf, 33)`.
- **`fmt_ago`:** `d = time_now − mtime`:
  - d < 60 → `just now`;
  - < 3600 → `N min ago`;
  - < 86400 → `N h ago`;
  - else `N days ago` (`1 day ago` when N = 1).
- **Settings file format:** lines of `key=value\n`, written in this order: `fov sensitivity render_distance volume difficulty invert_mouse vsync fullscreen gui_scale key_forward key_back key_left key_right key_jump key_sneak key_sprint key_inventory key_fly`.
- **`settings_load(path)`:**
  1. `file_read` with cap 4096. A missing file → defaults, return 1.
  2. Parse each line `key=value`. `value` must parse as `parse_u32`; numbers are clamped into their range; a key value outside 32–348 → that key's default.
  3. An unknown key, a missing `=` or a bad number marks the result "2" but continues.
  4. Return 0, or 2 if anything was bad.
- **`settings_save`:** build the text in a 1024-byte buffer, then `file_write_atomic`.
- **`settings_apply(win)`:**
  1. `glfwSwapInterval(vsync)`.
  2. If `fullscreen` and not currently fullscreen:
     1. Save the window position and size (`glfwGetWindowPos` and `glfwGetWindowSize`).
     2. Get `m = glfwGetPrimaryMonitor()` and `vm = glfwGetVideoMode(m)` (ints width@0, height@4, refreshRate@20).
     3. Call `glfwSetWindowMonitor(win, m, 0, 0, vm.width, vm.height, vm.refresh)`; the 7th argument goes at `[rsp]`.
  3. If not `fullscreen` and currently fullscreen: `glfwSetWindowMonitor(win, 0, saved x, y, w, h, GLFW_DONT_CARE)`.
  4. Track the current state in `fs_active`.
- **Tests:**
  - **`[saves_sanitize_name]`:** `"My World!"` → `My_World`; `"!!!"` → `World`; `"a/b..c"` → `abc`; `"  x  "` → `x`; 50 × `a` → 40 × `a`.
  - **`[saves_scan_rename_delete]`:**
    1. `saves_init(0, "/tmp/assemblycraft-selftest-data")`, then unlink `Alpha.acw` and `Beta.acw` there.
    2. Write two worlds with `world_save`: names "Alpha" (mode 0) and "Beta" (mode 1).
    3. Scan → 2 entries with those names and modes.
    4. Rename Alpha → "Gamma"; rescan → Gamma present, Alpha absent.
    5. Delete Beta's entry; rescan → 1.
    6. Unlink what is left.
  - **`[settings_roundtrip]`:**
    1. Defaults; set fov 95 and jump 74.
    2. Save to `/tmp/assemblycraft-selftest.cfg`, then reset the defaults.
    3. Load → 0, fov 95, jump 74, others at their defaults.
    4. Unlink the file and reset the defaults.
  - **`[settings_clamps_bad_values]`:**
    1. Write `"fov=500\nbogus line\nkey_jump=5\nvolume=50\n"`.
    2. Load → 2, fov 110, jump 32, volume 50.
    3. Unlink the file and reset the defaults.

**W4 Audio — `audio.asm`, `sfx.asm`**

- **`audio_init`:**
  - `pa_simple_new(0, "AssemblyCraft", 1 /*PA_STREAM_PLAYBACK*/, 0, "Game sounds", &ss, 0, &attr, &err)`.
  - `ss = {format 3 /*S16LE*/ dd, rate 44100 dd, channels 1 db}` (12 bytes).
  - `attr = {maxlength 0xFFFFFFFF, tlength 5292 (60 ms), prebuf 0xFFFFFFFF, minreq 0xFFFFFFFF, fragsize 0xFFFFFFFF}`.
  - NULL → `audio_enabled = 0` and return 0. Otherwise call `sfx_build` and return 1.
- **`audio_update(dt)`:**
  - Add `dt*44100` plus a fractional carry to `frames`; cap at 2048 and drop the excess.
  - Mix: 16 voices `{ptr, remaining, vol 0–256}`. Each output sample = `Σ s*vol >> 8`, then `× (settings.volume*256/100) >> 8`, clamped to ±32767.
  - `pa_simple_write` `frames*2` bytes (it may block briefly; that is the throttle).
- **`audio_play(snd, vol)`:**
  - `vol` is clamped to 0–1 → `int(vol*256)`.
  - Use a free voice, else steal the one with the least `remaining`.
- **`audio_play_at`:**
  - `d` = distance from `player_eye`; `vol *= max(0, 1 − d/16)`.
  - Skip when the result is 0.
- **`audio_shutdown`:** `pa_simple_free`.
- **`sfx_build`:** render layers into `sfx_pool` (`resw 262144`), one sound after another by id. `sfx_table[id] = {offset, length}`, length = `ceil(max(start+dur)*44100)`.
  - For each layer at sample n, `t = n/44100 − start`; skip if t < 0 or t ≥ dur.
  - **Wave:**
    - Frequency `f = f0 + (f1−f0)*t/dur + vdepth*tri(vrate*t)`, where `tri(x) = 1 − 4|frac(x) − 0.5|`.
    - The phase advances `f/44100`.
    - Square = ±1 on `frac(phase) < 0.5`; saw = `2*frac(phase) − 1`; noise = `(int16)(rng >> 16)/32768` with the sfx-private xorshift seeded 0xC0FFEE11.
  - **Filter:** per layer, one-pole `y += lp*(x − y)`; with `hp = 1` the output is `x − y`. `lp = 1.0` means unfiltered.
  - **Envelope:**
    - exp: `env *= k` with `k = 2^(−1/(half*44100))`, computed once with x87 `f2xm1`+1;
    - linear: `1 − t/dur`;
    - then `× min(1, t/attack)` when attack > 0.
  - Sum the layers `× amp`, `× 28000`, and clamp.
- **Layers** (f in Hz, times in s):

  |id|layers (wave f0→f1, lp, hp, env/half, attack, start, dur, amp, vdepth@vrate)|
  |---|---|
  |CLICK|square 1200→1200, lp 1, lin, dur .03, amp .25|
  |DIG_STONE|noise lp .5, exp .04, dur .20, amp .5|
  |DIG_WOOD|noise lp .18, exp .05, dur .20, amp .5 · square 180→160 lp .3, exp .05, dur .20, amp .15|
  |DIG_SOFT|noise lp .08, exp .05, dur .18, amp .6|
  |DIG_GLASS|noise lp .3 hp, exp .08, dur .35, amp .35 · square 2400 lp 1, exp .06, dur .30, amp .06 · square 3150 lp 1, exp .05, start .03, dur .30, amp .05|
  |STEP_STONE|noise lp .5, exp .02, dur .08, amp .3|
  |STEP_WOOD|noise lp .18, exp .025, dur .08, amp .3 · square 160 lp .3, exp .02, dur .08, amp .08|
  |STEP_SOFT|noise lp .08, exp .025, dur .08, amp .35|
  |HURT|square 600→300 lp .5, lin, dur .25, amp .35|
  |EAT|noise lp .3, exp .03, dur .12, amp .35|
  |BURP|square 120→90 lp .1, lin, dur .30, amp .5|
  |ZOMBIE_SAY|saw 90→80 lp .15, lin, attack .1, dur .80, amp .5, vib 10@5|
  |ZOMBIE_HURT|saw 140→90 lp .2, lin, dur .30, amp .5|
  |PIG_SAY|square 330→310 lp .25, lin, dur .12, amp .35 · square 280→260 lp .25, lin, start .17, dur .12, amp .35|
  |PIG_HURT|square 520→380 lp .3, lin, dur .25, amp .4|
  |TOOL_BREAK|noise lp .3 hp, exp .05, dur .25, amp .4 · square 1800→1200 lp 1, exp .05, dur .20, amp .08|
  |POP|square 400→900 lp .4, lin, dur .06, amp .3|

- **Proof:**
  1. A scratch harness calls `sfx_build` and writes each sound as a mono 44.1 kHz WAV to `/tmp/ac-sfx/<id>.wav`.
  2. `ffmpeg -i X -af volumedetect -f null -` for each shows `max_volume` between −12 and −0.1 dB, and the durations match the table.
  3. A live harness in `omabox up --audio` plays CLICK five times. `omabox run -- pactl list sink-inputs` shows `application.name = "AssemblyCraft"`.

**W5 Survival & sky — `survival.asm`, `sky.asm`, `test_survival.asm`**

- **`survival_reset`:** health 20, food 20, saturation 5.0, everything else 0.
- **`survival_damage(n, cause)`:**
  - Return 0 if `game_mode == MODE_CREATIVE`, `dead`, or `invuln > 0`.
  - Otherwise: `health = max(0, health − n)`, `invuln = 30`, `hurt_flash = 20`, `exhaustion += 0.1`, `audio_play(SND_HURT, 1.0)`.
  - `health == 0` → `dead = 1`, `death_cause = cause`.
  - Return 1.
- **`survival_land(d)`:** if d > 3 → `survival_damage(ceil(d − 3), CAUSE_FALL)`. If d ≥ 1, also play the step sound of the block under the feet at 0.6.
- **`survival_step(input, dist, jumped)`:** in this order:
  1. **Exhaustion:** `exhaustion += dist * (input.sprint ? 0.1 : 0.01)`, plus 0.05 if jumped (0.2 if jumped and sprinting).
  2. **Peaceful** (`settings.difficulty == 0`): `exhaustion = 0`; every 60 steps `health += 1` up to 20, using `regen_timer`; skip to step 6.
  3. **Drain:** while exhaustion ≥ 4: `exhaustion −= 4`; if saturation > 0 → `saturation = max(0, saturation − 1)`, else `food = max(0, food − 1)`.
  4. **Regen:** if food ≥ 18 and health < 20 → `regen_timer++`; at 240 → `health++`, `exhaustion += 3.0`, timer 0. Otherwise timer 0.
  5. **Starvation:** if food == 0 → `starve_timer++`; at 240 → timer 0, floor = {easy 10, normal 1, hard 0}[difficulty]; if health > floor → `survival_damage(1, CAUSE_STARVE)`. Otherwise timer 0.
  6. **Suffocation:** if the head cell `(floor x, floor(y+1.62), floor z)` is solid and opaque → `suffocate_timer++`; every 30 → `survival_damage(1, CAUSE_SUFFOCATE)`. Otherwise timer 0.
  7. `invuln` and `hurt_flash` decrement toward 0.
- **`survival_eat_step(rmb_held)`:**
  - With held = `inv_held()`: if `rmb_held`, `item_food[held.id] > 0` and `food < 20`:
    - `eat_timer++`; every 15 steps play `SND_EAT` (0.6).
    - At 96: `food = min(20, food + item_food)`, `saturation = min(food, saturation + item_saturation)`, `inv_consume_held(1)`, play `SND_BURP` (0.7), `eat_timer = 0`, return 1.
  - Otherwise `eat_timer = 0`, return 0.
- **`survival_can_sprint`:** `game_mode == MODE_CREATIVE` or food > 6.
- **`sky.asm`:** p = (time mod 72000)/72000.
  - **Brightness:**
    - p < 0.45 → 1.0;
    - < 0.55 → 1 − (p − 0.45)/0.10·0.75;
    - < 0.95 → 0.25;
    - else 0.25 + (p − 0.95)/0.05·0.75.
  - **Colour:** night (0.02,0.03,0.08) + (day (0.62,0.80,1.0) − night)·(b − 0.25)/0.75.
  - `sky_angle` = p·360. `sky_is_night` = b < 0.5.
- **Tests:** each sets `game_mode = 0`, `settings.difficulty = 2` and `survival_reset`.
  - **`[fall_damage]`:** land 5.0 → 18; `invuln = 0`, land 3.0 → 18; `invuln = 0`, land 3.5 → 17.
  - **`[exhaustion_drains]`:**
    1. `survival_exhaust(8.5)`, then 1 step with a zero INPUT and dist 0 → exhaustion 0.5 (±1e-4), saturation 3.0, food 20.
    2. Saturation 0, `exhaust(8.0)`, 1 step → food 18.
  - **`[regen_when_fed]`:** health 10, 240 steps → 11.
  - **`[damage_invulnerability]`:**
    1. Damage 4 → returns 1, health 16.
    2. Damage 4 again → returns 0, health 16.
    3. 30 steps, then damage 4 → 12.
    4. `game_mode = 1`, damage → returns 0.
  - **`[starvation_floor]`:**
    1. food 0, saturation 0, health 3, 1200 steps → 1.
    2. Difficulty 3, health 2, 480 steps → health 0, `dead = 1`, cause 3.
  - **`[sky_day_cycle]`:** brightness 0 → 1.0, 36000 → 0.625, 54000 → 0.25, 70200 → 0.625, 72000 → 1.0; `is_night(54000) = 1`, `is_night(6000) = 0`.

**W6 Mobs — `mobs.asm`, `test_mobs.asm`**

- **Dimensions:**
  - Zombie: `body_init(half_w 0.3, height 1.8, speed 2.6)`, health 20.
  - Pig: `body_init(0.45, 0.9, 1.6)`, health 10.
- **`mob_spawn`** takes the first free slot and sets `ai_timer = 0` and yaw = `rng%360`.
- **`mobs_step()`** runs once per fixed step. For each live mob:
  1. **AI** writes `.input` and yaw:
     - **Zombie targeting:** when `game_mode == survival`, difficulty > 0, `!surv.dead` and the horizontal distance² to the player < 576:
       - yaw = `atan2_deg(dx, −dz)` wrapped to [0,360), `fwd = 1`, `jump = blocked && on_ground`.
       - Attack: if `cooldown == 0` and the distance between body centres (y+0.9 for both) < 1.7 → `survival_damage({0,2,3,4}[difficulty], CAUSE_ZOMBIE)`.
       - If that applied: knock the player back with `kb = unit(player − zombie).xz * 6.0` and `vy = 5.0` if on ground; `cooldown = 60`.
     - **Pig with `panic > 0`:** `speed = 3.2`, `fwd = 1`, `panic−−`; at 0, `speed = 1.6`.
     - **Otherwise wander:** when `ai_timer−− ≤ 0`: `ai_timer = 60 + rng%180`; with `rng&1`, `fwd = 1` and `yaw = rng%360`, else `fwd = 0`. `jump = blocked && on_ground && fwd`.
  2. `body_step(&mob.body, &mob.input)`, then `walk += horizontal distance moved × 180`.
  3. Decrement `hurt` and `cooldown`.
  4. Ambient sound with `rng%600 == 0`: ZOMBIE_SAY or PIG_SAY at 0.7 (`audio_play_at`).
  5. **Zombie burning:** `sky_brightness(game_time) ≥ 0.8` and `world_top_y(floor x, floor z) < floor(y + 1.8)` → every 20 steps (`ai` counter `game_time % 20 == 0`) health −= 2 without knockback. At ≤ 0, remove.
  6. **Despawn:** remove zombies whose horizontal distance² to the player > 9216. When `settings.difficulty == 0`, remove every zombie.
- **Spawning:**
  - **Zombies:** every 60 steps (`game_time % 60 == 0`), when survival, difficulty > 0, `sky_is_night` and zombie count < 8.
    1. Angle = `rng%360`, dist = `24 + rng%17`, `x = floor(px + sin·dist)`, `z = floor(pz − cos·dist)`.
    2. Require 1 ≤ x, z ≤ 254, `ty = world_top_y`, `ty+1 ≤ 62`, and the top block ∈ {GRASS, DIRT, SAND, STONE, COBBLE}.
    3. Spawn at `(x+0.5, ty+1, z+0.5)`.
  - **Pigs:** every 1800 steps when `!night`, pig count < 10, dist `24 + rng%25`, and the top block == GRASS.
  - Total mobs ≤ 32.
- **`mobs_populate`:** up to 200 tries at `x = 128 + rng%97 − 48` (same for z) with top block GRASS → pig, stopping at 10 pigs.
- **`mobs_raycast`:** slab test of the ray against each mob's AABB `[x±half_w] × [y, y+height] × [z±half_w]`. Return the nearest index with t ≤ max, and t in xmm0.
- **`mob_hurt(idx, dmg, dirx, dirz)`:**
  - If `hurt > 0` → 0.
  - `health −= dmg`, `hurt = 10`, `kb = (dirx, dirz)*6.0`, `vy = 4.0` if on ground.
  - Sound: ZOMBIE_HURT or PIG_HURT at 1.0.
  - A pig gets `panic = 180` and yaw = away from the player.
  - At health ≤ 0: a pig → `inv_add(PORKCHOP, 1 + rng%3)`; the mob is removed.
  - Return 1.
- **`mobs_intersect_block`:** any live mob's box strictly overlaps the block.
- **`mobs_save`:** compact the live mobs into `hdr.mobs`, set `mob_count`.
- **`mobs_load`:** clear, then respawn each record whose type ∈ {1,2} and whose x, z ∈ [0,256) and y ∈ [0,64), restoring health (clamped 1 to the type max).
- **Tests:** each does `rng_seed(1234)`, `mobs_clear`, `game_mode = 0`, `settings.difficulty = 2`, `game_time = 6000`, `survival_reset`, and the floor fixture (STONE at y = 10, x and z 0–31) unless stated.
  - **`[mob_raycast_hits]`:** zombie at (10.5,11,10.5); ray from (10.5,11.9,5.5), dir (0,0,1), max 10 → index of the zombie, 4.69 < t < 4.71. Max 4 → −1.
  - **`[mob_hurt_pig_drops_food]`:** `inv_clear`, pig at (5.5,11,5.5); `mob_hurt(idx,6,…)` → 1; set `hurt = 0`; hurt again → pig removed (type 0) and `inv` slot 0 = PORKCHOP with count 1–3.
  - **`[zombie_attacks_player]`:**
    1. `body_init(&player, 0.3, 1.8, 4.317)` at (16.5,11,16.5); zombie at (17.5,11,16.5).
    2. One `mobs_step` → health 17.
    3. 10 more steps → still 17.
  - **`[mob_spawn_rules]`:**
    1. GRASS at y = 10 over the whole 256×256 (direct `blocks` writes, then `world_mark_all_dirty`).
    2. Player at (128.5,11,128.5); `game_time = 40000`.
    3. Run 600 `mobs_step`s while doing `game_time++` → 1 ≤ zombie count ≤ 8.
    4. `mobs_clear`, difficulty 0, 600 more steps → 0 zombies.

**W7 UI toolkit — `ui.asm`**

- **`ui_init`:**
  - For each glyph 32–126: OR its 8 rows into a mask. `left` = lowest set bit and `width` = highest − lowest + 1.
  - An empty mask (space) → width 3, no quad.
  - The advance is `(width + 1)·scale`.
- **`ui_begin(fb_w, fb_h)`:**
  1. Scale = `settings.gui_scale` or auto `clamp(min(fb_w/320, fb_h/240), 1, 4)`. Set `ui_w = fb_w/scale`, `ui_h = fb_h/scale`, `ui_mx = mouse_px/scale`, `ui_my = mouse_py/scale`.
  2. GL state:
     - viewport, `glOrtho(0, ui_w, ui_h, 0, −1, 1)` as doubles, identity modelview;
     - disable depth, cull and fog;
     - `glActiveTexture(TEXTURE1)` + disable `TEXTURE_2D`, then back to `TEXTURE0`;
     - bind the atlas `tex_id` (extern from render.asm);
     - blend SRC_ALPHA/ONE_MINUS_SRC_ALPHA on, alpha test OFF. Translucent rects would fail `GL_GREATER 0.5`; fully transparent glyph texels blend to nothing.
- **Drawing primitives:**
  - Rects and frames are untextured (`glDisable TEXTURE_2D` around them), with `glColor4ub` from the packed RGBA. `ui_frame` is a 1-unit outline. `ui_panel` = rect `RGBA(0,0,0,140)`.
  - **Text:**
    - A char outside 32–126 → `?`.
    - Each glyph quad has texcoords `u0 = (gx+left)*16`, `u1 = (gx+left+width)*16`, `v0 = gy*16`, `v1 = (gy+8)*16` (1/16-px units; the texture matrix is the 1/4096 one).
    - A shadow first at (+scale, +scale) in `rgb/4`, same alpha.
- **`ui_button(label, x, y, w, enabled)`** (height 20):
  - Hover = enabled and the mouse is inside.
  - Background: `RGBA(255,255,255, enabled ? (hover ? 77 : 38) : 16)`; on hover, also a frame `RGBA(255,255,255,128)`.
  - The label is centred at y+6: white, or `RGBA(128,128,128,255)` when disabled.
  - Clicked = hover and `ui_input.lmb_pressed`, with `audio_play(SND_CLICK, 0.6)`.
- **`ui_slider(def, x, y, w)`:**
  - Background as a button. The knob is an 8×20 rect `RGBA(255,255,255,170)` at `x + (v−min)*(w−8)/(max−min)`.
  - The label `prefix + value + suffix` is centred.
  - Drag: `lmb_pressed` inside → `ui_active = def`. While `ui_active == def` and `lmb_held`: `value = clamp(min + round((mx − x − 4)·(max−min)/(w−8)), min, max)`. On release, `ui_active = 0`.
  - Return 1 when the value changed.
- **`ui_textfield(tf, x, y, w)`** (height 20):
  - Background `RGBA(0,0,0,192)` with a frame: white when focused, `RGBA(160,160,160,255)` otherwise.
  - Text at x+4, y+6. When focused, a caret `_` blinks at `int(glfwGetTime()*2)&1`.
  - `lmb_pressed` inside → `ui_focus = tf`; `lmb_pressed` outside while focused → `ui_focus = 0`.
  - When focused: append `typed` chars while `len < max`, apply `backspace` deletions, return 1 if `ui_input.enter`.
- **`ui_slot(stack, x, y, show_count)`:** an 18×18 cell.
  - Background `RGBA(0,0,0,90)`, icon 16×16 at +1.
  - Count when > 1 and `show_count`: right-aligned, ending at x+17, y+10, white.
  - Durability bar when the item is a tool with dmg > 0: background 14×2 black at (x+2, y+14), foreground width `14·(dur−dmg)/dur`, colour `RGBA(255·dmg/dur, 255 − that, 0, 255)`.
  - Hover → `RGBA(255,255,255,96)` over the 16×16. Return hover.
- **`ui_item_icon(id, x, y, size)`:** the full tile `item_icon[id]`, with uv inset 1 unit as the mesher does.
- **`ui_icon9(tile, x, y)`:** a 9×9 quad, uv `col*256..col*256+144`, `row*256..+144`.
- **`ui_tooltip(s)`:** a panel at `(mx+12, my−12)`, padded 3, containing the text.
- **Proof:** a scratch harness window (throwaway `main` + stubbed `ui_input`, linked with the Wave-0 atlas) draws each widget once. Take an omabox screenshot and describe it.

### Wave 1 merge (integrator)

1. Copy each worker's owned files into `src/`.
2. Register the 20 Wave 1 tests in `selftest.asm`, in this order: items, survival, sky, saves, settings, mobs.
3. `make && make test` → `selftest: 38 passed, 0 failed`.
4. Check the W2 atlas PNG and the W7 widget shot yourself before accepting.
5. Commit `0.2 wave 1: items, art, storage, audio, survival, mobs, ui`.

### Wave 2 — screens, rendering, integration (W8–W11 in one batch, with prompts as in Wave 1 pointing at their own Wave 2 section; the integrator works on its own files concurrently)

**W8 Menus — `menus.asm`.** Coordinates are GUI units; `cx = ui_w/2`. Every screen handles `ui_input.escape` as "back", as listed.

- **Title:**
  - "ASSEMBLYCRAFT" at scale 4 (scale 3 if wider than `ui_w − 20`), centred at `y = ui_h/4 − 16`.
  - "x86-64 assembly edition" grey (`RGBA(160,160,160,255)`) at `ui_h/4 + 20`.
  - Buttons 200 wide at `x = cx − 100`, y = `ui_h/2`, +24, +48:
    - "Singleplayer" → `saves_scan`, `app_selected = −1`, `ST_WORLDS`;
    - "Settings..." → `app_settings_parent = ST_TITLE`, `ST_SETTINGS`;
    - "Quit Game" → `app_request_quit`.
  - "AssemblyCraft 0.2" grey at (2, `ui_h − 10`). Escape does nothing.
- **Worlds:**
  - "Select World" centred at y 12. If `app_message_timer > 0`, show `app_message` in red `RGBA(255,85,85,255)` centred at y 22.
  - **List** at x `cx−150`, w 300, y 32 to `ui_h−64`. Rows are 36 high, the first one visible is `scroll` (the wheel changes it, clamped).
    - Row line 1: name at (x+4, y+4), white.
    - Row line 2 at (x+4, y+16), grey: `<Survival|Creative|Creative (old format)> - seed <n> - <fmt_ago>`. An invalid entry instead shows `(unreadable)` in red.
    - The selected row gets background `RGBA(255,255,255,38)` and a white frame. A click selects. A double-click on a valid row → `app_play_world`.
    - Empty list → "No worlds yet" centred grey.
  - **Buttons:**
    - "Play Selected World" (`cx−155`, `ui_h−52`, 150), enabled for a valid selection only → `app_play_world(app_selected)`.
    - "Create New World" (`cx+5`, `ui_h−52`, 150) → `ST_CREATE`.
    - "Rename" (`cx−155`, `ui_h−28`, 72), enabled for a valid v2 entry only (`mode` 0 or 1) → `ST_RENAME`.
    - "Delete" (`cx−79`, `ui_h−28`, 72), enabled for any selection → `ST_DELETE`.
    - "Cancel" (`cx+5`, `ui_h−28`, 150) → TITLE. Escape → TITLE.
- **Create:**
  - On entry (`app_entered == 1`; clear it), reset the fields: name "New World", seed "", mode Survival, focus on name. The Rename screen (prefill) and the Controls screen (`capturing = −1`) use the same `app_entered` check.
  - "Create New World" centred at y 12.
  - Labels and fields:
    - "World Name" at (`cx−100`, 44) grey; field at (`cx−100`, 56, 200), max 32.
    - "Seed for the world generator" at (`cx−100`, 88); seed field at (`cx−100`, 100, 200), max 32.
    - "Leave blank for a random seed" grey at (`cx−100`, 124).
  - Button (`cx−100`, 140, 200): "Game Mode: Survival" or "Game Mode: Creative" toggles. Below it, centred at 166 in grey: "Gather resources, craft tools, stay alive" or "Unlimited blocks, flying, no damage".
  - Buttons "Create New World" (`cx−155`, `ui_h−28`, 150; enabled iff the trimmed name is non-empty) and "Cancel" (`cx+5`, …) → WORLDS. Enter in the name field = Create.
  - Seed:
    - blank → `rdtsc` low 32;
    - `parse_u32` ok → that value;
    - else `fnv1a(text)`.
  - Then `app_create_world(name, mode, seed)`. Escape → WORLDS.
- **Rename:** "Rename World", a field prefilled with the entry's name (on entry), "Rename" (enabled iff non-empty) → `saves_rename`, then `saves_scan` → WORLDS; "Cancel" → WORLDS.
- **Delete:**
  - "Are you sure you want to delete this world?" at `ui_h/2 − 40`.
  - `'<name>' will be lost forever! (A long time!)` grey at `ui_h/2 − 24`.
  - "Delete" (`cx−155`, `ui_h/2 + 10`) → `saves_delete`, `saves_scan`, `app_selected = −1` → WORLDS. "Cancel" (`cx+5`) → WORLDS.
- **Pause:**
  - Full-screen `RGBA(0,0,0,128)`. "Game Menu" at `ui_h/4`.
  - Buttons 200 wide at `ui_h/4` + 24, +48, +72:
    - "Back to Game" → PLAYING;
    - "Settings..." → `app_settings_parent = ST_PAUSED`, SETTINGS;
    - "Save and Quit to Title" → `app_quit_to_title`.
  - Escape → PLAYING.
- **Death:**
  - Full-screen `RGBA(150,0,0,115)`. "You died!" scale 2 centred at `ui_h/4`.
  - The cause centred at `ui_h/4 + 24`: fall "You fell from a high place", zombie "You were slain by a Zombie", starve "You starved to death", suffocate "You suffocated in a wall".
  - "Respawn" (`ui_h/4 + 48`) → `app_respawn(0)`. "Title Screen" (+72) → `app_respawn(1)`.
- **`screen_loading(text)`:** full-screen `RGBA(16,16,16,255)` with the text centred at `ui_h/2`.
- **Proof:** a scratch build with stubs for `app_*`/`saves_*`. A throwaway main renders each screen in omabox; take a shot of each.

**W9 Options — `options.asm`**

- **Settings:**
  - "Settings" at y 12. Left column x = `cx−155`, right x = `cx+5`, w 150, rows at `y = 36 + 24·row`:
    - row 0: FOV slider ("FOV: ", "") | Sensitivity ("Sensitivity: ", "%");
    - row 1: Render Distance ("Render Distance: ", " chunks") | Volume ("Volume: ", "%");
    - row 2: "Difficulty: Peaceful/Easy/Normal/Hard" (click cycles) | "GUI Scale: Auto/1/2/3/4" (cycles);
    - row 3: "Invert Mouse: ON/OFF" | "VSync: ON/OFF";
    - row 4: "Fullscreen: ON/OFF" | "Controls..." → CONTROLS.
  - "Done" (`cx−100`, `ui_h−28`, 200) and Escape → `settings_save(settings_path)`, then `app_goto(app_settings_parent)`.
  - VSync and Fullscreen changes call `settings_apply(app_window)` immediately. Everything else is read live by its consumer.
- **Controls:**
  - "Controls" at y 10. `pitch = min(24, (ui_h − 60)/9)`. For row i at `y = 28 + i·pitch`:
    - label at (`cx−150`, y+6) white: "Walk Forward", "Walk Backward", "Strafe Left", "Strafe Right", "Jump / Fly Up", "Sneak / Fly Down", "Sprint", "Inventory", "Toggle Fly (Creative)";
    - key button at (`cx+10`, y, 120).
  - The button label is `key_name`, `> ??? <` while capturing that row, and red `RGBA(255,85,85,255)` when another binding uses the same code (drawn with `ui_text` over a button whose label is empty).
  - Capture: clicking a key button sets `capturing = i`. While capturing, `ui_input.key_pressed`:
    - Esc → cancel;
    - any other code ≥ 32 → assign it and stop capturing.
  - Escape when not capturing → SETTINGS.
  - "Reset Keys" (`cx−155`, `ui_h−28`, 150) → `settings_reset_keys`. "Done" (`cx+5`, …) → SETTINGS.
- **`key_name(key, out)`:**
  1. If `glfwGetKeyName(key, 0)` is non-NULL, copy it, upper-casing a leading a–z and replacing bytes ≥ 128 with `?`.
  2. Else use the table: 32 Space, 257 Enter, 258 Tab, 259 Backspace, 260 Insert, 261 Delete, 262 Right, 263 Left, 264 Down, 265 Up, 266 Page Up, 267 Page Down, 268 Home, 269 End, 280 Caps Lock, 290–314 "F<n−289>", 320–329 "Num <n−320>", 335 Num Enter, 340 Left Shift, 341 Left Ctrl, 342 Left Alt, 343 Left Super, 344 Right Shift, 345 Right Ctrl, 346 Right Alt, 347 Right Super, 348 Menu.
  3. Else "Key <n>".
- **Proof:** as W8.

**W10 Inventory screens — `invscreen.asm`**

- **Panel:** 176×166 at `px = (ui_w−176)/2`, `py = (ui_h−166)/2`, over a full-screen `RGBA(0,0,0,100)`.
- **Survival inventory** (`game_mode == 0`, `craft_size = 2`; set by the app on open):
  - "Crafting" at (px+88, py+6).
  - Grid cells 0, 1, 3, 4 at (px+98+18c, py+18+18r).
  - "->" at (px+138, py+32). Result at (px+154, py+28).
  - "Inventory" at (px+8, py+72). Slots 9–35 at (px+8+18c, py+84+18r). Hotbar 0–8 at (px+8+18c, py+142).
- **Crafting table** (`craft_size = 3`):
  - "Crafting" at (px+28, py+6). Grid cells r·3+c at (px+30+18c, py+17+18r).
  - "->" at (px+92, py+39). Result at (px+124, py+35).
  - The inventory is laid out as above.
- **Creative** (`game_mode == 1`):
  - "Creative" at (px+8, py+6). A palette of 23 cells, ids [1..12, 32..42] in that order, at (px+8+18c, py+18+18r) for 3 rows of 9.
  - "Hotbar" at (px+8, py+130). Hotbar slots at (px+8+18c, py+142).
  - Palette click: if the cursor is non-empty → clear the cursor; else cursor = `{id, left ? item_max_stack[id] : 1, 0}`.
  - Hotbar clicks use `inv_click`.
- **Interaction:**
  - For every slot, `ui_slot`, with `show_count = (game_mode == 0)`.
  - A left or right press on a hovered slot → `inv_click(ref, button, ui_input.shift)`.
  - Hover with an empty cursor → `ui_tooltip(item_names[id])`.
  - The cursor stack is drawn last at (mx−8, my−8) as a 16×16 icon plus its count.
  - E (`frame_input.inventory`) or Escape:
    - survival → `inv_close_screen`;
    - creative → clear the cursor, `craft_size = 2`;
    - then `app_goto(ST_PLAYING)`.
- **Proof:** as W8. A scratch fixture fills `inv` with sample stacks, including a damaged tool.

**W11 World rendering and HUD — `render.asm`, `mobrender.asm`, `hud.asm`**

- **`render_init`** (in addition to 0.1):
  - Create `white_tex`, a 1×1 RGBA (255,255,255,255).
  - Configure texture unit 1 once:
    - `glActiveTexture(TEXTURE1)`, bind `white_tex`;
    - `TEXTURE_ENV_MODE = COMBINE`, `COMBINE_RGB = MODULATE`, `SOURCE0_RGB = PREVIOUS`, `SOURCE1_RGB = CONSTANT`, `OPERAND0/1_RGB = SRC_COLOR`;
    - `COMBINE_ALPHA = REPLACE`, `SOURCE0_ALPHA = PREVIOUS`, `OPERAND0_ALPHA = SRC_ALPHA`;
    - `glActiveTexture(TEXTURE0)`.
  - Export `tex_id`.
- **`render_world(cam, w, h)`:**
  1. Viewport. Get `b = sky_brightness(game_time)` and the colour from `sky_color`; clear to that colour.
  2. Projection:
     - `hh = 0.05·tan(fov/2)`, with `sincos_deg(settings.fov/2)` → sin/cos;
     - `glFrustum(−hh·a, hh·a, −hh, hh, 0.05, 300)`.
  3. **Sun and moon:**
     1. Modelview identity, rotate pitch, rotate yaw, then `glRotatef(sky_angle, 0, 0, 1)`.
     2. Depth test, fog and texturing off on both units.
     3. Sun quad at x = 100, y and z ∈ [−12, 12], colour (1.0, 0.93, 0.55).
     4. Moon quad at x = −100, half-size 8, colour (0.85, 0.88, 0.95).
  4. **World:**
     - Modelview as 0.1 using `cam` (eye = cam pos + 1.62).
     - Fog colour = sky colour; fog start = `render_dist·16·0.6`, end = `render_dist·16` (`glFogf`).
     - Enable unit 1 texturing with `TEXTURE_ENV_COLOR = (b, b, b, 1)`.
     - Draw the chunks as in 0.1, but with the horizontal distance limit `(render_dist·16 + 8)²`.
     - Then disable the three client states, `glBindBuffer(ARRAY_BUFFER, 0)`, and call `mobs_render()` with cull face on. Mob box faces are wound counter-clockwise seen from outside.
  5. **Crack overlay:** if `game_break_progress > 0` and `game_has_target`:
     - stage = `min(9, floor(progress·10))`;
     - draw the 6 faces of the box `[b − 0.002, b + 1.002]` with tile `16 + stage`, white, alpha test on, blend off.
  6. **Outline:** disable unit 1 texturing, then draw the outline as 0.1.
  7. Leave unit 1 disabled and the active unit at TEXTURE0.
- **`mobs_render`:**
  - Per mob: `glPushMatrix`, `glTranslatef(x, y, z)`, `glRotatef(−yaw, 0, 1, 0)`. Model space: front = −Z.
  - **Box drawing:** each box gets 6 faces, each a full tile (uv inset 1 unit, v0 at the top edge).
    - Shade per face: +Y 1.0, −Y 0.5, ±X 0.6, ±Z 0.8; × (1, 0.5, 0.5) while `hurt > 0`.
    - The front face (−Z) of a head uses the face tile; every other face uses the part tile.
  - **Limb swing:** `sw = sin(walk)·30°`. Swing a limb about X at its pivot with `glPushMatrix`, `glTranslatef(pivot)`, `glRotatef(±sw, 1, 0, 0)`, `glTranslatef(−pivot)`.
  - **Zombie:**
    - legs x [−0.25,0] and [0,0.25], y [0,0.75], z ±0.125, pants, pivot y 0.75, opposite swings;
    - body x ±0.25, y [0.75,1.5], z ±0.125, shirt;
    - arms x [−0.5,−0.25] and [0.25,0.5], y [1.25,1.5], z [−0.75,0], skin, swing ±sw/4;
    - head x ±0.25, y [1.5,2.0], z ±0.25, face tile 65.
  - **Pig:**
    - body x ±0.3125, y [0.375,0.875], z ±0.5;
    - head x ±0.25, y [0.5,1.0], z [−0.875,−0.5], face tile 69;
    - legs x [−0.3125,−0.0625] and [0.0625,0.3125], z [−0.4375,−0.1875] and [0.1875,0.4375], y [0,0.375], pivot y 0.375; front-left with back-right swing +sw, the other pair −sw.
- **`hud_draw`** (GUI units; `x0 = ui_w/2 − 91`, `y0 = ui_h − 22`):
  1. **Hurt flash:** `surv.hurt_flash > 0` (survival) → full-screen `RGBA(255,0,0, hurt_flash·90/20)`.
  2. **Crosshair** (`app_state == ST_PLAYING` only): `glBlendFunc(ONE_MINUS_DST_COLOR, ZERO)`, untextured white rects `(cx−5, cy, 11, 1)`, `(cx, cy−5, 1, 5)` and `(cx, cy+1, 1, 5)`. Restore the blend.
  3. **Hotbar:**
     - background `ui_rect(x0, y0, 182, 22, RGBA(0,0,0,115))`;
     - per slot i, the icon at (x0+3+20i, y0+3);
     - in survival, the count right-aligned ending at x0+3+20i+17, y0+12, plus the durability bar as `ui_slot`'s at (x0+3+20i, y0+3);
     - the selection frame `ui_frame(x0+20·inv_sel, y0, 22, 22, white)`.
  4. **Survival bars:**
     - hearts i = 0–9 at (x0+8i, y0−10): full if health ≥ 2i+2, half if == 2i+1, else empty;
     - food i = 0–9 at (x0+182−9−8i, y0−10), with the same rule on `food`.
  5. **Held name:** when `inv_sel` or the held id changes, `name_timer = 2.0`. While it is > 0, decrement it by `hud_dt` (a float global owned by `hud.asm`; the app writes the frame dt into it before `hud_draw`) and draw `item_names[held]` centred at y = `y0−24` (survival) or `y0−12` (creative), alpha `min(1, timer/0.5)·255`.
  6. **Debug** (`app_show_debug`): lines at (2, 2+10i), each over a `RGBA(0,0,0,96)` background:
     1. `AssemblyCraft 0.2  <app_fps> fps`
     2. `XYZ: <x 2dp> / <y 2dp> / <z 2dp>`
     3. `Facing: yaw <int> pitch <int>`
     4. `Target: <name> at <bx> <by> <bz>` or `Target: none`
     5. `Mode: Survival|Creative  Day <time/72000+1> <hh>:<mm>`, with `hh = (6 + (time mod 72000)·24/72000) mod 24` and mm from the remainder
     6. `Mobs: <z> zombies, <p> pigs`
     7. `Light: <int(b·100)>%`
     8. In survival: `Health <h>/20  Food <f>/20  Sat <s 1dp>`
- **Proof:** a scratch throwaway main loads a generated world, places a zombie and a pig in view at night time 40000, sets a break progress of 0.5, and renders a frame in omabox. Take a shot.

**Integrator (concurrently with W8–W11) — `input.asm`, `game.asm`, `app.asm`, `main.asm`, `test_game.asm`, `selftest.asm`**

- **`input.asm` (rewrite).**
  - `input_init(win)`: scroll, key and char callbacks, sticky keys and buttons, `input_set_captured(win, 0)`.
  - **Callbacks** write pending fields:
    - `key_cb(win, key, sc, action, mods)`:
      - PRESS → `pending_key = key`;
      - BACKSPACE PRESS/REPEAT → `pending_bs++`;
      - ENTER or KP_ENTER PRESS → `pending_enter = 1`;
      - ESC PRESS → `pending_esc = 1`.
    - `char_cb(win, cp)`: append 32–126 while the length < 32.
  - **`input_poll(win)`:**
    1. Zero both structs; `slot = −1`; move the pending fields into `ui_input` and clear them.
    2. Cursor: `mouse_px/py = cursor · fb_size/window_size`.
    3. Mouse buttons are polled (sticky) with edges. `shift` = left or right shift held.
    4. `double_click`: an lmb press within 0.4 s (`glfwGetTime`) and ±4 px of the previous press.
    5. `.inventory`, `.debug` (F3) and `.fullscreen` (F11) edges are computed in every state.
    6. **Only when `input_captured`:**
       - movement from the bindings;
       - look deltas from the baseline (as 0.1);
       - mouse buttons into `frame_input`, with recapture suppression until both buttons are released;
       - 1–9 edges, `toggle_fly` from `BIND_FLY`;
       - the scroll accumulator → `frame_input.scroll`.
    7. Not captured → the scroll goes to `ui_input.scroll`.
  - **`input_set_captured(win, on)`:** set the cursor mode, reset the baseline, set suppression when on, store `input_captured`.
- **`game.asm` (rewrite).**
  - **`game_new(seed, mode, name)`:**
    1. `world_generate(seed)`.
    2. Header: mode, `time = NEW_WORLD_TIME`, name (`str_copy`, max 32), spawn (128, `world_top_y(128,128)+1`, 128).
    3. `game_mode = mode`, `game_time = NEW_WORLD_TIME`.
    4. `player_spawn`, `survival_reset`.
    5. `inv_clear`, then `inv_set_creative_default` if creative; `inv_sel = 0`.
    6. `mobs_clear`, `mobs_populate`.
    7. Reset the break, place and accumulator state.
  - **`game_load(path)`:**
    1. `world_load` → return a nonzero code.
    2. Copy the header into the state.
    3. The player body comes from `.player`, then is fixed up: `half_w 0.3`, `height 1.8`, `speed 4.317`; velocity, kb, fall, blocked and `on_ground` = 0; flying forced to 0 in survival.
    4. health and food are clamped 0–20. health 0 → `survival_reset` + `player_spawn`.
    5. `sel` is clamped 0–8.
    6. Inventory slots with an invalid id (`item_max_stack == 0`) or count 0 or > max are cleared.
    7. mode is clamped 0–1; `game_time = .time`; `mobs_load`.
  - **`game_save(path)`:**
    1. Write the state into the header: player body, survival fields, sel, inventory, `time = game_time`, mode.
    2. `mobs_save`.
    3. `world_save`.
  - **`game_respawn`:** `survival_reset`, `player_spawn`.
  - **`game_frame(dt)`:**
    1. **Slot and scroll:** as 0.1, on `inv_sel`.
    2. **Fly:** `toggle_fly` only in creative.
    3. **Look:** `player_look(dx·s, dy·s·(invert ? −1 : 1))`, s = `settings.sensitivity/100`.
    4. **Fixed steps** (max 5, as 0.1). Each step:
       1. Copy `frame_input.move`; clear sprint if `!survival_can_sprint()`.
       2. Record `on_ground`, x, z; `landed = body_step(&player, &copy)`.
       3. `d = |Δxz|`, `jumped = was_on_ground && copy.jump && !flying`.
       4. Survival: `landed > 0` → `survival_land(landed)`; `survival_step(&copy, d, jumped)`; `survival_eat_step(frame_input.rmb_held)`.
       5. **Footsteps:** not flying, on ground, `d > 0` → `step_dist += d`; at ≥ 1.6, play `block_step_sound[block below feet]` at 0.35 and reset to 0.
       6. `mobs_step()`; `game_time++`.
    5. **Targeting:**
       - Reach is 4.5 in survival, 5.0 in creative. `game_has_target = raycast(eye, fwd, &game_target, reach)`.
       - `mob = mobs_raycast(eye, fwd, 3.5)` → t. A mob is targeted iff `mob ≥ 0` and `raycast(eye, fwd, scratch, t) == 0`.
    6. **LMB with a mob targeted** (`lmb_pressed`):
       - `mob_hurt(mob, item_attack_damage(held.id), fwd.x, fwd.z normalised)`.
       - If it applied: survival → `inv_damage_held(sword ? 1 : 2)` when the held item is a tool; `survival_exhaust(0.1)`.
       - Skip block breaking this frame.
    7. **LMB block, creative:** as 0.1 (instant, 0.25 s repeat, not BEDROCK). Play `block_dig_sound` at 1.0.
    8. **LMB block, survival:**
       - Only while `lmb_held` with a target whose hardness ≥ 0. A target change → `progress = 0`.
       - If `break_cooldown > 0` → `cooldown −= dt`. Else `progress += dt / item_break_time(id, held.id)`; every 0.25 s play `block_step_sound` at 0.4.
       - At progress ≥ 1:
         1. `drop = item_harvest_drop` (LEAVES: APPLE when `rng%16 == 0`).
         2. `world_set(b, AIR)`, dig sound at 1.0.
         3. `inv_add(drop, 1)` if drop ≠ 0.
         4. If the held item is a tool: `inv_damage_held(sword ? 2 : 1)`.
         5. `survival_exhaust(0.005)`, `progress = 0`, `cooldown = 0.25`.
       - Without `lmb_held`: `progress = 0`.
       - Mirror `progress` into `game_break_progress`.
    9. **RMB** (`rmb_pressed`, or held with the 0.25 s repeat as 0.1):
       - Target is CRAFTING_TABLE, `!frame_input.move.down`, and this is a press → `game_open_table = 1`, and stop.
       - Survival with held food → nothing; eating runs per step.
       - Held id is a block (1–12) and the placement checks pass (0.1 checks, plus `!mobs_intersect_block`):
         - `world_set(p, id)`, dig sound at 0.8;
         - survival → `inv_consume_held(1)`.
    10. **MMB** with a target:
        - creative → held = `{block id, 1, 0}`;
        - survival → `s = inv_find_hotbar(id)`; if s ≥ 0, `inv_sel = s`.
- **`app.asm`.**
  - **`app_run(play_path)`:** main loop. `frame dt = clamp(now − last, 0, 0.25)`.
    1. `glfwPollEvents`.
    2. If `glfwWindowShouldClose`: when in a world, `game_save`; a failure prints `assemblycraft: failed to save world to <path>\n` and the exit code becomes 1. Break.
    3. `input_poll`. The F11 edge toggles `settings.fullscreen`, then `settings_apply` and `settings_save`.
    4. **State logic:**
       - **PLAYING:**
         - not focused (`glfwGetWindowAttrib(FOCUSED) == 0`), or `ui_input.escape` → `game_save` + PAUSED;
         - `frame_input.inventory` → `craft_size = 2`, INVENTORY;
         - else `game_frame(dt)`; then `game_open_table` → clear it, `craft_size = 3`, CRAFTING;
         - `.debug` toggles `app_show_debug`;
         - `surv.dead` → DEATH, and `game_save`;
         - autosave every 120 s of PLAYING, INVENTORY or CRAFTING time.
       - **INVENTORY / CRAFTING:** `game_frame(dt)` keeps running (frame_input movement is zero while not captured). If dead → `inv_close_screen` → DEATH.
       - **PAUSED and DEATH:** nothing simulates.
       - **Not in a world:** the panorama yaw += 3·dt.
    5. `audio_update(dt)`, `render_update_chunks`, `app_message_timer = max(0, app_message_timer − dt)`, `hud_dt = dt`.
    6. If the framebuffer is > 0:
       - `render_world(in_world ? &player : &panorama_cam, w, h)`;
       - `ui_begin`;
       - `hud_draw` in PLAYING, PAUSED, INVENTORY and CRAFTING;
       - then the state's screen function.
    7. `glfwSwapBuffers`.
    8. Every 0.5 s: `app_fps`, and the window title — in a world `AssemblyCraft | <fps> FPS | <x> <y> <z> | <held name or "Empty">` + ` | fly` when flying; otherwise `AssemblyCraft`.
  - **`app_goto(s)`:**
    - capture is on iff `s == PLAYING`;
    - leaving INVENTORY or CRAFTING for PLAYING is the screen's job;
    - set `app_state`, and set `app_entered = 1` if `s` differs from the previous state.
  - **`app_show_loading(text)`:** framebuffer size, viewport, clear, `ui_begin`, `screen_loading(text)`, swap.
  - **`app_play_world(idx)`:**
    1. `app_show_loading("Loading world...")`.
    2. Path from `saves_entry_path`; `game_load`.
    3. On failure: `app_message = "Could not load '<name>'"`, `timer = 5`, stay in WORLDS.
    4. On success: `in_world = 1`, remember the path, a legacy entry (mode 2) gets the header name set from the entry name, then PLAYING.
  - **`app_create_world(name, mode, seed)`:**
    1. `app_show_loading("Generating world...")`.
    2. `saves_new_file_path`; −1 → message "Too many worlds named like that", then WORLDS.
    3. `game_new`, `game_save`; a failure → message "Could not save the new world", then WORLDS.
    4. Then as play.
  - **`app_quit_to_title`:**
    1. `app_show_loading("Saving world...")`, `game_save`; a failure prints the 0.1 stderr message.
    2. `in_world = 0`, `load_panorama`, `saves_scan`, TITLE.
  - **`load_panorama`:**
    - `world_generate(PANORAMA_SEED)`, `mobs_clear`, `game_time = NEW_WORLD_TIME`, `game_has_target = 0`, `game_break_progress = 0`;
    - `panorama_cam`: `body_init`, position (128.5, `top(128,128)+12`, 128.5), pitch 20.
  - **`app_respawn(to_title)`:** `game_respawn`, then PLAYING or `app_quit_to_title`.
  - **Start:** `play_path` → PLAYING (world already loaded by main); else `load_panorama` → TITLE.
- **`main.asm`.**
  - **Arguments:**
    - `--help`, `--selftest`, `--data-dir DIR`, `--play NAME`, `--creative`, `--seed N`.
    - `--creative`/`--seed` without `--play`, an unknown argument, or a missing or bad value → usage on stderr, exit 2.
  - **Usage text (verbatim):**
    ```
    usage: assemblycraft [--data-dir DIR] [--play NAME [--creative] [--seed N]] [--selftest] [--help]
      --data-dir DIR  where worlds and settings live (default: $XDG_DATA_HOME/assemblycraft
                      or ~/.local/share/assemblycraft)
      --play NAME     skip the menus and play world NAME, creating it if it does not exist
      --creative      with --play, create the new world in Creative mode (default: Survival)
      --seed N        with --play, seed for a newly created world (default: random)
      --selftest      run internal tests and exit
    controls (rebindable in Settings > Controls): WASD move, Space jump / fly up,
      Left Shift sneak / fly down, Left Ctrl sprint, E inventory, F toggle fly (Creative),
      mouse look, LMB break / attack, RMB place / use / eat, MMB pick block,
      1-9 / wheel select, Esc pause, F3 debug info, F11 fullscreen
    ```
  - **Game mode** (`envp` is main's 3rd argument, `rdx`):
    1. `rng_seed(rdtsc)`.
    2. `saves_init(envp, data_dir)`; failure → `assemblycraft: cannot create data directory <dir>\n`, exit 1.
    3. `settings_load(settings_path)`; a return of 2 → `assemblycraft: ignored invalid lines in <settings_path>\n`, then continue.
    4. If `--play`: path = `worlds_dir/` + `saves_name_to_file(NAME)` + `.acw`.
       - It exists → `game_load` (2 → `assemblycraft: <path> is not a valid AssemblyCraft world\n` exit 1; 3 → `assemblycraft: cannot read <path>\n` exit 1).
       - Otherwise `game_new(seed or rdtsc, creative ? 1 : 0, NAME)` + `game_save` (failure → save message, exit 1).
    5. Window setup as 0.1: `glfwInit`, hints, `glfwCreateWindow`, make current, `render_init`, `ui_init`, `input_init`.
    6. `audio_init`; 0 → `assemblycraft: sound disabled (cannot connect to PulseAudio)\n` and continue.
    7. `settings_apply(win)`.
    8. `r = app_run(play ? path : 0)`, `audio_shutdown`, destroy the window, terminate, return r.
- **`test_game.asm`** — `[game_save_load_roundtrip]`:
  1. `rng_seed(7)`, `game_new(42, 0, "Round Trip")`.
  2. Set `surv.health = 13`, `food = 9`, `inv.slots[3] = {STONE_PICKAXE,1,7}`, `game_time = 12345`. Record `p = mob_count_type(MOB_PIG)`.
  3. `game_save("/tmp/assemblycraft-selftest-game.acw")` → 0.
  4. `game_new(1, 1, "x")`, then `game_load` → 0.
  5. Check health 13, food 9, slot 3 `{37,1,7}`, `game_time` 12345, `game_mode` 0, `mob_count_type(PIG) == p`, header name "Round Trip".
  6. Unlink the file.
- **Registry:** after W1–W11 and the integrator files merge, `selftest.asm` lists 39 tests: the 18 from Wave 0, the 20 from Wave 1 and 1 from Wave 2.

### Wave 3 — integrate, verify live, fix, commit

1. Merge the Wave 2 files, then `make` (no warnings) and `make test` → `selftest: 39 passed, 0 failed`.
2. Run every check under **Verification**. A failure inside a worker-owned file goes back to that worker (`write agent://<id>`) if it is still alive; otherwise the integrator fixes it directly. Re-run the failed check after each fix.
3. Commit `0.2: survival, menus, saves, settings, day/night, mobs, sound`.

## Critical files & anchors

- **`src/common.inc` structs.** `WORLDHDR` offsets are load-bearing for the save files and the verification's byte patches. `BODY`'s first 40 bytes keep 0.1's `PLAYER` offsets, so old movement code ports by renaming.
- **`src/world.asm` `.bss` order.** `world_header` (1024) must be immediately followed by `blocks`, because the v1 conversion and single-buffer I/O depend on it.
- **`src/player.asm` `move_axis`.** The leading-slab collision is only valid while the per-step displacement is < 1 block. Knockback (≤ 6 + 5.612 → 0.19 block/step) keeps this true, and the terminal-velocity clamp stays.
- **`src/render.asm` texture unit 1.** It must be disabled before any HUD or UI draw (`ui_begin` disables it), or the GUI gets darkened at night.
- **`src/input.asm` capture and suppression.** Clicking "Back to Game" must not also break a block. Suppression holds until both buttons are released.

## Verification

Run everything from the repo root. GUI steps follow **Conventions → omabox**; take a shot after each action and read it.

1. **Unit tests.** `make && make test` prints exactly these 39 `ok` lines and `selftest: 39 passed, 0 failed`, exit 0:
   - `world_bounds`, `world_set_marks_dirty`, `world_save_load`, `world_load_v1_converts`;
   - `worldgen_deterministic`, `worldgen_shape`;
   - five `mesh_*`;
   - three `raycast_*`;
   - three `physics_*`, `body_intersects_block`;
   - `inv_add_merges`, `inv_right_click_split`, `craft_planks_from_log`, `craft_tool_shapes`, `craft_shift_click_all`, `break_time_rules`;
   - `fall_damage`, `exhaustion_drains`, `regen_when_fed`, `damage_invulnerability`, `starvation_floor`, `sky_day_cycle`;
   - `saves_sanitize_name`, `saves_scan_rename_delete`, `settings_roundtrip`, `settings_clamps_bad_values`;
   - `mob_raycast_hits`, `mob_hurt_pig_drops_food`, `zombie_attacks_player`, `mob_spawn_rules`;
   - `game_save_load_roundtrip`.

   The build shows no exec-stack warning.
2. **CLI.**
   - `./build/assemblycraft --bogus; echo $?` → usage on stderr, `2`.
   - `--seed 5` alone → `2`.
   - `--help` → the new usage, `0`.
   - `mkdir -p /tmp/acv/worlds && printf garbage > /tmp/acv/worlds/Bad.acw && ./build/assemblycraft --data-dir /tmp/acv --play Bad; echo $?` → `assemblycraft: /tmp/acv/worlds/Bad.acw is not a valid AssemblyCraft world`, then `1`, and no window opens.
3. **Box setup.**
   - `omabox up --audio` (cwd `$HOME`), the US layout, copy the binary.
   - Launch `omabox run -d --wait -- /home/sbx/assemblycraft --data-dir /home/sbx/acd`.
4. **Title.** The shot shows the rotating panorama (two shots 1 s apart differ), "ASSEMBLYCRAFT", and the buttons Singleplayer / Settings... / Quit Game. The title bar reads `AssemblyCraft`.
5. **Create a survival world.**
   1. Click Singleplayer → "No worlds yet" → Create New World.
   2. Select the name field text with backspaces, type `Survival Test`, click the seed field, type `42`, leave the mode on Survival, click Create New World.
   3. In game: 10 hearts, 10 food icons, an empty hotbar, and a title like `AssemblyCraft | … FPS | 128 13 128 | Empty`.
   4. `F3` shows the debug overlay with `Mode: Survival  Day 1 07:…` and `Mobs: 0 zombies, N pigs` with N ≥ 1.
6. **Timed breaking and drops.** The spawn view targets the ground (pitch 30; seed 42 spawns on sand).
   1. Hold LMB: `pointer --window assemblycraft -- move <cx> <cy> down sleep 400ms`, then take a shot → the crack overlay is visible on the targeted sand block.
   2. `pointer --window assemblycraft -- sleep 1s up` → the block is gone and hotbar slot 1 shows the Sand icon.
   3. If a held button does not persist across two `pointer` calls (the block is untouched after step 2), use one `move <cx> <cy> down sleep 1500ms up` for the break instead. Prove the crack overlay with W11's harness shot, and say so in the report.
   4. `ls -la /home/sbx/acd/worlds` (via `omabox run`) shows `Survival_Test.acw` of 4195328 bytes.
7. **Crafting with patched inventory and fall height.**
   1. Esc → the Game Menu → "Save and Quit to Title".
   2. With a throwaway Python script on the host, patch `$(omabox -b default path --home)/acd/worlds/Survival_Test.acw` (little-endian):
      - offset 156 → bytes `06 04 00 00` (LOG ×4);
      - 160 → `04 0a 00 00` (COBBLE ×10);
      - 152 (sel) → int32 0;
      - player x (68), y (72) and z (76) → floats `spawn_x + 0.5`, `spawn_y + 20.0` and `spawn_z + 0.5`, with spawn_* being the int32s at 56, 60 and 64.
   3. Back in Singleplayer, the list row reads `Survival Test` / `Survival - seed 42 - just now`. Double-click it.
   4. The player falls 20 blocks, taking `ceil(20 − 3) = 17` damage. Health shows 1 full heart and 1 half heart, F3 shows `Health 3/20`, and the screen flashes red.
   5. Press `E` → the inventory with the 2×2 grid.
      1. Left-click the log stack (hotbar row), then right-click the top-left grid cell → the result shows Planks ×4. Left-click the hotbar log slot again to put the remaining logs back. Shift-click the result → Planks ×4 appear in the inventory, and the grid is empty.
      2. Put planks in all 4 cells → Crafting Table. Take it.
      3. Put 2 planks vertically → Sticks ×4.
      4. Close with `E` → the grid items return to the inventory (count check in the hotbar).
   6. Place the crafting table (select its slot, right-click the ground), then right-click it → the 3×3 screen.
   7. Craft a Stone Pickaxe (cobble in the top row, sticks below the middle) → the result is Stone Pickaxe. Take it to the hotbar.
   8. Close the screen. Place one Cobblestone ahead (select it, then right-click).
      1. Hold LMB on it with an empty hand selected for 2 s → it is still there (10 s needed by hand).
      2. Select the Stone Pickaxe and hold LMB → the block breaks in about 0.75 s, and the Cobblestone count goes up by 1.
      3. The pickaxe slot shows a durability bar.
8. **Night, zombies, combat.**
   1. Quit to title and patch `time` (offset 16) to 40000.
   2. Reopen → a dark world, a dark sky, the moon visible when looking around (or in the F3 `Light: 25%`).
   3. Within 60 s, F3 shows `Mobs: ≥1 zombies`.
   4. Let one approach: health drops by 3 per hit, with the hurt sound and red flash.
   5. If a zombie crosses the crosshair (shots show it in the centre), click LMB → the zombie tints red, is knocked back, and dies after enough hits. Mouse look is unavailable in the box, so if none crosses the crosshair within 120 s, report "combat by click not verified in the box" and rely on the `mob_hurt_pig_drops_food` and `zombie_attacks_player` tests.
9. **Death and respawn.**
   1. Quit to title. Patch health (offset 136) to 1, and the player position to `(spawn_x+0.5, spawn_y+10, spawn_z+0.5)` at offsets 68, 72 and 76. Open the world → it falls 10 blocks for 7 damage, and the death screen shows "You died!" / "You fell from a high place".
   2. Respawn → back at spawn with 10 hearts.
10. **Eating.** Patch slot 0 to APPLE ×3 (`29 03 00 00`), sel (152) to 0 and food (140) to 10. Hold RMB for 2 s (`pointer --window assemblycraft -- down right sleep 2s up right`) → the food bar shows 7 full icons (10 + 4 = 14), and slot 1 shows Apple ×2.
11. **Pigs.** In daylight, F3 shows `N pigs` with N ≥ 1. If a pig crosses the crosshair, hitting it until it dies adds Raw Porkchop to the inventory. Otherwise, report it like step 8.5.
12. **Sound.**
    - `omabox run -- pactl list sink-inputs` shows `application.name = "AssemblyCraft"`.
    - `omabox run -- sh -c 'ffmpeg -f pulse -i "$(pactl get-default-sink).monitor" -t 3 /tmp/s.wav'` while breaking blocks, then `ffmpeg -i /tmp/s.wav -af volumedetect -f null -` in the box → `max_volume` > −30 dB.
    - The same capture while idle on the title screen shows `max_volume` < −60 dB, or "-inf".
13. **Settings and controls.**
    1. Esc → Settings...: move FOV to 100 (shot shows a wider view after Done); set Difficulty to Peaceful (zombies vanish at night within a few steps, per F3).
    2. Controls...: click "Jump / Fly Up", press `j` → the button shows `J`. Done → Done.
    3. In game, `keys --window assemblycraft down:j -s 300ms up:j` → the Y in the title rises, then returns.
    4. `omabox run -- cat /home/sbx/acd/settings.cfg` contains `fov=100`, `difficulty=0`, `key_jump=74`.
    5. F11 → `omabox windows` reports 1920×1080 fullscreen; F11 again → windowed.
14. **Creative world.**
    1. From the title, create "Creative Test" with mode Creative → no hearts, the default hotbar (Stone…Bricks), `F` toggles fly (title `| fly`), and breaking is instant.
    2. `E` opens the palette: click Crafting Table, then a hotbar slot → it appears there.
15. **Save management.**
    1. Quit to title, then Singleplayer → two rows, newest first.
    2. Select "Creative Test" → Rename → `Renamed` → Rename → the list shows `Renamed`.
    3. Select "Renamed" → Delete → the confirmation screen → Delete → one row remains, and `ls /home/sbx/acd/worlds` lists only `Survival_Test.acw`.
16. **Legacy import.**
    1. Build 0.1 in a throwaway worktree: `git worktree add /tmp/ac01 5ff203e && make -C /tmp/ac01`.
       1. Copy `/tmp/ac01/build/assemblycraft` into the box home as `ac01`, using the cp+mv pattern.
       2. Run `omabox run -d --wait -- /home/sbx/ac01 --world /home/sbx/acd/worlds/Old.acw --seed 3`.
       3. Close it with the Lua dispatch.
       4. `git worktree remove /tmp/ac01`.
    2. The 0.2 list shows `Old` / `Creative (old format)`. Playing it loads in creative with the 0.1 hotbar. After quitting, the file is 4195328 bytes.
17. **Window close saves.** Close the window via the Lua dispatch while in a world → the process exits 0 and the world's mtime updates.
18. **Performance.** Record the FPS from the title in survival at render distance 8, and again at 16, with 5+ mobs in view.
19. **Mouse look.** Report it as not testable in the box; it needs a check on the real desktop.
20. Run `omabox down`.

## Assumptions & contingencies

- **No ground item entities.**
  - Drops, crafted items and porkchops go straight into the inventory.
  - When the inventory is full, the drop is lost.
  - On death the inventory is kept.
- **Mobs:**
  - Zombies spawn only in Survival worlds, at night, on the surface. There are no caves or light levels in this world generator.
  - Zombies die in daylight. Pigs are pre-placed (10) and respawn slowly in daylight.
- **Not included:** first-person held-item rendering, sneaking slow-down and edge protection, a furnace, ores, saplings, and dropping items (Q).
- **Saving:** F5 quick-save is removed. Saving happens on pause, every 120 s, on Save & Quit, on death and on window close.
- **Difficulty and pause:**
  - Difficulty is a global setting, not per world.
  - The game pauses when the window loses focus.
- **Old-format worlds:** a 0.1 world becomes playable by copying it into `worlds/`. It loads as Creative with its 0.1 hotbar. The old `--world PATH` flag is removed.
- **Contingency — audio:** if `pa_simple_write` blocks noticeably (FPS drops below 55 only with audio enabled), change `tlength` to 8820 (100 ms) and cap the frames per update at 1024.
- **Contingency — texture combiner:** if the combiner leaves the world unchanged at night in the box (`Light: 25%` but no darkening), check `glGetError` after the unit-1 setup. If `GL_COMBINE` is rejected, darken instead by multiplying the vertex colour array on upload: remesh all chunks whenever the brightness changes by ≥ 0.05, scaling `r,g,b` by b in `render_update_chunks`.
- **Contingency — focus loss:** if pausing on focus loss triggers spuriously in the box (pause menu right after launch), drop the focus check, and say so in the final report.
- **Contingency — fullscreen:** if `glfwSetWindowMonitor` fails in the box (geometry unchanged), report fullscreen as "not verifiable in the box" and keep the code.
