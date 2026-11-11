; netmisc.asm - the multiplayer messages that carry no world state of their own: the twins of projectiles, sounds and
; effects, the reward events, faction standing, the shared quest chain, drops a guest makes and drops the host hands out, the
; night everybody has to sleep through, and the damage of an explosion to the other players. Network code runs on the main
; thread only.
; A handler is called by netsync's dispatch as (edi slot the message came from, esi type, rdx payload, ecx length) and ignores
; what is not meant for its role: a message for the host that reaches a guest (or the reverse), a short or insane payload.
; Positions on the wire are absolute (net_pos_out / net_pos_in); everything inside the game is local.
%include "common.inc"
default rel

global nx_on_proj, nx_on_proj_end, nx_on_sound, nx_on_fx, nx_on_event, nx_on_event_state, nx_on_standing, nx_on_faction_add, nx_on_spell
global nx_on_quest_sync, nx_on_quest_accept, nx_on_quest_bump, nx_on_quest_complete, nx_on_quest_reward
global nx_on_drop_spawn, nx_on_give
global net_proj_out, net_proj_end_out, net_sound_out, net_fx_out, net_event_out, net_standing_out, net_spell_beam_out
global net_faction_add_out, net_quest_sync_out, net_explosion_players, net_drop_flush, net_give_out, net_all_asleep
global nx_clock_ns

extern net_role, net_self, net_pvp, net_applying, net_peers
extern net_out, net_send_to, net_relay, net_pos_out, net_pos_in
extern net_hurt_send_direct
extern arrows, arrow_net, arrows_spawn
extern audio_play_at, audio_play, fx_explosion, fx_burst, spells_beam_fx
extern structures_dungeon_reward, structures_boss_reward
extern events_on_ev, events_net_apply
extern world_header, faction_add, faction_set_from_net
extern rpg_state, quests_current, quests_accept, quests_bump, quests_settle, quests_reward, quests_refund
extern drops, drops_spawn, inv_add_dmg, player
extern explode_pvp, explode_dmg_mult, explode_base_dmg, settings
extern time_mono_ns

%define PROJ_RANGE      128             ; the host sends a projectile to the guests within this many blocks of it
%define SOUND_RANGE     24
%define FX_RANGE        64
%define SOUND_RATE      60              ; sounds, effects a peer sends per second
%define FX_RATE         30
%define SPELL_RATE      10              ; beams a peer may send per second
%define BITS_DIR        0x3F8147AE      ; 1.01: the largest component of a unit direction
%define BEAM_MAX_LEN    24.5            ; the longest beam (a Laser with Pierce is 24 blocks)
%define GIVE_DELAY      120             ; steps before a stack a full inventory handed back can be picked up again
%define AF_WIRE         0x77F           ; the AF_* bits a projectile message may carry (flags and element)
%define BITS_V          0x447A0000      ; 1000.0: the largest |velocity| or |float| accepted from the wire, as float bits
%define BITS_Y          0x46000000      ; 8192.0: the largest |y|
%define BITS_FX         0x41800000      ; 16.0: the largest effect radius or speed

struc PROJMSG                           ; MT_PROJ
    .owner_peer: resb 1                 ; the peer that fired it, 255 = the world (a monster, a folk)
    .owner_slot: resb 1                 ; its slot in that machine's arrows[]
    .kind:       resb 1                 ; PROJ_*
    .pad:        resb 1
    .flags:      resd 1                 ; AF_*
    .pos:        resb NPOS_size
    .vx:         resd 1
    .vy:         resd 1
    .vz:         resd 1
endstruc                                ; 36
struc SNDMSG                            ; MT_SOUND
    .snd:        resb 1
    .vol:        resb 1                 ; x 100
    .pad:        resw 1
    .pos:        resb NPOS_size
endstruc                                ; 20
struc FXMSG                             ; MT_FX
    .kind:       resb 1                 ; FXN_*
    .sub:        resb 1                 ; the burst's particle kind
    .count:      resb 1
    .pad:        resb 1
    .f:          resd 1                 ; radius (explosion) or speed (burst)
    .pos:        resb NPOS_size
endstruc                                ; 24
struc SPELLMSG                          ; MT_SPELL
    .kind:       resb 1                 ; SPM_BEAM
    .elem:       resb 1                 ; ELEM_*
    .pad:        resw 1
    .len:        resd 1                 ; float blocks
    .dir:        resd 3                 ; float unit direction
    .pos:        resb NPOS_size         ; where the beam starts
endstruc                                ; 36
struc DROPMSG                           ; MT_DROP_SPAWN
    .id:         resb 1
    .count:      resb 1
    .dmg:        resw 1
    .delay:      resw 1
    .pad:        resw 1
    .pos:        resb NPOS_size
    .vx:         resd 1
    .vy:         resd 1
    .vz:         resd 1
endstruc                                ; 36
struc PVPMSG                            ; MT_PVP_HIT
    .victim:     resb 1
    .attacker:   resb 1
    .sts:        resb 1                 ; 255 = none
    .pad:        resb 1
    .amount:     resd 1
    .sts_mag:    resd 1
    .src_ax:     resd 1                 ; the first 12 bytes of an NPOS: where the blow comes from
    .src_az:     resd 1
    .src_fx:     resw 1
    .src_fz:     resw 1
    .kb:         resd 1
endstruc                                ; 28

section .rodata
align 4
c_100:         dd 100.0
c_one:         dd 1.0
c_chest:       dd 0.9                   ; a player's chest above his feet (explode.asm's)
c_twenty:      dd 20.0                  ; damage scales with max health / 20
c_three:       dd 3.0
c_kb:          dd 12.0                  ; knockback and hop at full strength: explode.asm's c_kb and c_hop
c_hop:         dd 6.0
c_proj_range:  dd 128.0
c_sound_range: dd 24.0
c_fx_range:    dd 64.0
c_beam_max:    dd BEAM_MAX_LEN
c_pop_vol:     dd 0.35
c_drop_y:      dd 0.5                   ; a stack that does not fit falls this far above the feet (rpg_give_item's)
c_nan:         dd 0x7FC00000            ; "no position": net_relay sends to every guest

section .bss
alignb 8
nx_clock_ns:   resq 1                   ; test seam: the clock (ns) the rate limiters read; 0 = the real one, time_mono_ns
snd_rate:      resd 2                   ; the second, sounds sent in it
fx_rate:       resd 2
snd_in:        resd 2 * NET_MAX_PEERS   ; the host's limiter, per sender slot: the second, sounds taken from him in it
fx_in:         resd 2 * NET_MAX_PEERS
spell_in:      resd 2 * NET_MAX_PEERS   ; the host's limiter for beams, per sender slot

section .text

; ---- helpers -----------------------------------------------------------------------------------------------------------

; rate_ok(rdi state {second dd, count dd}, esi limit) -> eax 1 when one more message may go out in this second
rate_ok:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12d, esi
    mov     rax, [nx_clock_ns]          ; a test sets a clock here
    test    rax, rax
    jnz     .clock
    call    time_mono_ns
.clock:
    xor     edx, edx
    mov     ecx, 1000000000
    div     rcx                         ; whole seconds
    cmp     eax, [rbx]
    je      .same
    mov     [rbx], eax
    mov     dword [rbx + 4], 0
.same:
    xor     eax, eax
    mov     ecx, [rbx + 4]
    cmp     ecx, r12d
    jae     .ret
    inc     ecx
    mov     [rbx + 4], ecx
    mov     eax, 1
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ghost_kill(edi tag): every ghost projectile carrying that tag is gone (at most one; a lost PROJ_END can leave an older one)
ghost_kill:
    lea     rax, [arrows]
    lea     rcx, [arrow_net]
    xor     edx, edx
.l:
    cmp     [rcx + rdx*4], edi
    jne     .next
    cmp     dword [rax + ARROWENT.live], 0
    je      .next
    test    dword [rax + ARROWENT.flags], AF_GHOST
    jz      .next
    mov     dword [rax + ARROWENT.live], 0
    mov     dword [rcx + rdx*4], 0
.next:
    add     rax, ARROWENT_size
    inc     edx
    cmp     edx, MAX_ARROWS
    jb      .l
    ret

; ---- projectiles ---------------------------------------------------------------------------------------------------------

; net_proj_out(edi arrow slot): arrows[slot] is a real projectile that was just spawned: its twin goes to the other peers.
; The tag in arrow_net pairs the two ((owner peer + 1) << 8 | slot; owner peer 255 for the world's). A guest sends to the
; host; the host sends to the guests within 128 blocks.
; rbx = the arrow, r12d = its slot; frame: PROJMSG @0
net_proj_out:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 48
    cmp     byte [net_role], NET_ROLE_OFF
    je      .ret
    mov     r12d, edi
    imul    eax, edi, ARROWENT_size
    lea     rbx, [arrows]
    add     rbx, rax
    movzx   eax, byte [net_self]
    mov     ecx, 255
    cmp     dword [rbx + ARROWENT.owner], OWNER_PLAYER
    cmovne  eax, ecx
    mov     [rsp + PROJMSG.owner_peer], al
    mov     [rsp + PROJMSG.owner_slot], r12b
    mov     eax, [rbx + ARROWENT.kind]
    mov     [rsp + PROJMSG.kind], al
    mov     byte [rsp + PROJMSG.pad], 0
    mov     eax, [rbx + ARROWENT.flags]
    mov     [rsp + PROJMSG.flags], eax
    mov     eax, [rbx + ARROWENT.vx]
    mov     [rsp + PROJMSG.vx], eax
    mov     eax, [rbx + ARROWENT.vy]
    mov     [rsp + PROJMSG.vy], eax
    mov     eax, [rbx + ARROWENT.vz]
    mov     [rsp + PROJMSG.vz], eax
    lea     rdi, [rsp + PROJMSG.pos]
    movss   xmm0, [rbx + ARROWENT.x]
    movss   xmm1, [rbx + ARROWENT.y]
    movss   xmm2, [rbx + ARROWENT.z]
    call    net_pos_out
    movzx   eax, byte [rsp + PROJMSG.owner_peer]
    inc     eax
    shl     eax, 8
    or      eax, r12d
    lea     rcx, [arrow_net]
    mov     [rcx + r12*4], eax
    cmp     byte [net_role], NET_ROLE_HOST
    je      .host
    mov     edi, MT_PROJ
    mov     rsi, rsp
    mov     edx, PROJMSG_size
    xor     ecx, ecx
    call    net_out
    jmp     .ret
.host:
    mov     edi, -1
    mov     esi, MT_PROJ
    mov     rdx, rsp
    mov     ecx, PROJMSG_size
    xor     r8d, r8d
    movss   xmm0, [rbx + ARROWENT.x]
    movss   xmm1, [rbx + ARROWENT.y]
    movss   xmm2, [rbx + ARROWENT.z]
    movss   xmm3, [c_proj_range]
    call    net_relay
.ret:
    add     rsp, 48
    pop     r12
    pop     rbx
    pop     rbp
    ret

; net_proj_end_out(edi arrow slot): the real projectile in that slot ended: its twins go (PROJ_END to the other peers) and
; the tag is cleared. Nothing when it carried none or the session is over.
; frame: owner peer @0, owner slot @1
net_proj_end_out:
    sub     rsp, 24
    lea     rcx, [arrow_net]
    mov     eax, [rcx + rdi*4]
    test    eax, eax
    jz      .ret
    mov     dword [rcx + rdi*4], 0
    cmp     byte [net_role], NET_ROLE_OFF
    je      .ret
    mov     [rsp + 1], al               ; the slot
    shr     eax, 8
    dec     eax
    mov     [rsp], al                   ; the peer
    cmp     byte [net_role], NET_ROLE_HOST
    je      .host
    mov     edi, MT_PROJ_END
    mov     rsi, rsp
    mov     edx, 2
    xor     ecx, ecx
    call    net_out
    jmp     .ret
.host:
    mov     edi, -1
    mov     esi, MT_PROJ_END
    mov     rdx, rsp
    mov     ecx, 2
    xor     r8d, r8d
    movss   xmm0, [c_nan]
    movaps  xmm1, xmm0
    movaps  xmm2, xmm0
    xorps   xmm3, xmm3
    call    net_relay
.ret:
    add     rsp, 24
    ret

; nx_on_proj(edi slot, esi type, rdx payload, ecx len): another peer's projectile: a ghost of it flies here (AF_GHOST: hits
; nothing, is never picked up, never explodes), tagged for its PROJ_END; one with the same tag (an end that got lost) is
; replaced. The host takes it only from the guest who fired it (owner peer = the sender, never the world's) and passes it,
; as it came, to the other guests within 128 blocks.
; rbx = the message, r12d = the sender's slot, r13d = its length, r14d = the tag; frame: position @0, net_applying @32
nx_on_proj:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 48
    cmp     ecx, PROJMSG_size
    jb      .ret
    cmp     byte [net_role], NET_ROLE_OFF
    je      .ret
    mov     rbx, rdx
    mov     r12d, edi
    mov     r13d, ecx
    movzx   eax, byte [rbx + PROJMSG.kind]
    cmp     eax, PROJ_SPELL
    ja      .ret
    jne     .kind_ok
    mov     edx, [rbx + PROJMSG.flags]  ; a rune spell's element is one of the five
    shr     edx, AF_ELEM_SHIFT
    and     edx, HITF_ELEM_MASK
    cmp     edx, ELEM_POISON
    ja      .ret
.kind_ok:
    movzx   eax, byte [rbx + PROJMSG.owner_slot]
    cmp     eax, MAX_ARROWS
    jae     .ret
    movzx   ecx, byte [rbx + PROJMSG.owner_peer]
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .heard
    cmp     ecx, r12d                   ; the host: a guest sends only what it fired itself - not another's, not the world's
    jne     .ret
    jmp     .tag
.heard:                                 ; a guest hears it from the host, who vouches for the owner
    cmp     ecx, 255
    je      .tag
    cmp     ecx, NET_MAX_PEERS
    jae     .ret
    movzx   edx, byte [net_self]
    cmp     ecx, edx
    je      .ret                        ; ours coming back: it exists here already
.tag:
    inc     ecx
    shl     ecx, 8
    or      ecx, eax
    mov     r14d, ecx
    mov     eax, [rbx + PROJMSG.vx]     ; finite and sane, or it is dropped
    and     eax, 0x7FFFFFFF
    cmp     eax, BITS_V
    ja      .ret
    mov     eax, [rbx + PROJMSG.vy]
    and     eax, 0x7FFFFFFF
    cmp     eax, BITS_V
    ja      .ret
    mov     eax, [rbx + PROJMSG.vz]
    and     eax, 0x7FFFFFFF
    cmp     eax, BITS_V
    ja      .ret
    mov     eax, [rbx + PROJMSG.pos + NPOS.y]
    and     eax, 0x7FFFFFFF
    cmp     eax, BITS_Y
    ja      .ret
    mov     edi, r14d
    call    ghost_kill
    lea     rdi, [rbx + PROJMSG.pos]
    call    net_pos_in
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 8], xmm2
    movzx   eax, byte [net_applying]
    mov     [rsp + 32], eax
    mov     byte [net_applying], 1
    movss   xmm3, [rbx + PROJMSG.vx]
    movss   xmm4, [rbx + PROJMSG.vy]
    movss   xmm5, [rbx + PROJMSG.vz]
    mov     edi, OWNER_MONSTER
    xor     esi, esi
    xor     edx, edx
    movzx   ecx, byte [rbx + PROJMSG.kind]
    mov     r8d, [rbx + PROJMSG.flags]
    and     r8d, AF_WIRE
    or      r8d, AF_GHOST
    call    arrows_spawn
    mov     edx, [rsp + 32]
    mov     [net_applying], dl
    test    eax, eax
    js      .relay
    lea     rcx, [arrow_net]
    mov     [rcx + rax*4], r14d
.relay:
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    mov     edi, r12d
    mov     esi, MT_PROJ
    mov     rdx, rbx
    mov     ecx, r13d
    xor     r8d, r8d
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    movss   xmm3, [c_proj_range]
    call    net_relay
.ret:
    add     rsp, 48
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; nx_on_proj_end(edi slot, esi type, rdx payload, ecx len): the owner's projectile ended: its ghost here is gone, and the
; host tells the other guests. The host takes it only from the guest who fired it (owner peer = the sender): nobody can end
; another's projectile, or the world's.
nx_on_proj_end:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    cmp     ecx, 2
    jb      .ret
    cmp     byte [net_role], NET_ROLE_OFF
    je      .ret
    mov     rbx, rdx
    mov     r12d, edi
    movzx   eax, byte [rbx + 1]
    movzx   ecx, byte [rbx]
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .heard
    cmp     ecx, r12d                   ; the host: a guest ends only what it fired itself
    jne     .ret
    jmp     .tag
.heard:                                 ; a guest hears it from the host, who vouches for the owner
    cmp     ecx, 255
    je      .tag
    cmp     ecx, NET_MAX_PEERS
    jae     .ret
.tag:
    inc     ecx
    shl     ecx, 8
    or      ecx, eax
    mov     edi, ecx
    call    ghost_kill
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    mov     edi, r12d
    mov     esi, MT_PROJ_END
    mov     rdx, rbx
    mov     ecx, 2
    xor     r8d, r8d
    movss   xmm0, [c_nan]
    movaps  xmm1, xmm0
    movaps  xmm2, xmm0
    xorps   xmm3, xmm3
    call    net_relay
.ret:
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- sounds and effects ------------------------------------------------------------------------------------------------

; net_sound_out(edi snd, xmm0..2 position, xmm3 volume): a positional sound played here goes to the other peers (a guest to the
; host; the host to the guests within 24 blocks), at most 60 a second. Silent sounds are not sent.
; ebx = snd, r12d = volume x 100; frame: SNDMSG @0, local position @24
net_sound_out:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 48
    cmp     byte [net_role], NET_ROLE_OFF
    je      .ret
    mov     ebx, edi
    movss   [rsp + 24], xmm0
    movss   [rsp + 28], xmm1
    movss   [rsp + 32], xmm2
    mulss   xmm3, [c_100]
    xorps   xmm4, xmm4
    maxss   xmm3, xmm4
    minss   xmm3, [c_100]
    cvttss2si r12d, xmm3
    test    r12d, r12d
    jz      .ret
    lea     rdi, [snd_rate]
    mov     esi, SOUND_RATE
    call    rate_ok
    test    eax, eax
    jz      .ret
    mov     [rsp + SNDMSG.snd], bl
    mov     [rsp + SNDMSG.vol], r12b
    mov     word [rsp + SNDMSG.pad], 0
    lea     rdi, [rsp + SNDMSG.pos]
    movss   xmm0, [rsp + 24]
    movss   xmm1, [rsp + 28]
    movss   xmm2, [rsp + 32]
    call    net_pos_out
    cmp     byte [net_role], NET_ROLE_HOST
    je      .host
    mov     edi, MT_SOUND
    mov     rsi, rsp
    mov     edx, SNDMSG_size
    xor     ecx, ecx
    call    net_out
    jmp     .ret
.host:
    mov     edi, -1
    mov     esi, MT_SOUND
    mov     rdx, rsp
    mov     ecx, SNDMSG_size
    xor     r8d, r8d
    movss   xmm0, [rsp + 24]
    movss   xmm1, [rsp + 28]
    movss   xmm2, [rsp + 32]
    movss   xmm3, [c_sound_range]
    call    net_relay
.ret:
    add     rsp, 48
    pop     r12
    pop     rbx
    pop     rbp
    ret

; nx_on_sound(edi slot, esi type, rdx payload, ecx len): another peer's sound is played here (and not sent on); the host
; passes a guest's on to the other guests within 24 blocks.
; rbx = the message, r12d = the sender's slot, r13d = its length; frame: local position @0, net_applying @12
nx_on_sound:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 24
    cmp     ecx, SNDMSG_size
    jb      .ret
    cmp     byte [net_role], NET_ROLE_OFF
    je      .ret
    mov     rbx, rdx
    mov     r12d, edi
    mov     r13d, ecx
    mov     eax, [rbx + SNDMSG.pos + NPOS.y]
    and     eax, 0x7FFFFFFF
    cmp     eax, BITS_Y                 ; not a number, or out of the world: dropped
    ja      .ret
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .unlimited                  ; (a guest hears the host's, which are limited at the host's end)
    cmp     r12d, NET_MAX_PEERS
    jae     .ret
    lea     rdi, [snd_in]
    lea     rdi, [rdi + r12*8]
    mov     esi, SOUND_RATE
    call    rate_ok
    test    eax, eax
    jz      .ret                        ; more than an honest client sends: not played, not passed on
.unlimited:
    lea     rdi, [rbx + SNDMSG.pos]
    call    net_pos_in
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 8], xmm2
    movzx   eax, byte [net_applying]
    mov     [rsp + 12], eax
    mov     byte [net_applying], 1
    movzx   edi, byte [rbx + SNDMSG.snd]
    movzx   eax, byte [rbx + SNDMSG.vol]
    cvtsi2ss xmm3, eax
    divss   xmm3, [c_100]
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    call    audio_play_at
    mov     eax, [rsp + 12]
    mov     [net_applying], al
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    mov     edi, r12d
    mov     esi, MT_SOUND
    mov     rdx, rbx
    mov     ecx, r13d
    xor     r8d, r8d
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    movss   xmm3, [c_sound_range]
    call    net_relay
.ret:
    add     rsp, 24
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; net_fx_out(edi kind, esi sub, edx count, xmm0 f, xmm1..3 position): an explosion (kind FXN_EXPLOSION, f = radius) or a
; burst (FXN_BURST, sub = the particle kind, f = speed) made here goes to the other peers (a guest to the host; the host to
; the guests within 64 blocks), at most 30 a second.
; ebx = kind, r12d = sub, r13d = count; frame: FXMSG @0, f @32, local position @36
net_fx_out:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 56
    cmp     byte [net_role], NET_ROLE_OFF
    je      .ret
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    movss   [rsp + 32], xmm0
    movss   [rsp + 36], xmm1
    movss   [rsp + 40], xmm2
    movss   [rsp + 44], xmm3
    lea     rdi, [fx_rate]
    mov     esi, FX_RATE
    call    rate_ok
    test    eax, eax
    jz      .ret
    mov     eax, 255
    cmp     r13d, eax
    cmova   r13d, eax
    mov     [rsp + FXMSG.kind], bl
    mov     [rsp + FXMSG.sub], r12b
    mov     [rsp + FXMSG.count], r13b
    mov     byte [rsp + FXMSG.pad], 0
    mov     eax, [rsp + 32]
    mov     [rsp + FXMSG.f], eax
    lea     rdi, [rsp + FXMSG.pos]
    movss   xmm0, [rsp + 36]
    movss   xmm1, [rsp + 40]
    movss   xmm2, [rsp + 44]
    call    net_pos_out
    cmp     byte [net_role], NET_ROLE_HOST
    je      .host
    mov     edi, MT_FX
    mov     rsi, rsp
    mov     edx, FXMSG_size
    xor     ecx, ecx
    call    net_out
    jmp     .ret
.host:
    mov     edi, -1
    mov     esi, MT_FX
    mov     rdx, rsp
    mov     ecx, FXMSG_size
    xor     r8d, r8d
    movss   xmm0, [rsp + 36]
    movss   xmm1, [rsp + 40]
    movss   xmm2, [rsp + 44]
    movss   xmm3, [c_fx_range]
    call    net_relay
.ret:
    add     rsp, 56
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; nx_on_fx(edi slot, esi type, rdx payload, ecx len): another peer's explosion or burst is drawn here (and not sent on); the
; host passes a guest's on to the other guests within 64 blocks. A radius or speed beyond 16 is dropped.
; rbx = the message, r12d = the sender's slot, r13d = its length; frame: local position @0, net_applying @12
nx_on_fx:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 24
    cmp     ecx, FXMSG_size
    jb      .ret
    cmp     byte [net_role], NET_ROLE_OFF
    je      .ret
    mov     rbx, rdx
    mov     r12d, edi
    mov     r13d, ecx
    mov     eax, [rbx + FXMSG.f]
    and     eax, 0x7FFFFFFF
    cmp     eax, BITS_FX
    ja      .ret
    mov     eax, [rbx + FXMSG.pos + NPOS.y]
    and     eax, 0x7FFFFFFF
    cmp     eax, BITS_Y
    ja      .ret
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .unlimited                  ; (a guest hears the host's, which are limited at the host's end)
    cmp     r12d, NET_MAX_PEERS
    jae     .ret
    lea     rdi, [fx_in]
    lea     rdi, [rdi + r12*8]
    mov     esi, FX_RATE
    call    rate_ok
    test    eax, eax
    jz      .ret                        ; more than an honest client sends: not drawn, not passed on
.unlimited:
    lea     rdi, [rbx + FXMSG.pos]
    call    net_pos_in
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 8], xmm2
    movzx   eax, byte [net_applying]
    mov     [rsp + 12], eax
    mov     byte [net_applying], 1
    movss   xmm3, [rbx + FXMSG.f]
    cmp     byte [rbx + FXMSG.kind], FXN_EXPLOSION
    jne     .burst
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    call    fx_explosion
    jmp     .played
.burst:
    cmp     byte [rbx + FXMSG.kind], FXN_BURST
    jne     .played
    movzx   edi, byte [rbx + FXMSG.sub]
    movzx   esi, byte [rbx + FXMSG.count]
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    call    fx_burst
.played:
    mov     eax, [rsp + 12]
    mov     [net_applying], al
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    mov     edi, r12d
    mov     esi, MT_FX
    mov     rdx, rbx
    mov     ecx, r13d
    xor     r8d, r8d
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    movss   xmm3, [c_fx_range]
    call    net_relay
.ret:
    add     rsp, 24
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- events and progression -------------------------------------------------------------------------------------------

; net_event_out(edi code, esi arg): the host's reward event (EV_DUNGEON_CLEARED, EV_BOSS_KILLED): applied here, and sent to
; every guest, who apply it the same way. On any other role it is applied here and nothing is sent.
; ebx = code, r12d = arg; frame: EVENT {code u8, pad[3], arg i32}
net_event_out:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    mov     ebx, edi
    mov     r12d, esi
    call    event_apply
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    mov     [rsp], bl
    mov     byte [rsp + 1], 0
    mov     word [rsp + 2], 0
    mov     [rsp + 4], r12d
    mov     edi, MT_EVENT
    mov     rsi, rsp
    mov     edx, 8
    mov     ecx, 1
    call    net_out
.ret:
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; event_apply(ebx code, r12d arg) -> the player's own half of the event: the XP and the banner (structures.asm), or for the
; events of events.asm (EV_EVENT_OFFER..EV_EVENT_LOST) its banner, sound and XP
event_apply:
    sub     rsp, 8
    lea     eax, [rbx - EV_EVENT_OFFER]
    cmp     eax, EV_EVENT_LOST - EV_EVENT_OFFER
    jbe     .event
    mov     edi, r12d
    cmp     ebx, EV_DUNGEON_CLEARED
    jne     .boss
    call    structures_dungeon_reward
    jmp     .ret
.boss:
    cmp     ebx, EV_BOSS_KILLED
    jne     .ret
    call    structures_boss_reward
    jmp     .ret
.event:
    mov     edi, ebx
    mov     esi, r12d
    call    events_on_ev
.ret:
    add     rsp, 8
    ret

; nx_on_event(edi slot, esi type, rdx payload, ecx len): a guest takes the host's reward event
nx_on_event:
    push    rbx
    push    r12
    push    r13                         ; rbx = code, r12d = arg, r13d = net_applying
    cmp     ecx, 8
    jb      .ret
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    movzx   ebx, byte [rdx]
    mov     r12d, [rdx + 4]
    movzx   r13d, byte [net_applying]
    mov     byte [net_applying], 1
    call    event_apply
    mov     [net_applying], r13b
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; nx_on_event_state(edi slot, esi type, rdx payload, ecx len): a guest takes the host's running event (one EVHUD, 20 bytes)
nx_on_event_state:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    cmp     ecx, 20
    jb      .ret
    mov     rdi, rdx
    mov     esi, ecx
    jmp     events_net_apply
.ret:
    ret

; net_standing_out(): the host sends every guest the standings and the champion bits (STANDING)
; frame: standing int16[8] @0, champions @16
net_standing_out:
    cmp     byte [net_role], NET_ROLE_HOST
    je      .go
    ret
.go:
    sub     rsp, 24
    mov     rax, [world_header + WORLDHDR.standing]
    mov     [rsp], rax
    mov     rax, [world_header + WORLDHDR.standing + 8]
    mov     [rsp + 8], rax
    movzx   eax, byte [world_header + WORLDHDR.champions]
    mov     [rsp + 16], al
    mov     byte [rsp + 17], 0
    mov     edi, MT_STANDING
    mov     rsi, rsp
    mov     edx, 18
    mov     ecx, 1
    call    net_out
    add     rsp, 24
    ret

; nx_on_standing(edi slot, esi type, rdx payload, ecx len): a guest takes over the host's standings
nx_on_standing:
    sub     rsp, 8
    cmp     ecx, 18
    jb      .ret
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    movzx   esi, byte [rdx + 16]
    mov     rdi, rdx
    call    faction_set_from_net
.ret:
    add     rsp, 8
    ret

; net_faction_add_out(edi f, esi delta): a guest asks the host to change a standing (FACTION_ADD)
; frame: {f u8, pad u8, delta i16}
net_faction_add_out:
    cmp     byte [net_role], NET_ROLE_GUEST
    je      .go
    ret
.go:
    sub     rsp, 24
    mov     [rsp], dil
    mov     byte [rsp + 1], 0
    mov     [rsp + 2], si
    mov     edi, MT_FACTION_ADD
    mov     rsi, rsp
    mov     edx, 4
    mov     ecx, 1
    call    net_out
    add     rsp, 24
    ret

; nx_on_faction_add(edi slot, esi type, rdx payload, ecx len): the host changes a standing for a guest (faction_add applies
; it, shows the banner and tells every guest)
nx_on_faction_add:
    sub     rsp, 8
    cmp     ecx, 4
    jb      .ret
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    movzx   edi, byte [rdx]
    cmp     edi, NUM_FACTIONS
    jae     .ret
    movsx   esi, word [rdx + 2]
    call    faction_add
.ret:
    add     rsp, 8
    ret

; net_quest_sync_out(): the host sends every guest the quest chain's position (QUEST_SYNC: quest, state, progress)
; frame: {quest u8, state u8, progress u16}
net_quest_sync_out:
    cmp     byte [net_role], NET_ROLE_HOST
    je      .go
    ret
.go:
    sub     rsp, 24
    mov     al, [rpg_state + RPGSAVE.quest]
    mov     [rsp], al
    mov     al, [rpg_state + RPGSAVE.quest_state]
    mov     [rsp + 1], al
    mov     ax, [rpg_state + RPGSAVE.quest_progress]
    mov     [rsp + 2], ax
    mov     edi, MT_QUEST_SYNC
    mov     rsi, rsp
    mov     edx, 4
    mov     ecx, 1
    call    net_out
    add     rsp, 24
    ret

; nx_on_quest_sync(edi slot, esi type, rdx payload, ecx len): a guest takes over the chain's position
nx_on_quest_sync:
    cmp     ecx, 4
    jb      .ret
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    movzx   eax, byte [rdx]
    cmp     eax, NUM_QUESTS
    ja      .ret
    cmp     byte [rdx + 1], 1
    ja      .ret
    mov     [rpg_state + RPGSAVE.quest], al
    mov     al, [rdx + 1]
    mov     [rpg_state + RPGSAVE.quest_state], al
    mov     ax, [rdx + 2]
    mov     [rpg_state + RPGSAVE.quest_progress], ax
.ret:
    ret

; nx_on_quest_accept(edi slot, esi type, rdx payload, ecx len): a guest accepts the quest on offer (only that one)
nx_on_quest_accept:
    sub     rsp, 8
    cmp     ecx, 1
    jb      .ret
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    movzx   eax, byte [rdx]
    cmp     al, [rpg_state + RPGSAVE.quest]
    jne     .ret
    call    quests_accept
.ret:
    add     rsp, 8
    ret

; nx_on_quest_bump(edi slot, esi type, rdx payload, ecx len): a guest's kill, clear or boss counts for the chain's quest
; (quests_bump checks that it is accepted, of that type and not done)
nx_on_quest_bump:
    sub     rsp, 8
    cmp     ecx, 1
    jb      .ret
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    movzx   edi, byte [rdx]
    call    quests_bump
.ret:
    add     rsp, 8
    ret

; nx_on_quest_complete(edi slot, esi type, rdx payload, ecx len): a guest hands in the quest. Only the one on offer, accepted,
; with its goal reached (a Q_BRING quest's items were taken from his inventory, which only he can show) is done: the chain
; moves on and every player is rewarded, once (quests_settle). Anything else gets the position back (QUEST_SYNC) and, when
; the quest he handed in was a Q_BRING one (a stale hand-in: somebody else was first, or it was not accepted), the items he
; took before asking (quests_refund: GIVE), so a second simultaneous hand-in loses nothing.
; ebx = the quest, r12d = the guest's slot
nx_on_quest_complete:
    push    rbx
    push    r12
    sub     rsp, 8
    cmp     ecx, 1
    jb      .ret
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    mov     r12d, edi
    movzx   ebx, byte [rdx]
    cmp     bl, [rpg_state + RPGSAVE.quest]
    jne     .refuse
    cmp     byte [rpg_state + RPGSAVE.quest_state], 1
    jne     .refuse
    call    quests_current
    test    rax, rax
    jz      .refuse
    cmp     dword [rax + QUESTINFO.type], Q_BRING
    je      .done
    movzx   ecx, word [rpg_state + RPGSAVE.quest_progress]
    cmp     ecx, [rax + QUESTINFO.count]
    jb      .refuse
.done:
    mov     edi, ebx
    call    quests_settle
    jmp     .ret
.refuse:
    mov     edi, r12d
    mov     esi, ebx
    call    quests_refund
    call    net_quest_sync_out
.ret:
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; nx_on_quest_reward(edi slot, esi type, rdx payload, ecx len): the host says a quest was handed in: this player is paid
nx_on_quest_reward:
    sub     rsp, 8
    cmp     ecx, 1
    jb      .ret
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    movzx   edi, byte [rdx]
    call    quests_reward
.ret:
    add     rsp, 8
    ret

; ---- drops --------------------------------------------------------------------------------------------------------------

; net_drop_flush() -> eax 1 when a guest's staging slot (the last drop) is free: what a guest's drops_spawn made there is sent to
; the host (DROP_SPAWN with its velocity and delay) and the slot is cleared; the host's snapshots bring it back. 0 when it
; could not be sent (the slot keeps it for the next step). Anything but a guest: 1.
; rbx = the staging slot; frame: DROPMSG @0
net_drop_flush:
    cmp     byte [net_role], NET_ROLE_GUEST
    je      .guest
    mov     eax, 1
    ret
.guest:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 56
    lea     rbx, [drops + (MAX_DROPS - 1) * DROP_size]
    mov     eax, 1
    cmp     byte [rbx + DROP.id], 0
    je      .ret
    mov     al, [rbx + DROP.id]
    mov     [rsp + DROPMSG.id], al
    mov     al, [rbx + DROP.count]
    mov     [rsp + DROPMSG.count], al
    mov     ax, [rbx + DROP.dmg]
    mov     [rsp + DROPMSG.dmg], ax
    mov     eax, [rbx + DROP.delay]
    mov     ecx, 0xFFFF
    cmp     eax, ecx
    cmova   eax, ecx
    mov     [rsp + DROPMSG.delay], ax
    mov     word [rsp + DROPMSG.pad], 0
    mov     eax, [rbx + DROP.vx]
    mov     [rsp + DROPMSG.vx], eax
    mov     eax, [rbx + DROP.vy]
    mov     [rsp + DROPMSG.vy], eax
    mov     eax, [rbx + DROP.vz]
    mov     [rsp + DROPMSG.vz], eax
    lea     rdi, [rsp + DROPMSG.pos]
    movss   xmm0, [rbx + DROP.x]
    movss   xmm1, [rbx + DROP.y]
    movss   xmm2, [rbx + DROP.z]
    call    net_pos_out
    mov     edi, MT_DROP_SPAWN
    mov     rsi, rsp
    mov     edx, DROPMSG_size
    mov     ecx, 1
    call    net_out
    test    eax, eax
    jz      .ret
    mov     byte [rbx + DROP.id], 0
    mov     eax, 1
.ret:
    add     rsp, 56
    pop     rbx
    pop     rbp
    ret

; nx_on_drop_spawn(edi slot, esi type, rdx payload, ecx len): the host makes a guest's drop, with the velocity and the pickup
; delay the guest gave it (a velocity that is not a sane number is not applied)
; rbx = the message
nx_on_drop_spawn:
    push    rbx
    cmp     ecx, DROPMSG_size
    jb      .ret
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    mov     rbx, rdx
    mov     eax, [rbx + DROPMSG.pos + NPOS.y]
    and     eax, 0x7FFFFFFF
    cmp     eax, BITS_Y
    ja      .ret
    lea     rdi, [rbx + DROPMSG.pos]
    call    net_pos_in
    movzx   edi, byte [rbx + DROPMSG.id]
    movzx   esi, byte [rbx + DROPMSG.count]
    movzx   edx, word [rbx + DROPMSG.dmg]
    call    drops_spawn
    test    eax, eax
    js      .ret
    imul    eax, eax, DROP_size
    lea     rcx, [drops]
    add     rcx, rax
    movzx   eax, word [rbx + DROPMSG.delay]
    mov     [rcx + DROP.delay], eax
    mov     eax, [rbx + DROPMSG.vx]
    and     eax, 0x7FFFFFFF
    cmp     eax, BITS_V
    ja      .ret
    mov     eax, [rbx + DROPMSG.vy]
    and     eax, 0x7FFFFFFF
    cmp     eax, BITS_V
    ja      .ret
    mov     eax, [rbx + DROPMSG.vz]
    and     eax, 0x7FFFFFFF
    cmp     eax, BITS_V
    ja      .ret
    mov     eax, [rbx + DROPMSG.vx]
    mov     [rcx + DROP.vx], eax
    mov     eax, [rbx + DROPMSG.vy]
    mov     [rcx + DROP.vy], eax
    mov     eax, [rbx + DROPMSG.vz]
    mov     [rcx + DROP.vz], eax
.ret:
    pop     rbx
    ret

; net_give_out(edi slot, esi id, edx count, ecx dmg) -> eax 1 when queued: the host hands a remote player the stack he walked
; over (GIVE)
; frame: {id u8, count u8, dmg u16}
net_give_out:
    sub     rsp, 24
    mov     [rsp], sil
    mov     [rsp + 1], dl
    mov     [rsp + 2], cx
    mov     esi, MT_GIVE
    mov     rdx, rsp
    mov     ecx, 4
    mov     r8d, 1
    call    net_send_to
    add     rsp, 24
    ret

; nx_on_give(edi slot, esi type, rdx payload, ecx len): a guest gets what the host's drop held: what fits goes into the
; inventory (pop sound), the rest drops at his feet again with a delay of 2 s, so it is not handed back at once.
; ebx = id, r12d = what is left, r13d = dmg, r14d = the count given
nx_on_give:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    cmp     ecx, 4
    jb      .ret
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    movzx   ebx, byte [rdx]
    movzx   r14d, byte [rdx + 1]
    movzx   r13d, word [rdx + 2]
    cmp     ebx, NUM_ITEMS
    jae     .ret
    test    r14d, r14d
    jz      .ret
    mov     edi, ebx
    mov     esi, r14d
    mov     edx, r13d
    call    inv_add_dmg
    mov     r12d, eax
    cmp     r12d, r14d
    jae     .none_fit
    mov     edi, SND_POP
    movss   xmm0, [c_pop_vol]
    call    audio_play
.none_fit:
    test    r12d, r12d
    jz      .ret
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    movss   xmm0, [player + BODY.x]
    movss   xmm1, [player + BODY.y]
    addss   xmm1, [c_drop_y]
    movss   xmm2, [player + BODY.z]
    call    drops_spawn
    test    eax, eax
    js      .ret
    imul    eax, eax, DROP_size
    lea     rcx, [drops]
    mov     dword [rcx + rax + DROP.delay], GIVE_DELAY
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- sleep ----------------------------------------------------------------------------------------------------------------

; net_all_asleep() -> eax 1 when every other player in the world lies in bed and is ready for the morning (PS_ASLEEP in his
; PSTATE): the READY peers but the local one, whose sleep the caller knows. No other player: 1.
net_all_asleep:
    xor     ecx, ecx
    lea     rdx, [net_peers]
.slot:
    movzx   eax, byte [net_self]
    cmp     ecx, eax
    je      .next
    cmp     dword [rdx + PEER.state], PEER_READY
    jne     .next
    test    word [rdx + PEER.ps + PSTATE.flags], PS_ASLEEP
    jz      .no
.next:
    add     rdx, PEER_size
    inc     ecx
    cmp     ecx, NET_MAX_PEERS
    jb      .slot
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; ---- explosions -----------------------------------------------------------------------------------------------------------

; net_explosion_players(xmm0..2 centre, xmm3 radius): the blast of explode_at (radius r, the damage scales with r / 3) is
; felt by every other READY, living player within 2r of his chest: ceil(f * base * r / 3 * k), f = 1 - d / 2r, base by the
; difficulty (explode_base_dmg) and k = explode_dmg_mult (a creeper's) else his max health / 20 - the local player's rule.
; TNT and creepers (explode_pvp 0) hurt every player, but only the host sends it; a player's own rocket or grenade
; (explode_pvp 1) hurts the others only with PvP on, whoever fired it. The host sends each one HURT (HM_DIRECT, knockback
; 12 f, hop 6 f); a guest has no way to HURT someone else, so his blow goes as PVP_HIT through the host.
; r12d = the slot, rbx = his record, r13d = the damage; frame: centre @0, r @12, 2r @16, r / 3 @20, base @24, f @28,
; the blast as an NPOS @32, PVPMSG @48
net_explosion_players:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 96
    cmp     byte [net_role], NET_ROLE_OFF
    je      .ret
    cmp     byte [explode_pvp], 0
    je      .world
    cmp     byte [net_pvp], 0
    je      .ret                        ; a player's weapon: only with PvP on
    jmp     .go
.world:
    cmp     byte [net_role], NET_ROLE_GUEST
    je      .ret                        ; TNT and creepers are the host's
.go:
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 8], xmm2
    movss   [rsp + 12], xmm3
    movaps  xmm4, xmm3
    addss   xmm4, xmm4
    movss   [rsp + 16], xmm4
    divss   xmm3, [c_three]
    movss   [rsp + 20], xmm3
    mov     eax, [settings + SETTINGS.difficulty]
    mov     ecx, DIFF_HARD
    cmp     eax, ecx
    cmova   eax, ecx
    lea     rcx, [explode_base_dmg]
    cvtsi2ss xmm0, dword [rcx + rax*4]
    movss   [rsp + 24], xmm0
    xor     r12d, r12d
.peer:
    movzx   eax, byte [net_self]
    cmp     r12d, eax
    je      .next
    imul    eax, r12d, PEER_size
    lea     rbx, [net_peers]
    add     rbx, rax
    cmp     dword [rbx + PEER.state], PEER_READY
    jne     .next
    test    word [rbx + PEER.ps + PSTATE.flags], PS_DEAD
    jnz     .next
    movss   xmm0, [rbx + PEER.body + BODY.x]
    subss   xmm0, [rsp]
    movss   xmm1, [rbx + PEER.body + BODY.y]
    addss   xmm1, [c_chest]
    subss   xmm1, [rsp + 4]
    movss   xmm2, [rbx + PEER.body + BODY.z]
    subss   xmm2, [rsp + 8]
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    mulss   xmm2, xmm2
    addss   xmm0, xmm1
    addss   xmm0, xmm2
    sqrtss  xmm0, xmm0                  ; d
    comiss  xmm0, [rsp + 16]
    jae     .next                       ; out of range
    divss   xmm0, [rsp + 16]
    movss   xmm1, [c_one]
    subss   xmm1, xmm0                  ; f
    movss   [rsp + 28], xmm1
    movss   xmm0, [rsp + 24]
    mulss   xmm0, xmm1
    mulss   xmm0, [rsp + 20]
    movss   xmm2, [explode_dmg_mult]    ; the creeper's factor, else his max health / 20
    xorps   xmm3, xmm3
    comiss  xmm2, xmm3
    ja      .have_mult
    movzx   eax, word [rbx + PEER.ps + PSTATE.max_health]
    cvtsi2ss xmm2, eax
    divss   xmm2, [c_twenty]
.have_mult:
    mulss   xmm0, xmm2
    roundss xmm0, xmm0, 10              ; ceil
    cvttss2si r13d, xmm0
    test    r13d, r13d
    jle     .next
    cmp     byte [net_role], NET_ROLE_GUEST
    je      .pvp
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, CAUSE_EXPLOSION
    mov     ecx, 255                    ; no mob, no status
    mov     r8d, 255
    xor     r9d, r9d
    movss   xmm0, [rsp]                 ; the blast is where the blow comes from
    movss   xmm1, [rsp + 8]
    movss   xmm2, [rsp + 28]
    mulss   xmm2, [c_kb]
    movss   xmm3, [rsp + 28]
    mulss   xmm3, [c_hop]
    call    net_hurt_send_direct
    jmp     .next
.pvp:
    lea     rdi, [rsp + 32]
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    call    net_pos_out
    mov     [rsp + 48 + PVPMSG.victim], r12b
    movzx   eax, byte [net_self]
    mov     [rsp + 48 + PVPMSG.attacker], al
    mov     byte [rsp + 48 + PVPMSG.sts], 255
    mov     byte [rsp + 48 + PVPMSG.pad], 0
    mov     [rsp + 48 + PVPMSG.amount], r13d
    mov     dword [rsp + 48 + PVPMSG.sts_mag], 0
    mov     eax, [rsp + 32 + NPOS.ax]
    mov     [rsp + 48 + PVPMSG.src_ax], eax
    mov     eax, [rsp + 32 + NPOS.az]
    mov     [rsp + 48 + PVPMSG.src_az], eax
    mov     ax, [rsp + 32 + NPOS.fx]
    mov     [rsp + 48 + PVPMSG.src_fx], ax
    mov     ax, [rsp + 32 + NPOS.fz]
    mov     [rsp + 48 + PVPMSG.src_fz], ax
    movss   xmm0, [rsp + 28]
    mulss   xmm0, [c_kb]
    movss   [rsp + 48 + PVPMSG.kb], xmm0
    mov     edi, MT_PVP_HIT
    lea     rsi, [rsp + 48]
    mov     edx, PVPMSG_size
    mov     ecx, 1
    call    net_out
.next:
    inc     r12d
    cmp     r12d, NET_MAX_PEERS
    jb      .peer
.ret:
    add     rsp, 96
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; net_spell_beam_out(rdi start float[3], rsi dir float[3], xmm0 length, edx element ELEM_*): a Laser beam cast here is drawn
; on the other peers (a guest sends it to the host; the host to the guests within 64 blocks). Nothing is checked or paid
; there: it is only the picture; the blows were struck here.
; rbx = start; frame: SPELLMSG @0, start local @40
net_spell_beam_out:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 56
    cmp     byte [net_role], NET_ROLE_OFF
    je      .ret
    mov     rbx, rdi
    mov     byte [rsp + SPELLMSG.kind], SPM_BEAM
    mov     [rsp + SPELLMSG.elem], dl
    mov     word [rsp + SPELLMSG.pad], 0
    movss   [rsp + SPELLMSG.len], xmm0
    mov     eax, [rsi]
    mov     [rsp + SPELLMSG.dir], eax
    mov     eax, [rsi + 4]
    mov     [rsp + SPELLMSG.dir + 4], eax
    mov     eax, [rsi + 8]
    mov     [rsp + SPELLMSG.dir + 8], eax
    movss   xmm0, [rbx]
    movss   [rsp + 40], xmm0
    movss   xmm1, [rbx + 4]
    movss   [rsp + 44], xmm1
    movss   xmm2, [rbx + 8]
    movss   [rsp + 48], xmm2
    lea     rdi, [rsp + SPELLMSG.pos]
    call    net_pos_out
    cmp     byte [net_role], NET_ROLE_HOST
    je      .host
    mov     edi, MT_SPELL
    mov     rsi, rsp
    mov     edx, SPELLMSG_size
    xor     ecx, ecx
    call    net_out
    jmp     .ret
.host:
    mov     edi, -1
    mov     esi, MT_SPELL
    mov     rdx, rsp
    mov     ecx, SPELLMSG_size
    xor     r8d, r8d
    movss   xmm0, [rsp + 40]
    movss   xmm1, [rsp + 44]
    movss   xmm2, [rsp + 48]
    movss   xmm3, [c_fx_range]
    call    net_relay
.ret:
    add     rsp, 56
    pop     rbx
    pop     rbp
    ret

; nx_on_spell(edi slot, esi type, rdx payload, ecx len): another peer's Laser beam is drawn here (net_applying keeps the motes
; from being sent on) and the host passes a guest's on to the other guests within 64 blocks. Dropped: a message that is
; short, not a beam, of an element above poison, longer than 24.5 blocks (or no length at all), with a direction component
; beyond 1.01 or an impossible height; and, at the host, more than SPELL_RATE beams a second from one guest.
; rbx = the message, r12d = the sender's slot, r13d = its length; frame: local position @0
nx_on_spell:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 24
    cmp     ecx, SPELLMSG_size
    jb      .ret
    cmp     byte [net_role], NET_ROLE_OFF
    je      .ret
    mov     rbx, rdx
    mov     r12d, edi
    mov     r13d, ecx
    cmp     byte [rbx + SPELLMSG.kind], SPM_BEAM
    jne     .ret
    cmp     byte [rbx + SPELLMSG.elem], ELEM_POISON
    ja      .ret
    movss   xmm0, [rbx + SPELLMSG.len]
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jbe     .ret                        ; no length, or not a number
    comiss  xmm0, [c_beam_max]
    ja      .ret
%assign d 0
%rep 3
    mov     eax, [rbx + SPELLMSG.dir + d]
    and     eax, 0x7FFFFFFF
    cmp     eax, BITS_DIR
    ja      .ret
%assign d d + 4
%endrep
    mov     eax, [rbx + SPELLMSG.pos + NPOS.y]
    and     eax, 0x7FFFFFFF
    cmp     eax, BITS_Y
    ja      .ret
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .unlimited                  ; (a guest hears the host's, which are limited at the host's end)
    cmp     r12d, NET_MAX_PEERS
    jae     .ret
    lea     rdi, [spell_in]
    lea     rdi, [rdi + r12*8]
    mov     esi, SPELL_RATE
    call    rate_ok
    test    eax, eax
    jz      .ret
.unlimited:
    lea     rdi, [rbx + SPELLMSG.pos]
    call    net_pos_in
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 8], xmm2
    lea     rdi, [rsp]
    lea     rsi, [rbx + SPELLMSG.dir]
    movss   xmm0, [rbx + SPELLMSG.len]
    movzx   edx, byte [rbx + SPELLMSG.elem]
    call    spells_beam_fx
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    mov     edi, r12d
    mov     esi, MT_SPELL
    mov     rdx, rbx
    mov     ecx, r13d
    xor     r8d, r8d
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    movss   xmm3, [c_fx_range]
    call    net_relay
.ret:
    add     rsp, 24
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
