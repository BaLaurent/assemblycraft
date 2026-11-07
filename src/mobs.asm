; mobs.asm - zombies and pigs: slot storage, AI, spawning, ray/block queries, damage, save records.
; A MOB starts with its BODY (MOB.body = 0), so a mob pointer is also a body pointer.
%include "common.inc"
default rel

global mobs, mob_count_type, mobs_clear, mobs_step, mobs_populate
global mob_spawn, mobs_raycast, mob_hurt, mobs_intersect_block
global mobs_save, mobs_load

extern body_init, body_step, body_intersects_block, player
extern rng_next, sincos_deg, atan2_deg
extern world_top_y, world_get
extern sky_brightness, sky_is_night
extern survival_damage, surv, inv_add, audio_play_at
extern settings, game_mode, game_time

%define ZOMBIE_CAP    8                 ; zombies the spawner keeps alive
%define PIG_CAP       10                ; pigs the spawner keeps alive
%define HURT_STEPS    10                ; mob_hurt invulnerability window
%define HIT_COOLDOWN  60                ; steps between zombie hits
%define PANIC_STEPS   180               ; a hurt pig runs this long
; ground a mob may spawn on, one bit per block id
%define ZOMBIE_GROUND ((1 << STONE) | (1 << GRASS) | (1 << DIRT) | (1 << COBBLE) | (1 << SAND))
%define PIG_GROUND    (1 << GRASS)

section .rodata
align 4
; per-type tables, index = type - 1 (zombie, pig)
t_half_w:   dd 0.3, 0.45
t_height:   dd 1.8, 0.9
t_speed:    dd 2.6, 1.6
t_health:   dd 20, 10
t_dmg:      dd 0, 2, 3, 4               ; zombie hit by difficulty
t_say:      db SND_ZOMBIE_SAY, SND_PIG_SAY
t_hurt:     db SND_ZOMBIE_HURT, SND_PIG_HURT
align 4
c_360:      dd 360.0
c_180:      dd 180.0                    ; walk-cycle degrees per block walked
c_half:     dd 0.5
c_aggro2:   dd 576.0                    ; zombies notice the player within 24 blocks
c_reach2:   dd 2.89                     ; zombie hit range 1.7 blocks, squared
c_far2:     dd 9216.0                   ; zombies further than 96 blocks vanish
c_kb:       dd 6.0                      ; knockback speed
c_tiny:     dd 0.0001
c_day:      dd 0.8                      ; brightness at which zombies burn
c_vol_say:  dd 0.7
c_vol_hurt: dd 1.0
c_pig_run:  dd 3.2                      ; panicking pig speed
c_pig_walk: dd 1.6
c_256:      dd 256.0
c_64:       dd 64.0

section .bss
alignb 16
mobs:       resb MAX_MOBS * MOB_size
mobs_end:

section .text

; mobs_clear(): remove every mob
mobs_clear:
    lea     rdi, [mobs]
    mov     ecx, MAX_MOBS * MOB_size
    xor     eax, eax
    rep     stosb
    ret

; mob_count_type(edi type) -> eax number of live mobs of that type
mob_count_type:
    xor     eax, eax
    lea     rcx, [mobs]
    lea     rdx, [mobs_end]
.loop:
    cmp     [rcx + MOB.type], edi
    jne     .next
    inc     eax
.next:
    add     rcx, MOB_size
    cmp     rcx, rdx
    jb      .loop
    ret

; mob_spawn(edi type, xmm0 x, xmm1 y, xmm2 z) -> eax slot index, or -1 (bad type / no free slot)
mob_spawn:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 24                     ; [rsp] x, [rsp+4] y, [rsp+8] z
    lea     eax, [rdi - 1]
    cmp     eax, 1
    ja      .none                       ; only zombies and pigs exist
    mov     ebx, edi
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 8], xmm2
    lea     r12, [mobs]
    xor     r13d, r13d
.find:
    cmp     dword [r12 + MOB.type], MOB_NONE
    je      .found
    add     r12, MOB_size
    inc     r13d
    cmp     r13d, MAX_MOBS
    jb      .find
.none:
    mov     eax, -1
    jmp     .ret
.found:
    lea     ecx, [rbx - 1]
    movss   xmm0, [t_half_w + rcx*4]
    movss   xmm1, [t_height + rcx*4]
    movss   xmm2, [t_speed + rcx*4]
    mov     rdi, r12
    call    body_init                   ; zeroes the body, then sets box and speed
    lea     rdi, [r12 + BODY_size]      ; clear everything after the body (stale after a removal)
    mov     ecx, MOB_size - BODY_size
    xor     eax, eax
    rep     stosb
    mov     [r12 + MOB.type], ebx
    lea     ecx, [rbx - 1]
    mov     eax, [t_health + rcx*4]
    mov     [r12 + MOB.health], eax
    mov     eax, [rsp]
    mov     [r12 + BODY.x], eax
    mov     eax, [rsp + 4]
    mov     [r12 + BODY.y], eax
    mov     eax, [rsp + 8]
    mov     [r12 + BODY.z], eax
    call    rng_next                    ; yaw = rng % 360
    xor     edx, edx
    mov     ecx, 360
    div     ecx
    cvtsi2ss xmm0, edx
    movss   [r12 + BODY.yaw], xmm0
    mov     eax, r13d
.ret:
    add     rsp, 24
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; yaw_from(xmm0 dx, xmm1 dz) -> xmm0 heading in [0, 360) whose forward vector (sin, -cos) runs along (dx, dz)
yaw_from:
    sub     rsp, 8
    xorps   xmm2, xmm2
    subss   xmm2, xmm1
    movaps  xmm1, xmm2                  ; atan2(dx, -dz)
    call    atan2_deg
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jae     .done
    addss   xmm0, [c_360]
    comiss  xmm0, [c_360]
    jb      .done                       ; a tiny negative angle can round up to exactly 360
    subss   xmm0, [c_360]
.done:
    add     rsp, 8
    ret

; mob_ai(rdi mob): this step's input and heading.
; Zombies hunt a living player within 24 blocks (Survival, difficulty > 0) and hit when close;
; a panicking pig runs along its heading; everything else wanders in 1-4 s legs.
; Frame: [rsp] dx, [rsp+4] dz, [rsp+8] horizontal distance^2 to the player.
mob_ai:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 24
    mov     rbx, rdi
    xor     eax, eax
    mov     [rbx + MOB.input + INPUT.strafe], eax
    mov     [rbx + MOB.input + INPUT.down], eax
    mov     [rbx + MOB.input + INPUT.sprint], eax
    cmp     dword [rbx + MOB.type], MOB_ZOMBIE
    jne     .pig
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .wander
    cmp     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL
    je      .wander
    cmp     dword [surv + SURVIVAL.dead], 0
    jne     .wander
    movss   xmm0, [player + BODY.x]
    subss   xmm0, [rbx + BODY.x]
    movss   [rsp], xmm0                 ; dx
    movss   xmm1, [player + BODY.z]
    subss   xmm1, [rbx + BODY.z]
    movss   [rsp + 4], xmm1             ; dz
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    movss   [rsp + 8], xmm0
    comiss  xmm0, [c_aggro2]
    jae     .wander                     ; too far to notice
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    call    yaw_from
    movss   [rbx + BODY.yaw], xmm0
    mov     dword [rbx + MOB.input + INPUT.fwd], 1
    cmp     dword [rbx + MOB.cooldown], 0
    jne     .jump
    movss   xmm0, [player + BODY.y]     ; body centres are both feet + 0.9, so only the feet differ
    subss   xmm0, [rbx + BODY.y]
    mulss   xmm0, xmm0
    addss   xmm0, [rsp + 8]
    comiss  xmm0, [c_reach2]
    jae     .jump
    mov     eax, [settings + SETTINGS.difficulty]
    mov     ecx, DIFF_HARD
    cmp     eax, ecx
    cmova   eax, ecx
    mov     edi, [t_dmg + rax*4]
    mov     esi, CAUSE_ZOMBIE
    call    survival_damage
    test    eax, eax
    jz      .jump                       ; not applied (invulnerable): try again next step
    movss   xmm2, [rsp + 8]
    sqrtss  xmm2, xmm2                  ; knock the player back along zombie -> player on the ground plane
    comiss  xmm2, [c_tiny]
    jb      .lift                       ; standing exactly on the player: no direction
    movss   xmm3, [c_kb]
    divss   xmm3, xmm2
    movss   xmm0, [rsp]
    mulss   xmm0, xmm3
    movss   [player + BODY.kbx], xmm0
    movss   xmm1, [rsp + 4]
    mulss   xmm1, xmm3
    movss   [player + BODY.kbz], xmm1
.lift:
    cmp     dword [player + BODY.on_ground], 0
    je      .hit_done
    mov     dword [player + BODY.vy], __float32__(5.0)
.hit_done:
    mov     dword [rbx + MOB.cooldown], HIT_COOLDOWN
    jmp     .jump
.pig:
    cmp     dword [rbx + MOB.panic], 0
    jle     .wander
    mov     eax, [c_pig_run]
    mov     [rbx + BODY.speed], eax
    mov     dword [rbx + MOB.input + INPUT.fwd], 1
    dec     dword [rbx + MOB.panic]
    jnz     .jump
    mov     eax, [c_pig_walk]           ; panic over: back to the stroll speed
    mov     [rbx + BODY.speed], eax
    jmp     .jump
.wander:
    mov     eax, [rbx + MOB.ai_timer]
    dec     dword [rbx + MOB.ai_timer]
    test    eax, eax
    jg      .jump                       ; keep the current leg
    call    rng_next                    ; next leg lasts 60 + rng % 180 steps
    xor     edx, edx
    mov     ecx, 180
    div     ecx
    add     edx, 60
    mov     [rbx + MOB.ai_timer], edx
    call    rng_next
    test    al, 1
    jz      .stand
    call    rng_next                    ; walk off in a random direction
    xor     edx, edx
    mov     ecx, 360
    div     ecx
    cvtsi2ss xmm0, edx
    movss   [rbx + BODY.yaw], xmm0
    mov     dword [rbx + MOB.input + INPUT.fwd], 1
    jmp     .jump
.stand:
    mov     dword [rbx + MOB.input + INPUT.fwd], 0
.jump:                                  ; hop when walking into something
    xor     eax, eax
    cmp     dword [rbx + MOB.input + INPUT.fwd], 0
    je      .store_jump
    cmp     dword [rbx + BODY.blocked], 0
    je      .store_jump
    cmp     dword [rbx + BODY.on_ground], 0
    je      .store_jump
    mov     eax, 1
.store_jump:
    mov     [rbx + MOB.input + INPUT.jump], eax
    add     rsp, 24
    pop     rbx
    pop     rbp
    ret

; mob_update(rdi mob): one fixed step for a live mob (AI, physics, timers, sound, sunlight, despawn).
; Frame: [rsp] x and [rsp+4] z before the move.
mob_update:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 24
    mov     rbx, rdi
    call    mob_ai
    movss   xmm0, [rbx + BODY.x]
    movss   [rsp], xmm0
    movss   xmm0, [rbx + BODY.z]
    movss   [rsp + 4], xmm0
    mov     rdi, rbx
    lea     rsi, [rbx + MOB.input]
    call    body_step
    movss   xmm0, [rbx + BODY.x]        ; walk cycle: 180 degrees per block walked
    subss   xmm0, [rsp]
    mulss   xmm0, xmm0
    movss   xmm1, [rbx + BODY.z]
    subss   xmm1, [rsp + 4]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    sqrtss  xmm0, xmm0
    mulss   xmm0, [c_180]
    addss   xmm0, [rbx + MOB.walk]
    movss   xmm1, [c_360]
    comiss  xmm0, xmm1
    jb      .walk_ok
    subss   xmm0, xmm1                  ; one wrap is enough: a step adds < 360 degrees (< 2 blocks)
.walk_ok:
    movss   [rbx + MOB.walk], xmm0
    cmp     dword [rbx + MOB.hurt], 0
    jle     .no_hurt
    dec     dword [rbx + MOB.hurt]
.no_hurt:
    cmp     dword [rbx + MOB.cooldown], 0
    jle     .no_cooldown
    dec     dword [rbx + MOB.cooldown]
.no_cooldown:
    call    rng_next                    ; ambient call about every 10 s
    xor     edx, edx
    mov     ecx, 600
    div     ecx
    test    edx, edx
    jnz     .quiet
    mov     eax, [rbx + MOB.type]
    movzx   edi, byte [t_say + rax - 1]
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [c_vol_say]
    call    audio_play_at
.quiet:
    cmp     dword [rbx + MOB.type], MOB_ZOMBIE
    jne     .done
    mov     eax, [game_time]            ; sunlight: -2 health every 20 steps in bright daylight
    xor     edx, edx
    mov     ecx, 20
    div     ecx
    test    edx, edx
    jnz     .despawn
    mov     edi, [game_time]
    call    sky_brightness
    comiss  xmm0, [c_day]
    jb      .despawn
    movss   xmm0, [rbx + BODY.x]
    roundss xmm0, xmm0, 9
    cvttss2si edi, xmm0
    movss   xmm0, [rbx + BODY.z]
    roundss xmm0, xmm0, 9
    cvttss2si esi, xmm0
    call    world_top_y
    movss   xmm0, [rbx + BODY.y]
    addss   xmm0, [rbx + BODY.height]
    roundss xmm0, xmm0, 9
    cvttss2si ecx, xmm0                 ; cell of the head top
    cmp     eax, ecx
    jge     .despawn                    ; roofed over: the sun cannot reach it
    sub     dword [rbx + MOB.health], 2
    jg      .despawn
    mov     dword [rbx + MOB.type], MOB_NONE
    jmp     .done
.despawn:
    cmp     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL
    je      .remove                     ; peaceful: no zombies at all
    movss   xmm0, [player + BODY.x]
    subss   xmm0, [rbx + BODY.x]
    mulss   xmm0, xmm0
    movss   xmm1, [player + BODY.z]
    subss   xmm1, [rbx + BODY.z]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [c_far2]
    jbe     .done
.remove:
    mov     dword [rbx + MOB.type], MOB_NONE
.done:
    add     rsp, 24
    pop     rbx
    pop     rbp
    ret

; spawn_at_ground(edi type, esi x, edx z, ecx ground mask) -> eax slot index, or -1.
; Needs 1 <= x, z <= 254, a surface at y + 1 <= 62 and a top block whose bit is set in the mask.
spawn_at_ground:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    lea     eax, [rsi - 1]
    cmp     eax, 253
    ja      .fail
    lea     eax, [rdx - 1]
    cmp     eax, 253
    ja      .fail
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    mov     edi, r12d
    mov     esi, r13d
    call    world_top_y
    test    eax, eax
    js      .fail                       ; empty column
    cmp     eax, 61
    jg      .fail
    mov     r15d, eax
    mov     edi, r12d
    mov     esi, r15d
    mov     edx, r13d
    call    world_get
    cmp     eax, 31
    ja      .fail
    bt      r14d, eax
    jnc     .fail
    movss   xmm3, [c_half]
    cvtsi2ss xmm0, r12d
    addss   xmm0, xmm3                  ; x + 0.5
    lea     eax, [r15 + 1]
    cvtsi2ss xmm1, eax                  ; on top of the ground
    cvtsi2ss xmm2, r13d
    addss   xmm2, xmm3                  ; z + 0.5
    mov     edi, ebx
    call    mob_spawn
    jmp     .ret
.fail:
    mov     eax, -1
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; spawn_near_player(edi type, esi min distance, edx distance range, ecx ground mask) -> eax slot or -1.
; Picks a random bearing and a distance in [min, min + range) around the player.
; Frame: [rsp] sin, [rsp+4] cos of the bearing.
spawn_near_player:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 16
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    call    rng_next                    ; bearing = rng % 360 degrees
    xor     edx, edx
    mov     ecx, 360
    div     ecx
    cvtsi2ss xmm0, edx
    call    sincos_deg
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    call    rng_next                    ; distance
    xor     edx, edx
    div     r13d
    add     edx, r12d
    cvtsi2ss xmm2, edx
    movss   xmm0, [rsp]
    mulss   xmm0, xmm2
    addss   xmm0, [player + BODY.x]     ; x = px + sin * dist
    roundss xmm0, xmm0, 9
    cvttss2si esi, xmm0
    movss   xmm1, [rsp + 4]
    mulss   xmm1, xmm2
    movss   xmm3, [player + BODY.z]
    subss   xmm3, xmm1                  ; z = pz - cos * dist
    roundss xmm3, xmm3, 9
    cvttss2si edx, xmm3
    mov     edi, ebx
    mov     ecx, r14d
    call    spawn_at_ground
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mobs_spawn_tick(): the ambient spawner, once per fixed step.
; Zombies every 60 steps at night in Survival (difficulty > 0, at most 8); pigs every
; 1800 steps by day (at most 10).
mobs_spawn_tick:
    push    rbp
    mov     rbp, rsp
    mov     eax, [game_time]
    xor     edx, edx
    mov     ecx, 60
    div     ecx
    test    edx, edx
    jnz     .pigs
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .pigs
    cmp     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL
    je      .pigs
    mov     edi, [game_time]
    call    sky_is_night
    test    eax, eax
    jz      .pigs
    mov     edi, MOB_ZOMBIE
    call    mob_count_type
    cmp     eax, ZOMBIE_CAP
    jae     .pigs
    mov     edi, MOB_ZOMBIE
    mov     esi, 24
    mov     edx, 17
    mov     ecx, ZOMBIE_GROUND
    call    spawn_near_player
.pigs:
    mov     eax, [game_time]
    xor     edx, edx
    mov     ecx, 1800
    div     ecx
    test    edx, edx
    jnz     .done
    mov     edi, [game_time]
    call    sky_is_night
    test    eax, eax
    jnz     .done
    mov     edi, MOB_PIG
    call    mob_count_type
    cmp     eax, PIG_CAP
    jae     .done
    mov     edi, MOB_PIG
    mov     esi, 24
    mov     edx, 25
    mov     ecx, PIG_GROUND
    call    spawn_near_player
.done:
    pop     rbp
    ret

; mobs_step(): one fixed 1/60 s step for every mob, then the spawner
mobs_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    lea     rbx, [mobs]
    lea     r12, [mobs_end]
.loop:
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .next
    mov     rdi, rbx
    call    mob_update
.next:
    add     rbx, MOB_size
    cmp     rbx, r12
    jb      .loop
    call    mobs_spawn_tick
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mobs_populate(): scatter pigs around the world centre (up to 200 tries, until 10 pigs live)
mobs_populate:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, 200
.try:
    mov     edi, MOB_PIG
    call    mob_count_type
    cmp     eax, PIG_CAP
    jae     .done
    call    rng_next                    ; x = 128 + rng % 97 - 48
    xor     edx, edx
    mov     ecx, 97
    div     ecx
    lea     r12d, [rdx + 80]
    call    rng_next
    xor     edx, edx
    mov     ecx, 97
    div     ecx
    add     edx, 80                     ; z
    mov     edi, MOB_PIG
    mov     esi, r12d
    mov     ecx, PIG_GROUND
    call    spawn_at_ground
    dec     ebx
    jnz     .try
.done:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ray_aabb(rdi origin[3], rsi dir[3], rdx lo[3], rcx hi[3], xmm0 tmax) -> eax 1 hit / 0 miss,
; xmm0 = entry distance t (0 when the origin is inside), 0 <= t <= tmax. Slab test.
ray_aabb:
    xorps   xmm1, xmm1                  ; tmin
    xorps   xmm6, xmm6
    xor     r8d, r8d                    ; byte offset of the axis
.axis:
    movss   xmm2, [rdi + r8]            ; o
    movss   xmm3, [rsi + r8]            ; d
    movss   xmm4, [rdx + r8]            ; lo
    movss   xmm5, [rcx + r8]            ; hi
    ucomiss xmm3, xmm6
    jp      .parallel
    jne     .slab
.parallel:                              ; no movement on this axis: the origin must be inside the slab
    ucomiss xmm2, xmm4
    jb      .miss
    ucomiss xmm2, xmm5
    ja      .miss
    jmp     .next
.slab:
    subss   xmm4, xmm2
    subss   xmm5, xmm2
    divss   xmm4, xmm3                  ; t at lo
    divss   xmm5, xmm3                  ; t at hi
    movaps  xmm7, xmm4
    minss   xmm7, xmm5                  ; entering the slab
    maxss   xmm4, xmm5                  ; leaving the slab
    maxss   xmm1, xmm7
    minss   xmm0, xmm4
.next:
    add     r8d, 4
    cmp     r8d, 12
    jb      .axis
    ucomiss xmm1, xmm0
    ja      .miss                       ; entry after exit or beyond tmax
    movaps  xmm0, xmm1
    mov     eax, 1
    ret
.miss:
    xor     eax, eax
    ret

; mobs_raycast(rdi origin[3], rsi dir[3], xmm0 max) -> eax index of the nearest mob hit within
; max (or -1), xmm0 = its distance t (max on a miss). Boxes: [x +- half_w] x [y, y + height] x [z +- half_w].
; Frame: lo[3] @0, hi[3] @16, best t @32.
mobs_raycast:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 56
    mov     r12, rdi
    mov     r13, rsi
    movss   [rsp + 32], xmm0
    mov     r15d, -1
    lea     rbx, [mobs]
    xor     r14d, r14d
.mob:
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .next
    movss   xmm3, [rbx + BODY.half_w]
    movss   xmm0, [rbx + BODY.x]
    movaps  xmm1, xmm0
    subss   xmm0, xmm3
    addss   xmm1, xmm3
    movss   [rsp], xmm0
    movss   [rsp + 16], xmm1
    movss   xmm0, [rbx + BODY.y]
    movss   [rsp + 4], xmm0
    addss   xmm0, [rbx + BODY.height]
    movss   [rsp + 20], xmm0
    movss   xmm0, [rbx + BODY.z]
    movaps  xmm1, xmm0
    subss   xmm0, xmm3
    addss   xmm1, xmm3
    movss   [rsp + 8], xmm0
    movss   [rsp + 24], xmm1
    mov     rdi, r12
    mov     rsi, r13
    lea     rdx, [rsp]
    lea     rcx, [rsp + 16]
    movss   xmm0, [rsp + 32]            ; only a hit nearer than the best so far counts
    call    ray_aabb
    test    eax, eax
    jz      .next
    movss   [rsp + 32], xmm0
    mov     r15d, r14d
.next:
    add     rbx, MOB_size
    inc     r14d
    cmp     r14d, MAX_MOBS
    jb      .mob
    movss   xmm0, [rsp + 32]
    mov     eax, r15d
    add     rsp, 56
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mob_hurt(edi idx, esi dmg, xmm0 dirx, xmm1 dirz) -> eax 1 applied / 0 (no such mob, or still in its
; hurt window). Knocks the mob along (dirx, dirz); a pig panics and flees that way, a dead pig drops pork.
; Frame: [rsp] dirx, [rsp+4] dirz.
mob_hurt:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 24
    cmp     edi, MAX_MOBS
    jae     .no
    imul    ebx, edi, MOB_size
    lea     rax, [mobs]
    add     rbx, rax
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .no
    cmp     dword [rbx + MOB.hurt], 0
    jg      .no
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    sub     [rbx + MOB.health], esi
    mov     dword [rbx + MOB.hurt], HURT_STEPS
    movss   xmm2, [c_kb]
    mulss   xmm0, xmm2
    movss   [rbx + BODY.kbx], xmm0
    mulss   xmm1, xmm2
    movss   [rbx + BODY.kbz], xmm1
    cmp     dword [rbx + BODY.on_ground], 0
    je      .sound
    mov     dword [rbx + BODY.vy], __float32__(4.0)
.sound:
    mov     eax, [rbx + MOB.type]
    movzx   edi, byte [t_hurt + rax - 1]
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [c_vol_hurt]
    call    audio_play_at
    cmp     dword [rbx + MOB.type], MOB_PIG
    jne     .check_dead
    mov     dword [rbx + MOB.panic], PANIC_STEPS
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    call    yaw_from                    ; run away from the attacker
    movss   [rbx + BODY.yaw], xmm0
.check_dead:
    cmp     dword [rbx + MOB.health], 0
    jg      .yes
    cmp     dword [rbx + MOB.type], MOB_PIG
    jne     .remove
    call    rng_next                    ; raw porkchop x (1 + rng % 3)
    xor     edx, edx
    mov     ecx, 3
    div     ecx
    mov     edi, PORKCHOP
    lea     esi, [rdx + 1]
    call    inv_add
.remove:
    mov     dword [rbx + MOB.type], MOB_NONE
.yes:
    mov     eax, 1
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    add     rsp, 24
    pop     rbx
    pop     rbp
    ret

; mobs_intersect_block(edi x, esi y, edx z) -> eax 1 if any live mob's box strictly overlaps the block
mobs_intersect_block:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r13d, edi
    mov     r14d, esi
    mov     r15d, edx
    lea     rbx, [mobs]
    lea     r12, [mobs_end]
.loop:
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .next
    mov     rdi, rbx
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, r15d
    call    body_intersects_block
    test    eax, eax
    jnz     .ret
.next:
    add     rbx, MOB_size
    cmp     rbx, r12
    jb      .loop
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mobs_save(rdi WORLDHDR*): the live mobs as compact MOBSAVE records, mob_count set
mobs_save:
    mov     r8, rdi
    lea     rdi, [r8 + WORLDHDR.mobs]
    mov     ecx, MAX_MOBS * MOBSAVE_size
    xor     eax, eax
    rep     stosb                       ; unused records read back as zero
    lea     rdi, [r8 + WORLDHDR.mobs]
    lea     rsi, [mobs]
    lea     rdx, [mobs_end]
    xor     ecx, ecx                    ; records written
.loop:
    mov     eax, [rsi + MOB.type]
    test    eax, eax
    jz      .next
    mov     [rdi + MOBSAVE.type], eax
    mov     eax, [rsi + MOB.health]
    mov     [rdi + MOBSAVE.health], eax
    mov     eax, [rsi + BODY.x]
    mov     [rdi + MOBSAVE.x], eax
    mov     eax, [rsi + BODY.y]
    mov     [rdi + MOBSAVE.y], eax
    mov     eax, [rsi + BODY.z]
    mov     [rdi + MOBSAVE.z], eax
    add     rdi, MOBSAVE_size
    inc     ecx
.next:
    add     rsi, MOB_size
    cmp     rsi, rdx
    jb      .loop
    mov     [r8 + WORLDHDR.mob_count], ecx
    ret

; IN_RANGE mem, bound: jump to .skip unless 0 <= float at mem < constant bound (NaN skips)
%macro IN_RANGE 2
    movss   xmm0, %1
    xorps   xmm3, xmm3
    ucomiss xmm0, xmm3
    jb      .skip
    ucomiss xmm0, [%2]
    jae     .skip
%endmacro

; mobs_load(rdi WORLDHDR*): clear, then respawn every saved record that describes a zombie or
; pig inside the world, with its health clamped to 1..max
mobs_load:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rdi
    call    mobs_clear
    mov     r12d, [rbx + WORLDHDR.mob_count]
    cmp     r12d, MAX_MOBS
    jbe     .count_ok
    mov     r12d, MAX_MOBS              ; garbage count: validate every record we can reach
.count_ok:
    lea     r13, [rbx + WORLDHDR.mobs]
.rec:
    test    r12d, r12d
    jz      .done
    dec     r12d
    mov     eax, [r13 + MOBSAVE.type]
    dec     eax
    cmp     eax, 1
    ja      .skip                       ; not a zombie or pig
    IN_RANGE [r13 + MOBSAVE.x], c_256
    IN_RANGE [r13 + MOBSAVE.y], c_64
    IN_RANGE [r13 + MOBSAVE.z], c_256
    mov     edi, [r13 + MOBSAVE.type]
    movss   xmm0, [r13 + MOBSAVE.x]
    movss   xmm1, [r13 + MOBSAVE.y]
    movss   xmm2, [r13 + MOBSAVE.z]
    call    mob_spawn
    test    eax, eax
    js      .done
    imul    eax, eax, MOB_size
    lea     rdx, [mobs]
    add     rdx, rax                    ; the new mob
    mov     ecx, [rdx + MOB.type]
    mov     esi, [t_health + rcx*4 - 4]
    mov     eax, [r13 + MOBSAVE.health]
    mov     ecx, 1
    cmp     eax, ecx
    cmovl   eax, ecx
    cmp     eax, esi
    cmovg   eax, esi
    mov     [rdx + MOB.health], eax
.skip:
    add     r13, MOBSAVE_size
    jmp     .rec
.done:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
