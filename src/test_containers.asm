; test_containers.asm - furnace smelting, chests spilling on break, the container table.
%include "common.inc"
default rel

global test_furnace_smelts, test_chest_spills_on_break

extern world_header, world_clear, world_set, world_get
extern cont_at, cont_create, cont_block_removed, conts_step, conts_validate
extern drops, drops_clear

%define STK(id, n, dmg) ((id) | ((n) << 8) | ((dmg) << 16))
%define IN_CELL   (CONTAINER.slots)
%define FUEL_CELL (CONTAINER.slots + 4)
%define OUT_CELL  (CONTAINER.slots + 8)

section .text

; zero_conts() - empties the whole container table
zero_conts:
    lea     rdi, [world_header + WORLDHDR.containers]
    mov     ecx, MAX_CONTAINERS * CONTAINER_size
    xor     eax, eax
    rep     stosb
    ret

; steps(edi n) - n fixed container steps
steps:
    push    rbx
    mov     ebx, edi
.l:
    call    conts_step
    dec     ebx
    jnz     .l
    pop     rbx
    ret

; PLACE x, y, z, block, kind: sets the block and creates its record -> rax
%macro PLACE 5
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    call    world_set
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %5
    call    cont_create
%endmacro

; EXPECT_BLOCK x, y, z, id
%macro EXPECT_BLOCK 4
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    call    world_get
    cmp     eax, %4
    jne     .fail
%endmacro

; EXPECT_AT x, y, z, record: cont_at must return exactly that record (register or 0)
%macro EXPECT_AT 4
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    call    cont_at
    cmp     rax, %4
    jne     .fail
%endmacro

test_furnace_smelts:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    zero_conts
    PLACE   5, 10, 5, FURNACE, CONT_FURNACE
    test    rax, rax
    jz      .fail
    mov     rbx, rax
    EXPECT_AT 5, 10, 5, rbx
    mov     dword [rbx + IN_CELL], STK(IRON_ORE, 2, 0)
    mov     dword [rbx + FUEL_CELL], STK(COAL, 1, 0)

    ; the first step lights the coal and starts cooking; the block shows the fire
    mov     edi, 1
    call    steps
    cmp     word [rbx + CONTAINER.burn], 1599
    jne     .fail
    cmp     word [rbx + CONTAINER.burn_max], 1600
    jne     .fail
    cmp     word [rbx + CONTAINER.cook], 1
    jne     .fail
    cmp     dword [rbx + FUEL_CELL], 0
    jne     .fail
    EXPECT_BLOCK 5, 10, 5, FURNACE_LIT
    mov     edi, 199
    call    steps                       ; 200 steps: the first ingot
    cmp     dword [rbx + OUT_CELL], STK(IRON_INGOT, 1, 0)
    jne     .fail
    cmp     dword [rbx + IN_CELL], STK(IRON_ORE, 1, 0)
    jne     .fail
    mov     edi, 200
    call    steps                       ; 400 steps: the second, the input is used up
    cmp     dword [rbx + OUT_CELL], STK(IRON_INGOT, 2, 0)
    jne     .fail
    cmp     dword [rbx + IN_CELL], 0
    jne     .fail
    mov     edi, 1
    call    steps                       ; nothing left to cook: the fuel still burns
    cmp     word [rbx + CONTAINER.cook], 0
    jne     .fail
    cmp     word [rbx + CONTAINER.burn], 1199
    jne     .fail
    EXPECT_BLOCK 5, 10, 5, FURNACE_LIT
    mov     word [rbx + CONTAINER.burn], 1
    mov     edi, 1
    call    steps                       ; the last step of the fuel puts the fire out
    EXPECT_BLOCK 5, 10, 5, FURNACE

    ; another product in the output blocks the furnace: nothing is lit, no fuel is used
    mov     dword [rbx + IN_CELL], STK(SAND, 1, 0)
    mov     dword [rbx + FUEL_CELL], STK(PLANKS, 2, 0)
    mov     dword [rbx + OUT_CELL], STK(IRON_INGOT, 2, 0)
    mov     edi, 1
    call    steps
    cmp     word [rbx + CONTAINER.burn], 0
    jne     .fail
    cmp     word [rbx + CONTAINER.cook], 0
    jne     .fail
    cmp     dword [rbx + FUEL_CELL], STK(PLANKS, 2, 0)
    jne     .fail
    EXPECT_BLOCK 5, 10, 5, FURNACE
    ; with a free output one plank (300 steps) smelts the sand into glass
    mov     dword [rbx + OUT_CELL], 0
    mov     edi, 200
    call    steps
    cmp     word [rbx + CONTAINER.burn], 100
    jne     .fail
    cmp     dword [rbx + FUEL_CELL], STK(PLANKS, 1, 0)
    jne     .fail
    cmp     dword [rbx + OUT_CELL], STK(GLASS, 1, 0)
    jne     .fail
    cmp     dword [rbx + IN_CELL], 0
    jne     .fail
    EXPECT_BLOCK 5, 10, 5, FURNACE_LIT
    ; a full output stack of the same item stops the cooking and resets it
    mov     dword [rbx + IN_CELL], STK(SAND, 1, 0)
    mov     dword [rbx + OUT_CELL], STK(GLASS, 64, 0)
    mov     word [rbx + CONTAINER.cook], 50
    mov     edi, 1
    call    steps
    cmp     word [rbx + CONTAINER.cook], 0
    jne     .fail
    cmp     dword [rbx + IN_CELL], STK(SAND, 1, 0)
    jne     .fail
    cmp     dword [rbx + OUT_CELL], STK(GLASS, 64, 0)
    jne     .fail

    ; conts_validate keeps a furnace record whatever its lit state and frees it once its
    ; block is gone
    call    conts_validate
    EXPECT_AT 5, 10, 5, rbx
    mov     edi, 5
    mov     esi, 10
    mov     edx, 5
    mov     ecx, FURNACE
    call    world_set
    call    conts_validate
    EXPECT_AT 5, 10, 5, rbx
    mov     edi, 5
    mov     esi, 10
    mov     edx, 5
    mov     ecx, STONE
    call    world_set
    call    conts_validate
    EXPECT_AT 5, 10, 5, 0
    cmp     byte [rbx + CONTAINER.kind], 0
    jne     .fail
    cmp     dword [rbx + OUT_CELL], 0
    jne     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    zero_conts
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

