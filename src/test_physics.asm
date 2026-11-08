; test_physics.asm - raycast and player physics tests.
%include "common.inc"
default rel

global test_raycast_hit_forward, test_raycast_miss_beyond_reach, test_raycast_hit_from_above
global test_physics_land_on_floor, test_physics_wall_blocks
global test_physics_jump_clears_one_block, test_body_intersects_block
global test_swim_physics, test_boats

extern player, body_init, body_step, body_intersects_block
extern raycast, world_clear, world_set
extern body_in_water, player_eye_in_water, survival_reset, survival_land, surv, game_mode
extern drops, drops_clear, banner_text, str_eq
extern boats, boat_riding, boats_clear, boats_step, boats_place, boats_raycast, boats_mount
extern boats_break, boats_save, boats_load, boats_shift

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
k_4_5:   dd 4.5
k_m2_5:  dd -2.5
k_3_0:   dd 3.0
k_7_0:   dd 7.0
k_0_475: dd 0.475                       ; half the land speed, +-5%
k_0_525: dd 0.525
k_0_6:   dd 0.6
k_0_1:   dd 0.1
k_0_05:  dd 0.05
k_5_5:   dd 5.5
k_10_625: dd 10.625
k_12_5:  dd 12.5
k_3_5:   dd 3.5
k_1_35:  dd 1.35
k_1_45:  dd 1.45
k_506_5: dd -506.5
k_524_5: dd 524.5
k_123_5: dd 123.5
k_90:    dd 90.0
k_10_525: dd 10.525
k_10_725: dd 10.725
k_12_45: dd 12.45
k_12_55: dd 12.55
k_16_0:  dd 16.0
k_30_0:  dd 30.0
s_too_many: db "Too many boats", 0

section .bss
align 4
inp:    resb INPUT_size                 ; the INPUT handed to body_step
maxy:   resd 1                          ; highest feet y seen by the jump test
minvy:  resd 1                          ; lowest vy seen by the swim test
hdr_buf: resb WORLDHDR_size             ; a world header for the boat save / load round trip

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

; ---- swimming ----------------------------------------------------------------

; set_pool(): WATER over the stone floor of set_floor: x, z in 2..29, y in 11..15 (surface at y = 16)
set_pool:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     r13d, 2                     ; z
.z:
    mov     r12d, 2                     ; x
.x:
    mov     ebx, 11                     ; y
.y:
    mov     edi, r12d
    mov     esi, ebx
    mov     edx, r13d
    mov     ecx, WATER
    call    world_set
    inc     ebx
    cmp     ebx, 15
    jle     .y
    inc     r12d
    cmp     r12d, 29
    jle     .x
    inc     r13d
    cmp     r13d, 29
    jle     .z
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; fall_run(): 300 steps of body_step on the player; a landing is handed to survival_land as sim_step does
fall_run:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, 300
.step:
    lea     rdi, [player]
    lea     rsi, [inp]
    call    body_step
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jbe     .next
    call    survival_land
.next:
    dec     ebx
    jnz     .step
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; set_ledge(): STONE x 30..40, y 11..15, z 0..31 beside the pool: dry land level with the surface (y = 16)
set_ledge:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    xor     r13d, r13d                  ; z
.z:
    mov     r12d, 30                    ; x
.x:
    mov     ebx, 11                     ; y
.y:
    mov     edi, r12d
    mov     esi, ebx
    mov     edx, r13d
    mov     ecx, STONE
    call    world_set
    inc     ebx
    cmp     ebx, 15
    jle     .y
    inc     r12d
    cmp     r12d, 40
    jle     .x
    inc     r13d
    cmp     r13d, 31
    jle     .z
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; Swimming: 60 steps east in the pool cover half of what they cover on land (+-5%). A dry fall of 8
; blocks hurts (control), a fall of 20 blocks into 5 deep water does not, and ends standing on the pool
; floor. Sinking never exceeds 2.5 blocks/s; jump held gives vy 3 (7 when the last step was blocked).
; body_in_water / player_eye_in_water read the cells at feet + 0.05 / + 0.4 and at the eye.
; Frame: [rsp] unused, [rsp + 4] land distance, [rsp + 8] ratio, [rsp + 12] the caller's game_mode.
test_swim_physics:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 24
    mov     eax, [game_mode]
    mov     [rsp + 12], eax
    mov     dword [game_mode], MODE_SURVIVAL
    call    world_clear
    call    set_floor
    call    survival_reset
    ; 1. on land, 60 steps east
    call    reset_player
    SETF    [player + BODY.x], 4.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 16.5
    SETF    [player + BODY.yaw], 90.0
    mov     dword [player + BODY.on_ground], 1
    mov     dword [inp + INPUT.fwd], 1
    mov     edi, 60
    call    run_steps
    movss   xmm0, [player + BODY.x]
    subss   xmm0, [k_4_5]
    movss   [rsp + 4], xmm0
    ; 2. control: a dry fall from 8 blocks up (the floor top is y = 11) costs health
    call    reset_player
    SETF    [player + BODY.x], 30.5
    SETF    [player + BODY.y], 19.0
    SETF    [player + BODY.z], 30.5
    call    fall_run
    cmp     dword [surv + SURVIVAL.health], 20
    jge     .fail
    call    survival_reset
    call    set_pool
    ; 3. the same walk in the pool: half the distance
    call    reset_player
    SETF    [player + BODY.x], 4.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 16.5
    SETF    [player + BODY.yaw], 90.0
    mov     dword [player + BODY.on_ground], 1
    mov     dword [inp + INPUT.fwd], 1
    mov     edi, 60
    call    run_steps
    movss   xmm0, [player + BODY.x]
    subss   xmm0, [k_4_5]
    divss   xmm0, [rsp + 4]
    movss   [rsp + 8], xmm0
    FRANGE  [rsp + 8], k_0_475, k_0_525
    ; 4. a fall of 20 blocks into the pool: no damage, and the body ends on the pool floor
    call    survival_reset
    call    reset_player
    SETF    [player + BODY.x], 16.5
    SETF    [player + BODY.y], 36.0
    SETF    [player + BODY.z], 16.5
    call    fall_run
    cmp     dword [surv + SURVIVAL.health], 20
    jne     .fail
    FEQ     [player + BODY.y], k_11
    cmp     dword [player + BODY.on_ground], 1
    jne     .fail
    ; 5. sinking from the surface: never faster than 2.5 blocks/s, and exactly that once it is up to speed
    call    reset_player
    SETF    [player + BODY.x], 16.5
    SETF    [player + BODY.y], 15.5
    SETF    [player + BODY.z], 16.5
    mov     dword [minvy], 0
    mov     ebx, 100
.sink:
    mov     edi, 1
    call    run_steps
    movss   xmm0, [player + BODY.vy]
    minss   xmm0, [minvy]
    movss   [minvy], xmm0
    dec     ebx
    jnz     .sink
    FEQ     [minvy], k_m2_5
    ; 6. jump held in water: vy = 3; against a ledge (blocked last step) vy = 7
    call    reset_player
    SETF    [player + BODY.x], 16.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 16.5
    mov     dword [player + BODY.on_ground], 1
    mov     dword [inp + INPUT.jump], 1
    mov     edi, 1
    call    run_steps
    FEQ     [player + BODY.vy], k_3_0
    call    reset_player
    SETF    [player + BODY.x], 16.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 16.5
    mov     dword [player + BODY.on_ground], 1
    mov     dword [player + BODY.blocked], 1
    mov     dword [inp + INPUT.jump], 1
    mov     edi, 1
    call    run_steps
    FEQ     [player + BODY.vy], k_7_0
    ; 6b. a bank level with the surface: swimming against it with jump held climbs out onto it
    call    set_ledge
    call    reset_player
    SETF    [player + BODY.x], 29.5
    SETF    [player + BODY.y], 15.3
    SETF    [player + BODY.z], 16.5
    SETF    [player + BODY.yaw], 90.0
    mov     dword [inp + INPUT.fwd], 1
    mov     dword [inp + INPUT.jump], 1
    mov     edi, 40
    call    run_steps
    mov     dword [inp + INPUT.fwd], 0
    mov     dword [inp + INPUT.jump], 0
    mov     edi, 60
    call    run_steps
    FEQ     [player + BODY.y], k_16_0
    cmp     dword [player + BODY.on_ground], 1
    jne     .fail
    movss   xmm0, [player + BODY.x]
    ucomiss xmm0, [k_30_0]
    jbe     .fail
    ; 7. the water probes: feet cell, feet + 0.05, the eye
    call    reset_player
    SETF    [player + BODY.x], 16.5
    SETF    [player + BODY.y], 15.7
    SETF    [player + BODY.z], 16.5
    lea     rdi, [player]
    call    body_in_water
    cmp     eax, 1
    jne     .fail                       ; feet + 0.05 = 15.75: still in the top water cell
    SETF    [player + BODY.y], 16.0
    lea     rdi, [player]
    call    body_in_water
    test    eax, eax
    jnz     .fail                       ; standing on the surface: dry
    SETF    [player + BODY.x], 30.5
    SETF    [player + BODY.y], 11.0
    lea     rdi, [player]
    call    body_in_water
    test    eax, eax
    jnz     .fail                       ; the dry column
    SETF    [player + BODY.x], 16.5
    SETF    [player + BODY.y], 14.0
    call    player_eye_in_water
    cmp     eax, 1
    jne     .fail                       ; the eye at 15.62
    SETF    [player + BODY.y], 14.5
    call    player_eye_in_water
    test    eax, eax
    jnz     .fail                       ; the eye at 16.12: above the surface
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ecx, [rsp + 12]
    mov     [game_mode], ecx
    add     rsp, 24
    pop     rbx
    pop     rbp
    ret

; ---- boats -------------------------------------------------------------------

; boat_world(): stone floor at y = 9 over x, z in 0..31 and a 20 x 20 pool of water at y = 10 over
; x, z in 4..23
boat_world:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    xor     r12d, r12d                  ; z
.z:
    xor     ebx, ebx                    ; x
.x:
    mov     edi, ebx
    mov     esi, 9
    mov     edx, r12d
    mov     ecx, STONE
    call    world_set
    lea     eax, [rbx - 4]
    cmp     eax, 19
    ja      .dry
    lea     eax, [r12 - 4]
    cmp     eax, 19
    ja      .dry
    mov     edi, ebx
    mov     esi, 10
    mov     edx, r12d
    mov     ecx, WATER
    call    world_set
.dry:
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

; count_boat_drops() -> eax drop records holding a BOAT
count_boat_drops:
    lea     rsi, [drops]
    mov     ecx, MAX_DROPS
    xor     eax, eax
.l:
    cmp     byte [rsi + DROP.id], BOAT
    jne     .next
    inc     eax
.next:
    add     rsi, DROP_size
    dec     ecx
    jnz     .l
    ret

; PLACE_BOAT: boats_place from the shore: eye (3.5, 11.62, 12.5), direction (0.949, -0.316, 0) -> eax
%macro PLACE_BOAT 0
    lea     rdi, [rsp + 0]
    lea     rsi, [rsp + 16]
    call    boats_place
%endmacro

; Boats on a 20 x 20 pool at y = 10. A ray into the ground places nothing; from the shore a ray down
; into the water puts a boat in the water cell at (5, 10, 12): (5.5, 10.625, 12.5), heading = the
; player's yaw. The ray test finds it (t = 1.4) and not behind. Mounted, W for 90 steps carries it
; 3.5..5 blocks along the heading (east) at the surface (y = 10.625 +- 0.1) with the rider in it;
; sneak steps out 0.6 above it. Breaking it leaves one BOAT item in Survival (none in Creative). Save and
; load keep x, y, z, yaw and skip a NaN / far record. A shift moves it, and a boat outside the loaded
; columns does not move. A full table refuses with the banner.
; Frame: eye[3] @0, dir[3] @16, caller's game_mode @32, x0 @36.
test_boats:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 40
    mov     eax, [game_mode]
    mov     [rsp + 32], eax
    mov     dword [game_mode], MODE_CREATIVE
    call    world_clear
    call    drops_clear
    call    boats_clear
    call    boat_world
    call    reset_player
    SETF    [player + BODY.x], 3.5
    SETF    [player + BODY.y], 10.0
    SETF    [player + BODY.z], 12.5
    SETF    [player + BODY.yaw], 90.0
    SETF    [rsp + 0], 3.5
    SETF    [rsp + 4], 11.62
    SETF    [rsp + 8], 12.5
    SETF    [rsp + 16], 0.0
    SETF    [rsp + 20], -1.0
    SETF    [rsp + 24], 0.0
    SETF    [rsp + 0], 1.5
    PLACE_BOAT                          ; straight down over dry land: the stone floor, no water
    test    eax, eax
    jnz     .fail
    cmp     dword [boats + BOATENT.used], 0
    jne     .fail
    SETF    [rsp + 0], 3.5
    SETF    [rsp + 16], 0.9486833
    SETF    [rsp + 20], -0.3162278
    PLACE_BOAT
    cmp     eax, 1
    jne     .fail
    cmp     dword [boats + BOATENT.used], 1
    jne     .fail
    FEQ     [boats + BODY.x], k_5_5
    FEQ     [boats + BODY.y], k_10_625
    FEQ     [boats + BODY.z], k_12_5
    FEQ     [boats + BODY.yaw], k_90
    ; the ray test: along +x at y = 10.9 the hull's near face is at x = 4.9, 1.4 from x = 3.5
    SETF    [rsp + 0], 3.5
    SETF    [rsp + 4], 10.9
    SETF    [rsp + 16], 1.0
    SETF    [rsp + 20], 0.0
    lea     rdi, [rsp + 0]
    lea     rsi, [rsp + 16]
    movss   xmm0, [k_reach]
    call    boats_raycast
    test    eax, eax
    jnz     .fail
    movss   [rsp + 36], xmm0
    FRANGE  [rsp + 36], k_1_35, k_1_45
    SETF    [rsp + 16], -1.0            ; and looking away from it: nothing
    lea     rdi, [rsp + 0]
    lea     rsi, [rsp + 16]
    movss   xmm0, [k_reach]
    call    boats_raycast
    cmp     eax, -1
    jne     .fail
    xor     edi, edi                    ; mount: the rider sits in the boat
    call    boats_mount
    cmp     dword [boat_riding], 1
    jne     .fail
    FEQ     [player + BODY.x], k_5_5
    mov     dword [inp + INPUT.fwd], 1  ; W for 90 steps
    mov     ebx, 90
.drive:
    lea     rdi, [inp]
    call    boats_step
    dec     ebx
    jnz     .drive
    movss   xmm0, [boats + BODY.x]
    subss   xmm0, [k_5_5]
    movss   [rsp + 36], xmm0
    FRANGE  [rsp + 36], k_3_5, k_reach  ; 3.5 .. 5 blocks east
    FEQ     [boats + BOATENT.speed], k_reach    ; and is at the 5 blocks/s cap
    FRANGE  [boats + BODY.y], k_10_525, k_10_725
    FRANGE  [boats + BODY.z], k_12_45, k_12_55
    mov     eax, [boats + BODY.x]       ; the rider rides along
    cmp     eax, [player + BODY.x]
    jne     .fail
    mov     eax, [boats + BODY.z]
    cmp     eax, [player + BODY.z]
    jne     .fail
    mov     dword [inp + INPUT.fwd], 0  ; sneak: out, 0.6 above the boat
    mov     dword [inp + INPUT.down], 1
    lea     rdi, [inp]
    call    boats_step
    cmp     dword [boat_riding], 0
    jne     .fail
    movss   xmm0, [boats + BODY.y]
    addss   xmm0, [k_0_6]
    ucomiss xmm0, [player + BODY.y]
    jne     .fail
    jp      .fail
    mov     dword [inp + INPUT.down], 0
    mov     dword [game_mode], MODE_SURVIVAL
    call    drops_clear
    xor     edi, edi
    call    boats_break                 ; Survival: one BOAT item
    call    count_boat_drops
    cmp     eax, 1
    jne     .fail
    cmp     dword [boats + BOATENT.used], 0
    jne     .fail
    mov     dword [game_mode], MODE_CREATIVE
    call    drops_clear
    SETF    [rsp + 0], 3.5
    SETF    [rsp + 4], 11.62
    SETF    [rsp + 16], 0.9486833
    SETF    [rsp + 20], -0.3162278
    PLACE_BOAT
    cmp     eax, 1
    jne     .fail
    xor     edi, edi
    call    boats_break                 ; Creative: nothing drops
    call    count_boat_drops
    test    eax, eax
    jnz     .fail
    cmp     dword [boats + BOATENT.used], 0
    jne     .fail
    PLACE_BOAT                          ; save and load keep x, y, z, yaw
    cmp     eax, 1
    jne     .fail
    mov     dword [boats + BODY.yaw], __float32__(123.5)
    lea     rdi, [hdr_buf]
    call    boats_save
    cmp     dword [hdr_buf + WORLDHDR.boat_count], 1
    jne     .fail
    FEQ     [hdr_buf + WORLDHDR.boats + BOATSAVE.x], k_5_5
    call    boats_clear
    cmp     dword [boats + BOATENT.used], 0
    jne     .fail
    lea     rdi, [hdr_buf]
    call    boats_load
    cmp     dword [boats + BOATENT.used], 1
    jne     .fail
    FEQ     [boats + BODY.x], k_5_5
    FEQ     [boats + BODY.y], k_10_625
    FEQ     [boats + BODY.z], k_12_5
    FEQ     [boats + BODY.yaw], k_123_5
    cmp     dword [boat_riding], 0
    jne     .fail
    mov     dword [hdr_buf + WORLDHDR.boat_count], 3    ; record 1: NaN x; record 2: 70000 away in z
    mov     dword [hdr_buf + WORLDHDR.boats + BOATSAVE_size + BOATSAVE.x], 0x7FC00000
    mov     dword [hdr_buf + WORLDHDR.boats + BOATSAVE_size + BOATSAVE.y], __float32__(10.0)
    mov     dword [hdr_buf + WORLDHDR.boats + BOATSAVE_size + BOATSAVE.z], __float32__(12.5)
    mov     dword [hdr_buf + WORLDHDR.boats + 2 * BOATSAVE_size + BOATSAVE.x], __float32__(5.5)
    mov     dword [hdr_buf + WORLDHDR.boats + 2 * BOATSAVE_size + BOATSAVE.y], __float32__(10.0)
    mov     dword [hdr_buf + WORLDHDR.boats + 2 * BOATSAVE_size + BOATSAVE.z], __float32__(70000.0)
    lea     rdi, [hdr_buf]
    call    boats_load
    cmp     dword [boats + BOATENT.used], 1
    jne     .fail
    cmp     dword [boats + BOATENT_size + BOATENT.used], 0
    jne     .fail
    mov     edi, 512                    ; a shift moves it ...
    mov     esi, -512
    call    boats_shift
    FEQ     [boats + BODY.x], k_506_5
    FEQ     [boats + BODY.z], k_524_5
    mov     ebx, 5                      ; ... and a boat outside the lit columns does not fall
.frozen:
    lea     rdi, [inp]
    call    boats_step
    dec     ebx
    jnz     .frozen
    FEQ     [boats + BODY.y], k_10_625
    call    boats_clear                 ; a full table refuses, with the banner
    mov     ecx, MAX_BOATS
    lea     rax, [boats]
.fill:
    mov     dword [rax + BOATENT.used], 1
    add     rax, BOATENT_size
    dec     ecx
    jnz     .fill
    mov     byte [banner_text], 0
    PLACE_BOAT
    test    eax, eax
    jnz     .fail
    lea     rdi, [banner_text]
    lea     rsi, [s_too_many]
    call    str_eq
    test    eax, eax
    jz      .fail
    xor     ebx, ebx
    jmp     .cleanup
.fail:
    mov     ebx, 1
.cleanup:
    call    boats_clear
    call    drops_clear
    mov     eax, [rsp + 32]
    mov     [game_mode], eax
    mov     eax, ebx
    add     rsp, 40
    pop     rbx
    pop     rbp
    ret
