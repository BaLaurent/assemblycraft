; sfx.asm - procedural sound effects: the 55 game sounds rendered once into one int16 pool.
; Each sound is the sum of a few layers (noise / square / saw through a one-pole filter and an
; envelope). sfx_table[id] = {offset, length} in samples; sfx_pool is mono signed 16-bit, 44100 Hz.
%include "common.inc"
default rel

global sfx_build, sfx_table, sfx_pool

%define POOL_SAMPLES 1048576

%define W_NOISE  0                      ; SFXLAYER.wave
%define W_SQUARE 1
%define W_SAW    2
%define E_EXP    0                      ; SFXLAYER.env
%define E_LIN    1

; LAYER sound, wave, f0, f1, lp, hp, env, half, attack, start, dur, amp, vdepth, vrate
; (one SFXLAYER record; every float field is written with a decimal point)
%macro LAYER 14
    dd %1, %2, %3, %4, %5, %6, %7, %8, %9, %10, %11, %12, %13, %14
%endmacro

section .rodata
align 4
c_one:       dd 1.0
c_two:       dd 2.0
c_four:      dd 4.0
c_half:      dd 0.5
c_rate:      dd 44100.0
c_inv_rate:  dd 2.2675736961451248e-5   ; 1 / 44100
c_gain:      dd 28000.0                 ; layer amp 1.0 = this many int16 units
c_inv_32768: dd 0.000030517578125       ; 2^-15
c_abs:       dd 0x7FFFFFFF
c_pmax:      dd 32767.0
c_pmin:      dd -32767.0
c_ceil_tol:  dd 0.01                    ; keeps float noise in 0.18 s etc. from adding a sample

