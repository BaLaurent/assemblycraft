; test_blocks.asm - shaped blocks in play: stepping onto slabs and stairs, doors, ladders,
; fences, the placement variants, support pops and shape-aware picking.
%include "common.inc"
default rel

global test_step_up_slab_not_block, test_stairs_then_block, test_door_blocks_until_opened
global test_ladder_climb, test_fence_cannot_jump, test_place_variants
global test_door_break_removes_pair_and_support, test_raycast_shapes

extern player, body_init, body_step
extern world_clear, world_set, world_get, raycast
extern place_block, block_use, block_removed, block_is_usable
extern mobs_clear, drops, drops_clear, game_mode, cont_at, cont_block_removed

section .rodata
align 4
k_half_w: dd 0.3
k_height: dd 1.8
k_speed:  dd 4.317
k_reach:  dd 5.0
k_11_5:   dd 11.5
k_12:     dd 12.0
k_21:     dd 21.0
k_21_3:   dd 21.3
k_22:     dd 22.0
k_22_1:   dd 22.1
k_22_3:   dd 22.3
k_22_4:   dd 22.4
k_22_8:   dd 22.8
k_23_5:   dd 23.5
k_1_5:    dd 1.5
k_0_5:    dd 0.5
k_t_lo:   dd 1.55
k_t_hi:   dd 1.58

section .bss
align 4
binp:      resb INPUT_size              ; the INPUT handed to body_step
fill_args: resd 7                       ; x0, x1, y0, y1, z0, z1, id
hit:       resb RAYHIT_size             ; the target handed to place_block, filled by raycast

section .text

; SETF mem, float literal
%macro SETF 2
    mov     dword %1, __float32__(%2)
%endmacro

; fail unless the float at %1 equals the float constant at %2
%macro FEQ 2
    movss   xmm0, %1
    ucomiss xmm0, [%2]
    jne     .fail
    jp      .fail
%endmacro

; fail unless the float at %1 is greater than the constant at %2 (NaN fails)
%macro FGT 2
    movss   xmm0, %1
    ucomiss xmm0, [%2]
    jbe     .fail
%endmacro

; fail unless the float at %1 is at least the constant at %2 (NaN fails)
%macro FGE 2
    movss   xmm0, %1
    ucomiss xmm0, [%2]
    jb      .fail
%endmacro

; fail unless the float at %1 is less than the constant at %2 (NaN fails)
%macro FLT 2
    movss   xmm0, [%2]
    ucomiss xmm0, %1
    jbe     .fail
%endmacro

; fail unless the world holds block id %4 at (%1, %2, %3)
%macro WORLD_IS 4
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    call    world_get
    cmp     eax, %4
    jne     .fail
%endmacro

; FILL x0, x1, y0, y1, z0, z1, id: the box of cells (inclusive) becomes block id
%macro FILL 7
    mov     dword [fill_args], %1
    mov     dword [fill_args + 4], %2
    mov     dword [fill_args + 8], %3
    mov     dword [fill_args + 12], %4
    mov     dword [fill_args + 16], %5
    mov     dword [fill_args + 20], %6
    mov     dword [fill_args + 24], %7
    lea     rdi, [fill_args]
    call    fill_box
%endmacro

; STONE floor at y = 10 over x 15..30, z 15..25
%macro FLOOR 0
    FILL    15, 30, 10, 10, 15, 25, STONE
%endmacro

; PLAYER_AT x, y, z, yaw: a standard body, no input
%macro PLAYER_AT 4
    call    reset_player
    SETF    [player + BODY.x], %1
    SETF    [player + BODY.y], %2
    SETF    [player + BODY.z], %3
    SETF    [player + BODY.yaw], %4
%endmacro

; HIT bx, by, bz, px, py, pz: the target handed to place_block
%macro HIT 6
    mov     dword [hit + RAYHIT.bx], %1
    mov     dword [hit + RAYHIT.by], %2
    mov     dword [hit + RAYHIT.bz], %3
    mov     dword [hit + RAYHIT.px], %4
    mov     dword [hit + RAYHIT.py], %5
    mov     dword [hit + RAYHIT.pz], %6
%endmacro

; PLACE item: eax = place_block(item, &hit)
%macro PLACE 1
    mov     edi, %1
    lea     rsi, [hit]
    call    place_block
%endmacro

; fail unless the RAYHIT `hit` is b = (%1, %2, %3), p = (%4, %5, %6)
%macro HIT_IS 6
    cmp     dword [hit + RAYHIT.bx], %1
    jne     .fail
    cmp     dword [hit + RAYHIT.by], %2
    jne     .fail
    cmp     dword [hit + RAYHIT.bz], %3
    jne     .fail
    cmp     dword [hit + RAYHIT.px], %4
    jne     .fail
    cmp     dword [hit + RAYHIT.py], %5
    jne     .fail
    cmp     dword [hit + RAYHIT.pz], %6
    jne     .fail
%endmacro

; USABLE id, expected: fail unless block_is_usable(id) == expected
%macro USABLE 2
    mov     edi, %1
    call    block_is_usable
    cmp     eax, %2
    jne     .fail
%endmacro

; ---- helpers -----------------------------------------------------------------

; fill_box(rdi int args[7] = x0, x1, y0, y1, z0, z1, id): world_set over the inclusive box
fill_box:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r14, rdi
    mov     r13d, [r14 + 16]            ; z
.z:
    mov     r12d, [r14 + 8]             ; y
.y:
    mov     ebx, [r14]                  ; x
.x:
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, [r14 + 24]
    call    world_set
    inc     ebx
    cmp     ebx, [r14 + 4]
    jle     .x
    inc     r12d
    cmp     r12d, [r14 + 12]
    jle     .y
    inc     r13d
    cmp     r13d, [r14 + 20]
    jle     .z
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; reset_player(): standard player body (0.3 x 1.8, walk 4.317), zero input
reset_player:
    push    rbp
    mov     rbp, rsp
    lea     rdi, [player]
    movss   xmm0, [k_half_w]
    movss   xmm1, [k_height]
    movss   xmm2, [k_speed]
    call    body_init
    lea     rdi, [binp]
    mov     ecx, INPUT_size
    xor     eax, eax
    rep     stosb
    pop     rbp
    ret

; run_steps(edi n >= 1): n times body_step(&player, &binp)
run_steps:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
.loop:
    lea     rdi, [player]
    lea     rsi, [binp]
    call    body_step
    dec     ebx
    jnz     .loop
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; count_drops(edi id) -> eax drop records holding that item id
count_drops:
    lea     rsi, [drops]
    mov     ecx, MAX_DROPS
    xor     eax, eax
.l:
    cmp     byte [rsi + DROP.id], dil
    jne     .next
    inc     eax
.next:
    add     rsi, DROP_size
    dec     ecx
    jnz     .l
    ret

; ---- stepping, doors, ladders, fences -----------------------------------------

; walking +x along a row of slabs lifts the player onto it; a full block stays a wall
test_step_up_slab_not_block:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    FLOOR
    FILL    21, 25, 11, 11, 20, 20, PLANK_SLAB
    PLAYER_AT 20.5, 11.0, 20.5, 90.0
    mov     dword [binp + INPUT.fwd], 1
    mov     edi, 40
    call    run_steps
    FGT     [player + BODY.x], k_21_3
    FEQ     [player + BODY.y], k_11_5
    call    world_clear
    FLOOR
    FILL    21, 21, 11, 11, 20, 20, STONE
    PLAYER_AT 20.5, 11.0, 20.5, 90.0
    mov     dword [binp + INPUT.fwd], 1
    mov     edi, 40
    call    run_steps
    FLT     [player + BODY.x], k_21
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret

; stairs facing east: lower step, upper step, then the full-height row beyond
test_stairs_then_block:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    FLOOR
    FILL    21, 21, 11, 11, 20, 20, PLANK_STAIRS + DIR_E
    FILL    22, 27, 11, 11, 20, 20, STONE
    PLAYER_AT 20.5, 11.0, 20.5, 90.0
    mov     dword [binp + INPUT.fwd], 1
    mov     edi, 60
    call    run_steps
    FEQ     [player + BODY.y], k_12
    FGT     [player + BODY.x], k_22_3
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret

; a closed door facing east stops the walk; once opened (both halves) its panel swings to the
; north edge of the cell and the player walks through
test_door_blocks_until_opened:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    FLOOR
    FILL    22, 22, 11, 11, 20, 20, WOOD_DOOR + DIR_E * 4
    FILL    22, 22, 12, 12, 20, 20, WOOD_DOOR + DIR_E * 4 + 1
    PLAYER_AT 20.5, 11.0, 20.5, 90.0
    mov     dword [binp + INPUT.fwd], 1
    mov     edi, 40
    call    run_steps
    FLT     [player + BODY.x], k_22_8
    FGT     [player + BODY.x], k_22_4
    mov     edi, 22
    mov     esi, 11
    mov     edx, 20
    call    block_use
    cmp     eax, 1
    jne     .fail
    WORLD_IS 22, 11, 20, WOOD_DOOR + DIR_E * 4 + 2
    WORLD_IS 22, 12, 20, WOOD_DOOR + DIR_E * 4 + 3
    mov     edi, 40
    call    run_steps
    FGT     [player + BODY.x], k_23_5
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret

; holding forward against a ladder climbs it
test_ladder_climb:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    FLOOR
    FILL    21, 21, 11, 14, 20, 20, LADDER + DIR_E
    FILL    22, 22, 11, 15, 20, 20, STONE
    PLAYER_AT 21.5, 11.0, 20.5, 90.0
    mov     dword [binp + INPUT.fwd], 1
    mov     edi, 40
    call    run_steps
    FGE     [player + BODY.y], k_12
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret

; a fence is 1.5 high: neither walking nor jumping gets over it
test_fence_cannot_jump:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    FLOOR
    FILL    22, 22, 11, 11, 18, 22, FENCE
    PLAYER_AT 20.5, 11.0, 20.5, 90.0
    mov     dword [binp + INPUT.fwd], 1
    mov     dword [binp + INPUT.jump], 1
    mov     edi, 60
    call    run_steps
    FGT     [player + BODY.x], k_22
    FLT     [player + BODY.x], k_22_1
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret

; ---- placement and support ------------------------------------------------------

test_place_variants:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    call    mobs_clear
    FLOOR
    PLAYER_AT 100.5, 11.0, 100.5, 90.0  ; far from every placement
    ; stairs face the way the player looks (east at yaw 90)
    HIT     20, 10, 20, 20, 11, 20
    PLACE   PLANK_STAIRS
    cmp     eax, 1
    jne     .fail
    WORLD_IS 20, 11, 20, PLANK_STAIRS + DIR_E
    ; a trapdoor: base + 2 * facing
    HIT     20, 10, 22, 20, 11, 22
    PLACE   TRAPDOOR
    cmp     eax, 1
    jne     .fail
    WORLD_IS 20, 11, 22, TRAPDOOR + DIR_E * 2
    ; a door looking north: both halves, the lower one first
    SETF    [player + BODY.yaw], 0.0
    HIT     22, 10, 20, 22, 11, 20
    PLACE   WOOD_DOOR
    cmp     eax, 1
    jne     .fail
    WORLD_IS 22, 11, 20, WOOD_DOOR
    WORLD_IS 22, 12, 20, WOOD_DOOR + 1
    mov     edi, 22                     ; a click on the upper half swings both
    mov     esi, 12
    mov     edx, 20
    call    block_use
    cmp     eax, 1
    jne     .fail
    WORLD_IS 22, 11, 20, WOOD_DOOR + 2
    WORLD_IS 22, 12, 20, WOOD_DOOR + 3
    mov     edi, 22                     ; and a click on the lower half closes them again
    mov     esi, 11
    mov     edx, 20
    call    block_use
    cmp     eax, 1
    jne     .fail
    WORLD_IS 22, 11, 20, WOOD_DOOR
    WORLD_IS 22, 12, 20, WOOD_DOOR + 1
    ; a door needs the cell above it free
    mov     edi, 24
    mov     esi, 12
    mov     edx, 20
    mov     ecx, STONE
    call    world_set
    HIT     24, 10, 20, 24, 11, 20
    PLACE   WOOD_DOOR
    test    eax, eax
    jnz     .fail
    WORLD_IS 24, 11, 20, AIR
    ; a slab on the top face of a slab of its own kind makes the full block
    mov     edi, 26
    mov     esi, 11
    mov     edx, 20
    mov     ecx, PLANK_SLAB
    call    world_set
    HIT     26, 11, 20, 26, 12, 20
    PLACE   PLANK_SLAB
    cmp     eax, 1
    jne     .fail
    WORLD_IS 26, 11, 20, PLANKS
    WORLD_IS 26, 12, 20, AIR
    ; ... a different slab stacks on top instead
    HIT     26, 11, 20, 26, 12, 20
    PLACE   COBBLE_SLAB
    cmp     eax, 1
    jne     .fail
    WORLD_IS 26, 12, 20, COBBLE_SLAB
    ; a torch leans on the side of a stone block ...
    mov     edi, 28
    mov     esi, 11
    mov     edx, 24
    mov     ecx, STONE
    call    world_set
    HIT     28, 11, 24, 27, 11, 24
    PLACE   TORCH
    cmp     eax, 1
    jne     .fail
    WORLD_IS 27, 11, 24, TORCH_WALL + DIR_E
    ; ... and stands on a floor
    HIT     20, 10, 24, 20, 11, 24
    PLACE   TORCH
    cmp     eax, 1
    jne     .fail
    WORLD_IS 20, 11, 24, TORCH
    ; a ladder hangs on the side of an opaque block, facing it
    mov     edi, 28
    mov     esi, 11
    mov     edx, 22
    mov     ecx, STONE
    call    world_set
    HIT     28, 11, 22, 27, 11, 22
    PLACE   LADDER
    cmp     eax, 1
    jne     .fail
    WORLD_IS 27, 11, 22, LADDER + DIR_E
    ; a ladder on a top face is refused
    HIT     20, 10, 18, 20, 11, 18
    PLACE   LADDER
    test    eax, eax
    jnz     .fail
    WORLD_IS 20, 11, 18, AIR
    ; items are not blocks, and no block goes where the player stands
    PLACE   STICK
    test    eax, eax
    jnz     .fail
    PLAYER_AT 20.5, 11.0, 18.5, 90.0
    HIT     20, 10, 18, 20, 11, 18
    PLACE   STONE
    test    eax, eax
    jnz     .fail
    WORLD_IS 20, 11, 18, AIR
    ; a slab does not merge into a full block around the player standing on it
    mov     edi, 28
    mov     esi, 11
    mov     edx, 20
    mov     ecx, PLANK_SLAB
    call    world_set
    PLAYER_AT 28.5, 11.5, 20.5, 90.0
    HIT     28, 11, 20, 28, 12, 20
    PLACE   PLANK_SLAB
    test    eax, eax
    jnz     .fail
    WORLD_IS 28, 11, 20, PLANK_SLAB
    PLAYER_AT 100.5, 11.0, 100.5, 90.0
    ; a furnace gets its container record
    HIT     16, 10, 16, 16, 11, 16
    PLACE   FURNACE
    cmp     eax, 1
    jne     .fail
    WORLD_IS 16, 11, 16, FURNACE
    mov     edi, 16
    mov     esi, 11
    mov     edx, 16
    call    cont_at
    test    rax, rax
    jz      .fail
    cmp     byte [rax + CONTAINER.kind], CONT_FURNACE
    jne     .fail
    mov     edi, 16
    mov     esi, 11
    mov     edx, 16
    call    cont_block_removed          ; frees the record again
    ; right clicks: a trapdoor opens and closes, stone does nothing
    mov     edi, 20
    mov     esi, 11
    mov     edx, 22
    call    block_use
    cmp     eax, 1
    jne     .fail
    WORLD_IS 20, 11, 22, TRAPDOOR + DIR_E * 2 + 1
    mov     edi, 20
    mov     esi, 11
    mov     edx, 22
    call    block_use
    cmp     eax, 1
    jne     .fail
    WORLD_IS 20, 11, 22, TRAPDOOR + DIR_E * 2
    mov     edi, 20
    mov     esi, 10
    mov     edx, 22
    call    block_use
    test    eax, eax
    jnz     .fail
    USABLE  CHEST, 1
    USABLE  FURNACE_LIT, 1
    USABLE  CRAFTING_TABLE, 1
    USABLE  WOOD_DOOR + 5, 1
    USABLE  IRON_DOOR + 15, 1
    USABLE  TRAPDOOR + 3, 1
    USABLE  STONE, 0
    USABLE  TORCH, 0
    USABLE  LADDER + 2, 0
    USABLE  GLASS_PANE, 0
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret

; breaking one half of a door removes the other; a torch (or a door) whose support is mined
; pops off and, in Survival, drops as an item
test_door_break_removes_pair_and_support:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    FLOOR
    call    drops_clear
    mov     dword [game_mode], MODE_SURVIVAL
    FILL    22, 22, 11, 11, 20, 20, WOOD_DOOR
    FILL    22, 22, 12, 12, 20, 20, WOOD_DOOR + 1
    mov     edi, 22
    mov     esi, 11
    mov     edx, 20
    xor     ecx, ecx
    call    world_set                   ; the lower half is broken ...
    mov     edi, 22
    mov     esi, 11
    mov     edx, 20
    mov     ecx, WOOD_DOOR
    call    block_removed
    WORLD_IS 22, 12, 20, AIR            ; ... and the upper half goes with it
    ; a wall torch on a stone block to its east: mine the stone
    mov     edi, 28
    mov     esi, 11
    mov     edx, 24
    mov     ecx, STONE
    call    world_set
    mov     edi, 27
    mov     esi, 11
    mov     edx, 24
    mov     ecx, TORCH_WALL + DIR_E
    call    world_set
    mov     edi, 28
    mov     esi, 11
    mov     edx, 24
    xor     ecx, ecx
    call    world_set
    mov     edi, 28
    mov     esi, 11
    mov     edx, 24
    mov     ecx, STONE
    call    block_removed
    WORLD_IS 27, 11, 24, AIR
    mov     edi, TORCH
    call    count_drops
    cmp     eax, 1
    jne     .fail
    ; a wall torch that leans on the far side of its own cell is not ours to pop
    mov     edi, 27
    mov     esi, 11
    mov     edx, 24
    mov     ecx, TORCH_WALL + DIR_W
    call    world_set                   ; leans on x = 26, not on the cell at x = 28
    mov     edi, 28
    mov     esi, 11
    mov     edx, 24
    mov     ecx, STONE
    call    block_removed
    WORLD_IS 27, 11, 24, TORCH_WALL + DIR_W
    ; a door pops with the floor under it, both halves, one door item
    FILL    18, 18, 11, 11, 18, 18, WOOD_DOOR
    FILL    18, 18, 12, 12, 18, 18, WOOD_DOOR + 1
    mov     edi, 18
    mov     esi, 10
    mov     edx, 18
    xor     ecx, ecx
    call    world_set
    mov     edi, 18
    mov     esi, 10
    mov     edx, 18
    mov     ecx, STONE
    call    block_removed
    WORLD_IS 18, 11, 18, AIR
    WORLD_IS 18, 12, 18, AIR
    mov     edi, WOOD_DOOR
    call    count_drops
    cmp     eax, 1
    jne     .fail
    mov     dword [game_mode], MODE_CREATIVE
    call    drops_clear
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     dword [game_mode], MODE_CREATIVE
    call    drops_clear
    mov     eax, 1
    pop     rbp
    ret

; ---- picking ---------------------------------------------------------------------

; Frame: origin[3] @0, dir[3] @16
test_raycast_shapes:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32
    call    world_clear
    mov     edi, 21
    mov     esi, 11
    mov     edx, 20
    mov     ecx, PLANK_SLAB
    call    world_set
    mov     edi, 22
    mov     esi, 11
    mov     edx, 20
    mov     ecx, STONE
    call    world_set
    SETF    [rsp + 0], 20.5
    SETF    [rsp + 4], 11.75
    SETF    [rsp + 8], 20.5
    SETF    [rsp + 16], 1.0
    SETF    [rsp + 20], 0.0
    SETF    [rsp + 24], 0.0
    lea     rdi, [rsp]                  ; over the slab's top: it hits the stone behind it
    lea     rsi, [rsp + 16]
    lea     rdx, [hit]
    movss   xmm0, [k_reach]
    call    raycast
    cmp     eax, 1
    jne     .fail
    HIT_IS  22, 11, 20, 21, 11, 20
    ucomiss xmm0, [k_1_5]
    jne     .fail
    jp      .fail
    SETF    [rsp + 4], 11.25            ; below the top: it hits the slab itself
    lea     rdi, [rsp]
    lea     rsi, [rsp + 16]
    lea     rdx, [hit]
    movss   xmm0, [k_reach]
    call    raycast
    cmp     eax, 1
    jne     .fail
    HIT_IS  21, 11, 20, 20, 11, 20
    ucomiss xmm0, [k_0_5]
    jne     .fail
    jp      .fail
    SETF    [rsp + 0], 20.5             ; from the side, above the top, slanting down: it meets the
    SETF    [rsp + 4], 12.2             ; top face, so the cell in front of it is the one above
    SETF    [rsp + 8], 20.5
    SETF    [rsp + 16], 0.894427
    SETF    [rsp + 20], -0.447214
    SETF    [rsp + 24], 0.0
    lea     rdi, [rsp]
    lea     rsi, [rsp + 16]
    lea     rdx, [hit]
    movss   xmm0, [k_reach]
    call    raycast
    cmp     eax, 1
    jne     .fail
    HIT_IS  21, 11, 20, 21, 12, 20
    ucomiss xmm0, [k_t_lo]
    jbe     .fail
    movss   xmm1, [k_t_hi]
    ucomiss xmm1, xmm0
    jbe     .fail                       ; t is 0.7 / 0.447214 = 1.565
    PLAYER_AT 100.5, 11.0, 100.5, 0.0   ; out of the way: placing a slab there merges with the slab
    PLACE   PLANK_SLAB
    cmp     eax, 1
    jne     .fail
    WORLD_IS 21, 11, 20, PLANKS
    xor     eax, eax
    leave
    ret
.fail:
    mov     eax, 1
    leave
    ret
