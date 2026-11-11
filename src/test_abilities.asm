; test_abilities.asm - the abilities of the skill web: cost, cooldown and bar rules (and the charge
; and war cry), the volley and the arrow rain; then the slot 3 abilities (ground slam, hunter's
; mark, fan of knives), the keystones that reach the abilities (Blood Magic, Barrage, Shadow Dance),
; AREA, the staff bolt and the binding of the ability bar; last the four Marksman abilities (the
; grenades they lob, the two timers they set) and the burst of a flashbang. The Mage's magic is the
; runes of spells.asm (test_spells.asm).
%include "common.inc"
default rel

global test_ability_cost_cooldown_and_unlock
global test_volley_and_arrow_rain_spawn, test_new_abilities
global test_ability_bar_binding, test_marksman_abilities, test_planes_view

extern abilities_cd, abilities_cd_total, abilities_bolt_cd, abilities_reset, abilities_step
extern abilities_use, abilities_staff_bolt, ab_flash_at
extern arrows, arrows_clear, arrows_step
extern mobs, mobs_clear, mob_spawn
extern fx_clear, fx_count, fx_step, fx_particles, fx_shake
extern tnt_clear, drops_clear, inv, inv_clear, inv_add, inv_count, inv_sel
extern player, body_init, player_eye, player_forward, rng_seed
extern world_clear, world_set, world_get, world_is_solid
extern game_mode, game_time, settings, surv, survival_reset
extern rpg_state, rpg_stats, rpg_recompute, rpg_reset, rpg_ext, rpg_keystones
extern rpg_spend, rpg_bar_set, rpg_bar_ability
extern gear_powers
extern combat_mana, combat_stamina, combat_reset
extern combat_warcry_t, combat_stealth_t, combat_crit_next_t, combat_bullseye_t, combat_fanhammer_t
extern combat_step
extern game_frame, frame_input, input_captured, game_open_screen, game_heavy_s, game_break_progress, brk_y
extern planes, plane_riding, plane_view, planes_clear, planes_board, boats, boat_riding, boats_clear

; ability ids, ABIL_BASE(archetype) + slot: what the ability bar holds and the index of abilities_cd
%define AB_CHARGE       0
%define AB_WARCRY       1
%define AB_WHIRL        2
%define AB_SLAM         3
%define AB_VOLLEY       4
%define AB_EXPLARROW    5
%define AB_RAIN         6
%define AB_MARK         7
%define AB_SMOKE        9
%define AB_KNIVES       11

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

; MOBF(n, field): that field of mob slot n (the mobs of a scene land in slots 0, 1, 2.. in the order
; they are spawned)
%define MOBF(n, f) [mobs + (n) * MOB_size + (f)]

; SPAWN type, x, y, z (float constants): rax = the new mob; fails the test when none fits
%macro SPAWN 4
    mov     edi, %1
    movss   xmm0, [%2]
    movss   xmm1, [%3]
    movss   xmm2, [%4]
    call    spawn
    test    rax, rax
    jz      .fail
%endmacro

; SAVE_HEALTH mob, offset: remember the mob's health at [rsp + offset]
%macro SAVE_HEALTH 2
    mov     eax, MOBF(%1, MOB.health)
    mov     [rsp + %2], eax
%endmacro

; EXPECT_LOST mob, offset, n: fail unless the mob lost exactly n health since SAVE_HEALTH
%macro EXPECT_LOST 3
    mov     eax, [rsp + %2]
    sub     eax, MOBF(%1, MOB.health)
    cmp     eax, %3
    jne     .fail
%endmacro

; CAST slot, buf: eax = abilities_use's answer for the view (eye[3], dir[3]) at [rsp + buf]
%macro CAST 2
    mov     edi, %1
    lea     rsi, [rsp + %2]
    lea     rdx, [rsp + %2 + 12]
    call    abilities_use
%endmacro

; BOLT buf: eax = abilities_staff_bolt's answer for the view at [rsp + buf]
%macro BOLT 1
    lea     rdi, [rsp + %1]
    lea     rsi, [rsp + %1 + 12]
    call    abilities_staff_bolt
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
; arrows, TNT, drops, particles or inventory, no skills, no cooldowns, Survival at Normal difficulty,
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
    mov     dword [rpg_keystones], 0
    mov     dword [gear_powers], 0
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
; skills or combat state
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
    mov     dword [rpg_keystones], 0
    mov     dword [gear_powers], 0
    add     rsp, 8
    ret

; set_path(edi archetype 1..5, esi level): a character of that level who took the path of the
; archetype and nothing else: rpg_reset, the level poked, every kit marked as given (so the spend
; gives no kit and wears no chestplate), rpg_spend of the path node (its ability lands in bar slot 0;
; the stats are recomputed with the archetype's base row) and crits switched off so damage is exact
; ebx = the path node (archetype - 1), r12d = level
set_path:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    lea     ebx, [rdi - 1]
    mov     r12d, esi
    call    rpg_reset
    mov     [rpg_state + RPGSAVE.level], r12b
    mov     byte [rpg_ext + RPGEXT.kits], 0xFF
    mov     edi, ebx
    call    rpg_spend
    mov     dword [rpg_stats + STAT_CRIT_CHANCE * 4], 0
    pop     r12
    pop     rbx
    pop     rbp
    ret

; learn(edi ability 1..15, one that is not a path's): the ability node that teaches it gets rank 1
; without the nodes before it (the stats stay as they are: an ability node adds none) and the
; ability goes to the bar slot of the same number, so abilities_use(slot) keeps its old meaning
; ebx = ability
learn:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
    shr     edi, 2                      ; its group: Warrior 0, Archer 1, Rogue 2, Marksman 3
    lea     eax, [rdi + 1]
    test    edi, edi
    cmovnz  edi, eax                    ; archetype - 1 (the Mage, 1, has no abilities)
    imul    edi, edi, 18
    mov     eax, ebx
    and     eax, 3                      ; its slot, 1..3
    lea     rdx, [abil_off - 1]
    movzx   eax, byte [rdx + rax]       ; its node within the archetype: 7, 9 or 15
    lea     eax, [rax + rdi + NUM_ARCHETYPES]
    lea     rdx, [rpg_ext + RPGEXT.web]
    mov     byte [rdx + rax], 1
    mov     edi, ebx
    and     edi, 3
    mov     esi, ebx
    call    rpg_bar_set
    add     rsp, 8
    pop     rbx
    pop     rbp
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
; 22 b/s and strikes the zombie in its way once (10 * 1.1 = 11; stunned 30 steps); a recast
; during the cooldown and the locked war cry cost nothing; COOLDOWN_RED shortens the cooldown;
; the unlocked war cry stuns hostile mobs within 6 blocks only (within 9 with AREA 50) for 40 steps.
; The Mage's casts are the runes of test_spells.asm.
; rbx = the zombie; frame: eye[3] @0, dir[3] @12, the zombie's health before the charge @24
test_ability_cost_cooldown_and_unlock:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 40
    call    world_clear
    call    fixture
    mov     edi, ARCH_WARRIOR
    mov     esi, 5
    call    set_path
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
    mov     eax, [rbx + MOB.health]
    mov     [rsp + 24], eax
    xor     edi, edi                    ; ---- Charge
    lea     rsi, [rsp]
    lea     rdx, [rsp + 12]
    call    abilities_use
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_stamina], 70.0
    cmp     dword [abilities_cd + AB_CHARGE * 4], 360
    jne     .fail
    cmp     dword [abilities_cd_total + AB_CHARGE * 4], 360
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
    cmp     dword [abilities_cd + AB_WARCRY * 4], 0
    jne     .fail
    call    abilities_step              ; the charge reaches the zombie
    mov     eax, [rsp + 24]
    sub     eax, [rbx + MOB.health]
    cmp     eax, 11
    jne     .fail
    cmp     dword [rbx + MOB.stun], 30
    jne     .fail
    call    abilities_step              ; and strikes it once
    mov     eax, [rsp + 24]
    sub     eax, [rbx + MOB.health]
    cmp     eax, 11
    jne     .fail
    cmp     dword [abilities_cd + AB_CHARGE * 4], 358
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
    cmp     dword [abilities_cd + AB_CHARGE * 4], 324
    jne     .fail
    cmp     dword [abilities_cd_total + AB_CHARGE * 4], 324
    jne     .fail
    call    abilities_reset             ; ---- War Cry, bought: stuns within 6 blocks, not beyond
    call    rpg_recompute
    mov     dword [rpg_stats + STAT_CRIT_CHANCE * 4], 0
    mov     edi, AB_WARCRY
    call    learn
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
    cmp     dword [abilities_cd + AB_WARCRY * 4], 1200
    jne     .fail
    cmp     dword [mobs + MOB.stun], 40
    jne     .fail
    cmp     dword [mobs + MOB_size + MOB.stun], 0
    jne     .fail
    call    abilities_reset             ; ---- AREA 50: 9 blocks, the zombie 8 ahead too
    mov     dword [rpg_stats + STAT_AREA * 4], 50
    SETF    [combat_stamina], 100.0
    mov     edi, 1
    lea     rsi, [rsp]
    lea     rdx, [rsp + 12]
    call    abilities_use
    cmp     eax, 1
    jne     .fail
    cmp     dword [mobs + MOB_size + MOB.stun], 40
    jne     .fail
    mov     dword [rpg_stats + STAT_AREA * 4], 0
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

; An Archer's Volley: 30 stamina, five live arrows (each carrying the unscaled 6) fanned -20, -10,
; 0, 10, 20 degrees around -z at 40 b/s, the ten arrows in the quiver all still there. Arrow Rain
; (slot 2, node 9), aimed 45 degrees down at the floor: 60 stamina and a 1800 step cooldown; after
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
    mov     edi, ARCH_ARCHER
    mov     esi, 5
    call    set_path
    mov     edi, AB_RAIN
    call    learn
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
    cmp     dword [rcx + ARROWENT.damage], 6
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
    cmp     dword [abilities_cd + AB_RAIN * 4], 1800
    jne     .fail
    mov     r12d, 120
.rain:
    call    abilities_step
    dec     r12d
    jnz     .rain
    call    count_live
    cmp     eax, 29
    jne     .fail                       ; 5 + 24, none more
    cmp     dword [abilities_cd + AB_VOLLEY * 4], 240
    jne     .fail
    cmp     dword [abilities_cd + AB_RAIN * 4], 1680
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
    cmp     dword [rcx + ARROWENT.damage], 6
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

; ---- the slot 3 abilities, the keystones that reach the abilities, AREA and the staff bolt -----
; test_new_abilities runs the scenes below in turn. Each starts from world_clear and the fixture,
; builds its character (the tree in rpg_ext, the keystones in rpg_keystones, the legendary powers
; in gear_powers, stats poked after the recompute) and cleans up after itself; it returns 0 when
; everything held.

; tree_12_15(edi archetype 1..5): rank 1 in the archetype's nodes 12, 13, 14 and 15 (the third branch
; down to its slot 3 ability) on top of what it has, the stats recomputed (crit chance off again) and
; that slot 3 ability bound to bar slot 3
; ebx = archetype - 1
tree_12_15:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    lea     ebx, [rdi - 1]
    imul    eax, ebx, 18
    lea     rdx, [rpg_ext + RPGEXT.web]
    mov     dword [rdx + rax + NUM_ARCHETYPES + 12], 0x01010101
    call    rpg_recompute
    mov     dword [rpg_stats + STAT_CRIT_CHANCE * 4], 0
    mov     edi, 3
    lea     esi, [rbx*4 + 3]
    call    rpg_bar_set
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; hold(edi id): the item alone in hotbar slot 0, selected
hold:
    mov     dword [inv_sel], 0
    mov     byte [inv + INVENTORY.slots + ITEMSTACK.id], dil
    mov     byte [inv + INVENTORY.slots + ITEMSTACK.count], 1
    mov     word [inv + INVENTORY.slots + ITEMSTACK.dmg], 0
    ret

