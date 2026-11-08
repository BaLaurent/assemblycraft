; invscreen.asm - the inventory screens: survival inventory with armor, jewelry and a 2x2
; crafting grid, the 3x3 crafting-table screen, the furnace and chest screens and the
; creative item palette. Immediate mode: every frame draws the panel and its slots,
; turns presses on hovered slots into inv_click calls, then draws the tooltip and the
; stack held on the cursor.
; The survival inventory, the crafting table and the furnace screen carry the recipe book
; (recipebook.asm) on the left of the panel; the tooltip of its hovered entry (book_tip) takes the
; place of the slot tooltip.
; Slot references (inv_click): 0..35 slots, 36..44 grid cells, 45 result, 47..50 armor
; (all at inv + ref*4), 51.. cells of the open container (inv_container), 78..80 the jewelry cells
; (ring, ring, amulet; survival inventory only). Gear changes the stats, so every inv_click that
; changed something is followed by rpg_recompute. A hovered stack shows item_tooltip's lines;
; with Shift held the equipped item of its kind is shown beside it.
%include "common.inc"
default rel

global screen_inventory, screen_crafting, screen_furnace, screen_chest

extern game_mode, frame_input, ui_input, inv, craft_size, inv_container
extern app_goto, app_entered
extern ui_w, ui_h, ui_mx, ui_my
extern ui_rect, ui_frame, ui_text, ui_text_width, ui_slot, ui_item_icon, ui_tooltip
extern ui_tooltip_lines
extern inv_click, inv_close_screen, item_tooltip, gear_equipped_for, gear_stack_worn, rpg_recompute
extern item_max_stack, i32_to_str
extern book_reset, book_draw, book_ghost_draw, book_tip

%define PANEL_W     176
%define PANEL_H     166
%define LABEL_COL   RGBA(220, 220, 220, 255)
%define GREY_COL    RGBA(170, 170, 170, 255)
%define PANEL_COL   RGBA(62, 62, 68, 235)
%define EDGE_COL    RGBA(255, 255, 255, 70)
%define PAL_VISIBLE 6
%define PAL_TRACK   (PAL_VISIBLE * 18)

%define BOOK_W      124                 ; the recipe book panel (recipebook.asm) and its gap to the panel
%define BOOK_GAP    2
%define BOOK_CRAFT  0                   ; book kinds; screen_begin takes kind + 1, 0 = no book
%define BOOK_FURNACE 1

%define CLOSE_INVENTORY 0               ; do_close / check_close screen kinds
%define CLOSE_CRAFTING  1
%define CLOSE_CONTAINER 2

section .rodata
s_inventory:  db "Inventory", 0
s_crafting:   db "Crafting", 0
s_creative:   db "Creative", 0
s_hotbar:     db "Hotbar", 0
s_arrow:      db "->", 0
s_armor:      db "Armor", 0
s_jewelry:    db "Jewelry", 0
s_equipped:   db "Equipped", 0
s_furnace:    db "Furnace", 0
s_chest:      db "Chest", 0

section .bss
alignb 8
hover_ptr:    resq 1                    ; ITEMSTACK under the mouse this frame, 0 = none
tip_lines:    resq 12                   ; item_tooltip lines of the hovered stack ...
tip_cols:     resd 12
cmp_lines:    resq 13                   ; ... and of the equipped one, under an "Equipped" line
cmp_cols:     resd 13
s_px:         resd 1                    ; panel origin in GUI units
s_py:         resd 1
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

; label(rdi s, esi x, edx y): grey 1x text
label:
    mov     ecx, LABEL_COL
    mov     r8d, 1
    jmp     ui_text

; screen_begin(edi show_counts, esi with_book): reset per-frame state, draw the dimmer, the panel
; and, for with_book = 1 + BOOK_CRAFT or 1 + BOOK_FURNACE (0 = none), the recipe book to the
; left of the panel. With a book the pair is centred; the panel never moves left of the book.
screen_begin:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, esi
    mov     [show_counts], edi
    mov     qword [hover_ptr], 0
    mov     byte [book_tip], 0
    mov     eax, [ui_w]
    sub     eax, PANEL_W
    test    ebx, ebx
    jz      .centre
    sub     eax, BOOK_W + BOOK_GAP
    sar     eax, 1
    add     eax, BOOK_W + BOOK_GAP
    mov     ecx, BOOK_W + BOOK_GAP
    cmp     eax, ecx
    cmovl   eax, ecx                    ; a narrow window pushes the panel right, not the book off
    jmp     .have_x
.centre:
    sar     eax, 1
.have_x:
    mov     [s_px], eax
    mov     eax, [ui_h]
    sub     eax, PANEL_H
    sar     eax, 1
    mov     [s_py], eax
    xor     edi, edi
    xor     esi, esi
    mov     edx, [ui_w]
    mov     ecx, [ui_h]
    mov     r8d, RGBA(0, 0, 0, 100)
    call    ui_rect
    mov     edi, [s_px]
    mov     esi, [s_py]
    mov     edx, PANEL_W
    mov     ecx, PANEL_H
    mov     r8d, PANEL_COL
    call    ui_rect
    mov     edi, [s_px]
    mov     esi, [s_py]
    mov     edx, PANEL_W
    mov     ecx, PANEL_H
    mov     r8d, EDGE_COL
    call    ui_frame
    test    ebx, ebx
    jz      .done
    mov     edi, [s_px]
    sub     edi, BOOK_W + BOOK_GAP
    mov     esi, [s_py]
    lea     edx, [rbx - 1]
    call    book_draw
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

; draw_cell(rdi ITEMSTACK*, esi x, edx y, ecx show_count) -> eax hover: ui_slot plus a
; thin border (the 18-unit cells touch, so the slots need a visible separator)
draw_cell:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     r12d, esi
    mov     r13d, edx
    call    ui_slot
    mov     ebx, eax
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, 18
    mov     ecx, 18
    mov     r8d, RGBA(16, 16, 20, 150)
    call    ui_frame
    mov     eax, ebx
    add     rsp, 8
    pop     r13
    pop     r12
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
    call    draw_cell
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
    call    draw_cell
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

; draw_player_inv(edi px, esi py): "Inventory" label, main slots and hotbar
draw_player_inv:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12d, esi
    lea     rdi, [s_inventory]
    lea     esi, [rbx + 8]
    lea     edx, [r12 + 72]
    call    label
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

; container_begin(edi with_book) -> eax 1 if the screen closed: Escape/inventory key, or the block
; behind it is gone. Otherwise draws the dimmer, the panel and the book (with_book as for
; screen_begin). A freshly entered screen resets the book first.
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

; draw_overlay(): the recipe book's tooltip or the hovered stack's item_tooltip (empty cursor
; only), plus with Shift held the equipped item of its kind on the left of the mouse (drawn first,
; so the hovered stack's panel stays whole where the two meet), or the stack carried on the cursor
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
    jz      .ret
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
    mov     dword [cmp_cols], GREY_COL
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
    mov     ecx, 0xFFFFFFFF
    mov     r8d, 1
    call    ui_text
.ret:
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; screen_inventory(): survival 2x2 inventory with armor and jewelry cells and the recipe book, or
; the creative palette in creative mode
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
    sete    dil
    mov     esi, edi                    ; survival: the crafting book beside the panel
    call    screen_begin
    mov     r12d, [s_px]
    mov     r13d, [s_py]
    cmp     dword [game_mode], MODE_CREATIVE
    je      .creative
    lea     rdi, [s_crafting]
    lea     esi, [r12 + 88]
    lea     edx, [r13 + 6]
    call    label
    lea     edi, [r12 + 98]
    lea     esi, [r13 + 18]
    mov     edx, 2
    call    draw_grid
    lea     edi, [r12 + 98]
    lea     esi, [r13 + 18]
    call    book_ghost_draw
    lea     rdi, [s_arrow]
    lea     esi, [r12 + 138]
    lea     edx, [r13 + 32]
    call    label
    lea     rdi, [inv + INVENTORY.result]
    lea     esi, [r12 + 154]
    lea     edx, [r13 + 28]
    mov     ecx, SLOTREF_RESULT
    call    slot_cell
    lea     rdi, [s_armor]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 6]
    call    label
    xor     ebx, ebx
.armor:
    lea     ecx, [rbx + SLOTREF_ARMOR]
    lea     rdi, [inv + rcx*4]
    imul    eax, ebx, 18
    lea     esi, [r12 + rax + 8]
    lea     edx, [r13 + 17]
    call    slot_cell
    inc     ebx
    cmp     ebx, 4
    jb      .armor
    lea     rdi, [s_jewelry]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 38]
    call    label
    xor     ebx, ebx
.jewelry:
    lea     ecx, [rbx + SLOTREF_JEWELRY]
    lea     rdi, [inv + INVENTORY.jewelry + rbx*4]
    imul    eax, ebx, 18
    lea     esi, [r12 + rax + 8]
    lea     edx, [r13 + 48]
    call    slot_cell
    inc     ebx
    cmp     ebx, 3
    jb      .jewelry
    mov     edi, r12d
    mov     esi, r13d
    call    draw_player_inv
    jmp     .overlay
.creative:
    lea     rdi, [s_creative]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 6]
    call    label
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
    mov     r8d, RGBA(255, 255, 255, 40)
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
    mov     r8d, RGBA(255, 255, 255, 160)
    call    ui_rect
    lea     rdi, [s_hotbar]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 130]
    call    label
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
    lea     esi, [r12 + 28]
    lea     edx, [r13 + 6]
    call    label
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
    call    label
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
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 6]
    call    label
    xor     edi, edi                    ; input
    lea     esi, [r12 + 56]
    lea     edx, [r13 + 17]
    call    container_cell
    ; flame: fuel left in the current item
    lea     edi, [r12 + 57]
    lea     esi, [r13 + 37]
    mov     edx, 14
    mov     ecx, 14
    mov     r8d, RGBA(0, 0, 0, 90)
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
    mov     edi, 1                      ; fuel
    lea     esi, [r12 + 56]
    lea     edx, [r13 + 53]
    call    container_cell
    ; progress arrow
    lea     edi, [r12 + 80]
    lea     esi, [r13 + 39]
    mov     edx, 24
    mov     ecx, 6
    mov     r8d, RGBA(0, 0, 0, 90)
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
    mov     r8d, RGBA(255, 255, 255, 200)
    call    ui_rect
.no_progress:
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
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 6]
    call    label
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
