# AssemblyCraft 0.12 — Events: camp defence waves and caravan escorts

## Context

AssemblyCraft is an x86-64 NASM Minecraft-like game at `/run/media/octopusman/Games/Experiences/assemblycraft`.
- It is on git `master` with remote `origin` (github.com/BaLaurent/assemblycraft). At planning time the last commit was `59493d3`, and `make test` passed 262/262.
- 0.10 added factions: 5 factions with standing, camps with LEADER/TRADER/GUARD/WORKER/CAPTIVE/CHAMPION folk, roads with patrols, travelling traders, and rivalries that make rival fighters fight on sight.
- 0.11 added host-authoritative co-op multiplayer.

A friend asked for enemy waves you can trigger. The user turned that into faction **events**:
- a faction camp (in a tent) asks for help, and the player defends it against waves;
- merchant caravans must be escorted on their route through ambushes;
- winning gives faction-themed loot and reputation.

**End state:**
- 4 event kinds play end to end, offline and in co-op.
- `make test` = 283/283 and the build is warning-free.
- `make windows` builds, and the Wine selftest is 283/283.
- The omabox live checks in Verification pass.
- The version string is `0.12.0`.
- `docs/superpowers/specs/2026-11-10-assemblycraft-events-design.md` (this plan plus a final "As built" section) is committed and pushed.

The other ideas in the untracked `feature-requests.md` (defensive gear such as portcullises and bear traps, skateboard, plane, gambling) are separate features: do not touch them, and do not stage that file.

## Decisions (fixed; workers do not revisit them)

1. **One event at a time, world-wide** (offline and online), run only by the host or the offline game. Events are not saved. A world reloaded mid-event has no event; tent blocks left by a quit stay as decoration.
2. **Kinds** (`EVK_*`):

   |Kind|Trigger|Protected NPC|Waves / ambushes|
   |---|---|---|---|
   |`EVK_CAMP` 1, temporary camp|spontaneous or debug: a tent camp built 32..56 blocks from a player, with a LEADER and 2 GUARDs|its LEADER|3 waves|
   |`EVK_SITE` 2, existing camp or village under threat|a site leader whose site is threatened today|that LEADER (a village's is the elder, faction Villagers)|4 waves; all the site's folk defend|
   |`EVK_CARAVAN` 3, free caravan|spontaneous or debug: a merchant (new `ROLE_CARAVAN`) and 2 GUARDs appear 20..32 blocks from a player and go to a point 160..240 blocks away|the merchant|2 ambushes, at 35 % and 70 % of the route|
   |`EVK_ROAD` 4, road caravan|a camp TRADER whose camp is threatened by the caravan rule today|the new merchant|3 ambushes, at 25 / 50 / 75 %|

3. **Faction eligibility.**
   - A temporary camp or free caravan takes a random faction among those with standing ≥ 0. None eligible → no event.
   - Site and road offers need the site faction's standing ≥ 0 (the leader gate).
   - The attackers' faction is a random rival of the defended faction (a random set bit of `faction_rivals[f]`). Every faction has at least one rival.
4. **Attackers.** A wave or ambush is chosen when it starts:
   - If `sky_is_night(game_time)` and the difficulty is not Peaceful, it is monsters: `rng%10` 0..4 ZOMBIE, 5..7 SKELETON, 8..9 SPIDER. No creepers.
   - Otherwise it is raiders: ROLE_PATROL folk of the attacker faction, class `1 + rng%4`.
   - Size = `3 + n + (players − 1)`, where n is the 1-based wave or ambush index and players are those within 64 blocks of the anchor. Cap 8, and never more than `free mob slots − 4`. A size ≤ 0 waits: retry every 60 steps.
   - The first attacker of the last wave or ambush is elite (`make_elite`).
   - Spawn order per attacker: `spawn_at_ground(type, cell x, cell z, GROUND_HOSTILE)` (type `MOB_FOLK` for raiders), then for a raider `folk_init(slot, rival, ROLE_PATROL, class)`, then `mob_set_level(slot, ev.level)`, then `make_elite(rdx = mob)` for the elite, then `patrol = key|2`, `dest = home = the protected NPC's position`, and `provoked = 600` for a raider.
   - Raiders get `provoked = 600`, refreshed every 60 steps, so they also target players in Survival above Peaceful.
5. **Event keys.** `key = EV_KEY_BASE | ((serial & 0x0FFFFFFF) << 2)`, with a new serial for each event.
   - Defenders carry `MOB.patrol = key` and attackers carry `key | EV_KEY_ATTACK` (2).
   - Road keys are odd (`hash|1`), so they never collide.
   - `mobs_shift` already shifts `dest_x/z` for `patrol != 0`.
6. **Combat rules added.**
   - A defender fighter (folk with `patrol != 0 && (patrol & 3) == 0`) also targets non-folk mobs whose `patrol == my.patrol | 2`.
   - A folk arrow hits a non-folk mob whose `(patrol & 3) == 2`. This coarse rule is acceptable because only one event exists at a time.
   - Non-folk mobs with `patrol != 0` walk to `dest_x/z` when they have no player target. Their `.idle` path otherwise wanders.
   - Every step, an attacker monster within 1.8 blocks horizontally and |dy| < 1.5 of a defender folk calls `folk_strike_mob(monster, defender idx, base)` and then waits 60 steps. The bases are zombie 4, spider 3, skeleton 2, and the cooldown lives in the events module's own array.
   - Every 20 steps, `dest` (and `home` for raiders) of every attacker is set to the protected NPC's position.
   - An attacker more than 64 blocks from the anchor (a camp centre, or a caravan's merchant) is removed.
7. **Flow.** States `EVS_*` and step timers, at 60 steps/s:

   ```mermaid
   stateDiagram-v2
     NONE --> OFFERED: spawn camp/caravan
     NONE --> COUNTDOWN: accept site/road offer
     OFFERED --> COUNTDOWN: accept
     OFFERED --> CLEANUP: 18000 steps or NPC dead
     COUNTDOWN --> WAVE: camp, 600 steps
     COUNTDOWN --> TRAVEL: caravan, 600 steps
     WAVE --> BREAK: wave cleared, more waves
     BREAK --> WAVE: 1200 steps
     TRAVEL --> AMBUSH: merchant passes the next threshold
     AMBUSH --> TRAVEL: ambush cleared
     WAVE --> CLEANUP: last wave cleared (WON) / NPC dead (LOST)
     TRAVEL --> CLEANUP: merchant within 4 blocks of dest (WON) / dead, abandoned, blocked (LOST)
     CLEANUP --> NONE: no event mobs or tent left, or 18000 steps
   ```

   - **Spawning a wave or ambush.** It spawns within 300 steps, at most 2 attackers per step with 8 cell tries each.
     - Camps: on `spawn_at_ground` cells within 6 blocks of a point 30 blocks from the anchor, on one random bearing per wave.
     - Caravans: 24 blocks ahead of the merchant along the route, with a random perpendicular offset of ±4..10.
     - If nothing spawned after 300 steps, the wave counts as cleared.
   - **Clearing.** A wave is cleared when no live mob has `patrol == key|2` after its spawn window.
   - **Wave timeout.** 7200 steps after the spawn window, attackers more than 24 blocks from every player are removed.
   - **Abandoned** (states COUNTDOWN..AMBUSH). No player is within 96 blocks of the anchor (camp centre, or merchant) for 3600 consecutive steps.
   - **Caravan walking.** The merchant walks only while a player is within 24 blocks of it and no attacker is alive. Otherwise `FF_HALT` is set.
   - **Stuck caravan.** When the merchant's `ai_timer` reaches 120 (blocked steps), the party hops to `evs_hop_cell` 4..48 blocks ahead. None found → LOST with `EVL_BLOCKED`.
   - **Caravan guards** follow by getting `home = merchant position` every 20 steps.
8. **Results.** There is no penalty for a loss. A win gives:

   |Kind|Standing to defended faction|XP per client (L = level)|Coins per participant|Item rolls|Gear rolls|
   |---|---|---|---|---|---|
   |CAMP|+40|120 + 12L|10 + L/2|2|1|
   |SITE|+60|200 + 20L|20 + L|3|2|
   |CARAVAN|+30|100 + 10L|8 + L/2|2|1|
   |ROAD|+50|180 + 18L|16 + L|3|2|

   - **Standing** is applied once, on the host, with `faction_add`.
   - **XP** is applied on each client in `events_on_ev`, using the local player's own level (`rpg_state + RPGSAVE.level`), and only when the local player is within 96 blocks of `ev_hud.ax/az`.
   - **Loot** is one bundle per participant: players within 64 blocks of the protected NPC, at least 1. It is dropped at the NPC with `drops_spawn` and `mob_coins`, and L there is the NPC's `MOB.level`.
   - **An item roll** picks a weighted row of `ev_loot[f]` and a count in min..max.
   - **A gear roll** picks `ev_gear[f*2 + rng%2]`. Its dmg is `gear_roll(item, gear_tier_for_level(L), LOOT_ELITE)` when `item_gear(item) != 0`, else 0.
   - `ev_loot` rows are (weight, item, min, max), 4 per faction:
     - Villagers: 30 APPLE 3-6, 25 COOKED_PORKCHOP 2-4, 25 IRON_INGOT 2-4, 20 HEALTH_POTION 1-2.
     - Bandits: 30 GOLD_INGOT 1-3, 30 ARROW 8-16, 20 HEALTH_POTION 1-2, 20 TNT 1-2.
     - Cult: 30 MANA_POTION 2-3, 25 HEALTH_POTION 1-2, 25 GOLD_INGOT 1-2, 20 TNT 1-2.
     - Beastfolk: 30 COOKED_PORKCHOP 3-6, 25 ARROW 8-16, 25 FEATHER 4-8, 20 HEALTH_POTION 1-2.
     - Stonekin: 35 IRON_INGOT 3-6, 25 GOLD_INGOT 1-3, 25 TORCH 8-16, 15 DIAMOND 1-1.
   - `ev_gear` pairs:
     - Villagers: IRON_SWORD, IRON_HELMET.
     - Bandits: IRON_DAGGER, BOW.
     - Cult: STAFF, AMULET.
     - Beastfolk: IRON_HAMMER, IRON_SPEAR.
     - Stonekin: IRON_PICKAXE, IRON_CHESTPLATE.
9. **Offers.**
   - **Spontaneous.** When `game_time % 36000 == 0` (every 10 minutes), in Survival, with state NONE:
     - an even `game_time/36000` tries a temporary camp, an odd one tries a free caravan;
     - the centre player rotates: `k = (game_time/36000) % (1 + nm_ready_count())`; k = 0 is the local `player`, else `nm_centre(k−1)` (fall back to `player` if it returns 0).
     - A failure (no site, no route, no eligible faction, < 7 free mob slots) does nothing until the next cycle.
   - **Site and road offers** (every 60 steps while state NONE; every centre in Survival, and only the forced centre in other modes; `events_force_threat` also runs the refresh at once):
     - For each folk with `patrol == 0` and `evs_site_of` ≠ 0, compute the absolute centre (cax, caz) and `day = game_time / DAY_LENGTH`.
     - A LEADER is threatened when `hash32(cax, caz, 4000 + 2*day) % 3 == 0`.
     - A camp TRADER (faction ≠ Villagers) offers a road caravan when `hash32(cax, caz, 4001 + 2*day) % 3 == 0` and `evs_road_from` finds a road.
     - Both also need standing ≥ 0 and no "done" record for (cax, caz, day, kind).
     - Matching NPCs get `FF_HELP`. NPCs that no longer match lose it.
     - The first time (cax, caz, day, kind) is flagged it is recorded and an `EV_EVENT_OFFER` banner is sent.
     - The rings (16 entries, in memory, reset by `events_reset`) hold {cax, caz, day, kind, done}. Accepting sets `done`.
     - When state ≠ NONE, every `FF_HELP` outside the current offer is cleared.
   - **Offering NPCs** show the plate "<name> - Help!" in gold. Right-clicking one opens the new `ST_EVENT` offer screen (Accept / Decline). A guest's Accept goes to the host as `IA_EVENT_ACCEPT`.
   - **An offered** temporary camp or free caravan expires after 18000 steps.
10. **Cleanup** (state CLEANUP, checked every 60 steps):
    - Remove every mob with `patrol == key` or `key|2` that has no player within 24 blocks.
    - Remove the tent (`evs_remove_tent`) once no player is within 48 blocks of its centre.
    - Then go to NONE.
    - After 18000 steps in CLEANUP, remove the remaining event mobs regardless, forget the tent record (its blocks stay as decoration), then go to NONE.
    - For `EVK_SITE`, the site's folk get `patrol = 0` the moment the event ends. They are never removed.
11. **Persistence.** Nothing is added to the save. `WORLDHDR` is unchanged, and so is the header magic.
12. **Version** `0.12.0`: `hud.asm` `s_dbg_title` (line ~68), `menus.asm` `t_version` (line 114), and the Makefile `windows-zip` file name.
13. **Text** is in English in game.
    - **Banners** (≤ 63 characters):
      - OFFER:
        - CAMP: "A <Faction> camp asks for help nearby".
        - SITE: "The <Faction> camp is under threat!", or "The village is under threat!" for faction Villagers.
        - CARAVAN and ROAD: "A <Faction> caravan needs an escort".
      - START: "Defend the camp! <n> waves" / "Escort the caravan!".
      - WAVE: "Wave <w>/<n>: raiders!" / "Wave <w>/<n>: monsters!" / "Ambush!".
      - WON: "The <Faction> camp is safe!" / "The village is safe!" / "The caravan has arrived!".
      - LOST, `EVL_DIED`: "The <Faction> camp has fallen" / "The village elder has fallen" / "The caravan was lost".
      - LOST, `EVL_ABANDONED`: "Event abandoned".
      - LOST, `EVL_BLOCKED`: "The caravan turned back".
    - **Sounds**: OFFER `SND_VILLAGER` 0.8; START and WAVE `SND_WARCRY` 0.8; WON `SND_QUEST` 1.0; LOST `SND_SLAM` 0.7.

## Conventions (as 0.11, with these deltas)

The 0.11 conventions are in `docs/superpowers/specs/2026-11-09-assemblycraft-multiplayer-design.md` § Conventions:
- the asm style (SysV, a header comment per function, `movzx`, `sar`);
- the hook pattern (`net_role` / `net_applying`);
- test rules (`test_<name>() → eax`, which restores every global, plus a negative control per new assertion);
- the edit tool only;
- git for the integrator only;
- never stage `.omp/`, `.asm-lsp.toml` or `feature-requests.md`;
- omabox live checks.

The deltas for 0.12:
- **Worker scratch copy:**
  `REPO=/run/media/octopusman/Games/Experiences/assemblycraft; rm -rf /tmp/ac12-<name> /tmp/ac12-<name>-base && mkdir -p /tmp/ac12-<name> && rsync -a --exclude build --exclude .git --exclude .omp $REPO/ /tmp/ac12-<name>/ && rsync -a $REPO/src/ /tmp/ac12-<name>-base/`.
- **Sibling symbols** go in `/tmp/ac12-<name>/src/zz_stub.asm`: faithful fakes where a test needs their behaviour, else `ret`-stubs. They are never copied back.
- **Each worker** registers its tests in its scratch `selftest.asm` and reports:
  - the exact `extern` / `TEST` / `TESTNAME` lines;
  - the `make test` tail;
  - its stubs, its scratch-only patches, and its deviations;
  - every unowned call site.
- **The integrator** copies back only owned files, after a `cmp` against `-base`, so drift is caught (the Makefile, which is not in `-base`, is checked with `git diff --stat Makefile`).
- **Deferred items** become `gh issue create --label need-triage --label ready-for-human`.

## Contracts (wave 0 writes `src/common.inc`; every worker codes against them)

- `ROLE_CARAVAN 9` (after `ROLE_TRAVELLER`). `NUM_ROLES` becomes `10`.
- `FF_HELP 8` (offers an event: gold plate, opens `ST_EVENT`). `FF_HALT 16` (a caravan merchant stands still).
- `ST_EVENT 25` (after `ST_CHAT 24`).
- `IA_EVENT_ACCEPT 2` (after `IA_FREE_CAPTIVE 1`).
- Event codes `EV_EVENT_OFFER 3`, `EV_EVENT_START 4`, `EV_EVENT_WAVE 5`, `EV_EVENT_WON 6` and `EV_EVENT_LOST 7`, after `EV_BOSS_KILLED 2`. Their `arg` layouts:

  |Code|`arg` layout|
  |---|---|
  |OFFER|`kind \| faction<<8`|
  |START|`kind \| faction<<8 \| waves<<16`|
  |WAVE|`kind \| wave<<8 \| waves<<16 \| night<<24`|
  |WON|`kind \| faction<<8`|
  |LOST|`kind \| faction<<8 \| reason<<16`|

- `MT_EVENT_STATE 17`, a free id. It is host → guests, reliable, and its payload is one `EVHUD`.
- `EVK_NONE 0`, `EVK_CAMP 1`, `EVK_SITE 2`, `EVK_CARAVAN 3`, `EVK_ROAD 4`.
- `EVS_NONE 0`, `EVS_OFFERED 1`, `EVS_COUNTDOWN 2`, `EVS_WAVE 3`, `EVS_BREAK 4`, `EVS_TRAVEL 5`, `EVS_AMBUSH 6`, `EVS_CLEANUP 7`.
- `EVL_DIED 0`, `EVL_ABANDONED 1`, `EVL_BLOCKED 2`.
- `EV_KEY_BASE 0x40000000`, `EV_KEY_ATTACK 2`. `EHF_WAIT 1` is an `EVHUD.flags` bit: the caravan waits for a player.
- `struc EVHUD` (20 bytes), with `%if EVHUD_size != 20` / `%error "EVHUD is the MT_EVENT_STATE payload (20 bytes)"`:

  ```
  .kind    resb 1   ; EVK_*
  .state   resb 1   ; EVS_*
  .wave    resb 1   ; current wave / ambush (1-based), 0 before the first
  .waves   resb 1   ; total waves / ambushes
  .faction resb 1   ; defended faction
  .left    resb 1   ; live attackers
  .protect resb 1   ; mob slot of the protected NPC, 255 none
  .flags   resb 1   ; EHF_WAIT
  .secs    resw 1   ; countdown / break seconds left (ceil(steps/60)), else 0
  .pad     resw 1
  .ax      resd 1   ; absolute cell x: camp centre, or caravan destination
  .az      resd 1
  ```

### Module APIs (owner in brackets; coordinates are local floats unless marked absolute)

**`src/events.asm` [W1, new]**, the host state machine plus the client-side HUD state:

```
events_reset()                                   ; clear ev, rings, ev_hud (state NONE), ev_sent, strike cooldowns
events_step()                                    ; host/offline, once per sim step (mobs_step, after folk_travel_tick)
events_shift(edi dx, esi dz)                     ; origin moved: shift every stored local position
events_accept(edi mob_slot) -> eax 1 started / 0 refused   ; validates MOB_FOLK + FF_HELP + state rules
events_offer_kind(edi mob_slot) -> eax EVK_*     ; any client: ev_hud.state==OFFERED && ev_hud.protect==slot
                                                 ; -> ev_hud.kind; else LEADER -> SITE, TRADER -> ROAD, else 0
events_on_ev(edi code, esi arg)                  ; every client, from event_apply: banner, sound, XP (WON)
events_net_apply(rdi payload, esi len)           ; guest: copy a >= 20-byte EVHUD into ev_hud
events_state_send(edi peer_slot)                 ; host: net_send_to(slot, MT_EVENT_STATE, ev_hud, 20, 1)
events_spawn_camp(rdi BODY*) -> eax 1/0          ; temporary camp offer near that player (any mode)
events_spawn_caravan(rdi BODY*) -> eax 1/0       ; free caravan offer near that player (any mode)
events_force_threat() -> eax 1/0                 ; debug: nearest site leader (<= 96 blocks of `player`) and that
                                                 ; camp's trader are threatened today, whatever the mode or day hash
events_skip() -> eax 1/0                         ; debug: WAVE/AMBUSH remove attackers; COUNTDOWN/BREAK timer = 1;
                                                 ; TRAVEL hop the party to the next threshold (or dest - 6 blocks)
events_finish(edi win)                           ; debug: WON now (1) or LOST with EVL_ABANDONED (0)
events_status(rdi out) -> rax end                ; debug text, no NUL: "none" | "<Kind> <Faction> <state> w/n (k left)"
ev_wave_size(edi n, esi players, edx free_slots) -> eax   ; pure: min(3+n+players-1, 8, free-4), floored at 0
globals: ev_hud (EVHUD), ev_kind_waves (db 0,3,4,2,3), ev_kind_rep (db 0,40,60,30,50)
```

**`src/evsites.asm` [W2, new]**, the world geometry of events: tents, routes, sites and hops:

```
evs_find_camp_site(rdi BODY*, rsi out dd[3]) -> eax 1/0   ; out = local cx, H, cz
evs_build_tent(edi cx, esi H, edx cz, ecx faction) -> eax blocks placed   ; records absolute cells + ids
evs_remove_tent() -> eax blocks removed          ; a cell becomes AIR only while it still holds the recorded id;
                                                 ; then the record is forgotten
evs_forget_tent()                                ; forget the record, leave the blocks
evs_tent_placed() -> eax recorded count
evs_find_route(edi ax, esi az, rdx out dd[2]) -> eax 1/0  ; absolute start -> absolute dest 160..240 away
evs_road_from(edi cax, esi caz, rdx out dd[2]) -> eax 1/0 ; absolute camp centre -> absolute other end of a
                                                 ; road of length 64..900 (first match in roads_in_rect order)
evs_site_of(rdi mob, rsi out dd[2]) -> eax EVK_SITE / EVK_ROAD / 0  ; absolute site centre from the slot home
evs_hop_cell(xmm0 x, xmm1 z, xmm2 dirx, xmm3 dirz, rdi out dd[2]) -> eax ground y, or -1
                                                 ; first ground cell 4..48 blocks ahead (local cells out)
evs_ground(edi x, esi z) -> eax ground y, or -1  ; leaf-ish: column ready, top <= 250; TALL_GRASS / SNOW_LAYER
                                                 ; top -> the block below; that block must be solid+opaque
                                                 ; (block_flags), not BEDROCK / LEAVES / PINE_LEAVES /
                                                 ; BIRCH_LEAVES, and the cell above it is not WATER / LAVA
```

**[W3]** `folk.asm`, `mobs.asm`, `arrows.asm`, `mobrender.asm`. No new public symbols except `events_step` being called from `mobs_step`.

**[W4]** `hud.asm` adds:
- `hud_heading_dist(xmm0 dx, xmm1 dz, rdi dst) -> rax end`
- `hud_mob_bar(rdi mob, rsi name, edx top)`
- `hud_event_bar(edi top) -> eax 1 drawn`
- `hud_event(edi y)`
- `hud_quest(edi y)` now returns eax = the y under its note (y + 30 when drawn, else y).

W4 also adds `screen_event` in `rpgscreens.asm` and `nx_on_event_state` in `netmisc.asm`.

## Approach

### Wave 0 — integrator (in the repo)

1. **Pre-flight** (AGENTS.md: parallel agents may have pushed):
   - `git fetch origin && git status -sb`.
   - If master is behind, run `git pull --ff-only`.
   - If there are uncommitted tracked changes, stop and report.
   - Run `make && make test` and record the baseline (expected 262/262).
2. **Write the Contracts block** into `src/common.inc`, next to the existing groups: roles near `:510-519`, FF near `:526-528`, ST near `:841`, IA and EV near `:1759-1761`, MT near `:1695`, and the EVHUD struct plus its size check after `MOBREC`.
   - Run `make` (all new constants unused) and `make test` (262/262).
3. **Copy this plan** to `docs/superpowers/specs/2026-11-10-assemblycraft-events-design.md`.
4. **Commit** `0.12 events: contracts and design doc`, staging only `src/common.inc` and the doc.
5. **Create the 4 scratch copies** `/tmp/ac12-{events,evsites,folk,uinet}` and start W1–W4 in one parallel batch. Each worker gets:
   - this whole plan file;
   - its section below;
   - the Conventions;
   - "skip `make windows`".

### Wave 1 — four parallel workers (disjoint files)

#### W1 `events` — owns `src/events.asm` (new) and `src/test_events.asm` (new)

- **Module state.** It holds `ev` (internal):
  - kind, state, faction, rival, wave, waves, timer, key, serial, protect slot;
  - anchor x/z (local floats);
  - route start sx/sz and dest dx/dz (local floats);
  - route length, next ambush index, spawn-window steps, spawned count, abandon counter, cleanup steps, level;
  - tent centre (local);
  - the loss/win reason.

  It also holds:
  - `ev_strike_cd` dd[MAX_MOBS];
  - the `ev_seen` ring of 16 × {cax, caz, day, kind byte, done byte};
  - the forced threat (cax, caz, day, valid);
  - `ev_sent` (20 bytes).

  `ev_hud` is rebuilt from `ev` at the end of every `events_step`.
- **`events_step` order:**
  1. Decrement strike cooldowns.
  2. Run the spontaneous cadence (Decision 9).
  3. Every 60 steps while state is NONE, refresh the site and road flags.
  4. Run the state handler.
  5. Do the 20-step and 60-step maintenance (dests, guard homes, provoked, leash).
  6. Do the monster strikes.
  7. Rebuild `ev_hud`.
  8. If `net_role == NET_ROLE_HOST` and the 20 bytes differ from `ev_sent`, call `net_out(MT_EVENT_STATE, ev_hud, 20, 1)` and copy to `ev_sent`.
- **Helpers (internal):**
  - `ev_players_near(xmm0 x, xmm1 z, xmm2 r2) -> eax`: counts the local `player` plus `nm_centre(k)` bodies for k = 0.. until rax is 0.
  - `ev_free_slots() -> eax`: counts `MOB_NONE` in `mobs`.
  - `ev_pick_faction() -> eax f / -1`.
  - `ev_pick_rival(edi f) -> eax`.
  - `ev_spawn_attacker(edi idx_in_wave, esi last) -> eax slot / -1`: tries 8 cells around the wave point (Decision 7), then applies the spawn order of Decision 4.
  - `ev_reward()`, following Decision 8.
  - `ev_end(edi won, esi reason)`:
    - sends `net_event_out(EV_EVENT_WON / EV_EVENT_LOST, arg)`;
    - for a win, calls `faction_add(f, ev_kind_rep[kind])` and `ev_reward`;
    - clears `FF_HELP` / `FF_HALT` on the event NPCs (keeping `FF_HALT` on a winning merchant);
    - for SITE, sets `patrol = 0` on the site folk;
    - sets state CLEANUP.

  `net_event_out` applies locally, offline as well.
- **`events_spawn_camp(body)`** — return 0 when:
  - the state is not NONE; or
  - `ev_free_slots() < 7`; or
  - `ev_pick_faction` gives −1; or
  - `evs_find_camp_site` fails.

  Otherwise:
  1. Call `evs_build_tent(cx, H, cz, f)`.
  2. Spawn the LEADER at (cx−2+0.5, H+1, cz−2+0.5) with `folk_spawn(f, ROLE_LEADER, 0, …)` and `FF_HELP`.
  3. Spawn the GUARDs at (cx+2+0.5, H+1, cz−2+0.5) with `FCLASS_ARCHER` and at (cx−2+0.5, H+1, cz+2+0.5) with `FCLASS_BERSERKER`.
  4. Give all three `patrol = key` and `mob_set_level(slot, level)`. The level is the body's: `rpg_state + RPGSAVE.level` for `player`, or the `edx` that `nm_centre` returned (keep it when picking the centre). The free caravan uses the same level rule.
  5. Set state OFFERED with timer 18000, protect = the leader, anchor = (cx+0.5, cz+0.5), waves 3.
  6. Send `net_event_out(EV_EVENT_OFFER, …)`.
- **`events_spawn_caravan(body)`:**
  1. Find a ground cell P 20..32 blocks from the body, over 16 random bearings, using `evs_ground`.
  2. Call `evs_find_route(P absolute) → dest`.
  3. Spawn the merchant `ROLE_CARAVAN` with `FF_HELP | FF_HALT` at P, and 2 GUARDs (`FCLASS_BRUTE`, `FCLASS_ARCHER`) offset ±1.5 perpendicular to the route. Give all of them `patrol = key`, the merchant `dest = dest`, and the guards `home = P`.
  4. Set state OFFERED with timer 18000, waves 2, thresholds {0.35, 0.70}.

  It has the same 0-returns as the camp.
- **`events_accept(slot)`.** Refuse unless `mobs[slot].type == MOB_FOLK` and `fflags & FF_HELP`. Then:
  - **OFFERED, and the slot is the protected NPC:** clear `FF_HELP`, set state COUNTDOWN with timer 600, and send START.
  - **State NONE, LEADER:** `evs_site_of → EVK_SITE` gives the centre.
    1. Take a new key.
    2. Give every folk with faction f, `patrol == 0`, role ≠ CAPTIVE, and home within 12 blocks (camp) or 17 blocks (village, faction Villagers) of the centre `patrol = key`.
    3. Protect = the leader; level = its `MOB.level`; waves 4; anchor = the centre (local).
    4. Mark the `ev_seen` entry done, clear all `FF_HELP`, set COUNTDOWN, and send START.
  - **State NONE, TRADER:** `evs_site_of → EVK_ROAD` gives the centre C, and `evs_road_from(C) → E`.
    1. Let dir = normalised E−C. Start S = C + dir·16, dest D = E − dir·16.
    2. Spawn the merchant (`ROLE_CARAVAN`, `FF_HALT`, no `FF_HELP`, `dest = D`) and 2 guards (`FCLASS_BRUTE`, `FCLASS_ARCHER`, `home = S`) at S and ±1.5 perpendicular, with y = `evs_ground` + 1, all with `patrol = key` and the trader's `MOB.level` as level. If that fails (no ground, or < 7 free slots), refuse.
    3. Set waves 3 with thresholds {0.25, 0.50, 0.75}, mark the entry done, COUNTDOWN, and START.
- **State handlers** follow Decisions 6, 7 and 10.
  - COUNTDOWN → WAVE starts wave 1. A caravan goes to TRAVEL and clears `FF_HALT` when the walking rule allows.
  - The merchant's route progress is the projection of its position onto S→D, divided by the length.
  - Every wave and ambush start sends WAVE with `night = sky_is_night(game_time) && difficulty != DIFF_PEACEFUL`. Read the difficulty and mode the way `folk_wants_any` does (`folk.asm:424-443`).
  - **Protected NPC check, every step:** it is alive when `type == MOB_FOLK && patrol == key`. Otherwise:
    - LOST with `EVL_DIED` in COUNTDOWN..AMBUSH;
    - CLEANUP without a banner in OFFERED.
- **`events_on_ev`** shows the banners and plays the sounds of Decision 13. Build the text with `faction_names`. For WON it calls `rpg_add_xp` per Decision 8.
- **`events_status`** examples: "none", "Camp Bandits wave 2/3 (4 left)", "Caravan Stonekin travel 1/2". The kind names are Camp / Site / Caravan / Road, the state names offered / countdown / wave / break / travel / ambush / cleanup.
- **Tests** (scratch faithful fakes for W2's `evs_*`: a tent site on a flat test plateau, and `evs_find_route` returning +40 x):
  1. **`test_events_wave_size`**:
     - (1,1,64) → 4, (4,1,64) → 7, (4,3,64) → 8;
     - (3,1,6) → 2, (1,1,5) → 1, (1,1,4) → 0.
  2. **`test_events_camp_flow`** (Survival, Normal, daytime `game_time`):
     - Spawn: OFFERED, the leader has `FF_HELP`, and 2 guards carry `patrol == key`.
     - Accept, then step 600: 4 attackers appear, ROLE_PATROL, rival faction, `patrol == key|2`, `provoked > 0`.
     - Remove them and step: BREAK.
     - Repeat to the end: the banner is "The <F> camp is safe!", the standing gained +40 exactly beyond the kill-free baseline, at least 3 drops exist, and the state is CLEANUP.
  3. **`test_events_night_wave`**:
     - Night `game_time`: the wave's attackers are ZOMBIE / SKELETON / SPIDER with `key|2`.
     - Peaceful at night: they are folk raiders.
  4. **`test_events_leader_dies`**: the leader removed during WAVE → LOST, the banner "… has fallen", unchanged standing, CLEANUP.
  5. **`test_events_abandon`**: the player is moved 120 blocks away, then 3600 steps → "Event abandoned". At 3599 steps it is still in progress.
  6. **`test_events_monster_strike`**: an event zombie 1 block from the defender leader. After one step the leader's health is lower; after the next step it is not lower again (cooldown).
  7. **`test_events_caravan_flow`**:
     - Free caravan, accept, countdown.
     - With the player within 24 blocks, the merchant is not `FF_HALT`.
     - Teleporting the merchant past 35 % → AMBUSH and `FF_HALT`.
     - Clearing the ambush → TRAVEL.
     - The merchant placed within 4 blocks of dest → "The caravan has arrived!" and +30.
  8. **`test_events_threat_flags`**:
     - A camp LEADER of faction Stonekin with home = centre + (−5, −6) + 0.5 (the real camp slot, so the integrated `evs_site_of` finds the centre); loop `day` 0..30 to find a day with `hash32(cax, caz, 4000 + 2*day) % 3 == 0` and set `game_time` to it.
     - After a 60-step boundary, `FF_HELP` is set and the banner says "under threat".
     - Standing −1 → the flag is cleared.
     - A day with `%3 != 0` → no flag.
  9. **`test_events_net`**:
     - Host role with the `net_capture` seam: a state change emits exactly one `MT_EVENT_STATE` of 20 bytes equal to `ev_hud`; a step without change emits none; `events_state_send(1)` captures one.
     - `events_net_apply` with a 20-byte payload fills `ev_hud`; with 19 bytes it does nothing.

#### W2 `evsites` — owns `src/evsites.asm` (new) and `src/test_evsites.asm` (new)

- **`evs_find_camp_site(body, out)`.** Up to 24 tries. Each try takes a random bearing and a distance of 32..56 from the body, giving centre (cx, cz) as local cells.
  - **Reject the try when any of these holds:**
    - any of the 81 cells of x, z ∈ [−4, 4] has `evs_ground` = −1;
    - the grounds of those cells span more than 1;
    - any cached `sites[]` entry of kind `SITE_VILLAGE` or `SITE_CAMP` lies within 64 blocks.
  - **Result:** H = max ground; out = cx, H, cz.
- **`evs_build_tent`** places blocks with `world_set`, which replicates to guests. It writes only into cells that hold AIR, `TALL_GRASS` or `SNOW_LAYER`. Each placed block is recorded as absolute (x, y, z, id) in a 64-entry record.
  - **Roof** material is `ev_tent_roof db WOOL, PLANKS, COAL_BLOCK, WOOL, SMOOTH_STONE` (by faction). Posts are `FENCE`. g = that column's ground.
  - **Leader canopy:**
    - posts at (−4,−4), (0,−4), (−4,0), (0,0), from g+1 to H+2;
    - roof at y = H+3 over x, z ∈ [−4, 0].
  - **Supply canopy:**
    - posts at (2,2), (4,2), (2,4), (4,4), from g+1 to H+1;
    - roof at H+2 over x, z ∈ [2, 4].
  - **Torch posts** at (3,−3) and (−3,3): FENCE from g+1 to H+1, then TORCH at H+2.
  - A new build first forgets the old record.
- **`evs_find_route(ax, az, out)`:**
  - Start from bearing b0 = `rng%8`. Try the bearings b0 + i·45° for i = 0..7, with D = 160 + `rng%81`.
  - Sample every 8 blocks from 8 to D with `gen_height` (pure, main-thread safe, `worldgen.asm:501`). Every sample must be ≥ 98, and |Δ| between consecutive samples (including the start's `gen_height`) must be ≤ 3.
  - The first passing bearing writes dest = start + D·dir.
- **`evs_road_from(cax, caz, out)`:**
  - Use `roads_in_rect(camp_main, cax−8, caz−8, cax+8, caz+8, buf288)`.
  - The first `ROADEDGE` whose A or B equals (cax, caz) gives the other end, provided its length is 64..900.
- **`evs_site_of(mob, out)`** works only for `MOB_FOLK` with `patrol == 0`, from `floor(home_x/z)` plus `world_origin`:

  |Folk|Kind|Centre|
  |---|---|---|
  |ROLE_LEADER, faction Villagers (village elder, slot (−6, 0))|EVK_SITE|home + (6, 0)|
  |ROLE_LEADER, faction 1..4 (camp slot (−5, −6))|EVK_SITE|home + (5, 6)|
  |ROLE_TRADER, faction 1..4 (slot (5, −6))|EVK_ROAD|home + (−5, 6)|

  Anything else → 0. The slots are `structures.asm` `camp_slots` / `village_slots` at `:334-345`. W2 reads them and fails the test if they differ.
- **`evs_hop_cell`** steps 1 block at a time from 4 to 48 along dir, from (x, z). It returns the first cell with `evs_ground` ≥ 0.
- **Tests:**
  1. **`test_evsites_camp_site`**: a flat STONE plateau around the player gives a site; `evs_build_tent` places > 0 blocks; and `world_get` at (cx−2, H+3, cz−2) equals the roof material.
     - A WATER block on the footprint, or a ground span of 2, makes it fail.
     - `evs_remove_tent` restores AIR, except a recorded cell the test changed to STONE, which stays STONE.
  2. **`test_evsites_route`**: with a fixed `gen_seed`, start on land where `gen_height` ≥ 98. The dest distance is within [160, 240], and every 8-block sample re-checked in-test passes. A start inside an ocean, found by scanning `gen_height` < 90, returns 0.
  3. **`test_evsites_site_of`**: camp leader, village elder and camp trader homes give the centres above; `patrol != 0` or a GUARD gives 0.
  4. **`test_evsites_hop`**: water columns for 10 blocks ahead, then stone → the cell 11 ahead (± the step). All water for 48 → −1.
  5. **`test_evsites_road_from`**: for a fixed seed, loop the super-regions (0..3)² with `roads_edges` until a road of length 64..900 is found. `evs_road_from(A)` returns B, and `evs_road_from(B)` returns A.

#### W3 `folk` — owns `src/folk.asm`, `src/mobs.asm`, `src/arrows.asm`, `src/mobrender.asm`, and new tests appended to `src/test_folk.asm`

- **`folk_find_target`** (`folk.asm:1093`, loop `:1155-1187`). At the `cmp MOB.type, MOB_FOLK / jne .next` (`:1156-1157`):
  - A non-folk mob is a candidate only when its type is not NONE, its health is > 0, `my.patrol != 0`, `(my.patrol & 3) == 0`, and `[r12+MOB.patrol] == my.patrol | 2`.
  - Such a candidate jumps to the distance code (`.measure` `:1167`), bypassing the captive and faction tests.
- **`folk_target_at`** (`:1201`, `:1219-1228`) keeps a mob target that passes the same non-folk test.
- **`mobs.asm` `mob_ai` `.idle`** (`:834`). Before the `MOB_BOSS` compare, a non-folk mob with `MOB.patrol != 0` gets this, then `jmp .jump`:
  - When `(dest − pos)² > 9`: `BODY.yaw = yaw_from(dx, dz)`, `INPUT.fwd = 1`, and `dword [rsp+12] = 1` (purposeful).
  - Else: `fwd = 0`.
- **`mobs_step`**: add `call events_step` right after `call folk_travel_tick` (`:2925`), plus the extern.
- **`folk_npc`** (`:991`): a `ROLE_CARAVAN` branch before `.roles` (`:1020`), keeping the panic branch first.
  - With `FF_HALT`: face a player within 4 blocks or stand still, `fwd = 0`, return 0.
  - Otherwise: steer to `dest_x/z` as `folk_idle`'s patrol steering does (`:1328-1349`): `yaw_from`, `fwd = 1`, return 1.
  - Count blocked steps (`BODY.blocked`) in `ai_timer`, resetting it to 0 on a step that is not blocked, exactly as the patrol does (`:1313-1327`). Do not swap ends.
  - `folk_base_speed` uses row 0 (2.0 b/s).
- **`folk_name`** (`:853`): `ROLE_CARAVAN` → member name + " Merchant" (for example "Stonekin Merchant").
- **`folk_interact`** (`:1885`):
  - Before the role switch (`:1902`): `fflags & FF_HELP` → return `ST_EVENT`.
  - `ROLE_CARAVAN` without `FF_HELP` → the `.traveller` path (trade at standing ≥ 0).
- **`folk_drops`** (`:783-801`): `ROLE_CARAVAN` drops 3 coins, like TRADER and TRAVELLER.
- **`mobrender.asm`** (`:249-266`): `ROLE_CARAVAN` gets the TRAVELLER's pack.
- **`arrows.asm`** `.mob_shot` (`:461-462`): a non-folk, non-NONE target with `(MOB.patrol & 3) == 2` goes to the `.hit` / `HIT_POINT` code (`:469`) with the same registers. Other non-folk targets keep going to `.player_arrow`.
- **Tests** in `test_folk.asm`:
  1. **`test_folk_event_targets`**:
     - A GUARD with `patrol K` and a ZOMBIE with `K|2` 8 blocks away → `folk_find_target` = 2 + zombie slot, and `folk_target_at` keeps it.
     - A guard with `patrol 0`, or a zombie with `K2|2`, → 0.
  2. **`test_folk_caravan`**:
     - A `ROLE_CARAVAN` with dest 20 blocks +x and `FF_HALT` clear moves ≥ 4 blocks +x in 180 steps of `mob_update`; with `FF_HALT` it moves < 0.5.
     - `folk_name` is "<Member> Merchant".
     - `folk_interact` gives `ST_EVENT` with `FF_HELP`, and `ST_TRADE` without it at standing ≥ 0.
  3. **`test_mobs_event_march`** (Creative, so no player target): a ZOMBIE with `patrol != 0` and dest 20 blocks +x ends within 4 blocks of dest after 600 steps; a zombie with `patrol != 0` placed 2 blocks from its dest has `INPUT.fwd == 0` after one `mob_ai` call.
  4. **`test_arrows_event_monster`**: an arrow with `owner OWNER_FOLK + f`, aimed at a zombie with `patrol K|2` → the zombie's health drops. With `patrol 0` its health is unchanged.

#### W4 `uinet` — owns `src/hud.asm`, `src/rpgscreens.asm`, `src/app.asm`, `src/game.asm`, `src/netmobs.asm`, `src/netmisc.asm`, `src/netsync.asm`, `src/debugmenu.asm`, `src/menus.asm`, `Makefile`, and new tests appended to `src/test_ui.asm` and `src/test_netmisc.asm`

- **`hud.asm`:**
  - Extract `hud_heading_dist(xmm0 dx, xmm1 dz, rdi dst) -> rax end` from `hud_quest` `:2026-2068`. The text is `s_gap` + heading + `s_space` + distance + `s_metres`. `hud_quest` calls it.
  - `hud_quest` returns eax = y + 30 when it drew, else y.
  - Extract `hud_mob_bar(rdi mob, rsi name, edx top)` from `hud_boss` `:1677-1695`: ribbon at `top`, bar at `top + 15`. `hud_boss` calls it with `s_boss` and 0.
  - **`hud_event_bar(edi top)`** draws when all of these hold:
    - `ev_hud.state` is in COUNTDOWN..AMBUSH;
    - `protect` < `MAX_MOBS`;
    - `mobs[protect].type == MOB_FOLK` with health > 0;
    - that mob is within 64 blocks of `player`.

    The name comes from `folk_name` into a local 40-byte buffer.
  - **The `hud_draw` y-chain** (`:249-266`):
    - `top = boss ? 22 : 0`;
    - `bar = hud_event_bar(top)`;
    - tracker y = 4 + 22·boss + 22·bar (the F3 override stays);
    - `y2 = hud_quest(y)`, then `hud_event(y2)`.
  - **`hud_event(edi y)`** is a `NINE_NOTE` note like `hud_quest`, shown while the state is in COUNTDOWN..AMBUSH.
    - **Line 1:**
      - camp kinds: "Defend the <Faction> camp", or "Defend the village" for SITE with faction 0;
      - caravans: "Escort the <Faction> caravan".
    - **Line 2:**

      |State|Line 2|
      |---|---|
      |COUNTDOWN, camp|"Wave 1/n in Ns"|
      |COUNTDOWN, caravan|"Setting off in Ns"|
      |WAVE|"Wave w/n: k left"|
      |BREAK|"Wave w+1/n in Ns"|
      |TRAVEL without `EHF_WAIT`|`hud_heading_dist` to (ax, az) − `world_origin`|
      |TRAVEL with `EHF_WAIT`|"Caravan waits" + `hud_heading_dist` to `mobs[protect]`|
      |AMBUSH|"Ambush! k left"|

    - For the camp kinds, the heading and distance to (ax, az) are appended when `player` is more than 32 blocks away.
  - **Folk plate** (`:1595-1629`, insert at `:1612`): `fflags & FF_HELP` → `folk_name` + " - Help!" in gold `RGBA(255,215,60,255)`.
  - **Version:** `s_dbg_title` → `0.12.0`.
- **`rpgscreens.asm` `screen_event`**, modelled on `screen_leader` (`:2640-2722`), panel `DL_W × DL_H`:
  - It reads `game_open_npc` (make it `global` in `game.asm:118` if it isn't).
  - Each frame it returns to `ST_PLAYING` when that mob is not `MOB_FOLK` or lacks `FF_HELP`.
  - **Kind:** `events_offer_kind(slot)`.
  - **Title:** "<Faction> Leader" (CAMP / SITE) or "<Faction> Merchant" (CARAVAN / ROAD).
  - **Lines at y+24 and y+40:**

    |Kind|Line 1|Line 2|
    |---|---|---|
    |CAMP|"Raiders are coming for our camp."|"Hold them off for <ev_kind_waves> waves."|
    |SITE|"Our camp is under threat." ("The village is under threat." for faction 0)|"Help us hold it for <n> waves."|
    |CARAVAN|"Escort my caravan to safety."|"Expect <n> ambushes on the way."|
    |ROAD|"Escort my caravan along the road."|"Expect <n> ambushes on the way."|

  - **Line at y+64:** "Reward: +<ev_kind_rep> standing, loot".
  - **Buttons** at y+118, w 100:
    - Accept at x 16: a guest sends `net_interact_out(slot, IA_EVENT_ACCEPT)`, otherwise `events_accept(slot)`; then `app_goto(ST_PLAYING)`.
    - Decline at x `DL_W−116`: `app_goto(ST_PLAYING)`.
- **`app.asm`:**
  - Add `screen_event` to `screens:` (`:87-92`) with its extern, and change the `cmp eax, ST_CHAT / ja` guard (`~:1090`) to `ST_EVENT`.
  - Add `ST_EVENT` beside `ST_LEADER` at `:899` (`update_state`), `:979` (`.alive` open list) and `:1067` (`.in_view`).
- **`game.asm`:**
  - `call events_reset` right after each `call structures_reset` (`:306`, `:391`, `:793`, the only callers, which guests also take).
  - `SHIFT_CALL events_shift` after `SHIFT_CALL structures_shift` (`:1006`).
  - `ST_EVENT` beside the talk screens in `game_unload_box` (`:1028-1033`).
- **`netmobs.asm` `nm_on_interact`** (`:1141`), before the captive compare: `payload[1] == IA_EVENT_ACCEPT` → validate the slot < `MAX_MOBS`, `payload[2] == MOB_FOLK` and `mobs[slot].type == MOB_FOLK`, then `events_accept(slot)`. The existing `IA_FREE_CAPTIVE` path is unchanged.
- **`netmisc.asm`:**
  - `event_apply` (`:762`): codes `EV_EVENT_OFFER..EV_EVENT_LOST` → `events_on_ev(ebx code, r12d arg)`.
  - New `nx_on_event_state(edi from, esi type, rdx payload, ecx len)`: only for the guest role and len ≥ 20; it calls `events_net_apply(rdx, ecx)`.
- **`netsync.asm`:**
  - `net_handlers` row 17 = `nx_on_event_state`. The free entries are a `dq 0, 0, 0 ; 17..19` run near `:240`: split it, and keep the size check at `:283`.
  - `call events_state_send` with the peer slot beside `standing_send` at `:1988` and `:2190`.
- **`debugmenu.asm` `tab_enemies`**, after the hint at y = 116:
  - `DTXT s_events "Events", 0, 128, C_RUBRIC`.
  - The `events_status` text at (52, 128), `C_INK`.
  - Buttons at y = 140, each calling its function and then `dnote` with "Event started" / "No room for an event" / "Done" by return value:

    |Button|x|w|Calls|
    |---|---|---|---|
    |Camp|0|50|`events_spawn_camp(player)`|
    |Caravan|52|62|`events_spawn_caravan(player)`|
    |Threat|116|56|`events_force_threat()`|
    |Wave|174|50|`events_skip()`|
    |Win|226|46|`events_finish(1)`|

  - At y = 158, `C_INK_SOFT`: "Nearest camp: <Faction> <x>, <z>" from `structures_nearest(SITE_CAMP, 0)` (absolute = local + `world_origin`), or "Nearest camp: none".
- **`menus.asm`** `t_version` → "AssemblyCraft 0.12.0". **`Makefile`** zip name → `AssemblyCraft-0.12.0-win64.zip`.
- **Tests:**
  1. **`test_hud_heading_dist`** (`test_ui.asm`): (0, −100) produces exactly `s_gap` + "N" + `s_space` + "100" + `s_metres`; (100, 0) gives "E"; (70.7, 70.7) gives "SE" and "100".
  2. **`test_net_event_state`** (`test_netmisc.asm`): `nx_on_event_state` with a 20-byte payload as guest → `ev_hud` equals it. As host, or with len 19 → `ev_hud` unchanged.
  3. **`test_net_event_accept`** (`test_netmisc.asm`): `nm_on_interact` with `IA_EVENT_ACCEPT` on a folk with `FF_HELP` reaches `events_accept` (the scratch fake records the slot). Each of these does not: a folk without `FF_HELP`, `payload[2] != MOB_FOLK`, or a non-folk mob.

### Wave 2 — integrator: integration

1. **Copy back** the owned files after the `cmp`-against-base check, and add each worker's `selftest.asm` lines in W1, W2, W3, W4 order.
2. **Wire the unowned call sites** each worker reported. Delete no worker file; drop every `zz_stub.asm`.
3. **Build and test:**
   - `make clean && make 2>&1 | grep -iE "warn|error"` prints nothing.
   - `make test` = 283/283.
4. **Negative controls** (break in scratch, see the test fail, revert):
   - drop the `.idle` march hook → `test_mobs_event_march`;
   - drop the arrow branch → `test_arrows_event_monster`;
   - drop the `FF_HELP` check in `folk_interact` → `test_folk_caravan`;
   - make `ev_wave_size` skip the cap → `test_events_wave_size`.
5. **Commit** `0.12 events: modules, hooks, UI, net (283 tests)`.

### Wave 3 — integrator: live checks, Windows, docs, release

1. Run the Verification live checks. If anything changes, fix it with the edit tool, rerun `make test`, and commit `0.12 events: fixes from live checks`.
2. Build `make windows` and run `WINEPREFIX=/tmp/acwine12 WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=d" wine build/win/assemblycraft.exe --selftest` → 283/283 (skill `assemblycraft-windows-build`). Pure asm adds no syscalls, so `win/` should need no change. If the link reports an undefined `w_*`, fix the asm extern.
3. **Docs:**
   - Append "As built" to the design doc: deviations, live-check results, deferred items with their issue numbers.
   - README: an **Events** bullet under "What's in it" (temporary camps, threatened camps and villages, free and road caravans, waves by day and night, faction loot and standing), and the zip name `0.12.0`.
   - Open a `gh issue` for each deferred item.
4. **Commit** `0.12 events: As built, README`, then `git push origin master`.

## Critical files & anchors

- `src/folk.asm`:
  - `folk_find_target` `:1093-1194`, `folk_target_at` `:1201`;
  - `folk_npc` `:991`, `folk_idle` patrol steering `:1307-1349`;
  - `folk_interact` `:1885`, `folk_name` `:853`.

  These are the defender rules and the caravan walker.
- `src/mobs.asm`: `mob_ai .idle` `:834`, `.jump` `:890`, `mobs_step` hook `:2925`, `spawn_at_ground` `:2334`, `folk_strike_mob` `:1178`, `mob_set_level` `:413` (it rescales health), `make_elite(rdx mob)` `:602`.
- `src/structures.asm`: `camp_slots` / `village_slots` `:334-380` (the source of `evs_site_of`), `roads_in_rect` `:1395`, `camp_main`, `sites` / `site_count` (`SITE` 56 bytes, local coordinates).
- `src/hud.asm`: `hud_draw` `:249-266`, plate `:1595-1629`, `hud_boss` `:1645`, `hud_quest` `:1976` (heading block `:2026-2068`).
- `src/netmisc.asm` / `src/netsync.asm`: `net_event_out` `:734`, `event_apply` `:762`, `nx_on_event` `:778`, `net_handlers` `:222-283`, `standing_send` call sites `:1988`, `:2190`.

## Verification

1. **Build and tests** (repo root):
   - `make clean && make 2>&1 | grep -iE "warn|error"` prints nothing.
   - `make test` ends with 283/283 passed.
   - Each wave-2 negative control fails its named test, then passes after the revert.
2. **Windows:** `make windows` succeeds, and the Wine selftest is 283/283 (Wave 3, step 2).
3. **Single-player live checks** in omabox:
   - Set up per the conventions: `omabox up --audio` from `$HOME`, install `build/assemblycraft`, US layout.
   - Launch `omabox -b default run -d --wait -- /home/sbx/assemblycraft --data-dir /home/sbx/acv12 --play ev1 --seed 4242`.
   - Open the debug menu with F12 ×3, Enemies tab. Each check needs a window screenshot (`omabox shot --window <addr> --fit 960`) showing the stated thing.
   - a. **Camp** at daytime (World tab 12:00): a two-canopy tent appears near the player, and the leader's plate reads "<Faction> Leader - Help!" in gold.
   - b. **Accept:** right-click the leader → the offer screen with "Hold them off for 3 waves." and "Reward: +40 standing, loot". After Accept, the HUD shows "Defend the <Faction> camp / Wave 1/3 in 10s" and the leader's bar.
   - c. **Waves:** raiders of a rival faction march in and fight the guards. Use Wave to skip, then Win → banner "The <Faction> camp is safe!", drops at the leader, and in the World tab the faction's standing up by 40 (plus any +5 kill bonuses).
   - d. **Night** (World tab 00:00) camp: zombies, skeletons and spiders walk to the leader; guards attack them; the leader's bar drops on contact.
   - e. **Leader dies:** start a daytime camp, accept, and stand back without fighting so the raiders kill the leader (they target rival folk) → "The <Faction> camp has fallen", standing unchanged.
   - f. **Caravan:** "<Faction> Merchant - Help!". After Accept, "Setting off in 10s", then the merchant walks with 2 guards. The HUD shows the heading and distance. Walking 40 blocks away gives "Caravan waits". An ambush around 35 % halts it. Win → "The caravan has arrived!", and right-clicking the merchant then opens trade.
   - g. **Threat:** read "Nearest camp: … x, z" in the Enemies tab, teleport there (World tab X/Z/Go), set standing ≥ 0 if needed, press Threat → banner "The <Faction> camp is under threat!", the leader shows "Help!", Accept → 4 waves with the camp's guards fighting. If the camp's trader shows "Help!" (it has a road), accept it after this event → the merchant spawns on the gravel road outside the palisade and walks toward the next camp.
   - h. **Spontaneous:** in a Survival world with no event running, use the World-tab clock buttons to reach 17:00 and wait about 50 s of real time (1 in-game hour = 3000 steps) until 18:00, where `game_time % 36000 == 0` → an OFFER banner and a temporary camp or a caravan near the player.
4. **Two-instance live check** (skill `assemblycraft-multiplayer-omabox-verify`): host `--play evmp --host --name Alice --server 127.0.0.1:27600`, guest `--join CODE --name Bob`.
   - On the host: Camp (debug) near Bob.
   - Bob sees the gold "Help!" plate, opens the offer and presses Accept → the host log and both HUDs show the countdown.
   - Bob's HUD shows the note and the leader bar.
   - Win → both get the banner. Bob gets XP (his level bar moves) and sees his loot bundle on the ground.
   - A guest joining mid-event sees the note within 1 s (late-join state).

## Assumptions & contingencies

- **Version and doc date:** the version is `0.12.0`, and the design doc name uses 2026-11-10.
- **Failure penalty:** none (the user chose this). The spontaneous cadence is every 10 minutes (the user chose this).
- **Free mob slots:**
  - If fewer than 7 slots are free when the player accepts a site or road event, `events_accept` refuses. Show no banner; the FF_HELP stays, so the player can retry.
  - If a wave's size computes ≤ 0, retry every 60 steps.
- **Tent bursts:** if a live check shows that the ~60 BLOCK messages of a tent build overflow the reliable ring on a guest (missing tent blocks on the guest only), spread `evs_build_tent` over steps at 16 blocks per step (a build queue drained by `events_step`). Do not change the net layer.
- **`hud_quest` height:** if `hud_quest`'s note height is not 26 (+4 gap), use its real height for the returned y.
- **Debug layout:** if the debug rows at y = 158 collide with the footer in the smallest GUI (320 × 240), move the "Nearest camp" line into the `events_status` line (at 52, 128) and drop the y = 158 row.
- **`evs_site_of` slots:** if the slot offsets in `structures.asm` differ from the table in W2, use the real offsets. The rule stays centre = floor(home) − slot.