; spawn(edi type, xmm0 x, xmm1 y, xmm2 z) -> rax the mob, 0 when the table is full
spawn:
    sub     rsp, 8
    call    mob_spawn
    test    eax, eax
    js      .none
    imul    eax, eax, MOB_size
    lea     rcx, [mobs]
    add     rax, rcx
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    add     rsp, 8
    ret

; arrows_all(edi n, esi kind, edx damage, ecx flags) -> eax 1 when the first n arrows are live
; arrows of the player's (no pickup) of that kind, carrying that damage and exactly those flags
arrows_all:
    lea     r8, [arrows]
.l:
    test    edi, edi
    jz      .yes
    cmp     dword [r8 + ARROWENT.live], 1
    jne     .no
    cmp     [r8 + ARROWENT.kind], esi
    jne     .no
    cmp     dword [r8 + ARROWENT.owner], 0
    jne     .no
    cmp     dword [r8 + ARROWENT.pickup], 0
    jne     .no
    cmp     [r8 + ARROWENT.damage], edx
    jne     .no
    cmp     [r8 + ARROWENT.flags], ecx
    jne     .no
    add     r8, ARROWENT_size
    dec     edi
    jmp     .l
.yes:
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; count_flag(edi bits) -> eax the live arrows whose flags carry any of the bits
count_flag:
    lea     rcx, [arrows]
    xor     eax, eax
    mov     edx, MAX_ARROWS
.l:
    cmp     dword [rcx + ARROWENT.live], 0
    je      .next
    test    [rcx + ARROWENT.flags], edi
    jz      .next
    inc     eax
.next:
    add     rcx, ARROWENT_size
    dec     edx
    jnz     .l
    ret

; arrow_near(rdi arrow, rsi float[6] x y z vx vy vz) -> eax 1 when the arrow's position and
; velocity are all within 0.01 of those
; rbx = arrow, r12 = the expected, r13d = the field
arrow_near:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12, rsi
    xor     r13d, r13d
.f:
    movss   xmm0, [rbx + r13*4]
    movss   xmm1, [r12 + r13*4]
    call    close_to
    test    eax, eax
    jz      .done
    inc     r13d
    cmp     r13d, 6
    jb      .f
    mov     eax, 1
.done:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; Ground Slam. Warrior L15 holding an iron sword, ranks in nodes 12..15 only, AREA 0, crit chance 0:
; it costs 45 stamina and starts a 720 step cooldown; the zombie 3 blocks ahead loses
; round(7 * 1.5 * 1.1) = 12, is stunned 40 steps and launched at 6 b/s; the Fallen King 3 blocks
; east is stunned 15 steps, a Juggernaut elite 3 blocks west not at all; the zombie 5 blocks ahead
; is untouched - until AREA 50 stretches the slam from 4 blocks to 6. The floor bursts and the
; camera shakes. With CRIT_CHANCE 100 the blow is a crit: round(7 * 1.5 * 1.1 * 1.5) = 17.
; frame: eye[3] @0, dir[3] @12, the health of mob 0 @24 and of mob 1 @28, the result @40
na_ground_slam:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 48
    call    world_clear
    call    fixture
    mov     edi, ARCH_WARRIOR
    mov     esi, 15
    call    set_path
    mov     edi, ARCH_WARRIOR
    call    tree_12_15
    mov     dword [rpg_stats + STAT_AREA * 4], 0
    mov     edi, IRON_SWORD
    call    hold
    SETF    [combat_stamina], 100.0
    lea     rdi, [rsp]
    xorps   xmm0, xmm0                  ; yaw 0: facing -z
    xorps   xmm1, xmm1
    call    view
    SPAWN   MOB_ZOMBIE, k_16_5, k_11, k_13_5    ; mob 0: 3 blocks ahead
    SPAWN   MOB_ZOMBIE, k_16_5, k_11, k_11_5    ; mob 1: 5 blocks ahead
    SPAWN   MOB_ZOMBIE, k_19_5, k_11, k_16_5    ; mob 2: 3 blocks east, the Fallen King
    mov     dword MOBF(2, MOB.type), MOB_BOSS
    SPAWN   MOB_ZOMBIE, k_13_5, k_11, k_16_5    ; mob 3: 3 blocks west, a Juggernaut
    mov     dword MOBF(3, MOB.affix), AFX_JUGGERNAUT
    SAVE_HEALTH 0, 24
    SAVE_HEALTH 1, 28
    CAST    3, 0
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_stamina], 55.0
    cmp     dword [abilities_cd + AB_SLAM * 4], 720
    jne     .fail
    cmp     dword [abilities_cd_total + AB_SLAM * 4], 720
    jne     .fail
    EXPECT_LOST 0, 24, 12
    cmp     dword MOBF(0, MOB.stun), 40
    jne     .fail
    movss   xmm0, MOBF(0, BODY.vy)
    comiss  xmm0, [k_6]
    jb      .fail                       ; launched
    cmp     dword MOBF(2, MOB.stun), 15
    jne     .fail
    cmp     dword MOBF(3, MOB.stun), 0
    jne     .fail
    EXPECT_LOST 1, 28, 0                ; out of reach
    cmp     dword MOBF(1, MOB.stun), 0
    jne     .fail
    call    fx_count
    test    eax, eax
    jz      .fail
    movss   xmm0, [fx_shake]
    comiss  xmm0, [k_0_6]
    jb      .fail
    call    mobs_clear                  ; ---- AREA 50: 4 * 1.5 = 6 blocks
    call    abilities_reset
    SETF    [combat_stamina], 100.0
    mov     dword [rpg_stats + STAT_AREA * 4], 50
    SPAWN   MOB_ZOMBIE, k_16_5, k_11, k_11_5
    SAVE_HEALTH 0, 24
    CAST    3, 0
    cmp     eax, 1
    jne     .fail
    EXPECT_LOST 0, 24, 12
    cmp     dword MOBF(0, MOB.stun), 40
    jne     .fail
    call    mobs_clear                  ; ---- a crit (a skeleton has no weakness to hide it)
    call    abilities_reset
    SETF    [combat_stamina], 100.0
    mov     dword [rpg_stats + STAT_AREA * 4], 0
    mov     dword [rpg_stats + STAT_CRIT_CHANCE * 4], 100
    SPAWN   MOB_SKELETON, k_16_5, k_11, k_13_5
    SAVE_HEALTH 0, 24
    CAST    3, 0
    cmp     eax, 1
    jne     .fail
    EXPECT_LOST 0, 24, 17               ; round(7 * 1.5 * 1.1 * 1.5) = round(17.3)
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     [rsp + 40], eax
    call    cleanup
    mov     eax, [rsp + 40]
    leave
    ret

