; stream.asm - which columns exist around the player: loading, generating, installing, lighting and
; unloading, all driven by stream_update once per frame on the main thread.
;
; One generator thread (glibc pthreads) runs only gen_column, into one of GEN_SLOTS private GENBUFs. The
; main thread owns the column table, the pool, light, meshing, GL and every region read and write.
; Buffer states (GENBUF.state) change under gen_mutex: FREE -> REQ (main) -> BUSY -> DONE (worker) ->
; FREE (main). Without a worker (selftests, or pthread_create failed) stream_update generates inline.
; A column whose install does not fit (world_install: the container table or the pool is full) holds back
; only itself: it is tried again BACKOFF_FRAMES frames later and every other column carries on.
;
; Radii: R = settings.render_dist (2..16); columns within Chebyshev R + 1 of the centre column are
; loaded, columns beyond R + 2 are unloaded (saved first when modified or holding containers).
; Coordinates passed to stream_update / stream_area_ready are local cells (x, z).
%include "common.inc"
default rel

global stream_begin, stream_end, stream_update, stream_area_ready, stream_thread_start
global stream_thread_stop, stream_stats, stream_spiral, stream_spiral_n

extern settings
extern world_origin_x, world_origin_z, columns, chunk_pool_used
extern world_column, world_column_claim, world_install, world_install_err, world_unload
extern world_save_dirty, world_drop_all
extern region_dir, region_set_dir, region_has_column, region_read_column, region_write_column
extern region_flush_cache
extern light_column
extern worldgen_set_seed, gen_column, gen_biome
extern time_mono_ns, sys_print
extern pthread_create, pthread_join, pthread_mutex_lock, pthread_mutex_unlock
extern pthread_cond_wait, pthread_cond_signal, pthread_cond_broadcast

%define SPIRAL_R        18              ; offsets -18..18: 37 x 37 = 1369 entries
%define SPIRAL_MAX      (37 * 37)
%define BACKOFF_FRAMES  60              ; frames until a column whose install did not fit is tried again
%define MAX_READS       4               ; region columns decoded per stream_update
%define MAX_INLINE      4               ; columns generated inline per stream_update
%define MAX_LIGHT       6               ; columns lit per stream_update

section .rodata
d_1e9:          dq 1.0e9
s_no_thread:    db "generator thread unavailable; generating on the main thread", 10, 0
s_pool_full:    db "chunk pool full", 10, 0
s_conts_full:   db "container table full", 10, 0

section .bss
alignb 64
gen_bufs:       resb GEN_SLOTS * GENBUF_size
load_buf:       resb GENBUF_size        ; the main thread's buffer for region reads
gen_mutex:      resb 64                 ; all zero = PTHREAD_MUTEX_INITIALIZER
gen_cond:       resb 64                 ; all zero = PTHREAD_COND_INITIALIZER
gen_tid:        resq 1
gen_quit:       resd 1
gen_threaded:   resd 1                  ; 1 while the worker runs
stream_session: resd 1
stream_frame:   resd 1                  ; stream_update calls so far
msg_done:       resd 1                  ; the "full" message of this session was printed
stream_spiral_n: resd 1
stream_spiral:  resd SPIRAL_MAX * 2     ; (dx, dz) pairs, nearest first
fail_until:     resd MAX_COLUMNS        ; by column slot: the stream_frame from which a failed install may be retried

section .text

; ---- the spiral -------------------------------------------------------------------------------------------

; sp_ensure(): build stream_spiral once - every (dx, dz) with |dx|, |dz| <= 18 sorted by dx^2 + dz^2,
; then dz, then dx. Clobbers rax, rcx, rdx, rsi, r8, r9.
sp_ensure:
    cmp     dword [stream_spiral_n], 0
    jne     .ret
    xor     r8d, r8d                    ; entries written
    xor     ecx, ecx                    ; the squared distance being emitted
.d2:
    mov     esi, -SPIRAL_R              ; dz
