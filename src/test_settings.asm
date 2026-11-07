; test_settings.asm - settings file round trip and bad-value handling.
%include "common.inc"
default rel

global test_settings_roundtrip, test_settings_clamps_bad_values, test_settings_reload_key

extern world_clear
extern settings, settings_defaults, settings_load, settings_save
extern file_write_atomic, file_unlink, str_len

section .rodata
cfg_path: db "/tmp/assemblycraft-selftest.cfg", 0
bad_cfg:  db "fov=500", 10, "bogus line", 10, "key_jump=5", 10, "volume=50", 10, 0
; written before 0.4: no key_reload line
old_cfg:  db "fov=80", 10, "key_fly=71", 10, 0
new_cfg:  db "key_reload=75", 10, 0
; every field at a non-default, in-range value
align 4
alt_img:
    dd 95, 250, 12, 30, 1, 1, 0, 1, 3
    dd 81, 82, 83, 84, 74, 259, 260, 261, 262, 263
    dd 264, 265, 266, 267, 268

section .text

; roundtrip_all(): every field non-default, save, reset, load, compare -> eax 0 ok
roundtrip_all:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    lea     rsi, [alt_img]
    lea     rdi, [settings]
    mov     ecx, SETTINGS_size / 4
    rep     movsd
    lea     rdi, [cfg_path]
    call    settings_save
    test    eax, eax
    jnz     .fail
    call    settings_defaults
    lea     rdi, [cfg_path]
    call    settings_load
    test    eax, eax
    jnz     .fail
    lea     rsi, [alt_img]
    lea     rdi, [settings]
    mov     ecx, SETTINGS_size / 4
    repe    cmpsd
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

test_settings_roundtrip:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    settings_defaults
    mov     dword [settings + SETTINGS.fov], 95
    mov     dword [settings + SETTINGS.keys + 4 * BIND_JUMP], 74
    lea     rdi, [cfg_path]
    call    settings_save
    test    eax, eax
    jnz     .fail
    call    settings_defaults
    lea     rdi, [cfg_path]
    call    settings_load
    test    eax, eax
    jnz     .fail
    cmp     dword [settings + SETTINGS.fov], 95
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_JUMP], 74
    jne     .fail
    cmp     dword [settings + SETTINGS.sensitivity], 100
    jne     .fail
    cmp     dword [settings + SETTINGS.render_dist], 8
    jne     .fail
    cmp     dword [settings + SETTINGS.volume], 100
    jne     .fail
    cmp     dword [settings + SETTINGS.difficulty], 2
    jne     .fail
    cmp     dword [settings + SETTINGS.invert_mouse], 0
    jne     .fail
    cmp     dword [settings + SETTINGS.vsync], 1
    jne     .fail
    cmp     dword [settings + SETTINGS.fullscreen], 0
    jne     .fail
    cmp     dword [settings + SETTINGS.gui_scale], 0
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_FORWARD], 87
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_BACK], 83
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_LEFT], 65
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_RIGHT], 68
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_SNEAK], 340
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_SPRINT], 341
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_INVENTORY], 69
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_FLY], 70
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_RELOAD], 82
    jne     .fail
    call    roundtrip_all               ; every field survives, not just the two above
    test    eax, eax
    jnz     .fail
    xor     ebx, ebx
    jmp     .done
.fail:
    mov     ebx, 1
.done:
    lea     rdi, [cfg_path]
    call    file_unlink
    call    settings_defaults
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

test_settings_clamps_bad_values:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    settings_defaults
    lea     rdi, [bad_cfg]
    call    str_len
    lea     rdi, [cfg_path]
    lea     rsi, [bad_cfg]
    mov     rdx, rax
    call    file_write_atomic
    test    eax, eax
    jnz     .fail
    lea     rdi, [cfg_path]
    call    settings_load
    cmp     eax, 2
    jne     .fail
    cmp     dword [settings + SETTINGS.fov], 110
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_JUMP], 32
    jne     .fail
    cmp     dword [settings + SETTINGS.volume], 50
    jne     .fail
    xor     ebx, ebx
    jmp     .done
.fail:
    mov     ebx, 1
.done:
    lea     rdi, [cfg_path]
    call    file_unlink
    call    settings_defaults
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; load_text(rdi zstr) -> eax settings_load result of a file holding exactly that text
load_text:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdi
    call    str_len
    lea     rdi, [cfg_path]
    mov     rsi, rbx
    mov     rdx, rax
    call    file_write_atomic
    test    eax, eax
    jnz     .bad
    call    settings_defaults
    lea     rdi, [cfg_path]
    call    settings_load
    jmp     .ret
.bad:
    mov     eax, -1
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; A settings file written before the Reload binding existed loads with R; a saved
; key_reload line wins.
test_settings_reload_key:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    lea     rdi, [old_cfg]
    call    load_text
    test    eax, eax
    jnz     .fail
    cmp     dword [settings + SETTINGS.fov], 80
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_FLY], 71
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_RELOAD], 82
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_DODGE], 67
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_ABILITY1], 81
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_ABILITY2], 71
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_ABILITY3], 86
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_SKILLS], 75
    jne     .fail
    lea     rdi, [new_cfg]
    call    load_text
    test    eax, eax
    jnz     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_RELOAD], 75
    jne     .fail
    xor     ebx, ebx
    jmp     .done
.fail:
    mov     ebx, 1
.done:
    lea     rdi, [cfg_path]
    call    file_unlink
    call    settings_defaults
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret
