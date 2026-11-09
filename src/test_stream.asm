; test_stream.asm - streaming tests: without a generator thread (everything inline) and with one.
%include "common.inc"
default rel

global test_stream_sync, test_stream_thread, test_stream_extra_centres, test_stream_guest_local_until_joined
global test_stream_pending_edit_columns

extern settings, world_clear, world_set, world_get, world_column, world_chunk, world_origin_x, world_origin_z
extern stream_begin, stream_end, stream_update, stream_thread_start, stream_thread_stop
extern gen_column, time_mono, dir_remove_tree, region_set_dir, region_write_column, region_plan
extern worldgen_set_seed, conts, cont_create, cont_at, gen_bufs, install_waiting, stream_frame
extern net_role, net_peers, gen_seed, col_index
extern net_in_world, net_capture, net_captured, net_column_forget, net_colv_pending
extern nw_apply_edit, net_edits_replay, net_edit_columns, region_read_column, world_set_raw

%define GJ_CAP 4096                     ; the capture buffer of test_stream_guest_local_until_joined
%define PE_MAX 32                       ; the most columns test_stream_pending_edit_columns asks net_edit_columns for

section .rodata
dir_stream:     db "/tmp/ac9t-stream", 0
dir_conts:      db "/tmp/ac9t-stream-conts", 0
dir_pending:    db "/tmp/ac11t-pending", 0
align 4
k_one:          dd 1.0
k_004:          dd 0.004
k_five:         dd 5.0

section .bss
alignb 16
gb:             resb GENBUF_size
t0:             resd 1
neighbour:      resd 1
plan:           resb MAX_REGION_SITES * SITE_size
has_chest:      resb 16                ; per column of the 3 x 3 around the chest column: it holds generated chests
t_ccx:          resd 1                 ; the chest column
t_ccz:          resd 1
pinned:         resd 1                 ; a DONE buffer was seen holding a column that backs off
pinned_n:       resd 1
sv_role:        resd 1                 ; test_stream_extra_centres borrows the net role and the peer in slot 1:
sv_peer:        resd 5                 ; their state, position (ax, az, fx and fz, y)
sv_seed:        resd 1
gj_cap:         resb GJ_CAP            ; test_stream_guest_local_until_joined: what the capture seam recorded
gj_pend:        resd 1                 ; ... and the column requests that were pending before it
pe_cols:        resd 2 * PE_MAX        ; test_stream_pending_edit_columns: the (acx, acz) pairs net_edit_columns listed

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

; fill_conts(): every record of conts[] in use, by chests of columns far away from the world's origin
fill_conts:
    lea     rdi, [conts]
    xor     ecx, ecx
.fill:
    mov     byte [rdi + CONTAINER.kind], CONT_CHEST
    mov     eax, ecx
    shl     eax, 4
    add     eax, 2000000
    mov     [rdi + CONTAINER.x], eax            ; one column each
    mov     dword [rdi + CONTAINER.y], 10
    mov     dword [rdi + CONTAINER.z], 2000000
    add     rdi, CONTAINER_size
    inc     ecx
    cmp     ecx, MAX_CONTAINERS
    jb      .fill
    ret

; clear_conts(): every record of conts[] free again
clear_conts:
    lea     rdi, [conts]
    mov     ecx, MAX_CONTAINERS * CONTAINER_size
    xor     eax, eax
    rep     stosb
    ret

; count_lit(edi acx, esi acz, edx r) -> eax how many columns within Chebyshev r of (acx, acz) are COL_LIT
count_lit:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r12d, edi
    mov     r13d, esi
    mov     r15d, edx
    xor     ebp, ebp                    ; the count
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
    jz      .next
    cmp     dword [rax + COLUMN.state], COL_LIT
    jne     .next
    inc     ebp
.next:
    inc     ebx
    cmp     ebx, r15d
    jle     .x
    inc     r14d
    cmp     r14d, r15d
    jle     .z
    mov     eax, ebp
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; pump_n(edi x, esi z, edx n): n stream_update calls (1 s budget each) around the cell (x, z), n >= 1
pump_n:
    push    rbx
    push    r12
    push    r13
    mov     r12d, edi
    mov     r13d, esi
    mov     ebx, edx
.again:
    mov     edi, r12d
    mov     esi, r13d
    movss   xmm0, [k_one]
    call    stream_update
    dec     ebx
    jnz     .again
    pop     r13
    pop     r12
    pop     rbx
    ret

; window_ok(edi all) -> eax 1 when the 3 x 3 columns around the chest column (t_ccx, t_ccz) are COL_LIT:
; all = 1 every one of them, all = 0 every one that holds no generated chest (has_chest)
window_ok:
    push    rbx
    push    r12
    sub     rsp, 8
    mov     r12d, edi
    xor     ebx, ebx                    ; index = (dz + 1) * 3 + dx + 1
.col:
    mov     eax, ebx
    xor     edx, edx
    mov     ecx, 3
    div     ecx                         ; eax = dz + 1, edx = dx + 1
    mov     edi, [t_ccx]
    lea     edi, [rdi + rdx - 1]
    mov     esi, [t_ccz]
    lea     esi, [rsi + rax - 1]
    call    world_column
    test    rax, rax
    jz      .out
    cmp     dword [rax + COLUMN.state], COL_LIT
    je      .next
.out:                                   ; not lit: only a column with chests may be that, and not when all = 1
    test    r12d, r12d
    jnz     .no
    cmp     byte [has_chest + rbx], 0
    je      .no
.next:
    inc     ebx
    cmp     ebx, 9
    jb      .col
    mov     eax, 1
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; pinned_check(): sets [pinned] when a DONE generator buffer belongs to a column whose install is
; backing off - such a buffer would stay held, and 8 of them would stop all generation for the session
pinned_check:
    push    rbx
    push    r12
    sub     rsp, 8
    lea     rbx, [gen_bufs]
    mov     r12d, GEN_SLOTS
.l:
    cmp     dword [rbx + GENBUF.state], GB_DONE
    jne     .n
    mov     edi, [rbx + GENBUF.cx]
    mov     esi, [rbx + GENBUF.cz]
    call    install_waiting
    test    eax, eax
    jz      .n
    mov     dword [pinned], 1
.n:
    add     rbx, GENBUF_size
    dec     r12d
    jnz     .l
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; no worker: stream_update generates inline. Load the columns around (8, 8), compare one with a direct
; gen_column, edit it, walk 3000 cells away so it is unloaded (and saved), walk back: the edit is read
; from its region file. Then conts_full_sync: a column that cannot be installed holds back only itself
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
    call    conts_full_sync
    or      ebx, eax
    mov     [settings + SETTINGS.render_dist], r12d
    mov     eax, ebx
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; with the generator thread: the columns around (-40, 72) are generated on the worker and installed by
; stream_update; column (-3, 4) equals a direct gen_column (compared once the worker has stopped). Then
; thread_conts_full: a generated column that cannot be installed holds back only itself
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
    call    thread_conts_full
    or      ebx, eax
    mov     [settings + SETTINGS.render_dist], r12d
    mov     eax, ebx
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; no worker, the container table full: column (0, 0) comes from its region file with a chest that has no
; record to go to, so it stays out - and the 48 other columns of the 7 x 7 window around (8, 8) still
; load (before the backoff was per column, this one failure froze the whole stream). Once the table has
; room, (0, 0) is retried and installs, with its chest. -> eax 0 = pass
conts_full_sync:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    xor     ebx, ebx
    mov     r12d, [settings + SETTINGS.render_dist]
    mov     dword [settings + SETTINGS.render_dist], 2
    lea     rdi, [dir_conts]
    call    dir_remove_tree             ; (the leftovers of an aborted run)
    call    world_clear
    lea     rdi, [dir_conts]
    call    region_set_dir
    mov     edi, 3                      ; column (0, 0) holds a chest, saved in its region file
    mov     esi, 61
    mov     edx, 3
    mov     ecx, CHEST
    call    world_set
    mov     edi, 3
    mov     esi, 61
    mov     edx, 3
    mov     ecx, CONT_CHEST
    call    cont_create
    test    rax, rax
    jz      .bad
    xor     edi, edi
    xor     esi, esi
    call    world_column
    test    rax, rax
    jz      .bad
    mov     rdi, rax
    call    region_write_column
    test    eax, eax
    jnz     .bad
    mov     edi, 42
    lea     rsi, [dir_conts]
    call    stream_begin                ; a session on that world: nothing loaded, conts[] empty
    call    fill_conts                  ; and now no record is free
    mov     edi, 8
    mov     esi, 8
    mov     edx, 130                    ; (0, 0) fails at frames 1, 61 and 121
    call    pump_n
    xor     edi, edi                    ; the 48 other columns of the window are lit
    xor     esi, esi
    mov     edx, 3
    call    count_lit
    cmp     eax, 48
    jne     .bad
    xor     edi, edi
    xor     esi, esi
    call    world_column
    test    rax, rax
    jz      .room                       ; not loaded: not lit either
    cmp     dword [rax + COLUMN.state], COL_LIT
    je      .bad
.room:
    call    clear_conts                 ; the table has room: the next retry takes it
    mov     edi, 8
    mov     esi, 8
    mov     edx, 70
    call    pump_n
    xor     edi, edi
    xor     esi, esi
    mov     edx, 3
    call    count_lit
    cmp     eax, 49
    jne     .bad
    mov     edi, 3                      ; it is the saved column: its chest is back
    mov     esi, 61
    mov     edx, 3
    call    world_get
    cmp     eax, CHEST
    jne     .bad
    mov     edi, 3
    mov     esi, 61
    mov     edx, 3
    call    cont_at
    test    rax, rax
    jz      .bad
    jmp     .done
.bad:
    mov     ebx, 1
.done:
    call    clear_conts
    xor     edi, edi
    call    stream_end
    xor     edi, edi
    call    region_set_dir
    lea     rdi, [dir_conts]
    call    dir_remove_tree
    mov     [settings + SETTINGS.render_dist], r12d
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; with the generator thread, the container table full: the first dungeon of region (0, 0) (seed 42) has
; a chest in the column of (x + 3, z + 3); that column is generated on the worker and cannot be installed:
; it backs off and frees its buffer (no buffer is ever seen DONE for a column that backs off, over 300
; more updates) while the columns around it (the 3 x 3 window, centred on it so that it is the first
; request and the first buffer) still load. Once the table has room, it installs. -> eax 0 = pass
thread_conts_full:
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
    mov     edi, 42
    call    worldgen_set_seed
    xor     edi, edi                    ; the first dungeon of region (0, 0)
    xor     esi, esi
    lea     rdx, [plan]
    call    region_plan
    mov     r13d, eax
    lea     r14, [plan]
.site:
    test    r13d, r13d
    jz      .bad                        ; no dungeon: this test needs one
    cmp     dword [r14 + SITE.kind], SITE_DUNGEON
    je      .found
    add     r14, SITE_size
    dec     r13d
    jmp     .site
.found:
    mov     eax, [r14 + SITE.x]         ; the column of its chest at (x + 3, z + 3)
    add     eax, 3
    sar     eax, 4
    mov     [t_ccx], eax
    mov     eax, [r14 + SITE.z]
    add     eax, 3
    sar     eax, 4
    mov     [t_ccz], eax
    xor     r13d, r13d                  ; which columns of the 3 x 3 around it hold generated chests
.flags:                                 ; (generated here, before the worker starts: gen_column is not reentrant)
    mov     eax, r13d
    xor     edx, edx
    mov     ecx, 3
    div     ecx                         ; eax = dz + 1, edx = dx + 1
    mov     ecx, [t_ccx]
    lea     ecx, [rcx + rdx - 1]
    mov     [gb + GENBUF.cx], ecx
    mov     ecx, [t_ccz]
    lea     ecx, [rcx + rax - 1]
    mov     [gb + GENBUF.cz], ecx
    lea     rdi, [gb]
    call    gen_column
    xor     eax, eax
    cmp     dword [gb + GENBUF.nchests], 0
    seta    al
    mov     [has_chest + r13], al
    inc     r13d
    cmp     r13d, 9
    jb      .flags
    cmp     byte [has_chest + 4], 0     ; the middle one is the chest column itself
    je      .bad
    call    stream_thread_start
    mov     edi, 42
    xor     esi, esi
    call    stream_begin                ; no world directory
    call    fill_conts                  ; no record is free
    call    time_mono
    movss   [t0], xmm0
.spin_full:
    call    pump_chest_column
    xor     edi, edi
    call    window_ok                   ; every column without chests lit?
    test    eax, eax
    jnz     .others
    call    time_mono
    subss   xmm0, [t0]
    comiss  xmm0, [k_five]
    jbe     .spin_full
    jmp     .bad                        ; not within 5 seconds: the failing column held the others back
.others:
    mov     dword [pinned], 0
    mov     dword [pinned_n], 300
.pin_loop:
    call    pump_chest_column
    call    pinned_check
    dec     dword [pinned_n]
    jnz     .pin_loop
    cmp     dword [pinned], 0
    jne     .bad                        ; a column that cannot install held its buffer
    mov     edi, 1
    call    window_ok
    test    eax, eax
    jnz     .bad                        ; the chest columns cannot be lit without a record each
    call    clear_conts                 ; the table has room: the retry installs them
    call    time_mono
    movss   [t0], xmm0
.spin_room:
    call    pump_chest_column
    mov     edi, 1
    call    window_ok
    test    eax, eax
    jnz     .done
    call    time_mono
    subss   xmm0, [t0]
    comiss  xmm0, [k_five]
    jbe     .spin_room
.bad:
    mov     ebx, 1
.done:
    call    stream_thread_stop          ; (nothing to stop when it never started)
    test    eax, eax
    jz      .joined
    mov     ebx, 1                      ; pthread_join failed
.joined:
    call    clear_conts
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

; pump_chest_column(): one stream_update (4 ms budget) around the middle of the chest column
pump_chest_column:
    sub     rsp, 8
    mov     edi, [t_ccx]
    shl     edi, 4
    add     edi, 8
    mov     esi, [t_ccz]
    shl     esi, 4
    add     esi, 8
    movss   xmm0, [k_004]
    call    stream_update
    add     rsp, 8
    ret

; ---- columns kept for remote players -----------------------------------------------------------------------

; count_loaded(edi acx, esi acz, edx r) -> eax how many columns within Chebyshev r of (acx, acz) are in the table
count_loaded:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r12d, edi
    mov     r13d, esi
    mov     r15d, edx
    xor     ebp, ebp                    ; the count
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
    jz      .next
    inc     ebp
.next:
    inc     ebx
    cmp     ebx, r15d
    jle     .x
    inc     r14d
    cmp     r14d, r15d
    jle     .z
    mov     eax, ebp
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; set_peer(edi acx): the peer in slot 1 is READY in the middle of column (acx, 0), 70 blocks up
set_peer:
    shl     edi, 4
    add     edi, 8
    mov     [net_peers + PEER_size + PEER.ps + PSTATE.pos + NPOS.ax], edi
    mov     dword [net_peers + PEER_size + PEER.ps + PSTATE.pos + NPOS.az], 8
    mov     dword [net_peers + PEER_size + PEER.ps + PSTATE.pos + NPOS.fx], 0
    mov     dword [net_peers + PEER_size + PEER.ps + PSTATE.pos + NPOS.y], 0x428C0000    ; 70.0
    mov     dword [net_peers + PEER_size + PEER.state], PEER_READY
    ret

; a hosting peer loads the columns around a remote player: the local player stands in column (0, 0), the
; peer in slot 1 (READY) in column (200, 0), 3200 blocks away; stream_update (inline) lights the 11 x 11
; columns around it (MP_SIM_R + 1 = 5), still lights the local 7 x 7 and loads nothing just outside the square.
; Then the peer walks to column 400: the square at 200 is unloaded (it is beyond MP_SIM_R + 2 of every centre)
; while the local area stays, and the column at 400 is loaded. -> eax 0 = pass
test_stream_extra_centres:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    xor     ebx, ebx                    ; 0 = pass
    movzx   eax, byte [net_role]
    mov     [sv_role], eax
    mov     eax, [net_peers + PEER_size + PEER.state]
    mov     [sv_peer], eax
    mov     eax, [net_peers + PEER_size + PEER.ps + PSTATE.pos + NPOS.ax]
    mov     [sv_peer + 4], eax
    mov     eax, [net_peers + PEER_size + PEER.ps + PSTATE.pos + NPOS.az]
    mov     [sv_peer + 8], eax
    mov     eax, [net_peers + PEER_size + PEER.ps + PSTATE.pos + NPOS.fx]
    mov     [sv_peer + 12], eax
    mov     eax, [net_peers + PEER_size + PEER.ps + PSTATE.pos + NPOS.y]
    mov     [sv_peer + 16], eax
    mov     eax, [gen_seed]
    mov     [sv_seed], eax
    mov     r12d, [settings + SETTINGS.render_dist]
    mov     dword [settings + SETTINGS.render_dist], 2
    call    world_clear
    mov     edi, 42
    xor     esi, esi
    call    stream_begin                ; no world directory: nothing is saved or read back
    mov     edi, 8
    mov     esi, 8
    call    pump                        ; the local 7 x 7 columns
    test    eax, eax
    jnz     .bad
    mov     byte [net_role], NET_ROLE_HOST
    mov     edi, 200
    call    set_peer
    mov     edi, 8
    mov     esi, 8
    mov     edx, 80
    call    pump_n
    mov     edi, 200                    ; the 11 x 11 around the remote player are lit
    xor     esi, esi
    mov     edx, 5
    call    count_lit
    cmp     eax, 121
    jne     .bad
    xor     edi, edi                    ; the local 7 x 7 still are
    xor     esi, esi
    mov     edx, 3
    call    count_lit
    cmp     eax, 49
    jne     .bad
    mov     edi, 200                    ; and 13 x 13 columns are loaded there, not one more
    xor     esi, esi
    mov     edx, 6
    call    count_loaded
    cmp     eax, 121
    jne     .bad
    mov     edi, 400                    ; the remote player walks to column 400
    call    set_peer
    mov     edi, 8
    mov     esi, 8
    mov     edx, 3
    call    pump_n
    mov     edi, 200                    ; nothing is left around 200
    xor     esi, esi
    mov     edx, 6
    call    count_loaded
    test    eax, eax
    jnz     .bad
    xor     edi, edi                    ; the local area stayed
    xor     esi, esi
    mov     edx, 3
    call    count_lit
    cmp     eax, 49
    jne     .bad
    mov     edi, 400                    ; and the new place started to load
    xor     esi, esi
    call    world_column
    test    rax, rax
    jz      .bad
    jmp     .done
.bad:
    mov     ebx, 1
.done:
    mov     eax, [sv_role]
    mov     [net_role], al
    mov     eax, [sv_peer]
    mov     [net_peers + PEER_size + PEER.state], eax
    mov     eax, [sv_peer + 4]
    mov     [net_peers + PEER_size + PEER.ps + PSTATE.pos + NPOS.ax], eax
    mov     eax, [sv_peer + 8]
    mov     [net_peers + PEER_size + PEER.ps + PSTATE.pos + NPOS.az], eax
    mov     eax, [sv_peer + 12]
    mov     [net_peers + PEER_size + PEER.ps + PSTATE.pos + NPOS.fx], eax
    mov     eax, [sv_peer + 16]
    mov     [net_peers + PEER_size + PEER.ps + PSTATE.pos + NPOS.y], eax
    xor     edi, edi
    call    stream_end
    call    index_empty                 ; every record went back: nothing is left in the index
    cmp     eax, 1
    je      .clean
    mov     ebx, 1
.clean:
    mov     word [col_index + COL_INDEX * 2 - 2], 1     ; the helper looks at the whole table: it sees the last word
    call    index_empty
    mov     word [col_index + COL_INDEX * 2 - 2], 0
    test    eax, eax
    jz      .sees
    mov     ebx, 1
.sees:
    mov     edi, [sv_seed]
    call    worldgen_set_seed
    mov     [settings + SETTINGS.render_dist], r12d
    mov     eax, ebx
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- a guest that is not in the host's world yet --------------------------------------------------------------

; count_col_req() -> eax how many COL_REQ records the capture seam holds (a record: slot u8, type u8, len u16,
; payload[len])
count_col_req:
    lea     rax, [gj_cap]
    mov     ecx, [net_captured]
    lea     rdx, [rax + rcx]            ; the end of what was recorded
    xor     esi, esi
.next:
    cmp     rax, rdx
    jae     .done
    cmp     byte [rax + 1], MT_COL_REQ
    jne     .skip
    inc     esi
.skip:
    movzx   ecx, word [rax + 2]
    lea     rax, [rax + rcx + 4]
    jmp     .next
.done:
    mov     eax, esi
    ret

; forget_area(edi ccx): net_column_forget for the 7 x 7 columns around column (ccx, 0) - the requests asked of the
; host for them go
forget_area:
    push    rbx
    push    r12
    push    r13
    mov     r12d, edi
    xor     ebx, ebx
.next:
    mov     eax, ebx
    xor     edx, edx
    mov     ecx, 7
    div     ecx                         ; eax = the row, edx = the column
    lea     esi, [rax - 3]
    lea     edi, [rdx + r12 - 3]
    call    net_column_forget
    inc     ebx
    cmp     ebx, 49
    jb      .next
    pop     r13
    pop     r12
    pop     rbx
    ret

; a guest asks the host for its columns only once it is in the host's world: the role is set when the host accepts
; it, net_in_world only at game_join, and in between the title panorama streams - asking the host then floods it
; with requests whose answers the guest drops. So with the role GUEST and net_in_world 0 the 7 x 7 columns
; around the player are generated locally and no COL_REQ is sent; with net_in_world 1 the columns around a
; player who walked far away are all asked of the host (49 COL_REQ, the one he stands in first) and none is
; generated before the host answers. -> eax 0 = pass
test_stream_guest_local_until_joined:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    xor     ebx, ebx                    ; 0 = pass
    movzx   r13d, byte [net_role]
    movzx   r14d, byte [net_in_world]
    mov     eax, [net_colv_pending]
    mov     [gj_pend], eax
    mov     eax, [gen_seed]
    mov     [sv_seed], eax
    mov     r12d, [settings + SETTINGS.render_dist]
    mov     dword [settings + SETTINGS.render_dist], 2
    call    world_clear
    mov     edi, 42
    xor     esi, esi
    call    stream_begin                ; no world directory: nothing is read back
    lea     rdi, [gj_cap]
    mov     esi, GJ_CAP
    call    net_capture                 ; nothing is sent from here on
    mov     byte [net_role], NET_ROLE_GUEST
    mov     byte [net_in_world], 0
    mov     edi, 8
    mov     esi, 8
    call    pump                        ; (a) the columns around the player are generated locally ...
    test    eax, eax
    jnz     .bad
    call    count_col_req
    test    eax, eax
    jnz     .bad                        ;     and the host is asked about none of them
    mov     eax, [net_colv_pending]
    cmp     eax, [gj_pend]
    jne     .bad
    lea     rdi, [gj_cap]               ; (b) in the world: the count of what is recorded starts again
    mov     esi, GJ_CAP
    call    net_capture
    mov     byte [net_in_world], 1
    mov     edi, 3000                   ;     the player is 3000 cells away: the columns around column (187, 0) are unknown
    mov     esi, 8
    movss   xmm0, [k_one]
    call    stream_update
    call    count_col_req
    cmp     eax, 49
    jne     .bad                        ;     each one is asked of the host ...
    cmp     byte [gj_cap + 1], MT_COL_REQ
    jne     .bad
    cmp     dword [gj_cap + 4], 187
    jne     .bad
    cmp     dword [gj_cap + 8], 0
    jne     .bad                        ;     the one the player stands in first
    mov     edi, 187
    xor     esi, esi
    mov     edx, 3
    call    count_loaded
    test    eax, eax
    jnz     .bad                        ;     and none is generated before the host answers
    jmp     .done
.bad:
    mov     ebx, 1
.done:
    xor     edi, edi                    ; the requests of both areas are forgotten again (a failing run too)
    call    forget_area
    mov     edi, 187
    call    forget_area
    mov     eax, [net_colv_pending]
    cmp     eax, [gj_pend]
    je      .clean
    mov     ebx, 1
.clean:
    xor     edi, edi
    xor     esi, esi
    call    net_capture                 ; the real network again
    mov     [net_role], r13b
    mov     [net_in_world], r14b
    xor     edi, edi
    call    stream_end
    mov     edi, [sv_seed]
    call    worldgen_set_seed
    mov     [settings + SETTINGS.render_dist], r12d
    mov     eax, ebx
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- block edits that wait for their column ----------------------------------------------------------------

; index_empty() -> eax 1 when no word of col_index (the whole table: COL_INDEX words) is set
index_empty:
    lea     rdi, [col_index]
    mov     ecx, COL_INDEX / 2          ; dwords
    xor     eax, eax
    repe    scasd
    sete    al
    movzx   eax, al
    ret

; edit_cols() -> eax how many columns net_edit_columns lists - the distinct columns of the block edits that wait
; in networld's queue, the oldest edit's first, at most PE_MAX - as (acx, acz) dword pairs in pe_cols
edit_cols:
    sub     rsp, 8
    lea     rdi, [pe_cols]
    mov     esi, PE_MAX
    call    net_edit_columns
    add     rsp, 8
    ret

; queue_edit(edi acx, esi lx) -> eax what nw_apply_edit makes of a BRICK at (acx * 16 + lx, 70, 8) - in column
; (acx, 0) - taken from guest slot 1 (0: the column is not loaded, the edit waits in the queue)
queue_edit:
    sub     rsp, 8
    shl     edi, 4
    add     edi, esi
    mov     esi, 70
    mov     edx, 8
    mov     ecx, BRICK
    mov     r8d, 1
    call    nw_apply_edit
    add     rsp, 8
    ret

; a hosting peer loads the column of every block edit that waits for it - the columns net_edit_columns lists. A
; guest's edit in a column nobody here loads (a rocket 100 blocks from every player) would wait in networld's
; queue and expire after 600 frames - and the guest's world would differ from the host's for good. With the local
; player in column 0 and no remote player: (a) an edit in column (200, 0) is queued and listed; stream_update loads
; and lights that column and keeps it: a block poked into it (not saved) is still there after 40 updates, and so
; is the edit; (b) the replay applies it; (c) nothing waits for the column any more, so the next updates unload
; it - saved with the edit; (d) an edit that expires in the queue (601 replays, no stream) brings its column in
; no more; (e) three edits, two of them in column 100, are listed as 2 columns, the oldest first; edits in 34
; columns list PE_MAX, the oldest first, and are all applied in the end, each column saved with its edits.
; -> eax 0 = pass
test_stream_pending_edit_columns:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    xor     ebx, ebx                    ; 0 = pass
    movzx   r13d, byte [net_role]
    mov     eax, [gen_seed]
    mov     [sv_seed], eax
    mov     r12d, [settings + SETTINGS.render_dist]
    mov     dword [settings + SETTINGS.render_dist], 2
    mov     byte [net_role], NET_ROLE_OFF
    call    net_edits_replay            ; offline the queue is emptied: no edit of an earlier test waits
    lea     rdi, [dir_pending]
    call    dir_remove_tree             ; (the leftovers of an aborted run)
    call    world_clear
    mov     edi, 42
    lea     rsi, [dir_pending]
    call    stream_begin                ; a world directory: an unloaded column is saved
    lea     rdi, [gj_cap]
    mov     esi, GJ_CAP
    call    net_capture                 ; what the host relays when it applies an edit goes nowhere
    mov     edi, 8
    mov     esi, 8
    call    pump                        ; the local 7 x 7 columns
    test    eax, eax
    jnz     .bad
    mov     byte [net_role], NET_ROLE_HOST
    call    edit_cols
    test    eax, eax
    jnz     .bad                        ; nothing waits yet
    mov     edi, 200                    ; (a) an edit far from every player: it waits ...
    mov     esi, 8
    call    queue_edit
    test    eax, eax
    jnz     .bad
    call    edit_cols
    cmp     eax, 1
    jne     .bad                        ;     and its column is listed
    cmp     dword [pe_cols], 200
    jne     .bad
    cmp     dword [pe_cols + 4], 0
    jne     .bad
    mov     edi, 8
    mov     esi, 8
    mov     edx, 3
    call    pump_n
    mov     edi, 200                    ;     the stream loads and lights it ...
    xor     esi, esi
    call    world_column
    test    rax, rax
    jz      .bad
    cmp     dword [rax + COLUMN.state], COL_LIT
    jne     .bad
    mov     edi, 3209                   ;     ... and keeps it: a block poked into it is still there after 40 updates
    mov     esi, 70
    mov     edx, 8
    mov     ecx, GLASS
    call    world_set_raw
    mov     edi, 8
    mov     esi, 8
    mov     edx, 40
    call    pump_n
    mov     edi, 3209
    mov     esi, 70
    mov     edx, 8
    call    world_get
    cmp     eax, GLASS
    jne     .bad
    call    edit_cols
    cmp     eax, 1
    jne     .bad                        ;     (nobody applied the edit)
    call    net_edits_replay            ; (b) the replay applies it
    call    edit_cols
    test    eax, eax
    jnz     .bad
    mov     edi, 3208
    mov     esi, 70
    mov     edx, 8
    call    world_get
    cmp     eax, BRICK
    jne     .bad
    mov     edi, 8                      ; (c) nothing waits any more: the column goes ...
    mov     esi, 8
    mov     edx, 3
    call    pump_n
    mov     edi, 200
    xor     esi, esi
    call    world_column
    test    rax, rax
    jnz     .bad
    mov     edi, 200                    ;     ... saved with the edit
    xor     esi, esi
    lea     rdx, [gb]
    call    region_read_column
    cmp     eax, 1
    jne     .bad
    cmp     byte [gb + GENBUF.blocks + (70 << 8) + (8 << 4) + 8], BRICK
    jne     .bad
    mov     edi, 300                    ; (d) an edit whose time runs out in the queue
    mov     esi, 8
    call    queue_edit
    test    eax, eax
    jnz     .bad
    call    edit_cols
    cmp     eax, 1
    jne     .bad
    mov     r14d, 601
.expire:
    call    net_edits_replay            ;     (no stream: its column is never loaded)
    dec     r14d
    jnz     .expire
    call    edit_cols
    test    eax, eax
    jnz     .bad
    mov     edi, 8                      ;     brings its column in no more
    mov     esi, 8
    mov     edx, 4
    call    pump_n
    mov     edi, 300
    xor     esi, esi
    call    world_column
    test    rax, rax
    jnz     .bad
    mov     edi, 100                    ; (e) edits in column 100 (two of them) and in column 101 ...
    mov     esi, 8
    call    queue_edit
    test    eax, eax
    jnz     .bad
    mov     edi, 101
    mov     esi, 8
    call    queue_edit
    test    eax, eax
    jnz     .bad
    mov     edi, 100
    mov     esi, 9
    call    queue_edit
    test    eax, eax
    jnz     .bad
    call    edit_cols
    cmp     eax, 2
    jne     .bad                        ;     ... list 2 columns, the oldest edit's first
    cmp     dword [pe_cols], 100
    jne     .bad
    cmp     dword [pe_cols + 4], 0
    jne     .bad
    cmp     dword [pe_cols + 8], 101
    jne     .bad
    cmp     dword [pe_cols + 12], 0
    jne     .bad
    mov     r14d, 2                     ;     and edits in 32 more columns
.many:
    lea     edi, [r14 + 100]
    mov     esi, 8
    call    queue_edit
    test    eax, eax
    jnz     .bad
    inc     r14d
    cmp     r14d, 34
    jb      .many
    call    edit_cols
    cmp     eax, PE_MAX
    jne     .bad                        ;     34 columns wait, PE_MAX of them are listed ...
    cmp     dword [pe_cols], 100
    jne     .bad
    cmp     dword [pe_cols + 8 * (PE_MAX - 1)], 100 + PE_MAX - 1
    jne     .bad                        ;     ... the oldest edits' columns
    mov     r14d, 600
.frames:
    call    net_edits_replay            ;     a frame: the replay, then the stream
    mov     edi, 8
    mov     esi, 8
    movss   xmm0, [k_one]
    call    stream_update
    call    edit_cols
    test    eax, eax
    jz      .applied
    dec     r14d
    jnz     .frames
    jmp     .bad                        ;     (not all of them within 600 frames)
.applied:
    mov     edi, 8                      ;     the last columns go
    mov     esi, 8
    mov     edx, 3
    call    pump_n
    xor     r14d, r14d
.saved:
    lea     edi, [r14 + 100]            ;     each of the 34 columns was saved with its edit
    xor     esi, esi
    lea     rdx, [gb]
    call    region_read_column
    cmp     eax, 1
    jne     .bad
    cmp     byte [gb + GENBUF.blocks + (70 << 8) + (8 << 4) + 8], BRICK
    jne     .bad
    test    r14d, r14d
    jnz     .saved_next
    cmp     byte [gb + GENBUF.blocks + (70 << 8) + (8 << 4) + 9], BRICK
    jne     .bad                        ;     (column 100 holds its second edit too)
.saved_next:
    inc     r14d
    cmp     r14d, 34
    jb      .saved
    jmp     .done
.bad:
    mov     ebx, 1
.done:
    mov     byte [net_role], NET_ROLE_OFF
    call    net_edits_replay            ; (a failing run leaves no edit waiting)
    xor     edi, edi
    xor     esi, esi
    call    net_capture                 ; the real network again
    xor     edi, edi
    call    stream_end
    call    index_empty                 ; every record went back
    cmp     eax, 1
    je      .clean
    mov     ebx, 1
.clean:
    xor     edi, edi
    call    region_set_dir
    lea     rdi, [dir_pending]
    call    dir_remove_tree
    mov     [net_role], r13b
    mov     edi, [sv_seed]
    call    worldgen_set_seed
    mov     [settings + SETTINGS.render_dist], r12d
    mov     eax, ebx
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
