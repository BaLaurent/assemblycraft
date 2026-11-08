; test_factions.asm - faction standings, tiers, rivalries, shrine tribute and the per-faction trade
; tables.
%include "common.inc"
default rel

global test_faction_tiers_and_caps, test_faction_kill_and_rivals, test_shrine_tribute
global test_trade_tables

extern world_clear, world_header, banner_text, str_eq
extern inv_clear, inv_add, inv_count
extern faction_reset, faction_validate, faction_standing, faction_tier, faction_add
extern faction_on_kill, faction_enemies, faction_tribute
extern trade_open, trade_offer, trade_execute, trade_count, trade_title

%define STAND   world_header + WORLDHDR.standing

section .rodata.str progbits alloc noexec nowrite align=1

section .rodata
align 4
t_trades:                               ; the 0.9 merchant's rows: give, give_n, get, get_n
    dd GOLD_COIN, 6, HEALTH_POTION, 1
    dd GOLD_COIN, 6, MANA_POTION, 1
    dd GOLD_COIN, 4, ARROW, 16
    dd GOLD_COIN, 8, IRON_INGOT, 4
    dd GOLD_COIN, 25, DIAMOND, 1
    dd GOLD_COIN, 12, STAFF, 1
    dd ROTTEN_FLESH, 10, GOLD_COIN, 1
    dd DIAMOND, 1, GOLD_COIN, 15
    dd GOLD_COIN, 30, RING, 1
    dd GOLD_COIN, 30, AMULET, 1
s_friendly: db "Beastfolk: now Friendly", 0
s_merchant: db "Merchant", 0
s_bandit_trader: db "Bandit Trader", 0
s_cult_trader: db "Cult Trader", 0
s_beast_trader: db "Beastkin Trader", 0
s_stone_trader: db "Stonekin Trader", 0

section .text

; ---- harness -------------------------------------------------------------------

%macro TEST_BEGIN 0
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    call    world_clear
%endmacro
; success unless a check jumped to .fail; the standings, inventory and trader are left reset
%macro TEST_END 0
    xor     ebx, ebx
    jmp     .out
.fail:
    mov     ebx, 1
.out:
    call    cleanup
    mov     eax, ebx
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
%endmacro

; set the standing of faction %1 to %2
%macro SET 2
    mov     word [STAND + (%1) * 2], %2
%endmacro
; fail unless the standing of faction %1 is %2
%macro STANDING 2
    mov     edi, %1
    call    faction_standing
    cmp     eax, %2
    jne     .fail
%endmacro
; fail unless faction_tier(%1) is %2
%macro TIER 2
    mov     edi, %1
    call    faction_tier
    cmp     eax, %2
    jne     .fail
%endmacro
; fail unless faction_add(%1, %2) returns %3
%macro ADDF 3
    mov     edi, %1
    mov     esi, %2
    call    faction_add
    cmp     eax, %3
    jne     .fail
%endmacro
; fail unless faction_tribute(%1, %2, %3) returns %4
%macro TRIBUTE 4
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    call    faction_tribute
    cmp     eax, %4
    jne     .fail
%endmacro
; fail unless inv_count(%1) is %2
%macro HAVE 2
    mov     edi, %1
    call    inv_count
    cmp     eax, %2
    jne     .fail
%endmacro
; fail unless the zstr at the address stored in dq %1 equals the zstr %2
%macro STR_PTR_IS 2
    mov     rdi, [%1]
    lea     rsi, [%2]
    call    str_eq
    test    eax, eax
    jz      .fail
%endmacro
; fail unless the zstr buffer %1 equals the zstr %2
%macro STR_IS 2
    lea     rdi, [%1]
    lea     rsi, [%2]
    call    str_eq
    test    eax, eax
    jz      .fail
%endmacro

; cleanup(): no standings and champions in the header, an empty inventory, the Merchant's table
cleanup:
    sub     rsp, 8
    xor     eax, eax
    mov     [STAND], rax
    mov     [STAND + 8], rax
    mov     byte [world_header + WORLDHDR.champions], al
    call    inv_clear
    mov     edi, FAC_VILLAGERS
    call    trade_open
    add     rsp, 8
    ret

; ---- tests -------------------------------------------------------------------------

; the starting standings and their tiers, the clamps (Cult 199, -1000), the tier thresholds, the
; banner of a tier change, and faction_validate after a load
test_faction_tiers_and_caps:
    TEST_BEGIN
    call    faction_reset
    STANDING FAC_VILLAGERS, 200
    STANDING FAC_BANDITS, -100
    STANDING FAC_CULT, -100
    STANDING FAC_BEASTFOLK, 0
    STANDING FAC_STONEKIN, 0
    TIER    FAC_VILLAGERS, TIER_FRIENDLY
    TIER    FAC_BANDITS, TIER_HOSTILE
    ADDF    FAC_CULT, 1000, 199
    STANDING FAC_CULT, 199
    ADDF    FAC_BEASTFOLK, -1500, -1000
    STANDING FAC_BEASTFOLK, -1000
    ADDF    FAC_VILLAGERS, 5000, 1000
    ; the tier thresholds
    SET     FAC_BEASTFOLK, -200
    TIER    FAC_BEASTFOLK, TIER_HOSTILE
    SET     FAC_BEASTFOLK, -201
    TIER    FAC_BEASTFOLK, TIER_HATED
    SET     FAC_BEASTFOLK, 199
    TIER    FAC_BEASTFOLK, TIER_NEUTRAL
    SET     FAC_BEASTFOLK, 200
    TIER    FAC_BEASTFOLK, TIER_FRIENDLY
    SET     FAC_BEASTFOLK, 499
    TIER    FAC_BEASTFOLK, TIER_FRIENDLY
    SET     FAC_BEASTFOLK, 500
    TIER    FAC_BEASTFOLK, TIER_ALLIED
    ; crossing into Friendly shows the banner; a move inside a tier shows none
    SET     FAC_BEASTFOLK, 190
    mov     byte [banner_text], 0
    ADDF    FAC_BEASTFOLK, 10, 200
    STR_IS  banner_text, s_friendly
    mov     byte [banner_text], 0
    ADDF    FAC_BEASTFOLK, 1, 201
    cmp     byte [banner_text], 0
    jne     .fail
    ; a load that left out-of-range values: validate clamps them
    SET     FAC_BANDITS, 5000
    SET     FAC_CULT, 400
    SET     FAC_STONEKIN, -3000
    mov     byte [world_header + WORLDHDR.champions], 0xFF
    call    faction_validate
    STANDING FAC_BANDITS, 1000
    STANDING FAC_CULT, 199
    STANDING FAC_STONEKIN, -1000
    cmp     byte [world_header + WORLDHDR.champions], 0x1F
    jne     .fail
    TEST_END

; killing a member costs its faction 10 (50 for a leader or champion) and pays each rival 5; the
; rivalry table is symmetric
test_faction_kill_and_rivals:
    TEST_BEGIN
    call    faction_reset
    mov     edi, FAC_BANDITS
    xor     esi, esi
    call    faction_on_kill
    STANDING FAC_BANDITS, -110
    STANDING FAC_VILLAGERS, 205
    STANDING FAC_STONEKIN, 5
    STANDING FAC_CULT, -100
    STANDING FAC_BEASTFOLK, 0
    mov     edi, FAC_CULT
    mov     esi, 1
    call    faction_on_kill
    STANDING FAC_CULT, -150
    STANDING FAC_VILLAGERS, 210
    STANDING FAC_BEASTFOLK, 5
    STANDING FAC_BANDITS, -110
    STANDING FAC_STONEKIN, 5
    ; the rivalries
    mov     edi, FAC_VILLAGERS
    mov     esi, FAC_BANDITS
    call    faction_enemies
    cmp     eax, 1
    jne     .fail
    mov     edi, FAC_BANDITS
    mov     esi, FAC_VILLAGERS
    call    faction_enemies
    cmp     eax, 1
    jne     .fail
    mov     edi, FAC_VILLAGERS
    mov     esi, FAC_BEASTFOLK
    call    faction_enemies
    test    eax, eax
    jnz     .fail
    mov     edi, FAC_CULT
    mov     esi, FAC_CULT
    call    faction_enemies
    test    eax, eax
    jnz     .fail
    ; every pair is symmetric
    xor     r12d, r12d
.a:
    xor     r13d, r13d
.b:
    mov     edi, r12d
    mov     esi, r13d
    call    faction_enemies
    mov     r14d, eax
    mov     edi, r13d
    mov     esi, r12d
    call    faction_enemies
    cmp     eax, r14d
    jne     .fail
    inc     r13d
    cmp     r13d, NUM_FACTIONS
    jb      .b
    inc     r12d
    cmp     r12d, NUM_FACTIONS
    jb      .a
    TEST_END

; tribute: coins give 1 standing per 5, wanted items 1 each; a payment the inventory lacks and a
; faction at its cap are refused without taking anything
test_shrine_tribute:
    TEST_BEGIN
    call    faction_reset
    call    inv_clear
    mov     edi, GOLD_COIN
    mov     esi, 60
    call    inv_add
    mov     edi, GOLD_INGOT
    mov     esi, 12
    call    inv_add
    TRIBUTE FAC_BANDITS, 0, 5, 1
    STANDING FAC_BANDITS, -99
    HAVE    GOLD_COIN, 55
    TRIBUTE FAC_BANDITS, 0, 50, 10
    STANDING FAC_BANDITS, -89
    HAVE    GOLD_COIN, 5
    TRIBUTE FAC_BANDITS, 0, 50, 0           ; 5 coins do not pay 50
    STANDING FAC_BANDITS, -89
    HAVE    GOLD_COIN, 5
    TRIBUTE FAC_BANDITS, 1, 10, 10
    STANDING FAC_BANDITS, -79
    HAVE    GOLD_INGOT, 2
    TRIBUTE FAC_BANDITS, 1, 10, 0           ; 2 ingots do not pay 10
    STANDING FAC_BANDITS, -79
    HAVE    GOLD_INGOT, 2
    TRIBUTE FAC_BANDITS, 1, 1, 1
    STANDING FAC_BANDITS, -78
    HAVE    GOLD_INGOT, 1
    ; the Ashen Cult is capped at 199: the coins stay in the pocket
    SET     FAC_CULT, 199
    TRIBUTE FAC_CULT, 0, 5, 0
    STANDING FAC_CULT, 199
    HAVE    GOLD_COIN, 5
    ; one short of the cap: the payment is taken, the standing clamps, the gain is what was left
    SET     FAC_CULT, 198
    TRIBUTE FAC_CULT, 0, 5, 1
    STANDING FAC_CULT, 199
    HAVE    GOLD_COIN, 0
    TEST_END

; every faction's table: row counts, titles, the Stonekin offers and a sale, the Merchant's rows
; as in 0.9
test_trade_tables:
    TEST_BEGIN
    mov     edi, FAC_STONEKIN
    call    trade_open
    cmp     dword [trade_count], 7
    jne     .fail
    STR_PTR_IS trade_title, s_stone_trader
    mov     edi, 1
    call    trade_offer
    test    rax, rax
    jz      .fail
    cmp     dword [rax], DIAMOND
    jne     .fail
    cmp     dword [rax + 4], 1
    jne     .fail
    cmp     dword [rax + 8], GOLD_COIN
    jne     .fail
    cmp     dword [rax + 12], 18
    jne     .fail
    mov     edi, 7
    call    trade_offer
    test    rax, rax
    jnz     .fail
    call    inv_clear
    mov     edi, DIAMOND
    mov     esi, 1
    call    inv_add
    mov     edi, 1
    call    trade_execute
    cmp     eax, 1
    jne     .fail
    HAVE    DIAMOND, 0
    HAVE    GOLD_COIN, 18
    ; the other traders
    mov     edi, FAC_BANDITS
    call    trade_open
    cmp     dword [trade_count], 7
    jne     .fail
    STR_PTR_IS trade_title, s_bandit_trader
    mov     edi, FAC_CULT
    call    trade_open
    cmp     dword [trade_count], 5
    jne     .fail
    STR_PTR_IS trade_title, s_cult_trader
    mov     edi, FAC_BEASTFOLK
    call    trade_open
    cmp     dword [trade_count], 6
    jne     .fail
    STR_PTR_IS trade_title, s_beast_trader
    ; the Merchant keeps the 0.9 table
    mov     edi, FAC_VILLAGERS
    call    trade_open
    cmp     dword [trade_count], 10
    jne     .fail
    STR_PTR_IS trade_title, s_merchant
    xor     r12d, r12d
.rows:
    mov     edi, r12d
    call    trade_offer
    test    rax, rax
    jz      .fail
    mov     rcx, r12
    shl     rcx, 4
    lea     rdx, [t_trades]
    add     rdx, rcx
    mov     ecx, [rdx]
    cmp     [rax], ecx
    jne     .fail
    mov     ecx, [rdx + 4]
    cmp     [rax + 4], ecx
    jne     .fail
    mov     ecx, [rdx + 8]
    cmp     [rax + 8], ecx
    jne     .fail
    mov     ecx, [rdx + 12]
    cmp     [rax + 12], ecx
    jne     .fail
    inc     r12d
    cmp     r12d, 10
    jb      .rows
    mov     edi, 10
    call    trade_offer
    test    rax, rax
    jnz     .fail
    TEST_END
