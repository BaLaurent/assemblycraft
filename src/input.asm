; input.asm - GLFW keyboard/mouse input: FRAMEINPUT for the game (only while the cursor
; is captured) and UIINPUT for the menus (every frame). Callbacks only queue events;
; input_poll turns them into one snapshot per frame.
%include "common.inc"
%include "gl.inc"
default rel

global frame_input, ui_input, input_captured
global input_init, input_poll, input_set_captured

extern settings

section .rodata
align 8
d_double_click: dq 0.4

section .data
align 4
pending_key: dd -1                      ; last key pressed since the previous poll

section .bss
alignb 8
frame_input:    resb FRAMEINPUT_size
alignb 8
ui_input:       resb UIINPUT_size
alignb 8
scroll_accum:   resq 1                  ; double, wheel steps not yet reported
base_x:         resq 1                  ; double cursor baseline (captured look)
base_y:         resq 1
cur_x:          resq 1
cur_y:          resq 1
last_click_t:   resq 1                  ; double time of the previous lmb press
input_captured: resd 1
suppress:       resd 1                  ; capture click: ignore buttons until both released
pending_bs:     resd 1
pending_enter:  resd 1
pending_esc:    resd 1
pending_lmb:    resd 1                  ; left presses since the previous poll
pending_rmb:    resd 1
pending_len:    resd 1
pending_typed:  resb 32
win_w:          resd 1
win_h:          resd 1
fb_w:           resd 1
fb_h:           resd 1
last_click_x:   resd 1
last_click_y:   resd 1
prev_lmb:       resd 1
prev_rmb:       resd 1
prev_mmb:       resd 1
prev_inv:       resd 1
prev_f3:        resd 1
prev_f11:       resd 1
prev_fly:       resd 1
prev_reload:    resd 1
prev_num:       resd 9

section .text

; scroll_cb(rdi window, xmm0 xoffset, xmm1 yoffset)
scroll_cb:
    addsd   xmm1, [scroll_accum]
    movsd   [scroll_accum], xmm1
    ret

; key_cb(rdi window, esi key, edx scancode, ecx action, r8d mods)
key_cb:
    cmp     ecx, GLFW_RELEASE
    je      .ret
    cmp     esi, KEY_BACKSPACE
    jne     .not_bs
    inc     dword [pending_bs]          ; press and repeat
.not_bs:
    cmp     ecx, GLFW_PRESS
    jne     .ret
    mov     [pending_key], esi
    cmp     esi, KEY_ENTER
    je      .enter
    cmp     esi, KEY_KP_ENTER
    jne     .not_enter
.enter:
    mov     dword [pending_enter], 1
.not_enter:
    cmp     esi, KEY_ESCAPE
    jne     .ret
    mov     dword [pending_esc], 1
.ret:
    ret

; char_cb(rdi window, esi codepoint): printable ASCII only
char_cb:
    cmp     esi, 32
    jb      .ret
    cmp     esi, 126
    ja      .ret
    mov     eax, [pending_len]
    cmp     eax, 32
    jae     .ret
    mov     [pending_typed + rax], sil
    inc     dword [pending_len]
.ret:
    ret

; mouse_cb(rdi window, esi button, edx action, ecx mods): count presses
mouse_cb:
    cmp     edx, GLFW_PRESS
    jne     .ret
    cmp     esi, MOUSE_LEFT
    jne     .not_left
    inc     dword [pending_lmb]
    ret
.not_left:
    cmp     esi, MOUSE_RIGHT
    jne     .ret
    inc     dword [pending_rmb]
.ret:
    ret

; input_init(rdi window): callbacks, sticky state, cursor released
input_init:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdi
    lea     rsi, [scroll_cb]
    call    glfwSetScrollCallback
    mov     rdi, rbx
    lea     rsi, [key_cb]
    call    glfwSetKeyCallback
    mov     rdi, rbx
    lea     rsi, [char_cb]
    call    glfwSetCharCallback
    mov     rdi, rbx
    lea     rsi, [mouse_cb]
    call    glfwSetMouseButtonCallback
    ; sticky state: a tap released before the next poll still reads as one press
    mov     rdi, rbx
    mov     esi, GLFW_STICKY_KEYS
    mov     edx, GLFW_TRUE
    call    glfwSetInputMode
    mov     rdi, rbx
    mov     esi, GLFW_STICKY_MOUSE_BUTTONS
    mov     edx, GLFW_TRUE
    call    glfwSetInputMode
    mov     rdi, rbx
    xor     esi, esi
    call    input_set_captured
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; input_set_captured(rdi window, esi on): lock/release the cursor. Capturing resets the
; look baseline and ignores mouse buttons until both are released (the click that
; resumed the game must not also break a block).
input_set_captured:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12d, esi
    mov     rdi, rbx
    mov     esi, GLFW_CURSOR
    mov     edx, GLFW_CURSOR_NORMAL
    test    r12d, r12d
    jz      .mode
    mov     edx, GLFW_CURSOR_DISABLED
.mode:
    call    glfwSetInputMode
    test    r12d, r12d
    jz      .store
    call    glfwRawMouseMotionSupported
    test    eax, eax
    jz      .no_raw
    mov     rdi, rbx
    mov     esi, GLFW_RAW_MOUSE_MOTION
    mov     edx, GLFW_TRUE
    call    glfwSetInputMode
.no_raw:
    mov     dword [suppress], 1
.store:
    mov     rdi, rbx
    lea     rsi, [base_x]
    lea     rdx, [base_y]
    call    glfwGetCursorPos
    xor     eax, eax
    mov     [scroll_accum], rax
    mov     [input_captured], r12d
    pop     r12
    pop     rbx
    pop     rbp
    ret

; KEY key -> eax = 1 if held (window in rbx); key may be a register or immediate
%macro KEY 1
    mov     rdi, rbx
    mov     esi, %1
    call    glfwGetKey
    cmp     eax, GLFW_PRESS
    sete    al
    movzx   eax, al
%endmacro

; BIND idx -> eax = 1 if the bound key is held
%macro BIND 1
    KEY     [settings + SETTINGS.keys + (%1)*4]
%endmacro

; BUTTON button -> eax = 1 if held
%macro BUTTON 1
    mov     rdi, rbx
    mov     esi, %1
    call    glfwGetMouseButton
    cmp     eax, GLFW_PRESS
    sete    al
    movzx   eax, al
%endmacro

; EDGE prev -> edx = rising edge of eax; prev = eax (eax preserved)
%macro EDGE 1
    mov     edx, [%1]
    not     edx
    and     edx, eax
    mov     [%1], eax
%endmacro

; input_poll(rdi window): call after glfwPollEvents
input_poll:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     rbx, rdi
    lea     rdi, [frame_input]
    mov     ecx, FRAMEINPUT_size
    xor     eax, eax
    rep     stosb
    lea     rdi, [ui_input]
    mov     ecx, UIINPUT_size
    rep     stosb
    mov     dword [frame_input + FRAMEINPUT.slot], -1

    ; queued callback events
    mov     eax, [pending_key]
    mov     [ui_input + UIINPUT.key_pressed], eax
    mov     dword [pending_key], -1
    xor     eax, eax
    xchg    eax, [pending_bs]
    mov     [ui_input + UIINPUT.backspace], eax
    xor     eax, eax
    xchg    eax, [pending_enter]
    mov     [ui_input + UIINPUT.enter], eax
    xor     eax, eax
    xchg    eax, [pending_esc]
    mov     [ui_input + UIINPUT.escape], eax
    mov     ecx, [pending_len]
    mov     [ui_input + UIINPUT.typed_len], ecx
    mov     dword [pending_len], 0
    lea     rsi, [pending_typed]
    lea     rdi, [ui_input + UIINPUT.typed]
    rep     movsb

    ; cursor in framebuffer pixels
    mov     rdi, rbx
    lea     rsi, [cur_x]
    lea     rdx, [cur_y]
    call    glfwGetCursorPos
    mov     rdi, rbx
    lea     rsi, [win_w]
    lea     rdx, [win_h]
    call    glfwGetWindowSize
    mov     rdi, rbx
    lea     rsi, [fb_w]
    lea     rdx, [fb_h]
    call    glfwGetFramebufferSize
    mov     eax, [win_w]
    test    eax, eax
    jle     .cursor_done
    mov     eax, [win_h]
    test    eax, eax
    jle     .cursor_done
    cvtsi2sd xmm0, dword [fb_w]
    cvtsi2sd xmm1, dword [win_w]
    divsd   xmm0, xmm1
    mulsd   xmm0, [cur_x]
    cvttsd2si eax, xmm0
    mov     [ui_input + UIINPUT.mouse_px], eax
    cvtsi2sd xmm0, dword [fb_h]
    cvtsi2sd xmm1, dword [win_h]
    divsd   xmm0, xmm1
    mulsd   xmm0, [cur_y]
    cvttsd2si eax, xmm0
    mov     [ui_input + UIINPUT.mouse_py], eax
.cursor_done:

    ; mouse buttons: edges are tracked every frame so capture changes never fake an edge;
    ; presses counted by the callback also catch clicks shorter than a frame
    BUTTON  MOUSE_LEFT
    EDGE    prev_lmb
    mov     r12d, eax                   ; lmb held
    mov     r13d, edx                   ; lmb pressed
    xor     eax, eax
    xchg    eax, [pending_lmb]
    cmp     eax, 2
    jb      .one_lmb
    mov     dword [ui_input + UIINPUT.double_click], 1 ; two presses within one frame
.one_lmb:
    test    eax, eax
    setnz   al
    movzx   eax, al
    or      r13d, eax
    BUTTON  MOUSE_RIGHT
    EDGE    prev_rmb
    mov     r14d, eax                   ; rmb held
    mov     r15d, edx                   ; rmb pressed
    xor     eax, eax
    xchg    eax, [pending_rmb]
    test    eax, eax
    setnz   al
    movzx   eax, al
    or      r15d, eax
    mov     [ui_input + UIINPUT.lmb_held], r12d
    mov     [ui_input + UIINPUT.lmb_pressed], r13d
    mov     [ui_input + UIINPUT.rmb_pressed], r15d
    KEY     KEY_LEFT_SHIFT
    mov     [rsp], eax
    KEY     KEY_RIGHT_SHIFT
    or      eax, [rsp]
    mov     [ui_input + UIINPUT.shift], eax

    ; double click: a second press within 0.4 s and 4 px of the previous one
    cmp     dword [ui_input + UIINPUT.double_click], 0
    jne     .no_click
    test    r13d, r13d
    jz      .no_click
    call    glfwGetTime
    movsd   xmm1, xmm0
    subsd   xmm1, [last_click_t]
    movsd   [last_click_t], xmm0
    mov     eax, [ui_input + UIINPUT.mouse_px]
    mov     ecx, [ui_input + UIINPUT.mouse_py]
    mov     edx, eax
    sub     edx, [last_click_x]
    mov     [last_click_x], eax
    mov     eax, ecx
    sub     eax, [last_click_y]
    mov     [last_click_y], ecx
    comisd  xmm1, [d_double_click]
    jae     .no_click
    mov     ecx, edx                    ; |dx| <= 4
    neg     ecx
    cmovs   ecx, edx
    cmp     ecx, 4
    jg      .no_click
    mov     ecx, eax                    ; |dy| <= 4
    neg     ecx
    cmovs   ecx, eax
    cmp     ecx, 4
    jg      .no_click
    mov     dword [ui_input + UIINPUT.double_click], 1
    xorpd   xmm0, xmm0                  ; a third click starts a new pair
    movsd   [last_click_t], xmm0
.no_click:

    ; edges reported in every state
    BIND    BIND_INVENTORY
    EDGE    prev_inv
    mov     [frame_input + FRAMEINPUT.inventory], edx
    KEY     KEY_F3
    EDGE    prev_f3
    mov     [frame_input + FRAMEINPUT.debug], edx
    KEY     KEY_F11
    EDGE    prev_f11
    mov     [frame_input + FRAMEINPUT.fullscreen], edx
    BIND    BIND_RELOAD
    EDGE    prev_reload
    mov     [frame_input + FRAMEINPUT.reload], edx

    ; edges tracked always, reported only while captured
    BUTTON  MOUSE_MIDDLE
    EDGE    prev_mmb
    mov     [rsp], edx
    BIND    BIND_FLY
    EDGE    prev_fly
    mov     [rsp + 4], edx
    xor     ecx, ecx
.num:
    push    rcx
    push    rcx                         ; keep rsp 16-aligned for the call
    mov     rdi, rbx
    lea     esi, [KEY_1 + ecx]
    call    glfwGetKey
    pop     rcx
    pop     rcx
    cmp     eax, GLFW_PRESS
    sete    al
    movzx   eax, al
    mov     edx, [prev_num + rcx*4]
    not     edx
    and     edx, eax
    mov     [prev_num + rcx*4], eax
    test    edx, edx
    jz      .num_next
    cmp     dword [input_captured], 0
    je      .num_next
    mov     [frame_input + FRAMEINPUT.slot], ecx
.num_next:
    inc     ecx
    cmp     ecx, 9
    jb      .num

    cmp     dword [input_captured], 0
    jne     .captured

    ; menus: read the movement keys anyway so sticky presses from typing (W, A, S, D...)
    ; are consumed here instead of moving the player on the first captured frame
%assign b 0
%rep 7
    BIND    b
%assign b b + 1
%endrep
    ; menus: whole wheel steps go to the UI
    movsd   xmm0, [scroll_accum]
    cvttsd2si eax, xmm0
    mov     [ui_input + UIINPUT.scroll], eax
    cvtsi2sd xmm1, eax
    subsd   xmm0, xmm1
    movsd   [scroll_accum], xmm0
    jmp     .ret

.captured:
    mov     eax, [rsp]
    mov     [frame_input + FRAMEINPUT.mmb_pressed], eax
    mov     eax, [rsp + 4]
    mov     [frame_input + FRAMEINPUT.toggle_fly], eax
    ; buttons, ignoring the click that captured the mouse until both are released
    cmp     dword [suppress], 0
    je      .buttons
    mov     eax, r12d
    or      eax, r14d
    jnz     .suppressed
    mov     dword [suppress], 0
.suppressed:
    xor     r12d, r12d
    xor     r13d, r13d
    xor     r14d, r14d
    xor     r15d, r15d
    mov     dword [frame_input + FRAMEINPUT.mmb_pressed], 0
.buttons:
    mov     [frame_input + FRAMEINPUT.lmb_held], r12d
    mov     [frame_input + FRAMEINPUT.lmb_pressed], r13d
    mov     [frame_input + FRAMEINPUT.rmb_held], r14d
    mov     [frame_input + FRAMEINPUT.rmb_pressed], r15d

    ; movement from the bindings
    BIND    BIND_FORWARD
    mov     r12d, eax
    BIND    BIND_BACK
    sub     r12d, eax
    mov     [frame_input + FRAMEINPUT.move + INPUT.fwd], r12d
    BIND    BIND_RIGHT
    mov     r12d, eax
    BIND    BIND_LEFT
    sub     r12d, eax
    mov     [frame_input + FRAMEINPUT.move + INPUT.strafe], r12d
    BIND    BIND_JUMP
    mov     [frame_input + FRAMEINPUT.move + INPUT.jump], eax
    BIND    BIND_SNEAK
    mov     [frame_input + FRAMEINPUT.move + INPUT.down], eax
    BIND    BIND_SPRINT
    mov     [frame_input + FRAMEINPUT.move + INPUT.sprint], eax

    ; mouse look: delta from the baseline
    movsd   xmm0, [cur_x]
    subsd   xmm0, [base_x]
    cvtsd2ss xmm0, xmm0
    movss   [frame_input + FRAMEINPUT.look_dx], xmm0
    movsd   xmm0, [cur_y]
    subsd   xmm0, [base_y]
    cvtsd2ss xmm0, xmm0
    movss   [frame_input + FRAMEINPUT.look_dy], xmm0
    mov     rax, [cur_x]
    mov     [base_x], rax
    mov     rax, [cur_y]
    mov     [base_y], rax

    ; whole wheel steps
    movsd   xmm0, [scroll_accum]
    cvttsd2si eax, xmm0
    mov     [frame_input + FRAMEINPUT.scroll], eax
    cvtsi2sd xmm1, eax
    subsd   xmm0, xmm1
    movsd   [scroll_accum], xmm0
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
