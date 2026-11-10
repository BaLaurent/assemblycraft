; test_vehicleview.asm - the Vehicle view binding: default key, persistence, old settings
; files without it, and a label for every binding.
%include "common.inc"
default rel

global test_vehicleview_default_key, test_vehicleview_roundtrip
global test_vehicleview_missing_key, test_vehicleview_labels

extern settings, settings_defaults, settings_load, settings_save
extern file_write_atomic, file_unlink, str_len
extern bind_labels

section .rodata
cfg_path:   db "/tmp/assemblycraft-selftest-vehicleview.cfg", 0
; written before the Vehicle view binding existed: other keys rebound, no key_vehicle_view line
old_cfg:    db "key_jump=74", 10, "key_chat=77", 10, "key_players=300", 10, 0

section .text

test_vehicleview_default_key:
    call    settings_defaults
    xor     eax, eax
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_VEHICLE_VIEW], 86
    setne   al
    ret

test_vehicleview_roundtrip:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    settings_defaults
    mov     dword [settings + SETTINGS.keys + 4 * BIND_VEHICLE_VIEW], 66
    lea     rdi, [cfg_path]
    call    settings_save
    test    eax, eax
    jnz     .fail
    call    settings_defaults
    lea     rdi, [cfg_path]
    call    settings_load
    test    eax, eax
    jnz     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_VEHICLE_VIEW], 66
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_PLAYERS], 258
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

test_vehicleview_missing_key:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    settings_defaults
    mov     dword [settings + SETTINGS.keys + 4 * BIND_VEHICLE_VIEW], 66 ; load must overwrite it
    lea     rdi, [old_cfg]
    call    str_len
    lea     rdi, [cfg_path]
    lea     rsi, [old_cfg]
    mov     rdx, rax
    call    file_write_atomic
    test    eax, eax
    jnz     .fail
    lea     rdi, [cfg_path]
    call    settings_load
    test    eax, eax
    jnz     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_VEHICLE_VIEW], 86
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_JUMP], 74
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_CHAT], 77
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_PLAYERS], 300
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_ABILITY3], 86
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_ABILITY4], 88
    jne     .fail
    cmp     dword [settings + SETTINGS.keys + 4 * BIND_FORWARD], 87
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

; every binding below NUM_BINDINGS has a non-empty label
test_vehicleview_labels:
    xor     ecx, ecx
.next:
    mov     rax, [bind_labels + rcx*8]
    test    rax, rax
    jz      .fail
    cmp     byte [rax], 0
    je      .fail
    inc     ecx
    cmp     ecx, NUM_BINDINGS
    jb      .next
    xor     eax, eax
    ret
.fail:
    mov     eax, 1
    ret
