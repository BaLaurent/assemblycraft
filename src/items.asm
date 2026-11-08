; items.asm - inventory, crafting and tool rules.
; Slot refs map straight onto the INVENTORY struct: ref*4 + inv is a slot (0..35), grid cell
; (36..44), the craft result (45), the cursor stack (46, never clickable) or a worn armor
; piece (47..50). Refs 51..77 are the cells of the open furnace/chest (inv_container).
%include "common.inc"
default rel

global inv, inv_sel, craft_size, inv_container
global inv_clear, inv_set_creative_default, inv_add, inv_add_dmg, inv_room_for, inv_held
global inv_consume_held, inv_damage_held, inv_find_hotbar, inv_click
global inv_close_screen, craft_update, inv_count, inv_remove_one, armor_points, armor_wear
global item_break_time, item_harvest_drop, item_attack_damage
global recipes, recipes_end

extern item_max_stack, item_tool, item_tier, item_durability, item_attack
extern item_burn, item_smelt, item_armor_slot, item_armor_points
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
%macro ARMOR 5                          ; material, helmet, chestplate, leggings, boots
    db 3, 2, %2, 1, %1, %1, %1, %1, 0, %1, 0, 0, 0
    db 3, 3, %3, 1, %1, 0, %1, %1, %1, %1, %1, %1, %1
    db 3, 3, %4, 1, %1, %1, %1, %1, 0, %1, %1, 0, %1
    db 3, 2, %5, 1, %1, 0, %1, %1, 0, %1, 0, 0, 0
%endmacro
; records with the same output must be adjacent (the recipe book groups runs of them)
%macro STORAGE 2                        ; material, block: 3x3 to the block, 1x1 back to 9
    db 3, 3, %2, 1, %1, %1, %1, %1, %1, %1, %1, %1, %1
    db 1, 1, %1, 9, %2, 0, 0, 0, 0, 0, 0, 0, 0
%endmacro
%macro STAIRS 2                         ; material, stairs: two mirrored records
    db 3, 3, %2, 4, %1, 0, 0, %1, %1, 0, %1, %1, %1
    db 3, 3, %2, 4, 0, 0, %1, 0, %1, %1, %1, %1, %1
%endmacro

recipes:
    db 1, 1, PLANKS, 4, LOG, 0, 0, 0, 0, 0, 0, 0, 0
    db 1, 2, STICK, 4, PLANKS, PLANKS, 0, 0, 0, 0, 0, 0, 0
    db 2, 2, CRAFTING_TABLE, 1, PLANKS, PLANKS, PLANKS, PLANKS, 0, 0, 0, 0, 0
    TOOLS PLANKS, WOOD_PICKAXE, WOOD_AXE, WOOD_SHOVEL, WOOD_SWORD
    TOOLS COBBLE, STONE_PICKAXE, STONE_AXE, STONE_SHOVEL, STONE_SWORD
    db 3, 3, FURNACE, 1, COBBLE, COBBLE, COBBLE, COBBLE, 0, COBBLE, COBBLE, COBBLE, COBBLE
    db 3, 3, CHEST, 1, PLANKS, PLANKS, PLANKS, PLANKS, 0, PLANKS, PLANKS, PLANKS, PLANKS
    TOOLS IRON_INGOT, IRON_PICKAXE, IRON_AXE, IRON_SHOVEL, IRON_SWORD
    TOOLS GOLD_INGOT, GOLD_PICKAXE, GOLD_AXE, GOLD_SHOVEL, GOLD_SWORD
    TOOLS DIAMOND, DIAMOND_PICKAXE, DIAMOND_AXE, DIAMOND_SHOVEL, DIAMOND_SWORD
    db 3, 3, BOW, 1, 0, STICK, STRING, STICK, 0, STRING, 0, STICK, STRING
    db 3, 3, BOW, 1, STRING, STICK, 0, STRING, 0, STICK, STRING, STICK, 0
    db 1, 3, ARROW, 4, FLINT, STICK, FEATHER, 0, 0, 0, 0, 0, 0
    db 2, 2, FLINT_AND_STEEL, 1, IRON_INGOT, 0, 0, FLINT, 0, 0, 0, 0, 0
    db 2, 2, FLINT_AND_STEEL, 1, 0, IRON_INGOT, FLINT, 0, 0, 0, 0, 0, 0
    db 2, 1, FLINT_AND_STEEL, 1, IRON_INGOT, FLINT, 0, 0, 0, 0, 0, 0, 0
    db 3, 3, TNT, 1, GUNPOWDER, SAND, GUNPOWDER, SAND, GUNPOWDER, SAND, GUNPOWDER, SAND, GUNPOWDER
    ARMOR IRON_INGOT, IRON_HELMET, IRON_CHESTPLATE, IRON_LEGGINGS, IRON_BOOTS
    ARMOR GOLD_INGOT, GOLD_HELMET, GOLD_CHESTPLATE, GOLD_LEGGINGS, GOLD_BOOTS
    ARMOR DIAMOND, DIAMOND_HELMET, DIAMOND_CHESTPLATE, DIAMOND_LEGGINGS, DIAMOND_BOOTS
%define I IRON_INGOT
    db 2, 2, PISTOL, 1, I, I, 0, PLANKS, 0, 0, 0, 0, 0
    db 3, 3, MUSKET, 1, 0, 0, I, 0, I, FLINT_AND_STEEL, LOG, 0, 0
    db 3, 2, SHOTGUN, 1, I, I, I, 0, PLANKS, PLANKS, 0, 0, 0
    db 3, 3, KALASHNIKOV, 1, I, I, I, 0, DIAMOND, I, 0, PLANKS, I
    db 3, 3, ROCKET_LAUNCHER, 1, I, I, I, DIAMOND, 0, DIAMOND, I, I, I
    db 1, 2, PISTOL_ROUND, 8, I, GUNPOWDER, 0, 0, 0, 0, 0, 0, 0
    db 2, 1, MUSKET_BALL, 4, I, GUNPOWDER, 0, 0, 0, 0, 0, 0, 0
    db 1, 3, SHOTGUN_SHELL, 4, I, GUNPOWDER, FEATHER, 0, 0, 0, 0, 0, 0
    db 1, 3, RIFLE_ROUND, 16, I, GUNPOWDER, GUNPOWDER, 0, 0, 0, 0, 0, 0
    db 1, 3, ROCKET, 1, I, TNT, GUNPOWDER, 0, 0, 0, 0, 0, 0
%undef I
    db 2, 2, STONE_BRICK, 4, STONE, STONE, STONE, STONE, 0, 0, 0, 0, 0
    db 1, 2, IRON_DAGGER, 1, IRON_INGOT, STICK, 0, 0, 0, 0, 0, 0, 0
    db 1, 2, DIAMOND_DAGGER, 1, DIAMOND, STICK, 0, 0, 0, 0, 0, 0, 0
    db 3, 3, STAFF, 1, 0, 0, GOLD_INGOT, 0, STICK, 0, STICK, 0, 0
    db 1, 2, HEALTH_POTION, 1, APPLE, GLASS, 0, 0, 0, 0, 0, 0, 0
    db 1, 2, MANA_POTION, 1, GOLD_INGOT, GLASS, 0, 0, 0, 0, 0, 0, 0
    db 2, 2, SANDSTONE, 1, SAND, SAND, SAND, SAND, 0, 0, 0, 0, 0
    db 2, 1, MOSSY_COBBLESTONE, 1, COBBLE, LEAVES, 0, 0, 0, 0, 0, 0, 0
    db 2, 1, MOSSY_STONE_BRICK, 1, STONE_BRICK, LEAVES, 0, 0, 0, 0, 0, 0, 0
    db 3, 3, BOOKSHELF, 1, PLANKS, PLANKS, PLANKS, STICK, STICK, STICK, PLANKS, PLANKS, PLANKS
    db 2, 2, WOOL, 1, STRING, STRING, STRING, STRING, 0, 0, 0, 0, 0
    STORAGE IRON_INGOT, IRON_BLOCK
    STORAGE GOLD_INGOT, GOLD_BLOCK
    STORAGE DIAMOND, DIAMOND_BLOCK
    STORAGE COAL, COAL_BLOCK
    db 3, 1, PLANK_SLAB, 6, PLANKS, PLANKS, PLANKS, 0, 0, 0, 0, 0, 0
    db 3, 1, COBBLE_SLAB, 6, COBBLE, COBBLE, COBBLE, 0, 0, 0, 0, 0, 0
    db 3, 1, STONE_BRICK_SLAB, 6, STONE_BRICK, STONE_BRICK, STONE_BRICK, 0, 0, 0, 0, 0, 0
    db 3, 1, BRICK_SLAB, 6, BRICK, BRICK, BRICK, 0, 0, 0, 0, 0, 0
    db 3, 1, SANDSTONE_SLAB, 6, SANDSTONE, SANDSTONE, SANDSTONE, 0, 0, 0, 0, 0, 0
    STAIRS PLANKS, PLANK_STAIRS
    STAIRS COBBLE, COBBLE_STAIRS
    STAIRS STONE_BRICK, STONE_BRICK_STAIRS
    STAIRS BRICK, BRICK_STAIRS
    STAIRS SANDSTONE, SANDSTONE_STAIRS
    db 2, 3, WOOD_DOOR, 3, PLANKS, PLANKS, PLANKS, PLANKS, PLANKS, PLANKS, 0, 0, 0
    db 2, 3, IRON_DOOR, 3, IRON_INGOT, IRON_INGOT, IRON_INGOT, IRON_INGOT, IRON_INGOT, IRON_INGOT, 0, 0, 0
    db 3, 2, TRAPDOOR, 2, PLANKS, PLANKS, PLANKS, PLANKS, PLANKS, PLANKS, 0, 0, 0
    db 3, 3, LADDER, 3, STICK, 0, STICK, STICK, STICK, STICK, STICK, 0, STICK
    db 1, 2, TORCH, 4, COAL, STICK, 0, 0, 0, 0, 0, 0, 0
    db 3, 2, FENCE, 3, PLANKS, STICK, PLANKS, PLANKS, STICK, PLANKS, 0, 0, 0
    db 3, 2, GLASS_PANE, 16, GLASS, GLASS, GLASS, GLASS, GLASS, GLASS, 0, 0, 0
recipes_end:

section .data
align 4
inv_sel:    dd 0
craft_size: dd 2                        ; 2 = inventory grid, 3 = crafting table

section .bss
align 4
inv: resb INVENTORY_size
alignb 8
inv_container: resq 1                   ; CONTAINER* of the open furnace/chest, or 0

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

; add_cells(rdi base, esi ncells, edx id, ecx count, r8d dmg) -> eax leftover
; Fills the ncells stacks at base: merges into same-id undamaged stacks first (a damaged item
; never merges), then empty cells, each stack capped at item_max_stack.
add_cells:
    mov     eax, edx
    lea     r9, [item_max_stack]
    movzx   r10d, byte [r9 + rax]
    mov     eax, ecx                    ; eax = count still to place
    test    r10d, r10d
    jz      .done                       ; not an item: nothing fits
    mov     r9d, esi                    ; r9d = ncells
    test    r8d, r8d
    jnz     .pass2                      ; damaged tools never merge
    xor     r11d, r11d
.p1:
    cmp     r11d, r9d
    jae     .pass2
    test    eax, eax
    jz      .done
    lea     rsi, [rdi + r11*4]
    cmp     byte [rsi], dl
    jne     .p1n
    cmp     word [rsi + 2], 0
    jne     .p1n
    movzx   ecx, byte [rsi + 1]
    cmp     ecx, r10d
    jae     .p1n
    neg     ecx
    add     ecx, r10d                   ; room in this stack
    cmp     ecx, eax
    cmova   ecx, eax
    add     [rsi + 1], cl
    sub     eax, ecx
.p1n:
    inc     r11d
    jmp     .p1
.pass2:
    xor     r11d, r11d
.p2:
    cmp     r11d, r9d
    jae     .done
    test    eax, eax
    jz      .done
    lea     rsi, [rdi + r11*4]
    cmp     byte [rsi + 1], 0
    jne     .p2n
    mov     ecx, eax
    cmp     ecx, r10d
    cmova   ecx, r10d                   ; take = min(count, max)
    mov     [rsi], dl
    mov     [rsi + 1], cl
    mov     [rsi + 2], r8w
    sub     eax, ecx
.p2n:
    inc     r11d
    jmp     .p2
.done:
    ret

; inv_add(edi id, esi count) -> eax leftover that did not fit
inv_add:
    xor     edx, edx
; inv_add_dmg(edi id, esi count, edx dmg) -> eax leftover (damaged tools never merge)
inv_add_dmg:
    mov     ecx, esi                    ; add_cells(inv, 36, id, count, dmg)
    mov     r8d, edx
    mov     edx, edi
    lea     rdi, [inv]
    mov     esi, INV_SLOTS
    jmp     add_cells

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
    lea     rdx, [item_durability]
    movzx   edx, word [rdx + rcx*2]
    test    edx, edx
    jz      .no                         ; no durability: the item never wears
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

; inv_count(edi id) -> eax total of that item over the 36 slots
inv_count:
    lea     rsi, [inv]
    xor     eax, eax
    xor     ecx, ecx
.l:
    cmp     byte [rsi + rcx*4], dil
    jne     .n
    movzx   edx, byte [rsi + rcx*4 + 1]
    add     eax, edx
.n:
    inc     ecx
    cmp     ecx, INV_SLOTS
    jb      .l
    ret

; inv_remove_one(edi id) -> eax 1 if one was taken from the first of the 36 slots holding it
inv_remove_one:
    lea     rsi, [inv]
    xor     ecx, ecx
.l:
    cmp     byte [rsi + rcx*4 + 1], 0
    je      .n
    cmp     byte [rsi + rcx*4], dil
    je      .found
.n:
    inc     ecx
    cmp     ecx, INV_SLOTS
    jb      .l
    xor     eax, eax
    ret
.found:
    dec     byte [rsi + rcx*4 + 1]
    jnz     .ok
    mov     dword [rsi + rcx*4], 0
.ok:
    mov     eax, 1
    ret

; armor_points() -> eax sum of item_armor_points over the worn pieces
armor_points:
    lea     rsi, [inv + INVENTORY.armor]
    lea     r8, [item_armor_points]
    xor     eax, eax
    xor     ecx, ecx
.l:
    cmp     byte [rsi + rcx*4 + 1], 0
    je      .n
    movzx   edx, byte [rsi + rcx*4]
    movzx   edx, byte [r8 + rdx]
    add     eax, edx
.n:
    inc     ecx
    cmp     ecx, 4
    jb      .l
    ret

; armor_wear() - every worn piece takes 1 damage; one that reaches its durability breaks
armor_wear:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    lea     rbx, [inv + INVENTORY.armor]
    xor     r12d, r12d
.l:
    cmp     byte [rbx + r12*4 + 1], 0
    je      .n
    movzx   ecx, byte [rbx + r12*4]
    lea     rdx, [item_durability]
    movzx   edx, word [rdx + rcx*2]
    movzx   eax, word [rbx + r12*4 + 2]
    inc     eax
    cmp     eax, edx
    jae     .break
    mov     [rbx + r12*4 + 2], ax
    jmp     .n
.break:
    mov     dword [rbx + r12*4], 0
    mov     edi, SND_TOOL_BREAK
    movss   xmm0, [f_break]
    call    audio_play
.n:
    inc     r12d
    cmp     r12d, 4
    jb      .l
    pop     r12
    pop     rbx
    pop     rbp
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

; inv_close_screen() - grid and cursor items go back to the inventory; no container stays open
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
    mov     qword [inv_container], 0
    mov     dword [craft_size], 2
    call    craft_update
    pop     r12
    pop     rbx
    pop     rbp
    ret

; inv_click(edi slotref, esi button 0 left/1 right, edx shift) -> eax 1 if anything changed
; Refs: 0..35 slots, 36..44 grid, 45 craft result, 46 none (the cursor), 47..50 armor,
; 51..77 cells of the open container (inv_container)
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
    je      .result
    ja      .high
    lea     rbx, [r12 + r13*4]          ; slot or grid cell: inv + ref*4
    jmp     .have
.high:
    cmp     r13d, SLOTREF_ARMOR
    jb      .none                       ; 46: the cursor is never clickable
    cmp     r13d, SLOTREF_CONTAINER
    jb      .armor_cell
    cmp     r13d, SLOTREF_CONTAINER + 26
    ja      .none
    mov     rax, [inv_container]
    test    rax, rax
    jz      .none
    lea     ecx, [r13 - SLOTREF_CONTAINER]
    cmp     byte [rax + CONTAINER.kind], CONT_FURNACE
    jne     .cont_cell
    cmp     ecx, 2
    ja      .none                       ; a furnace has three cells
.cont_cell:
    lea     rbx, [rax + CONTAINER.slots + rcx*4]
    jmp     .have
.armor_cell:
    lea     rbx, [r12 + r13*4]          ; the armor row follows the cursor: inv + ref*4
.have:
    test    r15d, r15d
    jnz     .shift
    cmp     r13d, SLOTREF_ARMOR
    jb      .plain
    cmp     r13d, SLOTREF_CONTAINER
    jb      .armor_rule
    mov     rax, [inv_container]
    cmp     byte [rax + CONTAINER.kind], CONT_FURNACE
    jne     .plain
    cmp     r13d, SLOTREF_CONTAINER + 2
    je      .output_rule
    cmp     r13d, SLOTREF_CONTAINER + 1
    jne     .plain
    cmp     byte [r12 + CURSOR_COUNT], 0
    je      .plain
    movzx   ecx, byte [r12 + INVENTORY.cursor]
    lea     rdx, [item_burn]
    cmp     word [rdx + rcx*2], 0
    je      .none                       ; fuel cell: only fuel goes in
.plain:
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

    ; armor cell, either button: only the matching piece goes in; the cursor and the cell swap
.armor_rule:
    cmp     byte [r12 + CURSOR_COUNT], 0
    je      .a_take
    movzx   ecx, byte [r12 + INVENTORY.cursor]
    lea     rdx, [item_armor_slot]
    movzx   ecx, byte [rdx + rcx]
    lea     eax, [r13 - (SLOTREF_ARMOR - 1)] ; this cell's armor slot number, 1..4
    cmp     ecx, eax
    jne     .none                       ; wrong piece for this cell
    jmp     .swap
.a_take:
    cmp     byte [rbx + 1], 0
    je      .none
    jmp     .swap

    ; furnace output cell, either button: take-only, the whole stack
.output_rule:
    cmp     byte [rbx + 1], 0
    je      .none
    cmp     byte [r12 + CURSOR_COUNT], 0
    jne     .o_merge
    mov     eax, [rbx]
    mov     [r12 + INVENTORY.cursor], eax
    mov     dword [rbx], 0
    jmp     .changed
.o_merge:
    mov     eax, [rbx]
    mov     ecx, [r12 + INVENTORY.cursor]
    cmp     al, cl
    jne     .none
    test    eax, 0xFFFF0000
    jnz     .none
    test    ecx, 0xFFFF0000
    jnz     .none
    movzx   edx, al
    lea     rsi, [item_max_stack]
    movzx   edx, byte [rsi + rdx]
    movzx   esi, byte [r12 + CURSOR_COUNT]
    movzx   eax, byte [rbx + 1]
    add     esi, eax
    cmp     esi, edx
    ja      .none                       ; the cursor stack would overflow
    mov     [r12 + CURSOR_COUNT], sil
    mov     dword [rbx], 0
    jmp     .changed

    ; shift click: move the stack to the other side. add_cells wants rdi base, esi ncells,
    ; edx id, ecx count, r8d dmg
.shift:
    cmp     byte [rbx + 1], 0
    je      .none
    movzx   edx, byte [rbx]
    movzx   ecx, byte [rbx + 1]
    movzx   r8d, word [rbx + 2]
    mov     rdi, r12                    ; grid, armor and container cells -> inventory [0, 36)
    mov     esi, INV_SLOTS
    cmp     r13d, SLOTREF_GRID
    jae     .sh_go
    mov     rax, [inv_container]        ; an inventory slot with a container open
    test    rax, rax
    jz      .sh_nocont
    lea     rdi, [rax + CONTAINER.slots]
    mov     esi, 27
    cmp     byte [rax + CONTAINER.kind], CONT_FURNACE
    jne     .sh_go                      ; chest: any cell
    mov     esi, 1
    lea     r9, [item_smelt]
    cmp     byte [r9 + rdx], 0
    jne     .sh_go                      ; smeltable -> input cell
    lea     r9, [item_burn]
    cmp     word [r9 + rdx*2], 0
    je      .sh_hm                      ; neither: the plain hotbar <-> main move
    add     rdi, 4                      ; fuel -> fuel cell
    jmp     .sh_go
.sh_nocont:
    lea     r9, [item_armor_slot]       ; armor goes to its free cell first
    movzx   eax, byte [r9 + rdx]
    test    eax, eax
    jz      .sh_hm
    lea     r9, [r12 + INVENTORY.armor + rax*4 - 4]
    cmp     byte [r9 + 1], 0
    jne     .sh_hm                      ; that cell is taken
    mov     eax, [rbx]
    mov     [r9], eax
    mov     dword [rbx], 0
    jmp     .changed
.sh_hm:
    lea     rdi, [r12 + HOTBAR_SLOTS*4] ; hotbar -> main [9, 36)
    mov     esi, INV_SLOTS - HOTBAR_SLOTS
    cmp     r13d, HOTBAR_SLOTS
    jb      .sh_go
    mov     rdi, r12                    ; main -> hotbar [0, 9)
    mov     esi, HOTBAR_SLOTS
.sh_go:
    call    add_cells
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
    mov     rdi, r12                    ; add_cells(inv, 36, result id, count, 0)
    mov     esi, INV_SLOTS
    movzx   edx, byte [r12 + INVENTORY.result]
    movzx   ecx, byte [r12 + RESULT_COUNT]
    xor     r8d, r8d
    call    add_cells
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
    lea     eax, [r13 - SLOTREF_GRID]
    cmp     eax, 8
    ja      .one
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
