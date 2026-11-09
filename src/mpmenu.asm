; mpmenu.asm - the multiplayer screens on the ui.asm toolkit, in the grimoire look of menus.asm: the
; join screen (ST_MP_JOIN, from the title: your name and a room code or IP:port, then the progress
; of the join the netsync module runs), the host screen (ST_MP_HOST, from the pause menu: open the
; world to others, then show the room code, the direct address and the PvP switch) and the chat bar
; (ST_CHAT: one text field over the bottom of the world). Every screen_*() runs once per frame after
; ui_begin and acts on ui_input; a screen that changes state returns at once, so one click never
; reaches two widgets. The name and target fields are reset when app_entered is set (and clear it).
%include "common.inc"
%include "theme.inc"
default rel

global screen_mp_join, screen_mp_host, screen_chat

extern ui_w, ui_h, ui_focus, ui_input
extern ui_rect, ui_nine, ui_text_centered, ui_text_width, ui_text_ink_centered, ui_text_ink
extern ui_button, ui_textfield
extern app_entered, app_goto, form_page
extern str_copy, str_append, i32_to_str
extern net_role, net_pvp, net_cfg_name, net_cfg_port, net_cfg_save, net_valid_name
extern net_join_begin, net_join_cancel, net_join_status, net_ep, net_ep_join_state
extern net_host_open, net_host_close, net_ep_rv_state, net_room_code, net_lan_text
extern net_set_pvp, net_chat_send

%define TARGET_MAX      24              ; "255.255.255.255:65535" is 21
%define CHAT_MAX        32              ; the TEXTFIELD limit
%define C_BAR           RGBA(0, 0, 0, 150)      ; the chat bar over the world
%define C_RV_FAIL       RGBA(255, 100, 90, 255) ; a failure on the dark plaque

; ---- drawing macros (as menus.asm; xbase / ybase are 64-bit registers holding a GUI coordinate) ---
%macro INKC 7                           ; str, xbase, xoff, ybase, yoff, rgba, scale (centred, no shadow)
    lea     rdi, [%1]
    lea     esi, [%2 + %3]
    lea     edx, [%4 + %5]
    mov     ecx, %6
    mov     r8d, %7
    call    ui_text_ink_centered
%endmacro
%macro INKCA 6                          ; str, xbase, xoff, y, rgba, scale (centred, no shadow, absolute y)
    lea     rdi, [%1]
    lea     esi, [%2 + %3]
    mov     edx, %4
    mov     ecx, %5
    mov     r8d, %6
    call    ui_text_ink_centered
%endmacro
%macro INKL 6                           ; str, xbase, xoff, y, rgba, scale (left aligned, no shadow)
    lea     rdi, [%1]
    lea     esi, [%2 + %3]
    mov     edx, %4
    mov     ecx, %5
    mov     r8d, %6
    call    ui_text_ink
%endmacro
%macro BTN 7                            ; label, xbase, xoff, ybase, yoff, w, enabled -> eax clicked
    lea     rdi, [%1]
    lea     esi, [%2 + %3]
    lea     edx, [%4 + %5]
    mov     ecx, %6
    mov     r8d, %7
    call    ui_button
%endmacro
%macro FIELD 5                          ; textfield, xbase, xoff, y, w -> eax 1 on Enter
    lea     rdi, [%1]
    lea     esi, [%2 + %3]
    mov     edx, %4
    mov     ecx, %5
    call    ui_textfield
%endmacro
%macro ENTER_FRAME 1                    ; frame with %1 bytes of locals (%1 = 8 mod 16)
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, %1
%endmacro
%macro LEAVE_FRAME 1
    add     rsp, %1
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
%endmacro
%macro GOTO 1                           ; leave the screen for state %1 (app_goto drops the text focus)
    mov     edi, %1
    call    app_goto
%endmacro

section .rodata
t_mp_title:     db "Multiplayer", 0
t_mp_host:      db "Open to Multiplayer", 0
t_name:         db "Name", 0
t_name_hint:    db "1-16 letters, digits or _", 0
t_target:       db "Room code or IP:port", 0
t_target_hint:  db "e.g. ABC123 or 192.168.1.20:27615", 0
t_join:         db "Join", 0
t_cancel:       db "Cancel", 0
t_back:         db "Back", 0
t_join_failed:  db "Could not join", 0
t_open:         db "Open", 0
t_pvp_off:      db "PvP: Off", 0
t_pvp_on:       db "PvP: On", 0
t_pvp_off_d:    db "Players cannot hurt each other", 0
t_pvp_on_d:     db "Players can hurt each other", 0
t_open_fail:    db "Could not open the game port (error ", 0
t_rparen:       db ")", 0
t_room_code:    db "Room code: ", 0
t_registering:  db "Registering...", 0
t_rv_fail:      db "Rendezvous unreachable - direct joins only", 0
t_direct:       db "Direct: ", 0
t_close_mp:     db "Close multiplayer", 0
t_done:         db "Done", 0
s_empty:        db 0

section .bss
alignb 8
tf_name:        resb TEXTFIELD_size     ; your name (join and host screens)
tf_target:      resb TEXTFIELD_size     ; the room code or IP:port to join
tf_chat:        resb TEXTFIELD_size     ; the chat bar
msg_buf:        resb 80                 ; a line built for the screen
join_failed:    resd 1                  ; net_join_begin refused the join
host_err:       resd 1                  ; errno of the last failed net_host_open, 0 none
mp_pvp:         resd 1                  ; the PvP choice made before the world is opened

section .text

; ---- helpers ---------------------------------------------------------------------------

; field_set(rdi TEXTFIELD*, rsi zstr, edx max): the field holds that text (cut to max characters)
; and takes no more than max
field_set:
    push    rbx
    mov     rbx, rdi
    mov     [rbx + TEXTFIELD.max], edx
    call    str_copy                    ; the buffer is the first member: rdi is already it
    sub     rax, rbx
    mov     [rbx + TEXTFIELD.len], eax
    pop     rbx
    ret

; has_text(rdi TEXTFIELD*) -> eax 1 when the text holds a character other than a space
has_text:
    mov     ecx, [rdi + TEXTFIELD.len]
    cmp     ecx, 32
    jbe     .len_ok
    mov     ecx, 32
.len_ok:
    xor     edx, edx
.scan:
    cmp     edx, ecx
    jae     .none
    cmp     byte [rdi + rdx], ' '
    jne     .some
    inc     edx
    jmp     .scan
.some:
    mov     eax, 1
    ret
.none:
    xor     eax, eax
    ret

; ---- join ----------------------------------------------------------------------------------

; screen_mp_join(): the join page over the dimmed title panorama. While a join runs (NJ_RV ..
; NJ_CONNECTED) the Join button is Cancel and the status line follows net_join_status; a failed
; join shows its reason in red. Join needs a valid name and a target; Enter in a field joins too.
; rbx = a join is running, r12d = cx, r13d = ui_h, r14d = the join state, r15d = Enter pressed
; [rsp] Join is possible
screen_mp_join:
    ENTER_FRAME 8
    mov     eax, [ui_w]
    shr     eax, 1
    mov     r12d, eax                   ; cx
    mov     r13d, [ui_h]
    cmp     dword [app_entered], 0
    je      .fields_ready
    mov     dword [app_entered], 0
    lea     rdi, [tf_name]
    lea     rsi, [net_cfg_name]
    mov     edx, NAME_MAX
    call    field_set
    lea     rdi, [tf_target]
    lea     rsi, [s_empty]
    mov     edx, TARGET_MAX
    call    field_set
    mov     dword [join_failed], 0
    lea     rax, [tf_target]
    mov     [ui_focus], rax
.fields_ready:
    lea     rdi, [t_mp_title]
    call    form_page
    INKL    t_name, r12, -100, 44, C_INK, 1
    FIELD   tf_name, r12, -100, 56, 200
    mov     r15d, eax                   ; Enter pressed in the name field ...
    INKL    t_name_hint, r12, -100, 80, C_INK_SOFT, 1
    INKL    t_target, r12, -100, 96, C_INK, 1
    FIELD   tf_target, r12, -100, 108, 200
    or      r15d, eax                   ; ... or in the target field
    INKL    t_target_hint, r12, -100, 132, C_INK_SOFT, 1
    lea     rdi, [net_ep]
    call    net_ep_join_state
    mov     r14d, eax                   ; NJ_*
    xor     ebx, ebx
    lea     eax, [r14 - NJ_RV]
    cmp     eax, NJ_CONNECTED - NJ_RV
    setbe   bl                          ; 1 while the join runs
    call    net_join_status             ; rax = the status line, empty when there is nothing to say
    cmp     byte [rax], 0
    jne     .status_text
    cmp     dword [join_failed], 0
    je      .no_status
    lea     rax, [t_join_failed]
.status_text:
    mov     rdi, rax
    mov     ecx, C_INK_SOFT
    mov     eax, C_RUBRIC
    cmp     r14d, NJ_FAILED
    cmove   ecx, eax
    cmp     dword [join_failed], 0
    cmovne  ecx, eax
    mov     esi, r12d
    mov     edx, 152
    mov     r8d, 1
    call    ui_text_ink_centered
.no_status:
    lea     rdi, [tf_name]              ; Join needs a valid name and a target
    call    net_valid_name
    cmp     dword [tf_target + TEXTFIELD.len], 0
    jne     .join_known
    xor     eax, eax
.join_known:
    mov     [rsp], eax
    test    ebx, ebx
    jnz     .running
    lea     rdi, [t_join]
    lea     esi, [r12 - 155]
    lea     edx, [r13 - 28]
    mov     ecx, 150
    mov     r8d, [rsp]
    call    ui_button
    test    eax, eax
    jnz     .start
    test    r15d, r15d
    jz      .back_button
    cmp     dword [rsp], 0
    jne     .start
    jmp     .back_button
.running:
    BTN     t_cancel, r12, -155, r13, -28, 150, 1
    test    eax, eax
    jz      .back_button
    call    net_join_cancel
    jmp     .ret
.back_button:
    BTN     t_back, r12, 5, r13, -28, 150, 1
    test    eax, eax
    jnz     .back
    cmp     dword [ui_input + UIINPUT.escape], 0
    je      .ret
.back:
    test    ebx, ebx
    jz      .leave
    call    net_join_cancel             ; leaving while the join runs gives it up
.leave:
    GOTO    ST_TITLE
    jmp     .ret
.start:
    lea     rdi, [net_cfg_name]
    lea     rsi, [tf_name]
    mov     edx, NAME_MAX
    call    str_copy
    call    net_cfg_save
    lea     rdi, [tf_target]
    lea     rsi, [tf_name]
    xor     edx, edx
    call    net_join_begin              ; 0, or the NJE_* that stopped it before it began
    test    eax, eax
    setnz   al
    movzx   eax, al
    mov     [join_failed], eax
.ret:
    LEAVE_FRAME 8

; ---- host ----------------------------------------------------------------------------------

; screen_mp_host(): from the pause menu. Not hosting: your name, the PvP choice, Open (which tries
; the game port: a failure shows its errno in red) and Back. Hosting: a leather plaque with the room
; code in gold (or "Registering..." / the rendezvous failure), the direct address, the live PvP
; switch, Close multiplayer and Done.
; rbx = scale of the room code / the name is valid, r12d = cx, r13d = ui_h, r15d = Enter pressed
screen_mp_host:
    ENTER_FRAME 8
    mov     eax, [ui_w]
    shr     eax, 1
    mov     r12d, eax                   ; cx
    mov     r13d, [ui_h]
    cmp     byte [net_role], NET_ROLE_HOST
    je      .hosting
    cmp     dword [app_entered], 0
    je      .fields_ready
    mov     dword [app_entered], 0
    lea     rdi, [tf_name]
    lea     rsi, [net_cfg_name]
    mov     edx, NAME_MAX
    call    field_set
    mov     dword [host_err], 0
    mov     dword [mp_pvp], 0
    lea     rax, [tf_name]
    mov     [ui_focus], rax
.fields_ready:
    lea     rdi, [t_mp_host]
    call    form_page
    INKL    t_name, r12, -100, 44, C_INK, 1
    FIELD   tf_name, r12, -100, 56, 200
    mov     r15d, eax                   ; Enter pressed in the name field
    INKL    t_name_hint, r12, -100, 80, C_INK_SOFT, 1
    lea     rdi, [t_pvp_off]
    lea     rax, [t_pvp_on]
    cmp     dword [mp_pvp], 0
    cmovne  rdi, rax
    lea     esi, [r12 - 100]
    mov     edx, 104
    mov     ecx, 200
    mov     r8d, 1
    call    ui_button
    test    eax, eax
    jz      .pvp_kept
    xor     dword [mp_pvp], 1
.pvp_kept:
    lea     rdi, [t_pvp_off_d]
    lea     rax, [t_pvp_on_d]
    cmp     dword [mp_pvp], 0
    cmovne  rdi, rax
    mov     esi, r12d
    mov     edx, 128
    mov     ecx, C_INK_SOFT
    mov     r8d, 1
    call    ui_text_ink_centered
    cmp     dword [host_err], 0
    je      .no_err
    lea     rdi, [msg_buf]              ; "Could not open the game port (error N)"
    lea     rsi, [t_open_fail]
    call    str_append
    mov     edi, [host_err]
    mov     rsi, rax
    call    i32_to_str
    mov     rdi, rax
    lea     rsi, [t_rparen]
    call    str_append
    mov     byte [rax], 0
    INKCA   msg_buf, r12, 0, 152, C_RUBRIC, 1
.no_err:
    lea     rdi, [tf_name]
    call    net_valid_name
    mov     ebx, eax                    ; Open needs a valid name
    BTN     t_open, r12, -155, r13, -28, 150, ebx
    test    eax, eax
    jnz     .open
    test    r15d, r15d
    jz      .not_enter
    test    ebx, ebx
    jnz     .open
.not_enter:
    BTN     t_back, r12, 5, r13, -28, 150, 1
    test    eax, eax
    jnz     .back
    cmp     dword [ui_input + UIINPUT.escape], 0
    je      .ret
.back:
    GOTO    ST_PAUSED
    jmp     .ret
.open:
    lea     rdi, [net_cfg_name]
    lea     rsi, [tf_name]
    mov     edx, NAME_MAX
    call    str_copy
    call    net_cfg_save
    mov     edi, [net_cfg_port]
    call    net_host_open               ; 0, or -errno
    test    eax, eax
    jz      .opened
    neg     eax
    mov     [host_err], eax
    jmp     .ret
.opened:
    mov     dword [host_err], 0
    mov     edi, [mp_pvp]
    call    net_set_pvp
    jmp     .ret

.hosting:
    mov     dword [app_entered], 0
    lea     rdi, [t_mp_title]
    call    form_page
    mov     edi, NINE_LEATHER           ; the plaque the room code hangs on
    lea     esi, [r12 - 150]
    mov     edx, 40
    mov     ecx, 300
    mov     r8d, 36
    call    ui_nine
    lea     rdi, [net_ep]
    call    net_ep_rv_state
    cmp     eax, RVS_OK
    je      .registered
    lea     rdi, [t_registering]
    mov     ecx, C_CREAM
    cmp     eax, RVS_FAIL
    jne     .plaque_text
    lea     rdi, [t_rv_fail]
    mov     ecx, C_RV_FAIL
.plaque_text:
    mov     esi, r12d
    mov     edx, 54
    mov     r8d, 1
    call    ui_text_centered
    jmp     .direct
.registered:
    lea     rdi, [msg_buf]              ; "Room code: ABC123", scale 3 when it fits the plaque, else 2
    lea     rsi, [t_room_code]
    call    str_append
    mov     rdi, rax
    lea     rsi, [net_room_code]
    call    str_append
    mov     byte [rax], 0
    lea     rdi, [msg_buf]
    mov     esi, 3
    call    ui_text_width
    mov     ebx, 3
    mov     edx, 46
    cmp     eax, 284
    jle     .scale_known
    mov     ebx, 2
    mov     edx, 50
.scale_known:
    lea     rdi, [msg_buf]
    mov     esi, r12d
    mov     ecx, C_GOLD_TEXT
    mov     r8d, ebx
    call    ui_text_centered
.direct:
    lea     rdi, [msg_buf]              ; "Direct: 192.168.1.20:27615"
    lea     rsi, [t_direct]
    call    str_append
    mov     rdi, rax
    lea     rsi, [net_lan_text]
    call    str_append
    mov     byte [rax], 0
    INKCA   msg_buf, r12, 0, 86, C_INK, 1
    movzx   ebx, byte [net_pvp]
    lea     rdi, [t_pvp_off]
    lea     rax, [t_pvp_on]
    test    ebx, ebx
    cmovnz  rdi, rax
    lea     esi, [r12 - 100]
    mov     edx, 104
    mov     ecx, 200
    mov     r8d, 1
    call    ui_button
    test    eax, eax
    jz      .pvp_shown
    xor     ebx, 1
    mov     edi, ebx
    call    net_set_pvp                 ; live: the host tells everyone
    jmp     .ret
.pvp_shown:
    lea     rdi, [t_pvp_off_d]
    lea     rax, [t_pvp_on_d]
    test    ebx, ebx
    cmovnz  rdi, rax
    mov     esi, r12d
    mov     edx, 128
    mov     ecx, C_INK_SOFT
    mov     r8d, 1
    call    ui_text_ink_centered
    BTN     t_close_mp, r12, -155, r13, -28, 150, 1
    test    eax, eax
    jz      .not_close
    call    net_host_close
    GOTO    ST_PAUSED
    jmp     .ret
.not_close:
    BTN     t_done, r12, 5, r13, -28, 150, 1
    test    eax, eax
    jnz     .done
    cmp     dword [ui_input + UIINPUT.escape], 0
    je      .ret
.done:
    GOTO    ST_PAUSED
.ret:
    LEAVE_FRAME 8

; ---- chat ------------------------------------------------------------------------------------

; screen_chat(): a dark bar over the bottom of the world with one text field that keeps the keyboard.
; The key that opened it typed its character in the very frame it was pressed: that frame's typed
; text is dropped. Enter sends a message that holds more than spaces (an empty one sends nothing)
; and returns to the game, so does Escape. The log above the bar is the HUD's.
; r12d = 0 (the field's x base), r14d = the field's y, r15d = its width
screen_chat:
    ENTER_FRAME 8
    cmp     dword [app_entered], 0
    je      .ready
    mov     dword [app_entered], 0
    mov     byte [tf_chat + TEXTFIELD.buf], 0
    mov     dword [tf_chat + TEXTFIELD.len], 0
    mov     dword [tf_chat + TEXTFIELD.max], CHAT_MAX
    mov     dword [ui_input + UIINPUT.typed_len], 0
.ready:
    lea     rax, [tf_chat]
    mov     [ui_focus], rax
    xor     edi, edi
    mov     esi, [ui_h]
    sub     esi, 26
    mov     edx, [ui_w]
    mov     ecx, 26
    mov     r8d, C_BAR
    call    ui_rect
    xor     r12d, r12d
    mov     r14d, [ui_h]
    sub     r14d, 23
    mov     r15d, [ui_w]
    sub     r15d, 8
    FIELD   tf_chat, r12, 4, r14d, r15d
    test    eax, eax
    jz      .no_enter
    lea     rdi, [tf_chat]
    call    has_text
    test    eax, eax
    jz      .close
    lea     rdi, [tf_chat]
    call    net_chat_send
.close:
    GOTO    ST_PLAYING
    jmp     .ret
.no_enter:
    cmp     dword [ui_input + UIINPUT.escape], 0
    je      .ret
    GOTO    ST_PLAYING
.ret:
    LEAVE_FRAME 8
