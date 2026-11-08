; test_shapes.asm - block shape geometry tests (shapes.asm).
%include "common.inc"
default rel

global test_shapes_boxes

extern shape_boxes, cell_boxes, block_sel_bounds, block_facing_from_yaw
extern world_clear, world_set

section .rodata
box_stairs_e:  db 8, 8, 0, 16, 16, 16
box_door_n:    db 0, 0, 0, 16, 16, 3
box_door_open: db 0, 0, 0, 3, 16, 16
box_fence_e:   db 10, 0, 6, 16, 24, 10
align 4
full_box:      dd -1.0, 5.0, 0.0, 0.0, 6.0, 1.0
slab_sel:      dd 3.0, 4.0, 5.0, 4.0, 4.5, 6.0

section .bss
alignb 16
bbuf:   resb 6 * MAX_SHAPE_BOXES
alignb 16
fbuf:   resd 6 * MAX_SHAPE_BOXES

section .text

; BOXES id, x, y, z, purpose: eax = shape_boxes(...) into bbuf
%macro BOXES 5
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    lea     r8, [bbuf]
    mov     r9d, %5
    call    shape_boxes
%endmacro

; SAME6 a, b: fail unless the 6 bytes at a and b match
%macro SAME6 2
    mov     eax, [%1]
    cmp     eax, [%2]
    jne     .fail
    mov     ax, [%1 + 4]
    cmp     ax, [%2 + 4]
    jne     .fail
%endmacro

; SAMEF n, a, b: fail unless the n floats at a and b are equal
%macro SAMEF 3
%assign k 0
%rep %1
    movss   xmm0, [%2 + k*4]
    ucomiss xmm0, [%3 + k*4]
    jne     .fail
    jp      .fail
%assign k k + 1
%endrep
%endmacro

test_shapes_boxes:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    ; stairs facing east: the slab plus the upper half on the +x side
    BOXES   PLANK_STAIRS + DIR_E, 10, 10, 10, BOXES_COLLIDE
    cmp     eax, 2
    jne     .fail
    SAME6   bbuf + 6, box_stairs_e
    ; a closed door facing north is a panel on the north side; opened it swings west
    BOXES   WOOD_DOOR, 10, 10, 10, BOXES_COLLIDE
    cmp     eax, 1
    jne     .fail
    SAME6   bbuf, box_door_n
    BOXES   WOOD_DOOR + 2, 10, 10, 10, BOXES_COLLIDE
    cmp     eax, 1
    jne     .fail
    SAME6   bbuf, box_door_open
    ; a fence joins the stone east of it: a 1.5-high post and arm
    mov     edi, 21
    mov     esi, 10
    mov     edx, 20
    mov     ecx, STONE
    call    world_set
    mov     edi, 20
    mov     esi, 10
    mov     edx, 20
    mov     ecx, FENCE
    call    world_set
    BOXES   FENCE, 20, 10, 20, BOXES_COLLIDE
    cmp     eax, 2
    jne     .fail
    SAME6   bbuf + 6, box_fence_e
    BOXES   FENCE, 20, 10, 20, BOXES_RENDER ; post + two rails
    cmp     eax, 3
    jne     .fail
    ; a lone pane shows its post and four arms
    BOXES   GLASS_PANE, 40, 10, 40, BOXES_RENDER
    cmp     eax, 5
    jne     .fail
    ; a pane between glass and a pane joins only those two sides
    mov     edi, 41
    mov     esi, 10
    mov     edx, 40
    mov     ecx, GLASS
    call    world_set
    mov     edi, 40
    mov     esi, 10
    mov     edx, 41
    mov     ecx, GLASS_PANE
    call    world_set
    BOXES   GLASS_PANE, 40, 10, 40, BOXES_RENDER
    cmp     eax, 3
    jne     .fail
    ; torches never collide but can be selected
    BOXES   TORCH, 10, 10, 10, BOXES_COLLIDE
    test    eax, eax
    jnz     .fail
    BOXES   TORCH_WALL + DIR_E, 10, 10, 10, BOXES_SELECT
    cmp     eax, 1
    jne     .fail
    cmp     byte [bbuf], 14             ; leaning on the east wall
    jne     .fail
    ; outside the world is one full collision box
    mov     edi, -1
    mov     esi, 5
    xor     edx, edx
    lea     rcx, [fbuf]
    mov     r8d, BOXES_COLLIDE
    call    cell_boxes
    cmp     eax, 1
    jne     .fail
    SAMEF   6, fbuf, full_box
    ; above the world nothing collides
    mov     edi, 5
    mov     esi, WORLD_Y
    mov     edx, 5
    lea     rcx, [fbuf]
    mov     r8d, BOXES_COLLIDE
    call    cell_boxes
    test    eax, eax
    jnz     .fail
    ; the selection bounds of a slab are its lower half
    mov     edi, 3
    mov     esi, 4
    mov     edx, 5
    mov     ecx, PLANK_SLAB
    call    world_set
    mov     edi, 3
    mov     esi, 4
    mov     edx, 5
    lea     rcx, [fbuf]
    call    block_sel_bounds
    cmp     eax, 1
    jne     .fail
    SAMEF   6, fbuf, slab_sel
    mov     edi, 3
    mov     esi, 5
    mov     edx, 5
    lea     rcx, [fbuf]
    call    block_sel_bounds             ; air: nothing to select
    test    eax, eax
    jnz     .fail
    ; facing from yaw
    mov     eax, __float32__(91.0)
    movd    xmm0, eax
    call    block_facing_from_yaw
    cmp     eax, DIR_E
    jne     .fail
    mov     eax, __float32__(359.0)
    movd    xmm0, eax
    call    block_facing_from_yaw
    cmp     eax, DIR_N
    jne     .fail
    mov     eax, __float32__(200.0)
    movd    xmm0, eax
    call    block_facing_from_yaw
    cmp     eax, DIR_S
    jne     .fail
    call    world_clear
    xor     eax, eax
    pop     rbp
    ret
.fail:
    call    world_clear
    mov     eax, 1
    pop     rbp
    ret
