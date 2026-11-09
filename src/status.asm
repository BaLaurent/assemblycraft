; status.asm - the statuses a mob carries: burn, bleed and poison (damage over time), chill (it
; slows; three stacks freeze it), shock (it takes more damage) and the Hunter's Mark. combat_hit_mob
; puts them on through status_apply; status_step, once per simulation step, ages the timers and pays
; the damage over time. The values live in the MOB record (see common.inc).
%include "common.inc"
default rel

global status_apply, status_step, status_speed_mult, status_damage_mult

extern mobs, mob_strike, rpg_stats, gear_powers
extern combat_hit_flags, dmgnum_text, audio_play_at

%define BURN_STEPS    180               ; burn and bleed last 3 s
%define POISON_STEPS  240               ; poison and shock 4 s
%define SHOCK_STEPS   240
%define CHILL_STEPS   120               ; chill 2 s
%define FREEZE_CD     120               ; steps after a freeze during which chill cannot freeze again
%define FREEZE_STEPS  90                ; the stun of a freeze; the boss and juggernauts thaw sooner
%define FREEZE_BOSS   30
%define FREEZE_JUGG   20
%define DOT_PERIOD    30                ; steps between two damage-over-time ticks
%define POISON_CAP    10                ; poison stacks; the Viper amulet doubles the cap
%define POISON_CAP_LP 20
%define SHOCK_CAP     3

section .rodata
align 4
k_1:        dd 1.0
k_6:        dd 6.0
k_100:      dd 100.0
k_0_5:      dd 0.5
k_0_08:     dd 0.08                     ; poison: a stack ticks for 8 % of the hit that applied it
k_shock_step: dd 0.05                   ; shock: 5 % more damage per stack
k_0_2:      dd 0.2                      ; chill: 20 % slower per stack
k_0_7:      dd 0.7                      ; armored elites take 30 % less
k_0_8:      dd 0.8                      ; volume of the freezing crack
k_1_3:      dd 1.3                      ; marked foes take 30 % more

section .text

; AGE timer, cleared...: one step off a status timer that runs; when it reaches 0 the listed fields
; (stacks, per-tick damage) are cleared. A timer at 0 is left alone.
%macro AGE 1-*
    mov     eax, [rbx + MOB.%1]
    test    eax, eax
    jle     %%done
    dec     eax
    mov     [rbx + MOB.%1], eax
    jnz     %%done
%rep %0 - 1
%rotate 1
    mov     dword [rbx + MOB.%1], 0
%endrep
%%done:
%endmacro

; status_apply(edi mob, esi kind, xmm0 magnitude): put one status (STS_*) on a mob. magnitude is the
; scaled damage of the hit that causes it; D = 1 + DOT_DMG / 100 strengthens the damage over time:
;   burn, bleed: 3 s, damage per tick = max(old, 0.5 * magnitude * D / 6)
;   poison: one more stack (10; 20 with the Viper amulet), 4 s, per stack and tick = max(old, 0.08 * magnitude * D)
;   chill: one more stack, 2 s; the third freezes the mob (stun 90, 30 for the boss, 20 for a
;     juggernaut; the stacks go, the freeze cools down 120 steps and holds chill at 2 stacks meanwhile)
;   shock: one more stack (3), 4 s
; Nothing for a bad index, an empty slot or an unknown kind.
; rbx = MOB*, r12d = kind. Frame: [rsp] magnitude, [rsp+4] D
status_apply:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    cmp     edi, MAX_MOBS
    jae     .ret
    imul    ebx, edi, MOB_size
    lea     rax, [mobs]
    add     rbx, rax
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .ret
    mov     r12d, esi
    movss   [rsp], xmm0
    cvtsi2ss xmm1, dword [rpg_stats + STAT_DOT_DMG * 4]
    divss   xmm1, [k_100]
    addss   xmm1, [k_1]
    movss   [rsp + 4], xmm1
    cmp     r12d, STS_BURN
    je      .burn
    cmp     r12d, STS_BLEED
    je      .bleed
    cmp     r12d, STS_POISON
    je      .poison
    cmp     r12d, STS_CHILL
    je      .chill
    cmp     r12d, STS_SHOCK
    je      .shock
    jmp     .ret
.burn:
    movss   xmm0, [rsp]
    mulss   xmm0, [k_0_5]
    mulss   xmm0, [rsp + 4]
    divss   xmm0, [k_6]
    maxss   xmm0, [rbx + MOB.burn_dmg]
    movss   [rbx + MOB.burn_dmg], xmm0
    mov     dword [rbx + MOB.burn_t], BURN_STEPS
    jmp     .ret
.bleed:
    movss   xmm0, [rsp]
    mulss   xmm0, [k_0_5]
    mulss   xmm0, [rsp + 4]
    divss   xmm0, [k_6]
    maxss   xmm0, [rbx + MOB.bleed_dmg]
    movss   [rbx + MOB.bleed_dmg], xmm0
    mov     dword [rbx + MOB.bleed_t], BURN_STEPS
    jmp     .ret
.poison:
    mov     eax, [rbx + MOB.poison]
    inc     eax
    mov     ecx, POISON_CAP
    mov     edx, POISON_CAP_LP
    test    dword [gear_powers], 1 << LP_VIPER
    cmovnz  ecx, edx
    cmp     eax, ecx
    cmova   eax, ecx
    mov     [rbx + MOB.poison], eax
    mov     dword [rbx + MOB.poison_t], POISON_STEPS
    movss   xmm0, [rsp]
    mulss   xmm0, [k_0_08]
    mulss   xmm0, [rsp + 4]
    maxss   xmm0, [rbx + MOB.poison_dmg]
    movss   [rbx + MOB.poison_dmg], xmm0
    jmp     .ret
.chill:
    mov     eax, [rbx + MOB.chill]
    inc     eax
    cmp     dword [rbx + MOB.freeze_cd], 0
    jg      .chill_stack                ; cooling down: the stacks stop at 2
    cmp     eax, 3
    jae     .freeze
.chill_stack:
    mov     ecx, 2
    cmp     eax, ecx
    cmova   eax, ecx
    mov     [rbx + MOB.chill], eax
    mov     dword [rbx + MOB.chill_t], CHILL_STEPS
    jmp     .ret
.freeze:
    mov     eax, FREEZE_STEPS
    cmp     dword [rbx + MOB.type], MOB_BOSS
    jne     .not_boss
    mov     eax, FREEZE_BOSS
    jmp     .stun
.not_boss:
    test    dword [rbx + MOB.affix], AFX_JUGGERNAUT
    jz      .stun
    mov     eax, FREEZE_JUGG
.stun:
    mov     ecx, [rbx + MOB.stun]
    cmp     ecx, eax
    cmovg   eax, ecx                    ; stun = max(stun, freeze)
    mov     [rbx + MOB.stun], eax
    mov     dword [rbx + MOB.chill], 0
    mov     dword [rbx + MOB.chill_t], 0
    mov     dword [rbx + MOB.freeze_cd], FREEZE_CD
    movss   xmm0, [rbx + BODY.x]        ; "FROZEN" over the head, and the crack
    movss   xmm1, [rbx + BODY.height]
    addss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    mov     edi, TXT_FROZEN
    call    dmgnum_text
    mov     edi, SND_FREEZE
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [k_0_8]
    call    audio_play_at
    jmp     .ret
.shock:
    mov     eax, [rbx + MOB.shock]
    inc     eax
    mov     ecx, SHOCK_CAP
    cmp     eax, ecx
    cmova   eax, ecx
    mov     [rbx + MOB.shock], eax
    mov     dword [rbx + MOB.shock_t], SHOCK_STEPS
.ret:
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; status_step(): once per simulation step, right after mobs_step. Every live mob's status timers
; run down one step; a timer that reaches 0 clears its stacks and per-tick damage. While any damage
; over time runs, dot_tick counts down; at 0 it restarts at 30 and the mob takes
; round((burn + bleed + poison stacks * poison per stack) * status_damage_mult), when that is at
; least 1, through mob_strike (it ignores the hurt window), flagged as the player's DoT in the
; element of the largest part (fire for burn, physical for bleed, poison for poison). A kill
; rewards the player as any other tagged kill.
; rbx = MOB*, r12d = its index. Frame: [rsp] burn part, [rsp+4] bleed part, [rsp+8] poison part
status_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    lea     rbx, [mobs]
    xor     r12d, r12d
.mob:
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .next
    AGE     burn_t, burn_dmg
    AGE     bleed_t, bleed_dmg
    AGE     poison_t, poison, poison_dmg
    AGE     chill_t, chill
    AGE     shock_t, shock
    AGE     mark_t
    AGE     freeze_cd
    cmp     dword [rbx + MOB.burn_t], 0
    jg      .dot
    cmp     dword [rbx + MOB.bleed_t], 0
    jg      .dot
    cmp     dword [rbx + MOB.poison_t], 0
    jle     .next
.dot:
    dec     dword [rbx + MOB.dot_tick]
    jg      .next
    mov     dword [rbx + MOB.dot_tick], DOT_PERIOD
    movss   xmm0, [rbx + MOB.burn_dmg]
    movss   [rsp], xmm0
    movss   xmm0, [rbx + MOB.bleed_dmg]
    movss   [rsp + 4], xmm0
    cvtsi2ss xmm0, dword [rbx + MOB.poison]
    mulss   xmm0, [rbx + MOB.poison_dmg]
    movss   [rsp + 8], xmm0
    mov     rdi, rbx
    call    status_damage_mult
    movss   xmm1, [rsp]
    addss   xmm1, [rsp + 4]
    addss   xmm1, [rsp + 8]
    mulss   xmm1, xmm0
    cvtss2si esi, xmm1                  ; the tick
    cmp     esi, 1
    jl      .next
    movss   xmm0, [rsp]                 ; the largest part colours the number
    mov     ecx, ELEM_FIRE
    movss   xmm2, [rsp + 4]
    comiss  xmm2, xmm0
    jbe     .poison_part
    movaps  xmm0, xmm2
    mov     ecx, ELEM_PHYS
.poison_part:
    movss   xmm2, [rsp + 8]
    comiss  xmm2, xmm0
    jbe     .flags
    mov     ecx, ELEM_POISON
.flags:
    shl     ecx, HF_ELEM_SHIFT
    or      ecx, HF_PLAYER | HF_DOT
    mov     [combat_hit_flags], ecx
    mov     edi, r12d
    xorps   xmm0, xmm0                  ; no knockback
    xorps   xmm1, xmm1
    call    mob_strike
.next:
    add     rbx, MOB_size
    inc     r12d
    cmp     r12d, MAX_MOBS
    jb      .mob
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; status_speed_mult(rdi MOB*) -> xmm0 walking speed factor: 1 - 0.2 per chill stack
status_speed_mult:
    cvtsi2ss xmm0, dword [rdi + MOB.chill]
    mulss   xmm0, [k_0_2]
    movss   xmm1, [k_1]
    subss   xmm1, xmm0
    movaps  xmm0, xmm1
    ret

; status_damage_mult(rdi MOB*) -> xmm0 factor on the damage the mob takes: (1 + 0.05 per shock
; stack) * 1.3 while marked * 0.7 for an armored elite
status_damage_mult:
    cvtsi2ss xmm0, dword [rdi + MOB.shock]
    mulss   xmm0, [k_shock_step]
    addss   xmm0, [k_1]
    cmp     dword [rdi + MOB.mark_t], 0
    jle     .unmarked
    mulss   xmm0, [k_1_3]
.unmarked:
    test    dword [rdi + MOB.affix], AFX_ARMORED
    jz      .done
    mulss   xmm0, [k_0_7]
.done:
    ret