.dz:
    mov     edx, -SPIRAL_R              ; dx
.dx:
    mov     eax, esi
    imul    eax, eax
    mov     r9d, edx
    imul    r9d, r9d
    add     eax, r9d
    cmp     eax, ecx
    jne     .next
    mov     [stream_spiral + r8*8], edx
    mov     [stream_spiral + r8*8 + 4], esi
    inc     r8d
.next:
    inc     edx
    cmp     edx, SPIRAL_R
    jle     .dx
    inc     esi
    cmp     esi, SPIRAL_R
    jle     .dz
    inc     ecx
    cmp     ecx, 2 * SPIRAL_R * SPIRAL_R
    jle     .d2
    mov     [stream_spiral_n], r8d
.ret:
    ret

; ---- generator buffers -----------------------------------------------------------------------------------------

; buf_get(rdi GENBUF*) -> eax its state (read under the lock while a worker runs)
buf_get:
    push    rbx
    sub     rsp, 16
    mov     rbx, rdi
    cmp     dword [gen_threaded], 0
    je      .plain
    lea     rdi, [gen_mutex]
    call    pthread_mutex_lock
    mov     eax, [rbx + GENBUF.state]
    mov     [rsp], eax
    lea     rdi, [gen_mutex]
    call    pthread_mutex_unlock
    mov     eax, [rsp]
    jmp     .ret
.plain:
    mov     eax, [rbx + GENBUF.state]
.ret:
    add     rsp, 16
    pop     rbx
    ret

; buf_set(rdi GENBUF*, esi state)
buf_set:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12d, esi
    cmp     dword [gen_threaded], 0
    je      .plain
    lea     rdi, [gen_mutex]
    call    pthread_mutex_lock
    mov     [rbx + GENBUF.state], r12d
    lea     rdi, [gen_mutex]
    call    pthread_mutex_unlock
    jmp     .ret
.plain:
    mov     [rbx + GENBUF.state], r12d
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; request_worker(edi acx, esi acz) -> eax 1 when a free buffer took the request (and the worker was
; signalled), 0 when all buffers are busy.
request_worker:
    push    rbx
    push    r12
    push    r13
    mov     r12d, edi
    mov     r13d, esi
    lea     rdi, [gen_mutex]
    call    pthread_mutex_lock
    lea     rbx, [gen_bufs]
    mov     ecx, GEN_SLOTS
.find:
    cmp     dword [rbx + GENBUF.state], GB_FREE
    je      .got
    add     rbx, GENBUF_size
    dec     ecx
    jnz     .find
    lea     rdi, [gen_mutex]
    call    pthread_mutex_unlock
    xor     eax, eax
    jmp     .ret
.got:
    mov     [rbx + GENBUF.cx], r12d
    mov     [rbx + GENBUF.cz], r13d
    mov     eax, [stream_session]
    mov     [rbx + GENBUF.session], eax
    mov     dword [rbx + GENBUF.state], GB_REQ
    lea     rdi, [gen_mutex]
    call    pthread_mutex_unlock
    lea     rdi, [gen_cond]
    call    pthread_cond_signal
    mov     eax, 1
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; gen_worker(void*) -> 0: the generator thread. Takes the lowest-index requested buffer, runs gen_column
; on it without the lock, marks it done and wakes whoever waits on gen_cond (stream_begin).
gen_worker:
    push    rbx
    push    r12
    push    r13
.loop:
    lea     rdi, [gen_mutex]
    call    pthread_mutex_lock
.scan:
    cmp     dword [gen_quit], 0
    jne     .quit
    lea     r12, [gen_bufs]
    mov     ebx, GEN_SLOTS
.find:
    cmp     dword [r12 + GENBUF.state], GB_REQ
    je      .got
    add     r12, GENBUF_size
    dec     ebx
    jnz     .find
    lea     rdi, [gen_cond]
    lea     rsi, [gen_mutex]
    call    pthread_cond_wait
    jmp     .scan
.got:
    mov     dword [r12 + GENBUF.state], GB_BUSY
    lea     rdi, [gen_mutex]
    call    pthread_mutex_unlock
    mov     rdi, r12
    call    gen_column
    lea     rdi, [gen_mutex]
    call    pthread_mutex_lock
    mov     dword [r12 + GENBUF.state], GB_DONE
    lea     rdi, [gen_cond]
    call    pthread_cond_broadcast
    lea     rdi, [gen_mutex]
    call    pthread_mutex_unlock
    jmp     .loop
.quit:
    lea     rdi, [gen_mutex]
    call    pthread_mutex_unlock
    xor     eax, eax
    pop     r13
    pop     r12
    pop     rbx
    ret

; stream_thread_start(): start the generator thread (app init, after GL init). When pthread_create
; fails, say so on stderr and keep generating inline.
stream_thread_start:
    sub     rsp, 8
    cmp     dword [gen_threaded], 0
    jne     .ret
    mov     dword [gen_quit], 0
    lea     rdi, [gen_tid]
    xor     esi, esi
    lea     rdx, [gen_worker]
    xor     ecx, ecx
    call    pthread_create
    test    eax, eax
    jnz     .fail
    mov     dword [gen_threaded], 1
    jmp     .ret
.fail:
    mov     edi, 2
    lea     rsi, [s_no_thread]
    call    sys_print
.ret:
    add     rsp, 8
    ret

; stream_thread_stop() -> eax pthread_join's result (0), also 0 without a worker.
stream_thread_stop:
    push    rbx
    cmp     dword [gen_threaded], 0
    je      .none
    lea     rdi, [gen_mutex]
    call    pthread_mutex_lock
    mov     dword [gen_quit], 1
    lea     rdi, [gen_cond]
    call    pthread_cond_broadcast
    lea     rdi, [gen_mutex]
    call    pthread_mutex_unlock
    mov     rdi, [gen_tid]
    xor     esi, esi
    call    pthread_join
    mov     ebx, eax
    mov     dword [gen_threaded], 0
    mov     eax, ebx
    pop     rbx
    ret
.none:
    xor     eax, eax
    pop     rbx
    ret

; ---- sessions -------------------------------------------------------------------------------------------------------

; stream_begin(edi seed, rsi world_dir or 0): a new session - the worker is quiesced (requests that
; did not start are cancelled, a running generation is waited for), every column goes unsaved, the
; generator gets the seed and the region directory is set (0: no saving).
stream_begin:
    push    rbx
    push    r12
    push    r13
    mov     ebx, edi
    mov     r12, rsi
    call    sp_ensure
    lea     r13, [gen_bufs]
    cmp     dword [gen_threaded], 0
    je      .free_all
    lea     rdi, [gen_mutex]
    call    pthread_mutex_lock
    mov     ecx, GEN_SLOTS
    mov     rax, r13
.cancel:
    cmp     dword [rax + GENBUF.state], GB_REQ
    jne     .c_next
    mov     dword [rax + GENBUF.state], GB_FREE
.c_next:
    add     rax, GENBUF_size
    dec     ecx
    jnz     .cancel
.wait:
    mov     ecx, GEN_SLOTS
    mov     rax, r13
.busy:
    cmp     dword [rax + GENBUF.state], GB_BUSY
    je      .sleep
    add     rax, GENBUF_size
    dec     ecx
    jnz     .busy
    mov     ecx, GEN_SLOTS              ; nobody works on a buffer: all of them are free again
    mov     rax, r13
.clear:
    mov     dword [rax + GENBUF.state], GB_FREE
    add     rax, GENBUF_size
    dec     ecx
    jnz     .clear
    lea     rdi, [gen_mutex]
    call    pthread_mutex_unlock
    jmp     .quiet
.sleep:
    lea     rdi, [gen_cond]
    lea     rsi, [gen_mutex]
    call    pthread_cond_wait
    jmp     .wait
.free_all:
    mov     ecx, GEN_SLOTS
    mov     rax, r13
.f:
    mov     dword [rax + GENBUF.state], GB_FREE
    add     rax, GENBUF_size
    dec     ecx
    jnz     .f
.quiet:
    call    world_drop_all
    mov     edi, ebx
    call    worldgen_set_seed
    inc     dword [stream_session]
    lea     rdi, [fail_until]           ; no column is backing off in the new session
    xor     eax, eax
    mov     ecx, MAX_COLUMNS
    rep     stosd
    mov     dword [msg_done], 0
    mov     rdi, r12
    call    region_set_dir
    pop     r13
    pop     r12
    pop     rbx
    ret

; stream_end(edi save): the session is over. With save, every modified or container-holding lit column is
; written first (world_save_dirty); then every column is unloaded and the region cache forgotten.
stream_end:
    push    rbx
    push    r12
    push    r13
    mov     r13d, edi
    test    r13d, r13d
    jz      .unload
    cmp     byte [region_dir], 0
    je      .unload
    lea     rdi, [region_dir]
    call    world_save_dirty
.unload:
    lea     rbx, [columns]
    mov     r12d, MAX_COLUMNS
.col:
    mov     eax, [rbx + COLUMN.state]
    test    eax, eax
    jz      .next
    cmp     eax, COL_PENDING
    jne     .real
    mov     dword [rbx + COLUMN.state], COL_FREE
    jmp     .next
.real:
    mov     rdi, rbx
    call    world_unload
.next:
    add     rbx, COLUMN_size
    dec     r12d
    jnz     .col
    call    region_flush_cache
    inc     dword [stream_session]
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- one frame -----------------------------------------------------------------------------------------------------------

; install_waiting(edi acx, esi acz) -> eax 1 while an install of that column that did not fit is still
; backing off, else 0. The frame counter is compared as a signed difference, so it may wrap. Clobbers ecx.
install_waiting:
    mov     eax, esi
    and     eax, 63
    shl     eax, 6
    mov     ecx, edi
    and     ecx, 63
    or      eax, ecx                    ; the column's slot
    lea     rcx, [fail_until]
    mov     eax, [rcx + rax*4]
    sub     eax, [stream_frame]
    test    eax, eax
    jle     .no
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; install_failed(edi acx, esi acz): world_install did not take that column (the pool or the container
; table is full). It is not tried again for BACKOFF_FRAMES frames - nothing else waits - and the reason is
; printed once per session. Clobbers rax, rcx, rdx, rsi, rdi.
install_failed:
    sub     rsp, 8
    mov     eax, esi
    and     eax, 63
    shl     eax, 6
    mov     ecx, edi
    and     ecx, 63
    or      eax, ecx                    ; the column's slot
    mov     ecx, [stream_frame]
    add     ecx, BACKOFF_FRAMES
    lea     rdx, [fail_until]
    mov     [rdx + rax*4], ecx
    cmp     dword [msg_done], 0
    jne     .ret
    mov     dword [msg_done], 1
    mov     edi, 2
    lea     rsi, [s_pool_full]
    cmp     dword [world_install_err], 2
    jne     .print
    lea     rsi, [s_conts_full]
.print:
    call    sys_print
.ret:
    add     rsp, 8
    ret

; install_from_region(edi acx, esi acz) -> eax 1 installed from its region file, 0 the file has no readable
; blob for it (generate instead), -1 the install did not fit (the slot is free again).
install_from_region:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12d, edi
    mov     r13d, esi
    lea     rdx, [load_buf]
    call    region_read_column
    test    eax, eax
    jz      .ret
    xor     r14d, r14d                  ; lz: the biome map is not stored
.bz:
    xor     r15d, r15d                  ; lx
.bx:
    mov     edi, r12d
    shl     edi, 4
    add     edi, r15d
    mov     esi, r13d
    shl     esi, 4
    add     esi, r14d
    call    gen_biome
    mov     ecx, r14d
    shl     ecx, 4
    add     ecx, r15d
    mov     [load_buf + GENBUF.biome + rcx], al
    inc     r15d
    cmp     r15d, 16
    jb      .bx
    inc     r14d
    cmp     r14d, 16
    jb      .bz
    mov     edi, r12d
    mov     esi, r13d
    call    world_column_claim
    lea     rdi, [load_buf]
    call    world_install
    test    eax, eax
    jns     .done
    mov     edi, r12d
    mov     esi, r13d
    call    world_column
    test    rax, rax
    jz      .failed
    mov     dword [rax + COLUMN.state], COL_FREE
.failed:
    mov     eax, -1
    jmp     .ret
.done:
    mov     eax, 1
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; generate_inline(edi acx, esi acz) -> eax 0 installed, -1 did not fit: gen_column on the first buffer
; on this thread (no worker), then install.
generate_inline:
    push    rbx
    push    r12
    push    r13
    mov     r12d, edi
    mov     r13d, esi
    lea     rbx, [gen_bufs]
    mov     [rbx + GENBUF.cx], edi
    mov     [rbx + GENBUF.cz], esi
    mov     rdi, rbx
    call    gen_column
    mov     edi, r12d
    mov     esi, r13d
    call    world_column_claim
    mov     rdi, rbx
    call    world_install
    test    eax, eax
    jns     .ret
    mov     edi, r12d
    mov     esi, r13d
    call    world_column
    test    rax, rax
    jz      .failed
    mov     dword [rax + COLUMN.state], COL_FREE
.failed:
    mov     eax, -1
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; stream_update(edi x, esi z, xmm0 budget_s): one frame around the local cell (x, z).
; 1. unload the columns beyond R + 2, 2. install the generator's finished columns, 3. start the missing
; columns within R + 1 nearest first (region file, worker or inline), 4. light the columns that hold
; blocks. Steps 3 and 4 stop when budget_s seconds have passed; 1 and 2 always run. A column whose install
; did not fit (world_install -1) is passed over for BACKOFF_FRAMES frames - its buffer stays DONE, or its
; slot goes free again - and every other column carries on.
stream_update:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 56                     ; [0] deadline, [8] ccx, [12] ccz, [16] L, [20] K, [24] reads,
                                        ; [28] inline, [32] spiral index, [36] lit
    mov     r12d, edi
    mov     r13d, esi
    cvtss2sd xmm0, xmm0
    mulsd   xmm0, [d_1e9]
    cvttsd2si rbx, xmm0                 ; the budget in ns
    call    sp_ensure
    call    time_mono_ns
    add     rax, rbx
    mov     [rsp], rax
    add     r12d, [world_origin_x]
    sar     r12d, 4                     ; the centre column
    add     r13d, [world_origin_z]
    sar     r13d, 4
    mov     [rsp + 8], r12d
    mov     [rsp + 12], r13d
    mov     eax, [settings + SETTINGS.render_dist]
    cmp     eax, 2
    jge     .r_lo
    mov     eax, 2
.r_lo:
    cmp     eax, MAX_RENDER_DIST
    jle     .r_hi
    mov     eax, MAX_RENDER_DIST
.r_hi:
    lea     ecx, [rax + 1]
    mov     [rsp + 16], ecx             ; L = R + 1
    add     eax, 2
    mov     [rsp + 20], eax             ; K = R + 2
    inc     dword [stream_frame]
.unload:
    lea     r14, [columns]
    xor     r15d, r15d                  ; slot
.u_loop:
    mov     eax, [r14 + COLUMN.state]
    test    eax, eax
    jz      .u_next
    mov     ecx, [r14 + COLUMN.cx]
    sub     ecx, r12d
    mov     edx, ecx
    sar     edx, 31
    xor     ecx, edx
    sub     ecx, edx                    ; |dx|
    mov     esi, [r14 + COLUMN.cz]
    sub     esi, r13d
    mov     edx, esi
    sar     edx, 31
    xor     esi, edx
    sub     esi, edx                    ; |dz|
    cmp     ecx, esi
    cmovl   ecx, esi
    cmp     ecx, [rsp + 20]
    jle     .u_next                     ; within the keep radius
    cmp     eax, COL_PENDING
    je      .u_pending
    test    dword [r14 + COLUMN.flags], CF_MODIFIED | CF_CONTS
    jz      .u_drop
    cmp     byte [region_dir], 0
    je      .u_drop
    mov     rdi, r14
    call    region_write_column         ; (a failed write loses the column's edits: nothing to retry with)
.u_drop:
    mov     rdi, r14
    call    world_unload
    jmp     .u_next
.u_pending:
    mov     dword [r14 + COLUMN.state], COL_FREE    ; a stale worker result is dropped at install
.u_next:
    add     r14, COLUMN_size
    inc     r15d
    cmp     r15d, MAX_COLUMNS
    jb      .u_loop
    xor     r14d, r14d                  ; buffer index
.collect:
    cmp     r14d, GEN_SLOTS
    jae     .dispatch
    mov     eax, r14d
    imul    eax, eax, GENBUF_size
    lea     r15, [gen_bufs]
    add     r15, rax
    mov     rdi, r15
    call    buf_get
    cmp     eax, GB_DONE
    jne     .c_next
    mov     eax, [r15 + GENBUF.session]
    cmp     eax, [stream_session]
    jne     .c_free                     ; a result of an old session
    mov     edi, [r15 + GENBUF.cx]
    mov     esi, [r15 + GENBUF.cz]
    call    install_waiting
    test    eax, eax
    jnz     .c_next                     ; its install did not fit lately: later; the other buffers go on
    mov     rdi, r15
    call    world_install
    test    eax, eax
    jns     .c_free
    mov     edi, [r15 + GENBUF.cx]
    mov     esi, [r15 + GENBUF.cz]
    call    install_failed              ; the buffer stays DONE: it is tried again when the backoff is over
    jmp     .c_next
.c_free:
    mov     rdi, r15
    mov     esi, GB_FREE
    call    buf_set
.c_next:
    inc     r14d
    jmp     .collect
.dispatch:
    mov     dword [rsp + 24], 0
    mov     dword [rsp + 28], 0
    mov     dword [rsp + 32], 0
.d_loop:
    mov     eax, [rsp + 32]
    cmp     eax, [stream_spiral_n]
    jae     .light
    inc     dword [rsp + 32]
    mov     ecx, [stream_spiral + rax*8 + 4]    ; dz
    mov     eax, [stream_spiral + rax*8]        ; dx
    mov     r9d, [rsp + 16]
    lea     r8d, [rax + r9]
    lea     r10d, [rcx + r9]
    add     r9d, r9d
    cmp     r8d, r9d
    ja      .d_loop                     ; beyond the load radius
    cmp     r10d, r9d
    ja      .d_loop
    add     eax, [rsp + 8]
    add     ecx, [rsp + 12]
    mov     r14d, eax                   ; acx
    mov     r15d, ecx                   ; acz
    mov     edx, ecx
    and     edx, 63
    shl     edx, 6
    and     eax, 63
    or      edx, eax
    imul    edx, edx, COLUMN_size
    lea     rax, [columns]
    cmp     dword [rax + rdx + COLUMN.state], COL_FREE
    jne     .d_loop                     ; loaded or on its way
    mov     edi, r14d
    mov     esi, r15d
    call    install_waiting
    test    eax, eax
    jnz     .d_loop                     ; its install did not fit lately: the next column
    mov     edi, r14d
    mov     esi, r15d
    call    region_has_column
    test    eax, eax
    jz      .generate
    cmp     dword [rsp + 24], MAX_READS
    jae     .d_loop                     ; this one waits for the next frame
    inc     dword [rsp + 24]
    mov     edi, r14d
    mov     esi, r15d
    call    install_from_region
    test    eax, eax
    jz      .generate                   ; unreadable: regenerate it
    jns     .d_check
    mov     edi, r14d
    mov     esi, r15d
    call    install_failed              ; this column backs off; the ones after it go on
    jmp     .d_check
.generate:
    cmp     dword [gen_threaded], 0
    je      .inline
    mov     edi, r14d
    mov     esi, r15d
    call    request_worker
    test    eax, eax
    jz      .light                      ; every buffer is busy: stop for this frame
    mov     edi, r14d
    mov     esi, r15d
    call    world_column_claim
    jmp     .d_check
.inline:
    cmp     dword [rsp + 28], MAX_INLINE
    jae     .light
    inc     dword [rsp + 28]
    mov     edi, r14d
    mov     esi, r15d
    call    generate_inline
    test    eax, eax
    jns     .d_check
    mov     edi, r14d
    mov     esi, r15d
    call    install_failed
.d_check:
    call    time_mono_ns
    cmp     rax, [rsp]
    jb      .d_loop
.light:
    mov     dword [rsp + 32], 0
    mov     dword [rsp + 36], 0
.l_loop:
    mov     eax, [rsp + 32]
    cmp     eax, [stream_spiral_n]
    jae     .done
    cmp     dword [rsp + 36], MAX_LIGHT
    jae     .done
    inc     dword [rsp + 32]
    mov     esi, [stream_spiral + rax*8 + 4]    ; dz
    mov     edi, [stream_spiral + rax*8]        ; dx
    mov     r9d, [rsp + 16]
    lea     r8d, [rdi + r9]
    lea     r10d, [rsi + r9]
    add     r9d, r9d
    cmp     r8d, r9d
    ja      .l_loop
    cmp     r10d, r9d
    ja      .l_loop
    add     edi, [rsp + 8]
    add     esi, [rsp + 12]
    call    world_column
    test    rax, rax
    jz      .l_loop
    cmp     dword [rax + COLUMN.state], COL_BLOCKS
    jne     .l_loop
    mov     rdi, rax
    call    light_column
    inc     dword [rsp + 36]
    call    time_mono_ns
    cmp     rax, [rsp]
    jb      .l_loop
.done:
    add     rsp, 56
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; stream_area_ready(edi x, esi z, edx r) -> eax 1 when every column within Chebyshev r of the column
; holding the local cell (x, z) is COL_LIT and fully meshed (dirty == 0).
stream_area_ready:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r15d, edx                   ; r
    add     edi, [world_origin_x]
    sar     edi, 4
    mov     r12d, edi                   ; the centre column
    add     esi, [world_origin_z]
    sar     esi, 4
    mov     r13d, esi
    mov     r14d, r15d
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
    cmp     dword [rax + COLUMN.dirty], 0
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

; stream_stats(rdi out dd[4]): columns loaded (any state but free), pending, lit, chunks in the pool.
stream_stats:
    lea     rsi, [columns]
    xor     r8d, r8d                    ; loaded
    xor     r9d, r9d                    ; pending
    xor     r10d, r10d                  ; lit
    mov     ecx, MAX_COLUMNS
.col:
    mov     eax, [rsi + COLUMN.state]
    test    eax, eax
    jz      .next
    inc     r8d
    cmp     eax, COL_PENDING
    jne     .lit
    inc     r9d
.lit:
    cmp     eax, COL_LIT
    jne     .next
    inc     r10d
.next:
    add     rsi, COLUMN_size
    dec     ecx
    jnz     .col
    mov     [rdi], r8d
    mov     [rdi + 4], r9d
    mov     [rdi + 8], r10d
    mov     eax, [chunk_pool_used]
    mov     [rdi + 12], eax
    ret
