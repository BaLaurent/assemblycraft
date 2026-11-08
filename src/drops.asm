; drops.asm - items lying in the world: they pop out of broken blocks and dead pigs, fall,
; slide to a stop, spin and bob, and are picked up when the player walks over them.
; Drops are not saved with the world.
%include "common.inc"
%include "gl.inc"
default rel

global drops, drops_clear, drops_spawn, drops_toss, drops_step, drops_render

extern player, player_eye, player_forward, world_is_solid, rng_next, sincos_deg
extern inv_add_dmg, audio_play, surv, item_max_stack, item_model_draw, item_model_is_block
extern light_bind_at, light_bind_index

%define DESPAWN_STEPS 18000             ; 5 minutes
%define SPAWN_DELAY   10                ; steps before a fresh drop can be picked up
%define TOSS_DELAY    40

section .rodata
align 4
c_dt:        dd 0.016666668
c_gravity:   dd 0.33333334              ; 20 blocks/s^2 per step
c_vy_min:    dd -30.0
c_pop_vy:    dd 3.0
c_scatter:   dd 0.0078125               ; (rng & 255) / 128 - 1 -> +-1 block/s
c_one:       dd 1.0
c_ground_fr: dd 0.6
c_air_fr:    dd 0.98
c_top:       dd 0.25                    ; head room checked when rising
c_step_y:    dd 0.1
c_out_y:     dd -8.0
c_pick_r2:   dd 1.0                     ; horizontal pickup radius^2
c_pick_lo:   dd -0.6                    ; drop y - player y window
c_pick_hi:   dd 1.9
c_pop_vol:   dd 0.35
c_toss_spd:  dd 5.0
c_toss_up:   dd 1.5
c_toss_dy:   dd -0.3
c_lift:      dd 0.2                     ; model centre above the drop's bottom
c_bob:       dd 0.08
c_bob_rate:  dd 3.0                     ; degrees per step
c_spin_rate: dd 2.0
c_block_sc:  dd 0.25
c_item_sc:   dd 0.45
c_stack_off: dd 0.25                    ; second copy of a stack, in model units
c_light_dy:  dd 0.25                    ; the light is sampled this far above the drop's bottom

section .bss
alignb 16
drops:       resb MAX_DROPS * DROP_size
drops_end:

section .text

; drops_clear()
drops_clear:
    lea     rdi, [drops]
    mov     ecx, MAX_DROPS * DROP_size
    xor     eax, eax
    rep     stosb
    ret

; scatter() -> xmm0 random speed in [-1, 1)
scatter:
    sub     rsp, 8
    call    rng_next
    and     eax, 255
    cvtsi2ss xmm0, eax
    mulss   xmm0, [c_scatter]
    subss   xmm0, [c_one]
    add     rsp, 8
    ret

; drops_spawn(edi id, esi count, edx dmg, xmm0 x, xmm1 y, xmm2 z) -> eax index or -1.
; Pops upward with a small random horizontal speed. When every slot is used the oldest
; drop is replaced.
drops_spawn:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 16
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 8], xmm2
    mov     eax, -1
    cmp     edi, NUM_ITEMS
    jae     .ret
    test    esi, esi
    jz      .ret
    cmp     byte [item_max_stack + rdi], 0
    je      .ret
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edx
    lea     rbx, [drops]                ; first free slot, else the oldest
    lea     rcx, [drops]
    mov     edx, -1                     ; oldest age seen
.find:
    cmp     byte [rcx + DROP.id], 0
    je      .free
    mov     eax, [rcx + DROP.age]
    cmp     eax, edx
    jle     .next
    mov     edx, eax
    mov     rbx, rcx
.next:
    add     rcx, DROP_size
    lea     rax, [drops_end]
    cmp     rcx, rax
    jb      .find
    jmp     .fill
.free:
    mov     rbx, rcx
.fill:
    mov     eax, [rsp]
    mov     [rbx + DROP.x], eax
    mov     eax, [rsp + 4]
    mov     [rbx + DROP.y], eax
    mov     eax, [rsp + 8]
    mov     [rbx + DROP.z], eax
    call    scatter
    movss   [rbx + DROP.vx], xmm0
    call    scatter
    movss   [rbx + DROP.vz], xmm0
    mov     eax, [c_pop_vy]
    mov     [rbx + DROP.vy], eax
    mov     dword [rbx + DROP.age], 0
    mov     dword [rbx + DROP.delay], SPAWN_DELAY
    mov     [rbx + DROP.id], r12b
    mov     ecx, 255
    cmp     r13d, ecx
    cmova   r13d, ecx
    mov     [rbx + DROP.count], r13b
    mov     [rbx + DROP.dmg], r14w
    mov     rax, rbx
    lea     rcx, [drops]
    sub     rax, rcx
    xor     edx, edx
    mov     ecx, DROP_size
    div     ecx
.ret:
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; drops_toss(edi id, esi count, edx dmg): thrown forward from just under the player's eyes
drops_toss:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 40                     ; [rsp] eye[3], [rsp+12] dir[3]
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     rdi, rsp
    call    player_eye
    lea     rdi, [rsp + 12]
    call    player_forward
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    addss   xmm1, [c_toss_dy]
    movss   xmm2, [rsp + 8]
    call    drops_spawn
    test    eax, eax
    js      .ret
    imul    eax, eax, DROP_size
    lea     rcx, [drops]
    add     rcx, rax
    movss   xmm0, [rsp + 12]
    mulss   xmm0, [c_toss_spd]
    movss   [rcx + DROP.vx], xmm0
    movss   xmm0, [rsp + 16]
    mulss   xmm0, [c_toss_spd]
    addss   xmm0, [c_toss_up]
    movss   [rcx + DROP.vy], xmm0
    movss   xmm0, [rsp + 20]
    mulss   xmm0, [c_toss_spd]
    movss   [rcx + DROP.vz], xmm0
    mov     dword [rcx + DROP.delay], TOSS_DELAY
.ret:
    add     rsp, 40
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; solid_at(xmm0 x, xmm1 y, xmm2 z) -> eax world_is_solid of the cell holding the point
solid_at:
    sub     rsp, 8
    roundss xmm0, xmm0, 9
    cvttss2si edi, xmm0
    roundss xmm1, xmm1, 9
    cvttss2si esi, xmm1
    roundss xmm2, xmm2, 9
    cvttss2si edx, xmm2
    call    world_is_solid
    add     rsp, 8
    ret

; drops_step(): one fixed step for every drop: physics, pickup, despawn
drops_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 24                     ; [rsp] new coordinate, [rsp+4] ground flag
    lea     rbx, [drops]
.loop:
    cmp     byte [rbx + DROP.id], 0
    je      .next
    inc     dword [rbx + DROP.age]
    cmp     dword [rbx + DROP.age], DESPAWN_STEPS
    jae     .remove
    cmp     dword [rbx + DROP.delay], 0
    je      .delay_ok
    dec     dword [rbx + DROP.delay]
.delay_ok:
    ; pushed up out of a block that was placed on it
    movss   xmm0, [rbx + DROP.x]
    movss   xmm1, [rbx + DROP.y]
    movss   xmm2, [rbx + DROP.z]
    call    solid_at
    test    eax, eax
    jz      .fall
    movss   xmm0, [rbx + DROP.y]
    roundss xmm0, xmm0, 9
    addss   xmm0, [c_one]
    movss   [rbx + DROP.y], xmm0
    mov     dword [rbx + DROP.vy], 0
.fall:
    ; vertical: gravity, land on the cell below, stop under a ceiling
    mov     dword [rsp + 4], 0
    movss   xmm0, [rbx + DROP.vy]
    subss   xmm0, [c_gravity]
    maxss   xmm0, [c_vy_min]
    movss   [rbx + DROP.vy], xmm0
    mulss   xmm0, [c_dt]
    addss   xmm0, [rbx + DROP.y]
    movss   [rsp], xmm0                 ; new y
    xorps   xmm3, xmm3
    comiss  xmm3, [rbx + DROP.vy]
    jbe     .rising
    movss   xmm0, [rbx + DROP.x]
    movss   xmm1, [rsp]
    movss   xmm2, [rbx + DROP.z]
    call    solid_at
    test    eax, eax
    jz      .move_y
    movss   xmm0, [rsp]                 ; landed on top of that cell
    roundss xmm0, xmm0, 9
    addss   xmm0, [c_one]
    movss   [rbx + DROP.y], xmm0
    mov     dword [rbx + DROP.vy], 0
    mov     dword [rsp + 4], 1
    jmp     .horizontal
.rising:
    movss   xmm0, [rbx + DROP.x]
    movss   xmm1, [rsp]
    addss   xmm1, [c_top]
    movss   xmm2, [rbx + DROP.z]
    call    solid_at
    test    eax, eax
    jz      .move_y
    mov     dword [rbx + DROP.vy], 0
    jmp     .horizontal
.move_y:
    mov     eax, [rsp]
    mov     [rbx + DROP.y], eax
.horizontal:
%macro MOVE_H 3                         ; position field, velocity field, 0 = x / 1 = z
    movss   xmm0, [rbx + %2]
    mulss   xmm0, [c_dt]
    addss   xmm0, [rbx + %1]
    movss   [rsp], xmm0
    movss   xmm0, [rbx + DROP.x]
    movss   xmm1, [rbx + DROP.y]
    addss   xmm1, [c_step_y]
    movss   xmm2, [rbx + DROP.z]
    movss   xmm3, [rsp]
%if %3 == 0
    movss   xmm0, xmm3
%else
    movss   xmm2, xmm3
%endif
    call    solid_at
    test    eax, eax
    jz      %%free
    mov     dword [rbx + %2], 0
    jmp     %%done
%%free:
    mov     eax, [rsp]
    mov     [rbx + %1], eax
%%done:
%endmacro
    MOVE_H  DROP.x, DROP.vx, 0
    MOVE_H  DROP.z, DROP.vz, 1
    movss   xmm1, [c_air_fr]
    cmp     dword [rsp + 4], 0
    je      .friction
    movss   xmm1, [c_ground_fr]
.friction:
    movss   xmm0, [rbx + DROP.vx]
    mulss   xmm0, xmm1
    movss   [rbx + DROP.vx], xmm0
    movss   xmm0, [rbx + DROP.vz]
    mulss   xmm0, xmm1
    movss   [rbx + DROP.vz], xmm0
    movss   xmm0, [rbx + DROP.y]
    comiss  xmm0, [c_out_y]
    jb      .remove                     ; fell out of the world

    ; pickup: inside the player's reach box once the delay has run out
    cmp     dword [rbx + DROP.delay], 0
    jne     .next
    cmp     dword [surv + SURVIVAL.dead], 0
    jne     .next
    movss   xmm0, [rbx + DROP.x]
    subss   xmm0, [player + BODY.x]
    mulss   xmm0, xmm0
    movss   xmm1, [rbx + DROP.z]
    subss   xmm1, [player + BODY.z]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [c_pick_r2]
    jae     .next
    movss   xmm0, [rbx + DROP.y]
    subss   xmm0, [player + BODY.y]
    comiss  xmm0, [c_pick_lo]
    jb      .next
    comiss  xmm0, [c_pick_hi]
    ja      .next
    movzx   edi, byte [rbx + DROP.id]
    movzx   esi, byte [rbx + DROP.count]
    movzx   edx, word [rbx + DROP.dmg]
    call    inv_add_dmg
    cmp     al, [rbx + DROP.count]
    je      .next                       ; inventory full: it stays on the ground
    mov     [rbx + DROP.count], al
    mov     [rsp + 8], eax
    mov     edi, SND_POP
    movss   xmm0, [c_pop_vol]
    call    audio_play
    cmp     dword [rsp + 8], 0
    jne     .next
.remove:
    mov     byte [rbx + DROP.id], 0
.next:
    add     rbx, DROP_size
    lea     rax, [drops_end]
    cmp     rbx, rax
    jb      .loop
    add     rsp, 24
    pop     rbx
    pop     rbp
    ret

; drops_render(): every drop spinning and bobbing above its spot. Called inside the world
; pass (atlas bound, alpha test on, light map active): each drop binds the light of the cell it
; floats in on unit 1 (sky-full again afterwards), so the model light is 1.
drops_render:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    lea     rbx, [drops]
.loop:
    movzx   r12d, byte [rbx + DROP.id]
    test    r12d, r12d
    jz      .next
    movss   xmm0, [rbx + DROP.x]
    movss   xmm1, [rbx + DROP.y]
    addss   xmm1, [c_light_dy]
    movss   xmm2, [rbx + DROP.z]
    call    light_bind_at
    call    glPushMatrix
    cvtsi2ss xmm0, dword [rbx + DROP.age]
    mulss   xmm0, [c_bob_rate]
    call    sincos_deg
    mulss   xmm0, [c_bob]
    addss   xmm0, [c_lift]
    addss   xmm0, [rbx + DROP.y]
    movaps  xmm1, xmm0
    movss   xmm0, [rbx + DROP.x]
    movss   xmm2, [rbx + DROP.z]
    call    glTranslatef
    cvtsi2ss xmm0, dword [rbx + DROP.age]
    mulss   xmm0, [c_spin_rate]
    xorps   xmm1, xmm1
    movss   xmm2, [c_one]
    xorps   xmm3, xmm3
    call    glRotatef
    mov     edi, r12d
    call    item_model_is_block
    movss   xmm0, [c_item_sc]
    test    eax, eax
    jz      .scale
    movss   xmm0, [c_block_sc]
.scale:
    movss   xmm1, xmm0
    movss   xmm2, xmm0
    call    glScalef
    mov     edi, r12d
    movss   xmm0, [c_one]
    call    item_model_draw
    cmp     byte [rbx + DROP.count], 1
    jbe     .pop
    ; stacks show a second copy, shifted diagonally
    movss   xmm0, [c_stack_off]
    movss   xmm1, xmm0
    movss   xmm2, xmm0
    call    glTranslatef
    mov     edi, r12d
    movss   xmm0, [c_one]
    call    item_model_draw
.pop:
    call    glPopMatrix
.next:
    add     rbx, DROP_size
    lea     rax, [drops_end]
    cmp     rbx, rax
    jb      .loop
    mov     edi, LIGHT_SKY_FULL
    call    light_bind_index
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret
