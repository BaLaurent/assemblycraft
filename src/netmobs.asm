; netmobs.asm - mobs, drops, boats and primed TNT on the wire, and who hurts whom (0.11 multiplayer).
; The host owns every mob: it simulates them (mobs.asm and friends, unchanged) around every player and
; sends each guest, every SNAP_STEPS steps, what lies within reach of him: SNAP_MOBS (mobs, 96 blocks),
; SNAP_DROPS (items, 48), SNAP_MISC (boats 96, primed TNT 64). A guest keeps copies of them in its own tables
; and only moves them towards the newest snapshot (nm_guest_step); everything it does to them is a message
; to the host: HIT (a blow), STATUS, MOBFX (stun, mark, launch), INTERACT. The host applies those and sends
; the kill's XP to the player who dealt it (KILL). What mobs do to a player is decided by the player's own
; game: the host sends HURT (a blow of a mob or an explosion) and the victim runs it through player_take_hit
; (parry, block, thorns, armour). PvP is the same shape: the attacker's game computes the damage with its
; own stats and sends PVP_HIT through the host to the victim's game.
; Coordinates on the wire are absolute (net_pos_out / net_pos_in); everything here is local.
%include "common.inc"
default rel

global nm_snap_send, nm_guest_step, nm_shift
global net_nearest_target, net_slot_ok, nm_peer_ok, nm_ready_count, nm_centre
global net_mob_hit_player, net_hurt_send, net_hurt_send_direct, net_kill_credit
global net_players_raycast, net_mob_damage_out, net_status_out, net_mobfx_out, net_interact_out
global nm_on_snap_mobs, nm_on_snap_drops, nm_on_snap_misc
global nm_on_hit, nm_on_status, nm_on_mobfx, nm_on_kill, nm_on_hurt, nm_on_pvp_hit, nm_on_interact

extern net_role, net_self, net_pvp, net_applying, net_hit_peer, net_peers
extern net_out, net_send_to, net_pos_out, net_pos_in
extern player, surv, game_time
extern combat_stealth_t, combat_attacker, combat_hit_flags
extern player_take_hit, survival_damage, combat_player_status, combat_kb_mult, combat_fang_kill
extern mobs, mob_hurt, mob_strike, mob_index, mob_replica_init, mob_affix_status
extern mob_set_stun, mob_set_mark, mob_launch, mob_tgt_slot, ray_aabb
extern status_apply_ex, rpg_on_mob_killed, dmgnum_spawn, folk_free_captive, mob_stunned_text
extern events_accept
extern drops, boats, boat_riding, primed, body_init, gear_rarity, boat_rider

%define NM_MOBS_PER_MSG  24             ; MOBREC records per SNAP_MOBS (16 + 24 x 44 = 1072 <= NET_MSG_MAX)
%define NM_DROPS_PER_MSG 45             ; DROPREC records per SNAP_DROPS
%define NM_HIT_LEN       16
%define NM_STATUS_LEN    12
%define NM_MOBFX_LEN     8
%define NM_KILL_LEN      8
%define NM_HURT_LEN      32
%define NM_PVP_LEN       28
%define NM_INTERACT_LEN  4
%define NM_DAMAGE_MAX    1000000        ; the most damage of a blow the host takes on a guest's word
%define NM_FX_MAX        3600           ; ...and the longest stun or mark (steps)
%define NM_BAR_STEPS     60             ; a guest keeps a hurt mob's health bar up this long
%define NM_HURT_STEPS    8              ; ...and its red tint
%define NM_BOSS_STUN     30             ; the Fallen King's stun after a parried slam (mobs.asm BOSS_STUN)

%define VIS_ELITE   1
%define VIS_HURT    2
%define VIS_BURN    4
%define VIS_POISON  8
%define VIS_CHILL   16
%define VIS_FROZEN  32                  ; chill >= 2
%define VIS_WINDUP  64
%define VIS_BAR     128

; .mag: bits 0..7 MOB.affix, 8..9 shock stacks, 10 marked, 11 bleeding, 12..17 wind-up steps left (<= 63),
; 18..25 burn steps left (<= 255), 26 freeze cooling down, 27..29 the faction that holds a captive, 30 a folk
; that is after a player (MOB.target = 1), 31 a folk a blow provoked (folk_hostile reads both)
%define MG_SHOCK_SHIFT  8
%define MG_MARK         (1 << 10)
%define MG_BLEED        (1 << 11)
%define MG_WINDUP_SHIFT 12
%define MG_BURN_SHIFT   18
%define MG_FREEZE       (1 << 26)
%define MG_CAPTOR_SHIFT 27
%define MG_TARGET       (1 << 30)
%define MG_PROVOKED     0x80000000

; CLAMP reg32, hi: reg = min(max(reg, 0), hi); clobbers r11d
%macro CLAMP 2
    xor     r11d, r11d
    test    %1, %1
    cmovs   %1, r11d
    mov     r11d, %2
    cmp     %1, r11d
    cmova   %1, r11d
%endmacro

section .rodata
align 4
c_96sq:     dd 9216.0                   ; mobs within 96 blocks are sent...
c_48sq:     dd 2304.0                   ; ...drops within 48...
c_64sq:     dd 4096.0                   ; ...primed TNT within 64
c_follow:   dd 0.35                     ; a copy covers this much of the way to its target per step
c_follow_d: dd 0.5                      ; ...a drop this much
c_snap2:    dd 36.0                     ; farther than 6 blocks from its target it jumps
c_180:      dd 180.0                    ; walk-cycle degrees per block walked, and half a turn
c_360:      dd 360.0
c_tiny:     dd 0.0001
c_big:      dd 1.0e30
c_two:      dd 2.0
c_lim_dir:  dd 10.0                     ; the knockback direction of a guest's blow is held to +-10...
c_lim_vy:   dd 100.0                    ; ...a launch to +-100 blocks/s...
c_lim_mag:  dd 1000000.0                ; ...a status magnitude to +-1e6...
c_lim_shove: dd 30.0                    ; ...a shove or a lift of the player to +-30 blocks/s...
c_lim_yaw:  dd 720.0                    ; ...and a heading to +-720 degrees
c_over_head: dd 0.2                     ; floating numbers start this far above the head
c_pl_hw:    dd 0.3                      ; a player's box: 0.6 wide, 1.8 high
c_pl_h:     dd 1.8
c_boat_hw:  dd 0.6                      ; a boat's box (boats.asm)
c_boat_h:   dd 0.5

section .bss
alignb 16
nm_buf:     resb 1104                   ; the message being assembled
nm_tgt:     resd MAX_MOBS * 4           ; a mob copy's target: x, y, z, yaw (local)
nd_tgt:     resd MAX_DROPS * 3          ; a drop copy's target: x, y, z
nb_tgt:     resd MAX_BOATS * 4          ; a boat copy's target: x, y, z, yaw
nm_cnt:     resd 1                      ; records in the message being assembled
nm_sent:    resd 1                      ; messages of this kind sent so far

section .text

; ==== who is where =============================================================================================

; nm_peer_ok(edi slot, esi alive_only) -> rax the PEER of that slot when it is another player in the game (READY, not
; this game's own slot) and, with alive_only, not dead; else 0
nm_peer_ok:
    xor     eax, eax
    cmp     edi, NET_MAX_PEERS
    jae     .ret
    movzx   ecx, byte [net_self]
    cmp     edi, ecx
    je      .ret
    imul    edx, edi, PEER_size
    lea     rcx, [net_peers]
    add     rcx, rdx
    cmp     dword [rcx + PEER.state], PEER_READY
    jne     .ret
    test    esi, esi
    jz      .ok
    test    word [rcx + PEER.ps + PSTATE.flags], PS_DEAD
    jnz     .ret
.ok:
    mov     rax, rcx
.ret:
    ret

; nm_ready_count() -> eax the number of READY peers other than this game's own player (0 offline)
nm_ready_count:
    xor     eax, eax
    cmp     byte [net_role], NET_ROLE_OFF
    je      .ret
    lea     r8, [net_peers]
    movzx   r9d, byte [net_self]
    xor     ecx, ecx
.slot:
    cmp     ecx, r9d
    je      .next
    cmp     dword [r8 + PEER.state], PEER_READY
    jne     .next
    inc     eax
.next:
    add     r8, PEER_size
    inc     ecx
    cmp     ecx, NET_MAX_PEERS
    jb      .slot
.ret:
    ret

; nm_centre(edi k) -> rax the BODY of the k-th (from 0) other player in the game who lives, edx his level (at least 1);
; rax 0 past the last one and offline. Mob spawners and the structure spawners work around these.
nm_centre:
    xor     eax, eax
    cmp     byte [net_role], NET_ROLE_OFF
    je      .ret
    lea     r8, [net_peers]
    movzx   r9d, byte [net_self]
    xor     ecx, ecx
.slot:
    cmp     ecx, NET_MAX_PEERS
    jae     .ret
    cmp     ecx, r9d
    je      .next
    cmp     dword [r8 + PEER.state], PEER_READY
    jne     .next
    test    word [r8 + PEER.ps + PSTATE.flags], PS_DEAD
    jnz     .next
    test    edi, edi
    jz      .found
    dec     edi
.next:
    add     r8, PEER_size
    inc     ecx
    jmp     .slot
.found:
    lea     rax, [r8 + PEER.body]
    movzx   edx, byte [r8 + PEER.ps + PSTATE.level]
    mov     ecx, 1
    cmp     edx, ecx
    cmovb   edx, ecx
.ret:
    ret

; net_slot_ok(edi slot, esi need_hostile_ok) -> eax 1 when the player in that slot (the local one, or a READY
; peer) lives and, with need_hostile_ok, is not hidden in smoke
net_slot_ok:
    xor     eax, eax
    cmp     edi, NET_MAX_PEERS
    jae     .ret
    movzx   ecx, byte [net_self]
    cmp     edi, ecx
    jne     .remote
    cmp     dword [surv + SURVIVAL.dead], 0
    jne     .ret
    test    esi, esi
    jz      .yes
    cmp     dword [combat_stealth_t], 0
    jg      .ret
.yes:
    mov     eax, 1
.ret:
    ret
.remote:
    imul    edx, edi, PEER_size
    lea     rcx, [net_peers]
    add     rcx, rdx
    cmp     dword [rcx + PEER.state], PEER_READY
    jne     .ret
    movzx   edx, word [rcx + PEER.ps + PSTATE.flags]
    test    edx, PS_DEAD
    jnz     .ret
    test    esi, esi
    jz      .yes
    test    edx, PS_STEALTH
    jnz     .ret
    jmp     .yes

; net_nearest_target(xmm0 x, xmm1 z, edi need_hostile_ok) -> rax the BODY of the player nearest to (x, z) (horizontally)
; or 0, edx his peer slot, xmm0 the distance^2. The local player counts while he lives and, with
; need_hostile_ok, is not hidden in smoke (combat_stealth_t); so does every READY peer without PS_DEAD (and, with
; need_hostile_ok, without PS_STEALTH). Offline it is the local player under exactly those conditions.
net_nearest_target:
    movss   xmm5, [c_big]
    xor     r8d, r8d                    ; the best body so far
    xor     r9d, r9d                    ; ...and its slot
    movzx   r10d, byte [net_self]
    cmp     dword [surv + SURVIVAL.dead], 0
    jne     .peers
    test    edi, edi
    jz      .local
    cmp     dword [combat_stealth_t], 0
    jg      .peers
.local:
    movss   xmm2, [player + BODY.x]
    subss   xmm2, xmm0
    mulss   xmm2, xmm2
    movss   xmm3, [player + BODY.z]
    subss   xmm3, xmm1
    mulss   xmm3, xmm3
    addss   xmm2, xmm3
    comiss  xmm2, xmm5
    jae     .peers
    movaps  xmm5, xmm2
    lea     r8, [player]
    mov     r9d, r10d
.peers:
    cmp     byte [net_role], NET_ROLE_OFF
    je      .done
    lea     r11, [net_peers]
    xor     ecx, ecx
.peer:
    cmp     ecx, r10d
    je      .next
    cmp     dword [r11 + PEER.state], PEER_READY
    jne     .next
    movzx   eax, word [r11 + PEER.ps + PSTATE.flags]
    test    eax, PS_DEAD
    jnz     .next
    test    edi, edi
    jz      .ok
    test    eax, PS_STEALTH
    jnz     .next
.ok:
    movss   xmm2, [r11 + PEER.body + BODY.x]
    subss   xmm2, xmm0
    mulss   xmm2, xmm2
    movss   xmm3, [r11 + PEER.body + BODY.z]
    subss   xmm3, xmm1
    mulss   xmm3, xmm3
    addss   xmm2, xmm3
    comiss  xmm2, xmm5
    jae     .next
    movaps  xmm5, xmm2
    lea     r8, [r11 + PEER.body]
    mov     r9d, ecx
.next:
    add     r11, PEER_size
    inc     ecx
    cmp     ecx, NET_MAX_PEERS
    jb      .peer
.done:
    mov     rax, r8
    mov     edx, r9d
    movaps  xmm0, xmm5
    ret

; net_players_raycast(rdi origin float[3], rsi dir float[3], xmm0 max) -> eax the slot of the nearest other player the
; ray meets within max, or -1; xmm0 = its distance t (max on a miss). Another player in the game who lives has a
; box 0.6 wide and 1.8 high on his proxy's feet. -1 while PvP is off.
; r12 = origin, r13 = dir, r14d = slot, ebx = best slot; frame: lo[3] @0, hi[3] @16, best t @32
net_players_raycast:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 48
    mov     r12, rdi
    mov     r13, rsi
    movss   [rsp + 32], xmm0
    mov     ebx, -1
    cmp     byte [net_pvp], 0
    je      .out
    xor     r14d, r14d
.slot:
    mov     edi, r14d
    mov     esi, 1
    call    nm_peer_ok
    test    rax, rax
    jz      .next
    movss   xmm3, [c_pl_hw]
    movss   xmm0, [rax + PEER.body + BODY.x]
    movaps  xmm1, xmm0
    subss   xmm0, xmm3
    addss   xmm1, xmm3
    movss   [rsp], xmm0
    movss   [rsp + 16], xmm1
    movss   xmm0, [rax + PEER.body + BODY.y]
    movss   [rsp + 4], xmm0
    addss   xmm0, [c_pl_h]
    movss   [rsp + 20], xmm0
    movss   xmm0, [rax + PEER.body + BODY.z]
    movaps  xmm1, xmm0
    subss   xmm0, xmm3
    addss   xmm1, xmm3
    movss   [rsp + 8], xmm0
    movss   [rsp + 24], xmm1
    mov     rdi, r12
    mov     rsi, r13
    lea     rdx, [rsp]
    lea     rcx, [rsp + 16]
    movss   xmm0, [rsp + 32]            ; only a hit nearer than the best so far counts
    call    ray_aabb
    test    eax, eax
    jz      .next
    movss   [rsp + 32], xmm0
    mov     ebx, r14d
.next:
    inc     r14d
    cmp     r14d, NET_MAX_PEERS
    jb      .slot
.out:
    movss   xmm0, [rsp + 32]
    mov     eax, ebx
    add     rsp, 48
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ==== what mobs do to a player ===================================================================================

; net_mob_hit_player(rdi mob, esi amount, edx cause, rcx parts int[5] or 0, xmm0 src_x, xmm1 src_z, xmm2 kb,
;                    xmm3 lift) -> eax HIT_*
; A blow of a mob on the player in mob_tgt_slot. The local player takes it through player_take_hit (the callers
; keep their statuses and shoves for HIT_TAKEN). Another player's game decides about its own: the blow goes there as
; a HURT message (net_hurt_send) with the strongest status the mob's affixes add (mob_affix_status over parts)
; and HIT_REMOTE comes back.
; rbx = mob, r12d = amount, r13d = cause, r14 = parts; frame: [rsp] the mob's slot, [rsp+4] the status (255 none),
; [rsp+8] its magnitude, [rsp+12] the affix being looked at
net_mob_hit_player:
    cmp     byte [net_role], NET_ROLE_OFF
    je      .local
    movzx   eax, byte [net_self]
    cmp     [mob_tgt_slot], eax
    je      .local
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 16
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14, rcx
    call    mob_index                   ; eax = the mob's slot (clobbers ecx, edx, rdi)
    mov     [rsp], eax
    mov     dword [rsp + 4], 255
    mov     dword [rsp + 8], 0
    test    r14, r14
    jz      .send
    mov     dword [rsp + 12], 0
.affix:
    mov     rdi, rbx
    mov     rsi, r14
    mov     edx, [rsp + 12]
    call    mob_affix_status            ; eax = STS_* or -1, edx = its magnitude
    test    eax, eax
    js      .send
    cmp     edx, [rsp + 8]
    jle     .affix_next                 ; not stronger than the one chosen
    mov     [rsp + 4], eax
    mov     [rsp + 8], edx
.affix_next:
    inc     dword [rsp + 12]
    jmp     .affix
.send:
    mov     edi, [mob_tgt_slot]
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, [rsp]
    mov     r8d, [rsp + 4]
    mov     r9d, [rsp + 8]
    call    net_hurt_send               ; (xmm0..3 as they came in: source, kb, lift)
    mov     eax, HIT_REMOTE
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
.local:
    mov     edi, esi
    mov     esi, edx
    jmp     player_take_hit             ; (xmm0, xmm1 = the source)

; net_hurt_send(edi slot, esi amount, edx cause, ecx mob or 255, r8d status or 255, r9d status magnitude, xmm0 src_x,
; xmm1 src_z, xmm2 kb, xmm3 lift): the player in that slot is hurt by a mob's blow (HM_HIT: it goes through his
; player_take_hit, then the status and the shove) or, net_hurt_send_direct, by a blast (HM_DIRECT: survival_damage,
; then the shove). HURT: amount i32, cause u8, mob u8, sts u8, mode u8, sts_mag i32, src_ax i32, src_az i32,
; src_fx u16, src_fz u16, kb f32, lift f32. The local player's own slot is served at once.
net_hurt_send:
    mov     eax, HM_HIT
    jmp     hurt_send
net_hurt_send_direct:
    mov     eax, HM_DIRECT
hurt_send:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 48                     ; the payload (32)
    mov     ebx, edi
    mov     [rsp], esi
    mov     [rsp + 4], dl
    mov     [rsp + 5], cl
    mov     [rsp + 6], r8b
    mov     [rsp + 7], al
    mov     [rsp + 8], r9d
    movss   [rsp + 24], xmm2
    movss   [rsp + 28], xmm3
    lea     rdi, [rsp + 12]
    call    src_wire                    ; (xmm0 = x, xmm1 = z)
    movzx   eax, byte [net_self]
    cmp     ebx, eax
    je      .self
    mov     edi, ebx
    mov     esi, MT_HURT
    mov     rdx, rsp
    mov     ecx, NM_HURT_LEN
    mov     r8d, 1
    call    net_send_to
    jmp     .ret
.self:
    mov     rdi, rsp
    call    hurt_apply
.ret:
    add     rsp, 48
    pop     r12
    pop     rbx
    pop     rbp
    ret

; src_wire(rdi out 12 bytes, xmm0 x, xmm1 z): a blow's source on the wire: ax i32, az i32, fx u16, fz u16
src_wire:
    push    rbx
    sub     rsp, 16                     ; an NPOS
    mov     rbx, rdi
    movaps  xmm2, xmm1
    xorps   xmm1, xmm1
    mov     rdi, rsp
    call    net_pos_out
    mov     eax, [rsp + NPOS.ax]
    mov     [rbx], eax
    mov     eax, [rsp + NPOS.az]
    mov     [rbx + 4], eax
    movzx   eax, word [rsp + NPOS.fx]
    mov     [rbx + 8], ax
    movzx   eax, word [rsp + NPOS.fz]
    mov     [rbx + 10], ax
    add     rsp, 16
    pop     rbx
    ret

; src_local(rdi payload) -> xmm0 x, xmm1 z: the source of a blow (the 12 bytes at payload+12, as src_wire writes
; them) in local coordinates
src_local:
    sub     rsp, 24                     ; an NPOS
    mov     eax, [rdi + 12]
    mov     [rsp + NPOS.ax], eax
    mov     eax, [rdi + 16]
    mov     [rsp + NPOS.az], eax
    movzx   eax, word [rdi + 20]
    mov     [rsp + NPOS.fx], ax
    movzx   eax, word [rdi + 22]
    mov     [rsp + NPOS.fz], ax
    mov     dword [rsp + NPOS.y], 0
    mov     rdi, rsp
    call    net_pos_in
    movaps  xmm1, xmm2
    add     rsp, 24
    ret

; clamp_f(xmm0 v, xmm1 limit) -> xmm0 v held to [-limit, limit]; a NaN becomes 0. For everything a peer sends as a float that
; ends up in a body or a damage formula. Clobbers xmm2, xmm3.
clamp_f:
    movaps  xmm2, xmm0
    cmpunordss xmm2, xmm2               ; all ones where v is NaN
    andnps  xmm2, xmm0                  ; NaN -> 0
    minss   xmm2, xmm1
    xorps   xmm3, xmm3
    subss   xmm3, xmm1                  ; -limit
    maxss   xmm2, xmm3
    movaps  xmm0, xmm2
    ret

; shove_player(xmm0 src_x, xmm1 src_z, xmm2 kb, xmm3 lift): the local player is shoved away from (src_x, src_z) at
; kb blocks/s and, standing on the ground, thrown up at lift blocks/s (when that is above 0); combat_kb_mult (0 with
; the Juggernaut keystone) scales both. knock_player's rules for a blow whose source is a point.
; Frame: [rsp] src x, z; [rsp+8] kb, lift; [rsp+16] the multiplier
shove_player:
    sub     rsp, 24
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 12], xmm3            ; (kept: the helper clobbers xmm3)
    movaps  xmm0, xmm2                  ; the shove and the lift are held to +-30 blocks/s: a wild value, NaN too
    movss   xmm1, [c_lim_shove]
    call    clamp_f
    movss   [rsp + 8], xmm0
    movss   xmm0, [rsp + 12]
    movss   xmm1, [c_lim_shove]
    call    clamp_f
    movss   [rsp + 12], xmm0
    call    combat_kb_mult
    movss   [rsp + 16], xmm0
    movss   xmm1, [player + BODY.x]
    subss   xmm1, [rsp]                 ; away from the source
    movss   xmm2, [player + BODY.z]
    subss   xmm2, [rsp + 4]
    movaps  xmm3, xmm1
    mulss   xmm3, xmm3
    movaps  xmm4, xmm2
    mulss   xmm4, xmm4
    addss   xmm3, xmm4
    sqrtss  xmm3, xmm3
    comiss  xmm3, [c_tiny]
    jb      .lift                       ; standing on the source: no direction
    movss   xmm4, [rsp + 8]
    mulss   xmm4, [rsp + 16]
    divss   xmm4, xmm3
    mulss   xmm1, xmm4
    movss   [player + BODY.kbx], xmm1
    mulss   xmm2, xmm4
    movss   [player + BODY.kbz], xmm2
.lift:
    cmp     dword [player + BODY.on_ground], 0
    je      .done
    movss   xmm0, [rsp + 12]
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jbe     .done
    mulss   xmm0, [rsp + 16]
    movss   [player + BODY.vy], xmm0
.done:
    add     rsp, 24
    ret

; hurt_apply(rdi payload): this game's player takes the blow of a HURT message (see net_hurt_send). HM_HIT: the
; blow goes through player_take_hit with combat_attacker naming the mob (thorns); once it lands (HIT_TAKEN) the status
; comes on (combat_player_status) and the shove (shove_player: along source -> player, kb blocks/s, and lift);
; a parried blow stuns the mob that struck (mob_set_stun: back to the host). HM_DIRECT: survival_damage, then the shove.
; rbx = payload; frame: [rsp] src x, z
hurt_apply:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    mov     rbx, rdi
    call    src_local
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    mov     edi, [rbx]
    movzx   esi, byte [rbx + 4]
    cmp     byte [rbx + 7], HM_DIRECT
    je      .direct
    movzx   eax, byte [rbx + 5]
    mov     ecx, -1
    cmp     eax, 255
    cmovne  ecx, eax
    mov     [combat_attacker], ecx
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    call    player_take_hit
    mov     dword [combat_attacker], -1
    cmp     eax, HIT_TAKEN
    je      .taken
    cmp     eax, HIT_PARRIED
    jne     .done
    movzx   edi, byte [rbx + 5]         ; the mob that struck (255: none)
    cmp     edi, MAX_MOBS
    jae     .done
    imul    eax, edi, MOB_size
    lea     r12, [mobs]
    add     r12, rax                    ; its record (a guest's own copy of it)
    cmp     dword [r12 + MOB.type], MOB_NONE
    je      .done
    mov     esi, STUN_PARRIED
    cmp     byte [rbx + 4], CAUSE_BOSS
    jne     .riposte
    mov     esi, NM_BOSS_STUN           ; the Fallen King's slam stuns him whatever he is ...
    jmp     .stun
.riposte:
    test    dword [r12 + MOB.affix], AFX_JUGGERNAUT
    jnz     .done                       ; ... the others' riposte a juggernaut shrugs off
.stun:
    call    mob_set_stun                ; (a guest asks the host)
    mov     rdi, r12
    call    mob_stunned_text
    jmp     .done
.direct:
    call    survival_damage
    test    eax, eax
    jz      .done
.taken:
    movzx   edi, byte [rbx + 6]
    cmp     edi, 255
    je      .shove
    mov     esi, [rbx + 8]
    call    combat_player_status
.shove:
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rbx + 24]
    movss   xmm3, [rbx + 28]
    call    shove_player
.done:
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; nm_on_hurt(edi from, esi type, rdx payload, ecx len): HURT, host -> guest: a blow on this game's player
nm_on_hurt:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    cmp     ecx, NM_HURT_LEN
    jb      .ret
    mov     rdi, rdx
    jmp     hurt_apply
.ret:
    ret

; pvp_apply(rdi payload): this game's player takes the blow of another player (PVP_HIT: victim u8, attacker u8, sts u8,
; pad u8, amount i32, sts_mag i32, src_ax i32, src_az i32, src_fx u16, src_fz u16, kb f32): player_take_hit as
; CAUSE_PLAYER (no thorns: combat_attacker stays -1), then the status and the shove (no lift)
; rbx = payload; frame: [rsp] src x, z
pvp_apply:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 24
    mov     rbx, rdi
    call    src_local
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    mov     dword [combat_attacker], -1
    mov     edi, [rbx + 4]
    mov     esi, CAUSE_PLAYER
    call    player_take_hit
    cmp     eax, HIT_TAKEN
    jne     .done
    movzx   edi, byte [rbx + 2]
    cmp     edi, 255
    je      .shove
    mov     esi, [rbx + 8]
    call    combat_player_status
.shove:
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rbx + 24]
    xorps   xmm3, xmm3
    call    shove_player
.done:
    add     rsp, 24
    pop     rbx
    pop     rbp
    ret

; nm_on_pvp_hit(edi from, esi type, rdx payload, ecx len): PVP_HIT. At the host, from a guest: the attacker is the sender
; (the host writes it in), the blow must be PvP-on, between two other players; the host's own player takes it here,
; any other victim gets it relayed. At a guest the message comes from the host and is for this game's player.
; rbx = the victim, r12d = the sender; frame: [rsp] a copy of the payload (28)
nm_on_pvp_hit:
    cmp     ecx, NM_PVP_LEN
    jb      .ret0
    cmp     byte [net_pvp], 0
    je      .ret0
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 32
    mov     r12d, edi
    mov     rax, [rdx]
    mov     [rsp], rax
    mov     rax, [rdx + 8]
    mov     [rsp + 8], rax
    mov     rax, [rdx + 16]
    mov     [rsp + 16], rax
    mov     eax, [rdx + 24]
    mov     [rsp + 24], eax
    mov     eax, [rsp + 4]              ; the damage: at least 1 and no absurd number
    cmp     eax, 1
    jl      .done
    cmp     eax, NM_DAMAGE_MAX
    jg      .done
    movzx   ebx, byte [rsp]
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .guest
    mov     [rsp + 1], r12b             ; the attacker is whoever sent it
    cmp     ebx, r12d
    je      .done                       ; (not himself)
    movzx   eax, byte [net_self]
    cmp     ebx, eax
    je      .apply
    mov     edi, ebx
    mov     esi, 1
    call    nm_peer_ok
    test    rax, rax
    jz      .done
    mov     edi, ebx
    mov     esi, MT_PVP_HIT
    mov     rdx, rsp
    mov     ecx, NM_PVP_LEN
    mov     r8d, 1
    call    net_send_to
    jmp     .done
.guest:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .done
    movzx   eax, byte [net_self]
    cmp     ebx, eax
    jne     .done
.apply:
    mov     rdi, rsp
    call    pvp_apply
.done:
    add     rsp, 32
    pop     r12
    pop     rbx
    pop     rbp
.ret0:
    ret

; net_kill_credit(edi slot, esi type, edx elite, ecx level, r8d mob): the player in that slot killed the mob in table slot `mob`, of
; that type, elite state and level: he gets the XP (a KILL message; his own game when the slot is this game's). Host.
; KILL: type u8, elite u8, mob slot + 1 u16, level i32. The slot tells the killer's game which of the mobs it hit died
; (combat_fang_kill: a Shadow Fang backstab kill resets Shadowstep, which a guest cannot see happen: its copy of the mob lives on
; until the next snapshot).
net_kill_credit:
    movzx   eax, byte [net_self]
    cmp     edi, eax
    je      .self
    sub     rsp, 24
    mov     [rsp], sil
    test    edx, edx
    setnz   al
    mov     [rsp + 1], al
    inc     r8d
    mov     [rsp + 2], r8w
    mov     [rsp + 4], ecx
    mov     rdx, rsp
    mov     ecx, NM_KILL_LEN
    mov     esi, MT_KILL
    mov     r8d, 1
    call    net_send_to
    add     rsp, 24
    ret
.self:
    mov     eax, esi
    mov     esi, edx
    mov     edx, ecx
    mov     edi, eax
    jmp     rpg_on_mob_killed

; nm_on_kill(edi from, esi type, rdx payload, ecx len): KILL, host -> guest: a mob this player killed died: the XP, the quest
; count and the rest of rpg_on_mob_killed's rewards (the host's mob_damage is where the mob died). KILL: type u8, elite u8,
; mob slot + 1 u16, level i32. A KILL grants XP and quest progress, so only a guest takes one, and only from the host (a
; guest's one connection is slot 0): the host and a guest that hears it from elsewhere ignore it. A type no mob has is
; ignored, the level is held to 1..1000, and the slot goes to combat_fang_kill.
nm_on_kill:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    test    edi, edi
    jnz     .ret
    cmp     ecx, NM_KILL_LEN
    jb      .ret
    movzx   eax, byte [rdx]
    lea     ecx, [rax - 1]
    cmp     ecx, NUM_MOB_TYPES - 1
    ja      .ret
    push    rbx
    mov     rbx, rdx
    movzx   edi, word [rbx + 2]
    call    combat_fang_kill
    movzx   edi, byte [rbx]
    cmp     byte [rbx + 1], 0
    setne   al
    movzx   esi, al
    mov     edx, [rbx + 4]
    mov     eax, 1
    cmp     edx, eax
    cmovl   edx, eax
    mov     eax, 1000
    cmp     edx, eax
    cmovg   edx, eax
    pop     rbx
    jmp     rpg_on_mob_killed
.ret:
    ret

; ==== what a guest does to mobs =====================================================================================

; net_mob_damage_out(edi idx, esi dmg, edx strike, xmm0 dirx, xmm1 dirz) -> eax 1 (mob_damage's entry on a guest)
; The guest asks the host to hurt the mob (HIT: slot u8, strike u8, flags u8 = combat_hit_flags, type u8, dmg i32,
; dirx f32, dirz f32) and shows the number over its head at once (and the bar, for a blow that is not a damage tick):
; nothing else changes, the health and the kill are the host's. combat_hit_flags is spent. 0 for an empty slot.
; rbx = the mob, r12d = the damage; frame: [rsp] the payload (16)
net_mob_damage_out:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 32
    cmp     edi, MAX_MOBS
    jae     .none
    imul    ebx, edi, MOB_size
    lea     rax, [mobs]
    add     rbx, rax
    mov     eax, [rbx + MOB.type]
    test    eax, eax
    jz      .none
    mov     r12d, esi
    mov     [rsp], dil
    mov     [rsp + 1], dl
    mov     ecx, [combat_hit_flags]
    mov     [rsp + 2], cl
    mov     [rsp + 3], al
    mov     [rsp + 4], esi
    movss   [rsp + 8], xmm0
    movss   [rsp + 12], xmm1
    mov     edi, MT_HIT
    mov     rsi, rsp
    mov     edx, NM_HIT_LEN
    mov     ecx, 1
    call    net_out
    movss   xmm0, [rbx + BODY.x]        ; the number floats up from above the head, as mob_damage's
    movss   xmm1, [rbx + BODY.height]
    minss   xmm1, [c_two]
    addss   xmm1, [rbx + BODY.y]
    addss   xmm1, [c_over_head]
    movss   xmm2, [rbx + BODY.z]
    mov     edi, r12d
    movzx   esi, byte [combat_hit_flags]
    and     esi, HF_CRIT | HF_DOT | HF_ELEM_MASK
    call    dmgnum_spawn
    movzx   eax, byte [combat_hit_flags]
    test    eax, HF_PLAYER
    jz      .yes
    test    eax, HF_DOT
    jnz     .yes
    mov     dword [rbx + MOB.bar], NM_BAR_STEPS
.yes:
    mov     byte [combat_hit_flags], 0
    mov     eax, 1
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    add     rsp, 32
    pop     r12
    pop     rbx
    pop     rbp
    ret

; net_status_out(edi idx, esi kind, xmm0 mag, edx dot_stat, ecx viper): the guest asks the host to put a status on the mob
; with this player's DOT_DMG and Viper amulet (STATUS: slot u8, kind u8, viper u8, type u8, mag f32, dot_stat i32)
net_status_out:
    cmp     edi, MAX_MOBS
    jae     .ret
    imul    eax, edi, MOB_size
    lea     r8, [mobs]
    mov     eax, [r8 + rax + MOB.type]
    test    eax, eax
    jz      .ret
    sub     rsp, 24
    mov     [rsp], dil
    mov     [rsp + 1], sil
    mov     [rsp + 2], cl
    mov     [rsp + 3], al
    movss   [rsp + 4], xmm0
    mov     [rsp + 8], edx
    mov     edi, MT_STATUS
    mov     rsi, rsp
    mov     edx, NM_STATUS_LEN
    mov     ecx, 1
    call    net_out
    add     rsp, 24
.ret:
    ret

; net_mobfx_out(edi idx, esi kind, edx ivalue, xmm0 fvalue): the guest asks the host for a stun or a mark of ivalue steps
; (MFX_STUN, MFX_MARK) or a launch at fvalue blocks/s (MFX_LAUNCH). MOBFX: slot u8, kind u8, type u8, pad u8, value
net_mobfx_out:
    cmp     edi, MAX_MOBS
    jae     .ret
    imul    eax, edi, MOB_size
    lea     r8, [mobs]
    mov     eax, [r8 + rax + MOB.type]
    test    eax, eax
    jz      .ret
    sub     rsp, 24
    mov     [rsp], dil
    mov     [rsp + 1], sil
    mov     [rsp + 2], al
    mov     byte [rsp + 3], 0
    cmp     esi, MFX_LAUNCH
    jne     .int
    movd    edx, xmm0
.int:
    mov     [rsp + 4], edx
    mov     edi, MT_MOBFX
    mov     rsi, rsp
    mov     edx, NM_MOBFX_LEN
    mov     ecx, 1
    call    net_out
    add     rsp, 24
.ret:
    ret

; net_interact_out(edi idx, esi action): the guest asks the host for something to do with the mob (INTERACT: slot u8, action
; u8 = IA_*, type u8, pad u8)
net_interact_out:
    cmp     edi, MAX_MOBS
    jae     .ret
    imul    eax, edi, MOB_size
    lea     r8, [mobs]
    mov     eax, [r8 + rax + MOB.type]
    test    eax, eax
    jz      .ret
    sub     rsp, 24
    mov     [rsp], dil
    mov     [rsp + 1], sil
    mov     [rsp + 2], al
    mov     byte [rsp + 3], 0
    mov     edi, MT_INTERACT
    mov     rsi, rsp
    mov     edx, NM_INTERACT_LEN
    mov     ecx, 1
    call    net_out
    add     rsp, 24
.ret:
    ret

; ==== what the host does for a guest ================================================================================

; nm_on_hit(edi from, esi type, rdx payload, ecx len): HIT, guest -> host: the guest's blow on a mob. Ignored unless
; the slot still holds a mob of the type the guest saw. The blow is applied as that guest's (net_hit_peer: the XP of
; the kill is his, folk turn on him) with the flags it came with: mob_strike (inside the hurt window too) or mob_hurt.
nm_on_hit:
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret0
    cmp     ecx, NM_HIT_LEN
    jb      .ret0
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    mov     rbx, rdx
    mov     r12d, edi
    movzx   eax, byte [rbx]
    cmp     eax, MAX_MOBS
    jae     .done
    movzx   ecx, byte [rbx + 3]
    test    ecx, ecx
    jz      .done
    imul    edx, eax, MOB_size
    lea     rsi, [mobs]
    cmp     [rsi + rdx + MOB.type], ecx
    jne     .done
    mov     esi, [rbx + 4]
    cmp     esi, 1
    jl      .done
    cmp     esi, NM_DAMAGE_MAX
    jg      .done
    mov     byte [net_applying], 1
    mov     [net_hit_peer], r12d
    movzx   edx, byte [rbx + 2]
    mov     [combat_hit_flags], edx
    movzx   edi, byte [rbx]
    movss   xmm0, [rbx + 8]
    movss   xmm1, [c_lim_dir]
    call    clamp_f                     ; the knockback direction is held to +-10: a wild value, NaN too
    movss   [rsp], xmm0
    movss   xmm0, [rbx + 12]
    movss   xmm1, [c_lim_dir]
    call    clamp_f
    movaps  xmm1, xmm0
    movss   xmm0, [rsp]
    cmp     byte [rbx + 1], 0
    jne     .strike
    call    mob_hurt
    jmp     .applied
.strike:
    call    mob_strike
.applied:
    mov     dword [net_hit_peer], 0
    mov     byte [net_applying], 0
.done:
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
.ret0:
    ret

; nm_on_status(edi from, esi type, rdx payload, ecx len): STATUS, guest -> host: status_apply_ex with the guest's stats on the
; mob (when the slot still holds the type the guest saw); the mob is the guest's from then on (a tick that kills it pays him)
nm_on_status:
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret0
    cmp     ecx, NM_STATUS_LEN
    jb      .ret0
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     rbx, rdx
    mov     r12d, edi
    movzx   eax, byte [rbx]
    cmp     eax, MAX_MOBS
    jae     .done
    movzx   ecx, byte [rbx + 3]
    test    ecx, ecx
    jz      .done
    imul    edx, eax, MOB_size
    lea     rsi, [mobs]
    cmp     [rsi + rdx + MOB.type], ecx
    jne     .done
    movzx   edi, byte [rbx]
    movzx   esi, byte [rbx + 1]
    movss   xmm0, [rbx + 4]
    movss   xmm1, [c_lim_mag]
    call    clamp_f                     ; the magnitude and the applier's DOT_DMG are held to sane values
    mov     edx, [rbx + 8]
    CLAMP   edx, 10000
    movzx   ecx, byte [rbx + 2]
    call    status_apply_ex
    movzx   eax, byte [rbx]
    imul    edx, eax, MOB_size
    lea     rsi, [mobs]
    mov     [rsi + rdx + MOB.peer], r12d
.done:
    pop     r12
    pop     rbx
    pop     rbp
.ret0:
    ret

; nm_on_mobfx(edi from, esi type, rdx payload, ecx len): MOBFX, guest -> host: a stun, a mark or a launch of the mob (when the
; slot still holds the type the guest saw)
nm_on_mobfx:
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret0
    cmp     ecx, NM_MOBFX_LEN
    jb      .ret0
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdx
    movzx   eax, byte [rbx]
    cmp     eax, MAX_MOBS
    jae     .done
    movzx   ecx, byte [rbx + 2]
    test    ecx, ecx
    jz      .done
    imul    edx, eax, MOB_size
    lea     rsi, [mobs]
    cmp     [rsi + rdx + MOB.type], ecx
    jne     .done
    movzx   edi, byte [rbx]
    movzx   eax, byte [rbx + 1]
    cmp     eax, MFX_LAUNCH
    je      .launch
    mov     esi, [rbx + 4]
    CLAMP   esi, NM_FX_MAX
    cmp     eax, MFX_STUN
    je      .stun
    cmp     eax, MFX_MARK
    jne     .done
    call    mob_set_mark
    jmp     .done
.stun:
    call    mob_set_stun
    jmp     .done
.launch:
    movss   xmm0, [rbx + 4]
    movss   xmm1, [c_lim_vy]
    call    clamp_f                     ; a wild launch, NaN too, is held to +-100 blocks/s
    call    mob_launch
.done:
    add     rsp, 8
    pop     rbx
    pop     rbp
.ret0:
    ret

; nm_on_interact(edi from, esi type, rdx payload, ecx len): INTERACT, guest -> host: IA_FREE_CAPTIVE frees the captive folk in
; that slot (folk_free_captive: the standing and the camp's record), when it is still one; IA_EVENT_ACCEPT accepts the event
; that folk offers (events_accept, which checks the offer itself)
nm_on_interact:
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    cmp     ecx, NM_INTERACT_LEN
    jb      .ret
    cmp     byte [rdx + 1], IA_EVENT_ACCEPT
    je      .slot
    cmp     byte [rdx + 1], IA_FREE_CAPTIVE
    jne     .ret
.slot:
    movzx   edi, byte [rdx]
    cmp     edi, MAX_MOBS
    jae     .ret
    cmp     byte [rdx + 2], MOB_FOLK
    jne     .ret
    imul    eax, edi, MOB_size
    lea     rcx, [mobs]
    cmp     dword [rcx + rax + MOB.type], MOB_FOLK
    jne     .ret
    cmp     byte [rdx + 1], IA_EVENT_ACCEPT
    je      events_accept
    jmp     folk_free_captive
.ret:
    ret

; ==== snapshots: the host's side =====================================================================================

; fill_mrec(rdi mob, rsi MOBREC*, edx idx): the wire record of a mob
fill_mrec:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    mov     rbx, rdi
    mov     r12, rsi
    mov     [r12 + MOBREC.slot], dl
    mov     eax, [rbx + MOB.type]
    mov     [r12 + MOBREC.type], al
    mov     al, [rbx + MOB.faction]
    mov     [r12 + MOBREC.faction], al
    mov     al, [rbx + MOB.role]
    mov     [r12 + MOBREC.role], al
    mov     al, [rbx + MOB.fclass]
    mov     [r12 + MOBREC.fclass], al
    mov     al, [rbx + MOB.fflags]
    mov     [r12 + MOBREC.fflags], al
    mov     al, [rbx + MOB.wid]
    mov     [r12 + MOBREC.wid], al
    xor     ecx, ecx                    ; vis
    cmp     dword [rbx + MOB.elite], 0
    je      .v_hurt
    or      ecx, VIS_ELITE
.v_hurt:
    cmp     dword [rbx + MOB.hurt], 0
    jle     .v_burn
    or      ecx, VIS_HURT
.v_burn:
    cmp     dword [rbx + MOB.burn_t], 0
    jle     .v_poison
    or      ecx, VIS_BURN
.v_poison:
    cmp     dword [rbx + MOB.poison_t], 0
    jle     .v_chill
    or      ecx, VIS_POISON
.v_chill:
    cmp     dword [rbx + MOB.chill_t], 0
    jle     .v_frozen
    or      ecx, VIS_CHILL
.v_frozen:
    cmp     dword [rbx + MOB.chill], 2
    jl      .v_windup
    or      ecx, VIS_FROZEN
.v_windup:
    cmp     dword [rbx + MOB.windup], 0
    jle     .v_bar
    or      ecx, VIS_WINDUP
.v_bar:
    cmp     dword [rbx + MOB.bar], 0
    jle     .v_done
    or      ecx, VIS_BAR
.v_done:
    mov     [r12 + MOBREC.vis], cl
    lea     rdi, [r12 + MOBREC.pos]
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    call    net_pos_out
    mov     eax, [rbx + BODY.yaw]
    mov     [r12 + MOBREC.yaw], eax
    mov     eax, [rbx + MOB.health]
    mov     [r12 + MOBREC.health], eax
    mov     eax, [rbx + MOB.max_health]
    mov     [r12 + MOBREC.max_health], eax
    mov     eax, [rbx + MOB.level]
    CLAMP   eax, 0xFFFF
    mov     [r12 + MOBREC.level], ax
    mov     eax, [rbx + MOB.stun]
    CLAMP   eax, 255
    mov     [r12 + MOBREC.stun], al
    mov     eax, [rbx + MOB.peer]
    mov     [r12 + MOBREC.peer], al
    movzx   eax, byte [rbx + MOB.affix] ; .mag
    mov     ecx, [rbx + MOB.shock]
    and     ecx, 3
    shl     ecx, MG_SHOCK_SHIFT
    or      eax, ecx
    cmp     dword [rbx + MOB.mark_t], 0
    jle     .m_bleed
    or      eax, MG_MARK
.m_bleed:
    cmp     dword [rbx + MOB.bleed_t], 0
    jle     .m_windup
    or      eax, MG_BLEED
.m_windup:
    mov     ecx, [rbx + MOB.windup]
    CLAMP   ecx, 63
    shl     ecx, MG_WINDUP_SHIFT
    or      eax, ecx
    mov     ecx, [rbx + MOB.burn_t]
    CLAMP   ecx, 255
    shl     ecx, MG_BURN_SHIFT
    or      eax, ecx
    cmp     dword [rbx + MOB.freeze_cd], 0
    jle     .m_captor
    or      eax, MG_FREEZE
.m_captor:
    movzx   ecx, byte [rbx + MOB.captor]
    and     ecx, 7
    shl     ecx, MG_CAPTOR_SHIFT
    or      eax, ecx
    cmp     dword [rbx + MOB.target], 1
    jne     .m_prov
    or      eax, MG_TARGET
.m_prov:
    cmp     dword [rbx + MOB.provoked], 0
    jle     .m_done
    or      eax, MG_PROVOKED
.m_done:
    mov     [r12 + MOBREC.mag], eax
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; snap_mobs_flush(): (ebx = the guest's slot) sends the SNAP_MOBS message holding the nm_cnt records collected so far
; and starts the next one
snap_mobs_flush:
    sub     rsp, 8
    mov     eax, [nm_cnt]
    mov     [nm_buf + 12], al
    imul    ecx, eax, MOBREC_size
    add     ecx, 16
    mov     edi, ebx
    mov     esi, MT_SNAP_MOBS
    lea     rdx, [nm_buf]
    xor     r8d, r8d
    call    net_send_to
    mov     dword [nm_cnt], 0
    inc     dword [nm_sent]
    add     rsp, 8
    ret

; snap_drops_flush(): the same for SNAP_DROPS
snap_drops_flush:
    sub     rsp, 8
    mov     eax, [nm_cnt]
    mov     [nm_buf + 8], al
    imul    ecx, eax, DROPREC_size
    add     ecx, 16
    mov     edi, ebx
    mov     esi, MT_SNAP_DROPS
    lea     rdx, [nm_buf]
    xor     r8d, r8d
    call    net_send_to
    mov     dword [nm_cnt], 0
    inc     dword [nm_sent]
    add     rsp, 8
    ret

; nm_snap_send(edi slot): one snapshot for the guest in that slot (host, called every SNAP_STEPS steps for each READY
; guest): SNAP_MOBS (time u32, mask u64 of the slots included, count u8, pad[3], MOBREC x count; at most 24 a message,
; every message repeating the whole mask; at least one message, for the time), SNAP_DROPS (mask u64, count u8,
; pad[7], DROPREC x count; at most 45; at least one message, so that a table that emptied empties on the guest; slot
; MAX_DROPS - 1 is the guest's own staging slot for its tosses and never goes into a snapshot, whatever lies in the host's) and
; SNAP_MISC (boat_mask u16, nboats u8, ntnt u8, BOATREC x nboats, TNTREC x ntnt). Mobs within 96 blocks of the
; guest's proxy are included, drops within 48, boats within 96, primed TNT within 64.
; ebx = slot, r12 = the guest's PEER (then a table counter), r13d = the table index, r14 = its entry, r15 = the mask;
; frame: [rsp] the guest's x, z, [rsp+8] the boats sent
nm_snap_send:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     ebx, edi
    xor     esi, esi
    call    nm_peer_ok
    test    rax, rax
    jz      .ret
    mov     r12, rax
    mov     eax, [r12 + PEER.body + BODY.x]
    mov     [rsp], eax
    mov     eax, [r12 + PEER.body + BODY.z]
    mov     [rsp + 4], eax
    ; ---- mobs
    xor     r15d, r15d
    xor     r13d, r13d
    lea     r14, [mobs]
.scan:
    cmp     dword [r14 + MOB.type], MOB_NONE
    je      .scan_next
    movss   xmm0, [r14 + BODY.x]
    subss   xmm0, [rsp]
    mulss   xmm0, xmm0
    movss   xmm1, [r14 + BODY.z]
    subss   xmm1, [rsp + 4]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [c_96sq]
    ja      .scan_next
    bts     r15, r13
.scan_next:
    add     r14, MOB_size
    inc     r13d
    cmp     r13d, MAX_MOBS
    jb      .scan
    mov     eax, [game_time]
    mov     [nm_buf], eax
    mov     [nm_buf + 4], r15
    mov     dword [nm_buf + 12], 0
    mov     dword [nm_cnt], 0
    mov     dword [nm_sent], 0
    xor     r13d, r13d
    lea     r14, [mobs]
.mob:
    bt      r15, r13
    jnc     .mob_next
    mov     eax, [nm_cnt]
    imul    eax, eax, MOBREC_size
    lea     rsi, [nm_buf + 16]
    add     rsi, rax
    mov     rdi, r14
    mov     edx, r13d
    call    fill_mrec
    inc     dword [nm_cnt]
    cmp     dword [nm_cnt], NM_MOBS_PER_MSG
    jb      .mob_next
    call    snap_mobs_flush
.mob_next:
    add     r14, MOB_size
    inc     r13d
    cmp     r13d, MAX_MOBS
    jb      .mob
    cmp     dword [nm_cnt], 0
    jne     .mob_last
    cmp     dword [nm_sent], 0
    jne     .drops
.mob_last:
    call    snap_mobs_flush
    ; ---- drops
.drops:
    xor     r15d, r15d
    xor     r13d, r13d
    lea     r14, [drops]
.d_scan:
    cmp     byte [r14 + DROP.id], 0
    je      .d_scan_next
    movss   xmm0, [r14 + DROP.x]
    subss   xmm0, [rsp]
    mulss   xmm0, xmm0
    movss   xmm1, [r14 + DROP.z]
    subss   xmm1, [rsp + 4]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [c_48sq]
    ja      .d_scan_next
    bts     r15, r13
.d_scan_next:
    add     r14, DROP_size
    inc     r13d
    cmp     r13d, MAX_DROPS - 1
    jb      .d_scan
    mov     [nm_buf], r15
    mov     qword [nm_buf + 8], 0
    mov     dword [nm_cnt], 0
    mov     dword [nm_sent], 0
    xor     r13d, r13d
    lea     r14, [drops]
.drop:
    bt      r15, r13
    jnc     .drop_next
    mov     eax, [nm_cnt]
    imul    eax, eax, DROPREC_size
    lea     r12, [nm_buf + 16]
    add     r12, rax                    ; the record
    mov     [r12 + DROPREC.slot], r13b
    movzx   edi, byte [r14 + DROP.id]
    mov     [r12 + DROPREC.id], dil
    mov     al, [r14 + DROP.count]
    mov     [r12 + DROPREC.count], al
    movzx   esi, word [r14 + DROP.dmg]
    mov     [r12 + DROPREC.dmg], si
    mov     word [r12 + DROPREC.pad], 0
    call    gear_rarity                 ; (the receivers work it out again when they draw the beams)
    mov     [r12 + DROPREC.rar], al
    lea     rdi, [r12 + DROPREC.pos]
    movss   xmm0, [r14 + DROP.x]
    movss   xmm1, [r14 + DROP.y]
    movss   xmm2, [r14 + DROP.z]
    call    net_pos_out
    inc     dword [nm_cnt]
    cmp     dword [nm_cnt], NM_DROPS_PER_MSG
    jb      .drop_next
    call    snap_drops_flush
.drop_next:
    add     r14, DROP_size
    inc     r13d
    cmp     r13d, MAX_DROPS - 1
    jb      .drop
    cmp     dword [nm_cnt], 0
    jne     .drop_last
    cmp     dword [nm_sent], 0
    jne     .misc
.drop_last:
    call    snap_drops_flush
    ; ---- boats and primed TNT
.misc:
    xor     r15d, r15d                  ; the boats' mask
    xor     r13d, r13d                  ; boats in the message
    lea     r14, [boats]
    xor     r12d, r12d                  ; the boat's slot
.boat:
    cmp     dword [r14 + BOATENT.used], 0
    je      .boat_next
    movss   xmm0, [r14 + BODY.x]
    subss   xmm0, [rsp]
    mulss   xmm0, xmm0
    movss   xmm1, [r14 + BODY.z]
    subss   xmm1, [rsp + 4]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [c_96sq]
    ja      .boat_next
    bts     r15, r12
    imul    eax, r13d, BOATREC_size
    lea     rsi, [nm_buf + 4]
    add     rsi, rax
    mov     [rsi + BOATREC.slot], r12b
    lea     rax, [boat_rider]           ; the rider: peer slot + 1 of a remote one, 1 when the host itself rides it
    movzx   eax, byte [rax + r12]
    test    eax, eax
    jnz     .rider_set
    lea     ecx, [r12 + 1]
    cmp     ecx, [boat_riding]
    jne     .rider_set
    mov     eax, 1
.rider_set:
    mov     [rsi + BOATREC.rider], al
    mov     word [rsi + BOATREC.pad], 0
    mov     eax, [r14 + BODY.yaw]
    mov     [rsi + BOATREC.yaw], eax
    lea     rdi, [rsi + BOATREC.pos]
    movss   xmm0, [r14 + BODY.x]
    movss   xmm1, [r14 + BODY.y]
    movss   xmm2, [r14 + BODY.z]
    call    net_pos_out
    inc     r13d
.boat_next:
    add     r14, BOATENT_size
    inc     r12d
    cmp     r12d, MAX_BOATS
    jb      .boat
    mov     [nm_buf], r15w              ; boat_mask u16
    mov     [nm_buf + 2], r13b          ; nboats
    mov     [rsp + 8], r13d
    imul    eax, r13d, BOATREC_size
    lea     r13, [nm_buf + 4]
    add     r13, rax                    ; where the TNT records go
    xor     r15d, r15d                  ; primed TNT in the message
    lea     r14, [primed]
    xor     r12d, r12d
.tnt:
    cmp     dword [r14 + PRIMED.fuse], 0
    je      .tnt_next
    movss   xmm0, [r14 + PRIMED.body + BODY.x]
    subss   xmm0, [rsp]
    mulss   xmm0, xmm0
    movss   xmm1, [r14 + PRIMED.body + BODY.z]
    subss   xmm1, [rsp + 4]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [c_64sq]
    ja      .tnt_next
    imul    eax, r15d, TNTREC_size
    lea     rsi, [r13 + rax]
    mov     eax, [r14 + PRIMED.fuse]
    mov     [rsi + TNTREC.fuse], ax
    mov     word [rsi + TNTREC.pad], 0
    lea     rdi, [rsi + TNTREC.pos]
    movss   xmm0, [r14 + PRIMED.body + BODY.x]
    movss   xmm1, [r14 + PRIMED.body + BODY.y]
    movss   xmm2, [r14 + PRIMED.body + BODY.z]
    call    net_pos_out
    inc     r15d
.tnt_next:
    add     r14, PRIMED_size
    inc     r12d
    cmp     r12d, MAX_PRIMED
    jb      .tnt
    mov     [nm_buf + 3], r15b          ; ntnt
    imul    eax, r15d, TNTREC_size
    mov     edx, [rsp + 8]
    imul    edx, edx, BOATREC_size
    lea     ecx, [rdx + rax + 4]        ; the length
    mov     edi, ebx
    mov     esi, MT_SNAP_MISC
    lea     rdx, [nm_buf]
    xor     r8d, r8d
    call    net_send_to
.ret:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ==== snapshots: the guest's side ====================================================================================

; apply_mrec(rdi MOBREC*): a guest writes one mob record of a snapshot into its mob table: the slot is (re)created when it
; holds no mob of that type, the flags of .vis and the packed .mag become the fields the renderer, the plates and the damage
; pipeline read, and the position and heading become the copy's target (nm_tgt: a new copy starts on it)
; rbx = the mob, r12 = the record, r13d = the slot; edx = .mag, eax = .vis; frame: [rsp] 1 for a new copy
apply_mrec:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     r12, rdi
    movzx   r13d, byte [r12 + MOBREC.slot]
    cmp     r13d, MAX_MOBS
    jae     .ret
    movzx   ecx, byte [r12 + MOBREC.type]
    lea     eax, [rcx - 1]
    cmp     eax, NUM_MOB_TYPES - 1
    ja      .ret                        ; not a mob type
    imul    ebx, r13d, MOB_size
    lea     rax, [mobs]
    add     rbx, rax
    mov     dword [rsp], 0
    cmp     [rbx + MOB.type], ecx
    je      .have
    mov     rdi, rbx
    mov     esi, ecx
    call    mob_replica_init
    mov     dword [rsp], 1
.have:
    xor     ecx, ecx
    movzx   eax, byte [r12 + MOBREC.faction]
    cmp     eax, NUM_FACTIONS
    cmovae  eax, ecx                    ; (a value no table has a row for is held to the first)
    mov     [rbx + MOB.faction], al
    movzx   eax, byte [r12 + MOBREC.role]
    cmp     eax, NUM_ROLES
    cmovae  eax, ecx
    mov     [rbx + MOB.role], al
    movzx   eax, byte [r12 + MOBREC.fclass]
    cmp     eax, NUM_FCLASSES
    cmovae  eax, ecx
    mov     [rbx + MOB.fclass], al
    mov     al, [r12 + MOBREC.fflags]
    mov     [rbx + MOB.fflags], al
    movzx   eax, byte [r12 + MOBREC.wid]
    cmp     eax, NUM_ITEMS
    cmovae  eax, ecx
    mov     [rbx + MOB.wid], al
    mov     ecx, [r12 + MOBREC.max_health]        ; a health bar divides by the maximum: at least 1, the health within it
    mov     edx, 1
    cmp     ecx, edx
    cmovl   ecx, edx
    mov     [rbx + MOB.max_health], ecx
    mov     edx, [r12 + MOBREC.health]
    xor     eax, eax
    test    edx, edx
    cmovs   edx, eax
    cmp     edx, ecx
    cmovg   edx, ecx
    mov     [rbx + MOB.health], edx
    movzx   ecx, word [r12 + MOBREC.level]
    mov     [rbx + MOB.level], ecx
    movzx   ecx, byte [r12 + MOBREC.stun]
    mov     [rbx + MOB.stun], ecx
    movzx   ecx, byte [r12 + MOBREC.peer]
    mov     [rbx + MOB.peer], ecx
    movzx   eax, byte [r12 + MOBREC.vis]
    mov     edx, [r12 + MOBREC.mag]
    mov     ecx, eax
    and     ecx, VIS_ELITE
    mov     [rbx + MOB.elite], ecx
    test    al, VIS_HURT                ; hurt: the red tint for a few steps, once
    jz      .burn
    cmp     dword [rbx + MOB.hurt], 0
    jg      .burn
    mov     dword [rbx + MOB.hurt], NM_HURT_STEPS
.burn:
    xor     ecx, ecx                    ; burning: the steps left it flickers by
    test    al, VIS_BURN
    jz      .burn_set
    mov     ecx, edx
    shr     ecx, MG_BURN_SHIFT
    and     ecx, 255
    mov     r8d, 1
    cmp     ecx, r8d
    cmovl   ecx, r8d
.burn_set:
    mov     [rbx + MOB.burn_t], ecx
    xor     ecx, ecx
    test    al, VIS_POISON
    setnz   cl
    mov     [rbx + MOB.poison_t], ecx
    mov     [rbx + MOB.poison], ecx
    xor     ecx, ecx                    ; chill stacks
    xor     r8d, r8d                    ; chill steps
    test    al, VIS_CHILL
    jz      .chill_frozen
    mov     ecx, 1
    mov     r8d, 1
.chill_frozen:
    test    al, VIS_FROZEN
    jz      .chill_set
    mov     ecx, 2
.chill_set:
    mov     [rbx + MOB.chill], ecx
    mov     [rbx + MOB.chill_t], r8d
    xor     ecx, ecx                    ; wind-up
    test    al, VIS_WINDUP
    jz      .windup_set
    mov     ecx, edx
    shr     ecx, MG_WINDUP_SHIFT
    and     ecx, 63
    mov     r8d, 1
    cmp     ecx, r8d
    cmovl   ecx, r8d
.windup_set:
    mov     [rbx + MOB.windup], ecx
    xor     ecx, ecx                    ; the health bar
    test    al, VIS_BAR
    jz      .bar_set
    mov     ecx, NM_BAR_STEPS
.bar_set:
    mov     [rbx + MOB.bar], ecx
    movzx   ecx, dl                     ; .mag: the affixes, shock, mark, bleed, freeze cooldown, captor
    mov     [rbx + MOB.affix], ecx
    mov     ecx, edx
    shr     ecx, MG_SHOCK_SHIFT
    and     ecx, 3
    mov     [rbx + MOB.shock], ecx
    test    ecx, ecx
    setnz   cl
    movzx   ecx, cl
    mov     [rbx + MOB.shock_t], ecx
    xor     ecx, ecx
    test    edx, MG_MARK
    setnz   cl
    mov     [rbx + MOB.mark_t], ecx
    xor     ecx, ecx
    test    edx, MG_BLEED
    setnz   cl
    mov     [rbx + MOB.bleed_t], ecx
    xor     ecx, ecx
    test    edx, MG_FREEZE
    setnz   cl
    mov     [rbx + MOB.freeze_cd], ecx
    mov     ecx, edx
    shr     ecx, MG_CAPTOR_SHIFT
    and     ecx, 7
    mov     [rbx + MOB.captor], cl
    xor     ecx, ecx
    test    edx, MG_TARGET
    setnz   cl
    mov     [rbx + MOB.target], ecx
    xor     ecx, ecx
    test    edx, MG_PROVOKED
    setnz   cl
    mov     [rbx + MOB.provoked], ecx
    lea     rdi, [r12 + MOBREC.pos]
    call    net_pos_in                  ; xmm0..2 = x, y, z (local)
    mov     eax, r13d
    shl     eax, 4
    lea     rcx, [nm_tgt]
    add     rcx, rax
    movss   [rcx], xmm0
    movss   [rcx + 4], xmm1
    movss   [rcx + 8], xmm2
    movss   xmm0, [r12 + MOBREC.yaw]
    movss   xmm1, [c_lim_yaw]
    call    clamp_f                     ; a wild heading is held to +-720 degrees, a NaN to 0
    movss   [rcx + 12], xmm0
    cmp     dword [rsp], 0
    je      .ret
    mov     eax, [rcx]                  ; a copy that was not there starts on its target
    mov     [rbx + BODY.x], eax
    mov     eax, [rcx + 4]
    mov     [rbx + BODY.y], eax
    mov     eax, [rcx + 8]
    mov     [rbx + BODY.z], eax
    movss   [rbx + BODY.yaw], xmm0
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; nm_on_snap_mobs(edi from, esi type, rdx payload, ecx len): SNAP_MOBS, host -> guest: every record is written into the mob
; table (apply_mrec); every slot the mask leaves out is emptied; game_time follows the host's when it is more than 30
; steps off (sleeping through a night, the debug menu)
nm_on_snap_mobs:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret0
    cmp     ecx, 16
    jb      .ret0
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rdx
    movzx   eax, byte [rbx + 12]
    cmp     eax, NM_MOBS_PER_MSG
    ja      .done
    imul    edx, eax, MOBREC_size
    add     edx, 16
    cmp     edx, ecx
    ja      .done                       ; cut short
    mov     r12d, eax
    mov     eax, [rbx]
    mov     edx, [game_time]
    sub     edx, eax
    mov     ecx, edx
    sar     ecx, 31
    xor     edx, ecx
    sub     edx, ecx
    cmp     edx, 30
    jle     .time_ok
    mov     [game_time], eax
.time_ok:
    lea     r13, [rbx + 16]
.rec:
    test    r12d, r12d
    jz      .clear
    mov     rdi, r13
    call    apply_mrec
    add     r13, MOBREC_size
    dec     r12d
    jmp     .rec
.clear:
    mov     rdx, [rbx + 4]              ; the mask: slots it leaves out are empty
    lea     rsi, [mobs]
    xor     ecx, ecx
.slot:
    bt      rdx, rcx
    jc      .keep
    cmp     dword [rsi + MOB.type], MOB_NONE
    je      .keep
    mov     dword [rsi + MOB.type], MOB_NONE
.keep:
    add     rsi, MOB_size
    inc     ecx
    cmp     ecx, MAX_MOBS
    jb      .slot
.done:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
.ret0:
    ret

; nm_on_snap_drops(edi from, esi type, rdx payload, ecx len): SNAP_DROPS, host -> guest: the drops of the mask are written
; into the drop table (a new one starts on its target; delay 9999: no pickup here: the host decides who gets an item); the
; others are emptied. Slot MAX_DROPS - 1 (63) is this guest's staging slot, where its own tosses wait for their DROP_SPAWN: a
; record that names it is ignored and it is never emptied, so what the host sends can neither fill it nor take it back.
; rbx = payload, r12d = records left, r13 = the record being read; frame: [rsp] its slot, [rsp+4] 1 for a new drop
nm_on_snap_drops:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret0
    cmp     ecx, 16
    jb      .ret0
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rdx
    movzx   eax, byte [rbx + 8]
    cmp     eax, NM_DROPS_PER_MSG
    ja      .done
    imul    edx, eax, DROPREC_size
    add     edx, 16
    cmp     edx, ecx
    ja      .done
    mov     r12d, eax
    lea     r13, [rbx + 16]
.rec:
    test    r12d, r12d
    jz      .clear
    movzx   eax, byte [r13 + DROPREC.slot]
    cmp     eax, MAX_DROPS - 1
    jae     .next
    movzx   ecx, byte [r13 + DROPREC.id]
    test    ecx, ecx
    jz      .next
    cmp     ecx, NUM_ITEMS
    jae     .next                       ; (no such item)
    mov     [rsp], eax
    imul    edx, eax, DROP_size
    lea     rsi, [drops]
    add     rsi, rdx                    ; the drop
    xor     eax, eax
    cmp     byte [rsi + DROP.id], 0
    sete    al
    mov     [rsp + 4], eax              ; 1: a new one
    mov     [rsi + DROP.id], cl
    mov     al, [r13 + DROPREC.count]
    mov     [rsi + DROP.count], al
    movzx   eax, word [r13 + DROPREC.dmg]
    mov     [rsi + DROP.dmg], ax
    mov     dword [rsi + DROP.delay], 9999
    lea     rdi, [r13 + DROPREC.pos]
    call    net_pos_in                  ; xmm0..2 = x, y, z (local)
    mov     eax, [rsp]
    lea     rcx, [nd_tgt]
    lea     eax, [rax + rax*2]
    lea     rcx, [rcx + rax*4]
    movss   [rcx], xmm0
    movss   [rcx + 4], xmm1
    movss   [rcx + 8], xmm2
    cmp     dword [rsp + 4], 0
    je      .next
    imul    edx, dword [rsp], DROP_size
    lea     rsi, [drops]
    add     rsi, rdx
    movss   [rsi + DROP.x], xmm0
    movss   [rsi + DROP.y], xmm1
    movss   [rsi + DROP.z], xmm2
    mov     dword [rsi + DROP.vx], 0
    mov     dword [rsi + DROP.vy], 0
    mov     dword [rsi + DROP.vz], 0
    mov     dword [rsi + DROP.age], 0
.next:
    add     r13, DROPREC_size
    dec     r12d
    jmp     .rec
.clear:
    mov     rdx, [rbx]
    lea     rsi, [drops]
    xor     ecx, ecx
.slot:
    cmp     ecx, MAX_DROPS - 1
    jae     .done
    bt      rdx, rcx
    jc      .keep
    mov     byte [rsi + DROP.id], 0
.keep:
    add     rsi, DROP_size
    inc     ecx
    jmp     .slot
.done:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
.ret0:
    ret

; nm_on_snap_misc(edi from, esi type, rdx payload, ecx len): SNAP_MISC, host -> guest: boats (a boat the mask leaves out is
; gone, a new one is made as boats_place makes it; the boat this player rides is never touched) and primed TNT
; (the first records take primed[0..n), the rest are out)
; rbx = payload, r12d = the boat mask, r13 = the record being read, r14 = a table entry, r15d = a counter;
; frame: [rsp] boats left, [rsp+4] TNT left, [rsp+8] 1 for a new boat
nm_on_snap_misc:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret0
    cmp     ecx, 4
    jb      .ret0
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     rbx, rdx
    movzx   eax, byte [rbx + 2]         ; nboats
    movzx   edx, byte [rbx + 3]         ; ntnt
    cmp     eax, MAX_BOATS
    ja      .done
    cmp     edx, MAX_PRIMED
    ja      .done
    mov     [rsp], eax
    mov     [rsp + 4], edx
    imul    eax, eax, BOATREC_size
    imul    edx, edx, TNTREC_size
    lea     eax, [rax + rdx + 4]
    cmp     eax, ecx
    ja      .done
    movzx   r12d, word [rbx]
    lea     r14, [boats]                ; boats the mask leaves out are gone (but the ridden one)
    xor     r15d, r15d
.gone:
    bt      r12d, r15d
    jc      .gone_next
    lea     eax, [r15 + 1]
    cmp     eax, [boat_riding]
    je      .gone_next
    mov     dword [r14 + BOATENT.used], 0
.gone_next:
    add     r14, BOATENT_size
    inc     r15d
    cmp     r15d, MAX_BOATS
    jb      .gone
    lea     r13, [rbx + 4]
.boat:
    cmp     dword [rsp], 0
    je      .tnt
    dec     dword [rsp]
    movzx   r15d, byte [r13 + BOATREC.slot]
    cmp     r15d, MAX_BOATS
    jae     .boat_next
    lea     eax, [r15 + 1]
    cmp     eax, [boat_riding]
    je      .boat_next                  ; the boat this player rides is his own to steer
    imul    r14d, r15d, BOATENT_size
    lea     rax, [boats]
    add     r14, rax
    xor     eax, eax
    cmp     dword [r14 + BOATENT.used], 0
    sete    al
    mov     [rsp + 8], eax              ; 1: a new boat
    test    eax, eax
    jz      .have_boat
    mov     rdi, r14
    movss   xmm0, [c_boat_hw]
    movss   xmm1, [c_boat_h]
    xorps   xmm2, xmm2
    call    body_init
    mov     dword [r14 + BOATENT.used], 1
    mov     dword [r14 + BOATENT.speed], 0
.have_boat:
    lea     rdi, [r13 + BOATREC.pos]
    call    net_pos_in
    shl     r15d, 4
    lea     rax, [nb_tgt]
    add     rax, r15
    movss   [rax], xmm0
    movss   [rax + 4], xmm1
    movss   [rax + 8], xmm2
    mov     ecx, [r13 + BOATREC.yaw]
    mov     [rax + 12], ecx
    cmp     dword [rsp + 8], 0
    je      .boat_next
    movss   [r14 + BODY.x], xmm0
    movss   [r14 + BODY.y], xmm1
    movss   [r14 + BODY.z], xmm2
    mov     [r14 + BODY.yaw], ecx
.boat_next:
    add     r13, BOATREC_size
    jmp     .boat
.tnt:
    lea     r14, [primed]
    mov     r15d, [rsp + 4]             ; records
.tnt_rec:
    test    r15d, r15d
    jz      .tnt_clear
    lea     rdi, [r13 + TNTREC.pos]
    call    net_pos_in
    movss   [r14 + PRIMED.body + BODY.x], xmm0
    movss   [r14 + PRIMED.body + BODY.y], xmm1
    movss   [r14 + PRIMED.body + BODY.z], xmm2
    movzx   eax, word [r13 + TNTREC.fuse]
    mov     [r14 + PRIMED.fuse], eax
    add     r13, TNTREC_size
    add     r14, PRIMED_size
    dec     r15d
    jmp     .tnt_rec
.tnt_clear:
    mov     eax, [rsp + 4]              ; the rest of the table is out
    lea     rcx, [primed]
    imul    edx, eax, PRIMED_size
    add     rcx, rdx
.tnt_out:
    cmp     eax, MAX_PRIMED
    jae     .done
    mov     dword [rcx + PRIMED.fuse], 0
    add     rcx, PRIMED_size
    inc     eax
    jmp     .tnt_out
.done:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
.ret0:
    ret

; ==== the guest's copies, each step ==================================================================================

; yaw_follow(xmm0 yaw, xmm1 target, xmm2 fraction) -> xmm0 yaw moved that fraction of the shortest way round to the target,
; in [0, 360). No loops: a wild float (NaN too) comes out wild but the call ends. Clobbers xmm3..xmm5.
yaw_follow:
    subss   xmm1, xmm0                  ; delta
    movss   xmm3, [c_180]
    movss   xmm4, [c_360]
    addss   xmm1, xmm3
    movaps  xmm5, xmm1
    divss   xmm5, xmm4
    roundss xmm5, xmm5, 9
    mulss   xmm5, xmm4
    subss   xmm1, xmm5                  ; (delta + 180) mod 360
    subss   xmm1, xmm3                  ; delta, into [-180, 180)
    mulss   xmm1, xmm2
    addss   xmm0, xmm1
    movaps  xmm5, xmm0
    divss   xmm5, xmm4
    roundss xmm5, xmm5, 9
    mulss   xmm5, xmm4
    subss   xmm0, xmm5                  ; the yaw, into [0, 360)
    ret

; nm_guest_step(): once per simulation step on a guest, where mobs_step, status_step, drops_step, tnt_step and the other
; boats' step would be: the mob copies move c_follow of the way to their snapshot targets (a copy over 6 blocks off jumps),
; turn the shortest way, walk their legs by the ground covered (mob_update's 180 degrees per block) and count their tint,
; stun, wind-up, burn and bar steps down; drop copies move half way and age (the bob); primed TNT blinks down; the
; boats (but the ridden one) follow their targets. Nothing else of the world is simulated here.
; rbx = the table entry, r12d = its index; frame: [rsp] the step taken on x, [rsp+4] on z
nm_guest_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    lea     rbx, [mobs]
    xor     r12d, r12d
.mob:
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .mob_next
    mov     eax, r12d
    shl     eax, 4
    lea     rcx, [nm_tgt]
    add     rcx, rax
    movss   xmm0, [rcx]
    subss   xmm0, [rbx + BODY.x]        ; dx
    movss   xmm1, [rcx + 4]
    subss   xmm1, [rbx + BODY.y]        ; dy
    movss   xmm2, [rcx + 8]
    subss   xmm2, [rbx + BODY.z]        ; dz
    movaps  xmm3, xmm0
    mulss   xmm3, xmm3
    movaps  xmm4, xmm1
    mulss   xmm4, xmm4
    addss   xmm3, xmm4
    movaps  xmm4, xmm2
    mulss   xmm4, xmm4
    addss   xmm3, xmm4
    comiss  xmm3, [c_snap2]
    jbe     .follow
    movss   xmm3, [rcx]                 ; too far off: it jumps
    movss   [rbx + BODY.x], xmm3
    movss   xmm3, [rcx + 4]
    movss   [rbx + BODY.y], xmm3
    movss   xmm3, [rcx + 8]
    movss   [rbx + BODY.z], xmm3
    xorps   xmm0, xmm0
    xorps   xmm2, xmm2
    jmp     .turn
.follow:
    movss   xmm3, [c_follow]
    mulss   xmm0, xmm3
    mulss   xmm1, xmm3
    mulss   xmm2, xmm3
    movss   xmm3, [rbx + BODY.x]
    addss   xmm3, xmm0
    movss   [rbx + BODY.x], xmm3
    movss   xmm3, [rbx + BODY.y]
    addss   xmm3, xmm1
    movss   [rbx + BODY.y], xmm3
    movss   xmm3, [rbx + BODY.z]
    addss   xmm3, xmm2
    movss   [rbx + BODY.z], xmm3
.turn:
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm2
    movss   xmm0, [rbx + BODY.yaw]
    movss   xmm1, [rcx + 12]
    movss   xmm2, [c_follow]
    call    yaw_follow
    movss   [rbx + BODY.yaw], xmm0
    movss   xmm0, [rsp]                 ; walk cycle: 180 degrees per block walked
    mulss   xmm0, xmm0
    movss   xmm1, [rsp + 4]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    sqrtss  xmm0, xmm0
    mulss   xmm0, [c_180]
    addss   xmm0, [rbx + MOB.walk]
    movss   xmm1, [c_360]
    comiss  xmm0, xmm1
    jb      .walk_ok
    subss   xmm0, xmm1
.walk_ok:
    movss   [rbx + MOB.walk], xmm0
    cmp     dword [rbx + MOB.hurt], 0
    jle     .no_hurt
    dec     dword [rbx + MOB.hurt]
.no_hurt:
    cmp     dword [rbx + MOB.stun], 0
    jle     .no_stun
    dec     dword [rbx + MOB.stun]
.no_stun:
    cmp     dword [rbx + MOB.windup], 1
    jle     .no_windup
    dec     dword [rbx + MOB.windup]
.no_windup:
    cmp     dword [rbx + MOB.burn_t], 1
    jle     .no_burn
    dec     dword [rbx + MOB.burn_t]
.no_burn:
    cmp     dword [rbx + MOB.bar], 0
    jle     .mob_next
    dec     dword [rbx + MOB.bar]
.mob_next:
    add     rbx, MOB_size
    inc     r12d
    cmp     r12d, MAX_MOBS
    jb      .mob
    ; ---- drops
    lea     rbx, [drops]
    xor     r12d, r12d
.drop:
    cmp     byte [rbx + DROP.id], 0
    je      .drop_next
    cmp     r12d, MAX_DROPS - 1
    jae     .drop_next                  ; (slot 63 is this guest's own, waiting to be sent)
    lea     eax, [r12 + r12*2]
    lea     rcx, [nd_tgt]
    lea     rcx, [rcx + rax*4]
    movss   xmm2, [c_follow_d]
    movss   xmm0, [rcx]
    subss   xmm0, [rbx + DROP.x]
    mulss   xmm0, xmm2
    addss   xmm0, [rbx + DROP.x]
    movss   [rbx + DROP.x], xmm0
    movss   xmm0, [rcx + 4]
    subss   xmm0, [rbx + DROP.y]
    mulss   xmm0, xmm2
    addss   xmm0, [rbx + DROP.y]
    movss   [rbx + DROP.y], xmm0
    movss   xmm0, [rcx + 8]
    subss   xmm0, [rbx + DROP.z]
    mulss   xmm0, xmm2
    addss   xmm0, [rbx + DROP.z]
    movss   [rbx + DROP.z], xmm0
    inc     dword [rbx + DROP.age]
.drop_next:
    add     rbx, DROP_size
    inc     r12d
    cmp     r12d, MAX_DROPS
    jb      .drop
    ; ---- primed TNT
    lea     rbx, [primed]
    mov     r12d, MAX_PRIMED
.tnt:
    cmp     dword [rbx + PRIMED.fuse], 1
    jle     .tnt_next
    dec     dword [rbx + PRIMED.fuse]
.tnt_next:
    add     rbx, PRIMED_size
    dec     r12d
    jnz     .tnt
    ; ---- boats
    lea     rbx, [boats]
    xor     r12d, r12d
.boat:
    cmp     dword [rbx + BOATENT.used], 0
    je      .boat_next
    lea     eax, [r12 + 1]
    cmp     eax, [boat_riding]
    je      .boat_next
    mov     eax, r12d
    shl     eax, 4
    lea     rcx, [nb_tgt]
    add     rcx, rax
    movss   xmm2, [c_follow]
    movss   xmm0, [rcx]
    subss   xmm0, [rbx + BODY.x]
    mulss   xmm0, xmm2
    movss   xmm1, [rcx + 8]
    subss   xmm1, [rbx + BODY.z]
    mulss   xmm1, xmm2
    movss   xmm3, [rcx + 4]
    subss   xmm3, [rbx + BODY.y]
    movaps  xmm4, xmm0
    mulss   xmm4, xmm4
    movaps  xmm5, xmm1
    mulss   xmm5, xmm5
    addss   xmm4, xmm5
    comiss  xmm4, [c_snap2]
    jbe     .boat_follow
    movss   xmm0, [rcx]                 ; too far off: it jumps
    movss   [rbx + BODY.x], xmm0
    movss   xmm0, [rcx + 4]
    movss   [rbx + BODY.y], xmm0
    movss   xmm0, [rcx + 8]
    movss   [rbx + BODY.z], xmm0
    jmp     .boat_yaw
.boat_follow:
    addss   xmm0, [rbx + BODY.x]
    movss   [rbx + BODY.x], xmm0
    addss   xmm1, [rbx + BODY.z]
    movss   [rbx + BODY.z], xmm1
    mulss   xmm3, xmm2
    addss   xmm3, [rbx + BODY.y]
    movss   [rbx + BODY.y], xmm3
.boat_yaw:
    movss   xmm0, [rbx + BODY.yaw]
    movss   xmm1, [rcx + 12]
    movss   xmm2, [c_follow]
    call    yaw_follow
    movss   [rbx + BODY.yaw], xmm0
.boat_next:
    add     rbx, BOATENT_size
    inc     r12d
    cmp     r12d, MAX_BOATS
    jb      .boat
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; nm_shift(edi dx, esi dz): the origin moved by (dx, dz) blocks (a floating-origin rebase): the targets of the mob, drop
; and boat copies drop by that much, as the entities themselves do
nm_shift:
    cvtsi2ss xmm0, edi
    cvtsi2ss xmm1, esi
    lea     rax, [nm_tgt]
    mov     ecx, MAX_MOBS
.mob:
    movss   xmm2, [rax]
    subss   xmm2, xmm0
    movss   [rax], xmm2
    movss   xmm2, [rax + 8]
    subss   xmm2, xmm1
    movss   [rax + 8], xmm2
    add     rax, 16
    dec     ecx
    jnz     .mob
    lea     rax, [nd_tgt]
    mov     ecx, MAX_DROPS
.drop:
    movss   xmm2, [rax]
    subss   xmm2, xmm0
    movss   [rax], xmm2
    movss   xmm2, [rax + 8]
    subss   xmm2, xmm1
    movss   [rax + 8], xmm2
    add     rax, 12
    dec     ecx
    jnz     .drop
    lea     rax, [nb_tgt]
    mov     ecx, MAX_BOATS
.boat:
    movss   xmm2, [rax]
    subss   xmm2, xmm0
    movss   [rax], xmm2
    movss   xmm2, [rax + 8]
    subss   xmm2, xmm1
    movss   [rax + 8], xmm2
    add     rax, 16
    dec     ecx
    jnz     .boat
    ret
