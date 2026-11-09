; test_guns.asm - firearms: reloading, firing, pellets, attachments, bullets, grenades and rockets in flight.
%include "common.inc"
default rel

global test_gun_reload_fills_magazine, test_gun_fire_cooldown_and_dry
global test_shotgun_spawns_six_pellets, test_bullet_hits_mob_and_stops
global test_rocket_explodes_on_impact, test_rifle_kills_zombie_point_blank
global test_aimed_shotgun_has_no_spread, test_bullet_damage_pipeline, test_gun_attachment_effects
global test_new_guns_fire, test_grenade_and_rocket_blasts

extern gun_reset, gun_reload_start, gun_step, gun_fire, gun_reload, gun_cooldown
extern gun_index, gun_magazine, gun_shot_info, gun_ammo, gun_automatic, gun_reload_total
extern arrows, arrows_clear, arrows_spawn, arrows_step
extern inv, inv_sel, inv_clear, game_mode, settings, game_time
extern mobs, mobs_clear, mob_spawn, mob_count_type, rng_seed, tnt_clear, drops_clear
extern world_clear, world_set, world_get, survival_reset
extern rpg_stats, rpg_keystones, game_aim, combat_bullseye_t, combat_fanhammer_t, explode_mob_mult

%define STK(id, n, dmg) ((id) | ((n) << 8) | ((dmg) << 16))
%define HELD (inv + INVENTORY.slots)    ; slot 0, selected by every test

section .rodata
align 4
eye:      dd 16.5, 12.62, 16.5          ; standing on the floor at (16.5, 11, 16.5)
dir_n:    dd 0.0, 0.0, -1.0
k_16_5:   dd 16.5
k_11:     dd 11.0
k_11_5:   dd 11.5
k_10_5:   dd 10.5
k_8_5:    dd 8.5
k_20:     dd 20.0
k_m90:    dd -90.0
k_m25:    dd -25.0
; zombie centres in front of the eye (z = 16.5): 1.0 ahead, and 0.2 ahead with the zombie
; overlapping the player so the muzzle (0.3 ahead) starts inside its box
zombie_z: dd 15.5, 16.3
k_one:    dd 1.0
k_117:    dd 117.0
k_tol:    dd 0.05
k_90:     dd 90.0
k_0_48:   dd 0.48
k_0_52:   dd 0.52
; blast_run's zombies: 1.5, 4.0, 12 and 7 blocks from the point (16.5, 16.5) the projectile is released
; over, and (V_HIT_G) one standing right under it
zomb_x:   dd 18.0, 20.5, 16.5, 23.5, 16.5
zomb_z:   dd 16.5, 16.5, 4.5, 16.5, 16.5
; blast_run's projectiles (variants): kind, height, vertical speed, steps flown
%define V_DROP       0                  ; a grenade dropped from 2 blocks up
%define V_DIVE       1                  ; a rocket diving at 25 blocks per second from 3 up
%define V_LOB        2                  ; a grenade lobbed up: 2 blocks above the floor again when its time is up
%define V_LOB_EARLY  3                  ; the same lob 25 steps before that, still flying high
%define V_HIT_G      4                  ; a grenade dropped onto a zombie's head
var_kind:  dd PROJ_GRENADE, PROJ_ROCKET, PROJ_GRENADE, PROJ_GRENADE, PROJ_GRENADE
var_y:     dd 13.0, 14.0, 11.5, 11.5, 13.0
var_vy:    dd 0.0, -25.0, 20.9, 20.9, 0.0
var_steps: dd 60, 60, 125, 100, 60

section .bss
alignb 4
stats_save: resd NUM_STATS              ; rpg_stats, rpg_keystones, game_aim and the two timers a test starts from
ks_save:    resd 1
aim_save:   resd 1
bull_save:  resd 1
fan_save:   resd 1
held_state: resd 1                      ; 1 while the saved state is held
out_info:   resd 4                      ; gun_shot_info results
alignb 8
pig_ptr:    resq 1                      ; the target of shoot_pig
sum_plain:  resd 1                      ; sums of |vx| over a shotgun shot's pellets
sum_comp:   resd 1
alignb 8
zomb:       resq 5                      ; the zombies of blast_run
dmg_plain:  resd 1                      ; what a plain grenade or rocket did to the nearest zombie

section .text

; state_enter(): clears rpg_stats, rpg_keystones, game_aim and the Bullseye and Fan the Hammer timers so
; the damage pipeline sees a plain character; the first call of a test saves what was there
state_enter:
    cmp     dword [held_state], 0
    jne     .clear
    lea     rsi, [rpg_stats]
    lea     rdi, [stats_save]
    mov     ecx, NUM_STATS
    rep     movsd
    mov     eax, [rpg_keystones]
    mov     [ks_save], eax
    mov     eax, [game_aim]
    mov     [aim_save], eax
    mov     eax, [combat_bullseye_t]
    mov     [bull_save], eax
    mov     eax, [combat_fanhammer_t]
    mov     [fan_save], eax
    mov     dword [held_state], 1
.clear:
    lea     rdi, [rpg_stats]
    mov     ecx, NUM_STATS
    xor     eax, eax
    rep     stosd
    mov     [rpg_keystones], eax
    mov     [game_aim], eax
    mov     [combat_bullseye_t], eax
    mov     [combat_fanhammer_t], eax
    ret

; state_leave(): puts back what the first state_enter of the test saved
state_leave:
    cmp     dword [held_state], 0
    je      .ret
    lea     rsi, [stats_save]
    lea     rdi, [rpg_stats]
    mov     ecx, NUM_STATS
    rep     movsd
    mov     eax, [ks_save]
    mov     [rpg_keystones], eax
    mov     eax, [aim_save]
    mov     [game_aim], eax
    mov     eax, [bull_save]
    mov     [combat_bullseye_t], eax
    mov     eax, [fan_save]
    mov     [combat_fanhammer_t], eax
    mov     dword [held_state], 0
.ret:
    ret

; setup(): empty world with a STONE floor at y = 10 (x, z 0..31), Survival at Normal
; difficulty, nothing in flight, no mobs, an empty inventory with slot 0 selected, a plain character
; (state_enter: no stats, keystones, aim or timers)
setup:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    state_enter
    call    world_clear
    mov     edi, 1234
    call    rng_seed
    call    inv_clear
    mov     dword [inv_sel], 0
    call    gun_reset
    call    arrows_clear
    call    mobs_clear
    call    tnt_clear
    call    drops_clear
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    mov     dword [game_time], NEW_WORLD_TIME
    call    survival_reset
    xor     r12d, r12d
.z:
    xor     ebx, ebx
.x:
    mov     edi, ebx
    mov     esi, 10
    mov     edx, r12d
    mov     ecx, STONE
    call    world_set
    inc     ebx
    cmp     ebx, 32
    jb      .x
    inc     r12d
    cmp     r12d, 32
    jb      .z
    pop     r12
    pop     rbx
    pop     rbp
    ret

; cleanup(eax result) -> eax result: leave no projectiles, mobs, drops or inventory behind
cleanup:
    push    rbx
    mov     ebx, eax
    call    arrows_clear
    call    mobs_clear
    call    tnt_clear
    call    drops_clear
    call    inv_clear
    call    gun_reset
    call    state_leave
    mov     dword [game_mode], MODE_SURVIVAL
    mov     eax, ebx
    pop     rbx
    ret

; live_of_kind(edi kind) -> eax number of live projectiles of that kind
live_of_kind:
    lea     rcx, [arrows]
    xor     eax, eax
    mov     edx, MAX_ARROWS
.l:
    cmp     dword [rcx + ARROWENT.live], 0
    je      .n
    cmp     [rcx + ARROWENT.kind], edi
    jne     .n
    inc     eax
.n:
    add     rcx, ARROWENT_size
    dec     edx
    jnz     .l
    ret

; steps(edi n): n times gun_step
steps:
    push    rbx
    mov     ebx, edi
.l:
    call    gun_step
    dec     ebx
    jnz     .l
    pop     rbx
    ret

; fire() -> eax gun_fire(eye, -z, full spread)
fire:
    lea     rdi, [eye]
    lea     rsi, [dir_n]
    movss   xmm0, [k_one]
    jmp     gun_fire

; fire_scale(xmm0 scale) -> eax gun_fire(eye, -z, that spread scale)
fire_scale:
    lea     rdi, [eye]
    lea     rsi, [dir_n]
    jmp     gun_fire

; first_live() -> rax the first live projectile, 0 when none
first_live:
    lea     rax, [arrows]
    mov     ecx, MAX_ARROWS
.l:
    cmp     dword [rax + ARROWENT.live], 0
    jne     .ret
    add     rax, ARROWENT_size
    dec     ecx
    jnz     .l
    xor     eax, eax
.ret:
    ret

; count_where(edi flag mask, esi mode) -> eax live projectiles: mode 0 with any of the flag bits set
; in ARROWENT.flags, mode 1 flying dead straight (vx = vy = 0; the mask is ignored)
count_where:
    lea     rcx, [arrows]
    xor     eax, eax
    mov     edx, MAX_ARROWS
.l:
    cmp     dword [rcx + ARROWENT.live], 0
    je      .n
    test    esi, esi
    jnz     .straight
    test    [rcx + ARROWENT.flags], edi
    jz      .n
    inc     eax
    jmp     .n
.straight:
    cmp     dword [rcx + ARROWENT.vx], 0
    jne     .n
    cmp     dword [rcx + ARROWENT.vy], 0
    jne     .n
    inc     eax
.n:
    add     rcx, ARROWENT_size
    dec     edx
    jnz     .l
    ret

; speed_of(rdi projectile) -> xmm0 its speed, blocks per second
speed_of:
    movss   xmm0, [rdi + ARROWENT.vx]
    mulss   xmm0, xmm0
    movss   xmm1, [rdi + ARROWENT.vy]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    movss   xmm1, [rdi + ARROWENT.vz]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    sqrtss  xmm0, xmm0
    ret

; close_to(xmm0 a, xmm1 b) -> eax 1 when |a - b| < 0.05
close_to:
    subss   xmm0, xmm1
    xorps   xmm2, xmm2
    subss   xmm2, xmm0
    maxss   xmm0, xmm2                  ; |a - b|
    xor     eax, eax
    comiss  xmm0, [k_tol]
    setb    al
    ret

; A reload takes the pistol's 60 steps and fills the magazine from the inventory: all 5
; rounds when that is all there is, 3 of 20 to top it up; a full magazine does not reload;
; in Creative the magazine fills without ammunition.
test_gun_reload_fills_magazine:
    push    rbp
    mov     rbp, rsp
    call    setup
    mov     dword [HELD], STK(PISTOL, 1, 0)
    mov     dword [HELD + 4], STK(PISTOL_ROUND, 5, 0)
    call    gun_reload_start
    cmp     eax, 1
    jne     .fail
    mov     edi, 59
    call    steps
    cmp     word [HELD + ITEMSTACK.dmg], 0
    jne     .fail                       ; not loaded before the reload ends
    mov     edi, 1
    call    steps
    cmp     dword [HELD], STK(PISTOL, 1, 5)
    jne     .fail
    cmp     byte [HELD + 4 + ITEMSTACK.count], 0
    jne     .fail
    mov     dword [HELD + 4], STK(PISTOL_ROUND, 20, 0)
    call    gun_reload_start
    cmp     eax, 1
    jne     .fail
    mov     edi, 60
    call    steps
    cmp     dword [HELD], STK(PISTOL, 1, 8)
    jne     .fail
    cmp     dword [HELD + 4], STK(PISTOL_ROUND, 17, 0)
    jne     .fail
    call    gun_reload_start
    test    eax, eax
    jnz     .fail                       ; full
    mov     dword [game_mode], MODE_CREATIVE
    mov     dword [HELD], STK(PISTOL, 1, 0)
    mov     dword [HELD + 4], 0
    call    gun_reload_start
    cmp     eax, 1
    jne     .fail
    mov     edi, 60
    call    steps
    cmp     dword [HELD], STK(PISTOL, 1, 8)
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    call    cleanup
    pop     rbp
    ret

; One shot takes a round and spawns a bullet; the next is refused for the pistol's 15-step
; cooldown; an empty magazine clicks, fires nothing and starts a reload.
test_gun_fire_cooldown_and_dry:
    push    rbp
    mov     rbp, rsp
    call    setup
    mov     dword [HELD], STK(PISTOL, 1, 2)
    mov     dword [HELD + 4], STK(PISTOL_ROUND, 10, 0)
    call    fire
    cmp     eax, 1
    jne     .fail
    cmp     word [HELD + ITEMSTACK.dmg], 1
    jne     .fail
    mov     edi, PROJ_BULLET
    call    live_of_kind
    cmp     eax, 1
    jne     .fail
    call    fire
    test    eax, eax
    jnz     .fail                       ; still cooling down
    mov     edi, 15
    call    steps
    call    fire
    cmp     eax, 1
    jne     .fail
    cmp     word [HELD + ITEMSTACK.dmg], 0
    jne     .fail
    mov     edi, 15
    call    steps
    call    fire
    test    eax, eax
    jnz     .fail                       ; empty
    cmp     dword [gun_reload], 0
    je      .fail                       ; the dry click started a reload
    mov     edi, PROJ_BULLET
    call    live_of_kind
    cmp     eax, 2
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    call    cleanup
    pop     rbp
    ret

; Fired fully aimed (spread scale 0), all six shotgun pellets fly dead straight along -z.
test_aimed_shotgun_has_no_spread:
    push    rbp
    mov     rbp, rsp
    call    setup
    mov     dword [HELD], STK(SHOTGUN, 1, 1)
    lea     rdi, [eye]
    lea     rsi, [dir_n]
    xorps   xmm0, xmm0
    call    gun_fire
    cmp     eax, 1
    jne     .fail
    lea     rcx, [arrows]
    xor     edx, edx                    ; pellets checked
    mov     r8d, MAX_ARROWS
.l:
    cmp     dword [rcx + ARROWENT.live], 0
    je      .n
    cmp     dword [rcx + ARROWENT.vx], 0
    jne     .fail
    cmp     dword [rcx + ARROWENT.vy], 0
    jne     .fail
    inc     edx
.n:
    add     rcx, ARROWENT_size
    dec     r8d
    jnz     .l
    cmp     edx, 6
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    call    cleanup
    pop     rbp
    ret

; One shotgun shell is six bullets.
test_shotgun_spawns_six_pellets:
    push    rbp
    mov     rbp, rsp
    call    setup
    mov     dword [HELD], STK(SHOTGUN, 1, 1)
    call    fire
    cmp     eax, 1
    jne     .fail
    mov     edi, PROJ_BULLET
    call    live_of_kind
    cmp     eax, 6
    jne     .fail
    cmp     word [HELD + ITEMSTACK.dmg], 0
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    call    cleanup
    pop     rbp
    ret

; spawn_bullet(xmm0 x, xmm1 y, xmm2 z, xmm5 vz, esi damage): a player bullet flying along z
spawn_bullet:
    xor     r8d, r8d
; spawn_bullet_flags(xmm0 x, xmm1 y, xmm2 z, xmm5 vz, esi damage, r8d AF_* flags)
spawn_bullet_flags:
    sub     rsp, 8
    xorps   xmm3, xmm3
    xorps   xmm4, xmm4
    xor     edi, edi
    xor     edx, edx
    mov     ecx, PROJ_BULLET
    call    arrows_spawn
    add     rsp, 8
    ret

; Two bullets fired together both hurt the pig in their way (20 - 5 - 5: the second lands
; inside the hurt window the first opened) and are spent; a bullet into a stone wall
; vanishes and leaves the wall standing.
test_bullet_hits_mob_and_stops:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    setup
    mov     edi, MOB_PIG                ; pig at (16.5, 11, 10.5)
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_10_5]
    call    mob_spawn
    test    eax, eax
    js      .fail
    imul    ebx, eax, MOB_size
    lea     rax, [mobs]
    add     rbx, rax
    mov     dword [rbx + MOB.health], 20
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11_5]
    movss   xmm2, [k_16_5]
    movss   xmm5, [k_m90]
    mov     esi, 5
    call    spawn_bullet
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11_5]
    movss   xmm2, [k_16_5]
    movss   xmm5, [k_m90]
    mov     esi, 5
    call    spawn_bullet
    mov     r12d, 30
.fly:
    call    arrows_step
    dec     r12d
    jnz     .fly
    cmp     dword [rbx + MOB.health], 10
    jne     .fail
    mov     edi, PROJ_BULLET
    call    live_of_kind
    test    eax, eax
    jnz     .fail
    call    mobs_clear
    mov     r12d, 4                     ; a stone wall at x = 16, y = 11, z = 4..6
.wall:
    mov     edi, 16
    mov     esi, 11
    mov     edx, r12d
    mov     ecx, STONE
    call    world_set
    inc     r12d
    cmp     r12d, 7
    jb      .wall
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11_5]
    movss   xmm2, [k_16_5]
    movss   xmm5, [k_m90]
    mov     esi, 5
    call    spawn_bullet
    mov     r12d, 30
.fly2:
    call    arrows_step
    dec     r12d
    jnz     .fly2
    mov     edi, PROJ_BULLET
    call    live_of_kind
    test    eax, eax
    jnz     .fail                       ; spent on the wall, not stuck in it
    mov     edi, 16
    mov     esi, 11
    mov     edx, 6
    call    world_get
    cmp     eax, STONE
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    call    cleanup
    pop     r12
    pop     rbx
    pop     rbp
    ret

; A rocket dropped onto a stone cube (x, y, z 2..14) blows a crater into its top.
test_rocket_explodes_on_impact:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    setup
    mov     r12d, 2                     ; y
.y:
    mov     ebx, (2 << 8) | 2           ; z << 8 | x
.zx:
    movzx   edi, bl
    mov     esi, r12d
    movzx   edx, bh
    mov     ecx, STONE
    call    world_set
    inc     bl
    cmp     bl, 15
    jb      .zx
    mov     bl, 2
    inc     bh
    cmp     bh, 15
    jb      .zx
    inc     r12d
    cmp     r12d, 15
    jb      .y
    movss   xmm0, [k_8_5]               ; rocket at (8.5, 20, 8.5) falling at 25 blocks/s
    movss   xmm1, [k_20]
    movss   xmm2, [k_8_5]
    xorps   xmm3, xmm3
    movss   xmm4, [k_m25]
    xorps   xmm5, xmm5
    xor     edi, edi
    xor     esi, esi
    xor     edx, edx
    mov     ecx, PROJ_ROCKET
    xor     r8d, r8d
    call    arrows_spawn
    mov     r12d, 120
.fly:
    call    arrows_step
    dec     r12d
    jnz     .fly
    mov     edi, PROJ_ROCKET
    call    live_of_kind
    test    eax, eax
    jnz     .fail
    mov     edi, 8
    mov     esi, 14
    mov     edx, 8
    call    world_get
    test    eax, eax
    jnz     .fail
    mov     edi, 8
    mov     esi, 13
    mov     edx, 8
    call    world_get
    test    eax, eax
    jnz     .fail
    mov     edi, 8                      ; the cube's base is out of reach
    mov     esi, 2
    mov     edx, 8
    call    world_get
    cmp     eax, STONE
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    call    cleanup
    pop     r12
    pop     rbx
    pop     rbp
    ret

; Four Kalashnikov rounds (4 x 6 >= 20) kill a zombie straight ahead at point blank, both
; 1 block in front and pressed against the player with the muzzle inside its box. Between
; shots the cooldown runs out and the bullets fly.
test_rifle_kills_zombie_point_blank:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    xor     r13d, r13d                  ; case: zombie_z index
.case:
    call    setup
    mov     dword [game_time], 40000    ; night: no sunburn to help
    mov     dword [HELD], STK(KALASHNIKOV, 1, 30)
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11]
    lea     rax, [zombie_z]
    movss   xmm2, [rax + r13*4]
    call    mob_spawn
    test    eax, eax
    js      .fail
    mov     ebx, 4                      ; shots
.shot:
    call    fire
    cmp     eax, 1
    jne     .fail
    mov     r12d, 6                     ; the rifle's cooldown, the bullets in flight
.step:
    call    arrows_step
    call    gun_step
    dec     r12d
    jnz     .step
    dec     ebx
    jnz     .shot
    mov     edi, MOB_ZOMBIE
    call    mob_count_type
    test    eax, eax
    jnz     .fail
    cmp     word [HELD + ITEMSTACK.dmg], 26
    jne     .fail
    inc     r13d
    cmp     r13d, 2
    jb      .case
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    call    cleanup
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- bullets through the damage pipeline ----------------------------------------------------

; shoot_pig(esi damage, r8d AF_* flags, edi bullets) -> eax the pig's health afterwards.
; The pig (pig_ptr) gets 20 health and no hurt window; the bullets start 6 blocks from it and fly at
; 90 blocks per second, one step apart; then 10 more steps run.
shoot_pig:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     ebx, esi
    mov     r12d, r8d
    mov     r13d, edi
    mov     rax, [pig_ptr]
    mov     dword [rax + MOB.health], 20
    mov     dword [rax + MOB.hurt], 0
    call    arrows_clear
.spawn:
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11_5]
    movss   xmm2, [k_16_5]
    movss   xmm5, [k_m90]
    mov     esi, ebx
    mov     r8d, r12d
    call    spawn_bullet_flags
    call    arrows_step
    dec     r13d
    jnz     .spawn
    mov     r14d, 10
.fly:
    call    arrows_step
    dec     r14d
    jnz     .fly
    mov     rax, [pig_ptr]
    mov     eax, [rax + MOB.health]
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; SHOOT bullets, damage, flags, expected health of the 20-health pig afterwards
%macro SHOOT 4
    mov     edi, %1
    mov     esi, %2
    mov     r8d, %3
    call    shoot_pig
    cmp     eax, %4
    jne     .fail
%endmacro

; A bullet goes through the damage pipeline as SRC_GUN: GUN_DMG (the gun family), ALL_DMG and a crit
; (x1.5 at no CRIT_DMG) scale it, SPELL_DMG does not, and every bullet counts, also two a step apart.
; A 5-damage bullet into a 20-health pig: 5 x 1.6 = 8 (GUN_DMG 60), a crit 12, 5 with only SPELL_DMG,
; 10 with ALL_DMG 100.
test_bullet_damage_pipeline:
    push    rbp
    mov     rbp, rsp
    call    setup
    mov     edi, MOB_PIG                ; pig at (16.5, 11, 10.5)
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_10_5]
    call    mob_spawn
    test    eax, eax
    js      .fail
    imul    eax, eax, MOB_size
    lea     rcx, [mobs]
    add     rax, rcx
    mov     [pig_ptr], rax
    SHOOT   1, 5, 0, 20 - 5             ; a plain character: the base damage
    mov     dword [rpg_stats + STAT_GUN_DMG * 4], 60
    SHOOT   1, 5, 0, 20 - 8
    SHOOT   1, 5, AF_CRIT, 20 - 12
    mov     dword [rpg_stats + STAT_GUN_DMG * 4], 0
    mov     dword [rpg_stats + STAT_SPELL_DMG * 4], 100
    SHOOT   1, 5, 0, 20 - 5             ; spell damage is not gun damage
    mov     dword [rpg_stats + STAT_SPELL_DMG * 4], 0
    mov     dword [rpg_stats + STAT_ALL_DMG * 4], 100
    SHOOT   1, 5, 0, 20 - 10
    mov     dword [rpg_stats + STAT_ALL_DMG * 4], 0
    SHOOT   2, 5, 0, 20 - 5 - 5        ; two bullets one step apart: both land
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    call    cleanup
    pop     rbp
    ret

; ---- attachments, keystones and abilities in the firing rules ------------------------------

; INFO id, w, damage, pellets, cooldown, crit: gun_shot_info gives exactly those four numbers
%macro INFO 6
    mov     edi, %1
    mov     esi, %2
    lea     rdx, [out_info]
    call    gun_shot_info
    cmp     eax, 1
    jne     .fail
    cmp     dword [out_info], %3
    jne     .fail
    cmp     dword [out_info + 4], %4
    jne     .fail
    cmp     dword [out_info + 8], %5
    jne     .fail
    cmp     dword [out_info + 12], %6
    jne     .fail
%endmacro

; MAGAZINE id, w, size: gun_magazine of that firearm with that dmg word
%macro MAGAZINE 3
    mov     edi, %1
    mov     esi, %2
    call    gun_magazine
    cmp     eax, %3
    jne     .fail
%endmacro

; START_RELOAD id, w, ammo id, ammo count: that firearm (dmg word w) in slot 0 and the ammunition in
; slot 1, a fresh state, then gun_reload_start -> eax
%macro START_RELOAD 4
    call    gun_reset
    mov     dword [HELD], STK(%1, 1, %2)
    mov     dword [HELD + 4], STK(%3, %4, 0)
    call    gun_reload_start
%endmacro

; SHOT id, w: nothing in flight, no cooldown, that firearm (dmg word w) in slot 0, one shot at the
; full hip spread -> eax (SHOT0: spread scale 0)
%macro SHOT 2
    call    arrows_clear
    mov     dword [gun_cooldown], 0
    mov     dword [gun_reload], 0
    mov     dword [HELD], STK(%1, 1, %2)
    call    fire
%endmacro
%macro SHOT0 2
    call    arrows_clear
    mov     dword [gun_cooldown], 0
    mov     dword [gun_reload], 0
    mov     dword [HELD], STK(%1, 1, %2)
    xorps   xmm0, xmm0
    call    fire_scale
%endmacro

; STRAIGHT n: exactly n live projectiles fly dead straight (vx = vy = 0)
%macro STRAIGHT 1
    xor     edi, edi
    mov     esi, 1
    call    count_where
    cmp     eax, %1
    jne     .fail
%endmacro

; vx_sum() -> xmm0 the sum of |vx| over the live projectiles
vx_sum:
    lea     rcx, [arrows]
    xorps   xmm0, xmm0
    mov     edx, MAX_ARROWS
.l:
    cmp     dword [rcx + ARROWENT.live], 0
    je      .n
    movss   xmm1, [rcx + ARROWENT.vx]
    xorps   xmm2, xmm2
    subss   xmm2, xmm1
    maxss   xmm1, xmm2
    addss   xmm0, xmm1
.n:
    add     rcx, ARROWENT_size
    dec     edx
    jnz     .l
    ret

; crit_shots(edi n, esi w) -> eax how many of n shots of a loaded pistol (dmg word w) were crits
crit_shots:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, esi
    xor     r13d, r13d
.shot:
    call    arrows_clear
    mov     dword [gun_cooldown], 0
    mov     dword [gun_reload], 0
    mov     eax, r12d
    shl     eax, 16
    or      eax, PISTOL | 0x100
    mov     [HELD], eax
    call    fire
    call    first_live
    test    rax, rax
    jz      .next
    test    dword [rax + ARROWENT.flags], AF_CRIT
    jz      .next
    inc     r13d
.next:
    dec     ebx
    jnz     .shot
    call    arrows_clear
    mov     eax, r13d
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; The numbers behind a shot: magazines (Extended Magazine, Quartermaster), gun_shot_info (Rifled
; Barrel, Compensator), the reload (RELOAD_SPEED, ARROW_SAVE, the high byte of the dmg word kept),
; Fan the Hammer (free rounds, half the cooldown), the spread (Bullseye, an aimed Scope, the
; Compensator), Rifled Barrel's speed and damage, and the crit (Bullseye +25, aimed Scope +15,
; Deadshot, no crit for a rocket).
test_gun_attachment_effects:
    push    rbp
    mov     rbp, rsp
    call    setup
    ; ---- magazines: ATT_EXTMAG makes it 3/2 rounded up, Quartermaster once more; rounds in the word do not count
    MAGAZINE PISTOL, 0, 8
    MAGAZINE PISTOL, ATT_EXTMAG, 12
    MAGAZINE PISTOL, ATT_EXTMAG | 5, 12
    MAGAZINE PISTOL, ATT_SCOPE | ATT_RIFLED | ATT_COMP, 8
    MAGAZINE KALASHNIKOV, ATT_EXTMAG, 45
    MAGAZINE STICK, ATT_EXTMAG, 0
    mov     dword [rpg_keystones], 1 << KS_QUARTERMASTER
    MAGAZINE PISTOL, 0, 12
    MAGAZINE PISTOL, ATT_EXTMAG, 18
    MAGAZINE KALASHNIKOV, ATT_EXTMAG, 68
    mov     dword [rpg_keystones], 0
    ; ---- gun_shot_info
    INFO    PISTOL, 0, 5, 1, 15, 1
    INFO    PISTOL, ATT_RIFLED | ATT_COMP, 6, 1, 11, 1
    INFO    PISTOL, ATT_SCOPE | ATT_EXTMAG | 8, 5, 1, 15, 1    ; scope, magazine and rounds change nothing here
    INFO    SHOTGUN, ATT_RIFLED, 4, 6, 48, 1                   ; 3 + max(1, 3 / 4)
    INFO    MUSKET, ATT_RIFLED, 17, 1, 10, 1                   ; 14 + 14 / 4
    INFO    KALASHNIKOV, ATT_RIFLED | ATT_COMP, 7, 1, 5, 1     ; 6 + 1; (3 * 6 + 2) / 4
    INFO    ROCKET_LAUNCHER, ATT_RIFLED | ATT_COMP, 24, 1, 8, 0 ; its blast does 24, no crit; (3 * 10 + 2) / 4
    INFO    REVOLVER, 0, 10, 1, 18, 1
    INFO    HUNTING_RIFLE, ATT_RIFLED, 27, 1, 40, 1            ; 22 + 22 / 4
    mov     dword [out_info], 0x7F7F7F7F
    mov     dword [out_info + 12], 0x7F7F7F7F
    mov     edi, STICK
    xor     esi, esi
    lea     rdx, [out_info]
    call    gun_shot_info
    test    eax, eax
    jnz     .fail                       ; not a firearm: 0, and the numbers are left alone
    cmp     dword [out_info], 0x7F7F7F7F
    jne     .fail
    cmp     dword [out_info + 12], 0x7F7F7F7F
    jne     .fail
    ; ---- the reload takes 60 * 100 / (100 + RELOAD_SPEED) steps, never under 10
    mov     dword [rpg_stats + STAT_RELOAD_SPEED * 4], 100
    START_RELOAD PISTOL, 0, PISTOL_ROUND, 20
    cmp     eax, 1
    jne     .fail
    cmp     dword [gun_reload], 30
    jne     .fail
    cmp     dword [gun_reload_total], 30
    jne     .fail
    mov     dword [rpg_stats + STAT_RELOAD_SPEED * 4], 15
    START_RELOAD PISTOL, 0, PISTOL_ROUND, 20
    cmp     dword [gun_reload], 52      ; (6000 + 57) / 115
    jne     .fail
    mov     dword [rpg_stats + STAT_RELOAD_SPEED * 4], 8
    START_RELOAD PISTOL, 0, PISTOL_ROUND, 20
    cmp     dword [gun_reload], 56      ; 6054 / 108 = 56.06: the quotient is rounded, not cut
    jne     .fail
    mov     dword [rpg_stats + STAT_RELOAD_SPEED * 4], 1000
    START_RELOAD PISTOL, 0, PISTOL_ROUND, 20
    cmp     dword [gun_reload], 10      ; 5.9 steps, but a reload never takes less than 10
    jne     .fail
    mov     dword [rpg_stats + STAT_RELOAD_SPEED * 4], 0
    START_RELOAD PISTOL, 0, PISTOL_ROUND, 20
    cmp     dword [gun_reload], 60
    jne     .fail
    ; ---- a firearm that carries attachments but no rounds is empty: the click is dry, and starts a reload
    call    gun_reset
    call    arrows_clear
    mov     dword [HELD], STK(PISTOL, 1, ATT_SCOPE | ATT_EXTMAG)
    mov     dword [HELD + 4], STK(PISTOL_ROUND, 5, 0)
    call    fire
    test    eax, eax
    jnz     .fail
    mov     edi, PROJ_BULLET
    call    live_of_kind
    test    eax, eax
    jnz     .fail
    cmp     dword [gun_reload], 0
    je      .fail
    cmp     dword [HELD], STK(PISTOL, 1, ATT_SCOPE | ATT_EXTMAG)
    jne     .fail
    ; ---- the magazine counts rounds in the low byte only: 8 rounds under an extended magazine are not full
    START_RELOAD PISTOL, ATT_EXTMAG | 8, PISTOL_ROUND, 20
    cmp     eax, 1
    jne     .fail
    START_RELOAD PISTOL, ATT_EXTMAG | 12, PISTOL_ROUND, 20
    test    eax, eax
    jnz     .fail                       ; 12 of 12
    START_RELOAD PISTOL, ATT_SCOPE | 8, PISTOL_ROUND, 20
    test    eax, eax
    jnz     .fail                       ; 8 of 8: a scope adds no rounds
    ; ---- a reload keeps the attachments; ARROW_SAVE leaves the rounds in the inventory
    START_RELOAD PISTOL, ATT_SCOPE, PISTOL_ROUND, 8
    cmp     eax, 1
    jne     .fail
    mov     edi, 60
    call    steps
    cmp     dword [HELD], STK(PISTOL, 1, ATT_SCOPE | 8)
    jne     .fail
    cmp     dword [HELD + 4], 0         ; all 8 rounds used up
    jne     .fail
    mov     dword [rpg_stats + STAT_ARROW_SAVE * 4], 100
    START_RELOAD PISTOL, ATT_SCOPE, PISTOL_ROUND, 8
    mov     edi, 60
    call    steps
    cmp     dword [HELD], STK(PISTOL, 1, ATT_SCOPE | 8)
    jne     .fail
    cmp     dword [HELD + 4], STK(PISTOL_ROUND, 8, 0) ; every round saved: still all 8
    jne     .fail
    mov     dword [rpg_stats + STAT_ARROW_SAVE * 4], 0
    mov     dword [game_mode], MODE_CREATIVE
    START_RELOAD PISTOL, ATT_EXTMAG, 0, 0
    cmp     eax, 1
    jne     .fail
    mov     edi, 60
    call    steps
    cmp     dword [HELD], STK(PISTOL, 1, ATT_EXTMAG | 12) ; Creative fills the extended magazine
    jne     .fail
    mov     dword [game_mode], MODE_SURVIVAL
    ; ---- Fan the Hammer: no round is spent and the cooldown is halved (at least 2)
    mov     dword [combat_fanhammer_t], 100
    SHOT    PISTOL, ATT_SCOPE | 3
    cmp     eax, 1
    jne     .fail
    cmp     dword [HELD], STK(PISTOL, 1, ATT_SCOPE | 3)
    jne     .fail
    cmp     dword [gun_cooldown], 7     ; 15 / 2
    jne     .fail
    SHOT    PISTOL, ATT_COMP | 3
    cmp     dword [gun_cooldown], 5     ; the Compensator's 11, halved
    jne     .fail
    mov     dword [combat_fanhammer_t], 0
    SHOT    PISTOL, ATT_SCOPE | 3
    cmp     dword [HELD], STK(PISTOL, 1, ATT_SCOPE | 2) ; now a round goes, the scope stays
    jne     .fail
    cmp     dword [gun_cooldown], 15
    jne     .fail
    SHOT    PISTOL, ATT_COMP | 3
    cmp     dword [gun_cooldown], 11    ; the Compensator: 25 % faster
    jne     .fail
    ; ---- Rifled Barrel: 30 % faster bullets, hitting a quarter harder (at least 1)
    SHOT0   PISTOL, ATT_RIFLED | 8
    cmp     eax, 1
    jne     .fail
    call    first_live
    cmp     dword [rax + ARROWENT.damage], 6
    jne     .fail
    mov     rdi, rax
    call    speed_of
    movss   xmm1, [k_117]
    call    close_to
    test    eax, eax
    jz      .fail
    SHOT0   PISTOL, 8
    call    first_live
    cmp     dword [rax + ARROWENT.damage], 5
    jne     .fail
    mov     rdi, rax
    call    speed_of
    movss   xmm1, [k_90]
    call    close_to
    test    eax, eax
    jz      .fail
    ; ---- spread: from the hip no pellet flies straight; Bullseye and an aimed Scope (game_aim >= 0.9)
    ; make all six straight; the Compensator halves the spread
    SHOT    SHOTGUN, 1
    STRAIGHT 0
    mov     dword [combat_bullseye_t], 100
    SHOT    SHOTGUN, 1
    STRAIGHT 6
    mov     dword [combat_bullseye_t], 0
    mov     dword [game_aim], __float32__(1.0)
    SHOT    SHOTGUN, ATT_SCOPE | 1
    STRAIGHT 6
    SHOT    SHOTGUN, 1                  ; aimed, but no scope
    STRAIGHT 0
    mov     dword [game_aim], __float32__(0.89)
    SHOT    SHOTGUN, ATT_SCOPE | 1      ; a scope, not aimed enough
    STRAIGHT 0
    mov     dword [game_aim], __float32__(0.9)
    SHOT    SHOTGUN, ATT_SCOPE | 1      ; exactly 0.9 counts as aimed
    STRAIGHT 6
    mov     dword [game_aim], __float32__(1.0)
    SHOT    PISTOL, ATT_SCOPE | 8       ; a scoped pistol, aimed: dead straight
    STRAIGHT 1
    SHOT    PISTOL, 8                   ; the same shot without the scope has its spread
    STRAIGHT 0
    mov     dword [game_aim], 0
    mov     edi, 1234
    call    rng_seed
    SHOT    SHOTGUN, 1
    call    vx_sum
    movss   [sum_plain], xmm0
    mov     edi, 1234
    call    rng_seed
    SHOT    SHOTGUN, ATT_COMP | 1       ; the same random numbers, half the sideways speed
    call    vx_sum
    movss   [sum_comp], xmm0
    movss   xmm0, [sum_comp]
    divss   xmm0, [sum_plain]
    comiss  xmm0, [k_0_48]
    jb      .fail
    comiss  xmm0, [k_0_52]
    ja      .fail
    ; ---- crits: CRIT_CHANCE 60, Bullseye +25 and an aimed Scope +15 make 100 %
    mov     dword [rpg_stats + STAT_CRIT_CHANCE * 4], 60
    mov     dword [combat_bullseye_t], 100
    mov     dword [game_aim], __float32__(1.0)
    mov     edi, 40
    mov     esi, ATT_SCOPE | 8
    call    crit_shots
    cmp     eax, 40
    jne     .fail
    mov     edi, 40
    mov     esi, 8                      ; Bullseye alone: 85 %
    call    crit_shots
    test    eax, eax
    jz      .fail
    cmp     eax, 40
    jae     .fail
    mov     dword [combat_bullseye_t], 0
    mov     edi, 40
    mov     esi, ATT_SCOPE | 8          ; the aimed Scope alone: 75 %
    call    crit_shots
    test    eax, eax
    jz      .fail
    cmp     eax, 40
    jae     .fail
    mov     dword [game_aim], 0
    mov     edi, 40
    mov     esi, ATT_SCOPE | 8          ; hip-fired the scope adds nothing: 60 %
    call    crit_shots
    test    eax, eax
    jz      .fail
    cmp     eax, 40
    jae     .fail
    mov     dword [rpg_stats + STAT_CRIT_CHANCE * 4], 0
    mov     edi, 40
    mov     esi, 8                      ; no chance: never
    call    crit_shots
    test    eax, eax
    jnz     .fail
    ; ---- Deadshot: aimed shots (game_aim >= 0.9) always crit, shots from the hip never do
    mov     dword [rpg_keystones], 1 << KS_DEADSHOT
    mov     dword [rpg_stats + STAT_CRIT_CHANCE * 4], 100
    mov     edi, 10
    mov     esi, 8
    call    crit_shots
    test    eax, eax
    jnz     .fail                       ; from the hip, whatever the chance
    mov     dword [rpg_stats + STAT_CRIT_CHANCE * 4], 0
    mov     dword [game_aim], __float32__(0.89)
    mov     edi, 10
    mov     esi, 8
    call    crit_shots
    test    eax, eax
    jnz     .fail
    mov     dword [game_aim], __float32__(0.9)
    mov     edi, 10
    mov     esi, 8
    call    crit_shots
    cmp     eax, 10                     ; aimed: always, with no chance at all
    jne     .fail
    SHOT    SHOTGUN, 1
    mov     edi, AF_CRIT
    xor     esi, esi
    call    count_where
    cmp     eax, 6                      ; one roll for the shot: every pellet carries it
    jne     .fail
    SHOT    ROCKET_LAUNCHER, 1          ; a blast never crits
    cmp     eax, 1
    jne     .fail
    call    first_live
    cmp     dword [rax + ARROWENT.kind], PROJ_ROCKET
    jne     .fail
    cmp     dword [rax + ARROWENT.flags], 0
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    call    cleanup
    pop     rbp
    ret

; INDEX id, g: gun_index of that item
%macro INDEX 2
    mov     edi, %1
    call    gun_index
    cmp     eax, %2
    jne     .fail
%endmacro

; The revolver and the hunting rifle: the lookup (-1 for everything that is no firearm, the
; neighbouring ids included), their magazines, ammunition, one bullet of the table's damage with the
; table's cooldown, a hunting rifle bullet flying straight at 140 blocks per second, and the reloads.
test_new_guns_fire:
    push    rbp
    mov     rbp, rsp
    call    setup
    INDEX   PISTOL, 0
    INDEX   ROCKET_LAUNCHER, 4
    INDEX   REVOLVER, 5
    INDEX   HUNTING_RIFLE, 6
    INDEX   STAFF, -1
    INDEX   ROCKET, -1
    INDEX   PISTOL_ROUND, -1
    INDEX   SCOPE, -1
    INDEX   COMPENSATOR, -1
    INDEX   PISTOL - 1, -1
    INDEX   0, -1
    MAGAZINE REVOLVER, 0, 6
    MAGAZINE HUNTING_RIFLE, 0, 5
    mov     edi, REVOLVER
    call    gun_ammo
    cmp     eax, PISTOL_ROUND
    jne     .fail
    mov     edi, HUNTING_RIFLE
    call    gun_ammo
    cmp     eax, RIFLE_ROUND
    jne     .fail
    mov     edi, REVOLVER
    call    gun_automatic
    test    eax, eax
    jnz     .fail
    mov     edi, KALASHNIKOV
    call    gun_automatic
    cmp     eax, 1
    jne     .fail
    ; a loaded revolver: one bullet of damage 10, a cooldown of 18 steps, one round gone
    mov     dword [HELD], STK(REVOLVER, 1, 6)
    call    fire
    cmp     eax, 1
    jne     .fail
    mov     edi, PROJ_BULLET
    call    live_of_kind
    cmp     eax, 1
    jne     .fail
    call    first_live
    cmp     dword [rax + ARROWENT.damage], 10
    jne     .fail
    cmp     dword [gun_cooldown], 18
    jne     .fail
    cmp     dword [HELD], STK(REVOLVER, 1, 5)
    jne     .fail
    ; the hunting rifle: damage 22, cooldown 40, no spread, 140 blocks per second
    call    arrows_clear
    call    gun_reset
    mov     dword [HELD], STK(HUNTING_RIFLE, 1, 5)
    call    fire
    cmp     eax, 1
    jne     .fail
    call    first_live
    cmp     dword [rax + ARROWENT.damage], 22
    jne     .fail
    cmp     dword [rax + ARROWENT.vx], 0
    jne     .fail
    cmp     dword [rax + ARROWENT.vy], 0
    jne     .fail
    cmp     dword [rax + ARROWENT.vz], __float32__(-140.0)
    jne     .fail
    cmp     dword [gun_cooldown], 40
    jne     .fail
    ; the reloads: 75 and 120 steps, from the matching ammunition only
    START_RELOAD REVOLVER, 0, PISTOL_ROUND, 20
    cmp     eax, 1
    jne     .fail
    cmp     dword [gun_reload], 75
    jne     .fail
    mov     edi, 75
    call    steps
    cmp     dword [HELD], STK(REVOLVER, 1, 6)
    jne     .fail
    cmp     dword [HELD + 4], STK(PISTOL_ROUND, 14, 0)
    jne     .fail
    START_RELOAD HUNTING_RIFLE, 0, RIFLE_ROUND, 20
    cmp     eax, 1
    jne     .fail
    cmp     dword [gun_reload], 120
    jne     .fail
    mov     edi, 120
    call    steps
    cmp     dword [HELD], STK(HUNTING_RIFLE, 1, 5)
    jne     .fail
    cmp     dword [HELD + 4], STK(RIFLE_ROUND, 15, 0)
    jne     .fail
    START_RELOAD REVOLVER, 0, RIFLE_ROUND, 20
    test    eax, eax
    jnz     .fail                       ; the revolver takes pistol rounds only
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    call    cleanup
    pop     rbp
    ret

; blast_run(edi variant V_*, esi AF_* flags, edx GUN_DMG, ecx keystone mask): a fresh setup in Creative
; (the player is no target), the stat and the keystones poked, four zombies of 100 health (zomb[0..3])
; 1.5, 4, 12 and 7 blocks from (16.5, 16.5) on the floor (V_HIT_G adds zomb[4] right at that spot), then
; that variant's projectile (damage 12) is released over (16.5, 16.5) and flies its steps
blast_run:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    call    setup
    mov     dword [game_mode], MODE_CREATIVE
    mov     [rpg_stats + STAT_GUN_DMG * 4], r13d
    mov     [rpg_keystones], r14d
    xor     r15d, r15d
    mov     dword [rsp], 4              ; zombies to place
    cmp     ebx, V_HIT_G
    jne     .zombie
    mov     dword [rsp], 5
.zombie:
    mov     edi, MOB_ZOMBIE
    lea     rax, [zomb_x]
    movss   xmm0, [rax + r15*4]
    movss   xmm1, [k_11]
    lea     rax, [zomb_z]
    movss   xmm2, [rax + r15*4]
    call    mob_spawn
    test    eax, eax
    js      .out
    imul    eax, eax, MOB_size
    lea     rcx, [mobs]
    add     rax, rcx
    mov     dword [rax + MOB.health], 100
    mov     dword [rax + MOB.max_health], 100
    lea     rcx, [zomb]
    mov     [rcx + r15*8], rax
    inc     r15d
    cmp     r15d, [rsp]
    jb      .zombie
    lea     rax, [var_y]
    movss   xmm1, [rax + rbx*4]
    lea     rax, [var_vy]
    movss   xmm4, [rax + rbx*4]
    movss   xmm0, [k_16_5]
    movss   xmm2, [k_16_5]
    xorps   xmm3, xmm3
    xorps   xmm5, xmm5
    xor     edi, edi
    mov     esi, 12
    xor     edx, edx
    lea     rax, [var_kind]
    mov     ecx, [rax + rbx*4]
    mov     r8d, r12d
    call    arrows_spawn
    lea     rax, [var_steps]
    mov     r14d, [rax + rbx*4]
.fly:
    call    arrows_step
    dec     r14d
    jnz     .fly
.out:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; DAMAGE i: eax = 100 - the health of zombie i; STUN i: eax = its stun
%macro DAMAGE 1
    mov     rax, [zomb + (%1) * 8]
    mov     ecx, 100
    sub     ecx, [rax + MOB.health]
    mov     eax, ecx
%endmacro
%macro STUN 1
    mov     rax, [zomb + (%1) * 8]
    mov     eax, [rax + MOB.stun]
%endmacro

; RUN variant, flags, GUN_DMG, keystones: blast_run
%macro RUN 4
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    call    blast_run
%endmacro

; A powder grenade bursts into fire where it lands: the zombie 1.5 blocks away takes 12 scaled by
; 1 - 0.5 d / r and by the zombie's 50 % fire weakness (6..18) and burns; GUN_DMG and a crit raise
; it; the one 4 blocks away (r = 3) is left alone until Powder Keg widens the burst by half, the far
; ones never. A flashbang (AF_FLASH) hurts nobody and stuns those within 5 blocks. A rocket's blast
; hurts mobs within 2r by the gun family too (explode_mob_mult, back to 1.0 afterwards) and Powder
; Keg reaches the zombie 7 blocks away that 2r = 6 does not.
test_grenade_and_rocket_blasts:
    push    rbp
    mov     rbp, rsp
    RUN     V_DROP, 0, 0, 0
    mov     edi, PROJ_GRENADE
    call    live_of_kind
    test    eax, eax
    jnz     .fail                       ; it went off
    DAMAGE  0
    mov     [dmg_plain], eax
    cmp     eax, 6
    jb      .fail
    cmp     eax, 18
    ja      .fail
    mov     rax, [zomb]
    cmp     dword [rax + MOB.burn_t], 0
    jle     .fail                       ; a fire blast
    DAMAGE  1
    test    eax, eax
    jnz     .fail                       ; 4 blocks: outside the radius of 3
    DAMAGE  2
    test    eax, eax
    jnz     .fail
    DAMAGE  3
    test    eax, eax
    jnz     .fail
    RUN     V_DROP, 0, 100, 0     ; GUN_DMG 100: twice the damage
    DAMAGE  0
    add     eax, 2
    mov     ecx, [dmg_plain]
    add     ecx, ecx
    cmp     eax, ecx
    jb      .fail
    RUN     V_DROP, AF_CRIT, 0, 0
    DAMAGE  0
    cmp     eax, [dmg_plain]
    jbe     .fail                       ; a crit hits harder
    RUN     V_DROP, 0, 0, 1 << KS_POWDER_KEG
    DAMAGE  1
    test    eax, eax
    jz      .fail                       ; the burst reaches 4.5 blocks now
    DAMAGE  3
    test    eax, eax
    jnz     .fail                       ; but not 7
    RUN     V_DROP, AF_FLASH, 0, 0
    mov     edi, PROJ_GRENADE
    call    live_of_kind
    test    eax, eax
    jnz     .fail
    DAMAGE  0
    test    eax, eax
    jnz     .fail                       ; a flash does no damage
    DAMAGE  1
    test    eax, eax
    jnz     .fail
    STUN    0
    test    eax, eax
    jle     .fail                       ; 1.5 blocks away: stunned
    STUN    1
    test    eax, eax
    jle     .fail                       ; 4 blocks away: stunned
    STUN    2
    test    eax, eax
    jnz     .fail                       ; 12 blocks away: not
    ; a grenade lobbed upwards goes off where it is when its 2 seconds are up, and not before
    RUN     V_LOB_EARLY, 0, 0, 0
    mov     edi, PROJ_GRENADE
    call    live_of_kind
    cmp     eax, 1
    jne     .fail                       ; 100 steps: still flying
    DAMAGE  0
    test    eax, eax
    jnz     .fail
    RUN     V_LOB, 0, 0, 0
    mov     edi, PROJ_GRENADE
    call    live_of_kind
    test    eax, eax
    jnz     .fail
    DAMAGE  0
    test    eax, eax
    jz      .fail                       ; it burst in the air and the zombie beside the spot burned
    mov     rax, [zomb]
    cmp     dword [rax + MOB.burn_t], 0
    jle     .fail
    ; a grenade that hits a zombie goes off on it: the neighbour 1.5 blocks away burns as well
    RUN     V_HIT_G, 0, 0, 0
    mov     edi, PROJ_GRENADE
    call    live_of_kind
    test    eax, eax
    jnz     .fail
    DAMAGE  4
    cmp     eax, 6
    jb      .fail
    DAMAGE  0
    test    eax, eax
    jz      .fail
    ; the rocket
    RUN     V_DIVE, 0, 0, 0
    mov     edi, PROJ_ROCKET
    call    live_of_kind
    test    eax, eax
    jnz     .fail
    cmp     dword [explode_mob_mult], __float32__(1.0)
    jne     .fail                       ; the blast put the factor back
    DAMAGE  0
    mov     [dmg_plain], eax
    cmp     eax, 10
    jb      .fail
    cmp     eax, 24
    ja      .fail
    DAMAGE  1
    test    eax, eax
    jz      .fail                       ; within 2r = 6
    DAMAGE  3
    test    eax, eax
    jnz     .fail                       ; 7 blocks: out
    RUN     V_DIVE, 0, 100, 0      ; GUN_DMG 100: the blast hurts mobs twice as much
    cmp     dword [explode_mob_mult], __float32__(1.0)
    jne     .fail
    DAMAGE  0
    add     eax, 2
    mov     ecx, [dmg_plain]
    add     ecx, ecx
    cmp     eax, ecx
    jb      .fail
    RUN     V_DIVE, 0, 0, 1 << KS_POWDER_KEG
    DAMAGE  3
    test    eax, eax
    jz      .fail                       ; Powder Keg: 2r = 9 reaches the zombie 7 blocks away
    DAMAGE  2
    test    eax, eax
    jnz     .fail                       ; 12 blocks is out of reach still
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    call    cleanup
    pop     rbp
    ret
