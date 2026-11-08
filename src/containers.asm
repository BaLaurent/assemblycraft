; containers.asm - furnaces and chests. The records live in the world header
; (WORLDHDR.containers_v5: MAX_CONTAINERS_V5 x CONTAINER), so they are saved with the world.
; A record is free while its kind byte is 0. A furnace uses cells 0 input, 1 fuel, 2 output.
%include "common.inc"
default rel

global cont_at, cont_create, cont_block_removed, conts_step, conts_validate, cont_fill_from_inv

extern world_header, world_get, world_set, drops_spawn
extern item_max_stack, item_burn, item_smelt
extern inv_container, inv_count, inv_remove_one, inv_take_stack

%define SLOT_IN   (CONTAINER.slots)
%define SLOT_FUEL (CONTAINER.slots + 4)
%define SLOT_OUT  (CONTAINER.slots + 8)

section .rodata
align 4
c_half: dd 0.5

section .text

; cont_at(edi x, esi y, edx z) -> rax CONTAINER* at that cell, or 0
cont_at:
    xor     eax, eax
    cmp     edi, WORLD_X - 1
    ja      .ret
    cmp     esi, WORLD_Y - 1
    ja      .ret
    cmp     edx, WORLD_Z - 1
    ja      .ret
    lea     rcx, [world_header + WORLDHDR.containers_v5]
    mov     r8d, MAX_CONTAINERS_V5
.l:
    cmp     byte [rcx + CONTAINER.kind], 0
    je      .n                          ; free record
    cmp     [rcx + CONTAINER.x], edi
    jne     .n
    cmp     [rcx + CONTAINER.y], esi
    jne     .n
    cmp     [rcx + CONTAINER.z], edx
    je      .found
.n:
    add     rcx, CONTAINER_size
    dec     r8d
    jnz     .l
    ret
.found:
    mov     rax, rcx
.ret:
    ret

; cont_create(edi x, esi y, edx z, ecx kind) -> rax CONTAINER* or 0 when all records are in
; use (or the cell lies outside the world). A record already at the cell is reused. The
; record is zeroed, then x, y, z and kind are set.
cont_create:
    xor     eax, eax
    cmp     edi, WORLD_X - 1
    ja      .ret
    cmp     esi, WORLD_Y - 1
    ja      .ret
    cmp     edx, WORLD_Z - 1
    ja      .ret
    mov     r11d, ecx                   ; kind
    lea     r8, [world_header + WORLDHDR.containers_v5]
    xor     r9d, r9d                    ; first free record
    mov     r10d, MAX_CONTAINERS_V5
.scan:
    cmp     byte [r8 + CONTAINER.kind], 0
    jne     .used
    test    r9, r9
    jnz     .next
    mov     r9, r8
    jmp     .next
.used:
    cmp     [r8 + CONTAINER.x], edi
    jne     .next
    cmp     [r8 + CONTAINER.y], esi
    jne     .next
    cmp     [r8 + CONTAINER.z], edx
    jne     .next
    mov     r9, r8                      ; a record already sits here: reuse it
    jmp     .fill
.next:
    add     r8, CONTAINER_size
    dec     r10d
    jnz     .scan
    test    r9, r9
    jz      .ret                        ; table full
.fill:
    mov     ecx, edi
    mov     rdi, r9
    mov     r10d, ecx                   ; x
    mov     ecx, CONTAINER_size / 8
    xor     eax, eax
    rep     stosq
    mov     [r9 + CONTAINER.x], r10d
    mov     [r9 + CONTAINER.y], esi
    mov     [r9 + CONTAINER.z], edx
    mov     [r9 + CONTAINER.kind], r11b
    mov     rax, r9
.ret:
    ret

; cont_block_removed(edi x, esi y, edx z) - the block at the cell is gone: every stack of its
; record pops out as an item drop and the record is freed. No record there: nothing happens.
cont_block_removed:
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
    mov     r14d, edx
    call    cont_at
    test    rax, rax
    jz      .ret
    mov     rbx, rax
    xor     r15d, r15d
.slot:
    cmp     byte [rbx + CONTAINER.slots + r15*4 + 1], 0
    je      .next
    movzx   edi, byte [rbx + CONTAINER.slots + r15*4]
    movzx   esi, byte [rbx + CONTAINER.slots + r15*4 + 1]
    movzx   edx, word [rbx + CONTAINER.slots + r15*4 + 2]
    cvtsi2ss xmm0, r12d
    addss   xmm0, [c_half]
    cvtsi2ss xmm1, r13d
    addss   xmm1, [c_half]
    cvtsi2ss xmm2, r14d
    addss   xmm2, [c_half]
    call    drops_spawn
.next:
    inc     r15d
    cmp     r15d, 27
    jb      .slot
    mov     rdi, rbx                    ; free the record
    mov     ecx, CONTAINER_size / 8
    xor     eax, eax
    rep     stosq
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; cont_fill_from_inv(edi cell, esi id) -> eax items moved
; The recipe book's click on a furnace entry: moves the inventory's stock of that item into cell
; `cell` of the open container (inv_container). The cell must be empty or already hold the same
; item unworn; at most item_max_stack end up in it. An item that does not stack (a wooden tool
; as fuel) moves its slot's stack as it is, wear kept. Nothing moves, and 0 comes back, when
; no container is open, the cell does not exist, or the cell holds something else.
cont_fill_from_inv:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    xor     r13d, r13d                  ; items moved
    mov     rbx, [inv_container]
    test    rbx, rbx
    jz      .out
    cmp     edi, 26
    ja      .out
    cmp     byte [rbx + CONTAINER.kind], CONT_FURNACE
    jne     .cell_ok
    cmp     edi, 2
    ja      .out                        ; a furnace has three cells
.cell_ok:
    mov     edi, edi
    lea     rbx, [rbx + CONTAINER.slots + rdi*4]
    movzx   r12d, sil                   ; id
    lea     rax, [item_max_stack]
    movzx   r14d, byte [rax + r12]
    test    r14d, r14d
    jz      .out                        ; not an item
    movzx   ecx, byte [rbx + ITEMSTACK.count]
    test    ecx, ecx
    jz      .room
    cmp     byte [rbx + ITEMSTACK.id], r12b
    jne     .out                        ; another item sits there
    cmp     word [rbx + ITEMSTACK.dmg], 0
    jne     .out
    sub     r14d, ecx
    jbe     .out                        ; the stack is full
.room:                                  ; r14d = room in the cell
    lea     rax, [item_max_stack]
    cmp     byte [rax + r12], 1
    ja      .many
    mov     edi, r12d
    call    inv_take_stack              ; does not stack: the slot's stack as it is
    test    eax, eax
    jz      .out
    mov     [rbx], eax
    mov     r13d, 1
    jmp     .out
.many:
    mov     edi, r12d
    call    inv_count
    cmp     eax, r14d
    cmova   eax, r14d                   ; min(room, stock)
    mov     r14d, eax
    test    eax, eax
    jz      .out
.one:
    mov     edi, r12d
    call    inv_remove_one
    inc     r13d
    cmp     r13d, r14d
    jb      .one
    mov     [rbx + ITEMSTACK.id], r12b
    add     [rbx + ITEMSTACK.count], r13b
    mov     word [rbx + ITEMSTACK.dmg], 0
.out:
    mov     eax, r13d
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; furnace_step(rdi CONTAINER*) - one fixed step of burning and smelting
furnace_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdi
    ; can = the input smelts into r9d and the output takes it
    xor     r8d, r8d
    xor     r9d, r9d
    cmp     byte [rbx + SLOT_IN + 1], 0
    je      .have_can
    movzx   eax, byte [rbx + SLOT_IN]
    lea     rcx, [item_smelt]
    movzx   r9d, byte [rcx + rax]
    test    r9d, r9d
    jz      .have_can
    cmp     byte [rbx + SLOT_OUT + 1], 0
    je      .can_yes                    ; an empty output takes anything
    cmp     byte [rbx + SLOT_OUT], r9b
    jne     .have_can
    lea     rcx, [item_max_stack]
    movzx   eax, byte [rcx + r9]
    cmp     byte [rbx + SLOT_OUT + 1], al
    jae     .have_can                   ; the output stack is full
.can_yes:
    mov     r8d, 1
.have_can:
    ; out of fuel with something to smelt: light the next fuel item
    cmp     word [rbx + CONTAINER.burn], 0
    jne     .burn
    test    r8d, r8d
    jz      .burn
    cmp     byte [rbx + SLOT_FUEL + 1], 0
    je      .burn
    movzx   eax, byte [rbx + SLOT_FUEL]
    lea     rcx, [item_burn]
    movzx   eax, word [rcx + rax*2]
    test    eax, eax
    jz      .burn
    mov     [rbx + CONTAINER.burn], ax
    mov     [rbx + CONTAINER.burn_max], ax
    dec     byte [rbx + SLOT_FUEL + 1]
    jnz     .burn
    mov     dword [rbx + SLOT_FUEL], 0
.burn:
    cmp     word [rbx + CONTAINER.burn], 0
    je      .cooked
    dec     word [rbx + CONTAINER.burn]
    test    r8d, r8d
    jz      .cooked
    inc     word [rbx + CONTAINER.cook]
    cmp     word [rbx + CONTAINER.cook], SMELT_STEPS
    jb      .cooked
    mov     word [rbx + CONTAINER.cook], 0
    dec     byte [rbx + SLOT_IN + 1]
    jnz     .in_left
    mov     dword [rbx + SLOT_IN], 0
.in_left:
    movzx   eax, byte [rbx + SLOT_OUT + 1]
    inc     eax
    mov     [rbx + SLOT_OUT], r9b
    mov     [rbx + SLOT_OUT + 1], al
    mov     word [rbx + SLOT_OUT + 2], 0
.cooked:
    test    r8d, r8d
    jnz     .block
    mov     word [rbx + CONTAINER.cook], 0
.block:
    ; the block shows the fire while fuel is burning
    mov     edi, [rbx + CONTAINER.x]
    mov     esi, [rbx + CONTAINER.y]
    mov     edx, [rbx + CONTAINER.z]
    call    world_get
    xor     ecx, ecx
    cmp     word [rbx + CONTAINER.burn], 0
    je      .unlit
    cmp     eax, FURNACE
    jne     .done
    mov     ecx, FURNACE_LIT
    jmp     .set
.unlit:
    cmp     eax, FURNACE_LIT
    jne     .done
    mov     ecx, FURNACE
.set:
    mov     edi, [rbx + CONTAINER.x]
    mov     esi, [rbx + CONTAINER.y]
    mov     edx, [rbx + CONTAINER.z]
    call    world_set
.done:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; conts_step() - one fixed step for every furnace
conts_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    lea     rbx, [world_header + WORLDHDR.containers_v5]
    mov     r12d, MAX_CONTAINERS_V5
.l:
    cmp     byte [rbx + CONTAINER.kind], CONT_FURNACE
    jne     .n
    mov     rdi, rbx
    call    furnace_step
.n:
    add     rbx, CONTAINER_size
    dec     r12d
    jnz     .l
    pop     r12
    pop     rbx
    pop     rbp
    ret

; conts_validate() - after a load: frees every record that is not a real furnace or chest
; (bad kind, cell outside the world, wrong block there) and clears the stacks that cannot
; exist (unknown item, count 0, count above the stack limit)
conts_validate:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    lea     rbx, [world_header + WORLDHDR.containers_v5]
    mov     r12d, MAX_CONTAINERS_V5
.rec:
    movzx   eax, byte [rbx + CONTAINER.kind]
    cmp     eax, CONT_FURNACE
    je      .check
    cmp     eax, CONT_CHEST
    jne     .zero                       ; free, or garbage
.check:
    mov     edi, [rbx + CONTAINER.x]
    mov     esi, [rbx + CONTAINER.y]
    mov     edx, [rbx + CONTAINER.z]
    cmp     edi, WORLD_X - 1
    ja      .zero
    cmp     esi, WORLD_Y - 1
    ja      .zero
    cmp     edx, WORLD_Z - 1
    ja      .zero
    call    world_get
    cmp     byte [rbx + CONTAINER.kind], CONT_CHEST
    je      .want_chest
    cmp     eax, FURNACE
    je      .good
    cmp     eax, FURNACE_LIT
    je      .good
    jmp     .zero
.want_chest:
    cmp     eax, CHEST
    jne     .zero
.good:
    xor     ecx, ecx
.stack:
    lea     rdx, [rbx + CONTAINER.slots + rcx*4]
    movzx   eax, byte [rdx]
    cmp     eax, NUM_ITEMS
    jae     .bad
    lea     rsi, [item_max_stack]
    movzx   esi, byte [rsi + rax]
    test    esi, esi
    jz      .bad                        ; not an item
    movzx   eax, byte [rdx + 1]
    test    eax, eax
    jz      .bad                        ; empty: also clears a stray id and damage
    cmp     eax, esi
    jbe     .keep
.bad:
    mov     dword [rdx], 0
.keep:
    inc     ecx
    cmp     ecx, 27
    jb      .stack
    jmp     .next
.zero:
    mov     rdi, rbx
    mov     ecx, CONTAINER_size / 8
    xor     eax, eax
    rep     stosq
.next:
    add     rbx, CONTAINER_size
    dec     r12d
    jnz     .rec
    pop     r12
    pop     rbx
    pop     rbp
    ret
