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
; The look is the grimoire's (theme.inc): every page (panel_begin) is a parchment NINE_PAGE under a ribbon
; with its title, its text in ink; a tooltip and a faction's standing are dark plates with light text. The
; grimoire itself is an open book (ui_book) with the web clipped to its viewport (ui_clip) and the footer
; drawn over the book.
%include "common.inc"
%include "gl.inc"
%include "theme.inc"
default rel

global screen_skills, screen_character, screen_trade, screen_dialog
global screen_shrine, screen_leader, screen_event, web_node_xy, web_pick, sheet_build, sheet_section, sheet_sec

extern ui_w, ui_h, ui_mx, ui_my, ui_input, frame_input, settings, app_entered
extern ui_rect, ui_frame, ui_panel, ui_text, ui_text_width, ui_text_ink, ui_text_ink_centered
extern ui_nine, ui_nine_tint, ui_line, ui_clip, ui_unclip, ui_ribbon, ui_book
extern ui_button, ui_item_icon, ui_tile_icon, ui_tooltip
extern app_goto, key_name, hud_banner_paint, audio_play, ui_icon9
extern item_names, item_gear, inv_count, i32_to_str, str_append, armor_effective
extern surv, surv_max_health, combat_weapon_preview, gear_tier_for_level
extern rpg_state, rpg_stats, rpg_level, rpg_points, rpg_rank
extern rpg_spend, rpg_stat_info, rpg_format_stat, rpg_recompute
extern rpg_attr, rpg_attr_points, rpg_spend_attr, rpg_attr_info, rpg_attr_desc
extern rpg_respec_cost, rpg_respec, rpg_ability_tile, rpg_path_tile
extern rpg_web_node, rpg_reachable, web_edges, web_edge_count, rpg_title, rpg_archetype_name
extern rpg_ability_learned, rpg_ability_info, rpg_bar_ability, rpg_bar_set
extern quests_current, quests_progress, quests_accept, quests_can_complete, quests_complete
extern trade_offer, trade_can, trade_execute, trade_count, trade_title
extern screen_faction, faction_names, faction_standing, faction_tier, faction_tier_color
extern faction_rivals, faction_champion_defeated, faction_tribute, faction_wanted
extern tier_names, champion_names
extern mobs, net_role, net_interact_out, game_open_npc
extern events_accept, events_offer_kind, ev_kind_waves, ev_kind_rep

; ---- colours: the palette is theme.inc's; these are what this file adds ----------------------
%define TINT_FAINT  RGBA(255, 255, 255, 205)    ; a web node nothing links to: its frame and icon
%define ICON_BACK_FAINT RGBA(46, 30, 20, 190)   ; C_UMBER, fainter: the backing of an icon nothing links to
%define TIP_RANK    RGBA(170, 255, 170, 255)    ; tooltip: "Rank r/m" of a node that has a rank
%define TIP_HINT    RGBA(255, 210, 120, 255)    ; tooltip: what is missing, or how to bind it

; ---- geometry (GUI units) -----------------------------------------------------------------
%define WEB_VX      20                  ; the grimoire's web viewport: x, y, and the margins that
%define WEB_VY      34                  ; leave it ui_w - 40 wide and ui_h - 76 high
%define WEB_VR      20                  ; right edge = ui_w - WEB_VR
%define WEB_VB      42                  ; bottom edge = ui_h - WEB_VB
%define WEB_CELL1   28                  ; units per web cell at zoom 1 ...
%define WEB_CELL0   8                   ; ... and at zoom 0 (the whole web, +-WEB_EXTENT / 8 cells, fits the viewport)
%define WEB_DRAG    3                   ; units of travel that turn a press on a node into a drag
%define DRAG_NONE   0                   ; web_drag: nothing pressed, panning, a press waiting on a node,
%define DRAG_PAN    1                   ; a press on a node that moved too far to be a click
%define DRAG_NODE   2
%define DRAG_CANCEL 3

%define SH_LW       156                 ; character sheet, an open book: left page (title, attributes, vitals) ...
%define SH_RW       166                 ; ... right page (the stats by section) ...
%define SH_H        224                 ; ... both this high
%define SH_TITLEW   144                 ; widest title drawn at scale 2
%define SH_TEXTW    144                 ; widest stat line a row holds (pen advance)
%define SH_BAND     RGBA(110, 84, 58, 28) ; every other stat row

%define SH_OFFENSE  0xF0                ; sheet_order entries beyond the stat ids: group headers, end
%define SH_DEFENSE  0xF1
%define SH_UTILITY  0xF2
%define SH_END      0xFF

%define TR_W        220                 ; trade panel: TR_BASE + TR_ROW per offer high (225 for 10)
%define TR_TOP      11                  ; ... its first row this far under the page top (the ribbon hangs above)
%define TR_BASE     15
%define TR_ROW      21
%define DL_W        260                 ; elder and faction leader panel
%define DL_H        144
%define TB_W        260                 ; shrine panel
%define TB_H        150
%define TB_BTN_W    116                 ; its tribute buttons, in two columns
%define TB_ROW_SIZE 24                  ; one tribute_rows entry

%define TIP_MAXW    172                 ; tooltips wrap here

section .rodata
align 4
attr_tiles:     db TILE_ATTR_STR, TILE_ATTR_DEX, TILE_ATTR_INT, TILE_ATTR_VIT
f_click:        dd 0.6                  ; click volume, as ui.asm's buttons
sheet_tab_geom: db 4, 56, 60, 56, 116, 46     ; the section tabs: x in the page, width (the labels are 49, 49, 40 wide)
web_dims_tab:   db 3, 7, 5, 10, 11, 22, 14, 28  ; web_dims: pick half, frame size by zoom * 2 + path
web_label_dy:   db 17, 17, -25, -25, -25       ; web_draw_compass, by archetype - 1: the name's y from its path node centre
                                                ; (centred on the node; below it for the Warrior and the Mage, above for the others)
ability_binds:  db BIND_ABILITY1, BIND_ABILITY2, BIND_ABILITY3, BIND_ABILITY4   ; bind of bar slot 0..3
align 4
web_edge_cols:  dd C_EDGE_LOCKED, C_INK, C_GOLD_DEEP      ; edges: no end ranked, one end, both ends

; the stat list in display order: group header markers and stat ids
sheet_order:
    db SH_OFFENSE, STAT_MELEE_DMG, STAT_RANGED_DMG, STAT_SPELL_DMG, STAT_GUN_DMG, STAT_ALL_DMG, STAT_WEAPON_DMG
    db STAT_CRIT_CHANCE, STAT_CRIT_DMG, STAT_ATTACK_SPEED, STAT_RELOAD_SPEED
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
s_colon_sp:     db ": ", 0
s_per_rank:     db " per rank", 0
s_keystone:     db " (Keystone)", 0
s_needs_level: db "Needs level ", 0
s_not_linked:  db "Learn a linked skill first", 0
s_press:       db "Press ", 0
s_place:       db " to place ", 0
s_on_bar:      db " on your bar", 0
s_rank:        db "Rank ", 0
s_grimoire:    db "Grimoire", 0
s_wheel_hint:  db "Wheel: zoom  Drag: move", 0
s_tab_char:    db "Tab: Character", 0
s_tab_grimoire: db "Tab: Grimoire", 0
s_character:   db "Character", 0

s_offense:      db "Offense", 0
s_defense:      db "Defense", 0
s_utility:      db "Utility", 0
s_v_health:     db "Health", 0
s_v_armor:      db "Armor", 0
s_armor_mid:    db " (-", 0
s_armor_close:  db "%)", 0
s_v_hit:        db "Hit", 0
s_v_crit:       db "Crit", 0
s_v_attacks:    db "Attacks", 0
s_level:        db "Level ", 0
s_wheel_tab:    db "Wheel: more  Tab: Grimoire", 0
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
s_respec:       db "Respec: ", 0
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
s_merchant_sfx: db " Merchant", 0
s_decline:      db "Decline", 0
s_ev_l1_camp:   db "Raiders are coming for our camp.", 0
s_ev_l1_site:   db "Our camp is under threat.", 0
s_ev_l1_village: db "The village is under threat.", 0
s_ev_l1_caravan: db "Escort my caravan to safety.", 0
s_ev_l1_road:   db "Escort my caravan along the road.", 0
s_ev_l2_camp:   db "Hold them off for ", 0
s_ev_l2_site:   db "Help us hold it for ", 0
s_ev_l2_expect: db "Expect ", 0
s_ev_waves:     db " waves.", 0
s_ev_ambushes:  db " ambushes on the way.", 0
s_ev_reward:    db "Reward: +", 0
s_ev_reward_sfx: db " standing, loot", 0

align 8
leader_greetings: dq s_greet_neutral, s_greet_friendly, s_greet_allied    ; by tier from Neutral up
; the offer screen's lines by EVK_* (0 = none): line one, the start of line two and its end after the count
ev_line1:       dq 0, s_ev_l1_camp, s_ev_l1_site, s_ev_l1_caravan, s_ev_l1_road
ev_line2a:      dq 0, s_ev_l2_camp, s_ev_l2_site, s_ev_l2_expect, s_ev_l2_expect
ev_line2b:      dq 0, s_ev_waves, s_ev_waves, s_ev_ambushes, s_ev_ambushes
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
sheet_tab:      resd 1                  ; its section: 0 offense, 1 defense, 2 utility
sheet_hover:    resd 1                  ; the attribute card under the mouse, or -1
sheet_sec:      resb 32                 ; the stat ids of the section being drawn (sheet_section)
hdr_buf:        resb 64                 ; "<title> - Level N" / "<Faction> Leader" / "Wanted: <item>"
pts_buf:        resb 32                 ; "Points: N" / "Attribute points: N"
coin_buf:       resb 32                 ; "Coins: N" / "Progress: p/c" / "Standing: N (Tier)" / counts / summary lines
fmt_buf:        resb 48                 ; one formatted stat
sheet_rows:     resb 64                 ; the stat list's visible rows (sheet_build)
tip_buf:        resb 256                ; skill tooltip text
tip_hint:       resb 128                ; ... and its hint (what is missing, or the keys to bind it)
tip_row:        resb 128                ; one wrapped tooltip row
row_buf:        resb 128                ; one wrapped row of "Rivals: ..." / "Champion: ..."
web_ox:         resd 1                  ; screen position of web cell (0, 0)
web_oy:         resd 1
web_zoom:       resd 1                  ; 1 = cells of 28 units, 0 = cells of 8
web_init:       resd 1                  ; the origin was set (first open of the session)
web_hover:      resd 1                  ; the node under the mouse that is drawn, or -1
web_drag:       resd 1                  ; DRAG_*
web_px:         resd 1                  ; where the button went down
web_py:         resd 1
web_lx:         resd 1                  ; the mouse of the last panning frame
web_ly:         resd 1
web_pressnode:  resd 1                  ; the node the press landed on
alignb 8
tip_paras:      resq 4                  ; tooltip_wrapped's paragraphs: name, what it does, rank, hint ...
tip_cols:       resd 4                  ; ... and their colours
tip_desc:       resb 128                ; "<stat value> per rank"
tip_rank:       resb 24                 ; "Rank r/m"

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
%macro TXTL 6                           ; label, xreg, xoff, yreg, yoff, rgba (1x ink, left aligned)
    lea     rdi, [%1]
    lea     esi, [%2 + %3]
    lea     edx, [%4 + %5]
    mov     ecx, %6
    mov     r8d, 1
    call    ui_text_ink
%endmacro
%macro TXTC 6                           ; label, xreg, xoff, yreg, yoff, rgba (1x ink, centred on x)
    lea     rdi, [%1]
    lea     esi, [%2 + %3]
    lea     edx, [%4 + %5]
    mov     ecx, %6
    mov     r8d, 1
    call    ui_text_ink_centered
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

; panel_begin(edi w, esi h, rdx title): a dimmer over the screen, then a w x h parchment page centred on it with
; the ribbon `title` hanging 7 units over its top (origin kept in s_px / s_py; y at least 7 so that the ribbon
; stays on the screen)
panel_begin:
    ENTER_FRAME 8
    mov     ebx, edi
    mov     r12d, esi
    mov     r13, rdx
    mov     eax, [ui_w]
    sub     eax, ebx
    sar     eax, 1
    mov     [s_px], eax
    mov     eax, [ui_h]
    sub     eax, r12d
    sar     eax, 1
    mov     ecx, 7
    cmp     eax, ecx
    cmovl   eax, ecx
    mov     [s_py], eax
    xor     edi, edi
    xor     esi, esi
    mov     edx, [ui_w]
    mov     ecx, [ui_h]
    mov     r8d, C_DIM
    call    ui_rect
    mov     edi, [s_px]
    mov     esi, [s_py]
    mov     edx, ebx
    mov     ecx, r12d
    call    ui_panel
    mov     rdi, r13
    mov     esi, ebx
    shr     esi, 1
    add     esi, [s_px]
    mov     edx, [s_py]
    sub     edx, 7
    call    ui_ribbon
    LEAVE_FRAME 8

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
; 1x shadowed paragraph word wrapped to maxw, left aligned at x, rows 11 units apart (the tooltip's pitch)
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
    add     r14d, 11
    jmp     .row
.done:
    mov     eax, r14d
    LEAVE_FRAME 8

; tooltip_wrapped(rdi paras qword[n], rsi cols dword[n], edx n): a NINE_TOOLTIP panel at the mouse, right of it or
; left of it when that would run off the screen, holding n paragraphs, each word wrapped at TIP_MAXW (and at the
; screen width) in its own colour, rows 11 units apart, a 4-unit pad; an empty paragraph takes no row.
; Locals: [rsp] panel x, [rsp+4] y, [rsp+8] w, [rsp+12] h, [rsp+16] rows in all, [rsp+20] widest row,
; [rsp+24] y of the next row
; ebx = paragraph, r12 = paras, r13 = cols, r14d = n, r15d = wrap width
tooltip_wrapped:
    ENTER_FRAME 40
    mov     r12, rdi
    mov     r13, rsi
    mov     r14d, edx
    mov     r15d, TIP_MAXW
    mov     eax, [ui_w]
    sub     eax, 12
    cmp     eax, r15d
    cmovl   r15d, eax
    mov     dword [rsp + 16], 0
    mov     dword [rsp + 20], 0
    xor     ebx, ebx
.measure:
    mov     rdi, [r12 + rbx*8]
    mov     esi, r15d
    call    text_extent
    add     [rsp + 16], eax
    cmp     edx, [rsp + 20]
    jbe     .measured
    mov     [rsp + 20], edx
.measured:
    inc     ebx
    cmp     ebx, r14d
    jb      .measure
    mov     eax, [rsp + 16]
    test    eax, eax
    jz      .ret
    imul    eax, eax, 11
    add     eax, 5
    mov     [rsp + 12], eax
    mov     eax, [rsp + 20]
    add     eax, 8
    mov     [rsp + 8], eax
    mov     ecx, [ui_mx]                ; x = mx + 12, or left of the mouse when that runs off the screen
    add     ecx, 12
    lea     edx, [rcx + rax]
    cmp     edx, [ui_w]
    jle     .x_set
    mov     ecx, [ui_mx]
    sub     ecx, 12
    sub     ecx, eax
.x_set:
    xor     eax, eax
    test    ecx, ecx
    cmovs   ecx, eax
    mov     [rsp], ecx
    mov     ecx, [ui_my]                ; y = my - 12, kept on the screen
    sub     ecx, 12
    mov     eax, [ui_h]
    sub     eax, [rsp + 12]
    cmp     ecx, eax
    cmovg   ecx, eax
    xor     eax, eax
    test    ecx, ecx
    cmovs   ecx, eax
    mov     [rsp + 4], ecx
    mov     edi, NINE_TOOLTIP
    mov     esi, [rsp]
    mov     edx, [rsp + 4]
    mov     ecx, [rsp + 8]
    mov     r8d, [rsp + 12]
    call    ui_nine
    mov     eax, [rsp + 4]
    add     eax, 4
    mov     [rsp + 24], eax
    xor     ebx, ebx
.draw:
    mov     rdi, [r12 + rbx*8]
    mov     esi, r15d
    mov     edx, [rsp]
    add     edx, 4
    mov     ecx, [rsp + 24]
    mov     r8d, [r13 + rbx*4]
    call    text_rows
    mov     [rsp + 24], eax
    inc     ebx
    cmp     ebx, r14d
    jb      .draw
.ret:
    LEAVE_FRAME 40

; ---- the grimoire: header and shared helpers ---------------------------------------------------

; screen_header(rsi points label, edx points, ecx panel width): the header line of the page whose origin is
; s_px / s_py: "<rpg_title> - Level N" in rubric ink at (px + 8, py + 9) and "<label><points>" right aligned
; to end at px + width - 8, in ink (soft while there are no points).
; Locals: [rsp] points, [rsp+4] panel width
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
    lea     rdi, [hdr_buf]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 9]
    mov     ecx, C_RUBRIC
    mov     r8d, 1
    call    ui_text_ink
    lea     r15, [pts_buf]
    APPP    r14
    APPN    dword [rsp]
    mov     byte [r15], 0
    lea     rdi, [pts_buf]
    mov     esi, 1
    call    ui_text_width
    mov     esi, [rsp + 4]
    lea     esi, [r12 + rsi - 8 + 1]    ; right aligned: the ink ends at px + width - 8
    sub     esi, eax
    mov     ecx, C_INK_SOFT
    mov     eax, C_INK
    cmp     dword [rsp], 0
    cmovg   ecx, eax
    lea     rdi, [pts_buf]
    lea     edx, [r13 + 9]
    mov     r8d, 1
    call    ui_text_ink
    LEAVE_FRAME 24

; ---- the grimoire: the skill web ---------------------------------------------------------------
; One web of 110 nodes (rpg.asm), each at a cell in 1/8 cell (WEB_SUB) around the compass, none further
; than WEB_EXTENT from it. web_ox / web_oy is the screen position of cell (0, 0), a cell is 28 GUI units
; wide at zoom 1 and 8 at zoom 0, where the whole web fits the viewport. The web is drawn over the open
; book and clipped to the viewport (ui_clip); only a mouse inside the viewport hovers or presses a node.

; web_node_xy(edi node, esi zoom) -> eax dx, edx dy: the node's cell (the signed bytes of its WEBNODE, in
; 1/8 cell) times the cell size, 28 at zoom 1 and 8 at zoom 0, shifted right by 3 (arithmetic: rounds
; towards minus infinity) = the node centre minus the web origin; 0, 0 for a node that does not exist
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
    sar     ecx, 3                      ; WEB_SUB
    sar     edx, 3
.none:
    mov     eax, ecx
    ret

; web_dims(edi node, esi zoom) -> eax half (the pick half-size), edx frame size: 11 / 22 for an
; ordinary node and 14 / 28 for a path node at zoom 1, 3 / 7 and 5 / 10 at zoom 0 (the pick box covers
; the frame and no two pick boxes of the web overlap; leaf but for rpg_web_node)
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

; web_centre(edi node) -> eax x, edx y: where the node's centre is on the screen now
web_centre:
    sub     rsp, 8
    mov     esi, [web_zoom]
    call    web_node_xy
    add     eax, [web_ox]
    add     edx, [web_oy]
    add     rsp, 8
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

; web_clamp(): keep the origin where at least one cell of the web (nodes up to WEB_EXTENT / 8 cells away)
; is inside the viewport: ox in [VX - m, right edge + m], oy likewise, m = (WEB_EXTENT - WEB_SUB) / 8
; cells = 220 units at zoom 1, 63 at zoom 0 (leaf)
web_clamp:
    mov     ecx, WEB_CELL0
    mov     eax, WEB_CELL1
    cmp     dword [web_zoom], 0
    cmovne  ecx, eax
    imul    ecx, ecx, WEB_EXTENT - WEB_SUB
    sar     ecx, 3                      ; WEB_SUB
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

; web_input(): hover, pan, click and the ability keys. web_hover = the node under the mouse, or -1; only a mouse
; inside the viewport hovers or presses anything. A press on the viewport outside any node starts a pan (the
; origin follows the mouse until the button is up); a press on a node waits for the release: under WEB_DRAG units
; of travel spends a point there (rpg_spend), more cancels (neither pans nor spends). While a node that teaches a
; learned ability is hovered, an ability key binds it to that bar slot.
; ebx = hovered node, r15d = 1 when the mouse is inside the viewport, r12d = ability, r13d = key, r14d = slot
web_input:
    ENTER_FRAME 24
    mov     dword [web_hover], -1
    mov     ebx, -1
    xor     r15d, r15d
    mov     edi, WEB_VX
    mov     esi, WEB_VY
    mov     edx, [ui_w]
    sub     edx, WEB_VX + WEB_VR
    mov     ecx, [ui_h]
    sub     ecx, WEB_VY + WEB_VB
    call    hit
    test    eax, eax
    jz      .picked
    mov     r15d, 1
    mov     edi, [ui_mx]
    mov     esi, [ui_my]
    mov     edx, [web_ox]
    mov     ecx, [web_oy]
    mov     r8d, [web_zoom]
    call    web_pick
    mov     ebx, eax
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
    test    r15d, r15d
    jz      .state                      ; a press outside the viewport pans nothing
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

; web_draw_edges(): every pair of web_edges as a line (ui_line) between the two node centres: gold when both
; ends have a rank, ink when one has, faint when none; 2 units wide at zoom 1, 1 at zoom 0. The viewport clip
; cuts what runs out. Locals: [rsp] x0, [rsp+4] y0, [rsp+8] x1, [rsp+12] y1
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
    call    ui_line
    inc     ebx
    jmp     .edge
.ret:
    LEAVE_FRAME 24

; web_draw_compass(): TILE_COMPASS on the origin (one 16 x 16 tile drawn 32 x 32 units, 16 x 16 at zoom 0) and,
; at zoom 1, the archetype names in rubric ink centred on their path nodes, below the Warrior's and the Mage's
; and above the others (web_label_dy).
; Locals: [rsp] name
; ebx = archetype, r12d = compass size, r13d / r14d = path node centre
web_draw_compass:
    ENTER_FRAME 24
    mov     r12d, 16
    mov     eax, 32
    cmp     dword [web_zoom], 0
    cmovne  r12d, eax
    mov     eax, r12d
    shr     eax, 1
    mov     esi, [web_ox]
    sub     esi, eax
    mov     edx, [web_oy]
    sub     edx, eax
    mov     edi, TILE_COMPASS
    mov     ecx, r12d
    mov     r8d, WHITE
    call    ui_tile_icon
    cmp     dword [web_zoom], 0
    je      .ret
    mov     ebx, 1
.arch:
    lea     edi, [rbx - 1]
    call    web_centre
    mov     r13d, eax
    mov     r14d, edx
    mov     edi, ebx
    call    rpg_archetype_name
    mov     [rsp], rax
    mov     rdi, rax
    mov     esi, 1
    call    ui_text_width
    dec     eax                         ; the ink: drop the trailing 1-unit gap
    shr     eax, 1
    mov     esi, r13d
    sub     esi, eax                    ; centred on the node ...
    lea     rcx, [web_label_dy]
    movsx   edx, byte [rcx + rbx - 1]
    add     edx, r14d                   ; ... below it or above it
    mov     rdi, [rsp]
    mov     ecx, C_RUBRIC
    mov     r8d, 1
    call    ui_text_ink
    inc     ebx
    cmp     ebx, NUM_ARCHETYPES
    jbe     .arch
.ret:
    LEAVE_FRAME 24

; web_draw_node(edi node): the node's frame by kind (NINE_NODE_STAT + kind: stat, ability, keystone, path), 22 x 22
; (path 28 x 28) with its 16 x 16 icon at zoom 1, 7 x 7 (path 10 x 10) without one at zoom 0, centred on its cell. A
; node that no ranked node links to is drawn faint (frame and icon tinted TINT_FAINT); a node a point could go into
; or that has a rank gets the 1-unit progress ring of web_ring just outside its frame (no number: the ring is the
; rank, filled clockwise in proportion to rank / max). The viewport clip cuts what runs out.
; Locals: [rsp] rank, [rsp+4] tint, [rsp+8] size, [rsp+12] frame x, [rsp+16] frame y, [rsp+20] centre x,
; [rsp+24] centre y, [rsp+28] reachable
; ebx = node, r12 = WEBNODE*
web_draw_node:
    ENTER_FRAME 40
    mov     ebx, edi
    call    rpg_web_node
    mov     r12, rax
    mov     edi, ebx
    call    rpg_rank
    mov     [rsp], eax
    mov     edi, ebx
    call    rpg_reachable
    mov     [rsp + 28], eax
    mov     ecx, WHITE
    mov     edx, TINT_FAINT
    mov     esi, [rsp]
    or      esi, eax                    ; zero when the node has no rank and nothing links to it
    cmovz   ecx, edx
    mov     [rsp + 4], ecx
    mov     edi, ebx
    call    web_centre
    mov     [rsp + 20], eax
    mov     [rsp + 24], edx
    mov     edi, ebx
    mov     esi, [web_zoom]
    call    web_dims
    mov     [rsp + 8], edx
    shr     edx, 1
    mov     eax, [rsp + 20]
    sub     eax, edx
    mov     [rsp + 12], eax
    mov     eax, [rsp + 24]
    sub     eax, edx
    mov     [rsp + 16], eax
    mov     eax, [rsp]
    or      eax, [rsp + 28]
    jz      .frame                      ; unranked and unreachable: no ring
    cmp     dword [rsp], 0
    jne     .ring
    cmp     dword [web_zoom], 0
    je      .frame                      ; zoom 0: no empty rings, they crowd the 8-unit cells
.ring:
    mov     edi, [rsp + 12]
    mov     esi, [rsp + 16]
    mov     edx, [rsp + 8]
    mov     ecx, [rsp]
    movzx   r8d, byte [r12 + WEBNODE.max]
    call    web_ring
.frame:
    movzx   edi, byte [r12 + WEBNODE.kind]
    add     edi, NINE_NODE_STAT
    mov     esi, [rsp + 12]
    mov     edx, [rsp + 16]
    mov     ecx, [rsp + 8]
    mov     r8d, ecx
    mov     r9d, [rsp + 4]
    call    ui_nine_tint
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
    call    rpg_path_tile
    mov     edi, eax
.draw_icon:
    mov     [rsp + 32], edi
    mov     edi, [rsp + 20]             ; umber backing: light icons (bolts, flames) vanish on parchment
    sub     edi, 8
    mov     esi, [rsp + 24]
    sub     esi, 8
    mov     edx, 16
    mov     ecx, 16
    mov     r8d, C_UMBER
    cmp     dword [rsp + 4], WHITE
    je      .back
    mov     r8d, ICON_BACK_FAINT
.back:
    call    ui_rect
    mov     edi, [rsp + 32]
    mov     esi, [rsp + 20]
    sub     esi, 8
    mov     edx, [rsp + 24]
    sub     edx, 8
    mov     ecx, 16
    mov     r8d, [rsp + 4]
    call    ui_tile_icon
.ret:
    LEAVE_FRAME 40

; web_ring(edi x, esi y, edx size, ecx rank, r8d max): the progress ring of a node whose frame is size x size at
; (x, y): a 1-unit track just outside the frame (C_LOCKED) and over it the first rank / max of the ring's
; perimeter in C_GOLD_DEEP, running clockwise from the top left corner (a one-rank node is lit all round, a
; five-rank node by fifths). max is at least 1.
; Locals: [rsp] x, [rsp+4] y, [rsp+8] size, [rsp+12] rank, [rsp+16] max, [rsp+20] lit units, [rsp+24] edge
; ebx / r12d = ring x / y, r13d = ring side, r14d = lit units of the current edge (at most side - 1)
web_ring:
    ENTER_FRAME 40
    mov     [rsp], edi
    mov     [rsp + 4], esi
    mov     [rsp + 8], edx
    mov     [rsp + 12], ecx
    mov     [rsp + 16], r8d
    lea     ebx, [rdi - 1]
    lea     r12d, [rsi - 1]
    lea     r13d, [rdx + 2]
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, r13d
    mov     r8d, C_LOCKED
    cmp     dword [rsp + 12], 0
    jne     .track
    mov     r8d, RGBA(150, 100, 20, 190)    ; nothing yet: the "a point can go here" ring, gold
.track:
    call    ui_frame
    lea     eax, [r13 - 1]
    shl     eax, 2                      ; perimeter units
    imul    eax, [rsp + 12]
    xor     edx, edx
    div     dword [rsp + 16]
    mov     [rsp + 20], eax
    mov     dword [rsp + 24], 0
.edge:
    mov     eax, [rsp + 20]
    mov     ecx, [rsp + 24]
    lea     edx, [r13 - 1]
    imul    ecx, edx
    sub     eax, ecx                    ; units left for this edge and the ones after it
    jle     .next
    cmp     eax, edx
    cmova   eax, edx
    mov     r14d, eax
    mov     ecx, [rsp + 24]
    cmp     ecx, 1
    je      .e1
    cmp     ecx, 2
    je      .e2
    cmp     ecx, 3
    je      .e3
    mov     edi, ebx                    ; top edge, left to right
    mov     esi, r12d
    mov     edx, r14d
    mov     ecx, 1
    jmp     .draw
.e1:                                    ; right edge, downwards
    lea     edi, [rbx + r13 - 1]
    mov     esi, r12d
    mov     edx, 1
    mov     ecx, r14d
    jmp     .draw
.e2:                                    ; bottom edge, right to left
    lea     edi, [rbx + r13]
    sub     edi, r14d
    lea     esi, [r12 + r13 - 1]
    mov     edx, r14d
    mov     ecx, 1
    jmp     .draw
.e3:                                    ; left edge, upwards
    mov     edi, ebx
    lea     esi, [r12 + r13]
    sub     esi, r14d
    mov     edx, 1
    mov     ecx, r14d
.draw:
    mov     r8d, C_GOLD_DEEP
    call    ui_rect
.next:
    inc     dword [rsp + 24]
    cmp     dword [rsp + 24], 4
    jb      .edge
    LEAVE_FRAME 40

; web_tooltip(edi node): the hovered node's tooltip at the mouse (tooltip_wrapped): its name in gold (" (Keystone)"
; after a keystone's), what it does (the stat's value per rank, or the node's description), "Rank r/m" (green once
; the node has a rank) and a hint in orange: "Needs level N" while the character is below the node's level, else
; "Learn a linked skill first" when no node linked to it has a rank, else for a learned ability "Press
; Q/G/V/X to place <ability> on your bar" (the four ability keys).
; Locals: [rsp] the rank, then the node's level, then its ability
; ebx = node, r12d = key index, r14 = WEBNODE*, r15 = write cursor
web_tooltip:
    ENTER_FRAME 24
    mov     ebx, edi
    call    rpg_web_node
    test    rax, rax
    jz      .ret
    mov     r14, rax
    lea     r15, [tip_buf]              ; the name
    APPP    [r14 + WEBNODE.name]
    cmp     byte [r14 + WEBNODE.kind], NODE_KEYSTONE
    jne     .name_done
    APPZ    s_keystone
.name_done:
    mov     byte [r15], 0
    lea     rax, [tip_buf]
    mov     [tip_paras], rax
    mov     dword [tip_cols], C_GOLD_TEXT
    lea     rax, [s_empty]              ; what it does
    cmp     byte [r14 + WEBNODE.kind], NODE_STAT
    jne     .desc
    movzx   edi, byte [r14 + WEBNODE.stat]      ; a stat node has no text of its own
    mov     esi, [r14 + WEBNODE.value]
    lea     rdx, [fmt_buf]
    call    rpg_format_stat
    lea     r15, [tip_desc]
    APPP    rax
    APPZ    s_per_rank
    mov     byte [r15], 0
    lea     rax, [tip_desc]
    jmp     .desc_set
.desc:
    mov     rcx, [r14 + WEBNODE.desc]
    test    rcx, rcx
    cmovnz  rax, rcx
.desc_set:
    mov     [tip_paras + 8], rax
    mov     dword [tip_cols + 4], C_CREAM
    lea     r15, [tip_rank]             ; "Rank r/m"
    APPZ    s_rank
    mov     edi, ebx
    call    rpg_rank
    mov     [rsp], eax
    APPN    eax
    APPZ    s_slash
    movzx   eax, byte [r14 + WEBNODE.max]
    APPN    eax
    mov     byte [r15], 0
    lea     rax, [tip_rank]
    mov     [tip_paras + 16], rax
    mov     ecx, C_CREAM
    mov     eax, TIP_RANK
    cmp     dword [rsp], 0
    cmovg   ecx, eax
    mov     [tip_cols + 8], ecx
    lea     r15, [tip_hint]             ; empty unless something is missing or to be told
    mov     byte [r15], 0
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
    mov     [rsp], eax
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
    mov     edi, [rsp]
    call    rpg_ability_info
    APPP    [rax + ABILINFO.name]
    APPZ    s_on_bar
.hint_done:
    mov     byte [r15], 0
    lea     rax, [tip_hint]
    mov     [tip_paras + 24], rax
    mov     dword [tip_cols + 12], TIP_HINT
    lea     rdi, [tip_paras]
    lea     rsi, [tip_cols]
    mov     edx, 4
    call    tooltip_wrapped
.ret:
    LEAVE_FRAME 24

; web_book(): the grimoire's page: a dimmer over the world, one wide leather-bound page (ui_book with no left page, so
; no spine cuts the web), 14 units in from the screen edge, the ribbon "Grimoire" hanging over its top and the header
; line (screen_header, s_px / s_py = 16 / 13 so that its text lands at x 24, y 22 and ends at ui_w - 24).
web_book:
    ENTER_FRAME 8
    xor     edi, edi
    xor     esi, esi
    mov     edx, [ui_w]
    mov     ecx, [ui_h]
    mov     r8d, C_DIM
    call    ui_rect
    xor     edx, edx                    ; no left page: no spine across the web
    mov     ecx, [ui_w]
    sub     ecx, 28
    mov     r8d, [ui_h]
    sub     r8d, 28
    mov     edi, 14
    mov     esi, 14
    call    ui_book
    lea     rdi, [s_grimoire]
    mov     esi, [ui_w]
    shr     esi, 1
    mov     edx, 7
    call    ui_ribbon
    mov     dword [s_px], 16
    mov     dword [s_py], 13
    call    rpg_points
    mov     edx, eax
    lea     rsi, [s_points]
    mov     ecx, [ui_w]
    sub     ecx, 32
    call    screen_header
    LEAVE_FRAME 8

; web_hint(rdi s, esi y, edx left limit): the hint s in soft ink, right aligned to end at ui_w - 20 unless it
; would start left of the limit. ebx = s, r12d = y, r13d = limit
web_hint:
    ENTER_FRAME 8
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    mov     esi, 1
    call    ui_text_width
    mov     esi, [ui_w]
    sub     esi, 19                     ; the ink ends at ui_w - 20 (the pen adds 1)
    sub     esi, eax
    cmp     esi, r13d
    jl      .ret
    mov     rdi, rbx
    mov     edx, r12d
    mov     ecx, C_INK_SOFT
    mov     r8d, 1
    call    ui_text_ink
.ret:
    LEAVE_FRAME 8

; web_footer(): at y = ui_h - 38 the "Respec: N coins" button (124 wide at x 24; enabled with N coins in the pack
; and a rank somewhere; a click calls rpg_respec), the four ability slots (NINE_RUNE 20 x 20, step 23, centred on
; ui_w / 2 but never under the button) with the bound ability's icon, a wash while hovered and the slot's key on a
; note above it; a right click on a slot empties it; and, right of the slots where they fit, the hints "Wheel:
; zoom  Drag: move" and "Tab: Character" (the only way to the character sheet).
; Locals: [rsp] respec cost, [rsp+4] y, [rsp+8] x of slot 0, [rsp+12] note x, [rsp+16..39] key name
; ebx = slot, r12d = enabled / slot hovered, r13d / r14d = slot x / y, r15d = note width
web_footer:
    ENTER_FRAME 40
    mov     eax, [ui_h]
    sub     eax, 38
    mov     [rsp + 4], eax
    call    rpg_respec_cost
    mov     [rsp], eax
    lea     r15, [coin_buf]
    APPZ    s_respec
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
    mov     ecx, 124
    mov     r8d, r12d
    call    ui_button
    test    eax, eax
    jz      .slots
    call    rpg_respec
.slots:
    mov     eax, [ui_w]
    shr     eax, 1
    sub     eax, 44                     ; the 89 units of four slots centred on ui_w / 2
    mov     ecx, 152
    cmp     eax, ecx
    cmovl   eax, ecx                    ; ... but right of the button
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
    jz      .draw
    cmp     dword [ui_input + UIINPUT.rmb_pressed], 0
    je      .draw
    mov     edi, ebx
    mov     esi, -1
    call    rpg_bar_set                 ; a right click empties the slot
.draw:
    mov     edi, NINE_RUNE
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, 20
    mov     r8d, 20
    call    ui_nine
    mov     edi, ebx
    call    rpg_bar_ability
    test    eax, eax
    js      .wash
    mov     edi, eax
    call    rpg_ability_tile
    mov     edi, eax
    lea     esi, [r13 + 2]
    lea     edx, [r14 + 2]
    mov     ecx, 16
    mov     r8d, WHITE
    call    ui_tile_icon
.wash:
    test    r12d, r12d
    jz      .label
    mov     edi, r13d
    mov     esi, r14d
    mov     edx, 20
    mov     ecx, 20
    mov     r8d, C_HOVER
    call    ui_rect
.label:
    lea     rax, [ability_binds]
    movzx   eax, byte [rax + rbx]
    lea     rcx, [settings + SETTINGS.keys]
    mov     edi, [rcx + rax*4]
    lea     rsi, [rsp + 16]
    call    key_name
    mov     byte [rsp + 19], 0          ; at most three characters fit over a slot
    lea     rdi, [rsp + 16]
    mov     esi, 1
    call    ui_text_width
    test    eax, eax
    jz      .next                       ; an unbound key has no note
    lea     r15d, [rax + 3]             ; note width: the ink + 4
    mov     esi, r15d
    shr     esi, 1
    neg     esi
    lea     esi, [rsi + r13 + 10]       ; centred over the slot
    mov     [rsp + 12], esi
    mov     edi, NINE_NOTE
    lea     edx, [r14 - 9]
    mov     ecx, r15d
    mov     r8d, 9
    call    ui_nine
    lea     rdi, [rsp + 16]
    mov     esi, [rsp + 12]
    add     esi, 2
    lea     edx, [r14 - 8]
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
.next:
    inc     ebx
    cmp     ebx, NUM_ABILITY_SLOTS
    jb      .slot
    mov     r13d, [rsp + 8]
    add     r13d, 90                    ; the hints start right of the slots
    lea     rdi, [s_wheel_hint]
    mov     esi, [rsp + 4]
    inc     esi
    mov     edx, r13d
    call    web_hint
    lea     rdi, [s_tab_char]
    mov     esi, [rsp + 4]
    add     esi, 11
    mov     edx, r13d
    call    web_hint
    LEAVE_FRAME 40

; screen_skills(): the grimoire - an open book over the world with the skill web (see above) on it:
; header, the web in its viewport (clipped), the footer and a tooltip for the hovered node. A click on a node
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
    call    web_book
    mov     edi, WEB_VX                 ; the web is clipped to its viewport; the draw calls up to ui_unclip
    mov     esi, WEB_VY                 ; never leave early, so the clip is always lifted
    mov     edx, [ui_w]
    sub     edx, WEB_VX + WEB_VR
    mov     ecx, [ui_h]
    sub     ecx, WEB_VY + WEB_VB
    call    ui_clip
    call    web_draw_edges
    call    web_draw_compass
    xor     ebx, ebx
.node:
    mov     edi, ebx
    call    web_draw_node
    inc     ebx
    cmp     ebx, NUM_WEB_NODES
    jb      .node
    call    ui_unclip
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

; sheet_section(edi tab, esi rows) -> eax n: the stat ids of group `tab` (0 offense, 1 defense, 2 utility)
; among the first `rows` entries of sheet_rows, in order, in sheet_sec (leaf)
sheet_section:
    lea     rdx, [sheet_rows]
    lea     r8, [sheet_sec]
    xor     ecx, ecx                    ; row read
    xor     eax, eax                    ; ids written
    mov     r9d, -1                     ; group of the rows being read
.row:
    cmp     ecx, esi
    jae     .done
    movzx   r10d, byte [rdx + rcx]
    inc     ecx
    cmp     r10d, SH_OFFENSE
    jb      .stat
    lea     r9d, [r10 - SH_OFFENSE]     ; a group header
    jmp     .row
.stat:
    cmp     r9d, edi
    jne     .row
    mov     [r8 + rax], r10b
    inc     eax
    jmp     .row
.done:
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

; plus_box(edi x, esi y, edx enabled) -> eax 1 when clicked: an 11 x 11 button (a parchment plate, brighter
; under the mouse, greyed when disabled) with a "+" in ink (the click sound is played by whatever the click does)
plus_box:
    ENTER_FRAME 24
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edx
    xor     ebx, ebx                    ; hovered (a disabled button never is)
    test    r14d, r14d
    jz      .draw
    mov     edx, 11
    mov     ecx, 11
    call    hit
    mov     ebx, eax
.draw:
    mov     edi, NINE_BUTTON_OFF
    mov     eax, NINE_BUTTON
    mov     ecx, NINE_BUTTON_HOT
    test    r14d, r14d
    cmovnz  edi, eax
    test    ebx, ebx
    cmovnz  edi, ecx
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, 11
    mov     r8d, 11
    call    ui_nine
    lea     rdi, [s_plus]
    lea     esi, [r12 + 5]
    lea     edx, [r13 + 2]
    mov     ecx, C_INK
    mov     eax, C_INK_SOFT
    test    r14d, r14d
    cmovz   ecx, eax
    mov     r8d, 1
    call    ui_text_ink_centered
    xor     eax, eax
    test    ebx, ebx
    jz      .ret
    cmp     dword [ui_input + UIINPUT.lmb_pressed], 0
    setne   al
.ret:
    LEAVE_FRAME 24

; vital_row(edi y, esi icon tile or -1, rdx label, rcx value): one line of the character sheet's dark
; vitals plate: the icon (a gold bullet for -1) at px + 13, the label in cream, the value in gold ending
; at px + 142
vital_row:
    ENTER_FRAME 8
    mov     ebx, edi
    mov     r12, rdx
    mov     r13, rcx
    mov     r14d, [s_px]
    test    esi, esi
    js      .bullet
    mov     edi, esi
    lea     esi, [r14 + 13]
    mov     edx, ebx
    call    ui_icon9
    jmp     .label
.bullet:
    lea     edi, [r14 + 16]
    lea     esi, [rbx + 3]
    mov     edx, 3
    mov     ecx, 3
    mov     r8d, C_GOLD_TEXT
    call    ui_rect
.label:
    mov     rdi, r12
    lea     esi, [r14 + 25]
    lea     edx, [rbx + 1]
    mov     ecx, C_CREAM
    mov     r8d, 1
    call    ui_text
    mov     rdi, r13
    mov     esi, 1
    call    ui_text_width
    lea     esi, [r14 + 143]
    sub     esi, eax
    mov     rdi, r13
    lea     edx, [rbx + 1]
    mov     ecx, C_GOLD_TEXT
    mov     r8d, 1
    call    ui_text
    LEAVE_FRAME 8

; sheet_left(): the character sheet's left page (origin s_px / s_py): the title (rpg_title, large when it fits),
; "Level N", the attribute points, four attribute cards (icon, name, points spent, a "+" box that spends a point,
; Shift up to five) and the dark vitals plate (health, armor with the damage it stops, the held weapon's hit,
; crit hit and attack rate). sheet_hover = the attribute whose card is under the mouse, else -1.
; Locals: [rsp] points in the attribute, [rsp+4] attribute points left, [rsp+12] combat_weapon_preview {hit,
; crit hit, attacks per 10 s}
sheet_left:
    ENTER_FRAME 40
    mov     r12d, [s_px]
    mov     r13d, [s_py]
    mov     dword [sheet_hover], -1
    call    rpg_title
    mov     r14, rax
    mov     rdi, r14
    mov     esi, 2
    call    ui_text_width
    mov     ebx, 2                      ; scale 2 when the title fits the page, else 1 a little lower
    mov     r15d, 8
    cmp     eax, SH_TITLEW
    jbe     .title
    mov     ebx, 1
    mov     r15d, 12
.title:
    mov     rdi, r14
    lea     esi, [r12 + SH_LW / 2]
    lea     edx, [r13 + r15]
    mov     ecx, C_RUBRIC
    mov     r8d, ebx
    call    ui_text_ink_centered
    lea     r15, [hdr_buf]
    APPZ    s_level
    call    rpg_level
    APPN    eax
    mov     byte [r15], 0
    TXTC    hdr_buf, r12, SH_LW / 2, r13, 26, C_INK
    call    rpg_attr_points
    mov     [rsp + 4], eax
    lea     r15, [pts_buf]
    APPZ    s_attr_points
    APPN    dword [rsp + 4]
    mov     byte [r15], 0
    lea     rdi, [pts_buf]
    lea     esi, [r12 + SH_LW / 2]
    lea     edx, [r13 + 38]
    mov     ecx, C_INK_SOFT
    mov     eax, C_RUBRIC
    cmp     dword [rsp + 4], 0
    cmovg   ecx, eax                    ; red while there are points to spend
    mov     r8d, 1
    call    ui_text_ink_centered
    xor     ebx, ebx
.attr:
    imul    r14d, ebx, 25
    lea     r14d, [r14 + r13 + 50]      ; card y
    lea     edi, [r12 + 8]
    mov     esi, r14d
    mov     edx, 140
    mov     ecx, 22
    call    hit
    test    eax, eax
    jz      .card
    mov     [sheet_hover], ebx
.card:
    mov     edi, NINE_SLOT
    lea     esi, [r12 + 8]
    mov     edx, r14d
    mov     ecx, 140
    mov     r8d, 22
    call    ui_nine
    cmp     [sheet_hover], ebx
    jne     .icon
    lea     edi, [r12 + 9]              ; the hovered card is washed
    lea     esi, [r14 + 1]
    mov     edx, 138
    mov     ecx, 20
    mov     r8d, C_HOVER
    call    ui_rect
.icon:
    lea     rax, [attr_tiles]
    movzx   edi, byte [rax + rbx]
    lea     esi, [r12 + 11]
    lea     edx, [r14 + 3]
    mov     ecx, 16
    mov     r8d, WHITE
    call    ui_tile_icon
    mov     edi, ebx
    call    rpg_attr_info
    mov     rdi, rax
    lea     esi, [r12 + 31]
    lea     edx, [r14 + 7]
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
    mov     edi, ebx
    call    rpg_attr
    mov     [rsp], eax
    mov     edi, eax
    lea     rsi, [coin_buf]
    call    i32_to_str
    mov     byte [rax], 0
    lea     rdi, [coin_buf]
    mov     esi, 1
    call    ui_text_width
    lea     esi, [r12 + 127]            ; right aligned: the ink ends at px + 126
    sub     esi, eax
    lea     rdi, [coin_buf]
    lea     edx, [r14 + 7]
    mov     ecx, C_INK_SOFT
    mov     eax, C_RUBRIC
    cmp     dword [rsp], 0
    cmovg   ecx, eax
    mov     r8d, 1
    call    ui_text_ink
    lea     edi, [r12 + 131]
    lea     esi, [r14 + 5]
    xor     edx, edx
    cmp     dword [rsp + 4], 0
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
    ; ---- the vitals plate
    mov     edi, NINE_TOOLTIP
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 152]
    mov     ecx, 140
    mov     r8d, 64
    call    ui_nine
    lea     rdi, [rsp + 12]
    call    combat_weapon_preview
    lea     r15, [coin_buf]
    APPN    dword [surv + SURVIVAL.health]
    APPZ    s_slash
    APPN    dword [surv_max_health]
    mov     byte [r15], 0
    lea     edi, [r13 + 158]
    mov     esi, TILE_HEART_FULL
    lea     rdx, [s_v_health]
    lea     rcx, [coin_buf]
    call    vital_row
    call    armor_effective             ; what the damage formula uses: at most 20, 4% each
    mov     ebx, eax
    lea     r15, [coin_buf]
    APPN    ebx
    APPZ    s_armor_mid
    lea     eax, [rbx*4]
    APPN    eax
    APPZ    s_armor_close
    mov     byte [r15], 0
    lea     edi, [r13 + 169]
    mov     esi, TILE_ARMOR_FULL
    lea     rdx, [s_v_armor]
    lea     rcx, [coin_buf]
    call    vital_row
    lea     r15, [coin_buf]
    APPN    dword [rsp + 12]
    mov     byte [r15], 0
    lea     edi, [r13 + 180]
    mov     esi, -1
    lea     rdx, [s_v_hit]
    lea     rcx, [coin_buf]
    call    vital_row
    lea     r15, [coin_buf]
    APPN    dword [rsp + 16]
    mov     byte [r15], 0
    lea     edi, [r13 + 191]
    mov     esi, -1
    lea     rdx, [s_v_crit]
    lea     rcx, [coin_buf]
    call    vital_row
    mov     eax, [rsp + 20]
    xor     edx, edx
    mov     ecx, 10
    div     ecx
    mov     r14d, eax                   ; whole attacks per second
    mov     ebx, edx                    ; and the tenth
    lea     r15, [coin_buf]
    APPN    r14d
    mov     byte [r15], '.'
    add     bl, '0'
    mov     [r15 + 1], bl
    add     r15, 2
    APPZ    s_per_s
    mov     byte [r15], 0
    lea     edi, [r13 + 202]
    mov     esi, -1
    lea     rdx, [s_v_attacks]
    lea     rcx, [coin_buf]
    call    vital_row
    LEAVE_FRAME 40

; sheet_right(): the character sheet's right page: three section tabs (Offense, Defense, Utility, touching; the choice is
; sheet_tab) over a gold rule, then the stats of that section in banded rows with a gold bullet, 14 units apart
; (12 and the wheel scrolls when there are more than 12). A line too wide for the page is shortened to
; "<label>: <number>" when that is shorter. The footer is the Tab hint.
; Locals: [rsp] row in the window, [rsp+4] first row, [rsp+8] y, [rsp+12] stat, [rsp+16] width of its text
; ebx = rows in the section, r12d = page x, r13d = page y, r14d = pitch, r15d = rows in the window
sheet_right:
    ENTER_FRAME 40
    mov     r12d, [s_px]
    add     r12d, SH_LW + 4
    mov     r13d, [s_py]
    xor     ebx, ebx
.tab:
    lea     rax, [sheet_tab_geom]
    movzx   r14d, byte [rax + rbx*2]
    add     r14d, r12d                  ; tab x
    movzx   r15d, byte [rax + rbx*2 + 1]    ; tab width
    mov     edi, r14d
    lea     esi, [r13 + 6]
    mov     edx, r15d
    mov     ecx, 16
    call    hit
    test    eax, eax
    jz      .tab_draw
    cmp     dword [ui_input + UIINPUT.lmb_pressed], 0
    je      .tab_draw
    cmp     [sheet_tab], ebx
    je      .tab_draw
    mov     [sheet_tab], ebx
    mov     dword [sheet_scroll], 0
    movss   xmm0, [f_click]
    mov     edi, SND_CLICK
    call    audio_play
.tab_draw:
    mov     edi, NINE_BUTTON
    mov     eax, NINE_BUTTON_HOT
    cmp     [sheet_tab], ebx
    cmove   edi, eax
    mov     esi, r14d
    lea     edx, [r13 + 6]
    mov     ecx, r15d
    mov     r8d, 16
    call    ui_nine
    lea     rax, [sheet_head]
    mov     rdi, [rax + rbx*8]
    mov     esi, r15d
    shr     esi, 1
    add     esi, r14d
    lea     edx, [r13 + 11]
    mov     ecx, C_INK
    mov     eax, C_RUBRIC
    cmp     [sheet_tab], ebx
    cmove   ecx, eax
    mov     r8d, 1
    call    ui_text_ink_centered
    inc     ebx
    cmp     ebx, 3
    jb      .tab
    lea     edi, [r12 + 6]
    lea     esi, [r13 + 26]
    mov     edx, SH_RW - 12
    mov     ecx, 1
    mov     r8d, C_GOLD_DEEP
    call    ui_rect
    call    sheet_build
    mov     esi, eax
    mov     edi, [sheet_tab]
    call    sheet_section
    mov     ebx, eax                    ; rows in the section
    mov     r14d, 14                    ; up to 12 rows: 14 apart, all shown
    mov     r15d, ebx
    cmp     ebx, 12
    jbe     .pitch
    mov     r14d, 12                    ; more: 12 apart, a window of 14 that the wheel scrolls
    mov     r15d, 14
.pitch:
    lea     edi, [r12 + 6]
    lea     esi, [r13 + 30]
    mov     edx, SH_RW - 12
    mov     ecx, 180
    call    hit
    mov     ecx, [sheet_scroll]
    test    eax, eax
    jz      .clamp
    sub     ecx, [ui_input + UIINPUT.scroll]    ; wheel up scrolls towards the top
.clamp:
    mov     eax, ebx
    sub     eax, r15d                   ; the largest first row: the window stays full
    xor     edx, edx
    test    eax, eax
    cmovs   eax, edx
    cmp     ecx, eax
    cmovg   ecx, eax
    test    ecx, ecx
    cmovs   ecx, edx
    mov     [sheet_scroll], ecx
    mov     [rsp + 4], ecx
    mov     dword [rsp], 0
.row:
    mov     eax, [rsp]
    cmp     eax, r15d
    jae     .rows_done
    add     eax, [rsp + 4]
    cmp     eax, ebx
    jae     .rows_done
    lea     rdx, [sheet_sec]
    movzx   eax, byte [rdx + rax]
    mov     [rsp + 12], eax
    mov     eax, [rsp]
    imul    eax, r14d
    lea     eax, [rax + r13 + 33]
    mov     [rsp + 8], eax              ; y
    test    byte [rsp], 1
    jnz     .no_band
    lea     edi, [r12 + 6]
    mov     esi, [rsp + 8]
    sub     esi, 3
    mov     edx, SH_RW - 12
    mov     ecx, 13
    mov     r8d, SH_BAND
    call    ui_rect
.no_band:
    lea     edi, [r12 + 10]
    mov     esi, [rsp + 8]
    add     esi, 2
    mov     edx, 3
    mov     ecx, 3
    mov     r8d, C_GOLD_DEEP
    call    ui_rect
    mov     edi, [rsp + 12]
    lea     rax, [rpg_stats]
    mov     esi, [rax + rdi*4]
    lea     rdx, [fmt_buf]
    call    rpg_format_stat
    lea     rdi, [fmt_buf]
    mov     esi, 1
    call    ui_text_width
    mov     [rsp + 16], eax             ; the sentence's width
    lea     rdi, [fmt_buf]
    cmp     eax, SH_TEXTW
    jbe     .fits
    mov     edi, [rsp + 12]             ; too wide: "<label>: <number>" if that is shorter
    lea     rsi, [fmt_buf]
    lea     rdx, [coin_buf]
    call    stat_compact
    lea     rdi, [coin_buf]
    mov     esi, 1
    call    ui_text_width
    lea     rdi, [fmt_buf]
    cmp     eax, [rsp + 16]
    jae     .fits
    lea     rdi, [coin_buf]
.fits:
    lea     esi, [r12 + 18]
    mov     edx, [rsp + 8]
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
    inc     dword [rsp]
    jmp     .row
.rows_done:
    lea     rdi, [s_tab_grimoire]
    cmp     ebx, r15d
    jbe     .footer
    lea     rdi, [s_wheel_tab]          ; the list scrolls
.footer:
    lea     esi, [r12 + SH_RW / 2]
    lea     edx, [r13 + SH_H - 12]
    mov     ecx, C_INK_SOFT
    mov     r8d, 1
    call    ui_text_ink_centered
    LEAVE_FRAME 40

; screen_character(): the character sheet, an open book: the left page holds the title, attribute cards and the
; vitals plate (sheet_left), the right page the stats by section (sheet_right); Tab opens the grimoire. The stats
; are recomputed first: gear changes them. Hovering an attribute card explains what a point does.
screen_character:
    ENTER_FRAME 24
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
    mov     eax, [ui_w]
    sub     eax, SH_LW + 4 + SH_RW
    sar     eax, 1
    mov     ecx, 6
    cmp     eax, ecx
    cmovl   eax, ecx
    mov     [s_px], eax
    mov     eax, [ui_h]
    sub     eax, SH_H
    sar     eax, 1
    mov     ecx, 8
    cmp     eax, ecx
    cmovl   eax, ecx
    mov     [s_py], eax                 ; the ribbon hangs 7 units over the page
    xor     edi, edi
    xor     esi, esi
    mov     edx, [ui_w]
    mov     ecx, [ui_h]
    mov     r8d, C_DIM
    call    ui_rect
    mov     edi, [s_px]
    mov     esi, [s_py]
    mov     edx, SH_LW
    mov     ecx, SH_RW
    mov     r8d, SH_H
    call    ui_book
    lea     rdi, [s_character]
    mov     esi, [s_px]
    add     esi, (SH_LW + 4 + SH_RW) / 2
    mov     edx, [s_py]
    sub     edx, 7
    call    ui_ribbon
    call    sheet_left
    call    sheet_right
    mov     eax, [sheet_hover]
    test    eax, eax
    js      .ret
    mov     edi, eax
    call    rpg_attr_desc
    mov     [tip_paras], rax
    mov     dword [tip_cols], C_CREAM
    lea     rdi, [tip_paras]
    lea     rsi, [tip_cols]
    mov     edx, 1
    call    tooltip_wrapped
.ret:
    LEAVE_FRAME 24

; ---- traders -------------------------------------------------------------------------------------

; screen_trade(): the current trader's trade_count offers (trade_open picked the table) as "give -> get" rows
; with a Trade button each (enabled while trade_can), on a page under a ribbon with the trade_title; the page
; is as high as its rows. The coins in the pack hang on a note over the page's bottom right edge. Hovering an
; icon names the item, or for a gear offer says what it rolls.
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
    mov     rdx, [trade_title]
    call    panel_begin
    mov     r12d, [s_px]
    mov     r13d, [s_py]
    mov     dword [rsp], 0
    lea     r15, [coin_buf]             ; the note: "Coins: N", 4 units over the page's bottom edge
    APPZ    s_coins
    mov     edi, GOLD_COIN
    call    inv_count
    APPN    eax
    mov     byte [r15], 0
    lea     rdi, [coin_buf]
    mov     esi, 1
    call    ui_text_width
    lea     ebx, [rax + 3]              ; note width: the ink + 4
    lea     r15d, [r12 + TR_W - 12]
    sub     r15d, ebx                   ; note x
    imul    r14d, [trade_count], TR_ROW
    lea     r14d, [r14 + r13 + TR_BASE - 4] ; note y
    mov     edi, NINE_NOTE
    mov     esi, r15d
    mov     edx, r14d
    mov     ecx, ebx
    mov     r8d, 9
    call    ui_nine
    lea     rdi, [coin_buf]
    lea     esi, [r15 + 2]
    lea     edx, [r14 + 1]
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
    xor     ebx, ebx
.row:
    imul    eax, ebx, TR_ROW
    lea     r14d, [rax + r13 + TR_TOP]  ; row y
    mov     edi, ebx
    call    trade_offer
    mov     r15, rax
    mov     edi, ebx
    call    trade_can
    mov     [rsp + 4], eax
    mov     edi, NINE_SLOT              ; row backing
    lea     esi, [r12 + 4]
    mov     edx, r14d
    mov     ecx, TR_W - 8
    mov     r8d, 20
    call    ui_nine
    mov     edi, [r15 + TRADEOFFER.give]        ; give: icon, then the count (rubric when it cannot be paid)
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
    mov     ecx, C_INK
    mov     eax, C_RUBRIC
    cmp     dword [rsp + 4], 0
    cmove   ecx, eax
    mov     r8d, 1
    call    ui_text_ink
    TXTL    s_arrow, r12, 66, r14, 6, C_INK_SOFT
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
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
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
; Leave, on a page under the ribbon "Elder"; when the chain is finished a farewell.
; Locals: [rsp] quest accepted, [rsp+4] progress
screen_dialog:
    ENTER_FRAME 24
    call    close_check
    test    eax, eax
    jnz     .ret
    mov     edi, DL_W
    mov     esi, DL_H
    lea     rdx, [s_elder]
    call    panel_begin
    mov     r12d, [s_px]
    mov     r13d, [s_py]
    call    quests_current
    test    rax, rax
    jnz     .quest
    TXTC    s_saved, r12, DL_W / 2, r13, 40, C_INK
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
    mov     ecx, C_RUBRIC
    mov     r8d, 1
    call    ui_text_ink
    mov     rdi, [r14 + QUESTINFO.line1]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 40]
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
    mov     rdi, [r14 + QUESTINFO.line2]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 52]
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
    cmp     dword [rsp], 0
    je      .buttons
    lea     r15, [coin_buf]             ; "Progress: p/c", in rubric once it is done
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
    mov     ecx, C_INK
    mov     eax, C_RUBRIC
    mov     edx, [rsp + 4]
    cmp     edx, [r14 + QUESTINFO.count]
    cmovae  ecx, eax
    lea     rdi, [coin_buf]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 68]
    mov     r8d, 1
    call    ui_text_ink
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

; draw_standing(edi faction, esi x, edx y): "Standing: N (Tier)" at (x, y) in the colour of the faction's tier, on a
; dark plate (NINE_TOOLTIP, 4 units of padding) so that the light tier colours read on parchment.
; ebx = faction, r12d = x, r13d = y, r14d = the tier colour, r15 = write cursor into coin_buf
draw_standing:
    ENTER_FRAME 8
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
    mov     r14d, eax
    lea     rdi, [coin_buf]
    mov     esi, 1
    call    ui_text_width
    mov     edi, NINE_TOOLTIP
    lea     esi, [r12 - 4]
    lea     edx, [r13 - 4]
    lea     ecx, [rax + 8]
    mov     r8d, 16
    call    ui_nine
    lea     rdi, [coin_buf]
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, r14d
    mov     r8d, 1
    call    ui_text
    LEAVE_FRAME 8

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
    mov     r14d, [screen_faction]
    lea     r15, [hdr_buf]              ; "<Faction> Leader": the ribbon over the page
    lea     rax, [faction_names]
    APPP    [rax + r14*8]
    APPZ    s_leader_sfx
    mov     byte [r15], 0
    mov     edi, DL_W
    mov     esi, DL_H
    lea     rdx, [hdr_buf]
    call    panel_begin
    mov     r12d, [s_px]
    mov     r13d, [s_py]
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
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
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
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
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
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
    BTN     s_leave, r12, (DL_W - 100) / 2, r13, 118, 100
    test    eax, eax
    jz      .ret
    mov     edi, ST_PLAYING
    call    app_goto
.ret:
    LEAVE_FRAME 24

; screen_event(): ST_EVENT, the offer of the folk in game_open_npc (it has FF_HELP): "<Faction> Leader" (camps and
; sites) or "<Faction> Merchant" (caravans) over what it asks, what it promises, and Accept / Decline. Accept starts the
; event (events_accept; a guest asks the host with IA_EVENT_ACCEPT) and both close the screen. The screen closes at once
; when the folk is gone, no longer offers, or events_offer_kind knows no event for it.
; rbx = the mob, r14d = its faction, r15 = write cursor, r12d, r13d = panel origin; frame: [rsp] EVK_*, [rsp+4] the slot
screen_event:
    ENTER_FRAME 24
    call    close_check
    test    eax, eax
    jnz     .ret
    mov     eax, [game_open_npc]
    mov     [rsp + 4], eax
    cmp     eax, MAX_MOBS
    jae     .close
    imul    eax, eax, MOB_size
    lea     rbx, [mobs]
    add     rbx, rax
    cmp     dword [rbx + MOB.type], MOB_FOLK
    jne     .close
    test    byte [rbx + MOB.fflags], FF_HELP
    jz      .close
    mov     edi, [rsp + 4]
    call    events_offer_kind
    mov     [rsp], eax
    sub     eax, EVK_CAMP
    cmp     eax, EVK_ROAD - EVK_CAMP
    ja      .close
    movzx   r14d, byte [rbx + MOB.faction]
    cmp     r14d, NUM_FACTIONS
    jb      .faction_ok
    xor     r14d, r14d
.faction_ok:
    lea     r15, [hdr_buf]              ; "<Faction> Leader" / "<Faction> Merchant"
    lea     rax, [faction_names]
    APPP    [rax + r14*8]
    lea     rsi, [s_leader_sfx]
    lea     rdx, [s_merchant_sfx]
    cmp     dword [rsp], EVK_CARAVAN
    cmovae  rsi, rdx
    mov     rdi, r15
    call    str_append
    mov     r15, rax
    mov     byte [r15], 0
    mov     edi, DL_W
    mov     esi, DL_H
    lea     rdx, [hdr_buf]
    call    panel_begin
    mov     r12d, [s_px]
    mov     r13d, [s_py]
    mov     eax, [rsp]                  ; line one: what it asks
    lea     rcx, [ev_line1]
    mov     rdi, [rcx + rax*8]
    lea     rdx, [s_ev_l1_village]
    test    r14d, r14d
    jnz     .line1
    cmp     eax, EVK_SITE
    cmove   rdi, rdx                    ; the village elder's own words
.line1:
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 24]
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
    lea     r15, [row_buf]              ; line two: "Hold them off for 3 waves." / "Expect 2 ambushes on the way."
    mov     eax, [rsp]
    lea     rcx, [ev_line2a]
    APPP    [rcx + rax*8]
    mov     eax, [rsp]
    lea     rcx, [ev_kind_waves]
    movzx   eax, byte [rcx + rax]
    APPN    eax
    mov     eax, [rsp]
    lea     rcx, [ev_line2b]
    APPP    [rcx + rax*8]
    mov     byte [r15], 0
    lea     rdi, [row_buf]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 40]
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
    lea     r15, [row_buf]              ; the promise: "Reward: +40 standing, loot"
    APPZ    s_ev_reward
    mov     eax, [rsp]
    lea     rcx, [ev_kind_rep]
    movzx   eax, byte [rcx + rax]
    APPN    eax
    APPZ    s_ev_reward_sfx
    mov     byte [r15], 0
    lea     rdi, [row_buf]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 64]
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
    BTN     s_accept, r12, 16, r13, 118, 100
    test    eax, eax
    jz      .decline
    mov     edi, [rsp + 4]
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .accept_here
    mov     esi, IA_EVENT_ACCEPT        ; a guest asks the host to start it
    call    net_interact_out
    jmp     .close
.accept_here:
    call    events_accept
    jmp     .close
.decline:
    BTN     s_decline, r12, DL_W - 116, r13, 118, 100
    test    eax, eax
    jz      .ret
.close:
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
    mov     r14d, [screen_faction]
    lea     r15, [hdr_buf]              ; "<Faction> Shrine": the ribbon over the page
    lea     rax, [faction_names]
    APPP    [rax + r14*8]
    APPZ    s_shrine_sfx
    mov     byte [r15], 0
    mov     edi, TB_W
    mov     esi, TB_H
    lea     rdx, [hdr_buf]
    call    panel_begin
    mov     r12d, [s_px]
    mov     r13d, [s_py]
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
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
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
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
    BTN     s_leave, r12, (TB_W - 100) / 2, r13, 126, 100
    test    eax, eax
    jz      .banner
    mov     edi, ST_PLAYING
    call    app_goto
    jmp     .ret
.banner:
    lea     edi, [r13 - 29]             ; a tier change shows its banner (faction_add), which this
    mov     eax, 2                      ; panel covers in the middle of the screen: above the panel
    cmp     edi, eax
    cmovl   edi, eax
    call    hud_banner_paint
.ret:
    LEAVE_FRAME 24
