; mobs.asm - zombies, pigs, creepers, skeletons, spiders and chickens, the RPG's villagers
; (merchant, elder) and the Fallen King boss: slot storage, AI, spawning, ray/block queries,
; damage, drops, save records.
; A MOB starts with its BODY (MOB.body = 0), so a mob pointer is also a body pointer.
%include "common.inc"
default rel

global mobs, mob_count_type, mob_count_kind, mobs_clear, mobs_step, mobs_populate
global mob_spawn, mob_spawn_elite, mob_spawn_npc, mob_is_hostile, mobs_raycast
global mob_hurt, mob_strike, mobs_intersect_block, ray_aabb
global mobs_save, mobs_load, yaw_from

extern body_init, body_step, body_intersects_block, player, player_eye
extern rng_next, sincos_deg, atan2_deg
extern world_top_y, world_get, raycast, light_get
extern sky_brightness, sky_is_night
extern surv, drops_spawn, audio_play_at
extern settings, game_mode, game_time
extern arrows_spawn, explode_at, fx_explosion
extern player_take_hit, combat_hit_flags, combat_stealth_t
extern dmgnum_spawn, dmgnum_text, hud_banner
extern rpg_state, rpg_on_mob_killed, rpg_add_xp, quests_on_boss_killed, structures_on_mob_killed

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
%define ZOMBIE_WINDUP 20                ; steps a zombie's arm is up before the blow
%define ZOMBIE_WINDUP_ELITE 16
%define SPIDER_WINDUP 12                ; steps a spider rears up before the bite
%define SPIDER_WINDUP_ELITE 10
%define STUN_PARRIED  50                ; a parried zombie or spider is dazed this long
%define BAR_STEPS     180               ; a hit mob's health bar stays up this long
%define TAG_STEPS     200               ; a player hit counts for XP this long
%define BOSS_WINDUP   36                ; the Fallen King's slam wind-up (phase 3: 24)
%define BOSS_WINDUP_RAGE 24
%define BOSS_STUN     30                ; a parried slam stuns him this long
%define BOSS_COOLDOWN 70                ; steps between slams (phase 3: 45)
%define BOSS_COOLDOWN_RAGE 45
%define BOSS_SUMMON_STEPS 600           ; skeletons rise this often
%define BOSS_VOLLEY_STEPS 240           ; arrow volleys (phases 2 and 3) this often
%define BOSS_MAX_MINIONS 4              ; no summons while this many skeletons live

; ELITE_DAMAGE reg32: damage x 1.5, rounded, when the mob at rbx is an elite (clobbers xmm7)
%macro ELITE_DAMAGE 1
    cmp     dword [rbx + MOB.elite], 0
    je      %%plain
    cvtsi2ss xmm7, %1
    mulss   xmm7, [c_1_5]
    cvtss2si %1, xmm7
%%plain:
%endmacro

; DEC_TIMER field: the step counter MOB.field of the mob at rbx counts down to 0 and stays there
%macro DEC_TIMER 1
    cmp     dword [rbx + %1], 0
    jle     %%zero
    dec     dword [rbx + %1]
%%zero:
%endmacro

section .rodata
align 4
; per-type tables, index = type - 1 (zombie, pig, creeper, skeleton, spider, chicken, merchant,
; elder, boss)
t_half_w:   dd 0.3, 0.45, 0.3, 0.3, 0.7, 0.2, 0.3, 0.3, 0.6
t_height:   dd 1.8, 0.9, 1.7, 1.8, 0.9, 0.7, 1.95, 1.95, 3.3
t_speed:    dd 2.6, 1.6, 2.4, 2.5, 3.0, 1.4, 1.0, 1.0, 2.4
t_run:      dd 0.0, 3.2, 0.0, 0.0, 0.0, 2.4, 0.0, 0.0, 0.0     ; panic speed of the passive types
t_health:   dd 20, 10, 20, 20, 16, 4, 20, 20, 300              ; (the boss's depends on the difficulty)
t_dmg:      dd 0, 2, 3, 4               ; zombie and skeleton hit by difficulty
t_dmg_spider: dd 0, 2, 2, 3
t_dmg_slam: dd 0, 6, 8, 12              ; the Fallen King's slam by difficulty
t_dmg_volley: dd 0, 3, 4, 5             ; ...and each arrow of his volley
t_boss_health: dd 200, 200, 300, 450
t_spread:   dd 0.0, 1.5, 1.0, 0.5       ; skeleton aim error in blocks/s by difficulty
t_hostile:  db 1, 0, 1, 1, 1, 0, 0, 0, 1
t_burns:    db 1, 0, 0, 1, 0, 0, 0, 0, 0   ; sunlight hurts the undead
t_say:      db SND_ZOMBIE_SAY, SND_PIG_SAY, 0xFF, SND_SKELETON_SAY, SND_SPIDER_SAY, SND_CHICKEN_SAY
            db SND_VILLAGER, SND_VILLAGER, SND_BOSS_ROAR
t_hurt:     db SND_ZOMBIE_HURT, SND_PIG_HURT, SND_CREEPER_HURT, SND_SKELETON_HURT
            db SND_SPIDER_HURT, SND_CHICKEN_HURT, SND_VILLAGER, SND_VILLAGER, SND_SKELETON_HURT
; death drops, 8 bytes per type: two (item, base, range) entries, count = base + rng % range;
; item 0 = unused entry. Villagers and the boss have none here: mob_drops special-cases the boss.
t_drops:    db ROTTEN_FLESH, 0, 3, 0, 0, 0, 0, 0
            db PORKCHOP, 1, 3, 0, 0, 0, 0, 0
            db GUNPOWDER, 0, 3, 0, 0, 0, 0, 0
            db ARROW, 0, 3, 0, 0, 0, 0, 0
            db STRING, 0, 3, 0, 0, 0, 0, 0
            db FEATHER, 0, 3, RAW_CHICKEN, 1, 1, 0, 0
            db 0, 0, 0, 0, 0, 0, 0, 0
            db 0, 0, 0, 0, 0, 0, 0, 0
            db 0, 0, 0, 0, 0, 0, 0, 0
; the Fallen King's legendary drop by class (none, warrior, mage, archer, rogue)
t_legendary: db KINGS_BLADE, KINGS_BLADE, ARCHMAGE_STAFF, CELESTIAL_BOW, SHADOW_FANG
; what the night spawner picks from
night_kinds: db MOB_ZOMBIE, MOB_SKELETON, MOB_CREEPER, MOB_SPIDER
align 8
hunt_ai:    dq 0, 0, ai_creeper, ai_skeleton, ai_spider, 0, 0, 0, ai_boss   ; by type - 1; the zombie's AI is inline
align 4
c_360:      dd 360.0
c_180:      dd 180.0                    ; walk-cycle degrees per block walked
c_half:     dd 0.5
c_aggro2:   dd 576.0                    ; zombies notice the player within 24 blocks
c_hunt2:    dd 256.0                    ; creepers, skeletons and spiders within 16
c_reach2:   dd 2.89                     ; zombie hit range 1.7 blocks, squared
c_close2:   dd 1.21                     ; a zombie stops walking 1.1 blocks from the player, squared
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
; elites and telegraphed attacks
c_1_5:      dd 1.5                      ; elite damage
c_1_15:     dd 1.15                     ; elite speed
c_2_5:      dd 2.5                      ; elite health
c_strike2:  dd 3.6                      ; a raised arm still connects within 1.9 blocks, squared
c_bite_end2: dd 2.45                    ; a rearing spider still bites within 1.56 blocks, squared
c_over_head: dd 0.2                     ; floating numbers start this far above the head
; villagers
c_home2:    dd 36.0                     ; they walk home from beyond 6 blocks
c_talk2:    dd 16.0                     ; they turn to a player within 4
; the Fallen King
c_boss_aggro2: dd 2304.0                ; he hunts within 48 blocks
c_boss_stop2: dd 4.84                   ; he stops 2.2 blocks from the player (his fists reach 3.5)
c_boss_speed: dd 2.4
c_boss_rage: dd 1.4                     ; phase 3 speed factor
c_slam_start2: dd 9.0                   ; the fists go up within 3 blocks
c_slam2:    dd 12.25                    ; the slam reaches 3.5 blocks (phase 3: 5), squared
c_slam2_rage: dd 25.0
c_slam_dy2: dd 6.25                     ; ...and 2.5 blocks up or down, squared
c_slam_kb:  dd 10.0                     ; speed of the shove
c_slam_lift: dd 0.2                     ; the blast sits just above the floor
c_slam_fx:  dd 1.5
c_boss_kb:  dd 0.2                      ; he barely budges when hit
c_boss_eye: dd 2.6                      ; his arrows leave from his head
c_volley_v: dd 30.0
c_volley_muzzle: dd 0.8
c_fan_step: dd 10.0                     ; degrees between the 5 arrows of a volley
c_boss_death_r: dd 3.0
c_two:      dd 2.0
s_furious:  db "The Fallen King grows furious!", 0
s_victory:  db "Victory! The Fallen King is no more.", 0

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

; mob_spawn(edi type, xmm0 x, xmm1 y, xmm2 z) -> eax slot index, or -1 (bad type / no free slot).
; Every mob remembers its spawn point as its home (villagers stroll around it); max_health is the
; spawn health. The Fallen King's health depends on the difficulty and his two timers start.
; mob_spawn_npc(...) is the same call: structures spawn the merchant and elder through it.
mob_spawn_npc:
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
    cmp     ebx, MOB_BOSS
    jne     .health
    mov     eax, [settings + SETTINGS.difficulty]   ; the Fallen King: 200 / 200 / 300 / 450 by difficulty
    mov     ecx, DIFF_HARD
    cmp     eax, ecx
    cmova   eax, ecx
    mov     eax, [t_boss_health + rax*4]
    mov     dword [r12 + MOB.timer_a], BOSS_SUMMON_STEPS
    mov     dword [r12 + MOB.timer_b], BOSS_VOLLEY_STEPS
.health:
    mov     [r12 + MOB.health], eax
    mov     [r12 + MOB.max_health], eax
    mov     eax, [rsp]
    mov     [r12 + BODY.x], eax
    mov     [r12 + MOB.home_x], eax
    mov     eax, [rsp + 4]
    mov     [r12 + BODY.y], eax
    mov     eax, [rsp + 8]
    mov     [r12 + BODY.z], eax
    mov     [r12 + MOB.home_z], eax
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

; mob_spawn_elite(edi type, xmm0 x, xmm1 y, xmm2 z) -> eax slot index, or -1: mob_spawn, then the
; elite upgrade (make_elite)
mob_spawn_elite:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    mob_spawn
    test    eax, eax
    js      .ret
    mov     ebx, eax
    imul    edx, eax, MOB_size
    lea     rcx, [mobs]
    add     rdx, rcx
    call    make_elite
    mov     eax, ebx
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; make_elite(rdx mob): an elite has 2.5 x the health (rounded), moves 1.15 x as fast, and the AI
; hits it 1.5 x harder (ELITE_DAMAGE); it is drawn gold and 1.2 x larger. Clobbers eax, xmm0.
make_elite:
    mov     dword [rdx + MOB.elite], 1
    cvtsi2ss xmm0, dword [rdx + MOB.health]
    mulss   xmm0, [c_2_5]
    cvtss2si eax, xmm0
    mov     [rdx + MOB.health], eax
    mov     [rdx + MOB.max_health], eax
    movss   xmm0, [rdx + BODY.speed]
    mulss   xmm0, [c_1_15]
    movss   [rdx + BODY.speed], xmm0
    ret

; mob_is_hostile(edi idx) -> eax 1 when slot idx holds a live hostile mob (zombie, creeper, skeleton,
; spider, the boss), else 0 (empty slot, bad index, passive animal, villager)
mob_is_hostile:
    xor     eax, eax
    cmp     edi, MAX_MOBS
    jae     .ret
    imul    edi, edi, MOB_size
    lea     rcx, [mobs]
    mov     edx, [rcx + rdi + MOB.type]
    test    edx, edx
    jz      .ret
    movzx   eax, byte [t_hostile + rdx - 1]
.ret:
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
; This step's input and heading. A stunned mob stands still and attacks nothing. Zombies hunt a
; living player within 24 blocks (Survival, difficulty > 0, not hidden in smoke) and, after raising
; an arm for 20 steps, hit through player_take_hit when he is still close; creepers, skeletons and
; spiders hunt within 16 blocks (ai_creeper, ai_skeleton, ai_spider); the Fallen King hunts within
; 48 blocks and sees through smoke (ai_boss); villagers stay within 6 blocks of home and turn to a
; player within 4; a panicking pig or chicken runs along its heading; everything else wanders in
; 1-4 s legs.
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
    cmp     dword [rbx + MOB.stun], 0
    jg      .stunned
    mov     ecx, [rbx + MOB.type]
    cmp     byte [t_hostile + rcx - 1], 0
    je      .passive
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .idle
    cmp     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL
    je      .idle
    cmp     dword [surv + SURVIVAL.dead], 0
    jne     .idle
    cmp     ecx, MOB_BOSS
    je      .seen                       ; the Fallen King sees through smoke
    cmp     dword [combat_stealth_t], 0
    jg      .idle                       ; hidden in smoke: nothing hunts him
.seen:
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
    jne     .not_zombie
    movss   xmm1, [c_aggro2]
.not_zombie:
    cmp     ecx, MOB_BOSS
    jne     .range
    movss   xmm1, [c_boss_aggro2]
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
    cmp     dword [rbx + MOB.windup], 0
    jg      .winding
    mov     dword [rbx + MOB.input + INPUT.fwd], 1
    movss   xmm0, [rsp + 8]
    comiss  xmm0, [c_close2]
    jae     .closing
    mov     dword [rbx + MOB.input + INPUT.fwd], 0 ; at arm's length: it stops rather than walk into him
.closing:
    cmp     dword [rbx + MOB.cooldown], 0
    jne     .jump
    movss   xmm0, [player + BODY.y]     ; body centres are both feet + 0.9, so only the feet differ
    subss   xmm0, [rbx + BODY.y]
    mulss   xmm0, xmm0
    addss   xmm0, [rsp + 8]
    comiss  xmm0, [c_reach2]
    jae     .jump                       ; out of reach
    mov     eax, ZOMBIE_WINDUP          ; in reach: the arm goes up, and the zombie stands to swing
    mov     ecx, ZOMBIE_WINDUP_ELITE
    cmp     dword [rbx + MOB.elite], 0
    cmovne  eax, ecx
    mov     [rbx + MOB.windup], eax
    mov     dword [rbx + MOB.input + INPUT.fwd], 0
    jmp     .jump
.winding:
    mov     dword [rbx + MOB.input + INPUT.fwd], 0
    dec     dword [rbx + MOB.windup]
    jnz     .jump                       ; the arm is still up
    movss   xmm0, [player + BODY.y]     ; the blow lands only on a player still within reach
    subss   xmm0, [rbx + BODY.y]
    mulss   xmm0, xmm0                  ; dy^2
    comiss  xmm0, [c_reach_y2]          ; |dy| < 1.5
    jae     .whiff
    addss   xmm0, [rsp + 8]             ; distance^2 including the height difference, as at the start
    comiss  xmm0, [c_strike2]
    ja      .whiff                      ; more than 1.9 blocks away
    mov     eax, [settings + SETTINGS.difficulty]
    mov     ecx, DIFF_HARD
    cmp     eax, ecx
    cmova   eax, ecx
    mov     edi, [t_dmg + rax*4]
    ELITE_DAMAGE edi
    mov     esi, CAUSE_ZOMBIE
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.z]
    call    player_take_hit
    cmp     eax, HIT_PARRIED
    je      .parried
    cmp     eax, HIT_TAKEN
    jne     .hit_done                   ; blocked or dodged: no knockback
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
.parried:                               ; the riposte stuns it: it reels back and stands dazed
    mov     dword [rbx + MOB.stun], STUN_PARRIED
    mov     rdi, rbx
    mov     rsi, rsp
    call    mob_reel
    mov     rdi, rbx
    call    mob_stunned_text
    jmp     .hit_done
.whiff:                                 ; the player got away: it recovers sooner
    mov     dword [rbx + MOB.cooldown], 20
    jmp     .jump
.stunned:                               ; a stunned mob stands still; its telegraph is broken
    mov     dword [rbx + MOB.input + INPUT.fwd], 0
    mov     dword [rbx + MOB.windup], 0
    jmp     .jump
.idle:                                  ; not hunting: a lit fuse dies down while it wanders
    mov     dword [rbx + MOB.windup], 0 ; a lost target breaks the telegraph
    cmp     dword [rbx + MOB.type], MOB_BOSS
    je      .stand                      ; the Fallen King guards his crypt, he never strolls off
    cmp     dword [rbx + MOB.fuse], 0
    jle     .wander
    dec     dword [rbx + MOB.fuse]
    jmp     .wander
.passive:
    mov     eax, [rbx + MOB.type]
    cmp     eax, MOB_MERCHANT
    je      .npc
    cmp     eax, MOB_ELDER
    je      .npc
    cmp     dword [rbx + MOB.panic], 0
    jle     .wander
    mov     edx, [t_run + rax*4 - 4]    ; a hurt pig or chicken runs
    mov     [rbx + BODY.speed], edx
    mov     dword [rbx + MOB.input + INPUT.fwd], 1
    dec     dword [rbx + MOB.panic]
    jnz     .jump
    mov     edx, [t_speed + rax*4 - 4]  ; panic over: back to the stroll speed
    mov     [rbx + BODY.speed], edx
    jmp     .jump
.npc:                                   ; a villager: walks home from beyond 6 blocks, faces a player within 4
    movss   xmm0, [rbx + MOB.home_x]
    subss   xmm0, [rbx + BODY.x]
    movss   [rsp], xmm0
    movss   xmm1, [rbx + MOB.home_z]
    subss   xmm1, [rbx + BODY.z]
    movss   [rsp + 4], xmm1
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [c_home2]
    jbe     .at_home
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    call    yaw_from
    movss   [rbx + BODY.yaw], xmm0
    mov     dword [rbx + MOB.input + INPUT.fwd], 1
    jmp     .jump
.at_home:
    movss   xmm0, [player + BODY.x]
    subss   xmm0, [rbx + BODY.x]
    movss   [rsp], xmm0
    movss   xmm1, [player + BODY.z]
    subss   xmm1, [rbx + BODY.z]
    movss   [rsp + 4], xmm1
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [c_talk2]
    jae     .wander                     ; nobody close: the usual stroll
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    call    yaw_from
    movss   [rbx + BODY.yaw], xmm0
    mov     dword [rbx + MOB.input + INPUT.fwd], 0
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

; mob_reel(rdi mob, rsi frame): knocks the mob away from the player at 6 blocks/s.
; frame = mob_ai's [dx, dz, horizontal distance^2], dx and dz running mob -> player.
mob_reel:
    movss   xmm2, [rsi + 8]
    sqrtss  xmm2, xmm2
    comiss  xmm2, [c_tiny]
    jb      .done                       ; standing on the player: no direction
    movss   xmm3, [c_kb]
    divss   xmm3, xmm2
    xorps   xmm4, xmm4
    movss   xmm0, [rsi]
    mulss   xmm0, xmm3
    subss   xmm4, xmm0
    movss   [rdi + BODY.kbx], xmm4
    xorps   xmm4, xmm4
    movss   xmm1, [rsi + 4]
    mulss   xmm1, xmm3
    subss   xmm4, xmm1
    movss   [rdi + BODY.kbz], xmm4
.done:
    ret

; mob_stunned_text(rdi mob): "STUNNED" floats up over the mob's head
mob_stunned_text:
    sub     rsp, 8
    movss   xmm0, [rdi + BODY.x]
    movss   xmm1, [rdi + BODY.y]
    addss   xmm1, [rdi + BODY.height]
    addss   xmm1, [c_over_head]
    movss   xmm2, [rdi + BODY.z]
    mov     edi, TXT_STUNNED
    call    dmgnum_text
    add     rsp, 8
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
    ELITE_DAMAGE esi
    xor     edx, edx                    ; cannot be picked up
    mov     ecx, PROJ_ARROW
    xor     r8d, r8d
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
; Always runs at the player and climbs what blocks it. Within 1.4 blocks it rears up (12 steps,
; elite 10) standing still, then bites through player_take_hit (every 20 steps) if the player is
; still in reach; from 2..4 blocks away it leaps at him (every 30 steps, from the ground). A parried
; bite stuns it.
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
    cmp     dword [rbx + MOB.windup], 0
    jg      .winding
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
    mov     eax, SPIDER_WINDUP          ; in reach: rear up
    mov     ecx, SPIDER_WINDUP_ELITE
    cmp     dword [rbx + MOB.elite], 0
    cmovne  eax, ecx
    mov     [rbx + MOB.windup], eax
    mov     dword [rbx + MOB.input + INPUT.fwd], 0
    jmp     .done
.winding:
    mov     dword [rbx + MOB.input + INPUT.fwd], 0
    dec     dword [rbx + MOB.windup]
    jnz     .done                       ; still rearing
    movss   xmm1, [player + BODY.y]     ; the bite lands only on a player still in reach
    subss   xmm1, [rbx + BODY.y]
    mulss   xmm1, xmm1
    comiss  xmm1, [c_reach_y2]
    jae     .bitten
    movss   xmm0, [r12 + 8]
    comiss  xmm0, [c_bite_end2]
    ja      .bitten
    mov     eax, [settings + SETTINGS.difficulty]
    mov     ecx, DIFF_HARD
    cmp     eax, ecx
    cmova   eax, ecx
    mov     edi, [t_dmg_spider + rax*4]
    ELITE_DAMAGE edi
    mov     esi, CAUSE_SPIDER
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.z]
    call    player_take_hit
    cmp     eax, HIT_PARRIED
    je      .parried
    cmp     eax, HIT_TAKEN
    jne     .bitten                     ; blocked or dodged: no knockback
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
.parried:                               ; the riposte stuns it: it reels back and stands dazed
    mov     dword [rbx + MOB.stun], STUN_PARRIED
    mov     rdi, rbx
    mov     rsi, r12
    call    mob_reel
    mov     rdi, rbx
    call    mob_stunned_text
    jmp     .bitten
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

; ai_boss(rdi mob, rsi frame) -> eax 0.  The Fallen King.
; frame = mob_ai's [dx, dz, horizontal distance^2]. Phase 1 above 66 % health, phase 2 above 33 %,
; phase 3 below. He walks at the player (phase 3: 1.4 x faster), stopping 1.6 blocks short. Within 3
; blocks, off cooldown, he raises his fists (36 steps, phase 3: 24) and slams the floor (boss_slam).
; Every 600 steps timer_a summons skeletons (boss_summon); every 240 steps timer_b looses a volley
; in phases 2 and 3 (boss_volley). mob_update counts both timers down before the AI runs.
ai_boss:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12, rsi
    mov     eax, [rbx + MOB.health]
    imul    eax, eax, 100
    mov     ecx, [rbx + MOB.max_health]
    imul    edx, ecx, 66
    mov     r13d, 1
    cmp     eax, edx
    jg      .phased
    imul    edx, ecx, 33
    mov     r13d, 2
    cmp     eax, edx
    jg      .phased
    mov     r13d, 3
.phased:
    movss   xmm0, [c_boss_speed]
    cmp     r13d, 3
    jne     .speed
    mulss   xmm0, [c_boss_rage]
.speed:
    movss   [rbx + BODY.speed], xmm0
    cmp     dword [rbx + MOB.windup], 0
    jg      .winding
    xor     eax, eax                    ; walk at the player until 1.6 blocks away
    movss   xmm0, [r12 + 8]
    comiss  xmm0, [c_boss_stop2]
    setae   al
    mov     [rbx + MOB.input + INPUT.fwd], eax
    cmp     dword [rbx + MOB.cooldown], 0
    jne     .timers
    movss   xmm1, [player + BODY.y]
    subss   xmm1, [rbx + BODY.y]
    mulss   xmm1, xmm1
    addss   xmm1, xmm0                  ; distance^2 including the height difference
    comiss  xmm1, [c_slam_start2]
    jae     .timers
    mov     eax, BOSS_WINDUP            ; within 3 blocks: raise the fists, standing still
    mov     ecx, BOSS_WINDUP_RAGE
    cmp     r13d, 3
    cmove   eax, ecx
    mov     [rbx + MOB.windup], eax
    mov     dword [rbx + MOB.input + INPUT.fwd], 0
    jmp     .timers
.winding:
    mov     dword [rbx + MOB.input + INPUT.fwd], 0
    dec     dword [rbx + MOB.windup]
    jnz     .timers
    mov     rdi, rbx
    mov     rsi, r12
    mov     edx, r13d
    call    boss_slam
.timers:
    cmp     dword [rbx + MOB.timer_a], 0
    jne     .volley
    mov     dword [rbx + MOB.timer_a], BOSS_SUMMON_STEPS
    mov     rdi, rbx
    call    boss_summon
.volley:
    cmp     dword [rbx + MOB.timer_b], 0
    jne     .done
    mov     dword [rbx + MOB.timer_b], BOSS_VOLLEY_STEPS
    cmp     r13d, 2
    jb      .done                       ; phase 1 keeps to melee
    mov     rdi, rbx
    call    boss_volley
.done:
    xor     eax, eax
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; boss_slam(rdi mob, rsi frame, edx phase): the fists come down. A player within 3.5 blocks (phase 3:
; 5) horizontally and 2.5 vertically takes the hit through player_take_hit: a parry stuns the boss
; for 30 steps, a hit shoves the player away at 10 blocks/s and throws him up. Either way the floor
; shakes (fx_explosion, SND_SLAM) and the slam cools down for 70 steps (phase 3: 45).
boss_slam:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13d, edx
    movss   xmm0, [player + BODY.y]
    subss   xmm0, [rbx + BODY.y]
    mulss   xmm0, xmm0
    comiss  xmm0, [c_slam_dy2]
    jae     .impact                     ; too far above or below
    movss   xmm0, [r12 + 8]
    movss   xmm1, [c_slam2]
    cmp     r13d, 3
    jne     .reach
    movss   xmm1, [c_slam2_rage]
.reach:
    comiss  xmm0, xmm1
    jae     .impact                     ; too far away
    mov     eax, [settings + SETTINGS.difficulty]
    mov     ecx, DIFF_HARD
    cmp     eax, ecx
    cmova   eax, ecx
    mov     edi, [t_dmg_slam + rax*4]
    mov     esi, CAUSE_BOSS
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.z]
    call    player_take_hit
    cmp     eax, HIT_PARRIED
    je      .parried
    cmp     eax, HIT_TAKEN
    jne     .impact                     ; blocked or dodged
    movss   xmm2, [r12 + 8]
    sqrtss  xmm2, xmm2                  ; shove the player along boss -> player on the ground plane
    comiss  xmm2, [c_tiny]
    jb      .lift
    movss   xmm3, [c_slam_kb]
    divss   xmm3, xmm2
    movss   xmm0, [r12]
    mulss   xmm0, xmm3
    movss   [player + BODY.kbx], xmm0
    movss   xmm1, [r12 + 4]
    mulss   xmm1, xmm3
    movss   [player + BODY.kbz], xmm1
.lift:
    cmp     dword [player + BODY.on_ground], 0
    je      .impact
    mov     dword [player + BODY.vy], __float32__(5.0)
    jmp     .impact
.parried:
    mov     dword [rbx + MOB.stun], BOSS_STUN
    mov     rdi, rbx
    call    mob_stunned_text
.impact:
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    addss   xmm1, [c_slam_lift]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [c_slam_fx]
    call    fx_explosion
    mov     edi, SND_SLAM
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [c_vol_hurt]
    call    audio_play_at
    mov     eax, BOSS_COOLDOWN
    mov     ecx, BOSS_COOLDOWN_RAGE
    cmp     r13d, 3
    cmove   eax, ecx
    mov     [rbx + MOB.cooldown], eax
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; boss_summon(rdi mob): two skeletons rise 2 blocks to either side of him, unless 4 already live
boss_summon:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdi
    mov     edi, MOB_SKELETON
    call    mob_count_type
    cmp     eax, BOSS_MAX_MINIONS
    jae     .done
    mov     edi, MOB_SKELETON
    movss   xmm0, [rbx + BODY.x]
    subss   xmm0, [c_two]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    call    mob_spawn
    mov     edi, MOB_SKELETON
    movss   xmm0, [rbx + BODY.x]
    addss   xmm0, [c_two]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    call    mob_spawn
.done:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; boss_volley(rdi mob): 5 skeleton arrows fanned -20..+20 degrees (10 apart) around the aim at the
; player's eye, from his head, at 30 blocks/s, lifted against gravity like a skeleton's
; Frame: own head o[3] @0, unit aim dir[3] @12, player eye[3] @24, distance @36, lift @44... see
; the offsets below: lift @40, sin @44, cos @48, rotated dx @52 and dz @60.
boss_volley:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 80
    mov     rbx, rdi
    movss   xmm0, [rbx + BODY.x]
    movss   [rsp], xmm0
    movss   xmm0, [rbx + BODY.y]
    addss   xmm0, [c_boss_eye]
    movss   [rsp + 4], xmm0
    movss   xmm0, [rbx + BODY.z]
    movss   [rsp + 8], xmm0
    lea     rdi, [rsp + 24]
    call    player_eye
    xor     ecx, ecx
.aim:                                   ; dir = player eye - own head
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
    movss   xmm0, [rsp + 36]            ; flight time dist / 30: lift 10 t against gravity
    divss   xmm0, [c_volley_v]
    mulss   xmm0, [c_lift]
    movss   [rsp + 40], xmm0
    mov     r12d, -2
.arrow:
    cvtsi2ss xmm0, r12d
    mulss   xmm0, [c_fan_step]
    call    sincos_deg                  ; xmm0 = sin, xmm1 = cos of the fan angle
    movss   xmm2, [rsp + 12]            ; turn the aim about the vertical axis
    movss   xmm3, [rsp + 20]
    movaps  xmm4, xmm2
    mulss   xmm4, xmm1                  ; dx cos
    movaps  xmm5, xmm3
    mulss   xmm5, xmm0                  ; dz sin
    subss   xmm4, xmm5
    movss   [rsp + 52], xmm4            ; dx' = dx cos - dz sin
    mulss   xmm2, xmm0                  ; dx sin
    mulss   xmm3, xmm1                  ; dz cos
    addss   xmm2, xmm3
    movss   [rsp + 60], xmm2            ; dz' = dx sin + dz cos
    movss   xmm3, [rsp + 52]
    mulss   xmm3, [c_volley_v]          ; vx
    movss   xmm4, [rsp + 16]
    mulss   xmm4, [c_volley_v]
    addss   xmm4, [rsp + 40]            ; vy
    movss   xmm5, [rsp + 60]
    mulss   xmm5, [c_volley_v]          ; vz
    movss   xmm0, [rsp + 52]            ; the arrow starts 0.8 blocks along its heading
    mulss   xmm0, [c_volley_muzzle]
    addss   xmm0, [rsp]
    movss   xmm1, [rsp + 16]
    mulss   xmm1, [c_volley_muzzle]
    addss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 60]
    mulss   xmm2, [c_volley_muzzle]
    addss   xmm2, [rsp + 8]
    mov     eax, [settings + SETTINGS.difficulty]
    mov     ecx, DIFF_HARD
    cmp     eax, ecx
    cmova   eax, ecx
    mov     esi, [t_dmg_volley + rax*4]
    mov     edi, 1                      ; fired by a mob
    xor     edx, edx                    ; cannot be picked up
    mov     ecx, PROJ_ARROW
    xor     r8d, r8d
    call    arrows_spawn
    inc     r12d
    cmp     r12d, 2
    jle     .arrow
    mov     edi, SND_BOW
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [c_vol_bow]
    call    audio_play_at
.done:
    add     rsp, 80
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mob_update(rdi mob): one fixed step for a live mob (timers, AI, physics, sound, sunlight, despawn).
; Frame: [rsp] x and [rsp+4] z before the move.
mob_update:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 24
    mov     rbx, rdi
    DEC_TIMER MOB.stun                  ; counted down first, so the AI sees this step's values
    DEC_TIMER MOB.tagged
    DEC_TIMER MOB.bar
    DEC_TIMER MOB.timer_a
    DEC_TIMER MOB.timer_b
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
; a hostile type also needs block light < 8 in the cell above that block (a torch keeps its
; surroundings clear); a spider (1.4 blocks wide) also needs the 3 x 3 cells above it free.
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
    lea     eax, [rbx - 1]
    cmp     eax, NUM_MOB_TYPES
    jae     .lit_ok
    cmp     byte [t_hostile + rax], 0
    je      .lit_ok
    mov     edi, r12d
    lea     esi, [r15 + 1]
    mov     edx, r13d
    call    light_get
    and     eax, 15                     ; the block-light nibble
    cmp     eax, 8
    jae     .fail
.lit_ok:
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

; mob_drop(rdi mob, esi item, edx count): `count` of `item` pop out of the mob at mid-body height
; (a pig's a little lower)
mob_drop:
    movss   xmm0, [rdi + BODY.x]
    movss   xmm1, [rdi + BODY.height]
    mulss   xmm1, [c_half]
    cmp     dword [rdi + MOB.type], MOB_PIG
    jne     .height
    movss   xmm1, [c_drop_dy]
.height:
    addss   xmm1, [rdi + BODY.y]
    movss   xmm2, [rdi + BODY.z]
    mov     eax, esi
    mov     esi, edx
    mov     edi, eax
    xor     edx, edx
    jmp     drops_spawn

; mob_drops(rdi mob): the loot of a dead mob, popped out at mid-body height. Each of the type's two
; table entries (item, base, range) drops base + rng % range. A hostile mob also drops a gold coin
; half of the time; an elite 3-5 coins and a health potion with 30 % chance; the Fallen King his
; class's legendary weapon, 30 coins and 4 diamonds.
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
    movzx   eax, byte [r12 + 1]
    add     edx, eax                    ; count
    jz      .next                       ; nothing this time
    movzx   esi, byte [r12]
    mov     rdi, rbx
    call    mob_drop
.next:
    add     r12, 3
    dec     r13d
    jnz     .entry
    mov     eax, [rbx + MOB.type]
    cmp     eax, MOB_BOSS
    je      .boss
    cmp     byte [t_hostile + rax - 1], 0
    je      .done                       ; passive mobs and villagers carry nothing else
    cmp     dword [rbx + MOB.elite], 0
    jne     .elite
    call    rng_next                    ; a coin every other time
    test    al, 1
    jnz     .done
    mov     rdi, rbx
    mov     esi, GOLD_COIN
    mov     edx, 1
    call    mob_drop
    jmp     .done
.elite:
    call    rng_next                    ; 3 + rng % 3 coins
    xor     edx, edx
    mov     ecx, 3
    div     ecx
    add     edx, 3
    mov     rdi, rbx
    mov     esi, GOLD_COIN
    call    mob_drop
    call    rng_next                    ; ...and a health potion with 30 % chance
    xor     edx, edx
    mov     ecx, 100
    div     ecx
    cmp     edx, 30
    jae     .done
    mov     rdi, rbx
    mov     esi, HEALTH_POTION
    mov     edx, 1
    call    mob_drop
    jmp     .done
.boss:
    movzx   eax, byte [rpg_state + RPGSAVE.class]
    xor     ecx, ecx
    cmp     eax, NUM_CLASSES
    cmova   eax, ecx                    ; garbage class: the warrior's blade
    movzx   esi, byte [t_legendary + rax]
    mov     rdi, rbx
    mov     edx, 1
    call    mob_drop
    mov     rdi, rbx
    mov     esi, GOLD_COIN
    mov     edx, 30
    call    mob_drop
    mov     rdi, rbx
    mov     esi, DIAMOND
    mov     edx, 4
    call    mob_drop
.done:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; boss_death(rdi mob): the Fallen King falls (his loot comes from mob_drops): the realm remembers
; it (progress flag bit 0), 500 XP, the quest chain moves on, a banner and a blast at his heart
boss_death:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdi
    or      byte [rpg_state + RPGSAVE.flags], 1
    mov     edi, 500
    call    rpg_add_xp
    call    quests_on_boss_killed
    lea     rdi, [s_victory]
    mov     esi, RGBA(255, 215, 60, 255)
    call    hud_banner
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.height]
    mulss   xmm1, [c_half]
    addss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [c_boss_death_r]
    call    fx_explosion
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; mob_hurt(edi idx, esi dmg, xmm0 dirx, xmm1 dirz) -> eax 1 applied / 0 (no such mob, a villager, or
; still in its hurt window). Knocks the mob along (dirx, dirz); a passive mob panics and flees that
; way, a dead mob drops its loot (mob_drops).
; mob_strike(...): the same, but it lands even inside the hurt window, so rapid fire, shotgun
; pellets, spells and melee strikes all count.
; Both consume combat_hit_flags (cleared on return): HF_PLAYER tags the mob, so a kill within 200
; steps pays XP; HF_CRIT makes the floating damage number a critical one. A kill reports to the RPG
; (rpg_on_mob_killed when tagged), to the dungeon the mob was born in (structures_on_mob_killed)
; and, for the Fallen King, to boss_death. The Fallen King barely budges when hit and roars when
; he drops to a third of his health.
; Frame: [rsp] dirx, [rsp+4] dirz, [rsp+8] health before the hit.
mob_strike:
    mov     r8d, 1
    jmp     mob_damage
mob_hurt:
    xor     r8d, r8d
mob_damage:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    cmp     edi, MAX_MOBS
    jae     .no
    imul    ebx, edi, MOB_size
    lea     rax, [mobs]
    add     rbx, rax
    mov     eax, [rbx + MOB.type]
    test    eax, eax
    jz      .no
    cmp     eax, MOB_MERCHANT           ; villagers cannot be hurt
    je      .no
    cmp     eax, MOB_ELDER
    je      .no
    test    r8d, r8d
    jnz     .apply
    cmp     dword [rbx + MOB.hurt], 0
    jg      .no
.apply:
    mov     r12d, esi                   ; damage
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    mov     eax, [rbx + MOB.health]
    mov     [rsp + 8], eax
    sub     [rbx + MOB.health], esi
    mov     dword [rbx + MOB.hurt], HURT_STEPS
    mov     dword [rbx + MOB.bar], BAR_STEPS
    test    byte [combat_hit_flags], HF_PLAYER
    jz      .knock
    mov     dword [rbx + MOB.tagged], TAG_STEPS
.knock:
    movss   xmm2, [c_kb]
    cmp     dword [rbx + MOB.type], MOB_BOSS
    jne     .shove
    mulss   xmm2, [c_boss_kb]           ; the Fallen King barely budges...
.shove:
    movss   xmm0, [rsp]
    mulss   xmm0, xmm2
    movss   [rbx + BODY.kbx], xmm0
    movss   xmm1, [rsp + 4]
    mulss   xmm1, xmm2
    movss   [rbx + BODY.kbz], xmm1
    cmp     dword [rbx + MOB.type], MOB_BOSS
    je      .sound                      ; ...and is never thrown into the air
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
    movss   xmm0, [rbx + BODY.x]        ; the damage number floats up from above the head; over
    movss   xmm1, [rbx + BODY.height]   ; the Fallen King it starts at 2 blocks, in view up close
    minss   xmm1, [c_two]
    addss   xmm1, [rbx + BODY.y]
    addss   xmm1, [c_over_head]
    movss   xmm2, [rbx + BODY.z]
    mov     edi, r12d
    movzx   esi, byte [combat_hit_flags]
    and     esi, HF_CRIT
    call    dmgnum_spawn
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
    jg      .alive
    cmp     dword [rbx + MOB.tagged], 0
    jle     .origin
    mov     edi, [rbx + MOB.type]       ; the player had a hand in it: XP
    mov     esi, [rbx + MOB.elite]
    call    rpg_on_mob_killed
.origin:
    mov     edi, [rbx + MOB.origin]
    lea     eax, [rdi - 1]
    cmp     eax, NUM_DUNGEONS - 1
    ja      .loot                       ; not born in a dungeon
    call    structures_on_mob_killed
.loot:
    cmp     dword [rbx + MOB.type], MOB_BOSS
    jne     .drops
    mov     rdi, rbx
    call    boss_death
.drops:
    mov     rdi, rbx
    call    mob_drops
    mov     dword [rbx + MOB.type], MOB_NONE
    jmp     .yes
.alive:
    cmp     dword [rbx + MOB.type], MOB_BOSS
    jne     .yes
    imul    ecx, [rbx + MOB.max_health], 33
    mov     eax, [rbx + MOB.health]
    imul    eax, eax, 100
    cmp     eax, ecx
    jg      .yes                        ; still above a third of his health
    mov     eax, [rsp + 8]
    imul    eax, eax, 100
    cmp     eax, ecx
    jle     .yes                        ; was already enraged
    mov     edi, SND_BOSS_ROAR          ; this hit drove him into phase 3
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [c_vol_hurt]
    call    audio_play_at
    lea     rdi, [s_furious]
    mov     esi, RGBA(255, 80, 60, 255)
    call    hud_banner
.yes:
    mov     eax, 1
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    mov     byte [combat_hit_flags], 0
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mobs_intersect_block(edi x, esi y, edx z, ecx id) -> eax 1 if any live mob's box strictly overlaps
; the collision boxes block `id` would have in that cell
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
    mov     [rsp], ecx
    lea     rbx, [mobs]
    lea     r12, [mobs_end]
.loop:
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .next
    mov     rdi, rbx
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, r15d
    mov     r8d, [rsp]
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

; mobs_save(rdi WORLDHDR*): the live mobs as compact MOBSAVE records, mob_count set. An elite's
; type carries MOB_ELITE_BIT; villagers and the boss are skipped (the sites re-create them).
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
    cmp     eax, MOB_MERCHANT
    jae     .next                       ; villagers and the boss are re-created from the sites
    cmp     dword [rsi + MOB.elite], 0
    je      .plain
    or      eax, MOB_ELITE_BIT
.plain:
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
; type (low byte 1..6, bit 8 = elite) inside the world, with its health clamped to 1..max
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
    movzx   eax, byte [r13 + MOBSAVE.type]
    dec     eax
    cmp     eax, 5
    ja      .skip                       ; not a saved mob type (1..6)
    IN_RANGE [r13 + MOBSAVE.x], c_256
    IN_RANGE [r13 + MOBSAVE.y], c_64
    IN_RANGE [r13 + MOBSAVE.z], c_256
    movzx   edi, byte [r13 + MOBSAVE.type]  ; the low byte is the type, bit 8 marks an elite
    movss   xmm0, [r13 + MOBSAVE.x]
    movss   xmm1, [r13 + MOBSAVE.y]
    movss   xmm2, [r13 + MOBSAVE.z]
    call    mob_spawn
    test    eax, eax
    js      .done
    imul    eax, eax, MOB_size
    lea     rdx, [mobs]
    add     rdx, rax                    ; the new mob
    test    dword [r13 + MOBSAVE.type], MOB_ELITE_BIT
    jz      .plain
    call    make_elite                  ; rdx = the new mob: elite flag, health and speed
.plain:
    mov     esi, [rdx + MOB.max_health] ; saved health clamps to 1..max (an elite's max is 2.5 x base)
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
