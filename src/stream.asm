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
; Radii: R = stream_rdist() (settings.render_dist clamped to 2..MAX_RENDER_DIST, capped by net_rdist_cap while hosting);
; columns within Chebyshev R + 1 of the centre column are loaded, columns beyond R + 2 are unloaded (saved
; first when modified or holding containers). A hosting peer also loads the columns within MP_SIM_R + 1 of
; every remote player's column (net_stream_centres) and keeps those within MP_SIM_R + 2; and it loads, lights
; and keeps the column of every block edit that waits in networld's queue (net_edit_columns) - an edit of a
; guest in a column nobody here loads would expire there and be lost for good - until the edit is applied. A
; guest asks the host for each column it needs (net_column_verdict): it generates a pristine one itself and
; installs the host's blob for an edited one; it never reads or writes region files.
; Coordinates passed to stream_update / stream_area_ready are local cells (x, z).
%include "common.inc"
default rel

global stream_begin, stream_end, stream_update, stream_area_ready, stream_thread_start
global stream_thread_stop, stream_stats, stream_spiral, stream_spiral_n, stream_rdist, stream_try_column
global gen_bufs, install_waiting, stream_frame  ; read by test_stream's buffer-pinning check
global stream_ccx, stream_ccz                   ; read by render.asm

extern settings
extern world_origin_x, world_origin_z, columns, chunk_pool_used
extern world_column, world_column_claim, world_column_release, world_install, world_install_err, world_unload
extern world_save_dirty, world_drop_all
extern region_dir, region_set_dir, region_has_column, region_read_column, region_write_column
extern region_flush_cache
extern light_column
extern worldgen_set_seed, gen_column, gen_biome
extern time_mono_ns, sys_print
extern pthread_create, pthread_join, pthread_mutex_lock, pthread_mutex_unlock
extern pthread_cond_wait, pthread_cond_signal, pthread_cond_broadcast
extern net_role, net_in_world, net_rdist_cap, net_stream_centres, net_edit_columns, net_column_verdict, net_column_take, net_column_forget

%define SPIRAL_R        (MAX_RENDER_DIST + 2)   ; offsets -SPIRAL_R..SPIRAL_R: the keep radius of the largest R
%define SPIRAL_MAX      ((2 * SPIRAL_R + 1) * (2 * SPIRAL_R + 1))
%define BACKOFF_FRAMES  60              ; frames until a column whose install did not fit is tried again
%define MAX_READS       4               ; region columns decoded per stream_update
%define MAX_INLINE      4               ; columns generated inline per stream_update
%define MAX_LIGHT       6               ; columns lit per stream_update
%define FAIL_MAX        64              ; columns backing off at once (fail_list)
%define MAX_EDIT_COLS   32              ; columns kept for waiting block edits at once (the max passed to net_edit_columns)

section .rodata
d_1e9:          dq 1.0e9
s_no_thread:    db "generator thread unavailable; generating on the main thread", 10, 0
s_pool_full:    db "chunk pool full", 10, 0
s_conts_full:   db "container table full", 10, 0
s_cols_full:    db "column table full", 10, 0

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
fail_n:         resd 1                  ; entries of fail_list in use
fail_list:      resd FAIL_MAX * 3       ; {acx, acz, until}: a column whose install did not fit, and the stream_frame from which it may be retried
alignb 8
su_deadline:    resq 1                  ; stream_update: the time_mono_ns() value its steps 3 and 4 stop at
su_reads:       resd 1                  ; columns read from a region file or taken from the host so far this call
su_inline:      resd 1                  ; columns generated inline so far
su_lit:         resd 1                  ; columns lit so far
su_nex:         resd 1                  ; remote players' columns this call (a hosting peer)
su_ex:          resd 2 * (NET_MAX_PEERS - 1)    ; their (acx, acz) pairs
su_ned:         resd 1                  ; columns with a block edit waiting for them (a hosting peer) ...
su_ed:          resd 2 * MAX_EDIT_COLS  ; ... their (acx, acz), the oldest edit's column first
stream_ccx:     resd 1                  ; the centre column of the last stream_update (absolute chunk coordinates):
stream_ccz:     resd 1                  ; render.asm measures the columns it never meshes from it

section .text

; ---- the spiral -------------------------------------------------------------------------------------------

; sp_ensure(): build stream_spiral once - every (dx, dz) with |dx|, |dz| <= SPIRAL_R sorted by dx^2 + dz^2,
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
    mov     dword [fail_n], 0           ; no column is backing off in the new session
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
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .drop
    mov     edi, [rbx + COLUMN.cx]      ; what the host sent for the column is not wanted any more
    mov     esi, [rbx + COLUMN.cz]
    call    net_column_forget
    mov     eax, [rbx + COLUMN.state]
.drop:
    cmp     eax, COL_PENDING
    jne     .real
    mov     rdi, rbx
    call    world_column_release
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
; backing off, else 0. The frame counter is compared as a signed difference, so it may wrap.
; Clobbers ecx, rdx.
install_waiting:
    mov     ecx, [fail_n]
    lea     rdx, [fail_list]
.scan:
    test    ecx, ecx
    jz      .no
    dec     ecx
    lea     eax, [rcx + rcx*2]          ; the entry's first dword
    cmp     [rdx + rax*4], edi
    jne     .scan
    cmp     [rdx + rax*4 + 4], esi
    jne     .scan
    mov     eax, [rdx + rax*4 + 8]
    sub     eax, [stream_frame]
    test    eax, eax
    jle     .no
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; install_failed(edi acx, esi acz): the column did not install (the pool, the container table or the column
; table is full). It is not tried again for BACKOFF_FRAMES frames - nothing else waits - and the reason is
; printed once per session. fail_list holds FAIL_MAX columns: the entry of that column is overwritten, else
; a new one is added, else the entry that expires first is replaced.
; Clobbers rax, rcx, rdx, rsi, rdi, r8-r11.
install_failed:
    sub     rsp, 8
    mov     r8d, [stream_frame]
    add     r8d, BACKOFF_FRAMES         ; until
    lea     rdx, [fail_list]
    xor     ecx, ecx
.scan:
    cmp     ecx, [fail_n]
    jae     .new
    lea     eax, [rcx + rcx*2]
    cmp     [rdx + rax*4], edi
    jne     .next
    cmp     [rdx + rax*4 + 4], esi
    je      .write
.next:
    inc     ecx
    jmp     .scan
.new:
    cmp     dword [fail_n], FAIL_MAX
    jae     .oldest
    mov     eax, [fail_n]
    lea     eax, [rax + rax*2]
    inc     dword [fail_n]
    jmp     .write
.oldest:
    xor     ecx, ecx
    xor     eax, eax                    ; the entry to replace: entry 0 so far
    mov     r9d, [rdx + 8]
    sub     r9d, [stream_frame]         ; its frames to go
.o_next:
    inc     ecx
    cmp     ecx, FAIL_MAX
    jae     .write
    lea     r10d, [rcx + rcx*2]
    mov     r11d, [rdx + r10*4 + 8]
    sub     r11d, [stream_frame]
    cmp     r11d, r9d
    jge     .o_next
    mov     r9d, r11d
    mov     eax, r10d
    jmp     .o_next
.write:
    mov     [rdx + rax*4], edi
    mov     [rdx + rax*4 + 4], esi
    mov     [rdx + rax*4 + 8], r8d
    cmp     dword [msg_done], 0
    jne     .ret
    mov     dword [msg_done], 1
    mov     edi, 2
    lea     rsi, [s_pool_full]
    mov     eax, [world_install_err]
    lea     rcx, [s_conts_full]
    cmp     eax, 2
    cmove   rsi, rcx
    lea     rcx, [s_cols_full]
    cmp     eax, 3
    cmove   rsi, rcx
    call    sys_print
.ret:
    add     rsp, 8
    ret

; install_decoded(edi acx, esi acz) -> eax 1 installed, -1 did not fit (the column is free again): the column
; decoded into load_buf gets its biome map (it is not stored), a record and its install.
install_decoded:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12d, edi
    mov     r13d, esi
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
    test    rax, rax
    jz      .no_record
    lea     rdi, [load_buf]
    call    world_install
    test    eax, eax
    jns     .done
    mov     edi, r12d
    mov     esi, r13d
    call    world_column
    test    rax, rax
    jz      .failed
    mov     rdi, rax
    call    world_column_release
.failed:
    mov     eax, -1
    jmp     .ret
.no_record:
    mov     dword [world_install_err], 3
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

; install_from_region(edi acx, esi acz) -> eax 1 installed from its region file, 0 the file has no readable
; blob for it (generate instead), -1 the install did not fit (the column is free again).
install_from_region:
    push    rbx
    push    r12
    push    r13
    mov     r12d, edi
    mov     r13d, esi
    lea     rdx, [load_buf]
    call    region_read_column
    test    eax, eax
    jz      .ret
    mov     edi, r12d
    mov     esi, r13d
    call    install_decoded
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; install_from_net(edi acx, esi acz) -> eax as install_from_region, from the blob the host sent for that
; column (net_column_take decodes it into load_buf and frees its entry).
install_from_net:
    push    rbx
    push    r12
    push    r13
    mov     r12d, edi
    mov     r13d, esi
    lea     rdx, [load_buf]
    call    net_column_take
    test    eax, eax
    jz      .ret
    mov     edi, r12d
    mov     esi, r13d
    call    install_decoded
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; generate_inline(edi acx, esi acz) -> eax 0 installed, -1 did not fit (the column is free again): a record
; first - with none free nothing is generated - then gen_column on the first buffer on this thread (no
; worker), then install.
generate_inline:
    push    rbx
    push    r12
    push    r13
    mov     r12d, edi
    mov     r13d, esi
    call    world_column_claim
    test    rax, rax
    jz      .no_record
    lea     rbx, [gen_bufs]
    mov     [rbx + GENBUF.cx], r12d
    mov     [rbx + GENBUF.cz], r13d
    mov     rdi, rbx
    call    gen_column
    mov     rdi, rbx
    call    world_install
    test    eax, eax
    jns     .ret
    mov     edi, r12d
    mov     esi, r13d
    call    world_column
    test    rax, rax
    jz      .failed
    mov     rdi, rax
    call    world_column_release
.failed:
    mov     eax, -1
    jmp     .ret
.no_record:
    mov     dword [world_install_err], 3
    mov     eax, -1
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; stream_rdist() -> eax the radius R the stream and the renderer work with: settings.render_dist clamped to
; 2..MAX_RENDER_DIST, at most net_rdist_cap while that is not 0 (a hosting peer). Clobbers ecx.
stream_rdist:
    mov     eax, [settings + SETTINGS.render_dist]
    cmp     eax, 2
    jge     .r_lo
    mov     eax, 2
.r_lo:
    cmp     eax, MAX_RENDER_DIST
    jle     .r_hi
    mov     eax, MAX_RENDER_DIST
.r_hi:
    mov     ecx, [net_rdist_cap]
    test    ecx, ecx
    jz      .ret
    cmp     eax, ecx
    cmovg   eax, ecx
.ret:
    ret

; stream_try_column(edi acx, esi acz) -> eax 0 nothing started (loaded or on its way already, backing off,
; no read budget left, or a guest that waits for the host's answer), 1 the column was installed, requested or
; failed to install (and backs off), 2 this frame's budget is spent (every generator buffer busy, MAX_INLINE
; reached, or the deadline passed): stop starting columns. The budgets are the su_* statics stream_update
; resets: a column comes from its region file (a guest: the host's blob, or - the host said it is
; pristine - the generator), else from the worker or inline.
stream_try_column:
    push    rbx
    push    r12
    push    r13
    mov     r12d, edi
    mov     r13d, esi
    call    world_column
    test    rax, rax
    jnz     .skip                       ; loaded or on its way
    mov     edi, r12d
    mov     esi, r13d
    call    install_waiting
    test    eax, eax
    jnz     .skip                       ; its install did not fit lately: the next column
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .local
    cmp     byte [net_in_world], 0
    jne     .guest                      ; a guest not yet in the host's world (the title panorama streams) stays local
.local:
    mov     edi, r12d
    mov     esi, r13d
    call    region_has_column
    test    eax, eax
    jz      .generate
    cmp     dword [su_reads], MAX_READS
    jae     .skip                       ; this one waits for the next frame
    inc     dword [su_reads]
    mov     edi, r12d
    mov     esi, r13d
    call    install_from_region
    jmp     .installed
.guest:
    mov     edi, r12d
    mov     esi, r13d
    call    net_column_verdict          ; 0 asked the host and waits, 1 pristine, 2 its blob arrived
    test    eax, eax
    jz      .skip
    cmp     eax, 1
    je      .generate
    cmp     dword [su_reads], MAX_READS
    jae     .skip
    inc     dword [su_reads]
    mov     edi, r12d
    mov     esi, r13d
    call    install_from_net
.installed:
    test    eax, eax
    jz      .generate                   ; unreadable: regenerate it
    jns     .check
    mov     edi, r12d
    mov     esi, r13d
    call    install_failed              ; this column backs off; the ones after it go on
    jmp     .check
.generate:
    cmp     dword [gen_threaded], 0
    je      .inline
    mov     edi, r12d
    mov     esi, r13d
    call    world_column_claim          ; the record first: with none free nothing is requested
    test    rax, rax
    jz      .no_record
    mov     rbx, rax
    mov     edi, r12d
    mov     esi, r13d
    call    request_worker
    test    eax, eax
    jnz     .check
    mov     rdi, rbx                    ; every buffer is busy: the column stays missing, stop for this frame
    call    world_column_release
    jmp     .spent
.inline:
    cmp     dword [su_inline], MAX_INLINE
    jae     .spent
    inc     dword [su_inline]
    mov     edi, r12d
    mov     esi, r13d
    call    generate_inline
    test    eax, eax
    jns     .check
    mov     edi, r12d
    mov     esi, r13d
    call    install_failed
.check:
    call    time_mono_ns
    cmp     rax, [su_deadline]
    jae     .spent
    mov     eax, 1
    jmp     .ret
.no_record:
    mov     dword [world_install_err], 3
    mov     edi, r12d
    mov     esi, r13d
    call    install_failed
    jmp     .check
.spent:
    mov     eax, 2
    jmp     .ret
.skip:
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; stream_dispatch(edi ccx, esi ccz, edx L) -> eax 1 when the frame's budget is spent (stop starting
; columns), else 0: every column within Chebyshev L of the column (ccx, ccz), nearest first, goes through
; stream_try_column.
stream_dispatch:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edx
    mov     r15d, edx
    imul    r15d, r15d
    add     r15d, r15d                  ; 2 L^2: no cell of the square lies farther out
    xor     ebx, ebx                    ; spiral index
.next:
    cmp     ebx, [stream_spiral_n]
    jae     .done
    mov     eax, [stream_spiral + rbx*8]        ; dx
    mov     ecx, [stream_spiral + rbx*8 + 4]    ; dz
    inc     ebx
    mov     edx, eax
    imul    edx, edx
    mov     esi, ecx
    imul    esi, esi
    add     edx, esi
    cmp     edx, r15d
    ja      .done                       ; sorted by distance: nothing nearer follows
    lea     edx, [rax + r14]
    lea     esi, [rcx + r14]
    lea     r8d, [r14 + r14]
    cmp     edx, r8d
    ja      .next                       ; beyond the load radius
    cmp     esi, r8d
    ja      .next
    lea     edi, [rax + r12]
    lea     esi, [rcx + r13]
    call    stream_try_column
    cmp     eax, 2
    jne     .next
    mov     eax, 1
    jmp     .ret
.done:
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; stream_light(edi ccx, esi ccz, edx L) -> eax 1 when the frame's lighting budget is spent (MAX_LIGHT columns
; or the deadline), else 0: the columns within Chebyshev L of the column (ccx, ccz) that hold blocks, nearest
; first, are lit.
stream_light:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edx
    mov     r15d, edx
    imul    r15d, r15d
    add     r15d, r15d                  ; 2 L^2
    xor     ebx, ebx                    ; spiral index
.next:
    cmp     ebx, [stream_spiral_n]
    jae     .done
    cmp     dword [su_lit], MAX_LIGHT
    jae     .stop
    mov     eax, [stream_spiral + rbx*8]        ; dx
    mov     ecx, [stream_spiral + rbx*8 + 4]    ; dz
    inc     ebx
    mov     edx, eax
    imul    edx, edx
    mov     esi, ecx
    imul    esi, esi
    add     edx, esi
    cmp     edx, r15d
    ja      .done
    lea     edx, [rax + r14]
    lea     esi, [rcx + r14]
    lea     r8d, [r14 + r14]
    cmp     edx, r8d
    ja      .next
    cmp     esi, r8d
    ja      .next
    lea     edi, [rax + r12]
    lea     esi, [rcx + r13]
    call    world_column
    test    rax, rax
    jz      .next
    cmp     dword [rax + COLUMN.state], COL_BLOCKS
    jne     .next
    mov     rdi, rax
    call    light_column
    inc     dword [su_lit]
    call    time_mono_ns
    cmp     rax, [su_deadline]
    jb      .next
.stop:
    mov     eax, 1
    jmp     .ret
.done:
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; stream_update(edi x, esi z, xmm0 budget_s): one frame around the local cell (x, z).
; 1. unload the columns beyond R + 2 of the local column, beyond MP_SIM_R + 2 of every remote player's
; column and without a block edit waiting for them, 2. install the generator's finished columns, 3. start the
; missing columns within R + 1 nearest first (region file, the host's blob, worker or inline), then those
; within MP_SIM_R + 1 of each remote player (a hosting peer: net_stream_centres), then the columns of the
; waiting block edits (just the column), 4. light the columns that hold blocks, in the same order.
; Steps 3 and 4 stop when budget_s seconds have passed; 1 and 2 always run. A column whose install did not
; fit (world_install -1) is passed over for BACKOFF_FRAMES frames - its buffer stays DONE, or its record goes
; free again - and every other column carries on.
stream_update:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24                     ; [0] L, [4] K
    mov     r12d, edi
    mov     r13d, esi
    cvtss2sd xmm0, xmm0
    mulsd   xmm0, [d_1e9]
    cvttsd2si rbx, xmm0                 ; the budget in ns
    call    sp_ensure
    call    time_mono_ns
    add     rax, rbx
    mov     [su_deadline], rax
    add     r12d, [world_origin_x]
    sar     r12d, 4                     ; the centre column
    add     r13d, [world_origin_z]
    sar     r13d, 4
    mov     [stream_ccx], r12d
    mov     [stream_ccz], r13d
    call    stream_rdist
    lea     ecx, [rax + 1]
    mov     [rsp], ecx                  ; L = R + 1
    add     eax, 2
    mov     [rsp + 4], eax              ; K = R + 2
    inc     dword [stream_frame]
    xor     eax, eax
    mov     [su_reads], eax
    mov     [su_inline], eax
    mov     [su_lit], eax
    mov     [su_nex], eax
    mov     [su_ned], eax
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .unload
    lea     rdi, [su_ex]
    call    net_stream_centres
    mov     ecx, NET_MAX_PEERS - 1
    cmp     eax, ecx
    cmova   eax, ecx
    mov     [su_nex], eax
    lea     rdi, [su_ed]
    mov     esi, MAX_EDIT_COLS
    call    net_edit_columns            ; the columns of the block edits that wait, the oldest edit's first
    mov     ecx, MAX_EDIT_COLS
    cmp     eax, ecx
    cmova   eax, ecx
    mov     [su_ned], eax
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
    cmp     ecx, [rsp + 4]
    jle     .u_next                     ; within the keep radius
    mov     ecx, [su_nex]
.u_remote:                              ; or within MP_SIM_R + 2 of a remote player's column
    test    ecx, ecx
    jz      .u_edits
    dec     ecx
    mov     edx, [r14 + COLUMN.cx]
    sub     edx, [su_ex + rcx*8]
    mov     esi, edx
    sar     esi, 31
    xor     edx, esi
    sub     edx, esi                    ; |dx|
    mov     esi, [r14 + COLUMN.cz]
    sub     esi, [su_ex + rcx*8 + 4]
    mov     r8d, esi
    sar     r8d, 31
    xor     esi, r8d
    sub     esi, r8d                    ; |dz|
    cmp     edx, esi
    cmovl   edx, esi
    cmp     edx, MP_SIM_R + 2
    jg      .u_remote
    jmp     .u_next                     ; kept for that player
.u_edits:                               ; or holds a block edit that waits to be applied
    mov     ecx, [su_ned]
.u_ed:
    test    ecx, ecx
    jz      .u_unload
    dec     ecx
    mov     edx, [r14 + COLUMN.cx]
    cmp     [su_ed + rcx*8], edx
    jne     .u_ed
    mov     edx, [r14 + COLUMN.cz]
    cmp     [su_ed + rcx*8 + 4], edx
    jne     .u_ed
    jmp     .u_next                     ; kept until the edit is applied
.u_unload:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .u_state
    mov     edi, [r14 + COLUMN.cx]      ; the host is asked again when the column is wanted back
    mov     esi, [r14 + COLUMN.cz]
    call    net_column_forget
    mov     eax, [r14 + COLUMN.state]
.u_state:
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
    mov     rdi, r14
    call    world_column_release        ; a stale worker result is dropped at install
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
    mov     rdi, r15
    call    world_install
    test    eax, eax
    jns     .c_free
    mov     edi, [r15 + GENBUF.cx]      ; it did not fit: that column backs off and is generated
    mov     esi, [r15 + GENBUF.cz]      ; again afterwards (generation is deterministic), so no
    call    install_failed              ; buffer is ever held by a column that cannot install
    mov     edi, [r15 + GENBUF.cx]
    mov     esi, [r15 + GENBUF.cz]
    call    world_column
    test    rax, rax
    jz      .c_free
    cmp     dword [rax + COLUMN.state], COL_PENDING
    jne     .c_free
    mov     rdi, rax
    call    world_column_release
.c_free:
    mov     rdi, r15
    mov     esi, GB_FREE
    call    buf_set
.c_next:
    inc     r14d
    jmp     .collect
.dispatch:
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, [rsp]
    call    stream_dispatch
    test    eax, eax
    jnz     .light                      ; the frame's budget is spent
    xor     ebx, ebx                    ; remote player
.d_remote:
    cmp     ebx, [su_nex]
    jae     .d_edits
    mov     edi, [su_ex + rbx*8]
    mov     esi, [su_ex + rbx*8 + 4]
    mov     edx, MP_SIM_R + 1
    call    stream_dispatch
    inc     ebx
    test    eax, eax
    jz      .d_remote
    jmp     .light
.d_edits:                               ; the columns of the block edits that wait: just the column
    xor     ebx, ebx
.d_ed:
    cmp     ebx, [su_ned]
    jae     .light
    mov     edi, [su_ed + rbx*8]
    mov     esi, [su_ed + rbx*8 + 4]
    call    stream_try_column
    inc     ebx
    cmp     eax, 2
    jne     .d_ed
.light:
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, [rsp]
    call    stream_light
    test    eax, eax
    jnz     .done
    xor     ebx, ebx
.l_remote:
    cmp     ebx, [su_nex]
    jae     .l_edits
    mov     edi, [su_ex + rbx*8]
    mov     esi, [su_ex + rbx*8 + 4]
    mov     edx, MP_SIM_R + 1
    call    stream_light
    inc     ebx
    test    eax, eax
    jz      .l_remote
    jmp     .done
.l_edits:
    xor     ebx, ebx
.l_ed:
    cmp     ebx, [su_ned]
    jae     .done
    mov     edi, [su_ed + rbx*8]
    mov     esi, [su_ed + rbx*8 + 4]
    xor     edx, edx                    ; L = 0: just the column
    call    stream_light
    inc     ebx
    test    eax, eax
    jz      .l_ed
.done:
    add     rsp, 24
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
