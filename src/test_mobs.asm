; test_mobs.asm - mob ray picking, damage and drops, zombie attacks and parries, elites, villagers,
; the Fallen King, kill rewards, spawn rules, mob levels and elite affixes, and (0.9) entities under a
; floating origin: shifts, unloading boxes, frozen mobs and water.
%include "common.inc"
default rel

global test_mob_raycast_hits, test_mob_hurt_pig_drops_food
global test_zombie_attacks_player, test_mob_spawn_rules
global test_zombie_windup_can_be_parried, test_elite_saved_and_tougher, test_npc_immune_and_not_saved
global test_boss_phases_slam_and_summons, test_mob_kill_awards_xp_and_coins
global test_mob_levels_and_scaling, test_elite_affixes
global test_entities_rebase, test_entities_remove_box, test_mob_water_ai

extern mobs, mobs_clear, mobs_step, mob_spawn, mobs_raycast, mob_hurt, mob_count_type, mob_count_kind
extern mob_spawn_elite, folk_spawn, mob_is_hostile, mob_strike, mobs_save, mobs_load
extern mobs_populate, spawn_at_ground, mobs_shift, mobs_remove_box
extern player, body_init, rng_seed, world_clear, world_set, world_get, world_header, light_update
extern game_mode, game_time, settings, surv, survival_reset, inv, inv_clear
extern drops, drops_clear, drops_spawn, drops_shift, drops_remove_box
extern arrows, arrows_clear, arrows_spawn, arrows_shift
extern primed, tnt_clear, tnt_shift, tnt_remove_box
extern fires, fire_clear, fire_shift, fire_remove_box
extern fx_particles, fx_clear, fx_shift
extern dmgnum_clear, dmgnum_spawn, dmgnum_list, dmgnum_shift
extern abilities_reset, abilities_shift, abilities_use, abilities_step, meteor_tgt, rain_tgt
extern rpg_recompute, rpg_ext, combat_stamina, inv_sel, player_eye, player_forward
extern combat_reset, combat_hit_flags, combat_guard_t
extern rpg_state, rpg_reset
extern mob_set_level, mob_level_for, mob_dmg_mult, mob_resist, mob_affix_name
extern combat_burn_t, combat_chill_t, combat_poison_t, combat_poison, rpg_stats
extern explode_dmg_mult
extern world_origin_x, world_origin_z

section .rodata
align 4
k_half_w: dd 0.3
k_height: dd 1.8
k_speed:  dd 4.317
k_11:     dd 11.0
k_10_5:   dd 10.5
k_5_5:    dd 5.5
k_16_5:   dd 16.5
k_17_5:   dd 17.5
k_one:    dd 1.0
k_10:     dd 10.0
k_4:      dd 4.0
k_t_lo:   dd 4.69
k_t_hi:   dd 4.71
k_kb_w:   dd -6.0                       ; zombie at +x of the player: knockback runs towards -x
k_8_5:    dd 8.5
k_18_5:   dd 18.5
k_2_4:    dd 2.4
k_2_9:    dd 2.9
k_3_3:    dd 3.3
k_24:     dd 24.0
k_89:     dd 89.0
k_91:     dd 91.0
k_1e9:    dd 1.0e9
k_m1e9:   dd -1.0e9
k_6:      dd 6.0
k_1_89:   dd 1.89
k_1_91:   dd 1.91
k_2_985:  dd 2.985
k_2_995:  dd 2.995
k_3_88:   dd 3.88
k_3_89:   dd 3.89
k_0_5:    dd 0.5
k_7:      dd 7.0
k_20:     dd 20.0
k_128_5:  dd 128.5
k_48_01:  dd 48.01
k_absmask: dd 0x7FFFFFFF               ; |x| mask (loaded with movss: andps needs a register here)
k_1000_5: dd 1000.5
k_m1000_5: dd -1000.5
k_1001:   dd 1001.0
k_m999:   dd -999.0
k_488_5:  dd 488.5
k_m488_5: dd -488.5
k_489:    dd 489.0
k_m487:   dd -487.0
k_22_5:   dd 22.5
k_26_5:   dd 26.5
k_11_0:   dd 11.0
k_nan:    dd 0x7FC00000
k_inf:    dd 0x7F800000
k_65535_5: dd 65535.5
k_m65535_5: dd -65535.5
k_65536: dd 65536.0
k_m65536_5: dd -65536.5
k_256:    dd 256.0
k_255_5:  dd 255.5
k_m0_5:   dd -0.5
k_m100_5: dd -100.5
k_12_0:   dd 12.0
k_5:      dd 5.0
k_300_5:  dd 300.5
k_3_5:    dd 3.5
k_13_5:   dd 13.5
k_15_4:   dd 15.4
k_15_5:   dd 15.5
; six points around the inclusive box (0,0)-(15,15) and the cells they lie in: inside (the far
; corner), east of it, inside (the near corner), west of x = 0, south of it, and the far corner of the
; box (-16,-16)-(-1,-1)
pts:      dd 15.5, 20.0, 15.5
          dd 16.5, 20.0, 15.5
          dd 0.5, 20.0, 0.5
          dd -0.5, 20.0, 0.5
          dd 15.5, 20.0, 16.5
          dd -0.5, 20.0, -0.5
cells:    dd 15, 20, 15
          dd 16, 20, 15
          dd 0, 20, 0
          dd -1, 20, 0
          dd 15, 20, 16
          dd -1, 20, -1
; zombies frozen outside the ready columns (the world_clear square is x, z -16..271): x, z (floats) and
; the type mobs_step leaves them with when the player stands at (130.5, 10.5) (column 8, 0) and the render
; distance is 8 (keep radius 10 columns): the ones 10 columns away or less stay, further ones are forgotten
%define FAR_CASES 8
far_cases:
    dd 280.5, 10.5, MOB_ZOMBIE          ; column 17: 9 away
    dd 296.5, 10.5, MOB_ZOMBIE          ; column 18: 10 away, the keep radius itself
    dd 312.5, 10.5, MOB_NONE            ; column 19: 11 away
    dd -24.5, 10.5, MOB_ZOMBIE          ; column -2: 10 away
    dd -40.5, 10.5, MOB_NONE            ; column -3: 11 away
    dd 130.5, 296.5, MOB_NONE           ; row 18: 18 away on z, the larger axis counts
    dd 130.5, -40.5, MOB_ZOMBIE         ; row -3: 3 away
    dd 130.5, -200.5, MOB_NONE          ; row -13: 13 away

section .text

; SETF mem, float literal
%macro SETF 2
    mov     dword %1, __float32__(%2)
%endmacro

; fixture(): the state every mob test starts from (after world_clear): rng seed 1234, no mobs,
; Survival at Normal difficulty, early morning, a level-1 character without a class (the level
; the mobs spawn at), fresh survival state, STONE floor at y = 10 for x, z in 0..31
fixture:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     edi, 1234
    call    rng_seed
    call    mobs_clear
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    mov     dword [game_time], NEW_WORLD_TIME
    call    rpg_reset
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
    pop     r12
    pop     rbx
    pop     rbp
    ret

; reset_player(): standard player body (0.3 x 1.8, walk 4.317)
reset_player:
    push    rbp
    mov     rbp, rsp
    lea     rdi, [player]
    movss   xmm0, [k_half_w]
    movss   xmm1, [k_height]
    movss   xmm2, [k_speed]
    call    body_init
    pop     rbp
    ret

; SPAWN type, x constant, z constant: a mob standing at y = 11 -> eax slot or -1
%macro SPAWN 3
    mov     edi, %1
    movss   xmm0, [%2]
    movss   xmm1, [k_11]
    movss   xmm2, [%3]
    call    mob_spawn
%endmacro

; fill_box(edi x0, esi y0, edx z0, ecx x1, r8d y1, r9d z1, r10d id): world_set `id` over the inclusive box
; rbx = x0, r12d = z0, r13d = x1, r14d = y1, r15d = z1; frame: [rsp] x, [rsp+4] y, [rsp+8] z (running),
; [rsp+12] y0, [rsp+16] id
fill_box:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     ebx, edi
    mov     [rsp + 12], esi
    mov     r12d, edx
    mov     r13d, ecx
    mov     r14d, r8d
    mov     r15d, r9d
    mov     [rsp + 16], r10d
    mov     eax, esi
    mov     [rsp + 4], eax
.y:
    mov     [rsp + 8], r12d
.z:
    mov     [rsp], ebx
.x:
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    mov     edx, [rsp + 8]
    mov     ecx, [rsp + 16]
    call    world_set
    inc     dword [rsp]
    cmp     [rsp], r13d
    jle     .x
    inc     dword [rsp + 8]
    cmp     [rsp + 8], r15d
    jle     .z
    inc     dword [rsp + 4]
    cmp     [rsp + 4], r14d
    jle     .y
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; FILLB x0, y0, z0, x1, y1, z1, id: fill_box
%macro FILLB 7
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    mov     r8d, %5
    mov     r9d, %6
    mov     r10d, %7
    call    fill_box
%endmacro

; fill_layer(edi x0, esi z0, edx x1, ecx z1, r8d id): the layer y = 10 becomes `id` over the inclusive square
fill_layer:
    push    rbp
    mov     rbp, rsp
    mov     r10d, r8d
    mov     r9d, ecx
    mov     r8d, 10
    mov     ecx, edx
    mov     edx, esi
    mov     esi, 10
    call    fill_box
    pop     rbp
    ret

; GROUND_CASE type, x, z, kind, expected: ground_ok must come to `expected`
%macro GROUND_CASE 5
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    call    ground_ok
    cmp     eax, %5
    jne     .fail
%endmacro

; SETBLOCK x, y, z, id: world_set
%macro SETBLOCK 4
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    call    world_set
%endmacro

; clear_sites(): the first 16 site state records and the count are empty
clear_sites:
    lea     rdi, [world_header + WORLDHDR.sites]
    mov     ecx, 16 * SITESTATE_size
    xor     eax, eax
    rep     stosb
    mov     dword [world_header + WORLDHDR.site_count], 0
    ret

; SITE_KIND index, kind: the site state record `index` gets that SITE_* kind
%macro SITE_KIND 2
    mov     byte [world_header + WORLDHDR.sites + %1 * SITESTATE_size + SITESTATE.kind], %2
%endmacro

test_mob_raycast_hits:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 40                     ; origin[3] @0, dir[3] @16
    call    world_clear
    call    fixture
    SPAWN   MOB_ZOMBIE, k_10_5, k_10_5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    SETF    [rsp + 0], 10.5             ; ray from (10.5, 11.9, 5.5) along +z
    SETF    [rsp + 4], 11.9
    SETF    [rsp + 8], 5.5
    SETF    [rsp + 16], 0.0
    SETF    [rsp + 20], 0.0
    SETF    [rsp + 24], 1.0
    lea     rdi, [rsp]
    lea     rsi, [rsp + 16]
    movss   xmm0, [k_10]
    call    mobs_raycast
    cmp     eax, ebx
    jne     .fail
    ucomiss xmm0, [k_t_lo]              ; 4.69 < t < 4.71
    jbe     .fail
    ucomiss xmm0, [k_t_hi]
    jae     .fail
    lea     rdi, [rsp]
    lea     rsi, [rsp + 16]
    movss   xmm0, [k_4]                 ; out of reach
    call    mobs_raycast
    cmp     eax, -1
    jne     .fail
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    mobs_clear
    mov     eax, ebx
    add     rsp, 40
    pop     rbx
    pop     rbp
    ret

test_mob_hurt_pig_drops_food:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    fixture
    call    inv_clear
    call    drops_clear
    SPAWN   MOB_PIG, k_5_5, k_5_5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    imul    r12d, ebx, MOB_size
    lea     rax, [mobs]
    add     r12, rax                    ; the pig
    mov     edi, ebx
    mov     esi, 6
    xorps   xmm0, xmm0
    movss   xmm1, [k_one]               ; hit direction (0, 1)
    call    mob_hurt
    cmp     eax, 1
    jne     .fail
    cmp     dword [r12 + MOB.health], 4 ; 10 - 6
    jne     .fail
    cmp     dword [r12 + MOB.hurt], 10  ; hurt window in steps
    jne     .fail
    mov     edi, ebx                    ; still hurting: ignored
    mov     esi, 6
    xorps   xmm0, xmm0
    movss   xmm1, [k_one]
    call    mob_hurt
    test    eax, eax
    jnz     .fail
    cmp     dword [r12 + MOB.type], MOB_PIG
    jne     .fail
    mov     dword [r12 + MOB.hurt], 0
    mov     edi, ebx
    mov     esi, 6
    xorps   xmm0, xmm0
    movss   xmm1, [k_one]
    call    mob_hurt
    cmp     eax, 1
    jne     .fail
    cmp     dword [r12 + MOB.type], MOB_NONE
    jne     .fail
    cmp     byte [drops + DROP.id], PORKCHOP ; dropped on the ground, not in the inventory
    jne     .fail
    movzx   eax, byte [drops + DROP.count]
    dec     eax
    cmp     eax, 2                      ; 1..3
    ja      .fail
    cmp     byte [inv + INVENTORY.slots + ITEMSTACK.count], 0
    jne     .fail
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    mobs_clear
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

test_zombie_attacks_player:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    call    reset_player
    call    combat_reset                ; the guard is down: the blow is not parried
    mov     dword [game_time], 40000    ; night: the zombie must not burn during the test
    SETF    [player + BODY.x], 16.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 16.5
    SPAWN   MOB_ZOMBIE, k_17_5, k_16_5
    test    eax, eax
    js      .fail
    call    mobs_step                            ; in reach: the arm goes up, no blow yet
    cmp     dword [surv + SURVIVAL.health], 20
    jne     .fail
    cmp     dword [mobs + MOB.windup], 0
    jle     .fail
    mov     ebx, 20
.windup:                                         ; ...the blow comes down when the 20 steps are up
    call    mobs_step
    dec     ebx
    jnz     .windup
    cmp     dword [surv + SURVIVAL.health], 17   ; Normal difficulty hits for 3
    jne     .fail
    movss   xmm0, [player + BODY.kbx]            ; knocked away from the zombie
    ucomiss xmm0, [k_kb_w]
    jne     .fail
    cmp     dword [player + BODY.kbz], 0
    jne     .fail
    mov     ebx, 10
.again:
    call    mobs_step
    dec     ebx
    jnz     .again
    cmp     dword [surv + SURVIVAL.health], 17   ; the 60-step cooldown holds
    jne     .fail
    mov     edi, MOB_ZOMBIE                      ; ...and the zombie is still there
    call    mob_count_type
    cmp     eax, 1
    jne     .fail
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    mobs_clear
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; Spawn rules. A night over a field of grass makes 1..12 hostile mobs, none at Peaceful; mobs_populate
; scatters 10 pigs and 6 chickens within 48 blocks of the player; and spawn_at_ground, asked about single
; cells, stands a mob on the top block (in the cell above it) or, for a TALL_GRASS / SNOW_LAYER top, in
; that cell on the block below; refuses water, bedrock and every kind of leaves for a hostile type and
; anything but grass for a passive one; refuses a torch-lit cell (block light 8+) to hostile types only;
; refuses a column that is not ready; and wants a spider's 3 x 3 cells free (plants are free).
test_mob_spawn_rules:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    mov     edi, 80                     ; GRASS over the layer y = 10, 97 x 97 blocks around the player
    mov     esi, 80
    mov     edx, 176
    mov     ecx, 176
    mov     r8d, GRASS
    call    fill_layer
    call    reset_player
    SETF    [player + BODY.x], 128.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 128.5
    mov     dword [game_time], 40000    ; deep night
    mov     ebx, 600
.night:
    call    mobs_step
    inc     dword [game_time]
    dec     ebx
    jnz     .night
    mov     edi, 1                      ; hostile mobs: zombies, skeletons, creepers, spiders
    call    mob_count_kind
    dec     eax
    cmp     eax, 11                     ; 1..12
    ja      .fail
    call    mobs_clear
    mov     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL
    mov     ebx, 600
.peaceful:
    call    mobs_step
    inc     dword [game_time]
    dec     ebx
    jnz     .peaceful
    mov     edi, 1
    call    mob_count_kind
    test    eax, eax
    jnz     .fail
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    call    mobs_clear                  ; a new world's animals: 10 pigs, 6 chickens, all near the player
    call    mobs_populate
    mov     edi, MOB_PIG
    call    mob_count_type
    cmp     eax, 10
    jne     .fail
    mov     edi, MOB_CHICKEN
    call    mob_count_type
    cmp     eax, 6
    jne     .fail
    call    within_48
    test    eax, eax
    jz      .fail
    call    mobs_clear
    GROUND_CASE MOB_ZOMBIE, 100, 100, 0, 1      ; grass: it stands in the cell above
    GROUND_CASE MOB_PIG, 100, 100, 1, 1
    SETBLOCK 101, 11, 100, TALL_GRASS
    GROUND_CASE MOB_ZOMBIE, 101, 100, 0, 1      ; a plant on top: it stands in the plant's cell...
    GROUND_CASE MOB_PIG, 101, 100, 1, 1         ; ...on the grass under it
    SETBLOCK 102, 10, 100, STONE
    SETBLOCK 102, 11, 100, SNOW_LAYER
    GROUND_CASE MOB_ZOMBIE, 102, 100, 0, 1      ; stone under a snow layer: fine for a zombie...
    GROUND_CASE MOB_PIG, 102, 100, 1, 0         ; ...not for a pig
    SETBLOCK 103, 10, 100, WATER
    GROUND_CASE MOB_ZOMBIE, 103, 100, 0, 0      ; water is no ground
    GROUND_CASE MOB_PIG, 103, 100, 1, 0
    SETBLOCK 104, 10, 100, LEAVES
    GROUND_CASE MOB_ZOMBIE, 104, 100, 0, 0      ; nor are leaves
    GROUND_CASE MOB_PIG, 104, 100, 1, 0
    SETBLOCK 105, 10, 100, SAND
    GROUND_CASE MOB_ZOMBIE, 105, 100, 0, 1      ; sand is for hostile types
    GROUND_CASE MOB_PIG, 105, 100, 1, 0
    SETBLOCK 106, 10, 100, BEDROCK
    GROUND_CASE MOB_ZOMBIE, 106, 100, 0, 0
    SETBLOCK 107, 10, 100, PINE_LEAVES
    GROUND_CASE MOB_ZOMBIE, 107, 100, 0, 0
    SETBLOCK 108, 10, 100, BIRCH_LEAVES
    GROUND_CASE MOB_ZOMBIE, 108, 100, 0, 0
    GROUND_CASE MOB_ZOMBIE, 300, 100, 0, 0      ; no ready column there
    SETBLOCK 110, 11, 100, TORCH                ; block light 8+ around a torch: no hostile mob spawns
    call    light_update
    GROUND_CASE MOB_ZOMBIE, 111, 100, 0, 0
    GROUND_CASE MOB_PIG, 111, 100, 1, 1         ; ...a pig does not mind
    GROUND_CASE MOB_ZOMBIE, 125, 100, 0, 1      ; away from it, in the dark: it does
    GROUND_CASE MOB_SPIDER, 140, 120, 0, 1      ; a spider needs its 3 x 3 cells free
    SETBLOCK 141, 11, 120, STONE
    GROUND_CASE MOB_SPIDER, 140, 120, 0, 0
    GROUND_CASE MOB_ZOMBIE, 140, 120, 0, 1
    SETBLOCK 150, 11, 120, TALL_GRASS           ; plants are free
    SETBLOCK 151, 11, 120, TALL_GRASS
    GROUND_CASE MOB_SPIDER, 150, 120, 0, 1
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    call    mobs_clear
    call    arrows_clear                ; skeletons and creepers may have left arrows, drops, TNT
    call    tnt_clear
    call    drops_clear
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ground_ok(edi type, esi x, edx z, ecx kind) -> eax 1 when spawn_at_ground put a mob at (x + 0.5, 11,
; z + 0.5), 0 when it refused or put it anywhere else; no mob is left behind
ground_ok:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, esi
    mov     r12d, edx
    call    spawn_at_ground
    test    eax, eax
    js      .no
    mov     edi, eax
    call    mob_ptr
    cvtsi2ss xmm0, ebx
    addss   xmm0, [k_0_5]
    ucomiss xmm0, [rax + BODY.x]
    jne     .no
    cvtsi2ss xmm0, r12d
    addss   xmm0, [k_0_5]
    ucomiss xmm0, [rax + BODY.z]
    jne     .no
    movss   xmm0, [k_11_0]
    ucomiss xmm0, [rax + BODY.y]
    jne     .no
    mov     ebx, 1
    jmp     .out
.no:
    xor     ebx, ebx
.out:
    call    mobs_clear
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; within_48() -> eax 1 when every live mob lies within 48.01 blocks of (128.5, 128.5) in x and z
within_48:
    mov     esi, MAX_MOBS
    lea     rcx, [mobs]
    movss   xmm1, [k_absmask]
.l:
    cmp     dword [rcx + MOB.type], MOB_NONE
    je      .n
    movss   xmm0, [rcx + BODY.x]
    subss   xmm0, [k_128_5]
    andps   xmm0, xmm1
    ucomiss xmm0, [k_48_01]
    ja      .bad
    movss   xmm0, [rcx + BODY.z]
    subss   xmm0, [k_128_5]
    andps   xmm0, xmm1
    ucomiss xmm0, [k_48_01]
    ja      .bad
.n:
    add     rcx, MOB_size
    dec     esi
    jnz     .l
    mov     eax, 1
    ret
.bad:
    xor     eax, eax
    ret

; ---- 0.6: telegraphs, parries, elites, villagers, the Fallen King, kill rewards -----------------

section .bss
alignb 16
hdr:        resb WORLDHDR_size          ; stands in for a WORLDHDR: mobs_save / mobs_load touch only
                                        ; .mob_count and .mobs

section .text

; mob_ptr(edi idx) -> rax the mob in that slot
mob_ptr:
    imul    eax, edi, MOB_size
    lea     rcx, [mobs]
    add     rax, rcx
    ret

; strike(edi idx, esi dmg) -> eax mob_strike's result, knocking along +z
strike:
    sub     rsp, 8
    xorps   xmm0, xmm0
    movss   xmm1, [k_one]
    call    mob_strike
    add     rsp, 8
    ret

; drops_of(edi item) -> eax item entities lying in the world, edx their total count
drops_of:
    xor     eax, eax
    xor     edx, edx
    lea     rcx, [drops]
    mov     esi, MAX_DROPS
.l:
    cmp     [rcx + DROP.id], dil
    jne     .next
    inc     eax
    movzx   r8d, byte [rcx + DROP.count]
    add     edx, r8d
.next:
    add     rcx, DROP_size
    dec     esi
    jnz     .l
    ret

; arrow_stats() -> eax live arrows, edx 1 when every one is a mob's with damage 4, xmm0 the spread
; of their z velocities (max - min)
arrow_stats:
    xor     eax, eax
    mov     edx, 1
    movss   xmm1, [k_1e9]
    movss   xmm2, [k_m1e9]
    lea     rcx, [arrows]
    mov     esi, MAX_ARROWS
.l:
    cmp     dword [rcx + ARROWENT.live], 0
    je      .next
    inc     eax
    cmp     dword [rcx + ARROWENT.owner], 1
    jne     .bad
    cmp     dword [rcx + ARROWENT.damage], 4
    je      .ok
.bad:
    xor     edx, edx
.ok:
    movss   xmm0, [rcx + ARROWENT.vz]
    minss   xmm1, xmm0
    maxss   xmm2, xmm0
.next:
    add     rcx, ARROWENT_size
    dec     esi
    jnz     .l
    movaps  xmm0, xmm2
    subss   xmm0, xmm1
    ret

; kill_zombie(edi origin) -> eax 0 when a zombie spawned at (8.5, 11, 8.5) with that dungeon origin
; died to a 100-point strike
kill_zombie:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     r12d, edi
    SPAWN   MOB_ZOMBIE, k_8_5, k_8_5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, eax
    call    mob_ptr
    mov     [rax + MOB.origin], r12d
    mov     edi, ebx
    mov     esi, 100
    call    strike
    cmp     eax, 1
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; A zombie in reach raises its arm for 20 steps before the blow. A player whose guard goes up on the
; very last of them parries it: nothing taken, the zombie reels back and stands dazed for 50 steps.
test_zombie_windup_can_be_parried:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    fixture
    call    reset_player
    call    combat_reset                ; guard down, no riposte, full stamina
    mov     dword [game_time], 40000    ; night: the zombie must not burn during the test
    SETF    [player + BODY.x], 16.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 16.5
    SETF    [player + BODY.yaw], 90.0   ; facing +x, towards the zombie: its blow is frontal
    SPAWN   MOB_ZOMBIE, k_17_5, k_16_5
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax                    ; the zombie
    call    mobs_step                   ; in reach: the arm goes up
    cmp     dword [r12 + MOB.windup], 20
    jne     .fail
    cmp     dword [r12 + MOB.input + INPUT.fwd], 0  ; and it stands still to swing
    jne     .fail
    mov     ebx, 19
.raise:                                 ; windup 19 .. 1: no blow yet
    call    mobs_step
    dec     ebx
    jnz     .raise
    cmp     dword [r12 + MOB.windup], 1
    jne     .fail
    cmp     dword [surv + SURVIVAL.health], 20
    jne     .fail
    mov     dword [combat_guard_t], 0   ; the guard comes up on the very last step
    call    mobs_step                   ; the blow lands on a fresh guard
    cmp     dword [surv + SURVIVAL.health], 20      ; parried: nothing taken
    jne     .fail
    cmp     dword [r12 + MOB.stun], 50
    jne     .fail
    cmp     dword [r12 + MOB.windup], 0
    jne     .fail
    movss   xmm0, [r12 + BODY.kbx]      ; the zombie stands at +x of the player: it reels back along +x
    ucomiss xmm0, [k_one]
    jbe     .fail
    mov     ebx, 10
.dazed:                                 ; stunned: no steps toward the player, no new blow
    call    mobs_step
    cmp     dword [r12 + MOB.input + INPUT.fwd], 0
    jne     .fail
    cmp     dword [r12 + MOB.windup], 0
    jne     .fail
    dec     ebx
    jnz     .dazed
    cmp     dword [surv + SURVIVAL.health], 20
    jne     .fail
    cmp     dword [r12 + MOB.stun], 40
    jne     .fail
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    combat_reset
    call    mobs_clear
    call    reset_player                ; yaw 90 was set
    call    fx_clear                    ; a parry throws sparks
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; An elite zombie has 2.5 x the health and moves faster, winds up for 16 steps and hits 1.5 x
; harder (rounded); it survives a save and load as an elite with its level and affixes, its health
; clamped to 2.5 x base; a record without the elite bit is a plain zombie whatever its affix bits
; say; villager records are not loaded. Its affix is pinned to ARMORED, which changes none of that
; (a rolled one could add health, speed, a shorter wind-up or elemental damage). A saved mob must lie at
; a finite place: |x| and |z| below 65536 (negative cells are fine) and 0 <= y < 256, or it is skipped.
test_elite_saved_and_tougher:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    fixture
    call    reset_player
    call    combat_reset
    call    inv_clear                   ; no armor
    mov     dword [game_time], 40000
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_8_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_8_5]
    call    mob_spawn_elite
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax                    ; the elite
    cmp     dword [r12 + MOB.affix], 0
    je      .fail                       ; it rolled an affix
    mov     dword [r12 + MOB.affix], AFX_ARMORED
    mov     edi, ebx
    mov     esi, 1
    call    mob_set_level               ; the health of an elite with that affix
    cmp     dword [r12 + MOB.health], 50            ; 2.5 x 20
    jne     .fail
    cmp     dword [r12 + MOB.max_health], 50
    jne     .fail
    cmp     dword [r12 + MOB.elite], 1
    jne     .fail
    movss   xmm0, [r12 + BODY.speed]    ; 1.15 x 2.6 = 2.99 (a rolled SWIFT: more)
    ucomiss xmm0, [k_2_9]
    jbe     .fail
    lea     rdi, [hdr]
    call    mobs_save
    cmp     dword [hdr + WORLDHDR.mob_count], 1
    jne     .fail
    cmp     dword [hdr + WORLDHDR.mobs + MOBSAVE.type], MOB_ZOMBIE | MOB_ELITE_BIT | (1 << MS_LEVEL_SHIFT) | (AFX_ARMORED << MS_AFFIX_SHIFT)
    jne     .fail
    mov     dword [r12 + MOB.health], 30            ; wounded: the 30 survives the round trip
    lea     rdi, [hdr]
    call    mobs_save
    call    mobs_clear
    lea     rdi, [hdr]
    call    mobs_load
    lea     r12, [mobs]
    cmp     dword [r12 + MOB.type], MOB_ZOMBIE
    jne     .fail
    cmp     dword [r12 + MOB.elite], 1
    jne     .fail
    cmp     dword [r12 + MOB.affix], AFX_ARMORED
    jne     .fail
    cmp     dword [r12 + MOB.level], 1
    jne     .fail
    cmp     dword [r12 + MOB.health], 30
    jne     .fail
    cmp     dword [r12 + MOB.max_health], 50
    jne     .fail
    mov     dword [hdr + WORLDHDR.mobs + MOBSAVE.health], 999   ; an inflated record clamps to 2.5 x base
    call    mobs_clear
    lea     rdi, [hdr]
    call    mobs_load
    cmp     dword [mobs + MOB.health], 50
    jne     .fail
    mov     dword [hdr + WORLDHDR.mobs + MOBSAVE.type], MOB_ZOMBIE | (1 << MS_LEVEL_SHIFT) | (AFX_JUGGERNAUT << MS_AFFIX_SHIFT)
    call    mobs_clear                  ; without the elite bit: a plain 20, the affix bits are ignored
    lea     rdi, [hdr]
    call    mobs_load
    cmp     dword [mobs + MOB.elite], 0
    jne     .fail
    cmp     dword [mobs + MOB.affix], 0
    jne     .fail
    cmp     dword [mobs + MOB.health], 20
    jne     .fail
    mov     dword [hdr + WORLDHDR.mobs + MOBSAVE.type], MOB_FOLK | MOB_ELITE_BIT   ; not a saved type
    call    mobs_clear
    lea     rdi, [hdr]
    call    mobs_load
    cmp     dword [mobs + MOB.type], MOB_NONE
    jne     .fail
    call    mobs_clear                  ; an elite next to the player: 16-step wind-up, blow of 4
    SETF    [player + BODY.x], 16.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 16.5
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_17_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_16_5]
    call    mob_spawn_elite
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax
    mov     dword [r12 + MOB.affix], AFX_ARMORED
    call    mobs_step
    cmp     dword [r12 + MOB.windup], 16
    jne     .fail
    cmp     dword [surv + SURVIVAL.health], 20
    jne     .fail
    mov     ebx, 16
.swing:
    call    mobs_step
    dec     ebx
    jnz     .swing
    cmp     dword [surv + SURVIVAL.health], 16      ; Normal hits for 3, x 1.5 = 4.5 -> 4
    jne     .fail
    movss   xmm0, [k_m100_5]                ; ---- where a saved mob may be
    movss   xmm1, [k_20]
    movss   xmm2, [k_300_5]
    call    load_pig
    cmp     eax, 1
    jne     .fail                           ; west of the origin is fine
    movss   xmm0, [k_65535_5]
    movss   xmm1, [k_255_5]
    movss   xmm2, [k_m65535_5]
    call    load_pig
    cmp     eax, 1
    jne     .fail                           ; the very edge of what is accepted
    movss   xmm0, [k_65536]
    movss   xmm1, [k_20]
    xorps   xmm2, xmm2
    call    load_pig
    test    eax, eax
    jnz     .fail                           ; x too far east
    xorps   xmm0, xmm0
    movss   xmm1, [k_20]
    movss   xmm2, [k_m65536_5]
    call    load_pig
    test    eax, eax
    jnz     .fail                           ; z too far west
    xorps   xmm0, xmm0
    movss   xmm1, [k_256]
    xorps   xmm2, xmm2
    call    load_pig
    test    eax, eax
    jnz     .fail                           ; above the world
    xorps   xmm0, xmm0
    movss   xmm1, [k_m0_5]
    xorps   xmm2, xmm2
    call    load_pig
    test    eax, eax
    jnz     .fail                           ; below it
    movss   xmm0, [k_nan]
    movss   xmm1, [k_20]
    xorps   xmm2, xmm2
    call    load_pig
    test    eax, eax
    jnz     .fail                           ; NaN
    xorps   xmm0, xmm0
    movss   xmm1, [k_20]
    movss   xmm2, [k_inf]
    call    load_pig
    test    eax, eax
    jnz     .fail                           ; infinity
    xorps   xmm0, xmm0
    movss   xmm1, [k_nan]
    xorps   xmm2, xmm2
    call    load_pig
    test    eax, eax
    jnz     .fail                           ; a NaN height
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    combat_reset
    call    mobs_clear
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; Villagers cannot be hurt, are not saved, stroll back toward their home when they stray beyond
; 6 blocks and turn to a player within 4. mob_is_hostile tells hostile mobs from the rest.
; Frame: slots [rsp] merchant, [rsp+4] elder, [rsp+8] pig, [rsp+12] zombie, [rsp+16] boss.
test_npc_immune_and_not_saved:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 32
    call    world_clear
    call    fixture
    call    reset_player
    call    combat_reset
    mov     dword [game_time], 40000
    SETF    [player + BODY.x], 2.5      ; far from everyone
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 2.5
    mov     edi, FAC_VILLAGERS
    mov     esi, ROLE_TRADER
    xor     edx, edx
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_16_5]
    call    folk_spawn
    test    eax, eax
    js      .fail
    mov     [rsp], eax
    mov     edi, FAC_VILLAGERS
    mov     esi, ROLE_LEADER
    xor     edx, edx
    movss   xmm0, [k_10_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_16_5]
    call    folk_spawn
    test    eax, eax
    js      .fail
    mov     [rsp + 4], eax
    SPAWN   MOB_PIG, k_5_5, k_5_5
    test    eax, eax
    js      .fail
    mov     [rsp + 8], eax
    mov     edi, [rsp]
    call    mob_ptr
    mov     r12, rax                    ; the merchant
    cmp     dword [r12 + MOB.health], 20
    jne     .fail
    mov     byte [combat_hit_flags], HF_PLAYER
    mov     edi, [rsp]
    mov     esi, 5
    call    strike                      ; a villager shrugs it off
    test    eax, eax
    jnz     .fail
    mov     edi, [rsp]
    mov     esi, 5
    xorps   xmm0, xmm0
    movss   xmm1, [k_one]
    call    mob_hurt
    test    eax, eax
    jnz     .fail
    cmp     dword [r12 + MOB.health], 20
    jne     .fail
    cmp     dword [r12 + MOB.hurt], 0
    jne     .fail
    cmp     dword [r12 + MOB.tagged], 0
    jne     .fail
    cmp     byte [combat_hit_flags], 0  ; the flags are consumed either way
    jne     .fail
    cmp     dword [r12 + MOB.type], MOB_FOLK
    jne     .fail
    mov     edi, [rsp]
    call    mob_is_hostile
    test    eax, eax
    jnz     .fail
    mov     edi, [rsp + 8]
    call    mob_is_hostile              ; a pig is no enemy either
    test    eax, eax
    jnz     .fail
    lea     rdi, [hdr]
    call    mobs_save                   ; the villagers are skipped: only the pig is saved
    cmp     dword [hdr + WORLDHDR.mob_count], 1
    jne     .fail
    cmp     dword [hdr + WORLDHDR.mobs + MOBSAVE.type], MOB_PIG | (1 << MS_LEVEL_SHIFT)   ; a level-1 pig
    jne     .fail
    SETF    [r12 + BODY.x], 24.5        ; 8 blocks east of home (16.5, 16.5): it walks back
    mov     ebx, 60
.home:
    call    mobs_step
    dec     ebx
    jnz     .home
    movss   xmm0, [r12 + BODY.x]
    ucomiss xmm0, [k_24]
    jae     .fail                       ; moved at least half a block west
    SETF    [r12 + BODY.x], 16.5        ; back home, the player 3 blocks east: it stands and faces him
    SETF    [r12 + BODY.z], 16.5
    SETF    [player + BODY.x], 19.5
    SETF    [player + BODY.z], 16.5
    call    mobs_step
    cmp     dword [r12 + MOB.input + INPUT.fwd], 0
    jne     .fail
    movss   xmm0, [r12 + BODY.yaw]      ; heading 90 degrees: forward is +x
    ucomiss xmm0, [k_89]
    jb      .fail
    ucomiss xmm0, [k_91]
    ja      .fail
    SETF    [player + BODY.x], 2.5      ; the player leaves before the hostile mobs appear
    SETF    [player + BODY.z], 2.5
    SPAWN   MOB_ZOMBIE, k_8_5, k_8_5
    test    eax, eax
    js      .fail
    mov     [rsp + 12], eax
    SPAWN   MOB_BOSS, k_16_5, k_18_5
    test    eax, eax
    js      .fail
    mov     [rsp + 16], eax
    mov     edi, [rsp + 12]
    call    mob_is_hostile
    cmp     eax, 1
    jne     .fail
    mov     edi, [rsp + 16]
    call    mob_is_hostile
    cmp     eax, 1
    jne     .fail
    mov     edi, [rsp + 4]
    call    mob_is_hostile              ; the elder is not
    test    eax, eax
    jnz     .fail
    mov     edi, MAX_MOBS - 1           ; an empty slot
    call    mob_is_hostile
    test    eax, eax
    jnz     .fail
    mov     edi, MAX_MOBS               ; no such slot
    call    mob_is_hostile
    test    eax, eax
    jnz     .fail
    mov     edi, -1
    call    mob_is_hostile
    test    eax, eax
    jnz     .fail
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    mov     byte [combat_hit_flags], 0
    call    combat_reset
    call    mobs_clear
    mov     eax, ebx
    add     rsp, 32
    pop     r12
    pop     rbx
    pop     rbp
    ret

; The Fallen King (Normal): 300 health, a 36-step wind-up and a slam of 8 on a player 2 blocks
; away (one slam in 40 steps, the 70-step cooldown holds the next), skeletons rise when timer_a
; runs out, a volley of 5 arrows comes every 240 steps from phase 2 on, and below a third of his
; health the wind-up shortens to 24. A boss that Thorns kill in the middle of his slam summons and
; fires nothing that step.
test_boss_phases_slam_and_summons:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    fixture
    call    reset_player
    call    combat_reset
    call    inv_clear                   ; no armor
    call    arrows_clear
    call    rpg_reset                   ; class 0: no armor bonus
    mov     dword [game_time], 40000
    SETF    [player + BODY.x], 18.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 16.5
    SPAWN   MOB_BOSS, k_16_5, k_16_5
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax                    ; the boss, 2 blocks from the player
    cmp     dword [r12 + MOB.health], 300
    jne     .fail
    cmp     dword [r12 + MOB.max_health], 300
    jne     .fail
    cmp     dword [r12 + MOB.timer_a], 600
    jne     .fail
    cmp     dword [r12 + MOB.timer_b], 240
    jne     .fail
    call    mobs_step                   ; the fists go up: wind-up 36, standing still
    cmp     dword [r12 + MOB.windup], 36
    jne     .fail
    movss   xmm0, [r12 + BODY.speed]    ; phase 1 walks at 2.4
    ucomiss xmm0, [k_2_4]
    jne     .fail
    mov     ebx, 39
.slam:                                  ; 40 steps in all: one slam of 8, no second
    call    mobs_step
    dec     ebx
    jnz     .slam
    cmp     dword [surv + SURVIVAL.health], 12
    jne     .fail
    cmp     dword [r12 + MOB.windup], 0
    jne     .fail
    cmp     dword [r12 + MOB.cooldown], 0
    jle     .fail
    mov     dword [r12 + MOB.timer_b], 1
    call    mobs_step                   ; phase 1 keeps to melee: the volley timer only recycles
    cmp     dword [r12 + MOB.timer_b], 240
    jne     .fail
    call    arrow_stats
    test    eax, eax
    jnz     .fail
    mov     dword [r12 + MOB.timer_a], 1
    call    mobs_step                   ; the timer runs out: two skeletons
    mov     edi, MOB_SKELETON
    call    mob_count_type
    cmp     eax, 2
    jne     .fail
    cmp     dword [r12 + MOB.timer_a], 600
    jne     .fail
    mov     dword [r12 + MOB.health], 90            ; 30 %: phase 3
    mov     dword [r12 + MOB.cooldown], 0
    mov     dword [r12 + MOB.windup], 0
    call    mobs_step
    cmp     dword [r12 + MOB.windup], 24
    jne     .fail
    movss   xmm0, [r12 + BODY.speed]    ; 1.4 x 2.4 = 3.36
    ucomiss xmm0, [k_3_3]
    jbe     .fail
    lea     rax, [mobs]                 ; the skeletons go (their own arrows would muddy the count)
    mov     ecx, MAX_MOBS
.skeletons:
    cmp     dword [rax + MOB.type], MOB_SKELETON
    jne     .not_skeleton
    mov     dword [rax + MOB.type], MOB_NONE
.not_skeleton:
    add     rax, MOB_size
    dec     ecx
    jnz     .skeletons
    call    arrows_clear
    mov     dword [r12 + MOB.timer_b], 1
    call    mobs_step                   ; phase 3: a volley of 5 arrows of 4, fanned about the aim
    call    arrow_stats
    cmp     eax, 5
    jne     .fail
    test    edx, edx
    jz      .fail
    ucomiss xmm0, [k_10]                ; the fan spans well over 10 blocks/s sideways
    jbe     .fail
    call    mobs_clear                  ; ---- Thorns kill the boss mid-slam: no summon, no volley
    call    arrows_clear
    call    reset_player
    call    survival_reset
    call    combat_reset
    SETF    [player + BODY.x], 18.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 16.5
    SPAWN   MOB_BOSS, k_16_5, k_16_5
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax
    mov     dword [r12 + MOB.health], 1
    mov     dword [r12 + MOB.windup], 1     ; the slam lands this step
    mov     dword [r12 + MOB.cooldown], 0
    mov     dword [r12 + MOB.timer_a], 0    ; a summon and a volley are due
    mov     dword [r12 + MOB.timer_b], 0
    mov     dword [rpg_stats + STAT_THORNS * 4], 1000
    call    mobs_step
    mov     dword [rpg_stats + STAT_THORNS * 4], 0
    cmp     dword [r12 + MOB.type], MOB_NONE
    jne     .fail                           ; the thorns killed him
    mov     edi, MOB_SKELETON
    call    mob_count_type
    test    eax, eax
    jnz     .fail                           ; the dead boss summoned nobody
    call    arrow_stats
    test    eax, eax
    jnz     .fail                           ; and fired nothing
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    mobs_clear
    call    arrows_clear                ; the skeletons may have shot
    call    fx_clear                    ; the slam's blast
    call    combat_reset
    call    rpg_reset
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; Kills the player had a hand in (combat_hit_flags HF_PLAYER) pay XP (zombie 10) and consume the
; flags; untagged kills pay none; a hit tags a mob for 200 steps and raises its health bar for 180.
; Hostile mobs drop coins (one every other kill: 1 + level / 10, an elite 3-5 + level / 5; gold find
; multiplies them); the Fallen King drops 30 + his level coins and 4 diamonds (his gear is gear.asm's)
; and the crypt he was born in (MOB.origin = site state index + 1) is recorded as cleared, while a boss
; born at no site touches no record.
test_mob_kill_awards_xp_and_coins:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    fixture
    call    reset_player
    call    combat_reset
    call    rpg_reset
    call    drops_clear
    mov     dword [game_time], 40000    ; night: nothing burns
    mov     byte [rpg_state + RPGSAVE.class], CLASS_WARRIOR
    mov     byte [combat_hit_flags], HF_PLAYER
    SPAWN   MOB_ZOMBIE, k_8_5, k_8_5
    test    eax, eax
    js      .fail
    mov     edi, eax
    mov     esi, 100
    call    strike
    cmp     eax, 1
    jne     .fail
    cmp     byte [combat_hit_flags], 0
    jne     .fail
    cmp     dword [rpg_state + RPGSAVE.xp], 10      ; a zombie is worth 10
    jne     .fail
    SPAWN   MOB_ZOMBIE, k_8_5, k_8_5    ; untagged (no flags): no XP
    test    eax, eax
    js      .fail
    mov     edi, eax
    mov     esi, 100
    call    strike
    cmp     eax, 1
    jne     .fail
    cmp     dword [rpg_state + RPGSAVE.xp], 10
    jne     .fail
    mov     byte [combat_hit_flags], HF_PLAYER      ; a wound tags the mob, then the timers run down
    SPAWN   MOB_ZOMBIE, k_8_5, k_8_5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, eax
    mov     esi, 1
    call    strike
    mov     edi, ebx
    call    mob_ptr
    mov     r12, rax
    cmp     dword [r12 + MOB.health], 19
    jne     .fail
    cmp     dword [r12 + MOB.tagged], 200
    jne     .fail
    cmp     dword [r12 + MOB.bar], 180
    jne     .fail
    call    mobs_step
    cmp     dword [r12 + MOB.tagged], 199
    jne     .fail
    cmp     dword [r12 + MOB.bar], 179
    jne     .fail
    mov     dword [r12 + MOB.tagged], 0 ; a tick of burning (HF_DOT): it still tags the mob and raises
    mov     dword [r12 + MOB.bar], 0    ; its bar, but opens no hurt window and shoves and lifts nothing
    mov     dword [r12 + MOB.hurt], 0
    mov     dword [r12 + BODY.kbz], 0
    mov     dword [r12 + BODY.on_ground], 1
    mov     dword [r12 + BODY.vy], 0
    mov     byte [combat_hit_flags], HF_PLAYER | HF_DOT | (ELEM_FIRE << HF_ELEM_SHIFT)
    mov     edi, ebx
    mov     esi, 2
    xorps   xmm0, xmm0
    movss   xmm1, [k_one]
    call    mob_hurt
    cmp     eax, 1
    jne     .fail
    cmp     dword [r12 + MOB.health], 17            ; 19 - 2
    jne     .fail
    cmp     dword [r12 + MOB.hurt], 0
    jne     .fail
    cmp     dword [r12 + BODY.kbz], 0
    jne     .fail
    cmp     dword [r12 + BODY.vy], 0
    jne     .fail
    cmp     dword [r12 + MOB.tagged], 200
    jne     .fail
    cmp     dword [r12 + MOB.bar], 180
    jne     .fail
    cmp     byte [combat_hit_flags], 0
    jne     .fail
    mov     byte [combat_hit_flags], HF_PLAYER | HF_DOT     ; the next tick lands at once
    mov     edi, ebx
    mov     esi, 2
    xorps   xmm0, xmm0
    movss   xmm1, [k_one]
    call    mob_hurt
    cmp     eax, 1
    jne     .fail
    cmp     dword [r12 + MOB.health], 15
    jne     .fail
    mov     byte [combat_hit_flags], HF_PLAYER | HF_DOT     ; a burning kill pays XP like any other
    mov     edi, ebx
    mov     esi, 100
    xorps   xmm0, xmm0
    movss   xmm1, [k_one]
    call    mob_hurt
    cmp     eax, 1
    jne     .fail
    cmp     dword [r12 + MOB.type], MOB_NONE
    jne     .fail
    cmp     dword [rpg_state + RPGSAVE.xp], 20
    jne     .fail
    SPAWN   MOB_PIG, k_5_5, k_5_5       ; a burning animal does not bolt, a blow sends it fleeing
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax
    mov     byte [combat_hit_flags], HF_DOT
    mov     edi, ebx
    mov     esi, 1
    xorps   xmm0, xmm0
    movss   xmm1, [k_one]
    call    mob_hurt
    cmp     eax, 1
    jne     .fail
    cmp     dword [r12 + MOB.panic], 0
    jne     .fail
    mov     edi, ebx
    mov     esi, 1
    xorps   xmm0, xmm0
    movss   xmm1, [k_one]
    call    mob_hurt
    cmp     eax, 1
    jne     .fail
    cmp     dword [r12 + MOB.panic], 180
    jne     .fail
    call    mobs_clear
    call    drops_clear                 ; coins: 12 untagged kills, a coin every other time
    mov     ebx, 12
.round:
    xor     edi, edi
    call    kill_zombie
    test    eax, eax
    jnz     .fail
    dec     ebx
    jnz     .round
    mov     edi, GOLD_COIN
    call    drops_of
    dec     eax
    cmp     eax, 10                     ; between 1 and 11 coins, never one per kill nor none
    ja      .fail
    call    drops_clear
    mov     edi, MOB_ZOMBIE             ; an elite drops 3..5 coins
    movss   xmm0, [k_8_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_8_5]
    call    mob_spawn_elite
    test    eax, eax
    js      .fail
    mov     edi, eax
    mov     esi, 200
    call    strike
    cmp     eax, 1
    jne     .fail
    mov     edi, GOLD_COIN
    call    drops_of
    cmp     eax, 1
    jne     .fail
    sub     edx, 3
    cmp     edx, 2
    ja      .fail
    call    drops_clear                 ; level 10 with 100 % gold find: a plain kill's coin pile is
    mov     byte [rpg_state + RPGSAVE.level], 10    ; (1 + 10 / 10) * 2 = 4 coins (untagged kills
    lea     rax, [rpg_stats]            ; pay no XP, so nothing recomputes the stat)
    mov     dword [rax + STAT_GOLD_FIND*4], 100
    mov     ebx, 12
.round10:
    xor     edi, edi
    call    kill_zombie
    test    eax, eax
    jnz     .fail
    dec     ebx
    jnz     .round10
    mov     edi, GOLD_COIN
    call    drops_of
    test    eax, eax
    jz      .fail                       ; 12 kills: some piles
    lea     ecx, [rax*4]
    cmp     edx, ecx                    ; ...each of 4 coins
    jne     .fail
    call    drops_clear                 ; an elite of level 10: (3 + rng % 3 + 10 / 5) * 2 = 10..14
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_8_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_8_5]
    call    mob_spawn_elite
    test    eax, eax
    js      .fail
    mov     edi, eax
    mov     esi, 1000
    call    strike
    cmp     eax, 1
    jne     .fail
    mov     edi, GOLD_COIN
    call    drops_of
    cmp     eax, 1
    jne     .fail
    sub     edx, 10
    cmp     edx, 4
    ja      .fail
    call    rpg_reset                   ; level 1 again, no gold find
    call    clear_sites                 ; a boss born at no site (origin 0) touches no record...
    SITE_KIND 2, SITE_CRYPT             ; (origin 3 backs this one)
    mov     dword [world_header + WORLDHDR.site_count], 3
    mov     byte [rpg_state + RPGSAVE.class], CLASS_ARCHER
    mov     byte [combat_hit_flags], HF_PLAYER | HF_CRIT
    SPAWN   MOB_BOSS, k_16_5, k_16_5
    test    eax, eax
    js      .fail
    mov     edi, eax
    mov     esi, 1000
    call    strike
    cmp     eax, 1
    jne     .fail
    cmp     byte [world_header + WORLDHDR.sites + 2 * SITESTATE_size + SITESTATE.flags], 0
    jne     .fail
    call    drops_clear                 ; ...the Fallen King born in the crypt of record 3 falls to an archer
    call    rpg_reset
    mov     byte [rpg_state + RPGSAVE.class], CLASS_ARCHER
    mov     byte [combat_hit_flags], HF_PLAYER | HF_CRIT
    SPAWN   MOB_BOSS, k_16_5, k_16_5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, eax
    call    mob_ptr
    mov     dword [rax + MOB.origin], 3
    mov     edi, ebx
    mov     esi, 1000
    call    strike
    cmp     eax, 1
    jne     .fail
    mov     edi, MOB_BOSS
    call    mob_count_type
    test    eax, eax
    jnz     .fail
    test    byte [world_header + WORLDHDR.sites + 2 * SITESTATE_size + SITESTATE.flags], SS_CLEARED
    jz      .fail                       ; the realm remembers: that record is cleared
    cmp     byte [world_header + WORLDHDR.sites + 1 * SITESTATE_size + SITESTATE.flags], 0
    jne     .fail                       ; and no other
    cmp     byte [rpg_state + RPGSAVE.level], 1     ; and 525 XP (500 + 25 for his level 1) raised the level
    jbe     .fail
    mov     edi, DIAMOND
    call    drops_of
    cmp     edx, 4
    jne     .fail
    mov     edi, GOLD_COIN
    call    drops_of
    cmp     edx, 31                     ; 30 + his level 1
    jne     .fail
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    mov     byte [combat_hit_flags], 0
    call    mobs_clear
    call    drops_clear
    call    fx_clear                    ; the Fallen King's blast, level-up sparks
    call    clear_sites
    call    rpg_reset
    call    combat_reset
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- 0.8: mob levels and elite affixes ---------------------------------------------------------

; LEVEL_FOR origin, level: mob_level_for(origin) must come to `level`
%macro LEVEL_FOR 2
    mov     edi, %1
    call    mob_level_for
    cmp     eax, %2
    jne     .fail
%endmacro

; RESIST type, elem, percent: mob_resist(type, elem) must come to `percent`
%macro RESIST 3
    mov     edi, %1
    mov     esi, %2
    call    mob_resist
    cmp     eax, %3
    jne     .fail
%endmacro

; stand_player(): no mobs, the player standing at (16.5, 11, 16.5)
stand_player:
    sub     rsp, 8
    call    mobs_clear
    SETF    [player + BODY.x], 16.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 16.5
    add     rsp, 8
    ret

; fresh_fight(): a new fight: no mobs, the player standing at (16.5, 11, 16.5) at full health with
; his guard down and no armor, nothing burning, chilled or poisoned, night
fresh_fight:
    sub     rsp, 8
    call    stand_player
    call    survival_reset
    call    combat_reset
    call    inv_clear
    mov     dword [combat_burn_t], 0
    mov     dword [combat_chill_t], 0
    mov     dword [combat_poison_t], 0
    mov     dword [combat_poison], 0
    mov     dword [game_time], 40000
    add     rsp, 8
    ret

; zombie_blow(edi affix, esi mob health or 0, edx fire resistance %) -> eax the player's health after
; the blow of a Normal zombie in reach of him (level 1, no armor, nothing burning, chilled or
; poisoned yet): the zombie stays a plain one with its affix bits poked to `affix`, and with health
; `esi` when that is not 0; the player's fire resistance is poked to `edx` for the blow. It lives
; on in slot 0. -1 when it did not spawn.
zombie_blow:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    call    fresh_fight
    lea     rax, [rpg_stats]
    mov     [rax + STAT_RES_FIRE*4], r13d
    SPAWN   MOB_ZOMBIE, k_17_5, k_16_5
    test    eax, eax
    js      .fail
    mov     [mobs + MOB.affix], ebx     ; slot 0: stand_player emptied them all
    test    r12d, r12d
    jz      .steps
    mov     [mobs + MOB.health], r12d
.steps:
    mov     ebx, 21                     ; the arm goes up, the blow lands 20 steps later
.step:
    call    mobs_step
    dec     ebx
    jnz     .step
    mov     eax, [surv + SURVIVAL.health]
    jmp     .ret
.fail:
    mov     eax, -1
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; spider_bite(edi affix) -> eax the player's health after the bite of a Normal spider in reach of
; him (level 1, a fresh fight), its affix bits poked to `affix`; -1 when it did not spawn. It
; lives on in slot 0.
spider_bite:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
    call    fresh_fight
    SPAWN   MOB_SPIDER, k_17_5, k_16_5
    test    eax, eax
    js      .fail
    mov     [mobs + MOB.affix], ebx     ; slot 0
    mov     ebx, 13                     ; it rears up (1), the bite lands 12 steps later
.step:
    call    mobs_step
    dec     ebx
    jnz     .step
    mov     eax, [surv + SURVIVAL.health]
    jmp     .ret
.fail:
    mov     eax, -1
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; parried_zombie(edi affix) -> eax the stun of a zombie (its affix bits poked to `affix`) whose
; blow the player parries with a guard raised on the last step; -1 when it did not spawn. It
; lives on in slot 0.
parried_zombie:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
    call    fresh_fight
    SETF    [player + BODY.yaw], 90.0   ; facing +x, towards the zombie: its blow is frontal
    SPAWN   MOB_ZOMBIE, k_17_5, k_16_5
    test    eax, eax
    js      .fail
    mov     [mobs + MOB.affix], ebx     ; slot 0
    mov     ebx, 20                     ; the arm goes up, the blow is due on the next step
.raise:
    call    mobs_step
    dec     ebx
    jnz     .raise
    mov     dword [combat_guard_t], 0   ; the guard comes up on the very last step
    call    mobs_step
    call    fx_clear                    ; a parry throws sparks
    mov     eax, [mobs + MOB.stun]
    jmp     .ret
.fail:
    mov     eax, -1
.ret:
    SETF    [player + BODY.yaw], 0.0
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; elite_windup(edi affix) -> eax the wind-up steps of an elite zombie, its affix poked to `affix`,
; after one step in reach of the player; -1 when it did not spawn
elite_windup:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
    call    stand_player
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_17_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_16_5]
    call    mob_spawn_elite
    test    eax, eax
    js      .none
    mov     [mobs + MOB.affix], ebx     ; slot 0
    call    mobs_step
    mov     eax, [mobs + MOB.windup]
    jmp     .ret
.none:
    mov     eax, -1
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; skeleton_shot(edi affix) -> eax 1 when a skeleton 8 blocks from the player, its affix bits
; poked to `affix`, shot an arrow in one step (arrows[0], the only one)
skeleton_shot:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
    call    arrows_clear
    call    stand_player
    call    combat_reset
    mov     dword [game_time], 40000
    SPAWN   MOB_SKELETON, k_16_5, k_8_5
    test    eax, eax
    js      .none
    mov     [mobs + MOB.affix], ebx     ; slot 0
    call    mobs_step
    xor     eax, eax
    cmp     dword [arrows + ARROWENT.live], 0
    setne   al
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; affix_rolls(edi player level, esi count) -> eax 0 when 64 elite zombies spawned at that player
; level each carry exactly `count` affixes (distinct kinds: the bits of MOB.affix, one of the 8)
; and the speed that goes with their SWIFT bit; edx = the kinds rolled together, ecx = how many
; of the 64 were SWIFT.
; rbx = rolls left, r12d = count, r13d = kinds seen, r14d = SWIFT seen, r15 = the mob
affix_rolls:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     [rpg_state + RPGSAVE.level], dil
    mov     r12d, esi
    xor     r13d, r13d
    xor     r14d, r14d
    mov     ebx, 64
.roll:
    call    mobs_clear
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_8_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_8_5]
    call    mob_spawn_elite
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    mob_ptr
    mov     r15, rax
    cmp     dword [r15 + MOB.elite], 1
    jne     .fail
    mov     eax, [r15 + MOB.affix]
    cmp     eax, 255
    ja      .fail
    or      r13d, eax
    xor     ecx, ecx                    ; count the set bits
.bits:
    test    eax, eax
    jz      .counted
    lea     edx, [rax - 1]
    and     eax, edx                    ; clears the lowest one
    inc     ecx
    jmp     .bits
.counted:
    cmp     ecx, r12d
    jne     .fail
    movss   xmm0, [r15 + BODY.speed]
    test    dword [r15 + MOB.affix], AFX_SWIFT
    jz      .plain
    inc     r14d
    ucomiss xmm0, [k_3_88]              ; 2.6 * 1.15 * 1.3 = 3.887
    jbe     .fail
    ucomiss xmm0, [k_3_89]
    jae     .fail
    jmp     .rolled
.plain:
    ucomiss xmm0, [k_2_985]             ; 2.6 * 1.15 = 2.99
    jbe     .fail
    ucomiss xmm0, [k_2_995]
    jae     .fail
.rolled:
    dec     ebx
    jnz     .roll
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     edx, r13d
    mov     ecx, r14d
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; night_census() -> eax live mobs, edx elites among them, ecx elites whose affix is not exactly
; one kind
night_census:
    xor     eax, eax
    xor     edx, edx
    xor     r8d, r8d
    lea     rcx, [mobs]
    mov     esi, MAX_MOBS
.l:
    cmp     dword [rcx + MOB.type], MOB_NONE
    je      .next
    inc     eax
    cmp     dword [rcx + MOB.elite], 0
    je      .next
    inc     edx
    mov     edi, [rcx + MOB.affix]
    lea     r9d, [rdi - 1]
    test    edi, r9d
    jnz     .bad                        ; two or more kinds
    test    edi, edi
    jnz     .next                       ; exactly one
.bad:
    inc     r8d
.next:
    add     rcx, MOB_size
    dec     esi
    jnz     .l
    mov     ecx, r8d
    ret

; A mob starts at the player's level (a villager at 1; a dungeon's mobs two above, the crypt boss
; three above and at least 20) with the health of that level: a level-10 zombie 20 * (1 + 0.15 * 9)
; = 47, level 12 53, an elite of level 10 round(117.5) = 118, the Fallen King at 20 300 * 3.85 =
; 1155; mob_set_level heals it fully. A level-10 zombie's blow on the unarmored Normal player is
; round(3 * 1.9) = 6, an elite's round(round(3 * 1.5) * 1.9) = 8. A save keeps the level and the
; affixes in the type word (an elite of level 12 with MOLTEN | SWIFT reads back as such; a record
; without them takes the player's level and no affix).
test_mob_levels_and_scaling:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    fixture
    call    reset_player
    call    combat_reset
    call    inv_clear                   ; no armor
    mov     dword [game_time], 40000
    mov     byte [rpg_state + RPGSAVE.class], CLASS_WARRIOR
    mov     byte [rpg_state + RPGSAVE.level], 10    ; poked: the stats stay as they are
    call    clear_sites                 ; site state records: 1 and 6 dungeons, 7 a village, 9 a crypt, 10 a camp
    SITE_KIND 0, SITE_DUNGEON
    SITE_KIND 5, SITE_DUNGEON
    SITE_KIND 6, SITE_VILLAGE
    SITE_KIND 8, SITE_CRYPT
    SITE_KIND 9, SITE_CAMP
    LEVEL_FOR 0, 10                     ; no site: the player's level
    LEVEL_FOR 1, 12                     ; a dungeon: two above
    LEVEL_FOR 6, 12
    LEVEL_FOR 7, 10                     ; a village
    LEVEL_FOR 9, 20                     ; a crypt: three above, at least 20
    LEVEL_FOR 10, 10                    ; a camp
    LEVEL_FOR 2, 10                     ; a record that is empty
    LEVEL_FOR 99, 10                    ; (the old crypt constant means nothing now)
    LEVEL_FOR 1025, 10                  ; beyond the table
    mov     byte [rpg_state + RPGSAVE.level], 25
    LEVEL_FOR 9, 28
    mov     byte [rpg_state + RPGSAVE.level], 10
    mov     edi, 1                      ; the blows' scale: 1.0 at level 1 (and below), 1.9 at 10
    call    mob_dmg_mult
    ucomiss xmm0, [k_one]
    jne     .fail
    xor     edi, edi
    call    mob_dmg_mult
    ucomiss xmm0, [k_one]
    jne     .fail
    mov     edi, 10
    call    mob_dmg_mult
    ucomiss xmm0, [k_1_89]
    jbe     .fail
    ucomiss xmm0, [k_1_91]
    jae     .fail
    lea     rdi, [mobs]                 ; a freed slot full of stale bytes: a spawn clears all the new fields
    mov     ecx, MOB_size
    mov     al, 0xFF
    rep     stosb
    mov     dword [mobs + MOB.type], MOB_NONE
    SPAWN   MOB_ZOMBIE, k_8_5, k_8_5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax                    ; a zombie at the player's level 10
    cmp     dword [r12 + MOB.level], 10
    jne     .fail
    cmp     dword [r12 + MOB.max_health], 47
    jne     .fail
    cmp     dword [r12 + MOB.health], 47
    jne     .fail
    lea     rcx, [r12 + MOB.affix]      ; affix, statuses and timers: 15 fields, all zero
    mov     edx, (MOB_size - MOB.affix) / 4
.fresh:
    cmp     dword [rcx], 0
    jne     .fail
    add     rcx, 4
    dec     edx
    jnz     .fresh
    mov     dword [r12 + MOB.health], 5
    mov     edi, ebx
    mov     esi, 12
    call    mob_set_level               ; level 12: 20 * 2.65, healed
    cmp     dword [r12 + MOB.level], 12
    jne     .fail
    cmp     dword [r12 + MOB.max_health], 53
    jne     .fail
    cmp     dword [r12 + MOB.health], 53
    jne     .fail
    mov     edi, ebx
    xor     esi, esi
    call    mob_set_level               ; levels run from 1...
    cmp     dword [r12 + MOB.level], 1
    jne     .fail
    cmp     dword [r12 + MOB.max_health], 20
    jne     .fail
    mov     edi, ebx
    mov     esi, 1000
    call    mob_set_level               ; ...to 255, the one byte a save keeps
    cmp     dword [r12 + MOB.level], 255
    jne     .fail
    mov     edi, MAX_MOBS - 1           ; an empty slot and a slot that does not exist stay as they are
    mov     esi, 30
    call    mob_set_level
    cmp     dword [mobs + (MAX_MOBS - 1) * MOB_size + MOB.type], MOB_NONE
    jne     .fail
    cmp     dword [mobs + (MAX_MOBS - 1) * MOB_size + MOB.level], 0
    jne     .fail
    mov     edi, MAX_MOBS
    mov     esi, 30
    call    mob_set_level
    call    mobs_clear
    mov     edi, FAC_VILLAGERS          ; folk stay at level 1 with 20 health
    mov     esi, ROLE_TRADER
    xor     edx, edx
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_16_5]
    call    folk_spawn
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    mob_ptr
    cmp     dword [rax + MOB.level], 1
    jne     .fail
    cmp     dword [rax + MOB.max_health], 20
    jne     .fail
    call    mobs_clear
    mov     edi, MOB_ZOMBIE             ; an elite of level 10, its affix pinned to a plain one
    movss   xmm0, [k_8_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_8_5]
    call    mob_spawn_elite
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax
    mov     dword [r12 + MOB.affix], AFX_ARMORED
    mov     edi, ebx
    mov     esi, 10
    call    mob_set_level
    cmp     dword [r12 + MOB.max_health], 118   ; round(20 * 2.35 * 2.5 = 117.5), in floats, once
    jne     .fail
    call    mobs_clear
    SPAWN   MOB_BOSS, k_16_5, k_16_5    ; the Fallen King, spawned at 10, then born in the crypt
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax
    cmp     dword [r12 + MOB.max_health], 705       ; 300 * 2.35
    jne     .fail
    mov     edi, 9                      ; the crypt record
    call    mob_level_for
    mov     edi, ebx
    mov     esi, eax
    call    mob_set_level
    cmp     dword [r12 + MOB.level], 20
    jne     .fail
    cmp     dword [r12 + MOB.max_health], 1155      ; 300 * 3.85
    jne     .fail
    cmp     dword [r12 + MOB.health], 1155
    jne     .fail
    call    stand_player                ; a level-10 zombie in reach of the unarmored player
    SPAWN   MOB_ZOMBIE, k_17_5, k_16_5
    test    eax, eax
    js      .fail
    mov     ebx, 21                     ; the arm goes up, the blow lands 20 steps later
.blow:
    call    mobs_step
    dec     ebx
    jnz     .blow
    cmp     dword [surv + SURVIVAL.health], 14      ; 20 - round(3 * 1.9)
    jne     .fail
    xor     edi, edi                    ; a spider's bite (Normal: 2): round(2 * 1.9) = 4
    call    spider_bite
    cmp     eax, 16
    jne     .fail
    call    stand_player                ; an elite: 3 * 1.5 -> 4, then x 1.9 -> 8
    call    survival_reset
    call    combat_reset
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_17_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_16_5]
    call    mob_spawn_elite
    test    eax, eax
    js      .fail
    mov     dword [mobs + MOB.affix], AFX_ARMORED
    mov     ebx, 17                     ; wind-up 16 steps
.eblow:
    call    mobs_step
    dec     ebx
    jnz     .eblow
    cmp     dword [surv + SURVIVAL.health], 12      ; 20 - round(round(3 * 1.5) * 1.9)
    jne     .fail
    call    mobs_clear                  ; the save: an elite of level 12 with MOLTEN | SWIFT
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_8_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_8_5]
    call    mob_spawn_elite
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax
    mov     dword [r12 + MOB.affix], AFX_MOLTEN | AFX_SWIFT
    mov     edi, ebx
    mov     esi, 12
    call    mob_set_level
    cmp     dword [r12 + MOB.max_health], 132       ; round(20 * 2.65 * 2.5 = 132.5), to even
    jne     .fail
    mov     dword [r12 + MOB.health], 100
    lea     rdi, [hdr]
    call    mobs_save
    cmp     dword [hdr + WORLDHDR.mob_count], 1
    jne     .fail
    cmp     dword [hdr + WORLDHDR.mobs + MOBSAVE.type], MOB_ZOMBIE | MOB_ELITE_BIT | (12 << MS_LEVEL_SHIFT) | ((AFX_MOLTEN | AFX_SWIFT) << MS_AFFIX_SHIFT)
    jne     .fail
    call    mobs_clear
    lea     rdi, [hdr]
    call    mobs_load
    lea     r12, [mobs]
    cmp     dword [r12 + MOB.type], MOB_ZOMBIE
    jne     .fail
    cmp     dword [r12 + MOB.elite], 1
    jne     .fail
    cmp     dword [r12 + MOB.level], 12
    jne     .fail
    cmp     dword [r12 + MOB.affix], AFX_MOLTEN | AFX_SWIFT
    jne     .fail
    cmp     dword [r12 + MOB.max_health], 132
    jne     .fail
    cmp     dword [r12 + MOB.health], 100
    jne     .fail
    movss   xmm0, [r12 + BODY.speed]    ; 2.6 * 1.15 * 1.3 = 3.887
    ucomiss xmm0, [k_3_88]
    jbe     .fail
    ucomiss xmm0, [k_3_89]
    jae     .fail
    mov     dword [hdr + WORLDHDR.mobs + MOBSAVE.type], MOB_ZOMBIE | MOB_ELITE_BIT
    call    mobs_clear                  ; an older record: the player's level 10, one affix rolled
    lea     rdi, [hdr]
    call    mobs_load
    cmp     dword [mobs + MOB.level], 10
    jne     .fail
    mov     eax, [mobs + MOB.affix]
    test    eax, eax
    jz      .fail                       ; a pre-0.8 elite rolls its affix on load...
    lea     ecx, [rax - 1]
    test    eax, ecx
    jnz     .fail                       ; ...one, below level 15
    mov     ecx, [mobs + MOB.max_health]
    cmp     ecx, 118
    je      .old_max
    cmp     ecx, 176                    ; JUGGERNAUT: round(20 * 2.35 * 2.5 * 1.5)
    jne     .fail
.old_max:
    cmp     dword [mobs + MOB.health], 100
    jne     .fail
    mov     dword [hdr + WORLDHDR.mobs + MOBSAVE.type], MOB_ZOMBIE
    call    mobs_clear
    lea     rdi, [hdr]
    call    mobs_load
    cmp     dword [mobs + MOB.level], 10
    jne     .fail
    cmp     dword [mobs + MOB.health], 47           ; the saved 100 clamps to a plain level-10 zombie's
    jne     .fail
    call    fresh_fight                 ; a level-10 creeper next to him: the fuse burns down, it blows
    mov     edi, MOB_CREEPER
    movss   xmm0, [k_18_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_16_5]
    call    mob_spawn
    test    eax, eax
    js      .fail
    mov     ebx, 95
.fuse:
    call    mobs_step
    dec     ebx
    jnz     .fuse
    mov     edi, MOB_CREEPER
    call    mob_count_type
    test    eax, eax
    jnz     .fail
    cmp     dword [explode_dmg_mult], 0 ; the blast's scale did not outlive it
    jne     .fail
    cmp     dword [surv + SURVIVAL.health], 20
    jge     .fail                       ; (and hurt him)
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    mobs_clear
    call    fx_clear
    call    tnt_clear
    call    combat_reset
    call    rpg_reset
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; Elites roll affixes: one below level 15, two from 15 on, never the same kind twice, every kind
; possible; a SWIFT elite moves 2.6 * 1.15 * 1.3 and winds up in 12 steps instead of 16; a
; JUGGERNAUT has 1.5 x the health (75) and a hit shoves it not at all. A Normal zombie's blow of 3
; gains half of it as fire (MOLTEN: 5 in all, the player burns; 4 with 50 % fire resistance), 0.3
; as frost (FROZEN: 4, chilled), 0.3 as poison (VENOMOUS: 4, poisoned), 0.5 as shock (STORM: 5);
; a VAMPIRIC one heals half of what it deals (10 -> 11, never past its maximum). A skeleton's
; arrow carries the whole damage and the element of its first elemental affix. mob_resist and
; mob_affix_name. 4 % of a night's spawns are elite, with one affix at level 1.
test_elite_affixes:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    world_clear
    call    fixture
    call    reset_player
    call    combat_reset
    call    inv_clear                   ; no armor
    mov     dword [game_time], 40000
    mov     edi, 5                      ; one affix below level 15...
    mov     esi, 1
    call    affix_rolls
    test    eax, eax
    jnz     .fail
    mov     r12d, edx                   ; the kinds seen
    mov     r13d, ecx                   ; the SWIFT ones
    mov     edi, 14
    mov     esi, 1
    call    affix_rolls
    test    eax, eax
    jnz     .fail
    or      r12d, edx
    add     r13d, ecx
    mov     edi, 15                     ; ...two from level 15 on, never the same kind twice
    mov     esi, 2
    call    affix_rolls
    test    eax, eax
    jnz     .fail
    or      r12d, edx
    add     r13d, ecx
    mov     edi, 20
    mov     esi, 2
    call    affix_rolls
    test    eax, eax
    jnz     .fail
    or      r12d, edx
    add     r13d, ecx
    cmp     r12d, 0xFF                  ; every one of the 8 kinds came up
    jne     .fail
    test    r13d, r13d
    jz      .fail                       ; some SWIFT ones...
    cmp     r13d, 4 * 64
    jae     .fail                       ; ...and some that were not
    mov     byte [rpg_state + RPGSAVE.level], 1
    mov     edi, AFX_SWIFT              ; a SWIFT elite winds up in 3/4 of 16 steps
    call    elite_windup
    cmp     eax, 12
    jne     .fail
    mov     edi, AFX_ARMORED            ; the others in 16
    call    elite_windup
    cmp     eax, 16
    jne     .fail
    call    mobs_clear                  ; raised to level 16 (a dungeon elite), one affix becomes two
    SPAWN   MOB_ZOMBIE, k_8_5, k_8_5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax
    mov     dword [r12 + MOB.elite], 1
    mov     dword [r12 + MOB.affix], AFX_ARMORED
    mov     edi, ebx
    mov     esi, 16
    call    mob_set_level
    mov     eax, [r12 + MOB.affix]
    test    eax, AFX_ARMORED
    jz      .fail                       ; it keeps the first one
    lea     ecx, [rax - 1]
    and     ecx, eax                    ; drop the lowest bit: one bit must remain
    jz      .fail
    lea     edx, [rcx - 1]
    test    ecx, edx
    jnz     .fail                       ; and only one
    call    mobs_clear                  ; JUGGERNAUT: 20 * 2.5 * 1.5 = 75 health, no knockback
    SPAWN   MOB_ZOMBIE, k_8_5, k_8_5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax
    mov     dword [r12 + MOB.elite], 1
    mov     dword [r12 + MOB.affix], AFX_JUGGERNAUT
    mov     edi, ebx
    mov     esi, 1
    call    mob_set_level
    cmp     dword [r12 + MOB.max_health], 75
    jne     .fail
    cmp     dword [r12 + MOB.health], 75
    jne     .fail
    mov     edi, ebx
    mov     esi, 5
    call    strike
    cmp     eax, 1
    jne     .fail
    cmp     dword [r12 + MOB.health], 70
    jne     .fail
    cmp     dword [r12 + BODY.kbx], 0
    jne     .fail
    cmp     dword [r12 + BODY.kbz], 0
    jne     .fail                       ; it stood firm...
    mov     dword [r12 + MOB.affix], 0
    mov     edi, ebx
    mov     esi, 5
    call    strike
    movss   xmm0, [r12 + BODY.kbz]
    ucomiss xmm0, [k_6]                 ; ...where an ordinary mob is shoved at 6 blocks/s
    jne     .fail
    xor     edi, edi                    ; a parried zombie reels back and is stunned for 50 steps...
    call    parried_zombie
    cmp     eax, 50
    jne     .fail
    movss   xmm0, [mobs + BODY.kbx]
    ucomiss xmm0, [k_one]
    jbe     .fail
    mov     edi, AFX_JUGGERNAUT         ; ...a juggernaut shrugs the riposte off
    call    parried_zombie
    test    eax, eax
    jnz     .fail
    cmp     dword [mobs + BODY.kbx], 0
    jne     .fail
    xor     edi, edi                    ; a plain zombie's blow: 20 - 3
    xor     esi, esi
    xor     edx, edx
    call    zombie_blow
    cmp     eax, 17
    jne     .fail
    mov     eax, [combat_burn_t]
    or      eax, [combat_chill_t]
    or      eax, [combat_poison_t]
    jnz     .fail
    mov     edi, AFX_MOLTEN             ; MOLTEN: + round(1.5) = 2 fire, and the player burns
    xor     esi, esi
    xor     edx, edx
    call    zombie_blow
    cmp     eax, 15
    jne     .fail
    cmp     dword [combat_burn_t], 180
    jne     .fail
    mov     edi, AFX_MOLTEN             ; 50 % fire resistance halves the part: 1
    xor     esi, esi
    mov     edx, 50
    call    zombie_blow
    cmp     eax, 16
    jne     .fail
    mov     edi, AFX_FROZEN             ; FROZEN: + round(0.9) = 1 frost, chilled
    xor     esi, esi
    xor     edx, edx
    call    zombie_blow
    cmp     eax, 16
    jne     .fail
    cmp     dword [combat_chill_t], 120
    jne     .fail
    mov     edi, AFX_VENOMOUS           ; VENOMOUS: + 1 poison, one stack of it
    xor     esi, esi
    xor     edx, edx
    call    zombie_blow
    cmp     eax, 16
    jne     .fail
    cmp     dword [combat_poison], 1
    jne     .fail
    cmp     dword [combat_poison_t], 0
    jle     .fail
    mov     edi, AFX_STORM              ; STORM: + round(1.5) = 2 shock, no status
    xor     esi, esi
    xor     edx, edx
    call    zombie_blow
    cmp     eax, 15
    jne     .fail
    mov     eax, [combat_burn_t]
    or      eax, [combat_chill_t]
    or      eax, [combat_poison_t]
    jnz     .fail
    xor     edi, edi                    ; a Normal spider's bite of 2...
    call    spider_bite
    cmp     eax, 18
    jne     .fail
    mov     edi, AFX_MOLTEN             ; ...MOLTEN: + round(1.0) = 1 fire, burning
    call    spider_bite
    cmp     eax, 17
    jne     .fail
    cmp     dword [combat_burn_t], 180
    jne     .fail
    mov     edi, AFX_VAMPIRIC           ; VAMPIRIC: half of the 3 dealt (1) heals it, 10 -> 11...
    mov     esi, 10
    xor     edx, edx
    call    zombie_blow
    cmp     eax, 17
    jne     .fail
    cmp     dword [mobs + MOB.health], 11
    jne     .fail
    mov     edi, AFX_VAMPIRIC           ; ...but never past its maximum
    xor     esi, esi
    xor     edx, edx
    call    zombie_blow
    cmp     dword [mobs + MOB.health], 20
    jne     .fail
    xor     edi, edi                    ; a skeleton's arrow: 3, no element...
    call    skeleton_shot
    test    eax, eax
    jz      .fail
    cmp     dword [arrows + ARROWENT.damage], 3
    jne     .fail
    cmp     dword [arrows + ARROWENT.flags], 0
    jne     .fail
    mov     edi, AFX_STORM | AFX_FROZEN | AFX_VAMPIRIC
    call    skeleton_shot               ; ...3 + 1 frost + 2 shock, frost (the first of them)
    test    eax, eax
    jz      .fail
    cmp     dword [arrows + ARROWENT.damage], 6
    jne     .fail
    cmp     dword [arrows + ARROWENT.flags], ELEM_FROST << AF_ELEM_SHIFT
    jne     .fail
    RESIST  MOB_ZOMBIE, ELEM_PHYS, 0
    RESIST  MOB_ZOMBIE, ELEM_FIRE, -50
    RESIST  MOB_ZOMBIE, ELEM_POISON, 25
    RESIST  MOB_CREEPER, ELEM_FROST, -25
    RESIST  MOB_CREEPER, ELEM_SHOCK, 50
    RESIST  MOB_SKELETON, ELEM_FROST, 25
    RESIST  MOB_SKELETON, ELEM_POISON, 100
    RESIST  MOB_SPIDER, ELEM_FIRE, -25
    RESIST  MOB_SPIDER, ELEM_POISON, 100
    RESIST  MOB_BOSS, ELEM_PHYS, 20
    RESIST  MOB_BOSS, ELEM_SHOCK, 20
    RESIST  MOB_BOSS, ELEM_POISON, 50
    RESIST  MOB_PIG, ELEM_FIRE, 0
    RESIST  MOB_NONE, ELEM_FIRE, 0      ; no such type, no such element
    RESIST  NUM_MOB_TYPES + 1, ELEM_FIRE, 0
    RESIST  MOB_ZOMBIE, NUM_ELEMS, 0
    xor     edi, edi
    call    mob_affix_name
    cmp     dword [rax], 'Molt'
    jne     .fail
    mov     edi, 6
    call    mob_affix_name
    cmp     dword [rax], 'Jugg'
    jne     .fail
    mov     edi, 7
    call    mob_affix_name
    cmp     dword [rax], 'Armo'
    jne     .fail
    mov     edi, 8
    call    mob_affix_name
    cmp     byte [rax], 0               ; no such affix: an empty string
    jne     .fail
    mov     edi, 80                     ; 4 % of the night's spawns: GRASS for them to stand on
    mov     esi, 80
    mov     edx, 176
    mov     ecx, 176
    mov     r8d, GRASS
    call    fill_layer
    call    stand_player
    SETF    [player + BODY.x], 128.5
    SETF    [player + BODY.z], 128.5
    mov     dword [game_time], 40020    ; a multiple of 60: the spawner acts on every step
    xor     r12d, r12d                  ; mobs spawned
    xor     r13d, r13d                  ; elites among them
    mov     ebx, 500
.night:
    call    mobs_clear
    call    mobs_step
    call    night_census
    add     r12d, eax
    add     r13d, edx
    test    ecx, ecx
    jnz     .fail                       ; every elite has exactly one affix at level 1
    dec     ebx
    jnz     .night
    cmp     r12d, 300                   ; the spawner found a place most of the time
    jb      .fail
    imul    eax, r13d, 100
    cmp     eax, r12d
    jb      .fail                       ; at least 1 % elite...
    imul    ecx, r12d, 10
    cmp     eax, ecx
    ja      .fail                       ; ...and at most 10 %
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    mobs_clear
    call    arrows_clear
    call    fx_clear
    call    combat_reset
    call    rpg_reset
    mov     dword [combat_burn_t], 0
    mov     dword [combat_chill_t], 0
    mov     dword [combat_poison_t], 0
    mov     dword [combat_poison], 0
    mov     eax, ebx
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- 0.9: entities under a floating origin, a streamed world and water --------------------------

; EXPECT_F mem, const: the float at mem must equal the constant exactly
%macro EXPECT_F 2
    movss   xmm0, %1
    ucomiss xmm0, [%2]
    jne     .fail
    jp      .fail
%endmacro

; SHIFT fn: fn(512, -512)
%macro SHIFT 1
    mov     edi, 512
    mov     esi, -512
    call    %1
%endmacro

; clear_entities(): nothing of any module lives any more
clear_entities:
    sub     rsp, 8
    call    mobs_clear
    call    drops_clear
    call    arrows_clear
    call    tnt_clear
    call    fire_clear
    call    fx_clear
    call    dmgnum_clear
    call    abilities_reset
    add     rsp, 8
    ret

; Every module that keeps a local position follows a rebase by (512, -512), exactly: a mob and its home,
; a drop, an arrow, a primed TNT, a fire cell, a particle, a floating number and the targets of the meteor
; storm and the arrow rain. Free slots are left alone.
test_entities_rebase:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    clear_entities
    mov     edi, 1234
    call    rng_seed
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_1000_5]
    movss   xmm1, [k_20]
    movss   xmm2, [k_m1000_5]
    call    mob_spawn
    test    eax, eax
    js      .fail
    SETF    [mobs + MOB.home_x], 1001.0
    SETF    [mobs + MOB.home_z], -999.0
    SETF    [mobs + MOB_size + BODY.x], 7.0     ; a free slot with a stale x
    mov     edi, DIRT
    mov     esi, 1
    xor     edx, edx
    movss   xmm0, [k_1000_5]
    movss   xmm1, [k_20]
    movss   xmm2, [k_m1000_5]
    call    drops_spawn
    test    eax, eax
    jnz     .fail
    movss   xmm0, [k_1000_5]
    movss   xmm1, [k_20]
    movss   xmm2, [k_m1000_5]
    xorps   xmm3, xmm3
    xorps   xmm4, xmm4
    xorps   xmm5, xmm5
    xor     edi, edi
    mov     esi, 1
    xor     edx, edx
    mov     ecx, PROJ_ARROW
    xor     r8d, r8d
    call    arrows_spawn
    test    eax, eax
    jnz     .fail
    mov     dword [primed + PRIMED.fuse], 50
    SETF    [primed + PRIMED.body + BODY.x], 1000.5
    SETF    [primed + PRIMED.body + BODY.y], 20.0
    SETF    [primed + PRIMED.body + BODY.z], -1000.5
    SETF    [primed + PRIMED_size + PRIMED.body + BODY.x], 7.0
    mov     dword [fires + FIREENT.x], 1000
    mov     dword [fires + FIREENT.y], 20
    mov     dword [fires + FIREENT.z], -1000
    mov     dword [fires + FIREENT_size + FIREENT.x], 7
    mov     dword [fx_particles + PARTICLE.kind], FX_FIRE
    SETF    [fx_particles + PARTICLE.x], 1000.5
    SETF    [fx_particles + PARTICLE.y], 20.0
    SETF    [fx_particles + PARTICLE.z], -1000.5
    mov     dword [fx_particles + PARTICLE.life], 100
    movss   xmm0, [k_1000_5]
    movss   xmm1, [k_20]
    movss   xmm2, [k_m1000_5]
    mov     edi, 5
    xor     esi, esi
    call    dmgnum_spawn
    SETF    [meteor_tgt], 1000.5
    SETF    [meteor_tgt + 4], 20.0
    SETF    [meteor_tgt + 8], -1000.5
    SETF    [rain_tgt], 1000.5
    SETF    [rain_tgt + 4], 20.0
    SETF    [rain_tgt + 8], -1000.5
    SHIFT   mobs_shift
    SHIFT   drops_shift
    SHIFT   arrows_shift
    SHIFT   tnt_shift
    SHIFT   fire_shift
    SHIFT   fx_shift
    SHIFT   dmgnum_shift
    SHIFT   abilities_shift
    EXPECT_F [mobs + BODY.x], k_488_5
    EXPECT_F [mobs + BODY.y], k_20
    EXPECT_F [mobs + BODY.z], k_m488_5
    EXPECT_F [mobs + MOB.home_x], k_489
    EXPECT_F [mobs + MOB.home_z], k_m487
    EXPECT_F [mobs + MOB_size + BODY.x], k_7
    EXPECT_F [drops + DROP.x], k_488_5
    EXPECT_F [drops + DROP.y], k_20
    EXPECT_F [drops + DROP.z], k_m488_5
    EXPECT_F [arrows + ARROWENT.x], k_488_5
    EXPECT_F [arrows + ARROWENT.y], k_20
    EXPECT_F [arrows + ARROWENT.z], k_m488_5
    EXPECT_F [primed + PRIMED.body + BODY.x], k_488_5
    EXPECT_F [primed + PRIMED.body + BODY.y], k_20
    EXPECT_F [primed + PRIMED.body + BODY.z], k_m488_5
    EXPECT_F [primed + PRIMED_size + PRIMED.body + BODY.x], k_7
    cmp     dword [fires + FIREENT.x], 488
    jne     .fail
    cmp     dword [fires + FIREENT.y], 20
    jne     .fail
    cmp     dword [fires + FIREENT.z], -488
    jne     .fail
    cmp     dword [fires + FIREENT_size + FIREENT.x], 7
    jne     .fail
    EXPECT_F [fx_particles + PARTICLE.x], k_488_5
    EXPECT_F [fx_particles + PARTICLE.y], k_20
    EXPECT_F [fx_particles + PARTICLE.z], k_m488_5
    EXPECT_F [dmgnum_list], k_488_5             ; DMGNUM: x, y, z first
    EXPECT_F [dmgnum_list + 4], k_20
    EXPECT_F [dmgnum_list + 8], k_m488_5
    EXPECT_F [meteor_tgt], k_488_5
    EXPECT_F [meteor_tgt + 4], k_20
    EXPECT_F [meteor_tgt + 8], k_m488_5
    EXPECT_F [rain_tgt], k_488_5
    EXPECT_F [rain_tgt + 4], k_20
    EXPECT_F [rain_tgt + 8], k_m488_5
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    clear_entities
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; mob_mask() -> eax bit i set when mobs[i] lives (i < 6); drop_mask(), tnt_mask() and fire_mask() the same
; for the drops, the primed TNT and the fires
mob_mask:
    xor     eax, eax
    xor     ecx, ecx
    lea     rsi, [mobs]
.l:
    imul    edx, ecx, MOB_size
    cmp     dword [rsi + rdx + MOB.type], MOB_NONE
    je      .n
    bts     eax, ecx
.n:
    inc     ecx
    cmp     ecx, 6
    jb      .l
    ret
drop_mask:
    xor     eax, eax
    xor     ecx, ecx
    lea     rsi, [drops]
.l:
    imul    edx, ecx, DROP_size
    cmp     byte [rsi + rdx + DROP.id], 0
    je      .n
    bts     eax, ecx
.n:
    inc     ecx
    cmp     ecx, 6
    jb      .l
    ret
tnt_mask:
    xor     eax, eax
    xor     ecx, ecx
    lea     rsi, [primed]
.l:
    imul    edx, ecx, PRIMED_size
    cmp     dword [rsi + rdx + PRIMED.fuse], 0
    je      .n
    bts     eax, ecx
.n:
    inc     ecx
    cmp     ecx, 6
    jb      .l
    ret
fire_mask:
    xor     eax, eax
    xor     ecx, ecx
    lea     rsi, [fires]
.l:
    imul    edx, ecx, FIREENT_size
    cmp     dword [rsi + rdx + FIREENT.y], -1
    je      .n
    bts     eax, ecx
.n:
    inc     ecx
    cmp     ecx, 6
    jb      .l
    ret

; MASKS expected: mob_mask, drop_mask, tnt_mask and fire_mask must all come to `expected`
%macro MASKS 1
    call    mob_mask
    cmp     eax, %1
    jne     .fail
    call    drop_mask
    cmp     eax, %1
    jne     .fail
    call    tnt_mask
    cmp     eax, %1
    jne     .fail
    call    fire_mask
    cmp     eax, %1
    jne     .fail
%endmacro

; BOXES x0, z0, x1, z1: the four remove_box functions on that inclusive local box
%macro BOXES 4
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    call    mobs_remove_box
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    call    drops_remove_box
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    call    tnt_remove_box
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    call    fire_remove_box
%endmacro

; far_run() -> eax 0: with the player at (130.5, 11, 10.5), render distance 8 and a time that spawns
; nothing, one zombie is spawned at each far_cases point (slot i) and one mobs_step leaves each of them
; as the table says
; rbx = case, r12 = its record
far_run:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    mobs_clear
    xor     ebx, ebx
.spawn:
    lea     eax, [rbx + rbx*2]
    lea     rcx, [far_cases]
    lea     r12, [rcx + rax*4]
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [r12]
    movss   xmm1, [k_11]
    movss   xmm2, [r12 + 4]
    call    mob_spawn
    cmp     eax, ebx
    jne     .fail
    inc     ebx
    cmp     ebx, FAR_CASES
    jb      .spawn
    call    mobs_step
    xor     ebx, ebx
.check:
    lea     eax, [rbx + rbx*2]
    lea     rcx, [far_cases]
    lea     r12, [rcx + rax*4]
    imul    eax, ebx, MOB_size
    lea     rdx, [mobs]
    mov     eax, [rdx + rax + MOB.type]
    cmp     eax, [r12 + 8]
    jne     .fail
    inc     ebx
    cmp     ebx, FAR_CASES
    jb      .check
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; A column that unloads takes the mobs, drops, primed TNT and fires inside it with it: six of each
; stand around the inclusive box (0,0)-(15,15) (two inside it, east, west of x = 0 and south of it stay)
; and then around (-16,-16)-(-1,-1) (the one in the corner goes). And a mob in a column that is not ready
; (x = 300) stands frozen: its hurt timer does not run down and it does not move, while one in a ready
; column carries on. Frozen for good it is not: at render distance 16 that mob is 18 columns from the
; player (the keep radius) and stays, at 8 (radius 10) it is forgotten; around the radius, on either side
; of x and z and with the origin moved, a frozen mob stays up to R + 2 columns away (Chebyshev) and goes
; beyond (far_cases).
test_entities_remove_box:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    mov     eax, [settings + SETTINGS.render_dist]
    mov     [rsp], eax
    call    world_clear
    call    fixture
    call    reset_player
    call    combat_reset
    call    clear_entities
    xor     ebx, ebx
.make:
    lea     eax, [rbx + rbx*2]          ; 3 words per point
    lea     rcx, [pts]
    lea     r12, [rcx + rax*4]
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [r12]
    movss   xmm1, [r12 + 4]
    movss   xmm2, [r12 + 8]
    call    mob_spawn
    test    eax, eax
    js      .fail
    mov     edi, DIRT
    mov     esi, 1
    xor     edx, edx
    movss   xmm0, [r12]
    movss   xmm1, [r12 + 4]
    movss   xmm2, [r12 + 8]
    call    drops_spawn
    test    eax, eax
    js      .fail
    imul    eax, ebx, PRIMED_size
    lea     rcx, [primed]
    add     rcx, rax
    mov     dword [rcx + PRIMED.fuse], 50
    mov     eax, [r12]
    mov     [rcx + PRIMED.body + BODY.x], eax
    mov     eax, [r12 + 8]
    mov     [rcx + PRIMED.body + BODY.z], eax
    imul    eax, ebx, FIREENT_size
    lea     rcx, [fires]
    add     rcx, rax
    lea     eax, [rbx + rbx*2]
    lea     rdx, [cells]
    mov     esi, [rdx + rax*4]
    mov     [rcx + FIREENT.x], esi
    mov     esi, [rdx + rax*4 + 4]
    mov     [rcx + FIREENT.y], esi
    mov     esi, [rdx + rax*4 + 8]
    mov     [rcx + FIREENT.z], esi
    inc     ebx
    cmp     ebx, 6
    jb      .make
    MASKS   0x3F
    BOXES   0, 0, 15, 15
    MASKS   0x3A                        ; the points 1 and 3 (indices 0 and 2) are gone
    BOXES   -16, -16, -1, -1
    MASKS   0x1A                        ; and the one at (-0.5, -0.5)
    call    clear_entities
    ; frozen mobs: a zombie in a column that is not ready, one in a ready column, both mid-hurt
    mov     dword [settings + SETTINGS.render_dist], 16     ; keep radius 18: the zombie at x = 300 is 18 columns off
    mov     dword [game_time], 40000
    SPAWN   MOB_ZOMBIE, k_10_5, k_10_5
    test    eax, eax
    js      .fail
    mov     dword [mobs + MOB.hurt], 7
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_300_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_10_5]
    call    mob_spawn
    test    eax, eax
    js      .fail
    mov     dword [mobs + MOB_size + MOB.hurt], 7
    SETF    [mobs + MOB_size + BODY.vy], 5.0
    mov     ebx, 5
.thaw:
    call    mobs_step
    dec     ebx
    jnz     .thaw
    cmp     dword [mobs + MOB.hurt], 2          ; 7 - 5 steps: the mob in the ready column ran
    jne     .fail
    cmp     dword [mobs + MOB_size + MOB.hurt], 7   ; the other one did not
    jne     .fail
    EXPECT_F [mobs + MOB_size + BODY.x], k_300_5
    EXPECT_F [mobs + MOB_size + BODY.y], k_11
    EXPECT_F [mobs + MOB_size + BODY.vy], k_5
    cmp     dword [mobs + MOB_size + MOB.type], MOB_ZOMBIE  ; 18 columns off at distance 16: still within K
    jne     .fail
    mov     dword [settings + SETTINGS.render_dist], 8      ; at 8 the radius is 10: the frozen one is forgotten
    call    mobs_step
    cmp     dword [mobs + MOB_size + MOB.type], MOB_NONE
    jne     .fail
    cmp     dword [mobs + MOB.type], MOB_ZOMBIE             ; the one in a ready column is not
    jne     .fail
    SETF    [player + BODY.x], 130.5                        ; around the radius
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 10.5
    call    far_run
    test    eax, eax
    jnz     .fail
    mov     dword [world_origin_x], 512                     ; moving the origin moves both columns alike
    mov     dword [world_origin_z], -1024
    call    far_run
    test    eax, eax
    jnz     .fail
    mov     dword [world_origin_x], 0
    mov     dword [world_origin_z], 0
    mov     eax, [rsp]
    mov     [settings + SETTINGS.render_dist], eax
    call    mask64                      ; and the table is 64 slots long all the way
    test    eax, eax
    jnz     .fail
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    clear_entities
    mov     eax, [rsp]
    mov     [settings + SETTINGS.render_dist], eax
    mov     dword [world_origin_x], 0
    mov     dword [world_origin_z], 0
    call    reset_player
    add     rsp, 16
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; Water. A pig strolling toward a pool 3 cells ahead of it never stands in water in 300 steps (it turns
; about at the shore); a zombie hunting a player across the same pool stops at its edge (fwd 0) and
; never enters it; a zombie that is in 4-deep water holds jump while one on dry ground does not.
; rbx = a counter, r12 = the mob, frame: [rsp] the highest x the mob reached
test_mob_water_ai:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    call    world_clear
    call    fixture
    call    reset_player
    call    combat_reset
    FILLB   12, 10, 6, 19, 10, 14, WATER    ; a pool flush with the floor (stone top at y = 11)
    FILLB   24, 11, 20, 28, 14, 24, WATER   ; and a deep one on the floor
    ; ---- the pig: facing +x at (8.5, 11, 10.5), mid-leg (the stroll timer will not end), walking
    SETF    [player + BODY.x], 2.5
    SETF    [player + BODY.z], 2.5
    SPAWN   MOB_PIG, k_8_5, k_10_5
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax
    SETF    [r12 + BODY.yaw], 90.0
    mov     dword [r12 + MOB.ai_timer], 100000
    mov     dword [r12 + MOB.input + INPUT.fwd], 1
    mov     dword [rsp], 0
    mov     ebx, 300
.pig:
    call    mobs_step
    call    mob_in_water
    test    eax, eax
    jnz     .fail                       ; it stood in water
    movss   xmm0, [r12 + BODY.x]
    maxss   xmm0, [rsp]
    movss   [rsp], xmm0
    dec     ebx
    jnz     .pig
    movss   xmm0, [rsp]
    ucomiss xmm0, [k_11_0]
    jbe     .fail                       ; it did walk up to the shore (x 11.3 is as far as it goes)
    ucomiss xmm0, [k_12_0]
    jae     .fail                       ; ...and no further
    call    mobs_clear
    ; ---- the zombie hunting a player on the far shore: it stops at the edge
    mov     dword [game_time], 40000
    SETF    [player + BODY.x], 22.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 10.5
    SPAWN   MOB_ZOMBIE, k_8_5, k_10_5
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax
    mov     dword [rsp], 0
    mov     ebx, 300
.zombie:
    call    mobs_step
    call    mob_in_water
    test    eax, eax
    jnz     .fail
    movss   xmm0, [r12 + BODY.x]
    maxss   xmm0, [rsp]
    movss   [rsp], xmm0
    dec     ebx
    jnz     .zombie
    movss   xmm0, [rsp]
    ucomiss xmm0, [k_11_0]
    jbe     .fail                       ; it came up to the water...
    ucomiss xmm0, [k_12_0]
    jae     .fail                       ; ...and not into it
    cmp     dword [r12 + MOB.input + INPUT.fwd], 0
    jne     .fail                       ; standing at the shore
    call    mobs_clear
    ; ---- swimming: a zombie in the deep pool holds jump; one on dry ground does not
    SETF    [player + BODY.x], 2.5
    SETF    [player + BODY.z], 2.5
    SPAWN   MOB_ZOMBIE, k_26_5, k_22_5
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax
    call    mobs_step
    cmp     dword [r12 + MOB.input + INPUT.jump], 1
    jne     .fail
    call    mobs_clear
    SPAWN   MOB_ZOMBIE, k_5_5, k_5_5
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax
    call    mobs_step
    cmp     dword [r12 + MOB.input + INPUT.jump], 0
    jne     .fail
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    mobs_clear
    call    combat_reset
    mov     eax, ebx
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mob_in_water(r12 mob) -> eax 1 when the cell of the mob's feet holds WATER
mob_in_water:
    sub     rsp, 8
    movss   xmm0, [r12 + BODY.x]
    roundss xmm0, xmm0, 9
    cvttss2si edi, xmm0
    movss   xmm0, [r12 + BODY.y]
    roundss xmm0, xmm0, 9
    cvttss2si esi, xmm0
    movss   xmm0, [r12 + BODY.z]
    roundss xmm0, xmm0, 9
    cvttss2si edx, xmm0
    call    world_get
    xor     ecx, ecx
    cmp     eax, WATER
    sete    cl
    mov     eax, ecx
    add     rsp, 8
    ret

; load_pig(xmm0 x, xmm1 y, xmm2 z) -> eax the pigs alive after mobs_load read a header whose one record is
; a level-1 pig at that position
load_pig:
    sub     rsp, 8
    movss   [hdr + WORLDHDR.mobs + MOBSAVE.x], xmm0
    movss   [hdr + WORLDHDR.mobs + MOBSAVE.y], xmm1
    movss   [hdr + WORLDHDR.mobs + MOBSAVE.z], xmm2
    mov     dword [hdr + WORLDHDR.mob_count], 1
    mov     dword [hdr + WORLDHDR.mobs + MOBSAVE.type], MOB_PIG | (1 << MS_LEVEL_SHIFT)
    mov     dword [hdr + WORLDHDR.mobs + MOBSAVE.health], 10
    call    mobs_clear
    lea     rdi, [hdr]
    call    mobs_load
    mov     edi, MOB_PIG
    call    mob_count_type
    add     rsp, 8
    ret

; spawn_pigs(edi n): n pigs standing at (3.5, 11, 3.5), far from the player
spawn_pigs:
    push    rbx
    mov     ebx, edi
.l:
    test    ebx, ebx
    jz      .done
    SPAWN   MOB_PIG, k_3_5, k_3_5
    dec     ebx
    jmp     .l
.done:
    pop     rbx
    ret

; mask64() -> eax 0 when the abilities' hit masks cover all 64 mob slots (a 32-bit mask would alias slot 40
; with slot 8): a Charge (warrior L5) into zombies in slots 8 and 40 strikes and stuns both; a Ground Slam
; (warrior L15, iron sword) stuns the zombie in slot 40 and leaves the pig in slot 8 alone
; frame: eye[3] @0, dir[3] @12
mask64:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 32
    call    world_clear
    call    fixture
    call    reset_player
    call    combat_reset
    call    inv_clear
    call    abilities_reset
    mov     byte [rpg_state + RPGSAVE.class], CLASS_WARRIOR
    mov     byte [rpg_state + RPGSAVE.level], 5
    call    rpg_recompute
    mov     dword [rpg_stats + STAT_CRIT_CHANCE * 4], 0
    SETF    [combat_stamina], 100.0
    call    stand_player                ; (16.5, 11, 16.5), facing -z
    lea     rdi, [rsp]
    call    player_eye
    lea     rdi, [rsp + 12]
    call    player_forward
    mov     edi, 8                      ; slots 0..7: pigs; slot 8: a zombie one block ahead...
    call    spawn_pigs
    SPAWN   MOB_ZOMBIE, k_16_5, k_15_5
    cmp     eax, 8
    jne     .fail
    mov     edi, 31                     ; slots 9..39: pigs; slot 40: a zombie just behind it
    call    spawn_pigs
    SPAWN   MOB_ZOMBIE, k_16_5, k_15_4
    cmp     eax, 40
    jne     .fail
    xor     edi, edi                    ; Charge
    lea     rsi, [rsp]
    lea     rdx, [rsp + 12]
    call    abilities_use
    cmp     eax, 1
    jne     .fail
    call    abilities_step
    mov     edi, 8
    call    mob_ptr
    cmp     dword [rax + MOB.stun], 30
    jne     .fail
    mov     edi, 40
    call    mob_ptr
    cmp     dword [rax + MOB.stun], 30
    jne     .fail                       ; struck too, whatever slot 8 did
    call    mobs_clear                  ; ---- Ground Slam
    call    abilities_reset
    mov     byte [rpg_state + RPGSAVE.level], 15
    mov     dword [rpg_ext + RPGEXT.ranks + 12], 0x01010101
    call    rpg_recompute
    mov     dword [rpg_stats + STAT_CRIT_CHANCE * 4], 0
    mov     dword [rpg_stats + STAT_AREA * 4], 0
    SETF    [combat_stamina], 100.0
    mov     dword [inv_sel], 0
    mov     byte [inv + INVENTORY.slots + ITEMSTACK.id], IRON_SWORD
    mov     byte [inv + INVENTORY.slots + ITEMSTACK.count], 1
    mov     edi, 40
    call    spawn_pigs                  ; slots 0..39
    SPAWN   MOB_ZOMBIE, k_16_5, k_13_5  ; slot 40, 3 blocks ahead
    cmp     eax, 40
    jne     .fail
    mov     edi, 3
    lea     rsi, [rsp]
    lea     rdx, [rsp + 12]
    call    abilities_use
    cmp     eax, 1
    jne     .fail
    mov     edi, 40
    call    mob_ptr
    cmp     dword [rax + MOB.stun], 40
    jne     .fail
    mov     edi, 8
    call    mob_ptr
    cmp     dword [rax + MOB.stun], 0
    jne     .fail                       ; a 32-bit mask would have stunned the pig too
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    mobs_clear
    call    abilities_reset
    call    rpg_reset
    call    combat_reset
    call    inv_clear
    call    fx_clear
    mov     eax, ebx
    add     rsp, 32
    pop     r12
    pop     rbx
    pop     rbp
    ret
