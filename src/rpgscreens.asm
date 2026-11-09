; rpgscreens.asm - the RPG screens: the grimoire (skill web), character sheet, a trader's offers,
; the elder's quest dialog, a faction leader's word and a shrine's tribute. Immediate mode
; like invscreen.asm / menus.asm: every screen_*() runs once per frame after ui_begin (app.asm
; draw_frame), reads ui_input / frame_input and changes state with app_goto. A screen that acts
; returns at once, so one click never reaches two widgets.
;  - ST_SKILLS (the grimoire), ST_CHARACTER, ST_TRADE, ST_DIALOG, ST_SHRINE and ST_LEADER close
;    (back to ST_PLAYING) on Escape, the inventory key or the skills key. The first frame after a
;    state change only clears app_entered: the key edge that opened the screen is still set in that
;    frame and must not close it. Tab switches between the grimoire and the character sheet.
;    Everyone may open both: there are no classes, the grimoire's one web holds every skill.
; All progression data (node texts, stats, attributes, quests, trades) comes from rpg.asm /
; quests.asm and all faction data (names, standings, rivals, champions, tribute) from factions.asm
; (Module API); the only text owned here is the UI wording.
%include "common.inc"
%include "gl.inc"
default rel

global screen_skills, screen_character, screen_trade, screen_dialog
global screen_shrine, screen_leader, web_node_xy, web_pick

extern ui_w, ui_h, ui_mx, ui_my, ui_input, frame_input, settings, app_entered
extern ui_rect, ui_frame, ui_panel, ui_text, ui_text_width, ui_text_centered
extern ui_button, ui_item_icon, ui_tile_icon, ui_tooltip
extern app_goto, key_name, hud_banner_paint
extern item_names, item_gear, inv_count, i32_to_str, str_append, armor_points
extern surv, surv_max_health, combat_weapon_preview, gear_tier_for_level
extern rpg_state, rpg_stats, rpg_level, rpg_points, rpg_rank
extern rpg_can_spend, rpg_spend, rpg_stat_info, rpg_format_stat, rpg_recompute
extern rpg_attr, rpg_attr_points, rpg_spend_attr, rpg_attr_info, rpg_attr_desc
extern rpg_respec_cost, rpg_respec, rpg_ability_tile
extern rpg_web_node, rpg_reachable, web_edges, web_edge_count, rpg_title, rpg_archetype_name
extern rpg_ability_learned, rpg_bar_ability, rpg_bar_set
extern quests_current, quests_progress, quests_accept, quests_can_complete, quests_complete
extern trade_offer, trade_can, trade_execute, trade_count, trade_title
extern screen_faction, faction_names, faction_standing, faction_tier, faction_tier_color
extern faction_rivals, faction_champion_defeated, faction_tribute, faction_wanted
extern tier_names, champion_names

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
%define COL_KEYSTONE RGBA(255, 200, 60, 255)
%define COL_COVER   RGBA(44, 30, 20, 245)       ; the grimoire: cover, spine, the web's backing ...
%define COL_SPINE   RGBA(24, 16, 12, 255)
%define COL_VIEW    RGBA(0, 0, 0, 70)
%define COL_ARCH    RGBA(235, 195, 100, 255)    ; ... archetype names, node grounds, rings, washes
%define COL_NODE_BG RGBA(18, 18, 24, 235)
%define COL_PATH_BG RGBA(48, 38, 22, 240)
%define COL_RING    GOLD
%define COL_WASH    RGBA(255, 255, 255, 50)
%define COL_DIMICON RGBA(255, 255, 255, 90)
%define COL_EDGE_OFF  RGBA(100, 100, 112, 255)  ; edges: no end ranked, one end, both ends
%define COL_EDGE_HALF RGBA(190, 190, 205, 230)
%define COL_EDGE_LIT  GOLD

; ---- geometry (GUI units) -----------------------------------------------------------------
%define WEB_VX      20                  ; the grimoire's web viewport: x, y, and the margins that
%define WEB_VY      34                  ; leave it ui_w - 40 wide and ui_h - 76 high
%define WEB_VR      20                  ; right edge = ui_w - WEB_VR
%define WEB_VB      42                  ; bottom edge = ui_h - WEB_VB
%define WEB_CELL1   28                  ; units per web cell at zoom 1 ...
%define WEB_CELL0   13                  ; ... and at zoom 0
%define WEB_DRAG    3                   ; units of travel that turn a press on a node into a drag
%define DRAG_NONE   0                   ; web_drag: nothing pressed, panning, a press waiting on a node,
%define DRAG_PAN    1                   ; a press on a node that moved too far to be a click
%define DRAG_NODE   2
%define DRAG_CANCEL 3

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

%define TR_W        220                 ; trade panel: TR_BASE + TR_ROW per offer high (236 for 10)
%define TR_BASE     26
%define TR_ROW      21
%define DL_W        260                 ; elder and faction leader panel
%define DL_H        144
%define TB_W        260                 ; shrine panel
%define TB_H        150
%define TB_BTN_W    116                 ; its tribute buttons, in two columns
%define TB_ROW_SIZE 24                  ; one tribute_rows entry

%define TIP_MAXW    320                 ; skill tooltip wraps here
%define HINT_COL    RGBA(255, 150, 110, 255)

section .rodata
align 4
attr_tiles:     db TILE_ATTR_STR, TILE_ATTR_DEX, TILE_ATTR_INT, TILE_ATTR_VIT
web_dims_tab:   db 5, 9, 6, 12, 11, 22, 14, 28  ; web_dims: pick half, frame size by zoom * 2 + path
ability_binds:  db BIND_ABILITY1, BIND_ABILITY2, BIND_ABILITY3, BIND_ABILITY4   ; bind of bar slot 0..3
align 4
web_edge_cols:  dd COL_EDGE_OFF, COL_EDGE_HALF, COL_EDGE_LIT

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

s_level_sep:    db " - Level ", 0
s_points:       db "Points: ", 0
s_attr_points:  db "Attribute points: ", 0
s_slash:        db "/", 0
s_space:        db " ", 0
s_colon_sp:     db ": ", 0
s_per_rank:     db " per rank", 0
s_keystone:     db " (Keystone)", 0
s_needs_level:  db "- needs level ", 0
s_not_linked:   db "- not linked to a skill you have", 0
s_press:        db "Press ", 0
s_place:        db " to place it on your bar", 0
s_grimoire:     db "Grimoire", 0
s_wheel_hint:   db "Wheel: zoom  Drag: move", 0
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
s_unlearn:      db "Unlearn all: ", 0
s_coins_sfx:    db " coins", 0
s_leader_sfx:   db " Leader", 0
s_shrine_sfx:   db " Shrine", 0
s_standing:     db "Standing: ", 0
s_open_paren:   db " (", 0
s_close_paren:  db ")", 0
s_greet_neutral: db "Prove yourself to us.", 0
s_greet_friendly: db "You are welcome at our fires.", 0
s_greet_allied: db "You are one of us now.", 0
s_rivals:       db "Rivals: ", 0
s_comma_sp:     db ", ", 0
s_champion:     db "Champion: ", 0
s_fallen:       db " (fallen)", 0
s_wanted:       db "Wanted: ", 0
s_tr_c5:        db "5 coins: +1", 0
s_tr_c50:       db "50 coins: +10", 0
s_tr_i1:        db "1 item: +1", 0
s_tr_i10:       db "10 items: +10", 0
s_pack_coins:   db "Coins ", 0
s_pack_items:   db ", items ", 0

align 8
leader_greetings: dq s_greet_neutral, s_greet_friendly, s_greet_allied    ; by tier from Neutral up
; the shrine's four tribute buttons: label, x, y (panel relative), kind (0 coins, 1 the wanted
; item) and the units paid (faction_tribute's kind and units)
tribute_rows:
    dq s_tr_c5
    dd 10, 60, 0, 5
    dq s_tr_c50
    dd 134, 60, 0, 50
    dq s_tr_i1
    dd 10, 84, 1, 1
    dq s_tr_i10
    dd 134, 84, 1, 10

section .bss
alignb 8
s_px:           resd 1                  ; panel origin of the screen being drawn
s_py:           resd 1
sheet_scroll:   resd 1                  ; first listed row of the character sheet's stat list
hdr_buf:        resb 64                 ; "<title> - Level N" / "<Faction> Leader" / "Wanted: <item>"
pts_buf:        resb 32                 ; "Points: N" / "Attribute points: N"
coin_buf:       resb 32                 ; "Coins: N" / "Progress: p/c" / "Standing: N (Tier)" / counts / summary lines
rank_buf:       resb 16                 ; "r/m" on a skill node
fmt_buf:        resb 48                 ; one formatted stat
sheet_rows:     resb 64                 ; the stat list's visible rows (sheet_build)
tip_buf:        resb 256                ; skill tooltip text
tip_hint:       resb 128                ; ... and its hint (what is missing, or the keys to bind it)
tip_row:        resb 128                ; one wrapped tooltip row
row_buf:        resb 128                ; one wrapped row of "Rivals: ..." / "Champion: ..."
web_ox:         resd 1                  ; screen position of web cell (0, 0)
web_oy:         resd 1
web_zoom:       resd 1                  ; 1 = cells of 28 units, 0 = cells of 13
web_init:       resd 1                  ; the origin was set (first open of the session)
web_hover:      resd 1                  ; the node under the mouse that is drawn, or -1
web_drag:       resd 1                  ; DRAG_*
web_px:         resd 1                  ; where the button went down
web_py:         resd 1
web_lx:         resd 1                  ; the mouse of the last panning frame
web_ly:         resd 1
web_pressnode:  resd 1                  ; the node the press landed on

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

; ---- the grimoire: header and shared helpers ---------------------------------------------------

; screen_header(rsi points label, edx points, ecx panel width): "<rpg_title> - Level N" at the top
; left of the panel being drawn (s_px / s_py), "<label><points>" right aligned at its top right
; (green while there are points). Locals: [rsp] points, [rsp+4] panel width
screen_header:
    ENTER_FRAME 24
    mov     [rsp], edx
    mov     [rsp + 4], ecx
    mov     r14, rsi
    lea     r15, [hdr_buf]
    call    rpg_title
    APPP    rax
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

; ---- the grimoire: the skill web ---------------------------------------------------------------
; One web of 88 nodes (rpg.asm) on a 17 x 17 cell grid around the compass. web_ox / web_oy is the
; screen position of cell (0, 0), a cell is 28 GUI units wide at zoom 1 and 13 at zoom 0. Nothing is
; clipped: a node, an edge or a label is drawn only when it lies whole inside the viewport
; (web_cull, the one place to swap for a clip rectangle) and input ignores what is not drawn.

; web_node_xy(edi node, esi zoom) -> eax dx, edx dy: the node's cell (the signed bytes of its WEBNODE)
; times the cell size, 28 at zoom 1 and 13 at zoom 0 = the node centre minus the web origin; 0, 0 for
; a node that does not exist
web_node_xy:
    sub     rsp, 8
    mov     [rsp], esi
    call    rpg_web_node
    mov     esi, [rsp]
    add     rsp, 8
    xor     ecx, ecx
    xor     edx, edx
    test    rax, rax
    jz      .none
    movsx   ecx, byte [rax + WEBNODE.x]
    movsx   edx, byte [rax + WEBNODE.y]
    mov     r8d, WEB_CELL0
    mov     r9d, WEB_CELL1
    test    esi, esi
    cmovnz  r8d, r9d
    imul    ecx, r8d
    imul    edx, r8d
.none:
    mov     eax, ecx
    ret

; web_dims(edi node, esi zoom) -> eax half (the pick half-size), edx frame size: 11 / 22 for an
; ordinary node and 14 / 28 for a path node at zoom 1, 5 / 9 and 6 / 12 at zoom 0 (leaf but for
; rpg_web_node)
web_dims:
    sub     rsp, 8
    mov     [rsp], esi
    call    rpg_web_node
    mov     esi, [rsp]
    add     rsp, 8
    xor     ecx, ecx
    test    rax, rax
    jz      .kind
    cmp     byte [rax + WEBNODE.kind], NODE_PATH
    sete    cl
.kind:
    xor     edx, edx
    test    esi, esi
    setnz   dl
    lea     ecx, [rcx + rdx*2]          ; zoom * 2 + path
    lea     rdx, [web_dims_tab]
    movzx   eax, byte [rdx + rcx*2]
    movzx   edx, byte [rdx + rcx*2 + 1]
    ret

; web_pick(edi mx, esi my, edx ox, ecx oy, r8d zoom) -> eax the node under (mx, my) when the web
; origin is at (ox, oy), or -1. A node is hit when |mx - (ox + dx)| <= half and |my - (oy + dy)| <= half
; (web_node_xy, web_dims); nodes are tested in id order and the first hit wins. The compass centre,
; which has no node, gives -1. Pure: it reads no screen state.
; r12d = mx, r13d = my, r14d = ox, r15d = oy, ebx = node, [rsp] zoom, [rsp+8] node centre x, [rsp+12] y
web_pick:
    ENTER_FRAME 24
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edx
    mov     r15d, ecx
    mov     [rsp], r8d
    xor     ebx, ebx
.node:
    cmp     ebx, NUM_WEB_NODES
    jae     .none
    mov     edi, ebx
    mov     esi, [rsp]
    call    web_node_xy
    add     eax, r14d
    add     edx, r15d
    mov     [rsp + 8], eax
    mov     [rsp + 12], edx
    mov     edi, ebx
    mov     esi, [rsp]
    call    web_dims                    ; eax = half
    mov     ecx, r12d
    sub     ecx, [rsp + 8]
    mov     edx, ecx
    sar     edx, 31
    xor     ecx, edx
    sub     ecx, edx                    ; |mx - cx|
    cmp     ecx, eax
    jg      .next
    mov     ecx, r13d
    sub     ecx, [rsp + 12]
    mov     edx, ecx
    sar     edx, 31
    xor     ecx, edx
    sub     ecx, edx                    ; |my - cy|
    cmp     ecx, eax
    jg      .next
    mov     eax, ebx
    jmp     .ret
.next:
    inc     ebx
    jmp     .node
.none:
    mov     eax, -1
.ret:
    LEAVE_FRAME 24

; web_cull(edi cx, esi cy, edx half) -> eax 1 when the square cx +- half, cy +- half lies whole inside
; the web viewport (leaf)
web_cull:
    xor     eax, eax
    lea     ecx, [rdi + rdx]
    mov     r8d, [ui_w]
    sub     r8d, WEB_VR
    cmp     ecx, r8d
    jg      .ret
    mov     ecx, edi
    sub     ecx, edx
    cmp     ecx, WEB_VX
    jl      .ret
    lea     ecx, [rsi + rdx]
    mov     r8d, [ui_h]
    sub     r8d, WEB_VB
    cmp     ecx, r8d
    jg      .ret
    mov     ecx, esi
    sub     ecx, edx
    cmp     ecx, WEB_VY
    jl      .ret
    mov     eax, 1
.ret:
    ret

; web_centre(edi node) -> eax x, edx y: where the node's centre is on the screen now
web_centre:
    sub     rsp, 8
    mov     esi, [web_zoom]
    call    web_node_xy
    add     eax, [web_ox]
    add     edx, [web_oy]
    add     rsp, 8
    ret

; web_vis(edi node) -> eax 1 when the node is drawn (and can be hovered or clicked): its frame, the
; 1-unit ring around it and, at zoom 1, the rank tag hanging 6 units below it all lie in the viewport
web_vis:
    push    rbx
    push    r12
    sub     rsp, 8
    mov     ebx, edi
    call    web_centre
    mov     r12d, eax
    mov     [rsp], edx
    mov     edi, ebx
    mov     esi, [web_zoom]
    call    web_dims
    mov     edx, 1                      ; margin: the ring ...
    mov     ecx, 6                      ; ... or the rank tag
    cmp     dword [web_zoom], 0
    cmovne  edx, ecx
    add     edx, eax
    mov     edi, r12d
    mov     esi, [rsp]
    call    web_cull
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; web_node_ability(edi node) -> eax the ability the node teaches: an ability node's id, a path node's
; slot-0 ability (archetype - 1) * 4; -1 for any other node
web_node_ability:
    sub     rsp, 8
    call    rpg_web_node
    add     rsp, 8
    mov     edx, -1
    test    rax, rax
    jz      .ret
    movzx   ecx, byte [rax + WEBNODE.stat]
    cmp     byte [rax + WEBNODE.kind], NODE_ABILITY
    jne     .path
    mov     edx, ecx
    jmp     .ret
.path:
    cmp     byte [rax + WEBNODE.kind], NODE_PATH
    jne     .ret
    lea     edx, [rcx - 1]
    shl     edx, 2
.ret:
    mov     eax, edx
    ret

; web_clamp(): keep the origin where at least one cell of the 17 x 17 web (cells -8..8) is inside the
; viewport: ox in [VX - 7 cells, right edge + 7 cells], oy likewise (leaf)
web_clamp:
    mov     ecx, WEB_CELL0
    mov     eax, WEB_CELL1
    cmp     dword [web_zoom], 0
    cmovne  ecx, eax
    imul    ecx, ecx, 7
    mov     eax, [web_ox]
    mov     edx, WEB_VX
    sub     edx, ecx
    cmp     eax, edx
    cmovl   eax, edx
    mov     edx, [ui_w]
    sub     edx, WEB_VR
    add     edx, ecx
    cmp     eax, edx
    cmovg   eax, edx
    mov     [web_ox], eax
    mov     eax, [web_oy]
    mov     edx, WEB_VY
    sub     edx, ecx
    cmp     eax, edx
    cmovl   eax, edx
    mov     edx, [ui_h]
    sub     edx, WEB_VB
    add     edx, ecx
    cmp     eax, edx
    cmovg   eax, edx
    mov     [web_oy], eax
    ret

; web_open(): the first open of the session puts the origin at the viewport centre at zoom 1 (leaf)
web_open:
    cmp     dword [web_init], 0
    jne     .ret
    mov     dword [web_init], 1
    mov     dword [web_zoom], 1
    mov     eax, [ui_w]
    sub     eax, WEB_VX + WEB_VR
    shr     eax, 1
    add     eax, WEB_VX
    mov     [web_ox], eax
    mov     eax, [ui_h]
    sub     eax, WEB_VY + WEB_VB
    shr     eax, 1
    add     eax, WEB_VY
    mov     [web_oy], eax
.ret:
    ret

; web_zoom_input(): the wheel zooms - up to zoom 1, down to zoom 0 - keeping the web cell under the mouse
; where it is: new origin = mouse - (mouse - origin) * new cell size / old cell size (leaf)
web_zoom_input:
    mov     eax, [ui_input + UIINPUT.scroll]
    test    eax, eax
    jz      .ret
    xor     ecx, ecx
    test    eax, eax
    setg    cl                          ; the zoom the wheel asks for
    cmp     ecx, [web_zoom]
    je      .ret
    mov     esi, WEB_CELL0              ; old cell size
    mov     edi, WEB_CELL1              ; new cell size
    cmp     dword [web_zoom], 0
    je      .sized
    xchg    esi, edi
.sized:
    mov     [web_zoom], ecx
    mov     r8d, [ui_mx]
    mov     eax, r8d
    sub     eax, [web_ox]
    imul    eax, edi
    cdq
    idiv    esi
    sub     r8d, eax
    mov     [web_ox], r8d
    mov     r8d, [ui_my]
    mov     eax, r8d
    sub     eax, [web_oy]
    imul    eax, edi
    cdq
    idiv    esi
    sub     r8d, eax
    mov     [web_oy], r8d
    jmp     web_clamp
.ret:
    ret

; web_input(): hover, pan, click and the ability keys. web_hover = the node under the mouse that is
; drawn, or -1. A press outside any node inside the viewport starts a pan (the origin follows the
; mouse until the button is up); a press on a node waits for the release: under WEB_DRAG units of
; travel spends a point there (rpg_spend), more cancels (neither pans nor spends). While a node
; that teaches a learned ability is hovered, an ability key binds it to that bar slot.
; ebx = hovered node, r12d = ability, r13d = key, r14d = slot
web_input:
    ENTER_FRAME 24
    mov     dword [web_hover], -1
    mov     edi, [ui_mx]
    mov     esi, [ui_my]
    mov     edx, [web_ox]
    mov     ecx, [web_oy]
    mov     r8d, [web_zoom]
    call    web_pick
    mov     ebx, eax
    test    ebx, ebx
    js      .picked
    mov     edi, ebx
    call    web_vis
    test    eax, eax
    jnz     .picked
    mov     ebx, -1                     ; under the mouse but not drawn: ignored
.picked:
    mov     [web_hover], ebx
    cmp     dword [ui_input + UIINPUT.lmb_pressed], 0
    je      .state
    mov     eax, [ui_mx]
    mov     [web_px], eax
    mov     [web_lx], eax
    mov     eax, [ui_my]
    mov     [web_py], eax
    mov     [web_ly], eax
    mov     [web_pressnode], ebx
    mov     dword [web_drag], DRAG_NODE
    test    ebx, ebx
    jns     .state
    mov     dword [web_drag], DRAG_NONE
    mov     eax, [ui_mx]                ; a press on the empty web pans, inside the viewport only
    cmp     eax, WEB_VX
    jl      .state
    mov     ecx, [ui_w]
    sub     ecx, WEB_VR
    cmp     eax, ecx
    jge     .state
    mov     eax, [ui_my]
    cmp     eax, WEB_VY
    jl      .state
    mov     ecx, [ui_h]
    sub     ecx, WEB_VB
    cmp     eax, ecx
    jge     .state
    mov     dword [web_drag], DRAG_PAN
.state:
    mov     eax, [web_drag]
    test    eax, eax
    jz      .keys
    cmp     eax, DRAG_PAN
    jne     .node
    cmp     dword [ui_input + UIINPUT.lmb_held], 0
    jne     .pan
    mov     dword [web_drag], DRAG_NONE
    jmp     .keys
.pan:
    mov     eax, [ui_mx]
    mov     ecx, eax
    sub     eax, [web_lx]
    add     [web_ox], eax
    mov     [web_lx], ecx
    mov     eax, [ui_my]
    mov     ecx, eax
    sub     eax, [web_ly]
    add     [web_oy], eax
    mov     [web_ly], ecx
    call    web_clamp
    mov     dword [web_hover], -1       ; nothing is hovered while the web is moving
    jmp     .done
.node:                                  ; a press on a node: a click unless the mouse travelled
    mov     eax, [ui_mx]
    sub     eax, [web_px]
    mov     edx, eax
    sar     edx, 31
    xor     eax, edx
    sub     eax, edx
    mov     ecx, [ui_my]
    sub     ecx, [web_py]
    mov     edx, ecx
    sar     edx, 31
    xor     ecx, edx
    sub     ecx, edx
    cmp     ecx, eax
    cmovg   eax, ecx                    ; max(|dx|, |dy|)
    cmp     eax, WEB_DRAG
    jl      .near
    mov     dword [web_drag], DRAG_CANCEL
.near:
    cmp     dword [ui_input + UIINPUT.lmb_held], 0
    jne     .keys
    cmp     dword [web_drag], DRAG_NODE
    jne     .released
    mov     edi, [web_pressnode]
    call    rpg_spend
.released:
    mov     dword [web_drag], DRAG_NONE
.keys:
    mov     ebx, [web_hover]
    test    ebx, ebx
    js      .done
    mov     edi, ebx
    call    web_node_ability
    test    eax, eax
    js      .done
    mov     r12d, eax
    mov     edi, eax
    call    rpg_ability_learned
    test    eax, eax
    jz      .done
    mov     r13d, [ui_input + UIINPUT.key_pressed]
    test    r13d, r13d
    jle     .done                       ; -1 = no key this frame (an unbound key must not match it)
    xor     r14d, r14d
.slot:
    lea     rax, [ability_binds]
    movzx   eax, byte [rax + r14]
    lea     rcx, [settings + SETTINGS.keys]
    cmp     r13d, [rcx + rax*4]
    jne     .next
    mov     edi, r14d
    mov     esi, r12d
    call    rpg_bar_set
    jmp     .done
.next:
    inc     r14d
    cmp     r14d, NUM_ABILITY_SLOTS
    jb      .slot
.done:
    LEAVE_FRAME 24

; web_line(edi x0, esi y0, edx x1, ecx y1, r8d rgba, r9d width): a line of width x width squares
; (ui_rect) from (x0, y0) to (x1, y1), DDA along the longer axis max(|dx|, |dy|) = n: a straight
; line is one rectangle, any other takes a square every `width` units of n (and one at the end), so
; neighbouring squares touch. Locals: [rsp] rgba, [rsp+4] width, [rsp+8] step i, [rsp+12] width / 2,
; [rsp+16] x of the square, [rsp+20] rectangle height
; ebx = x0, r12d = y0, r13d = dx, r14d = dy, r15d = n
web_line:
    ENTER_FRAME 24
    mov     [rsp], r8d
    mov     [rsp + 4], r9d
    shr     r9d, 1
    mov     [rsp + 12], r9d
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    sub     r13d, edi
    mov     r14d, ecx
    sub     r14d, esi
    mov     eax, r13d
    cdq
    xor     eax, edx
    sub     eax, edx
    mov     r15d, eax
    mov     eax, r14d
    cdq
    xor     eax, edx
    sub     eax, edx                    ; |dy|
    cmp     eax, r15d
    cmova   r15d, eax                   ; n
    test    r13d, r13d
    jz      .rect
    test    r14d, r14d
    jz      .rect
    mov     dword [rsp + 8], 0
.step:
    mov     eax, r13d
    imul    eax, [rsp + 8]
    cdq
    idiv    r15d
    add     eax, ebx
    sub     eax, [rsp + 12]
    mov     [rsp + 16], eax
    mov     eax, r14d
    imul    eax, [rsp + 8]
    cdq
    idiv    r15d
    add     eax, r12d
    sub     eax, [rsp + 12]
    mov     esi, eax
    mov     edi, [rsp + 16]
    mov     edx, [rsp + 4]
    mov     ecx, edx
    mov     r8d, [rsp]
    call    ui_rect
    mov     eax, [rsp + 8]
    cmp     eax, r15d
    jae     .ret
    add     eax, [rsp + 4]
    cmp     eax, r15d
    cmova   eax, r15d
    mov     [rsp + 8], eax
    jmp     .step
.rect:                                  ; straight (or a point): min(x0, x1) .. + |dx| + width
    mov     eax, r14d
    cdq
    xor     eax, edx
    sub     eax, edx
    add     eax, [rsp + 4]
    mov     [rsp + 20], eax             ; height
    mov     eax, r13d
    sar     eax, 31
    and     eax, r13d
    add     eax, ebx
    sub     eax, [rsp + 12]
    mov     [rsp + 16], eax             ; x
    mov     eax, r14d
    sar     eax, 31
    and     eax, r14d
    add     eax, r12d
    sub     eax, [rsp + 12]
    mov     esi, eax                    ; y
    mov     eax, r13d
    cdq
    xor     eax, edx
    sub     eax, edx
    add     eax, [rsp + 4]
    mov     edx, eax                    ; width
    mov     edi, [rsp + 16]
    mov     ecx, [rsp + 20]
    mov     r8d, [rsp]
    call    ui_rect
.ret:
    LEAVE_FRAME 24

; web_draw_edges(): every pair of web_edges as a line between the two node centres, gold when both
; ends have a rank, light when one has, dim when none; width 2 at zoom 1, 1 at zoom 0. Drawn only when
; both centres are inside the viewport. Locals: [rsp] x0, [rsp+4] y0, [rsp+8] x1, [rsp+12] y1
; ebx = edge, r13d / r14d = its end nodes, r12d = how many ends are ranked
web_draw_edges:
    ENTER_FRAME 24
    xor     ebx, ebx
.edge:
    cmp     ebx, [web_edge_count]
    jae     .ret
    lea     rax, [web_edges]
    movzx   r13d, word [rax + rbx*4]
    movzx   r14d, word [rax + rbx*4 + 2]
    mov     edi, r13d
    call    web_centre
    mov     [rsp], eax
    mov     [rsp + 4], edx
    mov     edi, r14d
    call    web_centre
    mov     [rsp + 8], eax
    mov     [rsp + 12], edx
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    xor     edx, edx
    call    web_cull
    test    eax, eax
    jz      .next
    mov     edi, [rsp + 8]
    mov     esi, [rsp + 12]
    xor     edx, edx
    call    web_cull
    test    eax, eax
    jz      .next
    xor     r12d, r12d
    mov     edi, r13d
    call    rpg_rank
    test    eax, eax
    setnz   r12b
    mov     edi, r14d
    call    rpg_rank
    test    eax, eax
    setnz   al
    movzx   eax, al
    add     r12d, eax
    lea     rax, [web_edge_cols]
    mov     r8d, [rax + r12*4]
    mov     r9d, 1
    mov     eax, 2
    cmp     dword [web_zoom], 0
    cmovne  r9d, eax
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    mov     edx, [rsp + 8]
    mov     ecx, [rsp + 12]
    call    web_line
.next:
    inc     ebx
    jmp     .edge
.ret:
    LEAVE_FRAME 24

; web_draw_compass(): TILE_COMPASS (32 x 32, 16 at zoom 0) on the origin and the four archetype names
; beside their path nodes: Warrior right of its node, Archer left, Mage and Rogue above (the first
; tier of every branch starts 3 units past the path node, so "outward" has no room, and below a
; node hangs its rank tag); a name is drawn when it lies whole inside the viewport.
; Locals: [rsp] name, [rsp+8] its width, [rsp+12] x, [rsp+16] y
; ebx = archetype, r12d = compass half size, r13d / r14d = path node centre, r15d = its half size
web_draw_compass:
    ENTER_FRAME 24
    mov     r12d, 8
    mov     eax, 16
    cmp     dword [web_zoom], 0
    cmovne  r12d, eax
    mov     edi, [web_ox]
    mov     esi, [web_oy]
    mov     edx, r12d
    call    web_cull
    test    eax, eax
    jz      .names
    mov     edi, TILE_COMPASS
    mov     esi, [web_ox]
    sub     esi, r12d
    mov     edx, [web_oy]
    sub     edx, r12d
    lea     ecx, [r12 + r12]
    mov     r8d, WHITE
    call    ui_tile_icon
.names:
    mov     ebx, 1
.arch:
    lea     edi, [rbx - 1]
    call    web_centre
    mov     r13d, eax
    mov     r14d, edx
    lea     edi, [rbx - 1]
    mov     esi, [web_zoom]
    call    web_dims
    mov     r15d, eax
    mov     edi, ebx
    call    rpg_archetype_name
    mov     [rsp], rax
    mov     rdi, rax
    mov     esi, 1
    call    ui_text_width
    mov     [rsp + 8], eax
    cmp     ebx, ARCH_WARRIOR
    jne     .not_warrior
    lea     eax, [r13 + r15 + 3]        ; right of the node
    lea     edx, [r14 - 4]
    jmp     .placed
.not_warrior:
    cmp     ebx, ARCH_ARCHER
    jne     .not_archer
    lea     eax, [r13 - 3]              ; left of the node
    sub     eax, r15d
    sub     eax, [rsp + 8]
    lea     edx, [r14 - 4]
    jmp     .placed
.not_archer:
    mov     eax, [rsp + 8]
    shr     eax, 1
    neg     eax
    add     eax, r13d                   ; centred on the node
    lea     edx, [r14 - 10]             ; Mage and Rogue: above the node
    sub     edx, r15d
.placed:
    mov     [rsp + 12], eax
    mov     [rsp + 16], edx
    mov     edi, eax
    lea     esi, [rdx + 4]
    mov     edx, 4
    call    web_cull
    test    eax, eax
    jz      .next
    mov     edi, [rsp + 12]
    add     edi, [rsp + 8]
    mov     esi, [rsp + 16]
    add     esi, 4
    mov     edx, 4
    call    web_cull
    test    eax, eax
    jz      .next
    mov     rdi, [rsp]
    mov     esi, [rsp + 12]
    mov     edx, [rsp + 16]
    mov     ecx, COL_ARCH
    mov     r8d, 1
    call    ui_text
.next:
    inc     ebx
    cmp     ebx, NUM_ARCHETYPES
    jbe     .arch
    LEAVE_FRAME 24

; web_draw_node(edi node): the node when it is inside the viewport: a frame by kind (stat: one
; line; ability: two; keystone and path: a thick one, the path on a warmer ground), 22 x 22 (path
; 28 x 28) with a 16 x 16 icon at zoom 1, 9 x 9 (path 12 x 12) without one at zoom 0, where a ranked
; node is a solid block. Border: maxed gold, ranked green, reachable white, locked grey (a keystone is
; always gold); a node that is reachable and still unranked has a gold ring 1 unit outside; an
; unreachable node's icon is dimmed; the hovered node gets a white wash; zoom 1 shows "r/m" at
; (right - 3 - width, bottom - 2).
; Locals: [rsp] rank, [rsp+4] reachable, [rsp+8] half, [rsp+12] size, [rsp+16] border colour,
; [rsp+20] frame x, [rsp+24] frame y, [rsp+28] centre x, [rsp+32] centre y
; ebx = node, r12 = WEBNODE*
web_draw_node:
    ENTER_FRAME 40
    mov     ebx, edi
    call    web_vis
    test    eax, eax
    jz      .ret
    mov     edi, ebx
    call    rpg_web_node
    mov     r12, rax
    mov     edi, ebx
    call    rpg_rank
    mov     [rsp], eax
    mov     edi, ebx
    call    rpg_reachable
    mov     [rsp + 4], eax
    mov     edi, ebx
    call    web_centre
    mov     [rsp + 28], eax
    mov     [rsp + 32], edx
    mov     edi, ebx
    mov     esi, [web_zoom]
    call    web_dims
    mov     [rsp + 8], eax
    mov     [rsp + 12], edx
    shr     edx, 1
    mov     eax, [rsp + 28]
    sub     eax, edx
    mov     [rsp + 20], eax
    mov     eax, [rsp + 32]
    sub     eax, edx
    mov     [rsp + 24], eax
    ; border: maxed, ranked, reachable, locked (in that priority); a keystone is always gold
    mov     eax, COL_LOCKED
    mov     edx, COL_SPEND
    cmp     dword [rsp + 4], 0
    cmovne  eax, edx
    mov     edx, [rsp]
    test    edx, edx
    jz      .border_set
    mov     eax, COL_RANKED
    mov     ecx, COL_MAXED
    movzx   esi, byte [r12 + WEBNODE.max]
    cmp     edx, esi
    cmovae  eax, ecx
.border_set:
    mov     ecx, COL_KEYSTONE
    cmp     byte [r12 + WEBNODE.kind], NODE_KEYSTONE
    cmove   eax, ecx
    mov     [rsp + 16], eax
    ; ground
    mov     r8d, COL_NODE_BG
    mov     eax, COL_PATH_BG
    cmp     byte [r12 + WEBNODE.kind], NODE_PATH
    cmove   r8d, eax
    cmp     dword [web_zoom], 0
    jne     .ground
    cmp     dword [rsp], 0
    je      .ground
    mov     r8d, [rsp + 16]             ; zoom 0: a ranked node is a solid block of its border colour
.ground:
    mov     edi, [rsp + 20]
    mov     esi, [rsp + 24]
    mov     edx, [rsp + 12]
    mov     ecx, edx
    call    ui_rect
    cmp     ebx, [web_hover]
    jne     .frame
    mov     edi, [rsp + 20]
    mov     esi, [rsp + 24]
    mov     edx, [rsp + 12]
    mov     ecx, edx
    mov     r8d, COL_WASH
    call    ui_rect
.frame:
    mov     edi, [rsp + 20]
    mov     esi, [rsp + 24]
    mov     edx, [rsp + 12]
    mov     ecx, edx
    mov     r8d, [rsp + 16]
    call    ui_frame
    cmp     dword [web_zoom], 0
    je      .ring
    xor     ecx, ecx                    ; inset of a second frame: ability 2, keystone and path 1
    movzx   eax, byte [r12 + WEBNODE.kind]
    cmp     eax, NODE_ABILITY
    jne     .not_ability
    mov     ecx, 2
    jmp     .inset
.not_ability:
    cmp     eax, NODE_KEYSTONE
    je      .thick
    cmp     eax, NODE_PATH
    jne     .inset
.thick:
    mov     ecx, 1
.inset:
    test    ecx, ecx
    jz      .ring
    mov     edi, [rsp + 20]
    add     edi, ecx
    mov     esi, [rsp + 24]
    add     esi, ecx
    lea     eax, [rcx + rcx]
    mov     edx, [rsp + 12]
    sub     edx, eax
    mov     ecx, edx
    mov     r8d, [rsp + 16]
    call    ui_frame
.ring:
    cmp     dword [rsp + 4], 0
    je      .icon
    cmp     dword [rsp], 0
    jne     .icon
    mov     edi, [rsp + 20]
    dec     edi
    mov     esi, [rsp + 24]
    dec     esi
    mov     edx, [rsp + 12]
    add     edx, 2
    mov     ecx, edx
    mov     r8d, COL_RING
    call    ui_frame
.icon:
    cmp     dword [web_zoom], 0
    je      .ret
    movzx   eax, byte [r12 + WEBNODE.kind]
    cmp     eax, NODE_ABILITY
    je      .t_ability
    cmp     eax, NODE_KEYSTONE
    je      .t_keystone
    cmp     eax, NODE_PATH
    je      .t_path
    movzx   edi, byte [r12 + WEBNODE.stat]      ; a stat node shows its stat's glyph
    call    rpg_stat_info
    movzx   edi, byte [rax + STATINFO.icon]
    jmp     .draw_icon
.t_ability:
    movzx   edi, byte [r12 + WEBNODE.stat]      ; the ability id
    call    rpg_ability_tile
    mov     edi, eax
    jmp     .draw_icon
.t_keystone:
    mov     edi, TILE_KEYSTONE
    jmp     .draw_icon
.t_path:
    movzx   edi, byte [r12 + WEBNODE.stat]
    add     edi, TILE_CLASS0 - 1
.draw_icon:
    mov     esi, [rsp + 28]
    sub     esi, 8
    mov     edx, [rsp + 32]
    sub     edx, 8
    mov     ecx, 16
    mov     r8d, WHITE
    mov     eax, COL_DIMICON
    cmp     dword [rsp + 4], 0
    cmove   r8d, eax                    ; not reachable: dimmed
    call    ui_tile_icon
    mov     edi, [rsp]
    movzx   esi, byte [r12 + WEBNODE.max]
    lea     rdx, [rank_buf]
    call    rank_text
    lea     rdi, [rank_buf]
    mov     esi, 1
    call    ui_text_width
    mov     esi, [rsp + 20]
    add     esi, [rsp + 12]
    sub     esi, 3                      ; the ink ends 4 units inside the right edge (the pen adds 1)
    sub     esi, eax
    mov     edx, [rsp + 24]
    add     edx, [rsp + 12]
    sub     edx, 2
    mov     ecx, RGBA(200, 200, 200, 255)
    mov     eax, [rsp + 16]
    cmp     dword [rsp], 0
    cmovne  ecx, eax
    lea     rdi, [rank_buf]
    mov     r8d, 1
    call    ui_text
.ret:
    LEAVE_FRAME 40

; web_tooltip(edi node): "<name>[ (Keystone)] r/m: <text>" at the mouse (tooltip_wrapped), the text
; being the stat's value per rank (rpg_format_stat) or the node's description; its hint paragraph is
; "- needs level N" while the character is below the node's level, else "- not linked to a skill you
; have" when the node is not reachable, else for a learned ability "Press Q/G/V/X to place it on your
; bar" (the four ability keys). Locals: [rsp] the node's level
; ebx = node, r12d = key index, r14 = WEBNODE*, r15 = write cursor
web_tooltip:
    ENTER_FRAME 24
    mov     ebx, edi
    call    rpg_web_node
    test    rax, rax
    jz      .ret
    mov     r14, rax
    lea     r15, [tip_buf]
    APPP    [r14 + WEBNODE.name]
    cmp     byte [r14 + WEBNODE.kind], NODE_KEYSTONE
    jne     .rank
    APPZ    s_keystone
.rank:
    APPZ    s_space
    mov     edi, ebx
    call    rpg_rank
    APPN    eax
    APPZ    s_slash
    movzx   eax, byte [r14 + WEBNODE.max]
    APPN    eax
    APPZ    s_colon_sp
    cmp     byte [r14 + WEBNODE.kind], NODE_STAT
    jne     .desc
    movzx   edi, byte [r14 + WEBNODE.stat]      ; a stat node has no text of its own
    mov     esi, [r14 + WEBNODE.value]
    lea     rdx, [fmt_buf]
    call    rpg_format_stat
    APPP    rax
    APPZ    s_per_rank
    jmp     .text_done
.desc:
    mov     rax, [r14 + WEBNODE.desc]
    test    rax, rax
    jz      .text_done
    APPP    rax
.text_done:
    mov     byte [r15], 0
    lea     r15, [tip_hint]
    mov     byte [r15], 0               ; empty unless something is missing or to be told
    movzx   eax, byte [r14 + WEBNODE.level]
    mov     [rsp], eax
    call    rpg_level
    cmp     eax, [rsp]
    jae     .level_ok
    APPZ    s_needs_level
    APPN    dword [rsp]
    jmp     .hint_done
.level_ok:
    mov     edi, ebx
    call    rpg_reachable
    test    eax, eax
    jnz     .linked
    APPZ    s_not_linked
    jmp     .hint_done
.linked:
    mov     edi, ebx
    call    web_node_ability
    test    eax, eax
    js      .hint_done
    mov     edi, eax
    call    rpg_ability_learned
    test    eax, eax
    jz      .hint_done
    APPZ    s_press
    xor     r12d, r12d
.key:
    test    r12d, r12d
    jz      .key_name
    mov     byte [r15], '/'
    inc     r15
.key_name:
    lea     rax, [ability_binds]
    movzx   eax, byte [rax + r12]
    lea     rcx, [settings + SETTINGS.keys]
    mov     edi, [rcx + rax*4]
    mov     rsi, r15
    call    key_name
    mov     r15, rax
    inc     r12d
    cmp     r12d, NUM_ABILITY_SLOTS
    jb      .key
    APPZ    s_place
.hint_done:
    mov     byte [r15], 0
    lea     rdi, [tip_buf]
    lea     rsi, [tip_hint]
    call    tooltip_wrapped
.ret:
    LEAVE_FRAME 24

; web_spread(): the flat stand-in of the open book: a dimmer, the cover, two pages 4 units apart
; with the spine between them, "Grimoire" centred on the cover, "<title> - Level N" and "Points: N"
; (screen_header, s_px / s_py = 16 / 17 so its text lands at x 24, y 22 and ends at ui_w - 24) and
; the dark backing of the viewport. Locals: [rsp] page width, [rsp+4] page height
web_spread:
    ENTER_FRAME 24
    mov     eax, [ui_w]
    sub     eax, 32
    shr     eax, 1
    mov     [rsp], eax
    mov     eax, [ui_h]
    sub     eax, 28
    mov     [rsp + 4], eax
    xor     edi, edi
    xor     esi, esi
    mov     edx, [ui_w]
    mov     ecx, [ui_h]
    mov     r8d, DIM_COL
    call    ui_rect
    mov     edi, 8                      ; the cover: 6 units beyond both pages
    mov     esi, 8
    mov     edx, [rsp]
    lea     edx, [rdx*2 + 16]
    mov     ecx, [rsp + 4]
    add     ecx, 12
    mov     r8d, COL_COVER
    call    ui_rect
    mov     edi, 14                     ; left page
    mov     esi, 14
    mov     edx, [rsp]
    mov     ecx, [rsp + 4]
    mov     r8d, PANEL_COL
    call    ui_rect
    mov     edi, 14
    mov     esi, 14
    mov     edx, [rsp]
    mov     ecx, [rsp + 4]
    mov     r8d, EDGE_COL
    call    ui_frame
    mov     edi, [rsp]                  ; spine
    add     edi, 14
    mov     esi, 14
    mov     edx, 4
    mov     ecx, [rsp + 4]
    mov     r8d, COL_SPINE
    call    ui_rect
    mov     edi, [rsp]                  ; right page
    add     edi, 18
    mov     esi, 14
    mov     edx, [rsp]
    mov     ecx, [rsp + 4]
    mov     r8d, PANEL_COL
    call    ui_rect
    mov     edi, [rsp]
    add     edi, 18
    mov     esi, 14
    mov     edx, [rsp]
    mov     ecx, [rsp + 4]
    mov     r8d, EDGE_COL
    call    ui_frame
    lea     rdi, [s_grimoire]
    mov     esi, [ui_w]
    shr     esi, 1
    mov     edx, 6
    mov     ecx, GOLD
    mov     r8d, 1
    call    ui_text_centered
    lea     rdi, [s_tab_char]           ; between the title and the points
    mov     esi, [ui_w]
    shr     esi, 1
    mov     edx, 22
    mov     ecx, GREY
    mov     r8d, 1
    call    ui_text_centered
    mov     edi, WEB_VX                 ; the viewport
    mov     esi, WEB_VY
    mov     edx, [ui_w]
    sub     edx, WEB_VX + WEB_VR
    mov     ecx, [ui_h]
    sub     ecx, WEB_VY + WEB_VB
    mov     r8d, COL_VIEW
    call    ui_rect
    mov     edi, WEB_VX
    mov     esi, WEB_VY
    mov     edx, [ui_w]
    sub     edx, WEB_VX + WEB_VR
    mov     ecx, [ui_h]
    sub     ecx, WEB_VY + WEB_VB
    mov     r8d, EDGE_COL
    call    ui_frame
    mov     dword [s_px], 16
    mov     dword [s_py], 17
    call    rpg_points
    mov     edx, eax
    lea     rsi, [s_points]
    mov     ecx, [ui_w]
    sub     ecx, 32
    call    screen_header
    LEAVE_FRAME 24

; web_footer(): at y = ui_h - 38 the "Unlearn all: N coins" button (120 wide at x 24; enabled with N
; coins in the pack and a rank somewhere; a click calls rpg_respec), the four bar slots (20 x 20,
; step 23, centred on ui_w / 2) with the bound ability's icon and its key above; a right click on a
; slot empties it; and "Wheel: zoom  Drag: move" ending at ui_w - 24.
; Locals: [rsp] respec cost, [rsp+4] y, [rsp+8] x of slot 0, [rsp+16..39] key name
; ebx = slot, r12d = enabled / slot hovered, r13d / r14d = slot x / y
web_footer:
    ENTER_FRAME 40
    mov     eax, [ui_h]
    sub     eax, 38
    mov     [rsp + 4], eax
    call    rpg_respec_cost
    mov     [rsp], eax
    lea     r15, [coin_buf]
    APPZ    s_unlearn
    APPN    dword [rsp]
    APPZ    s_coins_sfx
    mov     byte [r15], 0
    xor     r12d, r12d
    call    rpg_level
    mov     ebx, eax
    call    rpg_points
    cmp     eax, ebx
    jge     .button                     ; every point unspent: nothing to give back
    mov     edi, GOLD_COIN
    call    inv_count
    cmp     eax, [rsp]
    jb      .button
    mov     r12d, 1
.button:
    lea     rdi, [coin_buf]
    mov     esi, 24
    mov     edx, [rsp + 4]
    mov     ecx, 120
    mov     r8d, r12d
    call    ui_button
    test    eax, eax
    jz      .slots
    call    rpg_respec
.slots:
    mov     eax, [ui_w]
    shr     eax, 1
    sub     eax, 44                     ; the 89 units of four slots centred on ui_w / 2
    mov     [rsp + 8], eax
    xor     ebx, ebx
.slot:
    imul    r13d, ebx, 23
    add     r13d, [rsp + 8]
    mov     r14d, [rsp + 4]
    mov     edi, r13d
    mov     esi, r14d
    mov     edx, 20
    mov     ecx, 20
    call    hit
    mov     r12d, eax
    test    r12d, r12d
    jz      .backing
    cmp     dword [ui_input + UIINPUT.rmb_pressed], 0
    je      .backing
    mov     edi, ebx
    mov     esi, -1
    call    rpg_bar_set                 ; a right click empties the slot
.backing:
    mov     edi, r13d
    mov     esi, r14d
    mov     edx, 20
    mov     ecx, 20
    mov     r8d, RGBA(0, 0, 0, 115)
    call    ui_rect
    mov     r8d, EDGE_COL
    mov     eax, RGBA(255, 255, 255, 170)
    test    r12d, r12d
    cmovnz  r8d, eax
    mov     edi, r13d
    mov     esi, r14d
    mov     edx, 20
    mov     ecx, 20
    call    ui_frame
    mov     edi, ebx
    call    rpg_bar_ability
    test    eax, eax
    js      .label
    mov     edi, eax
    call    rpg_ability_tile
    mov     edi, eax
    lea     esi, [r13 + 2]
    lea     edx, [r14 + 2]
    mov     ecx, 16
    mov     r8d, WHITE
    call    ui_tile_icon
.label:
    lea     rax, [ability_binds]
    movzx   eax, byte [rax + rbx]
    lea     rcx, [settings + SETTINGS.keys]
    mov     edi, [rcx + rax*4]
    lea     rsi, [rsp + 16]
    call    key_name
    mov     byte [rsp + 19], 0          ; at most three characters fit over a slot
    lea     rdi, [rsp + 16]
    lea     esi, [r13 + 1]
    lea     edx, [r14 - 9]
    mov     ecx, WHITE
    mov     r8d, 1
    call    ui_text
    inc     ebx
    cmp     ebx, NUM_ABILITY_SLOTS
    jb      .slot
    lea     rdi, [s_wheel_hint]
    mov     esi, 1
    call    ui_text_width
    mov     esi, [ui_w]
    sub     esi, 24 - 1                 ; right aligned: the ink ends at ui_w - 24
    sub     esi, eax
    lea     rdi, [s_wheel_hint]
    mov     edx, [rsp + 4]
    add     edx, 6
    mov     ecx, GREY
    mov     r8d, 1
    call    ui_text
    LEAVE_FRAME 40

; screen_skills(): the grimoire - an open book over the world with the skill web (see above) on it:
; header, the web in its viewport, the footer and a tooltip for the hovered node. A click on a node
; spends a skill point (rpg_spend); Tab opens the character sheet. Everyone may open it.
; ebx = node being drawn
screen_skills:
    ENTER_FRAME 24
    cmp     dword [app_entered], 0
    je      .seen
    mov     dword [web_drag], DRAG_NONE ; a fresh visit cannot continue a press of the last one
.seen:
    call    close_check
    test    eax, eax
    jnz     .ret
    cmp     dword [ui_input + UIINPUT.key_pressed], KEY_TAB
    jne     .no_tab
    mov     edi, ST_CHARACTER
    call    app_goto
    jmp     .ret
.no_tab:
    call    web_open
    call    web_clamp                   ; the screen may have changed size since the last frame
    call    web_zoom_input
    call    web_input
    call    web_spread
    call    web_draw_edges
    call    web_draw_compass
    xor     ebx, ebx
.node:
    mov     edi, ebx
    call    web_draw_node
    inc     ebx
    cmp     ebx, NUM_WEB_NODES
    jb      .node
    call    web_footer
    mov     edi, [web_hover]
    test    edi, edi
    js      .ret
    call    web_tooltip
.ret:
    LEAVE_FRAME 24

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
; scrolls; Tab opens the grimoire. The stats are recomputed first: gear changes them.
; Locals: [rsp] hovered attribute or -1, [rsp+8] attribute points, [rsp+12]
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
    call    rpg_recompute
    mov     edi, CH_W
    mov     esi, CH_H
    call    panel_begin
    mov     r12d, [s_px]
    mov     r13d, [s_py]
    call    rpg_attr_points
    mov     [rsp + 8], eax
    mov     edx, eax
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

; ---- traders -------------------------------------------------------------------------------------

; screen_trade(): the current trader's trade_count offers (trade_open picked the table) as
; "give -> get" rows with a Trade button each (enabled while trade_can), under its trade_title;
; the panel is as high as its rows. Hovering an icon names the item, or for a gear offer says
; what it rolls.
; Locals: [rsp] item id under the mouse (0 = none), [rsp+4] trade_can of the row, [rsp+8] 1 when
; that icon is the "get" side
screen_trade:
    ENTER_FRAME 24
    call    close_check
    test    eax, eax
    jnz     .ret
    mov     edi, TR_W
    imul    esi, [trade_count], TR_ROW
    add     esi, TR_BASE
    call    panel_begin
    mov     r12d, [s_px]
    mov     r13d, [s_py]
    mov     dword [rsp], 0
    mov     rdi, [trade_title]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 6]
    mov     ecx, GOLD
    mov     r8d, 1
    call    ui_text
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
    imul    eax, ebx, TR_ROW
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
    cmp     ebx, [trade_count]
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

; screen_dialog(): the current quest of the chain (rpg.asm's quest state) with Accept / Complete /
; Leave; when the chain is finished a farewell. Locals: [rsp] quest accepted, [rsp+4] progress
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
    jmp     .ret
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
    jz      .ret
.close:
    mov     edi, ST_PLAYING
    call    app_goto
.ret:
    LEAVE_FRAME 24

; ---- factions ----------------------------------------------------------------------------------

; draw_standing(edi faction, esi x, edx y): "Standing: N (Tier)" at (x, y) in the colour of the
; faction's tier. ebx = faction, r12d = x, r13d = y, r15 = write cursor into coin_buf
draw_standing:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r15
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    lea     r15, [coin_buf]
    APPZ    s_standing
    mov     edi, ebx
    call    faction_standing
    APPN    eax
    APPZ    s_open_paren
    mov     edi, ebx
    call    faction_tier
    mov     ecx, eax
    lea     rdx, [tier_names]
    APPP    [rdx + rcx*8]
    APPZ    s_close_paren
    mov     byte [r15], 0
    mov     edi, ebx
    call    faction_tier_color
    mov     ecx, eax
    lea     rdi, [coin_buf]
    mov     esi, r12d
    mov     edx, r13d
    mov     r8d, 1
    call    ui_text
    pop     r15
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; screen_leader(): ST_LEADER, what the leader of screen_faction says: "<Faction> Leader", the
; standing in its tier colour, a greeting by tier (a tier under Neutral reads as Neutral), the
; rivals and the champion (fallen or not), and Leave. Informational: leader quests and rewards
; belong to the faction arcs.
; r12d, r13d = panel origin, r14d = faction, ebx = rivals still to name (a bit per faction),
; r15 = write cursor. Frame: [rsp] where the first rival's name starts, [rsp+8] the rival being
; named
screen_leader:
    ENTER_FRAME 24
    call    close_check
    test    eax, eax
    jnz     .ret
    mov     edi, DL_W
    mov     esi, DL_H
    call    panel_begin
    mov     r12d, [s_px]
    mov     r13d, [s_py]
    mov     r14d, [screen_faction]
    lea     r15, [hdr_buf]              ; "<Faction> Leader"
    lea     rax, [faction_names]
    APPP    [rax + r14*8]
    APPZ    s_leader_sfx
    mov     byte [r15], 0
    lea     rdi, [hdr_buf]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 6]
    mov     ecx, GOLD
    mov     r8d, 1
    call    ui_text
    mov     edi, r14d
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 24]
    call    draw_standing
    mov     edi, r14d                   ; the greeting: Neutral, Friendly or Allied
    call    faction_tier
    xor     ecx, ecx
    sub     eax, TIER_NEUTRAL
    cmovs   eax, ecx
    lea     rdx, [leader_greetings]
    mov     rdi, [rdx + rax*8]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 40]
    mov     ecx, LABEL_COL
    mov     r8d, 1
    call    ui_text
    lea     rdx, [faction_rivals]       ; "Rivals: A, B"
    movzx   ebx, byte [rdx + r14]
    lea     r15, [row_buf]
    APPZ    s_rivals
    mov     [rsp], r15
.rival:
    bsf     eax, ebx                    ; the next rival still to name
    jz      .rivals_done
    btr     ebx, eax
    mov     [rsp + 8], eax
    cmp     r15, [rsp]
    je      .first_rival
    APPZ    s_comma_sp
.first_rival:
    mov     eax, [rsp + 8]
    lea     rdx, [faction_names]
    APPP    [rdx + rax*8]
    jmp     .rival
.rivals_done:
    mov     byte [r15], 0
    lea     rdi, [row_buf]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 64]
    mov     ecx, LABEL_COL
    mov     r8d, 1
    call    ui_text
    lea     r15, [row_buf]              ; "Champion: <name>", with " (fallen)" once defeated
    APPZ    s_champion
    lea     rdx, [champion_names]
    APPP    [rdx + r14*8]
    mov     edi, r14d
    call    faction_champion_defeated
    test    eax, eax
    jz      .champion_up
    APPZ    s_fallen
.champion_up:
    mov     byte [r15], 0
    lea     rdi, [row_buf]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 78]
    mov     ecx, LABEL_COL
    mov     r8d, 1
    call    ui_text
    BTN     s_leave, r12, (DL_W - 100) / 2, r13, 118, 100
    test    eax, eax
    jz      .ret
    mov     edi, ST_PLAYING
    call    app_goto
.ret:
    LEAVE_FRAME 24

; screen_shrine(): ST_SHRINE, the tribute screen of the shrine of screen_faction: "<Faction>
; Shrine", the standing, the item it wants, four buttons (5 or 50 coins, 1 or 10 of the item) that
; call faction_tribute, what the pack holds and Leave. A button is enabled while the pack holds
; its payment and the standing is below the faction's cap (CULT_MAX for the Ashen Cult). The
; banner of a tier change (faction_add) is painted again above the panel, which covers the place
; hud_draw gave it.
; r12d, r13d = panel origin, r14d = faction, ebx = tribute row, r15 = its tribute_rows entry (then
; the write cursor). Frame: [rsp] coins in the pack, [rsp+4] the wanted item's count, [rsp+8] 1
; below the cap, [rsp+12] the wanted item
screen_shrine:
    ENTER_FRAME 24
    call    close_check
    test    eax, eax
    jnz     .ret
    mov     edi, TB_W
    mov     esi, TB_H
    call    panel_begin
    mov     r12d, [s_px]
    mov     r13d, [s_py]
    mov     r14d, [screen_faction]
    lea     r15, [hdr_buf]              ; "<Faction> Shrine"
    lea     rax, [faction_names]
    APPP    [rax + r14*8]
    APPZ    s_shrine_sfx
    mov     byte [r15], 0
    lea     rdi, [hdr_buf]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 6]
    mov     ecx, GOLD
    mov     r8d, 1
    call    ui_text
    mov     edi, r14d
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 24]
    call    draw_standing
    lea     rax, [faction_wanted]       ; "Wanted: <item>"
    movzx   eax, byte [rax + r14]
    mov     [rsp + 12], eax
    lea     r15, [hdr_buf]
    APPZ    s_wanted
    mov     eax, [rsp + 12]
    lea     rdx, [item_names]
    APPP    [rdx + rax*8]
    mov     byte [r15], 0
    lea     rdi, [hdr_buf]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 40]
    mov     ecx, LABEL_COL
    mov     r8d, 1
    call    ui_text
    mov     edi, GOLD_COIN              ; what the pack holds
    call    inv_count
    mov     [rsp], eax
    mov     edi, [rsp + 12]
    call    inv_count
    mov     [rsp + 4], eax
    mov     edi, r14d                   ; is the standing below the faction's cap?
    call    faction_standing
    mov     ecx, STANDING_MAX
    mov     edx, CULT_MAX
    cmp     r14d, FAC_CULT
    cmove   ecx, edx
    xor     edx, edx
    cmp     eax, ecx
    setl    dl
    mov     [rsp + 8], edx
    xor     ebx, ebx
.row:
    imul    eax, ebx, TB_ROW_SIZE
    lea     r15, [tribute_rows]
    add     r15, rax
    mov     eax, [r15 + 16]             ; kind: 0 pays in coins, 1 in the wanted item
    mov     ecx, [rsp + rax*4]          ; ... so that is the count the pack holds of it
    xor     edx, edx
    cmp     ecx, [r15 + 20]
    setae   dl
    and     edx, [rsp + 8]
    mov     r8d, edx                    ; enabled: payable and below the cap
    mov     rdi, [r15]
    mov     esi, [r15 + 8]
    add     esi, r12d
    mov     edx, [r15 + 12]
    add     edx, r13d
    mov     ecx, TB_BTN_W
    call    ui_button
    test    eax, eax
    jz      .next
    mov     edi, r14d
    mov     esi, [r15 + 16]
    mov     edx, [r15 + 20]
    call    faction_tribute
.next:
    inc     ebx
    cmp     ebx, 4
    jb      .row
    lea     r15, [coin_buf]             ; "Coins N, items M"
    APPZ    s_pack_coins
    APPN    dword [rsp]
    APPZ    s_pack_items
    APPN    dword [rsp + 4]
    mov     byte [r15], 0
    lea     rdi, [coin_buf]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 108]
    mov     ecx, LABEL_COL
    mov     r8d, 1
    call    ui_text
    BTN     s_leave, r12, (TB_W - 100) / 2, r13, 126, 100
    test    eax, eax
    jz      .banner
    mov     edi, ST_PLAYING
    call    app_goto
    jmp     .ret
.banner:
    lea     edi, [r13 - 18]             ; a tier change shows its banner (faction_add), which this
    mov     eax, 2                      ; panel covers in the middle of the screen: above the panel
    cmp     edi, eax
    cmovl   edi, eax
    call    hud_banner_paint
.ret:
    LEAVE_FRAME 24
