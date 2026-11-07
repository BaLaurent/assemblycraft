; survival.asm - health, hunger, damage and eating (survival mode state machine).
%include "common.inc"
default rel

global surv
global survival_reset, survival_damage, survival_land, survival_exhaust
global survival_step, survival_eat_step, survival_can_sprint

extern game_mode, settings, player
extern audio_play, inv_held, inv_consume_held
extern item_food, item_saturation, block_step_sound
extern world_get, world_is_solid, world_is_opaque

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
starve_floor: db 0, 10, 1, 0            ; per difficulty: health that starvation stops at

section .bss
align 4
surv: resb SURVIVAL_size

section .text

; survival_reset(): full health and food, everything else zero
survival_reset:
    lea     rdi, [surv]
    mov     ecx, SURVIVAL_size
    xor     eax, eax
    rep     stosb
    mov     dword [surv + SURVIVAL.health], 20
    mov     dword [surv + SURVIVAL.food], 20
    mov     dword [surv + SURVIVAL.saturation], __float32__(5.0)
    ret

; survival_damage(edi amount, esi cause) -> eax 1 if applied
survival_damage:
    push    rbp
    mov     rbp, rsp
    cmp     dword [game_mode], MODE_CREATIVE
    je      .no
    cmp     dword [surv + SURVIVAL.dead], 0
    jne     .no
    cmp     dword [surv + SURVIVAL.invuln], 0
    jg      .no
    mov     eax, [surv + SURVIVAL.health]
    sub     eax, edi
    xor     edx, edx
    test    eax, eax
    cmovs   eax, edx
    mov     [surv + SURVIVAL.health], eax
    mov     dword [surv + SURVIVAL.invuln], 30
    mov     dword [surv + SURVIVAL.hurt_flash], 20
    movss   xmm0, [surv + SURVIVAL.exhaustion]
    addss   xmm0, [k_0_1]
    movss   [surv + SURVIVAL.exhaustion], xmm0
    test    eax, eax
    jnz     .alive
    mov     dword [surv + SURVIVAL.dead], 1
    mov     [surv + SURVIVAL.death_cause], esi
.alive:
    mov     edi, SND_HURT
    movss   xmm0, [k_1]
    call    audio_play
    mov     eax, 1
    pop     rbp
    ret
.no:
    xor     eax, eax
    pop     rbp
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

; survival_step(rdi INPUT*, xmm0 horiz_dist, esi jumped): one fixed step, survival only
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
    cmp     dword [surv + SURVIVAL.health], 20
    jge     .suffocate
    inc     dword [surv + SURVIVAL.health]
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
    cmp     dword [surv + SURVIVAL.health], 20
    jge     .no_regen
    inc     dword [surv + SURVIVAL.regen_timer]
    cmp     dword [surv + SURVIVAL.regen_timer], 240
    jb      .starve
    mov     dword [surv + SURVIVAL.regen_timer], 0
    inc     dword [surv + SURVIVAL.health]
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
    mov     eax, [settings + SETTINGS.difficulty]
    and     eax, 3
    lea     rcx, [starve_floor]
    movzx   eax, byte [rcx + rax]
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
    jb      .timers
    mov     dword [surv + SURVIVAL.suffocate_timer], 0
    mov     edi, 1
    mov     esi, CAUSE_SUFFOCATE
    call    survival_damage
    jmp     .timers
.clear:
    mov     dword [surv + SURVIVAL.suffocate_timer], 0
    ; 7. timers count down
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
