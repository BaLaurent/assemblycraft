; app.asm - application state machine: main loop (the world streams around the player or the title's
; camera every frame), screen dispatch, world open/create/quit/respawn behind loading screens,
; autosave, window title.
%include "common.inc"
%include "gl.inc"
default rel

global app_state, app_entered, app_settings_parent, app_selected, app_in_world
global app_fps, app_show_debug, app_window, app_message, app_message_timer
global app_run, app_goto, app_play_world, app_create_world, app_quit_to_title
global app_respawn, app_request_quit, app_wait_area
global app_title_msg, app_join_world, app_leave_world, app_world_path, app_show_loading, app_wait_net

extern sys_print, str_append, str_copy, i32_to_str, floor_i
extern input_poll, input_set_captured, input_captured, frame_input, ui_input
extern game_new, game_load, game_save, game_frame, game_respawn, game_mode, game_time
extern game_on_area_ready
extern game_open_screen, game_open_cont, game_has_target, game_break_progress
extern settings, settings_apply, settings_save, settings_path
extern saves_scan, saves_entry_path, saves_new_world_dir, world_list
extern render_world, render_update_chunks, ui_begin, ui_focus, hud_draw, hud_dt
extern screen_title, screen_worlds, screen_create, screen_rename, screen_delete
extern screen_settings, screen_controls, screen_pause, screen_inventory
extern screen_crafting, screen_death, screen_loading, screen_furnace, screen_chest
extern audio_update, player, body_init, world_origin_x, world_origin_z, world_header
extern mobs_clear, inv, inv_sel, inv_close_screen, craft_size, surv, item_names
extern inv_container, hand_render, drops_clear, arrows_clear, tnt_clear
extern fire_clear, fx_clear, game_aim, game_heavy_s
extern screen_trade, screen_dialog, screen_skills, screen_character
extern screen_shrine, screen_leader, screen_event
extern debug_poll, debug_frame
extern rpg_begin, rpg_reset, combat_reset, dmgnum_clear, light_update
extern boats_clear
extern stream_begin, stream_end, stream_update, stream_area_ready, gen_find_spawn
extern dir_remove_tree
extern screen_mp_join, screen_mp_host, screen_chat
extern net_pump, net_flush, net_role, net_end_reason, net_join_ready, net_join_exit
extern net_host_open, net_host_close, net_set_pvp, net_leave, net_join_begin, net_join_cancel
extern net_ready_out, net_session_reset, net_player_save, net_died_out
extern net_title_on, net_title_text, net_cfg_name, net_cfg_port, net_winfo, net_image, net_image_valid
extern net_cli_host, net_cli_join, net_cli_relay, net_cli_pvp, net_join_failed, game_join
extern net_wait_check, time_mono_ns

section .rodata
s_loading:    db "Loading world", 0
s_generating: db "Generating terrain", 0
s_pano:       db "Generating", 0
s_respawning: db "Respawning", 0
s_pct:        db "%", 0
s_saving:     db "Saving world...", 0
s_cant_load:  db "Could not load '", 0
s_quote:      db "'", 0
s_too_many:   db "Too many worlds named like that", 0
s_cant_save:  db "Could not save the new world", 0
s_save_fail:  db "assemblycraft: failed to save world to ", 0
s_nl:         db 10, 0
s_title:      db "AssemblyCraft", 0
s_title_fps:  db "AssemblyCraft | ", 0
s_fps:        db " FPS | ", 0
s_space:      db " ", 0
s_sep:        db " | ", 0
s_empty:      db "Empty", 0
s_fly:        db " | fly", 0
s_joining:    db "Joining world", 0
s_leaving:    db "Leaving...", 0
s_msg_closed: db "The host closed the world", 0
s_msg_lost:   db "Lost connection to the host", 0
s_msg_nohost: db "net: cannot open multiplayer (error ", 0
s_msg_nohost2: db ")", 10, 0
align 4
f_half_w:     dd 0.3
f_height:     dd 1.8
f_speed:      dd 4.317
f_pano_rate:  dd 3.0
f_360:        dd 360.0
f_autosave:   dd 120.0
f_autosave_guest: dd 60.0              ; a guest's character goes to the host this often
f_msg_time:   dd 5.0
f_half:       dd 0.5
f_wait_budget: dd 0.030                ; seconds of streaming per frame behind a loading screen
f_stream_budget: dd 0.004              ; ... and while the world is on screen
f_mesh_budget: dd 0.006
align 8
d_max_dt:     dq 0.25
d_title_every: dq 0.5
; screen per state (0 = none)
screens:
    dq screen_title, screen_worlds, screen_create, screen_rename, screen_delete
    dq screen_settings, screen_controls, 0, screen_pause, screen_inventory
    dq screen_crafting, screen_death, 0, screen_furnace, screen_chest
    dq screen_trade, screen_dialog, screen_skills, screen_character
    dq screen_shrine, screen_leader, debug_frame, screen_mp_join, screen_mp_host, screen_chat, screen_event

section .data
align 4
app_state:           dd ST_TITLE
app_entered:         dd 1
app_settings_parent: dd ST_TITLE
app_selected:        dd -1
app_message_timer:   dd 0.0

section .bss
alignb 8
app_window:     resq 1
app_title_msg:  resq 1                  ; zstr drawn in red on the title screen (why a session ended), 0 none
last_time:      resq 1
title_time:     resq 1
app_in_world:   resd 1
app_fps:        resd 1
app_show_debug: resd 1
was_focused:    resd 1
frames:         resd 1
exit_code:      resd 1
fb_w:           resd 1
fb_h:           resd 1
autosave_timer: resd 1
frame_dt:       resd 1
alignb 16
panorama_cam:   resb BODY_size
app_message:    resb 128
app_world_path: resb 4096               ; the directory of the world that is open
title_buf:      resb 256
wait_text:      resb 160               ; "<text> N%" of the loading screen
pano_spawn:     resd 4                 ; the panorama world's spawn cell (absolute x, y, z)
alignb 8
app_wait_t0:    resq 1                 ; the clock (ns) when the loading wait in progress began

section .text

; app_goto(edi state): switch state; the cursor is captured only while PLAYING
app_goto:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
    cmp     ebx, [app_state]
    je      .same
    mov     dword [app_entered], 1
    mov     qword [ui_focus], 0
    cmp     ebx, ST_MP_JOIN
    je      .same
    mov     byte [net_join_failed], 0   ; a failed join's reason belongs to the join screen
.same:
    mov     [app_state], ebx
    xor     esi, esi
    cmp     ebx, ST_PLAYING
    sete    sil
    je      .captured
    mov     dword [game_heavy_s], __float32__(-1.0) ; any screen or pause drops a heavy charge
.captured:
    cmp     esi, [input_captured]
    je      .ret
    mov     rdi, [app_window]
    call    input_set_captured
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; app_request_quit(): close the window; the loop exits (saving if in a world)
app_request_quit:
    mov     rdi, [app_window]
    mov     esi, 1
    jmp     glfwSetWindowShouldClose

; set_message(rdi a, rsi b or 0, rdx c or 0): app_message = a b c, shown for 5 s
set_message:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     rbx, rsi
    mov     r12, rdx
    mov     rsi, rdi
    lea     rdi, [app_message]
    mov     edx, 127
    call    str_copy
    test    rbx, rbx
    jz      .done
    mov     rdi, rax
    lea     rdx, [app_message + 127]
    sub     rdx, rax
    mov     rsi, rbx
    call    str_copy
    test    r12, r12
    jz      .done
    mov     rdi, rax
    lea     rdx, [app_message + 127]
    sub     rdx, rax
    mov     rsi, r12
    call    str_copy
.done:
    movss   xmm0, [f_msg_time]
    movss   [app_message_timer], xmm0
    pop     r12
    pop     rbx
    pop     rbp
    ret

; save_world() -> eax 0 ok / 1 failed (message printed on stderr)
save_world:
    push    rbp
    mov     rbp, rsp
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .own
    call    net_player_save             ; a guest's character is kept by the host; it never writes files
    xor     eax, eax
    jmp     .ok
.own:
    lea     rdi, [app_world_path]
    call    game_save
    test    eax, eax
    jz      .ok
    mov     edi, 2
    lea     rsi, [s_save_fail]
    call    sys_print
    mov     edi, 2
    lea     rsi, [app_world_path]
    call    sys_print
    mov     edi, 2
    lea     rsi, [s_nl]
    call    sys_print
    mov     eax, 1
    pop     rbp
    ret
.ok:
    mov     dword [autosave_timer], 0
    pop     rbp
    ret

; app_show_loading(rdi text): draw one frame with the loading screen
app_show_loading:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdi
    mov     rdi, [app_window]
    lea     rsi, [fb_w]
    lea     rdx, [fb_h]
    call    glfwGetFramebufferSize
    cmp     dword [fb_w], 0
    jle     .ret
    cmp     dword [fb_h], 0
    jle     .ret
    xor     edi, edi
    xor     esi, esi
    mov     edx, [fb_w]
    mov     ecx, [fb_h]
    call    glViewport
    mov     edi, GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT
    call    glClear
    mov     edi, [fb_w]
    mov     esi, [fb_h]
    call    ui_begin
    mov     rdi, rbx
    call    screen_loading
    mov     rdi, [app_window]
    call    glfwSwapBuffers
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; wait_percent(edi x, esi z) -> eax 0..100: 4 for each of the 5 x 5 columns around the block (x, z)
; that are lit and meshed
wait_percent:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r12d, edi
    mov     r13d, esi
    xor     ebx, ebx
    mov     r14d, -2                    ; column row
.row:
    mov     r15d, -2                    ; column
.col:
    mov     eax, r15d
    shl     eax, 4
    lea     edi, [r12 + rax]
    mov     eax, r14d
    shl     eax, 4
    lea     esi, [r13 + rax]
    xor     edx, edx
    call    stream_area_ready
    add     ebx, eax
    inc     r15d
    cmp     r15d, 2
    jle     .col
    inc     r14d
    cmp     r14d, 2
    jle     .row
    lea     eax, [rbx * 4]
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; show_wait(rdi text, esi percent): one loading frame saying "<text> N%"
show_wait:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, esi
    mov     rsi, rdi
    lea     rdi, [wait_text]
    mov     edx, 120
    call    str_copy
    mov     byte [rax], ' '
    lea     rsi, [rax + 1]
    mov     edi, ebx
    call    i32_to_str
    mov     rdi, rax
    lea     rsi, [s_pct]
    call    str_append
    mov     byte [rax], 0
    lea     rdi, [wait_text]
    call    app_show_loading
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; app_wait_net() -> eax 1 when the multiplayer session is over (a guest whose host went away or fell silent: the
; columns it waits for will never come), else 0. Pumps the network first: behind a loading screen that is what
; tells it. app_wait_t0 is when the wait began (net_wait_check ends the session of a guest that waited a minute
; and lost the host).
app_wait_net:
    sub     rsp, 8
    call    net_pump
    mov     rdi, [app_wait_t0]
    call    net_wait_check
    add     rsp, 8
    ret

; app_wait_area(rdi text, rsi BODY* centre) -> eax 0 ready / 1 the window was closed or the session ended
; Streams the world around the centre behind a loading screen ("<text> N%") until the 5 x 5 columns
; around it are lit and meshed. With the player as the centre, game_on_area_ready then settles a new
; world or a respawn (stands the player on the ground, populates, finds the bed); when that moves the
; player to another area (a vanished bed), wait again.
app_wait_area:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi                    ; text
    mov     r12, rsi                    ; centre
    xor     esi, esi
    call    show_wait
    call    time_mono_ns
    mov     [app_wait_t0], rax          ; (a guest that waits too long without hearing the host has lost it)
.loop:
    call    glfwPollEvents
    mov     rdi, [app_window]
    call    glfwWindowShouldClose
    test    eax, eax
    jnz     .closed
    call    app_wait_net                ; the network goes on behind a loading screen, and says when the host is gone
    test    eax, eax
    jnz     .closed                     ; (only a guest's session ends that way) the callers return and the main loop
                                        ; leaves the world
    movss   xmm0, [r12 + BODY.x]
    call    floor_i
    mov     r13d, eax
    movss   xmm0, [r12 + BODY.z]
    call    floor_i
    mov     r14d, eax
    mov     edi, r13d
    mov     esi, r14d
    movss   xmm0, [f_wait_budget]
    call    stream_update
    call    light_update
    movss   xmm0, [f_wait_budget]
    call    render_update_chunks
    mov     edi, r13d
    mov     esi, r14d
    mov     edx, 2
    call    stream_area_ready
    test    eax, eax
    jnz     .ready
    mov     edi, r13d
    mov     esi, r14d
    call    wait_percent
    mov     esi, eax
    mov     rdi, rbx
    call    show_wait
    call    net_flush
    jmp     .loop
.ready:
    lea     rax, [player]
    cmp     r12, rax
    jne     .done
    call    game_on_area_ready
    test    eax, eax
    jnz     .loop                       ; the player moved on to another area: wait for it too
.done:
    xor     eax, eax
    jmp     .ret
.closed:
    mov     eax, 1
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; enter_world(): start playing the loaded/created world; the character gets the common kit once and,
; while it has no skill, a banner that points at the grimoire (rpg_begin)
enter_world:
    push    rbp
    mov     rbp, rsp
    mov     dword [app_in_world], 1
    mov     dword [autosave_timer], 0
    call    rpg_begin
    mov     edi, ST_PLAYING
    call    app_goto
    pop     rbp
    ret

; app_play_world(edi idx): only a valid 0.9 world (entry.valid 1) opens
app_play_world:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi
    mov     eax, ebx
    shl     eax, 7                      ; * WORLDENTRY_size
    lea     r12, [world_list + rax]
    cmp     dword [r12 + WORLDENTRY.valid], 1
    jne     .cant
    lea     rdi, [s_loading]
    xor     esi, esi
    call    show_wait
    mov     edi, ebx
    lea     rsi, [app_world_path]
    call    saves_entry_path
    lea     rdi, [app_world_path]
    call    game_load
    test    eax, eax
    jz      .loaded
.cant:
    lea     rdi, [s_cant_load]
    lea     rsi, [r12 + WORLDENTRY.name]
    lea     rdx, [s_quote]
    call    set_message
    mov     edi, ST_WORLDS
    call    app_goto
    jmp     .ret
.loaded:
    lea     rdi, [s_loading]
    lea     rsi, [player]
    call    app_wait_area
    test    eax, eax
    jnz     .ret                        ; the window was closed: the main loop leaves
    call    enter_world
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; app_create_world(rdi name, esi mode, edx seed)
; A new directory world: header and spawn first, then the terrain around the spawn is generated behind
; the loading screen, then everything is saved once (the player stands on the surface by then).
app_create_world:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    lea     rdi, [s_generating]
    xor     esi, esi
    call    show_wait
    mov     rdi, rbx
    lea     rsi, [app_world_path]
    call    saves_new_world_dir
    test    eax, eax
    jz      .path_ok
    lea     rdi, [s_too_many]
    cmp     eax, -1
    je      .fail
    lea     rdi, [s_cant_save]
    jmp     .fail
.path_ok:
    mov     edi, r13d
    mov     esi, r12d
    mov     rdx, rbx
    lea     rcx, [app_world_path]
    call    game_new
    lea     rdi, [s_generating]
    lea     rsi, [player]
    call    app_wait_area
    test    eax, eax
    jnz     .abandon                    ; the window was closed: leave no empty world behind
    lea     rdi, [app_world_path]
    call    game_save
    test    eax, eax
    jz      .saved
    lea     rdi, [app_world_path]       ; could not save: the half-made world goes, the title world returns
    call    dir_remove_tree
    call    load_panorama
    lea     rdi, [s_cant_save]
.fail:
    xor     esi, esi
    xor     edx, edx
    call    set_message
    call    saves_scan
    mov     edi, ST_WORLDS
    call    app_goto
    jmp     .ret
.abandon:
    lea     rdi, [app_world_path]
    call    dir_remove_tree
    jmp     .ret
.saved:
    call    enter_world
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; load_panorama(): the title-screen world (a streamed world of its own seed) and its camera, then
; the area around the camera is generated behind a loading screen
load_panorama:
    push    rbp
    mov     rbp, rsp
    mov     edi, PANORAMA_SEED
    xor     esi, esi                    ; no directory: the panorama is never saved
    call    stream_begin
    lea     rdi, [pano_spawn]
    call    gen_find_spawn
    mov     eax, [pano_spawn]
    and     eax, -REBASE_STEP
    mov     [world_origin_x], eax
    mov     eax, [pano_spawn + 8]
    and     eax, -REBASE_STEP
    mov     [world_origin_z], eax
    call    mobs_clear
    call    drops_clear
    call    arrows_clear
    call    tnt_clear
    call    fire_clear
    call    fx_clear
    call    dmgnum_clear
    call    boats_clear
    call    rpg_reset
    call    combat_reset
    mov     dword [game_aim], 0
    mov     dword [game_time], NEW_WORLD_TIME
    mov     dword [game_has_target], 0
    mov     dword [game_break_progress], 0
    lea     rdi, [panorama_cam]
    movss   xmm0, [f_half_w]
    movss   xmm1, [f_height]
    movss   xmm2, [f_speed]
    call    body_init
    mov     eax, [pano_spawn]
    sub     eax, [world_origin_x]
    cvtsi2ss xmm0, eax
    addss   xmm0, [f_half]
    movss   [panorama_cam + BODY.x], xmm0
    mov     eax, [pano_spawn + 4]
    add     eax, 12                     ; the camera hovers above the spawn
    cvtsi2ss xmm0, eax
    movss   [panorama_cam + BODY.y], xmm0
    mov     eax, [pano_spawn + 8]
    sub     eax, [world_origin_z]
    cvtsi2ss xmm0, eax
    addss   xmm0, [f_half]
    movss   [panorama_cam + BODY.z], xmm0
    mov     dword [panorama_cam + BODY.pitch], __float32__(20.0)
    lea     rdi, [s_pano]
    lea     rsi, [panorama_cam]
    call    app_wait_area
    pop     rbp
    ret

; app_quit_to_title(): return screen items, save, leave the world, back to the title screen
app_quit_to_title:
    push    rbp
    mov     rbp, rsp
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .not_guest
    call    net_leave                   ; a guest's character goes to the host first, then the world is left
    xor     edi, edi
    call    app_leave_world
    pop     rbp
    ret
.not_guest:
    lea     rdi, [s_saving]
    call    app_show_loading
    call    inv_close_screen            ; cursor and grid items go back before the save
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .save
    call    net_host_close              ; the guests are told and their characters are kept
.save:
    call    save_world
    mov     edi, 1
    call    stream_end                  ; the modified columns are written, every column unloads
    mov     dword [app_in_world], 0
    call    load_panorama
    call    saves_scan
    mov     edi, ST_TITLE
    call    app_goto
    pop     rbp
    ret

; app_respawn(edi to_title): back at the bed or the world spawn; the terrain around is waited for
; ("Respawning"), then the game goes on (or the world is left for the title screen)
app_respawn:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
    call    game_respawn
    lea     rdi, [s_respawning]
    lea     rsi, [player]
    call    app_wait_area
    test    eax, eax
    jnz     .ret                        ; the window was closed: the main loop leaves
    test    ebx, ebx
    jz      .play
    call    app_quit_to_title
    jmp     .ret
.play:
    mov     edi, ST_PLAYING
    call    app_goto
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; app_join_world(): a guest's character has arrived (net_join_ready). The world is built from WORLDINFO and the
; character (game_join), its area is waited for behind a loading screen, then the world is entered and the host
; hears READY
app_join_world:
    push    rbp
    mov     rbp, rsp
    mov     dword [net_join_ready], 0
    lea     rdi, [s_joining]
    xor     esi, esi
    call    show_wait
    lea     rdi, [net_winfo]
    lea     rsi, [net_image]
    cmp     dword [net_image_valid], 0
    jne     .image
    xor     esi, esi                    ; no saved character: a fresh one
.image:
    call    game_join
    lea     rdi, [s_joining]
    lea     rsi, [player]
    call    app_wait_area
    test    eax, eax
    jnz     .ret                        ; the window was closed: the main loop leaves
    cmp     dword [net_end_reason], 0
    jne     .ret                        ; the host went away meanwhile: the main loop leaves
    call    enter_world
    call    net_ready_out
.ret:
    pop     rbp
    ret

; app_leave_world(edi sys_code): a multiplayer session ends and the world with it: screen items go back, the
; world unloads without saving (a guest keeps nothing; the host's world is left by app_quit_to_title), the
; connection's remains are closed, the panorama returns and the title screen says why (SYS_HOST_CLOSED,
; SYS_TIMEOUT; 0 for a leave the player chose)
app_leave_world:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
    mov     dword [net_end_reason], 0
    lea     rdi, [s_leaving]
    call    app_show_loading
    call    inv_close_screen
    xor     edi, edi
    call    stream_end                  ; nothing is saved
    mov     dword [app_in_world], 0
    call    net_session_reset           ; the socket, the role, the render cap, the peers, the window title
    lea     rax, [s_msg_closed]
    cmp     ebx, SYS_HOST_CLOSED
    je      .msg
    lea     rax, [s_msg_lost]
    cmp     ebx, SYS_TIMEOUT
    je      .msg
    xor     eax, eax
.msg:
    mov     [app_title_msg], rax
    call    load_panorama
    call    saves_scan
    mov     edi, ST_TITLE
    call    app_goto
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; cli_host(): --host. The world that was just entered is opened to others (the port of --port or the
; configuration), PvP on with --pvp
cli_host:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     edi, [net_cfg_port]
    call    net_host_open
    test    eax, eax
    jns     .opened
    neg     eax
    mov     ebx, eax
    lea     rdi, [wait_text]
    lea     rsi, [s_msg_nohost]
    call    str_append
    mov     rsi, rax
    mov     edi, ebx
    call    i32_to_str
    mov     rdi, rax
    lea     rsi, [s_msg_nohost2]
    call    str_append
    mov     byte [rax], 0
    mov     edi, 2
    lea     rsi, [wait_text]
    call    sys_print
    jmp     .ret
.opened:
    movzx   edi, byte [net_cli_pvp]
    call    net_set_pvp
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; update_title(): window title with FPS, position, held item and fly state
update_title:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    cmp     byte [net_title_on], 0      ; in a multiplayer session the title is "AssemblyCraft - <name>"
    je      .normal
    mov     rdi, [app_window]
    lea     rsi, [net_title_text]
    call    glfwSetWindowTitle
    jmp     .ret
.normal:
    cmp     dword [app_in_world], 0
    jne     .world
    mov     rdi, [app_window]
    lea     rsi, [s_title]
    call    glfwSetWindowTitle
    jmp     .ret
.world:
    lea     rdi, [title_buf]
    lea     rsi, [s_title_fps]
    call    str_append
    mov     edi, [app_fps]
    mov     rsi, rax
    call    i32_to_str
    mov     rdi, rax
    lea     rsi, [s_fps]
    call    str_append
    mov     rbx, rax
%macro TITLE_COORD 3                    ; field, origin symbol or none, separator
    movss   xmm0, [player + BODY.%1]
    call    floor_i
%ifnidn %2, none
    add     eax, [%2]                   ; absolute: the local cell plus the origin
%endif
    mov     edi, eax
    mov     rsi, rbx
    call    i32_to_str
    mov     rdi, rax
    lea     rsi, [%3]
    call    str_append
    mov     rbx, rax
%endmacro
    TITLE_COORD x, world_origin_x, s_space
    TITLE_COORD y, none, s_space
    TITLE_COORD z, world_origin_z, s_sep
    mov     eax, [inv_sel]
    lea     rcx, [inv + INVENTORY.slots + rax*4]
    lea     rsi, [s_empty]
    movzx   eax, byte [rcx + ITEMSTACK.id]
    cmp     byte [rcx + ITEMSTACK.count], 0
    je      .name
    test    eax, eax
    jz      .name
    mov     rsi, [item_names + rax*8]
.name:
    mov     rdi, rbx
    call    str_append
    cmp     dword [player + BODY.flying], 0
    je      .no_fly
    mov     rdi, rax
    lea     rsi, [s_fly]
    call    str_append
.no_fly:
    mov     byte [rax], 0
    mov     rdi, [app_window]
    lea     rsi, [title_buf]
    call    glfwSetWindowTitle
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; tick_autosave(): every 120 s of in-world play time
tick_autosave:
    movss   xmm0, [autosave_timer]
    addss   xmm0, [frame_dt]
    movss   [autosave_timer], xmm0
    movss   xmm1, [f_autosave]
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .limit
    movss   xmm1, [f_autosave_guest]    ; a guest's character goes to the host every minute
.limit:
    comiss  xmm0, xmm1
    jb      .ret
    jmp     save_world
.ret:
    ret

; to_death(): the player died; save and show the death screen
to_death:
    push    rbp
    mov     rbp, rsp
    mov     edi, ST_DEATH
    call    app_goto
    call    save_world
    cmp     byte [net_role], NET_ROLE_OFF
    je      .out
    mov     edi, [surv + SURVIVAL.death_cause]
    call    net_died_out                ; the others read how he died
.out:
    pop     rbp
    ret

; update_state(): per-state simulation and transitions for this frame
update_state:
    push    rbp
    mov     rbp, rsp
    cmp     dword [app_in_world], 0
    je      .menus
    cmp     dword [frame_input + FRAMEINPUT.debug], 0
    je      .no_debug
    xor     dword [app_show_debug], 1
.no_debug:
    mov     eax, [app_state]
    cmp     eax, ST_PLAYING
    je      .playing
    cmp     eax, ST_INVENTORY
    je      .screen
    cmp     eax, ST_CRAFTING
    je      .screen
    cmp     eax, ST_FURNACE
    je      .screen
    cmp     eax, ST_CHEST
    je      .screen
    cmp     eax, ST_TRADE
    je      .screen
    cmp     eax, ST_DIALOG
    je      .screen
    cmp     eax, ST_SKILLS
    je      .screen
    cmp     eax, ST_CHARACTER
    je      .screen
    cmp     eax, ST_SHRINE
    je      .screen
    cmp     eax, ST_LEADER
    je      .screen
    cmp     eax, ST_EVENT
    je      .screen
    cmp     eax, ST_CHAT
    je      .screen                     ; the chat line: the world keeps running
    cmp     byte [net_role], NET_ROLE_OFF
    je      .ret                        ; paused, death, settings, the debug menu: offline, nothing simulates
    movss   xmm0, [frame_dt]            ; ... in a multiplayer world nothing freezes: the others play on
    call    game_frame
    jmp     .ret

.playing:
    call    debug_poll                  ; the F12 detector: three presses open the debug menu
    test    eax, eax
    jz      .no_debug_menu
    mov     edi, ST_DEBUG
    call    app_goto                    ; paused like the pause menu, the cursor released
    call    save_world                  ; the cheater mark is on disk at once
    jmp     .ret
.no_debug_menu:
    mov     rdi, [app_window]           ; pause when focus is lost (not before it arrives)
    mov     esi, GLFW_FOCUSED
    call    glfwGetWindowAttrib
    mov     ecx, [was_focused]
    mov     [was_focused], eax
    test    eax, eax
    jnz     .focused
    test    ecx, ecx
    jnz     .pause
.focused:
    cmp     dword [ui_input + UIINPUT.escape], 0
    je      .no_pause
.pause:
    mov     edi, ST_PAUSED
    call    app_goto
    call    save_world
    jmp     .ret
.no_pause:
    cmp     dword [frame_input + FRAMEINPUT.skills], 0
    je      .no_skills
    mov     edi, ST_SKILLS
    call    app_goto
    jmp     .ret
.no_skills:
    cmp     dword [frame_input + FRAMEINPUT.inventory], 0
    je      .no_inventory
    mov     dword [craft_size], 2
    mov     edi, ST_INVENTORY
    call    app_goto
    jmp     .ret
.no_inventory:
    cmp     byte [net_role], NET_ROLE_OFF
    je      .simulate
    cmp     dword [frame_input + FRAMEINPUT.chat], 0
    je      .simulate
    mov     edi, ST_CHAT
    call    app_goto
    jmp     .ret
.simulate:
    movss   xmm0, [frame_dt]
    call    game_frame
    cmp     dword [surv + SURVIVAL.dead], 0
    je      .alive
    call    to_death
    jmp     .ret
.alive:
    mov     edi, [game_open_screen]
    test    edi, edi
    jz      .autosave
    mov     dword [game_open_screen], 0
    cmp     edi, ST_CRAFTING
    jne     .not_table
    mov     dword [craft_size], 3
    jmp     .open
.not_table:
    cmp     edi, ST_TRADE               ; the screens of the folk and the shrines hold no container
    je      .open
    cmp     edi, ST_DIALOG
    je      .open
    cmp     edi, ST_SHRINE
    je      .open
    cmp     edi, ST_LEADER
    je      .open
    cmp     edi, ST_EVENT
    je      .open
.container:
    mov     rax, [game_open_cont]
    mov     [inv_container], rax
.open:
    call    app_goto
.autosave:
    call    tick_autosave
    jmp     .ret

.screen:                                ; inventory screens: the world keeps running
    movss   xmm0, [frame_dt]
    call    game_frame
    mov     dword [game_open_screen], 0
    cmp     dword [surv + SURVIVAL.dead], 0
    je      .autosave
    call    inv_close_screen
    call    to_death
    jmp     .ret

.menus:                                 ; title panorama turns slowly
    movss   xmm0, [frame_dt]
    mulss   xmm0, [f_pano_rate]
    addss   xmm0, [panorama_cam + BODY.yaw]
    movss   xmm1, [f_360]
    comiss  xmm0, xmm1
    jb      .yaw
    subss   xmm0, xmm1
.yaw:
    movss   [panorama_cam + BODY.yaw], xmm0
    cmp     dword [app_state], ST_MP_JOIN   ; the character arrived: enter the host's world
    jne     .ret
    cmp     dword [net_join_ready], 0
    je      .ret
    call    app_join_world
.ret:
    pop     rbp
    ret

; draw_frame(): world, held item, HUD, then the current state's screen
draw_frame:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rdi, [app_window]
    lea     rsi, [fb_w]
    lea     rdx, [fb_h]
    call    glfwGetFramebufferSize
    cmp     dword [fb_w], 0
    jle     .ret
    cmp     dword [fb_h], 0
    jle     .ret
    lea     rdi, [panorama_cam]
    cmp     dword [app_in_world], 0
    je      .cam
    lea     rdi, [player]
.cam:
    mov     esi, [fb_w]
    mov     edx, [fb_h]
    call    render_world
    xor     ebx, ebx                    ; ebx = 1: in-world screen with hand and HUD
    cmp     dword [app_in_world], 0
    je      .ui
    mov     eax, [app_state]
    cmp     eax, ST_PLAYING
    je      .in_view
    cmp     eax, ST_PAUSED
    je      .in_view
    cmp     eax, ST_INVENTORY
    je      .in_view
    cmp     eax, ST_CRAFTING
    je      .in_view
    cmp     eax, ST_FURNACE
    je      .in_view
    cmp     eax, ST_CHEST
    je      .in_view
    cmp     eax, ST_TRADE
    je      .in_view
    cmp     eax, ST_DIALOG
    je      .in_view
    cmp     eax, ST_SKILLS
    je      .in_view
    cmp     eax, ST_CHARACTER
    je      .in_view
    cmp     eax, ST_SHRINE
    je      .in_view
    cmp     eax, ST_LEADER
    je      .in_view
    cmp     eax, ST_EVENT
    je      .in_view
    cmp     eax, ST_DEBUG
    je      .in_view
    cmp     eax, ST_MP_HOST
    je      .in_view
    cmp     eax, ST_CHAT
    jne     .ui
.in_view:
    mov     ebx, 1
    mov     edi, [fb_w]
    mov     esi, [fb_h]
    movss   xmm0, [frame_dt]
    call    hand_render
.ui:
    mov     edi, [fb_w]
    mov     esi, [fb_h]
    call    ui_begin
    test    ebx, ebx
    jz      .screen
    call    hud_draw
.screen:
    mov     eax, [app_state]
    cmp     eax, ST_EVENT
    ja      .ret
    mov     rax, [screens + rax*8]
    test    rax, rax
    jz      .ret
    call    rax
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; app_run(rdi play_path or 0) -> eax exit code
app_run:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     dword [exit_code], 0
    test    rdi, rdi
    jz      .title
    mov     rsi, rdi
    lea     rdi, [app_world_path]
    mov     edx, 4095
    call    str_copy
    lea     rdi, [s_loading]
    lea     rsi, [player]
    call    app_wait_area
    test    eax, eax
    jnz     .start                      ; the window was closed while loading: the loop leaves
    call    enter_world
    cmp     byte [net_cli_host], 0      ; --host: the world is opened to others at once
    je      .start
    call    cli_host
    jmp     .start
.title:
    call    load_panorama
    mov     dword [app_state], -1       ; force the transition bookkeeping
    cmp     qword [net_cli_join], 0     ; --join: the title is skipped, the join starts at once
    jne     .cli_join
    mov     edi, ST_TITLE
    call    app_goto
    jmp     .start
.cli_join:
    mov     edi, ST_MP_JOIN
    call    app_goto
    mov     rdi, [net_cli_join]
    lea     rsi, [net_cfg_name]
    movzx   edx, byte [net_cli_relay]
    call    net_join_begin
    test    eax, eax
    jz      .start
    mov     dword [exit_code], 3        ; (net_join_begin said why on stderr)
    jmp     .done
.start:
    call    glfwGetTime
    movsd   [last_time], xmm0
    movsd   [title_time], xmm0
    mov     dword [frames], 0
    call    update_title

.loop:
    call    glfwPollEvents
    mov     rdi, [app_window]
    call    glfwWindowShouldClose
    test    eax, eax
    jnz     .quit
    call    glfwGetTime
    movsd   xmm1, xmm0
    subsd   xmm1, [last_time]
    movsd   [last_time], xmm0
    xorpd   xmm2, xmm2
    maxsd   xmm1, xmm2
    minsd   xmm1, [d_max_dt]
    cvtsd2ss xmm1, xmm1
    movss   [frame_dt], xmm1
    mov     rdi, [app_window]
    call    input_poll
    cmp     dword [frame_input + FRAMEINPUT.fullscreen], 0
    je      .no_fs
    xor     dword [settings + SETTINGS.fullscreen], 1
    mov     rdi, [app_window]
    call    settings_apply
    lea     rdi, [settings_path]
    call    settings_save
.no_fs:
    call    net_pump                    ; the network: what arrived, who joined or left, the session's flows
    cmp     byte [net_join_exit], 0     ; --join: the join failed (the reason is on stderr)
    je      .no_join_exit
    mov     dword [exit_code], 3
    jmp     .done
.no_join_exit:
    mov     edi, [net_end_reason]
    test    edi, edi
    jz      .no_end
    call    app_leave_world             ; the host closed or the connection died: back to the title
.no_end:
    mov     ebx, [app_state]
    call    update_state
    cmp     ebx, [app_state]
    je      .same_state
    ; the edge that changed state must not also act on the new state's screen
    xor     eax, eax
    mov     [ui_input + UIINPUT.escape], eax
    mov     [ui_input + UIINPUT.enter], eax
    mov     [ui_input + UIINPUT.lmb_pressed], eax
    mov     [ui_input + UIINPUT.rmb_pressed], eax
    mov     [ui_input + UIINPUT.double_click], eax
    mov     [frame_input + FRAMEINPUT.inventory], eax
    mov     [frame_input + FRAMEINPUT.skills], eax
    mov     [ui_input + UIINPUT.typed_len], eax     ; (the T that opened the chat is not its first letter)
    mov     dword [ui_input + UIINPUT.key_pressed], -1
.same_state:
    movss   xmm0, [frame_dt]
    call    audio_update
    lea     rbx, [panorama_cam]         ; the world is streamed around the player, or the title's camera
    lea     rax, [player]
    cmp     dword [app_in_world], 0
    cmovne  rbx, rax
    movss   xmm0, [rbx + BODY.x]
    call    floor_i
    mov     [rsp], eax
    movss   xmm0, [rbx + BODY.z]
    call    floor_i
    mov     esi, eax
    mov     edi, [rsp]
    movss   xmm0, [f_stream_budget]
    call    stream_update               ; unload, collect, dispatch, install, light
    call    light_update                ; queued light changes first: they dirty chunks
    movss   xmm0, [f_mesh_budget]
    call    render_update_chunks
    movss   xmm0, [app_message_timer]
    subss   xmm0, [frame_dt]
    xorps   xmm1, xmm1
    maxss   xmm0, xmm1
    movss   [app_message_timer], xmm0
    mov     eax, [frame_dt]
    mov     [hud_dt], eax
    call    draw_frame
    mov     rdi, [app_window]
    call    glfwSwapBuffers
    call    net_flush
    inc     dword [frames]
    movsd   xmm1, [last_time]
    subsd   xmm1, [title_time]
    comisd  xmm1, [d_title_every]
    jb      .loop
    cvtsi2sd xmm0, dword [frames]
    divsd   xmm0, xmm1
    cvtsd2si eax, xmm0
    mov     [app_fps], eax
    mov     dword [frames], 0
    movsd   xmm0, [last_time]
    movsd   [title_time], xmm0
    call    update_title
    jmp     .loop

.quit:
    cmp     dword [app_in_world], 0
    jne     .quit_world
    call    net_join_cancel             ; the window closed while joining: leave the room
    jmp     .done
.quit_world:
    call    inv_close_screen            ; cursor and grid items go back before the save
    cmp     byte [net_role], NET_ROLE_GUEST
    je      .quit_guest
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .quit_save
    call    net_host_close              ; the guests are told and their characters are kept
.quit_save:
    call    save_world
    mov     [exit_code], eax
    mov     edi, 1
    call    stream_end                  ; the modified columns are written, every column unloads
    jmp     .done
.quit_guest:
    call    net_leave                   ; the character goes to the host, the connection says goodbye
    xor     edi, edi
    call    stream_end                  ; a guest saves nothing
.done:
    mov     eax, [exit_code]
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret
