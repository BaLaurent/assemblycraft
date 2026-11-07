; test_saves.asm - file-name sanitising, world list scan/rename/delete, fmt_ago.
%include "common.inc"
default rel

global test_saves_sanitize_name, test_saves_scan_rename_delete

extern world_clear, world_save, world_header
extern str_eq, str_copy, file_unlink, time_now
extern saves_init, saves_scan, saves_name_to_file, saves_new_file_path
extern saves_delete, saves_rename, fmt_ago
extern world_list, world_count

section .rodata
n_in1:   db "My World!", 0
n_ex1:   db "My_World", 0
n_in2:   db "!!!", 0
n_ex2:   db "World", 0
n_in3:   db "a/b..c", 0
n_ex3:   db "abc", 0
n_in4:   db "  x  ", 0
n_ex4:   db "x", 0
n_in5:   times 50 db 'a'
         db 0
n_ex5:   times 40 db 'a'
         db 0

d_data:  db "/tmp/assemblycraft-selftest-data", 0
p_alpha: db "/tmp/assemblycraft-selftest-data/worlds/Alpha.acw", 0
p_alpha2: db "/tmp/assemblycraft-selftest-data/worlds/Alpha-2.acw", 0
p_beta:  db "/tmp/assemblycraft-selftest-data/worlds/Beta.acw", 0
p_gamma: db "/tmp/assemblycraft-selftest-data/worlds/Gamma.acw", 0
n_alpha: db "Alpha", 0
n_beta:  db "Beta", 0
n_gamma: db "Gamma", 0

a_just:  db "just now", 0
a_2min:  db "2 min ago", 0
a_2h:    db "2 h ago", 0
a_1day:  db "1 day ago", 0
a_3days: db "3 days ago", 0

section .bss
out_buf: resb 4200
ago_buf: resb 64

section .text

; check_name(rdi in, rsi expected) -> eax 0 if saves_name_to_file(in) == expected
check_name:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rsi
    lea     rsi, [out_buf]
    call    saves_name_to_file
    mov     byte [rax], 0
    lea     rdi, [out_buf]
    mov     rsi, rbx
    call    str_eq
    cmp     eax, 1
    setne   al
    movzx   eax, al
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

%macro CHECK_NAME 1
    lea     rdi, [n_in%1]
    lea     rsi, [n_ex%1]
    call    check_name
    test    eax, eax
    jnz     .fail
%endmacro

test_saves_sanitize_name:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    CHECK_NAME 1
    CHECK_NAME 2
    CHECK_NAME 3
    CHECK_NAME 4
    CHECK_NAME 5
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret

; make_world(rdi path, rsi name, edx mode) -> eax world_save result (header zeroed first)
make_world:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13d, edx
    call    zero_header
    lea     rdi, [world_header + WORLDHDR.name]
    mov     rsi, r12
    mov     edx, 32
    call    str_copy
    mov     [world_header + WORLDHDR.mode], r13d
    mov     dword [world_header + WORLDHDR.seed], 7
    mov     rdi, rbx
    call    world_save
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

zero_header:
    lea     rdi, [world_header]
    xor     eax, eax
    mov     ecx, WORLD_HDR_SIZE
    rep     stosb
    ret

; unlink_all(): remove every file the test may have left
unlink_all:
    sub     rsp, 8
    lea     rdi, [p_alpha]
    call    file_unlink
    lea     rdi, [p_beta]
    call    file_unlink
    lea     rdi, [p_gamma]
    call    file_unlink
    add     rsp, 8
    ret

; find_entry(rdi name, esi mode or -1 for any) -> eax index in world_list, or -1.
; Only valid entries match.
find_entry:
    xor     ecx, ecx
    mov     r8d, [world_count]
.l:
    cmp     ecx, r8d
    jae     .none
    mov     eax, ecx
    shl     rax, 7
    lea     rdx, [world_list]
    add     rdx, rax
    xor     r9d, r9d
.c:
    mov     al, [rdx + WORLDENTRY.name + r9]
    cmp     al, [rdi + r9]
    jne     .next
    test    al, al
    jz      .match
    inc     r9
    jmp     .c
.match:
    cmp     dword [rdx + WORLDENTRY.valid], 1
    jne     .next
    cmp     esi, -1
    je      .found
    cmp     [rdx + WORLDENTRY.mode], esi
    jne     .next
.found:
    mov     eax, ecx
    ret
.next:
    inc     ecx
    jmp     .l
.none:
    mov     eax, -1
    ret

; check_ago(edi seconds_ago, rsi expected) -> eax 0 if fmt_ago(now - seconds_ago) == expected
check_ago:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12, rsi
    call    time_now
    sub     rax, rbx
    mov     rsi, rax
    lea     rdi, [ago_buf]
    call    fmt_ago
    lea     rdi, [ago_buf]
    mov     rsi, r12
    call    str_eq
    cmp     eax, 1
    setne   al
    movzx   eax, al
    pop     r12
    pop     rbx
    pop     rbp
    ret

test_saves_scan_rename_delete:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    xor     edi, edi
    lea     rsi, [d_data]
    call    saves_init
    test    eax, eax
    jnz     .fail
    call    unlink_all
    lea     rdi, [p_alpha]
    lea     rsi, [n_alpha]
    xor     edx, edx
    call    make_world
    test    eax, eax
    jnz     .fail
    lea     rdi, [p_beta]
    lea     rsi, [n_beta]
    mov     edx, 1
    call    make_world
    test    eax, eax
    jnz     .fail
    ; Alpha.acw exists, so a new "Alpha" must become Alpha-2.acw
    lea     rdi, [n_alpha]
    lea     rsi, [out_buf]
    call    saves_new_file_path
    test    eax, eax
    jnz     .fail
    lea     rdi, [out_buf]
    lea     rsi, [p_alpha2]
    call    str_eq
    cmp     eax, 1
    jne     .fail
    ; scan: two entries with the right names and modes
    call    saves_scan
    cmp     eax, 2
    jne     .fail
    lea     rdi, [n_alpha]
    xor     esi, esi
    call    find_entry
    mov     ebx, eax
    test    ebx, ebx
    js      .fail
    lea     rdi, [n_beta]
    mov     esi, 1
    call    find_entry
    test    eax, eax
    js      .fail
    ; rename Alpha -> Gamma
    mov     edi, ebx
    lea     rsi, [n_gamma]
    call    saves_rename
    test    eax, eax
    jnz     .fail
    call    saves_scan
    cmp     eax, 2
    jne     .fail
    lea     rdi, [n_gamma]
    xor     esi, esi
    call    find_entry
    test    eax, eax
    js      .fail
    lea     rdi, [n_alpha]
    mov     esi, -1
    call    find_entry
    cmp     eax, -1
    jne     .fail
    ; delete Beta
    lea     rdi, [n_beta]
    mov     esi, 1
    call    find_entry
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    saves_delete
    test    eax, eax
    jnz     .fail
    call    saves_scan
    cmp     eax, 1
    jne     .fail
    lea     rdi, [n_gamma]
    mov     esi, -1
    call    find_entry
    test    eax, eax
    js      .fail
    ; fmt_ago
    xor     edi, edi
    lea     rsi, [a_just]
    call    check_ago
    test    eax, eax
    jnz     .fail
    mov     edi, 120
    lea     rsi, [a_2min]
    call    check_ago
    test    eax, eax
    jnz     .fail
    mov     edi, 7200
    lea     rsi, [a_2h]
    call    check_ago
    test    eax, eax
    jnz     .fail
    mov     edi, 86400 + 5
    lea     rsi, [a_1day]
    call    check_ago
    test    eax, eax
    jnz     .fail
    mov     edi, 3 * 86400 + 5
    lea     rsi, [a_3days]
    call    check_ago
    test    eax, eax
    jnz     .fail
    xor     ebx, ebx
    jmp     .done
.fail:
    mov     ebx, 1
.done:
    call    unlink_all
    call    zero_header
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret
