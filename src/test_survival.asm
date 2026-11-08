; test_survival.asm - survival rules and day/night cycle tests.
%include "common.inc"
default rel

global test_fall_damage, test_exhaustion_drains, test_regen_when_fed
global test_damage_invulnerability, test_starvation_floor, test_sky_day_cycle
global test_armor_reduces_damage

extern surv, survival_reset, survival_damage, survival_land, survival_exhaust, survival_step
extern surv_max_health
extern sky_brightness, sky_is_night
extern game_mode, settings, world_clear
extern inv, inv_clear, armor_points

section .rodata
align 4
k_eps:   dd 0.0001
k_0_5:   dd 0.5
k_3_0:   dd 3.0
k_5_0:   dd 5.0
k_3_5:   dd 3.5
k_8_0:   dd 8.0
k_8_5:   dd 8.5
k_1_0:   dd 1.0
k_0_625: dd 0.625
k_0_25:  dd 0.25

section .bss
align 4
inp: resb INPUT_size                    ; zero input for survival_step

section .text

; fail unless |float at %1 - float constant %2| < 1e-4
%macro FNEAR 2
    movss   xmm0, %1
    subss   xmm0, [%2]
    andps   xmm0, [absmask]
    ucomiss xmm0, [k_eps]
    jae     .fail
%endmacro

section .rodata
align 16
absmask: dd 0x7FFFFFFF, 0, 0, 0
section .text

; setup(): empty world, survival mode, normal difficulty, fresh state, zero input
setup:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    call    survival_reset
    lea     rdi, [inp]
    mov     ecx, INPUT_size
    xor     eax, eax
    rep     stosb
    pop     rbp
    ret

; steps(edi n): n times survival_step(&inp, 0.0, 0)
steps:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
.loop:
    lea     rdi, [inp]
    xorps   xmm0, xmm0
    xor     esi, esi
    call    survival_step
    dec     ebx
    jnz     .loop
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

test_fall_damage:
    push    rbp
    mov     rbp, rsp
    call    setup
    movss   xmm0, [k_5_0]
    call    survival_land
    cmp     dword [surv + SURVIVAL.health], 18
    jne     .fail
    mov     dword [surv + SURVIVAL.invuln], 0
    movss   xmm0, [k_3_0]
    call    survival_land
    cmp     dword [surv + SURVIVAL.health], 18
    jne     .fail
    mov     dword [surv + SURVIVAL.invuln], 0
    movss   xmm0, [k_3_5]
    call    survival_land
    cmp     dword [surv + SURVIVAL.health], 17
    jne     .fail
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret

test_exhaustion_drains:
    push    rbp
    mov     rbp, rsp
    call    setup
    movss   xmm0, [k_8_5]
    call    survival_exhaust
    mov     edi, 1
    call    steps
    FNEAR   [surv + SURVIVAL.exhaustion], k_0_5
    FNEAR   [surv + SURVIVAL.saturation], k_3_0
    cmp     dword [surv + SURVIVAL.food], 20
    jne     .fail
    mov     dword [surv + SURVIVAL.saturation], 0
    movss   xmm0, [k_8_0]
    call    survival_exhaust
    mov     edi, 1
    call    steps
    cmp     dword [surv + SURVIVAL.food], 18
    jne     .fail
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret

test_regen_when_fed:
    push    rbp
    mov     rbp, rsp
    call    setup
    mov     dword [surv + SURVIVAL.health], 10
    mov     edi, 240
    call    steps
    cmp     dword [surv + SURVIVAL.health], 11
    jne     .fail
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret

test_damage_invulnerability:
    push    rbp
    mov     rbp, rsp
    call    setup
    mov     edi, 4
    mov     esi, CAUSE_ZOMBIE
    call    survival_damage
    cmp     eax, 1
    jne     .fail
    cmp     dword [surv + SURVIVAL.health], 16
    jne     .fail
    mov     edi, 4
    mov     esi, CAUSE_ZOMBIE
    call    survival_damage
    test    eax, eax
    jnz     .fail
    cmp     dword [surv + SURVIVAL.health], 16
    jne     .fail
    mov     edi, 30
    call    steps
    mov     edi, 4
    mov     esi, CAUSE_ZOMBIE
    call    survival_damage
    cmp     dword [surv + SURVIVAL.health], 12
    jne     .fail
    mov     dword [game_mode], MODE_CREATIVE
    mov     dword [surv + SURVIVAL.invuln], 0
    mov     edi, 4
    mov     esi, CAUSE_ZOMBIE
    call    survival_damage
    test    eax, eax
    jnz     .fail
    cmp     dword [surv + SURVIVAL.health], 12
    jne     .fail
    mov     dword [game_mode], MODE_SURVIVAL
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     dword [game_mode], MODE_SURVIVAL
    mov     eax, 1
    pop     rbp
    ret

test_starvation_floor:
    push    rbp
    mov     rbp, rsp
    call    setup
    mov     dword [surv + SURVIVAL.food], 0
    mov     dword [surv + SURVIVAL.saturation], 0
    mov     dword [surv + SURVIVAL.health], 3
    mov     edi, 1200
    call    steps
    cmp     dword [surv + SURVIVAL.health], 1
    jne     .fail
    call    setup                       ; max 30: a tick is round(30/20) = 2 and must not cross the floor
    mov     dword [surv_max_health], 30
    mov     dword [surv + SURVIVAL.food], 0
    mov     dword [surv + SURVIVAL.saturation], 0
    mov     dword [surv + SURVIVAL.health], 2
    mov     edi, 1200
    call    steps
    cmp     dword [surv + SURVIVAL.health], 2
    jne     .fail
    cmp     dword [surv + SURVIVAL.dead], 0
    jne     .fail
    mov     dword [surv + SURVIVAL.health], 3
    mov     edi, 1200
    call    steps
    cmp     dword [surv + SURVIVAL.health], 1
    jne     .fail
    cmp     dword [surv + SURVIVAL.dead], 0
    jne     .fail
    mov     dword [surv_max_health], 20
    call    setup
    mov     dword [settings + SETTINGS.difficulty], DIFF_HARD
    mov     dword [surv + SURVIVAL.food], 0
    mov     dword [surv + SURVIVAL.saturation], 0
    mov     dword [surv + SURVIVAL.health], 2
    mov     edi, 480
    call    steps
    cmp     dword [surv + SURVIVAL.health], 0
    jne     .fail
    cmp     dword [surv + SURVIVAL.dead], 1
    jne     .fail
    cmp     dword [surv + SURVIVAL.death_cause], CAUSE_STARVE
    jne     .fail
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     dword [surv_max_health], 20
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    mov     eax, 1
    pop     rbp
    ret

; BRIGHT time, constant: fail unless sky_brightness(time) is within 1e-4 of it
%macro BRIGHT 2
    mov     edi, %1
    call    sky_brightness
    movss   [rsp], xmm0
    FNEAR   [rsp], %2
%endmacro

test_sky_day_cycle:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 16
    BRIGHT  0, k_1_0
    BRIGHT  36000, k_0_625
    BRIGHT  54000, k_0_25
    BRIGHT  70200, k_0_625
    BRIGHT  72000, k_1_0
    mov     edi, 54000
    call    sky_is_night
    cmp     eax, 1
    jne     .fail
    mov     edi, 6000
    call    sky_is_night
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    leave
    ret
.fail:
    mov     eax, 1
    leave
    ret

; set the four armor slots to ids %1..%1+3, count 1, dmg 0
%macro WEAR 1
    mov     dword [inv + INVENTORY.armor + 0], (%1) | (1 << 8)
    mov     dword [inv + INVENTORY.armor + 4], (%1 + 1) | (1 << 8)
    mov     dword [inv + INVENTORY.armor + 8], (%1 + 2) | (1 << 8)
    mov     dword [inv + INVENTORY.armor + 12], (%1 + 3) | (1 << 8)
%endmacro

; Full diamond (20 points) turns a 3-damage zombie hit into 1 and wears nothing (gear never wears);
; falls ignore armor; full iron (15 points) turns a 10-damage blast into 4.
test_armor_reduces_damage:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    setup
    call    inv_clear
    WEAR    DIAMOND_HELMET
    call    armor_points
    cmp     eax, 20
    jne     .fail
    mov     edi, 3
    mov     esi, CAUSE_ZOMBIE
    call    survival_damage
    cmp     dword [surv + SURVIVAL.health], 19
    jne     .fail
    xor     ebx, ebx
.wear:
    cmp     word [inv + INVENTORY.armor + rbx*4 + ITEMSTACK.dmg], 0     ; no piece took damage
    jne     .fail
    inc     ebx
    cmp     ebx, 4
    jb      .wear
    mov     dword [surv + SURVIVAL.invuln], 0
    mov     edi, 5
    mov     esi, CAUSE_FALL
    call    survival_damage
    cmp     dword [surv + SURVIVAL.health], 14
    jne     .fail
    WEAR    IRON_HELMET
    call    armor_points
    cmp     eax, 15
    jne     .fail
    mov     dword [surv + SURVIVAL.invuln], 0
    mov     edi, 10
    mov     esi, CAUSE_EXPLOSION
    call    survival_damage
    cmp     dword [surv + SURVIVAL.health], 10
    jne     .fail
    call    inv_clear
    xor     eax, eax
    jmp     .ret
.fail:
    call    inv_clear
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret
