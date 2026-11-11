# Runes: combinable magic attributes (AssemblyCraft 0.14)

## Context

The player wants a more complex magic system. You unlock attributes such as *ball*, *laser*, *fire* and *poison*, and you combine up to 4 of them by casting their keys together. Some attributes are utilities, such as *tp* and *dash*. These product decisions are fixed:
- **Casting:** no menu. Each rune owns a key. Hold rune keys, or tap them shortly before, then press the cast key.
- **Unlocking:** runes come from the grimoire web and from Rune items, which drop from mobs and turn up in chests.
- **Requirements:** casting needs nothing in hand.
- **The Mage:** its 4 abilities are **replaced** by runes. The other archetypes keep their abilities and the Q/G/V/X bar.
- **Roster:** 16 runes.
- **Multiplayer:** spells work in multiplayer in this release.

End state:
- 16 runes, castable by any character that has unlocked them.
- The Mage path teaches Ball and Fire. Three former Mage ability nodes teach Phase, Laser and Nova.
- 16 Rune items, learned with a right-click.
- A HUD rune strip with a live preview of the combination.
- Spells visible to peers.
- `make test` green with the new tests, warning-free build.
- Old saves load. Their ability bar is remapped and their Mage nodes now teach runes.

Repo: `/run/media/octopusman/Games/Experiences/assemblycraft`, x86-64 NASM, SysV ABI. rsp is 16-aligned at calls, and rbx, rbp and r12–r15 are callee-saved. Every function gets a header comment with its signature. Byte ids are loaded with `movzx`. Tests are `test_<name>() → eax` (0 = pass) and are registered in `src/selftest.asm`: one `extern`, one `TEST` row and one `TESTNAME` row, appended. Every new assertion gets a negative control: break the code once, watch the test fail, restore. Before starting, run `git status` and `git log -1`. HEAD should be `cf910c0` or later, and the only untracked files should be `.omp/`, `.asm-lsp.toml` and `feature-requests.md`; never add these. Commit once per step below.

## Rules of the system (the spec every step implements)

### The 16 runes

The id order is canonical. Every tie-break and the HUD order follow it.

|Id|Rune|Class|Default key (GLFW)|Mana|Cooldown (steps)|Delivery base dmg|Effect|
|---|---|---|---|---|---|---|---|
|0|Ball|delivery|Y 89|10|30|6|Orb that flies straight at 28 b/s and hits the first mob|
|1|Laser|delivery|U 85|16|90|5|Instant beam from the eye that passes through mobs and stops at the first block|
|2|Nova|delivery|I 73|18|240|5|Burst around the caster, radius 5|
|3|Phase|delivery|O 79|14|240|4|Teleport up to 8 blocks along the look ray (Blink's rules)|
|4|Dash|delivery|P 80|8|120|4|Horizontal surge of 18 b/s, untouchable for 20 steps|
|5|Fire|element|H 72|6|0|–|Damage becomes `ELEM_FIRE` (burn)|
|6|Frost|element|J 74|6|0|–|`ELEM_FROST` (chill; 3 chills freeze)|
|7|Shock|element|L 76|6|0|–|`ELEM_SHOCK` (shocked foes take more damage)|
|8|Poison|element|; 59|6|0|–|`ELEM_POISON` (stacking poison)|
|9|Burst|modifier|N 78|10|60|–|Explosion where the spell lands|
|10|Pierce|modifier|M 77|6|0|–|Ball: up to 3 mobs. Laser: range 12 → 24|
|11|Seek|modifier|, 44|6|0|–|Ball homes on the nearest hostile|
|12|Chain|modifier|. 46|8|30|–|Arc from the first victim to 2 more mobs within 6 blocks, half damage|
|13|Heal|boon|0 48|20|240|–|Heal max(6, 20 % of max health)|
|14|Haste|boon|- 45|12|300|–|Move speed ×1.3 for 600 steps|
|15|Feather|boon|= 61|10|180|–|vy ≥ +6 at cast, then 300 steps of vy ≥ −2 b/s and no fall damage|

- Element rune `r` maps to `ELEM_*` = `r − 4`.
- **Every rune key and the cast key is a rebindable binding.** They appear in the Controls screen and persist in the settings file like every other key, so a player can put them on a 12-button mouse, which sends keyboard keys, or anywhere else.
  - `BIND_CAST 19` defaults to **Right Shift (344)**.
  - `BIND_RUNE0 20` … `BIND_RUNE0 + 15 = 35`, one per rune in rune order. The defaults are the "Default key" column: top row deliveries, home row elements, bottom row modifiers, `0 - =` boons.
- **A digit 1..9 that is bound to any action no longer selects its hotbar slot.** Today the digits are hard-coded hotbar keys, so a 12-button mouse sending `1`…`=` would otherwise switch the held item on every rune press.

### Reading the stack

- `spells_input(held, down)` runs every captured frame.
- A rune whose key **rose** during the last `SPELL_ARM_STEPS = 45` fixed steps is *armed*. Every new rising edge restarts that shared timer. When the timer reaches 0, the armed set clears.
- At the cast key's rising edge the stack is `held | armed`. A cast clears the armed set, whether it succeeded or failed.

### `spells_resolve(stack, unlocked, out SPELLPLAN*) → eax` (pure; the core every test hits)

1. `s = stack & unlocked & 0xFFFF`. Locked runes are ignored, cost nothing and are not "dropped".
2. `kept` = the first `SPELL_MAX_RUNES = 4` set bits of `s` in ascending id order. `dropped = s & ~kept`.
3. If `kept == 0`, return 0.
4. `d` = the lowest delivery bit in `kept`. If there is none and `kept` has any element or modifier bit, `d` is Ball when Ball is unlocked. That *implicit Ball* is OR-ed into `kept` (it counts for cost and cooldown, not for the cap). Otherwise `d = −1`, which means a self cast.
5. `inert` starts as the delivery bits in `kept` other than `d`.
6. If `d = −1`:
   - all element and modifier bits go to `inert`, and `elems = mods = 0`;
   - if `kept` has no boon bit, return 0.
7. Otherwise:
   - `elems = kept & RUNES_ELEMENT`;
   - `mods = kept & RUNES_MOD & applies[d]`;
   - the rest of the modifiers go to `inert`.
   - `applies`: Ball = Burst | Pierce | Seek | Chain. Laser = Burst | Pierce | Chain. Nova, Phase and Dash = Burst.
8. `boons = kept & RUNES_BOON`.
9. Totals, with `n = popcount(kept)` including the implicit Ball and inert runes:
   - `cost = Σcost × (100 + 15(n − 1)) / 100` (integer division);
   - `cd = Σcd` in steps;
   - `dmg = base[d] + 2 × popcount(elems)` (0 when `d = −1`).
10. Return 1.

Worked results (these are test vectors):

|Stack (all unlocked unless noted)|delivery|elems|mods|inert|dropped|cost|cd|dmg|ret|
|---|---|---|---|---|---|---|---|---|---|
|Ball+Fire|Ball|Fire|–|–|–|18|30|8|1|
|Laser+Frost+Pierce|Laser|Frost|Pierce|–|–|36|90|7|1|
|Fire+Poison|Ball (implicit)|Fire,Poison|–|–|–|28|30|10|1|
|Fire+Poison, Ball locked|–|–|–|–|–|–|–|–|0|
|Ball+Laser+Fire+Burst+Seek+Heal|Ball|Fire|Burst|Laser|Seek,Heal|60|180|8|1|
|Nova+Seek|Nova|–|–|Seek|–|27|240|5|1|
|Heal|−1|–|–|–|–|20|240|0|1|
|nothing|–|–|–|–|–|–|–|–|0|

### Damage, crit and order of effects

- Each element in `elems` deals `dmg / nelem` (float) as its own `combat_hit_mob(mob, SRC_SPELL, elem | crit, base, dirx, dirz)`. So Fire + Poison applies both statuses through the pipeline's automatic element → status rule.
- With no element, there is one `ELEM_PHYS` hit of `dmg`.
- Crit: `ab_crit()` is rolled once per cast. A crit adds `HITF_CRIT` to every hit of that cast.
- Nova + Frost adds `HITF_CHILL3` to the frost hits (instant freeze, the same as the old Frost Nova).
- Chain hits add `HITF_CHAIN`.
- Execution order: delivery first, then boons.

### Casting flow: `spells_cast(rdi eye float[3], rsi dir float[3]) → eax 1/0`

1. No stack, or resolve returns 0: dry-fire click.
2. `spells_cd > 0`: dry-fire.
3. Riding a boat or a plane: return 0 silently.
4. Phase whose plan fails: dry-fire. Dash whose horizontal look is shorter than 0.05: dry-fire.
5. `combat_pay(RES_MANA, cost)` fails: dry-fire. This keeps Blood Magic and creative mode working.
6. Cooldown: `spells_cd = spells_cd_total = cd × (100 − STAT_COOLDOWN_RED) / 100`.
7. Run the delivery, then the boons.
8. Clear `combat_stealth_t`, swing the hand, set `net_swing_t = 10`.
9. Return 1.

Every dry-fire uses the `abilities_use .fail` sound (`SND_DRY_FIRE`, `k_vol_fail`). If the projectile pool is full (`arrows_spawn` returns −1), the mana is still spent.

## Approach

Steps run in order. Each step ends with `make -j && make test` green, then a commit.

### Step 1: Contracts (additions only)

In `src/common.inc`:

**Runes**
- `NUM_RUNES 16` and `RUNE_BALL 0` … `RUNE_FEATHER 15`, named as in the table.
- Class masks: `RUNES_DELIVERY 0x001F`, `RUNES_ELEMENT 0x01E0`, `RUNES_MOD 0x1E00`, `RUNES_BOON 0xE000`.
- `MAGE_PATH_RUNES ((1 << RUNE_BALL) | (1 << RUNE_FIRE))`, `SPELL_MAX_RUNES 4`, `SPELL_ARM_STEPS 45`.
- `NODE_RUNE 4`, after `NODE_PATH`.

**Projectiles, effects and network**
- `PROJ_SPELL 7`, after `PROJ_GRENADE`. `FX_POISON 8`, after `FX_FROST`.
- `MT_SPELL 67`, with `NUM_MT 68`. `SPM_BEAM 0`.

**Items and bindings**
- `RUNE_FIRST (FIRST_ITEM + 93)`, and `NUM_ITEMS` changes to `(FIRST_ITEM + 109)`, i.e. ids 237..252.
  - **Defer** the `NUM_ITEMS` change to Step 4, so the item tables stay consistent. In this step add only `RUNE_FIRST`.
- `BIND_CAST 19`, `BIND_RUNE0 20`, and `NUM_BINDINGS 36`.
  - **Defer** this to Step 5, together with its settings, labels and Controls page.

**Structs**
- `struc RUNEINFO` (32 bytes, `%error` size check): `.name` q zstr, `.desc` q zstr, `.cost` d, `.cd` d (steps), `.dmg` d (delivery base, 0 otherwise), `.pad` d.
- `struc SPELLPLAN` (44 bytes): dwords `.runes .dropped .delivery .elems .nelem .mods .inert .boons .cost .cd .dmg`.
  - `.delivery` is a rune id or −1.
  - `.runes`, `.elems`, `.mods`, `.inert`, `.boons` and `.dropped` are rune bitmasks.
- `struc RPGEXT`: carve `.runes: resw 1` at +180 (runes learned from items, bit r = rune r). `.pad2` becomes `resb 74`. The 256-byte assert stays.
- `struc FRAMEINPUT`: append `.runes_held resd 1`, `.runes_down resd 1` and `.cast resd 1`. If a size `%error`/test pins 112, update it to 124.
- `struc SPELLMSG` (MT_SPELL): `.kind` b, `.elem` b, `.pad` 2, `.len` d (float), `.dir` 3 d (float), `.pos` `resb NPOS_size`.

### Step 2: Retire the four Mage abilities and renumber the rest (depends on 1)

Ability ids become a dense index. Warrior 0–3 and Archer, Rogue and Marksman 4–15 (old id − 4). `NUM_ABILITIES 16`.

**`common.inc`**
- `ABIL_SHADOWSTEP 8`, `ABIL_GRENADE 12`, `ABIL_BULLSEYE 13`, `ABIL_FANHAMMER 14`, `ABIL_FLASHBANG 15`.
- Add `%define ABIL_BASE(a) ((((a) - 1) - ((a) > ARCH_MAGE)) * 4)`: Warrior 0, Archer 4, Rogue 8, Marksman 12. The Mage has no abilities.
- Rename `ABILINFO.pad` to `.tile`.
- `RPGX_VERSION 4`.

**`rpg.asm`**
- `ABIL` macro: gets a 7th argument, the tile, stored in `.tile`.
- `abil_tab`:
  - Delete rows fireball, blink, meteor and nova.
  - Tiles for the remaining rows, in order:
    - Warrior: `TILE_ABILITY0+0`, `+1`, `+2`, `TILE_ABILITY3_0+0`.
    - Archer: `TILE_ABILITY0+6`, `+7`, `+8`, `TILE_ABILITY3_0+2`.
    - Rogue: `TILE_ABILITY0+9`, `+10`, `+11`, `TILE_ABILITY3_0+3`.
    - Marksman: `TILE_MK_ABIL0+0..3`.
- `rpg_ability_tile`: becomes `id < NUM_ABILITIES ? abil_tab[id].tile : 0`. Delete the arithmetic.
- `ANODE` macro: stat becomes `ABIL_BASE(wb_arch) + %2`.
- `rpg_ability_learned`, path branch: a path node with `.stat == ARCH_MAGE` teaches no ability (`jmp .next`). Otherwise use `ABIL_BASE(stat)`, computed in registers as `(stat − 1 − (stat > ARCH_MAGE)) × 4`.
- `rpg_spend`: the path auto-bind (`bar_put_first_empty`) is skipped for the Mage path.
- `rpg_load`: when the loaded `.version == 3`, remap each of the 4 `.bar` bytes before the `.current` checks. 5..8 (old ids 4–7) → 0; ≥ 9 → b − 4. The existing stamp writes 4.

**`abilities.asm`**
- Delete:
  - `ab_fireball`, `ab_blink`, `ab_meteor`, `ab_nova`, `ab_meteor_step` and its call in `abilities_step`;
  - `meteor_n`, `meteor_t`, `meteor_tgt` (with the `global` and the `abilities_shift` lines);
  - `IDX_BLINK` and its `.plan_blink` branch;
  - `METEORS`, `METEOR_GAP`, `METEOR_DMG`, `FIREBALL_DMG` and every `k_fireball_*`, `k_meteor_*`, `k_nova_*` constant left unused.
- **Move** `ab_blink_plan` to `spells.asm` (Step 6) as `sp_phase_plan`, with the same signature and body.
- `ab_effects`: drop the Mage row.
- New indices: `IDX_MARK 7`, `IDX_SHADOW 8`, `IDX_SMOKE 9`.
- Export `ab_crit`, `ab_sweep`, `ab_burst` and `ab_box_free` (add to `global`) for `spells.asm`.
- `abilities_staff_bolt`, its `LP_ARCHMAGE` fireball (`PROJ_FIREBALL` stays) and the Mage-path rank gate stay unchanged.

**Mage path text**
- `PATHNODE` argument 5 becomes a string expression: `"Learns ", %5, "."`.
- Warrior, Archer, Rogue and Marksman pass `aname_<their slot-0 label>`. Find them with `grep -n "PATHNODE" src/rpg.asm`.
- The Mage passes `"the Ball and Fire runes"`.

**`texgen.asm`**
- Delete `BMP 142`, `143`, `144` and `218` (fireball, blink, meteor, nova), their bitmaps, any palettes no longer referenced, and the header-comment names.

**Tests: rewrite to the new ids; no re-pinning of incidental values**
- `test_abilities.asm`:
  - `AB_*` defines.
  - `test_ability_bar_binding` becomes the Warrior: the path auto-binds Charge to slot 0, and Deep Mind becomes a Warrior stat node; same structure.
  - Delete the Mage parts of `test_ability_cost_cooldown_and_unlock`.
  - Delete `test_fireball_explodes_without_breaking`, `test_blink_stops_before_wall`, `na_frost_nova` and the meteor half of `na_projectile_bases`. Step 6 recreates their behaviour as rune tests.
  - `na_blood_magic`: switch to a rune cast in Step 6. Until then, delete only its Fireball cast.
- `test_rpg.asm`:
  - `exp_abil` loses the Mage row.
  - The `rpg_ability_learned` truth table: the Mage path teaches no ability.
  - `abil_node_ok` skips `ARCH_MAGE`.
  - `rpg_ability_tile` checks for the new ids.
- `test_mobs.asm`: drop the `meteor_tgt` rebase lines.
- Fix every other hit of `grep -n "AB_FIREBALL\|AB_BLINK\|AB_METEOR\|AB_NOVA\|meteor_tgt\|ABIL_SHADOWSTEP\|ABIL_GRENADE\|ABIL_BULLSEYE\|ABIL_FANHAMMER\|ABIL_FLASHBANG\|NUM_ABILITIES" src/*.asm`. Constant users rebuild unchanged; literal ids must be rewritten.
- New test `test_rpg_v3_bar_remap`: a header with version 3 and `.bar = {5, 9, 13, 0}` loads as `{0, 5, 9, 0}`.

### Step 3: Rune unlocks in the grimoire (depends on 2)

**`rpg.asm`**
- New macro `RNODE name, desc, rune, x, y`: `FORMER …, NODE_RUNE, rune, 1, 0, x, y`.
- Replace the three Mage `ANODE`s in place. Edges are positional and so unchanged.

  |Was|Becomes|
  |---|---|
  |`ANODE blink, 1, 34, -11`|`RNODE "Phase Rune", "Learn Phase: teleport where you look", RUNE_PHASE, 34, -11`|
  |`ANODE meteor, 2, 51, -17`|`RNODE "Laser Rune", "Learn Laser: a beam through your foes", RUNE_LASER, 51, -17`|
  |`ANODE nova, 3, 54, 2`|`RNODE "Nova Rune", "Learn Nova: a burst all around you", RUNE_NOVA, 54, 2`|

- New exports:
  - `rpg_runes() → eax`: `rpg_ext.runes`, OR `MAGE_PATH_RUNES` when `rpg_rank(ARCH_MAGE − 1) > 0`, OR bit `.stat` of every ranked `NODE_RUNE`.
  - `rpg_learn_rune(edi rune) → eax`: 0 for an invalid rune or one already in `rpg_runes()`. Otherwise it sets the bit in `rpg_ext.runes` and returns 1.
- Web runes are derived, so a respec removes them. Item runes survive a respec; `rpg_respec` does not touch `.runes`, while `ext_reset` zeroes it.
- `rpg_spend`, on a `NODE_RUNE` going from rank 0 to 1: `hud_banner("Rune learned: <Name>", WHITE)`. The name comes from `spells_rune_name` (Step 6). Until then, use the node name.
- `rpg_recompute`'s node loop: `NODE_RUNE` adds no stat. Confirm that it reaches the same `.next` as `NODE_ABILITY`.

**`rpgscreens.asm`**
- Find every `NODE_ABILITY` switch with `grep -n NODE_ABILITY src/rpgscreens.asm`.
- `NODE_RUNE` draws `NINE_NODE_ABIL` with `ui_item_icon(RUNE_FIRST + stat, …, 16)`.
- It uses the WREC name and desc in the tooltip, and `web_node_ability` returns −1 for it, so there is no bar binding.

**`test_rpg.asm`**
- `exp_web`: the Blink row becomes `EXPW "Phase Rune", 30, NODE_RUNE, RUNE_PHASE, 1, ARCH_MAGE, 0, 34, -11, 4`.
- `web_nodes_ok`: for `ARCH_MAGE` at n ∈ {7, 9, 15}, expect `NODE_RUNE` with stat {Phase, Laser, Nova} instead of `NODE_ABILITY`.
- New test `test_rune_unlocks`:
  - a fresh character has `rpg_runes() = 0`;
  - spending the Mage path gives Ball | Fire;
  - spending node 30 adds Phase;
  - `rpg_learn_rune(RUNE_POISON)` returns 1, then 0 a second time; `rpg_learn_rune(16)` returns 0;
  - save → load round-trips Poison;
  - a respec leaves exactly Poison.

### Step 4: Rune items, drops, chests, right-click to learn (depends on 3)

**Items**
- `NUM_ITEMS (FIRST_ITEM + 109)`.
- `itemdefs.asm`: names `"Ball Rune"` … `"Feather Rune"`, in rune order, appended after the last item. Max stack is 16. There are no tool, gear or attack entries; `END_TABLE` defaults cover the rest.

**Icons**
- New file `src/iconart_runes.asm`: 16 `SKBMP` 32×32 cells in the `iconart_b.asm` format, each registered in `artreg.asm` (`extern` + `dq`, keeping the exact-count assert).
- Every cell draws the same rounded slate stone (outline `RGB(40,44,60)`, body `RGB(96,104,128)` with lighter top-left `RGB(140,150,176)`), with a distinct glyph about 14 px tall in the centre.
  - Deliveries are gold `RGB(240,200,80)`: Ball, a filled circle; Laser, a horizontal bar with an arrow tip; Nova, an 8-ray star; Phase, two offset circles joined by dots; Dash, three chevrons.
  - Elements: Fire, a flame `RGB(255,140,40)`; Frost, a snowflake `RGB(150,210,255)`; Shock, a zigzag bolt `RGB(255,240,90)`; Poison, a drop `RGB(110,230,80)`.
  - Modifiers are violet `RGB(190,120,255)`: Burst, a ring with spikes; Pierce, an arrow through a bar; Seek, a curved arrow; Chain, three linked dots.
  - Boons are green `RGB(120,230,140)`: Heal, a cross; Haste, a winged boot outline; Feather, a feather.
- `test_icons_art` must stay green: at least 64 opaque texels per cell and all cells distinct.

**Right-click to learn**
- `game.asm`: new `try_rune() → eax 1 when the click was spent`, modelled on `try_potion`:
  - requires `rmb_pressed` and `held_id` in `[RUNE_FIRST, RUNE_FIRST+16)`;
  - calls `rpg_learn_rune(id − RUNE_FIRST)`;
  - on 1: banner `"Rune learned: <Name>"`, built into a 64-byte `.bss` buffer; `SND_SPELL`; swing the hand; consume one in survival exactly as `try_potion` does;
  - on 0: banner `"You already know this rune"`, nothing consumed;
  - returns 1 in both cases.
- Call it immediately before each `call try_potion` (`game.asm:2277`, `:2395`), skipping the potion and the rest when it returns 1, the same way the `try_potion` result is used there.

**Drops**
- `mobs.asm`, `mob_drops`: after **all** existing rolls, so earlier rng draws are unchanged:
  - a hostile non-boss kill drops `RUNE_FIRST + rng_next % 16` when `rng_next % 100 < 2`;
  - the boss always drops one random rune;
  - spawn it with the same call `mob_drops` uses for its `t_drops` items.

**Chests**
- `structures.asm`: append 16 entries `db 1, RUNE_FIRST + r, 1, 1` (a `%rep`) to `loot_dungeon` and to `loot_crypt`.
- If a test pins exact contents of those chest tables, update its expected items to the new deterministic roll, after checking with a diff that only rune entries differ.

### Step 5: Input — rebindable rune keys and the cast key (independent of 3–4; depends on 1)

**Bindings**
- `common.inc`: `BIND_CAST 19`, `BIND_RUNE0 20` (rune r is `BIND_RUNE0 + r`), and `NUM_BINDINGS 36`.
- `settings.asm`, `SETTINGS_IMAGE`:
  - the third defaults line becomes `dd 84, 258, 86, 344`;
  - add a fourth line `dd 89, 85, 73, 79, 80, 72, 74, 76, 59, 78, 77, 44, 46, 48, 45, 61` with the comment `; runes: Y U I O P  H J L ;  N M , .  0 - =`.
- `settings.asm` `SETENT` rows, each `32, 348, 1` like the existing key rows:
  - `"key_cast"`;
  - `"key_rune_ball"`, `"key_rune_laser"`, `"key_rune_nova"`, `"key_rune_phase"`, `"key_rune_dash"`, `"key_rune_fire"`, `"key_rune_frost"`, `"key_rune_shock"`, `"key_rune_poison"`, `"key_rune_burst"`, `"key_rune_pierce"`, `"key_rune_seek"`, `"key_rune_chain"`, `"key_rune_heal"`, `"key_rune_haste"`, `"key_rune_feather"`.
  - Old settings files lack these names and so load the defaults, through the existing per-entry default path.
- `options.asm`, `bind_labels`: `"Cast spell"`, then `"Ball rune"` … `"Feather rune"` in rune order.
  - `test_vehicleview`'s "every binding has a label" check covers them automatically.
- `settings_reset_keys` already resets all `NUM_BINDINGS` keys. Confirm that it loops to `NUM_BINDINGS` rather than to a literal.

**Controls screen: two pages**
- 36 rows cannot fit on one page: the single-column fallback uses at least 14 units per row, so it would need 36 × 14 + 60 units of height.
- `options.asm`, `screen_controls`:
  - new `.bss` `ctrl_page: resd 1` (0 = general, 1 = runes). It is reset to 0 when the screen opens; use the same place `capturing` is reset to −1.
  - Page 0 shows bindings `0 .. BIND_RUNE0 − 1` (20 rows, cast key included). Page 1 shows `BIND_RUNE0 .. NUM_BINDINGS − 1` (16 rows).
  - The row loop runs `ebx` from the page's first to its last binding. The column/row arithmetic (`div [rsp + 36]`) and the narrow single-column row count (`[rsp + 36] = NUM_BINDINGS` today) use `ebx − first` and the page's row count. `CTRL_ROWS 10` and the wide/compact widths are unchanged, because each page has at most 2 columns.
  - Bottom buttons become three, each 100 wide, at `y = ui_h − 28`:
    - `s_reset_keys` at `r12 − 155`;
    - a page toggle at `r12 − 50`, labelled `"Rune keys"` on page 0 and `"General keys"` on page 1, which flips `ctrl_page` and sets `capturing = −1`;
    - `s_done` at `r12 + 55`.
  - `is_dup` keeps scanning all `NUM_BINDINGS`, so a clash across pages still shows red.

**`input.asm`**
- `.bss`: `rune_prev: resd 1`, `cast_prev: resd 1`.
- Every frame, beside the unconditional movement `%rep` (around `:453`), build `held`:
  - a `%rep 16` with `%assign r` of `BIND BIND_RUNE0 + r`, then `shl eax, r` and `or` into a callee-saved accumulator;
  - then `down = held & ~rune_prev`, `rune_prev = held`;
  - `BIND BIND_CAST` / `EDGE cast_prev` gives the cast edge.
- In the captured-only copy block (`:469-489`): write `.runes_held`, `.runes_down` and `.cast`. When not captured, write 0, following how the other captured fields are cleared.
- Hotbar digit loop (`.num`, `:424-448`):
  - before `glfwGetKey`, call new leaf `key_bound(edi code) → eax 1` when any `SETTINGS.keys[0 .. NUM_BINDINGS − 1]` equals `code`;
  - when it is bound, treat the digit as up: write 0 to `prev_num[ecx]` and skip the slot change.
- Test: new `test_bound_digit_skips_hotbar`, in `test_vehicleview.asm` next to the binding-label test.
  - Bind `BIND_RUNE0 + RUNE_FIRE` to `KEY_3`: `key_bound(KEY_3) = 1` and `key_bound(KEY_4) = 0`.
  - Restore the default afterwards.

### Step 6: `src/spells.asm` — table, resolution, casting, effects (depends on 2, 3, 5)

The new module is the sole owner of rune casting. Exports:
- data: `rune_tab` (16 `RUNEINFO` rows from the table), `spells_cd`, `spells_cd_total`, `spells_armed`, `spells_held`;
- functions: `spells_rune_name`, `spells_resolve`, `spells_input`, `spells_cast`, `spells_step`, `spells_reset`, `spells_preview`, `spells_proj_hit`, `spells_proj_end`, `spells_proj_steer`, `spells_beam_fx`, `spells_burst`.

**Small entry points**
- `spells_rune_name(edi) → rax zstr`, or an empty string out of range.
- `spells_resolve` exactly as specified above.
- `spells_input(edi held, esi down)`: `spells_held = held`. If `down ≠ 0`, `spells_armed |= down` and `sp_arm_t = SPELL_ARM_STEPS`.
- `spells_step()`, once per fixed step:
  - `spells_cd−−` while > 0;
  - `sp_arm_t−−`, and at 0 `spells_armed = 0`;
  - while `combat_feather_t > 0`: `player.fall = 0` and `player.vy = max(vy, −2.0)`.
- `spells_reset()` zeroes all spell state.

**Ball**
- `arrows_spawn` at `eye + dir × 0.6`, velocity `dir × 28`, `OWNER_PLAYER`, damage `dmg`, kind `PROJ_SPELL`.
- flags = `crit ? AF_CRIT : 0 | (first element or ELEM_PHYS) << AF_ELEM_SHIFT`. **Never** `AF_EXPLOSIVE`.
- Then:
  - `arrow_spell[slot] = runes | (Pierce ? 3 : 1) << 16`, where bits 16–19 count the mob hits left;
  - `arrow_hitmask[slot] = 0`.
- Sound `SND_FIREBALL` if Fire is in the spell, else `SND_SPELL`.

**Laser**
- `R = Pierce ? 24 : 12`.
- Block distance: `raycast(eye, dir, hit, R)`, refined with `ray_aabb` against the hit cell exactly as `ab_sight_mob` does. That gives `tb`, or `R` on a miss.
- Up to 8 times: `mobs_raycast_skip(eye, dir, mask, tb)`. Stop on −1. Otherwise set the mask bit, apply the per-element hits (dir = horizontal look), and Chain from the first victim only.
- Burst explodes at `eye + dir × tb`.
- Visual: `spells_beam_fx(eye, dir, tb, first elem)`. If `net_role ≠ NET_ROLE_OFF`, also `net_spell_beam_out`.
- Sound `SND_SPELL`.

**Nova**
- `radius = 5.0 × (Burst ? 1.5 : 1) × (1 + rpg_stats[STAT_AREA]/100)`.
- One `ab_sweep(base, radius, 3.0, 0.5, SRC_SPELL, elem | crit | (Frost ? HITF_CHILL3 : 0), 0)` per element, or one physical sweep.
- `ab_burst(fx kind of the first element, 40, 6.0)`.
- Sound `SND_FREEZE` if Frost, else `SND_SPELL`.

**Phase**
- `sp_phase_plan` runs before paying.
- After paying: write `player.x/y/z` and zero `vy`, `kbx`, `kbz` and `fall`, exactly as the old `ab_blink`. Magic sparks at both ends, `SND_BLINK`.
- If elements or Burst are present: `spells_burst(feet + (0, 1, 0), 3.0 × (Burst ? 1.5 : 1), runes, dmg, crit)` at the arrival point.

**Dash**
- `h` = the unit of `(dir.x, dir.z)`.
- `player.kbx/kbz = h × 18.0`, `surv.invuln = max(invuln, 20)`, `player.fall = 0`.
- `fx_burst(FX_MAGIC, 10)` at the feet.
- If elements or Burst are present: `spells_burst` at the departure point, radius `2.0 × (Burst ? 1.5 : 1)`.

**Boons**
- Heal: `combat_heal(max(6, surv_max_health × 2 / 10))`, plus `fx_burst(FX_GOLD, 12)` at the eye.
- Haste: `combat_haste_t = 600`.
- Feather: `combat_feather_t = 300` and `player.vy = max(vy, 6.0)`.

**`combat.asm`**
- `combat_haste_t` and `combat_feather_t` are added to `combat_timers`, so they are aged and reset automatically.
- `combat_speed_mult`: `× 1.3` while `combat_haste_t > 0`, placed after the blade-dance factor (new `k_1_3: dd 1.3` if absent).

**`spells_burst(xmm0..2 pos, xmm3 radius, edi runes, esi dmg, edx crit)`**
- One `explode_magic(pos, radius, dmg / nelem, SRC_SPELL, elem | crit)` per element, or one physical call.

**`spells_proj_hit(edi slot, esi mob, xmm0..2 point, xmm3 hdirx, xmm4 hdirz) → eax 1 keep flying / 0 end`**
- Per-element hits with `ARROWENT.damage / nelem`.
- Set the hitmask bit.
- Chain from the first victim only, when the hitmask had no bit before this hit.
- Decrement the hits left.
- Burst → `spells_burst` and return 0.
- Otherwise return `hits_left > 0`.

**`spells_proj_end(edi slot, xmm0..2 point)`**
- Burst → `spells_burst`.
- `fx_burst(element fx, 8)`.

**`spells_proj_steer(edi slot)`**
- Only for non-ghost spells with Seek.
- Target: the nearest `mob_is_hostile` mob within 16 blocks whose box centre is ahead (`dot(v, to) > 0`) and not in the hitmask. Use the mob box fields that `mobs_raycast` uses.
- `v ← normalize(v + unit(to) × |v| × 0.15) × |v|`.

**Chain**
- Up to 2 nearest hostile mobs within 6.0 blocks of the victim's centre, excluding the victim and the hitmask.
- Each takes per-element hits at half damage with `HITF_CHAIN`, plus `fx_burst(FX_SPARK, 6)`.

**`spells_beam_fx(rdi start, rsi dir, xmm0 len, edx elem)`**
- One `fx_burst(element fx, 1, speed 0.2)` every 0.5 block, with `net_applying = 1` around the loop so it is not mirrored particle by particle.

**Element fx table**
- phys `FX_MAGIC`, fire `FX_FIRE`, frost `FX_FROST`, shock `FX_SPARK`, poison `FX_POISON`.

**`spells_preview(rdi buf96) → eax`** (the resolve result)
- Built from `spells_held | spells_armed` and `rpg_runes()`.
- Format: rune names of `.runes` joined by `" + "`, then `"  "`, the cost, `" mana"`. Append `" (inert: A, B)"` and `" (dropped: C)"` when non-empty.
- When resolve returns 0: `"Nothing to cast"`.

**`game.asm`**
- After the ability loop in section 5b, which is already gated on captured + no screen:
  - `spells_input(runes_held, runes_down)`;
  - if `.cast` and `plane_riding == 0` and `boat_riding == 0`: `spells_cast(&F_EYE, &F_DIR)`.
- `spells_step` right after the `abilities_step` call.
- `spells_reset` right after `abilities_reset` (`game.asm:169`).

**Tests: new `src/test_spells.asm`** (scene helpers copied from `test_abilities.asm`)
- `test_spell_resolve`: every row of the worked-results table.
- `test_spell_ball`:
  - Ball+Fire, 100 mana → mana 82, `spells_cd` 30, a live `PROJ_SPELL` with fire element and damage 8;
  - stepping it into a zombie 6 blocks ahead lowers its health and sets `burn_t > 0`;
  - with 10 mana, the cast fails and mana stays 10.
- `test_spell_pierce_chain`:
  - three zombies in a line take Ball+Pierce: all three are hit and the projectile is gone after the third;
  - Ball+Chain on one zombie with 2 more within 4 blocks hits all three.
- `test_spell_laser`:
  - Laser+Frost hits a zombie at 10 blocks on the cast frame, with chill;
  - a stone block at 5 blocks shields it;
  - with Pierce, a zombie at 20 blocks is hit.
- `test_spell_nova_frost`: replaces `na_frost_nova`. Nova+Frost freezes both zombies in range (stun 90), and a zombie out of range is untouched.
- `test_spell_phase`: replaces the blink test. A wall right ahead fails at no cost. A wall 3.5 blocks away ends at 3.0, with motion and fall reset.
- `test_spell_multi_element`: Ball+Fire+Poison → `burn_t > 0` and `poison_t > 0` on one zombie.
- `test_spell_boons`:
  - Heal from 6 health with max 20 → 12;
  - Haste → `combat_speed_mult` ×1.3;
  - Feather → a fall from 10 blocks deals no damage.
- `test_spell_arming`:
  - `spells_input(0, Fire bit)`, 30 `spells_step`s, then the cast stack includes Fire;
  - after 46 steps it does not.
- `na_blood_magic` now casts Ball (cost 10 → 2 health).

### Step 7: Projectile integration (depends on 6)

**`arrows.asm`**
- New `.bss` side tables `arrow_spell: resd MAX_ARROWS` and `arrow_hitmask: resq MAX_ARROWS` (global). `arrows_spawn` zeroes both for the slot it fills.
- `max_age`: append `120`.
- After `.no_gravity`: for `PROJ_SPELL`, call `spells_proj_steer(slot)`, where slot = `(rbx − arrows) / ARROWENT_size`.
- `.creature`: for `PROJ_SPELL`, call `mobs_raycast_skip` with `rdx = arrow_hitmask[slot]`.
- Top of `.target`, right after `HIT_POINT`: if kind is `PROJ_SPELL` and `S_WHO < 0`:
  - call `spells_proj_hit(slot, S_IDX, S_HP, S_H)`;
  - if it returns 1, jump to `.settle` (handles a block later in this step, else flies);
  - else remove.
  - A PvP player hit keeps the generic path.
- `.settle`: `PROJ_SPELL` → `.spell_block`. It backs up by `c_embed`, runs `HIT_POINT`, calls `spells_proj_end`, then removes.
- `.expired`: non-ghost `PROJ_SPELL` → `spells_proj_end` at its position, then remove.
- Trail: `PROJ_SPELL` uses `spell_fx[(flags >> AF_ELEM_SHIFT) & 7]`.
- Magic draw pass: `PROJ_SPELL` → half-size 0.12, colour `c_spell_col[elem]` from these rows:
  - phys 0.85, 0.85, 1.0
  - fire 1.0, 0.55, 0.15
  - frost 0.6, 0.85, 1.0
  - shock 1.0, 1.0, 0.5
  - poison 0.45, 1.0, 0.3

**`mobs.asm`**
- New entry `mobs_raycast_skip(rdi origin, rsi dir, rdx skip qword, xmm0 max)`, placed in the same function body. `mobs_raycast` becomes `xor edx, edx` falling into it.
- Mobs whose index bit is set in `skip` are ignored. Check that `MAX_MOBS ≤ 64`; if not, the skip test uses `bt` on a 2-qword mask and `arrow_hitmask` grows to match.

**`fx.asm`**
- `FX_POISON`:
  - `burst_tab` row: a copy of MAGIC;
  - `k_burst_col` row `dd 0.45, 1.0, 0.3, 0.15, 0.5, 0.1`;
  - the range check extended to `FX_POISON`;
  - `fx_step` and `draw_pass` treat it like `FX_MAGIC`;
  - extend any `FXMSG.sub` bound in `nx_on_fx` to `FX_POISON`.

**Tests**
- The tests from Step 6 that fly projectiles go green here. Land Steps 6 and 7 in one commit if Step 6 cannot pass alone.

### Step 8: Network (depends on 7)

**`netmisc.asm`**
- The `nx_on_proj` kind gate becomes `cmp eax, PROJ_SPELL`. Ghosts take their colour from the element bits, which survive `AF_WIRE`.
- New `net_spell_beam_out(rdi start float[3], rsi dir float[3], xmm0 len, edx elem)`:
  - fills a `SPELLMSG` with `SPM_BEAM` and `net_pos_out`;
  - a guest sends it with `net_out(MT_SPELL, …, reliable 0)`;
  - the host sends it with `net_relay(-1, MT_SPELL, …, pos, c_proj_range)`.
- New `nx_on_spell(edi slot, esi type, rdx payload, ecx len)`:
  - rejects `len < SPELLMSG_size`, `kind ≠ SPM_BEAM`, `elem > ELEM_POISON`, beam length outside `(0, 24.5]`, any `|dir| > 1.01`, and `|pos.y| > BITS_Y`;
  - then draws `spells_beam_fx` with `net_applying = 1`;
  - the host relays it like `nx_on_proj`.

**`netsync.asm`**
- Append the `nx_on_spell` handler `dq` and its `extern`. The `NUM_MT` count `%error` must pass.

**Known limitation**
- A Seek ball's ghost flies straight on peers until `PROJ_END`.

**Test**
- `test_spell_net` in `test_netmisc.asm`, following that file's message-test pattern:
  - a valid beam message is accepted and spawns particles;
  - lengths 0 and 30, and an element of 5, are rejected;
  - a `PROJMSG` of kind `PROJ_SPELL` spawns a ghost with `AF_GHOST`.

### Step 9: HUD rune strip (depends on 6)

**`hud.asm`**
- New `hud_spells(edi x0, esi y0)`, called right after `hud_abilities` in `hud_draw`. It draws nothing when `rpg_runes() == 0`.
- Strip: k = the number of unlocked runes, in id order.
  - Cells are 14 units wide, starting at `x = ui_w − 4 − 14k`, `y = y0 − 2`.
  - Each cell: `ui_nine(NINE_RUNE, x, y, 14, 14)` and `ui_item_icon(RUNE_FIRST + r, x+1, y+1, 12)`.
  - Runes in `spells_held | spells_armed` get `ui_nine(NINE_SELECT, x−1, y−1, 16, 16)`.
  - Key labels: the name of `settings.keys[BIND_RUNE0 + r]`, from `key_name(edi code, rsi buf)` as `options.asm:465-467` calls it. Draw it above each cell in the same style as `hud_abilities`' key tabs (copy the `hud.asm:1364` call), so a rebind shows at once.
- Cooldown: while `spells_cd > 0`, `ui_rect(strip_x, y + 15, strip_w × cd / total, 2, C_MANA)`.
- Preview: when held or armed is non-empty, the `spells_preview` text is right-aligned 20 units above the strip.
  - Colour `C_CREAM`.
  - `RGBA(255,90,90,255)` when `combat_mana` is below the plan's cost, or when resolve returns 0.

## Critical files & anchors

- `src/arrows.asm`: `max_age` (:75), `.no_gravity` (~:291), `.creature` (~:332), `.target` (~:369), `.settle` (~:646), `.expired` (~:813), trail (~:848), magic pass (~:1164). These are all the `PROJ_SPELL` hook points.
- `src/rpg.asm`:
  - `ABIL`/`abil_tab` (:210-246), `ANODE`/`PATHNODE` (:261-354), Mage quarter (:359, :382-400);
  - `rpg_ability_learned` (:791), `rpg_ability_tile` (:1067), `rpg_spend` (:1645);
  - `rpg_load` version branches (:2146-2216): the v3 → v4 bar remap.
- `src/abilities.asm`: `ab_effects` (:157), the `abilities_use` plan/pay/cooldown/fail stages (:221-318), `ab_blink_plan` (:780), `ab_sweep` (:477), `ab_crit` (:470). These are the retirement work and the helpers to export.
- `src/input.asm`: `KEY`/`BIND`/`EDGE` macros (:203-233), the movement `%rep` (:453), the captured copy block (:469-489).
- `src/game.asm`: ability dispatch (:1828-1868), `try_potion` and its call sites (:1302, :2277, :2395), `abilities_reset` (:169), `abilities_step` (~:2831).

## Verification

Run from the repo root.

1. After each step: `make -j && make test`. The expected tail is `all N tests passed`, with no NASM warnings. The baseline is 319. Step 2 removes 2 tests and adds 1. Steps 3–9 add `test_rune_unlocks` and the 9 spell/net tests. Every test name listed above appears in the output.
2. Negative controls, each done once in a scratch edit and then reverted:
   - change `applies[Laser]` to include Seek → `test_spell_resolve` fails;
   - skip the hitmask OR in `spells_proj_hit` → `test_spell_pierce_chain` fails (the same zombie is hit repeatedly);
   - drop the v3 remap → `test_rpg_v3_bar_remap` fails.
3. Old save compatibility:
   - `git stash` is not needed: before Step 1, copy `world.acw` to `/tmp/acv3.acw`;
   - after Step 9, launch `./build/assemblycraft --data-dir /tmp/acv3-data --play <that world>` (copy the world dir there first);
   - expect it to load with the Warrior/Archer/Rogue bar entries intact, Mage ability entries emptied, and no refund banner unless the save was invalid.
4. Live check, per the `omabox` / `assemblycraft-gdb-live-driver` skills:
   - `omabox up --audio`, install the build into the box, and start a creative world;
   - unlock every rune by giving all 16 Rune items through the debug menu (F12 ×3) and right-clicking each. If the debug item list does not reach the new ids, write `0xFFFF` at `WORLDHDR` byte 16580 (`.rpgx` 16400 + `.runes` 180) with a throwaway header patcher before launch;
   - expect the 16-cell strip at the bottom right with key labels;
   - holding `U`+`J`+`M` previews `Laser + Frost + Pierce  36 mana`;
   - Right Shift fires a pale-blue beam that chills a zombie;
   - tapping `Y`, `H`, `;` and then Right Shift within 0.75 s fires an orange ball that burns and poisons;
   - `O` + Right Shift teleports;
   - capture `omabox -b default shot --window assemblycraft --fit 960` for each.
   - Rebinding, checked with screenshots:
     - Options → Controls → "Rune keys" shows 16 labelled rows.
     - Rebind "Fire rune" to `3`, then return to play. The HUD strip's Fire label reads `3`.
     - Tapping `3` then Right Shift casts a fire ball, and the hotbar selection does **not** move to slot 3.
     - Rebind "Cast spell" to `F4`; F4 now casts.
     - Quit and relaunch: both bindings persist.
     - "Reset keys" restores `H` and Right Shift.
5. Multiplayer: host plus guest in the box, per the `assemblycraft-multiplayer-omabox-verify` skill. A guest's Laser draws on the host and the host's zombie takes the damage. A guest's Ball shows as a coloured ghost on the host.
6. Windows: `make windows` (needs the `ac-mingw` image; build it with `make windows-image` if missing), then run the selftest under wine as before. If docker is unavailable, report that it was not run.

## Assumptions & contingencies

- Balance numbers (costs, cooldowns, damage, the 2 % mob rune drop, chest weight 1 per rune, Haste ×1.3) are first-pass values in data tables. Retuning them means editing data only.
- **One global spell cooldown**, the sum of the rune cooldowns, rather than per-rune cooldowns, so the HUD has one sweep.
- Bindings accept keyboard key codes only (32..348, the existing capture rule). A 12-button mouse works through the keys it sends. Binding raw mouse buttons 4+ is not supported.
- Laser and Ball hit any mob in their path, including passive animals and folk, the same as arrows and staff bolts do today.
- If `mob_drops` turns out to have no common spawn helper, spawn the rune with the same call its gear roll uses.
- If any existing test asserts that tiles 142/143/144/218 are opaque, delete that assertion together with the art.

## As built (differences from the plan above)

- Settings names of the rune keys are `key_r_<rune>` (`key_r_ball` … `key_r_feather`), not `key_rune_<rune>`: a settings record's name is 15 characters at most and `key_rune_feather` is 16. The Cast key is `key_cast`.
- The rune strip of the HUD wraps in rows (as many cells to a row as fit right of the hotbar, at least 4, rows 24 units apart) instead of one row of up to 16 cells, which would not fit beside the hotbar at the default GUI width. The cooldown sweeps down every cell instead of a bar under the strip. `spells_preview` also returns the mana cost (edx) and needs a 192 byte buffer (the worst case is about 160 characters).
- Steps 2 and 3 landed in one commit (the Mage's three ability nodes became rune nodes in the same change as the ability renumbering), and so did Steps 6 and 7 (the Ball needs the projectile hooks to fly).
- `rpg_rune_banner(name)` (rpg.asm) writes "Rune learned: <name>" for both a web rune node and a Rune item, so `spells_rune_name` does not exist; `spell_fx` (element -> particle kind) is exported by spells.asm and used by arrows.asm.
- `RUNE_FIRST` is defined beside the item ids in `common.inc`; `SPELLMSG` lives in `netmisc.asm` with `PROJMSG` and `FXMSG`.
- A guest or a host drops a `PROJ_SPELL` projectile whose element is above poison, and `MT_SPELL` beams are limited to 10 a second per sender.

- Phase is not inert next to a Ball, a Laser or a Nova (the plan said it was): it rides them and teleports the caster to where the spell ended: the Ball's last impact (a mob, with Pierce the last one it goes through, the face of a wall, the floor; a ball that only runs out of time warps nothing; you land in free space up to 4 blocks back along its flight), the beam followed for Phase's usual 8 blocks (not the beam's 12 or 24), or the Nova's centre (you arrive first, then it bursts). Dash rides every other delivery (Ball, Laser, Nova, Phase): after the rest, a 18 b/s horizontal shove (20 untouchable steps) along the Ball's flight at its impact, or along the look for the others; a Ball that only runs out of time shoves nothing. This replaces the plan's "two movements: the first wins" rule. Alone, Dash is still the shove plus the blast where it began. Landing in mid-air after a Phase ball and falling from there is intended.
- Phase's landing lifts a blocked candidate onto the floor or a one block ledge, up to the eye height (1.5 blocks), so looking down at the ground works and the landing is never past where the ray meets the floor.
- There is no spell cooldown (removed at the author's request: the player's own speed is the limit). `spells_cd`, `SPELLPLAN.cd`, `RUNEINFO.cd`, the HUD sweep and the COOLDOWN_RED scaling of spells are gone; the cooldown column of the rune table above is obsolete.
