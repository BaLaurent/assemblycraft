; hand.asm - first-person view of the held item (or the bare arm): swing animation on
; attack/dig/place, walk bob, lit like the world. Drawn after the world pass with its own
; projection and a cleared depth buffer so it never clips into blocks.
%include "common.inc"
%include "gl.inc"
default rel

global hand_render, hand_swing

extern player, inv_held, sky_brightness, game_time, sincos_deg, game_bow_charge, gun_kick
extern render_box, item_model_draw, tex_id, gun_model_draw, game_aim
extern gun_reload, gun_reload_total

section .rodata
align 8
d_near:      dq 0.05
d_far:       dq 10.0
d_hh:        dq 0.035010376             ; 0.05 * tan(35 deg): fixed 70 deg hand FOV
align 4
f_swing_inv: dd 3.3333333               ; 1 / 0.3 s
f_one:       dd 1.0
f_180:       dd 180.0
f_360:       dd 360.0
f_bob_rate:  dd 110.0                   ; walk-bob degrees per block walked
f_bob_x:     dd 0.02
f_bob_y:     dd 0.03
f_base_x:    dd 0.48
f_base_y:    dd -0.40
f_base_z:    dd -0.80
f_sw_x:      dd -0.25
f_sw_y:      dd 0.12
f_sw_z:      dd -0.2
f_sw_rot:    dd -55.0
f_bow_pull:  dd 0.18                    ; how far a fully drawn bow comes back
f_kick_back: dd 0.09                    ; firearm recoil at full kick: back and muzzle up
f_kick_rot:  dd 10.0
f_quarter:   dd 0.25                    ; a firearm bobs a quarter as much
; firearm position: from the hip (right, low) to down the sights (centred under the eye)
g_hip_x:     dd 0.30
g_hip_y:     dd -0.30
g_hip_z:     dd -0.55
g_aim_x:     dd 0.0
g_aim_y:     dd -0.16
g_aim_z:     dd -0.42
f_rel_dip:   dd 0.12                    ; reload: drop, roll and tip at mid-reload
f_rel_roll:  dd 25.0
f_rel_tip:   dd -20.0
; bare arm: a skin-coloured box reaching from below the screen corner
arm_box:     dd -0.1, -0.1, -0.3, 0.1, 0.1, 0.5
arm_tiles:   times 6 db TILE_PLAYER_SKIN
align 4
arm_shade:   dd 0.6, 0.6, 1.0, 0.5, 0.8, 0.8
; per-kind pose: rotate X, rotate Y, rotate Z (degrees), uniform scale
pose_arm:    dd 35.0, 15.0, 0.0, 1.0
pose_block:  dd 10.0, 45.0, 0.0, 0.32
pose_item:   dd 0.0, 160.0, 0.0, 0.5

section .bss
alignb 4
swing_p:     resd 1                     ; swing progress 0..1
swinging:    resd 1
bob_phase:   resd 1
light:       resd 1
shades:      resd 6
sw_s1:       resd 1                     ; sin(sqrt(p) * 180)
sw_s2:       resd 1                     ; sin(p * 180)
sw_s3:       resd 1                     ; sin(sqrt(p) * 360)
bob_s:       resd 1
bob_c:       resd 1
loaded:      resd 1                     ; held firearm: rounds in the magazine
reload_s:    resd 1                     ; held firearm: sin(180 * reload progress)

section .text

; hand_swing(): start a swing unless one is already in its first half
hand_swing:
    cmp     dword [swinging], 0
    je      .start
    movss   xmm0, [swing_p]
    ucomiss xmm0, [half]
    jb      .ret
.start:
    mov     dword [swinging], 1
    mov     dword [swing_p], 0
.ret:
    ret

section .rodata
align 4
half:        dd 0.5

section .text

; rot(xmm0 degrees, xmm1 x, xmm2 y, xmm3 z) = glRotatef, skipped for 0 degrees
rot:
    xorps   xmm4, xmm4
    ucomiss xmm0, xmm4
    jne     glRotatef
    ret

; hand_render(edi fb_w, esi fb_h, xmm0 dt)
hand_render:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     r12d, edi
    mov     r13d, esi

    ; ---- animation state ---------------------------------------------------------
    cmp     dword [swinging], 0
    je      .bob
    movss   xmm1, xmm0
    mulss   xmm1, [f_swing_inv]
    addss   xmm1, [swing_p]
    movss   [swing_p], xmm1
    comiss  xmm1, [f_one]
    jb      .bob
    mov     dword [swinging], 0
    mov     dword [swing_p], 0
.bob:
    cmp     dword [player + BODY.on_ground], 0
    je      .anim_done
    cmp     dword [player + BODY.flying], 0
    jne     .anim_done
    movss   xmm1, [player + BODY.vx]
    mulss   xmm1, xmm1
    movss   xmm2, [player + BODY.vz]
    mulss   xmm2, xmm2
    addss   xmm1, xmm2
    sqrtss  xmm1, xmm1                  ; horizontal speed
    mulss   xmm1, xmm0
    mulss   xmm1, [f_bob_rate]
    addss   xmm1, [bob_phase]
    movss   xmm2, [f_360]
    comiss  xmm1, xmm2
    jb      .phase
    subss   xmm1, xmm2
.phase:
    movss   [bob_phase], xmm1
.anim_done:
    movss   xmm0, [swing_p]
    sqrtss  xmm0, xmm0
    mulss   xmm0, [f_180]
    call    sincos_deg
    movss   [sw_s1], xmm0
    movss   xmm0, [swing_p]
    sqrtss  xmm0, xmm0
    mulss   xmm0, [f_360]
    call    sincos_deg
    movss   [sw_s3], xmm0
    movss   xmm0, [swing_p]
    mulss   xmm0, [f_180]
    call    sincos_deg
    movss   [sw_s2], xmm0
    movss   xmm0, [bob_phase]
    call    sincos_deg
    movss   [bob_s], xmm0
    andps   xmm1, [rel f_abs_vec]
    movss   [bob_c], xmm1
    mov     edi, [game_time]
    call    sky_brightness
    movss   [light], xmm0

    ; ---- view: own projection, fresh depth --------------------------------------
    mov     edi, GL_DEPTH_BUFFER_BIT
    call    glClear
    mov     edi, GL_PROJECTION
    call    glMatrixMode
    call    glLoadIdentity
    cvtsi2sd xmm1, r12d
    cvtsi2sd xmm2, r13d
    divsd   xmm1, xmm2
    mulsd   xmm1, [d_hh]                ; right
    movsd   xmm3, [d_hh]                ; top
    xorpd   xmm2, xmm2
    subsd   xmm2, xmm3                  ; bottom
    xorpd   xmm0, xmm0
    subsd   xmm0, xmm1                  ; left
    movsd   xmm4, [d_near]
    movsd   xmm5, [d_far]
    call    glFrustum
    mov     edi, GL_MODELVIEW
    call    glMatrixMode
    call    glLoadIdentity
    mov     edi, GL_DEPTH_TEST
    call    glEnable
    mov     edi, GL_CULL_FACE
    call    glEnable
    mov     edi, GL_TEXTURE_2D
    call    glEnable
    mov     edi, GL_TEXTURE_2D
    mov     esi, [tex_id]
    call    glBindTexture
    mov     edi, GL_ALPHA_TEST
    call    glEnable
    mov     edi, GL_FOG
    call    glDisable
    mov     edi, GL_BLEND
    call    glDisable

    ; ---- what is held ------------------------------------------------------------
    call    inv_held
    xor     ebx, ebx
    cmp     byte [rax + ITEMSTACK.count], 0
    je      .held
    movzx   ebx, byte [rax + ITEMSTACK.id]
    movzx   eax, word [rax + ITEMSTACK.dmg]
    mov     [loaded], eax               ; a firearm's rounds in the magazine
.held:
    lea     eax, [rbx - PISTOL]
    cmp     eax, NUM_GUNS
    jb      .gun_view

    ; ---- position: screen corner + walk bob + swing ------------------------------
    movss   xmm0, [bob_s]
    mulss   xmm0, [f_bob_x]
    addss   xmm0, [f_base_x]
    movss   xmm3, [sw_s1]
    mulss   xmm3, [f_sw_x]
    addss   xmm0, xmm3
    movss   xmm1, [bob_c]
    mulss   xmm1, [f_bob_y]
    movss   xmm3, [f_base_y]
    subss   xmm3, xmm1
    movss   xmm1, [sw_s3]
    mulss   xmm1, [f_sw_y]
    addss   xmm1, xmm3
    movss   xmm2, [sw_s2]
    mulss   xmm2, [f_sw_z]
    addss   xmm2, [f_base_z]
    call    glTranslatef
    movss   xmm0, [sw_s2]
    mulss   xmm0, [f_sw_rot]
    movss   xmm1, [f_one]
    xorps   xmm2, xmm2
    xorps   xmm3, xmm3
    call    rot

.kind:
    cmp     ebx, BOW                    ; a drawn bow comes back towards the eye
    jne     .no_draw
    movss   xmm2, [game_bow_charge]
    xorps   xmm0, xmm0
    comiss  xmm2, xmm0
    jbe     .no_draw
    minss   xmm2, [f_one]
    mulss   xmm2, [f_bow_pull]
    xorps   xmm1, xmm1
    call    glTranslatef
.no_draw:
    lea     rdi, [pose_arm]
    test    ebx, ebx
    jz      .pose
    lea     rdi, [pose_block]
    cmp     ebx, NUM_BLOCKS
    jb      .pose
    lea     rdi, [pose_item]
.pose:
    call    apply_pose
    test    ebx, ebx
    jz      .arm
    mov     edi, ebx
    movss   xmm0, [light]
    call    item_model_draw
    jmp     .ret

    ; ---- firearm: hip or aimed position, light bob, recoil, reload dip; no swing ----
.gun_view:
    mov     dword [reload_s], 0         ; reload motion: sin(180 p), p = reload progress
    mov     ecx, [gun_reload_total]
    test    ecx, ecx
    jz      .gun_place
    mov     eax, [gun_reload]
    test    eax, eax
    jz      .gun_place
    cvtsi2ss xmm0, eax
    cvtsi2ss xmm1, ecx
    divss   xmm0, xmm1
    movss   xmm1, [f_one]
    subss   xmm1, xmm0
    mulss   xmm1, [f_180]
    movaps  xmm0, xmm1
    call    sincos_deg
    movss   [reload_s], xmm0
.gun_place:
    movss   xmm3, [game_aim]
    movss   xmm0, [g_aim_x]             ; x = lerp(hip, aimed) + bob / 4
    subss   xmm0, [g_hip_x]
    mulss   xmm0, xmm3
    addss   xmm0, [g_hip_x]
    movss   xmm4, [bob_s]
    mulss   xmm4, [f_bob_x]
    mulss   xmm4, [f_quarter]
    addss   xmm0, xmm4
    movss   xmm1, [g_aim_y]             ; y = lerp - bob / 4 - reload dip
    subss   xmm1, [g_hip_y]
    mulss   xmm1, xmm3
    addss   xmm1, [g_hip_y]
    movss   xmm4, [bob_c]
    mulss   xmm4, [f_bob_y]
    mulss   xmm4, [f_quarter]
    subss   xmm1, xmm4
    movss   xmm4, [reload_s]
    mulss   xmm4, [f_rel_dip]
    subss   xmm1, xmm4
    movss   xmm2, [g_aim_z]             ; z = lerp + recoil
    subss   xmm2, [g_hip_z]
    mulss   xmm2, xmm3
    addss   xmm2, [g_hip_z]
    movss   xmm4, [gun_kick]
    mulss   xmm4, [f_kick_back]
    addss   xmm2, xmm4
    call    glTranslatef
    movss   xmm0, [gun_kick]            ; muzzle climbs with the recoil
    mulss   xmm0, [f_kick_rot]
    movss   xmm1, [f_one]
    xorps   xmm2, xmm2
    xorps   xmm3, xmm3
    call    rot
    movss   xmm0, [reload_s]            ; reload: roll the gun over and tip it down
    mulss   xmm0, [f_rel_roll]
    xorps   xmm1, xmm1
    xorps   xmm2, xmm2
    movss   xmm3, [f_one]
    call    rot
    movss   xmm0, [reload_s]
    mulss   xmm0, [f_rel_tip]
    movss   xmm1, [f_one]
    xorps   xmm2, xmm2
    xorps   xmm3, xmm3
    call    rot
    mov     edi, ebx
    mov     esi, [loaded]
    movss   xmm0, [light]
    movss   xmm1, [gun_kick]
    call    gun_model_draw
    jmp     .ret
.arm:
    xor     ecx, ecx
.arm_shade:
    movss   xmm0, [arm_shade + rcx*4]
    mulss   xmm0, [light]
    movss   [shades + rcx*4], xmm0
    inc     ecx
    cmp     ecx, 6
    jb      .arm_shade
    lea     rdi, [arm_box]
    lea     rsi, [arm_tiles]
    lea     rdx, [shades]
    movss   xmm0, [f_one]
    movss   xmm1, [f_one]
    movss   xmm2, [f_one]
    call    render_box
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; apply_pose(rdi pose float[4]): rotate X, Y, Z, then scale
apply_pose:
    push    rbx
    mov     rbx, rdi
    movss   xmm0, [rbx]
    movss   xmm1, [f_one]
    xorps   xmm2, xmm2
    xorps   xmm3, xmm3
    call    rot
    movss   xmm0, [rbx + 4]
    xorps   xmm1, xmm1
    movss   xmm2, [f_one]
    xorps   xmm3, xmm3
    call    rot
    movss   xmm0, [rbx + 8]
    xorps   xmm1, xmm1
    xorps   xmm2, xmm2
    movss   xmm3, [f_one]
    call    rot
    movss   xmm0, [rbx + 12]
    movss   xmm1, xmm0
    movss   xmm2, xmm0
    call    glScalef
    pop     rbx
    ret

section .rodata
align 16
f_abs_vec:   dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF
