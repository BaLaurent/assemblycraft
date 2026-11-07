; sys.asm - raw-syscall I/O and small string helpers (no libc).
%include "common.inc"
default rel

global sys_print, str_len, str_eq, parse_u32, i32_to_str, str_append
global file_read, file_write_atomic

section .rodata
tmp_suffix: db ".tmp", 0

section .bss
tmp_path:   resb 4104

section .text

; str_len(rdi zstr) -> rax
str_len:
    xor     eax, eax
.loop:
    cmp     byte [rdi + rax], 0
    je      .done
    inc     rax
    jmp     .loop
.done:
    ret

; str_eq(rdi a, rsi b) -> eax 1 if equal, 0 otherwise
str_eq:
    xor     ecx, ecx
.loop:
    movzx   eax, byte [rdi + rcx]
    movzx   edx, byte [rsi + rcx]
    cmp     eax, edx
    jne     .ne
    test    eax, eax
    jz      .eq
    inc     rcx
    jmp     .loop
.eq:
    mov     eax, 1
    ret
.ne:
    xor     eax, eax
    ret

; parse_u32(rdi zstr, rsi u32* out) -> eax 1 ok / 0 bad (empty, non-digit, > 4294967295)
parse_u32:
    movzx   ecx, byte [rdi]
    test    ecx, ecx
    jz      .bad
    xor     eax, eax                    ; accumulator (64-bit)
    mov     r8d, 0xFFFFFFFF
.loop:
    movzx   ecx, byte [rdi]
    test    ecx, ecx
    jz      .ok
    sub     ecx, '0'
    cmp     ecx, 9
    ja      .bad
    imul    rax, rax, 10
    add     rax, rcx
    cmp     rax, r8
    ja      .bad
    inc     rdi
    jmp     .loop
.ok:
    mov     [rsi], eax
    mov     eax, 1
    ret
.bad:
    xor     eax, eax
    ret

; i32_to_str(edi value, rsi buf) -> rax past last char (no NUL)
i32_to_str:
    movsxd  rax, edi
    test    rax, rax
    jns     .pos
    mov     byte [rsi], '-'
    inc     rsi
    neg     rax
.pos:
    sub     rsp, 24                     ; digit scratch (leaf)
    xor     ecx, ecx
    mov     r8d, 10
.digits:
    xor     edx, edx
    div     r8
    add     dl, '0'
    mov     [rsp + rcx], dl
    inc     ecx
    test    rax, rax
    jnz     .digits
.copy:
    dec     ecx
    mov     dl, [rsp + rcx]
    mov     [rsi], dl
    inc     rsi
    test    ecx, ecx
    jnz     .copy
    add     rsp, 24
    mov     rax, rsi
    ret

; str_append(rdi dst_end, rsi zstr) -> rax new end (no NUL)
str_append:
.loop:
    mov     al, [rsi]
    test    al, al
    jz      .done
    mov     [rdi], al
    inc     rdi
    inc     rsi
    jmp     .loop
.done:
    mov     rax, rdi
    ret

; sys_print(edi fd, rsi zstr): write the whole string, retrying partial writes
sys_print:
    push    rbx
    push    r12
    push    r13
    mov     r12d, edi
    mov     rbx, rsi
    mov     rdi, rsi
    call    str_len
    mov     r13, rax
.loop:
    test    r13, r13
    jz      .done
    mov     eax, SYS_WRITE
    mov     edi, r12d
    mov     rsi, rbx
    mov     rdx, r13
    syscall
    cmp     rax, -EINTR
    je      .loop
    test    rax, rax
    jle     .done
    add     rbx, rax
    sub     r13, rax
    jmp     .loop
.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; file_read(rdi path, rsi buf, rdx cap) -> rax bytes read or -errno
file_read:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rsi                    ; buf
    mov     r13, rdx                    ; cap
    xor     r14d, r14d                  ; total
    mov     eax, SYS_OPEN
    mov     esi, O_RDONLY
    xor     edx, edx
    syscall
    test    rax, rax
    js      .ret
    mov     rbx, rax                    ; fd
.loop:
    cmp     r14, r13
    jae     .close
    mov     eax, SYS_READ
    mov     rdi, rbx
    lea     rsi, [r12 + r14]
    mov     rdx, r13
    sub     rdx, r14
    syscall
    cmp     rax, -EINTR
    je      .loop
    test    rax, rax
    js      .fail
    jz      .close
    add     r14, rax
    jmp     .loop
.fail:
    mov     r14, rax                    ; -errno
.close:
    mov     eax, SYS_CLOSE
    mov     rdi, rbx
    syscall
    mov     rax, r14
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; file_write_atomic(rdi path, rsi buf, rdx len) -> eax 0 or -errno
; Writes path+".tmp", closes it, renames it onto path; unlinks the tmp on failure.
file_write_atomic:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi                    ; path
    mov     r13, rsi                    ; buf
    mov     r14, rdx                    ; remaining
    call    str_len
    cmp     rax, 4000
    ja      .toolong
    lea     rdi, [tmp_path]
    mov     rsi, r12
    call    str_append
    mov     rdi, rax
    lea     rsi, [tmp_suffix]
    call    str_append
    mov     byte [rax], 0

    mov     eax, SYS_OPEN
    lea     rdi, [tmp_path]
    mov     esi, O_WCT
    mov     edx, MODE_644
    syscall
    test    rax, rax
    js      .ret
    mov     rbx, rax                    ; fd
.wloop:
    test    r14, r14
    jz      .close
    mov     eax, SYS_WRITE
    mov     rdi, rbx
    mov     rsi, r13
    mov     rdx, r14
    syscall
    cmp     rax, -EINTR
    je      .wloop
    test    rax, rax
    js      .werr
    jz      .wzero
    add     r13, rax
    sub     r14, rax
    jmp     .wloop
.wzero:
    mov     rax, -5                     ; -EIO: write made no progress
.werr:
    mov     r15, rax
    mov     eax, SYS_CLOSE
    mov     rdi, rbx
    syscall
    jmp     .unlink
.close:
    mov     eax, SYS_CLOSE
    mov     rdi, rbx
    syscall
    test    rax, rax
    js      .err
    mov     eax, SYS_RENAME
    lea     rdi, [tmp_path]
    mov     rsi, r12
    syscall
    test    rax, rax
    js      .err
    xor     eax, eax
    jmp     .ret
.err:
    mov     r15, rax
.unlink:
    mov     eax, SYS_UNLINK
    lea     rdi, [tmp_path]
    syscall
    mov     rax, r15
    jmp     .ret
.toolong:
    mov     eax, -ENAMETOOLONG
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
