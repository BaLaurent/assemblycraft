; shapes.asm - the boxes a block occupies: rendering, collision and selection geometry of
; full cubes and the shaped blocks (slabs, stairs, doors, trapdoors, ladders, torches,
; fences, glass panes). Boxes are 6 bytes x0,y0,z0,x1,y1,z1 in 1/16 block relative to the
; cell's minimum corner; fence collision boxes reach y1 = 24 (1.5 blocks).
%include "common.inc"
default rel

global shape_boxes, cell_boxes, block_sel_bounds, block_facing_from_yaw
global dir_dx, dir_dz

extern block_shape, block_base, block_flags, world_get, world_column_ready

section .rodata
dir_dx: db 0, 1, 0, -1                  ; DIR_N, DIR_E, DIR_S, DIR_W
dir_dz: db -1, 0, 1, 0

b_cube:        db 0, 0, 0, 16, 16, 16
b_slab:        db 0, 0, 0, 16, 8, 16
b_stairs_top:  db 0, 8, 0, 16, 16, 8    ; N
               db 8, 8, 0, 16, 16, 16   ; E
               db 0, 8, 8, 16, 16, 16   ; S
               db 0, 8, 0, 8, 16, 16    ; W
b_panel:       db 0, 0, 0, 16, 16, 3    ; 3 thick against side N, E, S, W
               db 13, 0, 0, 16, 16, 16
               db 0, 0, 13, 16, 16, 16
               db 0, 0, 0, 3, 16, 16
b_trap_closed: db 0, 0, 0, 16, 3, 16
b_ladder:      db 0, 0, 0, 16, 16, 2    ; 2 thick against side N, E, S, W
               db 14, 0, 0, 16, 16, 16
               db 0, 0, 14, 16, 16, 16
               db 0, 0, 0, 2, 16, 16
b_torch:       db 7, 0, 7, 9, 10, 9
b_torch_wall:  db 7, 3, 0, 9, 13, 2     ; leaning on side N, E, S, W
               db 14, 3, 7, 16, 13, 9
               db 7, 3, 14, 9, 13, 16
               db 0, 3, 7, 2, 13, 9
b_fence_post:  db 6, 0, 6, 10, 16, 10
b_fence_rails: db 7, 6, 0, 9, 9, 6,     7, 12, 0, 9, 15, 6     ; two rails per side
               db 10, 6, 7, 16, 9, 9,   10, 12, 7, 16, 15, 9
               db 7, 6, 10, 9, 9, 16,   7, 12, 10, 9, 15, 16
               db 0, 6, 7, 6, 9, 9,     0, 12, 7, 6, 15, 9
b_fence_post_c: db 6, 0, 6, 10, 24, 10
b_fence_arm_c: db 6, 0, 0, 10, 24, 6
               db 10, 0, 6, 16, 24, 10
               db 6, 0, 10, 10, 24, 16
               db 0, 0, 6, 6, 24, 10
b_fence_arm_s: db 6, 0, 0, 10, 16, 6
               db 10, 0, 6, 16, 16, 10
               db 6, 0, 10, 10, 16, 16
               db 0, 0, 6, 6, 16, 10
b_pane_post:   db 7, 0, 7, 9, 16, 9
b_pane_arm:    db 7, 0, 0, 9, 16, 7
               db 9, 0, 7, 16, 16, 9
               db 7, 0, 9, 9, 16, 16
               db 0, 0, 7, 7, 16, 9
b_bed:         db 0, 0, 0, 16, 9, 16
b_cross_sel:   db 2, 0, 2, 14, 13, 14
b_snow:        db 0, 0, 0, 16, 2, 16
b_cactus:      db 1, 0, 1, 15, 16, 15

align 4
f_sixteenth:   dd 0.0625
f_one:         dd 1.0
f_yaw_bias:    dd 1485.0                ; 45 + 16 * 90: keeps the quotient positive
f_ninety:      dd 90.0

section .text

; shape_boxes(edi id, esi x, edx y, ecx z, r8 out byte[6*MAX_SHAPE_BOXES], r9d purpose) -> eax count
;   the boxes of block `id` standing in cell (x,y,z) for purpose BOXES_RENDER/COLLIDE/SELECT,
;   in 1/16 units relative to the cell's minimum corner. Fence and pane read their 4
;   horizontal neighbours from the world; the other shapes only use id.
; Frame: [rsp] y, [rsp+4] param, [rsp+8] neighbour mask.
shape_boxes:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     r12, r8
    mov     r13d, r9d
    mov     r14d, esi
    mov     r15d, ecx
    mov     edi, edi                    ; id indexes tables: zero the upper half
    mov     [rsp], edx
    xor     ebx, ebx                    ; count
    cmp     edi, NUM_BLOCKS
    jae     .done
    movzx   eax, byte [block_base + rdi]
    mov     ecx, edi
    sub     ecx, eax
    mov     [rsp + 4], ecx              ; param
    movzx   eax, byte [block_shape + rdi]
    cmp     eax, SHAPE_CACTUS
    ja      .done
    lea     rcx, [shape_jump]
    jmp     [rcx + rax*8]

.cube:
    cmp     r13d, BOXES_COLLIDE
    jne     .cube_box
    test    byte [block_flags + rdi], FLAG_SOLID
    jz      .done
.cube_box:
    lea     rsi, [b_cube]
    call    .emit
    jmp     .done
.slab:
    lea     rsi, [b_slab]
    call    .emit
    jmp     .done
.stairs:
    lea     rsi, [b_slab]
    call    .emit
    mov     eax, [rsp + 4]
    and     eax, 3
    lea     rax, [rax + rax*2]
    lea     rsi, [b_stairs_top]
    lea     rsi, [rsi + rax*2]
    call    .emit
    jmp     .done
.door:
    mov     eax, [rsp + 4]
    mov     ecx, eax
    shr     eax, 2                      ; facing
    and     eax, 3
    test    ecx, 2
    jz      .panel                      ; closed: the panel on the facing side
    add     eax, 3                      ; open: swung onto the side to the left
    and     eax, 3
    jmp     .panel
.trapdoor:
    mov     eax, [rsp + 4]
    test    eax, 1
    jnz     .trap_open
    lea     rsi, [b_trap_closed]
    call    .emit
    jmp     .done
.trap_open:
    shr     eax, 1
    and     eax, 3
.panel:                                 ; eax = side
    lea     rax, [rax + rax*2]
    lea     rsi, [b_panel]
    lea     rsi, [rsi + rax*2]
    call    .emit
    jmp     .done
.ladder:
    mov     eax, [rsp + 4]
    and     eax, 3
    lea     rax, [rax + rax*2]
    lea     rsi, [b_ladder]
    lea     rsi, [rsi + rax*2]
    call    .emit
    jmp     .done
.torch:
    cmp     r13d, BOXES_COLLIDE
    je      .done
    mov     eax, [rsp + 4]
    test    eax, eax
    jnz     .torch_wall
    lea     rsi, [b_torch]
    call    .emit
    jmp     .done
.torch_wall:
    dec     eax
    and     eax, 3
    lea     rax, [rax + rax*2]
    lea     rsi, [b_torch_wall]
    lea     rsi, [rsi + rax*2]
    call    .emit
    jmp     .done

.fence:
    mov     edi, SHAPE_FENCE
    call    .neighbours
    cmp     r13d, BOXES_COLLIDE
    je      .fence_collide
    lea     rsi, [b_fence_post]
    call    .emit
    cmp     r13d, BOXES_SELECT
    je      .fence_select
    xor     r15d, r15d                  ; side (z no longer needed)
.rail:
    bt      dword [rsp + 8], r15d
    jnc     .rail_next
    imul    eax, r15d, 12
    lea     rsi, [b_fence_rails]
    add     rsi, rax
    call    .emit
    imul    eax, r15d, 12
    lea     rsi, [b_fence_rails + 6]
    add     rsi, rax
    call    .emit
.rail_next:
    inc     r15d
    cmp     r15d, 4
    jb      .rail
    jmp     .done
.fence_collide:
    lea     rsi, [b_fence_post_c]
    call    .emit
    lea     r14, [b_fence_arm_c]
    jmp     .arms
.fence_select:
    lea     r14, [b_fence_arm_s]
    jmp     .arms
.pane:
    mov     edi, SHAPE_PANE
    call    .neighbours
    cmp     dword [rsp + 8], 0
    jne     .pane_post
    mov     dword [rsp + 8], 15         ; a lone pane shows all four arms
.pane_post:
    lea     rsi, [b_pane_post]
    call    .emit
    lea     r14, [b_pane_arm]
.arms:                                  ; r14 = 4 arm boxes, [rsp+8] = side mask
    xor     r15d, r15d
.arm:
    bt      dword [rsp + 8], r15d
    jnc     .arm_next
    imul    eax, r15d, 6
    lea     rsi, [r14 + rax]
    call    .emit
.arm_next:
    inc     r15d
    cmp     r15d, 4
    jb      .arm
    jmp     .done
.bed:
    lea     rsi, [b_bed]
    call    .emit
    jmp     .done
.cross:                                 ; drawn by the mesher: only the selection box
    cmp     r13d, BOXES_SELECT
    jne     .done
    lea     rsi, [b_cross_sel]
    call    .emit
    jmp     .done
.snow:                                  ; a 2/16 layer you walk through
    cmp     r13d, BOXES_COLLIDE
    je      .done
    lea     rsi, [b_snow]
    call    .emit
    jmp     .done
.cactus:
    lea     rsi, [b_cactus]
    call    .emit
.done:
    mov     eax, ebx
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; .emit(rsi box): append 6 bytes at out + count*6, count++ (clobbers rax, rdi)
.emit:
    lea     rdi, [rbx + rbx*2]
    lea     rdi, [r12 + rdi*2]
    mov     eax, [rsi]
    mov     [rdi], eax
    mov     ax, [rsi + 4]
    mov     [rdi + 4], ax
    inc     ebx
    ret

; .neighbours(edi own shape): [rsp+8] (caller frame) = bit d set when the neighbour on side d
; connects: the same shape, an opaque cube, or (panes) glass. Uses r14d = x, r15d = z, [rsp] = y.
.neighbours:
    push    rbx
    push    r12
    push    r13
    sub     rsp, 16                     ; 8 (ret) + 24 + 16 = 48: aligned for the calls below
    mov     r12d, edi
    xor     r13d, r13d                  ; mask
    xor     ebx, ebx                    ; side
.nb:
    movsx   eax, byte [dir_dx + rbx]
    lea     edi, [r14 + rax]
    mov     esi, [rsp + 48]             ; y, in the caller frame
    movsx   eax, byte [dir_dz + rbx]
    lea     edx, [r15 + rax]
    call    world_get
    movzx   ecx, byte [block_shape + rax]
    cmp     ecx, r12d
    je      .nb_yes
    cmp     r12d, SHAPE_PANE
    jne     .nb_cube
    cmp     eax, GLASS
    je      .nb_yes
.nb_cube:
    cmp     ecx, SHAPE_CUBE
    jne     .nb_next
    test    byte [block_flags + rax], FLAG_OPAQUE
    jz      .nb_next
.nb_yes:
    bts     r13d, ebx
.nb_next:
    inc     ebx
    cmp     ebx, 4
    jb      .nb
    mov     [rsp + 56], r13d            ; caller's [rsp+8]
    add     rsp, 16
    pop     r13
    pop     r12
    pop     rbx
    ret

section .rodata
align 8
shape_jump:
    dq shape_boxes.done                 ; SHAPE_NONE
    dq shape_boxes.cube
    dq shape_boxes.slab
    dq shape_boxes.stairs
    dq shape_boxes.door
    dq shape_boxes.trapdoor
    dq shape_boxes.ladder
    dq shape_boxes.torch
    dq shape_boxes.fence
    dq shape_boxes.pane
    dq shape_boxes.bed
    dq shape_boxes.cross
    dq shape_boxes.done                 ; SHAPE_LIQUID: the mesher's water path draws it
    dq shape_boxes.snow
    dq shape_boxes.cactus

section .text

; cell_boxes(edi x, esi y, edx z, rcx out float[6*MAX_SHAPE_BOXES], r8d purpose) -> eax count
;   the boxes of the block in the cell, in world floats (x0,y0,z0,x1,y1,z1 each). For
;   BOXES_COLLIDE a cell with y < 0 or whose column is not ready (world_column_ready = 0) is
;   one full solid box and y >= WORLD_H is empty; other purposes see AIR there (world_get).
; Frame: [rsp] byte boxes (54), [rsp+56] x, [rsp+60] y, [rsp+64] z.
cell_boxes:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 80
    mov     rbx, rcx
    mov     [rsp + 56], edi
    mov     [rsp + 60], esi
    mov     [rsp + 64], edx
    mov     r12d, r8d
    cmp     r8d, BOXES_COLLIDE
    jne     .lookup
    cmp     esi, WORLD_H
    jge     .empty
    test    esi, esi
    js      .wall
    mov     esi, edx                    ; world_column_ready(x, z)
    call    world_column_ready
    test    eax, eax
    jz      .wall
    mov     edi, [rsp + 56]
    mov     esi, [rsp + 60]
    mov     edx, [rsp + 64]
.lookup:
    call    world_get
    mov     edi, eax
    mov     esi, [rsp + 56]
    mov     edx, [rsp + 60]
    mov     ecx, [rsp + 64]
    lea     r8, [rsp]
    mov     r9d, r12d
    call    shape_boxes
    mov     r12d, eax                   ; count
    test    eax, eax
    jz      .ret
    ; convert: out[i*6 + k] = coord[k%3] + byte * 1/16
    imul    ecx, eax, 6
    xor     edx, edx
.conv:
    movzx   eax, byte [rsp + rdx]
    cvtsi2ss xmm0, eax
    mulss   xmm0, [f_sixteenth]
    mov     eax, edx
    xor     r8d, r8d
.mod3:                                  ; eax = edx % 3 (k < 6 within a box: small loop)
    cmp     eax, 3
    jb      .have_axis
    sub     eax, 3
    jmp     .mod3
.have_axis:
    cvtsi2ss xmm1, dword [rsp + 56 + rax*4]
    addss   xmm0, xmm1
    movss   [rbx + rdx*4], xmm0
    inc     edx
    cmp     edx, ecx
    jb      .conv
    mov     eax, r12d
    jmp     .ret
.wall:
    cvtsi2ss xmm0, dword [rsp + 56]
    cvtsi2ss xmm1, dword [rsp + 60]
    cvtsi2ss xmm2, dword [rsp + 64]
    movss   [rbx], xmm0
    movss   [rbx + 4], xmm1
    movss   [rbx + 8], xmm2
    addss   xmm0, [f_one]
    addss   xmm1, [f_one]
    addss   xmm2, [f_one]
    movss   [rbx + 12], xmm0
    movss   [rbx + 16], xmm1
    movss   [rbx + 20], xmm2
    mov     eax, 1
    jmp     .ret
.empty:
    xor     eax, eax
.ret:
    add     rsp, 80
    pop     r12
    pop     rbx
    pop     rbp
    ret

; block_sel_bounds(edi x, esi y, edx z, rcx out float[6]) -> eax 0/1: the world-float union
;   of the cell's BOXES_SELECT boxes (0 and out untouched when there are none)
block_sel_bounds:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 6 * MAX_SHAPE_BOXES * 4 + 16 ; 232: keeps rsp 16-aligned
    mov     rbx, rcx
    lea     rcx, [rsp]
    mov     r8d, BOXES_SELECT
    call    cell_boxes
    test    eax, eax
    jz      .ret
    movss   xmm4, [rsp + 12]
    movss   xmm5, [rsp + 16]
    movss   xmm6, [rsp + 20]
    movss   xmm1, [rsp]
    movss   xmm2, [rsp + 4]
    movss   xmm3, [rsp + 8]
    mov     ecx, 1
.u:
    cmp     ecx, eax
    jae     .store
    imul    edx, ecx, 24
    minss   xmm1, [rsp + rdx]
    minss   xmm2, [rsp + rdx + 4]
    minss   xmm3, [rsp + rdx + 8]
    maxss   xmm4, [rsp + rdx + 12]
    maxss   xmm5, [rsp + rdx + 16]
    maxss   xmm6, [rsp + rdx + 20]
    inc     ecx
    jmp     .u
.store:
    movss   [rbx], xmm1
    movss   [rbx + 4], xmm2
    movss   [rbx + 8], xmm3
    movss   [rbx + 12], xmm4
    movss   [rbx + 16], xmm5
    movss   [rbx + 20], xmm6
    mov     eax, 1
.ret:
    add     rsp, 6 * MAX_SHAPE_BOXES * 4 + 16
    pop     rbx
    pop     rbp
    ret

; block_facing_from_yaw(xmm0 yaw degrees) -> eax DIR_*: ((int)((yaw + 45) / 90)) & 3,
;   with the quotient kept positive for any yaw > -1485
block_facing_from_yaw:
    addss   xmm0, [f_yaw_bias]
    divss   xmm0, [f_ninety]
    cvttss2si eax, xmm0
    and     eax, 3
    ret
