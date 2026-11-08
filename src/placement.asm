; placement.asm - putting blocks into the world (slab merging, facing variants, door pairs, beds,
; support rules), using doors and trapdoors, and what becomes of a block's dependents
; (the other half of a door or bed, torches, ladders) when it goes away.
%include "common.inc"
default rel

global place_block, block_use, block_removed, block_is_usable

extern world_get, world_set, world_is_solid, world_column_ready
extern block_shape, block_base, block_flags, block_dig_sound, block_drop, item_max_stack
extern block_facing_from_yaw, dir_dx, dir_dz
extern player, body_intersects_block, mobs_intersect_block
extern cont_create
extern audio_play, audio_play_at, drops_spawn
extern game_mode

section .rodata
align 4
vol_place:  dd 0.8
vol_door:   dd 0.8
c_half:     dd 0.5
c_quarter:  dd 0.25                     ; where harvested items pop up in a cell (game.asm)
; the full block two slabs of one material make, indexed by slab id - PLANK_SLAB
slab_full:  db PLANKS, COBBLE, STONE_BRICK, BRICK, SANDSTONE

section .text

; place_block frame (rsp-relative): the cell the block goes into, a bed's head cell, and 1 when the
; cell is a plant or snow layer the block replaces in place
%define F_CX 0
%define F_CY 4
%define F_CZ 8
%define F_HX 12
%define F_HY 16
%define F_HZ 20
%define F_REPL 24

; facing() -> eax DIR_* the player is looking along
facing:
    movss   xmm0, [player + BODY.yaw]
    jmp     block_facing_from_yaw

; wall_dir(rdi RAYHIT*) -> eax DIR_* from the entered cell p towards the block hit b when b is
; p's horizontal neighbour (the face struck is a side face), else -1
wall_dir:
    mov     eax, [rdi + RAYHIT.py]
    cmp     eax, [rdi + RAYHIT.by]
    jne     .none
    mov     ecx, [rdi + RAYHIT.bx]
    sub     ecx, [rdi + RAYHIT.px]
    mov     edx, [rdi + RAYHIT.bz]
    sub     edx, [rdi + RAYHIT.pz]
    xor     eax, eax
.dir:
    movsx   esi, byte [dir_dx + rax]
    cmp     esi, ecx
    jne     .next
    movsx   esi, byte [dir_dz + rax]
    cmp     esi, edx
    je      .ret
.next:
    inc     eax
    cmp     eax, 4
    jb      .dir
.none:
    mov     eax, -1
.ret:
    ret

; target_flags(rdi RAYHIT*) -> eax block_flags of the block the ray hit
target_flags:
    sub     rsp, 8
    mov     edx, [rdi + RAYHIT.bz]
    mov     esi, [rdi + RAYHIT.by]
    mov     edi, [rdi + RAYHIT.bx]
    call    world_get
    movzx   eax, byte [block_flags + rax]
    add     rsp, 8
    ret

; cell_free(edi x, esi y, edx z) -> eax 1 when a block may be put into the cell: it lies at
; 0 <= y <= 255 in a ready (lit) column and holds air, water, tall grass or a snow layer
cell_free:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    cmp     esi, 255
    ja      .no                         ; unsigned: y < 0 too
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     esi, edx
    call    world_column_ready
    test    eax, eax
    jz      .no
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    call    world_get
    test    eax, eax
    jz      .yes
    cmp     eax, WATER
    je      .yes
    cmp     eax, TALL_GRASS
    je      .yes
    cmp     eax, SNOW_LAYER
    jne     .no
.yes:
    mov     eax, 1
    jmp     .out
.no:
    xor     eax, eax
.out:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; place_block(edi item, rsi RAYHIT* target) -> eax 1 placed / 0 refused
; Puts one block of `item` against the face the ray struck (target.p is the free cell in front
; of block target.b); the caller consumes the item. What goes in depends on the item's shape:
;  - a slab on the top face of the same slab makes the full block of its material in b;
;  - stairs face the way the player looks (base + facing), trapdoors likewise (base + 2 facing);
;  - a door (base + 4 facing, upper half above) needs a free cell above and solid ground below;
;  - a bed goes foot first into the cell (BED + facing, facing = the way the player looks), its
;    head (BED + 4 + facing) one cell further along the facing: both cells must be free with solid
;    ground under each, and both must clear the player and the mobs;
;  - a ladder needs the side face of an opaque block and points at it (base + side);
;  - a torch stands on a solid block's top face, or leans on an opaque block's side face
;    (TORCH_WALL + side);
;  - everything else is the item itself.
; A cell is free (cell_free) when it lies at 0 <= y <= 255 in a ready column and holds air, water,
; tall grass or a snow layer. A targeted tall grass or snow layer is replaced in place: the block
; goes into b itself (a torch there stands on the block below; a ladder cannot hang on a plant).
; Refused: not a block item, cell not free, a placement that does not suit the face, the player or
; a mob in the way (collision boxes of the variant), or no free container record for a furnace or
; chest. Success plays the block's dig sound.
; r13d = shape of the item, r14d = block that goes in, ebx = item, r12 = target.
; Frame: cell x, y, z @0 (placement cell), bed head x, y, z @12, replaced-plant flag @24.
place_block:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40
    xor     eax, eax
    cmp     edi, NUM_BLOCKS
    jae     .ret                        ; tools, food, materials are never placed
    mov     ebx, edi
    mov     r12, rsi
    cmp     byte [item_max_stack + rbx], 0
    je      .ret                        ; lit furnaces, flames, door halves ... have no item form
    movzx   r13d, byte [block_shape + rbx]
    mov     r14d, ebx
    cmp     r13d, SHAPE_SLAB
    jne     .free_cell
    mov     edi, [r12 + RAYHIT.bx]      ; a slab on the top face of the same slab: one full block
    mov     esi, [r12 + RAYHIT.by]
    mov     edx, [r12 + RAYHIT.bz]
    call    world_get
    cmp     eax, ebx
    jne     .free_cell
    mov     eax, [r12 + RAYHIT.px]
    cmp     eax, [r12 + RAYHIT.bx]
    jne     .free_cell
    mov     eax, [r12 + RAYHIT.pz]
    cmp     eax, [r12 + RAYHIT.bz]
    jne     .free_cell
    mov     eax, [r12 + RAYHIT.by]
    inc     eax
    cmp     eax, [r12 + RAYHIT.py]
    jne     .free_cell
    movzx   r14d, byte [slab_full + rbx - PLANK_SLAB]
    mov     eax, [r12 + RAYHIT.bx]      ; the merged block takes the slab's own cell
    mov     [rsp + F_CX], eax
    mov     eax, [r12 + RAYHIT.by]
    mov     [rsp + F_CY], eax
    mov     eax, [r12 + RAYHIT.bz]
    mov     [rsp + F_CZ], eax
    jmp     .entities
.free_cell:
    mov     edi, [r12 + RAYHIT.bx]      ; the block goes into b itself when that is tall grass or a snow
    mov     esi, [r12 + RAYHIT.by]      ; layer ...
    mov     edx, [r12 + RAYHIT.bz]
    call    world_get
    mov     dword [rsp + F_REPL], 0
    cmp     eax, TALL_GRASS
    je      .replace
    cmp     eax, SNOW_LAYER
    jne     .in_front
.replace:
    mov     dword [rsp + F_REPL], 1
    mov     eax, [r12 + RAYHIT.bx]
    mov     [rsp + F_CX], eax
    mov     eax, [r12 + RAYHIT.by]
    mov     [rsp + F_CY], eax
    mov     eax, [r12 + RAYHIT.bz]
    mov     [rsp + F_CZ], eax
    jmp     .shape
.in_front:                              ; ... else into the cell in front of the face, which must be free
    mov     edi, [r12 + RAYHIT.px]
    mov     esi, [r12 + RAYHIT.py]
    mov     edx, [r12 + RAYHIT.pz]
    call    cell_free
    test    eax, eax
    jz      .refuse
    mov     eax, [r12 + RAYHIT.px]
    mov     [rsp + F_CX], eax
    mov     eax, [r12 + RAYHIT.py]
    mov     [rsp + F_CY], eax
    mov     eax, [r12 + RAYHIT.pz]
    mov     [rsp + F_CZ], eax
.shape:
    cmp     r13d, SHAPE_STAIRS
    je      .stairs
    cmp     r13d, SHAPE_TRAPDOOR
    je      .trapdoor
    cmp     r13d, SHAPE_DOOR
    je      .door
    cmp     r13d, SHAPE_BED
    je      .bed
    cmp     r13d, SHAPE_LADDER
    je      .ladder
    cmp     r13d, SHAPE_TORCH
    je      .torch
    jmp     .entities
.stairs:
    call    facing
    add     r14d, eax
    jmp     .entities
.trapdoor:
    call    facing
    lea     r14d, [rbx + rax*2]
    jmp     .entities
.door:
    call    facing
    lea     r14d, [rbx + rax*4]
    mov     edi, [rsp + F_CX]           ; no room for the upper half: refused
    mov     esi, [rsp + F_CY]
    inc     esi
    mov     edx, [rsp + F_CZ]
    call    cell_free
    test    eax, eax
    jz      .refuse
    mov     edi, [rsp + F_CX]
    mov     esi, [rsp + F_CY]
    dec     esi
    mov     edx, [rsp + F_CZ]
    call    world_is_solid
    test    eax, eax
    jz      .refuse                     ; a door stands on something solid
    jmp     .entities
.bed:
    call    facing
    lea     r14d, [rbx + rax]           ; the foot: BED + facing
    movsx   ecx, byte [dir_dx + rax]
    add     ecx, [rsp + F_CX]
    mov     [rsp + F_HX], ecx           ; the head lies one cell along the facing
    mov     ecx, [rsp + F_CY]
    mov     [rsp + F_HY], ecx
    movsx   ecx, byte [dir_dz + rax]
    add     ecx, [rsp + F_CZ]
    mov     [rsp + F_HZ], ecx
    mov     edi, [rsp + F_HX]
    mov     esi, [rsp + F_HY]
    mov     edx, [rsp + F_HZ]
    call    cell_free
    test    eax, eax
    jz      .refuse
    mov     edi, [rsp + F_CX]
    mov     esi, [rsp + F_CY]
    dec     esi
    mov     edx, [rsp + F_CZ]
    call    world_is_solid
    test    eax, eax
    jz      .refuse                     ; both halves rest on something solid
    mov     edi, [rsp + F_HX]
    mov     esi, [rsp + F_HY]
    dec     esi
    mov     edx, [rsp + F_HZ]
    call    world_is_solid
    test    eax, eax
    jz      .refuse
    jmp     .entities
.ladder:
    mov     rdi, r12
    call    wall_dir
    test    eax, eax
    js      .refuse                     ; only on the side of a block
    mov     r15d, eax
    mov     rdi, r12
    call    target_flags
    test    eax, FLAG_OPAQUE
    jz      .refuse                     ; and only on a full opaque one
    lea     r14d, [rbx + r15]
    jmp     .entities
.torch:
    cmp     dword [rsp + F_REPL], 0
    je      .torch_top
    mov     edi, [rsp + F_CX]           ; it replaces a plant: it stands on the block below
    mov     esi, [rsp + F_CY]
    dec     esi
    mov     edx, [rsp + F_CZ]
    call    world_is_solid
    test    eax, eax
    jz      .refuse
    jmp     .entities                   ; r14d is the standing torch
.torch_top:
    mov     eax, [r12 + RAYHIT.px]      ; the top face of b: stands on it
    cmp     eax, [r12 + RAYHIT.bx]
    jne     .torch_wall
    mov     eax, [r12 + RAYHIT.pz]
    cmp     eax, [r12 + RAYHIT.bz]
    jne     .torch_wall
    mov     eax, [r12 + RAYHIT.by]
    inc     eax
    cmp     eax, [r12 + RAYHIT.py]
    jne     .torch_wall
    mov     edi, [r12 + RAYHIT.bx]
    mov     esi, [r12 + RAYHIT.by]
    mov     edx, [r12 + RAYHIT.bz]
    call    world_is_solid
    test    eax, eax
    jz      .refuse
    jmp     .entities                   ; r14d is the standing torch
.torch_wall:
    mov     rdi, r12
    call    wall_dir
    test    eax, eax
    js      .refuse                     ; not the bottom face, not a side face
    mov     r15d, eax
    mov     rdi, r12
    call    target_flags
    test    eax, FLAG_OPAQUE
    jz      .refuse
    lea     r14d, [r15 + TORCH_WALL]
.entities:
    lea     rdi, [player]
    mov     esi, [rsp + F_CX]
    mov     edx, [rsp + F_CY]
    mov     ecx, [rsp + F_CZ]
    mov     r8d, r14d
    call    body_intersects_block
    test    eax, eax
    jnz     .refuse
    mov     edi, [rsp + F_CX]
    mov     esi, [rsp + F_CY]
    mov     edx, [rsp + F_CZ]
    mov     ecx, r14d
    call    mobs_intersect_block
    test    eax, eax
    jnz     .refuse
    cmp     r13d, SHAPE_DOOR
    je      .upper
    cmp     r13d, SHAPE_BED
    jne     .container
    lea     rdi, [player]               ; the bed's head must clear the player and the mobs too
    mov     esi, [rsp + F_HX]
    mov     edx, [rsp + F_HY]
    mov     ecx, [rsp + F_HZ]
    lea     r8d, [r14 + 4]
    call    body_intersects_block
    test    eax, eax
    jnz     .refuse
    mov     edi, [rsp + F_HX]
    mov     esi, [rsp + F_HY]
    mov     edx, [rsp + F_HZ]
    lea     ecx, [r14 + 4]
    call    mobs_intersect_block
    test    eax, eax
    jnz     .refuse
    jmp     .container
.upper:
    lea     rdi, [player]               ; the upper half must clear the player and the mobs too
    mov     esi, [rsp + F_CX]
    mov     edx, [rsp + F_CY]
    inc     edx
    mov     ecx, [rsp + F_CZ]
    lea     r8d, [r14 + 1]
    call    body_intersects_block
    test    eax, eax
    jnz     .refuse
    mov     edi, [rsp + F_CX]
    mov     esi, [rsp + F_CY]
    inc     esi
    mov     edx, [rsp + F_CZ]
    lea     ecx, [r14 + 1]
    call    mobs_intersect_block
    test    eax, eax
    jnz     .refuse
.container:
    mov     ecx, CONT_FURNACE
    cmp     ebx, FURNACE
    je      .make_cont
    mov     ecx, CONT_CHEST
    cmp     ebx, CHEST
    jne     .set
.make_cont:
    mov     edi, [rsp + F_CX]
    mov     esi, [rsp + F_CY]
    mov     edx, [rsp + F_CZ]
    call    cont_create
    test    rax, rax
    jz      .refuse                     ; every container record is in use
.set:
    mov     edi, [rsp + F_CX]
    mov     esi, [rsp + F_CY]
    mov     edx, [rsp + F_CZ]
    mov     ecx, r14d
    call    world_set
    cmp     r13d, SHAPE_DOOR
    je      .set_upper
    cmp     r13d, SHAPE_BED
    jne     .sound
    mov     edi, [rsp + F_HX]           ; the bed's head
    mov     esi, [rsp + F_HY]
    mov     edx, [rsp + F_HZ]
    lea     ecx, [r14 + 4]
    call    world_set
    jmp     .sound
.set_upper:
    mov     edi, [rsp + F_CX]
    mov     esi, [rsp + F_CY]
    inc     esi
    mov     edx, [rsp + F_CZ]
    lea     ecx, [r14 + 1]              ; the upper half
    call    world_set
.sound:
    movzx   edi, byte [block_dig_sound + r14]
    movss   xmm0, [vol_place]
    call    audio_play
    mov     eax, 1
    jmp     .ret
.refuse:
    xor     eax, eax
.ret:
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; block_use(edi x, esi y, edx z) -> eax 1 if the block reacted
; A door swings: this half and its partner (above a lower half, below an upper half, when it
; belongs to the same door group) take the same open bit. A trapdoor flips open/closed. The
; matching sound plays at the cell.
; ebx, r12d, r13d = x, y, z; r14d = id; r15d = door param. Frame: new id @0, partner y @4.
block_use:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    call    world_get
    mov     r14d, eax
    movzx   ecx, byte [block_shape + rax]
    cmp     ecx, SHAPE_DOOR
    je      .door
    cmp     ecx, SHAPE_TRAPDOOR
    jne     .none
    mov     r15d, r14d
    xor     r15d, 1                     ; open bit is param bit 0
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, r15d
    call    world_set
    movzx   eax, byte [block_base + r15]
    mov     ecx, r15d
    sub     ecx, eax
    and     ecx, 1                      ; now open?
    jmp     .sound
