; worldgen.asm - deterministic heightmap terrain, sand beaches and trees.
%include "common.inc"
default rel

global world_generate

extern blocks, world_header
extern world_clear, world_mark_all_dirty

section .rodata
align 4
k_inv:    dd 3.0518043793392844e-5      ; 1 / 32767.5
k_one:    dd 1.0
k_three:  dd 3.0
k_base:   dd 30.0
amps:     dd 14.0, 7.0, 3.5, 1.75

section .bss
alignb 64
heightmap: resb 65536                   ; index z*256 + x
gen_seed:  resd 1

section .text

; hash32(edi ix, esi iz, edx k) -> eax   (seed taken from gen_seed)
hash32:
    imul    eax, edi, 0x27D4EB2D
    imul    esi, esi, 0x165667B1
    add     eax, esi
    imul    ecx, [gen_seed], 0x9E3779B1
    add     eax, ecx
    imul    edx, edx, 0x85EBCA77
    add     eax, edx
    mov     ecx, eax
    shr     ecx, 15
    xor     eax, ecx
    imul    eax, eax, 0x2C1B3C6D
    mov     ecx, eax
    shr     ecx, 12
    xor     eax, ecx
    imul    eax, eax, 0x297A2D39
    mov     ecx, eax
    shr     ecx, 15
    xor     eax, ecx
    ret

; lattice(edi ix, esi iz, edx k) -> xmm0 in [-1, 1]
lattice:
    sub     rsp, 8
    call    hash32
    add     rsp, 8
    movzx   eax, ax
    pxor    xmm0, xmm0
    cvtsi2ss xmm0, eax
    mulss   xmm0, [k_inv]
    subss   xmm0, [k_one]
    ret

; smoothstep: xmm0 = f*f*(3-2f); clobbers xmm1, xmm2
%macro SMOOTH 0
    movaps  xmm1, xmm0
    addss   xmm1, xmm1
    movss   xmm2, [k_three]
    subss   xmm2, xmm1
    mulss   xmm0, xmm0
    mulss   xmm0, xmm2
%endmacro

; noise(edi x, esi z, edx shift, ecx k) -> xmm0
noise:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 24                     ; [0]=sx [4]=sz [8]=v00 [12]=v10 [16]=v01
    mov     r13d, ecx
    mov     ecx, edx
    mov     ebx, edi
    shr     ebx, cl
    mov     r12d, esi
    shr     r12d, cl
    mov     eax, 1
    shl     eax, cl
    mov     edx, eax                    ; cell size
    dec     eax                         ; mask
    pxor    xmm3, xmm3
    cvtsi2ss xmm3, edx
    and     edi, eax
    and     esi, eax
    pxor    xmm0, xmm0
    cvtsi2ss xmm0, edi
    divss   xmm0, xmm3
    SMOOTH
    movss   [rsp], xmm0
    pxor    xmm0, xmm0
    cvtsi2ss xmm0, esi
    divss   xmm0, xmm3
    SMOOTH
    movss   [rsp + 4], xmm0
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    call    lattice
    movss   [rsp + 8], xmm0
    lea     edi, [rbx + 1]
    mov     esi, r12d
    mov     edx, r13d
    call    lattice
    movss   [rsp + 12], xmm0
    mov     edi, ebx
    lea     esi, [r12 + 1]
    mov     edx, r13d
    call    lattice
    movss   [rsp + 16], xmm0
    lea     edi, [rbx + 1]
    lea     esi, [r12 + 1]
    mov     edx, r13d
    call    lattice                     ; xmm0 = v11
    movss   xmm1, [rsp + 16]
    subss   xmm0, xmm1
    mulss   xmm0, [rsp]
    addss   xmm0, xmm1                  ; b = lerp(v01, v11, sx)
    movss   xmm1, [rsp + 8]
    movss   xmm2, [rsp + 12]
    subss   xmm2, xmm1
    mulss   xmm2, [rsp]
    addss   xmm1, xmm2                  ; a = lerp(v00, v10, sx)
    subss   xmm0, xmm1
    mulss   xmm0, [rsp + 4]
    addss   xmm0, xmm1
    add     rsp, 24
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; column_height(edi x, esi z) -> eax in [5, 56]
column_height:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8                      ; [0] accumulator
    mov     ebx, edi
    mov     r12d, esi
    movss   xmm0, [k_base]
    movss   [rsp], xmm0
    xor     r13d, r13d
.oct:
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, 6
    sub     edx, r13d
    mov     ecx, r13d
    call    noise
    lea     rax, [amps]
    mulss   xmm0, [rax + r13*4]
    addss   xmm0, [rsp]
    movss   [rsp], xmm0
    inc     r13d
    cmp     r13d, 4
    jb      .oct
    movss   xmm0, [rsp]
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    mov     ecx, 5
    cmp     eax, ecx
    cmovl   eax, ecx
    mov     ecx, 56
    cmp     eax, ecx
    cmovg   eax, ecx
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; place_layer(edi x, esi y, edx z, ecx r, r8d skipcorners)
; Writes LEAVES into AIR cells of the square |dx|,|dz| <= r (leaf function).
place_layer:
    lea     rax, [blocks]
    shl     esi, 16
    shl     edx, 8
    add     esi, edx
    add     esi, edi
    add     rax, rsi                    ; rax = &blocks[x,y,z]
    mov     edi, ecx
    imul    edi, edi                    ; r*r
    mov     r9d, ecx
    neg     r9d                         ; dz
.dz:
    mov     r10d, ecx
    neg     r10d                        ; dx
.dx:
    test    r8d, r8d
    jz      .place
    mov     edx, r9d
    imul    edx, edx
    cmp     edx, edi
    jne     .place
    mov     edx, r10d
    imul    edx, edx
    cmp     edx, edi
    je      .skip                       ; corner
.place:
    mov     edx, r9d
    shl     edx, 8
    add     edx, r10d
    movsxd  rdx, edx
    cmp     byte [rax + rdx], AIR
    jne     .skip
    mov     byte [rax + rdx], LEAVES
.skip:
    inc     r10d
    cmp     r10d, ecx
    jle     .dx
    inc     r9d
    cmp     r9d, ecx
    jle     .dz
    ret

; world_generate(edi seed)
world_generate:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     [gen_seed], edi
    call    world_clear
    ; ---- terrain columns ----
    xor     r12d, r12d                  ; z
.hz:
    xor     ebx, ebx                    ; x
.hx:
    mov     edi, ebx
    mov     esi, r12d
    call    column_height
    mov     r13d, eax                   ; h
    mov     eax, r12d
    shl     eax, 8
    or      eax, ebx                    ; z*256 + x
    lea     rcx, [heightmap]
    mov     [rcx + rax], r13b
    lea     rdi, [blocks]
    add     rdi, rax                    ; column base (y = 0)
    mov     byte [rdi], BEDROCK
    mov     eax, DIRT                   ; filler id (y h-3..h-1)
    mov     edx, GRASS                  ; top id (y h)
    cmp     r13d, 22
    jg      .land
    mov     eax, SAND
    mov     edx, SAND
.land:
    lea     rsi, [rdi + 65536]
    mov     ecx, 1                      ; y
    lea     r10d, [r13 - 4]
.yl:
    mov     r8d, STONE
    cmp     ecx, r10d
    jle     .set
    mov     r8d, eax
    cmp     ecx, r13d
    jl      .set
    mov     r8d, edx
.set:
    mov     [rsi], r8b
    add     rsi, 65536
    inc     ecx
    cmp     ecx, r13d
    jle     .yl
    inc     ebx
    cmp     ebx, 256
    jb      .hx
    inc     r12d
    cmp     r12d, 256
    jb      .hz
    ; ---- trees ----
    mov     r12d, 2                     ; z
.tz:
    mov     ebx, 2                      ; x
.tx:
    mov     eax, r12d
    shl     eax, 8
    or      eax, ebx
    lea     rcx, [heightmap]
    movzx   r13d, byte [rcx + rax]      ; h
    mov     eax, r13d
    shl     eax, 16
    mov     ecx, r12d
    shl     ecx, 8
    or      eax, ecx
    or      eax, ebx                    ; index of ground cell
    lea     rsi, [blocks]
    cmp     byte [rsi + rax], GRASS
    jne     .nexttree
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, 99
    call    hash32
    mov     r14d, eax                   ; t
    movzx   eax, r14b
    cmp     eax, 3
    jae     .nexttree
    mov     eax, r14d
    shr     eax, 8
    xor     edx, edx
    mov     ecx, 3
    div     ecx
    lea     r15d, [rdx + 4]             ; trunk height H
    lea     eax, [r13 + r15 + 1]        ; base + H
    cmp     eax, 63
    jg      .nexttree
    mov     eax, r13d
    shl     eax, 16
    mov     ecx, r12d
    shl     ecx, 8
    or      eax, ecx
    or      eax, ebx
    lea     rdi, [blocks]
    add     rdi, rax
    mov     byte [rdi], DIRT
    mov     ecx, r15d
.trunk:
    add     rdi, 65536
    mov     byte [rdi], LOG
    dec     ecx
    jnz     .trunk
    ; leaves: layers base+H-3, base+H-2 (r=2, corners cut), base+H-1 (r=1), base+H (r=1, corners cut)
    mov     edi, ebx
    lea     esi, [r13 + r15 - 2]
    mov     edx, r12d
    mov     ecx, 2
    mov     r8d, 1
    call    place_layer
    mov     edi, ebx
    lea     esi, [r13 + r15 - 1]
    mov     edx, r12d
    mov     ecx, 2
    mov     r8d, 1
    call    place_layer
    mov     edi, ebx
    lea     esi, [r13 + r15]
    mov     edx, r12d
    mov     ecx, 1
    xor     r8d, r8d
    call    place_layer
    mov     edi, ebx
    lea     esi, [r13 + r15 + 1]
    mov     edx, r12d
    mov     ecx, 1
    mov     r8d, 1
    call    place_layer
.nexttree:
    inc     ebx
    cmp     ebx, 254
    jb      .tx
    inc     r12d
    cmp     r12d, 254
    jb      .tz
    mov     eax, [gen_seed]
    mov     [world_header + WORLDHDR.seed], eax
    call    world_mark_all_dirty
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
