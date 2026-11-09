# AssemblyCraft 0.10.5: debug menu and the cheater mark

User request (2026-11-09): a debug menu to change the character's stats, add items, spawn enemies, "really a menu that lets me debug everything". It opens when F12 is pressed three times. Once it has been opened the save is labelled as cheated, so anyone who gets the save can see it was cheated.

Decisions (user, same day): the label shows in the world list and in the game (HUD and F3 screen); the menu has four tabs (Player, Items, Enemies, World); the game is paused while the menu is open; no mockup (the user judges in game).

## Behaviour

- **Trigger:** `F12` pressed three times with at most 1.0 s (60 steps) between presses opens the menu. Any other key or a longer gap resets the count. Works while playing (no other screen open); F12 x3 or Esc closes it. Not available on the title screen.
- **Cheater mark:** the first time the menu opens in a world, `WORLDHDR.cheater` (byte @605, inside the free `pad_a`; old saves read 0) is set to 1. It is never cleared by the game. It is saved with the world (the world is saved immediately on first open so the mark survives a crash).
- **Where it shows:** world list: a red `CHEATER` tag after the world's name; in game: a red `CHEATER` text under the title line of the F3 overlay and a small red `[C]` marker next to the level text in the HUD (always visible).
- **Pause:** while open the world does not step (like the pause menu); input goes to the menu; the mouse is released.

## Tabs

All controls are buttons/rows built with the existing `ui.asm` toolkit in the grimoire look (parchment page, tabs on top). Every action applies immediately.

1. **Player**
   - Level (set 1..50, `+1`, `-1`, `Max`), XP (`Level up` grants a level), skill points (`+1` / `+10`), attribute points (`+1` / `+10`), `Respec free` (refunds all skills, no coins).
   - Health / food / mana / stamina: `Full` restores all; `God mode` toggle (no damage), `Fly` toggle, mode toggle Creative/Survival.
   - Stats: a scrollable list of every stat (46) with the current computed value and `+`/`-` buttons that add a debug bonus (flat to the stat, kept in a `debug_bonus` table added after `rpg_recompute`, saved in the world so the bonus survives reload).
2. **Items**: search box (type to filter by name) over all items 1..`NUM_ITEMS-1`, list with icon and name, buttons `+1`, `+16`, `+64` (stack capped at the item's max), added to the first free/mergeable slot. For firearms a row of the four attachment toggles fits them directly.
3. **Enemies**: type list (every `MOB_*` hostile and passive), level (1..60, default player level), elite toggle, count (1, 5, 10), `Spawn` places them 4-8 blocks in front of the player on the ground; `Kill all` removes every mob; `Heal all`.
4. **World**: time of day (`Dawn`, `Noon`, `Dusk`, `Midnight`, `+1 h`), teleport (X Y Z fields + `Go`, plus `To spawn`, `To bed`), faction standing (`+100` / `-100` / `Max` per faction), `Reset cooldowns` (all ability cooldowns, bolt), `Clear drops`.

## Architecture

- New `src/debugmenu.asm`: owns the F12 detector state, the open flag, the tab/state, drawing and click handling, and the actions. Public entry points: `debug_press()` (called from the frame input path on an F12 edge; returns eax = 1 when the third press just opened the menu), `debug_open` (global flag), `debug_frame()` (draw + input while open), `debug_close()`, `debug_is_cheater()`, `debug_mark_cheater()` (sets the flag in the live header image).
- It calls existing APIs only: `inv_add`, `rpg_*` setters, `mob_spawn`, `world time`, teleport via the player body. Where an API is missing the smallest setter is added to the module that owns the data.
- `WORLDHDR.cheater` @605 read/written by `game.asm` save/load; `saves.asm` listing reads it into `WORLDENTRY` (new field `.cheater`); `menus.asm` draws the tag.
- Debug stat bonuses: 46 signed 16-bit values (92 bytes) stored in the free `WORLDHDR.pad2` at @16656 (named `.debug_stats`), loaded into a global `debug_stat_bonus` table that `rpg_recompute` adds after its caps run, so `rpg.asm` does not depend on the menu.

## Tests

- F12 detector: 3 presses within 1 s open it; 2 presses, a gap of 61 steps, or an interleaved other key do not; the open flag survives nothing else.
- `debug_mark_cheater` sets the header byte; save then load keeps it; an old header (byte 0) loads as not cheated; the world list entry carries the flag.
- Actions: give item (merge and overflow), set level / points, spawn N mobs of a type at a level and elite, kill all, set time, stat bonus changes `rpg_stat` and survives reload.
