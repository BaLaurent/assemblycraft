; fx.asm - effect particles: explosion fireballs and smoke, flying block debris, the sparks, magic
; motes and gold glitter of combat, camera shake and a screen flash. Particles are not saved with
; the world; everything lives in fx_particles.
;
; A particle has kind 0 (free), FX_FIRE, FX_SMOKE, FX_DEBRIS, FX_SPARK, FX_MAGIC or FX_GOLD.
; Velocities are in blocks per second and every position moves v / 60 per fixed step.
; fx_explosion, fx_debris and fx_burst spawn, fx_step runs once per fixed step, fx_render draws
; inside the world pass.
%include "common.inc"
%include "gl.inc"
default rel

global fx_clear, fx_explosion, fx_debris, fx_burst, fx_step, fx_render, fx_count
global fx_particles, fx_shake, fx_shake_yaw, fx_shake_pitch, fx_flash

extern rng_next, player_eye, world_is_solid, block_tiles, render_box
extern glIsEnabled, glGetFloatv

%define GL_CURRENT_COLOR 0x0B00

section .rodata
align 4
k_inv65536: dd 0.000015258789
k_dt:       dd 0.016666668              ; one fixed step in seconds
k_half:     dd 0.5
k_near2:    dd 0.64                     ; particles within 0.8 blocks of the eye are not drawn
k_one:      dd 1.0
k_neg_one:  dd -1.0
k_eps:      dd 0.0001
k_tiny:     dd 0.001
k_6:        dd 6.0
k_3:        dd 3.0
k_2:        dd 2.0
k_third:    dd 0.33333334
k_fire_lo:  dd 0.45
k_fire_hi:  dd 0.9
k_fire_v0:  dd 3.0                      ; fireball speed (3..8) * r / 3
k_fire_v1:  dd 8.0
k_fire_n:   dd 18.0                     ; fireball particles per block of radius
k_smoke_n:  dd 3.0                      ; smoke particles per block of radius
k_smoke_vy0: dd 1.0
k_smoke_vy1: dd 2.5
k_smoke_h:  dd 0.7
k_smoke_nh: dd -0.7
k_smoke_s0: dd 0.25
k_smoke_s1: dd 0.5
k_deb_s0:   dd 0.15
k_deb_s1:   dd 0.25
k_deb_v0:   dd 4.0
k_deb_v1:   dd 9.0
k_deb_up0:  dd 3.0
k_deb_up1:  dd 7.0
k_shk_k:    dd 1.5
k_shk_cap:  dd 2.5
k_flash_k:  dd 0.8
k_fire_dv:  dd 0.9
k_fire_up:  dd 0.03
k_fire_sz:  dd 0.975
k_smoke_dv: dd 0.98
k_smoke_gr: dd 0.006
k_smoke_fd: dd 0.9                      ; size factor per step while fading
%define SMOKE_FADE 25                   ; steps of fading before a smoke puff ends
k_grav:     dd 0.4                      ; debris gravity, blocks/s per step
k_bounce:   dd -0.35
k_friction: dd 0.6
k_shk_dec:  dd 0.88
k_shk_min:  dd 0.02
k_flash_dec: dd 0.06
; fire colour yellow -> red, smoke grey 0.55 -> 0.25
k_fire_r0:  dd 1.0
k_fire_g0:  dd 0.95
k_fire_b0:  dd 0.4
k_fire_r1:  dd 0.8
k_fire_g1:  dd 0.2
k_fire_b1:  dd 0.05
k_smoke_g0: dd 0.62
k_smoke_g1: dd 0.35
; fx_burst: sparks fall 0.3 b/s per step, magic motes slow x0.9 per step, gold rises 0.04 b/s per step
k_spark_g:  dd 0.3
k_magic_dv: dd 0.9
k_gold_up:  dd 0.04
; start and end colour (r, g, b, r, g, b) of the burst kinds SPARK, MAGIC, GOLD
k_burst_col:
    dd 1.0, 0.95, 0.6,  1.0, 0.6, 0.2
    dd 0.7, 0.3, 1.0,   0.3, 0.1, 0.6
    dd 1.0, 0.85, 0.3,  1.0, 0.6, 0.1
; fx_burst rows by kind - FX_FIRE: size lo, size hi, life lo, number of lives (hi = lo + n - 1);
; the DEBRIS row is never used
burst_tab:
    dd 0.15, 0.3,  10, 7                ; FIRE
    dd 0.2, 0.4,   40, 31               ; SMOKE
    dd 0.0, 0.0,   0, 1                 ; DEBRIS
    dd 0.08, 0.14, 10, 7                ; SPARK
    dd 0.12, 0.2,  18, 13               ; MAGIC
    dd 0.1, 0.18,  30, 21               ; GOLD
; render_box face order +X -X +Y -Y +Z -Z
shades_block: dd 0.6, 0.6, 1.0, 0.5, 0.8, 0.8
shades_flat:  dd 1.0, 1.0, 1.0, 1.0, 1.0, 1.0
zero_tiles:   db 0, 0, 0, 0, 0, 0, 0, 0

section .bss
alignb 16
fx_particles:     resb MAX_PARTICLES * PARTICLE_size
fx_particles_end:
fx_shake:         resd 1                ; camera shake strength (0 = none)
fx_shake_yaw:     resd 1                ; this step's camera offsets, degrees
fx_shake_pitch:   resd 1
fx_flash:         resd 1                ; screen flash strength 0..1
cull_eye:         resd 3                ; the eye this frame's particles are culled against

section .text

; rnd01() -> xmm0 in [0, 1)
rnd01:
    sub     rsp, 8
    call    rng_next
    add     rsp, 8
    shr     eax, 8
    and     eax, 0xFFFF
    cvtsi2ss xmm0, eax
    mulss   xmm0, [k_inv65536]
    ret

; rnd_range(xmm0 lo, xmm1 hi) -> xmm0 uniform in [lo, hi)
rnd_range:
    sub     rsp, 24
    movss   [rsp], xmm0
    subss   xmm1, xmm0
    movss   [rsp + 4], xmm1
    call    rnd01
    mulss   xmm0, [rsp + 4]
    addss   xmm0, [rsp]
    add     rsp, 24
    ret

; rnd_mod(edi n) -> eax in [0, n)
rnd_mod:
    sub     rsp, 24
    mov     [rsp], edi
    call    rng_next
    xor     edx, edx
    div     dword [rsp]
    mov     eax, edx
    add     rsp, 24
    ret

; alloc() -> rax a zeroed free particle (kind still 0: the caller sets it last), or 0 when full
alloc:
    lea     rax, [fx_particles]
    lea     rcx, [fx_particles_end]
.scan:
    cmp     dword [rax + PARTICLE.kind], 0
    je      .found
    add     rax, PARTICLE_size
    cmp     rax, rcx
    jb      .scan
    xor     eax, eax
    ret
.found:
%assign i 0
%rep PARTICLE_size / 4
    mov     dword [rax + i], 0
%assign i i + 4
%endrep
    ret

; solid_at(xmm0 x, xmm1 y, xmm2 z) -> eax world_is_solid of the cell holding the point
solid_at:
    sub     rsp, 8
    roundss xmm0, xmm0, 9
    cvttss2si edi, xmm0
    roundss xmm1, xmm1, 9
    cvttss2si esi, xmm1
    roundss xmm2, xmm2, 9
    cvttss2si edx, xmm2
    call    world_is_solid
    add     rsp, 8
    ret

; fx_clear(): no particles, no shake, no flash
fx_clear:
    lea     rdi, [fx_particles]
    mov     ecx, MAX_PARTICLES * PARTICLE_size
    xor     eax, eax
    rep     stosb
    mov     dword [fx_shake], 0
    mov     dword [fx_shake_yaw], 0
    mov     dword [fx_shake_pitch], 0
    mov     dword [fx_flash], 0
    ret

; fx_count() -> eax live particles
fx_count:
    lea     rdx, [fx_particles]
    lea     rcx, [fx_particles_end]
    xor     eax, eax
.loop:
    cmp     dword [rdx + PARTICLE.kind], 0
    setne   sil
    movzx   esi, sil
    add     eax, esi
    add     rdx, PARTICLE_size
    cmp     rdx, rcx
    jb      .loop
    ret

%define E_C     0                       ; centre xyz
%define E_R     12                      ; radius
%define E_EYE   16                      ; player eye xyz
%define E_TMP   32                      ; direction xyz
%define E_SCALE 44
%define E_HALF  48
%define E_FRAME 72

; fx_explosion(xmm0..2 centre, xmm3 radius): 12 r fireball particles, 6 r smoke puffs, and the
; camera shake and screen flash for the player's distance.
; rbx = the particle being filled, r12d = index, r13d = count.
fx_explosion:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, E_FRAME
    movss   [rsp + E_C], xmm0
    movss   [rsp + E_C + 4], xmm1
    movss   [rsp + E_C + 8], xmm2
    movss   [rsp + E_R], xmm3

    ; ---- fireball: random direction x (3..8) r / 3 b/s, size 0.45..0.9, life 20..38 ------
    movss   xmm0, [rsp + E_R]
    mulss   xmm0, [k_fire_n]
    cvttss2si r13d, xmm0
    xor     r12d, r12d
.fire:
    cmp     r12d, r13d
    jae     .fire_done
    call    alloc
    test    rax, rax
    jz      .fire_done                  ; table full: the rest is dropped
    mov     rbx, rax
    mov     eax, [rsp + E_C]
    mov     [rbx + PARTICLE.x], eax
    mov     eax, [rsp + E_C + 4]
    mov     [rbx + PARTICLE.y], eax
    mov     eax, [rsp + E_C + 8]
    mov     [rbx + PARTICLE.z], eax
%assign off 0
%rep 3
    movss   xmm0, [k_neg_one]
    movss   xmm1, [k_one]
    call    rnd_range
    movss   [rsp + E_TMP + off], xmm0
%assign off off + 4
%endrep
    movss   xmm1, [rsp + E_TMP]
    mulss   xmm1, xmm1
    movss   xmm0, [rsp + E_TMP + 4]
    mulss   xmm0, xmm0
    addss   xmm1, xmm0
    movss   xmm0, [rsp + E_TMP + 8]
    mulss   xmm0, xmm0
    addss   xmm1, xmm0                  ; |d|^2
    comiss  xmm1, [k_eps]
    ja      .fire_dir
    mov     dword [rsp + E_TMP], 0      ; degenerate: straight up
    mov     eax, [k_one]
    mov     [rsp + E_TMP + 4], eax
    mov     dword [rsp + E_TMP + 8], 0
    movss   xmm1, [k_one]
.fire_dir:
    sqrtss  xmm1, xmm1
    movss   xmm0, [k_one]
    divss   xmm0, xmm1
    movss   [rsp + E_SCALE], xmm0       ; 1 / |d|
    movss   xmm0, [k_fire_v0]
    movss   xmm1, [k_fire_v1]
    call    rnd_range
    mulss   xmm0, [rsp + E_R]
    mulss   xmm0, [k_third]
    mulss   xmm0, [rsp + E_SCALE]       ; speed / |d|
    movss   xmm1, [rsp + E_TMP]
    mulss   xmm1, xmm0
    movss   [rbx + PARTICLE.vx], xmm1
    movss   xmm1, [rsp + E_TMP + 4]
    mulss   xmm1, xmm0
    movss   [rbx + PARTICLE.vy], xmm1
    movss   xmm1, [rsp + E_TMP + 8]
    mulss   xmm1, xmm0
    movss   [rbx + PARTICLE.vz], xmm1
    movss   xmm0, [k_fire_lo]
    movss   xmm1, [k_fire_hi]
    call    rnd_range
    movss   [rbx + PARTICLE.size], xmm0
    mov     edi, 19
    call    rnd_mod
    add     eax, 20
    mov     [rbx + PARTICLE.life], eax
    mov     dword [rbx + PARTICLE.kind], FX_FIRE
    inc     r12d
    jmp     .fire
.fire_done:

    ; ---- smoke: within +-r/2 of the centre, rises 1..2.5 b/s, size 0.25..0.5, life 110..200 -
    movss   xmm0, [rsp + E_R]
    mulss   xmm0, [k_half]
    movss   [rsp + E_HALF], xmm0
    movss   xmm0, [rsp + E_R]
    mulss   xmm0, [k_smoke_n]
    cvttss2si r13d, xmm0
    xor     r12d, r12d
.smoke:
    cmp     r12d, r13d
    jae     .smoke_done
    call    alloc
    test    rax, rax
    jz      .smoke_done
    mov     rbx, rax
%assign off 0
%rep 3
    movss   xmm1, [rsp + E_HALF]
    xorps   xmm0, xmm0
    subss   xmm0, xmm1
    call    rnd_range
    addss   xmm0, [rsp + E_C + off]
    movss   [rbx + PARTICLE.x + off], xmm0
%assign off off + 4
%endrep
    movss   xmm0, [k_smoke_nh]
    movss   xmm1, [k_smoke_h]
    call    rnd_range
    movss   [rbx + PARTICLE.vx], xmm0
    movss   xmm0, [k_smoke_vy0]
    movss   xmm1, [k_smoke_vy1]
    call    rnd_range
    movss   [rbx + PARTICLE.vy], xmm0
    movss   xmm0, [k_smoke_nh]
    movss   xmm1, [k_smoke_h]
    call    rnd_range
    movss   [rbx + PARTICLE.vz], xmm0
    movss   xmm0, [k_smoke_s0]
    movss   xmm1, [k_smoke_s1]
    call    rnd_range
    movss   [rbx + PARTICLE.size], xmm0
    mov     edi, 91
    call    rnd_mod
    add     eax, 110
    mov     [rbx + PARTICLE.life], eax
    mov     dword [rbx + PARTICLE.kind], FX_SMOKE
    inc     r12d
    jmp     .smoke
.smoke_done:

    ; ---- shake and flash by the distance d from the player's eye --------------------
    lea     rdi, [rsp + E_EYE]
    call    player_eye
    movss   xmm0, [rsp + E_EYE]
    subss   xmm0, [rsp + E_C]
    mulss   xmm0, xmm0
    movss   xmm1, [rsp + E_EYE + 4]
    subss   xmm1, [rsp + E_C + 4]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    movss   xmm1, [rsp + E_EYE + 8]
    subss   xmm1, [rsp + E_C + 8]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    sqrtss  xmm0, xmm0                  ; d
    movss   [rsp + E_TMP], xmm0
    movss   xmm2, [rsp + E_R]
    maxss   xmm2, [k_tiny]
    movss   [rsp + E_SCALE], xmm2       ; r, kept off zero for the divisions
    ; shake += max(0, 1.5 (1 - d / 6r)), capped at 2.5
    mulss   xmm2, [k_6]
    divss   xmm0, xmm2
    movss   xmm1, [k_one]
    subss   xmm1, xmm0
    mulss   xmm1, [k_shk_k]
    xorps   xmm3, xmm3
    maxss   xmm1, xmm3
    addss   xmm1, [fx_shake]
    minss   xmm1, [k_shk_cap]
    movss   [fx_shake], xmm1
    ; flash = max(flash, 0.8 (1 - d / 3r))
    movss   xmm0, [rsp + E_TMP]
    movss   xmm2, [rsp + E_SCALE]
    mulss   xmm2, [k_3]
    divss   xmm0, xmm2
    movss   xmm1, [k_one]
    subss   xmm1, xmm0
    mulss   xmm1, [k_flash_k]
    maxss   xmm1, [fx_flash]
    movss   [fx_flash], xmm1

    add     rsp, E_FRAME
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; fx_debris(edi x, esi y, edx z, ecx block, xmm0..2 blast centre): one cube of that block's side
; texture, size 0.15..0.25, from the cell's centre away from the blast at 4..9 b/s and up 3..7
; b/s, life 40..80 steps. Nothing happens when the table is full.
; [rsp + 16..28] = cell centre, [rsp + 32] dx, [rsp + 36] dz, [rsp + 40] speed scale
fx_debris:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 48
    mov     r12d, ecx
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 8], xmm2
    cvtsi2ss xmm3, edi
    addss   xmm3, [k_half]
    movss   [rsp + 16], xmm3
    cvtsi2ss xmm3, esi
    addss   xmm3, [k_half]
    movss   [rsp + 20], xmm3
    cvtsi2ss xmm3, edx
    addss   xmm3, [k_half]
    movss   [rsp + 24], xmm3
    call    alloc
    test    rax, rax
    jz      .ret
    mov     rbx, rax
    mov     eax, [rsp + 16]
    mov     [rbx + PARTICLE.x], eax
    mov     eax, [rsp + 20]
    mov     [rbx + PARTICLE.y], eax
    mov     eax, [rsp + 24]
    mov     [rbx + PARTICLE.z], eax
    ; horizontal direction away from the blast
    movss   xmm0, [rsp + 16]
    subss   xmm0, [rsp]
    movss   [rsp + 32], xmm0
    movss   xmm1, [rsp + 24]
    subss   xmm1, [rsp + 8]
    movss   [rsp + 36], xmm1
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [k_eps]
    ja      .dir_ok
    movss   xmm0, [k_neg_one]           ; on the blast axis: any direction
    movss   xmm1, [k_one]
    call    rnd_range
    movss   [rsp + 32], xmm0
    movss   xmm0, [k_neg_one]
    movss   xmm1, [k_one]
    call    rnd_range
    movss   [rsp + 36], xmm0
    movss   xmm0, [rsp + 32]
    mulss   xmm0, xmm0
    movss   xmm1, [rsp + 36]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [k_eps]
    ja      .dir_ok
    mov     eax, [k_one]
    mov     [rsp + 32], eax
    mov     dword [rsp + 36], 0
    movss   xmm0, [k_one]
.dir_ok:
    sqrtss  xmm0, xmm0
    movss   xmm1, [k_one]
    divss   xmm1, xmm0
    movss   [rsp + 40], xmm1            ; 1 / |d|
    movss   xmm0, [k_deb_v0]
    movss   xmm1, [k_deb_v1]
    call    rnd_range
    mulss   xmm0, [rsp + 40]
    movss   xmm1, [rsp + 32]
    mulss   xmm1, xmm0
    movss   [rbx + PARTICLE.vx], xmm1
    movss   xmm1, [rsp + 36]
    mulss   xmm1, xmm0
    movss   [rbx + PARTICLE.vz], xmm1
    movss   xmm0, [k_deb_up0]
    movss   xmm1, [k_deb_up1]
    call    rnd_range
    movss   [rbx + PARTICLE.vy], xmm0
    movss   xmm0, [k_deb_s0]
    movss   xmm1, [k_deb_s1]
    call    rnd_range
    movss   [rbx + PARTICLE.size], xmm0
    mov     edi, 41
    call    rnd_mod
    add     eax, 40
    mov     [rbx + PARTICLE.life], eax
    lea     rax, [block_tiles]
    lea     ecx, [r12 + r12*2]
    movzx   eax, byte [rax + rcx + 1]   ; the block's side tile
    mov     [rbx + PARTICLE.tile], eax
    mov     dword [rbx + PARTICLE.kind], FX_DEBRIS
.ret:
    add     rsp, 48
    pop     r12
    pop     rbx
    pop     rbp
    ret

; rand_dir(rdi out float[3]): a random unit vector (a point of the cube [-1, 1)^3 normalised;
; straight up for a draw too close to the centre)
rand_dir:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdi
%assign off 0
%rep 3
    movss   xmm0, [k_neg_one]
    movss   xmm1, [k_one]
    call    rnd_range
    movss   [rbx + off], xmm0
%assign off off + 4
%endrep
    movss   xmm1, [rbx]
    mulss   xmm1, xmm1
    movss   xmm0, [rbx + 4]
    mulss   xmm0, xmm0
    addss   xmm1, xmm0
    movss   xmm0, [rbx + 8]
    mulss   xmm0, xmm0
    addss   xmm1, xmm0                  ; |d|^2
    comiss  xmm1, [k_eps]
    ja      .unit
    mov     dword [rbx], 0
    mov     eax, [k_one]
    mov     [rbx + 4], eax
    mov     dword [rbx + 8], 0
    jmp     .done
.unit:
    sqrtss  xmm1, xmm1
    movss   xmm0, [k_one]
    divss   xmm0, xmm1                  ; 1 / |d|
%assign off 0
%rep 3
    movss   xmm1, [rbx + off]
    mulss   xmm1, xmm0
    movss   [rbx + off], xmm1
%assign off off + 4
%endrep
.done:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

%define B_P     0                       ; float position[3]
%define B_V     12                      ; float unit direction[3]
%define B_SPEED 24                      ; float
%define B_FRAME 32

; fx_burst(xmm0..2 position, edi kind, esi count, xmm3 speed): count particles of one kind
; (FX_FIRE, FX_SMOKE, FX_SPARK, FX_MAGIC or FX_GOLD) fly off from the position in random
; directions at speed * U(0.5, 1) blocks per second, each with the size and life its kind has in
; burst_tab. Any other kind spawns nothing; when the table is full the rest is dropped.
; rbx = the particle being filled, r12d = particles left, r13 = the kind's burst_tab row,
; r14d = kind.
fx_burst:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, B_FRAME
    movss   [rsp + B_P], xmm0
    movss   [rsp + B_P + 4], xmm1
    movss   [rsp + B_P + 8], xmm2
    movss   [rsp + B_SPEED], xmm3
    mov     r12d, esi
    mov     r14d, edi
    lea     eax, [rdi - FX_FIRE]
    cmp     eax, FX_GOLD - FX_FIRE
    ja      .done                       ; not a particle kind
    cmp     edi, FX_DEBRIS
    je      .done                       ; debris is fx_debris's
    shl     eax, 4                      ; 16 bytes per row
    lea     r13, [burst_tab]
    add     r13, rax
.loop:
    test    r12d, r12d
    jle     .done
    call    alloc
    test    rax, rax
    jz      .done
    mov     rbx, rax
%assign off 0
%rep 3
    mov     eax, [rsp + B_P + off]
    mov     [rbx + PARTICLE.x + off], eax
%assign off off + 4
%endrep
    lea     rdi, [rsp + B_V]
    call    rand_dir
    movss   xmm0, [k_half]
    movss   xmm1, [k_one]
    call    rnd_range                   ; U(0.5, 1)
    mulss   xmm0, [rsp + B_SPEED]
%assign off 0
%rep 3
    movss   xmm1, [rsp + B_V + off]
    mulss   xmm1, xmm0
    movss   [rbx + PARTICLE.vx + off], xmm1
%assign off off + 4
%endrep
    movss   xmm0, [r13]
    movss   xmm1, [r13 + 4]
    call    rnd_range
    movss   [rbx + PARTICLE.size], xmm0
    mov     edi, [r13 + 12]
    call    rnd_mod
    add     eax, [r13 + 8]
    mov     [rbx + PARTICLE.life], eax
    mov     [rbx + PARTICLE.kind], r14d ; set last: the particle exists from here
    dec     r12d
    jmp     .loop
.done:
    add     rsp, B_FRAME
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; MOVE_POS: position += velocity / 60 for the particle at rbx
%macro MOVE_POS 0
%assign i 0
%rep 3
    movss   xmm0, [rbx + PARTICLE.vx + i]
    mulss   xmm0, [k_dt]
    addss   xmm0, [rbx + PARTICLE.x + i]
    movss   [rbx + PARTICLE.x + i], xmm0
%assign i i + 4
%endrep
%endmacro

; fx_step(): once per fixed step. Moves every particle, ages them, decays shake and flash and
; draws this step's camera offsets. rbx = the particle, [rsp] = the new position of debris.
fx_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 32
    lea     rbx, [fx_particles]
    lea     r12, [fx_particles_end]
.loop:
    mov     eax, [rbx + PARTICLE.kind]
    test    eax, eax
    jz      .next
    cmp     eax, FX_FIRE
    je      .fire
    cmp     eax, FX_SMOKE
    je      .smoke
    cmp     eax, FX_SPARK
    je      .spark
    cmp     eax, FX_MAGIC
    je      .magic
    cmp     eax, FX_GOLD
    je      .gold
    ; ---- debris: gravity, then move unless the new cell is solid (then bounce) ----------
    movss   xmm0, [rbx + PARTICLE.vy]
    subss   xmm0, [k_grav]
    movss   [rbx + PARTICLE.vy], xmm0
%assign i 0
%rep 3
    movss   xmm0, [rbx + PARTICLE.vx + i]
    mulss   xmm0, [k_dt]
    addss   xmm0, [rbx + PARTICLE.x + i]
    movss   [rsp + i], xmm0
%assign i i + 4
%endrep
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    call    solid_at
    test    eax, eax
    jnz     .bounce
    mov     eax, [rsp]
    mov     [rbx + PARTICLE.x], eax
    mov     eax, [rsp + 4]
    mov     [rbx + PARTICLE.y], eax
    mov     eax, [rsp + 8]
    mov     [rbx + PARTICLE.z], eax
    jmp     .age
.bounce:
    movss   xmm0, [rbx + PARTICLE.vy]
    mulss   xmm0, [k_bounce]
    movss   [rbx + PARTICLE.vy], xmm0
    movss   xmm0, [rbx + PARTICLE.vx]
    mulss   xmm0, [k_friction]
    movss   [rbx + PARTICLE.vx], xmm0
    movss   xmm0, [rbx + PARTICLE.vz]
    mulss   xmm0, [k_friction]
    movss   [rbx + PARTICLE.vz], xmm0
    jmp     .age
.fire:
%assign i 0
%rep 3
    movss   xmm0, [rbx + PARTICLE.vx + i]
    mulss   xmm0, [k_fire_dv]
    movss   [rbx + PARTICLE.vx + i], xmm0
%assign i i + 4
%endrep
    movss   xmm0, [rbx + PARTICLE.vy]
    addss   xmm0, [k_fire_up]
    movss   [rbx + PARTICLE.vy], xmm0
    movss   xmm0, [rbx + PARTICLE.size]
    mulss   xmm0, [k_fire_sz]
    movss   [rbx + PARTICLE.size], xmm0
    MOVE_POS
    jmp     .age
.smoke:
%assign i 0
%rep 3
    movss   xmm0, [rbx + PARTICLE.vx + i]
    mulss   xmm0, [k_smoke_dv]
    movss   [rbx + PARTICLE.vx + i], xmm0
%assign i i + 4
%endrep
    movss   xmm0, [rbx + PARTICLE.size]
    mov     eax, [rbx + PARTICLE.life]
    sub     eax, [rbx + PARTICLE.age]
    cmp     eax, SMOKE_FADE
    jle     .smoke_fade
    addss   xmm0, [k_smoke_gr]          ; billowing out...
    jmp     .smoke_size
.smoke_fade:
    mulss   xmm0, [k_smoke_fd]          ; ...then thinning away over its last steps
.smoke_size:
    movss   [rbx + PARTICLE.size], xmm0
    MOVE_POS
    jmp     .age
.spark:                                 ; sparks arc: vy -= 0.3 per step
    movss   xmm0, [rbx + PARTICLE.vy]
    subss   xmm0, [k_spark_g]
    movss   [rbx + PARTICLE.vy], xmm0
    MOVE_POS
    jmp     .age
.magic:                                 ; magic motes slow down: v *= 0.9 per step
%assign i 0
%rep 3
    movss   xmm0, [rbx + PARTICLE.vx + i]
    mulss   xmm0, [k_magic_dv]
    movss   [rbx + PARTICLE.vx + i], xmm0
%assign i i + 4
%endrep
    MOVE_POS
    jmp     .age
.gold:                                  ; gold glitter drifts up: vy += 0.04 per step
    movss   xmm0, [rbx + PARTICLE.vy]
    addss   xmm0, [k_gold_up]
    movss   [rbx + PARTICLE.vy], xmm0
    MOVE_POS
.age:
    inc     dword [rbx + PARTICLE.age]
    mov     eax, [rbx + PARTICLE.age]
    cmp     eax, [rbx + PARTICLE.life]
    jb      .next
    mov     dword [rbx + PARTICLE.kind], 0
.next:
    add     rbx, PARTICLE_size
    cmp     rbx, r12
    jb      .loop

    ; ---- shake decays x 0.88 (0 below 0.02); a fresh random offset in +-1.5 shake ------------
    movss   xmm0, [fx_shake]
    mulss   xmm0, [k_shk_dec]
    comiss  xmm0, [k_shk_min]
    jae     .shake_set
    xorps   xmm0, xmm0
.shake_set:
    movss   [fx_shake], xmm0
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    ja      .shake_rand
    mov     dword [fx_shake_yaw], 0
    mov     dword [fx_shake_pitch], 0
    jmp     .flash
.shake_rand:
    mulss   xmm0, [k_shk_k]
    movss   [rsp], xmm0                 ; 1.5 shake
    movss   xmm0, [k_neg_one]
    movss   xmm1, [k_one]
    call    rnd_range
    mulss   xmm0, [rsp]
    movss   [fx_shake_yaw], xmm0
    movss   xmm0, [k_neg_one]
    movss   xmm1, [k_one]
    call    rnd_range
    mulss   xmm0, [rsp]
    movss   [fx_shake_pitch], xmm0
.flash:
    movss   xmm0, [fx_flash]
    subss   xmm0, [k_flash_dec]
    xorps   xmm1, xmm1
    maxss   xmm0, xmm1
    movss   [fx_flash], xmm0
    add     rsp, 32
    pop     r12
    pop     rbx
    pop     rbp
    ret

; draw_pass(edi mode) -> eax particles drawn. Mode 0 draws the debris cubes (textured with their
; tile, shaded like a block); mode 1 draws fire (yellow -> red), sparks, magic and gold (their
; kind's two colours; all flat) and smoke (grey, shaded) with the caller having switched
; texturing off.
; rbx = particle, r12d = mode, r13d = drawn; [rsp] = box, [rsp + 24] = tile bytes
draw_pass:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 56
    mov     r12d, edi
    xor     r13d, r13d
    lea     rbx, [fx_particles]
.loop:
    mov     eax, [rbx + PARTICLE.kind]
    test    eax, eax
    jz      .next
    test    r12d, r12d
    jnz     .want_flat
    cmp     eax, FX_DEBRIS
    jne     .next
    jmp     .draw
.want_flat:
    cmp     eax, FX_DEBRIS
    je      .next
.draw:
    xorps   xmm2, xmm2                  ; a burst at the player's own chest would fill the view
%assign i 0
%rep 3
    movss   xmm0, [rbx + PARTICLE.x + i]
    subss   xmm0, [cull_eye + i]
    mulss   xmm0, xmm0
    addss   xmm2, xmm0
%assign i i + 4
%endrep
    comiss  xmm2, [k_near2]
    jb      .next
    movss   xmm4, [rbx + PARTICLE.size]
    mulss   xmm4, [k_half]
%assign i 0
%rep 3
    movss   xmm0, [rbx + PARTICLE.x + i]
    movaps  xmm1, xmm0
    subss   xmm0, xmm4
    addss   xmm1, xmm4
    movss   [rsp + i], xmm0
    movss   [rsp + 12 + i], xmm1
%assign i i + 4
%endrep
    mov     eax, [rbx + PARTICLE.kind]
    cmp     eax, FX_DEBRIS
    je      .debris
    cvtsi2ss xmm4, dword [rbx + PARTICLE.age]
    cvtsi2ss xmm5, dword [rbx + PARTICLE.life]
    divss   xmm4, xmm5                  ; t = age / life
    cmp     eax, FX_FIRE
    je      .fire
    cmp     eax, FX_SMOKE
    je      .smoke_col
    sub     eax, FX_SPARK               ; sparks, magic and gold: the row of k_burst_col
    lea     eax, [rax + rax*2]
    shl     eax, 3                      ; 24 bytes per kind
    lea     rcx, [k_burst_col]
    add     rcx, rax
%assign i 0
%rep 3
    movss   xmm %+ i, [rcx + 12 + i*4]
    subss   xmm %+ i, [rcx + i*4]
    mulss   xmm %+ i, xmm4
    addss   xmm %+ i, [rcx + i*4]
%assign i i + 1
%endrep
    lea     rsi, [zero_tiles]
    lea     rdx, [shades_flat]
    jmp     .call
.smoke_col:
    movss   xmm0, [k_smoke_g1]          ; grey 0.55 -> 0.25
    subss   xmm0, [k_smoke_g0]
    mulss   xmm0, xmm4
    addss   xmm0, [k_smoke_g0]
    movaps  xmm1, xmm0
    movaps  xmm2, xmm0
    lea     rsi, [zero_tiles]
    lea     rdx, [shades_block]
    jmp     .call
.fire:
    movss   xmm0, [k_fire_r1]
    subss   xmm0, [k_fire_r0]
    mulss   xmm0, xmm4
    addss   xmm0, [k_fire_r0]
    movss   xmm1, [k_fire_g1]
    subss   xmm1, [k_fire_g0]
    mulss   xmm1, xmm4
    addss   xmm1, [k_fire_g0]
    movss   xmm2, [k_fire_b1]
    subss   xmm2, [k_fire_b0]
    mulss   xmm2, xmm4
    addss   xmm2, [k_fire_b0]
    lea     rsi, [zero_tiles]
    lea     rdx, [shades_flat]
    jmp     .call
.debris:
    mov     eax, [rbx + PARTICLE.tile]
    mov     rcx, 0x0101010101010101
    imul    rax, rcx
    mov     [rsp + 24], rax
    movss   xmm0, [k_one]
    movss   xmm1, xmm0
    movss   xmm2, xmm0
    lea     rsi, [rsp + 24]
    lea     rdx, [shades_block]
.call:
    mov     rdi, rsp
    call    render_box
    inc     r13d
.next:
    add     rbx, PARTICLE_size
    lea     rax, [fx_particles_end]
    cmp     rbx, rax
    jb      .loop
    mov     eax, r13d
    add     rsp, 56
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; fx_render(): every particle as a cube. Called inside the world pass (atlas bound, alpha test
; on, unit 1 darkening the lit texel). Debris is drawn first, textured, and so follows the night
; darkening. Fire and smoke are then drawn with texturing off on unit 0 and on unit 1, so they
; glow regardless of the hour. Every texture unit state and the current colour are restored.
; [rsp] = saved colour, [rsp + 16] unit 0 was enabled, [rsp + 20] unit 1 was enabled,
; [rsp + 24] live particles
fx_render:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 48
    call    fx_count
    test    eax, eax
    jz      .ret
    mov     [rsp + 24], eax
    lea     rdi, [cull_eye]
    call    player_eye
    mov     edi, GL_CURRENT_COLOR
    mov     rsi, rsp
    call    glGetFloatv
    xor     edi, edi
    call    draw_pass
    cmp     eax, [rsp + 24]
    jae     .colour                     ; nothing but debris
    mov     edi, GL_TEXTURE_2D
    call    glIsEnabled
    movzx   eax, al
    mov     [rsp + 16], eax
    mov     edi, GL_TEXTURE1
    call    glActiveTexture
    mov     edi, GL_TEXTURE_2D
    call    glIsEnabled
    movzx   eax, al
    mov     [rsp + 20], eax
    mov     edi, GL_TEXTURE_2D
    call    glDisable
    mov     edi, GL_TEXTURE0
    call    glActiveTexture
    mov     edi, GL_TEXTURE_2D
    call    glDisable
    mov     edi, 1
    call    draw_pass
    cmp     dword [rsp + 16], 0
    je      .unit1
    mov     edi, GL_TEXTURE_2D
    call    glEnable
.unit1:
    cmp     dword [rsp + 20], 0
    je      .colour
    mov     edi, GL_TEXTURE1
    call    glActiveTexture
    mov     edi, GL_TEXTURE_2D
    call    glEnable
    mov     edi, GL_TEXTURE0
    call    glActiveTexture
.colour:
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    movss   xmm3, [rsp + 12]
    call    glColor4f
.ret:
    add     rsp, 48
    pop     r12
    pop     rbx
    pop     rbp
    ret
