; light.asm - Minecraft-style light: a sky channel and a block channel per cell.
;
; Light lives in the second half of every chunk (CHUNK_BYTES = 4096 block bytes, then 4096 light
; bytes, same index): sky << 4 | block, both 0..15. A null chunk reads as full sky (0xF0).
;   sky   - 15 in every column down to its first opaque cell, 0 below it; from there it spreads
;           sideways and down through non-opaque cells, losing 1 per step. WATER and ICE (l_att) take
;           one extra step per cell entered, in both channels.
;   block - block_light[id] of the cell; it spreads the same way (an opaque emitter keeps its own).
; Opaque means block_flags & FLAG_OPAQUE. Light is never saved: light_column lights a freshly
; installed column (stream.asm), light_update recomputes the regions that world_set queued.
;
; Both entry points run the same window recompute (light_region) over a flat copy of the area:
;   window  - a rectangle of whole columns: the region R plus a ring of one column. Block ids go to
;             w_blk and light to w_lit, index y << 14 | z << 7 | x (x, z relative to the window), for
;             the layers 0 .. ycap + 1; columns that are not lit are opaque dark walls. ycap is the
;             highest top of the window plus 16 (cells above it are plain sky). Layer ycap + 1 is a
;             read-only source layer.
;   passes  - 1. columns top-down over R: sky = open ? 15 : 0 (minus l_att per water cell), block =
;                emission; 2. seeds: cells that can raise a neighbour; 3. sources: the lit cells just
;                outside R's four faces and above it, read-only; 4. one FIFO flood fill over both
;                channels; 5. scatter: changed light goes back to the chunks (a null chunk is
;                allocated on its first write that differs from 0xF0) and the chunks around a changed
;                cell are marked dirty.
;   mode 0  - an edit region (light_update): only R is recomputed; the ring is read-only.
;   mode 1  - light_column: R is the one column; the flood may also raise the lit columns of the ring
;             (light travels at most 15 cells), so lighting columns in any order gives the same light.
; Everything here runs on the main thread.
%include "common.inc"
%include "gl.inc"
default rel

global light_get, light_fill_sky, light_compute_all, light_column, light_mark, light_update
global light_lut_build, light_brightness_at, light_bind_index, light_bind_at

extern columns, world_locate, world_column, world_chunk_alloc
extern block_flags, block_light, world_origin_x, world_origin_z
extern sky_brightness, game_time

%define LQ_SIZE      (1 << 22)          ; ring of window cell indices; one slot always stays free
%define LQ_MASK      (LQ_SIZE - 1)
%define MAX_REGIONS  16                 ; queued edit regions {cx0, cx1, cz0, cz1}, merged when they touch
%define WIN_CELLS    (128 * 128 * 256)  ; window index = y << 14 | z << 7 | x
%define CHUNK_LIGHT  4096               ; offset of a chunk's light bytes

section .rodata
align 16
k_f0:       times 16 db 0xF0            ; the light of a null chunk
k_stone:    times 16 db STONE           ; the block ids of a wall column
align 4
; brightness of a light level 0..15 (the lightmap and light_brightness_at share it)
light_curve: dd 0.04, 0.0565, 0.0867, 0.126, 0.172, 0.224, 0.283, 0.346
             dd 0.414, 0.486, 0.562, 0.643, 0.727, 0.815, 0.905, 1.0
light_tint:  dd 1.0, 0.93, 0.80         ; block light is warm: r, g, b multipliers
k_255:       dd 255.0

section .bss
alignb 4096
w_blk:        resb WIN_CELLS            ; the window's block ids
w_lit:        resb WIN_CELLS            ; the window's light
light_queue:  resd LQ_SIZE              ; flood-fill ring
col_sky:      resb 128 * 128            ; per window (z << 7 | x): the sky state of the column pass
l_opq:        resb 256                  ; 0 for opaque blocks, 0xFF otherwise (ids >= NUM_BLOCKS: 0xFF)
l_emit:       resb 256                  ; block_light by id
l_att:        resb 256                  ; 0x10 (one sky step) for translucent WATER / ICE, else 0
l_dec:        resb 256                  ; packed light minus 1 per channel, floored at 0
alignb 16
dirty_list:   resd 4 * MAX_REGIONS      ; cx0, cx1, cz0, cz1 per queued region (absolute chunk coordinates)
dirty_n:      resd 1
tables_built: resd 1
wcol:         resq 64                   ; window column [j * 8 + i] -> COLUMN* (0: a wall)
lr_center:    resq 1                    ; mode 1: the column being lit (writable although COL_BLOCKS)
lr_cx0:       resd 1                    ; the region (absolute chunk coordinates)
lr_cx1:       resd 1
lr_cz0:       resd 1
lr_cz1:       resd 1
lr_mode:      resd 1
lr_nx:        resd 1                    ; region size in columns
lr_nz:        resd 1
wn_x:         resd 1                    ; window size in columns (region + 2)
wn_z:         resd 1
wcx0:         resd 1                    ; absolute chunk coordinates of window column 0
wcz0:         resd 1
wycap:        resd 1                    ; the highest layer that is recomputed
wlayers:      resd 1                    ; layers gathered: ycap + 2 (source layer), at most 256
rg_x0:        resd 1                    ; the region in window cells (inclusive)
rg_x1:        resd 1
rg_z0:        resd 1
rg_z1:        resd 1
fb_x0:        resd 1                    ; where the flood may write, window cells (inclusive)
fb_x1:        resd 1
fb_z0:        resd 1
fb_z1:        resd 1
fl_ycap14:    resd 1                    ; ycap << 14: first cell index of the top layer
fl_beyond14:  resd 1                    ; (ycap + 1) << 14: first index above the written layers
sf_end14:     resd 1                    ; src_face: the layer offset (<< 14) to stop at
q_tail:       resd 1                    ; flood-fill tail while seeding (the head is 0 until then)

section .text

; ---- queries ----------------------------------------------------------------------------------

; light_get(edi x, esi y, edx z) -> eax packed light (sky << 4 | block), local coordinates.
; Above the world and in a column that is not lit: full sky; below the world: dark.
; Clobbers only eax.
light_get:
    push    rcx
    push    r8
    push    r9
    push    r10
    test    esi, esi
    js      .dark
    cmp     esi, 255
    ja      .full
    call    world_locate
    test    r9, r9
    jz      .full
    test    r10, r10
    jz      .full
    movzx   eax, byte [r10 + rax + CHUNK_LIGHT]
    jmp     .ret
.dark:
    xor     eax, eax
    jmp     .ret
.full:
    mov     eax, LIGHT_SKY_FULL
.ret:
    pop     r10
    pop     r9
    pop     r8
    pop     rcx
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

; ---- whole-world entry points ------------------------------------------------------------------------

; col_light_reset(rdi COLUMN*): the light of every allocated chunk back to full sky.
; Clobbers rax, rcx, rdx, rsi, r8; preserves rdi.
col_light_reset:
    mov     rsi, rdi
    mov     r8, 0xF0F0F0F0F0F0F0F0
    xor     edx, edx
.chunk:
    mov     rax, [rsi + COLUMN.chunks + rdx*8]
    test    rax, rax
    jz      .next
    push    rdi
    lea     rdi, [rax + CHUNK_LIGHT]
    mov     ecx, 4096 / 8
    mov     rax, r8
    rep     stosq
    pop     rdi
.next:
    inc     edx
    cmp     edx, COL_CHUNKS
    jb      .chunk
    ret

; light_fill_sky(): the light of every column that holds blocks goes back to full sky and nothing
; stays queued - the light of an empty world. Clobbers rax, rcx, rdx, rsi, rdi, r8, r9.
light_fill_sky:
    lea     r9, [columns]
    mov     r10d, MAX_COLUMNS
.col:
    cmp     dword [r9 + COLUMN.state], COL_BLOCKS
    jb      .next
    mov     rdi, r9
    call    col_light_reset
.next:
    add     r9, COLUMN_size
    dec     r10d
    jnz     .col
    mov     dword [dirty_n], 0
    ret

; light_compute_all(): the light of every column from scratch - lit columns go back to COL_BLOCKS
; with full-sky chunks, then every column that holds blocks is lit in table order (any order gives
; the same light). Nothing stays queued.
light_compute_all:
    push    rbx
    push    r12
    sub     rsp, 8
    lea     rbx, [columns]
    mov     r12d, MAX_COLUMNS
.reset:
    cmp     dword [rbx + COLUMN.state], COL_LIT
    jne     .rn
    mov     dword [rbx + COLUMN.state], COL_BLOCKS
    mov     dword [rbx + COLUMN.dirty], 0xFFFF
    mov     rdi, rbx
    call    col_light_reset
.rn:
    add     rbx, COLUMN_size
    dec     r12d
    jnz     .reset
    lea     rbx, [columns]
    mov     r12d, MAX_COLUMNS
.light:
    cmp     dword [rbx + COLUMN.state], COL_BLOCKS
    jne     .ln
    mov     rdi, rbx
    call    light_column
.ln:
    add     rbx, COLUMN_size
    dec     r12d
    jnz     .light
    mov     dword [dirty_n], 0
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; light_column(rdi COLUMN*): light a column that holds blocks (state COL_BLOCKS, or lit again):
; compute its own light from the sky and its emitters, take the light of the lit columns around it,
; give it back to them where it is brighter, and set the column COL_LIT and fully dirty.
light_column:
    push    rbx
    mov     rbx, rdi
    mov     edi, [rbx + COLUMN.cx]
    mov     esi, edi
    mov     edx, [rbx + COLUMN.cz]
    mov     ecx, edx
    mov     r8d, 1
    mov     r9, rbx
    call    light_region
    mov     dword [rbx + COLUMN.state], COL_LIT
    mov     dword [rbx + COLUMN.dirty], 0xFFFF
    pop     rbx
    ret

; ---- queued updates ---------------------------------------------------------------------------------------

; light_mark(edi x, esi y, edx z): the cell changed opacity, translucency or emission (local
; coordinates). Queues the 3 x 3 columns around it for light_update, merged into every queued region
; it overlaps or touches while the result stays within 4 x 4 columns, so queued regions never touch
; each other unless merging them would exceed that. When all MAX_REGIONS slots are taken, region 0 is
; recomputed on the spot and its slot reused.
; Clobbers rax, rcx, rdx, rsi, rdi, r8-r11; preserves every xmm register.
light_mark:
    add     edi, [world_origin_x]
    sar     edi, 4                      ; the cell's column
    add     edx, [world_origin_z]
    sar     edx, 4
    lea     r8d, [rdi - 1]              ; cx0
    lea     r9d, [rdi + 1]              ; cx1
    lea     r10d, [rdx - 1]             ; cz0
    lea     r11d, [rdx + 1]             ; cz1
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
    jg      .grow
    mov     edx, [rsi + rax + 4]
    cmp     edx, r9d
    jl      .grow
    mov     edx, [rsi + rax + 8]
    cmp     edx, r10d
    jg      .grow
    mov     edx, [rsi + rax + 12]
    cmp     edx, r11d
    jl      .grow
    ret
.grow:                                  ; merge only while the union stays within 4 x 4 columns
    mov     edx, [rsi + rax + 4]
    cmp     edx, r9d
    cmovl   edx, r9d                    ; the union's last column x
    mov     edi, [rsi + rax]
    cmp     edi, r8d
    cmovg   edi, r8d                    ; and its first
    sub     edx, edi
    cmp     edx, 3
    jg      .scan
    mov     edx, [rsi + rax + 12]
    cmp     edx, r11d
    cmovl   edx, r11d
    mov     edi, [rsi + rax + 8]
    cmp     edi, r10d
    cmovg   edi, r10d
    sub     edx, edi
    cmp     edx, 3
    jg      .scan
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
    push    r8                          ; full: recompute region 0 now, then reuse the slot
    push    r9
    push    r10
    push    r11
    call    flush_region0
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    lea     rsi, [dirty_list]
    mov     edx, [dirty_n]
.append:
    shl     edx, 4
    mov     [rsi + rdx], r8d
    mov     [rsi + rdx + 4], r9d
    mov     [rsi + rdx + 8], r10d
    mov     [rsi + rdx + 12], r11d
    inc     dword [dirty_n]
    ret

; flush_region0: recompute the queued region 0 now and drop it (the last region takes its slot).
; Preserves xmm0-xmm3 (light_region's only vector registers); clobbers the caller-saved integer ones.
flush_region0:
    sub     rsp, 72
    movdqu  [rsp], xmm0
    movdqu  [rsp + 16], xmm1
    movdqu  [rsp + 32], xmm2
    movdqu  [rsp + 48], xmm3
    lea     rax, [dirty_list]
    mov     edi, [rax]
    mov     esi, [rax + 4]
    mov     edx, [rax + 8]
    mov     ecx, [rax + 12]
    xor     r8d, r8d
    xor     r9d, r9d
    call    light_region
    lea     rsi, [dirty_list]
    mov     edx, [dirty_n]
    dec     edx
    mov     [dirty_n], edx
    shl     edx, 4
    mov     rdi, [rsi + rdx]
    mov     [rsi], rdi
    mov     rdi, [rsi + rdx + 8]
    mov     [rsi + 8], rdi
    movdqu  xmm0, [rsp]
    movdqu  xmm1, [rsp + 16]
    movdqu  xmm2, [rsp + 32]
    movdqu  xmm3, [rsp + 48]
    add     rsp, 72
    ret

; light_update(): recompute every queued region in place; chunks whose light changed are marked
; dirty. Cheap when nothing is queued (called every frame).
light_update:
    push    rbx
    xor     ebx, ebx
.next:
    cmp     ebx, [dirty_n]
    jae     .done
    mov     eax, ebx
    shl     eax, 4
    lea     rcx, [dirty_list]
    mov     edi, [rcx + rax]
    mov     esi, [rcx + rax + 4]
    mov     edx, [rcx + rax + 8]
    mov     ecx, [rcx + rax + 12]
    xor     r8d, r8d
    xor     r9d, r9d
    call    light_region
    inc     ebx
    jmp     .next
.done:
    mov     dword [dirty_n], 0
    pop     rbx
    ret

; ---- the window recompute --------------------------------------------------------------------------------------

; light_region(edi cx0, esi cx1, edx cz0, ecx cz1, r8d mode, r9 center): recompute the light of the
; columns cx0..cx1 x cz0..cz1 (absolute chunk coordinates, at most 4 per axis). Mode 0: an edit
; region - the lit columns around it are only read. Mode 1: center is the column being lit.
light_region:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     [lr_cx0], edi
    mov     [lr_cx1], esi
    mov     [lr_cz0], edx
    mov     [lr_cz1], ecx
    mov     [lr_mode], r8d
    mov     [lr_center], r9
    call    light_tables
    call    lr_setup
    call    lr_gather
    call    lr_pass
    mov     dword [q_tail], 0
    call    lr_seeds
    call    lr_sources
    call    lr_flood
    call    lr_scatter
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; light_tables(): the per-id lookup tables of the passes below, built once - l_opq (0 opaque, 0xFF
; else), l_emit, l_att (0x10 for translucent ids) and the packed decrement
; l_dec[v] = (max(sky - 1, 0) << 4) | max(block - 1, 0). Ids >= NUM_BLOCKS are transparent and dark.
light_tables:
    cmp     dword [tables_built], 0
    jne     .ret
    mov     dword [tables_built], 1
    xor     ecx, ecx
.id:
    mov     eax, 0xFF
    xor     r8d, r8d
    xor     r9d, r9d
    cmp     ecx, NUM_BLOCKS
    jae     .store
    test    byte [block_flags + rcx], FLAG_OPAQUE
    jz      .emit
    xor     eax, eax
.emit:
    movzx   r8d, byte [block_light + rcx]
    test    byte [block_flags + rcx], FLAG_TRANSLUCENT
    jz      .store
    mov     r9d, 0x10
.store:
    mov     [l_opq + rcx], al
    mov     [l_emit + rcx], r8b
    mov     [l_att + rcx], r9b
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
.ret:
    ret

; lr_setup(): find the window's columns (wcol; a column that is not lit is a wall, the centre column
; of mode 1 is kept), the layers to compute and the window rectangles (region, flood bounds).
lr_setup:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     eax, [lr_cx1]
    sub     eax, [lr_cx0]
    inc     eax
    mov     [lr_nx], eax
    add     eax, 2
    mov     [wn_x], eax
    mov     eax, [lr_cz1]
    sub     eax, [lr_cz0]
    inc     eax
    mov     [lr_nz], eax
    add     eax, 2
    mov     [wn_z], eax
    mov     eax, [lr_cx0]
    dec     eax
    mov     [wcx0], eax
    mov     eax, [lr_cz0]
    dec     eax
    mov     [wcz0], eax
    mov     r15d, -1                    ; the highest top of the window
    xor     r12d, r12d                  ; j
.j:
    xor     r13d, r13d                  ; i
.i:
    mov     edi, [wcx0]
    add     edi, r13d
    mov     esi, [wcz0]
    add     esi, r12d
    call    world_column
    test    rax, rax
    jz      .store
    cmp     rax, [lr_center]
    je      .keep
    cmp     dword [rax + COLUMN.state], COL_LIT
    jne     .wall
.keep:
    mov     ecx, [rax + COLUMN.top]
    cmp     ecx, r15d
    cmovg   r15d, ecx
    jmp     .store
.wall:
    xor     eax, eax
.store:
    mov     ecx, r12d
    shl     ecx, 3
    add     ecx, r13d
    mov     [wcol + rcx*8], rax
    inc     r13d
    cmp     r13d, [wn_x]
    jb      .i
    inc     r12d
    cmp     r12d, [wn_z]
    jb      .j
    lea     eax, [r15 + 16]             ; ycap = min(255, highest top + 16)
    cmp     eax, 255
    jle     .capped
    mov     eax, 255
.capped:
    mov     [wycap], eax
    lea     ecx, [rax + 2]              ; the layers gathered: ycap + 1 is the source layer
    cmp     eax, 255
    jb      .layers
    mov     ecx, 256
.layers:
    mov     [wlayers], ecx
    mov     ecx, eax
    shl     ecx, 14
    mov     [fl_ycap14], ecx
    add     ecx, 1 << 14
    mov     [fl_beyond14], ecx
    mov     eax, [lr_nx]                ; the region in window cells: x from 16 to 16 * (nx + 1) - 1
    inc     eax
    shl     eax, 4
    dec     eax
    mov     dword [rg_x0], 16
    mov     [rg_x1], eax
    mov     eax, [lr_nz]
    inc     eax
    shl     eax, 4
    dec     eax
    mov     dword [rg_z0], 16
    mov     [rg_z1], eax
    cmp     dword [lr_mode], 0
    jne     .wide
    mov     eax, [rg_x0]                ; edit region: the flood stays inside it
    mov     [fb_x0], eax
    mov     eax, [rg_x1]
    mov     [fb_x1], eax
    mov     eax, [rg_z0]
    mov     [fb_z0], eax
    mov     eax, [rg_z1]
    mov     [fb_z1], eax
    jmp     .ret
.wide:                                  ; lighting a column: the flood fills the whole window
    mov     dword [fb_x0], 0
    mov     dword [fb_z0], 0
    mov     eax, [wn_x]
    shl     eax, 4
    dec     eax
    mov     [fb_x1], eax
    mov     eax, [wn_z]
    shl     eax, 4
    dec     eax
    mov     [fb_z1], eax
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; lr_gather(): copy blocks and light of every window column into w_blk / w_lit (layers 0 ..
; wlayers - 1). A null chunk reads as AIR with light 0xF0; a wall column as STONE with light 0.
lr_gather:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    movdqa  xmm1, [k_f0]
    pxor    xmm2, xmm2
    movdqa  xmm3, [k_stone]
    xor     r12d, r12d                  ; j
.j:
    xor     r13d, r13d                  ; i
.i:
    mov     eax, r12d
    shl     eax, 3
    add     eax, r13d
    mov     r14, [wcol + rax*8]         ; the column, or 0 for a wall
    xor     r15d, r15d                  ; cy
.cy:
    mov     r10d, r15d
    shl     r10d, 4                     ; the chunk's first layer
    cmp     r10d, [wlayers]
    jae     .col_end
    xor     ebx, ebx                    ; the chunk, 0 when null or for a wall
    test    r14, r14
    jz      .rows
    mov     rbx, [r14 + COLUMN.chunks + r15*8]
.rows:
    xor     r8d, r8d                    ; ly
.ly:
    lea     r9d, [r10 + r8]             ; y
    cmp     r9d, [wlayers]
    jae     .col_end
    mov     edi, r9d
    shl     edi, 14
    mov     eax, r12d
    shl     eax, 11                     ; (j * 16) << 7
    or      edi, eax
    mov     eax, r13d
    shl     eax, 4
    or      edi, eax                    ; window index of the row lz = 0
    mov     rsi, r8
    shl     rsi, 8
    add     rsi, rbx                    ; the chunk's row ly (lz = 0)
    mov     ecx, 16
    test    r14, r14
    jz      .wall
    test    rbx, rbx
    jz      .null
.copy:
    movups  xmm0, [rsi]
    movups  [w_blk + rdi], xmm0
    movups  xmm0, [rsi + CHUNK_LIGHT]
    movups  [w_lit + rdi], xmm0
    add     rsi, 16
    add     edi, 128
    dec     ecx
    jnz     .copy
    jmp     .next_ly
.null:
    movups  [w_blk + rdi], xmm2
    movups  [w_lit + rdi], xmm1
    add     edi, 128
    dec     ecx
    jnz     .null
    jmp     .next_ly
.wall:
    movups  [w_blk + rdi], xmm3
    movups  [w_lit + rdi], xmm2
    add     edi, 128
    dec     ecx
    jnz     .wall
.next_ly:
    inc     r8d
    cmp     r8d, 16
    jb      .ly
    inc     r15d
    cmp     r15d, COL_CHUNKS
    jb      .cy
.col_end:
    inc     r13d
    cmp     r13d, [wn_x]
    jb      .i
    inc     r12d
    cmp     r12d, [wn_z]
    jb      .j
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; lr_pass(): pass 1 - walk every layer of the region from ycap down: a column stays open (sky 15)
; down to its first opaque cell and loses one step per translucent cell; each cell becomes
; sky | emission.
lr_pass:
    mov     r11d, [rg_z0]
.init:
    mov     edi, r11d
    shl     edi, 7
    add     edi, [rg_x0]
    lea     rdi, [col_sky + rdi]
    mov     ecx, [rg_x1]
    sub     ecx, [rg_x0]
    inc     ecx
    mov     al, 0xF0
    rep     stosb
    inc     r11d
    cmp     r11d, [rg_z1]
    jbe     .init
    mov     r9d, [rg_x1]
    sub     r9d, [rg_x0]
    inc     r9d                         ; row width
    mov     r10d, [wycap]               ; y
.layer:
    mov     r11d, [rg_z0]
.row:
    mov     eax, r10d
    shl     eax, 14
    mov     edx, r11d
    shl     edx, 7
    add     eax, edx
    add     edx, [rg_x0]                ; the row's column-state index
    add     eax, [rg_x0]                ; the row's first cell
    lea     rsi, [w_blk + rax]
    lea     rdi, [w_lit + rax]
    lea     rdx, [col_sky + rdx]
    mov     ecx, r9d
.cell:
    movzx   eax, byte [rsi]
    mov     r8b, [rdx]
    and     r8b, [l_opq + rax]
    sub     r8b, [l_att + rax]
    jnb     .ok
    xor     r8d, r8d
.ok:
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

; SEEDN off: the horizontal neighbour at rcx + off (inside the flood bounds) is not opaque and would
; be raised by the sky-level-esi cell rcx (it receives esi - 1, one less through water or ice):
; rcx is a seed.
%macro SEEDN 1
    movzx   edi, byte [w_lit + rcx + %1]
    shr     edi, 4                      ; the neighbour's sky
    mov     r8d, esi                    ; what it would receive
    movzx   r9d, byte [w_blk + rcx + %1]
    cmp     byte [l_opq + r9], 0
    je      %%ok                        ; opaque
    cmp     byte [l_att + r9], 0
    je      %%plain
    dec     r8d
%%plain:
    cmp     edi, r8d
    jb      .push
%%ok:
%endmacro

; lr_seeds(): pass 2 - enqueue every region cell that can raise a neighbour: block light >= 2, or a
; sky level >= 2 beside a horizontal neighbour (inside the flood bounds) that it would raise. After
; the column pass vertical neighbours never need it: the column state already carries the sky down.
lr_seeds:
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
    shl     r15d, 14
    mov     eax, r14d
    shl     eax, 7
    or      r15d, eax                   ; (y << 14) | (z << 7)
    mov     ebx, [rg_x0]                ; x
.x:
    lea     ecx, [r15 + rbx]            ; cell index
    movzx   edx, byte [w_lit + rcx]
    mov     esi, edx
    and     esi, 15
    cmp     esi, 2
    jae     .push
    mov     esi, edx
    shr     esi, 4
    cmp     esi, 2
    jb      .next
    dec     esi                         ; the sky level a neighbour would receive
    cmp     ebx, [fb_x0]
    jbe     .no_w
    SEEDN   -1
.no_w:
    cmp     ebx, [fb_x1]
    jae     .no_e
    SEEDN   1
.no_e:
    cmp     r14d, [fb_z0]
    jbe     .no_n
    SEEDN   -128
.no_n:
    cmp     r14d, [fb_z1]
    jae     .next
    SEEDN   128
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
    cmp     r13d, [wycap]
    jbe     .y
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; src_face(edi first cell, esi step, edx count, ecx delta): on each layer up to sf_end14 (layer << 14),
; the run of `count` source cells starting at the window cell `first` (step apart) is checked
; against the region cell `delta` away: a lit source that would raise it joins the queue (read-only:
; only the cell across the face ever receives from it).
; Clobbers rax, r8-r11; preserves rdi, rsi, rdx, rcx.
src_face:
    push    rbx
    push    r12
    xor     r8d, r8d                    ; layer offset << 14
.layer:
    lea     r9d, [rdi + r8]             ; the first source cell of this layer
    mov     r10d, edx
.cell:
    movzx   eax, byte [w_lit + r9]
    cmp     eax, 0x20
    jae     .check
    mov     r11d, eax
    and     r11d, 15
    cmp     r11d, 2
    jb      .next                       ; sky < 2 and block < 2: it gives nothing
.check:
    lea     r11d, [r9 + rcx]            ; the region cell across the face
    movzx   ebx, byte [w_blk + r11]
    cmp     byte [l_opq + rbx], 0
    je      .next                       ; opaque
    movzx   eax, byte [l_dec + rax]     ; what the source gives: one step dimmer
    cmp     byte [l_att + rbx], 0
    je      .rel
    movzx   eax, byte [l_dec + rax]     ; water and ice: one more
.rel:
    movzx   ebx, byte [w_lit + r11]     ; what the cell has
    mov     r11d, eax
    and     r11d, 0xF0
    mov     r12d, ebx
    and     r12d, 0xF0
    cmp     r11d, r12d
    ja      .push                       ; brighter sky
    and     eax, 15
    and     ebx, 15
    cmp     eax, ebx
    jbe     .next                       ; nothing to raise
.push:
    mov     eax, [q_tail]
    lea     ebx, [rax + 1]
    and     ebx, LQ_MASK
    jz      .next                       ; full (the head is 0)
    mov     [light_queue + rax*4], r9d
    mov     [q_tail], ebx
.next:
    add     r9d, esi
    dec     r10d
    jnz     .cell
    add     r8d, 1 << 14
    cmp     r8d, [sf_end14]
    jb      .layer
    pop     r12
    pop     rbx
    ret

; lr_sources(): pass 3 - the lit cells just outside the region's four faces and above it (the layer
; ycap + 1) are read-only sources: enqueue the ones that raise the region cell next to them.
lr_sources:
    push    rbx
    push    r12
    sub     rsp, 8
    mov     eax, [fl_beyond14]
    mov     [sf_end14], eax             ; layers 0 .. ycap
    mov     edx, [rg_z1]
    sub     edx, [rg_z0]
    inc     edx                         ; cells along a west / east face
    mov     edi, [rg_z0]                ; west: x = x0 - 1
    shl     edi, 7
    add     edi, [rg_x0]
    dec     edi
    mov     esi, 128
    mov     ecx, 1
    call    src_face
    mov     edi, [rg_z0]                ; east: x = x1 + 1
    shl     edi, 7
    add     edi, [rg_x1]
    inc     edi
    mov     esi, 128
    mov     ecx, -1
    call    src_face
    mov     edx, [rg_x1]
    sub     edx, [rg_x0]
    inc     edx                         ; cells along a north / south face
    mov     edi, [rg_z0]                ; north: z = z0 - 1
    dec     edi
    shl     edi, 7
    add     edi, [rg_x0]
    mov     esi, 1
    mov     ecx, 128
    call    src_face
    mov     edi, [rg_z1]                ; south: z = z1 + 1
    inc     edi
    shl     edi, 7
    add     edi, [rg_x0]
    mov     esi, 1
    mov     ecx, -128
    call    src_face
    cmp     dword [wlayers], 256
    jae     .done                       ; the region reaches the top of the world
    mov     dword [sf_end14], 1 << 14   ; the layer above: one layer per row of the region
    mov     ebx, [rg_x1]
    sub     ebx, [rg_x0]
    inc     ebx
    mov     r12d, [rg_z0]
.top:
    mov     edi, r12d
    shl     edi, 7
    add     edi, [rg_x0]
    add     edi, [fl_beyond14]
    mov     esi, 1
    mov     edx, ebx
    mov     ecx, -16384
    call    src_face
    inc     r12d
    cmp     r12d, [rg_z1]
    jbe     .top
.done:
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; RELAX off: the neighbour at rax + off (inside the bounds) takes the popped cell's light minus one
; per channel (r8d = sky << 4, r9d = block of the single decrement; r14d / r15d the double one for
; water and ice) unless it is opaque or already as bright; a raised neighbour joins the queue
; (r12d head, r13d tail).
%macro RELAX 1
    lea     edi, [rax + %1]
    movzx   esi, byte [w_blk + rdi]
    cmp     byte [l_opq + rsi], 0
    je      %%skip                      ; opaque cells stay dark
    movzx   edx, byte [w_lit + rdi]     ; the cell's current light
    mov     ebx, r8d
    mov     ecx, r9d
    cmp     byte [l_att + rsi], 0
    je      %%plain
    mov     ebx, r14d                   ; water and ice cost one more step
    mov     ecx, r15d
%%plain:
    mov     esi, edx
    and     esi, 0xF0
    cmp     esi, ebx
    cmovb   esi, ebx                    ; brighter sky
    mov     ebx, edx
    and     ebx, 15
    cmp     ebx, ecx
    cmovb   ebx, ecx                    ; brighter block light
    or      ebx, esi
    cmp     ebx, edx
    je      %%skip                      ; nothing to raise
    mov     [w_lit + rdi], bl
    lea     esi, [r13 + 1]
    and     esi, LQ_MASK
    cmp     esi, r12d
    je      %%skip                      ; queue full: drop the push
    mov     [light_queue + r13*4], edi
    mov     r13d, esi
%%skip:
%endmacro

; lr_flood(): pass 4 - flood fill from the queued seeds and sources. A popped cell outside the flood
; bounds (a read-only source) feeds only its one neighbour across the face; inside, it feeds its six
; neighbours except those past the bounds.
lr_flood:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    xor     r12d, r12d                  ; head
    mov     r13d, [q_tail]
.pop:
    cmp     r12d, r13d
    je      .done
    mov     eax, [light_queue + r12*4]
    inc     r12d
    and     r12d, LQ_MASK
    movzx   ecx, byte [w_lit + rax]
    movzx   ecx, byte [l_dec + rcx]     ; one step dimmer
    test    ecx, ecx
    jz      .pop                        ; nothing left to give
    movzx   edx, byte [l_dec + rcx]     ; two steps dimmer
    mov     r8d, ecx
    and     r8d, 0xF0
    mov     r9d, ecx
    and     r9d, 15
    mov     r14d, edx
    and     r14d, 0xF0
    mov     r15d, edx
    and     r15d, 15
    mov     r10d, eax
    and     r10d, 127                   ; x
    mov     r11d, eax
    shr     r11d, 7
    and     r11d, 127                   ; z
    cmp     r10d, [fb_x0]
    jb      .out_w
    cmp     r10d, [fb_x1]
    ja      .out_e
    cmp     r11d, [fb_z0]
    jb      .out_n
    cmp     r11d, [fb_z1]
    ja      .out_s
    cmp     eax, [fl_beyond14]
    jae     .out_t
    cmp     r10d, [fb_x0]
    jbe     .in_w
    RELAX   -1
.in_w:
    cmp     r10d, [fb_x1]
    jae     .in_e
    RELAX   1
.in_e:
    cmp     r11d, [fb_z0]
    jbe     .in_n
    RELAX   -128
.in_n:
    cmp     r11d, [fb_z1]
    jae     .in_s
    RELAX   128
.in_s:
    cmp     eax, 1 << 14
    jb      .in_d
    RELAX   -16384
.in_d:
    cmp     eax, [fl_ycap14]
    jae     .pop
    RELAX   16384
    jmp     .pop
.out_w:
    RELAX   1
    jmp     .pop
.out_e:
    RELAX   -1
    jmp     .pop
.out_n:
    RELAX   128
    jmp     .pop
.out_s:
    RELAX   -128
    jmp     .pop
.out_t:
    RELAX   -16384
    jmp     .pop
.done:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; mark_row_dirty(edi acx, esi acz, edx cy, ecx ly, r8d lz, r9d mask): a row of 16 light bytes (chunk
; cy of column (acx, acz), layer ly, row lz) changed at the bytes of `mask`. Marks every chunk that
; reads one of those cells: the chunk itself and the neighbours across the faces it touches (the
; mesher reads a one-cell border), as world_mark_cell_dirty does per cell.
mark_row_dirty:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12d, edi                   ; acx
    mov     r13d, esi                   ; acz
    mov     ebx, ecx                    ; ly
    mov     r10d, r8d                   ; lz
    mov     r11d, r9d                   ; mask
    mov     r14d, edx                   ; cy
    mov     ecx, r14d
    mov     r15d, 1
    shl     r15d, cl                    ; the chunk's own bit
    test    ebx, ebx
    jnz     .ytop
    test    r14d, r14d
    jz      .ytop
    mov     eax, r15d
    shr     eax, 1
    or      r15d, eax                   ; the chunk below
.ytop:
    cmp     ebx, 15
    jne     .ydone
    cmp     r14d, 15
    jae     .ydone
    mov     eax, 2
    mov     ecx, r14d
    shl     eax, cl
    or      r15d, eax                   ; the chunk above
.ydone:
    xor     r8d, r8d                    ; dz from
    test    r10d, r10d
    jnz     .zlo
    mov     r8d, -1
.zlo:
    xor     r9d, r9d                    ; dz to
    cmp     r10d, 15
    jne     .zhi
    mov     r9d, 1
.zhi:
    xor     ebx, ebx                    ; dx from
    test    r11d, 1
    jz      .xlo
    mov     ebx, -1
.xlo:
    xor     r14d, r14d                  ; dx to
    test    r11d, 0x8000
    jz      .dz
    mov     r14d, 1
.dz:
    mov     r10d, ebx                   ; dx
.dx:
    lea     edi, [r12 + r10]
    lea     esi, [r13 + r8]
    call    world_column
    test    rax, rax
    jz      .skip
    or      [rax + COLUMN.dirty], r15d
.skip:
    inc     r10d
    cmp     r10d, r14d
    jle     .dx
    inc     r8d
    cmp     r8d, r9d
    jle     .dz
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; lr_scatter(): pass 5 - give the recomputed light back to the chunks. Per 16-byte row of every
; writable window column (mode 0: the region's own; mode 1: all of them) the row is compared with
; the chunk's light (a null chunk holds 0xF0) and written when it differs, allocating the chunk on
; the first such write. Mode 0 marks the chunks that read a changed cell dirty; mode 1 marks every
; column whose light changed fully dirty (the lit column itself always is).
lr_scatter:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8                      ; [rsp] = this column changed
    movdqa  xmm2, [k_f0]
    xor     r12d, r12d                  ; j
.j:
    xor     r13d, r13d                  ; i
.i:
    mov     eax, r12d
    shl     eax, 3
    add     eax, r13d
    mov     r14, [wcol + rax*8]
    test    r14, r14
    jz      .next_i
    cmp     dword [lr_mode], 0
    jne     .go
    test    r13d, r13d                  ; mode 0: only the region's own columns
    jz      .next_i
    cmp     r13d, [lr_nx]
    ja      .next_i
    test    r12d, r12d
    jz      .next_i
    cmp     r12d, [lr_nz]
    ja      .next_i
.go:
    mov     dword [rsp], 0
    xor     r15d, r15d                  ; cy
.cy:
    mov     r10d, r15d
    shl     r10d, 4
    cmp     r10d, [wycap]
    ja      .col_end
    mov     rbx, [r14 + COLUMN.chunks + r15*8]
    xor     r8d, r8d                    ; ly
.ly:
    lea     r9d, [r10 + r8]
    cmp     r9d, [wycap]
    ja      .col_end
    mov     edi, r9d
    shl     edi, 14
    mov     eax, r12d
    shl     eax, 11
    or      edi, eax
    mov     eax, r13d
    shl     eax, 4
    or      edi, eax                    ; window index of the row lz = 0
    xor     r11d, r11d                  ; lz
.lz:
    movups  xmm0, [w_lit + rdi]
    test    rbx, rbx
    jz      .null
    mov     eax, r8d
    shl     eax, 8
    mov     ecx, r11d
    shl     ecx, 4
    add     eax, ecx
    movups  xmm1, [rbx + rax + CHUNK_LIGHT]
    jmp     .cmp
.null:
    movaps  xmm1, xmm2
.cmp:
    pcmpeqb xmm1, xmm0
    pmovmskb eax, xmm1
    xor     eax, 0xFFFF                 ; the bytes that differ
    jnz     .changed
.next_lz:
    add     edi, 128
    inc     r11d
    cmp     r11d, 16
    jb      .lz
    inc     r8d
    cmp     r8d, 16
    jb      .ly
    inc     r15d
    cmp     r15d, COL_CHUNKS
    jb      .cy
.col_end:
    cmp     dword [rsp], 0
    je      .next_i
    cmp     dword [lr_mode], 0
    je      .next_i
    mov     dword [r14 + COLUMN.dirty], 0xFFFF
.next_i:
    inc     r13d
    cmp     r13d, [wn_x]
    jb      .i
    inc     r12d
    cmp     r12d, [wn_z]
    jb      .j
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
.changed:
    test    rbx, rbx
    jnz     .write
    push    rdi                         ; a null chunk gets its first non-sky light: allocate it
    push    r8
    push    r9
    push    r10
    push    r11
    push    rax
    mov     rdi, r14
    mov     esi, r15d
    call    world_chunk_alloc
    mov     rbx, rax
    pop     rax
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    test    rbx, rbx
    jz      .next_lz                    ; the pool is empty: the light stays as it was
.write:
    mov     ecx, r8d
    shl     ecx, 8
    mov     edx, r11d
    shl     edx, 4
    add     ecx, edx
    movups  [rbx + rcx + CHUNK_LIGHT], xmm0
    mov     dword [rsp], 1
    cmp     dword [lr_mode], 0
    jne     .next_lz
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    mov     edi, [wcx0]
    add     edi, r13d
    mov     esi, [wcz0]
    add     esi, r12d
    mov     edx, r15d
    mov     ecx, r8d
    mov     r8d, r11d
    mov     r9d, eax
    call    mark_row_dirty
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    jmp     .next_lz
