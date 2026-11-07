# AssemblyCraft 0.4: firearms

## Goal

Add five craftable firearms. Each one fires its own craftable ammunition from a magazine, and the R key reloads it:

- a pistol;
- a musket;
- a shotgun;
- a Kalashnikov;
- a rocket launcher.

Bullets hurt mobs and stop on blocks. Rockets blow a crater, exactly like TNT, through `explode_at`.

## Decisions (agreed with the user)

- **Ammunition:** each weapon has its own ammo item, crafted with iron, gunpowder and so on.
- **Magazines:** reloading uses a rebindable Reload key, R by default. The HUD shows the rounds loaded.
- **Rockets:** a rocket destroys blocks like TNT: radius 3, ignites TNT, 30% block drops, and hurts the player too.
- **Projectiles:** all weapons extend the existing arrow system, `arrows.asm`, with a projectile kind. There is no separate hitscan path.

## Conventions

Same as the 0.3 spec (`2026-11-07-assemblycraft-content-design.md`, section Conventions):

- **Code:** SysV ABI, SSE-only floats, explicit sections, per-file extern/global.
- **Tests:** tests return 0 on success and are registered in `selftest.asm`.
- **Live checks:** run in an omabox box (`omabox up` from `$HOME`).

## Contracts

### `common.inc`

- **Items:**
  - Weapons: `PISTOL 82`, `MUSKET 83`, `SHOTGUN 84`, `KALASHNIKOV 85`, `ROCKET_LAUNCHER 86`.
  - Ammo: `PISTOL_ROUND 87`, `MUSKET_BALL 88`, `SHOTGUN_SHELL 89`, `RIFLE_ROUND 90`, `ROCKET 91`.
  - `NUM_ITEMS 92`. Icon tiles are `TILE_ITEM0 + id − 43`, i.e. 119–128.
- **Projectile kinds:** `PROJ_ARROW 0`, `PROJ_BULLET 1`, `PROJ_ROCKET 2`.
- **Sounds:** `SND_PISTOL 28`, `SND_MUSKET 29`, `SND_SHOTGUN 30`, `SND_RIFLE 31`, `SND_LAUNCHER 32`, `SND_RELOAD 33`, `SND_DRY_FIRE 34`. `NUM_SOUNDS 35`.
- **Bindings:** `BIND_RELOAD 9`, `NUM_BINDINGS 10`.
- **Structs:**
  - `FRAMEINPUT` gets `.reload: resd 1` appended (the edge of the Reload binding, reported in every state).
  - `ARROWENT` gets `.kind: resd 1` appended (52 bytes).
- **Capacity:** `MAX_ARROWS 96`.

### Gun state stored in the item

- A firearm stack has count 1. Its `ITEMSTACK.dmg` holds the rounds loaded, 0..magazine.
- Firearms have `item_durability = 0` and never wear, so no durability bar shows.
- `item_max_stack`: weapons 1, ammo 64.
- `item_attack` is 1 for all ten (a melee hit with a gun is a punch).
- The save format is unchanged (v3), and 0.3 worlds load as they are.

### Weapon table (`guns.asm`, index g = id − PISTOL)

|g|weapon|ammo|magazine|damage per pellet|pellets|spread|cooldown (steps)|reload (steps)|kind|speed (b/s)|sound|automatic|
|---|---|---|---|---|---|---|---|---|---|---|---|---|
|0|PISTOL|PISTOL_ROUND|8|5|1|0.02|15|60|BULLET|90|SND_PISTOL|0|
|1|MUSKET|MUSKET_BALL|1|14|1|0.0|10|150|BULLET|110|SND_MUSKET|0|
|2|SHOTGUN|SHOTGUN_SHELL|6|3|6|0.10|48|120|BULLET|70|SND_SHOTGUN|0|
|3|KALASHNIKOV|RIFLE_ROUND|30|6|1|0.03|6|120|BULLET|100|SND_RIFLE|1|
|4|ROCKET_LAUNCHER|ROCKET|1|0|1|0.0|10|180|ROCKET|25|SND_LAUNCHER|0|

**Spread:** each pellet's direction is `fwd + (u·s, v·s, w·s)` with u, v, w = `((rng % 2001) − 1000) / 1000`, then renormalized.

### `guns.asm` API (new module)

|Symbol|Contract|
|---|---|
|`gun_cooldown` (dd)|steps until the next shot is allowed|
|`gun_reload` (dd)|steps left in the current reload, 0 = none|
|`gun_reload_total` (dd)|length of the current reload, for the HUD bar|
|`gun_reload_slot` (dd)|hotbar slot being reloaded|
|`gun_kick` (float)|recoil 0..1, set to 1 on a shot, minus 0.1 per step down to 0|
|`gun_index`|`(edi id)→eax` g 0..4, or −1 if not a firearm|
|`gun_magazine`|`(edi id)→eax` magazine size, or 0|
|`gun_ammo`|`(edi id)→eax` ammo item id, or 0|
|`gun_reset`|`()` zeroes the five state globals; called from `game.asm` `reset_session`|
|`gun_reload_start`|`()→eax` 1 if a reload started. Needs: the held item is a firearm, no reload is running, loaded < magazine, and (creative, or `inv_count(ammo) > 0`). It sets `gun_reload = gun_reload_total = reload steps`, `gun_reload_slot = inv_sel`, and plays `audio_play(SND_RELOAD, 0.7)`|
|`gun_step`|`()` once per fixed step, see below|
|`gun_fire`|`(rdi eye[3], rsi dir[3])→eax` 1 if a shot left, see below|

**`gun_step`:**

1. `gun_cooldown` decreases by 1 down to 0; `gun_kick` decreases by 0.1 down to 0.
2. If `gun_reload > 0`:
   - If `inv_sel ≠ gun_reload_slot`, or the held item is no longer a firearm, the reload is cancelled: `gun_reload = 0`.
   - Otherwise `gun_reload` decreases by 1. When it reaches 0:
     1. `need = magazine − loaded`.
     2. In creative, `loaded = magazine`.
     3. In survival, `inv_remove_one(ammo)` is called up to `need` times, and `loaded` grows by the number of successful calls.
     4. `audio_play(SND_RELOAD, 0.9)`.

**`gun_fire`:**

1. If the held item is not a firearm, or `gun_reload > 0`, or `gun_cooldown > 0`, return 0.
2. If `loaded == 0`: `audio_play(SND_DRY_FIRE, 0.8)`, then `gun_reload_start()`, then `gun_cooldown = 10`, and return 0.
3. Otherwise:
   1. `loaded −= 1` and `gun_cooldown = cooldown`.
   2. For each pellet: `arrows_spawn(eye + dir·0.3, spread_dir·speed, owner 0, damage, pickup 0, kind)`.
   3. `audio_play(sound, 1.0)`, `gun_kick = 1.0`, `hand_swing()`.
   4. Return 1.

### `arrows.asm` changes

- `arrows_spawn(xmm0..xmm5, edi owner, esi damage, edx pickup, ecx kind)`. Every existing caller (the bow in `game.asm`, the skeleton in `mobs.asm`) passes `ecx = PROJ_ARROW`.
- **Per kind in `arrows_step`:**
  - **Gravity per step:** arrow 0.33333334, bullet 0.0, rocket 0.0.
  - **Flying age limit:** arrow 600, bullet 120, rocket 300.
  - **When a rocket reaches its age limit:** it explodes where it is.
  - **When a projectile hits a mob:**
    - arrow or bullet: `mob_hurt` as now, then removed;
    - rocket: `explode_at(hit point, 3.0)`, then removed.
  - **When a projectile hits a block:**
    - arrow: sticks, as now;
    - bullet: removed, with `audio_play_at(SND_ARROW_HIT, hit point, 0.4)`;
    - rocket: moves to `t − 0.05`, then `explode_at(position, 3.0)`, then removed.
- **When a rocket explodes:** `live` is set to 0 *before* `explode_at` is called.
- **Rendering per kind** (all boxes point to −Z like the arrow):
  - **Bullet:** a box from (−0.025,−0.025,−0.08) to (0.025,0.025,0.08), all tiles `TILE_GOLD_ORE`.
  - **Rocket:**
    - body (−0.07,−0.07,−0.25) to (0.07,0.07,0.2), tiles 0 (stone grey);
    - warhead (−0.08,−0.08,−0.38) to (0.08,0.08,−0.25), tiles `TILE_TNT_SIDE`;
    - fins (−0.15,−0.02,0.12) to (0.15,0.02,0.25), tiles 0.

### Recipes (`items.asm`, records `w, h, out, count, cells`; I = IRON_INGOT)

|Output|Shape|
|---|---|
|PISTOL ×1|2×2 `I I / 0 PLANKS`|
|MUSKET ×1|3×3 `0 0 I / 0 I FLINT_AND_STEEL / LOG 0 0`|
|SHOTGUN ×1|3×2 `I I I / 0 PLANKS PLANKS`|
|KALASHNIKOV ×1|3×3 `I I I / 0 DIAMOND I / 0 PLANKS I`|
|ROCKET_LAUNCHER ×1|3×3 `I I I / DIAMOND 0 DIAMOND / I I I`|
|PISTOL_ROUND ×8|1×2 `I / GUNPOWDER`|
|MUSKET_BALL ×4|2×1 `I GUNPOWDER`|
|SHOTGUN_SHELL ×4|1×3 `I / GUNPOWDER / FEATHER`|
|RIFLE_ROUND ×16|1×3 `I / GUNPOWDER / GUNPOWDER`|
|ROCKET ×1|1×3 `I / TNT / GUNPOWDER`|

**Item names:** "Pistol", "Musket", "Shotgun", "Kalashnikov", "Rocket Launcher", "Pistol Round", "Musket Ball", "Shotgun Shell", "Rifle Round", "Rocket".

### Integration

- **`game.asm`.**
  - `reset_session` calls `gun_reset`, and `sim_step` calls `gun_step` after `tnt_step`.
  - In `game_frame`, a new section 12 "firearm" runs after the bow section, before `.ret`. It applies when the held item is a firearm, `game_open_screen == 0` and `input_captured == 1`:
    1. A `frame_input.reload` edge → `gun_reload_start`.
    2. If (automatic and `rmb_held`) or `rmb_pressed` → `gun_fire(F_EYE, F_DIR)`.
  - The bow section's RMB handling is untouched (a firearm is not a bow).
  - A firearm has `item_food = 0` and an id ≥ `NUM_BLOCKS`, so the place path ignores it.
- **`input.asm`:** `BIND BIND_RELOAD` and `EDGE prev_reload` go to `frame_input.reload` in the "every state" group.
- **`settings.asm`:**
  - `SETTINGS_IMAGE` keys get `82` appended (R).
  - New entry `SETENT "key_reload", SETTINGS.keys + 4*BIND_RELOAD, 32, 348, 1`.
  - `NUM_SETENT 19`.
  - A file without the line keeps the default.
- **`options.asm`:**
  - New label `s_b_reload` "Reload", appended to `bind_labels`.
  - Row pitch = `min(24, (ui_h − 60) / NUM_BINDINGS)`.
- **`hud.asm`.** When the held item is a firearm:
  - The text `"<loaded>/<magazine>  [<inv_count(ammo)>]"` is drawn in white, 1×, at (x0 + 186, y0 + 7).
  - In creative, the count after the slash is followed by `"  [inf]"` instead.
  - While `gun_reload > 0`, a bar is drawn at the screen centre, (cx − 20, cy + 10):
    - background: 40 × 3, RGBA(0,0,0,140);
    - fill: `40·(total − reload)/total`, RGBA(255,255,255,220).
- **`hand.asm`:** when the held item is a firearm and `gun_kick > 0`, right after the swing rotation:
  - `glTranslatef(0, 0, 0.12·kick)`;
  - `glRotatef(−12·kick, 1, 0, 0)`.
- **Art (`texgen.asm`):** icons for tiles 119–128, drawn with `BMP` and 16×16 bitmaps:
  - pistol: grey with a dark grip;
  - musket: long brown stock with an iron barrel;
  - shotgun: double barrel with a brown pump;
  - Kalashnikov: black body with a curved magazine and a wood stock;
  - rocket launcher: green tube;
  - pistol round: small brass;
  - musket ball: grey sphere;
  - shotgun shell: red with a brass base;
  - rifle round: long brass;
  - rocket: grey body with a red warhead.
- **Sound (`sfx.asm`):** layers built with `LAYER`:
  - pistol: sharp noise crack;
  - musket: low boom with a long tail;
  - shotgun: wide noise boom;
  - rifle: short crack;
  - launcher: noise whoosh rising, plus a thump;
  - reload: two square clicks;
  - dry fire: one tiny click.

  Every peak must lie in [−18, −0.1] dB.

## Tests (new `src/test_guns.asm`, plus `test_items`/`test_settings` additions)

- **`[craft_firearms]`:** all ten recipes produce their output and count. A shotgun shape missing one planks crafts nothing.
- **`[gun_reload_fills_magazine]`:**
  1. Survival; slot 0 = {PISTOL,1,0}, slot 1 = {PISTOL_ROUND,5}.
  2. `gun_reload_start` → 1, then 60 × `gun_step` → loaded 5 and the ammo is gone.
  3. Slot 1 = {PISTOL_ROUND,20}; reload again → loaded 8 and 17 rounds left.
  4. With the magazine full, `gun_reload_start` → 0.
  5. In creative with no ammo: reload → loaded 8.
- **`[gun_fire_cooldown_and_dry]`:**
  1. Pistol loaded 2.
  2. `gun_fire` → 1, loaded 1, one live projectile of kind BULLET.
  3. An immediate `gun_fire` → 0.
  4. After 15 `gun_step`: `gun_fire` → 1, loaded 0.
  5. After 15 steps, with rounds in the inventory: `gun_fire` → 0 and `gun_reload > 0`.
- **`[shotgun_spawns_six_pellets]`:** shotgun loaded 1 → `gun_fire` → 6 live BULLET projectiles.
- **`[bullet_hits_mob_and_stops]`:**
  1. Fixture: STONE floor at y=10, x/z 0–31.
  2. A pig at (16.5,11,10.5); a bullet spawned at (16.5,11.5,16.5) with v (0,0,−90), damage 5. After 30 steps, pig health is 5.
  3. A wall at (16,11,4..6) STONE; a bullet aimed at it. After 30 steps the block is still STONE and the bullet is not live.
- **`[rocket_explodes_on_impact]`:**
  1. Stone cube x,y,z 2–14; a rocket spawned at (8.5,20,8.5), v (0,−25,0).
  2. Up to 120 steps.
  3. Check: (8,14,8) and (8,13,8) are AIR, and no projectile is live.
- **`[settings_reload_key_default]`:** a settings file without `key_reload` loads with `keys[BIND_RELOAD] == 82`. After `key_reload=75`, it loads 75.

Total after this work: 60 tests.

## Execution plan

1. **Contracts (inline).**
   - `common.inc`; the `itemdefs.asm` tables for ids 82–91; recipes; projectile `kind` in `arrows_spawn`, with every caller passing 0; `MAX_ARROWS 96`.
   - Settings, input and options for `BIND_RELOAD`.
   - Build, then `make test` (53 pass). Commit.
2. **In parallel:**
   - **Worker A (`texgen.asm` only):** the 10 icons. Proof: an atlas dump, byte-identical outside tiles 119–128.
   - **Worker B (`sfx.asm` only):** the 7 sounds, with a peak table.
3. **Inline:**
   - the projectile kinds in `arrows.asm`;
   - `guns.asm`;
   - the `game.asm`, `hud.asm` and `hand.asm` integration;
   - all tests.
   - Then `make test` (60 pass), and commit.
4. **Live box verification.**
   1. Patch a survival world with weapons and ammo; craft one weapon at a table.
   2. Fire each weapon at mobs and walls; reload with R; check the HUD counter and bar.
   3. Rocket crater; Kalashnikov full-auto.
   4. Rebind Reload in Controls.
   5. Sound capture of a shot.
