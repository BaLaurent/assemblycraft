; sfx.asm - procedural chip sound effects: the 60 game sounds rendered once into one int16 pool.
; Each sound is the sum of a few chip-instrument layers: band-limited pulse (variable duty) and saw,
; a 2A03-style 32-step triangle and a 15-bit LFSR noise channel (long or short mode), with a
; per-32-sample pitch tick (glide, tracker arpeggio, delayed vibrato), one-pole high/low-pass and an
; attack/decay/sustain/release envelope. Every sound is then normalised to a loudness,
; sfx_info[id].level: the K-weighted (ITU BS.1770) RMS of its loudest 100 ms, so sounds of one
; level are heard as equally loud whatever their length or brightness (a peak ceiling still applies).
; sfx_table[id] = {offset, length} in samples; sfx_pool is mono signed 16-bit, 44100 Hz.
%include "common.inc"
default rel

global sfx_build, sfx_table, sfx_pool, sfx_info

extern exp2_ss

; ---- layer DSL: LAYER sets the defaults, ARP/VIB/DUTY/ENV/FILT override, LEND emits the record.
; LAYER sound, wave, start, dur, amp, note0, note1, glide (every float with a decimal point)
%macro LAYER 8
    %define L_SOUND %1
    %define L_WAVE %2
    %define L_START %3
    %define L_DUR %4
    %define L_AMP %5
    %define L_NOTE0 %6
    %define L_NOTE1 %7
    %define L_GLIDE %8
    %define L_ARP1 0.0
    %define L_ARP2 0.0
    %define L_ARPHZ 0.0
    %define L_VDEPTH 0.0
    %define L_VHZ 0.0
    %define L_VDELAY 0.0
    %define L_DUTY0 0.5
    %define L_DUTY1 0.5
    %define L_ATTACK 0.0015
    %define L_DECAY 0.0
    %define L_SUSTAIN 1.0
    %define L_RELEASE 0.004
    %define L_LP 0.0
    %define L_HP 0.0
%endmacro
%macro ARP 3                            ; semitones a1, a2 (0 = two-step), steps per second
    %define L_ARP1 %1
    %define L_ARP2 %2
    %define L_ARPHZ %3
%endmacro
%macro VIB 3                            ; depth semitones, rate Hz, delay seconds
    %define L_VDEPTH %1
    %define L_VHZ %2
    %define L_VDELAY %3
%endmacro
%macro DUTY 2                           ; pulse duty at the start and at the end of the layer
    %define L_DUTY0 %1
    %define L_DUTY1 %2
%endmacro
%macro ENV 4                            ; attack, decay time constant, sustain, release
    %define L_ATTACK %1
    %define L_DECAY %2
    %define L_SUSTAIN %3
    %define L_RELEASE %4
%endmacro
%macro FILT 2                           ; low-pass Hz, high-pass Hz (0 = off)
    %define L_LP %1
    %define L_HP %2
%endmacro
%macro LEND 0                           ; SFXLAYER field order
    dd L_SOUND, L_WAVE, L_START, L_DUR, L_AMP, L_NOTE0, L_NOTE1, L_GLIDE
    dd L_ARP1, L_ARP2, L_ARPHZ, L_VDEPTH, L_VHZ, L_VDELAY, L_DUTY0, L_DUTY1
    dd L_ATTACK, L_DECAY, L_SUSTAIN, L_RELEASE, L_LP, L_HP
%endmacro

; SINFO level (int16 K-weighted RMS), jitter (+- cents), cap (voices), send (echo 0..255)
%macro SINFO 4
    dw %1, %2
    db %3, %4, 0, 0
%endmacro

section .rodata
align 4
c_one:       dd 1.0
c_mone:      dd -1.0
c_two:       dd 2.0
c_four:      dd 4.0
c_half:      dd 0.5
c_quarter:   dd 0.25
c_16:        dd 16.0
c_32:        dd 32.0
c_2_15:      dd 0.13333334              ; 2 / 15, triangle step
c_69:        dd 69.0
c_inv12:     dd 0.083333336             ; 1 / 12
c_440_rate:  dd 0.009977324             ; 440 / 44100: A4 phase step
c_rate:      dd 44100.0
c_inv_rate:  dd 2.2675736961451248e-5   ; 1 / 44100
c_fc:        dd -2.0555e-4              ; -2 pi / (44100 ln 2): one-pole coefficient exponent per Hz
c_duty_min:  dd 0.05
c_duty_max:  dd 0.95
c_att_min:   dd 0.0015                  ; engine floors: no layer starts or stops in a step
c_rel_min:   dd 0.004
c_abs:       dd 0x7FFFFFFF
c_pmax:      dd 32767.0
c_pmin:      dd -32767.0
c_ceil_tol:  dd 0.01                    ; keeps float noise in 0.18 s etc. from adding a sample
c_peak_max:  dd 30934.0                 ; -0.5 dBFS: loudness never pushes a peak past it
c_inv_4410:  dq 2.2675736961451248e-4   ; 1 / 4410, mean over a 100 ms window
align 8                                 ; K-weighting at 44.1 kHz: high shelf (b, a) then RLB high-pass (c, d)
k_b0:        dq 1.5245497507424821
k_b1:        dq -2.5910067542593858
k_b2:        dq 1.126819073893832
k_a1:        dq -1.6237063834520935
k_a2:        dq 0.68406845382902193
k_c0:        dq 0.9945921773542088
k_c1:        dq -1.9891843547084176
k_c2:        dq 0.9945921773542088
k_d1:        dq -1.9891696736297959
k_d2:        dq 0.98919903578703927

; per sound: loudness, pitch jitter, voice cap, echo send (audio.asm reads the last three). The
; levels set the mix: each is the loudness wanted in game, less the volume its usual call site plays
; it at (and the distance a positional sound is usually heard from), so an explosion 5 blocks off is
; the loudest event; then guns, slam and the boss (-2..-4 dB); player hurt, jingles, crits and
; abilities (-5..-9); mob hurts (-8); digs, mob voices, doors, eating (-11..-13); footsteps and UI
; clicks (-16..-18).
align 8
sfx_info:
    SINFO  1791,   0, 1,   0            ; 0  CLICK
    SINFO  2145, 250, 3,   0            ; 1  DIG_STONE
    SINFO  2145, 250, 3,   0            ; 2  DIG_WOOD
    SINFO  2145, 300, 3,   0            ; 3  DIG_SOFT
    SINFO  2406, 150, 2,  40            ; 4  DIG_GLASS
    SINFO  3071, 300, 2,   0            ; 5  STEP_STONE
    SINFO  3071, 300, 2,   0            ; 6  STEP_WOOD
    SINFO  3071, 350, 2,   0            ; 7  STEP_SOFT
    SINFO  4801, 120, 2,  20            ; 8  HURT
    SINFO  3186, 300, 2,   0            ; 9  EAT
    SINFO  3438, 150, 1,   0            ; 10 BURP
    SINFO  5500, 200, 2,  30            ; 11 ZOMBIE_SAY
    SINFO  4028, 150, 2,  20            ; 12 ZOMBIE_HURT
    SINFO  4902, 200, 2,  15            ; 13 PIG_SAY
    SINFO  4028, 150, 2,  15            ; 14 PIG_HURT
    SINFO  3777, 100, 1,  40            ; 15 TOOL_BREAK
    SINFO  3866, 400, 2,  15            ; 16 POP
    SINFO 12419, 120, 3,  70            ; 17 EXPLODE
    SINFO  3728,   0, 2,   0            ; 18 FUSE
    SINFO  3787, 150, 3,  25            ; 19 BOW
    SINFO  5361, 200, 3,  15            ; 20 ARROW_HIT
    SINFO  4902, 200, 2,  25            ; 21 SKELETON_SAY
    SINFO  4028, 150, 2,  20            ; 22 SKELETON_HURT
    SINFO  5500, 200, 2,  15            ; 23 SPIDER_SAY
    SINFO  4028, 150, 2,  15            ; 24 SPIDER_HURT
    SINFO  4028, 150, 2,  15            ; 25 CREEPER_HURT
    SINFO  4369, 200, 2,  15            ; 26 CHICKEN_SAY
    SINFO  3590, 150, 2,  15            ; 27 CHICKEN_HURT
    SINFO  5387,  80, 3,  55            ; 28 PISTOL
    SINFO  6782,  80, 2,  70            ; 29 MUSKET
    SINFO  6782,  80, 2,  65            ; 30 SHOTGUN
    SINFO  6044,  80, 3,  50            ; 31 RIFLE
    SINFO  6044,  60, 2,  55            ; 32 LAUNCHER
    SINFO  2681,  60, 1,  15            ; 33 RELOAD
    SINFO  2839,  60, 1,   0            ; 34 DRY_FIRE
    SINFO  3574, 250, 2,   0            ; 35 SWING
    SINFO  3814,  60, 2,  60            ; 36 PARRY
    SINFO  3814, 100, 2,  25            ; 37 BLOCK
    SINFO  2145, 150, 1,  10            ; 38 DODGE
    SINFO  4279,  80, 2,  55            ; 39 CRIT
    SINFO  4279,   0, 1,  90            ; 40 LEVELUP
    SINFO  4249, 100, 2,  70            ; 41 SPELL
    SINFO  5349, 100, 2,  60            ; 42 FIREBALL
    SINFO  4249,  60, 1,  80            ; 43 BLINK
    SINFO  5349,  60, 1,  60            ; 44 WARCRY
    SINFO  4249, 100, 1,  25            ; 45 WHIRL
    SINFO  3787, 100, 1,  40            ; 46 SMOKE
    SINFO  3857,   0, 2,  45            ; 47 COIN
    SINFO  3814,   0, 1,  90            ; 48 QUEST
    SINFO  9864,   0, 1,  70            ; 49 BOSS_ROAR
    SINFO  8477,  60, 1,  60            ; 50 SLAM
    SINFO  4085, 200, 2,  20            ; 51 VILLAGER
    SINFO  2681, 150, 1,   0            ; 52 DRINK
    SINFO  3319, 120, 2,  20            ; 53 DOOR_OPEN
    SINFO  3319, 120, 2,  25            ; 54 DOOR_CLOSE
    SINFO  4249,  80, 1,  60            ; 55 FREEZE
    SINFO  4279,  80, 1,  30            ; 56 HEAVY
    SINFO  4249,  80, 1,  20            ; 57 KNIVES
    SINFO  4856,   0, 1,  80            ; 58 LOOT_RARE
    SINFO  6113,   0, 1, 100            ; 59 LEGENDARY
%if $ - sfx_info != NUM_SOUNDS * SFXINFO_size
    %error "sfx_info must hold NUM_SOUNDS rows"
%endif

; Layers, grouped by sound id in id order (sfx_build relies on it). Notes are MIDI numbers; the
; noise clock is 16 x the note's Hz (n100 ~ 42 kHz bright white, n60 ~ 4.2 kHz dark crunch).
; amp is relative inside one sound: sfx_build normalises each sound to its sfx_info peak.
align 4
layers:
; 0 CLICK
    LAYER SND_CLICK, W_PULSE, 0.0, 0.025, 1.0, 96.0, 96.0, 0.0
    DUTY 0.125, 0.125
    ENV 0.0015, 0.006, 0.0, 0.008
    LEND
    LAYER SND_CLICK, W_TRI, 0.0, 0.02, 0.5, 72.0, 72.0, 0.0
    ENV 0.0015, 0.005, 0.0, 0.006
    LEND
; 1 DIG_STONE
    LAYER SND_DIG_STONE, W_NOISE, 0.0, 0.16, 1.0, 92.0, 84.0, 0.08
    ENV 0.0015, 0.035, 0.0, 0.03
    FILT 0.0, 600.0
    LEND
    LAYER SND_DIG_STONE, W_NOISE93, 0.0, 0.06, 0.35, 80.0, 80.0, 0.0
    ENV 0.0015, 0.015, 0.0, 0.02
    FILT 0.0, 1500.0
    LEND
    LAYER SND_DIG_STONE, W_TRI, 0.0, 0.06, 0.5, 45.0, 33.0, 0.04
    ENV 0.0015, 0.02, 0.0, 0.02
    LEND
; 2 DIG_WOOD
    LAYER SND_DIG_WOOD, W_TRI, 0.0, 0.12, 1.0, 55.0, 43.0, 0.05
    ENV 0.0015, 0.04, 0.0, 0.03
    LEND
    LAYER SND_DIG_WOOD, W_NOISE, 0.0, 0.08, 0.5, 78.0, 78.0, 0.0
    ENV 0.0015, 0.02, 0.0, 0.02
    FILT 3000.0, 300.0
    LEND
    LAYER SND_DIG_WOOD, W_PULSE, 0.0, 0.05, 0.25, 67.0, 60.0, 0.03
    ENV 0.0015, 0.015, 0.0, 0.015
    FILT 1800.0, 0.0
    LEND
; 3 DIG_SOFT
    LAYER SND_DIG_SOFT, W_NOISE, 0.0, 0.16, 1.0, 70.0, 62.0, 0.10
    ENV 0.004, 0.05, 0.0, 0.04
    FILT 2200.0, 150.0
    LEND
    LAYER SND_DIG_SOFT, W_NOISE, 0.0, 0.05, 0.25, 84.0, 84.0, 0.0
    ENV 0.0015, 0.015, 0.0, 0.015
    FILT 0.0, 2500.0
    LEND
; 4 DIG_GLASS
    LAYER SND_DIG_GLASS, W_NOISE93, 0.0, 0.12, 0.7, 94.0, 94.0, 0.0
    ENV 0.0015, 0.03, 0.0, 0.03
    FILT 0.0, 3000.0
    LEND
    LAYER SND_DIG_GLASS, W_PULSE, 0.0, 0.14, 0.3, 100.0, 100.0, 0.0
    DUTY 0.125, 0.125
    ENV 0.0015, 0.04, 0.0, 0.04
    LEND
    LAYER SND_DIG_GLASS, W_PULSE, 0.03, 0.12, 0.25, 103.0, 103.0, 0.0
    DUTY 0.125, 0.125
    ENV 0.0015, 0.04, 0.0, 0.04
    LEND
    LAYER SND_DIG_GLASS, W_PULSE, 0.06, 0.12, 0.2, 98.0, 98.0, 0.0
    DUTY 0.125, 0.125
    ENV 0.0015, 0.05, 0.0, 0.04
    LEND
; 5 STEP_STONE
    LAYER SND_STEP_STONE, W_NOISE, 0.0, 0.06, 1.0, 90.0, 84.0, 0.03
    ENV 0.0015, 0.015, 0.0, 0.02
    FILT 0.0, 900.0
    LEND
    LAYER SND_STEP_STONE, W_TRI, 0.0, 0.04, 0.35, 48.0, 40.0, 0.02
    ENV 0.0015, 0.012, 0.0, 0.012
    LEND
; 6 STEP_WOOD
    LAYER SND_STEP_WOOD, W_TRI, 0.0, 0.07, 1.0, 57.0, 45.0, 0.03
    ENV 0.0015, 0.025, 0.0, 0.02
    LEND
    LAYER SND_STEP_WOOD, W_NOISE, 0.0, 0.03, 0.35, 76.0, 76.0, 0.0
    ENV 0.0015, 0.008, 0.0, 0.01
    FILT 4000.0, 400.0
    LEND
; 7 STEP_SOFT
    LAYER SND_STEP_SOFT, W_NOISE, 0.0, 0.08, 1.0, 66.0, 60.0, 0.05
    ENV 0.004, 0.025, 0.0, 0.03
    FILT 1800.0, 120.0
    LEND
; 8 HURT
    LAYER SND_HURT, W_PULSE, 0.0, 0.22, 1.0, 76.0, 64.0, 0.12
    DUTY 0.25, 0.25
    VIB 0.6, 22.0, 0.0
    ENV 0.002, 0.08, 0.0, 0.05
    LEND
    LAYER SND_HURT, W_NOISE, 0.0, 0.10, 0.4, 80.0, 70.0, 0.10
    ENV 0.0015, 0.03, 0.0, 0.03
    FILT 0.0, 500.0
    LEND
    LAYER SND_HURT, W_TRI, 0.0, 0.10, 0.6, 50.0, 38.0, 0.06
    ENV 0.0015, 0.03, 0.0, 0.03
    LEND
; 9 EAT
    LAYER SND_EAT, W_NOISE, 0.0, 0.10, 1.0, 82.0, 76.0, 0.05
    ENV 0.002, 0.03, 0.0, 0.03
    FILT 4000.0, 600.0
    LEND
    LAYER SND_EAT, W_NOISE93, 0.0, 0.05, 0.25, 70.0, 70.0, 0.0
    ENV 0.0015, 0.015, 0.0, 0.015
    FILT 2500.0, 0.0
    LEND
; 10 BURP
    LAYER SND_BURP, W_PULSE, 0.0, 0.30, 1.0, 50.0, 45.0, 0.25
    VIB 0.8, 28.0, 0.0
    ENV 0.01, 0.15, 0.3, 0.08
    FILT 1500.0, 0.0
    LEND
; 11 ZOMBIE_SAY
    LAYER SND_ZOMBIE_SAY, W_PULSE, 0.0, 0.75, 1.0, 45.0, 41.0, 0.6
    DUTY 0.125, 0.125
    VIB 0.5, 5.5, 0.1
    ENV 0.06, 0.4, 0.4, 0.15
    FILT 1400.0, 0.0
    LEND
    LAYER SND_ZOMBIE_SAY, W_PULSE, 0.0, 0.75, 0.3, 52.0, 48.0, 0.6
    DUTY 0.25, 0.25
    VIB 0.5, 5.5, 0.1
    ENV 0.06, 0.4, 0.4, 0.15
    FILT 1400.0, 0.0
    LEND
    LAYER SND_ZOMBIE_SAY, W_NOISE, 0.0, 0.70, 0.18, 60.0, 60.0, 0.0
    ENV 0.10, 0.3, 0.3, 0.15
    FILT 900.0, 0.0
    LEND
; 12 ZOMBIE_HURT
    LAYER SND_ZOMBIE_HURT, W_PULSE, 0.0, 0.28, 1.0, 52.0, 40.0, 0.2
    DUTY 0.125, 0.125
    VIB 1.0, 18.0, 0.0
    ENV 0.002, 0.10, 0.0, 0.06
    FILT 2000.0, 0.0
    LEND
    LAYER SND_ZOMBIE_HURT, W_NOISE, 0.0, 0.12, 0.5, 78.0, 66.0, 0.10
    ENV 0.0015, 0.03, 0.0, 0.03
    FILT 0.0, 400.0
    LEND
; 13 PIG_SAY
    LAYER SND_PIG_SAY, W_PULSE, 0.0, 0.11, 1.0, 62.0, 57.0, 0.08
    DUTY 0.25, 0.25
    VIB 0.7, 32.0, 0.0
    ENV 0.004, 0.05, 0.0, 0.03
    FILT 2200.0, 0.0
    LEND
    LAYER SND_PIG_SAY, W_PULSE, 0.16, 0.11, 1.0, 60.0, 55.0, 0.08
    DUTY 0.25, 0.25
    VIB 0.7, 32.0, 0.0
    ENV 0.004, 0.05, 0.0, 0.03
    FILT 2200.0, 0.0
    LEND
; 14 PIG_HURT
    LAYER SND_PIG_HURT, W_PULSE, 0.0, 0.22, 1.0, 72.0, 60.0, 0.18
    DUTY 0.25, 0.25
    VIB 1.0, 30.0, 0.0
    ENV 0.002, 0.08, 0.0, 0.05
    FILT 3000.0, 0.0
    LEND
    LAYER SND_PIG_HURT, W_NOISE, 0.0, 0.05, 0.35, 80.0, 80.0, 0.0
    ENV 0.0015, 0.015, 0.0, 0.015
    FILT 0.0, 800.0
    LEND
; 15 TOOL_BREAK
    LAYER SND_TOOL_BREAK, W_NOISE93, 0.0, 0.22, 0.8, 88.0, 76.0, 0.15
    ENV 0.0015, 0.05, 0.0, 0.05
    FILT 0.0, 1200.0
    LEND
    LAYER SND_TOOL_BREAK, W_PULSE, 0.0, 0.20, 0.35, 91.0, 79.0, 0.18
    DUTY 0.125, 0.125
    ENV 0.0015, 0.06, 0.0, 0.05
    LEND
    LAYER SND_TOOL_BREAK, W_PULSE, 0.03, 0.18, 0.25, 86.0, 74.0, 0.18
    DUTY 0.125, 0.125
    ENV 0.0015, 0.06, 0.0, 0.05
    LEND
; 16 POP
    LAYER SND_POP, W_PULSE, 0.0, 0.07, 1.0, 79.0, 91.0, 0.03
    DUTY 0.25, 0.25
    ENV 0.0015, 0.025, 0.0, 0.02
    LEND
; 17 EXPLODE
    LAYER SND_EXPLODE, W_NOISE, 0.0, 1.20, 1.0, 94.0, 56.0, 0.9
    ENV 0.002, 0.22, 0.0, 0.30
    FILT 6000.0, 0.0
    LEND
    LAYER SND_EXPLODE, W_TRI, 0.0, 0.50, 0.8, 40.0, 26.0, 0.35
    ENV 0.002, 0.15, 0.0, 0.10
    LEND
    LAYER SND_EXPLODE, W_NOISE93, 0.0, 0.70, 0.3, 70.0, 58.0, 0.6
    ENV 0.0015, 0.18, 0.0, 0.15
    FILT 2500.0, 0.0
    LEND
; 18 FUSE
    LAYER SND_FUSE, W_NOISE, 0.0, 1.50, 1.0, 96.0, 96.0, 0.0
    ARP -14.0, 0.0, 17.0
    ENV 0.05, 0.0, 1.0, 0.12
    FILT 9000.0, 3000.0
    LEND
; 19 BOW
    LAYER SND_BOW, W_NOISE, 0.0, 0.10, 0.6, 88.0, 70.0, 0.06
    ENV 0.002, 0.03, 0.0, 0.03
    FILT 0.0, 1500.0
    LEND
    LAYER SND_BOW, W_TRI, 0.0, 0.13, 0.9, 60.0, 43.0, 0.08
    ENV 0.0015, 0.05, 0.0, 0.04
    LEND
    LAYER SND_BOW, W_PULSE, 0.0, 0.10, 0.3, 67.0, 55.0, 0.08
    ENV 0.0015, 0.03, 0.0, 0.03
    FILT 2000.0, 0.0
    LEND
; 20 ARROW_HIT
    LAYER SND_ARROW_HIT, W_TRI, 0.0, 0.07, 1.0, 55.0, 38.0, 0.03
    ENV 0.0015, 0.02, 0.0, 0.02
    LEND
    LAYER SND_ARROW_HIT, W_NOISE, 0.0, 0.04, 0.5, 84.0, 84.0, 0.0
    ENV 0.0015, 0.01, 0.0, 0.012
    FILT 0.0, 1200.0
    LEND
    LAYER SND_ARROW_HIT, W_PULSE, 0.0, 0.05, 0.15, 79.0, 79.0, 0.0
    DUTY 0.125, 0.125
    VIB 1.0, 40.0, 0.0
    ENV 0.0015, 0.015, 0.0, 0.015
    LEND
; 21 SKELETON_SAY: four dry bone clacks
    LAYER SND_SKELETON_SAY, W_NOISE93, 0.0, 0.04, 1.0, 90.0, 90.0, 0.0
    ENV 0.0015, 0.012, 0.0, 0.015
    FILT 0.0, 1500.0
    LEND
    LAYER SND_SKELETON_SAY, W_NOISE93, 0.07, 0.04, 1.0, 93.0, 93.0, 0.0
    ENV 0.0015, 0.012, 0.0, 0.015
    FILT 0.0, 1500.0
    LEND
    LAYER SND_SKELETON_SAY, W_NOISE93, 0.13, 0.04, 1.0, 88.0, 88.0, 0.0
    ENV 0.0015, 0.012, 0.0, 0.015
    FILT 0.0, 1500.0
    LEND
    LAYER SND_SKELETON_SAY, W_NOISE93, 0.20, 0.04, 1.0, 91.0, 91.0, 0.0
    ENV 0.0015, 0.012, 0.0, 0.015
    FILT 0.0, 1500.0
    LEND
; 22 SKELETON_HURT
    LAYER SND_SKELETON_HURT, W_NOISE93, 0.0, 0.16, 1.0, 92.0, 80.0, 0.10
    ENV 0.0015, 0.04, 0.0, 0.04
    FILT 0.0, 1200.0
    LEND
    LAYER SND_SKELETON_HURT, W_PULSE, 0.0, 0.14, 0.3, 84.0, 72.0, 0.12
    DUTY 0.125, 0.125
    ENV 0.0015, 0.04, 0.0, 0.04
    LEND
    LAYER SND_SKELETON_HURT, W_TRI, 0.0, 0.06, 0.4, 55.0, 45.0, 0.04
    ENV 0.0015, 0.02, 0.0, 0.02
    LEND
; 23 SPIDER_SAY
    LAYER SND_SPIDER_SAY, W_NOISE, 0.0, 0.42, 1.0, 86.0, 86.0, 0.0
    VIB 1.0, 9.0, 0.0
    ENV 0.03, 0.2, 0.4, 0.10
    FILT 0.0, 2500.0
    LEND
    LAYER SND_SPIDER_SAY, W_PULSE, 0.0, 0.42, 0.35, 43.0, 41.0, 0.4
    DUTY 0.125, 0.125
    VIB 0.5, 9.0, 0.0
    ENV 0.03, 0.2, 0.4, 0.10
    FILT 900.0, 0.0
    LEND
; 24 SPIDER_HURT
    LAYER SND_SPIDER_HURT, W_PULSE, 0.0, 0.22, 1.0, 69.0, 57.0, 0.15
    DUTY 0.125, 0.125
    VIB 1.5, 24.0, 0.0
    ENV 0.0015, 0.07, 0.0, 0.05
    FILT 2500.0, 0.0
    LEND
    LAYER SND_SPIDER_HURT, W_NOISE, 0.0, 0.08, 0.4, 86.0, 86.0, 0.0
    ENV 0.0015, 0.02, 0.0, 0.02
    FILT 0.0, 2000.0
    LEND
; 25 CREEPER_HURT
    LAYER SND_CREEPER_HURT, W_NOISE, 0.0, 0.20, 1.0, 84.0, 74.0, 0.12
    ENV 0.0015, 0.05, 0.0, 0.05
    FILT 0.0, 900.0
    LEND
    LAYER SND_CREEPER_HURT, W_PULSE, 0.0, 0.18, 0.4, 55.0, 46.0, 0.15
    DUTY 0.25, 0.25
    VIB 0.8, 20.0, 0.0
    ENV 0.0015, 0.06, 0.0, 0.05
    FILT 1800.0, 0.0
    LEND
; 26 CHICKEN_SAY
    LAYER SND_CHICKEN_SAY, W_PULSE, 0.0, 0.06, 1.0, 91.0, 94.0, 0.04
    DUTY 0.125, 0.125
    ENV 0.0015, 0.02, 0.0, 0.02
    LEND
    LAYER SND_CHICKEN_SAY, W_PULSE, 0.09, 0.08, 1.0, 94.0, 88.0, 0.06
    DUTY 0.125, 0.125
    ENV 0.0015, 0.03, 0.0, 0.025
    LEND
; 27 CHICKEN_HURT
    LAYER SND_CHICKEN_HURT, W_PULSE, 0.0, 0.14, 1.0, 96.0, 84.0, 0.12
    DUTY 0.125, 0.125
    VIB 1.0, 35.0, 0.0
    ENV 0.0015, 0.05, 0.0, 0.04
    LEND
    LAYER SND_CHICKEN_HURT, W_NOISE, 0.0, 0.04, 0.3, 90.0, 90.0, 0.0
    ENV 0.0015, 0.01, 0.0, 0.012
    FILT 0.0, 3000.0
    LEND
; 28 PISTOL
    LAYER SND_PISTOL, W_NOISE, 0.0, 0.22, 1.0, 96.0, 80.0, 0.10
    ENV 0.0015, 0.04, 0.0, 0.06
    FILT 0.0, 400.0
    LEND
    LAYER SND_PISTOL, W_TRI, 0.0, 0.12, 0.8, 50.0, 30.0, 0.06
    ENV 0.0015, 0.04, 0.0, 0.04
    LEND
    LAYER SND_PISTOL, W_NOISE93, 0.0, 0.05, 0.3, 84.0, 84.0, 0.0
    ENV 0.0015, 0.012, 0.0, 0.015
    FILT 0.0, 2000.0
    LEND
; 29 MUSKET
    LAYER SND_MUSKET, W_NOISE, 0.0, 0.03, 0.4, 100.0, 100.0, 0.0
    ENV 0.0015, 0.008, 0.0, 0.01
    FILT 0.0, 3000.0
    LEND
    LAYER SND_MUSKET, W_NOISE, 0.0, 0.85, 1.0, 92.0, 66.0, 0.5
    ENV 0.002, 0.14, 0.0, 0.25
    FILT 7000.0, 0.0
    LEND
    LAYER SND_MUSKET, W_TRI, 0.0, 0.35, 0.9, 45.0, 26.0, 0.2
    ENV 0.0015, 0.10, 0.0, 0.10
    LEND
; 30 SHOTGUN
    LAYER SND_SHOTGUN, W_NOISE, 0.0, 0.55, 1.0, 94.0, 70.0, 0.3
    ENV 0.0015, 0.09, 0.0, 0.15
    FILT 8000.0, 0.0
    LEND
    LAYER SND_SHOTGUN, W_TRI, 0.0, 0.30, 1.0, 43.0, 26.0, 0.15
    ENV 0.0015, 0.08, 0.0, 0.08
    LEND
    LAYER SND_SHOTGUN, W_NOISE93, 0.0, 0.08, 0.3, 80.0, 80.0, 0.0
    ENV 0.0015, 0.02, 0.0, 0.02
    FILT 0.0, 1500.0
    LEND
; 31 RIFLE
    LAYER SND_RIFLE, W_NOISE, 0.0, 0.15, 1.0, 100.0, 88.0, 0.05
    ENV 0.0015, 0.02, 0.0, 0.04
    FILT 0.0, 800.0
    LEND
    LAYER SND_RIFLE, W_TRI, 0.0, 0.08, 0.6, 55.0, 36.0, 0.04
    ENV 0.0015, 0.025, 0.0, 0.03
    LEND
    LAYER SND_RIFLE, W_NOISE93, 0.0, 0.03, 0.25, 92.0, 92.0, 0.0
    ENV 0.0015, 0.008, 0.0, 0.01
    FILT 0.0, 3000.0
    LEND
    LAYER SND_RIFLE, W_NOISE, 0.02, 0.30, 0.3, 80.0, 66.0, 0.2
    ENV 0.0015, 0.07, 0.0, 0.08
    FILT 4000.0, 0.0
    LEND
; 32 LAUNCHER
    LAYER SND_LAUNCHER, W_TRI, 0.0, 0.20, 0.9, 45.0, 28.0, 0.15
    ENV 0.0015, 0.06, 0.0, 0.05
    LEND
    LAYER SND_LAUNCHER, W_NOISE, 0.0, 0.05, 0.4, 92.0, 92.0, 0.0
    ENV 0.0015, 0.015, 0.0, 0.015
    FILT 0.0, 2000.0
    LEND
    LAYER SND_LAUNCHER, W_NOISE, 0.0, 0.60, 0.7, 70.0, 90.0, 0.45
    ENV 0.10, 0.0, 1.0, 0.12
    FILT 6000.0, 300.0
    LEND
    LAYER SND_LAUNCHER, W_SAW, 0.0, 0.55, 0.25, 40.0, 60.0, 0.5
    ENV 0.08, 0.0, 1.0, 0.10
    FILT 1200.0, 0.0
    LEND
; 33 RELOAD
    LAYER SND_RELOAD, W_PULSE, 0.0, 0.04, 0.6, 93.0, 88.0, 0.02
    DUTY 0.125, 0.125
    ENV 0.0015, 0.01, 0.0, 0.015
    LEND
    LAYER SND_RELOAD, W_NOISE93, 0.0, 0.03, 1.0, 92.0, 92.0, 0.0
    ENV 0.0015, 0.008, 0.0, 0.01
    FILT 0.0, 2500.0
    LEND
    LAYER SND_RELOAD, W_PULSE, 0.12, 0.04, 0.6, 88.0, 84.0, 0.02
    DUTY 0.125, 0.125
    ENV 0.0015, 0.01, 0.0, 0.015
    LEND
    LAYER SND_RELOAD, W_NOISE93, 0.12, 0.03, 1.0, 88.0, 88.0, 0.0
    ENV 0.0015, 0.008, 0.0, 0.01
    FILT 0.0, 2500.0
    LEND
; 34 DRY_FIRE
    LAYER SND_DRY_FIRE, W_PULSE, 0.0, 0.035, 0.6, 95.0, 90.0, 0.02
    DUTY 0.125, 0.125
    ENV 0.0015, 0.008, 0.0, 0.015
    LEND
    LAYER SND_DRY_FIRE, W_NOISE93, 0.0, 0.025, 1.0, 94.0, 94.0, 0.0
    ENV 0.0015, 0.006, 0.0, 0.01
    FILT 0.0, 3000.0
    LEND
; 35 SWING
    LAYER SND_SWING, W_NOISE, 0.0, 0.17, 1.0, 72.0, 86.0, 0.10
    ENV 0.04, 0.0, 1.0, 0.10
    FILT 5000.0, 600.0
    LEND
; 36 PARRY
    LAYER SND_PARRY, W_NOISE93, 0.0, 0.04, 0.8, 96.0, 96.0, 0.0
    ENV 0.0015, 0.01, 0.0, 0.012
    FILT 0.0, 3000.0
    LEND
    LAYER SND_PARRY, W_PULSE, 0.0, 0.45, 1.0, 93.0, 93.0, 0.0
    DUTY 0.125, 0.125
    VIB 0.15, 7.0, 0.05
    ENV 0.0015, 0.09, 0.0, 0.10
    LEND
    LAYER SND_PARRY, W_PULSE, 0.0, 0.30, 0.4, 100.0, 100.0, 0.0
    DUTY 0.25, 0.25
    ENV 0.0015, 0.05, 0.0, 0.08
    LEND
    LAYER SND_PARRY, W_TRI, 0.0, 0.06, 0.5, 57.0, 45.0, 0.04
    ENV 0.0015, 0.02, 0.0, 0.02
    LEND
; 37 BLOCK
    LAYER SND_BLOCK, W_TRI, 0.0, 0.18, 1.0, 50.0, 36.0, 0.06
    ENV 0.0015, 0.05, 0.0, 0.05
    LEND
    LAYER SND_BLOCK, W_NOISE, 0.0, 0.15, 0.8, 76.0, 64.0, 0.08
    ENV 0.0015, 0.04, 0.0, 0.04
    FILT 2000.0, 120.0
    LEND
    LAYER SND_BLOCK, W_NOISE93, 0.0, 0.03, 0.3, 84.0, 84.0, 0.0
    ENV 0.0015, 0.008, 0.0, 0.01
    FILT 0.0, 1500.0
    LEND
; 38 DODGE
    LAYER SND_DODGE, W_NOISE, 0.0, 0.28, 1.0, 68.0, 80.0, 0.12
    ENV 0.08, 0.0, 1.0, 0.15
    FILT 3500.0, 300.0
    LEND
; 39 CRIT
    LAYER SND_CRIT, W_NOISE93, 0.0, 0.14, 0.7, 96.0, 84.0, 0.08
    ENV 0.0015, 0.03, 0.0, 0.04
    FILT 0.0, 1500.0
    LEND
    LAYER SND_CRIT, W_TRI, 0.0, 0.14, 0.9, 52.0, 33.0, 0.06
    ENV 0.0015, 0.04, 0.0, 0.04
    LEND
    LAYER SND_CRIT, W_PULSE, 0.0, 0.25, 0.35, 91.0, 91.0, 0.0
    DUTY 0.125, 0.125
    ARP 5.0, 12.0, 40.0
    ENV 0.0015, 0.07, 0.0, 0.08
    LEND
; 40 LEVELUP: motif M, sequenced up a step, ii-V-I to D6 (16th = 0.075 s)
    LAYER SND_LEVELUP, W_PULSE, 0.0, 0.075, 1.0, 74.0, 74.0, 0.0      ; lead
    DUTY 0.25, 0.25
    ENV 0.0015, 0.0, 1.0, 0.012
    LEND
    LAYER SND_LEVELUP, W_PULSE, 0.075, 0.075, 1.0, 76.0, 76.0, 0.0
    DUTY 0.25, 0.25
    ENV 0.0015, 0.0, 1.0, 0.012
    LEND
    LAYER SND_LEVELUP, W_PULSE, 0.15, 0.15, 1.0, 81.0, 81.0, 0.0
    DUTY 0.25, 0.25
    ENV 0.0015, 0.0, 1.0, 0.015
    LEND
    LAYER SND_LEVELUP, W_PULSE, 0.30, 0.075, 1.0, 76.0, 76.0, 0.0
    DUTY 0.25, 0.25
    ENV 0.0015, 0.0, 1.0, 0.012
    LEND
    LAYER SND_LEVELUP, W_PULSE, 0.375, 0.075, 1.0, 78.0, 78.0, 0.0
    DUTY 0.25, 0.25
    ENV 0.0015, 0.0, 1.0, 0.012
    LEND
    LAYER SND_LEVELUP, W_PULSE, 0.45, 0.15, 1.0, 83.0, 83.0, 0.0
    DUTY 0.25, 0.25
    ENV 0.0015, 0.0, 1.0, 0.015
    LEND
    LAYER SND_LEVELUP, W_PULSE, 0.60, 0.075, 1.0, 85.0, 85.0, 0.0
    DUTY 0.25, 0.25
    ENV 0.0015, 0.0, 1.0, 0.012
    LEND
    LAYER SND_LEVELUP, W_PULSE, 0.675, 0.55, 1.0, 86.0, 86.0, 0.0
    DUTY 0.25, 0.25
    ENV 0.0015, 0.18, 0.25, 0.15
    LEND
    LAYER SND_LEVELUP, W_PULSE, 0.075, 0.075, 0.35, 74.0, 74.0, 0.0   ; echo
    DUTY 0.125, 0.125
    ENV 0.0015, 0.0, 1.0, 0.012
    LEND
    LAYER SND_LEVELUP, W_PULSE, 0.15, 0.075, 0.35, 76.0, 76.0, 0.0
    DUTY 0.125, 0.125
    ENV 0.0015, 0.0, 1.0, 0.012
    LEND
    LAYER SND_LEVELUP, W_PULSE, 0.225, 0.15, 0.35, 81.0, 81.0, 0.0
    DUTY 0.125, 0.125
    ENV 0.0015, 0.0, 1.0, 0.015
    LEND
    LAYER SND_LEVELUP, W_PULSE, 0.375, 0.075, 0.35, 76.0, 76.0, 0.0
    DUTY 0.125, 0.125
    ENV 0.0015, 0.0, 1.0, 0.012
    LEND
    LAYER SND_LEVELUP, W_PULSE, 0.45, 0.075, 0.35, 78.0, 78.0, 0.0
    DUTY 0.125, 0.125
    ENV 0.0015, 0.0, 1.0, 0.012
    LEND
    LAYER SND_LEVELUP, W_PULSE, 0.525, 0.15, 0.35, 83.0, 83.0, 0.0
    DUTY 0.125, 0.125
    ENV 0.0015, 0.0, 1.0, 0.015
    LEND
    LAYER SND_LEVELUP, W_PULSE, 0.675, 0.075, 0.35, 85.0, 85.0, 0.0
    DUTY 0.125, 0.125
    ENV 0.0015, 0.0, 1.0, 0.012
    LEND
    LAYER SND_LEVELUP, W_PULSE, 0.75, 0.50, 0.35, 86.0, 86.0, 0.0
    DUTY 0.125, 0.125
    ENV 0.0015, 0.18, 0.25, 0.15
    LEND
    LAYER SND_LEVELUP, W_TRI, 0.0, 0.28, 1.0, 50.0, 50.0, 0.0         ; bass
    ENV 0.0015, 0.08, 0.0, 0.04
    LEND
    LAYER SND_LEVELUP, W_TRI, 0.30, 0.28, 1.0, 52.0, 52.0, 0.0
    ENV 0.0015, 0.08, 0.0, 0.04
    LEND
    LAYER SND_LEVELUP, W_TRI, 0.60, 0.07, 1.0, 45.0, 45.0, 0.0
    ENV 0.0015, 0.0, 1.0, 0.012
    LEND
    LAYER SND_LEVELUP, W_TRI, 0.675, 0.55, 1.0, 50.0, 50.0, 0.0
    ENV 0.0015, 0.18, 0.0, 0.15
    LEND
    LAYER SND_LEVELUP, W_PULSE, 0.675, 0.50, 0.22, 86.0, 86.0, 0.0    ; sparkle
    DUTY 0.125, 0.125
    ARP 4.0, 7.0, 50.0
    ENV 0.0015, 0.15, 0.0, 0.12
    LEND
; 41 SPELL
    LAYER SND_SPELL, W_PULSE, 0.0, 0.24, 1.0, 74.0, 98.0, 0.18
    DUTY 0.5, 0.125
    ARP 7.0, 0.0, 30.0
    ENV 0.004, 0.0, 1.0, 0.08
    LEND
    LAYER SND_SPELL, W_NOISE, 0.0, 0.20, 0.15, 90.0, 90.0, 0.0
    ENV 0.02, 0.0, 1.0, 0.10
    FILT 0.0, 4000.0
    LEND
; 42 FIREBALL
    LAYER SND_FIREBALL, W_NOISE, 0.0, 0.60, 1.0, 80.0, 62.0, 0.5
    VIB 1.5, 11.0, 0.0
    ENV 0.04, 0.25, 0.3, 0.15
    FILT 3500.0, 150.0
    LEND
    LAYER SND_FIREBALL, W_TRI, 0.0, 0.50, 0.5, 43.0, 36.0, 0.5
    ENV 0.04, 0.0, 1.0, 0.15
    LEND
; 43 BLINK
    LAYER SND_BLINK, W_PULSE, 0.0, 0.26, 1.0, 103.0, 79.0, 0.22
    DUTY 0.125, 0.125
    ARP 12.0, 0.0, 45.0
    ENV 0.002, 0.0, 1.0, 0.10
    LEND
    LAYER SND_BLINK, W_PULSE, 0.04, 0.24, 0.4, 96.0, 72.0, 0.22
    DUTY 0.25, 0.25
    ARP 12.0, 0.0, 45.0
    ENV 0.002, 0.0, 1.0, 0.10
    LEND
    LAYER SND_BLINK, W_NOISE, 0.0, 0.10, 0.3, 94.0, 94.0, 0.0
    ENV 0.0015, 0.03, 0.0, 0.03
    FILT 0.0, 4000.0
    LEND
; 44 WARCRY
    LAYER SND_WARCRY, W_SAW, 0.0, 0.70, 1.0, 47.0, 45.0, 0.6
    VIB 0.4, 6.0, 0.1
    ENV 0.05, 0.4, 0.5, 0.20
    FILT 2200.0, 0.0
    LEND
    LAYER SND_WARCRY, W_PULSE, 0.0, 0.70, 0.5, 54.0, 52.0, 0.6
    DUTY 0.25, 0.25
    VIB 0.4, 6.0, 0.1
    ENV 0.05, 0.4, 0.5, 0.20
    FILT 2200.0, 0.0
    LEND
    LAYER SND_WARCRY, W_NOISE, 0.0, 0.60, 0.3, 70.0, 70.0, 0.0
    ENV 0.05, 0.3, 0.3, 0.20
    FILT 1500.0, 200.0
    LEND
; 45 WHIRL
    LAYER SND_WHIRL, W_NOISE, 0.0, 0.28, 1.0, 66.0, 84.0, 0.2
    ENV 0.08, 0.0, 1.0, 0.15
    FILT 5000.0, 400.0
    LEND
    LAYER SND_WHIRL, W_NOISE, 0.22, 0.30, 1.0, 70.0, 88.0, 0.2
    ENV 0.08, 0.0, 1.0, 0.15
    FILT 5000.0, 400.0
    LEND
; 46 SMOKE
    LAYER SND_SMOKE, W_TRI, 0.0, 0.15, 0.6, 43.0, 34.0, 0.10
    ENV 0.0015, 0.04, 0.0, 0.04
    LEND
    LAYER SND_SMOKE, W_NOISE, 0.0, 0.70, 1.0, 86.0, 70.0, 0.6
    ENV 0.01, 0.2, 0.2, 0.25
    FILT 6000.0, 300.0
    LEND
; 47 COIN: M's leap landing on the tonic, A5 -> D6
    LAYER SND_COIN, W_PULSE, 0.0, 0.065, 1.0, 81.0, 81.0, 0.0
    DUTY 0.25, 0.25
    ENV 0.0015, 0.0, 1.0, 0.012
    LEND
    LAYER SND_COIN, W_PULSE, 0.065, 0.30, 1.0, 86.0, 86.0, 0.0
    DUTY 0.25, 0.25
    ENV 0.0015, 0.08, 0.0, 0.06
    LEND
    LAYER SND_COIN, W_PULSE, 0.14, 0.25, 0.3, 86.0, 86.0, 0.0         ; echo
    DUTY 0.125, 0.125
    ENV 0.0015, 0.07, 0.0, 0.06
    LEND
; 48 QUEST: M plain, D5 E5 A5 F#5, closing on the 3rd over I
    LAYER SND_QUEST, W_PULSE, 0.0, 0.075, 1.0, 74.0, 74.0, 0.0        ; lead
    DUTY 0.25, 0.25
    ENV 0.0015, 0.0, 1.0, 0.012
    LEND
    LAYER SND_QUEST, W_PULSE, 0.075, 0.075, 1.0, 76.0, 76.0, 0.0
    DUTY 0.25, 0.25
    ENV 0.0015, 0.0, 1.0, 0.012
    LEND
    LAYER SND_QUEST, W_PULSE, 0.15, 0.15, 1.0, 81.0, 81.0, 0.0
    DUTY 0.25, 0.25
    ENV 0.0015, 0.0, 1.0, 0.015
    LEND
    LAYER SND_QUEST, W_PULSE, 0.30, 0.45, 1.0, 78.0, 78.0, 0.0
    DUTY 0.25, 0.25
    ENV 0.0015, 0.15, 0.3, 0.12
    LEND
    LAYER SND_QUEST, W_PULSE, 0.075, 0.075, 0.35, 74.0, 74.0, 0.0     ; echo
    DUTY 0.125, 0.125
    ENV 0.0015, 0.0, 1.0, 0.012
    LEND
    LAYER SND_QUEST, W_PULSE, 0.15, 0.075, 0.35, 76.0, 76.0, 0.0
    DUTY 0.125, 0.125
    ENV 0.0015, 0.0, 1.0, 0.012
    LEND
    LAYER SND_QUEST, W_PULSE, 0.225, 0.15, 0.35, 81.0, 81.0, 0.0
    DUTY 0.125, 0.125
    ENV 0.0015, 0.0, 1.0, 0.015
    LEND
    LAYER SND_QUEST, W_PULSE, 0.375, 0.40, 0.35, 78.0, 78.0, 0.0
    DUTY 0.125, 0.125
    ENV 0.0015, 0.15, 0.3, 0.12
    LEND
    LAYER SND_QUEST, W_TRI, 0.0, 0.14, 1.0, 50.0, 50.0, 0.0           ; bass
    ENV 0.0015, 0.06, 0.0, 0.03
    LEND
    LAYER SND_QUEST, W_TRI, 0.15, 0.14, 1.0, 45.0, 45.0, 0.0
    ENV 0.0015, 0.06, 0.0, 0.03
    LEND
    LAYER SND_QUEST, W_TRI, 0.30, 0.45, 1.0, 50.0, 50.0, 0.0
    ENV 0.0015, 0.15, 0.0, 0.10
    LEND
; 49 BOSS_ROAR
    LAYER SND_BOSS_ROAR, W_SAW, 0.0, 1.60, 1.0, 38.0, 33.0, 1.2
    VIB 0.7, 6.0, 0.0
    ENV 0.12, 0.7, 0.5, 0.35
    FILT 1500.0, 0.0
    LEND
    LAYER SND_BOSS_ROAR, W_PULSE, 0.0, 1.60, 0.5, 45.0, 40.0, 1.2
    DUTY 0.125, 0.125
    VIB 1.0, 7.0, 0.0
    ENV 0.12, 0.7, 0.5, 0.35
    FILT 1500.0, 0.0
    LEND
    LAYER SND_BOSS_ROAR, W_NOISE, 0.0, 1.50, 0.5, 66.0, 56.0, 1.2
    ENV 0.10, 0.6, 0.4, 0.35
    FILT 1800.0, 80.0
    LEND
    LAYER SND_BOSS_ROAR, W_NOISE93, 0.0, 1.40, 0.15, 60.0, 60.0, 0.0
    ENV 0.10, 0.6, 0.4, 0.35
    FILT 1200.0, 0.0
    LEND
; 50 SLAM
    LAYER SND_SLAM, W_TRI, 0.0, 0.70, 1.0, 40.0, 24.0, 0.3
    ENV 0.0015, 0.16, 0.0, 0.20
    LEND
    LAYER SND_SLAM, W_NOISE, 0.0, 0.80, 0.9, 84.0, 56.0, 0.5
    ENV 0.0015, 0.15, 0.0, 0.25
    FILT 4000.0, 0.0
    LEND
    LAYER SND_SLAM, W_NOISE93, 0.0, 0.12, 0.35, 76.0, 76.0, 0.0
    ENV 0.0015, 0.03, 0.0, 0.03
    FILT 0.0, 800.0
    LEND
; 51 VILLAGER
    LAYER SND_VILLAGER, W_PULSE, 0.0, 0.30, 1.0, 52.0, 48.0, 0.3
    DUTY 0.25, 0.25
    VIB 0.6, 8.0, 0.0
    ENV 0.02, 0.15, 0.5, 0.08
    FILT 1400.0, 0.0
    LEND
    LAYER SND_VILLAGER, W_PULSE, 0.0, 0.30, 0.25, 64.0, 60.0, 0.3
    DUTY 0.25, 0.25
    VIB 0.6, 8.0, 0.0
    ENV 0.02, 0.15, 0.5, 0.08
    FILT 1400.0, 0.0
    LEND
; 52 DRINK: three gulps over a liquid bed
    LAYER SND_DRINK, W_PULSE, 0.0, 0.07, 1.0, 55.0, 62.0, 0.06
    ENV 0.004, 0.03, 0.0, 0.025
    FILT 1200.0, 0.0
    LEND
    LAYER SND_DRINK, W_PULSE, 0.10, 0.07, 1.0, 53.0, 60.0, 0.06
    ENV 0.004, 0.03, 0.0, 0.025
    FILT 1200.0, 0.0
    LEND
    LAYER SND_DRINK, W_PULSE, 0.20, 0.07, 1.0, 51.0, 58.0, 0.06
    ENV 0.004, 0.03, 0.0, 0.025
    FILT 1200.0, 0.0
    LEND
    LAYER SND_DRINK, W_NOISE, 0.0, 0.27, 0.25, 64.0, 64.0, 0.0
    ENV 0.02, 0.10, 0.3, 0.06
    FILT 900.0, 100.0
    LEND
; 53 DOOR_OPEN: latch click, knock, creak
    LAYER SND_DOOR_OPEN, W_NOISE93, 0.0, 0.03, 1.0, 86.0, 86.0, 0.0
    ENV 0.0015, 0.008, 0.0, 0.01
    FILT 0.0, 2000.0
    LEND
    LAYER SND_DOOR_OPEN, W_TRI, 0.0, 0.08, 0.5, 50.0, 45.0, 0.05
    ENV 0.0015, 0.025, 0.0, 0.025
    LEND
    LAYER SND_DOOR_OPEN, W_PULSE, 0.0, 0.25, 0.6, 55.0, 58.0, 0.2
    DUTY 0.125, 0.125
    VIB 0.4, 23.0, 0.0
    ENV 0.02, 0.10, 0.4, 0.06
    FILT 1500.0, 0.0
    LEND
; 54 DOOR_CLOSE: thud and latch
    LAYER SND_DOOR_CLOSE, W_TRI, 0.0, 0.15, 1.0, 47.0, 36.0, 0.05
    ENV 0.0015, 0.04, 0.0, 0.04
    LEND
    LAYER SND_DOOR_CLOSE, W_NOISE, 0.0, 0.12, 0.7, 74.0, 64.0, 0.06
    ENV 0.0015, 0.03, 0.0, 0.03
    FILT 2500.0, 150.0
    LEND
    LAYER SND_DOOR_CLOSE, W_NOISE93, 0.02, 0.03, 0.5, 86.0, 86.0, 0.0
    ENV 0.0015, 0.008, 0.0, 0.01
    FILT 0.0, 2000.0
    LEND
; 55 FREEZE: five metallic ice ticks and two glassy pings
    LAYER SND_FREEZE, W_NOISE93, 0.0, 0.04, 0.8, 92.0, 92.0, 0.0
    ENV 0.0015, 0.01, 0.0, 0.012
    FILT 0.0, 3000.0
    LEND
    LAYER SND_FREEZE, W_NOISE93, 0.07, 0.04, 0.8, 96.0, 96.0, 0.0
    ENV 0.0015, 0.01, 0.0, 0.012
    FILT 0.0, 3000.0
    LEND
    LAYER SND_FREEZE, W_NOISE93, 0.12, 0.04, 0.8, 90.0, 90.0, 0.0
    ENV 0.0015, 0.01, 0.0, 0.012
    FILT 0.0, 3000.0
    LEND
    LAYER SND_FREEZE, W_NOISE93, 0.19, 0.04, 0.8, 94.0, 94.0, 0.0
    ENV 0.0015, 0.01, 0.0, 0.012
    FILT 0.0, 3000.0
    LEND
    LAYER SND_FREEZE, W_NOISE93, 0.23, 0.04, 0.8, 88.0, 88.0, 0.0
    ENV 0.0015, 0.01, 0.0, 0.012
    FILT 0.0, 3000.0
    LEND
    LAYER SND_FREEZE, W_PULSE, 0.02, 0.20, 0.3, 100.0, 100.0, 0.0
    DUTY 0.125, 0.125
    ENV 0.0015, 0.06, 0.0, 0.06
    LEND
    LAYER SND_FREEZE, W_PULSE, 0.10, 0.20, 0.22, 105.0, 105.0, 0.0
    DUTY 0.125, 0.125
    ENV 0.0015, 0.05, 0.0, 0.06
    LEND
; 56 HEAVY: whoosh swelling into a thud
    LAYER SND_HEAVY, W_NOISE, 0.0, 0.12, 0.7, 64.0, 78.0, 0.10
    ENV 0.06, 0.0, 1.0, 0.04
    FILT 3000.0, 200.0
    LEND
    LAYER SND_HEAVY, W_TRI, 0.09, 0.20, 1.0, 45.0, 26.0, 0.10
    ENV 0.0015, 0.05, 0.0, 0.05
    LEND
    LAYER SND_HEAVY, W_NOISE, 0.09, 0.16, 0.7, 78.0, 62.0, 0.10
    ENV 0.0015, 0.04, 0.0, 0.04
    FILT 2500.0, 0.0
    LEND
; 57 KNIVES: four swishes, each a little higher
    LAYER SND_KNIVES, W_NOISE, 0.0, 0.10, 1.0, 76.0, 90.0, 0.08
    ENV 0.02, 0.0, 1.0, 0.06
    FILT 7000.0, 1200.0
    LEND
    LAYER SND_KNIVES, W_NOISE, 0.06, 0.10, 1.0, 78.0, 92.0, 0.08
    ENV 0.02, 0.0, 1.0, 0.06
    FILT 7000.0, 1200.0
    LEND
    LAYER SND_KNIVES, W_NOISE, 0.12, 0.10, 1.0, 80.0, 94.0, 0.08
    ENV 0.02, 0.0, 1.0, 0.06
    FILT 7000.0, 1200.0
    LEND
    LAYER SND_KNIVES, W_NOISE, 0.18, 0.10, 1.0, 82.0, 96.0, 0.08
    ENV 0.02, 0.0, 1.0, 0.06
    FILT 7000.0, 1200.0
    LEND
; 58 LOOT_RARE: M's head on the dominant, open (A5 B5 E6)
    LAYER SND_LOOT_RARE, W_PULSE, 0.0, 0.075, 1.0, 81.0, 81.0, 0.0    ; lead
    DUTY 0.25, 0.25
    ENV 0.0015, 0.0, 1.0, 0.012
    LEND
    LAYER SND_LOOT_RARE, W_PULSE, 0.075, 0.075, 1.0, 83.0, 83.0, 0.0
    DUTY 0.25, 0.25
    ENV 0.0015, 0.0, 1.0, 0.012
    LEND
    LAYER SND_LOOT_RARE, W_PULSE, 0.15, 0.40, 1.0, 88.0, 88.0, 0.0
    DUTY 0.25, 0.25
    ENV 0.0015, 0.12, 0.0, 0.10
    LEND
    LAYER SND_LOOT_RARE, W_PULSE, 0.075, 0.075, 0.35, 81.0, 81.0, 0.0 ; echo
    DUTY 0.125, 0.125
    ENV 0.0015, 0.0, 1.0, 0.012
    LEND
    LAYER SND_LOOT_RARE, W_PULSE, 0.15, 0.075, 0.35, 83.0, 83.0, 0.0
    DUTY 0.125, 0.125
    ENV 0.0015, 0.0, 1.0, 0.012
    LEND
    LAYER SND_LOOT_RARE, W_PULSE, 0.225, 0.35, 0.35, 88.0, 88.0, 0.0
    DUTY 0.125, 0.125
    ENV 0.0015, 0.10, 0.0, 0.10
    LEND
    LAYER SND_LOOT_RARE, W_TRI, 0.0, 0.30, 0.8, 57.0, 57.0, 0.0       ; bass
    ENV 0.0015, 0.10, 0.0, 0.06
    LEND
    LAYER SND_LOOT_RARE, W_PULSE, 0.15, 0.40, 0.22, 81.0, 81.0, 0.0   ; sparkle
    DUTY 0.125, 0.125
    ARP 4.0, 7.0, 50.0
    ENV 0.0015, 0.12, 0.0, 0.10
    LEND
; 59 LEGENDARY: M augmented (16th = 0.065 s) + IV-V-I, octave-bounce bass
    LAYER SND_LEGENDARY, W_PULSE, 0.0, 0.13, 1.0, 74.0, 74.0, 0.0     ; lead
    DUTY 0.25, 0.25
    ENV 0.0015, 0.0, 1.0, 0.015
    LEND
    LAYER SND_LEGENDARY, W_PULSE, 0.13, 0.13, 1.0, 76.0, 76.0, 0.0
    DUTY 0.25, 0.25
    ENV 0.0015, 0.0, 1.0, 0.015
    LEND
    LAYER SND_LEGENDARY, W_PULSE, 0.26, 0.26, 1.0, 81.0, 81.0, 0.0
    DUTY 0.25, 0.25
    ENV 0.0015, 0.2, 0.6, 0.02
    LEND
    LAYER SND_LEGENDARY, W_PULSE, 0.52, 0.26, 1.0, 78.0, 78.0, 0.0
    DUTY 0.25, 0.25
    ENV 0.0015, 0.2, 0.6, 0.02
    LEND
    LAYER SND_LEGENDARY, W_PULSE, 0.78, 0.13, 1.0, 79.0, 79.0, 0.0
    DUTY 0.25, 0.25
    ENV 0.0015, 0.0, 1.0, 0.015
    LEND
    LAYER SND_LEGENDARY, W_PULSE, 0.91, 0.13, 1.0, 81.0, 81.0, 0.0
    DUTY 0.25, 0.25
    ENV 0.0015, 0.0, 1.0, 0.015
    LEND
    LAYER SND_LEGENDARY, W_PULSE, 1.04, 0.60, 1.0, 86.0, 86.0, 0.0
    DUTY 0.25, 0.25
    ENV 0.0015, 0.22, 0.3, 0.18
    LEND
    LAYER SND_LEGENDARY, W_PULSE, 0.065, 0.13, 0.35, 74.0, 74.0, 0.0  ; echo
    DUTY 0.125, 0.125
    ENV 0.0015, 0.0, 1.0, 0.015
    LEND
    LAYER SND_LEGENDARY, W_PULSE, 0.195, 0.13, 0.35, 76.0, 76.0, 0.0
    DUTY 0.125, 0.125
    ENV 0.0015, 0.0, 1.0, 0.015
    LEND
    LAYER SND_LEGENDARY, W_PULSE, 0.325, 0.26, 0.35, 81.0, 81.0, 0.0
    DUTY 0.125, 0.125
    ENV 0.0015, 0.2, 0.6, 0.02
    LEND
    LAYER SND_LEGENDARY, W_PULSE, 0.585, 0.26, 0.35, 78.0, 78.0, 0.0
    DUTY 0.125, 0.125
    ENV 0.0015, 0.2, 0.6, 0.02
    LEND
    LAYER SND_LEGENDARY, W_PULSE, 0.845, 0.13, 0.35, 79.0, 79.0, 0.0
    DUTY 0.125, 0.125
    ENV 0.0015, 0.0, 1.0, 0.015
    LEND
    LAYER SND_LEGENDARY, W_PULSE, 0.975, 0.13, 0.35, 81.0, 81.0, 0.0
    DUTY 0.125, 0.125
    ENV 0.0015, 0.0, 1.0, 0.015
    LEND
    LAYER SND_LEGENDARY, W_PULSE, 1.105, 0.55, 0.35, 86.0, 86.0, 0.0
    DUTY 0.125, 0.125
    ENV 0.0015, 0.22, 0.3, 0.18
    LEND
    LAYER SND_LEGENDARY, W_TRI, 0.0, 0.12, 1.0, 50.0, 50.0, 0.0       ; bass
    ENV 0.0015, 0.05, 0.0, 0.02
    LEND
    LAYER SND_LEGENDARY, W_TRI, 0.13, 0.12, 1.0, 38.0, 38.0, 0.0
    ENV 0.0015, 0.05, 0.0, 0.02
    LEND
    LAYER SND_LEGENDARY, W_TRI, 0.26, 0.12, 1.0, 50.0, 50.0, 0.0
    ENV 0.0015, 0.05, 0.0, 0.02
    LEND
    LAYER SND_LEGENDARY, W_TRI, 0.39, 0.12, 1.0, 38.0, 38.0, 0.0
    ENV 0.0015, 0.05, 0.0, 0.02
    LEND
    LAYER SND_LEGENDARY, W_TRI, 0.52, 0.12, 1.0, 50.0, 50.0, 0.0
    ENV 0.0015, 0.05, 0.0, 0.02
    LEND
    LAYER SND_LEGENDARY, W_TRI, 0.65, 0.12, 1.0, 38.0, 38.0, 0.0
    ENV 0.0015, 0.05, 0.0, 0.02
    LEND
    LAYER SND_LEGENDARY, W_TRI, 0.78, 0.12, 1.0, 43.0, 43.0, 0.0
    ENV 0.0015, 0.05, 0.0, 0.02
    LEND
    LAYER SND_LEGENDARY, W_TRI, 0.91, 0.12, 1.0, 45.0, 45.0, 0.0
    ENV 0.0015, 0.05, 0.0, 0.02
    LEND
    LAYER SND_LEGENDARY, W_TRI, 1.04, 0.60, 1.0, 50.0, 50.0, 0.0
    ENV 0.0015, 0.2, 0.0, 0.18
    LEND
    LAYER SND_LEGENDARY, W_PULSE, 1.04, 0.55, 0.22, 86.0, 86.0, 0.0   ; sparkle
    DUTY 0.125, 0.125
    ARP 4.0, 7.0, 50.0
    ENV 0.0015, 0.15, 0.0, 0.12
    LEND
    LAYER SND_LEGENDARY, W_NOISE93, 1.04, 0.05, 0.25, 96.0, 96.0, 0.0
    ENV 0.0015, 0.012, 0.0, 0.02
    FILT 0.0, 4000.0
    LEND
layers_end:

section .bss
alignb 16
sfx_table: resd NUM_SOUNDS * 2          ; per sound id: dd offset, dd length (samples)
sfx_rng:   resd 1                       ; private xorshift32 state, seeds the noise LFSRs
alignb 16
sfx_pool:  resw POOL_SAMPLES            ; all sounds, back to back
sfx_acc:   resd SOUND_MAX_SAMPLES       ; float mix of the sound being built

section .text

; sfx_build(): render every sound into sfx_pool, normalised to its sfx_info[id].level loudness under
; a -0.5 dBFS peak ceiling, and fill sfx_table. Safe to call again (same output).
sfx_build:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     dword [sfx_rng], 0xC0FFEE11
    lea     r14, [layers]               ; first layer of the current sound
    xor     r12d, r12d                  ; sound id
    xor     r13d, r13d                  ; pool offset, samples
.sound:
    xorps   xmm0, xmm0                  ; longest layer end, seconds
    mov     rax, r14
    lea     rcx, [layers_end]
.scan:
    cmp     rax, rcx
    jae     .scanned
    cmp     dword [rax + SFXLAYER.sound], r12d
    jne     .scanned
    movss   xmm1, [rax + SFXLAYER.start]
    addss   xmm1, [rax + SFXLAYER.dur]
    maxss   xmm0, xmm1
    add     rax, SFXLAYER_size
    jmp     .scan
.scanned:
    mov     r15, rax                    ; first layer of the next sound
    mulss   xmm0, [c_rate]
    subss   xmm0, [c_ceil_tol]
    roundss xmm0, xmm0, 10              ; ceil
    cvttss2si ebx, xmm0                 ; ebx = length in samples
    mov     eax, SOUND_MAX_SAMPLES
    cmp     ebx, eax
    cmova   ebx, eax
    mov     eax, POOL_SAMPLES
    sub     eax, r13d
    cmp     ebx, eax
    cmova   ebx, eax                    ; never past the end of the pool
    lea     rax, [sfx_table]
    mov     [rax + r12*8], r13d
    mov     [rax + r12*8 + 4], ebx
    lea     rdi, [sfx_acc]              ; clear the accumulator
    mov     ecx, ebx
    xor     eax, eax
    rep     stosd
.layer:
    cmp     r14, r15
    jae     .peak
    mov     rdi, r14
    lea     rsi, [sfx_acc]
    mov     edx, ebx
    call    render_layer
    add     r14, SFXLAYER_size
    jmp     .layer
.peak:                                  ; xmm1 = max |acc|
    lea     rsi, [sfx_acc]
    xorps   xmm1, xmm1
    movss   xmm3, [c_abs]
    xor     ecx, ecx
.peak_loop:
    cmp     ecx, ebx
    jae     .scale
    movss   xmm0, [rsi + rcx*4]
    andps   xmm0, xmm3
    maxss   xmm1, xmm0
    inc     ecx
    jmp     .peak_loop
.scale:                                 ; xmm2 = min(level / sqrt(loudest 100 ms mean square),
    movss   [rsp], xmm1                 ;            peak ceiling / peak); 1 for a silent sound
    movss   xmm2, [c_one]
    xorps   xmm0, xmm0
    ucomiss xmm1, xmm0
    jbe     .pack
    lea     rsi, [sfx_acc]
    mov     edx, ebx
    call    kweight_ms
    sqrtss  xmm0, xmm0
    lea     rax, [sfx_info]
    movzx   eax, word [rax + r12*SFXINFO_size + SFXINFO.level]
    cvtsi2ss xmm2, eax
    divss   xmm2, xmm0
    movss   xmm0, [c_peak_max]
    divss   xmm0, [rsp]
    minss   xmm2, xmm0
    lea     rsi, [sfx_acc]
.pack:                                  ; float * scale -> clamped int16 at pool + offset
    lea     rdi, [sfx_pool]
    lea     rdi, [rdi + r13*2]
    xor     ecx, ecx
.pack_loop:
    cmp     ecx, ebx
    jae     .packed
    movss   xmm0, [rsi + rcx*4]
    mulss   xmm0, xmm2
    minss   xmm0, [c_pmax]
    maxss   xmm0, [c_pmin]
    cvtss2si eax, xmm0
    mov     [rdi + rcx*2], ax
    inc     ecx
    jmp     .pack_loop
.packed:
    add     r13d, ebx
    inc     r12d
    cmp     r12d, NUM_SOUNDS
    jb      .sound
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; kweight_ms(rsi float x[], edx len) -> xmm0: the largest mean square of the K-weighted signal over
; a 100 ms window (10 blocks of 441 samples, 10 ms hops); a sound under 100 ms counts as padded with
; silence to 100 ms. Leaf, in doubles. Clobbers xmm0..xmm11, rax, rcx, rdx, r8..r11.
kweight_ms:
    sub     rsp, 88                     ; [rsp] ring of the last 10 block energies
    mov     r11d, edx                   ; len
    xor     eax, eax
.zero:
    mov     qword [rsp + rax*8], 0
    inc     eax
    cmp     eax, 10
    jb      .zero
    lea     eax, [r11 + 440]
    xor     edx, edx
    mov     ecx, 441
    div     ecx                         ; blocks in the sound, rounded up
    mov     ecx, 10
    cmp     eax, ecx
    cmovb   eax, ecx
    imul    r10d, eax, 441              ; samples to run, padding included
    xorpd   xmm2, xmm2                  ; shelf input x[n-1], x[n-2]
    xorpd   xmm3, xmm3
    xorpd   xmm4, xmm4                  ; shelf output y[n-1], y[n-2]: also the high-pass's input history
    xorpd   xmm5, xmm5
    xorpd   xmm6, xmm6                  ; high-pass output z[n-1], z[n-2]
    xorpd   xmm7, xmm7
    xorpd   xmm10, xmm10                ; energy of the current block
    xorpd   xmm11, xmm11                ; largest window sum
    xor     ecx, ecx                    ; n
    xor     r8d, r8d                    ; samples into the block
    xor     r9d, r9d                    ; ring slot of the next block
    xor     edx, edx                    ; blocks done
.sample:
    cmp     ecx, r10d
    jae     .done
    xorpd   xmm0, xmm0                  ; x = n < len ? x[n] : 0
    cmp     ecx, r11d
    jae     .filter
    cvtss2sd xmm0, [rsi + rcx*4]
.filter:
    movapd  xmm1, xmm0                  ; y = b0 x + b1 x1 + b2 x2 - a1 y1 - a2 y2
    mulsd   xmm1, [k_b0]
    movapd  xmm8, xmm2
    mulsd   xmm8, [k_b1]
    addsd   xmm1, xmm8
    movapd  xmm8, xmm3
    mulsd   xmm8, [k_b2]
    addsd   xmm1, xmm8
    movapd  xmm8, xmm4
    mulsd   xmm8, [k_a1]
    subsd   xmm1, xmm8
    movapd  xmm8, xmm5
    mulsd   xmm8, [k_a2]
    subsd   xmm1, xmm8
    movapd  xmm9, xmm1                  ; z = c0 y + c1 y1 + c2 y2 - d1 z1 - d2 z2
    mulsd   xmm9, [k_c0]
    movapd  xmm8, xmm4
    mulsd   xmm8, [k_c1]
    addsd   xmm9, xmm8
    movapd  xmm8, xmm5
    mulsd   xmm8, [k_c2]
    addsd   xmm9, xmm8
    movapd  xmm8, xmm6
    mulsd   xmm8, [k_d1]
    subsd   xmm9, xmm8
    movapd  xmm8, xmm7
    mulsd   xmm8, [k_d2]
    subsd   xmm9, xmm8
    movapd  xmm3, xmm2                  ; shift the histories
    movapd  xmm2, xmm0
    movapd  xmm5, xmm4
    movapd  xmm4, xmm1
    movapd  xmm7, xmm6
    movapd  xmm6, xmm9
    mulsd   xmm9, xmm9
    addsd   xmm10, xmm9
    inc     ecx
    inc     r8d
    cmp     r8d, 441
    jb      .sample
    xor     r8d, r8d                    ; block done: into the ring, then the window sum
    movsd   [rsp + r9*8], xmm10
    xorpd   xmm10, xmm10
    inc     r9d
    cmp     r9d, 10
    jb      .slot
    xor     r9d, r9d
.slot:
    inc     edx
    cmp     edx, 10
    jb      .sample
    xorpd   xmm0, xmm0
    xor     eax, eax
.sum:
    addsd   xmm0, [rsp + rax*8]
    inc     eax
    cmp     eax, 10
    jb      .sum
    maxsd   xmm11, xmm0
    jmp     .sample
.done:
    mulsd   xmm11, [c_inv_4410]
    cvtsd2ss xmm0, xmm11
    add     rsp, 88
    ret

; blep(xmm0 p, xmm1 dt) -> xmm0: polyBLEP residual of a unit upward step at phase 0. Leaf;
; clobbers xmm2 only.
blep:
    ucomiss xmm0, xmm1
    jae     .late
    divss   xmm0, xmm1                  ; x = p / dt
    movaps  xmm2, xmm0
    mulss   xmm2, xmm0
    addss   xmm0, xmm0
    subss   xmm0, xmm2
    subss   xmm0, [c_one]               ; 2x - x^2 - 1
    ret
.late:
    movss   xmm2, [c_one]
    subss   xmm2, xmm1
    ucomiss xmm0, xmm2
    jbe     .zero                       ; p <= 1 - dt: away from the edge
    subss   xmm0, [c_one]
    divss   xmm0, xmm1                  ; x = (p - 1) / dt
    movaps  xmm2, xmm0
    mulss   xmm2, xmm0
    addss   xmm0, xmm0
    addss   xmm0, xmm2
    addss   xmm0, [c_one]               ; x^2 + 2x + 1
    ret
.zero:
    xorps   xmm0, xmm0
    ret

; render_layer(rdi SFXLAYER*, rsi float acc[], edx len): add one layer, scaled by its amp, into
; acc[0..len). Pitch, duty and the oscillator step are recomputed every 32 samples (the chip's
; control tick) and held between ticks. Leaves the x87 stack empty.
; Loop state: xmm8 phase, xmm9 step per sample, xmm10 duty, xmm11 high-pass state, xmm12 low-pass
; state, xmm13 decay value, xmm14 noise clock accumulator, xmm15 amp; r14d LFSR, r15d sample.
%define RL_ATTACK  0                    ; [rsp + ...] locals
%define RL_RELEASE 4
%define RL_LP      8                    ; one-pole coefficients, 0 = off
%define RL_HP      12
%define RL_K       16                   ; per-sample decay factor
%define RL_TICK    20                   ; samples until the next control tick, mod 32
%define RL_T       24                   ; t of the current sample
%define RL_TAP     28                   ; LFSR feedback tap: 1 long, 6 short
render_layer:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40
    mov     rbx, rdi                    ; layer
    mov     r12, rsi                    ; acc
    mov     r13d, edx                   ; len
    movss   xmm0, [rbx + SFXLAYER.attack]
    maxss   xmm0, [c_att_min]
    movss   [rsp + RL_ATTACK], xmm0
    movss   xmm0, [rbx + SFXLAYER.release]
    maxss   xmm0, [c_rel_min]
    movss   [rsp + RL_RELEASE], xmm0
    xorps   xmm1, xmm1
    movss   [rsp + RL_LP], xmm1
    movss   [rsp + RL_HP], xmm1
    movss   xmm0, [rbx + SFXLAYER.lp_hz]    ; a = 1 - 2^(-fc * 2.0555e-4)
    ucomiss xmm0, xmm1
    jbe     .no_lp
    mulss   xmm0, [c_fc]
    call    exp2_ss
    movss   xmm1, [c_one]
    subss   xmm1, xmm0
    movss   [rsp + RL_LP], xmm1
.no_lp:
    movss   xmm0, [rbx + SFXLAYER.hp_hz]
    xorps   xmm1, xmm1
    ucomiss xmm0, xmm1
    jbe     .no_hp
    mulss   xmm0, [c_fc]
    call    exp2_ss
    movss   xmm1, [c_one]
    subss   xmm1, xmm0
    movss   [rsp + RL_HP], xmm1
.no_hp:
    movss   xmm1, [c_one]               ; k = 2^(-1 / (decay * 44100)), 1 without decay
    movss   [rsp + RL_K], xmm1
    movss   xmm1, [rbx + SFXLAYER.decay]
    xorps   xmm0, xmm0
    ucomiss xmm1, xmm0
    jbe     .no_decay
    mulss   xmm1, [c_rate]
    movss   xmm0, [c_mone]
    divss   xmm0, xmm1
    call    exp2_ss
    movss   [rsp + RL_K], xmm0
.no_decay:
    mov     dword [rsp + RL_TICK], 0
    mov     dword [rsp + RL_TAP], 1
    xor     r14d, r14d
    mov     eax, [rbx + SFXLAYER.wave]
    cmp     eax, W_NOISE
    jb      .state
    cmp     eax, W_NOISE93
    jne     .seed
    mov     dword [rsp + RL_TAP], 6
.seed:                                  ; LFSR = (next sfx_rng & 0x7FFF) | 1
    mov     eax, [sfx_rng]
    mov     edx, eax
    shl     edx, 13
    xor     eax, edx
    mov     edx, eax
    shr     edx, 17
    xor     eax, edx
    mov     edx, eax
    shl     edx, 5
    xor     eax, edx
    mov     [sfx_rng], eax
    and     eax, 0x7FFF
    or      eax, 1
    mov     r14d, eax
.state:
    xorps   xmm8, xmm8
    xorps   xmm9, xmm9
    movss   xmm10, [c_half]
    xorps   xmm11, xmm11
    xorps   xmm12, xmm12
    movss   xmm13, [c_one]
    xorps   xmm14, xmm14
    movss   xmm15, [rbx + SFXLAYER.amp]
    xor     r15d, r15d
.loop:
    cmp     r15d, r13d
    jae     .done
    cvtsi2ss xmm0, r15d
    mulss   xmm0, [c_inv_rate]
    subss   xmm0, [rbx + SFXLAYER.start] ; xmm0 = t
    xorps   xmm1, xmm1
    ucomiss xmm0, xmm1
    jb      .next                       ; not started yet
    ucomiss xmm0, [rbx + SFXLAYER.dur]
    jae     .done                       ; over (t only grows)
    movss   [rsp + RL_T], xmm0
    mov     eax, [rsp + RL_TICK]
    lea     ecx, [rax + 1]
    and     ecx, 31
    mov     [rsp + RL_TICK], ecx
    test    eax, eax
    jnz     .osc
    ; ---- control tick: note = glide + arpeggio + vibrato, then step and duty ----
    movss   xmm1, [rbx + SFXLAYER.note0]
    movss   xmm2, [rbx + SFXLAYER.glide]
    xorps   xmm3, xmm3
    ucomiss xmm2, xmm3
    jbe     .no_glide
    movaps  xmm4, xmm0
    divss   xmm4, xmm2
    minss   xmm4, [c_one]               ; min(1, t / glide)
    movss   xmm5, [rbx + SFXLAYER.note1]
    subss   xmm5, xmm1
    mulss   xmm5, xmm4
    addss   xmm1, xmm5
.no_glide:
    movss   xmm2, [rbx + SFXLAYER.arp_hz]
    ucomiss xmm2, xmm3
    jbe     .no_arp
    mulss   xmm2, xmm0
    cvttss2si eax, xmm2                 ; floor(t * arp_hz), t >= 0
    mov     ecx, 2
    ucomiss xmm3, [rbx + SFXLAYER.arp2]
    je      .arp_k
    mov     ecx, 3
.arp_k:
    xor     edx, edx
    div     ecx                         ; edx = step mod k
    test    edx, edx
    jz      .no_arp
    addss   xmm1, [rbx + SFXLAYER.arp1 + rdx*4 - 4]
.no_arp:
    movss   xmm2, [rbx + SFXLAYER.vib_depth]
    ucomiss xmm2, xmm3
    jbe     .no_vib
    movaps  xmm4, xmm0
    subss   xmm4, [rbx + SFXLAYER.vib_delay]
    ucomiss xmm4, xmm3
    jb      .no_vib
    mulss   xmm4, [rbx + SFXLAYER.vib_hz]
    addss   xmm4, [c_quarter]           ; starts at tri = 0
    movaps  xmm5, xmm4
    roundss xmm5, xmm5, 9
    subss   xmm4, xmm5                  ; frac
    subss   xmm4, [c_half]
    movss   xmm5, [c_abs]
    andps   xmm4, xmm5
    mulss   xmm4, [c_four]
    movss   xmm5, [c_one]
    subss   xmm5, xmm4                  ; tri = 1 - 4 |frac - 0.5|
    mulss   xmm5, xmm2
    addss   xmm1, xmm5
.no_vib:
    subss   xmm1, [c_69]
    mulss   xmm1, [c_inv12]
    movaps  xmm0, xmm1
    call    exp2_ss                     ; f / 440
    mulss   xmm0, [c_440_rate]          ; step = f / 44100
    cmp     dword [rbx + SFXLAYER.wave], W_NOISE
    jb      .tonal_step
    mulss   xmm0, [c_16]                ; noise clock = 16 f
.tonal_step:
    movaps  xmm9, xmm0
    movss   xmm0, [rsp + RL_T]
    divss   xmm0, [rbx + SFXLAYER.dur]
    movss   xmm1, [rbx + SFXLAYER.duty1]
    subss   xmm1, [rbx + SFXLAYER.duty0]
    mulss   xmm1, xmm0
    addss   xmm1, [rbx + SFXLAYER.duty0]
    maxss   xmm1, [c_duty_min]
    minss   xmm1, [c_duty_max]
    movaps  xmm10, xmm1
.osc:                                   ; xmm3 = oscillator output in [-1, 1]
    mov     eax, [rbx + SFXLAYER.wave]
    cmp     eax, W_TRI
    je      .tri
    cmp     eax, W_SAW
    je      .saw
    cmp     eax, W_NOISE
    jae     .noise
    ; pulse: naive +1 below the duty, -1 above, with a BLEP at each edge and its DC removed
    movaps  xmm0, xmm8
    movaps  xmm1, xmm9
    call    blep
    movaps  xmm6, xmm0                  ; + blep(p)
    movaps  xmm0, xmm8
    subss   xmm0, xmm10
    addss   xmm0, [c_one]
    movaps  xmm2, xmm0
    roundss xmm2, xmm2, 9
    subss   xmm0, xmm2                  ; frac(p - d + 1)
    call    blep
    subss   xmm6, xmm0
    movaps  xmm3, xmm8
    cmpltss xmm3, xmm10                 ; p < d ?
    movss   xmm4, [c_two]
    andps   xmm3, xmm4
    subss   xmm3, [c_one]               ; +1 / -1
    addss   xmm3, xmm6
    movaps  xmm4, xmm10
    addss   xmm4, xmm4
    subss   xmm4, [c_one]
    subss   xmm3, xmm4                  ; - (2d - 1)
    jmp     .advance
.tri:                                   ; 2A03: 32 steps, 15 down to 0 and back up
    movaps  xmm3, xmm8
    mulss   xmm3, [c_32]
    cvttss2si eax, xmm3
    and     eax, 31
    mov     ecx, 15
    sub     ecx, eax                    ; 15 - k
    lea     edx, [rax - 16]             ; k - 16
    cmp     eax, 16
    cmovae  ecx, edx
    cvtsi2ss xmm3, ecx
    mulss   xmm3, [c_2_15]
    subss   xmm3, [c_one]
    jmp     .advance
.saw:
    movaps  xmm0, xmm8
    movaps  xmm1, xmm9
    call    blep
    movaps  xmm3, xmm8
    addss   xmm3, xmm3
    subss   xmm3, [c_one]
    subss   xmm3, xmm0                  ; 2p - 1 - blep(p)
.advance:
    addss   xmm8, xmm9
    movaps  xmm5, xmm8
    roundss xmm5, xmm5, 9
    subss   xmm8, xmm5                  ; phase back into [0, 1)
    jmp     .filter
.noise:                                 ; clock the LFSR at most 8 times per sample
    addss   xmm14, xmm9
    mov     r9d, 8
    mov     ecx, [rsp + RL_TAP]
.lfsr:
    ucomiss xmm14, [c_one]
    jb      .lfsr_out
    subss   xmm14, [c_one]
    mov     eax, r14d
    shr     eax, cl
    xor     eax, r14d
    and     eax, 1                      ; bit = (r ^ (r >> tap)) & 1
    shl     eax, 14
    shr     r14d, 1
    or      r14d, eax
    dec     r9d
    jnz     .lfsr
    movaps  xmm5, xmm14                 ; excess clocks are dropped
    roundss xmm5, xmm5, 9
    subss   xmm14, xmm5
.lfsr_out:
    movss   xmm3, [c_one]
    test    r14d, 1
    jz      .filter
    movss   xmm3, [c_mone]
.filter:
    movss   xmm4, [rsp + RL_HP]
    xorps   xmm5, xmm5
    ucomiss xmm4, xmm5
    jbe     .lp
    movaps  xmm5, xmm3                  ; h += ah (x - h); x -= h
    subss   xmm5, xmm11
    mulss   xmm5, xmm4
    addss   xmm11, xmm5
    subss   xmm3, xmm11
.lp:
    movss   xmm4, [rsp + RL_LP]
    xorps   xmm5, xmm5
    ucomiss xmm4, xmm5
    jbe     .env
    movaps  xmm5, xmm3                  ; y += al (x - y); x = y
    subss   xmm5, xmm12
    mulss   xmm5, xmm4
    addss   xmm12, xmm5
    movaps  xmm3, xmm12
.env:                                   ; env = A * D * R
    movss   xmm0, [rsp + RL_T]
    movaps  xmm4, xmm0
    divss   xmm4, [rsp + RL_ATTACK]
    minss   xmm4, [c_one]               ; A = min(1, t / attack)
    movss   xmm5, [rbx + SFXLAYER.decay]
    xorps   xmm6, xmm6
    ucomiss xmm5, xmm6
    jbe     .release
    ucomiss xmm0, [rsp + RL_ATTACK]
    jb      .release
    movss   xmm5, [c_one]               ; D = sustain + (1 - sustain) v, then v *= k
    subss   xmm5, [rbx + SFXLAYER.sustain]
    mulss   xmm5, xmm13
    addss   xmm5, [rbx + SFXLAYER.sustain]
    mulss   xmm4, xmm5
    mulss   xmm13, [rsp + RL_K]
.release:
    movss   xmm5, [rbx + SFXLAYER.dur]
    subss   xmm5, xmm0
    divss   xmm5, [rsp + RL_RELEASE]
    minss   xmm5, [c_one]               ; R = min(1, (dur - t) / release)
    mulss   xmm4, xmm5
    mulss   xmm3, xmm4
    mulss   xmm3, xmm15
    addss   xmm3, [r12 + r15*4]
    movss   [r12 + r15*4], xmm3
.next:
    inc     r15d
    jmp     .loop
.done:
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
