; light.asm - Minecraft-style light: a sky channel and a block channel per cell.
;
; light_cells holds one byte per world cell (indexed like `blocks`): sky << 4 | block, both 0..15.
;   sky   - 15 in every column down to its first opaque cell, 0 below it; from there it spreads
;           sideways and down through non-opaque cells, losing 1 per step.
;   block - block_light[id] of the cell; it spreads the same way (an opaque emitter keeps its own).
; Opaque means block_flags & FLAG_OPAQUE. Light is not saved: world_load and world_generate call
; light_compute_all, world_set queues the cells whose opacity or emission changed (light_mark) and
; the main loop calls light_update once per frame, which recomputes only the queued regions.
;
; A region is a rectangle of columns over the full height. light_recompute rebuilds one region:
;   1. columns top-down: sky = open ? 15 : 0, block = emission;
;   2. seeds: cells that can raise a neighbour (sky 15 beside a darker open cell, block >= 2) plus,
;      for a partial region, the lit cells just outside its four faces (read-only sources);
;   3. one FIFO flood fill over both channels, never leaving the region;
;   4. partial regions: every cell that differs from its old value marks its chunks dirty.
%include "common.inc"
%include "gl.inc"
default rel

global light_cells, light_prev
global light_get, light_fill_sky, light_compute_all, light_mark, light_update
global light_lut_build, light_brightness_at, light_bind_index, light_bind_at

extern blocks, block_flags, block_light, world_mark_cell_dirty
extern sky_brightness, game_time

%define LQ_SIZE      (1 << 22)          ; ring of cell indices; one slot always stays free
%define LQ_MASK      (LQ_SIZE - 1)
%define MAX_REGIONS  16                 ; queued regions {x0, x1, z0, z1}, merged when they touch
%define MARK_RADIUS  16                 ; light travels 15 cells; one spare column

section .rodata
align 4
; brightness of a light level 0..15 (the lightmap and light_brightness_at share it)
light_curve: dd 0.04, 0.0565, 0.0867, 0.126, 0.172, 0.224, 0.283, 0.346
             dd 0.414, 0.486, 0.562, 0.643, 0.727, 0.815, 0.905, 1.0
light_tint:  dd 1.0, 0.93, 0.80         ; block light is warm: r, g, b multipliers
k_255:       dd 255.0

section .bss
alignb 64
light_cells:  resb WORLD_VOLUME         ; sky << 4 | block, indexed like `blocks`
light_prev:   resb WORLD_VOLUME         ; the region's cells before a partial recompute
light_queue:  resd LQ_SIZE              ; flood-fill ring
col_state:    resb 65536                ; per column: 0xF0 while open to the sky, 0 below an opaque cell
l_opq:        resb 256                  ; 0 for opaque blocks, 0xFF otherwise (ids >= NUM_BLOCKS: 0xFF)
l_emit:       resb 256                  ; block_light by id
l_dec:        resb 256                  ; packed light minus 1 per channel, floored at 0
alignb 16
dirty_list:   resd 4 * MAX_REGIONS      ; x0, x1, z0, z1 per queued region (inclusive)
dirty_n:      resd 1
rg_x0:        resd 1                    ; the region being recomputed (inclusive)
rg_x1:        resd 1
rg_z0:        resd 1
rg_z1:        resd 1
rg_partial:   resd 1                    ; 1: update in place (outside sources, change marking)
q_tail:       resd 1                    ; flood-fill tail while seeding (the head is 0 until then)

section .text

; ---- queries ----------------------------------------------------------------------------------

; light_get(edi x, esi y, edx z) -> eax packed light (sky << 4 | block).
; Beside the world or above it: full sky; below it: dark. Clobbers only eax.
light_get:
    cmp     edi, WORLD_X - 1
    ja      .full
    cmp     edx, WORLD_Z - 1
    ja      .full
    cmp     esi, WORLD_Y - 1
    ja      .vertical
    mov     eax, esi
    shl     eax, 8
    add     eax, edx
    shl     eax, 8
    add     eax, edi
    movzx   eax, byte [light_cells + rax]
    ret
.vertical:
    xor     eax, eax
    test    esi, esi
    js      .ret                        ; below the world
.full:
    mov     eax, LIGHT_SKY_FULL
.ret:
    ret

; light_bind_index(edi idx): the lightmap coordinate of the next vertices drawn (texture unit 1
; reads it as a 256 x 1 texture): glMultiTexCoord2f(GL_TEXTURE1, idx, 0).
light_bind_index:
    sub     rsp, 8
    cvtsi2ss xmm0, edi
    xorps   xmm1, xmm1
    mov     edi, GL_TEXTURE1
    call    glMultiTexCoord2f
    add     rsp, 8
    ret

; light_bind_at(xmm0 x, xmm1 y, xmm2 z): light_bind_index(light_get(floor x, floor y, floor z))
light_bind_at:
    sub     rsp, 8
    roundss xmm0, xmm0, 9
    cvttss2si edi, xmm0
    roundss xmm1, xmm1, 9
    cvttss2si esi, xmm1
    roundss xmm2, xmm2, 9
    cvttss2si edx, xmm2
    call    light_get
    mov     edi, eax
    call    light_bind_index
    add     rsp, 8
    ret

; light_brightness_at(xmm0 x, xmm1 y, xmm2 z) -> xmm0: how bright the cell is, 0.04 .. 1.0:
; max(curve[sky] * sky_brightness(game_time), curve[block]). Tints the hand model.
light_brightness_at:
    push    rbx
    roundss xmm0, xmm0, 9
    cvttss2si edi, xmm0
    roundss xmm1, xmm1, 9
    cvttss2si esi, xmm1
    roundss xmm2, xmm2, 9
    cvttss2si edx, xmm2
    call    light_get
    mov     ebx, eax
    mov     edi, [game_time]
    call    sky_brightness
    lea     rax, [light_curve]
    mov     ecx, ebx
    shr     ecx, 4
    mulss   xmm0, [rax + rcx*4]
    and     ebx, 15
    movss   xmm1, [rax + rbx*4]
    maxss   xmm0, xmm1
    pop     rbx
    ret

; light_lut_build(xmm0 bright, rdi out byte[1024]): the 256 x 1 RGBA lightmap, entry i = packed
; light sky << 4 | block. Per channel the brighter of the sky term curve[sky] * bright and the
; warm block term curve[block] * tint; round(v * 255), alpha 255.
light_lut_build:
    lea     r8, [light_curve]
    lea     r9, [light_tint]
    movss   xmm3, [k_255]
    xor     ecx, ecx                    ; sky
.sky:
    movss   xmm2, [r8 + rcx*4]
    mulss   xmm2, xmm0                  ; the sky term of this row
    xor     edx, edx                    ; block
.block:
    movss   xmm1, [r8 + rdx*4]
    xor     esi, esi                    ; channel
.channel:
    movaps  xmm4, xmm1
    mulss   xmm4, [r9 + rsi*4]
    maxss   xmm4, xmm2
    mulss   xmm4, xmm3
    cvtss2si eax, xmm4
    mov     r10d, 255
    cmp     eax, r10d
    cmova   eax, r10d
    xor     r11d, r11d
    test    eax, eax
    cmovs   eax, r11d
    mov     [rdi + rsi], al
    inc     esi
    cmp     esi, 3
    jb      .channel
    mov     byte [rdi + 3], 255
    add     rdi, 4
    inc     edx
    cmp     edx, 16
    jb      .block
    inc     ecx
    cmp     ecx, 16
    jb      .sky
    ret

; ---- whole-world entry points --------------------------------------------------------------------

; light_fill_sky(): every cell full sky and nothing queued - the light of an empty world
; (world_clear calls it). Clobbers rax, rcx, rdi.
light_fill_sky:
    lea     rdi, [light_cells]
    mov     rax, 0xF0F0F0F0F0F0F0F0
    mov     ecx, WORLD_VOLUME / 8
    rep     stosq
    mov     dword [dirty_n], 0
    ret

; light_compute_all(): the light of the whole world from scratch; nothing stays queued.
light_compute_all:
    sub     rsp, 8
    mov     dword [rg_x0], 0
    mov     dword [rg_x1], WORLD_X - 1
    mov     dword [rg_z0], 0
    mov     dword [rg_z1], WORLD_Z - 1
    mov     dword [rg_partial], 0
    call    light_recompute
    mov     dword [dirty_n], 0
    add     rsp, 8
    ret

; ---- queued updates ---------------------------------------------------------------------------

; light_mark(edi x, esi y, edx z): the cell changed opacity or emission. Queues the columns within
; MARK_RADIUS of it (clamped to the world, full height) for light_update, merged into every queued
; region they overlap or touch, so the queued regions never touch each other. When all
; MAX_REGIONS slots are taken, region 0 is folded into the new one first.
; Clobbers rax, rcx, rdx, rsi, rdi, r8-r11; touches no xmm register.
light_mark:
    lea     r8d, [rdi - MARK_RADIUS]    ; x0
    xor     eax, eax
    test    r8d, r8d
    cmovs   r8d, eax
    lea     r9d, [rdi + MARK_RADIUS]    ; x1
    mov     eax, WORLD_X - 1
    cmp     r9d, eax
    cmovg   r9d, eax
    lea     r10d, [rdx - MARK_RADIUS]   ; z0
    xor     eax, eax
    test    r10d, r10d
    cmovs   r10d, eax
    lea     r11d, [rdx + MARK_RADIUS]   ; z1
    mov     eax, WORLD_Z - 1
    cmp     r11d, eax
    cmovg   r11d, eax
    lea     rsi, [dirty_list]
.rescan:
    mov     ecx, [dirty_n]
.scan:
    test    ecx, ecx
    jz      .none
    dec     ecx
    mov     eax, ecx
    shl     eax, 4                      ; byte offset of region ecx
    mov     edx, [rsi + rax + 4]        ; apart if r.x0 > R.x1 + 1, r.x1 < R.x0 - 1, ...
    inc     edx
    cmp     r8d, edx
    jg      .scan
    mov     edx, [rsi + rax]
    dec     edx
    cmp     r9d, edx
    jl      .scan
    mov     edx, [rsi + rax + 12]
    inc     edx
    cmp     r10d, edx
    jg      .scan
    mov     edx, [rsi + rax + 8]
    dec     edx
    cmp     r11d, edx
    jl      .scan
    mov     edx, [rsi + rax]            ; R already covers r: nothing to queue
    cmp     edx, r8d
    jg      .merge
    mov     edx, [rsi + rax + 4]
    cmp     edx, r9d
    jl      .merge
    mov     edx, [rsi + rax + 8]
    cmp     edx, r10d
    jg      .merge
    mov     edx, [rsi + rax + 12]
    cmp     edx, r11d
    jl      .merge
    ret
.merge:                                 ; r absorbs region at rax, whose slot the last region takes
    mov     edx, [rsi + rax]
    cmp     edx, r8d
    cmovl   r8d, edx
    mov     edx, [rsi + rax + 4]
    cmp     edx, r9d
    cmovg   r9d, edx
    mov     edx, [rsi + rax + 8]
    cmp     edx, r10d
    cmovl   r10d, edx
    mov     edx, [rsi + rax + 12]
    cmp     edx, r11d
    cmovg   r11d, edx
    mov     edx, [dirty_n]
    dec     edx
    mov     [dirty_n], edx
    shl     edx, 4
    mov     rdi, [rsi + rdx]
    mov     [rsi + rax], rdi
    mov     rdi, [rsi + rdx + 8]
    mov     [rsi + rax + 8], rdi
    jmp     .rescan                     ; the grown r may now touch more regions
.none:
    mov     edx, [dirty_n]
    cmp     edx, MAX_REGIONS
    jb      .append
    xor     eax, eax                    ; full: fold region 0 into r and look again
    jmp     .merge
.append:
    shl     edx, 4
    mov     [rsi + rdx], r8d
    mov     [rsi + rdx + 4], r9d
    mov     [rsi + rdx + 8], r10d
    mov     [rsi + rdx + 12], r11d
    inc     dword [dirty_n]
    ret

; light_update(): recompute every queued region in place; chunks whose light changed are marked
; dirty. Cheap when nothing is queued (called every frame).
light_update:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    xor     ebx, ebx
.next:
    cmp     ebx, [dirty_n]
    jae     .done
    mov     eax, ebx
    shl     eax, 4
    lea     rcx, [dirty_list]
    mov     edx, [rcx + rax]
    mov     [rg_x0], edx
    mov     edx, [rcx + rax + 4]
    mov     [rg_x1], edx
    mov     edx, [rcx + rax + 8]
    mov     [rg_z0], edx
    mov     edx, [rcx + rax + 12]
    mov     [rg_z1], edx
    mov     dword [rg_partial], 1
    call    light_recompute
    inc     ebx
    jmp     .next
.done:
    mov     dword [dirty_n], 0
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- region recompute ------------------------------------------------------------------------------

; light_recompute(): rebuild the light of the region rg_x0..rg_x1 x rg_z0..rg_z1 (full height);
; rg_partial = 1 updates a region of an already lit world in place.
light_recompute:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    call    light_tables
    cmp     dword [rg_partial], 0
    je      .columns
    call    light_copy_prev
.columns:
    call    light_columns
    mov     dword [q_tail], 0
    call    light_seeds
    cmp     dword [rg_partial], 0
    je      .flood
    call    light_sources
.flood:
    call    light_flood
    cmp     dword [rg_partial], 0
    je      .done
    call    light_compare
.done:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; light_tables(): the per-id lookup tables of the passes below, and the packed decrement
; l_dec[v] = (max(sky - 1, 0) << 4) | max(block - 1, 0). Ids >= NUM_BLOCKS are transparent and dark.
light_tables:
    xor     ecx, ecx
.id:
    mov     eax, 0xFF
    xor     r8d, r8d
    cmp     ecx, NUM_BLOCKS
    jae     .store
    test    byte [block_flags + rcx], FLAG_OPAQUE
    jz      .emit
    xor     eax, eax
.emit:
    movzx   r8d, byte [block_light + rcx]
.store:
    mov     [l_opq + rcx], al
    mov     [l_emit + rcx], r8b
    mov     edx, ecx
    shr     edx, 4
    mov     esi, ecx
    and     esi, 15
    sub     edx, 1                      ; saturating decrement: the borrow adds the 1 back
    adc     edx, 0
    sub     esi, 1
    adc     esi, 0
    shl     edx, 4
    or      edx, esi
    mov     [l_dec + rcx], dl
    inc     ecx
    cmp     ecx, 256
    jb      .id
    ret

; light_copy_prev(): light_prev = light_cells over the region (to detect what changes)
light_copy_prev:
    mov     r8d, [rg_x1]
    sub     r8d, [rg_x0]
    inc     r8d                         ; row width
    xor     r10d, r10d                  ; y
.layer:
    mov     r11d, [rg_z0]
.row:
    mov     eax, r10d
    shl     eax, 8
    add     eax, r11d
    shl     eax, 8
    add     eax, [rg_x0]
    lea     rsi, [light_cells + rax]
    lea     rdi, [light_prev + rax]
    mov     ecx, r8d
    rep     movsb
    inc     r11d
    cmp     r11d, [rg_z1]
    jbe     .row
    inc     r10d
    cmp     r10d, WORLD_Y
    jb      .layer
    ret

; light_columns(): pass 1 - walk every layer of the region from the top: a column stays open
; (sky 15) down to its first opaque cell; each cell becomes sky | emission.
light_columns:
    lea     rdi, [col_state]
    mov     rax, 0xF0F0F0F0F0F0F0F0
    mov     ecx, 65536 / 8
    rep     stosq
    mov     r9d, [rg_x1]
    sub     r9d, [rg_x0]
    inc     r9d                         ; row width
    mov     r10d, WORLD_Y - 1           ; y
.layer:
    mov     r11d, [rg_z0]
.row:
    mov     eax, r10d
    shl     eax, 8
    add     eax, r11d
    shl     eax, 8
    add     eax, [rg_x0]                ; index of the row's first cell
    lea     rsi, [blocks + rax]
    lea     rdi, [light_cells + rax]
    mov     edx, r11d
    shl     edx, 8
    add     edx, [rg_x0]
    lea     rdx, [col_state + rdx]
    mov     ecx, r9d
.cell:
    movzx   eax, byte [rsi]
    mov     r8b, [rdx]
    and     r8b, [l_opq + rax]
    mov     [rdx], r8b
    or      r8b, [l_emit + rax]
    mov     [rdi], r8b
    inc     rsi
    inc     rdi
    inc     rdx
    dec     ecx
    jnz     .cell
    inc     r11d
    cmp     r11d, [rg_z1]
    jbe     .row
    dec     r10d
    jns     .layer
    ret

; SEEDCHK off: the cell at rcx + off, inside the region, is open and dark (sky 0, not opaque):
; the sky-15 cell rcx can raise it, so rcx is a seed.
%macro SEEDCHK 1
    movzx   edx, byte [light_cells + rcx + %1]
    test    dl, 0xF0
    jnz     %%ok
    movzx   edx, byte [blocks + rcx + %1]
    cmp     byte [l_opq + rdx], 0
    jne     .push
%%ok:
%endmacro

; light_seeds(): pass 2 - enqueue every region cell that can raise a neighbour: block light >= 2,
; or sky 15 beside a non-opaque horizontal neighbour that is still dark (before the flood fill
; only 0 and 15 exist; vertically an open column never has a dark open neighbour).
light_seeds:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    xor     r13d, r13d                  ; y
.y:
    mov     r14d, [rg_z0]               ; z
.z:
    mov     r15d, r13d
    shl     r15d, 8
    add     r15d, r14d
    shl     r15d, 8                     ; (y << 16) | (z << 8)
    mov     ebx, [rg_x0]                ; x
.x:
    lea     ecx, [r15 + rbx]            ; cell index
    movzx   edx, byte [light_cells + rcx]
    mov     esi, edx
    and     esi, 15
    cmp     esi, 2
    jae     .push
    cmp     edx, 0xF0
    jb      .next
    cmp     ebx, [rg_x0]
    jbe     .no_w
    SEEDCHK -1
.no_w:
    cmp     ebx, [rg_x1]
    jae     .no_e
    SEEDCHK 1
.no_e:
    cmp     r14d, [rg_z0]
    jbe     .no_n
    SEEDCHK -256
.no_n:
    cmp     r14d, [rg_z1]
    jae     .next
    SEEDCHK 256
    jmp     .next
.push:
    mov     eax, [q_tail]
    lea     esi, [rax + 1]
    and     esi, LQ_MASK
    jz      .next                       ; full (the head is 0)
    mov     [light_queue + rax*4], ecx
    mov     [q_tail], esi
.next:
    inc     ebx
    cmp     ebx, [rg_x1]
    jbe     .x
    inc     r14d
    cmp     r14d, [rg_z1]
    jbe     .z
    inc     r13d
    cmp     r13d, WORLD_Y
    jb      .y
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; light_sources(): partial regions - enqueue the lit cells (sky >= 2 or block >= 2) just outside
; the region's four horizontal faces. They are never written: they only feed the border cells.
light_sources:
    sub     rsp, 8
    mov     eax, [rg_x0]                ; west face, x = x0 - 1
    test    eax, eax
    jz      .no_w
    mov     edi, [rg_z0]
    shl     edi, 8
    lea     edi, [rdi + rax - 1]
    mov     esi, [rg_z1]
    sub     esi, [rg_z0]
    inc     esi
    mov     edx, 256
    call    light_src_face
.no_w:
    mov     eax, [rg_x1]                ; east face, x = x1 + 1
    cmp     eax, WORLD_X - 1
    jae     .no_e
    mov     edi, [rg_z0]
    shl     edi, 8
    lea     edi, [rdi + rax + 1]
    mov     esi, [rg_z1]
    sub     esi, [rg_z0]
    inc     esi
    mov     edx, 256
    call    light_src_face
.no_e:
    mov     eax, [rg_z0]                ; north face, z = z0 - 1
    test    eax, eax
    jz      .no_n
    dec     eax
    shl     eax, 8
    mov     edi, eax
    add     edi, [rg_x0]
    mov     esi, [rg_x1]
    sub     esi, [rg_x0]
    inc     esi
    mov     edx, 1
    call    light_src_face
.no_n:
    mov     eax, [rg_z1]                ; south face, z = z1 + 1
    cmp     eax, WORLD_Z - 1
    jae     .no_s
    inc     eax
    shl     eax, 8
    mov     edi, eax
    add     edi, [rg_x0]
    mov     esi, [rg_x1]
    sub     esi, [rg_x0]
    inc     esi
    mov     edx, 1
    call    light_src_face
.no_s:
    add     rsp, 8
    ret

; light_src_face(edi pos, esi count, edx step): on each of the 64 layers, the run of `count` cells
; starting at layer position pos (z << 8 | x), `step` apart: enqueue the lit ones.
; Leaf; clobbers rax, rcx, r8-r11.
light_src_face:
    xor     r8d, r8d                    ; y << 16
.layer:
    lea     r9d, [r8 + rdi]             ; cell index
    mov     ecx, esi
.cell:
    movzx   eax, byte [light_cells + r9]
    cmp     eax, 0x20
    jae     .push
    and     eax, 15
    cmp     eax, 2
    jb      .next
.push:
    mov     r10d, [q_tail]
    lea     r11d, [r10 + 1]
    and     r11d, LQ_MASK
    jz      .next                       ; full (the head is 0)
    mov     [light_queue + r10*4], r9d
    mov     [q_tail], r11d
.next:
    add     r9d, edx
    dec     ecx
    jnz     .cell
    add     r8d, 65536
    cmp     r8d, WORLD_Y << 16
    jb      .layer
    ret

; RELAX off: the neighbour at rax + off (inside the region) takes the popped cell's light minus
; one per channel (r8d = sky << 4, r9d = block of the decremented value) unless it is opaque or
; already as bright; a raised neighbour joins the queue (r12d head, r13d tail).
%macro RELAX 1
    lea     edi, [rax + %1]
    movzx   edx, byte [light_cells + rdi]
    mov     esi, edx
    and     esi, 0xF0
    cmp     esi, r8d
    cmovb   esi, r8d                    ; brighter sky
    mov     ecx, edx
    and     ecx, 15
    cmp     ecx, r9d
    cmovb   ecx, r9d                    ; brighter block light
    or      ecx, esi
    cmp     ecx, edx
    je      %%skip                      ; nothing to raise
    movzx   esi, byte [blocks + rdi]
    cmp     byte [l_opq + rsi], 0
    je      %%skip                      ; opaque cells stay dark
    mov     [light_cells + rdi], cl
    lea     esi, [r13 + 1]
    and     esi, LQ_MASK
    cmp     esi, r12d
    je      %%skip                      ; queue full: drop the push
    mov     [light_queue + r13*4], edi
    mov     r13d, esi
%%skip:
%endmacro

; light_flood(): pass 3 - flood fill from the queued seeds. The popped cell may lie outside the
; region (a face source): it then only feeds its one neighbour across the face. Inside, it feeds
; its six neighbours except those past the region's edge.
light_flood:
    push    r12
    push    r13
    sub     rsp, 8
    xor     r12d, r12d                  ; head
    mov     r13d, [q_tail]
.pop:
    cmp     r12d, r13d
    je      .done
    mov     eax, [light_queue + r12*4]
    inc     r12d
    and     r12d, LQ_MASK
    movzx   ecx, byte [light_cells + rax]
    movzx   ecx, byte [l_dec + rcx]
    test    ecx, ecx
    jz      .pop                        ; nothing left to give
    mov     r8d, ecx
    and     r8d, 0xF0                   ; sky
    and     ecx, 15
    mov     r9d, ecx                    ; block
    mov     r10d, eax
    and     r10d, 255                   ; x
    mov     r11d, eax
    shr     r11d, 8
    and     r11d, 255                   ; z
    cmp     r10d, [rg_x0]
    jb      .out_w
    cmp     r10d, [rg_x1]
    ja      .out_e
    cmp     r11d, [rg_z0]
    jb      .out_n
    cmp     r11d, [rg_z1]
    ja      .out_s
    cmp     r10d, [rg_x0]
    jbe     .in_w
    RELAX   -1
.in_w:
    cmp     r10d, [rg_x1]
    jae     .in_e
    RELAX   1
.in_e:
    cmp     r11d, [rg_z0]
    jbe     .in_n
    RELAX   -256
.in_n:
    cmp     r11d, [rg_z1]
    jae     .in_s
    RELAX   256
.in_s:
    cmp     eax, 65536
    jb      .in_d
    RELAX   -65536
.in_d:
    cmp     eax, (WORLD_Y - 1) << 16
    jae     .pop
    RELAX   65536
    jmp     .pop
.out_w:
    RELAX   1
    jmp     .pop
.out_e:
    RELAX   -1
    jmp     .pop
.out_n:
    RELAX   256
    jmp     .pop
.out_s:
    RELAX   -256
    jmp     .pop
.done:
    add     rsp, 8
    pop     r13
    pop     r12
    ret

; light_compare(): pass 4 (partial regions) - every cell whose light differs from light_prev marks
; its chunk neighbourhood dirty so the mesher relights it.
light_compare:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    xor     r12d, r12d                  ; y
.layer:
    mov     r13d, [rg_z0]               ; z
.row:
    mov     r15d, r12d
    shl     r15d, 8
    add     r15d, r13d
    shl     r15d, 8                     ; (y << 16) | (z << 8)
    mov     ebx, [rg_x0]                ; x
.cell:
    lea     r14d, [r15 + rbx]
    mov     al, [light_cells + r14]
    cmp     al, [light_prev + r14]
    je      .same
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    call    world_mark_cell_dirty
.same:
    inc     ebx
    cmp     ebx, [rg_x1]
    jbe     .cell
    inc     r13d
    cmp     r13d, [rg_z1]
    jbe     .row
    inc     r12d
    cmp     r12d, WORLD_Y
    jb      .layer
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
