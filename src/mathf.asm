; mathf.asm - trig and float->int rounding helpers.
%include "common.inc"
default rel

global sincos_deg, floor_i, ceil_i

section .rodata
deg2rad: dq 0.017453292519943295

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
