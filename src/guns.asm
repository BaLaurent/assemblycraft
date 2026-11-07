; guns.asm - firearms: per-weapon stats, magazines, reloading, firing projectiles.
; A firearm stack (count 1) keeps the rounds loaded in ITEMSTACK.dmg. Shots are bullets or
; rockets spawned through arrows_spawn; the cooldown, reload and recoil run on fixed steps.
%include "common.inc"
default rel

global gun_cooldown, gun_reload, gun_reload_total, gun_reload_slot, gun_kick
global gun_index, gun_magazine, gun_ammo, gun_automatic
global gun_reset, gun_reload_start, gun_step, gun_fire

extern inv, inv_sel, inv_count, inv_remove_one, game_mode
extern arrows_spawn, audio_play, rng_next

%define DRY_COOLDOWN 10                 ; steps between dry clicks

section .rodata
; per weapon, index g = id - PISTOL: pistol, musket, shotgun, kalashnikov, rocket launcher
g_ammo:     db PISTOL_ROUND, MUSKET_BALL, SHOTGUN_SHELL, RIFLE_ROUND, ROCKET
g_mag:      db 8, 1, 6, 30, 1
g_damage:   db 5, 14, 3, 6, 0           ; per pellet; the rocket's blast does its damage
g_pellets:  db 1, 1, 6, 1, 1
g_cooldown: db 15, 10, 48, 6, 10        ; steps between shots
g_kind:     db PROJ_BULLET, PROJ_BULLET, PROJ_BULLET, PROJ_BULLET, PROJ_ROCKET
g_sound:    db SND_PISTOL, SND_MUSKET, SND_SHOTGUN, SND_RIFLE, SND_LAUNCHER
g_auto:     db 0, 0, 0, 1, 0            ; fires while the button is held
align 2
g_reload:   dw 60, 150, 120, 120, 180   ; steps
align 4
g_spread:   dd 0.02, 0.0, 0.10, 0.03, 0.0
g_speed:    dd 90.0, 110.0, 70.0, 100.0, 25.0 ; blocks per second
c_muzzle:   dd 0.3                      ; shots start this far in front of the eye
c_kick_dec: dd 0.1
c_one:      dd 1.0
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
gun_index:
    lea     eax, [rdi - PISTOL]
    cmp     eax, NUM_GUNS
    jb      .ret
    mov     eax, -1
.ret:
    ret

; gun_magazine(edi id) -> eax magazine size, 0 for anything else
gun_magazine:
    call    gun_index
    test    eax, eax
    js      .none
    lea     rcx, [g_mag]
    movzx   eax, byte [rcx + rax]
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
    movzx   edx, byte [rcx + ITEMSTACK.id]
    sub     edx, PISTOL
    cmp     edx, NUM_GUNS
    jae     .ret
    mov     rax, rcx
.ret:
    ret

; gun_reload_start() -> eax 1 if a reload began: a firearm is held, nothing is reloading, the
; magazine is not full and (Creative, or ammunition is in the inventory)
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
    lea     rcx, [g_mag]
    movzx   ecx, byte [rcx + rbx]
    cmp     [rax + ITEMSTACK.dmg], cx
    jae     .no                         ; already full
    cmp     dword [game_mode], MODE_CREATIVE
    je      .start
    lea     rcx, [g_ammo]
    movzx   edi, byte [rcx + rbx]
    call    inv_count
    test    eax, eax
    jz      .no
.start:
    lea     rcx, [g_reload]
    movzx   eax, word [rcx + rbx*2]
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
; is cancelled when the hotbar selection changes, and fills the magazine when it ends
; (from the inventory in Survival, for free in Creative).
gun_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
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
    lea     rcx, [g_mag]
    movzx   r12d, byte [rcx + rdx]      ; magazine
    lea     rcx, [g_ammo]
    movzx   r13d, byte [rcx + rdx]      ; ammunition id
    cmp     dword [game_mode], MODE_CREATIVE
    jne     .take
    mov     [rbx + ITEMSTACK.dmg], r12w
    jmp     .loaded
.take:
    movzx   r14d, word [rbx + ITEMSTACK.dmg]
.round:
    cmp     r14d, r12d
    jae     .store
    mov     edi, r13d
    call    inv_remove_one
    test    eax, eax
    jz      .store                      ; out of ammunition: a partial magazine
    inc     r14d
    jmp     .round
.store:
    mov     [rbx + ITEMSTACK.dmg], r14w
.loaded:
    mov     edi, SND_RELOAD
    movss   xmm0, [c_done_vol]
    call    audio_play
    jmp     .ret
.cancel:
    mov     dword [gun_reload], 0
.ret:
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
%define F_SIZE   40

; gun_fire(rdi eye[3], rsi dir[3] unit, xmm0 spread scale) -> eax 1 if a shot left the barrel.
; Nothing while reloading or cooling down; an empty magazine clicks and starts a reload.
; Each pellet leaves from eye + dir * 0.3 along dir jittered by the weapon's spread times the
; scale (1 from the hip, less while aiming, 0 dead straight).
; rbx = g, r12 = eye, r13 = dir, r14 = stack, r15d = pellets left
gun_fire:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, F_SIZE                 ; 6 pushes leave rsp 8 off; F_SIZE = 40 realigns
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
    cmp     word [r14 + ITEMSTACK.dmg], 0
    jne     .shoot
    mov     edi, SND_DRY_FIRE
    movss   xmm0, [c_dry_vol]
    call    audio_play
    call    gun_reload_start
    mov     dword [gun_cooldown], DRY_COOLDOWN
    jmp     .no
.shoot:
    dec     word [r14 + ITEMSTACK.dmg]
    lea     rcx, [g_cooldown]
    movzx   eax, byte [rcx + rbx]
    mov     [gun_cooldown], eax
    lea     rcx, [g_spread]
    movss   xmm0, [rcx + rbx*4]
    mulss   xmm0, [rsp + F_SCALE]
    movss   [rsp + F_SPREAD], xmm0
    lea     rcx, [g_speed]
    movss   xmm0, [rcx + rbx*4]
    movss   [rsp + F_SPEED], xmm0
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
    lea     rcx, [g_pellets]
    movzx   r15d, byte [rcx + rbx]
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
    lea     rcx, [g_damage]
    movzx   esi, byte [rcx + rbx]
    xor     edx, edx                    ; never picked up
    lea     rcx, [g_kind]
    movzx   ecx, byte [rcx + rbx]
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
