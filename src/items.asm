; items.asm - inventory, crafting and tool rules.
; Slot refs map straight onto the INVENTORY struct: ref*4 + inv is a slot (0..35),
; grid cell (36..44) or the craft result (45); ref 46 is the cursor stack.
%include "common.inc"
default rel

global inv, inv_sel, craft_size
global inv_clear, inv_set_creative_default, inv_add, inv_add_dmg, inv_room_for, inv_held
global inv_consume_held, inv_damage_held, inv_find_hotbar, inv_click
global inv_close_screen, craft_update
global item_break_time, item_harvest_drop, item_attack_damage

extern item_max_stack, item_tool, item_tier, item_durability, item_attack
extern block_hardness, block_tool, block_harvest_level, block_drop
extern audio_play, drops_toss

%define CURSOR_COUNT (INVENTORY.cursor + 1)
%define RESULT_COUNT (INVENTORY.result + 1)

section .rodata
align 4
f_pop:    dd 0.5
f_break:  dd 0.9
f_inf:    dd 1.0e30
f_speed:  dd 1.0, 2.0, 4.0, 6.0, 8.0, 12.0 ; dig speed by tool tier (0 = no matching tool)
tier_level: db 0, 1, 2, 3, 4, 1         ; harvest level reached by each tier
align 4
f_hand:   dd 1.5                        ; time factor when the drop is allowed
f_slow:   dd 5.0                        ; time factor when the tool is required but wrong

creative_default: db STONE, DIRT, GRASS, COBBLE, PLANKS, LOG, LEAVES, GLASS, BRICK

; recipe record: w, h, out id, out count, cells[9] (row-major in w x h, 0 = empty)
%macro TOOLS 5                          ; material, pickaxe, axe, shovel, sword
    db 3, 3, %2, 1, %1, %1, %1, 0, STICK, 0, 0, STICK, 0
    db 2, 3, %3, 1, %1, %1, %1, STICK, 0, STICK, 0, 0, 0
    db 2, 3, %3, 1, %1, %1, STICK, %1, STICK, 0, 0, 0, 0
    db 1, 3, %4, 1, %1, STICK, STICK, 0, 0, 0, 0, 0, 0
    db 1, 3, %5, 1, %1, %1, STICK, 0, 0, 0, 0, 0, 0
%endmacro
RECIPE_SIZE equ 13

recipes:
    db 1, 1, PLANKS, 4, LOG, 0, 0, 0, 0, 0, 0, 0, 0
    db 1, 2, STICK, 4, PLANKS, PLANKS, 0, 0, 0, 0, 0, 0, 0
    db 2, 2, CRAFTING_TABLE, 1, PLANKS, PLANKS, PLANKS, PLANKS, 0, 0, 0, 0, 0
    TOOLS PLANKS, WOOD_PICKAXE, WOOD_AXE, WOOD_SHOVEL, WOOD_SWORD
    TOOLS COBBLE, STONE_PICKAXE, STONE_AXE, STONE_SHOVEL, STONE_SWORD
recipes_end:

section .data
align 4
inv_sel:    dd 0
craft_size: dd 2                        ; 2 = inventory grid, 3 = crafting table

section .bss
align 4
inv: resb INVENTORY_size

section .text

; inv_clear() - empties every slot, the grid, the result and the cursor
inv_clear:
    lea     rdi, [inv]
    mov     ecx, INVENTORY_size / 4
    xor     eax, eax
    rep     stosd
    ret

; inv_set_creative_default() - hotbar = the nine creative blocks, count 1
inv_set_creative_default:
    lea     rsi, [creative_default]
    lea     rdi, [inv]
    xor     ecx, ecx
.l:
    movzx   eax, byte [rsi + rcx]
    or      eax, 0x100                  ; count 1, dmg 0
    mov     [rdi + rcx*4], eax
    inc     ecx
    cmp     ecx, HOTBAR_SLOTS
    jb      .l
    ret

; add_range(edi id, esi count, edx dmg, ecx lo, r8d hi) -> eax leftover
; Fills slots [lo, hi): merges into same-id undamaged stacks first, then empty slots.
add_range:
    mov     edi, edi
    lea     rax, [item_max_stack]
    movzx   r10d, byte [rax + rdi]
    test    r10d, r10d
    jz      .done                       ; not an item: nothing fits
    mov     r9d, ecx
    test    edx, edx
    jnz     .pass2                      ; damaged tools never merge
    mov     r11d, r9d
.p1:
    cmp     r11d, r8d
    jae     .pass2
    test    esi, esi
    jz      .done
    lea     rax, [inv]
    lea     rax, [rax + r11*4]
    cmp     byte [rax], dil
    jne     .p1n
    cmp     word [rax + 2], 0
    jne     .p1n
    movzx   ecx, byte [rax + 1]
    cmp     ecx, r10d
    jae     .p1n
    neg     ecx
    add     ecx, r10d                   ; room in this stack
    cmp     ecx, esi
    cmova   ecx, esi
    add     [rax + 1], cl
    sub     esi, ecx
.p1n:
    inc     r11d
    jmp     .p1
.pass2:
    mov     r11d, r9d
.p2:
    cmp     r11d, r8d
    jae     .done
    test    esi, esi
    jz      .done
    lea     rax, [inv]
    lea     rax, [rax + r11*4]
    cmp     byte [rax + 1], 0
    jne     .p2n
    mov     ecx, esi
    cmp     ecx, r10d
    cmova   ecx, r10d                   ; take = min(count, max)
    mov     [rax], dil
    mov     [rax + 1], cl
    mov     [rax + 2], dx
    sub     esi, ecx
.p2n:
    inc     r11d
    jmp     .p2
.done:
    mov     eax, esi
    ret

; inv_add(edi id, esi count) -> eax leftover that did not fit
inv_add:
    xor     edx, edx
; inv_add_dmg(edi id, esi count, edx dmg) -> eax leftover (damaged tools never merge)
inv_add_dmg:
    xor     ecx, ecx
    mov     r8d, INV_SLOTS
    jmp     add_range

; inv_room_for(edi id) -> eax how many of this item fit in the 36 slots
inv_room_for:
    mov     edi, edi
    lea     rax, [item_max_stack]
    movzx   r10d, byte [rax + rdi]
    xor     eax, eax
    test    r10d, r10d
    jz      .ret
    lea     rsi, [inv]
    xor     ecx, ecx
.l:
    cmp     byte [rsi + rcx*4 + 1], 0
    jne     .occ
    add     eax, r10d
    jmp     .n
.occ:
    cmp     byte [rsi + rcx*4], dil
    jne     .n
    cmp     word [rsi + rcx*4 + 2], 0
    jne     .n
    movzx   edx, byte [rsi + rcx*4 + 1]
    cmp     edx, r10d
    jae     .n
    add     eax, r10d
    sub     eax, edx
.n:
    inc     ecx
    cmp     ecx, INV_SLOTS
    jb      .l
.ret:
    ret

; rax = &inv.slots[inv_sel] (clobbers rcx)
%macro HELD_RAX 0
    mov     eax, [inv_sel]
    lea     rcx, [inv]
    lea     rax, [rcx + rax*4]
%endmacro

; inv_held() -> rax ITEMSTACK*
inv_held:
    HELD_RAX
    ret

; inv_consume_held(edi n)
inv_consume_held:
    HELD_RAX
    movzx   ecx, byte [rax + 1]
    cmp     ecx, edi
    ja      .sub
    mov     dword [rax], 0
    ret
.sub:
    sub     [rax + 1], dil
    ret

; inv_damage_held(edi amount) -> eax 1 if the held tool broke
inv_damage_held:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    HELD_RAX
    mov     rbx, rax
    movzx   ecx, byte [rbx]
    lea     rdx, [item_tool]
    cmp     byte [rdx + rcx], 0
    je      .no
    lea     rdx, [item_durability]
    movzx   edx, word [rdx + rcx*2]
    movzx   eax, word [rbx + 2]
    add     eax, edi
    cmp     eax, edx
    jae     .break
    mov     [rbx + 2], ax
.no:
    xor     eax, eax
    jmp     .ret
.break:
    mov     dword [rbx], 0
    mov     edi, SND_TOOL_BREAK
    movss   xmm0, [f_break]
    call    audio_play
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; inv_find_hotbar(edi id) -> eax slot 0..8 or -1
inv_find_hotbar:
    lea     rsi, [inv]
    xor     ecx, ecx
.l:
    cmp     byte [rsi + rcx*4 + 1], 0
    je      .n
    cmp     byte [rsi + rcx*4], dil
    je      .found
.n:
    inc     ecx
    cmp     ecx, HOTBAR_SLOTS
    jb      .l
    mov     eax, -1
    ret
.found:
    mov     eax, ecx
    ret

; craft_update() - recomputes inv.result from the active craft_size x craft_size grid
craft_update:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    lea     r8, [inv]
    mov     r9d, [craft_size]
    mov     r10d, 9                     ; min row
    mov     r11d, -1                    ; max row
    mov     esi, 9                      ; min col
    mov     edi, -1                     ; max col
    xor     eax, eax
.r:
    xor     ecx, ecx
.c:
    lea     edx, [rax + rax*2]
    add     edx, ecx
    cmp     byte [r8 + INVENTORY.grid + rdx*4 + 1], 0
    je      .cn
    cmp     eax, r10d
    cmovl   r10d, eax
    cmp     eax, r11d
    cmovg   r11d, eax
    cmp     ecx, esi
    cmovl   esi, ecx
    cmp     ecx, edi
    cmovg   edi, ecx
.cn:
    inc     ecx
    cmp     ecx, r9d
    jb      .c
    inc     eax
    cmp     eax, r9d
    jb      .r
    cmp     r11d, -1
    je      .empty
    sub     edi, esi
    inc     edi                         ; w
    sub     r11d, r10d
    inc     r11d                        ; h
    lea     eax, [r10 + r10*2]
    add     eax, esi
    lea     r12, [r8 + rax*4 + INVENTORY.grid]  ; top-left of the bounding box
    lea     rbx, [recipes]
    lea     r9, [recipes_end]
.rec:
    cmp     rbx, r9
    jae     .empty
    movzx   eax, byte [rbx]
    cmp     eax, edi
    jne     .next
    movzx   eax, byte [rbx + 1]
    cmp     eax, r11d
    jne     .next
    lea     r14, [rbx + 4]
    mov     r13, r12
    xor     r15d, r15d
.row:
    xor     ecx, ecx
.col:
    xor     edx, edx
    cmp     byte [r13 + rcx*4 + 1], 0
    je      .g0
    movzx   edx, byte [r13 + rcx*4]
.g0:
    cmp     dl, [r14]
    jne     .next
    inc     r14
    inc     ecx
    cmp     ecx, edi
    jb      .col
    add     r13, 12                     ; next grid row (3 cells * 4 bytes)
    inc     r15d
    cmp     r15d, r11d
    jb      .row
    movzx   eax, byte [rbx + 2]
    movzx   edx, byte [rbx + 3]
    shl     edx, 8
    or      eax, edx
    mov     [r8 + INVENTORY.result], eax
    jmp     .ret
.next:
    add     rbx, RECIPE_SIZE
    jmp     .rec
.empty:
    mov     dword [r8 + INVENTORY.result], 0
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; craft_consume() - removes 1 from every non-empty active grid cell, then craft_update
craft_consume:
    push    rbp
    mov     rbp, rsp
    lea     rsi, [inv]
    mov     r8d, [craft_size]
    xor     eax, eax
.r:
    xor     ecx, ecx
.c:
    lea     edx, [rax + rax*2]
    add     edx, ecx
    lea     rdx, [rsi + rdx*4 + INVENTORY.grid]
    cmp     byte [rdx + 1], 0
    je      .n
    dec     byte [rdx + 1]
    jnz     .n
    mov     dword [rdx], 0
.n:
    inc     ecx
    cmp     ecx, r8d
    jb      .c
    inc     eax
    cmp     eax, r8d
    jb      .r
    call    craft_update
    pop     rbp
    ret

; return_stack(rdi ITEMSTACK*) - adds the stack to the inventory, tosses what does not fit
; in front of the player, clears it
return_stack:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdi
    cmp     byte [rbx + 1], 0
    je      .z
    movzx   edi, byte [rbx]
    movzx   esi, byte [rbx + 1]
    movzx   edx, word [rbx + 2]
    call    inv_add_dmg
    test    eax, eax
    jz      .z
    movzx   edi, byte [rbx]
    mov     esi, eax
    movzx   edx, word [rbx + 2]
    call    drops_toss
.z:
    mov     dword [rbx], 0
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; inv_close_screen() - grid and cursor items go back to the inventory
inv_close_screen:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    lea     rbx, [inv + INVENTORY.grid]
    xor     r12d, r12d
.l:
    lea     rdi, [rbx + r12*4]
    call    return_stack
    inc     r12d
    cmp     r12d, 9
    jb      .l
    lea     rdi, [inv + INVENTORY.cursor]
    call    return_stack
    mov     dword [craft_size], 2
    call    craft_update
    pop     r12
    pop     rbx
    pop     rbp
    ret

; inv_click(edi slotref, esi button 0 left/1 right, edx shift) -> eax 1 if anything changed
inv_click:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r13d, edi                   ; ref
    mov     r14d, esi                   ; button
    mov     r15d, edx                   ; shift
    lea     r12, [inv]
    cmp     r13d, SLOTREF_RESULT
    ja      .none
    je      .result
    lea     rbx, [r12 + r13*4]          ; the clicked stack
    test    r15d, r15d
    jnz     .shift
    test    r14d, r14d
    jnz     .right

    ; left click: take / put / merge / swap
    cmp     byte [r12 + CURSOR_COUNT], 0
    jne     .l_cur
    cmp     byte [rbx + 1], 0
    je      .none
    mov     eax, [rbx]
    mov     [r12 + INVENTORY.cursor], eax
    mov     dword [rbx], 0
    jmp     .changed
.l_cur:
    cmp     byte [rbx + 1], 0
    jne     .l_both
    mov     eax, [r12 + INVENTORY.cursor]
    mov     [rbx], eax
    mov     dword [r12 + INVENTORY.cursor], 0
    jmp     .changed
.l_both:
    mov     eax, [rbx]
    mov     ecx, [r12 + INVENTORY.cursor]
    cmp     al, cl
    jne     .swap
    test    eax, 0xFFFF0000
    jnz     .swap
    test    ecx, 0xFFFF0000
    jnz     .swap
    movzx   edx, al
    lea     rsi, [item_max_stack]
    movzx   edx, byte [rsi + rdx]       ; max
    cmp     edx, 1
    jbe     .swap
    movzx   esi, byte [rbx + 1]
    cmp     edx, esi
    jbe     .none                       ; stack already full
    sub     edx, esi                    ; room
    movzx   ecx, byte [r12 + CURSOR_COUNT]
    cmp     ecx, edx
    cmova   ecx, edx                    ; n = min(cursor, room)
    add     [rbx + 1], cl
    sub     [r12 + CURSOR_COUNT], cl
    jnz     .changed
    mov     dword [r12 + INVENTORY.cursor], 0
    jmp     .changed

    ; right click: split / place one / add one / swap
.right:
    cmp     byte [r12 + CURSOR_COUNT], 0
    jne     .r_cur
    cmp     byte [rbx + 1], 0
    je      .none
    movzx   ecx, byte [rbx + 1]
    lea     eax, [rcx + 1]
    shr     eax, 1                      ; cursor takes ceil(n/2)
    mov     edx, [rbx]
    mov     [r12 + INVENTORY.cursor], edx
    mov     [r12 + CURSOR_COUNT], al
    sub     ecx, eax
    jnz     .r_keep
    mov     dword [rbx], 0
    jmp     .changed
.r_keep:
    mov     [rbx + 1], cl
    jmp     .changed
.r_cur:
    cmp     byte [rbx + 1], 0
    jne     .r_both
    mov     eax, [r12 + INVENTORY.cursor]
    mov     [rbx], eax
    mov     byte [rbx + 1], 1
    dec     byte [r12 + CURSOR_COUNT]
    jnz     .changed
    mov     dword [r12 + INVENTORY.cursor], 0
    jmp     .changed
.r_both:
    mov     eax, [rbx]
    mov     ecx, [r12 + INVENTORY.cursor]
    cmp     al, cl
    jne     .swap
    test    eax, 0xFFFF0000
    jnz     .swap
    test    ecx, 0xFFFF0000
    jnz     .swap
    movzx   edx, al
    lea     rsi, [item_max_stack]
    movzx   edx, byte [rsi + rdx]
    movzx   esi, byte [rbx + 1]
    cmp     esi, edx
    jae     .swap
    inc     byte [rbx + 1]
    dec     byte [r12 + CURSOR_COUNT]
    jnz     .changed
    mov     dword [r12 + INVENTORY.cursor], 0
    jmp     .changed
.swap:
    mov     eax, [rbx]
    mov     ecx, [r12 + INVENTORY.cursor]
    mov     [rbx], ecx
    mov     [r12 + INVENTORY.cursor], eax
    jmp     .changed

    ; shift click: move between hotbar and main, or grid -> inventory
.shift:
    cmp     byte [rbx + 1], 0
    je      .none
    movzx   edi, byte [rbx]
    movzx   esi, byte [rbx + 1]
    movzx   edx, word [rbx + 2]
    mov     ecx, HOTBAR_SLOTS           ; hotbar -> main [9, 36)
    mov     r8d, INV_SLOTS
    cmp     r13d, HOTBAR_SLOTS
    jb      .sh_go
    xor     ecx, ecx                    ; main -> hotbar [0, 9)
    mov     r8d, HOTBAR_SLOTS
    cmp     r13d, SLOTREF_GRID
    jb      .sh_go
    mov     r8d, INV_SLOTS              ; grid -> anywhere [0, 36)
.sh_go:
    call    add_range
    movzx   ecx, byte [rbx + 1]
    cmp     eax, ecx
    je      .none                       ; nothing moved
    test    eax, eax
    jnz     .sh_left
    mov     dword [rbx], 0
    jmp     .changed
.sh_left:
    mov     [rbx + 1], al
    jmp     .changed

    ; craft result
.result:
    cmp     byte [r12 + RESULT_COUNT], 0
    je      .none
    test    r15d, r15d
    jnz     .res_shift
    cmp     byte [r12 + CURSOR_COUNT], 0
    jne     .res_cur
    mov     eax, [r12 + INVENTORY.result]
    mov     [r12 + INVENTORY.cursor], eax
    jmp     .crafted
.res_cur:
    mov     eax, [r12 + INVENTORY.result]
    mov     ecx, [r12 + INVENTORY.cursor]
    cmp     al, cl
    jne     .none
    test    ecx, 0xFFFF0000
    jnz     .none
    movzx   edx, al
    lea     rsi, [item_max_stack]
    movzx   edx, byte [rsi + rdx]
    movzx   esi, byte [r12 + CURSOR_COUNT]
    movzx   eax, byte [r12 + RESULT_COUNT]
    add     esi, eax
    cmp     esi, edx
    ja      .none
    mov     [r12 + CURSOR_COUNT], sil
    jmp     .crafted
.res_shift:
    xor     r14d, r14d                  ; crafted at least once
.rs_loop:
    cmp     byte [r12 + RESULT_COUNT], 0
    je      .rs_done
    movzx   edi, byte [r12 + INVENTORY.result]
    call    inv_room_for
    movzx   ecx, byte [r12 + RESULT_COUNT]
    cmp     eax, ecx
    jb      .rs_done
    movzx   edi, byte [r12 + INVENTORY.result]
    movzx   esi, byte [r12 + RESULT_COUNT]
    xor     edx, edx
    xor     ecx, ecx
    mov     r8d, INV_SLOTS
    call    add_range
    call    craft_consume
    mov     r14d, 1
    jmp     .rs_loop
.rs_done:
    test    r14d, r14d
    jz      .none
    jmp     .pop
.crafted:
    call    craft_consume
.pop:
    mov     edi, SND_POP
    movss   xmm0, [f_pop]
    call    audio_play
    mov     eax, 1
    jmp     .out
.changed:
    cmp     r13d, SLOTREF_GRID
    jb      .one
    call    craft_update                ; a grid cell changed
.one:
    mov     eax, 1
    jmp     .out
.none:
    xor     eax, eax
.out:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; harvest_info(edi block, esi held) -> eax 1 if the drop is allowed,
; edx = tier of the held tool when it matches the block's tool kind, else 0
harvest_info:
    lea     rax, [block_tool]
    movzx   eax, byte [rax + rdi]
    lea     rcx, [item_tool]
    movzx   ecx, byte [rcx + rsi]
    xor     edx, edx
    xor     r8d, r8d
    test    eax, eax
    jz      .nomatch
    cmp     eax, ecx
    jne     .nomatch
    lea     rcx, [item_tier]
    movzx   edx, byte [rcx + rsi]
    mov     r8d, 1
.nomatch:
    lea     rcx, [block_harvest_level]
    movzx   ecx, byte [rcx + rdi]
    mov     eax, 1
    test    ecx, ecx
    jz      .ret                        ; can = level == 0 || (match && tier_level >= level)
    xor     eax, eax
    test    r8d, r8d
    jz      .ret
    lea     r9, [tier_level]
    cmp     [r9 + rdx], cl
    setae   al
.ret:
    ret

; item_break_time(edi block, esi held_id) -> xmm0 seconds (1e30 = unbreakable)
item_break_time:
    push    rbp
    mov     rbp, rsp
    mov     edi, edi
    mov     esi, esi
    lea     rax, [block_hardness]
    movss   xmm1, [rax + rdi*4]
    xorps   xmm2, xmm2
    comiss  xmm1, xmm2
    jb      .unbreakable
    call    harvest_info                ; keeps xmm1
    lea     rcx, [f_speed]
    movss   xmm0, [rcx + rdx*4]         ; speed
    movss   xmm2, [f_hand]
    test    eax, eax
    jnz     .calc
    movss   xmm2, [f_slow]
.calc:
    mulss   xmm1, xmm2
    divss   xmm1, xmm0
    movaps  xmm0, xmm1
    pop     rbp
    ret
.unbreakable:
    movss   xmm0, [f_inf]
    pop     rbp
    ret

; item_harvest_drop(edi block, esi held_id) -> eax item id dropped, 0 for none
item_harvest_drop:
    push    rbp
    mov     rbp, rsp
    mov     edi, edi
    mov     esi, esi
    call    harvest_info
    test    eax, eax
    jz      .ret
    lea     rcx, [block_drop]
    movzx   eax, byte [rcx + rdi]
.ret:
    pop     rbp
    ret

; item_attack_damage(edi id) -> eax damage (1 bare-handed)
item_attack_damage:
    mov     edi, edi
    mov     eax, 1
    test    edi, edi
    jz      .ret
    cmp     edi, NUM_ITEMS
    jae     .ret
    lea     rax, [item_attack]
    movzx   eax, byte [rax + rdi]
.ret:
    ret
