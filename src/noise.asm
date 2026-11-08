; noise.asm - the integer hash and the value noise the terrain generator is built on.
;
; Everything here is reentrant: registers and stack only. The one global, gen_seed, is set by
; worldgen_set_seed before a session and never written during one, so the generator thread
; (gen_column) and the main thread (gen_height, region_plan, ...) call these at the same time
; without locks. All functions clobber the caller-saved registers (rax, rcx, rdx, rsi, rdi,
; r8-r11, xmm0-xmm15) and keep rbx, rbp, r12-r15.
%include "common.inc"
default rel

global hash32, noise2, noise3, fbm2, gen_seed

section .rodata
align 4
k_inv:    dd 3.0518043793392844e-5      ; 1 / 32767.5
k_one:    dd 1.0
k_three:  dd 3.0
k_half:   dd 0.5

section .bss
gen_seed: resd 1                        ; the world seed hash32 mixes in

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

; LATTICE xmm, reg: reg = the sum hash32 builds before mixing; xmm = the lattice value
; ((hash32 & 0xFFFF) / 32767.5 - 1) in [-1, 1]. Clobbers reg and ecx. Inlined so the corner
; hashes of one noise call overlap in the pipeline.
%macro LATTICE 2
    mov     ecx, %2
    shr     ecx, 15
    xor     %2, ecx
    imul    %2, %2, 0x2C1B3C6D
    mov     ecx, %2
    shr     ecx, 12
    xor     %2, ecx
    imul    %2, %2, 0x297A2D39
    mov     ecx, %2
    shr     ecx, 15
    xor     %2, ecx
    and     %2, 0xFFFF
    pxor    %1, %1
    cvtsi2ss %1, %2
    mulss   %1, [k_inv]
    subss   %1, [k_one]
%endmacro

; SMOOTH f, t1, t2: f = f*f*(3 - 2f) (smoothstep), clobbers t1 and t2
%macro SMOOTH 3
    movaps  %2, %1
    addss   %2, %2
    movss   %3, [k_three]
    subss   %3, %2
    mulss   %1, %1
    mulss   %1, %3
%endmacro

; noise2(edi x, esi z, edx shift, ecx salt) -> xmm0 in [-1, 1]
; Value noise on a lattice of 2^shift blocks: the smoothstep-weighted bilinear blend of the four
; corner values lattice(hash32(ix, iz, salt)). Cell indexes use sar and the fraction is x & mask,
; so the field is continuous across 0.
noise2:
    mov     r8d, ecx                    ; salt
    mov     ecx, edx                    ; cl = shift
    imul    r8d, r8d, 0x85EBCA77
    imul    eax, [gen_seed], 0x9E3779B1
    add     r8d, eax                    ; r8d = the seed and salt terms of every corner's sum
    mov     r9d, edi
    sar     r9d, cl                     ; ix
    mov     r10d, esi
    sar     r10d, cl                    ; iz
    mov     eax, 1
    shl     eax, cl
    dec     eax                         ; cell mask
    and     edi, eax
    and     esi, eax
    mov     edx, 127
    sub     edx, ecx
    shl     edx, 23
    movd    xmm3, edx                   ; 2^-shift, exact
    pxor    xmm0, xmm0
    cvtsi2ss xmm0, edi
    mulss   xmm0, xmm3
    SMOOTH  xmm0, xmm6, xmm7            ; sx
    pxor    xmm1, xmm1
    cvtsi2ss xmm1, esi
    mulss   xmm1, xmm3
    SMOOTH  xmm1, xmm6, xmm7            ; sz
    imul    r9d, r9d, 0x27D4EB2D
    add     r9d, r8d                    ; sum of corner (ix, .) without its z term
    lea     r11d, [r9 + 0x27D4EB2D]     ; the same for ix + 1
    imul    r10d, r10d, 0x165667B1      ; z term of iz
    lea     edx, [r10 + 0x165667B1]     ; z term of iz + 1
    lea     eax, [r9 + r10]
    LATTICE xmm2, eax                   ; v00
    lea     eax, [r11 + r10]
    LATTICE xmm3, eax                   ; v10
    lea     eax, [r9 + rdx]
    LATTICE xmm4, eax                   ; v01
    lea     eax, [r11 + rdx]
    LATTICE xmm5, eax                   ; v11
    subss   xmm3, xmm2
    mulss   xmm3, xmm0
    addss   xmm2, xmm3                  ; a = v00 + (v10 - v00) * sx
    subss   xmm5, xmm4
    mulss   xmm5, xmm0
    addss   xmm4, xmm5                  ; b = v01 + (v11 - v01) * sx
    subss   xmm4, xmm2
    mulss   xmm4, xmm1
    addss   xmm2, xmm4                  ; a + (b - a) * sz
    movaps  xmm0, xmm2
    ret

; noise3(edi x, esi y, edx z, ecx shift, r8d salt) -> xmm0 in [-1, 1]
; Trilinear value noise with smoothstep weights on a lattice of 2^shift blocks. The corner value is
; lattice(hash32(ix ^ (iy * 0x27D4EB2D), iz, salt)). Interpolation order: x, then y, then z.
noise3:
    imul    r8d, r8d, 0x85EBCA77
    imul    eax, [gen_seed], 0x9E3779B1
    add     r8d, eax                    ; seed and salt terms
    mov     r9d, edi
    sar     r9d, cl                     ; ix
    mov     r10d, esi
    sar     r10d, cl                    ; iy
    mov     r11d, edx
    sar     r11d, cl                    ; iz
    mov     eax, 1
    shl     eax, cl
    dec     eax                         ; cell mask
    and     edi, eax
    and     esi, eax
    and     edx, eax
    mov     eax, 127
    sub     eax, ecx
    shl     eax, 23
    movd    xmm3, eax                   ; 2^-shift, exact
    pxor    xmm0, xmm0
    cvtsi2ss xmm0, edi
    mulss   xmm0, xmm3
    SMOOTH  xmm0, xmm6, xmm7            ; sx
    pxor    xmm1, xmm1
    cvtsi2ss xmm1, esi
    mulss   xmm1, xmm3
    SMOOTH  xmm1, xmm6, xmm7            ; sy
    pxor    xmm2, xmm2
    cvtsi2ss xmm2, edx
    mulss   xmm2, xmm3
    SMOOTH  xmm2, xmm6, xmm7            ; sz
    ; the four (a, b) sums: ((ix + a) ^ ((iy + b) * C1)) * C1 + seed/salt terms
    imul    esi, r10d, 0x27D4EB2D       ; iy * C1
    lea     edi, [rsi + 0x27D4EB2D]     ; (iy + 1) * C1
    mov     eax, r9d
    xor     eax, esi
    imul    eax, eax, 0x27D4EB2D
    add     eax, r8d
    mov     r10d, eax                   ; e00
    lea     eax, [r9 + 1]
    xor     eax, esi
    imul    eax, eax, 0x27D4EB2D
    add     eax, r8d
    mov     edx, eax                    ; e10
    mov     eax, r9d
    xor     eax, edi
    imul    eax, eax, 0x27D4EB2D
    add     eax, r8d
    mov     esi, eax                    ; e01
    lea     eax, [r9 + 1]
    xor     eax, edi
    imul    eax, eax, 0x27D4EB2D
    add     eax, r8d
    mov     edi, eax                    ; e11
    imul    r11d, r11d, 0x165667B1      ; z term of iz
    lea     r9d, [r11 + 0x165667B1]     ; z term of iz + 1
    lea     eax, [r10 + r11]
    LATTICE xmm4, eax                   ; v000
    lea     eax, [rdx + r11]
    LATTICE xmm5, eax                   ; v100
    lea     eax, [rsi + r11]
    LATTICE xmm6, eax                   ; v010
    lea     eax, [rdi + r11]
    LATTICE xmm7, eax                   ; v110
    lea     eax, [r10 + r9]
    LATTICE xmm8, eax                   ; v001
    lea     eax, [rdx + r9]
    LATTICE xmm9, eax                   ; v101
    lea     eax, [rsi + r9]
    LATTICE xmm10, eax                  ; v011
    lea     eax, [rdi + r9]
    LATTICE xmm11, eax                  ; v111
    subss   xmm5, xmm4
    mulss   xmm5, xmm0
    addss   xmm4, xmm5                  ; lx(b0, c0) = v000 + (v100 - v000) * sx
    subss   xmm7, xmm6
    mulss   xmm7, xmm0
    addss   xmm6, xmm7                  ; lx(b1, c0)
    subss   xmm9, xmm8
    mulss   xmm9, xmm0
    addss   xmm8, xmm9                  ; lx(b0, c1)
    subss   xmm11, xmm10
    mulss   xmm11, xmm0
    addss   xmm10, xmm11                ; lx(b1, c1)
    subss   xmm6, xmm4
    mulss   xmm6, xmm1
    addss   xmm4, xmm6                  ; ly(c0) = lx(b0) + (lx(b1) - lx(b0)) * sy
    subss   xmm10, xmm8
    mulss   xmm10, xmm1
    addss   xmm8, xmm10                 ; ly(c1)
    subss   xmm8, xmm4
    mulss   xmm8, xmm2
    addss   xmm4, xmm8                  ; ly(c0) + (ly(c1) - ly(c0)) * sz
    movaps  xmm0, xmm4
    ret

; fbm2(edi x, esi z, edx shift, ecx octaves, r8d salt) -> xmm0 in [-1, 1]
; Fractal sum of noise2: octave o has lattice 2^(shift - o), salt + o and weight 0.5^o; the sum is
; divided by the sum of the weights. octaves >= 1 and shift >= octaves - 1.
fbm2:
    push    rbp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24                     ; [0] acc, [4] weight sum, [8] weight
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    mov     r15d, r8d
    pxor    xmm0, xmm0
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm0
    movss   xmm0, [k_one]
    movss   [rsp + 8], xmm0
    xor     ebp, ebp                    ; octave
.oct:
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    sub     edx, ebp
    lea     ecx, [r15 + rbp]
    call    noise2
    mulss   xmm0, [rsp + 8]
    addss   xmm0, [rsp]
    movss   [rsp], xmm0                 ; acc += noise * weight
    movss   xmm1, [rsp + 4]
    addss   xmm1, [rsp + 8]
    movss   [rsp + 4], xmm1             ; weight sum += weight
    movss   xmm1, [rsp + 8]
    mulss   xmm1, [k_half]
    movss   [rsp + 8], xmm1
    inc     ebp
    cmp     ebp, r14d
    jb      .oct
    movss   xmm0, [rsp]
    divss   xmm0, [rsp + 4]
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
