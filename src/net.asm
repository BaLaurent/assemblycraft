; net.asm - the UDP transport of 0.11 multiplayer: one socket, a reliable ordered channel and an
; unreliable channel multiplexed on it, hole punching and relaying through acrelay.
; Wire format and flows: docs/superpowers/specs/2026-11-09-assemblycraft-multiplayer-design.md
; (Wire format, Transport flows). Main thread only; raw syscalls, no libc, no DNS.
;
; An endpoint (NETEP) owns the socket, NET_MAX_PEERS connections (slot = index; a guest has only slot 0,
; the host), a queue of NETEVENTs and the join / rendezvous state machines. The game uses the global
; net_ep; tests allocate their own (net_ep_size bytes). A connection (CONN):
;   - reliable messages wait in a 2048-entry queue, each with a u16 rid, until a DATA packet that carried
;     them is acked (ack + 32 ack bits in every packet header); they are due again every RTO. Which packet
;     carried which rids is kept in a ring of SPK_COUNT sent packets, and a packet that is still unacked and
;     younger than SPK_KEEP_MS is never overwritten (the flush stops instead), so every ack that comes back
;     within SPK_KEEP_MS finds its packet whatever the send rate, and within SPK_COUNT packets otherwise;
;   - the receiver delivers them in rid order from a 512-entry window, drops duplicates, and reassembles
;     MT_BLOB_PART runs into one big message;
;   - unreliable messages are delivered at once and queued per frame in a 16 KiB buffer.
; Every length and offset read from a datagram is checked against that datagram, and a message type
; outside 1..NUM_MT-1 never reaches the game.
%include "common.inc"
default rel

global net_ep, net_ep_size
global net_ep_open, net_ep_close, net_ep_poll, net_ep_next_event, net_ep_flush
global net_ep_send, net_ep_send_big, net_ep_room, net_ep_accept, net_ep_deny, net_ep_drop
global net_ep_join, net_ep_join_state, net_ep_join_err
global net_ep_rv_host, net_ep_rv_state, net_ep_room_code
global net_ep_rtt_ms, net_ep_is_relay
global net_parse_addr, net_format_addr, net_local_ip
global net_ep_set_test, net_ep_test_rid

extern time_mono_ns, i32_to_str

; ---- socket syscalls (common.inc has the file ones) ----------------------------------------------
%define NSYS_SOCKET      41
%define NSYS_CONNECT     42
%define NSYS_SENDTO      44
%define NSYS_RECVFROM    45
%define NSYS_BIND        49
%define NSYS_GETSOCKNAME 51
%define NSYS_SETSOCKOPT  54
%define NSYS_GETRANDOM   318
%define N_AF_INET        2
%define N_SOCK_DGRAM     2
%define N_SOCK_NONBLOCK  0x800
%define N_SOCK_CLOEXEC   0x80000
%define N_SOL_SOCKET     1
%define N_SO_SNDBUF      7
%define N_SO_RCVBUF      8

; ---- protocol constants private to the transport ---------------------------------------------------
%define RV_VER            1                 ; rendezvous protocol version byte
%define RV_PORT_BE        (((RV_PORT & 0xFF) << 8) | (RV_PORT >> 8))
%define RV_RELAY_HDR      20                ; RV header, code[6], pad[2], addr NADDR
%define MAX_DGRAM         (NET_MTU + RV_RELAY_HDR)
%define RV_HOST_EVERY_MS  5000
%define RV_FAIL_MS        3000
%define RV_JOIN_EVERY_MS  500
%define RV_JOIN_FAIL_MS   5000
%define JOIN_PUNCH_MS     3000
%define JOIN_PUNCH_EVERY  100
%define JOIN_RELAY_MS     6000
%define JOIN_EVERY_MS     250
%define JOIN_DIRECT_MS    10000
%define PUNCH_MS          3000
%define PUNCH_EVERY_MS    100
%define RECENT_TTL_MS     15000
%define SRTT0_X8          1600              ; srtt starts at 200 ms, kept times 8
%define POLL_BUDGET       512               ; datagrams handled per net_ep_poll

%define CONN_FREE         0
%define CONN_ACTIVE       1
%define QE_SENT           1
%define QE_ACKED          2
%define SPK_COUNT         4096              ; sent-packet ring: 4 s of packets at 1000 per second (was 256)
%define SPK_KEEP_MS       2000              ; a packet still unacked and younger than this is never overwritten
%define SPK_RIDS          40
%define UR_SIZE           16384
%define EV_COUNT          64
%define RECENT_N          16
%define PUNCH_N           8

; ---- private layouts ---------------------------------------------------------------------------------
struc QE                                    ; one reliable message waiting for its ack
    .last:  resd 1                          ; ms of the last send
    .len:   resw 1
    .type:  resb 1
    .flags: resb 1                          ; QE_SENT | QE_ACKED
    .data:  resb NET_MSG_MAX
    .pad:   resb 4
endstruc                                    ; 1112

struc RW                                    ; a reliable message that arrived ahead of its turn
    .len:  resw 1
    .type: resb 1
    .pad:  resb 1
    .data: resb NET_MSG_MAX
endstruc                                    ; 1104

struc SPK                                   ; a DATA packet that was sent
    .seq:   resw 1
    .nrids: resb 1
    .state: resb 1                          ; 0 unused, 1 in flight, 2 acked
    .t:     resd 1                          ; ms when it was sent
    .rids:  resw SPK_RIDS                   ; the reliable ids it carried
endstruc                                    ; 88

struc RC                                    ; a CONNECT request seen lately (host), keyed by the joiner's nonce
    .reason: resd 1                         ; 0 pending, else the DENY_* sent
    .nonce:  resd 1
    .t:      resd 1
    .used:   resd 1
endstruc                                    ; 16

struc PU                                    ; a guest the host punches towards
    .pub:    resb NADDR_size
    .lan:    resb NADDR_size
    .until:  resd 1
    .next:   resd 1
    .active: resd 1
endstruc                                    ; 28

struc CONN
    .state:      resd 1                     ; CONN_*
    .slot:       resd 1
    .relay:      resd 1                     ; packets travel through the rendezvous server
    .token:      resd 1
    .nonce:      resd 1                     ; the CONNECT nonce that made it
    .addr:       resb NADDR_size            ; the peer (for a relayed one: its public address)
    .last_rx:    resd 1                     ; ms of the last packet received
    .last_tx:    resd 1                     ; ms of the last DATA packet sent
    .srtt8:      resd 1                     ; 8 * smoothed round trip, ms
    .tx_seq:     resd 1                     ; next DATA packet number (u16, never 0)
    .rx_ack:     resd 1                     ; newest packet number received (0 none)
    .rx_bits:    resd 1                     ; bit i = packet rx_ack-1-i was received
    .q_head:     resd 1                     ; rid of the oldest unacked entry (u16)
    .q_count:    resd 1                     ; entries queued (<= NET_RQ)
    .rx_exp:     resd 1                     ; next rid to deliver (u16)
    .ur_len:     resd 1                     ; bytes in urbuf
    .blob_on:    resd 1
    .blob_next:  resd 1
    .blob_parts: resd 1
    .blob_total: resd 1
    .blob_type:  resd 1
    .bye:        resd 1                     ; reason + 1 of a goodbye that waits for room in the event queue
    .ring:       resb SPK_COUNT * SPK_size
    .rw_valid:   resb NET_RWIN
    .zero_end:   resb 0                     ; conn_init clears everything before this
    alignb 16
    .urbuf:      resb UR_SIZE
    .q:          resb NET_RQ * QE_size
    .rw:         resb NET_RWIN * RW_size
    .blob:       resb NET_BLOB_MAX
endstruc

struc NETEP
    .open:        resd 1
    .fd:          resd 1
    .port:        resd 1                    ; bound port, host order
    .now:         resd 1                    ; ms, refreshed by poll / flush / accept / join
    .drop_pct:    resd 1                    ; test seam: percent of outgoing datagrams dropped
    .rng:         resd 1
    .clk:         resq 1                    ; test seam: pointer to a ns clock, or 0
    .deliver:     resq 1                    ; the game's message callback
    .ev_head:     resd 1
    .ev_tail:     resd 1
    .is_guest:    resd 1                    ; net_ep_join was called: never accept CONNECT
    .rv_set:      resd 1                    ; .rv is valid (RV packets are taken from it)
    .rv_on:       resd 1                    ; hosting: keep the room registered
    .rv_state:    resd 1
    .rv_nonce:    resd 1
    .rv_t0:       resd 1
    .rv_next:     resd 1
    .code_set:    resd 1
    .join_state:  resd 1
    .join_err:    resd 1
    .join_nonce:  resd 1
    .join_t0:     resd 1
    .join_next:   resd 1
    .join_force:  resd 1
    .recent_pos:  resd 1
    alignb 8
    .rv:          resb NADDR_size           ; the rendezvous server
    .lan:         resb NADDR_size           ; our LAN address (ip toward the server, bound port)
    .join_target: resb NADDR_size           ; direct join: the host
    .join_pub:    resb NADDR_size           ; code join: the host's public address
    .join_lan:    resb NADDR_size           ; code join: the host's LAN address
    .code:        resb 8                    ; the room code (host: from RV_ROOM, guest: the one joined)
    .join_name:   resb 24
    .events:      resb EV_COUNT * NETEVENT_size
    .recent:      resb RECENT_N * RC_size
    .punch:       resb PUNCH_N * PU_size
    .rxbuf:       resb 2048
    .txbuf:       resb 1280                 ; 20 bytes of RV_RELAY room, then a packet
    alignb 16
    .conn:        resb NET_MAX_PEERS * CONN_size
endstruc

section .rodata
align 4
net_ep_size:    dd NETEP_size
deny_err:       db NJE_UNREACHABLE, NJE_DENY_FULL, NJE_DENY_VERSION, NJE_DENY_NAME, NJE_DENY_CLOSED
d_loopback:     dd 0x0100007F                       ; 127.0.0.1 as bytes 7F 00 00 01

section .bss
alignb 4096
net_ep:         resb NETEP_size

section .text

; =====================================================================================================
; clock, randomness, raw datagrams
; =====================================================================================================

; ep_now(rdi ep) -> eax milliseconds, also kept in ep.now. The injected test clock wins over the real one.
ep_now:
    mov     rax, [rdi + NETEP.clk]
    test    rax, rax
    jz      .real
    mov     rax, [rax]
    jmp     .conv
.real:
    push    rdi
    call    time_mono_ns
    pop     rdi
.conv:
    xor     edx, edx
    mov     ecx, 1000000
    div     rcx
    mov     [rdi + NETEP.now], eax
    ret

; ep_rand32() -> eax a nonzero random dword (getrandom; the cycle counter if that fails)
ep_rand32:
    sub     rsp, 24
    mov     eax, NSYS_GETRANDOM
    lea     rdi, [rsp]
    mov     esi, 4
    xor     edx, edx
    syscall
    cmp     rax, 4
    je      .got
    rdtsc
    xor     eax, edx
    mov     [rsp], eax
.got:
    mov     eax, [rsp]
    add     rsp, 24
    test    eax, eax
    jnz     .ret
    mov     eax, 0x9E3779B9
.ret:
    ret

; ep_send_raw(rdi ep, rsi dst NADDR*, rdx buf, ecx len): one datagram to dst. The test seam may drop it.
; A send error (a full socket buffer) is ignored: reliable traffic is resent, the rest is expendable.
; Clobbers the caller-saved registers.
ep_send_raw:
    cmp     dword [rdi + NETEP.open], 0
    je      .ret
    mov     r10d, [rdi + NETEP.drop_pct]
    test    r10d, r10d
    jz      .send
    mov     eax, [rdi + NETEP.rng]              ; xorshift32
    mov     r8d, eax
    shl     r8d, 13
    xor     eax, r8d
    mov     r8d, eax
    shr     r8d, 17
    xor     eax, r8d
    mov     r8d, eax
    shl     r8d, 5
    xor     eax, r8d
    mov     [rdi + NETEP.rng], eax
    mov     r11, rdx                            ; div clobbers rdx
    xor     edx, edx
    mov     r8d, 100
    div     r8d
    cmp     edx, r10d
    mov     rdx, r11
    jb      .ret                                ; dropped
.send:
    sub     rsp, 24
    mov     word [rsp], N_AF_INET
    movzx   eax, word [rsi + NADDR.port]
    mov     [rsp + 2], ax
    mov     eax, [rsi + NADDR.ip]
    mov     [rsp + 4], eax
    mov     qword [rsp + 8], 0
    mov     r8, rsp
    mov     r9d, 16
    mov     rsi, rdx
    mov     edx, ecx
    xor     r10d, r10d
    mov     edi, [rdi + NETEP.fd]
    mov     eax, NSYS_SENDTO
    syscall
    add     rsp, 24
.ret:
    ret

; =====================================================================================================
; addresses
; =====================================================================================================

; net_parse_addr(rdi zstr, rsi NADDR*, edx default_port) -> eax 1 ok / 0 bad.
; "a.b.c.d" or "a.b.c.d:port" (port 1..65535); nothing else, no spaces. The result is in network order.
net_parse_addr:
    sub     rsp, 8
    mov     r8, rdi
    xor     ecx, ecx                            ; octets parsed
.octet:
    xor     eax, eax                            ; value
    xor     r9d, r9d                            ; digits
.digit:
    movzx   r10d, byte [r8]
    sub     r10d, '0'
    cmp     r10d, 9
    ja      .endnum
    imul    eax, eax, 10
    add     eax, r10d
    cmp     eax, 255
    ja      .bad
    inc     r9d
    inc     r8
    jmp     .digit
.endnum:
    test    r9d, r9d
    jz      .bad
    cmp     r9d, 3
    ja      .bad
    mov     [rsp + rcx], al
    inc     ecx
    cmp     ecx, 4
    jae     .tail
    cmp     byte [r8], '.'
    jne     .bad
    inc     r8
    jmp     .octet
.tail:
    mov     eax, edx                            ; default port
    movzx   r10d, byte [r8]
    test    r10d, r10d
    jz      .store
    cmp     r10d, ':'
    jne     .bad
    inc     r8
    xor     eax, eax
    xor     r9d, r9d
.pdigit:
    movzx   r10d, byte [r8]
    test    r10d, r10d
    jz      .pend
    sub     r10d, '0'
    cmp     r10d, 9
    ja      .bad
    imul    eax, eax, 10
    add     eax, r10d
    cmp     eax, 65535
    ja      .bad
    inc     r9d
    inc     r8
    jmp     .pdigit
.pend:
    test    r9d, r9d
    jz      .bad
    test    eax, eax
    jz      .bad
.store:
    rol     ax, 8                               ; host -> network order
    mov     [rsi + NADDR.port], ax
    mov     word [rsi + NADDR.pad], 0
    mov     eax, [rsp]
    mov     [rsi + NADDR.ip], eax
    mov     eax, 1
    add     rsp, 8
    ret
.bad:
    xor     eax, eax
    add     rsp, 8
    ret

; net_format_addr(rdi NADDR*, rsi buf) -> rax end: "a.b.c.d:port" without a NUL
net_format_addr:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    xor     r13d, r13d
.oct:
    movzx   edi, byte [rbx + r13]
    mov     rsi, r12
    call    i32_to_str
    mov     r12, rax
    inc     r13d
    cmp     r13d, 4
    jae     .port
    mov     byte [r12], '.'
    inc     r12
    jmp     .oct
.port:
    mov     byte [r12], ':'
    inc     r12
    movzx   edi, word [rbx + NADDR.port]
    rol     di, 8
    movzx   edi, di
    mov     rsi, r12
    call    i32_to_str
    pop     r13
    pop     r12
    pop     rbx
    ret

; net_local_ip(rdi NADDR* probe) -> eax our IPv4 address (network order) on the route to the probe.
; A UDP socket is connected to the probe (nothing is sent) and asked for its own name; 127.0.0.1 when
; there is no route.
net_local_ip:
    push    rbx
    push    r12
    sub     rsp, 40
    mov     r12, rdi
    mov     eax, NSYS_SOCKET
    mov     edi, N_AF_INET
    mov     esi, N_SOCK_DGRAM | N_SOCK_CLOEXEC
    xor     edx, edx
    syscall
    test    rax, rax
    js      .fallback
    mov     ebx, eax                            ; fd
    mov     word [rsp], N_AF_INET
    movzx   eax, word [r12 + NADDR.port]
    mov     [rsp + 2], ax
    mov     eax, [r12 + NADDR.ip]
    mov     [rsp + 4], eax
    mov     qword [rsp + 8], 0
    mov     eax, NSYS_CONNECT
    mov     edi, ebx
    lea     rsi, [rsp]
    mov     edx, 16
    syscall
    test    rax, rax
    js      .closed
    mov     qword [rsp + 16], 0
    mov     qword [rsp + 24], 0
    mov     dword [rsp + 32], 16
    mov     eax, NSYS_GETSOCKNAME
    mov     edi, ebx
    lea     rsi, [rsp + 16]
    lea     rdx, [rsp + 32]
    syscall
    test    rax, rax
    js      .closed
    mov     r12d, [rsp + 20]                    ; sin_addr
    mov     eax, SYS_CLOSE
    mov     edi, ebx
    syscall
    test    r12d, r12d
    jz      .fallback
    mov     eax, r12d
    jmp     .ret
.closed:
    mov     eax, SYS_CLOSE
    mov     edi, ebx
    syscall
.fallback:
    mov     eax, [d_loopback]
.ret:
    add     rsp, 40
    pop     r12
    pop     rbx
    ret

; =====================================================================================================
; endpoint life, events
; =====================================================================================================

; ep_clear(rdi ep): zero the endpoint header and free every connection (their bulk arrays stay untouched)
ep_clear:
    push    rdi
    mov     ecx, NETEP.conn
    xor     eax, eax
    rep     stosb
    pop     rdi
    xor     ecx, ecx
.conns:
    imul    rax, rcx, CONN_size
    mov     dword [rdi + rax + NETEP.conn + CONN.state], CONN_FREE
    inc     ecx
    cmp     ecx, NET_MAX_PEERS
    jb      .conns
    ret

; net_ep_open(rdi ep, esi port 0 = ephemeral, edx tries) -> eax the bound port, or -errno.
; A non-blocking IPv4 UDP socket with 1 MiB buffers, bound on 0.0.0.0 to port .. port+tries-1.
net_ep_open:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 48
    mov     rbx, rdi
    mov     r12d, esi                           ; port to try
    mov     r13d, edx                           ; tries left
    cmp     dword [rbx + NETEP.open], 0
    je      .fresh
    mov     edi, [rbx + NETEP.fd]               ; reopened without a close: do not leak the old socket
    mov     eax, SYS_CLOSE
    syscall
.fresh:
    mov     rdi, rbx
    call    ep_clear
    test    r13d, r13d
    jnz     .tries
    mov     r13d, 1
.tries:
    test    r12d, r12d
    jnz     .named
    mov     r13d, 1                             ; ephemeral: one bind
.named:
    mov     eax, 65536
    sub     eax, r12d
    cmp     r13d, eax
    jbe     .tries_ok
    mov     r13d, eax
    test    r13d, r13d
    jnz     .tries_ok
    mov     r13d, 1
.tries_ok:
    mov     eax, NSYS_SOCKET
    mov     edi, N_AF_INET
    mov     esi, N_SOCK_DGRAM | N_SOCK_NONBLOCK | N_SOCK_CLOEXEC
    xor     edx, edx
    syscall
    test    rax, rax
    js      .ret
    mov     r14d, eax                           ; fd
    mov     dword [rsp + 16], 1048576
    mov     eax, NSYS_SETSOCKOPT
    mov     edi, r14d
    mov     esi, N_SOL_SOCKET
    mov     edx, N_SO_RCVBUF
    lea     r10, [rsp + 16]
    mov     r8d, 4
    syscall
    mov     eax, NSYS_SETSOCKOPT
    mov     edi, r14d
    mov     esi, N_SOL_SOCKET
    mov     edx, N_SO_SNDBUF
    lea     r10, [rsp + 16]
    mov     r8d, 4
    syscall
.try:
    mov     word [rsp], N_AF_INET
    mov     eax, r12d
    rol     ax, 8
    mov     [rsp + 2], ax
    mov     dword [rsp + 4], 0
    mov     qword [rsp + 8], 0
    mov     eax, NSYS_BIND
    mov     edi, r14d
    lea     rsi, [rsp]
    mov     edx, 16
    syscall
    test    rax, rax
    jns     .bound
    mov     [rsp + 24], rax                     ; the errno of the last try
    inc     r12d
    dec     r13d
    jnz     .try
    mov     eax, SYS_CLOSE
    mov     edi, r14d
    syscall
    mov     rax, [rsp + 24]
    jmp     .ret
.bound:
    test    r12d, r12d
    jnz     .named_port
    mov     qword [rsp + 32], 0                 ; ephemeral: ask which port we got
    mov     qword [rsp + 40], 0
    mov     dword [rsp + 24], 16
    mov     eax, NSYS_GETSOCKNAME
    mov     edi, r14d
    lea     rsi, [rsp + 32]
    lea     rdx, [rsp + 24]
    syscall
    movzx   r12d, word [rsp + 34]
    rol     r12w, 8
    movzx   r12d, r12w
.named_port:
    mov     [rbx + NETEP.fd], r14d
    mov     [rbx + NETEP.port], r12d
    mov     dword [rbx + NETEP.open], 1
    mov     dword [rbx + NETEP.rng], 1234
    mov     eax, r12d
.ret:
    add     rsp, 48
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; net_ep_close(rdi ep): close the socket and free every connection; the endpoint is blank afterwards
net_ep_close:
    sub     rsp, 8
    cmp     dword [rdi + NETEP.open], 0
    je      .clear
    push    rdi
    mov     edi, [rdi + NETEP.fd]
    mov     eax, SYS_CLOSE
    syscall
    pop     rdi
.clear:
    call    ep_clear
    add     rsp, 8
    ret

; net_ep_next_event(rdi ep, rsi NETEVENT*) -> eax 1 and the oldest event copied out / 0 when none
net_ep_next_event:
    mov     eax, [rdi + NETEP.ev_head]
    cmp     eax, [rdi + NETEP.ev_tail]
    je      .none
    and     eax, EV_COUNT - 1
    imul    eax, eax, NETEVENT_size
    lea     rax, [rdi + rax + NETEP.events]
    movups  xmm0, [rax]
    movups  [rsi], xmm0
    movups  xmm0, [rax + 16]
    movups  [rsi + 16], xmm0
    mov     ecx, [rax + 32]
    mov     [rsi + 32], ecx
    inc     dword [rdi + NETEP.ev_head]
    mov     eax, 1
    ret
.none:
    xor     eax, eax
    ret

; ev_post(rdi ep, esi kind, edx slot, ecx reason, r8d relay) -> rax the queued event (zeroed, then these
; four fields set; the caller may fill addr / nonce / name) or 0 when the queue is full
ev_post:
    mov     eax, [rdi + NETEP.ev_tail]
    mov     r9d, eax
    sub     r9d, [rdi + NETEP.ev_head]
    cmp     r9d, EV_COUNT
    jae     .full
    and     eax, EV_COUNT - 1
    imul    eax, eax, NETEVENT_size
    lea     rax, [rdi + rax + NETEP.events]
    pxor    xmm0, xmm0
    movups  [rax], xmm0
    movups  [rax + 16], xmm0
    mov     dword [rax + 32], 0
    mov     [rax + NETEVENT.kind], sil
    mov     [rax + NETEVENT.slot], dl
    mov     [rax + NETEVENT.reason], cl
    mov     [rax + NETEVENT.relay], r8b
    inc     dword [rdi + NETEP.ev_tail]
    ret
.full:
    xor     eax, eax
    ret

; ev_set_addr(rax event, rsi NADDR*): the event's address
ev_set_addr:
    mov     ecx, [rsi + NADDR.ip]
    mov     [rax + NETEVENT.addr + NADDR.ip], ecx
    movzx   ecx, word [rsi + NADDR.port]
    mov     [rax + NETEVENT.addr + NADDR.port], cx
    ret

; =====================================================================================================
; control packets
; =====================================================================================================

; ctl_begin(rdi ep, esi kind, edx token) -> rax payload pointer. Writes the 16-byte header of a packet at
; txbuf + 20 (seq, ack and ack_bits zero).
ctl_begin:
    lea     rax, [rdi + NETEP.txbuf + 20]
    mov     word [rax], NET_MAGIC
    mov     byte [rax + 2], NET_VERSION
    mov     [rax + 3], sil
    mov     [rax + 4], edx
    mov     qword [rax + 8], 0
    add     rax, NET_PKT_HDR
    ret

; send_game(rdi ep, rsi dst NADDR*, edx relay, ecx len): send the packet built at txbuf + 20 to dst, directly
; or wrapped in RV_RELAY through the rendezvous server (dst becomes the wrapper's address)
send_game:
    test    edx, edx
    jnz     .relay
    lea     rdx, [rdi + NETEP.txbuf + 20]
    jmp     ep_send_raw
.relay:
    lea     r8, [rdi + NETEP.txbuf]
    mov     word [r8], RV_MAGIC
    mov     byte [r8 + 2], RV_VER
    mov     byte [r8 + 3], RV_RELAY
    mov     eax, [rdi + NETEP.code]
    mov     [r8 + 4], eax
    movzx   eax, word [rdi + NETEP.code + 4]
    mov     [r8 + 8], eax                       ; code[4..5] and the two pad bytes
    mov     eax, [rsi + NADDR.ip]
    mov     [r8 + 12], eax
    movzx   eax, word [rsi + NADDR.port]
    mov     [r8 + 16], eax
    lea     rsi, [rdi + NETEP.rv]
    mov     rdx, r8
    add     ecx, RV_RELAY_HDR
    jmp     ep_send_raw

; send_connect(rdi ep, rsi dst NADDR*, edx relay): CONNECT with the join nonce and name
send_connect:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13d, edx
    mov     esi, PK_CONNECT
    xor     edx, edx
    call    ctl_begin
    mov     ecx, [rbx + NETEP.join_nonce]
    mov     [rax], ecx
    movups  xmm0, [rbx + NETEP.join_name]
    movups  [rax + 4], xmm0
    movzx   ecx, byte [rbx + NETEP.join_name + 16]
    mov     [rax + 20], cl
    mov     rdi, rbx
    mov     rsi, r12
    mov     edx, r13d
    mov     ecx, NET_PKT_HDR + 4 + 17
    call    send_game
    pop     r13
    pop     r12
    pop     rbx
    ret

; send_accept(rdi ep, rsi conn): ACCEPT for the connection, to its address
send_accept:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    mov     esi, PK_ACCEPT
    mov     edx, [r12 + CONN.token]
    call    ctl_begin
    mov     ecx, [r12 + CONN.nonce]
    mov     [rax], ecx
    mov     ecx, [r12 + CONN.slot]
    mov     [rax + 4], cl
    mov     byte [rax + 5], NET_MAX_PEERS
    mov     rdi, rbx
    lea     rsi, [r12 + CONN.addr]
    mov     edx, [r12 + CONN.relay]
    mov     ecx, NET_PKT_HDR + 6
    call    send_game
    pop     r13
    pop     r12
    pop     rbx
    ret

; send_deny(rdi ep, rsi dst NADDR*, edx relay, ecx nonce, r8d reason)
send_deny:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13d, edx
    mov     r14d, ecx
    mov     r15d, r8d
    mov     esi, PK_DENY
    xor     edx, edx
    call    ctl_begin
    mov     [rax], r14d
    mov     [rax + 4], r15b
    mov     rdi, rbx
    mov     rsi, r12
    mov     edx, r13d
    mov     ecx, NET_PKT_HDR + 5
    call    send_game
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; send_punch(rdi ep, rsi dst NADDR*): an empty PUNCH, to open the NAT mapping towards dst
send_punch:
    sub     rsp, 8
    mov     [rsp], rsi
    mov     esi, PK_PUNCH
    xor     edx, edx
    call    ctl_begin
    mov     rsi, [rsp]
    xor     edx, edx
    mov     ecx, NET_PKT_HDR
    add     rsp, 8
    jmp     send_game

; send_rv_host(rdi ep): RV_HOST {nonce, lan} to the rendezvous server
send_rv_host:
    lea     rax, [rdi + NETEP.txbuf + 20]
    mov     word [rax], RV_MAGIC
    mov     byte [rax + 2], RV_VER
    mov     byte [rax + 3], RV_HOST
    mov     ecx, [rdi + NETEP.rv_nonce]
    mov     [rax + 4], ecx
    mov     rcx, [rdi + NETEP.lan]
    mov     [rax + 8], rcx
    lea     rsi, [rdi + NETEP.rv]
    mov     rdx, rax
    mov     ecx, 16
    jmp     ep_send_raw

; send_rv_join(rdi ep): RV_JOIN {code, nonce, lan} to the rendezvous server
send_rv_join:
    lea     rax, [rdi + NETEP.txbuf + 20]
    mov     word [rax], RV_MAGIC
    mov     byte [rax + 2], RV_VER
    mov     byte [rax + 3], RV_JOIN
    mov     ecx, [rdi + NETEP.code]
    mov     [rax + 4], ecx
    movzx   ecx, word [rdi + NETEP.code + 4]
    mov     [rax + 8], ecx                      ; code[4..5] and the two pad bytes
    mov     ecx, [rdi + NETEP.join_nonce]
    mov     [rax + 12], ecx
    mov     rcx, [rdi + NETEP.lan]
    mov     [rax + 16], rcx
    lea     rsi, [rdi + NETEP.rv]
    mov     rdx, rax
    mov     ecx, 24
    jmp     ep_send_raw

; =====================================================================================================
; connections: queueing, flushing
; =====================================================================================================

; conn_init(rdi conn, esi now): clear the connection's header and sent-packet ring, mark it active
conn_init:
    mov     edx, esi
    xor     eax, eax
    mov     rsi, rdi
    mov     ecx, CONN.zero_end
    rep     stosb
    mov     dword [rsi + CONN.state], CONN_ACTIVE
    mov     [rsi + CONN.last_rx], edx
    mov     [rsi + CONN.last_tx], edx
    mov     dword [rsi + CONN.srtt8], SRTT0_X8
    mov     dword [rsi + CONN.tx_seq], 1
    ret

; net_ep_room(rdi ep, esi slot) -> eax free reliable queue entries of that connection (0 if none)
net_ep_room:
    xor     eax, eax
    cmp     dword [rdi + NETEP.open], 0
    je      .ret
    cmp     esi, NET_MAX_PEERS
    jae     .ret
    mov     eax, esi
    imul    rax, rax, CONN_size
    lea     rcx, [rdi + rax + NETEP.conn]
    xor     eax, eax
    cmp     dword [rcx + CONN.state], CONN_ACTIVE
    jne     .ret
    mov     eax, NET_RQ
    sub     eax, [rcx + CONN.q_count]
.ret:
    ret

; net_ep_send(rdi ep, esi slot, edx type, rcx payload, r8d len <= NET_MSG_MAX, r9d reliable) -> eax 1 queued / 0
; no room (reliable queue full, unreliable buffer full) or no such connection
net_ep_send:
    xor     eax, eax
    cmp     dword [rdi + NETEP.open], 0
    je      .ret
    cmp     esi, NET_MAX_PEERS
    jae     .ret
    cmp     r8d, NET_MSG_MAX
    ja      .ret
    mov     eax, esi
    imul    rax, rax, CONN_size
    lea     r10, [rdi + rax + NETEP.conn]
    xor     eax, eax
    cmp     dword [r10 + CONN.state], CONN_ACTIVE
    jne     .ret
    test    r9d, r9d
    jz      .unrel
    mov     eax, [r10 + CONN.q_count]
    cmp     eax, NET_RQ
    jae     .no
    add     eax, [r10 + CONN.q_head]
    and     eax, NET_RQ - 1                     ; the entry of rid head + count
    imul    eax, eax, QE_size
    lea     r11, [r10 + rax + CONN.q]
    mov     [r11 + QE.type], dl
    mov     [r11 + QE.len], r8w
    mov     byte [r11 + QE.flags], 0
    lea     rdi, [r11 + QE.data]
    mov     rsi, rcx
    mov     ecx, r8d
    rep     movsb
    inc     dword [r10 + CONN.q_count]
    mov     eax, 1
    ret
.unrel:
    mov     eax, [r10 + CONN.ur_len]
    lea     r11d, [rax + r8 + 4]
    cmp     r11d, UR_SIZE
    ja      .no
    lea     rdi, [r10 + rax + CONN.urbuf]
    mov     [rdi], dl
    mov     byte [rdi + 1], 0
    mov     [rdi + 2], r8w
    add     rdi, 4
    mov     rsi, rcx
    mov     ecx, r8d
    rep     movsb
    mov     [r10 + CONN.ur_len], r11d
    mov     eax, 1
    ret
.no:
    xor     eax, eax
.ret:
    ret

; net_ep_send_big(rdi ep, esi slot, edx type, rcx data, r8d len <= NET_BLOB_MAX) -> eax 1 / 0.
; The data is cut into reliable MT_BLOB_PART messages {inner_type, pad, part u16, parts u16, pad u16,
; total u32, data}; all parts are queued or none.
net_ep_send_big:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24                             ; [rsp] type, [rsp+4] part index
    xor     eax, eax
    mov     rbx, rdi
    cmp     dword [rbx + NETEP.open], 0
    je      .out
    cmp     esi, NET_MAX_PEERS
    jae     .out
    cmp     r8d, NET_BLOB_MAX
    ja      .out
    mov     eax, esi
    imul    rax, rax, CONN_size
    lea     r12, [rbx + rax + NETEP.conn]
    xor     eax, eax
    cmp     dword [r12 + CONN.state], CONN_ACTIVE
    jne     .out
    mov     r13, rcx                            ; data
    mov     r14d, r8d                           ; len
    mov     [rsp], edx
    lea     eax, [r14 + NET_PART_MAX - 1]
    xor     edx, edx
    mov     ecx, NET_PART_MAX
    div     ecx
    test    eax, eax
    jnz     .parts_ok
    mov     eax, 1                              ; an empty blob is one empty part
.parts_ok:
    mov     r15d, eax                           ; parts
    mov     ecx, NET_RQ
    sub     ecx, [r12 + CONN.q_count]
    xor     eax, eax
    cmp     r15d, ecx
    ja      .out
    mov     dword [rsp + 4], 0
.part:
    mov     ecx, [rsp + 4]
    imul    ecx, ecx, NET_PART_MAX              ; offset of this part
    mov     edx, r14d
    sub     edx, ecx                            ; bytes left
    cmp     edx, NET_PART_MAX
    jbe     .chunk
    mov     edx, NET_PART_MAX
.chunk:
    mov     eax, [r12 + CONN.q_head]
    add     eax, [r12 + CONN.q_count]
    and     eax, NET_RQ - 1
    imul    eax, eax, QE_size
    lea     rdi, [r12 + rax + CONN.q]
    mov     byte [rdi + QE.type], MT_BLOB_PART
    lea     eax, [rdx + 12]
    mov     [rdi + QE.len], ax
    mov     byte [rdi + QE.flags], 0
    mov     eax, [rsp]
    mov     [rdi + QE.data], al
    mov     byte [rdi + QE.data + 1], 0
    mov     eax, [rsp + 4]
    mov     [rdi + QE.data + 2], ax
    mov     [rdi + QE.data + 4], r15w
    mov     word [rdi + QE.data + 6], 0
    mov     [rdi + QE.data + 8], r14d
    lea     rsi, [r13 + rcx]
    mov     ecx, edx
    add     rdi, QE.data + 12
    rep     movsb
    inc     dword [r12 + CONN.q_count]
    inc     dword [rsp + 4]
    mov     eax, [rsp + 4]
    cmp     eax, r15d
    jb      .part
    mov     eax, 1
.out:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; conn_flush locals (rsp relative)
%define FL_RTO    0
%define FL_LIMIT  4
%define FL_RELPK  8
%define FL_NPK    12
%define FL_UROFF  16
%define FL_NRIDS  20
%define FL_SP     24

; conn_flush(rdi ep, rsi conn): send this frame's DATA packets of one connection, at most NET_PKTS_FRAME.
; Packet by packet: the due reliable messages oldest first (never one more than NET_RWIN past the oldest
; unacked), then the unreliable records that fit. When unreliable data is pending, up to half the packets are
; kept for it, so a long reliable backlog (a big download) cannot starve the snapshots. An empty packet goes
; out when nothing else did for NET_KEEPALIVE_MS, so acks keep flowing. A packet whose ring slot still holds an
; unacked packet younger than SPK_KEEP_MS is not built at all: the ring is full of packets in flight, and
; sending more would make their acks useless (with a 600 ms round trip and 8 packets per frame the acks of a
; 256-entry ring all came back too late and the channel stalled for good). The unreliable buffer is emptied.
conn_flush:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 56
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13d, [rbx + NETEP.now]
    mov     eax, [r12 + CONN.srtt8]
    shr     eax, 2                              ; RTO = max(NET_RTO_MIN_MS, 2 * srtt)
    cmp     eax, NET_RTO_MIN_MS
    jae     .rto_ok
    mov     eax, NET_RTO_MIN_MS
.rto_ok:
    mov     [rsp + FL_RTO], eax
    mov     eax, [r12 + CONN.q_count]
    cmp     eax, NET_RWIN
    jbe     .limit_ok
    mov     eax, NET_RWIN
.limit_ok:
    mov     [rsp + FL_LIMIT], eax
    mov     eax, [r12 + CONN.ur_len]
    add     eax, NET_MTU - NET_PKT_HDR - 1
    xor     edx, edx
    mov     ecx, NET_MTU - NET_PKT_HDR
    div     ecx
    cmp     eax, NET_PKTS_FRAME / 2
    jbe     .ur_ok
    mov     eax, NET_PKTS_FRAME / 2
.ur_ok:
    mov     ecx, NET_PKTS_FRAME
    sub     ecx, eax
    mov     [rsp + FL_RELPK], ecx               ; packets that may carry reliable messages
    mov     dword [rsp + FL_NPK], 0
    mov     dword [rsp + FL_UROFF], 0
    xor     r14d, r14d                          ; scan position in the reliable queue
.packet:
    mov     eax, [r12 + CONN.tx_seq]
    mov     edx, eax
    and     edx, SPK_COUNT - 1
    imul    edx, edx, SPK_size
    lea     rcx, [r12 + rdx + CONN.ring]
    cmp     byte [rcx + SPK.state], 1
    jne     .slot_free
    mov     edx, r13d
    sub     edx, [rcx + SPK.t]
    cmp     edx, SPK_KEEP_MS
    jb      .done                               ; the packet in this slot is in flight and young: its ack must still find
.slot_free:                                     ; it, so nothing more goes out until an ack (or its age) frees the slot
    mov     [rsp + FL_SP], rcx
    mov     [rcx + SPK.seq], ax
    mov     byte [rcx + SPK.nrids], 0
    mov     byte [rcx + SPK.state], 0
    mov     [rcx + SPK.t], r13d
    mov     dword [rsp + FL_NRIDS], 0
    mov     rdi, rbx
    mov     esi, PK_DATA
    mov     edx, [r12 + CONN.token]
    call    ctl_begin
    lea     rdi, [rbx + NETEP.txbuf + 20]
    mov     eax, [r12 + CONN.tx_seq]
    mov     [rdi + 8], ax
    mov     eax, [r12 + CONN.rx_ack]
    mov     [rdi + 10], ax
    mov     eax, [r12 + CONN.rx_bits]
    mov     [rdi + 12], eax
    mov     r15d, NET_PKT_HDR                   ; write position
    mov     eax, [rsp + FL_NPK]
    cmp     eax, [rsp + FL_RELPK]
    jae     .unrel
.rel:
    cmp     r14d, [rsp + FL_LIMIT]
    jae     .unrel
    cmp     dword [rsp + FL_NRIDS], SPK_RIDS
    jae     .unrel
    mov     r8d, [r12 + CONN.q_head]
    add     r8d, r14d
    and     r8d, 0xFFFF                         ; rid
    mov     eax, r8d
    and     eax, NET_RQ - 1
    imul    eax, eax, QE_size
    lea     r9, [r12 + rax + CONN.q]
    movzx   eax, byte [r9 + QE.flags]
    test    al, QE_ACKED
    jnz     .skip
    test    al, QE_SENT
    jz      .due
    mov     edx, r13d
    sub     edx, [r9 + QE.last]
    cmp     edx, [rsp + FL_RTO]
    jb      .skip
.due:
    movzx   ecx, word [r9 + QE.len]
    lea     edx, [r15 + rcx + 6]
    cmp     edx, NET_MTU
    ja      .unrel                              ; this packet is full
    lea     rdi, [rbx + r15 + NETEP.txbuf + 20]
    movzx   eax, byte [r9 + QE.type]
    mov     [rdi], al
    mov     byte [rdi + 1], 1
    mov     [rdi + 2], cx
    mov     [rdi + 4], r8w
    add     rdi, 6
    lea     rsi, [r9 + QE.data]
    rep     movsb
    mov     r15d, edx
    or      byte [r9 + QE.flags], QE_SENT
    mov     [r9 + QE.last], r13d
    mov     rcx, [rsp + FL_SP]
    movzx   eax, byte [rcx + SPK.nrids]
    mov     [rcx + SPK.rids + rax * 2], r8w
    inc     eax
    mov     [rcx + SPK.nrids], al
    mov     [rsp + FL_NRIDS], eax
.skip:
    inc     r14d
    jmp     .rel
.unrel:
    mov     eax, [rsp + FL_UROFF]
.ur_loop:
    cmp     eax, [r12 + CONN.ur_len]
    jae     .ur_done
    lea     rsi, [r12 + rax + CONN.urbuf]
    movzx   ecx, word [rsi + 2]
    add     ecx, 4                              ; record size on the wire
    lea     edx, [r15 + rcx]
    cmp     edx, NET_MTU
    ja      .ur_done
    lea     rdi, [rbx + r15 + NETEP.txbuf + 20]
    mov     r15d, edx
    add     eax, ecx
    rep     movsb
    jmp     .ur_loop
.ur_done:
    mov     [rsp + FL_UROFF], eax
    cmp     r15d, NET_PKT_HDR
    ja      .commit                             ; the packet carries something
    cmp     dword [rsp + FL_NPK], 0
    jne     .done
    mov     eax, r13d
    sub     eax, [r12 + CONN.last_tx]
    cmp     eax, NET_KEEPALIVE_MS
    jb      .done                               ; nothing to say and no keepalive due
.commit:
    mov     rcx, [rsp + FL_SP]
    mov     byte [rcx + SPK.state], 1
    mov     eax, [r12 + CONN.tx_seq]
    inc     eax
    and     eax, 0xFFFF
    jnz     .seq_ok
    mov     eax, 1                              ; seq 0 means "nothing received yet" in an ack
.seq_ok:
    mov     [r12 + CONN.tx_seq], eax
    mov     [r12 + CONN.last_tx], r13d
    mov     rdi, rbx
    lea     rsi, [r12 + CONN.addr]
    mov     edx, [r12 + CONN.relay]
    mov     ecx, r15d
    call    send_game
    inc     dword [rsp + FL_NPK]
    cmp     dword [rsp + FL_NPK], NET_PKTS_FRAME
    jae     .done
    cmp     r14d, [rsp + FL_LIMIT]
    jb      .packet
    mov     eax, [rsp + FL_UROFF]
    cmp     eax, [r12 + CONN.ur_len]
    jb      .packet
.done:
    mov     dword [r12 + CONN.ur_len], 0
    add     rsp, 56
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; net_ep_flush(rdi ep): the join / rendezvous retries, then every connection's packets for this frame
net_ep_flush:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    cmp     dword [rbx + NETEP.open], 0
    je      .out
    call    ep_now
    mov     rdi, rbx
    call    ep_ticks
    xor     r12d, r12d
.loop:
    mov     eax, r12d
    imul    rax, rax, CONN_size
    lea     rsi, [rbx + rax + NETEP.conn]
    cmp     dword [rsi + CONN.state], CONN_ACTIVE
    jne     .next
    mov     rdi, rbx
    call    conn_flush
.next:
    inc     r12d
    cmp     r12d, NET_MAX_PEERS
    jb      .loop
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; =====================================================================================================
; connections: receiving
; =====================================================================================================

; conn_find(rdi ep, rsi src NADDR*, edx relay, ecx token) -> rax the active connection of that peer, or 0
conn_find:
    lea     rax, [rdi + NETEP.conn]
    mov     r8d, NET_MAX_PEERS
.loop:
    cmp     dword [rax + CONN.state], CONN_ACTIVE
    jne     .next
    cmp     [rax + CONN.token], ecx
    jne     .next
    cmp     [rax + CONN.relay], edx
    jne     .next
    mov     r9d, [rsi + NADDR.ip]
    cmp     r9d, [rax + CONN.addr + NADDR.ip]
    jne     .next
    movzx   r9d, word [rsi + NADDR.port]
    cmp     r9w, [rax + CONN.addr + NADDR.port]
    je      .found
.next:
    add     rax, CONN_size
    dec     r8d
    jnz     .loop
    xor     eax, eax
.found:
    ret

; pkt_acked(rdi ep, rsi conn, edx seq): the peer received our packet `seq`. Marks the reliable messages it
; carried as acked and feeds the round trip estimate (srtt = 7/8 srtt + 1/8 sample, kept times 8).
pkt_acked:
    mov     eax, edx
    and     eax, SPK_COUNT - 1
    imul    eax, eax, SPK_size
    lea     r8, [rsi + rax + CONN.ring]
    cmp     [r8 + SPK.seq], dx
    jne     .ret
    cmp     byte [r8 + SPK.state], 1
    jne     .ret
    mov     byte [r8 + SPK.state], 2
    mov     eax, [rdi + NETEP.now]
    sub     eax, [r8 + SPK.t]
    cmp     eax, 60000
    jbe     .sample
    mov     eax, 60000
.sample:
    mov     ecx, [rsi + CONN.srtt8]
    mov     r9d, ecx
    shr     r9d, 3
    sub     ecx, r9d
    add     ecx, eax
    mov     [rsi + CONN.srtt8], ecx
    movzx   ecx, byte [r8 + SPK.nrids]
    xor     r9d, r9d
.rid:
    cmp     r9d, ecx
    jae     .ret
    movzx   eax, word [r8 + SPK.rids + r9 * 2]
    mov     r10d, eax
    sub     r10d, [rsi + CONN.q_head]
    and     r10d, 0xFFFF
    cmp     r10d, [rsi + CONN.q_count]
    jae     .next                               ; not queued any more
    and     eax, NET_RQ - 1
    imul    eax, eax, QE_size
    or      byte [rsi + rax + CONN.q + QE.flags], QE_ACKED
.next:
    inc     r9d
    jmp     .rid
.ret:
    ret

; conn_ack(rdi ep, rsi conn, edx ack, ecx bits): the peer received packet `ack` and, for every set bit i,
; packet ack-1-i. Then the queue head moves past the acked entries.
conn_ack:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13d, edx
    mov     r14d, ecx
    test    r13d, r13d
    jz      .bits                               ; ack 0: the peer has received nothing yet
    mov     rdi, rbx
    mov     rsi, r12
    mov     edx, r13d
    call    pkt_acked
.bits:
    xor     r15d, r15d
.bit:
    test    r14d, r14d
    jz      .pop
    cmp     r15d, 32
    jae     .pop
    bt      r14d, r15d
    jnc     .nbit
    btr     r14d, r15d
    mov     edx, r13d
    sub     edx, r15d
    dec     edx
    and     edx, 0xFFFF
    mov     rdi, rbx
    mov     rsi, r12
    call    pkt_acked
.nbit:
    inc     r15d
    jmp     .bit
.pop:
    mov     eax, [r12 + CONN.q_count]
.popl:
    test    eax, eax
    jz      .popped
    mov     ecx, [r12 + CONN.q_head]
    and     ecx, NET_RQ - 1
    imul    ecx, ecx, QE_size
    test    byte [r12 + rcx + CONN.q + QE.flags], QE_ACKED
    jz      .popped
    mov     ecx, [r12 + CONN.q_head]
    inc     ecx
    and     ecx, 0xFFFF
    mov     [r12 + CONN.q_head], ecx
    dec     eax
    jmp     .popl
.popped:
    mov     [r12 + CONN.q_count], eax
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; deliver_msg(rdi ep, rsi conn, edx type, rcx payload, r8d len): one in-order message goes to the game
; (a blob part goes to the reassembly). Types outside 1..NUM_MT-1 are dropped here, never delivered.
deliver_msg:
    cmp     edx, MT_BLOB_PART
    je      blob_part
    lea     eax, [rdx - 1]
    cmp     eax, NUM_MT - 2
    ja      .drop
    mov     rax, [rdi + NETEP.deliver]
    test    rax, rax
    jz      .drop
    mov     edi, [rsi + CONN.slot]
    mov     esi, edx
    mov     rdx, rcx
    mov     ecx, r8d
    sub     rsp, 8
    call    rax
    add     rsp, 8
.drop:
    ret

; blob_part(rdi ep, rsi conn, rdx type (unused), rcx payload, r8d len): one MT_BLOB_PART {inner_type, pad,
; part u16, parts u16, pad u16, total u32, data}. Parts must come in order and be full (the last one ends
; exactly at total); anything else discards the blob. The last part delivers (inner_type, buffer, total).
blob_part:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rcx
    mov     r14d, r8d
    cmp     r14d, 12
    jb      .out
    movzx   eax, word [r13 + 2]                 ; part
    movzx   edx, word [r13 + 4]                 ; parts
    mov     ecx, [r13 + 8]                      ; total
    movzx   esi, byte [r13]                     ; inner type
    test    eax, eax
    jnz     .cont
    test    edx, edx
    jz      .bad
    cmp     ecx, NET_BLOB_MAX
    ja      .bad
    mov     dword [r12 + CONN.blob_on], 1       ; part 0 starts a blob
    mov     dword [r12 + CONN.blob_next], 0
    mov     [r12 + CONN.blob_parts], edx
    mov     [r12 + CONN.blob_total], ecx
    mov     [r12 + CONN.blob_type], esi
    jmp     .check
.cont:
    cmp     dword [r12 + CONN.blob_on], 0
    je      .out
.check:
    cmp     eax, [r12 + CONN.blob_next]
    jne     .bad
    cmp     edx, [r12 + CONN.blob_parts]
    jne     .bad
    cmp     ecx, [r12 + CONN.blob_total]
    jne     .bad
    cmp     esi, [r12 + CONN.blob_type]
    jne     .bad
    mov     r15d, eax                           ; part
    imul    eax, eax, NET_PART_MAX              ; offset
    lea     r8d, [r14 - 12]                     ; data length
    lea     r9d, [rax + r8]                     ; end
    cmp     r9d, ecx
    ja      .bad                                ; never past total (total <= NET_BLOB_MAX was checked)
    dec     edx
    cmp     r15d, edx
    je      .last
    cmp     r8d, NET_PART_MAX
    jne     .bad
    jmp     .copy
.last:
    cmp     r9d, ecx
    jne     .bad
.copy:
    lea     rdi, [r12 + rax + CONN.blob]
    lea     rsi, [r13 + 12]
    mov     ecx, r8d
    rep     movsb
    inc     dword [r12 + CONN.blob_next]
    mov     eax, [r12 + CONN.blob_parts]
    dec     eax
    cmp     r15d, eax
    jne     .out                                ; more parts to come
    mov     dword [r12 + CONN.blob_on], 0
    mov     eax, [r12 + CONN.blob_type]
    lea     ecx, [rax - 1]
    cmp     ecx, NUM_MT - 2
    ja      .out
    cmp     eax, MT_BLOB_PART
    je      .out
    mov     r9, [rbx + NETEP.deliver]
    test    r9, r9
    jz      .out
    mov     edi, [r12 + CONN.slot]
    mov     esi, eax
    lea     rdx, [r12 + CONN.blob]
    mov     ecx, [r12 + CONN.blob_total]
    call    r9
    jmp     .out
.bad:
    mov     dword [r12 + CONN.blob_on], 0
.out:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; msg_rx(rdi ep, rsi conn, edx type, rcx payload, r8d len, r9d rid or -1 for an unreliable message)
; Unreliable: delivered at once (never a blob part). Reliable: rid == rx_exp is delivered and the buffered
; successors drained, a rid ahead within NET_RWIN is buffered at rid % NET_RWIN, anything else is a duplicate.
msg_rx:
    cmp     r9d, -1
    jne     .reliable
    cmp     edx, MT_BLOB_PART
    je      .drop
    jmp     deliver_msg
.drop:
    ret
.reliable:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13d, edx
    mov     r14, rcx
    mov     r15d, r8d
    mov     eax, r9d
    sub     eax, [r12 + CONN.rx_exp]
    and     eax, 0xFFFF
    jz      .inorder
    cmp     eax, NET_RWIN
    jae     .out
    and     r9d, NET_RWIN - 1
    cmp     byte [r12 + r9 + CONN.rw_valid], 0
    jne     .out
    imul    eax, r9d, RW_size
    lea     rdi, [r12 + rax + CONN.rw]
    mov     [rdi + RW.len], r15w
    mov     [rdi + RW.type], r13b
    mov     byte [r12 + r9 + CONN.rw_valid], 1
    add     rdi, RW.data
    mov     rsi, r14
    mov     ecx, r15d
    rep     movsb
    jmp     .out
.inorder:
    mov     eax, [r12 + CONN.rx_exp]
    inc     eax
    and     eax, 0xFFFF
    mov     [r12 + CONN.rx_exp], eax
    mov     rdi, rbx
    mov     rsi, r12
    mov     edx, r13d
    mov     rcx, r14
    mov     r8d, r15d
    call    deliver_msg
.drain:
    cmp     dword [r12 + CONN.state], CONN_ACTIVE
    jne     .out
    mov     eax, [r12 + CONN.rx_exp]
    and     eax, NET_RWIN - 1
    cmp     byte [r12 + rax + CONN.rw_valid], 0
    je      .out
    mov     byte [r12 + rax + CONN.rw_valid], 0
    mov     ecx, [r12 + CONN.rx_exp]
    inc     ecx
    and     ecx, 0xFFFF
    mov     [r12 + CONN.rx_exp], ecx
    imul    eax, eax, RW_size
    lea     r9, [r12 + rax + CONN.rw]
    movzx   edx, byte [r9 + RW.type]
    movzx   r8d, word [r9 + RW.len]
    lea     rcx, [r9 + RW.data]
    mov     rdi, rbx
    mov     rsi, r12
    call    deliver_msg
    jmp     .drain
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

%define CR_SIZE 0

; conn_rx(rdi ep, rsi conn, rdx pkt, ecx len): a DATA packet of this connection. Duplicate packets (by
; number) are dropped, its ack info is processed, then its messages are parsed and handed on in order.
conn_rx:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14d, ecx
    mov     eax, [rbx + NETEP.now]
    mov     [r12 + CONN.last_rx], eax
    movzx   eax, word [r13 + 8]                 ; seq
    test    eax, eax
    jz      .out                                ; 0 is never sent
    mov     ecx, [r12 + CONN.rx_ack]
    test    ecx, ecx
    jz      .first
    mov     edx, eax
    sub     edx, ecx
    movsx   edx, dx                             ; diff, wrapped to s16
    test    edx, edx
    jz      .out                                ; the newest packet again
    js      .older
    cmp     edx, 32
    ja      .first                              ; everything older fell out of the window
    mov     r8d, [r12 + CONN.rx_bits]
    mov     ecx, edx
    shl     r8, cl                              ; 64-bit shift: a shift by 32 empties the dword
    dec     ecx
    mov     r9d, 1
    shl     r9d, cl
    or      r8d, r9d                            ; the old newest packet becomes bit diff-1
    mov     [r12 + CONN.rx_bits], r8d
    mov     [r12 + CONN.rx_ack], eax
    jmp     .counted
.first:
    mov     dword [r12 + CONN.rx_bits], 0
    mov     [r12 + CONN.rx_ack], eax
    jmp     .counted
.older:
    neg     edx
    cmp     edx, 32
    ja      .out                                ; too old to tell: drop
    lea     ecx, [rdx - 1]
    mov     r9d, 1
    shl     r9d, cl
    test    [r12 + CONN.rx_bits], r9d
    jnz     .out                                ; a duplicate
    or      [r12 + CONN.rx_bits], r9d
.counted:
    movzx   edx, word [r13 + 10]
    mov     ecx, [r13 + 12]
    mov     rdi, rbx
    mov     rsi, r12
    call    conn_ack
    mov     r15d, NET_PKT_HDR
.msg:
    cmp     r15d, r14d
    jae     .out
    mov     eax, r14d
    sub     eax, r15d                           ; bytes left
    cmp     eax, 4
    jb      .out
    movzx   esi, word [r13 + r15 + 2]           ; payload length
    movzx   ecx, byte [r13 + r15 + 1]           ; flags
    mov     r8d, 4
    mov     r9d, -1
    test    cl, 1
    jz      .sized
    cmp     eax, 6
    jb      .out
    mov     r8d, 6
    movzx   r9d, word [r13 + r15 + 4]           ; rid
.sized:
    lea     edx, [rsi + r8]
    cmp     edx, eax
    ja      .out                                ; claims more than the datagram holds
    cmp     esi, NET_MSG_MAX
    ja      .out
    mov     [rsp + CR_SIZE], edx
    movzx   edx, byte [r13 + r15]               ; type
    lea     rcx, [r13 + r15]
    add     rcx, r8                             ; payload
    mov     r8d, esi
    mov     rdi, rbx
    mov     rsi, r12
    call    msg_rx
    cmp     dword [r12 + CONN.state], CONN_ACTIVE
    jne     .out                                ; the game dropped the connection meanwhile
    add     r15d, [rsp + CR_SIZE]
    jmp     .msg
.out:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; conn_timeouts(rdi ep): a connection silent for NET_TIMEOUT_MS is reported as NE_TIMEOUT, and one whose peer said
; goodbye while the event queue was full (CONN.bye) as NE_DISCONNECTED. The connection is freed only when its event
; is queued, so a full queue delays the report to a later poll and never loses it.
conn_timeouts:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    xor     r12d, r12d
.loop:
    mov     eax, r12d
    imul    rax, rax, CONN_size
    lea     r13, [rbx + rax + NETEP.conn]
    cmp     dword [r13 + CONN.state], CONN_ACTIVE
    jne     .next
    mov     esi, NE_DISCONNECTED
    mov     ecx, [r13 + CONN.bye]
    dec     ecx                                 ; the goodbye's reason, or -1 when none is waiting
    jns     .report
    mov     eax, [rbx + NETEP.now]
    sub     eax, [r13 + CONN.last_rx]
    cmp     eax, NET_TIMEOUT_MS
    jb      .next
    mov     esi, NE_TIMEOUT
    xor     ecx, ecx
.report:
    mov     rdi, rbx
    mov     edx, r12d
    mov     r8d, [r13 + CONN.relay]
    call    ev_post
    test    rax, rax
    jz      .next                               ; the queue is full: the connection stays, the next poll tries again
    mov     dword [r13 + CONN.state], CONN_FREE
    lea     rsi, [r13 + CONN.addr]
    call    ev_set_addr
.next:
    inc     r12d
    cmp     r12d, NET_MAX_PEERS
    jb      .loop
    pop     r13
    pop     r12
    pop     rbx
    ret

; =====================================================================================================
; connection setup: host side
; =====================================================================================================

; recent_find(rdi ep, esi nonce) -> rax the RC entry of that request if it is younger than RECENT_TTL_MS, else 0.
; A joiner sends its CONNECT to several candidate addresses (public, LAN, relay); the copies share one nonce
; and are one request.
recent_find:
    lea     rax, [rdi + NETEP.recent]
    mov     r8d, RECENT_N
.loop:
    cmp     dword [rax + RC.used], 0
    je      .next
    cmp     [rax + RC.nonce], esi
    jne     .next
    mov     r9d, [rdi + NETEP.now]
    sub     r9d, [rax + RC.t]
    cmp     r9d, RECENT_TTL_MS
    jb      .found
.next:
    add     rax, RC_size
    dec     r8d
    jnz     .loop
    xor     eax, eax
.found:
    ret

; recent_add(rdi ep, esi nonce) -> rax a new RC entry (reason 0 = pending; the oldest entry is replaced)
recent_add:
    mov     eax, [rdi + NETEP.recent_pos]
    inc     dword [rdi + NETEP.recent_pos]
    and     eax, RECENT_N - 1
    imul    eax, eax, RC_size
    lea     rax, [rdi + rax + NETEP.recent]
    mov     dword [rax + RC.reason], 0
    mov     [rax + RC.nonce], esi
    mov     ecx, [rdi + NETEP.now]
    mov     [rax + RC.t], ecx
    mov     dword [rax + RC.used], 1
    ret

; handle_connect(rdi ep, rsi pkt, edx len, rcx src NADDR*, r8d relay): a CONNECT {nonce, name[17]} (host).
; Copies of a request that already has a connection are answered with ACCEPT again (ours may have been
; lost), by whichever candidate address they came; if the copy came through the relay and the connection
; (made from a direct copy) never heard from its guest, the guest cannot hear us direct: the connection moves
; to the relay. A request seen lately is ignored while pending and gets its DENY again if it was denied.
; Anything else is a new NE_CONNECT_REQ.
handle_connect:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rcx
    mov     r14d, r8d
    cmp     dword [rbx + NETEP.is_guest], 0
    jne     .out                                ; a guest does not host
    cmp     edx, NET_PKT_HDR + 4 + 17
    jb      .out
    mov     r15d, [r12 + 16]                    ; nonce
    xor     ecx, ecx
.scan:
    mov     eax, ecx
    imul    rax, rax, CONN_size
    lea     r9, [rbx + rax + NETEP.conn]
    cmp     dword [r9 + CONN.state], CONN_ACTIVE
    jne     .snext
    cmp     [r9 + CONN.nonce], r15d
    je      .have
.snext:
    inc     ecx
    cmp     ecx, NET_MAX_PEERS
    jb      .scan
    jmp     .recent
.have:
    test    r14d, r14d
    jz      .again
    cmp     dword [r9 + CONN.relay], 0
    jne     .again
    cmp     dword [r9 + CONN.rx_ack], 0
    jne     .again                              ; it has been heard: the direct path works
    mov     dword [r9 + CONN.relay], 1
    mov     eax, [r13 + NADDR.ip]
    mov     [r9 + CONN.addr + NADDR.ip], eax
    movzx   eax, word [r13 + NADDR.port]
    mov     [r9 + CONN.addr + NADDR.port], ax
.again:
    mov     rdi, rbx
    mov     rsi, r9
    call    send_accept
    jmp     .out
.recent:
    mov     rdi, rbx
    mov     esi, r15d
    call    recent_find
    test    rax, rax
    jz      .new
    mov     r8d, [rax + RC.reason]
    test    r8d, r8d
    jz      .out                                ; still waiting for the game's answer
    mov     rdi, rbx
    mov     rsi, r13
    mov     edx, r14d
    mov     ecx, r15d
    call    send_deny
    jmp     .out
.new:
    mov     eax, [rbx + NETEP.ev_tail]
    sub     eax, [rbx + NETEP.ev_head]
    cmp     eax, EV_COUNT - NET_MAX_PEERS
    jae     .out                                ; the last NET_MAX_PEERS places are for goodbyes: a flood of CONNECTs
                                                ; cannot take them (the joiner asks again)
    mov     rdi, rbx
    mov     esi, NE_CONNECT_REQ
    xor     edx, edx
    xor     ecx, ecx
    mov     r8d, r14d
    call    ev_post
    test    rax, rax
    jz      .out                                ; queue full: the joiner asks again
    mov     rsi, r13
    call    ev_set_addr
    mov     [rax + NETEVENT.nonce], r15d
    movups  xmm0, [r12 + 20]
    movups  [rax + NETEVENT.name], xmm0         ; 16 name bytes ...
    mov     byte [rax + NETEVENT.name + 16], 0  ; ... and a NUL
    mov     rdi, rbx
    mov     esi, r15d
    call    recent_add
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; reply_badver(rdi ep, rsi pkt, edx len, rcx src, r8d relay): a CONNECT of another protocol version gets
; DENY_VERSION (echoing its nonce) and no event; a guest endpoint stays silent
reply_badver:
    cmp     dword [rdi + NETEP.is_guest], 0
    jne     .ret
    xor     eax, eax
    cmp     edx, NET_PKT_HDR + 4
    jb      .go
    mov     eax, [rsi + 16]
.go:
    mov     rsi, rcx
    mov     edx, r8d
    mov     ecx, eax
    mov     r8d, DENY_VERSION
    jmp     send_deny
.ret:
    ret

; net_ep_accept(rdi ep, esi slot 1..NET_MAX_PEERS-1, rdx NETEVENT* of a NE_CONNECT_REQ): create the connection
; (same address, same relay flag), draw its token and send ACCEPT
net_ep_accept:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13, rdx
    cmp     dword [rbx + NETEP.open], 0
    je      .out
    lea     eax, [r12 - 1]
    cmp     eax, NET_MAX_PEERS - 2
    ja      .out
    mov     rdi, rbx
    call    ep_now
    mov     r15d, eax
    mov     eax, r12d
    imul    rax, rax, CONN_size
    lea     r14, [rbx + rax + NETEP.conn]
    cmp     dword [r14 + CONN.state], CONN_ACTIVE
    jne     .make
    mov     eax, [r13 + NETEVENT.nonce]
    cmp     [r14 + CONN.nonce], eax
    jne     .make                               ; another guest's connection: replaced below
    mov     rdi, rbx                            ; the same request accepted twice: ACCEPT again, keep the connection
    mov     rsi, r14
    call    send_accept
    jmp     .out
.make:
    mov     rdi, r14
    mov     esi, r15d
    call    conn_init
    mov     [r14 + CONN.slot], r12d
    mov     eax, [r13 + NETEVENT.addr + NADDR.ip]
    mov     [r14 + CONN.addr + NADDR.ip], eax
    movzx   eax, word [r13 + NETEVENT.addr + NADDR.port]
    mov     [r14 + CONN.addr + NADDR.port], ax
    movzx   eax, byte [r13 + NETEVENT.relay]
    mov     [r14 + CONN.relay], eax
    mov     eax, [r13 + NETEVENT.nonce]
    mov     [r14 + CONN.nonce], eax
    call    ep_rand32
    mov     [r14 + CONN.token], eax
    mov     rdi, rbx
    mov     rsi, r14
    call    send_accept
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; net_ep_deny(rdi ep, rsi NETEVENT* of a NE_CONNECT_REQ, edx reason DENY_*): send DENY, and remember it so
; that a repeated CONNECT of that request is answered with the same DENY
net_ep_deny:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13d, edx
    cmp     dword [rbx + NETEP.open], 0
    je      .out
    mov     rdi, rbx
    mov     esi, [r12 + NETEVENT.nonce]
    call    recent_find
    test    rax, rax
    jnz     .mark
    mov     rdi, rbx
    mov     esi, [r12 + NETEVENT.nonce]
    call    recent_add
.mark:
    mov     [rax + RC.reason], r13d
    mov     rdi, rbx
    lea     rsi, [r12 + NETEVENT.addr]
    movzx   edx, byte [r12 + NETEVENT.relay]
    mov     ecx, [r12 + NETEVENT.nonce]
    mov     r8d, r13d
    call    send_deny
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; net_ep_drop(rdi ep, esi slot, edx reason): send DISCONNECT three times and free the connection
net_ep_drop:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    cmp     dword [rbx + NETEP.open], 0
    je      .out
    cmp     esi, NET_MAX_PEERS
    jae     .out
    mov     eax, esi
    imul    rax, rax, CONN_size
    lea     r12, [rbx + rax + NETEP.conn]
    cmp     dword [r12 + CONN.state], CONN_ACTIVE
    jne     .out
    mov     r13d, edx
    mov     rdi, rbx
    mov     esi, PK_DISCONNECT
    mov     edx, [r12 + CONN.token]
    call    ctl_begin
    mov     [rax], r13b
    mov     r13d, 3
.send:
    mov     rdi, rbx
    lea     rsi, [r12 + CONN.addr]
    mov     edx, [r12 + CONN.relay]
    mov     ecx, NET_PKT_HDR + 1
    call    send_game
    dec     r13d
    jnz     .send
    mov     dword [r12 + CONN.state], CONN_FREE
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; handle_disconnect(rdi ep, rsi pkt, edx len, rcx src, r8d relay): the peer leaves (NE_DISCONNECTED). When the event
; queue is full the goodbye waits in CONN.bye and conn_timeouts reports it later; a repeated DISCONNECT changes nothing.
handle_disconnect:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13d, edx
    mov     rsi, rcx
    mov     edx, r8d
    mov     ecx, [r12 + 4]
    call    conn_find
    test    rax, rax
    jz      .out
    mov     r15, rax
    cmp     dword [r15 + CONN.bye], 0
    jne     .out
    xor     r14d, r14d                          ; the reason
    cmp     r13d, NET_PKT_HDR + 1
    jb      .have_reason
    movzx   r14d, byte [r12 + 16]
.have_reason:
    mov     rdi, rbx
    mov     esi, NE_DISCONNECTED
    mov     edx, [r15 + CONN.slot]
    mov     ecx, r14d
    mov     r8d, [r15 + CONN.relay]
    call    ev_post
    test    rax, rax
    jnz     .posted
    lea     eax, [r14 + 1]
    mov     [r15 + CONN.bye], eax               ; no room: conn_timeouts delivers it when there is
    jmp     .out
.posted:
    mov     dword [r15 + CONN.state], CONN_FREE
    lea     rsi, [r15 + CONN.addr]
    call    ev_set_addr
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =====================================================================================================
; connection setup: guest side, join state machine
; =====================================================================================================

; join_fail(rdi ep, esi NJE_*)
join_fail:
    mov     dword [rdi + NETEP.join_state], NJ_FAILED
    mov     [rdi + NETEP.join_err], esi
    ret

; handle_accept(rdi ep, rsi pkt, edx len, rcx src, r8d relay): ACCEPT {nonce, slot, max} while joining. The
; first one for our nonce wins whatever address it came from: the connection is locked to that address.
handle_accept:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rcx
    mov     r14d, r8d
    cmp     dword [rbx + NETEP.is_guest], 0
    je      .out
    mov     eax, [rbx + NETEP.join_state]
    cmp     eax, NJ_CONNECT
    je      .state_ok
    cmp     eax, NJ_PUNCH
    je      .state_ok
    cmp     eax, NJ_RELAY
    jne     .out
.state_ok:
    cmp     edx, NET_PKT_HDR + 6
    jb      .out
    mov     eax, [r12 + 16]
    cmp     eax, [rbx + NETEP.join_nonce]
    jne     .out
    cmp     dword [r12 + 4], 0                  ; the token
    je      .out
    movzx   r15d, byte [r12 + 20]               ; our slot
    lea     eax, [r15 - 1]
    cmp     eax, NET_MAX_PEERS - 2
    ja      .out
    lea     rdi, [rbx + NETEP.conn]
    mov     esi, [rbx + NETEP.now]
    call    conn_init
    mov     eax, [r12 + 4]
    mov     [rbx + NETEP.conn + CONN.token], eax
    mov     eax, [r12 + 16]
    mov     [rbx + NETEP.conn + CONN.nonce], eax
    mov     [rbx + NETEP.conn + CONN.relay], r14d
    mov     eax, [r13 + NADDR.ip]
    mov     [rbx + NETEP.conn + CONN.addr + NADDR.ip], eax
    movzx   eax, word [r13 + NADDR.port]
    mov     [rbx + NETEP.conn + CONN.addr + NADDR.port], ax
    mov     dword [rbx + NETEP.join_state], NJ_CONNECTED
    mov     rdi, rbx
    mov     esi, NE_ACCEPTED
    mov     edx, r15d
    xor     ecx, ecx
    mov     r8d, r14d
    call    ev_post
    test    rax, rax
    jz      .out
    mov     rsi, r13
    call    ev_set_addr
    mov     ecx, [r12 + 16]
    mov     [rax + NETEVENT.nonce], ecx
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; handle_deny(rdi ep, rsi pkt, edx len, rcx src, r8d relay): DENY {nonce, reason}. Read whatever the version
; byte says, so a version mismatch can be reported.
handle_deny:
    cmp     dword [rdi + NETEP.is_guest], 0
    je      .ret
    mov     eax, [rdi + NETEP.join_state]
    cmp     eax, NJ_CONNECT
    je      .state_ok
    cmp     eax, NJ_PUNCH
    je      .state_ok
    cmp     eax, NJ_RELAY
    jne     .ret
.state_ok:
    cmp     edx, NET_PKT_HDR + 5
    jb      .ret
    mov     eax, [rsi + 16]
    cmp     eax, [rdi + NETEP.join_nonce]
    jne     .ret
    movzx   eax, byte [rsi + 20]
    mov     esi, NJE_UNREACHABLE
    cmp     eax, DENY_CLOSED
    ja      .fail
    lea     rcx, [deny_err]
    movzx   esi, byte [rcx + rax]
.fail:
    jmp     join_fail
.ret:
    ret

; net_ep_join(rdi ep, rsi NADDR* target or 0, rdx code[6] or 0, rcx name zstr, r8d force_relay)
; By address: rdx = 0, rsi = the host (state NJ_CONNECT). By room code: rdx = the code, rsi = the rendezvous
; server (0 = the default one; state NJ_RV). Progress: net_ep_join_state / net_ep_join_err; NE_ACCEPTED ends it.
net_ep_join:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx
    mov     r15d, r8d
    cmp     dword [rbx + NETEP.open], 0
    jne     .opened
    mov     rdi, rbx
    mov     esi, NJE_SOCKET
    call    join_fail
    jmp     .out
.opened:
    mov     dword [rbx + NETEP.conn + CONN.state], CONN_FREE
    mov     dword [rbx + NETEP.is_guest], 1
    mov     dword [rbx + NETEP.rv_on], 0
    mov     dword [rbx + NETEP.join_err], 0
    mov     [rbx + NETEP.join_force], r15d
    call    ep_rand32
    mov     [rbx + NETEP.join_nonce], eax
    pxor    xmm0, xmm0                          ; the name: up to 16 characters, NUL padded
    movups  [rbx + NETEP.join_name], xmm0
    movups  [rbx + NETEP.join_name + 8], xmm0
    xor     ecx, ecx
.name:
    movzx   eax, byte [r14 + rcx]
    test    eax, eax
    jz      .named
    mov     [rbx + NETEP.join_name + rcx], al
    inc     ecx
    cmp     ecx, NAME_MAX
    jb      .name
.named:
    mov     rdi, rbx
    call    ep_now
    mov     [rbx + NETEP.join_t0], eax
    mov     [rbx + NETEP.join_next], eax
    test    r13, r13
    jz      .direct
    xor     ecx, ecx                            ; the code, upper-cased
.code:
    movzx   eax, byte [r13 + rcx]
    cmp     al, 'a'
    jb      .keep
    cmp     al, 'z'
    ja      .keep
    sub     al, 32
.keep:
    mov     [rbx + NETEP.code + rcx], al
    inc     ecx
    cmp     ecx, 6
    jb      .code
    mov     byte [rbx + NETEP.code + 6], 0
    mov     byte [rbx + NETEP.code + 7], 0
    mov     dword [rbx + NETEP.code_set], 1
    test    r12, r12
    jz      .default_rv
    mov     eax, [r12 + NADDR.ip]
    mov     [rbx + NETEP.rv + NADDR.ip], eax
    movzx   eax, word [r12 + NADDR.port]
    mov     [rbx + NETEP.rv + NADDR.port], ax
    jmp     .rv_set
.default_rv:
    mov     dword [rbx + NETEP.rv + NADDR.ip], RV_DEFAULT_IP
    mov     word [rbx + NETEP.rv + NADDR.port], RV_PORT_BE
.rv_set:
    mov     word [rbx + NETEP.rv + NADDR.pad], 0
    mov     dword [rbx + NETEP.rv_set], 1
    lea     rdi, [rbx + NETEP.rv]
    call    net_local_ip
    mov     [rbx + NETEP.lan + NADDR.ip], eax
    mov     eax, [rbx + NETEP.port]
    rol     ax, 8
    mov     [rbx + NETEP.lan + NADDR.port], ax
    mov     word [rbx + NETEP.lan + NADDR.pad], 0
    mov     dword [rbx + NETEP.join_state], NJ_RV
    jmp     .tick
.direct:
    test    r12, r12
    jnz     .have_target
    mov     rdi, rbx
    mov     esi, NJE_UNREACHABLE
    call    join_fail
    jmp     .out
.have_target:
    mov     eax, [r12 + NADDR.ip]
    mov     [rbx + NETEP.join_target + NADDR.ip], eax
    movzx   eax, word [r12 + NADDR.port]
    mov     [rbx + NETEP.join_target + NADDR.port], ax
    mov     word [rbx + NETEP.join_target + NADDR.pad], 0
    mov     dword [rbx + NETEP.join_state], NJ_CONNECT
.tick:
    mov     rdi, rbx
    call    join_tick
.out:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; net_ep_join_state(rdi ep) -> eax NJ_*
net_ep_join_state:
    mov     eax, [rdi + NETEP.join_state]
    ret

; net_ep_join_err(rdi ep) -> eax NJE_* (0 while no join failed)
net_ep_join_err:
    mov     eax, [rdi + NETEP.join_err]
    ret

; join_tick(rdi ep): the guest's timed sends and give-ups, at ep.now.
;   NJ_CONNECT: CONNECT every 250 ms, NJE_UNREACHABLE after 10 s.
;   NJ_RV: RV_JOIN every 500 ms, NJE_RV_TIMEOUT after 5 s.
;   NJ_PUNCH: CONNECT to the host's public and LAN addresses every 100 ms, NJ_RELAY after 3 s.
;   NJ_RELAY: CONNECT wrapped in RV_RELAY every 250 ms, NJE_UNREACHABLE after 6 s.
join_tick:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12d, [rbx + NETEP.now]
    mov     eax, [rbx + NETEP.join_state]
    cmp     eax, NJ_RV
    je      .rv
    cmp     eax, NJ_PUNCH
    je      .punch
    cmp     eax, NJ_RELAY
    je      .relay
    cmp     eax, NJ_CONNECT
    je      .direct
    jmp     .out
.rv:
    mov     eax, r12d
    sub     eax, [rbx + NETEP.join_t0]
    cmp     eax, RV_JOIN_FAIL_MS
    jae     .f_rv
    mov     eax, r12d
    sub     eax, [rbx + NETEP.join_next]
    js      .out
    mov     rdi, rbx
    call    send_rv_join
    lea     eax, [r12 + RV_JOIN_EVERY_MS]
    mov     [rbx + NETEP.join_next], eax
    jmp     .out
.f_rv:
    mov     rdi, rbx
    mov     esi, NJE_RV_TIMEOUT
    call    join_fail
    jmp     .out
.punch:
    mov     eax, r12d
    sub     eax, [rbx + NETEP.join_t0]
    cmp     eax, JOIN_PUNCH_MS
    jb      .p_go
    mov     dword [rbx + NETEP.join_state], NJ_RELAY
    mov     [rbx + NETEP.join_t0], r12d
    mov     [rbx + NETEP.join_next], r12d
    jmp     .relay
.p_go:
    mov     eax, r12d
    sub     eax, [rbx + NETEP.join_next]
    js      .out
    mov     rdi, rbx
    lea     rsi, [rbx + NETEP.join_pub]
    xor     edx, edx
    call    send_connect
    mov     eax, [rbx + NETEP.join_lan + NADDR.ip]
    test    eax, eax
    jz      .p_next
    cmp     eax, [rbx + NETEP.join_pub + NADDR.ip]
    jne     .p_lan
    movzx   eax, word [rbx + NETEP.join_lan + NADDR.port]
    cmp     ax, [rbx + NETEP.join_pub + NADDR.port]
    je      .p_next                             ; the same address twice
.p_lan:
    mov     rdi, rbx
    lea     rsi, [rbx + NETEP.join_lan]
    xor     edx, edx
    call    send_connect
.p_next:
    lea     eax, [r12 + JOIN_PUNCH_EVERY]
    mov     [rbx + NETEP.join_next], eax
    jmp     .out
.relay:
    mov     eax, r12d
    sub     eax, [rbx + NETEP.join_t0]
    cmp     eax, JOIN_RELAY_MS
    jae     .f_unreach
    mov     eax, r12d
    sub     eax, [rbx + NETEP.join_next]
    js      .out
    mov     rdi, rbx
    lea     rsi, [rbx + NETEP.join_pub]
    mov     edx, 1
    call    send_connect
    lea     eax, [r12 + JOIN_EVERY_MS]
    mov     [rbx + NETEP.join_next], eax
    jmp     .out
.direct:
    mov     eax, r12d
    sub     eax, [rbx + NETEP.join_t0]
    cmp     eax, JOIN_DIRECT_MS
    jae     .f_unreach
    mov     eax, r12d
    sub     eax, [rbx + NETEP.join_next]
    js      .out
    mov     rdi, rbx
    lea     rsi, [rbx + NETEP.join_target]
    xor     edx, edx
    call    send_connect
    lea     eax, [r12 + JOIN_EVERY_MS]
    mov     [rbx + NETEP.join_next], eax
    jmp     .out
.f_unreach:
    mov     rdi, rbx
    mov     esi, NJE_UNREACHABLE
    call    join_fail
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; =====================================================================================================
; rendezvous: host registration, punching, incoming RV packets
; =====================================================================================================

; net_ep_rv_host(rdi ep, rsi NADDR* the rendezvous server): register this host's room; RV_HOST goes out now
; and every 5 s. Call after net_ep_open. net_ep_rv_state / net_ep_room_code report the outcome.
net_ep_rv_host:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    cmp     dword [rbx + NETEP.open], 0
    je      .out
    mov     dword [rbx + NETEP.is_guest], 0
    mov     eax, [r12 + NADDR.ip]
    mov     [rbx + NETEP.rv + NADDR.ip], eax
    movzx   eax, word [r12 + NADDR.port]
    mov     [rbx + NETEP.rv + NADDR.port], ax
    mov     word [rbx + NETEP.rv + NADDR.pad], 0
    mov     dword [rbx + NETEP.rv_set], 1
    mov     dword [rbx + NETEP.rv_on], 1
    mov     dword [rbx + NETEP.rv_state], RVS_PENDING
    mov     dword [rbx + NETEP.code_set], 0
    call    ep_rand32
    mov     [rbx + NETEP.rv_nonce], eax
    mov     rdi, rbx
    call    ep_now
    mov     [rbx + NETEP.rv_t0], eax
    mov     [rbx + NETEP.rv_next], eax
    lea     rdi, [rbx + NETEP.rv]
    call    net_local_ip
    mov     [rbx + NETEP.lan + NADDR.ip], eax
    mov     eax, [rbx + NETEP.port]
    rol     ax, 8
    mov     [rbx + NETEP.lan + NADDR.port], ax
    mov     word [rbx + NETEP.lan + NADDR.pad], 0
    mov     rdi, rbx
    call    rv_tick
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; net_ep_rv_state(rdi ep) -> eax RVS_*
net_ep_rv_state:
    mov     eax, [rdi + NETEP.rv_state]
    ret

; net_ep_room_code(rdi ep, rsi out[7]): the room code and a NUL ("" while there is none)
net_ep_room_code:
    xor     eax, eax
    mov     [rsi], eax
    mov     [rsi + 3], eax
    cmp     dword [rdi + NETEP.code_set], 0
    je      .ret
    mov     eax, [rdi + NETEP.code]
    mov     [rsi], eax
    movzx   eax, word [rdi + NETEP.code + 4]
    mov     [rsi + 4], ax
    mov     byte [rsi + 6], 0
.ret:
    ret

; rv_tick(rdi ep): the host's registration: PENDING turns FAIL after 3 s without a RV_ROOM; RV_HOST every
; 5 s in every state (a late server turns FAIL into OK)
rv_tick:
    cmp     dword [rdi + NETEP.rv_on], 0
    je      .ret
    mov     eax, [rdi + NETEP.now]
    cmp     dword [rdi + NETEP.rv_state], RVS_PENDING
    jne     .send
    mov     edx, eax
    sub     edx, [rdi + NETEP.rv_t0]
    cmp     edx, RV_FAIL_MS
    jb      .send
    mov     dword [rdi + NETEP.rv_state], RVS_FAIL
.send:
    mov     edx, eax
    sub     edx, [rdi + NETEP.rv_next]
    js      .ret
    add     eax, RV_HOST_EVERY_MS
    mov     [rdi + NETEP.rv_next], eax
    jmp     send_rv_host
.ret:
    ret

; punch_add(rdi ep, rsi pub NADDR*, rdx lan NADDR*): the host punches towards a guest for PUNCH_MS: one
; PUNCH to each address now, then every PUNCH_EVERY_MS. A guest already listed is refreshed.
punch_add:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    lea     r14, [rbx + NETEP.punch]
    xor     ecx, ecx
.same:
    cmp     dword [r14 + PU.active], 0
    je      .snext
    mov     eax, [r12 + NADDR.ip]
    cmp     eax, [r14 + PU.pub + NADDR.ip]
    jne     .snext
    movzx   eax, word [r12 + NADDR.port]
    cmp     ax, [r14 + PU.pub + NADDR.port]
    je      .fill
.snext:
    add     r14, PU_size
    inc     ecx
    cmp     ecx, PUNCH_N
    jb      .same
    lea     r14, [rbx + NETEP.punch]
    xor     ecx, ecx
.free:
    cmp     dword [r14 + PU.active], 0
    je      .fill
    add     r14, PU_size
    inc     ecx
    cmp     ecx, PUNCH_N
    jb      .free
    lea     r14, [rbx + NETEP.punch]            ; all busy: the first entry is replaced
.fill:
    mov     eax, [r12 + NADDR.ip]
    mov     [r14 + PU.pub + NADDR.ip], eax
    movzx   eax, word [r12 + NADDR.port]
    mov     [r14 + PU.pub + NADDR.port], ax
    mov     word [r14 + PU.pub + NADDR.pad], 0
    mov     eax, [r13 + NADDR.ip]
    mov     [r14 + PU.lan + NADDR.ip], eax
    movzx   eax, word [r13 + NADDR.port]
    mov     [r14 + PU.lan + NADDR.port], ax
    mov     word [r14 + PU.lan + NADDR.pad], 0
    mov     eax, [r14 + PU.lan + NADDR.ip]
    cmp     eax, [r14 + PU.pub + NADDR.ip]
    jne     .lan_ok
    movzx   eax, word [r14 + PU.lan + NADDR.port]
    cmp     ax, [r14 + PU.pub + NADDR.port]
    jne     .lan_ok
    mov     dword [r14 + PU.lan + NADDR.ip], 0  ; the same address twice: once
.lan_ok:
    mov     eax, [rbx + NETEP.now]
    lea     ecx, [rax + PUNCH_MS]
    mov     [r14 + PU.until], ecx
    lea     ecx, [rax + PUNCH_EVERY_MS]
    mov     [r14 + PU.next], ecx
    mov     dword [r14 + PU.active], 1
    mov     rdi, rbx
    lea     rsi, [r14 + PU.pub]
    call    send_punch
    cmp     dword [r14 + PU.lan + NADDR.ip], 0
    je      .out
    mov     rdi, rbx
    lea     rsi, [r14 + PU.lan]
    call    send_punch
.out:
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; punch_tick(rdi ep): keep the listed punches going, retire the ones past their time
punch_tick:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    lea     r12, [rbx + NETEP.punch]
    xor     r13d, r13d
.loop:
    cmp     dword [r12 + PU.active], 0
    je      .next
    mov     eax, [rbx + NETEP.now]
    mov     edx, eax
    sub     edx, [r12 + PU.until]
    jns     .retire
    sub     eax, [r12 + PU.next]
    js      .next
    mov     rdi, rbx
    lea     rsi, [r12 + PU.pub]
    call    send_punch
    cmp     dword [r12 + PU.lan + NADDR.ip], 0
    je      .again
    mov     rdi, rbx
    lea     rsi, [r12 + PU.lan]
    call    send_punch
.again:
    mov     eax, [rbx + NETEP.now]
    add     eax, PUNCH_EVERY_MS
    mov     [r12 + PU.next], eax
    jmp     .next
.retire:
    mov     dword [r12 + PU.active], 0
.next:
    add     r12, PU_size
    inc     r13d
    cmp     r13d, PUNCH_N
    jb      .loop
    pop     r13
    pop     r12
    pop     rbx
    ret

; ep_ticks(rdi ep): the timed work of the registration, the join and the punches
ep_ticks:
    push    rbx
    mov     rbx, rdi
    call    rv_tick
    mov     rdi, rbx
    call    join_tick
    mov     rdi, rbx
    call    punch_tick
    pop     rbx
    ret

; code_ok(rdi 6 bytes) -> eax 1 when all are ASCII letters or digits
code_ok:
    xor     ecx, ecx
.loop:
    movzx   eax, byte [rdi + rcx]
    cmp     al, '0'
    jb      .bad
    cmp     al, '9'
    jbe     .good
    or      al, 0x20
    cmp     al, 'a'
    jb      .bad
    cmp     al, 'z'
    ja      .bad
.good:
    inc     ecx
    cmp     ecx, 6
    jb      .loop
    mov     eax, 1
    ret
.bad:
    xor     eax, eax
    ret

; code_is_ours(rdi ep, rsi 6 bytes) -> eax 1 when they equal ep.code
code_is_ours:
    mov     eax, [rsi]
    cmp     eax, [rdi + NETEP.code]
    jne     .no
    movzx   eax, word [rsi + 4]
    cmp     ax, [rdi + NETEP.code + 4]
    jne     .no
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; handle_rv(rdi ep, rsi pkt, edx len, rcx src): a RV_MAGIC datagram. Only the rendezvous server's own are
; believed. RV_ROOM (host): the room code. RV_PEER: the host starts punching, a joining guest moves to NJ_PUNCH
; (NJ_RELAY with force_relay). RV_NOROOM: the guest's join fails. RV_RELAY: the wrapped game packet is handled
; as if it came from the address in the wrapper, with the relay flag set.
handle_rv:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13d, edx
    cmp     dword [rbx + NETEP.rv_set], 0
    je      .out
    mov     eax, [rcx + NADDR.ip]
    cmp     eax, [rbx + NETEP.rv + NADDR.ip]
    jne     .out
    movzx   eax, word [rcx + NADDR.port]
    cmp     ax, [rbx + NETEP.rv + NADDR.port]
    jne     .out
    cmp     byte [r12 + 2], RV_VER
    jne     .out
    movzx   eax, byte [r12 + 3]
    cmp     eax, RV_ROOM
    je      .room
    cmp     eax, RV_PEER
    je      .peer
    cmp     eax, RV_NOROOM
    je      .noroom
    cmp     eax, RV_RELAY
    je      .relay
    jmp     .out
.room:
    cmp     r13d, 20
    jb      .out
    cmp     dword [rbx + NETEP.rv_on], 0
    je      .out
    lea     rdi, [r12 + 4]
    call    code_ok
    test    eax, eax
    jz      .out
    mov     eax, [r12 + 4]
    mov     [rbx + NETEP.code], eax
    movzx   eax, word [r12 + 8]
    mov     [rbx + NETEP.code + 4], ax
    mov     word [rbx + NETEP.code + 6], 0
    mov     dword [rbx + NETEP.code_set], 1
    mov     dword [rbx + NETEP.rv_state], RVS_OK
    jmp     .out
.peer:
    cmp     r13d, 36
    jb      .out
    cmp     dword [rbx + NETEP.rv_on], 0
    jne     .host_peer
    cmp     dword [rbx + NETEP.is_guest], 0
    je      .out
    cmp     dword [rbx + NETEP.join_state], NJ_RV
    jne     .out
    mov     rdi, rbx
    lea     rsi, [r12 + 4]
    call    code_is_ours
    test    eax, eax
    jz      .out
    mov     rax, [r12 + 12]                     ; the host's public address (pad is whatever it is)
    mov     [rbx + NETEP.join_pub], rax
    mov     word [rbx + NETEP.join_pub + NADDR.pad], 0
    mov     rax, [r12 + 20]
    mov     [rbx + NETEP.join_lan], rax
    mov     word [rbx + NETEP.join_lan + NADDR.pad], 0
    mov     eax, [rbx + NETEP.now]
    mov     [rbx + NETEP.join_t0], eax
    mov     [rbx + NETEP.join_next], eax
    mov     dword [rbx + NETEP.join_state], NJ_PUNCH
    cmp     dword [rbx + NETEP.join_force], 0
    je      .out
    mov     dword [rbx + NETEP.join_state], NJ_RELAY
    jmp     .out
.host_peer:
    mov     rdi, rbx
    lea     rsi, [r12 + 12]
    lea     rdx, [r12 + 20]
    call    punch_add
    jmp     .out
.noroom:
    cmp     r13d, 12
    jb      .out
    cmp     dword [rbx + NETEP.is_guest], 0
    je      .out
    cmp     dword [rbx + NETEP.join_state], NJ_RV
    jne     .out
    mov     rdi, rbx
    lea     rsi, [r12 + 4]
    call    code_is_ours
    test    eax, eax
    jz      .out
    mov     rdi, rbx
    mov     esi, NJE_NOROOM
    call    join_fail
    jmp     .out
.relay:
    cmp     r13d, RV_RELAY_HDR + NET_PKT_HDR
    jb      .out
    cmp     dword [rbx + NETEP.code_set], 0
    je      .out
    mov     rdi, rbx
    lea     rsi, [r12 + 4]
    call    code_is_ours
    test    eax, eax
    jz      .out
    cmp     word [r12 + RV_RELAY_HDR], NET_MAGIC
    jne     .out
    mov     rdi, rbx
    lea     rsi, [r12 + RV_RELAY_HDR]
    lea     edx, [r13 - RV_RELAY_HDR]
    lea     rcx, [r12 + 12]
    mov     r8d, 1
    call    handle_game
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =====================================================================================================
; incoming datagrams
; =====================================================================================================

; handle_game(rdi ep, rsi pkt, edx len, rcx src NADDR*, r8d relay): a datagram that starts with NET_MAGIC.
; DENY is read whatever its version; every other kind needs NET_VERSION (a CONNECT of another version is
; answered with DENY_VERSION).
handle_game:
    cmp     edx, NET_PKT_HDR
    jb      .drop
    movzx   eax, byte [rsi + 3]
    cmp     eax, PK_DENY
    je      handle_deny
    cmp     byte [rsi + 2], NET_VERSION
    jne     .badver
    cmp     eax, PK_DATA
    je      .data
    cmp     eax, PK_CONNECT
    je      handle_connect
    cmp     eax, PK_ACCEPT
    je      handle_accept
    cmp     eax, PK_DISCONNECT
    je      handle_disconnect
.drop:
    ret
.badver:
    cmp     eax, PK_CONNECT
    jne     .drop
    jmp     reply_badver
.data:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13d, edx
    mov     rsi, rcx
    mov     edx, r8d
    mov     ecx, [r12 + 4]
    call    conn_find
    test    rax, rax
    jz      .done
    mov     rdi, rbx
    mov     rsi, rax
    mov     rdx, r12
    mov     ecx, r13d
    call    conn_rx
.done:
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; handle_datagram(rdi ep, rsi buf, edx len, rcx src NADDR*): route one datagram by its magic
handle_datagram:
    cmp     edx, 4
    jb      .drop
    cmp     edx, MAX_DGRAM
    ja      .drop
    movzx   eax, word [rsi]
    cmp     eax, NET_MAGIC
    je      .game
    cmp     eax, RV_MAGIC
    je      handle_rv
.drop:
    ret
.game:
    xor     r8d, r8d
    jmp     handle_game

; net_ep_poll(rdi ep, rsi deliver_fn): receive until the socket is empty (at most POLL_BUDGET datagrams) and
; run everything they trigger. deliver_fn(edi slot, esi type, rdx payload, ecx len) is called for each
; in-order message; NETEVENTs are queued. Then silent connections time out and the timed state machines run.
net_ep_poll:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 40                             ; [rsp] sockaddr_in, [rsp+16] its length, [rsp+24] src NADDR
    mov     rbx, rdi
    mov     [rbx + NETEP.deliver], rsi
    cmp     dword [rbx + NETEP.open], 0
    je      .out
    mov     rdi, rbx
    call    ep_now
    mov     r12d, POLL_BUDGET
.recv:
    mov     qword [rsp], 0
    mov     qword [rsp + 8], 0
    mov     dword [rsp + 16], 16
    mov     eax, NSYS_RECVFROM
    mov     edi, [rbx + NETEP.fd]
    lea     rsi, [rbx + NETEP.rxbuf]
    mov     edx, 2048
    xor     r10d, r10d
    mov     r8, rsp
    lea     r9, [rsp + 16]
    syscall
    cmp     rax, -EINTR
    je      .recv
    test     rax, rax
    js      .timers                             ; EAGAIN (or any error): the socket is empty
    mov     r13d, eax
    cmp     word [rsp], N_AF_INET
    jne     .next
    mov     eax, [rsp + 4]
    mov     [rsp + 24], eax
    movzx   eax, word [rsp + 2]
    mov     [rsp + 28], eax
    mov     rdi, rbx
    lea     rsi, [rbx + NETEP.rxbuf]
    mov     edx, r13d
    lea     rcx, [rsp + 24]
    call    handle_datagram
.next:
    dec     r12d
    jnz     .recv
.timers:
    mov     rdi, rbx
    call    conn_timeouts
    mov     rdi, rbx
    call    ep_ticks
.out:
    add     rsp, 40
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; =====================================================================================================
; queries and the test seam
; =====================================================================================================

; net_ep_rtt_ms(rdi ep, esi slot) -> eax smoothed round trip of that connection in ms (0 if none)
net_ep_rtt_ms:
    xor     eax, eax
    cmp     esi, NET_MAX_PEERS
    jae     .ret
    mov     eax, esi
    imul    rax, rax, CONN_size
    lea     rcx, [rdi + rax + NETEP.conn]
    xor     eax, eax
    cmp     dword [rcx + CONN.state], CONN_ACTIVE
    jne     .ret
    mov     eax, [rcx + CONN.srtt8]
    shr     eax, 3
.ret:
    ret

; net_ep_is_relay(rdi ep, esi slot) -> eax 1 when that connection runs through the rendezvous server
net_ep_is_relay:
    xor     eax, eax
    cmp     esi, NET_MAX_PEERS
    jae     .ret
    mov     eax, esi
    imul    rax, rax, CONN_size
    lea     rcx, [rdi + rax + NETEP.conn]
    xor     eax, eax
    cmp     dword [rcx + CONN.state], CONN_ACTIVE
    jne     .ret
    mov     eax, [rcx + CONN.relay]
.ret:
    ret

; net_ep_set_test(rdi ep, esi drop_pct, rdx clock_ns_ptr or 0): test seam. Drops that percent of the
; outgoing datagrams (deterministic xorshift seeded 1234) and reads time from *clock_ns_ptr (nanoseconds)
; when it is non-zero.
net_ep_set_test:
    mov     [rdi + NETEP.drop_pct], esi
    mov     [rdi + NETEP.clk], rdx
    mov     dword [rdi + NETEP.rng], 1234
    ret

; net_ep_test_rid(rdi ep, esi slot, edx rid): test seam for the u16 wrap of reliable ids. On an idle connection
; (nothing queued) both the next id to send and the next id expected become rid; call it on both ends.
net_ep_test_rid:
    cmp     esi, NET_MAX_PEERS
    jae     .ret
    mov     eax, esi
    imul    rax, rax, CONN_size
    lea     rcx, [rdi + rax + NETEP.conn]
    cmp     dword [rcx + CONN.state], CONN_ACTIVE
    jne     .ret
    cmp     dword [rcx + CONN.q_count], 0
    jne     .ret
    movzx   edx, dx
    mov     [rcx + CONN.q_head], edx
    mov     [rcx + CONN.rx_exp], edx
.ret:
    ret
