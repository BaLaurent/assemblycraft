; test_planes.asm - planes: placement, taxiing and takeoff, stalling, landing and crashing, the
; streaming governor, saving, leaving, the chase camera, targeting and breaking.
%include "common.inc"
default rel

global test_planes_place, test_planes_takeoff, test_planes_stall, test_planes_landing
global test_planes_crashes, test_planes_governor, test_planes_save_load, test_planes_leave
global test_planes_camera

extern planes, plane_riding, plane_view, planes_clear, planes_step, planes_place, planes_raycast
extern planes_board, planes_break, planes_save, planes_load, planes_shift, plane_view_cam
extern player, body_init, world_clear, world_set, drops, drops_clear, game_mode, net_role

section .rodata
align 4
k_half_w:   dd 0.3
k_height:   dd 1.8
k_speed:    dd 4.317
k_pl_hw:    dd 1.5
k_pl_h:     dd 1.2
k_far:      dd 40.0
k_9_99:     dd 9.99
k_10_01:    dd 10.01
k_10_5:     dd 10.5
k_5_5:      dd 5.5
k_6_5:      dd 6.5
k_12_0:     dd 12.0
k_12_4:     dd 12.4
k_12_6:     dd 12.6
k_24_1:     dd 24.1
k_24_5:     dd 24.5
k_29_0:     dd 29.0
k_31_0:     dd 31.0
k_123_5:    dd 123.5
k_506_5:    dd -506.5
k_m30:      dd -30.0
k_m16:      dd -16.0
k_16_5:     dd 16.5
k_18_5:     dd 18.5
k_19_9:     dd 19.9
k_21_0:     dd 21.0
k_21_5:     dd 21.5
k_22_1:     dd 22.1
k_10_55:    dd 10.55
k_10_65:    dd 10.65
k_14_5:     dd 14.5
k_90:       dd 90.0
k_22_4:     dd 22.4
k_22_6:     dd 22.6
section .bss
align 4
inp:        resb INPUT_size
hdr_buf:    resb WORLDHDR_size
saved_mode: resd 1
saved_role: resb 1

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

; BLOCK x, y, z, id: world_set
%macro BLOCK 4
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    call    world_set
%endmacro

; PLANE0 x, y, z, yaw: plane 0 on its feet at that place, speed 0, throttle 0, no pilot
%macro PLANE0 4
    lea     rdi, [planes]
    movss   xmm0, [k_pl_hw]
    movss   xmm1, [k_pl_h]
    xorps   xmm2, xmm2
    call    body_init
    SETF    [planes + BODY.x], %1
    SETF    [planes + BODY.y], %2
    SETF    [planes + BODY.z], %3
    SETF    [planes + BODY.yaw], %4
    SETF    [planes + PLANEENT.vmax], 24.0
    mov     dword [planes + PLANEENT.used], 1
%endmacro

; begin(): an empty world, Creative (no damage), offline, no planes, the player a plain body at rest
begin:
    push    rbp
    mov     rbp, rsp
    mov     eax, [game_mode]
    mov     [saved_mode], eax
    mov     dword [game_mode], MODE_CREATIVE
    movzx   eax, byte [net_role]
    mov     [saved_role], al
    mov     byte [net_role], NET_ROLE_OFF
    call    world_clear
    call    drops_clear
    call    planes_clear
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

; finish(): the mode and role begin() changed, back
finish:
    mov     eax, [saved_mode]
    mov     [game_mode], eax
    movzx   eax, byte [saved_role]
    mov     [net_role], al
    ret

; floor(edi last): STONE at y = 9 for x, z in 0..last
floor:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    mov     r13d, edi
    xor     r12d, r12d                  ; z
.z:
    xor     ebx, ebx                    ; x
.x:
    mov     edi, ebx
    mov     esi, 9
    mov     edx, r12d
    mov     ecx, STONE
    call    world_set
    inc     ebx
    cmp     ebx, r13d
    jbe     .x
    inc     r12d
    cmp     r12d, r13d
    jbe     .z
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; steps(edi n): n times planes_step(&inp)
steps:
    push    rbx
    mov     ebx, edi
.loop:
    lea     rdi, [inp]
    call    planes_step
    dec     ebx
    jnz     .loop
    pop     rbx
    ret

; count_plane_drops() -> eax drop records holding a PLANE
count_plane_drops:
    lea     rsi, [drops]
    mov     ecx, MAX_DROPS
    xor     eax, eax
.l:
    cmp     byte [rsi + DROP.id], PLANE
    jne     .next
    inc     eax
.next:
    add     rsi, DROP_size
    dec     ecx
    jnz     .l
    ret

; a RAYHIT at the top face of the block (24, 9, 24): the cell in front of it is (24, 10, 24)
%macro TOP_HIT 1
    mov     dword [%1 + RAYHIT.bx], 24
    mov     dword [%1 + RAYHIT.by], 9
    mov     dword [%1 + RAYHIT.bz], 24
    mov     dword [%1 + RAYHIT.px], 24
    mov     dword [%1 + RAYHIT.py], 10
    mov     dword [%1 + RAYHIT.pz], 24
%endmacro

; ---- placement, targeting, breaking -----------------------------------------------------------------
; A plane is put on the top face of a block: centred on the cell above it, bottom on the block, heading
; the player's yaw. A side face, a block inside the 3 x 3 x 2 cells, an unloaded column, a full table and
; multiplayer (which has no planes yet) refuse. A ray hits its 3 x 1.2 x 3 box and passes over it.
; Breaking leaves a PLANE item in Survival and nothing in Creative, and lets the pilot go.
test_planes_place:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 56                     ; RAYHIT @0 (24), ray origin @32, direction @44
    call    begin
    mov     edi, 47
    call    floor
    SETF    [player + BODY.yaw], 90.0
    TOP_HIT rsp
    mov     rdi, rsp
    call    planes_place
    cmp     eax, 1
    jne     .fail
    cmp     dword [planes + PLANEENT.used], 1
    jne     .fail
    FEQ     [planes + BODY.x], k_24_5
    FEQ     [planes + BODY.y], k_10_0
    FEQ     [planes + BODY.z], k_24_5
    FEQ     [planes + BODY.yaw], k_90
    FEQ     [planes + PLANEENT.vmax], k_24_0
    call    planes_clear
    mov     dword [rsp + RAYHIT.py], 9  ; a side face: the cell in front is level with the block
    mov     rdi, rsp
    call    planes_place
    test    eax, eax
    jnz     .fail
    TOP_HIT rsp
    BLOCK   25, 11, 24, STONE           ; a block in the footprint at the second level
    mov     rdi, rsp
    call    planes_place
    test    eax, eax
    jnz     .fail
    BLOCK   25, 11, 24, AIR
    BLOCK   23, 10, 25, STONE           ; ... or at the first, in a corner
    mov     rdi, rsp
    call    planes_place
    test    eax, eax
    jnz     .fail
    BLOCK   23, 10, 25, AIR
    mov     dword [rsp + RAYHIT.bx], 700 ; a column outside the loaded world
    mov     dword [rsp + RAYHIT.px], 700
    mov     dword [rsp + RAYHIT.py], 10
    mov     dword [rsp + RAYHIT.by], 9
    mov     dword [rsp + RAYHIT.bz], 24
    mov     dword [rsp + RAYHIT.pz], 24
    mov     rdi, rsp
    call    planes_place
    test    eax, eax
    jnz     .fail
    TOP_HIT rsp
    mov     byte [net_role], NET_ROLE_HOST      ; multiplayer has no planes yet
    mov     rdi, rsp
    call    planes_place
    test    eax, eax
    jnz     .fail
    mov     byte [net_role], NET_ROLE_OFF
    cmp     dword [planes + PLANEENT.used], 0
    jne     .fail
    mov     ebx, MAX_PLANES             ; a full table refuses
    lea     rax, [planes]
.fill:
    mov     dword [rax + PLANEENT.used], 1
    add     rax, PLANEENT_size
    dec     ebx
    jnz     .fill
    mov     rdi, rsp
    call    planes_place
    test    eax, eax
    jnz     .fail
    call    planes_clear
    PLANE0  24.5, 10.0, 24.5, 0.0
    SETF    [rsp + 32], 24.5            ; a ray along +z at the height of the box hits its near face ...
    SETF    [rsp + 36], 10.6
    SETF    [rsp + 40], 10.5
    SETF    [rsp + 44], 0.0
    SETF    [rsp + 48], 0.0
    SETF    [rsp + 52], 1.0
    lea     rdi, [rsp + 32]
    lea     rsi, [rsp + 44]
    movss   xmm0, [k_far]
    call    planes_raycast
    test    eax, eax
    jnz     .fail
    FRANGE  xmm0, k_12_4, k_12_6
    SETF    [rsp + 36], 11.5            ; ... and one above 1.2 passes over it
    lea     rdi, [rsp + 32]
    lea     rsi, [rsp + 44]
    movss   xmm0, [k_far]
    call    planes_raycast
    cmp     eax, -1
    jne     .fail
    mov     edi, 0                      ; Survival: breaking drops one PLANE and frees the slot
    mov     dword [plane_riding], 1
    mov     dword [game_mode], MODE_SURVIVAL
    call    planes_break
    cmp     dword [planes + PLANEENT.used], 0
    jne     .fail
    cmp     dword [plane_riding], 0
    jne     .fail
    call    count_plane_drops
    cmp     eax, 1
    jne     .fail
    call    drops_clear
    PLANE0  24.5, 10.0, 24.5, 0.0
    mov     dword [game_mode], MODE_CREATIVE
    mov     edi, 0
    call    planes_break
    call    count_plane_drops
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
    add     rsp, 56
    pop     rbx
    pop     rbp
    ret

; ---- takeoff -----------------------------------------------------------------------------------------
; Flown flat out from rest on stone the plane rolls: after 2.5 s it is at 12 b/s or more and still on
; the ground, at the surface (y = 10). Pitching up then lifts it off (air, well above the floor).
test_planes_takeoff:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    begin
    mov     edi, 47
    call    floor
    PLANE0  24.5, 10.0, 4.5, 180.0
    xor     edi, edi
    call    planes_board
    SETF    [player + BODY.yaw], 180.0
    mov     dword [inp + INPUT.fwd], 1
    mov     edi, 150
    call    steps
    FRANGE  [planes + PLANEENT.speed], k_12_0, k_24_1
    cmp     dword [planes + PLANEENT.air], 0
    jne     .fail
    FRANGE  [planes + BODY.y], k_9_99, k_10_01
    SETF    [player + BODY.pitch], -10.0        ; the view looks 10 degrees up
    mov     edi, 30
    call    steps
    cmp     dword [planes + PLANEENT.air], 1
    jne     .fail
    FRANGE  [planes + BODY.y], k_10_5, k_far
    cmp     dword [plane_riding], 1
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

; ---- stall -------------------------------------------------------------------------------------------
; In the air below 9 b/s there is no lift: after one second the plane has dropped well over four blocks
; and its nose is down more than 30 degrees.
test_planes_stall:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    begin
    mov     edi, 47
    call    floor
    PLANE0  24.5, 40.0, 24.5, 180.0
    mov     dword [planes + PLANEENT.air], 1
    SETF    [planes + PLANEENT.speed], 5.0
    mov     edi, 60
    call    steps
    cmp     dword [planes + PLANEENT.used], 1
    jne     .fail
    movss   xmm0, [planes + BODY.y]
    ucomiss xmm0, [k_36_0]
    jae     .fail
    movss   xmm0, [planes + PLANEENT.pitch]
    ucomiss xmm0, [k_m30]
    jae     .fail
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

; ---- landing -----------------------------------------------------------------------------------------
; Gliding down at 13 b/s with the nose 10 degrees down touches down softly: the plane stays, is on the
; ground at y = 10 and its pilot is still in it.
test_planes_landing:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    begin
    mov     edi, 47
    call    floor
    PLANE0  24.5, 11.5, 12.5, 180.0
    mov     dword [planes + PLANEENT.air], 1
    SETF    [planes + PLANEENT.speed], 13.0
    SETF    [planes + PLANEENT.pitch], -10.0
    SETF    [planes + PLANEENT.throttle], 0.54
    xor     edi, edi
    call    planes_board
    SETF    [player + BODY.yaw], 180.0
    SETF    [player + BODY.pitch], 10.0
    mov     ebx, 120
.glide:
    mov     edi, 1
    call    steps
    cmp     dword [planes + PLANEENT.air], 0
    je      .down
    dec     ebx
    jnz     .glide
    jmp     .fail                       ; never came down
.down:
    cmp     dword [planes + PLANEENT.used], 1
    jne     .fail
    cmp     dword [plane_riding], 1
    jne     .fail
    FRANGE  [planes + BODY.y], k_9_99, k_10_01
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

; ---- crashes -----------------------------------------------------------------------------------------
; Destroyed (slot free, pilot out of it): touching down with the nose more than 25 degrees down, falling
; stalled onto the floor (vy below -9), water at its bottom, a wall at more than 14 b/s. A wall at 8 b/s
; only stops it.
test_planes_crashes:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    begin
    mov     edi, 47
    call    floor
    PLANE0  24.5, 16.0, 12.5, 180.0    ; nose down: the view looks 35 degrees down (the most)
    mov     dword [planes + PLANEENT.air], 1
    SETF    [planes + PLANEENT.speed], 13.0
    SETF    [planes + PLANEENT.throttle], 0.54
    xor     edi, edi
    call    planes_board
    SETF    [player + BODY.yaw], 180.0
    SETF    [player + BODY.pitch], 35.0
    mov     ebx, 150
.dive:
    mov     edi, 1
    call    steps
    cmp     dword [planes + PLANEENT.used], 0
    je      .dived
    dec     ebx
    jnz     .dive
    jmp     .fail
.dived:
    cmp     dword [plane_riding], 0
    jne     .fail
    call    planes_clear
    PLANE0  24.5, 22.0, 24.5, 180.0    ; stalled, no pilot: falls 12 blocks (vy about -22)
    mov     dword [planes + PLANEENT.air], 1
    mov     ebx, 120
.fall:
    mov     edi, 1
    call    steps
    cmp     dword [planes + PLANEENT.used], 0
    je      .fell
    dec     ebx
    jnz     .fall
    jmp     .fail
.fell:
    call    planes_clear
    PLANE0  24.5, 10.0, 24.5, 0.0     ; on the ground with water at its bottom cell
    BLOCK   24, 10, 24, WATER
    mov     edi, 1
    call    steps
    cmp     dword [planes + PLANEENT.used], 0
    jne     .fail
    BLOCK   24, 10, 24, AIR
    call    planes_clear
    BLOCK   24, 10, 20, STONE           ; a wall across the way north (-z) from z = 30.5
    BLOCK   25, 10, 20, STONE
    BLOCK   23, 10, 20, STONE
    BLOCK   24, 11, 20, STONE
    PLANE0  24.5, 10.0, 30.5, 0.0
    SETF    [planes + PLANEENT.speed], 20.0
    SETF    [planes + PLANEENT.throttle], 0.9
    mov     ebx, 120
.ram:
    mov     edi, 1
    call    steps
    cmp     dword [planes + PLANEENT.used], 0
    je      .rammed
    dec     ebx
    jnz     .ram
    jmp     .fail
.rammed:
    call    planes_clear
    PLANE0  24.5, 10.0, 24.5, 0.0       ; 8 b/s at a wall 5 blocks ahead: stopped, not destroyed
    SETF    [planes + PLANEENT.speed], 8.0
    SETF    [planes + PLANEENT.throttle], 0.34
    mov     edi, 60
    call    steps
    cmp     dword [planes + PLANEENT.used], 1
    jne     .fail
    FRANGE  [planes + BODY.z], k_22_4, k_22_6
    FRANGE  [planes + PLANEENT.speed], k_zero, k_9_0
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

; ---- streaming governor ------------------------------------------------------------------------------
; Flying towards the edge of the loaded world (the test arena ends at cell -16), the speed cap falls and
; stops at 12 (PL_STALL + 3): never below, and the plane does not leave the loaded area. With loaded
; columns ahead the cap climbs again.
test_planes_governor:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    begin
    PLANE0  24.5, 30.0, 8.5, 0.0       ; north (-z): the sampled columns at z -8, -24 ... lie outside
    mov     dword [planes + PLANEENT.air], 1
    SETF    [planes + PLANEENT.speed], 24.0
    SETF    [planes + PLANEENT.throttle], 1.0
    xor     edi, edi                    ; flown (a plane without a pilot idles: its throttle is the pilot's)
    call    planes_board
    SETF    [player + BODY.yaw], 0.0
    mov     edi, 30
    call    steps
    FRANGE  [planes + PLANEENT.vmax], k_21_5, k_23_9
    mov     edi, 400
    call    steps
    FEQ     [planes + PLANEENT.vmax], k_12_0
    cmp     dword [planes + PLANEENT.used], 1
    jne     .fail
    FRANGE  [planes + BODY.z], k_m16, k_9_0
    FRANGE  [planes + BODY.y], k_29_0, k_31_0
    SETF    [planes + PLANEENT.vmax], 12.0      ; the same plane going south: all four sampled columns are loaded
    SETF    [planes + BODY.x], 48.5
    SETF    [planes + BODY.z], 4.5
    SETF    [planes + BODY.yaw], 180.0
    SETF    [player + BODY.yaw], 180.0
    mov     edi, 60
    call    steps
    FRANGE  [planes + PLANEENT.vmax], k_13_5, k_14_5
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

; ---- saving ------------------------------------------------------------------------------------------
; The used planes' x, y, z, yaw round-trip through the header; a record with a NaN or a far coordinate is
; skipped; the count is capped at 4; a shift moves x and z.
test_planes_save_load:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    begin
    PLANE0  5.5, 10.0, 6.5, 123.5
    lea     rdi, [hdr_buf]
    call    planes_save
    cmp     dword [hdr_buf + WORLDHDR.plane_count], 1
    jne     .fail
    FEQ     [hdr_buf + WORLDHDR.planes + PLANESAVE.x], k_5_5
    call    planes_clear
    lea     rdi, [hdr_buf]
    call    planes_load
    cmp     dword [planes + PLANEENT.used], 1
    jne     .fail
    FEQ     [planes + BODY.x], k_5_5
    FEQ     [planes + BODY.y], k_10_0
    FEQ     [planes + BODY.z], k_6_5
    FEQ     [planes + BODY.yaw], k_123_5
    FEQ     [planes + PLANEENT.vmax], k_24_0
    cmp     dword [plane_riding], 0
    jne     .fail
    mov     dword [hdr_buf + WORLDHDR.plane_count], 3   ; record 0 is the plane above, 1: NaN x; 2: 2e7 away in z
    mov     dword [hdr_buf + WORLDHDR.planes + PLANESAVE_size + PLANESAVE.x], 0x7FC00000
    mov     dword [hdr_buf + WORLDHDR.planes + PLANESAVE_size + PLANESAVE.y], __float32__(10.0)
    mov     dword [hdr_buf + WORLDHDR.planes + PLANESAVE_size + PLANESAVE.z], __float32__(12.5)
    mov     dword [hdr_buf + WORLDHDR.planes + 2 * PLANESAVE_size + PLANESAVE.x], __float32__(5.5)
    mov     dword [hdr_buf + WORLDHDR.planes + 2 * PLANESAVE_size + PLANESAVE.y], __float32__(10.0)
    mov     dword [hdr_buf + WORLDHDR.planes + 2 * PLANESAVE_size + PLANESAVE.z], __float32__(20000000.0)
    lea     rdi, [hdr_buf]
    call    planes_load
    cmp     dword [planes + PLANEENT.used], 1
    jne     .fail
    cmp     dword [planes + PLANEENT_size + PLANEENT.used], 0
    jne     .fail
    mov     edi, 512                    ; a shift moves it
    mov     esi, -512
    call    planes_shift
    FEQ     [planes + BODY.x], k_506_5
    FEQ     [planes + BODY.z], k_518_5
    mov     dword [hdr_buf + WORLDHDR.plane_count], 9   ; a count beyond the table is capped
    lea     rdi, [hdr_buf]
    call    planes_load
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

; ---- leaving -----------------------------------------------------------------------------------------
; Sneaking lets the pilot out only on the ground and slower than 1 b/s: he then stands 0.6 above the
; plane's bottom. In the air, or while rolling at 5 b/s, he stays in his seat.
test_planes_leave:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    begin
    mov     edi, 47
    call    floor
    PLANE0  24.5, 10.0, 24.5, 0.0
    xor     edi, edi
    call    planes_board
    mov     dword [inp + INPUT.down], 1
    mov     dword [planes + PLANEENT.air], 1    ; in the air: stays
    SETF    [planes + BODY.y], 20.0
    mov     edi, 1
    call    steps
    cmp     dword [plane_riding], 1
    jne     .fail
    mov     dword [planes + PLANEENT.air], 0    ; on the ground at 5 b/s (throttle 0.2 keeps it there): stays
    SETF    [planes + BODY.y], 10.0
    SETF    [planes + PLANEENT.speed], 5.0
    SETF    [planes + PLANEENT.throttle], 0.2
    mov     edi, 1
    call    steps
    cmp     dword [plane_riding], 1
    jne     .fail
    SETF    [planes + PLANEENT.speed], 0.0
    mov     dword [planes + PLANEENT.throttle], 0
    mov     edi, 1
    call    steps
    cmp     dword [plane_riding], 0
    jne     .fail
    FRANGE  [player + BODY.y], k_10_55, k_10_65
    FEQ     [player + BODY.x], k_24_5
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

; ---- chase camera ------------------------------------------------------------------------------------
; A pilot in third person is drawn from a body 7 blocks behind the plane (heading south: smaller z), 2.5
; above its pivot and looking along the plane's heading; a block on the way pulls it in; in the cockpit,
; or on foot, the camera is the player himself.
test_planes_camera:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    begin
    mov     edi, 47
    call    floor
    lea     rax, [player]
    mov     rbx, rax
    call    plane_view_cam
    cmp     rax, rbx
    jne     .fail                       ; nobody flies: the player
    PLANE0  24.5, 20.0, 24.5, 180.0
    mov     dword [planes + PLANEENT.air], 1
    xor     edi, edi
    call    planes_board
    mov     dword [plane_view], 0
    call    plane_view_cam
    cmp     rax, rbx
    jne     .fail                       ; the cockpit: the player
    mov     dword [plane_view], 1
    call    plane_view_cam
    cmp     rax, rbx
    je      .fail
    mov     rbx, rax
    FRANGE  [rbx + BODY.z], k_16_5, k_18_5
    FRANGE  [rbx + BODY.x], k_24_0, k_25_0
    FRANGE  [rbx + BODY.y], k_21_5, k_22_1          ; 20 + 0.9 + 2.5 - the eye's 1.62 = 21.78
    FEQ     [rbx + BODY.yaw], k_180
    BLOCK   24, 22, 19, STONE                       ; a block on the way: pulled in to 0.3 before it
    call    plane_view_cam
    FRANGE  [rax + BODY.z], k_19_9, k_21_0
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
k_10_0:     dd 10.0
k_24_0:     dd 24.0
k_25_0:     dd 25.0
k_36_0:     dd 36.0
k_9_0:      dd 9.0
k_zero:     dd 0.0
k_23_9:     dd 23.9
k_13_5:     dd 13.5
k_518_5:    dd 518.5
k_180:      dd 180.0
