; player.asm - body physics (player and mobs), the player body, view vectors.
%include "common.inc"
default rel

global player, body_init, body_step, body_intersects_block
global player_spawn, player_look, player_eye, player_forward

extern sincos_deg, world_is_solid, world_header

section .rodata
align 4
c_dt:        dd 0.016666668             ; one fixed step, seconds
c_gravity:   dd 32.0
c_jump:      dd 9.0
c_fall_min:  dd -50.0                   ; terminal fall velocity (lower bound of vy)
c_sprint:    dd 5.612
c_fly_h:     dd 10.89
c_fly_v:     dd 7.5
c_eps:       dd 0.001
c_eye:       dd 1.62
c_one:       dd 1.0
c_half:      dd 0.5
c_sens:      dd 0.15                    ; degrees per mouse pixel
c_full:      dd 360.0
c_pitch_max: dd 89.9
c_pitch_min: dd -89.9
c_kb_decay:  dd 0.8
c_kb_min:    dd 0.05
c_abs_mask:  dd 0x7FFFFFFF             ; loaded with movss (andps needs a register here)
c_p_half_w:  dd 0.3
c_p_height:  dd 1.8
c_p_speed:   dd 4.317

section .bss
alignb 16
player: resb BODY_size

section .text

; body_init(rdi body, xmm0 half_w, xmm1 height, xmm2 speed): zero, then set the box/speed
body_init:
    mov     rdx, rdi
    mov     ecx, BODY_size
    xor     eax, eax
    rep     stosb
    movss   [rdx + BODY.half_w], xmm0
    movss   [rdx + BODY.height], xmm1
    movss   [rdx + BODY.speed], xmm2
    ret

; player_spawn(): standard player box at the header spawn cell, looking slightly down.
player_spawn:
    push    rbp
    mov     rbp, rsp
    lea     rdi, [player]
    movss   xmm0, [c_p_half_w]
    movss   xmm1, [c_p_height]
    movss   xmm2, [c_p_speed]
    call    body_init
    lea     rdx, [player]
    movss   xmm1, [c_half]
    cvtsi2ss xmm0, dword [world_header + WORLDHDR.spawn_x]
    addss   xmm0, xmm1
    movss   [rdx + BODY.x], xmm0
    cvtsi2ss xmm0, dword [world_header + WORLDHDR.spawn_y]
    movss   [rdx + BODY.y], xmm0
    cvtsi2ss xmm0, dword [world_header + WORLDHDR.spawn_z]
    addss   xmm0, xmm1
    movss   [rdx + BODY.z], xmm0
    mov     dword [rdx + BODY.pitch], __float32__(30.0)
    pop     rbp
    ret

; player_look(xmm0 dx, xmm1 dy): mouse pixels -> yaw wrapped into [0, 360), pitch clamped.
player_look:
    lea     rax, [player]
    movss   xmm2, [c_sens]
    mulss   xmm0, xmm2
    mulss   xmm1, xmm2
    addss   xmm0, [rax + BODY.yaw]
    movss   xmm3, [c_full]
    xorps   xmm4, xmm4
.wrap_up:                               ; while (yaw < 0) yaw += 360
    ucomiss xmm4, xmm0
    jbe     .wrap_down
    addss   xmm0, xmm3
    jmp     .wrap_up
.wrap_down:                             ; while (yaw >= 360) yaw -= 360
    ucomiss xmm0, xmm3
    jb      .yaw_ok
    subss   xmm0, xmm3
    jmp     .wrap_down
.yaw_ok:
    movss   [rax + BODY.yaw], xmm0
    addss   xmm1, [rax + BODY.pitch]
    maxss   xmm1, [c_pitch_min]
    minss   xmm1, [c_pitch_max]
    movss   [rax + BODY.pitch], xmm1
    ret

; player_eye(rdi float out[3]): eye position = feet + 1.62 up
player_eye:
    lea     rax, [player]
    movss   xmm0, [rax + BODY.x]
    movss   [rdi], xmm0
    movss   xmm0, [rax + BODY.y]
    addss   xmm0, [c_eye]
    movss   [rdi + 4], xmm0
    movss   xmm0, [rax + BODY.z]
    movss   [rdi + 8], xmm0
    ret

; player_forward(rdi float out[3]): unit view direction
;   (sin yaw * cos pitch, -sin pitch, -cos yaw * cos pitch)
player_forward:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 24                     ; [rsp] sin yaw, [rsp+4] cos yaw
    mov     rbx, rdi
    movss   xmm0, [player + BODY.yaw]
    call    sincos_deg
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   xmm0, [player + BODY.pitch]
    call    sincos_deg                  ; xmm0 = sin pitch, xmm1 = cos pitch
    movss   xmm2, [rsp]
    mulss   xmm2, xmm1
    movss   [rbx], xmm2                 ; x = sin yaw * cos pitch
    xorps   xmm3, xmm3
    subss   xmm3, xmm0
    movss   [rbx + 4], xmm3             ; y = -sin pitch
    movss   xmm2, [rsp + 4]
    mulss   xmm2, xmm1
    xorps   xmm3, xmm3
    subss   xmm3, xmm2
    movss   [rbx + 8], xmm3             ; z = -cos yaw * cos pitch
    add     rsp, 24
    pop     rbx
    pop     rbp
    ret

; box_lo(rdi body, ecx axis) -> xmm1 offset of the box min on that axis (0 for y)
; box_hi(rdi body, ecx axis) -> xmm2 offset of the box max on that axis
%macro BOX_LO 3                         ; dst xmm, body reg, axis reg (32-bit)
    xorps   %1, %1
    cmp     %3, 1
    je      %%y
    subss   %1, [%2 + BODY.half_w]
%%y:
%endmacro
%macro BOX_HI 3
    movss   %1, [%2 + BODY.half_w]
    cmp     %3, 1
    jne     %%xz
    movss   %1, [%2 + BODY.height]
%%xz:
%endmacro

; body_intersects_block(rdi body, esi x, edx y, ecx z) -> eax 0/1
; Strict overlap of the block [b, b+1]^3 with the body box.
body_intersects_block:
    sub     rsp, 16
    mov     [rsp], esi
    mov     [rsp + 4], edx
    mov     [rsp + 8], ecx
    xor     ecx, ecx
.axis:
    cvtsi2ss xmm0, dword [rsp + rcx*4]  ; b
    movss   xmm3, [rdi + rcx*4]         ; position
    BOX_LO  xmm1, rdi, ecx
    BOX_HI  xmm2, rdi, ecx
    addss   xmm1, xmm3                  ; box min
    addss   xmm2, xmm3                  ; box max
    ucomiss xmm2, xmm0
    jbe     .no                         ; max <= b
    addss   xmm0, [c_one]
    ucomiss xmm0, xmm1
    jbe     .no                         ; b + 1 <= min
    inc     ecx
    cmp     ecx, 3
    jb      .axis
    mov     eax, 1
    add     rsp, 16
    ret
.no:
    xor     eax, eax
    add     rsp, 16
    ret

; move_axis(rdi body, esi axis 0/1/2, xmm0 d): move the body by d along one axis and, if
; the box then overlaps a solid cell, snap it flush against that cell and zero the velocity
; there. Only the leading slab (the cell layer the box just entered) is tested for the axis
; moved, which is valid while |d| < 1 block per step.
; Frame: lo[3] @0, hi[3] @16 (cell ranges), direction @32 (1 = moving +, 0 = moving -).
move_axis:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40
    xorps   xmm1, xmm1
    ucomiss xmm0, xmm1
    je      .done                       ; d == 0 (or NaN): nothing to do
    mov     rbx, rdi
    mov     r12d, esi
    seta    al
    movzx   eax, al
    mov     [rsp + 32], eax
    movss   xmm1, [rbx + r12*4]         ; pos[axis] += d
    addss   xmm1, xmm0
    movss   [rbx + r12*4], xmm1
    xor     ecx, ecx
.bounds:                                ; cells overlapped by the box on each axis
    movss   xmm3, [rbx + rcx*4]
    BOX_LO  xmm1, rbx, ecx
    BOX_HI  xmm2, rbx, ecx
    addss   xmm1, xmm3
    addss   xmm2, xmm3
    roundss xmm1, xmm1, 9               ; floor(min)
    cvttss2si eax, xmm1
    mov     [rsp + rcx*4], eax
    roundss xmm2, xmm2, 10              ; ceil(max) - 1
    cvttss2si eax, xmm2
    dec     eax
    mov     [rsp + 16 + rcx*4], eax
    inc     ecx
    cmp     ecx, 3
    jb      .bounds
    cmp     dword [rsp + 32], 0         ; collapse the moving axis to its leading slab
    je      .lead_low
    mov     eax, [rsp + 16 + r12*4]
    mov     [rsp + r12*4], eax
    jmp     .scan
.lead_low:
    mov     eax, [rsp + r12*4]
    mov     [rsp + 16 + r12*4], eax
.scan:
    mov     r15d, [rsp + 8]
.scan_z:
    mov     r14d, [rsp + 4]
.scan_y:
    mov     r13d, [rsp]
.scan_x:
    mov     edi, r13d
    mov     esi, r14d
    mov     edx, r15d
    call    world_is_solid
    test    eax, eax
    jnz     .hit
    inc     r13d
    cmp     r13d, [rsp + 16]
    jle     .scan_x
    inc     r14d
    cmp     r14d, [rsp + 20]
    jle     .scan_y
    inc     r15d
    cmp     r15d, [rsp + 24]
    jle     .scan_z
    jmp     .done
.hit:
    cmp     r12d, 1
    je      .not_blocked
    mov     dword [rbx + BODY.blocked], 1
.not_blocked:
    mov     eax, [rsp + r12*4]          ; i = leading slab index (lo == hi on this axis)
    cvtsi2ss xmm1, eax
    cmp     dword [rsp + 32], 0
    je      .hit_low
    BOX_HI  xmm2, rbx, r12d
    subss   xmm1, xmm2                  ; i - extent - eps
    subss   xmm1, [c_eps]
    jmp     .store
.hit_low:
    addss   xmm1, [c_one]
    BOX_LO  xmm2, rbx, r12d
    subss   xmm1, xmm2                  ; i + 1 + extent (+ eps); feet land exactly on i + 1
    cmp     r12d, 1
    jne     .low_side
    mov     dword [rbx + BODY.on_ground], 1
    jmp     .store
.low_side:
    addss   xmm1, [c_eps]
.store:
    movss   [rbx + r12*4], xmm1
    mov     dword [rbx + BODY.vx + r12*4], 0
.done:
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; decay_kb(rdi float*): kb *= 0.8; zero once |kb| < 0.05
decay_kb:
    movss   xmm0, [rdi]
    mulss   xmm0, [c_kb_decay]
    movss   xmm1, [c_abs_mask]
    andps   xmm1, xmm0                  ; |kb|
    comiss  xmm1, [c_kb_min]
    jae     .store
    xorps   xmm0, xmm0
.store:
    movss   [rdi], xmm0
    ret

; body_step(rdi body, rsi INPUT*) -> xmm0 fall distance that ended on this step (0 if none).
; One fixed 1/60 s step. Sets velocity from input plus knockback, then moves Y, X, Z in that
; order so that resting on the ground leaves y exactly integral.
body_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16                     ; [rsp] y0
    mov     rbx, rdi
    mov     r12, rsi
    movss   xmm0, [rbx + BODY.y]
    movss   [rsp], xmm0
    mov     dword [rbx + BODY.blocked], 0
    movss   xmm0, [rbx + BODY.yaw]
    call    sincos_deg                  ; xmm0 = sin yaw, xmm1 = cos yaw
    ; wish direction m = fwd * (sin, -cos) + strafe * (cos, sin) on (x, z)
    cvtsi2ss xmm2, dword [r12 + INPUT.fwd]
    cvtsi2ss xmm3, dword [r12 + INPUT.strafe]
    movaps  xmm4, xmm2
    mulss   xmm4, xmm0                  ; fwd * sin
    movaps  xmm5, xmm3
    mulss   xmm5, xmm1                  ; strafe * cos
    addss   xmm4, xmm5                  ; mx
    mulss   xmm3, xmm0                  ; strafe * sin
    mulss   xmm2, xmm1                  ; fwd * cos
    subss   xmm3, xmm2                  ; mz
    movaps  xmm5, xmm4
    mulss   xmm5, xmm5
    movaps  xmm6, xmm3
    mulss   xmm6, xmm6
    addss   xmm5, xmm6                  ; |m|^2
    xorps   xmm6, xmm6
    ucomiss xmm5, xmm6
    jbe     .speed                      ; no input: m stays zero
    sqrtss  xmm5, xmm5
    divss   xmm4, xmm5
    divss   xmm3, xmm5
.speed:
    movss   xmm5, [c_fly_h]
    cmp     dword [rbx + BODY.flying], 0
    jne     .have_speed
    movss   xmm5, [rbx + BODY.speed]
    cmp     dword [r12 + INPUT.sprint], 0
    je      .have_speed
    movss   xmm5, [c_sprint]
.have_speed:
    mulss   xmm4, xmm5
    mulss   xmm3, xmm5
    addss   xmm4, [rbx + BODY.kbx]
    addss   xmm3, [rbx + BODY.kbz]
    movss   [rbx + BODY.vx], xmm4
    movss   [rbx + BODY.vz], xmm3
    lea     rdi, [rbx + BODY.kbx]
    call    decay_kb
    lea     rdi, [rbx + BODY.kbz]
    call    decay_kb
    cmp     dword [rbx + BODY.flying], 0
    jne     .fly_vy
    movss   xmm0, [rbx + BODY.vy]
    cmp     dword [r12 + INPUT.jump], 0
    je      .fall
    cmp     dword [rbx + BODY.on_ground], 0
    je      .fall
    movss   xmm0, [c_jump]
    jmp     .vy_set
.fall:
    movss   xmm1, [c_gravity]
    mulss   xmm1, [c_dt]
    subss   xmm0, xmm1                  ; vy -= 32 * dt
    maxss   xmm0, [c_fall_min]          ; vy >= -50
    jmp     .vy_set
.fly_vy:
    xorps   xmm0, xmm0
    cmp     dword [r12 + INPUT.jump], 0
    je      .no_up
    addss   xmm0, [c_fly_v]
.no_up:
    cmp     dword [r12 + INPUT.down], 0
    je      .vy_set
    subss   xmm0, [c_fly_v]
.vy_set:
    movss   [rbx + BODY.vy], xmm0
    mov     dword [rbx + BODY.on_ground], 0
    movss   xmm0, [rbx + BODY.vy]
    mulss   xmm0, [c_dt]
    mov     rdi, rbx
    mov     esi, 1
    call    move_axis
    movss   xmm0, [rbx + BODY.vx]
    mulss   xmm0, [c_dt]
    mov     rdi, rbx
    xor     esi, esi
    call    move_axis
    movss   xmm0, [rbx + BODY.vz]
    mulss   xmm0, [c_dt]
    mov     rdi, rbx
    mov     esi, 2
    call    move_axis
    ; fall tracking
    xorps   xmm0, xmm0
    cmp     dword [rbx + BODY.flying], 0
    jne     .fall_reset
    movss   xmm1, [rsp]                 ; y0 - y
    subss   xmm1, [rbx + BODY.y]
    cmp     dword [rbx + BODY.on_ground], 0
    je      .airborne
    maxss   xmm1, xmm0                  ; max(0, y0 - y)
    addss   xmm1, [rbx + BODY.fall]
    movss   [rbx + BODY.fall], xmm0
    movaps  xmm0, xmm1                  ; landed
    jmp     .ret
.airborne:
    comiss  xmm1, xmm0
    jbe     .ret                        ; not descending
    addss   xmm1, [rbx + BODY.fall]
    movss   [rbx + BODY.fall], xmm1
    jmp     .ret
.fall_reset:
    movss   [rbx + BODY.fall], xmm0
.ret:
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret
