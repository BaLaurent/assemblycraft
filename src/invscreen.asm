; invscreen.asm - the inventory screens: survival inventory with a 2x2 crafting grid,
; the 3x3 crafting-table screen and the creative item palette. Immediate mode: every
; frame draws the panel and its slots, turns presses on hovered slots into inv_click
; calls, then draws the tooltip and the stack held on the cursor.
; Slot references (inv_click): 0..35 slots, 36..44 grid cells, 45 result. All of them
; address inv + ref*4 (slots, grid and result are contiguous in INVENTORY).
%include "common.inc"
default rel

global screen_inventory, screen_crafting

extern game_mode, frame_input, ui_input, inv, craft_size
extern app_goto, app_entered
extern ui_w, ui_h, ui_mx, ui_my
extern ui_rect, ui_frame, ui_text, ui_text_width, ui_slot, ui_item_icon, ui_tooltip
extern inv_click, inv_close_screen
extern item_names, item_max_stack, i32_to_str

%define PANEL_W     176
%define PANEL_H     166
%define LABEL_COL   RGBA(220, 220, 220, 255)
%define PANEL_COL   RGBA(62, 62, 68, 235)
%define EDGE_COL    RGBA(255, 255, 255, 70)
%define PALETTE_N   23

section .rodata
palette:      db 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
              db 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42
s_inventory:  db "Inventory", 0
s_crafting:   db "Crafting", 0
s_creative:   db "Creative", 0
s_hotbar:     db "Hotbar", 0
s_arrow:      db "->", 0

section .bss
alignb 4
s_px:         resd 1                    ; panel origin in GUI units
s_py:         resd 1
show_counts:  resd 1                    ; draw stack counts on the slots
hover_id:     resd 1                    ; item id under the mouse this frame, 0 = none

section .text

; label(rdi s, esi x, edx y): grey 1x text
label:
    mov     ecx, LABEL_COL
    mov     r8d, 1
    jmp     ui_text

; screen_begin(edi show_counts): reset per-frame state, draw the dimmer and the panel
screen_begin:
    push    rbp
    mov     rbp, rsp
    mov     [show_counts], edi
    mov     dword [hover_id], 0
    mov     eax, [ui_w]
    sub     eax, PANEL_W
    sar     eax, 1
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
    pop     rbp
    ret

; do_close(edi crafting_screen): give grid/cursor items back and return to the game
do_close:
    push    rbp
    mov     rbp, rsp
    test    edi, edi
    jnz     .full
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

; check_close(edi crafting_screen) -> eax 1 if the screen closed. The first frame after
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
.after:
    cmp     byte [rbx + ITEMSTACK.count], 0
    je      .ret
    movzx   eax, byte [rbx + ITEMSTACK.id]
    mov     [hover_id], eax
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
    mov     [hover_id], r12d
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

; draw_overlay(): tooltip (empty cursor only) or the stack carried on the cursor
draw_overlay:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 24                     ; [rsp] count text
    lea     rbx, [inv + INVENTORY.cursor]
    cmp     byte [rbx + ITEMSTACK.count], 0
    jne     .cursor
    mov     eax, [hover_id]
    test    eax, eax
    jz      .ret
    lea     rcx, [item_names]
    mov     rdi, [rcx + rax*8]
    test    rdi, rdi
    jz      .ret
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
    mov     ecx, 0xFFFFFFFF
    mov     r8d, 1
    call    ui_text
.ret:
    add     rsp, 24
    pop     rbx
    pop     rbp
    ret

; screen_inventory(): survival 2x2 inventory, or the creative palette in creative mode
screen_inventory:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    xor     edi, edi
    call    check_close
    test    eax, eax
    jnz     .ret
    xor     edi, edi
    cmp     dword [game_mode], MODE_SURVIVAL
    sete    dil
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
    lea     rdi, [s_arrow]
    lea     esi, [r12 + 138]
    lea     edx, [r13 + 32]
    call    label
    lea     rdi, [inv + INVENTORY.result]
    lea     esi, [r12 + 154]
    lea     edx, [r13 + 28]
    mov     ecx, SLOTREF_RESULT
    call    slot_cell
    mov     edi, r12d
    mov     esi, r13d
    call    draw_player_inv
    jmp     .overlay
.creative:
    lea     rdi, [s_creative]
    lea     esi, [r12 + 8]
    lea     edx, [r13 + 6]
    call    label
    xor     ebx, ebx
.pal:
    mov     eax, ebx
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
    cmp     ebx, PALETTE_N
    jb      .pal
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
    mov     edi, 1
    call    check_close
    test    eax, eax
    jnz     .ret
    mov     edi, 1
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
