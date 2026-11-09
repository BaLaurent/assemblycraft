# AssemblyCraft 0.10.3 — chip sound overhaul (SFX only, modern chiptune)

## Context

The user says the sound design "sounds like a bad Amiga roleplay" and wants it to sound good while staying chiptune. The game has no music. The scope is the 60 procedural SFX (`src/sfx.asm`) and the mixer (`src/audio.asm`); music stays in the 0.12 roadmap. The user chose **SFX overhaul only** in a **modern chiptune** style: NES/C64 waveforms (pulse duties, 2A03 triangle, LFSR noise, tracker arpeggios), band-limited and clean, with stereo panning, a light echo and a soft limiter.

Measured defects in the current pool (offline render of `sfx_build`, HEAD `2fbea0a`):
- 16 sounds start at 40–100 % of their peak on sample 0 (onset clicks); QUEST, LEGENDARY and LOOT_RARE end at 9–15 % of peak (tail clicks: exponential decay cut off at `dur`).
- Noise is white xorshift through one one-pole filter. FUSE, SMOKE, KNIVES, RIFLE, DIG_GLASS, FREEZE and TOOL_BREAK carry 63–86 % of their energy above 8 kHz (hiss, not chip crunch).
- Square and saw oscillators are naive, so they alias: CLICK is 40 % inharmonic, and a 3.5 kHz square is 6.5 % aliased. There are only 50 % squares, linear-Hz sweeps and stacked-square "chords".
- Every play is bit-identical (footsteps machine-gun), output is mono with no room, and the sum is hard-clamped.

End state: a chip instrument renderer, a stereo mixer with per-play pitch jitter, per-sound instance caps, an echo send and a limiter, all 60 sounds redesigned, and the 5 jingles recomposed as one leitmotif family. Selftests pin the defects; the user's ear approves an A/B preview pack before the commit.

## Approach

Steps 1 → 2 → 3 → 4 → 5 → 6 → 7 in order. Steps 3 and 4 touch disjoint files (`sfx.asm` and `audio.asm`) and may run in parallel once step 2 lands. Every float in NASM data must be written with a decimal point (`81.0`, not `81`).

### 1. Design doc (project convention)
Copy this plan verbatim to `docs/superpowers/specs/2026-11-09-assemblycraft-chip-sound-design.md`.

### 2. Shared contracts: `common.inc` + `mathf.asm`
- **`mathf.asm`**: add `global exp2_ss`. `exp2_ss(xmm0 x) -> xmm0 2^x`, valid for any finite x, leaves the x87 stack empty: `fld x; fld st0; frndint; fsub st1, st0; fxch; f2xm1; fld1; faddp; fscale; fstp st1`, then store/load through `[rsp]` like `sincos_deg`. There is no equivalent today (sfx.asm's inline `f2xm1` only handles |x| ≤ 1). It is used by sfx.asm (pitch, decay factor, filter coefficients) and audio.asm (jitter).
- **`common.inc`**: replace `struc SFXLAYER` (line ~1410) with the 22-field layout below (all `resd 1`; ints marked, the rest floats). Order is load-bearing for the `LEND` macro:
  `.sound`(int) `.wave`(int) `.start` `.dur` `.amp` `.note0` `.note1` `.glide` `.arp1` `.arp2` `.arp_hz` `.vib_depth` `.vib_hz` `.vib_delay` `.duty0` `.duty1` `.attack` `.decay` `.sustain` `.release` `.lp_hz` `.hp_hz` (88 bytes).
- Add the wave ids next to the `SND_*` block: `%define W_PULSE 0`, `W_TRI 1`, `W_SAW 2`, `W_NOISE 3`, `W_NOISE93 4`.
- Add `struc SFXINFO`: `.peak resw 1` (target peak, int16 units), `.jitter resw 1` (± cents, unsigned), `.cap resb 1` (max simultaneous voices of this sound), `.send resb 1` (echo send 0..255), `.pad resw 1` (8 bytes).
- Move the voice struct here as `struc VOICE`: `.pos resq 1` (32.32 position from the sound's start), `.step resq 1` (32.32 rate, `1<<32` = as rendered), `.ptr resq 1` (first int16 of the sound in `sfx_pool`), `.len resd 1` (samples, 0 = free), `.snd resd 1`, `.gl resd 1`, `.gr resd 1`, `.send resd 1` (floats), `.serial resd 1` (48 bytes).
- Add `%define SOUND_MAX_SAMPLES 88200` (2.0 s) and `%define POOL_SAMPLES 1572864` (35.6 s; the new set is ~25 s and today's pool is already 97 % full). Delete `%define POOL_SAMPLES` from `sfx.asm`; the test needs the shared value.

### 3. Chip renderer and the 60 sounds: `src/sfx.asm` (clean cutover; the old `LAYER` table, `W_SQUARE`, `E_EXP`/`E_LIN`, `c_gain` go)
- Size `sfx_acc` to `resd SOUND_MAX_SAMPLES`. `sfx_build` keeps today's length rule (`ceil(max(start+dur)·44100 − 0.01)`), additionally clamps each sound to `SOUND_MAX_SAMPLES`, and keeps today's pool-end clamp.
- **Layer DSL** (replaces `%macro LAYER 14`). Defaults are set by `LAYER`; modifiers override them; `LEND` emits the 22 `dd` in SFXLAYER order using `%define`d single-line macros:
  - `LAYER sound, wave, start, dur, amp, note0, note1, glide`: defaults arp `0.0,0.0,0.0`, vib `0.0,0.0,0.0`, duty `0.5,0.5`, env `0.0015,0.0,1.0,0.004`, filt `0.0,0.0`.
  - `ARP a1, a2, hz` · `VIB depth, hz, delay` · `DUTY d0, d1` · `ENV attack, decay, sustain, release` · `FILT lp_hz, hp_hz` · `LEND`.
  - Layers stay grouped by sound id in id order (the build loop relies on it).
- **`sfx_info`** (`global`): `NUM_SOUNDS` rows via `%macro SINFO 4` (`dw peak, jitter` / `db cap, send, 0, 0`), in id order, followed by `%if $ - sfx_info != NUM_SOUNDS * SFXINFO_size` / `%error "sfx_info must hold NUM_SOUNDS rows"` / `%endif`.
- **`render_layer` semantics** (per layer; `t` = seconds since `.start`; the layer covers `[start, start+dur)`):
  - Engine floors: `attack = max(attack, 0.0015)`, `release = max(release, 0.004)`.
  - **Pitch, recomputed every 32 samples** (and at sample 0), held between ticks: `n = glide > 0 ? note0 + (note1−note0)·min(1, t/glide) : note0`. Add `[0, arp1, arp2][floor(t·arp_hz) mod k]` when `arp_hz > 0`, with `k = 3` if `arp2 ≠ 0` else 2. Add `vib_depth·tri(vib_hz·(t − vib_delay) + 0.25)` when `vib_depth > 0` and `t ≥ vib_delay`, where `tri(x) = 1 − 4·|frac(x) − 0.5|` (reuse today's tri code; the +0.25 makes it start at 0). Then `f = 440·exp2_ss((n − 69)/12)`, times 16 for both noise waves (the noise clock), and `dt = f/44100`. Pulse duty for the tick: `d = clamp(duty0 + (duty1−duty0)·t/dur, 0.05, 0.95)`.
  - **Oscillators** (phase in [0,1), starts at 0; `blep(p, dt)`: `p<dt → x=p/dt; 2x−x²−1`; `p>1−dt → x=(p−1)/dt; x²+2x+1`; else 0):
    - `W_PULSE`: `(p<d ? 1 : −1) + blep(p,dt) − blep(frac(p − d + 1), dt) − (2d − 1)`. The last term removes the duty's DC offset.
    - `W_TRI`: 2A03 32-step: `k = floor(p·32)`, `v = k<16 ? 15−k : k−16`, `y = v·(2/15) − 1`.
    - `W_SAW`: `2p − 1 − blep(p, dt)`.
    - `W_NOISE` / `W_NOISE93`: 15-bit LFSR initialised to `(next sfx_rng & 0x7FFF) | 1`; `acc += dt`; while `acc ≥ 1` (at most 8 steps per sample, excess dropped): `acc −= 1`, `bit = (r ^ (r >> tap)) & 1` with tap 1 (NOISE) or 6 (NOISE93), `r = (r >> 1) | (bit << 14)`. Output `(r & 1) ? −1 : +1`.
  - **Filters** (fixed per layer): `hp_hz > 0` → `h += ah·(x − h); x = x − h`; then `lp_hz > 0` → `y += al·(x − y); x = y`. The coefficient is `a = 1 − exp2_ss(−fc · 2.0555e-4)` (= 1 − e^(−2π·fc/44100)).
  - **Envelope** `A·D·R`: `A = min(1, t/attack)`. `D = decay > 0 ? sustain + (1−sustain)·v : 1`, with `v` starting at 1 when `t ≥ attack` and multiplied each sample by `k = exp2_ss(−1/(decay·44100))`. `R = min(1, (dur − t)/release)`. Sample = `osc · env · amp` added into `sfx_acc`.
- **Per-sound normalisation** in `sfx_build` before packing: take the peak |acc| over the sound. If the peak > 0, scale by `sfx_info[id].peak / peak`. Pack with `cvtss2si`, clamped to ±32767. Layer `amp` is therefore relative within a sound only.
- **Sound data**: write every row of the two tables under "Sound recipes" below. Recipe notation → DSL: `P50/P25/P12` = `W_PULSE` with `DUTY 0.5/0.25/0.125` both ends (unless `duty a→b` is given); `T` = `W_TRI`; `S` = `W_SAW`; `N` = `W_NOISE`; `N93` = `W_NOISE93`. `n0→n1/g` → note0, note1, glide; a single `n` → note0 = note1 = n, glide 0. `@s` → start (default 0). `d` → dur. `×a` → amp (default 1). `env a/k/s/r` → ENV. `st` = `env .0015/0/1/.012`. `arp +a1+a2@hz` → ARP. `vib depth@hz+delay` → VIB. `lp`/`hp` → FILT. Noise "notes" set the clock = 7040·2^((n−69)/12) Hz: n100 ≈ 42 kHz (bright white), n84 ≈ 17 kHz, n72 ≈ 8.4 kHz, n60 ≈ 4.2 kHz (dark crunch).

### 4. Stereo chip mixer: `src/audio.asm`
- **Stream**: `pa_ss` channels byte `2`; `pa_attr` tlength `10584` (60 ms stereo S16). `mix_buf` becomes `resw 2*MAX_FRAMES`, interleaved L,R. Float accumulators `accL`, `accR`, `accE` (`resd MAX_FRAMES` each) replace `mix_acc`. Delete the local `struc VOICE` (it now lives in common.inc).
- **Globals**: add `audio_mix`, `audio_reset`, `audio_enabled` (tests and the preview harness need them). Externs add `sfx_info`, `exp2_ss`, `sincos_deg`, `player`.
- **`audio_reset()`**: zeroes the voices, both echo lines, the echo filter states and `audio_serial`; sets the limiter gain `lim_g = 1.0` and the private RNG `audio_rng_state = 0xA5A5F00D`. `audio_init` calls it in place of its inline `rep stosd`. The private xorshift32 `audio_rng` is a leaf copy of `rng_next`'s algorithm on `audio_rng_state`. Never call the game's `rng_next` from audio (gameplay determinism).
- **`audio_mix(rdi int16 *out, esi frames ≤ MAX_FRAMES)`**, pure, no PulseAudio:
  1. Zero `accL/accR/accE[0..frames)`.
  2. For each voice with `len ≠ 0`, per frame: `idx = pos>>32`; if `idx ≥ len` → `len = 0`, stop this voice. `a = ptr[idx]`, `b = idx+1 < len ? ptr[idx+1] : 0`, `s = a + (b−a)·(low32(pos)·2^-32)`. `accL += s·gl`, `accR += s·gr`, `accE += s·send`, `pos += step`.
  3. Echo, per frame: `yl = echoL[il]`, `yr = echoR[ir]`; `fl += 0.45·(yl − fl)`, `fr += 0.45·(yr − fr)`; `echoL[il] = accE + 0.35·fl`, `echoR[ir] = accE + 0.35·fr`; advance and wrap `il`/`ir` (lengths `ECHO_L 7497` = 170 ms, `ECHO_R 8379` = 190 ms; float rings in .bss). Then `L = (accL + fl)·m`, `R = (accR + fr)·m`, with `m = settings.volume / 100.0`.
  4. Limiter, per frame: `pk = max(|L|,|R|)`; if `pk·lim_g > 29205.0` → `lim_g = 29205.0/pk`. Output `L·lim_g`, `R·lim_g`, clamped ±32767 and rounded with `cvtss2si`. Then `lim_g += (1 − lim_g)·0.00023` (~100 ms release).
- **`audio_update`**: unchanged frame/carry logic, then `audio_mix(mix_buf, frames)` and `pa_simple_write(bytes = frames·4)`.
- `audio_play(edi snd, xmm0 vol)` and `audio_play_at(edi snd, xmm0 x, xmm1 y, xmm2 z, xmm3 vol)` keep their signatures, so none of the ~50 call sites change.
- **`start_voice(edi snd, xmm0 vol, xmm1 pan)`** (internal; `audio_play` passes pan 0):
  - `vol ≤ 0` → return.
  - Voice choice: if the count of voices with `len≠0 && snd==edi` ≥ `sfx_info[snd].cap` → reuse the one of those with the smallest `serial`. Else a free voice; else the voice with the least remaining (`len − pos>>32`, today's policy). Stealing cuts the victim; that's accepted, because the same-sound retrigger masks it.
  - `step`: `J = sfx_info[snd].jitter`; `J == 0` → `1<<32` (no RNG draw); else `c = (audio_rng() mod (2J+1)) − J`, `step = cvtss2si64(exp2_ss(c/1200)·4294967296.0)`.
  - `gl = vol·min(1, 1−pan)`, `gr = vol·min(1, 1+pan)`, `send = vol·sfx_info[snd].send/255`; `pos = 0`; `ptr = sfx_pool + 2·sfx_table[snd].offset`; `len = sfx_table[snd].length`; `serial = audio_serial++`.
- **`audio_play_at`**: keep today's distance gain `max(0, 1 − d/16)·vol` (d from `player_eye`). Pan: `dx = x − eye.x`, `dz = z − eye.z`, `h = sqrt(dx²+dz²)`; `h < 0.001` → pan 0; else `(c, s) = sincos_deg(player.BODY.yaw)` and `pan = 0.6·(dx·cos + dz·sin)/h`. The right vector is `(cos yaw, sin yaw)`, per `player.asm`'s `strafe * (cos, sin)` with strafe = RIGHT − LEFT. A gain that comes to 0 starts nothing (as today).

### 5. Selftests: new `src/test_audio.asm` + registration in `src/selftest.asm`
Register all three with `extern` + `TEST` + `TESTNAME`, appended at the **end** of the existing lists so earlier tests' shared state (game RNG, world) is untouched. Copy the per-file `SETF` macro (`mov dword %1, __float32__(%2)`) as the other test files do. Return eax 0 = pass. Each mixer test first calls `sfx_build`, sets `audio_enabled = 1` and `settings.volume = 100`, and calls `audio_reset` before every sub-case; at the end it restores the previous volume, `audio_enabled = 0`, and calls `audio_reset` again.
- **`test_sfx_clean_edges`**: call `sfx_build`. For every id: `0 < len ≤ SOUND_MAX_SAMPLES`, peak ≥ 1000, `|x[0]| ≤ peak/64`, `|x[len−1]| ≤ peak/32`; and the sum of lengths ≤ `POOL_SAMPLES`. The check lives in a local `edge_ok(rdi int16*, esi len) -> eax 0 ok`. Negative controls: `edge_ok` must reject a 64-sample .rodata buffer of constant 20000, and a 64-sample buffer ramping 0→20000 (tail click).
- **`test_audio_pan`**: player at x 0.5, y 10.0, z 0.5. Positional `SND_CLICK` (jitter 0, send 0) at eye height, vol 1. Mix 1102 frames each time and compare Σ|L| and Σ|R|.
  - yaw 0, source at x+4 → ΣL/ΣR ∈ [0.37, 0.43].
  - source at x−4 → ΣR/ΣL ∈ [0.37, 0.43].
  - source at z−4 (in front) → |ΣL−ΣR| ≤ 1 % of ΣL.
  - yaw 90, source at z+4 → ΣL/ΣR ∈ [0.37, 0.43] (catches a z-sign error).
- **`test_audio_caps_jitter_limiter`**:
  - `audio_play(SND_STEP_STONE)` ×4 → exactly 2 voices hold that id. Their `.step` values differ, and both lie in `[2^32·2^(−300/1200) − 1024, 2^32·2^(300/1200) + 1024]` (float-precision slack). If the fixed seed happens to make the two draws equal, change `0xA5A5F00D` to `0xA5A5F00F`; do not loosen the check.
  - `audio_play(SND_LEVELUP)` → its `.step == 1<<32`.
  - Game RNG untouched: `rng_seed(1234)`, read `rng_next` → v1; `rng_seed(1234)`, `audio_play(SND_STEP_STONE)`, `rng_next` → v2; require `v1 == v2`.
  - Limiter: after `audio_reset`, start SND_EXPLODE ×3, SHOTGUN ×2, MUSKET ×2, PISTOL ×3, SLAM, BOSS_ROAR, LAUNCHER ×2, HEAVY, CRIT (16 voices, all within caps), vol 1. Mix 2048 frames: every |sample| ≤ 29206, and max |sample| ≥ 20000 (control: the scene really drives the limiter). Do not check for runs of equal samples: stepped triangles and flat pulse tops legitimately repeat values.

### 6. Preview harness, measurements and the user's listening gate (scratch in `/tmp/acsound`, never in the repo)
- Old pool: `git show 2fbea0a:src/sfx.asm > /tmp/acsound/old/sfx.asm` and `git show 2fbea0a:src/common.inc > /tmp/acsound/old/common.inc`; `nasm -f elf64 -I/tmp/acsound/old/ -o old/sfx.o old/sfx.asm`; link with a tiny C `dump_old.c` (`sfx_build()`, then `fwrite` `sfx_pool` (1048576 int16) and `sfx_table` (120 u32) to `old/pool.bin`, `old/table.bin`).
- New: assemble `src/sfx.asm`, `src/mathf.asm` and `src/audio.asm` (`-Isrc/`) into `/tmp/acsound/`; link with `harness.c`:
  ```c
  #include <stdio.h>
  #include <stdint.h>
  extern void sfx_build(void); extern uint32_t sfx_table[]; extern int16_t sfx_pool[];
  extern void audio_reset(void); extern void audio_mix(int16_t*, int);
  extern void audio_play(int, float); extern void audio_play_at(int, float, float, float, float);
  extern int audio_enabled;
  int settings[64] = {70, 100, 8, 100};          /* SETTINGS.volume at +12 */
  float player[17];                              /* BODY: x y z vx vy vz yaw(+24) */
  void player_eye(float *o){ o[0]=player[0]; o[1]=player[1]+1.62f; o[2]=player[2]; }
  void *pa_simple_new(){return 0;} int pa_simple_write(){return 0;} void pa_simple_free(){}
  ```
  `main` calls `sfx_build`, then dumps `pool.bin`/`table.bin` (`POOL_SAMPLES` int16, 120 u32). It sets `audio_enabled = 1` and then renders each scene: `audio_reset`; loop in 441-frame blocks, starting the events whose time ≤ block start; append `audio_mix` output to `scene_<name>.raw`; 2 s tail. Positional events use the player at (0, 0, 0) yaw 0, source y = 1.62. Scenes (time s: sound [x,z]; vol 0.6 for steps/digs, else 1):
  - walk: STEP_STONE every .35 s ×12, then STEP_WOOD ×6, STEP_SOFT ×6.
  - dig: DIG_STONE/DIG_WOOD/DIG_SOFT ×6 each every .25 s, then DIG_GLASS ×3.
  - mobs_pan: 0 ZOMBIE_SAY [−5,0]; 1.2 ZOMBIE_SAY [5,0]; 2.4 PIG_SAY [−3,−3]; 3.2 SKELETON_SAY [3,−3]; 4.0 SPIDER_SAY [0,−4]; 4.8 CHICKEN_SAY [4,1]; 5.4 VILLAGER [−4,1].
  - fight: 0 SWING, .15 ZOMBIE_HURT, .6 SWING, .75 CRIT, 1.4 PARRY, 2.0 BLOCK, 2.6 DODGE, 3.2 HEAVY, 3.8 KNIVES, 4.5 WARCRY, 5.4 WHIRL, 6.2 HURT.
  - guns: 0 DRY_FIRE, .4 RELOAD, 1.0 PISTOL, 1.25 PISTOL, 2.0 RIFLE, 3.0 SHOTGUN, 4.2 MUSKET, 5.6 LAUNCHER, 6.3 EXPLODE.
  - magic: 0 SPELL, .6 FIREBALL, 1.6 BLINK, 2.4 FREEZE, 3.2 SMOKE, 4.2 BOSS_ROAR, 6.0 SLAM.
  - jingles: 0 COIN, .5 COIN, 1.5 LOOT_RARE, 3.0 QUEST, 4.5 LEVELUP, 6.5 LEGENDARY.
  - misc: 0/.15/.3 CLICK, 1.0/1.2 POP, 1.8/2.0 EAT, 2.6 BURP, 3.2 DRINK, 4.0 DOOR_OPEN, 4.8 DOOR_CLOSE, 5.5 TOOL_BREAK, 6.2 BOW, 6.5 ARROW_HIT, 7.0 FUSE, 8.8 CREEPER_HURT, 9.4 PIG_HURT, 10.0 SKELETON_HURT, 10.6 SPIDER_HURT, 11.2 CHICKEN_HURT.
  - stress: the 16-voice set from `test_audio_caps_jitter_limiter`, all at t 0.
- `report.py` (run with `/usr/bin/python3`; the pyenv shim times out; numpy is available):
  - **Per-sound pairs** `wav/NN_NAME_old.wav` / `_new.wav`. Mono 44.1 kHz; scale the louder one down to equal RMS; 20 ms fades.
  - **Scene pairs** `wav/scene_X_new.wav` (stereo) and `scene_X_old.wav`. The old one sums the old pool at the same event times: mono, `vol·256` truncated, `>>8`, same distance gain, hard clamp, duplicated to stereo, which reproduces today's mixer. Both are RMS-matched.
  - **Printed table** per new sound: length ms, peak dBFS, `|x0|/pk`, `|x_end|/pk`, share of energy above 8 kHz.
  - **COIN check**: inharmonic share of COIN between 0.12 and 0.30 s against D6 = 1174.66 Hz harmonics (Hann window; bins within max(25 Hz, 0.6 %) of k·f0 count as harmonic).
  - **Scenes**: stress peak; mobs_pan L/R RMS over 0–1.0 s and 1.2–2.2 s.
- **Listening gate**: when every number in Verification passes, `ask` the user to listen to `/tmp/acsound/wav/` (scenes first, then per-sound pairs; say they are RMS-matched). Options: "Approve", "Change named sounds" (they type which and what's wrong), "Echo too much/too little". Iterate by changing only `sfx_info` values or recipe rows for the named sounds (or the echo constants), re-render and re-ask. Do not commit sound changes before "Approve".

### 7. Version + live smoke + commit
- Bump `"AssemblyCraft 0.10.2"` → `0.10.3` in `src/menus.asm` (`t_version`, ~line 111) and `src/hud.asm` (`s_dbg_title`, ~line 65).
- Live smoke per Verification, then commit per wave (`0.10.3 sound: chip renderer and sounds`, `0.10.3 sound: stereo mixer`, `0.10.3 sound: tests`, `0.10.3: version`), following the repo's `0.10.x:` message style.

## Sound recipes

Columns: `id NAME` | `peak` (int16; dBFS in brackets) / `jitter` cents / `cap` / `send` | layers (`;`-separated). Write each layer as one `LAYER … LEND` block.

| id NAME | peak/jit/cap/send | layers |
|---|---|---|
| 0 CLICK | 7336 (−13)/0/1/0 | P12 96 d.025 env .0015/.006/0/.008; T 72 d.02 ×.5 env .0015/.005/0/.006 |
| 1 DIG_STONE | 10362 (−10)/250/3/0 | N 92→84/.08 d.16 env .0015/.035/0/.03 hp 600; N93 80 d.06 ×.35 env .0015/.015/0/.02 hp 1500; T 45→33/.04 d.06 ×.5 env .0015/.02/0/.02 |
| 2 DIG_WOOD | 10362 (−10)/250/3/0 | T 55→43/.05 d.12 env .0015/.04/0/.03; N 78 d.08 ×.5 env .0015/.02/0/.02 lp 3000 hp 300; P50 67→60/.03 d.05 ×.25 env .0015/.015/0/.015 lp 1800 |
| 3 DIG_SOFT | 9235 (−11)/300/3/0 | N 70→62/.10 d.16 env .004/.05/0/.04 lp 2200 hp 150; N 84 d.05 ×.25 env .0015/.015/0/.015 hp 2500 |
| 4 DIG_GLASS | 10362 (−10)/150/2/40 | N93 94 d.12 ×.7 env .0015/.03/0/.03 hp 3000; P12 100 d.14 ×.3 env .0015/.04/0/.04; P12 103 @.03 d.12 ×.25 env .0015/.04/0/.04; P12 98 @.06 d.12 ×.2 env .0015/.05/0/.04 |
| 5 STEP_STONE | 6538 (−14)/300/2/0 | N 90→84/.03 d.06 env .0015/.015/0/.02 hp 900; T 48→40/.02 d.04 ×.35 env .0015/.012/0/.012 |
| 6 STEP_WOOD | 6538 (−14)/300/2/0 | T 57→45/.03 d.07 env .0015/.025/0/.02; N 76 d.03 ×.35 env .0015/.008/0/.01 lp 4000 hp 400 |
| 7 STEP_SOFT | 6538 (−14)/350/2/0 | N 66→60/.05 d.08 env .004/.025/0/.03 lp 1800 hp 120 |
| 8 HURT | 14637 (−7)/120/2/20 | P25 76→64/.12 d.22 env .002/.08/0/.05 vib .6@22+0; N 80→70/.10 d.10 ×.4 env .0015/.03/0/.03 hp 500; T 50→38/.06 d.10 ×.6 env .0015/.03/0/.03 |
| 9 EAT | 8231 (−12)/300/2/0 | N 82→76/.05 d.10 env .002/.03/0/.03 lp 4000 hp 600; N93 70 d.05 ×.25 env .0015/.015/0/.015 lp 2500 |
| 10 BURP | 11627 (−9)/150/1/0 | P50 50→45/.25 d.30 env .01/.15/.3/.08 vib .8@28+0 lp 1500 |
| 11 ZOMBIE_SAY | 13045 (−8)/200/2/30 | P12 45→41/.6 d.75 env .06/.4/.4/.15 vib .5@5.5+.1 lp 1400; P25 52→48/.6 d.75 ×.3 env .06/.4/.4/.15 vib .5@5.5+.1 lp 1400; N 60 d.70 ×.18 env .10/.3/.3/.15 lp 900 |
| 12 ZOMBIE_HURT | 14637 (−7)/150/2/20 | P12 52→40/.2 d.28 env .002/.10/0/.06 vib 1@18+0 lp 2000; N 78→66/.10 d.12 ×.5 env .0015/.03/0/.03 hp 400 |
| 13 PIG_SAY | 10362 (−10)/200/2/15 | P25 62→57/.08 d.11 env .004/.05/0/.03 vib .7@32+0 lp 2200; P25 60→55/.08 @.16 d.11 env .004/.05/0/.03 vib .7@32+0 lp 2200 |
| 14 PIG_HURT | 13045 (−8)/150/2/15 | P25 72→60/.18 d.22 env .002/.08/0/.05 vib 1@30+0 lp 3000; N 80 d.05 ×.35 env .0015/.015/0/.015 hp 800 |
| 15 TOOL_BREAK | 13045 (−8)/100/1/40 | N93 88→76/.15 d.22 ×.8 env .0015/.05/0/.05 hp 1200; P12 91→79/.18 d.20 ×.35 env .0015/.06/0/.05; P12 86→74/.18 @.03 d.18 ×.25 env .0015/.06/0/.05 |
| 16 POP | 8231 (−12)/400/2/15 | P25 79→91/.03 d.07 env .0015/.025/0/.02 |
| 17 EXPLODE | 27571 (−1.5)/120/3/70 | N 94→56/.9 d1.20 env .002/.22/0/.30 lp 6000; T 40→26/.35 d.50 ×.8 env .002/.15/0/.10; N93 70→58/.6 d.70 ×.3 env .0015/.18/0/.15 lp 2500 |
| 18 FUSE | 5827 (−15)/0/2/0 | N 96 d1.50 arp −14+0@17 env .05/0/1/.12 lp 9000 hp 3000 |
| 19 BOW | 16423 (−6)/150/3/25 | N 88→70/.06 d.10 ×.6 env .002/.03/0/.03 hp 1500; T 60→43/.08 d.13 ×.9 env .0015/.05/0/.04; P50 67→55/.08 d.10 ×.3 env .0015/.03/0/.03 lp 2000 |
| 20 ARROW_HIT | 13045 (−8)/200/3/15 | T 55→38/.03 d.07 env .0015/.02/0/.02; N 84 d.04 ×.5 env .0015/.01/0/.012 hp 1200; P12 79 d.05 ×.15 env .0015/.015/0/.015 vib 1@40+0 |
| 21 SKELETON_SAY | 10362 (−10)/200/2/25 | N93 90 d.04; N93 93 @.07 d.04; N93 88 @.13 d.04; N93 91 @.20 d.04 — all env .0015/.012/0/.015 hp 1500 |
| 22 SKELETON_HURT | 14637 (−7)/150/2/20 | N93 92→80/.10 d.16 env .0015/.04/0/.04 hp 1200; P12 84→72/.12 d.14 ×.3 env .0015/.04/0/.04; T 55→45/.04 d.06 ×.4 env .0015/.02/0/.02 |
| 23 SPIDER_SAY | 11627 (−9)/200/2/15 | N 86 d.42 env .03/.2/.4/.10 vib 1@9+0 hp 2500; P12 43→41/.4 d.42 ×.35 env .03/.2/.4/.10 vib .5@9+0 lp 900 |
| 24 SPIDER_HURT | 14637 (−7)/150/2/15 | P12 69→57/.15 d.22 env .0015/.07/0/.05 vib 1.5@24+0 lp 2500; N 86 d.08 ×.4 env .0015/.02/0/.02 hp 2000 |
| 25 CREEPER_HURT | 14637 (−7)/150/2/15 | N 84→74/.12 d.20 env .0015/.05/0/.05 hp 900; P25 55→46/.15 d.18 ×.4 env .0015/.06/0/.05 vib .8@20+0 lp 1800 |
| 26 CHICKEN_SAY | 8231 (−12)/200/2/15 | P12 91→94/.04 d.06 env .0015/.02/0/.02; P12 94→88/.06 @.09 d.08 env .0015/.03/0/.025 |
| 27 CHICKEN_HURT | 10362 (−10)/150/2/15 | P12 96→84/.12 d.14 env .0015/.05/0/.04 vib 1@35+0; N 90 d.04 ×.3 env .0015/.01/0/.012 hp 3000 |
| 28 PISTOL | 20675 (−4)/80/3/55 | N 96→80/.10 d.22 env .0015/.04/0/.06 hp 400; T 50→30/.06 d.12 ×.8 env .0015/.04/0/.04; N93 84 d.05 ×.3 env .0015/.012/0/.015 hp 2000 |
| 29 MUSKET | 23198 (−3)/80/2/70 | N 100 d.03 ×.4 env .0015/.008/0/.01 hp 3000; N 92→66/.5 d.85 env .002/.14/0/.25 lp 7000; T 45→26/.2 d.35 ×.9 env .0015/.10/0/.10 |
| 30 SHOTGUN | 26029 (−2)/80/2/65 | N 94→70/.3 d.55 env .0015/.09/0/.15 lp 8000; T 43→26/.15 d.30 env .0015/.08/0/.08; N93 80 d.08 ×.3 env .0015/.02/0/.02 hp 1500 |
| 31 RIFLE | 20675 (−4)/80/3/50 | N 100→88/.05 d.15 env .0015/.02/0/.04 hp 800; T 55→36/.04 d.08 ×.6 env .0015/.025/0/.03; N93 92 d.03 ×.25 env .0015/.008/0/.01 hp 3000; N 80→66/.2 @.02 d.30 ×.3 env .0015/.07/0/.08 lp 4000 |
| 32 LAUNCHER | 20675 (−4)/60/2/55 | T 45→28/.15 d.20 ×.9 env .0015/.06/0/.05; N 92 d.05 ×.4 env .0015/.015/0/.015 hp 2000; N 70→90/.45 d.60 ×.7 env .10/0/1/.12 lp 6000 hp 300; S 40→60/.5 d.55 ×.25 env .08/0/1/.10 lp 1200 |
| 33 RELOAD | 10362 (−10)/60/1/15 | P12 93→88/.02 d.04 ×.6 env .0015/.01/0/.015; N93 92 d.03 env .0015/.008/0/.01 hp 2500; P12 88→84/.02 @.12 d.04 ×.6 env .0015/.01/0/.015; N93 88 @.12 d.03 env .0015/.008/0/.01 hp 2500 |
| 34 DRY_FIRE | 9235 (−11)/60/1/0 | P12 95→90/.02 d.035 ×.6 env .0015/.008/0/.015; N93 94 d.025 env .0015/.006/0/.01 hp 3000 |
| 35 SWING | 11627 (−9)/250/2/0 | N 72→86/.10 d.17 env .04/0/1/.10 lp 5000 hp 600 |
| 36 PARRY | 18427 (−5)/60/2/60 | N93 96 d.04 ×.8 env .0015/.01/0/.012 hp 3000; P12 93 d.45 env .0015/.09/0/.10 vib .15@7+.05; P25 100 d.30 ×.4 env .0015/.05/0/.08; T 57→45/.04 d.06 ×.5 env .0015/.02/0/.02 |
| 37 BLOCK | 18427 (−5)/100/2/25 | T 50→36/.06 d.18 env .0015/.05/0/.05; N 76→64/.08 d.15 ×.8 env .0015/.04/0/.04 lp 2000 hp 120; N93 84 d.03 ×.3 env .0015/.008/0/.01 hp 1500 |
| 38 DODGE | 11627 (−9)/150/1/10 | N 68→80/.12 d.28 env .08/0/1/.15 lp 3500 hp 300 |
| 39 CRIT | 20675 (−4)/80/2/55 | N93 96→84/.08 d.14 ×.7 env .0015/.03/0/.04 hp 1500; T 52→33/.06 d.14 ×.9 env .0015/.04/0/.04; P12 91 d.25 ×.35 arp +5+12@40 env .0015/.07/0/.08 |
| 40 LEVELUP | 16423 (−6)/0/1/90 | jingle table |
| 41 SPELL | 14637 (−7)/100/2/70 | P25 74→98/.18 d.24 duty .5→.125 arp +7+0@30 env .004/0/1/.08; N 90 d.20 ×.15 env .02/0/1/.10 hp 4000 |
| 42 FIREBALL | 18427 (−5)/100/2/60 | N 80→62/.5 d.60 env .04/.25/.3/.15 vib 1.5@11+0 lp 3500 hp 150; T 43→36/.5 d.50 ×.5 env .04/0/1/.15 |
| 43 BLINK | 13045 (−8)/60/1/80 | P12 103→79/.22 d.26 arp +12+0@45 env .002/0/1/.10; P25 96→72/.22 @.04 d.24 ×.4 arp +12+0@45 env .002/0/1/.10; N 94 d.10 ×.3 env .0015/.03/0/.03 hp 4000 |
| 44 WARCRY | 18427 (−5)/60/1/60 | S 47→45/.6 d.70 env .05/.4/.5/.20 vib .4@6+.1 lp 2200; P25 54→52/.6 d.70 ×.5 env .05/.4/.5/.20 vib .4@6+.1 lp 2200; N 70 d.60 ×.3 env .05/.3/.3/.20 lp 1500 hp 200 |
| 45 WHIRL | 14637 (−7)/100/1/25 | N 66→84/.2 d.28 env .08/0/1/.15 lp 5000 hp 400; N 70→88/.2 @.22 d.30 env .08/0/1/.15 lp 5000 hp 400 |
| 46 SMOKE | 13045 (−8)/100/1/40 | T 43→34/.10 d.15 ×.6 env .0015/.04/0/.04; N 86→70/.6 d.70 env .01/.2/.2/.25 lp 6000 hp 300 |
| 47 COIN | 10362 (−10)/0/2/45 | jingle table |
| 48 QUEST | 16423 (−6)/0/1/90 | jingle table |
| 49 BOSS_ROAR | 23198 (−3)/0/1/70 | S 38→33/1.2 d1.60 env .12/.7/.5/.35 vib .7@6+0 lp 1500; P12 45→40/1.2 d1.60 ×.5 env .12/.7/.5/.35 vib 1@7+0 lp 1500; N 66→56/1.2 d1.50 ×.5 env .10/.6/.4/.35 lp 1800 hp 80; N93 60 d1.40 ×.15 env .10/.6/.4/.35 lp 1200 |
| 50 SLAM | 26029 (−2)/60/1/60 | T 40→24/.3 d.70 env .0015/.16/0/.20; N 84→56/.5 d.80 ×.9 env .0015/.15/0/.25 lp 4000; N93 76 d.12 ×.35 env .0015/.03/0/.03 hp 800 |
| 51 VILLAGER | 11627 (−9)/200/2/20 | P25 52→48/.3 d.30 env .02/.15/.5/.08 vib .6@8+0 lp 1400; P25 64→60/.3 d.30 ×.25 env .02/.15/.5/.08 vib .6@8+0 lp 1400 |
| 52 DRINK | 10362 (−10)/150/1/0 | P50 55→62/.06 d.07; P50 53→60/.06 @.10 d.07; P50 51→58/.06 @.20 d.07 — all env .004/.03/0/.025 lp 1200; N 64 d.27 ×.25 env .02/.10/.3/.06 lp 900 hp 100 |
| 53 DOOR_OPEN | 10362 (−10)/120/2/20 | N93 86 d.03 env .0015/.008/0/.01 hp 2000; T 50→45/.05 d.08 ×.5 env .0015/.025/0/.025; P12 55→58/.2 d.25 ×.6 env .02/.10/.4/.06 vib .4@23+0 lp 1500 |
| 54 DOOR_CLOSE | 13045 (−8)/120/2/25 | T 47→36/.05 d.15 env .0015/.04/0/.04; N 74→64/.06 d.12 ×.7 env .0015/.03/0/.03 lp 2500 hp 150; N93 86 @.02 d.03 ×.5 env .0015/.008/0/.01 hp 2000 |
| 55 FREEZE | 11627 (−9)/80/1/60 | N93 92 @0, 96 @.07, 90 @.12, 94 @.19, 88 @.23 — each d.04 ×.8 env .0015/.01/0/.012 hp 3000; P12 100 @.02 d.20 ×.3 env .0015/.06/0/.06; P12 105 @.10 d.20 ×.22 env .0015/.05/0/.06 |
| 56 HEAVY | 20675 (−4)/80/1/30 | N 64→78/.10 d.12 ×.7 env .06/0/1/.04 lp 3000 hp 200; T 45→26/.10 @.09 d.20 env .0015/.05/0/.05; N 78→62/.10 @.09 d.16 ×.7 env .0015/.04/0/.04 lp 2500 |
| 57 KNIVES | 14637 (−7)/80/1/20 | N 76→90/.08 @0, 78→92/.08 @.06, 80→94/.08 @.12, 82→96/.08 @.18 — each d.10 env .02/0/1/.06 lp 7000 hp 1200 |
| 58 LOOT_RARE | 14637 (−7)/0/1/80 | jingle table |
| 59 LEGENDARY | 18427 (−5)/0/1/100 | jingle table |

### Jingles — composition brief (one leitmotif family)

```
Title: "AssemblyCraft call" family / bright, rewarding / five one-shots, 0.39–1.66 s
Key: D major (Ionian) · 16th = 0.075 s (LEGENDARY: 0.065 s, augmented) · 4/4 · straight
Motif M: D5 E5 A5 F#5 (16th 16th 8th quarter) = degrees 1-2-5-3: step up, leap a 4th, fall to the 3rd
Variants: COIN = M's leap landing on the tonic (A5→D6) · LOOT_RARE = M's head on the dominant, open (A5 B5 E6)
          QUEST = M plain, closes on 3 over I · LEVELUP = M, sequence up a step, ii–V–I to D6
          LEGENDARY = M augmented + IV–V–I, octave-bounce bass, arpeggio shimmer
Chord charts: LEVELUP | D (bar 1) | Em (bar 2) | A → D |   LEGENDARY | D | D | G A | D |
Channels (≤ 4 sounding at once): lead P25 · echo P12 = lead one 16th later at ×.35 · bass T on every downbeat · sparkle P12 tracker arp
Peaks: COIN D6 · LOOT_RARE E6 · QUEST A5 · LEVELUP D6 (last note only) · LEGENDARY D6 (last note only)
Deliberate rule break: E5 (2) leaps instead of resolving by step (escape-tone figure); it is what makes M recognisable, and the line resolves on the 3rd two notes later.
```

| Jingle | Lead (P25) | Echo (P12 ×.35; each lead note one 16th later, same note/dur/env) | Bass (T) | Extra |
|---|---|---|---|---|
| 47 COIN | 81 d.065 st; 86 @.065 d.30 env .0015/.08/0/.06 | only the 2nd note: 86 @.14 d.25 ×.3 env .0015/.07/0/.06 | — | — |
| 58 LOOT_RARE | 81 d.075 st; 83 @.075 d.075 st; 88 @.15 d.40 env .0015/.12/0/.10 | +.075 s; the last one d.35 env .0015/.10/0/.10 | 57 d.30 ×.8 env .0015/.10/0/.06 | P12 81 @.15 d.40 ×.22 arp +4+7@50 env .0015/.12/0/.10 |
| 48 QUEST | 74 d.075 st; 76 @.075 d.075 st; 81 @.15 d.15 env .0015/0/1/.015; 78 @.30 d.45 env .0015/.15/.3/.12 | +.075 s; the last one d.40 | 50 d.14 env .0015/.06/0/.03; 45 @.15 d.14 same env; 50 @.30 d.45 env .0015/.15/0/.10 | — |
| 40 LEVELUP | 74 d.075 st; 76 @.075 d.075 st; 81 @.15 d.15 env .0015/0/1/.015; 76 @.30 d.075 st; 78 @.375 d.075 st; 83 @.45 d.15 env .0015/0/1/.015; 85 @.60 d.075 st; 86 @.675 d.55 env .0015/.18/.25/.15 | +.075 s; the last one d.50 | 50 d.28 env .0015/.08/0/.04; 52 @.30 d.28 same env; 45 @.60 d.07 st; 50 @.675 d.55 env .0015/.18/0/.15 | P12 86 @.675 d.50 ×.22 arp +4+7@50 env .0015/.15/0/.12 |
| 59 LEGENDARY | 74 d.13 and 76 @.13 d.13 (env .0015/0/1/.015); 81 @.26 d.26 and 78 @.52 d.26 (env .0015/.2/.6/.02); 79 @.78 d.13 and 81 @.91 d.13 (env .0015/0/1/.015); 86 @1.04 d.60 env .0015/.22/.3/.18 | +.065 s; the last one d.55 | 50 @0, 38 @.13, 50 @.26, 38 @.39, 50 @.52, 38 @.65, 43 @.78, 45 @.91 — each d.12 env .0015/.05/0/.02; 50 @1.04 d.60 env .0015/.2/0/.18 | P12 86 @1.04 d.55 ×.22 arp +4+7@50 env .0015/.15/0/.12; N93 96 @1.04 d.05 ×.25 env .0015/.012/0/.02 hp 4000 |

## Critical files & anchors

- `src/sfx.asm`: `layers:` table, `sfx_build` (`.pack` is where normalisation goes), `render_layer`. The whole renderer is replaced.
- `src/audio.asm`: `audio_update` `.voice`/`.out` loops (become `audio_mix`), `start_voice`, `audio_play_at`, `pa_ss`/`pa_attr`.
- `src/common.inc`: `struc SFXLAYER` (~1410), the `SND_*` block (~811), `struc SETTINGS` (`.volume` at +12, used by the harness stub).
- `src/player.asm`: `player_forward` and the strafe comment (~717); together they prove the right vector `(cos yaw, sin yaw)`.
- `src/selftest.asm`: the `extern` list, `tests:` (`TEST x`) and `TESTNAME x` lists.

## Verification

Run everything from the repo root `/run/media/octopusman/Games/Experiences/assemblycraft`.
1. `make 2>&1 | grep -i warning` prints nothing; `make test` → every test `ok`, including `sfx_clean_edges`, `audio_pan`, `audio_caps_jitter_limiter` (summary = previous count + 3, 0 failed).
2. Negative control for the measurement: build a `/tmp` copy of `sfx.asm` into the harness only, with the envelope's `A` and `R` terms forced to 1. `report.py` must then show `|x0|/pk` > 0.3 on CLICK and `|x_end|/pk` > 0.05 on at least one decaying sound. This proves the metric sees clicks. Do not modify the repo for this.
3. `report.py` on the new pool:
   - Every sound has `|x0|/pk ≤ 0.016` and `|x_end|/pk ≤ 0.031`.
   - No sound above 60 % energy over 8 kHz, except DIG_GLASS and FREEZE (glass/ice by design).
   - COIN's inharmonic share is < 1.0 % (the naive square measured 1.8 % at 1047 Hz).
   - Stress scene: max |sample| ≤ 29206.
   - mobs_pan: L RMS − R RMS ≥ 4 dB over 0–1.0 s (zombie left; dry ratio is 8 dB before the centred echo), and R − L ≥ 4 dB over 1.2–2.2 s.
   - Two harness runs give identical `md5sum pool.bin`.
4. Listening gate (step 6): the user answers "Approve".
5. Live smoke: with no other audio playing on the desktop, launch per the `omabox` skill (`make run`, open or create a world). Confirm stdout has no "no sound" line (audio_init connected). While walking, digging, hitting a mob and opening a door, run `timeout 6 parec -d @DEFAULT_MONITOR@ --format=s16le --rate=44100 --channels=2 /tmp/acsound/live.raw`. The capture must be non-silent, have samples where L≠R (stereo stream), and peak ≤ 29300. If the omabox session has no audio route (audio_init fails there), ask the user to run `make run` on their desktop and confirm footsteps vary, sounds pan and nothing clicks.

## Assumptions & contingencies

- Music, ambient loops and distance-based dulling stay out (user chose "SFX overhaul only"; the 0.12 music builds on this renderer).
- Per-sound levels: peaks keep today's balance within ±3 dB except deliberate changes: footsteps −2 dB, EXPLODE +4 dB, RIFLE +5.7 dB (it was oddly quiet), SWING/DODGE −4 dB (they play every attack). If the user flags a level, change only that row's `peak`.
- If COIN's inharmonic share is ≥ 1 %, the BLEP is wrong, not insufficient. Render a lone P25 at 1174.66 Hz in the harness and check the edge signs and the `frac(p − d + 1)` term. Do not mask aliasing with low-pass filters.
- If sfx_build makes startup visibly slower (> 0.3 s for `make test`'s `sfx_clean_edges`), keep the 32-sample control tick and move `exp2_ss` calls out of any per-sample path. Do not lower quality.
- If the user rejects the echo outright, set every `send` to 0 and delete the echo lines, their filter states and constants from `audio_mix` and `audio_reset` (no dead code). If they only want less or more, scale the `send` column.

## As built

- Shipped as planned, with these differences:
  - `audio.asm` exports `voices`, and `%define VOICES 16` moved to `common.inc` beside `struc VOICE`, so `test_audio.asm` can count voices per sound.
  - `start_voice` clamps the volume to 0..1 itself. Both `audio_play` and `audio_play_at` rely on that clamp.
- The renderer and the mixer land in one commit: once `struc VOICE` moved to `common.inc`, the old `audio.asm` no longer assembles.
- The pool holds 215 layers. `sfx_build` plus every harness scene runs in 0.06 s.
- Measured on the shipped pool (`/tmp/acsound/report.py`):
  - The worst onset is `|x0|/pk` = 0.0000 and the worst tail is `|x_end|/pk` = 0.0002.
  - The most energy above 8 kHz outside glass and ice is SKELETON_SAY's 44.5 %. FREEZE has 53.2 %.
  - COIN's inharmonic share is 0.078 %.
  - The stress scene peaks at 29205.
  - In mobs_pan, the zombie is 7.6 dB louder on its side, both left and right.
  - Two builds give the same pool md5.
- Negative controls:
  - Forcing the A and R envelope terms to 1 gives CLICK `|x0|/pk` = 0.56. It also gives tails of 0.07 (DIG_WOOD), 0.11 (STEP_SOFT) and 0.48 (BURP).
  - Each of these mutants fails its selftest: a pan sign error, no limiter, no voice cap, and no envelope edges.
- Live check: the game ran in an omabox `--audio` box. The menu clicks, footsteps, swings and a landing were captured from the sink monitor. The capture was non-silent, had 46936 frames with L≠R and peaked at 15991.
- The user approved the A/B preview pack by ear.

## Deferred

- None.

## Mix rework (after play-testing)

The user said the sounds were good but the mix was bad: levels did not match from one sound to the next.

**Cause.** `sfx_build` set each sound's level from its peak. At equal peaks, long low-crest noise sounds (SPELL, WHIRL, KNIVES, DODGE, BURP) were heard up to 10 dB louder than they should be. Short, spiky sounds (CLICK, STEP_WOOD, ARROW_HIT, CHICKEN_SAY, DRY_FIRE) came out up to 9 dB too quiet. Across all 60 sounds, the gap to the intended mix was 3.4 dB on average and 10 dB at worst.

**Fix.** `SFXINFO.peak` is now `SFXINFO.level`, a loudness target.
- The loudness measure is the RMS of the loudest 100 ms of the sound, after K-weighting (ITU BS.1770: high shelf, then a 38 Hz high-pass, both at 44.1 kHz in doubles). It is taken over 10 ms hops, and a sound shorter than 100 ms counts as padded with silence. `kweight_ms` in `sfx.asm` computes it.
- `sfx_build` scales each sound to its level. The scaling stops early wherever the peak would pass -0.5 dBFS.
- Each level equals the loudness wanted in game, less the volume of the sound's usual call site (and the distance gain for positional sounds), so the call sites stay untouched.

**The mix ladder,** in dB relative to an explosion 5 blocks away:

| Sounds | Level |
|---|---|
| Explosion | 0 |
| Guns, slam, boss roar | -2 to -4 |
| Player hurt, jingles, crit, heavy, block, parry, abilities | -5 to -9 |
| Mob hurts | -8 to -9 |
| Coin, bow | -9 to -10 |
| Dig, mob voices, doors, eat, drink, burp, reload | -11 to -13 |
| Arrow hit, swing, dodge | -12 |
| Dry fire, pop | -14 to -16 |
| Steps, click | -18 |

The staff bolt keeps its 0.35 call volume, which puts it about 7 dB under the other abilities.

**Checks.**
- An independent Python model (`/tmp/acsound/loud.py`) reads back every sound within 0.0 dB of its target.
- Every sound still passes the click checks, and the stress scene peaks at 26466.
- The overall level moved by less than 1 dB: the explosion went from -11.1 to -11.7 dB K-weighted.
