; test_light.asm - sky and block light tests (light.asm).
%include "common.inc"
default rel

global test_light_sky_and_shadow, test_torch_light_falloff
global test_light_update_on_change, test_light_lut
global test_light_column_order, test_light_water

extern world_clear, world_set, world_set_raw, world_column, world_chunk
extern light_get, light_compute_all, light_update, light_lut_build, light_column, light_fill_sky

%define SNAP_BYTES (18 * 18 * 4 * 4096) ; the light of chunks 0..3 of the 18 x 18 arena columns

section .rodata
align 4
k_quarter: dd 0.25

section .bss
alignb 16
lut:        resb 1024
alignb 64
snap_a:     resb SNAP_BYTES
snap_b:     resb SNAP_BYTES

section .text

; fill_box(edi x0, esi y0, edx z0, ecx x1, r8d y1, r9d z1, r10d id): world_set_raw over the inclusive box
; (no light or dirty hooks: the tests call light_compute_all themselves)
fill_box:
    push    rbp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40
    mov     [rsp], ecx                  ; x1
    mov     [rsp + 4], r8d              ; y1
    mov     [rsp + 8], r9d              ; z1
    mov     [rsp + 12], r10d            ; id
    mov     [rsp + 16], edi             ; x0
    mov     [rsp + 20], edx             ; z0
    mov     r12d, esi                   ; y
.y:
    mov     r13d, [rsp + 20]            ; z
.z:
    mov     r14d, [rsp + 16]            ; x
.x:
    mov     edi, r14d
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, [rsp + 12]
    call    world_set_raw
    inc     r14d
    cmp     r14d, [rsp]
    jle     .x
    inc     r13d
    cmp     r13d, [rsp + 8]
    jle     .z
    inc     r12d
    cmp     r12d, [rsp + 4]
    jle     .y
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; snap_light(rdi buf): copy the light of chunks 0..3 of every arena column (acz, acx in -1..16) into buf,
; 4096 bytes per chunk; a null chunk reads as 0xF0
snap_light:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 8
    mov     r12, rdi
    mov     r13d, -1                    ; acz
.z:
    mov     r14d, -1                    ; acx
.x:
    xor     ebx, ebx                    ; cy
.cy:
    mov     edi, r14d
    mov     esi, ebx
    mov     edx, r13d
    call    world_chunk
    mov     rdi, r12
    test    rax, rax
    jz      .null
    lea     rsi, [rax + 4096]
    mov     ecx, 512
    rep     movsq
    jmp     .next
.null:
    mov     rax, 0xF0F0F0F0F0F0F0F0
    mov     ecx, 512
    rep     stosq
.next:
    mov     r12, rdi
    inc     ebx
    cmp     ebx, 4
    jb      .cy
    inc     r14d
    cmp     r14d, 16
    jle     .x
    inc     r13d
    cmp     r13d, 16
    jle     .z
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; cmp_light(rdi buf) -> eax 0 iff the light of those chunks is exactly what snap_light stored in buf
cmp_light:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 8
    mov     r12, rdi
    mov     r13d, -1
.z:
    mov     r14d, -1
.x:
    xor     ebx, ebx
.cy:
    mov     edi, r14d
    mov     esi, ebx
    mov     edx, r13d
    call    world_chunk
    test    rax, rax
    jz      .null
    lea     rdi, [rax + 4096]
    mov     rsi, r12
    mov     ecx, 512
    repe    cmpsq
    jne     .diff
    mov     r12, rsi
    jmp     .next
.null:
    mov     rdi, r12
    mov     rax, 0xF0F0F0F0F0F0F0F0
    mov     ecx, 512
    repe    scasq
    jne     .diff
    mov     r12, rdi
.next:
    inc     ebx
    cmp     ebx, 4
    jb      .cy
    inc     r14d
    cmp     r14d, 16
    jle     .x
    inc     r13d
    cmp     r13d, 16
    jle     .z
    xor     eax, eax
    jmp     .ret
.diff:
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; same_as_full() -> eax 0 iff recomputing the whole world from scratch changes no cell: the light left by
; the incremental updates is exactly the light of a fresh computation
same_as_full:
    sub     rsp, 8
    lea     rdi, [snap_a]
    call    snap_light
    call    light_compute_all
    lea     rdi, [snap_a]
    call    cmp_light
    add     rsp, 8
    ret

; FILL x0, y0, z0, x1, y1, z1, id
%macro FILL 7
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    mov     r8d, %5
    mov     r9d, %6
    mov     r10d, %7
    call    fill_box
%endmacro

; LIGHT x, y, z -> eax = light_get
%macro LIGHT 3
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    call    light_get
%endmacro

; SETBLOCK x, y, z, id: world_set
%macro SETBLOCK 4
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    call    world_set
%endmacro

