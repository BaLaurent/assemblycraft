# AssemblyCraft 0.8 — Builds: attributes, rolled gear, elements and statuses, bigger skill trees, mob levels, character sheet

## Context

AssemblyCraft is an x86-64 NASM Minecraft-like game at `/run/media/octopusman/Games/Experiences/assemblycraft` (git `master`, HEAD `ec2f5e0`, `make test` = 115/115). The repo has no git remote.

The user wants the next big milestone toward a proper V1: an RPG with cool combat and real theorycrafting. Today a character has only 18 stats, a 12-node tree per class that a level-30 character nearly maxes, gear with no randomness, and one damage type. The milestone delivers, in this order:
- many more stats;
- attribute points;
- randomly rolled gear: affixes, rarities, rings and amulets, legendary powers;
- elements with status effects;
- 18-node trees with keystones;
- a 4th ability per class;
- mob levels and elite affixes;
- a heavy attack, warhammers and spears;
- a character sheet and item tooltips that show all of it;
- a final V1 bug sweep.

The milestone is executed by waves of parallel subagents. The integrator is the agent executing this plan.

## Conventions (same as 0.6/0.7)

- **Assembly:**
  - Each file has `%include "common.inc"`, `default rel`, explicit sections, and its own `extern`/`global`.
  - SysV ABI: rsp is 16-aligned at every call; rbx, rbp and r12–r15 are callee-saved; SSE is scalar.
  - Every function has a header comment with its signature and contract. `round()` means `cvtss2si` (round-half-even).
  - Zero-extend ids before indexing a table (`movzx`, or `mov edi, edi`). ITEMSTACK, DROP and recipe ids are bytes: load them with `movzx`, never `movsx`.
- **Tests:**
  - A test is `test_<name>() → eax` (0 = pass). It starts with `call world_clear`, sets every global it relies on, and cleans up after itself.
  - Register it in `src/selftest.asm` (`extern` + `TEST` + `TESTNAME`, appended in the order this plan lists them). The Makefile globs `src/*.asm`.
  - `make test` runs `./build/assemblycraft --selftest`.
  - Expected numbers in tests are derived from the formulas in this plan. When a formula changes an existing expectation, the owner of the test file rewrites it.
- **Workers:**
  - Each worker gets a scratch copy:
    `rm -rf /tmp/ac-<name> /tmp/ac-<name>-base && mkdir -p /tmp/ac-<name> && rsync -a --exclude build --exclude .git --exclude .omp $REPO/ /tmp/ac-<name>/ && rsync -a $REPO/src/ /tmp/ac-<name>-base/`
  - Use absolute /tmp paths only, and never run git.
  - Symbols that a sibling owns and has not written yet go in `/tmp/ac-<name>/src/zz_stub.asm` as stubs, or as faithful fakes when the worker's tests depend on their behaviour per this plan.
  - When a sibling changes the behaviour of an existing symbol in a file the worker does not own, the worker may apply a minimal scratch-only patch to that file to emulate the contract. Such patches are never copied back, and the worker reports them.
  - When green, the worker diffs against the baseline; the integrator copies back only owned files.
  - The worker reports its `selftest.asm` lines, the `make test` tail, its stubs and patches, and any deviations.
- **Edits:** use the edit tool, never sed/perl/python rewrites. Git is for the integrator only, one commit per wave.
- **Live checks:**
  - Use the omabox box. Run `omabox up --audio` from `$HOME`.
  - Install: `H=$(omabox -b default path --home); cp build/assemblycraft "$H/.ac.new" && mv -f "$H/.ac.new" "$H/assemblycraft"`.
  - Set the US layout: `omabox -b default lua 'hl.config({input={kb_layout="us", kb_variant=""}}); return "ok"'`.
  - Launch: `omabox -b default run -d --wait -- /home/sbx/assemblycraft --data-dir /home/sbx/acv3 --play NAME`.
  - Close (which saves): `omabox -b default lua 'hl.dispatch(hl.dsp.window.close())'`.
  - The mouse wheel only reaches GLFW with `omabox pointer … -- source wheel scroll 15` (one notch = 15).
  - Fire flicker stalls `run --wait`: launch fire scenes without `--wait`, then wait ~1 s.
- **Throwaway world patcher `/tmp/acpatch.py`:** recreate it if `/tmp` was wiped.
  - It accepts magics ACRAFT03/04/05. The block offset is the header size: 16384 for files of 4210688 bytes, 32768 for 4227072.
  - Ops (offsets into the header):
    - `slot=N:id:count[:dmg]` (156 + 4N, `<BBH>`), `armor=N:id[:dmg]` (944 + 4N)
    - `jewel=N:id:dmg` (16384 + 4N, count 1)
    - `sel` (152), `time` (16), `health` (136), `mode` (12)
    - `pos=x:y:z` (68, 3 floats), `yaw` (92), `pitch` (96)
    - `mobs=N` (300), `mob=i:typeword:hp:dx:dy:dz` (304 + 20i, `<iifff>`, relative to the player; typeword = type | 0x100·elite | level<<16 | affix<<24)
    - `rpg=class:level` (960, 961), `xp` (964)
    - `rank=node:r` (16400 + node), `attr=a:v` (16432 + 2a, word), `rpgxv=1` (16440)
    - `block=x:y:z:id`
  - Item ids are those of common.inc, e.g. STICK 128, COAL 139, DIAMOND 142, IRON_SWORD 146, DIAMOND_SWORD 154, RING 198, AMULET 199.
- **Deferred items:** the repo has no remote, so AGENTS.md's GitHub-issue rule cannot be applied. List deferred items in the final report instead.

## Contracts (wave 0 writes all of these; every worker codes against them)

### `src/common.inc`

**Stats.** Ids 0..17 keep their numbers; the new ones are appended and `NUM_STATS` becomes 44. Every elemental stat is laid out as `STAT_x_FIRE + (elem − 1)`.

|id|constant|unit|
|---|---|---|
|18|`STAT_ATTACK_SPEED`|% faster melee swings, staff bolts and bow draw|
|19–22|`STAT_FIRE_DMG`, `STAT_FROST_DMG`, `STAT_SHOCK_DMG`, `STAT_POISON_DMG`|% increased damage of that element (hits and its DoT)|
|23–26|`STAT_ADD_FIRE`, `STAT_ADD_FROST`, `STAT_ADD_SHOCK`, `STAT_ADD_POISON`|flat damage of that element added to weapon attacks|
|27–30|`STAT_RES_FIRE`, `STAT_RES_FROST`, `STAT_RES_SHOCK`, `STAT_RES_POISON`|% less damage of that element taken|
|31|`STAT_BLEED_CHANCE`|% chance that a physical weapon or melee-skill hit bleeds|
|32|`STAT_DOT_DMG`|% increased burn/bleed/poison damage|
|33|`STAT_ELITE_DMG`|% more damage to elites and the boss|
|34|`STAT_AREA`|% larger radius of abilities and magic blasts|
|35|`STAT_LIFE_REGEN`|tenths of a health point per second|
|36|`STAT_LIFE_ON_KILL`|health per tagged kill|
|37|`STAT_THORNS`|flat damage dealt back to a mob whose melee attack hits or is blocked|
|38|`STAT_BLOCK_COST`|% less stamina per blocked point|
|39|`STAT_XP_BONUS`|% more XP|
|40|`STAT_GOLD_FIND`|% more coins|
|41|`STAT_MAGIC_FIND`|% more weight on non-common rarities|
|42|`STAT_ALL_DMG`|% added to every damage family|
|43|`STAT_WEAPON_DMG`|flat physical damage added to weapon attacks|

**Other new constants:**
- **Elements:** `ELEM_PHYS 0`, `ELEM_FIRE 1`, `ELEM_FROST 2`, `ELEM_SHOCK 3`, `ELEM_POISON 4`, `NUM_ELEMS 5`.
- **Attributes:** `ATTR_STR 0`, `ATTR_DEX 1`, `ATTR_INT 2`, `ATTR_VIT 3`, `NUM_ATTRS 4`, `ATTR_PER_LEVEL 3`.
- **Progression:**
  - `MAX_LEVEL 50`, `NUM_NODES 18`, `NODES_PER_BRANCH 6`, `NUM_ABILITY_SLOTS 4`, `RPGX_VERSION 1`.
  - Node kinds: `NODE_STAT 0`, `NODE_ABILITY 1`, `NODE_KEYSTONE 2`.
  - Temporary, deleted in wave 2: `V4_NODES 12`, `V4_MAX_LEVEL 30` (see wave 0 step 4).
- **Keystones** (id = (class−1)·3 + branch): `KS_EXECUTIONER 0`, `KS_JUGGERNAUT 1`, `KS_BLOODRAGE 2`, `KS_INFERNO 3`, `KS_BLOOD_MAGIC 4`, `KS_MANA_SHIELD 5`, `KS_DEADEYE 6`, `KS_BARRAGE 7`, `KS_WIND_RUNNER 8`, `KS_ASSASSINATE 9`, `KS_SHADOW_DANCE 10`, `KS_VENOM_BLADES 11`.
- **Gear kinds:** `GK_NONE 0`, `GK_MELEE 1`, `GK_BOW 2`, `GK_STAFF 3`, `GK_HEAD 4`, `GK_CHEST 5`, `GK_LEGS 6`, `GK_FEET 7`, `GK_RING 8`, `GK_AMULET 9`.
- **Gear `dmg` word:** bits 14–15 rarity, bits 10–13 tier, bits 0–9 seed. `GEAR_RARITY_SHIFT 14`, `GEAR_TIER_SHIFT 10`, `GEAR_SEED_MASK 1023`.
- **Rarities:** `RAR_COMMON 0`, `RAR_MAGIC 1`, `RAR_RARE 2`, `RAR_EPIC 3`, `RAR_LEGENDARY 4` (display only), `MAX_AFFIXES 5`.
- **Loot tables:** `LOOT_MOB 0`, `LOOT_ELITE 1`, `LOOT_BOSS 2`, `LOOT_CHEST 3`, `LOOT_SHOP 4`.
- **Legendary powers:** `LP_NONE 0`, `LP_KINGSLAYER 1`, `LP_ARCHMAGE 2`, `LP_CELESTIAL 3`, `LP_SHADOW_FANG 4`, `LP_PHOENIX 5`, `LP_STORMS 6`, `LP_EMBERS 7`, `LP_VIPER 8`. `gear_powers` bit = 1 << lp.
- **Tools:** `TOOL_HAMMER 6`, `TOOL_SPEAR 7`.
- **Items:**
  - `RING (FIRST_ITEM+70)`, `AMULET +71`, `PHOENIX_RING +72`, `STORM_BAND +73`, `EMBER_AMULET +74`, `VIPER_AMULET +75`, `IRON_HAMMER +76`, `DIAMOND_HAMMER +77`, `IRON_SPEAR +78`, `DIAMOND_SPEAR +79`.
  - `NUM_ITEMS (FIRST_ITEM+80)` = 208.
- **Trades:** `NUM_TRADES 10`.
- **Inventory:** `INVENTORY` gets `.jewelry: resb 3*4` after `.armor` (offset 204, size 216): ring, ring, amulet. `SLOTREF_JEWELRY 78` (refs 78, 79 rings, 80 amulet).
- **Hit flags** (`combat_hit_flags`, mob side): `HF_CRIT 1`, `HF_PLAYER 2`, `HF_DOT 4`, `HF_ELEM_SHIFT 4`, `HF_ELEM_MASK 0x70`.
- **`combat_hit_mob` flags:** bits 0–2 element (`HITF_ELEM_MASK 7`), `HITF_CRIT 0x100`, `HITF_BLEED 0x200`, `HITF_HURTWIN 0x400`, `HITF_CHILL3 0x800`, `HITF_EXECUTE 0x1000`, `HITF_NOSTATUS 0x2000`, `HITF_CHAIN 0x4000`.
- **Damage sources:** `SRC_MELEE 0`, `SRC_BOW 1`, `SRC_BOLT 2`, `SRC_MELEE_SKILL 3`, `SRC_RANGED_SKILL 4`, `SRC_SPELL 5`, `SRC_THORNS 6`.
- **Statuses:** `STS_BURN 0`, `STS_CHILL 1`, `STS_SHOCK 2`, `STS_POISON 3`, `STS_BLEED 4`.
- **Projectiles:** `PROJ_KNIFE 5`; `AF_BLEED 8`, `AF_ATTACK 16`, `AF_ELEM_SHIFT 8` (ARROWENT.flags bits 8–10 = element).
- **Elite affixes:** `AFX_MOLTEN 1`, `AFX_FROZEN 2`, `AFX_VENOMOUS 4`, `AFX_STORM 8`, `AFX_VAMPIRIC 16`, `AFX_SWIFT 32`, `AFX_JUGGERNAUT 64`, `AFX_ARMORED 128`, `NUM_AFFIX_KINDS 8`.
- **MOBSAVE.type packing:** bits 0–7 type, bit 8 `MOB_ELITE_BIT`, bits 16–23 level (`MS_LEVEL_SHIFT 16`), bits 24–31 affixes (`MS_AFFIX_SHIFT 24`).
- **Misc:**
  - `FX_FROST 7`; `TXT_FROZEN 4`, `TXT_IMMUNE 5`; `CAUSE_POISON 10`; `ST_CHARACTER 19`.
  - `BIND_ABILITY4 15`, `NUM_BINDINGS 16`; `FRAMEINPUT.ability: resd 4`.
  - Sounds: `SND_FREEZE 55`, `SND_HEAVY 56`, `SND_KNIVES 57`, `SND_LOOT_RARE 58`, `SND_LEGENDARY 59`, `NUM_SOUNDS 60`.
  - Display formats: `FMT_PCT 0` ("+N%"), `FMT_FLAT 1` ("+N"), `FMT_TENTH 2` ("+N.N"), `FMT_NEGPCT 3` ("-N%").
- **Tiles** (the only 23 free tiles: 203–207, 216–223, 232–239, 254, 255):
  - `TILE_RING 203`, `TILE_AMULET 204`, `TILE_IRON_HAMMER 205`, `TILE_DIAMOND_HAMMER 206`, `TILE_IRON_SPEAR 207`, `TILE_DIAMOND_SPEAR 216`.
  - `TILE_ABILITY3_0 217` (217–220: the slot-3 icons of Warrior, Mage, Archer, Rogue).
  - `TILE_ATTR_STR 221`, `TILE_ATTR_DEX 222`, `TILE_ATTR_INT 223`, `TILE_ATTR_VIT 232`.
  - `TILE_ELEM_FIRE 233`, `TILE_ELEM_FROST 234`, `TILE_ELEM_SHOCK 235`, `TILE_ELEM_POISON 236`.
  - `TILE_STAT_ASPD 237`, `TILE_STAT_BLEED 238`, `TILE_STAT_AREA 239`, `TILE_STAT_ELITE 254`, `TILE_KEYSTONE 255`.

**Structs (with `%error` size checks).**
- `RPGSAVE` (64 bytes) keeps its layout; `.ranks` is renamed `.ranks_v4` (12 bytes, unused once W1 lands).
- New `RPGEXT` (256 bytes): `.ranks resb 32` (@0), `.attr resw NUM_ATTRS` (@32), `.version resb 1` (@40), `.pad resb 215`.
- `MOB` gets 16 dwords appended after `.home_z`, making `MOB_size` 228:
  - `.level`, `.affix`
  - `.burn_t`, `.burn_dmg` (float, per tick)
  - `.bleed_t`, `.bleed_dmg` (float)
  - `.poison_t`, `.poison` (stacks), `.poison_dmg` (float, per stack per tick)
  - `.chill_t`, `.chill` (stacks), `.freeze_cd`
  - `.shock_t`, `.shock` (stacks)
  - `.mark_t`, `.dot_tick`
- `STATINFO` (24 bytes): `.label resq 1` ("Melee damage"), `.suffix resq 1` ("% melee damage"), `.fmt resb 1`, `.icon resb 1`, `.pad resb 6`.
- `AFFIXDEF` (16 bytes): `.stat`, `.lo`, `.hi`, `.tlo`, `.thi`, `.pad` (bytes), `.kinds resw 1` (bit 1<<GK), `.word resq 1`.
- `GEARAFFIX` (8 bytes): `.stat resd 1`, `.value resd 1`.

**Save format v5.**
- Sizes: `WORLD_HDR_SIZE 32768`, `WORLD_FILE_SIZE 4227072`; `WORLD_V4_HDR 16384`, `WORLD_V4_SIZE 4210688` (v3 and v4 files).
- `WORLDHDR` after `.containers` (@1024..16383):
  - `.jewelry resb 16` @16384: 3 ITEMSTACKs and 4 spare bytes;
  - `.rpgx resb RPGEXT_size` @16400;
  - `.pad2` up to 32768.
- The magic comment becomes "ACRAFT05".

### `src/gl.inc`
`KEY_TAB 258`, `KEY_X 88`.

### Module APIs (owner in brackets)

**rpg.asm [W1]**
```
rpg_ext: resb RPGEXT_size               (global) ranks of nodes 0..17, attribute points spent, version
rpg_keystones: dd                        (global) bit ks set when the class's keystone node has rank 1
rpg_recompute()                          rebuild rpg_stats (see "Stats engine"); safe to call every step
rpg_points() -> eax                      level - sum of ranks
rpg_rank(edi node 0..17) -> eax
rpg_can_spend(edi node) -> eax           0 ok, 5 no class, 1 no points, 2 node >= 18 or maxed,
                                         3 level < tier_level[node % 6], 4 tier > 0 and rank[node-1] == 0
rpg_spend(edi node) -> eax 1/0
rpg_attr(edi a) -> eax spent points      rpg_attr_points() -> eax 3*(level-1) - sum
rpg_spend_attr(edi a) -> eax 1/0         SND_CLICK on success
rpg_attr_info(edi a) -> rax zstr name    rpg_attr_desc(edi a) -> rax zstr effects
rpg_respec_cost() -> eax 5*level         rpg_respec() -> eax 1 when paid (coins removed, ranks+attrs 0)
rpg_keystone(edi ks) -> eax 0/1
rpg_ability_unlocked(edi slot 0..3) -> eax   slot 0 class != 0; slots 1,2,3 = rank of node 7, 9, 15
rpg_ability_info(edi class, esi slot 0..3) -> rax ABILINFO*   index (class-1)*4 + slot
rpg_node_info(edi class, esi node 0..17) -> rax NODEINFO*     stat nodes: .desc = 0; keystones: .stat = ks id
rpg_stat_info(edi stat) -> rax STATINFO*
rpg_format_stat(edi stat, esi value, rdx out byte[48]) -> rax out   "+12% melee damage" style
rpg_xp_need(edi level) -> eax            20 + 10L + L*L for L 1..49, else 0
rpg_on_mob_killed(edi type, esi elite, edx level)   (new 3rd arg)
rpg_save(rdi hdr) / rpg_load(rdi hdr)    also hdr.rpgx <-> rpg_ext
```
**gear.asm [W2, new]**
```
gear_affixes(edi id, esi dmg, rdx out GEARAFFIX[5]) -> eax count
gear_rarity(edi id, esi dmg) -> eax RAR_*      gear_rarity_color(edi rarity) -> eax RGBA
gear_name(edi id, esi dmg, rdx out byte[48]) -> rax out
gear_add_stats(rdi stats dword[NUM_STATS])     adds equipped affixes + legendary implicits, sets gear_powers
gear_powers: dd (global)                        gear_has_power(edi lp) -> eax 0/1
gear_make(edi id, esi tier, edx rarity, ecx seed 1..1023) -> eax dmg
gear_roll(edi id, esi tier, edx table) -> eax dmg     (rarity by table + magic find, seed by rng_next)
gear_tier_for_level(edi level) -> eax min(15, (level-1)/3)
gear_pick_base(edi tier, esi class) -> eax item id    (rng_next)
gear_drop_from_mob(rdi MOB*)                   every gear drop of a dying mob
gear_fill_chest(rdi CONTAINER*, esi table, edx tier, ecx count, r8d seed)   deterministic
item_tooltip(rdi ITEMSTACK*, rsi out qword[12] line ptrs, rdx out dword[12] colours) -> eax lines
gear_equipped_for(edi id) -> rax ITEMSTACK* of the equipped item of the same kind, or 0
```
**combat.asm + status.asm [W3]**
```
combat_hit_mob(edi mob, esi src, edx flags, xmm0 base, xmm1 dirx, xmm2 dirz) -> eax damage dealt (0 refused/immune)
combat_calc(edi mob or -1, esi src, edx flags, xmm0 base) -> xmm0 total (pure; no rng, no side effects)
combat_weapon_preview(rdi out dword[3])        hit, crit hit, attacks per 10 s of the held weapon
combat_pay(edi res, xmm0 amount) -> eax 1 paid  (Blood Magic aware; replaces combat_spend for ability/bolt costs)
combat_heavy(edi mob, xmm0 dirx, xmm1 dirz) -> eax 1 landed
combat_kb_mult() -> xmm0 0.0 with KS_JUGGERNAUT else 1.0
combat_attacker: dd -1                          mob index whose melee attack is being resolved
combat_player_status(edi STS_BURN|STS_CHILL|STS_POISON, esi magnitude)
combat_burn_t, combat_chill_t, combat_poison_t, combat_poison: dd (globals, HUD)
status_apply(edi mob, esi kind, xmm0 magnitude)
status_step()                                    once per sim step, after mobs_step
status_speed_mult(rdi MOB*) -> xmm0              status_damage_mult(rdi MOB*) -> xmm0
explode_magic(xmm0-2 pos, xmm3 radius, edi damage, esi src, edx flags)   (signature change)
explode_dmg_mult: dd 0.0 (float; 0 = environment scaling)
survival_dot(edi amount, esi cause)              damage ignoring and not setting invuln
game_heavy_s: dd -1.0 (float seconds LMB held for a heavy attack, -1 idle)
```
**abilities.asm [W4]:** `abilities_use(edi slot 0..3, rsi eye, rdx dir)`, `abilities_cd: resd 4`, `abilities_cd_total: resd 4`, `abilities_staff_bolt` (unchanged signature).

**mobs.asm [W5]**
```
mob_level_for(edi origin) -> eax       origin 0: rpg_level(); 1..6: rpg_level()+2; 99: max(rpg_level()+3, 20); NPC types 1
mob_set_level(edi idx, esi level)      sets level, max_health and health from the scaling rules
mob_dmg_mult(edi level) -> xmm0        1 + MOB_DMG_STEP*(level-1)
mob_resist(edi type, esi elem) -> eax  signed percent (100 = immune)
mob_affix_name(edi bit 0..7) -> rax zstr
```
**ui.asm [W6]:** `ui_tooltip_lines(rdi lines qword[n], esi n, rdx colours dword[n], ecx side)`. Side 0 places the panel right of the mouse, side 1 left of it.

## Design data

### Stats engine (rpg.asm, W1)

`rpg_recompute()`:
1. Copy `base_stats[class]` (44 dwords per class). Ids 0..17 keep the current values; the new ids are 0.
2. `MAX_HEALTH += 2·(level − 1)`.
3. Stat nodes: `stats[node.stat] += rank·value`.
4. Attributes, with integer division:
   - STR: `MELEE_DMG += STR`, `MAX_STAMINA += STR`.
   - DEX: `RANGED_DMG += DEX`, `ATTACK_SPEED += DEX/3`, `CRIT_CHANCE += DEX/5`.
   - INT: `SPELL_DMG += INT`, `MAX_MANA += 2·INT`, `MANA_REGEN += INT/10`.
   - VIT: `MAX_HEALTH += VIT`, `STAMINA_REGEN += VIT`.
5. Keystones: `rpg_keystones` = bits of the class keystone nodes (5, 11, 17) with rank 1, id = (class−1)·3 + node/6. Stat effects:
   - JUGGERNAUT: `ARMOR_BONUS += 4`, `MOVE_SPEED −= 15`.
   - INFERNO: `FROST_DMG −= 50`.
   - BLOOD_MAGIC: `SPELL_DMG += 30`.
   - WIND_RUNNER: `MOVE_SPEED += 20`.
   - VENOM_BLADES: `CRIT_DMG −= 30`, `POISON_DMG += 50`.
6. `gear_add_stats(rpg_stats)`.
7. Caps and floors:
   - Upper caps: CRIT_CHANCE ≤ 75, COOLDOWN_RED ≤ 50, DODGE_COST ≤ 75, ARROW_SAVE ≤ 75, BLOCK_COST ≤ 75, ATTACK_SPEED ≤ 100, AREA ≤ 100, BLEED_CHANCE ≤ 100.
   - MOVE_SPEED is clamped to [−50, 50]. Each RES is clamped to [−100, 75].
   - Floors: CRIT_DMG ≥ −50; each element % ≥ −90.
8. BLOODRAGE: `MAX_HEALTH = max(2, MAX_HEALTH·9/10)`.
9. Publish `surv_max_health` and clamp health, mana and stamina down (as today).

**Call sites.**
- `sim_step` calls `rpg_recompute` first, every step.
- It is also called by `rpg_spend`, `rpg_spend_attr`, `rpg_respec`, `rpg_set_class`, `rpg_load`, `rpg_add_xp`, `rpg_reset`, after every `inv_click` that returns 1, and every frame in `screen_character`.

**`stat_info` rows** (label / suffix / fmt / icon). `FMT_NEGPCT` stats are stored positive and shown as a reduction.

|id|label|suffix|fmt|icon|
|---|---|---|---|---|
|0|Max health| max health|FLAT|155|
|1|Melee damage|% melee damage|PCT|156|
|2|Ranged damage|% ranged damage|PCT|157|
|3|Spell damage|% spell damage|PCT|158|
|4|Crit chance|% critical chance|PCT|159|
|5|Crit damage|% critical damage|PCT|160|
|6|Max mana| max mana|FLAT|161|
|7|Mana regen| mana per second|FLAT|162|
|8|Max stamina| max stamina|FLAT|163|
|9|Stamina regen|% stamina regen|PCT|164|
|10|Armor| armor|FLAT|165|
|11|Move speed|% move speed|PCT|166|
|12|Backstab|% backstab damage|PCT|167|
|13|Parry window| steps parry window|FLAT|168|
|14|Lifesteal|% of damage healed|PCT|169|
|15|Cooldowns|% cooldowns|NEGPCT|170|
|16|Arrow save|% arrows saved|PCT|171|
|17|Dodge cost|% dodge cost|NEGPCT|172|
|18|Attack speed|% attack speed|PCT|237|
|19–22|Fire/Frost/Shock/Poison damage|% fire/frost/shock/poison damage|PCT|233–236|
|23–26|Added fire/frost/shock/poison| fire/frost/shock/poison damage to attacks|FLAT|233–236|
|27–30|Fire/Frost/Shock/Poison resist|% fire/frost/shock/poison resistance|PCT|233–236|
|31|Bleed chance|% bleed chance|PCT|238|
|32|Damage over time|% damage over time|PCT|238|
|33|Elite damage|% damage to elites|PCT|254|
|34|Area|% area of effect|PCT|239|
|35|Life regen| health per second|TENTH|155|
|36|Life on kill| health per kill|FLAT|169|
|37|Thorns| thorns damage|FLAT|165|
|38|Block cost|% block stamina cost|NEGPCT|168|
|39|XP bonus|% experience|PCT|138|
|40|Gold find|% gold found|PCT|138|
|41|Magic find|% magic find|PCT|138|
|42|All damage|% all damage|PCT|160|
|43|Weapon damage| weapon damage|FLAT|156|

`rpg_format_stat` builds:
- PCT/FLAT: sign ("+", or "-" for a negative value), then |v|, then the suffix.
- NEGPCT: "-" then v then the suffix (a negative v shows "+").
- TENTH: "+v/10.v%10" then the suffix.

**Character-sheet display order** (group headers "Offense", "Defense", "Utility"):
- Offense: 1, 2, 3, 42, 43, 4, 5, 18, 19, 20, 21, 22, 23, 24, 25, 26, 31, 32, 33, 34, 12, 14, 36.
- Defense: 0, 10, 27, 28, 29, 30, 35, 37, 38, 13, 17.
- Utility: 6, 7, 8, 9, 11, 15, 16, 39, 40, 41.

A line is shown when the value ≠ 0, or the id is 0, 4 or 8.

### Leveling and attributes (W1)

- **Caps:** level cap 50. `rpg_xp_need(L) = 20 + 10L + L²` (L1 31, L2 44, L29 1131, L49 2911, L50 0).
- **Points:** skill points = level − Σranks. Attribute points = 3·(level − 1) − Σattr. All attributes start at 0.
- **XP sources:**
  - `rpg_add_xp(n)` first scales n by `(100 + XP_BONUS)/100` (integer).
  - Kill XP = `kill_xp[type]·(9 + level)/10` (integer), ×3 for an elite.
  - Dungeon clear pays `150 + 15·rpg_level()`. The boss death pays `500 + 25·boss level`. Ore XP is unchanged.
- **Life on kill:** `rpg_on_mob_killed` also calls `combat_heal(LIFE_ON_KILL)` when that stat is > 0.
- **Respec:** `rpg_respec()` needs `inv_count(GOLD_COIN) ≥ 5·level`. It removes the coins with `inv_remove_one`, zeroes `rpg_ext.ranks` and `.attr`, recomputes, plays `SND_COIN`, and shows `hud_banner("Skills and attributes reset", RGBA(255,215,60,255))`.
- **`rpg_load` validation:**
  - class/level out of range → `rpg_reset`.
  - `rpgx.version == 0` with class ≠ 0 → zero ranks and attrs, set version 1, and `hud_banner("The skill trees changed: points refunded", RGBA(255,215,60,255))`.
  - A rank > max, Σranks > level, or a ranked node whose previous node (tier > 0) has rank 0 → zero all ranks.
  - Σattr > 3·(level − 1) → zero attrs.
  - XP is clamped as today. Version is set to 1.
- **Reset paths:** `rpg_set_class` and `rpg_reset` also zero `rpg_ext` and set version 1.
- **Attribute texts** (`rpg_attr_info` / `rpg_attr_desc`):
  - "Strength" / "+1% melee damage, +1 max stamina"
  - "Dexterity" / "+1% ranged damage; per 3: +1% attack speed; per 5: +1% crit chance"
  - "Intelligence" / "+1% spell damage, +2 max mana; per 10: +1 mana per second"
  - "Vitality" / "+1 max health, +1% stamina regen"

### Skill trees (W1)

- **Layout:** node = branch·6 + tier. `tier_level = 1, 4, 9, 15, 22, 30`.
- **Fixed nodes for every class:**
  - nodes 7, 9 and 15 are the ability nodes for slots 1, 2, 3 (max 1);
  - nodes 5, 11 and 17 are keystones (max 1);
  - every other node is a stat node (max 5).
- **Points:** a full tree costs 66 points and level 50 gives 50, so a build must choose.
- **Prerequisite:** tier t > 0 needs rank ≥ 1 in node t − 1 of the same branch.

Stat nodes are listed as `name STAT +value per rank`; `A1`/`A2`/`A3` are ability slots and `KS` marks a keystone.

|class|branch 0|branch 1|branch 2|
|---|---|---|---|
|Warrior ("Blademaster", "Bulwark", "Endurance")|Weapon Mastery MELEE +6 · Precision CRIT_CHANCE +3 · Brutality CRIT_DMG +15 · Bloodthirst LIFESTEAL +2 · Swift Blade ATTACK_SPEED +5 · **KS Executioner**|Toughness MAX_HEALTH +4 · A1 War Cry · Iron Skin ARMOR_BONUS +1 · A2 Whirlwind · Shield Wall BLOCK_COST +10 · **KS Juggernaut**|Stamina MAX_STAMINA +12 · Second Wind STAMINA_REGEN +10 · Riposte PARRY_WINDOW +1 · A3 Ground Slam · Spiked Mail THORNS +3 · **KS Bloodrage**|
|Mage ("Fire", "Arcane", "Warding")|Pyromancy SPELL +6 · Kindling FIRE_DMG +8 · Combustion CRIT_DMG +15 · Fire Touch ADD_FIRE +1 · Static SHOCK_DMG +8 · **KS Inferno**|Deep Mind MAX_MANA +15 · A1 Blink · Flow MANA_REGEN +1 · A2 Meteor Storm · Haste COOLDOWN_RED +4 · **KS Blood Magic**|Vitality MAX_HEALTH +3 · Frost Weaving FROST_DMG +8 · Arcane Reach AREA +8 · A3 Frost Nova · Renewal LIFE_REGEN +5 · **KS Mana Shield**|
|Archer ("Marksman", "Hunter", "Survival")|Steady Aim RANGED +6 · Eagle Eye CRIT_CHANCE +3 · Deadly Shot CRIT_DMG +15 · Quick Draw ATTACK_SPEED +5 · Big Game ELITE_DMG +6 · **KS Deadeye**|Fleet Foot MOVE_SPEED +3 · A1 Explosive Arrow · Quiver ARROW_SAVE +10 · A2 Arrow Rain · Toxic Tips ADD_POISON +1 · **KS Barrage**|Vitality MAX_HEALTH +3 · Evasion DODGE_COST +10 · Second Wind STAMINA_REGEN +10 · A3 Hunter's Mark · Readiness COOLDOWN_RED +4 · **KS Wind Runner**|
|Rogue ("Assassin", "Shadow", "Agility")|Backstab BACKSTAB +20 · Precision CRIT_CHANCE +3 · Cruelty CRIT_DMG +15 · Serrated BLEED_CHANCE +8 · Blade Mastery MELEE +6 · **KS Assassinate**|Fleet Foot MOVE_SPEED +3 · A1 Smoke Bomb · Evasion DODGE_COST +10 · A2 Blade Dance · Venom POISON_DMG +10 · **KS Shadow Dance**|Endurance MAX_STAMINA +12 · Second Wind STAMINA_REGEN +10 · Leech LIFESTEAL +2 · A3 Fan of Knives · Lethality DOT_DMG +10 · **KS Venom Blades**|

**Keystone descriptions** (`NODEINFO.desc`). The mechanics are implemented where the Combat rules say.

|keystone|description|
|---|---|
|Executioner|"Melee hits on foes under 30% health deal +60% damage"|
|Juggernaut|"No knockback, +4 armor, -15% move speed"|
|Bloodrage|"+1% damage per 2% missing health, -10% max health"|
|Inferno|"Spell hits ignite; burning foes take +25% spell damage; -50% frost damage"|
|Blood Magic|"Mana costs are paid with health (1 per 5 mana); +30% spell damage"|
|Mana Shield|"35% of damage taken drains mana instead (2 mana per point)"|
|Deadeye|"Fully drawn shots always crit; attack speed no longer speeds your draw"|
|Barrage|"Bow shots fire 2 extra arrows (60% damage); Volley fires 7"|
|Wind Runner|"+20% move speed; dodges cost no stamina but recover twice as slowly"|
|Assassinate|"Backstabs kill non-boss foes under 25% health; +50% backstab vs bosses"|
|Shadow Dance|"Smoke Bomb stealth lasts 30 s; the first hit from stealth deals double"|
|Venom Blades|"Melee hits add 2 poison stacks; +50% poison damage; -30% crit damage"|

### Abilities (W1 table, W4 effects)

`abil_tab` is indexed (class−1)·4 + slot. Slots 0–2 are unchanged in name, cost, cooldown and description. Slot 3:

|class|name|res/cost/cd|desc|effect|
|---|---|---|---|---|
|Warrior|Ground Slam|ST 45 / 12 s|"Smash the ground, stunning foes"|Each hostile at horizontal distance < 4·(1+AREA/100) and \|dy\| < 2 is hit by `combat_hit_mob(SRC_MELEE_SKILL, PHYS \| crit, item_attack_damage(held)·1.5, outward·2)`. Then mob `vy = 6` and `stun = max(stun, 40)` (boss 15, juggernaut 0). Effects: `fx_explosion((x, y+0.1, z), 1.2)`, `SND_SLAM`, `fx_shake = max(fx_shake, 0.6)`|
|Mage|Frost Nova|MA 35 / 10 s|"Freeze nearby foes"|Each hostile at horizontal distance < 5·(1+AREA/100) and \|dy\| < 3 is hit by `combat_hit_mob(SRC_SPELL, FROST \| HITF_CHILL3 \| crit, 6.0, outward·0.5)`. Effects: `fx_burst(chest, FX_FROST, 40, 6)`, `SND_FREEZE`|
|Archer|Hunter's Mark|ST 20 / 8 s|"Marked foe takes 30% more damage"|Target = `mobs_raycast(eye, dir, 40)`; it must be hostile and nearer than the first block. Sets `mark_t = 600`, `fx_burst(head, FX_GOLD, 12, 2)`, `SND_SPELL`. With no target: dry fire, no cost|
|Rogue|Fan of Knives|ST 35 / 9 s|"Throw bleeding knives all around"|8 `PROJ_KNIFE` at (player x, eye y − 0.5, z), horizontal yaw = player yaw + 45k (k 0..7), speed 30, damage 4, flags `AF_BLEED` \| crit (one roll per knife), owner 0, pickup 0. Plays `SND_KNIVES`|

**Changes to the existing abilities** (W4):
- **Payment:** every cost is paid through `combat_pay`.
- **Crits:** `ab_crit` returns only the crit flag; the pipeline applies the multiplier. `ab_dmg` is deleted, and every damage goes through `combat_hit_mob` or a projectile carrying an unscaled base.
- **Bases:**
  - Charge: 6, SRC_MELEE_SKILL.
  - Whirlwind: `item_attack_damage(held)`·(warcry ? 1.3 : 1), SRC_MELEE_SKILL.
  - Fireball: 8, fire.
  - Meteor: 12, fire, AF_BIG.
  - Volley: 6 per arrow.
  - Explosive Arrow: 10, fire.
  - Arrow Rain: 6.
- **Area:** the War Cry radius 6 and the Whirlwind radius 3.5 are multiplied by `1 + AREA/100`.
- **Keystones:**
  - Shadow Dance: Smoke Bomb sets `combat_stealth_t = 1800` instead of 300.
  - Barrage: Volley fires 7 arrows at −30..30° in 10° steps.
- **Staff bolt:**
  - Damage 4 (STAFF) or 7 (ARCHMAGE_STAFF), flags `AF_ATTACK | crit | ELEM_SHOCK<<AF_ELEM_SHIFT`.
  - Cooldown = round(base_cd·100/(100 + ATTACK_SPEED)).
  - LP_ARCHMAGE: every 4th bolt (counter in abilities.asm) is a `PROJ_FIREBALL` with damage = base·2, fire, speed 28.

### Damage pipeline (combat.asm, W3)

**`combat_calc(mob m or −1, src s, flags f, base B)`:**
- e = f & 7.
- F = family multiplier:
  - MELEE / MELEE_SKILL: `1 + (MELEE_DMG + ALL_DMG)/100`;
  - BOW / RANGED_SKILL: `1 + (RANGED_DMG + ALL_DMG)/100`;
  - BOLT / SPELL: `1 + (SPELL_DMG + ALL_DMG)/100`, plus 0.25 when KS_INFERNO and m's `burn_t > 0`;
  - THORNS: 1.
- `elemMult(k) = 1 + stat[STAT_FIRE_DMG + k − 1]/100` for k ≥ 1; 1 for PHYS.
- `part[e] = B·F·elemMult(e)`.
- For a weapon attack (s ∈ MELEE, BOW, BOLT):
  - `part[PHYS] += WEAPON_DMG·F`;
  - `part[k] += stat[ADD_FIRE + k − 1]·F·elemMult(k)` for k 1..4.
- With m ≥ 0: `part[k] ·= (100 − mob_resist(type, k))/100`.
- T = Σpart.
- `mult` is the product of:
  - crit (`HITF_CRIT`): `max(1.0, 1.5 + CRIT_DMG/100)`;
  - m elite or boss: `1 + ELITE_DMG/100`;
  - `status_damage_mult(m)`: (1 + 0.1·shock) · (mark_t > 0 ? 1.3 : 1) · (affix ARMORED ? 0.7 : 1);
  - KS_EXECUTIONER, s ∈ MELEE/MELEE_SKILL and health·10 < max·3: 1.6;
  - KS_BLOODRAGE and s ≠ THORNS: `1 + (100 − 100·health/max_health)/200` (player health);
  - LP_EMBERS and burn_t > 0: 1.3.
- Return T·mult. With m = −1, the resist, elite, status, Executioner and Embers terms are skipped.

**`combat_hit_mob(m, s, f, B, dir)`:**
1. Refuse (return 0) when the index ≥ MAX_MOBS, the slot is empty, or the type is MERCHANT/ELDER.
2. Compute the parts and `mult` as in `combat_calc`. `scaled[k] = part[k]·mult`, total = Σ.
3. **Immune:** total < 0.01 → `dmgnum_text(TXT_IMMUNE)` over the mob, return 0.
4. dealt = max(1, round(total)). With `HITF_EXECUTE`: dealt = max(dealt, mob health).
5. Set `combat_hit_flags = HF_PLAYER | (crit ? HF_CRIT : 0) | argmax_k(scaled)<<HF_ELEM_SHIFT`.
6. Strike: `HITF_HURTWIN` → `mob_hurt(m, dealt, dir)`, else `mob_strike(m, dealt, dir)`. A 0 result returns 0.
7. **Statuses**, only if the mob is still alive and `HITF_NOSTATUS` is clear:
   - for each k ∈ fire/frost/shock/poison with `scaled[k] ≥ 1`: `status_apply(m, STS for k, scaled[k])`; a frost part with `HITF_CHILL3` applies chill 3 times;
   - bleed: `scaled[PHYS] ≥ 1` and (`HITF_BLEED`, or s ∈ MELEE/BOW/MELEE_SKILL with `rng_next%100 < BLEED_CHANCE`) → `status_apply(m, STS_BLEED, scaled[PHYS])`;
   - KS_INFERNO, s ∈ BOLT/SPELL and no fire part → `status_apply(m, STS_BURN, total)`;
   - s == MELEE: 2× `status_apply(m, STS_POISON, scaled[PHYS])` per KS_VENOM_BLADES, plus 2× per LP_SHADOW_FANG;
   - LP_CELESTIAL, s == BOW and crit: 3× `status_apply(m, STS_SHOCK, 0)`.
8. **Lifesteal** (s ≠ THORNS): `combat_life_carry += dealt·LIFESTEAL/100`; whole points go to `combat_heal`.
9. **LP_STORMS**, crit, s ≠ THORNS and no `HITF_CHAIN`: the first 3 other slots where `mob_is_hostile` holds within 6 blocks of m each take `combat_hit_mob(o, SRC_THORNS, SHOCK | HITF_CHAIN | HITF_NOSTATUS, dealt·0.5, 0, 0)`.
10. Return dealt.

**`combat_weapon_preview(out)`:**
- Held GK_MELEE or bare hand: base = `item_attack_damage`, src MELEE, cd = melee cd.
- GK_BOW: base 9, ×1.5 for CELESTIAL_BOW, src BOW, cd = 60 steps draw.
- GK_STAFF with class MAGE: base 4/7, src BOLT, element SHOCK, cd 24/18.
- Attack speed scales cd; for the bow only when not Deadeye.
- out = [round(calc(−1, …)), round(calc with HITF_CRIT), round(600/cd)].

### Combat rules (W3 unless noted)

- **Melee** (`combat_melee`, same signature):
  - Cooldown: `melee_cd[tool]` = none 10, pickaxe 14, axe 18, shovel 14, sword 12, dagger 7, hammer 20, spear 14. Then cd = max(4, round(cd·100/(100 + ATTACK_SPEED))), then the Blade Dance halving as today.
  - Base = `item_attack_damage(held)` × warcry 1.3 × combo (3rd hit ×1.5, ×2.0 with a hammer) × backstab `(1 + BACKSTAB/100)` × KS_ASSASSINATE vs the boss on a backstab 1.5 × KS_SHADOW_DANCE while stealthed 2.0.
  - Then `combat_hit_mob(SRC_MELEE, PHYS | crit | execute, base, dir·kb)`.
  - Execute = KS_ASSASSINATE, backstab, not the boss, and health·4 < max.
  - The forced-crit rules, combo, hit-stop, sounds and shake stay as today. The direct lifesteal code is deleted (the pipeline does it).
  - **Hammer:** kb ×1.5, and if the mob is alive, not the boss and not juggernaut: `stun = max(stun, 12)`.
  - **LP_SHADOW_FANG:** a backstab kill sets `abilities_cd[0] = 0`.
- **Heavy attack** (`combat_heavy`):
  - Needs a held GK_MELEE weapon, `attack_cd ≤ 0`, and `combat_pay(RES_STAMINA, 20)`. A failure is a dry click and returns 0.
  - Base = `item_attack_damage` × backstab × 2.2, flags `PHYS | HITF_BLEED | crit`, kb ×2.5.
  - Then `stun = max(stun, hammer ? 40 : 20)` (skipped for the boss and juggernauts).
  - Effects: `combat_hitstop = 0.12`, `fx_shake = max(fx_shake, 0.5)`, `SND_HEAVY`, attack_cd = cd·3/2.
- **Heavy input** (game.asm):
  - `game_heavy_s = −1` when idle.
  - With a GK_MELEE weapon held, guard down, and the LMB press edge happening while `F_MOB ≥ 0` or no block is targeted: `game_heavy_s = 0` (the light attack on that press runs as today).
  - While LMB is held: `game_heavy_s += dt`, and the block-dig path is skipped.
  - On release:
    - ≥ 0.5 s and `F_MOB ≥ 0` → `combat_heavy(F_MOB, dir)`;
    - ≥ 0.5 s and no mob → `hand_swing` only;
    - in both cases reset to −1.
- **Reach:** `mob_reach` is 4.5 with a spear held, else 3.5. `want_guard` also accepts TOOL_HAMMER and TOOL_SPEAR.
- **Hand pull-back** (hand.asm): while `game_heavy_s ≥ 0`, let o = min(game_heavy_s/0.5, 1). Translate the held item by (0, −0.08·o, +0.12·o) and rotate it −20·o° about X before drawing.
- **Bow** (game.asm):
  - `game_bow_charge += dt·(1 + ATTACK_SPEED/100)` (no ATTACK_SPEED term with KS_DEADEYE).
  - Base int = 1 + round(8p), ×3/2 (integer) for CELESTIAL_BOW. `ARROWENT.damage = base`, flags `AF_ATTACK | crit`. The crit is rolled, or forced with Deadeye and charge ≥ 1.
  - KS_BARRAGE: 2 more arrows at yaw ±6° with damage max(1, round(base·0.6)), no ammo, pickup 0.
  - The bow-wear call is deleted.
- **Projectile hits** (arrows.asm), player-owned:
  - PROJ_ARROW: src = AF_ATTACK ? BOW : RANGED_SKILL; flags `HITF_HURTWIN | elem(flags) | crit | (AF_BLEED ? HITF_BLEED : 0)`; dir as today.
  - AF_EXPLOSIVE arrow: `explode_magic(pos, 2.5, damage, SRC_RANGED_SKILL, FIRE | crit)`.
  - PROJ_BOLT: src = AF_ATTACK ? BOLT : SPELL.
  - PROJ_FIREBALL: `explode_magic(pos, AF_BIG ? 3.0 : 2.5, damage, SRC_SPELL, FIRE | crit)`.
  - PROJ_KNIFE: no gravity, max_age 20, src MELEE_SKILL, removed on a mob or block hit. Rendered as a 0.12 cube (0.75, 0.75, 0.8), lit like arrows.
  - The bolt lifesteal code is deleted. Mob arrows with element bits: on `HIT_TAKEN`, `combat_player_status(kind of that element, max(1, damage/3))` (FIRE→BURN, FROST→CHILL, POISON→POISON).
  - Guns are unchanged (no stat scaling).
- **`explode_magic`:** radius ×(1 + AREA/100). Each live non-NPC mob within r takes `combat_hit_mob(m, src, flags, damage·(1 − 0.5·d/r), unit(mob − c).xz·1.5)`.
- **`explode_at`:** player damage = `ceil(base_dmg[diff]·f·r/3·M)` with M = `explode_dmg_mult` if > 0, else `surv_max_health/20` (float).
- **Player intake** (`player_take_hit` / survival.asm):
  - **Perfect dodge:** a hit avoided by `dodge_t > 0` also sets `combat_riposte_t = 60`.
  - **Block:** stamina cost = `120·amount/surv_max_health·(1 − BLOCK_COST/100)` (float).
  - **Parry:** heals `surv_max_health/10` with LP_KINGSLAYER.
  - **Mana shield:** before the damage applies on a taken or blocked hit with KS_MANA_SHIELD, absorbed = min(floor(amount·35/100), floor(mana/2)); mana −= 2·absorbed; amount −= absorbed.
  - **Thorns:** on `HIT_TAKEN` or `HIT_BLOCKED` with `combat_attacker ≥ 0` and THORNS > 0 → `combat_hit_mob(combat_attacker, SRC_THORNS, PHYS | HITF_NOSTATUS, THORNS, 0, 0)`.
  - **Phoenix:** in `survival_damage`, damage that would kill with LP_PHOENIX and `combat_phoenix_cd == 0` sets health = max/2, invuln 60, `combat_phoenix_cd = 7200`, `fx_burst(chest, FX_FIRE, 40, 3)`, `SND_FIREBALL`, and `hud_banner("The Phoenix Ring saves you!", RGBA(255,140,40,255))`.
  - The `armor_wear` call is deleted.
  - **Environment damage** uses `env(b) = max(1, round(b·surv_max_health/20))`: fall `env(dist − 3)` (ceil before env), each fire cell `env(1)`, starvation `env(1)` with floor `starve_floor·surv_max_health/20`, suffocation `env(1)`.
  - **Regen:** fed and peaceful regen heal `max(1, surv_max_health/20)` per tick.
  - **Potions:** HEALTH_POTION heals max(8, max/10·3); MANA_POTION restores max(50, max_mana/2) (game.asm).
- **Juggernaut:** every player knockback assignment multiplies by `combat_kb_mult()`: zombie, spider and boss hits (W5), arrow hits (W3), blast knockback (W3). Dodge and Charge are untouched.
- **Wind Runner:** dodge cost 0 and `dodge_cd = 60`.
- **`combat_pay(res, amount)`:**
  - Creative: pay always.
  - RES_MANA with KS_BLOOD_MAGIC: cost = ceil(amount/5) health. Only if health > cost: health −= cost, `surv.hurt_flash = 6`, return 1; else 0.
  - Otherwise `combat_spend`.
- **Life regen:** in `combat_step`, `regen_carry += LIFE_REGEN/600` per step; whole points go to `combat_heal`.
- **Player statuses** (`combat_player_status`):
  - BURN: `burn_t = 180`, `burn_tick = max(burn_tick, max(1, m/6))`.
  - CHILL: `chill_t = 120`; `combat_speed_mult ×0.6` while > 0.
  - POISON: stacks = min(5, stacks + 1), `poison_t = 240`, `poison_tick = max(poison_tick, max(1, m/4))`.
  - Every 30 steps in `combat_step`: burn → `survival_dot(round(burn_tick), CAUSE_FIRE)`; poison → `survival_dot(round(stacks·poison_tick), CAUSE_POISON)`.
  - Timers that reach 0 clear their tick and stacks. All of it is cleared by `combat_reset`.
  - `survival_dot` applies no armor and no sound, sets `hurt_flash = 10`, and leaves invuln alone. Death is handled as in `survival_damage`.
- **sim_step order:** `rpg_recompute` first. `status_step` right after `mobs_step`. The ability loop covers 4 slots: binds 11, 12, 13 and 15 → `FRAMEINPUT.ability[0..3]`.
- **game save/load:**
  - Save copies `inv.jewelry` → `WORLDHDR.jewelry`.
  - Load keeps a cell only if count is 1 and `item_gear[id]` is GK_RING (cells 0, 1) or GK_AMULET (cell 2). `test_game_save_load_roundtrip` (W3) asserts a ring with dmg 0x8C05 survives.

### Statuses on mobs (status.asm, W3)

- **`status_apply(m, kind, mag)`**, with `D = 1 + DOT_DMG/100`:
  - BURN: `burn_t = 180`, `burn_dmg = max(burn_dmg, 0.5·mag·D/6)`.
  - BLEED: `bleed_t = 180`, `bleed_dmg = max(bleed_dmg, 0.5·mag·D/6)`.
  - POISON: stacks + 1 up to 10 (20 with LP_VIPER), `poison_t = 240`, `poison_dmg = max(poison_dmg, 0.08·mag·D)`.
  - CHILL: if `freeze_cd > 0` → `chill = min(2, chill + 1)`, `chill_t = 120`. Otherwise chill + 1; at 3 it freezes:
    - `stun = max(stun, boss ? 30 : juggernaut ? 20 : 90)`, `chill = 0`, `chill_t = 0`, `freeze_cd = 120`;
    - `dmgnum_text(TXT_FROZEN)`, `audio_play_at(SND_FREEZE, mob, 0.8)`.
  - SHOCK: `shock = min(3, shock + 1)`, `shock_t = 240`.
- **`status_step()`**, per live mob:
  - Decrement every timer to 0. An expired timer zeroes its stacks and per-tick value.
  - With any DoT active, `dot_tick −= 1`; at ≤ 0 → `dot_tick = 30`, then:
    - dmg = (burn_dmg + bleed_dmg + poison·poison_dmg)·status_damage_mult;
    - if round(dmg) ≥ 1: `combat_hit_flags = HF_PLAYER | HF_DOT | dominant << HF_ELEM_SHIFT`, then `mob_strike(i, round(dmg), 0, 0)`.
  - The dominant element is fire for burn, PHYS for bleed, poison for poison, whichever is largest.
- **`status_speed_mult(mob)`** = 1 − 0.2·chill.

### Mobs (mobs.asm, mobrender.asm, W5)

- **Levels:**
  - `mob_spawn` sets `level = mob_level_for(0)` and zeroes all new fields.
  - `structures.asm` calls `mob_set_level(idx, mob_level_for(origin))` after setting a dungeon mob's origin, and `mob_set_level(idx, mob_level_for(99))` for the boss (W1).
  - `MOB_HP_STEP 0.15` and `MOB_DMG_STEP 0.08` are named float constants in mobs.asm.
- **Health:** `max_health = round(base·(1 + MOB_HP_STEP·(L − 1))·(elite ? 2.5 : 1)·(JUGGERNAUT ? 1.5 : 1))`, computed in single-precision floats with one rounding at the end. base = `t_health`, or `t_boss_health[diff]` for the boss. health = max.
- **Damage:**
  - Every mob→player damage is ×`mob_dmg_mult(level)`, rounded: zombie, spider, skeleton arrow, boss slam and boss volley.
  - The creeper sets `explode_dmg_mult = mob_dmg_mult(level)` around its `explode_at` call and resets it to 0.0.
- **Elites:**
  - `make_elite` rolls affixes: 1 when level < 15, else 2, distinct, `rng_next % 8`, re-rolled on a duplicate.
  - Natural hostile night spawns become elite with `rng_next % 100 < 4`.
  - SWIFT: speed ×1.3, windup steps ×3/4. JUGGERNAUT: knockback taken 0, stun ignored except the freeze (20).
- **Elemental hits:** MOLTEN adds 0.5·phys fire, FROZEN 0.3 frost, VENOMOUS 0.3 poison, STORM 0.5 shock. Each part is `round(phys·share)·(100 − RES)/100` of the player's resistance.
  - The mob calls `player_take_hit(phys + Σparts)` with `combat_attacker = idx` set around the call.
  - On `HIT_TAKEN`: MOLTEN → `combat_player_status(STS_BURN, fire part)`, FROZEN → CHILL, VENOMOUS → POISON(poison part).
  - VAMPIRIC heals max(1, total/2), capped at max.
  - Skeleton arrows carry total damage and the AF_ELEM bits of the first elemental affix.
- **Resistances** `mob_resist` (phys, fire, frost, shock, poison):
  - zombie 0, −50, 0, 0, 25
  - creeper 0, 0, −25, 50, 0
  - skeleton 0, 0, 25, 0, 100
  - spider 0, −25, 0, 0, 100
  - boss 20, 20, 20, 20, 50
  - every other type 0
- **`mob_damage` with `HF_DOT`:** no knockback, lift, hurt sound or hurt window. It still sets bar and tagged, spawns the number with the flags, and pays the kill rewards. The flags' element bits go to `dmgnum_spawn`.
- **Chill:** `mob_update` multiplies `BODY.speed` by `status_speed_mult` around `body_step` and restores it.
- **Rewards:**
  - `rpg_on_mob_killed(type, elite, level)`.
  - Coins: a plain hostile drops 1 + L/10 on an even `rng_next`; an elite drops 3 + rng%3 + L/5; the boss drops 30 + L. Each count is ×(100 + GOLD_FIND)/100 (integer).
  - `mob_drops` calls `gear_drop_from_mob(mob)` for every hostile death. The `t_legendary` code moves into gear.asm and is deleted here. The boss keeps its 4 DIAMOND drop in mobs.asm.
  - `boss_death` pays `rpg_add_xp(500 + 25·level)` instead of 500.
- **Save:** `mobs_save` packs level and affix into MOBSAVE.type. `mobs_load` restores them; level 0 → `mob_level_for(0)`. Health is capped at the scaled maximum.
- **`mob_affix_name`:** "Molten", "Frozen", "Venomous", "Storm", "Vampiric", "Swift", "Juggernaut", "Armored".
- **Render tints** (mobrender.asm), in priority order:
  - hurt;
  - windup;
  - frozen (stun from a freeze, i.e. `freeze_cd > 0` and `stun > 0`): (0.5, 0.7, 1.0);
  - chilled: (0.7, 0.85, 1.0);
  - burning, while `(age>>3)&1`: (1, 0.6, 0.3);
  - poisoned: (0.75, 1, 0.6);
  - stun;
  - elite.

### Gear (gear.asm, items.asm, itemdefs.asm, drops.asm, W2)

- **Gear kinds** (`item_gear`, wave 0):
  - GK_MELEE: every sword, IRON/DIAMOND_DAGGER, SHADOW_FANG, KINGS_BLADE, both hammers, both spears.
  - GK_BOW: BOW, CELESTIAL_BOW. GK_STAFF: STAFF, ARCHMAGE_STAFF.
  - Helmets/chestplates/leggings/boots: GK_HEAD..GK_FEET.
  - GK_RING: RING, PHOENIX_RING, STORM_BAND. GK_AMULET: AMULET, EMBER_AMULET, VIPER_AMULET.
- **`item_legendary`** (wave 0): KINGS_BLADE 1, ARCHMAGE_STAFF 2, CELESTIAL_BOW 3, SHADOW_FANG 4, PHOENIX_RING 5, STORM_BAND 6, EMBER_AMULET 7, VIPER_AMULET 8.
- **Gear never wears** (W2): `item_durability` is 0 for every gear id. `inv_damage_held` returns 0 for gear. `armor_wear` is deleted. Tools and flint-and-steel keep their wear.
- **Equipped set** (`gear_add_stats`):
  - the held hotbar stack, when its gear kind is 1..3;
  - the 4 armor cells;
  - the 3 jewelry cells.
  - Each adds its affixes. Legendary implicits: KINGS_BLADE ELITE_DMG +50, EMBER_AMULET FIRE_DMG +20, VIPER_AMULET POISON_DMG +25. `gear_powers` = OR of `1 << item_legendary` over the equipped set.
- **Affix count:** Common 0, Magic 2, Rare 4, Epic 5, Legendary items 4 (their rarity bits are RAR_RARE).
- **Decode** (deterministic, no world seed):
  - For k in 0..n−1: `h = mix32(seed ^ (id << 10) ^ (k << 20) ^ 0x9E3779B9)`, where `mix32(x)`: x ^= x>>16; x *= 0x7FEB352D; x ^= x>>15; x *= 0x846CA68B; x ^= x>>16.
  - pool = the affixes whose kinds include the item's kind; pick `pool[h % size]`, advancing (wrapping) past ones already used.
  - r = (h >> 16) & 255; lo' = lo + tier·tlo, hi' = hi + tier·thi; v = lo' + r·(hi' − lo')/255 (integer). Epic: v = v·5/4. Then v = max(1, v).
- **Rarity roll:** per-mille weights common/magic/rare/epic. Every non-common weight is ×(100 + MAGIC_FIND)/100.

  |table|common|magic|rare|epic|
  |---|---|---|---|---|
  |LOOT_MOB|600|320|70|10|
  |LOOT_ELITE|200|500|250|50|
  |LOOT_BOSS|0|0|800|200|
  |LOOT_CHEST|300|450|220|30|
  |LOOT_SHOP|0|700|270|30|

- **`gear_make`:** `dmg = rarity<<14 | tier<<10 | seed`. `gear_roll` uses seed `1 + rng_next % 1023`.
- **`gear_pick_base(tier, class)`:** c = rng%100.
  - c < 35, weapon: with 60% chance the class family (Warrior: sword/hammer/spear equally; Mage: STAFF; Archer: BOW; Rogue: dagger; none: sword), else one of sword, hammer, spear, dagger, bow, staff.
    - Swords: tier 0 WOOD, 1 STONE, 2–5 IRON, ≥ 6 DIAMOND, with a 10% GOLD override.
    - Daggers, hammers, spears: IRON < 6 ≤ DIAMOND.
  - c < 75, armor: slot rng%4, IRON when tier < 6 else DIAMOND, with a 15% GOLD override.
  - c < 88: RING. Else AMULET.
- **`gear_drop_from_mob`:** tier = `gear_tier_for_level(mob level)`.
  - Non-elite hostile: one drop with rng%100 < 6 (LOOT_MOB).
  - Elite: one LOOT_ELITE drop plus a second with 30%.
  - Boss:
    - the class legendary (none/Warrior → KINGS_BLADE, Mage → ARCHMAGE_STAFF, Archer → CELESTIAL_BOW, Rogue → SHADOW_FANG) made with RAR_RARE;
    - 3 LOOT_BOSS drops;
    - with 25%, one of the 4 legendary jewelry items (RAR_RARE).
  - Drops use `drops_spawn(id, 1, dmg, mob centre)`. A rare or epic drop plays `SND_LOOT_RARE`; a legendary plays `SND_LEGENDARY`.
- **`gear_fill_chest`:** uses a private mix32 stream seeded by `seed`. It writes `count` gear stacks into the lowest free cells.
  - Dungeon d (`SITE.index`): table LOOT_CHEST, tier 2 + 2d, count 1, seed `hash32(x, z, 650)`.
  - Crypt chests: LOOT_BOSS, tier 13, count 2.
  - Called from structures.asm (W1).
- **Shop:** `trade_tab` gets rows 9 and 10: 30 GOLD_COIN → RING 1 and 30 GOLD_COIN → AMULET 1 (`NUM_TRADES 10`). `trade_execute` gives each gear item `gear_roll(get, gear_tier_for_level(rpg_level()), LOOT_SHOP)` via `inv_add_dmg`, with overflow going to `drops_spawn` (W1).
- **Names:**
  - Magic, Rare and Epic: "<word of affix 0> <base name>". Legendary and Common: the base name.
  - Rarity colours: Common (255,255,255), Magic (100,150,255), Rare (255,230,90), Epic (190,110,255), Legendary (255,150,40).
- **`item_tooltip`**, up to 12 lines of ≤ 48 chars:
  1. name in the rarity colour;
  2. "<Rarity> <kind> - Tier T" in (170,170,170). Kind words: Weapon, Bow, Staff, Helmet, Chestplate, Leggings, Boots, Ring, Amulet. Common gear omits " - Tier T";
  3. "Attack N" (weapons) or "Armor N" (armor) in white, plus "Hammer: stuns on hit" / "Spear: long reach" for those tools;
  4. affix lines from `rpg_format_stat` in (150,190,255);
  5. legendary power lines in (255,150,40);
  6. "Shift: compare" in (130,130,130) when `gear_equipped_for` returns a different stack.
  - Non-gear items: the name, plus "Durability d/D" for items with durability.
- **Legendary power lines:**
  - Kingslayer: "+50% damage to elites and bosses;" / "parries heal 10% health"
  - Archmage: "Every 4th staff bolt is a fireball"
  - Celestial: "No arrows needed, x1.5 damage;" / "crits shock the target"
  - Shadow Fang: "Hits add 2 poison stacks;" / "backstab kills reset Shadowstep"
  - Phoenix: "A killing blow heals you to half" / "health (once per 2 minutes)"
  - Storms: "Crits arc to 3 nearby foes" / "for 50% as shock"
  - Embers: "Burning foes take +30% damage;" / "+20% fire damage"
  - Viper: "Poison stacks up to 20;" / "+25% poison damage"
- **Jewelry slots** (items.asm `inv_click`):
  - Refs 78..80 map to `inv + INVENTORY.jewelry + (ref − 78)·4`. A cursor stack must be GK_RING for 78/79 and GK_AMULET for 80, else the click is refused.
  - Shift-click of a ring or amulet from the inventory goes to the first free matching cell, the same way as the armor shortcut.
- **Drop beam** (drops.asm): a gear drop with rarity ≥ magic draws 2 crossed vertical quads, 0.06 wide and 1.6 tall, in the rarity colour at alpha 0.5, fullbright with texturing off on units 0 and 1.

**Affix table** (`affix_tab`, gear.asm). Kinds: W = weapon (melee + bow + staff), M melee, B bow, S staff, H head, C chest, L legs, F feet, A = all four armor slots, R ring, Am amulet.

|#|stat|kinds|lo|hi|tlo|thi|word|
|---|---|---|---|---|---|---|---|
|0|WEAPON_DMG|W|1|2|1|1|Sharp|
|1|MELEE_DMG|M R Am|4|8|1|2|Brutal|
|2|RANGED_DMG|B R Am|4|8|1|2|Keen|
|3|SPELL_DMG|S H R Am|4|8|1|2|Arcane|
|4|ALL_DMG|Am|2|4|1|1|Mighty|
|5|CRIT_CHANCE|W H R|1|3|0|1|Precise|
|6|CRIT_DMG|W Am|5|10|2|3|Deadly|
|7|ATTACK_SPEED|W R|2|5|0|1|Quick|
|8–11|ADD_FIRE/FROST/SHOCK/POISON|W R|1|2|1|1|Burning / Chilling / Charged / Venomous|
|12–14|FIRE/FROST/SHOCK_DMG|S R Am|5|10|1|2|Blazing / Frigid / Stormy|
|15|POISON_DMG|M B R Am|5|10|1|2|Toxic|
|16|BLEED_CHANCE|M B|3|8|0|1|Serrated|
|17|DOT_DMG|S R Am|5|10|1|2|Lingering|
|18|ELITE_DMG|W Am|5|10|1|2|Slaying|
|19|LIFESTEAL|M R|1|3|0|0|Vampiric|
|20|LIFE_ON_KILL|W R|1|2|1|1|Reaping|
|21|MAX_HEALTH|A Am|2|4|1|2|Sturdy|
|22|ARMOR_BONUS|A|1|1|0|0|Reinforced|
|23|LIFE_REGEN|A Am|2|5|1|1|Renewing|
|24–27|RES_FIRE/FROST/SHOCK/POISON|A R Am|5|10|1|2|Fireproof / Insulated / Grounded / Purifying|
|28|MOVE_SPEED|F Am|2|5|0|0|Fleet|
|29|MAX_STAMINA|C L|5|10|1|2|Enduring|
|30|STAMINA_REGEN|L F Am|5|10|0|1|Tireless|
|31|MAX_MANA|H S R|5|15|1|2|Wise|
|32|MANA_REGEN|H S Am|1|2|0|0|Flowing|
|33|COOLDOWN_RED|H Am|2|5|0|0|Hasty|
|34|THORNS|C L|2|4|1|1|Spiked|
|35|BLOCK_COST|C M|5|10|0|1|Steadfast|
|36|AREA|S Am|4|8|0|1|Vast|
|37|XP_BONUS|H R|3|6|0|0|Studious|
|38|GOLD_FIND|R Am|5|15|0|1|Greedy|
|39|MAGIC_FIND|H R Am|5|10|0|1|Lucky|
|40|BACKSTAB|M|8|15|1|2|Treacherous|
|41|ARROW_SAVE|B|5|10|0|0|Endless|
|42|PARRY_WINDOW|M|1|1|0|0|Parrying|
|43|DODGE_COST|F|5|10|0|0|Nimble|

### New items (wave 0 tables)

|item|name|icon|attack|tool|recipe (3×3, row-major)|
|---|---|---|---|---|---|
|RING|Ring|203|1|0|none (drops, shop)|
|AMULET|Amulet|204|1|0|none|
|PHOENIX_RING|Phoenix Ring|203|1|0|none|
|STORM_BAND|Band of Storms|203|1|0|none|
|EMBER_AMULET|Ember Amulet|204|1|0|none|
|VIPER_AMULET|Viper Amulet|204|1|0|none|
|IRON_HAMMER|Iron Warhammer|205|9|HAMMER|I I I / I S I / 0 S 0 (I iron ingot, S stick)|
|DIAMOND_HAMMER|Diamond Warhammer|206|12|HAMMER|D D D / D S D / 0 S 0|
|IRON_SPEAR|Iron Spear|207|6|SPEAR|0 0 I / 0 S 0 / S 0 0|
|DIAMOND_SPEAR|Diamond Spear|216|8|SPEAR|0 0 D / 0 S 0 / S 0 0|

All have max stack 1 and durability 0. `item_tier`: TIER_IRON for the iron hammer and spear, TIER_DIAMOND for the diamond ones, 0 otherwise. Every other table is 0.

### UI (W6 screens, W7 HUD)

The GUI is at least 320×240 units (auto scale = min(fb_w/320, fb_h/240)), so every panel fits 320×240.

**Skill screen** (`screen_skills`, rpgscreens.asm):
- Panel 270×232, centred.
- Header "<Class> - Level N" at (px+8, py+5); "Points: N" right-aligned at px+262, green when > 0.
- XP bar at (px+8, py+15, 254, 3). Branch names centred at (px+45+90b, py+21).
- Node b,t: 24×24 at (px+33+90b, py+30+30t). Connector 2×6 at (nx+11, ny+24) for t 0..4, lit when the upper node is ranked.
- Click mapping inverts that grid exactly.
- Icons:
  - stat → `stat_info.icon`;
  - ability slot s → `TILE_ABILITY0 + (class−1)·3 + s` for s ≤ 2, `TILE_ABILITY3_0 + class − 1` for slot 3;
  - keystone → `TILE_KEYSTONE` with a 2-px gold (255,200,60) frame.
- Tooltip (the existing `tooltip_wrapped`):
  - stat: "<name> r/m: <rpg_format_stat(stat, value)> per rank";
  - ability: "<name> r/m: <desc> - Key: <key_name(bind)>". bind = 11 + slot for slots 0..2, 15 for slot 3;
  - keystone: "<name> (Keystone) r/m: <desc>";
  - plus the existing hints.
- Footer at py+214: "Tab: Character". Tab (`ui_input.key_pressed == KEY_TAB`) switches to ST_CHARACTER.

**Character screen** (`screen_character`, ST_CHARACTER, rpgscreens.asm):
- Calls `rpg_recompute` every frame.
- Panel 300×232. Header "<Class> - Level N"; "Attribute points: N" right-aligned, green when > 0.
- Attribute rows i at y = py+18+12i:
  - 10-px icon (`TILE_ATTR_*`) at px+8, name at px+22, value right-aligned at px+112;
  - a 9×9 "+" box at px+116, enabled when points > 0. A click calls `rpg_spend_attr(i)`; shift-click calls it up to 5 times;
  - hovering a row shows `rpg_attr_desc` in a tooltip.
- Summary at px+140, rows py+18..py+54, 9 px apart:
  - "Health H/M";
  - "Armor P (-4P% damage)", with P = min(20, armor_points + ARMOR_BONUS);
  - "Hit A  Crit C" and "Attacks X.Y/s" from `combat_weapon_preview` (X.Y = out[2]/10).
- Divider at py+66.
- Stat list from py+70 to py+220: two columns at px+8 and px+154, 9-px rows (16 rows per column). It follows the display order with group headers. The wheel scrolls one row when the mouse is over the list.
- Footer "Tab: Skills". Esc, the inventory key and the skills key close it as `close_check` does.

**Elder dialog:** `DL_H` becomes 144. Button "Reset skills: N coins" at (x+8, y+118, w 244), enabled when `inv_count(GOLD_COIN) ≥ rpg_respec_cost()` and class ≠ 0. A click calls `rpg_respec`.

**Merchant:**
- `TR_H` becomes 236, with 10 rows.
- A gear "get" icon tooltip reads "Random magic+ <Ring|Amulet>, tier T".

**Inventory** (invscreen.asm):
- Survival 2×2 screen: label "Jewelry" at (px+8, py+38); cells refs 78..80 at (px+8+18i, py+48).
- `slot_cell` records `hover_stack` (the dword) and `hover_ref`. The creative palette records `id | 1<<8`.
- `draw_overlay`:
  - the book tip keeps priority;
  - otherwise a hovered stack shows `item_tooltip` via `ui_tooltip_lines(side 0)`;
  - with shift held and `gear_equipped_for` returning a stack at a different ref than `hover_ref`, it also draws that stack's lines with a first line "Equipped" (170,170,170) at side 1.
- Every `inv_click` that returns 1 is followed by `rpg_recompute`.

**`ui_tooltip_lines`:** width = max `ui_text_width` + 6, height = 11·n + 3. The panel sits at (mx+12, my−12), or for side 1 it ends at mx−12. It is clamped to the screen and draws each line at y + 3 + 11i in its colour.

**Death screen** (menus.asm): `death_causes` gets "You succumbed to poison" for CAUSE_POISON, and the bound becomes CAUSE_POISON.

**app.asm:** ST_CHARACTER → `screen_character` in the screens table and in the bound check. ST_CHARACTER is listed wherever ST_SKILLS is (simulation and view handling). The skills key closes it.

**HUD** (hud.asm, dmgnum.asm, W7):
- **Hearts:** always 10. Heart i is full when health ≥ (i+1)·max/10 (float), half when ≥ (i+0.5)·max/10, else empty. "H/M" is right-aligned to end at x0−3, y0−15, in (255,120,120).
- **Abilities:** 4 slots at x0 − 93 + 23i, using the slot-3 icon tile above and key labels from binds 11, 12, 13, 15.
- **Level text:** "Level N", followed by " (<skills key>)" in (140,255,90) when skill or attribute points are unspent.
- **Held name:** for gear, `gear_name` in `gear_rarity_color`.
- **Crosshair:** (255,200,60) while `game_heavy_s ≥ 0.5`.
- **Player status pips:** 6×6 squares at (x0+102+8i, y0−29) for active burn (255,120,30), chill (120,190,255) and poison (110,220,70).
- **Mob plates:** for hostiles with `bar > 0` or elite within 24 blocks:
  - "Lv N" centred 9 px above the bar, in (200,200,200), or (255,200,80) for an elite;
  - for elites, the `mob_affix_name`s joined by spaces 9 px higher, in (255,140,60);
  - status pips 3×3, 4 px apart under the bar: burn (255,120,30), chill (120,190,255), shock (255,240,80), poison (110,220,70), bleed (210,30,30);
  - a marked mob gets a 1-px red (230,40,40) frame around its bar.
- **dmgnum:**
  - The number colour comes from the flags' element: phys white, fire (255,140,40), frost (130,200,255), shock (255,240,90), poison (120,220,80).
  - A crit is scale 2 in that colour, gold (255,220,60) when phys.
  - `HF_DOT` numbers are scale 1 at 85% alpha, and a PHYS DoT is (220,50,50).
  - New texts: TXT_FROZEN "FROZEN" (130,200,255) and TXT_IMMUNE "IMMUNE" (200,200,200), both scale 1. The bound check moves to TXT_IMMUNE.
  - `test_hud` follows any DMGNUM layout change.

### Art and sound (W8)

- **Tiles:** draw the 23 tiles after the 0.7 art and before the font. The atlas must stay byte-identical outside them; prove it with a dump harness as in 0.7.
  - **Items:**
    - ring: gold band with a red gem;
    - amulet: chain with a blue gem;
    - iron/diamond warhammer: a big block head on a shaft;
    - iron/diamond spear: a long shaft with a leaf blade.
  - **Abilities:**
    - Ground Slam: a fist with cracks;
    - Frost Nova: a snowflake ring;
    - Hunter's Mark: crosshair rings;
    - Fan of Knives: 3 fanned blades.
  - **Attributes:**
    - STR: red fist;
    - DEX: green feather;
    - INT: blue eye;
    - VIT: red heart with a plus.
  - **Elements:**
    - fire flame;
    - frost snowflake;
    - shock bolt;
    - poison drop.
  - **Stats:**
    - attack speed: double chevrons;
    - bleed: a dark red drop;
    - area: a burst ring;
    - elite: a gold skull;
    - keystone: a gold star on dark blue.
- **Sounds:** each peak within [−18, −0.1] dBFS. Raise `POOL_SAMPLES` only if the pool overflows.
  - SND_FREEZE: ice crackle; high noise bursts, 0.3 s.
  - SND_HEAVY: a low whoosh and thud, 0.25 s.
  - SND_KNIVES: 4 quick swishes, 0.3 s.
  - SND_LOOT_RARE: a two-note chime, 0.4 s.
  - SND_LEGENDARY: a rising three-note chime with sparkle, 0.7 s.

## Approach

### Wave 0 — contracts (integrator, inline; commit "0.8 contracts")

0. Run `git status` and `git log -1`. The tree must be clean except `.omp/` and `.asm-lsp.toml`, with HEAD `ec2f5e0` or a descendant that only you made.
1. **`common.inc`:** add every constant and struct in Contracts.
   - Rename `RPGSAVE.ranks` → `.ranks_v4` (12 bytes).
   - Add `V4_NODES 12` and `V4_MAX_LEVEL 30` with the comment "0.7 tree layout, removed in wave 2".
   - Update the WORLDHDR magic comment.
2. **`gl.inc`:** `KEY_TAB`, `KEY_X`.
3. **`itemdefs.asm`:** add the 10 items to every table with `PAD_TO` ordering, per "New items".
   - `item_icon`: the COAL `%rep` covers only `RING − COAL` ids, then explicit entries.
   - New tables `item_gear` and `item_legendary` (global, `END_TABLE` checked).
   - Leave the old durability values untouched (W2 zeroes them).
4. **Mechanical renames:**
   - In `rpg.asm`, `rpgscreens.asm` and `test_rpg.asm`: replace `NUM_NODES` → `V4_NODES` and `MAX_LEVEL` → `V4_MAX_LEVEL`.
   - In `rpg.asm`, `test_rpg.asm` and `test_abilities.asm`: replace `RPGSAVE.ranks` → `RPGSAVE.ranks_v4`.
   - Pad each `base_stats` row with 26 zero dwords.
   - Confirm with `grep -nw "NUM_NODES\|MAX_LEVEL\|RPGSAVE.ranks" src/*.asm`: only common.inc may remain (`-w` keeps `V4_MAX_LEVEL` and `ranks_v4` out of the result).
5. **`items.asm`:** append the 4 hammer/spear recipe records after GLASS_PANE. **`quests.asm`:** append the trade rows `GOLD_COIN,30, RING,1` and `GOLD_COIN,30, AMULET,1` (they give plain stacks until W1 adds the gear roll). Append the same 2 rows to `test_rpg.asm`'s local `trade_tab` copy.
6. **Bindings:**
   - `input.asm`: `prev_ability` resd 4, `cap_edges` resd 5, the BIND_ABILITY4 edge into `FRAMEINPUT.ability + 12`.
   - `settings.asm`: append 88 to `SETTINGS_IMAGE` keys; add `SETENT "key_ability4", SETTINGS.keys + 4*BIND_ABILITY4, 32, 348, 1`.
   - `options.asm`: append label "Ability 4" (`s_b_ability4`) to the binding label list.
7. **Save v5:**
   - `world.asm`:
     - magics `world_magic` "ACRAFT05" and `world_magic_v4` "ACRAFT04" (the v3, v2, v1 magics stay);
     - `world_load` dispatch by size: WORLD_FILE_SIZE + v5 magic → ok; WORLD_V4_SIZE + v4/v3 magic → `convert_v4`, `migrate_items_v3` (v3 only), `migrate_gear_v4`; WORLD_V2_SIZE → `convert_v2`, `migrate_items_v3`, `migrate_gear_v4`; v1 as today;
     - stamp v5 after any conversion.
   - `convert_v4` copies the blocks backwards from `world_header + WORLD_V4_HDR + WORLD_VOLUME − 1` to `blocks + WORLD_VOLUME − 1`, then zeroes header bytes 16384..32767.
   - `migrate_gear_v4` zeroes `dmg` of every stack whose `item_gear` ≠ 0 in the 36 slots, 4 armor cells, and the 27 cells of each used container.
   - `saves.asm`: add `m_v5` "ACRAFT05" to the accepted list.
   - `test_world.asm`:
     - layout asserts: `WORLDHDR_size 32768`, `.jewelry 16384`, `.rpgx 16400`, `RPGEXT_size 256`, `MOB_size 228`, `INVENTORY_size 216`;
     - the existing magic checks expect "ACRAFT05";
     - new `test_world_load_v4_converts`: write a v4 image of `WORLD_V4_SIZE` bytes with a 16384-byte header, magic "ACRAFT04":
       - slot 0 IRON_SWORD dmg 37, slot 1 STONE_PICKAXE dmg 7, armor 1 IRON_CHESTPLATE dmg 3;
       - container 0 = a chest at a CHEST cell with cell 0 BOW dmg 10;
       - BRICK at (1,2,3).
     - Expect after load:
       - sword dmg 0, pickaxe dmg 7, chestplate dmg 0, bow dmg 0, BRICK at (1,2,3);
       - `WORLDHDR.rpgx` all zero;
       - after `world_save` the magic is "ACRAFT05" and `file_read` returns `WORLD_FILE_SIZE` bytes.
8. Register the test; `make clean && make 2>&1 | grep -iE "warn|error"` prints nothing; `make test` = 116/116. Commit.

### Wave 1 — six parallel workers (one `task` batch; commit "0.8 core")

|worker|owns (only these files)|implements|new tests|
|---|---|---|---|
|W1 Progression|`rpg.asm`, `quests.asm`, `structures.asm`, `test_rpg.asm`, `test_structures.asm`|Stats engine, Leveling and attributes, Skill trees, the abilities table, respec, shop rows and gear trade, chest gear and mob levels in structures, dungeon/boss XP. Remove `V4_*` uses from its files|`test_rpg_attributes_and_respec`, `test_rpg_keystones_and_caps`|
|W2 Gear|new `gear.asm`, new `test_gear.asm`, `items.asm`, `itemdefs.asm`, `drops.asm`, `test_items.asm`|Gear section: decode, names, tooltips, stats/powers, rolls, drops, chests API, jewelry slots, no wear, drop beam; `CASE` rows for the 4 new recipes|`test_gear_decode_deterministic`, `test_gear_stats_and_powers`, `test_gear_drops_and_chests`, `test_gear_jewelry_and_no_wear`|
|W3 Combat|`combat.asm`, new `status.asm`, new `test_status.asm`, `arrows.asm`, `explode.asm`, `survival.asm`, `game.asm`, `hand.asm`, `test_melee.asm`, `test_combat.asm`, `test_survival.asm`, `test_game.asm`|Damage pipeline, Combat rules, Statuses on mobs, player statuses, sim_step hooks, jewelry save/load, heavy attack and hand pull-back|`test_damage_pipeline`, `test_status_effects`, `test_heavy_attack_and_speed`, `test_player_statuses_and_defenses`|
|W4 Abilities|`abilities.asm`, `fx.asm`, `test_abilities.asm`|4 slots, the new abilities, migration to the pipeline, `combat_pay`, AREA, Barrage/Shadow Dance, staff bolt rules, LP_ARCHMAGE; `FX_FROST` (size 0.12–0.2, life 20–30, velocity ×0.9/step, colour (0.75,0.9,1)→(0.4,0.6,1), fullbright)|`test_new_abilities`|
|W5 Mobs|`mobs.asm`, `mobrender.asm`, `test_mobs.asm`|Mobs section|`test_mob_levels_and_scaling`, `test_elite_affixes`|
|W8 Art+sound|`texgen.asm`, `sfx.asm`|Art and sound|none|

**Ability unlocks in `test_abilities.asm`.** W4 writes ranks through `rpg_ext + RPGEXT.ranks + node` (nodes 7, 9, 15 for slots 1, 2, 3), replacing the `RPGSAVE.ranks_v4` pokes. In its scratch, W4 patches rpg.asm's `rpg_ability_unlocked` and `rpg_ability_info` (4 per class, the table above) to the new contract; those patches are never copied back.

**Stubs and fakes each worker needs** (faithful to Contracts):
- **W1:** `gear_add_stats` (ret), `gear_powers` (dd 0); `gear_roll` returns `RAR_MAGIC<<14 | tier<<10 | 1`; `gear_fill_chest` writes `count` IRON_SWORD stacks with that dmg into the lowest free cells; `mob_set_level` sets `MOB.level` only; `mob_level_for` per its contract.
- **W2:** `armor_wear` (ret), because survival.asm still calls it in W2's scratch.
- **W3:**
  - `rpg_keystones` dd 0 plus `rpg_keystone` reading it; `gear_powers` dd 0 plus `gear_has_power`;
  - `mob_resist` with the exact resistance table;
  - `rpg_on_mob_killed` keeps the old 2-argument behaviour in scratch.
- **W4:**
  - `combat_hit_mob` / `combat_pay` / `combat_calc` as faithful fakes of the Damage pipeline: family multiplier, element multiplier, resist table, crit, `status_damage_mult` (mark only), `mob_strike` / `mob_hurt`, and chill×3 → `stun 90` for Frost Nova;
  - `rpg_keystones` / `rpg_keystone`; the scratch `rpg_ability_unlocked` patch;
  - the `PROJ_KNIFE` spawn only needs `arrows_spawn`, which exists.
- **W5:**
  - `combat_player_status` (sets `combat_burn_t = 180`, `combat_chill_t = 120`, poison stacks + 1 up to 5), `combat_attacker` dd −1, `combat_kb_mult` (1.0), `status_speed_mult` (1 − 0.2·chill), `explode_dmg_mult` dd 0.0;
  - `gear_drop_from_mob` (ret); `rpg_level` exists.

**Test contents** (exact expectations derive from the formulas above; the inputs are fixed here):
- **`test_rpg_attributes_and_respec`** (Warrior):
  - L2 via `rpg_add_xp(31)` gives 3 attribute points. 3×STR → MELEE 13, MAX_STAMINA 123, MAX_HEALTH 26.
  - Poke level 10 and recompute: 24 points left. DEX×12, INT×10, VIT×2 → RANGED 12, ATTACK_SPEED 4, CRIT 7, SPELL 10, MAX_MANA 20, MANA_REGEN 1, MAX_HEALTH 44.
  - Respec at L10 costs 50: refused with 49 coins; with 60 coins it is paid (10 left) and attrs/ranks are 0.
  - Attribute save/load round trip; an over-spent header has its attrs zeroed.
- **`test_rpg_keystones_and_caps`:**
  - Warrior L30, ranks 0..4 = 1, spend node 5 → `rpg_keystone(KS_EXECUTIONER)` 1.
  - Juggernaut path (nodes 6..11) → ARMOR_BONUS 5, MOVE_SPEED −15.
  - At L29 node 11 returns 3.
  - DEX poke 400 → CRIT 75, ATTACK_SPEED 100.
  - Version-0 header with class 2 → ranks 0, version 1.
  - `rpg_xp_need` 31 / 44 / 2911 / 0 at L1 / L2 / L49 / L50.
  - `rpg_on_mob_killed(ZOMBIE, 0, 11)` → +20 XP; elite → +60.
- **`test_gear_decode_deterministic`:**
  - `gear_make(IRON_SWORD, 5, RAR_RARE, 77)` == 0x9400 | 77.
  - Decoding twice gives identical output: 4 distinct stats, every kind mask includes GK_MELEE, every value in [lo + 5tlo, hi + 5thi].
  - Magic 2 affixes, epic 5; dmg 0 → 0; STONE_PICKAXE dmg 7 → 0.
  - Names: common IRON_SWORD "Iron Sword"; magic = "<word0> Iron Sword".
  - `gear_rarity(KINGS_BLADE, x)` = RAR_LEGENDARY.
- **`test_gear_stats_and_powers`:**
  - Held rare sword adds exactly its 4 affix values; unselected → nothing.
  - A worn chestplate adds its affixes; the same piece selected in the hotbar adds nothing.
  - A ring in a jewelry cell adds; EMBER_AMULET gives FIRE_DMG +20 and `gear_has_power(LP_EMBERS)` 1.
- **`test_gear_drops_and_chests`:**
  - `rng_seed(1234)`: 1000 × `gear_roll(RING, 4, LOOT_BOSS)` → no common, ≥ 1 epic. 1000 × LOOT_SHOP → no common.
  - `gear_tier_for_level` 1→0, 4→1, 50→15.
  - 200 × `gear_pick_base(5, CLASS_ARCHER)` → only gear ids, ≥ 1 BOW.
  - `gear_fill_chest(LOOT_BOSS, 13, 2, seed 9)` → exactly 2 gear cells of rarity rare/epic; the same seed again gives an identical chest.
  - An elite zombie L10 death adds ≥ 1 gear drop with tier 3.
- **`test_gear_jewelry_and_no_wear`:**
  - Ring → ref 78 placed; amulet → 78 refused; amulet → 80 placed; shift-click of a second ring → 79.
  - `inv_damage_held` on a held gear sword returns 0 with dmg unchanged; a STONE_PICKAXE goes 0 → 1.
  - Every id with `item_gear` ≠ 0 has durability 0.
- **`test_damage_pipeline`** (class none, CRIT_CHANCE 0, stats poked after recompute):
  - pig, MELEE base 5, MELEE_DMG 20 → 6;
  - ADD_FIRE 2, base 4 → 6 and burn applied;
  - zombie, same → 7 (fire −50%);
  - skeleton SPELL poison base 5 → 0, health unchanged;
  - crit with CRIT_DMG 50 → ×2.0; shock 2 → ×1.2; mark → ×1.3; elite with ELITE_DMG 50 → ×1.5;
  - KS_EXECUTIONER on a zombie at 5/20 → ×1.6;
  - LIFESTEAL 50 on 8 dealt → +4 health.
- **`test_status_effects`:**
  - burn_dmg 1.0 → 1 per 30 steps, 6 in total over 180 steps;
  - 3 poison applications of mag 10 → stacks 3, tick 2;
  - chill ×2 → speed mult 0.6; the 3rd → stun 90, freeze_cd 120; a 4th during cd → chill 1;
  - shock is capped at 3 (mult 1.3); timers expire to 0;
  - a DoT kill of a tagged zombie pays XP.
- **`test_heavy_attack_and_speed`:**
  - cd: iron sword 12, with ATTACK_SPEED 50 → 8; hammer 20; spear 14.
  - Heavy with an iron sword on a zombie: stamina 100 → 80, damage round(7·2.2) = 15, stun 20, bleed_t 180. With stamina 10 → 0 and nothing happens.
  - A hammer light hit stuns 12.
- **`test_player_statuses_and_defenses`:**
  - burn 12 → tick 2, health −2 after 30 steps despite invuln;
  - poison is capped at 5 stacks; chill → speed ×0.6;
  - THORNS 3 vs an attacking zombie → 17;
  - Mana Shield: mana 100, hit 10 → mana 94, health −7;
  - Phoenix saves once (health = max/2, cd 7200), then death;
  - a dodged hit sets riposte 60;
  - max health 40, blocked 4 → stamina −12;
  - fall of 5 blocks at max 40 → 4.
- **`test_new_abilities`:**
  - Ground Slam (Warrior L15 with rank 1 in nodes 12, 13, 14, 15 only, crit chance 0): stamina −45, cd 720; iron sword → zombie at 3 blocks takes round(7·1.5·1.1) = 12 with stun 40 and vy ≥ 6; a zombie at 5 blocks is untouched, but is hit with AREA 50.
  - Frost Nova (Mage L15 with rank 1 in nodes 12, 13, 14, 15 only): mana −35, a pig at 4 blocks is stunned 90 and takes round(6·1.1·1.08) = 7.
  - Hunter's Mark: mark_t 600 with a target; no target → no cost.
  - Fan of Knives: 8 PROJ_KNIFE, damage 4, flag AF_BLEED.
  - Blood Magic Fireball: health −5, mana unchanged.
  - Barrage Volley: 7 arrows.
- **`test_mob_levels_and_scaling`:**
  - Warrior poked to L10: a spawned zombie is level 10 with max health 47; `mob_set_level(…, 12)` → 53.
  - At normal difficulty a level-10 zombie blow costs an unarmored player round(3·1.72) = 5.
  - Elite L10 health 118 (single rounding of 20·2.35·2.5 in floats).
  - MOBSAVE round trip of an elite L12 MOLTEN|SWIFT zombie.
- **`test_elite_affixes`:**
  - Seeded `make_elite` → 1 affix at L5, 2 distinct at L20.
  - SWIFT speed = 2.6·1.15·1.3.
  - JUGGERNAUT: knockback 0, health ×1.5.
  - A MOLTEN zombie blow burns the player (`combat_burn_t` 180).
  - VAMPIRIC at 10/20 dealing 3 → 11.
  - `mob_resist(SKELETON, ELEM_POISON)` 100, `(ZOMBIE, ELEM_FIRE)` −50.

**Integration** (integrator):
1. Copy each worker's owned files back (diff against its base first).
2. Register the 13 tests in the order of the table.
3. Build warning-free; `make test` = 129/129.
4. Fix integration breaks in the owners' style. Expected seams:
   - `rpg_on_mob_killed`'s third argument;
   - `explode_magic` callers;
   - `abilities_cd` resd 4 read by the old hud.asm, which still reads 3 entries (harmless until wave 2).
5. Commit.

### Wave 2 — two parallel workers (commit "0.8 screens and HUD")

|worker|owns|implements|
|---|---|---|
|W6 Screens|`rpgscreens.asm`, `invscreen.asm`, `ui.asm`, `menus.asm`, `app.asm`|Skill screen, Character screen, Elder dialog, Merchant, Inventory, `ui_tooltip_lines`, death text, ST_CHARACTER wiring; remove the `V4_*` uses|
|W7 HUD|`hud.asm`, `dmgnum.asm`, `test_hud.asm`|HUD section|

Both work against the committed wave-1 APIs, with no stubs needed. The worker briefs require a headless smoke of each screen: an omabox screenshot proving each drawn element is in place.

**Integration:**
1. Delete `V4_NODES` and `V4_MAX_LEVEL` from common.inc. `grep -n "V4_NODES\|V4_MAX_LEVEL" src` must be empty.
2. Build; tests 129/129; commit.

### Wave 3 — balance and live verification (integrator)

1. **Balance harness** (throwaway, not committed): a test function in a scratch copy builds characters with `rpg_set_class`, poked levels, ranks, attributes, and gear made with `gear_make`, then prints `combat_weapon_preview` and `mob_set_level` health/damage.
   - **Targets:**
     - L1 Warrior with an iron sword kills an L1 zombie in 3 light hits;
     - L25 Warrior (STR 72, nodes 0–4 at 5, tier-8 rare diamond sword with WEAPON_DMG and MELEE_DMG affixes) kills an L25 zombie in 3–6 light hits;
     - an L25 zombie blow takes 5–12% of that Warrior's max health, wearing tier-8 rare iron armor;
     - the same holds at L50 with tier 15.
   - **If outside the range**, adjust only these knobs, in this order, then re-run:
     - `MOB_HP_STEP` ±0.03;
     - `MOB_DMG_STEP` ±0.02;
     - the WEAPON_DMG `tlo`/`thi` ±1.
2. **Live checks** in the order of Verification. Fix anything that fails in the owning module's style, then rerun the failing check.
3. Commit "0.8: builds - attributes, rolled gear with affixes and legendaries, elements and statuses, 18-node trees with keystones, 4th ability, mob levels and elite affixes, heavy attacks, warhammers and spears, character sheet".

### Wave 4 — V1 readiness sweep (commit "0.8 V1 sweep")

1. **Review:** spawn 4 `reviewer` subagents (read-only) on disjoint areas. Each returns findings as file:line, a reproduction, and a severity: crash, save corruption, softlock, broken feature, or cosmetic.
   - R1: save/load, world list, migration, settings and menus (`world.asm`, `saves.asm`, `game.asm` save/load, `menus.asm`, `app.asm`, `settings.asm`, `options.asm`).
   - R2: combat, mobs, abilities, statuses, gear and loot interactions.
   - R3: inventory, crafting, containers, recipe book, screens, HUD.
   - R4: blocks, placement, structures, light, rendering, performance.
2. **Fix:** reproduce each crash, corruption, softlock or broken-feature finding with a test or a live check, fix it, and keep a regression test where practical. Cosmetic findings go into the final report as deferred items.
3. **Regression playthrough:** a fresh survival world, seed 42, played in the box:
   - pick a class, craft tools, mine to iron, smelt, build with doors and stairs;
   - fight at night with a torch base, level to 5 and spend points;
   - visit the village (trade, gamble, quest) and clear a dungeon;
   - save, quit to the title, reload, and confirm that inventory, jewelry, ranks, attributes and mob levels persist.
4. `make clean && make`, `make test` = 129/129 (plus any regression tests added in this wave). Commit.

## Critical files & anchors

- `src/common.inc`: every contract above, plus `RPGSAVE` / `WORLDHDR` / `MOB` / `INVENTORY` layouts. These offsets are load-bearing for saves and the throwaway patcher.
- `src/combat.asm`:
  - `combat_melee` (~539), `player_take_hit` (~405), `combat_step` (~135), `melee_cd` (:47);
  - the new `combat_hit_mob` / `combat_calc`, which every player damage path must go through (guns excepted).
- `src/rpg.asm`: `rpg_recompute` (~378), `node_tab`, `abil_tab`, `rpg_can_spend` (~617), `rpg_load` (~760). It owns all tree and stat data.
- `src/world.asm`: `world_load` (~233), `convert_v2`, `convert_v1`, `migrate_items_v3`. v4→v5 conversion must keep 0.6/0.7 saves loading.
- `src/game.asm`:
  - `sim_step` (~1328), the melee and heavy path (~780), bow (~1134–1265), the ability loop (~708), `try_potion` (~456), `game_save` (~321) / `game_load` (~184);
  - the per-frame input that feeds the pipeline.

## Verification

1. **Build and tests:** `make clean && make 2>&1 | grep -iE "warn|error"` prints nothing. `make test` ends with `selftest: 129 passed, 0 failed` (more if wave 4 adds regression tests).
2. **Old saves:**
   - Load a 0.6 file (`/tmp/rpg06_crypt.acw` if present) or a 0.7 file as `old.acw` in the box. To make a 0.7 file, `git worktree add /tmp/ac-v07 ec2f5e0 && make -C /tmp/ac-v07`, run it in the box, and play and close a world.
   - On load: the banner "The skill trees changed: points refunded"; the K screen shows all points unspent; weapons and armor show as Common.
   - After close, the file is 4227072 bytes with magic "ACRAFT05".
3. **Progression:** on `--play b08 --seed 42`, patch `rpg=1:30`.
   - The character sheet shows 87 attribute points and the skill tree 30 points.
   - Spending 20 STR raises "Melee damage" by exactly 20.
   - Taking Juggernaut shows armor +4 and move speed −15.
   - Tab switches the two screens; the 4th ability key X casts Ground Slam once node 15 is ranked.
4. **Gear:**
   - Spawn elites with `mob=0:257:200:3:0:0` (an elite zombie; level 0 = player level), kill them, and see coloured beams on the drops.
   - The tooltip lists the affixes. Equipping a ring changes the listed sheet stats by its affix values; shift-hover shows the equipped item.
   - Gamble at the merchant gives a magic+ ring.
   - Patch `jewel=2:202:32769` (EMBER_AMULET, rarity rare, tier 0, seed 1): the sheet's Fire damage is +20 plus its affixes.
5. **Statuses and combat:**
   - A fire-affixed weapon sets zombies burning (orange tint and numbers); Frost Nova freezes ("FROZEN", blue tint).
   - Fan of Knives makes enemies bleed (red DoT numbers). Hunter's Mark shows a red bar frame.
   - Holding LMB 0.5 s on a zombie turns the crosshair gold and the release lands a heavy hit with SND_HEAVY. A warhammer stuns.
   - A Molten elite burns the player (orange pip).
6. **Mob plates:** "Lv N" over hurt hostiles; elites show their affix names.
7. **Performance:** with `PULSE_SERVER=unix:/nonexistent` and `vsync=0`, FPS in the village is ≥ 150. A throwaway `glfwGetTime` print around `rpg_recompute` averages ≤ 0.05 ms.
8. **Wave 4 regression playthrough** (Approach, wave 4 step 3) passes.

## Assumptions & contingencies

- **No questions asked:** the user is asleep, so these defaults stand and can be overridden later.
  - Mob levels follow the player's level: surface = player level, dungeon +2, boss ≥ 20. The world is too small for distance-based zones.
  - Gear never wears; tools still do.
  - Old saves get their skill points refunded, and old weapons and armor become Common.
  - Health grows by 2 per level, and hearts show proportionally with a number.
  - The 4th ability is on X. The character sheet is reached with Tab from the skill screen (K).
  - Rings, amulets and their legendaries are not craftable. They drop, or come from the merchant's 30-coin gamble.
- **Tile budget:** exactly the 23 free tiles are used, and `grep` confirms texgen draws none of them today. If any of them proves to be read as a texel elsewhere, `TILE_STAT_ELITE` falls back to the coin tile 138 and `TILE_KEYSTONE` to the crit-damage stat tile 160 drawn with a gold tint. Report the fallback.
- **Recompute cost:** if `rpg_recompute` per step exceeds 0.05 ms, call it instead from `inv_click`, hotbar selection changes, `rpg_spend*` and level-up, and keep the per-frame call in `screen_character`.
- **Sibling contract mismatch:** if a sibling's real symbol behaves differently from this plan at integration, the plan wins. Fix the deviating module, not the caller.
- **Header size:** if growing the header to 32768 breaks anything outside the files listed in wave 0, fix that consumer in wave 0. The other route — squeezing data into `RPGSAVE.pad` — is not taken.

## As built (deviations from this plan)

- **Balance:** `MOB_DMG_STEP` is 0.10 (was 0.08). The balance harness (Warrior with the listed build, tier-8 / tier-15 rare gear) gives 3 light hits per zombie at L1, L25 and L50 (target 3–6, met). A zombie blow costs 3.5 % (L25) and 3.1 % (L50) of that Warrior's health; the 5–12 % target is not reachable with the plan's knobs (armor cap 20 plus health affixes dominate), see the release notes.
- **XP curve:** `rpg_xp_need(29)` is 1151, the plan's formula (the "1131" above is a typo).
- **Frost Nova** hits hostile mobs only, as its effect text says; its test uses zombies and a skeleton (25 % frost resistance) and keeps a pig as the untouched control.
- **War Cry and Charge** skip JUGGERNAUT elites and never shorten a longer stun (a freeze), like every other stun source.
- **Burn flicker** on mobs uses `(burn_t >> 3) & 1` (MOB has no age field).
- **Loot sounds:** one per death, the loudest of the drops (legendary over rare), not one per drop.
- **`gear_fill_chest`** ignores magic find and class: a chest depends only on its seed.
- **Tooltips:** bows and staves show their real base damage (9 / 13, 4 / 7); "Durability d/D" shows remaining/max; the hammer/spear note is its own line. No "Shift: compare" for a stack that is itself equipped.
- **HUD:** "Level N (K)" sits right of the hotbar (clamped to the screen); the ability row moves above the left HUD stack when `x0 − 93` would leave the screen (narrow GUIs). A marked mob always shows its plate.
- **Character sheet:** a stat line wider than its column falls back to "<label>: <value>" (e.g. "Added fire: +20"); no scroll indicator.
- **Heavy attack:** any screen or pause cancels a charge (`app_goto`); a landed heavy blow also swings the hand; every refusal plays the dry click.
- **Environment damage** is scaled once in `survival_damage` (fall, starvation, suffocation, fire); the starvation floor uses the same scaled unit, so Normal never starves to death.
- **Saves:** pre-0.8 legendaries migrate with the legendary roll (RAR_RARE bits, seed 1) so their 4 affixes appear; a pre-0.8 elite rolls its affixes on load; a load restores the inventory before the character so gear health survives; a new world's animals take the new character's level; closing the window or quitting to the title returns the cursor stack and crafting grid to the inventory before saving.
- **Dungeon elites** raised to level 15+ by `mob_set_level` roll their second affix.
- **Shift-click** equips armor and jewelry only from the survival inventory screen, which shows those cells.