test_chest_spills_on_break:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    zero_conts
    call    drops_clear
    PLACE   5, 11, 5, CHEST, CONT_CHEST
    test    rax, rax
    jz      .fail
    mov     rbx, rax
    lea     rax, [world_header + WORLDHDR.containers]
    cmp     rbx, rax
    jne     .fail                       ; the first record of the table
    mov     dword [rbx + CONTAINER.slots], STK(DIRT, 10, 0)
    mov     dword [rbx + CONTAINER.slots + 26*4], STK(IRON_SWORD, 1, 7)
    PLACE   6, 11, 5, CHEST, CONT_CHEST ; a neighbour that must not be touched
    test    rax, rax
    jz      .fail
    mov     r12, rax
    mov     dword [r12 + CONTAINER.slots + 3*4], STK(COAL, 5, 0)

    mov     edi, 5
    mov     esi, 11
    mov     edx, 5
    call    cont_block_removed
    EXPECT_AT 5, 11, 5, 0
    cmp     dword [drops + DROP.id], STK(DIRT, 10, 0)
    jne     .fail
    cmp     dword [drops + DROP_size + DROP.id], STK(IRON_SWORD, 1, 7)
    jne     .fail
    cmp     dword [drops + DROP.x], 0x40B00000 ; the cell centre 5.5, 11.5, 5.5
    jne     .fail
    cmp     dword [drops + DROP.y], 0x41380000
    jne     .fail
    cmp     dword [drops + DROP.z], 0x40B00000
    jne     .fail
    cmp     byte [drops + 2*DROP_size + DROP.id], 0
    jne     .fail                       ; empty cells spill nothing
    EXPECT_AT 6, 11, 5, r12
    cmp     dword [r12 + CONTAINER.slots + 3*4], STK(COAL, 5, 0)
    jne     .fail
    mov     edi, 9                      ; no record there: nothing happens
    mov     esi, 9
    mov     edx, 9
    call    cont_block_removed
    cmp     byte [drops + 2*DROP_size + DROP.id], 0
    jne     .fail

    ; the freed record is handed out first again; creating on an occupied cell wipes it
    mov     edi, 7
    mov     esi, 11
    mov     edx, 5
    mov     ecx, CONT_CHEST
    call    cont_create
    cmp     rax, rbx
    jne     .fail
    mov     edi, 6
    mov     esi, 11
    mov     edx, 5
    mov     ecx, CONT_FURNACE
    call    cont_create
    cmp     rax, r12
    jne     .fail
    cmp     byte [r12 + CONTAINER.kind], CONT_FURNACE
    jne     .fail
    cmp     dword [r12 + CONTAINER.slots + 3*4], 0
    jne     .fail

    ; cells outside the world have no record; free records do not answer for cell 0,0,0
    call    zero_conts
    EXPECT_AT 0, 0, 0, 0
    mov     edi, 256
    xor     esi, esi
    xor     edx, edx
    mov     ecx, CONT_CHEST
    call    cont_create
    test    rax, rax
    jnz     .fail
    xor     edi, edi
    mov     esi, WORLD_Y
    xor     edx, edx
    mov     ecx, CONT_CHEST
    call    cont_create
    test    rax, rax
    jnz     .fail
    ; all 120 records in use: no new cell fits, a cell that has a record still resolves
    xor     r12d, r12d
.fill:
    mov     edi, r12d
    mov     esi, 20
    xor     edx, edx
    mov     ecx, CONT_CHEST
    call    cont_create
    test    rax, rax
    jz      .fail
    inc     r12d
    cmp     r12d, MAX_CONTAINERS
    jb      .fill
    mov     edi, 200
    mov     esi, 20
    xor     edx, edx
    mov     ecx, CONT_CHEST
    call    cont_create
    test    rax, rax
    jnz     .fail
    mov     edi, 3
    mov     esi, 20
    xor     edx, edx
    mov     ecx, CONT_FURNACE
    call    cont_create
    test    rax, rax
    jz      .fail
    cmp     byte [rax + CONTAINER.kind], CONT_FURNACE
    jne     .fail

    ; conts_validate: records without a matching block or a real kind are freed, and
    ; stacks that cannot exist are cleared
    call    zero_conts
    call    world_clear
    PLACE   5, 11, 5, CHEST, CONT_CHEST
    mov     rbx, rax
    mov     dword [rbx + CONTAINER.slots], STK(DIRT, 65, 0)
    mov     dword [rbx + CONTAINER.slots + 1*4], STK(NUM_ITEMS + 10, 1, 0)
    mov     dword [rbx + CONTAINER.slots + 2*4], STK(STICK, 0, 3)
    mov     dword [rbx + CONTAINER.slots + 3*4], STK(FURNACE_LIT, 1, 0)
    mov     dword [rbx + CONTAINER.slots + 4*4], STK(IRON_PICKAXE, 1, 9)
    mov     dword [rbx + CONTAINER.slots + 5*4], STK(COBBLE, 64, 0)
    PLACE   8, 11, 5, AIR, CONT_FURNACE ; the furnace block is missing
    PLACE   9, 11, 5, CHEST, CONT_FURNACE ; a furnace record on a chest block
    PLACE   10, 11, 5, CHEST, 3         ; a kind that does not exist
    PLACE   11, 11, 5, CHEST, CONT_CHEST
    mov     r12, rax
    mov     byte [r12 + CONTAINER.y], WORLD_Y ; and a cell above the world
    call    conts_validate
    EXPECT_AT 5, 11, 5, rbx
    cmp     dword [rbx + CONTAINER.slots], 0
    jne     .fail
    cmp     dword [rbx + CONTAINER.slots + 1*4], 0
    jne     .fail
    cmp     dword [rbx + CONTAINER.slots + 2*4], 0
    jne     .fail
    cmp     dword [rbx + CONTAINER.slots + 3*4], 0
    jne     .fail
    cmp     dword [rbx + CONTAINER.slots + 4*4], STK(IRON_PICKAXE, 1, 9)
    jne     .fail
    cmp     dword [rbx + CONTAINER.slots + 5*4], STK(COBBLE, 64, 0)
    jne     .fail
    EXPECT_AT 8, 11, 5, 0
    EXPECT_AT 9, 11, 5, 0
    EXPECT_AT 10, 11, 5, 0
    cmp     dword [r12 + CONTAINER.x], 0
    jne     .fail                       ; the out-of-world record was wiped entirely
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    zero_conts
    call    drops_clear
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret
