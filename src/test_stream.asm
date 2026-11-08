; test_stream.asm - streaming tests: without a generator thread (everything inline) and with one.
%include "common.inc"
default rel

global test_stream_sync, test_stream_thread

extern settings, world_clear, world_set, world_get, world_column, world_chunk, world_origin_x, world_origin_z
extern stream_begin, stream_end, stream_update, stream_thread_start, stream_thread_stop
extern gen_column, time_mono, dir_remove_tree, region_set_dir

section .rodata
dir_stream:     db "/tmp/ac9t-stream", 0
align 4
k_one:          dd 1.0
k_004:          dd 0.004
k_five:         dd 5.0

section .bss
alignb 16
gb:             resb GENBUF_size
t0:             resd 1
neighbour:      resd 1

section .text

; all_lit(edi acx, esi acz, edx r) -> eax 1 when every column within Chebyshev r of (acx, acz) is COL_LIT
all_lit:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12d, edi
    mov     r13d, esi
    mov     r15d, edx
    mov     r14d, edx
    neg     r14d                        ; dz
.z:
    mov     ebx, r15d
    neg     ebx                         ; dx
.x:
    lea     edi, [r12 + rbx]
    lea     esi, [r13 + r14]
    call    world_column
    test    rax, rax
    jz      .no
    cmp     dword [rax + COLUMN.state], COL_LIT
    jne     .no
    inc     ebx
    cmp     ebx, r15d
    jle     .x
    inc     r14d
    cmp     r14d, r15d
    jle     .z
    mov     eax, 1
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; pump(edi x, esi z) -> eax 0 when, within 60 stream_update calls around the cell (x, z), every column
; within Chebyshev 3 of its column became COL_LIT
pump:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edi                   ; the centre column
    add     r14d, [world_origin_x]
    sar     r14d, 4
    mov     r15d, 60
.again:
    mov     edi, r12d
    mov     esi, r13d
    movss   xmm0, [k_one]
    call    stream_update
    mov     edi, r14d
    mov     esi, r13d
    add     esi, [world_origin_z]
    sar     esi, 4
    mov     edx, 3
    call    all_lit
    test    eax, eax
    jnz     .ok
    dec     r15d
    jnz     .again
    mov     eax, 1
    jmp     .ret
.ok:
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; compare_column(edi acx, esi acz) -> eax 0 when the loaded column's blocks are exactly what gen_column
; produces for it (chunks the loaded column holds as null must be all AIR there)
compare_column:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 8
    mov     r12d, edi
    mov     r13d, esi
    mov     [gb + GENBUF.cx], edi
    mov     [gb + GENBUF.cz], esi
    lea     rdi, [gb]
    call    gen_column
    xor     ebx, ebx                    ; cy
.cy:
    mov     edi, r12d
    mov     esi, ebx
    mov     edx, r13d
    call    world_chunk
    mov     r14, rax
    mov     eax, ebx
    shl     eax, 12
    lea     rdi, [gb + GENBUF.blocks + rax]
    mov     ecx, 512
    test    r14, r14
    jz      .null
    mov     rsi, r14
    repe    cmpsq
    jne     .diff
    jmp     .next
.null:
    xor     eax, eax
    repe    scasq
    jne     .diff
.next:
    inc     ebx
    cmp     ebx, COL_CHUNKS
    jb      .cy
    xor     eax, eax
    jmp     .ret
.diff:
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; no worker: stream_update generates inline. Load the columns around (8, 8), compare one with a direct
; gen_column, edit it, walk 3000 cells away so it is unloaded (and saved), walk back: the edit is read
; from its region file
test_stream_sync:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    xor     ebx, ebx                    ; 0 = pass
    mov     r12d, [settings + SETTINGS.render_dist]
    mov     dword [settings + SETTINGS.render_dist], 2
    call    world_clear
    mov     edi, 42
    lea     rsi, [dir_stream]
    call    stream_begin
    mov     edi, 8
    mov     esi, 8
    call    pump
    test    eax, eax
    jnz     .bad
    mov     edi, 1
    mov     esi, 1
    call    compare_column
    test    eax, eax
    jnz     .bad
    movzx   eax, byte [gb + GENBUF.blocks + (70 << 8) + (4 << 4) + 5]
    mov     [neighbour], eax            ; what (21, 70, 20) is before the edit next to it
    mov     edi, 20                     ; an edit in column (1, 1)
    mov     esi, 70
    mov     edx, 20
    mov     ecx, GLASS
    call    world_set
    mov     edi, 20
    mov     esi, 70
    mov     edx, 20
    call    world_get
    cmp     eax, GLASS
    jne     .bad
    mov     edi, 3000                   ; far away: everything near the old spot unloads
    mov     esi, 8
    call    pump
    test    eax, eax
    jnz     .bad
    mov     edi, 1
    mov     esi, 1
    call    world_column
    test    rax, rax
    jnz     .bad                        ; unloaded
    mov     edi, 8                      ; and back
    mov     esi, 8
    call    pump
    test    eax, eax
    jnz     .bad
    mov     edi, 20
    mov     esi, 70
    mov     edx, 20
    call    world_get
    cmp     eax, GLASS
    jne     .bad                        ; the edit came back from the region file
    mov     edi, 21
    mov     esi, 70
    mov     edx, 20
    call    world_get
    cmp     eax, [neighbour]
    jne     .bad                        ; its neighbour is untouched
    jmp     .done
.bad:
    mov     ebx, 1
.done:
    xor     edi, edi
    call    stream_end
    xor     edi, edi
    call    region_set_dir
    lea     rdi, [dir_stream]
    call    dir_remove_tree
    mov     [settings + SETTINGS.render_dist], r12d
    mov     eax, ebx
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; with the generator thread: the columns around (-40, 72) are generated on the worker and installed by
; stream_update; column (-3, 4) equals a direct gen_column (compared once the worker has stopped)
test_stream_thread:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    xor     ebx, ebx
    mov     r12d, [settings + SETTINGS.render_dist]
    mov     dword [settings + SETTINGS.render_dist], 2
    call    world_clear
    call    stream_thread_start
    mov     edi, 7
    xor     esi, esi
    call    stream_begin
    call    time_mono
    movss   [t0], xmm0
.spin:
    mov     edi, -40
    mov     esi, 72
    movss   xmm0, [k_004]
    call    stream_update
    mov     edi, -3
    mov     esi, 4
    call    world_column
    test    rax, rax
    jz      .wait
    cmp     dword [rax + COLUMN.state], COL_LIT
    je      .ready
.wait:
    call    time_mono
    subss   xmm0, [t0]
    comiss  xmm0, [k_five]
    jbe     .spin
    mov     ebx, 1                      ; not lit within 5 seconds
.ready:
    call    stream_thread_stop
    test    eax, eax
    jz      .joined
    mov     ebx, 1                      ; pthread_join failed
.joined:
    test    ebx, ebx
    jnz     .done
    mov     edi, -3
    mov     esi, 4
    call    compare_column
    test    eax, eax
    jz      .done
    mov     ebx, 1
.done:
    xor     edi, edi
    call    stream_end
    mov     [settings + SETTINGS.render_dist], r12d
    mov     eax, ebx
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
