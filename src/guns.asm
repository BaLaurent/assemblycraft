; guns.asm - firearms: per-weapon stats, magazines, attachments, reloading, firing projectiles.
; A firearm stack (count 1) keeps in ITEMSTACK.dmg the rounds loaded (bits 0..7, GUN_ROUNDS_MASK) and
; its attachments (bits 8..11, ATT_*): every reader masks, every writer keeps the high byte. Shots are
; bullets or rockets spawned through arrows_spawn (the damage pipeline does the rest when they land);
; the cooldown, reload and recoil run on fixed steps. Every attachment, keystone and ability rule
; of a shot lives here: Scope, Extended Magazine, Rifled Barrel, Compensator, Deadshot, Quartermaster,
; Bullseye and Fan the Hammer.
%include "common.inc"
default rel

global gun_cooldown, gun_reload, gun_reload_total, gun_reload_slot, gun_kick
global gun_index, gun_magazine, gun_shot_info, gun_ammo, gun_automatic
global gun_reset, gun_reload_start, gun_step, gun_fire

extern inv, inv_sel, inv_count, inv_remove_one, game_mode
extern arrows_spawn, audio_play, rng_next
extern rpg_stats, rpg_keystones, game_aim, combat_bullseye_t, combat_fanhammer_t

%define DRY_COOLDOWN   10               ; steps between dry clicks
%define MIN_COOLDOWN   2                ; no shot comes faster than every 2 steps
%define MIN_RELOAD     10               ; no reload is shorter than 10 steps
%define ROCKET_MOB_DMG 24               ; the rocket launcher's blast on a mob at full strength (explode.asm)
%define BULLSEYE_CRIT  25               ; Bullseye: +25 % crit chance
%define SCOPE_CRIT     15               ; Scope, aimed: +15 % crit chance

%if GUN_ROUNDS_MASK != 0xFF
%error "the rounds of a firearm must be the low byte of its dmg word (guns.asm decrements and stores that byte)"
%endif
%if HUNTING_RIFLE - REVOLVER + 5 + 1 != NUM_GUNS
%error "NUM_GUNS must count the five original guns, the revolver and the hunting rifle"
%endif

section .rodata
; per weapon, index g (gun_index): pistol, musket, shotgun, kalashnikov, rocket launcher, revolver,
; hunting rifle
g_ammo:     db PISTOL_ROUND, MUSKET_BALL, SHOTGUN_SHELL, RIFLE_ROUND, ROCKET, PISTOL_ROUND, RIFLE_ROUND
g_mag:      db 8, 1, 6, 30, 1, 6, 5
g_damage:   db 5, 14, 3, 6, 0, 10, 22   ; per pellet; the rocket's blast does its damage
g_pellets:  db 1, 1, 6, 1, 1, 1, 1
g_cooldown: db 15, 10, 48, 6, 10, 18, 40 ; steps between shots
g_kind:     db PROJ_BULLET, PROJ_BULLET, PROJ_BULLET, PROJ_BULLET, PROJ_ROCKET, PROJ_BULLET, PROJ_BULLET
g_sound:    db SND_PISTOL, SND_MUSKET, SND_SHOTGUN, SND_RIFLE, SND_LAUNCHER, SND_PISTOL, SND_MUSKET
g_auto:     db 0, 0, 0, 1, 0, 0, 0      ; fires while the button is held
%if $ - g_ammo != NUM_GUNS * 8
%error "every per-gun byte table needs NUM_GUNS entries"
%endif
align 2
g_reload:   dw 60, 150, 120, 120, 180, 75, 120 ; steps
%if $ - g_reload != NUM_GUNS * 2
%error "g_reload needs NUM_GUNS entries"
%endif
align 4
g_spread:   dd 0.02, 0.0, 0.10, 0.03, 0.0, 0.015, 0.0
g_speed:    dd 90.0, 110.0, 70.0, 100.0, 25.0, 100.0, 140.0 ; blocks per second
%if $ - g_spread != NUM_GUNS * 8
%error "g_spread and g_speed need NUM_GUNS entries"
%endif
c_muzzle:   dd 0.3                      ; shots start this far in front of the eye
c_kick_dec: dd 0.1
c_one:      dd 1.0
c_half:     dd 0.5                      ; Compensator: half the spread
c_rifled_v: dd 1.3                      ; Rifled Barrel: bullets fly 30 % faster
c_aimed:    dd 0.9                      ; game_aim from here on counts as aimed (Scope, Deadshot)
c_thousand: dd 1000.0
c_dry_vol:  dd 0.8
c_rel_vol:  dd 0.7
c_done_vol: dd 0.9

section .bss
alignb 4
gun_cooldown:     resd 1                ; steps until the next shot is allowed
gun_reload:       resd 1                ; steps left in the reload, 0 = none
gun_reload_total: resd 1                ; length of the current reload
gun_reload_slot:  resd 1                ; hotbar slot being reloaded
gun_kick:         resd 1                ; float recoil 0..1

section .text

; gun_index(edi id) -> eax g 0..NUM_GUNS-1, or -1 when the id is not a firearm
; g = id - PISTOL for PISTOL..ROCKET_LAUNCHER, 5 for REVOLVER, 6 for HUNTING_RIFLE. A leaf that
; clobbers eax only: callers keep edi, esi, rdx and the rest across it.
gun_index:
    lea     eax, [rdi - PISTOL]
    cmp     eax, ROCKET_LAUNCHER - PISTOL
    jbe     .ret                        ; the five original guns are contiguous
    lea     eax, [rdi - REVOLVER + 5]
    cmp     edi, REVOLVER
    jb      .none
    cmp     edi, HUNTING_RIFLE
    jbe     .ret
.none:
    mov     eax, -1
.ret:
    ret

; mag_of(eax g, esi w) -> eax magazine of firearm g with the attachments of the dmg word w:
; ATT_EXTMAG makes it (3m + 1) / 2 and so does the Quartermaster keystone, once more
; (pistol 8 -> 12 -> 18, Kalashnikov 30 -> 45 -> 68). Clobbers rcx.
mag_of:
    lea     rcx, [g_mag]
    movzx   eax, byte [rcx + rax]
    test    esi, ATT_EXTMAG
    jz      .keystone
    lea     eax, [rax + rax*2 + 1]
    shr     eax, 1
.keystone:
    test    dword [rpg_keystones], 1 << KS_QUARTERMASTER
    jz      .ret
    lea     eax, [rax + rax*2 + 1]
    shr     eax, 1
.ret:
    ret

; gun_magazine(edi id, esi w) -> eax magazine size of that firearm carrying the attachments of
; the stack word w (the whole ITEMSTACK.dmg: the rounds in its low byte are ignored), 0 for
; anything else. See mag_of.
gun_magazine:
    call    gun_index
    test    eax, eax
    js      .none
    jmp     mag_of
.none:
    xor     eax, eax
    ret

; gun_shot_info(edi id, esi w, rdx out dword[4]) -> eax 1 for a firearm (out is filled), 0 for
; anything else (out untouched)
; out[0] damage of one pellet before the damage pipeline: the table's, plus max(1, d / 4) with
;        ATT_RIFLED; the rocket launcher: ROCKET_MOB_DMG, what its blast does to a mob at full
;        strength
; out[1] pellets per shot
; out[2] steps between shots: the table's, with ATT_COMP (3c + 2) / 4 and at least MIN_COOLDOWN
;        (Fan the Hammer halves it in gun_fire, not here)
; out[3] 1 when the shot can crit (bullets), 0 for the rocket
; w is the stack's dmg word; only its attachment bits count. Clobbers eax, ecx, r8, r9.
gun_shot_info:
    call    gun_index
    test    eax, eax
    js      .none
    mov     r8d, eax                    ; g
    lea     rcx, [g_damage]
    movzx   eax, byte [rcx + r8]
    lea     rcx, [g_kind]
    cmp     byte [rcx + r8], PROJ_ROCKET
    jne     .bullet
    mov     eax, ROCKET_MOB_DMG
    mov     dword [rdx + 12], 0
    jmp     .pellets
.bullet:
    mov     dword [rdx + 12], 1
    test    esi, ATT_RIFLED
    jz      .pellets
    test    eax, eax
    jz      .pellets                    ; nothing to rifle
    mov     ecx, eax
    shr     ecx, 2                      ; d / 4
    mov     r9d, 1
    cmp     ecx, r9d
    cmovb   ecx, r9d                    ; at least 1
    add     eax, ecx
.pellets:
    mov     [rdx], eax
    lea     rcx, [g_pellets]
    movzx   eax, byte [rcx + r8]
    mov     [rdx + 4], eax
    lea     rcx, [g_cooldown]
    movzx   eax, byte [rcx + r8]
    test    esi, ATT_COMP
    jz      .cooldown
    lea     eax, [rax + rax*2 + 2]
    shr     eax, 2                      ; (3c + 2) / 4
    mov     ecx, MIN_COOLDOWN
    cmp     eax, ecx
    cmovb   eax, ecx
.cooldown:
    mov     [rdx + 8], eax
    mov     eax, 1
    ret
.none:
    xor     eax, eax
    ret

; gun_ammo(edi id) -> eax ammunition item id, 0 for anything else
gun_ammo:
    call    gun_index
    test    eax, eax
    js      .none
    lea     rcx, [g_ammo]
    movzx   eax, byte [rcx + rax]
    ret
.none:
    xor     eax, eax
    ret

; gun_automatic(edi id) -> eax 1 if the firearm keeps firing while the button is held
gun_automatic:
    call    gun_index
    test    eax, eax
    js      .none
    lea     rcx, [g_auto]
    movzx   eax, byte [rcx + rax]
    ret
.none:
    xor     eax, eax
    ret

; gun_reset(): no cooldown, no reload, no recoil
gun_reset:
    xor     eax, eax
    mov     [gun_cooldown], eax
    mov     [gun_reload], eax
    mov     [gun_reload_total], eax
    mov     [gun_reload_slot], eax
    mov     [gun_kick], eax
    ret

; held_gun() -> rax held ITEMSTACK*, edx g; rax = 0 when no firearm is held
held_gun:
    mov     eax, [inv_sel]
    lea     rcx, [inv + INVENTORY.slots + rax*4]
    xor     eax, eax
    cmp     byte [rcx + ITEMSTACK.count], 0
    je      .ret
    movzx   edi, byte [rcx + ITEMSTACK.id]
    call    gun_index
    test    eax, eax
    js      .none
    mov     edx, eax
    mov     rax, rcx
    ret
.none:
    xor     eax, eax
.ret:
    ret

; reload_steps(eax g) -> eax length of that firearm's reload: its table steps scaled by
; 100 / (100 + RELOAD_SPEED), rounded to nearest, at least MIN_RELOAD. Clobbers rcx, rdx.
reload_steps:
    lea     rcx, [g_reload]
    movzx   eax, word [rcx + rax*2]
    imul    eax, eax, 100
    mov     ecx, [rpg_stats + STAT_RELOAD_SPEED * 4]
    add     ecx, 100                    ; 100 + R
    mov     edx, ecx
    shr     edx, 1
    add     eax, edx                    ; + (100 + R) / 2: the quotient rounds
    xor     edx, edx
    div     ecx
    mov     ecx, MIN_RELOAD
    cmp     eax, ecx
    cmovb   eax, ecx
    ret

; gun_reload_start() -> eax 1 if a reload began: a firearm is held, nothing is reloading, the
; magazine (gun_magazine of the held stack) is not full and (Creative, or ammunition is in the
; inventory). The reload takes reload_steps.
; rbx = g, r12d = rounds loaded
gun_reload_start:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    held_gun
    test    rax, rax
    jz      .no
    cmp     dword [gun_reload], 0
    jne     .no
    mov     ebx, edx                    ; g
    movzx   esi, word [rax + ITEMSTACK.dmg]
    mov     r12d, esi
    and     r12d, GUN_ROUNDS_MASK       ; the rounds in the magazine
    mov     eax, ebx
    call    mag_of
    cmp     r12d, eax
    jae     .no                         ; already full
    cmp     dword [game_mode], MODE_CREATIVE
    je      .start
    lea     rcx, [g_ammo]
    movzx   edi, byte [rcx + rbx]
    call    inv_count
    test    eax, eax
    jz      .no
.start:
    mov     eax, ebx
    call    reload_steps
    mov     [gun_reload], eax
    mov     [gun_reload_total], eax
    mov     eax, [inv_sel]
    mov     [gun_reload_slot], eax
    mov     edi, SND_RELOAD
    movss   xmm0, [c_rel_vol]
    call    audio_play
    mov     eax, 1
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; gun_step(): one fixed step: cooldown and recoil wind down; a running reload continues,
; is cancelled when the hotbar selection changes, and fills the magazine when it ends: Creative
; for free; Survival takes the rounds from the inventory one at a time, each staying in the
; inventory with an ARROW_SAVE % chance, until the magazine is full or the ammunition runs out.
; The rounds are the low byte of the stack's dmg word, so the attachments stay.
; rbx = the firearm's stack, r15d = g, r12d = magazine, r13d = ammunition id, r14d = rounds
gun_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8                      ; six pushes leave rsp 8 off
    mov     eax, [gun_cooldown]
    test    eax, eax
    jz      .kick
    dec     eax
    mov     [gun_cooldown], eax
.kick:
    movss   xmm0, [gun_kick]
    subss   xmm0, [c_kick_dec]
    xorps   xmm1, xmm1
    maxss   xmm0, xmm1
    movss   [gun_kick], xmm0
    cmp     dword [gun_reload], 0
    je      .ret
    mov     eax, [inv_sel]
    cmp     eax, [gun_reload_slot]
    jne     .cancel
    call    held_gun
    test    rax, rax
    jz      .cancel
    dec     dword [gun_reload]
    jnz     .ret
    mov     rbx, rax                    ; the firearm's stack
    mov     r15d, edx                   ; g
    movzx   esi, word [rbx + ITEMSTACK.dmg]
    mov     eax, r15d
    call    mag_of
    mov     r12d, eax                   ; magazine
    lea     rcx, [g_ammo]
    movzx   r13d, byte [rcx + r15]      ; ammunition id
    movzx   r14d, byte [rbx + ITEMSTACK.dmg] ; rounds loaded
    cmp     dword [game_mode], MODE_CREATIVE
    jne     .round
    mov     r14d, r12d
    jmp     .store
.round:
    cmp     r14d, r12d
    jae     .store
    mov     edi, r13d
    call    inv_count
    test    eax, eax
    jz      .store                      ; out of ammunition: a partial magazine
    call    rng_next
    xor     edx, edx
    mov     ecx, 100
    div     ecx
    cmp     edx, [rpg_stats + STAT_ARROW_SAVE * 4]
    jl      .loaded                     ; saved: this round loads and stays in the inventory
    mov     edi, r13d
    call    inv_remove_one
.loaded:
    inc     r14d
    jmp     .round
.store:
    mov     [rbx + ITEMSTACK.dmg], r14b
    mov     edi, SND_RELOAD
    movss   xmm0, [c_done_vol]
    call    audio_play
    jmp     .ret
.cancel:
    mov     dword [gun_reload], 0
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; spread_unit() -> xmm0 uniform in [-1, 1] (steps of 0.001)
spread_unit:
    sub     rsp, 8
    call    rng_next
    xor     edx, edx
    mov     ecx, 2001
    div     ecx
    sub     edx, 1000
    cvtsi2ss xmm0, edx
    divss   xmm0, [c_thousand]
    add     rsp, 8
    ret

; gun_fire frame (rsp-relative)
%define F_DIR    0                      ; float[3] this pellet's direction
%define F_POS    12                     ; float[3] muzzle
%define F_SPREAD 24                     ; float
%define F_SPEED  28                     ; float
%define F_SCALE  32                     ; float spread scale (aiming tightens it)
%define F_FLAGS  36                     ; int AF_* of every pellet (the shot's one crit); the chance while it is rolled
%define F_INFO   40                     ; int[4] gun_shot_info of this shot
%define F_AIMED  56                     ; int 1 when game_aim is at least c_aimed
%define F_SIZE   72

; gun_fire(rdi eye[3], rsi dir[3] unit, xmm0 spread scale) -> eax 1 if a shot left the barrel.
; Nothing while reloading or cooling down; an empty magazine (the low byte of the dmg word) clicks
; and starts a reload. A shot takes one round unless Fan the Hammer is running (combat_fanhammer_t > 0),
; which also halves the cooldown (at least MIN_COOLDOWN). The shot's numbers come from gun_shot_info
; of the held stack.
; Spread: the weapon's times the scale (1 from the hip, less while aiming, 0 dead straight), halved
; with ATT_COMP, none while Bullseye runs (combat_bullseye_t > 0) or with ATT_SCOPE when aimed
; (game_aim >= 0.9). Rifled Barrel makes the bullets 30 % faster.
; Crit, one roll per shot that all pellets share (a rocket never crits): with Deadshot an aimed shot
; crits and one from the hip does not; otherwise a roll under CRIT_CHANCE, +25 while Bullseye
; runs, +15 with ATT_SCOPE when aimed, capped at 100 (no number is drawn at 0). A crit sets
; AF_CRIT on every pellet.
; Each pellet leaves from eye + dir * 0.3 along dir jittered by the spread.
; rbx = g, r12 = eye, r13 = dir, r14 = stack, r15d = pellets left
gun_fire:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, F_SIZE                 ; 6 pushes leave rsp 8 off; F_SIZE = 72 realigns
    mov     r12, rdi
    mov     r13, rsi
    movss   [rsp + F_SCALE], xmm0
    call    held_gun
    test    rax, rax
    jz      .no
    cmp     dword [gun_reload], 0
    jne     .no
    cmp     dword [gun_cooldown], 0
    jne     .no
    mov     r14, rax
    mov     ebx, edx
    cmp     byte [r14 + ITEMSTACK.dmg], 0 ; the rounds: the low byte
    jne     .shoot
    mov     edi, SND_DRY_FIRE
    movss   xmm0, [c_dry_vol]
    call    audio_play
    call    gun_reload_start
    mov     dword [gun_cooldown], DRY_COOLDOWN
    jmp     .no
.shoot:
    movzx   edi, byte [r14 + ITEMSTACK.id]
    movzx   esi, word [r14 + ITEMSTACK.dmg]
    lea     rdx, [rsp + F_INFO]
    call    gun_shot_info
    xor     eax, eax
    movss   xmm0, [game_aim]
    comiss  xmm0, [c_aimed]
    setae   al
    mov     [rsp + F_AIMED], eax
    cmp     dword [combat_fanhammer_t], 0
    jg      .fan                        ; Fan the Hammer: the round is free
    dec     byte [r14 + ITEMSTACK.dmg]  ; one round: the low byte, the attachments stay
.fan:
    mov     eax, [rsp + F_INFO + 8]
    cmp     dword [combat_fanhammer_t], 0
    jle     .cooldown
    shr     eax, 1                      ; twice as fast
    mov     ecx, MIN_COOLDOWN
    cmp     eax, ecx
    cmovb   eax, ecx
.cooldown:
    mov     [gun_cooldown], eax
    movzx   edx, word [r14 + ITEMSTACK.dmg] ; the attachments (the high byte is untouched)
    lea     rcx, [g_spread]
    movss   xmm0, [rcx + rbx*4]
    mulss   xmm0, [rsp + F_SCALE]
    test    edx, ATT_COMP
    jz      .no_comp
    mulss   xmm0, [c_half]
.no_comp:
    cmp     dword [combat_bullseye_t], 0
    jg      .straight                   ; Bullseye: shots fly true
    test    edx, ATT_SCOPE
    jz      .spread_set
    cmp     dword [rsp + F_AIMED], 0
    je      .spread_set                 ; the scope helps only when aimed
.straight:
    xorps   xmm0, xmm0
.spread_set:
    movss   [rsp + F_SPREAD], xmm0
    lea     rcx, [g_speed]
    movss   xmm0, [rcx + rbx*4]
    test    edx, ATT_RIFLED
    jz      .speed_set
    mulss   xmm0, [c_rifled_v]
.speed_set:
    movss   [rsp + F_SPEED], xmm0
    mov     dword [rsp + F_FLAGS], 0
    cmp     dword [rsp + F_INFO + 12], 0
    je      .crit_done                  ; a blast does not crit
    test    dword [rpg_keystones], 1 << KS_DEADSHOT
    jz      .crit_roll
    cmp     dword [rsp + F_AIMED], 0
    je      .crit_done                  ; Deadshot: shots from the hip never crit...
    jmp     .crit_set                   ; ...aimed ones always do
.crit_roll:
    mov     ecx, [rpg_stats + STAT_CRIT_CHANCE * 4]
    cmp     dword [combat_bullseye_t], 0
    jle     .no_bullseye
    add     ecx, BULLSEYE_CRIT
.no_bullseye:
    test    edx, ATT_SCOPE
    jz      .no_scope
    cmp     dword [rsp + F_AIMED], 0
    je      .no_scope
    add     ecx, SCOPE_CRIT
.no_scope:
    mov     eax, 100
    cmp     ecx, eax
    cmova   ecx, eax                    ; at most 100
    test    ecx, ecx
    jle     .crit_done                  ; no chance: no number is drawn
    mov     [rsp + F_FLAGS], ecx        ; the chance, until the roll
    call    rng_next
    xor     edx, edx
    mov     ecx, 100
    div     ecx
    cmp     edx, [rsp + F_FLAGS]
    jae     .crit_none
.crit_set:
    mov     dword [rsp + F_FLAGS], AF_CRIT
    jmp     .crit_done
.crit_none:
    mov     dword [rsp + F_FLAGS], 0
.crit_done:
    movss   xmm1, [c_muzzle]
    xor     ecx, ecx
.muzzle:
    movss   xmm0, [r13 + rcx*4]
    mulss   xmm0, xmm1
    addss   xmm0, [r12 + rcx*4]
    movss   [rsp + F_POS + rcx*4], xmm0
    inc     ecx
    cmp     ecx, 3
    jb      .muzzle
    mov     r15d, [rsp + F_INFO + 4]    ; pellets
.pellet:
    xor     ecx, ecx
.jitter:
    push    rcx
    push    rcx                         ; keep rsp 16-aligned for the call
    call    spread_unit
    pop     rcx
    pop     rcx
    mulss   xmm0, [rsp + F_SPREAD]
    addss   xmm0, [r13 + rcx*4]
    movss   [rsp + F_DIR + rcx*4], xmm0
    inc     ecx
    cmp     ecx, 3
    jb      .jitter
    movss   xmm0, [rsp + F_DIR]         ; renormalise, then scale to the muzzle speed
    mulss   xmm0, xmm0
    movss   xmm1, [rsp + F_DIR + 4]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    movss   xmm1, [rsp + F_DIR + 8]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    sqrtss  xmm0, xmm0
    movss   xmm6, [rsp + F_SPEED]
    divss   xmm6, xmm0
    movss   xmm3, [rsp + F_DIR]
    mulss   xmm3, xmm6
    movss   xmm4, [rsp + F_DIR + 4]
    mulss   xmm4, xmm6
    movss   xmm5, [rsp + F_DIR + 8]
    mulss   xmm5, xmm6
    movss   xmm0, [rsp + F_POS]
    movss   xmm1, [rsp + F_POS + 4]
    movss   xmm2, [rsp + F_POS + 8]
    xor     edi, edi                    ; owner: the player
    mov     esi, [rsp + F_INFO]         ; damage per pellet
    xor     edx, edx                    ; never picked up
    lea     rcx, [g_kind]
    movzx   ecx, byte [rcx + rbx]
    mov     r8d, [rsp + F_FLAGS]
    call    arrows_spawn
    dec     r15d
    jnz     .pellet
    lea     rcx, [g_sound]
    movzx   edi, byte [rcx + rbx]
    movss   xmm0, [c_one]
    call    audio_play
    movss   xmm0, [c_one]
    movss   [gun_kick], xmm0
    mov     eax, 1
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    add     rsp, F_SIZE
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
