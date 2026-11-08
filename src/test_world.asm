; test_world.asm - world storage tests.
%include "common.inc"
default rel

global test_world_bounds, test_world_set_marks_dirty, test_world_save_load
global test_world_load_v1_converts, test_world_load_v2_converts, test_world_load_v3_migrates_items

extern blocks, chunk_dirty, world_header
extern world_get, world_set, world_is_solid, world_clear, world_save, world_load
extern file_write_atomic, file_unlink, fnv1a

section .rodata
save_path: db "/tmp/assemblycraft-selftest.acw", 0
v1_path:   db "/tmp/assemblycraft-selftest-v1.acw", 0
v2_path:   db "/tmp/assemblycraft-selftest-v2.acw", 0
garbage:   db "garbage!!!"
v1_magic:  db "ACRAFT01"
v2_magic:  db "ACRAFT02"
v3_magic:  db "ACRAFT03"
v4_magic:  db "ACRAFT04"
v1_hotbar: db 1, 3, 2, 4, 5, 6, 7, 9, 10

section .text

; expect eax == value, else fail
%macro EXPECT_EAX 1
    cmp     eax, %1
    jne     .fail
%endmacro

test_world_bounds:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    mov     edi, -1
    xor     esi, esi
    xor     edx, edx
    call    world_get
    EXPECT_EAX AIR
    mov     edi, 256
    xor     esi, esi
    xor     edx, edx
    call    world_get
    EXPECT_EAX AIR
    xor     edi, edi
    mov     esi, 64
    xor     edx, edx
    call    world_get
    EXPECT_EAX AIR
    mov     edi, -1
    mov     esi, 10
    mov     edx, 10
    call    world_is_solid
    EXPECT_EAX 1
    mov     edi, 256
    mov     esi, 10
    mov     edx, 10
    call    world_is_solid
    EXPECT_EAX 1
    mov     edi, 10
    mov     esi, -1
    mov     edx, 10
    call    world_is_solid
    EXPECT_EAX 1
    mov     edi, 10
    mov     esi, 64
    mov     edx, 10
    call    world_is_solid
    EXPECT_EAX 0
    lea     rdi, [blocks]
    mov     esi, WORLD_VOLUME
    call    fnv1a
    mov     ebx, eax
    mov     edi, -1
    xor     esi, esi
    xor     edx, edx
    mov     ecx, STONE
    call    world_set
    lea     rdi, [blocks]
    mov     esi, WORLD_VOLUME
    call    fnv1a
    EXPECT_EAX ebx
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

test_world_set_marks_dirty:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    lea     rdi, [chunk_dirty]
    mov     ecx, NUM_CHUNKS
    xor     eax, eax
    rep     stosb
    mov     edi, 16
    mov     esi, 5
    mov     edx, 5
    mov     ecx, STONE
    call    world_set
    cmp     byte [chunk_dirty + 0], 1
    jne     .fail
    cmp     byte [chunk_dirty + 1], 1
    jne     .fail
    cmp     byte [chunk_dirty + 2], 0
    jne     .fail
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret

test_world_save_load:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
%if WORLDHDR_size != 16384 || WORLDHDR.armor != 944 || WORLDHDR.containers != 1024 || CONTAINER_size != 128
    jmp     .fail
%endif
%if WORLDHDR.player != 68 || WORLDHDR.health != 136 || WORLDHDR.inventory != 156 || WORLDHDR.mobs != 304
    jmp     .fail
%endif
    mov     edi, 1
    mov     esi, 2
    mov     edx, 3
    mov     ecx, BRICK
    call    world_set
    mov     edi, 255
    mov     esi, 63
    mov     edx, 255
    mov     ecx, GLASS
    call    world_set
    mov     dword [world_header + WORLDHDR.seed], 7
    lea     rdi, [blocks]
    mov     esi, WORLD_VOLUME
    call    fnv1a
    mov     ebx, eax
    lea     rdi, [save_path]
    call    world_save
    EXPECT_EAX 0
    call    world_clear
    mov     dword [world_header + WORLDHDR.seed], 0
    lea     rdi, [save_path]
    call    world_load
    EXPECT_EAX 0
    lea     rdi, [blocks]
    mov     esi, WORLD_VOLUME
    call    fnv1a
    EXPECT_EAX ebx
    cmp     dword [world_header + WORLDHDR.seed], 7
    jne     .fail
    mov     edi, 1
    mov     esi, 2
    mov     edx, 3
    call    world_get
    EXPECT_EAX BRICK
    lea     rdi, [save_path]
    lea     rsi, [garbage]
    mov     edx, 10
    call    file_write_atomic
    EXPECT_EAX 0
    lea     rdi, [save_path]
    call    world_load
    EXPECT_EAX 2
    mov     eax, SYS_UNLINK
    lea     rdi, [save_path]
    syscall
    lea     rdi, [save_path]
    call    world_load
    EXPECT_EAX 1
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; A 0.1 file (48-byte header + blocks) loads as a v3 Creative world.
test_world_load_v1_converts:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    mov     edi, 1
    mov     esi, 2
    mov     edx, 3
    mov     ecx, BRICK
    call    world_set
    lea     rdi, [world_header]
    mov     ecx, WORLD_V1_HDR
    xor     eax, eax
    rep     stosb
    mov     rax, [v1_magic]
    mov     [world_header], rax
    mov     dword [world_header + V1_SEED], 77
    mov     byte [world_header + V1_SEL], 2
    lea     rsi, [v1_hotbar]
    lea     rdi, [world_header + V1_HOTBAR]
    mov     ecx, 9
    rep     movsb
    ; blocks forward to world_header+48 (dest < src, so a forward copy is safe)
    lea     rsi, [blocks]
    lea     rdi, [world_header + WORLD_V1_HDR]
    mov     ecx, WORLD_VOLUME
    rep     movsb
    lea     rdi, [v1_path]
    lea     rsi, [world_header]
    mov     edx, WORLD_V1_SIZE
    call    file_write_atomic
    EXPECT_EAX 0
    call    world_clear
    lea     rdi, [v1_path]
    call    world_load
    EXPECT_EAX 0
    mov     rax, [v4_magic]
    cmp     [world_header + WORLDHDR.magic], rax
    jne     .fail
    cmp     dword [world_header + WORLDHDR.seed], 77
    jne     .fail
    cmp     dword [world_header + WORLDHDR.mode], MODE_CREATIVE
    jne     .fail
    cmp     byte [world_header + WORLDHDR.inventory + 2*4 + ITEMSTACK.id], GRASS
    jne     .fail
    cmp     dword [world_header + WORLDHDR.sel], 2
    jne     .fail
    mov     edi, 1
    mov     esi, 2
    mov     edx, 3
    call    world_get
    EXPECT_EAX BRICK
    lea     rdi, [v1_path]
    call    file_unlink
    xor     eax, eax
    pop     rbp
    ret
.fail:
    lea     rdi, [v1_path]
    call    file_unlink
    mov     eax, 1
    pop     rbp
    ret

; A v2 file (1024-byte header + blocks) loads as v3 with the v3-only fields zeroed.
test_world_load_v2_converts:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    mov     edi, 1
    mov     esi, 2
    mov     edx, 3
    mov     ecx, BRICK
    call    world_set
    ; lands on containers record 0's .kind while the v2 image sits at world_header
    mov     edi, 3
    xor     esi, esi
    xor     edx, edx
    mov     ecx, STONE
    call    world_set
    lea     rdi, [world_header]
    mov     ecx, WORLD_BASE_HDR
    xor     eax, eax
    rep     stosb
    mov     rax, [v2_magic]
    mov     [world_header], rax
    mov     dword [world_header + WORLDHDR.seed], 55
    mov     byte [world_header + WORLDHDR.inventory + ITEMSTACK.id], DIRT
    mov     byte [world_header + WORLDHDR.inventory + ITEMSTACK.count], 5
    mov     byte [world_header + WORLDHDR.inventory + 4 + ITEMSTACK.id], V3_FIRST_ITEM ; old STICK
    mov     byte [world_header + WORLDHDR.inventory + 4 + ITEMSTACK.count], 2
    ; blocks forward to world_header+1024 (dest < src, so a forward copy is safe)
    lea     rsi, [blocks]
    lea     rdi, [world_header + WORLD_BASE_HDR]
    mov     ecx, WORLD_VOLUME
    rep     movsb
    lea     rdi, [v2_path]
    lea     rsi, [world_header]
    mov     edx, WORLD_V2_SIZE
    call    file_write_atomic
    EXPECT_EAX 0
    call    world_clear
    lea     rdi, [v2_path]
    call    world_load
    EXPECT_EAX 0
    mov     rax, [v4_magic]
    cmp     [world_header + WORLDHDR.magic], rax
    jne     .fail
    cmp     dword [world_header + WORLDHDR.seed], 55
    jne     .fail
    cmp     byte [world_header + WORLDHDR.inventory + ITEMSTACK.id], DIRT
    jne     .fail
    cmp     byte [world_header + WORLDHDR.inventory + ITEMSTACK.count], 5
    jne     .fail
    cmp     word [world_header + WORLDHDR.inventory + 4], STICK | (2 << 8)
    jne     .fail
    mov     edi, 1
    mov     esi, 2
    mov     edx, 3
    call    world_get
    EXPECT_EAX BRICK
    cmp     byte [world_header + WORLDHDR.containers + CONTAINER.kind], 0
    jne     .fail
    cmp     dword [world_header + WORLDHDR.armor], 0
    jne     .fail
    lea     rdi, [v2_path]
    call    file_unlink
    xor     eax, eax
    pop     rbp
    ret
.fail:
    lea     rdi, [v2_path]
    call    file_unlink
    mov     eax, 1
    pop     rbp
    ret

; A v3 (0.6) file loads with its item ids moved to the v4 numbering: blocks keep their
; id, items move up by FIRST_ITEM - V3_FIRST_ITEM, unused ids are emptied; a v4 save is
; not migrated a second time.
test_world_load_v3_migrates_items:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    mov     edi, 10
    mov     esi, 5
    mov     edx, 10
    mov     ecx, CHEST
    call    world_set
    lea     rdi, [world_header]
    mov     ecx, WORLD_HDR_SIZE
    xor     eax, eax
    rep     stosb
    mov     rax, [v3_magic]
    mov     [world_header], rax
    lea     rax, [world_header]
    mov     word [rax + WORLDHDR.inventory], 32 | (5 << 8)          ; old STICK x5
    mov     word [rax + WORLDHDR.inventory + 4], 24 | (3 << 8)      ; MOSSY_STONE_BRICK x3
    mov     word [rax + WORLDHDR.armor + 4], 79 | (1 << 8)          ; old DIAMOND_CHESTPLATE
    lea     rax, [world_header + WORLDHDR.containers]
    mov     dword [rax], 10 | (5 << 8) | (10 << 16) | (CONT_CHEST << 24)
    mov     word [rax + CONTAINER.slots], 44 | (7 << 8)             ; old IRON_INGOT x7
    mov     word [rax + CONTAINER.slots + 4], 27 | (1 << 8)         ; unused v3 id
    lea     rdi, [save_path]
    lea     rsi, [world_header]
    mov     edx, WORLD_FILE_SIZE
    call    file_write_atomic
    EXPECT_EAX 0
    call    world_clear
    mov     qword [world_header], 0
    lea     rdi, [save_path]
    call    world_load
    EXPECT_EAX 0
    lea     rax, [world_header]
    cmp     word [rax + WORLDHDR.inventory], STICK | (5 << 8)
    jne     .fail
    cmp     word [rax + WORLDHDR.inventory + 4], MOSSY_STONE_BRICK | (3 << 8)
    jne     .fail
    cmp     byte [rax + WORLDHDR.armor + 4], DIAMOND_CHESTPLATE
    jne     .fail
    lea     rax, [world_header + WORLDHDR.containers]
    cmp     word [rax + CONTAINER.slots], IRON_INGOT | (7 << 8)
    jne     .fail
    cmp     dword [rax + CONTAINER.slots + 4], 0
    jne     .fail
    mov     edi, 10
    mov     esi, 5
    mov     edx, 10
    call    world_get
    EXPECT_EAX CHEST
    lea     rdi, [save_path]
    call    world_save
    EXPECT_EAX 0
    mov     rax, [v4_magic]
    cmp     [world_header + WORLDHDR.magic], rax
    jne     .fail
    lea     rdi, [save_path]
    call    world_load
    EXPECT_EAX 0
    cmp     word [world_header + WORLDHDR.inventory], STICK | (5 << 8)
    jne     .fail
    lea     rdi, [save_path]
    call    file_unlink
    xor     eax, eax
    pop     rbp
    ret
.fail:
    lea     rdi, [save_path]
    call    file_unlink
    mov     eax, 1
    pop     rbp
    ret
