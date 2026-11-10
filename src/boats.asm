; boats.asm - boats: put on water, floating, driven by the rider, broken into an item, kept in the
; world header (WORLDHDR.boats) and drawn as the skin model m_boat. All coordinates are local. A boat is
; a BODY (y = bottom of its 1.2 x 0.5 x 1.2 box, yaw = heading; the box is 2.05 high while the player
; rides it, so that a ceiling over the water stops it before the rider's head meets it) plus its speed
; along the heading.
%include "common.inc"
%include "gl.inc"
default rel

global boats, boat_riding, boat_rider
global boats_clear, boats_step, boats_render, boats_place, boats_raycast, boats_mount
global boats_dismount, boats_break, boats_save, boats_load, boats_shift, coord_ok, meshable

extern body_init, move_axis, sincos_deg
extern world_get, world_is_solid, world_column_ready
extern player, game_mode, hud_banner, drops_spawn, ray_aabb
extern light_bind_at, light_bind_index, skin_model_draw, m_boat
extern net_role, net_applying, net_send_to
extern net_boat_place_out, net_boat_mount_out, net_boat_dismount_out, net_boat_break_out

section .rodata
align 4
c_dt:       dd 0.016666668              ; one fixed step, seconds
c_half_w:   dd 0.6                      ; the box: 1.2 wide ...
c_height:   dd 0.5                      ; ... 0.5 high
c_ridden_h: dd 2.05                     ; a ridden boat collides as high as its rider reaches: his feet are
                                        ; 0.25 above its bottom and he is 1.8 tall
c_half:     dd 0.5                      ; the middle of a cell
c_quarter:  dd 0.25                     ; the boat's light is sampled this far above its bottom
c_rest:     dd 0.625                    ; a floating boat's bottom above the floor of its water cell
c_probe:    dd 0.3                      ; the boat floats when the cell at y + 0.3 or at y is water
c_buoy:     dd 4.0                      ; vy = (rest level - y) * 4, within +-2
c_vmax:     dd 2.0
c_vmin:     dd -2.0
c_grav:     dd 20.0                     ; out of the water: vy -= 20 dt, at most 20 down
c_vfall:    dd -20.0
c_drag:     dd 0.9                      ; out of the water the speed shrinks by 10% per step
c_top:      dd 5.0                      ; speed targets, blocks/s: forward, reverse
c_rev:      dd -1.5
c_acc:      dd 4.0                      ; b/s^2 while a key is held
c_brake:    dd 2.0                      ; b/s^2 with no key (and for an empty boat)
c_turn:     dd 90.0                     ; degrees per second
c_360:      dd 360.0
c_lift:     dd 0.6                      ; a dismounting rider lands this far above the boat
c_rider:    dd 0.25                     ; the rider's feet above the boat's bottom
c_pop:      dd 0.3                      ; a broken boat's item appears this far above its bottom
c_far:      dd 1.0e30                   ; "this axis never moves"
c_one:      dd 1.0
c_reach:    dd 5.0                      ; boats_place reaches 5 blocks
c_nudge:    dd 0.11                     ; boats_place keeps the hull this far from a solid block beside it
c_bound:    dd 16777216.0               ; saved coordinates must lie inside +-2^24 (exact floats;
                                        ; a moored boat may be left far behind by rebases)
c_256:      dd 256.0
c_abs_mask: dd 0x7FFFFFFF
s_many:     db "Too many boats", 0

section .bss
alignb 16
boats:       resb MAX_BOATS * BOATENT_size
boat_riding: resd 1                     ; 0, or the index + 1 of the boat the player rides
boat_rider:  resb MAX_BOATS            ; host: peer slot + 1 of the guest who rides the boat, 0 none

section .text

; boats_clear(): no boats, nobody riding
boats_clear:
    lea     rdi, [boats]
    mov     ecx, MAX_BOATS * BOATENT_size
    xor     eax, eax
    rep     stosb
    lea     rdi, [boat_rider]           ; (eax is still 0)
    mov     ecx, MAX_BOATS
    rep     stosb
    mov     dword [boat_riding], 0
    ret

; boat_at(edi idx) -> rax the BOATENT of slot idx (idx < MAX_BOATS)
boat_at:
    imul    eax, edi, BOATENT_size
    lea     rdx, [boats]
    add     rax, rdx
    ret

; seat(rdi boat): the rider sits in the boat: its x and z, feet 0.25 above its bottom, at rest
seat:
    mov     eax, [rdi + BODY.x]
    mov     [player + BODY.x], eax
    mov     eax, [rdi + BODY.z]
    mov     [player + BODY.z], eax
    movss   xmm0, [rdi + BODY.y]
    addss   xmm0, [c_rider]
    movss   [player + BODY.y], xmm0
    xor     eax, eax
    mov     [player + BODY.vx], eax
    mov     [player + BODY.vy], eax
    mov     [player + BODY.vz], eax
    mov     [player + BODY.fall], eax
    mov     dword [player + BODY.on_ground], 1
    ret

; boats_place(rdi eye float[3], rsi dir float[3]) -> eax 1 when a boat was put on the water
; Walks the cells the ray enters for up to 5 blocks. A solid block ends the search (0). The first
; WATER cell whose cell above is not solid takes the boat: centred in the cell (but for the nudge of
; hull_nudge away from solid blocks beside it; with such blocks on both sides along x or z there is
; no room: 0), bottom 0.625 over the cell's floor, heading = the player's yaw. A full boat table
; says "Too many boats" (0). The caller consumes the item in Survival. A guest only sends the
; request to the host (net_boat_place_out) and says 1: the boat shows with the host's next snapshot.
; r13 = eye, r14 = dir, r15d = cells left, rbx = the new boat, r12d = slot counter.
; Frame: cell[3] @0, step[3] @16, tmax[3] @32, tdelta[3] @48; once the cell is found the hull's
; nudge: x @32, z @36.
boats_place:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 72
    mov     r13, rdi
    mov     r14, rsi
    xor     ecx, ecx
.setup:                                 ; one pass per axis
    movss   xmm0, [r13 + rcx*4]         ; o
    movss   xmm1, [r14 + rcx*4]         ; d
    roundss xmm2, xmm0, 9               ; floor(o)
    cvttss2si eax, xmm2
    mov     [rsp + rcx*4], eax
    movss   xmm5, [c_far]               ; tmax
    movaps  xmm6, xmm5                  ; tdelta
    xor     edx, edx                    ; step
    xorps   xmm3, xmm3
    ucomiss xmm1, xmm3
    jp      .axis_done                  ; NaN direction: the axis does not move
    ja      .pos
    jb      .neg
    jmp     .axis_done                  ; d == 0
.pos:
    mov     edx, 1
    movss   xmm3, [c_one]
    movaps  xmm6, xmm3
    divss   xmm6, xmm1                  ; tdelta = 1 / d
    addss   xmm2, xmm3
    subss   xmm2, xmm0                  ; cell + 1 - o
    divss   xmm2, xmm1
    movaps  xmm5, xmm2
    jmp     .axis_done
.neg:
    mov     edx, -1
    xorps   xmm4, xmm4
    subss   xmm4, xmm1                  ; -d
    movss   xmm6, [c_one]
    divss   xmm6, xmm4                  ; tdelta = 1 / -d
    subss   xmm0, xmm2                  ; o - cell
    divss   xmm0, xmm4
    movaps  xmm5, xmm0
.axis_done:
    mov     [rsp + 16 + rcx*4], edx
    movss   [rsp + 32 + rcx*4], xmm5
    movss   [rsp + 48 + rcx*4], xmm6
    inc     ecx
    cmp     ecx, 3
    jb      .setup
    mov     r15d, 64
.cell:
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    mov     edx, [rsp + 8]
    call    world_is_solid
    test    eax, eax
    jnz     .none                       ; a block in the way (or an unloaded column)
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    mov     edx, [rsp + 8]
    call    world_get
    cmp     eax, WATER
    jne     .advance
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    inc     esi
    mov     edx, [rsp + 8]
    call    world_is_solid
    test    eax, eax
    jz      .found                      ; water with room above it
.advance:
    movss   xmm0, [rsp + 32]            ; the axis with the smallest tmax (ties: x, then y)
    xor     ecx, ecx
    movss   xmm1, [rsp + 36]
    ucomiss xmm0, xmm1
    jbe     .not_y
    movaps  xmm0, xmm1
    mov     ecx, 1
.not_y:
    movss   xmm1, [rsp + 40]
    ucomiss xmm0, xmm1
    jbe     .not_z
    movaps  xmm0, xmm1
    mov     ecx, 2
.not_z:
    ucomiss xmm0, [c_reach]
    ja      .none                       ; the next cell lies beyond 5 blocks
    mov     eax, [rsp + 16 + rcx*4]
    add     [rsp + rcx*4], eax
    addss   xmm0, [rsp + 48 + rcx*4]
    movss   [rsp + 32 + rcx*4], xmm0
    dec     r15d
    jnz     .cell
.none:
    xor     eax, eax
    jmp     .out
.found:
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    mov     edx, [rsp + 8]
    call    hull_nudge                  ; solid blocks beside the cell push the hull away from them
    test    eax, eax
    jz      .none                       ; or leave no room for it
    movss   [rsp + 32], xmm0
    movss   [rsp + 36], xmm1
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .local
    cmp     byte [net_applying], 0
    jne     .local
    mov     rdi, r13                    ; a guest: the host puts the boat on the water
    mov     rsi, r14
    call    net_boat_place_out
    mov     eax, 1
    jmp     .out
.local:
    lea     rbx, [boats]
    xor     r12d, r12d
.slot:
    cmp     dword [rbx + BOATENT.used], 0
    je      .take
    add     rbx, BOATENT_size
    inc     r12d
    cmp     r12d, MAX_BOATS
    jb      .slot
    cmp     byte [net_applying], 0
    jne     .full                       ; a guest's request on the host: no banner (nw_on_boat_place gives the item back)
    lea     rdi, [s_many]
    mov     esi, RGBA(255, 150, 90, 255)
    call    hud_banner
.full:
    xor     eax, eax
    jmp     .out
.take:
    mov     rdi, rbx
    movss   xmm0, [c_half_w]
    movss   xmm1, [c_height]
    xorps   xmm2, xmm2
    call    body_init
    cvtsi2ss xmm0, dword [rsp]
    addss   xmm0, [c_half]
    addss   xmm0, [rsp + 32]
    movss   [rbx + BODY.x], xmm0
    cvtsi2ss xmm0, dword [rsp + 4]
    addss   xmm0, [c_rest]
    movss   [rbx + BODY.y], xmm0
    cvtsi2ss xmm0, dword [rsp + 8]
    addss   xmm0, [c_half]
    addss   xmm0, [rsp + 36]
    movss   [rbx + BODY.z], xmm0
    mov     eax, [player + BODY.yaw]
    mov     [rbx + BODY.yaw], eax
    mov     dword [rbx + BOATENT.used], 1
    mov     dword [rbx + BOATENT.speed], 0
    mov     eax, 1
.out:
    add     rsp, 72
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

%macro HULL_PROBE 4                     ; dx, dy, dz, bit
    lea     edi, [rbx + %1]
    lea     esi, [r12 + %2]
    lea     edx, [r13 + %3]
    call    world_is_solid
    test    eax, eax
    jz      %%free
    or      r15d, %4
%%free:
%endmacro

; hull_nudge(edi x, esi y, edx z) -> eax 1 with xmm0 = x offset and xmm1 = z offset (floats), or eax 0:
; no room. (x, y, z) is the water cell a boat is about to be put in. The hull is 1.2 wide: centred in
; the 1-wide cell it overlaps the cells beside it by 0.1, and move_axis lets a body move through a block
; it already overlaps, so a boat put against a wall could be driven through it. A solid cell beside the
; water cell at the hull's two levels (y and y + 1) therefore pushes the hull 0.11 the other way (0.01
; of clearance); solid cells on both sides along x, or along z, leave no room.
; ebx, r12d, r13d = x, y, z; r15d = the solid sides found: bit 0 -x, 1 +x, 2 -z, 3 +z.
hull_nudge:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r15
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    xor     r15d, r15d
    HULL_PROBE -1, 0, 0, 1
    HULL_PROBE -1, 1, 0, 1
    HULL_PROBE 1, 0, 0, 2
    HULL_PROBE 1, 1, 0, 2
    HULL_PROBE 0, 0, -1, 4
    HULL_PROBE 0, 1, -1, 4
    HULL_PROBE 0, 0, 1, 8
    HULL_PROBE 0, 1, 1, 8
    mov     eax, r15d
    and     eax, 3
    cmp     eax, 3
    je      .none                       ; solid on both sides along x ...
    mov     eax, r15d
    shr     eax, 2
    cmp     eax, 3
    je      .none                       ; ... or along z
    xorps   xmm0, xmm0
    xorps   xmm1, xmm1
    movss   xmm2, [c_nudge]
    test    r15d, 1
    jz      .no_xm
    addss   xmm0, xmm2                  ; solid at -x: towards +x
.no_xm:
    test    r15d, 2
    jz      .no_xp
    subss   xmm0, xmm2
.no_xp:
    test    r15d, 4
    jz      .no_zm
    addss   xmm1, xmm2
.no_zm:
    test    r15d, 8
    jz      .no_zp
    subss   xmm1, xmm2
.no_zp:
    mov     eax, 1
    jmp     .out
.none:
    xor     eax, eax
.out:
    pop     r15
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; boats_step(rdi INPUT*): one fixed step of every boat whose column is lit (the others are frozen).
; Floating (the cell at y + 0.3 or at y is WATER): vy = clamp((highest water cell within one of
; floor(y), + 0.625 - y) * 4, -2, 2). Otherwise vy -= 20 dt (at least -20) and the speed shrinks by
; 10%. The ridden boat (boat_riding): INPUT.fwd +1 aims at 5 blocks/s and -1 at -1.5 with 4 b/s^2,
; no key brakes at 2 b/s^2; INPUT.strafe turns at 90 degrees per second (+1 = clockwise from above,
; as a mouse moved right); INPUT.down dismounts. An empty boat brakes at 2 b/s^2. The boat moves
; along (sin yaw, -cos yaw) by speed * dt on x, then z, then y (move_axis); a horizontal block
; stops it dead. The rider is carried: the player takes the boat's x and z, feet at its bottom +
; 0.25, at rest and "on the ground". The boat's box is 0.5 high, and 2.05 (the rider's 0.25 plus his
; 1.8) while the player rides it: a ceiling that his head would meet stops the boat. The height is
; derived from boat_riding every step, so no path that lets go of a boat has to restore it.
; rbx = boat, r12 = INPUT*, r13d = index, r14d = ridden, r15d = floating.
; Multiplayer: a guest steps only the boat it rides (the others follow the host's snapshots); the
; host leaves a boat a guest rides (boat_rider) to that guest's pose messages.
; Frame: cell x @0, z @4, floor(y) @8, scan offset @12, dx @20, dz @24.
boats_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40
    mov     r12, rdi
    mov     eax, [boat_riding]
    test    eax, eax
    jz      .begin
    dec     eax
    cmp     eax, MAX_BOATS
    jae     .stale
    imul    ecx, eax, BOATENT_size
    lea     rdx, [boats]
    cmp     dword [rdx + rcx + BOATENT.used], 0
    jne     .begin
.stale:
    mov     dword [boat_riding], 0      ; the boat is gone: nobody rides it
.begin:
    lea     rbx, [boats]
    xor     r13d, r13d
.boat:
    cmp     dword [rbx + BOATENT.used], 0
    je      .next
    movss   xmm0, [rbx + BODY.x]
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    mov     [rsp], eax
    movss   xmm0, [rbx + BODY.z]
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    mov     [rsp + 4], eax
    movss   xmm0, [rbx + BODY.y]
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    mov     [rsp + 8], eax
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    call    world_column_ready
    test    eax, eax
    jz      .next                       ; its column is not lit: frozen
    lea     eax, [r13 + 1]
    xor     r14d, r14d
    cmp     eax, [boat_riding]
    sete    r14b
    movzx   eax, byte [net_role]
    test    eax, eax
    jz      .own                        ; offline: every boat steps
    cmp     eax, NET_ROLE_GUEST
    jne     .host_boat
    test    r14d, r14d                  ; a guest steps only the boat it rides: the others follow the
    jz      .next                       ; host's snapshots
    jmp     .own
.host_boat:
    lea     rax, [boat_rider]
    cmp     byte [rax + r13], 0         ; a boat a guest rides follows that guest's pose messages
    jne     .next
.own:
    movss   xmm0, [rbx + BODY.y]
    addss   xmm0, [c_probe]
    roundss xmm0, xmm0, 9
    cvttss2si esi, xmm0
    mov     edi, [rsp]
    mov     edx, [rsp + 4]
    call    world_get
    cmp     eax, WATER
    je      .floats
    mov     edi, [rsp]
    mov     esi, [rsp + 8]
    mov     edx, [rsp + 4]
    call    world_get
    cmp     eax, WATER
    je      .floats
    movss   xmm0, [rbx + BODY.vy]       ; in the air: fall and lose speed
    movss   xmm1, [c_grav]
    mulss   xmm1, [c_dt]
    subss   xmm0, xmm1
    maxss   xmm0, [c_vfall]
    movss   [rbx + BODY.vy], xmm0
    movss   xmm0, [rbx + BOATENT.speed]
    mulss   xmm0, [c_drag]
    movss   [rbx + BOATENT.speed], xmm0
    jmp     .drive
.floats:
    mov     dword [rsp + 12], 1         ; the highest water among floor(y) + 1, + 0, - 1
.scan:
    mov     edi, [rsp]
    mov     esi, [rsp + 8]
    add     esi, [rsp + 12]
    mov     edx, [rsp + 4]
    call    world_get
    cmp     eax, WATER
    je      .level
    dec     dword [rsp + 12]
    cmp     dword [rsp + 12], -1
    jge     .scan
    mov     dword [rsp + 12], 0
.level:
    mov     eax, [rsp + 8]
    add     eax, [rsp + 12]
    cvtsi2ss xmm0, eax
    addss   xmm0, [c_rest]
    subss   xmm0, [rbx + BODY.y]
    mulss   xmm0, [c_buoy]
    minss   xmm0, [c_vmax]
    maxss   xmm0, [c_vmin]
    movss   [rbx + BODY.vy], xmm0
.drive:
    test    r14d, r14d
    jz      .coast
    cmp     dword [r12 + INPUT.down], 0
    je      .controls
    call    boats_dismount              ; sneak: out of the boat
    xor     r14d, r14d
    jmp     .coast
.controls:
    cvtsi2ss xmm0, dword [r12 + INPUT.strafe]
    mulss   xmm0, [c_turn]
    mulss   xmm0, [c_dt]
    addss   xmm0, [rbx + BODY.yaw]
    xorps   xmm1, xmm1
.wrap_up:                               ; the heading stays in [0, 360)
    ucomiss xmm1, xmm0
    jbe     .wrap_down
    addss   xmm0, [c_360]
    jmp     .wrap_up
.wrap_down:
    ucomiss xmm0, [c_360]
    jb      .yaw_ok
    subss   xmm0, [c_360]
    jmp     .wrap_down
.yaw_ok:
    movss   [rbx + BODY.yaw], xmm0
    mov     eax, [r12 + INPUT.fwd]
    xorps   xmm1, xmm1                  ; target speed
    movss   xmm2, [c_brake]             ; rate
    test    eax, eax
    jz      .speed_set
    movss   xmm2, [c_acc]
    movss   xmm1, [c_top]
    jg      .speed_set
    movss   xmm1, [c_rev]
    jmp     .speed_set
.coast:
    xorps   xmm1, xmm1
    movss   xmm2, [c_brake]
.speed_set:                             ; the speed moves towards xmm1 by at most rate * dt
    mulss   xmm2, [c_dt]
    movss   xmm0, [rbx + BOATENT.speed]
    subss   xmm1, xmm0
    minss   xmm1, xmm2
    xorps   xmm3, xmm3
    subss   xmm3, xmm2
    maxss   xmm1, xmm3
    addss   xmm0, xmm1
    movss   [rbx + BOATENT.speed], xmm0
    mov     eax, [c_height]             ; the box: the hull, and the rider standing in it
    mov     ecx, [c_ridden_h]
    test    r14d, r14d
    cmovnz  eax, ecx
    mov     [rbx + BODY.height], eax
    movss   xmm0, [rbx + BODY.yaw]
    call    sincos_deg                  ; xmm0 = sin yaw, xmm1 = cos yaw
    movss   xmm2, [rbx + BOATENT.speed]
    mulss   xmm2, [c_dt]                ; the distance this step
    mulss   xmm0, xmm2
    movss   [rsp + 20], xmm0            ; dx = sin * distance
    mulss   xmm1, xmm2
    xorps   xmm3, xmm3
    subss   xmm3, xmm1
    movss   [rsp + 24], xmm3            ; dz = -cos * distance
    mov     dword [rbx + BODY.blocked], 0
    movss   xmm0, [rsp + 20]
    mov     rdi, rbx
    xor     esi, esi
    call    move_axis
    movss   xmm0, [rsp + 24]
    mov     rdi, rbx
    mov     esi, 2
    call    move_axis
    movss   xmm0, [rbx + BODY.vy]
    mulss   xmm0, [c_dt]
    mov     rdi, rbx
    mov     esi, 1
    call    move_axis
    cmp     dword [rbx + BODY.blocked], 0
    je      .carry
    mov     dword [rbx + BOATENT.speed], 0
.carry:
    test    r14d, r14d
    jz      .next
    mov     rdi, rbx
    call    seat
.next:
    add     rbx, BOATENT_size
    inc     r13d
    cmp     r13d, MAX_BOATS
    jb      .boat
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; boats_raycast(rdi origin[3], rsi dir[3], xmm0 max) -> eax index of the nearest boat hit within max
; (or -1), xmm0 = its distance t (max on a miss). Box: [x +- half_w] x [y, y + 0.5] x [z +- half_w]:
; the hull, not the taller box a ridden boat collides with.
; Frame: lo[3] @0, hi[3] @16, best t @32.
boats_raycast:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 56
    mov     r12, rdi
    mov     r13, rsi
    movss   [rsp + 32], xmm0
    mov     r15d, -1
    lea     rbx, [boats]
    xor     r14d, r14d
.boat:
    cmp     dword [rbx + BOATENT.used], 0
    je      .next
    movss   xmm3, [rbx + BODY.half_w]
    movss   xmm0, [rbx + BODY.x]
    movaps  xmm1, xmm0
    subss   xmm0, xmm3
    addss   xmm1, xmm3
    movss   [rsp], xmm0
    movss   [rsp + 16], xmm1
    movss   xmm0, [rbx + BODY.y]
    movss   [rsp + 4], xmm0
    addss   xmm0, [c_height]
    movss   [rsp + 20], xmm0
    movss   xmm0, [rbx + BODY.z]
    movaps  xmm1, xmm0
    subss   xmm0, xmm3
    addss   xmm1, xmm3
    movss   [rsp + 8], xmm0
    movss   [rsp + 24], xmm1
    mov     rdi, r12
    mov     rsi, r13
    lea     rdx, [rsp]
    lea     rcx, [rsp + 16]
    movss   xmm0, [rsp + 32]            ; only a hit nearer than the best so far counts
    call    ray_aabb
    test    eax, eax
    jz      .next
    movss   [rsp + 32], xmm0
    mov     r15d, r14d
.next:
    add     rbx, BOATENT_size
    inc     r14d
    cmp     r14d, MAX_BOATS
    jb      .boat
    movss   xmm0, [rsp + 32]
    mov     eax, r15d
    add     rsp, 56
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; boats_mount(edi idx): the player rides boat idx (a used slot): he sits in it at once. A guest asks
; the host (net_boat_mount_out) and sits down when the answer comes (nw_on_boat_mount_ok runs this
; again with net_applying set); the host refuses a boat a guest rides.
boats_mount:
    cmp     edi, MAX_BOATS
    jae     .ret
    movzx   eax, byte [net_role]
    test    eax, eax
    jz      .local                      ; offline
    mov     ecx, edi
    cmp     eax, NET_ROLE_GUEST
    je      .guest
    lea     rax, [boat_rider]           ; the host: a boat a guest rides is taken
    cmp     byte [rax + rcx], 0
    jne     .ret
    jmp     .local
.guest:
    cmp     byte [net_applying], 0
    jne     .local                      ; the host said yes (nw_on_boat_mount_ok): sit down
    jmp     net_boat_mount_out          ; the host decides; the seat comes with its answer
.local:
    sub     rsp, 8
    mov     [rsp], edi
    call    boat_at
    cmp     dword [rax + BOATENT.used], 0
    je      .done
    mov     edi, [rsp]
    inc     edi
    mov     [boat_riding], edi
    mov     rdi, rax
    call    seat
.done:
    add     rsp, 8
.ret:
    ret

; boats_dismount(): the rider steps out: he stands 0.6 above the boat's bottom at its x and z, at
; rest, and nobody rides. Nothing happens when nobody rides. A guest tells the host first, with
; the boat's pose (net_boat_dismount_out).
boats_dismount:
    sub     rsp, 8
    mov     eax, [boat_riding]
    test    eax, eax
    jz      .ret
    dec     eax
    cmp     eax, MAX_BOATS
    jae     .clear
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .leave
    cmp     byte [net_applying], 0
    jne     .leave
    mov     [rsp], eax
    mov     edi, eax
    call    net_boat_dismount_out       ; the host learns where the boat was left and that its rider is out
    mov     eax, [rsp]
.leave:
    mov     edi, eax
    call    boat_at
    cmp     dword [rax + BOATENT.used], 0
    je      .clear
    mov     edx, [rax + BODY.x]
    mov     [player + BODY.x], edx
    mov     edx, [rax + BODY.z]
    mov     [player + BODY.z], edx
    movss   xmm0, [rax + BODY.y]
    addss   xmm0, [c_lift]
    movss   [player + BODY.y], xmm0
    xor     edx, edx
    mov     [player + BODY.vx], edx
    mov     [player + BODY.vy], edx
    mov     [player + BODY.vz], edx
    mov     [player + BODY.fall], edx
    mov     dword [player + BODY.on_ground], 0
.clear:
    mov     dword [boat_riding], 0
.ret:
    add     rsp, 8
    ret

; boats_break(edi idx): boat idx is gone; in Survival it leaves a BOAT item. A rider is let go
; where he sits. A guest asks the host to break it (net_boat_break_out); the host lets a guest who
; rode it go (MT_BOAT_MOUNT_OK with ok = 0) and clears boat_rider.
boats_break:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    cmp     edi, MAX_BOATS
    jae     .out
    mov     r12d, edi
    call    boat_at
    mov     rbx, rax
    cmp     dword [rbx + BOATENT.used], 0
    je      .out
    movzx   eax, byte [net_role]
    test    eax, eax
    jz      .release                    ; offline
    cmp     eax, NET_ROLE_GUEST
    jne     .host
    cmp     byte [net_applying], 0
    jne     .release
    mov     edi, r12d
    call    net_boat_break_out          ; a guest: the host breaks the boat and drops the item
    lea     eax, [r12 + 1]
    cmp     eax, [boat_riding]
    jne     .out
    mov     dword [boat_riding], 0      ; a rider is let go where he sits
    jmp     .out
.host:
    lea     rax, [boat_rider]           ; a guest who rode it is let go as well
    movzx   edi, byte [rax + r12]
    mov     byte [rax + r12], 0
    test    edi, edi
    jz      .release
    dec     edi                         ; his slot
    mov     byte [rsp], r12b
    mov     byte [rsp + 1], 0
    mov     esi, MT_BOAT_MOUNT_OK
    mov     rdx, rsp
    mov     ecx, 2
    mov     r8d, 1
    call    net_send_to                 ; "not yours any more"
.release:
    lea     eax, [r12 + 1]
    cmp     eax, [boat_riding]
    jne     .drop
    mov     dword [boat_riding], 0
.drop:
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .free
    mov     edi, BOAT
    mov     esi, 1
    xor     edx, edx
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    addss   xmm1, [c_pop]
    movss   xmm2, [rbx + BODY.z]
    call    drops_spawn
.free:
    mov     rdi, rbx
    mov     ecx, BOATENT_size
    xor     eax, eax
    rep     stosb
.out:
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; boats_save(rdi WORLDHDR*): the used boats' x, y, z, yaw packed into .boats, .boat_count of them;
; the rest of the records are zeroed
boats_save:
    lea     rsi, [boats]
    lea     rdx, [rdi + WORLDHDR.boats]
    xor     ecx, ecx
    mov     r8d, MAX_BOATS
.copy:
    cmp     dword [rsi + BOATENT.used], 0
    je      .next
    mov     eax, [rsi + BODY.x]
    mov     [rdx + BOATSAVE.x], eax
    mov     eax, [rsi + BODY.y]
    mov     [rdx + BOATSAVE.y], eax
    mov     eax, [rsi + BODY.z]
    mov     [rdx + BOATSAVE.z], eax
    mov     eax, [rsi + BODY.yaw]
    mov     [rdx + BOATSAVE.yaw], eax
    add     rdx, BOATSAVE_size
    inc     ecx
.next:
    add     rsi, BOATENT_size
    dec     r8d
    jnz     .copy
    mov     [rdi + WORLDHDR.boat_count], ecx
.zero:
    cmp     ecx, MAX_BOATS
    jae     .ret
    mov     qword [rdx], 0
    mov     qword [rdx + 8], 0
    add     rdx, BOATSAVE_size
    inc     ecx
    jmp     .zero
.ret:
    ret

; coord_ok(xmm0 v) -> eax 1 when v is a finite float with |v| < 65536
coord_ok:
    movss   xmm1, [c_abs_mask]
    andps   xmm1, xmm0
    movss   xmm2, [c_bound]
    xor     eax, eax
    ucomiss xmm2, xmm1                  ; false for NaN
    seta    al
    ret

; boats_load(rdi WORLDHDR*): the saved boats (boat_count, at most 16) become the boats; a record with
; a non-finite value, |x| or |z| >= 65536 or y outside 0..255 is skipped. The heading is brought
; into [0, 360). Nobody rides afterwards.
; r12 = header, r13d = records left, r14 = the record, rbx = the next free slot.
boats_load:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rdi
    call    boats_clear
    mov     r13d, [r12 + WORLDHDR.boat_count]
    cmp     r13d, MAX_BOATS
    jbe     .counted
    mov     r13d, MAX_BOATS
.counted:
    lea     r14, [r12 + WORLDHDR.boats]
    lea     rbx, [boats]
.rec:
    test    r13d, r13d
    jz      .done
    movss   xmm0, [r14 + BOATSAVE.x]
    call    coord_ok
    test    eax, eax
    jz      .skip
    movss   xmm0, [r14 + BOATSAVE.z]
    call    coord_ok
    test    eax, eax
    jz      .skip
    movss   xmm0, [r14 + BOATSAVE.yaw]
    call    coord_ok
    test    eax, eax
    jz      .skip
    movss   xmm0, [r14 + BOATSAVE.y]
    xorps   xmm1, xmm1
    ucomiss xmm0, xmm1
    jb      .skip                       ; below 0 (or NaN)
    ucomiss xmm0, [c_256]
    jae     .skip
    mov     rdi, rbx
    movss   xmm0, [c_half_w]
    movss   xmm1, [c_height]
    xorps   xmm2, xmm2
    call    body_init
    mov     eax, [r14 + BOATSAVE.x]
    mov     [rbx + BODY.x], eax
    mov     eax, [r14 + BOATSAVE.y]
    mov     [rbx + BODY.y], eax
    mov     eax, [r14 + BOATSAVE.z]
    mov     [rbx + BODY.z], eax
    movss   xmm0, [r14 + BOATSAVE.yaw]
    movaps  xmm1, xmm0
    divss   xmm1, [c_360]
    roundss xmm1, xmm1, 9
    mulss   xmm1, [c_360]
    subss   xmm0, xmm1                  ; yaw mod 360
    ucomiss xmm0, [c_360]
    jb      .yaw_ok
    xorps   xmm0, xmm0
.yaw_ok:
    movss   [rbx + BODY.yaw], xmm0
    mov     dword [rbx + BOATENT.used], 1
    mov     dword [rbx + BOATENT.speed], 0
    add     rbx, BOATENT_size
.skip:
    add     r14, BOATSAVE_size
    dec     r13d
    jmp     .rec
.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; boats_shift(edi dx, esi dz): the world origin moved by (dx, dz): every boat's x and z drop by them
boats_shift:
    cvtsi2ss xmm0, edi
    cvtsi2ss xmm1, esi
    lea     rax, [boats]
    mov     ecx, MAX_BOATS
.l:
    cmp     dword [rax + BOATENT.used], 0
    je      .next
    movss   xmm2, [rax + BODY.x]
    subss   xmm2, xmm0
    movss   [rax + BODY.x], xmm2
    movss   xmm2, [rax + BODY.z]
    subss   xmm2, xmm1
    movss   [rax + BODY.z], xmm2
.next:
    add     rax, BOATENT_size
    dec     ecx
    jnz     .l
    ret

; meshable(edi x, esi z) -> eax 1 when the column holding (x, z) and its eight neighbours are all lit
; (the columns the chunk renderer draws)
meshable:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, -16
.dz:
    mov     r14d, -16
.dx:
    lea     edi, [rbx + r14]
    lea     esi, [r12 + r13]
    call    world_column_ready
    test    eax, eax
    jz      .out                        ; eax = 0
    add     r14d, 16
    cmp     r14d, 16
    jle     .dx
    add     r13d, 16
    cmp     r13d, 16
    jle     .dz
    mov     eax, 1
.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; boats_render(): every boat in a drawable column as the skin model m_boat under glTranslatef(x, y, z) and
; glRotatef(-yaw, 0, 1, 0), lit by the cell above its bottom. Its floor covers the water surface, 0.25 above a
; floating boat's bottom. Called in the world pass after the mobs (atlas bound, alpha test on, modelview = world - eye).
; rbx = boat, r12d = slot counter.
boats_render:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    lea     rbx, [boats]
    xor     r12d, r12d
.boat:
    cmp     dword [rbx + BOATENT.used], 0
    je      .next
    movss   xmm0, [rbx + BODY.x]
    roundss xmm0, xmm0, 9
    cvttss2si edi, xmm0
    movss   xmm0, [rbx + BODY.z]
    roundss xmm0, xmm0, 9
    cvttss2si esi, xmm0
    call    meshable
    test    eax, eax
    jz      .next
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    addss   xmm1, [c_quarter]
    movss   xmm2, [rbx + BODY.z]
    call    light_bind_at
    call    glPushMatrix
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    call    glTranslatef
    xorps   xmm0, xmm0
    subss   xmm0, [rbx + BODY.yaw]      ; glRotatef(-yaw, 0, 1, 0)
    xorps   xmm1, xmm1
    movss   xmm2, [c_one]
    xorps   xmm3, xmm3
    call    glRotatef
    lea     rdi, [m_boat]
    xor     esi, esi
    xorps   xmm0, xmm0
    movss   xmm1, [c_one]
    movaps  xmm2, xmm1
    movaps  xmm3, xmm1
    call    skin_model_draw
    call    glPopMatrix
.next:
    add     rbx, BOATENT_size
    inc     r12d
    cmp     r12d, MAX_BOATS
    jb      .boat
    mov     edi, LIGHT_SKY_FULL         ; the entities after this one are lit by their own cells
    call    light_bind_index
    pop     r12
    pop     rbx
    pop     rbp
    ret
