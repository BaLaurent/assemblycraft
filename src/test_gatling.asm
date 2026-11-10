; test_gatling.asm - a plane gunner's Gatling: the aiming cone, the fire rate, who may fire and the left button.
%include "common.inc"
default rel

global test_gatling_cone, test_gatling_fire, test_gatling_seats

extern gatling_step, gatling_input, plane_riding, plane_seat, planes, frame_input, player, body_init
extern arrows, arrows_clear

section .rodata
align 4
k_pl_hw:    dd 1.5
k_pl_h:     dd 1.2
k_p_hw:     dd 0.3
k_p_h:      dd 1.8
k_p_speed:  dd 4.317
k_340:      dd 340.0
k_270:      dd 270.0
k_40:       dd 40.0
k_m40:      dd -40.0
k_10:       dd 10.0


section .text

; SETF mem, float literal
%macro SETF 2
    mov     dword %1, __float32__(%2)
%endmacro

; fail unless the float at %1 equals the float constant at %2
%macro FEQ 2
    movss   xmm0, %1
    ucomiss xmm0, [%2]
    jne     .fail
    jp      .fail
%endmacro

; begin(): plane 0 at (16.5, 20, 16.5) heading north (yaw 0), the player a body in its left gunner seat (1) looking
; west (yaw 270, the middle of the cone), no arrows, an empty frame_input
begin:
    lea     rdi, [planes]
    movss   xmm0, [k_pl_hw]
    movss   xmm1, [k_pl_h]
    xorps   xmm2, xmm2
    call    body_init
    SETF    [planes + BODY.x], 16.5
    SETF    [planes + BODY.y], 20.0
    SETF    [planes + BODY.z], 16.5
    mov     dword [planes + PLANEENT.used], 1
    lea     rdi, [player]
    movss   xmm0, [k_p_hw]
    movss   xmm1, [k_p_h]
    movss   xmm2, [k_p_speed]
    call    body_init
    SETF    [player + BODY.x], 15.6
    SETF    [player + BODY.y], 20.15
    SETF    [player + BODY.z], 16.5
    SETF    [player + BODY.yaw], 270.0
    mov     dword [plane_riding], 1
    mov     dword [plane_seat], 1
    call    arrows_clear
    lea     rdi, [frame_input]
    mov     ecx, FRAMEINPUT_size
    xor     eax, eax
    rep     stosb
    call    gatling_input               ; (an empty frame, then a step with no button: the cooldown starts at 0)
    call    gatling_step
    ret

; finish(): nobody rides, no arrows
finish:
    sub     rsp, 8
    mov     dword [plane_riding], 0
    mov     dword [plane_seat], 0
    mov     dword [planes + PLANEENT.used], 0
    call    arrows_clear
    lea     rdi, [frame_input]
    mov     ecx, FRAMEINPUT_size
    xor     eax, eax
    rep     stosb
    add     rsp, 8
    ret

; bullets() -> eax live bullets
bullets:
    lea     rcx, [arrows]
    xor     eax, eax
    mov     edx, MAX_ARROWS
.l:
    cmp     dword [rcx + ARROWENT.live], 0
    je      .next
    cmp     dword [rcx + ARROWENT.kind], PROJ_BULLET
    jne     .next
    inc     eax
.next:
    add     rcx, ARROWENT_size
    dec     edx
    jnz     .l
    ret

; ---- the cone ----------------------------------------------------------------------------------------
; The left gunner's cone is centred on west (yaw 270 for a plane heading north): yaw 270 stays; yaw 0 (90 degrees
; round to the right) comes back to 340 (270 + 70); yaw 180 (90 round to the left) to 200 (270 - 70);
; pitch is held within +-40 (down is +). A plane heading east moves the cone with it (side = 90 - 90 = 0).
test_gatling_cone:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    begin
    SETF    [player + BODY.pitch], 10.0
    call    gatling_step
    FEQ     [player + BODY.yaw], k_270
    FEQ     [player + BODY.pitch], k_10
    SETF    [player + BODY.yaw], 0.0
    SETF    [player + BODY.pitch], 60.0
    call    gatling_step
    FEQ     [player + BODY.yaw], k_340
    FEQ     [player + BODY.pitch], k_40
    SETF    [player + BODY.yaw], 180.0
    SETF    [player + BODY.pitch], -60.0
    call    gatling_step
    FEQ     [player + BODY.yaw], k_200
    FEQ     [player + BODY.pitch], k_m40
    SETF    [planes + BODY.yaw], 90.0           ; heading east: the left side is north (yaw 0)
    SETF    [player + BODY.yaw], 90.0
    call    gatling_step
    FEQ     [player + BODY.yaw], k_70
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    finish
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- fire --------------------------------------------------------------------------------------------
; Held for 60 steps the button puts ten bullets in the air (the first at once, then every 6 steps), flying west
; at about 110 blocks/s, owned by the player, 3 damage, never picked up. Released, nothing more is fired.
test_gatling_fire:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    begin
    mov     dword [frame_input + FRAMEINPUT.lmb_held], 1
    call    gatling_input                       ; a frame's input: the latch takes the button
    cmp     dword [frame_input + FRAMEINPUT.lmb_held], 0
    jne     .fail
    mov     ebx, 60
.held:
    call    gatling_step
    dec     ebx
    jnz     .held
    call    bullets
    cmp     eax, 10
    jne     .fail
    lea     rcx, [arrows]
    cmp     dword [rcx + ARROWENT.owner], OWNER_PLAYER
    jne     .fail
    cmp     dword [rcx + ARROWENT.damage], 3
    jne     .fail
    cmp     dword [rcx + ARROWENT.pickup], 0
    jne     .fail
    movss   xmm0, [rcx + ARROWENT.vx]
    ucomiss xmm0, [k_m100]
    ja      .fail                       ; west: vx below -100
    movss   xmm0, [rcx + ARROWENT.vx]
    ucomiss xmm0, [k_m111]
    jb      .fail
    call    gatling_input                       ; the button is up
    mov     ebx, 30
.released:
    call    gatling_step
    dec     ebx
    jnz     .released
    call    bullets
    cmp     eax, 10
    jne     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    finish
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- who may fire ------------------------------------------------------------------------------------
; Only a gunner in a plane that exists: the pilot (seat 0), a player on foot and a seat in a plane that is gone
; fire nothing. gatling_input takes the left button from a gunner and leaves everybody else's alone.
test_gatling_seats:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    begin
    mov     dword [frame_input + FRAMEINPUT.lmb_held], 1
    mov     dword [frame_input + FRAMEINPUT.lmb_pressed], 1
    mov     dword [plane_seat], 0               ; the pilot
    call    gatling_input
    mov     ebx, 12
.pilot:
    call    gatling_step
    dec     ebx
    jnz     .pilot
    call    bullets
    test    eax, eax
    jnz     .fail
    cmp     dword [frame_input + FRAMEINPUT.lmb_held], 1
    jne     .fail                               ; the pilot keeps his button
    mov     dword [plane_seat], 2               ; right gunner: fires, and the button is his gun's
    SETF    [player + BODY.yaw], 90.0
    call    gatling_input
    call    gatling_step
    call    bullets
    cmp     eax, 1
    jne     .fail
    cmp     dword [frame_input + FRAMEINPUT.lmb_held], 0
    jne     .fail
    cmp     dword [frame_input + FRAMEINPUT.lmb_pressed], 0
    jne     .fail
    call    arrows_clear
    mov     dword [frame_input + FRAMEINPUT.lmb_held], 1
    mov     dword [frame_input + FRAMEINPUT.lmb_pressed], 1
    mov     dword [plane_riding], 0             ; on foot
    call    gatling_input
    mov     ebx, 12
.foot:
    call    gatling_step
    dec     ebx
    jnz     .foot
    call    bullets
    test    eax, eax
    jnz     .fail
    cmp     dword [frame_input + FRAMEINPUT.lmb_held], 1
    jne     .fail                               ; his button is his own
    mov     dword [plane_riding], 1             ; the plane is gone
    mov     dword [planes + PLANEENT.used], 0
    call    gatling_step
    call    bullets
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    finish
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

section .rodata
align 4
k_200:      dd 200.0
k_70:       dd 70.0
k_m100:     dd -100.0
k_m111:     dd -111.0
