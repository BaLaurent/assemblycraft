; test_mobs.asm - mob ray picking, damage and drops, zombie attacks, spawn rules.
%include "common.inc"
default rel

global test_mob_raycast_hits, test_mob_hurt_pig_drops_food
global test_zombie_attacks_player, test_mob_spawn_rules

extern mobs, mobs_clear, mobs_step, mob_spawn, mobs_raycast, mob_hurt, mob_count_type
extern player, body_init, rng_seed, world_clear, world_set, world_mark_all_dirty, blocks
extern game_mode, game_time, settings, surv, survival_reset, inv, inv_clear

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

section .text

; SETF mem, float literal
%macro SETF 2
    mov     dword %1, __float32__(%2)
%endmacro

; fixture(): the state every mob test starts from (after world_clear): rng seed 1234, no mobs,
; Survival at Normal difficulty, early morning, fresh survival state, STONE floor at y = 10
; for x, z in 0..31
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
    movzx   eax, byte [inv + INVENTORY.slots + ITEMSTACK.id]
    cmp     eax, PORKCHOP
    jne     .fail
    movzx   eax, byte [inv + INVENTORY.slots + ITEMSTACK.count]
    dec     eax
    cmp     eax, 2                      ; 1..3
    ja      .fail
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
    mov     dword [game_time], 40000    ; night: the zombie must not burn during the test
    SETF    [player + BODY.x], 16.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 16.5
    SPAWN   MOB_ZOMBIE, k_17_5, k_16_5
    test    eax, eax
    js      .fail
    call    mobs_step
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

test_mob_spawn_rules:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    lea     rdi, [blocks + (10 << 16)]  ; GRASS over the whole layer y = 10
    mov     ecx, WORLD_X * WORLD_Z
    mov     al, GRASS
    rep     stosb
    call    world_mark_all_dirty
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
    mov     edi, MOB_ZOMBIE
    call    mob_count_type
    dec     eax
    cmp     eax, 7                      ; 1..8 zombies
    ja      .fail
    call    mobs_clear
    mov     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL
    mov     ebx, 600
.peaceful:
    call    mobs_step
    inc     dword [game_time]
    dec     ebx
    jnz     .peaceful
    mov     edi, MOB_ZOMBIE
    call    mob_count_type
    test    eax, eax
    jnz     .fail
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    call    mobs_clear
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret
