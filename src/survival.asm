; survival.asm - health, hunger, damage and eating (survival mode state machine).
%include "common.inc"
default rel

global surv, surv_max_health
global survival_reset, survival_damage, survival_land, survival_exhaust
global survival_step, survival_eat_step, survival_can_sprint, survival_dot

extern game_mode, settings, player
extern audio_play, inv_held, inv_consume_held, armor_points
extern item_food, item_saturation, block_step_sound
extern world_get, world_is_solid, world_is_opaque
extern rpg_stats, gear_powers, combat_phoenix_cd, fx_burst, hud_banner
extern player_eye_in_water, sleep_cancel, body_in_liquid, combat_player_status, game_time

section .rodata
align 4
k_0_01:    dd 0.01
k_0_05:    dd 0.05
k_0_1:     dd 0.1
k_0_2:     dd 0.2
k_0_6:     dd 0.6
k_0_7:     dd 0.7
k_1:       dd 1.0
k_3:       dd 3.0
k_4:       dd 4.0
k_eye:     dd 1.62                      ; head height above the feet
k_below:   dd 0.1                       ; probe depth under the feet
k_1_2:     dd 1.2                       ; chest height above the feet (effect origin)
k_20:      dd 20.0                      ; the health environmental damage amounts are given for
s_phoenix: db "The Phoenix Ring saves you!", 0
starve_floor: db 0, 10, 1, 0            ; per difficulty: health that starvation stops at

section .bss
align 4
surv: resb SURVIVAL_size

section .data
align 4
surv_max_health: dd 20                  ; health cap in half hearts; rpg_recompute sets it

section .text

; survival_reset(): full health (surv_max_health) and food, a full lung of air, everything else zero
survival_reset:
    lea     rdi, [surv]
    mov     ecx, SURVIVAL_size
    xor     eax, eax
    rep     stosb
    mov     eax, [surv_max_health]
    mov     [surv + SURVIVAL.health], eax
    mov     dword [surv + SURVIVAL.food], 20
    mov     dword [surv + SURVIVAL.saturation], __float32__(5.0)
    mov     dword [surv + SURVIVAL.breath], MAX_BREATH
    ret

; survival_damage(edi amount, esi cause) -> eax 1 if applied. Armor (worn points plus the RPG
; armor bonus, at most 20) reduces damage from mobs (a faction's folk: CAUSE_FOLK..CAUSE_LAST)
; and explosions; environmental damage (a fall, fire, hunger, suffocation, drowning) is given for
; a 20-health character and scales with the maximum health (env_scale). A hit that lands starts
; 30 steps of invulnerability and wakes a sleeper (sleep_cancel). A blow that would kill may be
; undone by the Phoenix ring (lower_health).
survival_damage:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12d, esi
    cmp     dword [game_mode], MODE_CREATIVE
    je      .no
    cmp     dword [surv + SURVIVAL.dead], 0
    jne     .no
    cmp     dword [surv + SURVIVAL.invuln], 0
    jg      .no
    cmp     r12d, CAUSE_ZOMBIE
    je      .armored
    cmp     r12d, CAUSE_BOSS
    je      .armored
    lea     eax, [r12 - CAUSE_FOLK]     ; a faction's folk: CAUSE_FOLK .. CAUSE_LAST
    cmp     eax, CAUSE_LAST - CAUSE_FOLK
    jbe     .armored
    cmp     r12d, CAUSE_SKELETON
    jb      .environment
    cmp     r12d, CAUSE_SPIDER
    ja      .environment
.armored:
    call    armor_points
    add     eax, [rpg_stats + STAT_ARMOR_BONUS * 4]
    mov     ecx, 20
    cmp     eax, ecx
    cmovg   eax, ecx                    ; at most 20 points
    test    eax, eax
    jz      .apply
    mov     ecx, 25
    sub     ecx, eax
    imul    ecx, ebx                    ; amount * (25 - points)
    lea     eax, [rcx + 12]
    xor     edx, edx
    mov     ecx, 25
    div     ecx
    mov     ecx, 1
    cmp     eax, ecx
    cmovb   eax, ecx                    ; max(1, ...)
    mov     ebx, eax
    jmp     .apply
.environment:                           ; a fall, hunger, suffocation, fire or drowning: scaled to the health
    cmp     r12d, CAUSE_POISON
    je      .apply
    mov     edi, ebx
    call    env_scale
    mov     ebx, eax
.apply:
    call    sleep_cancel
    mov     dword [surv + SURVIVAL.invuln], 30
    mov     dword [surv + SURVIVAL.hurt_flash], 20
    movss   xmm0, [surv + SURVIVAL.exhaustion]
    addss   xmm0, [k_0_1]
    movss   [surv + SURVIVAL.exhaustion], xmm0
    mov     edi, ebx
    mov     esi, r12d
    call    lower_health                ; the Phoenix may replace the invulnerability by a longer one
    mov     edi, SND_HURT
    movss   xmm0, [k_1]
    call    audio_play
    mov     eax, 1
    pop     r12
    pop     rbx
    pop     rbp
    ret
.no:
    xor     eax, eax
    pop     r12
    pop     rbx
    pop     rbp
    ret

; survival_dot(edi amount, esi cause) -> eax 1 if applied. Damage over time (burn, poison): no armor,
; no sound, and invulnerability neither stops it nor is started by it; it flashes the screen. Nothing
; in creative, for the dead, or for an amount below 1. A lethal tick is handled as in survival_damage.
survival_dot:
    cmp     dword [game_mode], MODE_CREATIVE
    je      .no
    cmp     dword [surv + SURVIVAL.dead], 0
    jne     .no
    test    edi, edi
    jle     .no
    sub     rsp, 8
    call    lower_health
    mov     dword [surv + SURVIVAL.hurt_flash], 10
    add     rsp, 8
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; lower_health(edi amount, esi cause): the damage lands, health down by amount. A blow that would
; kill is undone by the Phoenix ring (gear_powers) once per 2 minutes: health back to half the
; maximum (at least 1), 60 steps of invulnerability, flames, a sound and a banner. Otherwise the
; player dies of that cause with 0 health.
lower_health:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, esi
    mov     eax, [surv + SURVIVAL.health]
    sub     eax, edi
    jg      .store                      ; still standing
    test    dword [gear_powers], 1 << LP_PHOENIX
    jz      .dead
    cmp     dword [combat_phoenix_cd], 0
    jg      .dead
    mov     eax, [surv_max_health]
    shr     eax, 1
    mov     ecx, 1
    cmp     eax, ecx
    cmovl   eax, ecx
    mov     [surv + SURVIVAL.health], eax
    mov     dword [surv + SURVIVAL.invuln], 60
    mov     dword [combat_phoenix_cd], 7200
    movss   xmm0, [player + BODY.x]
    movss   xmm1, [player + BODY.y]
    addss   xmm1, [k_1_2]
    movss   xmm2, [player + BODY.z]
    movss   xmm3, [k_3]
    mov     edi, FX_FIRE
    mov     esi, 40
    call    fx_burst
    mov     edi, SND_FIREBALL
    movss   xmm0, [k_1]
    call    audio_play
    lea     rdi, [s_phoenix]
    mov     esi, RGBA(255, 140, 40, 255)
    call    hud_banner
    jmp     .out
.dead:
    mov     dword [surv + SURVIVAL.health], 0
    mov     dword [surv + SURVIVAL.dead], 1
    mov     [surv + SURVIVAL.death_cause], ebx
    jmp     .out
.store:
    mov     [surv + SURVIVAL.health], eax
.out:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; env_scale(edi base) -> eax max(1, round(base * max health / 20)): environmental damage is given
; for a character of 20 health
env_scale:
    cvtsi2ss xmm0, edi
    cvtsi2ss xmm1, dword [surv_max_health]
    mulss   xmm0, xmm1
    divss   xmm0, [k_20]
    cvtss2si eax, xmm0
    mov     ecx, 1
    cmp     eax, ecx
    cmovl   eax, ecx
    ret

; regen_heal(): one regeneration tick: health + max(1, max health / 20), at most the maximum
regen_heal:
    mov     eax, [surv_max_health]
    xor     edx, edx
    mov     ecx, 20
    div     ecx
    mov     ecx, 1
    cmp     eax, ecx
    cmovb   eax, ecx
    add     eax, [surv + SURVIVAL.health]
    mov     ecx, [surv_max_health]
    cmp     eax, ecx
    cmovg   eax, ecx
    mov     [surv + SURVIVAL.health], eax
    ret

; survival_land(xmm0 dist): fall damage beyond 3 blocks, thud for any real landing
survival_land:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    movss   [rsp], xmm0
    ucomiss xmm0, [k_3]
    jbe     .thud
    subss   xmm0, [k_3]
    roundss xmm0, xmm0, 10              ; ceil
    cvttss2si edi, xmm0
    mov     esi, CAUSE_FALL
    call    survival_damage
.thud:
    movss   xmm0, [rsp]
    ucomiss xmm0, [k_1]
    jb      .done
    movss   xmm0, [player + BODY.x]
    roundss xmm0, xmm0, 9
    cvttss2si edi, xmm0
    movss   xmm0, [player + BODY.y]
    subss   xmm0, [k_below]
    roundss xmm0, xmm0, 9
    cvttss2si esi, xmm0
    movss   xmm0, [player + BODY.z]
    roundss xmm0, xmm0, 9
    cvttss2si edx, xmm0
    call    world_get
    test    eax, eax
    jz      .done
    movzx   edi, byte [block_step_sound + rax]
    movss   xmm0, [k_0_6]
    call    audio_play
.done:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; survival_exhaust(xmm0 amount)
survival_exhaust:
    addss   xmm0, [surv + SURVIVAL.exhaustion]
    movss   [surv + SURVIVAL.exhaustion], xmm0
    ret

; survival_step(rdi INPUT*, xmm0 horiz_dist, esi jumped): one fixed step, survival only (game.asm calls it in
; Survival only, so Creative never burns in lava)
survival_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 24                     ; [rsp..+12) head cell x, y, z
    cmp     dword [surv + SURVIVAL.dead], 0
    jne     .done
    ; 1. exhaustion from movement
    movss   xmm1, [k_0_01]
    movss   xmm3, [k_0_05]
    cmp     dword [rdi + INPUT.sprint], 0
    je      .walk
    movss   xmm1, [k_0_1]
    movss   xmm3, [k_0_2]
.walk:
    mulss   xmm0, xmm1
    test    esi, esi
    jz      .nojump
    addss   xmm0, xmm3
.nojump:
    addss   xmm0, [surv + SURVIVAL.exhaustion]
    movss   [surv + SURVIVAL.exhaustion], xmm0
    ; 2. peaceful: no hunger, slow regeneration
    cmp     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL
    jne     .drain
    mov     dword [surv + SURVIVAL.exhaustion], 0
    inc     dword [surv + SURVIVAL.regen_timer]
    cmp     dword [surv + SURVIVAL.regen_timer], 60
    jb      .suffocate
    mov     dword [surv + SURVIVAL.regen_timer], 0
    mov     eax, [surv_max_health]
    cmp     [surv + SURVIVAL.health], eax
    jge     .suffocate
    call    regen_heal
    jmp     .suffocate
    ; 3. drain: every 4.0 exhaustion costs saturation, then food
.drain:
    movss   xmm0, [surv + SURVIVAL.exhaustion]
    xorps   xmm2, xmm2
.drain_loop:
    ucomiss xmm0, [k_4]
    jb      .drain_done
    subss   xmm0, [k_4]
    movss   xmm1, [surv + SURVIVAL.saturation]
    ucomiss xmm1, xmm2
    jbe     .food_down
    subss   xmm1, [k_1]
    maxss   xmm1, xmm2
    movss   [surv + SURVIVAL.saturation], xmm1
    jmp     .drain_loop
.food_down:
    mov     eax, [surv + SURVIVAL.food]
    dec     eax
    xor     edx, edx
    test    eax, eax
    cmovs   eax, edx
    mov     [surv + SURVIVAL.food], eax
    jmp     .drain_loop
.drain_done:
    movss   [surv + SURVIVAL.exhaustion], xmm0
    ; 4. regeneration while well fed
    cmp     dword [surv + SURVIVAL.food], 18
    jl      .no_regen
    mov     eax, [surv_max_health]
    cmp     [surv + SURVIVAL.health], eax
    jge     .no_regen
    inc     dword [surv + SURVIVAL.regen_timer]
    cmp     dword [surv + SURVIVAL.regen_timer], 240
    jb      .starve
    mov     dword [surv + SURVIVAL.regen_timer], 0
    call    regen_heal
    movss   xmm0, [surv + SURVIVAL.exhaustion]
    addss   xmm0, [k_3]
    movss   [surv + SURVIVAL.exhaustion], xmm0
    jmp     .starve
.no_regen:
    mov     dword [surv + SURVIVAL.regen_timer], 0
    ; 5. starvation
.starve:
    cmp     dword [surv + SURVIVAL.food], 0
    jne     .fed
    inc     dword [surv + SURVIVAL.starve_timer]
    cmp     dword [surv + SURVIVAL.starve_timer], 240
    jb      .suffocate
    mov     dword [surv + SURVIVAL.starve_timer], 0
    mov     edi, 1
    call    env_scale                   ; one starvation tick, in the unit survival_damage applies
    mov     edx, [settings + SETTINGS.difficulty]
    and     edx, 3
    lea     rcx, [starve_floor]
    movzx   edx, byte [rcx + rdx]
    imul    eax, edx                    ; the floor is whole ticks, so a tick never crosses it
    cmp     [surv + SURVIVAL.health], eax
    jle     .suffocate
    mov     edi, 1
    mov     esi, CAUSE_STARVE
    call    survival_damage
    jmp     .suffocate
.fed:
    mov     dword [surv + SURVIVAL.starve_timer], 0
    ; 6. suffocation: head inside a solid, opaque block
.suffocate:
    movss   xmm0, [player + BODY.x]
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    mov     [rsp], eax
    movss   xmm0, [player + BODY.y]
    addss   xmm0, [k_eye]
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    mov     [rsp + 4], eax
    movss   xmm0, [player + BODY.z]
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    mov     [rsp + 8], eax
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    mov     edx, [rsp + 8]
    call    world_is_solid
    test    eax, eax
    jz      .clear
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    mov     edx, [rsp + 8]
    call    world_is_opaque
    test    eax, eax
    jz      .clear
    inc     dword [surv + SURVIVAL.suffocate_timer]
    cmp     dword [surv + SURVIVAL.suffocate_timer], 30
    jb      .breath
    mov     dword [surv + SURVIVAL.suffocate_timer], 0
    mov     edi, 1
    mov     esi, CAUSE_SUFFOCATE
    call    survival_damage
    jmp     .breath
.clear:
    mov     dword [surv + SURVIVAL.suffocate_timer], 0
    ; 7. breath: under water the air runs out, then 1 drowning damage every 60 steps; in the air it
    ; comes back 5 steps at a time
.breath:
    call    player_eye_in_water
    test    eax, eax
    jz      .air
    mov     eax, [surv + SURVIVAL.breath]
    test    eax, eax
    jz      .drowning
    dec     eax
    mov     [surv + SURVIVAL.breath], eax
    jnz     .lava
.drowning:
    inc     dword [surv + SURVIVAL.drown_timer]
    cmp     dword [surv + SURVIVAL.drown_timer], 60
    jb      .lava
    mov     dword [surv + SURVIVAL.drown_timer], 0
    mov     edi, 1
    mov     esi, CAUSE_DROWN
    call    survival_damage
    jmp     .lava
.air:
    mov     eax, [surv + SURVIVAL.breath]
    add     eax, 5
    mov     ecx, MAX_BREATH
    cmp     eax, ecx
    cmovg   eax, ecx
    mov     [surv + SURVIVAL.breath], eax
    mov     dword [surv + SURVIVAL.drown_timer], 0
    ; 8. lava: a player standing in it burns (combat_player_status, STS_BURN: 3 s, ticked by combat_step's
    ; damage over time) and on every 10th step of game_time the lava itself strikes for 4 (fire damage
    ; scaled to the maximum health, no armor; the 30 steps of invulnerability it starts leave one strike
    ; in 30 steps)
.lava:
    lea     rdi, [player]
    call    body_in_liquid
    cmp     eax, LAVA
    jne     .timers
    mov     edi, STS_BURN
    mov     esi, 24
    call    combat_player_status
    mov     eax, [game_time]
    xor     edx, edx
    mov     ecx, 10
    div     ecx
    test    edx, edx
    jnz     .timers
    mov     edi, 4
    mov     esi, CAUSE_FIRE
    call    survival_damage
    ; 9. timers count down
.timers:
    cmp     dword [surv + SURVIVAL.invuln], 0
    jle     .flash
    dec     dword [surv + SURVIVAL.invuln]
.flash:
    cmp     dword [surv + SURVIVAL.hurt_flash], 0
    jle     .done
    dec     dword [surv + SURVIVAL.hurt_flash]
.done:
    add     rsp, 24
    pop     rbx
    pop     rbp
    ret

; survival_eat_step(edi rmb_held) -> eax 1 on the step an item is finished
survival_eat_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    test    edi, edi
    jz      .no
    cmp     dword [surv + SURVIVAL.food], 20
    jge     .no
    call    inv_held
    cmp     byte [rax + ITEMSTACK.count], 0
    je      .no
    movzx   ebx, byte [rax + ITEMSTACK.id]
    cmp     ebx, NUM_ITEMS
    jae     .no
    lea     rax, [item_food]
    cmp     byte [rax + rbx], 0
    je      .no
    inc     dword [surv + SURVIVAL.eat_timer]
    mov     eax, [surv + SURVIVAL.eat_timer]
    cmp     eax, 96
    jae     .finish
    xor     edx, edx
    mov     ecx, 15
    div     ecx
    test    edx, edx
    jnz     .zero
    mov     edi, SND_EAT
    movss   xmm0, [k_0_6]
    call    audio_play
.zero:
    xor     eax, eax
    jmp     .out
.finish:
    lea     rax, [item_food]
    movzx   eax, byte [rax + rbx]
    add     eax, [surv + SURVIVAL.food]
    mov     edx, 20
    cmp     eax, edx
    cmovg   eax, edx
    mov     [surv + SURVIVAL.food], eax
    cvtsi2ss xmm1, eax
    lea     rax, [item_saturation]
    movss   xmm0, [surv + SURVIVAL.saturation]
    addss   xmm0, [rax + rbx*4]
    minss   xmm0, xmm1
    movss   [surv + SURVIVAL.saturation], xmm0
    mov     edi, 1
    call    inv_consume_held
    mov     dword [surv + SURVIVAL.eat_timer], 0
    mov     edi, SND_BURP
    movss   xmm0, [k_0_7]
    call    audio_play
    mov     eax, 1
    jmp     .out
.no:
    mov     dword [surv + SURVIVAL.eat_timer], 0
    xor     eax, eax
.out:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; survival_can_sprint() -> eax
survival_can_sprint:
    cmp     dword [game_mode], MODE_CREATIVE
    je      .yes
    xor     eax, eax
    cmp     dword [surv + SURVIVAL.food], 6
    setg    al
    ret
.yes:
    mov     eax, 1
    ret
