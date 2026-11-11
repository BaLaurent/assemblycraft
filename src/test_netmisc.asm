; test_netmisc.asm - multiplayer: the shared quest chain and faction standing, the night everybody sleeps through, the
; ghosts (twins) of other peers' projectiles, PvP with fireballs, what the host takes from a guest (the owner of a projectile,
; a hand-in, a flood of sounds). The network side is the capture seam (net_capture): nothing is sent; the tests read back the
; records net_out / net_send_to / net_relay would have sent. Every test restores what it touched.
%include "common.inc"
default rel

global test_net_quest_shared, test_net_sleep_all, test_net_ghost_projectile
global test_net_pvp_spells, test_net_quest_refund, test_net_proj_owner, test_net_relay_limit
global test_net_event_state, test_net_event_accept, test_spell_net

extern net_role, net_self, net_pvp, net_applying, net_peers, net_capture, net_captured, net_pos_out
extern rpg_state, rpg_stats, inv, inv_clear, inv_count, world_header
extern quests_accept, quests_complete, quests_on_kill, quests_progress
extern faction_add, faction_standing
extern nx_on_quest_complete, nx_on_quest_reward, nx_on_quest_sync, nx_on_faction_add, nx_on_standing
extern sleep_step, sleep_active, sleep_timer, sleep_fade, game_time, banner_text, str_eq
extern arrows, arrow_net, arrows_clear, arrows_spawn, arrows_step, nx_on_proj, nx_on_proj_end
extern mobs, mobs_clear, mob_spawn, world_clear, world_set, world_get
extern player, game_mode, surv, survival_reset
extern nx_on_sound, nx_on_fx, nx_on_give, nx_clock_ns, fx_clear, fx_count, dmgnum_clear, nx_on_spell
extern ev_hud, events_reset, events_step, nx_on_event_state, nm_on_interact, net_handlers
extern folk_spawn

%define CAP_SIZE    4096

section .rodata
align 4
k_half:     dd 0.5
k_11:       dd 11.0
k_11_5:     dd 11.5
k_10_5:     dd 10.5
k_16_5:     dd 16.5
k_14:       dd 14.0
k_m30:      dd -30.0
k_m20:      dd -20.0
k_nan:      dd 0x7FC00000
k_9_4:      dd 9.4
k_11_9:     dd 11.9
k_3_5:      dd 3.5
k_12:       dd 12.0
k_4_25:     dd 4.25
s_waiting:  db "Waiting for the others to sleep", 0

section .bss
alignb 8
zombie_ptr:  resq 1
alignb 16
cap:         resb CAP_SIZE              ; the capture buffer
peers_keep:  resb PEER_size * NET_MAX_PEERS
inv_keep:    resb INVENTORY_size
surv_keep:   resb SURVIVAL_size
player_keep: resb BODY_size
rpg_keep:    resb RPGSAVE_size
stand_keep:  resb 24                    ; world_header.standing (16) and .champions (1)
msg:         resb 64                    ; a message under construction
msg2:        resb 8                     ; a message kept from the capture
alignb 4
role_keep:   resb 4                     ; net_role, net_self, net_pvp, net_applying
mode_keep:   resd 1
time_keep:   resd 1
sleep_keep:  resd 4                     ; sleep_active, sleep_timer, sleep_fade, bed_set
xp_want:     resd 1
mob_hp:      resd 1
hp_keep:     resd 1

section .text

; ---- harness ---------------------------------------------------------------------------------------------------------------

; net_begin(): remember the network globals and the peers, start with no peers and nothing captured
net_begin:
    mov     al, [net_role]
    mov     [role_keep], al
    mov     al, [net_self]
    mov     [role_keep + 1], al
    mov     al, [net_pvp]
    mov     [role_keep + 2], al
    mov     al, [net_applying]
    mov     [role_keep + 3], al
    lea     rsi, [net_peers]
    lea     rdi, [peers_keep]
    mov     ecx, PEER_size * NET_MAX_PEERS
    rep     movsb
    lea     rdi, [net_peers]
    mov     ecx, PEER_size * NET_MAX_PEERS
    xor     eax, eax
    rep     stosb
    mov     byte [net_role], NET_ROLE_OFF
    mov     byte [net_self], 0
    mov     byte [net_pvp], 0
    mov     byte [net_applying], 0
    ret

; net_end(): capture off, the network globals and the peers back
net_end:
    sub     rsp, 8
    xor     edi, edi
    xor     esi, esi
    call    net_capture
    add     rsp, 8
    lea     rsi, [peers_keep]
    lea     rdi, [net_peers]
    mov     ecx, PEER_size * NET_MAX_PEERS
    rep     movsb
    mov     al, [role_keep]
    mov     [net_role], al
    mov     al, [role_keep + 1]
    mov     [net_self], al
    mov     al, [role_keep + 2]
    mov     [net_pvp], al
    mov     al, [role_keep + 3]
    mov     [net_applying], al
    ret

; cap_on(): start capturing into the buffer
cap_on:
    sub     rsp, 8
    lea     rdi, [cap]
    mov     esi, CAP_SIZE
    call    net_capture
    mov     dword [net_captured], 0
    add     rsp, 8
    ret

; cap_find(edi type) -> rax the payload of the first captured record of that type (0 none), edx its length.
; Records: slot u8, type u8, len u16, payload[len]
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
    xor     edx, edx
    ret

; cap_count(edi type) -> eax how many records of that type were captured
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

%macro EXPECT_D 2                       ; dword at %1 equals %2
    cmp     dword %1, %2
    jne     .fail
%endmacro
%macro EXPECT_B 2
    cmp     byte %1, %2
    jne     .fail
%endmacro
; RECORD type: rax = the payload of the first captured record of that type, or the test fails
%macro RECORD 1
    mov     edi, %1
    call    cap_find
    test    rax, rax
    jz      .fail
%endmacro
; COUNT type, n: exactly n records of that type were captured
%macro COUNT 2
    mov     edi, %1
    call    cap_count
    cmp     eax, %2
    jne     .fail
%endmacro

; ---- net_quest_shared --------------------------------------------------------------------------------------------------------

; The quest chain and the faction standings are the world's, one for everybody.
; A guest asks instead of doing: accepting sends QUEST_ACCEPT and changes nothing; a kill that counts sends QUEST_BUMP and the
; progress stays where it was (a kill of another mob type sends nothing); handing in takes the items, sends QUEST_COMPLETE, shows
; the quest as handed in (state 2) and pays nothing - the reward comes with QUEST_REWARD. A faction_add sends FACTION_ADD and
; leaves the standing; the host's STANDING is taken over.
; The host, on a guest's QUEST_COMPLETE for the quest on offer (accepted, goal reached): the chain moves on, the guests get
; QUEST_REWARD and QUEST_SYNC and the host is paid, once; the same message again (a stale hand-in), or one for a quest whose goal is not reached,
; pays nothing. FACTION_ADD changes the host's standing and sends STANDING.
; Frame: [rsp] the xp the quest pays with this character's XP bonus, [rsp + 4] the standing before
test_net_quest_shared:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 24
    call    net_begin
    lea     rsi, [rpg_state]
    lea     rdi, [rpg_keep]
    mov     ecx, RPGSAVE_size
    rep     movsb
    lea     rsi, [inv]
    lea     rdi, [inv_keep]
    mov     ecx, INVENTORY_size
    rep     movsb
    lea     rsi, [world_header + WORLDHDR.standing]
    lea     rdi, [stand_keep]
    mov     ecx, 17
    rep     movsb
    call    inv_clear
    mov     byte [rpg_state + RPGSAVE.level], 10     ; a bar of 220: 40 XP does not level up
    mov     dword [rpg_state + RPGSAVE.xp], 0
    mov     eax, [rpg_stats + STAT_XP_BONUS * 4]     ; what quest 0 pays: 40 + the XP bonus
    add     eax, 100
    jns     .scale
    xor     eax, eax
.scale:
    imul    eax, eax, 40
    xor     edx, edx
    mov     ecx, 100
    div     ecx
    mov     [rsp], eax
    mov     byte [net_pvp], 0
    mov     word [world_header + WORLDHDR.standing + FAC_BANDITS * 2], 0 ; (restored at the end)

    ; ---- a guest: accept, count, hand in ----------------------------------------------------------------------------------
    mov     byte [net_role], NET_ROLE_GUEST
    mov     byte [net_self], 1
    call    cap_on
    mov     byte [rpg_state + RPGSAVE.quest], 0       ; "Zombie Trouble": slay 6 zombies
    mov     byte [rpg_state + RPGSAVE.quest_state], 0
    mov     word [rpg_state + RPGSAVE.quest_progress], 0
    call    quests_accept
    cmp     eax, 1
    jne     .fail
    EXPECT_B [rpg_state + RPGSAVE.quest_state], 0    ; nothing changed here: the host decides
    RECORD  MT_QUEST_ACCEPT
    EXPECT_B [rax], 0
    mov     byte [rpg_state + RPGSAVE.quest_state], 1 ; (the host's QUEST_SYNC would say so)
    mov     word [rpg_state + RPGSAVE.quest_progress], 2
    mov     edi, MOB_ZOMBIE
    xor     esi, esi
    call    quests_on_kill
    RECORD  MT_QUEST_BUMP
    EXPECT_B [rax], Q_KILL
    cmp     word [rpg_state + RPGSAVE.quest_progress], 2 ; unchanged: counting is the host's
    jne     .fail
    mov     edi, MOB_PIG
    xor     esi, esi
    call    quests_on_kill
    COUNT   MT_QUEST_BUMP, 1                          ; a pig does not count: nothing sent
    mov     word [rpg_state + RPGSAVE.quest_progress], 6
    call    quests_complete
    cmp     eax, 1
    jne     .fail
    RECORD  MT_QUEST_COMPLETE
    EXPECT_B [rax], 0
    EXPECT_B [rpg_state + RPGSAVE.quest], 0           ; the chain did not move here
    EXPECT_B [rpg_state + RPGSAVE.quest_state], 2     ; handed in, waiting for the host
    EXPECT_D [rpg_state + RPGSAVE.xp], 0              ; and nothing was paid yet
    call    quests_complete
    test    eax, eax
    jnz     .fail                                     ; no second hand-in while the host has not answered
    COUNT   MT_QUEST_COMPLETE, 1
    ; the host's answers
    mov     byte [msg], 0
    lea     rdx, [msg]
    mov     edi, 0
    mov     esi, MT_QUEST_REWARD
    mov     ecx, 1
    call    nx_on_quest_reward
    mov     eax, [rsp]
    cmp     [rpg_state + RPGSAVE.xp], eax
    jne     .fail
    mov     byte [msg], 1                             ; QUEST_SYNC: quest 1, not accepted, progress 0
    mov     byte [msg + 1], 0
    mov     word [msg + 2], 0
    lea     rdx, [msg]
    xor     edi, edi
    mov     esi, MT_QUEST_SYNC
    mov     ecx, 4
    call    nx_on_quest_sync
    EXPECT_B [rpg_state + RPGSAVE.quest], 1
    EXPECT_B [rpg_state + RPGSAVE.quest_state], 0
    mov     byte [msg], 9                             ; a quest beyond the chain is not taken over
    lea     rdx, [msg]
    xor     edi, edi
    mov     esi, MT_QUEST_SYNC
    mov     ecx, 4
    call    nx_on_quest_sync
    EXPECT_B [rpg_state + RPGSAVE.quest], 1
    ; standing: asked, not applied
    mov     edi, FAC_BANDITS
    call    faction_standing
    mov     [rsp + 4], eax
    mov     edi, FAC_BANDITS
    mov     esi, 30
    call    faction_add
    mov     edi, FAC_BANDITS
    call    faction_standing
    cmp     eax, [rsp + 4]
    jne     .fail
    RECORD  MT_FACTION_ADD
    EXPECT_B [rax], FAC_BANDITS
    cmp     word [rax + 2], 30
    jne     .fail

    ; ---- the host: a guest hands in ----------------------------------------------------------------------------------------
    mov     byte [net_role], NET_ROLE_HOST
    mov     byte [net_self], 0
    lea     rdi, [net_peers + PEER_size]
    mov     dword [rdi + PEER.state], PEER_READY
    call    cap_on
    mov     byte [rpg_state + RPGSAVE.quest], 0
    mov     byte [rpg_state + RPGSAVE.quest_state], 1
    mov     word [rpg_state + RPGSAVE.quest_progress], 6
    mov     dword [rpg_state + RPGSAVE.xp], 0
    mov     byte [msg], 0
    lea     rdx, [msg]
    mov     edi, 1
    mov     esi, MT_QUEST_COMPLETE
    mov     ecx, 1
    call    nx_on_quest_complete
    EXPECT_B [rpg_state + RPGSAVE.quest], 1           ; the chain moved on by one
    EXPECT_B [rpg_state + RPGSAVE.quest_state], 0
    cmp     word [rpg_state + RPGSAVE.quest_progress], 0
    jne     .fail
    mov     eax, [rsp]
    cmp     [rpg_state + RPGSAVE.xp], eax             ; the host was paid, exactly once
    jne     .fail
    RECORD  MT_QUEST_REWARD
    EXPECT_B [rax], 0
    RECORD  MT_QUEST_SYNC
    EXPECT_B [rax], 1
    EXPECT_B [rax + 1], 0
    ; the same message again is stale: the quest on offer is another one now
    mov     byte [rpg_state + RPGSAVE.quest_state], 1
    mov     word [rpg_state + RPGSAVE.quest_progress], 9
    lea     rdx, [msg]
    mov     edi, 1
    mov     esi, MT_QUEST_COMPLETE
    mov     ecx, 1
    call    nx_on_quest_complete
    mov     eax, [rsp]
    cmp     [rpg_state + RPGSAVE.xp], eax
    jne     .fail                                     ; no second payment
    EXPECT_B [rpg_state + RPGSAVE.quest], 1
    COUNT   MT_QUEST_REWARD, 1
    ; a quest whose goal is not reached is not done: "Rattling Bones", 3 of 5 skeletons
    mov     byte [rpg_state + RPGSAVE.quest], 2
    mov     byte [rpg_state + RPGSAVE.quest_state], 1
    mov     word [rpg_state + RPGSAVE.quest_progress], 3
    mov     byte [msg], 2
    lea     rdx, [msg]
    mov     edi, 1
    mov     esi, MT_QUEST_COMPLETE
    mov     ecx, 1
    call    nx_on_quest_complete
    EXPECT_B [rpg_state + RPGSAVE.quest], 2
    COUNT   MT_QUEST_REWARD, 1
    ; standing: the host applies a guest's FACTION_ADD and tells everybody
    mov     edi, FAC_BANDITS
    call    faction_standing
    mov     [rsp + 4], eax
    mov     byte [msg], FAC_BANDITS
    mov     byte [msg + 1], 0
    mov     word [msg + 2], 30
    lea     rdx, [msg]
    mov     edi, 1
    mov     esi, MT_FACTION_ADD
    mov     ecx, 4
    call    nx_on_faction_add
    mov     edi, FAC_BANDITS
    call    faction_standing
    sub     eax, [rsp + 4]
    cmp     eax, 30
    jne     .fail
    RECORD  MT_STANDING
    movsx   ebx, word [rax + FAC_BANDITS * 2]         ; the standing the guests are told
    mov     edi, FAC_BANDITS
    call    faction_standing
    cmp     eax, ebx
    jne     .fail
    ; a guest takes STANDING over
    mov     byte [net_role], NET_ROLE_GUEST
    mov     byte [net_self], 1
    lea     rdi, [msg]
    mov     ecx, 64
    xor     eax, eax
    rep     stosb
    mov     word [msg + FAC_BANDITS * 2], -77
    mov     byte [msg + 16], 0x04
    lea     rdx, [msg]
    xor     edi, edi
    mov     esi, MT_STANDING
    mov     ecx, 18
    call    nx_on_standing
    mov     edi, FAC_BANDITS
    call    faction_standing
    cmp     eax, -77
    jne     .fail
    EXPECT_B [world_header + WORLDHDR.champions], 0x04
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    lea     rsi, [rpg_keep]
    lea     rdi, [rpg_state]
    mov     ecx, RPGSAVE_size
    rep     movsb
    lea     rsi, [inv_keep]
    lea     rdi, [inv]
    mov     ecx, INVENTORY_size
    rep     movsb
    lea     rsi, [stand_keep]
    lea     rdi, [world_header + WORLDHDR.standing]
    mov     ecx, 17
    rep     movsb
    call    net_end
    mov     eax, ebx
    add     rsp, 24
    pop     rbx
    pop     rbp
    ret

; ---- net_sleep_all -----------------------------------------------------------------------------------------------------------

; Night passes only when everybody sleeps. A host lying at step 120 with another player in the world who is not asleep (no
; PS_ASLEEP in his PSTATE) keeps lying: the time stays, the timer holds at 120 and the banner says so; when that player's
; PSTATE says PS_ASLEEP, the next step is the morning (54000 -> 72000). If it is day already the host just gets up and the
; time stays. A guest only waits at 120 and gets up when the host's time says morning. Without a network the night passes at
; step 120 as ever, and a host alone in the world does the same.
test_net_sleep_all:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    net_begin
    mov     eax, [game_time]
    mov     [time_keep], eax
    mov     eax, [sleep_active]
    mov     [sleep_keep], eax
    mov     eax, [sleep_timer]
    mov     [sleep_keep + 4], eax
    mov     eax, [sleep_fade]
    mov     [sleep_keep + 8], eax
    mov     eax, [world_header + WORLDHDR.bed_set]
    mov     [sleep_keep + 12], eax
    mov     dword [world_header + WORLDHDR.bed_set], 0 ; no bed: waking leaves him where he lay
    ; ---- a host with another player who is awake ---------------------------------------------------------------------------
    mov     byte [net_role], NET_ROLE_HOST
    mov     byte [net_self], 0
    lea     rbx, [net_peers + PEER_size]
    mov     dword [rbx + PEER.state], PEER_READY
    mov     word [rbx + PEER.ps + PSTATE.flags], PS_GROUND
    mov     dword [game_time], 54000
    mov     dword [sleep_active], 1
    mov     dword [sleep_timer], SLEEP_STEPS - 1
    call    sleep_step                                ; arrives at step 120: the banner says why he lies on
    lea     rdi, [banner_text]
    lea     rsi, [s_waiting]
    call    str_eq
    test    eax, eax
    jz      .fail
    mov     byte [banner_text], 0                     ; and says it once
    mov     r12d, 9
.wait:
    call    sleep_step
    dec     r12d
    jnz     .wait
    EXPECT_D [game_time], 54000                      ; the night stays
    EXPECT_D [sleep_active], 1
    EXPECT_D [sleep_timer], SLEEP_STEPS
    EXPECT_B [banner_text], 0
    ; ---- he falls asleep too: the next step is the morning --------------------------------------------------------------------
    mov     word [rbx + PEER.ps + PSTATE.flags], PS_GROUND | PS_SLEEP | PS_ASLEEP
    call    sleep_step
    EXPECT_D [game_time], 72000
    EXPECT_D [sleep_active], 0
    EXPECT_D [sleep_timer], 0
    ; ---- everybody asleep but it is day already: up, the time stays ---------------------------------------------------------------
    mov     dword [game_time], 90000
    mov     dword [sleep_active], 1
    mov     dword [sleep_timer], SLEEP_STEPS - 1
    call    sleep_step
    EXPECT_D [game_time], 90000
    EXPECT_D [sleep_active], 0
    ; ---- a guest: waits at 120, gets up when the host's time says morning --------------------------------------------------------
    mov     byte [net_role], NET_ROLE_GUEST
    mov     byte [net_self], 1
    mov     dword [game_time], 54000
    mov     dword [sleep_active], 1
    mov     dword [sleep_timer], SLEEP_STEPS - 1
    mov     r12d, 10
.guest:
    call    sleep_step
    dec     r12d
    jnz     .guest
    EXPECT_D [game_time], 54000
    EXPECT_D [sleep_active], 1
    EXPECT_D [sleep_timer], SLEEP_STEPS
    mov     dword [game_time], 90000                 ; the host's time arrived
    call    sleep_step
    EXPECT_D [game_time], 90000
    EXPECT_D [sleep_active], 0
    ; ---- no network: step 120 is the morning --------------------------------------------------------------------------------------
    mov     byte [net_role], NET_ROLE_OFF
    mov     dword [game_time], 54000
    mov     dword [sleep_active], 1
    mov     dword [sleep_timer], SLEEP_STEPS - 1
    call    sleep_step
    EXPECT_D [game_time], 72000
    EXPECT_D [sleep_active], 0
    ; ---- a host alone: the same ---------------------------------------------------------------------------------------------------
    mov     byte [net_role], NET_ROLE_HOST
    mov     dword [rbx + PEER.state], PEER_FREE
    mov     dword [game_time], 54000
    mov     dword [sleep_active], 1
    mov     dword [sleep_timer], SLEEP_STEPS - 1
    call    sleep_step
    EXPECT_D [game_time], 72000
    EXPECT_D [sleep_active], 0
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     r12d, eax
    mov     eax, [time_keep]
    mov     [game_time], eax
    mov     eax, [sleep_keep]
    mov     [sleep_active], eax
    mov     eax, [sleep_keep + 4]
    mov     [sleep_timer], eax
    mov     eax, [sleep_keep + 8]
    mov     [sleep_fade], eax
    mov     eax, [sleep_keep + 12]
    mov     [world_header + WORLDHDR.bed_set], eax
    call    net_end
    mov     eax, r12d
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- net_ghost_projectile ------------------------------------------------------------------------------------------------------

; fixture(): the world the arrows fly in: no mobs, arrows or inventory, Survival, a fresh character state, a stone floor at
; y = 10 for x, z in 0..31
fixture:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    mobs_clear
    call    arrows_clear
    call    inv_clear
    mov     dword [game_mode], MODE_SURVIVAL
    call    survival_reset
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
    pop     r12
    pop     rbx
    pop     rbp
    ret

; proj_msg(edi owner peer, esi owner slot, edx kind, xmm0 x, xmm1 y, xmm2 z, xmm3 vx, xmm4 vy, xmm5 vz): msg = a PROJ message
; (flags AF_ATTACK) with the position as the absolute NPOS the wire carries
proj_msg:
    push    rbx
    sub     rsp, 32
    mov     [msg], dil
    mov     [msg + 1], sil
    mov     [msg + 2], dl
    mov     byte [msg + 3], 0
    mov     dword [msg + 4], AF_ATTACK
    movss   [rsp], xmm3
    movss   [rsp + 4], xmm4
    movss   [rsp + 8], xmm5
    lea     rdi, [msg + 8]
    call    net_pos_out
    mov     eax, [rsp]
    mov     [msg + 24], eax
    mov     eax, [rsp + 4]
    mov     [msg + 28], eax
    mov     eax, [rsp + 8]
    mov     [msg + 32], eax
    add     rsp, 32
    pop     rbx
    ret

; live_count() -> eax how many projectiles are alive
live_count:
    xor     eax, eax
    lea     rcx, [arrows]
    mov     edx, MAX_ARROWS
.l:
    cmp     dword [rcx + ARROWENT.live], 0
    je      .n
    inc     eax
.n:
    add     rcx, ARROWENT_size
    dec     edx
    jnz     .l
    ret

; run(edi n): n arrows_step calls
run:
    push    rbx
    mov     ebx, edi
.l:
    call    arrows_step
    dec     ebx
    jnz     .l
    pop     rbx
    ret

; A projectile that was made here goes to the others as a PROJ with its owner, slot, kind and flags, and carries the tag that
; pairs it with its twin (arrow_net = (owner peer + 1) << 8 | slot); a monster's arrow on a guest is not sent; when it ends,
; PROJ_END follows and the tag is cleared. A PROJ from another peer makes a ghost (AF_GHOST) with the sender's tag: it flies
; through a zombie without a scratch, sticks in the floor, is not picked up by the player standing there, and PROJ_END removes
; it; the same PROJ twice leaves one ghost; a velocity that is not a number is dropped; a ghost rocket flying into the floor
; carves nothing.
test_net_ghost_projectile:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    net_begin
    mov     eax, [game_mode]
    mov     [mode_keep], eax
    lea     rsi, [surv]
    lea     rdi, [surv_keep]
    mov     ecx, SURVIVAL_size
    rep     movsb
    lea     rsi, [player]
    lea     rdi, [player_keep]
    mov     ecx, BODY_size
    rep     movsb
    lea     rsi, [inv]
    lea     rdi, [inv_keep]
    mov     ecx, INVENTORY_size
    rep     movsb
    call    fixture
    mov     dword [player + BODY.x], __float32__(3.5) ; away from every arrow
    mov     dword [player + BODY.y], __float32__(11.0)
    mov     dword [player + BODY.z], __float32__(3.5)

    ; ---- made here, on a guest ---------------------------------------------------------------------------------------------
    mov     byte [net_role], NET_ROLE_GUEST
    mov     byte [net_self], 1
    call    cap_on
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11_5]
    movss   xmm2, [k_16_5]
    xorps   xmm3, xmm3
    xorps   xmm4, xmm4
    movss   xmm5, [k_m30]
    xor     edi, edi                                  ; the player's
    mov     esi, 5
    mov     edx, 1
    mov     ecx, PROJ_ARROW
    mov     r8d, AF_ATTACK
    call    arrows_spawn
    test    eax, eax
    jnz     .fail                                     ; the first slot
    RECORD  MT_PROJ
    cmp     edx, 36
    jne     .fail
    EXPECT_B [rax], 1                                 ; fired by peer 1 (this one)
    EXPECT_B [rax + 1], 0                             ; from slot 0
    EXPECT_B [rax + 2], PROJ_ARROW
    EXPECT_D [rax + 4], AF_ATTACK
    EXPECT_D [rax + 32], __float32__(-30.0)           ; vz
    EXPECT_D [arrow_net], (1 + 1) << 8
    movss   xmm0, [k_16_5]                            ; a monster's arrow is not sent
    movss   xmm1, [k_14]
    movss   xmm2, [k_16_5]
    xorps   xmm3, xmm3
    xorps   xmm4, xmm4
    movss   xmm5, [k_m30]
    mov     edi, OWNER_MONSTER
    mov     esi, 5
    xor     edx, edx
    mov     ecx, PROJ_ARROW
    xor     r8d, r8d
    call    arrows_spawn
    cmp     eax, 1
    jne     .fail
    COUNT   MT_PROJ, 1
    EXPECT_D [arrow_net + 4], 0
    mov     dword [arrows + ARROWENT.live], 0         ; the real one ends
    call    arrows_step
    RECORD  MT_PROJ_END
    cmp     edx, 2
    jne     .fail
    EXPECT_B [rax], 1
    EXPECT_B [rax + 1], 0
    EXPECT_D [arrow_net], 0
    call    arrows_clear

    ; ---- the twin of another peer's, on the host --------------------------------------------------------------------------------
    mov     byte [net_role], NET_ROLE_HOST
    mov     byte [net_self], 0
    lea     rbx, [net_peers + 2 * PEER_size]          ; guest 2, in range: the host passes the projectile on to him
    mov     dword [rbx + PEER.state], PEER_READY
    mov     dword [rbx + PEER.body + BODY.x], __float32__(16.5)
    mov     dword [rbx + PEER.body + BODY.y], __float32__(11.0)
    mov     dword [rbx + PEER.body + BODY.z], __float32__(16.5)
    call    cap_on
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_10_5]
    call    mob_spawn
    test    eax, eax
    js      .fail
    imul    r12d, eax, MOB_size
    lea     rax, [mobs]
    add     r12, rax                                  ; the zombie
    mov     eax, [r12 + MOB.health]
    mov     [mob_hp], eax
    mov     eax, [surv + SURVIVAL.health]
    mov     [hp_keep], eax
    movss   xmm0, [k_16_5]                            ; the player stands where the arrow will land
    movss   [player + BODY.x], xmm0
    movss   xmm0, [k_11]
    movss   [player + BODY.y], xmm0
    movss   xmm0, [k_10_5]
    movss   [player + BODY.z], xmm0
    mov     edi, 1
    mov     esi, 7
    mov     edx, PROJ_ARROW
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11_5]
    movss   xmm2, [k_16_5]
    xorps   xmm3, xmm3
    xorps   xmm4, xmm4
    movss   xmm5, [k_m30]
    call    proj_msg
    lea     rdx, [msg]
    mov     edi, 1
    mov     esi, MT_PROJ
    mov     ecx, 36
    call    nx_on_proj
    test    dword [arrows + ARROWENT.flags], AF_GHOST
    jz      .fail
    EXPECT_D [arrows + ARROWENT.live], 1
    EXPECT_D [arrow_net], (1 + 1) << 8 | 7            ; the sender's tag
    RECORD  MT_PROJ                                   ; passed on to the other guest
    mov     edi, 30
    call    run
    mov     eax, [r12 + MOB.health]
    cmp     eax, [mob_hp]
    jne     .fail                                     ; flew through the zombie
    mov     eax, [surv + SURVIVAL.health]
    cmp     eax, [hp_keep]
    jne     .fail                                     ; nor did it hurt the player standing where it landed
    cmp     dword [r12 + MOB.hurt], 0
    jg      .fail
    EXPECT_D [arrows + ARROWENT.live], 1              ; stuck in the floor
    cmp     dword [arrows + ARROWENT.stuck], 0
    je      .fail
    mov     edi, ARROW
    call    inv_count
    test    eax, eax
    jnz     .fail                                     ; and nobody picked it up
    mov     byte [msg], 1                             ; PROJ_END {peer 1, slot 7}
    mov     byte [msg + 1], 7
    lea     rdx, [msg]
    mov     edi, 1
    mov     esi, MT_PROJ_END
    mov     ecx, 2
    call    nx_on_proj_end
    EXPECT_D [arrows + ARROWENT.live], 0
    EXPECT_D [arrow_net], 0
    RECORD  MT_PROJ_END                               ; passed on too
    ; the same PROJ twice: one ghost (an end that got lost leaves the older one behind otherwise)
    mov     edi, 1
    mov     esi, 7
    mov     edx, PROJ_ARROW
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_14]
    movss   xmm2, [k_16_5]
    xorps   xmm3, xmm3
    xorps   xmm4, xmm4
    movss   xmm5, [k_m30]
    call    proj_msg
    lea     rdx, [msg]
    mov     edi, 1
    mov     esi, MT_PROJ
    mov     ecx, 36
    call    nx_on_proj
    lea     rdx, [msg]
    mov     edi, 1
    mov     esi, MT_PROJ
    mov     ecx, 36
    call    nx_on_proj
    call    live_count
    cmp     eax, 1
    jne     .fail
    ; a velocity that is not a number: dropped (from another slot, so that it could not just replace the ghost above)
    mov     eax, [k_nan]
    mov     [msg + 24], eax
    mov     byte [msg + 1], 9
    lea     rdx, [msg]
    mov     edi, 1
    mov     esi, MT_PROJ
    mov     ecx, 36
    call    nx_on_proj
    call    live_count
    cmp     eax, 1
    jne     .fail
    call    arrows_clear
    ; a ghost rocket into the floor: it ends there without a crater
    mov     edi, 1
    mov     esi, 8
    mov     edx, PROJ_ROCKET
    movss   xmm0, [k_10_5]
    movss   xmm1, [k_14]
    movss   xmm2, [k_10_5]
    xorps   xmm3, xmm3
    movss   xmm4, [k_m20]
    xorps   xmm5, xmm5
    call    proj_msg
    lea     rdx, [msg]
    mov     edi, 1
    mov     esi, MT_PROJ
    mov     ecx, 36
    call    nx_on_proj
    EXPECT_D [arrows + ARROWENT.live], 1
    mov     edi, 30
    call    run
    EXPECT_D [arrows + ARROWENT.live], 0
    mov     edi, 10
    mov     esi, 10
    mov     edx, 10
    call    world_get
    cmp     eax, STONE
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     r12d, eax
    call    arrows_clear
    call    mobs_clear
    call    world_clear
    mov     eax, [mode_keep]
    mov     [game_mode], eax
    lea     rsi, [surv_keep]
    lea     rdi, [surv]
    mov     ecx, SURVIVAL_size
    rep     movsb
    lea     rsi, [player_keep]
    lea     rdi, [player]
    mov     ecx, BODY_size
    rep     movsb
    lea     rsi, [inv_keep]
    lea     rdi, [inv]
    mov     ecx, INVENTORY_size
    rep     movsb
    call    net_end
    mov     eax, r12d
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- net_pvp_spells ------------------------------------------------------------------------------------------------------------

; cap_slot(edi type) -> eax the slot byte of the first captured record of that type (-1: there is none)
cap_slot:
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
    movzx   eax, byte [r8 + rcx]
    ret
.none:
    mov     eax, -1
    ret

; shot(edi kind, esi flags) -> eax how many PVP_HIT records one projectile of the host player (damage 8) captured (99: no zombie).
; It flies along -z from (16.5, 11.9, 16.5) through the peer standing at z 10.5 and on to a zombie at z 9.4, 40 steps;
; [zombie_ptr] is the zombie and [mob_hp] its health before.
shot:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     r12d, edi
    mov     r13d, esi
    call    arrows_clear
    call    mobs_clear
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_9_4]
    call    mob_spawn
    test    eax, eax
    js      .bad
    imul    ebx, eax, MOB_size
    lea     rax, [mobs]
    add     rbx, rax
    mov     [zombie_ptr], rbx
    mov     eax, [rbx + MOB.health]
    mov     [mob_hp], eax
    call    cap_on
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11_9]
    movss   xmm2, [k_16_5]
    xorps   xmm3, xmm3
    xorps   xmm4, xmm4
    movss   xmm5, [k_m30]
    xor     edi, edi                                  ; the player's
    mov     esi, 8
    xor     edx, edx
    mov     ecx, r12d
    mov     r8d, r13d
    call    arrows_spawn
    mov     ebx, 40
.run:
    call    arrows_step
    dec     ebx
    jnz     .run
    mov     edi, MT_PVP_HIT
    call    cap_count
    jmp     .ret
.bad:
    mov     eax, 99
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; PvP: a bow arrow that meets another player (guest 1, standing in its way) sends a PVP_HIT without a status. A fireball and an
; explosive arrow do the same, burning him (STS_BURN, victim 1, attacker this player, an amount), and still burst: the zombie
; behind him takes the blast. With PvP off none of them hits anybody.
test_net_pvp_spells:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    net_begin
    mov     eax, [game_mode]
    mov     [mode_keep], eax
    lea     rsi, [surv]
    lea     rdi, [surv_keep]
    mov     ecx, SURVIVAL_size
    rep     movsb
    lea     rsi, [player]
    lea     rdi, [player_keep]
    mov     ecx, BODY_size
    rep     movsb
    call    fixture
    mov     dword [player + BODY.x], __float32__(3.5) ; the host player stands away from everything
    mov     dword [player + BODY.y], __float32__(11.0)
    mov     dword [player + BODY.z], __float32__(3.5)
    mov     byte [net_role], NET_ROLE_HOST
    mov     byte [net_self], 0
    mov     byte [net_pvp], 1
    lea     rbx, [net_peers + PEER_size]              ; guest 1 stands in the shots' way
    mov     dword [rbx + PEER.state], PEER_READY
    mov     word [rbx + PEER.ps + PSTATE.flags], 0
    mov     word [rbx + PEER.ps + PSTATE.max_health], 20
    mov     dword [rbx + PEER.body + BODY.x], __float32__(16.5)
    mov     dword [rbx + PEER.body + BODY.y], __float32__(11.0)
    mov     dword [rbx + PEER.body + BODY.z], __float32__(10.5)
    mov     edi, PROJ_ARROW                           ; a bow arrow
    mov     esi, AF_ATTACK
    call    shot
    cmp     eax, 1
    jne     .fail
    RECORD  MT_PVP_HIT
    EXPECT_B [rax], 1
    EXPECT_B [rax + 2], 255                           ; no status
    mov     edi, PROJ_FIREBALL                        ; a fireball
    mov     esi, AF_ATTACK
    call    shot
    cmp     eax, 1
    jne     .fail
    RECORD  MT_PVP_HIT
    EXPECT_B [rax], 1                                 ; the victim: guest 1
    EXPECT_B [rax + 1], 0                             ; the attacker: this player
    EXPECT_B [rax + 2], STS_BURN
    cmp     dword [rax + 4], 1
    jl      .fail                                     ; an amount
    mov     rax, [zombie_ptr]
    mov     eax, [rax + MOB.health]
    cmp     eax, [mob_hp]
    jge     .fail                                     ; the burst still went off
    mov     edi, PROJ_ARROW                           ; an explosive arrow
    mov     esi, AF_ATTACK | AF_EXPLOSIVE
    call    shot
    cmp     eax, 1
    jne     .fail
    RECORD  MT_PVP_HIT
    EXPECT_B [rax], 1
    EXPECT_B [rax + 2], STS_BURN
    mov     rax, [zombie_ptr]
    mov     eax, [rax + MOB.health]
    cmp     eax, [mob_hp]
    jge     .fail
    mov     byte [net_pvp], 0                         ; PvP off: nobody is hit
    mov     edi, PROJ_FIREBALL
    mov     esi, AF_ATTACK
    call    shot
    test    eax, eax
    jnz     .fail
    mov     edi, PROJ_ARROW
    mov     esi, AF_ATTACK | AF_EXPLOSIVE
    call    shot
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     r12d, eax
    call    dmgnum_clear
    call    arrows_clear
    call    mobs_clear
    call    world_clear
    mov     eax, [mode_keep]
    mov     [game_mode], eax
    lea     rsi, [surv_keep]
    lea     rdi, [surv]
    mov     ecx, SURVIVAL_size
    rep     movsb
    lea     rsi, [player_keep]
    lea     rdi, [player]
    mov     ecx, BODY_size
    rep     movsb
    call    net_end
    mov     eax, r12d
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- net_quest_refund ----------------------------------------------------------------------------------------------------------

; A hand-in the host refuses gives the guest back what he took for it. Two guests hand in "Iron for the Smithy" (quest 1: 8 iron
; ingots) at once: the first is done (the chain moves on, QUEST_REWARD, nothing given back), the second is stale: no second
; reward, a GIVE of 8 iron ingots to guest 2 (not to guest 1) and the position (QUEST_SYNC). The same when the quest was not
; accepted (guest 3). A stale hand-in of a quest that takes no items ("Zombie Trouble") or of a number beyond the chain gives
; nothing back. The guest that gets the GIVE has its 8 iron ingots again.
test_net_quest_refund:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    net_begin
    lea     rsi, [rpg_state]
    lea     rdi, [rpg_keep]
    mov     ecx, RPGSAVE_size
    rep     movsb
    lea     rsi, [inv]
    lea     rdi, [inv_keep]
    mov     ecx, INVENTORY_size
    rep     movsb
    call    inv_clear
    mov     byte [rpg_state + RPGSAVE.level], 10      ; a bar of 220: the reward does not level up
    mov     dword [rpg_state + RPGSAVE.xp], 0
    mov     byte [net_role], NET_ROLE_HOST
    mov     byte [net_self], 0
    call    cap_on
    mov     byte [rpg_state + RPGSAVE.quest], 1
    mov     byte [rpg_state + RPGSAVE.quest_state], 1
    mov     word [rpg_state + RPGSAVE.quest_progress], 0
    mov     byte [msg], 1
    lea     rdx, [msg]                                ; guest 1 is first
    mov     edi, 1
    mov     esi, MT_QUEST_COMPLETE
    mov     ecx, 1
    call    nx_on_quest_complete
    EXPECT_B [rpg_state + RPGSAVE.quest], 2
    COUNT   MT_QUEST_REWARD, 1
    COUNT   MT_GIVE, 0
    lea     rdx, [msg]                                ; guest 2 is late
    mov     edi, 2
    mov     esi, MT_QUEST_COMPLETE
    mov     ecx, 1
    call    nx_on_quest_complete
    EXPECT_B [rpg_state + RPGSAVE.quest], 2
    COUNT   MT_QUEST_REWARD, 1                        ; no second reward
    RECORD  MT_GIVE
    cmp     edx, 4
    jne     .fail
    EXPECT_B [rax], IRON_INGOT
    EXPECT_B [rax + 1], 8
    cmp     word [rax + 2], 0
    jne     .fail
    mov     ecx, [rax]
    mov     [msg2], ecx                               ; (kept for the guest below)
    mov     edi, MT_GIVE
    call    cap_slot
    cmp     eax, 2
    jne     .fail                                     ; to guest 2
    RECORD  MT_QUEST_SYNC
    call    cap_on                                    ; not accepted (guest 3)
    mov     byte [rpg_state + RPGSAVE.quest], 1
    mov     byte [rpg_state + RPGSAVE.quest_state], 0
    lea     rdx, [msg]
    mov     edi, 3
    mov     esi, MT_QUEST_COMPLETE
    mov     ecx, 1
    call    nx_on_quest_complete
    RECORD  MT_GIVE
    EXPECT_B [rax], IRON_INGOT
    mov     edi, MT_GIVE
    call    cap_slot
    cmp     eax, 3
    jne     .fail
    call    cap_on                                    ; a quest that takes no items
    mov     byte [rpg_state + RPGSAVE.quest], 2
    mov     byte [rpg_state + RPGSAVE.quest_state], 1
    mov     byte [msg], 0                             ; "Zombie Trouble"
    lea     rdx, [msg]
    mov     edi, 1
    mov     esi, MT_QUEST_COMPLETE
    mov     ecx, 1
    call    nx_on_quest_complete
    COUNT   MT_GIVE, 0
    COUNT   MT_QUEST_SYNC, 1
    mov     byte [msg], 9                             ; a quest beyond the chain
    lea     rdx, [msg]
    mov     edi, 1
    mov     esi, MT_QUEST_COMPLETE
    mov     ecx, 1
    call    nx_on_quest_complete
    COUNT   MT_GIVE, 0
    mov     byte [net_role], NET_ROLE_GUEST           ; the guest takes it back
    mov     byte [net_self], 2
    call    inv_clear
    lea     rdx, [msg2]
    xor     edi, edi
    mov     esi, MT_GIVE
    mov     ecx, 4
    call    nx_on_give
    mov     edi, IRON_INGOT
    call    inv_count
    cmp     eax, 8
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    lea     rsi, [rpg_keep]
    lea     rdi, [rpg_state]
    mov     ecx, RPGSAVE_size
    rep     movsb
    lea     rsi, [inv_keep]
    lea     rdi, [inv]
    mov     ecx, INVENTORY_size
    rep     movsb
    call    net_end
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- net_proj_owner ------------------------------------------------------------------------------------------------------------

; PROJ_FROM owner peer, owner slot, sender slot: a PROJ for an arrow with that owner reaches this game from that connection
%macro PROJ_FROM 3
    mov     edi, %1
    mov     esi, %2
    mov     edx, PROJ_ARROW
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11_5]
    movss   xmm2, [k_16_5]
    xorps   xmm3, xmm3
    xorps   xmm4, xmm4
    movss   xmm5, [k_m30]
    call    proj_msg
    lea     rdx, [msg]
    mov     edi, %3
    mov     esi, MT_PROJ
    mov     ecx, 36
    call    nx_on_proj
%endmacro
; END_FROM owner peer, owner slot, sender slot: a PROJ_END for that projectile reaches this game from that connection
%macro END_FROM 3
    mov     byte [msg], %1
    mov     byte [msg + 1], %2
    lea     rdx, [msg]
    mov     edi, %3
    mov     esi, MT_PROJ_END
    mov     ecx, 2
    call    nx_on_proj_end
%endmacro

; The host takes a projectile (and its end) from a guest only when that guest fired it: owner peer = the sender. Guest 1's
; own arrow makes a ghost and is passed on; guest 1 claiming guest 2's, the world's or the host's makes nothing and passes
; nothing on; guest 2 cannot end guest 1's arrow, and guest 1 cannot end a world's; guest 1 ends its own and that is passed
; on. A guest hears the host's word for any owner: another guest's, the world's; its own coming back is ignored; it passes
; nothing on.
test_net_proj_owner:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    net_begin
    call    arrows_clear
    mov     byte [net_role], NET_ROLE_HOST
    mov     byte [net_self], 0
    call    cap_on
    PROJ_FROM 1, 7, 1
    call    live_count
    cmp     eax, 1
    jne     .fail
    COUNT   MT_PROJ, 1                                ; passed on
    call    cap_on
    PROJ_FROM 2, 8, 1                                 ; guest 1 claims guest 2's arrow...
    PROJ_FROM 255, 9, 1                               ; ...the world's...
    PROJ_FROM 0, 10, 1                                ; ...the host's
    call    live_count
    cmp     eax, 1
    jne     .fail
    COUNT   MT_PROJ, 0
    END_FROM 1, 7, 2                                  ; guest 2 ends guest 1's arrow
    call    live_count
    cmp     eax, 1
    jne     .fail
    END_FROM 255, 7, 1                                ; guest 1 ends a world's
    COUNT   MT_PROJ_END, 0
    END_FROM 1, 7, 1                                  ; guest 1 ends its own
    call    live_count
    test    eax, eax
    jnz     .fail
    COUNT   MT_PROJ_END, 1
    mov     byte [net_role], NET_ROLE_GUEST           ; a guest hears the host's word
    mov     byte [net_self], 3
    call    cap_on
    PROJ_FROM 2, 4, 0                                 ; another guest's
    PROJ_FROM 255, 5, 0                               ; the world's
    PROJ_FROM 3, 6, 0                                 ; its own coming back
    call    live_count
    cmp     eax, 2
    jne     .fail
    COUNT   MT_PROJ, 0
    END_FROM 255, 5, 0
    call    live_count
    cmp     eax, 1
    jne     .fail
    END_FROM 2, 4, 0
    call    live_count
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    arrows_clear
    call    net_end
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- net_relay_limit -----------------------------------------------------------------------------------------------------------

; sound_msg(): msg = a SOUND message (SND_POP, volume 50) at (3.5, 12, 4.25)
sound_msg:
    sub     rsp, 8
    mov     byte [msg], SND_POP
    mov     byte [msg + 1], 50
    mov     word [msg + 2], 0
    movss   xmm0, [k_3_5]
    movss   xmm1, [k_12]
    movss   xmm2, [k_4_25]
    lea     rdi, [msg + 4]
    call    net_pos_out
    add     rsp, 8
    ret

; fx_msg(): msg = an FX message: an explosion of radius 3 at (3.5, 12, 4.25)
fx_msg:
    sub     rsp, 8
    mov     byte [msg], FXN_EXPLOSION
    mov     byte [msg + 1], 0
    mov     byte [msg + 2], 0
    mov     byte [msg + 3], 0
    mov     dword [msg + 4], __float32__(3.0)
    movss   xmm0, [k_3_5]
    movss   xmm1, [k_12]
    movss   xmm2, [k_4_25]
    lea     rdi, [msg + 8]
    call    net_pos_out
    add     rsp, 8
    ret

; flood(edi sender slot, esi type, edx length): 100 copies of msg reach the host from that guest (type MT_SOUND or MT_FX)
flood:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     eax, 100
    mov     [rsp], eax
.l:
    lea     rdx, [msg]
    mov     edi, ebx
    mov     esi, r12d
    mov     ecx, r13d
    cmp     r12d, MT_SOUND
    jne     .fx
    call    nx_on_sound
    jmp     .next
.fx:
    call    nx_on_fx
.next:
    dec     dword [rsp]
    jnz     .l
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; A guest cannot make the host pass on more sounds and effects than an honest client sends: 100 sounds in one second from guest 2
; reach the other guests as 60 (the limit of net_sound_out), guest 3 has its own 60, and in the next second guest 2 is heard
; again; 100 effects from guest 2 as 30, guest 3 its own 30. (A clock the test sets stands for time.)
test_net_relay_limit:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    net_begin
    call    fx_clear
    mov     rax, 5000000000000                        ; second 5000: the windows start empty
    mov     [nx_clock_ns], rax
    mov     byte [net_role], NET_ROLE_HOST
    mov     byte [net_self], 0
    call    cap_on
    call    sound_msg
    mov     edi, 2
    mov     esi, MT_SOUND
    mov     edx, 20
    call    flood
    COUNT   MT_SOUND, 60
    mov     edi, 3
    mov     esi, MT_SOUND
    mov     edx, 20
    call    flood
    COUNT   MT_SOUND, 120
    mov     rax, 5001000000000                        ; the next second
    mov     [nx_clock_ns], rax
    lea     rdx, [msg]
    mov     edi, 2
    mov     esi, MT_SOUND
    mov     ecx, 20
    call    nx_on_sound
    COUNT   MT_SOUND, 121
    call    cap_on
    call    fx_msg
    mov     edi, 2
    mov     esi, MT_FX
    mov     edx, 24
    call    flood
    COUNT   MT_FX, 30
    mov     edi, 3
    mov     esi, MT_FX
    mov     edx, 24
    call    flood
    COUNT   MT_FX, 60
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     r12d, eax
    mov     qword [nx_clock_ns], 0
    call    fx_clear
    call    net_end
    mov     eax, r12d
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- the running event on the wire, and a guest's accept --------------------------------------------------------------------

section .rodata
align 4
ev_payload:                             ; one EVHUD: a caravan travelling, waiting for a player
    db EVK_CARAVAN, EVS_TRAVEL, 1, 2, FAC_BEASTFOLK, 0, 7, EHF_WAIT
    dw 25, 0
    dd 1234, -567

section .bss
alignb 4
ev_keep:     resb EVHUD_size            ; ev_hud kept while a test runs
ev_none:     resb EVHUD_size            ; ev_hud as events_reset leaves it, taken by test_net_event_state

section .text

; ev_is_payload() -> eax 1 when ev_hud is ev_payload (leaf)
ev_is_payload:
    lea     rsi, [ev_hud]
    lea     rdi, [ev_payload]
    mov     ecx, EVHUD_size
    repe cmpsb
    sete    al
    movzx   eax, al
    ret

; ev_is_none() -> eax 1 when ev_hud is what events_reset leaves: all zero but no protected NPC (slot 255) (leaf)
ev_is_none:
    lea     rsi, [ev_hud]
    lea     rdi, [ev_none]
    mov     ecx, EVHUD_size
    repe cmpsb
    sete    al
    movzx   eax, al
    ret

; ev_save() / ev_restore(): ev_hud, kept in ev_keep
ev_save:
    lea     rsi, [ev_hud]
    lea     rdi, [ev_keep]
    mov     ecx, EVHUD_size
    rep movsb
    ret
ev_restore:
    lea     rsi, [ev_keep]
    lea     rdi, [ev_hud]
    mov     ecx, EVHUD_size
    rep movsb
    ret

; nx_on_event_state(MT_EVENT_STATE, one EVHUD): a guest takes the host's running event; the host, anyone offline, a payload under
; 20 bytes and a role other than guest leave ev_hud alone; a longer payload still gives the first 20 bytes; row 17 of the handler
; table is this handler
test_net_event_state:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    net_begin
    call    ev_save
    call    events_reset
    lea     rsi, [ev_hud]
    lea     rdi, [ev_none]
    mov     ecx, EVHUD_size
    rep movsb                           ; what events_reset leaves is what "no event" means
    lea     rsi, [ev_payload]
    lea     rdi, [msg]
    mov     ecx, EVHUD_size
    rep movsb
    mov     dword [msg + EVHUD_size], 0
    mov     byte [net_role], NET_ROLE_GUEST
    xor     edi, edi
    mov     esi, MT_EVENT_STATE
    lea     rdx, [msg]
    mov     ecx, EVHUD_size
    call    nx_on_event_state
    call    ev_is_payload
    test    eax, eax
    jz      .fail                       ; a guest takes it
    call    events_reset
    mov     byte [net_role], NET_ROLE_HOST
    xor     edi, edi
    mov     esi, MT_EVENT_STATE
    lea     rdx, [msg]
    mov     ecx, EVHUD_size
    call    nx_on_event_state
    call    ev_is_none
    test    eax, eax
    jz      .fail                       ; the host owns the event: it takes nothing
    mov     byte [net_role], NET_ROLE_OFF
    xor     edi, edi
    mov     esi, MT_EVENT_STATE
    lea     rdx, [msg]
    mov     ecx, EVHUD_size
    call    nx_on_event_state
    call    ev_is_none
    test    eax, eax
    jz      .fail
    mov     byte [net_role], NET_ROLE_GUEST
    xor     edi, edi
    mov     esi, MT_EVENT_STATE
    lea     rdx, [msg]
    mov     ecx, EVHUD_size - 1
    call    nx_on_event_state
    call    ev_is_none
    test    eax, eax
    jz      .fail                       ; 19 bytes are no EVHUD
    xor     edi, edi
    mov     esi, MT_EVENT_STATE
    lea     rdx, [msg]
    mov     ecx, EVHUD_size + 4
    call    nx_on_event_state
    call    ev_is_payload
    test    eax, eax
    jz      .fail                       ; 24 bytes: the first 20 are the event
    lea     rax, [net_handlers]
    lea     rcx, [nx_on_event_state]
    cmp     [rax + MT_EVENT_STATE * 8], rcx
    jne     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    ev_restore
    call    net_end
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ea_setup() -> eax the slot of a Stonekin leader that offers an event (FF_HELP), alone in the mob table, no event; -1 on failure
ea_setup:
    sub     rsp, 8
    call    mobs_clear
    call    events_reset
    mov     edi, FAC_STONEKIN
    mov     esi, ROLE_LEADER
    xor     edx, edx
    movss   xmm0, [k_10_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_12]
    call    folk_spawn
    test    eax, eax
    js      .ret
    imul    ecx, eax, MOB_size
    lea     rdx, [mobs]
    or      byte [rdx + rcx + MOB.fflags], FF_HELP
.ret:
    add     rsp, 8
    ret

; ea_feed(edi slot, esi action, edx type, ecx len) -> eax ev_hud.state after the host got that INTERACT from guest 2 and
; stepped the events once
ea_feed:
    sub     rsp, 8
    mov     [msg], dil
    mov     [msg + 1], sil
    mov     [msg + 2], dl
    mov     byte [msg + 3], 0
    mov     edi, 2
    mov     esi, MT_INTERACT
    lea     rdx, [msg]
    call    nm_on_interact
    call    events_step
    movzx   eax, byte [ev_hud + EVHUD.state]
    add     rsp, 8
    ret

%macro EA_NONE 4                        ; slot reg, action, payload type, length: no event starts
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    call    ea_feed
    cmp     eax, EVS_NONE
    jne     .fail
%endmacro

; The host, on a guest's INTERACT with IA_EVENT_ACCEPT for a folk that offers an event (FF_HELP): the event starts (state
; COUNTDOWN, that folk the protected NPC). No event starts for a folk that offers none, a payload that does not name a folk, a
; mob that is no folk (even one flagged FF_HELP), a message from a role other than the host, or a short message.
test_net_event_accept:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    net_begin
    call    ev_save
    mov     eax, [game_mode]
    mov     [mode_keep], eax
    mov     dword [game_mode], MODE_CREATIVE
    call    cap_on
    mov     byte [net_role], NET_ROLE_HOST
    mov     byte [net_self], 0
    call    ea_setup                    ; the folk that offers one is accepted
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, ebx
    mov     esi, IA_EVENT_ACCEPT
    mov     edx, MOB_FOLK
    mov     ecx, 4
    call    ea_feed
    cmp     eax, EVS_COUNTDOWN
    jne     .fail
    movzx   eax, byte [ev_hud + EVHUD.protect]
    cmp     eax, ebx
    jne     .fail
    call    ea_setup                    ; a folk that offers nothing
    test    eax, eax
    js      .fail
    mov     ebx, eax
    imul    ecx, ebx, MOB_size
    lea     rdx, [mobs]
    and     byte [rdx + rcx + MOB.fflags], ~FF_HELP
    EA_NONE ebx, IA_EVENT_ACCEPT, MOB_FOLK, 4
    call    ea_setup                    ; a payload that names no folk
    test    eax, eax
    js      .fail
    mov     ebx, eax
    EA_NONE ebx, IA_EVENT_ACCEPT, MOB_ZOMBIE, 4
    call    mobs_clear                  ; a zombie flagged FF_HELP is no folk
    call    events_reset
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_10_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_12]
    call    mob_spawn
    test    eax, eax
    js      .fail
    mov     ebx, eax
    imul    ecx, ebx, MOB_size
    lea     rdx, [mobs]
    or      byte [rdx + rcx + MOB.fflags], FF_HELP
    EA_NONE ebx, IA_EVENT_ACCEPT, MOB_FOLK, 4
    call    ea_setup                    ; a guest's own game does not run it
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     byte [net_role], NET_ROLE_GUEST
    EA_NONE ebx, IA_EVENT_ACCEPT, MOB_FOLK, 4
    mov     byte [net_role], NET_ROLE_HOST
    call    ea_setup                    ; a message under 4 bytes
    test    eax, eax
    js      .fail
    mov     ebx, eax
    EA_NONE ebx, IA_EVENT_ACCEPT, MOB_FOLK, 3
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    mobs_clear
    call    events_reset
    call    ev_restore
    mov     eax, [mode_keep]
    mov     [game_mode], eax
    call    net_end
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- a rune spell on the wire -------------------------------------------------------------------------------------------------

%define SPELLMSG_size 36                ; netmisc.asm's SPELLMSG and PROJMSG: kind, element, length, direction, position / owner, kind,
%define PROJMSG_size  36                ; flags, position, velocity

section .rodata
align 4
k_beam_ok:   dd 10.0
k_beam_long: dd 30.0
k_m28:       dd -28.0

section .text

; beam_msg(xmm0 length, edx element): msg = a beam message from (3.5, 12, 4.25) along -z
beam_msg:
    sub     rsp, 8
    mov     byte [msg], SPM_BEAM
    mov     [msg + 1], dl
    mov     word [msg + 2], 0
    movss   [msg + 4], xmm0
    mov     dword [msg + 8], 0
    mov     dword [msg + 12], 0
    mov     dword [msg + 16], __float32__(-1.0)
    movss   xmm0, [k_3_5]
    movss   xmm1, [k_12]
    movss   xmm2, [k_4_25]
    lea     rdi, [msg + 20]
    call    net_pos_out
    add     rsp, 8
    ret

; BEAM_IN n: the beam message of n bytes comes in from the host (slot 0)
%macro BEAM_IN 1
    xor     edi, edi
    mov     esi, MT_SPELL
    lea     rdx, [msg]
    mov     ecx, %1
    call    nx_on_spell
%endmacro

; A guest draws the beam another player cast: a valid one (10 blocks, frost) leaves its motes (18: one every half block from a block out); a
; message that is short, has no length or one beyond 24.5 blocks, or an element above poison draws nothing. A PROJMSG of
; kind PROJ_SPELL becomes a ghost (AF_GHOST) with its element kept; with an element above poison it is dropped.
test_spell_net:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    net_begin
    mov     byte [net_role], NET_ROLE_GUEST
    mov     byte [net_self], 1
    call    fx_clear
    movss   xmm0, [k_beam_ok]
    mov     edx, ELEM_FROST
    call    beam_msg
    BEAM_IN SPELLMSG_size
    call    fx_count
    cmp     eax, 18
    jb      .fail
    call    fx_clear                    ; ---- what is dropped
    movss   xmm0, [k_beam_ok]
    mov     edx, ELEM_FROST
    call    beam_msg
    BEAM_IN SPELLMSG_size - 1           ; short
    call    fx_count
    test    eax, eax
    jnz     .fail
    xorps   xmm0, xmm0                  ; no length
    mov     edx, ELEM_FROST
    call    beam_msg
    BEAM_IN SPELLMSG_size
    call    fx_count
    test    eax, eax
    jnz     .fail
    movss   xmm0, [k_beam_long]         ; 30 blocks
    mov     edx, ELEM_FROST
    call    beam_msg
    BEAM_IN SPELLMSG_size
    call    fx_count
    test    eax, eax
    jnz     .fail
    movss   xmm0, [k_beam_ok]
    mov     edx, ELEM_POISON + 1        ; an element that does not exist
    call    beam_msg
    BEAM_IN SPELLMSG_size
    call    fx_count
    test    eax, eax
    jnz     .fail
    call    arrows_clear                ; ---- the ghost of another player's Ball
    mov     byte [msg], 0               ; fired by peer 0 (the host), from its slot 0
    mov     byte [msg + 1], 0
    mov     byte [msg + 2], PROJ_SPELL
    mov     byte [msg + 3], 0
    mov     dword [msg + 4], ELEM_FROST << AF_ELEM_SHIFT
    movss   xmm0, [k_3_5]
    movss   xmm1, [k_12]
    movss   xmm2, [k_4_25]
    lea     rdi, [msg + 8]
    call    net_pos_out
    mov     dword [msg + 24], 0
    mov     dword [msg + 28], 0
    movss   xmm0, [k_m28]
    movss   [msg + 32], xmm0
    xor     edi, edi
    mov     esi, MT_PROJ
    lea     rdx, [msg]
    mov     ecx, PROJMSG_size
    call    nx_on_proj
    cmp     dword [arrows + ARROWENT.live], 1
    jne     .fail
    cmp     dword [arrows + ARROWENT.kind], PROJ_SPELL
    jne     .fail
    cmp     dword [arrows + ARROWENT.flags], AF_GHOST | (ELEM_FROST << AF_ELEM_SHIFT)
    jne     .fail
    call    arrows_clear
    mov     dword [msg + 4], (ELEM_POISON + 1) << AF_ELEM_SHIFT
    xor     edi, edi
    mov     esi, MT_PROJ
    lea     rdx, [msg]
    mov     ecx, PROJMSG_size
    call    nx_on_proj
    cmp     dword [arrows + ARROWENT.live], 0
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    arrows_clear
    call    fx_clear
    call    net_end
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret
