; test_net.asm - the transport (net.asm) on real 127.0.0.1 sockets, with an injected clock (16 ms per loop)
; and a deterministic loss: ordered exactly-once delivery of reliable messages through 30 % loss, a big
; message through 20 % loss (with unreliable snapshots getting through the backlog), the u16 wrap of reliable
; ids, the 10 s connection timeout, and the join handshake: refused joins (a version byte of 2, DENY_FULL,
; DENY_NAME, DENY_CLOSED), one request arriving by several candidate addresses, hostile packets from an
; accepted guest, and the join target parser; a 0.6 s round trip through a delay line made of two forwarding
; sockets (three 200000-byte blobs, then a sender that must stop at its sent-packet ring), and a full event
; queue (a CONNECT flood, goodbyes and timeouts that find no room), and a join whose ACCEPT and the host's first
; message are read by one poll (the caller must get NE_ACCEPTED first). Endpoints are mmap'd per test
; (net_ep_size bytes); the game's own net_ep is never touched.
%include "common.inc"
default rel

global test_net_reliable_lossy, test_net_big_message, test_net_rid_wrap, test_net_timeout
global test_net_handshake_deny
global test_net_long_rtt, test_net_event_queue_full
global test_net_accept_then_data_one_poll

extern net_ep_size, net_ep_open, net_ep_close, net_ep_poll, net_ep_next_event, net_ep_flush
extern net_ep_send, net_ep_send_big, net_ep_room, net_ep_accept, net_ep_deny
extern net_ep_join, net_ep_join_state, net_ep_join_err, net_ep_set_test, net_ep_test_rid
extern net_parse_addr, net_format_addr, net_local_ip

%define NSYS_MMAP        9
%define NSYS_MUNMAP      11
%define NSYS_SOCKET      41
%define NSYS_SENDTO      44
%define NSYS_RECVFROM    45
%define NSYS_BIND        49
%define NSYS_GETSOCKNAME 51
%define STEP_NS          16000000       ; one loop = 16 ms
%define ST_N             0              ; delivery state: messages delivered
%define ST_BAD           4              ; ... of them wrong
%define ST_MODE          8              ; 0: message i has the pattern of seed i; 1: one blob; 2: only count them
%define ST_WLEN          12             ; mode 1: expected length, type and pattern seed
%define ST_WTYPE         16
%define ST_WSEED         20
%define ST_UN            24             ; unreliable MT_PSTATE messages delivered
%define ST_LASTSEQ       28             ; the number of the newest of them
%define FW_ENTRIES       1024           ; the delay line: datagrams in flight
%define FW_ESIZE         1248           ; release ms u32, dest u32 (0 = A, 1 = B), len u32, pad u32, data[1232]
%define LONG_LOOPS       300            ; net_long_rtt: loops allowed for the three blobs (219 are needed)
%define RING_PKTS        4096           ; net_long_rtt: the sent-packet ring of net.asm (SPK_COUNT)
%define EVQ_CONNECTS     56             ; net_event_queue_full: the queue holds 64 events, the last NET_MAX_PEERS (8)
                                        ; places are not for CONNECT requests

section .rodata
s_bob:      db "Bob", 0
s_eve:      db "Eve", 0
a_s1:       db "1.2.3.4", 0
a_s2:       db "10.20.30.40:80", 0
a_s3:       db "255.255.255.255:65535", 0
a_s4:       db "192.168.1.20:27615", 0
a_s5:       db "127.0.0.1:1", 0
b_0:        db 0
b_1:        db "1.2.3", 0
b_2:        db "1.2.3.4.5", 0
b_3:        db "256.1.1.1", 0
b_4:        db "1.2.3.4:", 0
b_5:        db "1.2.3.4:0", 0
b_6:        db "1.2.3.4:65536", 0
b_7:        db "a.b.c.d", 0
b_8:        db "1.2.3.4 ", 0
b_9:        db " 1.2.3.4", 0
b_10:       db "1..3.4", 0
b_11:       db "1.2.3.4:80x", 0
b_12:       db "1234.1.1.1", 0
align 8
bad_addrs:  dq b_0, b_1, b_2, b_3, b_4, b_5, b_6, b_7, b_8, b_9, b_10, b_11, b_12, 0

section .bss
alignb 8
t_clock:    resq 1                      ; the injected clock, ns
t_a:        resq 1                      ; host-style endpoint (accepts slot 1)
t_b:        resq 1                      ; joining endpoint (its connection to the host is slot 0)
t_mode:     resd 1                      ; what step does with a CONNECT_REQ on A: 0 nothing, 1 accept, 2 deny
t_reason:   resd 1                      ; DENY_* for mode 2
t_pa:       resd 1                      ; A's port
t_a_tmo:    resd 1                      ; slot + 1 of an NE_TIMEOUT seen on A / on B
t_b_tmo:    resd 1
t_a_reqs:   resd 1                      ; NE_CONNECT_REQ seen on A
t_addr:     resb 8                      ; NADDR of A on 127.0.0.1
t_ev:       resb 48
st_a:       resd 8                      ; what A / B were delivered
st_b:       resd 8
t_buf:      resb 1104
t_big:      resb 200064
t_raw:      resb 128
t_sa:       resb 16
t_r1fd:     resd 1                      ; two raw sockets that play joining guests
t_r1port:   resd 1                      ; the first one's port, network order
t_r2fd:     resd 1
t_tok:      resd 1                      ; the token of an ACCEPT seen
t_ev2:      resb 48
t_pkt:      resb 1200                   ; a DATA packet of the first raw socket
t_seq:      resd 1                      ; its packet number
alignb 8
fw_ring:    resq 1                      ; the delay line (mmap'd FW_ENTRIES * FW_ESIZE)
fw_fa:      resd 1                      ; socket: the address A sees as "B"
fw_fb:      resd 1                      ; socket: the address B joins as "the host"
fw_bport:   resd 1                      ; B's real port (network order), learned from its first datagram
fw_delay:   resd 1                      ; one-way delay, ms of the injected clock
fw_head:    resd 1
fw_tail:    resd 1
fw_addr:    resb 8                      ; NADDR of FB, what B joins
t_nonce:    resd 1                      ; the next nonce of a synthetic CONNECT_REQ
t_sev:      resb 48                     ; a synthetic NE_CONNECT_REQ
ec_req:     resd 1                      ; what ev_drain counted: CONNECT_REQ, DISCONNECTED, TIMEOUT, others
ec_disc:    resd 1
ec_tmo:     resd 1
ec_other:   resd 1
ec_d1:      resd 1                      ; DISCONNECTED of slot 1 with reason DENY_CLOSED
ec_last_kind: resd 1                    ; the last event taken
ec_last_slot: resd 1
ec_last_reason: resd 1
t_greet:    resd 1                      ; A queues message 0 of the pattern for a guest it accepts (as netsync does with WORLDINFO)
t_acc_seen: resd 1                      ; NE_ACCEPTED events fetched on B
t_acc_n:    resd 1                      ; what B's callback had been given when the first of them was fetched

section .text

; ---- patterns ----------------------------------------------------------------------------------------

; pat_len(edi i) -> eax 1..1100: the length of message i (all different for i < 1100)
pat_len:
    imul    eax, edi, 37
    add     eax, 11
    xor     edx, edx
    mov     ecx, 1100
    div     ecx
    lea     eax, [rdx + 1]
    ret

; pat_fill(rdi buf, esi seed, edx len): byte j = seed * 131 + 13 + j * 7 + (j >> 8)
pat_fill:
    imul    esi, esi, 131
    add     esi, 13
    xor     ecx, ecx
.l:
    cmp     ecx, edx
    jae     .done
    mov     eax, ecx
    imul    eax, eax, 7
    add     eax, esi
    mov     r8d, ecx
    shr     r8d, 8
    add     eax, r8d
    mov     [rdi + rcx], al
    inc     ecx
    jmp     .l
.done:
    ret

; pat_check(rsi buf, edi seed, edx len) -> eax 0 when buf holds exactly that pattern
pat_check:
    imul    edi, edi, 131
    add     edi, 13
    xor     ecx, ecx
.l:
    cmp     ecx, edx
    jae     .ok
    mov     eax, ecx
    imul    eax, eax, 7
    add     eax, edi
    mov     r8d, ecx
    shr     r8d, 8
    add     eax, r8d
    cmp     [rsi + rcx], al
    jne     .bad
    inc     ecx
    jmp     .l
.ok:
    xor     eax, eax
    ret
.bad:
    mov     eax, 1
    ret

; st_reset(rdi state, esi mode, edx want_len, ecx want_type, r8d want_seed)
st_reset:
    mov     dword [rdi + ST_N], 0
    mov     dword [rdi + ST_BAD], 0
    mov     dword [rdi + ST_UN], 0
    mov     dword [rdi + ST_LASTSEQ], 0
    mov     [rdi + ST_MODE], esi
    mov     [rdi + ST_WLEN], edx
    mov     [rdi + ST_WTYPE], ecx
    mov     [rdi + ST_WSEED], r8d
    ret

; deliver_chk(edi slot, esi type, rdx payload, ecx len, r8 state): the deliver callback. Mode 0: the n-th message
; must have type MT_BLOCK + n % 5, length pat_len(n) and the pattern of seed n. Mode 1: the expected blob. Mode 2:
; any message is just counted.
deliver_chk:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, r8
    mov     r13d, esi
    mov     r14, rdx
    mov     r15d, ecx
    cmp     esi, MT_PSTATE
    je      .unrel
    mov     ebx, [r12 + ST_N]
    inc     dword [r12 + ST_N]
    cmp     dword [r12 + ST_MODE], 2
    je      .out
    cmp     dword [r12 + ST_MODE], 1
    je      .big
    mov     edi, ebx
    call    pat_len
    cmp     eax, r15d
    jne     .bad
    mov     eax, ebx
    xor     edx, edx
    mov     ecx, 5
    div     ecx
    add     edx, MT_BLOCK
    cmp     edx, r13d
    jne     .bad
    mov     rsi, r14
    mov     edi, ebx
    mov     edx, r15d
    call    pat_check
    test    eax, eax
    jnz     .bad
    jmp     .out
.unrel:                                 ; 400 bytes: dword 0 is its number (only ever growing: nothing twice,
    cmp     r15d, 400                   ; nothing reordered), the rest is the pattern of seed = number
    jne     .bad
    mov     eax, [r14]
    cmp     eax, [r12 + ST_LASTSEQ]
    jbe     .bad
    mov     [r12 + ST_LASTSEQ], eax
    inc     dword [r12 + ST_UN]
    lea     rsi, [r14 + 4]
    mov     edi, eax
    mov     edx, 396
    call    pat_check
    test    eax, eax
    jz      .out
    jmp     .bad
.big:
    cmp     r15d, [r12 + ST_WLEN]
    jne     .bad
    cmp     r13d, [r12 + ST_WTYPE]
    jne     .bad
    mov     rsi, r14
    mov     edi, [r12 + ST_WSEED]
    mov     edx, r15d
    call    pat_check
    test    eax, eax
    jz      .out
.bad:
    inc     dword [r12 + ST_BAD]
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

deliver_a:
    lea     r8, [st_a]
    jmp     deliver_chk

deliver_b:
    lea     r8, [st_b]
    jmp     deliver_chk

; ---- endpoints ---------------------------------------------------------------------------------------

; ep_new() -> rax a zeroed, page aligned endpoint (mmap) or 0
ep_new:
    mov     eax, NSYS_MMAP
    xor     edi, edi
    mov     esi, [net_ep_size]
    add     esi, 4095
    and     esi, -4096
    mov     edx, 3                      ; PROT_READ | PROT_WRITE
    mov     r10d, 0x22                  ; MAP_PRIVATE | MAP_ANONYMOUS
    mov     r8, -1
    xor     r9d, r9d
    syscall
    cmp     rax, -4096
    jbe     .ok
    xor     eax, eax
.ok:
    ret

; ep_free(rdi ep): close it and give the memory back (a null ep is ignored)
ep_free:
    test    rdi, rdi
    jz      .ret
    push    rdi
    call    net_ep_close
    pop     rdi
    mov     esi, [net_ep_size]
    add     esi, 4095
    and     esi, -4096
    mov     eax, NSYS_MUNMAP
    syscall
.ret:
    ret

teardown:
    sub     rsp, 8
    mov     rdi, [t_a]
    call    ep_free
    mov     rdi, [t_b]
    call    ep_free
    mov     qword [t_a], 0
    mov     qword [t_b], 0
    add     rsp, 8
    ret

; setup_eps(edi drop_pct) -> eax 0 ok: A and B on ephemeral ports with the shared clock and that loss, state cleared
setup_eps:
    push    rbx
    push    r12
    push    r13
    mov     r12d, edi
    mov     qword [t_clock], 1000000000
    mov     dword [t_mode], 0
    mov     dword [t_reason], 0
    mov     dword [t_a_tmo], 0
    mov     dword [t_b_tmo], 0
    mov     dword [t_a_reqs], 0
    mov     dword [t_greet], 0
    mov     dword [t_acc_seen], 0
    mov     dword [t_acc_n], 0
    call    ep_new
    mov     [t_a], rax
    test    rax, rax
    jz      .fail
    call    ep_new
    mov     [t_b], rax
    test    rax, rax
    jz      .fail
    mov     rdi, [t_a]
    xor     esi, esi
    mov     edx, 1
    call    net_ep_open
    test    eax, eax
    jle     .fail
    mov     [t_pa], eax
    mov     rdi, [t_b]
    xor     esi, esi
    mov     edx, 1
    call    net_ep_open
    test    eax, eax
    jle     .fail
    mov     rdi, [t_a]
    mov     esi, r12d
    lea     rdx, [t_clock]
    call    net_ep_set_test
    mov     rdi, [t_b]
    mov     esi, r12d
    lea     rdx, [t_clock]
    call    net_ep_set_test
    mov     dword [t_addr], 0x0100007F  ; 127.0.0.1:port of A
    mov     eax, [t_pa]
    rol     ax, 8
    mov     [t_addr + 4], ax
    mov     word [t_addr + 6], 0
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; drain_a(): A's events. A CONNECT_REQ is accepted into slot 1 (t_mode 1) or denied with t_reason (t_mode 2).
drain_a:
    push    rbx
.next:
    mov     rdi, [t_a]
    lea     rsi, [t_ev]
    call    net_ep_next_event
    test    eax, eax
    jz      .out
    movzx   eax, byte [t_ev + NETEVENT.kind]
    cmp     eax, NE_CONNECT_REQ
    je      .req
    cmp     eax, NE_TIMEOUT
    jne     .next
    movzx   eax, byte [t_ev + NETEVENT.slot]
    inc     eax
    mov     [t_a_tmo], eax
    jmp     .next
.req:
    inc     dword [t_a_reqs]
    mov     eax, [t_mode]
    cmp     eax, 1
    jne     .notacc
    mov     rdi, [t_a]
    mov     esi, 1
    lea     rdx, [t_ev]
    call    net_ep_accept
    cmp     dword [t_greet], 0
    je      .next
    mov     edi, 1
    call    greet
    jmp     .next
.notacc:
    cmp     eax, 2
    jne     .next
    mov     rdi, [t_a]
    lea     rsi, [t_ev]
    mov     edx, [t_reason]
    call    net_ep_deny
    jmp     .next
.out:
    pop     rbx
    ret

; drain_b(): B's events: an NE_ACCEPTED is counted, with the number of messages B's callback had been given by then;
; an NE_TIMEOUT is noted
drain_b:
    push    rbx
.next:
    mov     rdi, [t_b]
    lea     rsi, [t_ev]
    call    net_ep_next_event
    test    eax, eax
    jz      .out
    cmp     byte [t_ev + NETEVENT.kind], NE_ACCEPTED
    jne     .not_acc
    inc     dword [t_acc_seen]
    cmp     dword [t_acc_seen], 1
    jne     .next
    mov     eax, [st_b + ST_N]
    mov     [t_acc_n], eax
    jmp     .next
.not_acc:
    cmp     byte [t_ev + NETEVENT.kind], NE_TIMEOUT
    jne     .next
    movzx   eax, byte [t_ev + NETEVENT.slot]
    inc     eax
    mov     [t_b_tmo], eax
    jmp     .next
.out:
    pop     rbx
    ret

; poll_both(): poll and drain both endpoints, no clock advance, no flush
poll_both:
    sub     rsp, 8
    mov     rdi, [t_a]
    lea     rsi, [deliver_a]
    call    net_ep_poll
    call    drain_a
    mov     rdi, [t_b]
    lea     rsi, [deliver_b]
    call    net_ep_poll
    call    drain_b
    add     rsp, 8
    ret

; step(): one loop: the clock +16 ms, both endpoints poll and drain their events, then both flush
step:
    sub     rsp, 8
    add     qword [t_clock], STEP_NS
    call    poll_both
    mov     rdi, [t_a]
    call    net_ep_flush
    mov     rdi, [t_b]
    call    net_ep_flush
    add     rsp, 8
    ret

; pair_up(edi drop_pct) -> eax 0 when B joined A (A gave it slot 1) within 2000 loops
pair_up:
    push    rbx
    push    r12
    push    r13
    call    setup_eps
    test    eax, eax
    jnz     .out
    mov     dword [t_mode], 1
    mov     rdi, [t_b]
    lea     rsi, [t_addr]
    xor     edx, edx
    lea     rcx, [s_bob]
    xor     r8d, r8d
    call    net_ep_join
    mov     ebx, 2000
.loop:
    call    step
    mov     rdi, [t_b]
    call    net_ep_join_state
    cmp     eax, NJ_CONNECTED
    jne     .more
    mov     rdi, [t_a]
    mov     esi, 1
    call    net_ep_room
    test    eax, eax
    jnz     .joined
.more:
    dec     ebx
    jnz     .loop
    mov     eax, 1
    jmp     .out
.joined:
    xor     eax, eax
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; queue_msgs(edi count): message i (0 <= i < count) of the pattern goes reliably A -> B (slot 1) and B -> A (slot 0).
; -> eax 0 when every send was queued
queue_msgs:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r15d, edi
    xor     ebx, ebx
.msg:
    cmp     ebx, r15d
    jae     .ok
    mov     edi, ebx
    call    pat_len
    mov     r12d, eax                   ; len
    lea     rdi, [t_buf]
    mov     esi, ebx
    mov     edx, r12d
    call    pat_fill
    mov     eax, ebx
    xor     edx, edx
    mov     ecx, 5
    div     ecx
    lea     r13d, [rdx + MT_BLOCK]      ; type
    mov     rdi, [t_a]
    mov     esi, 1
    mov     edx, r13d
    lea     rcx, [t_buf]
    mov     r8d, r12d
    mov     r9d, 1
    call    net_ep_send
    test    eax, eax
    jz      .fail
    mov     rdi, [t_b]
    xor     esi, esi
    mov     edx, r13d
    lea     rcx, [t_buf]
    mov     r8d, r12d
    mov     r9d, 1
    call    net_ep_send
    test    eax, eax
    jz      .fail
    inc     ebx
    jmp     .msg
.ok:
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; run_until(edi want_a, esi want_b, edx extra) -> eax 0 when A and B each were delivered `want` messages within
; 2000 loops and, after `extra` more loops, still exactly that many (nothing delivered twice), none of them wrong
run_until:
    push    rbx
    push    r12
    push    r13
    mov     r12d, edi
    mov     r13d, esi
    mov     ebx, edx
    mov     ecx, 2000
.run:
    push    rcx
    sub     rsp, 8
    call    step
    add     rsp, 8
    pop     rcx
    cmp     [st_a + ST_N], r12d
    jb      .more
    cmp     [st_b + ST_N], r13d
    jae     .arrived
.more:
    dec     ecx
    jnz     .run
    jmp     .fail
.arrived:
    test    ebx, ebx
    jz      .check
.extra:
    call    step
    dec     ebx
    jnz     .extra
.check:
    cmp     [st_a + ST_N], r12d
    jne     .fail
    cmp     [st_b + ST_N], r13d
    jne     .fail
    cmp     dword [st_a + ST_BAD], 0
    jne     .fail
    cmp     dword [st_b + ST_BAD], 0
    jne     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- tests -------------------------------------------------------------------------------------------

; test_net_reliable_lossy() -> eax 0 on pass. Two endpoints on 127.0.0.1, 30 % loss both ways, 16 ms per loop: 300
; reliable messages of 1..1100 bytes each way arrive exactly once, in order, within 2000 loops (and no late
; duplicates in the 100 loops after).
test_net_reliable_lossy:
    push    rbx
    push    r12
    push    r13
    mov     r12d, 1
    mov     edi, 30
    call    pair_up
    test    eax, eax
    jnz     .end
    lea     rdi, [st_a]
    xor     esi, esi
    xor     edx, edx
    xor     ecx, ecx
    xor     r8d, r8d
    call    st_reset
    lea     rdi, [st_b]
    xor     esi, esi
    xor     edx, edx
    xor     ecx, ecx
    xor     r8d, r8d
    call    st_reset
    mov     edi, 300
    call    queue_msgs
    test    eax, eax
    jnz     .end
    mov     edi, 300
    mov     esi, 300
    mov     edx, 100
    call    run_until
    test    eax, eax
    jnz     .end
    xor     r12d, r12d
.end:
    call    teardown
    mov     eax, r12d
    pop     r13
    pop     r12
    pop     rbx
    ret

; test_net_big_message() -> eax 0 on pass. 20 % loss: a 200000-byte blob A -> B and a 30000-byte one B -> A each
; arrive intact as exactly one delivery (type and every byte checked by the callback). The queue accounting is
; checked (184 parts, an oversized blob refused and nothing queued), and one 400-byte unreliable message per
; loop A -> B must keep arriving (over half of them, none wrong or repeated) while the 184 parts are in flight.
test_net_big_message:
    push    rbx
    push    r12
    push    r13
    mov     r12d, 1
    mov     edi, 20
    call    pair_up
    test    eax, eax
    jnz     .end
    lea     rdi, [st_b]
    mov     esi, 1
    mov     edx, 200000
    mov     ecx, MT_COL_DATA
    mov     r8d, 255
    call    st_reset
    lea     rdi, [st_a]
    mov     esi, 1
    mov     edx, 30000
    mov     ecx, MT_PLAYER_SAVE
    mov     r8d, 77
    call    st_reset
    lea     rdi, [t_big]
    mov     esi, 255
    mov     edx, 200000
    call    pat_fill
    mov     rdi, [t_a]
    mov     esi, 1
    mov     edx, MT_COL_DATA
    lea     rcx, [t_big]
    mov     r8d, 200000
    call    net_ep_send_big
    test    eax, eax
    jz      .end
    mov     rdi, [t_a]
    mov     esi, 1
    call    net_ep_room
    cmp     eax, NET_RQ - 184           ; 200000 bytes are 184 parts of 1088
    jne     .end
    mov     rdi, [t_a]                  ; more than NET_BLOB_MAX is refused and queues nothing
    mov     esi, 1
    mov     edx, MT_COL_DATA
    lea     rcx, [t_big]
    mov     r8d, NET_BLOB_MAX + 1
    call    net_ep_send_big
    test    eax, eax
    jnz     .end
    mov     rdi, [t_a]
    mov     esi, 1
    call    net_ep_room
    cmp     eax, NET_RQ - 184
    jne     .end
    lea     rdi, [t_big]
    mov     esi, 77
    mov     edx, 30000
    call    pat_fill
    mov     rdi, [t_b]
    xor     esi, esi
    mov     edx, MT_PLAYER_SAVE
    lea     rcx, [t_big]
    mov     r8d, 30000
    call    net_ep_send_big
    test    eax, eax
    jz      .end
    mov     ebx, 2000                   ; the transfer, with one unreliable message A -> B per loop on top of it
    xor     r13d, r13d                  ; its number
.xfer:
    inc     r13d
    mov     [t_buf], r13d
    lea     rdi, [t_buf + 4]
    mov     esi, r13d
    mov     edx, 396
    call    pat_fill
    mov     rdi, [t_a]
    mov     esi, 1
    mov     edx, MT_PSTATE
    lea     rcx, [t_buf]
    mov     r8d, 400
    xor     r9d, r9d
    call    net_ep_send
    call    step
    cmp     dword [st_b + ST_N], 1
    jb      .more
    cmp     dword [st_a + ST_N], 1
    jae     .xfer_done
.more:
    dec     ebx
    jnz     .xfer
    jmp     .end
.xfer_done:
    mov     eax, r13d                   ; the backlog did not starve the snapshots: more than half of them (the
    shr     eax, 1                      ; loss takes 20 %) arrived meanwhile, none wrong, none twice
    cmp     [st_b + ST_UN], eax
    jbe     .end
    cmp     [st_b + ST_UN], r13d
    ja      .end
    cmp     dword [st_b + ST_BAD], 0
    jne     .end
    mov     edi, 1
    mov     esi, 1
    mov     edx, 50
    call    run_until
    test    eax, eax
    jnz     .end
    xor     r12d, r12d
.end:
    call    teardown
    mov     eax, r12d
    pop     r13
    pop     r12
    pop     rbx
    ret

; test_net_rid_wrap() -> eax 0 on pass. With the next reliable id forced to 65500 on both ends (15 % loss), 100
; messages each way arrive in order across the u16 wrap.
test_net_rid_wrap:
    push    rbx
    push    r12
    push    r13
    mov     r12d, 1
    mov     edi, 15
    call    pair_up
    test    eax, eax
    jnz     .end
    mov     rdi, [t_a]
    mov     esi, 1
    mov     edx, 65500
    call    net_ep_test_rid
    mov     rdi, [t_b]
    xor     esi, esi
    mov     edx, 65500
    call    net_ep_test_rid
    lea     rdi, [st_a]
    xor     esi, esi
    xor     edx, edx
    xor     ecx, ecx
    xor     r8d, r8d
    call    st_reset
    lea     rdi, [st_b]
    xor     esi, esi
    xor     edx, edx
    xor     ecx, ecx
    xor     r8d, r8d
    call    st_reset
    mov     edi, 100
    call    queue_msgs
    test    eax, eax
    jnz     .end
    mov     edi, 100
    mov     esi, 100
    mov     edx, 50
    call    run_until
    test    eax, eax
    jnz     .end
    xor     r12d, r12d
.end:
    call    teardown
    mov     eax, r12d
    pop     r13
    pop     r12
    pop     rbx
    ret

; test_net_timeout() -> eax 0 on pass. Connected and idle, keepalives hold the connection through 100 loops; then
; the clock jumps 9.9 s (still connected), then past 10 s with no traffic: both ends report NE_TIMEOUT for
; their connection and the connection is gone.
test_net_timeout:
    push    rbx
    push    r12
    push    r13
    mov     r12d, 1
    xor     edi, edi
    call    pair_up
    test    eax, eax
    jnz     .end
    mov     ebx, 100
.idle:
    call    step
    dec     ebx
    jnz     .idle
    call    poll_both                   ; take the datagrams still in flight: from here on the line is silent
    cmp     dword [t_a_tmo], 0
    jne     .end
    cmp     dword [t_b_tmo], 0
    jne     .end
    mov     rax, 9900000000
    add     [t_clock], rax
    call    poll_both
    cmp     dword [t_a_tmo], 0
    jne     .end                        ; 9.9 s of silence is not a timeout yet
    cmp     dword [t_b_tmo], 0
    jne     .end
    mov     rax, 200000000
    add     [t_clock], rax
    call    poll_both
    cmp     dword [t_a_tmo], 2          ; slot 1 on the host
    jne     .end
    cmp     dword [t_b_tmo], 1          ; slot 0 on the guest
    jne     .end
    mov     rdi, [t_a]
    mov     esi, 1
    mov     edx, MT_BLOCK
    lea     rcx, [t_buf]
    mov     r8d, 1
    mov     r9d, 1
    call    net_ep_send
    test    eax, eax
    jnz     .end                        ; the connection is gone: nothing can be queued
    xor     r12d, r12d
.end:
    call    teardown
    mov     eax, r12d
    pop     r13
    pop     r12
    pop     rbx
    ret

; raw_open() -> eax fd of a non-blocking UDP socket bound to an ephemeral port (t_sa holds its sockaddr), or -errno
raw_open:
    push    rbx
    sub     rsp, 32
    mov     eax, NSYS_SOCKET
    mov     edi, 2
    mov     esi, 2 | 0x800
    xor     edx, edx
    syscall
    test    rax, rax
    js      .out
    mov     ebx, eax
    mov     qword [rsp], 2              ; AF_INET, port 0, address 0.0.0.0
    mov     qword [rsp + 8], 0
    mov     eax, NSYS_BIND
    mov     edi, ebx
    lea     rsi, [rsp]
    mov     edx, 16
    syscall
    test    rax, rax
    js      .out
    mov     qword [rsp + 16], 0
    mov     dword [rsp + 24], 16
    mov     qword [t_sa], 0
    mov     qword [t_sa + 8], 0
    mov     eax, NSYS_GETSOCKNAME
    mov     edi, ebx
    lea     rsi, [t_sa]
    lea     rdx, [rsp + 24]
    syscall
    test    rax, rax
    js      .out
    mov     eax, ebx
.out:
    add     rsp, 32
    pop     rbx
    ret

; raw_send(edi fd, rsi buf, edx len, ecx port_be): a datagram to 127.0.0.1:port
raw_send:
    sub     rsp, 24
    mov     word [rsp], 2
    mov     [rsp + 2], cx
    mov     dword [rsp + 4], 0x0100007F
    mov     qword [rsp + 8], 0
    mov     r8, rsp
    mov     r9d, 16
    xor     r10d, r10d
    mov     eax, NSYS_SENDTO
    syscall
    add     rsp, 24
    ret

; raw_recv(edi fd, rsi buf, edx cap, rcx sockaddr out (16 bytes)) -> rax length or -errno (-EAGAIN: nothing yet)
raw_recv:
    sub     rsp, 24
    mov     dword [rsp], 16
    mov     r8, rcx
    mov     r9, rsp
    xor     r10d, r10d
    mov     eax, NSYS_RECVFROM
    syscall
    add     rsp, 24
    ret

; raw_close(edi fd)
raw_close:
    mov     eax, SYS_CLOSE
    syscall
    ret

; test_net_handshake_deny() -> eax 0 on pass.
;   a. A CONNECT with a version byte of 2 (raw socket -> host) is answered with a DENY_VERSION datagram and no event.
;   b. A joiner that gets a DENY_VERSION datagram whose own version byte is 2 reports NJE_DENY_VERSION.
;   c. A host that denies a CONNECT_REQ with DENY_FULL / DENY_NAME / DENY_CLOSED gives the joiner
;      NJE_DENY_FULL / NJE_DENY_NAME / NJE_DENY_CLOSED (join state NJ_FAILED).
;   d. dedupe_round: copies of one request from several addresses raise one event, ACCEPT / DENY are repeated.
;   e. addr_checks: net_parse_addr, net_format_addr, net_local_ip.
;   f. hostile_round (inside d): lying lengths and a blob run past its end deliver nothing and touch nothing.
test_net_handshake_deny:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12d, 1
    mov     r15d, -1                    ; the raw socket
    xor     edi, edi
    call    setup_eps
    test    eax, eax
    jnz     .end
    call    raw_open
    test    eax, eax
    js      .end
    mov     r15d, eax
    mov     [t_r1fd], eax
    movzx   ecx, word [t_sa + 2]
    mov     [t_r1port], ecx
    movzx   r13d, word [t_sa + 2]       ; the raw socket's port (network order)
    ; ---- a. a CONNECT of protocol version 2 to the host
    lea     rdi, [t_raw]
    mov     word [rdi], NET_MAGIC
    mov     byte [rdi + 2], 2
    mov     byte [rdi + 3], PK_CONNECT
    mov     qword [rdi + 4], 0          ; token, then seq and the first half of ack
    mov     qword [rdi + 12], 0
    mov     dword [rdi + 16], 0xCAFEBABE
    mov     dword [rdi + 20], 'Eve'
    mov     dword [rdi + 24], 0
    mov     dword [rdi + 28], 0
    mov     dword [rdi + 32], 0
    mov     dword [rdi + 36], 0
    mov     edi, r15d
    lea     rsi, [t_raw]
    mov     edx, 37
    mov     ecx, [t_pa]
    rol     cx, 8
    movzx   ecx, cx
    call    raw_send
    mov     rdi, [t_a]
    lea     rsi, [deliver_a]
    call    net_ep_poll
    mov     rdi, [t_a]
    lea     rsi, [t_ev]
    call    net_ep_next_event
    test    eax, eax
    jnz     .end                        ; no CONNECT_REQ for a mismatched version
    mov     edi, r15d
    lea     rsi, [t_raw + 64]
    mov     edx, 64
    sub     rsp, 16
    mov     rcx, rsp
    call    raw_recv
    add     rsp, 16
    cmp     rax, 21
    jne     .end
    cmp     word [t_raw + 64], NET_MAGIC
    jne     .end
    cmp     byte [t_raw + 64 + 2], NET_VERSION
    jne     .end
    cmp     byte [t_raw + 64 + 3], PK_DENY
    jne     .end
    cmp     dword [t_raw + 64 + 4], 0
    jne     .end
    cmp     dword [t_raw + 64 + 16], 0xCAFEBABE
    jne     .end
    cmp     byte [t_raw + 64 + 20], DENY_VERSION
    jne     .end
    ; ---- b. B joins the raw socket, which answers with a DENY whose version byte is 2
    mov     dword [t_addr], 0x0100007F
    mov     [t_addr + 4], r13w
    mov     rdi, [t_b]
    lea     rsi, [t_addr]
    xor     edx, edx
    lea     rcx, [s_bob]
    xor     r8d, r8d
    call    net_ep_join
    mov     edi, r15d
    lea     rsi, [t_raw + 64]
    mov     edx, 64
    sub     rsp, 16
    mov     rcx, rsp
    call    raw_recv
    mov     r14, rax                    ; B's CONNECT
    movzx   r13d, word [rsp + 2]        ; B's port, to answer it (network order)
    add     rsp, 16
    cmp     r14, 37
    jne     .end
    cmp     byte [t_raw + 64 + 3], PK_CONNECT
    jne     .end
    cmp     dword [t_raw + 64 + 20], 'Bob'
    jne     .end
    lea     rdi, [t_raw]
    mov     word [rdi], NET_MAGIC
    mov     byte [rdi + 2], 2           ; the host speaks another version
    mov     byte [rdi + 3], PK_DENY
    mov     qword [rdi + 4], 0
    mov     qword [rdi + 12], 0
    mov     eax, [t_raw + 64 + 16]
    mov     [rdi + 16], eax             ; echo the joiner's nonce
    mov     byte [rdi + 20], DENY_VERSION
    mov     edi, r15d
    lea     rsi, [t_raw]
    mov     edx, 21
    mov     ecx, r13d
    call    raw_send
    mov     rdi, [t_b]
    lea     rsi, [deliver_b]
    call    net_ep_poll
    mov     rdi, [t_b]
    call    net_ep_join_state
    cmp     eax, NJ_FAILED
    jne     .end
    mov     rdi, [t_b]
    call    net_ep_join_err
    cmp     eax, NJE_DENY_VERSION
    jne     .end
    ; ---- c. the host denies the CONNECT_REQ itself
    mov     dword [t_mode], 2
    mov     dword [t_reason], DENY_FULL
    mov     r13d, NJE_DENY_FULL
    call    deny_round
    test    eax, eax
    jnz     .end
    mov     dword [t_reason], DENY_NAME
    mov     r13d, NJE_DENY_NAME
    call    deny_round
    test    eax, eax
    jnz     .end
    mov     dword [t_reason], DENY_CLOSED
    mov     r13d, NJE_DENY_CLOSED
    call    deny_round
    test    eax, eax
    jnz     .end
    ; ---- d. a request that arrives by several candidate addresses is one request
    call    dedupe_round
    test    eax, eax
    jnz     .end
    ; ---- e. the join target parsing
    call    addr_checks
    test    eax, eax
    jnz     .end
    xor     r12d, r12d
.end:
    test    r15d, r15d
    js      .noraw
    mov     edi, r15d
    call    raw_close
.noraw:
    call    teardown
    mov     eax, r12d
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; deny_round(r13d expected NJE_*) -> eax 0: B joins A afresh; within 200 loops its join fails with exactly that error
deny_round:
    push    rbx
    mov     rdi, [t_b]
    lea     rsi, [t_addr]
    mov     eax, [t_pa]
    rol     ax, 8
    mov     [t_addr + 4], ax
    xor     edx, edx
    lea     rcx, [s_bob]
    xor     r8d, r8d
    call    net_ep_join
    mov     ebx, 200
.loop:
    call    step
    mov     rdi, [t_b]
    call    net_ep_join_state
    cmp     eax, NJ_FAILED
    je      .failed
    dec     ebx
    jnz     .loop
    mov     eax, 1
    jmp     .out
.failed:
    mov     rdi, [t_b]
    call    net_ep_join_err
    cmp     eax, r13d
    setne   al
    movzx   eax, al
.out:
    pop     rbx
    ret

; raw_wait(edi fd, rsi buf, edx cap, rcx sockaddr out) -> rax length or -errno: raw_recv, retried (sched_yield) while
; the datagram has not arrived yet
raw_wait:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 8
    mov     ebx, edi
    mov     r12, rsi
    mov     r13d, edx
    mov     r14, rcx
    mov     dword [rsp], 200
.try:
    mov     edi, ebx
    mov     rsi, r12
    mov     edx, r13d
    mov     rcx, r14
    call    raw_recv
    cmp     rax, -11                    ; EAGAIN
    jne     .out
    mov     eax, 24                     ; sched_yield
    syscall
    dec     dword [rsp]
    jnz     .try
    mov     rax, -11
.out:
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; build_connect(rdi buf, esi nonce, edx name4): a 37-byte CONNECT of protocol version NET_VERSION
build_connect:
    mov     word [rdi], NET_MAGIC
    mov     byte [rdi + 2], NET_VERSION
    mov     byte [rdi + 3], PK_CONNECT
    mov     qword [rdi + 4], 0
    mov     qword [rdi + 12], 0
    mov     [rdi + 16], esi
    mov     [rdi + 20], edx
    mov     dword [rdi + 24], 0
    mov     dword [rdi + 28], 0
    mov     dword [rdi + 32], 0
    mov     byte [rdi + 36], 0
    ret

; send_to_a(edi fd): t_raw (a CONNECT of 37 bytes) from that raw socket to the host A
send_to_a:
    sub     rsp, 8
    lea     rsi, [t_raw]
    mov     edx, 37
    mov     ecx, [t_pa]
    rol     cx, 8
    movzx   ecx, cx
    call    raw_send
    add     rsp, 8
    ret

; poll_a(): the host takes what arrived
poll_a:
    sub     rsp, 8
    mov     rdi, [t_a]
    lea     rsi, [deliver_a]
    call    net_ep_poll
    add     rsp, 8
    ret

; chk_accept(edi record) -> eax 0 when t_raw + 64 holds an ACCEPT of nonce 0x11223344 for slot 1 with a token:
; the token is recorded (edi 1) or must equal the recorded one (edi 0)
chk_accept:
    cmp     word [t_raw + 64], NET_MAGIC
    jne     .bad
    cmp     byte [t_raw + 64 + 2], NET_VERSION
    jne     .bad
    cmp     byte [t_raw + 64 + 3], PK_ACCEPT
    jne     .bad
    mov     eax, [t_raw + 64 + 4]
    test    eax, eax
    jz      .bad
    test    edi, edi
    jz      .same
    mov     [t_tok], eax
    jmp     .tail
.same:
    cmp     eax, [t_tok]
    jne     .bad
.tail:
    cmp     dword [t_raw + 64 + 16], 0x11223344
    jne     .bad
    cmp     byte [t_raw + 64 + 20], 1
    jne     .bad
    cmp     byte [t_raw + 64 + 21], NET_MAX_PEERS
    jne     .bad
    xor     eax, eax
    ret
.bad:
    mov     eax, 1
    ret

; chk_deny(edi nonce, esi reason) -> eax 0 when t_raw + 64 holds that DENY
chk_deny:
    cmp     word [t_raw + 64], NET_MAGIC
    jne     .bad
    cmp     byte [t_raw + 64 + 2], NET_VERSION
    jne     .bad
    cmp     byte [t_raw + 64 + 3], PK_DENY
    jne     .bad
    cmp     dword [t_raw + 64 + 4], 0
    jne     .bad
    cmp     [t_raw + 64 + 16], edi
    jne     .bad
    movzx   eax, byte [t_raw + 64 + 20]
    cmp     eax, esi
    jne     .bad
    xor     eax, eax
    ret
.bad:
    mov     eax, 1
    ret

; dedupe_round() -> eax 0 on pass. A joiner sends its CONNECT to several candidate addresses, all with one nonce:
;   - the same CONNECT from two raw sockets (R1 first) raises ONE NE_CONNECT_REQ, from R1;
;   - after net_ep_accept, R1 gets the ACCEPT {nonce, slot 1, a token};
;   - a later copy from R2 raises no event and the same ACCEPT goes again, to the accepted address (R1);
;   - a request the host denies gets its DENY, and a repeated copy gets the same DENY again, with no event.
dedupe_round:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12d, 1                     ; 1 = failed
    mov     dword [t_r2fd], -1
    call    raw_open
    test    eax, eax
    js      .out
    mov     [t_r2fd], eax
    lea     rdi, [t_raw]
    mov     esi, 0x11223344
    mov     edx, 'Dan'
    call    build_connect
    mov     edi, [t_r1fd]
    call    send_to_a
    mov     edi, [t_r2fd]
    call    send_to_a
    call    poll_a
    mov     rdi, [t_a]
    lea     rsi, [t_ev]
    call    net_ep_next_event
    test    eax, eax
    jz      .out
    cmp     byte [t_ev + NETEVENT.kind], NE_CONNECT_REQ
    jne     .out
    cmp     dword [t_ev + NETEVENT.nonce], 0x11223344
    jne     .out
    movzx   eax, word [t_ev + NETEVENT.addr + NADDR.port]
    cmp     eax, [t_r1port]
    jne     .out
    mov     rdi, [t_a]
    lea     rsi, [t_ev2]
    call    net_ep_next_event
    test    eax, eax
    jnz     .out                        ; the second copy is the same request: no second event
    mov     rdi, [t_a]
    mov     esi, 1
    lea     rdx, [t_ev]
    call    net_ep_accept
    mov     edi, [t_r1fd]
    lea     rsi, [t_raw + 64]
    mov     edx, 64
    lea     rcx, [t_sa]
    call    raw_wait
    cmp     rax, 22
    jne     .out
    mov     edi, 1
    call    chk_accept
    test    eax, eax
    jnz     .out
    mov     edi, [t_r2fd]               ; a late copy
    call    send_to_a
    call    poll_a
    mov     rdi, [t_a]
    lea     rsi, [t_ev2]
    call    net_ep_next_event
    test    eax, eax
    jnz     .out
    mov     edi, [t_r1fd]
    lea     rsi, [t_raw + 64]
    mov     edx, 64
    lea     rcx, [t_sa]
    call    raw_wait
    cmp     rax, 22
    jne     .out
    xor     edi, edi
    call    chk_accept
    test    eax, eax
    jnz     .out
    lea     rdi, [t_raw]                ; another request, which the host denies
    mov     esi, 0x55667788
    mov     edx, 'Ed'
    call    build_connect
    mov     edi, [t_r1fd]
    call    send_to_a
    call    poll_a
    mov     rdi, [t_a]
    lea     rsi, [t_ev]
    call    net_ep_next_event
    test    eax, eax
    jz      .out
    cmp     dword [t_ev + NETEVENT.nonce], 0x55667788
    jne     .out
    mov     rdi, [t_a]
    lea     rsi, [t_ev]
    mov     edx, DENY_NAME
    call    net_ep_deny
    mov     edi, [t_r1fd]
    lea     rsi, [t_raw + 64]
    mov     edx, 64
    lea     rcx, [t_sa]
    call    raw_wait
    cmp     rax, 21
    jne     .out
    mov     edi, 0x55667788
    mov     esi, DENY_NAME
    call    chk_deny
    test    eax, eax
    jnz     .out
    mov     edi, [t_r1fd]               ; the same CONNECT again
    call    send_to_a
    call    poll_a
    mov     rdi, [t_a]
    lea     rsi, [t_ev2]
    call    net_ep_next_event
    test    eax, eax
    jnz     .out
    mov     edi, [t_r1fd]
    lea     rsi, [t_raw + 64]
    mov     edx, 64
    lea     rcx, [t_sa]
    call    raw_wait
    cmp     rax, 21
    jne     .out
    mov     edi, 0x55667788
    mov     esi, DENY_NAME
    call    chk_deny
    test    eax, eax
    jnz     .out
    call    hostile_round
    test    eax, eax
    jnz     .out
    xor     r12d, r12d
.out:
    mov     edi, [t_r2fd]
    test    edi, edi
    js      .done
    call    raw_close
.done:
    mov     eax, r12d
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; addr_checks() -> eax 0 on pass: net_parse_addr takes a.b.c.d and a.b.c.d:port (network order result, the default
; port when none is given) and refuses everything else; net_format_addr prints one back; net_local_ip towards
; 127.0.0.1 is 127.0.0.1
addr_checks:
    push    rbx
    push    r12
    push    r13
    mov     r12d, 1
    lea     rdi, [a_s1]
    lea     rsi, [t_sa]
    mov     edx, 27615
    call    net_parse_addr
    cmp     eax, 1
    jne     .out
    cmp     dword [t_sa + NADDR.ip], 0x04030201
    jne     .out
    cmp     word [t_sa + NADDR.port], 0xDF6B        ; 27615 = 0x6BDF, big endian in memory
    jne     .out
    lea     rdi, [a_s2]
    lea     rsi, [t_sa]
    xor     edx, edx
    call    net_parse_addr
    cmp     eax, 1
    jne     .out
    cmp     dword [t_sa + NADDR.ip], 0x281E140A
    jne     .out
    cmp     word [t_sa + NADDR.port], 0x5000        ; 80
    jne     .out
    lea     rdi, [a_s3]
    lea     rsi, [t_sa]
    xor     edx, edx
    call    net_parse_addr
    cmp     eax, 1
    jne     .out
    cmp     dword [t_sa + NADDR.ip], 0xFFFFFFFF
    jne     .out
    cmp     word [t_sa + NADDR.port], 0xFFFF
    jne     .out
    lea     rbx, [bad_addrs]
.bad:
    mov     rdi, [rbx]
    test    rdi, rdi
    jz      .fmt
    lea     rsi, [t_sa]
    mov     edx, 27615
    call    net_parse_addr
    test    eax, eax
    jnz     .out                                    ; it took something it must refuse
    add     rbx, 8
    jmp     .bad
.fmt:
    lea     rdi, [a_s4]
    lea     rsi, [t_sa]
    xor     edx, edx
    call    net_parse_addr
    cmp     eax, 1
    jne     .out
    lea     rdi, [t_sa]
    lea     rsi, [t_raw + 64]
    call    net_format_addr
    lea     rcx, [t_raw + 64]
    sub     rax, rcx
    cmp     rax, 18
    jne     .out
    mov     byte [t_raw + 64 + 18], 0
    lea     rsi, [t_raw + 64]
    lea     rdi, [a_s4]
    mov     ecx, 19
    repe    cmpsb
    jne     .out
    lea     rdi, [a_s5]
    lea     rsi, [t_sa]
    xor     edx, edx
    call    net_parse_addr
    cmp     eax, 1
    jne     .out
    lea     rdi, [t_sa]
    call    net_local_ip
    cmp     eax, 0x0100007F
    jne     .out
    xor     r12d, r12d
.out:
    mov     eax, r12d
    pop     r13
    pop     r12
    pop     rbx
    ret

; h_begin(): the 16-byte DATA header of the first raw socket's next packet in t_pkt (its token, ack 0)
h_begin:
    lea     rdi, [t_pkt]
    mov     word [rdi], NET_MAGIC
    mov     byte [rdi + 2], NET_VERSION
    mov     byte [rdi + 3], PK_DATA
    mov     eax, [t_tok]
    mov     [rdi + 4], eax
    inc     dword [t_seq]
    mov     eax, [t_seq]
    mov     [rdi + 8], ax
    mov     word [rdi + 10], 0
    mov     dword [rdi + 12], 0
    ret

; h_send(edi len): t_pkt from the first raw socket to the host A
h_send:
    sub     rsp, 8
    mov     edx, edi
    mov     edi, [t_r1fd]
    lea     rsi, [t_pkt]
    mov     ecx, [t_pa]
    rol     cx, 8
    movzx   ecx, cx
    call    raw_send
    add     rsp, 8
    ret

; hostile_round() -> eax 0 on pass. The first raw socket is an accepted guest (slot 1, token t_tok). Hostile DATA
; packets from it must deliver nothing and change nothing:
;   - a message that claims 500 payload bytes in a datagram that ends after its header;
;   - a message whose length is NET_MSG_MAX + 1 (with the bytes to back it);
;   - 241 blob parts that claim parts = 65535 and total = 100: copied at their offsets they would run over the
;     end of the blob buffer, and part 240 carries a live connection header (state 1) for exactly the bytes where
;     the next slot's state lies; slot 2 must stay free.
; A good unreliable message sent in between is delivered, so nothing was merely lost.
hostile_round:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12d, 1
    lea     rdi, [st_a]
    xor     esi, esi
    xor     edx, edx
    xor     ecx, ecx
    xor     r8d, r8d
    call    st_reset
    mov     dword [t_seq], 0
    call    h_begin
    mov     byte [t_pkt + 16], MT_BLOCK
    mov     byte [t_pkt + 17], 0
    mov     word [t_pkt + 18], 500
    mov     edi, 20
    call    h_send
    call    h_begin
    mov     byte [t_pkt + 16], MT_BLOCK
    mov     byte [t_pkt + 17], 0
    mov     word [t_pkt + 18], NET_MSG_MAX + 1
    mov     edi, 16 + 4 + NET_MSG_MAX + 1
    call    h_send
    call    h_begin
    mov     byte [t_pkt + 16], MT_PSTATE
    mov     byte [t_pkt + 17], 0
    mov     word [t_pkt + 18], 400
    mov     dword [t_pkt + 20], 1                   ; its number
    lea     rdi, [t_pkt + 24]
    mov     esi, 1
    mov     edx, 396
    call    pat_fill
    mov     edi, 16 + 4 + 400
    call    h_send
    mov     rdi, [t_a]
    mov     esi, 1
    mov     edx, 7000
    call    net_ep_test_rid
    xor     ebx, ebx
.part:
    call    h_begin
    mov     byte [t_pkt + 16], MT_BLOB_PART
    mov     byte [t_pkt + 17], 1
    mov     word [t_pkt + 18], 12 + 1088
    lea     eax, [rbx + 7000]
    mov     [t_pkt + 20], ax
    mov     byte [t_pkt + 22], MT_COL_DATA
    mov     byte [t_pkt + 23], 0
    mov     [t_pkt + 24], bx
    mov     word [t_pkt + 26], 65535
    mov     word [t_pkt + 28], 0
    mov     dword [t_pkt + 30], 100
    xor     eax, eax
    cmp     ebx, 240
    jne     .state
    mov     eax, 1
.state:
    mov     [t_pkt + 34 + 1024], eax
    mov     edi, 34 + 1088
    call    h_send
    test    bl, 15
    jnz     .nopoll
    call    poll_a
.nopoll:
    inc     ebx
    cmp     ebx, 241
    jb      .part
    call    poll_a
    cmp     dword [st_a + ST_N], 0
    jne     .out
    cmp     dword [st_a + ST_BAD], 0
    jne     .out
    cmp     dword [st_a + ST_UN], 1
    jne     .out
    mov     rdi, [t_a]
    mov     esi, 2
    call    net_ep_room
    test    eax, eax
    jnz     .out
    xor     r12d, r12d
.out:
    mov     eax, r12d
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- a network with a delay: two sockets in the middle -------------------------------------------------
; B joins fw_addr (the socket FB). The test forwards what B sends to A, from the socket FA (so A sees "B" as FA's
; address), and what A sends to FA to B, from FB (B sees "the host" as FB's address, which is where it joined).
; Every datagram waits fw_delay ms of the injected clock in a ring before it is forwarded, in both directions.

; fw_ms() -> eax the injected clock in ms
fw_ms:
    mov     rax, [t_clock]
    xor     edx, edx
    mov     ecx, 1000000
    div     rcx
    ret

; fw_open() -> eax 0 when the ring and both sockets exist
fw_open:
    push    rbx
    mov     dword [fw_head], 0
    mov     dword [fw_tail], 0
    mov     dword [fw_bport], 0
    mov     eax, NSYS_MMAP
    xor     edi, edi
    mov     esi, FW_ENTRIES * FW_ESIZE
    mov     edx, 3
    mov     r10d, 0x22
    mov     r8, -1
    xor     r9d, r9d
    syscall
    cmp     rax, -4096
    ja      .fail
    mov     [fw_ring], rax
    call    raw_open
    test    eax, eax
    js      .fail
    mov     [fw_fa], eax
    call    raw_open
    test    eax, eax
    js      .fail
    mov     [fw_fb], eax
    mov     dword [fw_addr], 0x0100007F
    movzx   eax, word [t_sa + 2]            ; raw_open left the port of the socket it made last in t_sa
    mov     [fw_addr + 4], ax
    mov     word [fw_addr + 6], 0
    xor     eax, eax
    pop     rbx
    ret
.fail:
    mov     eax, 1
    pop     rbx
    ret

; fw_close(): the sockets and the ring go (whatever fw_open got that far); safe to call twice
fw_close:
    push    rbx
    mov     edi, [fw_fa]
    test    edi, edi
    js      .b
    call    raw_close
    mov     dword [fw_fa], -1
.b:
    mov     edi, [fw_fb]
    test    edi, edi
    js      .ring
    call    raw_close
    mov     dword [fw_fb], -1
.ring:
    mov     rdi, [fw_ring]
    test    rdi, rdi
    jz      .out
    mov     esi, FW_ENTRIES * FW_ESIZE
    mov     eax, NSYS_MUNMAP
    syscall
    mov     qword [fw_ring], 0
.out:
    pop     rbx
    ret

; fw_collect(): every datagram waiting on FA (A sent it to "B") and on FB (B sent it to "the host") enters the delay
; line, to leave fw_delay ms from now for the other side. B's real port is learned from FB's datagrams.
fw_collect:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 32                         ; [rsp]: the sender's sockaddr
    call    fw_ms
    mov     r12d, eax
    xor     r13d, r13d                      ; 0: FA (A's datagrams, for B), 1: FB (B's datagrams, for A)
.sock:
    mov     ebx, [fw_fa]
    test    r13d, r13d
    jz      .recv
    mov     ebx, [fw_fb]
.recv:
    mov     eax, [fw_tail]
    sub     eax, [fw_head]
    cmp     eax, FW_ENTRIES
    jae     .next_sock                      ; the line is full: the rest stays in the socket
    mov     eax, [fw_tail]
    and     eax, FW_ENTRIES - 1
    imul    eax, eax, FW_ESIZE
    mov     r14, [fw_ring]
    add     r14, rax
    mov     edi, ebx
    lea     rsi, [r14 + 16]
    mov     edx, 1232
    mov     rcx, rsp
    call    raw_recv
    test    rax, rax
    js      .next_sock
    mov     [r14 + 8], eax
    mov     eax, r12d
    add     eax, [fw_delay]
    mov     [r14], eax
    mov     eax, 1
    sub     eax, r13d
    mov     [r14 + 4], eax                  ; FA's datagrams go to B (1), FB's to A (0)
    test    r13d, r13d
    jz      .queued
    movzx   eax, word [rsp + 2]
    mov     [fw_bport], eax
.queued:
    inc     dword [fw_tail]
    jmp     .recv
.next_sock:
    inc     r13d
    cmp     r13d, 2
    jb      .sock
    add     rsp, 32
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; fw_release(): every queued datagram whose time has come is sent on to its side
fw_release:
    push    rbx
    push    r12
    push    r13
    call    fw_ms
    mov     r12d, eax
.loop:
    mov     eax, [fw_head]
    cmp     eax, [fw_tail]
    je      .out
    and     eax, FW_ENTRIES - 1
    imul    eax, eax, FW_ESIZE
    mov     rbx, [fw_ring]
    add     rbx, rax
    mov     eax, r12d
    sub     eax, [rbx]
    js      .out                            ; not yet
    cmp     dword [rbx + 4], 0
    jne     .to_b
    mov     edi, [fw_fa]                    ; to A, from FA
    lea     rsi, [rbx + 16]
    mov     edx, [rbx + 8]
    mov     ecx, [t_pa]
    rol     cx, 8
    movzx   ecx, cx
    call    raw_send
    jmp     .next
.to_b:
    mov     ecx, [fw_bport]
    test    ecx, ecx
    jz      .next                           ; B has not spoken yet: nowhere to send it
    mov     edi, [fw_fb]                    ; to B, from FB
    lea     rsi, [rbx + 16]
    mov     edx, [rbx + 8]
    call    raw_send
.next:
    inc     dword [fw_head]
    jmp     .loop
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; step_fw(): step() with the delay line in the middle: the clock +16 ms, what is due leaves the line, both ends
; poll, drain and flush, and what they sent enters the line
step_fw:
    sub     rsp, 8
    add     qword [t_clock], STEP_NS
    call    fw_release
    call    poll_both
    mov     rdi, [t_a]
    call    net_ep_flush
    mov     rdi, [t_b]
    call    net_ep_flush
    call    fw_collect
    add     rsp, 8
    ret

; test_net_long_rtt() -> eax 0 on pass.
;   1. A 300 ms one-way delay in both directions (a 0.6 s round trip) and 5 % loss, with a 16 ms loop: B joins through
;      the delay line, then three 200000-byte blobs A -> B (552 parts) must all arrive intact within LONG_LOOPS loops
;      (219 are needed; with a 256-entry ring that is kept from overwriting packets in flight it takes 352, and with
;      the original ring of 256 entries, which overwrote them, the acks came back after their slots had been reused,
;      no ack ever matched and the transfer stalled after the first blob), and nothing is delivered twice in the 50
;      loops after.
;   2. ring_full_round: the sender stops at the ring capacity and goes on after the age limit.
test_net_long_rtt:
    push    rbx
    push    r12
    push    r13
    mov     r12d, 1
    mov     dword [fw_fa], -1
    mov     dword [fw_fb], -1
    mov     qword [fw_ring], 0
    mov     edi, 5
    call    setup_eps
    test    eax, eax
    jnz     .end
    call    fw_open
    test    eax, eax
    jnz     .end
    mov     dword [fw_delay], 300
    mov     dword [t_mode], 1
    mov     rdi, [t_b]
    lea     rsi, [fw_addr]
    xor     edx, edx
    lea     rcx, [s_bob]
    xor     r8d, r8d
    call    net_ep_join
    mov     ebx, 600
.join:
    call    step_fw
    mov     rdi, [t_b]
    call    net_ep_join_state
    cmp     eax, NJ_CONNECTED
    jne     .jmore
    mov     rdi, [t_a]
    mov     esi, 1
    call    net_ep_room
    test    eax, eax
    jnz     .joined
.jmore:
    dec     ebx
    jnz     .join
    jmp     .end
.joined:
    lea     rdi, [st_b]
    mov     esi, 1
    mov     edx, 200000
    mov     ecx, MT_COL_DATA
    mov     r8d, 255
    call    st_reset
    lea     rdi, [st_a]
    xor     esi, esi
    xor     edx, edx
    xor     ecx, ecx
    xor     r8d, r8d
    call    st_reset
    lea     rdi, [t_big]
    mov     esi, 255
    mov     edx, 200000
    call    pat_fill
    mov     r13d, 3
.queue:
    mov     rdi, [t_a]
    mov     esi, 1
    mov     edx, MT_COL_DATA
    lea     rcx, [t_big]
    mov     r8d, 200000
    call    net_ep_send_big
    test    eax, eax
    jz      .end
    dec     r13d
    jnz     .queue
    mov     ebx, LONG_LOOPS
.xfer:
    call    step_fw
    cmp     dword [st_b + ST_N], 3
    jae     .arrived
    dec     ebx
    jnz     .xfer
    jmp     .end
.arrived:
    mov     ebx, 50
.after:
    call    step_fw
    dec     ebx
    jnz     .after
    cmp     dword [st_b + ST_N], 3
    jne     .end
    cmp     dword [st_b + ST_BAD], 0
    jne     .end
    cmp     dword [st_a + ST_BAD], 0
    jne     .end
    call    fw_close
    call    teardown
    call    ring_full_round
    mov     r12d, eax
.end:
    call    fw_close
    call    teardown
    mov     eax, r12d
    pop     r13
    pop     r12
    pop     rbx
    ret

; ring_full_round() -> eax 0 on pass. A and B are connected, B only polls (it never acknowledges anything), and the
; clock stands still. A queues 8 unreliable messages of 1100 bytes (one per packet) and flushes, 560 times: 4480
; packets wanted. Only RING_PKTS reach B: the 4097th would overwrite the first, which is in flight and not yet
; 2 s old, so the flush sends nothing more. Once the clock has moved 2.1 s the old packets may be overwritten and
; the next flush sends again.
ring_full_round:
    push    rbx
    push    r12
    push    r13
    mov     r12d, 1
    xor     edi, edi
    call    pair_up
    test    eax, eax
    jnz     .end
    lea     rdi, [st_b]
    mov     esi, 2
    xor     edx, edx
    xor     ecx, ecx
    xor     r8d, r8d
    call    st_reset
    lea     rdi, [t_buf]
    mov     esi, 9
    mov     edx, 1100
    call    pat_fill
    xor     ebx, ebx
.burst:
    call    burst8
    test    eax, eax
    jnz     .end
    inc     ebx
    cmp     ebx, 560
    jb      .burst
    cmp     dword [st_b + ST_N], RING_PKTS
    jne     .end
    mov     rax, 2100000000
    add     [t_clock], rax
    call    burst8
    test    eax, eax
    jnz     .end
    cmp     dword [st_b + ST_N], RING_PKTS
    jbe     .end
    xor     r12d, r12d
.end:
    call    teardown
    mov     eax, r12d
    pop     r13
    pop     r12
    pop     rbx
    ret

; burst8() -> eax 0: A queues 8 unreliable 1100-byte messages for slot 1 and flushes; B polls
burst8:
    push    rbx
    mov     ebx, 8
.queue:
    mov     rdi, [t_a]
    mov     esi, 1
    mov     edx, MT_SYS
    lea     rcx, [t_buf]
    mov     r8d, 1100
    xor     r9d, r9d
    call    net_ep_send
    test    eax, eax
    jz      .fail
    dec     ebx
    jnz     .queue
    mov     rdi, [t_a]
    call    net_ep_flush
    mov     rdi, [t_b]
    lea     rsi, [deliver_b]
    call    net_ep_poll
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    pop     rbx
    ret

; ---- the event queue -----------------------------------------------------------------------------------

; mk_sev(): t_sev = a synthetic NE_CONNECT_REQ from the first raw socket's address, with the next nonce
mk_sev:
    pxor    xmm0, xmm0
    movups  [t_sev], xmm0
    movups  [t_sev + 16], xmm0
    mov     dword [t_sev + 32], 0
    mov     byte [t_sev + NETEVENT.kind], NE_CONNECT_REQ
    mov     dword [t_sev + NETEVENT.addr + NADDR.ip], 0x0100007F
    mov     eax, [t_r1port]
    mov     [t_sev + NETEVENT.addr + NADDR.port], ax
    mov     eax, [t_nonce]
    inc     dword [t_nonce]
    mov     [t_sev + NETEVENT.nonce], eax
    ret

; send_bye(edi token): a DISCONNECT (reason DENY_CLOSED) of the first raw socket's guest to the host A
send_bye:
    sub     rsp, 8
    lea     rax, [t_pkt]
    mov     word [rax], NET_MAGIC
    mov     byte [rax + 2], NET_VERSION
    mov     byte [rax + 3], PK_DISCONNECT
    mov     [rax + 4], edi
    mov     qword [rax + 8], 0
    mov     byte [rax + 16], DENY_CLOSED
    mov     edi, [t_r1fd]
    lea     rsi, [t_pkt]
    mov     edx, 17
    mov     ecx, [t_pa]
    rol     cx, 8
    movzx   ecx, cx
    call    raw_send
    add     rsp, 8
    ret

; guest_in(edi slot) -> eax the token of the connection, 0 on failure: the first raw socket is accepted into that slot
; of A (a synthetic request, so no CONNECT datagram and no event are needed) and its ACCEPT is read
guest_in:
    push    rbx
    mov     ebx, edi
    call    mk_sev
    mov     rdi, [t_a]
    mov     esi, ebx
    lea     rdx, [t_sev]
    call    net_ep_accept
    mov     edi, [t_r1fd]
    lea     rsi, [t_raw + 64]
    mov     edx, 64
    lea     rcx, [t_sa]
    call    raw_wait
    xor     edx, edx
    cmp     rax, 22
    jne     .out
    mov     edx, [t_raw + 64 + 4]
.out:
    mov     eax, edx
    pop     rbx
    ret

; fill_goodbyes(edi count, esi first_slot, edx span) -> eax 0 ok: `count` times the first raw socket is accepted into slot
; first + i % span and says goodbye; every goodbye leaves one NE_DISCONNECTED in the queue and nobody takes them out
fill_goodbyes:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edx
    xor     ebx, ebx
.cycle:
    cmp     ebx, r12d
    jae     .ok
    mov     eax, ebx
    xor     edx, edx
    div     r14d
    lea     edi, [r13 + rdx]
    call    guest_in
    test    eax, eax
    jz      .fail
    mov     edi, eax
    call    send_bye
    call    poll_a
    inc     ebx
    jmp     .cycle
.ok:
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ev_reset(): clear what ev_drain counts
ev_reset:
    mov     dword [ec_req], 0
    mov     dword [ec_disc], 0
    mov     dword [ec_tmo], 0
    mov     dword [ec_other], 0
    mov     dword [ec_d1], 0
    mov     dword [ec_last_kind], 0
    mov     dword [ec_last_slot], 0
    mov     dword [ec_last_reason], 0
    ret

; ev_drain(): take every event of A out of the queue, counting the kinds and keeping the last one
ev_drain:
    push    rbx
.n:
    mov     rdi, [t_a]
    lea     rsi, [t_ev2]
    call    net_ep_next_event
    test    eax, eax
    jz      .out
    movzx   eax, byte [t_ev2 + NETEVENT.kind]
    movzx   ecx, byte [t_ev2 + NETEVENT.slot]
    movzx   edx, byte [t_ev2 + NETEVENT.reason]
    mov     [ec_last_kind], eax
    mov     [ec_last_slot], ecx
    mov     [ec_last_reason], edx
    cmp     eax, NE_CONNECT_REQ
    jne     .d
    inc     dword [ec_req]
    jmp     .n
.d:
    cmp     eax, NE_DISCONNECTED
    jne     .t
    inc     dword [ec_disc]
    cmp     ecx, 1
    jne     .n
    cmp     edx, DENY_CLOSED
    jne     .n
    inc     dword [ec_d1]
    jmp     .n
.t:
    cmp     eax, NE_TIMEOUT
    jne     .o
    inc     dword [ec_tmo]
    jmp     .n
.o:
    inc     dword [ec_other]
    jmp     .n
.out:
    pop     rbx
    ret

; test_net_event_queue_full() -> eax 0 on pass. The host's event queue holds 64 events and nothing takes them out:
;   1. A guest joins (slot 1). 70 CONNECTs from another socket then fill the queue only up to EVQ_CONNECTS (the rest
;      is refused, and not remembered: the same CONNECT asked again with room is a request); when the guest says
;      goodbye, its NE_DISCONNECTED gets through at once and the connection is gone.
;   2. 64 goodbyes fill the queue. A 65th finds no room: its connection stays, and is reported (as the newest event)
;      by the next poll after one place has been freed. Nothing is lost, nothing is reported twice.
;   3. A silent connection past the timeout, with the queue full, stays too and is reported as NE_TIMEOUT the same way.
test_net_event_queue_full:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12d, 1
    mov     dword [t_r1fd], -1
    mov     dword [t_r2fd], -1
    xor     edi, edi
    call    setup_eps
    test    eax, eax
    jnz     .end
    call    raw_open
    test    eax, eax
    js      .end
    mov     [t_r1fd], eax
    movzx   ecx, word [t_sa + 2]
    mov     [t_r1port], ecx
    call    raw_open
    test    eax, eax
    js      .end
    mov     [t_r2fd], eax
    mov     dword [t_nonce], 0x4000
    lea     rdi, [t_raw]                            ; the guest joins for real: CONNECT, event, accept into slot 1
    mov     esi, 0x1111
    mov     edx, 'Dan'
    call    build_connect
    mov     edi, [t_r1fd]
    call    send_to_a
    call    poll_a
    mov     rdi, [t_a]
    lea     rsi, [t_ev]
    call    net_ep_next_event
    test    eax, eax
    jz      .end
    cmp     byte [t_ev + NETEVENT.kind], NE_CONNECT_REQ
    jne     .end
    mov     rdi, [t_a]
    mov     esi, 1
    lea     rdx, [t_ev]
    call    net_ep_accept
    mov     edi, [t_r1fd]
    lea     rsi, [t_raw + 64]
    mov     edx, 64
    lea     rcx, [t_sa]
    call    raw_wait
    cmp     rax, 22
    jne     .end
    mov     r15d, [t_raw + 64 + 4]                  ; its token
    xor     ebx, ebx                                ; 1. the flood
.flood:
    lea     rdi, [t_raw]
    lea     esi, [rbx + 100]
    mov     edx, 'Fld'
    call    build_connect
    mov     edi, [t_r2fd]
    call    send_to_a
    inc     ebx
    cmp     ebx, 70
    jb      .flood
    call    poll_a
    mov     edi, r15d
    call    send_bye
    call    poll_a
    call    ev_reset
    call    ev_drain
    cmp     dword [ec_req], EVQ_CONNECTS
    jne     .end                                    ; the flood stopped at the reserve
    cmp     dword [ec_d1], 1
    jne     .end                                    ; the goodbye got through at once
    mov     rdi, [t_a]
    mov     esi, 1
    call    net_ep_room
    test    eax, eax
    jnz     .end                                    ; and the connection is gone
    lea     rdi, [t_raw]                            ; a refused CONNECT is not remembered
    mov     esi, 169
    mov     edx, 'Fld'
    call    build_connect
    mov     edi, [t_r2fd]
    call    send_to_a
    call    poll_a
    call    ev_reset
    call    ev_drain
    cmp     dword [ec_req], 1
    jne     .end
    mov     edi, 64                                 ; 2. 64 goodbyes: the queue is full
    mov     esi, 1
    mov     edx, 7
    call    fill_goodbyes
    test    eax, eax
    jnz     .end
    mov     edi, 2
    call    guest_in
    test    eax, eax
    jz      .end
    mov     edi, eax
    call    send_bye                                ; the 65th, from slot 2
    call    poll_a
    mov     rdi, [t_a]
    mov     esi, 2
    call    net_ep_room
    test    eax, eax
    jz      .end                                    ; no room for it: the connection waits
    mov     rdi, [t_a]
    lea     rsi, [t_ev2]
    call    net_ep_next_event                       ; one place frees up ...
    call    poll_a                                  ; ... and the next poll reports the waiting goodbye
    mov     rdi, [t_a]
    mov     esi, 2
    call    net_ep_room
    test    eax, eax
    jnz     .end
    call    ev_reset
    call    ev_drain
    cmp     dword [ec_disc], 64
    jne     .end
    cmp     dword [ec_last_kind], NE_DISCONNECTED
    jne     .end
    cmp     dword [ec_last_slot], 2
    jne     .end                                    ; the late goodbye is the newest event
    mov     edi, 1                                  ; 3. a connection that goes silent, with the queue full again
    call    guest_in
    test    eax, eax
    jz      .end
    mov     edi, 64
    mov     esi, 2
    mov     edx, 6
    call    fill_goodbyes
    test    eax, eax
    jnz     .end
    mov     rax, 10100000000
    add     [t_clock], rax
    call    poll_a
    mov     rdi, [t_a]
    mov     esi, 1
    call    net_ep_room
    test    eax, eax
    jz      .end                                    ; no room for its NE_TIMEOUT: it stays
    mov     rdi, [t_a]
    lea     rsi, [t_ev2]
    call    net_ep_next_event
    call    poll_a
    mov     rdi, [t_a]
    mov     esi, 1
    call    net_ep_room
    test    eax, eax
    jnz     .end
    call    ev_reset
    call    ev_drain
    cmp     dword [ec_tmo], 1
    jne     .end
    cmp     dword [ec_last_kind], NE_TIMEOUT
    jne     .end
    cmp     dword [ec_last_slot], 1
    jne     .end
    xor     r12d, r12d
.end:
    mov     edi, [t_r1fd]
    test    edi, edi
    js      .no1
    call    raw_close
.no1:
    mov     edi, [t_r2fd]
    test    edi, edi
    js      .no2
    call    raw_close
.no2:
    call    teardown
    mov     eax, r12d
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- a join's ACCEPT and the host's first message in one poll ------------------------------------------------

; greet(edi slot): A's first message to a guest it has just accepted, queued reliably (netsync does the same with
; WORLDINFO): message 0 of the pattern
greet:
    push    rbx
    push    r12
    push    r13
    mov     ebx, edi
    xor     edi, edi
    call    pat_len
    mov     r12d, eax
    lea     rdi, [t_buf]
    xor     esi, esi
    mov     edx, r12d
    call    pat_fill
    mov     rdi, [t_a]
    mov     esi, ebx
    mov     edx, MT_BLOCK
    lea     rcx, [t_buf]
    mov     r8d, r12d
    mov     r9d, 1
    call    net_ep_send
    pop     r13
    pop     r12
    pop     rbx
    ret

; accept_burst_round() -> eax 0 on pass. B joins A through the delay line with no delay: A's ACCEPT and its first message
; (queued at the accept, flushed in the same loop) reach B's socket together, so one poll of B finds both. The caller of
; the transport sets up its session when it fetches NE_ACCEPTED, and a message delivered before that is lost for good (it
; is acknowledged, so it is never sent again). So the callback must have been given nothing when the event is fetched
; (right after that poll), the next poll must deliver the message, once and intact, and A must hear the ack.
accept_burst_round:
    push    rbx
    push    r12
    push    r13
    mov     r12d, 1
    mov     dword [fw_fa], -1
    mov     dword [fw_fb], -1
    mov     qword [fw_ring], 0
    xor     edi, edi
    call    setup_eps
    test    eax, eax
    jnz     .end
    call    fw_open
    test    eax, eax
    jnz     .end
    mov     dword [fw_delay], 0
    mov     dword [t_mode], 1
    mov     dword [t_greet], 1
    lea     rdi, [st_b]
    xor     esi, esi
    xor     edx, edx
    xor     ecx, ecx
    xor     r8d, r8d
    call    st_reset
    mov     rdi, [t_b]
    lea     rsi, [fw_addr]
    xor     edx, edx
    lea     rcx, [s_bob]
    xor     r8d, r8d
    call    net_ep_join
    mov     ebx, 600
.join:
    call    step_fw
    cmp     dword [t_acc_seen], 0
    jne     .accepted
    dec     ebx
    jnz     .join
    jmp     .end
.accepted:
    cmp     dword [t_acc_n], 0
    jne     .end                        ; a message was delivered before the event could be fetched
    call    step_fw                     ; the next poll: the message that waited in the socket
    cmp     dword [st_b + ST_N], 1
    jne     .end
    mov     ebx, 40
.after:
    call    step_fw
    dec     ebx
    jnz     .after
    cmp     dword [st_b + ST_N], 1      ; still exactly one, and it was the right one
    jne     .end
    cmp     dword [st_b + ST_BAD], 0
    jne     .end
    cmp     dword [t_acc_seen], 1
    jne     .end
    mov     rdi, [t_b]
    call    net_ep_join_state
    cmp     eax, NJ_CONNECTED
    jne     .end
    mov     rdi, [t_a]
    mov     esi, 1
    call    net_ep_room
    cmp     eax, NET_RQ                 ; A's queue is empty again: B acknowledged the message
    jne     .end
    xor     r12d, r12d
.end:
    call    fw_close
    call    teardown
    mov     eax, r12d
    pop     r13
    pop     r12
    pop     rbx
    ret

; data_pkt() -> eax its length: t_pkt = a DATA packet of the first raw socket (token t_tok, its next packet number)
; with one reliable message, MT_BLOCK "hello" with rid 0
data_pkt:
    sub     rsp, 8
    call    h_begin
    mov     byte [t_pkt + 16], MT_BLOCK
    mov     byte [t_pkt + 17], 1
    mov     word [t_pkt + 18], 5
    mov     word [t_pkt + 20], 0
    mov     dword [t_pkt + 22], 'hell'
    mov     byte [t_pkt + 26], 'o'
    mov     eax, 27
    add     rsp, 8
    ret

; data_before_accept_round() -> eax 0 on pass. The host's side of the same ordering: a joiner's CONNECT and a DATA
; packet right behind it (with a token the host never issued) are in A's socket together. One poll of A raises the
; NE_CONNECT_REQ and delivers nothing: a connection exists only once net_ep_accept has made it. After the accept, the
; same packet with the token of the ACCEPT is delivered.
data_before_accept_round:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12d, 1
    mov     dword [t_r1fd], -1
    xor     edi, edi
    call    setup_eps
    test    eax, eax
    jnz     .end
    call    raw_open
    test    eax, eax
    js      .end
    mov     [t_r1fd], eax
    lea     rdi, [st_a]
    mov     esi, 2
    xor     edx, edx
    xor     ecx, ecx
    xor     r8d, r8d
    call    st_reset
    lea     rdi, [t_raw]
    mov     esi, 0x600D
    mov     edx, 'Gus'
    call    build_connect
    mov     edi, [t_r1fd]
    call    send_to_a
    mov     dword [t_tok], 0x13572468   ; a token nobody issued
    mov     dword [t_seq], 0
    call    data_pkt
    mov     edi, eax
    call    h_send
    call    poll_a
    mov     rdi, [t_a]
    lea     rsi, [t_ev]
    call    net_ep_next_event
    cmp     eax, 1
    jne     .end
    cmp     byte [t_ev + NETEVENT.kind], NE_CONNECT_REQ
    jne     .end
    cmp     dword [t_ev + NETEVENT.nonce], 0x600D
    jne     .end
    mov     rdi, [t_a]
    lea     rsi, [t_ev2]
    call    net_ep_next_event
    test    eax, eax
    jnz     .end                        ; the request, and nothing else
    cmp     dword [st_a + ST_N], 0
    jne     .end                        ; the DATA of a connection nobody accepted was not delivered
    mov     rdi, [t_a]
    mov     esi, 1
    lea     rdx, [t_ev]
    call    net_ep_accept
    mov     edi, [t_r1fd]
    lea     rsi, [t_raw + 64]
    mov     edx, 64
    lea     rcx, [t_sa]
    call    raw_wait
    cmp     rax, 22
    jne     .end
    mov     eax, [t_raw + 64 + 4]
    mov     [t_tok], eax                ; the token of the ACCEPT
    call    data_pkt
    mov     edi, eax
    call    h_send
    call    poll_a
    cmp     dword [st_a + ST_N], 1      ; now it is delivered
    jne     .end
    xor     r12d, r12d
.end:
    mov     edi, [t_r1fd]
    test    edi, edi
    js      .noclose
    call    raw_close
.noclose:
    call    teardown
    mov     eax, r12d
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; test_net_accept_then_data_one_poll() -> eax 0 on pass. A joiner is given NE_ACCEPTED before any message of the host,
; even when the ACCEPT and the host's first message are read by the same poll (accept_burst_round); the host delivers
; nothing for a connection it has not accepted (data_before_accept_round).
test_net_accept_then_data_one_poll:
    push    rbx
    call    accept_burst_round
    mov     ebx, eax
    test    eax, eax
    jnz     .out
    call    data_before_accept_round
    mov     ebx, eax
.out:
    mov     eax, ebx
    pop     rbx
    ret
