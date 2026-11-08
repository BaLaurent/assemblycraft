; rpgscreens.asm - the RPG screens: class selection, skill tree, merchant trade and the
; elder's quest dialog. Immediate mode like invscreen.asm / menus.asm: every screen_*() runs
; once per frame after ui_begin (app.asm draw_frame), reads ui_input / frame_input and changes
; state with app_goto. A screen that acts returns at once, so one click never reaches two
; widgets.
;  - ST_SKILLS, ST_TRADE and ST_DIALOG close (back to ST_PLAYING) on Escape, the inventory
;    key or the skills key. The first frame after a state change only clears app_entered:
;    the key edge that opened the screen is still set in that frame and must not close it.
;  - ST_CLASS cannot be closed: Escape saves and quits to the title, a card's button picks
;    the class (rpg_set_class) and starts playing.
; All progression data (class cards, node texts, branch names, quests, trades) comes from
; rpg.asm / quests.asm (Module API); the only text owned here is the UI wording.
%include "common.inc"
default rel

global screen_class, screen_skills, screen_trade, screen_dialog

extern ui_w, ui_h, ui_mx, ui_my, ui_input, frame_input, settings, app_entered
extern ui_rect, ui_frame, ui_panel, ui_text, ui_text_width, ui_text_centered
extern ui_button, ui_item_icon, ui_tile_icon, ui_tooltip
extern app_goto, app_quit_to_title, key_name
extern item_names, inv_count, i32_to_str, str_append
extern rpg_state, rpg_class, rpg_level, rpg_points, rpg_xp_need, rpg_rank
extern rpg_can_spend, rpg_spend, rpg_set_class, rpg_class_info, rpg_node_info
extern rpg_ability_info, rpg_ability_unlocked, rpg_branch_name
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

; ---- geometry (GUI units) -----------------------------------------------------------------
%define CARD_W      100                 ; class cards
%define CARD_H      150
%define CARD_Y      50
%define CARD_STEP   105
%define CARD_X0     210                 ; card 0 is at cx - CARD_X0

; The skill panel is wider than the plan's 260 so the longest ability footer
; ("Q: Shadowstep  G: Smoke Bomb  V: Blade Dance", 281 units) fits on one line; everything the
; plan positions relative to the 260 panel is shifted right by half the difference.
%define SK_W        292
%define SK_H        210
%define SK_SHIFT    ((SK_W - 260) / 2)
%define SK_NX       (38 + SK_SHIFT)     ; node column 0 x offset (columns are 80 apart)
%define SK_NY       44                  ; node row 0 y offset (rows are 40 apart)
%define SK_CONN_X   (49 + SK_SHIFT)
%define SK_BRANCH_X (50 + SK_SHIFT)
%define FOOT_GAP    8                   ; between the three ability hints

%define TR_W        220                 ; merchant panel
%define TR_H        200
%define DL_W        260                 ; elder panel
%define DL_H        120

%define TIP_MAXW    320                 ; skill tooltip wraps here
%define HINT_COL    RGBA(255, 150, 110, 255)

section .rodata
align 4
tier_req:       dd 1, 4, 9, 15          ; level needed by tier t (skill-tree rule, rpg.asm)

s_choose_class: db "Choose your class", 0
s_choose:       db "Choose", 0
s_level_sep:    db " - Level ", 0
s_points:       db "Points: ", 0
s_slash:        db "/", 0
s_space:        db " ", 0
s_colon_sp:     db ": ", 0
s_per_rank:     db " per rank", 0
s_needs_level:  db "- needs level ", 0
s_needs_prev:   db "- needs previous skill", 0

s_merchant:     db "Merchant", 0
s_coins:        db "Coins: ", 0
s_trade:        db "Trade", 0
s_arrow:        db "->", 0

s_elder:        db "Elder", 0
s_saved:        db "The realm is saved. Rest, hero.", 0
s_farewell:     db "Farewell", 0
s_progress:     db "Progress: ", 0
s_accept:       db "Accept", 0
s_leave:        db "Leave", 0
s_complete:     db "Complete", 0

section .bss
alignb 8
s_px:           resd 1                  ; panel origin of the screen being drawn
s_py:           resd 1
hdr_buf:        resb 64                 ; "<class> - Level N"
pts_buf:        resb 32                 ; "Points: N"
coin_buf:       resb 32                 ; "Coins: N" / "Progress: p/c" / counts
rank_buf:       resb 16                 ; "r/m" on a skill node
seg_buf:        resb 3 * 64             ; "<key>: <ability>" footer hints
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

; screen_skills(): header, xp bar, three branches of four nodes, the ability hints and a
; tooltip for the hovered node. A click on a node spends a skill point (rpg_spend).
; Locals: [rsp] hovered node or -1, [rsp+4] class, [rsp+8] points, [rsp+16] can_spend result
; of the node being drawn, [rsp+20] its border colour, [rsp+24] node x, [rsp+28] node y,
; [rsp+32] its rank, [rsp+40..48] widths of the three ability hints, [rsp+52] tier,
; [rsp+56] level required by the tier
screen_skills:
    ENTER_FRAME 72
    call    close_check
    test    eax, eax
    jnz     .ret
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
    ; ---- hovered node (column = dx / 80, tier = dy / 40, each node 24 wide) and the click
    mov     dword [rsp], -1
    mov     eax, [ui_mx]
    sub     eax, r12d
    sub     eax, SK_NX
    js      .hover_done
    xor     edx, edx
    mov     ecx, 80
    div     ecx
    cmp     edx, 24
    jae     .hover_done
    cmp     eax, 2
    ja      .hover_done
    mov     esi, eax                    ; column
    mov     eax, [ui_my]
    sub     eax, r13d
    sub     eax, SK_NY
    js      .hover_done
    xor     edx, edx
    mov     ecx, 40
    div     ecx
    cmp     edx, 24
    jae     .hover_done
    cmp     eax, 3
    ja      .hover_done
    lea     eax, [rax + rsi*4]          ; node = branch * 4 + tier
    mov     [rsp], eax
    cmp     dword [ui_input + UIINPUT.lmb_pressed], 0
    je      .hover_done
    mov     edi, eax
    call    rpg_spend
.hover_done:
    ; ---- header: "<class> - Level N" and "Points: N"
    lea     r15, [hdr_buf]
    mov     edi, [rsp + 4]
    call    rpg_class_info
    APPP    [rax + CLASSINFO.name]
    APPZ    s_level_sep
    call    rpg_level
    APPN    eax
    mov     byte [r15], 0
    TXTL    hdr_buf, r12, 8, r13, 6, WHITE
    lea     r15, [pts_buf]
    APPZ    s_points
    call    rpg_points
    mov     [rsp + 8], eax
    APPN    eax
    mov     byte [r15], 0
    lea     rdi, [pts_buf]
    mov     esi, 1
    call    ui_text_width
    lea     esi, [r12 + SK_W - 8 + 1]   ; right aligned at px + SK_W - 8
    sub     esi, eax
    mov     ecx, GREY
    mov     eax, GREEN
    cmp     dword [rsp + 8], 0
    cmovg   ecx, eax
    lea     rdi, [pts_buf]
    lea     edx, [r13 + 6]
    mov     r8d, 1
    call    ui_text
    ; ---- xp bar: full at the maximum level
    lea     edi, [r12 + 8]
    lea     esi, [r13 + 18]
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
    lea     esi, [r13 + 18]
    mov     edx, ecx
    mov     ecx, 3
    mov     r8d, XP_COL
    call    ui_rect
.xp_done:
    ; ---- branch names
    xor     ebx, ebx
.branch:
    mov     edi, [rsp + 4]
    mov     esi, ebx
    call    rpg_branch_name
    mov     rdi, rax
    imul    esi, ebx, 80
    lea     esi, [rsi + r12 + SK_BRANCH_X]
    lea     edx, [r13 + 28]
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
    and     eax, 3
    cmp     eax, 3
    je      .conn_next                  ; the last tier has nothing below it
    mov     edi, ebx
    call    rpg_rank
    mov     r8d, COL_LOCKED
    mov     edx, COL_SPEND
    test    eax, eax
    cmovnz  r8d, edx
    mov     eax, ebx
    shr     eax, 2
    imul    edi, eax, 80
    lea     edi, [rdi + r12 + SK_CONN_X]
    mov     eax, ebx
    and     eax, 3
    imul    esi, eax, 40
    lea     esi, [rsi + r13 + 24 + SK_NY]
    mov     edx, 2
    mov     ecx, 16
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
    shr     eax, 2
    imul    eax, eax, 80
    lea     eax, [rax + r12 + SK_NX]
    mov     [rsp + 24], eax
    mov     eax, ebx
    and     eax, 3
    imul    eax, eax, 40
    lea     eax, [rax + r13 + SK_NY]
    mov     [rsp + 28], eax
    ; border: maxed, ranked, spendable, locked (in that priority)
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
    ; icon: the stat's glyph, or for an ability node (stat = its slot) the class's ability icon
    movzx   eax, byte [r14 + NODEINFO.kind]
    test    eax, eax
    jnz     .ability_icon
    movzx   eax, byte [r14 + NODEINFO.stat]
    add     eax, TILE_STAT0
    jmp     .icon
.ability_icon:
    movzx   eax, byte [r14 + NODEINFO.stat]
    mov     ecx, [rsp + 4]
    dec     ecx
    lea     ecx, [rcx + rcx*2]
    lea     eax, [rax + rcx + TILE_ABILITY0]
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
    ; ---- footer: "<key>: <ability>" for the three slots, centred, locked ones grey
    xor     ebx, ebx
.seg:
    lea     rcx, [settings + SETTINGS.keys]
    lea     eax, [rbx + BIND_ABILITY1]
    mov     edi, [rcx + rax*4]
    imul    eax, ebx, 64
    lea     rsi, [seg_buf]
    add     rsi, rax
    call    key_name
    mov     r15, rax
    APPZ    s_colon_sp
    mov     edi, [rsp + 4]
    mov     esi, ebx
    call    rpg_ability_info
    APPP    [rax + ABILINFO.name]
    mov     byte [r15], 0
    imul    eax, ebx, 64
    lea     rdi, [seg_buf]
    add     rdi, rax
    mov     esi, 1
    call    ui_text_width
    mov     [rsp + 40 + rbx*4], eax
    inc     ebx
    cmp     ebx, 3
    jb      .seg
    mov     eax, [rsp + 40]
    add     eax, [rsp + 44]
    add     eax, [rsp + 48]
    sub     eax, 3                      ; trailing gaps
    add     eax, 2 * FOOT_GAP
    shr     eax, 1
    lea     r15d, [r12 + SK_W / 2]
    sub     r15d, eax                   ; x of the first hint
    xor     ebx, ebx
.fdraw:
    mov     edi, ebx
    call    rpg_ability_unlocked
    mov     ecx, GREY
    mov     edx, WHITE
    test    eax, eax
    cmovnz  ecx, edx
    imul    eax, ebx, 64
    lea     rdi, [seg_buf]
    add     rdi, rax
    mov     esi, r15d
    lea     edx, [r13 + 196]
    mov     r8d, 1
    call    ui_text
    lea     r15d, [r15 + rax + FOOT_GAP - 1]
    inc     ebx
    cmp     ebx, 3
    jb      .fdraw
    ; ---- tooltip: "<name> r/m: <desc>[ per rank][ - needs level N | - needs previous skill]"
    mov     eax, [rsp]
    test    eax, eax
    js      .ret
    mov     edi, [rsp + 4]
    mov     esi, eax
    call    rpg_node_info
    mov     r14, rax
    lea     r15, [tip_buf]
    APPP    [r14 + NODEINFO.name]
    APPZ    s_space
    mov     edi, [rsp]
    call    rpg_rank
    APPN    eax
    APPZ    s_slash
    movzx   eax, byte [r14 + NODEINFO.max]
    APPN    eax
    APPZ    s_colon_sp
    APPP    [r14 + NODEINFO.desc]
    cmp     byte [r14 + NODEINFO.kind], 0
    jne     .no_per_rank
    APPZ    s_per_rank
.no_per_rank:
    mov     byte [r15], 0
    lea     r15, [tip_hint]
    mov     byte [r15], 0               ; empty unless a requirement is missing
    mov     eax, [rsp]
    and     eax, 3
    mov     [rsp + 52], eax             ; tier
    lea     rcx, [tier_req]
    mov     eax, [rcx + rax*4]
    mov     [rsp + 56], eax             ; level the tier asks for
    call    rpg_level
    cmp     eax, [rsp + 56]
    jae     .level_ok
    APPZ    s_needs_level
    APPN    dword [rsp + 56]
    jmp     .hint_done
.level_ok:
    cmp     dword [rsp + 52], 0
    je      .hint_done
    mov     edi, [rsp]
    dec     edi                         ; the node above in the same branch
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
    LEAVE_FRAME 72

; ---- merchant ------------------------------------------------------------------------------------

; screen_trade(): the 8 trade offers as "give -> get" rows with a Trade button each (enabled
; while trade_can); hovering an icon names the item. Locals: [rsp] item id under the mouse
; (0 = none), [rsp+4] trade_can of the row
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
    lea     rcx, [item_names]
    mov     rdi, [rcx + rax*8]
    test    rdi, rdi
    jz      .ret
    call    ui_tooltip
.ret:
    LEAVE_FRAME 24

; ---- elder -----------------------------------------------------------------------------------------

; screen_dialog(): the current quest of the chain (rpg_state.quest) with Accept / Complete /
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
