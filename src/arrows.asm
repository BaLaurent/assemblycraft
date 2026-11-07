; arrows.asm - projectiles: arrows, bullets and rockets. Spawn, flight, hits on mobs and the
; player, arrows sticking in blocks and the player picking his own back up, rockets
; exploding on impact, drawing. Projectiles are not saved with the world.
%include "common.inc"
%include "gl.inc"
default rel

global arrows, arrows_clear, arrows_spawn, arrows_step, arrows_render

extern player, raycast, ray_aabb, mobs_raycast, mob_hurt, mob_shot, explode_at
extern survival_damage, surv, game_mode, inv_add
extern audio_play, audio_play_at
extern render_box, atan2_deg

%define STUCK_MOB_STEPS 60              ; a skeleton's arrow stays in the block 1 s
%define STUCK_OWN_STEPS 1200            ; the player's arrow stays 20 s

; arrows_step frame (rsp-relative)
%define S_SEG   0                       ; float seg[3]: this step's displacement
%define S_DIR   12                      ; float dir[3]: unit heading
%define S_HIT   24                      ; RAYHIT (24 bytes)
%define S_LO    48                      ; float lo[3] / hi[3] of the box under test
%define S_HI    60
%define S_LEN   72                      ; float |seg|
%define S_TMAX  76                      ; float nearest block distance, or len without a hit
%define S_T     80                      ; float distance of the hit that wins
%define S_HP    84                      ; float hit point[3]
%define S_H     96                      ; float unit horizontal heading (x, z)
%define S_IDX   104                     ; int mob index hit
%define S_BLK   108                     ; int 1 when raycast found a block
%define S_FRAME 112

section .rodata
align 4
c_dt:        dd 0.016666668
c_gravity:   dd 0.33333334              ; arrows: 20 blocks/s^2 per step
c_tiny:      dd 0.000001
c_hdir_min:  dd 0.0001
c_one:       dd 1.0
c_embed:     dd 0.05                    ; an arrow stops this far short of the surface it hit
c_out_y:     dd -8.0
c_pick_r2:   dd 1.0                     ; horizontal pickup radius^2
c_pick_hi:   dd 2.0                     ; arrow y - player y window
c_pop_vol:   dd 0.35
c_hit_vol:   dd 0.8
c_stick_vol: dd 0.5
c_kb:        dd 4.0                     ; knockback speed of an arrow hit on the player
c_half_w:    dd 0.3                     ; player box
c_height:    dd 1.8
f_one:       dd 1.0
c_bullet_vol: dd 0.4
c_rocket_r:  dd 3.0                     ; rocket blast radius
; flying steps before a projectile is gone (a rocket explodes then), by kind
max_age:     dd 600, 120, 300

; arrow model: shaft, tip, fletching (box lo xyz, hi xyz); the tip points to -Z
arrow_shaft: dd -0.03, -0.03, -0.25,  0.03, 0.03, 0.25
arrow_tip:   dd -0.04, -0.04, -0.30,  0.04, 0.04, -0.22
arrow_fletch: dd -0.06, -0.01, 0.15,  0.06, 0.01, 0.27
tiles_shaft: db 5, 5, 5, 5, 5, 5, 0, 0
tiles_tip:   db 0, 0, 0, 0, 0, 0, 0, 0
tiles_fletch: db TILE_CHICKEN_BODY, TILE_CHICKEN_BODY, TILE_CHICKEN_BODY
             db TILE_CHICKEN_BODY, TILE_CHICKEN_BODY, TILE_CHICKEN_BODY, 0, 0
arrow_shades: dd 0.6, 0.6, 1.0, 0.5, 0.8, 0.8   ; +X -X +Y -Y +Z -Z

; bullet: a short brass slug; rocket: body, red warhead, fins (all point to -Z)
bullet_box:  dd -0.025, -0.025, -0.08,  0.025, 0.025, 0.08
rocket_body: dd -0.07, -0.07, -0.25,  0.07, 0.07, 0.2
rocket_head: dd -0.08, -0.08, -0.38,  0.08, 0.08, -0.25
rocket_fins: dd -0.15, -0.02, 0.12,  0.15, 0.02, 0.25
tiles_brass: times 6 db TILE_CHICKEN_LEG
             db 0, 0
tiles_steel: times 6 db TILE_SKELETON_BONE
             db 0, 0
tiles_head:  times 6 db TILE_TNT_SIDE
             db 0, 0

section .bss
alignb 16
arrows:      resb MAX_ARROWS * ARROWENT_size
arrows_end:

section .text

; arrows_clear(): remove every arrow
arrows_clear:
    lea     rdi, [arrows]
    mov     ecx, MAX_ARROWS * ARROWENT_size
    xor     eax, eax
    rep     stosb
    ret

; arrows_spawn(xmm0 x, xmm1 y, xmm2 z, xmm3 vx, xmm4 vy, xmm5 vz, edi owner, esi damage,
;              edx pickup, ecx kind) -> eax slot index, or -1 when every slot is in use
; owner: 0 player, 1 mob. kind: PROJ_ARROW, PROJ_BULLET, PROJ_ROCKET. Velocities are
; blocks per second.
arrows_spawn:
    lea     r8, [arrows]
    xor     eax, eax
.find:
    cmp     dword [r8 + ARROWENT.live], 0
    je      .found
    add     r8, ARROWENT_size
    inc     eax
    cmp     eax, MAX_ARROWS
    jb      .find
    mov     eax, -1
    ret
.found:
    movss   [r8 + ARROWENT.x], xmm0
    movss   [r8 + ARROWENT.y], xmm1
    movss   [r8 + ARROWENT.z], xmm2
    movss   [r8 + ARROWENT.vx], xmm3
    movss   [r8 + ARROWENT.vy], xmm4
    movss   [r8 + ARROWENT.vz], xmm5
    mov     dword [r8 + ARROWENT.age], 0
    mov     dword [r8 + ARROWENT.stuck], 0
    mov     [r8 + ARROWENT.owner], edi
    mov     [r8 + ARROWENT.damage], esi
    mov     [r8 + ARROWENT.pickup], edx
    mov     [r8 + ARROWENT.kind], ecx
    mov     dword [r8 + ARROWENT.live], 1
    ret

; arrow_advance(rdi arrow, rsi dir[3], xmm0 t, rdx out[3]): out = arrow position + dir * t.
; out may be the arrow itself.
arrow_advance:
    movss   xmm1, [rsi]
    mulss   xmm1, xmm0
    addss   xmm1, [rdi + ARROWENT.x]
    movss   [rdx], xmm1
    movss   xmm1, [rsi + 4]
    mulss   xmm1, xmm0
    addss   xmm1, [rdi + ARROWENT.y]
    movss   [rdx + 4], xmm1
    movss   xmm1, [rsi + 8]
    mulss   xmm1, xmm0
    addss   xmm1, [rdi + ARROWENT.z]
    movss   [rdx + 8], xmm1
    ret

; arrow_hdir(rdi arrow, rsi out[2]): the arrow's horizontal heading as a unit vector (x, z);
; (0, 0) when it is flying straight up or down
arrow_hdir:
    movss   xmm0, [rdi + ARROWENT.vx]
    movss   xmm1, [rdi + ARROWENT.vz]
    movaps  xmm2, xmm0
    mulss   xmm2, xmm2
    movaps  xmm3, xmm1
    mulss   xmm3, xmm3
    addss   xmm2, xmm3
    sqrtss  xmm2, xmm2
    comiss  xmm2, [c_hdir_min]
    jae     .unit
    xorps   xmm0, xmm0
    xorps   xmm1, xmm1
    jmp     .store
.unit:
    divss   xmm0, xmm2
    divss   xmm1, xmm2
.store:
    movss   [rsi], xmm0
    movss   [rsi + 4], xmm1
    ret

; HIT_POINT: S_HP = arrow position + dir * S_T, S_H = unit horizontal heading
%macro HIT_POINT 0
    mov     rdi, rbx
    lea     rsi, [rsp + S_DIR]
    movss   xmm0, [rsp + S_T]
    lea     rdx, [rsp + S_HP]
    call    arrow_advance
    mov     rdi, rbx
    lea     rsi, [rsp + S_H]
    call    arrow_hdir
%endmacro

; arrows_step(): one fixed 1/60 s step for every arrow.
; Flying arrows fall under gravity along the segment they travel this step; the nearest of
; the first block, the first mob (the player's arrows) or the player (a mob's arrows) on that
; segment ends the flight: a creature is hurt and the arrow vanishes, a block holds it.
; Stuck arrows time out; the player walks over its own to pick it up again.
; rbx = arrow, r12 = end of the table
arrows_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, S_FRAME
    lea     rbx, [arrows]
    lea     r12, [arrows_end]
.loop:
    cmp     dword [rbx + ARROWENT.live], 0
    je      .next
    cmp     dword [rbx + ARROWENT.stuck], 0
    jne     .stuck

    ; ---- flying: lifetime, gravity (arrows only), then the segment v / 60 ----------
    inc     dword [rbx + ARROWENT.age]
    mov     eax, [rbx + ARROWENT.age]
    mov     ecx, [rbx + ARROWENT.kind]
    lea     rdx, [max_age]
    cmp     eax, [rdx + rcx*4]
    ja      .expired
    cmp     ecx, PROJ_ARROW
    jne     .no_gravity
    movss   xmm0, [rbx + ARROWENT.vy]
    subss   xmm0, [c_gravity]
    movss   [rbx + ARROWENT.vy], xmm0
.no_gravity:
    movss   xmm4, [c_dt]
    movss   xmm0, [rbx + ARROWENT.vx]
    mulss   xmm0, xmm4
    movss   [rsp + S_SEG], xmm0
    movss   xmm1, [rbx + ARROWENT.vy]
    mulss   xmm1, xmm4
    movss   [rsp + S_SEG + 4], xmm1
    movss   xmm2, [rbx + ARROWENT.vz]
    mulss   xmm2, xmm4
    movss   [rsp + S_SEG + 8], xmm2
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    mulss   xmm2, xmm2
    addss   xmm0, xmm1
    addss   xmm0, xmm2
    sqrtss  xmm0, xmm0
    movss   [rsp + S_LEN], xmm0
    comiss  xmm0, [c_tiny]
    jbe     .next                       ; not moving (or NaN): nothing to sweep
    movaps  xmm1, xmm0
    movss   xmm0, [rsp + S_SEG]
    divss   xmm0, xmm1
    movss   [rsp + S_DIR], xmm0
    movss   xmm0, [rsp + S_SEG + 4]
    divss   xmm0, xmm1
    movss   [rsp + S_DIR + 4], xmm0
    movss   xmm0, [rsp + S_SEG + 8]
    divss   xmm0, xmm1
    movss   [rsp + S_DIR + 8], xmm0

    ; ---- the first block on the segment ---------------------------------------
    mov     rdi, rbx                    ; x, y, z lead the record: a float[3] origin
    lea     rsi, [rsp + S_DIR]
    lea     rdx, [rsp + S_HIT]
    movss   xmm0, [rsp + S_LEN]
    call    raycast
    mov     [rsp + S_BLK], eax
    movss   xmm0, [rsp + S_LEN]
    movss   [rsp + S_TMAX], xmm0        ; no block: the whole segment is free
    test    eax, eax
    jz      .creature
    xor     ecx, ecx                    ; the cell's box [b, b + 1]
.cell_box:
    cvtsi2ss xmm0, dword [rsp + S_HIT + rcx*4]
    movss   [rsp + S_LO + rcx*4], xmm0
    addss   xmm0, [c_one]
    movss   [rsp + S_HI + rcx*4], xmm0
    inc     ecx
    cmp     ecx, 3
    jb      .cell_box
    mov     rdi, rbx
    lea     rsi, [rsp + S_DIR]
    lea     rdx, [rsp + S_LO]
    lea     rcx, [rsp + S_HI]
    movss   xmm0, [rsp + S_LEN]
    call    ray_aabb
    test    eax, eax
    jz      .creature                   ; a grazing miss of the box: keep the whole segment
    movss   [rsp + S_TMAX], xmm0

    ; ---- a creature nearer than the block ----------------------------------------
.creature:
    cmp     dword [rbx + ARROWENT.owner], 0
    jne     .player_arrow
    mov     rdi, rbx
    lea     rsi, [rsp + S_DIR]
    movss   xmm0, [rsp + S_TMAX]
    call    mobs_raycast
    test    eax, eax
    js      .settle                     ; no mob in front of the block
    mov     [rsp + S_IDX], eax
    movss   [rsp + S_T], xmm0
    HIT_POINT
    cmp     dword [rbx + ARROWENT.kind], PROJ_ROCKET
    je      .rocket_burst               ; a rocket goes off on the mob
    mov     edi, [rsp + S_IDX]
    mov     esi, [rbx + ARROWENT.damage]
    movss   xmm0, [rsp + S_H]
    movss   xmm1, [rsp + S_H + 4]
    cmp     dword [rbx + ARROWENT.kind], PROJ_BULLET
    je      .shot
    call    mob_hurt
    jmp     .impact
.shot:
    call    mob_shot                    ; every bullet counts, even in the hurt window
    jmp     .impact

.player_arrow:
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .settle                     ; nobody to hit in Creative
    cmp     dword [surv + SURVIVAL.dead], 0
    jne     .settle
    movss   xmm0, [player + BODY.x]     ; the player's box
    movss   xmm1, [c_half_w]
    movaps  xmm2, xmm0
    subss   xmm0, xmm1
    addss   xmm2, xmm1
    movss   [rsp + S_LO], xmm0
    movss   [rsp + S_HI], xmm2
    movss   xmm0, [player + BODY.z]
    movaps  xmm2, xmm0
    subss   xmm0, xmm1
    addss   xmm2, xmm1
    movss   [rsp + S_LO + 8], xmm0
    movss   [rsp + S_HI + 8], xmm2
    movss   xmm0, [player + BODY.y]
    movss   [rsp + S_LO + 4], xmm0
    addss   xmm0, [c_height]
    movss   [rsp + S_HI + 4], xmm0
    mov     rdi, rbx
    lea     rsi, [rsp + S_DIR]
    lea     rdx, [rsp + S_LO]
    lea     rcx, [rsp + S_HI]
    movss   xmm0, [rsp + S_TMAX]
    call    ray_aabb
    test    eax, eax
    jz      .settle
    movss   [rsp + S_T], xmm0
    HIT_POINT
    mov     edi, [rbx + ARROWENT.damage]
    mov     esi, CAUSE_SKELETON
    call    survival_damage
    test    eax, eax
    jz      .impact                     ; invulnerable: the arrow is spent anyway
    movss   xmm0, [rsp + S_H]           ; shoved along the arrow's heading
    mulss   xmm0, [c_kb]
    movss   [player + BODY.kbx], xmm0
    movss   xmm0, [rsp + S_H + 4]
    mulss   xmm0, [c_kb]
    movss   [player + BODY.kbz], xmm0

    ; ---- a creature was hit: sound at the hit point, the arrow is gone ----------------
.impact:
    mov     edi, SND_ARROW_HIT
    movss   xmm0, [rsp + S_HP]
    movss   xmm1, [rsp + S_HP + 4]
    movss   xmm2, [rsp + S_HP + 8]
    movss   xmm3, [c_hit_vol]
    call    audio_play_at
    jmp     .remove

    ; ---- no creature: the block holds an arrow, stops a bullet, sets off a rocket; else
    ; the projectile flies on --------------------------------------------------------
.settle:
    cmp     dword [rsp + S_BLK], 0
    je      .fly
    mov     eax, [rbx + ARROWENT.kind]
    cmp     eax, PROJ_BULLET
    je      .bullet_block
    cmp     eax, PROJ_ROCKET
    je      .rocket_block
    mov     rdi, rbx
    lea     rsi, [rsp + S_DIR]
    movss   xmm0, [rsp + S_TMAX]
    subss   xmm0, [c_embed]
    mov     rdx, rbx
    call    arrow_advance               ; stops just short of the surface
    mov     dword [rbx + ARROWENT.stuck], 1
    mov     edi, SND_ARROW_HIT
    movss   xmm0, [rbx + ARROWENT.x]
    movss   xmm1, [rbx + ARROWENT.y]
    movss   xmm2, [rbx + ARROWENT.z]
    movss   xmm3, [c_stick_vol]
    call    audio_play_at
    jmp     .next
.bullet_block:                          ; the bullet is spent on the surface
    movss   xmm0, [rsp + S_TMAX]
    movss   [rsp + S_T], xmm0
    HIT_POINT
    mov     edi, SND_ARROW_HIT
    movss   xmm0, [rsp + S_HP]
    movss   xmm1, [rsp + S_HP + 4]
    movss   xmm2, [rsp + S_HP + 8]
    movss   xmm3, [c_bullet_vol]
    call    audio_play_at
    jmp     .remove
.rocket_block:                          ; just short of the surface it hit
    movss   xmm0, [rsp + S_TMAX]
    subss   xmm0, [c_embed]
    movss   [rsp + S_T], xmm0
    HIT_POINT
.rocket_burst:                          ; S_HP = where it goes off; freed before the blast
    mov     dword [rbx + ARROWENT.live], 0
    movss   xmm0, [rsp + S_HP]
    movss   xmm1, [rsp + S_HP + 4]
    movss   xmm2, [rsp + S_HP + 8]
    movss   xmm3, [c_rocket_r]
    call    explode_at
    jmp     .next
.expired:                               ; out of time: an arrow or bullet vanishes,
    cmp     dword [rbx + ARROWENT.kind], PROJ_ROCKET
    jne     .remove
    mov     eax, [rbx + ARROWENT.x]     ; a rocket goes off where it is
    mov     [rsp + S_HP], eax
    mov     eax, [rbx + ARROWENT.y]
    mov     [rsp + S_HP + 4], eax
    mov     eax, [rbx + ARROWENT.z]
    mov     [rsp + S_HP + 8], eax
    jmp     .rocket_burst
.fly:
    movss   xmm0, [rbx + ARROWENT.x]
    addss   xmm0, [rsp + S_SEG]
    movss   [rbx + ARROWENT.x], xmm0
    movss   xmm0, [rbx + ARROWENT.y]
    addss   xmm0, [rsp + S_SEG + 4]
    movss   [rbx + ARROWENT.y], xmm0
    movss   xmm1, [c_out_y]
    comiss  xmm1, xmm0
    ja      .remove                     ; fell out of the world
    movss   xmm0, [rbx + ARROWENT.z]
    addss   xmm0, [rsp + S_SEG + 8]
    movss   [rbx + ARROWENT.z], xmm0
    jmp     .next

    ; ---- stuck in a block -----------------------------------------------------------
.stuck:
    inc     dword [rbx + ARROWENT.stuck]
    mov     eax, [rbx + ARROWENT.stuck]
    cmp     dword [rbx + ARROWENT.owner], 0
    jne     .stuck_mob
    cmp     eax, STUCK_OWN_STEPS
    ja      .remove
    cmp     dword [rbx + ARROWENT.pickup], 0
    je      .next
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .next
    cmp     dword [surv + SURVIVAL.dead], 0
    jne     .next
    movss   xmm0, [rbx + ARROWENT.x]
    subss   xmm0, [player + BODY.x]
    mulss   xmm0, xmm0
    movss   xmm1, [rbx + ARROWENT.z]
    subss   xmm1, [player + BODY.z]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [c_pick_r2]
    jae     .next
    movss   xmm0, [rbx + ARROWENT.y]
    subss   xmm0, [player + BODY.y]
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jb      .next                       ; below the player's feet
    comiss  xmm0, [c_pick_hi]
    ja      .next
    mov     edi, ARROW
    mov     esi, 1
    call    inv_add
    test    eax, eax
    jnz     .next                       ; inventory full: it stays in the block
    mov     edi, SND_POP
    movss   xmm0, [c_pop_vol]
    call    audio_play
    jmp     .remove
.stuck_mob:
    cmp     eax, STUCK_MOB_STEPS
    jbe     .next
.remove:
    mov     dword [rbx + ARROWENT.live], 0
.next:
    add     rbx, ARROWENT_size
    cmp     rbx, r12
    jb      .loop
    add     rsp, S_FRAME
    pop     r12
    pop     rbx
    pop     rbp
    ret

; arrows_render(): every projectile, aimed along its velocity, with its kind's model.
; Called inside the world pass (atlas bound, alpha test on, night darkening active).
; rbx = arrow, r12 = end of the table; [rsp] yaw/pitch scratch
arrows_render:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    lea     rbx, [arrows]
    lea     r12, [arrows_end]
.loop:
    cmp     dword [rbx + ARROWENT.live], 0
    je      .next
    call    glPushMatrix
    movss   xmm0, [rbx + ARROWENT.x]
    movss   xmm1, [rbx + ARROWENT.y]
    movss   xmm2, [rbx + ARROWENT.z]
    call    glTranslatef
    movss   xmm0, [rbx + ARROWENT.vx]   ; heading: yaw = atan2(vx, -vz)
    xorps   xmm1, xmm1
    subss   xmm1, [rbx + ARROWENT.vz]
    call    atan2_deg
    xorps   xmm1, xmm1
    subss   xmm1, xmm0                  ; glRotatef(-yaw, 0, 1, 0)
    movaps  xmm0, xmm1
    xorps   xmm1, xmm1
    movss   xmm2, [f_one]
    xorps   xmm3, xmm3
    call    glRotatef
    movss   xmm0, [rbx + ARROWENT.vx]   ; pitch = atan2(vy, horizontal speed)
    mulss   xmm0, xmm0
    movss   xmm1, [rbx + ARROWENT.vz]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    sqrtss  xmm1, xmm0
    movss   xmm0, [rbx + ARROWENT.vy]
    call    atan2_deg
    movss   xmm1, [f_one]
    xorps   xmm2, xmm2
    xorps   xmm3, xmm3
    call    glRotatef                   ; glRotatef(pitch, 1, 0, 0)
    mov     eax, [rbx + ARROWENT.kind]
    cmp     eax, PROJ_BULLET
    je      .bullet
    cmp     eax, PROJ_ROCKET
    je      .rocket
    lea     rdi, [arrow_shaft]
    lea     rsi, [tiles_shaft]
    call    draw_box
    lea     rdi, [arrow_tip]
    lea     rsi, [tiles_tip]
    call    draw_box
    lea     rdi, [arrow_fletch]
    lea     rsi, [tiles_fletch]
    call    draw_box
    jmp     .drawn
.bullet:
    lea     rdi, [bullet_box]
    lea     rsi, [tiles_brass]
    call    draw_box
    jmp     .drawn
.rocket:
    lea     rdi, [rocket_body]
    lea     rsi, [tiles_steel]
    call    draw_box
    lea     rdi, [rocket_head]
    lea     rsi, [tiles_head]
    call    draw_box
    lea     rdi, [rocket_fins]
    lea     rsi, [tiles_steel]
    call    draw_box
.drawn:
    call    glPopMatrix
.next:
    add     rbx, ARROWENT_size
    cmp     rbx, r12
    jb      .loop
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; draw_box(rdi box float[6], rsi tiles byte[6]): render_box with the arrow shades, untinted
draw_box:
    sub     rsp, 8
    lea     rdx, [arrow_shades]
    movss   xmm0, [f_one]
    movaps  xmm1, xmm0
    movaps  xmm2, xmm0
    call    render_box
    add     rsp, 8
    ret
