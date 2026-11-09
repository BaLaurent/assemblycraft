; test_netsync.asm - the multiplayer session layer's tests: a position on the wire is absolute (exact to 1/32768
; under one origin, the same point under another origin), a character's image (the first PLAYER_IMG_SIZE bytes of
; a header image) holds the whole character, a hosted world's directory can be deleted with the characters of its
; guests in it, a guest that becomes ready is brought up to date (standings, quest chain, PvP), closing the
; multiplayer frees the boats, a --join of the command line ends with its join, and a name held by a dead
; connection can be taken over by its player coming back.
%include "common.inc"
default rel

global test_net_pos_roundtrip, test_net_player_image_roundtrip
global test_world_delete_with_players, test_net_ready_resync, test_net_host_close_boats
global test_net_cli_join_cleared, test_net_rejoin_takeover, test_net_wait_ends_with_session

extern net_pos_out, net_pos_in, world_origin_x, world_origin_z
extern game_player_save, game_player_load, game_mode
extern world_header, player, surv, surv_max_health, inv, inv_sel
extern rpg_state, rpg_ext, rpg_reset, rpg_recompute, debug_stat_bonus
extern file_write_atomic, file_stat_mtime, mkdir_p, dir_remove_tree, str_copy
extern net_role, net_self, net_pvp, net_in_world, net_peers, net_rdist_cap, net_winfo, net_session_reset
extern net_capture, net_captured, netsync_dispatch, net_host_open, net_host_close, net_cfg_server
extern app_world_path, boat_rider
extern net_cli_join, net_join_exit, net_join_failed, net_join_active, net_session_name, net_join_target
extern net_join_begin, net_join_cancel
extern net_pump_now, net_peer_rx, net_peer_addr, net_peer_replaceable
extern app_wait_net, net_end_reason

section .rodata
align 16
k_abs_mask:   dq 0x7FFFFFFFFFFFFFFF, 0
k_tol:        dq 0.000030517578125              ; 1/32768
k_ulp:        dq 5.9604644775390625e-08         ; 2^-24: half a float32 step is at most |value| times this
align 4
; local positions (x, y, z)
k_pos:
    dd 0.5, 70.0, 0.5
    dd -1000.25, 5.0, 12345.75
    dd 8191.9, 255.0, -8191.9
; origins (x, z)
k_org:
    dd 0, 0
    dd -1024, 512
    dd 1048576, -1048576
m_v6:         db "ACRAFT06"

section .bss
alignb 16
npos:         resb NPOS_size
alignb 16
img_buf:      resb WORLD_HDR_SIZE
bk_hdr:       resb WORLD_HDR_SIZE
bk_player:    resb BODY_size
bk_inv:       resb INVENTORY_size
bk_surv:      resb SURVIVAL_size
bk_rpg:       resb RPGSAVE_size
bk_rpgx:      resb RPGEXT_size
bk_dbg:       resb NUM_STATS * 2
bk_misc:      resd 6                            ; origin x, z, game_mode, inv_sel, surv_max_health

section .text

; rt_one(edi position index, esi origin a, edx origin b) -> eax 0 ok / 1 failed
; The position goes out under origin a and comes back in under origin b: y is exact, and the absolute x and z
; (local plus origin) are the same point to within 1/32768 - under another origin plus half a float32 step of
; the shifted value, the most a float position can hold there.
; r14 = the position, r12d = a, r13d = b
rt_one:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    imul    eax, edi, 12
    lea     r14, [k_pos]
    add     r14, rax
    mov     r12d, esi
    mov     r13d, edx
    lea     rax, [k_org]
    mov     ecx, [rax + r12*8]
    mov     [world_origin_x], ecx
    mov     ecx, [rax + r12*8 + 4]
    mov     [world_origin_z], ecx
    lea     rdi, [npos]
    movss   xmm0, [r14]
    movss   xmm1, [r14 + 4]
    movss   xmm2, [r14 + 8]
    call    net_pos_out
    lea     rax, [k_org]
    mov     ecx, [rax + r13*8]
    mov     [world_origin_x], ecx
    mov     ecx, [rax + r13*8 + 4]
    mov     [world_origin_z], ecx
    lea     rdi, [npos]
    call    net_pos_in                          ; xmm0 x, xmm1 y, xmm2 z
    ucomiss xmm1, [r14 + 4]
    jne     .fail
    jp      .fail
    lea     rax, [k_org]
    cvtss2sd xmm6, xmm0                         ; x2 and z2 as doubles
    cvtss2sd xmm7, xmm2
    movaps  xmm0, xmm6                          ; x: (x2 + origin b) - (x + origin a)
    cvtsi2sd xmm3, dword [rax + r13*8]
    addsd   xmm0, xmm3
    cvtss2sd xmm4, dword [r14]
    cvtsi2sd xmm3, dword [rax + r12*8]
    addsd   xmm4, xmm3
    subsd   xmm0, xmm4
    andpd   xmm0, [k_abs_mask]
    movsd   xmm5, [k_tol]
    cmp     r12d, r13d
    je      .x_tol
    movaps  xmm3, xmm6
    andpd   xmm3, [k_abs_mask]
    mulsd   xmm3, [k_ulp]
    addsd   xmm5, xmm3
.x_tol:
    comisd  xmm0, xmm5
    jae     .fail
    movaps  xmm2, xmm7                          ; the same for z
    cvtsi2sd xmm3, dword [rax + r13*8 + 4]
    addsd   xmm2, xmm3
    cvtss2sd xmm4, dword [r14 + 8]
    cvtsi2sd xmm3, dword [rax + r12*8 + 4]
    addsd   xmm4, xmm3
    subsd   xmm2, xmm4
    andpd   xmm2, [k_abs_mask]
    movsd   xmm5, [k_tol]
    cmp     r12d, r13d
    je      .z_tol
    movaps  xmm3, xmm7
    andpd   xmm3, [k_abs_mask]
    mulsd   xmm3, [k_ulp]
    addsd   xmm5, xmm3
.z_tol:
    comisd  xmm2, xmm5
    jae     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; test_net_pos_roundtrip: every position goes out under every origin and comes in under the same or another one.
; Under the same origin the error stays below 1/32768; across origins the point is the same (rt_one); and the
; NPOS fields are what the wire format says
test_net_pos_roundtrip:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r14d, [world_origin_x]              ; r14 = the caller's origin x (z is on the stack below)
    push    qword [world_origin_z]
    sub     rsp, 8
    xor     ebx, ebx                            ; position
.p:
    xor     r12d, r12d                          ; origin out
.a:
    xor     r13d, r13d                          ; origin in
.b:
.run:
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    call    rt_one
    test    eax, eax
    jnz     .fail
.next:
    inc     r13d
    cmp     r13d, 3
    jb      .b
    inc     r12d
    cmp     r12d, 3
    jb      .a
    inc     ebx
    cmp     ebx, 3
    jb      .p
    ; the fields themselves: (0.5, 70, 0.5) under origin (0, 0)
    mov     dword [world_origin_x], 0
    mov     dword [world_origin_z], 0
    lea     rdi, [npos]
    movss   xmm0, [k_pos]
    movss   xmm1, [k_pos + 4]
    movss   xmm2, [k_pos + 8]
    call    net_pos_out
    cmp     dword [npos + NPOS.ax], 0
    jne     .fail
    cmp     dword [npos + NPOS.az], 0
    jne     .fail
    cmp     word [npos + NPOS.fx], 32768
    jne     .fail
    cmp     word [npos + NPOS.fz], 32768
    jne     .fail
    cmp     dword [npos + NPOS.y], __float32__(70.0)
    jne     .fail
    ; (-1000.25, 5, 12345.75) under origin (-1024, 512): x = -2024.25, z = 12857.75
    mov     dword [world_origin_x], -1024
    mov     dword [world_origin_z], 512
    lea     rdi, [npos]
    movss   xmm0, [k_pos + 12]
    movss   xmm1, [k_pos + 16]
    movss   xmm2, [k_pos + 20]
    call    net_pos_out
    cmp     dword [npos + NPOS.ax], -2025
    jne     .fail
    cmp     dword [npos + NPOS.az], 12857
    jne     .fail
    cmp     word [npos + NPOS.fx], 49152
    jne     .fail
    cmp     word [npos + NPOS.fz], 49152
    jne     .fail
    cmp     dword [npos + NPOS.y], __float32__(5.0)
    jne     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    add     rsp, 8
    pop     rcx
    mov     [world_origin_z], ecx
    mov     [world_origin_x], r14d
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

%macro COPY 3                                   ; COPY dst, src, bytes
    lea     rdi, [%1]
    lea     rsi, [%2]
    mov     ecx, %3
    rep     movsb
%endmacro

%macro WIPE 2                                   ; WIPE dst, bytes
    lea     rdi, [%1]
    mov     ecx, %2
    xor     eax, eax
    rep     stosb
%endmacro

; the character, saved into a header image and loaded back after everything was wiped: inventory, armor, a ring,
; the RPG record (level, XP, quest), health and food, position and angles, hotbar choice, origin and bed. The
; image must not reach past PLAYER_IMG_SIZE bytes.
test_net_player_image_roundtrip:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    COPY    bk_hdr, world_header, WORLD_HDR_SIZE        ; what the test touches, kept
    COPY    bk_player, player, BODY_size
    COPY    bk_inv, inv, INVENTORY_size
    COPY    bk_surv, surv, SURVIVAL_size
    COPY    bk_rpg, rpg_state, RPGSAVE_size
    COPY    bk_rpgx, rpg_ext, RPGEXT_size
    COPY    bk_dbg, debug_stat_bonus, NUM_STATS * 2
    mov     eax, [world_origin_x]
    mov     [bk_misc], eax
    mov     eax, [world_origin_z]
    mov     [bk_misc + 4], eax
    mov     eax, [game_mode]
    mov     [bk_misc + 8], eax
    mov     eax, [inv_sel]
    mov     [bk_misc + 12], eax
    mov     eax, [surv_max_health]
    mov     [bk_misc + 16], eax
    mov     dword [game_mode], MODE_SURVIVAL
    call    rpg_reset
    mov     byte [rpg_state + RPGSAVE.level], 12
    mov     dword [rpg_state + RPGSAVE.xp], 40
    mov     byte [rpg_state + RPGSAVE.quest], 3
    mov     byte [rpg_state + RPGSAVE.quest_state], 1
    mov     word [rpg_state + RPGSAVE.quest_progress], 2
    WIPE    inv, INVENTORY_size
    lea     rax, [inv + INVENTORY.slots + 3*4]
    mov     byte [rax + ITEMSTACK.id], STONE_PICKAXE
    mov     byte [rax + ITEMSTACK.count], 1
    mov     word [rax + ITEMSTACK.dmg], 7
    lea     rax, [inv + INVENTORY.slots + 10*4]
    mov     byte [rax + ITEMSTACK.id], APPLE
    mov     byte [rax + ITEMSTACK.count], 7
    lea     rax, [inv + INVENTORY.armor + 1*4]
    mov     byte [rax + ITEMSTACK.id], IRON_CHESTPLATE
    mov     byte [rax + ITEMSTACK.count], 1
    mov     word [rax + ITEMSTACK.dmg], 3
    lea     rax, [inv + INVENTORY.jewelry + 0*4]        ; a rare ring (rarity 2, tier 3, seed 5)
    mov     byte [rax + ITEMSTACK.id], RING
    mov     byte [rax + ITEMSTACK.count], 1
    mov     word [rax + ITEMSTACK.dmg], 0x8C05
    mov     dword [inv_sel], 4
    call    rpg_recompute
    mov     dword [surv + SURVIVAL.health], 13
    mov     dword [surv + SURVIVAL.food], 11
    mov     dword [surv + SURVIVAL.saturation], __float32__(3.5)
    mov     dword [surv + SURVIVAL.exhaustion], __float32__(0.25)
    mov     dword [surv + SURVIVAL.breath], 400
    mov     dword [world_origin_x], 1024
    mov     dword [world_origin_z], -512
    mov     dword [player + BODY.x], __float32__(12.5)
    mov     dword [player + BODY.y], __float32__(70.0)
    mov     dword [player + BODY.z], __float32__(-3.25)
    mov     dword [player + BODY.yaw], __float32__(90.0)
    mov     dword [player + BODY.pitch], __float32__(10.0)
    mov     dword [world_header + WORLDHDR.bed_x], 1234
    mov     dword [world_header + WORLDHDR.bed_y], 70
    mov     dword [world_header + WORLDHDR.bed_z], -567
    mov     dword [world_header + WORLDHDR.bed_set], 1
    WIPE    img_buf, WORLD_HDR_SIZE
    lea     rdi, [img_buf]
    call    game_player_save
    mov     rax, [m_v6]                                 ; the image is a header image ...
    cmp     [img_buf], rax
    jne     .fail
    xor     ebx, ebx                                    ; ... that ends at PLAYER_IMG_SIZE
.tail:
    cmp     qword [img_buf + PLAYER_IMG_SIZE + rbx*8], 0
    jne     .fail
    inc     ebx
    cmp     ebx, 16
    jb      .tail
    WIPE    player, BODY_size                           ; everything gone
    WIPE    inv, INVENTORY_size
    WIPE    surv, SURVIVAL_size
    WIPE    rpg_state, RPGSAVE_size
    WIPE    rpg_ext, RPGEXT_size
    WIPE    world_header, WORLD_HDR_SIZE
    mov     dword [inv_sel], 0
    mov     dword [world_origin_x], 0
    mov     dword [world_origin_z], 0
    lea     rdi, [img_buf]
    call    game_player_load
    test    eax, eax
    jnz     .fail                                       ; (a live player at a good position: no respawn)
    cmp     dword [world_origin_x], 1024
    jne     .fail
    cmp     dword [world_origin_z], -512
    jne     .fail
    cmp     dword [player + BODY.x], __float32__(12.5)
    jne     .fail
    cmp     dword [player + BODY.y], __float32__(70.0)
    jne     .fail
    cmp     dword [player + BODY.z], __float32__(-3.25)
    jne     .fail
    cmp     dword [player + BODY.yaw], __float32__(90.0)
    jne     .fail
    cmp     dword [player + BODY.pitch], __float32__(10.0)
    jne     .fail
    cmp     dword [inv_sel], 4
    jne     .fail
    lea     rax, [inv + INVENTORY.slots + 3*4]
    cmp     byte [rax + ITEMSTACK.id], STONE_PICKAXE
    jne     .fail
    cmp     byte [rax + ITEMSTACK.count], 1
    jne     .fail
    cmp     word [rax + ITEMSTACK.dmg], 7
    jne     .fail
    lea     rax, [inv + INVENTORY.slots + 10*4]
    cmp     byte [rax + ITEMSTACK.id], APPLE
    jne     .fail
    cmp     byte [rax + ITEMSTACK.count], 7
    jne     .fail
    lea     rax, [inv + INVENTORY.armor + 1*4]
    cmp     byte [rax + ITEMSTACK.id], IRON_CHESTPLATE
    jne     .fail
    cmp     word [rax + ITEMSTACK.dmg], 3
    jne     .fail
    lea     rax, [inv + INVENTORY.jewelry + 0*4]
    cmp     byte [rax + ITEMSTACK.id], RING
    jne     .fail
    cmp     word [rax + ITEMSTACK.dmg], 0x8C05
    jne     .fail
    cmp     byte [rpg_state + RPGSAVE.level], 12
    jne     .fail
    cmp     dword [rpg_state + RPGSAVE.xp], 40
    jne     .fail
    cmp     byte [rpg_state + RPGSAVE.quest], 3
    jne     .fail
    cmp     byte [rpg_state + RPGSAVE.quest_state], 1
    jne     .fail
    cmp     word [rpg_state + RPGSAVE.quest_progress], 2
    jne     .fail
    cmp     dword [surv + SURVIVAL.health], 13
    jne     .fail
    cmp     dword [surv + SURVIVAL.food], 11
    jne     .fail
    cmp     dword [surv + SURVIVAL.breath], 400
    jne     .fail
    cmp     dword [world_header + WORLDHDR.bed_x], 1234
    jne     .fail
    cmp     dword [world_header + WORLDHDR.bed_y], 70
    jne     .fail
    cmp     dword [world_header + WORLDHDR.bed_z], -567
    jne     .fail
    cmp     dword [world_header + WORLDHDR.bed_set], 1
    jne     .fail
    xor     ebx, ebx
    jmp     .restore
.fail:
    mov     ebx, 1
.restore:
    COPY    world_header, bk_hdr, WORLD_HDR_SIZE
    COPY    player, bk_player, BODY_size
    COPY    inv, bk_inv, INVENTORY_size
    COPY    surv, bk_surv, SURVIVAL_size
    COPY    rpg_state, bk_rpg, RPGSAVE_size
    COPY    rpg_ext, bk_rpgx, RPGEXT_size
    COPY    debug_stat_bonus, bk_dbg, NUM_STATS * 2
    mov     eax, [bk_misc]
    mov     [world_origin_x], eax
    mov     eax, [bk_misc + 4]
    mov     [world_origin_z], eax
    mov     eax, [bk_misc + 8]
    mov     [game_mode], eax
    mov     eax, [bk_misc + 12]
    mov     [inv_sel], eax
    call    rpg_recompute                               ; the derived stats follow the restored record
    mov     eax, [bk_misc + 16]
    mov     [surv_max_health], eax
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ==============================================================================================================
; the review fixes of round 1
; ==============================================================================================================

section .rodata
d_wd_root:    db "/tmp/assemblycraft-selftest-netsync-wd", 0
d_wd_reg:     db "/tmp/assemblycraft-selftest-netsync-wd/regions", 0
d_wd_pl:      db "/tmp/assemblycraft-selftest-netsync-wd/players", 0
f_wd_world:   db "/tmp/assemblycraft-selftest-netsync-wd/world.acw", 0
f_wd_region:  db "/tmp/assemblycraft-selftest-netsync-wd/regions/r.0.0.acr", 0
f_wd_bob:     db "/tmp/assemblycraft-selftest-netsync-wd/players/Bob.hdr", 0
d_hc_root:    db "/tmp/assemblycraft-selftest-netsync-hc", 0
s_bob:        db "Bob", 0
s_data:       db "data", 0
t_bad:        db "1.2.3", 0                      ; a dotted target that is no address: the join fails at once
t_bad2:       db "1.2.3", 0                      ; the same text in another place (typed on the join screen)
t_local:      db "127.0.0.1:1", 0                ; a real attempt, at a port nobody listens on
align 2
k_standing:   dw 100, -200, 300, 400, 500, 0, 0, 0
%define WINFO_PVP 45                             ; WORLDINFO.pvp (seed, mode, time and the 33-byte name come first)

section .bss
alignb 16
t_pst:        resb PSTATE_size
t_capbuf:     resb 512
t_ev:         resb NETEVENT_size
t_bk_peers:   resb PEER_size * NET_MAX_PEERS
t_bk_stand:   resb 16
t_bk_path:    resb 4096
t_bk_sname:   resb 20
t_bk_jtarget: resb 64
t_bk_boats:   resb MAX_BOATS
t_bk_misc:    resb 32                            ; saved scalars (the layout is each test's own)
t_bk_q:       resq 8
t_one:        resb 8
t_path:       resb 128                          ; a path in memory mkdir_p may write to

section .text

; mk_dir(rdi path zstr) -> eax mkdir_p's answer: the path is copied to where mkdir_p may write (the literals are
; read-only)
mk_dir:
    push    rbp
    mov     rbp, rsp
    mov     rsi, rdi
    lea     rdi, [t_path]
    mov     edx, 127
    call    str_copy
    lea     rdi, [t_path]
    call    mkdir_p
    pop     rbp
    ret

; test_world_delete_with_players: a world that was ever hosted has <world>/players holding its guests'
; characters; deleting the world (dir_remove_tree, which saves.asm's delete uses) must take that directory, its
; files, the regions and the world file with it - 0 back, nothing left
test_world_delete_with_players:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    lea     rdi, [d_wd_root]
    call    dir_remove_tree                             ; (what an earlier run may have left)
    lea     rdi, [d_wd_reg]
    call    mk_dir
    test    eax, eax
    jnz     .fail
    lea     rdi, [d_wd_pl]
    call    mk_dir
    test    eax, eax
    jnz     .fail
    lea     rdi, [f_wd_world]
    lea     rsi, [s_data]
    mov     edx, 4
    call    file_write_atomic
    test    eax, eax
    jnz     .fail
    lea     rdi, [f_wd_region]
    lea     rsi, [s_data]
    mov     edx, 4
    call    file_write_atomic
    test    eax, eax
    jnz     .fail
    lea     rdi, [f_wd_bob]
    lea     rsi, [s_data]
    mov     edx, 4
    call    file_write_atomic
    test    eax, eax
    jnz     .fail
    lea     rdi, [d_wd_root]
    call    dir_remove_tree
    test    eax, eax
    jnz     .fail                                       ; the delete itself must succeed ...
    lea     rdi, [d_wd_root]
    call    file_stat_mtime
    test    rax, rax
    jns     .fail                                       ; ... and the directory be gone
    lea     rdi, [f_wd_bob]
    call    file_stat_mtime
    test    rax, rax
    jns     .fail
    xor     ebx, ebx
    jmp     .out
.fail:
    mov     ebx, 1
    lea     rdi, [d_wd_root]
    call    dir_remove_tree
.out:
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; cap_find(edi type) -> rax the first captured record (slot u8, type u8, len u16, payload) of that message type
; or 0. The capture must still be on (turning it off forgets the count). Leaf
cap_find:
    lea     rax, [t_capbuf]
    mov     ecx, [net_captured]
    lea     rdx, [rax + rcx]
.loop:
    cmp     rax, rdx
    jae     .none
    cmp     [rax + 1], dil
    je      .hit
    movzx   ecx, word [rax + 2]
    lea     rax, [rax + rcx + 4]
    jmp     .loop
.none:
    xor     eax, eax
.hit:
    ret

; test_net_ready_resync: a joining guest's handlers drop the world's messages until it is in the world, so
; when it becomes ready (READY and a first state arrived) the host sends it the standings, the quest chain and
; the PvP rule as they are now; and a PVP that arrives while the world downloads is kept in the WORLDINFO game_join
; reads. The sends are captured (nothing goes on the wire).
; ebx = the answer
test_net_ready_resync:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    COPY    t_bk_peers, net_peers, PEER_size * NET_MAX_PEERS
    COPY    t_bk_stand, world_header + WORLDHDR.standing, 16
    movzx   eax, byte [net_role]
    mov     [t_bk_misc], al
    movzx   eax, byte [net_self]
    mov     [t_bk_misc + 1], al
    movzx   eax, byte [net_pvp]
    mov     [t_bk_misc + 2], al
    movzx   eax, byte [net_in_world]
    mov     [t_bk_misc + 3], al
    movzx   eax, byte [world_header + WORLDHDR.champions]
    mov     [t_bk_misc + 4], al
    movzx   eax, byte [rpg_state + RPGSAVE.quest]
    mov     [t_bk_misc + 5], al
    movzx   eax, byte [rpg_state + RPGSAVE.quest_state]
    mov     [t_bk_misc + 6], al
    movzx   eax, word [rpg_state + RPGSAVE.quest_progress]
    mov     [t_bk_misc + 8], ax
    movzx   eax, byte [net_winfo + WINFO_PVP]
    mov     [t_bk_misc + 7], al
    ; the host: Bob is joining, the world has moved on since his WORLDINFO
    mov     byte [net_role], NET_ROLE_HOST
    mov     byte [net_self], 0
    mov     byte [net_pvp], 1
    mov     byte [net_in_world], 0
    lea     rsi, [k_standing]
    lea     rdi, [world_header + WORLDHDR.standing]
    mov     ecx, 16
    rep     movsb
    mov     byte [world_header + WORLDHDR.champions], 5
    mov     byte [rpg_state + RPGSAVE.quest], 3
    mov     byte [rpg_state + RPGSAVE.quest_state], 1
    mov     word [rpg_state + RPGSAVE.quest_progress], 7
    WIPE    net_peers, PEER_size * NET_MAX_PEERS
    mov     dword [net_peers + PEER_size + PEER.state], PEER_JOINING
    mov     dword [net_peers + PEER_size + PEER.name], 0x00626F42      ; "Bob"
    WIPE    t_pst, PSTATE_size
    mov     word [t_pst + PSTATE.flags], PS_GROUND
    mov     dword [t_pst + PSTATE.pos + NPOS.ax], 10
    mov     dword [t_pst + PSTATE.pos + NPOS.az], 10
    mov     dword [t_pst + PSTATE.pos + NPOS.y], __float32__(70.0)
    mov     word [t_pst + PSTATE.health], 20
    mov     word [t_pst + PSTATE.max_health], 20
    mov     byte [t_pst + PSTATE.level], 3
    lea     rdi, [t_capbuf]
    mov     esi, 512
    call    net_capture
    mov     edi, 1                                      ; a first state alone does not make him ready
    mov     esi, MT_PSTATE
    lea     rdx, [t_pst]
    mov     ecx, PSTATE_size
    call    netsync_dispatch
    cmp     dword [net_captured], 0
    jne     .fail
    cmp     dword [net_peers + PEER_size + PEER.state], PEER_JOINING
    jne     .fail
    mov     edi, 1                                      ; READY does: now he is brought up to date
    mov     esi, MT_READY
    xor     edx, edx
    xor     ecx, ecx
    call    netsync_dispatch
    cmp     dword [net_peers + PEER_size + PEER.state], PEER_READY
    jne     .fail
    mov     edi, MT_SYS                                 ; (everybody hears that he joined: unchanged)
    call    cap_find
    test    rax, rax
    jz      .fail
    cmp     byte [rax], 1
    jne     .fail
    cmp     byte [rax + 4], SYS_JOINED
    jne     .fail
    mov     edi, MT_STANDING
    call    cap_find
    test    rax, rax
    jz      .fail
    cmp     byte [rax], 1                               ; to Bob (slot 1)
    jne     .fail
    cmp     word [rax + 2], 18
    jne     .fail
    cmp     word [rax + 4], 100
    jne     .fail
    cmp     word [rax + 6], -200
    jne     .fail
    cmp     byte [rax + 20], 5                          ; the champions
    jne     .fail
    mov     edi, MT_QUEST_SYNC
    call    cap_find
    test    rax, rax
    jz      .fail
    cmp     byte [rax], 1
    jne     .fail
    cmp     word [rax + 2], 4
    jne     .fail
    cmp     dword [rax + 4], 0x00070103                 ; quest 3, state 1, progress 7
    jne     .fail
    mov     edi, MT_PVP
    call    cap_find
    test    rax, rax
    jz      .fail
    cmp     byte [rax], 1
    jne     .fail
    cmp     word [rax + 2], 1
    jne     .fail
    cmp     byte [rax + 4], 1                           ; PvP on
    jne     .fail
    xor     edi, edi                                    ; the guest side: a PVP that arrives before the world
    xor     esi, esi
    call    net_capture
    mov     byte [net_role], NET_ROLE_GUEST
    mov     byte [net_in_world], 0
    mov     byte [net_pvp], 0
    mov     byte [net_winfo + WINFO_PVP], 0
    mov     byte [t_one], 1
    xor     edi, edi
    mov     esi, MT_PVP
    lea     rdx, [t_one]
    mov     ecx, 1
    call    netsync_dispatch
    cmp     byte [net_pvp], 1
    jne     .fail
    cmp     byte [net_winfo + WINFO_PVP], 1             ; ... is in the WORLDINFO game_join will read
    jne     .fail
    mov     byte [t_one], 0                             ; and the other way round
    xor     edi, edi
    mov     esi, MT_PVP
    lea     rdx, [t_one]
    mov     ecx, 1
    call    netsync_dispatch
    cmp     byte [net_pvp], 0
    jne     .fail
    cmp     byte [net_winfo + WINFO_PVP], 0
    jne     .fail
    xor     ebx, ebx
    jmp     .restore
.fail:
    mov     ebx, 1
.restore:
    xor     edi, edi
    xor     esi, esi
    call    net_capture
    call    net_session_reset                           ; the chat line of "Bob joined" goes with the session
    COPY    net_peers, t_bk_peers, PEER_size * NET_MAX_PEERS
    COPY    world_header + WORLDHDR.standing, t_bk_stand, 16
    movzx   eax, byte [t_bk_misc]
    mov     [net_role], al
    movzx   eax, byte [t_bk_misc + 1]
    mov     [net_self], al
    movzx   eax, byte [t_bk_misc + 2]
    mov     [net_pvp], al
    movzx   eax, byte [t_bk_misc + 3]
    mov     [net_in_world], al
    movzx   eax, byte [t_bk_misc + 4]
    mov     [world_header + WORLDHDR.champions], al
    movzx   eax, byte [t_bk_misc + 5]
    mov     [rpg_state + RPGSAVE.quest], al
    movzx   eax, byte [t_bk_misc + 6]
    mov     [rpg_state + RPGSAVE.quest_state], al
    movzx   eax, word [t_bk_misc + 8]
    mov     [rpg_state + RPGSAVE.quest_progress], ax
    movzx   eax, byte [t_bk_misc + 7]
    mov     [net_winfo + WINFO_PVP], al
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; test_net_host_close_boats: "Close multiplayer" frees what the guests held: net_host_open on an ephemeral
; loopback port (the rendezvous server is a closed local port), a boat marked as ridden by guests 1 and 4, then
; net_host_close - the role is off again and every boat_rider entry is zero
test_net_host_close_boats:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    COPY    t_bk_path, app_world_path, 4096
    COPY    t_bk_boats, boat_rider, MAX_BOATS
    mov     eax, [net_cfg_server]
    mov     [t_bk_misc], eax
    movzx   eax, word [net_cfg_server + 4]
    mov     [t_bk_misc + 4], ax
    lea     rdi, [app_world_path]
    lea     rsi, [d_hc_root]
    mov     edx, 4000
    call    str_copy
    lea     rdi, [d_hc_root]
    call    dir_remove_tree                             ; (what an earlier run may have left)
    mov     dword [net_cfg_server], 0x0100007F          ; 127.0.0.1 ...
    mov     word [net_cfg_server + 4], 0x0900           ; ... port 9: nobody answers there
    xor     edi, edi
    call    net_host_open
    test    eax, eax
    jnz     .fail
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .fail
    cmp     dword [net_rdist_cap], MP_HOST_RDIST
    jne     .fail
    mov     byte [boat_rider + 1], 2
    mov     byte [boat_rider + 3], 5
    call    net_host_close
    cmp     byte [net_role], NET_ROLE_OFF
    jne     .fail
    cmp     dword [net_rdist_cap], 0
    jne     .fail
    lea     rax, [boat_rider]
    xor     ecx, ecx
.boats:
    cmp     byte [rax + rcx], 0
    jne     .fail
    inc     ecx
    cmp     ecx, MAX_BOATS
    jb      .boats
    xor     ebx, ebx
    jmp     .restore
.fail:
    mov     ebx, 1
    call    net_session_reset                           ; (a host that did not close: no socket left behind)
.restore:
    lea     rdi, [d_hc_root]
    call    dir_remove_tree
    COPY    app_world_path, t_bk_path, 4096
    COPY    boat_rider, t_bk_boats, MAX_BOATS
    mov     eax, [t_bk_misc]
    mov     [net_cfg_server], eax
    movzx   eax, word [t_bk_misc + 4]
    mov     [net_cfg_server + 4], ax
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; test_net_cli_join_cleared: the command line's --join is one story: while its own target is being joined a
; failure ends the game (join_exit), but a join the player starts later from the join screen (another string) or a
; join that is cancelled ends that story - a later failure must not close the game. All with joins that fail at
; once, plus one real attempt at a closed loopback port that is cancelled.
test_net_cli_join_cleared:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rax, [net_cli_join]
    mov     [t_bk_q], rax
    movzx   eax, byte [net_join_exit]
    mov     [t_bk_misc], al
    movzx   eax, byte [net_join_failed]
    mov     [t_bk_misc + 1], al
    movzx   eax, byte [net_join_active]
    mov     [t_bk_misc + 2], al
    COPY    t_bk_sname, net_session_name, 20
    COPY    t_bk_jtarget, net_join_target, 64
    lea     rax, [t_bad]                                ; the command line's own target fails: the exit stays armed
    mov     [net_cli_join], rax
    lea     rdi, [t_bad]
    lea     rsi, [s_bob]
    xor     edx, edx
    call    net_join_begin
    cmp     eax, NJE_UNREACHABLE
    jne     .fail
    cmp     byte [net_join_exit], 1
    jne     .fail
    lea     rax, [t_bad]
    cmp     [net_cli_join], rax
    jne     .fail
    lea     rax, [t_bad]                                ; a join typed on the join screen: the --join is over
    mov     [net_cli_join], rax
    lea     rdi, [t_bad2]
    lea     rsi, [s_bob]
    xor     edx, edx
    call    net_join_begin
    cmp     eax, NJE_UNREACHABLE
    jne     .fail
    cmp     byte [net_join_exit], 0                     ; its failure does not close the game
    jne     .fail
    cmp     qword [net_cli_join], 0
    jne     .fail
    lea     rax, [t_local]                              ; a cancelled join ends it too
    mov     [net_cli_join], rax
    lea     rdi, [t_local]
    lea     rsi, [s_bob]
    xor     edx, edx
    call    net_join_begin
    test    eax, eax
    jnz     .fail
    cmp     byte [net_join_active], 1
    jne     .fail
    cmp     qword [net_cli_join], 0                     ; (its own target: kept while it runs)
    je      .fail
    call    net_join_cancel
    cmp     byte [net_join_active], 0
    jne     .fail
    cmp     qword [net_cli_join], 0
    jne     .fail
    xor     ebx, ebx
    jmp     .restore
.fail:
    mov     ebx, 1
    call    net_session_reset                           ; (no socket left behind)
.restore:
    mov     rax, [t_bk_q]
    mov     [net_cli_join], rax
    movzx   eax, byte [t_bk_misc]
    mov     [net_join_exit], al
    movzx   eax, byte [t_bk_misc + 1]
    mov     [net_join_failed], al
    movzx   eax, byte [t_bk_misc + 2]
    mov     [net_join_active], al
    COPY    net_session_name, t_bk_sname, 20
    COPY    net_join_target, t_bk_jtarget, 64
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; test_net_rejoin_takeover: a guest whose process was killed holds its name until the transport's timeout; its
; player coming back is let in when the request comes from the address the dead connection had, or when nobody has
; heard from the guest for more than 3 s - never from the host's own slot, never from a guest that was just heard.
; The decision (net_peer_replaceable) and the stamps that feed it (netsync_dispatch, host role only).
; r12 = the CONNECT event, the guest is slot 1 (1.2.3.4 port 0x1234), last heard at T = 1000 s
test_net_rejoin_takeover:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    COPY    t_bk_q, net_peer_addr, 16
    COPY    t_bk_q + 16, net_peer_rx, 16
    mov     rax, [net_pump_now]
    mov     [t_bk_q + 32], rax
    movzx   eax, byte [net_role]
    mov     [t_bk_misc], al
    lea     r12, [t_ev]
    lea     rax, [net_peer_addr]
    mov     dword [rax + 8], 0x04030201
    mov     word [rax + 12], 0x1234
    mov     word [rax + 14], 0
    mov     dword [rax], 0x04030201                     ; the host's own slot has the same address (a decoy)
    mov     word [rax + 4], 0x4321
    mov     rcx, 1000000000000
    lea     rax, [net_peer_rx]
    mov     [rax + 8], rcx                              ; guest 1 was last heard at T
    mov     qword [rax], 0                              ; ... the host's slot long ago (a decoy)
    mov     [net_pump_now], rcx                         ; and the clock says T
    WIPE    t_ev, NETEVENT_size
    mov     dword [t_ev + NETEVENT.addr + NADDR.ip], 0x04030201
    mov     word [t_ev + NETEVENT.addr + NADDR.port], 0x4321    ; same address, another port
    mov     edi, 1                                      ; heard just now, another port: refused
    mov     rsi, r12
    call    net_peer_replaceable
    test    eax, eax
    jnz     .fail
    mov     rcx, 1003000000000                          ; quiet for exactly 3 s: still refused (more than 3 s)
    mov     [net_pump_now], rcx
    mov     edi, 1
    mov     rsi, r12
    call    net_peer_replaceable
    test    eax, eax
    jnz     .fail
    mov     rcx, 1003500000000                          ; quiet for 3.5 s: gone
    mov     [net_pump_now], rcx
    mov     edi, 1
    mov     rsi, r12
    call    net_peer_replaceable
    cmp     eax, 1
    jne     .fail
    mov     rcx, 1000000000000                          ; heard just now, but from its very address: gone
    mov     [net_pump_now], rcx
    mov     word [t_ev + NETEVENT.addr + NADDR.port], 0x1234
    mov     edi, 1
    mov     rsi, r12
    call    net_peer_replaceable
    cmp     eax, 1
    jne     .fail
    mov     word [t_ev + NETEVENT.addr + NADDR.port], 0x4321
    mov     dword [t_ev + NETEVENT.addr + NADDR.ip], 0x08070605    ; another address, just heard: refused
    mov     edi, 1
    mov     rsi, r12
    call    net_peer_replaceable
    test    eax, eax
    jnz     .fail
    mov     dword [t_ev + NETEVENT.addr + NADDR.ip], 0x04030201
    mov     rcx, 1100000000000                          ; the host's slot is never given away, silent for ages
    mov     [net_pump_now], rcx
    xor     edi, edi
    mov     rsi, r12
    call    net_peer_replaceable
    test    eax, eax
    jnz     .fail
    mov     byte [net_role], NET_ROLE_HOST              ; a host stamps what it hears from a guest ...
    mov     rcx, 5000000000000
    mov     [net_pump_now], rcx
    mov     edi, 1
    mov     esi, MT_SAVE_ACK                            ; (a message the host's handler ignores)
    xor     edx, edx
    xor     ecx, ecx
    call    netsync_dispatch
    lea     rax, [net_peer_rx]
    mov     rdx, 5000000000000
    cmp     [rax + 8], rdx
    jne     .fail
    mov     rcx, 6000000000000                          ; ... but not a message that is none
    mov     [net_pump_now], rcx
    mov     edi, 1
    mov     esi, 200
    xor     edx, edx
    xor     ecx, ecx
    call    netsync_dispatch
    lea     rax, [net_peer_rx]
    mov     rdx, 5000000000000
    cmp     [rax + 8], rdx
    jne     .fail
    xor     eax, eax
    jmp     .restore
.fail:
    mov     eax, 1
.restore:
    mov     ebx, eax
    COPY    net_peer_addr, t_bk_q, 16
    COPY    net_peer_rx, t_bk_q + 16, 16
    mov     rax, [t_bk_q + 32]
    mov     [net_pump_now], rax
    movzx   eax, byte [t_bk_misc]
    mov     [net_role], al
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; test_net_wait_ends_with_session: the loading screens a guest waits behind (app_wait_area) end when the session
; does - the host closed or went silent, so the columns it waits for will never come. app_wait_net is what the wait
; loop asks each round: 0 while the session runs, 1 once net_end_reason says it is over (offline there is nothing
; to pump).
test_net_wait_ends_with_session:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, [net_end_reason]
    mov     dword [net_end_reason], 0
    call    app_wait_net
    test    eax, eax
    jnz     .fail
    mov     dword [net_end_reason], SYS_HOST_CLOSED
    call    app_wait_net
    cmp     eax, 1
    jne     .fail
    mov     dword [net_end_reason], SYS_TIMEOUT
    call    app_wait_net
    cmp     eax, 1
    jne     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     [net_end_reason], ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret
