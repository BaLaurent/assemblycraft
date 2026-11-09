; mobrender.asm - zombie, pig, creeper, skeleton, spider and chicken box models, faction folk
; and the Fallen King boss, drawn with the state render_world leaves set up:
; atlas on unit 0, light map on unit 1 (each mob binds the light at its body centre), fog,
; alpha test, face culling.
; Model space has the front at -Z; limbs swing about X at their pivot. A mob is tinted by what it
; is doing and suffering (hit red, wind-up red flicker, a raging folk red, frozen and chilled blue,
; burning orange flicker, poisoned green, stun yellow flicker, a champion its faction colour, a
; captive grey, elite gold; first one wins) and sized by what it is (elite 1.2 x, wind-up surge
; 1.05 x, creeper swell). A folk wears its faction's skin plus one more part for its role.
%include "common.inc"
%include "gl.inc"
default rel

global mobs_render, mob_parts_draw, folk_tables

extern mobs, render_box16, sincos_deg, light_bind_at, light_bind_index

; part record: box (lo xyz, hi xyz), tile per face (+X -X +Y -Y +Z -Z, 16-bit atlas ids), pivot y,
; pivot z, swing factor (limb angle = factor * walk swing; 0 = rigid)
%define PART_SIZE 48
%define P_BOX     0
%define P_TILES   24
%define P_PIVOT_Y 36
%define P_PIVOT_Z 40
%define P_SWING   44

; PART x0, y0, z0, x1, y1, z1, tile, front tile (-Z face), pivot y, pivot z, swing
%macro PART 11
    dd %1, %2, %3, %4, %5, %6
    dw %7, %7, %7, %7, %7, %8
    dd %9, %10, %11
%endmacro

section .rodata
align 4
f_one:      dd 1.0
f_half:     dd 0.5
f_swing:    dd 30.0                     ; peak limb angle, degrees
mob_shades: dd 0.6, 0.6, 1.0, 0.5, 0.8, 0.8   ; +X -X +Y -Y +Z -Z
f_swell:    dd 0.0022222222             ; creeper swell: 20 % over 90 fuse steps
f_elite_g:  dd 0.85                     ; elite tint (1, 0.85, 0.5)
f_elite_b:  dd 0.5
f_wind_g:   dd 0.45                     ; wind-up flicker (1, 0.45, 0.45)
f_wind_b:   dd 0.45
f_stun_b:   dd 0.4                      ; stun flicker (1, 1, 0.4)
f_elite_scale: dd 1.2
f_wind_scale: dd 1.05
f_pois_r:   dd 0.75                     ; poisoned tint (0.75, 1, 0.6)
f_pois_b:   dd 0.6
f_burn_g:   dd 0.6                      ; burning flicker (1, 0.6, 0.3)
f_burn_b:   dd 0.3
f_chill_r:  dd 0.7                      ; chilled tint (0.7, 0.85, 1)
f_chill_g:  dd 0.85
f_frozen_r: dd 0.5                      ; frozen tint (0.5, 0.7, 1)
f_frozen_g: dd 0.7
f_p6:       dd 0.6                      ; captive grey (0.6, 0.6, 0.6); raging folk (1, 0.6, 0.6)
champion_tint:                          ; per faction, in place of the elite gold
    dd 1.0, 0.95, 0.6                   ; Villagers
    dd 1.0, 0.6, 0.6                    ; Bandits
    dd 0.75, 0.6, 0.85                  ; Ashen Cult
    dd 1.0, 0.85, 0.5                   ; Beastfolk
    dd 0.7, 0.85, 1.0                   ; Stonekin

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

; the villagers share one model, only the robe differs: legs, body, folded arms, head, nose
%macro VILLAGER 1
    PART -0.22, 0.0, -0.11,  0.0,  0.75, 0.11,  %1, %1, 0.75, 0.0,  1.0                 ; left leg
    PART  0.0,  0.0, -0.11,  0.22, 0.75, 0.11,  %1, %1, 0.75, 0.0, -1.0                 ; right leg
    PART -0.25, 0.75, -0.15, 0.25, 1.45, 0.15,  %1, %1, 0.0, 0.0, 0.0                   ; body
    PART -0.3,  1.1, -0.3,   0.3,  1.35, -0.15, %1, %1, 0.0, 0.0, 0.0                   ; folded arms
    PART -0.2,  1.45, -0.2,  0.2,  1.95, 0.2,   TILE_VILLAGER_SKIN, TILE_VILLAGER_FACE, 0.0, 0.0, 0.0   ; head
    PART -0.05, 1.55, -0.3,  0.05, 1.72, -0.2,  TILE_VILLAGER_SKIN, TILE_VILLAGER_SKIN, 0.0, 0.0, 0.0   ; nose
%endmacro
merchant_parts:
    VILLAGER TILE_MERCHANT_ROBE
elder_parts:
    VILLAGER TILE_ELDER_ROBE
%define VILLAGER_PARTS 6

; the folk share one model, only the skin differs: legs, body, arms, head
%macro FOLK 4
    PART -0.22, 0.0, -0.11,  0.0,  0.75, 0.11,  %4, %4, 0.75, 0.0,  1.0                 ; left leg
    PART  0.0,  0.0, -0.11,  0.22, 0.75, 0.11,  %4, %4, 0.75, 0.0, -1.0                 ; right leg
    PART -0.25, 0.75, -0.15, 0.25, 1.45, 0.15,  %3, %3, 0.0, 0.0, 0.0                   ; body
    PART -0.38, 0.75, -0.1, -0.25, 1.45, 0.1,   %3, %3, 1.4, 0.0, -1.0                  ; left arm
    PART  0.25, 0.75, -0.1,  0.38, 1.45, 0.1,   %3, %3, 1.4, 0.0,  1.0                  ; right arm
    PART -0.2,  1.45, -0.2,  0.2,  1.95, 0.2,   %1, %2, 0.0, 0.0, 0.0                   ; head
%endmacro
; FOLK_SKIN f: the skin tiles 304 + 4f .. 304 + 4f + 3 of faction f
%macro FOLK_SKIN 1
    FOLK TILE_FOLK0 + 4 * %1 + TILE_FOLK_HEAD, TILE_FOLK0 + 4 * %1 + TILE_FOLK_FACE, TILE_FOLK0 + 4 * %1 + TILE_FOLK_TUNIC, TILE_FOLK0 + 4 * %1 + TILE_FOLK_PANTS
%endmacro
%define FOLK_PARTS 6
folk_parts_villagers:
    FOLK_SKIN FAC_VILLAGERS
folk_parts_bandits:
    FOLK_SKIN FAC_BANDITS
folk_parts_cult:
    FOLK_SKIN FAC_CULT
folk_parts_beastfolk:
    FOLK_SKIN FAC_BEASTFOLK
folk_parts_stonekin:
    FOLK_SKIN FAC_STONEKIN

; role extras: one more rigid part on top of the model
extra_hat:                              ; non-Villagers leader
    PART -0.22, 1.85, -0.22,  0.22, 2.0, 0.22,  TILE_GOLD_BLOCK, TILE_GOLD_BLOCK, 0.0, 0.0, 0.0
extra_helmet:                           ; guard and patrol, except acolytes
    PART -0.22, 1.7, -0.22,  0.22, 2.0, 0.22,  TILE_IRON_BLOCK, TILE_IRON_BLOCK, 0.0, 0.0, 0.0
extra_pack:                             ; non-Villagers trader and any traveller
    PART -0.2, 0.85, 0.15,  0.2, 1.35, 0.35,  TILE_CHEST_SIDE, TILE_CHEST_SIDE, 0.0, 0.0, 0.0
extra_crown:                            ; champion
    PART -0.23, 1.95, -0.23,  0.23, 2.15, 0.23,  TILE_BOSS_CROWN, TILE_BOSS_CROWN, 0.0, 0.0, 0.0
extra_hoods:                            ; acolyte, one per faction in the faction's tunic tile
%assign hood_f 0
%rep 5
    PART -0.22, 1.7, -0.22,  0.22, 2.02, 0.22,  TILE_FOLK0 + 4 * hood_f + TILE_FOLK_TUNIC, TILE_FOLK0 + 4 * hood_f + TILE_FOLK_TUNIC, 0.0, 0.0, 0.0
%assign hood_f hood_f + 1
%endrep

boss_parts:                             ; the Fallen King, 3.3 blocks tall
    PART -0.35, 0.0, -0.12, -0.1,  1.3, 0.12,  TILE_SKELETON_BONE, TILE_SKELETON_BONE, 1.3, 0.0,  1.0   ; left leg
    PART  0.1,  0.0, -0.12,  0.35, 1.3, 0.12,  TILE_SKELETON_BONE, TILE_SKELETON_BONE, 1.3, 0.0, -1.0   ; right leg
    PART -0.45, 1.1, -0.25,  0.45, 2.4, 0.25,  TILE_BOSS_ROBE, TILE_BOSS_ROBE, 0.0, 0.0, 0.0           ; robe
    PART -0.7,  1.4, -0.12, -0.45, 2.4, 0.12,  TILE_SKELETON_BONE, TILE_SKELETON_BONE, 2.3, 0.0, -0.5   ; left arm
    PART  0.45, 1.4, -0.12,  0.7,  2.4, 0.12,  TILE_SKELETON_BONE, TILE_SKELETON_BONE, 2.3, 0.0,  0.5   ; right arm
    PART -0.35, 2.4, -0.35,  0.35, 3.1, 0.35,  TILE_SKELETON_BONE, TILE_BOSS_FACE, 0.0, 0.0, 0.0        ; head
    PART -0.38, 3.1, -0.38,  0.38, 3.35, 0.38, TILE_BOSS_CROWN, TILE_BOSS_CROWN, 0.0, 0.0, 0.0         ; crown
%define BOSS_PARTS 7

align 8
models:                                 ; indexed by type - 1: parts, part count
    dq zombie_parts, ZOMBIE_PARTS
    dq pig_parts, PIG_PARTS
    dq creeper_parts, CREEPER_PARTS
    dq skeleton_parts, SKELETON_PARTS
    dq spider_parts, SPIDER_PARTS
    dq chicken_parts, CHICKEN_PARTS
    dq boss_parts, BOSS_PARTS
    dq folk_parts_villagers, FOLK_PARTS  ; folk: folk_model picks the table

align 8
folk_tables:                            ; folk skins by faction
    dq folk_parts_villagers, folk_parts_bandits, folk_parts_cult, folk_parts_beastfolk
    dq folk_parts_stonekin

section .text

; DRAW_PART: render_box16 of the part at r14, tinted by the mob's hurt colour at [rsp + 4..12]
%macro DRAW_PART 0
    lea     rdi, [r14 + P_BOX]
    lea     rsi, [r14 + P_TILES]
    lea     rdx, [mob_shades]
    movss   xmm0, [rsp + 4]
    movss   xmm1, [rsp + 8]
    movss   xmm2, [rsp + 12]
    call    render_box16
%endmacro

; folk_model(rdi mob) -> rax = its 6-part table, rdx = its role extra part or 0
; The Villagers' leader wears elder_parts and their trader merchant_parts; every other folk its
; faction's skin. The extra: a champion's crown; else a hat for a leader of another faction; else
; a hood for an acolyte guard or patrol, a helmet for any other; else a pack for a traveller and a
; trader of another faction.
folk_model:
    movzx   ecx, byte [rdi + MOB.faction]
    movzx   r8d, byte [rdi + MOB.role]
    lea     rax, [folk_tables]
    mov     rax, [rax + rcx * 8]
    test    ecx, ecx
    jnz     .extra
    lea     rsi, [elder_parts]
    cmp     r8d, ROLE_LEADER
    cmove   rax, rsi
    lea     rsi, [merchant_parts]
    cmp     r8d, ROLE_TRADER
    cmove   rax, rsi
.extra:
    lea     rdx, [extra_crown]
    cmp     r8d, ROLE_CHAMPION
    je      .done
    cmp     r8d, ROLE_LEADER
    jne     .not_leader
    lea     rdx, [extra_hat]
    test    ecx, ecx
    jnz     .done
    jmp     .none
.not_leader:
    cmp     r8d, ROLE_GUARD
    je      .fighter
    cmp     r8d, ROLE_PATROL
    jne     .not_fighter
.fighter:
    lea     rdx, [extra_helmet]
    cmp     byte [rdi + MOB.fclass], FCLASS_ACOLYTE
    jne     .done
    imul    ecx, ecx, PART_SIZE
    lea     rdx, [extra_hoods]
    add     rdx, rcx
    ret
