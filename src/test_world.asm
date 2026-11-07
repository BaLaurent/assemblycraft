; test_world.asm - world storage tests plus the shared fnv1a helper.
%include "common.inc"
default rel

global fnv1a, test_world_bounds, test_world_set_marks_dirty, test_world_save_load

extern blocks, chunk_dirty, world_header
extern world_get, world_set, world_is_solid, world_clear, world_save, world_load
extern file_write_atomic

section .rodata
save_path: db "/tmp/assemblycraft-selftest.acw", 0
garbage:   db "garbage!!!"

section .text

; fnv1a(rdi ptr, rsi len) -> eax  (FNV-1a 32-bit)
fnv1a:
    mov     eax, 2166136261
    test    rsi, rsi
    jz      .done
.loop:
    movzx   ecx, byte [rdi]
    xor     eax, ecx
    imul    eax, eax, 16777619
    inc     rdi
    dec     rsi
    jnz     .loop
.done:
    ret

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
