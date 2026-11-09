; containers.asm - furnaces and chests. The records live in the runtime table conts[]
; (MAX_CONTAINERS x CONTAINER) with ABSOLUTE cell coordinates (local + world_origin): a column's
; region blob carries its containers, world_install fills the table when the column is installed
; and conts_free_column empties it again when the column unloads. A record is free while its kind
; byte is 0. A furnace uses cells 0 input, 1 fuel, 2 output. Every function here that takes a
; cell takes LOCAL coordinates; the table itself never changes when the origin moves.
%include "common.inc"
default rel

global conts, cont_at, cont_create, conts_free_column, cont_block_removed, conts_step
global cont_fill_from_inv

extern world_origin_x, world_origin_z, world_get, world_set, world_column_ready, drops_spawn
extern item_max_stack, item_burn, item_smelt
extern net_role, net_cont_removed
extern inv_container, inv_count, inv_remove_one, inv_take_stack

%define SLOT_IN   (CONTAINER.slots)
%define SLOT_FUEL (CONTAINER.slots + 4)
%define SLOT_OUT  (CONTAINER.slots + 8)

section .rodata
align 4
c_half: dd 0.5

section .bss
alignb 16
conts:      resb MAX_CONTAINERS * CONTAINER_size

section .text

; cont_at(edi x, esi y, edx z) -> rax CONTAINER* at that local cell, or 0 (also for y outside 0..255)
cont_at:
    xor     eax, eax
    cmp     esi, WORLD_H - 1
    ja      .ret
    add     edi, [world_origin_x]       ; the table holds absolute cells
    add     edx, [world_origin_z]
    lea     rcx, [conts]
    mov     r8d, MAX_CONTAINERS
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

; cont_create(edi x, esi y, edx z, ecx kind) -> rax CONTAINER* or 0 when the table is full, the
; cell's column (x sar 4, z sar 4, absolute) already holds MAX_COL_CONTS records, or y lies outside
; 0..255. A record already at the cell is always reused. The record is zeroed, then x, y, z
; (absolute) and kind are set.
cont_create:
    push    rbx
    push    r12
    xor     eax, eax
    cmp     esi, WORLD_H - 1
    ja      .ret
    add     edi, [world_origin_x]       ; the absolute cell
    add     edx, [world_origin_z]
    mov     r11d, ecx                   ; kind
    lea     rcx, [conts]
    mov     r8d, MAX_CONTAINERS
.find:                                  ; a record already sits here: reuse it
    cmp     byte [rcx + CONTAINER.kind], 0
    je      .find_next
    cmp     [rcx + CONTAINER.x], edi
    jne     .find_next
    cmp     [rcx + CONTAINER.y], esi
    jne     .find_next
    cmp     [rcx + CONTAINER.z], edx
    je      .reuse
.find_next:
    add     rcx, CONTAINER_size
    dec     r8d
    jnz     .find
    mov     r10d, edi                   ; a new record: the cell's column...
    sar     r10d, 4
    mov     ebx, edx
    sar     ebx, 4
    xor     r9d, r9d                    ; first free record
    xor     r12d, r12d                  ; records already in that column
    lea     rcx, [conts]
    lea     r8, [conts + MAX_CONTAINERS * CONTAINER_size]
.scan:
    cmp     byte [rcx + CONTAINER.kind], 0
    jne     .used
    test    r9, r9
    jnz     .next
    mov     r9, rcx
    jmp     .next
.used:
    mov     eax, [rcx + CONTAINER.x]
    sar     eax, 4
    cmp     eax, r10d
    jne     .next
    mov     eax, [rcx + CONTAINER.z]
    sar     eax, 4
    cmp     eax, ebx
    jne     .next
    inc     r12d
.next:
    add     rcx, CONTAINER_size
    cmp     rcx, r8
    jb      .scan
    xor     eax, eax
    test    r9, r9
    jz      .ret                        ; table full
    cmp     r12d, MAX_COL_CONTS
    jae     .ret                        ; the column is full
    mov     rcx, r9
.reuse:                                 ; rcx = the record
    mov     r10d, edi                   ; x (rdi is the fill's destination)
    mov     rdi, rcx
    mov     ecx, CONTAINER_size / 8
    xor     eax, eax
    rep     stosq
    lea     rax, [rdi - CONTAINER_size]
    mov     [rax + CONTAINER.x], r10d
    mov     [rax + CONTAINER.y], esi
    mov     [rax + CONTAINER.z], edx
    mov     [rax + CONTAINER.kind], r11b
.ret:
    pop     r12
    pop     rbx
    ret

; conts_free_column(edi acx, esi acz): every record whose cell lies in that absolute column is
; zeroed (the column is unloading: its region blob already carries them)
conts_free_column:
    lea     rcx, [conts]
    lea     r8, [conts + MAX_CONTAINERS * CONTAINER_size]
.l:
    cmp     byte [rcx + CONTAINER.kind], 0
    je      .n
    mov     eax, [rcx + CONTAINER.x]
    sar     eax, 4
    cmp     eax, edi
    jne     .n
    mov     eax, [rcx + CONTAINER.z]
    sar     eax, 4
    cmp     eax, esi
    jne     .n
%assign i 0
%rep CONTAINER_size / 8
    mov     qword [rcx + i], 0
%assign i i + 8
%endrep
.n:
    add     rcx, CONTAINER_size
    cmp     rcx, r8
    jb      .l
    ret

; cont_block_removed(edi x, esi y, edx z) - the block at the cell is gone: every stack of its
; record pops out as an item drop and the record is freed. No record there: nothing happens. A guest
; does nothing at all (the host spills the real contents when it applies the guest's edit); the host
; tells net_cont_removed first, so that the peers holding the container open are let go.
cont_block_removed:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .go
    ret
.go:
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
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .spill
    mov     edi, [rbx + CONTAINER.x]    ; the record's own (absolute) cell
    mov     esi, [rbx + CONTAINER.y]
    mov     edx, [rbx + CONTAINER.z]
    call    net_cont_removed            ; the peers that hold it open are let go
.spill:
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

; furnace_step(rdi CONTAINER*) - one fixed step of burning and smelting. The record holds an
; absolute cell; its block is read and written at the local one. A furnace whose column is not
; ready (not loaded or not lit yet) waits: nothing burns or cooks until it is.
; r12d, r13d = the local x and z of the cell.
furnace_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12d, [rbx + CONTAINER.x]
    sub     r12d, [world_origin_x]
    mov     r13d, [rbx + CONTAINER.z]
    sub     r13d, [world_origin_z]
    mov     edi, r12d
    mov     esi, r13d
    call    world_column_ready
    test    eax, eax
    jz      .done
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
    mov     edi, r12d
    mov     esi, [rbx + CONTAINER.y]
    mov     edx, r13d
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
    mov     edi, r12d
    mov     esi, [rbx + CONTAINER.y]
    mov     edx, r13d
    call    world_set
.done:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; conts_step() - one fixed step for every furnace
conts_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    lea     rbx, [conts]
    mov     r12d, MAX_CONTAINERS
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
