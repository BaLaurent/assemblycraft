; explode.asm - explosions (creepers, TNT, rockets), magic blasts (fireballs, meteors, explosive
; arrows) and primed TNT. Primed TNT is a physics body: it hops when lit, falls, is thrown by
; blasts, and flashes white while it burns. It is not saved with the world; it lives in local
; coordinates (tnt_shift follows the origin, tnt_remove_box drops the TNT of a column that unloads).
%include "common.inc"
%include "gl.inc"
default rel

global explode_at, explode_magic, explode_dmg_mult, primed, tnt_prime, tnt_clear, tnt_step, tnt_render
global tnt_shift, tnt_remove_box

extern world_get, world_set, cont_block_removed, block_drop, drops_spawn, rng_next
extern block_removed, light_bind_at, light_bind_index
extern audio_play_at, player, settings, survival_damage, surv_max_health
extern mobs, mob_hurt, item_model_draw, body_init, body_step
extern combat_hit_mob, combat_kb_mult, rpg_stats, mob_is_hostile, block_hardness
extern fx_explosion, fx_debris

; explode_at frame (rsp-relative)
%define X_C     0                       ; float blast centre[3]
%define X_R2    12                      ; float r^2
%define X_RI    16                      ; int ceil(r)
%define X_BASE  20                      ; int floor(centre)[3]
%define X_F     32                      ; float 1 - d / 2r of the creature being hurt
%define X_DX    36                      ; float creature offset from the centre (x, z)
%define X_DZ    40
%define X_TWOR  44                      ; float 2r
%define X_K     48                      ; float r / 3
%define X_CELL  52                      ; int cell being cleared [3]
%define X_NDEB  64                      ; int blocks destroyed so far (every second: debris)
%define X_KBM   68                      ; float knockback factor on the player (Juggernaut: 0)
%define X_FRAME 72

; explode_magic frame (rsp-relative)
%define M_C     0                       ; float blast centre[3]
%define M_R     12                      ; float radius
%define M_DMG   16                      ; int damage at the centre
%define M_DX    20                      ; float mob offset from the centre (x, z)
%define M_DZ    24
%define M_SRC   28                      ; int SRC_* of the hits
%define M_FLAGS 32                      ; int HITF_* flags of the hits
%define M_BASE  36                      ; float damage the mob being hit takes, before the pipeline
%define M_FRAME 48

section .rodata
align 4
c_half:      dd 0.5
c_one:       dd 1.0
c_three:     dd 3.0
c_chest:     dd 0.9                     ; player centre above the feet
c_tiny:      dd 0.0001
c_kb:        dd 12.0                    ; player knockback speed at full strength
c_hop:       dd 6.0                     ; and the hop off the ground
c_mob_base:  dd 24.0                    ; mob damage at full strength for r = 3
c_blast:     dd 4.0                     ; primed TNT blast radius
c_tnt_half:  dd 0.49                    ; primed TNT body: half width, height, centre height
c_tnt_h:     dd 0.98
c_hop_up:    dd 2.0                     ; the little jump TNT makes when lit
c_hundred:   dd 100.0
c_throw:     dd 14.0                    ; blast push on primed TNT at full strength
c_lift:      dd 5.0                     ; and the extra upward kick
f_one:       dd 1.0
c_magic_fx:  dd 0.7                     ; magic blast: fireball radius / blast radius
c_magic_vol: dd 0.6
c_magic_kb:  dd 1.5                     ; push on a mob: along unit(mob - centre).xz
base_dmg:    dd 8, 12, 22, 33           ; player damage at full strength for r = 3, by difficulty
c_twenty:    dd 20.0                    ; the player's damage scales with max health / 20

section .data
align 4
explode_dmg_mult: dd 0.0                ; > 0: factor on the damage a blast does to the player (a creeper
                                        ; of a level sets it); 0: max health / 20

section .bss
alignb 16
primed:      resb MAX_PRIMED * PRIMED_size
primed_end:
zero_input:  resb INPUT_size            ; primed TNT has no controls

section .text

; tnt_clear(): no primed TNT
tnt_clear:
    lea     rdi, [primed]
    mov     ecx, MAX_PRIMED * PRIMED_size
    xor     eax, eax
    rep     stosb
    ret

; tnt_prime(edi x, esi y, edx z, ecx fuse): the block there becomes air and a primed TNT with
; that fuse (steps, at least 1) sits in its cell, hopping slightly. When every slot burns, the
; one with the shortest fuse is replaced.
tnt_prime:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edx
    mov     ebx, ecx
    mov     eax, 1
    cmp     ebx, eax
    cmovl   ebx, eax
    xor     ecx, ecx
    call    world_set                   ; edi, esi, edx are still x, y, z
    mov     edi, r12d                   ; what hung on the TNT pops off
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, TNT
    call    block_removed
    lea     rcx, [primed]
    mov     r15, rcx                    ; slot to use
    mov     edx, 0x7FFFFFFF             ; shortest fuse seen
.find:
    mov     esi, [rcx + PRIMED.fuse]
    test    esi, esi
    jz      .free
    cmp     esi, edx
    jge     .next
    mov     edx, esi
    mov     r15, rcx
.next:
    add     rcx, PRIMED_size
    lea     rsi, [primed_end]
    cmp     rcx, rsi
    jb      .find
    jmp     .fill
.free:
    mov     r15, rcx
.fill:
    mov     rdi, r15
    movss   xmm0, [c_tnt_half]
    movss   xmm1, [c_tnt_h]
    xorps   xmm2, xmm2                  ; it never walks
    call    body_init
    movss   xmm1, [c_half]
    cvtsi2ss xmm0, r12d
    addss   xmm0, xmm1
    movss   [r15 + PRIMED.body + BODY.x], xmm0
    cvtsi2ss xmm0, r13d
    movss   [r15 + PRIMED.body + BODY.y], xmm0
    cvtsi2ss xmm0, r14d
    addss   xmm0, xmm1
    movss   [r15 + PRIMED.body + BODY.z], xmm0
    movss   xmm0, [c_hop_up]
    movss   [r15 + PRIMED.body + BODY.vy], xmm0
    call    hop_unit
    movss   [r15 + PRIMED.body + BODY.kbx], xmm0
    call    hop_unit
    movss   [r15 + PRIMED.body + BODY.kbz], xmm0
    mov     [r15 + PRIMED.fuse], ebx
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; hop_unit() -> xmm0 uniform in [-1, 1] blocks/s (steps of 0.01)
hop_unit:
    sub     rsp, 8
    call    rng_next
    xor     edx, edx
    mov     ecx, 201
    div     ecx
    sub     edx, 100
    cvtsi2ss xmm0, edx
    divss   xmm0, [c_hundred]
    add     rsp, 8
    ret

; tnt_step(): every primed TNT moves (gravity, collisions, blast pushes decaying) and burns
; down; at 0 it blows with radius 4 from its centre. The slot is freed before the blast, so
; TNT primed by it may reuse the slot (their fuses are >= 10).
tnt_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16                     ; saved push (kbx, kbz)
    lea     rbx, [primed]
    lea     r12, [primed_end]
.loop:
    cmp     dword [rbx + PRIMED.fuse], 0
    je      .next
    mov     eax, [rbx + PRIMED.body + BODY.kbx]
    mov     [rsp], eax                  ; body_step decays the push; only friction should
    mov     eax, [rbx + PRIMED.body + BODY.kbz]
    mov     [rsp + 4], eax
    mov     rdi, rbx
    lea     rsi, [zero_input]
    call    body_step
    cmp     dword [rbx + PRIMED.body + BODY.on_ground], 0
    jne     .fuse                       ; sliding on the ground: friction (body_step's decay)
    cmp     dword [rbx + PRIMED.body + BODY.blocked], 0
    jne     .stopped                    ; hit a wall
    mov     eax, [rsp]                  ; flying: no air drag
    mov     [rbx + PRIMED.body + BODY.kbx], eax
    mov     eax, [rsp + 4]
    mov     [rbx + PRIMED.body + BODY.kbz], eax
    jmp     .fuse
.stopped:
    mov     dword [rbx + PRIMED.body + BODY.kbx], 0
    mov     dword [rbx + PRIMED.body + BODY.kbz], 0
.fuse:
    mov     eax, [rbx + PRIMED.fuse]
    dec     eax
    mov     [rbx + PRIMED.fuse], eax
    jnz     .next
    movss   xmm0, [rbx + PRIMED.body + BODY.x]
    movss   xmm1, [rbx + PRIMED.body + BODY.y]
    addss   xmm1, [c_tnt_half]
    movss   xmm2, [rbx + PRIMED.body + BODY.z]
    movss   xmm3, [c_blast]
    call    explode_at
.next:
    add     rbx, PRIMED_size
    cmp     rbx, r12
    jb      .loop
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; tnt_render(): every primed TNT as a block-sized TNT model, flashing white (untextured)
; every other 8 steps. Called inside the world pass (atlas bound, alpha test on).
tnt_render:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    lea     rbx, [primed]
    lea     r12, [primed_end]
.loop:
    mov     eax, [rbx + PRIMED.fuse]
    test    eax, eax
    jz      .next
    shr     eax, 3
    and     eax, 1
    mov     [rsp], eax                  ; flash this frame?
    movss   xmm0, [rbx + PRIMED.body + BODY.x] ; lit by the cell it sits in
    movss   xmm1, [rbx + PRIMED.body + BODY.y]
    addss   xmm1, [c_tnt_half]
    movss   xmm2, [rbx + PRIMED.body + BODY.z]
    call    light_bind_at
    call    glPushMatrix
    movss   xmm0, [rbx + PRIMED.body + BODY.x]
    movss   xmm1, [rbx + PRIMED.body + BODY.y]
    addss   xmm1, [c_tnt_half]
    movss   xmm2, [rbx + PRIMED.body + BODY.z]
    call    glTranslatef
    cmp     dword [rsp], 0
    je      .draw
    mov     edi, GL_TEXTURE_2D
    call    glDisable
.draw:
    mov     edi, TNT
    movss   xmm0, [f_one]
    call    item_model_draw
    cmp     dword [rsp], 0
    je      .pop
    mov     edi, GL_TEXTURE_2D
    call    glEnable
.pop:
    call    glPopMatrix
.next:
    add     rbx, PRIMED_size
    cmp     rbx, r12
    jb      .loop
    mov     edi, LIGHT_SKY_FULL         ; the entities after this one are lit by their own cells
    call    light_bind_index
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; explode_at(xmm0 x, xmm1 y, xmm2 z, xmm3 radius)
; 1. every block whose centre lies within the radius is destroyed (an unbreakable one, hardness < 0:
;    bedrock, a shrine, water, stays; TNT is primed with a 10..29 step fuse, 3 in 10 blocks drop
;    their item, containers spill);
; 2. the player within 2r takes ceil(f * base * r / 3), f = 1 - d / 2r, d measured to his chest
;    (survival_damage decides whether it applies), and is thrown away from the blast;
; 3. every mob within 2r takes ceil(f * 24 * r / 3) and is knocked away;
; 4. every primed TNT within 2r is thrown away (14 f, plus 5 f upwards).
; Effects: fx_explosion at the centre, fx_debris for every second destroyed block.
; r12d, r13d, r14d = x, y, z offsets of the cell from floor(centre) while sweeping blocks;
; r12d = mob index, rbx = mob while hurting mobs.
explode_at:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, X_FRAME
    movss   [rsp + X_C], xmm0
    movss   [rsp + X_C + 4], xmm1
    movss   [rsp + X_C + 8], xmm2
    movaps  xmm4, xmm3
    mulss   xmm4, xmm4
    movss   [rsp + X_R2], xmm4
    movaps  xmm4, xmm3
    addss   xmm4, xmm4
    movss   [rsp + X_TWOR], xmm4
    movaps  xmm4, xmm3
    divss   xmm4, [c_three]
    movss   [rsp + X_K], xmm4
    roundss xmm3, xmm3, 10              ; ceil(r)
    cvttss2si eax, xmm3
    mov     [rsp + X_RI], eax
    xor     ecx, ecx
.base:                                  ; the cell holding the centre
    movss   xmm0, [rsp + X_C + rcx*4]
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    mov     [rsp + X_BASE + rcx*4], eax
    inc     ecx
    cmp     ecx, 3
    jb      .base
    mov     edi, SND_EXPLODE
    movss   xmm0, [rsp + X_C]
    movss   xmm1, [rsp + X_C + 4]
    movss   xmm2, [rsp + X_C + 8]
    movss   xmm3, [c_one]
    call    audio_play_at
    movss   xmm0, [rsp + X_C]           ; fireball, smoke, shake and flash
    movss   xmm1, [rsp + X_C + 4]
    movss   xmm2, [rsp + X_C + 8]
    movss   xmm3, [rsp + X_TWOR]
    mulss   xmm3, [c_half]
    call    fx_explosion
    mov     dword [rsp + X_NDEB], 0

    ; ---- blocks --------------------------------------------------------------------
    mov     r14d, [rsp + X_RI]
    neg     r14d                        ; dz
.lz:
    mov     r13d, [rsp + X_RI]
    neg     r13d                        ; dy
.ly:
    mov     r12d, [rsp + X_RI]
    neg     r12d                        ; dx
.lx:
    mov     eax, [rsp + X_BASE]
    add     eax, r12d
    mov     [rsp + X_CELL], eax
    cvtsi2ss xmm0, eax
    addss   xmm0, [c_half]
    subss   xmm0, [rsp + X_C]
    mulss   xmm0, xmm0
    mov     eax, [rsp + X_BASE + 4]
    add     eax, r13d
    mov     [rsp + X_CELL + 4], eax
    cvtsi2ss xmm1, eax
    addss   xmm1, [c_half]
    subss   xmm1, [rsp + X_C + 4]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    mov     eax, [rsp + X_BASE + 8]
    add     eax, r14d
    mov     [rsp + X_CELL + 8], eax
    cvtsi2ss xmm1, eax
    addss   xmm1, [c_half]
    subss   xmm1, [rsp + X_C + 8]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [rsp + X_R2]
    ja      .cell_next                  ; centre outside the blast
    mov     edi, [rsp + X_CELL]
    mov     esi, [rsp + X_CELL + 4]
    mov     edx, [rsp + X_CELL + 8]
    call    world_get
    test    eax, eax
    jz      .cell_next                  ; air (or outside the world)
    lea     rcx, [block_hardness]
    xorps   xmm0, xmm0
    comiss  xmm0, [rcx + rax*4]
    ja      .cell_next                  ; unbreakable: bedrock, shrines (and water) stay
    cmp     eax, TNT
    je      .prime
    mov     ebx, eax                    ; block id
    mov     edi, [rsp + X_CELL]
    mov     esi, [rsp + X_CELL + 4]
    mov     edx, [rsp + X_CELL + 8]
    call    cont_block_removed
    mov     edi, [rsp + X_CELL]
    mov     esi, [rsp + X_CELL + 4]
    mov     edx, [rsp + X_CELL + 8]
    xor     ecx, ecx
    call    world_set
    mov     edi, [rsp + X_CELL]
    mov     esi, [rsp + X_CELL + 4]
    mov     edx, [rsp + X_CELL + 8]
    mov     ecx, ebx
    call    block_removed               ; torches and ladders on the block pop off, a door loses its half
    inc     dword [rsp + X_NDEB]        ; every second destroyed block flies off as debris
    mov     eax, [rsp + X_NDEB]
    xor     edx, edx
    mov     ecx, 2
    div     ecx
    cmp     edx, 1
    jne     .no_debris
    cmp     ebx, FIRE
    je      .no_debris
    mov     edi, [rsp + X_CELL]
    mov     esi, [rsp + X_CELL + 4]
    mov     edx, [rsp + X_CELL + 8]
    mov     ecx, ebx
    movss   xmm0, [rsp + X_C]
    movss   xmm1, [rsp + X_C + 4]
    movss   xmm2, [rsp + X_C + 8]
    call    fx_debris
.no_debris:
    call    rng_next                    ; 3 in 10 blocks drop their item
    xor     edx, edx
    mov     ecx, 10
    div     ecx
    cmp     edx, 3
    jae     .cell_next
    movzx   edi, byte [block_drop + rbx]
    test    edi, edi
    jz      .cell_next
    mov     esi, 1
    xor     edx, edx
    movss   xmm3, [c_half]
    cvtsi2ss xmm0, dword [rsp + X_CELL]
    addss   xmm0, xmm3
    cvtsi2ss xmm1, dword [rsp + X_CELL + 4]
    addss   xmm1, xmm3
    cvtsi2ss xmm2, dword [rsp + X_CELL + 8]
    addss   xmm2, xmm3
    call    drops_spawn
    jmp     .cell_next
.prime:                                 ; the blast sets TNT off: fuse 10 + rng % 20
    call    rng_next
    xor     edx, edx
    mov     ecx, 20
    div     ecx
    lea     ecx, [rdx + 10]
    mov     edi, [rsp + X_CELL]
    mov     esi, [rsp + X_CELL + 4]
    mov     edx, [rsp + X_CELL + 8]
    call    tnt_prime
.cell_next:
    inc     r12d
    cmp     r12d, [rsp + X_RI]
    jle     .lx
    inc     r13d
    cmp     r13d, [rsp + X_RI]
    jle     .ly
    inc     r14d
    cmp     r14d, [rsp + X_RI]
    jle     .lz

    ; ---- the player ---------------------------------------------------------------
    movss   xmm0, [player + BODY.x]
    subss   xmm0, [rsp + X_C]
    movss   [rsp + X_DX], xmm0
    movss   xmm1, [player + BODY.y]
    addss   xmm1, [c_chest]
    subss   xmm1, [rsp + X_C + 4]
    movss   xmm2, [player + BODY.z]
    subss   xmm2, [rsp + X_C + 8]
    movss   [rsp + X_DZ], xmm2
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    mulss   xmm2, xmm2
    addss   xmm0, xmm1
    addss   xmm0, xmm2
    sqrtss  xmm0, xmm0                  ; d
    comiss  xmm0, [rsp + X_TWOR]
    jae     .mobs                       ; out of range
    divss   xmm0, [rsp + X_TWOR]
    movss   xmm1, [c_one]
    subss   xmm1, xmm0                  ; f
    movss   [rsp + X_F], xmm1
    mov     eax, [settings + SETTINGS.difficulty]
    mov     ecx, DIFF_HARD
    cmp     eax, ecx
    cmova   eax, ecx
    cvtsi2ss xmm0, dword [base_dmg + rax*4]
    mulss   xmm0, xmm1
    mulss   xmm0, [rsp + X_K]
    movss   xmm2, [explode_dmg_mult]    ; the creeper's factor, else max health / 20
    xorps   xmm3, xmm3
    comiss  xmm2, xmm3
    ja      .have_mult
    cvtsi2ss xmm2, dword [surv_max_health]
    divss   xmm2, [c_twenty]
.have_mult:
    mulss   xmm0, xmm2
    roundss xmm0, xmm0, 10              ; ceil
    cvttss2si edi, xmm0
    mov     esi, CAUSE_EXPLOSION
    call    survival_damage
    test    eax, eax
    jz      .mobs                       ; invulnerable, creative or dead: no knockback either
    call    combat_kb_mult              ; Juggernaut: no knockback
    movss   [rsp + X_KBM], xmm0
    movss   xmm0, [rsp + X_DX]
    movss   xmm1, [rsp + X_DZ]
    movaps  xmm2, xmm0
    mulss   xmm2, xmm2
    movaps  xmm3, xmm1
    mulss   xmm3, xmm3
    addss   xmm2, xmm3
    sqrtss  xmm2, xmm2                  ; horizontal distance
    comiss  xmm2, [c_tiny]
    jb      .hop                        ; straight above or below the blast
    movss   xmm3, [rsp + X_F]
    mulss   xmm3, [c_kb]
    mulss   xmm3, [rsp + X_KBM]
    divss   xmm3, xmm2                  ; 12 f / h
    mulss   xmm0, xmm3
    mulss   xmm1, xmm3
    movss   [player + BODY.kbx], xmm0
    movss   [player + BODY.kbz], xmm1
.hop:
    cmp     dword [player + BODY.on_ground], 0
    je      .mobs
    movss   xmm0, [rsp + X_F]
    mulss   xmm0, [c_hop]
    mulss   xmm0, [rsp + X_KBM]         ; Juggernaut is not thrown up either
    movss   [player + BODY.vy], xmm0

    ; ---- the mobs -----------------------------------------------------------------
.mobs:
    lea     rbx, [mobs]
    xor     r12d, r12d
.mob:
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .mob_next
    movss   xmm0, [rbx + BODY.x]
    subss   xmm0, [rsp + X_C]
    movss   [rsp + X_DX], xmm0
    movss   xmm1, [rbx + BODY.height]
    mulss   xmm1, [c_half]
    addss   xmm1, [rbx + BODY.y]
    subss   xmm1, [rsp + X_C + 4]       ; from the middle of the body
    movss   xmm2, [rbx + BODY.z]
    subss   xmm2, [rsp + X_C + 8]
    movss   [rsp + X_DZ], xmm2
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    mulss   xmm2, xmm2
    addss   xmm0, xmm1
    addss   xmm0, xmm2
    sqrtss  xmm0, xmm0
    comiss  xmm0, [rsp + X_TWOR]
    jae     .mob_next
    divss   xmm0, [rsp + X_TWOR]
    movss   xmm1, [c_one]
    subss   xmm1, xmm0                  ; f
    mulss   xmm1, [c_mob_base]
    mulss   xmm1, [rsp + X_K]
    roundss xmm1, xmm1, 10
    cvttss2si r13d, xmm1                ; damage
    movss   xmm0, [rsp + X_DX]
    movss   xmm1, [rsp + X_DZ]
    movaps  xmm2, xmm0
    mulss   xmm2, xmm2
    movaps  xmm3, xmm1
    mulss   xmm3, xmm3
    addss   xmm2, xmm3
    sqrtss  xmm2, xmm2
    comiss  xmm2, [c_tiny]
    jb      .shove_none
    divss   xmm0, xmm2                  ; unit vector away from the blast
    divss   xmm1, xmm2
    jmp     .hurt
.shove_none:
    xorps   xmm0, xmm0
    xorps   xmm1, xmm1
.hurt:
    mov     edi, r12d
    mov     esi, r13d
    call    mob_hurt
.mob_next:
    add     rbx, MOB_size
    inc     r12d
    cmp     r12d, MAX_MOBS
    jb      .mob

    ; ---- primed TNT: thrown away from the blast (chain-lit TNT included) -----------
    lea     rbx, [primed]
.tnt:
    cmp     dword [rbx + PRIMED.fuse], 0
    je      .tnt_next
    movss   xmm0, [rbx + PRIMED.body + BODY.x]
    subss   xmm0, [rsp + X_C]
    movss   xmm1, [rbx + PRIMED.body + BODY.y]
    addss   xmm1, [c_tnt_half]
    subss   xmm1, [rsp + X_C + 4]
    movss   xmm2, [rbx + PRIMED.body + BODY.z]
    subss   xmm2, [rsp + X_C + 8]
    movaps  xmm3, xmm0
    mulss   xmm3, xmm3
    movaps  xmm4, xmm1
    mulss   xmm4, xmm4
    addss   xmm3, xmm4
    movaps  xmm4, xmm2
    mulss   xmm4, xmm4
    addss   xmm3, xmm4
    sqrtss  xmm3, xmm3                  ; d
    comiss  xmm3, [rsp + X_TWOR]
    jae     .tnt_next
    comiss  xmm3, [c_tiny]
    jae     .tnt_dir
    xorps   xmm0, xmm0                  ; right at the centre: straight up
    movss   xmm1, [c_one]
    xorps   xmm2, xmm2
    xorps   xmm5, xmm5
    jmp     .tnt_push
.tnt_dir:
    movaps  xmm5, xmm3
    divss   xmm5, [rsp + X_TWOR]        ; d / 2r
    divss   xmm0, xmm3                  ; unit vector away from the blast
    divss   xmm1, xmm3
    divss   xmm2, xmm3
.tnt_push:
    movss   xmm4, [c_one]
    subss   xmm4, xmm5                  ; f
    movaps  xmm6, xmm4
    mulss   xmm6, [c_throw]             ; 14 f
    mulss   xmm0, xmm6
    mulss   xmm1, xmm6
    mulss   xmm2, xmm6
    mulss   xmm4, [c_lift]
    addss   xmm1, xmm4                  ; + 5 f upwards
    movss   [rbx + PRIMED.body + BODY.kbx], xmm0
    movss   [rbx + PRIMED.body + BODY.vy], xmm1
    movss   [rbx + PRIMED.body + BODY.kbz], xmm2
    mov     dword [rbx + PRIMED.body + BODY.on_ground], 0
.tnt_next:
    add     rbx, PRIMED_size
    lea     rax, [primed_end]
    cmp     rbx, rax
    jb      .tnt
    add     rsp, X_FRAME
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; explode_magic(xmm0 x, xmm1 y, xmm2 z, xmm3 radius, edi damage, esi src, edx flags): a magic blast of
; radius * (1 + AREA / 100). Draws the explosion at 0.7 r and plays its sound; then every live mob
; whose body middle lies within r of the centre (a folk only while it is hostile: mob_is_hostile)
; takes combat_hit_mob(src, flags, damage * (1 - 0.5 d / r)) and is pushed 1.5 away along
; (mob - centre).xz. Blocks, TNT and the player are never touched.
; rbx = mob, r12d = mob index.
explode_magic:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, M_FRAME
    movss   [rsp + M_C], xmm0
    movss   [rsp + M_C + 4], xmm1
    movss   [rsp + M_C + 8], xmm2
    mov     [rsp + M_DMG], edi
    mov     [rsp + M_SRC], esi
    mov     [rsp + M_FLAGS], edx
    cvtsi2ss xmm4, dword [rpg_stats + STAT_AREA * 4]
    divss   xmm4, [c_hundred]
    addss   xmm4, [c_one]
    mulss   xmm3, xmm4                  ; r * (1 + AREA / 100)
    movss   [rsp + M_R], xmm3
    mulss   xmm3, [c_magic_fx]
    call    fx_explosion                ; xmm0..2 are still the centre
    mov     edi, SND_EXPLODE
    movss   xmm0, [rsp + M_C]
    movss   xmm1, [rsp + M_C + 4]
    movss   xmm2, [rsp + M_C + 8]
    movss   xmm3, [c_magic_vol]
    call    audio_play_at
    lea     rbx, [mobs]
    xor     r12d, r12d
.mob:
    mov     eax, [rbx + MOB.type]
    test    eax, eax
    jz      .next
    cmp     eax, MOB_FOLK
    jne     .reach
    mov     edi, r12d
    call    mob_is_hostile              ; a blast touches only the folk that are in the fight
    test    eax, eax
    jz      .next
.reach:
    movss   xmm0, [rbx + BODY.x]
    subss   xmm0, [rsp + M_C]
    movss   [rsp + M_DX], xmm0
    movss   xmm1, [rbx + BODY.height]
    mulss   xmm1, [c_half]
    addss   xmm1, [rbx + BODY.y]
    subss   xmm1, [rsp + M_C + 4]       ; from the middle of the body
    movss   xmm2, [rbx + BODY.z]
    subss   xmm2, [rsp + M_C + 8]
    movss   [rsp + M_DZ], xmm2
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    mulss   xmm2, xmm2
    addss   xmm0, xmm1
    addss   xmm0, xmm2
    sqrtss  xmm0, xmm0                  ; d
    comiss  xmm0, [rsp + M_R]
    jae     .next                       ; out of range (also every mob when r = 0)
    divss   xmm0, [rsp + M_R]
    mulss   xmm0, [c_half]
    movss   xmm1, [c_one]
    subss   xmm1, xmm0                  ; 1 - 0.5 d / r
    cvtsi2ss xmm0, dword [rsp + M_DMG]
    mulss   xmm0, xmm1
    movss   [rsp + M_BASE], xmm0
    movss   xmm0, [rsp + M_DX]
    movss   xmm1, [rsp + M_DZ]
    movaps  xmm2, xmm0
    mulss   xmm2, xmm2
    movaps  xmm3, xmm1
    mulss   xmm3, xmm3
    addss   xmm2, xmm3
    sqrtss  xmm2, xmm2                  ; horizontal distance
    comiss  xmm2, [c_tiny]
    jb      .still                      ; straight above or below the blast
    divss   xmm0, xmm2
    divss   xmm1, xmm2
    mulss   xmm0, [c_magic_kb]
    mulss   xmm1, [c_magic_kb]
    jmp     .strike
.still:
    xorps   xmm0, xmm0
    xorps   xmm1, xmm1
.strike:
    movaps  xmm2, xmm1                  ; dirz
    movaps  xmm1, xmm0                  ; dirx
    movss   xmm0, [rsp + M_BASE]
    mov     edi, r12d
    mov     esi, [rsp + M_SRC]
    mov     edx, [rsp + M_FLAGS]
    call    combat_hit_mob
.next:
    add     rbx, MOB_size
    inc     r12d
    cmp     r12d, MAX_MOBS
    jb      .mob
    add     rsp, M_FRAME
    pop     r12
    pop     rbx
    pop     rbp
    ret

; tnt_shift(edi dx, esi dz): the origin moved by (dx, dz) blocks: every primed TNT's local x and z
; drop by that much (exact: dx and dz are multiples of 512)
tnt_shift:
    cvtsi2ss xmm0, edi
    cvtsi2ss xmm1, esi
    lea     rax, [primed]
    lea     rcx, [primed_end]
.l:
    cmp     dword [rax + PRIMED.fuse], 0
    je      .next
    movss   xmm2, [rax + PRIMED.body + BODY.x]
    subss   xmm2, xmm0
    movss   [rax + PRIMED.body + BODY.x], xmm2
    movss   xmm2, [rax + PRIMED.body + BODY.z]
    subss   xmm2, xmm1
    movss   [rax + PRIMED.body + BODY.z], xmm2
.next:
    add     rax, PRIMED_size
    cmp     rax, rcx
    jb      .l
    ret

; tnt_remove_box(edi x0, esi z0, edx x1, ecx z1): every primed TNT whose cell (the floor of its x
; and z) lies in the inclusive local box x0..x1, z0..z1 is gone, without a blast
tnt_remove_box:
    lea     rax, [primed]
    lea     r8, [primed_end]
.l:
    cmp     dword [rax + PRIMED.fuse], 0
    je      .next
    movss   xmm0, [rax + PRIMED.body + BODY.x]
    roundss xmm0, xmm0, 9
    cvttss2si r9d, xmm0
    cmp     r9d, edi
    jl      .next
    cmp     r9d, edx
    jg      .next
    movss   xmm0, [rax + PRIMED.body + BODY.z]
    roundss xmm0, xmm0, 9
    cvttss2si r9d, xmm0
    cmp     r9d, esi
    jl      .next
    cmp     r9d, ecx
    jg      .next
    mov     dword [rax + PRIMED.fuse], 0
.next:
    add     rax, PRIMED_size
    cmp     rax, r8
    jb      .l
    ret
