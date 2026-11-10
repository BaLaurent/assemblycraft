; gatling.asm - the Gatlings of a plane's three gunner seats (planes.asm: plane_seat 1 left, 2 right, 3 tail).
; A gunner's view is held inside a cone around his seat's side (70 degrees either way in yaw, 40 in pitch);
; while the left button is held a bullet leaves his eye every 6 steps (10 shots a second): no magazine, no
; ammunition, no reload. The bullets are the player's own projectiles (arrows_spawn, PROJ_BULLET, a weapon
; attack): they hurt mobs, and players when PvP is on, never break blocks, and every other machine shows
; their ghost twins (arrows_spawn sends them), so a shot needs no message of its own.
%include "common.inc"
default rel

global gatling_step, gatling_input

extern player, player_eye, player_forward, spread_unit
extern plane_riding, plane_seat, planes, frame_input
extern arrows_spawn, audio_play

%define GAT_PERIOD      6               ; steps between two shots
%define GAT_DAMAGE      3               ; the base damage of a bullet (the damage pipeline scales it)

section .rodata
align 4
c_side:     dd 0.0, -90.0, 90.0, 180.0  ; a seat's side relative to the plane's heading, by seat (0: the pilot, unused)
c_yaw_max:  dd 70.0
c_pitch_max: dd 40.0
c_pitch_min: dd -40.0
c_360:      dd 360.0
c_speed:    dd 110.0                    ; muzzle speed, blocks/s
c_spread:   dd 0.026                    ; about 1.5 degrees
c_muzzle:   dd 0.3                      ; a bullet leaves this far in front of the eye
c_vol:      dd 0.6

section .bss
gat_cd:     resd 1                      ; steps until the next shot
gat_held:   resd 1                      ; the left button as game_frame saw it this frame (a gunner only)

section .text

; gatling_plane() -> rax the plane whose gunner seat the player sits in, 0 when he is not a gunner; ecx = his seat
gatling_plane:
    xor     eax, eax
    mov     edx, [plane_riding]
    test    edx, edx
    jz      .ret
    mov     ecx, [plane_seat]
    test    ecx, ecx
    jz      .ret                        ; the pilot has no gun
    cmp     ecx, 3
    ja      .ret
    dec     edx
    cmp     edx, MAX_PLANES
    jae     .ret
    imul    edx, edx, PLANEENT_size
    lea     rax, [planes]
    add     rax, rdx
    cmp     dword [rax + PLANEENT.used], 0
    jne     .ret
    xor     eax, eax
.ret:
    ret

; gatling_shoot(): one bullet from the player's eye along his view, jittered by the spread, at 110 blocks/s
; Frame: eye[3] @0, dir[3] @12.
gatling_shoot:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 40
    lea     rdi, [rsp]
    call    player_eye
    lea     rdi, [rsp + 12]
    call    player_forward
    xor     ebx, ebx
.jitter:
    call    spread_unit
    mulss   xmm0, [c_spread]
    addss   xmm0, [rsp + 12 + rbx*4]
    movss   [rsp + 12 + rbx*4], xmm0
    inc     ebx
    cmp     ebx, 3
    jb      .jitter
    movss   xmm0, [rsp + 12]            ; renormalise
    mulss   xmm0, xmm0
    movss   xmm1, [rsp + 16]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    movss   xmm1, [rsp + 20]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    sqrtss  xmm0, xmm0
    xor     ebx, ebx
.unit:
    movss   xmm1, [rsp + 12 + rbx*4]
    divss   xmm1, xmm0
    movss   [rsp + 12 + rbx*4], xmm1
    inc     ebx
    cmp     ebx, 3
    jb      .unit
    movss   xmm6, [c_speed]
    movss   xmm7, [c_muzzle]
    movss   xmm3, [rsp + 12]
    movss   xmm4, [rsp + 16]
    movss   xmm5, [rsp + 20]
    movss   xmm0, xmm3
    mulss   xmm0, xmm7
    addss   xmm0, [rsp]
    movss   xmm1, xmm4
    mulss   xmm1, xmm7
    addss   xmm1, [rsp + 4]
    movss   xmm2, xmm5
    mulss   xmm2, xmm7
    addss   xmm2, [rsp + 8]
    mulss   xmm3, xmm6
    mulss   xmm4, xmm6
    mulss   xmm5, xmm6
    xor     edi, edi                    ; owner: the player
    mov     esi, GAT_DAMAGE
    xor     edx, edx                    ; never picked up
    mov     ecx, PROJ_BULLET
    mov     r8d, AF_ATTACK
    call    arrows_spawn
    mov     edi, SND_PISTOL
    movss   xmm0, [c_vol]
    call    audio_play
    add     rsp, 40
    pop     rbx
    pop     rbp
    ret

; gatling_step(): one fixed step of the player's Gatling, when he sits in a gunner seat. His yaw stays within 70
; degrees of the seat's side (the plane's heading + -90, +90 or 180) and his pitch within +-40; with the left
; button held (gatling_input) a bullet leaves every 6 steps, the first at once.
gatling_step:
    push    rbp
    mov     rbp, rsp
    call    gatling_plane
    test    rax, rax
    jz      .idle
    movss   xmm0, [rax + BODY.yaw]
    lea     rdx, [c_side]
    addss   xmm0, [rdx + rcx*4]         ; the seat's side
    movss   xmm1, [player + BODY.yaw]
    subss   xmm1, xmm0                  ; his yaw relative to it, brought into [-180, 180]
    movss   xmm2, xmm1
    divss   xmm2, [c_360]
    roundss xmm2, xmm2, 8
    mulss   xmm2, [c_360]
    subss   xmm1, xmm2
    minss   xmm1, [c_yaw_max]
    xorps   xmm2, xmm2
    subss   xmm2, [c_yaw_max]
    maxss   xmm1, xmm2
    addss   xmm0, xmm1                  ; side + the clamped offset, into [0, 360)
    movss   xmm2, xmm0
    divss   xmm2, [c_360]
    roundss xmm2, xmm2, 9
    mulss   xmm2, [c_360]
    subss   xmm0, xmm2
    movss   [player + BODY.yaw], xmm0
    movss   xmm0, [player + BODY.pitch]
    minss   xmm0, [c_pitch_max]
    maxss   xmm0, [c_pitch_min]
    movss   [player + BODY.pitch], xmm0
    cmp     dword [gat_cd], 0
    jle     .ready
    dec     dword [gat_cd]
.ready:
    cmp     dword [gat_cd], 0
    jg      .ret
    cmp     dword [gat_held], 0
    je      .ret
    mov     dword [gat_cd], GAT_PERIOD
    call    gatling_shoot
    jmp     .ret
.idle:
    mov     dword [gat_cd], 0
.ret:
    pop     rbp
    ret

; gatling_input(): once a frame, before its steps: a gunner's left button belongs to his gun. gat_held keeps it for
; the steps and frame_input loses it, so the gun, dig, attack and break code of game_frame never sees it; for
; anybody else gat_held is 0 and frame_input stays as it is.
gatling_input:
    sub     rsp, 8
    mov     dword [gat_held], 0
    call    gatling_plane
    test    rax, rax
    jz      .ret
    mov     eax, [frame_input + FRAMEINPUT.lmb_held]
    mov     [gat_held], eax
    mov     dword [frame_input + FRAMEINPUT.lmb_held], 0
    mov     dword [frame_input + FRAMEINPUT.lmb_pressed], 0
.ret:
    add     rsp, 8
    ret
