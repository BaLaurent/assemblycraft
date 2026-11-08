; player.asm - body physics (player and mobs), the player body, view vectors, swimming.
%include "common.inc"
default rel

global player, body_init, body_step, body_intersects_block, move_axis
global player_look, player_eye, player_forward
global body_in_liquid, player_eye_in_water, player_shift

extern sincos_deg, world_get, shape_boxes, cell_boxes, block_shape

section .rodata
align 4
c_dt:        dd 0.016666668             ; one fixed step, seconds
c_gravity:   dd 32.0
c_jump:      dd 9.0
c_fall_min:  dd -50.0                   ; terminal fall velocity (lower bound of vy)
c_sprint:    dd 1.3                     ; sprint speed = walk speed * this
c_fly_h:     dd 10.89
c_fly_v:     dd 7.5
c_eps:       dd 0.001
c_eye:       dd 1.62
c_step_h:    dd 0.6                     ; step-up: how far a body is lifted over a low obstacle
c_step_gain: dd 0.0001                  ; a step-up must gain more ground than this
c_climb:     dd 2.4                     ; ladder: climbing speed
c_slide:     dd -2.4                    ; ladder: fastest slide down
c_inf:       dd 1.0e30                  ; "no clip found yet" for move_axis
c_sixteenth: dd 0.0625                  ; shape boxes are in 1/16 block
c_half:      dd 0.5
c_sens:      dd 0.15                    ; degrees per mouse pixel
c_full:      dd 360.0
c_pitch_max: dd 89.9
c_pitch_min: dd -89.9
c_kb_decay:  dd 0.8
c_kb_min:    dd 0.05
c_abs_mask:  dd 0x7FFFFFFF             ; loaded with movss (andps needs a register here)
c_swim_g:    dd 10.0                    ; swimming: vy falls by this per second ...
c_swim_min:  dd -2.5                    ; ... to at most this sink speed
c_swim_up:   dd 3.0                     ; jump held in water: rise speed
c_swim_out:  dd 7.0                     ; ... pushing against a ledge: enough to climb out
c_lava_slow: dd 0.3                     ; lava: horizontal speed factor (water: 0.5) ...
c_lava_up:   dd 1.5                     ; ... and the rise speed with jump held (water: 3.0)
c_probe_lo:  dd 0.4                     ; body_in_liquid probes the cells at feet + 0.4 and feet + 0.05
c_probe_hi:  dd 0.05

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

; player_shift(edi dx, esi dz): the world origin moved by (dx, dz) blocks, so the player's local
; position drops by them (the origin steps are multiples of 512: exact in a float)
player_shift:
    lea     rax, [player]
    cvtsi2ss xmm0, edi
    movss   xmm1, [rax + BODY.x]
    subss   xmm1, xmm0
    movss   [rax + BODY.x], xmm1
    cvtsi2ss xmm0, esi
    movss   xmm1, [rax + BODY.z]
    subss   xmm1, xmm0
    movss   [rax + BODY.z], xmm1
    ret

; body_in_liquid(rdi body) -> eax WATER, LAVA or 0: what the cell at (floor x, floor(y + 0.4), floor z) or the
; one at (floor x, floor(y + 0.05), floor z) holds, i.e. whether the feet or the lower body are under the
; surface of a liquid. When one probe finds WATER and the other LAVA the answer is WATER.
; r12d, r13d = x and z of the cell, r14d = the liquid found so far (0 or LAVA)
body_in_liquid:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    movss   xmm0, [rbx + BODY.x]
    roundss xmm0, xmm0, 9
    cvttss2si r12d, xmm0                ; cell x
    movss   xmm0, [rbx + BODY.z]
    roundss xmm0, xmm0, 9
    cvttss2si r13d, xmm0                ; cell z
    xor     r14d, r14d
    movss   xmm0, [rbx + BODY.y]
    addss   xmm0, [c_probe_hi]
    roundss xmm0, xmm0, 9
    cvttss2si esi, xmm0
    mov     edi, r12d
    mov     edx, r13d
    call    world_get
    cmp     eax, WATER
    je      .water
    cmp     eax, LAVA
    cmove   r14d, eax                   ; (eax is LAVA when it is equal)
    movss   xmm0, [rbx + BODY.y]
    addss   xmm0, [c_probe_lo]
    roundss xmm0, xmm0, 9
    cvttss2si esi, xmm0
    mov     edi, r12d
    mov     edx, r13d
    call    world_get
    cmp     eax, WATER
    je      .water
    cmp     eax, LAVA
    cmove   r14d, eax
    mov     eax, r14d
    jmp     .out
.water:
    mov     eax, WATER
.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; player_eye_in_water() -> eax 1 when the cell holding the player's eye (feet + 1.62) is WATER
player_eye_in_water:
    sub     rsp, 8
    movss   xmm0, [player + BODY.x]
    roundss xmm0, xmm0, 9
    cvttss2si edi, xmm0
    movss   xmm0, [player + BODY.y]
    addss   xmm0, [c_eye]
    roundss xmm0, xmm0, 9
    cvttss2si esi, xmm0
    movss   xmm0, [player + BODY.z]
    roundss xmm0, xmm0, 9
    cvttss2si edx, xmm0
    call    world_get
    xor     ecx, ecx
    cmp     eax, WATER
    sete    cl
    mov     eax, ecx
    add     rsp, 8
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

; body_intersects_block(rdi body, esi x, edx y, ecx z, r8d id) -> eax 0/1
; Strict overlap of the body box with the collision boxes block `id` would have standing in
; cell (x, y, z) (shapes.asm, BOXES_COLLIDE): none for air or a torch, the lower half for a
; slab, a panel for a door, ... Fences and panes also read their neighbours in the world.
; Frame: boxes byte[54] @0, cell x, y, z @56, @60, @64.
body_intersects_block:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 72
    mov     rbx, rdi
    mov     [rsp + 56], esi
    mov     [rsp + 60], edx
    mov     [rsp + 64], ecx
    mov     edi, r8d
    lea     r8, [rsp]                   ; esi, edx, ecx are still x, y, z
    mov     r9d, BOXES_COLLIDE
    call    shape_boxes
    mov     r12d, eax                   ; boxes left to test
    lea     r13, [rsp]                  ; the box under test
.box:
    test    r12d, r12d
    jz      .no
    xor     ecx, ecx
.axis:
    movzx   eax, byte [r13 + rcx]       ; box min, 1/16 block from the cell corner
    cvtsi2ss xmm0, eax
    mulss   xmm0, [c_sixteenth]
    cvtsi2ss xmm1, dword [rsp + 56 + rcx*4]
    addss   xmm0, xmm1                  ; box min
    movzx   eax, byte [r13 + rcx + 3]
    cvtsi2ss xmm2, eax
    mulss   xmm2, [c_sixteenth]
    addss   xmm2, xmm1                  ; box max
    movss   xmm3, [rbx + rcx*4]         ; position
    BOX_LO  xmm4, rbx, ecx
    BOX_HI  xmm5, rbx, ecx
    addss   xmm4, xmm3                  ; body min
    addss   xmm5, xmm3                  ; body max
    ucomiss xmm5, xmm0
    jbe     .next                       ; body max <= box min
    ucomiss xmm2, xmm4
    jbe     .next                       ; box max <= body min
    inc     ecx
    cmp     ecx, 3
    jb      .axis
    mov     eax, 1
    jmp     .ret
.next:
    add     r13, 6
    dec     r12d
    jmp     .box
.no:
    xor     eax, eax
.ret:
    add     rsp, 72
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; Frame of move_axis (rsp-relative)
%define MA_LO     0                     ; int cell range lo[3] the swept box touches
%define MA_HI     16                    ; int cell range hi[3]
%define MA_MIN    32                    ; float body min[3] before the move
%define MA_MAX    48                    ; float body max[3] before the move
%define MA_DIR    64                    ; int 1 = moving +, 0 = moving -
%define MA_TARGET 68                    ; float where the move wants the body to end
%define MA_BEST   72                    ; float tightest body position a box allows (+-1e30: none)
%define MA_OFFP   76                    ; float hi extent + eps: limit for d > 0 is box min - this
%define MA_OFFN   80                    ; float -lo extent (+ eps on x, z): limit for d < 0 is box max + this
%define MA_THR    84                    ; float a box face this far (or farther) ahead can stop the body
%define MA_D      88                    ; float d
%define MA_BOXES  96                    ; float boxes[9][6] of the cell under test
%define MA_FRAME  312

; move_axis(rdi body, esi axis 0/1/2, xmm0 d): move the body by d along one axis, stopped by
; the collision boxes (cell_boxes, BOXES_COLLIDE) of every cell the swept box touches. A box
; stops the body when it overlaps the box strictly on the two other axes and lies ahead on the
; moving axis (its near face no more than eps behind the body's far face); the body then
; ends flush against it, eps short on x and z, exactly on it on y. Touching counts as a
; clip: the velocity on that axis is zeroed, a downward y clip sets on_ground and an x or
; z clip sets blocked. Boxes the body already overlaps are ignored. Works for any |d|.
move_axis:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, MA_FRAME
    xorps   xmm1, xmm1
    ucomiss xmm0, xmm1
    je      .done                       ; d == 0 (or NaN): nothing to do
    mov     rbx, rdi
    mov     r12d, esi
    seta    al
    movzx   eax, al
    mov     [rsp + MA_DIR], eax
    movss   [rsp + MA_D], xmm0
    xor     ecx, ecx
.axis:                                  ; body extents, and the cells the swept box touches
    movss   xmm3, [rbx + rcx*4]
    BOX_LO  xmm1, rbx, ecx
    BOX_HI  xmm2, rbx, ecx
    addss   xmm1, xmm3
    addss   xmm2, xmm3
    movss   [rsp + MA_MIN + rcx*4], xmm1
    movss   [rsp + MA_MAX + rcx*4], xmm2
    subss   xmm1, [c_eps]
    addss   xmm2, [c_eps]
    cmp     ecx, r12d
    jne     .range
    movss   xmm0, [rsp + MA_D]          ; the moving axis also covers the way travelled
    cmp     dword [rsp + MA_DIR], 0
    je      .grow_lo
    addss   xmm2, xmm0
    jmp     .range
.grow_lo:
    addss   xmm1, xmm0
.range:
    roundss xmm1, xmm1, 9               ; floor
    cvttss2si eax, xmm1
    cmp     ecx, 1
    jne     .lo_store
    dec     eax                         ; a fence reaches 1.5 high: look one layer lower on y
.lo_store:
    mov     [rsp + MA_LO + rcx*4], eax
    roundss xmm2, xmm2, 9
    cvttss2si eax, xmm2
    mov     [rsp + MA_HI + rcx*4], eax
    inc     ecx
    cmp     ecx, 3
    jb      .axis
    movss   xmm0, [rbx + r12*4]
    addss   xmm0, [rsp + MA_D]
    movss   [rsp + MA_TARGET], xmm0
    BOX_HI  xmm1, rbx, r12d
    addss   xmm1, [c_eps]
    movss   [rsp + MA_OFFP], xmm1
    BOX_LO  xmm1, rbx, r12d
    xorps   xmm2, xmm2
    subss   xmm2, xmm1                  ; +half_w on x, z; 0 on y
    cmp     r12d, 1
    je      .offn
    addss   xmm2, [c_eps]
.offn:
    movss   [rsp + MA_OFFN], xmm2
    cmp     dword [rsp + MA_DIR], 0
    je      .thr_neg
    movss   xmm1, [rsp + MA_MAX + r12*4]
    subss   xmm1, [c_eps]               ; moving +: box min >= max - eps
    movss   xmm2, [c_inf]
    jmp     .thr_store
.thr_neg:
    movss   xmm1, [rsp + MA_MIN + r12*4]
    addss   xmm1, [c_eps]               ; moving -: box max <= min + eps
    xorps   xmm2, xmm2
    subss   xmm2, [c_inf]
.thr_store:
    movss   [rsp + MA_THR], xmm1
    movss   [rsp + MA_BEST], xmm2
    mov     r15d, [rsp + MA_LO + 8]
.scan_z:
    mov     r14d, [rsp + MA_LO + 4]
.scan_y:
    mov     r13d, [rsp + MA_LO]
.scan_x:
    mov     edi, r13d
    mov     esi, r14d
    mov     edx, r15d
    lea     rcx, [rsp + MA_BOXES]
    mov     r8d, BOXES_COLLIDE
    call    cell_boxes
    test    eax, eax
    jz      .cell_next
    mov     r9d, eax                    ; boxes in this cell
    lea     r10, [rsp + MA_BOXES]
.box:
    xor     ecx, ecx
.other:                                 ; strict overlap on the two axes that are not moving
    cmp     ecx, r12d
    je      .other_next
    movss   xmm0, [r10 + rcx*4]         ; box min
    ucomiss xmm0, [rsp + MA_MAX + rcx*4]
    jae     .box_next
    movss   xmm0, [r10 + 12 + rcx*4]    ; box max
    ucomiss xmm0, [rsp + MA_MIN + rcx*4]
    jbe     .box_next
.other_next:
    inc     ecx
    cmp     ecx, 3
    jb      .other
    cmp     dword [rsp + MA_DIR], 0
    je      .toward_neg
    movss   xmm0, [r10 + r12*4]         ; moving +: the box's near face is its min
    ucomiss xmm0, [rsp + MA_THR]
    jb      .box_next                   ; behind the body's far face: already past it
    subss   xmm0, [rsp + MA_OFFP]
    minss   xmm0, [rsp + MA_BEST]
    movss   [rsp + MA_BEST], xmm0
    jmp     .box_next
.toward_neg:
    movss   xmm0, [r10 + 12 + r12*4]    ; moving -: the box's near face is its max
    ucomiss xmm0, [rsp + MA_THR]
    ja      .box_next
    addss   xmm0, [rsp + MA_OFFN]
    maxss   xmm0, [rsp + MA_BEST]
    movss   [rsp + MA_BEST], xmm0
.box_next:
    add     r10, 24
    dec     r9d
    jnz     .box
.cell_next:
    inc     r13d
    cmp     r13d, [rsp + MA_HI]
    jle     .scan_x
    inc     r14d
    cmp     r14d, [rsp + MA_HI + 4]
    jle     .scan_y
    inc     r15d
    cmp     r15d, [rsp + MA_HI + 8]
    jle     .scan_z
    movss   xmm0, [rsp + MA_TARGET]
    movss   xmm1, [rsp + MA_BEST]
    cmp     dword [rsp + MA_DIR], 0
    je      .check_neg
    ucomiss xmm0, xmm1
    jb      .free                       ; target short of the tightest limit: the way is clear
    jmp     .hit
.check_neg:
    ucomiss xmm1, xmm0
    jb      .free
.hit:
    movss   [rbx + r12*4], xmm1         ; flush against what stopped it
    mov     dword [rbx + BODY.vx + r12*4], 0
    cmp     r12d, 1
    je      .hit_y
    mov     dword [rbx + BODY.blocked], 1
    jmp     .done
.hit_y:
    cmp     dword [rsp + MA_DIR], 0
    jne     .done                       ; a head bump
    mov     dword [rbx + BODY.on_ground], 1
    jmp     .done
.free:
    movss   [rbx + r12*4], xmm0
.done:
    add     rsp, MA_FRAME
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; body_on_ladder(rdi body) -> eax 1 when a cell the box strictly overlaps holds a ladder
; Frame: cell range lo[3] @0, hi[3] @16.
body_on_ladder:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40
    mov     rbx, rdi
    xor     ecx, ecx
.bounds:                                ; floor(min) .. ceil(max) - 1 on each axis
    movss   xmm3, [rbx + rcx*4]
    BOX_LO  xmm1, rbx, ecx
    BOX_HI  xmm2, rbx, ecx
    addss   xmm1, xmm3
    addss   xmm2, xmm3
    roundss xmm1, xmm1, 9
    cvttss2si eax, xmm1
    mov     [rsp + rcx*4], eax
    roundss xmm2, xmm2, 10
    cvttss2si eax, xmm2
    dec     eax
    mov     [rsp + 16 + rcx*4], eax
    inc     ecx
    cmp     ecx, 3
    jb      .bounds
    mov     r15d, [rsp + 8]
.z:
    mov     r14d, [rsp + 4]
.y:
    mov     r13d, [rsp]
.x:
    mov     edi, r13d
    mov     esi, r14d
    mov     edx, r15d
    call    world_get
    movzx   eax, byte [block_shape + rax]
    cmp     eax, SHAPE_LADDER
    je      .yes
    inc     r13d
    cmp     r13d, [rsp + 16]
    jle     .x
    inc     r14d
    cmp     r14d, [rsp + 20]
    jle     .y
    inc     r15d
    cmp     r15d, [rsp + 24]
    jle     .z
    xor     eax, eax
    jmp     .ret
.yes:
    mov     eax, 1
.ret:
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; step_up(rdi body, rsi float saved[6]: x0, z0, dx, dz, vx0, vz0): the horizontal moves of this
; step ended against something while the body stands on the ground. Redo them from the start
; lifted by c_step_h (less under a ceiling), then set the body back down by what it gained. The
; redo is kept only if it covered more ground than the first try did (blocked is then cleared);
; otherwise the first try's position, velocity and flags are restored.
; Frame: first try's x, y, z, vx, vy, vz @0, its ground covered @24, y before the lift @28,
; the lift @32.
step_up:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 48
    mov     rbx, rdi
    mov     r12, rsi
    xor     ecx, ecx
.keep:                                  ; x, y, z, vx, vy, vz are contiguous in BODY
    mov     eax, [rbx + rcx*4]
    mov     [rsp + rcx*4], eax
    inc     ecx
    cmp     ecx, 3
    jb      .keep
    mov     eax, [rbx + BODY.vx]
    mov     [rsp + 12], eax
    mov     eax, [rbx + BODY.vy]
    mov     [rsp + 16], eax
    mov     eax, [rbx + BODY.vz]
    mov     [rsp + 20], eax
    mov     eax, [rbx + BODY.y]
    mov     [rsp + 28], eax
    movss   xmm0, [rbx + BODY.x]
    subss   xmm0, [r12]
    movss   xmm1, [c_abs_mask]
    andps   xmm1, xmm0
    movss   xmm0, [rbx + BODY.z]
    subss   xmm0, [r12 + 4]
    movss   xmm2, [c_abs_mask]
    andps   xmm2, xmm0
    addss   xmm1, xmm2
    movss   [rsp + 24], xmm1            ; |dx| + |dz| the first try covered
    mov     eax, [r12]                  ; back to where the horizontal moves began
    mov     [rbx + BODY.x], eax
    mov     eax, [r12 + 4]
    mov     [rbx + BODY.z], eax
    mov     eax, [r12 + 16]
    mov     [rbx + BODY.vx], eax
    mov     eax, [r12 + 20]
    mov     [rbx + BODY.vz], eax
    mov     dword [rbx + BODY.blocked], 0
    movss   xmm0, [c_step_h]
    mov     rdi, rbx
    mov     esi, 1
    call    move_axis                   ; lift
    movss   xmm0, [rbx + BODY.y]
    subss   xmm0, [rsp + 28]
    movss   [rsp + 32], xmm0
    movss   xmm0, [r12 + 8]
    mov     rdi, rbx
    xor     esi, esi
    call    move_axis                   ; dx
    movss   xmm0, [r12 + 12]
    mov     rdi, rbx
    mov     esi, 2
    call    move_axis                   ; dz
    mov     dword [rbx + BODY.on_ground], 0
    xorps   xmm0, xmm0
    subss   xmm0, [rsp + 32]
    mov     rdi, rbx
    mov     esi, 1
    call    move_axis                   ; set down by what the lift gained
    movss   xmm0, [rbx + BODY.x]
    subss   xmm0, [r12]
    movss   xmm1, [c_abs_mask]
    andps   xmm1, xmm0
    movss   xmm0, [rbx + BODY.z]
    subss   xmm0, [r12 + 4]
    movss   xmm2, [c_abs_mask]
    andps   xmm2, xmm0
    addss   xmm1, xmm2                  ; ground the redo covered
    movss   xmm2, [rsp + 24]
    addss   xmm2, [c_step_gain]
    ucomiss xmm1, xmm2
    ja      .better
    xor     ecx, ecx
.restore:
    mov     eax, [rsp + rcx*4]
    mov     [rbx + rcx*4], eax
    inc     ecx
    cmp     ecx, 3
    jb      .restore
    mov     eax, [rsp + 12]
    mov     [rbx + BODY.vx], eax
    mov     eax, [rsp + 16]
    mov     [rbx + BODY.vy], eax
    mov     eax, [rsp + 20]
    mov     [rbx + BODY.vz], eax
    mov     dword [rbx + BODY.blocked], 1
    mov     dword [rbx + BODY.on_ground], 1
    jmp     .out
.better:
    mov     dword [rbx + BODY.blocked], 0
.out:
    add     rsp, 48
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
; order so that resting on the ground leaves y exactly integral. A ladder cell under the box
; overrides the vertical speed (climb, hold or slide) and ends every fall. A body on the ground
; that walks into a low step (slab, stair, trapdoor) is lifted over it (step_up).
; Swimming (not flying, body_in_liquid is WATER or LAVA at the start of the step): horizontal speed
; halves in water, drops to 0.3 in lava (sprint still x1.3), vy -= 10 dt down to -2.5, jump sets
; vy = 3 in water, 1.5 in lava (7 in either when the previous step was blocked horizontally: climbs a
; one-block ledge out of the liquid). A body that is in a liquid at the end of the step lands softly:
; its fall count is zeroed and the landed distance is 0.
; Frame: [rsp] y0, [rsp + 4] x0, z0, dx, dz, vx0, vz0 (what step_up needs), [rsp + 32] blocked
; by the previous step, [rsp + 36] the liquid the body is in (0, WATER or LAVA).
body_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 48
    mov     rbx, rdi
    mov     r12, rsi
    movss   xmm0, [rbx + BODY.y]
    movss   [rsp], xmm0
    mov     eax, [rbx + BODY.blocked]
    mov     [rsp + 32], eax
    mov     dword [rbx + BODY.blocked], 0
    xor     eax, eax
    cmp     dword [rbx + BODY.flying], 0
    jne     .swim_known
    mov     rdi, rbx
    call    body_in_liquid
.swim_known:
    mov     [rsp + 36], eax
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
    je      .sprint_done
    mulss   xmm5, [c_sprint]            ; sprinting is 30% faster than the current walk speed
.sprint_done:
    mov     eax, [rsp + 36]
    test    eax, eax
    je      .have_speed
    movss   xmm6, [c_half]              ; wading and swimming are half as fast ...
    cmp     eax, LAVA
    jne     .liquid_speed
    movss   xmm6, [c_lava_slow]         ; ... lava drags harder: 0.3
.liquid_speed:
    mulss   xmm5, xmm6
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
    cmp     dword [rsp + 36], 0
    jne     .swim_vy
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
.swim_vy:
    movss   xmm0, [rbx + BODY.vy]
    movss   xmm1, [c_swim_g]
    mulss   xmm1, [c_dt]
    subss   xmm0, xmm1                  ; vy -= 10 * dt
    maxss   xmm0, [c_swim_min]          ; sinks at 2.5 blocks/s at most
    cmp     dword [r12 + INPUT.jump], 0
    je      .vy_set
    movss   xmm0, [c_swim_up]           ; jump held: swim up at 3 (lava: 1.5)
    cmp     dword [rsp + 36], LAVA
    jne     .up_set
    movss   xmm0, [c_lava_up]
.up_set:
    cmp     dword [rsp + 32], 0
    je      .vy_set
    movss   xmm0, [c_swim_out]          ; ... against a ledge: 7, enough to climb out
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
    cmp     dword [rbx + BODY.flying], 0
    jne     .y_move
    mov     rdi, rbx
    call    body_on_ladder
    test    eax, eax
    jz      .y_move
    mov     dword [rbx + BODY.fall], 0  ; a ladder ends every fall
    movss   xmm0, [c_climb]
    cmp     dword [r12 + INPUT.fwd], 0
    jg      .ladder_vy                  ; forward or jump climbs
    cmp     dword [r12 + INPUT.jump], 0
    jne     .ladder_vy
    xorps   xmm0, xmm0
    cmp     dword [r12 + INPUT.down], 0
    jne     .ladder_vy                  ; sneaking holds on
    movss   xmm0, [rbx + BODY.vy]
    maxss   xmm0, [c_slide]             ; otherwise a slow slide down
.ladder_vy:
    movss   [rbx + BODY.vy], xmm0
.y_move:
    movss   xmm0, [rbx + BODY.vy]
    mulss   xmm0, [c_dt]
    mov     rdi, rbx
    mov     esi, 1
    call    move_axis
    mov     eax, [rbx + BODY.x]         ; where the horizontal moves start, for step_up
    mov     [rsp + 4], eax
    mov     eax, [rbx + BODY.z]
    mov     [rsp + 8], eax
    movss   xmm0, [rbx + BODY.vx]
    movss   [rsp + 20], xmm0
    mulss   xmm0, [c_dt]
    movss   [rsp + 12], xmm0
    movss   xmm0, [rbx + BODY.vz]
    movss   [rsp + 24], xmm0
    mulss   xmm0, [c_dt]
    movss   [rsp + 16], xmm0
    movss   xmm0, [rsp + 12]
    mov     rdi, rbx
    xor     esi, esi
    call    move_axis
    movss   xmm0, [rsp + 16]
    mov     rdi, rbx
    mov     esi, 2
    call    move_axis
    cmp     dword [rbx + BODY.flying], 0
    jne     .moved
    cmp     dword [rbx + BODY.on_ground], 0
    je      .moved
    cmp     dword [rbx + BODY.blocked], 0
    je      .moved
    mov     rdi, rbx
    lea     rsi, [rsp + 4]
    call    step_up                     ; a low step in the way: try to climb it
.moved:
    ; fall tracking: a body that ends the step in a liquid (water or lava) falls softly
    cmp     dword [rbx + BODY.flying], 0
    jne     .fall_reset
    mov     rdi, rbx
    call    body_in_liquid
    test    eax, eax
    jnz     .fall_reset
    xorps   xmm0, xmm0
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
    xorps   xmm0, xmm0
    movss   [rbx + BODY.fall], xmm0
.ret:
    add     rsp, 48
    pop     r12
    pop     rbx
    pop     rbp
    ret
