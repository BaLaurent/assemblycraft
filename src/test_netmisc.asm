; test_netmisc.asm - multiplayer: the shared quest chain and faction standing, the night everybody sleeps through, and the
; ghosts (twins) of other peers' projectiles. The network side is the capture seam (net_capture): nothing is sent; the tests
; read back the records net_out / net_send_to / net_relay would have sent. Every test restores what it touched.
%include "common.inc"
default rel

global test_net_quest_shared, test_net_sleep_all, test_net_ghost_projectile

extern net_role, net_self, net_pvp, net_applying, net_peers, net_capture, net_captured, net_pos_out
extern rpg_state, rpg_stats, inv, inv_clear, inv_count, world_header
extern quests_accept, quests_complete, quests_on_kill, quests_progress
extern faction_add, faction_standing
extern nx_on_quest_complete, nx_on_quest_reward, nx_on_quest_sync, nx_on_faction_add, nx_on_standing
extern sleep_step, sleep_active, sleep_timer, sleep_fade, game_time, banner_text, str_eq
extern arrows, arrow_net, arrows_clear, arrows_spawn, arrows_step, nx_on_proj, nx_on_proj_end
extern mobs, mobs_clear, mob_spawn, world_clear, world_set, world_get
extern player, game_mode, surv, survival_reset

%define SLEEP_STEPS 120                 ; sleep.asm's: steps in bed until the morning
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
s_waiting:  db "Waiting for the others to sleep", 0

section .bss
alignb 16
cap:         resb CAP_SIZE              ; the capture buffer
peers_keep:  resb PEER_size * NET_MAX_PEERS
inv_keep:    resb INVENTORY_size
surv_keep:   resb SURVIVAL_size
player_keep: resb BODY_size
rpg_keep:    resb RPGSAVE_size
stand_keep:  resb 24                    ; world_header.standing (16) and .champions (1)
msg:         resb 64                    ; a message under construction
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
