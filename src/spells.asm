; spells.asm - the runes: sixteen attributes the player casts together. Hold the rune keys, or tap them
; shortly before (SPELL_ARM_STEPS), then press the Cast key: the stack is every rune held or armed.
; spells_resolve turns a stack and the unlocked runes into a SPELLPLAN (the rules are in the comment
; above it); spells_cast pays for and fires it. A delivery rune (Ball, Laser, Nova, Phase, Dash) carries
; the element runes (Fire, Frost, Shock, Poison: each deals its share of the damage as a hit of its own
; element, so a status of each lands), the modifier runes that apply to it (Burst, Pierce, Seek, Chain)
; and the boons (Heal, Haste, Feather) follow it. Elements or modifiers without a delivery borrow the
; Ball when it is unlocked, boons alone are a self cast. Nothing is scaled here: a hit is a
; combat_hit_mob or explode_magic call and the damage pipeline applies the stats, the element, the
; resistances and the crit multiplier. The Ball is a PROJ_SPELL of arrows.asm: spells_proj_steer,
; spells_proj_hit and spells_proj_end are its hooks, and arrow_spell / arrow_hitmask its side tables.
%include "common.inc"
default rel

global rune_tab, spell_fx, spells_cd, spells_cd_total, spells_armed, spells_held
global spells_resolve, spells_input, spells_cast, spells_step, spells_reset, spells_preview
global spells_proj_hit, spells_proj_end, spells_proj_steer, spells_beam_fx

extern player, mobs, surv, surv_max_health
extern rpg_runes, rpg_stat, rpg_stats
extern combat_pay, combat_heal, combat_haste_t, combat_feather_t, combat_stealth_t, combat_hit_mob
extern arrows, arrows_spawn, arrow_spell, arrow_hitmask
extern mobs_raycast_skip, mob_is_hostile, raycast, ray_aabb
extern explode_magic, fx_burst
extern ab_crit, ab_sweep, ab_burst, ab_box_free
extern audio_play, hand_swing, net_swing_t, net_applying, net_spell_beam_out
extern str_append, i32_to_str

%define BALL_SPEED      28.0
%define LASER_VICTIMS   8               ; mobs one beam can strike
%define CHAIN_TARGETS   2               ; mobs a Chain arcs on to
%define PIERCE_HITS     3               ; mobs a Pierce ball goes through

section .rodata.str progbits alloc noexec nowrite align=1
s_nothing:  db "Nothing to cast", 0
s_plus:     db " + ", 0
s_gap:      db "  ", 0
s_mana:     db " mana", 0
s_inert:    db " (inert: ", 0
s_dropped:  db " (dropped: ", 0
s_comma:    db ", ", 0
s_close:    db ")", 0

; RUNE name, description, mana, cooldown in steps, base damage of a delivery rune
%macro RUNE 5
section .rodata.str
%%n: db %1, 0
%%d: db %2, 0
section .rodata
    dq %%n, %%d
    dd %3, %4, %5, 0
%endmacro

section .rodata
align 8
rune_tab:                               ; by rune id
    RUNE "Ball",    "A bolt of power that flies straight",      10,  30, 6
    RUNE "Laser",   "A beam through every foe in line",         16,  90, 5
    RUNE "Nova",    "A burst all around you",                   18, 240, 5
    RUNE "Phase",   "Teleport where you look",                  14, 240, 4
    RUNE "Dash",    "A surge forward, untouchable for a moment", 8, 120, 4
    RUNE "Fire",    "The spell burns",                           6,   0, 0
    RUNE "Frost",   "The spell chills, then freezes",            6,   0, 0
    RUNE "Shock",   "Shocked foes take more damage",             6,   0, 0
    RUNE "Poison",  "The spell poisons, stacking",               6,   0, 0
    RUNE "Burst",   "An explosion where the spell lands",       10,  60, 0
    RUNE "Pierce",  "Goes through more foes and reaches further", 6,  0, 0
    RUNE "Seek",    "The Ball homes in on a foe",                6,   0, 0
    RUNE "Chain",   "Arcs on to two more foes",                  8,  30, 0
    RUNE "Heal",    "Restore health",                           20, 240, 0
    RUNE "Haste",   "Move faster for ten seconds",              12, 300, 0
    RUNE "Feather", "Leap, then fall gently",                   10, 180, 0
%if $ - rune_tab != NUM_RUNES * RUNEINFO_size
%error "rune_tab needs one record per rune"
%endif

; the modifiers each delivery takes (rune masks), by delivery rune id
spell_applies:
    dd (1 << RUNE_BURST) | (1 << RUNE_PIERCE) | (1 << RUNE_SEEK) | (1 << RUNE_CHAIN)    ; Ball
    dd (1 << RUNE_BURST) | (1 << RUNE_PIERCE) | (1 << RUNE_CHAIN)                       ; Laser
    dd 1 << RUNE_BURST                                                                  ; Nova
    dd 1 << RUNE_BURST                                                                  ; Phase
    dd 1 << RUNE_BURST                                                                  ; Dash

; the particle kind of an element (ELEM_PHYS .. ELEM_POISON; the rest never occurs)
spell_fx:
    dd FX_MAGIC, FX_FIRE, FX_FROST, FX_SPARK, FX_POISON, FX_MAGIC, FX_MAGIC, FX_MAGIC

align 4
k_one:      dd 1.0
k_half:     dd 0.5
k_hundred:  dd 100.0
k_tiny:     dd 0.0001
k_2:        dd 2.0
k_2_5:      dd 2.5
k_3:        dd 3.0
k_5:        dd 5.0
k_6:        dd 6.0
k_12:       dd 12.0                     ; the Laser's range, 24 with Pierce
k_24:       dd 24.0
k_1_5:      dd 1.5                      ; what Burst does to a radius
k_ball_o:   dd 0.6                      ; the Ball starts this far ahead of the eye...
k_ball_v:   dd BALL_SPEED               ; ...at this speed, b/s
k_dash_v:   dd 18.0                     ; the Dash's shove, b/s
k_dash_min: dd 0.0025                   ; the horizontal look the Dash needs, squared (0.05)
k_quarter:  dd 0.25                     ; Phase marches in quarter blocks
k_eye_h:    dd 1.62                     ; eye above the feet
k_chest:    dd 1.0                      ; a blast sits this far above the feet
k_0_2:      dd 0.2                      ; a beam's mote speed
k_0_15:     dd 0.15                     ; how much of its speed a Seek ball turns towards its foe each step
k_chain_r2: dd 36.0                     ; Chain reaches 6 blocks
k_seek_r2:  dd 256.0                    ; Seek sees 16 blocks
k_m2:       dd -2.0                     ; Feather: the fastest fall
k_up:       dd 6.0                      ; Feather: the leap
k_vol:      dd 0.8
k_vol_fail: dd 0.5

align 8
sp_deliveries:                          ; by delivery rune id: (rdi plan, rsi eye, rdx dir, ecx crit, r8 Phase target)
    dq sp_ball, sp_laser, sp_nova, sp_phase, sp_dash

section .bss
alignb 4
sp_state:                               ; everything spells_reset clears
spells_cd:       resd 1                 ; steps until the next cast
spells_cd_total: resd 1                 ; the cooldown it started with (for the HUD)
spells_armed:    resd 1                 ; runes tapped within SPELL_ARM_STEPS (a rune mask)
spells_held:     resd 1                 ; runes whose key is down now
sp_arm_t:        resd 1                 ; steps until the armed runes are forgotten
sp_state_end:

section .text

; ---- the rules ---------------------------------------------------------------------------------

; spells_resolve(edi stack, esi unlocked, rdx out SPELLPLAN*) -> eax 1 when the stack casts something, 0
; when it does not (the plan still says what was kept, dropped and inert). Rune masks throughout.
;   s = stack & unlocked: a locked rune is ignored. kept = the first SPELL_MAX_RUNES set bits of s in rune
;   order; dropped = the rest. The delivery is the lowest delivery rune in kept; with none and an element
;   or modifier along, it is the Ball when unlocked (the implicit Ball joins kept: it pays and cools down,
;   but is not counted against the cap); else -1, a self cast: elements and modifiers are inert and
;   without a boon there is nothing to cast. With a delivery d: the other deliveries are inert, elems =
;   the element runes, mods = the modifiers spell_applies lists for d (the rest are inert).
;   cost = (sum of the mana) * (100 + 15 (n - 1)) / 100 for n kept runes, cd = the sum of the
;   cooldowns, dmg = d's base damage + 2 per element (0 for a self cast).
; r8 = out, r9d = unlocked, r10d = stack & unlocked, r11d = kept, ebx = delivery
spells_resolve:
    push    rbx
    mov     r8, rdx
    mov     r9d, esi
    mov     r10d, edi
    and     r10d, esi
    and     r10d, 0xFFFF
    mov     rdi, r8
    xor     eax, eax
    mov     ecx, SPELLPLAN_size / 4
    rep     stosd
    mov     dword [r8 + SPELLPLAN.delivery], -1
    xor     r11d, r11d
    mov     edx, r10d
    mov     ecx, SPELL_MAX_RUNES
.keep:
    test    edx, edx
    jz      .kept
    bsf     eax, edx
    btr     edx, eax
    bts     r11d, eax
    dec     ecx
    jnz     .keep
.kept:
    mov     eax, r11d
    not     eax
    and     eax, r10d
    mov     [r8 + SPELLPLAN.dropped], eax
    mov     [r8 + SPELLPLAN.runes], r11d
    xor     eax, eax
    test    r11d, r11d
    jz      .ret
    mov     edx, r11d
    and     edx, RUNES_DELIVERY
    jz      .implicit
    bsf     ebx, edx
    jmp     .have_d
.implicit:
    mov     ebx, -1
    test    r11d, RUNES_ELEMENT | RUNES_MOD
    jz      .have_d
    bt      r9d, RUNE_BALL
    jnc     .have_d
    mov     ebx, RUNE_BALL
    bts     r11d, RUNE_BALL             ; the implicit Ball
    mov     [r8 + SPELLPLAN.runes], r11d
.have_d:
    mov     [r8 + SPELLPLAN.delivery], ebx
    test    ebx, ebx
    js      .self
    mov     eax, r11d
    and     eax, RUNES_DELIVERY
    btr     eax, ebx                    ; the other deliveries do nothing
    mov     [r8 + SPELLPLAN.inert], eax
    mov     edx, r11d
    and     edx, RUNES_ELEMENT
    mov     [r8 + SPELLPLAN.elems], edx
    lea     rcx, [spell_applies]
    mov     ecx, [rcx + rbx*4]
    mov     eax, r11d
    and     eax, RUNES_MOD
    mov     edx, eax
    and     edx, ecx
    mov     [r8 + SPELLPLAN.mods], edx
    not     ecx
    and     eax, ecx                    ; the modifiers this delivery cannot use
    or      [r8 + SPELLPLAN.inert], eax
    jmp     .boons
.self:
    mov     eax, r11d
    and     eax, RUNES_ELEMENT | RUNES_MOD
    mov     [r8 + SPELLPLAN.inert], eax
    xor     eax, eax
    test    r11d, RUNES_BOON
    jz      .ret                        ; nothing to deliver and no boon
.boons:
    mov     eax, r11d
    and     eax, RUNES_BOON
    mov     [r8 + SPELLPLAN.boons], eax
    mov     edi, [r8 + SPELLPLAN.elems]
    call    sp_popcount
    mov     [r8 + SPELLPLAN.nelem], eax
    xor     esi, esi                    ; mana
    xor     edi, edi                    ; steps
    xor     ecx, ecx                    ; runes
    lea     r10, [rune_tab]
    mov     edx, r11d
.sum:
    bsf     eax, edx
    btr     edx, eax
    shl     eax, 5                      ; RUNEINFO_size
    add     esi, [r10 + rax + RUNEINFO.cost]
    add     edi, [r10 + rax + RUNEINFO.cd]
    inc     ecx
    test    edx, edx
    jnz     .sum
    lea     eax, [rcx - 1]
    imul    eax, eax, 15
    add     eax, 100
    imul    esi, eax
    mov     eax, esi
    xor     edx, edx
    mov     ecx, 100
    div     ecx
    mov     [r8 + SPELLPLAN.cost], eax
    mov     [r8 + SPELLPLAN.cd], edi
    xor     eax, eax
    test    ebx, ebx
    js      .dmg
    mov     eax, ebx
    shl     eax, 5
    mov     eax, [r10 + rax + RUNEINFO.dmg]
    mov     ecx, [r8 + SPELLPLAN.nelem]
    lea     eax, [rax + rcx*2]          ; base damage + 2 per element
.dmg:
    mov     [r8 + SPELLPLAN.dmg], eax
    mov     eax, 1
.ret:
    pop     rbx
    ret

; sp_popcount(edi mask) -> eax the number of set bits (leaf)
sp_popcount:
    xor     eax, eax
.l:
    test    edi, edi
    jz      .ret
    lea     ecx, [rdi - 1]
    and     edi, ecx
    inc     eax
    jmp     .l
.ret:
    ret

; sp_elem(edi elements mask) -> eax ELEM_* of the lowest element rune, ELEM_PHYS without one (leaf)
sp_elem:
    xor     eax, eax
    test    edi, edi
    jz      .ret
    bsf     eax, edi
    sub     eax, RUNE_FIRE - ELEM_FIRE  ; element rune r deals ELEM_* = r - 4
.ret:
    ret

; spells_input(edi held, esi down): every captured frame. held = the runes whose key is down, down = the
; ones whose key rose this frame: those are armed, and every new rise restarts the shared timer.
spells_input:
    mov     [spells_held], edi
    test    esi, esi
    jz      .ret
    or      [spells_armed], esi
    mov     dword [sp_arm_t], SPELL_ARM_STEPS
.ret:
    ret

; spells_step(): once per fixed step. The cooldown and the arming timer run down (the armed set is
; forgotten when it reaches 0); under the Feather rune the fall is gentle: no fall damage, and the fall
; speed stays within 2 b/s.
spells_step:
    cmp     dword [spells_cd], 0
    jle     .arm
    dec     dword [spells_cd]
.arm:
    cmp     dword [sp_arm_t], 0
    jle     .feather
    dec     dword [sp_arm_t]
    jnz     .feather
    mov     dword [spells_armed], 0
.feather:
    cmp     dword [combat_feather_t], 0
    jle     .ret
    mov     dword [player + BODY.fall], 0
    movss   xmm0, [player + BODY.vy]
    maxss   xmm0, [k_m2]
    movss   [player + BODY.vy], xmm0
.ret:
    ret

; spells_reset(): no cooldown, no armed or held rune
spells_reset:
    lea     rdi, [sp_state]
    mov     ecx, sp_state_end - sp_state
    xor     eax, eax
    rep     stosb
    ret

; ---- helpers -------------------------------------------------------------------------------------

; sp_hunit(rdi dir float[3]) -> xmm0 x, xmm1 z: the horizontal part of dir as a unit vector, (0, 0)
; when it points straight up or down (leaf)
sp_hunit:
    movss   xmm0, [rdi]
    movss   xmm1, [rdi + 8]
    movaps  xmm2, xmm0
    mulss   xmm2, xmm2
    movaps  xmm3, xmm1
    mulss   xmm3, xmm3
    addss   xmm2, xmm3
    sqrtss  xmm2, xmm2
    comiss  xmm2, [k_tiny]
    jae     .unit
    xorps   xmm0, xmm0
    xorps   xmm1, xmm1
    ret
.unit:
    divss   xmm0, xmm2
    divss   xmm1, xmm2
    ret

; sp_centre(edi mob) -> xmm0, xmm1, xmm2: the middle of the mob's body (leaf: clobbers rax, rcx)
sp_centre:
    imul    eax, edi, MOB_size
    lea     rcx, [mobs]
    add     rcx, rax
    movss   xmm0, [rcx + BODY.x]
    movss   xmm1, [rcx + BODY.height]
    mulss   xmm1, [k_half]
    addss   xmm1, [rcx + BODY.y]
    movss   xmm2, [rcx + BODY.z]
    ret

; sp_hit_mob(edi mob, esi elems, edx flags, xmm0 damage, xmm1 dirx, xmm2 dirz) -> eax 1 when a blow landed:
; one combat_hit_mob per element rune in elems, each for its share of the damage (damage / elements) with
; that element, flags (HITF_CRIT, HITF_CHAIN) on every one; without an element one physical blow
; ebx = mob, r12d = elements left, r13d = flags, r14d = blows landed; frame: share @0, dirx @4, dirz @8
sp_hit_mob:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 32
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    xor     r14d, r14d
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 8], xmm2
    mov     edi, esi
    call    sp_popcount
    mov     ecx, 1
    test    eax, eax
    cmovz   eax, ecx
    cvtsi2ss xmm1, eax
    movss   xmm0, [rsp]
    divss   xmm0, xmm1
    movss   [rsp], xmm0
.blow:
    xor     eax, eax                    ; ELEM_PHYS
    test    r12d, r12d
    jz      .go
    bsf     eax, r12d
    btr     r12d, eax
    sub     eax, RUNE_FIRE - ELEM_FIRE
.go:
    mov     edi, ebx
    mov     esi, SRC_SPELL
    mov     edx, r13d
    or      edx, eax
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    call    combat_hit_mob
    or      r14d, eax
    test    r12d, r12d
    jnz     .blow
    test    r14d, r14d
    setnz   al
    movzx   eax, al
    add     rsp, 32
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; sp_burst_at(xmm0 x, xmm1 y, xmm2 z, xmm3 radius, edi elems, esi damage, edx flags): an explosion (explode_magic,
; which widens the radius with AREA) per element rune in elems, each for its share of the damage, or one
; physical one; flags (HITF_CRIT) on every one
; r12d = elements left, r13d = flags, ebx = the share; frame: x, y, z, radius
sp_burst_at:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 24
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 8], xmm2
    movss   [rsp + 12], xmm3
    mov     r12d, edi
    mov     r13d, edx
    mov     ebx, esi
    call    sp_popcount
    mov     ecx, 1
    test    eax, eax
    cmovz   eax, ecx
    mov     ecx, eax
    mov     eax, ebx
    xor     edx, edx
    div     ecx
    mov     ebx, eax                    ; each element's share of the damage
.blast:
    xor     ecx, ecx                    ; ELEM_PHYS
    test    r12d, r12d
    jz      .go
    bsf     ecx, r12d
    btr     r12d, ecx
    sub     ecx, RUNE_FIRE - ELEM_FIRE
.go:
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    movss   xmm3, [rsp + 12]
    mov     edi, ebx
    mov     esi, SRC_SPELL
    mov     edx, r13d
    or      edx, ecx
    call    explode_magic
    test    r12d, r12d
    jnz     .blast
    add     rsp, 24
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; sp_chain(edi victim, esi elems, edx damage, ecx flags, r8 mask*) -> eax mobs struck: up to CHAIN_TARGETS of
; the nearest hostile mobs within 6 blocks of the victim's middle, never the victim or one in the mask (a
; qword, bit i = mob i: the struck ones are added to it), take the blows of elems for half the damage, flagged
; HITF_CHAIN and with the given flags; sparks fly where they stand
; ebx = elems, r12d = victim, r13 = mask*, r14d = flags, r15d = arcs left
; frame: best d^2 @0, best mob @4, victim's middle @8, skip mask @24 (qword), mob index @32, d^2 of the
; mob in view @36, damage @40, struck @44
sp_chain:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 56
    mov     ebx, esi
    mov     r12d, edi
    mov     r13, r8
    mov     r14d, ecx
    or      r14d, HITF_CHAIN
    mov     [rsp + 40], edx
    mov     dword [rsp + 44], 0
    call    sp_centre
    movss   [rsp + 8], xmm0
    movss   [rsp + 12], xmm1
    movss   [rsp + 16], xmm2
    mov     rax, [r13]
    bts     rax, r12
    mov     [rsp + 24], rax
    mov     r15d, CHAIN_TARGETS
.arc:
    movss   xmm0, [k_chain_r2]
    movss   [rsp], xmm0
    mov     dword [rsp + 4], -1
    mov     dword [rsp + 32], 0
.scan:
    mov     eax, [rsp + 32]
    imul    ecx, eax, MOB_size
    lea     rsi, [mobs]
    add     rsi, rcx
    cmp     dword [rsi + MOB.type], MOB_NONE
    je      .next
    bt      qword [rsp + 24], rax
    jc      .next
    movss   xmm0, [rsi + BODY.x]
    subss   xmm0, [rsp + 8]
    mulss   xmm0, xmm0
    movss   xmm1, [rsi + BODY.height]
    mulss   xmm1, [k_half]
    addss   xmm1, [rsi + BODY.y]
    subss   xmm1, [rsp + 12]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    movss   xmm1, [rsi + BODY.z]
    subss   xmm1, [rsp + 16]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [rsp]
    jae     .next                       ; not nearer than the best so far
    movss   [rsp + 36], xmm0
    mov     edi, eax
    call    mob_is_hostile
    test    eax, eax
    jz      .next
    movss   xmm0, [rsp + 36]
    movss   [rsp], xmm0
    mov     eax, [rsp + 32]
    mov     [rsp + 4], eax
.next:
    inc     dword [rsp + 32]
    cmp     dword [rsp + 32], MAX_MOBS
    jb      .scan
    mov     eax, [rsp + 4]
    test    eax, eax
    js      .done                       ; nobody left in reach
    bts     qword [rsp + 24], rax
    mov     edi, eax
    mov     esi, ebx
    mov     edx, r14d
    cvtsi2ss xmm0, dword [rsp + 40]
    mulss   xmm0, [k_half]
    xorps   xmm1, xmm1
    xorps   xmm2, xmm2
    call    sp_hit_mob
    mov     edi, [rsp + 4]
    call    sp_centre
    movss   xmm3, [k_one]
    mov     edi, FX_SPARK
    mov     esi, 6
    call    fx_burst
    inc     dword [rsp + 44]
    dec     r15d
    jnz     .arc
.done:
    mov     rax, [rsp + 24]
    mov     [r13], rax
    mov     eax, [rsp + 44]
    add     rsp, 56
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- casting ---------------------------------------------------------------------------------------

; spells_cast(rdi eye float[3], rsi dir float[3] unit look direction) -> eax 1 when a spell went off, 0 when
; the click only dry-fired: nothing castable in the stack (held | armed), still cooling down, a Phase with no
; room to land (sp_phase_plan) or a Dash with no horizontal look, or the mana was short (combat_pay: Blood
; Magic pays in health, Creative pays nothing). Failing or not, the armed runes are forgotten. A cast pays,
; starts the cooldown (the plan's, shortened by COOLDOWN_RED), runs the delivery and then the boons, ends
; stealth and swings the hand.
; r12 = eye, r13 = dir, r14d = stack, then the critical roll, r15d = the delivery rune
; frame: SPELLPLAN @0, the Phase target float[3] @48
spells_cast:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 72
    mov     r12, rdi
    mov     r13, rsi
    mov     r14d, [spells_held]
    or      r14d, [spells_armed]
    mov     dword [spells_armed], 0
    mov     dword [sp_arm_t], 0
    call    rpg_runes
    mov     edi, r14d
    mov     esi, eax
    lea     rdx, [rsp]
    call    spells_resolve
    test    eax, eax
    jz      .fail
    cmp     dword [spells_cd], 0
    jg      .fail
    mov     r15d, [rsp + SPELLPLAN.delivery]
    cmp     r15d, RUNE_PHASE
    jne     .dash_check
    mov     rdi, r12
    mov     rsi, r13
    lea     rdx, [rsp + 48]
    call    sp_phase_plan
    test    eax, eax
    jz      .fail                       ; nowhere to land: nothing is paid
    jmp     .pay
.dash_check:
    cmp     r15d, RUNE_DASH
    jne     .pay
    movss   xmm0, [r13]
    mulss   xmm0, xmm0
    movss   xmm1, [r13 + 8]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [k_dash_min]
    jb      .fail                       ; looking straight up or down: no direction to dash in
.pay:
    mov     edi, RES_MANA
    cvtsi2ss xmm0, dword [rsp + SPELLPLAN.cost]
    call    combat_pay
    test    eax, eax
    jz      .fail
    mov     edi, STAT_COOLDOWN_RED      ; cooldown steps = cd * (100 - COOLDOWN_RED) / 100
    call    rpg_stat
    mov     ecx, 100
    sub     ecx, eax
    mov     eax, [rsp + SPELLPLAN.cd]
    imul    eax, ecx
    xor     edx, edx
    mov     ecx, 100
    div     ecx
    mov     [spells_cd], eax
    mov     [spells_cd_total], eax
    call    ab_crit
    mov     r14d, eax                   ; one roll for the whole cast
    test    r15d, r15d
    js      .boons
    lea     rdi, [rsp]
    mov     rsi, r12
    mov     rdx, r13
    mov     ecx, r14d
    lea     r8, [rsp + 48]
    lea     rax, [sp_deliveries]
    call    [rax + r15*8]
.boons:
    lea     rdi, [rsp]
    call    sp_boons
    mov     dword [combat_stealth_t], 0 ; casting gives a hider away
    mov     dword [net_swing_t], 10     ; the other players see the cast swing
    call    hand_swing
    mov     eax, 1
    jmp     .ret
.fail:
    mov     edi, SND_DRY_FIRE
    movss   xmm0, [k_vol_fail]
    call    audio_play
    xor     eax, eax
.ret:
    add     rsp, 72
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; sp_boons(rdi plan): Heal restores max(6, a fifth of the maximum health), Haste walks 30 % faster for 600
; steps (combat_speed_mult), Feather leaps (vy at least 6 b/s) and then falls gently for 300 steps (spells_step)
; rbx = plan
sp_boons:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdi
    test    dword [rbx + SPELLPLAN.boons], 1 << RUNE_HEAL
    jz      .haste
    mov     eax, [surv_max_health]
    add     eax, eax
    xor     edx, edx
    mov     ecx, 10
    div     ecx
    mov     edi, 6
    cmp     eax, edi
    cmovl   eax, edi
    mov     edi, eax
    call    combat_heal
    movss   xmm0, [k_3]
    mov     edi, FX_GOLD
    mov     esi, 12
    call    ab_burst
.haste:
    test    dword [rbx + SPELLPLAN.boons], 1 << RUNE_HASTE
    jz      .feather
    mov     dword [combat_haste_t], 600
.feather:
    test    dword [rbx + SPELLPLAN.boons], 1 << RUNE_FEATHER
    jz      .ret
    mov     dword [combat_feather_t], 300
    movss   xmm0, [player + BODY.vy]
    maxss   xmm0, [k_up]
    movss   [player + BODY.vy], xmm0
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- deliveries: (rdi plan, rsi eye, rdx dir, ecx crit 0/1, r8 the Phase target) ---------------------

; sp_ball: a PROJ_SPELL of the player's from 0.6 ahead of the eye at 28 b/s, carrying the damage, the
; first element in its flags (and AF_CRIT) and in arrow_spell the element and modifier runes with the
; mob hits it may still make (3 with Pierce, else 1). A full projectile pool wastes the mana.
; rbx = plan
sp_ball:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdi
    movss   xmm3, [rdx]
    movss   xmm4, [rdx + 4]
    movss   xmm5, [rdx + 8]
    movss   xmm6, [k_ball_o]
    movaps  xmm0, xmm3
    mulss   xmm0, xmm6
    addss   xmm0, [rsi]
    movaps  xmm1, xmm4
    mulss   xmm1, xmm6
    addss   xmm1, [rsi + 4]
    movaps  xmm2, xmm5
    mulss   xmm2, xmm6
    addss   xmm2, [rsi + 8]
    movss   xmm7, [k_ball_v]
    mulss   xmm3, xmm7
    mulss   xmm4, xmm7
    mulss   xmm5, xmm7
    mov     r8d, ecx                    ; AF_CRIT is 1
    mov     edi, [rbx + SPELLPLAN.elems]
    call    sp_elem
    shl     eax, AF_ELEM_SHIFT
    or      r8d, eax
    xor     edi, edi                    ; the player's
    mov     esi, [rbx + SPELLPLAN.dmg]
    xor     edx, edx                    ; nobody picks it up
    mov     ecx, PROJ_SPELL
    call    arrows_spawn
    test    eax, eax
    js      .sound
    mov     ecx, [rbx + SPELLPLAN.elems]
    or      ecx, [rbx + SPELLPLAN.mods]
    mov     edx, 1
    mov     esi, PIERCE_HITS
    test    dword [rbx + SPELLPLAN.mods], 1 << RUNE_PIERCE
    cmovnz  edx, esi
    shl     edx, 16
    or      ecx, edx
    lea     rdx, [arrow_spell]
    mov     [rdx + rax*4], ecx
.sound:
    mov     edi, SND_SPELL
    test    dword [rbx + SPELLPLAN.elems], 1 << RUNE_FIRE
    jz      .play
    mov     edi, SND_FIREBALL
.play:
    movss   xmm0, [k_vol]
    call    audio_play
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; sp_laser: an instant beam from the eye along dir, up to 12 blocks (24 with Pierce) or the first block; up
; to LASER_VICTIMS mobs on the way are struck once each (the elements' blows) and Chain arcs on from the
; first; Burst explodes where the beam ends; the beam is drawn as motes of the first element
; rbx = plan, r12 = eye, r13 = dir, r14d = crit flags, r15d = victims left
; frame: RAYHIT @0, a block's box @24 and @36, beam length @48, push direction @52, @56, struck mask @64, mob @72
sp_laser:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 88
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14d, ecx
    shl     r14d, 8                     ; HITF_CRIT
    movss   xmm0, [k_12]
    test    dword [rbx + SPELLPLAN.mods], 1 << RUNE_PIERCE
    jz      .range
    movss   xmm0, [k_24]
.range:
    movss   [rsp + 48], xmm0
    mov     rdi, r12
    mov     rsi, r13
    lea     rdx, [rsp]
    call    raycast
    test    eax, eax
    jz      .march
    xor     ecx, ecx
.cell:                                  ; the block's box [b, b + 1]
    cvtsi2ss xmm0, dword [rsp + rcx*4]
    movss   [rsp + 24 + rcx*4], xmm0
    addss   xmm0, [k_one]
    movss   [rsp + 36 + rcx*4], xmm0
    inc     ecx
    cmp     ecx, 3
    jb      .cell
    mov     rdi, r12
    mov     rsi, r13
    lea     rdx, [rsp + 24]
    lea     rcx, [rsp + 36]
    movss   xmm0, [rsp + 48]
    call    ray_aabb
    test    eax, eax
    jz      .march                      ; a grazing miss: the whole range
    movss   [rsp + 48], xmm0
.march:
    mov     rdi, r13
    call    sp_hunit
    movss   [rsp + 52], xmm0
    movss   [rsp + 56], xmm1
    mov     qword [rsp + 64], 0
    mov     r15d, LASER_VICTIMS
.victim:
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, [rsp + 64]
    movss   xmm0, [rsp + 48]
    call    mobs_raycast_skip
    test    eax, eax
    js      .after
    mov     [rsp + 72], eax
    bts     qword [rsp + 64], rax
    mov     edi, eax
    mov     esi, [rbx + SPELLPLAN.elems]
    mov     edx, r14d
    cvtsi2ss xmm0, dword [rbx + SPELLPLAN.dmg]
    movss   xmm1, [rsp + 52]
    movss   xmm2, [rsp + 56]
    call    sp_hit_mob
    cmp     r15d, LASER_VICTIMS
    jne     .next                       ; Chain arcs on from the first one only
    test    dword [rbx + SPELLPLAN.mods], 1 << RUNE_CHAIN
    jz      .next
    mov     edi, [rsp + 72]
    mov     esi, [rbx + SPELLPLAN.elems]
    mov     edx, [rbx + SPELLPLAN.dmg]
    mov     ecx, r14d
    lea     r8, [rsp + 64]
    call    sp_chain
.next:
    dec     r15d
    jnz     .victim
.after:
    test    dword [rbx + SPELLPLAN.mods], 1 << RUNE_BURST
    jz      .beam
    movss   xmm3, [rsp + 48]            ; where the beam ends: eye + dir * length
    movss   xmm0, [r13]
    mulss   xmm0, xmm3
    addss   xmm0, [r12]
    movss   xmm1, [r13 + 4]
    mulss   xmm1, xmm3
    addss   xmm1, [r12 + 4]
    movss   xmm2, [r13 + 8]
    mulss   xmm2, xmm3
    addss   xmm2, [r12 + 8]
    movss   xmm3, [k_2_5]
    mov     edi, [rbx + SPELLPLAN.elems]
    mov     esi, [rbx + SPELLPLAN.dmg]
    mov     edx, r14d
    call    sp_burst_at
.beam:
    mov     edi, [rbx + SPELLPLAN.elems]
    call    sp_elem
    mov     edx, eax
    mov     rdi, r12
    mov     rsi, r13
    movss   xmm0, [rsp + 48]
    call    spells_beam_fx
    mov     edi, [rbx + SPELLPLAN.elems]
    call    sp_elem
    mov     edx, eax
    mov     rdi, r12
    mov     rsi, r13
    movss   xmm0, [rsp + 48]
    call    net_spell_beam_out          ; the other players see the beam too
    mov     edi, SND_SPELL
    movss   xmm0, [k_vol]
    call    audio_play
    add     rsp, 88
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; sp_nova: a burst around the caster: 5 blocks (x 1.5 with Burst, x (1 + AREA / 100)) and 3 in height, every
; hostile mob inside takes each element's blow (Frost chills three times at once: a freeze), shoved
; outwards at 0.5; a ring of the first element's motes
; rbx = plan, r12d = crit flags, r13d = elements left; frame: radius @0, each element's share @4
sp_nova:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 24
    mov     rbx, rdi
    mov     r12d, ecx
    shl     r12d, 8                     ; HITF_CRIT
    movss   xmm0, [k_5]
    test    dword [rbx + SPELLPLAN.mods], 1 << RUNE_BURST
    jz      .area
    mulss   xmm0, [k_1_5]
.area:
    cvtsi2ss xmm1, dword [rpg_stats + STAT_AREA * 4]
    divss   xmm1, [k_hundred]
    addss   xmm1, [k_one]
    mulss   xmm0, xmm1
    movss   [rsp], xmm0
    mov     r13d, [rbx + SPELLPLAN.elems]
    mov     edi, r13d
    call    sp_popcount
    mov     ecx, 1
    test    eax, eax
    cmovz   eax, ecx
    cvtsi2ss xmm1, eax
    cvtsi2ss xmm0, dword [rbx + SPELLPLAN.dmg]
    divss   xmm0, xmm1
    movss   [rsp + 4], xmm0
.sweep:
    xor     eax, eax                    ; ELEM_PHYS
    test    r13d, r13d
    jz      .go
    bsf     eax, r13d
    btr     r13d, eax
    sub     eax, RUNE_FIRE - ELEM_FIRE
.go:
    mov     esi, eax
    or      esi, r12d
    cmp     eax, ELEM_FROST
    jne     .strike
    or      esi, HITF_CHILL3
.strike:
    movss   xmm0, [rsp + 4]
    movss   xmm1, [rsp]
    movss   xmm2, [k_3]
    movss   xmm3, [k_half]
    mov     edi, SRC_SPELL
    xor     edx, edx
    call    ab_sweep
    test    r13d, r13d
    jnz     .sweep
    mov     edi, [rbx + SPELLPLAN.elems]
    call    sp_elem
    lea     rdx, [spell_fx]
    mov     edi, [rdx + rax*4]
    mov     esi, 40
    movss   xmm0, [k_6]
    call    ab_burst
    mov     edi, SND_SPELL
    test    dword [rbx + SPELLPLAN.elems], 1 << RUNE_FROST
    jz      .sound
    mov     edi, SND_FREEZE
.sound:
    movss   xmm0, [k_vol]
    call    audio_play
    add     rsp, 24
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; sp_phase_plan(rdi eye float[3], rsi dir float[3], rdx out float[3]) -> eax 1 when the player can teleport at
; least a block: marches along dir in quarter-block steps up to 8 blocks, the candidate feet being
; eye + dir * s - (0, 1.62, 0), until the box is no longer free; out = the last free candidate
; rbx = out, r12 = eye, r13 = dir, r14d = step, r15d = last free step; frame: candidate float[3]
sp_phase_plan:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     rbx, rdx
    mov     r12, rdi
    mov     r13, rsi
    xor     r15d, r15d
    mov     r14d, 1
.march:
    cvtsi2ss xmm3, r14d
    mulss   xmm3, [k_quarter]           ; s
    movss   xmm0, [r13]
    mulss   xmm0, xmm3
    addss   xmm0, [r12]
    movss   [rsp], xmm0
    movss   xmm1, [r13 + 4]
    mulss   xmm1, xmm3
    addss   xmm1, [r12 + 4]
    subss   xmm1, [k_eye_h]
    movss   [rsp + 4], xmm1
    movss   xmm2, [r13 + 8]
    mulss   xmm2, xmm3
    addss   xmm2, [r12 + 8]
    movss   [rsp + 8], xmm2
    call    ab_box_free
    test    eax, eax
    jz      .stop
    mov     r15d, r14d
    mov     eax, [rsp]
    mov     [rbx], eax
    mov     eax, [rsp + 4]
    mov     [rbx + 4], eax
    mov     eax, [rsp + 8]
    mov     [rbx + 8], eax
    inc     r14d
    cmp     r14d, 32
    jbe     .march
.stop:
    xor     eax, eax
    cmp     r15d, 4                     ; best >= 1 block
    setae   al
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; sp_phase: the player appears at the planned spot (r8), motion and fall forgotten; magic sparks at both ends;
; with an element or Burst a blast (3 blocks, x 1.5 with Burst) at the arrival
; rbx = plan, r12 = the spot, r13d = crit flags
sp_phase:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 24
    mov     rbx, rdi
    mov     r12, r8
    mov     r13d, ecx
    shl     r13d, 8                     ; HITF_CRIT
    movss   xmm0, [k_2]
    mov     edi, FX_MAGIC
    mov     esi, 20
    call    ab_burst
    mov     eax, [r12]
    mov     [player + BODY.x], eax
    mov     eax, [r12 + 4]
    mov     [player + BODY.y], eax
    mov     eax, [r12 + 8]
    mov     [player + BODY.z], eax
    xor     eax, eax
    mov     [player + BODY.vy], eax
    mov     [player + BODY.kbx], eax
    mov     [player + BODY.kbz], eax
    mov     [player + BODY.fall], eax
    movss   xmm0, [k_2]
    mov     edi, FX_MAGIC
    mov     esi, 20
    call    ab_burst
    mov     edi, SND_BLINK
    movss   xmm0, [k_vol]
    call    audio_play
    mov     eax, [rbx + SPELLPLAN.elems]
    or      eax, [rbx + SPELLPLAN.mods]
    jz      .ret
    movss   xmm0, [player + BODY.x]
    movss   xmm1, [player + BODY.y]
    addss   xmm1, [k_chest]
    movss   xmm2, [player + BODY.z]
    movss   xmm3, [k_3]
    test    dword [rbx + SPELLPLAN.mods], 1 << RUNE_BURST
    jz      .blast
    mulss   xmm3, [k_1_5]
.blast:
    mov     edi, [rbx + SPELLPLAN.elems]
    mov     esi, [rbx + SPELLPLAN.dmg]
    mov     edx, r13d
    call    sp_burst_at
.ret:
    add     rsp, 24
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; sp_dash: a horizontal shove of 18 b/s along dir, untouchable for 20 steps, the fall forgotten; with an element
; or Burst a blast (2 blocks, x 1.5 with Burst) where the dash began
; rbx = plan, r13d = crit flags
sp_dash:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r13
    sub     rsp, 16
    mov     rbx, rdi
    mov     r13d, ecx
    shl     r13d, 8                     ; HITF_CRIT
    mov     rdi, rdx
    call    sp_hunit
    mulss   xmm0, [k_dash_v]
    movss   [player + BODY.kbx], xmm0
    mulss   xmm1, [k_dash_v]
    movss   [player + BODY.kbz], xmm1
    mov     eax, [surv + SURVIVAL.invuln]
    mov     ecx, 20
    cmp     eax, ecx
    cmovl   eax, ecx
    mov     [surv + SURVIVAL.invuln], eax   ; untouchable for 20 steps, or what is left of a longer one
    mov     dword [player + BODY.fall], 0
    movss   xmm0, [k_2]
    mov     edi, FX_MAGIC
    mov     esi, 10
    call    ab_burst
    mov     eax, [rbx + SPELLPLAN.elems]
    or      eax, [rbx + SPELLPLAN.mods]
    jz      .ret
    movss   xmm0, [player + BODY.x]
    movss   xmm1, [player + BODY.y]
    addss   xmm1, [k_chest]
    movss   xmm2, [player + BODY.z]
    movss   xmm3, [k_2]
    test    dword [rbx + SPELLPLAN.mods], 1 << RUNE_BURST
    jz      .blast
    mulss   xmm3, [k_1_5]
.blast:
    mov     edi, [rbx + SPELLPLAN.elems]
    mov     esi, [rbx + SPELLPLAN.dmg]
    mov     edx, r13d
    call    sp_burst_at
.ret:
    add     rsp, 16
    pop     r13
    pop     rbx
    pop     rbp
    ret

; ---- the Ball in flight (hooks of arrows.asm) --------------------------------------------------------

; spells_proj_steer(edi slot): a Ball with Seek bends towards the nearest hostile mob within 16 blocks that
; is ahead of it and was not struck yet: v = |v| * unit(v + unit(to) * |v| * 0.15)
; rbx = the projectile, r12d = slot, r13 = struck mask, r14d = mob index
; frame: best d^2 @0, best mob @4, vector to it @8, to the mob in view @24, its d^2 @36
spells_proj_steer:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 48
    mov     r12d, edi
    lea     rax, [arrow_spell]
    test    dword [rax + rdi*4], 1 << RUNE_SEEK
    jz      .ret
    imul    eax, edi, ARROWENT_size
    lea     rbx, [arrows]
    add     rbx, rax
    lea     rax, [arrow_hitmask]
    mov     r13, [rax + r12*8]
    movss   xmm0, [k_seek_r2]
    movss   [rsp], xmm0
    mov     dword [rsp + 4], -1
    xor     r14d, r14d
.scan:
    imul    eax, r14d, MOB_size
    lea     rsi, [mobs]
    add     rsi, rax
    cmp     dword [rsi + MOB.type], MOB_NONE
    je      .next
    bt      r13, r14
    jc      .next
    movss   xmm0, [rsi + BODY.x]
    subss   xmm0, [rbx + ARROWENT.x]
    movss   xmm1, [rsi + BODY.height]
    mulss   xmm1, [k_half]
    addss   xmm1, [rsi + BODY.y]
    subss   xmm1, [rbx + ARROWENT.y]
    movss   xmm2, [rsi + BODY.z]
    subss   xmm2, [rbx + ARROWENT.z]
    movss   xmm3, [rbx + ARROWENT.vx]
    mulss   xmm3, xmm0
    movss   xmm4, [rbx + ARROWENT.vy]
    mulss   xmm4, xmm1
    addss   xmm3, xmm4
    movss   xmm4, [rbx + ARROWENT.vz]
    mulss   xmm4, xmm2
    addss   xmm3, xmm4                  ; v . to
    xorps   xmm4, xmm4
    comiss  xmm3, xmm4
    jbe     .next                       ; behind it
    movaps  xmm3, xmm0
    mulss   xmm3, xmm3
    movaps  xmm4, xmm1
    mulss   xmm4, xmm4
    addss   xmm3, xmm4
    movaps  xmm4, xmm2
    mulss   xmm4, xmm4
    addss   xmm3, xmm4                  ; d^2
    comiss  xmm3, [rsp]
    jae     .next
    movss   [rsp + 24], xmm0
    movss   [rsp + 28], xmm1
    movss   [rsp + 32], xmm2
    movss   [rsp + 36], xmm3
    mov     edi, r14d
    call    mob_is_hostile
    test    eax, eax
    jz      .next
    movss   xmm0, [rsp + 36]
    movss   [rsp], xmm0
    mov     [rsp + 4], r14d
    mov     rax, [rsp + 24]
    mov     [rsp + 8], rax
    mov     eax, [rsp + 32]
    mov     [rsp + 16], eax
.next:
    inc     r14d
    cmp     r14d, MAX_MOBS
    jb      .scan
    cmp     dword [rsp + 4], 0
    jl      .ret
    movss   xmm0, [rsp]
    sqrtss  xmm0, xmm0                  ; |to|
    comiss  xmm0, [k_tiny]
    jb      .ret
    movss   xmm1, [rbx + ARROWENT.vx]
    mulss   xmm1, xmm1
    movss   xmm2, [rbx + ARROWENT.vy]
    mulss   xmm2, xmm2
    addss   xmm1, xmm2
    movss   xmm2, [rbx + ARROWENT.vz]
    mulss   xmm2, xmm2
    addss   xmm1, xmm2
    sqrtss  xmm1, xmm1                  ; |v|
    movaps  xmm2, xmm1
    mulss   xmm2, [k_0_15]
    divss   xmm2, xmm0                  ; |v| * 0.15 / |to|
    movss   xmm3, [rsp + 8]
    mulss   xmm3, xmm2
    addss   xmm3, [rbx + ARROWENT.vx]
    movss   xmm4, [rsp + 12]
    mulss   xmm4, xmm2
    addss   xmm4, [rbx + ARROWENT.vy]
    movss   xmm5, [rsp + 16]
    mulss   xmm5, xmm2
    addss   xmm5, [rbx + ARROWENT.vz]
    movaps  xmm6, xmm3
    mulss   xmm6, xmm6
    movaps  xmm7, xmm4
    mulss   xmm7, xmm7
    addss   xmm6, xmm7
    movaps  xmm7, xmm5
    mulss   xmm7, xmm7
    addss   xmm6, xmm7
    sqrtss  xmm6, xmm6                  ; |v'|
    comiss  xmm6, [k_tiny]
    jb      .ret
    movaps  xmm7, xmm1
    divss   xmm7, xmm6                  ; back to the old speed
    mulss   xmm3, xmm7
    mulss   xmm4, xmm7
    mulss   xmm5, xmm7
    movss   [rbx + ARROWENT.vx], xmm3
    movss   [rbx + ARROWENT.vy], xmm4
    movss   [rbx + ARROWENT.vz], xmm5
.ret:
    add     rsp, 48
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; spells_proj_hit(edi slot, esi mob, xmm0 x, xmm1 y, xmm2 z the hit point, xmm3 hdirx, xmm4 hdirz) -> eax 1 when
; the Ball flies on, 0 when it is spent. The blow: each element's share of the damage it carries; the mob
; joins arrow_hitmask. Chain arcs on from the first mob it strikes. With Burst it explodes here and is
; spent; else one of its mob hits is used up and it goes on while some are left (Pierce: 3, else 1).
; rbx = the projectile, r12d = slot, r13d = mob, r14d = arrow_spell word, r15 = struck mask
; frame: point @0, push @16, struck mask @24, hits left @32
spells_proj_hit:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40
    mov     r12d, edi
    mov     r13d, esi
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 8], xmm2
    movss   [rsp + 16], xmm3
    movss   [rsp + 20], xmm4
    imul    eax, r12d, ARROWENT_size
    lea     rbx, [arrows]
    add     rbx, rax
    lea     rax, [arrow_spell]
    mov     r14d, [rax + r12*4]
    lea     rax, [arrow_hitmask]
    mov     r15, [rax + r12*8]
    mov     edi, r13d
    mov     esi, r14d
    and     esi, RUNES_ELEMENT
    mov     edx, [rbx + ARROWENT.flags]
    and     edx, AF_CRIT
    shl     edx, 8                      ; HITF_CRIT
    cvtsi2ss xmm0, dword [rbx + ARROWENT.damage]
    movss   xmm1, [rsp + 16]
    movss   xmm2, [rsp + 20]
    call    sp_hit_mob
    mov     rax, r15                    ; the mask before this blow
    bts     r15, r13
    mov     [rsp + 24], r15
    bt      r14d, RUNE_CHAIN
    jnc     .store
    test    rax, rax
    jnz     .store                      ; Chain arcs on from the first victim only
    mov     edi, r13d
    mov     esi, r14d
    and     esi, RUNES_ELEMENT
    mov     edx, [rbx + ARROWENT.damage]
    mov     ecx, [rbx + ARROWENT.flags]
    and     ecx, AF_CRIT
    shl     ecx, 8
    lea     r8, [rsp + 24]
    call    sp_chain
.store:
    mov     rax, [rsp + 24]
    lea     rcx, [arrow_hitmask]
    mov     [rcx + r12*8], rax
    bt      r14d, RUNE_BURST
    jnc     .hits
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    movss   xmm3, [k_2_5]
    mov     edi, r14d
    and     edi, RUNES_ELEMENT
    mov     esi, [rbx + ARROWENT.damage]
    mov     edx, [rbx + ARROWENT.flags]
    and     edx, AF_CRIT
    shl     edx, 8
    call    sp_burst_at
    xor     eax, eax
    jmp     .ret
.hits:
    mov     eax, r14d
    shr     eax, 16
    dec     eax                         ; hits left after this one
    jle     .spent
    shl     eax, 16
    and     r14d, 0xFFFF
    or      r14d, eax
    lea     rcx, [arrow_spell]
    mov     [rcx + r12*4], r14d
    mov     eax, 1
    jmp     .ret
.spent:
    xor     eax, eax
.ret:
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; spells_proj_end(edi slot, xmm0 x, xmm1 y, xmm2 z): a Ball ends without a mob (it met a block or ran out of
; time): Burst explodes where it ended, and sparks of its element fly
; rbx = the projectile, r12d = its runes; frame: point @0, the mote's kind @12
spells_proj_end:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 32
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 8], xmm2
    imul    eax, edi, ARROWENT_size
    lea     rbx, [arrows]
    add     rbx, rax
    lea     rax, [arrow_spell]
    mov     r12d, [rax + rdi*4]
    bt      r12d, RUNE_BURST
    jnc     .sparks
    movss   xmm3, [k_2_5]
    mov     edi, r12d
    and     edi, RUNES_ELEMENT
    mov     esi, [rbx + ARROWENT.damage]
    mov     edx, [rbx + ARROWENT.flags]
    and     edx, AF_CRIT
    shl     edx, 8
    call    sp_burst_at
.sparks:
    mov     edi, r12d
    and     edi, RUNES_ELEMENT
    call    sp_elem
    lea     rdx, [spell_fx]
    mov     edi, [rdx + rax*4]
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    movss   xmm3, [k_one]
    mov     esi, 8
    call    fx_burst
    add     rsp, 32
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- drawing a beam, and the HUD's text ---------------------------------------------------------------

; spells_beam_fx(rdi start float[3], rsi dir float[3], xmm0 length, edx element ELEM_*): a mote of the element's
; kind every half block along the beam. Not sent to the other players (they get the beam in one message).
; rbx = start, r12 = dir; frame: distance along @0, length @4, kind @8, net_applying before @12
spells_beam_fx:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 32
    mov     rbx, rdi
    mov     r12, rsi
    movss   [rsp + 4], xmm0
    and     edx, 7
    lea     rcx, [spell_fx]
    mov     eax, [rcx + rdx*4]
    mov     [rsp + 8], eax
    movzx   eax, byte [net_applying]
    mov     [rsp + 12], eax
    mov     byte [net_applying], 1
    mov     dword [rsp], 0
.mote:
    movss   xmm4, [rsp]
    movss   xmm0, [r12]
    mulss   xmm0, xmm4
    addss   xmm0, [rbx]
    movss   xmm1, [r12 + 4]
    mulss   xmm1, xmm4
    addss   xmm1, [rbx + 4]
    movss   xmm2, [r12 + 8]
    mulss   xmm2, xmm4
    addss   xmm2, [rbx + 8]
    movss   xmm3, [k_0_2]
    mov     edi, [rsp + 8]
    mov     esi, 1
    call    fx_burst
    movss   xmm0, [rsp]
    addss   xmm0, [k_half]
    movss   [rsp], xmm0
    comiss  xmm0, [rsp + 4]
    jb      .mote
    mov     eax, [rsp + 12]
    mov     [net_applying], al
    add     rsp, 32
    pop     r12
    pop     rbx
    pop     rbp
    ret

; sp_names(rdi end, esi mask, rdx separator zstr) -> rax the new end: the names of the runes in mask, in rune
; order, joined by the separator (no NUL)
; rbx = end, r12d = runes left, r13 = separator; frame: first @0, rune @4
sp_names:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 24
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13, rdx
    mov     dword [rsp], 1
.rune:
    test    r12d, r12d
    jz      .done
    bsf     eax, r12d
    btr     r12d, eax
    mov     [rsp + 4], eax
    cmp     dword [rsp], 0
    jne     .name
    mov     rdi, rbx
    mov     rsi, r13
    call    str_append
    mov     rbx, rax
.name:
    mov     dword [rsp], 0
    mov     eax, [rsp + 4]
    shl     eax, 5
    lea     rcx, [rune_tab]
    mov     rsi, [rcx + rax + RUNEINFO.name]
    mov     rdi, rbx
    call    str_append
    mov     rbx, rax
    jmp     .rune
.done:
    mov     rax, rbx
    add     rsp, 24
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; sp_note(rdi end, rsi prefix zstr, edx mask) -> rax the new end: prefix, the names in mask joined by ", " and
; ")"; nothing at all for an empty mask
; rbx = mask
sp_note:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rax, rdi
    test    edx, edx
    jz      .ret
    mov     ebx, edx
    call    str_append
    mov     rdi, rax
    mov     esi, ebx
    lea     rdx, [s_comma]
    call    sp_names
    mov     rdi, rax
    lea     rsi, [s_close]
    call    str_append
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; spells_preview(rdi buf 96 bytes) -> eax 1 when the runes held or armed cast something. The text: the names
; of the runes that count, " + " between them, two spaces, the mana ("Laser + Frost + Pierce  36 mana"),
; then " (inert: ...)" for runes that do nothing here and " (dropped: ...)" for those over the cap; "Nothing to
; cast" otherwise.
; rbx = buf, r12d = the answer; frame: SPELLPLAN @0
spells_preview:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 56
    mov     rbx, rdi
    mov     r13d, [spells_held]
    or      r13d, [spells_armed]
    call    rpg_runes
    mov     edi, r13d
    mov     esi, eax
    lea     rdx, [rsp]
    call    spells_resolve
    mov     r12d, eax
    test    eax, eax
    jnz     .cast
    mov     rdi, rbx
    lea     rsi, [s_nothing]
    call    str_append
    mov     byte [rax], 0
    jmp     .ret
.cast:
    mov     rdi, rbx
    mov     esi, [rsp + SPELLPLAN.runes]
    lea     rdx, [s_plus]
    call    sp_names
    mov     rdi, rax
    lea     rsi, [s_gap]
    call    str_append
    mov     rsi, rax
    mov     edi, [rsp + SPELLPLAN.cost]
    call    i32_to_str
    mov     rdi, rax
    lea     rsi, [s_mana]
    call    str_append
    mov     rdi, rax
    lea     rsi, [s_inert]
    mov     edx, [rsp + SPELLPLAN.inert]
    call    sp_note
    mov     rdi, rax
    lea     rsi, [s_dropped]
    mov     edx, [rsp + SPELLPLAN.dropped]
    call    sp_note
    mov     byte [rax], 0
.ret:
    mov     eax, r12d
    add     rsp, 56
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
