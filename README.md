# AssemblyCraft

A Minecraft-like voxel sandbox written **entirely in x86-64 NASM assembly** — no C game code, no engine, just `nasm`, GLFW, OpenGL and PulseAudio.

> **Vibe-coded, on purpose.** This is an experiment: how far can Claude go writing a whole game in assembly? The author can't really read assembly, so nobody has reviewed it line by line. It is **buggy**, and that's fine — it's part of the fun. Expect crashes, weird terrain, and things that only work because the selftests say so.

## What's in it

~98k lines of assembly across 94 source files in `src/`:

- **World**: infinite streamed terrain, climate-based biomes (taiga, savanna, shores, birch forests…), caves, ravines, lava, ores, villages, dungeons and other generated structures
- **Gameplay**: Creative and Survival modes, crafting, furnaces, chests, inventory, day/night and sleeping, fire and explosions
- **Combat & RPG**: mobs, melee, bows and firearms, abilities, gear, quests, factions
- **Presentation**: OpenGL chunk mesher, dynamic lighting, sky, HUD, menus, procedural sound and audio
- **Saves**: worlds persist to disk (`world.acw`)
- **Tests**: a built-in selftest suite (178 tests) run by the binary itself

Design notes for each milestone live in `docs/superpowers/`.

## Build & run

Requirements: Linux x86-64, `nasm`, `gcc` (used only as linker), and the GLFW, OpenGL and PulseAudio (`libpulse-simple`) development libraries.

```sh
make          # build to build/assemblycraft
make run      # launch the game
make test     # run the built-in selftests
make clean
```

## Status

Working, playable, and definitely not stable. Known deferred items are tracked in the GitHub issues. Bug reports are welcome, but fixes are mostly "ask Claude again".

## Why?

Because it's funny, and because it's a good stress test of an AI writing low-level code at scale.
