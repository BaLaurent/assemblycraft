# AssemblyCraft 0.10 — Factions: five factions with reputation, camps, shrines, fighters, patrols on roads, travelling traders and champions

## Context

**Repository and baseline.** AssemblyCraft is an x86-64 NASM Minecraft-like game at `/run/media/octopusman/Games/Experiences/assemblycraft`.
- It is on git `master` at `f3a8f79` (0.9 "World"), with no git remote.
- `make test` is 154/154 and the build is warning-free.
- 0.9 left reserved faction-camp slots, `SITE_CAMP` from `camp_plan` in `src/structures.asm`, as flat clearings with a fence post and a torch.

**What 0.10 adds** (roadmap `docs/superpowers/specs/2026-11-08-assemblycraft-v1-roadmap.md`, section "0.10 Factions"):
- 5 factions with per-faction reputation, standing tiers and rivalries.
- Shrine tribute, with a shrine block and its own screen.
- Camps in their home biomes with role NPCs: leader, trader, guards, workers, a captive.
- Humanoid fighters in 4 classes that use weapons and elements and drop their weapon.
- Patrols of 3 walking generated roads between camps.
- Travelling traders.
- One named champion per faction.

**Decisions the user made for this plan:**
- **Villages are the Villagers' camps.** The elder is their leader and the merchant their trader. Villages gain guards, workers, a champion and a shrine. The separate Villagers camp slot is dropped.
- **Rival factions' NPCs fight each other on sight,** not only through reputation.
- **Roads are stamped on the surface** between camps, and patrols walk them.
- **Starting standings:** Villagers +200, Bandits −100, Ashen Cult −100, Beastfolk 0, Stonekin 0.

**End state:**
- `make test` = 172/172 and the build is warning-free.
- The omabox live checks in Verification pass.
- The design doc `docs/superpowers/specs/2026-11-08-assemblycraft-factions-design.md` (this plan, plus a final "As built" section) is committed.

## Conventions (same as 0.9)

- **Assembly:**
  - Each file has `%include "common.inc"`, `default rel`, explicit sections and its own `extern`/`global`.
  - SysV ABI: rsp is 16-aligned at every call; rbx, rbp and r12–r15 are callee-saved; SSE is scalar.
  - Every function has a header comment with its signature and contract.
  - Byte ids are loaded with `movzx`. Signed coordinates use `sar`; floats are floored with `roundss 9` + `cvttss2si`.
- **Tests:**
  - A test is `test_<name>() → eax` (0 = pass). It starts with `call world_clear`, sets every global it relies on, and cleans up after itself (mobs, drops, arrows, containers, `/tmp` files).
  - Register it in `src/selftest.asm` with an `extern`, a `TEST` row and a `TESTNAME` row, appended in the order of the test list in this plan.
  - Every new assertion is proven by a negative control: break the code once in scratch and watch the test fail.
- **Workers:**
  - Each worker gets a scratch copy:
    `REPO=/run/media/octopusman/Games/Experiences/assemblycraft; rm -rf /tmp/ac10-<name> /tmp/ac10-<name>-base && mkdir -p /tmp/ac10-<name> && rsync -a --exclude build --exclude .git --exclude .omp $REPO/ /tmp/ac10-<name>/ && rsync -a $REPO/src/ /tmp/ac10-<name>-base/`.
  - Use absolute paths only, and never run git.
  - Sibling-owned symbols that a worker needs go in `/tmp/ac10-<name>/src/zz_stub.asm`, as faithful fakes where the worker's tests depend on their behaviour.
  - A minimal scratch-only patch to a file the worker does not own is allowed. It is reported and never copied back.
  - Each worker reports:
    - its owned files;
    - its `selftest.asm` lines;
    - the `make test` tail;
    - its stubs and patches;
    - its deviations;
    - every unowned call site the integrator must wire.
  - The integrator copies back only owned files, after a `cmp` against the base to catch drift.
- **Edits:** use the edit tool, never sed/perl/python rewrites. Only the integrator runs git, with one commit per wave step. Never add `.omp/` or `.asm-lsp.toml`.
- **Live checks** (omabox, run from `$HOME`):
  1. Start the box with `omabox up --audio`.
  2. Install the build:
     `H=$(omabox -b default path --home); cp build/assemblycraft "$H/.ac.new" && mv -f "$H/.ac.new" "$H/assemblycraft"`.
  3. Set the US layout:
     `omabox -b default lua 'hl.config({input={kb_layout="us", kb_variant=""}}); return "ok"'`.
  4. Launch:
     `omabox -b default run -d --wait -- /home/sbx/assemblycraft --data-dir /home/sbx/acv10 --play NAME [--creative --seed N]`.
  5. Close the window, which saves:
     `omabox -b default lua 'hl.dispatch(hl.dsp.window.close())'`.

  The game is not ptrace-attachable in the box. To trace it, run it under `gdb -batch -x script --args …` inside `omabox run -d -- sh -c "…"`.
- **Throwaway tools** (never committed):
  - `/tmp/acpatch9.py` (the v6 header patcher) gains two ops:
    - `standing=f:value` writes int16 at offset 588 + 2f;
    - `champions=mask` writes a byte at 604.
  - `/tmp/acview9.sh WORLD ops…` closes the game, patches, relaunches, presses F3 and prints the screenshot path.
- **Deferred items:** the repo has no remote, so AGENTS.md's GitHub-issue rule cannot be applied. List deferred items in the final report and in As built.

## Decisions (fixed; workers do not revisit them)

1. **One mob type for every faction member.**
   - `MOB_MERCHANT` (7) and `MOB_ELDER` (8) are deleted.
   - `MOB_BOSS` becomes 7 and `MOB_FOLK` = 8, with `NUM_MOB_TYPES` 8.
   - A folk carries `MOB.faction`, `.role` and `.fclass`. Roles and classes are data tables in `src/folk.asm`, not new mob types.
   - The 0.9 merchant and elder become folk of faction Villagers with role TRADER and role LEADER. They keep their models, screens and positions.
2. **Folk are never saved,** as 0.9 village NPCs were not. `mobs_save` keeps types 1..6 only.
   - Camp and village members are re-created from the site plan.
   - Patrols are re-created from road edges, and travellers spawn near the player.
   - Persistent state lives in the header: standings and champions-defeated bits. It also lives in `SITESTATE.flags` (captive freed).
3. **Reputation** is a signed int16 per faction in `WORLDHDR.standing[f]`, clamped to −1000..1000. The Ashen Cult is also capped at 199, so it can never become Friendly.
   - Tiers: Hated < −200 ≤ Hostile < 0 ≤ Neutral < 200 ≤ Friendly < 500 ≤ Allied.
   - Only player kills (the mob was `tagged`) change standing:
     - killing a member costs −10 with its faction (−50 for a LEADER or CHAMPION);
     - every rival of the victim's faction gains +5.
   - Tribute gives +1 per 5 coins or +1 per wanted item.
   - Freeing a captive gives +25 to the captive's faction.
   - Standings never decay.
4. **Rivalries** (symmetric) are Villagers↔Bandits, Bandits↔Stonekin, Cult↔Beastfolk and Cult↔Villagers. The same table drives NPC fights and the +5 rule.
5. **Hostility to the player.** A folk fighter (GUARD, PATROL, or an awake CHAMPION) targets the player when every condition holds:
   - the game is in Survival, the difficulty is not Peaceful, the player is alive and not hidden in smoke (`combat_stealth_t <= 0`);
   - and either the faction's standing is < 0, or this folk is provoked (`MOB.provoked > 0`).

   The other roles never attack. Hitting any folk provokes it, and every fighter of its faction within 16 blocks, for 600 steps. It also wakes a champion and makes non-fighters flee.
6. **Rival fights.** Fighters attack folk of a rival faction (any role except CAPTIVE) within 16 blocks, in every mode and at every difficulty. Folk ignore monsters, and monsters ignore folk.
7. **Re-creation.** Camp and village members are re-created every 60 steps:
   - a site seen for the first time this session is populated fully while its centre is within 96 blocks;
   - after that, a missing member is re-created only while the player is 32..96 blocks from the site centre.

   So a camp you cleared stays clear while you stand in it, and a world loaded inside a village is populated at once.
8. **Interaction gates:**

   |Who|Opens at|Below the gate|
   |---|---|---|
   |Leader|Neutral or better|"<Faction> leader won't speak with you" banner|
   |Camp/village trader|Friendly or better|"<Faction> won't trade with you yet" banner|
   |Travelling trader|Neutral or better|"<Faction> won't trade with you yet" banner|
   |Shrine|any standing|—|

   - The Villagers' leader opens the existing elder dialog (`ST_DIALOG`), with the quest chain and respec.
   - The other leaders open a new informational screen. Leader quests and allied rewards are 0.11's arcs.
9. **Champions.** There is one named champion per faction: a champion slot in every camp of that faction, and one in every village for the Villagers.
   - It is spawned asleep while `WORLDHDR.champions` bit f is clear.
   - It wakes when hit, or when its faction's standing is Hated.
   - It is elite, at player level + 5, with a guaranteed class legendary.
   - Its death by the player sets bit f, and it never appears again.
10. **Patrols and roads.**
    - Within each super-region (1536×1536 blocks, `camp_plan`'s unit), the camps present are chained in faction order: Bandits → Cult → Beastfolk → Stonekin, skipping absent ones.
    - Each consecutive pair is a road: 3 wide, GRAVEL on the surface, skipped where the surface is at or below sea level (96).
    - Each road has one patrol of 3 fighters of the start camp's faction.
    - A patrol's position is a pure function of the road and `game_time`. It is materialised as mobs when that position is 48..96 blocks from the player, at most once per 36000 steps per road.
    - Roads to villages are out of scope.
11. **Tile ids above 255.** Mob model tiles become 16-bit, and the new faction skins live at atlas tiles 304..323. Rows 304..511 are unused today, and `TILE_BEGIN` already handles ids ≥ 256.
    - Block tiles stay bytes.
    - The shrine uses the last free byte tiles 228 and 229.

## Contracts (wave 0 writes `common.inc`; every worker codes against this)

### `src/common.inc`

- **Mob types:**
  - `MOB_BOSS 7`, `MOB_FOLK 8`, `NUM_MOB_TYPES 8`.
  - `MOB_MERCHANT` and `MOB_ELDER` are deleted.
- **Roles:**
  - `ROLE_NONE 0`, `ROLE_LEADER 1`, `ROLE_TRADER 2`, `ROLE_GUARD 3`, `ROLE_WORKER 4`, `ROLE_CAPTIVE 5`, `ROLE_CHAMPION 6`, `ROLE_PATROL 7`, `ROLE_TRAVELLER 8`, `NUM_ROLES 9`.
  - The fighters are GUARD, CHAMPION and PATROL.
- **Classes:** `FCLASS_NONE 0`, `FCLASS_ARCHER 1`, `FCLASS_BRUTE 2`, `FCLASS_ACOLYTE 3`, `FCLASS_BERSERKER 4`, `NUM_FCLASSES 5`.
- **Folk flags:** `FF_ASLEEP 1`, `FF_RAGE 2`.
- **Tiers:**
  - `TIER_HATED 0`, `TIER_HOSTILE 1`, `TIER_NEUTRAL 2`, `TIER_FRIENDLY 3`, `TIER_ALLIED 4`.
  - Thresholds: `STANDING_HOSTILE -200`, `STANDING_NEUTRAL 0`, `STANDING_FRIENDLY 200`, `STANDING_ALLIED 500`.
  - Limits: `STANDING_MIN -1000`, `STANDING_MAX 1000`, `CULT_MAX 199`.
- **Projectile owners:** `OWNER_PLAYER 0`, `OWNER_MONSTER 1`, `OWNER_FOLK 2` (`ARROWENT.owner = OWNER_FOLK + faction`).
- **Death causes:** `CAUSE_FOLK 12` (`CAUSE_FOLK + faction`, so 12..16) and `CAUSE_LAST 16`.
- **Screens:** `ST_SHRINE 20`, `ST_LEADER 21`.
- **Blocks:**
  - `SHRINE 130` is a variant group of 5 ids with `block_base` = SHRINE and param = faction.
  - `NUM_BLOCKS 135`; ids 135..143 are unused.
- **Tiles:**
  - `TILE_SHRINE_TOP 228`, `TILE_SHRINE_SIDE 229`.
  - `TILE_FOLK0 304`, `TILE_FOLK_HEAD 0`, `TILE_FOLK_FACE 1`, `TILE_FOLK_TUNIC 2`, `TILE_FOLK_PANTS 3`.
  - Faction f's tile k is `TILE_FOLK0 + 4f + k`, so 304..323.
- **Site state:** `SS_FREED 2` is a `SITESTATE.flags` bit meaning the camp's captive was freed.
- **`MOB` append** (after `.dot_tick`, 32 bytes; `MOB_size` 228 → 260; `mob_spawn` already zeroes everything after BODY):

  ```
  .faction  resb 1   ; FAC_*
  .role     resb 1   ; ROLE_*
  .fclass   resb 1   ; FCLASS_* of a fighter, else 0
  .fflags   resb 1   ; FF_ASLEEP, FF_RAGE
  .wid      resb 1   ; weapon item id, 0 = none
  .captor   resb 1   ; ROLE_CAPTIVE: the faction holding it
  .wdmg     resw 1   ; weapon dmg word (gear roll)
  .target   resd 1   ; 0 none, 1 the player, 2 + slot: another mob
  .provoked resd 1   ; steps the player stays a target whatever the standing
  .patrol   resd 1   ; road key of a patrol member, else 0
  .dest_x   resd 1   ; patrol: the end it walks to (local float); home_x/home_z hold the other end
  .dest_z   resd 1
  .greet    resd 1   ; steps before this guard greets again
  ```

- **`ROADEDGE`** (24 bytes, absolute): `.ax .az .bx .bz` (camp centres, A = start, B = end), `.faction` (A's faction), `.key` = `hash32(sx, sz, 900 + i) | 1`.
- **`WORLDHDR`:**
  - `.standing: resw 8 ; @588` (5 used).
  - `.champions: resb 1 ; @604` (bit f = faction f's champion is defeated).
  - `.pad_a: resb 944 - 605`.
  - Every other offset is unchanged, as are the magic "ACRAFT06" and the existing `%if` layout check.

### Module APIs (owner in brackets; coordinates are local unless marked absolute)

**`src/factions.asm` [W1, new]**

```
faction_reset()                                   ; start standings 200,-100,-100,0,0; champions = 0
faction_validate()                                ; after a load: clamp every standing, Cult <= 199, champions &= 0x1F
faction_standing(edi f) -> eax                    ; signed
faction_tier(edi f) -> eax TIER_*
faction_add(edi f, esi delta) -> eax new standing ; clamped; a tier change shows the banner "<Faction>: now <Tier>"
                                                  ; (green RGBA(140,255,90,255) up, red RGBA(255,85,85,255) down)
faction_on_kill(edi f, esi big)                   ; -10 (big: -50) to f, +5 to every rival of f
faction_enemies(edi a, esi b) -> eax 0/1          ; rivalry table; a == b -> 0
faction_hostile(edi f) -> eax 1 when standing < 0
faction_tribute(edi f, esi kind, edx units) -> eax standing gained, 0 = refused (nothing taken)
                                                  ; kind 0: units coins in {5, 50} -> +units/5; kind 1: units of
                                                  ; faction_wanted[f] in {1, 10} -> +units; refused when the
                                                  ; inventory lacks the payment or the faction is at its cap;
                                                  ; plays SND_COIN at 0.7 on success
faction_tier_color(edi f) -> eax RGBA             ; Hated/Hostile RGBA(255,90,90,255), Neutral RGBA(230,230,230,255),
                                                  ; Friendly RGBA(140,255,90,255), Allied RGBA(255,215,60,255)
faction_champion_defeated(edi f) -> eax 0/1, faction_defeat_champion(edi f)
globals: faction_names (dq zstr: "Villagers","Bandits","Ashen Cult","Beastfolk","Stonekin"),
         faction_members ("Villager","Bandit","Cultist","Beastkin","Stonekin"),
         faction_short ("Vil","Ban","Cul","Bst","Stk"),
         tier_names ("Hated","Hostile","Neutral","Friendly","Allied"),
         champion_names ("Captain Aldric","Grisk the Cutthroat","Morvael the Ashen","Hrodna Bloodmane","Thane Durgar"),
         faction_wanted (db APPLE, GOLD_INGOT, ROTTEN_FLESH, PORKCHOP, IRON_INGOT),
         faction_rivals (db bitmasks 0x06, 0x11, 0x09, 0x04, 0x02),
         screen_faction (dd: the faction of the open ST_LEADER / ST_SHRINE / trade screen)
```

**`src/quests.asm` [W1]** — the trade code becomes table-driven:
- `trade_tab` is deleted. The tables are `trade_villagers` (the existing 10 rows, unchanged), `trade_bandits`, `trade_cult`, `trade_beastfolk` and `trade_stonekin`.
- `trade_open(edi faction)` sets `trade_cur` (a TRADEOFFER table), `trade_count` (dd) and `trade_title` (dq zstr).
- `trade_offer`, `trade_can` and `trade_execute` index the current table, and `trade_offer(i)` returns 0 for `i >= trade_count`.
- The initial `trade_cur` is `trade_villagers`, titled "Merchant".
- `test_rpg.asm`'s local copy of the expected rows is renamed from `trade_tab` to `t_trades`.
- `NUM_TRADES` is deleted from common.inc by the integrator at wave-1 integration (workers leave it in place). Its callers become `trade_count`:
  - `quests.asm` `trade_offer` (W1);
  - `rpgscreens.asm` `screen_trade` row loop (W4);
  - `test_rpg.asm` (W1).

**`src/folk.asm` [prep creates; W2 completes]**

```
folk_spawn(edi faction, esi role, edx fclass, xmm0 x, xmm1 y, xmm2 z) -> eax slot / -1
folk_init(edi slot, esi faction, edx role, ecx fclass)  ; fields, speed, health, weapon, element
folk_make_champion(edi slot)                        ; elite, level = player level + 5, FF_ASLEEP
folk_ai(rdi mob) -> eax 0 input set / 1 purposeful heading / 2 use the shared wander
folk_interact(edi slot) -> eax ST_* to open, or 0   ; gates, banners, trade_open, screen_faction, captives
folk_hostile(rdi mob) -> eax 1 when it currently counts as hostile to the player
folk_on_player_hit(rdi mob)                         ; provoke / wake / flee
folk_on_death(rdi mob)                              ; reputation (tagged kills), champion bit + banner
folk_drops(rdi mob)                                 ; weapon, legendary, coins
folk_hit_by(edi idx, esi dmg, edx elem, xmm0 dirx, xmm1 dirz)  ; a rival's projectile hit this mob
folk_name(rdi mob, rsi out) -> rax end (no NUL)     ; the name plate text
folk_travel_tick()                                  ; travelling traders
folk_weapon_affix(edi wid, esi wdmg, edx faction, ecx fclass) -> eax AFX_* element bit or 0   ; pure
```

**`src/mobs.asm` [W2]** — new public symbols beside the hooks:

```
mob_blow_raw(rdi mob, esi base) -> eax             ; physical blow on another mob
folk_strike_mob(rdi attacker, esi target_idx, edx base)   ; melee blow of a folk on another mob
mob_coins, mob_drop, spawn_near_player             ; exported unchanged for folk.asm
```

**`src/structures.asm` [W3]** — new public symbols:

```
roads_edges(edi sx, esi sz, rdx out ROADEDGE[3]) -> eax n        ; main thread (camp_main cache); roads_prepare
                                                                 ; uses the same rule through camp_gen
roads_prepare(rdi GENBUF*)                                       ; generator: fills road_mask before vegetation
road_mask (global, byte[22*22], generator thread only)            ; cell (lx+3, lz+3): 0 none, 1 near, 2 surface
patrol_point(rdi ROADEDGE*, esi time, rdx out dd[3]) ; out: abs x, abs z, 1 = heading to B
patrol_consider(rdi ROADEDGE*) -> eax 1 when it spawned the patrol
structures_mark_freed(edi x, esi z) -> eax 1 when (x, z) lies in a cached camp (SS_FREED set)
```

**`src/render.asm` [W5]** — `render_box16(rdi box, rsi tiles word[6], rdx shades, xmm0..2 tint)` is `render_box` with 16-bit tile ids.

**`src/rpgscreens.asm` [W4]** — adds `screen_shrine` and `screen_leader`; `screen_trade` reads `trade_count`/`trade_title`.

## Design data

### Faction data (W1)

- **Starting standings:** Villagers +200, Bandits −100, Ashen Cult −100, Beastfolk 0, Stonekin 0.
- **Trade tables** (`TRADEOFFER` rows give, give_n → get, get_n):
  - Gear outputs (`item_gear != 0`) roll `LOOT_SHOP` as today.
  - The titles are "Merchant" (Villagers), "Bandit Trader", "Cult Trader", "Beastkin Trader" and "Stonekin Trader".

|Faction|Rows|
|---|---|
|Villagers|the existing 10 rows of `trade_tab`, unchanged|
|Bandits|12 GOLD_COIN → 1 IRON_DAGGER; 20 GOLD_COIN → 1 BOW; 4 GOLD_COIN → 16 ARROW; 6 GOLD_COIN → 1 FLINT_AND_STEEL; 3 GOLD_INGOT → 12 GOLD_COIN; 8 GOLD_COIN → 1 HEALTH_POTION; 40 GOLD_COIN → 1 RING|
|Ashen Cult|15 GOLD_COIN → 1 STAFF; 6 GOLD_COIN → 1 MANA_POTION; 16 ROTTEN_FLESH → 3 GOLD_COIN; 40 GOLD_COIN → 1 AMULET; 10 GOLD_COIN → 2 TNT|
|Beastfolk|3 GOLD_COIN → 4 COOKED_PORKCHOP; 25 GOLD_COIN → 1 IRON_HAMMER; 18 GOLD_COIN → 1 IRON_SPEAR; 6 PORKCHOP → 2 GOLD_COIN; 8 FEATHER → 8 ARROW; 30 GOLD_COIN → 1 IRON_HELMET|
|Stonekin|20 GOLD_COIN → 1 IRON_PICKAXE; 1 DIAMOND → 18 GOLD_COIN; 4 IRON_INGOT → 6 GOLD_COIN; 35 GOLD_COIN → 1 IRON_CHESTPLATE; 60 GOLD_COIN → 1 DIAMOND_PICKAXE; 12 GOLD_COIN → 16 TORCH; 25 GOLD_COIN → 1 DIAMOND|

### Folk roles, classes and combat (W2, folk.asm + mobs.asm)

**Class table:**

|Class|Weapon (tier < 6 / ≥ 6)|Base health|Speed b/s|Attack|
|---|---|---|---|---|
|ARCHER|BOW / BOW|18|2.6|arrow; keeps 6..12 blocks (backs off < 6, closes > 12); shoots when line of sight is clear, then cooldown 50 + rng%30; aim as `ai_skeleton` (`c_arrow_v` 24, lift, spread `t_spread[diff]` at the player, 0.5 at folk); base 3|
|BRUTE|IRON_HAMMER / DIAMOND_HAMMER|32|2.2|melee: closes to reach 2.0; windup 28; hits if the target is within 2.4 blocks with \|dy\| < 1.5; cooldown 70; knockback ×1.5; base `item_attack(wid) − 4`|
|ACOLYTE|STAFF / STAFF|16|2.4|`PROJ_BOLT` at 18 b/s, straight at the target's centre (y + 1.0); keeps 5..10; cooldown 60 + rng%20; base 4|
|BERSERKER|IRON_SWORD / DIAMOND_SWORD|24|3.0|melee as BRUTE: windup 12, cooldown 30, knockback ×1.0, base `item_attack(wid) − 3`. Below half health it sets `FF_RAGE`: speed ×1.3, windup 8, cooldown 20|

- **Non-fighters:** base health 20, speed 2.0. A captive has speed 0.
- **Health** = round(base × (1 + 0.15·(level − 1)) × 2.5 for an elite).
  - `mob_scale` takes `folk_class_health` for `MOB_FOLK`, with the class column for fighters and 20 otherwise.
- **Level:** player level for every folk; the champion is player level + 5.
- **Weapon:**
  - `wid` comes from the table at tier `gear_tier_for_level(level)`.
  - `wdmg = gear_roll(wid, tier, LOOT_MOB)` for guards and patrols, and `LOOT_ELITE` for a champion.
- **Element:**
  - The first affix of `gear_affixes(wid, wdmg)` that is `STAT_ADD_FIRE/FROST/SHOCK/POISON` sets `AFX_MOLTEN/FROZEN/STORM/VENOMOUS` on `MOB.affix`.
  - A Cult ACOLYTE without one gets `AFX_MOLTEN`.
  - `mob_blow`, `mob_melee_hit` and `mob_arrow_flags` then supply the elemental part and the player status unchanged. Only elites show affix names.
- **Damage to the player:**
  - `base_d = max(1, round(base × {0, 0.67, 1.0, 1.33}[difficulty]))`.
  - Melee: `mob_melee_hit(mob, base_d, CAUSE_FOLK + faction, x, z)`. On `HIT_TAKEN` it calls `knock_player` with `c_kb × class knockback`. On `HIT_PARRIED` it applies stun `STUN_PARRIED` + `mob_reel`, as the zombie does.
  - Projectiles: `arrows_spawn(..., owner = OWNER_FOLK + faction, damage = mob_blow(mob, base_d, 0), pickup 0, PROJ_ARROW | PROJ_BOLT, flags = mob_arrow_flags(mob))`.
- **Damage to folk** (rival fights):
  - New `mob_blow_raw(rdi mob, esi base) -> eax` = round(base × 1.5 for an elite × `mob_dmg_mult(level)`), physical only.
  - Melee: `folk_strike_mob(attacker, target_idx, base)`:
    1. `combat_hit_flags = 0`.
    2. `mob_hurt(target, raw, dirx, dirz)`.
    3. If the attacker has an elemental affix bit, `status_apply(target, sts, max(1, raw/2))`.
    4. A fighter target with `target == 0` gets `target = attacker slot + 2`.
- **Targeting** (fighters, re-evaluated every 20 steps through `MOB.timer_b`):
  - Candidates within 16 blocks: the player (Decision 5), and folk of a rival faction (any role except CAPTIVE).
  - The nearest candidate wins.
  - The target is dropped when it dies, leaves 24 blocks, or the player stops qualifying.
- **Steering:**
  - **No target:**
    - Guards walk home when more than 6 blocks away. Otherwise they face a player within 4 blocks, or else return 2 (wander).
    - Patrols steer to `dest`. Within 6 blocks of it they swap `dest`/`home`. After 120 consecutive blocked steps (counted in `MOB.ai_timer`) they also swap.
    - An asleep champion stands still with input 0 and never targets.
    - Leaders, traders, workers and travellers: the 0.9 `.npc` rule (home radius 6, face the player within 4, wander).
    - A captive stands and faces the player within 4.
  - **Fleeing:** a non-fighter with `MOB.panic > 0` runs away from the player or its attacker at speed × 1.5.
- **Greeting:** a GUARD of a Friendly or Allied faction with the player within 4 blocks and `greet == 0` shows the banner "<Member>: Well met, friend" (green) and sets `greet = 1200`.
- **Interaction** (`folk_interact`):
  - LEADER:
    - Villagers at standing ≥ 0 → `ST_DIALOG`.
    - Other factions at standing ≥ 0 → `screen_faction = f`, `ST_LEADER`.
    - Otherwise the banner "<Faction> leader won't speak with you" (red).
  - TRADER: Friendly or better → `trade_open(f)`, `screen_faction = f`, `ST_TRADE`; else "<Faction> won't trade with you yet".
  - TRAVELLER: the same at standing ≥ 0.
  - CAPTIVE:
    - If an awake fighter of `captor` is within 12 blocks → banner "Its guards are watching".
    - Else: `faction_add(captive faction, +25)`, `structures_mark_freed(x, z)`, banner "Freed a <Member> captive (+25)", and the captive is removed (`MOB_NONE`) after an `FX_MAGIC` burst.
  - Other roles → 0.
- **Player hits:** `mob_damage` calls `folk_on_player_hit` when `HF_PLAYER` is set. It:
  - sets `provoked = 600` on the mob and on every fighter of its faction within 16 blocks;
  - clears `FF_ASLEEP`, with the banner "<Champion name> wakes!";
  - sets `panic = 120` on non-fighters.
- **Death** (`folk_on_death`, from `mob_damage .check_dead`):
  - If `tagged`: `faction_on_kill(faction, role == LEADER || role == CHAMPION)`.
  - A tagged CHAMPION also calls `faction_defeat_champion(f)` and shows the banner "<Name> has fallen!" (gold).
- **Drops** (`folk_drops`; `mob_drops` calls it instead of the `t_drops` and hostile-gear blocks for `MOB_FOLK`):
  - GUARD/PATROL: 25% the weapon (`drops_spawn(wid, 1, wdmg, …)`) + `mob_coins(mob, 1 + level/10)`.
  - CHAMPION: the weapon, then `gear_drop_from_mob(mob)` (gear.asm). Its `.boss` branch, today taken for `MOB_BOSS`, is also taken for a `MOB_FOLK` with role CHAMPION: the class legendary, 3 `LOOT_BOSS` rolls and a 25% legendary jewel. Then `mob_coins(mob, 20 + level)`.
  - LEADER: coins 5 + level/5. TRADER/TRAVELLER: coins 3. WORKER/CAPTIVE: nothing.
- **XP:** `kill_xp[MOB_FOLK] = 12`; an elite triples it as today.
- **`mob_is_hostile`** for `MOB_FOLK` returns `folk_hostile(mob)`: 1 for a fighter that is awake and either targets the player or meets Decision 5. So health bars, ability masks, the storm arc and the sleep check treat only hostile folk as hostile.
- **Area effects:** `explode_magic` skips a `MOB_FOLK` for which `mob_is_hostile` is 0. Direct hits (melee, arrows, bolts, bullets, TNT, fire) hit any folk.
- **Travellers** (`folk_travel_tick`, called from `mobs_step` after `mobs_spawn_tick`):
  - **When it runs:** on a step where `game_time % 3600 == 0`, by day (`sky_is_night` false), with no live TRAVELLER, and when `(game_time / 3600) % 3 == 0`. This cadence is deterministic: no rng.
  - **Faction:** the nearest cached `SITE_CAMP` within 512 blocks if its standing is ≥ 0, else Stonekin.
  - It spawns through `spawn_near_player(MOB_FOLK, 24, 17, GROUND_HOSTILE)` + `folk_init(slot, f, ROLE_TRAVELLER, 0)`, with `timer_a = 18000`.
  - When `timer_a` reaches 0 and the player is more than 24 blocks away, it is removed.

### Projectiles (W2, arrows.asm)

- `owner == OWNER_PLAYER` is unchanged.
- `OWNER_MONSTER` is today's mob path.
- `owner >= OWNER_FOLK`:
  1. `mobs_raycast` in front of the block hit. If the nearest mob is a `MOB_FOLK` and `faction_enemies(owner − 2, mob.faction)` → `folk_hit_by(idx, damage, element from flags, dir)` → `.impact`. Otherwise mobs are ignored.
  2. Then today's player test, with cause `CAUSE_FOLK + owner − 2` instead of `CAUSE_SKELETON`. Crossfire can hit a friendly player.

  A folk `PROJ_BOLT` that hits a block takes `.bolt_block` (it fizzles), as today.

### Camps, villages, roads, patrols (W3, structures.asm + worldgen.asm)

- **`camp_plan`:**
  - Plans factions 1..4 only (the Villagers camp is dropped).
  - It adds the acceptance rule "centre `gen_height` ≥ 97".
  - Salts and the other rules are unchanged.
- **Camp layout.** All coordinates are relative to the centre (cx, h, cz), and y is relative to h.
  - Material codes 247..251 in the `BOX` id byte stand for: 247 = SHRINE + f, 248 = wall, 249 = roof, 250 = floor, 251 = post.
  - The rodata table `camp_mat` (4 bytes per faction, rows 0..4, row 0 unused) gives wall, roof, floor and post per faction.
  - `build_camp` copies camp f's row into the generator-only static `box_mat`. `box_fill` translates codes 247..251 through it, and only `build_camp` uses those codes.

  |Faction|wall|roof|floor|post|
  |---|---|---|---|---|
  |Bandits|LOG|PLANKS|COBBLE|FENCE|
  |Cult|MOSSY_COBBLESTONE|COAL_BLOCK|CRACKED_STONE_BRICK|FENCE|
  |Beastfolk|PINE_LOG|WOOL|PLANKS|FENCE|
  |Stonekin|STONE_BRICK|SMOOTH_STONE|COBBLE|COBBLE|

  The `camp_boxes` table, after today's clearing (flatten ±10, AIR to h+12):

  ```
  BOX -10,1,-10, -2,2,-10, 251    BOX 2,1,-10, 10,2,-10, 251     ; palisade with 3-wide gates
  BOX -10,1,10,  -2,2,10,  251    BOX 2,1,10,  10,2,10,  251     ; at x -1..1 (N/S) and
  BOX -10,1,-9,  -10,2,-2, 251    BOX -10,1,2, -10,2,9,  251     ; z -1..1 (E/W)
  BOX 10,1,-9,   10,2,-2,  251    BOX 10,1,2,  10,2,9,   251
  BOX -10,3,-10, -10,3,-10, TORCH  (and the same at (10,3,-10), (-10,3,10), (10,3,10))
  BOX -7,0,-8, -3,0,-4, 250   BOX -7,1,-8, -3,3,-4, 248   BOX -6,1,-7, -4,3,-5, AIR   ; leader hut
  BOX -5,1,-4, -5,2,-4, AIR   BOX -8,4,-9, -2,4,-3, 249   BOX -6,2,-6, -6,2,-6, TORCH_WALL+DIR_W
  BOX -2,0,4, 2,0,8, 250      BOX -2,1,4, 2,3,8, 248      BOX -1,1,5, 1,3,7, AIR      ; champion hut
  BOX 0,1,4, 0,2,4, AIR       BOX -3,4,3, 3,4,9, 249      BOX 1,2,6, 1,2,6, TORCH_WALL+DIR_E
  BOX 3,1,-8, 3,2,-8, 251  BOX 7,1,-8, 7,2,-8, 251  BOX 3,1,-4, 3,2,-4, 251  BOX 7,1,-4, 7,2,-4, 251
  BOX 3,3,-8, 7,3,-4, 249                                                             ; trader stall
  BOX 0,1,0, 0,1,0, 247   BOX -2,1,0, -2,1,0, 251  BOX -2,2,0, -2,2,0, TORCH
  BOX 2,1,0, 2,1,0, 251   BOX 2,2,0, 2,2,0, TORCH                                     ; shrine
  BOX 5,1,4, 7,2,6, 251   BOX 6,1,5, 6,2,5, AIR                                       ; captive pen
  ```

  Plus `place_chest(cx−5, h+1, cz−7, 2)`: chest table 2 = camp loot.

  ```
  loot_camp: 30 GOLD_COIN 2..6, 15 ARROW 4..12, 15 COOKED_PORKCHOP 1..3, 15 IRON_INGOT 1..3, 10 HEALTH_POTION 1..1
  ```

  - Table 2 gets 3 item rolls and no gear (`structures_fill_chest` gets an explicit `table == 2` branch).
  - Explosions must not destroy shrines: `explode_at` skips every block with `block_hardness < 0` instead of only BEDROCK. W2 makes this change in `explode.asm`.
- **Village additions:**
  - `village_boxes` gains `BOX 4,1,4, 4,1,4, SHRINE + FAC_VILLAGERS`, which is literal id 130.
- **Member slots** (role, class, dx, dz; homes at (x + dx + 0.5, h + 1, z + dz + 0.5)):

  |Site|Slots|
  |---|---|
  |Village (Villagers)|LEADER (−6,0); TRADER (6,0); GUARD ARCHER (−12,−12); GUARD BRUTE (12,12); WORKER (−4,4); WORKER (4,−4); CHAMPION BRUTE (−12,12)|
  |Camp (all)|LEADER (−5,−6); TRADER (5,−6); WORKER (−3,2); WORKER (3,2); CAPTIVE (6,5) when `camp_captive[f]` exists and the camp's SITESTATE lacks `SS_FREED`; CHAMPION (0,6) with `champion_class[f]`|
  |Camp guards|GUARD homes in this order: (0,−9), (9,0), (−9,0), (3,9); the count and classes come from the guard table|

  |Faction|Guard classes (in order)|Champion class|Captive (captor → captive faction)|
  |---|---|---|---|
  |Villagers|ARCHER, BRUTE|BRUTE|—|
  |Bandits|ARCHER, BERSERKER, BRUTE, ARCHER|BERSERKER|Villagers|
  |Cult|ACOLYTE, ACOLYTE, BRUTE|ACOLYTE|Beastfolk|
  |Beastfolk|BERSERKER, BERSERKER, ARCHER|BERSERKER|—|
  |Stonekin|BRUTE, ARCHER|BRUTE|Bandits|

  A slot is matched by `MOB_FOLK` + faction + role + home cell (within 0.01). It is spawned with `folk_spawn`; a CHAMPION also gets `folk_make_champion`, and only while `faction_champion_defeated(f) == 0`. A CAPTIVE gets `.captor = f`.
- **`camp_npcs`** (replaces `village_npcs`, every 60 steps from `structures_step`) for every cached `SITE_VILLAGE`/`SITE_CAMP` whose centre column is ready:
  - **First visit:** if the site's (rx, rz, slot) is not in `pop_seen` (64 entries, session-only, ring replacement, cleared by `structures_reset`) and its centre is within 96 blocks → ensure every slot, then insert it.
  - **Later visits:** ensure every slot only while the player is 32..96 blocks from the centre.
- **`structures_mark_freed(x, z)`:** finds the cached camp whose trigger box contains (x, z), takes `site_state`, and ORs `SS_FREED` into its flags.
- **Roads:**
  - **Edges:** `roads_edges(sx, sz)` = consecutive pairs of the camps of `camp_plan(sx, sz)` in faction order, at most 3.
  - **Camp caches:** two caches of 8 entries, keyed by (seed fingerprint `hash32(0,0,0)`, sx, sz): `camp_gen` (generator thread) and `camp_main` (main thread), the same pattern as `plan_gen`/`plan_main`.
  - **`roads_prepare(GENBUF*)`** (called by `gen_column` right before `gen_vegetation`):
    - For the 22×22 cells (lx −3..18, lz −3..18), it collects the edges of every distinct super-region holding one of the window's four corners.
    - For each cell centre it takes the minimum distance d to any segment between camp centres (x + 0.5, z + 0.5).
    - `road_mask` = 2 if d ≤ 1.5, 1 if d ≤ 4.0, else 0.
  - **`gen_vegetation`** (worldgen.asm) skips a candidate cell whose `road_mask != 0`, both trees and tall grass.
  - **`structures_stamp`**, before the site kind loop: for each in-column cell with `road_mask == 2` it takes h = `gen_height`, and if h > SEA_LEVEL it does `gb_set(h) = GRAVEL`, `gb_set(h+1) = AIR`, `gb_set(h+2) = AIR`.
  - Sites are stamped after roads, so clearings and villages override them.
- **Patrols:**
  - **`patrol_point(edge, time)`:**
    - L = round(|AB|), T = time / 30 (2 blocks/s), s = T mod 2L.
    - d = s if s ≤ L, else 2L − s.
    - P = A + (B − A)·d/L (rounded to cells).
    - Heading to B = (s < L).
  - **`patrol_consider(edge)`** spawns when all of these hold:
    - P is 48..96 blocks from the player;
    - no live mob has `patrol == key`;
    - the `patrol_next` table (16 entries {key, next_time}, session-only) allows it;
    - P's column is ready, and the top block at P is solid and not WATER.

    It then spawns 3 `ROLE_PATROL` folk with the first 3 guard classes of the faction (Stonekin: BRUTE, ARCHER, BRUTE).
    - They stand at P + {0, −1.5, +1.5} × the unit perpendicular of AB, at y = top + 1.
    - `patrol = key`, `dest` = the heading end (local), `home` = the other end.
    - It sets next_time = `game_time` + 36000.
  - **`patrols_step`** (every 60 steps, from `structures_step`, in every mode) calls `patrol_consider` for the edges of each distinct super-region containing a corner of the 192×192 box around the player's absolute position.

### Screens, HUD, flow (W4)

- **`ST_LEADER`** (`screen_leader`, panel 260×144, the `screen_dialog` skeleton):
  - Lines, in order:
    - title "<Faction> Leader" (gold);
    - "Standing: N (Tier)" in `faction_tier_color`;
    - the greeting "Prove yourself to us." (Neutral), "You are welcome at our fires." (Friendly) or "You are one of us now." (Allied);
    - "Rivals: <names joined by ', '>";
    - "Champion: <name>" or "Champion: <name> (fallen)".
  - A "Leave" button 100 wide, centred at y + 118.
- **`ST_SHRINE`** (`screen_shrine`, panel 260×150):
  - Title "<Faction> Shrine" (gold), then "Standing: N (Tier)", then "Wanted: <item name>".
  - Buttons 116 wide in two columns at x + 10 and x + 134:
    - row y + 60: "5 coins: +1" and "50 coins: +10";
    - row y + 84: "1 item: +1" and "10 items: +10".

    They are enabled when payable and below the cap, and each calls `faction_tribute(screen_faction, kind, units)`.
  - A line "Coins N, items M" at y + 108, and "Leave" at y + 126.
- **`screen_trade`** draws `trade_count` rows and titles itself with `trade_title`.
- **`app.asm`:**
  - `screens[]` gains `screen_shrine` and `screen_leader`, and the bound becomes `ST_LEADER`.
  - `update_state` (`.screen` list) and `draw_frame` (`.in_view` list) include both states.
  - The `.open` no-container list includes both.
- **`game.asm`:**
  - Right-click on a `MOB_FOLK` → `folk_interact(slot)`; a non-zero result goes to `game_open_screen`, with `game_open_npc` = slot.
  - Right-click on a block with `block_base == SHRINE` (before `.not_cont`) → `screen_faction = id − SHRINE`, `game_open_screen = ST_SHRINE`.
  - `want_guard` does not guard on `MOB_FOLK`.
  - `game_unload_box` also closes `ST_LEADER`.
  - `game_new` calls `faction_reset` after the header is zeroed, and `game_load` calls `faction_validate` in the sanity block.
- **`hud.asm`:**
  - Folk name plates within 10 blocks show `folk_name` in `faction_tier_color(faction)`. A champion's is gold, plus " (asleep)" while `FF_ASLEEP`.
  - Health bars follow `mob_is_hostile`, as today.
  - F3 gains "Standing: Vil N Ban N Cul N Bst N Stk N" after the Camp line, and the quest tracker's F3 offset goes from 132 to 142.
  - `faction_names` is now the factions.asm global (delete hud.asm's copy).
- **`folk_name` texts:**
  - Villagers LEADER "Elder", TRADER "Merchant".
  - Other leaders "<Member> Chief", traders "<Member> Trader".
  - Fighters "<Member> <Class>" (Archer, Brute, Acolyte, Berserker).
  - Workers "<Member> Worker", captives "Captive <Member>", travellers "Travelling <Member>".
  - A champion: its name.
- **`menus.asm`:**
  - `death_causes` gains "Slain by the Villagers", "Slain by Bandits", "Slain by the Ashen Cult", "Slain by Beastfolk" and "Slain by Stonekin" for 12..16, and the clamp becomes `CAUSE_LAST`.
  - `t_version` becomes "AssemblyCraft 0.10".
- **`survival.asm`:** armour reduces causes `CAUSE_FOLK`..`CAUSE_LAST`.

### Blocks and art (W5)

- **Shrine rows (wave 0 writes them; W5 checks them):**
  - Flags SOLID|OPAQUE (3); tiles top `TILE_SHRINE_TOP`, side `TILE_SHRINE_SIDE`, bottom `TILE_STONE_BRICK`.
  - Hardness −1, tool none, harvest level 0, drop 0, stone dig/step sounds, flammable 0.
  - `SHAPE_CUBE`, `block_base` SHRINE, `block_light` 10.
  - Name "Shrine", icon 0, `item_max_stack` 0 (no item form, not in the creative palette).
  - `block_is_usable(SHRINE..SHRINE+4)` = 1.
- **Tiles:**
  - 228 and 229 are draw-free `BMP`s:
    - top: a gold rune ring on grey stone;
    - side: stone brick with a glowing amber rune.
  - 304..323 are `NBMP` 16×16 bitmaps over the light noise (224, 31), drawn after the 0.9 art and before the font in tile order:

    |Faction|Head (sides/top)|Face|Tunic|Pants|
    |---|---|---|---|---|
    |Villagers|skin (225,180,140), brown hair top|as `npc_face`|green (90,140,60) with belt|brown (110,80,50)|
    |Bandits|tan (200,150,110), red bandana top (150,30,30)|black cloth mask on the lower face|dark leather (80,55,35), strap|dark grey (60,60,60)|
    |Ashen Cult|pale (190,185,180), ash hood (70,65,70)|red glowing eyes, ash smudges|charcoal robe (50,45,50), red trim|charcoal (45,40,45)|
    |Beastfolk|brown-grey fur (130,110,90)|white war paint, fangs|fur (150,130,100), crossed straps|dark fur (90,75,60)|
    |Stonekin|grey-brown (150,130,115)|braided beard (170,120,70)|chain grey (140,140,150)|dark brown (80,60,45)|

  - The atlas is byte-identical outside these 22 tiles. Prove it with the 0.9 dump harness.
- **Models** (mobrender.asm):
  - The `PART` macro emits 6 `dw` tiles (P_TILES 24, P_PIVOT_Y 36, P_PIVOT_Z 40, P_SWING 44, PART_SIZE 48), and `DRAW_PART` calls `render_box16`.
  - `FOLK head, face, tunic, pants` macro:

    ```
    PART -0.22,0.0,-0.11, 0.0,0.75,0.11, pants,pants, 0.75,0.0, 1.0   ; left leg
    PART  0.0,0.0,-0.11, 0.22,0.75,0.11, pants,pants, 0.75,0.0,-1.0   ; right leg
    PART -0.25,0.75,-0.15, 0.25,1.45,0.15, tunic,tunic, 0.0,0.0,0.0   ; body
    PART -0.38,0.75,-0.1, -0.25,1.45,0.1, tunic,tunic, 1.4,0.0,-1.0   ; left arm
    PART  0.25,0.75,-0.1, 0.38,1.45,0.1, tunic,tunic, 1.4,0.0, 1.0    ; right arm
    PART -0.2,1.45,-0.2, 0.2,1.95,0.2, head,face, 0.0,0.0,0.0          ; head
    ```

  - There is one 6-part table per faction. The Villagers LEADER/TRADER keep `elder_parts`/`merchant_parts`.
  - Role extras, drawn as one more part:

    |Role|Part box|Tile|
    |---|---|---|
    |LEADER (non-Villagers), hat|(−0.22,1.85,−0.22)–(0.22,2.0,0.22)|`TILE_GOLD_BLOCK`|
    |GUARD/PATROL (not ACOLYTE), helmet|(−0.22,1.7,−0.22)–(0.22,2.0,0.22)|`TILE_IRON_BLOCK`|
    |ACOLYTE, hood|(−0.22,1.7,−0.22)–(0.22,2.02,0.22)|the faction tunic|
    |TRADER (non-Villagers) and TRAVELLER, pack|(−0.2,0.85,0.15)–(0.2,1.35,0.35)|`TILE_CHEST_SIDE`|
    |CHAMPION, crown|(−0.23,1.95,−0.23)–(0.23,2.15,0.23)|`TILE_BOSS_CROWN`|

  - **Tints:**
    - A captive is (0.6, 0.6, 0.6).
    - A champion replaces the elite tint with `champion_tint[f]` = (1,0.95,0.6), (1,0.6,0.6), (0.75,0.6,0.85), (1,0.85,0.5), (0.7,0.85,1).
    - `FF_RAGE` is (1,0.6,0.6) under the hit and wind-up flickers.

## Approach

### Wave 0 — design doc, folk-type prep, contracts (integrator, inline; three commits)

0. Run `git status` and `git log -1`. The tree must be clean except `.omp/` and `.asm-lsp.toml`, with HEAD `f3a8f79` or a descendant that you made.
1. **Design doc.** Copy this plan to `docs/superpowers/specs/2026-11-08-assemblycraft-factions-design.md` and commit "0.10 design: factions, reputation, camps and shrines, folk fighters, roads and patrols, champions".
2. **Prep: one folk type** (behaviour-preserving; commit "0.10 prep: merchant and elder become Villagers folk"):
   - **`common.inc`:**
     - Delete `MOB_MERCHANT`/`MOB_ELDER`; set `MOB_BOSS 7`, `MOB_FOLK 8`, `NUM_MOB_TYPES 8`.
     - Add the `ROLE_*` and `FCLASS_*` defines and the MOB append from Contracts.
   - **`mobs.asm`:**
     - Rebuild every type table (`t_half_w`, `t_height`, `t_speed`, `t_run`, `t_health`, `t_hostile`, `t_burns`, `t_say`, `t_hurt`, `t_drops`, `t_resist`, `hunt_ai`) in id order: monsters 1..6, boss row as row 7, the old merchant row as row 8 (folk); delete the elder row.
     - `mob_spawn`'s level-1 rule, the `.passive` → `.npc` branch and `mob_damage`'s immunity test `MOB_FOLK`.
     - `mobs_save` skips `type >= MOB_BOSS`.
     - Delete `mob_spawn_npc`.
   - **New `src/folk.asm`:**
     - `folk_spawn`: `mob_spawn(MOB_FOLK)` + set faction/role/fclass.
     - `folk_interact`: LEADER → `ST_DIALOG`, TRADER → `ST_TRADE`, else 0.
   - **`structures.asm`:** `ensure_npc` becomes `ensure_folk(faction, role, fclass, dx, dz, SITE*)`, matching faction + role + home and spawning through `folk_spawn`. `village_npcs` calls it with (VILLAGERS, TRADER, 0, 6, 0) and (VILLAGERS, LEADER, 0, −6, 0).
   - **`game.asm`:** the NPC right-click calls `folk_interact` for `MOB_FOLK`; `want_guard` tests `MOB_FOLK`.
   - **`combat.asm` and `explode.asm`:** the villager refusal/skip tests `MOB_FOLK`.
   - **`hud.asm`:** the name plate tests `MOB_FOLK` and picks "Elder"/"Merchant" by role.
   - **`mobrender.asm`:** the `models` rows are in the new order; for `MOB_FOLK`, `mobs_render` draws `elder_parts` when role == LEADER, else `merchant_parts`.
   - **`rpg.asm`:** `kill_xp: db 0,10,2,15,12,10,2,0,0`.
   - **`test_world.asm`:** `MOB_size != 260`.
   - **Tests:** rewrite the tests that spawned merchants/elders to use `folk_spawn(FAC_VILLAGERS, ROLE_TRADER|ROLE_LEADER, 0, …)` (test_mobs npc tests, test_structures village test, test_game unload test).
   - **Check:**
     - `grep -nE "MOB_MERCHANT|MOB_ELDER|mob_spawn_npc" src/*.asm src/*.inc` prints nothing.
     - The build is warning-free; `make test` 154/154.
     - Omabox: in a seed-42 world, at the village (−77, 99, −180), the merchant and elder stand at ±6 and the trade and dialog screens open.
3. **Contracts** (commit "0.10 contracts: factions, shrine blocks, header standings, folk layouts"):
   - **`common.inc`:** everything in Contracts that step 2 did not add (FF_*, TIER_*, STANDING_*, OWNER_*, CAUSE_FOLK/CAUSE_LAST, ST_SHRINE/ST_LEADER, SHRINE + NUM_BLOCKS 135, TILE_SHRINE_*, TILE_FOLK*, SS_FREED, ROADEDGE, WORLDHDR `.standing`/`.champions`/`.pad_a`).
   - **`blockdefs.asm`/`itemdefs.asm`:** the shrine rows from "Blocks and art" (tiles 228/229 stay blank until W5).
   - **`test_world.asm`:** assert `WORLDHDR.standing == 588` and `WORLDHDR.champions == 604`.
   - **Check:** warning-free build, `make test` 154/154.

### Wave 1 — five parallel workers (one `task` batch; commit "0.10 core")

|Worker|Owns (only these files)|Implements|New tests (in this order)|
|---|---|---|---|
|W1 Factions|new `factions.asm`, `quests.asm`, new `test_factions.asm`, `test_rpg.asm`|Faction data, the factions.asm API, table-driven trading with the 5 stock tables|`faction_tiers_and_caps`, `faction_kill_and_rivals`, `shrine_tribute`, `trade_tables`|
|W2 Folk|`folk.asm`, `mobs.asm`, `arrows.asm`, `combat.asm`, `explode.asm`, `gear.asm`, `test_mobs.asm`, `test_combat.asm`, new `test_folk.asm`|Roles/classes/combat, projectiles, the hooks in `mob_ai`/`mob_damage`/`mob_drops`/`mob_scale`/`mob_is_hostile`/`mobs_step`, `mob_blow_raw`, `folk_strike_mob`, the champion branch in `gear_drop_from_mob`, travellers. Removes the `combat_hit_mob` folk refusal and the `mob_damage` folk immunity. `explode_magic` skips non-hostile folk; `explode_at` skips `hardness < 0`, and the existing `explosion_breaks_blocks` test (test_combat.asm) gains: a SHRINE + 1 cell inside the blast stays. `mobs_shift` also shifts `dest_x/dest_z`. Exports `mob_coins`, `mob_drop`, `spawn_near_player`|`folk_spawn_and_weapons`, `folk_targets_and_standing`, `folk_rivals_fight`, `folk_kill_reputation_and_drops`, `folk_projectiles`, `folk_interact_gates`, `folk_travellers`|
|W3 Camps & roads|`structures.asm`, `worldgen.asm`, `test_structures.asm`, `test_worldgen.asm`|camp_plan changes, camp builder and village additions, member slots, `camp_npcs` + `pop_seen`, captives, roads, patrols. Rewrites `village_built_with_npcs` for the 7 village slots and the 32..96 band|`camp_built_with_slots`, `camp_npcs_recreated`, `roads_stamped`, `patrol_spawns_on_road`|
|W4 Screens & flow|`rpgscreens.asm`, `app.asm`, `game.asm`, `hud.asm`, `menus.asm`, `survival.asm`, `test_game.asm`, `test_hud.asm`|Everything under "Screens, HUD, flow"|`faction_save_load`, `shrine_and_folk_dispatch`|
|W5 Art & blocks|`texgen.asm`, `mobrender.asm`, `render.asm`, `blockdefs.asm`, `itemdefs.asm`, `placement.asm`, `test_items.asm`, `test_blocks.asm`|`render_box16`, word `PART` tiles, folk models/extras/tints, tiles 228/229 and 304..323, shrine rows, `block_is_usable`|`shrine_block_tables`|

**Fakes per worker** (scratch only; faithful to Contracts):
- **W2:**
  - factions: a real standings array with the starting values, tiers, `faction_enemies` from the rivals table, `faction_on_kill`, `faction_add` without banners, `faction_champion_defeated`/`faction_defeat_champion`;
  - `trade_open` sets `trade_count`/`trade_title`;
  - `screen_faction`;
  - `structures_mark_freed` returns 1.
- **W3:**
  - the factions fake above;
  - `folk_make_champion` sets elite + `FF_ASLEEP`;
  - prep's `folk_spawn` is real.
- **W4:**
  - the factions fake;
  - `folk_name` writes "Folk";
  - `trade_open` as for W2;
  - a scratch-only patch to prep's `folk_interact` so a TRADER at Friendly or better calls `trade_open(faction)` and sets `screen_faction`, as W2's version does.
- **W1 and W5:** none.

**Test contents** (inputs fixed here; expectations follow Design data):
- **`faction_tiers_and_caps` (W1):**
  - `faction_reset` → standings (200, −100, −100, 0, 0); `faction_tier`: Villagers FRIENDLY, Bandits HOSTILE.
  - `faction_add(CULT, +1000)` → 199.
  - `faction_add(BEASTFOLK, −1500)` → −1000.
  - For Beastfolk set to −200/−201/199/200/499/500, `faction_tier` is HOSTILE/HATED/NEUTRAL/FRIENDLY/FRIENDLY/ALLIED.
  - Going from 190 with +10 leaves `banner_text` = "Beastfolk: now Friendly".
- **`faction_kill_and_rivals` (W1):**
  - From reset, `faction_on_kill(BANDITS, 0)` → Bandits −110, Villagers 205, Stonekin 5, Cult −100.
  - `faction_on_kill(CULT, 1)` → Cult −150, Villagers 210, Beastfolk 5.
  - `faction_enemies(VIL, BAN)` = `faction_enemies(BAN, VIL)` = 1; `(VIL, BST)` = 0; `(CUL, CUL)` = 0.
- **`shrine_tribute` (W1):** start with 60 GOLD_COIN and 12 GOLD_INGOT, Bandits at −100.
  - Coins 5 → −99, 55 coins left.
  - Coins 50 → −89, 5 left.
  - Coins 50 with 5 coins → 0, nothing taken.
  - Items 10 → −79, 2 ingots left.
  - Cult at 199: coins 5 → 0 and nothing taken.
- **`trade_tables` (W1):**
  - `trade_open(STONEKIN)` → `trade_count` 7, offer 1 = DIAMOND×1 → GOLD_COIN×18; `trade_execute(1)` with 1 diamond gives 18 coins.
  - `trade_open(VILLAGERS)` → count 10, rows equal to 0.9's table, title "Merchant".
- **`folk_spawn_and_weapons` (W2):** player level 1.
  - `folk_spawn(BANDITS, GUARD, BRUTE)` → type `MOB_FOLK`, the fields set, `wid` IRON_HAMMER, health 32, speed 2.2.
  - The element rule through a pure helper `folk_weapon_affix(wid, wdmg, faction, fclass) -> eax AFX bit`:
    - a crafted rare IRON_SWORD dmg whose `gear_affixes` include `STAT_ADD_FROST` → `AFX_FROZEN`;
    - common STAFF + Cult ACOLYTE → `AFX_MOLTEN`;
    - common BOW + Bandits ARCHER → 0.
- **`folk_targets_and_standing` (W2):** flat arena, Survival Normal, player at (100.5, 11, 100.5).
  - A Bandits BRUTE guard 8 blocks away at standing −100 → after 40 steps `target == 1` and `mob_is_hostile` 1.
  - Standing 0 → after 40 steps target 0 and hostile 0.
  - `combat_hit_mob` on it → provoked > 0 and target 1, and a second Bandits guard 10 blocks away is provoked.
  - A Villagers guard never targets.
  - At Peaceful with Bandits at −100 → no player target.
- **`folk_rivals_fight` (W2):** Creative, player 60 blocks away.
  - A Villagers BRUTE and a Bandits BRUTE 6 apart → one of them dies within 600 steps, and the standings are unchanged.
  - A Bandits BRUTE and a Cult BRUTE 6 apart → both alive at full health after 600 steps.
- **`folk_kill_reputation_and_drops` (W2):**
  - Kill a Bandits guard through repeated `combat_hit_mob(SRC_MELEE)` → Bandits −110, Villagers 205, Stonekin 5, at least one GOLD_COIN drop.
  - A Cult champion (`folk_make_champion`):
    - asleep: input 0 and target 0 for 100 steps at Cult −100;
    - one hit → `FF_ASLEEP` clear;
    - kill → `WORLDHDR.champions` bit 2 set, and a drop with `item_legendary[id] != 0`.
- **`folk_projectiles` (W2):**
  - Creative, player far; a Bandits ARCHER and a Villagers BRUTE 10 apart in an open arena → within 300 steps an `ARROWENT` with owner `OWNER_FOLK + FAC_BANDITS` exists, and the Villagers brute loses health.
  - Survival, Cult at −100; a Cult ACOLYTE with `AFX_MOLTEN` 8 blocks from the player → within 400 steps `combat_burn_t > 0`.
- **`folk_interact_gates` (W2):**
  - A Bandits TRADER at −100 → returns 0 with banner "Bandits won't trade with you yet"; at 200 → `ST_TRADE` and `screen_faction` 1.
  - A Villagers LEADER → `ST_DIALOG`.
  - A Cult LEADER at −100 → 0; at 0 → `ST_LEADER`.
  - A Villagers CAPTIVE (captor Bandits) with an awake Bandits guard 6 away → 0 and banner "Its guards are watching". After the guard is cleared → Villagers +25 and the captive slot free.
- **`folk_travellers` (W2):**
  - Day: `game_time` = 10800 (09:36), no camps cached, one `folk_travel_tick` → one Stonekin TRAVELLER 24..41 blocks away.
  - At `game_time` = 54000 (night, also a multiple of 10800) → none.
  - At `game_time` = 14400 (day, `14400 / 3600 % 3 != 0`) → none.
  - After its `timer_a` runs out with the player 30 blocks away → removed.
- **`camp_built_with_slots` (W3):** seed 42. Take the first camp of `camp_plan` over super-regions (0, 0), (−1, 0), (0, −1), (−1, −1), in that order, and build it through the `tg_reset` GENBUF grid. With f its faction and `camp_mat[f]` its materials:
  - (x, h+1, z) = SHRINE + f.
  - (x+10, h+1, z+5) = the post material, and (x+10, h+1, z) = AIR (gate).
  - (x−7, h+2, z−6) = the wall material (leader hut).
  - (x−5, h+1, z−7) = CHEST with a GENCHEST of table 2.
  - (x, h+4, z+6) = the roof material (champion hut).
  - Every camp of those 4 super-regions has centre `gen_height` ≥ 97 and faction ≠ VILLAGERS.
- **`camp_npcs_recreated` (W3):** flat arena, a fabricated Bandits camp in `sites[]`, Survival.
  - Player 50 blocks away → after 60 steps: 1 LEADER, 1 TRADER, 4 GUARDs (ARCHER, BERSERKER, BRUTE, ARCHER at their homes), 2 WORKERs, 1 CAPTIVE (faction Villagers, captor Bandits), 1 CHAMPION.
  - `mobs_clear` with the player 20 blocks away → none after 120 steps; player back at 50 → all re-created.
  - With `SS_FREED` → no captive. With champions bit 1 → no champion.
  - A fabricated village → the 7 Villagers slots.
- **`roads_stamped` (W3):** seed 42. Take the first edge of `roads_edges` over super-regions (0, 0), (−1, 0), (0, −1), (−1, −1), in that order. If none of them has an edge, scan sx, sz in −3..3 in row order, and fail when no edge exists anywhere.
  - Sample the points at fractions 0.2, 0.35, 0.5, 0.65 and 0.8 that lie outside every site footprint, with `gen_height` > 96.
  - At each, `gen_column` of its column has GRAVEL at `gen_height` and AIR at +1.
  - No LOG/PINE_LOG/BIRCH_LOG in the cell column of any cell with `road_mask != 0` in those columns.
- **`patrol_spawns_on_road` (W3):**
  - `patrol_point` on a fabricated edge A (0, 0)–B (300, 0): time 0 → (0, 0, to B); 300·30 → (300, 0); 450·30 → (150, 0, to A).
  - On the flat arena with the player at (150, 11, 150), a fabricated edge whose point lies 60 blocks away → `patrol_consider` spawns 3 PATROL folk with `patrol == key`.
  - At 30 blocks → nothing.
  - After `mobs_clear` within 36000 steps → nothing.
- **`faction_save_load` (W4):** temp world dir.
  - `game_new` → the starting standings.
  - Set Bandits 321 and champions 0b101; `game_save`; zero them; `game_load` → 321 and 0b101.
  - Patch `world.hdr` to Bandits 5000 and Cult 400; load → 1000 and 199.
- **`shrine_and_folk_dispatch` (W4):**
  - SHRINE + FAC_STONEKIN in front of the player with `rmb_pressed` → one `game_frame` → `game_open_screen == ST_SHRINE` and `screen_faction == 4`.
  - A targeted Stonekin TRADER at standing 200 → `ST_TRADE` and `trade_title` "Stonekin Trader".
- **`shrine_block_tables` (W5):**
  - For SHRINE..SHRINE+4: flags 3, hardness −1, drop 0, base SHRINE, light 10, tiles (228, 229, `TILE_STONE_BRICK`), `item_max_stack` 0, `block_is_usable` 1, name "Shrine".
  - (The shrine-in-explosion rule is checked by W2 in `explosion_breaks_blocks`.)

**Integration** (integrator):
1. Copy back W1, W2, W3, W4 and W5 in that order, each after a `cmp` against its base.
2. Register the 18 new tests in the table's order.
3. Build warning-free; `make test` = 172/172.
4. Fix seams in the owners' style. Expected seams:
   - unowned tests touching villager immunity or AoE (`test_combat`, `test_melee`, `test_abilities`);
   - `faction_names` moving out of hud.asm;
   - `trade_tab` callers;
   - every `CAUSE_SKELETON` assumption for mob arrows.
5. Omabox smoke: new world, village folk visible, a camp with buildings. Commit.

### Wave 2 — live verification and tuning (integrator)

1. Add the patcher ops `standing=` and `champions=`.
2. Write a throwaway C helper linked against `build/*.o` minus `main.o`, as in 0.9. For seed 42 it prints the nearest camp of each faction (absolute centre, y) and every road edge of the super-regions around (0, 0).
3. Run Verification 3 in order. Fix bugs with a regression test where a unit test can catch it. Commit "0.10 tuning from live checks" if anything changed.

### Wave 3 — V1 readiness sweep (commit "0.10 V1 sweep")

1. Spawn 3 read-only `reviewer` subagents. Each reports file:line, a reproduction and a severity.
   - R1: folk.asm, mobs.asm, arrows.asm, combat.asm, explode.asm, gear.asm (AI, targeting, damage, projectiles, drops, slots).
   - R2: structures.asm, worldgen.asm (camps, roads, patrols, re-creation, pop_seen, determinism).
   - R3: factions.asm, quests.asm, rpgscreens.asm, app.asm, game.asm, hud.asm, menus.asm, survival.asm (reputation, gates, screens, save/load).
2. Fix every crash, save-corruption, softlock and broken-feature finding, each with a regression assertion inside an existing test.
3. Append "As built (deviations from this plan)" and "Deferred" to the design doc. Commit.

## Critical files & anchors

- `src/mobs.asm`:
  - the type tables (97–146) and the `.passive`/`.npc` branch of `mob_ai` (795–847, where `MOB_FOLK` dispatches to `folk_ai` before the `t_hostile` test at 664);
  - `mob_melee_hit`/`mob_blow` (1027–1176);
  - the kill path in `mob_damage` (2737–2872, `.check_dead` ~2822) and `mob_drops` (2595);
  - `mobs_save` (2939), `mobs_shift` (3075).
- `src/structures.asm`:
  - `camp_plan` (726), `build_camp` (1612), `structures_stamp` (1688, roads before the kind loop at 1723);
  - `ensure_npc`/`village_npcs` (2187/2248), `structures_step` (2542);
  - the loot tables (231–251).
- `src/arrows.asm`: the `.creature` and `.player_arrow` branches (275–424); the folk owner branch and cause go here.
- `src/app.asm`: `screens[]` (70–74) and its bound (869), the state lists in `update_state` (705–721) and `draw_frame` (833–853), and the `.open` list (762–779).
- `src/render.asm`: `render_box_px`'s byte tile load at 998 (the `render_box16` twin).

## Verification

1. **Build and tests:** `cd /run/media/octopusman/Games/Experiences/assemblycraft && make clean && make 2>&1 | grep -iE "warn|error"` prints nothing. `make test` ends with `selftest: 172 passed, 0 failed`.
2. **Greps:**
   - `grep -nE "MOB_MERCHANT|MOB_ELDER|mob_spawn_npc|trade_tab\b" src/*.asm src/*.inc` prints nothing.
   - `git status --short` shows only `.asm-lsp.toml` and `.omp/` untracked.
3. **Live checks** (omabox, world `v10a` seed 42, the helper's coordinates, the patcher), each proven by a screenshot (`omabox -b default shot --window assemblycraft --fit 960`) or a patcher `show`:
   - a. **New world:** F3 shows "Standing: Vil 200 Ban -100 Cul -100 Bst 0 Stk 0".
   - b. **Village** (−77, 99, −180), approached from 60 blocks:
     - the Elder, Merchant, 2 guards (helmets), 2 workers and "Captain Aldric (asleep)" plates;
     - a shrine block next to the well;
     - the Merchant's trade opens.
   - c. **Bandits camp** (helper), Survival:
     - the palisade, huts, stall, shrine and pen are visible;
     - guards attack;
     - killing one moves F3 to Ban −110, Vil 205, Stk 5;
     - the death screen after being killed there says "Slain by Bandits".
   - d. **Beastfolk camp,** standing patched to 199:
     - the shrine screen shows "Standing: 199 (Neutral)";
     - "5 coins: +1" (with `slot=0:213:64` coins) shows the banner "Beastfolk: now Friendly";
     - the Beastkin Trader then opens.
   - e. **Captive:** at the Bandits camp in Creative, kill the guards, right-click the captive → banner "Freed a Villager captive (+25)" and F3 Vil +25. Quit and reopen 60 blocks away: no captive returns.
   - f. **Champion:** at the Cult camp, the plate "Morvael the Ashen (asleep)"; patch Cult −300 → he wakes and fights; kill him → banner "Morvael the Ashen has fallen!", a legendary drop, and patcher `show` → champions bit 2. He never reappears after a reload.
   - g. **Road and patrol:** the helper's first edge; the screenshot shows a gravel road with trees beside it intact. Standing 60 blocks from the patrol point at the current time shows 3 patrol members with plates on the road.
   - h. **Rival fight:** a Cult patrol walking to a Beastfolk camp (the helper picks an edge Cult → Beastfolk if seed 42 has one; else patch standings and use any rival pair at a camp gate). Screenshots show the fight; the player's standings are unchanged.
   - i. **Traveller:** stand in the open by day for up to 5 minutes; a "Travelling <Member>" appears, and its trade opens at standing ≥ 0.
   - j. **Persistence:** quit and reopen → standings and champion bits kept, and camp folk re-created when re-approached.
   - k. **Title:** the panorama renders and the version says "AssemblyCraft 0.10".
4. **Performance** (the 0.9 scratch perf patch, never committed): `render_dist` 16, `vsync=0`, `PULSE_SERVER=unix:/nonexistent`, a 2,000-block flight at 16 b/s through a super-region with camps and roads.
   - 0 frames over 50 ms after the initial load; report the max and p99.
   - At render distance 8 inside a village with its 7 folk and a nearby patrol, ≥ 60 FPS.

## Assumptions & contingencies

- **Tunables** (the user may change them later; they are not design choices for the implementer): the −10/−50/+5/+25 reputation amounts, the 25% weapon drop, the 32..96 re-creation band, the 36000-step patrol cooldown, the traveller cadence (3600 steps, 1 in 3, lifetime 18000), the class stats, the trade rows and the champion names.
- **Mob table full.** `MAX_MOBS` stays 64. If a village plus two camps plus a patrol saturate it, then in live checks:
  - `ensure_folk` skips silently (spawn returns −1) and retries next pass;
  - if live checks show camps missing members, reduce camp WORKERs to 1 and record it in As built.
- **Road cost.** If `gen_column` with roads exceeds 0.5 ms per column on average (measure 64 columns as in 0.9), keep the stamp and replace `road_mask`'s per-cell segment test with a bounding-box rejection per segment first.
- **Rival pair missing.** If seed 42 has no rival pair on a chained road within reach for check 3h, prove the fight by unit test only and note it in As built.
- **Unbreakable blocks in explosions.** `explode_at` skipping every `hardness < 0` block also protects BEDROCK, unchanged.

## As built (deviations from this plan)

**Factions and trading (W1)**
- `faction_tribute` returns the standing actually gained after the clamp, and refuses (taking nothing) when that gain would be 0, for example 3 coins.

**Folk (W2)**
- `folk_rivals_fight` runs 900 steps, not 600: with the specified brute numbers (32 health, blows of 5, a 28 + 70 step cycle) the first death lands at step 671.
- `mobs_shift` moves `dest_x/dest_z` only for patrol members (`MOB.patrol != 0`).
- A rival's blow or bolt wakes a sleeping champion silently; the "<Champion> wakes!" banner stays player-only (a Hated standing shows it too).
- New `FF_FOLKDOT` (fflags bit 4, in common.inc): a burn or poison set by another folk's weapon is nobody's kill, so it never moves the player's standing.
- `folk_travel_tick` tries up to 8 spots on its step, since the cadence fires on a single step.
- Explosions no longer remove WATER: its hardness is −1, so the `hardness < 0` rule covers it.
- Extra folk.asm globals: `folk_scare`, `folk_is_fighter`, `folk_base_speed`. `test_npc_immune_and_not_saved` became `test_npc_hurt_and_not_saved`.

**Camps and roads (W3)**
- Extra structures.asm exports for tests: `camp_plan`, `road_mark`, `roads_in_rect`, `camp_main`.
- `patrol_consider` has no explicit WATER test: water is not solid, so the solid-top test rejects it.
- `gen_column` averages 0.20–0.22 ms per column with roads, so the bounding-box contingency was not needed.
- First visit (fixed in the live checks): `ensure_folk` returns 0 only while a slot's column is loading; a full mob table skips the slot (1). A first visit with a full table therefore still marks the site seen, and a cleared camp stays clear while the player stands in it; the skipped folk come back from the 32..96 band. Regression in `camp_npcs_recreated`.

**Screens, HUD and flow (W4)**
- game.asm: only the right click belongs to a folk (talk, and the click is spent: no use, place or potion). The left button reaches heavy, melee, staff and gun as on any mob.
- `screen_trade`'s panel is `26 + 21 × trade_count` high (236 for the Villagers' 10 rows, as before).
- `hud_banner_paint(edi y)` is split out of the banner draw. `screen_shrine` paints a tier banner above its panel, and the HUD skips its own copy under the shrine screen (so it shows once; fixed in the live checks).
- Death strings are the spec's literal texts ("Slain by Bandits"), with a size check on the table.
- A creative left click never breaks a block with `hardness < 0` (a shrine; bedrock as before). Regression in `shrine_and_folk_dispatch`.

**Art (W5)**
- `render_box`, `render_box_px` and `render_box16` share one body, `box_draw`. Outside tiles 228, 229 and 304..323, the atlas is byte-identical to 0.9.
- The helmet and hood boxes are the spec's: they cover the top of the face tile.

**Integration**
- `FF_FOLKDOT`, `GROUND_HOSTILE`/`GROUND_PASSIVE` and `STUN_PARRIED` live in common.inc (each was defined in several files).
- `kill_xp[MOB_FOLK] = 12`. `NUM_TRADES` is gone; `trade_count` replaces it.

**Live checks**
- Mouse look does not reach the game in omabox, so aiming used patched yaw/pitch plus timed movement keys.
- For 3e, the guards watching the captive were removed through a gdb breakpoint on `folk_interact` (MOB.type = 0, like a despawn); the right click itself, the +25, the banner, SS_FREED and its persistence ran through the real code. Player kills are covered by 3c and 3f.
- 3f: the "Morvael the Ashen has fallen!" banner expired before the screenshot. The kill's standing changes, the King's Blade legendary and champions bit 2 were checked live, and the banner text by its unit test.
- 3h: the Cult patrol reached the Beastfolk camp and shot a Beastfolk guard three times with fire bolts (gdb trace on `folk_hit_by`, health 42 → 24); the player's standings did not change. The fight then stood off at the palisade (see Deferred).
- Balance seen live: the four Bandit guards killed a level-5 player with no armour in about 6 s, and the awake Cult champion with his camp at Hated in about 5 s.
- Performance: 2,000-block flight at render 16, vsync off, audio off: 71,843 frames, max 15.8 ms, p99 5.3 ms, p50 1.6 ms, 0 frames over 50 ms. Village with its folk at render 8: 1,045 FPS.

**V1 sweep (three reviewers; structures.asm and worldgen.asm had no findings)**
- A champion that dies some other way than by the player (TNT, a rival) drops a guard's loot. Before, it dropped its legendary hoard and then came back unbeaten, so legendaries could be farmed. Regression in `folk_kill_reputation_and_drops`.
- A fighter keeps its target until it leaves 24 blocks, as specified. Before, the 20-step look-around replaced it with nothing at 16. Regression in `folk_targets_and_standing`.
- A creative pick-block on a shrine gives nothing; before, it put an unplaceable "Shrine" item in the hand. Regression in `shrine_and_folk_dispatch`.

## Deferred

The repo has no remote, so these are listed here instead of GitHub issues.
- Folk steer in straight lines, so rival fighters on either side of a camp palisade stand off instead of going through the gates.
- Leader quests and allied rewards (0.11 arcs), and roads to villages.
- A 0.9 world loads with every standing at 0 (Villagers 0, not +200): the header pad is zero and there is no migration. In a 0.9 world, columns generated before the upgrade keep their 0.9 blocks: a camp whose position moved, or that lies in such a column, has folk but no buildings there, and roads stop at those columns' edges.
- The elder dialog's "Quest complete!" banner is painted under its panel (the shrine's repaint was not applied there).
- Balance: guard and champion damage against an unarmoured player is high (see As built).
