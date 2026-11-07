; test_guns.asm - firearms: reloading, firing, pellets, bullets and rockets in flight.
%include "common.inc"
default rel

global test_gun_reload_fills_magazine, test_gun_fire_cooldown_and_dry
global test_shotgun_spawns_six_pellets, test_bullet_hits_mob_and_stops
global test_rocket_explodes_on_impact, test_rifle_kills_zombie_point_blank
global test_aimed_shotgun_has_no_spread

extern gun_reset, gun_reload_start, gun_step, gun_fire, gun_reload, gun_cooldown
extern arrows, arrows_clear, arrows_spawn, arrows_step
extern inv, inv_sel, inv_clear, game_mode, settings, game_time
extern mobs, mobs_clear, mob_spawn, mob_count_type, rng_seed, tnt_clear, drops_clear
extern world_clear, world_set, world_get, survival_reset

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

section .text

; setup(): empty world with a STONE floor at y = 10 (x, z 0..31), Survival at Normal
; difficulty, nothing in flight, no mobs, an empty inventory with slot 0 selected
setup:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
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
    sub     rsp, 8
    xorps   xmm3, xmm3
    xorps   xmm4, xmm4
    xor     edi, edi
    xor     edx, edx
    mov     ecx, PROJ_BULLET
    xor     r8d, r8d
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
