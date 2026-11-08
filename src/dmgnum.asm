; dmgnum.asm - floating combat text: damage numbers (crits larger and gold) and the words
; PARRY!, BLOCKED, DODGED and STUNNED. 32 entries; each rises 0.6 blocks/s for 50 fixed steps
; and is drawn by the HUD at world_to_ui of its position, fading over its last 15 steps.
; When every entry is taken the oldest is replaced. Nothing here is saved or random.
%include "common.inc"
default rel

global dmgnum_clear, dmgnum_spawn, dmgnum_text, dmgnum_step, dmgnum_draw
global dmgnum_count, dmgnum_list

extern world_to_ui, ui_text_centered, i32_to_str

%define MAX_DMGNUM  32
%define DMG_LIFE    50                  ; steps an entry lives
%define DMG_FADE    15                  ; alpha fades over the last steps of the life

%define DK_FREE     0                   ; DMGNUM.kind
%define DK_NUMBER   1
%define DK_CRIT     2
%define DK_TEXT     3

; one floating text; x, y, z come first so an entry is also a float pos[3] for world_to_ui
struc DMGNUM
    .x:     resd 1                      ; floats, world position (y rises every step)
    .y:     resd 1
    .z:     resd 1
    .age:   resd 1                      ; steps since it appeared
    .kind:  resd 1
    .value: resd 1                      ; the amount, or the TXT_* id of a DK_TEXT
endstruc                                ; 24 bytes
%if DMGNUM_size != 24 || DMGNUM.y != 4 || DMGNUM.value != 20
%error "test_hud.asm mirrors this layout (DN_Y, DN_VALUE, DN_SIZE)"
%endif

section .rodata
align 4
c_rise:     dd 0.01                     ; 0.6 blocks/s over a 1/60 s step
s_parry:    db "PARRY!", 0
s_blocked:  db "BLOCKED", 0
s_dodged:   db "DODGED", 0
s_stunned:  db "STUNNED", 0
align 8
; by TXT_* id: string, colour (alpha comes from the fade), scale
txt_table:
    dq s_parry
    dd RGBA(255, 215, 0, 0), 2
    dq s_blocked
    dd RGBA(180, 180, 200, 0), 1
    dq s_dodged
    dd RGBA(150, 220, 255, 0), 1
    dq s_stunned
    dd RGBA(255, 160, 60, 0), 1

section .bss
alignb 4
dmgnum_list: resb MAX_DMGNUM * DMGNUM_size

section .text

; dmgnum_clear(): drop every floating text
dmgnum_clear:
    lea     rdi, [dmgnum_list]
    mov     ecx, MAX_DMGNUM * DMGNUM_size / 4
    xor     eax, eax
    rep     stosd
    ret

; dmgnum_count() -> eax live entries
dmgnum_count:
    xor     eax, eax
    lea     rcx, [dmgnum_list]
    lea     rdx, [dmgnum_list + MAX_DMGNUM * DMGNUM_size]
.l:
    cmp     dword [rcx + DMGNUM.kind], DK_FREE
    je      .n
    inc     eax
.n:
    add     rcx, DMGNUM_size
    cmp     rcx, rdx
    jb      .l
    ret

; dmg_alloc() -> rax a free entry, else the oldest (the first of equal age); clobbers rcx, rdx, r8
dmg_alloc:
    lea     rax, [dmgnum_list]
    lea     rcx, [dmgnum_list + MAX_DMGNUM * DMGNUM_size]
    mov     rdx, rax                    ; oldest so far
.scan:
    cmp     dword [rax + DMGNUM.kind], DK_FREE
    je      .ret                        ; a free entry: take it
    mov     r8d, [rax + DMGNUM.age]
    cmp     r8d, [rdx + DMGNUM.age]
    jle     .keep
    mov     rdx, rax
.keep:
    add     rax, DMGNUM_size
    cmp     rax, rcx
    jb      .scan
    mov     rax, rdx                    ; all taken: reuse the oldest
.ret:
    ret

; dmgnum_spawn(xmm0 x, xmm1 y, xmm2 z, edi amount, esi flags): a damage number at a world position;
; flags & HF_CRIT makes it a crit (larger, gold)
dmgnum_spawn:
    call    dmg_alloc
    movss   [rax + DMGNUM.x], xmm0
    movss   [rax + DMGNUM.y], xmm1
    movss   [rax + DMGNUM.z], xmm2
    mov     dword [rax + DMGNUM.age], 0
    mov     [rax + DMGNUM.value], edi
    mov     ecx, DK_NUMBER
    mov     edx, DK_CRIT
    test    esi, HF_CRIT
    cmovnz  ecx, edx
    mov     [rax + DMGNUM.kind], ecx
    ret

; dmgnum_text(xmm0 x, xmm1 y, xmm2 z, edi txt): TXT_PARRY .. TXT_STUNNED at a world position;
; an unknown id is ignored
dmgnum_text:
    cmp     edi, TXT_STUNNED
    ja      .ret
    call    dmg_alloc
    movss   [rax + DMGNUM.x], xmm0
    movss   [rax + DMGNUM.y], xmm1
    movss   [rax + DMGNUM.z], xmm2
    mov     dword [rax + DMGNUM.age], 0
    mov     [rax + DMGNUM.value], edi
    mov     dword [rax + DMGNUM.kind], DK_TEXT
.ret:
    ret

; dmgnum_step(): once per fixed step; every entry rises and ages, and the 50th step frees it
dmgnum_step:
    lea     rax, [dmgnum_list]
    lea     rcx, [dmgnum_list + MAX_DMGNUM * DMGNUM_size]
    movss   xmm1, [c_rise]
.l:
    cmp     dword [rax + DMGNUM.kind], DK_FREE
    je      .n
    movss   xmm0, [rax + DMGNUM.y]
    addss   xmm0, xmm1
    movss   [rax + DMGNUM.y], xmm0
    inc     dword [rax + DMGNUM.age]
    cmp     dword [rax + DMGNUM.age], DMG_LIFE
    jb      .n
    mov     dword [rax + DMGNUM.kind], DK_FREE
.n:
    add     rax, DMGNUM_size
    cmp     rax, rcx
    jb      .l
    ret

; dmgnum_draw(): every entry in front of the camera, centred on its projected position;
; numbers white (crit: gold at scale 2), words from txt_table
; rbx = entry, r12 = end, r13 = text, r14d = rgba, r15d = scale; [rsp] out x, y; [rsp+8] number text
dmgnum_draw:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40
    lea     rbx, [dmgnum_list]
    lea     r12, [dmgnum_list + MAX_DMGNUM * DMGNUM_size]
.entry:
    mov     eax, [rbx + DMGNUM.kind]
    test    eax, eax
    jz      .next
    mov     rdi, rbx
    mov     rsi, rsp
    call    world_to_ui
    test    eax, eax
    jz      .next
    mov     eax, [rbx + DMGNUM.kind]
    cmp     eax, DK_TEXT
    je      .word
    lea     r13, [rsp + 8]
    mov     edi, [rbx + DMGNUM.value]
    mov     rsi, r13
    call    i32_to_str
    mov     byte [rax], 0
    mov     r14d, RGBA(255, 255, 255, 0)
    mov     r15d, 1
    cmp     dword [rbx + DMGNUM.kind], DK_CRIT
    jne     .alpha
    mov     r14d, RGBA(255, 220, 60, 0)
    mov     r15d, 2
    jmp     .alpha
.word:
    mov     eax, [rbx + DMGNUM.value]
    shl     eax, 4
    lea     rcx, [txt_table]
    add     rcx, rax
    mov     r13, [rcx]
    mov     r14d, [rcx + 8]
    mov     r15d, [rcx + 12]
.alpha:
    mov     eax, DMG_LIFE
    sub     eax, [rbx + DMGNUM.age]     ; steps left
    mov     ecx, 255
    cmp     eax, DMG_FADE
    jae     .opaque
    imul    eax, eax, 255
    xor     edx, edx
    mov     ecx, DMG_FADE
    div     ecx                         ; 255 * left / 15
    mov     ecx, eax
.opaque:
    shl     ecx, 24
    or      ecx, r14d                   ; rgba with the fade in the alpha byte
    mov     rdi, r13
    mov     esi, [rsp]
    mov     edx, r15d
    shl     edx, 2                      ; half the glyph height: centred on the anchor
    neg     edx
    add     edx, [rsp + 4]
    mov     r8d, r15d
    call    ui_text_centered
.next:
    add     rbx, DMGNUM_size
    cmp     rbx, r12
    jb      .entry
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
