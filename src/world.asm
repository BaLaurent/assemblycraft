; world.asm - block storage, chunk dirty flags, the light hooks (world_set queues light changes,
; world_clear / world_load reset or compute the light), save/load of the world file image.
%include "common.inc"
default rel

global world_header, blocks, chunk_dirty
global world_get, world_set, world_is_solid, world_is_opaque, world_top_y
global world_clear, world_mark_all_dirty, world_mark_cell_dirty, world_save, world_load

extern block_flags, block_light, file_read, file_write_atomic, item_gear
extern light_mark, light_fill_sky, light_compute_all

section .rodata
world_magic:    db "ACRAFT05"
world_magic_v4: db "ACRAFT04"
world_magic_v3: db "ACRAFT03"
world_magic_v2: db "ACRAFT02"
world_magic_v1: db "ACRAFT01"
default_hotbar: db STONE, DIRT, GRASS, COBBLE, PLANKS, LOG, LEAVES, GLASS, BRICK

section .bss
; world_header and blocks are one contiguous file image (header immediately followed by
; blocks: the v1 conversion and single-buffer I/O depend on it).
alignb 64
world_header: resb WORLD_HDR_SIZE
blocks:       resb WORLD_VOLUME
world_slack:  resb 16                   ; absorbs the +1 probe byte of world_load
chunk_dirty:  resb NUM_CHUNKS
v1_scratch:   resb WORLD_V1_HDR

section .text

; world_get(edi x, esi y, edx z) -> eax id; out of bounds -> AIR
world_get:
    cmp     edi, WORLD_X - 1
    ja      .oob
    cmp     esi, WORLD_Y - 1
    ja      .oob
    cmp     edx, WORLD_Z - 1
    ja      .oob
    mov     eax, esi
    shl     eax, 16
    shl     edx, 8
    or      eax, edx
    or      eax, edi
    movzx   eax, byte [blocks + rax]
    ret
.oob:
    xor     eax, eax
    ret

; world_set(edi x, esi y, edx z, ecx id): store the block. When the cell's opacity or light
; emission changes, queue its light recompute (light_mark); then mark its chunks dirty.
; Preserves rdi and rbx; out-of-bounds cells are ignored.
world_set:
    cmp     edi, WORLD_X - 1
    ja      .ret
    cmp     esi, WORLD_Y - 1
    ja      .ret
    cmp     edx, WORLD_Z - 1
    ja      .ret
    mov     eax, esi
    shl     eax, 16
    mov     r8d, edx
    shl     r8d, 8
    or      eax, r8d
    or      eax, edi
    movzx   r8d, byte [blocks + rax]    ; the old id
    mov     [blocks + rax], cl
    movzx   r9d, cl                     ; the new id
    movzx   eax, byte [block_flags + r8]
    xor     al, [block_flags + r9]
    test    al, FLAG_OPAQUE
    jnz     .light
    mov     al, [block_light + r8]
    cmp     al, [block_light + r9]
    je      world_mark_cell_dirty       ; tail jump: marks the neighbourhood, returns to the caller
.light:
    push    rdi
    push    rsi
    push    rdx
    call    light_mark
    pop     rdx
    pop     rsi
    pop     rdi
    jmp     world_mark_cell_dirty
.ret:
    ret

; world_mark_cell_dirty(edi x, esi y, edx z): flag every chunk that contains an in-bounds cell of
; the 3x3x3 neighbourhood of an in-bounds cell (a box, so mark the clamped box). Also the mesher's
; hook for light changes. Preserves rdi and rbx; clobbers eax, ecx, edx, esi, r8-r11.
world_mark_cell_dirty:
    push    rbx
    ; chunk ranges: lo = max(c-1,0)>>4, hi = min(c+1,max)>>4
%macro CRANGE 4                         ; coord, max, lo, hi
    lea     %3, [%1 - 1]
    xor     eax, eax
    test    %3, %3
    cmovs   %3, eax
    shr     %3, 4
    lea     %4, [%1 + 1]
    mov     eax, %2
    cmp     %4, eax
    cmova   %4, eax
    shr     %4, 4
%endmacro
    CRANGE  edi, WORLD_X - 1, r8d, r9d  ; x: r8..r9
    CRANGE  esi, WORLD_Y - 1, r10d, r11d ; y: r10..r11
    CRANGE  edx, WORLD_Z - 1, ecx, ebx  ; z: ecx..ebx
    mov     edx, ecx                    ; z lo kept in edx
.ly:
    mov     ecx, edx
.lz:
    mov     esi, r8d
.lx:
    mov     eax, r10d
    shl     eax, 4
    add     eax, ecx
    shl     eax, 4
    add     eax, esi
    mov     byte [chunk_dirty + rax], 1
    inc     esi
    cmp     esi, r9d
    jbe     .lx
    inc     ecx
    cmp     ecx, ebx
    jbe     .lz
    inc     r10d
    cmp     r10d, r11d
    jbe     .ly
    pop     rbx
    ret

; world_is_solid(edi x, esi y, edx z) -> eax 0/1
world_is_solid:
    test    esi, esi
    js      .solid
    cmp     esi, WORLD_Y - 1
    jg      .air
    cmp     edi, WORLD_X - 1
    ja      .solid
    cmp     edx, WORLD_Z - 1
    ja      .solid
    mov     eax, esi
    shl     eax, 16
    shl     edx, 8
    or      eax, edx
    or      eax, edi
    movzx   eax, byte [blocks + rax]
    movzx   eax, byte [block_flags + rax]
    and     eax, FLAG_SOLID
    ret
.solid:
    mov     eax, 1
    ret
.air:
    xor     eax, eax
    ret

; world_is_opaque(edi x, esi y, edx z) -> eax 0/1; out of bounds -> 0
world_is_opaque:
    cmp     edi, WORLD_X - 1
    ja      .no
    cmp     esi, WORLD_Y - 1
    ja      .no
    cmp     edx, WORLD_Z - 1
    ja      .no
    mov     eax, esi
    shl     eax, 16
    shl     edx, 8
    or      eax, edx
    or      eax, edi
    movzx   eax, byte [blocks + rax]
    movzx   eax, byte [block_flags + rax]
    shr     eax, 1
    and     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; world_top_y(edi x, esi z) -> eax highest non-air y, or -1
world_top_y:
    mov     eax, -1
    cmp     edi, WORLD_X - 1
    ja      .ret
    cmp     esi, WORLD_Z - 1
    ja      .ret
    shl     esi, 8
    or      esi, edi
    mov     eax, WORLD_Y - 1
.loop:
    mov     ecx, eax
    shl     ecx, 16
    or      ecx, esi
    cmp     byte [blocks + rcx], AIR
    jne     .ret
    dec     eax
    jns     .loop
.ret:
    ret

; world_clear(): zero every block (an empty world is all sky: light_fill_sky). Returns eax = 0.
world_clear:
    sub     rsp, 8
    lea     rdi, [blocks]
    mov     ecx, WORLD_VOLUME / 8
    xor     eax, eax
    rep     stosq
    call    light_fill_sky
    xor     eax, eax
    add     rsp, 8
    ret

; world_mark_all_dirty(): flag all chunks for remeshing
world_mark_all_dirty:
    lea     rdi, [chunk_dirty]
    mov     ecx, NUM_CHUNKS
    mov     al, 1
    rep     stosb
    ret

; world_save(rdi path) -> eax 0 or -errno
world_save:
    mov     rax, [world_magic]
    mov     [world_header + WORLDHDR.magic], rax
    lea     rsi, [world_header]
    mov     edx, WORLD_FILE_SIZE
    jmp     file_write_atomic

; world_load(rdi path) -> eax 0 ok / 1 missing / 2 invalid / 3 I/O error.
; Accepts v5, converts v4 (16384-byte header, gear wear), v3 (also item ids), v2 and 0.1
; files in memory; a converted image is stamped v5.
world_load:
    push    rbp
    mov     rbp, rsp
    lea     rsi, [world_header]
    mov     edx, WORLD_FILE_SIZE + 1
    call    file_read
    cmp     rax, -ENOENT
    je      .missing
    test    rax, rax
    js      .ioerr
    cmp     rax, WORLD_FILE_SIZE
    je      .v5
    cmp     rax, WORLD_V4_SIZE
    je      .v4
    cmp     rax, WORLD_V2_SIZE
    je      .v2
    cmp     rax, WORLD_V1_SIZE
    jne     .invalid
    mov     rax, [world_magic_v1]
    cmp     [world_header + WORLDHDR.magic], rax
    jne     .invalid
    call    convert_v1
    jmp     .ok
.v2:
    mov     rax, [world_magic_v2]
    cmp     [world_header + WORLDHDR.magic], rax
    jne     .invalid
    call    convert_v2
    call    migrate_items_v3
    jmp     .gear
.v4:
    mov     rax, [world_header + WORLDHDR.magic]
    cmp     rax, [world_magic_v4]
    je      .conv4
    cmp     rax, [world_magic_v3]
    jne     .invalid
    call    convert_v4
    call    migrate_items_v3
    jmp     .gear
.conv4:
    call    convert_v4
.gear:
    call    migrate_gear_v4
    mov     rax, [world_magic]
    mov     [world_header + WORLDHDR.magic], rax
    jmp     .ok
.v5:
    mov     rax, [world_header + WORLDHDR.magic]
    cmp     rax, [world_magic]
    jne     .invalid
.ok:
    call    light_compute_all
    call    world_mark_all_dirty
    xor     eax, eax
    pop     rbp
    ret
.missing:
    mov     eax, 1
    pop     rbp
    ret
.invalid:
    mov     eax, 2
    pop     rbp
    ret
.ioerr:
    mov     eax, 3
    pop     rbp
    ret

; convert_v2(): a v2 image (1024-byte header + blocks) sits at world_header. Move the
; blocks up to `blocks`, zero the v3+ header fields, stamp the v5 magic (the item ids
; are still v3 ones: the caller runs migrate_items_v3).
convert_v2:
    ; overlapping, dest > src, so copy backwards
    lea     rsi, [world_header + WORLD_BASE_HDR + WORLD_VOLUME - 1]
    lea     rdi, [blocks + WORLD_VOLUME - 1]
    mov     ecx, WORLD_VOLUME
    std
    rep     movsb
    cld
    lea     rdi, [world_header + WORLDHDR.armor]
    mov     ecx, WORLD_HDR_SIZE - WORLDHDR.armor
    xor     eax, eax
    rep     stosb
    mov     rax, [world_magic]
    mov     [world_header + WORLDHDR.magic], rax
    ret

; convert_v4(): a v3/v4 image (16384-byte header + blocks) sits at world_header. Move the
; blocks up to `blocks` and zero the v5-only header bytes 16384..32767 (jewelry, rpgx).
; The magic is left alone: the caller dispatches on it and stamps v5.
convert_v4:
    ; overlapping, dest > src, so copy backwards
    lea     rsi, [world_header + WORLD_V4_HDR + WORLD_VOLUME - 1]
    lea     rdi, [blocks + WORLD_VOLUME - 1]
    mov     ecx, WORLD_VOLUME
    std
    rep     movsb
    cld
    lea     rdi, [world_header + WORLD_V4_HDR]
    mov     ecx, WORLD_HDR_SIZE - WORLD_V4_HDR
    xor     eax, eax
    rep     stosb
    ret

; convert_v1(): the 0.1 image (48-byte header + blocks) sits at world_header; rebuild it
; as a v5 image in place. Old worlds load as Creative with their 0.1 hotbar.
convert_v1:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    lea     rsi, [world_header]
    lea     rdi, [v1_scratch]
    mov     ecx, WORLD_V1_HDR
    rep     movsb
    ; move the blocks up by 1024-48 bytes: overlapping, dest > src, so copy backwards
    lea     rsi, [world_header + WORLD_V1_HDR + WORLD_VOLUME - 1]
    lea     rdi, [blocks + WORLD_VOLUME - 1]
    mov     ecx, WORLD_VOLUME
    std
    rep     movsb
    cld
    lea     rdi, [world_header]
    mov     ecx, WORLD_HDR_SIZE
    xor     eax, eax
    rep     stosb
    lea     rbx, [world_header]
    mov     rax, [world_magic]
    mov     [rbx + WORLDHDR.magic], rax
    mov     eax, [v1_scratch + V1_SEED]
    mov     [rbx + WORLDHDR.seed], eax
    mov     dword [rbx + WORLDHDR.mode], MODE_CREATIVE
    mov     dword [rbx + WORLDHDR.time], NEW_WORLD_TIME
    mov     edi, 128
    mov     esi, 128
    call    world_top_y
    inc     eax
    mov     dword [rbx + WORLDHDR.spawn_x], 128
    mov     [rbx + WORLDHDR.spawn_y], eax
    mov     dword [rbx + WORLDHDR.spawn_z], 128
    mov     eax, [v1_scratch + V1_PX]
    mov     [rbx + WORLDHDR.player + BODY.x], eax
    mov     eax, [v1_scratch + V1_PY]
    mov     [rbx + WORLDHDR.player + BODY.y], eax
    mov     eax, [v1_scratch + V1_PZ]
    mov     [rbx + WORLDHDR.player + BODY.z], eax
    mov     eax, [v1_scratch + V1_YAW]
    mov     [rbx + WORLDHDR.player + BODY.yaw], eax
    mov     eax, [v1_scratch + V1_PITCH]
    mov     [rbx + WORLDHDR.player + BODY.pitch], eax
    movzx   eax, byte [v1_scratch + V1_FLYING]
    and     eax, 1
    mov     [rbx + WORLDHDR.player + BODY.flying], eax
    mov     dword [rbx + WORLDHDR.health], 20
    mov     dword [rbx + WORLDHDR.food], 20
    mov     dword [rbx + WORLDHDR.saturation], __float32__(5.0)
    movzx   eax, byte [v1_scratch + V1_SEL]
    xor     ecx, ecx
    cmp     eax, HOTBAR_SLOTS
    cmovae  eax, ecx
    mov     [rbx + WORLDHDR.sel], eax
    xor     ecx, ecx
.slot:
    movzx   eax, byte [v1_scratch + V1_HOTBAR + rcx]
    test    eax, eax
    jz      .default
    cmp     eax, V3_NUM_BLOCKS
    jb      .have
.default:
    movzx   eax, byte [default_hotbar + rcx]
.have:
    mov     [rbx + WORLDHDR.inventory + rcx*4 + ITEMSTACK.id], al
    mov     byte [rbx + WORLDHDR.inventory + rcx*4 + ITEMSTACK.count], 1
    inc     ecx
    cmp     ecx, HOTBAR_SLOTS
    jb      .slot
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; migrate_items_v3(): renumber every item stack of a v3 header (inventory, armor and the
; cells of every used container) to the v4 id space: blocks keep their id, items move up
; by FIRST_ITEM - V3_FIRST_ITEM, unknown ids are emptied.
migrate_items_v3:
    lea     rdi, [world_header + WORLDHDR.inventory]
    mov     ecx, INV_SLOTS
.inv:
    call    migrate_stack
    add     rdi, 4
    dec     ecx
    jnz     .inv
    lea     rdi, [world_header + WORLDHDR.armor]
    mov     ecx, 4
.armor:
    call    migrate_stack
    add     rdi, 4
    dec     ecx
    jnz     .armor
    lea     rdx, [world_header + WORLDHDR.containers]
    mov     esi, MAX_CONTAINERS
.cont:
    cmp     byte [rdx + CONTAINER.kind], 0
    je      .cnext
    lea     rdi, [rdx + CONTAINER.slots]
    mov     ecx, 27
.cell:
    call    migrate_stack
    add     rdi, 4
    dec     ecx
    jnz     .cell
.cnext:
    add     rdx, CONTAINER_size
    dec     esi
    jnz     .cont
    ret

; migrate_stack(rdi ITEMSTACK*): v3 -> v4 id of one stack. Leaf, clobbers eax only.
migrate_stack:
    cmp     byte [rdi + ITEMSTACK.count], 0
    je      .ret
    movzx   eax, byte [rdi + ITEMSTACK.id]
    cmp     eax, V3_NUM_BLOCKS
    jb      .ret
    cmp     eax, V3_FIRST_ITEM
    jb      .zero
    cmp     eax, V3_NUM_ITEMS
    jae     .zero
    add     eax, FIRST_ITEM - V3_FIRST_ITEM
    mov     [rdi + ITEMSTACK.id], al
    ret
.zero:
    mov     dword [rdi], 0
.ret:
    ret

; migrate_gear_v4(): pre-0.8 gear kept its wear in ITEMSTACK.dmg, which now holds the
; rarity/tier/seed roll. Zero dmg of every gear stack (item_gear != 0) in the inventory,
; armor and every used container, so old weapons and armor load as Common.
migrate_gear_v4:
    lea     rdi, [world_header + WORLDHDR.inventory]
    mov     ecx, INV_SLOTS
.inv:
    call    gear_unroll
    add     rdi, 4
    dec     ecx
    jnz     .inv
    lea     rdi, [world_header + WORLDHDR.armor]
    mov     ecx, 4
.armor:
    call    gear_unroll
    add     rdi, 4
    dec     ecx
    jnz     .armor
    lea     rdx, [world_header + WORLDHDR.containers]
    mov     esi, MAX_CONTAINERS
.cont:
    cmp     byte [rdx + CONTAINER.kind], 0
    je      .cnext
    lea     rdi, [rdx + CONTAINER.slots]
    mov     ecx, 27
.cell:
    call    gear_unroll
    add     rdi, 4
    dec     ecx
    jnz     .cell
.cnext:
    add     rdx, CONTAINER_size
    dec     esi
    jnz     .cont
    ret

; gear_unroll(rdi ITEMSTACK*): zero dmg when the id is gear. Leaf, clobbers eax, r8.
gear_unroll:
    movzx   eax, byte [rdi + ITEMSTACK.id]
    cmp     eax, NUM_ITEMS
    jae     .ret
    lea     r8, [item_gear]
    cmp     byte [r8 + rax], GK_NONE
    je      .ret
    mov     word [rdi + ITEMSTACK.dmg], 0
.ret:
    ret
