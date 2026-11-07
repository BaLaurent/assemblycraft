; test_fire.asm - fire spreads through wood, ignites TNT, dies out on stone and burns the player.
%include "common.inc"
default rel

global test_fire_spreads_and_burns_wood, test_fire_ignites_tnt
global test_fire_dies_on_stone, test_fire_hurts_player

extern fires, fire_clear, fire_place, fire_step
extern primed, tnt_clear
extern mobs_clear
extern player, body_init, rng_seed, world_clear, world_set, world_get
extern game_mode, game_time, surv, survival_reset

section .rodata
align 4
k_half_w: dd 0.3
k_height: dd 1.8
k_speed:  dd 4.317
k_5_5:    dd 5.5
k_11:     dd 11.0

section .text

; setup(): the state every fire test starts from (after world_clear): no fires, mobs or primed
; TNT, Creative (so nobody is hurt unless a test says so), rng seed 1
setup:
    sub     rsp, 8
    call    fire_clear
    call    tnt_clear
    call    mobs_clear
    mov     dword [game_mode], MODE_CREATIVE
    mov     dword [game_time], NEW_WORLD_TIME
    mov     edi, 1
    call    rng_seed
    add     rsp, 8
    ret

; cleanup(): leave no fires or primed TNT behind
cleanup:
    sub     rsp, 8
    call    fire_clear
    call    tnt_clear
    call    world_clear
    add     rsp, 8
    ret

; steps(edi n): n fire steps
steps:
    push    rbx
    mov     ebx, edi
.l:
    call    fire_step
    dec     ebx
    jnz     .l
    pop     rbx
    ret

; fires_live() -> eax number of occupied fire slots
fires_live:
    lea     rcx, [fires]
    mov     edx, MAX_FIRES
    xor     eax, eax
.l:
    cmp     dword [rcx + FIREENT.x], -1
    je      .next
    inc     eax
.next:
    add     rcx, FIREENT_size
    dec     edx
    jnz     .l
    ret

; floor_fill(edi size, esi block): fills x, z in 0..size-1 at y = 10 with that block
floor_fill:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r13d, edi
    mov     r14d, esi
    xor     r12d, r12d                  ; z
.z:
    xor     ebx, ebx                    ; x
.x:
    mov     edi, ebx
    mov     esi, 10
    mov     edx, r12d
    mov     ecx, r14d
    call    world_set
    inc     ebx
    cmp     ebx, r13d
    jb      .x
    inc     r12d
    cmp     r12d, r13d
    jb      .z
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; count_fire_far(edi limit) -> eax FIRE blocks with x >= limit or z >= limit, in the region
; x, z < 64, y 8..15
count_fire_far:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r15d, edi
    xor     r14d, r14d                  ; count
    xor     r13d, r13d                  ; z
.z:
    xor     r12d, r12d                  ; x
.x:
    cmp     r12d, r15d
    jae     .scan
    cmp     r13d, r15d
    jb      .next
.scan:
    mov     ebx, 8                      ; y
.y:
    mov     edi, r12d
    mov     esi, ebx
    mov     edx, r13d
    call    world_get
    cmp     eax, FIRE
    jne     .ny
    inc     r14d
.ny:
    inc     ebx
    cmp     ebx, 15
    jbe     .y
.next:
    inc     r12d
    cmp     r12d, 64
    jb      .x
    inc     r13d
    cmp     r13d, 64
    jb      .z
    mov     eax, r14d
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; fire placed on a 5x5 planks floor burns it: after 1200 steps at least 10 planks are gone,
; no fire is left beyond x or z = 8, and the table is empty
test_fire_spreads_and_burns_wood:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    world_clear
    call    setup
    mov     edi, 5
    mov     esi, PLANKS
    call    floor_fill
    mov     edi, 2
    mov     esi, 11
    mov     edx, 2
    call    fire_place
    cmp     eax, 1
    jne     .fail
    mov     edi, 2
    mov     esi, 11
    mov     edx, 2
    call    world_get
    cmp     eax, FIRE
    jne     .fail
    mov     edi, 1200
    call    steps
    xor     r13d, r13d                  ; planks gone
    xor     r12d, r12d                  ; z
.cz:
    xor     ebx, ebx                    ; x
.cx:
    mov     edi, ebx
    mov     esi, 10
    mov     edx, r12d
    call    world_get
    cmp     eax, PLANKS
    je      .kept
    inc     r13d
.kept:
    inc     ebx
    cmp     ebx, 5
    jb      .cx
    inc     r12d
    cmp     r12d, 5
    jb      .cz
    cmp     r13d, 10
    jb      .fail
    mov     edi, 8
    call    count_fire_far
    test    eax, eax
    jnz     .fail
    call    fires_live
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     r12d, eax
    call    cleanup
    mov     eax, r12d
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; fire beside a TNT block primes it within 400 steps
test_fire_ignites_tnt:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    setup
    mov     edi, 5
    mov     esi, 11
    mov     edx, 5
    mov     ecx, TNT
    call    world_set
    mov     edi, 6
    mov     esi, 11
    mov     edx, 5
    call    fire_place
    cmp     eax, 1
    jne     .fail
    mov     edi, 400
    call    steps
    mov     eax, 1
    lea     rcx, [primed]
    mov     edx, MAX_PRIMED
.l:
    cmp     dword [rcx + PRIMED.fuse], 0
    jne     .found
    add     rcx, PRIMED_size
    dec     edx
    jnz     .l
    jmp     .fail
.found:
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     r12d, eax
    call    cleanup
    mov     eax, r12d
    pop     r12
    pop     rbx
    pop     rbp
    ret

; fire on a stone floor has nothing to burn: within 100 steps it is gone, nothing else caught
test_fire_dies_on_stone:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    setup
    mov     edi, 16
    mov     esi, STONE
    call    floor_fill
    mov     edi, 5
    mov     esi, 11
    mov     edx, 5
    call    fire_place
    cmp     eax, 1
    jne     .fail
    mov     edi, 100
    call    steps
    call    fires_live
    test    eax, eax
    jnz     .fail
    mov     edi, 0
    call    count_fire_far              ; every cell of the region: none left
    test    eax, eax
    jnz     .fail
    mov     edi, 5
    mov     esi, 11
    mov     edx, 5
    call    world_get
    test    eax, eax                    ; AIR again
    jnz     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     r12d, eax
    call    cleanup
    mov     eax, r12d
    pop     r12
    pop     rbx
    pop     rbp
    ret

; a Survival player standing in a fire is hurt within 40 steps
test_fire_hurts_player:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    setup
    mov     dword [game_mode], MODE_SURVIVAL
    call    survival_reset
    lea     rdi, [player]
    movss   xmm0, [k_half_w]
    movss   xmm1, [k_height]
    movss   xmm2, [k_speed]
    call    body_init
    movss   xmm0, [k_5_5]
    movss   [player + BODY.x], xmm0
    movss   [player + BODY.z], xmm0
    movss   xmm0, [k_11]
    movss   [player + BODY.y], xmm0
    mov     edi, 5
    mov     esi, 11
    mov     edx, 5
    call    fire_place
    cmp     eax, 1
    jne     .fail
    cmp     dword [surv + SURVIVAL.health], 20
    jne     .fail
    mov     edi, 40
    call    steps
    cmp     dword [surv + SURVIVAL.health], 20
    jge     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     r12d, eax
    call    survival_reset
    mov     dword [game_mode], MODE_CREATIVE
    call    cleanup
    mov     eax, r12d
    pop     r12
    pop     rbx
    pop     rbp
    ret
