; world.asm - block storage, chunk dirty flags, save/load of the world file image.
%include "common.inc"
default rel

global world_header, blocks, chunk_dirty
global world_get, world_set, world_is_solid, world_is_opaque, world_top_y
global world_clear, world_mark_all_dirty, world_save, world_load

extern block_flags, file_read, file_write_atomic

section .rodata
world_magic: db "ACRAFT01"

section .bss
; world_header and blocks are one contiguous 4194352-byte file image.
alignb 64
world_header: resb WORLD_HDR_SIZE
blocks:       resb WORLD_VOLUME
world_slack:  resb 16                   ; absorbs the +1 probe byte of world_load
chunk_dirty:  resb NUM_CHUNKS

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

; world_set(edi x, esi y, edx z, ecx id). Marks dirty every chunk containing an
; in-bounds cell of the 3x3x3 neighbourhood (a box, so mark the clamped box).
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
    mov     [blocks + rax], cl
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
.ret:
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

; world_clear(): zero every block
world_clear:
    lea     rdi, [blocks]
    mov     ecx, WORLD_VOLUME / 8
    xor     eax, eax
    rep     stosq
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

; world_load(rdi path) -> eax 0 ok / 1 missing / 2 invalid / 3 I/O error
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
    jne     .invalid
    mov     rax, [world_magic]
    cmp     [world_header + WORLDHDR.magic], rax
    jne     .invalid
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
