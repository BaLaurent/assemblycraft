; options.asm - Settings and Controls screens, and key_name (GLFW key code -> label).
; Both screens are immediate-mode: call once per frame after ui_begin. Settings
; are edited live in the global `settings` struct; Done / Escape on the Settings
; screen writes the settings file and returns to app_settings_parent.
%include "common.inc"
%include "gl.inc"
default rel

global screen_settings, screen_controls, key_name

extern ui_w, ui_h, ui_input
extern ui_text, ui_text_centered, ui_button, ui_slider
extern settings, settings_path, settings_save, settings_apply, settings_reset_keys
extern app_goto, app_settings_parent, app_entered, app_window
extern str_append, i32_to_str

%define WHITE   0xFFFFFFFF
%define RED     RGBA(255, 85, 85, 255)

; Controls layout (GUI units): two columns of 8 rows when they fit, else one column of 15.
; wide (ui_w >= 470): the 465-unit layout, labels 125 wide, 100-wide key buttons
; compact (ui_w >= 408): 401 units, labels 112 wide, 84-wide key buttons (the 426-wide GUI
;   of the default 1280x720 window)
%define CTRL_WIDE_W     470
%define CTRL_COMPACT_W  408
%define CTRL_ROWS       8

section .rodata
s_empty:        db 0
s_settings:     db "Settings", 0
s_controls:     db "Controls", 0
s_controls_btn: db "Controls...", 0
s_done:         db "Done", 0
s_reset_keys:   db "Reset Keys", 0
s_capturing:    db "> ??? <", 0

s_fov:          db "FOV: ", 0
s_sens:         db "Sensitivity: ", 0
s_pct:          db "%", 0
s_render:       db "Render Dist: ", 0  ; "Render Distance: 16 chunks" overflows a 150-wide slider
s_chunks:       db " chunks", 0
s_volume:       db "Volume: ", 0
s_difficulty:   db "Difficulty: ", 0
s_gui_scale:    db "GUI Scale: ", 0
s_invert:       db "Invert Mouse: ", 0
s_vsync:        db "VSync: ", 0
s_fullscreen:   db "Fullscreen: ", 0

s_peaceful:     db "Peaceful", 0
s_easy:         db "Easy", 0
s_normal:       db "Normal", 0
s_hard:         db "Hard", 0
s_auto:         db "Auto", 0
s_1:            db "1", 0
s_2:            db "2", 0
s_3:            db "3", 0
s_4:            db "4", 0
s_off:          db "OFF", 0
s_on:           db "ON", 0

align 8
difficulty_names: dq s_peaceful, s_easy, s_normal, s_hard
scale_names:      dq s_auto, s_1, s_2, s_3, s_4
onoff_names:      dq s_off, s_on

s_b_forward:    db "Walk Forward", 0
s_b_back:       db "Walk Backward", 0
s_b_left:       db "Strafe Left", 0
s_b_right:      db "Strafe Right", 0
s_b_jump:       db "Jump / Fly Up", 0
s_b_sneak:      db "Sneak / Fly Down", 0
s_b_sprint:     db "Sprint", 0
s_b_inventory:  db "Inventory", 0
s_b_fly:        db "Toggle Fly", 0
s_b_reload:     db "Reload", 0
s_b_dodge:      db "Dodge", 0
s_b_ability1:   db "Ability 1", 0
s_b_ability2:   db "Ability 2", 0
s_b_ability3:   db "Ability 3", 0
s_b_skills:     db "Skill Tree", 0
s_b_ability4:   db "Ability 4", 0
align 8
bind_labels:    dq s_b_forward, s_b_back, s_b_left, s_b_right, s_b_jump
                dq s_b_sneak, s_b_sprint, s_b_inventory, s_b_fly, s_b_reload
                dq s_b_dodge, s_b_ability1, s_b_ability2, s_b_ability3, s_b_skills
                dq s_b_ability4

; Names of keys that glfwGetKeyName does not report: dw key, zstr; dw 0 ends it.
%macro KEY 2
    dw %1
    db %2, 0
%endmacro
key_table:
    KEY 32, "Space"
    KEY 257, "Enter"
    KEY 258, "Tab"
    KEY 259, "Backspace"
    KEY 260, "Insert"
    KEY 261, "Delete"
    KEY 262, "Right"
    KEY 263, "Left"
    KEY 264, "Down"
    KEY 265, "Up"
    KEY 266, "Page Up"
    KEY 267, "Page Down"
    KEY 268, "Home"
    KEY 269, "End"
    KEY 280, "Caps Lock"
    KEY 335, "Num Enter"
    KEY 340, "Left Shift"
    KEY 341, "Left Ctrl"
    KEY 342, "Left Alt"
    KEY 343, "Left Super"
    KEY 344, "Right Shift"
    KEY 345, "Right Ctrl"
    KEY 346, "Right Alt"
    KEY 347, "Right Super"
    KEY 348, "Menu"
    dw 0
s_num:          db "Num ", 0
s_key:          db "Key ", 0

section .data
align 8
slider_fov:     dq settings + SETTINGS.fov, s_fov, s_empty
                dd 50, 110
slider_sens:    dq settings + SETTINGS.sensitivity, s_sens, s_pct
                dd 10, 300
slider_render:  dq settings + SETTINGS.render_dist, s_render, s_chunks
                dd 2, 16
slider_volume:  dq settings + SETTINGS.volume, s_volume, s_pct
                dd 0, 100
capturing:      dd -1                   ; binding row waiting for a key, or -1

section .text

; label2(rdi buf, rsi a, rdx b): buf = a + b (NUL-terminated)
label2:
    push    rbx
    mov     rbx, rdx
    call    str_append
    mov     rdi, rax
    mov     rsi, rbx
    call    str_append
    mov     byte [rax], 0
    pop     rbx
    ret

; opt_cycle(rdi prefix, rsi names[], rdx int32* field, ecx x, r8d y, r9d modulus)
;   -> eax 1 if clicked. A 150-wide button labelled prefix + names[*field]; a click
;   advances the field to (value + 1) mod modulus.
opt_cycle:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 72                     ; [rsp] label (64), [rsp+64] value
    mov     rbx, rsi
    mov     r12, rdx
    mov     r13d, ecx
    mov     r14d, r8d
    mov     r15d, r9d
    mov     eax, [r12]
    cmp     eax, r15d
    jb      .in_range
    xor     eax, eax
.in_range:
    mov     [rsp + 64], eax
    mov     rsi, rdi
    mov     rdx, [rbx + rax*8]
    mov     rdi, rsp
    call    label2
    mov     rdi, rsp
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, 150
    mov     r8d, 1
    call    ui_button
    test    eax, eax
    jz      .ret
    mov     eax, [rsp + 64]
    inc     eax
    cmp     eax, r15d
    jb      .store
    xor     eax, eax
.store:
    mov     [r12], eax
    mov     eax, 1
.ret:
    add     rsp, 72
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- Settings screen --------------------------------------------------------

%macro SLIDER 3                         ; def, x offset from centre, row
    lea     rdi, [%1]
    lea     esi, [r12 + %2]
    mov     edx, 36 + 24*%3
    mov     ecx, 150
    call    ui_slider
%endmacro

%macro CYCLE 6                          ; prefix, names, field, x offset, row, modulus
    lea     rdi, [%1]
    lea     rsi, [%2]
    lea     rdx, [settings + %3]
    lea     ecx, [r12 + %4]
    mov     r8d, 36 + 24*%5
    mov     r9d, %6
    call    opt_cycle
%endmacro

; screen_settings()
screen_settings:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     dword [app_entered], 0
    mov     r12d, [ui_w]
    shr     r12d, 1                     ; cx
    lea     rdi, [s_settings]
    mov     esi, r12d
    mov     edx, 12
    mov     ecx, WHITE
    mov     r8d, 1
    call    ui_text_centered
    SLIDER  slider_fov, -155, 0
    SLIDER  slider_sens, 5, 0
    SLIDER  slider_render, -155, 1
    SLIDER  slider_volume, 5, 1
    CYCLE   s_difficulty, difficulty_names, SETTINGS.difficulty, -155, 2, 4
    CYCLE   s_gui_scale, scale_names, SETTINGS.gui_scale, 5, 2, 5
    CYCLE   s_invert, onoff_names, SETTINGS.invert_mouse, -155, 3, 2
    CYCLE   s_vsync, onoff_names, SETTINGS.vsync, 5, 3, 2
    test    eax, eax
    jz      .vsync_done
    mov     rdi, [app_window]
    call    settings_apply
.vsync_done:
    CYCLE   s_fullscreen, onoff_names, SETTINGS.fullscreen, -155, 4, 2
    test    eax, eax
    jz      .fs_done
    mov     rdi, [app_window]
    call    settings_apply
.fs_done:
    lea     rdi, [s_controls_btn]
    lea     esi, [r12 + 5]
    mov     edx, 36 + 24*4
    mov     ecx, 150
    mov     r8d, 1
    call    ui_button
    test    eax, eax
    jz      .done_button
    mov     edi, ST_CONTROLS
    call    app_goto
    jmp     .ret
.done_button:
    lea     rdi, [s_done]
    lea     esi, [r12 - 100]
    mov     edx, [ui_h]
    sub     edx, 28
    mov     ecx, 200
    mov     r8d, 1
    call    ui_button
    test    eax, eax
    jnz     .finish
    cmp     dword [ui_input + UIINPUT.escape], 0
    je      .ret
.finish:
    lea     rdi, [settings_path]
    call    settings_save
    mov     edi, [app_settings_parent]
    call    app_goto
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- Controls screen --------------------------------------------------------

; is_dup(edi row) -> eax 1 if another binding uses the same key code (leaf)
is_dup:
    mov     edx, [settings + SETTINGS.keys + rdi*4]
    xor     ecx, ecx
.next:
    cmp     ecx, edi
    je      .skip
    cmp     edx, [settings + SETTINGS.keys + rcx*4]
    je      .yes
.skip:
    inc     ecx
    cmp     ecx, NUM_BINDINGS
    jb      .next
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; screen_controls()
screen_controls:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 72                     ; [rsp] key label (32), [rsp+32] capture state, [rsp+36] layout
    cmp     dword [app_entered], 0
    je      .entered
    mov     dword [capturing], -1
    mov     dword [app_entered], 0
.entered:
    mov     r15d, [capturing]           ; capture state when the frame began
    mov     [rsp + 32], r15d
    test    r15d, r15d
    js      .layout
    mov     eax, [ui_input + UIINPUT.key_pressed]
    cmp     eax, 256
    je      .cancel
    cmp     eax, 32
    jl      .layout                     ; nothing pressed (-1)
    cmp     eax, 348
    jg      .layout
    mov     [settings + SETTINGS.keys + r15*4], eax
.cancel:
    mov     dword [capturing], -1
.layout:
    mov     r12d, [ui_w]
    shr     r12d, 1                     ; cx
    lea     rdi, [s_controls]
    mov     esi, r12d
    mov     edx, 10
    mov     ecx, WHITE
    mov     r8d, 1
    call    ui_text_centered
    ; layout: [rsp+36] rows per column, [rsp+40] column step, [rsp+44] label x of column 0,
    ; [rsp+48] button offset from the label, [rsp+52] button width, [rsp+56] label x of the row
    mov     eax, [ui_w]
    cmp     eax, CTRL_WIDE_W
    jae     .wide
    cmp     eax, CTRL_COMPACT_W
    jae     .compact
    mov     dword [rsp + 36], NUM_BINDINGS
    mov     dword [rsp + 40], 0
    lea     eax, [r12 - 150]
    mov     [rsp + 44], eax
    mov     dword [rsp + 48], 160
    mov     dword [rsp + 52], 120
    jmp     .pitch
.wide:
    mov     dword [rsp + 36], CTRL_ROWS
    mov     dword [rsp + 40], 240
    lea     eax, [r12 - 235]
    mov     [rsp + 44], eax
    mov     dword [rsp + 48], 125
    mov     dword [rsp + 52], 100
    jmp     .pitch
.compact:
    mov     dword [rsp + 36], CTRL_ROWS
    mov     dword [rsp + 40], 205
    lea     eax, [r12 - 200]
    mov     [rsp + 44], eax
    mov     dword [rsp + 48], 112
    mov     dword [rsp + 52], 84
.pitch:
    mov     eax, [ui_h]
    sub     eax, 60
    cdq
    idiv    dword [rsp + 36]
    mov     r14d, 24                    ; pitch = min(24, (ui_h - 60) / rows), at least 14
    cmp     eax, r14d
    cmovl   r14d, eax
    mov     eax, 14
    cmp     r14d, eax
    cmovl   r14d, eax
    xor     ebx, ebx                    ; row
.row:
    mov     eax, ebx
    xor     edx, edx
    div     dword [rsp + 36]            ; eax = column, edx = row within the column
    imul    eax, [rsp + 40]
    add     eax, [rsp + 44]
    mov     [rsp + 56], eax
    mov     r13d, r14d
    imul    r13d, edx
    add     r13d, 28                    ; y
    mov     rax, [bind_labels + rbx*8]
    mov     rdi, rax
    mov     esi, [rsp + 56]
    lea     edx, [r13 + 6]
    mov     ecx, WHITE
    mov     r8d, 1
    call    ui_text
    lea     rdi, [s_empty]
    mov     esi, [rsp + 56]
    add     esi, [rsp + 48]
    mov     edx, r13d
    mov     ecx, [rsp + 52]
    mov     r8d, 1
    call    ui_button
    test    eax, eax
    jz      .label
    mov     [capturing], ebx
.label:
    mov     ecx, WHITE
    cmp     [capturing], ebx
    jne     .key_label
    lea     rdi, [s_capturing]
    jmp     .draw
.key_label:
    mov     edi, ebx
    call    is_dup
    mov     ecx, WHITE
    mov     edx, RED
    test    eax, eax
    cmovnz  ecx, edx
    mov     r15d, ecx                   ; label colour, kept across key_name
    mov     edi, [settings + SETTINGS.keys + rbx*4]
    mov     rsi, rsp
    call    key_name
    mov     ecx, r15d
    mov     rdi, rsp
.draw:
    mov     esi, [rsp + 52]
    shr     esi, 1
    add     esi, [rsp + 48]
    add     esi, [rsp + 56]             ; centre of the key button
    lea     edx, [r13 + 6]
    mov     r8d, 1
    call    ui_text_centered
    inc     ebx
    cmp     ebx, NUM_BINDINGS
    jb      .row
    lea     rdi, [s_reset_keys]
    lea     esi, [r12 - 155]
    mov     edx, [ui_h]
    sub     edx, 28
    mov     ecx, 150
    mov     r8d, 1
    call    ui_button
    test    eax, eax
    jz      .done_button
    call    settings_reset_keys
    mov     dword [capturing], -1
.done_button:
    lea     rdi, [s_done]
    lea     esi, [r12 + 5]
    mov     edx, [ui_h]
    sub     edx, 28
    mov     ecx, 150
    mov     r8d, 1
    call    ui_button
    test    eax, eax
    jnz     .back
    cmp     dword [rsp + 32], 0         ; Escape leaves only when it was not cancelling a capture
    jl      .esc_check
    jmp     .ret
.esc_check:
    cmp     dword [ui_input + UIINPUT.escape], 0
    je      .ret
.back:
    mov     edi, ST_SETTINGS
    call    app_goto
.ret:
    add     rsp, 72
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- key names --------------------------------------------------------------

; key_name(edi key, rsi out) -> rax pointer to the written NUL
; The layout-aware name from glfwGetKeyName when there is one (first letter
; upper-cased, non-ASCII bytes shown as '?'), else a fixed table, else "Key <n>".
key_name:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12, rsi
    xor     esi, esi
    call    glfwGetKeyName
    test    rax, rax
    jz      .table
    cmp     byte [rax], ' '
    jbe     .table                      ; blank names (Space) come from the table
    mov     rsi, rax
    mov     rdi, r12
    movzx   eax, byte [rsi]
    lea     edx, [rax - 'a']
    cmp     edx, 25
    ja      .first_ok
    sub     eax, 32
.first_ok:
    xor     ecx, ecx
.emit:
    cmp     eax, 128
    jb      .ascii
    mov     eax, '?'
.ascii:
    mov     [rdi], al
    inc     rdi
    inc     rsi
    inc     ecx
    cmp     ecx, 23
    jae     .terminate
    movzx   eax, byte [rsi]
    test    eax, eax
    jnz     .emit
.terminate:
    mov     byte [rdi], 0
    mov     rax, rdi
    jmp     .ret
.table:
    lea     rsi, [key_table]
.scan:
    movzx   eax, word [rsi]
    test    eax, eax
    jz      .ranges
    add     rsi, 2
    cmp     eax, ebx
    je      .found
.skip:
    cmp     byte [rsi], 0
    je      .skipped
    inc     rsi
    jmp     .skip
.skipped:
    inc     rsi
    jmp     .scan
.found:
    mov     rdi, r12
    call    str_append
    mov     byte [rax], 0
    jmp     .ret
.ranges:
    lea     eax, [rbx - 290]
    cmp     eax, 24
    ja      .not_f
    mov     byte [r12], 'F'             ; F1..F25
    lea     edi, [rbx - 289]
    lea     rsi, [r12 + 1]
    call    i32_to_str
    mov     byte [rax], 0
    jmp     .ret
.not_f:
    lea     eax, [rbx - 320]
    cmp     eax, 9
    ja      .generic
    mov     rdi, r12                    ; Num 0..Num 9
    lea     rsi, [s_num]
    call    str_append
    mov     rsi, rax
    mov     edi, ebx
    sub     edi, 320
    call    i32_to_str
    mov     byte [rax], 0
    jmp     .ret
.generic:
    mov     rdi, r12
    lea     rsi, [s_key]
    call    str_append
    mov     rsi, rax
    mov     edi, ebx
    call    i32_to_str
    mov     byte [rax], 0
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret
