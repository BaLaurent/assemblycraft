; mobs.asm - zombies, pigs, creepers, skeletons, spiders and chickens: slot storage, AI,
; spawning, ray/block queries, damage, drops, save records.
; A MOB starts with its BODY (MOB.body = 0), so a mob pointer is also a body pointer.
%include "common.inc"
default rel

global mobs, mob_count_type, mob_count_kind, mobs_clear, mobs_step, mobs_populate
global mob_spawn, mobs_raycast, mob_hurt, mobs_intersect_block, ray_aabb
global mobs_save, mobs_load

extern body_init, body_step, body_intersects_block, player, player_eye
extern rng_next, sincos_deg, atan2_deg
extern world_top_y, world_get, raycast
extern sky_brightness, sky_is_night
extern survival_damage, surv, drops_spawn, audio_play_at
extern settings, game_mode, game_time
extern arrows_spawn, explode_at

%define HOSTILE_CAP   12                ; hostile mobs the spawner keeps alive
%define PIG_CAP       10                ; pigs the spawner keeps alive
%define CHICKEN_CAP   8                 ; chickens the spawner keeps alive
%define CHICKEN_START 6                 ; chickens a new world starts with
%define HURT_STEPS    10                ; mob_hurt invulnerability window
%define HIT_COOLDOWN  60                ; steps between zombie hits
%define PANIC_STEPS   180               ; a hurt pig or chicken runs this long
%define CREEPER_FUSE  90                ; steps from a lit fuse to the blast
; ground a mob may spawn on, one bit per block id
%define HOSTILE_GROUND ((1 << STONE) | (1 << GRASS) | (1 << DIRT) | (1 << COBBLE) | (1 << SAND) | (1 << GRAVEL))
%define PASSIVE_GROUND (1 << GRASS)

section .rodata
align 4
; per-type tables, index = type - 1 (zombie, pig, creeper, skeleton, spider, chicken)
t_half_w:   dd 0.3, 0.45, 0.3, 0.3, 0.7, 0.2
t_height:   dd 1.8, 0.9, 1.7, 1.8, 0.9, 0.7
t_speed:    dd 2.6, 1.6, 2.4, 2.5, 3.0, 1.4
t_run:      dd 0.0, 3.2, 0.0, 0.0, 0.0, 2.4     ; panic speed of the passive types
t_health:   dd 20, 10, 20, 20, 16, 4
t_dmg:      dd 0, 2, 3, 4               ; zombie and skeleton hit by difficulty
t_dmg_spider: dd 0, 2, 2, 3
t_spread:   dd 0.0, 1.5, 1.0, 0.5       ; skeleton aim error in blocks/s by difficulty
t_hostile:  db 1, 0, 1, 1, 1, 0
t_burns:    db 1, 0, 0, 1, 0, 0         ; sunlight hurts the undead
t_say:      db SND_ZOMBIE_SAY, SND_PIG_SAY, 0xFF, SND_SKELETON_SAY, SND_SPIDER_SAY, SND_CHICKEN_SAY
t_hurt:     db SND_ZOMBIE_HURT, SND_PIG_HURT, SND_CREEPER_HURT, SND_SKELETON_HURT
            db SND_SPIDER_HURT, SND_CHICKEN_HURT
; death drops, 8 bytes per type: two (item, base, range) entries, count = base + rng % range;
; item 0 = unused entry
t_drops:    db ROTTEN_FLESH, 0, 3, 0, 0, 0, 0, 0
            db PORKCHOP, 1, 3, 0, 0, 0, 0, 0
            db GUNPOWDER, 0, 3, 0, 0, 0, 0, 0
            db ARROW, 0, 3, 0, 0, 0, 0, 0
            db STRING, 0, 3, 0, 0, 0, 0, 0
            db FEATHER, 0, 3, RAW_CHICKEN, 1, 1, 0, 0
; what the night spawner picks from
night_kinds: db MOB_ZOMBIE, MOB_SKELETON, MOB_CREEPER, MOB_SPIDER
align 8
hunt_ai:    dq 0, 0, ai_creeper, ai_skeleton, ai_spider, 0   ; by type - 1; the zombie's AI is inline
align 4
c_360:      dd 360.0
c_180:      dd 180.0                    ; walk-cycle degrees per block walked
c_half:     dd 0.5
c_aggro2:   dd 576.0                    ; zombies notice the player within 24 blocks
c_hunt2:    dd 256.0                    ; creepers, skeletons and spiders within 16
c_reach2:   dd 2.89                     ; zombie hit range 1.7 blocks, squared
c_bite2:    dd 1.96                     ; spider bite range 1.4 blocks, squared
c_far2:     dd 9216.0                   ; hostile mobs further than 96 blocks vanish
c_kb:       dd 6.0                      ; knockback speed
c_kb_spider: dd 5.0                     ; knockback of a spider's bite and leap
c_drop_dy:  dd 0.4                      ; porkchops pop out at mid-body height
c_tiny:     dd 0.0001
c_day:      dd 0.8                      ; brightness at which zombies burn
c_vol_say:  dd 0.7
c_vol_hurt: dd 1.0
c_glide:    dd -3.0                     ; slowest a chicken falls, blocks/s
c_256:      dd 256.0
c_64:       dd 64.0
c_one:      dd 1.0
; creeper
c_ignite2:  dd 9.0                      ; the fuse lights within 3 blocks
c_stop2:    dd 4.0                      ; it stops walking within 2
c_calm2:    dd 49.0                     ; the fuse burns on while the player is within 7
c_chest:    dd 0.9                      ; player centre above his feet
c_mid:      dd 0.85                     ; creeper centre above its feet
c_blast:    dd 3.0
c_vol_fuse: dd 1.0
; skeleton
c_near2:    dd 25.0                     ; backs away within 5 blocks
c_far_in2:  dd 100.0                    ; closes in beyond 10
c_shoot2:   dd 225.0                    ; shoots within 15
c_eye:      dd 1.62                     ; eye height above the feet
c_muzzle:   dd 0.6                      ; arrow starts this far along the aim
c_arrow_v:  dd 24.0                     ; arrow speed, blocks/s
c_lift:     dd 10.0                     ; upward aim per second of flight against gravity
c_cent:     dd 0.01
c_vol_bow:  dd 0.8
; spider
c_reach_y2: dd 2.25                     ; bite height window 1.5, squared
c_leap_lo2: dd 4.0                      ; leaps from 2 to 4 blocks away
c_leap_hi2: dd 16.0
c_climb:    dd 3.0
c_leap_vy:  dd 5.5
c_lift_vy:  dd 5.0

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

; mob_count_kind(edi hostile 0/1) -> eax number of live mobs that are hostile (1) or passive (0)
mob_count_kind:
    xor     eax, eax
    lea     rcx, [mobs]
    lea     rdx, [mobs_end]
.loop:
    mov     esi, [rcx + MOB.type]
    test    esi, esi
    jz      .next
    movzx   esi, byte [t_hostile + rsi - 1]
    cmp     esi, edi
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
    cmp     eax, NUM_MOB_TYPES - 1
    ja      .none                       ; not a mob type
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

; mob_ai(rdi mob) -> eax 1 when the mob blew up and is gone, else 0.
; This step's input and heading. Zombies hunt a living player within 24 blocks (Survival,
; difficulty > 0) and hit when close; creepers, skeletons and spiders hunt within 16 blocks
; (ai_creeper, ai_skeleton, ai_spider); a panicking pig or chicken runs along its heading;
; everything else wanders in 1-4 s legs.
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
    mov     ecx, [rbx + MOB.type]
    cmp     byte [t_hostile + rcx - 1], 0
    je      .passive
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .idle
    cmp     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL
    je      .idle
    cmp     dword [surv + SURVIVAL.dead], 0
    jne     .idle
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
    movss   xmm1, [c_hunt2]
    cmp     ecx, MOB_ZOMBIE
    jne     .range
    movss   xmm1, [c_aggro2]
.range:
    comiss  xmm0, xmm1
    jae     .idle                       ; too far to notice
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    call    yaw_from
    movss   [rbx + BODY.yaw], xmm0
    mov     eax, [rbx + MOB.type]
    cmp     eax, MOB_ZOMBIE
    je      .zombie
    mov     rdi, rbx
    mov     rsi, rsp
    lea     rcx, [hunt_ai]
    call    [rcx + rax*8 - 8]
    test    eax, eax
    jnz     .ret                        ; it blew up
    jmp     .jump
.zombie:
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
.idle:                                  ; not hunting: a lit fuse dies down while it wanders
    cmp     dword [rbx + MOB.fuse], 0
    jle     .wander
    dec     dword [rbx + MOB.fuse]
    jmp     .wander
.passive:
    cmp     dword [rbx + MOB.panic], 0
    jle     .wander
    mov     eax, [rbx + MOB.type]
    mov     edx, [t_run + rax*4 - 4]    ; a hurt pig or chicken runs
    mov     [rbx + BODY.speed], edx
    mov     dword [rbx + MOB.input + INPUT.fwd], 1
    dec     dword [rbx + MOB.panic]
    jnz     .jump
    mov     edx, [t_speed + rax*4 - 4]  ; panic over: back to the stroll speed
    mov     [rbx + BODY.speed], edx
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
    xor     eax, eax
.ret:
    add     rsp, 24
    pop     rbx
    pop     rbp
    ret

; ai_creeper(rdi mob, rsi frame) -> eax 1 when it exploded (the mob is gone).
; frame = mob_ai's [dx, dz, horizontal distance^2]. A creeper walks up to the player; within 3
; blocks (between body centres) the fuse lights and keeps burning while the player stays
; within 7, else it dies down; once lit it stops walking within 2 blocks; at CREEPER_FUSE
; it blows up with radius 3 where it stands.
ai_creeper:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdi
    movss   xmm0, [player + BODY.y]
    addss   xmm0, [c_chest]
    movss   xmm1, [rbx + BODY.y]
    addss   xmm1, [c_mid]
    subss   xmm0, xmm1                  ; dy between the centres
    mulss   xmm0, xmm0
    addss   xmm0, [rsi + 8]             ; + horizontal distance^2
    cmp     dword [rbx + MOB.fuse], 0
    jne     .lit
    mov     dword [rbx + MOB.input + INPUT.fwd], 1
    comiss  xmm0, [c_ignite2]
    jae     .check
    mov     dword [rbx + MOB.fuse], 1   ; close enough: light the fuse
    mov     edi, SND_FUSE
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [c_vol_fuse]
    call    audio_play_at
    jmp     .check
.lit:
    xor     eax, eax
    comiss  xmm0, [c_stop2]
    seta    al
    mov     [rbx + MOB.input + INPUT.fwd], eax  ; walks on only while farther than 2 blocks
    comiss  xmm0, [c_calm2]
    jae     .dying
    inc     dword [rbx + MOB.fuse]
    jmp     .check
.dying:
    dec     dword [rbx + MOB.fuse]
.check:
    xor     eax, eax
    cmp     dword [rbx + MOB.fuse], CREEPER_FUSE
    jl      .ret
    mov     dword [rbx + MOB.type], MOB_NONE    ; gone before the blast looks for mobs to hurt
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    addss   xmm1, [c_mid]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [c_blast]
    call    explode_at
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ai_skeleton(rdi mob, rsi frame) -> eax 0.
; Keeps 5..10 blocks from the player (closes in beyond 10, backs off inside 5) and, every
; 40..69 steps, shoots an arrow when within 15 blocks with a clear line to the player's eye.
; The arrow leaves 0.6 blocks along the aim at 24 blocks/s, lifted against gravity and
; scattered by the difficulty.
; Frame: own eye o[3] @0, unit aim dir[3] @12, player eye[3] @24, distance @36,
; sx @44, sz @48, RAYHIT scratch @52 (24 bytes), clamped difficulty @76.
ai_skeleton:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 80
    mov     rbx, rdi
    mov     r12, rsi
    xor     eax, eax
    movss   xmm0, [r12 + 8]             ; horizontal distance^2
    comiss  xmm0, [c_far_in2]
    jbe     .not_far
    mov     eax, 1                      ; too far to shoot well: close in
    jmp     .set_fwd
.not_far:
    comiss  xmm0, [c_near2]
    jae     .set_fwd                    ; 5..10 blocks: stand and shoot
    mov     eax, -1                     ; too close: back away, still facing the player
.set_fwd:
    mov     [rbx + MOB.input + INPUT.fwd], eax
    cmp     dword [rbx + MOB.cooldown], 0
    jne     .done
    comiss  xmm0, [c_shoot2]
    jae     .done
    movss   xmm0, [rbx + BODY.x]        ; own eye
    movss   [rsp], xmm0
    movss   xmm0, [rbx + BODY.y]
    addss   xmm0, [c_eye]
    movss   [rsp + 4], xmm0
    movss   xmm0, [rbx + BODY.z]
    movss   [rsp + 8], xmm0
    lea     rdi, [rsp + 24]
    call    player_eye
    xor     ecx, ecx
.aim:                                   ; dir = player eye - own eye
    movss   xmm0, [rsp + 24 + rcx*4]
    subss   xmm0, [rsp + rcx*4]
    movss   [rsp + 12 + rcx*4], xmm0
    inc     ecx
    cmp     ecx, 3
    jb      .aim
    movss   xmm0, [rsp + 12]
    mulss   xmm0, xmm0
    movss   xmm1, [rsp + 16]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    movss   xmm1, [rsp + 20]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    sqrtss  xmm0, xmm0                  ; distance
    comiss  xmm0, [c_tiny]
    jb      .done                       ; eye to eye: no direction to aim along
    movss   [rsp + 36], xmm0
    xor     ecx, ecx
.unit:
    movss   xmm1, [rsp + 12 + rcx*4]
    divss   xmm1, xmm0
    movss   [rsp + 12 + rcx*4], xmm1
    inc     ecx
    cmp     ecx, 3
    jb      .unit
    lea     rdi, [rsp]                  ; line of sight: no block between the two eyes
    lea     rsi, [rsp + 12]
    lea     rdx, [rsp + 52]
    movss   xmm0, [rsp + 36]
    call    raycast
    test    eax, eax
    jnz     .done
    mov     eax, [settings + SETTINGS.difficulty]
    mov     ecx, DIFF_HARD
    cmp     eax, ecx
    cmova   eax, ecx
    mov     [rsp + 76], eax
    call    rng_next                    ; aim error: (rng % 201 - 100) / 100 * spread, per axis
    xor     edx, edx
    mov     ecx, 201
    div     ecx
    sub     edx, 100
    cvtsi2ss xmm0, edx
    mulss   xmm0, [c_cent]
    mov     eax, [rsp + 76]
    mulss   xmm0, [t_spread + rax*4]
    movss   [rsp + 44], xmm0
    call    rng_next
    xor     edx, edx
    mov     ecx, 201
    div     ecx
    sub     edx, 100
    cvtsi2ss xmm0, edx
    mulss   xmm0, [c_cent]
    mov     eax, [rsp + 76]
    mulss   xmm0, [t_spread + rax*4]
    movss   [rsp + 48], xmm0
    movss   xmm6, [rsp + 36]            ; flight time dist / 24: lift 10 t against gravity
    divss   xmm6, [c_arrow_v]
    mulss   xmm6, [c_lift]
    movss   xmm3, [rsp + 12]
    mulss   xmm3, [c_arrow_v]
    addss   xmm3, [rsp + 44]            ; vx
    movss   xmm4, [rsp + 16]
    mulss   xmm4, [c_arrow_v]
    addss   xmm4, xmm6                  ; vy
    movss   xmm5, [rsp + 20]
    mulss   xmm5, [c_arrow_v]
    addss   xmm5, [rsp + 48]            ; vz
    movss   xmm0, [rsp + 12]            ; starts 0.6 blocks along the aim
    mulss   xmm0, [c_muzzle]
    addss   xmm0, [rsp]
    movss   xmm1, [rsp + 16]
    mulss   xmm1, [c_muzzle]
    addss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 20]
    mulss   xmm2, [c_muzzle]
    addss   xmm2, [rsp + 8]
    mov     edi, 1                      ; fired by a mob
    mov     eax, [rsp + 76]
    mov     esi, [t_dmg + rax*4]
    xor     edx, edx                    ; cannot be picked up
    call    arrows_spawn
    mov     edi, SND_BOW
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [c_vol_bow]
    call    audio_play_at
    call    rng_next                    ; reload: 40..69 steps
    xor     edx, edx
    mov     ecx, 30
    div     ecx
    add     edx, 40
    mov     [rbx + MOB.cooldown], edx
.done:
    xor     eax, eax
    add     rsp, 80
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ai_spider(rdi mob, rsi frame) -> eax 0.
; Always runs at the player and climbs what blocks it. Within 1.4 blocks it bites (every 20
; steps); from 2..4 blocks away it leaps at him (every 30 steps, from the ground).
ai_spider:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    mov     rbx, rdi
    mov     r12, rsi
    mov     dword [rbx + MOB.input + INPUT.fwd], 1
    cmp     dword [rbx + BODY.blocked], 0
    je      .free
    mov     eax, [c_climb]              ; against a wall: climb it
    mov     [rbx + BODY.vy], eax
.free:
    cmp     dword [rbx + MOB.cooldown], 0
    jne     .done
    movss   xmm0, [r12 + 8]             ; horizontal distance^2
    comiss  xmm0, [c_bite2]
    jae     .leap
    movss   xmm1, [player + BODY.y]
    subss   xmm1, [rbx + BODY.y]
    mulss   xmm1, xmm1
    comiss  xmm1, [c_reach_y2]
    jae     .done                       ; above or below its reach
    mov     eax, [settings + SETTINGS.difficulty]
    mov     ecx, DIFF_HARD
    cmp     eax, ecx
    cmova   eax, ecx
    mov     edi, [t_dmg_spider + rax*4]
    mov     esi, CAUSE_SPIDER
    call    survival_damage
    test    eax, eax
    jz      .done                       ; not applied (invulnerable): bite again next step
    movss   xmm2, [r12 + 8]
    sqrtss  xmm2, xmm2                  ; knock the player back along spider -> player
    comiss  xmm2, [c_tiny]
    jb      .lift
    movss   xmm3, [c_kb_spider]
    divss   xmm3, xmm2
    movss   xmm0, [r12]
    mulss   xmm0, xmm3
    movss   [player + BODY.kbx], xmm0
    movss   xmm1, [r12 + 4]
    mulss   xmm1, xmm3
    movss   [player + BODY.kbz], xmm1
.lift:
    cmp     dword [player + BODY.on_ground], 0
    je      .bitten
    mov     eax, [c_lift_vy]
    mov     [player + BODY.vy], eax
.bitten:
    mov     dword [rbx + MOB.cooldown], 20
    jmp     .done
.leap:
    cmp     dword [rbx + BODY.on_ground], 0
    je      .done
    comiss  xmm0, [c_leap_lo2]
    jb      .done
    comiss  xmm0, [c_leap_hi2]
    ja      .done
    sqrtss  xmm2, xmm0
    movss   xmm3, [c_kb_spider]
    divss   xmm3, xmm2
    movss   xmm0, [r12]
    mulss   xmm0, xmm3
    movss   [rbx + BODY.kbx], xmm0      ; hurl itself at the player
    movss   xmm1, [r12 + 4]
    mulss   xmm1, xmm3
    movss   [rbx + BODY.kbz], xmm1
    mov     eax, [c_leap_vy]
    mov     [rbx + BODY.vy], eax
    mov     dword [rbx + MOB.cooldown], 30
.done:
    xor     eax, eax
    add     rsp, 16
    pop     r12
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
    test    eax, eax
    jnz     .done                       ; blew up: nothing left to move
    movss   xmm0, [rbx + BODY.x]
    movss   [rsp], xmm0
    movss   xmm0, [rbx + BODY.z]
    movss   [rsp + 4], xmm0
    mov     rdi, rbx
    lea     rsi, [rbx + MOB.input]
    call    body_step
    cmp     dword [rbx + MOB.type], MOB_CHICKEN
    jne     .no_glide
    movss   xmm0, [rbx + BODY.vy]       ; chickens flutter down: they never fall faster than 3 blocks/s
    maxss   xmm0, [c_glide]
    movss   [rbx + BODY.vy], xmm0
.no_glide:
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
    cmp     edi, 0xFF
    je      .quiet                      ; creepers make no ambient sound
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [c_vol_say]
    call    audio_play_at
.quiet:
    mov     eax, [rbx + MOB.type]
    cmp     byte [t_hostile + rax - 1], 0
    je      .done                       ; passive mobs neither burn nor despawn
    cmp     byte [t_burns + rax - 1], 0
    je      .despawn                    ; hostile but sun-proof
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
; Needs 1 <= x, z <= 254, a surface at y + 1 <= 62 and a top block whose bit is set in the mask;
; a spider (1.4 blocks wide) also needs the 3 x 3 cells above that block free.
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
    cmp     ebx, MOB_SPIDER
    jne     .place
    mov     edi, r12d
    lea     esi, [r15 + 1]
    mov     edx, r13d
    call    area_clear
    test    eax, eax
    jz      .fail
.place:
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

; area_clear(edi x, esi y, edx z) -> eax 1 when the 3 x 3 cells centred on (x, y, z) are all air
area_clear:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edx
    mov     ebx, 9                      ; cell index 8..0: column = i % 3, row = i / 3
.cell:
    dec     ebx
    js      .clear
    mov     eax, ebx
    xor     edx, edx
    mov     ecx, 3
    div     ecx
    lea     edi, [r12 + rdx - 1]
    lea     edx, [r14 + rax - 1]
    mov     esi, r13d
    call    world_get
    test    eax, eax
    jz      .cell
    xor     eax, eax
    jmp     .ret
.clear:
    mov     eax, 1
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; spawn_passive(edi type, esi cap): one more of that type around the player (24..48 blocks
; away, on grass) unless `cap` already live
spawn_passive:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12d, esi
    call    mob_count_type
    cmp     eax, r12d
    jae     .done
    mov     edi, ebx
    mov     esi, 24
    mov     edx, 25
    mov     ecx, PASSIVE_GROUND
    call    spawn_near_player
.done:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mobs_spawn_tick(): the ambient spawner, once per fixed step.
; Every 60 steps at night in Survival (difficulty > 0): a zombie, skeleton, creeper or spider
; while fewer than 12 hostile mobs live. Every 1800 steps by day: a pig (at most 10) and a
; chicken (at most 8).
mobs_spawn_tick:
    push    rbp
    mov     rbp, rsp
    mov     eax, [game_time]
    xor     edx, edx
    mov     ecx, 60
    div     ecx
    test    edx, edx
    jnz     .passive
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .passive
    cmp     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL
    je      .passive
    mov     edi, [game_time]
    call    sky_is_night
    test    eax, eax
    jz      .passive
    mov     edi, 1
    call    mob_count_kind
    cmp     eax, HOSTILE_CAP
    jae     .passive
    call    rng_next                    ; which kind: night_kinds[rng % 4]
    and     eax, 3
    movzx   edi, byte [night_kinds + rax]
    mov     esi, 24
    mov     edx, 17
    mov     ecx, HOSTILE_GROUND
    call    spawn_near_player
.passive:
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
    mov     esi, PIG_CAP
    call    spawn_passive
    mov     edi, MOB_CHICKEN
    mov     esi, CHICKEN_CAP
    call    spawn_passive
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

; mobs_populate(): scatter pigs, then chickens, around the world centre (up to 200 tries
; each, until 10 pigs / 6 chickens live)
mobs_populate:
    push    rbp
    mov     rbp, rsp
    mov     edi, MOB_PIG
    mov     esi, PIG_CAP
    call    populate
    mov     edi, MOB_CHICKEN
    mov     esi, CHICKEN_START
    call    populate
    pop     rbp
    ret

; populate(edi type, esi count): up to 200 tries at spawning that type on grass in the 97 x 97
; square around the world centre, until `count` of them live
populate:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r13d, edi
    mov     r14d, esi
    mov     ebx, 200
.try:
    mov     edi, r13d
    call    mob_count_type
    cmp     eax, r14d
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
    mov     edi, r13d
    mov     esi, r12d
    mov     ecx, PASSIVE_GROUND
    call    spawn_at_ground
    dec     ebx
    jnz     .try
.done:
    pop     r14
    pop     r13
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

; mob_drops(rdi mob): the loot of a dead mob, popped out at mid-body height (a pig's a little
; lower). Each of the type's two table entries (item, base, range) drops base + rng % range.
mob_drops:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rdi
    mov     eax, [rbx + MOB.type]
    lea     r12, [t_drops + rax*8 - 8]
    mov     r13d, 2
.entry:
    cmp     byte [r12], 0
    je      .next
    call    rng_next
    movzx   ecx, byte [r12 + 2]
    xor     edx, edx
    div     ecx
    movzx   esi, byte [r12 + 1]
    add     esi, edx                    ; count
    jz      .next                       ; nothing this time
    movzx   edi, byte [r12]
    xor     edx, edx
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.height]
    mulss   xmm1, [c_half]
    cmp     dword [rbx + MOB.type], MOB_PIG
    jne     .height
    movss   xmm1, [c_drop_dy]
.height:
    addss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    call    drops_spawn
.next:
    add     r12, 3
    dec     r13d
    jnz     .entry
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mob_hurt(edi idx, esi dmg, xmm0 dirx, xmm1 dirz) -> eax 1 applied / 0 (no such mob, or still in its
; hurt window). Knocks the mob along (dirx, dirz); a passive mob panics and flees that way, a dead
; mob drops its loot (mob_drops).
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
    mov     eax, [rbx + MOB.type]
    cmp     byte [t_hostile + rax - 1], 0
    jne     .check_dead                 ; hostile mobs stand and fight
    mov     dword [rbx + MOB.panic], PANIC_STEPS
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    call    yaw_from                    ; passive mobs run away from the attacker
    movss   [rbx + BODY.yaw], xmm0
.check_dead:
    cmp     dword [rbx + MOB.health], 0
    jg      .yes
    mov     rdi, rbx
    call    mob_drops
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

; mobs_load(rdi WORLDHDR*): clear, then respawn every saved record that describes a known mob
; type inside the world, with its health clamped to 1..max
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
    cmp     eax, NUM_MOB_TYPES - 1
    ja      .skip                       ; not a mob type
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
