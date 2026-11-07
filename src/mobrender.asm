; mobrender.asm - zombie, pig, creeper, skeleton, spider and chicken box models, drawn with the
; state render_world leaves set up: atlas on unit 0, night combiner on unit 1, fog, alpha test,
; face culling.
; Model space has the front at -Z; limbs swing about X at their pivot.
%include "common.inc"
%include "gl.inc"
default rel

global mobs_render

extern mobs, render_box, sincos_deg

; part record: box (lo xyz, hi xyz), tile per face (+X -X +Y -Y +Z -Z), pivot y, pivot z,
; swing factor (limb angle = factor * walk swing; 0 = rigid)
%define PART_SIZE 44
%define P_BOX     0
%define P_TILES   24
%define P_PIVOT_Y 32
%define P_PIVOT_Z 36
%define P_SWING   40

; PART x0, y0, z0, x1, y1, z1, tile, front tile (-Z face), pivot y, pivot z, swing
%macro PART 11
    dd %1, %2, %3, %4, %5, %6
    db %7, %7, %7, %7, %7, %8, 0, 0
    dd %9, %10, %11
%endmacro

section .rodata
align 4
f_one:      dd 1.0
f_half:     dd 0.5
f_swing:    dd 30.0                     ; peak limb angle, degrees
mob_shades: dd 0.6, 0.6, 1.0, 0.5, 0.8, 0.8   ; +X -X +Y -Y +Z -Z
f_swell:    dd 0.0022222222             ; creeper swell: 20 % over 90 fuse steps

zombie_parts:
    PART -0.25, 0.0, -0.125,  0.0, 0.75, 0.125,   TILE_ZOMBIE_PANTS, TILE_ZOMBIE_PANTS, 0.75, 0.0,  1.0    ; left leg
    PART  0.0,  0.0, -0.125,  0.25, 0.75, 0.125,  TILE_ZOMBIE_PANTS, TILE_ZOMBIE_PANTS, 0.75, 0.0, -1.0    ; right leg
    PART -0.25, 0.75, -0.125, 0.25, 1.5, 0.125,   TILE_ZOMBIE_SHIRT, TILE_ZOMBIE_SHIRT, 0.0, 0.0,  0.0     ; body
    PART -0.5,  1.25, -0.75, -0.25, 1.5, 0.0,     TILE_ZOMBIE_SKIN, TILE_ZOMBIE_SKIN, 1.375, 0.0, -0.25    ; left arm
    PART  0.25, 1.25, -0.75,  0.5,  1.5, 0.0,     TILE_ZOMBIE_SKIN, TILE_ZOMBIE_SKIN, 1.375, 0.0,  0.25    ; right arm
    PART -0.25, 1.5, -0.25,   0.25, 2.0, 0.25,    TILE_ZOMBIE_SKIN, TILE_ZOMBIE_FACE, 0.0, 0.0,  0.0       ; head
%define ZOMBIE_PARTS 6

pig_parts:
    PART -0.3125, 0.375, -0.5,   0.3125, 0.875, 0.5,     TILE_PIG_SKIN, TILE_PIG_SKIN, 0.0, 0.0, 0.0        ; body
    PART -0.25,   0.5,   -0.875, 0.25,   1.0,  -0.5,     TILE_PIG_SKIN, TILE_PIG_FACE, 0.0, 0.0, 0.0        ; head
    PART -0.3125, 0.0, -0.4375, -0.0625, 0.375, -0.1875, TILE_PIG_SKIN, TILE_PIG_SKIN, 0.375, -0.3125,  1.0  ; front left
    PART  0.0625, 0.0, -0.4375,  0.3125, 0.375, -0.1875, TILE_PIG_SKIN, TILE_PIG_SKIN, 0.375, -0.3125, -1.0  ; front right
    PART -0.3125, 0.0,  0.1875, -0.0625, 0.375,  0.4375, TILE_PIG_SKIN, TILE_PIG_SKIN, 0.375,  0.3125, -1.0  ; back left
    PART  0.0625, 0.0,  0.1875,  0.3125, 0.375,  0.4375, TILE_PIG_SKIN, TILE_PIG_SKIN, 0.375,  0.3125,  1.0  ; back right
%define PIG_PARTS 6

creeper_parts:
    PART -0.25, 0.375, -0.125,  0.25, 1.125, 0.125,  TILE_CREEPER_SKIN, TILE_CREEPER_SKIN, 0.0, 0.0, 0.0       ; body
    PART -0.25, 1.125, -0.25,   0.25, 1.625, 0.25,   TILE_CREEPER_SKIN, TILE_CREEPER_FACE, 0.0, 0.0, 0.0       ; head
    PART -0.25, 0.0, -0.375,    0.0,  0.375, -0.125, TILE_CREEPER_SKIN, TILE_CREEPER_SKIN, 0.375, -0.25,  1.0  ; front left
    PART  0.0,  0.0, -0.375,    0.25, 0.375, -0.125, TILE_CREEPER_SKIN, TILE_CREEPER_SKIN, 0.375, -0.25, -1.0  ; front right
    PART -0.25, 0.0,  0.125,    0.0,  0.375,  0.375, TILE_CREEPER_SKIN, TILE_CREEPER_SKIN, 0.375,  0.25, -1.0  ; back left
    PART  0.0,  0.0,  0.125,    0.25, 0.375,  0.375, TILE_CREEPER_SKIN, TILE_CREEPER_SKIN, 0.375,  0.25,  1.0  ; back right
%define CREEPER_PARTS 6

skeleton_parts:
    PART -0.1875, 0.0, -0.0625, -0.0625, 0.75, 0.0625, TILE_SKELETON_BONE, TILE_SKELETON_BONE, 0.75, 0.0,  1.0   ; left leg
    PART  0.0625, 0.0, -0.0625,  0.1875, 0.75, 0.0625, TILE_SKELETON_BONE, TILE_SKELETON_BONE, 0.75, 0.0, -1.0   ; right leg
    PART -0.25,   0.75, -0.125,  0.25,   1.5,  0.125,  TILE_SKELETON_BONE, TILE_SKELETON_BONE, 0.0,  0.0,  0.0   ; body
    PART -0.375,  0.75, -0.0625, -0.25,  1.5,  0.0625, TILE_SKELETON_BONE, TILE_SKELETON_BONE, 1.4375, 0.0, -1.0 ; left arm
    PART  0.25,   0.75, -0.0625,  0.375, 1.5,  0.0625, TILE_SKELETON_BONE, TILE_SKELETON_BONE, 1.4375, 0.0,  1.0 ; right arm
    PART -0.25,   1.5,  -0.25,    0.25,  2.0,  0.25,   TILE_SKELETON_BONE, TILE_SKELETON_FACE, 0.0, 0.0,  0.0   ; head
%define SKELETON_PARTS 6

spider_parts:
    PART -0.375,  0.25,   0.0,   0.375,  0.8125, 0.75,  TILE_SPIDER_BODY, TILE_SPIDER_BODY, 0.0, 0.0, 0.0   ; abdomen
    PART -0.1875, 0.3125, -0.25, 0.1875, 0.6875, 0.0,   TILE_SPIDER_BODY, TILE_SPIDER_BODY, 0.0, 0.0, 0.0   ; thorax
    PART -0.25,   0.25,  -0.75,  0.25,   0.75,  -0.25,  TILE_SPIDER_BODY, TILE_SPIDER_FACE, 0.0, 0.0, 0.0   ; head
    PART -1.0, 0.4375, -0.4375, -0.1875, 0.5625, -0.3125, TILE_SPIDER_BODY, TILE_SPIDER_BODY, 0.5, -0.375,  0.5  ; left legs, front to back
    PART -1.0, 0.4375, -0.1875, -0.1875, 0.5625, -0.0625, TILE_SPIDER_BODY, TILE_SPIDER_BODY, 0.5, -0.125, -0.5
    PART -1.0, 0.4375,  0.0625, -0.1875, 0.5625,  0.1875, TILE_SPIDER_BODY, TILE_SPIDER_BODY, 0.5,  0.125,  0.5
    PART -1.0, 0.4375,  0.3125, -0.1875, 0.5625,  0.4375, TILE_SPIDER_BODY, TILE_SPIDER_BODY, 0.5,  0.375, -0.5
    PART 0.1875, 0.4375, -0.4375, 1.0, 0.5625, -0.3125,   TILE_SPIDER_BODY, TILE_SPIDER_BODY, 0.5, -0.375, -0.5  ; right legs
    PART 0.1875, 0.4375, -0.1875, 1.0, 0.5625, -0.0625,   TILE_SPIDER_BODY, TILE_SPIDER_BODY, 0.5, -0.125,  0.5
    PART 0.1875, 0.4375,  0.0625, 1.0, 0.5625,  0.1875,   TILE_SPIDER_BODY, TILE_SPIDER_BODY, 0.5,  0.125, -0.5
    PART 0.1875, 0.4375,  0.3125, 1.0, 0.5625,  0.4375,   TILE_SPIDER_BODY, TILE_SPIDER_BODY, 0.5,  0.375,  0.5
%define SPIDER_PARTS 11

chicken_parts:
    PART -0.1875, 0.3125, -0.25,   0.1875, 0.75,   0.25,    TILE_CHICKEN_BODY, TILE_CHICKEN_BODY, 0.0, 0.0, 0.0   ; body
    PART -0.125,  0.5625, -0.4375, 0.125,  0.9375, -0.1875, TILE_CHICKEN_BODY, TILE_CHICKEN_FACE, 0.0, 0.0, 0.0   ; head
    PART -0.25,   0.375,  -0.1875, -0.1875, 0.6875, 0.1875, TILE_CHICKEN_BODY, TILE_CHICKEN_BODY, 0.0, 0.0, 0.0   ; left wing
    PART  0.1875, 0.375,  -0.1875,  0.25,   0.6875, 0.1875, TILE_CHICKEN_BODY, TILE_CHICKEN_BODY, 0.0, 0.0, 0.0   ; right wing
    PART -0.125,  0.0, -0.03125, -0.0625, 0.3125, 0.03125, TILE_CHICKEN_LEG, TILE_CHICKEN_LEG, 0.3125, 0.0,  1.0  ; left leg
    PART  0.0625, 0.0, -0.03125,  0.125,  0.3125, 0.03125, TILE_CHICKEN_LEG, TILE_CHICKEN_LEG, 0.3125, 0.0, -1.0  ; right leg
%define CHICKEN_PARTS 6

align 8
models:                                 ; indexed by type - 1: parts, part count
    dq zombie_parts, ZOMBIE_PARTS
    dq pig_parts, PIG_PARTS
    dq creeper_parts, CREEPER_PARTS
    dq skeleton_parts, SKELETON_PARTS
    dq spider_parts, SPIDER_PARTS
    dq chicken_parts, CHICKEN_PARTS

section .text

; DRAW_PART: render_box of the part at r14, tinted by the mob's hurt colour at [rsp + 4..12]
%macro DRAW_PART 0
    lea     rdi, [r14 + P_BOX]
    lea     rsi, [r14 + P_TILES]
    lea     rdx, [mob_shades]
    movss   xmm0, [rsp + 4]
    movss   xmm1, [rsp + 8]
    movss   xmm2, [rsp + 12]
    call    render_box
%endmacro

; mobs_render(): draw every live mob.
; rbx = mob, r12 = end of the table, r13d = model index, r14 = part, r15d = parts left
; stack: [rsp] swing angle, [rsp+4..12] tint rgb, [rsp+16] limb angle
mobs_render:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    lea     rbx, [mobs]
    lea     r12, [mobs + MAX_MOBS * MOB_size]
.mob:
    mov     r13d, [rbx + MOB.type]
    dec     r13d                        ; model index; a free slot (0) wraps and is skipped
    cmp     r13d, NUM_MOB_TYPES - 1
    ja      .next
    movss   xmm0, [rbx + MOB.walk]
    call    sincos_deg
    mulss   xmm0, [f_swing]
    movss   [rsp], xmm0                 ; swing = sin(walk) * 30 degrees
    movss   xmm0, [f_one]
    movss   xmm1, xmm0
    movss   xmm2, xmm0
    cmp     dword [rbx + MOB.hurt], 0
    jle     .tinted
    movss   xmm1, [f_half]              ; hit: red tint
    movss   xmm2, [f_half]
.tinted:
    movss   [rsp + 4], xmm0
    movss   [rsp + 8], xmm1
    movss   [rsp + 12], xmm2
    call    glPushMatrix
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    call    glTranslatef
    xorps   xmm0, xmm0
    subss   xmm0, [rbx + BODY.yaw]
    xorps   xmm1, xmm1
    movss   xmm2, [f_one]
    xorps   xmm3, xmm3
    call    glRotatef                   ; front (-Z) turns to the mob's heading
    mov     dword [rsp + 20], 0         ; flash flag: untextured parts
    cmp     dword [rbx + MOB.type], MOB_CREEPER
    jne     .model
    mov     eax, [rbx + MOB.fuse]
    test    eax, eax
    jle     .model
    mov     ecx, 90
    cmp     eax, ecx
    cmova   eax, ecx                    ; swells with the fuse: up to 20 % bigger
    cvtsi2ss xmm0, eax
    mulss   xmm0, [f_swell]
    addss   xmm0, [f_one]
    movaps  xmm1, xmm0
    movaps  xmm2, xmm0
    call    glScalef
    mov     eax, [rbx + MOB.fuse]
    shr     eax, 2
    and     eax, 1                      ; white flash every other 4 steps
    mov     [rsp + 20], eax
    jz      .model
    mov     edi, GL_TEXTURE_2D
    call    glDisable
.model:
    shl     r13d, 4
    lea     rax, [models]
    mov     r14, [rax + r13]
    mov     r15d, [rax + r13 + 8]
.part:
    movss   xmm0, [r14 + P_SWING]
    xorps   xmm1, xmm1
    ucomiss xmm0, xmm1
    jne     .swung
    DRAW_PART
    jmp     .part_next
.swung:
    mulss   xmm0, [rsp]
    movss   [rsp + 16], xmm0
    call    glPushMatrix
    xorps   xmm0, xmm0
    movss   xmm1, [r14 + P_PIVOT_Y]
    movss   xmm2, [r14 + P_PIVOT_Z]
    call    glTranslatef
    movss   xmm0, [rsp + 16]
    movss   xmm1, [f_one]
    xorps   xmm2, xmm2
    xorps   xmm3, xmm3
    call    glRotatef
    xorps   xmm0, xmm0
    xorps   xmm1, xmm1
    subss   xmm1, [r14 + P_PIVOT_Y]
    xorps   xmm2, xmm2
    subss   xmm2, [r14 + P_PIVOT_Z]
    call    glTranslatef
    DRAW_PART
    call    glPopMatrix
.part_next:
    add     r14, PART_SIZE
    dec     r15d
    jnz     .part
    cmp     dword [rsp + 20], 0
    je      .unflash
    mov     edi, GL_TEXTURE_2D
    call    glEnable
.unflash:
    call    glPopMatrix
.next:
    add     rbx, MOB_size
    cmp     rbx, r12
    jb      .mob
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