.door:
    movzx   eax, byte [block_base + r14]
    mov     r15d, r14d
    sub     r15d, eax                   ; param: facing * 4 + open * 2 + upper
    mov     ecx, r14d
    xor     ecx, 2
    mov     [rsp], ecx                  ; the new id of this half
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    call    world_set
    lea     esi, [r12 + 1]              ; the partner: above a lower half, below an upper one
    lea     eax, [r12 - 1]
    test    r15d, 1
    cmovnz  esi, eax
    mov     [rsp + 4], esi
    mov     edi, ebx
    mov     edx, r13d
    call    world_get
    movzx   ecx, byte [block_base + rax]
    movzx   edx, byte [block_base + r14]
    cmp     ecx, edx
    jne     .door_open                  ; no partner: a lone half swings alone
    mov     ecx, eax
    and     ecx, -3                     ; clear the partner's open bit ...
    mov     edx, [rsp]
    and     edx, 2
    or      ecx, edx                    ; ... and give it this half's
    mov     edi, ebx
    mov     esi, [rsp + 4]
    mov     edx, r13d
    call    world_set
.door_open:
    mov     ecx, [rsp]
    movzx   eax, byte [block_base + r14]
    sub     ecx, eax
    shr     ecx, 1
    and     ecx, 1                      ; now open?
.sound:
    mov     edi, SND_DOOR_CLOSE
    mov     eax, SND_DOOR_OPEN
    test    ecx, ecx
    cmovnz  edi, eax
    cvtsi2ss xmm0, ebx
    addss   xmm0, [c_half]
    cvtsi2ss xmm1, r12d
    addss   xmm1, [c_half]
    cvtsi2ss xmm2, r13d
    addss   xmm2, [c_half]
    movss   xmm3, [vol_door]
    call    audio_play_at
    mov     eax, 1
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; pop_cell(edi x, esi y, edx z): the block in the cell has lost its support. It becomes air
; (what hung on it goes with it) and, in Survival, drops as an item at the cell centre.
pop_cell:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 16
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    call    world_get
    mov     r14d, eax                   ; what pops
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    xor     ecx, ecx
    call    world_set
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, r14d
    call    block_removed
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .ret
    movzx   edi, byte [block_drop + r14]
    test    edi, edi
    jz      .ret
    mov     esi, 1
    xor     edx, edx
    cvtsi2ss xmm0, ebx
    addss   xmm0, [c_half]
    cvtsi2ss xmm1, r12d
    addss   xmm1, [c_quarter]
    cvtsi2ss xmm2, r13d
    addss   xmm2, [c_half]
    call    drops_spawn
.ret:
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; block_removed(edi x, esi y, edx z, ecx old_id): the cell (x, y, z) just became air; its
; old block was `old_id`. A door loses its other half and a bed its other half (no drop: the
; broken half drops the door or the bed). What depended on the cell pops off (pop_cell): a
; standing torch or the lower half of a door above it, and every horizontal neighbour that is
; a ladder or wall torch whose support side points back at the cell.
; ebx, r12d, r13d = x, y, z; r14d = old id; r15d = door / bed param, neighbour direction.
; Frame: neighbour x @0, z @4, expected bed id @8.
block_removed:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    movzx   eax, byte [block_shape + r14]
    cmp     eax, SHAPE_BED
    je      .bed
    cmp     eax, SHAPE_DOOR
    jne     .above
    movzx   eax, byte [block_base + r14]
    mov     r15d, r14d
    sub     r15d, eax                   ; param: bit 0 set = upper half
    lea     esi, [r12 + 1]
    lea     eax, [r12 - 1]
    test    r15d, 1
    cmovnz  esi, eax                    ; the other half's y
    mov     [rsp], esi
    mov     edi, ebx
    mov     edx, r13d
    call    world_get
    movzx   ecx, byte [block_base + rax]
    movzx   edx, byte [block_base + r14]
    cmp     ecx, edx
    jne     .above                      ; not this door's other half
    mov     edi, ebx
    mov     esi, [rsp]
    mov     edx, r13d
    xor     ecx, ecx
    call    world_set
.above:
    mov     edi, ebx
    lea     esi, [r12 + 1]
    mov     edx, r13d
    call    world_get
    cmp     eax, TORCH
    je      .pop_above
    movzx   ecx, byte [block_shape + rax]
    cmp     ecx, SHAPE_DOOR
    jne     .sides
    movzx   ecx, byte [block_base + rax]
    sub     eax, ecx
    test    eax, 1
    jnz     .sides                      ; an upper half hangs on its lower half, not on us
.pop_above:
    mov     edi, ebx
    lea     esi, [r12 + 1]
    mov     edx, r13d
    call    pop_cell
.sides:
    xor     r15d, r15d                  ; direction of the neighbour from this cell
.dir:
    movsx   edi, byte [dir_dx + r15]
    add     edi, ebx
    movsx   edx, byte [dir_dz + r15]
    add     edx, r13d
    mov     [rsp], edi
    mov     [rsp + 4], edx
    mov     esi, r12d
    call    world_get
    lea     ecx, [r15 + 2]
    and     ecx, 3                      ; the neighbour's side that faces this cell
    mov     edx, eax
    sub     edx, LADDER
    cmp     edx, 3
    jbe     .attached                   ; a ladder: its id - LADDER is its support side
    mov     edx, eax
    sub     edx, TORCH_WALL
    cmp     edx, 3
    ja      .next_dir                   ; a wall torch: id - TORCH_WALL is its support side
.attached:
    cmp     edx, ecx
    jne     .next_dir
    mov     edi, [rsp]
    mov     esi, r12d
    mov     edx, [rsp + 4]
    call    pop_cell
.next_dir:
    inc     r15d
    cmp     r15d, 4
    jb      .dir
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
.bed:                                   ; the other half of the bed goes too, without a drop
    mov     eax, r14d
    sub     eax, BED
    mov     r15d, eax                   ; param: bit 2 = head, bits 0..1 = facing (foot -> head)
    and     eax, 3
    movsx   edi, byte [dir_dx + rax]
    movsx   edx, byte [dir_dz + rax]
    lea     ecx, [rax + BED + 4]        ; a foot looks for the head one cell along its facing ...
    test    r15d, 4
    jz      .bed_partner
    neg     edi                         ; ... a head for the foot one cell back
    neg     edx
    lea     ecx, [rax + BED]
.bed_partner:
    add     edi, ebx
    add     edx, r13d
    mov     [rsp], edi
    mov     [rsp + 4], edx
    mov     [rsp + 8], ecx
    mov     esi, r12d
    call    world_get
    cmp     eax, [rsp + 8]
    jne     .above                      ; not this bed's other half
    mov     edi, [rsp]
    mov     esi, r12d
    mov     edx, [rsp + 4]
    xor     ecx, ecx
    call    world_set
    mov     edi, [rsp]
    mov     esi, r12d
    mov     edx, [rsp + 4]
    mov     ecx, [rsp + 8]
    call    block_removed               ; what rested on or leaned against that half pops too
    jmp     .above

; block_is_usable(edi id) -> eax 1 when a right click on the block does something (it is
; not placed against): crafting table, furnace (lit or not), chest, door, trapdoor, bed
block_is_usable:
    mov     edi, edi
    mov     eax, 1
    cmp     edi, CRAFTING_TABLE
    je      .ret
    cmp     edi, FURNACE
    je      .ret
    cmp     edi, FURNACE_LIT
    je      .ret
    cmp     edi, CHEST
    je      .ret
    xor     eax, eax
    cmp     edi, NUM_BLOCKS
    jae     .ret
    movzx   ecx, byte [block_shape + rdi]
    cmp     ecx, SHAPE_DOOR
    je      .yes
    cmp     ecx, SHAPE_BED
    je      .yes
    cmp     ecx, SHAPE_TRAPDOOR
    jne     .ret
.yes:
    mov     eax, 1
.ret:
    ret
