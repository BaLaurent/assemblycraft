; input.asm - GLFW keyboard/mouse polling into one FRAMEINPUT per frame.
%include "common.inc"
%include "gl.inc"
default rel

global frame_input, input_init, input_poll

section .bss
alignb 8
frame_input:  resb FRAMEINPUT_size
alignb 8
scroll_accum: resq 1                    ; double, wheel steps not yet reported
base_x:       resq 1                    ; double cursor baseline
base_y:       resq 1
cur_x:        resq 1
cur_y:        resq 1
captured:     resd 1
suppress_lmb: resd 1                    ; the recapture click must not break a block
prev_esc:     resd 1
prev_f:       resd 1
prev_f5:      resd 1
prev_lmb:     resd 1
prev_rmb:     resd 1
prev_mmb:     resd 1
prev_num:     resd 9

section .text

; scroll_cb(rdi window, xmm0 xoffset, xmm1 yoffset)
scroll_cb:
    addsd   xmm1, [scroll_accum]
    movsd   [scroll_accum], xmm1
    ret

; input_init(rdi window)
input_init:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdi
    lea     rsi, [scroll_cb]
    call    glfwSetScrollCallback
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
    mov     esi, GLFW_CURSOR
    mov     edx, GLFW_CURSOR_DISABLED
    call    glfwSetInputMode
    call    glfwRawMouseMotionSupported
    test    eax, eax
    jz      .no_raw
    mov     rdi, rbx
    mov     esi, GLFW_RAW_MOUSE_MOTION
    mov     edx, GLFW_TRUE
    call    glfwSetInputMode
.no_raw:
    mov     rdi, rbx
    lea     rsi, [base_x]
    lea     rdx, [base_y]
    call    glfwGetCursorPos
    mov     dword [captured], 1
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; KEY key -> eax = 1 if held (window in rbx)
%macro KEY 1
    mov     rdi, rbx
    mov     esi, %1
    call    glfwGetKey
    cmp     eax, GLFW_PRESS
    sete    al
    movzx   eax, al
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
    mov     dword [frame_input + FRAMEINPUT.slot], -1

    ; Esc releases the mouse
    KEY     KEY_ESCAPE
    EDGE    prev_esc
    test    edx, edx
    jz      .esc_done
    cmp     dword [captured], 0
    je      .esc_done
    mov     rdi, rbx
    mov     esi, GLFW_CURSOR
    mov     edx, GLFW_CURSOR_NORMAL
    call    glfwSetInputMode
    mov     dword [captured], 0
.esc_done:

    ; edge state is tracked every frame so capture changes never fake an edge
    BUTTON  MOUSE_LEFT
    EDGE    prev_lmb
    mov     r12d, eax                   ; lmb held
    mov     r13d, edx                   ; lmb pressed
    BUTTON  MOUSE_RIGHT
    EDGE    prev_rmb
    mov     r14d, eax                   ; rmb held
    mov     r15d, edx                   ; rmb pressed
    BUTTON  MOUSE_MIDDLE
    EDGE    prev_mmb
    mov     [frame_input + FRAMEINPUT.mmb_pressed], edx
    KEY     KEY_F
    EDGE    prev_f
    mov     [frame_input + FRAMEINPUT.toggle_fly], edx
    KEY     KEY_F5
    EDGE    prev_f5
    mov     [frame_input + FRAMEINPUT.save], edx
    xor     ecx, ecx
.num:
    mov     [rsp], ecx
    mov     rdi, rbx
    lea     esi, [KEY_1 + ecx]
    call    glfwGetKey
    cmp     eax, GLFW_PRESS
    sete    al
    movzx   eax, al
    mov     ecx, [rsp]
    mov     edx, [prev_num + rcx*4]
    not     edx
    and     edx, eax
    mov     [prev_num + rcx*4], eax
    test    edx, edx
    jz      .num_next
    mov     [frame_input + FRAMEINPUT.slot], ecx
.num_next:
    inc     ecx
    cmp     ecx, 9
    jb      .num

    cmp     dword [captured], 0
    jne     .captured

    ; not captured: a left click recaptures; nothing else is reported
    lea     rdi, [frame_input]
    mov     ecx, FRAMEINPUT_size
    xor     eax, eax
    rep     stosb
    mov     dword [frame_input + FRAMEINPUT.slot], -1
    xor     eax, eax
    mov     [scroll_accum], rax
    test    r13d, r13d
    jz      .ret
    mov     rdi, rbx
    mov     esi, GLFW_CURSOR
    mov     edx, GLFW_CURSOR_DISABLED
    call    glfwSetInputMode
    mov     rdi, rbx
    lea     rsi, [base_x]
    lea     rdx, [base_y]
    call    glfwGetCursorPos
    mov     dword [captured], 1
    mov     dword [suppress_lmb], 1
    jmp     .ret

.captured:
    mov     dword [frame_input + FRAMEINPUT.captured], 1
    ; left button, ignoring the click that recaptured the mouse until released
    cmp     dword [suppress_lmb], 0
    je      .lmb
    test    r12d, r12d
    jnz     .lmb_suppressed
    mov     dword [suppress_lmb], 0
.lmb_suppressed:
    xor     r12d, r12d
    xor     r13d, r13d
.lmb:
    mov     [frame_input + FRAMEINPUT.lmb_held], r12d
    mov     [frame_input + FRAMEINPUT.lmb_pressed], r13d
    mov     [frame_input + FRAMEINPUT.rmb_held], r14d
    mov     [frame_input + FRAMEINPUT.rmb_pressed], r15d

    ; movement
    KEY     KEY_W
    mov     r12d, eax
    KEY     KEY_S
    sub     r12d, eax
    mov     [frame_input + FRAMEINPUT.move + INPUT.fwd], r12d
    KEY     KEY_D
    mov     r12d, eax
    KEY     KEY_A
    sub     r12d, eax
    mov     [frame_input + FRAMEINPUT.move + INPUT.strafe], r12d
    KEY     KEY_SPACE
    mov     [frame_input + FRAMEINPUT.move + INPUT.jump], eax
    KEY     KEY_LEFT_SHIFT
    mov     [frame_input + FRAMEINPUT.move + INPUT.down], eax
    KEY     KEY_LEFT_CONTROL
    mov     [frame_input + FRAMEINPUT.move + INPUT.sprint], eax

    ; mouse look: delta from the baseline
    mov     rdi, rbx
    lea     rsi, [cur_x]
    lea     rdx, [cur_y]
    call    glfwGetCursorPos
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
