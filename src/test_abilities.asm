; test_abilities.asm - the class abilities: cost, cooldown and unlock rules (and the charge and war
; cry), a fireball that explodes without breaking anything, blink stopping at walls, the volley
; and the arrow rain.
%include "common.inc"
default rel

global test_ability_cost_cooldown_and_unlock, test_fireball_explodes_without_breaking
global test_blink_stops_before_wall, test_volley_and_arrow_rain_spawn

extern abilities_cd, abilities_cd_total, abilities_reset, abilities_step, abilities_use
extern arrows, arrows_clear, arrows_step
extern mobs, mobs_clear, mob_spawn
extern fx_clear, fx_count
extern tnt_clear, drops_clear, inv_clear, inv_add, inv_count, inv_sel
extern player, body_init, player_eye, player_forward, rng_seed
extern world_clear, world_set, world_get, world_is_solid
extern game_mode, game_time, settings, surv, survival_reset
extern rpg_state, rpg_stats, rpg_recompute, rpg_reset
extern combat_mana, combat_stamina, combat_reset
extern combat_warcry_t

section .rodata
align 4
k_abs:    dd 0x7FFFFFFF
k_eps:    dd 0.01
k_half_w: dd 0.3
k_height: dd 1.8
k_speed:  dd 4.317
k_11:     dd 11.0
k_15_5:   dd 15.5
k_16_5:   dd 16.5
k_17:     dd 17.0
k_17_5:   dd 17.5
k_12_5:   dd 12.5
k_8_5:    dd 8.5
k_90:     dd 90.0
k_45:     dd 45.0
k_one:    dd 1.0
k_m1:     dd -1.0
k_lo_x:   dd 12.4                       ; arrow rain: 16.5 +- 4 around the target
k_hi_x:   dd 20.6
k_lo_z:   dd 10.4                       ; 14.5 +- 4
k_hi_z:   dd 18.6
k_5:      dd 5.0

section .text

; SETF mem, float literal
%macro SETF 2
    mov     dword %1, __float32__(%2)
%endmacro

; EXPECT_NEAR float mem operand, value: fail unless |mem - value| < 0.01
%macro EXPECT_NEAR 2
    section .rodata
    align 4
%%v: dd %2
    section .text
    movss   xmm0, %1
    movss   xmm1, [%%v]
    call    close_to
    test    eax, eax
    jz      .fail
%endmacro

; EXPECT_BLOCK x, y, z, id: fail unless the cell holds that block
%macro EXPECT_BLOCK 4
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    call    world_get
    cmp     eax, %4
    jne     .fail
%endmacro

; FILL x0, y0, z0, x1, y1, z1, block: every cell of the box becomes that block
%macro FILL 7
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    mov     r8d, %5
    mov     r9d, %6
    mov     r10d, %7
    call    fill_box
%endmacro

; close_to(xmm0 a, xmm1 b) -> eax 1 when |a - b| < 0.01
close_to:
    subss   xmm0, xmm1
    movss   xmm1, [k_abs]
    andps   xmm1, xmm0
    xor     eax, eax
    comiss  xmm1, [k_eps]
    setb    al
    ret

; fill_box(edi x0, esi y0, edx z0, ecx x1, r8d y1, r9d z1, r10d block): the box, bounds inclusive
; r12d, r13d, r14d = the cell, r15d = block; frame: the six bounds
fill_box:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40
    mov     [rsp], edi
    mov     [rsp + 4], esi
    mov     [rsp + 8], edx
    mov     [rsp + 12], ecx
    mov     [rsp + 16], r8d
    mov     [rsp + 20], r9d
    mov     r15d, r10d
    mov     r14d, [rsp + 8]
.z:
    mov     r13d, [rsp + 4]
.y:
    mov     r12d, [rsp]
.x:
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, r15d
    call    world_set
    inc     r12d
    cmp     r12d, [rsp + 12]
    jle     .x
    inc     r13d
    cmp     r13d, [rsp + 16]
    jle     .y
    inc     r14d
    cmp     r14d, [rsp + 20]
    jle     .z
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; fixture(): the state every test here starts from (after world_clear): rng seed 1234, no mobs,
; arrows, TNT, drops, particles or inventory, no class, no cooldowns, Survival at Normal difficulty,
; early morning, a fresh survival state, STONE floor at y = 10 for x, z in 0..31, the player
; standing on it at (16.5, 11, 16.5)
fixture:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     edi, 1234
    call    rng_seed
    call    mobs_clear
    call    arrows_clear
    call    tnt_clear
    call    drops_clear
    call    inv_clear
    call    fx_clear
    call    abilities_reset
    call    rpg_reset
    call    combat_reset
    mov     dword [inv_sel], 0
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    mov     dword [game_time], NEW_WORLD_TIME
    call    survival_reset
    xor     r12d, r12d                  ; z
.z:
    xor     ebx, ebx                    ; x
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
    lea     rdi, [player]
    movss   xmm0, [k_half_w]
    movss   xmm1, [k_height]
    movss   xmm2, [k_speed]
    call    body_init
    movss   xmm0, [k_16_5]
    movss   [player + BODY.x], xmm0
    movss   [player + BODY.z], xmm0
    movss   xmm0, [k_11]
    movss   [player + BODY.y], xmm0
    pop     r12
    pop     rbx
    pop     rbp
    ret

; cleanup(): leave nothing behind: no mobs, arrows, TNT, drops, particles, inventory, cooldowns,
; class or combat state
cleanup:
    sub     rsp, 8
    call    mobs_clear
    call    arrows_clear
    call    tnt_clear
    call    drops_clear
    call    inv_clear
    call    fx_clear
    call    abilities_reset
    call    rpg_reset
    call    combat_reset
    add     rsp, 8
    ret

; set_class(edi class, esi level): the class and level in rpg_state, the stats recomputed, and
; crits switched off so damage is exact
set_class:
    lea     rax, [rpg_state]
    mov     [rax + RPGSAVE.class], dil
    mov     [rax + RPGSAVE.level], sil
    sub     rsp, 8
    call    rpg_recompute
    mov     dword [rpg_stats + STAT_CRIT_CHANCE * 4], 0
    add     rsp, 8
    ret

; view(rdi buf float[6], xmm0 yaw, xmm1 pitch): aims the player; buf = eye[3], dir[3] as the game
; hands them to abilities_use
view:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdi
    movss   [player + BODY.yaw], xmm0
    movss   [player + BODY.pitch], xmm1
    mov     rdi, rbx
    call    player_eye
    lea     rdi, [rbx + 12]
    call    player_forward
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; count_live() -> eax live arrows
count_live:
    lea     rcx, [arrows]
    xor     eax, eax
    mov     edx, MAX_ARROWS
.l:
    cmp     dword [rcx + ARROWENT.live], 0
    setne   sil
    movzx   esi, sil
    add     eax, esi
    add     rcx, ARROWENT_size
    dec     edx
    jnz     .l
    ret

; Warrior: Charge costs 30 stamina, starts a 360 step cooldown, shoves the player along -z at
; 22 b/s and strikes the zombie in its way once (round(6 * 1.1) = 7, stunned 30 steps); a recast
; during the cooldown and the locked war cry cost nothing; COOLDOWN_RED shortens the cooldown;
; the unlocked war cry stuns hostile mobs within 6 blocks only. Mage with 10 mana: no Fireball
; (nothing paid, nothing fired); with 100 it fires one (75 mana left, 180 steps, damage 9).
; rbx = the zombie; frame: eye[3] @0, dir[3] @12
test_ability_cost_cooldown_and_unlock:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 40
    call    world_clear
    call    fixture
    mov     edi, CLASS_WARRIOR
    mov     esi, 5
    call    set_class
    SETF    [combat_stamina], 100.0
    lea     rdi, [rsp]
    xorps   xmm0, xmm0                  ; yaw 0: facing -z
    xorps   xmm1, xmm1
    call    view
    mov     edi, MOB_ZOMBIE             ; one block ahead, in the way of the charge
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_15_5]
    call    mob_spawn
    test    eax, eax
    js      .fail
    imul    ebx, eax, MOB_size
    lea     rax, [mobs]
    add     rbx, rax
    xor     edi, edi                    ; ---- Charge
    lea     rsi, [rsp]
    lea     rdx, [rsp + 12]
    call    abilities_use
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_stamina], 70.0
    cmp     dword [abilities_cd], 360
    jne     .fail
    cmp     dword [abilities_cd_total], 360
    jne     .fail
    EXPECT_NEAR [player + BODY.kbx], 0.0
    EXPECT_NEAR [player + BODY.kbz], -22.0
    xor     edi, edi                    ; a recast waits for the cooldown
    lea     rsi, [rsp]
    lea     rdx, [rsp + 12]
    call    abilities_use
    test    eax, eax
    jnz     .fail
    EXPECT_NEAR [combat_stamina], 70.0
    mov     edi, 1                      ; the war cry is not bought yet
    lea     rsi, [rsp]
    lea     rdx, [rsp + 12]
    call    abilities_use
    test    eax, eax
    jnz     .fail
    EXPECT_NEAR [combat_stamina], 70.0
    cmp     dword [abilities_cd + 4], 0
    jne     .fail
    call    abilities_step              ; the charge reaches the zombie
    cmp     dword [rbx + MOB.health], 13
    jne     .fail
    cmp     dword [rbx + MOB.stun], 30
    jne     .fail
    call    abilities_step              ; and strikes it once
    cmp     dword [rbx + MOB.health], 13
    jne     .fail
    cmp     dword [abilities_cd], 358
    jne     .fail
    call    mobs_clear                  ; ---- COOLDOWN_RED 10 %: 6 s * 60 * 90 / 100 = 324
    call    abilities_reset
    SETF    [combat_stamina], 100.0
    mov     dword [rpg_stats + STAT_COOLDOWN_RED * 4], 10
    xor     edi, edi
    lea     rsi, [rsp]
    lea     rdx, [rsp + 12]
    call    abilities_use
    cmp     eax, 1
    jne     .fail
    cmp     dword [abilities_cd], 324
    jne     .fail
    cmp     dword [abilities_cd_total], 324
    jne     .fail
    call    abilities_reset             ; ---- War Cry, bought: stuns within 6 blocks, not beyond
    call    rpg_recompute
    mov     dword [rpg_stats + STAT_CRIT_CHANCE * 4], 0
    mov     byte [rpg_state + RPGSAVE.ranks_v4 + 5], 1
    SETF    [combat_stamina], 100.0
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_12_5]              ; 4 blocks ahead
    call    mob_spawn
    test    eax, eax
    js      .fail
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_8_5]               ; 8 blocks ahead
    call    mob_spawn
    test    eax, eax
    js      .fail
    mov     edi, 1
    lea     rsi, [rsp]
    lea     rdx, [rsp + 12]
    call    abilities_use
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_stamina], 60.0
    cmp     dword [combat_warcry_t], 480
    jne     .fail
    cmp     dword [abilities_cd + 4], 1200
    jne     .fail
    cmp     dword [mobs + MOB.stun], 20
    jne     .fail
    cmp     dword [mobs + MOB_size + MOB.stun], 0
    jne     .fail
    call    mobs_clear                  ; ---- Mage: short of mana
    call    abilities_reset
    mov     edi, CLASS_MAGE
    mov     esi, 5
    call    set_class
    SETF    [combat_mana], 10.0
    xor     edi, edi
    lea     rsi, [rsp]
    lea     rdx, [rsp + 12]
    call    abilities_use
    test    eax, eax
    jnz     .fail
    EXPECT_NEAR [combat_mana], 10.0
    cmp     dword [abilities_cd], 0
    jne     .fail
    cmp     dword [arrows + ARROWENT.live], 0
    jne     .fail
    SETF    [combat_mana], 100.0        ; enough: a Fireball flies
    xor     edi, edi
    lea     rsi, [rsp]
    lea     rdx, [rsp + 12]
    call    abilities_use
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_mana], 75.0
    cmp     dword [abilities_cd], 180
    jne     .fail
    cmp     dword [arrows + ARROWENT.live], 1
    jne     .fail
    cmp     dword [arrows + ARROWENT.kind], PROJ_FIREBALL
    jne     .fail
    cmp     dword [arrows + ARROWENT.owner], 0
    jne     .fail
    cmp     dword [arrows + ARROWENT.pickup], 0
    jne     .fail
    cmp     dword [arrows + ARROWENT.flags], 0
    jne     .fail
    cmp     dword [arrows + ARROWENT.damage], 9 ; round(8 * 1.1)
    jne     .fail
    EXPECT_NEAR [arrows + ARROWENT.z], 16.0
    EXPECT_NEAR [arrows + ARROWENT.vz], -28.0
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 40
    pop     rbx
    pop     rbp
    ret

; A Mage's Fireball (damage 9, radius 2.5) flies +x into a stone wall with a pig standing in front
; of it, beside the line of flight: the pig takes ceil(9 * (1 - 0.5 d / 2.5)) = 7 from the blast
; (d = 1.35 to its middle), while the wall, a floor cell the blast reaches and the player's health
; (he stands 3.5 blocks away, inside the 2r a TNT blast would hurt) are untouched.
; rbx = the pig, r12d = steps left; frame: eye[3] @0, dir[3] @12
test_fireball_explodes_without_breaking:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 48
    call    world_clear
    call    fixture
    mov     edi, CLASS_MAGE
    mov     esi, 5
    call    set_class
    SETF    [combat_mana], 100.0
    mov     eax, [surv + SURVIVAL.health]       ; whatever the class leaves him with (the real
    mov     [rsp + 24], eax                     ; rpg_recompute clamps it to the Mage's 18)
    movss   xmm0, [k_14_5]
    movss   [player + BODY.x], xmm0
    lea     rdi, [rsp]
    movss   xmm0, [k_90]                ; facing +x
    xorps   xmm1, xmm1
    call    view
    FILL    18, 11, 14, 18, 14, 18, STONE
    mov     edi, MOB_PIG
    movss   xmm0, [k_17_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_17]
    call    mob_spawn
    test    eax, eax
    js      .fail
    imul    ebx, eax, MOB_size
    lea     rax, [mobs]
    add     rbx, rax
    xor     edi, edi
    lea     rsi, [rsp]
    lea     rdx, [rsp + 12]
    call    abilities_use
    cmp     eax, 1
    jne     .fail
    mov     r12d, 40
.fly:
    call    arrows_step
    dec     r12d
    jnz     .fly
    cmp     dword [arrows + ARROWENT.live], 0
    jne     .fail                       ; spent on the wall
    cmp     dword [rbx + MOB.health], 3 ; 10 - 7
    jne     .fail
    call    fx_count
    test    eax, eax
    jz      .fail                       ; the blast was drawn
    EXPECT_BLOCK 18, 12, 16, STONE      ; the wall where it hit
    EXPECT_BLOCK 18, 11, 14, STONE
    EXPECT_BLOCK 18, 14, 18, STONE
    EXPECT_BLOCK 17, 10, 16, STONE      ; the floor, 2.2 from the blast centre
    mov     eax, [rsp + 24]
    cmp     [surv + SURVIVAL.health], eax
    jne     .fail
    EXPECT_NEAR [player + BODY.kbx], 0.0
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 48
    pop     r12
    pop     rbx
    pop     rbp
    ret

; A Mage with Blink (slot 1, node 5) facing +x: a stone wall right in front leaves no room (less
; than a block): the cast fails and costs nothing. With the wall 3.5 blocks away the march stops
; at 3.0 blocks (the box would touch the wall at 3.25): the player is there, upright, motion and
; fall forgotten, 20 mana and 300 steps spent, magic sparks at both ends.
; frame: eye[3] @0, dir[3] @12
test_blink_stops_before_wall:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32
    call    world_clear
    call    fixture
    mov     edi, CLASS_MAGE
    mov     esi, 5
    call    set_class
    mov     byte [rpg_state + RPGSAVE.ranks_v4 + 5], 1
    SETF    [combat_mana], 100.0
    lea     rdi, [rsp]
    movss   xmm0, [k_90]                ; facing +x
    xorps   xmm1, xmm1
    call    view
    FILL    17, 11, 15, 17, 13, 17, STONE   ; ---- a wall 0.5 ahead: nowhere to go
    mov     edi, 1
    lea     rsi, [rsp]
    lea     rdx, [rsp + 12]
    call    abilities_use
    test    eax, eax
    jnz     .fail
    EXPECT_NEAR [combat_mana], 100.0
    cmp     dword [abilities_cd + 4], 0
    jne     .fail
    EXPECT_NEAR [player + BODY.x], 16.5
    call    fx_count
    test    eax, eax
    jnz     .fail
    FILL    17, 11, 15, 17, 13, 17, AIR     ; ---- the wall 3.5 ahead
    FILL    20, 11, 15, 20, 13, 17, STONE
    SETF    [player + BODY.vy], -5.0
    SETF    [player + BODY.kbx], 3.0
    SETF    [player + BODY.fall], 5.0
    mov     edi, 1
    lea     rsi, [rsp]
    lea     rdx, [rsp + 12]
    call    abilities_use
    cmp     eax, 1
    jne     .fail
    movss   xmm0, [player + BODY.x]
    comiss  xmm0, [k_18_5]
    jbe     .fail                       ; moved more than 2 blocks
    comiss  xmm0, [k_20]
    jae     .fail                       ; and not into the wall
    EXPECT_NEAR [player + BODY.x], 19.5
    EXPECT_NEAR [player + BODY.y], 11.0
    EXPECT_NEAR [player + BODY.z], 16.5
    EXPECT_NEAR [player + BODY.vy], 0.0
    EXPECT_NEAR [player + BODY.kbx], 0.0
    EXPECT_NEAR [player + BODY.fall], 0.0
    EXPECT_NEAR [combat_mana], 80.0
    cmp     dword [abilities_cd + 4], 300
    jne     .fail
    mov     edi, 19                     ; his box is in free air and the wall still stands
    mov     esi, 11
    mov     edx, 16
    call    world_is_solid
    test    eax, eax
    jnz     .fail
    mov     edi, 19
    mov     esi, 12
    mov     edx, 16
    call    world_is_solid
    test    eax, eax
    jnz     .fail
    mov     edi, 20
    mov     esi, 11
    mov     edx, 16
    call    world_is_solid
    test    eax, eax
    jz      .fail
    call    fx_count
    cmp     eax, 40                     ; 20 sparks at each end
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     [rsp + 24], eax
    call    cleanup
    mov     eax, [rsp + 24]
    add     rsp, 32
    pop     rbp
    ret

; An Archer's Volley: 30 stamina, five live arrows (damage round(6 * 1.15) = 7) fanned -20, -10, 0,
; 10, 20 degrees around -z at 40 b/s, the ten arrows in the quiver all still there. Arrow Rain
; (slot 2, node 7), aimed 45 degrees down at the floor: 60 stamina and a 1800 step cooldown; after
; 120 steps all 24 arrows exist (29 in all), each above the target (16.5, 10.5, 14.5) at
; y = 24.5, within +-4 of it, falling straight down at 35 b/s.
; rbx = arrow, r12d = counter; frame: eye[3] @0, dir[3] @12
test_volley_and_arrow_rain_spawn:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 48
    call    world_clear
    call    fixture
    mov     edi, CLASS_ARCHER
    mov     esi, 5
    call    set_class
    mov     byte [rpg_state + RPGSAVE.ranks_v4 + 7], 1
    SETF    [combat_stamina], 100.0
    mov     edi, ARROW
    mov     esi, 10
    call    inv_add
    lea     rdi, [rsp]
    xorps   xmm0, xmm0                  ; facing -z, level
    xorps   xmm1, xmm1
    call    view
    xor     edi, edi                    ; ---- Volley
    lea     rsi, [rsp]
    lea     rdx, [rsp + 12]
    call    abilities_use
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_stamina], 70.0
    call    count_live
    cmp     eax, 5
    jne     .fail
    mov     edi, ARROW
    call    inv_count
    cmp     eax, 10
    jne     .fail                       ; none was taken from the quiver
    EXPECT_NEAR [arrows + ARROWENT.vx], -13.68
    EXPECT_NEAR [arrows + ARROWENT.vz], -37.59
    EXPECT_NEAR [arrows + ARROWENT_size + ARROWENT.vx], -6.95
    EXPECT_NEAR [arrows + ARROWENT_size * 2 + ARROWENT.vx], 0.0
    EXPECT_NEAR [arrows + ARROWENT_size * 2 + ARROWENT.vz], -40.0
    EXPECT_NEAR [arrows + ARROWENT_size * 2 + ARROWENT.z], 16.1
    EXPECT_NEAR [arrows + ARROWENT_size * 3 + ARROWENT.vx], 6.95
    EXPECT_NEAR [arrows + ARROWENT_size * 4 + ARROWENT.vx], 13.68
    EXPECT_NEAR [arrows + ARROWENT_size * 4 + ARROWENT.vz], -37.59
    xor     ebx, ebx
.volley:
    imul    eax, ebx, ARROWENT_size
    lea     rcx, [arrows]
    add     rcx, rax
    cmp     dword [rcx + ARROWENT.kind], PROJ_ARROW
    jne     .fail
    cmp     dword [rcx + ARROWENT.owner], 0
    jne     .fail
    cmp     dword [rcx + ARROWENT.pickup], 0
    jne     .fail
    cmp     dword [rcx + ARROWENT.flags], 0
    jne     .fail
    cmp     dword [rcx + ARROWENT.damage], 7
    jne     .fail
    inc     ebx
    cmp     ebx, 5
    jb      .volley
    lea     rdi, [rsp]                  ; ---- Arrow Rain, 45 degrees down onto the floor
    xorps   xmm0, xmm0
    movss   xmm1, [k_45]
    call    view
    mov     edi, 2
    lea     rsi, [rsp]
    lea     rdx, [rsp + 12]
    call    abilities_use
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_stamina], 10.0
    cmp     dword [abilities_cd + 8], 1800
    jne     .fail
    mov     r12d, 120
.rain:
    call    abilities_step
    dec     r12d
    jnz     .rain
    call    count_live
    cmp     eax, 29
    jne     .fail                       ; 5 + 24, none more
    cmp     dword [abilities_cd], 240
    jne     .fail
    cmp     dword [abilities_cd + 8], 1680
    jne     .fail
    mov     ebx, 5
.drop:
    imul    eax, ebx, ARROWENT_size
    lea     rcx, [arrows]
    add     rcx, rax
    cmp     dword [rcx + ARROWENT.live], 0
    je      .fail
    cmp     dword [rcx + ARROWENT.kind], PROJ_ARROW
    jne     .fail
    cmp     dword [rcx + ARROWENT.owner], 0
    jne     .fail
    cmp     dword [rcx + ARROWENT.pickup], 0
    jne     .fail
    cmp     dword [rcx + ARROWENT.damage], 7
    jne     .fail
    movss   xmm0, [rcx + ARROWENT.y]
    movss   xmm1, [k_24_5]
    call    close_to
    test    eax, eax
    jz      .fail
    lea     rcx, [arrows]
    imul    eax, ebx, ARROWENT_size
    add     rcx, rax
    movss   xmm0, [rcx + ARROWENT.vy]
    movss   xmm1, [k_m35]
    call    close_to
    test    eax, eax
    jz      .fail
    lea     rcx, [arrows]
    imul    eax, ebx, ARROWENT_size
    add     rcx, rax
    cmp     dword [rcx + ARROWENT.vx], 0
    jne     .fail
    cmp     dword [rcx + ARROWENT.vz], 0
    jne     .fail
    movss   xmm0, [rcx + ARROWENT.x]
    comiss  xmm0, [k_lo_x]
    jb      .fail
    comiss  xmm0, [k_hi_x]
    ja      .fail
    movss   xmm0, [rcx + ARROWENT.z]
    comiss  xmm0, [k_lo_z]
    jb      .fail
    comiss  xmm0, [k_hi_z]
    ja      .fail
    inc     ebx
    cmp     ebx, 29
    jb      .drop
    cmp     dword [arrows + ARROWENT_size * 29 + ARROWENT.live], 0
    jne     .fail
    movss   xmm0, [arrows + ARROWENT_size * 5 + ARROWENT.x]
    subss   xmm0, [arrows + ARROWENT_size * 6 + ARROWENT.x]
    movss   xmm1, [k_abs]
    andps   xmm1, xmm0
    comiss  xmm1, [k_eps]
    jbe     .fail                       ; they are scattered, not stacked
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 48
    pop     r12
    pop     rbx
    pop     rbp
    ret

section .rodata
align 4
k_14_5:   dd 14.5
k_18_5:   dd 18.5
k_20:     dd 20.0
k_24_5:   dd 24.5
k_m35:    dd -35.0