; Hunter's Mark. Archer L5 with rank 1 in node 15: a zombie 6 blocks ahead behind a stone wall is
; no target - the cast fails and costs nothing; with the wall gone it marks the zombie for 600
; steps, costs 20 stamina, starts a 480 step cooldown and gold sparks fly; a pig in plain sight is
; no target either.
; frame: eye[3] @0, dir[3] @12, the result @40
na_hunters_mark:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 48
    call    world_clear
    call    fixture
    mov     edi, ARCH_ARCHER
    mov     esi, 5
    call    set_path
    mov     edi, AB_MARK
    call    learn
    SETF    [combat_stamina], 100.0
    lea     rdi, [rsp]
    xorps   xmm0, xmm0
    xorps   xmm1, xmm1
    call    view
    SPAWN   MOB_ZOMBIE, k_16_5, k_11, k_10_5    ; mob 0: 6 blocks ahead
    FILL    16, 11, 13, 16, 13, 13, STONE       ; a wall in between
    CAST    3, 0
    test    eax, eax
    jnz     .fail
    EXPECT_NEAR [combat_stamina], 100.0
    cmp     dword [abilities_cd + AB_MARK * 4], 0
    jne     .fail
    cmp     dword MOBF(0, MOB.mark_t), 0
    jne     .fail
    FILL    16, 11, 13, 16, 13, 13, AIR         ; the wall gone
    CAST    3, 0
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_stamina], 80.0
    cmp     dword [abilities_cd + AB_MARK * 4], 480
    jne     .fail
    cmp     dword MOBF(0, MOB.mark_t), 600
    jne     .fail
    call    fx_count
    cmp     eax, 12
    jb      .fail
    call    mobs_clear                  ; ---- a pig is no foe (on a step: the eye ray meets it)
    call    abilities_reset
    SETF    [combat_stamina], 100.0
    SPAWN   MOB_PIG, k_16_5, k_12, k_10_5
    CAST    3, 0
    test    eax, eax
    jnz     .fail
    EXPECT_NEAR [combat_stamina], 100.0
    cmp     dword MOBF(0, MOB.mark_t), 0
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     [rsp + 40], eax
    call    cleanup
    mov     eax, [rsp + 40]
    leave
    ret

; Fan of Knives. Rogue L5 with rank 1 in node 15: it costs 35 stamina and starts a 540 step
; cooldown; eight live PROJ_KNIFE of the player's (no pickup, damage 6, AF_BLEED) leave
; (16.5, eye y - 0.5, 16.5) level at 30 b/s, 45 degrees apart from the heading, -z: knife k flies
; along (sin 45k, -cos 45k). With CRIT_CHANCE 100 every knife also carries AF_CRIT; with 50 each
; rolls for itself (the eight are not all alike).
; frame: eye[3] @0, dir[3] @12, the result @40
na_fan_of_knives:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 56
    call    world_clear
    call    fixture
    mov     edi, ARCH_ROGUE
    mov     esi, 5
    call    set_path
    mov     edi, AB_KNIVES
    call    learn
    SETF    [combat_stamina], 100.0
    lea     rdi, [rsp]
    xorps   xmm0, xmm0
    xorps   xmm1, xmm1
    call    view
    CAST    3, 0
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_stamina], 65.0
    cmp     dword [abilities_cd + AB_KNIVES * 4], 540
    jne     .fail
    mov     edi, 8
    mov     esi, PROJ_KNIFE
    mov     edx, 6
    mov     ecx, AF_BLEED
    call    arrows_all
    test    eax, eax
    jz      .fail
    call    count_live
    cmp     eax, 8
    jne     .fail
    xor     ebx, ebx
.knife:
    imul    eax, ebx, ARROWENT_size
    lea     rdi, [arrows]
    add     rdi, rax
    imul    eax, ebx, 24
    lea     rsi, [knife_exp]
    add     rsi, rax
    call    arrow_near
    test    eax, eax
    jz      .fail
    inc     ebx
    cmp     ebx, 8
    jb      .knife
    call    arrows_clear                ; ---- CRIT_CHANCE 100: all eight carry AF_CRIT
    call    abilities_reset
    SETF    [combat_stamina], 100.0
    mov     dword [rpg_stats + STAT_CRIT_CHANCE * 4], 100
    CAST    3, 0
    cmp     eax, 1
    jne     .fail
    mov     edi, 8
    mov     esi, PROJ_KNIFE
    mov     edx, 6
    mov     ecx, AF_BLEED | AF_CRIT
    call    arrows_all
    test    eax, eax
    jz      .fail
    call    arrows_clear                ; ---- 50 %: each knife rolls on its own
    call    abilities_reset
    SETF    [combat_stamina], 100.0
    mov     dword [rpg_stats + STAT_CRIT_CHANCE * 4], 50
    CAST    3, 0
    cmp     eax, 1
    jne     .fail
    mov     edi, AF_CRIT
    call    count_flag
    test    eax, eax
    jz      .fail
    cmp     eax, 8
    je      .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     [rsp + 40], eax
    call    cleanup
    mov     eax, [rsp + 40]
    add     rsp, 56
    pop     rbx
    pop     rbp
    ret

; Barrage. Archer L5 with the keystone: the Volley (30 stamina) fires seven arrows, none of them
; from the quiver, each carrying the unscaled 6 and fanned from -30 to 30 degrees in 10 degree
; steps around -z at 40 b/s: the ends fly along (-+20, -34.64), the middle one along -z.
; frame: eye[3] @0, dir[3] @12, the result @40
na_barrage:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 48
    call    world_clear
    call    fixture
    mov     edi, ARCH_ARCHER
    mov     esi, 5
    call    set_path
    or      dword [rpg_keystones], 1 << KS_BARRAGE
    SETF    [combat_stamina], 100.0
    mov     edi, ARROW
    mov     esi, 10
    call    inv_add
    lea     rdi, [rsp]
    xorps   xmm0, xmm0
    xorps   xmm1, xmm1
    call    view
    CAST    0, 0
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_stamina], 70.0
    call    count_live
    cmp     eax, 7
    jne     .fail
    mov     edi, 7
    mov     esi, PROJ_ARROW
    mov     edx, 6
    xor     ecx, ecx
    call    arrows_all
    test    eax, eax
    jz      .fail
    mov     edi, ARROW
    call    inv_count
    cmp     eax, 10
    jne     .fail
    EXPECT_NEAR [arrows + ARROWENT.vx], -20.0
    EXPECT_NEAR [arrows + ARROWENT.vz], -34.64
    EXPECT_NEAR [arrows + ARROWENT_size * 3 + ARROWENT.vx], 0.0
    EXPECT_NEAR [arrows + ARROWENT_size * 3 + ARROWENT.vz], -40.0
    EXPECT_NEAR [arrows + ARROWENT_size * 6 + ARROWENT.vx], 20.0
    EXPECT_NEAR [arrows + ARROWENT_size * 6 + ARROWENT.vz], -34.64
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     [rsp + 40], eax
    call    cleanup
    mov     eax, [rsp + 40]
    leave
    ret

; BOLT_KIND n, kind: another staff bolt, the wait over and the mana full: it is arrow n, of that
; kind
%macro BOLT_KIND 2
    mov     dword [abilities_bolt_cd], 0
    SETF    [combat_mana], 100.0
    BOLT    0
    cmp     eax, 1
    jne     .fail
    cmp     dword [arrows + ARROWENT_size * %1 + ARROWENT.kind], %2
    jne     .fail
%endmacro

; The staff bolt. Mage L5 holding a staff: 5 mana, a PROJ_BOLT carrying the unscaled 4, AF_ATTACK
; and a shock element, at 45 b/s from 0.4 ahead of the eye, and 24 steps until the next (asked
; too early it is silently nothing); with ATTACK_SPEED 50 the wait is 16 steps (24 * 100 / 150),
; 12 for the Archmage Staff (18 * 100 / 150), which costs 4 mana and carries 7; CRIT_CHANCE 100
; adds AF_CRIT; short of mana (3) the click plays and the wait is the full 24 steps. Under the
; Archmage's power every 4th bolt is a fireball for twice the base (8, no flags, 28 b/s) and the
; count starts over. A Warrior holding the staff swings it.
; frame: eye[3] @0, dir[3] @12, the result @40
na_staff_bolt:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 48
    call    world_clear
    call    fixture
    mov     edi, ARCH_MAGE
    mov     esi, 5
    call    set_path
    mov     edi, STAFF
    call    hold
    SETF    [combat_mana], 100.0
    lea     rdi, [rsp]
    xorps   xmm0, xmm0
    xorps   xmm1, xmm1
    call    view
    BOLT    0
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_mana], 95.0
    cmp     dword [abilities_bolt_cd], 24
    jne     .fail
    mov     edi, 1
    mov     esi, PROJ_BOLT
    mov     edx, 4
    mov     ecx, AF_ATTACK | (ELEM_SHOCK << AF_ELEM_SHIFT)
    call    arrows_all
    test    eax, eax
    jz      .fail
    EXPECT_NEAR [arrows + ARROWENT.z], 16.1
    EXPECT_NEAR [arrows + ARROWENT.vz], -45.0
    BOLT    0                           ; too early: nothing
    test    eax, eax
    jnz     .fail
    EXPECT_NEAR [combat_mana], 95.0
    call    count_live
    cmp     eax, 1
    jne     .fail
    call    arrows_clear                ; ---- ATTACK_SPEED 50: 24 * 100 / 150 = 16 steps
    mov     dword [abilities_bolt_cd], 0
    mov     dword [rpg_stats + STAT_ATTACK_SPEED * 4], 50
    SETF    [combat_mana], 100.0
    BOLT    0
    cmp     eax, 1
    jne     .fail
    cmp     dword [abilities_bolt_cd], 16
    jne     .fail
    call    arrows_clear                ; ---- the Archmage Staff: 4 mana, base 7, 12 steps
    mov     dword [abilities_bolt_cd], 0
    mov     edi, ARCHMAGE_STAFF
    call    hold
    SETF    [combat_mana], 100.0
    BOLT    0
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_mana], 96.0
    cmp     dword [abilities_bolt_cd], 12
    jne     .fail
    mov     edi, 1
    mov     esi, PROJ_BOLT
    mov     edx, 7
    mov     ecx, AF_ATTACK | (ELEM_SHOCK << AF_ELEM_SHIFT)
    call    arrows_all
    test    eax, eax
    jz      .fail
    call    arrows_clear                ; ---- a crit rides along as a flag
    mov     dword [abilities_bolt_cd], 0
    mov     dword [rpg_stats + STAT_CRIT_CHANCE * 4], 100
    SETF    [combat_mana], 100.0
    BOLT    0
    cmp     eax, 1
    jne     .fail
    mov     edi, 1
    mov     esi, PROJ_BOLT
    mov     edx, 7
    mov     ecx, AF_ATTACK | AF_CRIT | (ELEM_SHOCK << AF_ELEM_SHIFT)
    call    arrows_all
    test    eax, eax
    jz      .fail
    call    arrows_clear                ; ---- short of mana: the click, and the full wait
    mov     dword [abilities_bolt_cd], 0
    mov     dword [rpg_stats + STAT_ATTACK_SPEED * 4], 0
    mov     edi, STAFF
    call    hold
    SETF    [combat_mana], 3.0
    BOLT    0
    test    eax, eax
    jnz     .fail
    cmp     dword [abilities_bolt_cd], 24
    jne     .fail
    EXPECT_NEAR [combat_mana], 3.0
    call    count_live
    test    eax, eax
    jnz     .fail
    mov     dword [rpg_stats + STAT_CRIT_CHANCE * 4], 0     ; ---- the Archmage's power
    or      dword [gear_powers], 1 << LP_ARCHMAGE
    BOLT_KIND 0, PROJ_BOLT
    BOLT_KIND 1, PROJ_BOLT
    BOLT_KIND 2, PROJ_BOLT
    BOLT_KIND 3, PROJ_FIREBALL
    cmp     dword [arrows + ARROWENT_size * 3 + ARROWENT.damage], 8
    jne     .fail
    cmp     dword [arrows + ARROWENT_size * 3 + ARROWENT.flags], 0
    jne     .fail
    EXPECT_NEAR [arrows + ARROWENT_size * 3 + ARROWENT.vz], -28.0
    BOLT_KIND 4, PROJ_BOLT              ; the count starts over
    call    arrows_clear                ; ---- a Warrior swings the staff
    mov     edi, ARCH_WARRIOR
    mov     esi, 5
    call    set_path
    mov     dword [abilities_bolt_cd], 0
    SETF    [combat_mana], 100.0
    BOLT    0
    test    eax, eax
    jnz     .fail
    call    count_live
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     [rsp + 40], eax
    call    cleanup
    mov     eax, [rsp + 40]
    leave
    ret

; The whirlwind's reach and the smoke bomb. Warrior L5 holding an iron sword with rank 1 in node 9,
; AREA 0: there is no slot 4; the whirlwind costs 60 stamina, starts a 1800 step cooldown and pulses
; on the next step: the zombie 3 blocks ahead loses round(7 * 1.1) = 8, the one 4 ahead is beyond
; its 3.5 blocks - until AREA 50 stretches them to 5.25 (and under the war cry the blow is x1.3:
; round(7 * 1.3 * 1.1) = 10). Rogue L5 with rank 1 in node 7: the smoke bomb gives 300 steps of
; stealth, 1800 under Shadow Dance.
; frame: eye[3] @0, dir[3] @12, the health of mobs 0 and 1 @24, @28, the result @40
na_whirl_and_smoke:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 48
    call    world_clear
    call    fixture
    mov     edi, ARCH_WARRIOR
    mov     esi, 5
    call    set_path
    mov     edi, AB_WHIRL
    call    learn
    mov     dword [rpg_stats + STAT_AREA * 4], 0
    mov     edi, IRON_SWORD
    call    hold
    SETF    [combat_stamina], 100.0
    lea     rdi, [rsp]
    xorps   xmm0, xmm0
    xorps   xmm1, xmm1
    call    view
    CAST    4, 0
    test    eax, eax
    jnz     .fail
    EXPECT_NEAR [combat_stamina], 100.0
    SPAWN   MOB_ZOMBIE, k_16_5, k_11, k_13_5    ; mob 0: 3 blocks ahead
    SPAWN   MOB_ZOMBIE, k_16_5, k_11, k_12_5    ; mob 1: 4 blocks ahead
    SAVE_HEALTH 0, 24
    SAVE_HEALTH 1, 28
    CAST    2, 0
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_stamina], 40.0
    cmp     dword [abilities_cd + AB_WHIRL * 4], 1800
    jne     .fail
    call    abilities_step             ; the first pulse
    EXPECT_LOST 0, 24, 8
    EXPECT_LOST 1, 28, 0
    call    mobs_clear                  ; ---- AREA 50: 5.25 blocks, and the war cry: x1.3
    call    abilities_reset
    SETF    [combat_stamina], 100.0
    mov     dword [rpg_stats + STAT_AREA * 4], 50
    SPAWN   MOB_ZOMBIE, k_16_5, k_11, k_12_5
    SAVE_HEALTH 0, 24
    CAST    2, 0
    cmp     eax, 1
    jne     .fail
    mov     dword [combat_warcry_t], 480
    call    abilities_step
    EXPECT_LOST 0, 24, 10               ; round(7 * 1.3 * 1.1) = round(10.01)
    call    abilities_reset             ; ---- the smoke bomb
    mov     edi, ARCH_ROGUE
    mov     esi, 5
    call    set_path
    mov     edi, AB_SMOKE
    call    learn
    SETF    [combat_stamina], 100.0
    CAST    1, 0
    cmp     eax, 1
    jne     .fail
    cmp     dword [combat_stealth_t], 300
    jne     .fail
    call    abilities_reset
    SETF    [combat_stamina], 100.0
    or      dword [rpg_keystones], 1 << KS_SHADOW_DANCE
    CAST    1, 0
    cmp     eax, 1
    jne     .fail
    cmp     dword [combat_stealth_t], 1800
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     [rsp + 40], eax
    call    cleanup
    mov     eax, [rsp + 40]
    leave
    ret

; Shadowstep (its target search is the one Hunter's Mark uses). Rogue L5, a zombie 4 blocks ahead
; that faces -z: with a stone wall in between nothing is in sight - the cast fails and costs
; nothing; with the wall gone the player appears behind the zombie by its half width plus 0.8
; (16.5, 11, 13.6), facing it (yaw 0, pitch level), with 25 stamina and a 480 step cooldown paid,
; and his next hit within 120 steps is a crit.
; frame: eye[3] @0, dir[3] @12, the result @40
na_shadowstep:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 48
    call    world_clear
    call    fixture
    mov     edi, ARCH_ROGUE
    mov     esi, 5
    call    set_path
    SETF    [combat_stamina], 100.0
    lea     rdi, [rsp]
    xorps   xmm0, xmm0                  ; yaw 0: facing -z
    xorps   xmm1, xmm1
    call    view
    SPAWN   MOB_ZOMBIE, k_16_5, k_11, k_12_5    ; mob 0: 4 blocks ahead
    mov     dword MOBF(0, BODY.yaw), 0          ; facing -z as well
    FILL    16, 11, 13, 16, 13, 13, STONE       ; a wall in between
    CAST    0, 0
    test    eax, eax
    jnz     .fail
    EXPECT_NEAR [combat_stamina], 100.0
    EXPECT_NEAR [player + BODY.z], 16.5
    cmp     dword [abilities_cd + ABIL_SHADOWSTEP * 4], 0
    jne     .fail
    FILL    16, 11, 13, 16, 13, 13, AIR         ; the wall gone
    CAST    0, 0
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_stamina], 75.0
    cmp     dword [abilities_cd + ABIL_SHADOWSTEP * 4], 480
    jne     .fail
    EXPECT_NEAR [player + BODY.x], 16.5
    EXPECT_NEAR [player + BODY.y], 11.0
    EXPECT_NEAR [player + BODY.z], 13.6
    EXPECT_NEAR [player + BODY.yaw], 0.0
    EXPECT_NEAR [player + BODY.pitch], 0.0
    cmp     dword [combat_crit_next_t], 120
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     [rsp + 40], eax
    call    cleanup
    mov     eax, [rsp + 40]
    leave
    ret

; The projectile abilities carry unscaled bases. Archer L5 with rank 1 in node 7: the Explosive Arrow
; (35 stamina, a 600 step cooldown) is a PROJ_ARROW carrying 10 and AF_EXPLOSIVE, and AF_CRIT besides
; with CRIT_CHANCE 100.
; frame: eye[3] @0, dir[3] @12, the result @40
na_projectile_bases:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 48
    call    world_clear
    call    fixture
    call    arrows_clear                ; ---- the Explosive Arrow
    call    abilities_reset
    mov     edi, ARCH_ARCHER
    mov     esi, 5
    call    set_path
    mov     edi, AB_EXPLARROW
    call    learn
    SETF    [combat_stamina], 100.0
    CAST    1, 0
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_stamina], 65.0
    cmp     dword [abilities_cd + AB_EXPLARROW * 4], 600
    jne     .fail
    mov     edi, 1
    mov     esi, PROJ_ARROW
    mov     edx, 10
    mov     ecx, AF_EXPLOSIVE
    call    arrows_all
    test    eax, eax
    jz      .fail
    call    arrows_clear
    call    abilities_reset
    SETF    [combat_stamina], 100.0
    mov     dword [rpg_stats + STAT_CRIT_CHANCE * 4], 100
    CAST    1, 0
    cmp     eax, 1
    jne     .fail
    mov     edi, 1
    mov     esi, PROJ_ARROW
    mov     edx, 10
    mov     ecx, AF_EXPLOSIVE | AF_CRIT
    call    arrows_all
    test    eax, eax
    jz      .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     [rsp + 40], eax
    call    cleanup
    mov     eax, [rsp + 40]
    leave
    ret

; War Cry and Charge stun rules. Warrior L15 with the war cry bought: the war cry stuns the plain
; zombie 3 blocks ahead 40 steps, leaves the Juggernaut elite 3 blocks east unstunned and never
; shortens the 90 step freeze of the zombie 3 blocks west. A charge into a Juggernaut leaves its
; stun at 0 (the blow still lands), and into a frozen zombie leaves the freeze at 90.
; frame: eye[3] @0, dir[3] @12, the health of mob 0 @24, the result @40
na_stun_rules:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 48
    call    world_clear
    call    fixture
    mov     edi, ARCH_WARRIOR
    mov     esi, 15
    call    set_path
    mov     edi, AB_WARCRY
    call    learn
    SETF    [combat_stamina], 100.0
    lea     rdi, [rsp]
    xorps   xmm0, xmm0                  ; yaw 0: facing -z
    xorps   xmm1, xmm1
    call    view
    SPAWN   MOB_ZOMBIE, k_16_5, k_11, k_13_5    ; mob 0: 3 blocks ahead
    SPAWN   MOB_ZOMBIE, k_19_5, k_11, k_16_5    ; mob 1: 3 blocks east, a Juggernaut
    mov     dword MOBF(1, MOB.affix), AFX_JUGGERNAUT
    SPAWN   MOB_ZOMBIE, k_13_5, k_11, k_16_5    ; mob 2: 3 blocks west, frozen
    mov     dword MOBF(2, MOB.stun), 90
    CAST    1, 0
    cmp     eax, 1
    jne     .fail
    cmp     dword MOBF(0, MOB.stun), 40
    jne     .fail
    cmp     dword MOBF(1, MOB.stun), 0
    jne     .fail
    cmp     dword MOBF(2, MOB.stun), 90
    jne     .fail
    call    mobs_clear                  ; ---- Charge into a Juggernaut
    call    abilities_reset
    SETF    [combat_stamina], 100.0
    SPAWN   MOB_ZOMBIE, k_16_5, k_11, k_15_5    ; one block ahead
    mov     dword MOBF(0, MOB.affix), AFX_JUGGERNAUT
    SAVE_HEALTH 0, 24
    CAST    0, 0
    cmp     eax, 1
    jne     .fail
    call    abilities_step
    mov     eax, MOBF(0, MOB.health)
    cmp     eax, [rsp + 24]
    jge     .fail                       ; the blow landed
    cmp     dword MOBF(0, MOB.stun), 0
    jne     .fail
    call    mobs_clear                  ; ---- Charge into a frozen zombie
    call    abilities_reset
    SETF    [combat_stamina], 100.0
    SPAWN   MOB_ZOMBIE, k_16_5, k_11, k_15_5
    mov     dword MOBF(0, MOB.stun), 90
    CAST    0, 0
    cmp     eax, 1
    jne     .fail
    call    abilities_step
    cmp     dword MOBF(0, MOB.stun), 90
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     [rsp + 40], eax
    call    cleanup
    mov     eax, [rsp + 40]
    leave
    ret

; SCENE function, number: run the scene; a failure ends test_new_abilities with the scene's number
%macro SCENE 2
    call    %1
    test    eax, eax
    jz      %%ok
    mov     eax, %2
    jmp     .ret
%%ok:
%endmacro