.not_fighter:
    lea     rdx, [extra_pack]
    cmp     r8d, ROLE_TRAVELLER
    je      .done
    cmp     r8d, ROLE_TRADER
    jne     .none
    test    ecx, ecx
    jnz     .done
.none:
    xor     edx, edx
.done:
    ret

; mob_parts_draw(rdi parts, rsi extra or 0, edx count, xmm0 swing_deg, xmm1 r, xmm2 g, xmm3 b): draw
; the first count parts of the table at rdi in the model space the caller has set up (translated to
; the feet, turned to the heading, scaled: see mobs_render), every one tinted (r, g, b); a part with
; a swing factor turns about X at its pivot by factor * swing_deg. Then the rigid part at rsi, when
; there is one (a role extra). mobs_render and peers_render (peerrender.asm) draw their bodies with it.
; r14 = part, r15d = parts left; stack: [rsp] swing, [rsp+4..12] tint rgb, [rsp+16] limb angle,
; [rsp+32] the extra part (0 once drawn)
mob_parts_draw:
    push    rbp
    mov     rbp, rsp
    push    r14
    push    r15
    sub     rsp, 48
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 8], xmm2
    movss   [rsp + 12], xmm3
    mov     [rsp + 32], rsi
    mov     r14, rdi
    mov     r15d, edx
    test    r15d, r15d
    jz      .extra
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
.extra:
    mov     r14, [rsp + 32]             ; then the role extra part, if any
    test    r14, r14
    jz      .done
    mov     qword [rsp + 32], 0
    mov     r15d, 1
    jmp     .part
.done:
    add     rsp, 48
    pop     r15
    pop     r14
    pop     rbp
    ret

; mobs_render(): draw every live mob.
; rbx = mob, r12 = end of the table, r13d = model index
; stack: [rsp] swing angle, [rsp+4..12] tint rgb, [rsp+20] flash flag, [rsp+24] size factor
mobs_render:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 40
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
    movss   xmm0, [f_one]               ; tint, lowest priority first: elite gold, stun flicker,
    movss   xmm1, xmm0                  ; poison green, burning flicker, chill blue, freeze blue,
    movss   xmm2, xmm0                  ; wind-up flicker, then the hit's red over everything
    cmp     dword [rbx + MOB.elite], 0
    je      .not_elite
    movss   xmm1, [f_elite_g]
    movss   xmm2, [f_elite_b]
.not_elite:
    cmp     dword [rbx + MOB.type], MOB_FOLK
    jne     .tint_status
    movzx   eax, byte [rbx + MOB.role]
    cmp     eax, ROLE_CAPTIVE
    jne     .not_captive
    movss   xmm0, [f_p6]                ; a captive is grey
    movaps  xmm1, xmm0
    movaps  xmm2, xmm0
    jmp     .tint_status
.not_captive:
    cmp     eax, ROLE_CHAMPION
    jne     .tint_status
    movzx   eax, byte [rbx + MOB.faction]
    lea     rax, [rax + rax * 2]
    lea     rcx, [champion_tint]
    movss   xmm0, [rcx + rax * 4]       ; a champion wears its faction's colour, not the elite gold
    movss   xmm1, [rcx + rax * 4 + 4]
    movss   xmm2, [rcx + rax * 4 + 8]
.tint_status:
    mov     eax, [rbx + MOB.stun]
    test    eax, eax
    jle     .not_stunned
    test    al, 4                       ; (stun >> 2) & 1: yellow flicker
    jz      .not_stunned
    movss   xmm1, [f_one]
    movss   xmm2, [f_stun_b]
.not_stunned:
    cmp     dword [rbx + MOB.poison_t], 0
    jle     .not_poisoned
    movss   xmm0, [f_pois_r]
    movss   xmm1, [f_one]
    movss   xmm2, [f_pois_b]
.not_poisoned:
    mov     eax, [rbx + MOB.burn_t]
    test    eax, eax
    jle     .not_burning
    test    al, 8                       ; (burn_t >> 3) & 1: orange flicker
    jz      .not_burning
    movss   xmm0, [f_one]
    movss   xmm1, [f_burn_g]
    movss   xmm2, [f_burn_b]
.not_burning:
    cmp     dword [rbx + MOB.chill_t], 0
    jle     .not_chilled
    movss   xmm0, [f_chill_r]
    movss   xmm1, [f_chill_g]
    movss   xmm2, [f_one]
.not_chilled:
    cmp     dword [rbx + MOB.freeze_cd], 0
    jle     .not_frozen
    cmp     dword [rbx + MOB.stun], 0
    jle     .not_frozen                 ; frozen: stunned by a freeze
    movss   xmm0, [f_frozen_r]
    movss   xmm1, [f_frozen_g]
    movss   xmm2, [f_one]
.not_frozen:
    cmp     dword [rbx + MOB.type], MOB_FOLK
    jne     .not_raging
    test    byte [rbx + MOB.fflags], FF_RAGE
    jz      .not_raging
    movss   xmm0, [f_one]               ; a raging berserker is red under the flickers
    movss   xmm1, [f_p6]
    movss   xmm2, [f_p6]
.not_raging:
    mov     eax, [rbx + MOB.windup]
    test    eax, eax
    jle     .not_winding
    test    al, 4                       ; (windup >> 2) & 1: red flicker
    jz      .not_winding
    movss   xmm0, [f_one]
    movss   xmm1, [f_wind_g]
    movss   xmm2, [f_wind_b]
.not_winding:
    cmp     dword [rbx + MOB.hurt], 0
    jle     .tinted
    movss   xmm0, [f_one]
    movss   xmm1, [f_half]              ; hit: red tint
    movss   xmm2, [f_half]
.tinted:
    movss   [rsp + 4], xmm0
    movss   [rsp + 8], xmm1
    movss   [rsp + 12], xmm2
    movss   xmm0, [rbx + BODY.height]   ; lit by the cell at the middle of the body
    mulss   xmm0, [f_half]
    addss   xmm0, [rbx + BODY.y]
    movaps  xmm1, xmm0
    movss   xmm0, [rbx + BODY.x]
    movss   xmm2, [rbx + BODY.z]
    call    light_bind_at
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
    movss   xmm0, [f_one]               ; size: creeper swell x elite x wind-up surge
    movss   [rsp + 24], xmm0
    cmp     dword [rbx + MOB.type], MOB_CREEPER
    jne     .size_elite
    mov     eax, [rbx + MOB.fuse]
    test    eax, eax
    jle     .size_elite
    mov     ecx, 90
    cmp     eax, ecx
    cmova   eax, ecx                    ; swells with the fuse: up to 20 % bigger
    cvtsi2ss xmm0, eax
    mulss   xmm0, [f_swell]
    addss   xmm0, [f_one]
    movss   [rsp + 24], xmm0
    mov     eax, [rbx + MOB.fuse]
    shr     eax, 2
    and     eax, 1                      ; white flash every other 4 steps
    mov     [rsp + 20], eax
.size_elite:
    cmp     dword [rbx + MOB.elite], 0
    je      .size_windup
    movss   xmm0, [rsp + 24]
    mulss   xmm0, [f_elite_scale]
    movss   [rsp + 24], xmm0
.size_windup:
    cmp     dword [rbx + MOB.windup], 0
    jle     .sized
    movss   xmm0, [rsp + 24]
    mulss   xmm0, [f_wind_scale]
    movss   [rsp + 24], xmm0
.sized:
    movss   xmm0, [rsp + 24]
    ucomiss xmm0, [f_one]
    je      .unscaled
    movaps  xmm1, xmm0
    movaps  xmm2, xmm0
    call    glScalef
.unscaled:
    cmp     dword [rsp + 20], 0
    je      .model
    mov     edi, GL_TEXTURE_2D
    call    glDisable
.model:
    shl     r13d, 4
    lea     rax, [models]
    mov     rdi, [rax + r13]            ; the model's parts and how many there are
    mov     edx, [rax + r13 + 8]
    xor     esi, esi                    ; no role extra part
    cmp     dword [rbx + MOB.type], MOB_FOLK
    jne     .draw
    mov     rdi, rbx
    call    folk_model                  ; rax = its 6-part table, rdx = its role extra part or 0
    mov     rdi, rax
    mov     rsi, rdx
    mov     edx, FOLK_PARTS
.draw:
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    movss   xmm3, [rsp + 12]
    call    mob_parts_draw
.parts_done:
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
    mov     edi, LIGHT_SKY_FULL
    call    light_bind_index
    add     rsp, 40
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
