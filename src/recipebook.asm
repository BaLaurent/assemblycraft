; recipebook.asm - the recipe book: the contents of the left page of the inventory book (the survival
; inventory's Recipes tab, the crafting-table and furnace screens), and the ghost of a missing recipe
; in the crafting grid.
; The entry lists are built once from the tables. Craft entries are the runs of adjacent recipe
; records with the same output (the run's first record stands for it), smelt entries every item
; with an item_smelt result, fuel entries every item with an item_burn value. Every frame the
; shown list is filtered and drawn as a 6-column grid of 18-unit cells. A press on a craft entry
; fills the grid (recipe_fill) or, when something is missing, leaves a ghost of the pattern in
; the grid; a press on a furnace entry moves that item into the furnace (cont_fill_from_inv).
; invscreen.asm draws the book and its page, places the contents with book_draw, calls book_ghost_draw
; after the grid and draws book_tip, the tooltip of the hovered entry, last.
%include "common.inc"
%include "theme.inc"
default rel

global book_reset, book_draw, book_ghost_draw, book_tip

extern ui_mx, ui_my, ui_input
extern ui_rect, ui_frame, ui_text_ink_centered, ui_button, ui_slot, ui_item_icon_tint
extern inv, craft_size
extern recipes, recipes_end
extern recipe_uses, recipe_have, recipe_fits, recipe_sets, recipe_fill
extern cont_fill_from_inv, inv_count
extern item_names, item_burn, item_smelt, item_max_stack
extern audio_play, i32_to_str

%define BOOK_CRAFT      0               ; book kinds (invscreen.asm passes the same numbers)
%define BOOK_FURNACE    1
%define BOOK_W          124             ; the left page's size; invscreen.asm draws the page itself
%define BOOK_H          166             ; = PANEL_H, the right page it stands beside
%define COLS            6
%define CELL            18
%define TOP_CRAFT       40              ; y of the first cell row inside the page
%define TOP_FURNACE     62              ; (the furnace book has the tab button above its cells)
%define ROWS_CRAFT      ((BOOK_H - TOP_CRAFT - 6) / CELL)
%define ROWS_FURNACE    ((BOOK_H - TOP_FURNACE - 6) / CELL)
%define MAX_ENTRIES     256
%define TIP_MAX         180             ; the tooltip text stops here; book_tip is 192 bytes

; locals of book_draw
%define L_TOP           0               ; first cell row, relative to the page
%define L_ROWS          4               ; rows shown at a time
%define L_TOTAL         8               ; rows the filtered list needs
%define L_TRACK         12              ; scrollbar track height
%define L_CX            16              ; the cell being drawn
%define L_CY            20
%define L_ENTRY         24
%define L_STACK         28              ; the ITEMSTACK handed to ui_slot
%define L_HOVER         32

; entry flags (vis_flag, entry_state)
%define F_OK            1               ; craftable now / owned in the inventory
%define F_FITS          2               ; the recipe fits the active grid

section .rodata
align 8
filter_labels:  dq s_all, s_craftable, s_all, s_in_inventory    ; [kind * 2 + filter]
tab_labels:     dq s_smelting, s_fuel                           ; [tab]
s_recipes:      db "Recipes", 0
s_all:          db "Show: All", 0
s_craftable:    db "Show: Craftable", 0
s_in_inventory: db "Show: In inventory", 0
s_smelting:     db "Smelting", 0
s_fuel:         db "Fuel", 0
s_x:            db " x", 0
s_colon:        db ": ", 0
s_comma:        db ", ", 0
s_arrow:        db " -> ", 0
s_needs_table:  db " - needs a Crafting Table", 0
s_missing:      db " - missing items", 0
s_none_inv:     db " - none in inventory", 0
s_smelts:       db ": smelts ", 0
s_items:        db " items", 0
align 4
f_click_vol:    dd 0.6

section .bss
alignb 8
ghost_rec:      resq 1                  ; RECIPE* drawn as a ghost in the grid, or 0
tip_end:        resq 1                  ; where the next tooltip character goes
book_tip:       resb 192                ; tooltip of the hovered entry, [0] = 0 when none
alignb 4
entries_built:  resd 1
book_kind:      resd 1                  ; the kind being drawn this frame
book_tab:       resd 1                  ; furnace book: 0 smelting, 1 fuel
book_scroll:    resd 1                  ; first visible row
book_filter:    resd 2                  ; per kind: 1 = only craftable / in the inventory
craft_n:        resd 1
smelt_n:        resd 1
fuel_n:         resd 1
vis_n:          resd 1                  ; entries that pass the filter
craft_first:    resw MAX_ENTRIES        ; index of the first record of a craft entry's run
craft_run:      resb MAX_ENTRIES        ; records in the run
smelt_ids:      resb MAX_ENTRIES        ; the item each smelt entry smelts
fuel_ids:       resb MAX_ENTRIES        ; the item each fuel entry is
vis_idx:        resw MAX_ENTRIES        ; entry index of each visible entry
vis_flag:       resb MAX_ENTRIES        ; F_OK | F_FITS of each visible entry

section .text

; ---- entries ------------------------------------------------------------------------------

; build_entries() - fills the three entry lists, once
build_entries:
    cmp     dword [entries_built], 0
    jne     .ret
    mov     dword [entries_built], 1
    lea     rsi, [recipes]
    lea     r8, [recipes_end]
    xor     ecx, ecx                    ; record index
    xor     edx, edx                    ; craft entries so far
    mov     r9d, -1                     ; output of the open run
.rec:
    cmp     rsi, r8
    jae     .craft_done
    movzx   eax, byte [rsi + 2]
    cmp     eax, r9d
    je      .same
    cmp     edx, MAX_ENTRIES
    jae     .craft_done                 ; list full: the rest stays out of the book
    mov     r9d, eax
    lea     rdi, [craft_first]
    mov     [rdi + rdx*2], cx
    lea     rdi, [craft_run]
    mov     byte [rdi + rdx], 1
    inc     edx
    jmp     .nextrec
.same:
    lea     rdi, [craft_run]
    inc     byte [rdi + rdx - 1]
.nextrec:
    add     rsi, RECIPE_SIZE
    inc     ecx
    jmp     .rec
.craft_done:
    mov     [craft_n], edx
    lea     r8, [item_smelt]
    lea     r9, [item_burn]
    lea     r10, [item_max_stack]
    lea     rdi, [smelt_ids]
    lea     rsi, [fuel_ids]
    xor     edx, edx                    ; smelt entries
    xor     r11d, r11d                  ; fuel entries
    mov     ecx, 1
.item:
    cmp     byte [r8 + rcx], 0
    je      .not_smelt
    mov     [rdi + rdx], cl
    inc     edx
.not_smelt:
    cmp     byte [r10 + rcx], 0
    je      .not_fuel
    cmp     word [r9 + rcx*2], 0
    je      .not_fuel
    mov     [rsi + r11], cl
    inc     r11d
.not_fuel:
    inc     ecx
    cmp     ecx, NUM_ITEMS
    jb      .item
    mov     [smelt_n], edx
    mov     [fuel_n], r11d
.ret:
    ret

; list_n() -> eax entries in the list the book shows now
list_n:
    cmp     dword [book_kind], BOOK_CRAFT
    jne     .furnace
    mov     eax, [craft_n]
    ret
.furnace:
    cmp     dword [book_tab], 0
    jne     .fuel
    mov     eax, [smelt_n]
    ret
.fuel:
    mov     eax, [fuel_n]
    ret

; entry_rec(edi e) -> rax first record of craft entry e
entry_rec:
    lea     rax, [craft_first]
    movzx   eax, word [rax + rdi*2]
    imul    eax, eax, RECIPE_SIZE
    lea     rcx, [recipes]
    add     rax, rcx
    ret

; entry_id(edi e) -> eax the item of furnace entry e: what it smelts, or the fuel
entry_id:
    lea     rax, [fuel_ids]
    lea     rcx, [smelt_ids]
    cmp     dword [book_tab], 0
    cmove   rax, rcx
    movzx   eax, byte [rax + rdi]
    ret

; craft_pick(edi e, esi mode) -> rax a record of craft entry e's run, or 0
; mode 0: the first record that fits the active grid; mode 1: the first one that fits and that
; the inventory and grid can make at least once
craft_pick:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     r13d, esi
    lea     rax, [craft_run]
    movzx   r12d, byte [rax + rdi]
    call    entry_rec
    mov     rbx, rax
.rec:
    mov     rdi, rbx
    call    recipe_fits
    test    eax, eax
    jz      .next
    test    r13d, r13d
    jz      .found
    mov     rdi, rbx
    call    recipe_sets
    test    eax, eax
    jnz     .found
.next:
    add     rbx, RECIPE_SIZE
    dec     r12d
    jnz     .rec
    xor     eax, eax
    jmp     .out
.found:
    mov     rax, rbx
.out:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; entry_state(edi e) -> eax F_OK | F_FITS of entry e of the shown list. Craft: F_FITS when a
; record of the run fits the grid, F_OK when one of those can be made now. Furnace: F_FITS
; always, F_OK when the inventory holds the item.
entry_state:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi
    xor     r12d, r12d
    cmp     dword [book_kind], BOOK_CRAFT
    jne     .furnace
    mov     edi, ebx
    xor     esi, esi
    call    craft_pick
    test    rax, rax
    jz      .out
    mov     r12d, F_FITS
    mov     edi, ebx
    mov     esi, 1
    call    craft_pick
    test    rax, rax
    jz      .out
    or      r12d, F_OK
    jmp     .out
.furnace:
    mov     r12d, F_FITS
    mov     edi, ebx
    call    entry_id
    mov     edi, eax
    call    inv_count
    test    eax, eax
    jz      .out
    or      r12d, F_OK
.out:
    mov     eax, r12d
    pop     r12
    pop     rbx
    pop     rbp
    ret

; collect() - fills vis_idx / vis_flag with the entries of the shown list that pass the
; filter, and vis_n with how many there are
collect:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    xor     r12d, r12d                  ; visible entries
    xor     r13d, r13d                  ; entry
    call    list_n
    mov     r14d, eax
    mov     eax, [book_kind]
    lea     rcx, [book_filter]
    mov     ebx, [rcx + rax*4]
.entry:
    cmp     r13d, r14d
    jae     .done
    mov     edi, r13d
    call    entry_state
    test    ebx, ebx
    jz      .keep
    test    eax, F_OK
    jz      .skip                       ; the filter hides what cannot be made / is not owned
.keep:
    lea     rcx, [vis_idx]
    mov     [rcx + r12*2], r13w
    lea     rcx, [vis_flag]
    mov     [rcx + r12], al
    inc     r12d
.skip:
    inc     r13d
    jmp     .entry
.done:
    mov     [vis_n], r12d
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- tooltip text -------------------------------------------------------------------------

; tip_begin() - empties book_tip and starts a new text
tip_begin:
    lea     rax, [book_tip]
    mov     [tip_end], rax
    mov     byte [rax], 0
    ret

; tip_finish() - closes the text with its NUL
tip_finish:
    mov     rax, [tip_end]
    mov     byte [rax], 0
    ret

; tip_str(rdi zstr) - appends the text; what does not fit in book_tip is cut off
tip_str:
    mov     rsi, rdi
    mov     rdi, [tip_end]
    lea     rdx, [book_tip + TIP_MAX]
.l:
    mov     al, [rsi]
    test    al, al
    jz      .done
    cmp     rdi, rdx
    jae     .done
    mov     [rdi], al
    inc     rdi
    inc     rsi
    jmp     .l
.done:
    mov     [tip_end], rdi
    ret

; tip_chr(edi c) - appends one character
tip_chr:
    mov     rdx, [tip_end]
    lea     rax, [book_tip + TIP_MAX]
    cmp     rdx, rax
    jae     .ret
    mov     [rdx], dil
    inc     rdx
    mov     [tip_end], rdx
.ret:
    ret

; tip_num(edi n) - appends n in decimal
tip_num:
    sub     rsp, 8
    mov     rsi, [tip_end]
    call    i32_to_str
    mov     [tip_end], rax
    add     rsp, 8
    ret

; tip_item(edi id) - appends the item's name
tip_item:
    mov     edi, edi
    lea     rax, [item_names]
    mov     rdi, [rax + rdi*8]
    jmp     tip_str

; tip_craft(rdi rec, esi suffix) - "<Name>[ x<count>]: <n> <Ingredient>, ..." and, for suffix 1,
; " - needs a Crafting Table" (the recipe does not fit the grid) or, for 2, " - missing items"
tip_craft:
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
    call    tip_begin
    movzx   edi, byte [rbx + 2]
    call    tip_item
    movzx   edi, byte [rbx + 3]
    cmp     edi, 1
    jbe     .no_count
    mov     r13d, edi
    lea     rdi, [s_x]
    call    tip_str
    mov     edi, r13d
    call    tip_num
.no_count:
    lea     rdi, [s_colon]
    call    tip_str
    xor     r13d, r13d                  ; cell
    xor     r14d, r14d                  ; ingredients written
.cell:
    movzx   r15d, byte [rbx + 4 + r13]
    test    r15d, r15d
    jz      .next
    xor     ecx, ecx
.dup:                                   ; an ingredient is listed once, at its first cell
    cmp     ecx, r13d
    jae     .new
    cmp     [rbx + 4 + rcx], r15b
    je      .next
    inc     ecx
    jmp     .dup
.new:
    test    r14d, r14d
    jz      .first
    lea     rdi, [s_comma]
    call    tip_str
.first:
    inc     r14d
    mov     rdi, rbx
    mov     esi, r15d
    call    recipe_uses
    mov     edi, eax
    call    tip_num
    mov     edi, ' '
    call    tip_chr
    mov     edi, r15d
    call    tip_item
.next:
    inc     r13d
    cmp     r13d, 9
    jb      .cell
    test    r12d, r12d
    jz      .finish
    lea     rdi, [s_needs_table]
    cmp     r12d, 1
    je      .suffix
    lea     rdi, [s_missing]
.suffix:
    call    tip_str
.finish:
    call    tip_finish
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; tip_smelt(edi id, esi owned) - "<Item> -> <Result>", plus " - none in inventory" unless owned
tip_smelt:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12d, esi
    call    tip_begin
    mov     edi, ebx
    call    tip_item
    lea     rdi, [s_arrow]
    call    tip_str
    lea     rax, [item_smelt]
    movzx   edi, byte [rax + rbx]
    call    tip_item
    test    r12d, r12d
    jnz     .finish
    lea     rdi, [s_none_inv]
    call    tip_str
.finish:
    call    tip_finish
    pop     r12
    pop     rbx
    pop     rbp
    ret

; tip_fuel(edi id) - "<Fuel>: smelts <a.b> items": its burn steps over SMELT_STEPS, in tenths
tip_fuel:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
    call    tip_begin
    mov     edi, ebx
    call    tip_item
    lea     rdi, [s_smelts]
    call    tip_str
    lea     rax, [item_burn]
    movzx   eax, word [rax + rbx*2]
    imul    eax, eax, 10
    xor     edx, edx
    mov     ecx, SMELT_STEPS
    div     ecx                         ; tenths of an item
    xor     edx, edx
    mov     ecx, 10
    div     ecx                         ; eax = whole items, edx = tenths
    mov     ebx, edx
    mov     edi, eax
    call    tip_num
    mov     edi, '.'
    call    tip_chr
    lea     edi, [rbx + '0']
    call    tip_chr
    lea     rdi, [s_items]
    call    tip_str
    call    tip_finish
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- clicks -------------------------------------------------------------------------------

; click_sound()
click_sound:
    sub     rsp, 8
    mov     edi, SND_CLICK
    movss   xmm0, [f_click_vol]
    call    audio_play
    add     rsp, 8
    ret

; craft_click(edi e, esi shift) - a press on craft entry e. A record that fits and that the
; inventory can make fills the grid (shift: as many sets as there are, up to a stack); else
; the first record that fits becomes the ghost. A press always drops the previous ghost.
craft_click:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12d, esi
    mov     qword [ghost_rec], 0
    mov     esi, 1
    call    craft_pick
    test    rax, rax
    jz      .ghost
    mov     rdi, rax
    mov     esi, 1
    test    r12d, r12d
    jz      .fill
    mov     esi, 64
.fill:
    call    recipe_fill
    call    click_sound
    jmp     .out
.ghost:
    mov     edi, ebx
    xor     esi, esi
    call    craft_pick
    mov     [ghost_rec], rax
.out:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; cell_hover(edi e, esi flags) - the mouse is over the cell of entry e: write its tooltip and
; act on a left press
cell_hover:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12d, esi
    cmp     dword [book_kind], BOOK_CRAFT
    jne     .furnace
    mov     edi, ebx
    call    entry_rec
    mov     rdi, rax
    xor     esi, esi                    ; suffix: none when it can be made
    test    r12d, F_FITS
    jnz     .fits
    mov     esi, 1                      ; needs a bigger grid
    jmp     .tip
.fits:
    test    r12d, F_OK
    jnz     .tip
    mov     esi, 2                      ; missing items
.tip:
    call    tip_craft
    cmp     dword [ui_input + UIINPUT.lmb_pressed], 0
    je      .out
    mov     edi, ebx
    mov     esi, [ui_input + UIINPUT.shift]
    call    craft_click
    jmp     .out
.furnace:
    mov     edi, ebx
    call    entry_id
    mov     ebx, eax                    ; the item
    mov     edi, ebx
    cmp     dword [book_tab], 0
    jne     .fuel_tip
    mov     esi, r12d
    and     esi, F_OK
    call    tip_smelt
    jmp     .furnace_click
.fuel_tip:
    call    tip_fuel
.furnace_click:
    cmp     dword [ui_input + UIINPUT.lmb_pressed], 0
    je      .out
    mov     edi, [book_tab]             ; cell 0 takes what smelts, cell 1 the fuel
    mov     esi, ebx
    call    cont_fill_from_inv
    test    eax, eax
    jz      .out
    call    click_sound
.out:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- drawing ------------------------------------------------------------------------------

; book_reset() - a screen was entered: scroll back to the top, the furnace book to its smelting
; tab, the ghost and the tooltip cleared. The filters stay as the player left them.
book_reset:
    mov     dword [book_scroll], 0
    mov     dword [book_tab], 0
    mov     qword [ghost_rec], 0
    mov     byte [book_tip], 0
    ret

; book_draw(edi x, esi y, edx kind) - the contents of the recipe page, whose top-left corner is at
; (x, y): BOOK_CRAFT (0) or BOOK_FURNACE (1). Draws, handles presses and the wheel, and leaves the
; hovered entry's tooltip in book_tip.
book_draw:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40
    mov     r12d, edi                   ; x
    mov     r13d, esi                   ; y
    mov     ebx, edx                    ; kind
    mov     [book_kind], edx
    mov     byte [book_tip], 0
    call    build_entries
    lea     rdi, [s_recipes]
    lea     esi, [r12 + BOOK_W / 2]
    lea     edx, [r13 + 6]
    mov     ecx, C_RUBRIC
    mov     r8d, 1
    call    ui_text_ink_centered
    ; filter button
    lea     rax, [book_filter]
    mov     r14d, [rax + rbx*4]
    lea     eax, [r14 + rbx*2]
    lea     rcx, [filter_labels]
    mov     rdi, [rcx + rax*8]
    lea     esi, [r12 + 6]
    lea     edx, [r13 + 16]
    mov     ecx, 112
    mov     r8d, 1
    call    ui_button
    test    eax, eax
    jz      .tab
    xor     r14d, 1
    lea     rax, [book_filter]
    mov     [rax + rbx*4], r14d
    mov     dword [book_scroll], 0
.tab:
    mov     dword [rsp + L_TOP], TOP_CRAFT
    mov     dword [rsp + L_ROWS], ROWS_CRAFT
    cmp     ebx, BOOK_FURNACE
    jne     .list
    mov     dword [rsp + L_TOP], TOP_FURNACE
    mov     dword [rsp + L_ROWS], ROWS_FURNACE
    mov     eax, [book_tab]
    lea     rcx, [tab_labels]
    mov     rdi, [rcx + rax*8]
    lea     esi, [r12 + 6]
    lea     edx, [r13 + 38]
    mov     ecx, 112
    mov     r8d, 1
    call    ui_button
    test    eax, eax
    jz      .list
    xor     dword [book_tab], 1
    mov     dword [book_scroll], 0
.list:
    call    collect
    ; rows of the filtered list, the wheel (only over the page), and the scroll limits
    mov     eax, [vis_n]
    add     eax, COLS - 1
    xor     edx, edx
    mov     ecx, COLS
    div     ecx
    mov     [rsp + L_TOTAL], eax
    mov     eax, [ui_mx]
    sub     eax, r12d
    cmp     eax, BOOK_W
    jae     .clamp
    mov     eax, [ui_my]
    sub     eax, r13d
    cmp     eax, BOOK_H
    jae     .clamp
    mov     eax, [book_scroll]
    sub     eax, [ui_input + UIINPUT.scroll] ; wheel up scrolls towards the first row
    mov     [book_scroll], eax
.clamp:
    mov     ecx, [rsp + L_TOTAL]
    sub     ecx, [rsp + L_ROWS]
    xor     edx, edx
    test    ecx, ecx
    cmovs   ecx, edx                    ; the last first-row: rows - visible, at least 0
    mov     eax, [book_scroll]
    cmp     eax, ecx
    cmovg   eax, ecx
    test    eax, eax
    cmovs   eax, edx
    mov     [book_scroll], eax
    ; the cells
    xor     r14d, r14d                  ; cell on screen
.cell:
    mov     eax, [rsp + L_ROWS]
    imul    eax, eax, COLS
    cmp     r14d, eax
    jae     .scrollbar
    mov     eax, [book_scroll]
    imul    eax, eax, COLS
    add     eax, r14d                   ; index in the filtered list
    cmp     eax, [vis_n]
    jae     .scrollbar
    mov     r15d, eax
    mov     eax, r14d
    xor     edx, edx
    mov     ecx, COLS
    div     ecx                         ; eax = row, edx = column
    imul    edx, edx, CELL
    lea     ecx, [r12 + rdx + 6]
    mov     [rsp + L_CX], ecx
    imul    eax, eax, CELL
    add     eax, [rsp + L_TOP]
    add     eax, r13d
    mov     [rsp + L_CY], eax
    lea     rax, [vis_idx]
    movzx   edi, word [rax + r15*2]
    mov     [rsp + L_ENTRY], edi
    cmp     ebx, BOOK_CRAFT
    jne     .stock
    call    entry_rec                   ; craft: the output and its count
    movzx   ecx, byte [rax + 2]
    movzx   edx, byte [rax + 3]
    jmp     .icon
.stock:
    call    entry_id                    ; furnace: the fuel itself, or what the item smelts into
    mov     ecx, eax
    mov     edx, 1
    cmp     dword [book_tab], 0
    jne     .icon
    lea     rax, [item_smelt]
    movzx   ecx, byte [rax + rcx]
.icon:
    shl     edx, 8
    or      ecx, edx
    mov     [rsp + L_STACK], ecx        ; {id, count, 0}
    lea     rdi, [rsp + L_STACK]
    mov     esi, [rsp + L_CX]
    mov     edx, [rsp + L_CY]
    mov     ecx, 1
    call    ui_slot
    mov     [rsp + L_HOVER], eax
    lea     rax, [vis_flag]
    movzx   eax, byte [rax + r15]
    test    eax, F_FITS
    jz      .too_big
    test    eax, F_OK
    jnz     .no_overlay
    mov     r8d, RGBA(150, 32, 28, 90)  ; cannot be made / not owned
    jmp     .overlay
.too_big:
    mov     r8d, C_DIM                  ; does not fit the grid
.overlay:
    mov     edi, [rsp + L_CX]
    inc     edi
    mov     esi, [rsp + L_CY]
    inc     esi
    mov     edx, CELL - 2
    mov     ecx, CELL - 2
    call    ui_rect
.no_overlay:
    cmp     dword [rsp + L_HOVER], 0
    je      .next_cell
    mov     edi, [rsp + L_CX]
    mov     esi, [rsp + L_CY]
    mov     edx, CELL
    mov     ecx, CELL
    mov     r8d, C_GOLD
    call    ui_frame
    lea     rax, [vis_flag]
    movzx   esi, byte [rax + r15]
    mov     edi, [rsp + L_ENTRY]
    call    cell_hover
.next_cell:
    inc     r14d
    jmp     .cell
.scrollbar:
    imul    eax, [rsp + L_ROWS], CELL
    mov     [rsp + L_TRACK], eax
    lea     edi, [r12 + 116]
    mov     esi, [rsp + L_TOP]
    add     esi, r13d
    mov     edx, 2
    mov     ecx, eax
    mov     r8d, C_LOCKED
    call    ui_rect
    mov     r15d, [rsp + L_TRACK]       ; thumb height: the whole track when nothing scrolls
    xor     r14d, r14d                  ; thumb offset
    mov     eax, [rsp + L_TOTAL]
    cmp     eax, [rsp + L_ROWS]
    jbe     .thumb
    mov     eax, [rsp + L_TRACK]        ; track * visible / total rows, at least 6
    imul    eax, [rsp + L_ROWS]
    xor     edx, edx
    div     dword [rsp + L_TOTAL]
    cmp     eax, 6
    jae     .thumb_h
    mov     eax, 6
.thumb_h:
    mov     r15d, eax
    mov     eax, [rsp + L_TRACK]
    sub     eax, r15d
    imul    eax, [book_scroll]
    mov     ecx, [rsp + L_TOTAL]
    sub     ecx, [rsp + L_ROWS]
    xor     edx, edx
    div     ecx                         ; (track - thumb) * scroll / (rows - visible)
    mov     r14d, eax
.thumb:
    lea     edi, [r12 + 116]
    mov     esi, [rsp + L_TOP]
    add     esi, r13d
    add     esi, r14d
    mov     edx, 2
    mov     ecx, r15d
    mov     r8d, C_INK_SOFT
    call    ui_rect
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; book_ghost_draw(edi grid_x, esi grid_y) - the ghost of the recipe the player picked but cannot
; make yet: each empty grid cell its ingredient needs shows that item, faint, and red when the
; inventory plus grid hold fewer of it than the recipe uses. The ghost goes away once the grid
; shows a result.
book_ghost_draw:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24                     ; [rsp] item, +4 icon x, +8 icon y, +12 uses
    cmp     byte [inv + INVENTORY.result + 1], 0
    je      .check
    mov     qword [ghost_rec], 0
.check:
    mov     rbx, [ghost_rec]
    test    rbx, rbx
    jz      .ret
    mov     r12d, edi
    mov     r13d, esi
    xor     r14d, r14d                  ; row
.row:
    xor     r15d, r15d                  ; column
.col:
    movzx   eax, byte [rbx]
    imul    eax, r14d
    add     eax, r15d
    movzx   eax, byte [rbx + 4 + rax]
    test    eax, eax
    jz      .next
    mov     [rsp], eax
    lea     ecx, [r14 + r14*2]
    add     ecx, r15d                   ; grid cell 3 * row + column
    lea     rdx, [inv + INVENTORY.grid]
    cmp     byte [rdx + rcx*4 + 1], 0
    jne     .next                       ; the player already put something there
    imul    ecx, r15d, CELL
    lea     ecx, [r12 + rcx + 1]
    mov     [rsp + 4], ecx
    imul    ecx, r14d, CELL
    lea     ecx, [r13 + rcx + 1]
    mov     [rsp + 8], ecx
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    mov     edx, [rsp + 8]
    mov     ecx, 16
    mov     r8d, RGBA(255, 255, 255, 150)
    call    ui_item_icon_tint
    mov     rdi, rbx
    mov     esi, [rsp]
    call    recipe_uses
    mov     [rsp + 12], eax
    mov     edi, [rsp]
    call    recipe_have
    cmp     eax, [rsp + 12]
    jae     .next
    mov     edi, [rsp + 4]
    mov     esi, [rsp + 8]
    mov     edx, 16
    mov     ecx, 16
    mov     r8d, RGBA(150, 32, 28, 60)
    call    ui_rect
.next:
    inc     r15d
    movzx   eax, byte [rbx]
    cmp     r15d, eax
    jb      .col
    inc     r14d
    movzx   eax, byte [rbx + 1]
    cmp     r14d, eax
    jb      .row
.ret:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
