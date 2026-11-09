; networld.asm - the world on the wire (0.11 multiplayer): block edits, column requests and replies,
; containers, TNT and boats. The host owns all of it; a guest edits a copy and asks the host.
;
;  * Block edits. world_set tells net_block_out (guest: BLOCK to the host; host: BLOCK to every
;    accepted guest, one send each). A received BLOCK goes through nw_apply_edit with net_applying
;    set, so that nothing is echoed; the host applies a guest's edit and relays the cell as it then
;    stands to every guest, the originator included, so that the host's order is the final one. An
;    edit whose column is not lit yet waits in net_edit_q and net_edits_replay applies it once the
;    column is lit; so does every later edit of a column that has one waiting (the order of a cell's
;    edits is kept). The host lets an edit wait NEDIT_TTL frames (net_edit_columns names the columns
;    the stream must load for them). A guest keeps an edit for as long as it holds the column or an
;    answer / a request for it: an answer the column is installed from may predate the edit.
;    A BLOCK is never lost for want of room in a send queue: a guest's wait in net_bq; the host, whose
;    guests each have a queue of their own, remembers the COLUMNS a guest missed an edit of
;    (dirty_mark) and tells the guest to fetch them afresh once it has room (COL_REQ, host to guest:
;    column_stale), so that the answer holds every edit made so far.
;  * Columns. A guest asks the host for every column it needs (COL_REQ) and is answered with the
;    saved/modified blob (COL_DATA), or "pristine" (generate it from the seed). The answers wait in
;    net_colv / net_colbuf until the stream takes them (net_column_verdict / net_column_take); one
;    nobody asks about for COLV_IDLE frames is forgotten, and a full set of buffers gives up its least
;    recently asked blob. The host answers at most 8 requests per frame, round-robin over the guests,
;    and follows every COL_DATA with a BLOCK(FIRE) for each flame in the column (the encoding of a
;    column writes FIRE as AIR).
;  * Containers. The records live on the host. A guest opens one with CONT_OPEN, edits a shadow copy
;    (net_cont_shadow) and sends whole-slot puts with a sequence number (continuing the host's count
;    of its puts); the host applies them (last writer wins) and resends the record to the peers who
;    have it open every 10 frames.
;  * TNT and boats are asked of the host: TNT_PRIME, BOAT_PLACE / MOUNT / DISMOUNT / BREAK, and the
;    pose of a ridden boat (BOAT_POSE).
; All of it runs on the main thread. Coordinates on the wire are absolute; the handlers convert with
; world_origin_x/z. Every handler is called as handler(edi sender slot, esi type, rdx payload,
; ecx length) and checks the length it needs before reading.
%include "common.inc"
default rel

global net_stat_block_rx, net_stat_block_tx
global net_block_out, nw_apply_edit, net_edits_replay, net_edit_n, net_edit_columns, net_bq_n, net_dirty_n
global net_column_verdict, net_column_take, net_column_forget, net_host_columns_serve, net_colv_pending, net_colbuf_used
global net_cont_open_out, net_cont_close_out, net_cont_frame, net_cont_removed
global net_cont_shadow, net_cont_sent, net_cont_seq, net_cont_active
global net_tnt_prime_out
global net_boat_place_out, net_boat_mount_out, net_boat_dismount_out, net_boat_break_out, net_boat_tick
global nw_on_block, nw_on_col_req, nw_on_col_data, nw_on_col_pristine
global nw_on_cont_open, nw_on_cont_data, nw_on_cont_put, nw_on_cont_close, nw_on_cont_gone
global nw_on_tnt_prime
global nw_on_boat_place, nw_on_boat_mount, nw_on_boat_mount_ok, nw_on_boat_dismount
global nw_on_boat_break, nw_on_boat_pose

extern net_role, net_applying, net_in_world, net_peers
extern net_out, net_send_to, net_send_big_to, net_pos_in, net_pos_out
extern net_ep, net_ep_room
extern world_origin_x, world_origin_z, world_get, world_set, world_column, world_column_ready
extern region_has_column, region_encode_column, region_read_blob, decode_blob, blob_buf
extern cont_at, cont_create, cont_block_removed, item_max_stack
extern fire_place, fire_track, fire_untrack
extern tnt_prime
extern boats, boat_riding, boat_rider, boats_place, boats_mount, boats_break
extern player, game_mode, net_give_out
extern app_state, inv_container, game_open_cont, game_open_screen
extern world_unload, world_column_release
extern fires

%define NEDIT_MAX      1024             ; queued edits (a power of two: a ring)
%define NEDIT_TTL      600              ; frames an edit waits for its column
%define NOUT_MAX       4096             ; guest: BLOCK messages waiting for room in the send queue (a ring)
%define COLV_MAX       256              ; guest: column answers tracked (net_colv)
%define COLV_PENDING   64               ; ... of which unanswered requests
%define COLV_TIMEOUT   3600             ; frames before an unanswered request is asked again
%define COLV_IDLE      NEDIT_TTL        ; frames an answered entry may go unasked about before it is forgotten
%define COLBUF_N       32               ; guest: blobs held until the stream takes them
%define COLQ_N         256              ; host: requests queued per guest (a power of two: a ring)
%define COLS_FRAME     8                ; host: requests answered per frame, all guests together
%define CONT_SYNC      10               ; host: frames between the resends of an open container
%define CONT_GRACE     3                ; guest: frames its container screen may take to appear
%define NDIRTY_MAX     128              ; host: columns remembered per guest whose edits it could not send

%define CV_FREE        0                ; COLV.state
%define CV_PENDING     1                ; asked, no answer yet
%define CV_PRISTINE    2                ; the host says: generate it
%define CV_DATA        3                ; the host's blob waits in net_colbuf

struc NEDIT
    .ax:   resd 1                       ; absolute cell
    .az:   resd 1
    .ttl:  resw 1                       ; frames left
    .y:    resb 1
    .id:   resb 1
    .from: resb 1                       ; the peer that made the edit
    .pad:  resb 3
endstruc                                ; 16

struc COLV
    .acx:   resd 1                      ; absolute column
    .acz:   resd 1
    .len:   resd 1                      ; blob bytes (CV_DATA)
    .age:   resw 1                      ; frames since the request (CV_PENDING)
    .state: resb 1                      ; CV_*
    .buf:   resb 1                      ; index into net_colbuf (CV_DATA)
endstruc                                ; 16

section .rodata
align 4
k_bound:   dd 16777216.0                ; wire coordinates must lie inside +-2^24
k_256:     dd 256.0
k_360:     dd 360.0
k_absmask: dd 0x7FFFFFFF

section .bss
alignb 16
net_stat_block_rx: resd 1               ; BLOCK messages received (shown on F3)
net_stat_block_tx: resd 1               ; BLOCK messages sent
net_guest_dirty:   resd 1               ; guest: some per-session state below was touched
net_edit_q:        resb NEDIT_MAX * NEDIT_size
net_edit_head:     resd 1               ; next write index
net_edit_n:        resd 1               ; entries queued, the oldest at (head - n) & (NEDIT_MAX - 1)
net_bq:            resb NOUT_MAX * 12   ; guest: BLOCK messages that found no room, oldest first: {ax, az, y, id, 2 pad}
net_bq_head:       resd 1               ; next write index
net_bq_n:          resd 1               ; entries waiting, the oldest at (head - n) & (NOUT_MAX - 1)
net_dirty:         resq NET_MAX_PEERS * NDIRTY_MAX  ; host: per guest slot the columns it missed an edit of: {acx, acz}
net_dirty_n:       resd NET_MAX_PEERS
net_colv:          resb COLV_MAX * COLV_size
net_colv_pending:  resd 1
net_colbuf_used:   resd 1               ; bit i = net_colbuf[i] holds a blob
net_colq:          resq NET_MAX_PEERS * COLQ_N      ; host: per guest slot a ring of {acx, acz}
net_colq_head:     resd NET_MAX_PEERS
net_colq_n:        resd NET_MAX_PEERS
net_col_rr:        resd 1               ; host: the guest served first (0..6 = slot 1..7)
net_cont_seq:      resd 1               ; guest: the last CONT_PUT sequence number sent
net_cont_active:   resd 1               ; guest: a container is open (or its screen is about to open)
net_cont_grace:    resd 1
net_cont_tick:     resd 1               ; host: frames until the next resend
net_cont_want:     resd 1               ; guest: CONT_OPEN sent for the cell below, its answer still to come
net_cont_want_x:   resd 1
net_cont_want_y:   resd 1
net_cont_want_z:   resd 1
alignb 16
net_cont_shadow:   resb CONTAINER_size  ; guest: the open container, absolute cell
net_cont_sent:     resb CONTAINER_size  ; guest: what the host holds as far as we know
net_col_stage:     resb NET_BLOB_MAX + 16
alignb 64
net_colbuf:        resb COLBUF_N * NET_BLOB_MAX

section .text

; ---- peers ------------------------------------------------------------------------------------------

; peer_ok(edi slot) -> eax 1 when slot is a guest slot (1..7) holding an accepted peer (host side)
peer_ok:
    lea     eax, [rdi - 1]
    cmp     eax, NET_MAX_PEERS - 2
    ja      .no
    imul    eax, edi, PEER_size
    lea     rcx, [net_peers]
    cmp     dword [rcx + rax + PEER.state], PEER_FREE
    setne   al
    movzx   eax, al
    ret
.no:
    xor     eax, eax
    ret

; peer_of(edi slot) -> rax the PEER of that slot (slot < NET_MAX_PEERS)
peer_of:
    imul    eax, edi, PEER_size
    lea     rcx, [net_peers]
    add     rax, rcx
    ret

; abs_below(xmm0 v, xmm1 limit) -> eax 1 when |v| < limit (false for NaN and infinity). Clobbers xmm2.
abs_below:
    movss   xmm2, [k_absmask]
    andps   xmm2, xmm0
    xor     eax, eax
    ucomiss xmm1, xmm2
    seta    al
    ret

; ---- block edits ------------------------------------------------------------------------------------

; net_block_out(edi x, esi y, edx z, ecx id, r8d old_id): the (local) cell just changed from old_id to
; id through world_set and nobody applied it from the wire: BLOCK {ax, az, y, id} goes to the host
; (guest) or to every accepted guest (host). A guest that removed a flame also forgets its fire entry
; (fire_step does not run on a guest).
; Frame: [rsp] ax, [rsp + 4] az, [rsp + 8] y, [rsp + 9] id.
net_block_out:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 16
    mov     eax, [world_origin_x]
    add     eax, edi
    mov     [rsp], eax
    mov     eax, [world_origin_z]
    add     eax, edx
    mov     [rsp + 4], eax
    mov     [rsp + 8], sil
    mov     [rsp + 9], cl
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .send
    cmp     r8d, FIRE
    jne     .send
    cmp     ecx, FIRE
    je      .send
    call    fire_untrack                ; edi, esi, edx are still the cell
.send:
    inc     dword [net_stat_block_tx]
    mov     rdi, rsp
    call    block_send
    leave
    ret

; edit_lost(rdi NEDIT*): the queued edit is dropped without having been applied (the host's time for it ran
; out, or the ring needs its place). The copies of the world must not stay apart over it: the host tells the
; guest who made the edit to fetch the column afresh (the host never applied it), a guest fetches the column
; afresh itself (what it holds of the column may be older than the edit). Both are marks on the column
; (dirty_mark: dirty_flush / guest_dirty_flush act on them). Clobbers like dirty_mark.
edit_lost:
    mov     esi, [rdi + NEDIT.ax]
    sar     esi, 4
    mov     edx, [rdi + NEDIT.az]
    sar     edx, 4
    xor     eax, eax                    ; a guest marks for itself: slot 0
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .mark
    movzx   eax, byte [rdi + NEDIT.from]
.mark:
    mov     edi, eax
    jmp     dirty_mark

; edit_queue(edi ax, esi y, edx az, ecx id, r8d from): the edit waits for its column. A full ring
; overwrites its oldest entry (edit_lost).
edit_queue:
    mov     eax, [net_edit_head]
    imul    r9d, eax, NEDIT_size
    lea     r10, [net_edit_q]
    add     r10, r9
    cmp     dword [net_edit_n], NEDIT_MAX
    jb      .store
    push    rdi                         ; full: the oldest entry (at head) is about to be overwritten
    push    rsi
    push    rdx
    push    rcx
    push    r8
    push    r10
    sub     rsp, 8
    mov     rdi, r10
    call    edit_lost
    add     rsp, 8
    pop     r10
    pop     r8
    pop     rcx
    pop     rdx
    pop     rsi
    pop     rdi
    mov     eax, [net_edit_head]
.store:
    mov     [r10 + NEDIT.ax], edi
    mov     [r10 + NEDIT.az], edx
    mov     word [r10 + NEDIT.ttl], NEDIT_TTL
    mov     [r10 + NEDIT.y], sil
    mov     [r10 + NEDIT.id], cl
    mov     [r10 + NEDIT.from], r8b
    inc     eax
    and     eax, NEDIT_MAX - 1
    mov     [net_edit_head], eax
    cmp     dword [net_edit_n], NEDIT_MAX
    jae     .full
    inc     dword [net_edit_n]
.full:
    mov     dword [net_guest_dirty], 1
    ret

; edit_pending(edi ax, esi az) -> eax 1 when an edit of the same column (16 x 16 cells) waits in the queue.
; Clobbers ecx, edx, esi, edi, r8, r9.
edit_pending:
    mov     ecx, [net_edit_n]
    test    ecx, ecx
    jz      .no
    mov     r8d, [net_edit_head]
    sub     r8d, ecx
    and     r8d, NEDIT_MAX - 1          ; the oldest entry
    sar     edi, 4
    sar     esi, 4
    lea     r9, [net_edit_q]
.l:
    imul    eax, r8d, NEDIT_size
    mov     edx, [r9 + rax + NEDIT.ax]
    sar     edx, 4
    cmp     edx, edi
    jne     .n
    mov     edx, [r9 + rax + NEDIT.az]
    sar     edx, 4
    cmp     edx, esi
    je      .yes
.n:
    inc     r8d
    and     r8d, NEDIT_MAX - 1
    dec     ecx
    jnz     .l
.no:
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; block_send(rdi msg): BLOCK {ax i32, az i32, y u8, id u8} (the 10 bytes at msg) goes out.
;  * A guest sends it to the host: now, or, when the connection has no room or older ones still wait for it,
;    behind them in net_bq (a burst of edits can outrun the 2048 entries of the send queue). When that ring
;    is full as well, the guest remembers the COLUMN of the edit it cannot send (dirty_mark, slot 0) and
;    fetches it afresh from the host (net_edits_replay: column_stale): its own edit is undone, the host's
;    world is the truth.
;  * The host sends it to every accepted guest on its own (net_send_to), so that a guest whose queue is full
;    neither holds the others back nor makes them hear it twice. What such a guest missed is not queued (a
;    stalled guest would make that grow without end): the host remembers the COLUMN (dirty_mark). When the
;    guest has room again (dirty_flush, from net_host_columns_serve) it is told "that column is stale"
;    (COL_REQ, host to guest); the guest drops the column (column_stale) and asks for it afresh, and the
;    answer holds every edit made so far. A guest therefore never misses an edit for good.
block_send:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    cmp     byte [net_role], NET_ROLE_HOST
    je      .host
    cmp     dword [net_bq_n], 0
    jne     .wait
    mov     edi, MT_BLOCK
    mov     rsi, rbx
    mov     edx, 10
    mov     ecx, 1
    call    net_out
    test    eax, eax
    jnz     .done
.wait:
    cmp     dword [net_bq_n], NOUT_MAX
    jb      .enqueue
    xor     edi, edi                    ; the ring is full too: this guest fetches the column afresh itself
    mov     esi, [rbx]
    sar     esi, 4
    mov     edx, [rbx + 4]
    sar     edx, 4
    call    dirty_mark
    jmp     .done
.enqueue:
    mov     eax, [net_bq_head]
    imul    ecx, eax, 12
    lea     rdx, [net_bq]
    mov     rsi, [rbx]
    mov     [rdx + rcx], rsi
    movzx   esi, word [rbx + 8]
    mov     [rdx + rcx + 8], esi
    inc     eax
    and     eax, NOUT_MAX - 1
    mov     [net_bq_head], eax
    inc     dword [net_bq_n]
    jmp     .done
.host:
    mov     r12d, 1
.guest:
    mov     edi, r12d
    call    peer_ok
    test    eax, eax
    jz      .next
    mov     edi, r12d
    mov     esi, MT_BLOCK
    mov     rdx, rbx
    mov     ecx, 10
    mov     r8d, 1
    call    net_send_to
    test    eax, eax
    jnz     .next
    mov     edi, r12d                   ; no room for this guest: its copy of the column is stale from now on
    mov     esi, [rbx]
    sar     esi, 4
    mov     edx, [rbx + 4]
    sar     edx, 4
    call    dirty_mark
.next:
    inc     r12d
    cmp     r12d, NET_MAX_PEERS
    jb      .guest
.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; block_flush(): a guest's BLOCK messages that found no room go out, oldest first, until one finds none again
; (the host keeps no such queue: see block_send)
block_flush:
    push    rbx
.loop:
    mov     eax, [net_bq_n]
    test    eax, eax
    jz      .ret
    mov     ecx, [net_bq_head]
    sub     ecx, eax
    and     ecx, NOUT_MAX - 1
    imul    ecx, ecx, 12
    lea     rsi, [net_bq]
    add     rsi, rcx
    mov     edi, MT_BLOCK
    mov     edx, 10
    mov     ecx, 1
    call    net_out
    test    eax, eax
    jz      .ret
    dec     dword [net_bq_n]
    jmp     .loop
.ret:
    pop     rbx
    ret

; dirty_mark(edi slot, esi acx, edx acz): the copy of that absolute column which `slot` holds is stale. The host
; marks for a guest (slot 1..7: dirty_flush tells it); a guest marks for itself with slot 0 (guest_dirty_flush acts
; on it). A column already remembered is not added twice; a full set (NDIRTY_MAX columns of one slot at once)
; loses the mark. Clobbers eax, ecx, r8-r11.
dirty_mark:
    cmp     edi, NET_MAX_PEERS
    jae     .ret
    lea     r8, [net_dirty_n]
    mov     ecx, [r8 + rdi*4]
    imul    r9d, edi, NDIRTY_MAX
    lea     r10, [net_dirty]
    xor     eax, eax
.l:
    cmp     eax, ecx
    jae     .add
    lea     r11d, [r9 + rax]
    cmp     [r10 + r11*8], esi
    jne     .n
    cmp     [r10 + r11*8 + 4], edx
    je      .ret
.n:
    inc     eax
    jmp     .l
.add:
    cmp     ecx, NDIRTY_MAX
    jae     .ret
    lea     r11d, [r9 + rcx]
    mov     [r10 + r11*8], esi
    mov     [r10 + r11*8 + 4], edx
    inc     dword [r8 + rdi*4]
    test    edi, edi
    jnz     .ret
    mov     dword [net_guest_dirty], 1  ; (a guest's own marks belong to its session)
.ret:
    ret

; dirty_flush() (host, once per frame from net_host_columns_serve): every guest that missed edits is told which
; of its columns are stale (COL_REQ {acx, acz}, host to guest), the newest mark first, for as long as its
; connection has room; the marks that found none stay. A slot nobody holds forgets its marks.
; Frame: [rsp] the message.
dirty_flush:
    push    rbx
    sub     rsp, 16
    mov     ebx, 1
.slot:
    mov     edi, ebx
    call    peer_ok
    test    eax, eax
    jnz     .mark
    lea     rax, [net_dirty_n]
    mov     dword [rax + rbx*4], 0
    jmp     .next
.mark:
    lea     rax, [net_dirty_n]
    mov     ecx, [rax + rbx*4]
    test    ecx, ecx
    jz      .next
    dec     ecx                         ; the newest mark
    imul    edx, ebx, NDIRTY_MAX
    add     edx, ecx
    lea     rsi, [net_dirty]
    mov     rax, [rsi + rdx*8]
    mov     [rsp], rax
    mov     edi, ebx
    mov     esi, MT_COL_REQ
    mov     rdx, rsp
    mov     ecx, 8
    mov     r8d, 1
    call    net_send_to
    test    eax, eax
    jz      .next                       ; no room yet
    lea     rax, [net_dirty_n]
    dec     dword [rax + rbx*4]
    jmp     .mark
.next:
    inc     ebx
    cmp     ebx, NET_MAX_PEERS
    jb      .slot
    add     rsp, 16
    pop     rbx
    ret

; column_stale(edi acx, esi acz) (guest): the host says that column changed in ways it could not tell us (its
; send queue to us was full). Whatever we hold or wait for of it goes: the entry, and the column itself the way
; stream_update drops one (a loaded one is unloaded, one still being generated is released: its worker result
; is dropped at install), so that the stream asks the host for it afresh. The edits that wait for the column
; are dropped by net_edits_replay in the same pass (edit_try: the guest holds neither column nor answer).
column_stale:
    push    rbx
    push    r12
    push    r13
    mov     r12d, edi
    mov     r13d, esi
    call    net_column_forget
    mov     edi, r12d
    mov     esi, r13d
    call    world_column
    test    rax, rax
    jz      .ret
    cmp     dword [rax + COLUMN.state], COL_PENDING
    mov     rdi, rax
    je      .pending
    call    world_unload
    jmp     .ret
.pending:
    call    world_column_release
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; edit_apply(edi ax, esi y, edx az, ecx id, r8d from): the edit's column is lit; make the cell hold id.
; With net_applying set, so that nothing is sent by the hooks underneath:
;  * the cell already holds id: done (no relay);
;  * host: a container block that goes away spills its record (cont_block_removed); a flame is
;    placed by fire_place (air only); every other block by world_set;
;  * guest: world_set, plus fire_track / fire_untrack to keep the fire table in step;
;  * host: the cell as it stands afterwards (id, or what the host kept when it could not apply the
;    edit) is relayed to every accepted guest, the originator included.
; Returns eax 1. Frame: [rsp] net_applying before, [rsp + 4] old block, [rsp + 8] the BLOCK payload.
edit_apply:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     r12d, edi
    sub     r12d, [world_origin_x]      ; local x
    mov     r13d, esi                   ; y
    mov     r14d, edx
    sub     r14d, [world_origin_z]      ; local z
    mov     r15d, ecx                   ; id
    movzx   eax, byte [net_applying]
    mov     [rsp], eax
    mov     byte [net_applying], 1
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    call    world_get
    mov     [rsp + 4], eax
    cmp     eax, r15d
    je      .done
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .apply
    lea     ecx, [r15 - FURNACE]
    cmp     ecx, CHEST - FURNACE
    jbe     .apply                      ; another container block replaces it: its record stays
    mov     eax, [rsp + 4]
    sub     eax, FURNACE
    cmp     eax, CHEST - FURNACE
    ja      .apply
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    call    cont_block_removed          ; the host spills what the chest held
.apply:
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    cmp     r15d, FIRE
    jne     .plain
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .guest_fire
    call    fire_place                  ; air only; the host's own table gets the entry
    jmp     .applied
.guest_fire:
    mov     ecx, FIRE
    call    world_set                   ; preserves edi
    mov     esi, r13d
    mov     edx, r14d
    call    fire_track
    jmp     .applied
.plain:
    mov     ecx, r15d
    call    world_set
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .applied
    cmp     dword [rsp + 4], FIRE
    jne     .applied
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    call    fire_untrack                ; a flame was replaced
.applied:
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .done
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    call    world_get                   ; the cell as it is now
    mov     ecx, r12d
    add     ecx, [world_origin_x]
    mov     [rsp + 8], ecx
    mov     ecx, r14d
    add     ecx, [world_origin_z]
    mov     [rsp + 12], ecx
    mov     [rsp + 16], r13b
    mov     [rsp + 17], al
    inc     dword [net_stat_block_tx]
    lea     rdi, [rsp + 8]
    call    block_send
.done:
    mov     eax, [rsp]
    mov     [net_applying], al
    mov     eax, 1
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; nw_apply_edit(edi ax, esi y, edx az, ecx id, r8d from_slot) -> eax 1 applied / 0 queued or dropped
; Makes the absolute cell hold block id (see edit_apply). A bad y or id is dropped. When the column is not
; lit: the host queues the edit (its stream may still load the column); a guest queues it when it holds the
; column (loaded below COL_LIT) or an answer / a request for it (column_awaited), and drops it otherwise
; (a column asked for later is answered with the edit in).
nw_apply_edit:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    cmp     esi, 255
    ja      .drop
    cmp     ecx, NUM_BLOCKS
    jae     .drop
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edx
    mov     r15d, ecx
    mov     ebx, r8d
    sub     edi, [world_origin_x]
    mov     esi, edx
    sub     esi, [world_origin_z]
    call    world_column_ready
    test    eax, eax
    jnz     .lit
    movzx   eax, byte [net_role]
    cmp     eax, NET_ROLE_HOST
    je      .queue
    cmp     eax, NET_ROLE_GUEST
    jne     .drop
    mov     edi, r12d
    sar     edi, 4
    mov     esi, r14d
    sar     esi, 4
    call    column_awaited
    test    eax, eax
    jz      .drop
.queue:
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, r15d
    mov     r8d, ebx
    call    edit_queue
    jmp     .drop
.lit:
    cmp     dword [net_edit_n], 0
    je      .now
    mov     edi, r12d
    mov     esi, r14d
    call    edit_pending                ; older edits of this column still wait: this one goes behind them
    test    eax, eax
    jnz     .queue
.now:
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, r15d
    mov     r8d, ebx
    call    edit_apply
    jmp     .out
.drop:
    xor     eax, eax
.out:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; column_awaited(edi acx, esi acz) -> eax 1 when this guest holds that column (loaded) or an answer or a
; request for it (colv_find), else 0
column_awaited:
    push    rbx
    push    r12
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, esi
    call    world_column
    test    rax, rax
    jnz     .yes
    mov     edi, ebx
    mov     esi, r12d
    call    colv_find
    test    rax, rax
    jnz     .yes
    xor     eax, eax
    jmp     .out
.yes:
    mov     eax, 1
.out:
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; edit_try(rdi NEDIT*) -> eax 1 the entry stays, 0 it is finished (applied or dropped)
; Applies the edit when its column is lit. Otherwise:
;  * host: its time runs down; an edit that waited NEDIT_TTL frames is dropped (edit_lost: the guest who made
;    it is told to fetch the column afresh);
;  * guest: it stays for as long as the guest holds the column (loaded, below COL_LIT) or an answer / a
;    request for it (column_awaited): the answer a column is installed from may predate the edit, so the edit
;    must outlive it however long the stream keeps the answer. Once the guest holds neither, the next request
;    is answered with the edit in, and the edit is dropped.
edit_try:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12d, [rbx + NEDIT.ax]
    mov     r13d, [rbx + NEDIT.az]
    mov     edi, r12d
    sub     edi, [world_origin_x]
    mov     esi, r13d
    sub     esi, [world_origin_z]
    call    world_column_ready
    test    eax, eax
    jnz     .lit
    cmp     byte [net_role], NET_ROLE_GUEST
    je      .guest
    dec     word [rbx + NEDIT.ttl]
    jnz     .keep
    mov     rdi, rbx                    ; the host's time for it is up
    call    edit_lost
    jmp     .drop
.guest:
    mov     edi, r12d
    sar     edi, 4
    mov     esi, r13d
    sar     esi, 4
    call    column_awaited
    test    eax, eax
    jnz     .keep
.drop:
    xor     eax, eax
    jmp     .out
.keep:
    mov     eax, 1
    jmp     .out
.lit:
    mov     edi, r12d
    movzx   esi, byte [rbx + NEDIT.y]
    mov     edx, r13d
    movzx   ecx, byte [rbx + NEDIT.id]
    movzx   r8d, byte [rbx + NEDIT.from]
    call    edit_apply
    xor     eax, eax
.out:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; guest_dirty_flush() (guest): every column in this guest's own dirty set (its outbox overflowed, or the host
; said the column is stale: nw_on_col_req) is dropped and asked for afresh (column_stale). Marks made while it
; runs (none can) would be taken in the same loop.
guest_dirty_flush:
    push    rbx
.l:
    mov     eax, [net_dirty_n]          ; slot 0's marks are net_dirty[0 .. n)
    test    eax, eax
    jz      .ret
    dec     eax
    mov     [net_dirty_n], eax
    lea     rcx, [net_dirty]
    mov     rbx, [rcx + rax*8]
    mov     edi, ebx
    shr     rbx, 32
    mov     esi, ebx
    call    column_stale
    jmp     .l
.ret:
    pop     rbx
    ret

; net_edits_replay(): once per frame (net_pump). Offline: the queue is emptied. A guest outside a world
; (between the accept and game_join) starts its session state clean. Otherwise every queued edit is
; tried in the order it arrived (edit_try); the ones that stay are packed to the front of the ring.
; A guest also ages its unanswered column requests.
net_edits_replay:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    movzx   eax, byte [net_role]
    test    eax, eax
    jz      .off
    cmp     eax, NET_ROLE_GUEST
    jne     .queue
    cmp     byte [net_in_world], 0
    jne     .live
    call    nw_guest_reset
    jmp     .ret
.live:
    call    colv_age
    call    guest_dirty_flush
.queue:
    call    block_flush
    mov     r12d, [net_edit_n]
    test    r12d, r12d
    jz      .ret
    mov     eax, [net_edit_head]
    sub     eax, r12d
    and     eax, NEDIT_MAX - 1
    mov     r13d, eax                   ; read index
    mov     r14d, eax                   ; write index
    xor     r15d, r15d                  ; survivors
.entry:
    imul    eax, r13d, NEDIT_size
    lea     rbx, [net_edit_q]
    add     rbx, rax
    mov     rdi, rbx
    call    edit_try
    test    eax, eax
    jz      .gone
    imul    eax, r14d, NEDIT_size
    lea     rcx, [net_edit_q]
    add     rcx, rax
    cmp     rcx, rbx
    je      .packed
    mov     rax, [rbx]
    mov     [rcx], rax
    mov     rax, [rbx + 8]
    mov     [rcx + 8], rax
.packed:
    inc     r14d
    and     r14d, NEDIT_MAX - 1
    inc     r15d
.gone:
    inc     r13d
    and     r13d, NEDIT_MAX - 1
    dec     r12d
    jnz     .entry
    mov     [net_edit_head], r14d
    mov     [net_edit_n], r15d
    jmp     .ret
.off:
    mov     dword [net_edit_n], 0
    mov     dword [net_bq_n], 0
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; net_edit_columns(rdi int32 out[2 * max], esi max) -> eax n
; The distinct absolute chunk columns (acx = ax sar 4, acz = az sar 4) of the edits waiting in the queue,
; the oldest edit's column first, at most max (and at most 32) of them, written to out as (acx, acz) int32
; pairs. The host's stream loads these columns (the edits wait for them to be lit); 0 when this is not the
; host or nothing waits. Changes nothing but out. A leaf: rdi, esi, eax, ecx, edx, r8-r11 only.
net_edit_columns:
    xor     eax, eax
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    mov     ecx, [net_edit_n]
    test    ecx, ecx
    jz      .ret
    mov     r8d, 32
    cmp     esi, r8d
    cmova   esi, r8d                    ; at most 32
    test    esi, esi
    jz      .ret
    mov     r8d, [net_edit_head]
    sub     r8d, ecx
    and     r8d, NEDIT_MAX - 1          ; the oldest entry
    lea     r9, [net_edit_q]
.entry:
    imul    r10d, r8d, NEDIT_size
    mov     r11d, [r9 + r10 + NEDIT.ax]
    sar     r11d, 4                     ; acx
    mov     r10d, [r9 + r10 + NEDIT.az]
    sar     r10d, 4                     ; acz
    xor     edx, edx
.seen:
    cmp     edx, eax
    jae     .new
    cmp     [rdi + rdx*8], r11d
    jne     .again
    cmp     [rdi + rdx*8 + 4], r10d
    je      .next
.again:
    inc     edx
    jmp     .seen
.new:
    cmp     eax, esi
    jae     .ret                        ; max columns: the rest are newer
    mov     [rdi + rax*8], r11d
    mov     [rdi + rax*8 + 4], r10d
    inc     eax
.next:
    inc     r8d
    and     r8d, NEDIT_MAX - 1
    dec     ecx
    jnz     .entry
.ret:
    ret

; nw_on_block(edi from, esi type, rdx payload, ecx len): BLOCK {ax i32, az i32, y u8, id u8}.
; The host takes edits from its guests only, a guest from the host only.
nw_on_block:
    cmp     ecx, 10
    jb      .ret
    movzx   eax, byte [net_role]
    cmp     eax, NET_ROLE_HOST
    je      .host
    cmp     eax, NET_ROLE_GUEST
    jne     .ret
    test    edi, edi
    jnz     .ret
    jmp     .take
.host:
    sub     rsp, 8
    call    peer_ok                     ; keeps rdi, rdx
    add     rsp, 8
    test    eax, eax
    jz      .ret
.take:
    inc     dword [net_stat_block_rx]
    mov     r8d, edi
    mov     edi, [rdx]
    mov     eax, [rdx + 4]
    movzx   esi, byte [rdx + 8]
    movzx   ecx, byte [rdx + 9]
    mov     edx, eax
    jmp     nw_apply_edit
.ret:
    ret

; ---- guest: the host's answers about columns ----------------------------------------------------------

; colv_find(edi acx, esi acz) -> rax the entry for that column, or 0. Clobbers ecx.
colv_find:
    lea     rax, [net_colv]
    mov     ecx, COLV_MAX
.l:
    cmp     byte [rax + COLV.state], CV_FREE
    je      .n
    cmp     [rax + COLV.acx], edi
    jne     .n
    cmp     [rax + COLV.acz], esi
    je      .ret
.n:
    add     rax, COLV_size
    dec     ecx
    jnz     .l
    xor     eax, eax
.ret:
    ret

; colv_release(rdi entry): the entry is free again (a pending request stops counting, a blob's buffer
; is given back)
colv_release:
    movzx   eax, byte [rdi + COLV.state]
    cmp     eax, CV_PENDING
    jne     .data
    dec     dword [net_colv_pending]
    jmp     .clear
.data:
    cmp     eax, CV_DATA
    jne     .clear
    movzx   ecx, byte [rdi + COLV.buf]
    btr     dword [net_colbuf_used], ecx
.clear:
    mov     byte [rdi + COLV.state], CV_FREE
    ret

; colv_alloc() -> rax a free entry or 0. A table with no free entry gives up a pristine one: its
; verdict can be asked again.
colv_alloc:
    lea     rax, [net_colv]
    mov     ecx, COLV_MAX
    xor     edx, edx                    ; a pristine entry seen
.l:
    movzx   esi, byte [rax + COLV.state]
    test    esi, esi
    jz      .ret
    cmp     esi, CV_PRISTINE
    jne     .n
    test    rdx, rdx
    jnz     .n
    mov     rdx, rax
.n:
    add     rax, COLV_size
    dec     ecx
    jnz     .l
    mov     rax, rdx
.ret:
    ret

; colv_age(): every entry grows older. A request the host did not answer for COLV_TIMEOUT frames is forgotten
; (the host may never have got it: the next verdict asks again). An answer - pristine, or a blob - nobody asked
; about for COLV_IDLE frames is forgotten too: the stream lost interest, its blob must not hold one of the
; buffers, and an answer that old must not be installed under newer edits. A verdict asked of an answered entry
; keeps it young (net_column_verdict).
colv_age:
    push    rbx
    push    r12
    sub     rsp, 8
    lea     rbx, [net_colv]
    mov     r12d, COLV_MAX
.l:
    movzx   eax, byte [rbx + COLV.state]
    test    eax, eax
    jz      .n
    inc     word [rbx + COLV.age]
    mov     ecx, COLV_IDLE
    cmp     eax, CV_PENDING
    jne     .limit
    mov     ecx, COLV_TIMEOUT
.limit:
    cmp     [rbx + COLV.age], cx
    jb      .n
    mov     rdi, rbx
    call    colv_release
.n:
    add     rbx, COLV_size
    dec     r12d
    jnz     .l
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; nw_guest_reset(): a new session starts (the guest has joined but is not in the world yet): forget
; every queued edit, column answer and container of the last one. Does nothing when nothing was
; touched.
nw_guest_reset:
    cmp     dword [net_guest_dirty], 0
    je      .ret
    mov     dword [net_guest_dirty], 0
    mov     dword [net_edit_n], 0
    mov     dword [net_edit_head], 0
    mov     dword [net_bq_n], 0
    mov     dword [net_bq_head], 0
    mov     dword [net_dirty_n], 0      ; (slot 0: the columns this guest was to fetch afresh)
    lea     rdi, [net_colv]
    mov     ecx, COLV_MAX * COLV_size / 8
    xor     eax, eax
    rep     stosq
    mov     dword [net_colv_pending], 0
    mov     dword [net_colbuf_used], 0
    mov     dword [net_cont_active], 0
    mov     dword [net_cont_want], 0
    mov     dword [net_cont_seq], 0
    mov     byte [net_cont_shadow + CONTAINER.kind], 0
.ret:
    ret

; net_column_verdict(edi acx, esi acz) -> eax 0 pending / 1 pristine / 2 data (guest)
; An unknown column is asked of the host (COL_REQ) when fewer than 64 requests are pending and the
; table has room; the answer is 0 until the host replies. 1: the column is unmodified, generate it
; from the seed. 2: the host's blob waits (net_column_take). Anything but a guest: 1.
; Frame: [rsp] the request {acx, acz}.
net_column_verdict:
    cmp     byte [net_role], NET_ROLE_GUEST
    je      .guest
    mov     eax, 1
    ret
.guest:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 24
    mov     r12d, edi
    mov     r13d, esi
    call    colv_find
    test    rax, rax
    jnz     .known
    cmp     dword [net_colv_pending], COLV_PENDING
    jae     .wait
    call    colv_alloc
    mov     rbx, rax
    test    rbx, rbx
    jz      .wait
    mov     [rsp], r12d
    mov     [rsp + 4], r13d
    mov     edi, MT_COL_REQ
    mov     rsi, rsp
    mov     edx, 8
    mov     ecx, 1
    call    net_out
    test    eax, eax
    jz      .wait                       ; no room to ask: the next call tries again
    mov     [rbx + COLV.acx], r12d
    mov     [rbx + COLV.acz], r13d
    mov     dword [rbx + COLV.len], 0
    mov     word [rbx + COLV.age], 0
    mov     byte [rbx + COLV.buf], 0
    mov     byte [rbx + COLV.state], CV_PENDING
    inc     dword [net_colv_pending]
    mov     dword [net_guest_dirty], 1
.wait:
    xor     eax, eax
    jmp     .out
.known:
    movzx   ecx, byte [rax + COLV.state]
    cmp     ecx, CV_PENDING
    je      .answer                     ; (a pending request keeps its age: it is asked again once it is too old)
    mov     word [rax + COLV.age], 0    ; an answer somebody still asks for stays
.answer:
    lea     eax, [rcx - 1]              ; pending 0, pristine 1, data 2
.out:
    add     rsp, 24
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; net_column_take(edi acx, esi acz, rdx GENBUF*) -> eax 1/0 (guest)
; Decodes the host's blob for that column into the buffer (decode_blob: blocks, top, containers at
; their absolute cells; the caller fills the biome map) and frees the entry. 0: no blob is waiting
; for that column, or it does not decode (the entry is freed all the same).
net_column_take:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12d, edi                   ; acx
    mov     ebx, esi                    ; acz
    mov     r13, rdx                    ; the buffer
    call    colv_find
    test    rax, rax
    jz      .none
    cmp     byte [rax + COLV.state], CV_DATA
    jne     .none
    mov     r14, rax                    ; the entry
    movzx   ecx, byte [r14 + COLV.buf]
    imul    rdi, rcx, NET_BLOB_MAX
    lea     rdx, [net_colbuf]
    add     rdi, rdx                    ; the blob
    mov     esi, [r14 + COLV.len]
    mov     rdx, r13
    mov     ecx, r12d
    mov     r8d, ebx
    call    decode_blob
    mov     ebx, eax
    mov     rdi, r14
    call    colv_release
    mov     eax, ebx
    jmp     .out
.none:
    xor     eax, eax
.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; net_column_forget(edi acx, esi acz): the stream dropped that column (or gave up on it): its entry
; goes, a waiting blob with it
net_column_forget:
    sub     rsp, 8
    call    colv_find
    test    rax, rax
    jz      .ret
    mov     rdi, rax
    call    colv_release
.ret:
    add     rsp, 8
    ret

; nw_on_col_data(edi from, esi type, rdx payload, ecx len): COL_DATA {acx i32, acz i32, blob}.
; Guest. The blob is copied into a free buffer of net_colbuf and the entry becomes CV_DATA; a column
; nobody asked about (anymore) is ignored. When every buffer holds a blob nobody has taken, the blob
; asked about least recently (the oldest age) gives up its buffer: its entry is forgotten and that
; column is asked for again when the stream wants it. A newer answer replaces an older one that was
; not taken yet.
nw_on_col_data:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .out
    test    edi, edi
    jnz     .out
    cmp     ecx, 9
    jb      .out
    cmp     ecx, NET_BLOB_MAX
    ja      .out
    mov     r12, rdx
    mov     r13d, ecx
    mov     edi, [r12]
    mov     esi, [r12 + 4]
    call    colv_find
    test    rax, rax
    jz      .out
    mov     rbx, rax
    cmp     byte [rbx + COLV.state], CV_DATA
    je      .copy                       ; its buffer is reused
.alloc:
    mov     eax, [net_colbuf_used]
    not     eax
    bsf     ecx, eax
    jnz     .got
    lea     rax, [net_colv]             ; every buffer is taken: find the blob asked about least recently
    mov     ecx, COLV_MAX
    xor     r14d, r14d
    mov     edx, -1
.old:
    cmp     byte [rax + COLV.state], CV_DATA
    jne     .old_next
    movzx   esi, word [rax + COLV.age]
    cmp     esi, edx
    jle     .old_next
    mov     edx, esi
    mov     r14, rax
.old_next:
    add     rax, COLV_size
    dec     ecx
    jnz     .old
    test    r14, r14
    jz      .no_buf                     ; (cannot happen: a full set of buffers is a set of blobs)
    mov     rdi, r14
    call    colv_release                ; its buffer is free now
    jmp     .alloc
.got:
    bts     dword [net_colbuf_used], ecx
    cmp     byte [rbx + COLV.state], CV_PENDING
    jne     .claimed
    dec     dword [net_colv_pending]
.claimed:
    mov     [rbx + COLV.buf], cl
    mov     byte [rbx + COLV.state], CV_DATA
.copy:
    movzx   eax, byte [rbx + COLV.buf]
    imul    rdi, rax, NET_BLOB_MAX
    lea     rax, [net_colbuf]
    add     rdi, rax
    lea     rsi, [r12 + 8]
    lea     ecx, [r13 - 8]
    mov     [rbx + COLV.len], ecx
    mov     word [rbx + COLV.age], 0
    rep     movsb
    jmp     .out
.no_buf:
    mov     rdi, rbx
    call    colv_release
.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; nw_on_col_pristine(edi from, esi type, rdx payload, ecx len): COL_PRISTINE {acx i32, acz i32}.
; Guest. The entry says "generate it" (a blob it still held is dropped).
nw_on_col_pristine:
    sub     rsp, 8
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    test    edi, edi
    jnz     .ret
    cmp     ecx, 8
    jb      .ret
    mov     edi, [rdx]
    mov     esi, [rdx + 4]
    call    colv_find
    test    rax, rax
    jz      .ret
    mov     [rsp], rax
    mov     rdi, rax
    call    colv_release                ; frees the buffer / the pending count ...
    mov     rax, [rsp]
    mov     byte [rax + COLV.state], CV_PRISTINE    ; ... and the entry says "pristine"
    mov     word [rax + COLV.age], 0
.ret:
    add     rsp, 8
    ret

; ---- host: serving columns ---------------------------------------------------------------------------

; nw_on_col_req(edi from, esi type, rdx payload, ecx len): COL_REQ {acx i32, acz i32}.
; Host: the request joins that guest's queue (256; a full queue drops the request, which the guest's
; timeout asks again).
; Guest: the host says that column is stale (it could not tell this guest of an edit of it: its send queue
; to the guest was full): the column is marked, net_edits_replay drops it and asks for it afresh
; (column_stale).
nw_on_col_req:
    sub     rsp, 24
    movzx   eax, byte [net_role]
    cmp     eax, NET_ROLE_HOST
    je      .host
    cmp     eax, NET_ROLE_GUEST
    jne     .ret
    test    edi, edi
    jnz     .ret                        ; only the host says so
    cmp     ecx, 8
    jb      .ret
    mov     esi, [rdx]
    mov     edx, [rdx + 4]
    xor     edi, edi
    call    dirty_mark
    jmp     .ret
.host:
    cmp     ecx, 8
    jb      .ret
    mov     [rsp], rdx
    mov     [rsp + 8], edi
    call    peer_ok
    test    eax, eax
    jz      .ret
    mov     edi, [rsp + 8]
    lea     rax, [net_colq_n]
    mov     ecx, [rax + rdi*4]
    cmp     ecx, COLQ_N
    jae     .ret
    lea     rdx, [net_colq_head]
    add     ecx, [rdx + rdi*4]
    and     ecx, COLQ_N - 1
    mov     esi, edi
    shl     esi, 8
    add     esi, ecx                    ; slot * COLQ_N + (head + n) & mask
    mov     rdx, [rsp]
    mov     rdx, [rdx]
    lea     rcx, [net_colq]
    mov     [rcx + rsi*8], rdx
    inc     dword [rax + rdi*4]
.ret:
    add     rsp, 24
    ret

; fire_column(edi slot, esi acx, edx acz) -> eax the flames of that absolute column in the host's fire table
; (an entry whose cell no longer holds FIRE - fire_step has not freed it yet - is not one).
; With a slot (>= 0) each of them is also sent to that guest as BLOCK(FIRE) {ax, az, y, FIRE} on the reliable
; channel: a column's encoding (a COL_DATA blob) writes FIRE as AIR, so the guest learns of the burning cells
; from these (edit_apply puts the block and fire_track's its entry). The caller has made sure that the
; connection has room for them (slot -1 only counts).
; r12d = slot, r13d, r14d = acx, acz, r15d = count, rbx = the entry. Frame: [rsp] the BLOCK, [rsp + 16] the end.
fire_column:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 32
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edx
    xor     r15d, r15d
    lea     rbx, [fires]
    lea     rax, [rbx + MAX_FIRES * FIREENT_size]
    mov     [rsp + 16], rax
.l:
    cmp     dword [rbx + FIREENT.y], -1
    je      .next
    mov     edi, [rbx + FIREENT.x]
    mov     esi, [rbx + FIREENT.y]
    mov     edx, [rbx + FIREENT.z]
    call    world_get
    cmp     eax, FIRE
    jne     .next
    mov     eax, [rbx + FIREENT.x]
    add     eax, [world_origin_x]       ; absolute cell
    mov     ecx, eax
    sar     ecx, 4
    cmp     ecx, r13d
    jne     .next
    mov     edx, [rbx + FIREENT.z]
    add     edx, [world_origin_z]
    mov     ecx, edx
    sar     ecx, 4
    cmp     ecx, r14d
    jne     .next
    inc     r15d
    test    r12d, r12d
    js      .next                       ; only counting
    mov     [rsp], eax
    mov     [rsp + 4], edx
    mov     ecx, [rbx + FIREENT.y]
    mov     [rsp + 8], cl
    mov     byte [rsp + 9], FIRE
    inc     dword [net_stat_block_tx]
    mov     edi, r12d
    mov     esi, MT_BLOCK
    mov     rdx, rsp
    mov     ecx, 10
    mov     r8d, 1
    call    net_send_to
.next:
    add     rbx, FIREENT_size
    cmp     rbx, [rsp + 16]
    jb      .l
    mov     eax, r15d
    add     rsp, 32
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; col_serve_one(edi slot) -> eax 1 when the oldest request of that guest was answered (and removed),
; 0 when it must wait (its connection has no room for the answer)
; The answer: the loaded column when it holds changes (CF_MODIFIED | CF_CONTS) -> its encoding; else
; the region file's blob when it has the column; else "pristine". A blob goes out as COL_DATA {acx,
; acz, blob} (net_send_big_to) when the connection has room for its parts, the flames of the column
; (fire_column: BLOCK(FIRE) after the blob) and four more messages.
col_serve_one:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     ebx, edi
    lea     rax, [net_colq_head]
    mov     ecx, [rax + rbx*4]
    mov     edx, ebx
    shl     edx, 8
    add     edx, ecx
    lea     rax, [net_colq]
    mov     rax, [rax + rdx*8]
    mov     r12d, eax
    shr     rax, 32
    mov     r13d, eax
    mov     edi, r12d
    mov     esi, r13d
    call    world_column
    test    rax, rax
    jz      .stored
    cmp     dword [rax + COLUMN.state], COL_BLOCKS
    jb      .stored
    test    dword [rax + COLUMN.flags], CF_MODIFIED | CF_CONTS
    jz      .stored
    mov     rdi, rax
    call    region_encode_column
    jmp     .blob
.stored:
    mov     edi, r12d
    mov     esi, r13d
    call    region_has_column
    test    eax, eax
    jz      .pristine
    mov     edi, r12d
    mov     esi, r13d
    call    region_read_blob
.blob:
    test    eax, eax
    jz      .pristine                   ; nothing readable: the guest generates it as the host would
    mov     r14d, eax
    cmp     eax, NET_BLOB_MAX - 8
    ja      .pop                        ; cannot be sent (and cannot happen: a blob stays below 140 KB)
    lea     rdi, [net_col_stage]
    mov     [rdi], r12d
    mov     [rdi + 4], r13d
    add     rdi, 8
    lea     rsi, [blob_buf]
    mov     ecx, r14d
    rep     movsb
    lea     eax, [r14 + 8 + NET_PART_MAX - 1]
    xor     edx, edx
    mov     ecx, NET_PART_MAX
    div     ecx                         ; the parts of the message
    lea     r15d, [rax + 4]
    mov     edi, -1
    mov     esi, r12d
    mov     edx, r13d
    call    fire_column                 ; the flames of the column follow the blob: they need room as well
    add     r15d, eax
    lea     rdi, [net_ep]
    mov     esi, ebx
    call    net_ep_room
    cmp     eax, r15d
    jl      .wait
    mov     edi, ebx
    mov     esi, MT_COL_DATA
    lea     rdx, [net_col_stage]
    lea     ecx, [r14 + 8]
    call    net_send_big_to
    test    eax, eax
    jz      .wait
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    call    fire_column                 ; ... and now the flames, behind it on the same ordered channel
    jmp     .pop
.pristine:
    mov     [rsp], r12d
    mov     [rsp + 4], r13d
    mov     edi, ebx
    mov     esi, MT_COL_PRISTINE
    mov     rdx, rsp
    mov     ecx, 8
    mov     r8d, 1
    call    net_send_to
    test    eax, eax
    jz      .wait
.pop:
    lea     rax, [net_colq_head]
    mov     ecx, [rax + rbx*4]
    inc     ecx
    and     ecx, COLQ_N - 1
    mov     [rax + rbx*4], ecx
    lea     rax, [net_colq_n]
    dec     dword [rax + rbx*4]
    mov     eax, 1
    jmp     .out
.wait:
    xor     eax, eax
.out:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; net_host_columns_serve(): once per frame on the host. Answers at most 8 requests (COLS_FRAME), the
; guests taking turns (the first served moves on every frame); a guest whose connection has no room
; is skipped and keeps its queue. The queue of a slot nobody holds is emptied.
net_host_columns_serve:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    call    dirty_flush                 ; the guests that missed edits are told which columns to fetch afresh
    mov     ebx, 1
.free:
    mov     edi, ebx
    call    peer_ok
    test    eax, eax
    jnz     .held
    lea     rax, [net_colq_n]
    mov     dword [rax + rbx*4], 0
.held:
    inc     ebx
    cmp     ebx, NET_MAX_PEERS
    jb      .free
    mov     r12d, COLS_FRAME            ; replies left
.round:
    xor     r14d, r14d                  ; replies sent in this pass
    xor     r13d, r13d                  ; k: the k-th guest from the first served
.guest:
    test    r12d, r12d
    jz      .done
    mov     eax, [net_col_rr]
    add     eax, r13d
    cmp     eax, NET_MAX_PEERS - 1
    jb      .wrapped
    sub     eax, NET_MAX_PEERS - 1
.wrapped:
    lea     ebx, [rax + 1]              ; slot 1..7
    lea     rax, [net_colq_n]
    cmp     dword [rax + rbx*4], 0
    je      .next
    mov     edi, ebx
    call    col_serve_one
    test    eax, eax
    jz      .next
    dec     r12d
    inc     r14d
.next:
    inc     r13d
    cmp     r13d, NET_MAX_PEERS - 1
    jb      .guest
    test    r14d, r14d
    jnz     .round
.done:
    mov     eax, [net_col_rr]
    inc     eax
    cmp     eax, NET_MAX_PEERS - 1
    jb      .rr
    xor     eax, eax
.rr:
    mov     [net_col_rr], eax
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- containers ---------------------------------------------------------------------------------------

; cont_dirty() -> eax 1 when the shadow's 27 cells differ from what was last sent or received
cont_dirty:
    lea     rsi, [net_cont_shadow + CONTAINER.slots]
    lea     rdi, [net_cont_sent + CONTAINER.slots]
    mov     ecx, 27
    repe    cmpsd
    setne   al
    movzx   eax, al
    ret

; cont_put_if_dirty() -> eax 1 when nothing is left to send (the shadow equals what the host holds, or the put
; was queued just now), 0 when the put found no room (it is made again next frame). A guest whose shadow
; changed since the last put sends CONT_PUT {ax, ay, az, seq, slots[108]} with the next sequence number.
; Frame: the message at [rsp] (124 bytes).
cont_put_if_dirty:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 128
    cmp     byte [net_cont_shadow + CONTAINER.kind], 0
    je      .clean
    call    cont_dirty
    test    eax, eax
    jz      .clean
    mov     eax, [net_cont_shadow + CONTAINER.x]
    mov     [rsp], eax
    mov     eax, [net_cont_shadow + CONTAINER.y]
    mov     [rsp + 4], eax
    mov     eax, [net_cont_shadow + CONTAINER.z]
    mov     [rsp + 8], eax
    mov     eax, [net_cont_seq]
    inc     eax
    mov     [rsp + 12], eax
    lea     rdi, [rsp + 16]
    lea     rsi, [net_cont_shadow + CONTAINER.slots]
    mov     ecx, 27
    rep     movsd
    mov     edi, MT_CONT_PUT
    mov     rsi, rsp
    mov     edx, 124
    mov     ecx, 1
    call    net_out
    test    eax, eax
    jz      .out                        ; no room: eax is 0
    inc     dword [net_cont_seq]
    lea     rdi, [net_cont_sent + CONTAINER.slots]
    lea     rsi, [net_cont_shadow + CONTAINER.slots]
    mov     ecx, 27
    rep     movsd
.clean:
    mov     eax, 1
.out:
    leave
    ret

; cont_data_send(edi slot, esi seq, rdx CONTAINER*): CONT_DATA {ax, ay, az, seq, record[124]} to that
; guest: the record's cell and bytes 12..135 (kind, cells, burn, cook)
; Frame: the message at [rsp] (140 bytes).
cont_data_send:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 152
    mov     ebx, edi
    mov     eax, [rdx + CONTAINER.x]
    mov     [rsp], eax
    mov     eax, [rdx + CONTAINER.y]
    mov     [rsp + 4], eax
    mov     eax, [rdx + CONTAINER.z]
    mov     [rsp + 8], eax
    mov     [rsp + 12], esi
    lea     rsi, [rdx + CONTAINER.kind]
    lea     rdi, [rsp + 16]
    mov     ecx, (CONTAINER_size - CONTAINER.kind) / 4
    rep     movsd
    mov     edi, ebx
    mov     esi, MT_CONT_DATA
    mov     rdx, rsp
    mov     ecx, 140
    mov     r8d, 1
    call    net_send_to
    add     rsp, 152
    pop     rbx
    pop     rbp
    ret

; cont_block_ok(edi x, esi y, edx z, ecx kind) -> eax 1 when the (local) cell holds the block of that
; container kind (a furnace, lit or not, or a chest)
cont_block_ok:
    push    rbx
    mov     ebx, ecx
    call    world_get
    cmp     ebx, CONT_CHEST
    je      .chest
    cmp     ebx, CONT_FURNACE
    jne     .no
    cmp     eax, FURNACE
    je      .yes
    cmp     eax, FURNACE_LIT
    je      .yes
    jmp     .no
.chest:
    cmp     eax, CHEST
    je      .yes
.no:
    xor     eax, eax
    pop     rbx
    ret
.yes:
    mov     eax, 1
    pop     rbx
    ret

; net_cont_open_out(edi x, esi y, edx z, ecx kind) (guest): CONT_OPEN {ax, ay, az, kind} for the
; (local) cell of a chest or furnace the player clicked. The screen opens when the host's CONT_DATA
; arrives.
net_cont_open_out:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    push    rbp
    mov     rbp, rsp
    sub     rsp, 16
    mov     eax, [world_origin_x]
    add     eax, edi
    mov     [rsp], eax
    mov     [rsp + 4], esi
    mov     eax, [world_origin_z]
    add     eax, edx
    mov     [rsp + 8], eax
    mov     [rsp + 12], cl
    mov     eax, [rsp]                  ; the answer is waited for
    mov     [net_cont_want_x], eax
    mov     eax, [rsp + 4]
    mov     [net_cont_want_y], eax
    mov     eax, [rsp + 8]
    mov     [net_cont_want_z], eax
    mov     dword [net_cont_want], 1
    mov     dword [net_guest_dirty], 1
    mov     edi, MT_CONT_OPEN
    mov     rsi, rsp
    mov     edx, 13
    mov     ecx, 1
    call    net_out
    leave
.ret:
    ret

; nw_on_cont_open(edi from, esi type, rdx payload, ecx len): CONT_OPEN {ax, ay, az i32, kind u8}.
; Host. The cell must hold the block of that kind; its record is found (cont_at) or made
; (cont_create), noted as the one that guest has open, and sent back (CONT_DATA, with the sequence of
; the guest's last put). Anything else answers CONT_GONE.
; rbx = sender, r12d, r13d, r14d = ax, ay, az, r15 = payload.
; Frame: [rsp] local x, [rsp + 4] local z, [rsp + 8] the record / the CONT_GONE message.
nw_on_cont_open:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .out
    cmp     ecx, 13
    jb      .out
    mov     ebx, edi
    mov     r15, rdx
    call    peer_ok
    test    eax, eax
    jz      .out
    mov     r12d, [r15]
    mov     r13d, [r15 + 4]
    mov     r14d, [r15 + 8]
    mov     eax, r12d
    sub     eax, [world_origin_x]
    mov     [rsp], eax
    mov     eax, r14d
    sub     eax, [world_origin_z]
    mov     [rsp + 4], eax
    movzx   ecx, byte [r15 + 12]
    cmp     ecx, CONT_FURNACE
    je      .kind_ok
    cmp     ecx, CONT_CHEST
    jne     .out                        ; no such kind: not worth an answer
.kind_ok:
    mov     edi, [rsp]
    mov     esi, r13d
    mov     edx, [rsp + 4]
    movzx   ecx, byte [r15 + 12]
    call    cont_block_ok
    test    eax, eax
    jz      .gone
    mov     edi, [rsp]
    mov     esi, r13d
    mov     edx, [rsp + 4]
    call    cont_at
    test    rax, rax
    jnz     .have
    mov     edi, [rsp]
    mov     esi, r13d
    mov     edx, [rsp + 4]
    movzx   ecx, byte [r15 + 12]
    call    cont_create
    test    rax, rax
    jz      .gone                       ; every record is in use
.have:
    movzx   ecx, byte [r15 + 12]
    cmp     [rax + CONTAINER.kind], cl
    jne     .gone
    mov     [rsp + 8], rax
    mov     edi, ebx
    call    peer_of
    mov     [rax + PEER.open_x], r12d
    mov     [rax + PEER.open_y], r13d
    mov     [rax + PEER.open_z], r14d
    movzx   ecx, byte [r15 + 12]
    mov     [rax + PEER.open_kind], ecx
    mov     esi, [rax + PEER.put_seq]
    mov     edi, ebx
    mov     rdx, [rsp + 8]
    call    cont_data_send
    jmp     .out
.gone:
    mov     [rsp + 8], r12d
    mov     [rsp + 12], r13d
    mov     [rsp + 16], r14d
    mov     edi, ebx
    mov     esi, MT_CONT_GONE
    lea     rdx, [rsp + 8]
    mov     ecx, 12
    mov     r8d, 1
    call    net_send_to
.out:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; nw_on_cont_put(edi from, esi type, rdx payload, ecx len): CONT_PUT {ax, ay, az i32, seq u32,
; slots[108]}. Host. Accepted when that guest has exactly that container open and seq is newer than the
; last one applied from it (a duplicate or an old put is dropped). The 27 cells are taken as they are
; unless a stack is impossible (an unknown item, a count of 0 or above the stack size): those cells
; become empty. The column gets CF_CONTS (it is saved) and every other peer that has the container
; open gets the new record.
; rbx = sender, r12d, r13d, r14d = ax, ay, az, r15 = payload. Frame: [rsp] the record, [rsp + 8] the peer.
nw_on_cont_put:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .out
    cmp     ecx, 124
    jb      .out
    mov     ebx, edi
    mov     r15, rdx
    call    peer_ok
    test    eax, eax
    jz      .out
    mov     edi, ebx
    call    peer_of
    mov     [rsp + 8], rax
    mov     r12d, [r15]
    mov     r13d, [r15 + 4]
    mov     r14d, [r15 + 8]
    cmp     dword [rax + PEER.open_kind], 0
    je      .out
    cmp     [rax + PEER.open_x], r12d
    jne     .out
    cmp     [rax + PEER.open_y], r13d
    jne     .out
    cmp     [rax + PEER.open_z], r14d
    jne     .out
    mov     ecx, [r15 + 12]
    sub     ecx, [rax + PEER.put_seq]
    jle     .out                        ; not newer than the last applied put
    mov     edi, r12d
    sub     edi, [world_origin_x]
    mov     esi, r13d
    mov     edx, r14d
    sub     edx, [world_origin_z]
    call    cont_at
    test    rax, rax
    jz      .out
    mov     [rsp], rax
    xor     ecx, ecx
.cell:
    movzx   eax, byte [r15 + 16 + rcx*4]    ; id
    xor     edx, edx                        ; the cell, empty unless the stack is sound
    cmp     eax, NUM_ITEMS
    jae     .store
    lea     rsi, [item_max_stack]
    movzx   esi, byte [rsi + rax]
    test    esi, esi
    jz      .store                          ; not an item
    movzx   edi, byte [r15 + 17 + rcx*4]    ; count
    test    edi, edi
    jz      .store
    cmp     edi, esi
    ja      .store
    mov     edx, [r15 + 16 + rcx*4]
.store:
    mov     rax, [rsp]
    mov     [rax + CONTAINER.slots + rcx*4], edx
    inc     ecx
    cmp     ecx, 27
    jb      .cell
    mov     rax, [rsp + 8]
    mov     ecx, [r15 + 12]
    mov     [rax + PEER.put_seq], ecx
    mov     edi, r12d
    sar     edi, 4
    mov     esi, r14d
    sar     esi, 4
    call    world_column
    test    rax, rax
    jz      .fan
    or      dword [rax + COLUMN.flags], CF_CONTS
.fan:
    mov     ecx, 1
.peer:
    cmp     ecx, ebx
    je      .next
    mov     edi, ecx
    mov     [rsp + 16], ecx
    call    peer_ok
    test    eax, eax
    jz      .skip
    mov     edi, [rsp + 16]
    call    peer_of
    cmp     dword [rax + PEER.open_kind], 0
    je      .skip
    cmp     [rax + PEER.open_x], r12d
    jne     .skip
    cmp     [rax + PEER.open_y], r13d
    jne     .skip
    cmp     [rax + PEER.open_z], r14d
    jne     .skip
    mov     esi, [rax + PEER.put_seq]
    mov     edi, [rsp + 16]
    mov     rdx, [rsp]
    call    cont_data_send
.skip:
    mov     ecx, [rsp + 16]
.next:
    inc     ecx
    cmp     ecx, NET_MAX_PEERS
    jb      .peer
.out:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; nw_on_cont_close(edi from, esi type, rdx payload, ecx len): CONT_CLOSE. Host: that guest holds no
; container open any more.
nw_on_cont_close:
    sub     rsp, 8
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    call    peer_ok
    test    eax, eax
    jz      .ret
    call    peer_of
    mov     dword [rax + PEER.open_kind], 0
.ret:
    add     rsp, 8
    ret

; net_cont_removed(edi ax, esi ay, edx az) (host): the container at that absolute cell is going away
; (cont_block_removed): every guest that has it open is told (CONT_GONE) and let go.
; Frame: the message at [rsp].
net_cont_removed:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 16
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edx
    mov     ebx, 1
.peer:
    mov     edi, ebx
    call    peer_ok
    test    eax, eax
    jz      .next
    mov     edi, ebx
    call    peer_of
    cmp     dword [rax + PEER.open_kind], 0
    je      .next
    cmp     [rax + PEER.open_x], r12d
    jne     .next
    cmp     [rax + PEER.open_y], r13d
    jne     .next
    cmp     [rax + PEER.open_z], r14d
    jne     .next
    mov     dword [rax + PEER.open_kind], 0
    mov     [rsp], r12d
    mov     [rsp + 4], r13d
    mov     [rsp + 8], r14d
    mov     edi, ebx
    mov     esi, MT_CONT_GONE
    mov     rdx, rsp
    mov     ecx, 12
    mov     r8d, 1
    call    net_send_to
.next:
    inc     ebx
    cmp     ebx, NET_MAX_PEERS
    jb      .peer
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; nw_on_cont_data(edi from, esi type, rdx payload, ecx len): CONT_DATA {ax, ay, az i32, seq u32,
; record[124]}. Guest. A container that is not open opens only as the answer to this guest's own
; CONT_OPEN (net_cont_want; a resend that was already on its way when the guest closed the container
; opens nothing): the record becomes the shadow (and net_cont_sent), the numbering of the guest's puts
; continues from the host's seq, and the game's chest or furnace screen is requested (game_open_cont /
; game_open_screen); the guest waits CONT_GRACE frames for it to show. While a container is open only
; that one is listened to; data older than the last put this guest sent (the host has not seen that put
; yet) is dropped, and so is data that arrives while the shadow holds edits not sent yet (they go out
; first; the next resend brings the host's view).
nw_on_cont_data:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .out
    test    edi, edi
    jnz     .out
    cmp     ecx, 140
    jb      .out
    mov     r12, rdx
    movzx   eax, byte [r12 + 16]
    cmp     eax, CONT_FURNACE
    je      .kind_ok
    cmp     eax, CONT_CHEST
    jne     .out
.kind_ok:
    cmp     dword [net_cont_active], 0
    jne     .update
    cmp     dword [net_cont_want], 0
    je      .out                        ; nobody asked
    mov     eax, [r12]
    cmp     eax, [net_cont_want_x]
    jne     .out
    mov     eax, [r12 + 4]
    cmp     eax, [net_cont_want_y]
    jne     .out
    mov     eax, [r12 + 8]
    cmp     eax, [net_cont_want_z]
    jne     .out
    jmp     .copy
.update:
    mov     eax, [r12 + 12]
    sub     eax, [net_cont_seq]
    js      .out
    mov     eax, [r12]
    cmp     eax, [net_cont_shadow + CONTAINER.x]
    jne     .out
    mov     eax, [r12 + 4]
    cmp     eax, [net_cont_shadow + CONTAINER.y]
    jne     .out
    mov     eax, [r12 + 8]
    cmp     eax, [net_cont_shadow + CONTAINER.z]
    jne     .out
    call    cont_dirty
    test    eax, eax
    jnz     .out
.copy:
    mov     eax, [r12]
    mov     [net_cont_shadow + CONTAINER.x], eax
    mov     eax, [r12 + 4]
    mov     [net_cont_shadow + CONTAINER.y], eax
    mov     eax, [r12 + 8]
    mov     [net_cont_shadow + CONTAINER.z], eax
    lea     rsi, [r12 + 16]
    lea     rdi, [net_cont_shadow + CONTAINER.kind]
    mov     ecx, (CONTAINER_size - CONTAINER.kind) / 4
    rep     movsd
    lea     rsi, [net_cont_shadow]
    lea     rdi, [net_cont_sent]
    mov     ecx, CONTAINER_size / 4
    rep     movsd
    mov     dword [net_guest_dirty], 1
    cmp     dword [net_cont_active], 0
    jne     .out
    mov     dword [net_cont_want], 0
    mov     eax, [r12 + 12]
    mov     [net_cont_seq], eax         ; the host's count: the next put is the next number
    mov     dword [net_cont_active], 1
    mov     dword [net_cont_grace], CONT_GRACE
    lea     rax, [net_cont_shadow]
    mov     [game_open_cont], rax
    mov     eax, ST_CHEST
    mov     ecx, ST_FURNACE
    cmp     byte [net_cont_shadow + CONTAINER.kind], CONT_FURNACE
    cmove   eax, ecx
    mov     [game_open_screen], eax
.out:
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; nw_on_cont_gone(edi from, esi type, rdx payload, ecx len): CONT_GONE {ax, ay, az i32}. Guest: when
; that is the open container, the shadow loses its kind, so that the screen closes by itself
; (container_gone); when it is the one this guest asked for and none is open, the host refused: the
; guest stops waiting.
nw_on_cont_gone:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    test    edi, edi
    jnz     .ret
    cmp     ecx, 12
    jb      .ret
    cmp     dword [net_cont_active], 0
    je      .asked
    mov     eax, [rdx]
    cmp     eax, [net_cont_shadow + CONTAINER.x]
    jne     .ret
    mov     eax, [rdx + 4]
    cmp     eax, [net_cont_shadow + CONTAINER.y]
    jne     .ret
    mov     eax, [rdx + 8]
    cmp     eax, [net_cont_shadow + CONTAINER.z]
    jne     .ret
    mov     byte [net_cont_shadow + CONTAINER.kind], 0
    ret
.asked:
    mov     eax, [rdx]
    cmp     eax, [net_cont_want_x]
    jne     .ret
    mov     eax, [rdx + 4]
    cmp     eax, [net_cont_want_y]
    jne     .ret
    mov     eax, [rdx + 8]
    cmp     eax, [net_cont_want_z]
    jne     .ret
    mov     dword [net_cont_want], 0
.ret:
    ret

; net_cont_close_out() (guest): the open container is closed: a last put when the shadow changed after the
; previous one, then CONT_CLOSE. Both must be queued before the guest lets the container go: while either finds
; no room it stays open and net_cont_frame calls this again next frame (a put dropped here would lose the last
; edit, a close dropped would leave the host holding the container open for it). A screen that never showed is
; called off when the container goes.
net_cont_close_out:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    cmp     dword [net_cont_active], 0
    je      .ret
    push    rbp
    mov     rbp, rsp
    sub     rsp, 16
    call    cont_put_if_dirty
    test    eax, eax
    jz      .out
    mov     edi, MT_CONT_CLOSE
    mov     rsi, rsp
    xor     edx, edx
    mov     ecx, 1
    call    net_out
    test    eax, eax
    jz      .out
    mov     dword [net_cont_active], 0
    lea     rax, [net_cont_shadow]
    cmp     [game_open_cont], rax
    jne     .out
    mov     dword [game_open_screen], 0     ; its screen never opened: it must not open later
    mov     qword [game_open_cont], 0
.out:
    leave
.ret:
    ret

; net_cont_frame(): once per frame (net_pump).
; Guest: outside a world, a new session starts clean. While the container screen of the shadow is up,
; a changed shadow is sent (cont_put_if_dirty). When the screen is gone (it closed, the container
; vanished, or it never showed within CONT_GRACE frames) the guest closes the container.
; Host: every CONT_SYNC frames each guest that has a container open gets its record again; a record
; that is gone ends it (CONT_GONE).
net_cont_frame:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    movzx   eax, byte [net_role]
    cmp     eax, NET_ROLE_GUEST
    je      .guest
    cmp     eax, NET_ROLE_HOST
    jne     .ret
    dec     dword [net_cont_tick]
    jg      .ret
    mov     dword [net_cont_tick], CONT_SYNC
    mov     ebx, 1
.peer:
    mov     edi, ebx
    call    peer_ok
    test    eax, eax
    jz      .next
    mov     edi, ebx
    call    peer_of
    cmp     dword [rax + PEER.open_kind], 0
    je      .next
    mov     r12, rax
    mov     edi, [r12 + PEER.open_x]
    sub     edi, [world_origin_x]
    mov     esi, [r12 + PEER.open_y]
    mov     edx, [r12 + PEER.open_z]
    sub     edx, [world_origin_z]
    call    cont_at
    test    rax, rax
    jz      .vanished
    mov     rdx, rax
    mov     edi, ebx
    mov     esi, [r12 + PEER.put_seq]
    call    cont_data_send
    jmp     .next
.vanished:
    mov     eax, [r12 + PEER.open_x]
    mov     [rsp], eax
    mov     eax, [r12 + PEER.open_y]
    mov     [rsp + 4], eax
    mov     eax, [r12 + PEER.open_z]
    mov     [rsp + 8], eax
    mov     dword [r12 + PEER.open_kind], 0
    mov     edi, ebx
    mov     esi, MT_CONT_GONE
    mov     rdx, rsp
    mov     ecx, 12
    mov     r8d, 1
    call    net_send_to
.next:
    inc     ebx
    cmp     ebx, NET_MAX_PEERS
    jb      .peer
    jmp     .ret
.guest:
    cmp     byte [net_in_world], 0
    jne     .live
    call    nw_guest_reset
    jmp     .ret
.live:
    cmp     dword [net_cont_active], 0
    je      .ret
    mov     eax, [app_state]
    cmp     eax, ST_CHEST
    je      .screen
    cmp     eax, ST_FURNACE
    jne     .absent
.screen:
    lea     rax, [net_cont_shadow]
    cmp     [inv_container], rax
    jne     .absent
    cmp     byte [net_cont_shadow + CONTAINER.kind], 0
    je      .absent                     ; gone: its screen closes itself
    mov     dword [net_cont_grace], 0   ; shown
    call    cont_put_if_dirty
    jmp     .ret
.absent:
    cmp     dword [net_cont_grace], 0
    jle     .close
    dec     dword [net_cont_grace]
    jmp     .ret
.close:
    call    net_cont_close_out
.ret:
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- TNT -------------------------------------------------------------------------------------------------

; net_tnt_prime_out(edi x, esi y, edx z, ecx fuse) (guest): TNT_PRIME {ax, ay, az i32, fuse u16} for the
; (local) cell; the host primes it (its block change comes back as a BLOCK edit)
net_tnt_prime_out:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    push    rbp
    mov     rbp, rsp
    sub     rsp, 16
    mov     eax, [world_origin_x]
    add     eax, edi
    mov     [rsp], eax
    mov     [rsp + 4], esi
    mov     eax, [world_origin_z]
    add     eax, edx
    mov     [rsp + 8], eax
    mov     eax, 1
    test    ecx, ecx
    cmovle  ecx, eax
    mov     eax, 0xFFFF
    cmp     ecx, eax
    cmova   ecx, eax
    mov     [rsp + 12], cx
    mov     edi, MT_TNT_PRIME
    mov     rsi, rsp
    mov     edx, 14
    mov     ecx, 1
    call    net_out
    leave
.ret:
    ret

; nw_on_tnt_prime(edi from, esi type, rdx payload, ecx len): TNT_PRIME {ax, ay, az i32, fuse u16}. Host:
; the cell must still hold TNT; it becomes a primed TNT (tnt_prime, with its own BLOCK edit going out
; through world_set).
nw_on_tnt_prime:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .out
    cmp     ecx, 14
    jb      .out
    mov     r12, rdx
    call    peer_ok
    test    eax, eax
    jz      .out
    mov     ebx, [r12]
    sub     ebx, [world_origin_x]       ; local x
    mov     r13d, [r12 + 8]
    sub     r13d, [world_origin_z]      ; local z
    mov     edi, ebx
    mov     esi, [r12 + 4]
    mov     edx, r13d
    call    world_get
    cmp     eax, TNT
    jne     .out
    mov     edi, ebx
    mov     esi, [r12 + 4]
    mov     edx, r13d
    movzx   ecx, word [r12 + 12]
    call    tnt_prime
.out:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- boats ------------------------------------------------------------------------------------------------

; boat_pose_send(edi slot, esi type, edx reliable): the pose of boat `slot` goes to the host as the
; message `type`: {slot u8, pad[3], NPOS, yaw f32} (24 bytes)
; Frame: the message at [rsp].
boat_pose_send:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 32
    cmp     edi, MAX_BOATS
    jae     .out
    mov     ebx, esi
    mov     r12d, edx
    mov     [rsp], edi                  ; slot, and three zero bytes
    imul    eax, edi, BOATENT_size
    lea     rcx, [boats]
    add     rcx, rax
    mov     eax, [rcx + BODY.yaw]
    mov     [rsp + 20], eax
    movss   xmm0, [rcx + BODY.x]
    movss   xmm1, [rcx + BODY.y]
    movss   xmm2, [rcx + BODY.z]
    lea     rdi, [rsp + 4]
    call    net_pos_out
    mov     edi, ebx
    mov     rsi, rsp
    mov     edx, 24
    mov     ecx, r12d
    call    net_out
.out:
    add     rsp, 32
    pop     r12
    pop     rbx
    pop     rbp
    ret

; net_boat_place_out(rdi eye float[3], rsi dir float[3]) (guest): BOAT_PLACE {eye NPOS, dir f32 x 3}
; Frame: the message at [rsp].
net_boat_place_out:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 40
    mov     rbx, rsi
    movss   xmm0, [rdi]
    movss   xmm1, [rdi + 4]
    movss   xmm2, [rdi + 8]
    lea     rdi, [rsp]
    call    net_pos_out
    mov     eax, [rbx]
    mov     [rsp + 16], eax
    mov     eax, [rbx + 4]
    mov     [rsp + 20], eax
    mov     eax, [rbx + 8]
    mov     [rsp + 24], eax
    mov     edi, MT_BOAT_PLACE
    mov     rsi, rsp
    mov     edx, 28
    mov     ecx, 1
    call    net_out
    add     rsp, 40
    pop     rbx
    pop     rbp
    ret

; net_boat_mount_out(edi slot) (guest): BOAT_MOUNT {slot}; the host answers BOAT_MOUNT_OK
net_boat_mount_out:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 16
    mov     [rsp], dil
    mov     edi, MT_BOAT_MOUNT
    mov     rsi, rsp
    mov     edx, 1
    mov     ecx, 1
    call    net_out
    leave
    ret

; net_boat_break_out(edi slot) (guest): BOAT_BREAK {slot}
net_boat_break_out:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 16
    mov     [rsp], dil
    mov     edi, MT_BOAT_BREAK
    mov     rsi, rsp
    mov     edx, 1
    mov     ecx, 1
    call    net_out
    leave
    ret

; net_boat_dismount_out(edi slot) (guest): BOAT_DISMOUNT {slot, pose}: the boat as the guest leaves it
net_boat_dismount_out:
    mov     esi, MT_BOAT_DISMOUNT
    mov     edx, 1
    jmp     boat_pose_send

; net_boat_tick(): called every SNAP_STEPS steps (net_tick). A guest that rides a boat sends its pose
; (BOAT_POSE, unreliable): the host does not simulate that boat.
net_boat_tick:
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .ret
    mov     edi, [boat_riding]
    dec     edi
    cmp     edi, MAX_BOATS
    jae     .ret                        ; nobody rides (-1 as unsigned)
    mov     esi, MT_BOAT_POSE
    xor     edx, edx
    jmp     boat_pose_send
.ret:
    ret

; boat_pose_apply(rdi payload) -> eax 1 written / 0 refused
; payload = {slot u8, pad[3], NPOS, yaw f32}: boat `slot` takes the pose (local coordinates), its yaw
; brought into [0, 360). A pose with a non-finite value, |x| or |z| of 2^24 or more, or y outside 0..255
; is refused. Frame: [rsp] x, y, z, yaw.
boat_pose_apply:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    mov     r12, rdi
    movzx   eax, byte [rdi]
    cmp     eax, MAX_BOATS
    jae     .no
    imul    eax, eax, BOATENT_size
    lea     rbx, [boats]
    add     rbx, rax
    lea     rdi, [r12 + 4]
    call    net_pos_in
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 8], xmm2
    movss   xmm1, [k_bound]
    call    abs_below
    test    eax, eax
    jz      .no
    movss   xmm0, [rsp + 8]
    movss   xmm1, [k_bound]
    call    abs_below
    test    eax, eax
    jz      .no
    movss   xmm0, [rsp + 4]
    xorps   xmm1, xmm1
    ucomiss xmm0, xmm1
    jb      .no                         ; below 0 (or NaN)
    ucomiss xmm0, [k_256]
    jae     .no
    movss   xmm0, [r12 + 20]
    movss   xmm1, [k_bound]
    call    abs_below
    test    eax, eax
    jz      .no
    movss   xmm0, [r12 + 20]            ; the heading mod 360
    movaps  xmm1, xmm0
    divss   xmm1, [k_360]
    roundss xmm1, xmm1, 9
    mulss   xmm1, [k_360]
    subss   xmm0, xmm1
    ucomiss xmm0, [k_360]
    jb      .yaw_ok
    xorps   xmm0, xmm0
.yaw_ok:
    movss   [rbx + BODY.yaw], xmm0
    mov     eax, [rsp]
    mov     [rbx + BODY.x], eax
    mov     eax, [rsp + 4]
    mov     [rbx + BODY.y], eax
    mov     eax, [rsp + 8]
    mov     [rbx + BODY.z], eax
    mov     eax, 1
    jmp     .out
.no:
    xor     eax, eax
.out:
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; boat_of_rider(edi from, rdx payload) -> rax the BOATENT of boat payload[0] when it is in use and
; that guest rides it, else 0 (host)
boat_of_rider:
    movzx   eax, byte [rdx]
    cmp     eax, MAX_BOATS
    jae     .no
    lea     rcx, [boat_rider]
    inc     edi
    cmp     [rcx + rax], dil
    jne     .no
    imul    eax, eax, BOATENT_size
    lea     rcx, [boats]
    add     rax, rcx
    cmp     dword [rax + BOATENT.used], 0
    jne     .ret
.no:
    xor     eax, eax
.ret:
    ret

; nw_on_boat_pose(edi from, esi type, rdx payload, ecx len): BOAT_POSE {slot, pad[3], NPOS, yaw}.
; Host: the boat that guest rides takes the pose (the host does not simulate it); anything else is
; dropped (an old pose after the dismount).
nw_on_boat_pose:
    sub     rsp, 8
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    cmp     ecx, 24
    jb      .ret
    mov     [rsp], rdx
    call    peer_ok
    test    eax, eax
    jz      .ret
    mov     rdx, [rsp]
    call    boat_of_rider               ; (edi = from, still)
    test    rax, rax
    jz      .ret
    mov     rdi, [rsp]
    call    boat_pose_apply
.ret:
    add     rsp, 8
    ret

; nw_on_boat_dismount(edi from, esi type, rdx payload, ecx len): BOAT_DISMOUNT {slot, pad[3], NPOS, yaw}.
; Host: the guest who rode that boat left it where the pose says; the boat is the host's again, at rest.
nw_on_boat_dismount:
    push    rbx
    sub     rsp, 16
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .out
    cmp     ecx, 24
    jb      .out
    mov     [rsp], rdx
    call    peer_ok
    test    eax, eax
    jz      .out
    mov     rdx, [rsp]
    call    boat_of_rider
    test    rax, rax
    jz      .out
    mov     rbx, rax
    mov     rdi, [rsp]
    call    boat_pose_apply
    mov     rax, [rsp]
    movzx   eax, byte [rax]             ; the boat's slot
    lea     rcx, [boat_rider]
    mov     byte [rcx + rax], 0         ; nobody rides it: the host steps it again, at rest
    mov     dword [rbx + BOATENT.speed], 0
.out:
    add     rsp, 16
    pop     rbx
    ret

; nw_on_boat_mount(edi from, esi type, rdx payload, ecx len): BOAT_MOUNT {slot}. Host: answers
; BOAT_MOUNT_OK {slot, ok}; ok = the boat is in use and either nobody rides it (no guest, and the host
; does not) or the asking guest already does (a double click: the second answer must not take the boat
; away from the guest who sits in it). On a free boat the guest rides it from now on (boat_rider; a
; boat the guest rode before is let go).
; Frame: [rsp] the answer.
nw_on_boat_mount:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .out
    cmp     ecx, 1
    jb      .out
    mov     ebx, edi
    movzx   r12d, byte [rdx]
    call    peer_ok
    test    eax, eax
    jz      .out
    xor     edx, edx                    ; ok
    cmp     r12d, MAX_BOATS
    jae     .answer
    imul    eax, r12d, BOATENT_size
    lea     rcx, [boats]
    cmp     dword [rcx + rax + BOATENT.used], 0
    je      .answer
    lea     rcx, [boat_rider]
    movzx   eax, byte [rcx + r12]
    test    eax, eax
    jz      .free
    lea     esi, [rbx + 1]
    cmp     eax, esi
    jne     .answer                     ; a boat another guest rides
    mov     edx, 1                      ; his own, asked for again: yes again, nothing changes
    jmp     .answer
.free:
    lea     eax, [r12 + 1]
    cmp     eax, [boat_riding]
    je      .answer                     ; the host sits in it
    xor     eax, eax
.release:                               ; the boat that guest rode before is free
    lea     edx, [rbx + 1]
    cmp     [rcx + rax], dl
    jne     .keep
    mov     byte [rcx + rax], 0
.keep:
    inc     eax
    cmp     eax, MAX_BOATS
    jb      .release
    lea     eax, [rbx + 1]
    mov     [rcx + r12], al
    mov     edx, 1
.answer:
    mov     [rsp], r12b
    mov     [rsp + 1], dl
    mov     edi, ebx
    mov     esi, MT_BOAT_MOUNT_OK
    mov     rdx, rsp
    mov     ecx, 2
    mov     r8d, 1
    call    net_send_to
.out:
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; nw_on_boat_mount_ok(edi from, esi type, rdx payload, ecx len): BOAT_MOUNT_OK {slot, ok}. Guest: ok
; seats the player in that boat (boats_mount with net_applying set: no request goes out). Not ok while
; the guest rides that very boat means the host took it away (it was broken): the guest is let go
; where it sits.
nw_on_boat_mount_ok:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .out
    test    edi, edi
    jnz     .out
    cmp     ecx, 2
    jb      .out
    movzx   ebx, byte [rdx]
    cmp     ebx, MAX_BOATS
    jae     .out
    cmp     byte [rdx + 1], 0
    je      .refused
    movzx   eax, byte [net_applying]
    mov     [rsp], eax
    mov     byte [net_applying], 1
    mov     edi, ebx
    call    boats_mount
    mov     eax, [rsp]
    mov     [net_applying], al
    jmp     .out
.refused:
    lea     eax, [rbx + 1]
    cmp     eax, [boat_riding]
    jne     .out
    mov     dword [boat_riding], 0
.out:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; nw_on_boat_break(edi from, esi type, rdx payload, ecx len): BOAT_BREAK {slot}. Host: the boat is
; broken (boats_break: the item drops, a rider is let go).
nw_on_boat_break:
    sub     rsp, 8
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    cmp     ecx, 1
    jb      .ret
    movzx   eax, byte [rdx]
    mov     [rsp], eax
    call    peer_ok
    test    eax, eax
    jz      .ret
    mov     edi, [rsp]
    call    boats_break
.ret:
    add     rsp, 8
    ret

; nw_on_boat_place(edi from, esi type, rdx payload, ecx len): BOAT_PLACE {eye NPOS, dir f32 x 3}.
; Host: boats_place from that eye along that direction, with the heading of the guest's last PSTATE
; (boats_place reads the host's own yaw: it is swapped for the call). A non-finite eye or direction
; is dropped.
; rbx = sender, r12 = payload. Frame: [rsp] eye, [rsp + 16] dir, [rsp + 32] the host's yaw.
nw_on_boat_place:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 48
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .out
    cmp     ecx, 28
    jb      .out
    mov     ebx, edi
    mov     r12, rdx
    call    peer_ok
    test    eax, eax
    jz      .out
    mov     rdi, r12
    call    net_pos_in
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 8], xmm2
    xor     ecx, ecx
.check:                                 ; the eye: three finite coordinates
    movss   xmm0, [rsp + rcx*4]
    movss   xmm1, [k_bound]
    mov     [rsp + 36], ecx
    call    abs_below
    test    eax, eax
    jz      .out
    mov     ecx, [rsp + 36]
    inc     ecx
    cmp     ecx, 3
    jb      .check
    xor     ecx, ecx
.dir:                                   ; the direction: three finite numbers
    mov     eax, [r12 + 16 + rcx*4]
    mov     [rsp + 16 + rcx*4], eax
    movd    xmm0, eax
    movss   xmm1, [k_bound]
    mov     [rsp + 36], ecx
    call    abs_below
    test    eax, eax
    jz      .out
    mov     ecx, [rsp + 36]
    inc     ecx
    cmp     ecx, 3
    jb      .dir
    mov     edi, ebx                    ; the heading: the yaw of the guest's last PSTATE
    call    peer_of
    mov     edx, [rax + PEER.ps + PSTATE.yaw]
    movd    xmm0, edx
    movss   xmm1, [k_bound]
    call    abs_below                   ; (keeps edx)
    xor     ecx, ecx
    test    eax, eax
    cmovz   edx, ecx                    ; not a number: it heads north
    mov     eax, [player + BODY.yaw]
    mov     [rsp + 32], eax
    mov     [player + BODY.yaw], edx
    movzx   eax, byte [net_applying]    ; a guest's request, not the host's own click: no banner
    mov     [rsp + 36], eax
    mov     byte [net_applying], 1
    lea     rdi, [rsp]
    lea     rsi, [rsp + 16]
    call    boats_place
    mov     r12d, eax
    mov     eax, [rsp + 36]
    mov     [net_applying], al
    mov     eax, [rsp + 32]
    mov     [player + BODY.yaw], eax
    test    r12d, r12d
    jnz     .out
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .out                        ; (in Creative the guest's boat item was not used up)
    mov     edi, ebx
    mov     esi, BOAT
    mov     edx, 1
    xor     ecx, ecx
    call    net_give_out                ; no boat could be put there (the table is full, ...): the item comes back
.out:
    add     rsp, 48
    pop     r12
    pop     rbx
    pop     rbp
    ret
