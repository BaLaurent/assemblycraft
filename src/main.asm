; main.asm - command-line handling and program entry.
%include "common.inc"
default rel

global main

extern sys_print, str_eq, parse_u32, selftest_run

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

section .data
align 8
world_path: dq default_world
seed_value: dd 0
seed_given: dd 0
want_help:  dd 0
want_test:  dd 0

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
    je      .usage_err                  ; step 1: the game is not wired yet
    call    selftest_run
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
