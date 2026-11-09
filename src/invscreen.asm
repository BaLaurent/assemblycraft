; invscreen.asm - the inventory screens, drawn as an open grimoire: the survival inventory (the
; character page or the recipe book on the left, the 2x2 crafting grid and the satchel on the right),
; the creative item palette (the character page on the left), the 3x3 crafting-table screen, the
; furnace and the chest. Immediate mode: every frame draws the book and its slots, turns presses on
; hovered slots into inv_click calls, then draws the tooltip and the stack held on the cursor.
; The right page is PANEL_W x PANEL_H at (s_px, s_py): every cell coordinate of a screen is relative
; to it. The left page, BOOK_W wide and LEFT_SPAN left of the right one, is the character page
; (silhouette, armor, jewelry and hand cells, health and armor) or, on the crafting-table and furnace
; screens, the recipe book (recipebook.asm); the survival inventory shows either, chosen with the
; tabs above it. The tooltip of the recipe book's hovered entry (book_tip) takes the place of the
; slot tooltip.
; Slot references (inv_click): 0..35 slots, 36..44 grid cells, 45 result, 47..50 armor
; (all at inv + ref*4), 51.. cells of the open container (inv_container), 78..80 the jewelry cells
; (ring, ring, amulet; the character page). Gear changes the stats, so every inv_click that
; changed something is followed by rpg_recompute. A hovered stack shows item_tooltip's lines;
; with Shift held the equipped item of its kind is shown beside it.
%include "common.inc"
%include "theme.inc"
default rel

global screen_inventory, screen_crafting, screen_furnace, screen_chest

extern game_mode, frame_input, ui_input, inv, craft_size, inv_container
extern app_goto, app_entered
extern ui_w, ui_h, ui_mx, ui_my
extern ui_rect, ui_text, ui_text_width, ui_text_ink, ui_text_ink_centered
extern armor_effective
extern ui_slot, ui_item_icon, ui_tile_icon, ui_icon9, ui_nine, ui_book, ui_ribbon
extern ui_tooltip, ui_tooltip_lines
extern inv_click, inv_close_screen, inv_held, item_tooltip, gear_equipped_for, gear_stack_worn
extern rpg_recompute, rpg_title, rpg_level, rpg_stats, armor_points, surv, surv_max_health
extern item_max_stack, i32_to_str, str_append, audio_play
extern book_reset, book_draw, book_ghost_draw, book_tip

%define PANEL_W     176                 ; the right page
%define PANEL_H     166
%define PAL_VISIBLE 6
%define PAL_TRACK   (PAL_VISIBLE * 18)

%define BOOK_W      124                 ; the left page (recipebook.asm draws its page this wide)
%define LEFT_SPAN   128                 ; the left page and the 4-wide spine: s_px - LEFT_SPAN is its x
%define BOOK_MIN_W  316                 ; the whole book, cover included; a narrower screen gets no left page
%define BOOK_CRAFT  0                   ; recipe book kinds; screen_begin takes 1 + kind
%define BOOK_FURNACE 1
%define LEFT_CHARACTER 3                ; screen_begin's other left page: the character page

%define TAB_DY      -20                 ; the survival inventory's tabs: top, relative to the pages
%define TAB_H       16
%define TAB_CHAR_X  2                   ; x from the left page, and width
%define TAB_CHAR_W  70
%define TAB_REC_X   74
%define TAB_REC_W   52

%define CLOSE_INVENTORY 0               ; do_close / check_close screen kinds
%define CLOSE_CRAFTING  1
%define CLOSE_CONTAINER 2

section .rodata
align 4
f_click_vol:  dd 0.6
s_crafting:   db "Crafting", 0
s_creative:   db "Creative", 0
s_satchel:    db "Satchel", 0
s_hotbar:     db "Hotbar", 0
s_arrow:      db "->", 0
s_level:      db "Level ", 0
s_health:     db "Health ", 0
s_armor:      db "Armor ", 0
s_slash:      db "/", 0
s_in_hand:    db "In hand", 0
s_equipped:   db "Equipped", 0
s_tab_character: db "Character", 0
s_tab_recipes:   db "Recipes", 0
s_furnace:    db "Furnace", 0
s_chest:      db "Chest", 0

section .bss
alignb 8
hover_ptr:    resq 1                    ; ITEMSTACK under the mouse this frame, 0 = none
hover_note:   resq 1                    ; zstr tooltip of the display-only cell under the mouse, 0 = none
tip_lines:    resq 12                   ; item_tooltip lines of the hovered stack ...
tip_cols:     resd 12
cmp_lines:    resq 13                   ; ... and of the equipped one, under an "Equipped" line
cmp_cols:     resd 13
s_px:         resd 1                    ; the right page's origin in GUI units
s_py:         resd 1
s_left:       resd 1                    ; the left page screen_begin drew: 0 = none, else its left argument
inv_left:     resd 1                    ; the survival inventory's left page: 0 character, 1 recipes (kept)
show_counts:  resd 1                    ; draw stack counts on the slots
hover_pal:    resd 1                    ; the creative palette cell under the mouse: id | 1 << 8
pal_scroll:   resd 1                    ; creative palette: first visible row
palette_n:    resd 1                    ; entries in palette, 0 = not built yet
palette:      resb 256                  ; creative palette: every id with a max stack

section .text

; palette_build(): fill palette with every id 1..NUM_ITEMS-1 whose item_max_stack != 0
palette_build:
    xor     eax, eax                    ; count
    mov     ecx, 1
.l:
    cmp     byte [item_max_stack + rcx], 0
    je      .n
    mov     [palette + rax], cl
    inc     eax
.n:
    inc     ecx
    cmp     ecx, NUM_ITEMS
    jb      .l
    mov     [palette_n], eax
    ret

; caption(rdi s, esi x, edx y): a heading in rubric ink on a page
caption:
    mov     ecx, C_RUBRIC
    mov     r8d, 1
    jmp     ui_text_ink

; page_title(rdi s): the title of the right page, on a ribbon hanging over its top edge
page_title:
    mov     esi, [s_px]
    add     esi, PANEL_W / 2
    mov     edx, [s_py]
    sub     edx, 7
    jmp     ui_ribbon

; screen_begin(edi show_counts, esi left): reset per-frame state, draw the dimmer and the open book and,
; on its left page, left = LEFT_CHARACTER the character page, 1 + BOOK_CRAFT or 1 + BOOK_FURNACE the
; recipe book of that kind, 0 nothing (a single right page). The right page is at (s_px, s_py); with a
; left page the book is centred on the screen, cover included. A screen narrower than BOOK_MIN_W has no
; room for a left page and gets none: s_left = the page that was drawn.
screen_begin:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    xor     ebx, ebx
    cmp     dword [ui_w], BOOK_MIN_W
    jl      .have_left
    mov     ebx, esi
.have_left:
    mov     [s_left], ebx
    mov     [show_counts], edi
    mov     qword [hover_ptr], 0
    mov     qword [hover_note], 0
    mov     byte [book_tip], 0
    mov     eax, [ui_w]
    sub     eax, PANEL_W                ; a single page is centred
    xor     ecx, ecx
    test    ebx, ebx
    jz      .have_x
    sub     eax, BOOK_MIN_W - PANEL_W   ; the pair, with the cover
    mov     ecx, LEFT_SPAN
.have_x:
    sar     eax, 1
    add     eax, ecx
    mov     [s_px], eax
    mov     eax, [ui_h]
    sub     eax, PANEL_H
    sar     eax, 1
    mov     [s_py], eax
    xor     edi, edi
    xor     esi, esi
    mov     edx, [ui_w]
    mov     ecx, [ui_h]
    mov     r8d, C_DIM
    call    ui_rect
    mov     edi, [s_px]
    mov     esi, [s_py]
    xor     edx, edx                    ; no left page: the right page is at x
    mov     ecx, PANEL_W
    mov     r8d, PANEL_H
    test    ebx, ebx
    jz      .cover
    sub     edi, LEFT_SPAN
    mov     edx, BOOK_W
.cover:
    call    ui_book
    test    ebx, ebx
    jz      .done
    mov     edi, [s_px]
    sub     edi, LEFT_SPAN
    mov     esi, [s_py]
    cmp     ebx, LEFT_CHARACTER
    je      .character
    lea     edx, [rbx - 1]              ; the recipe book of that kind
    call    book_draw
    jmp     .done
.character:
    call    draw_character
.done:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; do_close(edi kind): give grid/cursor items back and return to the game. The creative
; inventory just drops the cursor; every other screen kind returns its items.
do_close:
    push    rbp
    mov     rbp, rsp
    cmp     edi, CLOSE_INVENTORY
    jne     .full
    cmp     dword [game_mode], MODE_CREATIVE
    jne     .full
    mov     dword [inv + INVENTORY.cursor], 0
    mov     dword [craft_size], 2
    jmp     .go
.full:
    call    inv_close_screen
.go:
    mov     edi, ST_PLAYING
    call    app_goto
    pop     rbp
    ret

; check_close(edi kind) -> eax 1 if the screen closed. The first frame after
; a state change only clears app_entered: the key edge that opened the screen is still
; set in that frame and must not close it again.
check_close:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
    cmp     dword [app_entered], 0
    je      .test
    mov     dword [app_entered], 0
    xor     eax, eax
    jmp     .ret
.test:
    cmp     dword [frame_input + FRAMEINPUT.inventory], 0
    jne     .close
    cmp     dword [ui_input + UIINPUT.escape], 0
    je      .no
.close:
    mov     edi, ebx
    call    do_close
    mov     eax, 1
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; slot_cell(rdi ITEMSTACK*, esi x, edx y, ecx ref): draw one slot, click it via inv_click
slot_cell:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12d, ecx
    mov     ecx, [show_counts]
    call    ui_slot
    test    eax, eax
    jz      .ret
    cmp     dword [ui_input + UIINPUT.lmb_pressed], 0
    je      .not_left
    xor     esi, esi
    jmp     .click
.not_left:
    cmp     dword [ui_input + UIINPUT.rmb_pressed], 0
    je      .after
    mov     esi, 1
.click:
    mov     edi, r12d
    mov     edx, [ui_input + UIINPUT.shift]
    call    inv_click
    test    eax, eax
    jz      .after
    call    rpg_recompute               ; the click may have moved gear
.after:
    cmp     byte [rbx + ITEMSTACK.count], 0
    je      .ret
    mov     [hover_ptr], rbx
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; pal_cell(edi x, esi y, edx id): creative palette cell. A press picks the item up on
; the cursor (left: a full stack, right: one) or, with a full cursor, clears the cursor.
pal_cell:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    mov     r12d, edx
    mov     eax, edx
    or      eax, 0x100                  ; {id, 1, 0}
    mov     [rsp], eax
    mov     edx, esi
    mov     esi, edi
    mov     rdi, rsp
    xor     ecx, ecx
    call    ui_slot
    test    eax, eax
    jz      .ret
    mov     eax, [rsp]                  ; the palette cell's stack {id, 1, 0}
    mov     [hover_pal], eax
    lea     rax, [hover_pal]
    mov     [hover_ptr], rax
    cmp     dword [ui_input + UIINPUT.lmb_pressed], 0
    je      .not_left
    xor     ebx, ebx
    jmp     .press
.not_left:
    cmp     dword [ui_input + UIINPUT.rmb_pressed], 0
    je      .ret
    mov     ebx, 1
.press:
    lea     rcx, [inv + INVENTORY.cursor]
    cmp     byte [rcx + ITEMSTACK.count], 0
    je      .take
    mov     dword [rcx], 0
    jmp     .ret
.take:
    mov     eax, 1
    test    ebx, ebx
    jnz     .put
    lea     rdx, [item_max_stack]
    movzx   eax, byte [rdx + r12]
.put:
    shl     eax, 8
    or      eax, r12d
    mov     [rcx], eax
.ret:
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; draw_hotbar(edi px, esi py): slots 0..8 at (px+8+18c, py+142)
draw_hotbar:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12d, edi
    mov     r13d, esi
    xor     ebx, ebx
.l:
    lea     rdi, [inv + rbx*4]
    imul    eax, ebx, 18
    lea     esi, [r12 + rax + 8]
    lea     edx, [r13 + 142]
    mov     ecx, ebx
    call    slot_cell
    inc     ebx
    cmp     ebx, 9
    jb      .l
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; draw_main(edi px, esi py): slots 9..35 at (px+8+18c, py+84+18r)
draw_main:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12d, edi
    mov     r13d, esi
    xor     ebx, ebx
.l:
    mov     eax, ebx
    xor     edx, edx
    mov     ecx, 9
    div     ecx                         ; eax = row, edx = column
    imul    edx, edx, 18
    imul    eax, eax, 18
    lea     esi, [r12 + rdx + 8]
    lea     edx, [r13 + rax + 84]
    lea     ecx, [rbx + 9]
    lea     rdi, [inv + rcx*4]
    call    slot_cell
    inc     ebx
    cmp     ebx, 27
    jb      .l
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; draw_player_inv(edi px, esi py): "Satchel" caption, main slots and hotbar
draw_player_inv:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12d, esi
    lea     rdi, [s_satchel]
    lea     esi, [rbx + 8]
    lea     edx, [r12 + 72]
    call    caption
    mov     edi, ebx
    mov     esi, r12d
    call    draw_main
    mov     edi, ebx
    mov     esi, r12d
    call    draw_hotbar
    pop     r12
    pop     rbx
    pop     rbp
    ret

; draw_grid(edi x0, esi y0, edx n): n x n crafting cells, cell (r,c) = ref 36 + 3r + c
draw_grid:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r12d, edi
    mov     r13d, esi
    mov     ebx, edx
    xor     r14d, r14d
.row:
    xor     r15d, r15d
.col:
    lea     eax, [r14 + r14*2]
    add     eax, r15d
    add     eax, SLOTREF_GRID
    mov     ecx, eax
    lea     rdi, [inv + rax*4]
    imul    eax, r15d, 18
    lea     esi, [r12 + rax]
    imul    eax, r14d, 18
    lea     edx, [r13 + rax]
    call    slot_cell
    inc     r15d
    cmp     r15d, ebx
    jb      .col
    inc     r14d
    cmp     r14d, ebx
    jb      .row
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; text_num(rdi dst, rsi prefix zstr, edx value) -> rax past the number (no NUL): the prefix, then
; the value in decimal
text_num:
    push    rbx
    mov     ebx, edx
    call    str_append
    mov     edi, ebx
    mov     rsi, rax
    call    i32_to_str
    pop     rbx
    ret

; gear_cell(rdi ITEMSTACK*, esi x, edx y, ecx ref, r8d glyph): a cell of the character page, clicked
; through slot_cell; while it is empty it shows the ink glyph tile of what it takes
; rbx = the stack, r12d = x, r13d = y, r14d = glyph
gear_cell:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, r8d
    call    slot_cell
    cmp     byte [rbx + ITEMSTACK.count], 0
    jne     .ret
    mov     edi, r14d
    lea     esi, [r12 + 1]
    lea     edx, [r13 + 1]
    mov     ecx, 16
    mov     r8d, C_INK_SOFT
    call    ui_tile_icon
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; tab(rdi label, esi x, edx w, ecx selected) -> eax 1 if an unselected tab was pressed: a TAB_H high
; plate above the pages (top at s_py + TAB_DY), lit when selected, a hover wash otherwise, the label in
; ink centred on it. A press clicks as a button does.
; rbx = label, r12d = x, r13d = w, r14d = selected, r15d = y, [rsp] 1 while the mouse is over it
tab:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    mov     r15d, [s_py]
    add     r15d, TAB_DY
    xor     ecx, ecx
    mov     eax, [ui_mx]
    sub     eax, r12d
    cmp     eax, r13d
    jae     .over_known                 ; unsigned: also rejects mx < x
    mov     eax, [ui_my]
    sub     eax, r15d
    cmp     eax, TAB_H
    setb    cl
.over_known:
    mov     [rsp], ecx
    mov     edi, NINE_BUTTON
    mov     eax, NINE_BUTTON_HOT
    test    r14d, r14d
    cmovnz  edi, eax
    mov     esi, r12d
    mov     edx, r15d
    mov     ecx, r13d
    mov     r8d, TAB_H
    call    ui_nine
    test    r14d, r14d
    jnz     .label
    cmp     dword [rsp], 0
    je      .label
    lea     edi, [r12 + 1]
    lea     esi, [r15 + 1]
    lea     edx, [r13 - 2]
    mov     ecx, TAB_H - 2
    mov     r8d, C_HOVER
    call    ui_rect
.label:
    mov     eax, r13d
    shr     eax, 1
    lea     esi, [r12 + rax]            ; x + w / 2
    lea     edx, [r15 + 4]
    mov     rdi, rbx
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink_centered
    xor     eax, eax
    test    r14d, r14d
    jnz     .ret
    cmp     dword [rsp], 0
    je      .ret
    cmp     dword [ui_input + UIINPUT.lmb_pressed], 0
    je      .ret
    mov     edi, SND_CLICK
    movss   xmm0, [f_click_vol]
    call    audio_play
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; draw_tabs(): the survival inventory's tabs above the left page, "Character" and "Recipes", the one of
; the page shown lit; a press on the other one switches inv_left. Nothing when screen_begin dropped the
; left page (a narrow screen).
; ebx = x of the left page, r12d = the page this frame shows
draw_tabs:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    cmp     dword [s_left], 0
    je      .ret
    mov     ebx, [s_px]
    sub     ebx, LEFT_SPAN
    mov     r12d, [inv_left]
    lea     rdi, [s_tab_character]
    lea     esi, [rbx + TAB_CHAR_X]
    mov     edx, TAB_CHAR_W
    xor     ecx, ecx
    test    r12d, r12d
    sete    cl
    call    tab
    test    eax, eax
    jz      .recipes
    mov     dword [inv_left], 0
.recipes:
    lea     rdi, [s_tab_recipes]
    lea     esi, [rbx + TAB_REC_X]
    mov     edx, TAB_REC_W
    xor     ecx, ecx
    test    r12d, r12d
    setne   cl
    call    tab
    test    eax, eax
    jz      .ret
    mov     dword [inv_left], 1
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; JEWEL ref, y offset, glyph tile: one jewelry cell of the character page (draw_character)
%macro JEWEL 3
    lea     rdi, [inv + INVENTORY.jewelry + (%1 - SLOTREF_JEWELRY) * 4]
    lea     esi, [r12 + 96]
    lea     edx, [r13 + %2]
    mov     ecx, %1
    mov     r8d, %3
    call    gear_cell
%endmacro

; draw_character(edi lx, esi py): the character page, the left page of the book with its corner at
; (lx, py): the archetype title and "Level N" centred on it, the silhouette (TILE_SIL0, 3 x 6 tiles of
; 16 units) with the four armor cells (refs 47..50) on its left and, on its right, the amulet, the two
; rings (refs 80, 78, 79) and the stack in hand (display only, "In hand" tooltip), then the Health and
; Armor lines. An empty gear cell shows the ink glyph of its kind.
; r12d = lx, r13d = py, ebx = loop counter, [rsp] the text line (48 bytes)
draw_character:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 56
    mov     r12d, edi
    mov     r13d, esi
    call    rpg_title
    mov     rdi, rax
    lea     esi, [r12 + 62]
    lea     edx, [r13 + 5]
    mov     ecx, C_RUBRIC
    mov     r8d, 1
    call    ui_text_ink_centered
    call    rpg_level
    mov     edx, eax
    mov     rdi, rsp
    lea     rsi, [s_level]
    call    text_num
    mov     byte [rax], 0
    mov     rdi, rsp
    lea     esi, [r12 + 62]
    lea     edx, [r13 + 15]
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink_centered
    xor     ebx, ebx
.sil:                                   ; silhouette sub-tile ebx: row ebx / 3, column ebx % 3
    mov     eax, ebx
    xor     edx, edx
    mov     ecx, 3
    div     ecx
    shl     eax, 4                      ; 16 * row
    lea     edi, [rax + rdx + TILE_SIL0]
    shl     edx, 4                      ; 16 * column
    lea     esi, [r12 + rdx + 38]
    lea     edx, [r13 + rax + 26]
    mov     ecx, 16
    mov     r8d, WHITE
    call    ui_tile_icon
    inc     ebx
    cmp     ebx, 18
    jb      .sil
    xor     ebx, ebx
.armor:
    lea     ecx, [rbx + SLOTREF_ARMOR]
    lea     rdi, [inv + rcx*4]
    lea     esi, [r12 + 10]
    imul    eax, ebx, 24
    lea     edx, [r13 + rax + 28]
    lea     r8d, [rbx + TILE_SLOT_HEAD]
    call    gear_cell
    inc     ebx
    cmp     ebx, 4
    jb      .armor
    JEWEL   SLOTREF_JEWELRY + 2, 36, TILE_SLOT_AMULET
    JEWEL   SLOTREF_JEWELRY + 0, 60, TILE_SLOT_RING
    JEWEL   SLOTREF_JEWELRY + 1, 84, TILE_SLOT_RING
    call    inv_held
    mov     rdi, rax
    lea     esi, [r12 + 96]
    lea     edx, [r13 + 108]
    mov     ecx, [show_counts]
    call    ui_slot
    test    eax, eax
    jz      .vitals
    lea     rax, [s_in_hand]
    mov     [hover_note], rax
.vitals:
    mov     edi, TILE_HEART_FULL
    lea     esi, [r12 + 10]
    lea     edx, [r13 + 128]
    call    ui_icon9
    mov     edx, [surv + SURVIVAL.health]
    mov     rdi, rsp
    lea     rsi, [s_health]
    call    text_num
    mov     rdi, rax
    lea     rsi, [s_slash]
    call    str_append
    mov     edi, [surv_max_health]
    mov     rsi, rax
    call    i32_to_str
    mov     byte [rax], 0
    mov     rdi, rsp
    lea     esi, [r12 + 22]
    lea     edx, [r13 + 128]
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
    mov     edi, TILE_ARMOR_FULL
    lea     esi, [r12 + 10]
    lea     edx, [r13 + 140]
    call    ui_icon9
    call    armor_effective
    mov     edx, eax
    mov     rdi, rsp
    lea     rsi, [s_armor]
    call    text_num
    mov     byte [rax], 0
    mov     rdi, rsp
    lea     esi, [r12 + 22]
    lea     edx, [r13 + 140]
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
    add     rsp, 56
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; container_cell(edi k, esi x, edx y): cell k of the open container, ref 51 + k
container_cell:
    mov     rax, [inv_container]
    lea     rax, [rax + CONTAINER.slots + rdi*4]
    lea     ecx, [rdi + SLOTREF_CONTAINER]
    mov     rdi, rax
    jmp     slot_cell

; container_gone() -> eax 1 if the open container was destroyed (or none is open)
container_gone:
    mov     rcx, [inv_container]
    test    rcx, rcx
    jz      .gone
    xor     eax, eax
    cmp     byte [rcx + CONTAINER.kind], 0
    sete    al
    ret
.gone:
    mov     eax, 1
    ret

; container_begin(edi left) -> eax 1 if the screen closed: Escape/inventory key, or the block
; behind it is gone. Otherwise draws the dimmer and the book (left as for screen_begin). A freshly
; entered screen resets the recipe book first.
container_begin:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
    call    container_gone
    test    eax, eax
    jz      .open
    mov     edi, CLOSE_CONTAINER
    call    do_close
    mov     eax, 1
    jmp     .ret
.open:
    cmp     dword [app_entered], 0
    je      .check
    call    book_reset
.check:
    mov     edi, CLOSE_CONTAINER
    call    check_close
    test    eax, eax
    jnz     .ret
    mov     edi, 1
    mov     esi, ebx
    call    screen_begin
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; draw_overlay(): the recipe book's tooltip, the hovered stack's item_tooltip (empty cursor only) or the
; note of a display-only cell, plus with Shift held the equipped item of its kind on the left of the
; mouse (drawn first, so the hovered stack's panel stays whole where the two meet), or the stack
; carried on the cursor
draw_overlay:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16                     ; [rsp] count text
    lea     rbx, [inv + INVENTORY.cursor]
    cmp     byte [rbx + ITEMSTACK.count], 0
    jne     .cursor
    cmp     byte [book_tip], 0
    je      .hover
    lea     rdi, [book_tip]
    call    ui_tooltip
    jmp     .ret
.hover:
    mov     rbx, [hover_ptr]
    test    rbx, rbx
    jz      .note
    mov     rdi, rbx
    lea     rsi, [tip_lines]
    lea     rdx, [tip_cols]
    call    item_tooltip
    test    eax, eax
    jz      .ret
    mov     r12d, eax                   ; the hovered stack's lines
    cmp     dword [ui_input + UIINPUT.shift], 0
    je      .draw
    mov     rdi, rbx
    call    gear_stack_worn
    test    eax, eax
    jnz     .draw                       ; a worn piece is its own comparison
    movzx   edi, byte [rbx + ITEMSTACK.id]
    call    gear_equipped_for
    test    rax, rax
    jz      .draw
    cmp     rax, rbx
    je      .draw                       ; the hovered stack is the equipped one
    mov     rdi, rax
    lea     rsi, [cmp_lines + 8]
    lea     rdx, [cmp_cols + 4]
    call    item_tooltip                ; its text lives in the other buffer: the hovered lines stay valid
    lea     rcx, [s_equipped]
    mov     [cmp_lines], rcx
    mov     dword [cmp_cols], C_GOLD_TEXT
    lea     esi, [rax + 1]
    lea     rdi, [cmp_lines]
    lea     rdx, [cmp_cols]
    mov     ecx, 1
    call    ui_tooltip_lines
.draw:
    lea     rdi, [tip_lines]
    mov     esi, r12d
    lea     rdx, [tip_cols]
    xor     ecx, ecx
    call    ui_tooltip_lines
    jmp     .ret
.note:
    mov     rdi, [hover_note]           ; 0 when the mouse is over no display-only cell
    call    ui_tooltip
    jmp     .ret
.cursor:
    movzx   edi, byte [rbx + ITEMSTACK.id]
    cmp     edi, NUM_ITEMS
    jae     .ret
    lea     rax, [item_max_stack]
    cmp     byte [rax + rdi], 0
    je      .ret
    mov     esi, [ui_mx]
    sub     esi, 8
    mov     edx, [ui_my]
    sub     edx, 8
    mov     ecx, 16
    call    ui_item_icon
    cmp     dword [show_counts], 0
    je      .ret
    movzx   edi, byte [rbx + ITEMSTACK.count]
    cmp     edi, 1
    jbe     .ret
    mov     rsi, rsp
    call    i32_to_str
    mov     byte [rax], 0
    mov     rdi, rsp
    mov     esi, 1
    call    ui_text_width
    mov     esi, [ui_mx]
    add     esi, 8
    sub     esi, eax                    ; right-aligned to the icon's right edge, as in a slot
    mov     rdi, rsp
    mov     edx, [ui_my]
    inc     edx
    mov     ecx, C_CREAM
    mov     r8d, 1
    call    ui_text
.ret:
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; screen_inventory(): the survival inventory (the character page or the recipe book on the left, the
; 2x2 crafting grid and the satchel on the right) or, in creative mode, the character page and the
; item palette
screen_inventory:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    cmp     dword [palette_n], 0
    jne     .built
    call    palette_build
.built:
    cmp     dword [app_entered], 0
    je      .entered
    mov     dword [pal_scroll], 0
    call    book_reset
.entered:
    mov     edi, CLOSE_INVENTORY
    call    check_close
    test    eax, eax
    jnz     .ret
    xor     edi, edi
    cmp     dword [game_mode], MODE_SURVIVAL
    sete    dil                         ; counts on the stacks in survival only
    mov     esi, LEFT_CHARACTER
    test    edi, edi
    jz      .begin                      ; creative: no recipe book
    mov     eax, 1 + BOOK_CRAFT
    cmp     dword [inv_left], 0
    cmovne  esi, eax
.begin:
    call    screen_begin
    mov     r12d, [s_px]
    mov     r13d, [s_py]
    cmp     dword [game_mode], MODE_CREATIVE
    je      .creative
    call    draw_tabs
    lea     rdi, [s_crafting]
    lea     esi, [r12 + 48]
    lea     edx, [r13 + 6]
    call    caption
    lea     edi, [r12 + 50]
    lea     esi, [r13 + 18]
    mov     edx, 2
    call    draw_grid
    lea     edi, [r12 + 50]
    lea     esi, [r13 + 18]
    call    book_ghost_draw
    lea     rdi, [s_arrow]
    lea     esi, [r12 + 92]
    lea     edx, [r13 + 32]
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
    lea     rdi, [inv + INVENTORY.result]
    lea     esi, [r12 + 110]
    lea     edx, [r13 + 28]
    mov     ecx, SLOTREF_RESULT
    call    slot_cell
    mov     edi, r12d
    mov     esi, r13d
    call    draw_player_inv
    jmp     .overlay
.creative:
    lea     rdi, [s_creative]
    call    page_title
    ; wheel up scrolls towards the first row
    mov     eax, [pal_scroll]
    sub     eax, [ui_input + UIINPUT.scroll]
    xor     ecx, ecx
    test    eax, eax
    cmovs   eax, ecx
    mov     ecx, [palette_n]
    add     ecx, 8
    imul    ecx, ecx, 0x38E4            ; / 9 (exact for n < 16384)
    shr     ecx, 17
    sub     ecx, PAL_VISIBLE            ; rows - visible
    cmp     eax, ecx
    cmovg   eax, ecx
    xor     ecx, ecx
    test    eax, eax
    cmovs   eax, ecx
    mov     [pal_scroll], eax
    imul    ebx, eax, 9                 ; first visible palette index
    lea     r14d, [rbx + PAL_VISIBLE * 9]
    cmp     r14d, [palette_n]
    jbe     .pal
    mov     r14d, [palette_n]
.pal:
    imul    ecx, [pal_scroll], 9
    mov     eax, ebx
    sub     eax, ecx                    ; index within the visible window
    xor     edx, edx
    mov     ecx, 9
    div     ecx                         ; eax = row, edx = column
    imul    edx, edx, 18
    imul    eax, eax, 18
    lea     edi, [r12 + rdx + 8]
    lea     esi, [r13 + rax + 18]
    lea     rcx, [palette]
    movzx   edx, byte [rcx + rbx]
    call    pal_cell
    inc     ebx
    cmp     ebx, r14d
    jb      .pal
    ; scrollbar: track and thumb
    lea     edi, [r12 + 170]
    lea     esi, [r13 + 18]
    mov     edx, 2
    mov     ecx, PAL_TRACK
    mov     r8d, C_LOCKED
    call    ui_rect
    mov     eax, [palette_n]
    add     eax, 8
    xor     edx, edx
    mov     ecx, 9
    div     ecx
    mov     r14d, eax                   ; rows
    imul    eax, [pal_scroll], PAL_TRACK
    xor     edx, edx
    div     r14d
    lea     edi, [r12 + 170]
    lea     esi, [r13 + rax + 18]
    mov     eax, PAL_TRACK * PAL_VISIBLE
    xor     edx, edx
    div     r14d
    mov     ecx, eax
    mov     edx, 2
    mov     r8d, C_INK_SOFT
    call    ui_rect
    lea     rdi, [s_hotbar]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 130]
    call    caption
    mov     edi, r12d
    mov     esi, r13d
    call    draw_hotbar
.overlay:
    call    draw_overlay
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; screen_crafting(): the 3x3 crafting-table screen over the player inventory
screen_crafting:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    cmp     dword [app_entered], 0
    je      .check
    call    book_reset
.check:
    mov     edi, CLOSE_CRAFTING
    call    check_close
    test    eax, eax
    jnz     .ret
    mov     edi, 1
    mov     esi, 1 + BOOK_CRAFT
    call    screen_begin
    mov     r12d, [s_px]
    mov     r13d, [s_py]
    lea     rdi, [s_crafting]
    call    page_title
    lea     edi, [r12 + 30]
    lea     esi, [r13 + 17]
    mov     edx, 3
    call    draw_grid
    lea     edi, [r12 + 30]
    lea     esi, [r13 + 17]
    call    book_ghost_draw
    lea     rdi, [s_arrow]
    lea     esi, [r12 + 92]
    lea     edx, [r13 + 39]
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
    lea     rdi, [inv + INVENTORY.result]
    lea     esi, [r12 + 124]
    lea     edx, [r13 + 35]
    mov     ecx, SLOTREF_RESULT
    call    slot_cell
    mov     edi, r12d
    mov     esi, r13d
    call    draw_player_inv
    call    draw_overlay
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; screen_furnace(): input, fuel and output cells with the flame and progress gauges
screen_furnace:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     edi, 1 + BOOK_FURNACE
    call    container_begin
    test    eax, eax
    jnz     .ret
    mov     r12d, [s_px]
    mov     r13d, [s_py]
    mov     rbx, [inv_container]
    lea     rdi, [s_furnace]
    call    page_title
    xor     edi, edi                    ; input
    lea     esi, [r12 + 56]
    lea     edx, [r13 + 17]
    call    container_cell
    ; flame: fuel left in the current item
    lea     edi, [r12 + 57]
    lea     esi, [r13 + 37]
    mov     edx, 14
    mov     ecx, 14
    mov     r8d, C_LOCKED
    call    ui_rect
    movzx   ecx, word [rbx + CONTAINER.burn_max]
    test    ecx, ecx
    jz      .no_flame
    movzx   eax, word [rbx + CONTAINER.burn]
    imul    eax, eax, 14
    xor     edx, edx
    div     ecx
    test    eax, eax
    jz      .no_flame
    mov     ecx, 14
    cmp     eax, ecx
    cmova   eax, ecx
    mov     ecx, eax                    ; h
    lea     edi, [r12 + 57]
    lea     esi, [r13 + 51]
    sub     esi, eax
    mov     edx, 14
    mov     r8d, RGBA(255, 140, 20, 255)
    call    ui_rect
.no_flame:
    mov     edi, NINE_BAR               ; the gauge's frame, over its edge
    lea     esi, [r12 + 56]
    lea     edx, [r13 + 36]
    mov     ecx, 16
    mov     r8d, 16
    call    ui_nine
    mov     edi, 1                      ; fuel
    lea     esi, [r12 + 56]
    lea     edx, [r13 + 53]
    call    container_cell
    ; progress arrow
    lea     edi, [r12 + 80]
    lea     esi, [r13 + 39]
    mov     edx, 24
    mov     ecx, 6
    mov     r8d, C_LOCKED
    call    ui_rect
    movzx   eax, word [rbx + CONTAINER.cook]
    imul    eax, eax, 24
    xor     edx, edx
    mov     ecx, SMELT_STEPS
    div     ecx
    test    eax, eax
    jz      .no_progress
    mov     edx, 24
    cmp     eax, edx
    cmova   eax, edx
    mov     edx, eax                    ; w
    lea     edi, [r12 + 80]
    lea     esi, [r13 + 39]
    mov     ecx, 6
    mov     r8d, C_INK
    call    ui_rect
.no_progress:
    mov     edi, NINE_BAR
    lea     esi, [r12 + 79]
    lea     edx, [r13 + 38]
    mov     ecx, 26
    mov     r8d, 8
    call    ui_nine
    mov     edi, 2                      ; output
    lea     esi, [r12 + 116]
    lea     edx, [r13 + 35]
    call    container_cell
    mov     edi, r12d
    mov     esi, r13d
    call    draw_player_inv
    call    draw_overlay
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; screen_chest(): 3 rows of 9 chest cells over the player inventory
screen_chest:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    xor     edi, edi                    ; no book on a chest
    call    container_begin
    test    eax, eax
    jnz     .ret
    mov     r12d, [s_px]
    mov     r13d, [s_py]
    lea     rdi, [s_chest]
    call    page_title
    xor     ebx, ebx
.cell:
    mov     eax, ebx
    xor     edx, edx
    mov     ecx, 9
    div     ecx                         ; eax = row, edx = column
    imul    edx, edx, 18
    imul    eax, eax, 18
    lea     esi, [r12 + rdx + 8]
    lea     edx, [r13 + rax + 17]
    mov     edi, ebx
    call    container_cell
    inc     ebx
    cmp     ebx, 27
    jb      .cell
    mov     edi, r12d
    mov     esi, r13d
    call    draw_player_inv
    call    draw_overlay
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
