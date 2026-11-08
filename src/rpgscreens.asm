; rpgscreens.asm - the RPG screens: class selection, skill tree, character sheet, merchant trade
; and the elder's quest dialog. Immediate mode like invscreen.asm / menus.asm: every screen_*()
; runs once per frame after ui_begin (app.asm draw_frame), reads ui_input / frame_input and
; changes state with app_goto. A screen that acts returns at once, so one click never reaches two
; widgets.
;  - ST_SKILLS, ST_CHARACTER, ST_TRADE and ST_DIALOG close (back to ST_PLAYING) on Escape, the
;    inventory key or the skills key. The first frame after a state change only clears
;    app_entered: the key edge that opened the screen is still set in that frame and must not
;    close it. Tab switches between the skill tree and the character sheet.
;  - ST_CLASS cannot be closed: Escape saves and quits to the title, a card's button picks
;    the class (rpg_set_class) and starts playing.
; All progression data (class cards, node texts, branch names, stats, attributes, quests, trades)
; comes from rpg.asm / quests.asm (Module API); the only text owned here is the UI wording.
%include "common.inc"
%include "gl.inc"
default rel

global screen_class, screen_skills, screen_character, screen_trade, screen_dialog

extern ui_w, ui_h, ui_mx, ui_my, ui_input, frame_input, settings, app_entered
extern ui_rect, ui_frame, ui_panel, ui_text, ui_text_width, ui_text_centered
extern ui_button, ui_item_icon, ui_tile_icon, ui_tooltip
extern app_goto, app_quit_to_title, key_name
extern item_names, item_gear, inv_count, i32_to_str, str_append, armor_points
extern surv, surv_max_health, combat_weapon_preview, gear_tier_for_level
extern rpg_state, rpg_stats, rpg_class, rpg_level, rpg_points, rpg_xp_need, rpg_rank
extern rpg_can_spend, rpg_spend, rpg_set_class, rpg_class_info, rpg_node_info
extern rpg_branch_name, rpg_stat_info, rpg_format_stat, rpg_recompute
extern rpg_attr, rpg_attr_points, rpg_spend_attr, rpg_attr_info, rpg_attr_desc
extern rpg_respec_cost, rpg_respec, rpg_ability_tile
extern quests_current, quests_progress, quests_accept, quests_can_complete, quests_complete
extern trade_offer, trade_can, trade_execute

; ---- colours ------------------------------------------------------------------------------
%define WHITE       0xFFFFFFFF
%define GOLD        RGBA(255, 215, 60, 255)
%define LABEL_COL   RGBA(220, 220, 220, 255)
%define GREY        RGBA(128, 128, 128, 255)
%define GREEN       RGBA(140, 255, 90, 255)
%define RED         RGBA(255, 85, 85, 255)
%define PANEL_COL   RGBA(62, 62, 68, 235)
%define EDGE_COL    RGBA(255, 255, 255, 70)
%define DIM_COL     RGBA(0, 0, 0, 100)
%define COL_MAXED   RGBA(255, 200, 60, 255)
%define COL_RANKED  RGBA(120, 220, 90, 255)
%define COL_SPEND   RGBA(255, 255, 255, 200)
%define COL_LOCKED  RGBA(90, 90, 90, 255)
%define XP_COL      RGBA(120, 220, 60, 255)
%define COL_KEYSTONE RGBA(255, 200, 60, 255)

; ---- geometry (GUI units) -----------------------------------------------------------------
%define CARD_W      100                 ; class cards
%define CARD_H      150
%define CARD_Y      50
%define CARD_STEP   105
%define CARD_X0     210                 ; card 0 is at cx - CARD_X0

%define SK_W        270                 ; skill panel: 3 branches (SK_DX apart) of 6 tiers (SK_DY
%define SK_H        232                 ; apart) of 24 x 24 nodes, node (0, 0) at (SK_NX, SK_NY)
%define SK_NX       33
%define SK_NY       30
%define SK_DX       90
%define SK_DY       30

%define CH_W        300                 ; character sheet: attributes, summary, stat list
%define CH_H        232
%define CH_ROWS     16                  ; stat list: rows per column (a power of two) ...
%define CH_COL0     8                   ; ... the x of its two columns ...
%define CH_COL1     154
%define CH_LIST_Y   70                  ; ... and the y of its first row
%define CH_COLW     142                 ; widest stat line a column holds (pen advance)

%define SH_OFFENSE  0xF0                ; sheet_order entries beyond the stat ids: group headers, end
%define SH_DEFENSE  0xF1
%define SH_UTILITY  0xF2
%define SH_END      0xFF

%define TR_W        220                 ; merchant panel
%define TR_H        236
%define DL_W        260                 ; elder panel
%define DL_H        144

%define TIP_MAXW    320                 ; skill tooltip wraps here
%define HINT_COL    RGBA(255, 150, 110, 255)

section .rodata
align 4
tier_req:       dd 1, 4, 9, 15, 22, 30  ; level needed by tier t (skill-tree rule, rpg.asm)
attr_tiles:     db TILE_ATTR_STR, TILE_ATTR_DEX, TILE_ATTR_INT, TILE_ATTR_VIT

; the stat list in display order: group header markers and stat ids
sheet_order:
    db SH_OFFENSE, STAT_MELEE_DMG, STAT_RANGED_DMG, STAT_SPELL_DMG, STAT_ALL_DMG, STAT_WEAPON_DMG
    db STAT_CRIT_CHANCE, STAT_CRIT_DMG, STAT_ATTACK_SPEED
    db STAT_FIRE_DMG, STAT_FROST_DMG, STAT_SHOCK_DMG, STAT_POISON_DMG
    db STAT_ADD_FIRE, STAT_ADD_FROST, STAT_ADD_SHOCK, STAT_ADD_POISON
    db STAT_BLEED_CHANCE, STAT_DOT_DMG, STAT_ELITE_DMG, STAT_AREA, STAT_BACKSTAB, STAT_LIFESTEAL
    db STAT_LIFE_ON_KILL
    db SH_DEFENSE, STAT_MAX_HEALTH, STAT_ARMOR_BONUS, STAT_RES_FIRE, STAT_RES_FROST
    db STAT_RES_SHOCK, STAT_RES_POISON, STAT_LIFE_REGEN, STAT_THORNS, STAT_BLOCK_COST
    db STAT_PARRY_WINDOW, STAT_DODGE_COST
    db SH_UTILITY, STAT_MAX_MANA, STAT_MANA_REGEN, STAT_MAX_STAMINA, STAT_STAMINA_REGEN
    db STAT_MOVE_SPEED, STAT_COOLDOWN_RED, STAT_ARROW_SAVE, STAT_XP_BONUS, STAT_GOLD_FIND
    db STAT_MAGIC_FIND
    db SH_END
sheet_order_end:
%if sheet_order_end - sheet_order != NUM_STATS + 4
%error "sheet_order lists every stat once, the three headers and the end marker"
%endif
align 8
sheet_head:     dq s_offense, s_defense, s_utility

s_choose_class: db "Choose your class", 0
s_choose:       db "Choose", 0
s_level_sep:    db " - Level ", 0
s_points:       db "Points: ", 0
s_attr_points:  db "Attribute points: ", 0
s_slash:        db "/", 0
s_space:        db " ", 0
s_colon_sp:     db ": ", 0
s_per_rank:     db " per rank", 0
s_keystone:     db " (Keystone)", 0
s_key:          db " - Key: ", 0
s_needs_level:  db "- needs level ", 0
s_needs_prev:   db "- needs previous skill", 0
s_tab_char:     db "Tab: Character", 0
s_tab_skills:   db "Tab: Skills", 0

s_offense:      db "Offense", 0
s_defense:      db "Defense", 0
s_utility:      db "Utility", 0
s_health:       db "Health ", 0
s_armor:        db "Armor ", 0
s_armor_mid:    db " (-", 0
s_armor_end:    db "% damage)", 0
s_hit:          db "Hit ", 0
s_crit:         db "  Crit ", 0
s_attacks:      db "Attacks ", 0
s_per_s:        db "/s", 0
s_plus:         db "+", 0
s_empty:        db 0

s_merchant:     db "Merchant", 0
s_coins:        db "Coins: ", 0
s_trade:        db "Trade", 0
s_arrow:        db "->", 0
s_random:       db "Random magic+ ", 0
s_tier_sep:     db ", tier ", 0

s_elder:        db "Elder", 0
s_saved:        db "The realm is saved. Rest, hero.", 0
s_farewell:     db "Farewell", 0
s_progress:     db "Progress: ", 0
s_accept:       db "Accept", 0
s_leave:        db "Leave", 0
s_complete:     db "Complete", 0
s_reset:        db "Reset skills: ", 0
s_coins_sfx:    db " coins", 0

section .bss
alignb 8
s_px:           resd 1                  ; panel origin of the screen being drawn
s_py:           resd 1
sheet_scroll:   resd 1                  ; first listed row of the character sheet's stat list
hdr_buf:        resb 64                 ; "<class> - Level N"
pts_buf:        resb 32                 ; "Points: N" / "Attribute points: N"
coin_buf:       resb 32                 ; "Coins: N" / "Progress: p/c" / counts / summary lines
rank_buf:       resb 16                 ; "r/m" on a skill node
fmt_buf:        resb 48                 ; one formatted stat
sheet_rows:     resb 64                 ; the stat list's visible rows (sheet_build)
tip_buf:        resb 256                ; skill tooltip text
tip_hint:       resb 64                 ; ... and its requirement hint
tip_row:        resb 128                ; one wrapped tooltip row
row_buf:        resb 128                ; one wrapped class-card row

; ---- macros ----------------------------------------------------------------------------------
%macro ENTER_FRAME 1                    ; frame with %1 bytes of locals (%1 = 8 mod 16)
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, %1
%endmacro
%macro LEAVE_FRAME 1
    add     rsp, %1
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
%endmacro
%macro TXTL 6                           ; label, xreg, xoff, yreg, yoff, rgba (1x, left aligned)
    lea     rdi, [%1]
    lea     esi, [%2 + %3]
    lea     edx, [%4 + %5]
    mov     ecx, %6
    mov     r8d, 1
    call    ui_text
%endmacro
%macro TXTC 6                           ; label, xreg, xoff, yreg, yoff, rgba (1x, centred on x)
    lea     rdi, [%1]
    lea     esi, [%2 + %3]
    lea     edx, [%4 + %5]
    mov     ecx, %6
    mov     r8d, 1
    call    ui_text_centered
%endmacro
%macro BTN 6                            ; label, xreg, xoff, yreg, yoff, w -> eax clicked
    lea     rdi, [%1]
    lea     esi, [%2 + %3]
    lea     edx, [%4 + %5]
    mov     ecx, %6
    mov     r8d, 1
    call    ui_button
%endmacro
; string building: r15 is the write cursor, the text is NUL terminated by the caller
%macro APPZ 1                           ; append the string at label %1
    mov     rdi, r15
    lea     rsi, [%1]
    call    str_append
    mov     r15, rax
%endmacro
%macro APPP 1                           ; append the string whose address is in %1
    mov     rdi, r15
    mov     rsi, %1
    call    str_append
    mov     r15, rax
%endmacro
%macro APPN 1                           ; append the decimal value of the 32-bit operand %1
    mov     edi, %1
    mov     rsi, r15
    call    i32_to_str
    mov     r15, rax
%endmacro

section .text

; ---- helpers ---------------------------------------------------------------------------------

; hit(edi x, esi y, edx w, ecx h) -> eax 1 if the mouse is inside the rectangle (leaf)
hit:
    mov     eax, [ui_mx]
    sub     eax, edi
    cmp     eax, edx                    ; unsigned: also rejects mx < x
    jae     .no
    mov     eax, [ui_my]
    sub     eax, esi
    cmp     eax, ecx
    jae     .no
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; panel_begin(edi w, esi h): dimmer over the screen, then a w x h panel centred on it
; (origin kept in s_px / s_py, y never above the screen)
panel_begin:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12d, esi
    mov     eax, [ui_w]
    sub     eax, ebx
    sar     eax, 1
    mov     [s_px], eax
    mov     eax, [ui_h]
    sub     eax, r12d
    sar     eax, 1
    xor     ecx, ecx
    test    eax, eax
    cmovs   eax, ecx
    mov     [s_py], eax
    xor     edi, edi
    xor     esi, esi
    mov     edx, [ui_w]
    mov     ecx, [ui_h]
    mov     r8d, DIM_COL
    call    ui_rect
    mov     edi, [s_px]
    mov     esi, [s_py]
    mov     edx, ebx
    mov     ecx, r12d
    mov     r8d, PANEL_COL
    call    ui_rect
    mov     edi, [s_px]
    mov     esi, [s_py]
    mov     edx, ebx
    mov     ecx, r12d
    mov     r8d, EDGE_COL
    call    ui_frame
    pop     r12
    pop     rbx
    pop     rbp
    ret

; close_check() -> eax 1 if the screen closed (back to ST_PLAYING) on Escape, the inventory
; key or the skills key. The first frame after a state change only clears app_entered.
close_check:
    sub     rsp, 8
    cmp     dword [app_entered], 0
    je      .test
    mov     dword [app_entered], 0
    xor     eax, eax
    jmp     .ret
.test:
    cmp     dword [frame_input + FRAMEINPUT.inventory], 0
    jne     .close
    cmp     dword [frame_input + FRAMEINPUT.skills], 0
    jne     .close
    cmp     dword [ui_input + UIINPUT.escape], 0
    je      .no
.close:
    mov     edi, ST_PLAYING
    call    app_goto
    mov     eax, 1
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    add     rsp, 8
    ret

; wrap_next(rdi pos, esi maxw, rdx buf) -> rax pointer past the row copied into buf, 0 when
; no text is left. Word wrap: a row takes as many whole words as fit in maxw GUI units; a
; first word that is too wide still gets a row of its own. buf receives at most 127 chars.
wrap_next:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12d, esi                   ; maxw
    mov     r13, rdx                    ; buf
.skip:
    cmp     byte [rbx], ' '
    jne     .start
    inc     rbx
    jmp     .skip
.start:
    cmp     byte [rbx], 0
    jne     .have
    mov     byte [r13], 0
    xor     eax, eax
    jmp     .ret
.have:
    xor     r14d, r14d                  ; end of the last candidate that fits (0 = none yet)
    mov     r15, rbx                    ; start of the word being tried
.word:
    mov     rax, r15
.wend:
    cmp     byte [rax], 0
    je      .wfound
    cmp     byte [rax], ' '
    je      .wfound
    inc     rax
    jmp     .wend
.wfound:                                ; rax = end of this word
    mov     [rsp], rax
    mov     rdi, r13                    ; buf = [row start, word end)
    mov     rsi, rbx
    mov     rcx, rax
    sub     rcx, rbx
    cmp     rcx, 127
    jbe     .copy
    mov     ecx, 127
.copy:
    rep movsb
    mov     byte [rdi], 0
    mov     rdi, r13
    mov     esi, 1
    call    ui_text_width
    dec     eax                         ; ink width: drop the trailing 1-unit gap
    cmp     eax, r12d
    jbe     .fits
    test    r14, r14
    jnz     .done                       ; too wide, and a shorter row is already known
.fits:
    mov     r14, [rsp]
    mov     r15, r14
.sp:
    cmp     byte [r15], ' '
    jne     .more
    inc     r15
    jmp     .sp
.more:
    cmp     byte [r15], 0
    jne     .word
.done:                                  ; buf = [row start, r14)
    mov     rdi, r13
    mov     rsi, rbx
    mov     rcx, r14
    sub     rcx, rbx
    cmp     rcx, 127
    jbe     .final
    mov     ecx, 127
.final:
    rep movsb
    mov     byte [rdi], 0
    mov     rax, r14
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; card_text(rdi zstr, esi cx, edx y, ecx rgba, r8d maxw) -> eax y below the paragraph
; 1x text word wrapped to maxw, every row centred on cx; rows are 10 units apart and the
; paragraph is followed by a 2-unit gap
card_text:
    ENTER_FRAME 8
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    mov     r15d, r8d
.row:
    mov     rdi, rbx
    mov     esi, r15d
    lea     rdx, [row_buf]
    call    wrap_next
    test    rax, rax
    jz      .done
    mov     rbx, rax
    lea     rdi, [row_buf]
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, r14d
    mov     r8d, 1
    call    ui_text_centered
    add     r13d, 10
    jmp     .row
.done:
    lea     eax, [r13 + 2]
    LEAVE_FRAME 8

; text_extent(rdi zstr, esi maxw) -> eax rows, edx widest row (ink width): the layout of a
; paragraph word wrapped to maxw
text_extent:
    ENTER_FRAME 8
    mov     rbx, rdi
    mov     r12d, esi
    xor     r13d, r13d                  ; rows
    xor     r14d, r14d                  ; widest row
.row:
    mov     rdi, rbx
    mov     esi, r12d
    lea     rdx, [tip_row]
    call    wrap_next
    test    rax, rax
    jz      .done
    mov     rbx, rax
    inc     r13d
    lea     rdi, [tip_row]
    mov     esi, 1
    call    ui_text_width
    dec     eax                         ; drop the trailing 1-unit gap
    cmp     eax, r14d
    cmova   r14d, eax
    jmp     .row
.done:
    mov     eax, r13d
    mov     edx, r14d
    LEAVE_FRAME 8

; text_rows(rdi zstr, esi maxw, edx x, ecx y, r8d rgba) -> eax y below the last row
; 1x paragraph word wrapped to maxw, left aligned at x, rows 10 units apart
text_rows:
    ENTER_FRAME 8
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    mov     r15d, r8d
.row:
    mov     rdi, rbx
    mov     esi, r12d
    lea     rdx, [tip_row]
    call    wrap_next
    test    rax, rax
    jz      .done
    mov     rbx, rax
    lea     rdi, [tip_row]
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, r15d
    mov     r8d, 1
    call    ui_text
    add     r14d, 10
    jmp     .row
.done:
    mov     eax, r14d
    LEAVE_FRAME 8

; tooltip_wrapped(rdi zstr, rsi hint): a tooltip panel at the mouse like ui_tooltip, but the
; text wraps at TIP_MAXW (and at the screen width) instead of running off the screen. The hint
; (may be empty) is a second paragraph in HINT_COL.
tooltip_wrapped:
    ENTER_FRAME 24                      ; [rsp] panel x, [rsp+4] y, [rsp+8] w, [rsp+12] h
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13d, TIP_MAXW
    mov     eax, [ui_w]
    sub     eax, 12
    cmp     eax, r13d
    cmovl   r13d, eax                   ; maxw
    mov     rdi, rbx
    mov     esi, r13d
    call    text_extent
    mov     r14d, eax                   ; rows
    mov     r15d, edx                   ; widest row
    test    r14d, r14d
    jz      .ret
    mov     rdi, r12
    mov     esi, r13d
    call    text_extent
    add     r14d, eax
    cmp     edx, r15d
    cmova   r15d, edx
    lea     eax, [r15 + 6]              ; panel: text + 3 padding each side
    mov     [rsp + 8], eax
    imul    eax, r14d, 10
    add     eax, 4
    mov     [rsp + 12], eax
    mov     ecx, [ui_mx]                ; x = mx + 12, kept on the screen
    add     ecx, 12
    mov     eax, [ui_w]
    sub     eax, [rsp + 8]
    cmp     ecx, eax
    cmovg   ecx, eax
    xor     eax, eax
    test    ecx, ecx
    cmovs   ecx, eax
    mov     [rsp], ecx
    mov     ecx, [ui_my]                ; y = my - 12
    sub     ecx, 12
    mov     eax, [ui_h]
    sub     eax, [rsp + 12]
    cmp     ecx, eax
    cmovg   ecx, eax
    xor     eax, eax
    test    ecx, ecx
    cmovs   ecx, eax
    mov     [rsp + 4], ecx
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    mov     edx, [rsp + 8]
    mov     ecx, [rsp + 12]
    call    ui_panel
    mov     rdi, rbx
    mov     esi, r13d
    mov     edx, [rsp]
    add     edx, 3
    mov     ecx, [rsp + 4]
    add     ecx, 3
    mov     r8d, WHITE
    call    text_rows
    mov     ecx, eax                    ; the hint continues below the text
    mov     rdi, r12
    mov     esi, r13d
    mov     edx, [rsp]
    add     edx, 3
    mov     r8d, HINT_COL
    call    text_rows
.ret:
    LEAVE_FRAME 24

; rank_text(edi rank, esi max, rdx buf) -> rax end (NUL written): "rank/max"
rank_text:
    push    r12
    mov     r12d, esi
    mov     rsi, rdx
    call    i32_to_str
    mov     byte [rax], '/'
    inc     rax
    mov     edi, r12d
    mov     rsi, rax
    call    i32_to_str
    mov     byte [rax], 0
    pop     r12
    ret

; ---- class selection ---------------------------------------------------------------------------

; screen_class(): four class cards; "Choose" calls rpg_set_class and starts playing,
; Escape saves and quits to the title (there is no other way out before a class is picked)
screen_class:
    ENTER_FRAME 24                      ; [rsp] line index
    mov     dword [app_entered], 0
    cmp     dword [ui_input + UIINPUT.escape], 0
    je      .draw
    call    app_quit_to_title
    jmp     .ret
.draw:
    xor     edi, edi
    xor     esi, esi
    mov     edx, [ui_w]
    mov     ecx, [ui_h]
    mov     r8d, RGBA(0, 0, 0, 150)
    call    ui_rect
    mov     r12d, [ui_w]
    shr     r12d, 1                     ; cx
    lea     rdi, [s_choose_class]
    mov     esi, r12d
    mov     edx, 20
    mov     ecx, WHITE
    mov     r8d, 2
    call    ui_text_centered
    sub     r12d, CARD_X0               ; x of card 0
    xor     ebx, ebx
.card:
    imul    r13d, ebx, CARD_STEP
    add     r13d, r12d                  ; card x
    lea     edi, [rbx + 1]
    call    rpg_class_info
    mov     r14, rax
    mov     edi, r13d
    mov     esi, CARD_Y
    mov     edx, CARD_W
    mov     ecx, CARD_H
    call    hit
    mov     r15d, eax                   ; hovered
    mov     r8d, PANEL_COL
    mov     eax, RGBA(86, 86, 98, 240)
    test    r15d, r15d
    cmovnz  r8d, eax
    mov     edi, r13d
    mov     esi, CARD_Y
    mov     edx, CARD_W
    mov     ecx, CARD_H
    call    ui_rect
    mov     r8d, EDGE_COL
    mov     eax, RGBA(255, 255, 255, 170)
    test    r15d, r15d
    cmovnz  r8d, eax
    mov     edi, r13d
    mov     esi, CARD_Y
    mov     edx, CARD_W
    mov     ecx, CARD_H
    call    ui_frame
    lea     edi, [rbx + TILE_CLASS0]
    lea     esi, [r13 + CARD_W / 2 - 16]
    mov     edx, CARD_Y + 8
    mov     ecx, 32
    mov     r8d, WHITE
    call    ui_tile_icon
    mov     rdi, [r14 + CLASSINFO.name]
    lea     esi, [r13 + CARD_W / 2]
    mov     edx, CARD_Y + 46
    mov     ecx, GOLD
    mov     r8d, 1
    call    ui_text_centered
    mov     r15d, CARD_Y + 62           ; y of the next paragraph
    mov     dword [rsp], 1
.line:
    mov     eax, [rsp]
    mov     rdi, [r14 + rax*8]          ; line1..line3 at +8, +16, +24
    lea     esi, [r13 + CARD_W / 2]
    mov     edx, r15d
    mov     ecx, LABEL_COL
    mov     r8d, CARD_W - 6
    call    card_text
    mov     r15d, eax
    inc     dword [rsp]
    cmp     dword [rsp], 3
    jbe     .line
    lea     rdi, [s_choose]
    lea     esi, [r13 + 5]
    mov     edx, CARD_Y + 124
    mov     ecx, CARD_W - 10
    mov     r8d, 1
    call    ui_button
    test    eax, eax
    jz      .next
    lea     edi, [rbx + 1]
    call    rpg_set_class
    mov     edi, ST_PLAYING
    call    app_goto
    jmp     .ret
.next:
    inc     ebx
    cmp     ebx, NUM_CLASSES
    jb      .card
.ret:
    LEAVE_FRAME 24

; ---- skill tree -----------------------------------------------------------------------------------

; screen_header(edi class, rsi points label, edx points, ecx panel width): "<class> - Level N" at
; the top left of the panel being drawn, "<label><points>" right aligned at its top right (green
; while there are points). Locals: [rsp] points, [rsp+4] panel width
screen_header:
    ENTER_FRAME 24
    mov     [rsp], edx
    mov     [rsp + 4], ecx
    mov     r14, rsi
    lea     r15, [hdr_buf]
    call    rpg_class_info
    APPP    [rax + CLASSINFO.name]
    APPZ    s_level_sep
    call    rpg_level
    APPN    eax
    mov     byte [r15], 0
    mov     r12d, [s_px]
    mov     r13d, [s_py]
    TXTL    hdr_buf, r12, 8, r13, 5, WHITE
    lea     r15, [pts_buf]
    APPP    r14
    APPN    dword [rsp]
    mov     byte [r15], 0
    lea     rdi, [pts_buf]
    mov     esi, 1
    call    ui_text_width
    mov     esi, [rsp + 4]
    lea     esi, [r12 + rsi - 8 + 1]    ; right aligned at px + width - 8
    sub     esi, eax
    mov     ecx, GREY
    mov     eax, GREEN
    cmp     dword [rsp], 0
    cmovg   ecx, eax
    lea     rdi, [pts_buf]
    lea     edx, [r13 + 5]
    mov     r8d, 1
    call    ui_text
    LEAVE_FRAME 24

; screen_skills(): header, xp bar, three branches of six nodes and a tooltip for the hovered node.
; A click on a node spends a skill point (rpg_spend); Tab opens the character sheet.
; Locals: [rsp] hovered node or -1, [rsp+4] class, [rsp+8] points, [rsp+16] can_spend result of the
; node being drawn, [rsp+20] its border colour, [rsp+24] node x, [rsp+28] node y, [rsp+32] its
; rank, [rsp+36] tier, [rsp+40] level required by the tier
screen_skills:
    ENTER_FRAME 56
    call    close_check
    test    eax, eax
    jnz     .ret
    cmp     dword [ui_input + UIINPUT.key_pressed], KEY_TAB
    jne     .no_tab
    mov     edi, ST_CHARACTER
    call    app_goto
    jmp     .ret
.no_tab:
    call    rpg_class
    mov     [rsp + 4], eax
    lea     ecx, [rax - 1]
    cmp     ecx, NUM_CLASSES
    jb      .have_class
    mov     edi, ST_PLAYING             ; no class yet: nothing to show
    call    app_goto
    jmp     .ret
.have_class:
    mov     edi, SK_W
    mov     esi, SK_H
    call    panel_begin
    mov     r12d, [s_px]
    mov     r13d, [s_py]
    ; ---- hovered node (branch = dx / SK_DX, tier = dy / SK_DY, each node 24 wide) and the click
    mov     dword [rsp], -1
    mov     eax, [ui_mx]
    sub     eax, r12d
    sub     eax, SK_NX
    js      .hover_done
    xor     edx, edx
    mov     ecx, SK_DX
    div     ecx
    cmp     edx, 24
    jae     .hover_done
    cmp     eax, 2
    ja      .hover_done
    mov     esi, eax                    ; branch
    mov     eax, [ui_my]
    sub     eax, r13d
    sub     eax, SK_NY
    js      .hover_done
    xor     edx, edx
    mov     ecx, SK_DY
    div     ecx
    cmp     edx, 24
    jae     .hover_done
    cmp     eax, NODES_PER_BRANCH - 1
    ja      .hover_done
    imul    esi, esi, NODES_PER_BRANCH
    add     eax, esi                    ; node = branch * 6 + tier
    mov     [rsp], eax
    cmp     dword [ui_input + UIINPUT.lmb_pressed], 0
    je      .hover_done
    mov     edi, eax
    call    rpg_spend
.hover_done:
    ; ---- header: "<class> - Level N" and "Points: N"
    call    rpg_points
    mov     [rsp + 8], eax
    mov     edx, eax
    mov     edi, [rsp + 4]
    lea     rsi, [s_points]
    mov     ecx, SK_W
    call    screen_header
    ; ---- xp bar: full at the maximum level
    lea     edi, [r12 + 8]
    lea     esi, [r13 + 15]
    mov     edx, SK_W - 16
    mov     ecx, 3
    mov     r8d, RGBA(0, 0, 0, 160)
    call    ui_rect
    call    rpg_level
    mov     edi, eax
    call    rpg_xp_need
    mov     ecx, SK_W - 16
    test    eax, eax
    jz      .xp_fill
    mov     esi, eax                    ; need
    mov     eax, [rpg_state + RPGSAVE.xp]
    imul    eax, eax, SK_W - 16
    xor     edx, edx
    div     esi
    mov     ecx, SK_W - 16
    cmp     eax, ecx
    cmovb   ecx, eax
.xp_fill:
    test    ecx, ecx
    jz      .xp_done
    lea     edi, [r12 + 8]
    lea     esi, [r13 + 15]
    mov     edx, ecx
    mov     ecx, 3
    mov     r8d, XP_COL
    call    ui_rect
.xp_done:
    ; ---- branch names, centred over their column of nodes
    xor     ebx, ebx
.branch:
    mov     edi, [rsp + 4]
    mov     esi, ebx
    call    rpg_branch_name
    mov     rdi, rax
    imul    esi, ebx, SK_DX
    lea     esi, [rsi + r12 + SK_NX + 12]
    lea     edx, [r13 + 21]
    mov     ecx, LABEL_COL
    mov     r8d, 1
    call    ui_text_centered
    inc     ebx
    cmp     ebx, 3
    jb      .branch
    ; ---- connectors: lit when the node above has a rank
    xor     ebx, ebx
.conn:
    mov     eax, ebx
    xor     edx, edx
    mov     ecx, NODES_PER_BRANCH
    div     ecx                         ; eax = branch, edx = tier
    cmp     edx, NODES_PER_BRANCH - 1
    je      .conn_next                  ; the last tier has nothing below it
    mov     r14d, eax
    mov     r15d, edx
    mov     edi, ebx
    call    rpg_rank
    mov     r8d, COL_LOCKED
    mov     edx, COL_SPEND
    test    eax, eax
    cmovnz  r8d, edx
    imul    edi, r14d, SK_DX
    lea     edi, [rdi + r12 + SK_NX + 11]
    imul    esi, r15d, SK_DY
    lea     esi, [rsi + r13 + SK_NY + 24]
    mov     edx, 2
    mov     ecx, SK_DY - 24
    call    ui_rect
.conn_next:
    inc     ebx
    cmp     ebx, NUM_NODES
    jb      .conn
    ; ---- nodes
    xor     ebx, ebx
.node:
    mov     edi, [rsp + 4]
    mov     esi, ebx
    call    rpg_node_info
    mov     r14, rax
    mov     edi, ebx
    call    rpg_rank
    mov     [rsp + 32], eax
    mov     edi, ebx
    call    rpg_can_spend
    mov     [rsp + 16], eax             ; 0 = a point can be spent here now
    mov     eax, ebx
    xor     edx, edx
    mov     ecx, NODES_PER_BRANCH
    div     ecx                         ; eax = branch, edx = tier
    imul    eax, eax, SK_DX
    lea     eax, [rax + r12 + SK_NX]
    mov     [rsp + 24], eax
    imul    edx, edx, SK_DY
    lea     edx, [rdx + r13 + SK_NY]
    mov     [rsp + 28], edx
    ; border: maxed, ranked, spendable, locked (in that priority); a keystone is always gold
    movzx   ecx, byte [r14 + NODEINFO.max]
    mov     eax, COL_LOCKED
    mov     edx, COL_SPEND
    cmp     dword [rsp + 16], 0
    cmove   eax, edx
    mov     edx, [rsp + 32]
    test    edx, edx
    jz      .border_set
    mov     eax, COL_RANKED
    mov     esi, COL_MAXED
    cmp     edx, ecx
    cmovae  eax, esi
.border_set:
    mov     edx, COL_KEYSTONE
    cmp     byte [r14 + NODEINFO.kind], NODE_KEYSTONE
    cmove   eax, edx
    mov     [rsp + 20], eax
    mov     edi, [rsp + 24]
    mov     esi, [rsp + 28]
    mov     edx, 24
    mov     ecx, 24
    mov     r8d, RGBA(18, 18, 24, 235)
    call    ui_rect
    cmp     ebx, [rsp]
    jne     .no_hover
    mov     edi, [rsp + 24]
    mov     esi, [rsp + 28]
    mov     edx, 24
    mov     ecx, 24
    mov     r8d, RGBA(255, 255, 255, 50)
    call    ui_rect
.no_hover:
    mov     edi, [rsp + 24]
    mov     esi, [rsp + 28]
    mov     edx, 24
    mov     ecx, 24
    mov     r8d, [rsp + 20]
    call    ui_frame
    cmp     byte [r14 + NODEINFO.kind], NODE_KEYSTONE
    jne     .icon_sel
    mov     edi, [rsp + 24]             ; a keystone's frame is two units thick
    inc     edi
    mov     esi, [rsp + 28]
    inc     esi
    mov     edx, 22
    mov     ecx, 22
    mov     r8d, [rsp + 20]
    call    ui_frame
    ; icon: a stat node shows its stat's glyph, an ability node its class's ability icon (slots
    ; 1 and 2 follow the 0.7 ability tiles, slot 3 has its own row), a keystone its star
.icon_sel:
    movzx   eax, byte [r14 + NODEINFO.kind]
    cmp     eax, NODE_ABILITY
    je      .ability_icon
    cmp     eax, NODE_KEYSTONE
    je      .keystone_icon
    movzx   edi, byte [r14 + NODEINFO.stat]
    call    rpg_stat_info
    movzx   eax, byte [rax + STATINFO.icon]
    jmp     .icon
.keystone_icon:
    mov     eax, TILE_KEYSTONE
    jmp     .icon
.ability_icon:
    movzx   edi, byte [r14 + NODEINFO.stat]     ; the ability slot
    call    rpg_ability_tile
.icon:
    mov     edi, eax
    mov     esi, [rsp + 24]
    add     esi, 4
    mov     edx, [rsp + 28]
    add     edx, 2                      ; high in the node: the rank text sits below it
    mov     ecx, 16
    mov     r8d, WHITE
    mov     eax, RGBA(255, 255, 255, 90)
    cmp     dword [rsp + 32], 0
    jne     .tint_ok
    cmp     dword [rsp + 16], 0
    cmovne  r8d, eax                    ; unranked and not spendable: dimmed
.tint_ok:
    call    ui_tile_icon
    ; rank text "r/m", bottom right
    mov     edi, [rsp + 32]
    movzx   esi, byte [r14 + NODEINFO.max]
    lea     rdx, [rank_buf]
    call    rank_text
    lea     rdi, [rank_buf]
    mov     esi, 1
    call    ui_text_width
    mov     esi, [rsp + 24]
    add     esi, 23                     ; ink ends 2 units inside the frame (the shadow adds 1)
    sub     esi, eax
    mov     ecx, RGBA(200, 200, 200, 255)
    mov     eax, [rsp + 20]
    cmp     dword [rsp + 32], 0
    cmovne  ecx, eax
    lea     rdi, [rank_buf]
    mov     edx, [rsp + 28]
    add     edx, 14
    mov     r8d, 1
    call    ui_text
    inc     ebx
    cmp     ebx, NUM_NODES
    jb      .node
    TXTC    s_tab_char, r12, SK_W / 2, r13, 214, GREY
    ; ---- tooltip: "<name>[ (Keystone)] r/m: <text>", the text being the stat's value per rank,
    ; the ability's description and its key, or the keystone's description; then
    ; "- needs level N" or "- needs previous skill" when the node is still out of reach
    mov     eax, [rsp]
    test    eax, eax
    js      .ret
    mov     edi, [rsp + 4]
    mov     esi, eax
    call    rpg_node_info
    mov     r14, rax
    lea     r15, [tip_buf]
    APPP    [r14 + NODEINFO.name]
    cmp     byte [r14 + NODEINFO.kind], NODE_KEYSTONE
    jne     .tip_rank
    APPZ    s_keystone
.tip_rank:
    APPZ    s_space
    mov     edi, [rsp]
    call    rpg_rank
    APPN    eax
    APPZ    s_slash
    movzx   eax, byte [r14 + NODEINFO.max]
    APPN    eax
    APPZ    s_colon_sp
    cmp     byte [r14 + NODEINFO.kind], NODE_STAT
    jne     .tip_desc
    movzx   edi, byte [r14 + NODEINFO.stat]     ; a stat node has no text of its own
    mov     esi, [r14 + NODEINFO.value]
    lea     rdx, [fmt_buf]
    call    rpg_format_stat
    APPP    rax
    APPZ    s_per_rank
    jmp     .tip_done
.tip_desc:
    APPP    [r14 + NODEINFO.desc]
    cmp     byte [r14 + NODEINFO.kind], NODE_ABILITY
    jne     .tip_done
    APPZ    s_key
    movzx   eax, byte [r14 + NODEINFO.stat]     ; slots 1 and 2 follow ability key 1, slot 3 has its own
    lea     edx, [rax + BIND_ABILITY1]
    mov     ecx, BIND_ABILITY4
    cmp     eax, 3
    cmove   edx, ecx
    lea     rcx, [settings + SETTINGS.keys]
    mov     edi, [rcx + rdx*4]
    mov     rsi, r15
    call    key_name
    mov     r15, rax
.tip_done:
    mov     byte [r15], 0
    lea     r15, [tip_hint]
    mov     byte [r15], 0               ; empty unless a requirement is missing
    mov     eax, [rsp]
    xor     edx, edx
    mov     ecx, NODES_PER_BRANCH
    div     ecx
    mov     [rsp + 36], edx             ; tier
    lea     rcx, [tier_req]
    mov     eax, [rcx + rdx*4]
    mov     [rsp + 40], eax             ; level the tier asks for
    call    rpg_level
    cmp     eax, [rsp + 40]
    jae     .level_ok
    APPZ    s_needs_level
    APPN    dword [rsp + 40]
    jmp     .hint_done
.level_ok:
    cmp     dword [rsp + 36], 0
    je      .hint_done
    mov     edi, [rsp]
    dec     edi                         ; the previous node of the same branch
    call    rpg_rank
    test    eax, eax
    jnz     .hint_done
    APPZ    s_needs_prev
.hint_done:
    mov     byte [r15], 0
    lea     rdi, [tip_buf]
    lea     rsi, [tip_hint]
    call    tooltip_wrapped
.ret:
    LEAVE_FRAME 56

; ---- character sheet --------------------------------------------------------------------------------

; sheet_build() -> eax rows: the visible rows of the stat list in display order, in sheet_rows: a
; group header marker (SH_OFFENSE..SH_UTILITY) or a stat id. A stat is listed when its value is
; not 0, or it is max health, crit chance or max stamina (leaf)
sheet_build:
    lea     r8, [rpg_stats]
    lea     rsi, [sheet_order]
    lea     rdi, [sheet_rows]
    xor     ecx, ecx
.next:
    movzx   eax, byte [rsi]
    inc     rsi
    cmp     eax, SH_END
    je      .done
    cmp     eax, SH_OFFENSE
    jae     .keep
    cmp     dword [r8 + rax*4], 0
    jne     .keep
    cmp     eax, STAT_MAX_HEALTH
    je      .keep
    cmp     eax, STAT_CRIT_CHANCE
    je      .keep
    cmp     eax, STAT_MAX_STAMINA
    jne     .next
.keep:
    mov     [rdi + rcx], al
    inc     ecx
    jmp     .next
.done:
    mov     eax, ecx
    ret

; stat_compact(edi stat, rsi formatted, rdx out) -> rax out: "<label>: <number>[%]" for a stat whose
; rpg_format_stat text (sign, number, then a suffix that starts with '%' or a space) does not fit a
; column. The number is copied up to the first space, so a '%' stays with it.
stat_compact:
    ENTER_FRAME 8
    mov     r12, rdx
    mov     r13, rsi
    call    rpg_stat_info
    mov     r15, r12
    APPP    [rax + STATINFO.label]
    APPZ    s_colon_sp
.copy:
    mov     al, [r13]
    test    al, al
    jz      .done
    cmp     al, ' '
    je      .done
    mov     [r15], al
    inc     r15
    inc     r13
    jmp     .copy
.done:
    mov     byte [r15], 0
    mov     rax, r12
    LEAVE_FRAME 8

; plus_box(edi x, esi y, edx enabled) -> eax 1 when clicked: a 9 x 9 "+" button (the click sound is
; played by whatever the click does)
plus_box:
    ENTER_FRAME 24
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edx
    xor     ebx, ebx                    ; hovered (a disabled button never is)
    test    r14d, r14d
    jz      .draw
    mov     edx, 9
    mov     ecx, 9
    call    hit
    mov     ebx, eax
.draw:
    mov     r8d, RGBA(255, 255, 255, 16)
    mov     eax, RGBA(255, 255, 255, 38)
    mov     ecx, RGBA(255, 255, 255, 77)
    test    r14d, r14d
    cmovnz  r8d, eax
    test    ebx, ebx
    cmovnz  r8d, ecx
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, 9
    mov     ecx, 9
    call    ui_rect
    test    ebx, ebx
    jz      .plus
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, 9
    mov     ecx, 9
    mov     r8d, RGBA(255, 255, 255, 128)
    call    ui_frame
.plus:
    lea     rdi, [s_plus]
    lea     esi, [r12 + 4]
    lea     edx, [r13 + 1]
    mov     ecx, WHITE
    mov     eax, GREY
    test    r14d, r14d
    cmovz   ecx, eax
    mov     r8d, 1
    call    ui_text_centered
    xor     eax, eax
    test    ebx, ebx
    jz      .ret
    cmp     dword [ui_input + UIINPUT.lmb_pressed], 0
    setne   al
.ret:
    LEAVE_FRAME 24

; screen_character(): attribute rows (a "+" box spends an attribute point, Shift up to five), a
; summary of health, armor and the held weapon, and every stat in two columns that the wheel
; scrolls; Tab opens the skill tree. The stats are recomputed first: gear changes them.
; Locals: [rsp] hovered attribute or -1, [rsp+4] class, [rsp+8] attribute points, [rsp+12]
; combat_weapon_preview {hit, crit hit, attacks per 10 s}, and of the stat row being drawn: [rsp+24]
; x, [rsp+28] y, [rsp+32] stat, [rsp+36] width of its text
screen_character:
    ENTER_FRAME 40
    cmp     dword [app_entered], 0
    je      .seen
    mov     dword [sheet_scroll], 0     ; a fresh visit starts at the top of the list
.seen:
    call    close_check
    test    eax, eax
    jnz     .ret
    cmp     dword [ui_input + UIINPUT.key_pressed], KEY_TAB
    jne     .no_tab
    mov     edi, ST_SKILLS
    call    app_goto
    jmp     .ret
.no_tab:
    call    rpg_class
    mov     [rsp + 4], eax
    lea     ecx, [rax - 1]
    cmp     ecx, NUM_CLASSES
    jb      .have_class
    mov     edi, ST_PLAYING             ; no class yet: nothing to show
    call    app_goto
    jmp     .ret
.have_class:
    call    rpg_recompute
    mov     edi, CH_W
    mov     esi, CH_H
    call    panel_begin
    mov     r12d, [s_px]
    mov     r13d, [s_py]
    call    rpg_attr_points
    mov     [rsp + 8], eax
    mov     edx, eax
    mov     edi, [rsp + 4]
    lea     rsi, [s_attr_points]
    mov     ecx, CH_W
    call    screen_header
    ; ---- attribute rows: icon, name, points spent, "+" box; the hovered row's effect is the tooltip
    mov     dword [rsp], -1
    xor     ebx, ebx
.attr:
    imul    r14d, ebx, 12
    lea     r14d, [r14 + r13 + 18]      ; row y
    lea     edi, [r12 + 8]
    mov     esi, r14d
    mov     edx, 117
    mov     ecx, 12
    call    hit
    test    eax, eax
    jz      .attr_draw
    mov     [rsp], ebx
.attr_draw:
    lea     rax, [attr_tiles]
    movzx   edi, byte [rax + rbx]
    lea     esi, [r12 + 8]
    lea     edx, [r14 + 1]
    mov     ecx, 10
    mov     r8d, WHITE
    call    ui_tile_icon
    mov     edi, ebx
    call    rpg_attr_info
    mov     rdi, rax
    lea     esi, [r12 + 22]
    lea     edx, [r14 + 2]
    mov     ecx, LABEL_COL
    mov     r8d, 1
    call    ui_text
    mov     edi, ebx
    call    rpg_attr
    mov     edi, eax
    lea     rsi, [coin_buf]
    call    i32_to_str
    mov     byte [rax], 0
    lea     rdi, [coin_buf]
    mov     esi, 1
    call    ui_text_width
    lea     esi, [r12 + 112 + 1]        ; right aligned at px + 112
    sub     esi, eax
    lea     rdi, [coin_buf]
    lea     edx, [r14 + 2]
    mov     ecx, WHITE
    mov     r8d, 1
    call    ui_text
    lea     edi, [r12 + 116]
    lea     esi, [r14 + 1]
    xor     edx, edx
    cmp     dword [rsp + 8], 0
    setg    dl                          ; enabled while attribute points are left
    call    plus_box
    test    eax, eax
    jz      .attr_next
    mov     edi, ebx
    call    rpg_spend_attr
    cmp     dword [ui_input + UIINPUT.shift], 0
    je      .attr_next
    mov     r15d, 4                     ; Shift: up to five points in all
.shift:
    mov     edi, ebx
    call    rpg_spend_attr
    test    eax, eax
    jz      .attr_next
    dec     r15d
    jnz     .shift
.attr_next:
    inc     ebx
    cmp     ebx, NUM_ATTRS
    jb      .attr
    ; ---- summary: health, armor (what the damage formula uses: at most 20, 4% each), the held
    ; weapon's hit, crit hit and attack rate
    lea     rdi, [rsp + 12]
    call    combat_weapon_preview
    lea     r15, [coin_buf]
    APPZ    s_health
    APPN    dword [surv + SURVIVAL.health]
    APPZ    s_slash
    APPN    dword [surv_max_health]
    mov     byte [r15], 0
    TXTL    coin_buf, r12, 140, r13, 18, LABEL_COL
    call    armor_points
    add     eax, [rpg_stats + STAT_ARMOR_BONUS * 4]
    mov     ecx, 20
    cmp     eax, ecx
    cmovg   eax, ecx
    mov     ebx, eax
    lea     r15, [coin_buf]
    APPZ    s_armor
    APPN    ebx
    APPZ    s_armor_mid
    lea     eax, [rbx*4]
    APPN    eax
    APPZ    s_armor_end
    mov     byte [r15], 0
    TXTL    coin_buf, r12, 140, r13, 27, LABEL_COL
    lea     r15, [coin_buf]
    APPZ    s_hit
    APPN    dword [rsp + 12]
    APPZ    s_crit
    APPN    dword [rsp + 16]
    mov     byte [r15], 0
    TXTL    coin_buf, r12, 140, r13, 36, LABEL_COL
    mov     eax, [rsp + 20]
    xor     edx, edx
    mov     ecx, 10
    div     ecx
    mov     r14d, eax                   ; whole attacks per second
    mov     ebx, edx                    ; and the tenth
    lea     r15, [coin_buf]
    APPZ    s_attacks
    APPN    r14d
    mov     byte [r15], '.'
    add     bl, '0'
    mov     [r15 + 1], bl
    add     r15, 2
    APPZ    s_per_s
    mov     byte [r15], 0
    TXTL    coin_buf, r12, 140, r13, 45, LABEL_COL
    ; ---- divider and the stat list
    lea     edi, [r12 + 8]
    lea     esi, [r13 + 66]
    mov     edx, CH_W - 16
    mov     ecx, 1
    mov     r8d, EDGE_COL
    call    ui_rect
    call    sheet_build
    mov     ebx, eax                    ; rows listed
    lea     edi, [r12 + CH_COL0]
    lea     esi, [r13 + CH_LIST_Y]
    mov     edx, CH_W - 16
    mov     ecx, CH_ROWS * 9 + 6
    call    hit
    mov     ecx, [sheet_scroll]
    test    eax, eax
    jz      .clamp
    sub     ecx, [ui_input + UIINPUT.scroll]    ; wheel up scrolls towards the top
.clamp:
    lea     eax, [rbx - 2 * CH_ROWS]    ; the largest first row: the window stays full
    xor     edx, edx
    test    eax, eax
    cmovs   eax, edx
    cmp     ecx, eax
    cmovg   ecx, eax
    test    ecx, ecx
    cmovs   ecx, edx
    mov     [sheet_scroll], ecx
    mov     r14d, ecx                   ; first listed row
    xor     r15d, r15d                  ; position in the window: column = r15 / CH_ROWS
.row:
    lea     eax, [r14 + r15]
    cmp     eax, ebx
    jae     .list_done
    lea     rdx, [sheet_rows]
    movzx   edi, byte [rdx + rax]
    mov     ecx, r15d
    shr     ecx, 4
    imul    ecx, ecx, CH_COL1 - CH_COL0
    lea     eax, [r12 + rcx + CH_COL0]
    mov     [rsp + 24], eax             ; x
    mov     edx, r15d
    and     edx, CH_ROWS - 1
    imul    edx, edx, 9
    lea     eax, [rdx + r13 + CH_LIST_Y]
    mov     [rsp + 28], eax             ; y
    cmp     edi, SH_OFFENSE
    jae     .head
    lea     rax, [rpg_stats]
    mov     esi, [rax + rdi*4]
    mov     [rsp + 32], edi
    lea     rdx, [fmt_buf]
    call    rpg_format_stat
    lea     rdi, [fmt_buf]
    mov     esi, 1
    call    ui_text_width
    mov     [rsp + 36], eax             ; the sentence's width
    lea     rdi, [fmt_buf]
    cmp     eax, CH_COLW
    jbe     .fits
    mov     edi, [rsp + 32]             ; too wide for its column: "<label>: <number>" if that is shorter
    lea     rsi, [fmt_buf]
    lea     rdx, [coin_buf]
    call    stat_compact
    lea     rdi, [coin_buf]
    mov     esi, 1
    call    ui_text_width
    lea     rdi, [fmt_buf]
    cmp     eax, [rsp + 36]
    jae     .fits
    lea     rdi, [coin_buf]
.fits:
    mov     ecx, LABEL_COL
    jmp     .text
.head:
    sub     edi, SH_OFFENSE
    lea     rax, [sheet_head]
    mov     rdi, [rax + rdi*8]
    mov     ecx, GOLD
.text:
    mov     esi, [rsp + 24]
    mov     edx, [rsp + 28]
    mov     r8d, 1
    call    ui_text
    inc     r15d
    cmp     r15d, 2 * CH_ROWS
    jb      .row
.list_done:
    TXTC    s_tab_skills, r12, CH_W / 2, r13, 221, GREY
    mov     eax, [rsp]
    test    eax, eax
    js      .ret
    mov     edi, eax
    call    rpg_attr_desc
    mov     rdi, rax
    lea     rsi, [s_empty]
    call    tooltip_wrapped
.ret:
    LEAVE_FRAME 40

; ---- merchant ------------------------------------------------------------------------------------

; screen_trade(): the 10 trade offers as "give -> get" rows with a Trade button each (enabled
; while trade_can); hovering an icon names the item, or for a gear offer says what it rolls.
; Locals: [rsp] item id under the mouse (0 = none), [rsp+4] trade_can of the row, [rsp+8] 1 when
; that icon is the "get" side
screen_trade:
    ENTER_FRAME 24
    call    close_check
    test    eax, eax
    jnz     .ret
    mov     edi, TR_W
    mov     esi, TR_H
    call    panel_begin
    mov     r12d, [s_px]
    mov     r13d, [s_py]
    mov     dword [rsp], 0
    TXTL    s_merchant, r12, 8, r13, 6, GOLD
    lea     r15, [coin_buf]
    APPZ    s_coins
    mov     edi, GOLD_COIN
    call    inv_count
    APPN    eax
    mov     byte [r15], 0
    lea     rdi, [coin_buf]
    mov     esi, 1
    call    ui_text_width
    lea     esi, [r12 + TR_W - 8 + 1]   ; right aligned at px + 212
    sub     esi, eax
    lea     rdi, [coin_buf]
    lea     edx, [r13 + 6]
    mov     ecx, GOLD
    mov     r8d, 1
    call    ui_text
    xor     ebx, ebx
.row:
    imul    eax, ebx, 21
    lea     r14d, [rax + r13 + 22]      ; row y
    mov     edi, ebx
    call    trade_offer
    mov     r15, rax
    mov     edi, ebx
    call    trade_can
    mov     [rsp + 4], eax
    lea     edi, [r12 + 4]              ; row backing
    mov     esi, r14d
    mov     edx, TR_W - 8
    mov     ecx, 20
    mov     r8d, RGBA(0, 0, 0, 55)
    call    ui_rect
    mov     edi, [r15 + TRADEOFFER.give]        ; give: icon, then the count (red when it cannot be paid)
    lea     esi, [r12 + 10]
    lea     edx, [r14 + 2]
    mov     ecx, 16
    call    ui_item_icon
    lea     edi, [r12 + 10]
    lea     esi, [r14 + 2]
    mov     edx, 16
    mov     ecx, 16
    call    hit
    test    eax, eax
    jz      .no_give_tip
    mov     eax, [r15 + TRADEOFFER.give]
    mov     [rsp], eax
    mov     dword [rsp + 8], 0
.no_give_tip:
    mov     edi, [r15 + TRADEOFFER.give_n]
    lea     rsi, [coin_buf]
    call    i32_to_str
    mov     byte [rax], 0
    lea     rdi, [coin_buf]
    lea     esi, [r12 + 29]
    lea     edx, [r14 + 6]
    mov     ecx, WHITE
    mov     eax, RED
    cmp     dword [rsp + 4], 0
    cmove   ecx, eax
    mov     r8d, 1
    call    ui_text
    TXTL    s_arrow, r12, 66, r14, 6, GREY
    mov     edi, [r15 + TRADEOFFER.get]         ; get: icon and count
    lea     esi, [r12 + 90]
    lea     edx, [r14 + 2]
    mov     ecx, 16
    call    ui_item_icon
    lea     edi, [r12 + 90]
    lea     esi, [r14 + 2]
    mov     edx, 16
    mov     ecx, 16
    call    hit
    test    eax, eax
    jz      .no_get_tip
    mov     eax, [r15 + TRADEOFFER.get]
    mov     [rsp], eax
    mov     dword [rsp + 8], 1
.no_get_tip:
    mov     edi, [r15 + TRADEOFFER.get_n]
    lea     rsi, [coin_buf]
    call    i32_to_str
    mov     byte [rax], 0
    lea     rdi, [coin_buf]
    lea     esi, [r12 + 109]
    lea     edx, [r14 + 6]
    mov     ecx, WHITE
    mov     r8d, 1
    call    ui_text
    lea     rdi, [s_trade]
    lea     esi, [r12 + 162]
    mov     edx, r14d
    mov     ecx, 50
    mov     r8d, [rsp + 4]
    call    ui_button
    test    eax, eax
    jz      .next
    mov     edi, ebx
    call    trade_execute
.next:
    inc     ebx
    cmp     ebx, NUM_TRADES
    jb      .row
    mov     eax, [rsp]                  ; item tooltip, like the inventory screens
    test    eax, eax
    jz      .ret
    cmp     eax, NUM_ITEMS
    jae     .ret
    cmp     dword [rsp + 8], 0
    je      .plain
    lea     rcx, [item_gear]
    cmp     byte [rcx + rax], 0
    je      .plain
    mov     ebx, eax                    ; gear is rolled on purchase: "Random magic+ <item>, tier T"
    lea     r15, [tip_buf]
    APPZ    s_random
    lea     rcx, [item_names]
    APPP    [rcx + rbx*8]
    APPZ    s_tier_sep
    call    rpg_level
    mov     edi, eax
    call    gear_tier_for_level
    APPN    eax
    mov     byte [r15], 0
    lea     rdi, [tip_buf]
    call    ui_tooltip
    jmp     .ret
.plain:
    lea     rcx, [item_names]
    mov     rdi, [rcx + rax*8]
    test    rdi, rdi
    jz      .ret
    call    ui_tooltip
.ret:
    LEAVE_FRAME 24

; ---- elder -----------------------------------------------------------------------------------------

; screen_dialog(): the current quest of the chain (rpg_state.quest) with Accept / Complete /
; Leave; when the chain is finished a farewell. Below it always "Reset skills: N coins"
; (rpg_respec). Locals: [rsp] quest accepted, [rsp+4] progress
screen_dialog:
    ENTER_FRAME 24
    call    close_check
    test    eax, eax
    jnz     .ret
    mov     edi, DL_W
    mov     esi, DL_H
    call    panel_begin
    mov     r12d, [s_px]
    mov     r13d, [s_py]
    TXTL    s_elder, r12, 8, r13, 6, WHITE
    call    quests_current
    test    rax, rax
    jnz     .quest
    TXTC    s_saved, r12, DL_W / 2, r13, 40, LABEL_COL
    BTN     s_farewell, r12, (DL_W - 118) / 2, r13, 92, 118
    test    eax, eax
    jnz     .close
    jmp     .respec
.quest:
    mov     r14, rax
    movzx   eax, byte [rpg_state + RPGSAVE.quest_state]
    mov     [rsp], eax
    mov     rdi, [r14 + QUESTINFO.title]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 24]
    mov     ecx, GOLD
    mov     r8d, 1
    call    ui_text
    mov     rdi, [r14 + QUESTINFO.line1]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 40]
    mov     ecx, LABEL_COL
    mov     r8d, 1
    call    ui_text
    mov     rdi, [r14 + QUESTINFO.line2]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 52]
    mov     ecx, LABEL_COL
    mov     r8d, 1
    call    ui_text
    cmp     dword [rsp], 0
    je      .buttons
    lea     r15, [coin_buf]             ; "Progress: p/c", green once it is done
    APPZ    s_progress
    call    quests_progress
    mov     ecx, [r14 + QUESTINFO.count]
    cmp     eax, ecx
    cmova   eax, ecx                    ; never "7/6"
    mov     [rsp + 4], eax
    APPN    eax
    APPZ    s_slash
    APPN    dword [r14 + QUESTINFO.count]
    mov     byte [r15], 0
    mov     ecx, WHITE
    mov     eax, GREEN
    mov     edx, [rsp + 4]
    cmp     edx, [r14 + QUESTINFO.count]
    cmovae  ecx, eax
    lea     rdi, [coin_buf]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 68]
    mov     r8d, 1
    call    ui_text
.buttons:
    cmp     dword [rsp], 0
    je      .offer
    call    quests_can_complete
    test    eax, eax
    jz      .leave_only
    BTN     s_complete, r12, 8, r13, 92, 118
    test    eax, eax
    jz      .leave_right
    call    quests_complete
    jmp     .ret
.offer:
    BTN     s_accept, r12, 8, r13, 92, 118
    test    eax, eax
    jz      .leave_right
    call    quests_accept
    jmp     .ret
.leave_right:
    BTN     s_leave, r12, 134, r13, 92, 118
    jmp     .leave_done
.leave_only:
    BTN     s_leave, r12, (DL_W - 118) / 2, r13, 92, 118
.leave_done:
    test    eax, eax
    jz      .respec
.close:
    mov     edi, ST_PLAYING
    call    app_goto
    jmp     .ret
.respec:                                ; enabled with a class and the coins in the pack
    call    rpg_respec_cost
    mov     ebx, eax
    lea     r15, [coin_buf]
    APPZ    s_reset
    APPN    ebx
    APPZ    s_coins_sfx
    mov     byte [r15], 0
    xor     r14d, r14d
    call    rpg_class
    test    eax, eax
    jz      .reset_btn
    mov     edi, GOLD_COIN
    call    inv_count
    cmp     eax, ebx
    setae   r14b
.reset_btn:
    lea     rdi, [coin_buf]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 118]
    mov     ecx, DL_W - 16
    mov     r8d, r14d
    call    ui_button
    test    eax, eax
    jz      .ret
    call    rpg_respec
.ret:
    LEAVE_FRAME 24
