; test_items.asm - inventory, crafting and tool-rule tests.
%include "common.inc"
default rel

global test_inv_add_merges, test_inv_right_click_split, test_craft_planks_from_log
global test_craft_tool_shapes, test_craft_shift_click_all, test_break_time_rules

extern inv, inv_sel, craft_size
extern inv_clear, inv_add, inv_click, craft_update
extern item_break_time, item_harvest_drop
extern world_clear

section .rodata
align 16
abs_mask: dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF
tol:      dd 0.001
f_1e29:   dd 1.0e29
t_075:    dd 0.75
t_75:     dd 7.5
t_1125:   dd 1.125

section .text

; stack constant for slot/grid/result/cursor comparisons
%define STK(id, n, dmg) ((id) | ((n) << 8) | ((dmg) << 16))
; slot ref: 0..35 slot, 36..44 grid cell, 45 result, 46 cursor
%define CELL(n) (SLOTREF_GRID + (n))
%define CURSOR  46

%macro TEST_INIT 0
    call    world_clear
    call    inv_clear
    mov     dword [inv_sel], 0
    mov     dword [craft_size], 2
%endmacro

; SET ref, id, n, dmg
%macro SET 4
    lea     rax, [inv]
    mov     dword [rax + (%1)*4], STK(%2, %3, %4)
%endmacro

; EXPECT ref, id, n, dmg  - fails the test when the stack differs
%macro EXPECT 4
    lea     rax, [inv]
    cmp     dword [rax + (%1)*4], STK(%2, %3, %4)
    jne     .fail
%endmacro

; CLICK ref, button, shift
%macro CLICK 3
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    call    inv_click
%endmacro

; ADD id, n
%macro ADD 2
    mov     edi, %1
    mov     esi, %2
    call    inv_add
%endmacro

; empties the whole 3x3 grid
%macro CLEAR_GRID 0
    lea     rax, [inv]
    %assign i 0
    %rep 9
        mov     dword [rax + CELL(i)*4], 0
        %assign i i+1
    %endrep
%endmacro

%macro RETURN_OK 0
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret
%endmacro

test_inv_add_merges:
    push    rbp
    mov     rbp, rsp
    TEST_INIT
    ADD     DIRT, 70
    test    eax, eax
    jnz     .fail
    EXPECT  0, DIRT, 64, 0
    EXPECT  1, DIRT, 6, 0
    ADD     WOOD_PICKAXE, 1
    ADD     WOOD_PICKAXE, 1
    EXPECT  2, WOOD_PICKAXE, 1, 0
    EXPECT  3, WOOD_PICKAXE, 1, 0
    ADD     COBBLE, 2304
    cmp     eax, 256
    jne     .fail
    RETURN_OK

test_inv_right_click_split:
    push    rbp
    mov     rbp, rsp
    TEST_INIT
    SET     5, DIRT, 5, 0
    CLICK   5, 1, 0
    EXPECT  CURSOR, DIRT, 3, 0
    EXPECT  5, DIRT, 2, 0
    CLICK   6, 1, 0
    EXPECT  6, DIRT, 1, 0
    EXPECT  CURSOR, DIRT, 2, 0
    CLICK   6, 0, 0
    EXPECT  6, DIRT, 3, 0
    EXPECT  CURSOR, 0, 0, 0
    RETURN_OK

test_craft_planks_from_log:
    push    rbp
    mov     rbp, rsp
    TEST_INIT
    SET     CELL(4), LOG, 1, 0
    call    craft_update
    EXPECT  SLOTREF_RESULT, PLANKS, 4, 0
    CLICK   SLOTREF_RESULT, 0, 0
    EXPECT  CURSOR, PLANKS, 4, 0
    EXPECT  CELL(4), 0, 0, 0
    EXPECT  SLOTREF_RESULT, 0, 0, 0
    RETURN_OK

test_craft_tool_shapes:
    push    rbp
    mov     rbp, rsp
    TEST_INIT
    mov     dword [craft_size], 3
    ; stone pickaxe: CCC / 0S0 / 0S0
    SET     CELL(0), COBBLE, 1, 0
    SET     CELL(1), COBBLE, 1, 0
    SET     CELL(2), COBBLE, 1, 0
    SET     CELL(4), STICK, 1, 0
    SET     CELL(7), STICK, 1, 0
    call    craft_update
    EXPECT  SLOTREF_RESULT, STONE_PICKAXE, 1, 0
    ; wooden axe, mirrored: PP / SP / S0
    CLEAR_GRID
    SET     CELL(0), PLANKS, 1, 0
    SET     CELL(1), PLANKS, 1, 0
    SET     CELL(4), PLANKS, 1, 0
    SET     CELL(3), STICK, 1, 0
    SET     CELL(6), STICK, 1, 0
    call    craft_update
    EXPECT  SLOTREF_RESULT, WOOD_AXE, 1, 0
    ; the same shape one column to the right
    CLEAR_GRID
    SET     CELL(1), PLANKS, 1, 0
    SET     CELL(2), PLANKS, 1, 0
    SET     CELL(5), PLANKS, 1, 0
    SET     CELL(4), STICK, 1, 0
    SET     CELL(7), STICK, 1, 0
    call    craft_update
    EXPECT  SLOTREF_RESULT, WOOD_AXE, 1, 0
    ; two planks on a diagonal match nothing
    CLEAR_GRID
    SET     CELL(0), PLANKS, 1, 0
    SET     CELL(4), PLANKS, 1, 0
    call    craft_update
    EXPECT  SLOTREF_RESULT, 0, 0, 0
    ; 2x2 grid of planks -> crafting table
    CLEAR_GRID
    mov     dword [craft_size], 2
    SET     CELL(0), PLANKS, 1, 0
    SET     CELL(1), PLANKS, 1, 0
    SET     CELL(3), PLANKS, 1, 0
    SET     CELL(4), PLANKS, 1, 0
    call    craft_update
    EXPECT  SLOTREF_RESULT, CRAFTING_TABLE, 1, 0
    RETURN_OK

test_craft_shift_click_all:
    push    rbp
    mov     rbp, rsp
    TEST_INIT
    SET     CELL(0), LOG, 3, 0
    call    craft_update
    CLICK   SLOTREF_RESULT, 0, 1
    EXPECT  0, PLANKS, 12, 0
    EXPECT  CELL(0), 0, 0, 0
    EXPECT  SLOTREF_RESULT, 0, 0, 0
    RETURN_OK

; CHECK_TIME block, held, expected-label: |item_break_time - expected| <= 0.001
%macro CHECK_TIME 3
    mov     edi, %1
    mov     esi, %2
    call    item_break_time
    subss   xmm0, [%3]
    andps   xmm0, [abs_mask]
    comiss  xmm0, [tol]
    ja      .fail
%endmacro

; CHECK_DROP block, held, expected
%macro CHECK_DROP 3
    mov     edi, %1
    mov     esi, %2
    call    item_harvest_drop
    cmp     eax, %3
    jne     .fail
%endmacro

test_break_time_rules:
    push    rbp
    mov     rbp, rsp
    TEST_INIT
    CHECK_TIME DIRT, 0, t_075
    CHECK_TIME STONE, 0, t_75
    CHECK_TIME STONE, WOOD_PICKAXE, t_1125
    CHECK_TIME LOG, STONE_AXE, t_075
    mov     edi, BEDROCK
    xor     esi, esi
    call    item_break_time
    comiss  xmm0, [f_1e29]
    jb      .fail
    CHECK_DROP STONE, 0, 0
    CHECK_DROP STONE, WOOD_PICKAXE, COBBLE
    CHECK_DROP GRASS, 0, DIRT
    CHECK_DROP GLASS, 0, 0
    RETURN_OK
