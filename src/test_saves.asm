; test_saves.asm - file-name sanitising, the world list over 0.9 world directories and worlds of 0.8 or
; earlier (scan, create, rename, delete), fmt_ago.
%include "common.inc"
default rel

global test_saves_sanitize_name, test_saves_scan_rename_delete, test_saves_old_world_incompatible

extern world_clear, world_header
extern str_eq, str_copy, str_append, file_unlink, file_read, file_write_atomic, file_stat_mtime
extern time_now, mkdir_p, dir_remove_tree
extern saves_init, saves_scan, saves_name_to_file, saves_new_world_dir
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
w_alpha: db "/tmp/assemblycraft-selftest-data/worlds/Alpha", 0
w_alpha2: db "/tmp/assemblycraft-selftest-data/worlds/Alpha-2", 0
w_alpha2_regions: db "/tmp/assemblycraft-selftest-data/worlds/Alpha-2/regions", 0
w_beta:  db "/tmp/assemblycraft-selftest-data/worlds/Beta", 0
w_a:     db "/tmp/assemblycraft-selftest-data/worlds/A", 0
w_bad:   db "/tmp/assemblycraft-selftest-data/worlds/Bad", 0
w_old2:  db "/tmp/assemblycraft-selftest-data/worlds/Old-2", 0
p_a_reg: db "/tmp/assemblycraft-selftest-data/worlds/A/regions/r.0.0.bin", 0
p_bad_hdr: db "/tmp/assemblycraft-selftest-data/worlds/Bad/world.hdr", 0
p_old:   db "/tmp/assemblycraft-selftest-data/worlds/Old.acw", 0
p_note:  db "/tmp/assemblycraft-selftest-data/worlds/note.txt", 0
p_leftovers:                            ; files an interrupted run of the 0.8 version of this test left
         db "/tmp/assemblycraft-selftest-data/worlds/Alpha.acw", 0
         db "/tmp/assemblycraft-selftest-data/worlds/Beta.acw", 0
         db "/tmp/assemblycraft-selftest-data/worlds/Gamma.acw", 0
         db 0
n_alpha: db "Alpha", 0
n_beta:  db "Beta", 0
n_gamma: db "Gamma", 0
n_a:     db "A", 0
n_old:   db "Old", 0
n_new:   db "New", 0
f_old:   db "Old.acw", 0
s_regions: db "/regions", 0
s_hdr:   db "/world.hdr", 0

a_just:  db "just now", 0
a_2min:  db "2 min ago", 0
a_2h:    db "2 h ago", 0
a_1day:  db "1 day ago", 0
a_3days: db "3 days ago", 0

section .bss
out_buf: resb 4200
ago_buf: resb 64
dir_buf: resb 4200
hdr_path_buf: resb 4200
file_buf: resb 1024
read_buf: resb 128

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

zero_header:
    lea     rdi, [world_header]
    xor     eax, eax
    mov     ecx, WORLD_HDR_SIZE
    rep     stosb
    ret

; make_world(rdi dir, rsi name, edx mode) -> eax 0 / -errno
; A 0.9 world: the directory with its regions/ and a world.hdr (magic, name, mode, seed 7); the header
; image world_header is used for it and left holding it.
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
    lea     rdi, [dir_buf]
    mov     rsi, rbx
    mov     edx, 4000
    call    str_copy
    mov     rdi, rax
    lea     rsi, [s_regions]
    call    str_append
    mov     byte [rax], 0
    lea     rdi, [dir_buf]                  ; mkdir_p makes <dir> on the way to <dir>/regions
    call    mkdir_p
    test    eax, eax
    jnz     .ret
    call    zero_header
    mov     rax, "ACRAFT06"
    mov     [world_header + WORLDHDR.magic], rax
    lea     rdi, [world_header + WORLDHDR.name]
    mov     rsi, r12
    mov     edx, 32
    call    str_copy
    mov     [world_header + WORLDHDR.mode], r13d
    mov     dword [world_header + WORLDHDR.seed], 7
    lea     rdi, [hdr_path_buf]
    mov     rsi, rbx
    mov     edx, 4000
    call    str_copy
    mov     rdi, rax
    lea     rsi, [s_hdr]
    call    str_append
    mov     byte [rax], 0
    lea     rdi, [hdr_path_buf]
    lea     rsi, [world_header]
    mov     edx, WORLD_HDR_SIZE
    call    file_write_atomic
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; clean_up(): remove everything the tests of this file may have left
clean_up:
    push    rbx
    lea     rdi, [w_alpha]
    call    dir_remove_tree
    lea     rdi, [w_alpha2]
    call    dir_remove_tree
    lea     rdi, [w_beta]
    call    dir_remove_tree
    lea     rdi, [w_a]
    call    dir_remove_tree
    lea     rdi, [w_bad]
    call    dir_remove_tree
    lea     rdi, [w_old2]
    call    dir_remove_tree
    lea     rdi, [p_old]
    call    file_unlink
    lea     rdi, [p_note]
    call    file_unlink
    lea     rbx, [p_leftovers]
.left:
    cmp     byte [rbx], 0
    je      .ret
    mov     rdi, rbx
    call    file_unlink
.skip:
    inc     rbx
    cmp     byte [rbx - 1], 0
    jne     .skip
    jmp     .left
.ret:
    pop     rbx
    ret

; find_entry(rdi name, esi mode or -1 for any, edx valid) -> eax index in world_list, or -1.
find_entry:
    xor     ecx, ecx
    mov     r8d, [world_count]
.l:
    cmp     ecx, r8d
    jae     .none
    mov     eax, ecx
    shl     rax, 7
    lea     r10, [world_list]
    add     r10, rax
    xor     r9d, r9d
.c:
    mov     al, [r10 + WORLDENTRY.name + r9]
    cmp     al, [rdi + r9]
    jne     .next
    test    al, al
    jz      .match
    inc     r9
    jmp     .c
.match:
    cmp     [r10 + WORLDENTRY.valid], edx
    jne     .next
    cmp     esi, -1
    je      .found
    cmp     [r10 + WORLDENTRY.mode], esi
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

; entry_file_is(edi idx, rsi expected) -> eax 1 if world_list[idx].file == expected
entry_file_is:
    push    rbp
    mov     rbp, rsp
    mov     eax, edi
    shl     rax, 7
    lea     rdi, [world_list + WORLDENTRY.file]
    add     rdi, rax
    call    str_eq
    pop     rbp
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
    call    clean_up
    lea     rdi, [w_alpha]
    lea     rsi, [n_alpha]
    xor     edx, edx
    call    make_world
    test    eax, eax
    jnz     .fail
    lea     rdi, [w_beta]
    lea     rsi, [n_beta]
    mov     edx, 1
    call    make_world
    test    eax, eax
    jnz     .fail
    ; Alpha exists, so a new "Alpha" becomes Alpha-2, made together with its regions/
    lea     rdi, [n_alpha]
    lea     rsi, [out_buf]
    call    saves_new_world_dir
    test    eax, eax
    jnz     .fail
    lea     rdi, [out_buf]
    lea     rsi, [w_alpha2]
    call    str_eq
    cmp     eax, 1
    jne     .fail
    lea     rdi, [w_alpha2_regions]
    call    file_stat_mtime
    test    rax, rax
    js      .fail
    ; scan: the two worlds with the right names and modes (Alpha-2 has no world.hdr yet: not a world)
    call    saves_scan
    cmp     eax, 2
    jne     .fail
    lea     rdi, [n_alpha]
    xor     esi, esi
    mov     edx, 1
    call    find_entry
    mov     ebx, eax
    test    ebx, ebx
    js      .fail
    lea     rdi, [n_beta]
    mov     esi, 1
    mov     edx, 1
    call    find_entry
    test    eax, eax
    js      .fail
    ; rename Alpha -> Gamma: the header's name changes, the directory keeps its name
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
    mov     edx, 1
    call    find_entry
    test    eax, eax
    js      .fail
    mov     edi, eax
    lea     rsi, [n_alpha]
    call    entry_file_is
    test    eax, eax
    jz      .fail
    lea     rdi, [n_alpha]
    mov     esi, -1
    mov     edx, 1
    call    find_entry
    cmp     eax, -1
    jne     .fail
    ; delete Beta: its whole directory goes
    lea     rdi, [n_beta]
    mov     esi, 1
    mov     edx, 1
    call    find_entry
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    saves_delete
    test    eax, eax
    jnz     .fail
    lea     rdi, [w_beta]
    call    file_stat_mtime
    test    rax, rax
    jns     .fail
    call    saves_scan
    cmp     eax, 1
    jne     .fail
    lea     rdi, [n_gamma]
    mov     esi, -1
    mov     edx, 1
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
    call    clean_up
    call    zero_header
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; A directory with a good world.hdr is a world (valid 1); a <stem>.acw file is a world of 0.8 or earlier
; (valid 2): listed, never renamed, never changed, deletable; a directory whose world.hdr has no good
; magic and a stray file are not listed; deleting a 0.9 world removes its directory and regions/ tree.
test_saves_old_world_incompatible:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    xor     edi, edi
    lea     rsi, [d_data]
    call    saves_init
    test    eax, eax
    jnz     .fail
    call    clean_up
    lea     rdi, [w_a]
    lea     rsi, [n_a]
    xor     edx, edx
    call    make_world
    test    eax, eax
    jnz     .fail
    lea     rdi, [file_buf]                 ; a region file in A/regions: the whole tree must go
    mov     ecx, 16
    mov     al, 0x33
    rep     stosb
    lea     rdi, [p_a_reg]
    lea     rsi, [file_buf]
    mov     edx, 16
    call    file_write_atomic
    test    eax, eax
    jnz     .fail
    lea     rdi, [dir_buf]                  ; Bad/world.hdr: 1024 bytes without the magic
    lea     rsi, [w_bad]
    mov     edx, 4000
    call    str_copy
    lea     rdi, [dir_buf]
    call    mkdir_p
    test    eax, eax
    jnz     .fail
    lea     rdi, [file_buf]
    mov     ecx, 1024
    xor     eax, eax
    rep     stosb
    lea     rdi, [p_bad_hdr]
    lea     rsi, [file_buf]
    mov     edx, 1024
    call    file_write_atomic
    test    eax, eax
    jnz     .fail
    lea     rdi, [file_buf]                 ; Old.acw: 64 bytes standing for a world of 0.8
    mov     ecx, 64
    mov     al, 0x5A
    rep     stosb
    mov     rax, "ACRAFT05"
    mov     [file_buf], rax
    lea     rdi, [p_old]
    lea     rsi, [file_buf]
    mov     edx, 64
    call    file_write_atomic
    test    eax, eax
    jnz     .fail
    lea     rdi, [p_note]                   ; note.txt: no world at all
    lea     rsi, [file_buf]
    mov     edx, 5
    call    file_write_atomic
    test    eax, eax
    jnz     .fail
    call    saves_scan                      ; A and Old; neither Bad nor note.txt
    cmp     eax, 2
    jne     .fail
    lea     rdi, [n_old]                    ; a new world named like a world of 0.8 gets the next name
    lea     rsi, [out_buf]
    call    saves_new_world_dir
    test    eax, eax
    jnz     .fail
    lea     rdi, [out_buf]
    lea     rsi, [w_old2]
    call    str_eq
    cmp     eax, 1
    jne     .fail
    lea     rdi, [n_a]
    mov     esi, -1
    mov     edx, 1
    call    find_entry
    test    eax, eax
    js      .fail
    lea     rdi, [n_old]
    mov     esi, -1
    mov     edx, 2
    call    find_entry
    mov     ebx, eax
    test    ebx, ebx
    js      .fail
    mov     edi, ebx
    lea     rsi, [f_old]
    call    entry_file_is
    test    eax, eax
    jz      .fail
    mov     edi, ebx                        ; a world of 0.8 is not renamed ...
    lea     rsi, [n_new]
    call    saves_rename
    cmp     eax, -1
    jne     .fail
    lea     rdi, [p_old]                    ; ... and its file is as it was
    lea     rsi, [read_buf]
    mov     edx, 128
    call    file_read
    cmp     rax, 64
    jne     .fail
    lea     rsi, [file_buf]
    lea     rdi, [read_buf]
    mov     ecx, 64
    repe cmpsb
    jne     .fail
    mov     edi, ebx                        ; deleting it removes the file only
    call    saves_delete
    test    eax, eax
    jnz     .fail
    lea     rdi, [p_old]
    call    file_stat_mtime
    test    rax, rax
    jns     .fail
    lea     rdi, [p_note]
    call    file_stat_mtime
    test    rax, rax
    js      .fail
    call    saves_scan                      ; the list is not updated by a delete: rescan
    cmp     eax, 1
    jne     .fail
    lea     rdi, [n_a]
    mov     esi, -1
    mov     edx, 1
    call    find_entry
    test    eax, eax
    js      .fail
    mov     edi, eax                        ; deleting A removes its directory and its regions/ tree
    call    saves_delete
    test    eax, eax
    jnz     .fail
    lea     rdi, [w_a]
    call    file_stat_mtime
    test    rax, rax
    jns     .fail
    lea     rdi, [p_a_reg]
    call    file_stat_mtime
    test    rax, rax
    jns     .fail
    call    saves_scan
    test    eax, eax
    jnz     .fail
    xor     ebx, ebx
    jmp     .done
.fail:
    mov     ebx, 1
.done:
    call    clean_up
    call    zero_header
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret
