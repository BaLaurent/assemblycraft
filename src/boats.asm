; boats.asm - boats: put on water, floating, driven by the rider, broken into an item, kept in the
; world header (WORLDHDR.boats) and drawn as five plank boxes. All coordinates are local. A boat is
; a BODY (y = bottom of its 1.2 x 0.5 x 1.2 box, yaw = heading) plus its speed along the heading.
%include "common.inc"
%include "gl.inc"
default rel

global boats, boat_riding
global boats_clear, boats_step, boats_render, boats_place, boats_raycast, boats_mount
global boats_dismount, boats_break, boats_save, boats_load, boats_shift

extern body_init, move_axis, sincos_deg
extern world_get, world_is_solid, world_column_ready
extern player, game_mode, hud_banner, drops_spawn, ray_aabb
extern block_tiles, render_box, light_bind_at, light_bind_index

section .rodata
align 4
c_dt:       dd 0.016666668              ; one fixed step, seconds
c_half_w:   dd 0.6                      ; the box: 1.2 wide ...
c_height:   dd 0.5                      ; ... 0.5 high
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
c_bound:    dd 65536.0                  ; saved coordinates must lie inside +-this
c_256:      dd 256.0
c_abs_mask: dd 0x7FFFFFFF
s_many:     db "Too many boats", 0
; the five boxes of the hull in model space (blocks, bow towards -z): lo xyz, hi xyz. The floor is
; 5/16 thick so it covers the water surface (14/16 of the cell, 0.25 above a floating boat's bottom)
hull:
    dd -0.55, 0.0, -0.85, 0.55, 0.3125, 0.85        ; floor
    dd -0.55, 0.3125, -0.85, -0.45, 0.5, 0.85       ; left wall
    dd 0.45, 0.3125, -0.85, 0.55, 0.5, 0.85         ; right wall
    dd -0.45, 0.3125, -0.85, 0.45, 0.5, -0.75       ; bow
    dd -0.45, 0.3125, 0.75, 0.45, 0.5, 0.85         ; stern
hull_shades: dd 0.6, 0.6, 1.0, 0.5, 0.8, 0.8        ; +X -X +Y -Y +Z -Z

section .bss
alignb 16
boats:       resb MAX_BOATS * BOATENT_size
boat_riding: resd 1                     ; 0, or the index + 1 of the boat the player rides
plank_tiles: resb 8                     ; the PLANKS tile on all six faces

section .text

; boats_clear(): no boats, nobody riding
boats_clear:
    lea     rdi, [boats]
    mov     ecx, MAX_BOATS * BOATENT_size
    xor     eax, eax
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
; WATER cell whose cell above is not solid takes the boat: centred in the cell, bottom 0.625 over
; the cell's floor, heading = the player's yaw. A full boat table says "Too many boats" (0). The
; caller consumes the item in Survival.
; r13 = eye, r14 = dir, r15d = cells left, rbx = the new boat, r12d = slot counter.
; Frame: cell[3] @0, step[3] @16, tmax[3] @32, tdelta[3] @48.
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
    lea     rbx, [boats]
    xor     r12d, r12d
.slot:
    cmp     dword [rbx + BOATENT.used], 0
    je      .take
    add     rbx, BOATENT_size
    inc     r12d
    cmp     r12d, MAX_BOATS
    jb      .slot
    lea     rdi, [s_many]
    mov     esi, RGBA(255, 150, 90, 255)
    call    hud_banner
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
    movss   [rbx + BODY.x], xmm0
    cvtsi2ss xmm0, dword [rsp + 4]
    addss   xmm0, [c_rest]
    movss   [rbx + BODY.y], xmm0
    cvtsi2ss xmm0, dword [rsp + 8]
    addss   xmm0, [c_half]
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

; boats_step(rdi INPUT*): one fixed step of every boat whose column is lit (the others are frozen).
; Floating (the cell at y + 0.3 or at y is WATER): vy = clamp((highest water cell within one of
; floor(y), + 0.625 - y) * 4, -2, 2). Otherwise vy -= 20 dt (at least -20) and the speed shrinks by
; 10%. The ridden boat (boat_riding): INPUT.fwd +1 aims at 5 blocks/s and -1 at -1.5 with 4 b/s^2,
; no key brakes at 2 b/s^2; INPUT.strafe turns at 90 degrees per second (+1 = clockwise from above,
; as a mouse moved right); INPUT.down dismounts. An empty boat brakes at 2 b/s^2. The boat moves
; along (sin yaw, -cos yaw) by speed * dt on x, then z, then y (move_axis); a horizontal block
; stops it dead. The rider is carried: the player takes the boat's x and z, feet at its bottom +
; 0.25, at rest and "on the ground".
; rbx = boat, r12 = INPUT*, r13d = index, r14d = ridden, r15d = floating.
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
; (or -1), xmm0 = its distance t (max on a miss). Box: [x +- half_w] x [y, y + height] x [z +- half_w].
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

; boats_mount(edi idx): the player rides boat idx (a used slot): he sits in it at once
boats_mount:
    cmp     edi, MAX_BOATS
    jae     .ret
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
; rest, and nobody rides. Nothing happens when nobody rides.
boats_dismount:
    sub     rsp, 8
    mov     eax, [boat_riding]
    test    eax, eax
    jz      .ret
    dec     eax
    cmp     eax, MAX_BOATS
    jae     .clear
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
; where he sits.
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

; boats_render(): every boat in a drawable column as five plank boxes (floor, two walls, bow,
; stern) under glTranslatef(x, y, z) and glRotatef(-yaw, 0, 1, 0), lit by the cell above its bottom.
; Called in the world pass after the mobs (atlas bound, alpha test on, modelview = world - eye).
; rbx = boat, r12d = slot counter, r13d = box counter.
boats_render:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    movzx   eax, byte [block_tiles + PLANKS * 3 + 1]
    mov     rcx, 0x0101010101010101
    imul    rax, rcx
    mov     [plank_tiles], rax
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
    xor     r13d, r13d
.box:
    imul    eax, r13d, 24
    lea     rdi, [hull]
    add     rdi, rax
    lea     rsi, [plank_tiles]
    lea     rdx, [hull_shades]
    movss   xmm0, [c_one]
    movaps  xmm1, xmm0
    movaps  xmm2, xmm0
    call    render_box
    inc     r13d
    cmp     r13d, 5
    jb      .box
    call    glPopMatrix
.next:
    add     rbx, BOATENT_size
    inc     r12d
    cmp     r12d, MAX_BOATS
    jb      .boat
    mov     edi, LIGHT_SKY_FULL         ; the entities after this one are lit by their own cells
    call    light_bind_index
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
