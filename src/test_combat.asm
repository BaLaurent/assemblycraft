; test_combat.asm - arrows, explosions, and what creepers, skeletons and dying mobs do.
%include "common.inc"
default rel

global test_arrow_hits_mob, test_explosion_breaks_blocks, test_creeper_explodes
global test_skeleton_shoots_player, test_mob_drops_by_type
global test_tnt_thrown_by_blast, test_tnt_falls, test_skill_arrows_ignore_hurt_window

extern arrows, arrows_clear, arrows_spawn, arrows_step
extern primed, tnt_clear, tnt_prime, tnt_step, explode_at
extern mobs, mobs_clear, mobs_step, mob_spawn, mob_hurt
extern mob_count_type
extern drops, drops_clear
extern player, body_init, rng_seed, world_clear, world_set, world_get
extern game_mode, game_time, settings, surv, survival_reset, inv_clear, rpg_stats

section .rodata
align 4
k_half_w: dd 0.3
k_height: dd 1.8
k_speed:  dd 4.317
k_11:     dd 11.0
k_11_5:   dd 11.5
k_10_5:   dd 10.5
k_16_5:   dd 16.5
k_18_5:   dd 18.5
k_8_5:    dd 8.5
k_7_6:    dd 7.6
k_11_5f:  dd 11.5
k_m30:    dd -30.0
k_one:    dd 1.0
k_three:  dd 3.0
k_13_5:   dd 13.5
k_four:   dd 4.0
k_16:     dd 16.0                      ; 4 blocks, squared
k_11_01:  dd 11.01
k_10_99:  dd 10.99

section .bss
alignb 4
stats_keep: resd NUM_STATS              ; rpg_stats of the test that runs, kept while it works on a plain character
alignb 8
zombie_ptr: resq 1                      ; the target of two_arrows

section .text

; SETF mem, float literal
%macro SETF 2
    mov     dword %1, __float32__(%2)
%endmacro

; fixture(): the state every combat test starts from (after world_clear): rng seed 1234, no
; mobs, arrows, primed TNT, drops or inventory, Survival at Normal difficulty, early morning,
; fresh survival state, STONE floor at y = 10 for x, z in 0..31
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

; cleanup(): leave no mobs, arrows, TNT, drops or inventory behind
cleanup:
    sub     rsp, 8
    call    mobs_clear
    call    arrows_clear
    call    tnt_clear
    call    drops_clear
    call    inv_clear
    add     rsp, 8
    ret

; has_drop(edi item id) -> eax 1 when some item entity on the ground is that item
has_drop:
    lea     rcx, [drops]
    mov     edx, MAX_DROPS
.l:
    cmp     [rcx + DROP.id], dil
    je      .yes
    add     rcx, DROP_size
    dec     edx
    jnz     .l
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; EXPECT_BLOCK x, y, z, id: fail unless the cell holds that block
%macro EXPECT_BLOCK 4
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    call    world_get
    cmp     eax, %4
    jne     .fail
%endmacro

; a player arrow flies 5.5 blocks along -z and hits the pig standing in its way
test_arrow_hits_mob:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    fixture
    mov     dword [game_time], 6000
    mov     edi, MOB_PIG                ; pig at (16.5, 11, 10.5)
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_10_5]
    call    mob_spawn
    test    eax, eax
    js      .fail
    imul    ebx, eax, MOB_size
    lea     rax, [mobs]
    add     rbx, rax                    ; the pig
    movss   xmm0, [k_16_5]              ; arrow from (16.5, 11.5, 16.5) at 30 blocks/s along -z
    movss   xmm1, [k_11_5]
    movss   xmm2, [k_16_5]
    xorps   xmm3, xmm3
    xorps   xmm4, xmm4
    movss   xmm5, [k_m30]
    xor     edi, edi                    ; the player's
    mov     esi, 5                      ; damage
    mov     edx, 1                      ; can be picked up again
    mov     ecx, PROJ_ARROW
    xor     r8d, r8d
    call    arrows_spawn
    test    eax, eax
    jnz     .fail                       ; first slot
    mov     r12d, 30
.step:
    call    arrows_step
    dec     r12d
    jnz     .step
    cmp     dword [rbx + MOB.health], 5 ; 10 - 5
    jne     .fail
    cmp     dword [rbx + MOB.hurt], 0
    jle     .fail
    cmp     dword [arrows + ARROWENT.live], 0
    jne     .fail                       ; spent on the pig
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     r12d, eax
    call    cleanup
    mov     eax, r12d
    pop     r12
    pop     rbx
    pop     rbp
    ret

; a radius 3 blast at the middle of a stone cube: a sphere of air, bedrock and a shrine (unbreakable) stay,
; TNT is set off, the player 3 blocks away loses 11 health at Normal difficulty
test_explosion_breaks_blocks:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    world_clear
    call    drops_clear
    call    tnt_clear
    call    mobs_clear
    call    arrows_clear
    mov     edi, 1234
    call    rng_seed
    mov     r13d, 2                     ; stone fills x, y, z in 2..14
.fz:
    mov     r12d, 2
.fy:
    mov     ebx, 2
.fx:
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, STONE
    call    world_set
    inc     ebx
    cmp     ebx, 14
    jbe     .fx
    inc     r12d
    cmp     r12d, 14
    jbe     .fy
    inc     r13d
    cmp     r13d, 14
    jbe     .fz
    mov     edi, 8
    mov     esi, 8
    mov     edx, 8
    mov     ecx, BEDROCK
    call    world_set
    mov     edi, 8
    mov     esi, 8
    mov     edx, 11
    mov     ecx, TNT
    call    world_set
    mov     edi, 9                      ; a shrine one block east of the centre: unbreakable
    mov     esi, 8
    mov     edx, 8
    mov     ecx, SHRINE + 1
    call    world_set
    call    reset_player                ; the player stands 3 blocks east of the blast
    SETF    [player + BODY.x], 11.5
    SETF    [player + BODY.y], 7.6
    SETF    [player + BODY.z], 8.5
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    call    survival_reset
    call    inv_clear
    movss   xmm0, [k_8_5]
    movss   xmm1, [k_8_5]
    movss   xmm2, [k_8_5]
    movss   xmm3, [k_three]
    call    explode_at
    EXPECT_BLOCK 8, 8, 8, BEDROCK
    EXPECT_BLOCK 9, 8, 8, SHRINE + 1    ; inside the blast, and still there
    EXPECT_BLOCK 8, 8, 5, AIR           ; exactly 3 blocks away: inside
    EXPECT_BLOCK 8, 8, 4, STONE
    EXPECT_BLOCK 10, 10, 8, AIR
    EXPECT_BLOCK 10, 10, 10, STONE
    EXPECT_BLOCK 8, 8, 11, AIR          ; the TNT was set off...
    mov     eax, [primed + PRIMED.fuse]
    sub     eax, 10
    cmp     eax, 19                     ; ...with a fuse of 10..29
    ja      .fail
    cmp     dword [surv + SURVIVAL.health], 9
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; a creeper 2 blocks from the player lights its fuse, burns it down and blows a crater
test_creeper_explodes:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    mov     dword [game_time], 40000    ; night
    call    reset_player
    SETF    [player + BODY.x], 16.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 16.5
    mov     edi, MOB_CREEPER
    movss   xmm0, [k_18_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_16_5]
    call    mob_spawn
    test    eax, eax
    js      .fail
    mov     ebx, 95
.again:
    call    mobs_step
    call    arrows_step
    call    tnt_step
    dec     ebx
    jnz     .again
    mov     edi, MOB_CREEPER
    call    mob_count_type
    test    eax, eax
    jnz     .fail                       ; it blew up
    cmp     dword [surv + SURVIVAL.health], 20
    jge     .fail                       ; and hurt the player
    EXPECT_BLOCK 18, 10, 16, AIR        ; the floor under it is gone
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; a skeleton 8 blocks away with a clear line shoots the player within 4 seconds
test_skeleton_shoots_player:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    mov     dword [game_time], 40000    ; night: the skeleton does not burn
    call    reset_player
    SETF    [player + BODY.x], 16.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 16.5
    mov     edi, MOB_SKELETON
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_8_5]
    call    mob_spawn
    test    eax, eax
    js      .fail
    mov     ebx, 240
.again:
    call    mobs_step
    call    arrows_step
    dec     ebx
    jnz     .again
    cmp     dword [surv + SURVIVAL.health], 17
    jg      .fail                       ; at least one arrow (3 damage at Normal) landed
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; drop_rounds(edi mob type, esi item, edx rounds) -> eax 0 when killing that many of the type at
; (8.5, 11, 8.5) left at least one entity of the item on the ground
; rbx = type, r12d = item, r13d = rounds left
drop_rounds:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    call    drops_clear
.round:
    mov     edi, ebx
    movss   xmm0, [k_8_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_8_5]
    call    mob_spawn
    test    eax, eax
    js      .fail
    mov     edi, eax
    mov     esi, 100                    ; far more than any health
    xorps   xmm0, xmm0
    movss   xmm1, [k_one]
    call    mob_hurt
    cmp     eax, 1
    jne     .fail
    dec     r13d
    jnz     .round
    mov     edi, r12d
    call    has_drop
    test    eax, eax
    jz      .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; each type's loot: rotten flesh, gunpowder, arrows, string, and a chicken's raw meat
test_mob_drops_by_type:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    mov     edi, MOB_ZOMBIE
    mov     esi, ROTTEN_FLESH
    mov     edx, 10
    call    drop_rounds
    test    eax, eax
    jnz     .fail
    mov     edi, MOB_CREEPER
    mov     esi, GUNPOWDER
    mov     edx, 10
    call    drop_rounds
    test    eax, eax
    jnz     .fail
    mov     edi, MOB_SKELETON
    mov     esi, ARROW
    mov     edx, 10
    call    drop_rounds
    test    eax, eax
    jnz     .fail
    mov     edi, MOB_SPIDER
    mov     esi, STRING
    mov     edx, 10
    call    drop_rounds
    test    eax, eax
    jnz     .fail
    mov     edi, MOB_CHICKEN
    mov     esi, RAW_CHICKEN
    mov     edx, 1
    call    drop_rounds
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; A primed TNT 3 blocks from a radius-4 blast is thrown more than 4 blocks away from it
; (horizontally) within half a second; its long fuse keeps it from going off.
test_tnt_thrown_by_blast:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    fixture
    mov     edi, 16
    mov     esi, 11
    mov     edx, 16
    mov     ecx, 200
    call    tnt_prime
    movss   xmm0, [k_13_5]
    movss   xmm1, [k_11_5]
    movss   xmm2, [k_16_5]
    movss   xmm3, [k_four]
    call    explode_at
    mov     r12d, 30
.step:
    call    tnt_step
    dec     r12d
    jnz     .step
    cmp     dword [primed + PRIMED.fuse], 0
    je      .fail                       ; it must still be burning
    movss   xmm0, [primed + PRIMED.body + BODY.x]
    subss   xmm0, [k_13_5]
    mulss   xmm0, xmm0
    movss   xmm1, [primed + PRIMED.body + BODY.z]
    subss   xmm1, [k_16_5]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [k_16]
    jbe     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     r12d, eax
    call    cleanup
    mov     eax, r12d
    pop     r12
    pop     rbx
    pop     rbp
    ret

; A primed TNT lit 3 blocks above the floor falls and comes to rest on it.
test_tnt_falls:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    fixture
    mov     edi, 16
    mov     esi, 14
    mov     edx, 16
    mov     ecx, 200
    call    tnt_prime
    mov     r12d, 60
.step:
    call    tnt_step
    dec     r12d
    jnz     .step
    movss   xmm0, [primed + PRIMED.body + BODY.y]
    comiss  xmm0, [k_11_01]
    ja      .fail
    comiss  xmm0, [k_10_99]
    jb      .fail
    cmp     dword [primed + PRIMED.body + BODY.on_ground], 0
    je      .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     r12d, eax
    call    cleanup
    mov     eax, r12d
    pop     r12
    pop     rbx
    pop     rbp
    ret

; two_arrows(esi AF_* flags) -> eax the health of the zombie (zombie_ptr: 20 health, no hurt window)
; after two 5-damage arrows with those flags, shot one step apart from 6 blocks away at 30 blocks/s,
; have flown 30 steps
two_arrows:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, esi
    mov     rax, [zombie_ptr]
    mov     dword [rax + MOB.health], 20
    mov     dword [rax + MOB.hurt], 0
    call    arrows_clear
    mov     r12d, 2
.spawn:
    movss   xmm0, [k_16_5]              ; from (16.5, 11.5, 16.5) along -z
    movss   xmm1, [k_11_5]
    movss   xmm2, [k_16_5]
    xorps   xmm3, xmm3
    xorps   xmm4, xmm4
    movss   xmm5, [k_m30]
    xor     edi, edi                    ; the player's
    mov     esi, 5
    xor     edx, edx
    mov     ecx, PROJ_ARROW
    mov     r8d, ebx
    call    arrows_spawn
    call    arrows_step                 ; the next arrow flies one step behind
    dec     r12d
    jnz     .spawn
    mov     r12d, 30
.fly:
    call    arrows_step
    dec     r12d
    jnz     .fly
    mov     rax, [zombie_ptr]
    mov     eax, [rax + MOB.health]
    pop     r12
    pop     rbx
    pop     rbp
    ret

; Skill arrows (Volley, Arrow Rain: no AF_ATTACK) never wait for the mob's hurt window: both of two
; arrows a step apart hurt the zombie (20 - 5 - 5). A bow shot (AF_ATTACK) does wait, so the second
; is refused (20 - 5). The Barrage's extra arrows (AF_ATTACK | AF_NOWIN) land too (20 - 5 - 5).
test_skill_arrows_ignore_hurt_window:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    mov     dword [game_time], 40000    ; night: no sunburn
    lea     rsi, [rpg_stats]
    lea     rdi, [stats_keep]
    mov     ecx, NUM_STATS
    rep     movsd
    lea     rdi, [rpg_stats]            ; a plain character: the arrows deal their 5
    mov     ecx, NUM_STATS
    xor     eax, eax
    rep     stosd
    mov     edi, MOB_ZOMBIE             ; zombie at (16.5, 11, 10.5)
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_10_5]
    call    mob_spawn
    test    eax, eax
    js      .fail
    imul    eax, eax, MOB_size
    lea     rcx, [mobs]
    add     rax, rcx
    mov     [zombie_ptr], rax
    xor     esi, esi                    ; a skill's arrows
    call    two_arrows
    cmp     eax, 20 - 5 - 5
    jne     .fail
    mov     esi, AF_ATTACK              ; a bow shot
    call    two_arrows
    cmp     eax, 20 - 5
    jne     .fail
    mov     esi, AF_ATTACK | AF_NOWIN   ; a Barrage extra
    call    two_arrows
    cmp     eax, 20 - 5 - 5
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    lea     rsi, [stats_keep]
    lea     rdi, [rpg_stats]
    mov     ecx, NUM_STATS
    rep     movsd
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret
