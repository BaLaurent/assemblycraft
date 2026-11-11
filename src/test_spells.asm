; test_spells.asm - the runes: the resolution rules (every row of the plan's table, locked runes, the cap,
; the implicit Ball, inert and dropped runes), a Ball with an element (cost, cooldown, the projectile, a
; burn on the foe it hits, a failed cast that costs nothing), Pierce and Chain, the Laser (range, a block in
; the way, Pierce), Nova with Frost, Phase against a wall, several elements at once, Seek, the boons, the
; arming of tapped runes, Blood Magic paying a cast in health and the preview text.
%include "common.inc"
%undef FIRE                            ; the block and the item named like the runes: R(FIRE) and R(FEATHER) paste RUNE_ onto the name
%undef FEATHER
default rel

global test_spell_resolve, test_spell_ball, test_spell_pierce_chain, test_spell_laser, test_spell_nova_frost
global test_spell_phase, test_spell_multi_element, test_spell_seek, test_spell_boons, test_spell_arming
global test_spell_blood_magic, test_spell_preview, test_spell_dash_burst

extern world_clear, world_set, mobs, mobs_clear, mob_spawn
extern arrows, arrows_clear, arrows_step
extern tnt_clear, drops_clear, inv_clear, inv_sel, fx_clear, fx_count
extern abilities_reset, rpg_reset, rpg_ext, rpg_stats, rpg_keystones, gear_powers
extern combat_reset, combat_mana, combat_haste_t, combat_feather_t, combat_speed_mult
extern game_mode, game_time, settings, surv, surv_max_health, survival_reset
extern player, body_init, rng_seed, player_eye, player_forward, str_eq, str_len
extern spells_resolve, spells_input, spells_cast, spells_step, spells_reset, spells_preview
extern spells_cd, spells_cd_total, spells_armed, spells_held

%define R(r)    (1 << RUNE_ %+ r)
%define ALL_RUNES 0xFFFF
%define MOBF(n, f) [mobs + (n) * MOB_size + (f)]

section .rodata
align 4
k_half_w: dd 0.3
k_height: dd 1.8
k_speed:  dd 4.317
k_x16_5:  dd 16.5
k_y11:    dd 11.0
k_z1_5:   dd 1.5
k_z21_5:  dd 21.5
k_z10_5:  dd 10.5
k_z8_5:   dd 8.5
k_z6_5:   dd 6.5
k_z12_5:  dd 12.5
k_z5:     dd 5.0                        ; 11.5 blocks ahead of z = 16.5 is z = 5
k_x20_5:  dd 20.5
k_x12_5:  dd 12.5
k_x19_5:  dd 19.5
k_z9_5:   dd 9.5
k_z1:     dd 1.5
k_yaw0:   dd 0.0
k_yaw180: dd 180.0
k_eps:    dd 0.01
k_abs:    dd 0x7FFFFFFF
k_1_3:    dd 1.3
k_13_5:   dd 13.5
k_x18_5:  dd 18.5
k_pitch90: dd 90.0

; the plan's worked results: stack, unlocked, answer, delivery, elems, mods, inert, dropped, cost, cd, dmg
; (only the answer is compared for an answer of 0)
%macro VEC 11
    dd %1, %2, %3, %4, %5, %6, %7, %8, %9, %10, %11
%endmacro
vectors:
    VEC R(BALL) | R(FIRE), ALL_RUNES, 1, RUNE_BALL, R(FIRE), 0, 0, 0, 18, 30, 8
    VEC R(LASER) | R(FROST) | R(PIERCE), ALL_RUNES, 1, RUNE_LASER, R(FROST), R(PIERCE), 0, 0, 36, 90, 7
    VEC R(FIRE) | R(POISON), ALL_RUNES, 1, RUNE_BALL, R(FIRE) | R(POISON), 0, 0, 0, 28, 30, 10
    VEC R(FIRE) | R(POISON), ALL_RUNES & ~R(BALL), 0, 0, 0, 0, 0, 0, 0, 0, 0
    VEC R(BALL) | R(LASER) | R(FIRE) | R(BURST) | R(SEEK) | R(HEAL), ALL_RUNES, 1, RUNE_BALL, R(FIRE), R(BURST), R(LASER), R(SEEK) | R(HEAL), 60, 180, 8
    VEC R(NOVA) | R(SEEK), ALL_RUNES, 1, RUNE_NOVA, 0, 0, R(SEEK), 0, 27, 240, 5
    VEC R(LASER) | R(SEEK), ALL_RUNES, 1, RUNE_LASER, 0, 0, R(SEEK), 0, 25, 90, 5     ; Seek is for the Ball
    VEC R(HEAL), ALL_RUNES, 1, -1, 0, 0, 0, 0, 20, 240, 0
    VEC 0, ALL_RUNES, 0, 0, 0, 0, 0, 0, 0, 0, 0
    VEC R(LASER) | R(FIRE), R(BALL) | R(FIRE), 1, RUNE_BALL, R(FIRE), 0, 0, 0, 18, 30, 8   ; a locked rune is ignored, not dropped
vectors_end:

s_pv_laser:   db "Laser + Frost + Pierce  36 mana", 0
s_pv_nothing: db "Nothing to cast", 0
s_pv_inert:   db "Ball + Laser + Fire + Burst  60 mana (inert: Laser) (dropped: Seek, Heal)", 0

section .bss
alignb 4
view_buf:  resd 6                       ; eye[3], dir[3] as spells_cast takes them
plan:      resb SPELLPLAN_size
text:      resb 192                    ; spells_preview's buffer ...
canary:    resq 1                      ; ... and what must stay untouched behind it

section .text

; SETF mem, float literal
%macro SETF 2
    mov     dword %1, __float32__(%2)
%endmacro

; EXPECT_NEAR float mem operand, value: fail unless |mem - value| < 0.01
%macro EXPECT_NEAR 2
    section .rodata
    align 4
%%v: dd %2
    section .text
    movss   xmm0, %1
    movss   xmm1, [%%v]
    call    close_to
    test    eax, eax
    jz      .fail
%endmacro

; close_to(xmm0 a, xmm1 b) -> eax 1 when |a - b| < 0.01
close_to:
    subss   xmm0, xmm1
    movss   xmm1, [k_abs]
    andps   xmm1, xmm0
    xor     eax, eax
    comiss  xmm1, [k_eps]
    setb    al
    ret

; fixture(): rng seed 1234, nothing left from other tests, Survival at Normal, a STONE floor at y = 10
; for x, z in 0..31, the player standing on it at (16.5, 11, 16.5), every rune unlocked, 100 mana, no
; crit chance (so the damage is exact), nothing cast yet; an empty world first
; rbx = x, r12d = z
fixture:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear                 ; nothing left of an earlier subcase's walls
    mov     edi, 1234
    call    rng_seed
    call    mobs_clear
    call    arrows_clear
    call    tnt_clear
    call    drops_clear
    call    inv_clear
    call    fx_clear
    call    abilities_reset
    call    spells_reset
    call    rpg_reset
    call    combat_reset
    mov     dword [rpg_keystones], 0
    mov     dword [gear_powers], 0
    mov     dword [inv_sel], 0
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    mov     dword [game_time], NEW_WORLD_TIME
    call    survival_reset
    mov     word [rpg_ext + RPGEXT.runes], ALL_RUNES
    mov     dword [rpg_stats + STAT_CRIT_CHANCE * 4], 0
    SETF    [combat_mana], 100.0
    xor     r12d, r12d
.z:
    xor     ebx, ebx
.x:
    mov     edi, ebx
    mov     esi, 10
    mov     edx, r12d
    mov     ecx, STONE
    call    world_set
    inc     ebx
    cmp     ebx, 32
    jb      .x
    inc     r12d
    cmp     r12d, 32
    jb      .z
    lea     rdi, [player]
    movss   xmm0, [k_half_w]
    movss   xmm1, [k_height]
    movss   xmm2, [k_speed]
    call    body_init
    movss   xmm0, [k_x16_5]
    movss   [player + BODY.x], xmm0
    movss   [player + BODY.z], xmm0
    movss   xmm0, [k_y11]
    movss   [player + BODY.y], xmm0
    pop     r12
    pop     rbx
    pop     rbp
    ret

; cleanup(): leave nothing behind
cleanup:
    sub     rsp, 8
    call    mobs_clear
    call    arrows_clear
    call    tnt_clear
    call    drops_clear
    call    inv_clear
    call    fx_clear
    call    abilities_reset
    call    spells_reset
    call    rpg_reset
    call    combat_reset
    mov     dword [rpg_keystones], 0
    mov     dword [gear_powers], 0
    add     rsp, 8
    ret

; aim(xmm0 yaw): the player looks that way, level; view_buf = eye[3], dir[3]
aim:
    push    rbx
    movss   [player + BODY.yaw], xmm0
    xorps   xmm0, xmm0
    movss   [player + BODY.pitch], xmm0
    lea     rdi, [view_buf]
    call    player_eye
    lea     rdi, [view_buf + 12]
    call    player_forward
    pop     rbx
    ret

; cast(edi stack) -> eax spells_cast's answer: the runes in the stack are held, the Cast key is pressed
cast:
    sub     rsp, 8
    xor     esi, esi
    call    spells_input
    lea     rdi, [view_buf]
    lea     rsi, [view_buf + 12]
    call    spells_cast
    add     rsp, 8
    ret

; spawn(xmm0 x, xmm1 y, xmm2 z) -> eax the zombie's slot, -1 when none fits
spawn:
    sub     rsp, 8
    mov     edi, MOB_ZOMBIE
    call    mob_spawn
    add     rsp, 8
    ret

; SPAWN x, z (float constants, y = 11): a zombie; fails the test when none fits
%macro SPAWN 2
    movss   xmm0, [%1]
    movss   xmm1, [k_y11]
    movss   xmm2, [%2]
    call    spawn
    test    eax, eax
    js      .fail
%endmacro

; fly(): the projectiles fly up to 150 steps (until none is left)
fly:
    push    rbx
    mov     ebx, 150
.step:
    call    arrows_step
    dec     ebx
    jnz     .step
    pop     rbx
    ret

; live() -> eax the live projectiles
live:
    lea     rcx, [arrows]
    xor     eax, eax
    mov     edx, MAX_ARROWS
.l:
    cmp     dword [rcx + ARROWENT.live], 0
    setne   sil
    movzx   esi, sil
    add     eax, esi
    add     rcx, ARROWENT_size
    dec     edx
    jnz     .l
    ret

; hurt(slot) -> eax 1 when the mob lost health: MOBF(n, MOB.health) < MOBF(n, MOB.max_health)
%macro HURT 1
    mov     eax, MOBF(%1, MOB.health)
    cmp     eax, MOBF(%1, MOB.max_health)
%endmacro

; the plan's worked results (spells_resolve on every row of the table above)
; r12 = the row, r13d = rows left
test_spell_resolve:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    lea     r12, [vectors]
    mov     r13d, (vectors_end - vectors) / 44
.row:
    mov     edi, [r12]
    mov     esi, [r12 + 4]
    lea     rdx, [plan]
    call    spells_resolve
    cmp     eax, [r12 + 8]
    jne     .fail
    test    eax, eax
    jz      .next
    mov     eax, [r12 + 12]
    cmp     [plan + SPELLPLAN.delivery], eax
    jne     .fail
    mov     eax, [r12 + 16]
    cmp     [plan + SPELLPLAN.elems], eax
    jne     .fail
    mov     eax, [r12 + 20]
    cmp     [plan + SPELLPLAN.mods], eax
    jne     .fail
    mov     eax, [r12 + 24]
    cmp     [plan + SPELLPLAN.inert], eax
    jne     .fail
    mov     eax, [r12 + 28]
    cmp     [plan + SPELLPLAN.dropped], eax
    jne     .fail
    mov     eax, [r12 + 32]
    cmp     [plan + SPELLPLAN.cost], eax
    jne     .fail
    mov     eax, [r12 + 36]
    cmp     [plan + SPELLPLAN.cd], eax
    jne     .fail
    mov     eax, [r12 + 40]
    cmp     [plan + SPELLPLAN.dmg], eax
    jne     .fail
.next:
    add     r12, 44
    dec     r13d
    jnz     .row
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; Ball + Fire with 100 mana: 18 mana and a 30 step cooldown are spent and one PROJ_SPELL of the player's
; flies: carrying 8, a fire element in its flags, no pickup. Flying into a zombie 6 blocks ahead it hurts
; the zombie and sets it burning; the Ball is gone. With 10 mana the cast dry-fires: no mana spent, no
; cooldown, nothing flies.
test_spell_ball:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    movss   xmm0, [k_yaw0]
    call    aim
    SPAWN   k_x16_5, k_z10_5
    mov     edi, R(BALL) | R(FIRE)
    call    cast
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_mana], 82.0
    cmp     dword [spells_cd], 30
    jne     .fail
    cmp     dword [spells_cd_total], 30
    jne     .fail
    cmp     dword [arrows + ARROWENT.live], 1
    jne     .fail
    cmp     dword [arrows + ARROWENT.kind], PROJ_SPELL
    jne     .fail
    cmp     dword [arrows + ARROWENT.owner], 0
    jne     .fail
    cmp     dword [arrows + ARROWENT.pickup], 0
    jne     .fail
    cmp     dword [arrows + ARROWENT.damage], 8
    jne     .fail
    cmp     dword [arrows + ARROWENT.flags], ELEM_FIRE << AF_ELEM_SHIFT
    jne     .fail
    EXPECT_NEAR [arrows + ARROWENT.vz], -28.0
    call    fly
    call    live
    test    eax, eax
    jnz     .fail                       ; it ended on the zombie
    HURT    0
    jge     .fail
    cmp     dword MOBF(0, MOB.burn_t), 0
    jle     .fail
    call    cleanup                     ; ---- short of mana
    call    fixture
    SETF    [combat_mana], 10.0
    movss   xmm0, [k_yaw0]
    call    aim
    mov     edi, R(BALL) | R(FIRE)
    call    cast
    test    eax, eax
    jnz     .fail
    EXPECT_NEAR [combat_mana], 10.0
    cmp     dword [spells_cd], 0
    jne     .fail
    call    live
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; Three zombies in a line ahead: a plain Ball hurts the first only; with Pierce all three are hurt and the
; Ball is gone after the third. Chain: a Ball into a zombie with two more within 4 blocks of it (to its
; east and west) hurts all three, and a fourth 9 blocks away stays untouched.
test_spell_pierce_chain:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    movss   xmm0, [k_yaw0]
    call    aim
    SPAWN   k_x16_5, k_z10_5
    SPAWN   k_x16_5, k_z8_5
    SPAWN   k_x16_5, k_z6_5
    mov     edi, R(BALL)
    call    cast
    cmp     eax, 1
    jne     .fail
    call    fly
    HURT    0
    jge     .fail
    HURT    1
    jl      .fail
    HURT    2
    jl      .fail                       ; a plain Ball stops at the first
    call    cleanup                     ; ---- Pierce
    call    fixture
    movss   xmm0, [k_yaw0]
    call    aim
    SPAWN   k_x16_5, k_z10_5
    SPAWN   k_x16_5, k_z8_5
    SPAWN   k_x16_5, k_z6_5
    mov     edi, R(BALL) | R(PIERCE)
    call    cast
    cmp     eax, 1
    jne     .fail
    call    fly
    HURT    0
    jge     .fail
    HURT    1
    jge     .fail
    HURT    2
    jge     .fail
    call    live
    test    eax, eax
    jnz     .fail
    call    cleanup                     ; ---- Chain
    call    fixture
    movss   xmm0, [k_yaw0]
    call    aim
    SPAWN   k_x16_5, k_z10_5            ; the one the Ball meets
    SPAWN   k_x20_5, k_z10_5            ; 4 blocks east
    SPAWN   k_x12_5, k_z10_5            ; 4 blocks west
    SPAWN   k_x16_5, k_z1_5             ; 9 blocks north
    mov     edi, R(BALL) | R(CHAIN)
    call    cast
    cmp     eax, 1
    jne     .fail
    call    fly
    HURT    0
    jge     .fail
    HURT    1
    jge     .fail
    HURT    2
    jge     .fail
    HURT    3
    jl      .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; Laser + Frost: a zombie 10 blocks ahead is hurt and chilled on the cast frame itself; a stone wall 4.5
; blocks ahead shields it; it reaches only 12 blocks, so a zombie 20 blocks ahead is safe until Pierce
; doubles the range.
test_spell_laser:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    movss   xmm0, [k_yaw0]
    call    aim
    SPAWN   k_x16_5, k_z6_5
    mov     edi, R(LASER) | R(FROST)
    call    cast
    cmp     eax, 1
    jne     .fail
    HURT    0
    jge     .fail
    cmp     dword MOBF(0, MOB.chill_t), 0
    jle     .fail
    EXPECT_NEAR [combat_mana], 75.0
    cmp     dword [spells_cd], 90
    jne     .fail
    call    cleanup                     ; ---- a wall in the way
    call    fixture
%assign y 11
%rep 3
    mov     edi, 16
    mov     esi, y
    mov     edx, 11
    mov     ecx, STONE
    call    world_set
%assign y y + 1
%endrep
    movss   xmm0, [k_yaw0]
    call    aim
    SPAWN   k_x16_5, k_z6_5
    mov     edi, R(LASER) | R(FROST)
    call    cast
    cmp     eax, 1
    jne     .fail
    HURT    0
    jl      .fail                       ; the wall took the beam
    call    cleanup                     ; ---- 20 blocks: out of range, then within the range Pierce gives
    call    fixture
    movss   xmm0, [k_z1_5]
    movss   [player + BODY.z], xmm0
    movss   xmm0, [k_yaw180]
    call    aim
    SPAWN   k_x16_5, k_z21_5
    mov     edi, R(LASER)
    call    cast
    cmp     eax, 1
    jne     .fail
    HURT    0
    jl      .fail
    call    spells_reset
    SETF    [combat_mana], 100.0
    mov     edi, R(LASER) | R(PIERCE)
    call    cast
    cmp     eax, 1
    jne     .fail
    HURT    0
    jge     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; Nova + Frost: 27 mana and a 240 step cooldown; the zombies 4 blocks ahead and 4 blocks east are hurt and
; frozen at once (stunned 90 steps), the one 6 blocks ahead (beyond the 5 blocks of the burst) is not.
test_spell_nova_frost:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    movss   xmm0, [k_yaw0]
    call    aim
    SPAWN   k_x16_5, k_z12_5
    SPAWN   k_x20_5, k_x16_5
    SPAWN   k_x16_5, k_z10_5
    mov     edi, R(NOVA) | R(FROST)
    call    cast
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_mana], 73.0
    cmp     dword [spells_cd], 240
    jne     .fail
    HURT    0
    jge     .fail
    cmp     dword MOBF(0, MOB.stun), 90
    jne     .fail
    HURT    1
    jge     .fail
    cmp     dword MOBF(1, MOB.stun), 90
    jne     .fail
    HURT    2
    jl      .fail
    cmp     dword MOBF(2, MOB.stun), 0
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; Phase: a wall right in front leaves no room (under a block): the cast fails and costs nothing. With the wall
; 3.5 blocks away the player lands 3.0 blocks ahead, upright, motion and fall forgotten, 14 mana and 240
; steps spent.
test_spell_phase:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
%assign x 15
%rep 3
%assign y 11
%rep 3
    mov     edi, x
    mov     esi, y
    mov     edx, 15
    mov     ecx, STONE
    call    world_set
%assign y y + 1
%endrep
%assign x x + 1
%endrep
    movss   xmm0, [k_yaw0]
    call    aim
    mov     edi, R(PHASE)
    call    cast
    test    eax, eax
    jnz     .fail                       ; a wall 0.5 ahead: nowhere to go
    EXPECT_NEAR [combat_mana], 100.0
    cmp     dword [spells_cd], 0
    jne     .fail
    EXPECT_NEAR [player + BODY.z], 16.5
    call    cleanup                     ; ---- the wall 3.5 ahead
    call    fixture
%assign x 15
%rep 3
%assign y 11
%rep 3
    mov     edi, x
    mov     esi, y
    mov     edx, 12
    mov     ecx, STONE
    call    world_set
%assign y y + 1
%endrep
%assign x x + 1
%endrep
    SETF    [player + BODY.vy], -5.0
    SETF    [player + BODY.kbz], 3.0
    SETF    [player + BODY.fall], 5.0
    movss   xmm0, [k_yaw0]
    call    aim
    mov     edi, R(PHASE)
    call    cast
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [player + BODY.x], 16.5
    EXPECT_NEAR [player + BODY.y], 11.0
    EXPECT_NEAR [player + BODY.z], 13.5
    EXPECT_NEAR [player + BODY.vy], 0.0
    EXPECT_NEAR [player + BODY.kbz], 0.0
    EXPECT_NEAR [player + BODY.fall], 0.0
    EXPECT_NEAR [combat_mana], 86.0
    cmp     dword [spells_cd], 240
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; Ball + Fire + Poison into a zombie: it burns and is poisoned, each element a blow of its own
test_spell_multi_element:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    movss   xmm0, [k_yaw0]
    call    aim
    SPAWN   k_x16_5, k_z10_5
    mov     edi, R(FIRE) | R(POISON)    ; the Ball is implied
    call    cast
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_mana], 72.0
    cmp     dword [arrows + ARROWENT.damage], 10
    jne     .fail
    call    fly
    HURT    0
    jge     .fail
    cmp     dword MOBF(0, MOB.burn_t), 0
    jle     .fail
    cmp     dword MOBF(0, MOB.poison_t), 0
    jle     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; Seek: a zombie 3 blocks off the line of fire is missed by a plain Ball and caught by a Ball with Seek
test_spell_seek:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    movss   xmm0, [k_yaw0]
    call    aim
    SPAWN   k_x19_5, k_z9_5
    mov     edi, R(BALL)
    call    cast
    cmp     eax, 1
    jne     .fail
    call    fly
    HURT    0
    jl      .fail                       ; it flew past
    call    cleanup
    call    fixture
    movss   xmm0, [k_yaw0]
    call    aim
    SPAWN   k_x19_5, k_z9_5
    mov     edi, R(BALL) | R(SEEK)
    call    cast
    cmp     eax, 1
    jne     .fail
    call    fly
    HURT    0
    jge     .fail                       ; it turned towards the zombie
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; The boons. Heal from 6 of 20 health: +6 (a fifth is 4, at least 6) and 20 mana. Haste walks 1.3 times as
; fast. Feather leaps (vy 6) and a fall from 30 b/s with 10 blocks fallen becomes -2 b/s and no distance.
; rbx = the walking speed before Haste
test_spell_boons:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    movss   xmm0, [k_yaw0]
    call    aim
    mov     dword [surv_max_health], 20
    mov     dword [surv + SURVIVAL.health], 6
    mov     edi, R(HEAL)
    call    cast
    cmp     eax, 1
    jne     .fail
    cmp     dword [surv + SURVIVAL.health], 12
    jne     .fail
    EXPECT_NEAR [combat_mana], 80.0
    cmp     dword [spells_cd], 240
    jne     .fail
    call    spells_reset                ; ---- Haste
    call    combat_speed_mult
    movss   [rsp], xmm0
    mov     edi, R(HASTE)
    call    cast
    cmp     eax, 1
    jne     .fail
    cmp     dword [combat_haste_t], 600
    jne     .fail
    call    combat_speed_mult
    movss   xmm1, [rsp]
    mulss   xmm1, [k_1_3]
    call    close_to
    test    eax, eax
    jz      .fail
    call    spells_reset                ; ---- Feather
    SETF    [combat_mana], 100.0
    mov     edi, R(FEATHER)
    call    cast
    cmp     eax, 1
    jne     .fail
    cmp     dword [combat_feather_t], 300
    jne     .fail
    EXPECT_NEAR [player + BODY.vy], 6.0
    SETF    [player + BODY.fall], 10.0
    SETF    [player + BODY.vy], -30.0
    call    spells_step
    EXPECT_NEAR [player + BODY.fall], 0.0
    EXPECT_NEAR [player + BODY.vy], -2.0
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; A tapped rune stays armed for 45 steps (the cast stack is held | armed) and is forgotten after that; a
; Fire tapped and then 30 steps later a held Ball and the Cast key is a Ball with fire; 46 steps later it
; is a plain Ball.
test_spell_arming:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    movss   xmm0, [k_yaw0]
    call    aim
    mov     edi, 0
    mov     esi, R(FIRE)
    call    spells_input
    mov     ebx, 30
.wait:
    call    spells_step
    dec     ebx
    jnz     .wait
    cmp     dword [spells_armed], R(FIRE)
    jne     .fail
    mov     edi, R(BALL)
    call    cast
    cmp     eax, 1
    jne     .fail
    cmp     dword [arrows + ARROWENT.flags], ELEM_FIRE << AF_ELEM_SHIFT
    jne     .fail
    cmp     dword [spells_armed], 0     ; a cast clears the armed runes
    jne     .fail
    call    cleanup                     ; ---- 46 steps later
    call    fixture
    movss   xmm0, [k_yaw0]
    call    aim
    mov     edi, 0
    mov     esi, R(FIRE)
    call    spells_input
    mov     ebx, 46
.wait2:
    call    spells_step
    dec     ebx
    jnz     .wait2
    cmp     dword [spells_armed], 0
    jne     .fail
    mov     edi, R(BALL)
    call    cast
    cmp     eax, 1
    jne     .fail
    cmp     dword [arrows + ARROWENT.flags], 0
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; Blood Magic pays the 10 mana of a Ball with ceil(10 / 5) = 2 health (12 -> 10): the mana stays, the hurt
; flash is 6, the cooldown runs and a Ball flies. With 2 health left (not more than the cost) the cast fails
; and costs nothing.
test_spell_blood_magic:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    or      dword [rpg_keystones], 1 << KS_BLOOD_MAGIC
    movss   xmm0, [k_yaw0]
    call    aim
    mov     dword [surv + SURVIVAL.health], 12
    mov     edi, R(BALL)
    call    cast
    cmp     eax, 1
    jne     .fail
    cmp     dword [surv + SURVIVAL.health], 10
    jne     .fail
    EXPECT_NEAR [combat_mana], 100.0
    cmp     dword [surv + SURVIVAL.hurt_flash], 6
    jne     .fail
    cmp     dword [spells_cd], 30
    jne     .fail
    call    live
    cmp     eax, 1
    jne     .fail
    call    spells_reset
    call    arrows_clear
    mov     dword [surv + SURVIVAL.health], 2
    mov     edi, R(BALL)
    call    cast
    test    eax, eax
    jnz     .fail
    cmp     dword [surv + SURVIVAL.health], 2
    jne     .fail
    cmp     dword [spells_cd], 0
    jne     .fail
    call    live
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; The text under the HUD strip: names joined by " + ", the mana, what is inert or dropped; and "Nothing to cast"
test_spell_preview:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    mov     edi, R(LASER) | R(FROST) | R(PIERCE)
    xor     esi, esi
    call    spells_input
    lea     rdi, [text]
    call    spells_preview
    cmp     eax, 1
    jne     .fail
    lea     rdi, [text]
    lea     rsi, [s_pv_laser]
    call    str_eq
    test    eax, eax
    jz      .fail
    mov     edi, R(BALL) | R(LASER) | R(FIRE) | R(BURST) | R(SEEK) | R(HEAL)
    xor     esi, esi
    call    spells_input
    lea     rdi, [text]
    call    spells_preview
    cmp     eax, 1
    jne     .fail
    lea     rdi, [text]
    lea     rsi, [s_pv_inert]
    call    str_eq
    test    eax, eax
    jz      .fail
    xor     edi, edi
    xor     esi, esi
    call    spells_input
    lea     rdi, [text]
    call    spells_preview
    test    eax, eax
    jnz     .fail
    lea     rdi, [text]
    lea     rsi, [s_pv_nothing]
    call    str_eq
    test    eax, eax
    jz      .fail
    mov     rax, 0x5A5A5A5A5A5A5A5A     ; ---- every rune held: the longest text there is fits the buffer
    mov     [canary], rax
    mov     edi, ALL_RUNES
    xor     esi, esi
    call    spells_input
    lea     rdi, [text]
    call    spells_preview
    mov     rax, 0x5A5A5A5A5A5A5A5A
    cmp     [canary], rax
    jne     .fail
    lea     rdi, [text]
    call    str_len
    cmp     eax, 150                    ; names of four runes, three inert, twelve dropped
    jb      .fail
    cmp     eax, 191
    ja      .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; Dash: 8 mana and 120 steps; the player is shoved 18 b/s along -z, untouchable for 20 steps, the fall
; forgotten; looking straight down there is no direction to dash in (nothing is paid). Burst: a Ball with
; Burst explodes where it hits: a zombie 2 blocks beside the one it hit is hurt too, and the Ball is gone.
test_spell_dash_burst:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    movss   xmm0, [k_yaw0]
    call    aim
    SETF    [player + BODY.fall], 4.0
    mov     edi, R(DASH)
    call    cast
    cmp     eax, 1
    jne     .fail
    EXPECT_NEAR [combat_mana], 92.0
    cmp     dword [spells_cd], 120
    jne     .fail
    EXPECT_NEAR [player + BODY.kbz], -18.0
    EXPECT_NEAR [player + BODY.kbx], 0.0
    EXPECT_NEAR [player + BODY.fall], 0.0
    cmp     dword [surv + SURVIVAL.invuln], 20
    jne     .fail
    call    cleanup                     ; ---- looking straight down
    call    fixture
    movss   xmm0, [k_yaw0]
    call    aim
    movss   xmm0, [k_pitch90]
    movss   [player + BODY.pitch], xmm0
    lea     rdi, [view_buf + 12]
    call    player_forward
    mov     edi, R(DASH)
    call    cast
    test    eax, eax
    jnz     .fail
    EXPECT_NEAR [combat_mana], 100.0
    cmp     dword [spells_cd], 0
    jne     .fail
    call    cleanup                     ; ---- Burst
    call    fixture
    movss   xmm0, [k_yaw0]
    call    aim
    SPAWN   k_x16_5, k_z10_5
    SPAWN   k_x18_5, k_z10_5
    mov     edi, R(BALL) | R(BURST)
    call    cast
    cmp     eax, 1
    jne     .fail
    call    fly
    HURT    0
    jge     .fail
    HURT    1
    jge     .fail
    call    live
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret
