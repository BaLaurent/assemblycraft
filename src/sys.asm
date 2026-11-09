; sys.asm - raw-syscall I/O and small string helpers (no libc).
%include "common.inc"
default rel

global sys_print, str_len, str_eq, parse_u32, i32_to_str, str_append
global file_read, file_write_atomic
global fnv1a, str_copy, f32_to_str, file_stat_mtime, file_patch, file_unlink, time_now
global time_mono, time_mono_ns, file_pread, mkdir_p, dir_remove_tree

section .rodata
tmp_suffix: db ".tmp", 0
align 8
d_half:     dq 0.5
d_ten:      dq 10.0
d_nano:     dq 1.0e-9
s_regions:  db "/regions", 0
s_players:  db "/players", 0

section .bss
tmp_path:   resb 4104
alignb 8
tm_base:    resq 1                      ; time_mono_ns epoch (ns of the first call)
tm_init:    resd 1

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

; fnv1a(rdi ptr, rsi len) -> eax  (FNV-1a 32-bit)
fnv1a:
    mov     eax, 2166136261
    test    rsi, rsi
    jz      .done
.loop:
    movzx   ecx, byte [rdi]
    xor     eax, ecx
    imul    eax, eax, 16777619
    inc     rdi
    dec     rsi
    jnz     .loop
.done:
    ret

; str_copy(rdi dst, rsi src, rdx max) -> rax end (points at the written NUL).
; Copies at most max chars, then writes a NUL.
str_copy:
    xor     ecx, ecx
.loop:
    cmp     rcx, rdx
    jae     .done
    mov     al, [rsi + rcx]
    test    al, al
    jz      .done
    mov     [rdi + rcx], al
    inc     rcx
    jmp     .loop
.done:
    lea     rax, [rdi + rcx]
    mov     byte [rax], 0
    ret

; f32_to_str(xmm0 v, rdi buf, esi decimals) -> rax end (no NUL).
; Signed fixed-point text, rounding half away from zero. No '-' when it rounds to 0.
f32_to_str:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi                    ; out cursor
    mov     r12d, esi                   ; decimals
    cvtss2sd xmm0, xmm0
    xor     r14d, r14d                  ; negative?
    xorpd   xmm1, xmm1
    comisd  xmm0, xmm1
    jae     .pos
    mov     r14d, 1
    subsd   xmm1, xmm0
    movapd  xmm0, xmm1                  ; |v|
.pos:
    mov     r13d, 1                     ; scale = 10^decimals
    mov     ecx, r12d
.scale:
    test    ecx, ecx
    jz      .scaled
    imul    r13, r13, 10
    mulsd   xmm0, [d_ten]
    dec     ecx
    jmp     .scale
.scaled:
    addsd   xmm0, [d_half]
    cvttsd2si rax, xmm0                 ; n = round(|v| * scale)
    test    rax, rax
    jz      .no_sign
    test    r14d, r14d
    jz      .no_sign
    mov     byte [rbx], '-'
    inc     rbx
.no_sign:
    xor     edx, edx
    div     r13                         ; rax = int part, rdx = fraction
    mov     r14, rdx
    mov     edi, eax
    mov     rsi, rbx
    call    i32_to_str
    mov     rbx, rax
    test    r12d, r12d
    jz      .done
    mov     byte [rbx], '.'
    inc     rbx
    mov     ecx, r12d                   ; write the fraction right to left, zero padded
    mov     rax, r14
    mov     r8d, 10
.frac:
    dec     ecx
    xor     edx, edx
    div     r8
    add     dl, '0'
    mov     [rbx + rcx], dl
    test    ecx, ecx
    jnz     .frac
    add     rbx, r12
.done:
    mov     rax, rbx
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; file_stat_mtime(rdi path) -> rax mtime seconds or -errno
file_stat_mtime:
    sub     rsp, 152
    mov     eax, SYS_STAT
    mov     rsi, rsp
    syscall
    test    rax, rax
    js      .ret
    mov     rax, [rsp + 88]             ; st_mtime
.ret:
    add     rsp, 152
    ret

; file_patch(rdi path, rsi offset, rdx buf, rcx len) -> eax 0 / -errno.
; Overwrites len bytes at offset of an existing file.
file_patch:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rsi                    ; offset
    mov     r13, rdx                    ; buf
    mov     r14, rcx                    ; remaining
    mov     eax, SYS_OPEN
    mov     esi, O_WRONLY
    xor     edx, edx
    syscall
    test    rax, rax
    js      .ret
    mov     rbx, rax
    xor     r15d, r15d                  ; result
.loop:
    test    r14, r14
    jz      .close
    mov     eax, SYS_PWRITE64
    mov     rdi, rbx
    mov     rsi, r13
    mov     rdx, r14
    mov     r10, r12
    syscall
    cmp     rax, -EINTR
    je      .loop
    test    rax, rax
    js      .err
    jz      .eio
    add     r13, rax
    add     r12, rax
    sub     r14, rax
    jmp     .loop
.eio:
    mov     rax, -5
.err:
    mov     r15, rax
.close:
    mov     eax, SYS_CLOSE
    mov     rdi, rbx
    syscall
    test    r15, r15
    jnz     .res
    test    rax, rax
    js      .ret
.res:
    mov     rax, r15
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; file_unlink(rdi path) -> eax 0 / -errno
file_unlink:
    mov     eax, SYS_UNLINK
    syscall
    ret

; time_now() -> rax epoch seconds
time_now:
    mov     eax, SYS_TIME
    xor     edi, edi
    syscall
    ret

; time_mono_ns() -> rax nanoseconds on CLOCK_MONOTONIC since the first call (that call returns 0).
; Clobbers rcx, rdx, rsi, rdi, r11. Main thread only (the epoch is taken lazily).
time_mono_ns:
    sub     rsp, 24
    mov     eax, SYS_CLOCK_GETTIME
    mov     edi, CLOCK_MONOTONIC
    mov     rsi, rsp
    syscall
    mov     rax, [rsp]
    imul    rax, rax, 1000000000
    add     rax, [rsp + 8]
    add     rsp, 24
    cmp     dword [tm_init], 0
    jne     .have
    mov     [tm_base], rax
    mov     dword [tm_init], 1
.have:
    sub     rax, [tm_base]
    ret

; time_mono() -> xmm0 float seconds since the first call. float32 keeps ~0.5 ms after an hour; code
; that measures short budgets over long runs uses time_mono_ns instead.
time_mono:
    sub     rsp, 8
    call    time_mono_ns
    cvtsi2sd xmm0, rax
    mulsd   xmm0, [d_nano]
    cvtsd2ss xmm0, xmm0
    add     rsp, 8
    ret

; file_pread(rdi path, rsi buf, rdx len, rcx offset) -> rax bytes read or -errno.
; Reads up to len bytes at offset (fewer at end of file); open errors come back as -errno.
file_pread:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rsi                    ; buf
    mov     r13, rdx                    ; len
    mov     r15, rcx                    ; offset
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
    mov     eax, SYS_PREAD64
    mov     rdi, rbx
    lea     rsi, [r12 + r14]
    mov     rdx, r13
    sub     rdx, r14
    lea     r10, [r15 + r14]
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
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; mkdir_p(rdi path, writable) -> eax 0 or the first -errno other than -EEXIST.
; Creates every prefix of the path (mode 0755). The path buffer is written to (a '/' is replaced
; by NUL while its prefix is made) and restored.
mkdir_p:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    xor     r12d, r12d                  ; first error
    mov     r13d, 1                     ; index (skip a leading '/')
.scan:
    mov     al, [rbx + r13]
    test    al, al
    jz      .final
    cmp     al, '/'
    jne     .adv
    mov     byte [rbx + r13], 0
    mov     eax, SYS_MKDIR
    mov     rdi, rbx
    mov     esi, 493                    ; 0755
    syscall
    mov     byte [rbx + r13], '/'
    test    rax, rax
    jz      .adv
    cmp     rax, -EEXIST
    je      .adv
    test    r12, r12
    jnz     .adv
    mov     r12, rax
.adv:
    inc     r13
    jmp     .scan
.final:
    mov     eax, SYS_MKDIR
    mov     rdi, rbx
    mov     esi, 493
    syscall
    test    rax, rax
    jz      .done
    cmp     rax, -EEXIST
    je      .done
    test    r12, r12
    jnz     .done
    mov     r12, rax
.done:
    mov     eax, r12d
    pop     r13
    pop     r12
    pop     rbx
    ret

; rmdir_flat(rdi dir) -> rax 0 / -errno (the first error).
; Unlinks every entry of dir (a subdirectory entry fails with its errno, nothing recurses), then
; removes dir itself. -ENOENT when dir does not exist.
rmdir_flat:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8192 + 4104 + 8        ; getdents buffer | entry path | alignment
    mov     r12, rdi                    ; dir
    xor     r15d, r15d                  ; first error
    call    str_len
    cmp     rax, 3800
    jbe     .open
    mov     rax, -ENAMETOOLONG
    jmp     .out
.open:
    mov     eax, SYS_OPEN
    mov     rdi, r12
    mov     esi, O_RDONLY | O_DIRECTORY
    xor     edx, edx
    syscall
    test    rax, rax
    js      .out                        ; -errno (rax)
    mov     rbx, rax                    ; fd
.prefix:
    lea     rdi, [rsp + 8192]
    mov     rsi, r12
    call    str_append
    mov     byte [rax], '/'
    inc     rax
    mov     r14, rax                    ; names are appended here
.batch:
    mov     eax, SYS_GETDENTS64
    mov     rdi, rbx
    mov     rsi, rsp
    mov     edx, 8192
    syscall
    test    rax, rax
    jz      .done                       ; end of the directory
    js      .readerr
    mov     r13, rax                    ; bytes in this batch
    xor     r8d, r8d                    ; offset of the current dirent
.entry:
    cmp     r8, r13
    jae     .batch
    lea     r9, [rsp + r8]
    movzx   eax, word [r9 + 16]         ; d_reclen
    add     r8, rax
    lea     rsi, [r9 + 19]              ; d_name
    cmp     byte [rsi], '.'
    jne     .real
    cmp     byte [rsi + 1], 0
    je      .entry                      ; "."
    cmp     byte [rsi + 1], '.'
    jne     .real
    cmp     byte [rsi + 2], 0
    je      .entry                      ; ".."
.real:
    mov     rdi, r14
    call    str_append
    mov     byte [rax], 0
    mov     eax, SYS_UNLINK
    lea     rdi, [rsp + 8192]
    syscall
    test    rax, rax
    jz      .entry
    test    r15, r15
    jnz     .entry
    mov     r15, rax
    jmp     .entry
.readerr:
    test    r15, r15
    jnz     .done
    mov     r15, rax
.done:
    mov     eax, SYS_CLOSE
    mov     rdi, rbx
    syscall
    mov     eax, SYS_RMDIR
    mov     rdi, r12
    syscall
    test    rax, rax
    jz      .fin
    test    r15, r15
    jnz     .fin
    mov     r15, rax
.fin:
    mov     rax, r15
.out:
    add     rsp, 8192 + 4104 + 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; dir_remove_tree(rdi path) -> eax 0 / -errno (the first error).
; Removes a world directory: every entry of path/regions, that directory, every entry of path/players (the
; characters a hosted world keeps for its guests), that directory, every file of path, then path itself. One
; level of subdirectory only; -ENOENT when path does not exist.
; rbx = the first error of the subdirectories (0 when none; a missing one is not an error)
dir_remove_tree:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 4104
    mov     r12, rdi
    call    str_len
    cmp     rax, 3700
    jbe     .ok
    mov     eax, -ENAMETOOLONG
    jmp     .out
.ok:
    mov     rdi, rsp
    mov     rsi, r12
    call    str_append
    mov     rdi, rax
    lea     rsi, [s_regions]
    call    str_append
    mov     byte [rax], 0
    mov     rdi, rsp
    call    rmdir_flat                  ; regions first; no regions directory is fine
    mov     rbx, rax
    cmp     rbx, -ENOENT
    jne     .players
    xor     ebx, ebx
.players:
    mov     rdi, rsp
    mov     rsi, r12
    call    str_append
    mov     rdi, rax
    lea     rsi, [s_players]
    call    str_append
    mov     byte [rax], 0
    mov     rdi, rsp
    call    rmdir_flat                  ; then the guests' characters; a world never hosted has none
    cmp     rax, -ENOENT
    je      .top
    test    rbx, rbx
    jnz     .top
    mov     rbx, rax
.top:
    mov     rdi, r12
    call    rmdir_flat
    test    rbx, rbx
    jnz     .res
    mov     rbx, rax
.res:
    mov     eax, ebx
.out:
    add     rsp, 4104
    pop     r12
    pop     rbx
    pop     rbp
    ret
