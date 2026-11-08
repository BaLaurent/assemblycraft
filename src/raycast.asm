; raycast.asm - voxel ray traversal (Amanatides-Woo DDA) that respects block shapes.
%include "common.inc"
default rel

global raycast

extern world_get, block_shape, cell_boxes

section .rodata
align 4
c_far:  dd 1.0e30                       ; tMax / tDelta of an axis the ray never crosses
c_one:  dd 1.0
; the unit step out of a block through each face struck: -x, +x, -y, +y, -z, +z
face_dx: db -1, 1, 0, 0, 0, 0
face_dy: db 0, 0, -1, 1, 0, 0
face_dz: db 0, 0, 0, 0, -1, 1

section .text

; Frame (rsp-relative): int cell[3], prev[3], step[3]; float tMax[3], tDelta[3], maxdist,
; t_enter (where the ray entered the current cell), best t of the cell's boxes, int boxes left,
; int 1 once a box was hit, int face of the best hit, float boxes[9][6] (the current cell's
; selection boxes).
%define RC_CELL 0
%define RC_PREV 16
%define RC_STEP 32
%define RC_TMAX 48
%define RC_TDLT 64
%define RC_MAX  80
%define RC_TENT 84
%define RC_BEST 88
%define RC_NB   92
%define RC_ANY  96
%define RC_FACE 100
%define RC_BOXES 112
%define RC_FRAME 328

; raycast(rdi float origin[3], rsi float dir[3], rdx RAYHIT* out, xmm0 maxdist) -> eax hit 0/1,
;   xmm0 = distance along the ray to the hit (maxdist on a miss)
; Walks the cells the ray enters, in order, for at most 64 steps or until the next cell
; boundary lies beyond maxdist. A full cube is hit where the ray enters its cell; a shaped
; block (slab, stairs, door, ...) only where the ray meets one of its selection boxes, so
; the ray passes over a slab's empty upper half; air and flames never stop it. On a hit,
; out = { b = block hit, p = the cell in front of the face struck }: for a cube the cell the
; ray came from, for a shaped block the neighbour on the side of the box face it entered
; through (the top face of a slab: the cell above, whichever way the ray arrived).
raycast:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, RC_FRAME
    movss   [rsp + RC_MAX], xmm0
    mov     rbx, rdx
    mov     r13, rdi
    mov     r14, rsi
    mov     dword [rsp + RC_TENT], 0
    xor     ecx, ecx
.setup:                                 ; one pass per axis
    movss   xmm0, [rdi + rcx*4]         ; o
    movss   xmm1, [rsi + rcx*4]         ; d
    roundss xmm2, xmm0, 9               ; floor(o)
    cvttss2si eax, xmm2
    mov     [rsp + RC_CELL + rcx*4], eax
    mov     [rsp + RC_PREV + rcx*4], eax
    movss   xmm5, [c_far]               ; tMax
    movaps  xmm6, xmm5                  ; tDelta
    xor     edx, edx                    ; step
    xorps   xmm3, xmm3
    ucomiss xmm1, xmm3
    jp      .axis_done                  ; NaN direction: treat the axis as not moving
    ja      .pos
    jb      .neg
    jmp     .axis_done                  ; d == 0
.pos:
    mov     edx, 1
    movss   xmm3, [c_one]
    movaps  xmm6, xmm3
    divss   xmm6, xmm1                  ; tDelta = 1/d
    addss   xmm2, xmm3
    subss   xmm2, xmm0                  ; cell + 1 - o
    divss   xmm2, xmm1
    movaps  xmm5, xmm2                  ; tMax
    jmp     .axis_done
.neg:
    mov     edx, -1
    xorps   xmm4, xmm4
    subss   xmm4, xmm1                  ; -d
    movss   xmm6, [c_one]
    divss   xmm6, xmm4                  ; tDelta = 1/-d
    subss   xmm0, xmm2                  ; o - cell
    divss   xmm0, xmm4
    movaps  xmm5, xmm0                  ; tMax
.axis_done:
    mov     [rsp + RC_STEP + rcx*4], edx
    movss   [rsp + RC_TMAX + rcx*4], xmm5
    movss   [rsp + RC_TDLT + rcx*4], xmm6
    inc     ecx
    cmp     ecx, 3
    jb      .setup

    mov     r12d, 64
.loop:
    mov     edi, [rsp + RC_CELL]
    mov     esi, [rsp + RC_CELL + 4]
    mov     edx, [rsp + RC_CELL + 8]
    call    world_get
    movzx   eax, byte [block_shape + rax]
    cmp     eax, SHAPE_CUBE
    je      .hit_cube
    test    eax, eax
    jz      .pass                       ; air, flames
    mov     edi, [rsp + RC_CELL]        ; a shaped block: does the ray meet one of its boxes?
    mov     esi, [rsp + RC_CELL + 4]
    mov     edx, [rsp + RC_CELL + 8]
    lea     rcx, [rsp + RC_BOXES]
    mov     r8d, BOXES_SELECT
    call    cell_boxes
    test    eax, eax
    jz      .pass
    mov     [rsp + RC_NB], eax
    mov     dword [rsp + RC_ANY], 0
    mov     eax, [rsp + RC_MAX]
    mov     [rsp + RC_BEST], eax        ; only a hit nearer than the best so far counts
    lea     r15, [rsp + RC_BOXES]
.shape_box:
    mov     rdi, r13
    mov     rsi, r14
    mov     rdx, r15                    ; box min xyz, then max xyz
    movss   xmm0, [rsp + RC_BEST]
    call    box_face
    test    eax, eax
    js      .shape_next
    movss   [rsp + RC_BEST], xmm0
    mov     [rsp + RC_FACE], eax
    mov     dword [rsp + RC_ANY], 1
.shape_next:
    add     r15, 24
    dec     dword [rsp + RC_NB]
    jnz     .shape_box
    cmp     dword [rsp + RC_ANY], 0
    je      .pass
    mov     eax, [rsp + RC_FACE]
    cmp     eax, 6
    jae     .hit                        ; the ray started inside the box: no face, keep the cell it came from
    movsx   ecx, byte [face_dx + rax]
    add     ecx, [rsp + RC_CELL]
    mov     [rsp + RC_PREV], ecx
    movsx   ecx, byte [face_dy + rax]
    add     ecx, [rsp + RC_CELL + 4]
    mov     [rsp + RC_PREV + 4], ecx
    movsx   ecx, byte [face_dz + rax]
    add     ecx, [rsp + RC_CELL + 8]
    mov     [rsp + RC_PREV + 8], ecx
    jmp     .hit
.pass:
    movss   xmm0, [rsp + RC_TMAX]       ; a = axis with the smallest tMax (ties: x, then y)
    xor     ecx, ecx
    movss   xmm1, [rsp + RC_TMAX + 4]
    ucomiss xmm0, xmm1
    jbe     .not_y
    movaps  xmm0, xmm1
    mov     ecx, 1
.not_y:
    movss   xmm1, [rsp + RC_TMAX + 8]
    ucomiss xmm0, xmm1
    jbe     .not_z
    movaps  xmm0, xmm1
    mov     ecx, 2
.not_z:
    ucomiss xmm0, [rsp + RC_MAX]
    ja      .miss                       ; next boundary is out of reach
    movss   [rsp + RC_TENT], xmm0       ; the ray enters the next cell here
    mov     rax, [rsp + RC_CELL]        ; prev = cell
    mov     [rsp + RC_PREV], rax
    mov     eax, [rsp + RC_CELL + 8]
    mov     [rsp + RC_PREV + 8], eax
    mov     eax, [rsp + RC_STEP + rcx*4]
    add     [rsp + RC_CELL + rcx*4], eax
    addss   xmm0, [rsp + RC_TDLT + rcx*4]
    movss   [rsp + RC_TMAX + rcx*4], xmm0
    dec     r12d
    jnz     .loop
.miss:
    movss   xmm0, [rsp + RC_MAX]
    xor     eax, eax
    jmp     .ret
.hit_cube:
    mov     eax, [rsp + RC_TENT]
    mov     [rsp + RC_BEST], eax
.hit:
    mov     eax, [rsp + RC_CELL]
    mov     [rbx + RAYHIT.bx], eax
    mov     eax, [rsp + RC_CELL + 4]
    mov     [rbx + RAYHIT.by], eax
    mov     eax, [rsp + RC_CELL + 8]
    mov     [rbx + RAYHIT.bz], eax
    mov     eax, [rsp + RC_PREV]
    mov     [rbx + RAYHIT.px], eax
    mov     eax, [rsp + RC_PREV + 4]
    mov     [rbx + RAYHIT.py], eax
    mov     eax, [rsp + RC_PREV + 8]
    mov     [rbx + RAYHIT.pz], eax
    movss   xmm0, [rsp + RC_BEST]
    mov     eax, 1
.ret:
    add     rsp, RC_FRAME
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; box_face(rdi float origin[3], rsi float dir[3], rdx float box[6] = min xyz, max xyz, xmm0 tmax)
;   -> eax the face the ray enters the box through (0 -x, 1 +x, 2 -y, 3 +y, 4 -z, 5 +z; 6 when
;   the origin is inside the box), or -1 when it misses within tmax; xmm0 = entry distance.
;   Slab test; on a tie the earlier axis wins.
box_face:
    xorps   xmm1, xmm1                  ; tmin
    xorps   xmm6, xmm6
    mov     r9d, 6
    xor     r8d, r8d                    ; byte offset of the axis
    xor     r10d, r10d                  ; axis
.axis:
    movss   xmm2, [rdi + r8]            ; o
    movss   xmm3, [rsi + r8]            ; d
    movss   xmm4, [rdx + r8]            ; lo
    movss   xmm5, [rdx + r8 + 12]       ; hi
    ucomiss xmm3, xmm6
    jp      .parallel
    jne     .slab
.parallel:                              ; no movement on this axis: the origin must be inside the slab
    ucomiss xmm2, xmm4
    jb      .miss
    ucomiss xmm2, xmm5
    ja      .miss
    jmp     .next
.slab:
    subss   xmm4, xmm2
    subss   xmm5, xmm2
    divss   xmm4, xmm3                  ; t at lo
    divss   xmm5, xmm3                  ; t at hi
    movaps  xmm7, xmm4
    minss   xmm7, xmm5                  ; entering the slab
    maxss   xmm4, xmm5                  ; leaving it
    minss   xmm0, xmm4
    ucomiss xmm7, xmm1
    jbe     .next                       ; no later than the entry so far
    movaps  xmm1, xmm7
    lea     r9d, [r10 * 2]              ; a ray moving + enters through the lo face (-axis) ...
    ucomiss xmm3, xmm6
    ja      .next
    inc     r9d                         ; ... one moving - through the hi face (+axis)
.next:
    add     r8d, 4
    inc     r10d
    cmp     r10d, 3
    jb      .axis
    ucomiss xmm1, xmm0
    ja      .miss                       ; entry after the exit, or beyond tmax
    movaps  xmm0, xmm1
    mov     eax, r9d
    ret
.miss:
    mov     eax, -1
    ret
