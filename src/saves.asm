; saves.asm - data directory, world list (scan, create, rename, delete over 0.9 world directories; worlds
; of 0.8 and earlier are listed but never opened) and file-name helpers.
%include "common.inc"
default rel

global data_dir, worlds_dir, settings_path, world_list, world_count
global saves_init, saves_scan, saves_entry_path, saves_name_to_file
global saves_new_world_dir, saves_delete, saves_rename, fmt_ago

extern str_len, str_copy, str_append, i32_to_str
extern file_read, file_stat_mtime, file_patch, file_unlink, time_now
extern mkdir_p, dir_remove_tree

%define MAX_WORLDS  64
%define DIR_MAX     3800                ; longest base dir; keeps every derived path < 4096
%define DENTS_SIZE  32768

section .rodata
s_xdg:      db "XDG_DATA_HOME=", 0
s_home:     db "HOME=", 0
s_xdg_sub:  db "/assemblycraft", 0
s_home_sub: db "/.local/share/assemblycraft", 0
s_fallback: db "./assemblycraft-data", 0
s_worlds:   db "/worlds", 0
s_cfg:      db "/settings.cfg", 0
s_ext:      db ".acw", 0
s_just_now: db "just now", 0
s_min:      db " min ago", 0
s_hour:     db " h ago", 0
s_day:      db " day ago", 0
s_days:     db " days ago", 0
m_v6:       db "ACRAFT06"
s_hdr_name: db "/world.hdr", 0
s_regions:  db "/regions", 0

section .bss
align 8
data_dir:      resb 4096
worlds_dir:    resb 4096
settings_path: resb 4096
world_list:    resb MAX_WORLDS * WORLDENTRY_size
world_count:   resd 1
alignb 8
dents:         resb DENTS_SIZE
path_buf:      resb 4200
tmp_entry:     resb WORLDENTRY_size
hdr_buf:       resb 1024               ; the header fields a listing reads (name, mode, seed, cheater mark)
name_buf:      resb 40

section .text

; env_get(rdi envp, rsi name incl. '=') -> rax pointer to the value, or 0
env_get:
    test    rdi, rdi
    jz      .none
.entry:
    mov     rdx, [rdi]
    test    rdx, rdx
    jz      .none
    xor     ecx, ecx
.cmp:
    mov     al, [rsi + rcx]
    test    al, al
    jz      .match
    cmp     al, [rdx + rcx]
    jne     .next
    inc     rcx
    jmp     .cmp
.match:
    lea     rax, [rdx + rcx]
    ret
.next:
    add     rdi, 8
    jmp     .entry
.none:
    xor     eax, eax
    ret

; saves_init(rdi envp or 0, rsi override_dir or 0) -> eax 0 / -errno
; Picks the base dir (override, $XDG_DATA_HOME/assemblycraft, $HOME/.local/share/assemblycraft,
; ./assemblycraft-data), creates base and base/worlds, fills the three path buffers.
saves_init:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    mov     rbx, rdi                    ; envp
    mov     r12, rsi                    ; override
    test    r12, r12
    jz      .env
    lea     rdi, [data_dir]
    mov     rsi, r12
    mov     edx, DIR_MAX
    call    str_copy
    jmp     .base_done
.env:
    mov     rdi, rbx
    lea     rsi, [s_xdg]
    call    env_get
    test    rax, rax
    jz      .home
    cmp     byte [rax], 0
    je      .home
    lea     rdi, [data_dir]
    mov     rsi, rax
    mov     edx, DIR_MAX
    call    str_copy
    mov     rdi, rax
    lea     rsi, [s_xdg_sub]
    call    str_append
    mov     byte [rax], 0
    jmp     .base_done
.home:
    mov     rdi, rbx
    lea     rsi, [s_home]
    call    env_get
    test    rax, rax
    jz      .fallback
    cmp     byte [rax], 0
    je      .fallback
    lea     rdi, [data_dir]
    mov     rsi, rax
    mov     edx, DIR_MAX
    call    str_copy
    mov     rdi, rax
    lea     rsi, [s_home_sub]
    call    str_append
    mov     byte [rax], 0
    jmp     .base_done
.fallback:
    lea     rdi, [data_dir]
    lea     rsi, [s_fallback]
    mov     edx, DIR_MAX
    call    str_copy
.base_done:
    lea     rdi, [worlds_dir]
    lea     rsi, [data_dir]
    mov     edx, 4000
    call    str_copy
    mov     rdi, rax
    lea     rsi, [s_worlds]
    call    str_append
    mov     byte [rax], 0
    lea     rdi, [settings_path]
    lea     rsi, [data_dir]
    mov     edx, 4000
    call    str_copy
    mov     rdi, rax
    lea     rsi, [s_cfg]
    call    str_append
    mov     byte [rax], 0
    lea     rdi, [worlds_dir]           ; creates every prefix of base too
    call    mkdir_p
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; stat_info(rdi path) -> rax mtime seconds or -errno, edx st_mode (valid when rax >= 0); follows links
stat_info:
    sub     rsp, 152
    mov     eax, SYS_STAT
    mov     rsi, rsp
    syscall
    test    rax, rax
    js      .ret
    mov     edx, [rsp + 24]             ; st_mode
    mov     rax, [rsp + 88]             ; st_mtime
.ret:
    add     rsp, 152
    ret

; add_entry(rdi dirent name, esi count, edx d_type) -> eax 1 if a world entry was inserted into
; world_list (kept sorted newest first), else 0. A directory whose world.hdr starts with a good 0.9
; header is a world (valid 1, and WORLDENTRY.cheater 1 when the header carries the cheater mark); a
; regular <stem>.acw file is a world of 0.8 or earlier (valid 2: listed, never opened); nothing else is
; listed. A type the dirent does not settle (DT_UNKNOWN, a link) is looked up with stat.
add_entry:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 16                     ; [rsp] end of the path in path_buf
    mov     rbx, rdi                    ; name
    mov     r12d, esi                   ; count
    mov     r14d, edx                   ; d_type
    cmp     byte [rbx], '.'
    jne     .named
    cmp     byte [rbx + 1], 0
    je      .skip                       ; "."
    cmp     word [rbx + 1], '.'
    je      .skip                       ; ".." (the bytes '.', 0)
.named:
    mov     rdi, rbx
    call    str_len
    test    rax, rax
    jz      .skip
    cmp     rax, 63
    ja      .skip                       ; WORLDENTRY.file holds 63 characters
    mov     r13, rax                    ; name length
    lea     rdi, [path_buf]             ; path = worlds_dir/name
    lea     rsi, [worlds_dir]
    mov     edx, 4000
    call    str_copy
    mov     byte [rax], '/'
    lea     rdi, [rax + 1]
    mov     rsi, rbx
    call    str_append
    mov     byte [rax], 0
    mov     [rsp], rax
    lea     rdi, [tmp_entry]
    xor     eax, eax
    mov     ecx, WORLDENTRY_size / 8
    rep     stosq
    lea     rdi, [tmp_entry + WORLDENTRY.file]
    mov     rsi, rbx
    mov     edx, 63
    call    str_copy
    cmp     r14d, DT_DIR
    je      .dir
    cmp     r14d, DT_REG
    je      .file
    lea     rdi, [path_buf]             ; anything else: stat decides
    call    stat_info
    test    rax, rax
    js      .skip
    and     edx, 0xF000
    cmp     edx, 0x4000
    je      .dir
    cmp     edx, 0x8000
    jne     .skip
.file:
    cmp     r13, 4
    jbe     .skip
    cmp     dword [rbx + r13 - 4], 0x7763612E   ; ".acw"
    jne     .skip
    lea     rdi, [path_buf]
    call    stat_info
    test    rax, rax
    js      .skip
    mov     [tmp_entry + WORLDENTRY.mtime], rax
    mov     dword [tmp_entry + WORLDENTRY.valid], 2
    lea     rdi, [tmp_entry + WORLDENTRY.name]  ; its name is the file stem (<= 32 chars)
    mov     rsi, rbx
    lea     rdx, [r13 - 4]
    cmp     rdx, 32
    jbe     .stem
    mov     edx, 32
.stem:
    call    str_copy
    jmp     .insert
.dir:
    mov     rdi, [rsp]                  ; <dir>/world.hdr: a world only with a readable 0.9 header
    lea     rsi, [s_hdr_name]
    call    str_append
    mov     byte [rax], 0
    lea     rdi, [path_buf]
    call    stat_info
    test    rax, rax
    js      .skip
    mov     [tmp_entry + WORLDENTRY.mtime], rax
    lea     rdi, [path_buf]
    lea     rsi, [hdr_buf]
    mov     edx, 1024
    call    file_read
    cmp     rax, 1024
    jl      .skip
    mov     rdx, [hdr_buf]
    cmp     rdx, [m_v6]
    jne     .skip
    mov     eax, [hdr_buf + WORLDHDR.mode]
    cmp     eax, MODE_CREATIVE
    ja      .skip                       ; garbage mode: not a world
    mov     [tmp_entry + WORLDENTRY.mode], eax
    mov     eax, [hdr_buf + WORLDHDR.seed]
    mov     [tmp_entry + WORLDENTRY.seed], eax
    mov     dword [tmp_entry + WORLDENTRY.valid], 1
    xor     eax, eax                    ; the cheater mark: the debug menu was opened in this world
    cmp     byte [hdr_buf + WORLDHDR.cheater], 0
    setne   al
    mov     [tmp_entry + WORLDENTRY.cheater], eax
    lea     rdi, [tmp_entry + WORLDENTRY.name]  ; the header's name, else the directory's
    lea     rsi, [hdr_buf + WORLDHDR.name]
    cmp     byte [rsi], 0
    jne     .have_name
    mov     rsi, rbx
.have_name:
    mov     edx, 32
    call    str_copy
.insert:
    mov     rax, [tmp_entry + WORLDENTRY.mtime]
    lea     rdi, [world_list]
    xor     r13d, r13d                  ; j = first index with an older mtime
.find:
    cmp     r13d, r12d
    jae     .found
    mov     edx, r13d
    shl     rdx, 7
    cmp     [rdi + rdx + WORLDENTRY.mtime], rax
    jl      .found
    inc     r13d
    jmp     .find
.found:
    mov     edx, r12d                   ; shift entries j..count-1 up one slot
.shift:
    cmp     edx, r13d
    jbe     .place
    mov     eax, edx
    shl     rax, 7
    lea     rdi, [world_list]
    add     rdi, rax
    lea     rsi, [rdi - WORLDENTRY_size]
    mov     ecx, WORLDENTRY_size / 8
    rep     movsq
    dec     edx
    jmp     .shift
.place:
    mov     eax, r13d
    shl     rax, 7
    lea     rdi, [world_list]
    add     rdi, rax
    lea     rsi, [tmp_entry]
    mov     ecx, WORLDENTRY_size / 8
    rep     movsq
    mov     eax, 1
    jmp     .ret
.skip:
    xor     eax, eax
.ret:
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; saves_scan() -> eax number of worlds found (also in world_count)
saves_scan:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     dword [world_count], 0
    xor     r14d, r14d                  ; count
    mov     eax, SYS_OPEN
    lea     rdi, [worlds_dir]
    mov     esi, O_RDONLY | O_DIRECTORY
    xor     edx, edx
    syscall
    test    rax, rax
    js      .done
    mov     rbx, rax                    ; fd
.read:
    mov     eax, SYS_GETDENTS64
    mov     rdi, rbx
    lea     rsi, [dents]
    mov     edx, DENTS_SIZE
    syscall
    cmp     rax, -EINTR
    je      .read
    test    rax, rax
    jle     .close
    mov     r13, rax                    ; bytes in buffer
    xor     r12d, r12d                  ; offset
.ent:
    cmp     r12, r13
    jae     .read
    lea     r15, [dents]
    add     r15, r12
    movzx   eax, word [r15 + 16]        ; d_reclen
    test    eax, eax
    jz      .close
    add     r12, rax
    cmp     r14d, MAX_WORLDS
    jae     .close
    lea     rdi, [r15 + 19]             ; d_name
    mov     esi, r14d
    movzx   edx, byte [r15 + 18]        ; d_type
    call    add_entry
    add     r14d, eax
    jmp     .ent
.close:
    mov     eax, SYS_CLOSE
    mov     rdi, rbx
    syscall
.done:
    mov     [world_count], r14d
    mov     eax, r14d
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; saves_entry_path(edi idx, rsi out): out = worlds_dir/<file>, NUL-terminated (out >= 4096 bytes)
saves_entry_path:
    push    rbx
    push    r12
    sub     rsp, 8
    mov     rbx, rsi
    cmp     edi, MAX_WORLDS
    jae     .empty
    mov     eax, edi
    shl     rax, 7
    lea     r12, [world_list + WORLDENTRY.file]
    add     r12, rax
    mov     rdi, rbx
    lea     rsi, [worlds_dir]
    mov     edx, 4000
    call    str_copy
    mov     byte [rax], '/'
    lea     rdi, [rax + 1]
    mov     rsi, r12
    call    str_append
    mov     byte [rax], 0
    jmp     .ret
.empty:
    mov     byte [rbx], 0
.ret:
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; saves_name_to_file(rdi name, rsi out) -> rax end (no NUL)
; Trims spaces, keeps [A-Za-z0-9_-], maps space to '_', drops the rest; <= 40 chars; empty -> "World".
saves_name_to_file:
.lead:
    cmp     byte [rdi], ' '
    jne     .lead_done
    inc     rdi
    jmp     .lead
.lead_done:
    mov     rdx, rdi
.end:
    cmp     byte [rdx], 0
    je      .end_done
    inc     rdx
    jmp     .end
.end_done:
.trail:
    cmp     rdx, rdi
    jbe     .trail_done
    cmp     byte [rdx - 1], ' '
    jne     .trail_done
    dec     rdx
    jmp     .trail
.trail_done:
    mov     r8, rsi                     ; out start
.loop:
    cmp     rdi, rdx
    jae     .mapped
    movzx   eax, byte [rdi]
    inc     rdi
    cmp     al, ' '
    je      .space
    cmp     al, '_'
    je      .keep
    cmp     al, '-'
    je      .keep
    mov     ecx, eax
    sub     ecx, '0'
    cmp     ecx, 9
    jbe     .keep
    mov     ecx, eax
    or      ecx, 0x20
    sub     ecx, 'a'
    cmp     ecx, 25
    jbe     .keep
    jmp     .loop
.space:
    mov     al, '_'
.keep:
    mov     [rsi], al
    inc     rsi
    mov     rcx, rsi
    sub     rcx, r8
    cmp     rcx, 40
    jb      .loop
.mapped:
    cmp     rsi, r8
    jne     .ret
    mov     dword [rsi], 'Worl'
    mov     byte [rsi + 4], 'd'
    add     rsi, 5
.ret:
    mov     rax, rsi
    ret

; saves_new_world_dir(rdi name, rsi out) -> eax 0 / -1 (<stem>, <stem>-2 .. <stem>-99 are all taken) /
; -errno (the directory could not be made)
; out = worlds_dir/<stem>[-N]: a name that is neither a directory nor a world of 0.8 or earlier
; (<stem>[-N].acw); the directory is made together with its regions/ directory.
saves_new_world_dir:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12, rsi
    mov     rdi, r12
    lea     rsi, [worlds_dir]
    mov     edx, 4000
    call    str_copy
    mov     byte [rax], '/'
    lea     rsi, [rax + 1]
    mov     rdi, rbx
    call    saves_name_to_file
    mov     r13, rax                    ; end of the stem
    xor     ebx, ebx                    ; 0, then the suffixes 2 .. 99
.try:
    mov     r14, r13
    test    ebx, ebx
    jz      .name_ok
    cmp     ebx, 99
    ja      .full
    mov     byte [r13], '-'
    lea     rsi, [r13 + 1]
    mov     edi, ebx
    call    i32_to_str
    mov     r14, rax                    ; end of the candidate
.name_ok:
    mov     byte [r14], 0
    mov     rdi, r12                    ; taken as a directory ...
    call    file_stat_mtime
    test    rax, rax
    jns     .taken
    mov     rdi, r14                    ; ... or as a world of 0.8 or earlier
    lea     rsi, [s_ext]
    call    str_append
    mov     byte [rax], 0
    mov     rdi, r12
    call    file_stat_mtime
    mov     byte [r14], 0               ; the extension off again
    test    rax, rax
    jns     .taken
    mov     rdi, r12                    ; free: make it and its regions/
    call    mkdir_p
    test    eax, eax
    jnz     .ret
    mov     rdi, r14
    lea     rsi, [s_regions]
    call    str_append
    mov     byte [rax], 0
    mov     rdi, r12
    call    mkdir_p
    mov     byte [r14], 0
    jmp     .ret                        ; 0, or the -errno of regions/
.taken:
    inc     ebx
    cmp     ebx, 2
    jae     .try
    mov     ebx, 2
    jmp     .try
.full:
    mov     eax, -1
.ret:
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; saves_delete(edi idx) -> eax 0 / -errno (-1 for a bad index or an entry that is not valid 1 or 2)
; A 0.9 world goes with its whole directory (dir_remove_tree), a world of 0.8 or earlier is one file.
; The list is not updated: rescan.
saves_delete:
    push    rbx
    push    r12
    sub     rsp, 8
    mov     r12d, edi
    cmp     edi, [world_count]
    jae     .bad
    mov     eax, edi
    shl     rax, 7
    lea     rcx, [world_list]
    mov     ebx, [rcx + rax + WORLDENTRY.valid]
    cmp     ebx, 1
    je      .path
    cmp     ebx, 2
    jne     .bad
.path:
    mov     edi, r12d
    lea     rsi, [path_buf]
    call    saves_entry_path
    lea     rdi, [path_buf]
    cmp     ebx, 1
    jne     .file
    call    dir_remove_tree
    jmp     .ret
.file:
    call    file_unlink
    jmp     .ret
.bad:
    mov     eax, -1
.ret:
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; saves_rename(edi idx, rsi new_name) -> eax 0 / -errno / -1 (the entry is not a valid 0.9 world).
; Patches the 33-byte name field of <dir>/world.hdr in place.
saves_rename:
    push    rbx
    push    r12
    push    r13
    cmp     edi, [world_count]
    jae     .bad
    mov     eax, edi
    shl     rax, 7
    lea     rbx, [world_list]
    add     rbx, rax                    ; entry
    cmp     dword [rbx + WORLDENTRY.valid], 1
    jne     .bad
    cmp     dword [rbx + WORLDENTRY.mode], MODE_CREATIVE
    ja      .bad
    mov     r12, rsi
    mov     r13d, edi
    lea     rdi, [name_buf]
    xor     eax, eax
    mov     ecx, 33
    rep     stosb
    lea     rdi, [name_buf]
    mov     rsi, r12
    mov     edx, 32
    call    str_copy
    mov     edi, r13d
    lea     rsi, [path_buf]
    call    saves_entry_path
    lea     rdi, [path_buf]
    call    str_len
    lea     rdi, [path_buf]
    add     rdi, rax
    lea     rsi, [s_hdr_name]
    call    str_append
    mov     byte [rax], 0
    lea     rdi, [path_buf]
    mov     esi, WORLDHDR.name
    lea     rdx, [name_buf]
    mov     ecx, 33
    call    file_patch
    test    eax, eax
    jnz     .ret
    lea     rdi, [rbx + WORLDENTRY.name]    ; keep the cached entry in sync
    lea     rsi, [name_buf]
    mov     edx, 32
    call    str_copy
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, -1
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; fmt_ago(rdi out, rsi mtime) -> rax end (points at the written NUL)
; "just now", "N min ago", "N h ago", "N day(s) ago".
fmt_ago:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    call    time_now
    sub     rax, r12
    jns     .nonneg
    xor     eax, eax
.nonneg:
    cmp     rax, 60
    jb      .just
    cmp     rax, 3600
    jb      .min
    cmp     rax, 86400
    jb      .hour
    xor     edx, edx
    mov     ecx, 86400
    div     rcx
    lea     r13, [s_days]
    cmp     eax, 1
    jne     .emit
    lea     r13, [s_day]
    jmp     .emit
.min:
    xor     edx, edx
    mov     ecx, 60
    div     rcx
    lea     r13, [s_min]
    jmp     .emit
.hour:
    xor     edx, edx
    mov     ecx, 3600
    div     rcx
    lea     r13, [s_hour]
.emit:
    mov     edi, eax
    mov     rsi, rbx
    call    i32_to_str
    mov     rdi, rax
    mov     rsi, r13
    call    str_append
    mov     byte [rax], 0
    jmp     .ret
.just:
    mov     rdi, rbx
    lea     rsi, [s_just_now]
    mov     edx, 16
    call    str_copy
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret
