; dmgnum.asm - floating combat text: damage numbers (coloured by element, crits larger, DoT ticks
; smaller and translucent) and the words PARRY!, BLOCKED, DODGED, STUNNED, FROZEN and IMMUNE.
; 32 entries; each rises 0.6 blocks/s for 50 fixed steps and is drawn by the HUD at world_to_ui of
; its position, fading over its last 15 steps. When every entry is taken the oldest is replaced.
; Nothing here is saved or random.
%include "common.inc"
default rel

global dmgnum_clear, dmgnum_spawn, dmgnum_text, dmgnum_step, dmgnum_draw
global dmgnum_count, dmgnum_list, dmgnum_style

extern world_to_ui, ui_text_centered, i32_to_str

%define MAX_DMGNUM  32
%define DMG_LIFE    50                  ; steps an entry lives
%define DMG_FADE    15                  ; alpha fades over the last steps of the life
%define DOT_ALPHA   217                 ; HF_DOT numbers draw at 85% of the opacity (255 * 0.85)
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
    .flags: resd 1                      ; the combat_hit_flags of a number (HF_*), 0 for a word
endstruc                                ; 28 bytes
%if DMGNUM_size != 28 || DMGNUM.y != 4 || DMGNUM.value != 20 || DMGNUM.flags != 24
%error "test_hud.asm mirrors this layout (DN_Y, DN_VALUE, DN_FLAGS, DN_SIZE)"
%endif

section .rodata
align 4
c_rise:     dd 0.01                     ; 0.6 blocks/s over a 1/60 s step
s_parry:    db "PARRY!", 0
s_blocked:  db "BLOCKED", 0
s_dodged:   db "DODGED", 0
s_stunned:  db "STUNNED", 0
s_frozen:   db "FROZEN", 0
s_immune:   db "IMMUNE", 0
align 4
; number colours by element (ELEM_PHYS .. ELEM_POISON); alpha comes from the fade
elem_rgb:
    dd RGBA(255, 255, 255, 0)
    dd RGBA(255, 140, 40, 0)
    dd RGBA(130, 200, 255, 0)
    dd RGBA(255, 240, 90, 0)
    dd RGBA(120, 220, 80, 0)
c_crit_phys: dd RGBA(255, 220, 60, 0)   ; a physical crit is gold
c_dot_phys:  dd RGBA(220, 50, 50, 0)    ; a physical damage-over-time tick (bleed) is red
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
    dq s_frozen
    dd RGBA(130, 200, 255, 0), 1
    dq s_immune
    dd RGBA(200, 200, 200, 0), 1

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
; flags & HF_CRIT makes it a crit (larger); the HF_* element and HF_DOT bits pick its colour and size
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
    mov     [rax + DMGNUM.flags], esi
    ret

; dmgnum_text(xmm0 x, xmm1 y, xmm2 z, edi txt): TXT_PARRY .. TXT_IMMUNE at a world position;
; an unknown id is ignored
dmgnum_text:
    cmp     edi, TXT_IMMUNE
    ja      .ret
    call    dmg_alloc
    movss   [rax + DMGNUM.x], xmm0
    movss   [rax + DMGNUM.y], xmm1
    movss   [rax + DMGNUM.z], xmm2
    mov     dword [rax + DMGNUM.age], 0
    mov     [rax + DMGNUM.value], edi
    mov     dword [rax + DMGNUM.kind], DK_TEXT
    mov     dword [rax + DMGNUM.flags], 0
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

; dmgnum_style(rdi DMGNUM*) -> eax rgb (alpha byte 0), edx scale, ecx alpha cap (0..255)
; A word takes its txt_table row. A number takes the colour of its element (HF_ELEM_MASK bits of the
; flags: phys white, fire orange, frost blue, shock yellow, poison green) at scale 1. A crit is scale 2,
; gold when physical. An HF_DOT tick (it wins over a crit) is scale 1 at 85% alpha, red when physical.
dmgnum_style:
    cmp     dword [rdi + DMGNUM.kind], DK_TEXT
    jne     .number
    mov     eax, [rdi + DMGNUM.value]
    shl     eax, 4
    lea     rcx, [txt_table]
    mov     edx, [rcx + rax + 12]
    mov     eax, [rcx + rax + 8]
    mov     ecx, 255
    ret
.number:
    mov     r8d, [rdi + DMGNUM.flags]
    and     r8d, HF_ELEM_MASK
    shr     r8d, HF_ELEM_SHIFT
    cmp     r8d, NUM_ELEMS - 1
    jbe     .elem
    xor     r8d, r8d                    ; an unknown element draws as physical
.elem:
    lea     rcx, [elem_rgb]
    mov     eax, [rcx + r8*4]
    mov     edx, 1
    mov     ecx, 255
    test    dword [rdi + DMGNUM.flags], HF_DOT
    jnz     .dot
    cmp     dword [rdi + DMGNUM.kind], DK_CRIT
    jne     .ret
    mov     edx, 2
    test    r8d, r8d
    jnz     .ret
    mov     eax, [c_crit_phys]
.ret:
    ret
.dot:
    mov     ecx, DOT_ALPHA
    test    r8d, r8d
    jnz     .ret
    mov     eax, [c_dot_phys]
    ret

; dmgnum_draw(): every entry in front of the camera, centred on its projected position, styled by
; dmgnum_style
; rbx = entry, r12 = end, r13 = text, r14d = rgb, r15d = scale; [rsp] out x, y; [rsp+8] number text;
; [rsp+24] alpha cap
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
    cmp     dword [rbx + DMGNUM.kind], DK_TEXT
    je      .word
    lea     r13, [rsp + 8]
    mov     edi, [rbx + DMGNUM.value]
    mov     rsi, r13
    call    i32_to_str
    mov     byte [rax], 0
    jmp     .style
.word:
    mov     eax, [rbx + DMGNUM.value]
    shl     eax, 4
    lea     rcx, [txt_table]
    mov     r13, [rcx + rax]
.style:
    mov     rdi, rbx
    call    dmgnum_style
    mov     r14d, eax
    mov     r15d, edx
    mov     [rsp + 24], ecx
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
    imul    ecx, [rsp + 24]             ; times the style's alpha cap / 255
    mov     eax, ecx
    xor     edx, edx
    mov     ecx, 255
    div     ecx
    mov     ecx, eax
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
