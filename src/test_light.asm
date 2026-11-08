; test_light.asm - sky and block light tests (light.asm).
%include "common.inc"
default rel

global test_light_sky_and_shadow, test_torch_light_falloff
global test_light_update_on_change, test_light_lut

extern blocks, chunk_dirty, light_cells, light_prev
extern world_clear, world_set
extern light_get, light_compute_all, light_update, light_lut_build

section .rodata
align 4
k_quarter: dd 0.25

section .bss
alignb 16
lut: resb 1024

section .text

; fill_box(edi x0, esi y0, edx z0, ecx x1, r8d y1, r9d z1, r10d id): write `id` straight into
; blocks[] over the inclusive box (no light hooks: the tests call light_compute_all themselves)
fill_box:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r11d, ecx
    sub     r11d, edi
    inc     r11d                        ; row width
    mov     r12d, esi                   ; y
    mov     r13d, edx                   ; z0
    mov     r14d, r10d                  ; id
    mov     ebx, edi                    ; x0
.y:
    mov     r10d, r13d                  ; z
.z:
    mov     eax, r12d
    shl     eax, 8
    add     eax, r10d
    shl     eax, 8
    add     eax, ebx
    lea     rdi, [blocks + rax]
    mov     ecx, r11d
    mov     eax, r14d
    rep     stosb
    inc     r10d
    cmp     r10d, r9d
    jbe     .z
    inc     r12d
    cmp     r12d, r8d
    jbe     .y
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; same_as_full() -> eax 0 iff recomputing the whole world from scratch changes no cell: the
; light left by the incremental updates is exactly the light of a fresh computation
same_as_full:
    push    rbp
    mov     rbp, rsp
    lea     rsi, [light_cells]
    lea     rdi, [light_prev]
    mov     ecx, WORLD_VOLUME / 8
    rep     movsq
    call    light_compute_all
    lea     rsi, [light_cells]
    lea     rdi, [light_prev]
    mov     ecx, WORLD_VOLUME / 8
    repe    cmpsq
    setne   al
    movzx   eax, al
    pop     rbp
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
; spreads under it losing one level per step, and the world edges read as sky above / dark below
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
    PACKED  -1, 5, 5, LIGHT_SKY_FULL    ; beside the world
    PACKED  256, 5, 5, LIGHT_SKY_FULL
    PACKED  5, 5, 300, LIGHT_SKY_FULL
    PACKED  5, 64, 5, LIGHT_SKY_FULL    ; above it
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
    SETBLOCK 25, 15, 25, TORCH
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

; changing the world and calling light_update relights only the queued region, marks the chunks
; whose light changed dirty, and leaves exactly the light a full recompute would give
test_light_update_on_change:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    FILL    30, 10, 30, 70, 10, 70, STONE   ; a plate under open sky
    call    light_compute_all
    SKY     40, 11, 40, 15
    SETBLOCK 40, 30, 40, STONE              ; a stone high above it shades its column
    lea     rdi, [chunk_dirty]
    mov     ecx, NUM_CHUNKS
    xor     eax, eax
    rep     stosb                           ; forget what world_set marked
    call    light_update
    SKY     40, 29, 40, 14
    SKY     40, 11, 40, 14
    cmp     byte [chunk_dirty + 34], 1      ; chunk (2, 0, 2) holds (40, 11, 40): only the light change marks it
    jne     .fail
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
    SETBLOCK 78, 11, 60, STONE              ; 18 cells east: that region starts inside the torch's light
    call    light_update
    BLOCK   62, 11, 60, 12                  ; light entering the region from outside must survive
    BLOCK   70, 11, 60, 4
    call    same_as_full
    test    eax, eax
    jnz     .fail
    SETBLOCK 60, 11, 60, AIR
    call    light_update
    BLOCK   60, 11, 60, 0
    BLOCK   61, 11, 60, 0
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
