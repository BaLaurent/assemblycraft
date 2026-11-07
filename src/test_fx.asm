; test_fx.asm - explosion particles (spawn, expiry, shake, flash) and bouncing block debris.
%include "common.inc"
default rel

global test_fx_explosion_spawns_and_expires, test_fx_debris_falls_and_bounces

extern fx_clear, fx_explosion, fx_debris, fx_step, fx_count
extern fx_particles, fx_shake, fx_flash
extern player, body_init, rng_seed, world_clear, world_set, world_is_solid

section .rodata
align 4
k_half_w: dd 0.3
k_height: dd 1.8
k_speed:  dd 4.317
k_10:     dd 10.0
k_16_5:   dd 16.5
k_18_5:   dd 18.5
k_11_62:  dd 11.62
k_3:      dd 3.0
k_15_5:   dd 15.5
k_10_5:   dd 10.5
k_10_99:  dd 10.99
k_11_15:  dd 11.15

section .text

; test_fx_explosion_spawns_and_expires: r = 3 at 2 blocks from the player's eye makes more than
; 30 particles, shake and flash; after 200 steps there is nothing left of any of them.
test_fx_explosion_spawns_and_expires:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fx_clear
    mov     edi, 77
    call    rng_seed
    lea     rdi, [player]
    movss   xmm0, [k_half_w]
    movss   xmm1, [k_height]
    movss   xmm2, [k_speed]
    call    body_init
    movss   xmm0, [k_16_5]
    movss   [player + BODY.x], xmm0
    movss   xmm0, [k_10]
    movss   [player + BODY.y], xmm0
    movss   xmm0, [k_16_5]
    movss   [player + BODY.z], xmm0
    movss   xmm0, [k_18_5]              ; centre: 2 blocks east of the eye (16.5, 11.62, 16.5)
    movss   xmm1, [k_11_62]
    movss   xmm2, [k_16_5]
    movss   xmm3, [k_3]
    call    fx_explosion
    call    fx_count
    cmp     eax, 30
    jle     .fail1
    xorps   xmm1, xmm1
    movss   xmm0, [fx_shake]
    comiss  xmm0, xmm1
    jbe     .fail2
    movss   xmm0, [fx_flash]
    comiss  xmm0, xmm1
    jbe     .fail2
    mov     ebx, 200
.steps:
    call    fx_step
    dec     ebx
    jnz     .steps
    call    fx_count
    test    eax, eax
    jnz     .fail3
    mov     eax, [fx_shake]
    test    eax, eax
    jnz     .fail4
    mov     eax, [fx_flash]
    test    eax, eax
    jnz     .fail4
    xor     eax, eax
    jmp     .out
.fail1:
    mov     eax, 1
    jmp     .out
.fail2:
    mov     eax, 2
    jmp     .out
.fail3:
    mov     eax, 3
    jmp     .out
.fail4:
    mov     eax, 4
.out:
    mov     ebx, eax
    call    fx_clear
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; test_fx_debris_falls_and_bounces: one STONE debris cube thrown from just above a stone floor
; (top at y = 11) falls, bounces (vy goes from negative to positive) and in every one of its 80
; steps stays out of solid cells and no lower than 0.01 under the floor top.
; r13d = 1 once it came within 0.15 of the floor, 2 once it bounced, 4 while it was falling
test_fx_debris_falls_and_bounces:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    world_clear
    call    fx_clear
    mov     edi, 5
    call    rng_seed
    xor     r12d, r12d                  ; z
.floor_z:
    xor     ebx, ebx                    ; x
.floor_x:
    mov     edi, ebx
    mov     esi, 10
    mov     edx, r12d
    mov     ecx, STONE
    call    world_set
    inc     ebx
    cmp     ebx, 32
    jb      .floor_x
    inc     r12d
    cmp     r12d, 32
    jb      .floor_z
    mov     edi, 16
    mov     esi, 11
    mov     edx, 16
    mov     ecx, STONE
    movss   xmm0, [k_15_5]              ; blast centre: south-west of the cell
    movss   xmm1, [k_10_5]
    movss   xmm2, [k_15_5]
    call    fx_debris
    cmp     dword [fx_particles + PARTICLE.kind], FX_DEBRIS
    jne     .fail1
    mov     dword [fx_particles + PARTICLE.life], 80
    xor     r13d, r13d
    xor     ebx, ebx
.step:
    call    fx_step
    cmp     dword [fx_particles + PARTICLE.kind], 0
    je      .done
    movss   xmm0, [fx_particles + PARTICLE.y]
    comiss  xmm0, [k_10_99]
    jb      .fail2
    movss   xmm0, [fx_particles + PARTICLE.x]
    roundss xmm0, xmm0, 9
    cvttss2si edi, xmm0
    movss   xmm0, [fx_particles + PARTICLE.y]
    roundss xmm0, xmm0, 9
    cvttss2si esi, xmm0
    movss   xmm0, [fx_particles + PARTICLE.z]
    roundss xmm0, xmm0, 9
    cvttss2si edx, xmm0
    call    world_is_solid
    test    eax, eax
    jnz     .fail3
    movss   xmm0, [fx_particles + PARTICLE.y]
    comiss  xmm0, [k_11_15]
    ja      .no_floor
    or      r13d, 1
.no_floor:
    movss   xmm0, [fx_particles + PARTICLE.vy]
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jb      .falling
    jbe     .vy_done                    ; exactly 0
    test    r13d, 4
    jz      .vy_done
    or      r13d, 2
    jmp     .vy_done
.falling:
    or      r13d, 4
.vy_done:
    inc     ebx
    cmp     ebx, 100
    jb      .step
.done:
    and     r13d, 3
    cmp     r13d, 3
    jne     .fail4
    xor     eax, eax
    jmp     .out
.fail1:
    mov     eax, 1
    jmp     .out
.fail2:
    mov     eax, 2
    jmp     .out
.fail3:
    mov     eax, 3
    jmp     .out
.fail4:
    mov     eax, 4
.out:
    mov     ebx, eax
    call    fx_clear
    call    world_clear
    mov     eax, ebx
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
