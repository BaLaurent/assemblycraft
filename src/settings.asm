; settings.asm - persistent user settings: defaults, text-file load/save, window apply.
%include "common.inc"
%include "gl.inc"
default rel

global settings, settings_defaults, settings_reset_keys
global settings_load, settings_save, settings_apply

extern parse_u32, str_eq, str_append, i32_to_str
extern file_read, file_write_atomic

; fov sensitivity render_dist volume difficulty invert vsync fullscreen gui_scale, then NUM_BINDINGS keys
%macro SETTINGS_IMAGE 0
    dd 70, 100, 8, 100, 2, 0, 1, 0, 0
    dd 87, 83, 65, 68, 32, 340, 341, 69, 70, 82 ; W S A D Space LShift LCtrl E F R
    dd 67, 81, 71, 86, 75, 88           ; C Q G V K X
    dd 84, 258, 86                      ; T (chat), Tab (player list), V (vehicle view)
%endmacro

; one table record = 32 bytes: name[16] NUL padded, field offset, min, max, flag
; flag 1: a value outside min..max resets to the default instead of clamping (key codes)
%macro SETENT 5
    %%s: db %1, 0
    times 16 - ($ - %%s) db 0
    dd %2, %3, %4, %5
%endmacro

section .data
align 4
settings:
    SETTINGS_IMAGE

section .rodata
align 4
settings_default_img:
    SETTINGS_IMAGE

align 8
settings_table:
    SETENT "fov",             SETTINGS.fov,          50, 110, 0
    SETENT "sensitivity",     SETTINGS.sensitivity,  10, 300, 0
    SETENT "render_distance", SETTINGS.render_dist,   2,  24, 0
    SETENT "volume",          SETTINGS.volume,        0, 100, 0
    SETENT "difficulty",      SETTINGS.difficulty,    0,   3, 0
    SETENT "invert_mouse",    SETTINGS.invert_mouse,  0,   1, 0
    SETENT "vsync",           SETTINGS.vsync,         0,   1, 0
    SETENT "fullscreen",      SETTINGS.fullscreen,    0,   1, 0
    SETENT "gui_scale",       SETTINGS.gui_scale,     0,   4, 0
    SETENT "key_forward",     SETTINGS.keys + 4 * BIND_FORWARD,   32, 348, 1
    SETENT "key_back",        SETTINGS.keys + 4 * BIND_BACK,      32, 348, 1
    SETENT "key_left",        SETTINGS.keys + 4 * BIND_LEFT,      32, 348, 1
    SETENT "key_right",       SETTINGS.keys + 4 * BIND_RIGHT,     32, 348, 1
    SETENT "key_jump",        SETTINGS.keys + 4 * BIND_JUMP,      32, 348, 1
    SETENT "key_sneak",       SETTINGS.keys + 4 * BIND_SNEAK,     32, 348, 1
    SETENT "key_sprint",      SETTINGS.keys + 4 * BIND_SPRINT,    32, 348, 1
    SETENT "key_inventory",   SETTINGS.keys + 4 * BIND_INVENTORY, 32, 348, 1
    SETENT "key_fly",         SETTINGS.keys + 4 * BIND_FLY,       32, 348, 1
    SETENT "key_reload",      SETTINGS.keys + 4 * BIND_RELOAD,    32, 348, 1
    SETENT "key_dodge",       SETTINGS.keys + 4 * BIND_DODGE,     32, 348, 1
    SETENT "key_ability1",    SETTINGS.keys + 4 * BIND_ABILITY1,  32, 348, 1
    SETENT "key_ability2",    SETTINGS.keys + 4 * BIND_ABILITY2,  32, 348, 1
    SETENT "key_ability3",    SETTINGS.keys + 4 * BIND_ABILITY3,  32, 348, 1
    SETENT "key_skills",      SETTINGS.keys + 4 * BIND_SKILLS,    32, 348, 1
    SETENT "key_ability4",    SETTINGS.keys + 4 * BIND_ABILITY4,  32, 348, 1
    SETENT "key_chat",        SETTINGS.keys + 4 * BIND_CHAT,      32, 348, 1
    SETENT "key_players",     SETTINGS.keys + 4 * BIND_PLAYERS,   32, 348, 1
    SETENT "key_vehicleview", SETTINGS.keys + 4 * BIND_VEHICLE_VIEW, 32, 348, 1
settings_table_end:

section .bss
align 8
cfg_buf:    resb 4104
out_buf:    resb 1024
fs_active:  resd 1
fs_x:       resd 1
fs_y:       resd 1
fs_w:       resd 1
fs_h:       resd 1

section .text

; settings_defaults(): every field back to its default
settings_defaults:
    lea     rsi, [settings_default_img]
    lea     rdi, [settings]
    mov     ecx, SETTINGS_size / 4
    rep     movsd
    ret

; settings_reset_keys(): only the key bindings back to their defaults
settings_reset_keys:
    lea     rsi, [settings_default_img + SETTINGS.keys]
    lea     rdi, [settings + SETTINGS.keys]
    mov     ecx, NUM_BINDINGS
    rep     movsd
    ret

; apply_line(rdi key zstr, rsi value zstr) -> eax 1 stored / 0 unknown key or bad number
apply_line:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 24                     ; [rsp] parsed value, [rsp+8] table end
    mov     r13, rdi
    mov     r12, rsi
    lea     rbx, [settings_table]
    lea     rax, [settings_table_end]
    mov     [rsp + 8], rax
.lookup:
    cmp     rbx, [rsp + 8]
    jae     .bad
    mov     rdi, r13
    mov     rsi, rbx
    call    str_eq
    test    eax, eax
    jnz     .found
    add     rbx, 32
    jmp     .lookup
.found:
    mov     rdi, r12
    lea     rsi, [rsp]
    call    parse_u32
    test    eax, eax
    jz      .bad
    mov     eax, [rsp]
    mov     edx, [rbx + 16]             ; field offset
    mov     ecx, [rbx + 20]             ; min
    mov     esi, [rbx + 24]             ; max
    cmp     eax, ecx
    jb      .out
    cmp     eax, esi
    jbe     .store
.out:
    cmp     dword [rbx + 28], 0
    jne     .deflt
    cmp     eax, ecx
    jb      .min
    mov     eax, esi
    jmp     .store
.min:
    mov     eax, ecx
    jmp     .store
.deflt:
    lea     rcx, [settings_default_img]
    mov     eax, [rcx + rdx]
.store:
    lea     rcx, [settings]
    mov     [rcx + rdx], eax
    mov     eax, 1
    jmp     .ret
.bad:
    xor     eax, eax
.ret:
    add     rsp, 24
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; settings_load(rdi path) -> eax 0 ok / 1 file missing (defaults loaded) / 2 some lines were bad.
; Starts from the defaults; numbers are clamped, bad key codes reset to their default.
settings_load:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8                      ; [rsp] next line start
    lea     rsi, [cfg_buf]
    mov     edx, 4096
    call    file_read
    test    rax, rax
    js      .missing
    lea     rbx, [cfg_buf]
    lea     r12, [rbx + rax]            ; end of data
    mov     byte [r12], 0
    call    settings_defaults
    xor     r13d, r13d                  ; saw a bad line
.line:
    cmp     rbx, r12
    jae     .finish
    mov     rdx, rbx
.eol:
    cmp     rdx, r12
    jae     .eol_done
    cmp     byte [rdx], 10
    je      .eol_done
    inc     rdx
    jmp     .eol
.eol_done:
    mov     byte [rdx], 0
    lea     rcx, [rdx + 1]
    mov     [rsp], rcx
    cmp     rdx, rbx
    jbe     .nostrip
    cmp     byte [rdx - 1], 13
    jne     .nostrip
    mov     byte [rdx - 1], 0
.nostrip:
    cmp     byte [rbx], 0
    je      .next                       ; blank line
    mov     rax, rbx
.eq:
    mov     cl, [rax]
    test    cl, cl
    jz      .noeq
    cmp     cl, '='
    je      .haveeq
    inc     rax
    jmp     .eq
.haveeq:
    mov     byte [rax], 0
    mov     rdi, rbx
    lea     rsi, [rax + 1]
    call    apply_line
    test    eax, eax
    jnz     .next
.noeq:
    mov     r13d, 1
.next:
    mov     rbx, [rsp]
    jmp     .line
.finish:
    lea     eax, [r13 * 2]
    jmp     .ret
.missing:
    call    settings_defaults
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; settings_save(rdi path) -> eax 0 / -errno. Writes "key=value\n" lines in table order.
settings_save:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     r13, rdi
    lea     r12, [out_buf]
    lea     rbx, [settings_table]
.ent:
    lea     rax, [settings_table_end]
    cmp     rbx, rax
    jae     .write
    mov     rdi, r12
    mov     rsi, rbx
    call    str_append
    mov     byte [rax], '='
    lea     rsi, [rax + 1]
    mov     edx, [rbx + 16]
    lea     rcx, [settings]
    mov     edi, [rcx + rdx]
    call    i32_to_str
    mov     byte [rax], 10
    lea     r12, [rax + 1]
    add     rbx, 32
    jmp     .ent
.write:
    mov     rdi, r13
    lea     rsi, [out_buf]
    mov     rdx, r12
    sub     rdx, rsi
    call    file_write_atomic
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; settings_apply(rdi window): applies vsync and the fullscreen setting (GL thread only)
settings_apply:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16                     ; [rsp] 7th call argument
    mov     rbx, rdi
    mov     edi, [settings + SETTINGS.vsync]
    call    glfwSwapInterval
    xor     r12d, r12d                  ; wanted fullscreen state, normalised
    cmp     dword [settings + SETTINGS.fullscreen], 0
    setne   r12b
    cmp     r12d, [fs_active]
    je      .done
    test    r12d, r12d
    jz      .leave
    mov     rdi, rbx                    ; enter: remember the windowed geometry
    lea     rsi, [fs_x]
    lea     rdx, [fs_y]
    call    glfwGetWindowPos
    mov     rdi, rbx
    lea     rsi, [fs_w]
    lea     rdx, [fs_h]
    call    glfwGetWindowSize
    call    glfwGetPrimaryMonitor
    test    rax, rax
    jz      .done
    mov     r12, rax                    ; monitor
    mov     rdi, rax
    call    glfwGetVideoMode
    test    rax, rax
    jz      .done
    mov     ecx, [rax + 20]             ; refreshRate
    mov     [rsp], rcx
    mov     r8d, [rax]                  ; width
    mov     r9d, [rax + 4]              ; height
    mov     rdi, rbx
    mov     rsi, r12
    xor     edx, edx
    xor     ecx, ecx
    call    glfwSetWindowMonitor
    mov     dword [fs_active], 1
    jmp     .done
.leave:
    mov     qword [rsp], GLFW_DONT_CARE
    mov     rdi, rbx
    xor     esi, esi
    mov     edx, [fs_x]
    mov     ecx, [fs_y]
    mov     r8d, [fs_w]
    mov     r9d, [fs_h]
    call    glfwSetWindowMonitor
    mov     dword [fs_active], 0
.done:
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret
