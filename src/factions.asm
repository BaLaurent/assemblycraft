; factions.asm - the five factions: standing with each (a signed int16 per faction in the world
; header), the tiers it falls into, the rivalries that move it, and the tribute paid at a shrine.
; Villagers, Bandits, Ashen Cult, Beastfolk, Stonekin (FAC_*). Standings are clamped to
; -1000..1000, the Ashen Cult to at most 199 so it can never become Friendly. A tier change shows
; a banner. The header also holds one bit per faction: its champion is defeated.
%include "common.inc"
default rel

global faction_reset, faction_validate, faction_standing, faction_tier, faction_add
global faction_on_kill, faction_enemies, faction_hostile, faction_tribute, faction_tier_color
global faction_champion_defeated, faction_defeat_champion
global faction_names, faction_members, faction_short, tier_names, champion_names
global faction_wanted, faction_rivals, screen_faction

extern world_header, hud_banner, str_append, inv_count, inv_remove_one, audio_play

%define STANDING_ADDR   world_header + WORLDHDR.standing
%define COL_UP          RGBA(140, 255, 90, 255)
%define COL_DOWN        RGBA(255, 85, 85, 255)
%define KILL_COST       -10
%define KILL_COST_BIG   -50
%define RIVAL_GAIN      5

section .rodata.str progbits alloc noexec nowrite align=1

; one pointer-table entry: the string goes to .rodata.str, its address to the table being built
%macro ZS 1
section .rodata.str
%%s: db %1, 0
section .rodata
    dq %%s
%endmacro

section .rodata
align 4
f_vol_coin: dd 0.7
tier_colors:                            ; per TIER_*
    dd RGBA(255, 90, 90, 255)
    dd RGBA(255, 90, 90, 255)
    dd RGBA(230, 230, 230, 255)
    dd RGBA(140, 255, 90, 255)
    dd RGBA(255, 215, 60, 255)
start_standing:                         ; per FAC_*, int16
    dw 200, -100, -100, 0, 0, 0, 0, 0
faction_wanted:                         ; per FAC_*: the item its shrine takes as tribute
    db APPLE, GOLD_INGOT, ROTTEN_FLESH, PORKCHOP, IRON_INGOT
faction_rivals:                         ; per FAC_*: bit r set = faction r is a rival (symmetric)
    db 0x06, 0x11, 0x09, 0x04, 0x02
s_now: db ": now ", 0

align 8
faction_names:
    ZS "Villagers"
    ZS "Bandits"
    ZS "Ashen Cult"
    ZS "Beastfolk"
    ZS "Stonekin"
faction_members:
    ZS "Villager"
    ZS "Bandit"
    ZS "Cultist"
    ZS "Beastkin"
    ZS "Stonekin"
faction_short:
    ZS "Vil"
    ZS "Ban"
    ZS "Cul"
    ZS "Bst"
    ZS "Stk"
tier_names:
    ZS "Hated"
    ZS "Hostile"
    ZS "Neutral"
    ZS "Friendly"
    ZS "Allied"
champion_names:
    ZS "Captain Aldric"
    ZS "Grisk the Cutthroat"
    ZS "Morvael the Ashen"
    ZS "Hrodna Bloodmane"
    ZS "Thane Durgar"

section .bss
align 4
screen_faction: resd 1                  ; the faction of the open leader / shrine / trade screen
tier_buf:       resb 48                 ; "<Faction>: now <Tier>"

section .text

; faction_reset(): the starting standings (Villagers 200, Bandits -100, Cult -100, Beastfolk 0,
; Stonekin 0) and no champion defeated
faction_reset:
    lea     rsi, [start_standing]
    lea     rdi, [STANDING_ADDR]
    mov     rax, [rsi]
    mov     [rdi], rax
    mov     rax, [rsi + 8]
    mov     [rdi + 8], rax
    mov     byte [world_header + WORLDHDR.champions], 0
    ret

; faction_validate(): after a load - every standing back into -1000..1000 (the Ashen Cult at most
; 199), and no champion bit beyond the five factions
faction_validate:
    lea     rdi, [STANDING_ADDR]
    xor     ecx, ecx
.next:
    movsx   eax, word [rdi + rcx * 2]
    mov     edx, STANDING_MAX
    cmp     ecx, FAC_CULT
    jne     .hi
    mov     edx, CULT_MAX
.hi:
    cmp     eax, edx
    cmovg   eax, edx
    mov     edx, STANDING_MIN
    cmp     eax, edx
    cmovl   eax, edx
    mov     [rdi + rcx * 2], ax
    inc     ecx
    cmp     ecx, NUM_FACTIONS
    jb      .next
    and     byte [world_header + WORLDHDR.champions], 0x1F
    ret

; faction_standing(edi f) -> eax the signed standing with faction f
faction_standing:
    lea     rcx, [STANDING_ADDR]
    movsx   eax, word [rcx + rdi * 2]
    ret

; standing_tier(edi standing) -> eax TIER_*: Hated < -200 <= Hostile < 0 <= Neutral < 200 <=
; Friendly < 500 <= Allied
standing_tier:
    xor     eax, eax
    cmp     edi, STANDING_HOSTILE
    jl      .done
    inc     eax
    cmp     edi, STANDING_NEUTRAL
    jl      .done
    inc     eax
    cmp     edi, STANDING_FRIENDLY
    jl      .done
    inc     eax
    cmp     edi, STANDING_ALLIED
    jl      .done
    inc     eax
.done:
    ret

; faction_tier(edi f) -> eax TIER_* of the standing with faction f
faction_tier:
    sub     rsp, 8
    call    faction_standing
    mov     edi, eax
    call    standing_tier
    add     rsp, 8
    ret

; faction_add(edi f, esi delta) -> eax the new standing. The result is clamped to -1000..1000
; (the Ashen Cult to 199). When it lands in another tier the banner "<Faction>: now <Tier>" shows,
; green for a rise and red for a fall.
faction_add:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     ebx, edi
    mov     r13d, esi
    call    faction_standing
    mov     edi, eax
    mov     r12d, eax                   ; old standing
    call    standing_tier
    mov     r14d, eax                   ; old tier
    lea     eax, [r12 + r13]
    mov     ecx, STANDING_MAX
    cmp     ebx, FAC_CULT
    jne     .hi
    mov     ecx, CULT_MAX
.hi:
    cmp     eax, ecx
    cmovg   eax, ecx
    mov     ecx, STANDING_MIN
    cmp     eax, ecx
    cmovl   eax, ecx
    mov     r13d, eax                   ; new standing
    lea     rcx, [STANDING_ADDR]
    mov     [rcx + rbx * 2], ax
    mov     edi, eax
    call    standing_tier
    mov     r12d, eax                   ; new tier
    cmp     eax, r14d
    je      .done
    mov     r14d, COL_UP
    jg      .text
    mov     r14d, COL_DOWN
.text:
    lea     rdi, [tier_buf]
    lea     rax, [faction_names]
    mov     rsi, [rax + rbx * 8]
    call    str_append
    mov     rdi, rax
    lea     rsi, [s_now]
    call    str_append
    mov     rdi, rax
    lea     rcx, [tier_names]
    mov     rsi, [rcx + r12 * 8]
    call    str_append
    mov     byte [rax], 0
    lea     rdi, [tier_buf]
    mov     esi, r14d
    call    hud_banner
.done:
    mov     eax, r13d
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; faction_on_kill(edi f, esi big): the player killed a member of faction f (big: its leader or
; champion). f loses 10 standing (50 when big), and every rival of f gains 5.
faction_on_kill:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     ebx, edi
    mov     eax, KILL_COST
    mov     ecx, KILL_COST_BIG
    test    esi, esi
    cmovnz  eax, ecx
    mov     esi, eax
    call    faction_add                 ; edi = f
    lea     rax, [faction_rivals]
    movzx   r12d, byte [rax + rbx]
    xor     r13d, r13d
.rival:
    bt      r12d, r13d
    jnc     .skip
    mov     edi, r13d
    mov     esi, RIVAL_GAIN
    call    faction_add
.skip:
    inc     r13d
    cmp     r13d, NUM_FACTIONS
    jb      .rival
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; faction_enemies(edi a, esi b) -> eax 1 when factions a and b are rivals (a faction is never its
; own rival)
faction_enemies:
    lea     rax, [faction_rivals]
    movzx   eax, byte [rax + rdi]
    mov     ecx, esi
    shr     eax, cl
    and     eax, 1
    ret

; faction_hostile(edi f) -> eax 1 when the standing with faction f is below 0
faction_hostile:
    sub     rsp, 8
    call    faction_standing
    shr     eax, 31
    add     rsp, 8
    ret

; faction_tribute(edi f, esi kind, edx units) -> eax the standing gained, 0 = refused (nothing is
; taken). kind 0: units gold coins (5 or 50) for units / 5 standing; kind 1: units of the item
; faction_wanted[f] (1 or 10) for units standing. Refused when the inventory lacks the payment,
; when it would earn nothing, or when the faction is already at its cap. Success plays the coin
; sound.
faction_tribute:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     ebx, edi
    mov     r13d, esi
    mov     r12d, edx
    mov     eax, edx
    test    r13d, r13d
    jnz     .gain
    xor     edx, edx
    mov     ecx, 5
    div     ecx                         ; coins: 1 standing per 5
.gain:
    test    eax, eax
    jz      .refuse
    mov     r14d, eax
    mov     edi, ebx
    call    faction_standing
    mov     ecx, STANDING_MAX
    cmp     ebx, FAC_CULT
    jne     .cap
    mov     ecx, CULT_MAX
.cap:
    cmp     eax, ecx
    jge     .refuse
    mov     edi, GOLD_COIN
    test    r13d, r13d
    jz      .item
    lea     rax, [faction_wanted]
    movzx   edi, byte [rax + rbx]
.item:
    mov     r13d, edi                   ; the item that pays
    call    inv_count
    cmp     eax, r12d
    jb      .refuse
.take:
    mov     edi, r13d
    call    inv_remove_one
    dec     r12d
    jnz     .take
    mov     edi, ebx
    call    faction_standing
    mov     r12d, eax                   ; standing before
    mov     edi, ebx
    mov     esi, r14d
    call    faction_add
    sub     eax, r12d
    mov     r14d, eax                   ; what the clamp let through
    mov     edi, SND_COIN
    movss   xmm0, [f_vol_coin]
    call    audio_play
    mov     eax, r14d
    jmp     .ret
.refuse:
    xor     eax, eax
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; faction_tier_color(edi f) -> eax RGBA of the faction's tier: red for Hated and Hostile, grey for
; Neutral, green for Friendly, gold for Allied
faction_tier_color:
    sub     rsp, 8
    call    faction_tier
    lea     rcx, [tier_colors]
    mov     eax, [rcx + rax * 4]
    add     rsp, 8
    ret

; faction_champion_defeated(edi f) -> eax 1 when faction f's champion has been defeated
faction_champion_defeated:
    movzx   eax, byte [world_header + WORLDHDR.champions]
    mov     ecx, edi
    shr     eax, cl
    and     eax, 1
    ret

; faction_defeat_champion(edi f): records faction f's champion as defeated
faction_defeat_champion:
    mov     ecx, edi
    mov     eax, 1
    shl     eax, cl
    or      [world_header + WORLDHDR.champions], al
    ret
