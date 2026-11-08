; quests.asm - the quest chain every elder hands out, and the merchant's trades.
; The chain position lives in rpg_state (quest, quest_state, quest_progress) and is saved with
; the character. Rewards are XP and coins, sometimes an item; what does not fit in the
; inventory is dropped at the player's feet.
%include "common.inc"
default rel

global quests_current, quests_progress, quests_accept, quests_can_complete, quests_complete
global quests_on_kill, quests_on_dungeon_cleared, quests_on_boss_killed
global trade_offer, trade_can, trade_execute

extern rpg_state, rpg_add_xp, rpg_give_item
extern inv_count, inv_remove_one, audio_play, hud_banner

section .rodata.str progbits alloc noexec nowrite align=1

section .rodata
align 4
f_vol_full: dd 1.0
f_vol_coin: dd 0.7
s_done:     db "Quest complete!", 0

%macro QUEST 10                         ; type, target, count, xp, coins, item, item_n, title, line1, line2
section .rodata.str
%%t: db %8, 0
%%a: db %9, 0
%%b: db %10, 0
section .rodata
    dd %1, %2, %3, %4, %5, %6, %7, 0
    dq %%t, %%a, %%b
%endmacro

align 8
quest_tab:
    QUEST Q_KILL,  MOB_ZOMBIE,   6,  40,  6, 0,             0, "Zombie Trouble",        "The dead walk at night.",         "Slay 6 zombies."
    QUEST Q_BRING, IRON_INGOT,   8,  50, 10, 0,             0, "Iron for the Smithy",   "Our smith needs iron.",           "Bring 8 iron ingots."
    QUEST Q_KILL,  MOB_SKELETON, 5,  60,  8, HEALTH_POTION, 1, "Rattling Bones",        "Archers of bone haunt us.",       "Destroy 5 skeletons."
    QUEST Q_KILL,  MOB_CREEPER,  3,  70, 10, 0,             0, "Silent Hissers",        "Something hisses nearby.",        "Kill 3 creepers."
    QUEST Q_CLEAR, 0,            1, 150, 20, HEALTH_POTION, 2, "Into the Depths",       "Dungeons lie below us.",          "Clear one of them."
    QUEST Q_BRING, DIAMOND,      3, 120, 25, 0,             0, "Shining Treasure",      "Diamonds buy us steel.",          "Bring 3 diamonds."
    QUEST Q_ELITE, 0,            5, 200, 30, 0,             0, "Champions of Darkness", "Elite fiends guard the deep.",    "Slay 5 elite monsters."
    QUEST Q_BOSS,  0,            1, 500, 60, 0,             0, "The Fallen King",       "A dead king stirs in his crypt.", "End his reign."

trade_tab:                              ; give -> get
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

section .text

; ---- quests ------------------------------------------------------------------

; quests_current() -> rax QUESTINFO* of the quest the elders offer, 0 once the chain is done
quests_current:
    movzx   eax, byte [rpg_state + RPGSAVE.quest]
    cmp     eax, NUM_QUESTS
    jae     .done
    imul    eax, eax, QUESTINFO_size
    lea     rcx, [quest_tab]
    add     rax, rcx
    ret
.done:
    xor     eax, eax
    ret

; quests_progress() -> eax how far the current quest is: Q_BRING counts the items in the
; inventory (at most the quest's count), the others the saved counter
quests_progress:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    quests_current
    mov     rbx, rax
    xor     eax, eax
    test    rbx, rbx
    jz      .ret
    cmp     dword [rbx + QUESTINFO.type], Q_BRING
    je      .bring
    movzx   eax, word [rpg_state + RPGSAVE.quest_progress]
    jmp     .ret
.bring:
    mov     edi, [rbx + QUESTINFO.target]
    call    inv_count
    mov     ecx, [rbx + QUESTINFO.count]
    cmp     eax, ecx
    cmova   eax, ecx
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; quests_accept() -> eax 1 when the current quest was just accepted (counting starts from 0)
quests_accept:
    push    rbp
    mov     rbp, rsp
    call    quests_current
    test    rax, rax
    jz      .no
    cmp     byte [rpg_state + RPGSAVE.quest_state], 0
    jne     .no
    mov     byte [rpg_state + RPGSAVE.quest_state], 1
    mov     word [rpg_state + RPGSAVE.quest_progress], 0
    mov     eax, 1
    pop     rbp
    ret
.no:
    xor     eax, eax
    pop     rbp
    ret

; quests_can_complete() -> eax 1 when the quest is accepted and its goal is reached
quests_can_complete:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    quests_current
    mov     rbx, rax
    xor     eax, eax
    test    rbx, rbx
    jz      .ret
    cmp     byte [rpg_state + RPGSAVE.quest_state], 1
    jne     .ret
    call    quests_progress
    cmp     eax, [rbx + QUESTINFO.count]
    setae   al
    movzx   eax, al
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; quests_complete() -> eax 1 when the quest was handed in: Q_BRING takes its items, then XP,
; coins and the item reward are paid, the chain moves on, sound and banner
quests_complete:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    quests_can_complete
    test    eax, eax
    jz      .ret
    call    quests_current
    mov     rbx, rax
    cmp     dword [rbx + QUESTINFO.type], Q_BRING
    jne     .paid_in
    mov     r12d, [rbx + QUESTINFO.count]
.take:
    mov     edi, [rbx + QUESTINFO.target]
    call    inv_remove_one
    dec     r12d
    jnz     .take
.paid_in:
    mov     edi, [rbx + QUESTINFO.xp]
    call    rpg_add_xp
    mov     esi, [rbx + QUESTINFO.coins]
    test    esi, esi
    jz      .no_coins
    mov     edi, GOLD_COIN
    call    rpg_give_item
.no_coins:
    mov     edi, [rbx + QUESTINFO.item]
    test    edi, edi
    jz      .next
    mov     esi, [rbx + QUESTINFO.item_count]
    call    rpg_give_item
.next:
    inc     byte [rpg_state + RPGSAVE.quest]
    mov     byte [rpg_state + RPGSAVE.quest_state], 0
    mov     word [rpg_state + RPGSAVE.quest_progress], 0
    mov     edi, SND_QUEST
    movss   xmm0, [f_vol_full]
    call    audio_play
    lea     rdi, [s_done]
    mov     esi, RGBA(255, 215, 60, 255)
    call    hud_banner
    mov     eax, 1
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; bump(edi type): +1 progress when the quest on offer is accepted, of that type and not done yet
bump:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
    call    quests_current
    test    rax, rax
    jz      .ret
    cmp     byte [rpg_state + RPGSAVE.quest_state], 1
    jne     .ret
    cmp     [rax + QUESTINFO.type], ebx
    jne     .ret
    movzx   ecx, word [rpg_state + RPGSAVE.quest_progress]
    cmp     ecx, [rax + QUESTINFO.count]
    jae     .ret
    inc     word [rpg_state + RPGSAVE.quest_progress]
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; quests_on_kill(edi type, esi elite): a mob died to the player. Counts for a Q_KILL quest
; whose target is that mob type and for a Q_ELITE quest when the mob was elite.
quests_on_kill:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12d, esi
    call    quests_current
    test    rax, rax
    jz      .ret
    mov     edi, [rax + QUESTINFO.type]        ; what bump has to match
    cmp     edi, Q_KILL
    je      .kill
    cmp     edi, Q_ELITE
    jne     .ret
    test    r12d, r12d
    jz      .ret                        ; not an elite
    jmp     .count
.kill:
    cmp     [rax + QUESTINFO.target], ebx
    jne     .ret                        ; another kind of mob
.count:
    call    bump
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; quests_on_dungeon_cleared(): counts for a Q_CLEAR quest
quests_on_dungeon_cleared:
    mov     edi, Q_CLEAR
    jmp     bump

; quests_on_boss_killed(): counts for a Q_BOSS quest
quests_on_boss_killed:
    mov     edi, Q_BOSS
    jmp     bump

; ---- trades ----------------------------------------------------------------------

; trade_offer(edi i) -> rax TRADEOFFER* {give, give_n, get, get_n}, 0 for i >= NUM_TRADES
trade_offer:
    xor     eax, eax
    cmp     edi, NUM_TRADES
    jae     .ret
    mov     eax, edi
    shl     eax, 4                      ; TRADEOFFER_size
    lea     rcx, [trade_tab]
    add     rax, rcx
.ret:
    ret

; trade_can(edi i) -> eax 1 when the inventory holds the offer's price
trade_can:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    trade_offer
    mov     rbx, rax
    xor     eax, eax
    test    rbx, rbx
    jz      .ret
    mov     edi, [rbx + TRADEOFFER.give]
    call    inv_count
    cmp     eax, [rbx + TRADEOFFER.give_n]
    setae   al
    movzx   eax, al
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; trade_execute(edi i) -> eax 1 when the trade was made: the price is taken, the goods are
; added (what does not fit is dropped at the player), coin sound
trade_execute:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     r12d, edi
    call    trade_can
    test    eax, eax
    jz      .ret
    mov     edi, r12d
    call    trade_offer
    mov     rbx, rax
    mov     r12d, [rbx + TRADEOFFER.give_n]
.take:
    mov     edi, [rbx + TRADEOFFER.give]
    call    inv_remove_one
    dec     r12d
    jnz     .take
    mov     edi, [rbx + TRADEOFFER.get]
    mov     esi, [rbx + TRADEOFFER.get_n]
    call    rpg_give_item
    mov     edi, SND_COIN
    movss   xmm0, [f_vol_coin]
    call    audio_play
    mov     eax, 1
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret
