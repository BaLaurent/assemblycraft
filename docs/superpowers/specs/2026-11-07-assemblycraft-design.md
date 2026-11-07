# AssemblyCraft — a Minecraft-Classic-style clone in x86-64 NASM

## Context

The user wants a Minecraft clone written **entirely in assembly**. Settled choices:
- Every source line is hand-written x86-64 NASM. There are no C files and no shaders (fixed-function OpenGL).
- The game links GLFW (window, input), legacy OpenGL (rendering) and libc (only for `crt1`'s `_start` → `main`).
- Target: Linux x86-64, in the empty directory `/run/media/octopusman/Games/Experiences/assemblycraft`. It is not a git repo yet.
- The first milestone is **"Classic creative"**:
  - a fixed 256×64×256 chunked world with heightmap terrain and trees, and 11 block types with procedurally generated textures;
  - walk, jump and collision, plus a fly toggle;
  - break, place and pick blocks with a raycast;
  - a hotbar and a crosshair;
  - save and load to one file.

Probed environment:
- NASM 3.02 (`/usr/bin/nasm`), gcc as the linker, `libglfw` 3.5.1 and `libGL` (glvnd). Both libraries export every function used here directly, including the GL 1.5 calls `glGenBuffers`, `glBindBuffer` and `glBufferData`, so no `GetProcAddress` is needed.
- Mesa reports a 4.6 compatibility profile.
- Hyprland on Wayland; an AVX2/SSE4.2 CPU; `omabox` 1.0.1, `gdb`, `ffmpeg` and `magick` are available.

## Conventions (every file)

- **File header:** `%include "common.inc"` first, then `default rel`. Files that touch GLFW/GL also `%include "gl.inc"`.
- **GNU-stack note:** `common.inc` itself contains `section .note.GNU-stack noalloc noexec nowrite progbits`, so every file that includes it must switch to `section .text` / `.data` / `.rodata` / `.bss` explicitly before emitting anything.
- **Assemble and link:** `nasm -f elf64 -g -F dwarf -Isrc/`, linked with `gcc -no-pie … -lglfw -lGL`.
  - `-no-pie` is load-bearing. It allows absolute `[table + reg*scale]` addressing of `.bss`/`.data` symbols (RIP-relative addressing can't take an index register).
  - It also lets `call glfwInit` resolve through the PLT with no `wrt ..plt`.
- **Calling convention:** SysV AMD64 for ALL functions, internal ones included.
  - Integer arguments go in `rdi, rsi, rdx, rcx, r8, r9`; float/double arguments in `xmm0–7`.
  - Return values come back in `eax/rax` or `xmm0`.
  - Callee-saved registers are `rbx, rbp, r12–r15`. Every `xmm` register is caller-saved: spill floats to the stack across calls (e.g. `world_is_solid` inside the physics code).
- **Stack alignment:** `rsp` must be 16-byte aligned at every `call`.
  - Non-leaf functions start with `push rbp` / `mov rbp, rsp`, then push callee-saved registers, then `sub rsp, N`, with `8*(pushes after rbp) + N ≡ 0 (mod 16)`.
  - Stack arguments (only `glTexImage2D` has them: arguments 7–9) are placed at `[rsp]`, `[rsp+8]` and `[rsp+16]` at call time, with `rsp` still 16-aligned.
- **Symbols:** each file declares its own `extern`s for other modules' symbols, plus `global` for its own API. NEVER put cross-module `extern`s in `common.inc`: a file must not both `extern` and define the same symbol.
- **Floats:** scalar SSE single precision (`movss`, `addss`, …) for game math.
  - Floor: `roundss xmm, xmm, 9`. Ceil: `roundss xmm, xmm, 10`. Both followed by `cvttss2si`.
  - x87 is used ONLY inside `sincos_deg`, which must leave the x87 stack empty.
- **No libc calls.** All I/O uses raw syscalls via `sys.asm`. The only libc involvement is `_start` → `main`.

## Shared contracts

This section is the contract that lets modules be written in parallel. Names, layouts and values are fixed.

### `src/common.inc` constants and structs

- **World**
  - `WORLD_X 256`, `WORLD_Y 64`, `WORLD_Z 256`, `WORLD_VOLUME 4194304`.
  - Block index = `(y<<16)|(z<<8)|x`; one byte per block.
- **Chunks**
  - `CHUNK 16`, `CHUNKS_X 16`, `CHUNKS_Y 4`, `CHUNKS_Z 16`, `NUM_CHUNKS 1024`.
  - Chunk index = `(cy*16 + cz)*16 + cx`.
- **Block ids**
  - `AIR 0`, `STONE 1`, `GRASS 2`, `DIRT 3`, `COBBLE 4`, `PLANKS 5`, `LOG 6`, `LEAVES 7`, `SAND 8`, `GLASS 9`, `BRICK 10`, `BEDROCK 11`, `NUM_BLOCKS 12`.
  - Flags: `FLAG_SOLID 1`, `FLAG_OPAQUE 2`, `FLAG_CULL_SAME 4`.
- **Mesh:** `MAX_CHUNK_VERTS 98304` (4096 blocks × 6 faces × 4), `VERTEX_SIZE 16`.
- **Texture:** `ATLAS_PX 256`, `TILE_PX 16`, `TEX_UNITS_PER_TILE 256`. Texture coordinates are integers in 1/16-pixel units, so the atlas spans 4096 units.
- **Save file:** `WORLD_HDR_SIZE 48`, `WORLD_FILE_SIZE 4194352`, `HOTBAR_SLOTS 9`.
- **Syscalls:**
  - `SYS_READ 0`, `SYS_WRITE 1`, `SYS_OPEN 2`, `SYS_CLOSE 3`, `SYS_RENAME 82`, `SYS_UNLINK 87`.
  - Open flags: `O_RDONLY 0`, `O_WCT 0x241` (`O_WRONLY|O_CREAT|O_TRUNC`), `MODE_644 420`.
  - Errors: `ENOENT 2`, `EINTR 4`, `ENAMETOOLONG 36`.
- **Structs** (NASM `struc` with `.field: resd 1`):
  - `INPUT` (20 B): `.fwd .strafe` (int32, −1/0/1; W=+1/S=−1, D=+1/A=−1), then `.jump .down .sprint` (int32, 0/1).
  - `FRAMEINPUT`:
    - `.move` (`resb INPUT_size`, at offset 0);
    - `.look_dx .look_dy` (float pixels);
    - `.lmb_held .lmb_pressed .rmb_held .rmb_pressed .mmb_pressed`;
    - `.slot` (−1 or 0..8);
    - `.scroll` (signed steps, +1 = wheel up);
    - `.toggle_fly .save .captured`.
    - All fields are int32 except `look_*`.
  - `PLAYER` (40 B): `.x .y .z .vx .vy .vz .yaw .pitch` (float; `.y` = feet), then `.on_ground .flying` (int32).
  - `RAYHIT` (24 B): `.bx .by .bz` (block hit) and `.px .py .pz` (the cell entered just before it), all int32.
  - `WORLDHDR` (48 B): `.magic resb 8` (`"ACRAFT01"`), `.seed` u32, `.px .py .pz .yaw .pitch` float, `.flying resb 1`, `.sel resb 1`, `.hotbar resb 9`, `.pad resb 5`.
  - `VERTEX` (16 B): int16 `x, y, z, pad`; int16 `u, v`; uint8 `r, g, b, a`.

### `src/gl.inc`

- GLFW/GL `extern`s plus the enum values below, copied from `/usr/include/GLFW/glfw3.h` and `/usr/include/GL/gl.h`/`glext.h` (values verified).
- **GLFW:**
  - Basics: `GLFW_TRUE 1`, `GLFW_PRESS 1`, `GLFW_DEPTH_BITS 0x21005`.
  - Cursor: `GLFW_CURSOR 0x33001`, `GLFW_CURSOR_NORMAL 0x34001`, `GLFW_CURSOR_DISABLED 0x34003`, `GLFW_RAW_MOUSE_MOTION 0x33005`.
  - Window identity: `GLFW_WAYLAND_APP_ID 0x26001`, `GLFW_X11_CLASS_NAME 0x24001`.
  - Keys: `KEY_SPACE 32`, `KEY_1 49` … `KEY_9 57`, `KEY_A 65`, `KEY_D 68`, `KEY_F 70`, `KEY_S 83`, `KEY_W 87`, `KEY_ESCAPE 256`, `KEY_F5 294`, `KEY_LEFT_SHIFT 340`, `KEY_LEFT_CONTROL 341`.
  - Mouse buttons: `MOUSE_LEFT 0`, `MOUSE_RIGHT 1`, `MOUSE_MIDDLE 2`.
- **GL:**
  - Types: `GL_UNSIGNED_BYTE 0x1401`, `GL_SHORT 0x1402`.
  - Primitives: `GL_LINES 1`, `GL_LINE_LOOP 2`, `GL_QUADS 7`.
  - Client arrays: `GL_VERTEX_ARRAY 0x8074`, `GL_COLOR_ARRAY 0x8076`, `GL_TEXTURE_COORD_ARRAY 0x8078`.
  - Matrix modes: `GL_MODELVIEW 0x1700`, `GL_PROJECTION 0x1701`, `GL_TEXTURE 0x1702`.
  - Capabilities: `GL_CULL_FACE 0x0B44`, `GL_DEPTH_TEST 0x0B71`, `GL_ALPHA_TEST 0x0BC0`, `GL_BLEND 0x0BE2`, `GL_FOG 0x0B60`, `GL_TEXTURE_2D 0x0DE1`.
  - Comparison: `GL_GREATER 0x0204`.
  - Blending: `GL_ZERO 0`, `GL_SRC_ALPHA 0x0302`, `GL_ONE_MINUS_SRC_ALPHA 0x0303`, `GL_ONE_MINUS_DST_COLOR 0x0307`.
  - Fog: `GL_FOG_MODE 0x0B65`, `GL_FOG_COLOR 0x0B66`, `GL_FOG_START 0x0B63`, `GL_FOG_END 0x0B64`, `GL_LINEAR 0x2601`.
  - Textures: `GL_RGBA 0x1908`, `GL_UNPACK_ALIGNMENT 0x0CF5`, `GL_TEXTURE_WRAP_S 0x2802`, `GL_TEXTURE_WRAP_T 0x2803`, `GL_TEXTURE_MAG_FILTER 0x2800`, `GL_TEXTURE_MIN_FILTER 0x2801`, `GL_NEAREST 0x2600`, `GL_CLAMP_TO_EDGE 0x812F`.
  - Clear bits: `GL_COLOR_BUFFER_BIT 0x4000`, `GL_DEPTH_BUFFER_BIT 0x100`.
  - Buffers: `GL_ARRAY_BUFFER 0x8892`, `GL_STATIC_DRAW 0x88E4`.

### Module API

Arguments are listed in register order.

| File | Symbol | Signature / contents |
|---|---|---|
| `sys.asm` | `sys_print` | `(edi fd, rsi zstr)`; loops `write` until done |
| | `str_len` / `str_eq` | `(rdi)→rax` / `(rdi, rsi)→eax 1/0` |
| | `parse_u32` | `(rdi zstr, rsi u32* out)→eax 1 ok / 0 bad`. Decimal digits only, non-empty; overflow above 4294967295 → 0 |
| | `i32_to_str` | `(edi value, rsi buf)→rax` = pointer past the last char. Signed; writes no NUL |
| | `str_append` | `(rdi dst_end, rsi zstr)→rax` new end; writes no NUL |
| | `file_read` | `(rdi path, rsi buf, rdx cap)→rax` bytes read or `-errno`. Loops `read` until 0 or `cap`; retries on `-EINTR` |
| | `file_write_atomic` | `(rdi path, rsi buf, rdx len)→eax 0` or `-errno`. Writes `path+".tmp"` (mode 0644, loops on partial writes), `close`, `rename` onto `path`. On any failure, `unlink`s the tmp file. `str_len(path) > 4000` → `-ENAMETOOLONG` |
| `mathf.asm` | `sincos_deg` | `(xmm0 deg)→xmm0 sin, xmm1 cos` (float). x87 `fsincos` on `deg*π/180` |
| | `floor_i` / `ceil_i` | `(xmm0 float)→eax` |
| `blockdefs.asm` | `block_flags` | `db` ×12: AIR 0; STONE, GRASS, DIRT, COBBLE, PLANKS, LOG, SAND, BRICK, BEDROCK = 3; LEAVES = 1; GLASS = 5 |
| | `block_tiles` | `db` ×12×3 (top, side, bottom): AIR 0,0,0 · STONE 0,0,0 · GRASS 1,2,3 · DIRT 3,3,3 · COBBLE 4,4,4 · PLANKS 5,5,5 · LOG 7,6,7 · LEAVES 8,8,8 · SAND 9,9,9 · GLASS 10,10,10 · BRICK 11,11,11 · BEDROCK 12,12,12 |
| | `block_names` | `dq` ×12 pointers to NUL-terminated strings: "Air", "Stone", "Grass", "Dirt", "Cobblestone", "Planks", "Log", "Leaves", "Sand", "Glass", "Bricks", "Bedrock" |
| `world.asm` | `world_header`, `blocks`, `chunk_dirty` | `.bss`, declared contiguously: `alignb 64`, `world_header resb 48`, `blocks resb WORLD_VOLUME`, `world_slack resb 16`. The header and blocks together form the 4194352-byte file image starting at `world_header`. Then `chunk_dirty resb 1024` |
| | `world_get` | `(edi x, esi y, edx z)→eax id`; out of bounds → `AIR` |
| | `world_set` | `(edi x, esi y, edx z, ecx id)`. No-op out of bounds. Otherwise stores the id and sets `chunk_dirty` for the chunk of every in-bounds cell in the 3×3×3 neighbourhood |
| | `world_is_solid` | `(edi, esi, edx)→eax 0/1`. y<0 → 1; y≥64 → 0; x or z out of bounds → 1; else `block_flags & FLAG_SOLID` |
| | `world_is_opaque` | `(edi, esi, edx)→eax 0/1`; out of bounds → 0 |
| | `world_top_y` | `(edi x, esi z)→eax` highest non-air y, or −1 |
| | `world_clear` / `world_mark_all_dirty` | zero `blocks` / set all 1024 `chunk_dirty` bytes to 1 |
| | `world_save` | `(rdi path)→eax 0` or `-errno`. Writes the magic `"ACRAFT01"` into the header, then `file_write_atomic(path, world_header, WORLD_FILE_SIZE)` |
| | `world_load` | `(rdi path)→eax` 0 ok / 1 missing / 2 invalid / 3 I/O error. `file_read(path, world_header, WORLD_FILE_SIZE+1)`: `-ENOENT` → 1; other negative → 3; byte count ≠ `WORLD_FILE_SIZE` or bad magic → 2. On 0, calls `world_mark_all_dirty` |
| `worldgen.asm` | `world_generate` | `(edi seed)` |
| `texgen.asm` | `texgen_build` | `(rdi out)`; fills 256×256×4 RGBA |
| `mesher.asm` | `mesh_chunk` | `(edi cx, esi cy, edx cz, rcx out)→eax` vertex count |
| | `mesh_scratch` | `.bss`, `MAX_CHUNK_VERTS*16` bytes |
| `raycast.asm` | `raycast` | `(rdi float origin[3], rsi float dir[3], rdx RAYHIT* out, xmm0 maxdist)→eax hit 0/1` |
| `player.asm` | `player` | `PLAYER` instance |
| | `player_spawn` / `player_step` | `()` / `(rdi INPUT*)`: one 1/60 s step |
| | `player_look` | `(xmm0 dx, xmm1 dy)` |
| | `player_eye` / `player_forward` | `(rdi float out[3])` |
| | `player_intersects_block` | `(edi x, esi y, edx z)→eax 0/1` |
| `input.asm` | `frame_input`, `input_init`, `input_poll` | `FRAMEINPUT` instance; `(rdi window)`; `(rdi window)` |
| `game.asm` | `hotbar` (`resb 9`), `hotbar_sel` (dd), `game_target` (`RAYHIT`), `game_has_target` (dd) | game state |
| | `game_new` / `game_load` / `game_save` / `game_frame` | `(edi seed)` / `(rdi path)→eax` as `world_load` / `(rdi path)→eax` as `world_save` / `(xmm0 float dt)` |
| `render.asm` | `render_init` / `render_update_chunks` / `render_frame` | `()` / `()` / `(edi fb_w, esi fb_h)` |
| `selftest.asm` | `selftest_run` | `()→eax` exit code |
| `main.asm` | `main` | `(edi argc, rsi argv)→eax` |

## Approach

### Step 1 — Scaffold, platform helpers, world storage, selftest runner (sequential, one owner)

1. **Initialise the repo.** Run `git init`. Write `.gitignore` with `build/`, `*.acw` and `*.acw.tmp`. Copy this plan to `docs/superpowers/specs/2026-11-07-assemblycraft-design.md`.
2. **Write the `Makefile`:**
   ```make
   NASMFLAGS := -f elf64 -g -F dwarf -Isrc/
   SRCS := $(wildcard src/*.asm)
   OBJS := $(patsubst src/%.asm,build/%.o,$(SRCS))
   INCS := $(wildcard src/*.inc)
   all: build/assemblycraft
   build/assemblycraft: $(OBJS) ; gcc -no-pie -o $@ $(OBJS) -lglfw -lGL
   build/%.o: src/%.asm $(INCS) | build ; nasm $(NASMFLAGS) $< -o $@
   build: ; mkdir -p build
   test: build/assemblycraft ; ./build/assemblycraft --selftest
   run: build/assemblycraft ; ./build/assemblycraft
   clean: ; rm -rf build
   .PHONY: all test run clean
   ```
3. **Write the shared files.** `src/common.inc`, `src/gl.inc`, `src/sys.asm`, `src/mathf.asm`, `src/blockdefs.asm` and `src/world.asm`, exactly per **Shared contracts**.
4. **Write `src/selftest.asm`.**
   - A `.data` registry `tests: dq fn, name, fn, name, …, 0`. Each test function is `()→eax`: 0 = pass, nonzero = fail. Each printed name is the function name without its `test_` prefix (e.g. `test_world_bounds` → `world_bounds`).
   - `selftest_run` calls each test and prints `ok <name>\n` or `FAIL <name>\n` to stdout.
   - It finishes with `selftest: <P> passed, <F> failed\n` and returns 0 iff F = 0.
   - Every test begins with `world_clear` itself.
5. **Write `src/test_world.asm`.** It exports `fnv1a (rdi ptr, rsi len)→eax` (FNV-1a 32-bit: offset 2166136261, prime 16777619) plus three tests:
   - `test_world_bounds`:
     - `world_get` returns AIR for (−1,0,0), (256,0,0) and (0,64,0).
     - `world_is_solid` is 1 for (−1,10,10), (256,10,10) and (10,−1,10), and 0 for (10,64,10).
     - The `fnv1a` of `blocks` is unchanged by `world_set(−1,0,0,STONE)`.
   - `test_world_set_marks_dirty`: zero `chunk_dirty`, then `world_set(16,5,5,STONE)`. Chunks (0,0,0) and (1,0,0) are dirty; chunk (2,0,0) is not.
   - `test_world_save_load`:
     1. Set `world_set(1,2,3,BRICK)` and `world_set(255,63,255,GLASS)`, plus header seed 7.
     2. Hash `blocks`, then `world_save("/tmp/assemblycraft-selftest.acw")` must return 0.
     3. `world_clear`, header seed 0, then `world_load` must return 0. The hash must match, the seed must be 7 and (1,2,3) must be BRICK.
     4. `file_write_atomic(path, "garbage!!!", 10)`, then `world_load` must return 2.
     5. `unlink(path)`, then `world_load` must return 1.
6. **Write `src/main.asm` (argument handling only in this step).**
   - Parse `--help`, `--selftest`, `--seed N` (via `parse_u32`) and `--world PATH` (default `"world.acw"`).
   - An unknown argument or a bad/missing value prints the usage to stderr and returns 2.
   - `--help` prints the usage to stdout and returns 0.
   - `--selftest` returns `selftest_run()`.
   - In step 1 only, a plain run (no `--selftest`/`--help`) prints the usage to stderr and returns 2. Step 3 replaces that branch with the game.
   - Usage text, verbatim:
     ```
     usage: assemblycraft [--world PATH] [--seed N] [--selftest] [--help]
       --world PATH  world file to load and save (default: world.acw)
       --seed N      seed for a newly generated world (default: random)
       --selftest    run internal tests and exit
     controls: WASD move, mouse look, Space jump (fly: up), Left Shift fly down, Left Ctrl sprint,
               F toggle fly, LMB break, RMB place, MMB pick block, 1-9 / wheel select, F5 save,
               Esc release mouse (click to recapture), close window to save and quit
     ```
7. **Done when** `make && make test` prints three `ok` lines and `selftest: 3 passed, 0 failed`, and exits 0. Then commit: `step 1: scaffold, world storage, selftest`.

### Step 2 — Core modules (four independent workers, in parallel after step 1)

- **Ownership:** each worker owns only its files and writes no other file.
- **Test registration:** the integrator (step 1's owner) adds each worker's tests to the `selftest.asm` registry, then runs `make test`. Once all four workers are merged and `make test` reports `selftest: 17 passed, 0 failed`, commit `step 2: worldgen, mesher, physics, texgen`.
- **Independence:** the workers depend only on step 1 files and the contracts. Worker C's tests use `world_set` from step 1, not worldgen.

#### Worker A — `src/worldgen.asm`, `src/test_worldgen.asm`

- **Hash.** `hash32(ix, iz, seed, k)` uses wrapping u32 arithmetic (`imul r32`):
  - `h = ix*0x27D4EB2D + iz*0x165667B1 + seed*0x9E3779B1 + k*0x85EBCA77`
  - then `h ^= h>>15; h *= 0x2C1B3C6D; h ^= h>>12; h *= 0x297A2D39; h ^= h>>15`.
  - The lattice value is `(h & 0xFFFF) * (1/32767.5) − 1.0`.
- **Value noise.** `noise(x, z, shift, k)`:
  - `ix = x>>shift`, `fx = (x & ((1<<shift)−1)) / (1<<shift)` (same for z);
  - `s = f*f*(3−2f)` smoothstep;
  - bilinear blend of lattice values at (ix,iz), (ix+1,iz), (ix,iz+1), (ix+1,iz+1).
- **Height.** `height(x,z) = clamp(floor(30 + 14·noise(6,k0) + 7·noise(5,k1) + 3.5·noise(4,k2) + 1.75·noise(3,k3)), 5, 56)`, where k0–k3 = 0..3. Store it in a 64 KiB `heightmap` (`z*256+x`).
- **`world_generate(seed)`:**
  1. Call `world_clear`.
  2. For every column, with `sand = h ≤ 22`, write directly into `blocks`:
     - y=0 BEDROCK;
     - y 1..h−4 STONE;
     - y h−3..h−1 SAND if `sand`, else DIRT;
     - y=h SAND if `sand`, else GRASS.
  3. Trees: for x, z in 2..253:
     - Skip unless `blocks[h]` is GRASS and `(t = hash32(x,z,seed,99)) & 255 < 3`.
     - Trunk height `H = 4 + ((t>>8) % 3)`, `base = h+1`; skip if `base+H > 63`.
     - Set (x,h,z) to DIRT and y `base..base+H−1` to LOG.
     - Place leaves only where AIR:
       - layers `base+H−3` and `base+H−2`: dx, dz ∈ [−2,2] except the four |dx|=|dz|=2 corners;
       - layer `base+H−1`: dx, dz ∈ [−1,1];
       - layer `base+H`: dx, dz ∈ [−1,1] except the corners.
  4. Set `world_header.seed = seed` and call `world_mark_all_dirty`.
- **Tests:**
  - `test_worldgen_deterministic`: generating seed 42 twice gives the same `fnv1a(blocks)`; seed 43 gives a different one.
  - `test_worldgen_shape`: for seed 42, every column has BEDROCK at y=0, every byte < `NUM_BLOCKS`, the GRASS count > 10000, and the LOG and LEAVES counts are both > 0.

#### Worker B — `src/mesher.asm`, `src/test_mesher.asm`

- **Traversal.** For each non-air block in chunk (cx,cy,cz) (loops ly, lz, lx) and for each face d in order `0 +X, 1 −X, 2 +Y, 3 −Y, 4 +Z, 5 −Z`:
  - The neighbour id is `world_get(block + normal)`.
  - The face is visible iff the neighbour is AIR, or (the neighbour is not `FLAG_OPAQUE` and (neighbour ≠ block or the block lacks `FLAG_CULL_SAME`)). So leaf–leaf faces render, glass–glass faces don't, and neighbouring chunks are read through `world_get`.
- **Corners.** Corner offsets in order BL, BR, TR, TL are counter-clockwise seen from outside, so the default GL back-face culling works:
  - +X: (1,0,1) (1,0,0) (1,1,0) (1,1,1)
  - −X: (0,0,0) (0,0,1) (0,1,1) (0,1,0)
  - +Y: (0,1,1) (1,1,1) (1,1,0) (0,1,0)
  - −Y: (1,0,1) (0,0,1) (0,0,0) (1,0,0)
  - +Z: (0,0,1) (1,0,1) (1,1,1) (0,1,1)
  - −Z: (1,0,0) (0,0,0) (0,1,0) (1,1,0)
- **Texture coordinates.**
  - The tile is `block_tiles[id*3 + slot]`, with slot = 0 for face +Y, 2 for −Y, 1 otherwise.
  - `col = tile & 15`, `row = tile >> 4`.
  - `u0 = col*256+1`, `u1 = col*256+255`, `v0 = row*256+1`, `v1 = row*256+255` (a 1/16-px inset against bleeding).
  - Assign BL=(u0,v1), BR=(u1,v1), TR=(u1,v0), TL=(u0,v0).
- **Ambient occlusion per vertex.**
  - For each axis i where `n[i] = 0`, set `s[i] = 2*corner[i] − 1`. Call the two such axes i1 < i2.
  - `side1 = opaque(B+n+s[i1]·e_i1)`, `side2 = opaque(B+n+s[i2]·e_i2)`, `corner = opaque(B+n+s[i1]·e_i1+s[i2]·e_i2)`, using `world_is_opaque`.
  - `ao = (side1 && side2) ? 0 : 3 − (side1+side2+corner)`.
- **Brightness.** `shade[d][ao]`, with r=g=b=brightness and a=255:
  - ±X: 77, 99, 122, 153
  - +Y: 128, 166, 204, 255
  - −Y: 64, 83, 102, 128
  - ±Z: 102, 133, 163, 204
- **Diagonal flip.** If `ao1+ao3 > ao0+ao2`, emit vertices in order v1, v2, v3, v0 (each keeping its own uv and colour); otherwise v0..v3.
- **Output.** Write `VERTEX`es to `out` with world coordinates (block + corner) as int16 and pad 0. Return the vertex count.
- **Tests** (each calls `mesh_chunk(…, mesh_scratch)`):
  - `test_mesh_single_block`: STONE at (5,5,5) → 24.
  - `test_mesh_adjacent_opaque`: STONE at (5,5,5) and (6,5,5) → 40.
  - `test_mesh_adjacent_leaves`: LEAVES at both → 48.
  - `test_mesh_adjacent_glass`: GLASS at both → 40.
  - `test_mesh_chunk_boundary`: STONE at (15,5,5) and (16,5,5) → chunk (0,0,0) = 20 and chunk (1,0,0) = 20.

#### Worker C — `src/raycast.asm`, `src/player.asm`, `src/test_physics.asm`

- **`raycast` (Amanatides–Woo DDA).**
  - Setup per axis:
    - `cell = floor(origin)`, `step = sign(dir)`, `tDelta = |1/dir|` (1e30 if dir = 0);
    - `tMax = (cell+1−o)/dir` when step > 0, `(o−cell)/(−dir)` when step < 0, 1e30 when 0.
  - Set prev = cell. Loop at most 64 times:
    1. If `world_get(cell) ≠ AIR`, fill `out` (b = cell, p = prev) and return 1.
    2. Take axis a with the smallest tMax. If `tMax[a] > maxdist`, return 0.
    3. Set prev = cell, `cell[a] += step[a]`, `tMax[a] += tDelta[a]`.
  - Return 0 after the loop.
- **Physics constants (float).** dt 0.016666668, gravity 32.0, jump 9.0, terminal fall 50.0, walk 4.317, sprint 5.612, fly horizontal 10.89, fly vertical 7.5, half-width 0.3, height 1.8, eye 1.62, eps 0.001.
- **`player_step(INPUT*)`:**
  1. Wish direction:
     - forward `(sin yaw, 0, −cos yaw)` and right `(cos yaw, 0, sin yaw)` via `sincos_deg`;
     - `m = fwd·forward + strafe·right`, normalised when its length > 0.
  2. Horizontal velocity: `v.xz = m · (flying ? 10.89 : sprint ? 5.612 : 4.317)`.
  3. Vertical velocity:
     - If flying: `vy = (jump ? 7.5 : 0) − (down ? 7.5 : 0)`.
     - Else if jump && on_ground: `vy = 9.0`.
     - Else `vy −= 32·dt`, clamped to ≥ −50.
  4. Set `on_ground = 0`, then call `move_axis` for Y, then X, then Z.
- **`move_axis(axis, d = v·dt)`:**
  1. If d = 0, return. Otherwise add d to the position.
  2. The AABB is `[x−0.3, x+0.3] × [y, y+1.8] × [z−0.3, z+0.3]`.
  3. Leading slab `i = d > 0 ? ceil(max_a)−1 : floor(min_a)`. The other axes span `floor(min)..ceil(max)−1`.
  4. If any `world_is_solid` cell exists in that slab:
     - d > 0: x/z → `i − 0.3 − 0.001`; y → `i − 1.8 − 0.001`.
     - d < 0: x/z → `i + 1 + 0.3 + 0.001`; y → exactly `i + 1` and `on_ground = 1`.
     - Zero that velocity component.
  5. This is correct only because the per-step speed stays below 1 block (max 50/60 = 0.83); keep the terminal clamp.
- **`player_look(dx, dy)`:**
  - `yaw += dx*0.15`, wrapped into [0,360) with loops;
  - `pitch += dy*0.15`, clamped to [−89.9, 89.9].
- **`player_forward`:** `(sin yaw·cos pitch, −sin pitch, −cos yaw·cos pitch)`.
- **`player_eye`:** `pos + (0, 1.62, 0)`.
- **`player_intersects_block`:** strict AABB overlap of block `[b, b+1]³` with the player box.
- **`player_spawn`:**
  - position `(128.5, world_top_y(128,128)+1, 128.5)`;
  - velocity 0, yaw 0.0, pitch 30.0 (so the spawn view always targets a block), flying 0, on_ground 0.
- **Tests:**
  - `test_raycast_hit_forward`: STONE at (10,10,10), origin (10.5,10.5,5.5), dir (0,0,1), max 5.0 → hit; b = (10,10,10), p = (10,10,9).
  - `test_raycast_miss_beyond_reach`: origin z = 4.0 → no hit.
  - `test_raycast_hit_from_above`: origin (10.5,13.0,10.5), dir (0,−1,0) → b = (10,10,10), p = (10,11,10).
  - Physics floor fixture: STONE on y=10 for x, z in 0..31.
    - `test_physics_land_on_floor`: start at (16.5,12.0,16.5), zero input, 120 steps → y == 11.0 exactly and on_ground = 1.
    - `test_physics_wall_blocks`: add STONE at x=18, y ∈ {11,12}, z 0..31. Start at (16.5,11.0,16.5) with on_ground = 1, yaw 90, fwd = 1, 120 steps → 17.69 ≤ x ≤ 17.70, y == 11.0, 16.49 ≤ z ≤ 16.51.
    - `test_physics_jump_clears_one_block`: start on the floor at y 11.0 with on_ground = 1. One step with jump = 1, then 59 with jump = 0 → max y > 12.0 and final y == 11.0.
  - `test_player_intersects_block`: player at (16.5,11,16.5) → (16,11,16) = 1, (16,12,16) = 1, (16,13,16) = 0, (17,11,16) = 0.

#### Worker D — `src/texgen.asm`

`texgen_build(out)`:
- **Setup.** Zero all 262144 bytes, then seed `xorshift32` with state 0x12345678 (`x ^= x<<13; x ^= x>>17; x ^= x<<5`).
- **Pixel formula.** Draw tile t at `x0 = (t&15)*16`, `y0 = (t>>4)*16`, row-major RGBA, image row 0 = top of the tile. Unless stated otherwise, each pixel is `base * m >> 8` with alpha 255, where m is a per-pixel random multiplier (never above 255, so no clamping is needed).

| # | Tile | Base RGB | m | Rule |
|---|---|---|---|---|
| 0 | stone | (128,128,128) | `200 + (r&55)` | plain noise |
| 1 | grass_top | (106,170,64) | `192 + (r&63)` | plain noise |
| 2 | grass_side | (106,170,64) above the edge; (150,108,74) below | as tiles 1 and 3 | depth `d(px) = 3 + (r&1)`, plus 2 more if `(r&7)==0` (one draw per column first). Green where `py < d(px)`, dirt below |
| 3 | dirt | (150,108,74) | `192 + (r&63)` | plain noise |
| 4 | cobble | stones (130,130,130); mortar (70,70,70) | `176 + (r&63)` | mortar where `(py&3)==3` or `(px + (py>>2)*3) % 5 == 4` |
| 5 | planks | (162,130,78); lines (110,86,50) | `216 + (r&31)` | line where `(py&3)==3`, or `px == (((py>>2)*7+3)&15)` |
| 6 | log_side | (104,82,50); stripes (78,60,36) | `208 + (r&47)` | stripe where `((px + (r&1)) & 3) == 0` |
| 7 | log_top | light (176,140,88), dark (150,118,70); bark border (104,82,50) | `224 + (r&31)` | bark where px or py ∈ {0,15}. Else `dx = 2px−15`, `dy = 2py−15`, `ring = (cvttss2si(0.5·sqrt(dx²+dy²)) >> 1) & 1`: light if ring = 0, dark if 1 |
| 8 | leaves | (60,140,40) | `160 + (r&95)` | transparent (RGBA 0,0,0,0) where `(r&3)==0` |
| 9 | sand | (222,210,160) | `224 + (r&31)` | plain noise |
| 10 | glass | — | — | border pixels (220,240,245,255); streak (255,255,255,255) where `px+py ∈ {10,11}` and `3 ≤ px ≤ 8`; else transparent (0,0,0,0) |
| 11 | brick | (156,72,56); mortar (180,180,170) | `200 + (r&55)` | mortar where `(py&3)==3` or `((px + ((py>>2)&1)*4) & 7) == 7` |
| 12 | bedrock | (80,80,80) | `64 + (r&191)` | plain noise |

- **Done when** `texgen.asm` assembles. Its pixels are verified visually in step 3.

### Step 3 — Window, rendering, input, game loop (one owner; depends on all of step 2)

1. **`src/input.asm`.**
   - `input_init(win)`:
     - `glfwSetScrollCallback(win, scroll_cb)`; `scroll_cb` is a leaf that adds `xmm1` (yoffset, double) to `scroll_accum`.
     - Set `GLFW_CURSOR` to `CURSOR_DISABLED`.
     - If `glfwRawMouseMotionSupported()`, set `GLFW_RAW_MOUSE_MOTION` to `GLFW_TRUE`.
     - Record the baseline from `glfwGetCursorPos`; `captured = 1`.
   - `input_poll(win)` (called after `glfwPollEvents`):
     1. Zero `frame_input`. Key state is `glfwGetKey(win, key) == GLFW_PRESS`. Edge detection keeps the previous state per key and button.
     2. Esc edge while captured → `CURSOR_NORMAL`, `captured = 0`.
     3. While not captured: an LMB edge → `CURSOR_DISABLED`, `captured = 1`, reset the baseline, report nothing this frame. Otherwise report nothing (only `.captured = 0`).
     4. While captured:
        - movement (W/S/A/D/Space/LShift/LCtrl);
        - `look_d* = cursor − baseline` (converted double→float), then baseline = cursor;
        - mouse button held/pressed, with MMB pressed-only;
        - key 1..9 edge → `.slot` (the last one wins);
        - F edge → `.toggle_fly`; F5 edge → `.save`;
        - `.scroll = cvttsd2si(scroll_accum)`, and subtract that from the accumulator.
2. **`src/game.asm`.**
   - `game_new(seed)`: `world_generate(seed)`, `player_spawn`, default hotbar [STONE, DIRT, GRASS, COBBLE, PLANKS, LOG, LEAVES, GLASS, BRICK], `hotbar_sel = 0`.
   - `game_load(path)`:
     - `r = world_load(path)`; return r if nonzero.
     - Copy header position/yaw/pitch/flying into `player`, with velocity 0.
     - Copy the hotbar, replacing any id that is 0 or ≥ `NUM_BLOCKS` with that slot's default.
     - `sel` = header sel if < 9, else 0. Return 0.
   - `game_save(path)`: fill the header from `player`/hotbar/sel, then return `world_save(path)`.
   - `game_frame(dt)`:
     1. Slot: apply `.slot` if ≥ 0, then `sel = (sel − scroll) mod 9`, kept non-negative.
     2. `.toggle_fly` → `flying ^= 1`, `vy = 0`.
     3. `player_look(look_dx, look_dy)`.
     4. Fixed step: `accum += dt`; while `accum ≥ 1/60` and steps < 5, run `player_step(&frame_input.move)` and subtract. After 5 steps, reset accum to 0.
     5. Target: `raycast(player_eye, player_forward, &game_target, 5.0)` → `game_has_target`.
     6. Break (LMB): fire on `lmb_pressed`, or while `lmb_held` every 0.25 s (timer reset to 0.25 on press; decremented by dt while held; fires and adds 0.25 when ≤ 0; zeroed on release). Requires a target that is not BEDROCK → `world_set(b, AIR)`.
     7. Place (RMB): same repeat rule. Requires a target, p in bounds, `world_get(p) == AIR` and `!player_intersects_block(p)` → `world_set(p, hotbar[sel])`.
     8. Pick (MMB pressed) with a target → `hotbar[sel] = world_get(b)`.
3. **`src/render.asm`.** It owns `atlas` (262144 B `.bss`), `chunk_vbo dd[1024]`, `chunk_count dd[1024]` and `tex_id`.
   - `render_init()`:
     1. Texture: `texgen_build(atlas)`, `glGenTextures(1, &tex_id)`, bind, `glPixelStorei(UNPACK_ALIGNMENT, 1)`, `glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 256, 256, 0, GL_RGBA, GL_UNSIGNED_BYTE, atlas)`, NEAREST min/mag, CLAMP_TO_EDGE wrap.
     2. Texture matrix: `GL_TEXTURE` mode, `glLoadIdentity`, `glScalef(1/4096, 1/4096, 1)`, back to MODELVIEW. This one matrix serves world and HUD alike: all texture coordinates everywhere are 1/16-px units.
     3. `glGenBuffers(1024, chunk_vbo)`.
     4. Fog: `glFogi(FOG_MODE, LINEAR)`, start 80.0, end 128.0, colour {0.62, 0.80, 1.0, 1.0}.
     5. `glAlphaFunc(GL_GREATER, 0.5)`.
   - `render_update_chunks()`:
     - For each chunk with `chunk_dirty` set: `n = mesh_chunk(cx, cy, cz, mesh_scratch)`.
     - If n > 0: `glBindBuffer(ARRAY_BUFFER, vbo)` and `glBufferData(ARRAY_BUFFER, n*16, mesh_scratch, STATIC_DRAW)`.
     - `chunk_count = n`, dirty = 0. At the end, bind buffer 0.
     - The first call meshes all 1024 chunks; that is expected.
   - `render_frame(w, h)` — world pass:
     1. `glViewport`, then clear colour (0.62, 0.80, 1.0, 1) with colour and depth bits.
     2. Projection: `glFrustum(−hh·a, hh·a, −hh, hh, 0.05, 300.0)` in doubles, with `hh = 0.035010377` (0.05·tan 35°, a 70° vertical FOV) and `a = w/h`.
     3. Modelview: identity, `glRotatef(pitch,1,0,0)`, `glRotatef(yaw,0,1,0)`, `glTranslatef(−eye)`.
     4. Enable DEPTH_TEST, CULL_FACE, TEXTURE_2D (bound atlas), ALPHA_TEST and FOG; disable BLEND.
     5. Enable the vertex, texture-coordinate and colour client states.
     6. For each chunk with count > 0 whose horizontal distance² from the eye to its centre `(cx*16+8, cz*16+8)` is ≤ 19600 (140²): `glBindBuffer`, `glVertexPointer(3, GL_SHORT, 16, 0)`, `glTexCoordPointer(2, GL_SHORT, 16, 8)`, `glColorPointer(4, GL_UNSIGNED_BYTE, 16, 12)`, `glDrawArrays(GL_QUADS, 0, count)`.
     7. Disable the client states and bind buffer 0.
   - `render_frame` — target outline: if `game_has_target`, disable TEXTURE_2D and ALPHA_TEST, `glColor4f(0,0,0,1)`, `glLineWidth(2)`, then `GL_LINES` for the 12 edges of the box `[b−0.002, b+1.002]` via `glVertex3f`.
   - `render_frame` — HUD:
     1. Disable DEPTH_TEST, CULL_FACE and FOG. Projection `glOrtho(0, w, h, 0, −1, 1)`; modelview identity.
     2. Hotbar geometry: `x0 = (w − 396)/2`, `y0 = h − 52`.
     3. Background: BLEND on with SRC_ALPHA / ONE_MINUS_SRC_ALPHA, texture off, `glColor4f(0,0,0,0.45)`, a quad from (x0−2, y0−2) of size 400×48 via `glVertex2i`.
     4. Icons: texture and ALPHA_TEST on, colour 1,1,1,1. For slot i, draw the side tile of `hotbar[i]` as a 32×32 quad at (x0+44i+6, y0+6) with `glTexCoord2i` (u0..u1, v0..v1 as in the mesher).
     5. Selection frame: texture off, white, line width 2, `GL_LINE_LOOP` (x0+44·sel+1, y0+1) – (x0+44·sel+43, y0+43).
     6. Crosshair: `glBlendFunc(GL_ONE_MINUS_DST_COLOR, GL_ZERO)`, white, quads (cx−10, cy−1, 20×2), (cx−1, cy−10, 2×9) and (cx−1, cy+1, 2×9), with cx = w/2 and cy = h/2. The vertical bar is split so the centre isn't inverted twice.
     7. Restore the SRC_ALPHA blend and disable BLEND.
4. **Extend `main`** (the order is load-bearing: world errors surface before any window opens).
   1. Load or create the world:
      - `r = game_load(path)`;
      - r = 1 → `game_new(seed)`, where the seed is the `--seed` value or the low 32 bits of `rdtsc`;
      - r = 2 → print `assemblycraft: <path> is not a valid AssemblyCraft world\n` to stderr and return 1;
      - r = 3 → print `assemblycraft: cannot read <path>\n` and return 1.
      - `--seed` is ignored when the file exists.
   2. `glfwInit()` (failure → `assemblycraft: glfwInit failed\n`, return 1).
   3. Window hints: `glfwWindowHint(DEPTH_BITS, 24)`, `glfwWindowHintString(WAYLAND_APP_ID, "assemblycraft")`, `glfwWindowHintString(X11_CLASS_NAME, "assemblycraft")`.
   4. `glfwCreateWindow(1280, 720, "AssemblyCraft", 0, 0)` (NULL → `assemblycraft: cannot create window\n`, terminate, return 1). Then `glfwMakeContextCurrent`, `glfwSwapInterval(1)`, `render_init`, `input_init`.
   5. Loop while `!glfwWindowShouldClose`:
      1. `glfwPollEvents`.
      2. `dt = now − last` from `glfwGetTime` (double), clamped to ≤ 0.25.
      3. `input_poll`.
      4. If `.save`, call `game_save` (failure → `assemblycraft: failed to save world to <path>\n`, keep running).
      5. `game_frame(dt as float)`, then `render_update_chunks`.
      6. `glfwGetFramebufferSize`; call `render_frame` only if w > 0 && h > 0.
      7. `glfwSwapBuffers`.
      8. Every ≥ 0.5 s, set the window title to `AssemblyCraft | <fps> FPS | <x> <y> <z> | <block name>` (+ ` | fly` when flying), built with `str_append`/`i32_to_str`. fps = `cvtsd2si(frames/elapsed)`; coordinates = `floor_i` of the player position; the name comes from `block_names[hotbar[sel]]`.
   6. After the loop: `game_save` (failure → the same message and exit code 1), `glfwDestroyWindow`, `glfwTerminate`, return 0.
5. **Commit** `step 3: playable classic creative` after **Verification** passes.

## Critical files & anchors

- `src/common.inc`: the structs and constants every module and test is written against. A layout change after step 1 breaks parallel work, so freeze it in step 1.
- `src/world.asm` `.bss` order: `world_header` must be immediately followed by `blocks` (plus slack). Save/load does single-buffer I/O over that range.
- `src/mesher.asm` corner table plus the AO rule: winding and culling correctness hinge on the exact BL/BR/TR/TL order listed in worker B.
- `src/player.asm` `move_axis`: the leading-slab collision is only valid while per-step displacement is < 1 block. Keep the terminal-velocity clamp and the 1/60 s fixed step.

## Verification

All commands run from the repo root.

1. **Unit-level.** `make && make test` → 17 `ok` lines (`world_bounds`, `world_set_marks_dirty`, `world_save_load`, `worldgen_deterministic`, `worldgen_shape`, `mesh_single_block`, `mesh_adjacent_opaque`, `mesh_adjacent_leaves`, `mesh_adjacent_glass`, `mesh_chunk_boundary`, `raycast_hit_forward`, `raycast_miss_beyond_reach`, `raycast_hit_from_above`, `physics_land_on_floor`, `physics_wall_blocks`, `physics_jump_clears_one_block`, `player_intersects_block`) and `selftest: 17 passed, 0 failed`, exit 0. Run it after step 1 (3 tests), after each step-2 worker merges, and after step 3.
2. **CLI paths (host, no window).**
   - `./build/assemblycraft --bogus; echo $?` → usage on stderr, `2`.
   - `./build/assemblycraft --help; echo $?` → usage, `0`.
   - `printf garbage > /tmp/ac-bad.acw; ./build/assemblycraft --world /tmp/ac-bad.acw; echo $?` → `assemblycraft: /tmp/ac-bad.acw is not a valid AssemblyCraft world`, `1`, and no window opens.
3. **Visual and interaction, in an omabox desktop.** Follow `skill://omabox`; never launch the GUI on the user's session.
   1. `omabox up`, then `omabox run -d --wait -- ./build/assemblycraft --world /home/sbx/ac.acw --seed 42`.
   2. `omabox shot --window assemblycraft` → Read the PNG. Expect:
      - a sky-blue background, fog fading the far terrain;
      - textured grass/dirt/stone terrain with visible darkening in corners (AO);
      - trees with see-through leaves;
      - a centred inverted crosshair and a black outline on the targeted ground block (spawn pitch is 30°);
      - the 9-icon hotbar with slot 1 framed.
   3. `omabox keys --window assemblycraft --wait 3` → the shot shows the frame on slot 3.
   4. `omabox click --window assemblycraft <centre x> <centre y>` (centre from the shot) → the shot shows the targeted block removed. Then `omabox keys --window assemblycraft --wait 8` (Glass), then right-click at the centre (button argument per `omabox help click`) → a Glass block appears in the hole.
   5. `omabox hyprctl dispatch closewindow class:assemblycraft` (if that dispatcher is refused, use `omabox keys --window assemblycraft super+w`, Omarchy's close binding) → the process exits, and `stat -c %s "$(omabox path --home)/ac.acw"` prints `4194352`.
   6. Relaunch the step-3.1 command (the player resumes at the saved position and view) → the shot shows the same view with the Glass block from step 3.4 and slot 8 framed, proving save and load.
   7. `omabox keys --window assemblycraft down:w`, then `omabox wait change --window assemblycraft`, then `omabox keys --window assemblycraft up:w` → the view moved, and the XYZ in the title changed (`omabox windows` or a shot).
   8. `omabox keys --window assemblycraft --wait f`, then `down:space` / `up:space` → the camera rises, and the title shows `| fly`.
   9. Mouse look: `omabox drag --window assemblycraft 640 360 840 360` → the view yaws. If the box's virtual pointer produces no relative motion (the view is unchanged), report mouse look as "not testable in the box; needs a check on the real desktop" rather than claiming it works.
   10. The FPS in the title is ≥ 55 on a GPU-rendered box. Record the number. If the box renders with llvmpipe (`omabox up` says so), only record it.
   11. `omabox down`.

## Assumptions & contingencies

- **User-overridable scope and UX defaults** (chosen to match Minecraft Classic):
  - 256×64×256 world; no water, caves, ores or sunlight propagation (face shading + AO only);
  - an 11-block set; Sand is obtainable only via pick-block;
  - F toggles fly;
  - Esc only releases the mouse; closing the window saves and quits;
  - the world file defaults to `./world.acw`;
  - a new world's seed is random unless `--seed` is given.
- **No GL context in the box.** If the Wayland window comes up black or `glfwCreateWindow` fails there, run `omabox log apps --grep -i egl` first. If the box is on NVIDIA and EGL fails, start a box on the Intel node: `OMABOX_RENDER_NODE=/dev/dri/renderD128 omabox up --new` (`omabox config gpu` lists the nodes), then repeat Verification 3 there.
- **Linker warnings.** If `gcc -no-pie` warns about an executable stack, a file is missing the `common.inc` include. Fix the include; do not add linker flags.
- **A selftest constant fails while the module looks right.** If a step-2 test's expected constant (e.g. 17.69 ≤ x ≤ 17.70) fails but the module matches this spec, first re-derive the expectation from the spec's formulas with `gdb` (`break test_physics_wall_blocks`). Change the test only if the spec arithmetic proves the expectation wrong; never loosen it to pass.

## Implementation notes (deviations found during verification)

- **Sticky keys and buttons.** `input_init` also enables `GLFW_STICKY_KEYS` (0x33002) and `GLFW_STICKY_MOUSE_BUTTONS` (0x33003). Without them, a key tapped and released between two polls reads as never pressed, so the edge detection drops it (observed in the box: a quick tap of `3` did not select slot 3).
- **The recapture click does nothing.** After the left click that recaptures the mouse, `lmb_held` and `lmb_pressed` stay 0 until that button is released. Otherwise the held-repeat timer (zeroed while uncaptured) would break a block on the very next frame.
