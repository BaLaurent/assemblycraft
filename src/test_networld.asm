; test_networld.asm - the world on the wire: block edits that wait for their column (and the answers a guest
; holds for it), the guest's column verdicts, the container puts with their sequence numbers, sends that find
; no room, flames in a column, boats and the edit queue's columns. The network is the capture seam of netsync
; (net_capture / net_captured: records slot u8, type u8, len u16, payload[len]); a send that must fail is
; made to by capturing into a buffer too small for it (cap_small).
%include "common.inc"
default rel

global test_net_edit_queue_replay, test_net_column_verdict, test_net_container_put_seq
global test_net_stale_verdict, test_net_block_overflow, test_net_cont_close_retry, test_net_fire_in_column
global test_net_boat_double_mount, test_net_fire_guest_step, test_net_column_expiry, test_net_boat_giveback
global test_net_edit_columns, test_net_plane_seats, test_net_plane_msgs, test_net_plane_pose, test_net_plane_rec
global test_net_plane_leave, test_net_plane_crash, test_net_plane_place

extern net_role, net_in_world, net_peers
extern net_capture, net_captured
extern nw_apply_edit, net_edits_replay, net_edit_n
extern net_column_verdict, net_column_take, net_column_forget, net_colv_pending, net_colbuf_used
extern nw_on_col_data, nw_on_col_pristine
extern net_cont_frame, net_cont_shadow, net_cont_sent, net_cont_seq, net_cont_active
extern nw_on_cont_open, nw_on_cont_data, nw_on_cont_gone, nw_on_cont_put, nw_on_cont_close, net_cont_removed
extern net_cont_open_out
extern world_clear, world_set, world_get, world_column, world_column_claim, world_install
extern region_encode_column, blob_buf
extern cont_at, cont_create
extern app_state, inv_container, game_open_cont, game_open_screen
extern net_dirty_n, net_bq_n, net_edit_columns, net_block_out, net_host_columns_serve, net_cont_close_out
extern nw_on_col_req, nw_on_block, nw_on_boat_mount, nw_on_boat_place
extern boats, boats_clear, boat_rider
extern planes, planes_clear, plane_riding, plane_seat, plane_tgt, planes_crash, net_handlers, plane_pose_apply
extern nw_on_plane_place, nw_on_plane_board, nw_on_plane_board_ok, nw_on_plane_leave, nw_on_plane_pose
extern nw_on_plane_break, nm_on_snap_planes, nm_plane_enc, nm_plane_dec
extern fires, fire_clear, fire_place, fire_track, fire_guest_step
extern banner_text
extern game_mode, player, body_init, survival_reset, surv
extern net_ep, net_ep_open, net_ep_close, net_ep_accept, net_pos_out
extern world_unload

%define STK(id, n, dmg) ((id) | ((n) << 8) | ((dmg) << 16))
%define CAP_SIZE 8192
%define NEDIT_TTL 600                   ; frames a queued edit waits (networld.asm)
%define COLV_IDLE_FRAMES 600            ; frames a guest keeps an answer nobody asks about (networld.asm)
%define COLV_TIMEOUT_FRAMES 3600        ; frames a guest waits for an answer before it asks again
%define CONT_GRACE_FRAMES 3             ; frames a container screen may take to show (networld.asm)

; EDIT ax, y, az, id, from: nw_apply_edit -> eax
%macro EDIT 5
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    mov     r8d, %5
    call    nw_apply_edit
%endmacro

; EXPECT_BLOCK x, y, z, id
%macro EXPECT_BLOCK 4
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    call    world_get
    cmp     eax, %4
    jne     .fail
%endmacro

; EXPECT_D dword operand, value
%macro EXPECT_D 2
    cmp     dword %1, %2
    jne     .fail
%endmacro

; EXPECT_CAP n, slot, type, len: capture record n exists and has that header (rax = the record, its
; payload at rax + 4)
%macro EXPECT_CAP 4
    mov     edi, %1
    call    cap_rec
    test    rax, rax
    jz      .fail
    cmp     byte [rax], %2
    jne     .fail
    cmp     byte [rax + 1], %3
    jne     .fail
    cmp     word [rax + 2], %4
    jne     .fail
%endmacro

; EXPECT_NO_CAP n: there is no capture record n
%macro EXPECT_NO_CAP 1
    mov     edi, %1
    call    cap_rec
    test    rax, rax
    jnz     .fail
%endmacro

; EXPECT_CAPT n, slot, type: as EXPECT_CAP, whatever the length
%macro EXPECT_CAPT 3
    mov     edi, %1
    call    cap_rec
    test    rax, rax
    jz      .fail
    cmp     byte [rax], %2
    jne     .fail
    cmp     byte [rax + 1], %3
    jne     .fail
%endmacro

; SETB x, y, z, id: world_set
%macro SETB 4
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    call    world_set
%endmacro

%if PEER_size % 8 != 0 || GENBUF_size % 8 != 0
%error "the tests clear PEER and GENBUF with rep stosq"
%endif

section .rodata
align 4
k_half_w: dd 0.3
k_height: dd 1.8
k_speed:  dd 4.317
k_5_5:    dd 5.5
k_11:     dd 11.0
k_70_5:   dd 70.5
k_22:     dd 22.0
k_m1:     dd -1.0
kp_nan:   dd 0x7FC00000
kp_300:   dd 300.0
kp_12_5:  dd 12.5
kp_13_5:  dd 13.5
kp_110_5: dd 110.5
kp_10_5:  dd 10.5
kp_20_5:  dd 20.5
kp_90:    dd 90.0
kp_70_5:  dd 70.5
kp_9_5:   dd 9.5
; the plane messages and the handlers the dispatch table must hold for them
plane_ids: dd MT_PLANE_PLACE, MT_PLANE_BOARD, MT_PLANE_BOARD_OK, MT_PLANE_LEAVE, MT_PLANE_POSE, MT_PLANE_BREAK, MT_SNAP_PLANES
plane_hs:  dq nw_on_plane_place, nw_on_plane_board, nw_on_plane_board_ok, nw_on_plane_leave, nw_on_plane_pose
           dq nw_on_plane_break, nm_on_snap_planes

section .bss
alignb 16
cap_buf:   resb CAP_SIZE
cd_buf:    resb 65536
small_buf: resb 64
save_player: resb BODY_size
save_surv:   resb SURVIVAL_size
save_banner: resb 64
genbuf:    resb GENBUF_size

section .text

; cap_on(): capture from here on (the count starts at 0)
cap_on:
    sub     rsp, 8
    lea     rdi, [cap_buf]
    mov     esi, CAP_SIZE
    call    net_capture
    mov     dword [net_captured], 0
    add     rsp, 8
    ret

; cap_off(): back to the real network
cap_off:
    sub     rsp, 8
    xor     edi, edi
    xor     esi, esi
    call    net_capture
    add     rsp, 8
    ret

; cap_rec(edi n) -> rax the n-th captured record (0 = the first), or 0 when there are fewer
cap_rec:
    lea     rax, [cap_buf]
    mov     ecx, [net_captured]
    lea     rdx, [rax + rcx]
.l:
    cmp     rax, rdx
    jae     .none
    test    edi, edi
    jz      .ret
    movzx   ecx, word [rax + 2]
    lea     rax, [rax + rcx + 4]
    dec     edi
    jmp     .l
.none:
    xor     eax, eax
.ret:
    ret

; cap_count() -> eax records captured
cap_count:
    lea     rax, [cap_buf]
    mov     ecx, [net_captured]
    lea     rdx, [rax + rcx]
    xor     esi, esi
.l:
    cmp     rax, rdx
    jae     .ret
    movzx   ecx, word [rax + 2]
    lea     rax, [rax + rcx + 4]
    inc     esi
    jmp     .l
.ret:
    mov     eax, esi
    ret

; ---- net_edit_queue_replay ------------------------------------------------------------------------------
; A guest's edit for a column that is loaded but not lit is queued and applied once the column is lit; for a
; column nobody has loaded or asked for it is dropped; nothing is sent. The host queues too, relays the cell
; to the guests when it applies it, lets an edit time out after NEDIT_TTL frames, relays nothing for a cell
; that already holds the block, and drops a bad y or block id.
test_net_edit_queue_replay:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    world_clear
    mov     byte [net_in_world], 1
    mov     dword [net_edit_n], 0
    mov     edi, 3
    mov     esi, 3
    call    world_column                ; column (3, 3): cells 48..63
    test    rax, rax
    jz      .fail
    mov     rbx, rax
    ; ---- guest ----
    mov     byte [net_role], NET_ROLE_GUEST
    call    cap_on
    mov     dword [rbx + COLUMN.state], COL_BLOCKS
    EDIT    53, 40, 55, STONE, 0
    test    eax, eax
    jnz     .fail                       ; queued: not applied
    EXPECT_D [net_edit_n], 1
    call    net_edits_replay            ; not lit yet: it waits
    EXPECT_D [net_edit_n], 1
    mov     dword [rbx + COLUMN.state], COL_LIT
    EXPECT_BLOCK 53, 40, 55, AIR
    call    net_edits_replay
    EXPECT_D [net_edit_n], 0
    EXPECT_BLOCK 53, 40, 55, STONE
    ; the order is kept: the column lights up, but an older edit of it still waits, so a newer one goes behind
    mov     dword [rbx + COLUMN.state], COL_BLOCKS
    EDIT    53, 42, 55, STONE, 0
    mov     dword [rbx + COLUMN.state], COL_LIT
    EDIT    53, 42, 55, AIR, 0
    test    eax, eax
    jnz     .fail                       ; queued behind the first, not applied before it
    EXPECT_D [net_edit_n], 2
    call    net_edits_replay
    EXPECT_D [net_edit_n], 0
    EXPECT_BLOCK 53, 42, 55, AIR        ; the later edit won
    EDIT    641, 40, 641, STONE, 0      ; column (40, 40): not loaded, not asked for
    test    eax, eax
    jnz     .fail
    EXPECT_D [net_edit_n], 0            ; dropped
    EXPECT_D [net_captured], 0          ; and nothing went out
    ; a column whose answer is pending takes the edit; once the column is forgotten, it goes
    mov     edi, 40
    mov     esi, 40
    call    net_column_verdict
    test    eax, eax
    jnz     .fail
    EDIT    641, 40, 641, STONE, 0
    EXPECT_D [net_edit_n], 1
    mov     edi, 40
    mov     esi, 40
    call    net_column_forget
    call    net_edits_replay
    EXPECT_D [net_edit_n], 0
    ; ---- host ----
    mov     byte [net_role], NET_ROLE_HOST
    lea     rax, [net_peers + PEER_size]
    mov     dword [rax + PEER.state], PEER_READY
    call    cap_on
    mov     dword [rbx + COLUMN.state], COL_BLOCKS
    EDIT    53, 41, 55, DIRT, 1
    test    eax, eax
    jnz     .fail
    EXPECT_D [net_edit_n], 1
    EXPECT_D [net_captured], 0          ; nothing relayed before it is applied
    mov     dword [rbx + COLUMN.state], COL_LIT
    call    net_edits_replay
    EXPECT_D [net_edit_n], 0
    EXPECT_BLOCK 53, 41, 55, DIRT
    EXPECT_CAP 0, 1, MT_BLOCK, 10      ; relayed to every guest (one send each: slot 1 is the one there is)
    EXPECT_D [rax + 4], 53
    EXPECT_D [rax + 8], 55
    cmp     byte [rax + 12], 41
    jne     .fail
    cmp     byte [rax + 13], DIRT
    jne     .fail
    EXPECT_NO_CAP 1
    call    cap_on
    EDIT    53, 41, 55, DIRT, 1         ; the cell already holds it: applied, nothing relayed
    cmp     eax, 1
    jne     .fail
    EXPECT_D [net_captured], 0
    mov     dword [rbx + COLUMN.state], COL_BLOCKS
    EDIT    54, 41, 55, DIRT, 1         ; waits for a column that never lights up
    EXPECT_D [net_edit_n], 1
    mov     r12d, NEDIT_TTL - 1
.wait:
    call    net_edits_replay
    dec     r12d
    jnz     .wait
    EXPECT_D [net_edit_n], 1            ; one frame left
    call    net_edits_replay
    EXPECT_D [net_edit_n], 0            ; timed out
    EXPECT_D [net_dirty_n + 4], 1       ; its guest never saw it applied: it is to fetch the column afresh
    mov     dword [net_dirty_n + 4], 0
    EDIT    53, 300, 55, STONE, 1       ; y outside the world: dropped, not queued
    EXPECT_D [net_edit_n], 0
    EDIT    53, 41, 55, NUM_BLOCKS, 1   ; no such block
    EXPECT_D [net_edit_n], 0
    mov     edi, 800                    ; the ring: the 1025th edit pushes the oldest out (column (50, 50), not loaded)
    mov     esi, 41
    mov     edx, 800
    mov     ecx, STONE
    mov     r8d, 1
    call    nw_apply_edit
    mov     r12d, 1024
.ring:
    mov     edi, 801
    mov     esi, 41
    mov     edx, 801
    mov     ecx, STONE
    mov     r8d, 2
    call    nw_apply_edit
    dec     r12d
    jnz     .ring
    EXPECT_D [net_edit_n], 1024
    EXPECT_D [net_dirty_n + 4], 1       ; the guest whose edit was lost is to fetch its column afresh
    EXPECT_D [net_dirty_n + 8], 0
    mov     dword [net_edit_n], 0
    mov     dword [rbx + COLUMN.state], COL_LIT
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    mov     byte [net_role], NET_ROLE_OFF
    mov     byte [net_in_world], 0
    mov     dword [net_edit_n], 0
    call    peers_free
    call    cap_off
    call    world_clear
    mov     eax, ebx
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- net_column_verdict -----------------------------------------------------------------------------------
; The first query asks the host (one COL_REQ) and answers 0, a second one asks nothing; the host's
; "pristine" makes the verdict 1; a blob from region_encode_column makes it 2 and net_column_take decodes it
; into a GENBUF that installs, with its blocks and its container; the entry is gone after the take. At most 64
; requests are pending; a blob with no free buffer forgets its entry.
test_net_column_verdict:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    world_clear
    ; the column (2, 2) of the arena gets three blocks and a chest holding coal
    mov     edi, 33
    mov     esi, 50
    mov     edx, 34
    mov     ecx, STONE
    call    world_set
    mov     edi, 36
    mov     esi, 51
    mov     edx, 37
    mov     ecx, DIRT
    call    world_set
    mov     edi, 47
    mov     esi, 52
    mov     edx, 32
    mov     ecx, PLANKS
    call    world_set
    mov     edi, 35
    mov     esi, 60
    mov     edx, 35
    mov     ecx, CHEST
    call    world_set
    mov     edi, 35
    mov     esi, 60
    mov     edx, 35
    mov     ecx, CONT_CHEST
    call    cont_create
    test    rax, rax
    jz      .fail
    mov     dword [rax + CONTAINER.slots], STK(COAL, 5, 0)
    mov     edi, 2
    mov     esi, 2
    call    world_column
    test    rax, rax
    jz      .fail
    mov     rdi, rax
    call    region_encode_column        ; the blob, in blob_buf
    cmp     eax, 8
    jb      .fail
    mov     r12d, eax                   ; its length
    lea     rdi, [cd_buf + 8]
    lea     rsi, [blob_buf]
    mov     ecx, r12d
    rep     movsb
    mov     dword [cd_buf], 42          ; COL_DATA {42, 43, blob}
    mov     dword [cd_buf + 4], 43
    mov     byte [net_in_world], 1
    mov     byte [net_role], NET_ROLE_GUEST
    call    cap_on
    ; ---- asking ----
    mov     edi, 40
    mov     esi, 41
    call    net_column_verdict
    test    eax, eax
    jnz     .fail                       ; pending
    EXPECT_CAP 0, 255, MT_COL_REQ, 8
    EXPECT_D [rax + 4], 40
    EXPECT_D [rax + 8], 41
    mov     edi, 40
    mov     esi, 41
    call    net_column_verdict
    test    eax, eax
    jnz     .fail                       ; still pending
    EXPECT_NO_CAP 1                     ; and not asked again
    ; ---- pristine ----
    mov     dword [small_buf], 40
    mov     dword [small_buf + 4], 41
    xor     edi, edi
    mov     esi, MT_COL_PRISTINE
    lea     rdx, [small_buf]
    mov     ecx, 8
    call    nw_on_col_pristine
    mov     edi, 40
    mov     esi, 41
    call    net_column_verdict
    cmp     eax, 1
    jne     .fail
    EXPECT_NO_CAP 1
    ; ---- data ----
    mov     edi, 42
    mov     esi, 43
    call    net_column_verdict
    test    eax, eax
    jnz     .fail
    EXPECT_CAP 1, 255, MT_COL_REQ, 8
    EXPECT_D [rax + 4], 42
    EXPECT_D [rax + 8], 43
    xor     edi, edi
    mov     esi, MT_COL_DATA
    lea     rdx, [cd_buf]
    lea     ecx, [r12 + 8]
    call    nw_on_col_data
    mov     edi, 42
    mov     esi, 43
    call    net_column_verdict
    cmp     eax, 2
    jne     .fail
    mov     edi, 42
    mov     esi, 43
    lea     rdx, [genbuf]
    call    net_column_take
    cmp     eax, 1
    jne     .fail
    EXPECT_D [genbuf + GENBUF.cx], 42
    EXPECT_D [genbuf + GENBUF.cz], 43
    cmp     byte [genbuf + GENBUF.blocks + ((50 << 8) | (2 << 4) | 1)], STONE
    jne     .fail
    cmp     byte [genbuf + GENBUF.blocks + ((51 << 8) | (5 << 4) | 4)], DIRT
    jne     .fail
    cmp     byte [genbuf + GENBUF.blocks + ((52 << 8) | 15)], PLANKS
    jne     .fail
    cmp     byte [genbuf + GENBUF.blocks + ((60 << 8) | (3 << 4) | 3)], CHEST
    jne     .fail
    EXPECT_D [genbuf + GENBUF.nconts], 1
    EXPECT_D [genbuf + GENBUF.conts + CONTAINER.x], 42 * 16 + 3
    EXPECT_D [genbuf + GENBUF.conts + CONTAINER.y], 60
    EXPECT_D [genbuf + GENBUF.conts + CONTAINER.z], 43 * 16 + 3
    cmp     byte [genbuf + GENBUF.conts + CONTAINER.kind], CONT_CHEST
    jne     .fail
    EXPECT_D [genbuf + GENBUF.conts + CONTAINER.slots], STK(COAL, 5, 0)
    ; the GENBUF installs
    mov     edi, 42
    mov     esi, 43
    call    world_column_claim
    test    rax, rax
    jz      .fail
    lea     rdi, [genbuf]
    call    world_install
    test    eax, eax
    jnz     .fail
    mov     edi, 42
    mov     esi, 43
    call    world_column
    test    rax, rax
    jz      .fail
    mov     dword [rax + COLUMN.state], COL_LIT
    EXPECT_BLOCK 42 * 16 + 1, 50, 43 * 16 + 2, STONE
    mov     edi, 42 * 16 + 3
    mov     esi, 60
    mov     edx, 43 * 16 + 3
    call    cont_at
    test    rax, rax
    jz      .fail
    EXPECT_D [rax + CONTAINER.slots], STK(COAL, 5, 0)
    ; the entry went with the take: a second take finds nothing, a new verdict asks again
    mov     edi, 42
    mov     esi, 43
    lea     rdx, [genbuf]
    call    net_column_take
    test    eax, eax
    jnz     .fail
    mov     edi, 42
    mov     esi, 43
    call    net_column_verdict
    test    eax, eax
    jnz     .fail
    EXPECT_CAP 2, 255, MT_COL_REQ, 8
    mov     edi, 42
    mov     esi, 43
    call    net_column_forget
    mov     edi, 40
    mov     esi, 41
    call    net_column_forget
    EXPECT_D [net_colv_pending], 0
    ; ---- limits: 64 requests pending, 32 blobs held ----
    call    cap_on
    xor     r13d, r13d
.ask:
    lea     edi, [r13 + 100]
    mov     esi, 100
    call    net_column_verdict
    test    eax, eax
    jnz     .fail
    inc     r13d
    cmp     r13d, 70
    jb      .ask
    EXPECT_D [net_colv_pending], 64
    call    cap_count
    cmp     eax, 64
    jne     .fail                       ; the last 6 asked nothing
    mov     dword [cd_buf + 8], 0x394C4F43  ; (not a real blob: it is only stored here)
    mov     dword [cd_buf + 12], 0
    xor     r13d, r13d
.answer:
    lea     eax, [r13 + 100]
    mov     [cd_buf], eax
    mov     dword [cd_buf + 4], 100
    xor     edi, edi
    mov     esi, MT_COL_DATA
    lea     rdx, [cd_buf]
    mov     ecx, 16
    call    nw_on_col_data
    inc     r13d
    cmp     r13d, 33
    jb      .answer
    EXPECT_D [net_colbuf_used], -1      ; 32 buffers hold blobs
    EXPECT_D [net_colv_pending], 31     ; the 33rd blob took the buffer of the one asked about least recently
    mov     edi, 132
    mov     esi, 100
    call    net_column_verdict
    cmp     eax, 2
    jne     .fail                       ; the new blob is held
    mov     edi, 100
    mov     esi, 100
    call    net_column_verdict
    test    eax, eax
    jnz     .fail                       ; the oldest gave its buffer up ...
    call    cap_count
    cmp     eax, 65
    jne     .fail                       ; ... and is asked for again
    xor     r13d, r13d
.forget:
    lea     edi, [r13 + 100]
    mov     esi, 100
    call    net_column_forget
    inc     r13d
    cmp     r13d, 70
    jb      .forget
    EXPECT_D [net_colv_pending], 0
    EXPECT_D [net_colbuf_used], 0
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    mov     byte [net_role], NET_ROLE_OFF
    mov     byte [net_in_world], 0
    call    cap_off
    call    world_clear
    mov     eax, ebx
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- net_container_put_seq --------------------------------------------------------------------------------
; Guest: a CONT_DATA opens the shadow and asks for the chest screen; an edit of the shadow sends CONT_PUT with
; sequence 1; a CONT_DATA with sequence 0 (older than that put) does not overwrite the shadow, one with
; sequence 1 does, unless the shadow holds edits not sent yet; leaving the screen sends CONT_CLOSE once; a
; screen that never shows is called off after a grace period. Host: CONT_OPEN answers the record, CONT_PUT
; applies a newer sequence number only (and from a peer that has the container open), cleans impossible
; stacks, tells the other peers, CONT_CLOSE and net_cont_removed let go.
; Frame: [rsp] app_state, [rsp + 8] inv_container as they were.
test_net_container_put_seq:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 24
    call    world_clear
    mov     eax, [app_state]
    mov     [rsp], eax
    mov     rax, [inv_container]
    mov     [rsp + 8], rax
    ; ---- guest ----
    mov     byte [net_in_world], 1
    mov     byte [net_role], NET_ROLE_GUEST
    call    cap_on
    lea     rdi, [cd_buf]               ; CONT_DATA {100, 64, 100, seq 0, a chest holding 5 coal}
    xor     eax, eax
    mov     ecx, 140 / 4
    rep     stosd
    mov     dword [cd_buf], 100
    mov     dword [cd_buf + 4], 64
    mov     dword [cd_buf + 8], 100
    mov     byte [cd_buf + 16], CONT_CHEST
    mov     dword [cd_buf + 20], STK(COAL, 5, 0)
    call    send_data                   ; nobody asked for it: nothing opens
    EXPECT_D [net_cont_active], 0
    EXPECT_D [game_open_screen], 0
    call    open_chest                  ; the player clicks the chest
    EXPECT_CAP 0, 255, MT_CONT_OPEN, 13
    EXPECT_D [rax + 4], 100
    EXPECT_D [rax + 8], 64
    EXPECT_D [rax + 12], 100
    cmp     byte [rax + 16], CONT_CHEST
    jne     .fail
    call    cap_on
    call    send_data                   ; the host's answer opens it
    cmp     byte [net_cont_shadow + CONTAINER.kind], CONT_CHEST
    jne     .fail
    EXPECT_D [net_cont_shadow + CONTAINER.x], 100
    EXPECT_D [net_cont_shadow + CONTAINER.y], 64
    EXPECT_D [net_cont_shadow + CONTAINER.z], 100
    EXPECT_D [net_cont_shadow + CONTAINER.slots], STK(COAL, 5, 0)
    EXPECT_D [net_cont_sent + CONTAINER.slots], STK(COAL, 5, 0)
    EXPECT_D [game_open_screen], ST_CHEST
    lea     rax, [net_cont_shadow]
    cmp     [game_open_cont], rax
    jne     .fail
    ; the screen is up
    mov     dword [game_open_screen], 0
    mov     qword [game_open_cont], 0
    mov     dword [app_state], ST_CHEST
    lea     rax, [net_cont_shadow]
    mov     [inv_container], rax
    call    net_cont_frame
    EXPECT_NO_CAP 0                     ; nothing changed: nothing sent
    mov     dword [net_cont_shadow + CONTAINER.slots + 4], STK(COAL, 3, 0)
    call    net_cont_frame
    EXPECT_CAP 0, 255, MT_CONT_PUT, 124
    EXPECT_D [rax + 4], 100
    EXPECT_D [rax + 8], 64
    EXPECT_D [rax + 12], 100
    EXPECT_D [rax + 16], 1              ; sequence 1
    EXPECT_D [rax + 20], STK(COAL, 5, 0)
    EXPECT_D [rax + 24], STK(COAL, 3, 0)
    EXPECT_D [net_cont_seq], 1
    EXPECT_D [net_cont_sent + CONTAINER.slots + 4], STK(COAL, 3, 0)
    call    net_cont_frame
    EXPECT_NO_CAP 1                     ; sent once
    ; a CONT_DATA older than that put is not applied; one with its number is
    mov     dword [cd_buf + 12], 0
    mov     dword [cd_buf + 20], STK(COAL, 5, 0)
    mov     dword [cd_buf + 24], STK(COAL, 3, 0)
    mov     dword [cd_buf + 28], STK(COAL, 1, 0)    ; cell 2
    call    send_data
    EXPECT_D [net_cont_shadow + CONTAINER.slots + 8], 0
    mov     dword [cd_buf + 12], 1
    call    send_data
    EXPECT_D [net_cont_shadow + CONTAINER.slots + 8], STK(COAL, 1, 0)
    EXPECT_D [net_cont_sent + CONTAINER.slots + 8], STK(COAL, 1, 0)
    ; edits not sent yet are not overwritten
    mov     dword [net_cont_shadow + CONTAINER.slots + 12], STK(COAL, 2, 0)     ; cell 3
    mov     dword [cd_buf + 36], STK(COAL, 9, 0)                                ; the host says cell 4
    call    send_data
    EXPECT_D [net_cont_shadow + CONTAINER.slots + 16], 0
    EXPECT_D [net_cont_shadow + CONTAINER.slots + 12], STK(COAL, 2, 0)
    call    net_cont_frame
    EXPECT_CAP 1, 255, MT_CONT_PUT, 124
    EXPECT_D [rax + 16], 2
    EXPECT_D [rax + 32], STK(COAL, 2, 0)    ; cell 3
    ; the screen closes: CONT_CLOSE, once
    mov     dword [app_state], ST_PLAYING
    mov     qword [inv_container], 0
    call    net_cont_frame
    EXPECT_CAP 2, 255, MT_CONT_CLOSE, 0
    EXPECT_D [net_cont_active], 0
    call    net_cont_frame
    EXPECT_NO_CAP 3
    mov     dword [cd_buf + 12], 2      ; a resend that was on its way when it closed: opens nothing
    mov     dword [cd_buf + 36], 0
    call    send_data
    EXPECT_D [net_cont_active], 0
    EXPECT_D [game_open_screen], 0
    ; the container vanishes: CONT_GONE for another cell changes nothing, for this one the shadow loses its kind
    mov     dword [cd_buf + 12], 5      ; the host counts 5 puts of this guest
    call    open_chest
    call    send_data                   ; opens it again: the numbering continues from the host's count
    EXPECT_D [net_cont_active], 1
    EXPECT_D [net_cont_seq], 5
    mov     dword [game_open_screen], 0
    mov     qword [game_open_cont], 0
    mov     dword [app_state], ST_CHEST
    lea     rax, [net_cont_shadow]
    mov     [inv_container], rax
    call    cap_on
    mov     dword [net_cont_shadow + CONTAINER.slots + 4], STK(COAL, 1, 0)
    call    net_cont_frame
    EXPECT_CAP 0, 255, MT_CONT_PUT, 124
    EXPECT_D [rax + 16], 6
    mov     dword [app_state], ST_PLAYING
    mov     qword [inv_container], 0
    mov     dword [game_open_screen], 0
    mov     qword [game_open_cont], 0
    mov     dword [small_buf], 101
    mov     dword [small_buf + 4], 64
    mov     dword [small_buf + 8], 100
    xor     edi, edi
    mov     esi, MT_CONT_GONE
    lea     rdx, [small_buf]
    mov     ecx, 12
    call    nw_on_cont_gone
    cmp     byte [net_cont_shadow + CONTAINER.kind], CONT_CHEST
    jne     .fail
    mov     dword [small_buf], 100
    xor     edi, edi
    mov     esi, MT_CONT_GONE
    lea     rdx, [small_buf]
    mov     ecx, 12
    call    nw_on_cont_gone
    cmp     byte [net_cont_shadow + CONTAINER.kind], 0
    jne     .fail
    ; a screen that never shows is called off after the grace period (3 frames)
    mov     dword [net_cont_active], 0
    call    open_chest
    call    cap_on
    call    send_data
    EXPECT_D [game_open_screen], ST_CHEST
    mov     r13d, 3
.grace:
    call    net_cont_frame
    dec     r13d
    jnz     .grace
    EXPECT_NO_CAP 0
    call    net_cont_frame
    EXPECT_CAP 0, 255, MT_CONT_CLOSE, 0
    EXPECT_D [game_open_screen], 0
    EXPECT_D [net_cont_active], 0
    ; the host refuses (CONT_GONE for the cell asked for): the guest stops waiting
    call    open_chest
    xor     edi, edi
    mov     esi, MT_CONT_GONE
    lea     rdx, [small_buf]
    mov     ecx, 12
    call    nw_on_cont_gone
    call    send_data
    EXPECT_D [net_cont_active], 0
    EXPECT_D [game_open_screen], 0
    ; ---- host ----
    mov     byte [net_role], NET_ROLE_OFF
    mov     edi, 100
    mov     esi, 64
    mov     edx, 100
    mov     ecx, CHEST
    call    world_set
    mov     byte [net_role], NET_ROLE_HOST
    lea     rax, [net_peers + PEER_size]
    mov     dword [rax + PEER.state], PEER_READY
    lea     rax, [net_peers + 2 * PEER_size]
    mov     dword [rax + PEER.state], PEER_READY
    lea     rax, [net_peers + 3 * PEER_size]
    mov     dword [rax + PEER.state], PEER_READY
    call    cap_on
    mov     dword [cd_buf], 100         ; CONT_OPEN {100, 64, 100, chest}
    mov     dword [cd_buf + 4], 64
    mov     dword [cd_buf + 8], 100
    mov     byte [cd_buf + 12], CONT_CHEST
    mov     edi, 1
    call    host_open
    EXPECT_CAP 0, 1, MT_CONT_DATA, 140
    EXPECT_D [rax + 4], 100
    cmp     byte [rax + 20], CONT_CHEST
    jne     .fail
    mov     edi, 100
    mov     esi, 64
    mov     edx, 100
    call    cont_at
    test    rax, rax
    jz      .fail                       ; the record was made
    mov     rbx, rax
    mov     edi, 2
    call    host_open                   ; peer 2 has it open as well
    EXPECT_CAP 1, 2, MT_CONT_DATA, 140
    mov     edi, 1                      ; peer 1 puts, sequence 1: 7 coal in cell 0, an impossible stack in cell 5
    mov     esi, 1
    mov     edx, STK(COAL, 7, 0)
    mov     ecx, 255 | (3 << 8)
    call    host_put
    EXPECT_D [rbx + CONTAINER.slots], STK(COAL, 7, 0)
    EXPECT_D [rbx + CONTAINER.slots + 20], 0
    lea     rax, [net_peers + PEER_size]
    EXPECT_D [rax + PEER.put_seq], 1
    mov     edi, 6
    mov     esi, 6
    call    world_column
    test    rax, rax
    jz      .fail
    test    dword [rax + COLUMN.flags], CF_CONTS
    jz      .fail                       ; the column is saved
    EXPECT_CAP 2, 2, MT_CONT_DATA, 140  ; the other peer gets the record, the sender does not
    EXPECT_D [rax + 24], STK(COAL, 7, 0)
    EXPECT_D [rax + 44], 0
    EXPECT_NO_CAP 3
    mov     edi, 1                      ; the same number again: ignored
    mov     esi, 1
    mov     edx, STK(COAL, 9, 0)
    xor     ecx, ecx
    call    host_put
    EXPECT_D [rbx + CONTAINER.slots], STK(COAL, 7, 0)
    mov     edi, 1                      ; an older one: ignored
    xor     esi, esi
    mov     edx, STK(COAL, 9, 0)
    xor     ecx, ecx
    call    host_put
    EXPECT_D [rbx + CONTAINER.slots], STK(COAL, 7, 0)
    mov     edi, 3                      ; a peer that has nothing open: ignored
    mov     esi, 1
    mov     edx, STK(COAL, 9, 0)
    xor     ecx, ecx
    call    host_put
    EXPECT_D [rbx + CONTAINER.slots], STK(COAL, 7, 0)
    mov     edi, 1                      ; a newer one is applied
    mov     esi, 2
    mov     edx, STK(COAL, 8, 0)
    xor     ecx, ecx
    call    host_put
    EXPECT_D [rbx + CONTAINER.slots], STK(COAL, 8, 0)
    lea     rax, [net_peers + PEER_size]
    EXPECT_D [rax + PEER.put_seq], 2
    ; CONT_CLOSE: that peer holds nothing; its puts are ignored
    mov     edi, 1
    mov     esi, MT_CONT_CLOSE
    lea     rdx, [small_buf]
    xor     ecx, ecx
    call    nw_on_cont_close
    mov     edi, 1
    mov     esi, 3
    mov     edx, STK(COAL, 4, 0)
    xor     ecx, ecx
    call    host_put
    EXPECT_D [rbx + CONTAINER.slots], STK(COAL, 8, 0)
    ; the resend: peer 2 hears the record every 10 frames
    call    cap_on
    mov     r13d, 10
.sync:
    call    net_cont_frame
    dec     r13d
    jnz     .sync
    call    cap_count
    cmp     eax, 1
    jne     .fail
    EXPECT_CAP 0, 2, MT_CONT_DATA, 140
    ; the block goes away: peer 2 is told and let go
    call    cap_on
    mov     edi, 100
    mov     esi, 64
    mov     edx, 100
    call    net_cont_removed
    EXPECT_CAP 0, 2, MT_CONT_GONE, 12
    EXPECT_NO_CAP 1
    lea     rax, [net_peers + 2 * PEER_size]
    EXPECT_D [rax + PEER.open_kind], 0
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    mov     byte [net_role], NET_ROLE_OFF
    mov     byte [net_in_world], 0
    mov     dword [net_cont_active], 0
    mov     dword [net_cont_seq], 0
    mov     byte [net_cont_shadow + CONTAINER.kind], 0
    mov     dword [game_open_screen], 0
    mov     qword [game_open_cont], 0
    mov     eax, [rsp]
    mov     [app_state], eax
    mov     rax, [rsp + 8]
    mov     [inv_container], rax
    lea     rdi, [net_peers + PEER_size]
    mov     ecx, 3 * PEER_size / 8
    xor     eax, eax
    rep     stosq
    call    cap_off
    call    world_clear
    mov     eax, ebx
    add     rsp, 24
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; open_chest(): the player clicks the chest at (100, 64, 100): net_cont_open_out
open_chest:
    sub     rsp, 8
    mov     edi, 100
    mov     esi, 64
    mov     edx, 100
    mov     ecx, CONT_CHEST
    call    net_cont_open_out
    add     rsp, 8
    ret

; send_data(): nw_on_cont_data(0, MT_CONT_DATA, cd_buf, 140)
send_data:
    sub     rsp, 8
    xor     edi, edi
    mov     esi, MT_CONT_DATA
    lea     rdx, [cd_buf]
    mov     ecx, 140
    call    nw_on_cont_data
    add     rsp, 8
    ret

; host_open(edi slot): nw_on_cont_open from that peer with the CONT_OPEN message at cd_buf
host_open:
    sub     rsp, 8
    mov     esi, MT_CONT_OPEN
    lea     rdx, [cd_buf]
    mov     ecx, 13
    call    nw_on_cont_open
    add     rsp, 8
    ret

; host_put(edi slot, esi seq, edx cell 0, ecx cell 5): nw_on_cont_put from that peer for the container at
; (100, 64, 100): its 27 cells empty but cell 0 and cell 5
host_put:
    push    rbx
    push    r12
    push    r13
    mov     ebx, edi
    mov     r12d, edx
    mov     r13d, ecx
    lea     rdi, [cd_buf + 256]
    xor     eax, eax
    mov     ecx, 124 / 4
    rep     stosd
    mov     dword [cd_buf + 256], 100
    mov     dword [cd_buf + 260], 64
    mov     dword [cd_buf + 264], 100
    mov     [cd_buf + 268], esi
    mov     [cd_buf + 272], r12d        ; cell 0
    mov     [cd_buf + 292], r13d        ; cell 5
    mov     edi, ebx
    mov     esi, MT_CONT_PUT
    lea     rdx, [cd_buf + 256]
    mov     ecx, 124
    call    nw_on_cont_put
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- helpers of the tests that follow ---------------------------------------------------------------------

; cap_small(edi cap): capture into the buffer, but with room for cap bytes only: a send that does not fit
; fails, as a send into a full queue does
cap_small:
    sub     rsp, 8
    mov     esi, edi
    lea     rdi, [cap_buf]
    call    net_capture
    add     rsp, 8
    ret

; peers_ready(edi n): guests 1..n are accepted and READY
peers_ready:
    mov     ecx, 1
    lea     rdx, [net_peers]
.l:
    cmp     ecx, edi
    ja      .ret
    imul    eax, ecx, PEER_size
    mov     dword [rdx + rax + PEER.state], PEER_READY
    inc     ecx
    jmp     .l
.ret:
    ret

; peers_free(): guests 1..7 are free again, and nobody has marks
peers_free:
    lea     rdi, [net_peers + PEER_size]
    mov     ecx, (NET_MAX_PEERS - 1) * PEER_size / 8
    xor     eax, eax
    rep     stosq
    lea     rdi, [net_dirty_n]
    mov     ecx, NET_MAX_PEERS
    rep     stosd
    ret

; answer_pristine(edi acx, esi acz): the host's COL_PRISTINE for that column arrives
answer_pristine:
    sub     rsp, 8
    mov     [small_buf], edi
    mov     [small_buf + 4], esi
    xor     edi, edi
    mov     esi, MT_COL_PRISTINE
    lea     rdx, [small_buf]
    mov     ecx, 8
    call    nw_on_col_pristine
    add     rsp, 8
    ret

; answer_data(edi acx, esi acz): the host's COL_DATA for that column arrives (a blob of 8 bytes: it is only held)
answer_data:
    sub     rsp, 8
    mov     [cd_buf + 2048], edi
    mov     [cd_buf + 2052], esi
    mov     dword [cd_buf + 2056], 0x394C4F43
    mov     dword [cd_buf + 2060], 0
    xor     edi, edi
    mov     esi, MT_COL_DATA
    lea     rdx, [cd_buf + 2048]
    mov     ecx, 16
    call    nw_on_col_data
    add     rsp, 8
    ret

; host_block(edi ax, esi az, edx y, ecx id): the host's BLOCK for that cell arrives
host_block:
    sub     rsp, 8
    mov     [small_buf + 32], edi
    mov     [small_buf + 36], esi
    mov     [small_buf + 40], dl
    mov     [small_buf + 41], cl
    xor     edi, edi
    mov     esi, MT_BLOCK
    lea     rdx, [small_buf + 32]
    mov     ecx, 10
    call    nw_on_block
    add     rsp, 8
    ret

; install_empty(edi acx, esi acz) -> eax 0: the column is claimed, installed empty (air up to y 79) and lit
install_empty:
    push    rbx
    push    r12
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, esi
    call    world_column_claim
    test    rax, rax
    jz      .fail
    lea     rdi, [genbuf]
    xor     eax, eax
    mov     ecx, GENBUF_size / 8
    rep     stosq
    mov     [genbuf + GENBUF.cx], ebx
    mov     [genbuf + GENBUF.cz], r12d
    mov     dword [genbuf + GENBUF.top], 79
    lea     rdi, [genbuf]
    call    world_install
    test    eax, eax
    jnz     .out
    mov     edi, ebx
    mov     esi, r12d
    call    world_column
    test    rax, rax
    jz      .fail
    mov     dword [rax + COLUMN.state], COL_LIT
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; fires_live() -> eax the occupied slots of the fire table (a free slot has y = -1)
fires_live:
    lea     rcx, [fires]
    mov     edx, MAX_FIRES
    xor     eax, eax
.l:
    cmp     dword [rcx + FIREENT.y], -1
    je      .next
    inc     eax
.next:
    add     rcx, FIREENT_size
    dec     edx
    jnz     .l
    ret

; ep_up() -> eax 0: the shared endpoint is open (an ephemeral port) and holds a connection for guest 1, accepted
; from 127.0.0.1:9. Nothing is read through it and the capture seam takes the sends: net_ep_room just has an
; answer for the host's column service.
ep_up:
    push    rbx
    sub     rsp, 48
    lea     rdi, [net_ep]               ; (a stale endpoint of another test goes first)
    call    net_ep_close
    lea     rdi, [net_ep]
    xor     esi, esi
    mov     edx, 1
    call    net_ep_open
    test    eax, eax
    js      .fail
    mov     rdi, rsp
    xor     eax, eax
    mov     ecx, 6
    rep     stosq
    mov     byte [rsp + NETEVENT.kind], NE_CONNECT_REQ
    mov     dword [rsp + NETEVENT.addr + NADDR.ip], 0x0100007F
    mov     word [rsp + NETEVENT.addr + NADDR.port], 0x0900
    mov     dword [rsp + NETEVENT.nonce], 1
    lea     rdi, [net_ep]
    mov     esi, 1
    mov     rdx, rsp
    call    net_ep_accept
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    add     rsp, 48
    pop     rbx
    ret

; ep_down(): the endpoint is closed again
ep_down:
    sub     rsp, 8
    lea     rdi, [net_ep]
    call    net_ep_close
    add     rsp, 8
    ret

; ---- net_stale_verdict ------------------------------------------------------------------------------------
; The host's answer for a column ("pristine" here; a blob is the same) waits for the stream, and a BLOCK for a
; cell of that column arrives behind it, so the answer predates the edit. (a) While the stream keeps the answer
; (it asks every frame, 601 > NEDIT_TTL of them) the edit waits as well, and is applied when the column is
; installed. (b) When nobody asks about the answer any more, it is forgotten (COLV_IDLE) and the edit goes with
; it: the next request is answered with the edit in, and the verdict is no longer "pristine".
test_net_stale_verdict:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    world_clear
    mov     dword [net_edit_n], 0
    mov     byte [net_in_world], 1
    mov     byte [net_role], NET_ROLE_GUEST
    call    cap_on
    mov     edi, 40
    mov     esi, 40
    call    net_column_verdict
    test    eax, eax
    jnz     .fail
    mov     edi, 40
    mov     esi, 40
    call    answer_pristine
    mov     edi, 40
    mov     esi, 40
    call    net_column_verdict
    cmp     eax, 1
    jne     .fail
    mov     edi, 643                    ; the host's BLOCK for a cell of the column, behind the answer
    mov     esi, 643
    mov     edx, 70
    mov     ecx, STONE
    call    host_block
    EXPECT_D [net_edit_n], 1
    mov     r12d, NEDIT_TTL + 1
.keep:
    call    net_edits_replay
    mov     edi, 40
    mov     esi, 40
    call    net_column_verdict          ; the stream asks again, every frame it wants the column
    cmp     eax, 1
    jne     .fail
    dec     r12d
    jnz     .keep
    EXPECT_D [net_edit_n], 1            ; the edit outlived the time a host lets one of its own wait
    mov     edi, 40                     ; the stream installs the column from the answer
    mov     esi, 40
    call    install_empty
    test    eax, eax
    jnz     .fail
    call    net_edits_replay
    EXPECT_D [net_edit_n], 0
    EXPECT_BLOCK 643, 70, 643, STONE    ; and the edit is in it
    mov     edi, 41                     ; (b) the same for column (41, 40), but nobody asks about it any more
    mov     esi, 40
    call    net_column_verdict
    mov     edi, 41
    mov     esi, 40
    call    answer_pristine
    mov     edi, 659
    mov     esi, 643
    mov     edx, 70
    mov     ecx, STONE
    call    host_block
    EXPECT_D [net_edit_n], 1
    mov     r12d, NEDIT_TTL + 1
.idle:
    call    net_edits_replay
    dec     r12d
    jnz     .idle
    EXPECT_D [net_edit_n], 0            ; the edit went with its answer ...
    call    cap_on
    mov     edi, 41
    mov     esi, 40
    call    net_column_verdict
    test    eax, eax
    jnz     .fail                       ; ... which is not "pristine" any more:
    EXPECT_CAP 0, 255, MT_COL_REQ, 8    ; the host is asked afresh
    EXPECT_D [rax + 4], 41
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    mov     edi, 40
    mov     esi, 40
    call    net_column_forget
    mov     edi, 41
    mov     esi, 40
    call    net_column_forget
    mov     byte [net_role], NET_ROLE_OFF
    mov     byte [net_in_world], 0
    mov     dword [net_edit_n], 0
    call    cap_off
    call    world_clear
    mov     eax, ebx
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- net_block_overflow -----------------------------------------------------------------------------------
; A BLOCK that finds no room is never lost for good. Host: every guest is sent it on its own, so that one with a
; full queue neither holds the others back nor hears it twice; what it missed is remembered as a COLUMN (once),
; and when it has room the host tells it that column is stale (COL_REQ, host to guest). Guest: the host's
; notice marks the column, which is dropped (with the answer held for it and the edits waiting for it) and
; fetched afresh; an outbox that overflows (4096) does the same to the column of the edit it cannot keep.
test_net_block_overflow:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    world_clear
    call    peers_free
    mov     byte [net_role], NET_ROLE_HOST      ; ---- host: two guests, capture room for one BLOCK only
    mov     edi, 2
    call    peers_ready
    mov     edi, 14
    call    cap_small
    mov     edi, -20                    ; column (-2, 2)
    mov     esi, 6
    mov     edx, 40
    mov     ecx, STONE
    xor     r8d, r8d
    call    net_block_out
    EXPECT_CAP 0, 1, MT_BLOCK, 10       ; guest 1 heard it
    EXPECT_D [rax + 4], -20
    EXPECT_NO_CAP 1
    EXPECT_D [net_dirty_n + 4], 0
    EXPECT_D [net_dirty_n + 8], 1       ; guest 2 had no room: it is to fetch the column afresh
    mov     edi, -19                    ; the same column again: now neither has room
    mov     esi, 6
    mov     edx, 41
    mov     ecx, STONE
    xor     r8d, r8d
    call    net_block_out
    EXPECT_D [net_dirty_n + 4], 1
    EXPECT_D [net_dirty_n + 8], 1       ; (no second mark for a column)
    mov     edi, 100                    ; another column: (6, 6)
    mov     esi, 6
    mov     edx, 100
    mov     ecx, STONE
    xor     r8d, r8d
    call    net_block_out
    EXPECT_D [net_dirty_n + 4], 2
    EXPECT_D [net_dirty_n + 8], 2
    mov     edi, 8                      ; no room for the notice either: the marks stay
    call    cap_small
    call    net_host_columns_serve
    EXPECT_D [net_dirty_n + 4], 2
    EXPECT_D [net_dirty_n + 8], 2
    call    cap_on                      ; room: each guest is told, the newest mark first
    call    net_host_columns_serve
    EXPECT_CAP 0, 1, MT_COL_REQ, 8
    EXPECT_D [rax + 4], 6
    EXPECT_D [rax + 8], 6
    EXPECT_CAP 1, 1, MT_COL_REQ, 8
    EXPECT_D [rax + 4], -2
    EXPECT_D [rax + 8], 2
    EXPECT_CAP 2, 2, MT_COL_REQ, 8
    EXPECT_D [rax + 4], 6
    EXPECT_CAP 3, 2, MT_COL_REQ, 8
    EXPECT_D [rax + 4], -2
    EXPECT_NO_CAP 4
    EXPECT_D [net_dirty_n + 4], 0
    EXPECT_D [net_dirty_n + 8], 0
    call    cap_on
    call    net_host_columns_serve
    EXPECT_D [net_captured], 0          ; told once
    call    peers_free                  ; ---- guest: the host says that columns are stale
    mov     byte [net_role], NET_ROLE_GUEST
    mov     byte [net_in_world], 1
    call    cap_on
    mov     edi, 3                      ; column (3, 3) is loaded, not lit, with an edit waiting for it
    mov     esi, 3
    call    world_column
    test    rax, rax
    jz      .fail
    mov     dword [rax + COLUMN.state], COL_BLOCKS
    EDIT    53, 40, 55, STONE, 0
    EXPECT_D [net_edit_n], 1
    mov     edi, 41                     ; the host's answer for column (41, 40) waits for the stream
    mov     esi, 40
    call    net_column_verdict
    mov     edi, 41
    mov     esi, 40
    call    answer_pristine
    mov     edi, 41
    mov     esi, 40
    call    net_column_verdict
    cmp     eax, 1
    jne     .fail
    mov     dword [small_buf + 16], 3   ; the host: COL_REQ {3, 3} ...
    mov     dword [small_buf + 20], 3
    xor     edi, edi
    mov     esi, MT_COL_REQ
    lea     rdx, [small_buf + 16]
    mov     ecx, 8
    call    nw_on_col_req
    mov     dword [small_buf + 16], 41  ; ... and {41, 40}
    mov     dword [small_buf + 20], 40
    xor     edi, edi
    mov     esi, MT_COL_REQ
    lea     rdx, [small_buf + 16]
    mov     ecx, 8
    call    nw_on_col_req
    EXPECT_D [net_dirty_n], 2
    mov     edi, 1                      ; (only the host says so)
    mov     esi, MT_COL_REQ
    lea     rdx, [small_buf + 16]
    mov     ecx, 8
    call    nw_on_col_req
    EXPECT_D [net_dirty_n], 2
    call    net_edits_replay
    EXPECT_D [net_dirty_n], 0
    EXPECT_D [net_edit_n], 0            ; the edit is older than the answer to come
    mov     edi, 3
    mov     esi, 3
    call    world_column
    test    rax, rax
    jnz     .fail                       ; the column was dropped ...
    call    cap_on
    mov     edi, 41
    mov     esi, 40
    call    net_column_verdict
    test    eax, eax
    jnz     .fail                       ; ... and so was the answer: asked afresh
    EXPECT_CAP 0, 255, MT_COL_REQ, 8
    EXPECT_D [rax + 4], 41
    xor     edi, edi                    ; ---- guest: an edit that finds no room waits, and is not passed by newer ones
    call    cap_small
    mov     r12d, 80
.wait3:
    mov     edi, r12d
    mov     esi, 6
    mov     edx, 80
    mov     ecx, STONE
    xor     r8d, r8d
    call    net_block_out
    inc     r12d
    cmp     r12d, 83
    jb      .wait3
    EXPECT_D [net_bq_n], 3
    call    cap_on                      ; room again: a new edit still goes behind the ones that wait
    mov     edi, 83
    mov     esi, 6
    mov     edx, 80
    mov     ecx, STONE
    xor     r8d, r8d
    call    net_block_out
    EXPECT_NO_CAP 0
    EXPECT_D [net_bq_n], 4
    call    net_edits_replay            ; they go out oldest first
    EXPECT_CAP 0, 255, MT_BLOCK, 10
    EXPECT_D [rax + 4], 80
    EXPECT_CAP 3, 255, MT_BLOCK, 10
    EXPECT_D [rax + 4], 83
    EXPECT_NO_CAP 4
    EXPECT_D [net_bq_n], 0
    lea     rdi, [cap_buf]              ; ---- guest: the outbox overflows (nothing fits any more)
    xor     esi, esi
    call    net_capture
    xor     r12d, r12d
.over:
    mov     edi, r12d
    and     edi, 15
    add     edi, 64                     ; x 64..79, z 70: column (4, 4), loaded
    mov     esi, 6
    mov     edx, 70
    mov     ecx, STONE
    xor     r8d, r8d
    call    net_block_out
    inc     r12d
    cmp     r12d, 4097
    jb      .over
    EXPECT_D [net_bq_n], 4096           ; the ring is full ...
    EXPECT_D [net_dirty_n], 1           ; ... the 4097th edit had no place: its column is to be fetched afresh
    call    net_edits_replay
    EXPECT_D [net_dirty_n], 0
    mov     edi, 4
    mov     esi, 4
    call    world_column
    test    rax, rax
    jnz     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    mov     edi, 41
    mov     esi, 40
    call    net_column_forget
    mov     byte [net_role], NET_ROLE_GUEST     ; (the next replay starts the session state afresh)
    mov     byte [net_in_world], 0
    call    net_edits_replay
    mov     byte [net_role], NET_ROLE_OFF
    call    peers_free
    call    cap_off
    call    world_clear
    mov     eax, ebx
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- net_cont_close_retry ---------------------------------------------------------------------------------
; A guest that closes a container stays in it until the last put and the CONT_CLOSE are both queued: a send
; that finds no room is made again the next frame, and the put is not sent twice.
; Frame: [rsp] app_state, [rsp + 8] inv_container as they were.
test_net_cont_close_retry:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 24
    call    world_clear
    mov     eax, [app_state]
    mov     [rsp], eax
    mov     rax, [inv_container]
    mov     [rsp + 8], rax
    mov     byte [net_in_world], 1
    mov     byte [net_role], NET_ROLE_GUEST
    call    cap_on
    lea     rdi, [cd_buf]               ; CONT_DATA {100, 64, 100, seq 0, a chest holding 5 coal}
    xor     eax, eax
    mov     ecx, 140 / 4
    rep     stosd
    mov     dword [cd_buf], 100
    mov     dword [cd_buf + 4], 64
    mov     dword [cd_buf + 8], 100
    mov     byte [cd_buf + 16], CONT_CHEST
    mov     dword [cd_buf + 20], STK(COAL, 5, 0)
    call    open_chest
    call    send_data
    EXPECT_D [net_cont_active], 1
    mov     dword [game_open_screen], 0
    mov     qword [game_open_cont], 0
    mov     dword [app_state], ST_PLAYING       ; its screen is not up
    mov     qword [inv_container], 0
    mov     dword [net_cont_shadow + CONTAINER.slots + 4], STK(COAL, 3, 0)   ; an edit not sent yet
    mov     edi, 20                     ; (a) no room for the put: the container stays open, nothing is lost
    call    cap_small
    mov     r13d, CONT_GRACE_FRAMES
.grace:
    call    net_cont_frame
    dec     r13d
    jnz     .grace
    call    net_cont_frame              ; the grace is over: it closes, but the put does not fit
    EXPECT_D [net_cont_active], 1
    EXPECT_D [net_captured], 0
    call    net_cont_frame
    EXPECT_D [net_cont_active], 1
    call    cap_on                      ; room: the put, then the close
    call    net_cont_frame
    EXPECT_CAP 0, 255, MT_CONT_PUT, 124
    EXPECT_D [rax + 16], 1
    EXPECT_D [rax + 24], STK(COAL, 3, 0)
    EXPECT_CAP 1, 255, MT_CONT_CLOSE, 0
    EXPECT_D [net_cont_active], 0
    call    net_cont_frame
    EXPECT_NO_CAP 2
    mov     dword [cd_buf + 12], 1      ; (b) room for the put but not for the close: the put is not sent twice
    call    open_chest
    call    send_data
    EXPECT_D [net_cont_active], 1
    mov     dword [game_open_screen], 0
    mov     qword [game_open_cont], 0
    mov     dword [net_cont_shadow + CONTAINER.slots + 8], STK(COAL, 1, 0)
    mov     edi, 128                    ; a CONT_PUT record is 4 + 124 bytes, a CONT_CLOSE one 4
    call    cap_small
    mov     r13d, CONT_GRACE_FRAMES + 1
.grace2:
    call    net_cont_frame
    dec     r13d
    jnz     .grace2
    EXPECT_CAP 0, 255, MT_CONT_PUT, 124
    EXPECT_D [rax + 16], 2
    EXPECT_NO_CAP 1
    EXPECT_D [net_cont_active], 1       ; the close found no room
    call    cap_on
    call    net_cont_frame
    EXPECT_CAP 0, 255, MT_CONT_CLOSE, 0 ; only the close now
    EXPECT_NO_CAP 1
    EXPECT_D [net_cont_active], 0
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    mov     byte [net_role], NET_ROLE_OFF
    mov     byte [net_in_world], 0
    mov     dword [net_cont_active], 0
    mov     dword [net_cont_seq], 0
    mov     byte [net_cont_shadow + CONTAINER.kind], 0
    mov     dword [game_open_screen], 0
    mov     qword [game_open_cont], 0
    mov     eax, [rsp]
    mov     [app_state], eax
    mov     rax, [rsp + 8]
    mov     [inv_container], rax
    call    cap_off
    call    world_clear
    mov     eax, ebx
    add     rsp, 24
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- net_fire_in_column -----------------------------------------------------------------------------------
; A column's encoding writes FIRE as AIR, so the host follows every COL_DATA with a BLOCK(FIRE) for each flame in
; that column (and for no other). On the guest the BLOCKs behind the answer wait for the column (they do not
; spoil the answer) and, once it is installed, put the flames back: the blocks and the fire table.
test_net_fire_in_column:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    world_clear
    call    fire_clear
    SETB    20, 30, 20, STONE           ; column (1, 1) holds a change and two flames, column (0, 0) one
    mov     edi, 21
    mov     esi, 31
    mov     edx, 21
    call    fire_place
    cmp     eax, 1
    jne     .fail
    mov     edi, 30
    mov     esi, 40
    mov     edx, 25
    call    fire_place
    cmp     eax, 1
    jne     .fail
    mov     edi, 5
    mov     esi, 11
    mov     edx, 5
    call    fire_place
    cmp     eax, 1
    jne     .fail
    mov     edi, 22                     ; an entry whose block is gone (fire_step has not freed it yet): no flame
    mov     esi, 33
    mov     edx, 22
    call    fire_track
    test    eax, eax
    jz      .fail
    call    ep_up
    test    eax, eax
    jnz     .fail
    mov     byte [net_role], NET_ROLE_HOST
    mov     edi, 1
    call    peers_ready
    mov     dword [small_buf + 16], 1   ; guest 1 asks for column (1, 1)
    mov     dword [small_buf + 20], 1
    mov     edi, 1
    mov     esi, MT_COL_REQ
    lea     rdx, [small_buf + 16]
    mov     ecx, 8
    call    nw_on_col_req
    call    cap_on
    call    net_host_columns_serve
    EXPECT_CAPT 0, 1, MT_COL_DATA
    EXPECT_CAP 1, 1, MT_BLOCK, 10       ; ... and the flames, behind it
    EXPECT_D [rax + 4], 21
    EXPECT_D [rax + 8], 21
    cmp     byte [rax + 12], 31
    jne     .fail
    cmp     byte [rax + 13], FIRE
    jne     .fail
    EXPECT_CAP 2, 1, MT_BLOCK, 10
    EXPECT_D [rax + 4], 30
    EXPECT_D [rax + 8], 25
    cmp     byte [rax + 12], 40
    jne     .fail
    EXPECT_NO_CAP 3                     ; (not the flame of column (0, 0))
    lea     rsi, [cap_buf]              ; keep what was sent: the guest below is given it
    lea     rdi, [cd_buf + 4096]
    mov     ecx, [net_captured]
    mov     r13d, ecx
    rep     movsb
    movzx   r12d, word [cd_buf + 4096 + 2]      ; the length of COL_DATA
    mov     dword [small_buf + 16], 30  ; a column nobody touched is just "pristine": no flames
    mov     dword [small_buf + 20], 30
    mov     edi, 1
    mov     esi, MT_COL_REQ
    lea     rdx, [small_buf + 16]
    mov     ecx, 8
    call    nw_on_col_req
    call    cap_on
    call    net_host_columns_serve
    EXPECT_CAP 0, 1, MT_COL_PRISTINE, 8
    EXPECT_NO_CAP 1
    mov     edi, 1                      ; the host's column (1, 1) goes: this process is both ends of the wire
    mov     esi, 1
    call    world_column
    test    rax, rax
    jz      .fail
    mov     rdi, rax
    call    world_unload
    call    fires_live
    cmp     eax, 1                      ; (only the flame of column (0, 0) is left)
    jne     .fail
    mov     byte [net_role], NET_ROLE_GUEST
    mov     byte [net_in_world], 1
    call    peers_free
    call    cap_on
    mov     edi, 1
    mov     esi, 1
    call    net_column_verdict
    test    eax, eax
    jnz     .fail
    xor     edi, edi                    ; the answer ...
    mov     esi, MT_COL_DATA
    lea     rdx, [cd_buf + 4096 + 4]
    mov     ecx, r12d
    call    nw_on_col_data
    lea     rbx, [cd_buf + 4096 + 4]    ; ... and the two BLOCKs behind it
    add     rbx, r12
.blocks:
    lea     rax, [cd_buf + 4096]
    add     rax, r13
    cmp     rbx, rax
    jae     .answered
    xor     edi, edi
    mov     esi, MT_BLOCK
    lea     rdx, [rbx + 4]
    mov     ecx, 10
    call    nw_on_block
    add     rbx, 14
    jmp     .blocks
.answered:
    EXPECT_D [net_edit_n], 2            ; they wait for the column
    mov     edi, 1
    mov     esi, 1
    call    net_column_verdict
    cmp     eax, 2
    jne     .fail                       ; and did not spoil the answer
    mov     edi, 1
    mov     esi, 1
    lea     rdx, [genbuf]
    call    net_column_take
    cmp     eax, 1
    jne     .fail
    mov     edi, 1
    mov     esi, 1
    call    world_column_claim
    test    rax, rax
    jz      .fail
    lea     rdi, [genbuf]
    call    world_install
    test    eax, eax
    jnz     .fail
    mov     edi, 1
    mov     esi, 1
    call    world_column
    test    rax, rax
    jz      .fail
    mov     dword [rax + COLUMN.state], COL_LIT
    EXPECT_BLOCK 21, 31, 21, AIR        ; (the blob had no flames)
    call    net_edits_replay
    EXPECT_D [net_edit_n], 0
    EXPECT_BLOCK 21, 31, 21, FIRE
    EXPECT_BLOCK 30, 40, 25, FIRE
    call    fires_live
    cmp     eax, 3                      ; the fire table has them again (plus the one of column (0, 0))
    jne     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    mov     byte [net_role], NET_ROLE_OFF
    mov     byte [net_in_world], 0
    mov     dword [net_edit_n], 0
    call    peers_free
    call    ep_down
    call    cap_off
    call    fire_clear
    call    world_clear
    mov     eax, ebx
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- net_boat_double_mount --------------------------------------------------------------------------------
; A guest that clicks the boat it already sits in is told yes again (the first answer may have been lost or
; slow); another guest is still refused.
test_net_boat_double_mount:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    world_clear
    call    boats_clear
    mov     dword [boats + BOATENT.used], 1
    mov     byte [net_role], NET_ROLE_HOST
    mov     edi, 2
    call    peers_ready
    call    cap_on
    mov     edi, 1
    xor     esi, esi
    call    mount_boat
    mov     edi, 1
    xor     esi, esi
    call    mount_boat
    mov     edi, 2
    xor     esi, esi
    call    mount_boat
    EXPECT_CAP 0, 1, MT_BOAT_MOUNT_OK, 2
    cmp     byte [rax + 4], 0
    jne     .fail
    cmp     byte [rax + 5], 1
    jne     .fail
    EXPECT_CAP 1, 1, MT_BOAT_MOUNT_OK, 2
    cmp     byte [rax + 4], 0
    jne     .fail
    cmp     byte [rax + 5], 1           ; yes again
    jne     .fail
    EXPECT_CAP 2, 2, MT_BOAT_MOUNT_OK, 2
    cmp     byte [rax + 4], 0
    jne     .fail
    cmp     byte [rax + 5], 0           ; the other guest is refused
    jne     .fail
    cmp     byte [boat_rider], 2        ; guest 1 still rides it
    jne     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    mov     byte [net_role], NET_ROLE_OFF
    call    peers_free
    call    boats_clear
    call    cap_off
    call    world_clear
    mov     eax, ebx
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mount_boat(edi from, esi boat): BOAT_MOUNT {boat} from that guest
mount_boat:
    sub     rsp, 8
    mov     [small_buf + 48], sil
    mov     esi, MT_BOAT_MOUNT
    lea     rdx, [small_buf + 48]
    mov     ecx, 1
    call    nw_on_boat_mount
    add     rsp, 8
    ret

; ---- net_fire_guest_step ----------------------------------------------------------------------------------
; fire_guest_step is the damage pass of fire_step alone, against the guest's own fire table: a Survival player
; standing in a flame is hurt, one beside it is not, Creative is not, and a flame whose block is gone leaves the
; table without hurting anyone.
; (the player's body and survival state are put back as they were)
test_net_fire_guest_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    world_clear
    call    fire_clear
    mov     r12d, [game_mode]
    lea     rsi, [player]
    lea     rdi, [save_player]
    mov     ecx, BODY_size
    rep     movsb
    lea     rsi, [surv]
    lea     rdi, [save_surv]
    mov     ecx, SURVIVAL_size
    rep     movsb
    mov     dword [game_mode], MODE_SURVIVAL
    call    survival_reset
    lea     rdi, [player]
    movss   xmm0, [k_half_w]
    movss   xmm1, [k_height]
    movss   xmm2, [k_speed]
    call    body_init
    movss   xmm0, [k_5_5]
    movss   [player + BODY.x], xmm0
    movss   [player + BODY.z], xmm0
    movss   xmm0, [k_11]
    movss   [player + BODY.y], xmm0
    SETB    9, 11, 9, FIRE              ; a flame beside the player
    mov     edi, 9
    mov     esi, 11
    mov     edx, 9
    call    fire_track
    call    fire_guest_step
    cmp     dword [surv + SURVIVAL.health], 20
    jne     .fail                       ; (not hurt)
    SETB    5, 11, 5, FIRE              ; the one he stands in
    mov     edi, 5
    mov     esi, 11
    mov     edx, 5
    call    fire_track
    call    fire_guest_step
    cmp     dword [surv + SURVIVAL.health], 20
    jge     .fail                       ; hurt
    call    survival_reset
    mov     dword [game_mode], MODE_CREATIVE
    call    fire_guest_step
    cmp     dword [surv + SURVIVAL.health], 20
    jne     .fail                       ; Creative is not
    mov     dword [game_mode], MODE_SURVIVAL
    SETB    5, 11, 5, AIR               ; the host's BLOCK put it out
    call    fire_guest_step
    cmp     dword [surv + SURVIVAL.health], 20
    jne     .fail
    call    fires_live
    cmp     eax, 1                      ; its entry is gone, the other flame stays
    jne     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    lea     rsi, [save_player]
    lea     rdi, [player]
    mov     ecx, BODY_size
    rep     movsb
    lea     rsi, [save_surv]
    lea     rdi, [surv]
    mov     ecx, SURVIVAL_size
    rep     movsb
    mov     [game_mode], r12d
    call    fire_clear
    call    world_clear
    mov     eax, ebx
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- net_column_expiry ------------------------------------------------------------------------------------
; A guest's answers do not pile up. A blob or "pristine" that nobody asks about for COLV_IDLE (600) frames is
; forgotten (its buffer is free again); one the stream keeps asking about stays; a request the host never
; answered is asked again after 3600 frames. When all 32 buffers hold blobs, a new blob takes the buffer of the
; one asked about least recently (the oldest, not the first).
test_net_column_expiry:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    world_clear
    mov     byte [net_in_world], 1
    mov     byte [net_role], NET_ROLE_GUEST
    call    cap_on
    xor     r13d, r13d
.ask:
    lea     edi, [r13 + 100]            ; (100, 100) will hold a blob, (101, 100) is "pristine", (102, 100) unanswered
    mov     esi, 100
    call    net_column_verdict
    inc     r13d
    cmp     r13d, 3
    jb      .ask
    mov     edi, 100
    mov     esi, 100
    call    answer_data
    mov     edi, 101
    mov     esi, 100
    call    answer_pristine
    EXPECT_D [net_colbuf_used], 1
    mov     r12d, COLV_IDLE_FRAMES - 1
.wait:
    call    net_edits_replay
    dec     r12d
    jnz     .wait
    EXPECT_D [net_colbuf_used], 1       ; 599 frames: nothing goes
    mov     edi, 101                    ; the stream asks about (101, 100)
    mov     esi, 100
    call    net_column_verdict
    cmp     eax, 1
    jne     .fail
    call    net_edits_replay            ; frame 600
    EXPECT_D [net_colbuf_used], 0       ; nobody asked about the blob: it is let go
    call    cap_on
    mov     edi, 100
    mov     esi, 100
    call    net_column_verdict
    test    eax, eax
    jnz     .fail
    EXPECT_CAP 0, 255, MT_COL_REQ, 8    ; and is asked for again
    EXPECT_D [rax + 4], 100
    mov     edi, 101
    mov     esi, 100
    call    net_column_verdict
    cmp     eax, 1
    jne     .fail                       ; the one the stream asked about stays
    mov     edi, 102
    mov     esi, 100
    call    net_column_verdict
    test    eax, eax
    jnz     .fail
    EXPECT_NO_CAP 1                     ; (102, 100) is still waiting for its answer: not asked twice
    mov     r12d, COLV_TIMEOUT_FRAMES - COLV_IDLE_FRAMES
.timeout:
    call    net_edits_replay
    dec     r12d
    jnz     .timeout
    call    cap_on
    mov     edi, 102
    mov     esi, 100
    call    net_column_verdict
    test    eax, eax
    jnz     .fail
    EXPECT_CAP 0, 255, MT_COL_REQ, 8    ; 3600 frames without an answer: asked again
    EXPECT_D [rax + 4], 102
    xor     r13d, r13d                  ; eviction: 33 blobs for 32 buffers
    mov     edi, 100
    mov     esi, 100
    call    net_column_forget
    mov     edi, 101
    mov     esi, 100
    call    net_column_forget
    mov     edi, 102
    mov     esi, 100
    call    net_column_forget
.ask33:
    lea     edi, [r13 + 200]
    mov     esi, 200
    call    net_column_verdict
    inc     r13d
    cmp     r13d, 33
    jb      .ask33
    xor     r13d, r13d
.fill:
    lea     edi, [r13 + 200]
    mov     esi, 200
    call    answer_data
    inc     r13d
    cmp     r13d, 32
    jb      .fill
    EXPECT_D [net_colbuf_used], -1
    mov     r12d, 10
.age:
    call    net_edits_replay
    dec     r12d
    jnz     .age
    mov     edi, 200                    ; the stream asks about the first of them: it is the youngest now
    mov     esi, 200
    call    net_column_verdict
    cmp     eax, 2
    jne     .fail
    mov     edi, 232
    mov     esi, 200
    call    answer_data                 ; the 33rd: the oldest (201, not the first, 200) makes room
    EXPECT_D [net_colbuf_used], -1
    mov     edi, 232
    mov     esi, 200
    call    net_column_verdict
    cmp     eax, 2
    jne     .fail
    mov     edi, 200
    mov     esi, 200
    call    net_column_verdict
    cmp     eax, 2
    jne     .fail
    call    cap_on
    mov     edi, 201
    mov     esi, 200
    call    net_column_verdict
    test    eax, eax
    jnz     .fail
    EXPECT_CAP 0, 255, MT_COL_REQ, 8    ; the one that gave up its buffer is asked for again
    EXPECT_D [rax + 4], 201
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    mov     byte [net_in_world], 0      ; (the next replay of a guest outside a world forgets all of it)
    call    net_edits_replay
    mov     byte [net_role], NET_ROLE_OFF
    call    cap_off
    call    world_clear
    mov     eax, ebx
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- net_boat_giveback ------------------------------------------------------------------------------------
; A guest's boat item is used up in Survival before the host has looked at the water. When the host cannot put
; the boat there (the table of 16 is full), the item goes back (GIVE) and the host sees no "Too many boats"
; banner for it; in Creative nothing is owed; when there is room the boat is placed and nothing goes back.
; (the game mode and the banner text are put back as they were)
test_net_boat_giveback:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    world_clear
    call    boats_clear
    mov     r12d, [game_mode]
    lea     rsi, [banner_text]
    lea     rdi, [save_banner]
    mov     ecx, 64
    rep     movsb
    mov     dword [game_mode], MODE_SURVIVAL
    SETB    70, 20, 70, WATER
    mov     byte [net_role], NET_ROLE_HOST
    mov     edi, 1
    call    peers_ready
    xor     r13d, r13d
.full:
    imul    eax, r13d, BOATENT_size
    lea     rcx, [boats]
    mov     dword [rcx + rax + BOATENT.used], 1
    inc     r13d
    cmp     r13d, MAX_BOATS
    jb      .full
    mov     byte [banner_text], 0
    call    cap_on
    call    place_boat
    EXPECT_CAP 0, 1, MT_GIVE, 4
    cmp     byte [rax + 4], BOAT
    jne     .fail
    cmp     byte [rax + 5], 1
    jne     .fail
    EXPECT_NO_CAP 1
    cmp     byte [banner_text], 0
    jne     .fail                       ; no banner on the host
    mov     dword [game_mode], MODE_CREATIVE
    call    cap_on
    call    place_boat
    EXPECT_NO_CAP 0                     ; Creative: nothing was used up
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [boats + (MAX_BOATS - 1) * BOATENT_size + BOATENT.used], 0
    call    cap_on
    call    place_boat
    EXPECT_NO_CAP 0                     ; room: the boat is placed
    cmp     dword [boats + (MAX_BOATS - 1) * BOATENT_size + BOATENT.used], 1
    jne     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    mov     byte [net_role], NET_ROLE_OFF
    lea     rsi, [save_banner]
    lea     rdi, [banner_text]
    mov     ecx, 64
    rep     movsb
    mov     [game_mode], r12d
    call    peers_free
    call    boats_clear
    call    cap_off
    call    world_clear
    mov     eax, ebx
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; place_boat(): BOAT_PLACE from guest 1: the eye above the water cell (70, 20, 70), looking straight down
place_boat:
    sub     rsp, 8
    lea     rdi, [cd_buf + 1024]
    movss   xmm0, [k_70_5]
    movss   xmm1, [k_22]
    movss   xmm2, [k_70_5]
    call    net_pos_out
    mov     dword [cd_buf + 1040], 0
    mov     eax, [k_m1]
    mov     [cd_buf + 1044], eax
    mov     dword [cd_buf + 1048], 0
    mov     edi, 1
    mov     esi, MT_BOAT_PLACE
    lea     rdx, [cd_buf + 1024]
    mov     ecx, 28
    call    nw_on_boat_place
    add     rsp, 8
    ret

; ---- net_edit_columns -------------------------------------------------------------------------------------
; The host's stream asks which columns the queued edits wait for: the distinct ones, the oldest edit's first,
; at most max (and 32). It is 0 off the host and for an empty queue, and changes nothing but its output.
test_net_edit_columns:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    world_clear
    mov     dword [net_edit_n], 0
    mov     byte [net_role], NET_ROLE_HOST
    lea     rdi, [cd_buf + 512]
    mov     esi, 8
    call    net_edit_columns
    test    eax, eax
    jnz     .fail                       ; nothing waits
    mov     edi, 643                    ; column (40, 40)
    mov     esi, 40
    mov     edx, 643
    mov     ecx, STONE
    mov     r8d, 1
    call    nw_apply_edit
    mov     edi, -17                    ; column (-2, 0)
    mov     esi, 40
    mov     edx, 5
    mov     ecx, STONE
    mov     r8d, 1
    call    nw_apply_edit
    mov     edi, 644                    ; column (40, 40) again
    mov     esi, 41
    mov     edx, 650
    mov     ecx, STONE
    mov     r8d, 1
    call    nw_apply_edit
    mov     edi, 1000                   ; column (62, 62)
    mov     esi, 40
    mov     edx, 1000
    mov     ecx, STONE
    mov     r8d, 1
    call    nw_apply_edit
    EXPECT_D [net_edit_n], 4
    lea     rdi, [cd_buf + 512]
    mov     dword [rdi + 24], 0x5A5A5A5A
    mov     esi, 8
    call    net_edit_columns
    cmp     eax, 3
    jne     .fail
    EXPECT_D [cd_buf + 512], 40         ; the oldest edit's column first
    EXPECT_D [cd_buf + 516], 40
    EXPECT_D [cd_buf + 520], -2
    EXPECT_D [cd_buf + 524], 0
    EXPECT_D [cd_buf + 528], 62
    EXPECT_D [cd_buf + 532], 62
    EXPECT_D [cd_buf + 536], 0x5A5A5A5A ; nothing past n is written
    EXPECT_D [net_edit_n], 4            ; and the queue is as it was
    lea     rdi, [cd_buf + 512]
    mov     esi, 2
    call    net_edit_columns
    cmp     eax, 2                      ; at most max
    jne     .fail
    EXPECT_D [cd_buf + 520], -2
    lea     rdi, [cd_buf + 512]
    xor     esi, esi
    call    net_edit_columns
    test    eax, eax
    jnz     .fail
    mov     byte [net_role], NET_ROLE_GUEST     ; only the host streams for waiting edits
    lea     rdi, [cd_buf + 512]
    mov     esi, 8
    call    net_edit_columns
    test    eax, eax
    jnz     .fail
    mov     byte [net_role], NET_ROLE_OFF
    lea     rdi, [cd_buf + 512]
    mov     esi, 8
    call    net_edit_columns
    test    eax, eax
    jnz     .fail
    mov     byte [net_role], NET_ROLE_HOST      ; 40 distinct columns: 32 are given, whatever max says
    mov     dword [net_edit_n], 0
    xor     r13d, r13d
.many:
    mov     edi, r13d
    shl     edi, 4
    add     edi, 2000
    mov     esi, 40
    mov     edx, 2000
    mov     ecx, STONE
    mov     r8d, 1
    call    nw_apply_edit
    inc     r13d
    cmp     r13d, 40
    jb      .many
    EXPECT_D [net_edit_n], 40
    lea     rdi, [cd_buf + 1024]
    mov     esi, 100
    call    net_edit_columns
    cmp     eax, 32
    jne     .fail
    EXPECT_D [cd_buf + 1024], 125       ; (2000 >> 4: the first edit)
    EXPECT_D [cd_buf + 1024 + 31 * 8], 156
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    mov     byte [net_role], NET_ROLE_OFF
    mov     dword [net_edit_n], 0
    call    world_clear
    mov     eax, ebx
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- planes ----------------------------------------------------------------------------------------------
; Modelled on the boat tests. The seat of a guest is the host's to give; a plane's pilot is the guest whose pose
; messages move it.

; board_plane(edi from, esi plane): PLANE_BOARD {plane} from that guest
board_plane:
    sub     rsp, 8
    mov     [small_buf + 48], sil
    mov     esi, MT_PLANE_BOARD
    lea     rdx, [small_buf + 48]
    mov     ecx, 1
    call    nw_on_plane_board
    add     rsp, 8
    ret

; pose_msg(xmm0 x, xmm1 y, xmm2 z): the payload of PLANE_POSE / PLANE_LEAVE for plane 0 at cd_buf + 1024: in the
; air, heading 90, pitch, bank, speed and vertical speed 0
pose_msg:
    sub     rsp, 8
    lea     rdi, [cd_buf + 1028]
    call    net_pos_out
    mov     dword [cd_buf + 1024], 0x100
    mov     eax, [kp_90]
    mov     [cd_buf + 1044], eax
    mov     dword [cd_buf + 1048], 0
    mov     dword [cd_buf + 1052], 0
    mov     dword [cd_buf + 1056], 0
    mov     dword [cd_buf + 1060], 0
    add     rsp, 8
    ret

; plane_world(): no world, no planes, nobody seated
plane_world:
    sub     rsp, 8
    call    world_clear
    call    planes_clear
    add     rsp, 8
    ret

; plane_end(): the network, the capture and the planes put away
plane_end:
    sub     rsp, 8
    mov     byte [net_role], NET_ROLE_OFF
    call    peers_free
    call    planes_clear
    call    cap_off
    call    world_clear
    add     rsp, 8
    ret

; ---- net_plane_seats ---------------------------------------------------------------------------------------
; The host gives the first guest to board the pilot's seat, the next three the gunners' (left, right, tail) and
; refuses a fifth; a guest who boards again is told yes again in the seat he has (nobody else gets it); boarding
; another plane lets go of the seat he held; a plane that is not in use is refused.
test_net_plane_seats:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 8
    call    plane_world
    mov     dword [planes + PLANEENT.used], 1
    mov     dword [planes + PLANEENT_size + PLANEENT.used], 1
    mov     byte [net_role], NET_ROLE_HOST
    mov     edi, 5
    call    peers_ready
    call    cap_on
    mov     r12d, 1
.board:
    mov     edi, r12d
    xor     esi, esi
    call    board_plane
    inc     r12d
    cmp     r12d, 6
    jb      .board
    xor     r12d, r12d
.answer:                                ; guest n + 1 got seat n, the fifth none
    mov     edi, r12d
    call    cap_rec
    test    rax, rax
    jz      .fail
    lea     ecx, [r12 + 1]
    cmp     [rax], cl
    jne     .fail
    cmp     byte [rax + 1], MT_PLANE_BOARD_OK
    jne     .fail
    cmp     word [rax + 2], 3
    jne     .fail
    cmp     byte [rax + 4], 0
    jne     .fail
    cmp     r12d, 4
    jae     .refused
    cmp     byte [rax + 5], r12b
    jne     .fail
    cmp     byte [rax + 6], 1
    jne     .fail
    jmp     .next
.refused:
    cmp     byte [rax + 5], 0
    jne     .fail
    cmp     byte [rax + 6], 0
    jne     .fail
.next:
    inc     r12d
    cmp     r12d, 5
    jb      .answer
    mov     edi, 1                      ; guest 1 clicks again
    xor     esi, esi
    call    board_plane
    EXPECT_CAP 5, 1, MT_PLANE_BOARD_OK, 3
    cmp     byte [rax + 5], 0
    jne     .fail
    cmp     byte [rax + 6], 1
    jne     .fail
    EXPECT_D [planes + PLANEENT.occ], 2
    EXPECT_D [planes + PLANEENT.occ + 4], 3
    EXPECT_D [planes + PLANEENT.occ + 8], 4
    EXPECT_D [planes + PLANEENT.occ + 12], 5
    mov     edi, 1                      ; ... and boards the other plane: his old seat is free
    mov     esi, 1
    call    board_plane
    EXPECT_CAP 6, 1, MT_PLANE_BOARD_OK, 3
    cmp     byte [rax + 4], 1
    jne     .fail
    cmp     byte [rax + 5], 0
    jne     .fail
    cmp     byte [rax + 6], 1
    jne     .fail
    EXPECT_D [planes + PLANEENT.occ], 0
    EXPECT_D [planes + PLANEENT_size + PLANEENT.occ], 2
    mov     edi, 2                      ; a plane nobody put down
    mov     esi, 3
    call    board_plane
    EXPECT_CAP 7, 2, MT_PLANE_BOARD_OK, 3
    cmp     byte [rax + 6], 0
    jne     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    plane_end
    mov     eax, ebx
    add     rsp, 8
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- net_plane_msgs ------------------------------------------------------------------------------------------
; The seven plane message ids are distinct, inside the table, and each holds its own handler.
test_net_plane_msgs:
    xor     ecx, ecx
.l:
    lea     rax, [plane_ids]
    mov     edx, [rax + rcx * 4]
    cmp     edx, NUM_MT
    jae     .fail
    lea     rax, [net_handlers]
    mov     rax, [rax + rdx * 8]
    lea     rsi, [plane_hs]
    cmp     rax, [rsi + rcx * 8]
    jne     .fail
    xor     r8d, r8d
.earlier:
    cmp     r8d, ecx
    jae     .next
    lea     rax, [plane_ids]
    cmp     edx, [rax + r8 * 4]
    je      .fail
    inc     r8d
    jmp     .earlier
.next:
    inc     ecx
    cmp     ecx, 7
    jb      .l
    xor     eax, eax
    ret
.fail:
    mov     eax, 1
    ret

; ---- net_plane_pose ----------------------------------------------------------------------------------------
; A pose is applied when it is finite, inside 65536 on x and z, y in 0..255 and within 64 blocks of the plane on
; each axis (a step of 2 is; NaN, a teleport of 98 blocks and a height of 300 are not); only the plane's pilot's
; pose messages count.
test_net_plane_pose:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 16
    call    plane_world
    mov     dword [planes + PLANEENT.used], 1
    mov     dword [planes + BODY.x], __float32__(10.5)
    mov     dword [planes + BODY.y], __float32__(20.5)
    mov     dword [planes + BODY.z], __float32__(10.5)
    mov     dword [planes + PLANEENT.occ], 2
    mov     byte [net_role], NET_ROLE_HOST
    mov     edi, 2
    call    peers_ready
    movss   xmm0, [kp_12_5]
    movss   xmm1, [kp_20_5]
    movss   xmm2, [kp_10_5]
    call    pose_msg
    lea     rdi, [cd_buf + 1024]
    call    plane_pose_apply
    cmp     eax, 1
    jne     .fail
    EXPECT_D [planes + BODY.x], __float32__(12.5)
    EXPECT_D [planes + PLANEENT.air], 1
    EXPECT_D [planes + BODY.yaw], __float32__(90.0)
    mov     eax, [kp_nan]
    mov     [cd_buf + 1052], eax        ; the speed is not a number
    lea     rdi, [cd_buf + 1024]
    call    plane_pose_apply
    test    eax, eax
    jnz     .fail
    movss   xmm0, [kp_110_5]            ; a teleport
    movss   xmm1, [kp_20_5]
    movss   xmm2, [kp_10_5]
    call    pose_msg
    lea     rdi, [cd_buf + 1024]
    call    plane_pose_apply
    test    eax, eax
    jnz     .fail
    movss   xmm0, [kp_12_5]             ; above the world
    movss   xmm1, [kp_300]
    movss   xmm2, [kp_10_5]
    call    pose_msg
    lea     rdi, [cd_buf + 1024]
    call    plane_pose_apply
    test    eax, eax
    jnz     .fail
    EXPECT_D [planes + BODY.x], __float32__(12.5)
    movss   xmm0, [kp_13_5]             ; the pilot's message moves the plane, another guest's does not
    movss   xmm1, [kp_20_5]
    movss   xmm2, [kp_10_5]
    call    pose_msg
    mov     edi, 2
    mov     esi, MT_PLANE_POSE
    lea     rdx, [cd_buf + 1024]
    mov     ecx, 40
    call    nw_on_plane_pose
    EXPECT_D [planes + BODY.x], __float32__(12.5)
    movss   xmm0, [kp_13_5]
    movss   xmm1, [kp_20_5]
    movss   xmm2, [kp_10_5]
    call    pose_msg
    mov     edi, 1
    mov     esi, MT_PLANE_POSE
    lea     rdx, [cd_buf + 1024]
    mov     ecx, 40
    call    nw_on_plane_pose
    EXPECT_D [planes + BODY.x], __float32__(13.5)
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    plane_end
    mov     eax, ebx
    add     rsp, 16
    pop     rbx
    pop     rbp
    ret

; ---- net_plane_rec -----------------------------------------------------------------------------------------
; A PLANEREC carries the slot, the seats' occupants, the position, heading, pitch, bank, speed and vertical speed
; and a guest's copy takes them: a new copy starts on the position, an old one only moves its target; the plane the
; guest flies keeps his pose but learns the seats. SNAP_PLANES makes the planes it lists and drops the others (but
; the one the guest sits in).
test_net_plane_rec:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    plane_world
    lea     rdi, [planes + 2 * PLANEENT_size]
    mov     dword [rdi + PLANEENT.used], 1
    mov     dword [rdi + BODY.x], __float32__(40.5)
    mov     dword [rdi + BODY.y], __float32__(30.5)
    mov     dword [rdi + BODY.z], __float32__(50.5)
    mov     dword [rdi + BODY.yaw], __float32__(135.0)
    mov     dword [rdi + BODY.vy], __float32__(-2.5)
    mov     dword [rdi + PLANEENT.pitch], __float32__(12.0)
    mov     dword [rdi + PLANEENT.roll], __float32__(-7.0)
    mov     dword [rdi + PLANEENT.speed], __float32__(15.5)
    mov     dword [rdi + PLANEENT.air], 1
    mov     dword [rdi + PLANEENT.occ], 2
    mov     dword [rdi + PLANEENT.occ + 4], 3
    mov     dword [rdi + PLANEENT.occ + 12], 5
    lea     rdi, [cd_buf + 2000]
    lea     rsi, [planes + 2 * PLANEENT_size]
    mov     edx, 2
    call    nm_plane_enc
    cmp     byte [cd_buf + 2000], 2     ; slot, air, the four seats
    jne     .fail
    cmp     byte [cd_buf + 2001], 1
    jne     .fail
    cmp     dword [cd_buf + 2002], 0x05000302
    jne     .fail
    call    planes_clear
    lea     rdi, [cd_buf + 2000]
    call    nm_plane_dec
    EXPECT_D [planes + 2 * PLANEENT_size + PLANEENT.used], 1
    EXPECT_D [planes + 2 * PLANEENT_size + PLANEENT.occ], 2
    EXPECT_D [planes + 2 * PLANEENT_size + PLANEENT.occ + 4], 3
    EXPECT_D [planes + 2 * PLANEENT_size + PLANEENT.occ + 8], 0
    EXPECT_D [planes + 2 * PLANEENT_size + PLANEENT.occ + 12], 5
    EXPECT_D [planes + 2 * PLANEENT_size + PLANEENT.air], 1
    EXPECT_D [planes + 2 * PLANEENT_size + PLANEENT.pitch], __float32__(12.0)
    EXPECT_D [planes + 2 * PLANEENT_size + PLANEENT.roll], __float32__(-7.0)
    EXPECT_D [planes + 2 * PLANEENT_size + PLANEENT.speed], __float32__(15.5)
    EXPECT_D [planes + 2 * PLANEENT_size + BODY.vy], __float32__(-2.5)
    EXPECT_D [planes + 2 * PLANEENT_size + BODY.x], __float32__(40.5)
    EXPECT_D [planes + 2 * PLANEENT_size + BODY.y], __float32__(30.5)
    EXPECT_D [planes + 2 * PLANEENT_size + BODY.z], __float32__(50.5)
    EXPECT_D [planes + 2 * PLANEENT_size + BODY.yaw], __float32__(135.0)
    EXPECT_D [plane_tgt + 2 * 16], __float32__(40.5)
    EXPECT_D [plane_tgt + 2 * 16 + 12], __float32__(135.0)
    mov     dword [planes + 2 * PLANEENT_size + BODY.x], __float32__(44.5)   ; the record of a moved plane
    lea     rdi, [cd_buf + 2000]
    lea     rsi, [planes + 2 * PLANEENT_size]
    mov     edx, 2
    call    nm_plane_enc
    mov     dword [planes + 2 * PLANEENT_size + BODY.x], __float32__(40.5)
    lea     rdi, [cd_buf + 2000]
    call    nm_plane_dec
    EXPECT_D [planes + 2 * PLANEENT_size + BODY.x], __float32__(40.5)       ; the copy stays, its target moves
    EXPECT_D [plane_tgt + 2 * 16], __float32__(44.5)
    mov     dword [plane_riding], 3     ; the guest flies it: his pose stays
    mov     dword [planes + 2 * PLANEENT_size + PLANEENT.pitch], __float32__(1.0)
    mov     dword [planes + 2 * PLANEENT_size + PLANEENT.occ], 0
    lea     rdi, [cd_buf + 2000]
    call    nm_plane_dec
    EXPECT_D [planes + 2 * PLANEENT_size + PLANEENT.pitch], __float32__(1.0)
    EXPECT_D [planes + 2 * PLANEENT_size + PLANEENT.occ], 2
    mov     dword [plane_riding], 0
    mov     dword [planes + PLANEENT.used], 1       ; SNAP_PLANES {1, the record}: plane 0 is not listed
    mov     dword [planes + 2 * PLANEENT_size + PLANEENT.used], 0
    mov     dword [cd_buf + 3000], 1
    lea     rdi, [cd_buf + 3004]
    lea     rsi, [planes + 2 * PLANEENT_size]
    mov     edx, 2
    call    nm_plane_enc
    mov     byte [net_role], NET_ROLE_GUEST
    xor     edi, edi
    mov     esi, MT_SNAP_PLANES
    lea     rdx, [cd_buf + 3000]
    mov     ecx, 48
    call    nm_on_snap_planes
    EXPECT_D [planes + PLANEENT.used], 0
    EXPECT_D [planes + 2 * PLANEENT_size + PLANEENT.used], 1
    mov     dword [planes + PLANEENT.used], 1       ; ... unless the guest sits in it
    mov     dword [plane_riding], 1
    xor     edi, edi
    mov     esi, MT_SNAP_PLANES
    lea     rdx, [cd_buf + 3000]
    mov     ecx, 48
    call    nm_on_snap_planes
    EXPECT_D [planes + PLANEENT.used], 1
    mov     ecx, 47                     ; a message too short for its count is dropped
    mov     dword [planes + 2 * PLANEENT_size + PLANEENT.used], 0
    xor     edi, edi
    mov     esi, MT_SNAP_PLANES
    lea     rdx, [cd_buf + 3000]
    call    nm_on_snap_planes
    EXPECT_D [planes + 2 * PLANEENT_size + PLANEENT.used], 0
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    plane_end
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- net_plane_leave -------------------------------------------------------------------------------------------
; A gunner who leaves frees his seat and nothing else; the pilot who leaves frees his, the plane takes the pose he
; left it in and is pilotless (throttle 0); a guest that does not sit in the plane is ignored.
test_net_plane_leave:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 16
    call    plane_world
    mov     dword [planes + PLANEENT.used], 1
    mov     dword [planes + BODY.x], __float32__(10.5)
    mov     dword [planes + BODY.y], __float32__(20.5)
    mov     dword [planes + BODY.z], __float32__(10.5)
    mov     dword [planes + PLANEENT.throttle], __float32__(0.5)
    mov     dword [planes + PLANEENT.occ], 2
    mov     dword [planes + PLANEENT.occ + 4], 3
    mov     byte [net_role], NET_ROLE_HOST
    mov     edi, 3
    call    peers_ready
    movss   xmm0, [kp_12_5]
    movss   xmm1, [kp_20_5]
    movss   xmm2, [kp_10_5]
    call    pose_msg
    mov     edi, 3                      ; a guest who is not aboard
    mov     esi, MT_PLANE_LEAVE
    lea     rdx, [cd_buf + 1024]
    mov     ecx, 40
    call    nw_on_plane_leave
    EXPECT_D [planes + PLANEENT.occ], 2
    EXPECT_D [planes + PLANEENT.occ + 4], 3
    mov     edi, 2                      ; the gunner
    mov     esi, MT_PLANE_LEAVE
    lea     rdx, [cd_buf + 1024]
    mov     ecx, 40
    call    nw_on_plane_leave
    EXPECT_D [planes + PLANEENT.occ + 4], 0
    EXPECT_D [planes + PLANEENT.occ], 2
    EXPECT_D [planes + BODY.x], __float32__(10.5)
    mov     edi, 1                      ; the pilot
    mov     esi, MT_PLANE_LEAVE
    lea     rdx, [cd_buf + 1024]
    mov     ecx, 40
    call    nw_on_plane_leave
    EXPECT_D [planes + PLANEENT.occ], 0
    EXPECT_D [planes + BODY.x], __float32__(12.5)
    EXPECT_D [planes + PLANEENT.throttle], 0
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    plane_end
    mov     eax, ebx
    add     rsp, 16
    pop     rbx
    pop     rbp
    ret

; ---- net_plane_crash -------------------------------------------------------------------------------------------
; A crash the host steps hurts every guest in the plane (HURT, 12 damage by falling) and lets him go (BOARD_OK
; not ok), puts the host's own seat down and empties the plane. A guest pilot's crash report (PLANE_BREAK, crash)
; does the same for the others in it; a report from a guest who does not pilot it is ignored.
test_net_plane_crash:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 8
    call    plane_world
    mov     r12d, [game_mode]
    lea     rsi, [banner_text]
    lea     rdi, [save_banner]
    mov     ecx, 64
    rep     movsb
    mov     dword [game_mode], MODE_CREATIVE
    mov     byte [net_role], NET_ROLE_HOST
    mov     edi, 2
    call    peers_ready
    mov     dword [planes + PLANEENT.used], 1
    mov     dword [planes + PLANEENT.occ], 1        ; the host pilots, guest 1 is the left gunner, guest 2 the right
    mov     dword [planes + PLANEENT.occ + 4], 2
    mov     dword [planes + PLANEENT.occ + 8], 3
    mov     dword [plane_riding], 1
    call    cap_on
    xor     edi, edi
    call    planes_crash
    EXPECT_CAP 0, 1, MT_HURT, 32
    cmp     dword [rax + 4], 12                 ; PL_CRASH_DMG
    jne     .fail
    cmp     byte [rax + 8], CAUSE_FALL
    jne     .fail
    EXPECT_CAP 1, 1, MT_PLANE_BOARD_OK, 3
    cmp     byte [rax + 6], 0
    jne     .fail
    EXPECT_CAP 2, 2, MT_HURT, 32
    EXPECT_CAP 3, 2, MT_PLANE_BOARD_OK, 3
    EXPECT_NO_CAP 4
    EXPECT_D [planes + PLANEENT.used], 0
    EXPECT_D [planes + PLANEENT.occ + 4], 0
    EXPECT_D [plane_riding], 0
    mov     dword [planes + PLANEENT.used], 1       ; guest 1 pilots, guest 2 is a gunner
    mov     dword [planes + PLANEENT.occ], 2
    mov     dword [planes + PLANEENT.occ + 4], 3
    call    cap_on
    mov     byte [small_buf + 48], 0
    mov     byte [small_buf + 49], 1
    mov     edi, 2                      ; the gunner's crash report means nothing
    mov     esi, MT_PLANE_BREAK
    lea     rdx, [small_buf + 48]
    mov     ecx, 2
    call    nw_on_plane_break
    EXPECT_NO_CAP 0
    EXPECT_D [planes + PLANEENT.used], 1
    mov     edi, 1
    mov     esi, MT_PLANE_BREAK
    lea     rdx, [small_buf + 48]
    mov     ecx, 2
    call    nw_on_plane_break
    EXPECT_CAP 0, 2, MT_HURT, 32
    EXPECT_CAP 1, 2, MT_PLANE_BOARD_OK, 3
    EXPECT_NO_CAP 2                     ; (the pilot took his own damage)
    EXPECT_D [planes + PLANEENT.used], 0
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    lea     rsi, [save_banner]
    lea     rdi, [banner_text]
    mov     ecx, 64
    rep     movsb
    mov     [game_mode], r12d
    call    plane_end
    mov     eax, ebx
    add     rsp, 8
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- net_plane_place -----------------------------------------------------------------------------------------
; PLANE_PLACE names the block a guest's ray hit: the host puts a plane on its top with the guest's heading; a
; plane that cannot be put there (the table is full) goes back to the guest in Survival and nothing does in
; Creative; a cell nothing stands on is refused.
test_net_plane_place:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    plane_world
    mov     r12d, [game_mode]
    lea     rsi, [banner_text]
    lea     rdi, [save_banner]
    mov     ecx, 64
    rep     movsb
    SETB    70, 9, 70, STONE
    mov     byte [net_role], NET_ROLE_HOST
    mov     edi, 1
    call    peers_ready
    mov     dword [game_mode], MODE_CREATIVE
    call    cap_on
    call    place_plane
    EXPECT_NO_CAP 0
    EXPECT_D [planes + PLANEENT.used], 1
    EXPECT_D [planes + BODY.x], __float32__(70.5)
    EXPECT_D [planes + BODY.y], __float32__(10.0)
    EXPECT_D [planes + BODY.yaw], __float32__(90.0)
    mov     dword [game_mode], MODE_SURVIVAL
    mov     byte [banner_text], 0
    xor     r13d, r13d
.full:
    imul    eax, r13d, PLANEENT_size
    lea     rcx, [planes]
    mov     dword [rcx + rax + PLANEENT.used], 1
    inc     r13d
    cmp     r13d, MAX_PLANES
    jb      .full
    call    cap_on
    call    place_plane
    EXPECT_CAP 0, 1, MT_GIVE, 4
    cmp     byte [rax + 4], PLANE
    jne     .fail
    EXPECT_NO_CAP 1
    cmp     byte [banner_text], 0
    jne     .fail                       ; no banner on the host
    call    planes_clear
    SETB    70, 9, 70, AIR              ; nothing to stand on
    call    cap_on
    call    place_plane
    EXPECT_D [planes + PLANEENT.used], 0
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    lea     rsi, [save_banner]
    lea     rdi, [banner_text]
    mov     ecx, 64
    rep     movsb
    mov     [game_mode], r12d
    call    plane_end
    mov     eax, ebx
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; place_plane(): PLANE_PLACE from guest 1: the block (70, 9, 70), heading 90
place_plane:
    sub     rsp, 8
    lea     rdi, [cd_buf + 1024]
    movss   xmm0, [kp_70_5]
    movss   xmm1, [kp_9_5]
    movss   xmm2, [kp_70_5]
    call    net_pos_out
    mov     eax, [kp_90]
    mov     [cd_buf + 1040], eax
    mov     edi, 1
    mov     esi, MT_PLANE_PLACE
    lea     rdx, [cd_buf + 1024]
    mov     ecx, 20
    call    nw_on_plane_place
    add     rsp, 8
    ret
