; test_networld.asm - the world on the wire: block edits that wait for their column, the guest's column
; verdicts, and the container puts with their sequence numbers. The network is the capture seam of
; netsync (net_capture / net_captured: records slot u8, type u8, len u16, payload[len]).
%include "common.inc"
default rel

global test_net_edit_queue_replay, test_net_column_verdict, test_net_container_put_seq

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

%define STK(id, n, dmg) ((id) | ((n) << 8) | ((dmg) << 16))
%define CAP_SIZE 8192
%define NEDIT_TTL 600                   ; frames a queued edit waits (networld.asm)

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

section .bss
alignb 16
cap_buf:   resb CAP_SIZE
cd_buf:    resb 65536
small_buf: resb 64
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
    EXPECT_CAP 0, 255, MT_BLOCK, 10     ; relayed to every guest
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
    EDIT    53, 300, 55, STONE, 1       ; y outside the world: dropped, not queued
    EXPECT_D [net_edit_n], 0
    EDIT    53, 41, 55, NUM_BLOCKS, 1   ; no such block
    EXPECT_D [net_edit_n], 0
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
    lea     rdi, [net_peers + PEER_size]
    mov     ecx, PEER_size / 8
    xor     eax, eax
    rep     stosq
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
    EXPECT_D [net_colv_pending], 31     ; the 33rd blob found no buffer: its entry is forgotten
    mov     edi, 132
    mov     esi, 100
    call    net_column_verdict
    test    eax, eax
    jnz     .fail
    call    cap_count
    cmp     eax, 65
    jne     .fail                       ; ... and asked again
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
