# AssemblyCraft

A Minecraft-like voxel sandbox written **entirely in x86-64 NASM assembly** — no C game code, no engine, just `nasm`, GLFW, OpenGL and PulseAudio.

> **Vibe-coded, on purpose.** This is an experiment: how far can Claude go writing a whole game in assembly? The author can't really read assembly, so nobody has reviewed it line by line. It is **buggy**, and that's fine — it's part of the fun. Expect crashes, weird terrain, and things that only work because the selftests say so.

## What's in it

~140k lines of assembly across 110 source files in `src/` (plus the rendezvous server in `server/`):

- **World**: infinite streamed terrain, climate-based biomes (taiga, savanna, shores, birch forests…), caves, ravines, lava, ores, villages, dungeons and other generated structures
- **Gameplay**: Creative and Survival modes, crafting, furnaces, chests, inventory, day/night and sleeping, fire and explosions
- **Combat & RPG**: mobs, melee, bows and firearms (with attachments), abilities (four each for the Warrior, Archer, Rogue and Marksman; the Mage casts runes instead), a shared skill web with five archetypes (Warrior, Mage, Marksman, Rogue, Archer), gear, quests, factions
- **Debug menu**: press `F12` three times while playing for a tabbed menu (Player, Items, Enemies, World) to change stats and levels, give items, spawn mobs, set the time, teleport and more; opening it marks the world as cheated for good (a red `CHEATER` tag in the world list, a `[C]` in the HUD and a line in the F3 overlay)
- **HUD vials**: health, hunger, mana, stamina and XP are glass vials (brass caps, graduation marks, a liquid that drains and refills) with a `value/max` counter inside, in white with a dark outline so it reads on any liquid.
- **Presentation**: OpenGL chunk mesher, dynamic lighting, sky, HUD, menus, procedural sound and audio
- **Multiplayer** (0.11): up to 8 players in one world. A player hosts the world they have open (Esc, *Open to multiplayer*); friends join with a 6-letter room code (UDP hole punching through a small rendezvous server, with a relay fallback) or a direct `IP:port`. Co-op survival (shared mobs, drops, chests, boats, TNT, fire), optional PvP, chat (`T`), a player list (`Tab`), a shared quest chain and faction standing, and each guest's character is saved by the host
- **Events** (0.12): faction events you play through, alone or in co-op. A temporary camp asks for help and you hold it through three waves; an existing camp or village can come under threat (four waves, all its folk defend); a free caravan or a camp trader's road caravan needs an escort past two or three ambushes. Raiders of a rival faction attack by day, zombies, skeletons and spiders by night. Winning pays faction standing, XP and faction-themed loot. One event runs at a time; a new offer arrives every 10 minutes, and the debug menu's Enemies tab (Camp, Caravan, Threat, Wave, Win) starts and steers them. Design: `docs/superpowers/specs/2026-11-10-assemblycraft-events-design.md`
- **Planes** (0.13): craft an Airplane from an engine, two wings, a fuselage, a propeller and a tail (about 35 iron ingots), put it on the top of a block, board it with a right click, hold `W` to roll and raise the view to take off. The plane follows the view (mouse, `A`/`D` to turn), `W`/`S` set the throttle, `V` flips between the third-person chase camera and the cockpit, sneak lets you out once it has stopped on the ground. Land gently (slow, nose level), on ground or on water, or it crashes: a crash wears the airplane (it has a durability bar, the fourth crash destroys it) and throws you out; the plane stays where it fell. In multiplayer the plane seats a pilot and three gunners (a right click boards the first free seat): a gunner aims within a cone around his side of the plane and holds the left button for a Gatling with unlimited ammunition (10 shots a second; it hurts mobs, and players when PvP is on). Design: `docs/superpowers/specs/2026-11-10-assemblycraft-plane-design.md`
- **Looks** (0.13): every character is a detailed cartoon-blocky skinned model (faces, clothes, hair, accessories; the five factions, their elders, merchants, hoods, helmets and packs, all mobs, the Fallen King and the players' avatars, tinted by slot colour); all 93 item icons are redrawn at 32×32; NPCs, mobs and other players hold their weapon or item in the hand; firearms, the boat and the plane are detailed models. Art is data (`src/art.inc` macros in `src/skins_*.asm` and `src/iconart_*.asm`), drawn by `src/skin.asm` and `src/icons.asm` from a 256×4096 atlas. Design: `docs/superpowers/specs/2026-11-10-assemblycraft-looks-design.md`
- **Runes** (0.14): sixteen magic attributes you combine by casting them together. Deliveries: Ball, Laser, Nova, Phase (teleport), Dash; elements: Fire, Frost, Shock, Poison; modifiers: Burst, Pierce, Seek, Chain; boons: Heal, Haste, Feather. Hold the keys of up to four runes, or tap them within 0.75 s, then press the Cast key (`Right Shift`): `Laser` + `Frost` + `Pierce` is a long freezing beam, `Fire` + `Poison` alone is a burning poisoned Ball, `Heal` alone heals. Phase rides a Ball, Laser or Nova instead of doing nothing: `Ball` + `Phase` teleports you to where the ball hits (a mob, a wall, the floor; with Pierce, the last foe it goes through; a ball that meets nothing takes you nowhere), `Laser` + `Phase` follows the beam (up to Phase's 8 blocks), `Nova` + `Phase` arrives first and then bursts. Dash rides every delivery too: `Ball` + `Dash` surges you along the ball's flight when it hits, `Laser`/`Nova` + `Dash` surge you along your look after the beam or the burst, `Phase` + `Dash` blinks then surges (and `Ball` + `Phase` + `Dash` does both at the impact). Falling after a Phase ball that lands you high up is intended. Each rune adds its mana and cooldown (a rune that does nothing in the combination is inert; a fifth rune is dropped), and the HUD strip at the bottom right shows your runes, their keys and a live preview of the spell. The Path of the Mage teaches Ball and Fire and three of its grimoire nodes teach Phase, Laser and Nova; every rune is also a Rune item, dropped by hostile mobs (2 %, the Fallen King always) and found in dungeon and crypt chests, learned with a right click. The rune keys and the Cast key are rebindable (Options > Controls > Rune keys), and Options has a Rune Opacity slider (10-100 %) for the strip; a digit bound to an action no longer picks its hotbar slot. Spells work in multiplayer. Design: `docs/superpowers/specs/2026-11-11-assemblycraft-runes-design.md`
- **Saves**: worlds persist to disk (`world.acw`)
- **Tests**: a built-in selftest suite run by the binary itself (`make test`)

Design notes for each milestone live in `docs/superpowers/`.

## Build & run

Requirements: Linux x86-64, `nasm`, `gcc` (used only as linker), and the GLFW, OpenGL and PulseAudio (`libpulse-simple`) development libraries.

```sh
make          # build to build/assemblycraft
make run      # launch the game
make test     # run the built-in selftests
make relay    # build the rendezvous/relay server, build/acrelay (static, no libc)
make clean
```

### Windows build

A native 64-bit Windows `.exe` is cross-built on Linux: the game's assembly is assembled with `nasm -f win64`, and a small C platform layer in `win/` (Linux-syscall emulation on Win32/Winsock, GL/GLFW wrappers, threads, waveOut audio) bridges the System V convention the assembly uses to Windows. It needs Docker for the mingw-w64 toolchain.

```sh
make windows-image   # once: builds the ac-mingw docker image (gcc-mingw-w64)
make windows         # build/win/assemblycraft.exe
make windows-zip     # build/win/AssemblyCraft-0.13.1-win64.zip (exe + README-WINDOWS.txt + licenses)
```

The full selftest suite runs under Wine: `wine build/win/assemblycraft.exe --selftest`. Windows and Linux builds play together in the same multiplayer world.

## Multiplayer

The host is authoritative: it owns the world (blocks, mobs, drops, time, quests) and every guest simulates only its own player. Guests' characters are saved by the host under `<world>/players/<name>.hdr`.

```sh
# host: open the world from the pause menu, or from the command line
build/assemblycraft --play myworld --host --name Alice [--pvp]
# join with the room code the host sees, or a direct address (LAN / Tailscale)
build/assemblycraft --join ABC123 --name Bob
build/assemblycraft --join 192.168.1.20:27615 --name Bob
build/assemblycraft --join ABC123 --name Bob --force-relay   # skip hole punching
```

`multiplayer.cfg` in the data directory keeps the name, rendezvous server (`server=ip:port`, default `93.127.163.226:27600`) and host port. Run your own server with `build/acrelay --port 27600` (`server/acrelay.service` is a systemd unit); `acrelay --probe IP:PORT` checks one and `acrelay --selftest` runs its tests. Design: `docs/superpowers/specs/2026-11-09-assemblycraft-multiplayer-design.md`.

## Status

Working, playable, and definitely not stable. Known deferred items are tracked in the GitHub issues. Bug reports are welcome, but fixes are mostly "ask Claude again".

## Why?

Because it's funny, and because it's a good stress test of an AI writing low-level code at scale.