; Layers, grouped by sound id in id order. amp is the spec's value except on the six lines marked
; "spec": the spec's amp leaves those sounds peaking under -12 dBFS, against the spec's own check
; that every sound peaks between -12 and -0.1 dBFS (CLICK's .25 * 28000 cannot reach -12 at all:
; CLICK -13.4, DIG_SOFT -16.0, STEP_STONE -13.9, STEP_WOOD -16.5, STEP_SOFT -19.6, EAT -15.4).
; They are raised to peak near -11.5 dBFS; the layers of one sound keep the spec's ratio.
;     sound            wave      f0      f1      lp   hp  env    half   attack start dur   amp   vdepth vrate
layers:
    LAYER SND_CLICK,       W_SQUARE, 1200.0, 1200.0, 1.0,  0, E_LIN, 0.0,   0.0,  0.0,  0.03, 0.31, 0.0,  0.0 ; spec .25
    LAYER SND_DIG_STONE,   W_NOISE,  0.0,    0.0,    0.5,  0, E_EXP, 0.04,  0.0,  0.0,  0.20, 0.5,  0.0,  0.0
    LAYER SND_DIG_WOOD,    W_NOISE,  0.0,    0.0,    0.18, 0, E_EXP, 0.05,  0.0,  0.0,  0.20, 0.5,  0.0,  0.0
    LAYER SND_DIG_WOOD,    W_SQUARE, 180.0,  160.0,  0.3,  0, E_EXP, 0.05,  0.0,  0.0,  0.20, 0.15, 0.0,  0.0
    LAYER SND_DIG_SOFT,    W_NOISE,  0.0,    0.0,    0.08, 0, E_EXP, 0.05,  0.0,  0.0,  0.18, 1.0,  0.0,  0.0 ; spec .6
    LAYER SND_DIG_GLASS,   W_NOISE,  0.0,    0.0,    0.3,  1, E_EXP, 0.08,  0.0,  0.0,  0.35, 0.35, 0.0,  0.0
    LAYER SND_DIG_GLASS,   W_SQUARE, 2400.0, 2400.0, 1.0,  0, E_EXP, 0.06,  0.0,  0.0,  0.30, 0.06, 0.0,  0.0
    LAYER SND_DIG_GLASS,   W_SQUARE, 3150.0, 3150.0, 1.0,  0, E_EXP, 0.05,  0.0,  0.03, 0.30, 0.05, 0.0,  0.0
    LAYER SND_STEP_STONE,  W_NOISE,  0.0,    0.0,    0.5,  0, E_EXP, 0.02,  0.0,  0.0,  0.08, 0.39, 0.0,  0.0 ; spec .3
    LAYER SND_STEP_WOOD,   W_NOISE,  0.0,    0.0,    0.18, 0, E_EXP, 0.025, 0.0,  0.0,  0.08, 0.525, 0.0, 0.0 ; spec .3
    LAYER SND_STEP_WOOD,   W_SQUARE, 160.0,  160.0,  0.3,  0, E_EXP, 0.02,  0.0,  0.0,  0.08, 0.14, 0.0,  0.0 ; spec .08
    LAYER SND_STEP_SOFT,   W_NOISE,  0.0,    0.0,    0.08, 0, E_EXP, 0.025, 0.0,  0.0,  0.08, 0.88, 0.0,  0.0 ; spec .35
    LAYER SND_HURT,        W_SQUARE, 600.0,  300.0,  0.5,  0, E_LIN, 0.0,   0.0,  0.0,  0.25, 0.35, 0.0,  0.0
    LAYER SND_EAT,         W_NOISE,  0.0,    0.0,    0.3,  0, E_EXP, 0.03,  0.0,  0.0,  0.12, 0.55, 0.0,  0.0 ; spec .35
    LAYER SND_BURP,        W_SQUARE, 120.0,  90.0,   0.1,  0, E_LIN, 0.0,   0.0,  0.0,  0.30, 0.5,  0.0,  0.0
    LAYER SND_ZOMBIE_SAY,  W_SAW,    90.0,   80.0,   0.15, 0, E_LIN, 0.0,   0.1,  0.0,  0.80, 0.5,  10.0, 5.0
    LAYER SND_ZOMBIE_HURT, W_SAW,    140.0,  90.0,   0.2,  0, E_LIN, 0.0,   0.0,  0.0,  0.30, 0.5,  0.0,  0.0
    LAYER SND_PIG_SAY,     W_SQUARE, 330.0,  310.0,  0.25, 0, E_LIN, 0.0,   0.0,  0.0,  0.12, 0.35, 0.0,  0.0
    LAYER SND_PIG_SAY,     W_SQUARE, 280.0,  260.0,  0.25, 0, E_LIN, 0.0,   0.0,  0.17, 0.12, 0.35, 0.0,  0.0
    LAYER SND_PIG_HURT,    W_SQUARE, 520.0,  380.0,  0.3,  0, E_LIN, 0.0,   0.0,  0.0,  0.25, 0.4,  0.0,  0.0
    LAYER SND_TOOL_BREAK,  W_NOISE,  0.0,    0.0,    0.3,  1, E_EXP, 0.05,  0.0,  0.0,  0.25, 0.4,  0.0,  0.0
    LAYER SND_TOOL_BREAK,  W_SQUARE, 1800.0, 1200.0, 1.0,  0, E_EXP, 0.05,  0.0,  0.0,  0.20, 0.08, 0.0,  0.0
    LAYER SND_POP,         W_SQUARE, 400.0,  900.0,  0.4,  0, E_LIN, 0.0,   0.0,  0.0,  0.06, 0.3,  0.0,  0.0
    LAYER SND_EXPLODE,       W_NOISE,  0.0,    0.0,    0.12, 0, E_EXP, 0.25,  0.0,  0.0,  1.2,  1.0,  0.0,  0.0
    LAYER SND_EXPLODE,       W_NOISE,  0.0,    0.0,    0.6,  1, E_EXP, 0.05,  0.0,  0.0,  0.3,  0.6,  0.0,  0.0
    LAYER SND_FUSE,          W_NOISE,  0.0,    0.0,    0.7,  1, E_LIN, 0.0,   0.3,  0.0,  1.5,  0.45, 0.0,  0.0
    LAYER SND_BOW,           W_NOISE,  0.0,    0.0,    0.5,  1, E_EXP, 0.03,  0.0,  0.0,  0.12, 0.45, 0.0,  0.0
    LAYER SND_BOW,           W_SQUARE, 220.0,  110.0,  0.2,  0, E_LIN, 0.0,   0.0,  0.0,  0.15, 0.3,  0.0,  0.0
    LAYER SND_ARROW_HIT,     W_NOISE,  0.0,    0.0,    0.35, 0, E_EXP, 0.02,  0.0,  0.0,  0.08, 0.7,  0.0,  0.0
    LAYER SND_ARROW_HIT,     W_SQUARE, 900.0,  600.0,  0.5,  0, E_EXP, 0.02,  0.0,  0.0,  0.06, 0.12, 0.0,  0.0
    LAYER SND_SKELETON_SAY,  W_SQUARE, 1100.0, 900.0,  0.5,  0, E_LIN, 0.0,   0.0,  0.0,  0.05, 0.35, 0.0,  0.0
    LAYER SND_SKELETON_SAY,  W_SQUARE, 1100.0, 900.0,  0.5,  0, E_LIN, 0.0,   0.0,  0.08, 0.05, 0.35, 0.0,  0.0
    LAYER SND_SKELETON_SAY,  W_SQUARE, 1100.0, 900.0,  0.5,  0, E_LIN, 0.0,   0.0,  0.16, 0.05, 0.35, 0.0,  0.0
    LAYER SND_SKELETON_HURT, W_SQUARE, 800.0,  400.0,  0.5,  0, E_LIN, 0.0,   0.0,  0.0,  0.2,  0.4,  0.0,  0.0
    LAYER SND_SKELETON_HURT, W_NOISE,  0.0,    0.0,    0.5,  0, E_EXP, 0.03,  0.0,  0.0,  0.1,  0.35, 0.0,  0.0
    LAYER SND_SPIDER_SAY,    W_NOISE,  0.0,    0.0,    0.15, 0, E_LIN, 0.0,   0.05, 0.0,  0.45, 0.6,  0.0,  0.0
    LAYER SND_SPIDER_SAY,    W_SAW,    70.0,   60.0,   0.1,  0, E_LIN, 0.0,   0.0,  0.0,  0.45, 0.35, 8.0,  9.0
    LAYER SND_SPIDER_HURT,   W_SAW,    220.0,  120.0,  0.3,  0, E_LIN, 0.0,   0.0,  0.0,  0.25, 0.5,  0.0,  0.0
    LAYER SND_CREEPER_HURT,  W_NOISE,  0.0,    0.0,    0.5,  1, E_EXP, 0.06,  0.0,  0.0,  0.25, 0.5,  0.0,  0.0
    LAYER SND_CREEPER_HURT,  W_SAW,    160.0,  110.0,  0.2,  0, E_LIN, 0.0,   0.0,  0.0,  0.2,  0.35, 0.0,  0.0
    LAYER SND_CHICKEN_SAY,   W_SQUARE, 1500.0, 1700.0, 0.5,  0, E_LIN, 0.0,   0.0,  0.0,  0.06, 0.3,  0.0,  0.0
    LAYER SND_CHICKEN_SAY,   W_SQUARE, 1700.0, 1300.0, 0.5,  0, E_LIN, 0.0,   0.0,  0.1,  0.08, 0.3,  0.0,  0.0
    LAYER SND_CHICKEN_HURT,  W_SQUARE, 1900.0, 1000.0, 0.5,  0, E_LIN, 0.0,   0.0,  0.0,  0.15, 0.35, 0.0,  0.0
    LAYER SND_PISTOL,        W_NOISE,  0.0,    0.0,    0.6,  1, E_EXP, 0.03,  0.0,  0.0,  0.25, 0.7,  0.0,  0.0
    LAYER SND_PISTOL,        W_NOISE,  0.0,    0.0,    0.08, 0, E_EXP, 0.06,  0.0,  0.0,  0.2,  0.5,  0.0,  0.0
    LAYER SND_PISTOL,        W_SQUARE, 150.0,  60.0,   0.2,  0, E_EXP, 0.05,  0.0,  0.0,  0.15, 0.3,  0.0,  0.0
    LAYER SND_MUSKET,        W_NOISE,  0.0,    0.0,    0.1,  0, E_EXP, 0.2,   0.0,  0.0,  0.9,  0.9,  0.0,  0.0
    LAYER SND_MUSKET,        W_NOISE,  0.0,    0.0,    0.5,  1, E_EXP, 0.04,  0.0,  0.0,  0.3,  0.5,  0.0,  0.0
    LAYER SND_MUSKET,        W_SAW,    90.0,   45.0,   0.1,  0, E_LIN, 0.0,   0.0,  0.0,  0.4,  0.3,  0.0,  0.0
    LAYER SND_SHOTGUN,       W_NOISE,  0.0,    0.0,    0.3,  0, E_EXP, 0.12,  0.0,  0.0,  0.6,  0.9,  0.0,  0.0
    LAYER SND_SHOTGUN,       W_NOISE,  0.0,    0.0,    0.7,  1, E_EXP, 0.04,  0.0,  0.0,  0.25, 0.6,  0.0,  0.0
    LAYER SND_SHOTGUN,       W_SQUARE, 100.0,  50.0,   0.15, 0, E_EXP, 0.08,  0.0,  0.0,  0.3,  0.3,  0.0,  0.0
    LAYER SND_RIFLE,         W_NOISE,  0.0,    0.0,    0.7,  1, E_EXP, 0.015, 0.0,  0.0,  0.15, 0.7,  0.0,  0.0
    LAYER SND_RIFLE,         W_NOISE,  0.0,    0.0,    0.2,  0, E_EXP, 0.02,  0.0,  0.0,  0.08, 0.3,  0.0,  0.0
    LAYER SND_LAUNCHER,      W_NOISE,  0.0,    0.0,    0.3,  1, E_LIN, 0.0,   0.15, 0.0,  0.7,  0.5,  0.0,  0.0
    LAYER SND_LAUNCHER,      W_SAW,    150.0,  700.0,  0.15, 0, E_LIN, 0.0,   0.1,  0.0,  0.6,  0.25, 0.0,  0.0
    LAYER SND_LAUNCHER,      W_SQUARE, 120.0,  50.0,   0.15, 0, E_EXP, 0.06,  0.0,  0.0,  0.25, 0.45, 0.0,  0.0
    LAYER SND_LAUNCHER,      W_NOISE,  0.0,    0.0,    0.1,  0, E_EXP, 0.1,   0.0,  0.0,  0.3,  0.5,  0.0,  0.0
    LAYER SND_RELOAD,        W_SQUARE, 2000.0, 1500.0, 1.0,  0, E_EXP, 0.015, 0.0,  0.0,  0.05, 0.25, 0.0,  0.0
    LAYER SND_RELOAD,        W_NOISE,  0.0,    0.0,    0.5,  1, E_EXP, 0.01,  0.0,  0.0,  0.03, 0.3,  0.0,  0.0
    LAYER SND_RELOAD,        W_SQUARE, 1400.0, 1000.0, 1.0,  0, E_EXP, 0.015, 0.0,  0.12, 0.05, 0.25, 0.0,  0.0
    LAYER SND_RELOAD,        W_NOISE,  0.0,    0.0,    0.5,  1, E_EXP, 0.01,  0.0,  0.12, 0.03, 0.3,  0.0,  0.0
    LAYER SND_DRY_FIRE,      W_SQUARE, 1800.0, 1200.0, 1.0,  0, E_EXP, 0.01,  0.0,  0.0,  0.04, 0.3,  0.0,  0.0
    LAYER SND_DRY_FIRE,      W_NOISE,  0.0,    0.0,    0.5,  1, E_EXP, 0.008, 0.0,  0.0,  0.03, 0.3,  0.0,  0.0
    ; --- 0.6 RPG sounds 35..52 (peak target: inside -18 .. -0.1 dBFS, measured with the harness) ---
    LAYER SND_SWING,         W_NOISE,  0.0,    0.0,    0.2,  0, E_LIN, 0.0,   0.04, 0.0,  0.18, 1.6,  0.0,  0.0
    LAYER SND_SWING,         W_NOISE,  0.0,    0.0,    0.6,  1, E_LIN, 0.0,   0.05, 0.02, 0.14, 0.25, 0.0,  0.0
    LAYER SND_PARRY,         W_SQUARE, 1800.0, 1600.0, 0.6,  0, E_EXP, 0.12,  0.0,  0.0,  0.50, 0.30, 0.0,  0.0
    LAYER SND_PARRY,         W_SQUARE, 2700.0, 2400.0, 0.6,  0, E_EXP, 0.08,  0.0,  0.0,  0.40, 0.14, 0.0,  0.0
    LAYER SND_PARRY,         W_NOISE,  0.0,    0.0,    0.7,  1, E_EXP, 0.01,  0.0,  0.0,  0.06, 0.45, 0.0,  0.0
    LAYER SND_BLOCK,         W_NOISE,  0.0,    0.0,    0.06, 0, E_EXP, 0.03,  0.0,  0.0,  0.20, 2.2,  0.0,  0.0
    LAYER SND_BLOCK,         W_SQUARE, 90.0,   55.0,   0.2,  0, E_EXP, 0.05,  0.0,  0.0,  0.20, 0.35, 0.0,  0.0
    LAYER SND_DODGE,         W_NOISE,  0.0,    0.0,    0.08, 0, E_LIN, 0.0,   0.08, 0.0,  0.30, 2.6,  0.0,  0.0
    LAYER SND_CRIT,          W_NOISE,  0.0,    0.0,    0.7,  1, E_EXP, 0.02,  0.0,  0.0,  0.12, 0.5,  0.0,  0.0
    LAYER SND_CRIT,          W_SQUARE, 120.0,  60.0,   0.2,  0, E_EXP, 0.03,  0.0,  0.0,  0.10, 0.30, 0.0,  0.0
    LAYER SND_CRIT,          W_SQUARE, 2600.0, 2200.0, 0.6,  0, E_EXP, 0.08,  0.0,  0.0,  0.30, 0.22, 0.0,  0.0
    LAYER SND_CRIT,          W_SQUARE, 3400.0, 3200.0, 0.6,  0, E_EXP, 0.06,  0.0,  0.03, 0.25, 0.14, 0.0,  0.0
    LAYER SND_LEVELUP,       W_SQUARE, 523.0,  523.0,  0.5,  0, E_EXP, 0.10,  0.0,  0.0,  0.22, 0.30, 0.0,  0.0
    LAYER SND_LEVELUP,       W_SQUARE, 659.0,  659.0,  0.5,  0, E_EXP, 0.10,  0.0,  0.10, 0.22, 0.30, 0.0,  0.0
    LAYER SND_LEVELUP,       W_SQUARE, 784.0,  784.0,  0.5,  0, E_EXP, 0.10,  0.0,  0.20, 0.22, 0.30, 0.0,  0.0
    LAYER SND_LEVELUP,       W_SQUARE, 1047.0, 1047.0, 0.5,  0, E_EXP, 0.18,  0.0,  0.30, 0.55, 0.30, 0.0,  0.0
    LAYER SND_SPELL,         W_SAW,    500.0,  1400.0, 0.12, 0, E_LIN, 0.0,   0.01, 0.0,  0.22, 0.80, 0.0,  0.0
    LAYER SND_SPELL,         W_NOISE,  0.0,    0.0,    0.6,  1, E_LIN, 0.0,   0.01, 0.0,  0.20, 0.12, 0.0,  0.0
    LAYER SND_FIREBALL,      W_NOISE,  0.0,    0.0,    0.25, 0, E_LIN, 0.0,   0.05, 0.0,  0.60, 1.0,  0.0,  0.0
    LAYER SND_FIREBALL,      W_SAW,    70.0,   50.0,   0.1,  0, E_LIN, 0.0,   0.05, 0.0,  0.60, 0.30, 8.0,  11.0
    LAYER SND_BLINK,         W_SQUARE, 3000.0, 800.0,  0.5,  0, E_LIN, 0.0,   0.0,  0.0,  0.30, 0.22, 60.0, 30.0
    LAYER SND_BLINK,         W_SQUARE, 2000.0, 500.0,  0.5,  0, E_LIN, 0.0,   0.0,  0.04, 0.26, 0.16, 40.0, 27.0
    LAYER SND_BLINK,         W_NOISE,  0.0,    0.0,    0.6,  1, E_LIN, 0.0,   0.0,  0.0,  0.25, 0.15, 0.0,  0.0
    LAYER SND_WARCRY,        W_SAW,    110.0,  90.0,   0.2,  0, E_LIN, 0.0,   0.05, 0.0,  0.70, 0.45, 6.0,  7.0
    LAYER SND_WARCRY,        W_SAW,    220.0,  180.0,  0.2,  0, E_LIN, 0.0,   0.05, 0.0,  0.70, 0.18, 10.0, 7.0
    LAYER SND_WARCRY,        W_NOISE,  0.0,    0.0,    0.3,  0, E_LIN, 0.0,   0.05, 0.0,  0.60, 0.35, 0.0,  0.0
    LAYER SND_WHIRL,         W_NOISE,  0.0,    0.0,    0.2,  0, E_LIN, 0.0,   0.05, 0.0,  0.30, 1.2,  0.0,  0.0
    LAYER SND_WHIRL,         W_NOISE,  0.0,    0.0,    0.2,  0, E_LIN, 0.0,   0.05, 0.22, 0.30, 1.2,  0.0,  0.0
    LAYER SND_SMOKE,         W_NOISE,  0.0,    0.0,    0.5,  1, E_LIN, 0.0,   0.1,  0.0,  0.70, 0.60, 0.0,  0.0
    LAYER SND_COIN,          W_SQUARE, 2600.0, 2600.0, 0.7,  0, E_EXP, 0.04,  0.0,  0.0,  0.18, 0.30, 0.0,  0.0
    LAYER SND_COIN,          W_SQUARE, 3500.0, 3500.0, 0.7,  0, E_EXP, 0.07,  0.0,  0.08, 0.30, 0.30, 0.0,  0.0
    LAYER SND_QUEST,         W_SQUARE, 523.0,  523.0,  0.4,  0, E_EXP, 0.10,  0.0,  0.0,  0.18, 0.35, 0.0,  0.0
    LAYER SND_QUEST,         W_SQUARE, 659.0,  659.0,  0.4,  0, E_EXP, 0.10,  0.0,  0.14, 0.18, 0.35, 0.0,  0.0
    LAYER SND_QUEST,         W_SQUARE, 784.0,  784.0,  0.4,  0, E_EXP, 0.18,  0.0,  0.28, 0.50, 0.35, 0.0,  0.0
    LAYER SND_BOSS_ROAR,     W_SAW,    70.0,   45.0,   0.1,  0, E_LIN, 0.0,   0.15, 0.0,  1.60, 0.45, 8.0,  6.0
    LAYER SND_BOSS_ROAR,     W_SAW,    105.0,  68.0,   0.1,  0, E_LIN, 0.0,   0.15, 0.0,  1.60, 0.22, 10.0, 7.0
    LAYER SND_BOSS_ROAR,     W_NOISE,  0.0,    0.0,    0.15, 0, E_LIN, 0.0,   0.10, 0.0,  1.40, 0.75, 0.0,  0.0
    LAYER SND_SLAM,          W_NOISE,  0.0,    0.0,    0.05, 0, E_EXP, 0.15,  0.0,  0.0,  0.80, 1.4,  0.0,  0.0
    LAYER SND_SLAM,          W_SAW,    60.0,   30.0,   0.2,  0, E_EXP, 0.12,  0.0,  0.0,  0.60, 0.40, 0.0,  0.0
    LAYER SND_SLAM,          W_NOISE,  0.0,    0.0,    0.5,  1, E_EXP, 0.02,  0.0,  0.0,  0.08, 0.35, 0.0,  0.0
    LAYER SND_VILLAGER,      W_SQUARE, 140.0,  120.0,  0.1,  0, E_LIN, 0.0,   0.03, 0.0,  0.30, 0.45, 6.0,  8.0
    LAYER SND_VILLAGER,      W_SQUARE, 280.0,  240.0,  0.1,  0, E_LIN, 0.0,   0.03, 0.0,  0.30, 0.15, 12.0, 8.0
    LAYER SND_DRINK,         W_SQUARE, 250.0,  400.0,  0.3,  0, E_LIN, 0.0,   0.0,  0.0,  0.07, 0.35, 0.0,  0.0
    LAYER SND_DRINK,         W_SQUARE, 220.0,  350.0,  0.3,  0, E_LIN, 0.0,   0.0,  0.10, 0.07, 0.35, 0.0,  0.0
    LAYER SND_DRINK,         W_SQUARE, 200.0,  300.0,  0.3,  0, E_LIN, 0.0,   0.0,  0.20, 0.07, 0.35, 0.0,  0.0
    LAYER SND_DRINK,         W_NOISE,  0.0,    0.0,    0.1,  0, E_LIN, 0.0,   0.0,  0.0,  0.27, 0.40, 0.0,  0.0
    ; --- 0.7 door sounds 53..54 (peak target: inside -18 .. -0.1 dBFS, measured with the harness) ---
    LAYER SND_DOOR_OPEN,     W_SAW,    220.0,  180.0,  0.12, 0, E_LIN, 0.0,   0.03, 0.0,  0.25, 0.45, 12.0, 16.0 ; creak
    LAYER SND_DOOR_OPEN,     W_SAW,    330.0,  260.0,  0.08, 0, E_LIN, 0.0,   0.05, 0.02, 0.20, 0.10, 20.0, 23.0
    LAYER SND_DOOR_OPEN,     W_NOISE,  0.0,    0.0,    0.5,  1, E_EXP, 0.008, 0.0,  0.0,  0.04, 0.35, 0.0,  0.0  ; latch click
    LAYER SND_DOOR_CLOSE,    W_NOISE,  0.0,    0.0,    0.06, 0, E_EXP, 0.03,  0.0,  0.0,  0.15, 1.3,  0.0,  0.0  ; thud
    LAYER SND_DOOR_CLOSE,    W_SQUARE, 90.0,   90.0,   0.2,  0, E_EXP, 0.04,  0.0,  0.0,  0.15, 0.30, 0.0,  0.0
layers_end:

section .bss
alignb 16
sfx_table: resd NUM_SOUNDS * 2          ; per sound id: dd offset, dd length (samples)
sfx_rng:   resd 1                       ; private xorshift32 state for noise
alignb 16
sfx_pool:  resw POOL_SAMPLES            ; all sounds, back to back
sfx_acc:   resd POOL_SAMPLES            ; float mix of the sound being built (only its length is touched)

section .text

; sfx_build(): render every sound into sfx_pool and fill sfx_table. Safe to call again (same output).
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
    jae     .pack
    mov     rdi, r14
    lea     rsi, [sfx_acc]
    mov     edx, ebx
    call    render_layer
    add     r14, SFXLAYER_size
    jmp     .layer
.pack:                                  ; float -> clamped int16 at pool + offset
    lea     rsi, [sfx_acc]
    lea     rdi, [sfx_pool]
    lea     rdi, [rdi + r13*2]
    mov     ecx, ebx
    test    ecx, ecx
    jz      .packed
.pack_loop:
    movss   xmm0, [rsi]
    minss   xmm0, [c_pmax]
    maxss   xmm0, [c_pmin]
    cvtss2si eax, xmm0
    mov     [rdi], ax
    add     rsi, 4
    add     rdi, 2
    dec     ecx
    jnz     .pack_loop
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

; render_layer(rdi SFXLAYER*, rsi float acc[], edx len): add one layer, already scaled by
; amp * 28000, into acc[0..len). Leaves the x87 stack empty.
render_layer:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 16
    mov     rbx, rdi                    ; layer
    mov     r12, rsi                    ; acc
    mov     r13d, edx                   ; len
    mov     r14d, [sfx_rng]             ; noise state for the duration of the layer
    movss   xmm12, [rbx + SFXLAYER.amp]
    mulss   xmm12, [c_gain]             ; xmm12 = amp * 28000
    movss   xmm10, [c_one]              ; xmm10 = exponential envelope value
    xorps   xmm8, xmm8                  ; xmm8  = oscillator phase [0, 1)
    xorps   xmm9, xmm9                  ; xmm9  = filter state y
    cmp     dword [rbx + SFXLAYER.env], E_EXP
    jne     .loop_init
    movss   xmm0, [rbx + SFXLAYER.half]
    mulss   xmm0, [c_rate]              ; half-life in samples
    movss   xmm1, [c_one]
    divss   xmm1, xmm0
    movss   [rsp], xmm1                 ; x = 1 / (half * 44100)
    fld     dword [rsp]
    fchs                                ; -x
    f2xm1                               ; 2^-x - 1
    fld1
    faddp   st1, st0                    ; 2^-x
    fstp    dword [rsp]
    movss   xmm11, [rsp]                ; xmm11 = k, the per-sample decay factor
.loop_init:
    xor     r8d, r8d                    ; n
.loop:
    cmp     r8d, r13d
    jae     .done
    cvtsi2ss xmm0, r8d
    mulss   xmm0, [c_inv_rate]
    subss   xmm0, [rbx + SFXLAYER.start] ; xmm0 = t
    xorps   xmm1, xmm1
    ucomiss xmm0, xmm1
    jb      .next                       ; not started yet
    movss   xmm2, [rbx + SFXLAYER.dur]
    ucomiss xmm0, xmm2
    jae     .done                       ; over (t only grows)
    movaps  xmm13, xmm0
    divss   xmm13, xmm2                 ; xmm13 = t / dur
    mov     eax, [rbx + SFXLAYER.wave]
    test    eax, eax
    jnz     .tonal
    mov     edx, r14d                   ; noise: xorshift32 step, (int16)(rng >> 16) / 32768
    shl     edx, 13
    xor     r14d, edx
    mov     edx, r14d
    shr     edx, 17
    xor     r14d, edx
    mov     edx, r14d
    shl     edx, 5
    xor     r14d, edx
    mov     edx, r14d
    sar     edx, 16
    cvtsi2ss xmm3, edx
    mulss   xmm3, [c_inv_32768]
    jmp     .filter
.tonal:
    movss   xmm4, [rbx + SFXLAYER.f1]   ; f = f0 + (f1 - f0) * t / dur + vdepth * tri(vrate * t)
    movss   xmm5, [rbx + SFXLAYER.f0]
    subss   xmm4, xmm5
    mulss   xmm4, xmm13
    addss   xmm4, xmm5
    movss   xmm5, [rbx + SFXLAYER.vrate]
    mulss   xmm5, xmm0
    movaps  xmm6, xmm5
    roundss xmm6, xmm6, 9
    subss   xmm5, xmm6                  ; frac(vrate * t)
    subss   xmm5, [c_half]
    movss   xmm6, [c_abs]
    andps   xmm5, xmm6                  ; |frac - 0.5|
    mulss   xmm5, [c_four]
    movss   xmm6, [c_one]
    subss   xmm6, xmm5                  ; tri = 1 - 4 |frac - 0.5|
    mulss   xmm6, [rbx + SFXLAYER.vdepth]
    addss   xmm4, xmm6                  ; xmm4 = f
    cmp     eax, W_SQUARE
    jne     .saw
    movaps  xmm3, xmm8
    cmpltss xmm3, [c_half]              ; phase < 0.5 ?
    movss   xmm5, [c_two]
    andps   xmm3, xmm5
    subss   xmm3, [c_one]               ; +1 / -1
    jmp     .advance
.saw:
    movaps  xmm3, xmm8
    addss   xmm3, xmm3
    subss   xmm3, [c_one]               ; 2 * phase - 1
.advance:
    mulss   xmm4, [c_inv_rate]
    addss   xmm8, xmm4                  ; phase += f / 44100
    movaps  xmm5, xmm8
    roundss xmm5, xmm5, 9
    subss   xmm8, xmm5                  ; back into [0, 1)
.filter:
    movaps  xmm4, xmm3                  ; y += lp * (x - y)
    subss   xmm4, xmm9
    mulss   xmm4, [rbx + SFXLAYER.lp]
    addss   xmm9, xmm4
    movaps  xmm5, xmm9                  ; output y, or x - y for the high-pass
    cmp     dword [rbx + SFXLAYER.hp], 0
    je      .env
    movaps  xmm5, xmm3
    subss   xmm5, xmm9
.env:
    cmp     dword [rbx + SFXLAYER.env], E_EXP
    jne     .env_lin
    movaps  xmm6, xmm10                 ; exponential: this sample's value, then decay
    mulss   xmm10, xmm11
    jmp     .attack
.env_lin:
    movss   xmm6, [c_one]
    subss   xmm6, xmm13                 ; 1 - t / dur
.attack:
    movss   xmm4, [rbx + SFXLAYER.attack]
    xorps   xmm7, xmm7
    ucomiss xmm4, xmm7
    jbe     .mix                        ; no attack ramp
    movaps  xmm7, xmm0
    divss   xmm7, xmm4
    minss   xmm7, [c_one]               ; min(1, t / attack)
    mulss   xmm6, xmm7
.mix:
    mulss   xmm5, xmm6
    mulss   xmm5, xmm12
    addss   xmm5, [r12 + r8*4]
    movss   [r12 + r8*4], xmm5
.next:
    inc     r8d
    jmp     .loop
.done:
    mov     [sfx_rng], r14d
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
