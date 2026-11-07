# AssemblyCraft 0.5: fire, explosion effects, thrown TNT, better firearms

## User feedback (2026-11-07) and decisions

1. **Gun animations are poor.** Firearms get real box-built 3D models, held pointing forward. They have:
   - a smooth recoil and recovery, plus a muzzle flash;
   - a reload dip-and-roll;
   - no swing animation.
2. **Holding a firearm:** RMB aims down the sights and LMB fires.
   - **Aiming:** the gun moves to the centre of the view, the FOV narrows, and sensitivity and spread drop.
   - **Fire button:** LMB never breaks blocks or punches while a firearm is held.
   - **No block use:** RMB never opens a block while a firearm is held.
3. **Flint and steel starts fire**, with Minecraft-style spread (the user's choice):
   - fire spreads to and consumes flammable blocks;
   - it ignites TNT, hurts what stands in it, and burns out.
4. **Explosions get more spectacular** (the user's choice): an orange fireball plus rising smoke, flying block debris, camera shake, and a screen flash near the blast.
5. **Primed TNT is a physics body:** it falls, and explosions throw it, chain-reacting TNT included.

## Conventions

Same as the 0.3/0.4 specs:
- SysV ABI, SSE floats, per-file extern/global.
- Tests return 0 and are registered in `selftest.asm`.
- Workers build in a scratch copy and copy back only the files they own.

## Contracts

### `common.inc`

- **Blocks:** `FIRE 22`, `NUM_BLOCKS 23`.
- **Tiles:** `TILE_FIRE0 57` and `TILE_FIRE1 58`, two animation frames with transparent pixels (alpha 0) around the flames.
- **Cause:** `CAUSE_FIRE 8`, shown on the death screen as "You burned to death".
- **Fire table:**
  - `MAX_FIRES 1024`.
  - `struc FIREENT`: `.x .y .z` (dd int), `.age` (dd steps), `.tick` (dd steps to the next spread or burn roll); 20 bytes. `.x = -1` marks a free slot.
- **Particles:**
  - `MAX_PARTICLES 768`.
  - `struc PARTICLE`: `.x .y .z .vx .vy .vz` (float), `.age`, `.life` (dd steps), `.size` (float), `.kind` (dd: 0 free, `FX_FIRE 1`, `FX_SMOKE 2`, `FX_DEBRIS 3`), `.tile` (dd); 44 bytes.
- **`struc PRIMED`:** becomes `.body: resb BODY_size` followed by `.fuse: resd 1`.
  - `body.y` is the bottom of the 0.98-wide cube, and the explosion centre is `(x, y + 0.49, z)`.

### Blocks (`blockdefs.asm`, `itemdefs.asm`)

- **FIRE (22):**
  - **block data:** flags 0 (not solid, not opaque), tiles 0,0,0, hardness 0.0, tool 0, harvest level 0, drop 0, dig sound `SND_DIG_SOFT`, step sound `SND_STEP_SOFT`;
  - **item data:** name "Fire", `item_max_stack 0`, icon 0.
- **`block_flammable db` (new table), the chance per fire tick in % of burning or catching:** PLANKS 20, LOG 5, LEAVES 30, CRAFTING_TABLE 20, CHEST 20, TNT 100. All others are 0.
- **Mesher:** it skips FIRE (fire.asm draws it).
- **Raycast:** it passes through FIRE, so fire never stops arrows, bullets or targeting.

### `fire.asm` (new, worker A)

|Symbol|Contract|
|---|---|
|`fires` (table), `fire_clear()`|every slot free|
|`fire_place(edi x, esi y, edx z) → eax 1/0`|The cell must be in the world, AIR, and have a free slot. It sets the block to FIRE and records a slot with `age 0` and `tick = 20 + rng%20`|
|`fire_step()`|once per fixed step, see the rules below|
|`fire_render()`|world pass (atlas bound, alpha test on). For each fire, two crossed vertical slabs (0.04 thick, 0..1 tall) use `TILE_FIRE0`/`TILE_FIRE1`, alternating by `(game_time / 6 + index) & 1`, at full brightness (colour 1, shades 1)|
|`fire_rebuild()`|after a world load: clears the table and records every FIRE block in the world (a full scan). FIRE blocks beyond `MAX_FIRES` become AIR|

**`fire_step`, for each live slot:**

1. If the block at the slot is no longer FIRE, free the slot.
2. `age++`.
3. Apply damage:
   - **The player:** while the player's box (0.6 × 1.8) overlaps the cell, in survival, call `survival_damage(1, CAUSE_FIRE)` (its invulnerability throttles it).
   - **Mobs:** every mob whose box overlaps the cell takes `mob_hurt(i, 1, 0, 0)`.
4. `tick−−`. At 0, roll the fire tick:
   1. Set `tick = 20 + rng%20`.
   2. **Burn the neighbours:** for each of the 6 neighbours with `block_flammable > 0`, when `rng%100 < flammable`:
      - **TNT:** `tnt_prime(cell, 80)`.
      - **Anything else:** call `cont_block_removed(cell)` and set AIR. Then, if `rng%2 == 0`, call `fire_place(cell)`.
   3. **Spread:** pick one random cell in x±1, y−1..+2, z±1. If it is AIR and one of its 6 neighbours is flammable, call `fire_place` there.
   4. **Burn out**, when `fuel` = any flammable neighbour:
      - no fuel and `age > 40 + rng%40`;
      - fuel and `age > 400 + rng%400`.

      Either way the block becomes AIR and the slot is freed.

### `fx.asm` (new, worker B)

|Symbol|Contract|
|---|---|
|`fx_clear()`|no particles, no shake, no flash|
|`fx_explosion(xmm0..2 centre, xmm3 radius)`|see below|
|`fx_debris(edi x, esi y, edx z, ecx block, xmm0..2 blast centre)`|one debris cube per call, sized 0.15–0.25, with `tile = block_tiles[3*block+1]` (side tile). It flies away from the centre at 4–9 b/s and up 3–7 b/s. Life is 40–80 steps. The caller decides how many blocks get debris|
|`fx_step()`|once per fixed step: moves particles, decays the shake and the flash|
|`fx_render()`|world pass: particles as `render_box` cubes, see below|
|`fx_shake_yaw`, `fx_shake_pitch` (float degrees)|a fresh random offset in ±1.5·shake each step, for the camera|
|`fx_flash` (float 0..1)|full-screen flash strength for the HUD|

**`fx_explosion`:**

- **Fireball:** `18·r` FIRE particles at the centre with random direction × (3..8)·r/3 b/s. Size 0.45–0.9, life 20–38 steps.
- **Smoke:** `3·r` SMOKE particles within ±r/2 of the centre. They rise at 1–2.5 b/s with ±0.7 b/s horizontal drift. Size 0.25–0.5, life 110–200 steps.
- **Shake and flash:** d = distance to `player_eye`.
  - `shake += max(0, 1.5·(1 − d/(6r)))`, capped at 2.5;
  - `flash = max(flash, 0.8·(1 − d/(3r)))`.

**Per particle in `fx_step`:**

- **FIRE:** velocity × 0.9, vy += 0.03, size × 0.975.
- **SMOKE:** velocity × 0.98, size + 0.006, then × 0.9 per step over its last 25 steps.
- **DEBRIS:**
  - vy −= 0.4 (gravity), then move.
  - When the new cell is solid, restore the old position, then set `vy = −vy·0.35` and multiply vx, vz by 0.6.
- **All kinds:**
  - `age++`; at `age ≥ life` the particle is freed.
  - The shake decays × 0.88 per step, to 0 below 0.02. The flash decays −0.06 per step.

When the table is full, new particles are dropped.

**`fx_render`:**

- **FIRE:** untextured, colour from yellow (1, 0.95, 0.4) to red (0.8, 0.2, 0.05) by age/life.
- **SMOKE:** untextured grey, 0.55 → 0.25 by age/life.
- **DEBRIS:** textured with its tile and lit by `sky_brightness`.
- Fire and smoke ignore the night darkening, because texture unit 0 is disabled for them. Texture state is restored afterwards.

### `explode.asm` (integrator)

- **`tnt_prime`:**
  - `body_init(&primed.body, 0.49, 0.98, 0)`;
  - position `(x+0.5, y, z+0.5)`;
  - a small hop: `vy = 2`, `kbx/kbz = ((rng%201)−100)/100`.
- **`tnt_step`:** each live entry runs `body_step(&body, zero INPUT)`. While airborne, the push (`kbx/kbz`) is restored after `body_step`, so there is no air drag; on the ground `body_step`'s decay acts as friction, and a wall hit zeroes it. Then the fuse ticks down. At 0 it explodes at the body's centre.
- **`explode_at`:**
  - **Effects:** calls `fx_explosion(c, r)`, and `fx_debris` for every 2nd destroyed block.
  - **Pushing primed TNT:** after the mobs, every live primed TNT within 2r of the centre (body centre) is pushed:
    - `f = 1 − d/2r`, `u = unit(centre_tnt − c)` (straight up when d < 0.01);
    - `kbx = u.x·14f`, `kbz = u.z·14f`, `vy = u.y·14f + 5f`.
    - TNT primed by this same blast is pushed too.
- **`tnt_render`:** translates to the body centre.

### Firearms (integrator; `guns.asm`, `hand.asm`, `game.asm`, `render.asm`)

- **`gun_fire(rdi eye, rsi dir, xmm0 spread_scale)`:** the spread is multiplied by `spread_scale`. The game passes `1 − 0.75·game_aim`. The `hand_swing` call is removed.
- **`game_aim` (float 0..1, `game.asm`):**
  - The target is 1 while a firearm is held, RMB is held, no screen is open and the cursor is captured; otherwise 0.
  - `aim += (target − aim)·min(1, 12·dt)` every frame.
  - The world FOV is `fov·(1 − 0.3·aim)`, and the look sensitivity is scaled by `1 − 0.4·aim`.
- **With a firearm held:**
  - LMB `pressed` (or `held` for the automatic) → `gun_fire`. It never breaks or attacks.
  - RMB never uses or opens blocks and never places.
- **`hand.asm`.** When a firearm is held, it is drawn by `gun_model_draw(id, light)`: boxes tinted on the near-white tile `TILE_CHICKEN_BODY`.
  - **Pose:** hip `(0.30, −0.30, −0.55)`, aimed `(0.0, −0.105, −0.5)`, lerped by `game_aim`.
  - **Recoil:** `z += 0.09·kick`, `rotX(+10·kick)`.
  - **Reload:** with `p = 1 − reload/total` and `s = sin(180p)`: `y −= 0.12·s`, `rotZ(25·s)`, `rotX(−20·s)`.
  - **Muzzle flash:** a bright untextured yellow box at the muzzle while `kick > 0.6`.
  - **No swing, little bob:** no swing is applied, and the bob is a quarter of the normal amount.
- **Models** (z towards the target is −Z; colours: metal (0.22,0.22,0.25), dark (0.12,0.12,0.13), wood (0.55,0.33,0.16), brass (0.9,0.7,0.25), green (0.30,0.45,0.22), red (0.75,0.12,0.1)):
  - **Pistol:** slide metal (−0.035,0.0,−0.28)…(0.035,0.07,0.02); grip dark (−0.03,−0.16,−0.04)…(0.03,0.0,0.04); muzzle z −0.29.
  - **Musket:**
    - barrel metal (−0.02,0.02,−1.05)…(0.02,0.06,−0.25);
    - stock wood (−0.045,−0.05,−0.75)…(0.045,0.04,0.2);
    - butt wood (−0.05,−0.16,0.05)…(0.05,0.02,0.35);
    - muzzle z −1.06.
  - **Shotgun:**
    - two barrels metal (−0.045,0.02,−0.8)…(0,0.065,−0.1) and (0,0.02,−0.8)…(0.045,0.065,−0.1);
    - pump wood (−0.04,−0.04,−0.6)…(0.04,0.02,−0.35);
    - receiver dark (−0.045,−0.04,−0.12)…(0.045,0.06,0.12);
    - stock wood (−0.04,−0.13,0.1)…(0.04,0.03,0.45);
    - muzzle z −0.81.
  - **Kalashnikov:**
    - barrel dark (−0.015,0.03,−0.7)…(0.015,0.06,−0.3);
    - handguard wood (−0.04,−0.01,−0.48)…(0.04,0.06,−0.25);
    - receiver dark (−0.045,−0.02,−0.25)…(0.045,0.07,0.15);
    - magazine brass-brown (−0.03,−0.2,−0.2)…(0.03,−0.02,−0.1) plus (−0.03,−0.28,−0.17)…(0.03,−0.19,−0.06);
    - grip dark (−0.03,−0.14,0.0)…(0.03,−0.02,0.06);
    - stock wood (−0.035,−0.08,0.15)…(0.035,0.04,0.45);
    - muzzle z −0.71.
  - **Rocket launcher:**
    - tube green (−0.065,−0.02,−0.55)…(0.065,0.11,0.2);
    - grip dark (−0.03,−0.18,−0.05)…(0.03,−0.02,0.03);
    - when loaded (dmg > 0), a warhead red (−0.05,0.0,−0.66)…(0.05,0.09,−0.55);
    - muzzle z −0.56.
- **Flint and steel (`game.asm`):** RMB on TNT primes it, as now. RMB on any other block calls `fire_place(target.px, py, pz)`. On success: `audio_play(SND_FUSE, 0.5)`, a hand swing, and in survival `inv_damage_held(1)`.
- **Clears:**
  - `game_new`, `game_load` and `load_panorama` call `fire_clear` and `fx_clear`;
  - `game_load` then calls `fire_rebuild`;
  - `sim_step` runs `fire_step` and then `fx_step` after `gun_step`.
- **`render.asm`:**
  - after `tnt_render`: `fire_render`, then `fx_render`;
  - camera: pitch += `fx_shake_pitch`, yaw += `fx_shake_yaw`;
  - FOV as above.
- **`hud.asm`:** while `fx_flash > 0`, a full-screen rectangle RGBA(255, 210, 150, 200·flash) is drawn before the crosshair.
- **`menus.asm`:** death cause 8 → "You burned to death".

## Tests

- **fire (worker A):**
  - **`[fire_spreads_and_burns_wood]`:**
    1. Seed 1; a 5×5 PLANKS floor at y=10; fire placed at (2,11,2).
    2. After 1200 steps, at least 10 of the 25 planks are gone.
    3. No FIRE is left at x or z ≥ 8, and the table is empty.
  - **`[fire_ignites_tnt]`:** TNT at (5,11,5) with fire at (6,11,5); within 400 steps a primed TNT exists.
  - **`[fire_dies_on_stone]`:** fire on a stone floor; within 100 steps it is gone and it has spread nowhere.
  - **`[fire_hurts_player]`:** survival, the player standing in a fire cell; health < 20 after 40 steps.
- **fx (worker B):**
  - **`[fx_explosion_spawns_and_expires]`:**
    1. `fx_explosion(r=3)`: more than 30 live particles.
    2. With the player 2 blocks away: shake > 0 and flash > 0.
    3. After 200 `fx_step`: 0 particles, shake 0, flash 0.
  - **`[fx_debris_falls_and_bounces]`:** debris over a stone floor ends resting above the floor (y ≥ floor top − 0.01) and never inside it.
- **integrator:**
  - **`[tnt_thrown_by_blast]`:** primed TNT on a floor 2.5 blocks from `explode_at(r=4)` is more than 4 blocks from the blast after 30 `tnt_step` (its fuse is set to 200 so it does not blow).
  - **`[tnt_falls]`:** primed TNT 3 blocks above a floor rests on it after 60 steps.
  - **`[aimed_shotgun_has_no_spread]`:** a shotgun fired with `spread_scale 0` sends all six pellets with vx = vy = 0.
  - **existing `gun_*` tests:** they pass `spread_scale 1.0`.
- **Total:** 60 + 9 = 69.

## Live verification (omabox, US layout, data dir copy)

1. **Guns:** a shot of each gun at the hip and while aiming. Recoil and muzzle flash right after LMB. Reload pose mid-reload. LMB with a gun does not break the targeted block.
2. **Fire:** flint and steel on a planks house → spreads and consumes it. Fire next to TNT ignites it. Standing in fire hurts, and the death message reads "burned".
3. **Explosions:** a rocket and a TNT, each with frames at 0.1 s, 0.4 s and 1.5 s: fireball, debris, smoke and flash.
4. **Chain reaction:** a TNT pile is thrown apart: primed blocks fly before exploding.
