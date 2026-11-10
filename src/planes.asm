; planes.asm - airplanes: put on the ground, taxied, flown by the pilot, broken into an item, kept in the
; world header (WORLDHDR.planes) and drawn as a handful of boxes. All coordinates are local. A plane is
; a BODY (y = bottom of its 3.0 x 1.2 x 3.0 box, yaw = heading) plus its speed along the heading, its
; pitch (degrees, + = nose up), its bank, its throttle and the streaming governor's current speed cap.
; The pilot steers with the view: the plane's heading and pitch follow the player's yaw and pitch (the
; mouse; A and D turn the view), W and S move the throttle. BODY.vy is the vertical speed.
; Seats: occ[] holds per seat (0 pilot, 1 left gunner, 2 right gunner, 3 tail gunner) the peer slot + 1 of who
; sits there; plane_riding / plane_seat say where the local player sits. Only the pilot flies the plane; every
; seated player is carried to his seat each step. In multiplayer the pilot's machine steps the plane and the
; host the pilotless ones (a guest steps only the plane he flies, the others are copies of the host's snapshots).
%include "common.inc"
%include "gl.inc"
default rel

global planes, plane_riding, plane_view
global planes_clear, planes_step, planes_render, planes_place, planes_raycast, planes_board
global planes_leave, planes_break, planes_save, planes_load, planes_shift, plane_view_cam
global plane_seat, plane_tgt, planes_sit, planes_free_seat, planes_crash, planes_mirror_step
global planes_free_peer, planes_free_guests, planes_hum

extern body_init, move_axis, sincos_deg
extern world_get, world_is_solid, world_column_ready, coord_ok, meshable
extern player, game_mode, hud_banner, drops_spawn, ray_aabb, raycast, survival_damage
extern block_tiles, render_box16, light_bind_at, light_bind_index
extern audio_play_local_at
extern net_role, net_self, net_applying, folk_tables, mob_parts_draw, net_hurt_send_direct
extern net_plane_place_out, net_plane_board_out, net_plane_leave_out, net_plane_break_out, net_plane_ok_out

%define PL_LOOK_COLS    4               ; columns sampled ahead of the heading, 16 blocks apart
%define PL_CRASH_DMG    12              ; HP the pilot loses in a crash (survival_damage, CAUSE_FALL)
%define PLANE_BOXES     8               ; the boxes of plane_model
%define HUM_STEPS       15              ; a 0.30 s engine chunk is played again every 0.25 s: the ends crossfade

section .rodata
align 4
c_dt:       dd 0.016666668              ; one fixed step, seconds
c_half_w:   dd 1.5                      ; the box: 3.0 wide and long ...
c_height:   dd 1.2                      ; ... 1.2 high
c_half:     dd 0.5                      ; the middle of a cell
c_center:   dd 0.6                      ; the model's centre above the plane's bottom
c_rider:    dd 0.15                     ; the pilot's feet above the plane's bottom (his eye: 1.77)
c_eye:      dd 1.62                     ; a standing body's eye above its feet
c_lift:     dd 0.6                      ; a leaving pilot lands this far above the plane
c_pop:      dd 0.3                      ; a broken plane's item appears this far above its bottom
c_probe:    dd 0.1                      ; the plane is in water or lava when the cell at y + 0.1 is
c_360:      dd 360.0
c_180:      dd 180.0
c_n180:     dd -180.0
c_one:      dd 1.0
c_90:       dd 90.0
c_quarter:  dd 0.25
c_16:       dd 16.0                     ; the streaming governor samples a column every 16 blocks
c_foot:     dd 2.0                      ; a step may not enter a column more than this far from the centre
c_256:      dd 256.0
c_prop_z:   dd -1.5                     ; the propeller hub, in front of the engine cowl
; ---- flight model (blocks, seconds, degrees)
c_hum_vol:  dd 0.4                      ; the engine's volume: 0.4 at rest ...
c_hum_span: dd 0.6                      ; ... + 0.6 x speed / top speed
c_hum_hi:   dd 14.0                     ; above this speed the flat-out chunk sounds
c_hum_near: dd 0.3333                   ; another plane's engine is heard from a third of its distance: 48 blocks, not 16
c_vmax:     dd 24.0                     ; PL_VMAX: top speed; the streaming governor lowers it while the terrain ahead is not loaded
c_takeoff:  dd 12.0                     ; PL_TAKEOFF: speed from which pitching up leaves the ground
c_stall:    dd 9.0                      ; PL_STALL: below it in the air there is no lift
c_acc:      dd 6.0                      ; PL_ACC: b/s^2 towards a higher target speed
c_brake:    dd 5.0                      ; PL_DRAG: b/s^2 towards a lower one
c_turn:     dd 60.0                     ; PL_TURN_RATE: degrees per second
c_pmax:     dd 35.0                     ; PL_PITCH_MAX
c_pmin:     dd -35.0
c_prate:    dd 45.0                     ; the nose follows the pilot's pitch at this many degrees per second
c_pdrop:    dd 40.0                     ; a stalled nose drops this fast ...
c_pstall:   dd -60.0                    ; ... down to here
c_ceiling:  dd 240.0                    ; PL_CEILING: no climbing above it
c_grav:     dd 20.0                     ; vy -= 20 dt without lift (and on the ground), at most 30 down
c_vfall:    dd -30.0
c_lift_k:   dd 0.15                     ; vy closes 15% of the gap to speed * sin(pitch) per step
c_tk_vy:    dd 3.0                      ; the push that leaves the ground
c_thr_rate: dd 0.5                      ; the throttle moves by half its range per second
c_roll_k:   dd 0.5                      ; bank = 0.5 x the turn still to make, ...
c_roll_max: dd 35.0                     ; ... within +-35 degrees, ...
c_roll_min: dd -35.0
c_roll_s:   dd 0.1                      ; ... approached by 10% per step
c_crash_vy: dd -9.0                     ; PL_CRASH_VY: touching down faster than this destroys the plane
c_crash_p:  dd -25.0                    ; PL_CRASH_PITCH: ... or with the nose lower than this
c_crash_v:  dd 14.0                     ; PL_CRASH_SPEED: ... or faster than this (also against a wall)
c_leave_v:  dd 1.0                      ; the pilot may leave a plane slower than this, on the ground
c_gov_dn:   dd 4.0                      ; governor: the cap falls 4 b/s^2 while a sampled column is not loaded ...
c_gov_up:   dd 2.0                      ; ... and recovers 2 b/s^2 otherwise
c_gov_lo:   dd 12.0                     ; PL_STALL + 3: never lower than this
c_gov_hint: dd 0.5                      ; the hint shows while the cap is more than this below PL_VMAX
c_prop_i:   dd 60.0                     ; propeller degrees per second: idle + 700 x throttle
c_prop_t:   dd 700.0
; ---- camera
c_cam_back: dd 7.0
c_cam_up:   dd 2.5
c_cam_pivot: dd 0.9                     ; the camera looks at the plane from here (above its bottom)
c_cam_gap:  dd 0.3                      ; kept this far from a block the camera ray meets
c_cam_min:  dd 0.4
c_cam_tilt: dd 14.0                     ; the camera looks this far below the plane's pitch: the plane sits in the middle
c_seat:     dd -0.4                     ; the pilot's feet in model space: the fuselage top is 0.35
c_pivot_g:  dd 0.75                     ; a gunner's camera looks at him from this far above his feet
c_follow:   dd 0.35                     ; a mirrored plane covers this much of the way to its target per step
c_snap2:    dd 36.0                     ; farther than 6 blocks from its target it jumps
; the seats in plane space (x right, z back; the nose is at -z): pilot, left gunner, right gunner, tail gunner
seat_x:     dd 0.0, -0.9, 0.9, 0.0
seat_z:     dd 0.0, -0.1, -0.1, 1.2
s_crash:    db "The plane crashed", 0
s_many:     db "Too many planes", 0
s_load:     db "Terrain loading", 0
; the boxes of the plane in model space (blocks, centre at the origin, nose towards -z):
; lo xyz, hi xyz, tile set (0 iron, 1 wool, 2 coal)
plane_model:
    dd -0.35, -0.30, -1.20,  0.35,  0.35,  1.10, 0      ; fuselage
    dd -0.30, -0.25, -1.45,  0.30,  0.30, -1.20, 2      ; engine cowl
    dd -1.50,  0.05, -0.60,  1.50,  0.17,  0.30, 1      ; wing
    dd -0.85,  0.05,  0.85,  0.85,  0.14,  1.40, 1      ; tailplane
    dd -0.05,  0.10,  0.85,  0.05,  0.70,  1.40, 1      ; fin
    dd -0.50, -0.60, -0.80, -0.30, -0.30, -0.50, 2      ; left wheel
    dd  0.30, -0.60, -0.80,  0.50, -0.30, -0.50, 2      ; right wheel
    dd -0.06, -0.50,  1.00,  0.06, -0.30,  1.15, 2      ; tail wheel
blade:      dd -0.70, -0.06, -0.04, 0.70, 0.06, 0.04    ; one propeller blade (two, crossed)
plane_blocks: db IRON_BLOCK, WOOL, COAL_BLOCK           ; the block each tile set takes its side tile from
plane_shades: dd 0.6, 0.6, 1.0, 0.5, 0.8, 0.8           ; +X -X +Y -Y +Z -Z

section .bss
alignb 16
planes:       resb MAX_PLANES * PLANEENT_size
plane_riding: resd 1                    ; 0, or the index + 1 of the plane the player flies
plane_seat:   resd 1                    ; the local player's seat while plane_riding != 0
plane_view:   resd 1                    ; 1 third person (the default on boarding), 0 cockpit
hum_cd:       resb MAX_PLANES               ; steps until the plane's engine chunk is played again
plane_hint:   resd 1                    ; 1 while "Terrain loading" has been shown for the current slow-down
plane_cam:    resb BODY_size            ; the third-person camera
plane_tgt:    resd MAX_PLANES * 4       ; a mirrored plane's target: x, y, z, yaw (local; guests)
plane_tiles:  resw 6 * 3                ; the six face tiles of each tile set

section .text

; planes_clear(): no planes, nobody flying
planes_clear:
    lea     rdi, [planes]
    mov     ecx, MAX_PLANES * PLANEENT_size
    xor     eax, eax
    rep     stosb
    mov     dword [plane_riding], 0
    mov     dword [plane_seat], 0
    mov     dword [plane_hint], 0
    ret

; plane_at(edi idx) -> rax the PLANEENT of slot idx (idx < MAX_PLANES)
plane_at:
    imul    eax, edi, PLANEENT_size
    lea     rdx, [planes]
    add     rax, rdx
    ret

; plane_index(rdi plane) -> eax its slot
plane_index:
    lea     rax, [planes]
    sub     rdi, rax
    mov     eax, edi
    xor     edx, edx
    mov     ecx, PLANEENT_size
    div     ecx
    ret

; seat_pos(rdi plane, esi seat) -> xmm0 x, xmm1 z: where that seat of the plane is (its offset in plane space,
; turned by the heading)
seat_pos:
    push    rbx
    sub     rsp, 16
    mov     rbx, rdi
    mov     [rsp], esi
    movss   xmm0, [rdi + BODY.yaw]
    call    sincos_deg
    mov     eax, [rsp]
    lea     rdx, [seat_x]
    movss   xmm2, [rdx + rax * 4]
    lea     rdx, [seat_z]
    movss   xmm3, [rdx + rax * 4]
    movaps  xmm4, xmm2
    mulss   xmm4, xmm1                  ; x cos
    movaps  xmm5, xmm3
    mulss   xmm5, xmm0                  ; z sin
    subss   xmm4, xmm5
    addss   xmm4, [rbx + BODY.x]
    mulss   xmm2, xmm0                  ; x sin
    mulss   xmm3, xmm1                  ; z cos
    addss   xmm2, xmm3
    addss   xmm2, [rbx + BODY.z]
    movaps  xmm0, xmm4
    movaps  xmm1, xmm2
    add     rsp, 16
    pop     rbx
    ret

; seat(rdi plane, esi seat): the player sits in that seat: its x and z, feet 0.15 above the plane's bottom, at rest
seat:
    push    rbx
    mov     rbx, rdi
    call    seat_pos
    movss   [player + BODY.x], xmm0
    movss   [player + BODY.z], xmm1
    movss   xmm0, [rbx + BODY.y]
    addss   xmm0, [c_rider]
    movss   [player + BODY.y], xmm0
    xor     eax, eax
    mov     [player + BODY.vx], eax
    mov     [player + BODY.vy], eax
    mov     [player + BODY.vz], eax
    mov     [player + BODY.fall], eax
    mov     dword [player + BODY.on_ground], 1
    pop     rbx
    ret

; wrap360(xmm0 degrees) -> xmm0 in [0, 360); clobbers xmm1
wrap360:
    xorps   xmm1, xmm1
.up:
    ucomiss xmm1, xmm0
    jbe     .down
    addss   xmm0, [c_360]
    jmp     .up
.down:
    ucomiss xmm0, [c_360]
    jb      .ret
    subss   xmm0, [c_360]
    jmp     .down
.ret:
    ret

; wrap180(xmm0 degrees) -> xmm0 in [-180, 180)
wrap180:
.up:
    ucomiss xmm0, [c_n180]
    jp      .ret
    jae     .down
    addss   xmm0, [c_360]
    jmp     .up
.down:
    ucomiss xmm0, [c_180]
    jb      .ret
    subss   xmm0, [c_360]
    jmp     .down
.ret:
    ret

; approach(xmm0 cur, xmm1 target, xmm2 max step >= 0) -> xmm0 cur moved towards target by at most the step;
; clobbers xmm1, xmm3
approach:
    subss   xmm1, xmm0
    minss   xmm1, xmm2
    xorps   xmm3, xmm3
    subss   xmm3, xmm2
    maxss   xmm1, xmm3
    addss   xmm0, xmm1
    ret

; planes_place(rdi RAYHIT*) -> eax 1 when a plane was put on the ground. The ray must have hit the top face
; of a block (the cell in front of it lies directly above the block); the 3 x 3 cells around that cell, at
; its level and the one above, must be free and loaded (a plane overhanging a ledge is fine). It stands
; centred on the cell, bottom on the block, heading = the player's yaw. A full table says "Too many
; planes. A guest asks the host (net_plane_place_out) and says 1.
; r12 = RAYHIT, r13d = dz, r14d = dx, r15d = dy, rbx = the new plane.
planes_place:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r12, rdi
    mov     eax, [r12 + RAYHIT.py]
    sub     eax, [r12 + RAYHIT.by]
    cmp     eax, 1
    jne     .none                       ; not the top of the block
    mov     eax, [r12 + RAYHIT.px]
    cmp     eax, [r12 + RAYHIT.bx]
    jne     .none
    mov     eax, [r12 + RAYHIT.pz]
    cmp     eax, [r12 + RAYHIT.bz]
    jne     .none
    mov     edi, [r12 + RAYHIT.bx]
    mov     esi, [r12 + RAYHIT.by]
    mov     edx, [r12 + RAYHIT.bz]
    call    world_is_solid
    test    eax, eax
    jz      .none                       ; nothing to stand on
    mov     r13d, -1
.dz:
    mov     r14d, -1
.dx:
    xor     r15d, r15d
.dy:
    mov     edi, [r12 + RAYHIT.px]
    add     edi, r14d
    mov     esi, [r12 + RAYHIT.py]
    add     esi, r15d
    mov     edx, [r12 + RAYHIT.pz]
    add     edx, r13d
    call    world_is_solid              ; (an unloaded column counts as solid)
    test    eax, eax
    jnz     .none
    inc     r15d
    cmp     r15d, 1
    jbe     .dy
    inc     r14d
    cmp     r14d, 1
    jle     .dx
    inc     r13d
    cmp     r13d, 1
    jle     .dz
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .local
    cmp     byte [net_applying], 0
    jne     .local
    mov     rdi, r12                    ; a guest: the host puts the plane down
    call    net_plane_place_out
    mov     eax, 1
    jmp     .out
.local:
    lea     rbx, [planes]
    xor     r13d, r13d
.slot:
    cmp     dword [rbx + PLANEENT.used], 0
    je      .take
    add     rbx, PLANEENT_size
    inc     r13d
    cmp     r13d, MAX_PLANES
    jb      .slot
    cmp     byte [net_applying], 0
    jne     .none                       ; a guest's request on the host: no banner (nw_on_plane_place gives the item back)
    lea     rdi, [s_many]
    mov     esi, RGBA(255, 150, 90, 255)
    call    hud_banner
    jmp     .none
.take:
    mov     rdi, rbx
    mov     ecx, PLANEENT_size
    xor     eax, eax
    rep     stosb
    mov     rdi, rbx
    movss   xmm0, [c_half_w]
    movss   xmm1, [c_height]
    xorps   xmm2, xmm2
    call    body_init
    cvtsi2ss xmm0, dword [r12 + RAYHIT.px]
    addss   xmm0, [c_half]
    movss   [rbx + BODY.x], xmm0
    cvtsi2ss xmm0, dword [r12 + RAYHIT.py]
    movss   [rbx + BODY.y], xmm0
    cvtsi2ss xmm0, dword [r12 + RAYHIT.pz]
    addss   xmm0, [c_half]
    movss   [rbx + BODY.z], xmm0
    mov     eax, [player + BODY.yaw]
    mov     [rbx + BODY.yaw], eax
    mov     eax, [c_vmax]
    mov     [rbx + PLANEENT.vmax], eax
    mov     dword [rbx + PLANEENT.used], 1
    mov     eax, 1
    jmp     .out
.none:
    xor     eax, eax
.out:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; plane_footprint_ready(rdi plane, xmm0 dx, xmm1 dz) -> eax 1 when the columns under the four corners of a
; box 2.0 around the plane's centre moved by (dx, dz) are all loaded
plane_footprint_ready:
    push    rbx
    push    r12
    push    r13
    sub     rsp, 16
    mov     rbx, rdi
    movss   xmm2, [rbx + BODY.x]
    addss   xmm2, xmm0
    movss   [rsp], xmm2
    movss   xmm2, [rbx + BODY.z]
    addss   xmm2, xmm1
    movss   [rsp + 4], xmm2
    xor     r12d, r12d
.corner:
    mov     eax, r12d
    and     eax, 1
    lea     eax, [rax * 2 - 1]
    cvtsi2ss xmm0, eax
    mulss   xmm0, [c_foot]
    addss   xmm0, [rsp]
    roundss xmm0, xmm0, 9
    cvttss2si edi, xmm0
    mov     eax, r12d
    shr     eax, 1
    lea     eax, [rax * 2 - 1]
    cvtsi2ss xmm0, eax
    mulss   xmm0, [c_foot]
    addss   xmm0, [rsp + 4]
    roundss xmm0, xmm0, 9
    cvttss2si esi, xmm0
    call    world_column_ready
    test    eax, eax
    jz      .out                        ; eax = 0
    inc     r12d
    cmp     r12d, 4
    jb      .corner
    mov     eax, 1
.out:
    add     rsp, 16
    pop     r13
    pop     r12
    pop     rbx
    ret

; plane_governor(rdi plane): the streaming governor. Samples the columns 16, 32 ... blocks ahead along the
; heading; while one of them is not loaded the plane's speed cap falls 4 b/s^2 (never below 12), otherwise
; it recovers 2 b/s^2 up to the top speed.
plane_governor:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    mov     rbx, rdi
    movss   xmm0, [rbx + BODY.yaw]
    call    sincos_deg
    movss   [rsp], xmm0                 ; sin yaw
    movss   [rsp + 4], xmm1             ; cos yaw
    mov     r12d, 1
.col:
    cvtsi2ss xmm2, r12d
    mulss   xmm2, [c_16]
    movss   xmm0, [rsp]
    mulss   xmm0, xmm2
    addss   xmm0, [rbx + BODY.x]
    roundss xmm0, xmm0, 9
    cvttss2si edi, xmm0
    movss   xmm1, [rsp + 4]
    mulss   xmm1, xmm2
    movss   xmm3, [rbx + BODY.z]
    subss   xmm3, xmm1
    roundss xmm3, xmm3, 9
    cvttss2si esi, xmm3
    call    world_column_ready
    test    eax, eax
    jz      .slow
    inc     r12d
    cmp     r12d, PL_LOOK_COLS
    jbe     .col
    movss   xmm0, [rbx + PLANEENT.vmax]
    movss   xmm1, [c_gov_up]
    mulss   xmm1, [c_dt]
    addss   xmm0, xmm1
    minss   xmm0, [c_vmax]
    jmp     .store
.slow:
    movss   xmm0, [rbx + PLANEENT.vmax]
    movss   xmm1, [c_gov_dn]
    mulss   xmm1, [c_dt]
    subss   xmm0, xmm1
    maxss   xmm0, [c_gov_lo]
.store:
    movss   [rbx + PLANEENT.vmax], xmm0
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; plane_crash(rdi plane): the plane is destroyed (it drops nothing) and every occupant takes 12 damage. The host
; hurts each guest in it (net_hurt_send_direct) and tells him he is out (net_plane_ok_out); the local player, when
; he sits in it, is put down at the wreck, says so and takes the damage; a guest who flew it tells the host
; (net_plane_break_out, crash), which does the same for the others.
; rbx = plane, r12d = its slot, r13d = seat counter.
plane_crash:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rdi
    call    plane_index
    mov     r12d, eax
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .own
    xor     r13d, r13d
.seat:
    mov     eax, [rbx + r13 * 4 + PLANEENT.occ]
    test    eax, eax
    jz      .seat_next
    dec     eax
    movzx   ecx, byte [net_self]
    cmp     eax, ecx
    je      .seat_next                  ; the host's own seat: below
    mov     [rsp], eax
    mov     edi, eax
    mov     esi, PL_CRASH_DMG
    mov     edx, CAUSE_FALL
    mov     ecx, 255                    ; no mob, no status
    mov     r8d, 255
    xor     r9d, r9d
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.z]
    xorps   xmm2, xmm2
    xorps   xmm3, xmm3
    call    net_hurt_send_direct
    mov     edi, [rsp]
    mov     esi, r12d
    xor     edx, edx
    xor     ecx, ecx
    call    net_plane_ok_out            ; not his any more
.seat_next:
    inc     r13d
    cmp     r13d, PLANE_SEATS
    jb      .seat
.own:
    lea     eax, [r12 + 1]
    cmp     eax, [plane_riding]
    jne     .tell
    mov     dword [plane_riding], 0
    mov     eax, [rbx + BODY.x]
    mov     [player + BODY.x], eax
    mov     eax, [rbx + BODY.z]
    mov     [player + BODY.z], eax
    movss   xmm0, [rbx + BODY.y]
    addss   xmm0, [c_lift]
    movss   [player + BODY.y], xmm0
    xor     eax, eax
    mov     [player + BODY.vx], eax
    mov     [player + BODY.vy], eax
    mov     [player + BODY.vz], eax
    mov     [player + BODY.fall], eax
    mov     dword [player + BODY.on_ground], 0
    lea     rdi, [s_crash]
    mov     esi, RGBA(255, 90, 90, 255)
    call    hud_banner
    mov     edi, PL_CRASH_DMG
    mov     esi, CAUSE_FALL
    call    survival_damage
.tell:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .free
    mov     edi, r12d
    mov     esi, 1
    call    net_plane_break_out         ; the host destroys it for the others
.free:
    mov     rdi, rbx
    mov     ecx, PLANEENT_size
    xor     eax, eax
    rep     stosb
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; planes_crash(edi idx): plane idx (a used slot) is destroyed as plane_crash does it (the host, on a guest pilot's report)
planes_crash:
    cmp     edi, MAX_PLANES
    jae     .ret
    sub     rsp, 8
    call    plane_at
    cmp     dword [rax + PLANEENT.used], 0
    je      .done
    mov     rdi, rax
    call    plane_crash
.done:
    add     rsp, 8
.ret:
    ret

; plane_update(rdi plane, rsi INPUT*, edx 1 when the player flies it): one fixed step of one plane.
; A plane whose column is not loaded, or whose next step would enter a column that is not, stands still.
; Water or lava at the plane's bottom destroys it. The pilot: the player's pitch is held within +-35, A and D
; turn his yaw by 60 degrees per second, W and S move the throttle by half a range per second; the heading
; follows his yaw at 60 degrees per second (on the ground only as fast as the plane rolls: speed / 4) and the
; bank follows the turn left to make. The speed goes towards throttle x cap (+6, -5 b/s^2). On the ground the
; nose settles level and pitching up at 12 b/s or more leaves it; in the air above 9 b/s the nose follows the
; pilot's pitch and vy closes 15% per step of the gap to speed x sin pitch; below 9 b/s the nose drops 40
; degrees per second down to -60 and vy -= 20 dt (at most 30 down). The plane moves speed x cos pitch along
; the heading by x, z and then vy by y (move_axis). A wall at more than 14 b/s destroys it, a slower one
; stops it. Touching down after being airborne destroys it when vy was below -9, the nose below -25 degrees
; or the speed above 14, otherwise the plane is on the ground again. Sneaking on the ground slower than
; 1 b/s lets the pilot out; otherwise he sits in the plane.
; rbx = plane, r12 = INPUT*, r13d = flown. Frame: vy before the move @0, sin yaw @8, cos yaw @12, cell x @16,
; cell z @20, turn left to make @24, commanded pitch @32, dx @36, dz @40.
plane_update:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 56
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13d, edx
    movss   xmm0, [rbx + BODY.x]
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    mov     [rsp + 16], eax
    movss   xmm0, [rbx + BODY.z]
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    mov     [rsp + 20], eax
    mov     edi, [rsp + 16]
    mov     esi, [rsp + 20]
    call    world_column_ready
    test    eax, eax
    jz      .out                        ; its column is not loaded: it stands still
    movss   xmm0, [rbx + BODY.y]
    addss   xmm0, [c_probe]
    roundss xmm0, xmm0, 9
    cvttss2si esi, xmm0
    mov     edi, [rsp + 16]
    mov     edx, [rsp + 20]
    call    world_get
    cmp     eax, WATER
    je      .crash
    cmp     eax, LAVA
    je      .crash
    ; ---- the pilot's controls
    xorps   xmm5, xmm5                  ; commanded pitch (nose up): 0 without a pilot
    xorps   xmm0, xmm0
    test    r13d, r13d
    jz      .controls_done
    movss   xmm0, [player + BODY.pitch] ; the view's pitch (+ = down) stays within +-35
    minss   xmm0, [c_pmax]
    maxss   xmm0, [c_pmin]
    movss   [player + BODY.pitch], xmm0
    xorps   xmm5, xmm5
    subss   xmm5, xmm0
    cvtsi2ss xmm0, dword [r12 + INPUT.strafe]
    mulss   xmm0, [c_turn]
    mulss   xmm0, [c_dt]
    addss   xmm0, [player + BODY.yaw]
    call    wrap360
    movss   [player + BODY.yaw], xmm0
    cvtsi2ss xmm0, dword [r12 + INPUT.fwd]
    mulss   xmm0, [c_thr_rate]
    mulss   xmm0, [c_dt]
    addss   xmm0, [rbx + PLANEENT.throttle]
    movss   xmm1, [c_one]
    minss   xmm0, xmm1
    xorps   xmm1, xmm1
    maxss   xmm0, xmm1
    movss   [rbx + PLANEENT.throttle], xmm0
    movss   xmm0, [player + BODY.yaw]
    subss   xmm0, [rbx + BODY.yaw]
    call    wrap180                     ; the turn left to make
.controls_done:
    movss   [rsp + 32], xmm5
    test    r13d, r13d
    jnz     .have_turn
    xorps   xmm0, xmm0
    mov     dword [rbx + PLANEENT.throttle], 0
.have_turn:
    movss   [rsp + 24], xmm0
    ; ---- heading and bank
    movss   xmm1, [c_turn]
    mulss   xmm1, [c_dt]                ; the most it may turn this step
    cmp     dword [rbx + PLANEENT.air], 0
    jne     .turn_lim
    movss   xmm2, [rbx + PLANEENT.speed]
    mulss   xmm2, [c_quarter]
    minss   xmm2, [c_one]
    xorps   xmm3, xmm3
    maxss   xmm2, xmm3
    mulss   xmm1, xmm2
.turn_lim:
    minss   xmm0, xmm1
    xorps   xmm2, xmm2
    subss   xmm2, xmm1
    maxss   xmm0, xmm2
    addss   xmm0, [rbx + BODY.yaw]
    call    wrap360
    movss   [rbx + BODY.yaw], xmm0
    movss   xmm0, [rsp + 24]
    mulss   xmm0, [c_roll_k]
    minss   xmm0, [c_roll_max]
    maxss   xmm0, [c_roll_min]
    cmp     dword [rbx + PLANEENT.air], 0
    jne     .bank
    xorps   xmm0, xmm0                  ; no bank while rolling
.bank:
    subss   xmm0, [rbx + PLANEENT.roll]
    mulss   xmm0, [c_roll_s]
    addss   xmm0, [rbx + PLANEENT.roll]
    movss   [rbx + PLANEENT.roll], xmm0
    ; ---- speed
    mov     rdi, rbx
    call    plane_governor
    movss   xmm1, [rbx + PLANEENT.throttle]
    mulss   xmm1, [rbx + PLANEENT.vmax]
    movss   xmm0, [rbx + PLANEENT.speed]
    subss   xmm1, xmm0
    movss   xmm3, [c_acc]
    mulss   xmm3, [c_dt]
    minss   xmm1, xmm3
    movss   xmm3, [c_brake]
    mulss   xmm3, [c_dt]
    xorps   xmm4, xmm4
    subss   xmm4, xmm3
    maxss   xmm1, xmm4
    addss   xmm0, xmm1
    movss   [rbx + PLANEENT.speed], xmm0
    test    r13d, r13d
    jz      .no_hint
    movss   xmm0, [c_vmax]
    subss   xmm0, [rbx + PLANEENT.vmax]
    ucomiss xmm0, [c_gov_hint]
    ja      .slowed
    mov     dword [plane_hint], 0
    jmp     .no_hint
.slowed:
    cmp     dword [plane_hint], 0
    jne     .no_hint
    mov     dword [plane_hint], 1
    lea     rdi, [s_load]
    mov     esi, RGBA(255, 220, 120, 255)
    call    hud_banner
.no_hint:
    ; ---- propeller
    movss   xmm0, [rbx + PLANEENT.throttle]
    mulss   xmm0, [c_prop_t]
    addss   xmm0, [c_prop_i]
    mulss   xmm0, [c_dt]
    addss   xmm0, [rbx + PLANEENT.prop]
    call    wrap360
    movss   [rbx + PLANEENT.prop], xmm0
    ; ---- vertical: on the ground, and in the air with and without lift
    cmp     dword [rbx + PLANEENT.air], 0
    jne     .flight
    movss   xmm0, [rbx + PLANEENT.pitch]
    xorps   xmm1, xmm1
    movss   xmm2, [c_prate]
    mulss   xmm2, [c_dt]
    call    approach
    movss   [rbx + PLANEENT.pitch], xmm0
    movss   xmm0, [rbx + PLANEENT.speed]
    ucomiss xmm0, [c_takeoff]
    jb      .gravity
    xorps   xmm1, xmm1
    ucomiss xmm1, [rsp + 32]
    jae     .gravity                    ; the pilot is not pitching up
    mov     dword [rbx + PLANEENT.air], 1
    mov     eax, [c_tk_vy]
    mov     [rbx + BODY.vy], eax
    jmp     .motion
.gravity:
    movss   xmm0, [rbx + BODY.vy]
    movss   xmm1, [c_grav]
    mulss   xmm1, [c_dt]
    subss   xmm0, xmm1
    maxss   xmm0, [c_vfall]
    movss   [rbx + BODY.vy], xmm0
    jmp     .motion
.flight:
    movss   xmm0, [rbx + PLANEENT.speed]
    ucomiss xmm0, [c_stall]
    jb      .stalled
    movss   xmm0, [rbx + PLANEENT.pitch]
    movss   xmm1, [rsp + 32]
    movss   xmm2, [c_prate]
    mulss   xmm2, [c_dt]
    call    approach
    movss   [rbx + PLANEENT.pitch], xmm0
    call    sincos_deg                  ; xmm0 = sin pitch
    mulss   xmm0, [rbx + PLANEENT.speed]
    subss   xmm0, [rbx + BODY.vy]
    mulss   xmm0, [c_lift_k]
    addss   xmm0, [rbx + BODY.vy]
    movss   [rbx + BODY.vy], xmm0
    jmp     .ceiling
.stalled:
    movss   xmm0, [rbx + PLANEENT.pitch]
    movss   xmm1, [c_pdrop]
    mulss   xmm1, [c_dt]
    subss   xmm0, xmm1
    maxss   xmm0, [c_pstall]
    movss   [rbx + PLANEENT.pitch], xmm0
    movss   xmm0, [rbx + BODY.vy]
    movss   xmm1, [c_grav]
    mulss   xmm1, [c_dt]
    subss   xmm0, xmm1
    maxss   xmm0, [c_vfall]
    movss   [rbx + BODY.vy], xmm0
.ceiling:
    movss   xmm0, [rbx + BODY.y]
    ucomiss xmm0, [c_ceiling]
    jb      .motion
    movss   xmm0, [rbx + BODY.vy]
    xorps   xmm1, xmm1
    minss   xmm0, xmm1
    movss   [rbx + BODY.vy], xmm0
.motion:
    movss   xmm0, [rbx + BODY.yaw]
    call    sincos_deg
    movss   [rsp + 8], xmm0
    movss   [rsp + 12], xmm1
    movss   xmm6, [c_one]               ; cos pitch: the horizontal share of the speed, in the air
    cmp     dword [rbx + PLANEENT.air], 0
    je      .share
    movss   xmm0, [rbx + PLANEENT.pitch]
    call    sincos_deg
    movaps  xmm6, xmm1
.share:
    movss   xmm2, [rbx + PLANEENT.speed]
    mulss   xmm2, xmm6
    mulss   xmm2, [c_dt]                ; the distance this step
    movss   xmm0, [rsp + 8]
    mulss   xmm0, xmm2
    movss   [rsp + 36], xmm0            ; dx = sin * distance
    movss   xmm1, [rsp + 12]
    mulss   xmm1, xmm2
    xorps   xmm3, xmm3
    subss   xmm3, xmm1
    movss   [rsp + 40], xmm3            ; dz = -cos * distance
    mov     rdi, rbx
    movss   xmm0, [rsp + 36]
    movss   xmm1, [rsp + 40]
    call    plane_footprint_ready
    test    eax, eax
    jz      .out                        ; the next step would enter unloaded terrain: it stands still
    mov     dword [rbx + BODY.blocked], 0
    mov     dword [rbx + BODY.on_ground], 0
    mov     eax, [rbx + BODY.vy]
    mov     [rsp], eax
    movss   xmm0, [rsp + 36]
    mov     rdi, rbx
    xor     esi, esi
    call    move_axis
    movss   xmm0, [rsp + 40]
    mov     rdi, rbx
    mov     esi, 2
    call    move_axis
    movss   xmm0, [rbx + BODY.vy]
    mulss   xmm0, [c_dt]
    mov     rdi, rbx
    mov     esi, 1
    call    move_axis
    cmp     dword [rbx + BODY.blocked], 0
    je      .no_wall
    movss   xmm0, [rbx + PLANEENT.speed]
    ucomiss xmm0, [c_crash_v]
    ja      .crash
    mov     dword [rbx + PLANEENT.speed], 0
.no_wall:
    cmp     dword [rbx + BODY.on_ground], 0
    jne     .touch
    mov     dword [rbx + PLANEENT.air], 1   ; rolled off an edge
    jmp     .carry
.touch:
    cmp     dword [rbx + PLANEENT.air], 0
    je      .carry
    movss   xmm0, [rsp]
    ucomiss xmm0, [c_crash_vy]
    jb      .crash
    movss   xmm0, [rbx + PLANEENT.pitch]
    ucomiss xmm0, [c_crash_p]
    jb      .crash
    movss   xmm0, [rbx + PLANEENT.speed]
    ucomiss xmm0, [c_crash_v]
    ja      .crash
    mov     dword [rbx + PLANEENT.air], 0   ; a safe landing
.carry:
    test    r13d, r13d
    jz      .out
    cmp     dword [r12 + INPUT.down], 0
    je      .out
    cmp     dword [rbx + PLANEENT.air], 0
    jne     .out
    movss   xmm0, [rbx + PLANEENT.speed]
    ucomiss xmm0, [c_leave_v]
    jae     .out
    call    planes_leave
    jmp     .out
.crash:
    mov     rdi, rbx
    call    plane_crash
.out:
    add     rsp, 56
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; planes_step(rdi INPUT*): one fixed step of the planes this machine steps (plane_update; the one the local
; player pilots is flown with the input): offline all, on the host those no guest pilots, on a guest only the
; one he flies. Then the seated local player is carried to his seat, and a gunner who sneaks steps out.
planes_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rdi
    mov     eax, [plane_riding]
    test    eax, eax
    jz      .begin
    dec     eax
    cmp     eax, MAX_PLANES
    jae     .stale
    imul    ecx, eax, PLANEENT_size
    lea     rdx, [planes]
    cmp     dword [rdx + rcx + PLANEENT.used], 0
    jne     .begin
.stale:
    mov     dword [plane_riding], 0     ; the plane is gone: nobody sits in it
.begin:
    lea     rbx, [planes]
    xor     r14d, r14d
.plane:
    cmp     dword [rbx + PLANEENT.used], 0
    je      .next
    lea     eax, [r14 + 1]
    xor     edx, edx
    cmp     eax, [plane_riding]
    jne     .role
    cmp     dword [plane_seat], 0
    sete    dl                          ; the player pilots this one
.role:
    movzx   eax, byte [net_role]
    test    eax, eax
    jz      .step
    cmp     eax, NET_ROLE_GUEST
    jne     .host
    test    edx, edx
    jz      .next                       ; a guest steps only the plane he flies
    jmp     .step
.host:
    cmp     dword [rbx + PLANEENT.occ], 1
    ja      .next                       ; a guest pilots it: his pose messages move it
.step:
    mov     rdi, rbx
    mov     rsi, r12
    call    plane_update
.next:
    add     rbx, PLANEENT_size
    inc     r14d
    cmp     r14d, MAX_PLANES
    jb      .plane
    mov     eax, [plane_riding]
    test    eax, eax
    jz      .out
    dec     eax
    mov     edi, eax
    call    plane_at
    mov     rbx, rax
    mov     esi, [plane_seat]
    test    esi, esi
    jz      .sit
    cmp     dword [r12 + INPUT.down], 0
    je      .sit
    call    planes_leave                ; a gunner steps out where he sits, in the air too
    jmp     .out
.sit:
    mov     rdi, rbx
    call    seat
.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; planes_raycast(rdi origin[3], rsi dir[3], xmm0 max) -> eax index of the nearest plane hit within max (or
; -1), xmm0 = its distance t (max on a miss). Box: [x +- 1.5] x [y, y + 1.2] x [z +- 1.5].
; Frame: lo[3] @0, hi[3] @16, best t @32.
planes_raycast:
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
    lea     rbx, [planes]
    xor     r14d, r14d
.plane:
    cmp     dword [rbx + PLANEENT.used], 0
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
    addss   xmm0, [rbx + BODY.height]
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
    add     rbx, PLANEENT_size
    inc     r14d
    cmp     r14d, MAX_PLANES
    jb      .plane
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

; planes_free_seat(rdi plane) -> eax its first free seat (0 pilot first, then the gunners), or -1 when it is full
planes_free_seat:
    xor     eax, eax
.l:
    cmp     dword [rdi + rax * 4 + PLANEENT.occ], 0
    je      .ret
    inc     eax
    cmp     eax, PLANE_SEATS
    jb      .l
    mov     eax, -1
.ret:
    ret

; planes_sit(edi idx, esi seat): the local player sits in that seat of plane idx (a used slot): the pilot in
; third person, a gunner in his turret; he is placed at the seat at once
planes_sit:
    cmp     edi, MAX_PLANES
    jae     .ret
    push    rbx
    push    r12
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, esi
    call    plane_at
    cmp     dword [rax + PLANEENT.used], 0
    je      .done
    lea     edx, [rbx + 1]
    mov     [plane_riding], edx
    mov     [plane_seat], r12d
    xor     edx, edx
    test    r12d, r12d
    sete    dl
    mov     [plane_view], edx
    mov     dword [plane_hint], 0
    movzx   edx, byte [net_self]
    inc     edx
    mov     [rax + r12 * 4 + PLANEENT.occ], edx
    mov     rdi, rax
    mov     esi, r12d
    call    seat
.done:
    add     rsp, 8
    pop     r12
    pop     rbx
.ret:
    ret

; planes_board(edi idx): the player boards plane idx (a used slot): the pilot's seat when nobody sits in it,
; else the first free gunner seat; a full plane refuses. A guest asks the host (net_plane_board_out) and sits
; down when the answer comes (nw_on_plane_board_ok runs planes_sit).
planes_board:
    cmp     edi, MAX_PLANES
    jae     .ret
    push    rbx
    mov     ebx, edi
    call    plane_at
    cmp     dword [rax + PLANEENT.used], 0
    je      .out
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .seat
    mov     edi, ebx
    call    net_plane_board_out
    jmp     .out
.seat:
    mov     rdi, rax
    call    planes_free_seat
    test    eax, eax
    js      .out                        ; full
    mov     edi, ebx
    mov     esi, eax
    call    planes_sit
.out:
    pop     rbx
.ret:
    ret

; planes_leave(): the local player steps out where he sits (the seat's x and z, 0.6 above the plane's bottom), at
; rest, and his seat is free. Nothing happens when he sits in no plane. A guest tells the host first, with the
; plane's pose (net_plane_leave_out).
; rbx = the plane, r12d = its slot.
planes_leave:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     eax, [plane_riding]
    test    eax, eax
    jz      .out
    dec     eax
    cmp     eax, MAX_PLANES
    jae     .clear
    mov     r12d, eax
    mov     edi, eax
    call    plane_at
    mov     rbx, rax
    cmp     dword [rbx + PLANEENT.used], 0
    je      .clear
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .place
    mov     edi, r12d
    call    net_plane_leave_out
.place:
    mov     rdi, rbx
    mov     esi, [plane_seat]
    call    seat_pos
    movss   [player + BODY.x], xmm0
    movss   [player + BODY.z], xmm1
    movss   xmm0, [rbx + BODY.y]
    addss   xmm0, [c_lift]
    movss   [player + BODY.y], xmm0
    xor     eax, eax
    mov     [player + BODY.vx], eax
    mov     [player + BODY.vy], eax
    mov     [player + BODY.vz], eax
    mov     [player + BODY.fall], eax
    mov     dword [player + BODY.on_ground], 0
    mov     ecx, [plane_seat]
    movzx   edx, byte [net_self]
    inc     edx
    cmp     [rbx + rcx * 4 + PLANEENT.occ], edx
    jne     .clear
    mov     dword [rbx + rcx * 4 + PLANEENT.occ], 0
.clear:
    mov     dword [plane_riding], 0
.out:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; planes_break(edi idx): plane idx is gone; in Survival it leaves a PLANE item. The player who sits in it is let
; go where he sits. A guest asks the host to break it (net_plane_break_out); the host tells every guest who sat
; in it (PLANE_BOARD_OK with ok = 0).
; rbx = the plane, r12d = its slot, r13d = seat counter.
planes_break:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    cmp     edi, MAX_PLANES
    jae     .out
    mov     r12d, edi
    call    plane_at
    mov     rbx, rax
    cmp     dword [rbx + PLANEENT.used], 0
    je      .out
    movzx   eax, byte [net_role]
    test    eax, eax
    jz      .release                    ; offline
    cmp     eax, NET_ROLE_GUEST
    jne     .host
    mov     edi, r12d
    xor     esi, esi
    call    net_plane_break_out         ; a guest: the host breaks it and drops the item
    lea     eax, [r12 + 1]
    cmp     eax, [plane_riding]
    jne     .out
    mov     dword [plane_riding], 0
    jmp     .out
.host:
    xor     r13d, r13d
.seat:
    mov     eax, [rbx + r13 * 4 + PLANEENT.occ]
    test    eax, eax
    jz      .seat_next
    dec     eax
    movzx   ecx, byte [net_self]
    cmp     eax, ecx
    je      .seat_next
    mov     edi, eax
    mov     esi, r12d
    xor     edx, edx
    xor     ecx, ecx
    call    net_plane_ok_out            ; "not yours any more"
.seat_next:
    inc     r13d
    cmp     r13d, PLANE_SEATS
    jb      .seat
.release:
    lea     eax, [r12 + 1]
    cmp     eax, [plane_riding]
    jne     .drop
    mov     dword [plane_riding], 0
.drop:
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .free
    mov     edi, PLANE
    mov     esi, 1
    xor     edx, edx
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    addss   xmm1, [c_pop]
    movss   xmm2, [rbx + BODY.z]
    call    drops_spawn
.free:
    mov     rdi, rbx
    mov     ecx, PLANEENT_size
    xor     eax, eax
    rep     stosb
.out:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; planes_save(rdi WORLDHDR*): the used planes' x, y, z, yaw packed into .planes, .plane_count of them;
; the rest of the records are zeroed
planes_save:
    lea     rsi, [planes]
    lea     rdx, [rdi + WORLDHDR.planes]
    xor     ecx, ecx
    mov     r8d, MAX_PLANES
.copy:
    cmp     dword [rsi + PLANEENT.used], 0
    je      .next
    mov     eax, [rsi + BODY.x]
    mov     [rdx + PLANESAVE.x], eax
    mov     eax, [rsi + BODY.y]
    mov     [rdx + PLANESAVE.y], eax
    mov     eax, [rsi + BODY.z]
    mov     [rdx + PLANESAVE.z], eax
    mov     eax, [rsi + BODY.yaw]
    mov     [rdx + PLANESAVE.yaw], eax
    add     rdx, PLANESAVE_size
    inc     ecx
.next:
    add     rsi, PLANEENT_size
    dec     r8d
    jnz     .copy
    mov     [rdi + WORLDHDR.plane_count], ecx
.zero:
    cmp     ecx, MAX_PLANES
    jae     .ret
    mov     qword [rdx], 0
    mov     qword [rdx + 8], 0
    add     rdx, PLANESAVE_size
    inc     ecx
    jmp     .zero
.ret:
    ret

; planes_load(rdi WORLDHDR*): the saved planes (plane_count, at most 4) become the planes; a record with a
; non-finite value, |x| or |z| >= 65536 or y outside 0..255 is skipped. The heading is brought into
; [0, 360). They stand still on the ground (or fall to it); nobody flies afterwards.
; r12 = header, r13d = records left, r14 = the record, rbx = the next free slot.
planes_load:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rdi
    call    planes_clear
    mov     r13d, [r12 + WORLDHDR.plane_count]
    cmp     r13d, MAX_PLANES
    jbe     .counted
    mov     r13d, MAX_PLANES
.counted:
    lea     r14, [r12 + WORLDHDR.planes]
    lea     rbx, [planes]
.rec:
    test    r13d, r13d
    jz      .done
    movss   xmm0, [r14 + PLANESAVE.x]
    call    coord_ok
    test    eax, eax
    jz      .skip
    movss   xmm0, [r14 + PLANESAVE.z]
    call    coord_ok
    test    eax, eax
    jz      .skip
    movss   xmm0, [r14 + PLANESAVE.yaw]
    call    coord_ok
    test    eax, eax
    jz      .skip
    movss   xmm0, [r14 + PLANESAVE.y]
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
    mov     eax, [r14 + PLANESAVE.x]
    mov     [rbx + BODY.x], eax
    mov     eax, [r14 + PLANESAVE.y]
    mov     [rbx + BODY.y], eax
    mov     eax, [r14 + PLANESAVE.z]
    mov     [rbx + BODY.z], eax
    movss   xmm0, [r14 + PLANESAVE.yaw]
    call    wrap360
    movss   [rbx + BODY.yaw], xmm0
    mov     eax, [c_vmax]
    mov     [rbx + PLANEENT.vmax], eax
    mov     dword [rbx + PLANEENT.used], 1
    add     rbx, PLANEENT_size
.skip:
    add     r14, PLANESAVE_size
    dec     r13d
    jmp     .rec
.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; planes_shift(edi dx, esi dz): the world origin moved by (dx, dz): every plane's x and z drop by them
planes_shift:
    cvtsi2ss xmm0, edi
    cvtsi2ss xmm1, esi
    lea     rax, [planes]
    mov     ecx, MAX_PLANES
.l:
    cmp     dword [rax + PLANEENT.used], 0
    je      .next
    movss   xmm2, [rax + BODY.x]
    subss   xmm2, xmm0
    movss   [rax + BODY.x], xmm2
    movss   xmm2, [rax + BODY.z]
    subss   xmm2, xmm1
    movss   [rax + BODY.z], xmm2
.next:
    add     rax, PLANEENT_size
    dec     ecx
    jnz     .l
    lea     rax, [plane_tgt]            ; and the targets of the mirrored planes
    mov     ecx, MAX_PLANES
.t:
    movss   xmm2, [rax]
    subss   xmm2, xmm0
    movss   [rax], xmm2
    movss   xmm2, [rax + 8]
    subss   xmm2, xmm1
    movss   [rax + 8], xmm2
    add     rax, 16
    dec     ecx
    jnz     .t
    ret

; plane_view_cam() -> rax the BODY render_world draws from: the player, unless he sits in a plane in third
; person; then a copy of him 7 blocks behind the plane along its heading and pitch (a gunner: behind his own
; view direction, about him) and 2.5 above, pulled in to 0.3 before any block the way there meets, looking
; along that direction. (The real eye stays the player's: targeting and shooting use it.)
; rbx = the plane, r12 = the camera. Frame: pivot[3] @0, offset[3] @16, hit RAYHIT @32 (24 bytes), sin yaw @56,
; cos yaw @60, sin pitch @64, cos pitch @68, length @72, the heading @80, the pitch @84 (degrees, + = up).
plane_view_cam:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 96
    mov     ecx, [plane_riding]
    test    ecx, ecx
    jz      .player
    cmp     dword [plane_view], 0
    je      .player
    dec     ecx
    cmp     ecx, MAX_PLANES
    jae     .player
    mov     edi, ecx
    call    plane_at
    mov     rbx, rax
    cmp     dword [rbx + PLANEENT.used], 0
    je      .player
    lea     r12, [plane_cam]
    mov     rdi, r12
    lea     rsi, [player]
    mov     ecx, BODY_size
    rep     movsb
    cmp     dword [plane_seat], 0
    jne     .gunner
    mov     eax, [rbx + BODY.yaw]       ; the pilot: the camera follows the plane
    mov     [rsp + 80], eax
    mov     eax, [rbx + PLANEENT.pitch]
    mov     [rsp + 84], eax
    movss   xmm0, [rbx + BODY.x]
    movss   [rsp], xmm0
    movss   xmm0, [rbx + BODY.y]
    addss   xmm0, [c_cam_pivot]
    movss   [rsp + 4], xmm0
    movss   xmm0, [rbx + BODY.z]
    movss   [rsp + 8], xmm0
    jmp     .aim
.gunner:                                ; a gunner: the camera follows his view, about him
    mov     eax, [player + BODY.yaw]
    mov     [rsp + 80], eax
    xorps   xmm1, xmm1
    subss   xmm1, [player + BODY.pitch] ; (his pitch is + = down)
    movss   [rsp + 84], xmm1
    movss   xmm0, [player + BODY.x]
    movss   [rsp], xmm0
    movss   xmm0, [player + BODY.y]
    addss   xmm0, [c_pivot_g]
    movss   [rsp + 4], xmm0
    movss   xmm0, [player + BODY.z]
    movss   [rsp + 8], xmm0
.aim:
    movss   xmm0, [rsp + 80]
    call    sincos_deg
    movss   [rsp + 56], xmm0
    movss   [rsp + 60], xmm1
    movss   xmm0, [rsp + 84]
    call    sincos_deg
    movss   [rsp + 64], xmm0
    movss   [rsp + 68], xmm1
    ; offset = -forward * 7 + up * 2.5, forward = (sin yaw cos p, sin p, -cos yaw cos p)
    movss   xmm2, [c_cam_back]
    movss   xmm0, [rsp + 56]
    mulss   xmm0, [rsp + 68]
    mulss   xmm0, xmm2
    xorps   xmm3, xmm3
    subss   xmm3, xmm0
    movss   [rsp + 16], xmm3
    movss   xmm0, [rsp + 64]
    mulss   xmm0, xmm2
    xorps   xmm3, xmm3
    subss   xmm3, xmm0
    addss   xmm3, [c_cam_up]
    movss   [rsp + 20], xmm3
    movss   xmm0, [rsp + 60]
    mulss   xmm0, [rsp + 68]
    mulss   xmm0, xmm2
    movss   [rsp + 24], xmm0
    movss   xmm0, [rsp + 16]
    mulss   xmm0, xmm0
    movss   xmm1, [rsp + 20]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    movss   xmm1, [rsp + 24]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    sqrtss  xmm0, xmm0
    movss   [rsp + 72], xmm0
    movss   xmm1, [rsp + 16]            ; the ray direction: the offset, normalised
    divss   xmm1, xmm0
    movss   [rsp + 16], xmm1
    movss   xmm1, [rsp + 20]
    divss   xmm1, xmm0
    movss   [rsp + 20], xmm1
    movss   xmm1, [rsp + 24]
    divss   xmm1, xmm0
    movss   [rsp + 24], xmm1
    lea     rdi, [rsp]
    lea     rsi, [rsp + 16]
    lea     rdx, [rsp + 32]
    movss   xmm0, [rsp + 72]            ; the camera ray is as long as the offset
    call    raycast                     ; xmm0 = the distance to the block hit, or the length
    test    eax, eax
    jz      .placed                     ; xmm0 = the length: free all the way
    subss   xmm0, [c_cam_gap]
    maxss   xmm0, [c_cam_min]
.placed:
    movss   xmm1, [rsp + 16]
    mulss   xmm1, xmm0
    addss   xmm1, [rsp]
    movss   [r12 + BODY.x], xmm1
    movss   xmm1, [rsp + 20]
    mulss   xmm1, xmm0
    addss   xmm1, [rsp + 4]
    subss   xmm1, [c_eye]
    movss   [r12 + BODY.y], xmm1
    movss   xmm1, [rsp + 24]
    mulss   xmm1, xmm0
    addss   xmm1, [rsp + 8]
    movss   [r12 + BODY.z], xmm1
    mov     eax, [rsp + 80]
    mov     [r12 + BODY.yaw], eax
    xorps   xmm0, xmm0
    subss   xmm0, [rsp + 84]
    addss   xmm0, [c_cam_tilt]
    movss   [r12 + BODY.pitch], xmm0
    mov     rax, r12
    jmp     .out
.player:
    lea     rax, [player]
.out:
    add     rsp, 96
    pop     r12
    pop     rbx
    pop     rbp
    ret

; planes_render(): every plane in a drawable column as the nine boxes of plane_model and the two crossed
; propeller blades, under glTranslatef(x, y + 0.6, z), glRotatef(-yaw, 0, 1, 0), glRotatef(pitch, 1, 0, 0) and
; glRotatef(-bank, 0, 0, 1), lit by the cell at its centre. The plane the player flies is not drawn from
; the cockpit. Called in the world pass after the boats (atlas bound, alpha test on, modelview = world - eye).
; rbx = plane, r12d = slot counter, r13d = box counter.
planes_render:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    lea     rsi, [plane_blocks]
    lea     rdi, [plane_tiles]
    lea     rdx, [block_tiles]
    xor     ecx, ecx
.set:                                   ; the side tile of each block, on all six faces
    movzx   eax, byte [rsi + rcx]
    lea     eax, [rax + rax * 2 + 1]
    movzx   eax, word [rdx + rax * 2]
    mov     r8d, 6
.face:
    mov     [rdi], ax
    add     rdi, 2
    dec     r8d
    jnz     .face
    inc     ecx
    cmp     ecx, 3
    jb      .set
    lea     rbx, [planes]
    xor     r12d, r12d
.plane:
    cmp     dword [rbx + PLANEENT.used], 0
    je      .next
    lea     eax, [r12 + 1]
    cmp     eax, [plane_riding]
    jne     .draw
    cmp     dword [plane_seat], 0
    jne     .draw                       ; a gunner sees the plane around him
    cmp     dword [plane_view], 0
    je      .next                       ; the cockpit: the plane is around the eye
.draw:
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
    addss   xmm1, [c_center]
    movss   xmm2, [rbx + BODY.z]
    call    light_bind_at
    call    glPushMatrix
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    addss   xmm1, [c_center]
    movss   xmm2, [rbx + BODY.z]
    call    glTranslatef
    xorps   xmm0, xmm0
    subss   xmm0, [rbx + BODY.yaw]
    xorps   xmm1, xmm1
    movss   xmm2, [c_one]
    xorps   xmm3, xmm3
    call    glRotatef
    movss   xmm0, [rbx + PLANEENT.pitch]
    movss   xmm1, [c_one]
    xorps   xmm2, xmm2
    xorps   xmm3, xmm3
    call    glRotatef
    xorps   xmm0, xmm0
    subss   xmm0, [rbx + PLANEENT.roll]
    xorps   xmm1, xmm1
    xorps   xmm2, xmm2
    movss   xmm3, [c_one]
    call    glRotatef
    xor     r13d, r13d
.box:
    imul    eax, r13d, 28
    lea     rdi, [plane_model]
    add     rdi, rax
    mov     eax, [rdi + 24]
    imul    eax, eax, 12
    lea     rsi, [plane_tiles]
    add     rsi, rax
    lea     rdx, [plane_shades]
    movss   xmm0, [c_one]
    movaps  xmm1, xmm0
    movaps  xmm2, xmm0
    call    render_box16
    inc     r13d
    cmp     r13d, PLANE_BOXES
    jb      .box
    lea     eax, [r12 + 1]              ; the pilot: torso and head above the fuselage (third person only, see above)
    cmp     eax, [plane_riding]
    jne     .no_pilot
    cmp     dword [plane_view], 0
    je      .no_pilot                   ; (first person: no avatar around the eye)
    call    glPushMatrix
    mov     eax, [plane_seat]
    lea     rcx, [seat_x]
    movss   xmm0, [rcx + rax * 4]
    movss   xmm1, [c_seat]
    lea     rcx, [seat_z]
    movss   xmm2, [rcx + rax * 4]
    call    glTranslatef
    lea     rax, [folk_tables]
    mov     r14, [rax + FAC_VILLAGERS * 8]
    lea     rdi, [r14 + FOLK_BODY * FOLK_PART_SIZE]
    xor     esi, esi
    mov     edx, 1
    xorps   xmm0, xmm0
    movss   xmm1, [c_one]
    movaps  xmm2, xmm1
    movaps  xmm3, xmm1
    call    mob_parts_draw
    lea     rdi, [r14 + FOLK_HEAD * FOLK_PART_SIZE]
    xor     esi, esi
    mov     edx, 1
    xorps   xmm0, xmm0
    movss   xmm1, [c_one]
    movaps  xmm2, xmm1
    movaps  xmm3, xmm1
    call    mob_parts_draw
    call    glPopMatrix
.no_pilot:
    xorps   xmm0, xmm0                  ; the propeller: two blades crossed, spinning about the nose axis
    xorps   xmm1, xmm1
    movss   xmm2, [c_prop_z]
    call    glTranslatef
    movss   xmm0, [rbx + PLANEENT.prop]
    xorps   xmm1, xmm1
    xorps   xmm2, xmm2
    movss   xmm3, [c_one]
    call    glRotatef
    xor     r13d, r13d
.blade:
    lea     rdi, [blade]
    lea     rsi, [plane_tiles + 2 * 12]
    lea     rdx, [plane_shades]
    movss   xmm0, [c_one]
    movaps  xmm1, xmm0
    movaps  xmm2, xmm0
    call    render_box16
    movss   xmm0, [c_90]
    xorps   xmm1, xmm1
    xorps   xmm2, xmm2
    movss   xmm3, [c_one]
    call    glRotatef
    inc     r13d
    cmp     r13d, 2
    jb      .blade
    call    glPopMatrix
.next:
    add     rbx, PLANEENT_size
    inc     r12d
    cmp     r12d, MAX_PLANES
    jb      .plane
    mov     edi, LIGHT_SKY_FULL         ; the entities after this one are lit by their own cells
    call    light_bind_index
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; planes_mirror_step(): once per step on a guest (nm_guest_step): every plane copy but the one he flies goes on
; towards its snapshot target (plane_tgt): the target moves along the heading by speed x cos(pitch) (and by
; the vertical speed in the air) between snapshots, the copy covers 35% of the way (over 6 blocks off it
; jumps), turns the shortest way and spins its propeller with the speed.
; rbx = plane, r12d = slot, r13 = its target. Frame: sin yaw @0, cos yaw @4.
planes_mirror_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 24
    lea     rbx, [planes]
    xor     r12d, r12d
.plane:
    cmp     dword [rbx + PLANEENT.used], 0
    je      .next
    lea     eax, [r12 + 1]
    cmp     eax, [plane_riding]
    jne     .mirror
    cmp     dword [plane_seat], 0
    je      .next                       ; the one he flies
.mirror:
    mov     eax, r12d
    shl     eax, 4
    lea     r13, [plane_tgt]
    add     r13, rax
    movss   xmm0, [r13 + 12]
    call    sincos_deg
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   xmm0, [rbx + PLANEENT.pitch]
    call    sincos_deg                  ; xmm1 = cos pitch
    movss   xmm2, [rbx + PLANEENT.speed]
    mulss   xmm2, xmm1
    mulss   xmm2, [c_dt]                ; the distance this step
    movss   xmm0, [rsp]
    mulss   xmm0, xmm2
    addss   xmm0, [r13]
    movss   [r13], xmm0
    movss   xmm0, [rsp + 4]
    mulss   xmm0, xmm2
    movss   xmm1, [r13 + 8]
    subss   xmm1, xmm0
    movss   [r13 + 8], xmm1
    cmp     dword [rbx + PLANEENT.air], 0
    je      .follow
    movss   xmm0, [rbx + BODY.vy]
    mulss   xmm0, [c_dt]
    addss   xmm0, [r13 + 4]
    movss   [r13 + 4], xmm0
.follow:
    movss   xmm2, [c_follow]
    movss   xmm0, [r13]
    subss   xmm0, [rbx + BODY.x]
    movss   xmm1, [r13 + 8]
    subss   xmm1, [rbx + BODY.z]
    movss   xmm3, [r13 + 4]
    subss   xmm3, [rbx + BODY.y]
    movaps  xmm4, xmm0
    mulss   xmm4, xmm4
    movaps  xmm5, xmm1
    mulss   xmm5, xmm5
    addss   xmm4, xmm5
    comiss  xmm4, [c_snap2]
    jbe     .glide
    mov     eax, [r13]                  ; too far off: it jumps
    mov     [rbx + BODY.x], eax
    mov     eax, [r13 + 4]
    mov     [rbx + BODY.y], eax
    mov     eax, [r13 + 8]
    mov     [rbx + BODY.z], eax
    jmp     .yaw
.glide:
    mulss   xmm0, xmm2
    addss   xmm0, [rbx + BODY.x]
    movss   [rbx + BODY.x], xmm0
    mulss   xmm1, xmm2
    addss   xmm1, [rbx + BODY.z]
    movss   [rbx + BODY.z], xmm1
    mulss   xmm3, xmm2
    addss   xmm3, [rbx + BODY.y]
    movss   [rbx + BODY.y], xmm3
.yaw:
    movss   xmm0, [r13 + 12]
    subss   xmm0, [rbx + BODY.yaw]
    call    wrap180
    mulss   xmm0, [c_follow]
    addss   xmm0, [rbx + BODY.yaw]
    call    wrap360
    movss   [rbx + BODY.yaw], xmm0
    movss   xmm0, [rbx + PLANEENT.speed]
    divss   xmm0, [c_vmax]
    minss   xmm0, [c_one]
    xorps   xmm1, xmm1
    maxss   xmm0, xmm1
    mulss   xmm0, [c_prop_t]
    addss   xmm0, [c_prop_i]
    mulss   xmm0, [c_dt]
    addss   xmm0, [rbx + PLANEENT.prop]
    call    wrap360
    movss   [rbx + PLANEENT.prop], xmm0
.next:
    add     rbx, PLANEENT_size
    inc     r12d
    cmp     r12d, MAX_PLANES
    jb      .plane
    add     rsp, 24
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; planes_free_peer(edi slot): the guest in that slot sits in no plane any more (it left or timed out); a plane
; it flew is pilotless, the host's to step
planes_free_peer:
    lea     edx, [rdi + 1]
    lea     rax, [planes]
    mov     ecx, MAX_PLANES
.plane:
    xor     esi, esi
.seat:
    cmp     [rax + rsi * 4 + PLANEENT.occ], edx
    jne     .seat_next
    mov     dword [rax + rsi * 4 + PLANEENT.occ], 0
.seat_next:
    inc     esi
    cmp     esi, PLANE_SEATS
    jb      .seat
    add     rax, PLANEENT_size
    dec     ecx
    jnz     .plane
    ret

; planes_free_guests(): no guest sits in any plane (the host closed multiplayer); the host's own seat stays
planes_free_guests:
    lea     rax, [planes]
    mov     ecx, MAX_PLANES
.plane:
    xor     esi, esi
.seat:
    cmp     dword [rax + rsi * 4 + PLANEENT.occ], 1
    jbe     .seat_next
    mov     dword [rax + rsi * 4 + PLANEENT.occ], 0
.seat_next:
    inc     esi
    cmp     esi, PLANE_SEATS
    jb      .seat
    add     rax, PLANEENT_size
    dec     ecx
    jnz     .plane
    ret

; planes_hum(): once a step, on every machine: each plane with a pilot (occ[0]) sounds its engine from where it is, a chunk
; every 15 steps (the idle chunk, the flat-out one above 14 b/s), louder as the speed rises. The sound is made locally:
; every machine hears the planes it sees, so nothing is sent. A plane nobody pilots is silent (it glides) and starts at
; once when a pilot sits down.
; rbx = plane, r12d = slot counter
planes_hum:
    push    rbx
    push    r12
    push    r13
    lea     rbx, [planes]
    xor     r12d, r12d
.plane:
    lea     r13, [hum_cd]
    add     r13, r12
    cmp     dword [rbx + PLANEENT.used], 0
    je      .quiet
    cmp     dword [rbx + PLANEENT.occ], 0
    je      .quiet
    cmp     byte [r13], 0
    je      .play
    dec     byte [r13]
    jmp     .next
.play:
    mov     byte [r13], HUM_STEPS - 1
    movss   xmm3, [rbx + PLANEENT.speed]
    divss   xmm3, [c_vmax]
    minss   xmm3, [c_one]
    mulss   xmm3, [c_hum_span]
    addss   xmm3, [c_hum_vol]
    mov     edi, SND_ENGINE
    mov     eax, SND_ENGINE_HIGH
    movss   xmm0, [rbx + PLANEENT.speed]
    ucomiss xmm0, [c_hum_hi]
    cmova   edi, eax
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    addss   xmm1, [c_center]
    movss   xmm2, [rbx + BODY.z]
    lea     eax, [r12 + 1]
    cmp     eax, [plane_riding]
    je      .go                         ; the plane he sits in: at its own place, full volume
    movss   xmm4, [player + BODY.x]     ; another: its place pulled towards the listener (the pan stays)
    subss   xmm0, xmm4
    mulss   xmm0, [c_hum_near]
    addss   xmm0, xmm4
    movss   xmm4, [player + BODY.y]
    addss   xmm4, [c_eye]
    subss   xmm1, xmm4
    mulss   xmm1, [c_hum_near]
    addss   xmm1, xmm4
    movss   xmm4, [player + BODY.z]
    subss   xmm2, xmm4
    mulss   xmm2, [c_hum_near]
    addss   xmm2, xmm4
.go:
    call    audio_play_local_at
    jmp     .next
.quiet:
    mov     byte [r13], 0
.next:
    add     rbx, PLANEENT_size
    inc     r12d
    cmp     r12d, MAX_PLANES
    jb      .plane
    pop     r13
    pop     r12
    pop     rbx
    ret
