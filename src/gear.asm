; gear.asm - rolled gear: affixes, rarities, names and tooltips, the stats and legendary powers of
; what the player has equipped, loot rolls, mob drops and chest loot.
;
; A gear item (item_gear != GK_NONE) carries its whole roll in the stack's dmg word:
;     bits 14..15 rarity (RAR_COMMON .. RAR_EPIC), bits 10..13 tier (0..15), bits 0..9 seed.
; Nothing else is stored: the affixes are a pure function of (item id, dmg word), decoded on
; demand (see decode), so they cost no save space and every build agrees on them. Legendary items
; (item_legendary != LP_NONE) are shown as RAR_LEGENDARY whatever their bits say; they are made
; with RAR_RARE bits, so they carry 4 affixes besides their implicit stat and power.
%include "common.inc"
default rel

global affix_tab
global gear_affixes, gear_rarity, gear_rarity_color, gear_name
global gear_add_stats, gear_powers, gear_has_power
global gear_make, gear_roll, gear_tier_for_level, gear_pick_base
global gear_drop_from_mob, gear_fill_chest, item_tooltip, gear_equipped_for, gear_stack_worn

extern item_gear, item_legendary, item_names, item_attack, item_armor_points
extern item_durability, item_tool
extern inv, inv_sel
extern rng_next, rpg_stats, rpg_class, rpg_format_stat
extern drops_spawn, audio_play_at
extern str_append, i32_to_str

%define NUM_AFFIXES 44
%define TIP_LINES   12                  ; lines of one tooltip
%define TIP_SLOT    64                  ; bytes of one line buffer (text <= 48 chars)

; item_tooltip colours
%define COL_WHITE   RGBA(255, 255, 255, 255)
%define COL_GREY    RGBA(170, 170, 170, 255)
%define COL_AFFIX   RGBA(150, 190, 255, 255)
%define COL_POWER   RGBA(255, 150, 40, 255)
%define COL_HINT    RGBA(130, 130, 130, 255)

; base attack shown for the weapons whose damage does not come from item_attack: a fully drawn
; bow shot (x3/2 with the Celestial Bow) and a staff bolt
%define ATK_BOW       9
%define ATK_CELESTIAL 13
%define ATK_STAFF     4
%define ATK_ARCHMAGE  7

; the weapon families of gear_pick_base
%define FAM_SWORD   0
%define FAM_HAMMER  1
%define FAM_SPEAR   2
%define FAM_DAGGER  3
%define FAM_BOW     4
%define FAM_STAFF   5

%if PHOENIX_RING + 3 != VIPER_AMULET
%error "the four legendary jewels must have consecutive ids"
%endif
%if DIAMOND_HAMMER != IRON_HAMMER + 1 || DIAMOND_SPEAR != IRON_SPEAR + 1 || DIAMOND_DAGGER != IRON_DAGGER + 1
%error "iron and diamond hammers, spears and daggers must have consecutive ids"
%endif
%if GOLD_HELMET != IRON_HELMET + 4 || DIAMOND_HELMET != IRON_HELMET + 8
%error "armor sets must be iron, gold, diamond with four pieces each"
%endif

; kind masks of AFFIXDEF.kinds: bit 1 << GK_*
%define K_MELEE  (1 << GK_MELEE)
%define K_BOW    (1 << GK_BOW)
%define K_STAFF  (1 << GK_STAFF)
%define K_HEAD   (1 << GK_HEAD)
%define K_CHEST  (1 << GK_CHEST)
%define K_LEGS   (1 << GK_LEGS)
%define K_FEET   (1 << GK_FEET)
%define K_RING   (1 << GK_RING)
%define K_AMULET (1 << GK_AMULET)
%define K_W      (K_MELEE | K_BOW | K_STAFF)
%define K_A      (K_HEAD | K_CHEST | K_LEGS | K_FEET)

; strings of the affix table live in their own section so the 16-byte records stay contiguous
section .rodata.str progbits alloc noexec nowrite align=1

section .rodata
align 4
c_half:       dd 0.5
c_vol:        dd 0.8

; ---- the affix table: one row per stat, in the order of the design table -----------------------
; AFFIXDEF record: stat, lo, hi, tlo, thi, kinds, word. A rolled value lies in
; [lo + tier * tlo, hi + tier * thi]; every stat appears exactly once.
%macro AFFIX 7                          ; stat, lo, hi, tlo, thi, kinds, word
section .rodata.str
%%w: db %7, 0
section .rodata
    db %1, %2, %3, %4, %5, 0
    dw %6
    dq %%w
%endmacro

align 8
affix_tab:
    AFFIX STAT_WEAPON_DMG,    1,  2, 1, 1, K_W, "Sharp"
    AFFIX STAT_MELEE_DMG,     4,  8, 1, 2, K_MELEE | K_RING | K_AMULET, "Brutal"
    AFFIX STAT_RANGED_DMG,    4,  8, 1, 2, K_BOW | K_RING | K_AMULET, "Keen"
    AFFIX STAT_SPELL_DMG,     4,  8, 1, 2, K_STAFF | K_HEAD | K_RING | K_AMULET, "Arcane"
    AFFIX STAT_ALL_DMG,       2,  4, 1, 1, K_AMULET, "Mighty"
    AFFIX STAT_CRIT_CHANCE,   1,  3, 0, 1, K_W | K_HEAD | K_RING, "Precise"
    AFFIX STAT_CRIT_DMG,      5, 10, 2, 3, K_W | K_AMULET, "Deadly"
    AFFIX STAT_ATTACK_SPEED,  2,  5, 0, 1, K_W | K_RING, "Quick"
    AFFIX STAT_ADD_FIRE,      1,  2, 1, 1, K_W | K_RING, "Burning"
    AFFIX STAT_ADD_FROST,     1,  2, 1, 1, K_W | K_RING, "Chilling"
    AFFIX STAT_ADD_SHOCK,     1,  2, 1, 1, K_W | K_RING, "Charged"
    AFFIX STAT_ADD_POISON,    1,  2, 1, 1, K_W | K_RING, "Venomous"
    AFFIX STAT_FIRE_DMG,      5, 10, 1, 2, K_STAFF | K_RING | K_AMULET, "Blazing"
    AFFIX STAT_FROST_DMG,     5, 10, 1, 2, K_STAFF | K_RING | K_AMULET, "Frigid"
    AFFIX STAT_SHOCK_DMG,     5, 10, 1, 2, K_STAFF | K_RING | K_AMULET, "Stormy"
    AFFIX STAT_POISON_DMG,    5, 10, 1, 2, K_MELEE | K_BOW | K_RING | K_AMULET, "Toxic"
    AFFIX STAT_BLEED_CHANCE,  3,  8, 0, 1, K_MELEE | K_BOW, "Serrated"
    AFFIX STAT_DOT_DMG,       5, 10, 1, 2, K_STAFF | K_RING | K_AMULET, "Lingering"
    AFFIX STAT_ELITE_DMG,     5, 10, 1, 2, K_W | K_AMULET, "Slaying"
    AFFIX STAT_LIFESTEAL,     1,  3, 0, 0, K_MELEE | K_RING, "Vampiric"
    AFFIX STAT_LIFE_ON_KILL,  1,  2, 1, 1, K_W | K_RING, "Reaping"
    AFFIX STAT_MAX_HEALTH,    2,  4, 1, 2, K_A | K_AMULET, "Sturdy"
    AFFIX STAT_ARMOR_BONUS,   1,  1, 0, 0, K_A, "Reinforced"
    AFFIX STAT_LIFE_REGEN,    2,  5, 1, 1, K_A | K_AMULET, "Renewing"
    AFFIX STAT_RES_FIRE,      5, 10, 1, 2, K_A | K_RING | K_AMULET, "Fireproof"
    AFFIX STAT_RES_FROST,     5, 10, 1, 2, K_A | K_RING | K_AMULET, "Insulated"
    AFFIX STAT_RES_SHOCK,     5, 10, 1, 2, K_A | K_RING | K_AMULET, "Grounded"
    AFFIX STAT_RES_POISON,    5, 10, 1, 2, K_A | K_RING | K_AMULET, "Purifying"
    AFFIX STAT_MOVE_SPEED,    2,  5, 0, 0, K_FEET | K_AMULET, "Fleet"
    AFFIX STAT_MAX_STAMINA,   5, 10, 1, 2, K_CHEST | K_LEGS, "Enduring"
    AFFIX STAT_STAMINA_REGEN, 5, 10, 0, 1, K_LEGS | K_FEET | K_AMULET, "Tireless"
    AFFIX STAT_MAX_MANA,      5, 15, 1, 2, K_HEAD | K_STAFF | K_RING, "Wise"
    AFFIX STAT_MANA_REGEN,    1,  2, 0, 0, K_HEAD | K_STAFF | K_AMULET, "Flowing"
    AFFIX STAT_COOLDOWN_RED,  2,  5, 0, 0, K_HEAD | K_AMULET, "Hasty"
    AFFIX STAT_THORNS,        2,  4, 1, 1, K_CHEST | K_LEGS, "Spiked"
    AFFIX STAT_BLOCK_COST,    5, 10, 0, 1, K_CHEST | K_MELEE, "Steadfast"
    AFFIX STAT_AREA,          4,  8, 0, 1, K_STAFF | K_AMULET, "Vast"
    AFFIX STAT_XP_BONUS,      3,  6, 0, 0, K_HEAD | K_RING, "Studious"
    AFFIX STAT_GOLD_FIND,     5, 15, 0, 1, K_RING | K_AMULET, "Greedy"
    AFFIX STAT_MAGIC_FIND,    5, 10, 0, 1, K_HEAD | K_RING | K_AMULET, "Lucky"
    AFFIX STAT_BACKSTAB,      8, 15, 1, 2, K_MELEE, "Treacherous"
    AFFIX STAT_ARROW_SAVE,    5, 10, 0, 0, K_BOW, "Endless"
    AFFIX STAT_PARRY_WINDOW,  1,  1, 0, 0, K_MELEE, "Parrying"
    AFFIX STAT_DODGE_COST,    5, 10, 0, 0, K_FEET, "Nimble"
%if $ - affix_tab != NUM_AFFIXES * AFFIXDEF_size
%error "affix_tab must have NUM_AFFIXES rows"
%endif

affix_counts: db 0, 2, 4, 5             ; affixes by rarity bits: common, magic, rare, epic

; implicit stat of a legendary power (indexed by LP_*; value 0 = none)
implicit_stat:  db 0, STAT_ELITE_DMG, 0, 0, 0, 0, 0, STAT_FIRE_DMG, STAT_POISON_DMG
implicit_value: db 0, 50, 0, 0, 0, 0, 0, 20, 25
%if $ - implicit_value != LP_VIPER + 1
%error "implicit_value needs one entry per legendary power"
%endif

; ---- loot -------------------------------------------------------------------------------------
; rarity weights in per mille (common, magic, rare, epic) by LOOT_* table
loot_weights:
    dw 600, 320,  70,  10               ; LOOT_MOB
    dw 200, 500, 250,  50               ; LOOT_ELITE
    dw   0,   0, 800, 200               ; LOOT_BOSS
    dw 300, 450, 220,  30               ; LOOT_CHEST
    dw   0, 700, 270,  30               ; LOOT_SHOP

; the Fallen King's legendary by class (none, warrior, mage, archer, rogue)
t_legendary: db KINGS_BLADE, KINGS_BLADE, ARCHMAGE_STAFF, CELESTIAL_BOW, SHADOW_FANG
; the family of a class's own weapons (the warrior picks among sword, hammer and spear)
class_family: db FAM_SWORD, FAM_SWORD, FAM_STAFF, FAM_BOW, FAM_DAGGER
; the iron item of a hammer / spear / dagger family (the diamond one follows it)
melee_pair: db 0, IRON_HAMMER, IRON_SPEAR, IRON_DAGGER

; ---- texts ------------------------------------------------------------------------------------
w_common:     db "Common", 0
w_magic:      db "Magic", 0
w_rare:       db "Rare", 0
w_epic:       db "Epic", 0
w_legendary:  db "Legendary", 0
w_weapon:     db "Weapon", 0
w_bow:        db "Bow", 0
w_staff:      db "Staff", 0
w_helmet:     db "Helmet", 0
w_chestplate: db "Chestplate", 0
w_leggings:   db "Leggings", 0
w_boots:      db "Boots", 0
w_ring:       db "Ring", 0
w_amulet:     db "Amulet", 0
s_tier:       db " - Tier ", 0
s_attack:     db "Attack ", 0
s_armor:      db "Armor ", 0
s_hammer:     db "Hammer: stuns on hit", 0
s_spear:      db "Spear: long reach", 0
s_compare:    db "Shift: compare", 0
s_durability: db "Durability ", 0

p_king1:      db "+50% damage to elites and bosses;", 0
p_king2:      db "parries heal 10% health", 0
p_arch1:      db "Every 4th staff bolt is a fireball", 0
p_celes1:     db "No arrows needed, x1.5 damage;", 0
p_celes2:     db "crits shock the target", 0
p_fang1:      db "Hits add 2 poison stacks;", 0
p_fang2:      db "backstab kills reset Shadowstep", 0
p_phoe1:      db "A killing blow heals you to half", 0
p_phoe2:      db "health (once per 2 minutes)", 0
p_storm1:     db "Crits arc to 3 nearby foes", 0
p_storm2:     db "for 50% as shock", 0
p_ember1:     db "Burning foes take +30% damage;", 0
p_ember2:     db "+20% fire damage", 0
p_viper1:     db "Poison stacks up to 20;", 0
p_viper2:     db "+25% poison damage", 0

align 8
rarity_words: dq w_common, w_magic, w_rare, w_epic, w_legendary
kind_words:   dq w_weapon, w_bow, w_staff, w_helmet, w_chestplate, w_leggings, w_boots
              dq w_ring, w_amulet
; the description lines of a legendary power: two string pointers (0 = no line) per LP_*
power_lines:
    dq 0, 0
    dq p_king1, p_king2
    dq p_arch1, 0
    dq p_celes1, p_celes2
    dq p_fang1, p_fang2
    dq p_phoe1, p_phoe2
    dq p_storm1, p_storm2
    dq p_ember1, p_ember2
    dq p_viper1, p_viper2

align 4
rarity_colors:                          ; common, magic, rare, epic, legendary
    dd RGBA(255, 255, 255, 255), RGBA(100, 150, 255, 255), RGBA(255, 230, 90, 255)
    dd RGBA(190, 110, 255, 255), RGBA(255, 150, 40, 255)

section .data
align 4
gear_powers: dd 0                       ; bit 1 << LP_* of every equipped legendary
gr_private:  dd 0                       ; 1 inside gear_fill_chest: rolls use the private stream
gr_state:    dd 0                       ; the private stream's counter
tip_flip:    dd 0                       ; which half of tip_buf the last item_tooltip filled

section .bss
alignb 8
tip_buf: resb 2 * TIP_LINES * TIP_SLOT  ; two tooltips' line texts, used alternately

section .text

; ---- random numbers ---------------------------------------------------------------------------

; mix32(eax x) -> eax. The integer finalizer the decode and the chest stream are built on:
; x ^= x >> 16; x *= 0x7FEB352D; x ^= x >> 15; x *= 0x846CA68B; x ^= x >> 16. Clobbers ecx.
mix32:
    mov     ecx, eax
    shr     ecx, 16
    xor     eax, ecx
    imul    eax, eax, 0x7FEB352D
    mov     ecx, eax
    shr     ecx, 15
    xor     eax, ecx
    mov     ecx, 0x846CA68B
    imul    eax, ecx
    mov     ecx, eax
    shr     ecx, 16
    xor     eax, ecx
    ret

; gr_next() -> eax. The next random number of the gear rolls: the global rng_next stream, except
; inside gear_fill_chest, which runs a private mix32 stream so that a chest depends on its seed
; alone. Clobbers ecx.
gr_next:
    cmp     dword [gr_private], 0
    je      rng_next
    mov     eax, [gr_state]
    add     eax, 0x9E3779B9
    mov     [gr_state], eax
    jmp     mix32

; ---- decoding ---------------------------------------------------------------------------------

; decode(edi id, esi dmg, rdx out GEARAFFIX[5], rcx rows byte[5]) -> eax count
; The affixes of a stack, a pure function of (id, dmg). Their number follows the rarity bits (0, 2,
; 4, 5 for common .. epic). Affix k is entry h % size of the pool (the affix_tab rows whose kinds
; include the item's gear kind, in table order), h = mix32(seed ^ id' << 10 ^ k << 20 ^
; 0x9E3779B9) with id' = id - FIRST_ITEM + 128, moved on (wrapping) past the rows already taken. Its value lies between
; lo + tier * tlo and hi + tier * thi, at r = (h >> 16) & 255 of 255, times 5/4 for an epic, and is
; at least 1. rows[k] receives the affix_tab row of affix k. 0 for non-gear ids and common stacks.
; Frame: [rsp] pool[44], +44 pool size, +48 count, +52 rarity bits, +56 k.
decode:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 72
    mov     rbx, rdx
    mov     r15, rcx
    mov     r12d, edi
    cmp     r12d, NUM_ITEMS
    jae     .none
    lea     rax, [item_gear]
    movzx   r8d, byte [rax + r12]       ; r8d = gear kind
    test    r8d, r8d
    jz      .none
    mov     eax, esi
    shr     eax, GEAR_RARITY_SHIFT
    and     eax, 3
    mov     [rsp + 52], eax
    lea     rcx, [affix_counts]
    movzx   eax, byte [rcx + rax]
    test    eax, eax
    jz      .none
    mov     [rsp + 48], eax
    mov     r13d, esi
    and     r13d, GEAR_SEED_MASK        ; seed
    mov     r14d, esi
    shr     r14d, GEAR_TIER_SHIFT
    and     r14d, 15                    ; tier
    lea     r9, [affix_tab]             ; the pool: rows whose kinds include this kind
    xor     ecx, ecx
    xor     r10d, r10d
.pool:
    movzx   eax, word [r9 + AFFIXDEF.kinds]
    bt      eax, r8d
    jnc     .pool_next
    mov     [rsp + r10], cl
    inc     r10d
.pool_next:
    add     r9, AFFIXDEF_size
    inc     ecx
    cmp     ecx, NUM_AFFIXES
    jb      .pool
    test    r10d, r10d
    jz      .none
    mov     [rsp + 44], r10d
    xor     esi, esi                    ; rsi = rows taken, one bit each
    mov     dword [rsp + 56], 0
.pick:
    mov     eax, [rsp + 56]
    cmp     eax, [rsp + 48]
    jae     .done
    shl     eax, 20                     ; k << 20
    lea     ecx, [r12 - FIRST_ITEM + 128]   ; the 0.8 numbering (items from 128): rolls are
    shl     ecx, 10                     ; unchanged by moving FIRST_ITEM; id' << 10
    xor     eax, ecx
    xor     eax, r13d
    xor     eax, 0x9E3779B9
    call    mix32
    mov     r11d, eax                   ; h
    xor     edx, edx
    div     dword [rsp + 44]
    mov     r10d, edx                   ; position in the pool
.find:
    movzx   ecx, byte [rsp + r10]       ; its table row
    bt      rsi, rcx
    jnc     .take
    inc     r10d                        ; taken already: the next one, wrapping
    cmp     r10d, [rsp + 44]
    jb      .find
    xor     r10d, r10d
    jmp     .find
.take:
    bts     rsi, rcx
    mov     r8d, ecx                    ; row
    shl     ecx, 4                      ; * AFFIXDEF_size
    lea     r9, [affix_tab]
    add     r9, rcx
    movzx   eax, byte [r9 + AFFIXDEF.tlo]
    imul    eax, r14d
    movzx   ecx, byte [r9 + AFFIXDEF.lo]
    add     ecx, eax                    ; lo' = lo + tier * tlo
    movzx   eax, byte [r9 + AFFIXDEF.thi]
    imul    eax, r14d
    movzx   edx, byte [r9 + AFFIXDEF.hi]
    add     eax, edx                    ; hi' = hi + tier * thi
    sub     eax, ecx
    mov     r10d, r11d
    shr     r10d, 16
    movzx   r10d, r10b                  ; r = (h >> 16) & 255
    imul    eax, r10d
    xor     edx, edx
    mov     r10d, 255
    div     r10d
    add     eax, ecx                    ; v = lo' + r * (hi' - lo') / 255
    cmp     dword [rsp + 52], RAR_EPIC
    jne     .floor
    lea     eax, [rax + rax*4]
    shr     eax, 2                      ; epic: v * 5 / 4
.floor:
    mov     edx, 1
    cmp     eax, edx
    cmovl   eax, edx                    ; at least 1
    mov     ecx, [rsp + 56]
    movzx   edx, byte [r9 + AFFIXDEF.stat]
    mov     [rbx + rcx*8 + GEARAFFIX.stat], edx
    mov     [rbx + rcx*8 + GEARAFFIX.value], eax
    mov     [r15 + rcx], r8b
    inc     ecx
    mov     [rsp + 56], ecx
    jmp     .pick
.done:
    mov     eax, [rsp + 48]
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    add     rsp, 72
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; gear_affixes(edi id, esi dmg, rdx out GEARAFFIX[5]) -> eax count
; Decodes the affixes of a stack (see decode): out[i] = {stat, value}. 0 for non-gear ids, common
; stacks and dmg 0. Deterministic: the same (id, dmg) always gives the same affixes.
gear_affixes:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 16                     ; rows[5]
    mov     rcx, rsp
    call    decode
    leave
    ret

; gear_rarity(edi id, esi dmg) -> eax RAR_*
; The rarity bits of a gear stack; RAR_LEGENDARY for the legendary items; RAR_COMMON for non-gear.
gear_rarity:
    mov     edi, edi
    xor     eax, eax
    cmp     edi, NUM_ITEMS
    jae     .ret
    lea     rcx, [item_gear]
    cmp     byte [rcx + rdi], 0
    je      .ret
    lea     rcx, [item_legendary]
    cmp     byte [rcx + rdi], 0
    je      .bits
    mov     eax, RAR_LEGENDARY
    ret
.bits:
    mov     eax, esi
    shr     eax, GEAR_RARITY_SHIFT
    and     eax, 3
.ret:
    ret

; gear_rarity_color(edi rarity) -> eax RGBA (white for an unknown rarity)
gear_rarity_color:
    xor     eax, eax
    cmp     edi, RAR_LEGENDARY
    cmova   edi, eax
    mov     edi, edi
    lea     rcx, [rarity_colors]
    mov     eax, [rcx + rdi*4]
    ret

; gear_name(edi id, esi dmg, rdx out byte[48]) -> rax out
; The display name: "<word of the first affix> <item name>" for a magic, rare or epic gear stack,
; the plain item name for everything else (common gear, legendaries, non-gear). "?" for an unknown
; id. Frame: [rsp] GEARAFFIX[5] (40 bytes), +40 rows[5].
gear_name:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 48
    mov     rbx, rdx
    mov     r12d, edi
    cmp     edi, NUM_ITEMS
    jae     .unknown
    lea     rax, [item_legendary]
    cmp     byte [rax + r12], 0
    jne     .plain                      ; legendaries keep their own name
    mov     rdx, rsp
    lea     rcx, [rsp + 40]
    call    decode
    test    eax, eax
    jz      .plain
    movzx   eax, byte [rsp + 40]        ; the first affix's row
    shl     eax, 4
    lea     rcx, [affix_tab]
    mov     rsi, [rcx + rax + AFFIXDEF.word]
    mov     rdi, rbx
    call    str_append
    mov     byte [rax], ' '
    inc     rax
    jmp     .base
.plain:
    mov     rax, rbx
.base:
    mov     rdi, rax
    lea     rcx, [item_names]
    mov     rsi, [rcx + r12*8]
    call    str_append
    mov     byte [rax], 0
    mov     rax, rbx
    jmp     .out
.unknown:
    mov     word [rbx], '?'             ; "?" and its NUL
    mov     rax, rbx
.out:
    add     rsp, 48
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- what the player has equipped -------------------------------------------------------------

; gear_add_stats(rdi stats dword[NUM_STATS])
; Adds the affixes of what the player has equipped to stats: the held hotbar stack when it is a
; weapon (GK_MELEE, GK_BOW, GK_STAFF), the 4 armor cells and the 3 jewelry cells. A legendary item
; also adds its implicit stat (King's Blade +50 elite damage, Ember Amulet +20 fire damage, Viper
; Amulet +25 poison damage) and sets its bit in gear_powers, which every call rebuilds.
; Frame: [rsp] GEARAFFIX[5] (40 bytes), +40 rows[5]. r14d walks the candidates: 0 the held stack,
; 1..4 armor, 5..7 jewelry.
gear_add_stats:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 48
    mov     rbx, rdi
    xor     r13d, r13d                  ; powers
    xor     r14d, r14d
.cand:
    lea     rcx, [inv]
    test    r14d, r14d
    jnz     .worn
    mov     eax, [inv_sel]
    cmp     eax, HOTBAR_SLOTS
    jae     .skip
    lea     r12, [rcx + rax*4]
    jmp     .check
.worn:
    lea     r12, [rcx + INVENTORY.armor - 4]
    cmp     r14d, 4
    jbe     .addr
    lea     r12, [rcx + INVENTORY.jewelry - 5*4]
.addr:
    lea     r12, [r12 + r14*4]
.check:
    cmp     byte [r12 + ITEMSTACK.count], 0
    je      .skip
    movzx   edi, byte [r12 + ITEMSTACK.id]
    cmp     edi, NUM_ITEMS
    jae     .skip
    lea     rax, [item_gear]
    movzx   eax, byte [rax + rdi]
    test    eax, eax
    jz      .skip                       ; not gear
    test    r14d, r14d
    jnz     .apply
    cmp     eax, GK_STAFF
    ja      .skip                       ; armor and jewelry in the hotbar do nothing
.apply:
    movzx   esi, word [r12 + ITEMSTACK.dmg]
    mov     rdx, rsp
    lea     rcx, [rsp + 40]
    call    decode
    xor     ecx, ecx
.add:
    cmp     ecx, eax
    jae     .implicit
    mov     edx, [rsp + rcx*8 + GEARAFFIX.stat]
    mov     esi, [rsp + rcx*8 + GEARAFFIX.value]
    add     [rbx + rdx*4], esi
    inc     ecx
    jmp     .add
.implicit:
    movzx   eax, byte [r12 + ITEMSTACK.id]
    lea     rcx, [item_legendary]
    movzx   eax, byte [rcx + rax]       ; legendary power
    test    eax, eax
    jz      .skip
    cmp     eax, LP_VIPER
    ja      .skip
    bts     r13d, eax
    lea     rcx, [implicit_stat]
    movzx   edx, byte [rcx + rax]
    lea     rcx, [implicit_value]
    movzx   esi, byte [rcx + rax]
    add     [rbx + rdx*4], esi          ; a power without an implicit adds 0
.skip:
    inc     r14d
    cmp     r14d, 8
    jb      .cand
    mov     [gear_powers], r13d
    add     rsp, 48
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; gear_has_power(edi lp) -> eax 1 when an equipped item carries that legendary power (per the
; last gear_add_stats)
gear_has_power:
    xor     eax, eax
    cmp     edi, 31
    ja      .ret
    mov     ecx, [gear_powers]
    bt      ecx, edi
    setc    al
.ret:
    ret

; gear_equipped_for(edi id) -> rax ITEMSTACK* of the equipped item of the same gear kind, or 0
; Weapons compare with the held hotbar stack when it is of the same kind, armor with the worn
; piece of its slot, a ring with the first occupied ring cell, an amulet with the amulet cell.
gear_equipped_for:
    xor     eax, eax
    cmp     edi, NUM_ITEMS
    jae     .ret
    mov     edi, edi
    lea     rcx, [item_gear]
    movzx   edx, byte [rcx + rdi]       ; kind
    test    edx, edx
    jz      .ret
    lea     rcx, [inv]
    cmp     edx, GK_STAFF
    ja      .worn
    mov     esi, [inv_sel]              ; weapons: the held stack, when it is of this kind
    cmp     esi, HOTBAR_SLOTS
    jae     .ret
    lea     rax, [rcx + rsi*4]
    cmp     byte [rax + ITEMSTACK.count], 0
    je      .none
    movzx   esi, byte [rax + ITEMSTACK.id]
    cmp     esi, NUM_ITEMS
    jae     .none
    lea     rdi, [item_gear]
    cmp     dl, [rdi + rsi]
    jne     .none
    ret
.worn:
    cmp     edx, GK_FEET
    ja      .jewel
    lea     rax, [rcx + INVENTORY.armor + rdx*4 - GK_HEAD*4]
    jmp     .cell
.jewel:
    lea     rax, [rcx + INVENTORY.jewelry]
    cmp     edx, GK_AMULET
    je      .amulet
    cmp     byte [rax + ITEMSTACK.count], 0
    jne     .cell                       ; the first ring cell
    add     rax, 4
    jmp     .cell
.amulet:
    add     rax, 8
.cell:
    cmp     byte [rax + ITEMSTACK.count], 0
    jne     .ret
.none:
    xor     eax, eax
.ret:
    ret

; gear_stack_worn(rdi ITEMSTACK*) -> eax 1 when the pointer is one of the armor or jewelry cells of
; inv: a worn piece, which is its own comparison however many of its kind are worn
gear_stack_worn:
    lea     rax, [inv + INVENTORY.armor]
    lea     rcx, [inv + INVENTORY_size]
    cmp     rdi, rax
    setae   al
    cmp     rdi, rcx
    setb    cl
    and     al, cl
    movzx   eax, al
    ret

; ---- rolling ----------------------------------------------------------------------------------

; gear_make(edi id, esi tier, edx rarity, ecx seed) -> eax dmg
; The dmg word rarity << 14 | tier << 10 | seed of a gear item (tier and seed are masked to their
; fields; RAR_LEGENDARY, which only displays, makes RAR_RARE bits). 0 for a non-gear id.
gear_make:
    xor     eax, eax
    cmp     edi, NUM_ITEMS
    jae     .ret
    mov     edi, edi
    lea     r8, [item_gear]
    cmp     byte [r8 + rdi], 0
    je      .ret
    cmp     edx, RAR_EPIC
    jbe     .rarity
    mov     edx, RAR_RARE
.rarity:
    shl     edx, GEAR_RARITY_SHIFT
    and     esi, 15
    shl     esi, GEAR_TIER_SHIFT
    and     ecx, GEAR_SEED_MASK
    mov     eax, edx
    or      eax, esi
    or      eax, ecx
.ret:
    ret

; roll_rarity(edi r, esi table) -> eax RAR_COMMON .. RAR_EPIC
; r % (sum of the table's weights) picks the rarity; every non-common weight is first scaled by
; (100 + MAGIC_FIND) / 100 (integer), except in the private chest stream, which has no magic find so
; that a chest does not depend on who opens the world.
roll_rarity:
    sub     rsp, 24                     ; leaf: [rsp] the four scaled weights
    cmp     esi, LOOT_SHOP
    jbe     .table
    xor     esi, esi
.table:
    lea     r10, [loot_weights]
    lea     r10, [r10 + rsi*8]
    mov     ecx, 100
    cmp     dword [gr_private], 0
    jne     .factor
    add     ecx, [rpg_stats + STAT_MAGIC_FIND*4]
    jns     .factor
    xor     ecx, ecx
.factor:
    xor     r9d, r9d                    ; weight index
    xor     r8d, r8d                    ; total
.weights:
    movzx   eax, word [r10 + r9*2]
    test    r9d, r9d
    jz      .store
    imul    eax, ecx
    xor     edx, edx
    mov     r11d, 100
    div     r11d
.store:
    mov     [rsp + r9*4], eax
    add     r8d, eax
    inc     r9d
    cmp     r9d, 4
    jb      .weights
    xor     eax, eax
    test    r8d, r8d
    jz      .out
    mov     eax, edi
    xor     edx, edx
    div     r8d                         ; edx = r % total
    xor     eax, eax
.walk:
    mov     ecx, [rsp + rax*4]
    cmp     edx, ecx
    jb      .out
    sub     edx, ecx
    inc     eax
    cmp     eax, 3
    jb      .walk
.out:
    add     rsp, 24
    ret

; gear_roll(edi id, esi tier, edx table) -> eax dmg
; A fresh roll of that gear item: the rarity from the LOOT_* table (and magic find), the seed
; 1 + rng_next % 1023, packed by gear_make.
gear_roll:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    call    gr_next
    mov     edi, eax
    mov     esi, r13d
    call    roll_rarity
    mov     r13d, eax                   ; rarity
    call    gr_next
    xor     edx, edx
    mov     ecx, 1023
    div     ecx
    lea     ecx, [rdx + 1]              ; seed
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    call    gear_make
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; gear_tier_for_level(edi level) -> eax min(15, (level - 1) / 3)
gear_tier_for_level:
    lea     eax, [rdi - 1]
    xor     edx, edx
    test    eax, eax
    cmovs   eax, edx                    ; a level below 1 counts as 1
    xor     edx, edx
    mov     ecx, 3
    div     ecx
    mov     ecx, 15
    cmp     eax, ecx
    cmova   eax, ecx
    ret

; gear_pick_base(edi tier, esi class) -> eax item id
; The base item of a roll. c = r % 100: below 35 a weapon, below 75 a piece of armor, below 88 a
; ring, else an amulet. A weapon is of the class's own family 60 % of the time (warrior: sword,
; hammer or spear equally; mage staff; archer bow; rogue dagger; none sword), else any of sword,
; hammer, spear, dagger, bow, staff. Swords are wood at tier 0, stone at 1, iron 2..5, diamond from
; 6, golden 10 % of the time; hammers, spears and daggers iron below tier 6, else diamond. Armor
; is a random slot, iron below tier 6, else diamond, golden 15 % of the time.
gear_pick_base:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi                    ; tier
    mov     r12d, esi                   ; class
    call    gr_next
    xor     edx, edx
    mov     ecx, 100
    div     ecx
    cmp     edx, 35
    jb      .weapon
    cmp     edx, 75
    jb      .armor
    mov     eax, RING
    cmp     edx, 88
    jb      .ret
    mov     eax, AMULET
    jmp     .ret
.weapon:
    call    gr_next
    xor     edx, edx
    mov     ecx, 100
    div     ecx
    cmp     edx, 60
    jae     .any
    cmp     r12d, CLASS_WARRIOR
    je      .warrior
    xor     eax, eax
    cmp     r12d, NUM_CLASSES
    ja      .family
    lea     rcx, [class_family]
    movzx   eax, byte [rcx + r12]
    jmp     .family
.warrior:
    call    gr_next
    xor     edx, edx
    mov     ecx, 3
    div     ecx
    mov     eax, edx                    ; sword, hammer or spear
    jmp     .family
.any:
    call    gr_next
    xor     edx, edx
    mov     ecx, 6
    div     ecx
    mov     eax, edx
.family:
    cmp     eax, FAM_BOW
    jb      .melee
    mov     eax, BOW
    je      .ret
    mov     eax, STAFF
    jmp     .ret
.melee:
    test    eax, eax
    jnz     .pair
    call    gr_next                     ; a sword: 10 % golden, else by tier
    xor     edx, edx
    mov     ecx, 100
    div     ecx
    mov     eax, GOLD_SWORD
    cmp     edx, 10
    jb      .ret
    mov     eax, WOOD_SWORD
    test    ebx, ebx
    jz      .ret
    mov     eax, STONE_SWORD
    cmp     ebx, 1
    je      .ret
    mov     eax, IRON_SWORD
    cmp     ebx, 6
    jb      .ret
    mov     eax, DIAMOND_SWORD
    jmp     .ret
.pair:                                  ; hammer, spear, dagger
    lea     rcx, [melee_pair]
    movzx   eax, byte [rcx + rax]
    cmp     ebx, 6
    jb      .ret
    inc     eax                         ; the diamond one
    jmp     .ret
.armor:
    call    gr_next
    and     eax, 3
    mov     r12d, eax                   ; slot: head, chest, legs, feet
    call    gr_next
    xor     edx, edx
    mov     ecx, 100
    div     ecx
    mov     eax, 4                      ; golden set
    cmp     edx, 15
    jb      .piece
    xor     eax, eax                    ; iron
    cmp     ebx, 6
    jb      .piece
    mov     eax, 8                      ; diamond
.piece:
    add     eax, r12d
    add     eax, IRON_HELMET
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- drops ------------------------------------------------------------------------------------

; spawn_drop(edi id, esi dmg, rdx pos float[3]) -> eax sound rank
; Pops one gear item out at pos. The rank is 0 for a common or magic item, 1 for a rare or epic
; one and 2 for a legendary: how loud its find is announced.
spawn_drop:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12d, esi
    movss   xmm0, [rdx]
    movss   xmm1, [rdx + 4]
    movss   xmm2, [rdx + 8]
    mov     edx, esi
    mov     esi, 1
    call    drops_spawn
    mov     edi, ebx
    mov     esi, r12d
    call    gear_rarity
    mov     ecx, 2
    cmp     eax, RAR_LEGENDARY
    je      .rank
    mov     ecx, 1
    cmp     eax, RAR_RARE
    jae     .rank
    xor     ecx, ecx
.rank:
    mov     eax, ecx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; drop_roll(edi table, esi tier, edx class, rcx pos float[3]) -> eax sound rank
; One roll from a LOOT_* table: a base item for the tier and class, its rolled dmg, popped out.
drop_roll:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12d, edi
    mov     r13d, esi
    mov     r14, rcx
    mov     edi, esi
    mov     esi, edx
    call    gear_pick_base
    mov     ebx, eax                    ; id
    mov     edi, ebx
    mov     esi, r13d
    mov     edx, r12d
    call    gear_roll
    mov     edi, ebx
    mov     esi, eax
    mov     rdx, r14
    call    spawn_drop
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; legendary_drop(edi id, esi tier, rdx pos float[3]) -> eax sound rank
; Pops out a legendary item made RAR_RARE with a random seed.
legendary_drop:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, esi
    mov     r13, rdx
    call    rng_next
    xor     edx, edx
    mov     ecx, 1023
    div     ecx
    lea     ecx, [rdx + 1]
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, RAR_RARE
    call    gear_make
    mov     edi, ebx
    mov     esi, eax
    mov     rdx, r13
    call    spawn_drop
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; percent(edi n) -> eax 1 with n % probability (one rng_next)
percent:
    sub     rsp, 8
    mov     [rsp], edi
    call    rng_next
    xor     edx, edx
    mov     ecx, 100
    div     ecx
    xor     eax, eax
    cmp     edx, [rsp]
    setb    al
    add     rsp, 8
    ret

; keep the louder of the announced finds so far in [rsp + 12]
%macro KEEP_LOUDEST 0
    cmp     eax, [rsp + 12]
    jbe     %%keep
    mov     [rsp + 12], eax
%%keep:
%endmacro

; gear_drop_from_mob(rdi MOB*)
; The gear a dead hostile mob drops, popped out at mid-body height; its tier follows the mob's
; level. A plain mob drops one LOOT_MOB roll 6 % of the time. An elite always drops one LOOT_ELITE
; roll and, 30 % of the time, a second. The Fallen King, and a faction's champion (a MOB_FOLK with role
; ROLE_CHAMPION), drop their class's legendary (made RAR_RARE), 3 LOOT_BOSS rolls and, 25 % of the
; time, one of the four legendary jewels. A rare or epic find plays SND_LOOT_RARE, a legendary one
; SND_LEGENDARY (one sound per death, the loudest).
; Frame: [rsp] x, +4 y, +8 z, +12 loudest rank so far.
gear_drop_from_mob:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40
    mov     rbx, rdi
    movss   xmm0, [rbx + BODY.x]
    movss   [rsp], xmm0
    movss   xmm1, [rbx + BODY.height]
    mulss   xmm1, [c_half]
    addss   xmm1, [rbx + BODY.y]
    movss   [rsp + 4], xmm1
    movss   xmm2, [rbx + BODY.z]
    movss   [rsp + 8], xmm2
    mov     dword [rsp + 12], 0
    mov     edi, [rbx + MOB.level]
    call    gear_tier_for_level
    mov     r12d, eax                   ; tier
    call    rpg_class
    mov     r13d, eax                   ; class
    cmp     dword [rbx + MOB.type], MOB_BOSS
    je      .boss
    cmp     dword [rbx + MOB.type], MOB_FOLK
    jne     .mob
    cmp     byte [rbx + MOB.role], ROLE_CHAMPION
    je      .boss                       ; a champion drops like the Fallen King
.mob:
    cmp     dword [rbx + MOB.elite], 0
    jne     .elite
    mov     edi, 6
    call    percent
    test    eax, eax
    jz      .sound
    mov     edi, LOOT_MOB
    jmp     .one
.elite:
    mov     edi, LOOT_ELITE
    mov     esi, r12d
    mov     edx, r13d
    mov     rcx, rsp
    call    drop_roll
    KEEP_LOUDEST
    mov     edi, 30
    call    percent
    test    eax, eax
    jz      .sound
    mov     edi, LOOT_ELITE
.one:
    mov     esi, r12d
    mov     edx, r13d
    mov     rcx, rsp
    call    drop_roll
    KEEP_LOUDEST
    jmp     .sound
.boss:
    mov     eax, r13d
    cmp     eax, NUM_CLASSES
    jbe     .class
    xor     eax, eax                    ; a garbage class: the warrior's blade
.class:
    lea     rcx, [t_legendary]
    movzx   edi, byte [rcx + rax]
    mov     esi, r12d
    mov     rdx, rsp
    call    legendary_drop
    KEEP_LOUDEST
    mov     r15d, 3
.boss_loot:
    mov     edi, LOOT_BOSS
    mov     esi, r12d
    mov     edx, r13d
    mov     rcx, rsp
    call    drop_roll
    KEEP_LOUDEST
    dec     r15d
    jnz     .boss_loot
    mov     edi, 25
    call    percent
    test    eax, eax
    jz      .sound
    call    rng_next                    ; one of the four legendary jewels
    and     eax, 3
    lea     edi, [rax + PHOENIX_RING]
    mov     esi, r12d
    mov     rdx, rsp
    call    legendary_drop
    KEEP_LOUDEST
.sound:
    mov     eax, [rsp + 12]
    test    eax, eax
    jz      .ret
    mov     edi, SND_LOOT_RARE
    cmp     eax, 2
    jb      .play
    mov     edi, SND_LEGENDARY
.play:
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    movss   xmm3, [c_vol]
    call    audio_play_at
.ret:
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; gear_fill_chest(rdi CONTAINER*, esi table, edx tier, ecx count, r8d seed)
; Writes count gear stacks (count 1, base item and roll from the LOOT_* table at that tier) into
; the lowest free cells of the chest. The rolls come from a private mix32 stream started at seed,
; with no magic find and no class, so the same arguments always fill the same chest.
gear_fill_chest:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8                      ; [rsp] the picked item id
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    mov     [gr_state], r8d
    mov     dword [gr_private], 1
    xor     r15d, r15d                  ; first cell not yet looked at
.stack:
    test    r14d, r14d
    jz      .end
.cell:
    cmp     r15d, 27
    jae     .end
    cmp     byte [rbx + CONTAINER.slots + r15*4 + ITEMSTACK.count], 0
    je      .free
    inc     r15d
    jmp     .cell
.free:
    mov     edi, r13d
    xor     esi, esi
    call    gear_pick_base
    mov     [rsp], eax
    mov     edi, eax
    mov     esi, r13d
    mov     edx, r12d
    call    gear_roll
    shl     eax, 16                     ; dmg
    movzx   ecx, byte [rsp]
    or      eax, ecx
    or      eax, 0x100                  ; count 1
    mov     [rbx + CONTAINER.slots + r15*4], eax
    inc     r15d
    dec     r14d
    jmp     .stack
.end:
    mov     dword [gr_private], 0
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- tooltips ---------------------------------------------------------------------------------

; the slot of line n holds its text: record the line (pointer, colour %1) and advance n
%macro PUSHLINE 1
    mov     ecx, r14d
    shl     ecx, 6                      ; * TIP_SLOT
    lea     rcx, [r15 + rcx]
    mov     [r12 + r14*8], rcx
    mov     dword [r13 + r14*4], %1
    inc     r14d
%endmacro

; EMIT_STR colour: line n = the zstring in rsi
%macro EMIT_STR 1
    mov     eax, r14d
    shl     eax, 6
    lea     rdi, [r15 + rax]
    call    str_append
    mov     byte [rax], 0
    PUSHLINE %1
%endmacro

; item_tooltip(rdi ITEMSTACK*, rsi lines qword[12], rdx colours dword[12]) -> eax line count
; The lines of a stack's tooltip. Gear: its name in the rarity colour; "<Rarity> <kind> - Tier T"
; (no tier for a common stack); "Attack N" or "Armor N" (a weapon's base attack, an armor piece's
; points) plus a note for hammers and spears; one line per affix; the legendary power; and
; "Shift: compare" when something else of its kind is equipped (not for a stack that is itself worn).
; Any other item: its name and its
; durability left. 0 lines for an empty stack or an unknown id. The texts live in two static
; buffers used alternately, so the lines of the last two calls stay valid (the inventory draws the
; hovered stack and the equipped one together).
; Frame: [rsp] GEARAFFIX[5] + rows[5] (48 bytes), +48 id, +52 dmg, +56 rarity, +60 kind,
; +64 scratch (a value, the affix count or a table row pointer), +68 affix index.
; rbx = the stack, r12 / r13 = line and colour arrays, r14d = lines so far, r15 = this call's buffer.
item_tooltip:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 72
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    xor     r14d, r14d
    cmp     byte [rbx + ITEMSTACK.count], 0
    je      .done
    movzx   eax, byte [rbx + ITEMSTACK.id]
    cmp     eax, NUM_ITEMS
    jae     .done
    mov     [rsp + 48], eax
    movzx   ecx, word [rbx + ITEMSTACK.dmg]
    mov     [rsp + 52], ecx
    mov     edx, [tip_flip]             ; this call's half of the buffer
    xor     edx, 1
    mov     [tip_flip], edx
    imul    edx, edx, TIP_LINES * TIP_SLOT
    lea     r15, [tip_buf]
    add     r15, rdx
    lea     rcx, [item_gear]
    movzx   eax, byte [rcx + rax]
    mov     [rsp + 60], eax
    test    eax, eax
    jnz     .gear

    ; ---- anything else: the name, the durability left
    mov     edx, r14d
    shl     edx, 6
    add     rdx, r15
    mov     edi, [rsp + 48]
    mov     esi, [rsp + 52]
    call    gear_name
    PUSHLINE COL_WHITE
    mov     ecx, [rsp + 48]
    lea     rax, [item_durability]
    movzx   edx, word [rax + rcx*2]     ; the full durability
    test    edx, edx
    jz      .done
    mov     [rsp + 64], edx
    movzx   eax, word [rbx + ITEMSTACK.dmg]
    cmp     eax, edx
    cmova   eax, edx
    sub     edx, eax
    mov     [rsp + 68], edx             ; what is left
    mov     eax, r14d
    shl     eax, 6
    lea     rdi, [r15 + rax]
    lea     rsi, [s_durability]
    call    str_append
    mov     edi, [rsp + 68]
    mov     rsi, rax
    call    i32_to_str
    mov     byte [rax], '/'
    inc     rax
    mov     edi, [rsp + 64]
    mov     rsi, rax
    call    i32_to_str
    mov     byte [rax], 0
    PUSHLINE COL_GREY
    jmp     .done

    ; ---- gear: name in the rarity colour
.gear:
    mov     edi, [rsp + 48]
    mov     esi, [rsp + 52]
    call    gear_rarity
    mov     [rsp + 56], eax
    mov     edx, r14d
    shl     edx, 6
    add     rdx, r15
    mov     edi, [rsp + 48]
    mov     esi, [rsp + 52]
    call    gear_name
    mov     edi, [rsp + 56]
    call    gear_rarity_color
    mov     esi, eax
    PUSHLINE esi

    ; "<Rarity> <kind>" and, when the stack carries a roll, " - Tier T"
    mov     eax, r14d
    shl     eax, 6
    lea     rdi, [r15 + rax]
    mov     eax, [rsp + 56]
    lea     rcx, [rarity_words]
    mov     rsi, [rcx + rax*8]
    call    str_append
    mov     byte [rax], ' '
    inc     rax
    mov     rdi, rax
    mov     eax, [rsp + 60]
    lea     rcx, [kind_words]
    mov     rsi, [rcx + rax*8 - 8]
    call    str_append
    test    dword [rsp + 52], 0xC000
    jz      .line2_end
    mov     rdi, rax
    lea     rsi, [s_tier]
    call    str_append
    mov     edi, [rsp + 52]
    shr     edi, GEAR_TIER_SHIFT
    and     edi, 15
    mov     rsi, rax
    call    i32_to_str
.line2_end:
    mov     byte [rax], 0
    PUSHLINE COL_GREY

    ; "Attack N" (weapons) or "Armor N" (armor); jewelry has neither
    mov     eax, [rsp + 60]
    mov     ecx, [rsp + 48]
    cmp     eax, GK_STAFF
    ja      .armor
    lea     rsi, [s_attack]
    cmp     eax, GK_MELEE
    jne     .ranged
    lea     rdx, [item_attack]
    movzx   edx, byte [rdx + rcx]
    jmp     .value
.ranged:
    cmp     eax, GK_BOW
    jne     .staff
    mov     edx, ATK_BOW
    cmp     ecx, CELESTIAL_BOW
    jne     .value
    mov     edx, ATK_CELESTIAL
    jmp     .value
.staff:
    mov     edx, ATK_STAFF
    cmp     ecx, ARCHMAGE_STAFF
    jne     .value
    mov     edx, ATK_ARCHMAGE
    jmp     .value
.armor:
    cmp     eax, GK_FEET
    ja      .affixes
    lea     rsi, [s_armor]
    lea     rdx, [item_armor_points]
    movzx   edx, byte [rdx + rcx]
.value:
    mov     [rsp + 64], edx
    mov     eax, r14d
    shl     eax, 6
    lea     rdi, [r15 + rax]
    call    str_append
    mov     edi, [rsp + 64]
    mov     rsi, rax
    call    i32_to_str
    mov     byte [rax], 0
    PUSHLINE COL_WHITE
    mov     ecx, [rsp + 48]             ; a note for the two tools with a rule of their own
    lea     rax, [item_tool]
    movzx   eax, byte [rax + rcx]
    lea     rsi, [s_hammer]
    cmp     eax, TOOL_HAMMER
    je      .note
    lea     rsi, [s_spear]
    cmp     eax, TOOL_SPEAR
    jne     .affixes
.note:
    EMIT_STR COL_WHITE

    ; one line per affix
.affixes:
    mov     edi, [rsp + 48]
    mov     esi, [rsp + 52]
    mov     rdx, rsp
    lea     rcx, [rsp + 40]
    call    decode
    mov     [rsp + 64], eax
    mov     dword [rsp + 68], 0
.affix:
    mov     ecx, [rsp + 68]
    cmp     ecx, [rsp + 64]
    jae     .power
    mov     eax, r14d
    shl     eax, 6
    lea     rdx, [r15 + rax]
    mov     edi, [rsp + rcx*8 + GEARAFFIX.stat]
    mov     esi, [rsp + rcx*8 + GEARAFFIX.value]
    call    rpg_format_stat
    PUSHLINE COL_AFFIX
    inc     dword [rsp + 68]
    jmp     .affix

    ; the legendary power's lines
.power:
    mov     ecx, [rsp + 48]
    lea     rax, [item_legendary]
    movzx   eax, byte [rax + rcx]
    test    eax, eax
    jz      .compare
    shl     eax, 4                      ; two pointers per power
    lea     rcx, [power_lines]
    add     rcx, rax
    mov     [rsp + 64], rcx
    mov     rsi, [rcx]
    EMIT_STR COL_POWER
    mov     rcx, [rsp + 64]
    mov     rsi, [rcx + 8]
    test    rsi, rsi
    jz      .compare
    EMIT_STR COL_POWER

    ; something else of its kind is equipped
.compare:
    mov     rdi, rbx
    call    gear_stack_worn
    test    eax, eax
    jnz     .done                       ; it is itself worn: nothing to compare with
    mov     edi, [rsp + 48]
    call    gear_equipped_for
    test    rax, rax
    jz      .done
    cmp     rax, rbx
    je      .done
    lea     rsi, [s_compare]
    EMIT_STR COL_HINT
.done:
    mov     eax, r14d
    add     rsp, 72
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
