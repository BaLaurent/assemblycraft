; mathf.asm - trig, float->int rounding and the shared xorshift32 RNG.
%include "common.inc"
default rel

global sincos_deg, atan2_deg, floor_i, ceil_i, rng_seed, rng_next, exp2_ss

section .rodata
deg2rad: dq 0.017453292519943295
rad2deg: dq 57.29577951308232

section .data
align 4
rng_state: dd 0x12345678

section .text

; sincos_deg(xmm0 deg) -> xmm0 sin, xmm1 cos. Leaves the x87 stack empty.
sincos_deg:
    sub     rsp, 8
    movss   [rsp], xmm0
    fld     dword [rsp]
    fmul    qword [deg2rad]
    fsincos                             ; st0 = cos, st1 = sin
    fstp    dword [rsp]
    fstp    dword [rsp + 4]
    movss   xmm1, [rsp]
    movss   xmm0, [rsp + 4]
    add     rsp, 8
    ret

; exp2_ss(xmm0 x) -> xmm0 2^x, for any finite x. Clobbers only xmm0 and the x87 stack, which it
; leaves empty (sfx.asm's renderer keeps its state in xmm1..xmm15 across this call).
exp2_ss:
    sub     rsp, 8
    movss   [rsp], xmm0
    fld     dword [rsp]                 ; x
    fld     st0                         ; x, x
    frndint                             ; r = round(x), x
    fsub    st1, st0                    ; r, f = x - r in [-0.5, 0.5]
    fxch                                ; f, r
    f2xm1                               ; 2^f - 1, r
    fld1
    faddp   st1, st0                    ; 2^f, r
    fscale                              ; 2^x, r
    fstp    st1                         ; 2^x
    fstp    dword [rsp]
    movss   xmm0, [rsp]
    add     rsp, 8
    ret

; atan2_deg(xmm0 y, xmm1 x) -> xmm0 degrees in (-180, 180]. Leaves the x87 stack empty.
atan2_deg:
    sub     rsp, 8
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    fld     dword [rsp]                 ; y
    fld     dword [rsp + 4]             ; x
    fpatan                              ; st0 = atan2(y, x)
    fmul    qword [rad2deg]
    fstp    dword [rsp]
    movss   xmm0, [rsp]
    add     rsp, 8
    ret

; rng_seed(edi seed): zero becomes 0x9E3779B9
rng_seed:
    test    edi, edi
    jnz     .set
    mov     edi, 0x9E3779B9
.set:
    mov     [rng_state], edi
    ret

; rng_next() -> eax: xorshift32
rng_next:
    mov     eax, [rng_state]
    mov     ecx, eax
    shl     ecx, 13
    xor     eax, ecx
    mov     ecx, eax
    shr     ecx, 17
    xor     eax, ecx
    mov     ecx, eax
    shl     ecx, 5
    xor     eax, ecx
    mov     [rng_state], eax
    ret

; floor_i(xmm0) -> eax
floor_i:
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    ret

; ceil_i(xmm0) -> eax
ceil_i:
    roundss xmm0, xmm0, 10
    cvttss2si eax, xmm0
    ret
