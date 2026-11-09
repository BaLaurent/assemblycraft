; test_ui.asm - the pure geometry of the nine-slice frames (ui_nine_layout).
%include "common.inc"
default rel

global test_ui_nine_layout

extern ui_nine_layout

%define COV_MAX 30000

section .bss
alignb 4
t_buf:  resb NINE_MAX_QUADS * 32
t_cov:  resb COV_MAX                    ; how often each unit of the rectangle is covered

section .text

; t_check(edi w, esi h, edx b) -> eax record count, or -1 when a record is out of range, has
; a texel span different from its unit span, or the records do not cover every unit exactly once
t_check:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r12d, edi
    mov     r13d, esi
    mov     r15d, edx
    mov     ecx, r12d
    imul    ecx, r13d                   ; w * h
    cmp     ecx, COV_MAX
    ja      .bad
    lea     rdi, [t_cov]
    xor     eax, eax
    rep stosb
    lea     rdi, [t_buf]
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, r15d
    call    ui_nine_layout
    mov     r14d, eax                   ; n
    lea     rbx, [t_buf]
    xor     r15d, r15d
.rec:
    cmp     r15d, r14d
    jae     .verify
    mov     eax, [rbx]                  ; x0
    mov     ecx, [rbx + 4]              ; y0
    mov     edx, [rbx + 8]              ; x1
    mov     esi, [rbx + 12]             ; y1
    mov     r8d, [rbx + 16]             ; u0
    mov     r9d, [rbx + 20]             ; v0
    mov     r10d, [rbx + 24]            ; u1
    mov     r11d, [rbx + 28]            ; v1
    cmp     eax, edx
    jae     .bad                        ; unsigned: also rejects x0 < 0
    cmp     edx, r12d
    ja      .bad
    cmp     ecx, esi
    jae     .bad
    cmp     esi, r13d
    ja      .bad
    cmp     r8d, r10d
    jae     .bad
    cmp     r10d, 16
    ja      .bad
    cmp     r9d, r11d
    jae     .bad
    cmp     r11d, 16
    ja      .bad
    sub     r10d, r8d
    mov     edi, edx
    sub     edi, eax
    cmp     r10d, edi
    jne     .bad                        ; one texel per unit across
    sub     r11d, r9d
    mov     edi, esi
    sub     edi, ecx
    cmp     r11d, edi
    jne     .bad                        ; and down
.fill_y:
    cmp     ecx, esi
    jae     .next
    mov     r8d, eax
.fill_x:
    cmp     r8d, edx
    jae     .y_next
    mov     r9d, ecx
    imul    r9d, r12d
    add     r9d, r8d
    lea     r10, [t_cov]
    inc     byte [r10 + r9]
    inc     r8d
    jmp     .fill_x
.y_next:
    inc     ecx
    jmp     .fill_y
.next:
    add     rbx, 32
    inc     r15d
    jmp     .rec
.verify:
    mov     ecx, r12d
    imul    ecx, r13d
    lea     rdi, [t_cov]
.cell:
    test    ecx, ecx
    jz      .good
    dec     ecx
    cmp     byte [rdi + rcx], 1
    jne     .bad
    jmp     .cell
.good:
    mov     eax, r14d
    jmp     .ret
.bad:
    mov     eax, -1
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; test_ui_nine_layout: an 18 x 18 frame with border 2 is 16 records (4 corners, 8 edge pieces,
; 4 centre pieces); 176 x 166 with border 4 is 23 x 22 = 506 records covering every unit once
; with the strip repeated and the last repeat cut short; 6 x 30 and 30 x 6 clamp the border to 3
; (10 records, first corner 3 wide); 3000 x 10 is 376 x 3 = 1128 records (no per-axis cap); a
; zero-sized rectangle has no records.
test_ui_nine_layout:
    push    rbp
    mov     rbp, rsp
    mov     edi, 18
    mov     esi, 18
    mov     edx, 2
    call    t_check
    cmp     eax, 16
    jne     .fail
    mov     edi, 176
    mov     esi, 166
    mov     edx, 4
    call    t_check
    cmp     eax, 506
    jne     .fail
    mov     edi, 6
    mov     esi, 30
    mov     edx, 4
    call    t_check
    cmp     eax, 10
    jne     .fail
    cmp     dword [t_buf + 8], 3        ; first corner: x1 = clamped border
    jne     .fail
    cmp     dword [t_buf + 24], 3       ; u1 = 3
    jne     .fail
    mov     edi, 30
    mov     esi, 6
    mov     edx, 4
    call    t_check
    cmp     eax, 10
    jne     .fail
    mov     edi, 3000                   ; 374 strip repeats: past any per-axis cap of 256
    mov     esi, 10
    mov     edx, 4
    call    t_check
    cmp     eax, 1128
    jne     .fail
    mov     edi, 0
    mov     esi, 10
    mov     edx, 4
    call    t_check
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret
