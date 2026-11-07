; main.asm - command-line handling, world load/create, window and game loop.
%include "common.inc"
%include "gl.inc"
default rel

global main

extern sys_print, str_eq, parse_u32, str_append, i32_to_str, selftest_run
extern game_load, game_new, game_save, game_frame, frame_input
extern render_init, render_update_chunks, render_frame, input_init, input_poll
extern player, hotbar, hotbar_sel, block_names, floor_i

section .rodata
usage_text:
    db "usage: assemblycraft [--world PATH] [--seed N] [--selftest] [--help]", 10
    db "  --world PATH  world file to load and save (default: world.acw)", 10
    db "  --seed N      seed for a newly generated world (default: random)", 10
    db "  --selftest    run internal tests and exit", 10
    db "controls: WASD move, mouse look, Space jump (fly: up), Left Shift fly down, Left Ctrl sprint,", 10
    db "          F toggle fly, LMB break, RMB place, MMB pick block, 1-9 / wheel select, F5 save,", 10
    db "          Esc release mouse (click to recapture), close window to save and quit", 10, 0
opt_help:     db "--help", 0
opt_selftest: db "--selftest", 0
opt_seed:     db "--seed", 0
opt_world:    db "--world", 0
default_world: db "world.acw", 0
s_prefix:     db "assemblycraft: ", 0
s_invalid:    db " is not a valid AssemblyCraft world", 10, 0
s_cannot_read: db "assemblycraft: cannot read ", 0
s_save_fail:  db "assemblycraft: failed to save world to ", 0
s_nl:         db 10, 0
s_glfw_fail:  db "assemblycraft: glfwInit failed", 10, 0
s_win_fail:   db "assemblycraft: cannot create window", 10, 0
s_app_id:     db "assemblycraft", 0
s_title:      db "AssemblyCraft", 0
s_title_fps:  db "AssemblyCraft | ", 0
s_fps:        db " FPS | ", 0
s_space:      db " ", 0
s_sep:        db " | ", 0
s_fly:        db " | fly", 0
align 8
d_max_dt:     dq 0.25
d_title_every: dq 0.5

section .data
align 8
world_path: dq default_world
seed_value: dd 0
seed_given: dd 0
want_help:  dd 0
want_test:  dd 0

section .bss
alignb 8
window:     resq 1
last_time:  resq 1
title_time: resq 1
frame_dt:   resq 1
frames:     resd 1
fb_w:       resd 1
fb_h:       resd 1
title_buf:  resb 256

section .text

; main(edi argc, rsi argv) -> eax exit code
main:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     r12d, edi                   ; argc
    mov     r13, rsi                    ; argv
    mov     ebx, 1                      ; i
.arg:
    cmp     ebx, r12d
    jge     .parsed
    mov     rdi, [r13 + rbx*8]
    lea     rsi, [opt_help]
    call    str_eq
    test    eax, eax
    jz      .not_help
    mov     dword [want_help], 1
    inc     ebx
    jmp     .arg
.not_help:
    mov     rdi, [r13 + rbx*8]
    lea     rsi, [opt_selftest]
    call    str_eq
    test    eax, eax
    jz      .not_test
    mov     dword [want_test], 1
    inc     ebx
    jmp     .arg
.not_test:
    mov     rdi, [r13 + rbx*8]
    lea     rsi, [opt_seed]
    call    str_eq
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
    mov     rdi, [r13 + rbx*8]
    lea     rsi, [opt_world]
    call    str_eq
    test    eax, eax
    jz      .usage_err
    inc     ebx
    cmp     ebx, r12d
    jge     .usage_err
    mov     rax, [r13 + rbx*8]
    mov     [world_path], rax
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

; print_path_msg(rdi prefix, rsi suffix): stderr <prefix><world_path><suffix>
print_path_msg:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rsi
    mov     rsi, rdi
    mov     edi, 2
    call    sys_print
    mov     edi, 2
    mov     rsi, [world_path]
    call    sys_print
    mov     edi, 2
    mov     rsi, rbx
    call    sys_print
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; update_title(xmm0 double fps)
update_title:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    cvtsd2si ebx, xmm0
    lea     rdi, [title_buf]
    lea     rsi, [s_title_fps]
    call    str_append
    mov     edi, ebx
    mov     rsi, rax
    call    i32_to_str
    mov     rdi, rax
    lea     rsi, [s_fps]
    call    str_append
    mov     rbx, rax
%macro TITLE_COORD 2                    ; field, separator
    movss   xmm0, [player + PLAYER.%1]
    call    floor_i
    mov     edi, eax
    mov     rsi, rbx
    call    i32_to_str
    mov     rdi, rax
    lea     rsi, [%2]
    call    str_append
    mov     rbx, rax
%endmacro
    TITLE_COORD x, s_space
    TITLE_COORD y, s_space
    TITLE_COORD z, s_sep
    mov     eax, [hotbar_sel]
    movzx   eax, byte [hotbar + rax]
    mov     rsi, [block_names + rax*8]
    mov     rdi, rbx
    call    str_append
    cmp     dword [player + PLAYER.flying], 0
    je      .no_fly
    mov     rdi, rax
    lea     rsi, [s_fly]
    call    str_append
.no_fly:
    mov     byte [rax], 0
    mov     rdi, [window]
    lea     rsi, [title_buf]
    call    glfwSetWindowTitle
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; run_game() -> eax exit code. World errors surface before any window opens.
run_game:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     rdi, [world_path]
    call    game_load
    test    eax, eax
    jz      .world_ready
    cmp     eax, 1
    je      .new_world
    cmp     eax, 2
    jne     .unreadable
    lea     rdi, [s_prefix]
    lea     rsi, [s_invalid]
    call    print_path_msg
    mov     eax, 1
    jmp     .ret
.unreadable:
    lea     rdi, [s_cannot_read]
    lea     rsi, [s_nl]
    call    print_path_msg
    mov     eax, 1
    jmp     .ret
.new_world:
    mov     edi, [seed_value]
    cmp     dword [seed_given], 0
    jne     .seeded
    rdtsc
    mov     edi, eax
.seeded:
    call    game_new
.world_ready:

    call    glfwInit
    test    eax, eax
    jnz     .glfw_ok
    mov     edi, 2
    lea     rsi, [s_glfw_fail]
    call    sys_print
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
    mov     edi, 2
    lea     rsi, [s_win_fail]
    call    sys_print
    call    glfwTerminate
    mov     eax, 1
    jmp     .ret
.win_ok:
    mov     [window], rax
    mov     rdi, rax
    call    glfwMakeContextCurrent
    mov     edi, 1
    call    glfwSwapInterval
    call    render_init
    mov     rdi, [window]
    call    input_init
    call    glfwGetTime
    movsd   [last_time], xmm0
    movsd   [title_time], xmm0
    mov     dword [frames], 0

.loop:
    mov     rdi, [window]
    call    glfwWindowShouldClose
    test    eax, eax
    jnz     .quit
    call    glfwPollEvents
    call    glfwGetTime
    movsd   xmm1, xmm0
    subsd   xmm1, [last_time]
    movsd   [last_time], xmm0
    minsd   xmm1, [d_max_dt]
    movsd   [frame_dt], xmm1
    mov     rdi, [window]
    call    input_poll
    cmp     dword [frame_input + FRAMEINPUT.save], 0
    je      .no_save
    mov     rdi, [world_path]
    call    game_save
    test    eax, eax
    jz      .no_save
    lea     rdi, [s_save_fail]
    lea     rsi, [s_nl]
    call    print_path_msg
.no_save:
    cvtsd2ss xmm0, [frame_dt]
    call    game_frame
    call    render_update_chunks
    mov     rdi, [window]
    lea     rsi, [fb_w]
    lea     rdx, [fb_h]
    call    glfwGetFramebufferSize
    mov     edi, [fb_w]
    mov     esi, [fb_h]
    test    edi, edi
    jle     .no_draw
    test    esi, esi
    jle     .no_draw
    call    render_frame
.no_draw:
    mov     rdi, [window]
    call    glfwSwapBuffers
    inc     dword [frames]
    movsd   xmm1, [last_time]
    subsd   xmm1, [title_time]
    comisd  xmm1, [d_title_every]
    jb      .loop
    cvtsi2sd xmm0, dword [frames]
    divsd   xmm0, xmm1
    call    update_title
    mov     dword [frames], 0
    movsd   xmm0, [last_time]
    movsd   [title_time], xmm0
    jmp     .loop

.quit:
    xor     ebx, ebx
    mov     rdi, [world_path]
    call    game_save
    test    eax, eax
    jz      .saved
    lea     rdi, [s_save_fail]
    lea     rsi, [s_nl]
    call    print_path_msg
    mov     ebx, 1
.saved:
    mov     rdi, [window]
    call    glfwDestroyWindow
    call    glfwTerminate
    mov     eax, ebx
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret
