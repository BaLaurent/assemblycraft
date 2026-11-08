; test_world.asm - world storage tests.
%include "common.inc"
default rel

global test_world_bounds, test_world_set_marks_dirty, test_world_save_load

extern blocks, chunk_dirty, world_header
extern world_get, world_set, world_is_solid, world_clear, world_save, world_load
extern file_write_atomic, file_unlink, file_read, fnv1a

section .rodata
save_path: db "/tmp/assemblycraft-selftest.acw", 0
garbage:   db "garbage!!!"
v6_magic:  db "ACRAFT06"

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
%if WORLDHDR_size != 32768 || WORLDHDR.armor != 944 || WORLDHDR.rpg != 960 || CONTAINER_size != 136
    jmp     .fail
%endif
%if WORLDHDR.jewelry != 16384 || WORLDHDR.rpgx != 16400 || RPGEXT_size != 256
    jmp     .fail
%endif
%if MOB_size != 228 || INVENTORY_size != 216 || SITE_size != 56 || COLUMN_size != 408
    jmp     .fail
%endif
%if WORLDHDR.player != 68 || WORLDHDR.health != 136 || WORLDHDR.inventory != 156 || WORLDHDR.origin_x != 300
    jmp     .fail
%endif
%if WORLDHDR.bed_set != 320 || WORLDHDR.boats != 332 || WORLDHDR.mob_count != 1024 || WORLDHDR.mobs != 1028 || WORLDHDR.sites != 2312
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
    mov     rax, [v6_magic]
    cmp     [world_header + WORLDHDR.magic], rax
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
