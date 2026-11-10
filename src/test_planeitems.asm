; test_planeitems.asm - the plane's six items: crafting grids, names and stacks (their icons are test_icons_art's).
%include "common.inc"
default rel

global test_plane_recipes, test_plane_item_tables

extern inv, craft_size, inv_clear, craft_update
extern recipes, recipes_end
extern item_max_stack, item_names

; CASE result id, result count, then the 3x3 grid ids row by row (0 = empty cell)
%macro CASE 11
    db %1, %2, %3, %4, %5, %6, %7, %8, %9, %10, %11
%endmacro

; PIROW item id, max stack, name
%macro PIROW 3
    db %1, %2
    dq %3
%endmacro

section .rodata
pn_engine:  db "Engine", 0
pn_wing:    db "Wing", 0
pn_fuse:    db "Fuselage", 0
pn_prop:    db "Propeller", 0
pn_tail:    db "Tail", 0
pn_plane:   db "Airplane", 0

plane_cases:
    CASE PLANE_ENGINE, 1,     GUNPOWDER, IRON_INGOT, 0,  IRON_INGOT, IRON_BLOCK, IRON_INGOT,  0, IRON_INGOT, COAL
    CASE PLANE_WING, 1,       IRON_INGOT, IRON_INGOT, IRON_INGOT,  IRON_INGOT, WOOL, WOOL,  IRON_INGOT, WOOL, WOOL
    CASE PLANE_FUSELAGE, 1,   IRON_INGOT, IRON_INGOT, IRON_INGOT,  GLASS, GLASS, GLASS,  IRON_INGOT, IRON_INGOT, IRON_INGOT
    CASE PLANE_PROP, 1,       0, IRON_INGOT, 0,  IRON_INGOT, STICK, IRON_INGOT,  0, STICK, 0
    CASE PLANE_TAIL, 1,       WOOL, WOOL, WOOL,  IRON_INGOT, STICK, IRON_INGOT,  0, IRON_INGOT, 0
    CASE PLANE, 1,            0, PLANE_PROP, 0,  PLANE_WING, PLANE_ENGINE, PLANE_WING,  0, PLANE_FUSELAGE, PLANE_TAIL
    ; the plane needs every part, both wings included
    CASE 0, 0,                0, 0, 0,  PLANE_WING, PLANE_ENGINE, PLANE_WING,  0, PLANE_FUSELAGE, PLANE_TAIL
    CASE 0, 0,                0, PLANE_PROP, 0,  0, PLANE_ENGINE, PLANE_WING,  0, PLANE_FUSELAGE, PLANE_TAIL
    CASE 0, 0,                0, PLANE_PROP, 0,  PLANE_WING, 0, PLANE_WING,  0, PLANE_FUSELAGE, PLANE_TAIL
    CASE 0, 0,                0, PLANE_PROP, 0,  PLANE_WING, PLANE_ENGINE, PLANE_WING,  0, 0, PLANE_TAIL
    CASE 0, 0,                0, PLANE_PROP, 0,  PLANE_WING, PLANE_ENGINE, PLANE_WING,  0, PLANE_FUSELAGE, 0
    ; a component with an ingredient missing or swapped crafts nothing
    CASE 0, 0,                GUNPOWDER, IRON_INGOT, 0,  IRON_INGOT, IRON_INGOT, IRON_INGOT,  0, IRON_INGOT, COAL
    CASE 0, 0,                IRON_INGOT, IRON_INGOT, IRON_INGOT,  IRON_INGOT, WOOL, WOOL,  IRON_INGOT, WOOL, 0
    CASE 0, 0,                IRON_INGOT, IRON_INGOT, IRON_INGOT,  GLASS, GLASS, GLASS,  IRON_INGOT, IRON_INGOT, 0
    CASE 0, 0,                0, IRON_INGOT, 0,  IRON_INGOT, STICK, IRON_INGOT,  0, 0, 0
    CASE 0, 0,                WOOL, WOOL, WOOL,  IRON_INGOT, 0, IRON_INGOT,  0, IRON_INGOT, 0
plane_cases_end:

plane_item_rows:
    PIROW PLANE_ENGINE, 16, pn_engine
    PIROW PLANE_WING, 16, pn_wing
    PIROW PLANE_FUSELAGE, 16, pn_fuse
    PIROW PLANE_PROP, 16, pn_prop
    PIROW PLANE_TAIL, 16, pn_tail
    PIROW PLANE, 1, pn_plane
plane_item_rows_end:

section .text

; pi_streq(rdi a, rsi b) -> eax 1 when the two zero-terminated strings are equal
pi_streq:
.l:
    mov     al, [rdi]
    cmp     al, [rsi]
    jne     .no
    test    al, al
    jz      .yes
    inc     rdi
    inc     rsi
    jmp     .l
.yes:
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; test_plane_recipes() -> eax 0 pass
;   each plane recipe yields its item (one of it) from exactly its grid; the plane grid with one part
;   missing and the near-miss component grids yield nothing; the table still fits the recipe book,
;   which lists one entry per run of records with the same output, 256 at most (recipebook.asm
;   MAX_ENTRIES, a local constant there)
test_plane_recipes:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    inv_clear
    mov     dword [craft_size], 3
    lea     rbx, [plane_cases]
    lea     r12, [plane_cases_end]
.case:
    lea     rdi, [inv + INVENTORY.grid]
    xor     ecx, ecx
.cell:
    movzx   eax, byte [rbx + 2 + rcx]
    test    eax, eax
    jz      .put
    or      eax, 0x100                  ; one item
.put:
    mov     [rdi + rcx*4], eax
    inc     ecx
    cmp     ecx, 9
    jb      .cell
    call    craft_update
    movzx   eax, byte [rbx + 1]
    shl     eax, 8
    movzx   ecx, byte [rbx]
    or      eax, ecx
    cmp     [inv + INVENTORY.result], eax
    jne     .fail
    add     rbx, 11
    cmp     rbx, r12
    jb      .case
    lea     rsi, [recipes]
    lea     rdx, [recipes_end]
    xor     ecx, ecx                    ; book entries
    mov     r8d, -1                     ; output of the open run
.run:
    cmp     rsi, rdx
    jae     .runs_done
    movzx   eax, byte [rsi + 2]
    cmp     eax, r8d
    je      .same
    inc     ecx
    mov     r8d, eax
.same:
    add     rsi, RECIPE_SIZE
    jmp     .run
.runs_done:
    cmp     ecx, 256
    ja      .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    inv_clear
    mov     dword [craft_size], 2
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; test_plane_item_tables() -> eax 0 pass
;   the six plane items have their names and max stacks (components 16, the plane 1); their icons are
;   32x32 bitmaps of the icon registry, which test_icons_art checks for every item
test_plane_item_tables:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    lea     rbx, [plane_item_rows]
.row:
    movzx   ecx, byte [rbx]
    lea     rdx, [item_max_stack]
    movzx   eax, byte [rdx + rcx]
    cmp     al, [rbx + 1]
    jne     .fail
    lea     rdx, [item_names]
    mov     rdi, [rdx + rcx*8]
    mov     rsi, [rbx + 2]
    call    pi_streq
    test    eax, eax
    jz      .fail
    add     rbx, 10
    lea     rax, [plane_item_rows_end]
    cmp     rbx, rax
    jb      .row
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret
