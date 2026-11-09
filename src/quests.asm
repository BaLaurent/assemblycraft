; quests.asm - the quest chain every elder hands out, and the traders' offers.
; The chain position lives in rpg_state (quest, quest_state, quest_progress) and is saved with
; the character. Rewards are XP and coins, sometimes an item; what does not fit in the
; inventory is dropped at the player's feet. Each faction's trader sells from its own table
; (trade_open picks it); a gear item an offer sells (jewelry, weapons, armour) is rolled when it
; is bought: a magic-or-better piece of the tier of the player's level.
; In multiplayer the chain is the world's, one for everybody: the host owns the position (QUEST_SYNC tells the guests), a guest
; asks for accepting, counting and handing in, and a hand-in rewards every connected player (QUEST_REWARD).
%include "common.inc"
default rel

global quests_current, quests_progress, quests_accept, quests_can_complete, quests_complete
global quests_pay, quests_advance, quests_reward, quests_settle, quests_bump, quests_refund
global quests_on_kill, quests_on_dungeon_cleared, quests_on_boss_killed
global trade_offer, trade_can, trade_execute, trade_open
global trade_cur, trade_count, trade_title

extern rpg_state, rpg_add_xp, rpg_give_item
extern inv_count, inv_remove_one, inv_add_dmg, drops_spawn, player, audio_play, hud_banner
extern item_gear, gear_roll, gear_tier_for_level
extern net_role, net_out, net_quest_sync_out, net_give_out

section .rodata.str progbits alloc noexec nowrite align=1

section .rodata
align 4
f_vol_full: dd 1.0
f_vol_coin: dd 0.7
f_drop_y:   dd 0.5                     ; a piece that does not fit falls this far above the feet
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

; one trade table per faction: give, give_n, get, get_n rows between the two labels
trade_villagers:
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
trade_villagers_end:
trade_bandits:
    dd GOLD_COIN, 12, IRON_DAGGER, 1
    dd GOLD_COIN, 20, BOW, 1
    dd GOLD_COIN, 4, ARROW, 16
    dd GOLD_COIN, 6, FLINT_AND_STEEL, 1
    dd GOLD_INGOT, 3, GOLD_COIN, 12
    dd GOLD_COIN, 8, HEALTH_POTION, 1
    dd GOLD_COIN, 40, RING, 1
trade_bandits_end:
trade_cult:
    dd GOLD_COIN, 15, STAFF, 1
    dd GOLD_COIN, 6, MANA_POTION, 1
    dd ROTTEN_FLESH, 16, GOLD_COIN, 3
    dd GOLD_COIN, 40, AMULET, 1
    dd GOLD_COIN, 10, TNT, 2
trade_cult_end:
trade_beastfolk:
    dd GOLD_COIN, 3, COOKED_PORKCHOP, 4
    dd GOLD_COIN, 25, IRON_HAMMER, 1
    dd GOLD_COIN, 18, IRON_SPEAR, 1
    dd PORKCHOP, 6, GOLD_COIN, 2
    dd FEATHER, 8, ARROW, 8
    dd GOLD_COIN, 30, IRON_HELMET, 1
trade_beastfolk_end:
trade_stonekin:
    dd GOLD_COIN, 20, IRON_PICKAXE, 1
    dd DIAMOND, 1, GOLD_COIN, 18
    dd IRON_INGOT, 4, GOLD_COIN, 6
    dd GOLD_COIN, 35, IRON_CHESTPLATE, 1
    dd GOLD_COIN, 60, DIAMOND_PICKAXE, 1
    dd GOLD_COIN, 12, TORCH, 16
    dd GOLD_COIN, 25, DIAMOND, 1
trade_stonekin_end:

%macro TRADEROW 2                       ; table label stem, trader title
section .rodata.str
%%t: db %2, 0
section .rodata
    dq trade_%1, (trade_%1_end - trade_%1) / TRADEOFFER_size, %%t
%endmacro

align 8
trade_index:                            ; per FAC_*: table, row count, title
    TRADEROW villagers, "Merchant"
    TRADEROW bandits, "Bandit Trader"
    TRADEROW cult, "Cult Trader"
    TRADEROW beastfolk, "Beastkin Trader"
    TRADEROW stonekin, "Stonekin Trader"

section .data
align 8
trade_cur:   dq trade_villagers         ; the TRADEOFFER table the trade screen is showing
trade_title: dq s_merchant              ; its title
trade_count: dd 10                      ; its row count

section .rodata.str
s_merchant: db "Merchant", 0
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

; quests_accept() -> eax 1 when the current quest was just accepted (counting starts from 0). On a guest the host is asked
; (QUEST_ACCEPT) and 1 means the request went out; the host's QUEST_SYNC brings the answer.
quests_accept:
    push    rbp
    mov     rbp, rsp
    call    quests_current
    test    rax, rax
    jz      .no
    cmp     byte [rpg_state + RPGSAVE.quest_state], 0
    jne     .no
    cmp     byte [net_role], NET_ROLE_GUEST
    je      .ask
    mov     byte [rpg_state + RPGSAVE.quest_state], 1
    mov     word [rpg_state + RPGSAVE.quest_progress], 0
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .yes
    call    net_quest_sync_out
.yes:
    mov     eax, 1
    pop     rbp
    ret
.ask:
    movzx   edi, byte [rpg_state + RPGSAVE.quest]
    mov     esi, MT_QUEST_ACCEPT
    call    quest_send
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

; quests_complete() -> eax 1 when the quest was handed in: Q_BRING takes its items (quests_pay), then the chain moves on and
; XP, coins and the item are paid, sound and banner (quests_settle). On a guest the host decides: the items are taken here,
; QUEST_COMPLETE goes out and the quest shows as handed in (quest_state 2) until the host's QUEST_SYNC answers; the reward,
; for every player this one included, and the new position come back from the host.
quests_complete:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    movzx   ebx, byte [rpg_state + RPGSAVE.quest] ; the quest being handed in
    call    quests_pay
    test    eax, eax
    jz      .ret
    cmp     byte [net_role], NET_ROLE_GUEST
    je      .guest
    mov     edi, ebx
    call    quests_settle
    mov     eax, 1
    jmp     .ret
.guest:
    mov     edi, ebx
    mov     esi, MT_QUEST_COMPLETE
    call    quest_send
    mov     byte [rpg_state + RPGSAVE.quest_state], 2 ; no second hand-in while the host has not answered
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; quests_pay() -> eax 1 when the quest on offer can be handed in (accepted, goal reached): a Q_BRING quest's items are taken
; from the inventory. 0, and nothing taken, otherwise.
quests_pay:
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
    jne     .paid
    mov     r12d, [rbx + QUESTINFO.count]
.take:
    mov     edi, [rbx + QUESTINFO.target]
    call    inv_remove_one
    dec     r12d
    jnz     .take
.paid:
    mov     eax, 1
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; quests_advance() -> eax 1 when the chain moved on: the quest on offer was accepted (and the chain is not over); the next one
; is not accepted yet and has no progress. 0 otherwise.
quests_advance:
    sub     rsp, 8
    call    quests_current
    test    rax, rax
    jz      .no
    cmp     byte [rpg_state + RPGSAVE.quest_state], 1
    jne     .no
    inc     byte [rpg_state + RPGSAVE.quest]
    mov     byte [rpg_state + RPGSAVE.quest_state], 0
    mov     word [rpg_state + RPGSAVE.quest_progress], 0
    mov     eax, 1
    add     rsp, 8
    ret
.no:
    xor     eax, eax
    add     rsp, 8
    ret

; quests_refund(edi slot, esi quest): the host did not take guest `slot`'s hand-in of quest number `quest` (a stale one: somebody
; else was first; or the quest was not accepted): a Q_BRING quest's items, which that guest took from his inventory before
; asking (quests_pay), go back to him (GIVE), so a second simultaneous hand-in loses nothing. A quest that takes no items, or
; a number beyond the chain: nothing.
quests_refund:
    cmp     esi, NUM_QUESTS
    jae     .none
    imul    eax, esi, QUESTINFO_size
    lea     rcx, [quest_tab]
    add     rcx, rax
    cmp     dword [rcx + QUESTINFO.type], Q_BRING
    jne     .none
    mov     esi, [rcx + QUESTINFO.target]
    mov     edx, [rcx + QUESTINFO.count]
    xor     ecx, ecx
    jmp     net_give_out                ; (edi = the slot is in place)
.none:
    ret

; quests_reward(edi quest): the pay of quest number `quest`: XP, coins and the item reward (what does not fit drops at the
; feet), the quest sound and the "Quest complete!" banner. Nothing for a number beyond the chain.
quests_reward:
    cmp     edi, NUM_QUESTS
    jb      .go
    ret
.go:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    imul    eax, edi, QUESTINFO_size
    lea     rbx, [quest_tab]
    add     rbx, rax
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
    jz      .done
    mov     esi, [rbx + QUESTINFO.item_count]
    call    rpg_give_item
.done:
    mov     edi, SND_QUEST
    movss   xmm0, [f_vol_full]
    call    audio_play
    lea     rdi, [s_done]
    mov     esi, RGBA(255, 215, 60, 255)
    call    hud_banner
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; quests_settle(edi quest): the chain's quest number `quest` is done (the host or offline): the chain moves on; on the host
; the guests are rewarded (QUEST_REWARD), then this player is (quests_reward); on the host the guests then learn the new
; position (QUEST_SYNC).
quests_settle:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
    call    quests_advance
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .reward
    mov     edi, ebx
    mov     esi, MT_QUEST_REWARD
    call    quest_send                  ; net_out: to every guest
.reward:
    mov     edi, ebx
    call    quests_reward
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    call    net_quest_sync_out
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; quest_send(edi arg, esi type) -> eax 1 when queued: a one-byte reliable message (net_out: the host's go to every guest, a
; guest's to the host)
quest_send:
    sub     rsp, 24
    mov     [rsp], dil
    mov     edi, esi
    mov     rsi, rsp
    mov     edx, 1
    mov     ecx, 1
    call    net_out
    add     rsp, 24
    ret

; quests_bump(edi type): +1 progress when the quest on offer is accepted, of that type and not done yet. The host or offline
; counts it (the host tells the guests: QUEST_SYNC); a guest asks the host (QUEST_BUMP), who checks it all again.
quests_bump:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .count
    mov     esi, MT_QUEST_BUMP
    jmp     quest_send
.count:
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
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    call    net_quest_sync_out
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
    call    quests_bump
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; quests_on_dungeon_cleared(): counts for a Q_CLEAR quest
quests_on_dungeon_cleared:
    mov     edi, Q_CLEAR
    jmp     quests_bump

; quests_on_boss_killed(): counts for a Q_BOSS quest
quests_on_boss_killed:
    mov     edi, Q_BOSS
    jmp     quests_bump

; ---- trades ----------------------------------------------------------------------

; trade_open(edi faction): the trader of that faction is the one the trade screen shows from now
; on: sets trade_cur, trade_count and trade_title
trade_open:
    lea     rcx, [trade_index]
    lea     eax, [rdi + rdi * 2]        ; 24-byte records
    lea     rcx, [rcx + rax * 8]
    mov     rax, [rcx]
    mov     [trade_cur], rax
    mov     rax, [rcx + 8]
    mov     [trade_count], eax
    mov     rax, [rcx + 16]
    mov     [trade_title], rax
    ret

; trade_offer(edi i) -> rax TRADEOFFER* {give, give_n, get, get_n} of the open table, 0 for
; i >= trade_count
trade_offer:
    xor     eax, eax
    cmp     edi, [trade_count]
    jae     .ret
    mov     eax, edi
    shl     rax, 4                      ; TRADEOFFER_size
    add     rax, [trade_cur]
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
; added (what does not fit is dropped at the player), coin sound. A gear item (item_gear != 0) is
; rolled piece by piece: its dmg word is gear_roll(item, gear_tier_for_level(level), LOOT_SHOP).
trade_execute:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
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
    lea     rax, [item_gear]
    cmp     byte [rax + rdi], 0
    jne     .gear
    mov     esi, [rbx + TRADEOFFER.get_n]
    call    rpg_give_item
    jmp     .paid
.gear:
    mov     r12d, [rbx + TRADEOFFER.get_n]
.piece:
    movzx   edi, byte [rpg_state + RPGSAVE.level]
    call    gear_tier_for_level
    mov     edi, [rbx + TRADEOFFER.get]
    mov     esi, eax
    mov     edx, LOOT_SHOP
    call    gear_roll
    mov     r13d, eax                   ; the piece's dmg word
    mov     edi, [rbx + TRADEOFFER.get]
    mov     esi, 1
    mov     edx, r13d
    call    inv_add_dmg
    test    eax, eax
    jz      .next
    mov     esi, eax                    ; no room: it falls at the player's feet
    mov     edi, [rbx + TRADEOFFER.get]
    mov     edx, r13d
    movss   xmm0, [player + BODY.x]
    movss   xmm1, [player + BODY.y]
    addss   xmm1, [f_drop_y]
    movss   xmm2, [player + BODY.z]
    call    drops_spawn
.next:
    dec     r12d
    jnz     .piece
.paid:
    mov     edi, SND_COIN
    movss   xmm0, [f_vol_coin]
    call    audio_play
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
