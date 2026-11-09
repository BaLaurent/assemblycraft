; netsync.asm - the multiplayer session layer of 0.11: who is in the world and how they got there (host
; open/close, accept and deny, the welcome sequence, join and leave, character saves), the other players
; (state messages, proxy bodies with interpolation, nearest-player queries), chat, the message dispatch
; table and the send helpers every other multiplayer module uses. net.asm moves bytes and knows nothing of
; the game; this file is the glue.
;
; Roles (net_role): 0 offline, 1 host (slot 0, the owner of the world), 2 guest (slot 1..7 = net_self).
; Every wire coordinate is absolute (net_pos_out / net_pos_in convert with world_origin_x/z); a peer's
; proxy body (net_peers[slot].body) is in local coordinates. All of it runs on the main thread.
%include "common.inc"
%include "gl.inc"
default rel

global net_role, net_self, net_pvp, net_applying, net_in_world, net_hit_peer
global net_peers, net_rdist_cap, net_join_ready, net_end_reason
global net_cfg_name, net_cfg_server, net_cfg_port, net_handlers
global net_room_code, net_lan_text, net_captured, net_swing_t
global net_winfo, net_image, net_image_valid
global net_join_active, net_join_failed, net_join_target, net_title_on, net_title_text, net_session_name
global net_cli_host, net_cli_join, net_cli_relay, net_cli_pvp, net_join_exit
global net_pump, net_flush, net_tick, net_out, net_send_to, net_send_big_to, net_relay
global net_pos_out, net_pos_in, net_peer_body, net_stream_centres, net_shift, net_nearest_dist2
global net_host_open, net_host_close, net_join_begin, net_join_cancel, net_leave
global net_join_status, net_host_info, net_player_save, net_died_out, net_set_pvp
global net_chat_send, net_chat_line, net_cfg_load, net_cfg_save, net_valid_name
global net_capture, netsync_dispatch, net_ready_out, net_session_reset, net_pstate_build, net_cfg_cli
%define CLI_NAME   1                    ; cfg_cli_flags: what the command line set for this run only
%define CLI_SERVER 2
%define CLI_PORT   4
global net_pump_now, net_peer_rx, net_peer_addr, net_peer_replaceable
%define SILENT_NS  3000000000           ; a guest nobody has heard of for this long is gone (its name can be taken)
global net_join_accept_ns, net_join_timeout_check, net_wait_check

; net.asm (transport)
extern net_ep, net_ep_open, net_ep_close, net_ep_poll, net_ep_next_event, net_ep_flush
extern net_ep_send, net_ep_send_big, net_ep_accept, net_ep_deny, net_ep_drop
extern net_ep_join, net_ep_join_state, net_ep_join_err, net_ep_rv_host, net_ep_rv_state
extern net_ep_room_code, net_ep_is_relay
extern net_parse_addr, net_format_addr, net_local_ip
; the other multiplayer modules: handlers of the dispatch table, and what the pump drives
extern nw_on_block, nw_on_col_req, nw_on_col_data, nw_on_col_pristine, nw_on_cont_open
extern nw_on_cont_data, nw_on_cont_put, nw_on_cont_close, nw_on_cont_gone, nw_on_tnt_prime
extern nw_on_boat_place, nw_on_boat_mount, nw_on_boat_mount_ok, nw_on_boat_dismount
extern nw_on_boat_break, nw_on_boat_pose
extern nm_on_snap_mobs, nm_on_snap_drops, nm_on_snap_misc, nm_on_hit, nm_on_status, nm_on_mobfx
extern nm_on_kill, nm_on_hurt, nm_on_pvp_hit, nm_on_interact
extern nx_on_proj, nx_on_proj_end, nx_on_sound, nx_on_fx, nx_on_event, nx_on_standing
extern nx_on_faction_add, nx_on_quest_sync, nx_on_quest_accept, nx_on_quest_bump
extern nx_on_quest_complete, nx_on_quest_reward, nx_on_drop_spawn, nx_on_give
extern nm_snap_send, nm_shift, net_boat_tick
extern net_host_columns_serve, net_cont_frame, net_edits_replay
extern boat_rider, boat_riding
; the game
extern world_header, world_origin_x, world_origin_z, player, surv, surv_max_health
extern inv, inv_sel, inv_close_screen, rpg_level, rpg_archetype, rpg_state
extern sleep_active, sleep_timer, combat_guard_t, combat_stealth_t, frame_input
extern game_mode, game_time, game_player_save, death_causes
extern app_window, app_in_world, app_world_path, app_show_loading
extern data_dir, sys_print, str_len, str_eq, str_copy, str_append, i32_to_str, parse_u32
extern file_read, file_write_atomic, mkdir_p, time_mono_ns, usleep

%define CHAT_LEN        96                      ; bytes per chat line
%define CHAT_LINES      8                       ; the log keeps the 8 newest
%define SLEEP_STEPS     120                     ; sleep.asm's SLEEP_STEPS: in bed this long = ready for morning
%define SAVE_WAIT_NS    3000000000              ; a leaving guest / closing host waits this long for the saves
%define HCLOSE_WAIT_NS  2500000000              ; a guest told "host closing" waits this long for its save ack
%define CFG_MAX         1023
%define JERR_LOST       100                     ; join_err: the connection died after it was accepted
%define JERR_NOANSWER   101                     ; join_err: accepted, but the host never sent the character ...
%define JOIN_WAIT_NS    10000000000             ; ... within this long after the accept
%define WAIT_LOST_NS    60000000000             ; a guest that waited this long behind a loading screen ...
%define HOST_QUIET_NS   10000000000             ; ... while the host said nothing for this long has lost the host
%define RV_PORT_BE      (((RV_PORT & 0xFF) << 8) | (RV_PORT >> 8))

; the WORLDINFO message (84 bytes, host to guest); game.asm's WINFO is the same layout
struc WINFO
    .seed:        resd 1
    .mode:        resd 1
    .time:        resd 1
    .name:        resb 33
    .pvp:         resb 1
    .your_slot:   resb 1
    .cheater:     resb 1
    .spawn_x:     resd 1
    .spawn_y:     resd 1
    .spawn_z:     resd 1
    .standing:    resw 8
    .champions:   resb 1
    .quest:       resb 1
    .quest_state: resb 1
    .pad:         resb 1
    .quest_progress: resw 1
    .pad2:        resw 1
endstruc
%if WINFO_size != 84
%error "WORLDINFO is 84 bytes"
%endif
%if (PEER_size * NET_MAX_PEERS) % 8 != 0
%error "peers_clear clears quadwords"
%endif

; ENTER_N n [locals]: rbp frame, the first n of rbx r12 r13 r14 r15 saved, locals (a multiple of 16)
; reserved; rsp is 16-aligned for calls afterwards. LEAVE_N n [locals] undoes it.
%macro ENTER_N 1-2 0
    push    rbp
    mov     rbp, rsp
%if %1 >= 1
    push    rbx
%endif
%if %1 >= 2
    push    r12
%endif
%if %1 >= 3
    push    r13
%endif
%if %1 >= 4
    push    r14
%endif
%if %1 >= 5
    push    r15
%endif
%if (%1 & 1) == 1
    sub     rsp, 8
%endif
%if %2 > 0
    sub     rsp, %2
%endif
%endmacro

%macro LEAVE_N 1-2 0
%if %2 > 0
    add     rsp, %2
%endif
%if (%1 & 1) == 1
    add     rsp, 8
%endif
%if %1 >= 5
    pop     r15
%endif
%if %1 >= 4
    pop     r14
%endif
%if %1 >= 3
    pop     r13
%endif
%if %1 >= 2
    pop     r12
%endif
%if %1 >= 1
    pop     rbx
%endif
    pop     rbp
%endmacro

section .rodata
align 4
f_inv65536:   dd 0.0000152587890625
f_blend:      dd 0.35                           ; a proxy moves this far to its target each step
f_snap2:      dd 36.0                           ; ... and snaps when farther than 6 blocks
f_walk_deg:   dd 60.0                           ; degrees of walk cycle per block walked
f_walk_wrap:  dd 3600.0
f_360:        dd 360.0
f_180:        dd 180.0
f_neg180:     dd -180.0
f_inv360:     dd 0.0027777778
f_half_w:     dd 0.3
f_height:     dd 1.8
f_speed:      dd 4.317
f_y_min:      dd -1024.0                        ; wire sanity limits (a state comes from another machine)
f_y_max:      dd 4096.0
f_ang_min:    dd -1.0e6
f_ang_max:    dd 1.0e6
f_pitch_min:  dd -90.0
f_pitch_max:  dd 90.0
align 8
d_65536:      dq 65536.0
m_v6:         db "ACRAFT06"

s_net:        db "net: ", 0
s_hosting:    db "hosting on port ", 0
s_lan_open:   db " (lan ", 0
s_room:       db "room ", 0
s_unreach:    db "rendezvous unreachable", 0
s_joined_slot: db " joined slot ", 0
s_left_t:     db " left (left)", 0
s_left_to:    db " left (timeout)", 0
s_direct_p:   db " (direct)", 0
s_relay_p:    db " (relay)", 0
s_joined_as:  db "joined as slot ", 0
s_join_failed: db "join failed: ", 0
s_host_closed_l: db "host closed", 0
s_host_lost_l: db "lost connection to the host", 0
s_chat:       db "chat ", 0
s_gt:         db "> ", 0
s_qmark:      db "?", 0
s_colon:      db ": ", 0
s_died:       db "died", 0
s_t_joined:   db " joined the world", 0
s_t_left:     db " left", 0
s_t_lost:     db " lost connection", 0
s_pvp_on:     db "PvP enabled", 0
s_pvp_off:    db "PvP disabled", 0
s_title_pfx:  db "AssemblyCraft - ", 0
s_title_plain: db "AssemblyCraft", 0
s_players:    db "/players", 0
s_players_sl: db "/players/", 0
s_hdr_ext:    db ".hdr", 0
s_cfg_file:   db "/multiplayer.cfg", 0
s_key_name:   db "name=", 0
s_key_server: db "server=", 0
s_key_port:   db "port=", 0
s_default_name: db "Player", 0
s_info_room:  db "Room ", 0
s_info_direct: db "Direct only", 0
s_info_open:  db "Opening room", 0
s_info_sep:   db " - ", 0
s_info_players: db " players", 0
s_saving_pl:  db "Saving players...", 0
s_leaving:    db "Leaving...", 0
s_empty:      db 0
s_st_rv:      db "Contacting rendezvous server...", 0
s_st_punch:   db "Connecting to the host...", 0
s_st_relay:   db "Connecting through the relay...", 0
s_st_connect: db "Connecting to ", 0
s_st_dots:    db "...", 0
s_st_download: db "Downloading world...", 0
s_e_rv:       db "Rendezvous server unreachable", 0
s_e_noroom:   db "No world with code ", 0
s_e_unreach:  db "Could not reach the host", 0
s_e_full:     db "The world is full", 0
s_e_version:  db "Version mismatch with the host", 0
s_e_name:     db "That name is already taken", 0
s_e_closed:   db "The host closed the world", 0
s_e_net:      db "Network error", 0
s_e_lost:     db "Lost connection to the host", 0
s_e_noanswer: db "The host did not answer", 0
code_alphabet: db "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
%define CODE_ALPHABET_LEN 32
align 8
join_err_text:                                  ; by NJE_* (0 and the unknown ones: a network error)
    dq s_e_net, s_e_rv, s_e_noroom, s_e_unreach, s_e_full, s_e_version, s_e_name, s_e_closed, s_e_net
join_err_text_end:

section .data
align 8
net_handlers:                                   ; message type -> handler(edi slot, esi type, rdx payload, ecx len)
    dq 0                                        ; 0
    dq ns_on_worldinfo                          ; 1  MT_WORLDINFO
    dq ns_on_peer_join                          ; 2  MT_PEER_JOIN
    dq ns_on_peer_leave                         ; 3  MT_PEER_LEAVE
    dq ns_on_player_image                       ; 4  MT_PLAYER_IMAGE
    dq ns_on_player_fresh                       ; 5  MT_PLAYER_FRESH
    dq ns_on_ready                              ; 6  MT_READY
    dq ns_on_player_save                        ; 7  MT_PLAYER_SAVE
    dq ns_on_host_closing                       ; 8  MT_HOST_CLOSING
    dq ns_on_pstate                             ; 9  MT_PSTATE
    dq ns_on_players                            ; 10 MT_PLAYERS
    dq ns_on_chat                               ; 11 MT_CHAT
    dq ns_on_sys                                ; 12 MT_SYS
    dq ns_on_pvp                                ; 13 MT_PVP
    dq ns_on_died                               ; 14 MT_DIED
    dq 0                                        ; 15 MT_BLOB_PART (the transport's own)
    dq ns_on_save_ack                           ; 16 MT_SAVE_ACK
    dq 0, 0, 0                                  ; 17..19
    dq nw_on_block                              ; 20
    dq nw_on_col_req                            ; 21
    dq nw_on_col_data                           ; 22
    dq nw_on_col_pristine                       ; 23
    dq nw_on_cont_open                          ; 24
    dq nw_on_cont_data                          ; 25
    dq nw_on_cont_put                           ; 26
    dq nw_on_cont_close                         ; 27
    dq nw_on_cont_gone                          ; 28
    dq nw_on_tnt_prime                          ; 29
    dq nw_on_boat_place                         ; 30
    dq nw_on_boat_mount                         ; 31
    dq nw_on_boat_mount_ok                      ; 32
    dq nw_on_boat_dismount                      ; 33
    dq nw_on_boat_break                         ; 34
    dq nw_on_boat_pose                          ; 35
    dq 0, 0, 0, 0                               ; 36..39
    dq nm_on_snap_mobs                          ; 40
    dq nm_on_snap_drops                         ; 41
    dq nm_on_snap_misc                          ; 42
    dq nm_on_hit                                ; 43
    dq nm_on_status                             ; 44
    dq nm_on_mobfx                              ; 45
    dq nm_on_kill                               ; 46
    dq nm_on_hurt                               ; 47
    dq nm_on_pvp_hit                            ; 48
    dq nm_on_interact                           ; 49
    dq nx_on_proj                               ; 50
    dq nx_on_proj_end                           ; 51
    dq nx_on_sound                              ; 52
    dq nx_on_fx                                 ; 53
    dq nx_on_event                              ; 54
    dq nx_on_standing                           ; 55
    dq nx_on_faction_add                        ; 56
    dq nx_on_quest_sync                         ; 57
    dq nx_on_quest_accept                       ; 58
    dq nx_on_quest_bump                         ; 59
    dq nx_on_quest_complete                     ; 60
    dq nx_on_quest_reward                       ; 61
    dq nx_on_drop_spawn                         ; 62
    dq nx_on_give                               ; 63
net_handlers_end:
%if net_handlers_end - net_handlers != 8 * NUM_MT
%error "net_handlers has one qword per message type"
%endif
align 4
net_cfg_name:   db "Player", 0
                times 20 - 7 db 0
net_cfg_server: dd RV_DEFAULT_IP                ; the rendezvous server, as in sockaddr_in
                dw RV_PORT_BE
                dw 0
net_cfg_port:   dd NET_PORT

section .bss
alignb 16
net_peers:      resb PEER_size * NET_MAX_PEERS  ; slot 0 = the host
alignb 8
cap_buf:        resq 1                          ; net_capture: the record buffer (0 = capture off)
cap_cap:        resd 1
net_captured:   resd 1                          ; ... and the bytes used
net_hit_peer:   resd 1                          ; the slot whose action is being applied (0 otherwise)
net_rdist_cap:  resd 1                          ; render distance cap while hosting (0 = none)
net_join_ready: resd 1                          ; guest: the character arrived, the world can be joined
net_end_reason: resd 1                          ; SYS_* code: the session is over (the app returns to the title)
net_swing_t:    resd 1                          ; steps left of "his arm swings" (game.asm sets it on every swing)
net_image_valid: resd 1                         ; the saved character in net_image is real (else a fresh one)
net_step_ctr:   resd 1                          ; sim steps since the last state message
hc_t0:          resq 1                          ; time of HOST_CLOSING
net_pump_now:   resq 1                          ; the clock (ns) at the start of this frame's pump
net_join_accept_ns: resq 1                      ; guest: the clock (ns) when the host accepted this join
net_peer_rx:    resq NET_MAX_PEERS              ; host: when each guest was last heard (a delivered message), ns
net_peer_addr:  resq NET_MAX_PEERS              ; host: the address (a NADDR) each guest connected from
net_role:       resb 1
net_self:       resb 1
net_pvp:        resb 1
net_applying:   resb 1
net_in_world:   resb 1
net_join_active: resb 1                         ; a join is in progress (from net_join_begin until the world is entered)
net_join_failed: resb 1                         ; the last join failed (net_join_status holds why)
net_title_on:   resb 1
ep_open:        resb 1                          ; net_ep is open
ready_sent:     resb 1                          ; guest: READY went out
host_closing:   resb 1                          ; guest: the host said it is closing
save_acked:     resb 1
winfo_valid:    resb 1
rv_fail_logged: resb 1
net_cli_host:   resb 1                          ; --host
net_cli_relay:  resb 1                          ; --force-relay
net_cli_pvp:    resb 1                          ; --pvp
net_join_exit:  resb 1                          ; --join failed: the app exits with code 3
alignb 8
net_cli_join:   resq 1                          ; --join target text or 0
join_err:       resd 1
net_room_code:  resb 8                          ; 6 characters and a NUL
net_lan_text:   resb 24
net_session_name: resb 20                       ; the name this session plays under
cfg_file_name:  resb 20                        ; what multiplayer.cfg says (net_cfg_save writes these) ...
cfg_cli_name:   resb 20                        ; ... and the name --name gave this run
cfg_file_server: resb 8                        ; a NADDR
cfg_file_port:  resd 1
cfg_cli_flags:  resb 1
net_title_text: resb 48
net_join_target: resb 64                        ; what the player typed (upper-cased for a room code)
join_text:      resb 96
join_addr:      resb 8                          ; NADDR
join_code:      resb 8
log_buf:        resb 192
chat_tmp:       resb 128
chat_out:       resb 40
chat_head:      resd 1
chat_count:     resd 1
alignb 8
chat_time:      resq CHAT_LINES
chat_lines:     resb CHAT_LINES * CHAT_LEN
alignb 8
ev_buf:         resb NETEVENT_size
alignb 16
msg_buf:        resb NET_MSG_MAX + 64
net_winfo:      resb WINFO_size
alignb 16
net_image:      resb PLAYER_IMG_SIZE
alignb 16
pl_buf:         resb WORLD_HDR_SIZE             ; a guest's character file, whole
path_buf:       resb 4112
cfg_path_buf:   resb 4112
cfg_buf:        resb CFG_MAX + 1

section .text

; ---- small helpers -----------------------------------------------------------------------------

; peer_ptr(edi slot 0..7) -> rax &net_peers[slot]. Leaf; clobbers edx
peer_ptr:
    imul    eax, edi, PEER_size
    lea     rdx, [net_peers]
    add     rax, rdx
    ret

; peer_name(edi slot) -> rax the zstr name of a slot, "?" for a free or unknown one. Leaf
peer_name:
    cmp     edi, NET_MAX_PEERS
    jae     .unknown
    imul    eax, edi, PEER_size
    lea     rdx, [net_peers]
    add     rax, rdx
    cmp     dword [rax + PEER.state], PEER_FREE
    je      .unknown
    add     rax, PEER.name
    ret
.unknown:
    lea     rax, [s_qmark]
    ret

; peers_clear(): every slot free, every proxy gone
peers_clear:
    lea     rdi, [net_peers]
    mov     ecx, (PEER_size * NET_MAX_PEERS) / 8
    xor     eax, eax
    rep     stosq
    ret

; peer_init(rdi PEER*, rsi name zstr, edx state): a new record (all zero), its name (16 characters at most)
; and state
peer_init:
    ENTER_N 3
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13d, edx
    xor     eax, eax
    mov     ecx, PEER_size
    rep     stosb
    mov     [rbx + PEER.state], r13d
    lea     rdi, [rbx + PEER.name]
    mov     rsi, r12
    mov     edx, NAME_MAX
    call    str_copy
    LEAVE_N 3
    ret

; log_start() -> rax: log_buf holds "net: " and rax is its end (the line goes on with str_append)
log_start:
    lea     rdi, [log_buf]
    lea     rsi, [s_net]
    jmp     str_append

; log_flush(rdi end): the line ends here; it is written to stderr
log_flush:
    mov     word [rdi], 10              ; newline, NUL
    mov     edi, 2
    lea     rsi, [log_buf]
    jmp     sys_print

; app_num(rdi end, esi value) -> rax new end: the decimal text of a number
app_num:
    mov     rdx, rdi
    mov     edi, esi
    mov     rsi, rdx
    jmp     i32_to_str

; log_text(rdi a zstr, rsi b zstr or 0): "net: a b" on stderr
log_text:
    ENTER_N 2
    mov     rbx, rdi
    mov     r12, rsi
    call    log_start
    mov     rdi, rax
    mov     rsi, rbx
    call    str_append
    test    r12, r12
    jz      .end
    mov     rdi, rax
    mov     rsi, r12
    call    str_append
.end:
    mov     rdi, rax
    call    log_flush
    LEAVE_N 2
    ret

; log_hosting(edi port): "net: hosting on port P (lan IP:P)"
log_hosting:
    ENTER_N 1
    mov     ebx, edi
    call    log_start
    mov     rdi, rax
    lea     rsi, [s_hosting]
    call    str_append
    mov     rdi, rax
    mov     esi, ebx
    call    app_num
    mov     rdi, rax
    lea     rsi, [s_lan_open]
    call    str_append
    mov     rdi, rax
    lea     rsi, [net_lan_text]
    call    str_append
    mov     byte [rax], ')'
    lea     rdi, [rax + 1]
    call    log_flush
    LEAVE_N 1
    ret

; log_name_slot(rdi name, esi slot, edx relay): "net: NAME joined slot N (direct|relay)"
log_name_slot:
    ENTER_N 3
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    call    log_start
    mov     rdi, rax
    mov     rsi, rbx
    call    str_append
    mov     rdi, rax
    lea     rsi, [s_joined_slot]
    call    str_append
    mov     rdi, rax
    mov     esi, r12d
    call    app_num
    mov     rdi, rax
    mov     esi, r13d
    call    log_link
    mov     rdi, rax
    call    log_flush
    LEAVE_N 3
    ret

; log_link(rdi end, esi relay) -> rax end: " (direct)" or " (relay)"
log_link:
    lea     rdx, [s_direct_p]
    lea     rax, [s_relay_p]
    test    esi, esi
    mov     rsi, rdx
    cmovnz  rsi, rax
    jmp     str_append

; ---- positions on the wire ---------------------------------------------------------------------

; net_pos_out(rdi NPOS*, xmm0 x, xmm1 y, xmm2 z): a local position to its absolute wire form. x and z are
; added to the origin in double precision, floored (ax, az) and the fraction kept in 1/65536 (fx, fz); y is
; sent as it is.
net_pos_out:
    movss   [rdi + NPOS.y], xmm1
    cvtss2sd xmm0, xmm0
    cvtsi2sd xmm3, dword [world_origin_x]
    addsd   xmm0, xmm3
    roundsd xmm4, xmm0, 9
    cvttsd2si eax, xmm4
    mov     [rdi + NPOS.ax], eax
    subsd   xmm0, xmm4
    mulsd   xmm0, [d_65536]
    cvttsd2si eax, xmm0
    mov     [rdi + NPOS.fx], ax
    cvtss2sd xmm2, xmm2
    cvtsi2sd xmm3, dword [world_origin_z]
    addsd   xmm2, xmm3
    roundsd xmm4, xmm2, 9
    cvttsd2si eax, xmm4
    mov     [rdi + NPOS.az], eax
    subsd   xmm2, xmm4
    mulsd   xmm2, [d_65536]
    cvttsd2si eax, xmm2
    mov     [rdi + NPOS.fz], ax
    ret

; net_pos_in(rdi NPOS*) -> xmm0 x, xmm1 y, xmm2 z: the absolute wire position in this peer's local frame
net_pos_in:
    mov     eax, [rdi + NPOS.ax]
    sub     eax, [world_origin_x]
    cvtsi2ss xmm0, eax
    movzx   eax, word [rdi + NPOS.fx]
    cvtsi2ss xmm3, eax
    mulss   xmm3, [f_inv65536]
    addss   xmm0, xmm3
    movss   xmm1, [rdi + NPOS.y]
    mov     eax, [rdi + NPOS.az]
    sub     eax, [world_origin_z]
    cvtsi2ss xmm2, eax
    movzx   eax, word [rdi + NPOS.fz]
    cvtsi2ss xmm3, eax
    mulss   xmm3, [f_inv65536]
    addss   xmm2, xmm3
    ret

; ---- names and the configuration file ----------------------------------------------------------

; net_valid_name(rdi zstr) -> eax 1 when it is 1..16 characters from [A-Za-z0-9_], else 0. Leaf
net_valid_name:
    xor     ecx, ecx
.loop:
    movzx   eax, byte [rdi + rcx]
    test    eax, eax
    jz      .end
    cmp     ecx, NAME_MAX
    jae     .bad                        ; a 17th character
    cmp     eax, '_'
    je      .ok
    lea     edx, [rax - '0']
    cmp     edx, 9
    jbe     .ok
    lea     edx, [rax - 'A']
    cmp     edx, 25
    jbe     .ok
    lea     edx, [rax - 'a']
    cmp     edx, 25
    ja      .bad
.ok:
    inc     ecx
    jmp     .loop
.end:
    test    ecx, ecx
    jz      .bad                        ; empty
    mov     eax, 1
    ret
.bad:
    xor     eax, eax
    ret

; cfg_path() -> rax "<data_dir>/multiplayer.cfg" (in cfg_path_buf)
cfg_path:
    sub     rsp, 8
    lea     rdi, [cfg_path_buf]
    lea     rsi, [data_dir]
    mov     edx, 4000
    call    str_copy
    mov     rdi, rax
    lea     rsi, [s_cfg_file]
    call    str_append
    mov     byte [rax], 0
    lea     rax, [cfg_path_buf]
    add     rsp, 8
    ret

; cfg_key(rdi line, rsi key zstr) -> rax the text after the key when the line starts with it, else 0. Leaf
cfg_key:
.loop:
    mov     al, [rsi]
    test    al, al
    jz      .match
    cmp     al, [rdi]
    jne     .no
    inc     rsi
    inc     rdi
    jmp     .loop
.match:
    mov     rax, rdi
    ret
.no:
    xor     eax, eax
    ret

; net_cfg_load(): the defaults (name "Player", the default server, port NET_PORT), then <data_dir>/
; multiplayer.cfg over them: lines "name=", "server=a.b.c.d:port" and "port=N"; a line that is not good
; leaves its default.
; Frame: [rsp] NADDR / u32 scratch (16). rbx = line start, r12 = line end
net_cfg_load:
    ENTER_N 2, 16
    lea     rdi, [net_cfg_name]
    lea     rsi, [s_default_name]
    mov     edx, NAME_MAX
    call    str_copy
    mov     dword [net_cfg_server + NADDR.ip], RV_DEFAULT_IP
    mov     word [net_cfg_server + NADDR.port], RV_PORT_BE
    mov     word [net_cfg_server + NADDR.pad], 0
    mov     dword [net_cfg_port], NET_PORT
    call    cfg_path
    mov     rdi, rax
    lea     rsi, [cfg_buf]
    mov     edx, CFG_MAX
    call    file_read
    test    rax, rax
    jle     .done
    lea     rcx, [cfg_buf]
    mov     byte [rcx + rax], 0
    mov     rbx, rcx
.line:
    cmp     byte [rbx], 0
    je      .done
    mov     r12, rbx                    ; find the end of the line, cut it there
.eol:
    mov     al, [r12]
    test    al, al
    jz      .cut
    cmp     al, 10
    je      .cut
    inc     r12
    jmp     .eol
.cut:
    mov     rdx, r12                    ; strip a trailing CR
    cmp     rdx, rbx
    je      .no_cr
    cmp     byte [rdx - 1], 13
    jne     .no_cr
    mov     byte [rdx - 1], 0
.no_cr:
    cmp     byte [r12], 0
    mov     byte [r12], 0
    je      .at_end
    inc     r12
.at_end:
    mov     rdi, rbx
    lea     rsi, [s_key_name]
    call    cfg_key
    test    rax, rax
    jz      .not_name
    mov     rbx, rax
    mov     rdi, rbx
    call    net_valid_name
    test    eax, eax
    jz      .next
    lea     rdi, [net_cfg_name]
    mov     rsi, rbx
    mov     edx, NAME_MAX
    call    str_copy
    jmp     .next
.not_name:
    mov     rdi, rbx
    lea     rsi, [s_key_server]
    call    cfg_key
    test    rax, rax
    jz      .not_server
    mov     rdi, rax
    mov     rsi, rsp
    mov     edx, RV_PORT
    call    net_parse_addr
    test    eax, eax
    jz      .next
    mov     rax, [rsp]
    mov     [net_cfg_server], rax
    jmp     .next
.not_server:
    mov     rdi, rbx
    lea     rsi, [s_key_port]
    call    cfg_key
    test    rax, rax
    jz      .next
    mov     rdi, rax
    mov     rsi, rsp
    call    parse_u32
    test    eax, eax
    jz      .next
    mov     eax, [rsp]
    lea     ecx, [rax - 1]
    cmp     ecx, 65534                  ; 1..65535
    ja      .next
    mov     [net_cfg_port], eax
.next:
    mov     rbx, r12
    jmp     .line
.done:
    lea     rdi, [cfg_file_name]        ; what the file says: net_cfg_save writes these, not a run's overrides
    lea     rsi, [net_cfg_name]
    mov     edx, NAME_MAX
    call    str_copy
    mov     rax, [net_cfg_server]
    mov     [cfg_file_server], rax
    mov     eax, [net_cfg_port]
    mov     [cfg_file_port], eax
    mov     byte [cfg_cli_flags], 0
    LEAVE_N 2, 16
    ret

; net_cfg_cli(rdi name zstr or 0, rsi NADDR* or 0, edx port or 0): the command line's --name, --server and --port.
; They replace the live values for this run only: net_cfg_save keeps writing what the file said for each of them
; (a name the player has edited since is his choice and is written)
net_cfg_cli:
    ENTER_N 2
    mov     rbx, rsi
    mov     r12d, edx
    test    rdi, rdi
    jz      .no_name
    mov     rsi, rdi
    lea     rdi, [cfg_cli_name]
    mov     edx, NAME_MAX
    call    str_copy
    lea     rdi, [net_cfg_name]
    lea     rsi, [cfg_cli_name]
    mov     edx, NAME_MAX
    call    str_copy
    or      byte [cfg_cli_flags], CLI_NAME
.no_name:
    test    rbx, rbx
    jz      .no_server
    mov     rax, [rbx]
    mov     [net_cfg_server], rax
    or      byte [cfg_cli_flags], CLI_SERVER
.no_server:
    test    r12d, r12d
    jz      .out
    mov     [net_cfg_port], r12d
    or      byte [cfg_cli_flags], CLI_PORT
.out:
    LEAVE_N 2
    ret

; net_cfg_save(): <data_dir>/multiplayer.cfg from net_cfg_name, net_cfg_server and net_cfg_port - except what the
; command line set for this run only (a --name nobody edited, --server, --port): there the file keeps its own value
; rbx = length, r12 = the name written, r13 = the server written, r14d = the port written
net_cfg_save:
    ENTER_N 4
    lea     r12, [net_cfg_name]
    test    byte [cfg_cli_flags], CLI_NAME
    jz      .named
    lea     rdi, [net_cfg_name]
    lea     rsi, [cfg_cli_name]
    call    str_eq
    test    eax, eax
    jz      .edited
    lea     r12, [cfg_file_name]        ; still the name --name gave: the file keeps its own
    jmp     .named
.edited:
    and     byte [cfg_cli_flags], ~CLI_NAME     ; the player chose this one
.named:
    lea     r13, [net_cfg_server]
    test    byte [cfg_cli_flags], CLI_SERVER
    jz      .server_live
    lea     r13, [cfg_file_server]
.server_live:
    mov     r14d, [net_cfg_port]
    test    byte [cfg_cli_flags], CLI_PORT
    jz      .port_live
    mov     r14d, [cfg_file_port]
.port_live:
    lea     rdi, [cfg_buf]
    lea     rsi, [s_key_name]
    call    str_append
    mov     rdi, rax
    mov     rsi, r12
    call    str_append
    mov     byte [rax], 10
    lea     rdi, [rax + 1]
    lea     rsi, [s_key_server]
    call    str_append
    mov     rsi, rax
    mov     rdi, r13
    call    net_format_addr
    mov     byte [rax], 10
    lea     rdi, [rax + 1]
    lea     rsi, [s_key_port]
    call    str_append
    mov     rsi, rax
    mov     edi, r14d
    call    i32_to_str
    mov     byte [rax], 10
    inc     rax
    lea     rdx, [cfg_buf]
    sub     rax, rdx
    mov     rbx, rax                    ; length
    call    cfg_path
    mov     rdi, rax
    lea     rsi, [cfg_buf]
    mov     rdx, rbx
    call    file_write_atomic
    lea     rdi, [cfg_file_name]        ; the file's own values are what was just written
    mov     rsi, r12
    mov     edx, NAME_MAX
    call    str_copy
    mov     rax, [r13]
    mov     [cfg_file_server], rax
    mov     [cfg_file_port], r14d
    LEAVE_N 4
    ret

; ---- chat -------------------------------------------------------------------------------------

; chat_add(rdi line zstr): the newest of the 8 kept lines, stamped now; it also goes to stderr
chat_add:
    ENTER_N 2
    mov     r12, rdi
    mov     ebx, [chat_head]
    lea     eax, [rbx + 1]
    and     eax, CHAT_LINES - 1
    mov     [chat_head], eax
    cmp     dword [chat_count], CHAT_LINES
    jae     .full
    inc     dword [chat_count]
.full:
    imul    edi, ebx, CHAT_LEN
    lea     rax, [chat_lines]
    add     rdi, rax
    mov     rsi, r12
    mov     edx, CHAT_LEN - 1
    call    str_copy
    call    time_mono_ns
    lea     rcx, [chat_time]
    mov     [rcx + rbx*8], rax
    call    log_start
    mov     rdi, rax
    lea     rsi, [s_chat]
    call    str_append
    mov     rdi, rax
    mov     rsi, r12
    call    str_append
    mov     rdi, rax
    call    log_flush
    LEAVE_N 2
    ret

; net_chat_line(edi i) -> rax the i-th newest line (0 = newest) or 0, edx its age in ms
net_chat_line:
    ENTER_N 1
    cmp     edi, [chat_count]
    jae     .none
    mov     ebx, [chat_head]
    sub     ebx, edi
    dec     ebx
    and     ebx, CHAT_LINES - 1
    call    time_mono_ns
    lea     rcx, [chat_time]
    sub     rax, [rcx + rbx*8]
    xor     edx, edx
    mov     ecx, 1000000
    div     rcx                         ; ns -> ms
    mov     rcx, 0x7FFFFFFF
    cmp     rax, rcx
    cmova   rax, rcx
    mov     edx, eax
    imul    eax, ebx, CHAT_LEN
    lea     rcx, [chat_lines]
    add     rax, rcx
    jmp     .out
.none:
    xor     eax, eax
    xor     edx, edx
.out:
    LEAVE_N 1
    ret

; chat_player_line(edi slot, rsi text zstr): the log gets "<NAME> text"
chat_player_line:
    ENTER_N 2
    mov     r12, rsi
    call    peer_name
    lea     rdi, [chat_tmp]
    mov     byte [rdi], '<'
    inc     rdi
    mov     rsi, rax
    call    str_append
    mov     rdi, rax
    lea     rsi, [s_gt]
    call    str_append
    mov     rdi, rax
    mov     rsi, r12
    call    str_append
    mov     byte [rax], 0
    lea     rdi, [chat_tmp]
    call    chat_add
    LEAVE_N 2
    ret

; chat_death_line(edi slot, esi cause): "NAME: <the death text>" ("NAME: died" when the cause has none)
chat_death_line:
    ENTER_N 2
    mov     ebx, esi
    call    peer_name
    lea     rdi, [chat_tmp]
    mov     rsi, rax
    call    str_append
    mov     rdi, rax
    lea     rsi, [s_colon]
    call    str_append
    mov     rdi, rax
    lea     rsi, [s_died]
    cmp     ebx, CAUSE_LAST
    ja      .text
    lea     rcx, [death_causes]
    mov     rdx, [rcx + rbx*8]
    cmp     byte [rdx], 0
    cmovne  rsi, rdx
.text:
    call    str_append
    mov     byte [rax], 0
    lea     rdi, [chat_tmp]
    call    chat_add
    LEAVE_N 2
    ret

; chat_clean(rdi dst[34], rsi src, edx n): at most 32 characters of the n bytes at src, up to a NUL; what is
; not ASCII 32..126 becomes '?'; dst ends in a NUL. Leaf
chat_clean:
    xor     ecx, ecx
.loop:
    cmp     ecx, 32
    jae     .done
    cmp     ecx, edx
    jae     .done
    movzx   eax, byte [rsi + rcx]
    test    eax, eax
    jz      .done
    lea     r8d, [rax - 32]
    cmp     r8d, 94
    jbe     .ok
    mov     eax, '?'
.ok:
    mov     [rdi + rcx], al
    inc     ecx
    jmp     .loop
.done:
    mov     byte [rdi + rcx], 0
    ret

; chat_say(edi slot, rsi text zstr <= 32 characters): host. The line goes into its own log and to every
; ready guest (the speaker included: the host's order is the order everyone sees)
chat_say:
    ENTER_N 3
    mov     ebx, edi
    mov     r12, rsi
    call    chat_player_line
    mov     [chat_out], bl
    lea     rdi, [chat_out + 1]
    mov     rsi, r12
    mov     edx, 33
    call    chat_clean
    mov     r13d, 1
.guest:
    mov     edi, r13d
    call    peer_ptr
    cmp     dword [rax + PEER.state], PEER_READY
    jne     .next
    mov     edi, r13d
    mov     esi, MT_CHAT
    lea     rdx, [chat_out]
    mov     ecx, 34
    mov     r8d, 1
    call    net_send_to
.next:
    inc     r13d
    cmp     r13d, NET_MAX_PEERS
    jb      .guest
    LEAVE_N 3
    ret

; net_chat_send(rdi text zstr): the local player says something (cut at 32 characters; nothing offline)
net_chat_send:
    ENTER_N 1
    cmp     byte [net_role], NET_ROLE_OFF
    je      .out
    cmp     byte [rdi], 0
    je      .out
    mov     rsi, rdi
    lea     rdi, [chat_out + 1]
    mov     edx, 32
    call    chat_clean
    movzx   eax, byte [net_self]
    mov     [chat_out], al
    cmp     byte [net_role], NET_ROLE_HOST
    je      .host
    xor     edi, edi                    ; a guest: to the host, which says it for him
    mov     esi, MT_CHAT
    lea     rdx, [chat_out]
    mov     ecx, 34
    mov     r8d, 1
    call    net_send_to
    jmp     .out
.host:
    movzx   edi, byte [net_self]
    lea     rsi, [chat_out + 1]
    call    chat_say
.out:
    LEAVE_N 1
    ret

; ---- the capture seam and the send helpers ---------------------------------------------------------

; net_capture(rdi buf or 0, esi cap): test seam. With a buffer, net_out / net_send_to / net_send_big_to /
; net_relay append records "slot u8 (255 for net_out and net_relay), type u8, len u16, payload" to it instead
; of sending; net_captured counts the bytes. 0 turns it off.
net_capture:
    mov     [cap_buf], rdi
    mov     [cap_cap], esi
    mov     dword [net_captured], 0
    ret

; cap_record(edi slot, esi type, rdx payload, ecx len) -> eax 1 recorded / 0 the buffer is full. Leaf
cap_record:
    mov     eax, [net_captured]
    mov     r8d, ecx
    cmp     r8d, 0xFFFF
    jbe     .len_ok
    mov     r8d, 0xFFFF
.len_ok:
    lea     r9d, [rax + r8 + 4]
    cmp     r9d, [cap_cap]
    ja      .full
    mov     r10, [cap_buf]
    mov     [r10 + rax], dil
    mov     [r10 + rax + 1], sil
    mov     [r10 + rax + 2], r8w
    lea     r11, [r10 + rax + 4]
    mov     [net_captured], r9d
    mov     rsi, rdx
    mov     rdi, r11
    mov     ecx, r8d
    rep     movsb
    mov     eax, 1
    ret
.full:
    xor     eax, eax
    ret

; net_out(edi type, rsi payload, edx len <= NET_MSG_MAX, ecx reliable) -> eax 1 queued for everyone / 0
; some queue had no room. A host sends to every accepted guest (joining or ready); a guest to the host;
; offline nothing is sent (and 1 returned).
net_out:
    ENTER_N 5, 16
    cmp     byte [net_role], NET_ROLE_OFF
    je      .ok
    mov     ebx, edi
    mov     r12, rsi
    mov     r13d, edx
    mov     r14d, ecx
    cmp     qword [cap_buf], 0
    je      .real
    mov     edi, 255
    mov     esi, ebx
    mov     rdx, r12
    mov     ecx, r13d
    call    cap_record
    jmp     .out
.real:
    cmp     byte [net_role], NET_ROLE_GUEST
    je      .to_host
    mov     dword [rsp], 1              ; result
    mov     r15d, 1
.guest:
    mov     edi, r15d
    call    peer_ptr
    cmp     dword [rax + PEER.state], PEER_FREE
    je      .next
    lea     rdi, [net_ep]
    mov     esi, r15d
    mov     edx, ebx
    mov     rcx, r12
    mov     r8d, r13d
    mov     r9d, r14d
    call    net_ep_send
    test    eax, eax
    jnz     .next
    mov     dword [rsp], 0
.next:
    inc     r15d
    cmp     r15d, NET_MAX_PEERS
    jb      .guest
    mov     eax, [rsp]
    jmp     .out
.to_host:
    lea     rdi, [net_ep]
    xor     esi, esi
    mov     edx, ebx
    mov     rcx, r12
    mov     r8d, r13d
    mov     r9d, r14d
    call    net_ep_send
    jmp     .out
.ok:
    mov     eax, 1
.out:
    LEAVE_N 5, 16
    ret

; net_send_to(edi slot, esi type, rdx payload, ecx len, r8d reliable) -> eax 1 queued / 0 no room.
; A guest's only slot is 0 (the host).
net_send_to:
    cmp     byte [net_role], NET_ROLE_OFF
    je      .ok
    cmp     qword [cap_buf], 0
    jne     cap_record                  ; (edi slot, esi type, rdx payload, ecx len) are its arguments as they are
    mov     r9d, r8d
    mov     r8d, ecx
    mov     rcx, rdx
    mov     edx, esi
    mov     esi, edi
    lea     rdi, [net_ep]
    jmp     net_ep_send
.ok:
    mov     eax, 1
    ret

; net_send_big_to(edi slot, esi type, rdx data, ecx len <= NET_BLOB_MAX) -> eax 1 queued / 0 no room
net_send_big_to:
    cmp     byte [net_role], NET_ROLE_OFF
    je      .ok
    cmp     qword [cap_buf], 0
    jne     cap_record
    mov     r8d, ecx
    mov     rcx, rdx
    mov     edx, esi
    mov     esi, edi
    lea     rdi, [net_ep]
    jmp     net_ep_send_big
.ok:
    mov     eax, 1
    ret

; net_relay(edi from_slot or -1, esi type, rdx payload, ecx len, r8d reliable, xmm0-2 pos (local) or NaN,
; xmm3 range): host only. The message goes to every accepted guest except from_slot; with a position, only
; to the ready guests within range blocks of it.
; Frame: [rsp] x, [rsp+4] y, [rsp+8] z, [rsp+12] range^2, [rsp+16] has a position, [rsp+20] slot
net_relay:
    ENTER_N 5, 32
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .out
    mov     ebx, edi
    mov     r12d, esi
    mov     r13, rdx
    mov     r14d, ecx
    mov     r15d, r8d
    cmp     qword [cap_buf], 0
    je      .real
    mov     edi, 255
    mov     esi, r12d
    mov     rdx, r13
    mov     ecx, r14d
    call    cap_record
    jmp     .out
.real:
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 8], xmm2
    mulss   xmm3, xmm3
    movss   [rsp + 12], xmm3
    ucomiss xmm0, xmm0
    setnp   al
    movzx   eax, al
    mov     [rsp + 16], eax
    mov     dword [rsp + 20], 1
.guest:
    mov     edi, [rsp + 20]
    cmp     edi, ebx
    je      .next                       ; the sender gets nothing back
    call    peer_ptr
    mov     rcx, rax
    cmp     dword [rcx + PEER.state], PEER_FREE
    je      .next
    cmp     dword [rsp + 16], 0
    je      .send
    cmp     dword [rcx + PEER.state], PEER_READY
    jne     .next
    movss   xmm0, [rcx + PEER.body + BODY.x]
    subss   xmm0, [rsp]
    mulss   xmm0, xmm0
    movss   xmm1, [rcx + PEER.body + BODY.y]
    subss   xmm1, [rsp + 4]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    movss   xmm1, [rcx + PEER.body + BODY.z]
    subss   xmm1, [rsp + 8]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [rsp + 12]
    ja      .next
.send:
    lea     rdi, [net_ep]
    mov     esi, [rsp + 20]
    mov     edx, r12d
    mov     rcx, r13
    mov     r8d, r14d
    mov     r9d, r15d
    call    net_ep_send
.next:
    inc     dword [rsp + 20]
    cmp     dword [rsp + 20], NET_MAX_PEERS
    jb      .guest
.out:
    LEAVE_N 5, 32
    ret

; net_flush(): the end of the frame: whatever was queued goes out
net_flush:
    cmp     byte [net_role], NET_ROLE_OFF
    jne     .go
    cmp     byte [net_join_active], 0
    je      .ret
.go:
    lea     rdi, [net_ep]
    jmp     net_ep_flush
.ret:
    ret

; netsync_dispatch(edi slot, esi type, rdx payload, ecx len): the transport's deliver function. The handler
; of the type gets the same arguments; an unknown type is dropped, and so is everything of the world (type
; 20 and up) that reaches a guest before game_join: the column replies cover what it missed. While a join is
; running and the role is not set yet, the events that wait in the transport's queue are handled before the
; message (the transport can hand the host's first messages over in the very poll that produced NE_ACCEPTED),
; and each message stamps when its sender was last heard (net_peer_rx).
netsync_dispatch:
    cmp     esi, NUM_MT
    jae     .drop
    cmp     byte [net_role], NET_ROLE_OFF
    jne     .stamp
    cmp     byte [net_join_active], 0
    je      .gate
    push    rdi                         ; a join is running and this peer is no guest yet: the transport may hand over
    push    rsi                         ; the host's first messages in the very poll that produced NE_ACCEPTED. The
    push    rdx                         ; events that wait are handled first, so the role is right when the message is
    push    rcx
    sub     rsp, 8
    call    join_events
    add     rsp, 8
    pop     rcx
    pop     rdx
    pop     rsi
    pop     rdi
    cmp     byte [net_role], NET_ROLE_OFF
    je      .gate
.stamp:
    cmp     edi, NET_MAX_PEERS
    jae     .gate
    mov     r8d, edi                    ; each side notes when it last heard each peer (a host: its guests, so a name is
    mov     r9, [net_pump_now]          ; only taken over from one that has gone quiet; a guest: the host, so a loading
    lea     r10, [net_peer_rx]          ; screen can tell it is lost); the handler's arguments (rdx, rcx) stay as they are
    mov     [r10 + r8*8], r9
.gate:
    cmp     esi, 20
    jb      .go
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .go
    cmp     byte [net_in_world], 0
    je      .drop
.go:
    lea     rax, [net_handlers]
    mov     rax, [rax + rsi*8]
    test    rax, rax
    jz      .drop
    jmp     rax
.drop:
    ret

; ---- the remote players ------------------------------------------------------------------------

; pstate_sanitize(rdi PSTATE*): a state comes off the wire: the floats made finite and clamped (a NaN gives the
; second operand of max/min: the limit), the ids inside their tables. Leaf
pstate_sanitize:
    movss   xmm0, [rdi + PSTATE.pos + NPOS.y]
    maxss   xmm0, [f_y_min]
    minss   xmm0, [f_y_max]
    movss   [rdi + PSTATE.pos + NPOS.y], xmm0
    movss   xmm0, [rdi + PSTATE.yaw]
    maxss   xmm0, [f_ang_min]
    minss   xmm0, [f_ang_max]
    movss   [rdi + PSTATE.yaw], xmm0
    movss   xmm0, [rdi + PSTATE.pitch]
    maxss   xmm0, [f_pitch_min]
    minss   xmm0, [f_pitch_max]
    movss   [rdi + PSTATE.pitch], xmm0
    movzx   eax, byte [rdi + PSTATE.level]
    lea     ecx, [rax - 1]
    cmp     ecx, MAX_LEVEL - 1
    jbe     .level
    mov     byte [rdi + PSTATE.level], 1
.level:
    cmp     byte [rdi + PSTATE.arch], NUM_ARCHETYPES
    jbe     .arch
    mov     byte [rdi + PSTATE.arch], 0
.arch:
    movzx   eax, byte [rdi + PSTATE.held]
    cmp     eax, NUM_ITEMS
    jb      .held
    mov     byte [rdi + PSTATE.held], 0
.held:
    cmp     byte [rdi + PSTATE.boat], MAX_BOATS
    jbe     .boat
    mov     byte [rdi + PSTATE.boat], 0
.boat:
    and     word [rdi + PSTATE.flags], 0x3FF
    ret

; proxy_target(rdi PEER*, esi snap): the target position (local floats) and angles of a peer come from its last
; state (ps); with snap the body is put there at once (a first state, a proxy that just became ready). The
; body's box is set every time.
proxy_target:
    ENTER_N 2
    mov     rbx, rdi
    mov     r12d, esi
    lea     rdi, [rbx + PEER.ps + PSTATE.pos]
    call    net_pos_in
    movss   [rbx + PEER.tx], xmm0
    movss   [rbx + PEER.ty], xmm1
    movss   [rbx + PEER.tz], xmm2
    movss   xmm0, [rbx + PEER.ps + PSTATE.yaw]     ; yaw into [0, 360)
    movaps  xmm1, xmm0
    mulss   xmm1, [f_inv360]
    roundss xmm1, xmm1, 9
    mulss   xmm1, [f_360]
    subss   xmm0, xmm1
    movss   [rbx + PEER.tyaw], xmm0
    mov     eax, [rbx + PEER.ps + PSTATE.pitch]
    mov     [rbx + PEER.tpitch], eax
    mov     eax, [f_half_w]
    mov     [rbx + PEER.body + BODY.half_w], eax
    mov     eax, [f_height]
    mov     [rbx + PEER.body + BODY.height], eax
    mov     eax, [f_speed]
    mov     [rbx + PEER.body + BODY.speed], eax
    test    r12d, r12d
    jz      .out
    mov     eax, [rbx + PEER.tx]
    mov     [rbx + PEER.body + BODY.x], eax
    mov     eax, [rbx + PEER.ty]
    mov     [rbx + PEER.body + BODY.y], eax
    mov     eax, [rbx + PEER.tz]
    mov     [rbx + PEER.body + BODY.z], eax
    mov     eax, [rbx + PEER.tyaw]
    mov     [rbx + PEER.body + BODY.yaw], eax
    mov     eax, [rbx + PEER.tpitch]
    mov     [rbx + PEER.body + BODY.pitch], eax
    xor     eax, eax
    mov     [rbx + PEER.body + BODY.vx], eax
    mov     [rbx + PEER.body + BODY.vy], eax
    mov     [rbx + PEER.body + BODY.vz], eax
    mov     [rbx + PEER.body + BODY.kbx], eax
    mov     [rbx + PEER.body + BODY.kbz], eax
    mov     [rbx + PEER.body + BODY.fall], eax
    mov     [rbx + PEER.body + BODY.blocked], eax
.out:
    LEAVE_N 2
    ret

; proxy_step(rdi PEER*): one fixed step of an avatar. Each axis moves 35 % of the way to its target (farther
; than 6 blocks: it snaps), yaw and pitch follow along the shortest arc, the walk cycle advances 60 degrees per
; block walked, and on_ground / flying come from the state's flags. Leaf
proxy_step:
    movss   xmm0, [rdi + PEER.tx]
    subss   xmm0, [rdi + PEER.body + BODY.x]
    movss   xmm1, [rdi + PEER.ty]
    subss   xmm1, [rdi + PEER.body + BODY.y]
    movss   xmm2, [rdi + PEER.tz]
    subss   xmm2, [rdi + PEER.body + BODY.z]
    movaps  xmm3, xmm0
    mulss   xmm3, xmm3
    movaps  xmm4, xmm1
    mulss   xmm4, xmm4
    addss   xmm3, xmm4
    movaps  xmm4, xmm2
    mulss   xmm4, xmm4
    addss   xmm3, xmm4                  ; distance squared
    comiss  xmm3, [f_snap2]
    jbe     .blend
    mov     eax, [rdi + PEER.tx]
    mov     [rdi + PEER.body + BODY.x], eax
    mov     eax, [rdi + PEER.ty]
    mov     [rdi + PEER.body + BODY.y], eax
    mov     eax, [rdi + PEER.tz]
    mov     [rdi + PEER.body + BODY.z], eax
    jmp     .angles
.blend:
    movss   xmm5, [f_blend]
    mulss   xmm0, xmm5
    mulss   xmm1, xmm5
    mulss   xmm2, xmm5
    movaps  xmm3, xmm0                  ; the horizontal step walks the legs
    mulss   xmm3, xmm3
    movaps  xmm4, xmm2
    mulss   xmm4, xmm4
    addss   xmm3, xmm4
    sqrtss  xmm3, xmm3
    mulss   xmm3, [f_walk_deg]
    addss   xmm3, [rdi + PEER.walk]
    comiss  xmm3, [f_walk_wrap]
    jb      .walk_ok
    subss   xmm3, [f_walk_wrap]
.walk_ok:
    movss   [rdi + PEER.walk], xmm3
    addss   xmm0, [rdi + PEER.body + BODY.x]
    movss   [rdi + PEER.body + BODY.x], xmm0
    addss   xmm1, [rdi + PEER.body + BODY.y]
    movss   [rdi + PEER.body + BODY.y], xmm1
    addss   xmm2, [rdi + PEER.body + BODY.z]
    movss   [rdi + PEER.body + BODY.z], xmm2
.angles:
    movss   xmm0, [rdi + PEER.tyaw]
    subss   xmm0, [rdi + PEER.body + BODY.yaw]
    comiss  xmm0, [f_180]
    jbe     .no_hi
    subss   xmm0, [f_360]
.no_hi:
    movss   xmm1, [f_neg180]
    comiss  xmm1, xmm0
    jbe     .no_lo
    addss   xmm0, [f_360]
.no_lo:
    mulss   xmm0, [f_blend]
    addss   xmm0, [rdi + PEER.body + BODY.yaw]
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jae     .yaw_pos
    addss   xmm0, [f_360]
.yaw_pos:
    comiss  xmm0, [f_360]
    jb      .yaw_ok
    subss   xmm0, [f_360]
.yaw_ok:
    movss   [rdi + PEER.body + BODY.yaw], xmm0
    movss   xmm0, [rdi + PEER.tpitch]
    subss   xmm0, [rdi + PEER.body + BODY.pitch]
    mulss   xmm0, [f_blend]
    addss   xmm0, [rdi + PEER.body + BODY.pitch]
    movss   [rdi + PEER.body + BODY.pitch], xmm0
    movzx   eax, word [rdi + PEER.ps + PSTATE.flags]
    xor     edx, edx
    test    eax, PS_GROUND
    setnz   dl
    mov     [rdi + PEER.body + BODY.on_ground], edx
    xor     edx, edx
    test    eax, PS_FLY
    setnz   dl
    mov     [rdi + PEER.body + BODY.flying], edx
    ret

; net_pstate_build(rdi PSTATE*): the local player's state as it goes on the wire (absolute position)
net_pstate_build:
    ENTER_N 2
    mov     rbx, rdi
    movzx   eax, byte [net_self]
    mov     [rbx + PSTATE.slot], al
    mov     eax, [boat_riding]
    cmp     eax, MAX_BOATS
    jbe     .boat_ok
    xor     eax, eax
.boat_ok:
    mov     [rbx + PSTATE.boat], al
    xor     r12d, r12d
    cmp     dword [player + BODY.on_ground], 0
    je      .f_fly
    or      r12d, PS_GROUND
.f_fly:
    cmp     dword [player + BODY.flying], 0
    je      .f_sneak
    or      r12d, PS_FLY
.f_sneak:
    cmp     dword [frame_input + FRAMEINPUT.move + INPUT.down], 0
    je      .f_sleep
    or      r12d, PS_SNEAK
.f_sleep:
    cmp     dword [sleep_active], 0
    je      .f_dead
    or      r12d, PS_SLEEP
    cmp     dword [sleep_timer], SLEEP_STEPS
    jl      .f_dead
    or      r12d, PS_ASLEEP
.f_dead:
    cmp     dword [surv + SURVIVAL.dead], 0
    je      .f_swing
    or      r12d, PS_DEAD
.f_swing:
    cmp     dword [net_swing_t], 0
    jle     .f_guard
    or      r12d, PS_SWING
.f_guard:
    cmp     dword [combat_guard_t], 0
    jl      .f_hurt
    or      r12d, PS_GUARD
.f_hurt:
    cmp     dword [surv + SURVIVAL.hurt_flash], 0
    jle     .f_stealth
    or      r12d, PS_HURT
.f_stealth:
    cmp     dword [combat_stealth_t], 0
    jle     .f_done
    or      r12d, PS_STEALTH
.f_done:
    mov     [rbx + PSTATE.flags], r12w
    lea     rdi, [rbx + PSTATE.pos]
    movss   xmm0, [player + BODY.x]
    movss   xmm1, [player + BODY.y]
    movss   xmm2, [player + BODY.z]
    call    net_pos_out
    mov     eax, [player + BODY.yaw]
    mov     [rbx + PSTATE.yaw], eax
    mov     eax, [player + BODY.pitch]
    mov     [rbx + PSTATE.pitch], eax
    mov     eax, [surv + SURVIVAL.health]
    xor     ecx, ecx
    test    eax, eax
    cmovs   eax, ecx
    mov     ecx, 0xFFFF
    cmp     eax, ecx
    cmova   eax, ecx
    mov     [rbx + PSTATE.health], ax
    mov     eax, [surv_max_health]
    xor     ecx, ecx
    test    eax, eax
    cmovs   eax, ecx
    mov     ecx, 0xFFFF
    cmp     eax, ecx
    cmova   eax, ecx
    mov     [rbx + PSTATE.max_health], ax
    call    rpg_level
    mov     [rbx + PSTATE.level], al
    call    rpg_archetype
    mov     [rbx + PSTATE.arch], al
    mov     eax, [inv_sel]
    xor     ecx, ecx
    cmp     eax, HOTBAR_SLOTS
    cmovae  eax, ecx
    movzx   eax, byte [inv + INVENTORY.slots + rax*4 + ITEMSTACK.id]
    mov     [rbx + PSTATE.held], al
    mov     byte [rbx + PSTATE.pad], 0
    LEAVE_N 2
    ret

; state_send(): a guest sends the state in its own record to the host (unreliable)
state_send:
    sub     rsp, 8
    movzx   edi, byte [net_self]
    call    peer_ptr
    lea     rdx, [rax + PEER.ps]
    xor     edi, edi
    mov     esi, MT_PSTATE
    mov     ecx, PSTATE_size
    xor     r8d, r8d
    call    net_send_to
    add     rsp, 8
    ret

; players_send(edi guest slot): the host sends one guest the states of everyone else who is ready (itself
; included): "count u8, pad[3], PSTATE x count"
players_send:
    ENTER_N 4
    mov     ebx, edi
    lea     r12, [msg_buf + 4]
    xor     r13d, r13d
    xor     r14d, r14d
.loop:
    cmp     r14d, ebx
    je      .next
    mov     edi, r14d
    call    peer_ptr
    cmp     dword [rax + PEER.state], PEER_READY
    jne     .next
    lea     rsi, [rax + PEER.ps]
    mov     rdi, r12
    mov     ecx, PSTATE_size
    rep     movsb
    mov     r12, rdi
    inc     r13d
.next:
    inc     r14d
    cmp     r14d, NET_MAX_PEERS
    jb      .loop
    mov     [msg_buf], r13b
    mov     word [msg_buf + 1], 0
    mov     byte [msg_buf + 3], 0
    imul    ecx, r13d, PSTATE_size
    add     ecx, 4
    mov     edi, ebx
    mov     esi, MT_PLAYERS
    lea     rdx, [msg_buf]
    xor     r8d, r8d
    call    net_send_to
    LEAVE_N 4
    ret

; net_tick(): the end of every fixed step. The proxies advance one step. Every SNAP_STEPS steps the local
; state is rebuilt; a guest sends it to the host (and its boat pose), the host sends every ready guest the
; others' states and the world snapshot.
net_tick:
    cmp     byte [net_role], NET_ROLE_OFF
    jne     .on
    ret
.on:
    ENTER_N 3
    mov     eax, [net_swing_t]
    test    eax, eax
    jle     .swing_done
    dec     eax
    mov     [net_swing_t], eax
.swing_done:
    xor     ebx, ebx
.proxy:
    movzx   eax, byte [net_self]
    cmp     ebx, eax
    je      .proxy_next
    mov     edi, ebx
    call    peer_ptr
    cmp     dword [rax + PEER.state], PEER_READY
    jne     .proxy_next
    mov     rdi, rax
    call    proxy_step
.proxy_next:
    inc     ebx
    cmp     ebx, NET_MAX_PEERS
    jb      .proxy
    inc     dword [net_step_ctr]
    cmp     dword [net_step_ctr], SNAP_STEPS
    jb      .out
    mov     dword [net_step_ctr], 0
    movzx   edi, byte [net_self]
    call    peer_ptr
    lea     rdi, [rax + PEER.ps]
    call    net_pstate_build
    cmp     byte [net_role], NET_ROLE_HOST
    je      .host
    cmp     byte [ready_sent], 0
    je      .out
    call    state_send
    call    net_boat_tick
    jmp     .out
.host:
    mov     ebx, 1
.send:
    mov     edi, ebx
    call    peer_ptr
    cmp     dword [rax + PEER.state], PEER_READY
    jne     .send_next
    mov     edi, ebx
    call    players_send
    mov     edi, ebx
    call    nm_snap_send
.send_next:
    inc     ebx
    cmp     ebx, NET_MAX_PEERS
    jb      .send
.out:
    LEAVE_N 3
    ret

; net_peer_body(edi slot) -> rax the BODY of that player: `player` for the local slot, the proxy of a ready
; peer, else 0. Leaf
net_peer_body:
    cmp     edi, NET_MAX_PEERS
    jae     .none
    movzx   eax, byte [net_self]
    cmp     edi, eax
    je      .self
    imul    eax, edi, PEER_size
    lea     rdx, [net_peers]
    add     rax, rdx
    cmp     dword [rax + PEER.state], PEER_READY
    jne     .none
    add     rax, PEER.body
    ret
.self:
    lea     rax, [player]
    ret
.none:
    xor     eax, eax
    ret

; net_stream_centres(rdi int32[2 * 7] out) -> eax n: the absolute chunk column (acx, acz) of every ready guest
; (host only; 0 elsewhere). Leaf
net_stream_centres:
    xor     eax, eax
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    mov     ecx, 1
.loop:
    imul    edx, ecx, PEER_size
    lea     r8, [net_peers]
    add     r8, rdx
    cmp     dword [r8 + PEER.state], PEER_READY
    jne     .next
    mov     edx, [r8 + PEER.ps + PSTATE.pos + NPOS.ax]
    sar     edx, 4
    mov     [rdi + rax*8], edx
    mov     edx, [r8 + PEER.ps + PSTATE.pos + NPOS.az]
    sar     edx, 4
    mov     [rdi + rax*8 + 4], edx
    inc     eax
.next:
    inc     ecx
    cmp     ecx, NET_MAX_PEERS
    jb      .loop
.ret:
    ret

; net_nearest_dist2(xmm0 x, xmm1 z) -> xmm0 squared horizontal distance to the nearest player in any state (the
; local player and every ready proxy, dead or not). Leaf
net_nearest_dist2:
    movss   xmm2, xmm0
    subss   xmm2, [player + BODY.x]
    mulss   xmm2, xmm2
    movss   xmm3, xmm1
    subss   xmm3, [player + BODY.z]
    mulss   xmm3, xmm3
    addss   xmm2, xmm3
    cmp     byte [net_role], NET_ROLE_OFF
    je      .done
    xor     ecx, ecx
.loop:
    movzx   eax, byte [net_self]
    cmp     ecx, eax
    je      .next
    imul    edx, ecx, PEER_size
    lea     r8, [net_peers]
    add     r8, rdx
    cmp     dword [r8 + PEER.state], PEER_READY
    jne     .next
    movss   xmm3, xmm0
    subss   xmm3, [r8 + PEER.body + BODY.x]
    mulss   xmm3, xmm3
    movss   xmm4, xmm1
    subss   xmm4, [r8 + PEER.body + BODY.z]
    mulss   xmm4, xmm4
    addss   xmm3, xmm4
    minss   xmm2, xmm3
.next:
    inc     ecx
    cmp     ecx, NET_MAX_PEERS
    jb      .loop
.done:
    movaps  xmm0, xmm2
    ret

; net_shift(edi dx, esi dz): the local origin moved by (dx, dz): every proxy body and target drops by it (the
; wire positions are absolute and stay), then the mirrored entities follow (nm_shift)
net_shift:
    cmp     byte [net_role], NET_ROLE_OFF
    jne     .on
    ret
.on:
    ENTER_N 2
    mov     ebx, edi
    mov     r12d, esi
    cvtsi2ss xmm0, ebx
    cvtsi2ss xmm1, r12d
    xor     ecx, ecx
.loop:
    movzx   eax, byte [net_self]
    cmp     ecx, eax
    je      .next
    imul    edx, ecx, PEER_size
    lea     r8, [net_peers]
    add     r8, rdx
    cmp     dword [r8 + PEER.state], PEER_FREE
    je      .next
    movss   xmm2, [r8 + PEER.body + BODY.x]
    subss   xmm2, xmm0
    movss   [r8 + PEER.body + BODY.x], xmm2
    movss   xmm2, [r8 + PEER.tx]
    subss   xmm2, xmm0
    movss   [r8 + PEER.tx], xmm2
    movss   xmm2, [r8 + PEER.body + BODY.z]
    subss   xmm2, xmm1
    movss   [r8 + PEER.body + BODY.z], xmm2
    movss   xmm2, [r8 + PEER.tz]
    subss   xmm2, xmm1
    movss   [r8 + PEER.tz], xmm2
.next:
    inc     ecx
    cmp     ecx, NET_MAX_PEERS
    jb      .loop
    mov     edi, ebx
    mov     esi, r12d
    call    nm_shift
    LEAVE_N 2
    ret

; ---- the host ----------------------------------------------------------------------------------

; chat_text2(rdi a zstr, rsi b zstr): the log gets a followed by b
chat_text2:
    ENTER_N 1
    mov     rbx, rsi
    mov     rsi, rdi
    lea     rdi, [chat_tmp]
    call    str_append
    mov     rdi, rax
    mov     rsi, rbx
    call    str_append
    mov     byte [rax], 0
    lea     rdi, [chat_tmp]
    call    chat_add
    LEAVE_N 1
    ret

; players_path(rdi name zstr) -> rax "<world dir>/players/<name>.hdr" (in path_buf). The name was checked
; (net_valid_name) when its guest was accepted
players_path:
    ENTER_N 1
    mov     rbx, rdi
    lea     rdi, [path_buf]
    lea     rsi, [app_world_path]
    mov     edx, 3900
    call    str_copy
    mov     rdi, rax
    lea     rsi, [s_players_sl]
    call    str_append
    mov     rdi, rax
    mov     rsi, rbx
    call    str_append
    mov     rdi, rax
    lea     rsi, [s_hdr_ext]
    call    str_append
    mov     byte [rax], 0
    lea     rax, [path_buf]
    LEAVE_N 1
    ret

; standing_send(edi slot): the world's faction standings and champion bits to one guest
standing_send:
    ENTER_N 1
    mov     ebx, edi
    lea     rsi, [world_header + WORLDHDR.standing]
    lea     rdi, [msg_buf]
    mov     ecx, 16
    rep     movsb
    mov     al, [world_header + WORLDHDR.champions]
    mov     [msg_buf + 16], al
    mov     byte [msg_buf + 17], 0
    mov     edi, ebx
    mov     esi, MT_STANDING
    lea     rdx, [msg_buf]
    mov     ecx, 18
    mov     r8d, 1
    call    net_send_to
    LEAVE_N 1
    ret

; host_welcome(edi slot): the first messages of a new guest, in the order it needs them: the world, who is
; there, its character (the saved one or a fresh one), the standings. All reliable and ordered.
; rbx = the guest, r12 = the WORLDINFO under construction (msg_buf), r13d = the peer being listed
host_welcome:
    ENTER_N 4
    mov     ebx, edi
    lea     rdi, [msg_buf]
    mov     ecx, WINFO_size
    xor     eax, eax
    rep     stosb
    lea     r12, [msg_buf]
    mov     eax, [world_header + WORLDHDR.seed]
    mov     [r12 + WINFO.seed], eax
    mov     eax, [game_mode]
    mov     [r12 + WINFO.mode], eax
    mov     eax, [game_time]
    mov     [r12 + WINFO.time], eax
    lea     rdi, [r12 + WINFO.name]
    lea     rsi, [world_header + WORLDHDR.name]
    mov     edx, 32
    call    str_copy
    mov     al, [net_pvp]
    mov     [r12 + WINFO.pvp], al
    mov     [r12 + WINFO.your_slot], bl
    mov     al, [world_header + WORLDHDR.cheater]
    mov     [r12 + WINFO.cheater], al
    mov     eax, [world_header + WORLDHDR.spawn_x]
    mov     [r12 + WINFO.spawn_x], eax
    mov     eax, [world_header + WORLDHDR.spawn_y]
    mov     [r12 + WINFO.spawn_y], eax
    mov     eax, [world_header + WORLDHDR.spawn_z]
    mov     [r12 + WINFO.spawn_z], eax
    lea     rsi, [world_header + WORLDHDR.standing]
    lea     rdi, [r12 + WINFO.standing]
    mov     ecx, 16
    rep     movsb
    mov     al, [world_header + WORLDHDR.champions]
    mov     [r12 + WINFO.champions], al
    mov     al, [rpg_state + RPGSAVE.quest]
    mov     [r12 + WINFO.quest], al
    mov     al, [rpg_state + RPGSAVE.quest_state]
    mov     [r12 + WINFO.quest_state], al
    mov     ax, [rpg_state + RPGSAVE.quest_progress]
    mov     [r12 + WINFO.quest_progress], ax
    mov     edi, ebx
    mov     esi, MT_WORLDINFO
    mov     rdx, r12
    mov     ecx, WINFO_size
    mov     r8d, 1
    call    net_send_to
    xor     r13d, r13d                  ; everyone who is in the world (the host and the new guest included)
.peers:
    mov     edi, r13d
    call    peer_ptr
    cmp     dword [rax + PEER.state], PEER_FREE
    je      .peers_next
    mov     [msg_buf], r13b
    lea     rdi, [msg_buf + 1]
    lea     rsi, [rax + PEER.name]
    mov     ecx, 17
    rep     movsb
    mov     edi, ebx
    mov     esi, MT_PEER_JOIN
    lea     rdx, [msg_buf]
    mov     ecx, 18
    mov     r8d, 1
    call    net_send_to
.peers_next:
    inc     r13d
    cmp     r13d, NET_MAX_PEERS
    jb      .peers
    mov     edi, ebx                    ; the character: its saved image, or a fresh one
    call    peer_ptr
    lea     rdi, [rax + PEER.name]
    call    players_path
    mov     rdi, rax
    lea     rsi, [pl_buf]
    mov     edx, WORLD_HDR_SIZE + 1
    call    file_read
    cmp     rax, WORLD_HDR_SIZE
    jne     .fresh
    mov     rax, [m_v6]
    cmp     [pl_buf], rax
    jne     .fresh
    mov     edi, ebx
    mov     esi, MT_PLAYER_IMAGE
    lea     rdx, [pl_buf]
    mov     ecx, PLAYER_IMG_SIZE
    call    net_send_big_to
    jmp     .standing
.fresh:
    mov     edi, ebx
    mov     esi, MT_PLAYER_FRESH
    xor     edx, edx
    xor     ecx, ecx
    mov     r8d, 1
    call    net_send_to
.standing:
    mov     edi, ebx
    call    standing_send
    LEAVE_N 4
    ret

; peer_join_broadcast(edi slot): every other guest learns of the new one
peer_join_broadcast:
    ENTER_N 2
    mov     ebx, edi
    call    peer_ptr
    mov     [msg_buf], bl
    lea     rdi, [msg_buf + 1]
    lea     rsi, [rax + PEER.name]
    mov     ecx, 17
    rep     movsb
    mov     r12d, 1
.loop:
    cmp     r12d, ebx
    je      .next
    mov     edi, r12d
    call    peer_ptr
    cmp     dword [rax + PEER.state], PEER_FREE
    je      .next
    mov     edi, r12d
    mov     esi, MT_PEER_JOIN
    lea     rdx, [msg_buf]
    mov     ecx, 18
    mov     r8d, 1
    call    net_send_to
.next:
    inc     r12d
    cmp     r12d, NET_MAX_PEERS
    jb      .loop
    LEAVE_N 2
    ret

; net_peer_replaceable(edi slot, rsi NETEVENT* of a CONNECT) -> eax 1 when the guest in that slot is gone, so its
; name may go to the new connection: the request comes from the address that guest connected from (one socket
; cannot live twice: the player restarted on the same port), or nobody has heard from the guest for 3 s (a killed
; process says nothing; a live guest sends its state twenty times a second). The host's own slot never is. Leaf
net_peer_replaceable:
    cmp     edi, 1
    jb      .no
    cmp     edi, NET_MAX_PEERS
    jae     .no
    mov     eax, edi
    lea     rcx, [net_peer_addr]
    mov     edx, [rsi + NETEVENT.addr + NADDR.ip]
    cmp     edx, [rcx + rax*8 + NADDR.ip]
    jne     .silent
    movzx   edx, word [rsi + NETEVENT.addr + NADDR.port]
    cmp     dx, [rcx + rax*8 + NADDR.port]
    je      .yes
.silent:
    lea     rcx, [net_peer_rx]
    mov     rdx, [net_pump_now]
    sub     rdx, [rcx + rax*8]
    mov     r8, SILENT_NS
    cmp     rdx, r8
    jg      .yes
.no:
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; peer_evict(edi slot): the guest in that slot is replaced by a new connection of the same name (net_peer_replaceable
; says its old one is dead). The old connection is dropped (a guest that was only hung hears of it when it wakes),
; the slot is freed as for a timeout and everyone is told
peer_evict:
    ENTER_N 1
    mov     ebx, edi
    lea     rdi, [net_ep]
    mov     esi, ebx
    mov     edx, DENY_NAME
    call    net_ep_drop
    mov     edi, ebx
    mov     esi, SYS_TIMEOUT
    call    peer_gone
    LEAVE_N 1
    ret

; host_on_connect(rdi NETEVENT*): a connection request. The name must be valid and not be the host's or any
; guest's, and a slot must be free; the guest then gets the welcome sequence
host_on_connect:
    ENTER_N 4
    mov     rbx, rdi
    mov     byte [rbx + NETEVENT.name + NAME_MAX], 0
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .closed
    lea     rdi, [rbx + NETEVENT.name]
    call    net_valid_name
    test    eax, eax
    jz      .bad_name
    xor     r12d, r12d
.names:
    mov     edi, r12d
    call    peer_ptr
    cmp     dword [rax + PEER.state], PEER_FREE
    je      .names_next
    lea     rdi, [rax + PEER.name]
    lea     rsi, [rbx + NETEVENT.name]
    call    str_eq
    test    eax, eax
    jz      .names_next
    mov     edi, r12d                   ; the name is in use: refused, unless this is the dead connection of that
    mov     rsi, rbx                    ; very player coming back
    call    net_peer_replaceable
    test    eax, eax
    jz      .bad_name
    mov     edi, r12d
    call    peer_evict
.names_next:
    inc     r12d
    cmp     r12d, NET_MAX_PEERS
    jb      .names
    mov     r12d, 1
.slot:
    mov     edi, r12d
    call    peer_ptr
    cmp     dword [rax + PEER.state], PEER_FREE
    je      .got
    inc     r12d
    cmp     r12d, NET_MAX_PEERS
    jb      .slot
    mov     edx, DENY_FULL
    jmp     .deny
.got:
    mov     r13, rax
    lea     rdi, [net_ep]
    mov     esi, r12d
    mov     rdx, rbx
    call    net_ep_accept
    mov     rax, [rbx + NETEVENT.addr]  ; where the guest connected from, and when it was last heard (now)
    lea     rcx, [net_peer_addr]
    mov     [rcx + r12*8], rax
    mov     rax, [net_pump_now]
    lea     rcx, [net_peer_rx]
    mov     [rcx + r12*8], rax
    mov     rdi, r13
    lea     rsi, [rbx + NETEVENT.name]
    mov     edx, PEER_JOINING
    call    peer_init
    lea     rdi, [rbx + NETEVENT.name]
    mov     esi, r12d
    movzx   edx, byte [rbx + NETEVENT.relay]
    call    log_name_slot
    mov     edi, r12d
    call    host_welcome
    mov     edi, r12d
    call    peer_join_broadcast
    jmp     .out
.bad_name:
    mov     edx, DENY_NAME
    jmp     .deny
.closed:
    mov     edx, DENY_CLOSED
.deny:
    lea     rdi, [net_ep]
    mov     rsi, rbx
    call    net_ep_deny
.out:
    LEAVE_N 4
    ret

; peer_try_ready(edi slot): a joining guest that has said READY and sent a first state becomes ready: from now
; on the world counts it (snapshots, targeting, the columns around it) and everybody hears that it joined
peer_try_ready:
    ENTER_N 3
    mov     ebx, edi
    call    peer_ptr
    mov     r12, rax
    cmp     dword [r12 + PEER.state], PEER_JOINING
    jne     .out
    cmp     byte [r12 + PEER.pad0], 0           ; pad0[0]: a state arrived, pad0[1]: READY arrived
    je      .out
    cmp     byte [r12 + PEER.pad0 + 1], 0
    je      .out
    mov     dword [r12 + PEER.state], PEER_READY
    mov     edi, ebx
    lea     rsi, [s_t_joined]
    call    chat_named
    mov     byte [msg_buf], SYS_JOINED
    mov     [msg_buf + 1], bl
    mov     word [msg_buf + 2], 0
    mov     r13d, 1
.loop:
    mov     edi, r13d
    call    peer_ptr
    cmp     dword [rax + PEER.state], PEER_READY
    jne     .next
    mov     edi, r13d
    mov     esi, MT_SYS
    lea     rdx, [msg_buf]
    mov     ecx, 4
    mov     r8d, 1
    call    net_send_to
.next:
    inc     r13d
    cmp     r13d, NET_MAX_PEERS
    jb      .loop
    mov     edi, ebx                    ; what changed while it downloaded the world (its handlers drop those
    call    standing_send               ; messages before game_join): the standings, the quest chain and the PvP
    mov     edi, ebx                    ; rule as they are now
    call    quest_sync_send
    mov     edi, ebx
    call    pvp_send
.out:
    LEAVE_N 3
    ret

; quest_sync_send(edi slot): the quest chain's position (quest, state, progress) to one guest
quest_sync_send:
    ENTER_N 1
    mov     ebx, edi
    mov     al, [rpg_state + RPGSAVE.quest]
    mov     [msg_buf], al
    mov     al, [rpg_state + RPGSAVE.quest_state]
    mov     [msg_buf + 1], al
    mov     ax, [rpg_state + RPGSAVE.quest_progress]
    mov     [msg_buf + 2], ax
    mov     edi, ebx
    mov     esi, MT_QUEST_SYNC
    lea     rdx, [msg_buf]
    mov     ecx, 4
    mov     r8d, 1
    call    net_send_to
    LEAVE_N 1
    ret

; pvp_send(edi slot): the PvP rule to one guest
pvp_send:
    ENTER_N 1
    mov     ebx, edi
    mov     al, [net_pvp]
    mov     [msg_buf], al
    mov     edi, ebx
    mov     esi, MT_PVP
    lea     rdx, [msg_buf]
    mov     ecx, 1
    mov     r8d, 1
    call    net_send_to
    LEAVE_N 1
    ret

; chat_named(edi slot, rsi suffix zstr): the log gets "<name of the slot><suffix>"
chat_named:
    sub     rsp, 8
    mov     [rsp], rsi
    call    peer_name
    mov     rdi, rax
    mov     rsi, [rsp]
    call    chat_text2
    add     rsp, 8
    ret

; peer_gone(edi slot, esi sys): a guest's connection ended (SYS_LEFT: it said goodbye, SYS_TIMEOUT: it went
; silent). Its slot frees, the boat it rode is free, everyone is told.
; Frame: [rsp] its name (17). r14d = the guest being told
peer_gone:
    ENTER_N 4, 32
    cmp     edi, 1
    jb      .out
    cmp     edi, NET_MAX_PEERS
    jae     .out
    mov     ebx, edi
    mov     r12d, esi
    call    peer_ptr
    mov     r13, rax
    cmp     dword [r13 + PEER.state], PEER_FREE
    je      .out
    lea     rdi, [rsp]
    lea     rsi, [r13 + PEER.name]
    mov     edx, NAME_MAX
    call    str_copy
    lea     rcx, [boat_rider]                   ; the boat it rode is free again
    lea     edx, [rbx + 1]
    xor     eax, eax
.boat:
    cmp     byte [rcx + rax], dl
    jne     .boat_next
    mov     byte [rcx + rax], 0
.boat_next:
    inc     eax
    cmp     eax, MAX_BOATS
    jb      .boat
    mov     rdi, r13                            ; the record is gone (its open container, its proxy with it)
    mov     ecx, PEER_size
    xor     eax, eax
    rep     stosb
    mov     [msg_buf], bl
    mov     [msg_buf + 1], r12b
    mov     r14d, 1
.tell:
    mov     edi, r14d
    call    peer_ptr
    cmp     dword [rax + PEER.state], PEER_FREE
    je      .tell_next
    mov     edi, r14d
    mov     esi, MT_PEER_LEAVE
    lea     rdx, [msg_buf]
    mov     ecx, 2
    mov     r8d, 1
    call    net_send_to
.tell_next:
    inc     r14d
    cmp     r14d, NET_MAX_PEERS
    jb      .tell
    lea     rdi, [rsp]                          ; chat line and log line
    lea     rsi, [s_t_left]
    lea     rdx, [s_t_lost]
    cmp     r12d, SYS_TIMEOUT
    cmove   rsi, rdx
    call    chat_text2
    call    log_start
    mov     rdi, rax
    lea     rsi, [rsp]
    call    str_append
    mov     rdi, rax
    lea     rsi, [s_left_t]
    lea     rdx, [s_left_to]
    cmp     r12d, SYS_TIMEOUT
    cmove   rsi, rdx
    call    str_append
    mov     rdi, rax
    call    log_flush
.out:
    LEAVE_N 4, 32
    ret

; peers_ready_count() -> eax the peers that are ready (the host included). Leaf
peers_ready_count:
    xor     eax, eax
    xor     ecx, ecx
    lea     rdx, [net_peers + PEER.state]
.loop:
    cmp     dword [rdx], PEER_READY
    sete    r8b
    movzx   r8d, r8b
    add     eax, r8d
    add     rdx, PEER_size
    inc     ecx
    cmp     ecx, NET_MAX_PEERS
    jb      .loop
    ret

; net_host_open(edi port) -> eax 0 or -errno: the world that is open becomes a multiplayer world. The socket is
; bound to port .. port + 9, this peer is slot 0, the render distance is capped (the area of seven guests must
; fit the column table), the rendezvous server learns of the room, <world dir>/players exists.
; Frame: [rsp] a NADDR (the LAN endpoint). rbx = the port asked for, r12d = the port bound
net_host_open:
    ENTER_N 3, 16
    xor     eax, eax
    cmp     byte [net_role], NET_ROLE_OFF
    jne     .out                        ; (already open)
    mov     ebx, edi
    call    ep_close_stale              ; (the leftover of a failed join)
    lea     rdi, [net_ep]
    mov     esi, ebx
    mov     edx, 10
    call    net_ep_open
    test    eax, eax
    js      .out
    mov     r12d, eax
    mov     byte [ep_open], 1
    mov     byte [net_role], NET_ROLE_HOST
    mov     byte [net_self], 0
    mov     dword [net_rdist_cap], MP_HOST_RDIST
    mov     dword [net_step_ctr], 0
    mov     dword [net_end_reason], 0
    mov     byte [rv_fail_logged], 0
    mov     byte [net_room_code], 0
    mov     dword [chat_count], 0
    mov     dword [chat_head], 0
    call    peers_clear
    lea     rdi, [net_session_name]
    lea     rsi, [net_cfg_name]
    mov     edx, NAME_MAX
    call    str_copy
    lea     rdi, [net_peers]
    lea     rsi, [net_session_name]
    mov     edx, PEER_READY
    call    peer_init
    lea     rdi, [net_ep]
    lea     rsi, [net_cfg_server]
    call    net_ep_rv_host
    lea     rdi, [net_cfg_server]
    call    net_local_ip
    mov     [rsp], eax
    mov     eax, r12d
    rol     ax, 8                       ; the port in network byte order
    mov     [rsp + 4], ax
    mov     word [rsp + 6], 0
    mov     rdi, rsp
    lea     rsi, [net_lan_text]
    call    net_format_addr
    mov     byte [rax], 0
    mov     edi, r12d
    call    log_hosting
    lea     rdi, [path_buf]
    lea     rsi, [app_world_path]
    mov     edx, 3900
    call    str_copy
    mov     rdi, rax
    lea     rsi, [s_players]
    call    str_append
    mov     byte [rax], 0
    lea     rdi, [path_buf]
    xor     esi, esi
    call    mkdir_p
    call    title_set
    xor     eax, eax
.out:
    LEAVE_N 3, 16
    ret

; net_host_close(): the world stops being shared. Every guest is told (HOST_CLOSING), the ready ones send their
; characters one last time (the loop waits for them, at most 3 s, behind a loading screen), then every
; connection is dropped and the socket closed. Blocks, pumping.
net_host_close:
    ENTER_N 3
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .out
    mov     r12d, 1
.tell:
    mov     edi, r12d
    call    peer_ptr
    cmp     dword [rax + PEER.state], PEER_FREE
    je      .tell_next
    mov     dword [rax + PEER.saved], 0
    mov     edi, r12d
    mov     esi, MT_HOST_CLOSING
    xor     edx, edx
    xor     ecx, ecx
    mov     r8d, 1
    call    net_send_to
.tell_next:
    inc     r12d
    cmp     r12d, NET_MAX_PEERS
    jb      .tell
    call    time_mono_ns
    mov     rbx, rax
.wait:
    call    glfwPollEvents
    call    net_pump
    call    net_flush
    xor     r12d, r12d                  ; r12d = a ready guest whose character has not arrived: 1
    mov     r13d, 1
.pending:
    mov     edi, r13d
    call    peer_ptr
    cmp     dword [rax + PEER.state], PEER_READY
    jne     .pending_next
    cmp     dword [rax + PEER.saved], 0
    jne     .pending_next
    mov     r12d, 1
.pending_next:
    inc     r13d
    cmp     r13d, NET_MAX_PEERS
    jb      .pending
    test    r12d, r12d
    jz      .drop
    call    time_mono_ns
    sub     rax, rbx
    mov     rcx, SAVE_WAIT_NS
    cmp     rax, rcx
    jae     .drop
    lea     rdi, [s_saving_pl]
    call    app_show_loading
    mov     edi, 2000
    call    usleep
    jmp     .wait
.drop:
    mov     r12d, 1
.drop_one:
    mov     edi, r12d
    call    peer_ptr
    cmp     dword [rax + PEER.state], PEER_FREE
    je      .drop_next
    lea     rdi, [net_ep]
    mov     esi, r12d
    mov     edx, DENY_CLOSED
    call    net_ep_drop
.drop_next:
    inc     r12d
    cmp     r12d, NET_MAX_PEERS
    jb      .drop_one
    lea     rdi, [boat_rider]           ; nobody rides any more: the boats are free in the next session
    mov     ecx, MAX_BOATS
    xor     eax, eax
    rep     stosb
    call    net_session_reset
.out:
    LEAVE_N 3
    ret

; net_host_info(rdi out zstr 64): "Room ABC123 - 3 players", "Direct only - 3 players" (the rendezvous server
; did not answer), "Opening room - 3 players" (it has not yet); empty when this peer is not hosting
net_host_info:
    ENTER_N 3
    mov     rbx, rdi
    mov     byte [rbx], 0
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .out
    lea     rdi, [net_ep]
    call    net_ep_rv_state
    mov     r12d, eax
    mov     rdi, rbx
    cmp     r12d, RVS_OK
    je      .room
    lea     rsi, [s_info_open]
    cmp     r12d, RVS_FAIL
    jne     .text
    lea     rsi, [s_info_direct]
    jmp     .text
.room:
    lea     rdi, [net_ep]
    lea     rsi, [net_room_code]
    call    net_ep_room_code
    mov     rdi, rbx
    lea     rsi, [s_info_room]
    call    str_append
    mov     rdi, rax
    lea     rsi, [net_room_code]
.text:
    call    str_append
    mov     rdi, rax
    lea     rsi, [s_info_sep]
    call    str_append
    mov     r13, rax
    call    peers_ready_count
    mov     rdi, r13
    mov     esi, eax
    call    app_num
    mov     rdi, rax
    lea     rsi, [s_info_players]
    call    str_append
    mov     byte [rax], 0
.out:
    LEAVE_N 3
    ret

; net_set_pvp(edi on): host only. Players hurt each other (melee, projectiles, their explosions) when on; everyone
; is told, in a message and in the chat
net_set_pvp:
    ENTER_N 1
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .out
    and     edi, 1
    mov     ebx, edi
    cmp     bl, [net_pvp]
    je      .out
    mov     [net_pvp], bl
    mov     [msg_buf], bl
    mov     edi, MT_PVP
    lea     rsi, [msg_buf]
    mov     edx, 1
    mov     ecx, 1
    call    net_out
    mov     byte [msg_buf], SYS_PVP
    mov     byte [msg_buf + 1], 0
    mov     [msg_buf + 2], bl
    mov     byte [msg_buf + 3], 0
    mov     edi, MT_SYS
    lea     rsi, [msg_buf]
    mov     edx, 4
    mov     ecx, 1
    call    net_out
    lea     rdi, [s_pvp_off]
    lea     rsi, [s_pvp_on]
    test    ebx, ebx
    cmovnz  rdi, rsi
    call    chat_add
.out:
    LEAVE_N 1
    ret

; announce_death(edi slot, esi cause): host. "NAME: <cause>" in the chat of everyone
announce_death:
    ENTER_N 2
    mov     ebx, edi
    mov     r12d, esi
    call    chat_death_line
    mov     byte [msg_buf], SYS_DIED
    mov     [msg_buf + 1], bl
    mov     [msg_buf + 2], r12b
    mov     byte [msg_buf + 3], 0
    mov     edi, MT_SYS
    lea     rsi, [msg_buf]
    mov     edx, 4
    mov     ecx, 1
    call    net_out
    LEAVE_N 2
    ret

; net_died_out(edi cause): the local player died. A guest tells the host; the host tells everybody itself
net_died_out:
    ENTER_N 1
    mov     ebx, edi
    cmp     byte [net_role], NET_ROLE_HOST
    je      .host
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .out
    mov     [msg_buf], bl
    xor     edi, edi
    mov     esi, MT_DIED
    lea     rdx, [msg_buf]
    mov     ecx, 1
    mov     r8d, 1
    call    net_send_to
    jmp     .out
.host:
    xor     edi, edi
    mov     esi, ebx
    call    announce_death
.out:
    LEAVE_N 1
    ret

; ---- window title, session end ---------------------------------------------------------------

; title_set(): the window says "AssemblyCraft - <name>" for as long as the session lasts
title_set:
    sub     rsp, 8
    lea     rdi, [net_title_text]
    lea     rsi, [s_title_pfx]
    call    str_append
    mov     rdi, rax
    lea     rsi, [net_session_name]
    call    str_append
    mov     byte [rax], 0
    mov     byte [net_title_on], 1
    mov     rdi, [app_window]
    test    rdi, rdi
    jz      .out
    lea     rsi, [net_title_text]
    call    glfwSetWindowTitle
.out:
    add     rsp, 8
    ret

; title_reset(): the normal window title again (app.asm's update_title keeps it fresh from here on)
title_reset:
    sub     rsp, 8
    mov     byte [net_title_on], 0
    mov     rdi, [app_window]
    test    rdi, rdi
    jz      .out
    lea     rsi, [s_title_plain]
    call    glfwSetWindowTitle
.out:
    add     rsp, 8
    ret

; net_session_reset(): back to offline. The socket is closed (without a goodbye: net_leave and net_host_close
; say it first), every session flag and the peers are cleared, the window title is the normal one again.
; net_end_reason is left to the app (it reads it, then leaves the world)
net_session_reset:
    sub     rsp, 8
    call    ep_close_stale
    call    session_clear
    add     rsp, 8
    ret

; ep_close_stale(): the socket of a finished session, or of a join that failed (it stays open in NJ_FAILED for
; the join screen to read), is closed. Nothing when no socket is open
ep_close_stale:
    sub     rsp, 8
    cmp     byte [ep_open], 0
    je      .out
    lea     rdi, [net_ep]
    call    net_ep_close
    mov     byte [ep_open], 0
.out:
    add     rsp, 8
    ret

; session_clear(): every session flag, the peers and the window title back to offline; the socket is left alone
session_clear:
    sub     rsp, 8
    mov     byte [net_role], NET_ROLE_OFF
    mov     byte [net_self], 0
    mov     byte [net_pvp], 0
    mov     byte [net_applying], 0
    mov     byte [net_in_world], 0
    mov     byte [net_join_active], 0
    mov     byte [ready_sent], 0
    mov     byte [host_closing], 0
    mov     byte [save_acked], 0
    mov     byte [winfo_valid], 0
    mov     dword [net_hit_peer], 0
    mov     dword [net_rdist_cap], 0
    mov     dword [net_join_ready], 0
    mov     dword [net_image_valid], 0
    mov     dword [net_step_ctr], 0
    mov     dword [chat_count], 0
    mov     dword [chat_head], 0
    call    peers_clear
    call    title_reset
    add     rsp, 8
    ret

; ---- the guest: joining, leaving -------------------------------------------------------------

; join_error_text(edi err) -> rax the text of a join error (NJE_NOROOM names the code that was typed)
join_error_text:
    ENTER_N 1
    mov     ebx, edi
    lea     rax, [s_e_lost]
    cmp     ebx, JERR_LOST
    je      .out
    lea     rax, [s_e_noanswer]
    cmp     ebx, JERR_NOANSWER
    je      .out
    lea     rcx, [join_err_text]
    cmp     ebx, NJE_SOCKET
    jbe     .known
    xor     ebx, ebx                    ; anything else: a network error
.known:
    mov     rax, [rcx + rbx*8]
    cmp     ebx, NJE_NOROOM
    jne     .out
    lea     rdi, [join_text]
    lea     rsi, [s_e_noroom]
    call    str_append
    mov     rdi, rax
    lea     rsi, [net_join_target]
    call    str_append
    mov     byte [rax], 0
    lea     rax, [join_text]
.out:
    LEAVE_N 1
    ret

; join_fail(edi err) -> eax err: the join is over and failed. The line goes to stderr, the reason is kept for the
; join screen (net_join_status), the socket is closed; a --join run exits with code 3
join_fail:
    ENTER_N 2
    mov     ebx, edi
    mov     [join_err], ebx
    call    join_error_text
    mov     r12, rax
    call    log_start
    mov     rdi, rax
    lea     rsi, [s_join_failed]
    call    str_append
    mov     rdi, rax
    mov     rsi, r12
    call    str_append
    mov     rdi, rax
    call    log_flush
    call    session_clear               ; (the socket stays: its NJ_FAILED state is what the join screen reads)
    mov     byte [net_join_failed], 1
    cmp     qword [net_cli_join], 0
    je      .out
    mov     byte [net_join_exit], 1
.out:
    mov     eax, ebx
    LEAVE_N 2
    ret

; net_join_status() -> rax zstr: what the join screen says: why the last join failed, or how far the running one is
net_join_status:
    ENTER_N 1
    cmp     byte [net_join_failed], 0
    je      .not_failed
    mov     edi, [join_err]
    call    join_error_text
    jmp     .out
.not_failed:
    lea     rax, [s_empty]
    cmp     byte [net_join_active], 0
    je      .out
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .connecting
    lea     rax, [s_st_download]
    jmp     .out
.connecting:
    lea     rdi, [net_ep]
    call    net_ep_join_state
    lea     rcx, [s_st_rv]
    cmp     eax, NJ_RV
    je      .set
    lea     rcx, [s_st_punch]
    cmp     eax, NJ_PUNCH
    je      .set
    lea     rcx, [s_st_relay]
    cmp     eax, NJ_RELAY
    je      .set
    cmp     eax, NJ_CONNECT
    jne     .empty
    lea     rdi, [join_text]
    lea     rsi, [s_st_connect]
    call    str_append
    mov     rdi, rax
    lea     rsi, [net_join_target]
    call    str_append
    mov     rdi, rax
    lea     rsi, [s_st_dots]
    call    str_append
    mov     byte [rax], 0
    lea     rax, [join_text]
    jmp     .out
.set:
    mov     rax, rcx
    jmp     .out
.empty:
    lea     rax, [s_empty]
.out:
    LEAVE_N 1
    ret

; code_char_ok(eax c) -> eax 1 when c is one of the room code characters. Leaf
code_char_ok:
    lea     rdx, [code_alphabet]
    xor     ecx, ecx
.loop:
    cmp     al, [rdx + rcx]
    je      .yes
    inc     ecx
    cmp     ecx, CODE_ALPHABET_LEN
    jb      .loop
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; net_join_begin(rdi target zstr, rsi name zstr, edx force_relay) -> eax 0 started / NJE_* (it failed at once; the
; reason is in net_join_status). The target is a room code (6 characters of the code alphabet, any case) or,
; when it holds a '.', an address a.b.c.d[:port] (default port NET_PORT). The player's progress is followed by
; net_pump; NE_ACCEPTED makes this peer a guest.
; r12 = target text, r13 = name, r14d = force_relay, r15d = 1 for an address
net_join_begin:
    ENTER_N 5
    mov     r12, rdi
    mov     r13, rsi
    mov     r14d, edx
    cmp     byte [net_role], NET_ROLE_OFF
    jne     .net_err                    ; hosting or playing already
    cmp     byte [net_join_active], 0
    je      .fresh
    call    net_join_cancel
.fresh:
    call    ep_close_stale              ; (the leftover of an earlier failed join)
    cmp     r12, [net_cli_join]         ; the command line's own target keeps the --join (it exits with code 3 when
    je      .cli_own                    ; it fails); a join the player starts from the join screen is a new story
    mov     qword [net_cli_join], 0
.cli_own:
    mov     byte [net_join_failed], 0
    mov     byte [net_join_exit], 0
    mov     dword [join_err], 0
    mov     rdi, r13
    call    net_valid_name
    test    eax, eax
    jz      .bad_name
    lea     rdi, [net_session_name]
    mov     rsi, r13
    mov     edx, NAME_MAX
    call    str_copy
    mov     rsi, r12                    ; the typed target: no leading or trailing spaces
.lead:
    cmp     byte [rsi], ' '
    jne     .lead_done
    inc     rsi
    jmp     .lead
.lead_done:
    lea     rdi, [net_join_target]
    mov     edx, 63
    call    str_copy
.trail:
    lea     rcx, [net_join_target]
    cmp     rax, rcx
    jbe     .trail_done
    cmp     byte [rax - 1], ' '
    jne     .trail_done
    dec     rax
    mov     byte [rax], 0
    jmp     .trail
.trail_done:
    xor     r15d, r15d
    lea     rdi, [net_join_target]
.dot:
    mov     al, [rdi]
    test    al, al
    jz      .kind
    cmp     al, '.'
    jne     .dot_next
    mov     r15d, 1
    jmp     .kind
.dot_next:
    inc     rdi
    jmp     .dot
.kind:
    test    r15d, r15d
    jz      .code
    lea     rdi, [net_join_target]
    lea     rsi, [join_addr]
    mov     edx, NET_PORT
    call    net_parse_addr
    test    eax, eax
    jz      .unreach
    jmp     .open
.code:
    lea     rdi, [net_join_target]
    xor     ebx, ebx
.code_char:
    movzx   eax, byte [rdi + rbx]
    test    eax, eax
    jz      .code_end
    cmp     ebx, 6
    jae     .no_room                    ; a seventh character
    lea     edx, [rax - 'a']
    cmp     edx, 25
    ja      .upper_done
    sub     eax, 32
    mov     [rdi + rbx], al
.upper_done:
    call    code_char_ok
    test    eax, eax
    jz      .no_room
    inc     ebx
    lea     rdi, [net_join_target]
    jmp     .code_char
.code_end:
    cmp     ebx, 6
    jne     .no_room
    mov     rax, [net_join_target]
    mov     [join_code], rax
    mov     byte [join_code + 6], 0
.open:
    lea     rdi, [net_ep]
    xor     esi, esi
    mov     edx, 1
    call    net_ep_open
    test    eax, eax
    js      .socket
    mov     byte [ep_open], 1
    lea     rdi, [net_ep]
    lea     rsi, [join_addr]
    xor     edx, edx
    test    r15d, r15d
    jnz     .join_call
    lea     rsi, [net_cfg_server]
    lea     rdx, [join_code]
.join_call:
    lea     rcx, [net_session_name]
    mov     r8d, r14d
    call    net_ep_join
    mov     byte [net_join_active], 1
    mov     byte [ready_sent], 0
    mov     byte [host_closing], 0
    mov     byte [save_acked], 0
    mov     byte [winfo_valid], 0
    mov     dword [net_join_ready], 0
    mov     dword [net_image_valid], 0
    mov     dword [net_end_reason], 0
    call    title_set
    xor     eax, eax
    jmp     .out
.bad_name:
    mov     edi, NJE_DENY_NAME
    jmp     .fail
.no_room:
    mov     edi, NJE_NOROOM
    jmp     .fail
.unreach:
    mov     edi, NJE_UNREACHABLE
    jmp     .fail
.socket:
    mov     edi, NJE_SOCKET
    jmp     .fail
.net_err:                               ; a session runs already: refused, and that session left as it is
    mov     eax, NJE_SOCKET
    jmp     .out
.fail:
    call    join_fail
.out:
    LEAVE_N 5
    ret

; net_join_cancel(): the join in progress is abandoned (a guest that was accepted says goodbye). After the world
; is entered a guest leaves with net_leave instead.
net_join_cancel:
    ENTER_N 0
    cmp     byte [net_join_active], 0
    jne     .go
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .out
    cmp     byte [net_in_world], 0
    jne     .out
.go:
    mov     qword [net_cli_join], 0     ; a cancelled join ends the command line's --join too
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .close
    lea     rdi, [net_ep]
    xor     esi, esi
    xor     edx, edx
    call    net_ep_drop
.close:
    call    net_session_reset
    mov     byte [net_join_failed], 0
.out:
    LEAVE_N 0
    ret

; net_ready_out(): guest. The world is entered: the host hears READY and, in the same flush, a first state, so it
; can count this player at once
net_ready_out:
    ENTER_N 0
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .out
    xor     edi, edi
    mov     esi, MT_READY
    xor     edx, edx
    xor     ecx, ecx
    mov     r8d, 1
    call    net_send_to
    mov     byte [ready_sent], 1
    mov     byte [net_join_active], 0
    mov     qword [net_cli_join], 0     ; the join is complete: the command line's --join is over (until now a failure
                                        ; of it, even after the accept, closes the game with code 3)
    movzx   edi, byte [net_self]
    call    peer_ptr
    lea     rdi, [rax + PEER.ps]
    call    net_pstate_build
    call    state_send
.out:
    LEAVE_N 0
    ret

; net_player_save(): guest. The character goes to the host, which keeps it as <world>/players/<name>.hdr (a guest
; never writes files). Nothing before the world is entered: there is no character yet.
net_player_save:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    cmp     dword [app_in_world], 0
    je      .ret
    sub     rsp, 8
    lea     rdi, [world_header]
    call    game_player_save
    xor     edi, edi
    mov     esi, MT_PLAYER_SAVE
    lea     rdx, [world_header]
    mov     ecx, PLAYER_IMG_SIZE
    call    net_send_big_to
    add     rsp, 8
.ret:
    ret

; net_leave(): guest, a clean goodbye. Screen items go back, the character is sent and acknowledged (at most
; 3 s, behind a loading screen), the connection is dropped and the session ends. Blocks, pumping.
net_leave:
    ENTER_N 1
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .out
    call    inv_close_screen
    mov     byte [save_acked], 0
    cmp     dword [app_in_world], 0
    jne     .save
    mov     byte [save_acked], 1        ; (no character to send before the world is entered)
.save:
    call    net_player_save
    call    time_mono_ns
    mov     rbx, rax
.wait:
    cmp     byte [save_acked], 0
    jne     .bye
    cmp     dword [net_end_reason], 0
    jne     .bye
    call    glfwPollEvents
    call    net_pump
    call    net_flush
    cmp     byte [save_acked], 0
    jne     .bye
    call    time_mono_ns
    sub     rax, rbx
    mov     rcx, SAVE_WAIT_NS
    cmp     rax, rcx
    jae     .bye
    lea     rdi, [s_leaving]
    call    app_show_loading
    mov     edi, 2000
    call    usleep
    jmp     .wait
.bye:
    lea     rdi, [net_ep]
    xor     esi, esi
    xor     edx, edx
    call    net_ep_drop
    call    net_session_reset
.out:
    LEAVE_N 1
    ret

; host_gone(edi sys): the connection to the host ended (SYS_HOST_CLOSED or SYS_TIMEOUT): the app is told to leave
host_gone:
    sub     rsp, 8
    cmp     dword [net_end_reason], 0
    jne     .out
    mov     [net_end_reason], edi
    lea     rax, [s_host_closed_l]
    lea     rdx, [s_host_lost_l]
    cmp     edi, SYS_TIMEOUT
    cmove   rax, rdx
    mov     rdi, rax
    xor     esi, esi
    call    log_text
.out:
    add     rsp, 8
    ret

; ---- the pump -----------------------------------------------------------------------------------

; join_events(): the transport's events that are waiting are handled now, in order (see netsync_dispatch)
join_events:
    ENTER_N 0
.next:
    lea     rdi, [net_ep]
    lea     rsi, [ev_buf]
    call    net_ep_next_event
    test    eax, eax
    jz      .out
    lea     rdi, [ev_buf]
    call    on_event
    jmp     .next
.out:
    LEAVE_N 0
    ret

; net_join_timeout_check(): guest, from the pump. A guest that the host accepted but whose character (PLAYER_IMAGE
; or PLAYER_FRESH, which set net_join_ready) has not arrived 10 s later fails the join: a message that was lost must
; never leave the join screen on "Downloading world..." for good. It says goodbye (the host frees the slot at once),
; closes the socket, and the join fails with a status of its own ("The host did not answer"); a --join run exits.
net_join_timeout_check:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    cmp     byte [net_join_active], 0
    je      .ret
    cmp     dword [net_join_ready], 0
    jne     .ret
    cmp     byte [net_in_world], 0
    jne     .ret
    mov     rax, [net_pump_now]
    sub     rax, [net_join_accept_ns]
    mov     rcx, JOIN_WAIT_NS
    cmp     rax, rcx
    jle     .ret
    sub     rsp, 8
    lea     rdi, [net_ep]
    xor     esi, esi
    xor     edx, edx
    call    net_ep_drop
    call    ep_close_stale
    mov     edi, JERR_NOANSWER
    call    join_fail
    add     rsp, 8
.ret:
    ret

; net_wait_check(rdi t0) -> eax 1 when the multiplayer session is over, else 0. For the loading screens a guest waits
; behind (t0: the clock, in ns, when the wait began). Besides the session having ended (net_end_reason), a guest that
; has waited more than 60 s while nothing at all was heard from the host for 10 s has lost the host: the transport
; still hears its keepalives, but the messages the wait needs never come. The session then ends as if the transport
; had timed out (net_end_reason = SYS_TIMEOUT). Nothing but the reason is read offline and on a host.
net_wait_check:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .end
    cmp     dword [net_end_reason], 0
    jne     .end
    mov     rax, [net_pump_now]
    sub     rax, rdi
    mov     rcx, WAIT_LOST_NS
    cmp     rax, rcx
    jle     .end
    mov     rax, [net_pump_now]
    lea     rdx, [net_peer_rx]
    sub     rax, [rdx]                  ; slot 0: when the host last said anything (netsync_dispatch)
    mov     rcx, HOST_QUIET_NS
    cmp     rax, rcx
    jle     .end
    sub     rsp, 8
    mov     edi, SYS_TIMEOUT
    call    host_gone
    add     rsp, 8
.end:
    xor     eax, eax
    cmp     dword [net_end_reason], 0
    setne   al
    ret

; on_event(rdi NETEVENT*): one event of the transport
on_event:
    ENTER_N 1
    mov     rbx, rdi
    movzx   eax, byte [rbx + NETEVENT.kind]
    cmp     eax, NE_CONNECT_REQ
    je      .req
    cmp     eax, NE_ACCEPTED
    je      .accepted
    cmp     eax, NE_TIMEOUT
    je      .timeout
    cmp     eax, NE_DISCONNECTED
    jne     .out
    mov     esi, SYS_LEFT               ; a host sees a guest leave, a guest sees the host close
    mov     edx, SYS_HOST_CLOSED
    jmp     .gone
.timeout:
    mov     esi, SYS_TIMEOUT
    mov     edx, SYS_TIMEOUT
.gone:
    cmp     byte [net_role], NET_ROLE_HOST
    je      .peer
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .out
    mov     edi, edx
    call    host_gone
    jmp     .out
.peer:
    movzx   edi, byte [rbx + NETEVENT.slot]
    call    peer_gone
    jmp     .out
.req:
    mov     rdi, rbx
    call    host_on_connect
    jmp     .out
.accepted:
    cmp     byte [net_join_active], 0
    je      .out
    cmp     byte [net_role], NET_ROLE_OFF
    jne     .out
    movzx   eax, byte [rbx + NETEVENT.slot]
    lea     ecx, [rax - 1]
    cmp     ecx, NET_MAX_PEERS - 2
    ja      .out                        ; a guest slot is 1..7
    mov     [net_self], al
    mov     byte [net_role], NET_ROLE_GUEST
    mov     rax, [net_pump_now]         ; the join timeout counts from here
    mov     [net_join_accept_ns], rax
    mov     dword [net_step_ctr], 0
    mov     dword [chat_count], 0
    mov     dword [chat_head], 0
    call    peers_clear
    movzx   edi, byte [net_self]
    call    peer_ptr
    mov     rdi, rax
    lea     rsi, [net_session_name]
    mov     edx, PEER_READY
    call    peer_init
    call    log_start
    mov     rdi, rax
    lea     rsi, [s_joined_as]
    call    str_append
    mov     rdi, rax
    movzx   esi, byte [net_self]
    call    app_num
    mov     rdi, rax
    movzx   esi, byte [rbx + NETEVENT.relay]
    call    log_link
    mov     rdi, rax
    call    log_flush
.out:
    LEAVE_N 1
    ret

; pump_flows(): what the pump does each frame besides the transport. The host reports the rendezvous state on
; stderr (the room code, or that the server is unreachable); a joining guest follows the transport's verdict;
; a guest that was told the host is closing waits for its last save to be acknowledged, then ends the session.
; Frame: [rsp] the room code the transport reports (8)
pump_flows:
    ENTER_N 0, 16
    movzx   eax, byte [net_role]
    cmp     eax, NET_ROLE_HOST
    je      .host
    cmp     eax, NET_ROLE_GUEST
    je      .guest
    cmp     byte [net_join_active], 0
    je      .out
    lea     rdi, [net_ep]
    call    net_ep_join_state
    cmp     eax, NJ_FAILED
    jne     .out
    lea     rdi, [net_ep]
    call    net_ep_join_err
    mov     edi, eax
    call    join_fail
    jmp     .out
.host:
    lea     rdi, [net_ep]
    call    net_ep_rv_state
    cmp     eax, RVS_OK
    je      .rv_ok
    cmp     eax, RVS_FAIL
    jne     .out
    cmp     byte [rv_fail_logged], 0
    jne     .out
    mov     byte [rv_fail_logged], 1
    lea     rdi, [s_unreach]
    xor     esi, esi
    call    log_text
    jmp     .out
.rv_ok:
    mov     byte [rv_fail_logged], 0
    mov     qword [rsp], 0
    lea     rdi, [net_ep]
    mov     rsi, rsp
    call    net_ep_room_code
    mov     rax, [rsp]
    cmp     rax, [net_room_code]
    je      .out
    mov     [net_room_code], rax
    lea     rdi, [s_room]
    lea     rsi, [net_room_code]
    call    log_text
    jmp     .out
.guest:
    call    net_join_timeout_check
    cmp     byte [host_closing], 0
    je      .out
    cmp     dword [net_end_reason], 0
    jne     .out
    cmp     byte [save_acked], 0
    jne     .hc_end
    call    time_mono_ns
    sub     rax, [hc_t0]
    mov     rcx, HCLOSE_WAIT_NS
    cmp     rax, rcx
    jb      .out
.hc_end:
    mov     byte [host_closing], 0
    mov     edi, SYS_HOST_CLOSED
    call    host_gone
.out:
    LEAVE_N 0, 16
    ret

; net_pump(): once per frame, before update_state. The transport reads what arrived (every message goes through
; netsync_dispatch), its events are handled (a host accepts or denies, a peer is gone), the session flows run,
; and the other modules do their per-frame network work. Nothing happens offline unless a join is running.
net_pump:
    ENTER_N 0
    cmp     byte [net_role], NET_ROLE_OFF
    jne     .active
    cmp     byte [net_join_active], 0
    je      .out
.active:
    call    time_mono_ns
    mov     [net_pump_now], rax         ; this frame's clock (stamps of the guests heard from in this pump)
    lea     rdi, [net_ep]
    lea     rsi, [netsync_dispatch]
    call    net_ep_poll
.events:
    lea     rdi, [net_ep]
    lea     rsi, [ev_buf]
    call    net_ep_next_event
    test    eax, eax
    jz      .events_done
    lea     rdi, [ev_buf]
    call    on_event
    jmp     .events
.events_done:
    call    pump_flows
    cmp     byte [net_role], NET_ROLE_OFF
    je      .out                        ; (the join failed meanwhile)
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .world
    call    net_host_columns_serve
.world:
    call    net_cont_frame              ; every pump of a session, a guest's before its world too: they reset
    call    net_edits_replay            ; their per-session state while role is GUEST and net_in_world is 0
.out:
    LEAVE_N 0
    ret

; ---- handlers of the messages this module owns ------------------------------------------------
; Each is called by netsync_dispatch as handler(edi slot, esi type, rdx payload, ecx len) and checks the length
; and the role first: what arrives is another machine's word.

; MT_WORLDINFO (guest): the world's facts, kept until the character has arrived too
ns_on_worldinfo:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    cmp     ecx, WINFO_size
    jb      .ret
    cmp     byte [net_in_world], 0
    jne     .ret
    mov     rsi, rdx
    lea     rdi, [net_winfo]
    mov     ecx, WINFO_size
    rep     movsb
    mov     byte [winfo_valid], 1
.ret:
    ret

; MT_PEER_JOIN (guest): slot u8, name[17]. A new player of the world (it becomes ready with its first state)
ns_on_peer_join:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    cmp     ecx, 18
    jb      .ret
    movzx   eax, byte [rdx]
    cmp     eax, NET_MAX_PEERS
    jae     .ret
    ENTER_N 2
    mov     rbx, rdx
    mov     edi, eax
    call    peer_ptr
    mov     r12, rax
    cmp     dword [r12 + PEER.state], PEER_FREE
    jne     .out                        ; (known already: this peer's own record, or a repeat)
    mov     rdi, r12
    lea     rsi, [rbx + 1]
    mov     edx, PEER_JOINING
    call    peer_init
.out:
    LEAVE_N 2
.ret:
    ret

; MT_PEER_LEAVE (guest): slot u8, sys u8. A player is gone
ns_on_peer_leave:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    cmp     ecx, 2
    jb      .ret
    movzx   eax, byte [rdx]
    cmp     eax, NET_MAX_PEERS
    jae     .ret
    movzx   ecx, byte [rdx + 1]
    ENTER_N 2
    mov     ebx, eax
    mov     r12d, ecx
    movzx   edx, byte [net_self]
    cmp     ebx, edx
    je      .out
    mov     edi, ebx
    call    peer_ptr
    cmp     dword [rax + PEER.state], PEER_FREE
    je      .out
    lea     rsi, [s_t_left]
    lea     rdx, [s_t_lost]
    cmp     r12d, SYS_TIMEOUT
    cmove   rsi, rdx
    mov     edi, ebx
    call    chat_named
    mov     edi, ebx
    call    peer_ptr
    mov     rdi, rax
    mov     ecx, PEER_size
    xor     eax, eax
    rep     stosb
.out:
    LEAVE_N 2
.ret:
    ret

; MT_PLAYER_IMAGE (guest): the saved character. A wrong size or magic makes the join take a fresh one instead
; (the join must not hang)
ns_on_player_image:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    cmp     byte [winfo_valid], 0
    je      .ret
    cmp     byte [net_in_world], 0
    jne     .ret
    xor     eax, eax
    cmp     ecx, PLAYER_IMG_SIZE
    jne     .go
    mov     rax, [m_v6]
    cmp     [rdx], rax
    jne     .bad
    mov     rsi, rdx
    lea     rdi, [net_image]
    mov     ecx, PLAYER_IMG_SIZE
    rep     movsb
    mov     eax, 1
    jmp     .go
.bad:
    xor     eax, eax
.go:
    mov     [net_image_valid], eax
    mov     dword [net_join_ready], 1
.ret:
    ret

; MT_PLAYER_FRESH (guest): this world has no saved character of this name
ns_on_player_fresh:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    cmp     byte [winfo_valid], 0
    je      .ret
    cmp     byte [net_in_world], 0
    jne     .ret
    mov     dword [net_image_valid], 0
    mov     dword [net_join_ready], 1
.ret:
    ret

; MT_READY (host): the guest has entered the world
ns_on_ready:
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    lea     eax, [rdi - 1]
    cmp     eax, NET_MAX_PEERS - 2
    ja      .ret
    ENTER_N 1
    mov     ebx, edi
    call    peer_ptr
    cmp     dword [rax + PEER.state], PEER_JOINING
    jne     .out
    mov     byte [rax + PEER.pad0 + 1], 1
    mov     edi, ebx
    call    peer_try_ready
.out:
    LEAVE_N 1
.ret:
    ret

; MT_PLAYER_SAVE (host): a guest's character, PLAYER_IMG_SIZE bytes. Written whole (a zero-padded world header
; image) to <world>/players/<name>.hdr, then acknowledged
ns_on_player_save:
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    cmp     ecx, PLAYER_IMG_SIZE
    jne     .ret
    lea     eax, [rdi - 1]
    cmp     eax, NET_MAX_PEERS - 2
    ja      .ret
    mov     rax, [m_v6]
    cmp     [rdx], rax
    jne     .ret
    ENTER_N 3
    mov     ebx, edi
    mov     r12, rdx
    call    peer_ptr
    mov     r13, rax
    cmp     dword [r13 + PEER.state], PEER_FREE
    je      .out
    lea     rdi, [pl_buf]
    mov     ecx, WORLD_HDR_SIZE / 8
    xor     eax, eax
    rep     stosq
    lea     rdi, [pl_buf]
    mov     rsi, r12
    mov     ecx, PLAYER_IMG_SIZE
    rep     movsb
    lea     rdi, [r13 + PEER.name]
    call    players_path
    mov     rdi, rax
    lea     rsi, [pl_buf]
    mov     edx, WORLD_HDR_SIZE
    call    file_write_atomic
    mov     dword [r13 + PEER.saved], 1         ; (a close does not wait for a save that cannot be kept)
    test    eax, eax
    jnz     .out
    mov     edi, ebx
    mov     esi, MT_SAVE_ACK
    xor     edx, edx
    xor     ecx, ecx
    mov     r8d, 1
    call    net_send_to
.out:
    LEAVE_N 3
.ret:
    ret

; MT_HOST_CLOSING (guest): the host is closing the world. The character goes out one last time; the session
; ends (net_end_reason) when the host has acknowledged it, or after 2.5 s
ns_on_host_closing:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    cmp     byte [host_closing], 0
    jne     .ret
    ENTER_N 0
    mov     byte [host_closing], 1
    mov     byte [save_acked], 0
    call    time_mono_ns
    mov     [hc_t0], rax
    cmp     dword [app_in_world], 0
    jne     .save
    mov     byte [save_acked], 1
.save:
    call    net_player_save
    LEAVE_N 0
.ret:
    ret

; MT_SAVE_ACK (guest): the host has kept the character
ns_on_save_ack:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    mov     byte [save_acked], 1
.ret:
    ret

; MT_PSTATE (host): a guest's state. Stored (sanitized), the proxy's target follows; the first one places the
; proxy, and with READY it makes the guest a ready peer
ns_on_pstate:
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    cmp     ecx, PSTATE_size
    jb      .ret
    lea     eax, [rdi - 1]
    cmp     eax, NET_MAX_PEERS - 2
    ja      .ret
    ENTER_N 3
    mov     ebx, edi
    mov     r12, rdx
    call    peer_ptr
    mov     r13, rax
    cmp     dword [r13 + PEER.state], PEER_FREE
    je      .out
    lea     rdi, [r13 + PEER.ps]
    mov     rsi, r12
    mov     ecx, PSTATE_size
    rep     movsb
    mov     [r13 + PEER.ps + PSTATE.slot], bl
    lea     rdi, [r13 + PEER.ps]
    call    pstate_sanitize
    xor     esi, esi
    cmp     byte [r13 + PEER.pad0], 0
    sete    sil
    mov     rdi, r13
    call    proxy_target
    mov     byte [r13 + PEER.pad0], 1
    mov     edi, ebx
    call    peer_try_ready
.out:
    LEAVE_N 3
.ret:
    ret

; MT_PLAYERS (guest): count u8, pad[3], PSTATE x count. The other players' states; the first record of a peer
; makes it ready and places its proxy
ns_on_players:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    cmp     ecx, 4
    jb      .ret
    movzx   eax, byte [rdx]
    cmp     eax, NET_MAX_PEERS - 1
    ja      .ret
    imul    r8d, eax, PSTATE_size
    add     r8d, 4
    cmp     ecx, r8d
    jb      .ret
    ENTER_N 5
    mov     r12d, eax
    lea     r13, [rdx + 4]
    xor     ebx, ebx
.rec:
    cmp     ebx, r12d
    jae     .out
    movzx   eax, byte [r13]
    cmp     eax, NET_MAX_PEERS
    jae     .next
    movzx   ecx, byte [net_self]
    cmp     eax, ecx
    je      .next
    mov     r14d, eax
    mov     edi, eax
    call    peer_ptr
    mov     r15, rax
    cmp     dword [r15 + PEER.state], PEER_FREE
    je      .next                       ; (its PEER_JOIN has not arrived yet: the next states will do)
    lea     rdi, [r15 + PEER.ps]
    mov     rsi, r13
    mov     ecx, PSTATE_size
    rep     movsb
    mov     [r15 + PEER.ps + PSTATE.slot], r14b
    lea     rdi, [r15 + PEER.ps]
    call    pstate_sanitize
    xor     esi, esi
    cmp     dword [r15 + PEER.state], PEER_READY
    setne   sil
    mov     rdi, r15
    call    proxy_target
    mov     dword [r15 + PEER.state], PEER_READY
.next:
    add     r13, PSTATE_size
    inc     ebx
    jmp     .rec
.out:
    LEAVE_N 5
.ret:
    ret

; MT_CHAT (both): slot u8, text[33]. A guest's line reaches the host, which says it for him (its own slot overrides
; whatever the message claims); the host's relay reaches the guests with the speaker's slot
ns_on_chat:
    cmp     ecx, 2
    jb      .ret
    ENTER_N 3, 48
    mov     ebx, edi
    mov     r12, rdx
    lea     edx, [rcx - 1]
    lea     rdi, [rsp]
    lea     rsi, [r12 + 1]
    call    chat_clean
    cmp     byte [net_role], NET_ROLE_HOST
    je      .from_guest
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .out
    movzx   edi, byte [r12]
    lea     rsi, [rsp]
    call    chat_player_line
    jmp     .out
.from_guest:
    lea     eax, [rbx - 1]
    cmp     eax, NET_MAX_PEERS - 2
    ja      .out
    mov     edi, ebx
    call    peer_ptr
    cmp     dword [rax + PEER.state], PEER_READY
    jne     .out
    mov     edi, ebx
    lea     rsi, [rsp]
    call    chat_say
.out:
    LEAVE_N 3, 48
.ret:
    ret

; MT_SYS (guest): code u8, slot u8, arg u8, pad u8: a line for the chat
ns_on_sys:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    cmp     ecx, 4
    jb      .ret
    movzx   esi, byte [rdx + 1]
    movzx   eax, byte [rdx]
    movzx   ecx, byte [rdx + 2]
    cmp     eax, SYS_JOINED
    je      .joined
    cmp     eax, SYS_DIED
    je      .died
    cmp     eax, SYS_PVP
    jne     .ret
    lea     rdi, [s_pvp_off]
    lea     rax, [s_pvp_on]
    test    ecx, ecx
    cmovnz  rdi, rax
    jmp     chat_add
.joined:
    mov     edi, esi
    lea     rsi, [s_t_joined]
    jmp     chat_named
.died:
    mov     edi, esi
    mov     esi, ecx
    jmp     chat_death_line
.ret:
    ret

; MT_PVP (guest): on u8
ns_on_pvp:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    cmp     ecx, 1
    jb      .ret
    movzx   eax, byte [rdx]
    and     eax, 1
    mov     [net_pvp], al
    mov     [net_winfo + WINFO.pvp], al ; (a PVP that arrives while the world downloads: game_join reads it from here)
.ret:
    ret

; MT_DIED (host): cause u8. A guest died: its death is told to everyone
ns_on_died:
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    cmp     ecx, 1
    jb      .ret
    lea     eax, [rdi - 1]
    cmp     eax, NET_MAX_PEERS - 2
    ja      .ret
    imul    eax, edi, PEER_size
    lea     r8, [net_peers]
    cmp     dword [r8 + rax + PEER.state], PEER_FREE
    je      .ret
    movzx   esi, byte [rdx]
    jmp     announce_death
.ret:
    ret
