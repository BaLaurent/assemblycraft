; main.asm - command line, data directory/settings setup, window creation, app loop.
%include "common.inc"
%include "gl.inc"
default rel

global main

extern sys_print, str_eq, parse_u32, str_append, str_copy, selftest_run, rng_seed
extern saves_init, saves_name_to_file, data_dir, worlds_dir, settings_path
extern settings_load, settings_apply, file_stat_mtime
extern game_load, game_new, game_save
extern render_init, ui_init, input_init, audio_init, audio_shutdown
extern app_run, app_window
extern stream_thread_start, stream_thread_stop, mkdir_p
extern net_cfg_load, net_cfg_cli, net_valid_name, net_parse_addr
extern net_cli_host, net_cli_join, net_cli_relay, net_cli_pvp

section .rodata
usage_text:
    db "usage: assemblycraft [--data-dir DIR] [--play NAME [--creative] [--seed N] [--host [--pvp]]]", 10
    db "                     [--name NAME] [--port N] [--server IP:PORT] [--join CODE|IP:PORT [--force-relay]]", 10
    db "                     [--selftest] [--help]", 10
    db "  --data-dir DIR  where worlds and settings live (default: $XDG_DATA_HOME/assemblycraft", 10
    db "                  or ~/.local/share/assemblycraft)", 10
    db "  --play NAME     skip the menus and play world NAME, creating it if it does not exist", 10
    db "  --creative      with --play, create the new world in Creative mode (default: Survival)", 10
    db "  --seed N        with --play, seed for a newly created world (default: random)", 10
    db "  --name NAME     the multiplayer name for this run (1-16 letters, digits or _)", 10
    db "  --host          with --play, open the world to multiplayer at once", 10
    db "  --pvp           with --host, players can hurt each other", 10
    db "  --port N        UDP port to host on (default 27615, then the next nine)", 10
    db "  --server IP:PORT  rendezvous server for this run (default 93.127.163.226:27600)", 10
    db "  --join TARGET   skip the title and join a world: a room code or IP[:PORT]; exit code 3 if it fails", 10
    db "  --force-relay   with --join, go through the relay server without trying to punch through", 10
    db "  --selftest      run internal tests and exit", 10
    db "controls (rebindable in Settings > Controls): WASD move, Space jump / fly up,", 10
    db "  Left Shift sneak / fly down, Left Ctrl sprint, E inventory, F toggle fly (Creative),", 10
    db "  R reload, C dodge roll, Q / G / V / X abilities, K grimoire,", 10
    db "  mouse look, LMB break / attack / cast, RMB place / use / eat / guard (melee weapon),", 10
    db "  MMB pick block, 1-9 / wheel select, Esc pause, F3 debug info, F11 fullscreen", 10, 0
opt_help:     db "--help", 0
opt_selftest: db "--selftest", 0
opt_data:     db "--data-dir", 0
opt_play:     db "--play", 0
opt_creative: db "--creative", 0
opt_seed:     db "--seed", 0
opt_name:     db "--name", 0
opt_host:     db "--host", 0
opt_port:     db "--port", 0
opt_pvp:      db "--pvp", 0
opt_server:   db "--server", 0
opt_join:     db "--join", 0
opt_relay:    db "--force-relay", 0
s_prefix:     db "assemblycraft: ", 0
s_no_dir:     db "assemblycraft: cannot create data directory ", 0
s_bad_cfg:    db "assemblycraft: ignored invalid lines in ", 0
s_invalid:    db " is not a valid AssemblyCraft world", 10, 0
s_cannot_read: db "assemblycraft: cannot read ", 0
s_save_fail:  db "assemblycraft: failed to save world to ", 0
s_no_sound:   db "assemblycraft: sound disabled (cannot connect to PulseAudio)", 10, 0
s_nl:         db 10, 0
s_slash:      db "/", 0
s_ext:        db ".acw", 0
s_hdr:        db "/world.hdr", 0
s_old_world:  db " is a world from 0.8 or earlier; this version cannot open it", 10, 0
s_glfw_fail:  db "assemblycraft: glfwInit failed", 10, 0
s_win_fail:   db "assemblycraft: cannot create window", 10, 0
s_app_id:     db "assemblycraft", 0
s_title:      db "AssemblyCraft", 0

section .bss
alignb 8
envp:        resq 1
data_arg:    resq 1                     ; --data-dir value or 0
play_name:   resq 1                     ; --play value or 0
cli_name:    resq 1                     ; --name value or 0
cli_server:  resq 1                     ; --server value (a NADDR)
window:      resq 1
seed_value:  resd 1
seed_given:  resd 1
creative:    resd 1
cli_port:    resd 1                     ; --port value or 0
cli_server_set: resd 1
want_help:   resd 1
want_test:   resd 1
play_path:   resb 4096

section .text

; main(edi argc, rsi argv, rdx envp) -> eax exit code
main:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     r12d, edi                   ; argc
    mov     r13, rsi                    ; argv
    mov     [envp], rdx
    mov     ebx, 1                      ; i
.arg:
    cmp     ebx, r12d
    jge     .parsed
%macro IS_OPT 1                         ; eax = argv[i] == %1
    mov     rdi, [r13 + rbx*8]
    lea     rsi, [%1]
    call    str_eq
%endmacro
    IS_OPT  opt_help
    test    eax, eax
    jz      .not_help
    mov     dword [want_help], 1
    inc     ebx
    jmp     .arg
.not_help:
    IS_OPT  opt_selftest
    test    eax, eax
    jz      .not_test
    mov     dword [want_test], 1
    inc     ebx
    jmp     .arg
.not_test:
    IS_OPT  opt_creative
    test    eax, eax
    jz      .not_creative
    mov     dword [creative], 1
    inc     ebx
    jmp     .arg
.not_creative:
    IS_OPT  opt_seed
    test    eax, eax
    jz      .not_seed
    inc     ebx
    cmp     ebx, r12d
    jge     .usage_err
    mov     rdi, [r13 + rbx*8]
    lea     rsi, [seed_value]
    call    parse_u32
    test    eax, eax
    jz      .usage_err
    mov     dword [seed_given], 1
    inc     ebx
    jmp     .arg
.not_seed:
    IS_OPT  opt_data
    test    eax, eax
    jz      .not_data
    inc     ebx
    cmp     ebx, r12d
    jge     .usage_err
    mov     rax, [r13 + rbx*8]
    cmp     byte [rax], 0
    je      .usage_err
    mov     [data_arg], rax
    inc     ebx
    jmp     .arg
.not_data:
    IS_OPT  opt_play
    test    eax, eax
    jz      .not_play
    inc     ebx
    cmp     ebx, r12d
    jge     .usage_err
    mov     rax, [r13 + rbx*8]
    cmp     byte [rax], 0
    je      .usage_err
    mov     [play_name], rax
    inc     ebx
    jmp     .arg
.not_play:
    IS_OPT  opt_host
    test    eax, eax
    jz      .not_host
    mov     byte [net_cli_host], 1
    inc     ebx
    jmp     .arg
.not_host:
    IS_OPT  opt_pvp
    test    eax, eax
    jz      .not_pvp
    mov     byte [net_cli_pvp], 1
    inc     ebx
    jmp     .arg
.not_pvp:
    IS_OPT  opt_relay
    test    eax, eax
    jz      .not_relay
    mov     byte [net_cli_relay], 1
    inc     ebx
    jmp     .arg
.not_relay:
    IS_OPT  opt_name
    test    eax, eax
    jz      .not_name
    inc     ebx
    cmp     ebx, r12d
    jge     .usage_err
    mov     rdi, [r13 + rbx*8]
    call    net_valid_name
    test    eax, eax
    jz      .usage_err
    mov     rax, [r13 + rbx*8]
    mov     [cli_name], rax
    inc     ebx
    jmp     .arg
.not_name:
    IS_OPT  opt_port
    test    eax, eax
    jz      .not_port
    inc     ebx
    cmp     ebx, r12d
    jge     .usage_err
    mov     rdi, [r13 + rbx*8]
    lea     rsi, [cli_port]
    call    parse_u32
    test    eax, eax
    jz      .usage_err
    mov     eax, [cli_port]
    lea     ecx, [rax - 1]
    cmp     ecx, 65534                  ; 1..65535
    ja      .usage_err
    inc     ebx
    jmp     .arg
.not_port:
    IS_OPT  opt_server
    test    eax, eax
    jz      .not_server
    inc     ebx
    cmp     ebx, r12d
    jge     .usage_err
    mov     rdi, [r13 + rbx*8]
    lea     rsi, [cli_server]
    mov     edx, RV_PORT
    call    net_parse_addr
    test    eax, eax
    jz      .usage_err
    mov     dword [cli_server_set], 1
    inc     ebx
    jmp     .arg
.not_server:
    IS_OPT  opt_join
    test    eax, eax
    jz      .usage_err
    inc     ebx
    cmp     ebx, r12d
    jge     .usage_err
    mov     rax, [r13 + rbx*8]
    cmp     byte [rax], 0
    je      .usage_err
    mov     [net_cli_join], rax
    inc     ebx
    jmp     .arg

.parsed:
    cmp     dword [want_help], 0
    je      .no_help
    mov     edi, 1
    lea     rsi, [usage_text]
    call    sys_print
    xor     eax, eax
    jmp     .ret
.no_help:
    cmp     qword [play_name], 0
    jne     .play_ok
    movzx   eax, byte [net_cli_host]
    or      eax, [creative]
    or      eax, [seed_given]
    jnz     .usage_err                  ; --creative / --seed / --host need --play
.play_ok:
    cmp     byte [net_cli_host], 0
    jne     .pvp_ok
    cmp     byte [net_cli_pvp], 0
    jne     .usage_err                  ; --pvp needs --host
.pvp_ok:
    cmp     qword [net_cli_join], 0
    jne     .join_given
    cmp     byte [net_cli_relay], 0
    jne     .usage_err                  ; --force-relay needs --join
    jmp     .join_ok
.join_given:
    cmp     qword [play_name], 0
    jne     .usage_err                  ; --join and --play are two ways into a world
.join_ok:
    cmp     dword [want_test], 0
    je      .game
    call    selftest_run
    jmp     .ret
.game:
    call    run_game
    jmp     .ret

.usage_err:
    mov     edi, 2
    lea     rsi, [usage_text]
    call    sys_print
    mov     eax, 2
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; err3(rdi a, rsi b, rdx c): stderr a b c (b, c may be 0)
err3:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     rbx, rsi
    mov     r12, rdx
    mov     rsi, rdi
    mov     edi, 2
    call    sys_print
    test    rbx, rbx
    jz      .c
    mov     edi, 2
    mov     rsi, rbx
    call    sys_print
.c:
    test    r12, r12
    jz      .ret
    mov     edi, 2
    mov     rsi, r12
    call    sys_print
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; prepare_play_world() -> eax 0 ok / 1 error reported / 2 a world of 0.8 or earlier has that name.
; The world is the directory worlds/<sanitized name>: loaded when it holds a world.hdr, created
; (Survival, or Creative with --creative; the seed from --seed or the clock) when nothing of that
; name exists.
prepare_play_world:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    lea     rdi, [play_path]
    lea     rsi, [worlds_dir]
    call    str_append
    mov     rdi, rax
    lea     rsi, [s_slash]
    call    str_append
    mov     rdi, [play_name]
    mov     rsi, rax
    call    saves_name_to_file
    mov     rbx, rax                    ; end of the directory path
    mov     byte [rbx], 0
    mov     rdi, rbx                    ; is there a <dir>/world.hdr?
    lea     rsi, [s_hdr]
    call    str_append
    mov     byte [rax], 0
    lea     rdi, [play_path]
    call    file_stat_mtime
    mov     byte [rbx], 0
    test    rax, rax
    jns     .load
    mov     rdi, rbx                    ; or a <dir>.acw: a world of 0.8 or earlier
    lea     rsi, [s_ext]
    call    str_append
    mov     byte [rax], 0
    lea     rdi, [play_path]
    call    file_stat_mtime
    mov     byte [rbx], 0
    test    rax, rax
    jns     .old
    lea     rdi, [play_path]            ; nothing of that name: a new world
    call    mkdir_p
    mov     edi, [seed_value]
    cmp     dword [seed_given], 0
    jne     .seeded
    rdtsc
    mov     edi, eax
.seeded:
    mov     esi, [creative]
    mov     rdx, [play_name]
    lea     rcx, [play_path]
    call    game_new
    lea     rdi, [play_path]
    call    game_save
    test    eax, eax
    jz      .ok
    lea     rdi, [s_save_fail]
    lea     rsi, [play_path]
    lea     rdx, [s_nl]
    call    err3
    jmp     .fail
.load:
    lea     rdi, [play_path]
    call    game_load
    test    eax, eax
    jz      .ok
    cmp     eax, 2
    jne     .unreadable
    lea     rdi, [s_prefix]
    lea     rsi, [play_path]
    lea     rdx, [s_invalid]
    call    err3
    jmp     .fail
.unreadable:
    lea     rdi, [s_cannot_read]
    lea     rsi, [play_path]
    lea     rdx, [s_nl]
    call    err3
    jmp     .fail
.old:
    mov     rdi, [play_name]
    lea     rsi, [s_old_world]
    xor     edx, edx
    call    err3
    mov     eax, 2
    jmp     .ret
.fail:
    mov     eax, 1
    jmp     .ret
.ok:
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; run_game() -> eax exit code. Setup errors surface before any window opens.
run_game:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    rdtsc
    mov     edi, eax
    call    rng_seed
    mov     rdi, [envp]
    mov     rsi, [data_arg]
    call    saves_init
    test    eax, eax
    jz      .dirs_ok
    mov     rsi, [data_arg]
    test    rsi, rsi
    jnz     .dir_msg
    lea     rsi, [data_dir]
.dir_msg:
    lea     rdi, [s_no_dir]
    lea     rdx, [s_nl]
    call    err3
    mov     eax, 1
    jmp     .ret
.dirs_ok:
    lea     rdi, [settings_path]
    call    settings_load
    cmp     eax, 2
    jne     .cfg_ok
    lea     rdi, [s_bad_cfg]
    lea     rsi, [settings_path]
    lea     rdx, [s_nl]
    call    err3
.cfg_ok:
    call    net_cfg_load                ; multiplayer.cfg, then the command line over it (for this run only)
    mov     rdi, [cli_name]
    xor     esi, esi
    cmp     dword [cli_server_set], 0
    je      .no_server
    lea     rsi, [cli_server]
.no_server:
    mov     edx, [cli_port]
    call    net_cfg_cli
    xor     r12d, r12d                  ; play path for app_run
    cmp     qword [play_name], 0
    je      .window
    call    prepare_play_world
    test    eax, eax
    jnz     .ret
    lea     r12, [play_path]

.window:
    call    glfwInit
    test    eax, eax
    jnz     .glfw_ok
    lea     rdi, [s_glfw_fail]
    xor     esi, esi
    xor     edx, edx
    call    err3
    mov     eax, 1
    jmp     .ret
.glfw_ok:
    mov     edi, GLFW_DEPTH_BITS
    mov     esi, 24
    call    glfwWindowHint
    mov     edi, GLFW_WAYLAND_APP_ID
    lea     rsi, [s_app_id]
    call    glfwWindowHintString
    mov     edi, GLFW_X11_CLASS_NAME
    lea     rsi, [s_app_id]
    call    glfwWindowHintString
    mov     edi, 1280
    mov     esi, 720
    lea     rdx, [s_title]
    xor     ecx, ecx
    xor     r8d, r8d
    call    glfwCreateWindow
    test    rax, rax
    jnz     .win_ok
    lea     rdi, [s_win_fail]
    xor     esi, esi
    xor     edx, edx
    call    err3
    call    glfwTerminate
    mov     eax, 1
    jmp     .ret
.win_ok:
    mov     [window], rax
    mov     [app_window], rax
    mov     rdi, rax
    call    glfwMakeContextCurrent
    call    render_init
    call    ui_init
    mov     rdi, [window]
    call    input_init
    call    audio_init
    test    eax, eax
    jnz     .sound_ok
    lea     rdi, [s_no_sound]
    xor     esi, esi
    xor     edx, edx
    call    err3
.sound_ok:
    mov     rdi, [window]
    call    settings_apply
    call    stream_thread_start         ; the terrain generator runs beside the game from here on
    mov     rdi, r12
    call    app_run
    mov     ebx, eax
    call    stream_thread_stop
    call    audio_shutdown
    mov     rdi, [window]
    call    glfwDestroyWindow
    call    glfwTerminate
    mov     eax, ebx
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret
