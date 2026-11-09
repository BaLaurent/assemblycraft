; test_netmobs.asm - multiplayer mobs and combat (0.11): the mob, drop, boat and TNT snapshots and the copies that follow
; them, a zombie and a folk that hunt the nearest player and strike a remote one through a HURT message (which the
; victim's game applies), a guest's blow, stun and status that go to the host and are applied there, the XP of a kill that
; goes to the guest who dealt it, and the PvP switch with its relay. Network traffic is read back from the net_capture
; seam: records of slot u8 (255 for net_out), type u8, len u16, payload.
%include "common.inc"
default rel

global test_net_mob_snapshot_apply, test_net_mob_target_nearest, test_net_guest_hit_forward
global test_net_kill_credit, test_net_pvp_toggle
global test_net_drop_slot63, test_net_kill_authority, test_net_fang_kill_reset, test_net_folk_provoker_kept

extern net_role, net_self, net_pvp, net_applying, net_hit_peer, net_peers, net_capture, net_captured
extern mobs, mobs_clear, mobs_step, mob_spawn, mob_replica_init, mob_set_stun, drops, drops_clear
extern boats, boat_riding, boat_rider, primed, folk_spawn, folk_interact, faction_standing
extern player, body_init, world_clear, world_set, rng_seed, game_mode, game_time, settings
extern rpg_state, rpg_reset, survival_reset, surv, combat_reset, combat_hit_flags, combat_attack_cd, combat_guard_t
extern combat_hit_mob, combat_hit_player, combat_melee_player, status_apply, dmgnum_clear
extern nm_snap_send, nm_guest_step, nm_on_snap_mobs, nm_on_snap_drops, nm_on_snap_misc
extern nm_on_hit, nm_on_status, nm_on_mobfx, nm_on_kill, nm_on_hurt, nm_on_pvp_hit
extern net_nearest_target, net_players_raycast, net_hurt_send_direct, nm_on_interact
extern world_origin_x, world_origin_z, structures_step, mob_spawn_level
extern inv, inv_clear, inv_sel, rpg_keystones, gear_powers, combat_stamina
extern net_drop_flush, net_pos_out, combat_melee, combat_fang_slot, combat_fang_t, abilities_cd, folk_on_player_hit

%define CAP_SIZE 16384

section .rodata
align 4
k_20_5:   dd 20.5
k_neg1:   dd -1.0
k_half_w: dd 0.3
k_height: dd 1.8
k_speed:  dd 4.317
k_4_5:    dd 4.5
k_6:      dd 6.0
k_7_5:    dd 7.5
k_10:     dd 10.0
k_10_5:   dd 10.5
k_11:     dd 11.0
k_12_5:   dd 12.5
k_14_5:   dd 14.5
k_18_5:   dd 18.5
k_1:      dd 1.0
k_0:      dd 0.0
k_5:      dd 5.0
k_t_lo:   dd 3.6
k_t_hi:   dd 3.8
k_eps:    dd 0.01
k_absmask: dd 0x7FFFFFFF
k_9_2:    dd 9.2                        ; 8.5 + 0.35 x 2: one step of a copy towards its target
k_3:      dd 3.0
k_126:    dd 126.0
k_10_5_5: dd 10.5
k_11_5:   dd 11.5
k_10_7:   dd 10.7
k_12:     dd 12.0
k_90:     dd 90.0
k_9_5:    dd 9.5
k_800_5:  dd 800.5
k_60_5:   dd 60.5
k_6_5:    dd 6.5
k_80:     dd 80.0
align 4
ray_origin: dd 10.5, 12.62, 10.5        ; the eye of a player at (10.5, 11, 10.5)
ray_dir:    dd 0.0, 0.0, 1.0            ; ... looking along +z

section .bss
alignb 16
cap_a:      resb CAP_SIZE
cap_b:      resb CAP_SIZE
cap_a_len:  resd 1
cap_b_len:  resd 1
cap_c:      resb CAP_SIZE
cap_c_len:  resd 1
saved_xp:   resd 1
saved_hp:   resd 1
hurt_copy:  resb 64                     ; a copy of a captured payload (the capture buffer is reused)
pvp_pay:    resb 32

section .text

; FNEAR mem, constant: fail unless |float at mem - float constant| < 0.01
%macro FNEAR 2
    movss   xmm0, %1
    subss   xmm0, [%2]
    andps   xmm0, [k_absmask_v]
    ucomiss xmm0, [k_eps]
    jp      .fail
    jae     .fail
%endmacro

section .rodata
align 16
k_absmask_v: dd 0x7FFFFFFF, 0, 0, 0
section .text

; cap_find(rdi buf, esi len, edx type, ecx nth) -> rax the nth (from 0) record of that type among the first len bytes of
; the capture buffer, or 0. A record: slot u8, type u8, len u16, payload.
cap_find:
    mov     esi, esi
    lea     r8, [rdi + rsi]
.next:
    cmp     rdi, r8
    jae     .none
    movzx   eax, byte [rdi + 1]
    cmp     eax, edx
    jne     .skip
    test    ecx, ecx
    jz      .found
    dec     ecx
.skip:
    movzx   eax, word [rdi + 2]
    lea     rdi, [rdi + rax + 4]
    jmp     .next
.found:
    mov     rax, rdi
    ret
.none:
    xor     eax, eax
    ret

; feed(rdi buf, esi len, edx type, rcx handler, r8d from) -> eax 1 when the capture holds a record of that type: the first one
; goes to the handler as handler(from, type, payload, len)
feed:
    push    rbx
    push    r12
    sub     rsp, 8
    mov     r12, rcx
    mov     ebx, r8d
    mov     [rsp], edx
    xor     ecx, ecx
    call    cap_find
    test    rax, rax
    jz      .none
    movzx   ecx, word [rax + 2]
    lea     rdx, [rax + 4]
    mov     edi, ebx
    mov     esi, [rsp]
    call    r12
    mov     eax, 1
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; capture_on(rdi buf): the seam records into buf; capture_off(): it records nothing
capture_on:
    sub     rsp, 8
    mov     esi, CAP_SIZE
    call    net_capture
    add     rsp, 8
    ret
capture_off:
    sub     rsp, 8
    xor     edi, edi
    xor     esi, esi
    call    net_capture
    add     rsp, 8
    ret

; nt_restore(): every global these tests touch goes back: no mobs, drops, boats, TNT or damage numbers, the offline role, no
; peers, no capture, fresh character, survival and combat state
nt_restore:
    sub     rsp, 8
    call    capture_off
    call    mobs_clear
    call    drops_clear
    call    dmgnum_clear
    lea     rdi, [boats]
    mov     ecx, MAX_BOATS * BOATENT_size
    xor     eax, eax
    rep     stosb
    lea     rdi, [primed]
    mov     ecx, MAX_PRIMED * PRIMED_size
    xor     eax, eax
    rep     stosb
    lea     rdi, [boat_rider]
    mov     ecx, MAX_BOATS
    xor     eax, eax
    rep     stosb
    mov     dword [boat_riding], 0
    mov     byte [net_role], NET_ROLE_OFF
    mov     byte [net_self], 0
    mov     byte [net_pvp], 0
    mov     byte [net_applying], 0
    mov     dword [net_hit_peer], 0
    lea     rdi, [net_peers]
    mov     ecx, PEER_size * NET_MAX_PEERS
    xor     eax, eax
    rep     stosb
    call    rpg_reset
    call    survival_reset
    call    combat_reset
    call    inv_clear
    add     rsp, 8
    ret

; nt_fixture(): Survival at Normal difficulty at night, the rng seeded, no mobs or items, a fresh level-1 character, the
; player (0.3 x 1.8) at (10.5, 11, 10.5)
nt_fixture:
    sub     rsp, 8
    mov     edi, 1234
    call    rng_seed
    call    mobs_clear
    call    drops_clear
    call    inv_clear
    mov     dword [inv_sel], 0
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    mov     dword [game_time], 40000
    mov     dword [rpg_keystones], 0
    mov     dword [gear_powers], 0
    call    rpg_reset
    call    survival_reset
    call    combat_reset
    call    dmgnum_clear
    lea     rdi, [player]
    movss   xmm0, [k_half_w]
    movss   xmm1, [k_height]
    movss   xmm2, [k_speed]
    call    body_init
    mov     dword [player + BODY.x], __float32__(10.5)
    mov     dword [player + BODY.y], __float32__(11.0)
    mov     dword [player + BODY.z], __float32__(10.5)
    add     rsp, 8
    ret

; nt_floor(edi lo, esi hi): a stone floor at y = 10 for x, z in lo..hi, both inclusive (the columns world_clear made ready)
nt_floor:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 8
    mov     r13d, edi
    mov     r14d, esi
    mov     r12d, r13d
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
    cmp     r12d, r14d
    jle     .z
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; peer_ready(edi slot, xmm0 x, xmm1 y, xmm2 z): that peer is READY with its proxy's feet there (local) and level 3
peer_ready:
    imul    edi, edi, PEER_size
    lea     rax, [net_peers]
    add     rax, rdi
    mov     dword [rax + PEER.state], PEER_READY
    movss   [rax + PEER.body + BODY.x], xmm0
    movss   [rax + PEER.body + BODY.y], xmm1
    movss   [rax + PEER.body + BODY.z], xmm2
    mov     word [rax + PEER.ps + PSTATE.flags], 0
    mov     byte [rax + PEER.ps + PSTATE.level], 3
    ret

; MOBAT slot, type: rdi = &mobs[slot] made a clean copy of that type (mob_replica_init), esi = type consumed
%macro MOBAT 2
    lea     rdi, [mobs + %1 * MOB_size]
    mov     esi, %2
    call    mob_replica_init
%endmacro

; host_table(esi with_pig): the host's mobs for the snapshot test: slot 3 an elite level-7 zombie that burns and winds up
; (health 17 / 20, MOLTEN and SWIFT affixes), slot 40 a pig (9 / 10) when esi != 0, slot 63 a level-3 spider (11 / 16)
host_table:
    push    rbx
    sub     rsp, 16
    mov     ebx, esi
    call    mobs_clear
    MOBAT   3, MOB_ZOMBIE
    mov     dword [mobs + 3 * MOB_size + MOB.health], 17
    mov     dword [mobs + 3 * MOB_size + MOB.max_health], 20
    mov     dword [mobs + 3 * MOB_size + MOB.level], 7
    mov     dword [mobs + 3 * MOB_size + MOB.elite], 1
    mov     dword [mobs + 3 * MOB_size + MOB.affix], AFX_MOLTEN | AFX_SWIFT
    mov     dword [mobs + 3 * MOB_size + MOB.burn_t], 150
    mov     dword [mobs + 3 * MOB_size + MOB.windup], 12
    mov     dword [mobs + 3 * MOB_size + MOB.target], 1
    mov     dword [mobs + 3 * MOB_size + MOB.provoked], 77
    mov     dword [mobs + 3 * MOB_size + BODY.x], __float32__(10.5)
    mov     dword [mobs + 3 * MOB_size + BODY.y], __float32__(11.0)
    mov     dword [mobs + 3 * MOB_size + BODY.z], __float32__(12.5)
    mov     dword [mobs + 3 * MOB_size + BODY.yaw], __float32__(350.0)
    test    ebx, ebx
    jz      .spider
    MOBAT   40, MOB_PIG
    mov     dword [mobs + 40 * MOB_size + MOB.health], 9
    mov     dword [mobs + 40 * MOB_size + MOB.max_health], 10
    mov     dword [mobs + 40 * MOB_size + MOB.level], 2
    mov     dword [mobs + 40 * MOB_size + BODY.x], __float32__(14.25)
    mov     dword [mobs + 40 * MOB_size + BODY.y], __float32__(11.0)
    mov     dword [mobs + 40 * MOB_size + BODY.z], __float32__(13.0)
.spider:
    MOBAT   63, MOB_SPIDER
    mov     dword [mobs + 63 * MOB_size + MOB.health], 11
    mov     dword [mobs + 63 * MOB_size + MOB.max_health], 16
    mov     dword [mobs + 63 * MOB_size + MOB.level], 3
    mov     dword [mobs + 63 * MOB_size + BODY.x], __float32__(5.0)
    mov     dword [mobs + 63 * MOB_size + BODY.y], __float32__(11.0)
    mov     dword [mobs + 63 * MOB_size + BODY.z], __float32__(5.0)
    add     rsp, 16
    pop     rbx
    ret

; host_extras(esi present): the host's drop in slot 7 (4 arrows at (11.5, 11, 11.5)), boat in slot 2 (at (12, 10.5, 9) heading
; 90, ridden by peer slot 1: boat_rider 2) and primed TNT in slot 0 (fuse 40 at (9.5, 11, 9.5)); with esi == 0 all three are gone
host_extras:
    test    esi, esi
    jz      .gone
    mov     byte [drops + 7 * DROP_size + DROP.id], ARROW
    mov     byte [drops + 7 * DROP_size + DROP.count], 4
    mov     word [drops + 7 * DROP_size + DROP.dmg], 0
    mov     dword [drops + 7 * DROP_size + DROP.x], __float32__(11.5)
    mov     dword [drops + 7 * DROP_size + DROP.y], __float32__(11.0)
    mov     dword [drops + 7 * DROP_size + DROP.z], __float32__(11.5)
    mov     dword [boats + 2 * BOATENT_size + BOATENT.used], 1
    mov     dword [boats + 2 * BOATENT_size + BODY.x], __float32__(12.0)
    mov     dword [boats + 2 * BOATENT_size + BODY.y], __float32__(10.5)
    mov     dword [boats + 2 * BOATENT_size + BODY.z], __float32__(9.0)
    mov     dword [boats + 2 * BOATENT_size + BODY.yaw], __float32__(90.0)
    mov     byte [boat_rider + 2], 2
    mov     dword [primed + 0 * PRIMED_size + PRIMED.fuse], 40
    mov     dword [primed + 0 * PRIMED_size + PRIMED.body + BODY.x], __float32__(9.5)
    mov     dword [primed + 0 * PRIMED_size + PRIMED.body + BODY.y], __float32__(11.0)
    mov     dword [primed + 0 * PRIMED_size + PRIMED.body + BODY.z], __float32__(9.5)
    ret
.gone:
    mov     byte [drops + 7 * DROP_size + DROP.id], 0
    mov     dword [boats + 2 * BOATENT_size + BOATENT.used], 0
    mov     dword [primed + 0 * PRIMED_size + PRIMED.fuse], 0
    ret

; Mobs, drops, boats and TNT on the wire. The host's tables (an elite burning zombie in slot 3, a pig in 40, a spider in 63; a drop,
; a boat and a primed TNT) are sent to a guest's proxy: SNAP_MOBS with 3 records and the mask of those slots, SNAP_DROPS, SNAP_MISC.
; Fed to a guest with empty tables they make the same things (type, health, level, elite, affixes, burning, wind-up, position,
; the drop's item and count, the boat's pose, the TNT's fuse). The guest's copies then follow their targets, one step at a
; time: 0.35 of the way for a mob, half for a drop, the TNT's fuse counting down. The next snapshot, without the pig, the drop,
; the boat and the TNT, empties them and leaves the others.
test_net_mob_snapshot_apply:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    nt_fixture
    mov     byte [net_role], NET_ROLE_HOST
    mov     byte [net_self], 0
    mov     edi, 1
    movss   xmm0, [k_10]
    movss   xmm1, [k_11]
    movss   xmm2, [k_10]
    call    peer_ready
    mov     esi, 1
    call    host_table
    mov     esi, 1
    call    host_extras
    lea     rdi, [cap_a]
    call    capture_on
    mov     edi, 1
    call    nm_snap_send
    mov     eax, [net_captured]
    mov     [cap_a_len], eax
    lea     rdi, [cap_a]                ; the boat's rider: boat_rider[2] = 2, peer slot 1 + 1
    mov     esi, [cap_a_len]
    mov     edx, MT_SNAP_MISC
    xor     ecx, ecx
    call    cap_find
    test    rax, rax
    jz      .fail
    cmp     byte [rax + 4 + 4 + BOATREC.rider], 2
    jne     .fail
    mov     byte [boat_rider + 2], 0    ; ... and 1 when the host itself rides it
    mov     dword [boat_riding], 3
    lea     rdi, [cap_c]
    call    capture_on
    mov     edi, 1
    call    nm_snap_send
    mov     eax, [net_captured]
    mov     [cap_c_len], eax
    mov     dword [boat_riding], 0
    lea     rdi, [cap_c]
    mov     esi, [cap_c_len]
    mov     edx, MT_SNAP_MISC
    xor     ecx, ecx
    call    cap_find
    test    rax, rax
    jz      .fail
    cmp     byte [rax + 4 + 4 + BOATREC.rider], 1
    jne     .fail
    xor     esi, esi                    ; the second snapshot: no pig, no drop, no boat, no TNT
    call    host_table
    xor     esi, esi
    call    host_extras
    lea     rdi, [cap_b]
    call    capture_on
    mov     edi, 1
    call    nm_snap_send
    mov     eax, [net_captured]
    mov     [cap_b_len], eax
    call    capture_off
    ; the first message: count 3, the mask of slots 3, 40 and 63
    lea     rdi, [cap_a]
    mov     esi, [cap_a_len]
    mov     edx, MT_SNAP_MOBS
    xor     ecx, ecx
    call    cap_find
    test    rax, rax
    jz      .fail
    cmp     byte [rax + 4 + 12], 3
    jne     .fail
    mov     rcx, 1 << 3
    mov     rdx, 1 << 40
    or      rcx, rdx
    mov     rdx, 1 << 63
    or      rcx, rdx
    cmp     [rax + 4 + 4], rcx
    jne     .fail
    ; the guest
    call    mobs_clear
    mov     byte [net_role], NET_ROLE_GUEST
    mov     byte [net_self], 1
    lea     rdi, [cap_a]
    mov     esi, [cap_a_len]
    mov     edx, MT_SNAP_MOBS
    lea     rcx, [nm_on_snap_mobs]
    xor     r8d, r8d
    call    feed
    test    eax, eax
    jz      .fail
    lea     rdi, [cap_a]
    mov     esi, [cap_a_len]
    mov     edx, MT_SNAP_DROPS
    lea     rcx, [nm_on_snap_drops]
    xor     r8d, r8d
    call    feed
    test    eax, eax
    jz      .fail
    lea     rdi, [cap_a]
    mov     esi, [cap_a_len]
    mov     edx, MT_SNAP_MISC
    lea     rcx, [nm_on_snap_misc]
    xor     r8d, r8d
    call    feed
    test    eax, eax
    jz      .fail
    cmp     dword [mobs + 3 * MOB_size + MOB.type], MOB_ZOMBIE
    jne     .fail
    cmp     dword [mobs + 3 * MOB_size + MOB.health], 17
    jne     .fail
    cmp     dword [mobs + 3 * MOB_size + MOB.max_health], 20
    jne     .fail
    cmp     dword [mobs + 3 * MOB_size + MOB.level], 7
    jne     .fail
    cmp     dword [mobs + 3 * MOB_size + MOB.elite], 1
    jne     .fail
    cmp     dword [mobs + 3 * MOB_size + MOB.affix], AFX_MOLTEN | AFX_SWIFT
    jne     .fail
    cmp     dword [mobs + 3 * MOB_size + MOB.burn_t], 150
    jne     .fail
    cmp     dword [mobs + 3 * MOB_size + MOB.windup], 12
    jne     .fail
    cmp     dword [mobs + 3 * MOB_size + MOB.target], 1
    jne     .fail
    cmp     dword [mobs + 3 * MOB_size + MOB.provoked], 0
    jle     .fail
    movss   xmm0, [mobs + 3 * MOB_size + BODY.x]
    ucomiss xmm0, [k_10_5]
    jne     .fail
    movss   xmm0, [mobs + 3 * MOB_size + BODY.z]
    ucomiss xmm0, [k_12_5]
    jne     .fail
    cmp     dword [mobs + 40 * MOB_size + MOB.type], MOB_PIG
    jne     .fail
    cmp     dword [mobs + 40 * MOB_size + MOB.health], 9
    jne     .fail
    cmp     dword [mobs + 63 * MOB_size + MOB.type], MOB_SPIDER
    jne     .fail
    cmp     dword [mobs + 63 * MOB_size + MOB.level], 3
    jne     .fail
    cmp     dword [mobs + 0 * MOB_size + MOB.type], MOB_NONE
    jne     .fail
    cmp     byte [drops + 7 * DROP_size + DROP.id], ARROW
    jne     .fail
    cmp     byte [drops + 7 * DROP_size + DROP.count], 4
    jne     .fail
    cmp     dword [drops + 7 * DROP_size + DROP.delay], 9999
    jne     .fail
    cmp     dword [boats + 2 * BOATENT_size + BOATENT.used], 1
    jne     .fail
    movss   xmm0, [boats + 2 * BOATENT_size + BODY.x]
    ucomiss xmm0, [k_12]
    jne     .fail
    movss   xmm0, [boats + 2 * BOATENT_size + BODY.yaw]
    ucomiss xmm0, [k_90]
    jne     .fail
    cmp     dword [primed + 0 * PRIMED_size + PRIMED.fuse], 40
    jne     .fail
    movss   xmm0, [primed + 0 * PRIMED_size + PRIMED.body + BODY.x]
    ucomiss xmm0, [k_9_5]
    jne     .fail
    cmp     dword [primed + 1 * PRIMED_size + PRIMED.fuse], 0
    jne     .fail
    ; the copies follow their targets: the mob was put 2 blocks west of it, the drop 2 west, the boat 2 west
    mov     dword [mobs + 3 * MOB_size + BODY.x], __float32__(8.5)
    mov     dword [drops + 7 * DROP_size + DROP.x], __float32__(9.5)
    mov     dword [boats + 2 * BOATENT_size + BODY.x], __float32__(10.0)
    mov     dword [mobs + 3 * MOB_size + BODY.yaw], __float32__(10.0)   ; the host's mob faces 350: the short way round is -20
    call    nm_guest_step
    FNEAR   [mobs + 3 * MOB_size + BODY.x], k_9_2
    FNEAR   [drops + 7 * DROP_size + DROP.x], k_10_5_5
    FNEAR   [boats + 2 * BOATENT_size + BODY.x], k_10_7
    FNEAR   [mobs + 3 * MOB_size + BODY.yaw], k_3
    FNEAR   [mobs + 3 * MOB_size + MOB.walk], k_126
    cmp     dword [primed + 0 * PRIMED_size + PRIMED.fuse], 39
    jne     .fail
    cmp     dword [drops + 7 * DROP_size + DROP.age], 1
    jne     .fail
    cmp     dword [mobs + 3 * MOB_size + MOB.windup], 11
    jne     .fail
    mov     ebx, 60
.walk:
    call    nm_guest_step
    dec     ebx
    jnz     .walk
    FNEAR   [mobs + 3 * MOB_size + BODY.x], k_10_5_5
    FNEAR   [drops + 7 * DROP_size + DROP.x], k_11_5
    cmp     dword [primed + 0 * PRIMED_size + PRIMED.fuse], 1
    jne     .fail
    ; the second snapshot: slot 40, the drop, the boat and the TNT are gone, the rest stays
    lea     rdi, [cap_b]
    mov     esi, [cap_b_len]
    mov     edx, MT_SNAP_MOBS
    lea     rcx, [nm_on_snap_mobs]
    xor     r8d, r8d
    call    feed
    test    eax, eax
    jz      .fail
    lea     rdi, [cap_b]
    mov     esi, [cap_b_len]
    mov     edx, MT_SNAP_DROPS
    lea     rcx, [nm_on_snap_drops]
    xor     r8d, r8d
    call    feed
    lea     rdi, [cap_b]
    mov     esi, [cap_b_len]
    mov     edx, MT_SNAP_MISC
    lea     rcx, [nm_on_snap_misc]
    xor     r8d, r8d
    call    feed
    cmp     dword [mobs + 40 * MOB_size + MOB.type], MOB_NONE
    jne     .fail
    cmp     dword [mobs + 3 * MOB_size + MOB.type], MOB_ZOMBIE
    jne     .fail
    cmp     dword [mobs + 63 * MOB_size + MOB.type], MOB_SPIDER
    jne     .fail
    cmp     byte [drops + 7 * DROP_size + DROP.id], 0
    jne     .fail
    cmp     dword [boats + 2 * BOATENT_size + BOATENT.used], 0
    jne     .fail
    cmp     dword [primed + 0 * PRIMED_size + PRIMED.fuse], 0
    jne     .fail
    xor     ebx, ebx
    jmp     .out
.fail:
    mov     ebx, 1
.out:
    call    nt_restore
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; A zombie at (4.5, 4.5), the local player 20 blocks away and a peer's proxy (slot 2) 3 blocks away: the nearest target is
; slot 2. With the arm up and the proxy 1.5 blocks away, the blow does not hurt the local player: it leaves as a HURT to slot 2
; (the zombie's damage, CAUSE_ZOMBIE, the zombie's slot) and the local health stays 20. As the victim's game receives that HURT
; (a guest in slot 2) it takes 3 damage and is shoved 6 blocks/s away from the zombie. A provoked bandit guard 4 blocks from the
; proxy goes for it (target 1, peer 2) and strikes it with a HURT of its own (CAUSE_FOLK + FAC_BANDITS).
test_net_mob_target_nearest:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    xor     edi, edi
    mov     esi, 31
    call    nt_floor
    call    nt_fixture
    mov     dword [player + BODY.x], __float32__(24.5)
    mov     dword [player + BODY.z], __float32__(4.5)
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_4_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_4_5]
    call    mob_spawn
    test    eax, eax
    js      .fail
    mov     ebx, eax                    ; the zombie's slot
    mov     byte [net_role], NET_ROLE_HOST
    mov     byte [net_self], 0
    mov     edi, 2
    movss   xmm0, [k_7_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_4_5]
    call    peer_ready
    movss   xmm0, [k_4_5]
    movss   xmm1, [k_4_5]
    mov     edi, 1
    call    net_nearest_target
    cmp     edx, 2
    jne     .fail
    lea     rcx, [net_peers + 2 * PEER_size + PEER.body]
    cmp     rax, rcx
    jne     .fail
    comiss  xmm0, [k_10]                ; 3 blocks: 9
    jae     .fail
    ; the blow: the proxy 1.5 blocks away, the arm up for one more step
    mov     dword [net_peers + 2 * PEER_size + PEER.body + BODY.x], __float32__(6.0)
    imul    ecx, ebx, MOB_size
    lea     rax, [mobs]
    mov     dword [rax + rcx + MOB.windup], 1
    mov     dword [rax + rcx + MOB.cooldown], 0
    lea     rdi, [cap_a]
    call    capture_on
    call    mobs_step
    mov     eax, [net_captured]
    mov     [cap_a_len], eax
    call    capture_off
    lea     rdi, [cap_a]
    mov     esi, [cap_a_len]
    mov     edx, MT_HURT
    xor     ecx, ecx
    call    cap_find
    test    rax, rax
    jz      .fail
    cmp     byte [rax], 2               ; sent to slot 2
    jne     .fail
    cmp     word [rax + 2], 32
    jne     .fail
    cmp     dword [rax + 4], 3          ; Normal: a level-1 zombie hits for 3
    jne     .fail
    cmp     byte [rax + 4 + 4], CAUSE_ZOMBIE
    jne     .fail
    movzx   ecx, byte [rax + 4 + 5]
    cmp     ecx, ebx                    ; the zombie's slot
    jne     .fail
    cmp     byte [rax + 4 + 7], HM_HIT
    jne     .fail
    cmp     dword [surv + SURVIVAL.health], 20
    jne     .fail
    ; the victim's game: slot 2 receives the HURT
    mov     rcx, [rax + 4]
    mov     [hurt_copy], rcx
    mov     rcx, [rax + 4 + 8]
    mov     [hurt_copy + 8], rcx
    mov     rcx, [rax + 4 + 16]
    mov     [hurt_copy + 16], rcx
    mov     rcx, [rax + 4 + 24]
    mov     [hurt_copy + 24], rcx
    mov     byte [net_role], NET_ROLE_GUEST
    mov     byte [net_self], 2
    xor     edi, edi
    mov     esi, MT_HURT
    lea     rdx, [hurt_copy]
    mov     ecx, 32
    call    nm_on_hurt
    cmp     dword [surv + SURVIVAL.health], 17
    jne     .fail
    FNEAR   [player + BODY.kbx], k_6
    FNEAR   [player + BODY.kbz], k_0
    ; a host does not take a HURT from anyone
    mov     byte [net_role], NET_ROLE_HOST
    mov     byte [net_self], 0
    xor     edi, edi
    mov     esi, MT_HURT
    lea     rdx, [hurt_copy]
    mov     ecx, 32
    call    nm_on_hurt
    cmp     dword [surv + SURVIVAL.health], 17
    jne     .fail
    ; a parry: the guard just raised, facing the zombie (yaw 270 looks along -x): no damage, and the zombie is stunned
    ; (a MOBFX to the host with the stun of a parried blow)
    call    survival_reset
    mov     dword [combat_guard_t], 0
    mov     dword [player + BODY.yaw], __float32__(270.0)
    mov     byte [net_role], NET_ROLE_GUEST
    mov     byte [net_self], 2
    lea     rdi, [cap_b]
    call    capture_on
    xor     edi, edi
    mov     esi, MT_HURT
    lea     rdx, [hurt_copy]
    mov     ecx, 32
    call    nm_on_hurt
    mov     eax, [net_captured]
    mov     [cap_b_len], eax
    call    capture_off
    cmp     dword [surv + SURVIVAL.health], 20
    jne     .fail
    lea     rdi, [cap_b]
    mov     esi, [cap_b_len]
    mov     edx, MT_MOBFX
    xor     ecx, ecx
    call    cap_find
    test    rax, rax
    jz      .fail
    movzx   ecx, byte [rax + 4]
    cmp     ecx, ebx                    ; the zombie's slot
    jne     .fail
    cmp     byte [rax + 4 + 1], MFX_STUN
    jne     .fail
    cmp     dword [rax + 4 + 4], STUN_PARRIED
    jne     .fail
    mov     dword [combat_guard_t], -1
    mov     dword [player + BODY.yaw], 0
    call    mobs_clear
    mov     byte [net_role], NET_ROLE_HOST
    mov     byte [net_self], 0
    ; a folk: a provoked bandit guard hunts the nearest player, the peer, and strikes it
    mov     dword [net_peers + 2 * PEER_size + PEER.body + BODY.x], __float32__(18.5)
    mov     dword [net_peers + 2 * PEER_size + PEER.body + BODY.z], __float32__(14.5)
    mov     dword [player + BODY.x], __float32__(30.5)
    mov     dword [player + BODY.z], __float32__(30.5)
    mov     edi, FAC_BANDITS
    mov     esi, ROLE_GUARD
    mov     edx, FCLASS_BRUTE
    movss   xmm0, [k_14_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_14_5]
    call    folk_spawn
    test    eax, eax
    js      .fail
    mov     ebx, eax
    imul    ecx, ebx, MOB_size
    lea     rax, [mobs]
    mov     dword [rax + rcx + MOB.provoked], 600
    mov     r12d, 400
    lea     rdi, [cap_a]
    call    capture_on
.folk:
    call    mobs_step
    dec     r12d
    jnz     .folk
    mov     eax, [net_captured]
    mov     [cap_a_len], eax
    call    capture_off
    imul    ecx, ebx, MOB_size
    lea     rax, [mobs]
    cmp     dword [rax + rcx + MOB.target], 1
    jne     .fail
    cmp     dword [rax + rcx + MOB.peer], 2
    jne     .fail
    lea     rdi, [cap_a]
    mov     esi, [cap_a_len]
    mov     edx, MT_HURT
    xor     ecx, ecx
    call    cap_find
    test    rax, rax
    jz      .fail
    cmp     byte [rax], 2
    jne     .fail
    cmp     byte [rax + 4 + 4], CAUSE_FOLK + FAC_BANDITS
    jne     .fail
    cmp     dword [surv + SURVIVAL.health], 20
    jne     .fail
    ; a mob frozen in a column nobody loads is forgotten, unless a remote player stands near it: peer 3's PSTATE position
    ; is that column at first (net_stream_centres), 800 blocks off afterwards
    call    mobs_clear
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_800_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_4_5]
    call    mob_spawn
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, 3
    movss   xmm0, [k_800_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_4_5]
    call    peer_ready
    mov     eax, [world_origin_x]
    add     eax, 800
    mov     [net_peers + 3 * PEER_size + PEER.ps + PSTATE.pos + NPOS.ax], eax
    mov     eax, [world_origin_z]
    add     eax, 4
    mov     [net_peers + 3 * PEER_size + PEER.ps + PSTATE.pos + NPOS.az], eax
    call    mobs_step
    imul    ecx, ebx, MOB_size
    lea     rax, [mobs]
    cmp     dword [rax + rcx + MOB.type], MOB_ZOMBIE
    jne     .fail                       ; kept: a remote player stands in its column
    mov     eax, [world_origin_x]
    add     eax, 1600
    mov     [net_peers + 3 * PEER_size + PEER.ps + PSTATE.pos + NPOS.ax], eax
    call    mobs_step
    imul    ecx, ebx, MOB_size
    lea     rax, [mobs]
    cmp     dword [rax + rcx + MOB.type], MOB_NONE
    jne     .fail                       ; he has gone: it is forgotten
    ; structures_step with remote players leaves the level override clear
    call    structures_step
    cmp     dword [mob_spawn_level], 0
    jne     .fail
    ; the night spawner works around every player at his own level: the local player (level 1) and peer 1 (level 5)
    ; 50 blocks off: both levels turn up among the mobs, and no other
    mov     edi, -16
    mov     esi, 110
    call    nt_floor
    call    mobs_clear
    mov     dword [net_peers + 2 * PEER_size + PEER.state], PEER_FREE
    mov     dword [net_peers + 3 * PEER_size + PEER.state], PEER_FREE
    mov     edi, 1
    movss   xmm0, [k_60_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_60_5]
    call    peer_ready
    mov     byte [net_peers + 1 * PEER_size + PEER.ps + PSTATE.level], 5
    mov     dword [player + BODY.x], __float32__(10.5)
    mov     dword [player + BODY.z], __float32__(10.5)
    mov     r12d, 12
.tick:
    mov     dword [game_time], 40020
    call    mobs_step
    dec     r12d
    jnz     .tick
    xor     ecx, ecx                    ; levels seen: 1 -> bit 0, 5 -> bit 1, any other -> bit 2
    lea     rax, [mobs]
    mov     edx, MAX_MOBS
.level:
    cmp     dword [rax + MOB.type], MOB_NONE
    je      .level_next
    mov     esi, [rax + MOB.level]
    mov     edi, 4
    cmp     esi, 1
    jne     .not_1
    mov     edi, 1
.not_1:
    cmp     esi, 5
    jne     .seen
    mov     edi, 2
.seen:
    or      ecx, edi
.level_next:
    add     rax, MOB_size
    dec     edx
    jnz     .level
    cmp     ecx, 3
    jne     .fail
    mov     dword [game_time], 3600     ; ...and the day's passive spawner runs round the same centres
    mov     r12d, 4
.day:
    call    mobs_step
    dec     r12d
    jnz     .day
    cmp     dword [mob_spawn_level], 0
    jne     .fail
    xor     ebx, ebx
    jmp     .out
.fail:
    mov     ebx, 1
.out:
    call    nt_restore
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; A guest hits the zombie in slot 5 (combat_hit_mob): the host is asked (a HIT with slot, type and damage), the local copy
; keeps its health and combat_hit_flags is spent. The guest's stun, too, goes to the host (MOBFX) and the copy keeps
; its stun; a status (STATUS) the same. At the host those three messages (from slot 1) do their work: the zombie loses the
; damage, is stunned 40 steps and burns, and is the guest's from then on (MOB.peer 1).
test_net_guest_hit_forward:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    nt_fixture
    mov     byte [net_role], NET_ROLE_GUEST
    mov     byte [net_self], 1
    MOBAT   5, MOB_ZOMBIE
    mov     dword [mobs + 5 * MOB_size + MOB.health], 20
    mov     dword [mobs + 5 * MOB_size + MOB.max_health], 20
    mov     dword [mobs + 5 * MOB_size + MOB.level], 1
    mov     dword [mobs + 5 * MOB_size + BODY.x], __float32__(10.5)
    mov     dword [mobs + 5 * MOB_size + BODY.y], __float32__(11.0)
    mov     dword [mobs + 5 * MOB_size + BODY.z], __float32__(12.5)
    lea     rdi, [cap_a]
    call    capture_on
    mov     edi, 5
    mov     esi, SRC_MELEE
    xor     edx, edx
    movss   xmm0, [k_5]
    movss   xmm1, [k_0]
    movss   xmm2, [k_1]
    call    combat_hit_mob
    test    eax, eax
    jz      .fail                       ; (the damage dealt: asked for)
    mov     ebx, eax                    ; ... and what the host should apply
    cmp     dword [mobs + 5 * MOB_size + MOB.health], 20
    jne     .fail
    cmp     byte [combat_hit_flags], 0
    jne     .fail
    mov     edi, 5
    mov     esi, 40
    call    mob_set_stun
    cmp     dword [mobs + 5 * MOB_size + MOB.stun], 0
    jne     .fail
    mov     edi, 5
    mov     esi, STS_BURN
    movss   xmm0, [k_6]
    call    status_apply
    cmp     dword [mobs + 5 * MOB_size + MOB.burn_t], 0
    jne     .fail
    mov     eax, [net_captured]
    mov     [cap_a_len], eax
    call    capture_off
    lea     rdi, [cap_a]
    mov     esi, [cap_a_len]
    mov     edx, MT_HIT
    xor     ecx, ecx
    call    cap_find
    test    rax, rax
    jz      .fail
    cmp     byte [rax], 255             ; net_out: to the host
    jne     .fail
    cmp     byte [rax + 4], 5           ; slot
    jne     .fail
    cmp     byte [rax + 4 + 3], MOB_ZOMBIE
    jne     .fail
    cmp     [rax + 4 + 4], ebx          ; the damage
    jne     .fail
    lea     rdi, [cap_a]
    mov     esi, [cap_a_len]
    mov     edx, MT_MOBFX
    xor     ecx, ecx
    call    cap_find
    test    rax, rax
    jz      .fail
    cmp     byte [rax + 4], 5
    jne     .fail
    cmp     byte [rax + 4 + 1], MFX_STUN
    jne     .fail
    cmp     dword [rax + 4 + 4], 40
    jne     .fail
    lea     rdi, [cap_a]
    mov     esi, [cap_a_len]
    mov     edx, MT_STATUS
    xor     ecx, ecx
    call    cap_find
    test    rax, rax
    jz      .fail
    cmp     byte [rax + 4], 5
    jne     .fail
    cmp     byte [rax + 4 + 1], STS_BURN
    jne     .fail
    ; the host
    mov     byte [net_role], NET_ROLE_HOST
    mov     byte [net_self], 0
    lea     rdi, [cap_a]
    mov     esi, [cap_a_len]
    mov     edx, MT_MOBFX
    lea     rcx, [nm_on_mobfx]
    mov     r8d, 1
    call    feed
    test    eax, eax
    jz      .fail
    cmp     dword [mobs + 5 * MOB_size + MOB.stun], 40
    jne     .fail
    lea     rdi, [cap_a]
    mov     esi, [cap_a_len]
    mov     edx, MT_STATUS
    lea     rcx, [nm_on_status]
    mov     r8d, 1
    call    feed
    test    eax, eax
    jz      .fail
    cmp     dword [mobs + 5 * MOB_size + MOB.burn_t], 180
    jne     .fail
    cmp     dword [mobs + 5 * MOB_size + MOB.peer], 1
    jne     .fail
    lea     rdi, [cap_a]
    mov     esi, [cap_a_len]
    mov     edx, MT_HIT
    lea     rcx, [nm_on_hit]
    mov     r8d, 1
    call    feed
    test    eax, eax
    jz      .fail
    mov     eax, 20
    sub     eax, ebx
    cmp     [mobs + 5 * MOB_size + MOB.health], eax
    jne     .fail
    cmp     dword [mobs + 5 * MOB_size + MOB.tagged], 0
    jle     .fail                       ; the blow was a player's: it counts for XP
    ; a captive: the guest's right-click on it asks the host (INTERACT) and the copy leaves at once; the host, where the
    ; captive still stands, frees it on that message: +25 with its faction
    call    mobs_clear
    mov     byte [net_role], NET_ROLE_GUEST
    mov     byte [net_self], 1
    mov     edi, FAC_STONEKIN
    mov     esi, ROLE_CAPTIVE
    xor     edx, edx
    movss   xmm0, [k_10_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_12_5]
    call    folk_spawn
    test    eax, eax
    js      .fail
    mov     ebx, eax                    ; its slot
    lea     rdi, [cap_a]
    call    capture_on
    mov     edi, ebx
    call    folk_interact
    mov     eax, [net_captured]
    mov     [cap_a_len], eax
    call    capture_off
    imul    ecx, ebx, MOB_size
    lea     rax, [mobs]
    cmp     dword [rax + rcx + MOB.type], MOB_NONE
    jne     .fail
    mov     byte [net_role], NET_ROLE_HOST
    mov     byte [net_self], 0
    mov     edi, FAC_STONEKIN
    mov     esi, ROLE_CAPTIVE
    xor     edx, edx
    movss   xmm0, [k_10_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_12_5]
    call    folk_spawn
    cmp     eax, ebx                    ; the same slot
    jne     .fail
    mov     edi, FAC_STONEKIN
    call    faction_standing
    mov     [saved_xp], eax
    lea     rdi, [cap_a]
    mov     esi, [cap_a_len]
    mov     edx, MT_INTERACT
    lea     rcx, [nm_on_interact]
    mov     r8d, 1
    call    feed
    test    eax, eax
    jz      .fail
    imul    ecx, ebx, MOB_size
    lea     rax, [mobs]
    cmp     dword [rax + rcx + MOB.type], MOB_NONE
    jne     .fail                       ; freed
    mov     edi, FAC_STONEKIN
    call    faction_standing
    sub     eax, [saved_xp]
    cmp     eax, 25
    jne     .fail
    xor     ebx, ebx
    jmp     .out
.fail:
    mov     ebx, 1
.out:
    call    nt_restore
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; The host applies a guest's lethal HIT (slot 3) on a zombie in slot 2: the XP is the guest's (a KILL to slot 3 with the
; mob's type, elite state and level) and the host's own XP stays where it was; net_hit_peer and net_applying are back to 0.
; As the guest's game receives that KILL it gets the XP.
test_net_kill_credit:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 40                     ; the HIT payload (16) @0
    call    nt_fixture
    mov     byte [net_role], NET_ROLE_HOST
    mov     byte [net_self], 0
    MOBAT   2, MOB_ZOMBIE
    mov     dword [mobs + 2 * MOB_size + MOB.health], 5
    mov     dword [mobs + 2 * MOB_size + MOB.max_health], 20
    mov     dword [mobs + 2 * MOB_size + MOB.level], 1
    mov     dword [mobs + 2 * MOB_size + BODY.x], __float32__(10.5)
    mov     dword [mobs + 2 * MOB_size + BODY.y], __float32__(11.0)
    mov     dword [mobs + 2 * MOB_size + BODY.z], __float32__(12.5)
    mov     eax, [rpg_state + RPGSAVE.xp]
    mov     [saved_xp], eax
    mov     byte [rsp], 2               ; slot
    mov     byte [rsp + 1], 1           ; strike
    mov     byte [rsp + 2], HF_PLAYER
    mov     byte [rsp + 3], MOB_ZOMBIE
    mov     dword [rsp + 4], 50         ; lethal
    mov     dword [rsp + 8], __float32__(1.0)
    mov     dword [rsp + 12], 0
    lea     rdi, [cap_a]
    call    capture_on
    mov     edi, 3
    mov     esi, MT_HIT
    mov     rdx, rsp
    mov     ecx, 16
    call    nm_on_hit
    mov     eax, [net_captured]
    mov     [cap_a_len], eax
    call    capture_off
    cmp     dword [mobs + 2 * MOB_size + MOB.type], MOB_NONE
    jne     .fail                       ; it died
    lea     rdi, [cap_a]
    mov     esi, [cap_a_len]
    mov     edx, MT_KILL
    xor     ecx, ecx
    call    cap_find
    test    rax, rax
    jz      .fail
    cmp     byte [rax], 3               ; to the guest who struck
    jne     .fail
    cmp     byte [rax + 4], MOB_ZOMBIE
    jne     .fail
    cmp     byte [rax + 4 + 1], 0       ; not elite
    jne     .fail
    cmp     dword [rax + 4 + 4], 1      ; level
    jne     .fail
    cmp     word [rax + 4 + 2], 3       ; the mob's slot + 1: slot 2
    jne     .fail
    mov     eax, [rpg_state + RPGSAVE.xp]
    cmp     eax, [saved_xp]
    jne     .fail
    cmp     dword [net_hit_peer], 0
    jne     .fail
    cmp     byte [net_applying], 0
    jne     .fail
    ; the guest's game
    mov     byte [net_role], NET_ROLE_GUEST
    mov     byte [net_self], 3
    lea     rdi, [cap_a]
    mov     esi, [cap_a_len]
    mov     edx, MT_KILL
    lea     rcx, [nm_on_kill]
    xor     r8d, r8d
    call    feed
    test    eax, eax
    jz      .fail
    movzx   eax, byte [rpg_state + RPGSAVE.level]
    cmp     eax, 1
    ja      .paid                       ; (a level-up is a payment too)
    mov     eax, [rpg_state + RPGSAVE.xp]
    cmp     eax, [saved_xp]
    jbe     .fail
.paid:
    xor     ebx, ebx
    jmp     .out
.fail:
    mov     ebx, 1
.out:
    call    nt_restore
    mov     eax, ebx
    add     rsp, 40
    pop     rbx
    pop     rbp
    ret

; PvP. A peer's proxy (slot 1) stands 4 blocks in front of the player: net_players_raycast finds nobody while PvP is off and
; slot 1 (at about 3.7 blocks) while it is on. combat_hit_player then sends a PVP_HIT (victim 1, attacker 0, an amount of at
; least 1 that it also returns, the shove 6 blocks/s) and combat_melee_player lands a strike (cooldown set, a second one refused
; at once); with PvP off neither sends anything. A PVP_HIT received at the host from guest 1 is applied when it is for the host
; (4 damage, a shove away from the guest, the attacker written in) and relayed when it is for guest 2; at a guest it is applied
; only when it is for that guest; with PvP off it is dropped.
test_net_pvp_toggle:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    nt_fixture
    mov     byte [net_role], NET_ROLE_HOST
    mov     byte [net_self], 0
    mov     edi, 1
    movss   xmm0, [k_10_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_14_5]
    call    peer_ready
    mov     byte [net_pvp], 0
    lea     rdi, [ray_origin]
    lea     rsi, [ray_dir]
    movss   xmm0, [k_5]
    call    net_players_raycast
    cmp     eax, -1
    jne     .fail
    lea     rdi, [cap_a]
    call    capture_on
    mov     edi, 1
    mov     esi, SRC_MELEE
    xor     edx, edx
    movss   xmm0, [k_5]
    movss   xmm1, [k_0]
    movss   xmm2, [k_1]
    call    combat_hit_player
    test    eax, eax
    jnz     .fail                       ; PvP off: nothing dealt
    cmp     dword [net_captured], 0
    jne     .fail                       ; (nothing sent)
    mov     edi, 1
    xor     esi, esi
    movss   xmm0, [k_0]
    movss   xmm1, [k_1]
    call    combat_melee_player
    test    eax, eax
    jnz     .fail
    cmp     dword [net_captured], 0
    jne     .fail                       ; nothing was sent
    mov     byte [net_pvp], 1
    lea     rdi, [ray_origin]
    lea     rsi, [ray_dir]
    movss   xmm0, [k_5]
    call    net_players_raycast
    cmp     eax, 1
    jne     .fail
    comiss  xmm0, [k_t_lo]
    jb      .fail
    comiss  xmm0, [k_t_hi]
    ja      .fail
    mov     edi, 1
    mov     esi, SRC_MELEE
    xor     edx, edx
    movss   xmm0, [k_5]
    movss   xmm1, [k_0]
    movss   xmm2, [k_1]
    call    combat_hit_player
    test    eax, eax
    jz      .fail
    mov     ebx, eax                    ; the damage dealt
    mov     eax, [net_captured]
    mov     [cap_a_len], eax
    lea     rdi, [cap_a]
    mov     esi, [cap_a_len]
    mov     edx, MT_PVP_HIT
    xor     ecx, ecx
    call    cap_find
    test    rax, rax
    jz      .fail
    cmp     byte [rax], 1               ; host -> the victim
    jne     .fail
    cmp     byte [rax + 4], 1           ; victim
    jne     .fail
    cmp     byte [rax + 4 + 1], 0       ; attacker: this game's slot
    jne     .fail
    cmp     [rax + 4 + 4], ebx          ; amount: what it returned
    jne     .fail
    cmp     ebx, 1
    jl      .fail
    movss   xmm0, [rax + 4 + 24]        ; shove: |dir| x 6
    ucomiss xmm0, [k_6]
    jne     .fail
    ; a strike: lands, sets the cooldown, a second one is refused
    mov     dword [net_captured], 0
    mov     edi, 1
    xor     esi, esi
    movss   xmm0, [k_0]
    movss   xmm1, [k_1]
    call    combat_melee_player
    cmp     eax, 1
    jne     .fail
    cmp     dword [combat_attack_cd], 0
    jle     .fail
    cmp     dword [net_captured], 0
    je      .fail
    mov     ebx, [net_captured]
    mov     edi, 1
    xor     esi, esi
    movss   xmm0, [k_0]
    movss   xmm1, [k_1]
    call    combat_melee_player
    test    eax, eax
    jnz     .fail                       ; refused while the cooldown runs ...
    cmp     [net_captured], ebx
    jne     .fail                       ; ... and nothing more was sent
    ; the host receives a PVP_HIT from guest 1: for the host (4 damage, a shove away from the guest at (10.5, 6.5))
    call    capture_off
    mov     edi, 2
    movss   xmm0, [k_10_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_18_5]
    call    peer_ready
    lea     rdi, [pvp_pay]
    mov     ecx, 32
    xor     eax, eax
    rep     stosb
    mov     byte [pvp_pay], 0           ; victim: the host
    mov     byte [pvp_pay + 1], 2       ; (a lie: the host writes the sender in)
    mov     byte [pvp_pay + 2], 255
    mov     dword [pvp_pay + 4], 4
    mov     dword [pvp_pay + 12], 10    ; src_ax, az, fx, fz: (10.5, 6.5)
    mov     dword [pvp_pay + 16], 6
    mov     word [pvp_pay + 20], 32768
    mov     word [pvp_pay + 22], 32768
    mov     dword [pvp_pay + 24], __float32__(6.0)
    call    survival_reset
    mov     edi, 1
    mov     esi, MT_PVP_HIT
    lea     rdx, [pvp_pay]
    mov     ecx, 28
    call    nm_on_pvp_hit
    cmp     dword [surv + SURVIVAL.health], 16
    jne     .fail
    FNEAR   [player + BODY.kbz], k_6
    ; ... for guest 2: relayed to it, with the attacker written in
    mov     byte [pvp_pay], 2
    lea     rdi, [cap_a]
    call    capture_on
    mov     edi, 1
    mov     esi, MT_PVP_HIT
    lea     rdx, [pvp_pay]
    mov     ecx, 28
    call    nm_on_pvp_hit
    mov     eax, [net_captured]
    mov     [cap_a_len], eax
    call    capture_off
    lea     rdi, [cap_a]
    mov     esi, [cap_a_len]
    mov     edx, MT_PVP_HIT
    xor     ecx, ecx
    call    cap_find
    test    rax, rax
    jz      .fail
    cmp     byte [rax], 2               ; to the victim
    jne     .fail
    cmp     byte [rax + 4 + 1], 1       ; attacker: the sender
    jne     .fail
    cmp     dword [surv + SURVIVAL.health], 16
    jne     .fail                       ; (the host's own health stays)
    ; PvP off: dropped
    mov     byte [net_pvp], 0
    mov     byte [pvp_pay], 0
    mov     edi, 1
    mov     esi, MT_PVP_HIT
    lea     rdx, [pvp_pay]
    mov     ecx, 28
    call    nm_on_pvp_hit
    cmp     dword [surv + SURVIVAL.health], 16
    jne     .fail
    ; a guest (slot 3): a PVP_HIT for it is applied, one for someone else is not
    call    survival_reset
    mov     byte [net_pvp], 1
    mov     byte [net_role], NET_ROLE_GUEST
    mov     byte [net_self], 3
    mov     byte [pvp_pay], 4
    xor     edi, edi
    mov     esi, MT_PVP_HIT
    lea     rdx, [pvp_pay]
    mov     ecx, 28
    call    nm_on_pvp_hit
    cmp     dword [surv + SURVIVAL.health], 20
    jne     .fail
    mov     byte [pvp_pay], 3
    xor     edi, edi
    mov     esi, MT_PVP_HIT
    lea     rdx, [pvp_pay]
    mov     ecx, 28
    call    nm_on_pvp_hit
    cmp     dword [surv + SURVIVAL.health], 16
    jne     .fail
    ; the heavy attack (PvP on, an iron sword in hand, stamina to spare): a PVP_HIT of round(7 x 2.2) = 15, 20 stamina paid, the
    ; cooldown 3/2 of a sword's 12; too tired it is a dry click and nothing is sent
    mov     byte [net_role], NET_ROLE_HOST
    mov     byte [net_self], 0
    mov     byte [net_pvp], 1
    call    combat_reset
    mov     byte [inv + INVENTORY.slots + ITEMSTACK.id], IRON_SWORD
    mov     byte [inv + INVENTORY.slots + ITEMSTACK.count], 1
    mov     word [inv + INVENTORY.slots + ITEMSTACK.dmg], 0
    lea     rdi, [cap_b]
    call    capture_on
    mov     edi, 1
    mov     esi, 1
    movss   xmm0, [k_0]
    movss   xmm1, [k_1]
    call    combat_melee_player
    mov     ebx, eax
    mov     eax, [net_captured]
    mov     [cap_b_len], eax
    call    capture_off
    cmp     ebx, 1
    jne     .fail
    lea     rdi, [cap_b]
    mov     esi, [cap_b_len]
    mov     edx, MT_PVP_HIT
    xor     ecx, ecx
    call    cap_find
    test    rax, rax
    jz      .fail
    cmp     dword [rax + 4 + 4], 15
    jne     .fail
    cmp     dword [combat_attack_cd], 18
    jne     .fail
    FNEAR   [combat_stamina], k_80
    mov     dword [combat_attack_cd], 0
    mov     dword [combat_stamina], __float32__(10.0)
    lea     rdi, [cap_a]
    call    capture_on
    mov     edi, 1
    mov     esi, 1
    movss   xmm0, [k_0]
    movss   xmm1, [k_1]
    call    combat_melee_player
    mov     ebx, eax
    mov     eax, [net_captured]
    mov     [cap_a_len], eax
    call    capture_off
    test    ebx, ebx
    jnz     .fail                       ; too tired
    cmp     dword [cap_a_len], 0
    jne     .fail                       ; ... and nothing was sent
    ; a blast: the host hurts guest 3 (HM_DIRECT: survival_damage, then a shove away from the blast and up); the guest's game
    ; takes the 5 damage and is thrown; the host's own slot is served at once
    mov     byte [net_pvp], 0
    lea     rdi, [cap_b]
    call    capture_on
    mov     edi, 3
    mov     esi, 5
    mov     edx, CAUSE_EXPLOSION
    mov     ecx, 255
    mov     r8d, 255
    xor     r9d, r9d
    movss   xmm0, [k_10_5]
    movss   xmm1, [k_6_5]
    movss   xmm2, [k_12]
    movss   xmm3, [k_6]
    call    net_hurt_send_direct
    mov     eax, [net_captured]
    mov     [cap_b_len], eax
    call    capture_off
    lea     rdi, [cap_b]
    mov     esi, [cap_b_len]
    mov     edx, MT_HURT
    xor     ecx, ecx
    call    cap_find
    test    rax, rax
    jz      .fail
    cmp     byte [rax], 3
    jne     .fail
    cmp     byte [rax + 4 + 7], HM_DIRECT
    jne     .fail
    mov     rcx, [rax + 4]
    mov     [hurt_copy], rcx
    mov     rcx, [rax + 4 + 8]
    mov     [hurt_copy + 8], rcx
    mov     rcx, [rax + 4 + 16]
    mov     [hurt_copy + 16], rcx
    mov     rcx, [rax + 4 + 24]
    mov     [hurt_copy + 24], rcx
    call    survival_reset
    mov     dword [player + BODY.on_ground], 1
    mov     dword [player + BODY.kbz], 0
    mov     dword [player + BODY.vy], 0
    mov     byte [net_role], NET_ROLE_GUEST
    mov     byte [net_self], 3
    xor     edi, edi
    mov     esi, MT_HURT
    lea     rdx, [hurt_copy]
    mov     ecx, 32
    call    nm_on_hurt
    cmp     dword [surv + SURVIVAL.health], 15
    jne     .fail
    FNEAR   [player + BODY.kbz], k_12   ; (the blast 4 blocks north of him: 12 blocks/s along +z)
    FNEAR   [player + BODY.vy], k_6
    call    survival_reset
    mov     byte [net_role], NET_ROLE_HOST
    mov     byte [net_self], 0
    xor     edi, edi
    mov     esi, 5
    mov     edx, CAUSE_EXPLOSION
    mov     ecx, 255
    mov     r8d, 255
    xor     r9d, r9d
    movss   xmm0, [k_10_5]
    movss   xmm1, [k_6_5]
    movss   xmm2, [k_12]
    movss   xmm3, [k_6]
    call    net_hurt_send_direct
    cmp     dword [surv + SURVIVAL.health], 15
    jne     .fail
    xor     ebx, ebx
    jmp     .out
.fail:
    mov     ebx, 1
.out:
    call    nt_restore
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ==== review round 1 ================================================================================================

; mk_snap63(): hurt_copy = a SNAP_DROPS payload of one record for drop slot 63: 5 stones at (5.0, 11, 5.0)
mk_snap63:
    sub     rsp, 8
    lea     rdi, [hurt_copy]
    mov     ecx, 64
    xor     eax, eax
    rep     stosb
    mov     rax, 1
    shl     rax, 63
    mov     [hurt_copy], rax
    mov     byte [hurt_copy + 8], 1
    mov     byte [hurt_copy + 16 + DROPREC.slot], 63
    mov     byte [hurt_copy + 16 + DROPREC.id], STONE
    mov     byte [hurt_copy + 16 + DROPREC.count], 5
    lea     rdi, [hurt_copy + 16 + DROPREC.pos]
    movss   xmm0, [k_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_5]
    call    net_pos_out
    add     rsp, 8
    ret

; Drop slot 63 is a guest's staging slot (what its drops_spawn makes waits there for net_drop_flush). At a host a drop in it is an
; ordinary drop for the host's pickup and never goes into a snapshot: with drops in slots 7 and 63 near a READY guest the
; SNAP_DROPS lists slot 7 alone (a mask of 1 << 7, one record). At a guest a snapshot that names slot 63 (a buggy or hostile host)
; neither fills an empty staging slot (the guest's step would send it straight back as its own DROP_SPAWN: a duplicate drop) nor
; overwrites a toss that waits in it.
test_net_drop_slot63:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    nt_fixture
    mov     byte [net_role], NET_ROLE_HOST
    mov     byte [net_self], 0
    mov     edi, 1
    movss   xmm0, [k_10]
    movss   xmm1, [k_11]
    movss   xmm2, [k_10]
    call    peer_ready
    mov     byte [drops + 7 * DROP_size + DROP.id], ARROW
    mov     byte [drops + 7 * DROP_size + DROP.count], 4
    mov     dword [drops + 7 * DROP_size + DROP.x], __float32__(11.5)
    mov     dword [drops + 7 * DROP_size + DROP.y], __float32__(11.0)
    mov     dword [drops + 7 * DROP_size + DROP.z], __float32__(11.5)
    mov     byte [drops + 63 * DROP_size + DROP.id], STONE
    mov     byte [drops + 63 * DROP_size + DROP.count], 5
    mov     dword [drops + 63 * DROP_size + DROP.x], __float32__(11.5)
    mov     dword [drops + 63 * DROP_size + DROP.y], __float32__(11.0)
    mov     dword [drops + 63 * DROP_size + DROP.z], __float32__(12.5)
    lea     rdi, [cap_a]
    call    capture_on
    mov     edi, 1
    call    nm_snap_send
    mov     eax, [net_captured]
    mov     [cap_a_len], eax
    call    capture_off
    lea     rdi, [cap_a]
    mov     esi, [cap_a_len]
    mov     edx, MT_SNAP_DROPS
    xor     ecx, ecx
    call    cap_find
    test    rax, rax
    jz      .fail
    cmp     byte [rax + 4 + 8], 1               ; one record ...
    jne     .fail
    cmp     qword [rax + 4], 1 << 7             ; ... of slot 7: the mask has no bit 63
    jne     .fail
    cmp     byte [rax + 4 + 16 + DROPREC.slot], 7
    jne     .fail
    ; the guest's game: a snapshot that names slot 63
    call    drops_clear
    mov     byte [net_role], NET_ROLE_GUEST
    mov     byte [net_self], 1
    call    mk_snap63
    xor     edi, edi
    mov     esi, MT_SNAP_DROPS
    lea     rdx, [hurt_copy]
    mov     ecx, 16 + DROPREC_size
    call    nm_on_snap_drops
    cmp     byte [drops + 63 * DROP_size + DROP.id], 0
    jne     .fail                               ; it cannot fill the staging slot ...
    lea     rdi, [cap_a]
    call    capture_on
    call    net_drop_flush
    mov     eax, [net_captured]
    mov     [cap_a_len], eax
    call    capture_off
    cmp     dword [cap_a_len], 0
    jne     .fail                               ; ... so nothing goes back to the host as the guest's own toss
    mov     byte [drops + 63 * DROP_size + DROP.id], ARROW
    mov     byte [drops + 63 * DROP_size + DROP.count], 3
    xor     edi, edi
    mov     esi, MT_SNAP_DROPS
    lea     rdx, [hurt_copy]
    mov     ecx, 16 + DROPREC_size
    call    nm_on_snap_drops
    cmp     byte [drops + 63 * DROP_size + DROP.id], ARROW
    jne     .fail                               ; a toss that waits there is not overwritten ...
    cmp     byte [drops + 63 * DROP_size + DROP.count], 3
    jne     .fail
    xor     ebx, ebx
    jmp     .out
.fail:
    mov     ebx, 1
.out:
    call    nt_restore
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; mk_kill(edi mob slot + 1): pvp_pay = a KILL payload: an elite level-30 zombie, with that slot
mk_kill:
    mov     r8d, edi
    lea     rdi, [pvp_pay]
    mov     ecx, 32
    xor     eax, eax
    rep     stosb
    mov     byte [pvp_pay], MOB_ZOMBIE
    mov     byte [pvp_pay + 1], 1
    mov     [pvp_pay + 2], r8w
    mov     dword [pvp_pay + 4], 30
    ret

; do_kill(edi from, esi len): nm_on_kill gets pvp_pay from that sender
do_kill:
    sub     rsp, 8
    mov     ecx, esi
    lea     rdx, [pvp_pay]
    mov     esi, MT_KILL
    call    nm_on_kill
    add     rsp, 8
    ret

; xp_same() -> eax 1 when nothing a KILL does has happened: the character's XP and level are what the test started with (saved_xp,
; saved_hp) and the Shadowstep cooldown the test armed (100) is still running
xp_same:
    xor     eax, eax
    mov     ecx, [rpg_state + RPGSAVE.xp]
    cmp     ecx, [saved_xp]
    jne     .ret
    movzx   ecx, byte [rpg_state + RPGSAVE.level]
    cmp     ecx, [saved_hp]
    jne     .ret
    cmp     dword [abilities_cd + ABIL_SHADOWSTEP * 4], 100
    jne     .ret
    mov     eax, 1
.ret:
    ret

; A KILL grants XP and quest progress (and a Shadow Fang backstab waiting for it gets its Shadowstep reset): only a guest takes
; one, and only from the host. The host ignores one from guest 1, a guest ignores one that did not come from slot 0, offline there is
; nothing to receive; from the host a type no mob has (0, 9) or a message cut short is ignored too, and the right one pays.
test_net_kill_authority:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    nt_fixture
    mov     eax, [rpg_state + RPGSAVE.xp]
    mov     [saved_xp], eax
    movzx   eax, byte [rpg_state + RPGSAVE.level]
    mov     [saved_hp], eax
    lea     rdi, [cap_c]
    call    capture_on
    mov     dword [combat_fang_slot], 6         ; a Shadow Fang backstab of the mob in slot 5 waits for its KILL ...
    mov     dword [combat_fang_t], 30
    mov     dword [abilities_cd + ABIL_SHADOWSTEP * 4], 100
    mov     edi, 6                              ; ... which is the one that arrives
    call    mk_kill
    mov     byte [net_role], NET_ROLE_HOST      ; the host: from guest 1
    mov     byte [net_self], 0
    mov     edi, 1
    mov     esi, 8
    call    do_kill
    call    xp_same
    test    eax, eax
    jz      .fail
    mov     byte [net_role], NET_ROLE_GUEST     ; a guest: from anyone but the host
    mov     byte [net_self], 2
    mov     edi, 1
    mov     esi, 8
    call    do_kill
    call    xp_same
    test    eax, eax
    jz      .fail
    mov     byte [net_role], NET_ROLE_OFF       ; offline
    xor     edi, edi
    mov     esi, 8
    call    do_kill
    call    xp_same
    test    eax, eax
    jz      .fail
    mov     byte [net_role], NET_ROLE_GUEST     ; from the host: a type no mob has, a short message
    mov     byte [pvp_pay], 0
    xor     edi, edi
    mov     esi, 8
    call    do_kill
    call    xp_same
    test    eax, eax
    jz      .fail
    mov     byte [pvp_pay], 9
    xor     edi, edi
    mov     esi, 8
    call    do_kill
    call    xp_same
    test    eax, eax
    jz      .fail
    mov     byte [pvp_pay], MOB_ZOMBIE
    xor     edi, edi
    mov     esi, 7
    call    do_kill
    call    xp_same
    test    eax, eax
    jz      .fail
    xor     edi, edi                            ; the right one
    mov     esi, 8
    call    do_kill
    call    xp_same
    test    eax, eax
    jnz     .fail
    xor     ebx, ebx
    jmp     .out
.fail:
    mov     ebx, 1
.out:
    mov     dword [abilities_cd + ABIL_SHADOWSTEP * 4], 0
    call    nt_restore
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; Shadow Fang at a guest. The guest's copy of a mob it backstabs is still alive when the blow lands, so combat_melee cannot see a
; kill: it notes the mob (slot + 1) and a window, and the KILL the host sends (it names the mob) does the Shadowstep reset
; (combat_fang_kill). A KILL for another mob, or one after the window, resets nothing; the one that fits resets once.
test_net_fang_kill_reset:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    nt_fixture
    mov     dword [player + BODY.z], __float32__(12.5)
    mov     byte [net_role], NET_ROLE_GUEST
    mov     byte [net_self], 1
    mov     dword [gear_powers], 1 << LP_SHADOW_FANG
    mov     dword [abilities_cd + ABIL_SHADOWSTEP * 4], 100
    lea     rdi, [cap_c]
    call    capture_on
    MOBAT   5, MOB_ZOMBIE
    mov     dword [mobs + 5 * MOB_size + MOB.health], 5
    mov     dword [mobs + 5 * MOB_size + MOB.max_health], 20
    mov     dword [mobs + 5 * MOB_size + MOB.level], 1
    mov     dword [mobs + 5 * MOB_size + BODY.x], __float32__(10.5)
    mov     dword [mobs + 5 * MOB_size + BODY.y], __float32__(11.0)
    mov     dword [mobs + 5 * MOB_size + BODY.z], __float32__(11.5)
    mov     dword [mobs + 5 * MOB_size + BODY.yaw], 0   ; it faces away from the player: a backstab
    mov     edi, 5
    xorps   xmm0, xmm0
    movss   xmm1, [k_neg1]
    call    combat_melee
    cmp     eax, 1
    jne     .fail
    cmp     dword [combat_fang_slot], 6                 ; noted: slot 5 + 1 ...
    jne     .fail
    cmp     dword [combat_fang_t], 0
    jle     .fail
    cmp     dword [abilities_cd + ABIL_SHADOWSTEP * 4], 100
    jne     .fail                                       ; ... but not reset before the host says it died
    mov     edi, 7                                      ; a KILL for another mob
    call    mk_kill
    xor     edi, edi
    mov     esi, 8
    call    do_kill
    cmp     dword [abilities_cd + ABIL_SHADOWSTEP * 4], 100
    jne     .fail
    mov     dword [combat_fang_t], 0                    ; the window is over
    mov     edi, 6
    call    mk_kill
    xor     edi, edi
    mov     esi, 8
    call    do_kill
    cmp     dword [abilities_cd + ABIL_SHADOWSTEP * 4], 100
    jne     .fail
    mov     dword [combat_fang_t], 30                   ; inside the window: the mob that died is the one that was backstabbed
    xor     edi, edi
    mov     esi, 8
    call    do_kill
    cmp     dword [abilities_cd + ABIL_SHADOWSTEP * 4], 0
    jne     .fail
    cmp     dword [combat_fang_slot], 0                 ; once
    jne     .fail
    xor     ebx, ebx
    jmp     .out
.fail:
    mov     ebx, 1
.out:
    mov     dword [gear_powers], 0
    mov     dword [abilities_cd + ABIL_SHADOWSTEP * 4], 0
    call    nt_restore
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; A provoked folk goes on after the player who hit it. A bandit guard that guest 1 hit (folk_on_player_hit: peer 1, provoked, target 1)
; stands 6 blocks from guest 1 and 2 from guest 2: it walks to guest 1 and strikes him (the first HURT goes to slot 1) and MOB.peer
; stays 1, not the nearest player (the XP of a burning kill and the retaliation are the hitter's). A provoked ally with no player
; target yet still picks the nearest one: guest 2.
test_net_folk_provoker_kept:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    xor     edi, edi
    mov     esi, 31
    call    nt_floor
    call    nt_fixture
    mov     dword [player + BODY.x], __float32__(30.5)
    mov     dword [player + BODY.z], __float32__(30.5)
    mov     byte [net_role], NET_ROLE_HOST
    mov     byte [net_self], 0
    mov     edi, 1
    movss   xmm0, [k_20_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_14_5]
    call    peer_ready                          ; guest 1, the provoker: 6 blocks east of the folk
    mov     edi, 2
    movss   xmm0, [k_12_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_14_5]
    call    peer_ready                          ; guest 2: 2 blocks west of it: the nearest
    mov     edi, FAC_BANDITS
    mov     esi, ROLE_GUARD
    mov     edx, FCLASS_BRUTE
    movss   xmm0, [k_14_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_14_5]
    call    folk_spawn
    test    eax, eax
    js      .fail
    mov     ebx, eax
    imul    edi, ebx, MOB_size
    lea     rax, [mobs]
    add     rdi, rax
    mov     dword [net_hit_peer], 1
    call    folk_on_player_hit                  ; guest 1 hit it
    mov     dword [net_hit_peer], 0
    lea     rdi, [cap_a]
    call    capture_on
    mov     r12d, 400
.walk:
    call    mobs_step
    dec     r12d
    jnz     .walk
    mov     eax, [net_captured]
    mov     [cap_a_len], eax
    call    capture_off
    imul    ecx, ebx, MOB_size
    lea     rax, [mobs]
    cmp     dword [rax + rcx + MOB.peer], 1
    jne     .fail
    cmp     dword [rax + rcx + MOB.target], 1
    jne     .fail
    lea     rdi, [cap_a]
    mov     esi, [cap_a_len]
    mov     edx, MT_HURT
    xor     ecx, ecx
    call    cap_find
    test    rax, rax
    jz      .fail
    cmp     byte [rax], 1                       ; the first blow went to guest 1
    jne     .fail
    call    mobs_clear                          ; an ally: provoked, no player target yet
    mov     edi, FAC_BANDITS
    mov     esi, ROLE_GUARD
    mov     edx, FCLASS_BRUTE
    movss   xmm0, [k_9_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_11_5]
    call    folk_spawn
    test    eax, eax
    js      .fail
    mov     ebx, eax
    imul    ecx, ebx, MOB_size
    lea     rax, [mobs]
    mov     dword [rax + rcx + MOB.provoked], 600
    mov     r12d, 30
.ally:
    call    mobs_step
    dec     r12d
    jnz     .ally
    imul    ecx, ebx, MOB_size
    lea     rax, [mobs]
    cmp     dword [rax + rcx + MOB.target], 1
    jne     .fail
    cmp     dword [rax + rcx + MOB.peer], 2
    jne     .fail
    xor     ebx, ebx
    jmp     .out
.fail:
    mov     ebx, 1
.out:
    call    nt_restore
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret
