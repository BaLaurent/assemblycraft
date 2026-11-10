# AssemblyCraft: plane (craftable, third-person, multi-crew, unlimited Gatlings)

Status: approved 2026-11-10. Delivered in two phases (solo plane, then multiplayer crew). `make` stays warning-free and `make test` green after every step.

## Context

AssemblyCraft is x86-64 NASM (`src/*.asm`). The plane is a new vehicle beside the boat: accelerate to take off, pilot it in third person, up to 4 crew (1 pilot, 3 Gatling gunners with unlimited ammo), craftable from expensive components. The new module is `src/planes.asm`, modelled on `src/boats.asm`; boats code is not modified except where a shared call site needs a sibling branch.

## Decisions (fixed)

- Crew = other players in multiplayer only; solo = pilot alone. No fuel, bombs, seat switching, seaplane, NPC crew.
- Takeoff from any clear ground. Arcade flight. Soft landing OK; harsh landing or water = crash (plane destroyed, every occupant takes damage).
- 4 seats: 0 pilot, 1 left gunner, 2 right gunner, 3 tail gunner. The first to board takes the pilot seat, then the first free gunner seat.
- Gatling: about 10 shots/s, no ammo, no reload, cone-limited aim; hits mobs always and players only when `net_pvp`; never breaks blocks.
- View key: new rebindable binding "Vehicle view", default V, read only while seated; Ability 3 (V) is read only when not seated. Pilot defaults to third person, V = cockpit. Gunner defaults to first person from the turret, V = free third-person orbit (barrel follows the reticle inside the cone).
- `MAX_PLANES` = 4.

## Items and recipes

Six new byte item ids after the current last item (`NUM_ITEMS` 231; ids 231..236, 255 reserved): `PLANE_ENGINE`, `PLANE_WING`, `PLANE_FUSELAGE`, `PLANE_PROP`, `PLANE_TAIL`, `PLANE`. `NUM_ITEMS` becomes 237. Max stack: 1 for `PLANE`, 16 for components. Names: "Engine", "Wing", "Fuselage", "Propeller", "Tail", "Airplane".

Costs (grids chosen at implementation, totals fixed):

- Wing (count 1, two needed): 5 iron ingots + 4 wool.
- Fuselage: 6 iron ingots + 3 glass.
- Propeller: 3 iron ingots + 2 sticks.
- Tail: 3 iron ingots + 3 wool + 1 stick.
- Engine: iron block centre, 4 iron ingots on the sides, gunpowder and coal at the top corners.
- Plane: engine + 2 wings + fuselage + propeller + tail in a 3x3 grid.

About 40 iron ingots in total.

## Flight model

- `PLANEENT`: body (y = bottom, yaw = heading), pitch, roll, speed, throttle, used, `occ[4]` (peer slot + 1 per seat, 0 = free), vy.
- Constants: `PL_VMAX` 24.0 b/s (set from the streaming measurement), `PL_TAKEOFF` 12.0, `PL_STALL` 9.0, `PL_ACC` 6.0 b/s^2, `PL_DRAG`, `PL_TURN_RATE` 60 deg/s, `PL_PITCH_MAX` +-35 deg, `PL_CEILING` 240.0, crash limits `PL_CRASH_VY` -9.0 b/s, `PL_CRASH_PITCH` -25 deg, `PL_CRASH_SPEED` 14.0, `PL_CRASH_DMG` 12 HP.
- Ground: nose level, rolls with throttle, collision box 3.0 x 1.2 x 3.0. Airborne when speed >= `PL_TAKEOFF`, pitch > 0 and mouse pitch up. Below `PL_STALL` in the air: lift 0, nose drops 40 deg/s, `vy -= 20 dt`. Otherwise lift cancels gravity proportionally to pitch.
- Landing: any of vy, pitch, speed beyond the crash limits, or water below, destroys the plane and damages every occupant (the fall-damage path). It drops nothing.
- Leave: sneak key only when grounded and speed < 1.0; the player is placed 0.6 above the plane.
- Pilotless planes (leave, disconnect, load): throttle 0, glide by the same rules, crash rules apply.
- Save: `PLANESAVE{x,y,z,yaw}` x 4 in the free `WORLDHDR.pad_a` bytes; the magic `ACRAFT06` is kept (old saves read count 0).

## Streaming

Columns that are not ready count as air for the plane; loaded blocks collide normally. Governor: each step sample `PL_LOOK_COLS` columns along the heading (`world_column_ready`); if any is not ready, the effective max speed falls by 4 b/s^2 toward `PL_STALL + 3.0` (never below), otherwise it recovers by 2 b/s^2 up to `PL_VMAX`. HUD hint "Terrain loading" while reduced. If the column under the plane is not ready the plane freezes (as boats do). `PL_VMAX` and `PL_LOOK_COLS` come from a measurement at the default `render_dist` 8; if fewer than 2 columns are ready ahead even at 16 b/s, `PL_VMAX` is 16.0 and the governor stays.

## Camera and view

Third-person: a scratch BODY placed 7.0 behind the plane, +2.5 up, clamped by `raycast` so it never enters a solid block, is passed to `render_world`; interaction raycasts keep the real eye. The hand is not drawn in third person and the pilot is drawn with the remote-avatar path.

## Multiplayer

- Messages: `MT_PLANE_PLACE`, `MT_PLANE_BOARD {slot, seat_req}`, `MT_PLANE_BOARD_OK {slot, seat, ok}`, `MT_PLANE_LEAVE`, `MT_PLANE_POSE`, `MT_PLANE_BREAK`, modelled one-to-one on the boat messages. The host assigns the seat; a double board of one seat is rejected.
- The pilot's machine steps the plane and sends `PLANE_POSE` every 3 steps (20 Hz); the host validates like `boat_pose_apply`.
- Snapshots carry `PLANEREC` (slot, occupants[4], position, yaw, pitch, roll, speed) after the boat records; guests extrapolate along the heading.
- `PSTATE` carries the seat in the spare pad byte; gunners and pilot are drawn at their seats.
- A peer leaving or the host closing frees the occupancy; if the pilot leaves in flight the host simulates the now pilotless plane.
- The host keeps columns loaded `MP_SIM_R + 2` around a plane's pilot.

## Gatling

In `sim_step` with `plane_seat >= 1`: the mouse aims within +-70 deg yaw / +-40 deg pitch around the seat's side vector (1 = left, 2 = right, 3 = rear). The eye is the seat's turret position. Held fire spawns, every 6 steps, `arrows_spawn` with the muzzle at `eye + dir*0.3`, speed 110 b/s, spread 1.5 deg, damage `PL_GATLING_DMG` 3, no pickup, lifetime capped to 1.5 s, sound `SND_PISTOL`. Peers' ghost twins come from `arrows_spawn`; there is no fire net message.

## As built

### Phase 1 (solo plane)

- **Streaming measurement** (omabox, gdb-driven, a plane at 24 b/s level at y 130 over terrain the player had never visited, default `render_dist` 8, one sample per second for 18 s, east and south): every one of the eight columns sampled 16..128 blocks ahead was loaded at every sample. `PL_VMAX` stays 24.0 and `PL_LOOK_COLS` 4. The governor only works when the loaded area is smaller (a low render distance): it is covered by `test_planes_governor`.
- **Controls.** The pilot steers with the view rather than with mouse deltas passed to `planes_step`: the plane's heading and pitch follow the player's yaw and pitch (the player's pitch is held within +-35 while flying), A and D turn the view at 60 degrees per second, W and S move the throttle. `planes_step` therefore takes only the `INPUT*`.
- **Unloaded columns.** Rather than treating them as air (which needed a change to `cell_boxes`), a plane whose next step would put a corner of a box 2.0 around its centre over a column that is not loaded stands still until it is. `shapes.asm` is unchanged.
- **Placement** uses the block ray the game already casts (`planes_place(RAYHIT*)`, top faces only) instead of a second ray walk. In multiplayer `planes_place` refuses with a banner until phase 2.
- **Model.** An open cockpit (no canopy); in third person the pilot's torso and head are drawn from the folk model, the hand is not, and the chase camera looks 14 degrees below the plane's pitch so the plane sits in the middle of the view. `coord_ok` and `meshable` are exported from `boats.asm` and shared.
- **Recipes** (3 x 3 shaped, about 35 iron ingots in all): Engine `gunpowder, I, _ / I, iron block, I / _, I, coal`; Wing `I I I / I W W / I W W`; Fuselage `I I I / G G G / I I I`; Propeller `_ I _ / I stick I / _ stick _`; Tail `W W W / I stick I / _ I _`; Airplane `_ propeller _ / wing engine wing / _ fuselage tail` (I iron ingot, W wool, G glass).
- **View key.** `BIND_VEHICLE_VIEW` (`key_vehicleview` in the settings file, 16 characters at most), default V, edge `FRAMEINPUT.vehicle_view`; `game_frame` flips `plane_view` on it only while a plane is flown and ignores Ability 3's key then.
- **Verified.** `make test`: 299 passed, 0 failed (`test_planes`: placement rules, targeting, breaking with the item drop, takeoff, stall, soft landing, four crash causes, governor, save/load, leaving, chase camera; the crash-pitch limit and the governor floor were mutated to confirm the tests catch them).
- **Live check (omabox, game under gdb; the item was written into the hotbar with gdb, not crafted or given through the F12 menu).** On an 80-block runway carved with gdb `world_set`: right click on a block top placed the plane (item consumed), a right click boarded it, it rolled, took off, flew 18 s at 24 b/s, banked with D, landed softly at 13 b/s, a nose-down touchdown destroyed it (banner, 12 damage, the death screen reads "fell from a high place"), V flipped to the cockpit and back, sneaking left it, a left click broke it. No 60 s flight was made, and the origin rebase during a flight was not observed live (`planes_shift` is covered by the selftest).
- **Known limitation: takeoff needs a long, clear, flat strip.** On natural terrain the plane stopped dead within 4-13 blocks on every heading around spawn (seed 4242, forest; terrain steps of one block and trees; a 2/16 snow layer does not block it). Five takeoffs from the longest natural clear strips found within 140 blocks of a spawn (27 and 44 blocks) ended in trees just past the strip or in a wall at more than 14 b/s. With `PL_TAKEOFF` 12 and the nose rising 45 degrees per second the plane climbs about 4 b/s at first, about 3 blocks in the 12 blocks after liftoff, which does not clear trees. The flight model was left as designed; retuning (a lower takeoff speed, a stronger first climb, a grounded step-up over one-block rises) is filed as a GitHub issue.
