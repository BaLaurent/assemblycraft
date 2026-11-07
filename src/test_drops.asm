; test_drops.asm - item entities: falling, landing, pickup, full inventory.
%include "common.inc"
default rel

global test_drops_fall_and_pickup

extern drops, drops_clear, drops_spawn, drops_step
extern player, body_init, rng_seed, world_clear, world_set
extern inv, inv_clear, survival_reset

section .rodata
align 4
k_half_w: dd 0.3
k_height: dd 1.8
k_speed:  dd 4.317
k_far:    dd 30.5
k_floor:  dd 11.0
k_x:      dd 5.5
k_y:      dd 12.0

section .text

; run(edi n): n drops_step calls
run:
    push    rbx
    mov     ebx, edi
.l:
    call    drops_step
    dec     ebx
    jnz     .l
    pop     rbx
    ret

test_drops_fall_and_pickup:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    xor     r12d, r12d                  ; STONE floor at y = 10, x and z 0..31
.fz:
    xor     ebx, ebx
.fx:
    mov     edi, ebx
    mov     esi, 10
    mov     edx, r12d
    mov     ecx, STONE
    call    world_set
    inc     ebx
    cmp     ebx, 32
    jb      .fx
    inc     r12d
    cmp     r12d, 32
    jb      .fz
    mov     edi, 5
    call    rng_seed
    call    drops_clear
    call    inv_clear
    call    survival_reset
    lea     rdi, [player]
    movss   xmm0, [k_half_w]
    movss   xmm1, [k_height]
    movss   xmm2, [k_speed]
    call    body_init
    mov     eax, [k_far]                ; player far away: nothing is picked up
    mov     [player + BODY.x], eax
    mov     [player + BODY.z], eax
    mov     eax, [k_floor]
    mov     [player + BODY.y], eax

    ; a dirt stack pops out above the floor and settles on it
    mov     edi, DIRT
    mov     esi, 3
    xor     edx, edx
    movss   xmm0, [k_x]
    movss   xmm1, [k_y]
    movss   xmm2, [k_x]
    call    drops_spawn
    test    eax, eax
    jnz     .fail
    mov     edi, 120
    call    run
    cmp     byte [drops + DROP.id], DIRT
    jne     .fail
    movss   xmm0, [drops + DROP.y]
    ucomiss xmm0, [k_floor]
    jne     .fail
    jp      .fail

    ; walking onto it picks the whole stack up
    mov     eax, [drops + DROP.x]
    mov     [player + BODY.x], eax
    mov     eax, [drops + DROP.z]
    mov     [player + BODY.z], eax
    mov     edi, 1
    call    run
    cmp     byte [drops + DROP.id], 0
    jne     .fail
    cmp     byte [inv + INVENTORY.slots + ITEMSTACK.id], DIRT
    jne     .fail
    cmp     byte [inv + INVENTORY.slots + ITEMSTACK.count], 3
    jne     .fail

    ; with no room left the drop stays on the ground
    xor     ecx, ecx
.full:
    mov     byte [inv + INVENTORY.slots + rcx*4 + ITEMSTACK.id], STONE
    mov     byte [inv + INVENTORY.slots + rcx*4 + ITEMSTACK.count], 64
    inc     ecx
    cmp     ecx, INV_SLOTS
    jb      .full
    mov     edi, COBBLE
    mov     esi, 1
    xor     edx, edx
    movss   xmm0, [player + BODY.x]
    movss   xmm1, [k_floor]
    movss   xmm2, [player + BODY.z]
    call    drops_spawn
    mov     edi, 60
    call    run
    cmp     byte [drops + DROP.id], COBBLE
    jne     .fail
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    drops_clear
    call    inv_clear
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret
