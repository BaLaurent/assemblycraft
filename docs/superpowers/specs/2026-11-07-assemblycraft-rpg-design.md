# AssemblyCraft 0.6 — RPG: classes, skill trees, magic, parry/dodge combat, dungeons, villages, quests, boss

## Context

AssemblyCraft (`/run/media/octopusman/Games/Experiences/assemblycraft`, branch `master`, HEAD `d2f3fcc`, `make test` = 69/69) is a Minecraft-like game written entirely in x86-64 NASM. The user wants it turned into a full RPG ("un putain de monde de RPG super stylé"). Their choices:

- **Classes:** 4 fixed classes (Warrior, Mage, Archer, Rogue), chosen when the character is created.
- **Progression:** each class has its own skill tree (3 branches) and 3 active abilities.
- **Magic:** a craftable staff fires a magic bolt with LMB at a mana cost. Class abilities are cast on 3 dedicated keys whatever is held, and a mana bar shows on the HUD.
- **Melee combat:**
  - RMB held with a melee weapon = guard. Frontal hits are reduced and cost stamina.
  - Guard raised just before impact = perfect parry: the attacker is stunned and the riposte crits.
  - A dodge key gives a roll with short invincibility.
  - Stamina bar, 3-hit combo, crit while falling.
  - Monsters visibly wind up their attacks.
- **Scope "tout d'un coup":** all of the above plus:
  - combat juice (floating damage numbers, enemy health bars, crits, hit-stop, elite monsters);
  - generated dungeons with loot and elites;
  - a multi-phase boss in a crypt;
  - villages with NPCs, a merchant and a quest chain.

Game UI text stays in English, like every existing string.

## Conventions (unchanged from 0.3–0.5)

- **Assembly:** `%include "common.inc"`, `default rel`, explicit sections, per-file `extern`/`global`. SysV ABI with rsp 16-aligned at calls; callee-saved rbx/rbp/r12–r15; scalar SSE only. The Makefile globs `src/*.asm`, so new files need no Makefile edit.
- **Rounding:** every "round(x)" in this plan is `cvtss2si` (round to nearest); "ceil" is `roundss` mode 10.
- **Tests:** `test_<name>() → eax` (0 = pass). A test starts with `call world_clear`, sets every global it relies on, and cleans up after itself: mobs, arrows, primed TNT, drops, inventory, containers region, `rpg_state`, combat state. Register each test in `src/selftest.asm` with `extern` + `TEST` + `TESTNAME`.
- **Workers:**
  - Each worker works in a scratch copy made from the working tree after the wave-0 commit:
    `rm -rf /tmp/ac-<name> && mkdir -p /tmp/ac-<name> && rsync -a --exclude build --exclude .git <repo>/ /tmp/ac-<name>/`.
  - Edit with absolute /tmp paths only. Never run git in the repo.
  - Put throwaway stubs for sibling symbols in `/tmp/ac-<name>/src/zz_stub.asm` (functions return 0 and do nothing; data symbols are zeroed with their declared size). Never copy stubs back.
  - When green, copy back only the files you own, after `diff` confirms the repo copy still equals your starting copy.
  - Report the `selftest.asm` registration lines, the `make test` tail and any deviations.
- **Git:** integrator only, one commit per wave.
- **Live checks:** in an omabox box. Run `omabox up --audio` from `$HOME`, install the binary with `H=$(omabox -b default path --home); cp build/assemblycraft "$H/.ac.new" && mv -f "$H/.ac.new" "$H/assemblycraft"`, and set the US layout with `omabox -b default lua 'hl.config({input={kb_layout="us", kb_variant=""}}); return "ok"'`.
  - World patching uses `/tmp/acpatch.py` (throwaway; recreate if missing). It patches the v3 header:
    - `slot=N:id:count[:dmg]` at 156+4N (`<BBH>`);
    - `armor=N:id`;
    - `sel`, `time`, `health`, `food`, `mobs`;
    - `mob=i:type:hp:dx:dy:dz` (20-byte records at 304, relative to the player);
    - `yaw`, `pitch`, `rise=DY`;
    - `block=x:y:z:id` (blocks at 16384 + ((y<<16)|(z<<8)|x));
    - `mode`.
  - Add two ops: `pos=x:y:z` (player floats at 68/72/76) and `rpg=class:level` (bytes at 960/961).
  - `/tmp/acarena.sh` builds a flat stone arena around the spawn.

## Contracts (wave 0 writes all of these first; every worker codes against them)

### `src/common.inc` — constants

- **Blocks:** `STONE_BRICK 23`, `MOSSY_STONE_BRICK 24`, `NUM_BLOCKS 25`. Item ids 25–31 stay unused.
- **Items** (`NUM_ITEMS 102`):
  - `STAFF 92`, `ARCHMAGE_STAFF 93`, `IRON_DAGGER 94`, `DIAMOND_DAGGER 95`, `SHADOW_FANG 96`, `KINGS_BLADE 97`, `CELESTIAL_BOW 98`, `HEALTH_POTION 99`, `MANA_POTION 100`, `GOLD_COIN 101`.
  - Icon tile = `TILE_ITEM0 + id − 43`, i.e. tiles 129–138.
- **Tools:** `TOOL_DAGGER 5`.
- **Tiles:**
  - `TILE_STONE_BRICK 59`, `TILE_MOSSY_BRICK 60`;
  - `TILE_ABILITY0 139` (tile = 139 + (class−1)·3 + slot, so 139–150);
  - `TILE_CLASS0 151` (151–154);
  - `TILE_STAT0 155` (155 + stat id, so 155–172);
  - `TILE_VILLAGER_SKIN 173`, `TILE_VILLAGER_FACE 174`, `TILE_MERCHANT_ROBE 175`, `TILE_ELDER_ROBE 176`, `TILE_BOSS_ROBE 177`, `TILE_BOSS_FACE 178`, `TILE_BOSS_CROWN 179`.
- **Classes:** `CLASS_NONE 0`, `CLASS_WARRIOR 1`, `CLASS_MAGE 2`, `CLASS_ARCHER 3`, `CLASS_ROGUE 4`, `NUM_CLASSES 4`, `MAX_LEVEL 30`, `NUM_NODES 12`.
- **Stats** (`NUM_STATS 18`): `STAT_MAX_HEALTH 0`, `STAT_MELEE_DMG 1`, `STAT_RANGED_DMG 2`, `STAT_SPELL_DMG 3`, `STAT_CRIT_CHANCE 4`, `STAT_CRIT_DMG 5`, `STAT_MAX_MANA 6`, `STAT_MANA_REGEN 7`, `STAT_MAX_STAMINA 8`, `STAT_STAMINA_REGEN 9`, `STAT_ARMOR_BONUS 10`, `STAT_MOVE_SPEED 11`, `STAT_BACKSTAB 12`, `STAT_PARRY_WINDOW 13`, `STAT_LIFESTEAL 14`, `STAT_COOLDOWN_RED 15`, `STAT_ARROW_SAVE 16`, `STAT_DODGE_COST 17`.
- **Resources:** `RES_STAMINA 0`, `RES_MANA 1`.
- **Mobs:** `MOB_MERCHANT 7`, `MOB_ELDER 8`, `MOB_BOSS 9`, `NUM_MOB_TYPES 9`, `MOB_ELITE_BIT 0x100` (MOBSAVE.type flag).
- **Causes:** `CAUSE_BOSS 9`.
- **Hit results** (`player_take_hit`): `HIT_NONE 0`, `HIT_TAKEN 1`, `HIT_BLOCKED 2`, `HIT_PARRIED 3`.
- **`combat_hit_flags` bits:** `HF_CRIT 1`, `HF_PLAYER 2`.
- **Projectiles:** `PROJ_BOLT 3`, `PROJ_FIREBALL 4`. `ARROWENT.flags` bits: `AF_CRIT 1`, `AF_EXPLOSIVE 2`, `AF_BIG 4`.
- **FX kinds:** `FX_SPARK 4`, `FX_MAGIC 5`, `FX_GOLD 6`.
- **Damage-number text ids:** `TXT_PARRY 0`, `TXT_BLOCKED 1`, `TXT_DODGED 2`, `TXT_STUNNED 3`.
- **Sites:** `SITE_VILLAGE 1`, `SITE_DUNGEON 2`, `SITE_CRYPT 3`, `MAX_SITES 9`, `NUM_DUNGEONS 6`, `DUNGEON_KILLS 8`.
- **Quests** (`NUM_QUESTS 8`): `Q_KILL 1`, `Q_BRING 2`, `Q_CLEAR 3`, `Q_ELITE 4`, `Q_BOSS 5`.
- **Trade:** `NUM_TRADES 8`.
- **Sounds** (`NUM_SOUNDS 53`): `SND_SWING 35`, `SND_PARRY 36`, `SND_BLOCK 37`, `SND_DODGE 38`, `SND_CRIT 39`, `SND_LEVELUP 40`, `SND_SPELL 41`, `SND_FIREBALL 42`, `SND_BLINK 43`, `SND_WARCRY 44`, `SND_WHIRL 45`, `SND_SMOKE 46`, `SND_COIN 47`, `SND_QUEST 48`, `SND_BOSS_ROAR 49`, `SND_SLAM 50`, `SND_VILLAGER 51`, `SND_DRINK 52`.
- **App states:** `ST_TRADE 15`, `ST_DIALOG 16`, `ST_CLASS 17`, `ST_SKILLS 18`.
- **Bindings** (`NUM_BINDINGS 15`): `BIND_DODGE 10`, `BIND_ABILITY1 11`, `BIND_ABILITY2 12`, `BIND_ABILITY3 13`, `BIND_SKILLS 14`.

### `src/common.inc` — structs

- **`FRAMEINPUT`:** append `.dodge` and `.skills` (`resd 1` each), then `.ability: resd 3`.
  - `.skills` is an edge reported in every state.
  - `.dodge` and `.ability[i]` are edges reported only while the cursor is captured.
- **`MOB`:** append these fields after `.input`. MOB is never saved directly.
  - `.windup` (steps left in a telegraphed attack, 0 = none)
  - `.stun` (steps)
  - `.elite` (0/1)
  - `.tagged` (steps; >0 = a player hit counts for XP)
  - `.origin` (0 none, 1..6 = dungeon index+1, 99 = crypt boss)
  - `.bar` (steps the health bar stays visible)
  - `.max_health`
  - `.timer_a`, `.timer_b` (boss timers)
  - `.home_x`, `.home_z` (floats, NPC home)

  All are `resd 1`.
- **`ARROWENT`:** append `.flags: resd 1` (56 bytes).
- **`struc RPGSAVE`** (64 bytes; `%if RPGSAVE_size != 64` → `%error`):

  |offset|field|meaning|
  |---|---|---|
  |0|`.class` db|class|
  |1|`.level` db|1..30|
  |2|`.quest` db|next quest index 0..8 (8 = chain finished)|
  |3|`.quest_state` db|0 not accepted, 1 accepted|
  |4|`.xp` dd|XP into the current level|
  |8|`.ranks` resb 12|rank of node b·4 + t|
  |20|`.cleared` db|bit d = dungeon d cleared|
  |21|`.flags` db|bit0 = boss defeated|
  |22|`.quest_progress` dw||
  |24|`.pad` resb 40||

  Points are derived, not stored: points = level − Σranks.
- **`WORLDHDR`:** replace `.pad: resb 64` (@960) with `.rpg: resb RPGSAVE_size`. Offsets and the file format do not change: every existing v3 save holds zeros there, which reads as class 0 and triggers class selection.
- **`struc SITE`** (44 bytes): `.kind .index .x .y .z .lo_x .lo_y .lo_z .hi_x .hi_y .hi_z`, all `resd 1`.
  - `y` = ground level (village) or floor y (dungeon, crypt).
  - lo/hi = inclusive trigger box.

### Tables and recipes (wave 0)

- **`blockdefs.asm`.** Ids 23 and 24 get: flags 3, tiles 59/59/59 and 60/60/60, hardness 1.5, tool PICKAXE, harvest level 1, drop self, `SND_DIG_STONE`/`SND_STEP_STONE`, `block_flammable` 0.
- **`itemdefs.asm`** (extend every table to 102 entries):
  - **Names:** 23 "Stone Bricks", 24 "Mossy Stone Bricks", then "Staff", "Archmage Staff", "Iron Dagger", "Diamond Dagger", "Shadow Fang", "King's Blade", "Celestial Bow", "Health Potion", "Mana Potion", "Gold Coin".
  - **Icons:** 23 → 59, 24 → 60, items via the `TILE_ITEM0` formula.
  - **max_stack:**
    - 23 and 24 → 64.
    - Weapons 92–98 → 1.
    - Potions → 16.
    - Coin → 64.
  - **item_tool:** daggers 94/95/96 → `TOOL_DAGGER`; `KINGS_BLADE` → `TOOL_SWORD` (tier `TIER_DIAMOND`); everything else 0.
  - **item_attack:** STAFF 2, ARCHMAGE_STAFF 3, IRON_DAGGER 5, DIAMOND_DAGGER 7, SHADOW_FANG 9, KINGS_BLADE 11; all others 1.
  - **item_durability:** STAFF 300, IRON_DAGGER 200, DIAMOND_DAGGER 1200; all others 0 (legendaries never wear).
  - **item_food, saturation, burn, smelt, armor:** 0 for the new items.
- **`items.asm` recipes** (append):

  |Output|Shape|
  |---|---|
  |STONE_BRICK ×4|2×2 `STONE STONE / STONE STONE`|
  |IRON_DAGGER|1×2 `IRON_INGOT / STICK`|
  |DIAMOND_DAGGER|1×2 `DIAMOND / STICK`|
  |STAFF|3×3 `0 0 GOLD_INGOT / 0 STICK 0 / STICK 0 0`|
  |HEALTH_POTION|1×2 `APPLE / GLASS`|
  |MANA_POTION|1×2 `GOLD_INGOT / GLASS`|

- **`invscreen.asm`:** the creative palette = blocks 1–17, 19, 20, 21, 23, 24, then items 32–101 (`PALETTE_N 92`). The existing `%if` size check and the `PAL_ROWS` formula stay.

### Bindings and settings (wave 0)

- **`settings.asm`:** `SETTINGS_IMAGE` keys get `67, 81, 71, 86, 75` appended (C, Q, G, V, K). New `SETENT` lines: `key_dodge`, `key_ability1`, `key_ability2`, `key_ability3`, `key_skills` (32..348, flag 1).
- **`input.asm`:**
  - `BIND_SKILLS` + `EDGE prev_skills` → `.skills` in the "every state" group.
  - `BIND_DODGE`, `BIND_ABILITY1..3` + their EDGEs → stored in the captured branch, like `toggle_fly`.
- **`options.asm`:** `bind_labels` gets "Dodge", "Ability 1", "Ability 2", "Ability 3", "Skill Tree". W9 changes the layout.

### Module API (who defines what)

|Module (owner)|Symbol|Contract|
|---|---|---|
|`rpg.asm` (W3)|`rpg_state`|`resb RPGSAVE_size`, live progression|
||`rpg_stats`|`resd NUM_STATS`, recomputed by `rpg_recompute`|
||`rpg_reset()`|zero `rpg_state`, set level 1, recompute|
||`rpg_set_class(edi class) → eax`|1 = set (class was 0, arg 1..4): level 1, xp 0, ranks 0, starting kit, recompute, `combat_refill`. 0 otherwise|
||`rpg_class() → eax`, `rpg_level() → eax`, `rpg_points() → eax`||
||`rpg_xp_need(edi level) → eax`|`20 + 10·level` for 1..29; 0 at 30|
||`rpg_add_xp(edi amount)`|no-op when class 0 or level 30; level-up loop (see Progression)|
||`rpg_rank(edi node) → eax`||
||`rpg_can_spend(edi node) → eax`|checks in this order, first failure wins: 5 no class; 1 no points; 2 max rank; 3 level below the tier requirement; 4 prerequisite (b, t−1) has rank 0. Returns 0 when spendable|
||`rpg_spend(edi node) → eax`|1 spent (rank++, recompute, `SND_CLICK`), else 0|
||`rpg_stat(edi stat) → eax`|`rpg_stats[stat]`|
||`rpg_recompute()`|stats = class base + Σ ranks·value, then caps; sets `surv_max_health`, clamps health; clamps `combat_mana`/`combat_stamina` to the maxima|
||`rpg_ability_unlocked(edi slot) → eax`|slot 0: class ≠ 0; slot 1: rank(node 5) ≥ 1; slot 2: rank(node 7) ≥ 1|
||`rpg_class_info(edi class) → rax`|`CLASSINFO*` = {name, line1, line2, line3: dq zstr}|
||`rpg_node_info(edi class, esi node) → rax`|`NODEINFO*` = {name dq, desc dq, kind db (0 stat, 1 ability), stat db, max db, pad db, value dd} (24 B)|
||`rpg_ability_info(edi class, esi slot) → rax`|`ABILINFO*` = {name dq, desc dq, resource dd, cost dd, cooldown_s dd, pad dd} (32 B)|
||`rpg_on_mob_killed(edi type, esi elite)`|XP table, then `quests_on_kill`|
||`rpg_on_block_mined(edi block)`|COAL_ORE 2, IRON_ORE 5, GOLD_ORE 8, DIAMOND_ORE 20 XP|
||`rpg_on_death()`|`xp = 0` (level and ranks kept)|
||`rpg_load(rdi header)`, `rpg_save(rdi header)`|copy `WORLDHDR.rpg` ↔ `rpg_state`; load validates (see Progression), then recompute|
|`quests.asm` (W3)|`quests_current() → rax`|`QUESTINFO*` or 0 when the chain is finished. QUESTINFO = {type, target, count, xp, coins, item, item_count, pad: dd; title, line1, line2: dq} (56 B)|
||`quests_progress() → eax`|BRING: min(`inv_count(item)`, count); else `quest_progress`|
||`quests_accept() → eax`, `quests_can_complete() → eax`, `quests_complete() → eax`||
||`quests_on_kill(edi type, esi elite)`, `quests_on_dungeon_cleared()`, `quests_on_boss_killed()`||
||`trade_offer(edi i) → rax`|`TRADEOFFER*` = {give, give_n, get, get_n: dd}|
||`trade_can(edi i) → eax`, `trade_execute(edi i) → eax`||
|`combat.asm` (W4)|globals|`combat_mana`, `combat_stamina` (float); `combat_guard_t` (dd, −1 = not guarding); `combat_guard_break_t`, `combat_dodge_t`, `combat_dodge_cd`, `combat_attack_cd`, `combat_combo`, `combat_combo_t`, `combat_riposte_t`, `combat_crit_next_t`, `combat_warcry_t`, `combat_blade_t`, `combat_stealth_t`, `combat_slow_t`, `combat_spend_t` (dd steps); `combat_hitstop` (float s); `combat_hit_flags` (db); `combat_life_carry` (float)|
||`combat_reset()`|timers 0, guard −1, refill|
||`combat_refill()`|mana = max, stamina = max|
||`combat_max_mana() → xmm0`, `combat_max_stamina() → xmm0`|from `rpg_stat`|
||`combat_step(edi sprinting)`|once per fixed step|
||`combat_spend(edi res, xmm0 amount) → eax`|1 = paid (creative: always 1, no deduction); stamina spending sets `combat_spend_t = 36`|
||`combat_set_guard(edi wanted)`|per frame|
||`combat_dodge(rdi INPUT*) → eax`||
||`combat_melee(edi mob, xmm0 dirx, xmm1 dirz) → eax`|1 = a strike landed|
||`player_take_hit(edi amount, esi cause, xmm0 src_x, xmm1 src_z) → eax`|`HIT_*`|
||`combat_speed_mult() → xmm0`||
||`combat_crit_roll(edi forced) → eax`|1 = crit (forced ≠ 0, or rng%100 < CRIT_CHANCE)|
||`combat_crit_mult() → xmm0`|1.5 + CRIT_DMG/100|
||`combat_heal(edi half_hearts)`|clamp to `surv_max_health`|
|`survival.asm` (W4)|`surv_max_health` (dd, default 20)|replaces every literal 20 for health|
|`mobs.asm` (W5)|`mob_strike`|renamed `mob_shot` (same contract: ignores the hurt window)|
||`mob_spawn_elite(edi type, xmm0..2) → eax`||
||`mob_spawn_npc(edi type, xmm0..2) → eax`|sets home = (x, z)|
||`mob_is_hostile(edi idx) → eax`||
|`abilities.asm` (W6)|`abilities_cd` (dd[3] steps), `abilities_cd_total` (dd[3]), `abilities_bolt_cd` (dd)||
||`abilities_reset()`, `abilities_step()`||
||`abilities_use(edi slot, rsi eye[3], rdx dir[3]) → eax`||
||`abilities_staff_bolt(rdi eye, rsi dir) → eax`||
|`arrows.asm` (W6)|`arrows_spawn(..., ecx kind, r8d flags)`|new 5th integer argument. Callers pass `r8d = 0`: game.asm bow, mobs.asm skeleton, guns.asm, test_combat.asm, test_guns.asm|
|`explode.asm` (W6)|`explode_magic(xmm0..2 c, xmm3 r, edi damage)`||
|`fx.asm` (W6)|`fx_burst(xmm0..2 pos, edi kind, esi count, xmm3 speed)`||
|`structures.asm` (W7)|`sites` (`MAX_SITES × SITE`), `site_count` (dd)||
||`structures_plan(edi seed)`, `structures_generate()`, `structures_spawn_npcs()`, `structures_reset()`, `structures_step()`||
||`structures_on_mob_killed(edi origin)`||
||`structures_nearest(edi kind, esi uncleared_only) → rax`|`SITE*` or 0|
|`worldgen.asm` (W7)|`hash32` (made global), `worldgen_height(edi x, esi z) → eax`, `worldgen_set_seed(edi seed)`||
|`project.asm` (W8)|`world_to_ui(rdi pos[3], rsi out int[2]) → eax`|1 = in front of the camera|
|`dmgnum.asm` (W8)|`dmgnum_clear()`, `dmgnum_spawn(xmm0..2, edi amount, esi flags)`, `dmgnum_text(xmm0..2, edi txt)`, `dmgnum_step()`, `dmgnum_draw()`||
|`hud.asm` (W8)|`hud_banner(rdi zstr, esi rgba)`|copies text (≤ 47 chars), shows 2.5 s|
|`ui.asm` (W8)|`ui_tile_icon(edi tile, esi x, edx y, ecx size, r8d rgba)`|`ui_item_icon` calls it with WHITE|
|`rpgscreens.asm` (W9)|`screen_class`, `screen_skills`, `screen_trade`, `screen_dialog`||
|`game.asm` (integrator)|`game_open_npc` (dd mob index)||

**Wave 0 also renames `mob_shot` → `mob_strike`** in its 3 locations (mobs.asm global and label, arrows.asm extern and call), so no worker touches another worker's file for it.

## Design data

### Classes, base stats and caps

Base stat arrays, in stat-id order:

|class|base stats|
|---|---|
|NONE|20,0,0,0,0,0,0,0,100,0,0,0,0,0,0,0,0,0|
|WARRIOR|24,10,0,0,5,0,0,0,120,0,0,0,0,0,0,0,0,0|
|MAGE|18,0,0,10,5,0,100,4,80,0,0,0,0,0,0,0,0,0|
|ARCHER|20,0,15,0,8,0,0,0,100,0,0,5,0,0,0,0,10,0|
|ROGUE|20,0,0,0,10,0,0,0,110,10,0,5,100,0,0,0,0,0|

- **Caps after summing:** CRIT_CHANCE 60, COOLDOWN_RED 40, DODGE_COST 60, ARROW_SAVE 60, MOVE_SPEED 40.
- **Class card lines:**
  - Warrior: "Heavy armor", "Charge and cleave", "Parry master".
  - Mage: "Fire and arcane", "Staff bolts", "Fragile, deadly".
  - Archer: "Bows and volleys", "Deadly at range", "Swift hunter".
  - Rogue: "Daggers, stealth", "Backstab x2", "Shadowstep".
- **Starting kits** (`inv_add`; overflow dropped at the player with `drops_spawn`). Every class gets COOKED_PORKCHOP ×4, plus:
  - Warrior: IRON_SWORD, and IRON_CHESTPLATE put into armor slot 1 if it is empty, else into the inventory.
  - Mage: STAFF, MANA_POTION ×2.
  - Archer: BOW, ARROW ×32.
  - Rogue: IRON_DAGGER, HEALTH_POTION ×2.

### Skill trees

- **Node layout:** node = b·4 + t (branch b 0..2, tier t 0..3). Node b,t needs rank ≥ 1 in node b,t−1, and level ≥ {1, 4, 9, 15}[t].
- **Points and ranks:** points = level − Σranks. Passive max rank 3; ability nodes (5 and 7) max rank 1.
- **Node description:** for a stat node, the text shown is `desc` followed by " per rank".

|class|branch 0|branch 1|branch 2|
|---|---|---|---|
|Warrior ("Blademaster", "Bulwark", "Endurance")|Weapon Mastery MELEE +8 · Precision CRIT_CHANCE +5 · Brutality CRIT_DMG +25 · Bloodthirst LIFESTEAL +4|Toughness MAX_HEALTH +2 · **War Cry** · Iron Skin ARMOR +2 · **Whirlwind**|Stamina MAX_STAMINA +15 · Second Wind STAMINA_REGEN +15 · Riposte PARRY_WINDOW +2 · Light Feet DODGE_COST +15|
|Mage ("Fire", "Arcane", "Warding")|Pyromancy SPELL +8 · Focus CRIT_CHANCE +4 · Combustion CRIT_DMG +25 · Haste COOLDOWN_RED +8|Deep Mind MAX_MANA +20 · **Blink** · Flow MANA_REGEN +2 · **Meteor Storm**|Vitality MAX_HEALTH +2 · Mage Armor ARMOR +2 · Swiftness MOVE_SPEED +5 · Siphon LIFESTEAL +3|
|Archer ("Marksman", "Hunter", "Survival")|Steady Aim RANGED +8 · Eagle Eye CRIT_CHANCE +5 · Deadly Shot CRIT_DMG +25 · Quiver ARROW_SAVE +15|Fleet Foot MOVE_SPEED +4 · **Explosive Arrow** · Endurance MAX_STAMINA +15 · **Arrow Rain**|Vitality MAX_HEALTH +2 · Evasion DODGE_COST +15 · Second Wind STAMINA_REGEN +15 · Readiness COOLDOWN_RED +8|
|Rogue ("Assassin", "Shadow", "Agility")|Backstab BACKSTAB +25 · Precision CRIT_CHANCE +5 · Cruelty CRIT_DMG +25 · Blade Mastery MELEE +8|Fleet Foot MOVE_SPEED +5 · **Smoke Bomb** · Evasion DODGE_COST +15 · **Blade Dance**|Endurance MAX_STAMINA +15 · Second Wind STAMINA_REGEN +15 · Leech LIFESTEAL +4 · Readiness COOLDOWN_RED +8|

- **Stat descriptions** (stat id → text):
  - MELEE "+8% melee damage" (the value in each text follows the node's value);
  - CRIT_CHANCE "+5% critical chance";
  - CRIT_DMG "+25% critical damage";
  - LIFESTEAL "+4% of damage healed";
  - MAX_HEALTH "+1 heart";
  - ARMOR "+2 armor";
  - MAX_STAMINA "+15 stamina";
  - STAMINA_REGEN "+15% stamina regen";
  - PARRY_WINDOW "+2 steps parry window";
  - DODGE_COST "-15% dodge cost";
  - SPELL "+8% spell damage";
  - COOLDOWN_RED "-8% cooldowns";
  - MAX_MANA "+20 mana";
  - MANA_REGEN "+2 mana per second";
  - MOVE_SPEED "+5% move speed";
  - RANGED "+8% bow damage";
  - ARROW_SAVE "+15% arrows saved";
  - BACKSTAB "+25% backstab damage".
- **Ability nodes:** the text is the ability description.

### Abilities

Slot 0 is free from level 1 (key Q, `BIND_ABILITY1`). Slot 1 is node 5 (key G); slot 2 is node 7 (key V).

- **Cast rules:**
  - Cooldown steps = cd_s·60·(100 − COOLDOWN_RED)/100.
  - A cast fails with no cost (`SND_DRY_FIRE`, volume 0.5) when: not unlocked, on cooldown, the resource can't be paid (`combat_spend`), or the ability has no valid target.
  - Every cast except Smoke Bomb ends stealth (`combat_stealth_t = 0`).
- **Damage terms:** `M` = 1 + MELEE/100, `R` = 1 + RANGED/100, `S` = 1 + SPELL/100.
- **Crit:** `crit` = `combat_crit_roll(0)` at cast. On a crit, damage is multiplied by `combat_crit_mult()` and `AF_CRIT` is set.

|class|slot|name|res/cost/cd|effect|
|---|---|---|---|---|
|Warrior|0|Charge|ST 30 / 6 s|player `kbx/kbz` = forward_h·22, `charge_t = 15`. In `abilities_step`, each hostile mob not yet hit (32-bit mask) with horizontal distance < half_w + 0.9 and \|dy\| < 1.5: `combat_hit_flags = HF_PLAYER`, `mob_strike(i, round(6·M), forward_h·2)`, `MOB.stun = 30`. Plays `SND_WARCRY`|
||1|War Cry|ST 40 / 20 s|`combat_warcry_t = 480`. Hostiles within 6 blocks: `stun = 20`. `fx_burst(chest, FX_GOLD, 24, 3)`, `SND_WARCRY`|
||2|Whirlwind|ST 60 / 30 s|`whirl_t = 90`, `combat_slow_t = 90`. Pulses when `whirl_t` ∈ {90, 60, 30}: every hostile at horizontal distance < 3.5 and \|dy\| < 2 takes `round(item_attack_damage(held)·M·(warcry ? 1.3 : 1))` with outward knockback ×1.5. Each pulse: `fx_burst(FX_SPARK, 16, 4)`, `SND_WHIRL`, `hand_swing`|
|Mage|0|Fireball|MA 25 / 3 s|`arrows_spawn(eye + dir·0.5, dir·28, owner 0, round(8·S)·crit, pickup 0, PROJ_FIREBALL, flags)`. Plays `SND_FIREBALL`|
||1|Blink|MA 20 / 5 s|march s = 0.25, 0.5 … 8 along the full look direction; candidate feet = eye + dir·s − (0, 1.62, 0); stop at the first s whose box (0.3 × 1.8) is not free (any cell overlapped is `world_is_solid`). best = the last free s; best < 1.0 → fail. Set player xyz = candidate(best), vy = kb = fall = 0. `fx_burst(FX_MAGIC, 20, 2)` at the start and the end, `SND_BLINK`|
||2|Meteor Storm|MA 70 / 40 s|target = `raycast` block (40) hit cell centre, else eye + dir·30. 8 meteors, one every 22 steps (first immediately): a fireball at target + (U(−4,4), 18, U(−4,4)), v (0, −30, 0), damage round(12·S), flags `AF_BIG`|
|Archer|0|Volley|ST 30 / 6 s|5 arrows at yaw offsets −20, −10, 0, 10, 20°, current pitch, from eye + d·0.4, v = d·40, damage round(6·R) with its own crit roll each, pickup 0, kind ARROW. No arrow is consumed. `SND_BOW`|
||1|Explosive Arrow|ST 35 / 10 s|one arrow, v = dir·45, damage round(10·R)·crit, flags `AF_EXPLOSIVE`. On any impact: `explode_magic(pos, 2.5, damage)`|
||2|Arrow Rain|ST 60 / 30 s|target as for Meteor Storm (raycast 40, else eye + dir·25). 24 arrows, one every 5 steps, at target + (U(−4,4), 14, U(−4,4)), v (0, −35, 0), damage round(6·R)|
|Rogue|0|Shadowstep|ST 25 / 8 s|target = `mobs_raycast(eye, dir, 12)`; it must be hostile and nearer than the first block (`raycast` t). Position = mob − mob_forward·(half_w + 0.8), y = mob y; the box must be free. Set the player there with yaw = `yaw_from(mob − player)` and pitch 0; `combat_crit_next_t = 120`. `fx_burst(FX_MAGIC, 16, 2)` at both ends, `SND_BLINK`|
||1|Smoke Bomb|ST 40 / 20 s|`fx_burst(chest, FX_SMOKE, 40, 2.5)`, `combat_stealth_t = 300`, `SND_SMOKE`|
||2|Blade Dance|ST 60 / 35 s|`combat_blade_t = 360`, `fx_burst(FX_MAGIC, 20, 3)`, `SND_WARCRY`|

**Staff bolt** (LMB with STAFF or ARCHMAGE_STAFF while class = MAGE; any other class uses the staff as a melee weapon):
- STAFF: mana 5, cooldown 24 steps, damage round(4·S)·crit.
- ARCHMAGE_STAFF: mana 4, cooldown 18 steps, damage round(7·S)·crit.
- Projectile `PROJ_BOLT` at 45 b/s from eye + dir·0.4. Plays `SND_SPELL`.

**Projectile rules** (arrows.asm):
- **PROJ_BOLT:** no gravity, life 90 steps.
  - Mob hit → `combat_hit_flags = HF_PLAYER | (crit ? HF_CRIT : 0)`, then `mob_strike`, then lifesteal via `combat_heal(floor(dmg·LIFESTEAL/100))`.
  - Block → `fx_burst(FX_MAGIC, 6, 1)`, then removed.
  - Trail: one `fx_burst(FX_MAGIC, 1, 0.3)` per step.
- **PROJ_FIREBALL:** no gravity, life 120 steps. Any hit or expiry → `explode_magic(pos, flags & AF_BIG ? 3.0 : 2.5, damage)`. Trail: `fx_burst(FX_FIRE, 1, 0.3)`.
- **Arrow with `AF_EXPLOSIVE`:** on mob or block impact → `explode_magic(pos, 2.5, damage)`, never sticks.
- **Every player-owned (owner 0) projectile hit on a mob** sets `combat_hit_flags = HF_PLAYER | (AF_CRIT ? HF_CRIT : 0)` before `mob_hurt`/`mob_strike`.
- **Rendering:** bolt = untextured cube 0.18 (0.75, 0.4, 1.0); fireball = cube 0.3 (1, 0.55, 0.15). Both are fullbright: GL_TEXTURE_2D disabled on units 0 and 1 around the draw, exactly as `fx_render` does for FIRE.

**`explode_magic`:**
- `fx_explosion(c, 0.7·r)`, `audio_play_at(SND_EXPLODE, c, 0.6)`.
- Every live non-NPC mob within distance r of its body centre: `combat_hit_flags = HF_PLAYER`, `mob_strike(i, ceil(damage·(1 − 0.5·d/r)), unit(mob − c).xz·1.5)`.
- No block damage, no player damage, no TNT priming.

**`fx_burst`:** random unit direction × speed × U(0.5, 1). Per-kind size / life / behaviour:

|kind|size|life (steps)|motion|colour (start → end of life)|
|---|---|---|---|---|
|FIRE|0.15–0.3|10–16|as `fx_step`|as `fx_step`|
|SMOKE|0.2–0.4|40–70|as `fx_step`|as `fx_step`|
|SPARK|0.08–0.14|10–16|vy −0.3/step|(1, 0.95, 0.6) → (1, 0.6, 0.2)|
|MAGIC|0.12–0.2|18–30|velocity ×0.9/step|(0.7, 0.3, 1) → (0.3, 0.1, 0.6)|
|GOLD|0.1–0.18|30–50|vy +0.04/step|(1, 0.85, 0.3) → (1, 0.6, 0.1)|

SPARK, MAGIC and GOLD are fullbright like FIRE.

### Combat rules (combat.asm)

- **`combat_step(sprinting)`:**
  - **Timers:** every timer decrements toward 0.
  - **Guard:** if `combat_guard_t ≥ 0` → `++`.
  - **Mana:** += MANA_REGEN/60, capped at the max.
  - **Stamina:**
    - If `combat_spend_t == 0` and not sprinting → `+= (20/60)·(1 + STAMINA_REGEN/100)`.
    - Sprinting → `−= 0.2` and `combat_spend_t = 36`.
    - Clamp to 0..max.
- **`combat_set_guard(wanted)`:** wanted and `combat_guard_break_t == 0` and stamina ≥ 1 → if `guard_t < 0`, set `guard_t = 0`; otherwise `guard_t = −1`.
- **`combat_speed_mult`:** `(1 + MOVE_SPEED/100) · (guard ? 0.4 : 1) · (combat_slow_t > 0 ? 0.7 : 1) · (combat_blade_t > 0 ? 1.2 : 1)`.
- **`combat_dodge(INPUT*)`:**
  - Requirements: player on ground, not guarding, `dodge_cd == 0`, `combat_spend(RES_STAMINA, max(5, 25·(1 − DODGE_COST/100)))`.
  - Direction = fwd·(sin yaw, −cos yaw) + strafe·(cos yaw, sin yaw), normalised; with no input, −forward_h.
  - Effect: player `kbx/kbz` = dir·16, `vy = 3.5`, `dodge_t = 16`, `dodge_cd = 30`. `SND_DODGE`, `fx_burst(feet, FX_SMOKE, 6, 1)`. Returns 1.
- **`player_take_hit(amount, cause, src_x, src_z)`:** returns `HIT_NONE` when creative, dead or `surv.invuln > 0`. Otherwise:
  1. **Dodging** (`dodge_t > 0`): `dmgnum_text(eye + fwd·1.2, TXT_DODGED)`, return `HIT_NONE`.
  2. **Frontal** = (src − player) has length < 0.01, or dot(unit(src − player).xz, forward_h) ≥ 0.34.
  3. **Guarding and frontal:**
     - **Parry** (`guard_t < 6 + PARRY_WINDOW`): no damage. `combat_riposte_t = 60`, `SND_PARRY`, `fx_burst(midpoint at chest height, FX_SPARK, 12, 4)`, `combat_hitstop = 0.1`, `dmgnum_text(TXT_PARRY)`. Return `HIT_PARRIED`.
     - **Block:** stamina −= amount·6. If the stamina stayed > 0 → `survival_damage((amount + 3)/4, cause)`, `SND_BLOCK`, `dmgnum_text(TXT_BLOCKED)`, return `HIT_BLOCKED`. Otherwise stamina = 0, `guard_break_t = 60`, `guard_t = −1`, then fall through.
  4. **Taken:** amount' = warcry_t > 0 ? max(1, amount/2) : amount. Return `survival_damage(amount', cause) ? HIT_TAKEN : HIT_NONE`.
- **`combat_melee(mob, dirx, dirz)`:** returns 0 if `combat_attack_cd > 0`. Otherwise:
  1. **Cooldown:** `attack_cd` = by the held item's `item_tool`: none 10, PICKAXE 14, AXE 18, SHOVEL 14, SWORD 12, DAGGER 7. Halved (min 4) while `blade_t > 0`.
  2. **Damage:** base = `item_attack_damage(held)`; mult = M · (warcry ? 1.3 : 1).
  3. **Combo:** `combo = combo_t > 0 ? combo + 1 : 1`; `combo_t = 45`. At 3: mult ×1.5, knockback ×1.8, `combo = 0`.
  4. **Backstab:** dot(mob_forward (sin yaw, −cos yaw), unit(player − mob).xz) < −0.3 → mult ×(1 + BACKSTAB/100).
  5. **Forced crit** if any of:
     - `riposte_t > 0` (consumed);
     - `crit_next_t > 0` (consumed);
     - `stealth_t > 0` (consumed; stealth ends);
     - `blade_t > 0`;
     - player in the air with vy < −1.
  6. **Crit:** crit = `combat_crit_roll(forced)`; mult ×`crit_mult` on a crit.
  7. **Strike:** dmg = max(1, round(base·mult)); `combat_hit_flags = HF_PLAYER | crit`; `mob_strike(mob, dmg, dir·kbmul)`.
  8. **On success:**
     - lifesteal: `life_carry += dmg·LIFESTEAL/100`; heal floor(carry) and keep the fraction;
     - `combat_hitstop = crit ? 0.09 : 0.05`;
     - `SND_SWING`, plus `SND_CRIT` and `fx_shake = max(fx_shake, 0.35)` on a crit;
     - stealth ends.

  Returns 1.
- **`survival.asm`:**
  - `surv_max_health` replaces the literals 20 in `survival_reset`, peaceful regen and fed regen.
  - Armor in `survival_damage` = min(20, `armor_points()` + `rpg_stat(STAT_ARMOR_BONUS)`), and it applies when armor points > 0 or the bonus > 0.
- **`player.asm` `body_step`:** sprint speed = `BODY.speed`·1.3 instead of the constant 5.612.

### Mobs (mobs.asm, mobrender.asm)

- **Type tables** for types 7, 8, 9:

  |table|MERCHANT|ELDER|BOSS|
  |---|---|---|---|
  |half_w|0.3|0.3|0.6|
  |height|1.95|1.95|3.3|
  |speed|1.0|1.0|2.4|
  |health|20|20|300 (set at spawn: {200, 200, 300, 450}[difficulty])|
  |hostile|0|0|1|
  |burns|0|0|0|
  |run|0|0|0|
  |say|`SND_VILLAGER`|`SND_VILLAGER`|`SND_BOSS_ROAR`|
  |hurt|`SND_VILLAGER`|`SND_VILLAGER`|`SND_SKELETON_HURT`|

  No drop entries (the boss drops come from a special case).
- **`mob_spawn`:** sets `max_health` = the spawn health.
- **`mob_spawn_elite`:** health ×2.5 (rounded), `elite = 1`.
- **`mob_spawn_npc`:** sets the home.
- **`mob_damage` (shared by `mob_hurt` and `mob_strike`):**
  1. NPC types → return 0 with no effect.
  2. Boss: knockback ×0.2.
  3. Set `bar = 180`. If `combat_hit_flags & HF_PLAYER` → `tagged = 200`.
  4. `dmgnum_spawn((x, y + height + 0.2, z), amount, combat_hit_flags & HF_CRIT)`.
  5. On death:
     - if `tagged > 0` → `rpg_on_mob_killed(type, elite)`;
     - if `origin` is 1..6 → `structures_on_mob_killed(origin)`;
     - for the boss, the death sequence below.
  6. Clear `combat_hit_flags` before returning.
- **`mob_update`:** decrements `stun`, `tagged`, `bar`, `timer_a`, `timer_b`.
- **Stun:** while `stun > 0`, the AI sets zero inputs and makes no attacks.
- **Stealth:** `combat_stealth_t > 0` → hostile AI (except the boss) behaves as not hunting (wander, creeper fuse decays).
- **Telegraphs:**
  - **Zombie:** in reach (dist² ≤ 2.89, existing test), cooldown 0 and `windup == 0` → `windup = 20` (elite 16); fwd = 0 during the windup. When the windup ends:
    - in range (dist² ≤ 3.6 and |dy| < 1.5) → r = `player_take_hit(dmg, CAUSE_ZOMBIE, x, z)`:
      - r = `HIT_PARRIED` → `stun = 50`, mob knockback away ×6, `dmgnum_text(TXT_STUNNED)`;
      - r = `HIT_TAKEN` → the existing player knockback and lift.
      - `cooldown = HIT_COOLDOWN`.
    - out of range → `cooldown = 20`.
  - **Spider bite:** the same with windup 12 and its existing range.
  - **Skeleton arrows** hitting the player go through `player_take_hit(dmg, CAUSE_SKELETON, arrow.x − vx·0.1, arrow.z − vz·0.1)`; the knockback applies only on `HIT_TAKEN`. This change is in arrows.asm, so W6 implements it.
  - **Elite damage** ×1.5 (rounded), and speed ×1.15.
- **NPC AI:**
  - Beyond 6 blocks from home → walk home.
  - Within 4 blocks of the player → stand and face the player.
  - Otherwise the existing wander. Never panics. Ignored by the spawner, despawn and peaceful removal.
- **Boss AI** (`MOB_BOSS` "The Fallen King"): phase P1 hp > 66 %, P2 > 33 %, P3 ≤ 33 %. It always hunts within 48 blocks and ignores stealth.
  - **Movement:** walks to the player at speed 2.4 (P3 ×1.4).
  - **Slam:** dist < 3.0 and cooldown 0 → `windup` 36 (P3 24). At the end: player horizontal distance < 3.5 (P3 5.0) and |dy| < 2.5 → `player_take_hit({0,6,8,12}[diff], CAUSE_BOSS, x, z)`.
    - Parried → `stun = 30`.
    - `HIT_TAKEN` → player kb 10, vy 5.
    - Either way: `fx_explosion((x, y + 0.2, z), 1.5)`, `SND_SLAM`, cooldown 70 (P3 45).
  - **Summon:** `timer_a` every 600 steps: if `mob_count_type(MOB_SKELETON)` < 4 → spawn 2 skeletons at boss ±2 x.
  - **Volley (P2/P3):** `timer_b` every 240 steps: 5 skeleton arrows (owner 1, dmg {0,3,4,5}[diff], speed 30) fanned ±20° at the player eye. `SND_BOW`.
  - **Entering P3:** `SND_BOSS_ROAR`, `hud_banner("The Fallen King grows furious!", RGBA(255,80,60,255))`.
  - **Death:**
    - drops: the class legendary (WARRIOR or none → KINGS_BLADE, MAGE → ARCHMAGE_STAFF, ARCHER → CELESTIAL_BOW, ROGUE → SHADOW_FANG), 30 GOLD_COIN, 4 DIAMOND;
    - `rpg_state.flags |= 1`, `rpg_add_xp(500)`, `quests_on_boss_killed()`;
    - `hud_banner("Victory! The Fallen King is no more.", RGBA(255,215,60,255))`;
    - `fx_explosion(centre, 3)`.
- **Drops:** non-boss hostiles drop 1 GOLD_COIN when rng%2 == 0. Elites drop 3 + rng%3 coins plus a HEALTH_POTION with 30 % chance.
- **Save:**
  - `mobs_save` skips types 7–9 and writes `type | MOB_ELITE_BIT` for elites.
  - `mobs_load` accepts `(type & 0xFF)` in 1..6, with bit 8 → elite (health capped at 2.5×base).
- **Rendering:**
  - **Villager models** (front −Z):
    - legs x [−0.22,0]/[0,0.22], y 0–0.75, z ±0.11, robe tile, pivot y 0.75, swing ±1;
    - body x ±0.25, y 0.75–1.45, z ±0.15, robe;
    - folded arms x ±0.3, y 1.1–1.35, z −0.3..−0.15, robe, rigid;
    - head x ±0.2, y 1.45–1.95, z ±0.2, `TILE_VILLAGER_SKIN` with front `TILE_VILLAGER_FACE`;
    - nose x ±0.05, y 1.55–1.72, z −0.3..−0.2, skin.

    MERCHANT uses `TILE_MERCHANT_ROBE`, ELDER uses `TILE_ELDER_ROBE`.
  - **Boss model:**
    - legs x [−0.35,−0.1](+1)/[0.1,0.35](−1), y 0–1.3, z ±0.12, bone, pivot 1.3;
    - robe x ±0.45, y 1.1–2.4, z ±0.25, `TILE_BOSS_ROBE`;
    - arms x [−0.7,−0.45](−0.5)/[0.45,0.7](+0.5), y 1.4–2.4, z ±0.12, bone, pivot 2.3;
    - head x ±0.35, y 2.4–3.1, z ±0.35, bone, front `TILE_BOSS_FACE`;
    - crown x ±0.38, y 3.1–3.35, z ±0.38, `TILE_BOSS_CROWN`.
  - **Tints**, in priority order:
    - hurt (existing red);
    - windup: (1, 0.45, 0.45) while `(windup >> 2) & 1`, with scale ×1.05 during the windup;
    - stun: (1, 1, 0.4) while `(stun >> 2) & 1`;
    - elite: constant (1, 0.85, 0.5) and scale ×1.2.

### Progression, quests, trade (W3)

- **XP per kill** (only when tagged, via `rpg_on_mob_killed`): zombie 10, pig 2, creeper 15, skeleton 12, spider 10, chicken 2, merchant 0, elder 0, boss 0. Elite ×3. The boss's 500 XP comes from its death sequence. Dungeon clear 150; quests as listed below.
- **`rpg_add_xp` level-up loop:** while xp ≥ need and level < 30:
  1. xp −= need, level++;
  2. `SND_LEVELUP`, `hud_banner("Level N!", RGBA(255,215,60,255))`, `fx_burst(player chest, FX_GOLD, 30, 3)`;
  3. health = `surv_max_health` after recompute, `combat_refill()`.

  At level 30, xp = 0.
- **`rpg_load` validation:**
  - class > 4 → full reset.
  - class 0 → full reset (level 1).
  - level outside 1..30 → full reset.
  - Any rank > its max → ranks = 0.
  - Σranks > level → ranks = 0.
  - xp ≥ need(level) → need − 1.
  - quest > 8 → 0.
  - quest_state > 1 → 0.
  - `cleared &= 0x3F`, `flags &= 1`.
- **Quest chain** (shared by every elder; rewards are XP + coins, with an optional item):

  |#|type/target/count|title|line1 / line2|reward|
  |---|---|---|---|---|
  |0|KILL ZOMBIE 6|Zombie Trouble|"The dead walk at night." / "Slay 6 zombies."|40 XP, 6 coins|
  |1|BRING IRON_INGOT 8|Iron for the Smithy|"Our smith needs iron." / "Bring 8 iron ingots."|50 XP, 10 coins|
  |2|KILL SKELETON 5|Rattling Bones|"Archers of bone haunt us." / "Destroy 5 skeletons."|60 XP, 8 coins, 1 HEALTH_POTION|
  |3|KILL CREEPER 3|Silent Hissers|"Something hisses nearby." / "Kill 3 creepers."|70 XP, 10 coins|
  |4|CLEAR 1|Into the Depths|"Dungeons lie below us." / "Clear one of them."|150 XP, 20 coins, 2 HEALTH_POTION|
  |5|BRING DIAMOND 3|Shining Treasure|"Diamonds buy us steel." / "Bring 3 diamonds."|120 XP, 25 coins|
  |6|ELITE 5|Champions of Darkness|"Elite fiends guard the deep." / "Slay 5 elite monsters."|200 XP, 30 coins|
  |7|BOSS 1|The Fallen King|"A dead king stirs in his crypt." / "End his reign."|500 XP, 60 coins|

  - **Progress:** counts only while accepted. KILL: target type matches. ELITE: any elite. CLEAR: `quests_on_dungeon_cleared`. BOSS: `quests_on_boss_killed`.
  - **`quests_complete`:**
    1. BRING removes `count` items with `inv_remove_one`.
    2. `rpg_add_xp`, then coins and the item via `inv_add` (overflow → `drops_spawn` at the player).
    3. quest++, state 0, progress 0.
    4. `SND_QUEST`, `hud_banner("Quest complete!", RGBA(255,215,60,255))`.
- **Trades** (give → get):
  1. 6 coin → 1 HEALTH_POTION
  2. 6 coin → 1 MANA_POTION
  3. 4 coin → 16 ARROW
  4. 8 coin → 4 IRON_INGOT
  5. 25 coin → 1 DIAMOND
  6. 12 coin → 1 STAFF
  7. 10 ROTTEN_FLESH → 1 coin
  8. 1 DIAMOND → 15 coin

  `trade_can` = `inv_count(give) ≥ give_n`. `trade_execute` removes, adds (overflow dropped), plays `SND_COIN`.

### Structures (structures.asm, W7)

- **Site planning.** `structures_plan(seed)` calls `worldgen_set_seed(seed)`; h(x,z) = `worldgen_height`. All choices are deterministic, so planning reproduces the same sites at load.
  - **Villages** (up to 2):
    - candidates k = 0..95: x = 24 + `hash32(k,0,600)`%208, z = 24 + `hash32(k,1,600)`%208;
    - accept when: distance to (128,128) is in [30, 100]; ≥ 60 from accepted villages; h(x,z) ≥ 25; and |h(x+dx, z+dz) − h(x,z)| ≤ 3 for dx, dz ∈ {−15, −10, −5, 0, 5, 10, 15};
    - if fewer than 2 are found, a second pass with tolerance 6 and h ≥ 23;
    - site: y = h(x,z), box x±16, y..y+10, z±16; index = order.
  - **Dungeons** (up to 6):
    - candidates k = 0..191: x = 60 + `hash32(k,0,610)`%170, z = 8 + `hash32(k,1,610)`%226;
    - accept when: h ≥ 16 at (x,z), (x+14,z) and (x+14,z+14); ≥ 30 from (128,128); ≥ 40 from accepted dungeons; ≥ 32 from village centres;
    - site: y = 8, box x−5..x+19, 7..13, z−5..z+19.
  - **Crypt** (1):
    - candidates k = 0..191: x = 66 + `hash32(k,0,620)`%160, z = 10 + `hash32(k,1,620)`%236;
    - accept when: h ≥ 18 at the centre and at (x±8, z±8); distance to spawn in [60, 110]; ≥ 40 from dungeons and villages;
    - fallback pass with a spawn distance of [40, 130];
    - site: y = 6, box x−7..x+7, 6..13, z−7..z+7.
- **Building** (`structures_generate`, called at the end of `world_generate` after the trees; it uses `world_set`, `cont_create` and `world_header`). Shell block = `hash32(X·7+Y, Z, 630)`%10 < 3 ? MOSSY_STONE_BRICK : STONE_BRICK.
  - **Dungeon (ox, oz)**, built in passes:
    1. **Shells:**
       - rooms R0 (ox,oz), R1 (ox+14,oz), R2 (ox+14,oz+14), each box c±5 × y 7..13;
       - corridor A: x ox+5..ox+9, z oz−2..oz+2, y 7..11;
       - corridor B: x ox+12..ox+16, z oz+5..oz+9, y 7..11.

       Every cell is set to a shell block.
    2. **Interiors set to AIR:** rooms c±4 × 8..12; corridor A x ox+6..ox+8 / z oz−1..oz+1 / y 8..10; corridor B x ox+13..ox+15 / z oz+6..oz+8 / y 8..10.
    3. **Openings set to AIR:** (ox+5, 8..10, oz−1..oz+1), (ox+9, 8..10, oz−1..oz+1), (ox+13..ox+15, 8..10, oz+5), (ox+13..ox+15, 8..10, oz+9), and (ox−5, 8..10, oz−1..oz+1).
    4. **Stair tunnel** from (ox−5, z = oz), floor y0 = 7. For i = 1..60, with X = ox − 5 − i and floor Yf = y0 + i:
       - first, if the original `world_top_y(X, oz)` < Yf + 1 → place the entrance (pillars MOSSY at (X, Yf+1..Yf+3, oz−2) and (X, Yf+1..Yf+3, oz+2), lintel MOSSY at (X, Yf+4, oz−2..oz+2)) and stop;
       - otherwise: floor (X, Yf, oz−1..oz+1) = shell; air (X, Yf+1..Yf+3, oz−1..oz+1); walls (X, Yf..Yf+4, oz±2) and ceiling (X, Yf+4, oz−1..oz+1) = shell, but only where the existing block is non-AIR.
    5. **Chests** at (ox+3, 8, oz+3), (ox+17, 8, oz−3), (ox+11, 8, oz+17), (ox+17, 8, oz+17): `world_set` CHEST + `cont_create(CONT_CHEST)` + loot.
  - **Loot:**
    - rolls = 4 + `hash32(X,Z,641)`%3; roll r: h = `hash32(X·31+r, Z·17+Y, 640)`;
    - entry = weighted pick by h % total; count = min + (h>>16) % (max−min+1); cell = (h>>8) % 27, or the next free cell if taken.
    - Dungeon table (weight, item, min–max): 30 GOLD_COIN 3–8; 15 IRON_INGOT 2–5; 10 GOLD_INGOT 1–3; 5 DIAMOND 1–2; 12 HEALTH_POTION 1–2; 8 MANA_POTION 1–2; 10 ARROW 8–16; 5 PISTOL_ROUND 8–16; 5 COOKED_PORKCHOP 2–4.
    - Crypt table: 30 GOLD_COIN 10–20; 15 DIAMOND 2–4; 20 HEALTH_POTION 2–3; 15 MANA_POTION 2–3; 20 GOLD_INGOT 3–6.
  - **Crypt (cx, cz):**
    1. shell box cx±8 × y 5..14 × cz±8;
    2. interior AIR cx±7 × 6..13 × cz±7;
    3. 4 STONE_BRICK pillars at (cx±4, 6..13, cz±4);
    4. opening AIR (cx−8, 6..8, cz−1..cz+1);
    5. stair tunnel from (cx−8, z = cz) with y0 = 5;
    6. 2 crypt chests at (cx+6, 6, cz−6) and (cx+6, 6, cz+6).
  - **Village (vx, vy, vz):**
    1. **Flatten** x/z ±15: AIR over vy+1..vy+14; GRASS at vy; DIRT where AIR in vy−3..vy−1.
    2. **Well:** COBBLE ring (vx+i, vy+1, vz+j) for i, j ∈ −1..1 except the centre; GLASS at (vx, vy, vz); LOG posts at (vx±1, vy+2..vy+3, vz±1); PLANKS roof 3×3 at vy+4.
    3. **Houses** at offsets (+9,0), (−9,0), (0,+9), (0,−9) (house 0..3), centre (hx, hz), footprint hx±2 / hz±2:
       - floor COBBLE at vy;
       - walls vy+1..vy+3 on the perimeter: PLANKS, with LOG at the 4 corners;
       - GLASS at vy+2 in the middle of each wall except the door wall;
       - door = middle cells at vy+1 and vy+2 of the wall facing (vx, vz), set to AIR;
       - roof PLANKS 7×7 at vy+4, BRICK 5×5 at vy+5, BRICK 3×3 at vy+6.
    4. **Paths:** GRAVEL at ground level vy on the cells between distance 2 and 6 from the centre along each axis.
    5. **NPC homes:** merchant (vx+6.5, vz+0.5), elder (vx−5.5, vz+0.5).
- **`structures_spawn_npcs`:** for each village, `mob_spawn_npc(MOB_MERCHANT, home0, y = world_top_y + 1)` and `mob_spawn_npc(MOB_ELDER, home1, …)`.
- **`structures_reset`:** zero the RAM arrays `spawned[6]`, `kills[6]` and the timer.
- **`structures_step`** (survival and difficulty > 0 only):
  - **Dungeon d not cleared, player feet inside its box expanded by 2:** every 90 steps, if live mobs with origin d+1 < 3 and `spawned[d]` < 8:
    1. room = rng%3; position = room centre + ((rng%7)−3, 0, (rng%7)−3) at y 8;
    2. require player distance² ≥ 36 and AIR at y 8 and 9;
    3. type = {ZOMBIE, SKELETON, SPIDER}[rng%3];
    4. idx = `mob_spawn_elite`; `origin = d+1`; `spawned[d]++`.
  - **Crypt:** boss not defeated, player inside the crypt box, `mob_count_type(MOB_BOSS) == 0` → spawn the boss at (cx+0.5, 6, cz+0.5) with origin 99. `SND_BOSS_ROAR`, `hud_banner("The Fallen King awakens!", RGBA(255,80,60,255))`.
- **`structures_on_mob_killed(origin)`:** origin 1..6 → `kills[d]++`. At 8 with the bit unset: `cleared |= 1<<d`, `rpg_add_xp(150)`, `hud_banner("Dungeon cleared!", RGBA(120,255,120,255))`, `SND_QUEST`, `quests_on_dungeon_cleared()`.
- **`structures_nearest(kind, uncleared_only)`:** nearest site of that kind to the player by horizontal distance. With `uncleared_only`, it skips dungeons whose cleared bit is set and the crypt once the boss is defeated.

### UI (W8 HUD, W9 screens)

- **`world_to_ui`:**
  - Basis vectors:
    - f = `player_forward`;
    - r = (cos yaw, 0, sin yaw);
    - u = (sin yaw·sin pitch, cos pitch, −cos yaw·sin pitch);
    - rel = p − eye.
  - Camera coordinates: xc = rel·r, yc = rel·u, zc = rel·f. Visible only when zc > 0.05.
  - Projection: t = tan(fov·(1 − 0.3·`game_aim`)/2); sx = ui_w/2 + (xc/zc)/t·(ui_h/2); sy = ui_h/2 − (yc/zc)/t·(ui_h/2).
- **`dmgnum`:**
  - 32 entries, life 50 steps, rising 0.6 b/s; alpha fades over the last 15 steps; the oldest entry is replaced when full.
  - Number colour: white; crit = (255, 220, 60) at scale 2, other numbers scale 1.
  - Texts: "PARRY!" (255, 215, 0), "BLOCKED" (180, 180, 200), "DODGED" (150, 220, 255), "STUNNED" (255, 160, 60).
- **HUD layout** (y0 = ui_h − 22, x0 = ui_w/2 − 91, survival bars only in survival):
  - **XP bar** (class ≠ 0): rect (x0+1, y0−5, 180, 3), bg (0,0,0,160), fill (120,220,60) proportional to xp/need. Level text centred at (ui_w/2, y0−15) in (140,255,90).
  - **Hearts:** row 1 at y0−15 (10 icons). If `surv_max_health` > 20, row 2 at y0−25 (icons 10..14). Food row at y0−15 at the existing x.
  - **Left stack:** ly = top heart row y. Mana bar (max mana > 0): (x0, ly−6, 80, 4) fill (70,110,255); ly −= 6. Armor row (points > 0) at ly−10; ly −= 10.
  - **Stamina bar:** (x0+102, y0−21, 80, 4) fill (240,200,60), or (220,60,40) when < 25.
  - **Held name:** at min(ly, y0−21) − 12.
  - **Ability bar:** slots i = 0..2 at (x0 − 70 + 23i, y0+1), 20×20 bg (0,0,0,115).
    - Icon via `ui_tile_icon(TILE_ABILITY0 + (class−1)·3 + i, x+2, y+2, 16, tint)`:
      - tint WHITE when ready;
      - (255,90,90,255) when the resource is short;
      - (255,255,255,80) when locked.
    - Cooldown overlay: rect from the top, height 20·cd/total, (0,0,0,170).
    - Key label from `key_name(settings.keys[BIND_ABILITY1+i])` at (x+1, y−9).
  - **Boss bar:** a living boss within 48 blocks → "The Fallen King" centred at (ui_w/2, 4); bar (ui_w/2−91, 14, 182, 5) fill (200,30,30).
  - **Mob health bars:** hostile mobs with `bar > 0` or `elite`, within 24 blocks → 20×2 bar centred at `world_to_ui(x, y+height+0.35, z)`, fill (230,40,40), gold frame for elites.
  - **NPC name tags:** within 10 blocks → "Merchant"/"Elder" in (255,255,180) at y+height+0.5.
  - **Damage numbers, banner:** banner centred at (ui_w/2, ui_h/2−50), scale 2, fading over the last 0.5 s.
  - **Quest tracker:** at (4, debug shown ? 102 : 4): "Quest: <title>  p/c". For CLEAR/BOSS quests, append "  <N|NE|E|SE|S|SW|W|NW> <dist>m" toward `structures_nearest(DUNGEON or CRYPT, 1)` (N = −z).
  - **Stealth overlay:** full-screen RGBA(20,0,40,60) while `stealth_t > 0`.
  - **F3 lines:** "Class: <name> Lv N  XP x/need" and "Sites: V x,z  D x,z  C x,z" (nearest of each kind). The debug health line prints "/<max>" instead of "/20".
- **Screens (rpgscreens.asm).** Each screen closes with Esc, the inventory key or the skills key (back to `ST_PLAYING`). The class screen instead quits to the title on Esc and has no other close.
  - **`screen_class`:**
    - dimmer; "Choose your class" scale 2 at (cx, 20);
    - 4 cards 100×150 at (cx − 210 + 105i, 50): `ui_tile_icon(TILE_CLASS0+i, card centre − 16, y+8, 32, WHITE)`, name at y+46, the 3 lines at y+62/74/86, button "Choose" (x+5, y+124, w 90);
    - a click → `rpg_set_class(i+1)` → `ST_PLAYING`.
  - **`screen_skills`:**
    - **Panel:** 260×210 centred. Header "<class> - Level N" at (px+8, py+6); "Points: N" right-aligned at px+252; XP bar (px+8, py+18, 244, 3). Branch names centred at (px+50+80c, py+28).
    - **Nodes:** 24×24 at (px+38+80c, py+44+40t). Connectors (px+49+80c, py+68+40t, 2, 16) in (255,255,255,200) when the upper node has rank ≥ 1, else (90,90,90,255).
    - **Node border colour:** maxed (255,200,60); ranked (120,220,90); spendable (255,255,255,200); locked (90,90,90).
    - **Node icon:** ability → `TILE_ABILITY0 + …`; stat → `TILE_STAT0 + stat`. Dimmed (255,255,255,90) when rank 0 and not spendable. Rank text "r/m" inside, bottom-right.
    - **Hover:** `ui_tooltip("<name> r/m: <desc>[ - needs level N | - needs previous skill]")`.
    - **Click:** `rpg_spend`.
    - **Footer:** at py+196, "<key>: <ability0>  <key>: <ability1>  <key>: <ability2>".
  - **`screen_trade`:**
    - panel 220×200; "Merchant" title; "Coins: N" right;
    - 8 rows at py+22+21r: `ui_item_icon(give)` + count, "->", `ui_item_icon(get)` + count, and a button "Trade" (px+160, row, w 50, enabled = `trade_can`) → `trade_execute`.
  - **`screen_dialog`:**
    - panel 260×120, "Elder" title.
    - Chain finished: "The realm is saved. Rest, hero." and a "Farewell" button.
    - Otherwise: the title in (255,215,60), line1, line2, and "Progress: p/c" once accepted.
    - Buttons: state 0 → "Accept" and "Leave"; accepted and `quests_can_complete` → "Complete" and "Leave"; otherwise "Leave".
  - **`options.asm` controls, 2 columns:**
    - row r < 8 in column 0, else column 1, at row r mod 8;
    - pitch = min(24, (ui_h − 60)/8);
    - label at x = cx − 235 + 240c; button at x + 125, w 100;
    - the Reset/Done buttons stay where they are.

### Art (W1) and sound (W2)

- **Tiles (texgen.asm):**
  - 59 stone bricks: grey 2-row brick pattern with dark mortar lines.
  - 60 mossy bricks: the same with green moss blotches.
  - 129–138 item icons:
    - staff: wood shaft, gold head;
    - archmage staff: dark shaft, glowing cyan orb;
    - iron dagger and diamond dagger;
    - Shadow Fang: black/purple blade;
    - King's Blade: gold hilt, white-gold blade;
    - Celestial Bow: white/cyan;
    - health potion: red flask;
    - mana potion: blue flask;
    - gold coin: round yellow with rim.
  - 139–150 ability icons in the order of the ability table.
  - 151–154 class emblems: crossed swords, flame staff, bow, dagger in a hood.
  - 155–172 stat icons, one simple glyph per stat id: heart, sword, arrow, star, crosshair, burst, blue drop, blue drop with an arrow, yellow bolt, bolt with an arrow, shield, boot, dagger-back, crossed blades, red drop, hourglass, quiver, wind.
  - 173–179 NPC and boss textures per the Mobs section: villager skin (225,180,140), face with eyes and brows, merchant robe green (60,130,60) with a belt, elder robe purple (100,60,140) with gold trim, boss robe dark purple with ragged edges, skull face with glowing red eyes, gold crown with red gems.
  - **Proof:** an atlas dump, byte-identical outside these tiles.
- **Sounds (sfx.asm):** layers with the `LAYER` macro; every peak in [−18, −0.1] dB; `POOL_SAMPLES` raised if needed.
  - swing: short noise whoosh
  - parry: bright metallic ring (square 1800→1600, long decay)
  - block: dull thud
  - dodge: soft whoosh
  - crit: sharp crack plus a high ping
  - levelup: rising 4-note square arpeggio
  - spell: rising sine-like saw blip
  - fireball: noise whoosh plus a low roar
  - blink: descending shimmer
  - warcry: low saw shout with vibrato
  - whirl: two fast whooshes
  - smoke: hiss
  - coin: two high clinks
  - quest: 3-note fanfare
  - boss_roar: long low saw with vibrato plus noise
  - slam: deep boom
  - villager: short "hmm" (low square with vibrato)
  - drink: gulp blips

## Approach

### Wave 0 — contracts (integrator, inline)

1. Make every edit in **Contracts**: constants, structs, tables, recipes, palette, bindings, settings, input, labels, and the `mob_shot` → `mob_strike` rename.
2. Update existing callers of the changed signatures:
   - `arrows_spawn` gets `r8d = 0` at its 5 call sites;
   - `test_settings.asm` `alt_img` gets 5 more keys (264..268);
   - `test_settings_reload_key` also checks the defaults dodge 67, ability1 81, ability2 71, ability3 86, skills 75.
4. Done when `make` prints no warnings and `make test` = 69/69. Commit "0.6 contracts".

### Wave 1 — nine parallel workers (one `task` batch)

Every worker gets this plan's path, its section names, and the Conventions. Each owns exactly these files:

|Worker|Owns|Delivers + tests|
|---|---|---|
|W1 Art|`texgen.asm`|all tiles; atlas proof; PNG crop path|
|W2 Sound|`sfx.asm`|18 sounds; peak table|
|W3 RPG|new `rpg.asm`, `quests.asm`, `test_rpg.asm`|see below|
|W4 Combat|new `combat.asm`, `test_melee.asm`; `survival.asm`, `player.asm`|see below|
|W5 Mobs|`mobs.asm`, `mobrender.asm`, `test_mobs.asm`|see below|
|W6 Abilities|new `abilities.asm`, `test_abilities.asm`; `arrows.asm`, `explode.asm`, `fx.asm`|see below|
|W7 World|new `structures.asm`, `test_structures.asm`; `worldgen.asm`, `test_worldgen.asm`|see below|
|W8 HUD|new `project.asm`, `dmgnum.asm`, `test_hud.asm`; `hud.asm`, `ui.asm`|see below|
|W9 Screens|new `rpgscreens.asm`; `options.asm`|screens render and respond; tested live in wave 2|

**Tests per worker** (all expectations from the Design data):

- **W3:**
  - `[rpg_levels_and_points]`: class 1; `rpg_add_xp(30)` → level 2, xp 0, points 2; `rpg_add_xp(10000)` → level 30, xp 0.
  - `[rpg_skill_spend_rules]`: Warrior at level 3 (3 points):
    - `rpg_can_spend(1)` → 3 (level below 4); `rpg_can_spend(4)` → 0;
    - `rpg_spend(0)` three times → 1, 1, 1; then `rpg_can_spend(0)` → 1 (no points, checked before max rank);
    - set level 4: `rpg_can_spend(1)` → 0; `rpg_can_spend(5)` → 4 (node 4 has rank 0);
    - set level 5: `rpg_can_spend(0)` → 2 (max rank).
  - `[rpg_stats_from_class_and_ranks]`: Rogue with node 0 at rank 2 → BACKSTAB 150, MOVE_SPEED 5; Mage MAX_MANA 100 → 160 after node 4 at rank 3.
  - `[rpg_save_load_validates]`: round trip through `world_header`; ranks [3,3,3,…] at level 5 → ranks zeroed; class 9 → class 0.
  - `[quest_chain_progress_and_rewards]`: accept quest 0; 6 × `quests_on_kill(ZOMBIE,0)` → can complete; complete → quest 1, +40 XP, coins in the inventory; quest 1 with 8 IRON_INGOT → complete removes them.
  - `[trade_exchanges_items]`: 6 coins, trade 0 → 0 coins plus 1 HEALTH_POTION; then `trade_can(0)` = 0.
- **W4:**
  - `[guard_blocks_and_parries]` (class 0: health 20, stamina 100; set `surv.invuln = 0` before every hit):
    - guard raised, hit of 3 from the front at `guard_t` 0 → `HIT_PARRIED`, health 20, `combat_riposte_t` 60;
    - 10 × `combat_step(0)`, hit of 3 from the front → `HIT_BLOCKED`, health 19, stamina 82;
    - hit of 3 from behind → `HIT_TAKEN`, health 16;
    - stamina 5, guard up ≥ 10 steps, hit of 3 from the front → `HIT_TAKEN`, `combat_guard_break_t` 60, health 13.
  - `[dodge_iframes_and_stamina]` (class 0, player on the ground): dodge → 1, kb set, stamina 75; hit during `dodge_t > 0` → `HIT_NONE`; a second dodge before the cooldown → 0; after 30 steps with `on_ground = 0` → 0.
  - `[melee_combo_crit_backstab]`: zombie 1 block in front, facing the player; held IRON_SWORD (attack 7); Warrior (MELEE 10); after `rpg_recompute`, set `rpg_stats[STAT_CRIT_CHANCE] = 0`; player on the ground:
    - hit 1 → zombie health 20 − 8 (7·1.1 = 7.7 → 8);
    - an immediate second `combat_melee` → 0 (attack cooldown);
    - 12 × `combat_step`, hit 2 → −8; 12 steps, hit 3 → −12 (7·1.1·1.5 = 11.55 → 12);
    - new zombie turned away (yaw +180), Warrior → −8 (BACKSTAB 0);
    - Rogue (MELEE 0, BACKSTAB 100), fresh combo, zombie turned away → −14.
  - `[stamina_mana_regen_and_max_health]`: stamina regen waits 36 steps after spending; Mage mana regen 4/s; Warrior `surv_max_health` 24 and `survival_reset` health 24.
- **W5:**
  - `[zombie_windup_can_be_parried]`: zombie in reach, player guard raised at the end of the windup → no damage, zombie `stun` 50.
  - Update `zombie_attacks_player`: after 1 step the health is unchanged and `windup` > 0; after 20 more steps the existing health and knockback expectations hold (the hit now lands at the end of the windup); then the existing 10-step hold check.
  - `[elite_saved_and_tougher]`: elite zombie health 50; save/load → elite flag and health kept.
  - `[npc_immune_and_not_saved]`: `mob_strike` on a merchant → 0, health unchanged; `mobs_save` skips it.
  - `[boss_phases_slam_and_summons]` (survival, difficulty 2, class 0, no armor). The boss spawn sets `timer_a = 600`, `timer_b = 240`.
    - spawn → health 300, `max_health` 300;
    - player 2 blocks in front → within 40 `mobs_step` calls, health exactly 12 (one slam of 8; the 70-step cooldown prevents a second);
    - set `timer_a = 1` → after 1 step, `mob_count_type(MOB_SKELETON)` = 2;
    - set health 90, cooldown 0, player within 2 → on the step a slam starts, `windup` = 24.
  - `[mob_kill_awards_xp_and_coins]`: class 1; `combat_hit_flags = HF_PLAYER`; `mob_strike(zombie, 100)` → XP 10; coin drop with seeded rng; an untagged kill gives no XP.
- **W6:**
  - `[ability_cost_cooldown_and_unlock]`: Warrior Charge → stamina −30, cd 360; recast → 0; slot 1 locked → 0; Mage with 10 mana → Fireball 0.
  - `[fireball_explodes_without_breaking]`: fireball into a stone wall with a pig beside it → pig hurt, wall intact, player health unchanged.
  - `[blink_stops_before_wall]`: wall 4 blocks ahead → player x moved by < 4 and > 2, inside free space.
  - `[volley_and_arrow_rain_spawn]`: Volley → 5 live arrows, arrow count unchanged; Arrow Rain after 120 `abilities_step` → 24 spawned in total.
- **W7:**
  - `[structure_sites_deterministic]`: plan seed 42 twice → identical sites, ≥ 1 village, 6 dungeons, 1 crypt.
  - `[dungeon_built_with_chests]`: `world_generate(42)` → for dungeon 0, room centre (x, 9, z) AIR, (x−5, 9, z+3) a brick block, 4 containers of kind 2 inside its box, each with ≥ 1 non-empty cell.
  - `[village_built_with_npcs]`: after generate + `structures_spawn_npcs` → 1 MERCHANT and 1 ELDER per village, and the well GLASS at (vx, vy, vz).
  - `[dungeon_clears_after_kills]`: `structures_on_mob_killed(1)` ×8 → cleared bit 0, +150 XP.
  - `[crypt_spawns_boss_once]`: player inside the crypt box, survival, 1 step → 1 boss; another step → still 1; flags bit 0 set → none spawns after killing it.
  - `test_worldgen.asm` tests zero the containers region after each `world_generate`.
- **W8:**
  - `[world_to_ui_centres_forward]`: eye + `player_forward`·5 → (ui_w/2, ui_h/2) ±1; a point behind → 0; yaw 0 with a point at +x → sx > centre.
  - `[dmgnum_rises_and_expires]`: spawn → y rises after 10 steps; gone after 50.

Each worker's acceptance: green scratch build with its tests and no warnings; owned files copied back; report.

### Wave 2 — integration (integrator)

1. **Merge:** register every wave-1 test in `selftest.asm`; build to 95 tests; fix integration breaks in the owners' style.
2. **`game.asm`:**
   - **Globals:** `game_open_npc`.
   - **`reset_session`:** `combat_reset`, `abilities_reset`, `dmgnum_clear`.
   - **`game_new`:** after `mobs_populate`: `rpg_reset`, `structures_reset`, `structures_spawn_npcs`.
   - **`game_load`:**
     1. `rpg_load(header)` before the survival clamps; the health clamp uses `surv_max_health`;
     2. after `mobs_load`: `structures_plan(header.seed)`, `structures_reset`, `structures_spawn_npcs`.
   - **`game_save`:** `rpg_save(header)`.
   - **`game_respawn`:** `rpg_on_death`, `combat_reset`.
   - **New section 5b, after targets** (only when `input_captured == 1` and `game_open_screen == 0`):
     - **Guard:** wanted = RMB held, held `item_tool` ∈ {SWORD, AXE, DAGGER}, and not this frame's RMB press on a CRAFTING_TABLE/FURNACE/FURNACE_LIT/CHEST target → `combat_set_guard(wanted)`. With no capture, call `combat_set_guard(0)`.
     - **Dodge:** the `.dodge` edge → `combat_dodge(&frame_input.move)`.
     - **Abilities:** `.ability[i]` edges → `abilities_use(i, F_EYE, F_DIR)`.
   - **Section 6 in this order:**
     1. **NPC:** `F_MOB` ≥ 0 and the type is MERCHANT/ELDER → RMB press sets `game_open_screen` = ST_TRADE/ST_DIALOG and `game_open_npc` = idx; skip all attack, break and place (go to `.pick`).
     2. **Firearm:** the existing branch.
     3. **Staff:** held STAFF or ARCHMAGE_STAFF and class MAGE → LMB held → `abilities_staff_bolt(F_EYE, F_DIR)`; reset dig state; go to `.pick`.
     4. **Melee:** `F_MOB` ≥ 0 and LMB pressed → `hand_swing`, then `combat_melee(idx, dirx, dirz)`; if it lands and survival → `damage_held_tool` + exhaust.
   - **`damage_held_tool`:** amount 1 for TOOL_SWORD or TOOL_DAGGER.
   - **Section 9:**
     - skip entirely while `combat_guard_t ≥ 0`;
     - before the food check, potions: RMB press with HEALTH_POTION → `combat_heal(8)`; with MANA_POTION → mana = min(max, mana + 50). Then `SND_DRINK`, and consume 1 in survival.
   - **Survival break:** after `item_harvest_drop`, if drop ≠ 0 → `rpg_on_block_mined(block)`.
   - **Bow:**
     - BOW or CELESTIAL_BOW;
     - damage = round((1 + round(8p))·R·(celestial ? 1.5 : 1)), crit via `combat_crit_roll(0)` → `AF_CRIT`;
     - an arrow is consumed only if not CELESTIAL_BOW and rng%100 ≥ ARROW_SAVE.
   - **Hit-stop:** in the step loop, if `combat_hitstop` > 0, subtract dt and add nothing to `step_accum` this frame.
   - **`sim_step`:**
     - before `body_step`: `player.speed = 4.317·combat_speed_mult()`; clear `INPUT.sprint` when `combat_stamina` < 1;
     - after `gun_step`: `combat_step(sprinting)`, `abilities_step`, `dmgnum_step`, `structures_step`.
3. **`app.asm`:**
   - **`enter_world`:** `rpg_class() == 0` → `ST_CLASS`, else `ST_PLAYING`.
   - **Screens table:** add `screen_trade, screen_dialog, screen_class, screen_skills`; bound `ST_SKILLS`.
   - **`update_state`:**
     - PLAYING: the `.skills` edge → `ST_SKILLS`; `game_open_screen` ST_TRADE/ST_DIALOG → `app_goto` (no container);
     - the `.screen` branch adds 15, 16, 18;
     - ST_CLASS does not simulate.
   - **`draw_frame`:** the in-view list adds 15, 16, 18.
   - **`load_panorama`:** `dmgnum_clear`, `combat_reset`, `rpg_reset`.
4. **`hand.asm`:**
   - **Guard pose** (`combat_guard_t ≥ 0`, melee weapon): after the base translate, `glTranslatef(−0.15, 0.12, 0.05)`, `rotZ(70)`, `rotX(−10)`.
   - **Dodge:** y −= 0.12 while `dodge_t > 0`.
   - The bow pull check accepts CELESTIAL_BOW.
5. **`menus.asm`:** cause 9 "You were crushed by the Fallen King"; bound `CAUSE_BOSS`.
6. **`/tmp/acpatch.py`:** add the `pos` and `rpg` ops.
7. **Verification** (below), then commit "0.6: RPG".

## Critical files & anchors

- `src/common.inc` `WORLDHDR`: `.rpg` replaces `.pad` at 960 (64 bytes). Never move other offsets; old saves rely on zeros there.
- `src/mobs.asm` `mob_damage` (≈1268): the single place for NPC immunity, damage numbers, XP tagging, dungeon kill counting and boss death. Every damage path goes through it.
- `src/game.asm` `game_frame` sections 5–12 (≈520–1050): input ownership order NPC → firearm → staff → melee. A held firearm or guard must never break, place or use blocks.
- `src/worldgen.asm` `world_generate` tail (≈583): `structures_plan` + `structures_generate` before `world_mark_all_dirty`. `structures_plan` must stay pure (no block writes), because `game_load` calls it.
- `src/app.asm` `enter_world` (≈219): the only entry into play, used by world list, create, CLI `--play` and respawn-free loads.

## Verification

1. **Build and tests:** `make clean && make 2>&1 | grep -iE "warn|error"` prints nothing. `make test` → `selftest: 95 passed, 0 failed`.
2. **Old save:** the box copy of a 0.5 world loads into the class screen. Choose Warrior → the kit is in the inventory; save, quit and reload → class kept, file size still 4210688.
3. **Combat** (survival arena at night, Warrior, `mob=0:1:20:0:0:-4`):
   - shot during the zombie windup → red pulse;
   - hold RMB with the sword 0.1 s before impact → "PARRY!" and a stunned yellow pulse;
   - hold RMB early → "BLOCKED", health −1, stamina bar drops;
   - C → roll, "DODGED";
   - LMB three times → numbers, the 3rd larger, hit-stop visible.
4. **Classes:**
   - Mage: staff bolts (purple), Q fireball crater-free explosion, G blink, V meteors.
   - Archer: Q volley fan, G explosive arrow, V arrow rain.
   - Rogue: Q shadowstep behind a pig (crit), G smoke (stealth overlay; zombies stop chasing), V blade dance.
   - Warrior: Q charge stun, G war cry, V whirlwind.
   - Use `rpg=c:15` and the skill-tree screen (K) to buy the nodes first; a screenshot of the tree shows the borders and the tooltip.
5. **World:**
   - F3 "Sites" gives the coordinates. `pos=` to a village → houses, well, 2 NPCs with name tags. RMB on the merchant → a trade works (coins patched in). RMB on the elder → accept quest 0; kill zombies → tracker progress; complete → banner and XP.
   - `pos=` into a dungeon entrance → stairs down, 3 rooms, chests with loot, elites spawn with gold tint and health bars; 8 kills → "Dungeon cleared!".
6. **Boss:** `pos=` into the crypt at level 30 with diamond gear → banner, boss bar, slam telegraph, skeleton summons, P2 volleys, P3 banner; kill → legendary drop and victory banner. Reload → it does not respawn.
7. **HUD:** the level number and XP bar, mana (Mage) and stamina bars, ability bar cooldown overlays, level-up banner (patch xp close to need).
8. **Sound:** one capture of a parry and of a boss roar with `cap.sh` → max_volume > −20 dB.
9. **Performance:** title FPS with audio off (`PULSE_SERVER=unix:/nonexistent`) in a village with 10 mobs and a meteor storm ≥ 150.

## Assumptions & contingencies

- **Saves:**
  - Arrows, projectiles, dmgnums and the dungeon kill counters are not saved; partial dungeon progress resets on load.
  - NPCs are respawned from sites on every load, and the boss is respawned on entering the crypt while undefeated.
- **No lighting:** dungeons are not dark; the engine has no light propagation.
- **Magic never breaks blocks or hurts the player.** Rockets and TNT still do.
- **Site placement:**
  - If no village site passes both passes, the world has fewer villages; quests still work from any elder found.
  - If no village exists at all, quests are unavailable; the F3 Sites line shows "V none".
- **Mob slots:** if `mob_spawn` fails (32 slots), elite and boss spawns retry on later steps.
- **Generation time:** if `world_generate` slows world creation beyond 3 s in the box, build villages with direct `blocks` writes instead of `world_set` (same cells).
- **Narrow screens:** if the two-column controls layout overlaps at ui_w < 500, fall back to one column with pitch = max(14, (ui_h−60)/15).

## As built (deviations found during implementation and live checks)

- **Info records:** `CLASSINFO`, `NODEINFO`, `ABILINFO`, `QUESTINFO` and `TRADEOFFER` are strucs in `common.inc`, shared by rpg, quests, hud, abilities and the screens. `rpg_branch_name(class, branch)` exports the branch names; an ability node's `NODEINFO.stat` holds its ability slot.
- **Spacing:** a hunting zombie stops 1.1 blocks from the player and the Fallen King 2.2 blocks (his slam still reaches 3.5), so neither walks into the camera once blocks and parries remove the old knockback.
- **NPCs** stand on the village ground (`vy + 1`); both homes sit under a house's eave, where the top block is the roof.
- **Visuals:** bolts and fireballs leave no trail for their first 3 steps; particles within 0.8 blocks of the eye are not drawn (bursts centred on the player); the boss's damage numbers start 2 blocks up; mob bars, name tags and damage numbers are hidden while a screen is open.
- **Combat:** armor also reduces `CAUSE_BOSS`; blocking pauses stamina regen like any other spend; a level-up's effects play once per `rpg_add_xp` call.
- **Dungeon spawner:** `kills + live < 8` replaces the `spawned[]` counter, so an elite that despawns unkilled cannot leave a dungeon uncleared.
- **Shadowstep** targets hostile mobs only (the verification list's "behind a pig" was checked on a zombie).
- **Screens:** the skill panel is 292 wide (the longest ability footer is 282), class card lines wrap, and the controls screen has a compact two-column layout for 408 ≤ ui_w < 470.