; Every scene above in turn: 0 when all held, else the number of the first scene that failed
; (1 ground slam, 2 hunter's mark, 3 fan of knives, 4 barrage, 5 staff bolt, 6 whirlwind and smoke
; bomb, 7 shadowstep, 8 projectile bases, 9 stun rules)
test_new_abilities:
    push    rbp
    mov     rbp, rsp
    SCENE   na_ground_slam, 1
    SCENE   na_hunters_mark, 2
    SCENE   na_fan_of_knives, 3
    SCENE   na_barrage, 4
    SCENE   na_staff_bolt, 5
    SCENE   na_whirl_and_smoke, 6
    SCENE   na_shadowstep, 7
    SCENE   na_projectile_bases, 8
    SCENE   na_stun_rules, 9
    xor     eax, eax
.ret:
    pop     rbp
    ret

; EXPECT_BAR slot, ability: fail unless the bar's slot holds that ability id (-1: empty)
%macro EXPECT_BAR 2
    mov     edi, %1
    call    rpg_bar_ability
    cmp     eax, %2
    jne     .fail
%endmacro

; BAR_SET slot, ability, answer: rpg_bar_set(slot, ability) must answer 0 or 1
%macro BAR_SET 3
    mov     edi, %1
    mov     esi, %2
    call    rpg_bar_set
    cmp     eax, %3
    jne     .fail
%endmacro

; The ability bar. Level 5, the Path of the Warrior taken by spending a point: Charge goes into slot 0
; (the other slots are empty); War Cry cannot be bound before it is learned; Toughness binds nothing,
; War Cry (the next ability node, bought with the next point) goes into the first empty slot. Binding
; Charge to the empty slot 2 moves it (slot 0 empties); binding it to slot 1 swaps it with War Cry. A
; cast from slot 1 is the Charge: 30 stamina, a 360 step cooldown kept in the Charge's own cell, not in
; a slot's; rebound to slot 3 the cooldown is still running and a recast from slot 3 costs nothing; an
; empty slot dry-fires at no cost; War Cry from slot 2 runs its own cooldown beside it. Whirlwind (not
; learned), a stray ability id and a slot out of range cannot be bound; ability -1 empties a slot.
; frame: eye[3] @0, dir[3] @12, the result @24
test_ability_bar_binding:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32
    call    world_clear
    call    fixture
    mov     byte [rpg_state + RPGSAVE.level], 5
    mov     edi, ARCH_WARRIOR - 1       ; ---- the Path of the Warrior: Charge into slot 0
    call    rpg_spend
    cmp     eax, 1
    jne     .fail
    EXPECT_BAR 0, AB_CHARGE
    EXPECT_BAR 1, -1
    EXPECT_BAR 2, -1
    EXPECT_BAR 3, -1
    BAR_SET 1, AB_WARCRY, 0             ; ---- not learned: it cannot be bound
    EXPECT_BAR 1, -1
    mov     edi, NUM_ARCHETYPES + 6     ; Toughness (the Warrior's node 6): a stat node binds nothing
    call    rpg_spend
    cmp     eax, 1
    jne     .fail
    EXPECT_BAR 1, -1
    mov     edi, NUM_ARCHETYPES + 7     ; War Cry (node 7): the bar takes it into its first empty slot
    call    rpg_spend
    cmp     eax, 1
    jne     .fail
    EXPECT_BAR 0, AB_CHARGE
    EXPECT_BAR 1, AB_WARCRY
    BAR_SET 2, AB_CHARGE, 1             ; ---- onto the empty slot 2: slot 0 empties
    EXPECT_BAR 0, -1
    EXPECT_BAR 1, AB_WARCRY
    EXPECT_BAR 2, AB_CHARGE
    BAR_SET 1, AB_CHARGE, 1             ; ---- onto slot 1: the two swap
    EXPECT_BAR 1, AB_CHARGE
    EXPECT_BAR 2, AB_WARCRY
    SETF    [combat_stamina], 100.0     ; ---- a cast from slot 1 is the Charge
    lea     rdi, [rsp]
    xorps   xmm0, xmm0                  ; facing -z
    xorps   xmm1, xmm1
    call    view
    CAST    1, 0
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_stamina], 70.0
    cmp     dword [abilities_cd + AB_CHARGE * 4], 360
    jne     .fail
    cmp     dword [abilities_cd + AB_WARCRY * 4], 0     ; not the cell of "slot 1"
    jne     .fail
    BAR_SET 3, AB_CHARGE, 1             ; ---- rebound to slot 3: the cooldown stays with the ability
    EXPECT_BAR 1, -1
    EXPECT_BAR 3, AB_CHARGE
    cmp     dword [abilities_cd + AB_CHARGE * 4], 360
    jne     .fail
    CAST    3, 0
    test    eax, eax
    jnz     .fail                       ; it still cools down: nothing is paid
    EXPECT_NEAR [combat_stamina], 70.0
    cmp     dword [abilities_cd + AB_CHARGE * 4], 360
    jne     .fail
    CAST    1, 0                        ; ---- an empty slot: no cast, no cost
    test    eax, eax
    jnz     .fail
    EXPECT_NEAR [combat_stamina], 70.0
    CAST    2, 0                        ; ---- War Cry from slot 2: its own cooldown
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_stamina], 30.0
    cmp     dword [abilities_cd + AB_WARCRY * 4], 1200
    jne     .fail
    cmp     dword [abilities_cd + AB_CHARGE * 4], 360
    jne     .fail
    BAR_SET 0, AB_WHIRL, 0              ; ---- not learned
    BAR_SET 0, AB_VOLLEY, 0             ; another archetype's
    BAR_SET 0, NUM_ABILITIES, 0         ; no such ability
    BAR_SET 0, -2, 0
    BAR_SET 4, AB_CHARGE, 0             ; no such slot
    EXPECT_BAR 0, -1
    EXPECT_BAR 3, AB_CHARGE
    EXPECT_BAR 4, -1
    BAR_SET 0, AB_CHARGE, 1             ; ---- slot 0 again: slot 3 empties
    EXPECT_BAR 0, AB_CHARGE
    EXPECT_BAR 3, -1
    BAR_SET 0, -1, 1                    ; ---- -1 empties a slot
    EXPECT_BAR 0, -1
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

; ---- the Marksman abilities ---------------------------------------------------------------------
; test_marksman_abilities runs the scenes below in turn: 0 when everything held, else the number of
; the first scene that failed (1 the four casts, 2 the flash's radius, 3 who a flash stuns). The bar
; is filled by hand (it stores id + 1): what the web teaches ends up in the same place, and the casts
; depend on nothing but what the bar holds. None of the four needs a gun in the hand.

; BIND slot, ability: the ability sits in that bar slot
%macro BIND 2
    mov     byte [rpg_ext + RPGEXT.bar + %1], %2 + 1
%endmacro

; FLASH_AT x, y, z (float constants): ab_flash_at at that point
%macro FLASH_AT 3
    movss   xmm0, [%1]
    movss   xmm1, [%2]
    movss   xmm2, [%3]
    call    ab_flash_at
%endmacro

; STUN_IS mob, steps: fail unless the mob's stun is that many steps
%macro STUN_IS 2
    cmp     dword MOBF(%1, MOB.stun), %2
    jne     .fail
%endmacro

; UNSTUN mob: the mob is not stunned
%macro UNSTUN 1
    mov     dword MOBF(%1, MOB.stun), 0
%endmacro

; The four casts. Powder Grenade costs 30 stamina, starts an 8 s cooldown (480 steps) and lobs one
; PROJ_GRENADE of the player's (no pickup, damage 12, no flag; AF_CRIT when the crit roll hits) from
; half a block ahead of the eye at 20 b/s; a recast waits out the cooldown and costs nothing.
; Bullseye (20 stamina, 900 steps) only sets the 300 step combat_bullseye_t, which ages with the
; other timers (combat_step) and goes with combat_reset; Fan the Hammer (50 stamina, 1800 steps) the
; 240 step combat_fanhammer_t. Flashbang (35 stamina, 720 steps) lobs a PROJ_GRENADE for 0 flagged
; AF_FLASH, and never a crit.
; frame: eye[3] @0, dir[3] @12, the result @40
ma_casts:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 48
    call    world_clear
    call    fixture
    mov     dword [rpg_stats + STAT_CRIT_CHANCE * 4], 0
    BIND    0, ABIL_GRENADE
    BIND    1, ABIL_BULLSEYE
    BIND    2, ABIL_FANHAMMER
    BIND    3, ABIL_FLASHBANG
    SETF    [combat_stamina], 100.0
    lea     rdi, [rsp]
    xorps   xmm0, xmm0                  ; yaw 0: facing -z
    xorps   xmm1, xmm1
    call    view
    CAST    0, 0                        ; ---- Powder Grenade
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_stamina], 70.0
    cmp     dword [abilities_cd + ABIL_GRENADE * 4], 480
    jne     .fail
    cmp     dword [abilities_cd_total + ABIL_GRENADE * 4], 480
    jne     .fail
    mov     edi, 1
    mov     esi, PROJ_GRENADE
    mov     edx, 12
    xor     ecx, ecx
    call    arrows_all
    test    eax, eax
    jz      .fail
    call    count_live
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [arrows + ARROWENT.y], 12.62    ; level with the eye
    EXPECT_NEAR [arrows + ARROWENT.z], 16.0     ; half a block ahead of it
    EXPECT_NEAR [arrows + ARROWENT.vz], -20.0
    CAST    0, 0                        ; a recast during the cooldown: nothing paid, nothing thrown
    test    eax, eax
    jnz     .fail
    EXPECT_NEAR [combat_stamina], 70.0
    call    count_live
    cmp     eax, 1
    jne     .fail
    call    arrows_clear                ; ---- the grenade of a critical roll carries AF_CRIT
    call    abilities_reset
    SETF    [combat_stamina], 100.0
    mov     dword [rpg_stats + STAT_CRIT_CHANCE * 4], 100
    CAST    0, 0
    cmp     eax, 1
    jne     .fail
    mov     edi, 1
    mov     esi, PROJ_GRENADE
    mov     edx, 12
    mov     ecx, AF_CRIT
    call    arrows_all
    test    eax, eax
    jz      .fail
    call    arrows_clear                ; ---- Bullseye: a timer and nothing in the air
    call    abilities_reset
    SETF    [combat_stamina], 100.0
    CAST    1, 0
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_stamina], 80.0
    cmp     dword [abilities_cd + ABIL_BULLSEYE * 4], 900
    jne     .fail
    cmp     dword [combat_bullseye_t], 300
    jne     .fail
    cmp     dword [combat_fanhammer_t], 0
    jne     .fail
    call    count_live
    test    eax, eax
    jnz     .fail
    xor     edi, edi
    call    combat_step                 ; it ages with the other timers
    cmp     dword [combat_bullseye_t], 299
    jne     .fail
    SETF    [combat_stamina], 100.0     ; ---- Fan the Hammer
    CAST    2, 0
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_stamina], 50.0
    cmp     dword [abilities_cd + ABIL_FANHAMMER * 4], 1800
    jne     .fail
    cmp     dword [combat_fanhammer_t], 240
    jne     .fail
    cmp     dword [combat_bullseye_t], 299      ; each has its own timer
    jne     .fail
    call    combat_reset                ; both go with the combat state
    cmp     dword [combat_bullseye_t], 0
    jne     .fail
    cmp     dword [combat_fanhammer_t], 0
    jne     .fail
    call    abilities_reset             ; ---- Flashbang: never a crit
    SETF    [combat_stamina], 100.0
    mov     dword [rpg_stats + STAT_CRIT_CHANCE * 4], 100
    CAST    3, 0
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_stamina], 65.0
    cmp     dword [abilities_cd + ABIL_FLASHBANG * 4], 720
    jne     .fail
    mov     edi, 1
    mov     esi, PROJ_GRENADE
    xor     edx, edx
    mov     ecx, AF_FLASH
    call    arrows_all
    test    eax, eax
    jz      .fail
    EXPECT_NEAR [arrows + ARROWENT.z], 16.0
    EXPECT_NEAR [arrows + ARROWENT.vz], -20.0
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     [rsp + 40], eax
    call    cleanup
    mov     eax, [rsp + 40]
    leave
    ret

; The radius of a flash at (16.5, 11.9, 14.5), the middle of a standing zombie's body. Zombies 4.5, 6
; and 8 blocks south of it: the first is stunned 60 steps, the others are out of the 5 blocks - until
; Powder Keg (x1.5: 7.5 blocks) or AREA 50 (x1.5) reaches the second, and both together (11.25 blocks)
; the third.
; frame: the result @40
ma_flash_radius:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 48
    call    world_clear
    call    fixture
    SPAWN   MOB_ZOMBIE, k_16_5, k_11, k_19_0    ; mob 0: 4.5 blocks south
    SPAWN   MOB_ZOMBIE, k_16_5, k_11, k_20_5    ; mob 1: 6 blocks
    SPAWN   MOB_ZOMBIE, k_16_5, k_11, k_22_5    ; mob 2: 8 blocks
    FLASH_AT k_16_5, k_11_9, k_14_5             ; ---- the plain radius of 5
    STUN_IS 0, 60
    STUN_IS 1, 0
    STUN_IS 2, 0
    UNSTUN  0                           ; ---- Powder Keg: 7.5
    mov     dword [rpg_keystones], 1 << KS_POWDER_KEG
    FLASH_AT k_16_5, k_11_9, k_14_5
    STUN_IS 0, 60
    STUN_IS 1, 60
    STUN_IS 2, 0
    UNSTUN  0                           ; ---- AREA 50 alone: 7.5 as well
    UNSTUN  1
    mov     dword [rpg_keystones], 0
    mov     dword [rpg_stats + STAT_AREA * 4], 50
    FLASH_AT k_16_5, k_11_9, k_14_5
    STUN_IS 0, 60
    STUN_IS 1, 60
    STUN_IS 2, 0
    UNSTUN  0                           ; ---- both: 11.25
    UNSTUN  1
    mov     dword [rpg_keystones], 1 << KS_POWDER_KEG
    FLASH_AT k_16_5, k_11_9, k_14_5
    STUN_IS 0, 60
    STUN_IS 1, 60
    STUN_IS 2, 60
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     [rsp + 40], eax
    call    cleanup
    mov     eax, [rsp + 40]
    leave
    ret

; Who a flash at (16.5, 11.9, 14.5) stuns: the zombie where it bursts 60 steps, the Fallen King 2
; blocks east 20, never a Juggernaut elite (2 blocks west), nor a pig (3 blocks west: no foe), nor
; the zombie 6 blocks south; a longer stun is kept (the frozen zombie 2 blocks north keeps its 90), a
; shorter one lengthened to 60. Nobody loses health, 40 gold sparks fly. The distance is measured
; from the middle of the body: a flash 4.1 blocks above a zombie's middle (5 above its feet) stuns
; it, one 5.1 above does not.
; frame: the health of mob 0 @24, the player's @28, the result @40
ma_flash_rules:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 48
    call    world_clear
    call    fixture
    SPAWN   MOB_ZOMBIE, k_16_5, k_11, k_14_5    ; mob 0: where it bursts
    SPAWN   MOB_ZOMBIE, k_18_5, k_11, k_14_5    ; mob 1: 2 blocks east, the Fallen King
    mov     dword MOBF(1, MOB.type), MOB_BOSS
    SPAWN   MOB_ZOMBIE, k_14_5, k_11, k_14_5    ; mob 2: 2 blocks west, a Juggernaut
    mov     dword MOBF(2, MOB.affix), AFX_JUGGERNAUT
    SPAWN   MOB_ZOMBIE, k_16_5, k_11, k_12_5    ; mob 3: 2 blocks north, frozen
    mov     dword MOBF(3, MOB.stun), 90
    SPAWN   MOB_ZOMBIE, k_18_5, k_11, k_12_5    ; mob 4: 2.8 blocks off, stunned 10 steps
    mov     dword MOBF(4, MOB.stun), 10
    SPAWN   MOB_PIG, k_13_5, k_11, k_14_5       ; mob 5: 3 blocks west
    SPAWN   MOB_ZOMBIE, k_16_5, k_11, k_20_5    ; mob 6: 6 blocks south
    SAVE_HEALTH 0, 24
    mov     eax, [surv + SURVIVAL.health]
    mov     [rsp + 28], eax
    FLASH_AT k_16_5, k_11_9, k_14_5
    STUN_IS 0, 60
    STUN_IS 1, 20
    STUN_IS 2, 0
    STUN_IS 3, 90
    STUN_IS 4, 60
    STUN_IS 5, 0
    STUN_IS 6, 0
    EXPECT_LOST 0, 24, 0
    mov     eax, [surv + SURVIVAL.health]
    cmp     eax, [rsp + 28]
    jne     .fail
    call    fx_count
    cmp     eax, 40
    jne     .fail
    call    mobs_clear                  ; ---- the middle of the body, not the feet
    SPAWN   MOB_ZOMBIE, k_16_5, k_11, k_14_5
    FLASH_AT k_16_5, k_16_0, k_14_5
    STUN_IS 0, 60
    UNSTUN  0
    FLASH_AT k_16_5, k_17, k_14_5
    STUN_IS 0, 0
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     [rsp + 40], eax
    call    cleanup
    mov     eax, [rsp + 40]
    leave
    ret

; test_marksman_abilities: the casts of Powder Grenade, Bullseye, Fan the Hammer and Flashbang, and
; the flashbang's burst (ab_flash_at); 0 when everything held, else the number of the first scene that failed
test_marksman_abilities:
    push    rbp
    mov     rbp, rsp
    SCENE   ma_casts, 1
    SCENE   ma_flash_radius, 2
    SCENE   ma_flash_rules, 3
    xor     eax, eax
.ret:
    pop     rbp
    ret

section .rodata
align 4
k_14_5:   dd 14.5
k_18_5:   dd 18.5
k_20:     dd 20.0
k_24_5:   dd 24.5
k_m35:    dd -35.0
k_13_5:   dd 13.5                       ; 3, 5, 6 blocks off the player (16.5); 19.5, 20.5 east
k_11_5:   dd 11.5
k_10_5:   dd 10.5
k_19_5:   dd 19.5
k_20_5:   dd 20.5
k_6:      dd 6.0
k_0_6:    dd 0.6
k_12:     dd 12.0
k_0_12:   dd 0.12
k_0_2:    dd 0.2
k_0_9:    dd 0.9
k_11_9:   dd 11.9                       ; the middle of a standing zombie's body
k_16_0:   dd 16.0
k_19_0:   dd 19.0
k_22_5:   dd 22.5
knife_exp:                              ; x y z vx vy vz of knife k, facing -z from (16.5, 11, 16.5)
    dd 16.5, 12.12, 16.5,    0.0,     0.0, -30.0
    dd 16.5, 12.12, 16.5,   21.2132,  0.0, -21.2132
    dd 16.5, 12.12, 16.5,   30.0,     0.0,   0.0
    dd 16.5, 12.12, 16.5,   21.2132,  0.0,  21.2132
    dd 16.5, 12.12, 16.5,    0.0,     0.0,  30.0
    dd 16.5, 12.12, 16.5,  -21.2132,  0.0,  21.2132
    dd 16.5, 12.12, 16.5,  -30.0,     0.0,   0.0
    dd 16.5, 12.12, 16.5,  -21.2132,  0.0, -21.2132
abil_off: db 7, 9, 15                   ; the node of ability slot 1, 2, 3 within an archetype's 18

; ---- the vehicle keys in game_frame ---------------------------------------------------------------------
section .text


; frame_state(): what game_frame needs: by day in Peaceful, the cursor captured, no screen open, no button down
frame_state:
    sub     rsp, 8
    mov     dword [game_time], 6007
    mov     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL
    lea     rdi, [frame_input]
    mov     ecx, FRAMEINPUT_size
    xor     eax, eax
    rep     stosb
    mov     dword [frame_input + FRAMEINPUT.slot], -1
    mov     dword [input_captured], 1
    mov     dword [game_open_screen], 0
    mov     dword [game_heavy_s], __float32__(-1.0)
    mov     dword [game_break_progress], 0
    mov     dword [brk_y], -1
    add     rsp, 8
    ret

; frames(edi n >= 1): n times game_frame(1/60 s), which runs exactly one sim_step
frames:
    push    rbx
    mov     ebx, edi
.l:
    movss   xmm0, [k_frame_dt]
    call    game_frame
    dec     ebx
    jnz     .l
    pop     rbx
    ret

; A Warrior with Whirlwind (the key of Ability 3 is bar slot 2) beside a ground plane and a boat 2.5 blocks
; ahead of his eye. On foot the vehicle view key changes nothing, the Ability 3 key casts (cooldown 1800) and
; a right click boards the boat. Seated in the plane the Ability 3 key casts nothing, the vehicle view key flips
; plane_view each time, and a right click on the boat boards nothing: the pilot stays in the plane.
test_planes_view:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    mov     edi, ARCH_WARRIOR
    mov     esi, 5
    call    set_path
    mov     edi, AB_WHIRL
    call    learn
    mov     edi, IRON_SWORD
    call    hold
    call    planes_clear
    call    boats_clear
    call    frame_state
    SETF    [combat_stamina], 100.0
    lea     rdi, [planes]
    movss   xmm0, [k_plane_hw]
    movss   xmm1, [k_plane_h]
    xorps   xmm2, xmm2
    call    body_init
    SETF    [planes + BODY.x], 16.5
    SETF    [planes + BODY.y], 11.0
    SETF    [planes + BODY.z], 16.5
    SETF    [planes + PLANEENT.vmax], 24.0
    mov     dword [planes + PLANEENT.used], 1
    mov     dword [plane_view], 1
    mov     dword [frame_input + FRAMEINPUT.vehicle_view], 1    ; on foot: nothing flips
    mov     edi, 1
    call    frames
    cmp     dword [plane_view], 1
    jne     .fail
    mov     dword [frame_input + FRAMEINPUT.vehicle_view], 0
    mov     dword [frame_input + FRAMEINPUT.ability + 8], 1     ; the Ability 3 key casts
    mov     edi, 1
    call    frames
    cmp     dword [abilities_cd + AB_WHIRL * 4], 0
    jle     .fail
    mov     dword [frame_input + FRAMEINPUT.ability + 8], 0
    lea     rdi, [boats]                ; a boat in front of the eye (eye at y 12.62: the boat's box 12.3..12.8)
    movss   xmm0, [k_boat_hw]
    movss   xmm1, [k_boat_h]
    xorps   xmm2, xmm2
    call    body_init
    SETF    [boats + BODY.x], 16.5
    SETF    [boats + BODY.y], 12.3
    SETF    [boats + BODY.z], 14.0
    mov     dword [boats + BOATENT.used], 1
    mov     dword [frame_input + FRAMEINPUT.rmb_pressed], 1
    mov     dword [frame_input + FRAMEINPUT.rmb_held], 1
    mov     edi, 1
    call    frames
    cmp     dword [boat_riding], 1      ; on foot the click boards the boat
    jne     .fail
    call    boats_clear                 ; ---- seated in the plane
    call    abilities_reset
    SETF    [combat_stamina], 100.0
    lea     rdi, [player]
    movss   xmm0, [k_p_hw]
    movss   xmm1, [k_p_h]
    movss   xmm2, [k_p_speed]
    call    body_init
    SETF    [player + BODY.x], 16.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 16.5
    xor     edi, edi
    call    planes_board
    cmp     dword [plane_riding], 1
    jne     .fail
    lea     rdi, [boats]
    movss   xmm0, [k_boat_hw]
    movss   xmm1, [k_boat_h]
    xorps   xmm2, xmm2
    call    body_init
    SETF    [boats + BODY.x], 16.5
    SETF    [boats + BODY.y], 12.3
    SETF    [boats + BODY.z], 14.0
    mov     dword [boats + BOATENT.used], 1
    mov     edi, 1                      ; (the click is still down)
    call    frames
    cmp     dword [boat_riding], 0
    jne     .fail
    cmp     dword [plane_riding], 1
    jne     .fail
    mov     dword [frame_input + FRAMEINPUT.rmb_pressed], 0
    mov     dword [frame_input + FRAMEINPUT.rmb_held], 0
    mov     dword [frame_input + FRAMEINPUT.ability + 8], 1     ; the Ability 3 key casts nothing
    mov     edi, 1
    call    frames
    cmp     dword [abilities_cd + AB_WHIRL * 4], 0
    jne     .fail
    mov     dword [frame_input + FRAMEINPUT.ability + 8], 0
    mov     dword [frame_input + FRAMEINPUT.vehicle_view], 1    ; the view key flips the view, each press
    mov     edi, 1
    call    frames
    cmp     dword [plane_view], 0
    jne     .fail
    mov     edi, 1
    call    frames
    cmp     dword [plane_view], 1
    jne     .fail
    xor     ebx, ebx
    jmp     .done
.fail:
    mov     ebx, 1
.done:
    lea     rdi, [frame_input]
    mov     ecx, FRAMEINPUT_size
    xor     eax, eax
    rep     stosb
    call    planes_clear
    call    boats_clear
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

section .rodata
align 4
k_frame_dt: dd 0.016666668
k_plane_hw: dd 1.5
k_plane_h:  dd 1.2
k_boat_hw:  dd 0.6
k_boat_h:   dd 0.5
k_p_hw:     dd 0.3
k_p_h:      dd 1.8
k_p_speed:  dd 4.317