; SKY x, y, z, n / BLOCK x, y, z, n / PACKED x, y, z, v: fail unless that light channel has the value
%macro SKY 4
    LIGHT   %1, %2, %3
    shr     eax, 4
    cmp     eax, %4
    jne     .fail
%endmacro
%macro BLOCK 4
    LIGHT   %1, %2, %3
    and     eax, 15
    cmp     eax, %4
    jne     .fail
%endmacro
%macro PACKED 4
    LIGHT   %1, %2, %3
    cmp     eax, %4
    jne     .fail
%endmacro

; a stone floor at y = 10 and a 5x5 roof at y = 20 centred on (40, 40): the sky stops at the roof,
; spreads under it losing one level per step, and the unloaded world reads as sky above / beside it and
; dark below
test_light_sky_and_shadow:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    FILL    0, 10, 0, 255, 10, 255, STONE
    FILL    38, 20, 38, 42, 20, 42, STONE
    call    light_compute_all
    SKY     40, 25, 40, 15              ; above the roof
    SKY     40, 19, 40, 12              ; under its centre: three steps from the open sky
    SKY     43, 19, 40, 15              ; beside it
    SKY     41, 19, 40, 13
    SKY     38, 19, 38, 14              ; the corner is one step from (37, 19, 38)
    SKY     40, 11, 40, 12              ; the shadow reaches the floor
    SKY     40, 20, 40, 0               ; stone is dark
    SKY     30, 9, 30, 0                ; under the floor
    PACKED  40, 19, 40, 0xC0
    PACKED  -1, 5, 5, LIGHT_SKY_FULL    ; beside the floor: an empty arena column
    PACKED  256, 5, 5, LIGHT_SKY_FULL
    PACKED  5, 5, 300, LIGHT_SKY_FULL   ; past the arena: no column
    PACKED  1000, 5, 1000, LIGHT_SKY_FULL
    PACKED  5, 64, 5, LIGHT_SKY_FULL    ; high above the floor
    PACKED  5, 300, 5, LIGHT_SKY_FULL   ; above the world
    PACKED  5, -1, 5, 0                 ; below it
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret

; a torch in a closed stone cube: 14 at the flame, one less per step, nothing leaks through the shell
test_torch_light_falloff:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    FILL    20, 10, 20, 30, 20, 30, STONE
    FILL    21, 11, 21, 29, 19, 29, AIR     ; hollow, the shell one thick
    FILL    25, 15, 25, 25, 15, 25, TORCH
    call    light_compute_all
    BLOCK   25, 15, 25, 14
    BLOCK   26, 15, 25, 13
    BLOCK   29, 15, 25, 10
    BLOCK   27, 17, 27, 8               ; 2 + 2 + 2 steps away
    BLOCK   32, 15, 25, 0               ; outside the shell
    BLOCK   20, 15, 25, 0               ; stone stays dark
    SKY     25, 16, 25, 0               ; and the box is closed to the sky
    SKY     32, 15, 25, 15
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret

; changing the world and calling light_update relights only the queued region, marks the chunks whose
; light changed dirty, and leaves exactly the light a full recompute would give - also for light that
; enters the region from a column outside it
test_light_update_on_change:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    FILL    30, 10, 30, 70, 10, 70, STONE   ; a plate under open sky
    call    light_compute_all
    SKY     40, 11, 40, 15
    SETBLOCK 40, 30, 40, STONE              ; a stone high above it shades its column
    mov     edi, 2
    mov     esi, 2
    call    world_column
    mov     dword [rax + COLUMN.dirty], 0   ; forget what world_set marked
    call    light_update
    SKY     40, 29, 40, 14
    SKY     40, 11, 40, 14
    mov     edi, 2
    mov     esi, 2
    call    world_column
    test    dword [rax + COLUMN.dirty], 1   ; chunk (2, 0, 2) holds (40, 11, 40): only the light change marks it
    jz      .fail
    call    same_as_full
    test    eax, eax
    jnz     .fail
    SETBLOCK 60, 11, 60, TORCH
    call    light_update
    BLOCK   60, 11, 60, 14
    BLOCK   61, 11, 60, 13
    BLOCK   60, 11, 70, 4
    call    same_as_full
    test    eax, eax
    jnz     .fail
    SETBLOCK 85, 11, 60, STONE              ; two columns east: that region starts inside the torch's light
    call    light_update
    BLOCK   64, 11, 60, 10                  ; light entering the region from outside must survive
    BLOCK   68, 11, 60, 6
    call    same_as_full
    test    eax, eax
    jnz     .fail
    SETBLOCK 60, 11, 60, AIR
    call    light_update
    BLOCK   60, 11, 60, 0
    BLOCK   61, 11, 60, 0
    BLOCK   64, 11, 60, 0
    SKY     60, 11, 60, 15
    call    same_as_full
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret

; the lightmap at sky brightness 0.25: full sky is 25 % grey, a level-14 torch is warm, the floor is
; the dark curve end
test_light_lut:
    push    rbp
    mov     rbp, rsp
    movss   xmm0, [k_quarter]
    lea     rdi, [lut]
    call    light_lut_build
    cmp     dword [lut + 0xF0 * 4], (255 << 24) | (64 << 16) | (64 << 8) | 64
    jne     .fail
    cmp     dword [lut + 0x0E * 4], (255 << 24) | (185 << 16) | (215 << 8) | 231
    jne     .fail
    cmp     dword [lut + 0x00 * 4], (255 << 24) | (8 << 16) | (9 << 8) | 10
    jne     .fail
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret

; ---- lighting columns in any order -------------------------------------------------------------------

; relight_three(): columns (0,0), (1,0), (2,0) back to COL_BLOCKS and every column's light to full sky
relight_three:
    sub     rsp, 8
    xor     edi, edi
    xor     esi, esi
    call    world_column
    mov     dword [rax + COLUMN.state], COL_BLOCKS
    mov     edi, 1
    xor     esi, esi
    call    world_column
    mov     dword [rax + COLUMN.state], COL_BLOCKS
    mov     edi, 2
    xor     esi, esi
    call    world_column
    mov     dword [rax + COLUMN.state], COL_BLOCKS
    call    light_fill_sky
    add     rsp, 8
    ret

; light_col(edi acx): light_column of column (acx, 0)
light_col:
    sub     rsp, 8
    xor     esi, esi
    call    world_column
    mov     rdi, rax
    call    light_column
    add     rsp, 8
    ret

; a stone roof over columns (0,0) and (1,0), a torch under it at the border between them, a wall with a
; hole: lighting the three columns A, B, C in the order A, B, C or C, B, A gives byte-identical light,
; and both equal a full recompute
test_light_column_order:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    FILL    0, 9, 0, 47, 9, 15, STONE       ; floor under all three columns
    FILL    0, 20, 0, 31, 20, 15, STONE     ; the roof over A and B
    FILL    24, 10, 0, 24, 19, 15, STONE    ; a wall in B ...
    FILL    24, 15, 8, 24, 15, 8, AIR       ; ... with a hole
    FILL    15, 15, 8, 15, 15, 8, TORCH     ; the torch at A's east edge
    call    relight_three
    xor     edi, edi
    call    light_col
    mov     edi, 1
    call    light_col
    mov     edi, 2
    call    light_col
    lea     rdi, [snap_a]
    call    snap_light
    BLOCK   15, 15, 8, 14                   ; the torch
    BLOCK   16, 15, 8, 13                   ; and its light one column over
    SKY     31, 19, 8, 14                   ; open sky of C enters under the roof of B
    SKY     25, 15, 8, 8
    SKY     24, 15, 8, 7                    ; through the hole in the wall
    SKY     23, 15, 8, 7                    ; the z = 16 side is 8 cells away
    call    relight_three
    mov     edi, 2
    call    light_col
    mov     edi, 1
    call    light_col
    xor     edi, edi
    call    light_col
    lea     rdi, [snap_b]
    call    snap_light
    lea     rsi, [snap_a]
    lea     rdi, [snap_b]
    mov     ecx, SNAP_BYTES / 8
    repe    cmpsq
    jne     .fail
    lea     rdi, [snap_a]                   ; a full recompute agrees with both
    call    cmp_light
    test    eax, eax
    jnz     .fail
    call    light_compute_all
    lea     rdi, [snap_a]
    call    cmp_light
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret

; water takes one extra step per cell: sky light 14, 13, 12, 11, 10 down a water column under open sky;
; sideways through water a step costs two
test_light_water:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    FILL    4, 9, 4, 8, 9, 8, STONE         ; the floor
    FILL    4, 10, 4, 8, 14, 8, STONE       ; a ring of stone ...
    FILL    5, 10, 5, 7, 14, 7, WATER       ; ... around a 3 x 3 pool, five deep
    call    light_compute_all
    SKY     6, 15, 6, 15                    ; the air above
    SKY     6, 14, 6, 14
    SKY     6, 13, 6, 13
    SKY     6, 12, 6, 12
    SKY     6, 11, 6, 11
    SKY     6, 10, 6, 10
    SKY     4, 14, 6, 0                     ; the ring is stone
    FILL    5, 15, 5, 5, 15, 7, STONE       ; a roof over the west column of the pool
    call    light_compute_all
    SKY     6, 14, 6, 14                    ; the open columns keep their light
    SKY     5, 14, 6, 12                    ; the shaded water gets it sideways: 14 - 1 - 1
    SKY     5, 13, 6, 11
    SKY     5, 10, 6, 8
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret
