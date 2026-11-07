; selftest.asm - runs every registered test and prints a summary.
%include "common.inc"
default rel

global selftest_run

extern sys_print, i32_to_str, str_append
extern test_world_bounds, test_world_set_marks_dirty, test_world_save_load
extern test_world_load_v1_converts
extern test_worldgen_deterministic, test_worldgen_shape
extern test_mesh_single_block, test_mesh_adjacent_opaque, test_mesh_adjacent_leaves
extern test_mesh_adjacent_glass, test_mesh_chunk_boundary
extern test_raycast_hit_forward, test_raycast_miss_beyond_reach, test_raycast_hit_from_above
extern test_physics_land_on_floor, test_physics_wall_blocks
extern test_physics_jump_clears_one_block, test_body_intersects_block

%macro TEST 1
    dq test_%1, name_%1
%endmacro
%macro TESTNAME 1
    name_%1: db %str(%1), 0
%endmacro

section .data
align 8
tests:
    TEST world_bounds
    TEST world_set_marks_dirty
    TEST world_save_load
    TEST world_load_v1_converts
    TEST worldgen_deterministic
    TEST worldgen_shape
    TEST mesh_single_block
    TEST mesh_adjacent_opaque
    TEST mesh_adjacent_leaves
    TEST mesh_adjacent_glass
    TEST mesh_chunk_boundary
    TEST raycast_hit_forward
    TEST raycast_miss_beyond_reach
    TEST raycast_hit_from_above
    TEST physics_land_on_floor
    TEST physics_wall_blocks
    TEST physics_jump_clears_one_block
    TEST body_intersects_block
    dq 0

section .rodata
    TESTNAME world_bounds
    TESTNAME world_set_marks_dirty
    TESTNAME world_save_load
    TESTNAME world_load_v1_converts
    TESTNAME worldgen_deterministic
    TESTNAME worldgen_shape
    TESTNAME mesh_single_block
    TESTNAME mesh_adjacent_opaque
    TESTNAME mesh_adjacent_leaves
    TESTNAME mesh_adjacent_glass
    TESTNAME mesh_chunk_boundary
    TESTNAME raycast_hit_forward
    TESTNAME raycast_miss_beyond_reach
    TESTNAME raycast_hit_from_above
    TESTNAME physics_land_on_floor
    TESTNAME physics_wall_blocks
    TESTNAME physics_jump_clears_one_block
    TESTNAME body_intersects_block
s_ok:     db "ok ", 0
s_fail:   db "FAIL ", 0
s_nl:     db 10, 0
s_head:   db "selftest: ", 0
s_passed: db " passed, ", 0
s_failed: db " failed", 10, 0

section .bss
line: resb 128

section .text

; selftest_run() -> eax 0 iff every test passed
selftest_run:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    lea     rbx, [tests]
    xor     r12d, r12d                  ; passed
    xor     r13d, r13d                  ; failed
.next:
    mov     rax, [rbx]
    test    rax, rax
    jz      .summary
    call    rax
    lea     rsi, [s_ok]
    test    eax, eax
    jz      .pass
    inc     r13d
    lea     rsi, [s_fail]
    jmp     .print
.pass:
    inc     r12d
.print:
    mov     edi, 1
    call    sys_print
    mov     edi, 1
    mov     rsi, [rbx + 8]
    call    sys_print
    mov     edi, 1
    lea     rsi, [s_nl]
    call    sys_print
    add     rbx, 16
    jmp     .next
.summary:
    lea     rdi, [line]
    lea     rsi, [s_head]
    call    str_append
    mov     edi, r12d
    mov     rsi, rax
    call    i32_to_str
    mov     rdi, rax
    lea     rsi, [s_passed]
    call    str_append
    mov     edi, r13d
    mov     rsi, rax
    call    i32_to_str
    mov     rdi, rax
    lea     rsi, [s_failed]
    call    str_append
    mov     byte [rax], 0
    mov     edi, 1
    lea     rsi, [line]
    call    sys_print
    xor     eax, eax
    test    r13d, r13d
    setnz   al
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
