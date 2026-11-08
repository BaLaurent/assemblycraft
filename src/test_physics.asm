; test_physics.asm - raycast and player physics tests.
%include "common.inc"
default rel

global test_raycast_hit_forward, test_raycast_miss_beyond_reach, test_raycast_hit_from_above
global test_physics_land_on_floor, test_physics_wall_blocks
global test_physics_jump_clears_one_block, test_body_intersects_block

extern player, body_init, body_step, body_intersects_block
extern raycast, world_clear, world_set

section .rodata
align 4
k_half_w: dd 0.3
k_height: dd 1.8
k_speed:  dd 4.317
k_reach: dd 5.0
k_11:    dd 11.0
k_12:    dd 12.0
k_x_lo:  dd 17.69
k_x_hi:  dd 17.70
k_z_lo:  dd 16.49
k_z_hi:  dd 16.51

section .bss
align 4
inp:    resb INPUT_size                 ; the INPUT handed to body_step
maxy:   resd 1                          ; highest feet y seen by the jump test

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

; fail unless lo <= float at %1 <= hi (constants at %2, %3); NaN fails
%macro FRANGE 3
    movss   xmm0, %1
    ucomiss xmm0, [%2]
    jb      .fail
    ucomiss xmm0, [%3]
    ja      .fail
%endmacro

; ---- helpers -----------------------------------------------------------------

; set_floor(): STONE at y = 10 for x, z in 0..31
set_floor:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    xor     r12d, r12d                  ; z
.z:
    xor     ebx, ebx                    ; x
.x:
    mov     edi, ebx
    mov     esi, 10
    mov     edx, r12d
    mov     ecx, STONE
    call    world_set
    inc     ebx
    cmp     ebx, 32
    jb      .x
    inc     r12d
    cmp     r12d, 32
    jb      .z
    pop     r12
    pop     rbx
    pop     rbp
    ret

; set_wall(): STONE at x = 18, y in {11, 12}, z in 0..31
set_wall:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    xor     ebx, ebx                    ; z
.z:
    mov     edi, 18
    mov     esi, 11
    mov     edx, ebx
    mov     ecx, STONE
    call    world_set
    mov     edi, 18
    mov     esi, 12
    mov     edx, ebx
    mov     ecx, STONE
    call    world_set
    inc     ebx
    cmp     ebx, 32
    jb      .z
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; reset_player(): standard player body (0.3 x 1.8, walk 4.317), zero input
reset_player:
    push    rbp
    mov     rbp, rsp
    lea     rdi, [player]
    movss   xmm0, [k_half_w]
    movss   xmm1, [k_height]
    movss   xmm2, [k_speed]
    call    body_init
    lea     rdi, [inp]
    mov     ecx, INPUT_size
    xor     eax, eax
    rep     stosb
    pop     rbp
    ret

; run_steps(edi n >= 1): n times body_step(&player, &inp)
run_steps:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
.loop:
    lea     rdi, [player]
    lea     rsi, [inp]
    call    body_step
    dec     ebx
    jnz     .loop
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- raycast -----------------------------------------------------------------

; Frame: origin[3] @0, dir[3] @16, RAYHIT @32 (64 bytes).
%define R_ORG 0
%define R_DIR 16
%define R_HIT 32

; casts the ray in the frame with maxdist 5.0 -> eax
%macro CAST 0
    lea     rdi, [rsp + R_ORG]
    lea     rsi, [rsp + R_DIR]
    lea     rdx, [rsp + R_HIT]
    movss   xmm0, [k_reach]
    call    raycast
%endmacro

; fail unless the RAYHIT in the frame is b = (%1, %2, %3), p = (%4, %5, %6)
%macro EXPECT_HIT 6
    cmp     dword [rsp + R_HIT + RAYHIT.bx], %1
    jne     .fail
    cmp     dword [rsp + R_HIT + RAYHIT.by], %2
    jne     .fail
    cmp     dword [rsp + R_HIT + RAYHIT.bz], %3
    jne     .fail
    cmp     dword [rsp + R_HIT + RAYHIT.px], %4
    jne     .fail
    cmp     dword [rsp + R_HIT + RAYHIT.py], %5
    jne     .fail
    cmp     dword [rsp + R_HIT + RAYHIT.pz], %6
    jne     .fail
%endmacro

; STONE at (10, 10, 10) in a cleared world
%macro SET_TARGET 0
    mov     edi, 10
    mov     esi, 10
    mov     edx, 10
    mov     ecx, STONE
    call    world_set
%endmacro

test_raycast_hit_forward:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 64
    call    world_clear
    SET_TARGET
    SETF    [rsp + R_ORG + 0], 10.5
    SETF    [rsp + R_ORG + 4], 10.5
    SETF    [rsp + R_ORG + 8], 5.5
    SETF    [rsp + R_DIR + 0], 0.0
    SETF    [rsp + R_DIR + 4], 0.0
    SETF    [rsp + R_DIR + 8], 1.0
    CAST
    cmp     eax, 1
    jne     .fail
    EXPECT_HIT 10, 10, 10, 10, 10, 9
    xor     eax, eax
    leave
    ret
.fail:
    mov     eax, 1
    leave
    ret

test_raycast_miss_beyond_reach:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 64
    call    world_clear
    SET_TARGET
    SETF    [rsp + R_ORG + 0], 10.5
    SETF    [rsp + R_ORG + 4], 10.5
    SETF    [rsp + R_ORG + 8], 4.0
    SETF    [rsp + R_DIR + 0], 0.0
    SETF    [rsp + R_DIR + 4], 0.0
    SETF    [rsp + R_DIR + 8], 1.0
    CAST
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    leave
    ret
.fail:
    mov     eax, 1
    leave
    ret

test_raycast_hit_from_above:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 64
    call    world_clear
    SET_TARGET
    SETF    [rsp + R_ORG + 0], 10.5
    SETF    [rsp + R_ORG + 4], 13.0
    SETF    [rsp + R_ORG + 8], 10.5
    SETF    [rsp + R_DIR + 0], 0.0
    SETF    [rsp + R_DIR + 4], -1.0
    SETF    [rsp + R_DIR + 8], 0.0
    CAST
    cmp     eax, 1
    jne     .fail
    EXPECT_HIT 10, 10, 10, 10, 11, 10
    xor     eax, eax
    leave
    ret
.fail:
    mov     eax, 1
    leave
    ret

; ---- player physics ----------------------------------------------------------

test_physics_land_on_floor:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    call    set_floor
    call    reset_player
    SETF    [player + BODY.x], 16.5
    SETF    [player + BODY.y], 12.0
    SETF    [player + BODY.z], 16.5
    mov     edi, 120
    call    run_steps
    FEQ     [player + BODY.y], k_11
    cmp     dword [player + BODY.on_ground], 1
    jne     .fail
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret

test_physics_wall_blocks:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    call    set_floor
    call    set_wall
    call    reset_player
    SETF    [player + BODY.x], 16.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 16.5
    SETF    [player + BODY.yaw], 90.0
    mov     dword [player + BODY.on_ground], 1
    mov     dword [inp + INPUT.fwd], 1
    mov     edi, 120
    call    run_steps
    FRANGE  [player + BODY.x], k_x_lo, k_x_hi
    FEQ     [player + BODY.y], k_11
    FRANGE  [player + BODY.z], k_z_lo, k_z_hi
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret

test_physics_jump_clears_one_block:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    call    set_floor
    call    reset_player
    SETF    [player + BODY.x], 16.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 16.5
    mov     dword [player + BODY.on_ground], 1
    mov     dword [inp + INPUT.jump], 1
    mov     edi, 1
    call    run_steps
    mov     dword [inp + INPUT.jump], 0
    mov     eax, [player + BODY.y]
    mov     [maxy], eax
    mov     edi, 59
    call    .track
    FEQ     [player + BODY.y], k_11
    movss   xmm0, [maxy]
    ucomiss xmm0, [k_12]
    jbe     .fail                       ; need max y > 12.0
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret
; track(edi n): n single steps, recording the highest feet y in maxy
.track:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
.t_loop:
    mov     edi, 1
    call    run_steps
    movss   xmm0, [player + BODY.y]
    maxss   xmm0, [maxy]
    movss   [maxy], xmm0
    dec     ebx
    jnz     .t_loop
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; player at (16.5, 11, 16.5): box x 16.2..16.8, y 11..12.8, z 16.2..16.8
%macro EXPECT_OVERLAP 4                 ; x, y, z, expected 0/1
    lea     rdi, [player]
    mov     esi, %1
    mov     edx, %2
    mov     ecx, %3
    mov     r8d, STONE
    call    body_intersects_block
    cmp     eax, %4
    jne     .fail
%endmacro

test_body_intersects_block:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    call    reset_player
    SETF    [player + BODY.x], 16.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 16.5
    EXPECT_OVERLAP 16, 11, 16, 1
    EXPECT_OVERLAP 16, 12, 16, 1
    EXPECT_OVERLAP 16, 13, 16, 0
    EXPECT_OVERLAP 17, 11, 16, 0
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret
