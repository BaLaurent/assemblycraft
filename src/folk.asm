; folk.asm - faction folk: every faction member is one MOB_FOLK mob whose MOB.faction, .role and
; .fclass (common.inc ROLE_*, FCLASS_*) say who it is. Spawning and what a right-click on one
; opens live here.
%include "common.inc"
default rel

global folk_spawn, folk_interact

extern mobs, mob_spawn

section .text

; folk_spawn(edi faction, esi role, edx fclass, xmm0 x, xmm1 y, xmm2 z) -> eax slot index, or -1
; (no free slot): a MOB_FOLK at (x, y, z), home there, with that faction, role and class
folk_spawn:
    push    rbx
    push    r12
    push    r13
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     edi, MOB_FOLK
    call    mob_spawn
    test    eax, eax
    js      .ret
    imul    ecx, eax, MOB_size
    lea     rdx, [mobs]
    add     rdx, rcx
    mov     [rdx + MOB.faction], bl
    mov     [rdx + MOB.role], r12b
    mov     [rdx + MOB.fclass], r13b
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; folk_interact(edi slot) -> eax the ST_* screen a right-click on that folk opens, or 0: a leader
; opens the dialog, a trader the trade screen; anything else (or an empty or bad slot) nothing
folk_interact:
    xor     eax, eax
    cmp     edi, MAX_MOBS
    jae     .ret
    imul    ecx, edi, MOB_size
    lea     rdx, [mobs]
    add     rdx, rcx
    cmp     dword [rdx + MOB.type], MOB_FOLK
    jne     .ret
    movzx   ecx, byte [rdx + MOB.role]
    mov     r8d, ST_DIALOG
    cmp     ecx, ROLE_LEADER
    cmove   eax, r8d
    mov     r8d, ST_TRADE
    cmp     ecx, ROLE_TRADER
    cmove   eax, r8d
.ret:
    ret
