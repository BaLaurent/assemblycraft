; test_events.asm - 0.12 events (events.asm): the wave sizes, a temporary camp from offer to loot and cleanup, night waves
; (monsters) against Peaceful ones (raiders), a protected leader's death, an abandoned event, a monster's blows on a
; defender, a free caravan from offer to arrival (ambushes at 35 % and 70 %), the daily threat flags of a camp's
; leader, and the EVHUD on the wire. The events step is called directly (the mobs never move). Every test restores what
; it touched.
%include "common.inc"
default rel

global test_events_wave_size, test_events_camp_flow, test_events_night_wave, test_events_leader_dies
global test_events_abandon, test_events_monster_strike, test_events_caravan_flow, test_events_threat_flags
global test_events_net

extern mobs, mobs_clear, mobs_shift, mob_spawn, drops, drops_clear, arrows_clear
extern player, body_init, rng_seed, world_clear, world_set, world_origin_x, world_origin_z
extern game_mode, game_time, settings, surv, survival_reset, inv_clear, rpg_reset, rpg_state
extern combat_reset, combat_hit_flags, world_header, banner_text, site_count, gen_seed, worldgen_set_seed
extern faction_reset, faction_names, faction_rivals, folk_spawn, hash32
extern ev_hud, ev_wave_size, events_reset, events_step, events_shift, events_accept, events_net_apply
extern events_state_send, events_spawn_camp, events_spawn_caravan, events_force_threat
extern evs_find_route, evs_tent_placed
extern net_role, net_self, net_applying, net_capture, net_captured, net_peers

%define CAP_SIZE 2048

section .rodata
align 4
k_half_w:   dd 0.3
k_height:   dd 1.8
k_speed:    dd 4.317
k_one:      dd 1.0
k_300:      dd 300.0
k_40:       dd 40.0
k_0_4:      dd 0.4
k_0_75:     dd 0.75
k_24:       dd 24.0
k_half:     dd 0.5
k_mone:     dd -1.0
start_standing: dw 200, -100, -100, 0, 0
s_a:            db "A ", 0
s_camp_asks:    db " camp asks for help nearby", 0
s_the:          db "The ", 0
s_camp_safe:    db " camp is safe!", 0
s_camp_fell:    db " camp has fallen", 0
s_camp_thr:     db " camp is under threat!", 0
s_defend:       db "Defend the camp! 3 waves", 0
s_w1_mon:       db "Wave 1/3: monsters!", 0
s_w1_raid:      db "Wave 1/3: raiders!", 0
s_abandoned:    db "Event abandoned", 0
s_ambush:       db "Ambush!", 0
s_arrived:      db "The caravan has arrived!", 0
s_escort:       db "Escort the caravan!", 0

section .bss
alignb 8
cap:         resb CAP_SIZE
bnr:         resb 96                    ; a banner under construction
t_u:         resd 8                     ; the caravan's geometry: Sx, Sz, Dx, Dz, ux, uz, len
t_ax:        resd 2
t_xp:        resd 2                     ; the player's level and XP before
t_hp:        resd 2
t_keep:      resd 4                     ; net_role, net_self, net_applying, gen_seed
alignb 4
t_peers:     resb PEER_size * NET_MAX_PEERS

section .text

%macro SETF 2
    mov     dword %1, __float32__(%2)
%endmacro

; ---- harness ---------------------------------------------------------------------------------------------------------

; fixture(): rng seed 1234, no mobs, arrows, drops or inventory, a level-1 character, the starting standings, no event, Survival
; at Normal difficulty in the morning, no banner, no cached sites, origin 0, the player at (120.5, 11, 120.5)
fixture:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 8
    mov     edi, 1234
    call    rng_seed
    call    mobs_clear
    call    arrows_clear
    call    drops_clear
    call    inv_clear
    call    rpg_reset
    call    survival_reset
    call    combat_reset
    call    faction_reset
    call    events_reset
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    mov     dword [game_time], NEW_WORLD_TIME
    mov     byte [banner_text], 0
    mov     dword [site_count], 0
    mov     dword [world_origin_x], 0
    mov     dword [world_origin_z], 0
    lea     rdi, [player]
    movss   xmm0, [k_half_w]
    movss   xmm1, [k_height]
    movss   xmm2, [k_speed]
    call    body_init
    SETF    [player + BODY.x], 120.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 120.5
    add     rsp, 8
    pop     rbp
    ret


; fixture_big(): world_clear, fixture and a STONE floor at y = 10 for x, z in 20 .. 220
fixture_big:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 8
    call    world_clear
    call    fixture
    mov     edi, 20
    mov     esi, 20
    mov     edx, 220
    mov     ecx, 220
    call    patch_rows
    add     rsp, 8
    pop     rbp
    ret

; patch_rows(edi x0, esi z0, edx x1, ecx z1): as patch, plainly
; rbx = x, r12d = z, r13d = x0, r14d = x1, r15d = z1
patch_rows:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r13d, edi
    mov     r12d, esi
    mov     r14d, edx
    mov     r15d, ecx
.z:
    mov     ebx, r13d
.x:
    mov     edi, ebx
    mov     esi, 10
    mov     edx, r12d
    mov     ecx, STONE
    call    world_set
    inc     ebx
    cmp     ebx, r14d
    jle     .x
    inc     r12d
    cmp     r12d, r15d
    jle     .z
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; cleanup(): leave no mobs, drops, banner, event, role or standings changed behind
cleanup:
    sub     rsp, 8
    call    mobs_clear
    call    arrows_clear
    call    drops_clear
    call    inv_clear
    call    combat_reset
    call    faction_reset
    call    events_reset
    call    rpg_reset
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    mov     dword [game_time], NEW_WORLD_TIME
    mov     byte [banner_text], 0
    mov     dword [site_count], 0
    mov     dword [world_origin_x], 0
    mov     dword [world_origin_z], 0
    SETF    [player + BODY.x], 100.5
    SETF    [player + BODY.z], 100.5
    add     rsp, 8
    ret

; mob_ptr(edi idx) -> rax the mob in that slot
mob_ptr:
    imul    eax, edi, MOB_size
    lea     rcx, [mobs]
    add     rax, rcx
    ret

; steps(edi n): n events steps
steps:
    push    rbx
    mov     ebx, edi
.l:
    call    events_step
    dec     ebx
    jnz     .l
    pop     rbx
    ret

; standing(edi faction) -> eax
standing:
    lea     rcx, [world_header + WORLDHDR.standing]
    movsx   eax, word [rcx + rdi*2]
    ret

; set_standing(edi faction, esi standing)
set_standing:
    lea     rcx, [world_header + WORLDHDR.standing]
    mov     [rcx + rdi*2], si
    ret

; streq(rdi a, rsi b) -> eax 1 when the two NUL-terminated strings are equal
streq:
.l:
    mov     al, [rdi]
    cmp     al, [rsi]
    jne     .no
    test    al, al
    jz      .yes
    inc     rdi
    inc     rsi
    jmp     .l
.yes:
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; banner_is(rdi expected) -> eax 1 when the HUD banner shows exactly that text
banner_is:
    sub     rsp, 8
    mov     rsi, rdi
    lea     rdi, [banner_text]
    call    streq
    add     rsp, 8
    ret

; banner3(rdi head, esi faction, rdx tail) -> eax 1 when the banner is head + the faction's name + tail
banner3:
    push    rbx
    push    r12
    push    r13
    mov     r12d, esi
    mov     r13, rdx
    lea     rbx, [bnr]
.h:
    mov     al, [rdi]
    test    al, al
    jz      .name
    mov     [rbx], al
    inc     rbx
    inc     rdi
    jmp     .h
.name:
    lea     rcx, [faction_names]
    mov     rsi, [rcx + r12*8]
.n:
    mov     al, [rsi]
    test    al, al
    jz      .tail
    mov     [rbx], al
    inc     rbx
    inc     rsi
    jmp     .n
.tail:
    mov     rsi, r13
.t:
    mov     al, [rsi]
    mov     [rbx], al
    inc     rbx
    inc     rsi
    test    al, al
    jnz     .t
    lea     rdi, [bnr]
    call    banner_is
    pop     r13
    pop     r12
    pop     rbx
    ret

; key_of_leader() -> eax the defenders' key: the protected NPC's patrol (needs a step since the event began)
key_of_leader:
    movzx   edi, byte [ev_hud + EVHUD.protect]
    cmp     edi, MAX_MOBS
    jae     .none
    imul    eax, edi, MOB_size
    lea     rcx, [mobs]
    mov     eax, [rcx + rax + MOB.patrol]
    ret
.none:
    xor     eax, eax
    ret

; att_count(edi key) -> eax the live mobs carrying key | 2
att_count:
    or      edi, EV_KEY_ATTACK
    lea     rcx, [mobs]
    mov     edx, MAX_MOBS
    xor     eax, eax
.l:
    cmp     dword [rcx + MOB.type], MOB_NONE
    je      .n
    cmp     [rcx + MOB.patrol], edi
    jne     .n
    inc     eax
.n:
    add     rcx, MOB_size
    dec     edx
    jnz     .l
    ret

; kill_att(edi key): every mob carrying key | 2 is gone
kill_att:
    or      edi, EV_KEY_ATTACK
    lea     rcx, [mobs]
    mov     edx, MAX_MOBS
.l:
    cmp     [rcx + MOB.patrol], edi
    jne     .n
    mov     dword [rcx + MOB.type], MOB_NONE
.n:
    add     rcx, MOB_size
    dec     edx
    jnz     .l
    ret

; defenders(edi key, esi role) -> eax the folk of that role carrying the key
defenders:
    lea     rcx, [mobs]
    mov     edx, MAX_MOBS
    xor     eax, eax
.l:
    cmp     dword [rcx + MOB.type], MOB_FOLK
    jne     .n
    cmp     [rcx + MOB.patrol], edi
    jne     .n
    movzx   r8d, byte [rcx + MOB.role]
    cmp     r8d, esi
    jne     .n
    inc     eax
.n:
    add     rcx, MOB_size
    dec     edx
    jnz     .l
    ret

; raiders_ok(edi key, esi defended faction, edx expected) -> eax 1 when exactly that many attackers live and all are
; ROLE_PATROL folk of a rival faction, provoked, carrying key | 2
; r8d = count
raiders_ok:
    or      edi, EV_KEY_ATTACK
    lea r9, [faction_rivals]
    movzx   r9d, byte [r9 + rsi]
    lea     rcx, [mobs]
    mov     r10d, MAX_MOBS
    xor     r8d, r8d
.l:
    cmp     dword [rcx + MOB.type], MOB_NONE
    je      .n
    cmp     [rcx + MOB.patrol], edi
    jne     .n
    cmp     dword [rcx + MOB.type], MOB_FOLK
    jne     .bad
    cmp     byte [rcx + MOB.role], ROLE_PATROL
    jne     .bad
    movzx   eax, byte [rcx + MOB.faction]
    bt      r9d, eax
    jnc     .bad
    cmp     dword [rcx + MOB.provoked], 0
    jle     .bad
    inc     r8d
.n:
    add     rcx, MOB_size
    dec     r10d
    jnz     .l
    xor     eax, eax
    cmp     r8d, edx
    sete    al
    ret
.bad:
    xor     eax, eax
    ret

; monsters_ok(edi key, edx expected) -> eax 1 when exactly that many attackers live and all are zombies, skeletons or spiders
monsters_ok:
    or      edi, EV_KEY_ATTACK
    lea     rcx, [mobs]
    mov     r10d, MAX_MOBS
    xor     r8d, r8d
.l:
    mov     eax, [rcx + MOB.type]
    test    eax, eax
    jz      .n
    cmp     [rcx + MOB.patrol], edi
    jne     .n
    cmp     eax, MOB_ZOMBIE
    je      .ok
    cmp     eax, MOB_SKELETON
    je      .ok
    cmp     eax, MOB_SPIDER
    jne     .bad
.ok:
    inc     r8d
.n:
    add     rcx, MOB_size
    dec     r10d
    jnz     .l
    xor     eax, eax
    cmp     r8d, edx
    sete    al
    ret
.bad:
    xor     eax, eax
    ret

; drop_kinds() -> eax the item entities on the ground
drop_kinds:
    lea     rcx, [drops]
    mov     edx, MAX_DROPS
    xor     eax, eax
.l:
    cmp     byte [rcx + DROP.id], 0
    je      .n
    inc     eax
.n:
    add     rcx, DROP_size
    dec     edx
    jnz     .l
    ret

; camp_up() -> eax the leader's slot of a camp that was offered and accepted, or -1. The event is stepped once (OFFERED
; seen), then the leader accepts: COUNTDOWN with its 600 steps still to run
camp_up:
    push    rbx
    sub     rsp, 16
    lea     rdi, [player]
    call    events_spawn_camp
    cmp     eax, 1
    jne     .fail
    mov     edi, 1
    call    steps
    movzx   ebx, byte [ev_hud + EVHUD.protect]
    cmp     ebx, MAX_MOBS
    jae     .fail
    mov     edi, ebx
    call    events_accept
    cmp     eax, 1
    jne     .fail
    mov     eax, ebx
    jmp     .ret
.fail:
    mov     eax, -1
.ret:
    add     rsp, 16
    pop     rbx
    ret

%macro BEGIN 0
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40
%endmacro
%macro END 0
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
%endmacro
%macro EXPECT_B 2
    cmp     byte %1, %2
    jne     .fail
%endmacro
%macro EXPECT_D 2
    cmp     dword %1, %2
    jne     .fail
%endmacro
; SAY head, faction reg, tail: the banner is head + the faction + tail
%macro SAY 3
    lea     rdi, [%1]
    mov     esi, %2
    lea     rdx, [%3]
    call    banner3
    test    eax, eax
    jz      .fail
%endmacro
%macro SAYS 1
    lea     rdi, [%1]
    call    banner_is
    test    eax, eax
    jz      .fail
%endmacro

; ---- ev_wave_size ----------------------------------------------------------------------------------------------------

; min(3 + n + players - 1, 8, free - 4), floored at 0: (1,1,64) 4, (4,1,64) 7, (4,3,64) 8 (the cap), (3,1,6) 2 and (1,1,5) 1
; (the free slots), (1,1,4) 0
test_events_wave_size:
    push    rbp
    mov     rbp, rsp
    mov     edi, 1
    mov     esi, 1
    mov     edx, 64
    call    ev_wave_size
    cmp     eax, 4
    jne     .fail
    mov     edi, 4
    mov     esi, 1
    mov     edx, 64
    call    ev_wave_size
    cmp     eax, 7
    jne     .fail
    mov     edi, 4
    mov     esi, 3
    mov     edx, 64
    call    ev_wave_size
    cmp     eax, 8
    jne     .fail
    mov     edi, 3
    mov     esi, 1
    mov     edx, 6
    call    ev_wave_size
    cmp     eax, 2
    jne     .fail
    mov     edi, 1
    mov     esi, 1
    mov     edx, 5
    call    ev_wave_size
    cmp     eax, 1
    jne     .fail
    mov     edi, 1
    mov     esi, 1
    mov     edx, 4
    call    ev_wave_size
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    pop     rbp
    ret

; ---- test_events_camp_flow -------------------------------------------------------------------------------------------

; A temporary camp: offered (a leader with FF_HELP, 2 guards, the banner), the origin shift keeps its HUD cell, accepted (the
; START banner, 10 s countdown), then 3 waves of 4, 5 and 6 rival raiders (provoked, key | 2; the last wave's first is an
; elite), a break between; the last wave cleared pays +40 standing, loot (>= 3 drops) and XP, the banner says the camp is safe,
; and once the player leaves the event's mobs and the tent go.
; rbx = the leader, r12d = the faction, r13d = the standing before, r14d = the wave
test_events_camp_flow:
    BEGIN
    call    fixture_big
    mov     eax, [rpg_state + RPGSAVE.xp]
    mov     [t_xp], eax
    movzx   eax, byte [rpg_state + RPGSAVE.level]
    mov     [t_xp + 4], eax
    lea     rdi, [player]
    call    events_spawn_camp
    cmp     eax, 1
    jne     .fail
    mov     edi, 1
    call    steps
    EXPECT_B [ev_hud + EVHUD.state], EVS_OFFERED
    EXPECT_B [ev_hud + EVHUD.kind], EVK_CAMP
    EXPECT_B [ev_hud + EVHUD.waves], 3
    movzx   ebx, byte [ev_hud + EVHUD.protect]
    cmp     ebx, MAX_MOBS
    jae     .fail
    movzx   r12d, byte [ev_hud + EVHUD.faction]
    mov     edi, r12d
    call    standing
    test    eax, eax
    js      .fail                           ; an eligible faction
    mov     r13d, eax
    mov     edi, ebx
    call    mob_ptr
    EXPECT_D [rax + MOB.type], MOB_FOLK
    EXPECT_B [rax + MOB.role], ROLE_LEADER
    test    byte [rax + MOB.fflags], FF_HELP
    jz      .fail
    call    key_of_leader
    mov     r15d, eax
    mov     edi, r15d
    mov     esi, ROLE_GUARD
    call    defenders
    cmp     eax, 2
    jne     .fail
    SAY     s_a, r12d, s_camp_asks
    ; the origin moves: the HUD cell stays
    mov     eax, [ev_hud + EVHUD.ax]
    mov     [t_ax], eax
    mov     eax, [ev_hud + EVHUD.az]
    mov     [t_ax + 4], eax
    mov     edi, 512
    xor     esi, esi
    call    events_shift
    mov     edi, 512
    xor     esi, esi
    call    mobs_shift
    add     dword [world_origin_x], 512
    mov     edi, 1
    call    steps
    mov     eax, [t_ax]
    cmp     [ev_hud + EVHUD.ax], eax
    jne     .fail
    mov     eax, [t_ax + 4]
    cmp     [ev_hud + EVHUD.az], eax
    jne     .fail
    mov     edi, -512
    xor     esi, esi
    call    events_shift
    mov     edi, -512
    xor     esi, esi
    call    mobs_shift
    sub     dword [world_origin_x], 512
    ; accept
    mov     edi, ebx
    call    events_accept
    cmp     eax, 1
    jne     .fail
    mov     edi, ebx
    call    mob_ptr
    test    byte [rax + MOB.fflags], FF_HELP
    jnz     .fail
    mov     edi, ebx
    call    events_accept                   ; no offer any more
    test    eax, eax
    jnz     .fail
    SAYS    s_defend
    mov     edi, 1
    call    steps
    EXPECT_B [ev_hud + EVHUD.state], EVS_COUNTDOWN
    cmp     word [ev_hud + EVHUD.secs], 10
    jne     .fail
    mov     edi, 599
    call    steps
    EXPECT_B [ev_hud + EVHUD.state], EVS_WAVE
    EXPECT_B [ev_hud + EVHUD.wave], 1
    mov     r14d, 1
.wave:
    mov     edi, 6
    call    steps
    movzx   eax, byte [ev_hud + EVHUD.wave]
    cmp     eax, r14d
    jne     .fail
    EXPECT_B [ev_hud + EVHUD.state], EVS_WAVE
    mov     edi, r15d
    mov     esi, r12d
    lea     edx, [r14 + 3]
    call    raiders_ok
    test    eax, eax
    jz      .fail
    movzx   eax, byte [ev_hud + EVHUD.left]
    lea     ecx, [r14 + 3]
    cmp     eax, ecx
    jne     .fail
    ; elites among the attackers: one in the last wave, none before
    lea     rcx, [mobs]
    mov     edx, MAX_MOBS
    xor     r8d, r8d
    lea     r9d, [r15 + 2]
.el:
    cmp     dword [rcx + MOB.type], MOB_NONE
    je      .eln
    cmp     [rcx + MOB.patrol], r9d
    jne     .eln
    add     r8d, [rcx + MOB.elite]
.eln:
    add     rcx, MOB_size
    dec     edx
    jnz     .el
    xor     eax, eax
    cmp     r14d, 3
    jne     .el_ok
    mov     eax, 1
.el_ok:
    cmp     r8d, eax
    jne     .fail
    mov     edi, r15d
    call    kill_att
    mov     edi, 2
    call    steps
    cmp     r14d, 3
    je      .won
    EXPECT_B [ev_hud + EVHUD.state], EVS_BREAK
    mov     edi, 1200
    call    steps
    inc     r14d
    jmp     .wave
.won:
    EXPECT_B [ev_hud + EVHUD.state], EVS_CLEANUP
    SAY     s_the, r12d, s_camp_safe
    mov     edi, r12d
    call    standing
    lea     ecx, [r13 + 40]
    cmp     eax, ecx
    jne     .fail
    call    drop_kinds
    cmp     eax, 3
    jb      .fail
    mov     eax, [rpg_state + RPGSAVE.xp]
    movzx   ecx, byte [rpg_state + RPGSAVE.level]
    cmp     eax, [t_xp]
    jne     .xp_ok
    cmp     ecx, [t_xp + 4]
    je      .fail
.xp_ok:
    ; the player leaves: the camp's folk and its tent go
    mov     edi, ebx
    call    mob_ptr
    EXPECT_D [rax + MOB.type], MOB_FOLK
    SETF    [player + BODY.x], 520.5
    mov     edi, 130
    call    steps
    EXPECT_B [ev_hud + EVHUD.state], EVS_NONE
    mov     edi, ebx
    call    mob_ptr
    EXPECT_D [rax + MOB.type], MOB_NONE
    call    evs_tent_placed
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    END

; ---- test_events_night_wave ------------------------------------------------------------------------------------------

; By night the wave is monsters (zombie / skeleton / spider carrying key | 2, no folk) and its banner says so; at Peaceful it is
; raiders even by night
test_events_night_wave:
    BEGIN
    call    fixture_big
    mov     dword [game_time], 54000        ; midnight
    call    camp_up
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, 606
    call    steps
    EXPECT_B [ev_hud + EVHUD.state], EVS_WAVE
    call    key_of_leader
    mov     r15d, eax
    mov     edi, r15d
    mov     edx, 4
    call    monsters_ok
    test    eax, eax
    jz      .fail
    SAYS    s_w1_mon
    call    cleanup
    call    fixture_big
    mov     dword [game_time], 54000
    mov     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL
    call    camp_up
    test    eax, eax
    js      .fail
    mov     edi, 606
    call    steps
    EXPECT_B [ev_hud + EVHUD.state], EVS_WAVE
    movzx   r12d, byte [ev_hud + EVHUD.faction]
    call    key_of_leader
    mov     edi, eax
    mov     esi, r12d
    mov     edx, 4
    call    raiders_ok
    test    eax, eax
    jz      .fail
    SAYS    s_w1_raid
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    END

; ---- test_events_leader_dies -----------------------------------------------------------------------------------------

; The protected leader falls mid-wave: the event is lost ("... has fallen"), the standing is unchanged, CLEANUP
test_events_leader_dies:
    BEGIN
    call    fixture_big
    call    camp_up
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, 606
    call    steps
    EXPECT_B [ev_hud + EVHUD.state], EVS_WAVE
    movzx   r12d, byte [ev_hud + EVHUD.faction]
    mov     edi, r12d
    call    standing
    mov     r13d, eax
    mov     edi, ebx
    call    mob_ptr
    mov     dword [rax + MOB.type], MOB_NONE
    mov     byte [banner_text], 0
    mov     edi, 1
    call    steps
    EXPECT_B [ev_hud + EVHUD.state], EVS_CLEANUP
    SAY     s_the, r12d, s_camp_fell
    mov     edi, r12d
    call    standing
    cmp     eax, r13d
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    END

; ---- test_events_abandon ---------------------------------------------------------------------------------------------

; No player within 96 blocks of the camp for 3600 steps in a row: "Event abandoned". After 3599 it is still on.
test_events_abandon:
    BEGIN
    call    fixture_big
    call    camp_up
    test    eax, eax
    js      .fail
    SETF    [player + BODY.x], 420.5        ; 300 blocks away
    mov     edi, 3599
    call    steps
    movzx   eax, byte [ev_hud + EVHUD.state]
    cmp     eax, EVS_COUNTDOWN
    jb      .fail
    cmp     eax, EVS_AMBUSH
    ja      .fail
    SAYS    s_w1_raid
    mov     edi, 1
    call    steps
    EXPECT_B [ev_hud + EVHUD.state], EVS_CLEANUP
    SAYS    s_abandoned
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    END

; ---- test_events_monster_strike --------------------------------------------------------------------------------------

; An event zombie 1 block from the defender leader strikes it on the next step; the step after it does not (60-step
; cooldown); 60 steps later it does again. A zombie 3 blocks off strikes nothing.
; rbx = the leader, r12d = the zombie
test_events_monster_strike:
    BEGIN
    call    fixture_big
    call    camp_up
    test    eax, eax
    js      .fail
    mov     ebx, eax
    call    key_of_leader
    mov     r15d, eax
    mov     edi, ebx
    call    mob_ptr
    mov     r13, rax
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [r13 + BODY.x]
    addss   xmm0, [k_one]
    movss   xmm1, [r13 + BODY.y]
    movss   xmm2, [r13 + BODY.z]
    call    mob_spawn
    test    eax, eax
    js      .fail
    mov     r12d, eax
    mov     edi, r12d
    call    mob_ptr
    lea     ecx, [r15 + 2]
    mov     [rax + MOB.patrol], ecx
    mov     eax, [r13 + MOB.health]
    mov     [t_hp], eax
    mov     edi, 1
    call    steps
    mov     eax, [r13 + MOB.health]
    cmp     eax, [t_hp]
    jge     .fail                           ; struck
    mov     [t_hp], eax
    mov     dword [r13 + MOB.hurt], 0       ; the hurt window is out of it: only the 60-step cooldown holds the next blow back
    mov     edi, 1
    call    steps
    mov     eax, [r13 + MOB.health]
    cmp     eax, [t_hp]
    jne     .fail                           ; cooling down
    mov     dword [r13 + MOB.hurt], 0       ; (the mobs do not step here: the hurt window would never close)
    mov     edi, 70
    call    steps
    mov     eax, [r13 + MOB.health]
    cmp     eax, [t_hp]
    jge     .fail                           ; again
    ; too far
    mov     [t_hp], eax
    mov     edi, r12d
    call    mob_ptr
    movss   xmm0, [r13 + BODY.x]
    addss   xmm0, [k_40]
    movss   [rax + BODY.x], xmm0
    mov     dword [r13 + MOB.hurt], 0       ; a blow that landed now would show
    mov     edi, 130
    call    steps
    mov     eax, [r13 + MOB.health]
    cmp     eax, [t_hp]
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    END

; ---- test_events_caravan_flow ----------------------------------------------------------------------------------------

; route_point(xmm0 t) -> xmm0 x, xmm1 z: the point t of the way from S to D (t_u: Sx, Sz, Dx, Dz, ux, uz, len)
route_point:
    mulss   xmm0, [t_u + 24]
    movss   xmm1, xmm0
    mulss   xmm0, [t_u + 16]
    addss   xmm0, [t_u]
    mulss   xmm1, [t_u + 20]
    addss   xmm1, [t_u + 4]
    ret

; party_at(xmm0 x, xmm1 z): the merchant (slot r12d... the caller's rbx) and the player stand there
; (rdi = the merchant's mob)
party_at:
    movss   [rdi + BODY.x], xmm0
    movss   [rdi + BODY.z], xmm1
    SETF    [rdi + BODY.y], 11.0
    movss   [player + BODY.x], xmm0
    movss   [player + BODY.z], xmm1
    ret

; ambush_patch(xmm0 t): a floor 16 blocks round the point 24 blocks ahead of route point t
ambush_patch:
    sub     rsp, 8
    call    route_point
    movss   xmm2, [t_u + 16]
    mulss   xmm2, [k_24]
    addss   xmm0, xmm2
    movss   xmm2, [t_u + 20]
    mulss   xmm2, [k_24]
    addss   xmm1, xmm2
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    roundss xmm1, xmm1, 9
    cvttss2si ecx, xmm1
    lea     edi, [rax - 16]
    lea     esi, [rcx - 16]
    lea     edx, [rax + 16]
    add     ecx, 16
    call    patch_rows
    add     rsp, 8
    ret

; A free caravan on a land seed: offered (merchant with FF_HELP and FF_HALT, two guards), accepted, 10 s, it sets off. With a
; player near it walks (no FF_HALT); with none it waits (FF_HALT and EHF_WAIT). Past 35 % an ambush: FF_HALT, "Ambush!", raiders
; spawn ahead; cleared, the party travels on; the same at 70 %; at the destination "The caravan has arrived!" and +30 standing.
; rbx = the merchant, r12d = the faction, r13d = the standing before, r14d = tries, r15d = the key
test_events_caravan_flow:
    BEGIN
    mov     eax, [gen_seed]
    mov     [t_keep + 12], eax
    mov     r14d, 1
.seed:                                      ; a seed with land round the player
    mov     edi, r14d
    call    worldgen_set_seed
    mov     edi, 120
    mov     esi, 120
    lea     rdx, [t_ax]
    call    evs_find_route
    test    eax, eax
    jnz     .seeded
    inc     r14d
    cmp     r14d, 80
    jb      .seed
    jmp     .fail
.seeded:
    call    world_clear
    call    fixture
    mov     edi, 84
    mov     esi, 84
    mov     edx, 156
    mov     ecx, 156
    call    patch_rows
    mov     r14d, 80
.try:                                       ; an offer whose route and ambushes lie inside the arena
    call    mobs_clear
    call    events_reset
    SETF    [player + BODY.x], 120.5
    SETF    [player + BODY.z], 120.5
    lea     rdi, [player]
    call    events_spawn_caravan
    test    eax, eax
    jz      .retry
    mov     edi, 1
    call    steps
    movzx   ebx, byte [ev_hud + EVHUD.protect]
    mov     edi, ebx
    call    mob_ptr
    movss   xmm0, [rax + BODY.x]
    movss   [t_u], xmm0
    movss   xmm0, [rax + BODY.z]
    movss   [t_u + 4], xmm0
    cvtsi2ss xmm0, dword [ev_hud + EVHUD.ax]
    addss   xmm0, [k_half]
    movss   [t_u + 8], xmm0
    cvtsi2ss xmm0, dword [ev_hud + EVHUD.az]
    addss   xmm0, [k_half]
    movss   [t_u + 12], xmm0
    movss   xmm0, [t_u + 8]
    subss   xmm0, [t_u]
    movss   xmm1, [t_u + 12]
    subss   xmm1, [t_u + 4]
    movaps  xmm2, xmm0
    mulss   xmm2, xmm2
    movaps  xmm3, xmm1
    mulss   xmm3, xmm3
    addss   xmm2, xmm3
    sqrtss  xmm2, xmm2
    movss   [t_u + 24], xmm2
    divss   xmm0, xmm2
    divss   xmm1, xmm2
    movss   [t_u + 16], xmm0
    movss   [t_u + 20], xmm1
    movss   xmm0, [k_0_75]                  ; the second ambush's cell, 24 ahead, must be inside the arena
    call    route_point
    movss   xmm2, [t_u + 16]
    mulss   xmm2, [k_24]
    addss   xmm0, xmm2
    movss   xmm2, [t_u + 20]
    mulss   xmm2, [k_24]
    addss   xmm1, xmm2
    movss   xmm3, [k_mone]
    xorps   xmm4, xmm4
    mov     eax, __float32__(30.0)
    movd    xmm5, eax
    mov     eax, __float32__(240.0)
    movd    xmm6, eax
    comiss  xmm0, xmm5
    jb      .retry
    comiss  xmm0, xmm6
    ja      .retry
    comiss  xmm1, xmm5
    jb      .retry
    comiss  xmm1, xmm6
    ja      .retry
    jmp     .routed
.retry:
    dec     r14d
    jnz     .try
    jmp     .fail
.routed:
    movss   xmm0, [k_0_4]
    call    ambush_patch
    movss   xmm0, [k_0_75]
    call    ambush_patch
    movzx   r12d, byte [ev_hud + EVHUD.faction]
    mov     edi, r12d
    call    standing
    mov     r13d, eax
    EXPECT_B [ev_hud + EVHUD.state], EVS_OFFERED
    EXPECT_B [ev_hud + EVHUD.kind], EVK_CARAVAN
    EXPECT_B [ev_hud + EVHUD.waves], 2
    mov     edi, ebx
    call    mob_ptr
    EXPECT_B [rax + MOB.role], ROLE_CARAVAN
    mov     cl, [rax + MOB.fflags]
    and     cl, FF_HELP | FF_HALT
    cmp     cl, FF_HELP | FF_HALT
    jne     .fail
    mov     r15d, [rax + MOB.patrol]
    mov     edi, r15d
    mov     esi, ROLE_GUARD
    call    defenders
    cmp     eax, 2
    jne     .fail
    mov     edi, ebx
    call    events_accept
    cmp     eax, 1
    jne     .fail
    SAYS    s_escort
    mov     edi, 601
    call    steps
    EXPECT_B [ev_hud + EVHUD.state], EVS_TRAVEL
    ; a player beside it: it walks
    mov     edi, ebx
    call    mob_ptr
    movss   xmm0, [rax + BODY.x]
    movss   [player + BODY.x], xmm0
    movss   xmm0, [rax + BODY.z]
    movss   [player + BODY.z], xmm0
    mov     edi, 1
    call    steps
    mov     edi, ebx
    call    mob_ptr
    test    byte [rax + MOB.fflags], FF_HALT
    jnz     .fail
    test    byte [ev_hud + EVHUD.flags], EHF_WAIT
    jnz     .fail
    ; no player near: it waits
    movss   xmm0, [player + BODY.x]
    addss   xmm0, [k_40]
    movss   [player + BODY.x], xmm0
    mov     edi, 1
    call    steps
    mov     edi, ebx
    call    mob_ptr
    test    byte [rax + MOB.fflags], FF_HALT
    jz      .fail
    test    byte [ev_hud + EVHUD.flags], EHF_WAIT
    jz      .fail
    ; the first ambush at 35 %
    movss   xmm0, [k_0_4]
    call    route_point
    mov     edi, ebx
    call    mob_ptr
    mov     rdi, rax
    call    party_at
    mov     edi, 1
    call    steps
    EXPECT_B [ev_hud + EVHUD.state], EVS_AMBUSH
    EXPECT_B [ev_hud + EVHUD.wave], 1
    SAYS    s_ambush
    mov     edi, ebx
    call    mob_ptr
    test    byte [rax + MOB.fflags], FF_HALT
    jz      .fail
    mov     edi, 8
    call    steps
    mov     edi, r15d
    call    att_count
    test    eax, eax
    jz      .fail
    mov     edi, r15d
    call    kill_att
    mov     edi, 3
    call    steps
    EXPECT_B [ev_hud + EVHUD.state], EVS_TRAVEL
    ; the second at 70 %
    movss   xmm0, [k_0_75]
    call    route_point
    mov     edi, ebx
    call    mob_ptr
    mov     rdi, rax
    call    party_at
    mov     edi, 1
    call    steps
    EXPECT_B [ev_hud + EVHUD.state], EVS_AMBUSH
    EXPECT_B [ev_hud + EVHUD.wave], 2
    mov     edi, 8
    call    steps
    mov     edi, r15d
    call    att_count
    test    eax, eax
    jz      .fail
    mov     edi, r15d
    call    kill_att
    mov     edi, 3
    call    steps
    EXPECT_B [ev_hud + EVHUD.state], EVS_TRAVEL
    ; arrival
    movss   xmm0, [t_u + 8]
    movss   xmm1, [t_u + 12]
    mov     edi, ebx
    call    mob_ptr
    mov     rdi, rax
    call    party_at
    mov     edi, 1
    call    steps
    EXPECT_B [ev_hud + EVHUD.state], EVS_CLEANUP
    SAYS    s_arrived
    mov     edi, r12d
    call    standing
    lea     ecx, [r13 + 30]
    cmp     eax, ecx
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ecx, eax
    mov     edi, [t_keep + 12]
    mov     r12d, ecx
    call    worldgen_set_seed
    mov     eax, r12d
    END

; ---- test_events_threat_flags ----------------------------------------------------------------------------------------

; A Stonekin camp's leader whose home is its centre + (-5, -6): on a day when hash32(cax, caz, 4000 + 2 day) % 3 == 0 it offers
; the event (FF_HELP, "The Stonekin camp is under threat!", once: the offer is recorded), loses it at standing -1, never has it on
; a day the hash says no, and in Creative only events_force_threat makes it offer
; rbx = the leader, r12d = a threatened day, r13d = a quiet day, r14d = the day under test
test_events_threat_flags:
    BEGIN
    call    world_clear
    call    fixture
    xor     r14d, r14d
    mov     r12d, -1
    mov     r13d, -1
.day:
    mov     edi, 100
    mov     esi, 100
    lea     edx, [r14 * 2 + 4000]
    call    hash32
    xor     edx, edx
    mov     ecx, 3
    div     ecx
    test    edx, edx
    jnz     .quiet
    test    r12d, r12d
    jns     .dnext
    mov     r12d, r14d
    jmp     .dnext
.quiet:
    test    r13d, r13d
    jns     .dnext
    mov     r13d, r14d
.dnext:
    inc     r14d
    cmp     r14d, 40
    jb      .day
    test    r12d, r12d
    js      .fail
    test    r13d, r13d
    js      .fail
    imul    eax, r12d, DAY_LENGTH
    add     eax, NEW_WORLD_TIME
    mov     [game_time], eax
    mov     edi, FAC_STONEKIN
    mov     esi, ROLE_LEADER
    xor     edx, edx
    mov     eax, __float32__(95.5)
    movd    xmm0, eax
    mov     eax, __float32__(11.0)
    movd    xmm1, eax
    mov     eax, __float32__(94.5)
    movd    xmm2, eax
    call    folk_spawn
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, 59
    call    steps
    mov     edi, ebx
    call    mob_ptr
    test    byte [rax + MOB.fflags], FF_HELP
    jnz     .fail                           ; not before the 60th step
    mov     edi, 1
    call    steps
    mov     edi, ebx
    call    mob_ptr
    test    byte [rax + MOB.fflags], FF_HELP
    jz      .fail
    SAY     s_the, 4, s_camp_thr
    ; standing -1: no offer
    mov     edi, FAC_STONEKIN
    mov     esi, -1
    call    set_standing
    mov     edi, 60
    call    steps
    mov     edi, ebx
    call    mob_ptr
    test    byte [rax + MOB.fflags], FF_HELP
    jnz     .fail
    ; standing back: offered again, but announced once
    mov     edi, FAC_STONEKIN
    xor     esi, esi
    call    set_standing
    mov     byte [banner_text], 0
    mov     edi, 60
    call    steps
    mov     edi, ebx
    call    mob_ptr
    test    byte [rax + MOB.fflags], FF_HELP
    jz      .fail
    cmp     byte [banner_text], 0
    jne     .fail
    ; a quiet day
    imul    eax, r13d, DAY_LENGTH
    add     eax, NEW_WORLD_TIME
    mov     [game_time], eax
    mov     edi, 60
    call    steps
    mov     edi, ebx
    call    mob_ptr
    test    byte [rax + MOB.fflags], FF_HELP
    jnz     .fail
    ; Creative on the threatened day: nothing, until it is forced
    imul    eax, r12d, DAY_LENGTH
    add     eax, NEW_WORLD_TIME
    mov     [game_time], eax
    mov     dword [game_mode], MODE_CREATIVE
    mov     edi, 60
    call    steps
    mov     edi, ebx
    call    mob_ptr
    test    byte [rax + MOB.fflags], FF_HELP
    jnz     .fail
    call    events_force_threat
    cmp     eax, 1
    jne     .fail
    mov     edi, ebx
    call    mob_ptr
    test    byte [rax + MOB.fflags], FF_HELP
    jz      .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    END

; ---- test_events_net -------------------------------------------------------------------------------------------------

; cap_find(edi type) -> rax the payload of the first captured record of that type (0 none); cap_count(edi type) -> eax
cap_find:
    xor     ecx, ecx
    lea     r8, [cap]
.l:
    mov     eax, [net_captured]
    cmp     ecx, eax
    jae     .none
    movzx   eax, byte [r8 + rcx + 1]
    movzx   edx, word [r8 + rcx + 2]
    cmp     eax, edi
    je      .found
    lea     ecx, [rcx + rdx + 4]
    jmp     .l
.found:
    lea     rax, [r8 + rcx + 4]
    ret
.none:
    xor     eax, eax
    ret
cap_count:
    xor     eax, eax
    xor     ecx, ecx
    lea     r8, [cap]
.l:
    mov     edx, [net_captured]
    cmp     ecx, edx
    jae     .done
    movzx   edx, byte [r8 + rcx + 1]
    cmp     edx, edi
    jne     .skip
    inc     eax
.skip:
    movzx   edx, word [r8 + rcx + 2]
    lea     ecx, [rcx + rdx + 4]
    jmp     .l
.done:
    ret

; cap_on(): capture into the buffer
cap_on:
    sub     rsp, 8
    lea     rdi, [cap]
    mov     esi, CAP_SIZE
    call    net_capture
    add     rsp, 8
    ret

; hud_is(rdi payload) -> eax 1 when those 20 bytes equal ev_hud
hud_is:
    lea     rsi, [ev_hud]
    mov     ecx, EVHUD_size
.l:
    mov     al, [rdi]
    cmp     al, [rsi]
    jne     .no
    inc     rdi
    inc     rsi
    dec     ecx
    jnz     .l
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; As a host (the capture seam), a step that changes the EVHUD emits exactly one MT_EVENT_STATE of 20 bytes equal to ev_hud, a step
; without a change none; events_state_send(1) sends it to slot 1; a guest's events_net_apply takes 20 bytes into ev_hud, and 19
; change nothing.
test_events_net:
    BEGIN
    call    fixture_big
    mov     al, [net_role]
    mov     [t_keep], al
    mov     al, [net_self]
    mov     [t_keep + 1], al
    mov     al, [net_applying]
    mov     [t_keep + 2], al
    lea     rsi, [net_peers]
    lea     rdi, [t_peers]
    mov     ecx, PEER_size * NET_MAX_PEERS
    rep     movsb
    lea     rdi, [net_peers]
    mov     ecx, PEER_size * NET_MAX_PEERS
    xor     eax, eax
    rep     stosb
    mov     byte [net_self], 0
    mov     byte [net_applying], 0
    lea     rdi, [player]
    call    events_spawn_camp               ; offline: nothing goes out
    cmp     eax, 1
    jne     .fail
    mov     byte [net_role], NET_ROLE_HOST
    call    cap_on
    mov     edi, 1
    call    steps
    mov     edi, MT_EVENT_STATE
    call    cap_count
    cmp     eax, 1
    jne     .fail
    mov     edi, MT_EVENT_STATE
    call    cap_find
    test    rax, rax
    jz      .fail
    cmp     word [rax - 2], EVHUD_size
    jne     .fail
    mov     rdi, rax
    call    hud_is
    test    eax, eax
    jz      .fail
    mov     edi, 3
    call    steps
    mov     edi, MT_EVENT_STATE
    call    cap_count
    cmp     eax, 1
    jne     .fail                           ; no change, nothing sent
    ; the leader accepts: COUNTDOWN is one more
    movzx   edi, byte [ev_hud + EVHUD.protect]
    call    events_accept
    cmp     eax, 1
    jne     .fail
    call    cap_on
    mov     edi, 1
    call    steps
    mov     edi, MT_EVENT_STATE
    call    cap_count
    cmp     eax, 1
    jne     .fail
    mov     edi, MT_EVENT_STATE
    call    cap_find
    test    rax, rax
    jz      .fail
    cmp     byte [rax + EVHUD.state], EVS_COUNTDOWN
    jne     .fail
    ; a peer joins late
    call    cap_on
    mov     edi, 1
    call    events_state_send
    mov     edi, MT_EVENT_STATE
    call    cap_count
    cmp     eax, 1
    jne     .fail
    cmp     byte [cap], 1                   ; to slot 1
    jne     .fail
    mov     edi, MT_EVENT_STATE
    call    cap_find
    mov     rdi, rax
    call    hud_is
    test    eax, eax
    jz      .fail
    ; a guest takes the host's EVHUD
    xor     edi, edi
    xor     esi, esi
    call    net_capture
    mov     byte [net_role], NET_ROLE_GUEST
    lea     rdi, [ev_hud]
    mov     ecx, EVHUD_size
    xor     eax, eax
    rep     stosb
    lea     rdi, [bnr]
    mov     ecx, 24
    mov     al, 0x5A
    rep     stosb
    mov     byte [bnr + EVHUD.state], EVS_WAVE
    mov     byte [bnr + EVHUD.kind], EVK_CAMP
    mov     dword [bnr + EVHUD.ax], 1234
    lea     rdi, [bnr]
    mov     esi, 19
    call    events_net_apply
    cmp     byte [ev_hud + EVHUD.state], 0
    jne     .fail
    lea     rdi, [bnr]
    mov     esi, EVHUD_size
    call    events_net_apply
    lea     rdi, [bnr]
    call    hud_is
    test    eax, eax
    jz      .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     r12d, eax
    xor     edi, edi
    xor     esi, esi
    call    net_capture
    lea     rsi, [t_peers]
    lea     rdi, [net_peers]
    mov     ecx, PEER_size * NET_MAX_PEERS
    rep     movsb
    mov     al, [t_keep]
    mov     [net_role], al
    mov     al, [t_keep + 1]
    mov     [net_self], al
    mov     al, [t_keep + 2]
    mov     [net_applying], al
    mov     eax, r12d
    END
