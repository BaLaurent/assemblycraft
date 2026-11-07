; test_worldgen.asm - terrain generator tests.
%include "common.inc"
default rel

global test_worldgen_deterministic, test_worldgen_shape

extern blocks
extern world_clear, world_generate, fnv1a

section .text

; hash of the whole block array
%macro HASH_BLOCKS 0
    lea     rdi, [blocks]
    mov     esi, WORLD_VOLUME
    call    fnv1a
%endmacro

test_worldgen_deterministic:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    mov     edi, 42
    call    world_generate
    HASH_BLOCKS
    mov     ebx, eax
    mov     edi, 42
    call    world_generate
    HASH_BLOCKS
    cmp     eax, ebx
    jne     .fail
    mov     edi, 43
    call    world_generate
    HASH_BLOCKS
    cmp     eax, ebx
    je      .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    pop     r12
    pop     rbx
    pop     rbp
    ret

test_worldgen_shape:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    call    world_clear
    mov     edi, 42
    call    world_generate
    ; bedrock at y = 0 of every column (first 65536 bytes)
    lea     rsi, [blocks]
    mov     ecx, 65536
.bed:
    cmp     byte [rsi], BEDROCK
    jne     .fail
    inc     rsi
    dec     ecx
    jnz     .bed
    ; count ids, reject any >= NUM_BLOCKS
    lea     rsi, [blocks]
    mov     ecx, WORLD_VOLUME
    xor     ebx, ebx                    ; grass
    xor     r12d, r12d                  ; log
    xor     r13d, r13d                  ; leaves
.scan:
    movzx   eax, byte [rsi]
    cmp     eax, NUM_BLOCKS
    jae     .fail
    cmp     eax, GRASS
    sete    dl
    movzx   edx, dl
    add     ebx, edx
    cmp     eax, LOG
    sete    dl
    movzx   edx, dl
    add     r12d, edx
    cmp     eax, LEAVES
    sete    dl
    movzx   edx, dl
    add     r13d, edx
    inc     rsi
    dec     ecx
    jnz     .scan
    cmp     ebx, 10000
    jbe     .fail
    test    r12d, r12d
    jz      .fail
    test    r13d, r13d
    jz      .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
