; acrelay.asm - AssemblyCraft rendezvous and relay server (0.11): IPv4 UDP, raw syscalls, no libc.
;
; Built by `make relay`:  nasm -f elf64 -g -F dwarf -Isrc/ server/acrelay.asm -o build/acrelay.o
;                         ld -static -o build/acrelay build/acrelay.o
;
;   acrelay [--port N]          serve UDP 0.0.0.0:N (default RV_PORT 27600); one log line per event on stdout
;   acrelay --selftest          in-process tests with an injected clock and captured output (no sockets);
;                               prints "ok NAME" / "FAIL NAME (check N)" per test, exits 1 when any failed
;   acrelay --probe IP[:PORT]   sends RV_HOST, waits 2 s for the RV_ROOM; prints
;                               "probe ok: room CODE, you are a.b.c.d:p" and exits 0, else "probe failed", exit 1
;
; Wire format, little-endian. Every packet is RV_MAGIC u16, version u8 = 1, kind u8, then (NADDR = ip, port, pad
; as in sockaddr_in: network byte order, pad 0):
;   RV_HOST    host  -> srv, every 5 s   nonce u32, lan NADDR                                       16 bytes
;   RV_ROOM    srv   -> host             code[6], pad[2], pub NADDR (the host as seen from here)    20
;   RV_JOIN    guest -> srv, every 0.5 s code[6], pad[2], nonce u32, lan NADDR                      24
;   RV_PEER    srv   -> host and guest   code[6], pad[2], other_pub, other_lan, self_pub (3 NADDR)   36
;   RV_NOROOM  srv   -> guest            code[6], pad[2]                                            12
;   RV_RELAY   either way                code[6], pad[2], addr NADDR, then one game packet          20 + 1..NET_MTU
;                                        (to the server addr is the destination, from it the source)
; Lengths are checked before a byte of a packet is read: a datagram that is too short, too long, of another
; magic or version, or of a kind clients never send, is dropped without an answer.
;
; Rooms (256): a room is the pair (host endpoint, RV_HOST nonce) and lives 30 s past its last RV_HOST. RV_JOIN
; with the code (any letter case) records the sender as one of the room's 7 guests (a known endpoint is refreshed,
; the oldest is replaced when all 7 are taken), a guest lives 30 s past its last packet. RV_RELAY is forwarded when
; the sender is the room's host or a guest and the destination is the host or a guest other than the sender, at
; most 2 MiB per room per second; it refreshes the sender's guest entry.

%include "common.inc"
default rel

global _start

; ---- limits and wire sizes -------------------------------------------------------------------------------
%define ACR_MAX_ROOMS    256
%define ACR_MAX_GUESTS   7              ; NET_MAX_PEERS - 1
%define ACR_TTL          30             ; seconds: a room without RV_HOST, a guest without any packet
%define ACR_BUDGET       2097152        ; relayed bytes per room per second
%define ACR_BUF          2048           ; datagram buffers
%define ACR_HDR          4              ; RV_MAGIC u16, version u8, kind u8
%define ACR_CODE_LEN     6
%define ACR_RELAY_HDR    20             ; ACR_HDR + code[6] + pad[2] + addr NADDR: the game packet starts here
%define ACR_LEN_HOST     16             ; whole packets: ACR_HDR + payload
%define ACR_LEN_ROOM     20
%define ACR_LEN_JOIN     24
%define ACR_LEN_PEER     36
%define ACR_LEN_NOROOM   12
%define ACR_CAP_SIZE     16384          ; self-test: sent datagrams are appended here instead of leaving
%define ACR_LOG_SIZE     16384          ; self-test: log lines are appended here instead of going to stdout

; ---- syscalls and constants beyond common.inc ------------------------------------------------------------
%define ACR_SYS_POLL         7
%define ACR_SYS_SOCKET       41
%define ACR_SYS_SENDTO       44
%define ACR_SYS_RECVFROM     45
%define ACR_SYS_BIND         49
%define ACR_SYS_SETSOCKOPT   54
%define ACR_SYS_EXIT_GROUP   231
%define ACR_SYS_GETRANDOM    318
%define ACR_AF_INET          2
%define ACR_SOCK_DGRAM       2
%define ACR_SOL_SOCKET       1
%define ACR_SO_RCVTIMEO      20
%define ACR_MSG_DONTWAIT     0x40
%define ACR_POLLIN           1
%define ACR_EAGAIN           11

; An endpoint is held as a "key": a u64 with the ip in the low dword and the port in bits 32..47, both in network
; byte order, bits 48..63 zero. That is exactly the NADDR of the wire (and the sockaddr_in port/addr fields), so a
; key is loaded from or stored to a packet with one 8-byte move and compared with one cmp.

struc ACR_GUEST
    .pub:   resq 1                      ; endpoint key
    .seen:  resd 1                      ; second of its last packet
    .flags: resd 1                      ; bit 0 in use, bit 1 "relay start" already logged
endstruc                                ; 16

struc ACR_ROOM
    .used:     resd 1
    .nonce:    resd 1                   ; of the RV_HOST that opened it
    .code:     resq 1                   ; 6 alphabet characters + 2 zero bytes: the code[6], pad[2] of the wire
    .host_pub: resq 1                   ; endpoint key of the host as seen from here
    .host_lan: resq 1                   ; the host's own idea of its address, passed on to guests
    .seen:     resd 1                   ; second of its last RV_HOST
    .bytes:    resd 1                   ; relayed bytes within .second
    .second:   resd 1                   ; the budget window
    .pad:      resd 1
    .guests:   resb ACR_GUEST_size * ACR_MAX_GUESTS
endstruc                                ; 160

%if (ACR_ROOM_size & 7) != 0
%error "ACR_ROOM_size must stay a multiple of 8: on_host clears a new room with rep stosq"
%endif

; CHK cc, n: test step - carry on when condition cc holds, otherwise the test returns n (its .out unwinds it)
%macro CHK 2
    j%1     %%ok
    mov     eax, %2
    jmp     .out
%%ok:
%endmacro

section .rodata
s_alphabet:     db "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"        ; 32 characters: a random byte & 31 picks one
s_opt_port:     db "--port", 0
s_opt_selftest: db "--selftest", 0
s_opt_probe:    db "--probe", 0
s_usage:        db "usage: acrelay [--port N] | --selftest | --probe IP[:PORT]", 10, 0
s_listening:    db "acrelay: listening on UDP port ", 0
s_err_socket:   db "acrelay: socket() failed", 10, 0
s_err_opt:      db "acrelay: setsockopt(SO_RCVTIMEO) failed", 10, 0
s_err_bind:     db "acrelay: bind() failed (port in use, or not permitted?)", 10, 0
s_err_recv:     db "acrelay: recvfrom() failed", 10, 0
s_open_host:    db "open host", 0
s_join:         db "join", 0
s_relay_start:  db "relay start", 0
s_expired:      db "expired", 0
s_probe_ok:     db "probe ok: room ", 0
s_probe_you:    db ", you are ", 0
s_probe_fail:   db "probe failed", 10, 0
s_ok:           db "ok ", 0
s_fail:         db "FAIL ", 0
s_check:        db " (check ", 0
s_summary:      db "acrelay selftest: ", 0
s_passed:       db " passed, ", 0
s_failed:       db " failed", 10, 0
s_t_rooms:      db "rooms", 0
s_t_expiry:     db "expiry", 0
s_t_relay_auth: db "relay_auth", 0
s_t_join:       db "join", 0
s_t_budget:     db "relay_budget", 0
; scripted random bytes for the self-test: byte & 31 indexes s_alphabet
s_script_collide: db 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0,  1, 1, 1, 1, 1, 1     ; AAAAAA, AAAAAA again, BBBBBB
s_script_abcdef:  db 0, 1, 2, 3, 4, 5                                           ; ABCDEF
t_code_a:       db "AAAAAA", 0, 0
t_code_b:       db "BBBBBB", 0, 0
t_code_abcdef:  db "ABCDEF", 0, 0
t_lower_abcdef: db "abcdef", 0, 0
t_code_none:    db "000000", 0, 0                                               ; '0' is not in the alphabet
align 8
tv_1s:          dq 1, 0                                                         ; timeval for SO_RCVTIMEO
st_table:       dq s_t_rooms, st_rooms
                dq s_t_expiry, st_expiry
                dq s_t_relay_auth, st_relay_auth
                dq s_t_join, st_join
                dq s_t_budget, st_relay_budget
                dq 0, 0

section .data
; expected log lines: the 6 ?s are patched with the code under test (st_patch)
t_exp_open:     db "room ??????", " open host 10.0.0.1:27615", 10, 0
t_exp_join2:    db "room ??????", " join 10.0.0.2:27615", 10, 0
t_exp_expired:  db "room ??????", " expired", 10, 0
t_exp_rs1:      db "room ??????", " relay start 10.0.0.1:27615", 10, 0
t_exp_rs2:      db "room ??????", " relay start 10.0.0.2:27615", 10, 0
t_exp_rs3:      db "room ??????", " relay start 10.0.0.3:27615", 10, 0

section .bss
alignb 8
rooms:          resb ACR_ROOM_size * ACR_MAX_ROOMS
txbuf:          resb ACR_BUF                    ; every reply is built here, then sent
rxbuf:          resb ACR_BUF                    ; the datagram being handled (a relay is forwarded in place)
rx_sa:          resb 16                         ; sockaddr_in of the sender
rx_salen:       resd 1
sock_fd:        resd 1
acr_now:        resd 1                          ; seconds, set by get_now once per step
sweep_last:     resd 1                          ; the second of the last expiry sweep
pfd:            resd 2                          ; struct pollfd for the probe
alignb 8
clock_val:      resq 1                          ; self-test clock, seconds
clock_fake:     resb 1                          ; 1: get_now reads clock_val instead of the system clock
sink_on:        resb 1                          ; 1: send_dgram/log_write capture instead of the network/stdout
alignb 8
rng_script:     resq 1                          ; self-test: 0, or bytes rng_bytes hands out instead of getrandom
rng_script_len: resd 1
rng_script_pos: resd 1
cap_len:        resd 1                          ; captured datagrams: records of dst key u64, len u32, bytes
cap_count:      resd 1
log_len:        resd 1                          ; captured log text, NUL-terminated
alignb 8
cap_buf:        resb ACR_CAP_SIZE
log_buf:        resb ACR_LOG_SIZE
tpkt:           resb ACR_BUF                    ; self-test: the datagram under construction
t_codes:        resq 128
t_code:         resq 1
t_code2:        resq 1
t_tmp:          resq 1
t_k1:           resq 1
t_k2:           resq 1

section .text

; ---------------------------------------------------------------------------------------------------------
; entry
; ---------------------------------------------------------------------------------------------------------

; _start: argc/argv from the initial stack. The last of --selftest / --probe wins; no argument serves on RV_PORT.
_start:
    mov     rbx, [rsp]                  ; argc
    lea     r12, [rsp + 8]              ; argv
    mov     r13d, RV_PORT               ; --port
    xor     r14d, r14d                  ; mode: 0 serve, 1 selftest, 2 probe
    xor     r15d, r15d                  ; --probe target
    mov     ebp, 1                      ; next argv index
.arg:
    cmp     rbp, rbx
    jae     .go
    mov     rdi, [r12 + rbp*8]
    inc     ebp
    lea     rsi, [s_opt_selftest]
    call    str_eq
    test    eax, eax
    jz      .not_selftest
    mov     r14d, 1
    jmp     .arg
.not_selftest:
    mov     rdi, [r12 + rbp*8 - 8]
    lea     rsi, [s_opt_port]
    call    str_eq
    test    eax, eax
    jz      .not_port
    cmp     rbp, rbx
    jae     usage                       ; --port without a value
    mov     rdi, [r12 + rbp*8]
    inc     ebp
    mov     esi, 65535
    call    parse_dec
    test    eax, eax
    jle     usage                       ; -1 (not a number / too big) or 0
    mov     r13d, eax
    jmp     .arg
.not_port:
    mov     rdi, [r12 + rbp*8 - 8]
    lea     rsi, [s_opt_probe]
    call    str_eq
    test    eax, eax
    jz      usage                       ; an argument nobody knows
    cmp     rbp, rbx
    jae     usage                       ; --probe without a target
    mov     r15, [r12 + rbp*8]
    inc     ebp
    mov     r14d, 2
    jmp     .arg
.go:
    cmp     r14d, 1
    je      run_selftest
    cmp     r14d, 2
    je      .probe
    mov     edi, r13d
    jmp     run_server
.probe:
    mov     rdi, r15
    jmp     run_probe

; usage: the synopsis on stderr, exit 2. Never returns.
usage:
    mov     edi, 2
    lea     rsi, [s_usage]
    call    out_fd
    mov     edi, 2
    jmp     exit

; die(rsi msg zstr): the message on stderr, exit 1. Never returns.
die:
    mov     edi, 2
    call    out_fd
    mov     edi, 1
    jmp     exit

; exit(edi code): exit_group. Never returns.
exit:
    mov     eax, ACR_SYS_EXIT_GROUP
    syscall

; out_fd(edi fd, rsi zstr): write(fd, zstr, strlen). A failed write has nowhere to be reported.
out_fd:
    mov     rdx, rsi
.len:
    cmp     byte [rdx], 0
    je      .write
    inc     rdx
    jmp     .len
.write:
    sub     rdx, rsi
    mov     eax, SYS_WRITE
    syscall
    ret

; ---------------------------------------------------------------------------------------------------------
; the server
; ---------------------------------------------------------------------------------------------------------

; run_server(edi port): bind 0.0.0.0:port and handle datagrams for ever. The receive times out after 1 s so that
; expiry (and its log lines) keeps running when the network is quiet. Never returns.
run_server:
    mov     r12d, edi
    mov     eax, ACR_SYS_SOCKET
    mov     edi, ACR_AF_INET
    mov     esi, ACR_SOCK_DGRAM
    xor     edx, edx
    syscall
    test    eax, eax
    js      .e_socket
    mov     [sock_fd], eax
    mov     edi, eax
    mov     esi, ACR_SOL_SOCKET
    mov     edx, ACR_SO_RCVTIMEO
    lea     r10, [tv_1s]
    mov     r8d, 16
    mov     eax, ACR_SYS_SETSOCKOPT
    syscall
    test    eax, eax
    js      .e_opt
    sub     rsp, 16                     ; sockaddr_in { AF_INET, port, INADDR_ANY }
    mov     word [rsp], ACR_AF_INET
    mov     eax, r12d
    rol     ax, 8                       ; host to network byte order
    mov     [rsp + 2], ax
    mov     dword [rsp + 4], 0
    mov     qword [rsp + 8], 0
    mov     edi, [sock_fd]
    mov     rsi, rsp
    mov     edx, 16
    mov     eax, ACR_SYS_BIND
    syscall
    add     rsp, 16
    test    eax, eax
    js      .e_bind
    lea     rdi, [txbuf]                ; "acrelay: listening on UDP port N"
    lea     rsi, [s_listening]
    call    copy_z
    mov     rdi, rax
    mov     esi, r12d
    call    fmt_u32
    mov     byte [rax], 10
    inc     rax
    lea     rdi, [txbuf]
    mov     rsi, rax
    sub     rsi, rdi
    call    log_write
.loop:
    mov     dword [rx_salen], 16
    mov     edi, [sock_fd]
    lea     rsi, [rxbuf]
    mov     edx, ACR_BUF
    xor     r10d, r10d
    lea     r8, [rx_sa]
    lea     r9, [rx_salen]
    mov     eax, ACR_SYS_RECVFROM
    syscall
    cmp     rax, -ACR_EAGAIN            ; the 1 s timeout
    je      .tick
    cmp     rax, -EINTR
    je      .tick
    test    rax, rax
    js      .e_recv
    cmp     word [rx_sa], ACR_AF_INET
    jne     .tick
    mov     edi, [rx_sa + 4]            ; the sender's key: ip | port << 32, both already in network order
    movzx   ecx, word [rx_sa + 2]
    shl     rcx, 32
    or      rdi, rcx
    lea     rsi, [rxbuf]
    mov     rdx, rax
    call    relay_step
    jmp     .loop
.tick:
    xor     edi, edi
    xor     esi, esi
    xor     edx, edx
    call    relay_step
    jmp     .loop
.e_socket:
    lea     rsi, [s_err_socket]
    jmp     die
.e_opt:
    lea     rsi, [s_err_opt]
    jmp     die
.e_bind:
    lea     rsi, [s_err_bind]
    jmp     die
.e_recv:
    lea     rsi, [s_err_recv]
    jmp     die

; relay_step(rdi src_key, rsi buf, rdx len): one step of the server. Reads the clock, drops what expired, then
; handles the datagram in buf that came from src_key. rsi = 0 is a timer tick without a datagram. buf may be
; rewritten (a relay is forwarded in place).
relay_step:
    push    r12
    push    r13
    push    r14
    mov     r12, rdi
    mov     r13, rsi
    mov     r14, rdx
    call    get_now
    mov     edi, eax
    call    sweep
    test    r13, r13
    jz      .ret
    cmp     r14, ACR_HDR
    jb      .ret
    cmp     word [r13], RV_MAGIC
    jne     .ret
    cmp     byte [r13 + 2], 1
    jne     .ret
    movzx   eax, byte [r13 + 3]
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    cmp     eax, RV_HOST
    jne     .not_host
    call    on_host
    jmp     .ret
.not_host:
    cmp     eax, RV_JOIN
    jne     .not_join
    call    on_join
    jmp     .ret
.not_join:
    cmp     eax, RV_RELAY
    jne     .ret
    call    on_relay
.ret:
    pop     r14
    pop     r13
    pop     r12
    ret

; on_host(rdi src, rsi buf, rdx len): RV_HOST nonce u32, lan NADDR. The pair (src, nonce) names a room: a repeat
; refreshes it, anything else opens a new room under a new unique code (nothing when the 256 slots are taken or
; no random bytes can be had). Every RV_HOST that is accepted is answered with RV_ROOM, so a host sees the
; answer to a late retry as well.
on_host:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    cmp     rdx, ACR_LEN_HOST
    jb      .ret
    mov     r12, rdi                    ; src
    mov     r13, rsi                    ; packet
    mov     ebx, [r13 + 4]              ; nonce
    lea     rdi, [r13 + 8]
    call    key_load
    mov     r14, rax                    ; the host's lan endpoint
    lea     r15, [rooms]
    mov     ecx, ACR_MAX_ROOMS
.find:
    cmp     dword [r15 + ACR_ROOM.used], 0
    je      .find_next
    cmp     [r15 + ACR_ROOM.host_pub], r12
    jne     .find_next
    cmp     [r15 + ACR_ROOM.nonce], ebx
    je      .refresh
.find_next:
    add     r15, ACR_ROOM_size
    dec     ecx
    jnz     .find
    lea     r15, [rooms]                ; a new room in the first free slot
    mov     ecx, ACR_MAX_ROOMS
.free:
    cmp     dword [r15 + ACR_ROOM.used], 0
    je      .open
    add     r15, ACR_ROOM_size
    dec     ecx
    jnz     .free
    jmp     .ret                        ; table full: no room, no answer
.open:
    mov     rdi, r15
    xor     eax, eax
    mov     ecx, ACR_ROOM_size / 8
    rep stosq
    lea     rdi, [r15 + ACR_ROOM.code]
    call    gen_code
    test    eax, eax
    jz      .ret
    mov     dword [r15 + ACR_ROOM.used], 1
    mov     [r15 + ACR_ROOM.nonce], ebx
    mov     [r15 + ACR_ROOM.host_pub], r12
    mov     rdi, r15
    lea     rsi, [s_open_host]
    mov     rdx, r12
    call    log_room
.refresh:
    mov     eax, [acr_now]
    mov     [r15 + ACR_ROOM.seen], eax
    mov     [r15 + ACR_ROOM.host_lan], r14
    mov     esi, RV_ROOM
    call    tx_begin
    mov     rcx, [r15 + ACR_ROOM.code]
    mov     [rax + 4], rcx              ; code[6], pad[2]
    mov     [rax + 12], r12             ; pub: the host as we see it
    mov     rdi, r12
    mov     rsi, rax
    mov     edx, ACR_LEN_ROOM
    call    send_dgram
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; on_join(rdi src, rsi buf, rdx len): RV_JOIN code[6], pad[2], nonce u32, lan NADDR. A known room (code in any letter
; case) records the sender as a guest and RV_PEER goes to both sides, each told about the other; an unknown code
; gets RV_NOROOM with the code as it came.
on_join:
    push    rbx
    push    r12
    push    r13
    push    r14
    cmp     rdx, ACR_LEN_JOIN
    jb      .ret
    mov     r12, rdi                    ; the guest's endpoint
    mov     r13, rsi                    ; packet
    lea     rdi, [r13 + 4]
    call    code_norm
    mov     rdi, rax
    call    room_find
    test    rax, rax
    jnz     .found
    mov     esi, RV_NOROOM
    call    tx_begin
    mov     ecx, [r13 + 4]
    mov     [rax + 4], ecx
    movzx   ecx, word [r13 + 8]
    mov     [rax + 8], cx
    mov     word [rax + 10], 0
    mov     rdi, r12
    mov     rsi, rax
    mov     edx, ACR_LEN_NOROOM
    call    send_dgram
    jmp     .ret
.found:
    mov     rbx, rax                    ; the room
    mov     rdi, rbx
    mov     rsi, r12
    call    guest_record
    mov     rdi, rbx
    lea     rsi, [s_join]
    mov     rdx, r12
    call    log_room
    lea     rdi, [r13 + 16]
    call    key_load
    mov     r14, rax                    ; the guest's lan endpoint
    mov     esi, RV_PEER                ; to the guest: the host is the other side
    call    tx_begin
    mov     rcx, [rbx + ACR_ROOM.code]
    mov     [rax + 4], rcx
    mov     rcx, [rbx + ACR_ROOM.host_pub]
    mov     [rax + 12], rcx             ; other_pub
    mov     rcx, [rbx + ACR_ROOM.host_lan]
    mov     [rax + 20], rcx             ; other_lan
    mov     [rax + 28], r12             ; self_pub
    mov     rdi, r12
    mov     rsi, rax
    mov     edx, ACR_LEN_PEER
    call    send_dgram
    mov     esi, RV_PEER                ; to the host: the guest is the other side
    call    tx_begin
    mov     rcx, [rbx + ACR_ROOM.code]
    mov     [rax + 4], rcx
    mov     [rax + 12], r12             ; other_pub
    mov     [rax + 20], r14             ; other_lan
    mov     rcx, [rbx + ACR_ROOM.host_pub]
    mov     [rax + 28], rcx             ; self_pub
    mov     rdi, rcx
    mov     rsi, rax
    mov     edx, ACR_LEN_PEER
    call    send_dgram
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; on_relay(rdi src, rsi buf, rdx len): RV_RELAY code[6], pad[2], addr NADDR, game packet. Forwarded to addr with addr
; replaced by the sender when: the room exists; the sender is its host or a guest; the destination is its host or
; a guest and not the sender; the room has budget left in this second. A guest sender is refreshed, and logged
; ("relay start") the first time it relays after joining. buf is rewritten in place.
on_relay:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp
    cmp     rdx, ACR_RELAY_HDR + 1      ; at least one byte of game packet
    jb      .ret
    cmp     rdx, ACR_RELAY_HDR + NET_MTU
    ja      .ret
    mov     r12, rdi                    ; sender
    mov     r13, rsi                    ; datagram
    mov     r14, rdx                    ; its length
    lea     rdi, [r13 + 4]
    call    code_norm
    mov     rdi, rax
    call    room_find
    test    rax, rax
    jz      .ret
    mov     rbx, rax                    ; the room
    xor     r15d, r15d                  ; the sender's guest entry, 0 when it is the host
    cmp     r12, [rbx + ACR_ROOM.host_pub]
    je      .sender_ok
    mov     rdi, rbx
    mov     rsi, r12
    call    guest_find
    test    rax, rax
    jz      .ret                        ; a stranger
    mov     r15, rax
.sender_ok:
    lea     rdi, [r13 + 12]
    call    key_load
    mov     rbp, rax                    ; the destination
    cmp     rbp, r12
    je      .ret                        ; to itself
    cmp     rbp, [rbx + ACR_ROOM.host_pub]
    je      .dest_ok
    mov     rdi, rbx
    mov     rsi, rbp
    call    guest_find
    test    rax, rax
    jz      .ret                        ; not a member of the room
.dest_ok:
    mov     eax, [acr_now]
    cmp     eax, [rbx + ACR_ROOM.second]
    je      .window
    mov     [rbx + ACR_ROOM.second], eax
    mov     dword [rbx + ACR_ROOM.bytes], 0
.window:
    mov     eax, [rbx + ACR_ROOM.bytes]
    add     eax, r14d
    cmp     eax, ACR_BUDGET
    ja      .ret                        ; over this second's budget
    mov     [rbx + ACR_ROOM.bytes], eax
    test    r15, r15
    jz      .forward
    mov     eax, [acr_now]
    mov     [r15 + ACR_GUEST.seen], eax
    test    dword [r15 + ACR_GUEST.flags], 2
    jnz     .forward
    or      dword [r15 + ACR_GUEST.flags], 2
    mov     rdi, rbx
    lea     rsi, [s_relay_start]
    mov     rdx, r12
    call    log_room
.forward:
    mov     [r13 + 12], r12             ; addr: from now on the source
    mov     rdi, rbp
    mov     rsi, r13
    mov     rdx, r14
    call    send_dgram
.ret:
    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; sweep(edi now): frees the rooms whose last RV_HOST is ACR_TTL seconds old (one log line each) and the guests
; whose last packet is. Runs once per second at most: expiry can only change when the second does.
sweep:
    cmp     edi, [sweep_last]
    je      .quiet
    push    rbx
    push    r12
    push    r13
    mov     [sweep_last], edi
    mov     r13d, edi
    lea     rbx, [rooms]
    mov     r12d, ACR_MAX_ROOMS
.room:
    cmp     dword [rbx + ACR_ROOM.used], 0
    je      .next
    mov     eax, r13d
    sub     eax, [rbx + ACR_ROOM.seen]
    cmp     eax, ACR_TTL
    jae     .gone
    lea     rdx, [rbx + ACR_ROOM.guests]
    mov     ecx, ACR_MAX_GUESTS
.guest:
    test    dword [rdx + ACR_GUEST.flags], 1
    jz      .guest_next
    mov     eax, r13d
    sub     eax, [rdx + ACR_GUEST.seen]
    cmp     eax, ACR_TTL
    jb      .guest_next
    mov     dword [rdx + ACR_GUEST.flags], 0
.guest_next:
    add     rdx, ACR_GUEST_size
    dec     ecx
    jnz     .guest
    jmp     .next
.gone:
    mov     rdi, rbx
    lea     rsi, [s_expired]
    xor     edx, edx
    call    log_room
    mov     dword [rbx + ACR_ROOM.used], 0
.next:
    add     rbx, ACR_ROOM_size
    dec     r12d
    jnz     .room
    pop     r13
    pop     r12
    pop     rbx
.quiet:
    ret

; room_find(rdi code) -> rax room or 0. code is the normalised qword (6 upper-case characters + 2 zero bytes).
room_find:
    lea     rax, [rooms]
    mov     ecx, ACR_MAX_ROOMS
.l:
    cmp     dword [rax + ACR_ROOM.used], 0
    je      .next
    cmp     rdi, [rax + ACR_ROOM.code]
    je      .ret
.next:
    add     rax, ACR_ROOM_size
    dec     ecx
    jnz     .l
    xor     eax, eax
.ret:
    ret

; code_norm(rdi ptr) -> rax: the 6 code bytes at ptr as a qword, upper-cased, the top two bytes zero.
code_norm:
    sub     rsp, 8
    mov     qword [rsp], 0
    xor     ecx, ecx
.l:
    movzx   eax, byte [rdi + rcx]
    lea     edx, [rax - 'a']
    cmp     edx, 'z' - 'a'
    ja      .store
    sub     eax, 32
.store:
    mov     [rsp + rcx], al
    inc     ecx
    cmp     ecx, ACR_CODE_LEN
    jb      .l
    mov     rax, [rsp]
    add     rsp, 8
    ret

; gen_code(rdi out) -> eax 1 stored / 0 failed: a random code (6 characters of s_alphabet, 2 zero bytes) that no
; live room has; a collision draws again, up to 16 times. 0 when no random bytes can be had.
gen_code:
    push    rbx
    push    r12
    sub     rsp, 16
    mov     r12, rdi
    mov     ebx, 16
.try:
    mov     qword [rsp], 0
    mov     rdi, rsp
    mov     esi, ACR_CODE_LEN
    call    rng_bytes
    test    eax, eax
    jz      .fail
    lea     rdx, [s_alphabet]
    xor     ecx, ecx
.map:
    movzx   eax, byte [rsp + rcx]
    and     eax, 31
    mov     al, [rdx + rax]
    mov     [rsp + rcx], al
    inc     ecx
    cmp     ecx, ACR_CODE_LEN
    jb      .map
    mov     rdi, [rsp]
    call    room_find
    test    rax, rax
    jz      .ok
    dec     ebx
    jnz     .try
.fail:
    xor     eax, eax
    jmp     .out
.ok:
    mov     rax, [rsp]
    mov     [r12], rax
    mov     eax, 1
.out:
    add     rsp, 16
    pop     r12
    pop     rbx
    ret

; rng_bytes(rdi buf, esi n) -> eax 1 filled / 0 failed. getrandom(2); the self-test points rng_script at fixed bytes.
rng_bytes:
    cmp     qword [rng_script], 0
    jne     .script
    mov     esi, esi                    ; n, zero-extended
.again:
    xor     edx, edx
    mov     eax, ACR_SYS_GETRANDOM
    syscall
    cmp     rax, -EINTR
    je      .again
    cmp     rax, rsi                    ; an error or a short read
    jne     .bad
    mov     eax, 1
    ret
.script:
    mov     eax, [rng_script_pos]
    lea     edx, [rax + rsi]
    cmp     edx, [rng_script_len]
    ja      .bad                        ; the script ran dry
    mov     [rng_script_pos], edx
    mov     rdx, [rng_script]
    lea     rdx, [rdx + rax]
    mov     ecx, esi
    mov     rsi, rdx
    rep movsb
    mov     eax, 1
    ret
.bad:
    xor     eax, eax
    ret

; guest_record(rdi room, rsi key) -> rax guest entry: the guest with this endpoint refreshed, else a free entry,
; else the entry of the oldest guest (all 7 in use). Its "relay start" flag is cleared: a join starts a new session.
guest_record:
    lea     rdx, [rdi + ACR_ROOM.guests]
    mov     ecx, ACR_MAX_GUESTS
    mov     r11d, [acr_now]
    xor     r8d, r8d                    ; first free entry
    xor     r9d, r9d                    ; oldest entry in use
    xor     r10d, r10d                  ; its age
.scan:
    test    dword [rdx + ACR_GUEST.flags], 1
    jz      .free
    cmp     [rdx + ACR_GUEST.pub], rsi
    je      .refresh
    mov     eax, r11d
    sub     eax, [rdx + ACR_GUEST.seen]
    test    r9, r9
    jz      .older
    cmp     eax, r10d
    jbe     .scan_next
.older:
    mov     r9, rdx
    mov     r10d, eax
    jmp     .scan_next
.free:
    test    r8, r8
    jnz     .scan_next
    mov     r8, rdx
.scan_next:
    add     rdx, ACR_GUEST_size
    dec     ecx
    jnz     .scan
    mov     rdx, r8
    test    rdx, rdx
    jnz     .fill
    mov     rdx, r9                     ; all in use: the oldest gives way
.fill:
    mov     [rdx + ACR_GUEST.pub], rsi
.refresh:
    mov     [rdx + ACR_GUEST.seen], r11d
    mov     dword [rdx + ACR_GUEST.flags], 1
    mov     rax, rdx
    ret

; guest_find(rdi room, rsi key) -> rax the guest entry with this endpoint, or 0.
guest_find:
    lea     rax, [rdi + ACR_ROOM.guests]
    mov     ecx, ACR_MAX_GUESTS
.l:
    test    dword [rax + ACR_GUEST.flags], 1
    jz      .next
    cmp     [rax + ACR_GUEST.pub], rsi
    je      .ret
.next:
    add     rax, ACR_GUEST_size
    dec     ecx
    jnz     .l
    xor     eax, eax
.ret:
    ret

; key_load(rdi NADDR*) -> rax key: ip | port << 32, the pad dropped.
key_load:
    mov     eax, [rdi + NADDR.ip]
    movzx   ecx, word [rdi + NADDR.port]
    shl     rcx, 32
    or      rax, rcx
    ret

; tx_begin(esi kind) -> rax txbuf with the 4-byte header written.
tx_begin:
    lea     rax, [txbuf]
    mov     word [rax], RV_MAGIC
    mov     byte [rax + 2], 1
    mov     [rax + 3], sil
    ret

; get_now() -> eax seconds on CLOCK_MONOTONIC (the self-test clock while clock_fake is set); also kept in acr_now.
get_now:
    cmp     byte [clock_fake], 0
    jne     .fake
    sub     rsp, 24
    mov     eax, SYS_CLOCK_GETTIME
    mov     edi, CLOCK_MONOTONIC
    mov     rsi, rsp
    syscall
    mov     rax, [rsp]
    add     rsp, 24
    jmp     .store
.fake:
    mov     rax, [clock_val]
.store:
    mov     [acr_now], eax
    ret

; send_dgram(rdi dst_key, rsi buf, rdx len): sendto the endpoint. A failed send is a dropped packet, as on any
; UDP path. While sink_on is set the datagram is appended to cap_buf instead (dst key u64, len u32, bytes).
send_dgram:
    cmp     byte [sink_on], 0
    jne     .sink
    mov     rax, rdi
    mov     edi, [sock_fd]
    sub     rsp, 16                     ; sockaddr_in
    mov     word [rsp], ACR_AF_INET
    mov     r8, rax
    shr     r8, 32
    mov     [rsp + 2], r8w
    mov     [rsp + 4], eax
    mov     qword [rsp + 8], 0
    xor     r10d, r10d
    mov     r8, rsp
    mov     r9d, 16
    mov     eax, ACR_SYS_SENDTO
    syscall
    add     rsp, 16
    ret
.sink:
    mov     eax, [cap_len]
    lea     rcx, [rdx + rax + 12]
    cmp     rcx, ACR_CAP_SIZE
    ja      .full                       ; (the tests send a few small datagrams between resets)
    mov     [cap_len], ecx
    inc     dword [cap_count]
    lea     r8, [cap_buf]
    add     r8, rax
    mov     [r8], rdi
    mov     [r8 + 8], edx
    lea     rdi, [r8 + 12]
    mov     rcx, rdx
    rep movsb
.full:
    ret

; log_write(rdi buf, rsi len): the line to stdout, or appended to log_buf (NUL-terminated) while sink_on is set.
log_write:
    cmp     byte [sink_on], 0
    jne     .sink
    mov     rdx, rsi
    mov     rsi, rdi
    mov     edi, 1
    mov     eax, SYS_WRITE
    syscall
    ret
.sink:
    mov     eax, [log_len]
    lea     rdx, [rax + rsi]
    cmp     rdx, ACR_LOG_SIZE - 1
    ja      .full
    mov     [log_len], edx
    lea     rdx, [log_buf]
    add     rdx, rax
    mov     rcx, rsi
    mov     rsi, rdi
    mov     rdi, rdx
    rep movsb
    mov     byte [rdi], 0
.full:
    ret

; log_room(rdi room, rsi text zstr, rdx key or 0): the line "room CODE text[ ip:port]\n".
log_room:
    push    rbx
    push    r12
    push    r13
    sub     rsp, 112
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     dword [rsp], 'room'
    mov     byte [rsp + 4], ' '
    mov     rax, [rbx + ACR_ROOM.code]
    mov     [rsp + 5], eax
    shr     rax, 32
    mov     [rsp + 9], ax
    mov     byte [rsp + 11], ' '
    lea     rdi, [rsp + 12]
    mov     rsi, r12
    call    copy_z
    test    r13, r13
    jz      .nl
    mov     byte [rax], ' '
    lea     rdi, [rax + 1]
    mov     rsi, r13
    call    fmt_endpoint
.nl:
    mov     byte [rax], 10
    inc     rax
    mov     rdi, rsp
    mov     rsi, rax
    sub     rsi, rdi
    call    log_write
    add     rsp, 112
    pop     r13
    pop     r12
    pop     rbx
    ret

; copy_z(rdi dst, rsi zstr) -> rax end of the copy (the NUL is not written).
copy_z:
.l:
    mov     al, [rsi]
    test    al, al
    jz      .done
    mov     [rdi], al
    inc     rdi
    inc     rsi
    jmp     .l
.done:
    mov     rax, rdi
    ret

; fmt_u32(rdi buf, esi value) -> rax end (decimal, no NUL). Clobbers rcx, rdx, rsi, r8.
fmt_u32:
    sub     rsp, 16
    mov     eax, esi
    mov     ecx, 10
    lea     r8, [rsp + 16]
.digit:
    xor     edx, edx
    div     ecx
    add     dl, '0'
    dec     r8
    mov     [r8], dl
    test    eax, eax
    jnz     .digit
    lea     rsi, [rsp + 16]
.copy:
    mov     dl, [r8]
    mov     [rdi], dl
    inc     rdi
    inc     r8
    cmp     r8, rsi
    jb      .copy
    mov     rax, rdi
    add     rsp, 16
    ret

; fmt_endpoint(rdi buf, rsi key) -> rax end (no NUL): "a.b.c.d:port", the port in host byte order.
fmt_endpoint:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
%assign SHIFT 0
%rep 4
    mov     rdi, rbx
    mov     rsi, r12
    shr     rsi, SHIFT
    movzx   esi, sil
    call    fmt_u32
    mov     rbx, rax
%if SHIFT < 24
    mov     byte [rbx], '.'
    inc     rbx
%endif
%assign SHIFT SHIFT + 8
%endrep
    mov     byte [rbx], ':'
    inc     rbx
    mov     rsi, r12
    shr     rsi, 32
    movzx   esi, si
    rol     si, 8
    mov     rdi, rbx
    call    fmt_u32
    pop     r12
    pop     rbx
    ret

; str_eq(rdi a, rsi b) -> eax 1 when the strings are equal.
str_eq:
.l:
    mov     al, [rdi]
    cmp     al, [rsi]
    jne     .ne
    test    al, al
    jz      .eq
    inc     rdi
    inc     rsi
    jmp     .l
.eq:
    mov     eax, 1
    ret
.ne:
    xor     eax, eax
    ret

; parse_dec(rdi zstr, esi max) -> eax value, or -1 when the string is empty, has a non-digit, or exceeds max.
; Leaves rdi at the end of the digits read.
parse_dec:
    xor     eax, eax
    xor     ecx, ecx
.d:
    movzx   edx, byte [rdi]
    sub     edx, '0'
    cmp     edx, 9
    ja      .end
    imul    eax, eax, 10
    add     eax, edx
    cmp     eax, esi
    ja      .bad
    inc     ecx
    inc     rdi
    jmp     .d
.end:
    test    ecx, ecx
    jz      .bad
    cmp     byte [rdi], 0
    jne     .bad
    ret
.bad:
    mov     eax, -1
    ret

; parse_addr(rdi zstr "a.b.c.d[:port]", esi default_port) -> rax key, or -1 when it is not one.
parse_addr:
    push    rbx
    push    r12
    mov     r12d, esi
    xor     ebx, ebx                    ; ip, the first octet in the lowest byte
    xor     r8d, r8d                    ; octets read
.octet:
    xor     eax, eax
    xor     ecx, ecx
.digit:
    movzx   edx, byte [rdi]
    sub     edx, '0'
    cmp     edx, 9
    ja      .digits_end
    imul    eax, eax, 10
    add     eax, edx
    cmp     eax, 255
    ja      .bad
    inc     ecx
    inc     rdi
    jmp     .digit
.digits_end:
    test    ecx, ecx
    jz      .bad
    lea     ecx, [r8*8]
    shl     eax, cl
    or      ebx, eax
    inc     r8d
    cmp     r8d, 4
    je      .port
    cmp     byte [rdi], '.'
    jne     .bad
    inc     rdi
    jmp     .octet
.port:
    mov     eax, r12d
    cmp     byte [rdi], 0
    je      .have_port
    cmp     byte [rdi], ':'
    jne     .bad
    inc     rdi
    mov     esi, 65535
    call    parse_dec
    test    eax, eax
    jle     .bad                        ; -1, or port 0
.have_port:
    rol     ax, 8                       ; network byte order
    movzx   eax, ax
    shl     rax, 32
    or      rax, rbx
    jmp     .out
.bad:
    mov     rax, -1
.out:
    pop     r12
    pop     rbx
    ret

; mono_ms() -> rax milliseconds on CLOCK_MONOTONIC.
mono_ms:
    sub     rsp, 24
    mov     eax, SYS_CLOCK_GETTIME
    mov     edi, CLOCK_MONOTONIC
    mov     rsi, rsp
    syscall
    mov     rax, [rsp + 8]
    xor     edx, edx
    mov     ecx, 1000000
    div     rcx
    mov     rcx, [rsp]
    imul    rcx, rcx, 1000
    add     rax, rcx
    add     rsp, 24
    ret

; ---------------------------------------------------------------------------------------------------------
; --probe
; ---------------------------------------------------------------------------------------------------------

; run_probe(rdi target zstr "a.b.c.d[:port]"): sends RV_HOST (random nonce, no lan endpoint) and waits up to 2 s for
; the RV_ROOM that comes back from the target. Prints "probe ok: room CODE, you are a.b.c.d:p" and exits 0, else
; prints "probe failed" and exits 1. A target that is not an address is a usage error. Never returns.
run_probe:
    mov     esi, RV_PORT
    call    parse_addr
    cmp     rax, -1
    je      usage
    mov     r12, rax                    ; the target
    mov     eax, ACR_SYS_SOCKET
    mov     edi, ACR_AF_INET
    mov     esi, ACR_SOCK_DGRAM
    xor     edx, edx
    syscall
    test    eax, eax
    js      .failed
    mov     [sock_fd], eax
    mov     esi, RV_HOST
    call    tx_begin
    mov     rbx, rax
    lea     rdi, [rbx + 4]              ; nonce
    mov     esi, 4
    call    rng_bytes
    test    eax, eax
    jz      .failed
    mov     qword [rbx + 8], 0          ; lan: none
    mov     rdi, r12
    mov     rsi, rbx
    mov     edx, ACR_LEN_HOST
    call    send_dgram
    call    mono_ms
    lea     r13, [rax + 2000]           ; deadline
.wait:
    call    mono_ms
    mov     rdx, r13
    sub     rdx, rax                    ; ms left
    jle     .failed
    mov     eax, [sock_fd]
    mov     [pfd], eax
    mov     dword [pfd + 4], ACR_POLLIN
    lea     rdi, [pfd]
    mov     esi, 1
    mov     eax, ACR_SYS_POLL
    syscall
    cmp     rax, -EINTR
    je      .wait
    test    rax, rax
    jle     .failed                     ; timeout or error
    mov     dword [rx_salen], 16
    mov     edi, [sock_fd]
    lea     rsi, [rxbuf]
    mov     edx, ACR_BUF
    mov     r10d, ACR_MSG_DONTWAIT
    lea     r8, [rx_sa]
    lea     r9, [rx_salen]
    mov     eax, ACR_SYS_RECVFROM
    syscall
    test    rax, rax
    js      .wait
    cmp     rax, ACR_LEN_ROOM
    jb      .wait
    cmp     word [rx_sa], ACR_AF_INET
    jne     .wait
    mov     edi, [rx_sa + 4]            ; only the target's own answer counts
    movzx   ecx, word [rx_sa + 2]
    shl     rcx, 32
    or      rdi, rcx
    cmp     rdi, r12
    jne     .wait
    cmp     word [rxbuf], RV_MAGIC
    jne     .wait
    cmp     byte [rxbuf + 2], 1
    jne     .wait
    cmp     byte [rxbuf + 3], RV_ROOM
    jne     .wait
    lea     rdi, [txbuf]
    lea     rsi, [s_probe_ok]
    call    copy_z
    mov     ecx, [rxbuf + 4]            ; code[6]
    mov     [rax], ecx
    movzx   ecx, word [rxbuf + 8]
    mov     [rax + 4], cx
    add     rax, ACR_CODE_LEN
    mov     rdi, rax
    lea     rsi, [s_probe_you]
    call    copy_z
    mov     rbx, rax
    lea     rdi, [rxbuf + 12]           ; pub NADDR
    call    key_load
    mov     rdi, rbx
    mov     rsi, rax
    call    fmt_endpoint
    mov     byte [rax], 10
    mov     byte [rax + 1], 0
    mov     edi, 1
    lea     rsi, [txbuf]
    call    out_fd
    xor     edi, edi
    jmp     exit
.failed:
    mov     edi, 1
    lea     rsi, [s_probe_fail]
    call    out_fd
    mov     edi, 1
    jmp     exit

; ---------------------------------------------------------------------------------------------------------
; --selftest: the server core driven in-process. The clock is clock_val, sent datagrams and log lines are captured
; (sink_on), random bytes can be scripted (rng_script). Each test returns eax 0 = pass, else the number of the
; first failed check.
; ---------------------------------------------------------------------------------------------------------

; run_selftest: runs st_table, one "ok NAME" / "FAIL NAME (check N)" line per test and a summary; exit 0 / 1.
run_selftest:
    xor     ebx, ebx                    ; failed
    xor     r14d, r14d                  ; run
    lea     r12, [st_table]
.next:
    cmp     qword [r12], 0
    je      .done
    call    st_reset
    call    qword [r12 + 8]
    mov     r13d, eax
    mov     byte [sink_on], 0
    inc     r14d
    lea     rdi, [txbuf]
    test    r13d, r13d
    jnz     .fail
    lea     rsi, [s_ok]
    call    copy_z
    mov     rdi, rax
    mov     rsi, [r12]
    call    copy_z
    jmp     .line
.fail:
    inc     ebx
    lea     rsi, [s_fail]
    call    copy_z
    mov     rdi, rax
    mov     rsi, [r12]
    call    copy_z
    mov     rdi, rax
    lea     rsi, [s_check]
    call    copy_z
    mov     rdi, rax
    mov     esi, r13d
    call    fmt_u32
    mov     byte [rax], ')'
    inc     rax
.line:
    mov     byte [rax], 10
    mov     byte [rax + 1], 0
    mov     edi, 1
    lea     rsi, [txbuf]
    call    out_fd
    add     r12, 16
    jmp     .next
.done:
    lea     rdi, [txbuf]
    lea     rsi, [s_summary]
    call    copy_z
    mov     rdi, rax
    mov     esi, r14d
    sub     esi, ebx
    call    fmt_u32
    mov     rdi, rax
    lea     rsi, [s_passed]
    call    copy_z
    mov     rdi, rax
    mov     esi, ebx
    call    fmt_u32
    mov     rdi, rax
    lea     rsi, [s_failed]
    call    copy_z
    mov     byte [rax], 0
    mov     edi, 1
    lea     rsi, [txbuf]
    call    out_fd
    xor     edi, edi
    test    ebx, ebx
    setnz   dil
    jmp     exit

; st_reset: empty server at second 1000, capturing, real random bytes.
st_reset:
    lea     rdi, [rooms]
    mov     ecx, (ACR_ROOM_size * ACR_MAX_ROOMS) / 8
    xor     eax, eax
    rep stosq
    mov     dword [sweep_last], -1
    mov     byte [clock_fake], 1
    mov     qword [clock_val], 1000
    mov     byte [sink_on], 1
    mov     qword [rng_script], 0
    mov     dword [cap_len], 0
    mov     dword [cap_count], 0
    mov     dword [log_len], 0
    mov     byte [log_buf], 0
    ret

; st_ep(edi n) -> rax key of test endpoint n: ip 10.0.(n >> 8).(n & 255), port 27615. Clobbers ecx, edx.
st_ep:
    movzx   eax, dil
    shl     eax, 24
    mov     ecx, edi
    shr     ecx, 8
    movzx   ecx, cl
    shl     ecx, 16
    or      eax, ecx
    or      eax, 10
    mov     edx, 0xDF6B                 ; 27615 in network byte order, read as a little-endian word
    shl     rdx, 32
    or      rax, rdx
    ret

; st_lan(edi n) -> rax key of the lan endpoint test host/guest n announces: 192.168.0.(n & 255), port 27615.
st_lan:
    movzx   eax, dil
    shl     eax, 24
    or      eax, 0xC0 | (0xA8 << 8)
    mov     ecx, 0xDF6B
    shl     rcx, 32
    or      rax, rcx
    ret

; st_code_valid(rdi qword*) -> eax 1 when its 6 characters are all in the alphabet.
st_code_valid:
    xor     r8d, r8d
.char:
    movzx   eax, byte [rdi + r8]
    lea     rsi, [s_alphabet]
    mov     ecx, 32
.scan:
    cmp     al, [rsi]
    je      .found
    inc     rsi
    dec     ecx
    jnz     .scan
    xor     eax, eax
    ret
.found:
    inc     r8d
    cmp     r8d, ACR_CODE_LEN
    jb      .char
    mov     eax, 1
    ret

; st_patch(rdi template, rsi code qword*): the 6 characters of the code into the "??????" of a template line.
st_patch:
    mov     eax, [rsi]
    mov     [rdi + 5], eax
    movzx   eax, word [rsi + 4]
    mov     [rdi + 9], ax
    ret

; st_set_script(rdi bytes, esi len): rng_bytes hands out these bytes (in order) instead of getrandom.
st_set_script:
    mov     [rng_script], rdi
    mov     [rng_script_len], esi
    mov     dword [rng_script_pos], 0
    ret

; st_count_rooms() -> eax rooms in use.
st_count_rooms:
    lea     rdx, [rooms]
    mov     ecx, ACR_MAX_ROOMS
    xor     eax, eax
.l:
    cmp     dword [rdx + ACR_ROOM.used], 0
    je      .next
    inc     eax
.next:
    add     rdx, ACR_ROOM_size
    dec     ecx
    jnz     .l
    ret

; st_count_guests(rdi room) -> eax guests in use.
st_count_guests:
    lea     rdx, [rdi + ACR_ROOM.guests]
    mov     ecx, ACR_MAX_GUESTS
    xor     eax, eax
.l:
    test    dword [rdx + ACR_GUEST.flags], 1
    jz      .next
    inc     eax
.next:
    add     rdx, ACR_GUEST_size
    dec     ecx
    jnz     .l
    ret

; st_room_of(rdi host key) -> rax the room that host opened, or 0.
st_room_of:
    lea     rax, [rooms]
    mov     ecx, ACR_MAX_ROOMS
.l:
    cmp     dword [rax + ACR_ROOM.used], 0
    je      .next
    cmp     [rax + ACR_ROOM.host_pub], rdi
    je      .ret
.next:
    add     rax, ACR_ROOM_size
    dec     ecx
    jnz     .l
    xor     eax, eax
.ret:
    ret

; cap_rec(edi i) -> rax the i-th captured datagram: [rax] dst key, [rax + 8] length, [rax + 12] bytes.
cap_rec:
    lea     rax, [cap_buf]
    test    edi, edi
    jz      .ret
.walk:
    mov     ecx, [rax + 8]
    lea     rax, [rax + rcx + 12]
    dec     edi
    jnz     .walk
.ret:
    ret

; cap_find(rdi dst key) -> rax the first captured datagram sent to that endpoint, or 0.
cap_find:
    lea     rax, [cap_buf]
    mov     ecx, [cap_count]
.l:
    test    ecx, ecx
    jz      .none
    cmp     [rax], rdi
    je      .ret
    mov     edx, [rax + 8]
    lea     rax, [rax + rdx + 12]
    dec     ecx
    jmp     .l
.none:
    xor     eax, eax
.ret:
    ret

; log_has(rdi zstr) -> eax how many times the text occurs in the captured log.
log_has:
    push    rbx
    xor     eax, eax
    lea     rsi, [log_buf]
    mov     r8d, [log_len]
    lea     r9, [rsi + r8]
.pos:
    cmp     rsi, r9
    jae     .done
    mov     rcx, rdi
    mov     rdx, rsi
.cmp:
    mov     bl, [rcx]
    test    bl, bl
    jz      .match
    cmp     rdx, r9
    jae     .skip
    cmp     bl, [rdx]
    jne     .skip
    inc     rcx
    inc     rdx
    jmp     .cmp
.match:
    inc     eax
.skip:
    inc     rsi
    jmp     .pos
.done:
    pop     rbx
    ret

; st_hdr_ok(rdi record, esi kind, edx len) -> eax 0 when the captured datagram has this length, RV_MAGIC, version 1, kind.
st_hdr_ok:
    cmp     [rdi + 8], edx
    jne     .bad
    cmp     word [rdi + 12], RV_MAGIC
    jne     .bad
    cmp     byte [rdi + 14], 1
    jne     .bad
    movzx   eax, byte [rdi + 15]
    cmp     eax, esi
    jne     .bad
    xor     eax, eax
    ret
.bad:
    mov     eax, 1
    ret

; tb_head(esi kind) -> rax tpkt with the 4-byte header written.
tb_head:
    lea     rax, [tpkt]
    mov     word [rax], RV_MAGIC
    mov     byte [rax + 2], 1
    mov     [rax + 3], sil
    ret

; tb_host(edi nonce, rsi lan key): an RV_HOST in tpkt.
tb_host:
    mov     r8d, edi
    mov     r9, rsi
    mov     esi, RV_HOST
    call    tb_head
    mov     [rax + 4], r8d
    mov     [rax + 8], r9
    ret

; tb_join(rdi code ptr, esi nonce, rdx lan key): an RV_JOIN in tpkt, the 6 code bytes as given.
tb_join:
    mov     r8d, esi
    mov     esi, RV_JOIN
    call    tb_head
    mov     ecx, [rdi]
    mov     [rax + 4], ecx
    movzx   ecx, word [rdi + 4]
    mov     [rax + 8], cx
    mov     word [rax + 10], 0
    mov     [rax + 12], r8d
    mov     [rax + 16], rdx
    ret

; tb_relay(rdi code ptr, rsi dest key, edx inner) -> eax packet length: an RV_RELAY in tpkt carrying inner game
; packet bytes, byte i = 7 * i + 3 (mod 256).
tb_relay:
    mov     r8d, edx
    mov     r9, rsi
    mov     esi, RV_RELAY
    call    tb_head
    mov     ecx, [rdi]
    mov     [rax + 4], ecx
    movzx   ecx, word [rdi + 4]
    mov     [rax + 8], cx
    mov     word [rax + 10], 0
    mov     [rax + 12], r9
    xor     ecx, ecx
.fill:
    cmp     ecx, r8d
    jae     .done
    lea     edx, [rcx*8]
    sub     edx, ecx
    add     edx, 3
    mov     [rax + ACR_RELAY_HDR + rcx], dl
    inc     ecx
    jmp     .fill
.done:
    lea     eax, [r8 + ACR_RELAY_HDR]
    ret

; st_send(rdi src key, esi len): hands tpkt (len bytes, from src) to relay_step with the capture emptied.
st_send:
    mov     dword [cap_len], 0
    mov     dword [cap_count], 0
    mov     edx, esi
    lea     rsi, [tpkt]
    jmp     relay_step

; st_tick(edi t): the clock moves to second t and the server takes a step without a datagram.
st_tick:
    mov     [clock_val], rdi
    mov     dword [cap_len], 0
    mov     dword [cap_count], 0
    xor     edi, edi
    xor     esi, esi
    xor     edx, edx
    jmp     relay_step

; st_host(edi n, esi nonce) -> eax datagrams sent back: an RV_HOST from endpoint n (lan = st_lan(n)).
st_host:
    push    rbx
    push    r12
    mov     r12d, edi
    mov     ebx, esi
    mov     edi, r12d
    call    st_lan
    mov     rsi, rax
    mov     edi, ebx
    call    tb_host
    mov     edi, r12d
    call    st_ep
    mov     rdi, rax
    mov     esi, ACR_LEN_HOST
    call    st_send
    mov     eax, [cap_count]
    pop     r12
    pop     rbx
    ret

; st_host_ok(edi n, esi nonce, rdx code_out) -> eax 0 when the RV_HOST from endpoint n was answered by exactly one
; well-formed RV_ROOM to that endpoint (length, kind, zero pad, pub = the endpoint); its code qword is stored at
; code_out. Otherwise the number of the first thing that was wrong.
st_host_ok:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdx
    mov     r12d, edi
    call    st_host
    cmp     eax, 1
    jne     .e1
    xor     edi, edi
    call    cap_rec
    mov     r13, rax
    mov     rdi, r13
    mov     esi, RV_ROOM
    mov     edx, ACR_LEN_ROOM
    call    st_hdr_ok
    test    eax, eax
    jnz     .e2
    mov     edi, r12d
    call    st_ep
    cmp     [r13], rax                  ; sent to the host
    jne     .e3
    cmp     [r13 + 12 + 12], rax        ; pub: the host as seen from the server
    jne     .e4
    cmp     word [r13 + 12 + 10], 0     ; pad
    jne     .e5
    mov     rax, [r13 + 12 + 4]
    mov     [rbx], rax
    xor     eax, eax
    jmp     .out
.e1:
    mov     eax, 1
    jmp     .out
.e2:
    mov     eax, 2
    jmp     .out
.e3:
    mov     eax, 3
    jmp     .out
.e4:
    mov     eax, 4
    jmp     .out
.e5:
    mov     eax, 5
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; st_host_bad(edi variant) -> eax datagrams sent back: an RV_HOST from endpoint 7 broken in one way:
; 0 one byte short, 1 wrong magic, 2 wrong version, 3 a kind servers never take (RV_ROOM), 4 shorter than the header.
st_host_bad:
    push    rbx
    push    r12
    mov     ebx, edi
    mov     edi, 7
    call    st_lan
    mov     rsi, rax
    mov     edi, 7
    call    tb_host
    mov     r12d, ACR_LEN_HOST
    cmp     ebx, 0
    jne     .v1
    mov     r12d, ACR_LEN_HOST - 1
.v1:
    cmp     ebx, 1
    jne     .v2
    mov     word [tpkt], RV_MAGIC ^ 1
.v2:
    cmp     ebx, 2
    jne     .v3
    mov     byte [tpkt + 2], 2
.v3:
    cmp     ebx, 3
    jne     .v4
    mov     byte [tpkt + 3], RV_ROOM
.v4:
    cmp     ebx, 4
    jne     .send
    mov     r12d, ACR_HDR - 1
.send:
    mov     edi, 7
    call    st_ep
    mov     rdi, rax
    mov     esi, r12d
    call    st_send
    mov     eax, [cap_count]
    pop     r12
    pop     rbx
    ret

; st_join_send(edi n, rsi code ptr) -> eax datagrams sent back: an RV_JOIN from endpoint n (lan = st_lan(n),
; nonce n) for the 6 code bytes at code ptr.
st_join_send:
    push    rbx
    push    r12
    mov     r12d, edi
    mov     rbx, rsi
    mov     edi, r12d
    call    st_lan
    mov     rdx, rax
    mov     rdi, rbx
    mov     esi, r12d
    call    tb_join
    mov     edi, r12d
    call    st_ep
    mov     rdi, rax
    mov     esi, ACR_LEN_JOIN
    call    st_send
    mov     eax, [cap_count]
    pop     r12
    pop     rbx
    ret

; st_relay(rdi src key, rsi code ptr, rdx dest key, ecx inner) -> eax datagrams sent back (1 = forwarded): an
; RV_RELAY from src to dest carrying inner game packet bytes.
st_relay:
    push    rbx
    mov     rbx, rdi
    mov     rdi, rsi
    mov     rsi, rdx
    mov     edx, ecx
    call    tb_relay
    mov     rdi, rbx
    mov     esi, eax
    call    st_send
    mov     eax, [cap_count]
    pop     rbx
    ret

; st_fwd_ok(rdi record, rsi dest, rdx sender, ecx inner) -> eax 0 when the captured datagram is an RV_RELAY of the
; right length that was sent to dest, names the sender as its addr, and carries the tb_relay bytes.
st_fwd_ok:
    cmp     [rdi], rsi
    jne     .bad
    lea     r8d, [rcx + ACR_RELAY_HDR]
    cmp     [rdi + 8], r8d
    jne     .bad
    cmp     word [rdi + 12], RV_MAGIC
    jne     .bad
    cmp     byte [rdi + 14], 1
    jne     .bad
    cmp     byte [rdi + 15], RV_RELAY
    jne     .bad
    cmp     [rdi + 12 + 12], rdx
    jne     .bad
    xor     eax, eax
.byte:
    cmp     eax, ecx
    jae     .ok
    lea     r8d, [rax*8]
    sub     r8d, eax
    add     r8d, 3
    cmp     [rdi + 12 + ACR_RELAY_HDR + rax], r8b
    jne     .bad
    inc     eax
    jmp     .byte
.ok:
    xor     eax, eax
    ret
.bad:
    mov     eax, 1
    ret

; --- rooms: codes, refresh, collisions, a full table, malformed packets ---
st_rooms:
    push    rbx
    push    r12
    xor     ebx, ebx                    ; 100 hosts from distinct endpoints: one well-formed RV_ROOM each
.hosts:
    lea     edi, [rbx + 1]
    lea     esi, [rbx + 0x4000]
    lea     rdx, [t_codes]
    lea     rdx, [rdx + rbx*8]
    call    st_host_ok
    test    eax, eax
    CHK     z, 1
    lea     rdi, [t_codes]
    lea     rdi, [rdi + rbx*8]
    call    st_code_valid
    test    eax, eax
    CHK     nz, 2
    inc     ebx
    cmp     ebx, 100
    jb      .hosts
    xor     ebx, ebx                    ; ... and all 100 codes differ
.pair_i:
    lea     r12d, [rbx + 1]
.pair_j:
    cmp     r12d, 100
    jae     .pair_next
    lea     rax, [t_codes]
    mov     rcx, [rax + rbx*8]
    cmp     rcx, [rax + r12*8]
    CHK     ne, 3
    inc     r12d
    jmp     .pair_j
.pair_next:
    inc     ebx
    cmp     ebx, 99
    jb      .pair_i
    lea     rdi, [t_exp_open]           ; the first room is in the log in the documented format
    lea     rsi, [t_codes]
    call    st_patch
    lea     rdi, [t_exp_open]
    call    log_has
    cmp     eax, 1
    CHK     e, 4
    mov     edi, 1                      ; a repeat (same endpoint, same nonce) keeps its code and opens nothing
    mov     esi, 0x4000
    lea     rdx, [t_tmp]
    call    st_host_ok
    test    eax, eax
    CHK     z, 5
    mov     rax, [t_tmp]
    lea     rcx, [t_codes]
    cmp     rax, [rcx]
    CHK     e, 6
    call    st_count_rooms
    cmp     eax, 100
    CHK     e, 7
    mov     edi, 1                      ; the same endpoint with another nonce is another room with another code
    mov     esi, 0x5555
    lea     rdx, [t_tmp]
    call    st_host_ok
    test    eax, eax
    CHK     z, 8
    mov     rax, [t_tmp]
    lea     rcx, [t_codes]
    cmp     rax, [rcx]
    CHK     ne, 9
    call    st_count_rooms
    cmp     eax, 101
    CHK     e, 10
    call    st_reset                    ; a drawn code that is taken is drawn again: AAAAAA, then AAAAAA, then BBBBBB
    lea     rdi, [s_script_collide]
    mov     esi, 18
    call    st_set_script
    mov     edi, 1
    mov     esi, 1
    lea     rdx, [t_tmp]
    call    st_host_ok
    test    eax, eax
    CHK     z, 11
    mov     rax, [t_tmp]
    cmp     rax, [t_code_a]
    CHK     e, 12
    mov     edi, 2
    mov     esi, 2
    lea     rdx, [t_tmp]
    call    st_host_ok
    test    eax, eax
    CHK     z, 13
    mov     rax, [t_tmp]
    cmp     rax, [t_code_b]
    CHK     e, 14
    mov     edi, 3                      ; no random bytes left: no room and no answer
    mov     esi, 3
    call    st_host
    test    eax, eax
    CHK     z, 15
    call    st_count_rooms
    cmp     eax, 2
    CHK     e, 16
    call    st_reset                    ; 256 rooms fill the table
    xor     ebx, ebx
.fill:
    lea     edi, [rbx + 1]
    lea     esi, [rbx + 1]
    lea     rdx, [t_tmp]
    call    st_host_ok
    test    eax, eax
    CHK     z, 17
    inc     ebx
    cmp     ebx, ACR_MAX_ROOMS
    jb      .fill
    mov     edi, ACR_MAX_ROOMS + 1      ; the 257th gets nothing
    mov     esi, ACR_MAX_ROOMS + 1
    call    st_host
    test    eax, eax
    CHK     z, 18
    call    st_count_rooms
    cmp     eax, ACR_MAX_ROOMS
    CHK     e, 19
    mov     edi, 1                      ; a known host is still refreshed
    mov     esi, 1
    lea     rdx, [t_tmp]
    call    st_host_ok
    test    eax, eax
    CHK     z, 20
    call    st_reset                    ; short, foreign and mistyped RV_HOSTs are ignored
    xor     ebx, ebx
.bad:
    mov     edi, ebx
    call    st_host_bad
    test    eax, eax
    jz      .bad_next
    lea     eax, [rbx + 21]
    jmp     .out
.bad_next:
    inc     ebx
    cmp     ebx, 5
    jb      .bad
    call    st_count_rooms
    test    eax, eax
    CHK     z, 26
    xor     eax, eax
.out:
    pop     r12
    pop     rbx
    ret

; --- expiry: rooms and guests go 30 s after their last RV_HOST / packet, not a second earlier ---
st_expiry:
    push    rbx
    push    r12
    mov     edi, 1                      ; t = 1000: room 1 (host 1) with guest 3, room 2 (host 2)
    mov     esi, 1
    lea     rdx, [t_code]
    call    st_host_ok
    test    eax, eax
    CHK     z, 1
    mov     edi, 3
    lea     rsi, [t_code]
    call    st_join_send
    cmp     eax, 2
    CHK     e, 2
    mov     edi, 2
    mov     esi, 2
    lea     rdx, [t_code2]
    call    st_host_ok
    test    eax, eax
    CHK     z, 3
    mov     qword [clock_val], 1010     ; t = 1010: guest 4 joins room 1, host 1 refreshes it
    mov     edi, 4
    lea     rsi, [t_code]
    call    st_join_send
    cmp     eax, 2
    CHK     e, 4
    mov     edi, 1
    mov     esi, 1
    lea     rdx, [t_tmp]
    call    st_host_ok
    test    eax, eax
    CHK     z, 5
    mov     edi, 1029                   ; t = 1029: room 2 and guest 3 are 29 s old: alive
    call    st_tick
    call    st_count_rooms
    cmp     eax, 2
    CHK     e, 6
    mov     edi, 1
    call    st_ep
    mov     rdi, rax
    call    st_room_of
    mov     rbx, rax                    ; room 1
    test    rbx, rbx
    CHK     nz, 7
    mov     rdi, rbx
    call    st_count_guests
    cmp     eax, 2
    CHK     e, 8
    mov     edi, 1030                   ; t = 1030: room 2 and guest 3 are 30 s old: gone; room 1, guest 4 stay
    call    st_tick
    call    st_count_rooms
    cmp     eax, 1
    CHK     e, 9
    mov     rdi, rbx
    call    st_count_guests
    cmp     eax, 1
    CHK     e, 10
    lea     rdi, [t_exp_expired]        ; room 2's expiry is logged once, and its code now draws RV_NOROOM
    lea     rsi, [t_code2]
    call    st_patch
    lea     rdi, [t_exp_expired]
    call    log_has
    cmp     eax, 1
    CHK     e, 11
    mov     edi, 6
    lea     rsi, [t_code2]
    call    st_join_send
    cmp     eax, 1
    CHK     e, 12
    xor     edi, edi
    call    cap_rec
    mov     rdi, rax
    mov     esi, RV_NOROOM
    mov     edx, ACR_LEN_NOROOM
    call    st_hdr_ok
    test    eax, eax
    CHK     z, 13
    mov     qword [clock_val], 1035     ; t = 1035: host 1 refreshes room 1 again
    mov     edi, 1
    mov     esi, 1
    lea     rdx, [t_tmp]
    call    st_host_ok
    test    eax, eax
    CHK     z, 14
    mov     edi, 1039                   ; guest 4 (joined 1010): 29 s at 1039, 30 s at 1040
    call    st_tick
    mov     rdi, rbx
    call    st_count_guests
    cmp     eax, 1
    CHK     e, 15
    mov     edi, 1040
    call    st_tick
    mov     rdi, rbx
    call    st_count_guests
    test    eax, eax
    CHK     z, 16
    call    st_count_rooms
    cmp     eax, 1
    CHK     e, 17
    mov     edi, 5                      ; t = 1040: guest 5 joins room 1
    lea     rsi, [t_code]
    call    st_join_send
    cmp     eax, 2
    CHK     e, 18
    mov     edi, 1060                   ; t = 1060: guest 5 relays to host 1 (a packet: it counts as fresh again)
    call    st_tick
    mov     edi, 5
    call    st_ep
    mov     r12, rax
    mov     edi, 1
    call    st_ep
    mov     rdx, rax
    mov     rdi, r12
    lea     rsi, [t_code]
    mov     ecx, 4
    call    st_relay
    cmp     eax, 1
    CHK     e, 19
    mov     edi, 1                      ; host 1 refreshes at 1060 and 1070: room 1 is good to 1100
    mov     esi, 1
    lea     rdx, [t_tmp]
    call    st_host_ok
    test    eax, eax
    CHK     z, 20
    mov     qword [clock_val], 1070
    mov     edi, 1
    mov     esi, 1
    lea     rdx, [t_tmp]
    call    st_host_ok
    test    eax, eax
    CHK     z, 21
    mov     edi, 1089                   ; guest 5: 29 s after its relay at 1060 alive, 30 s gone; the room goes on
    call    st_tick
    mov     rdi, rbx
    call    st_count_guests
    cmp     eax, 1
    CHK     e, 22
    mov     edi, 1090
    call    st_tick
    mov     rdi, rbx
    call    st_count_guests
    test    eax, eax
    CHK     z, 23
    call    st_count_rooms
    cmp     eax, 1
    CHK     e, 24
    mov     edi, 1099                   ; room 1: 29 s after its last RV_HOST (1070) alive, 30 s gone
    call    st_tick
    call    st_count_rooms
    cmp     eax, 1
    CHK     e, 25
    mov     edi, 1100
    call    st_tick
    call    st_count_rooms
    test    eax, eax
    CHK     z, 26
    lea     rdi, [t_exp_expired]
    lea     rsi, [t_code]
    call    st_patch
    lea     rdi, [t_exp_expired]
    call    log_has
    cmp     eax, 1
    CHK     e, 27
    mov     edi, 7                      ; nobody can join it any more
    lea     rsi, [t_code]
    call    st_join_send
    cmp     eax, 1
    CHK     e, 28
    xor     eax, eax
.out:
    pop     r12
    pop     rbx
    ret

; --- relay_auth: host and guests reach each other, nobody else does ---
st_relay_auth:
    push    rbx
    push    r12
    push    r13
    lea     rdi, [s_script_abcdef]      ; the room's code is ABCDEF
    mov     esi, 6
    call    st_set_script
    mov     edi, 1
    mov     esi, 1
    lea     rdx, [t_code]
    call    st_host_ok
    test    eax, eax
    CHK     z, 1
    mov     qword [rng_script], 0
    mov     edi, 2
    lea     rsi, [t_code]
    call    st_join_send
    cmp     eax, 2
    CHK     e, 2
    mov     edi, 3
    lea     rsi, [t_code]
    call    st_join_send
    cmp     eax, 2
    CHK     e, 3
    mov     edi, 1
    call    st_ep
    mov     rbx, rax                    ; host
    mov     edi, 2
    call    st_ep
    mov     r12, rax                    ; guest 2
    mov     edi, 3
    call    st_ep
    mov     r13, rax                    ; guest 3
    mov     rdi, r12                    ; guest -> host, 32 bytes of game packet
    lea     rsi, [t_code]
    mov     rdx, rbx
    mov     ecx, 32
    call    st_relay
    cmp     eax, 1
    CHK     e, 4
    xor     edi, edi
    call    cap_rec
    mov     rdi, rax
    mov     rsi, rbx
    mov     rdx, r12
    mov     ecx, 32
    call    st_fwd_ok
    test    eax, eax
    CHK     z, 5
    mov     rdi, rbx                    ; host -> guest
    lea     rsi, [t_code]
    mov     rdx, r12
    mov     ecx, 5
    call    st_relay
    cmp     eax, 1
    CHK     e, 6
    xor     edi, edi
    call    cap_rec
    mov     rdi, rax
    mov     rsi, r12
    mov     rdx, rbx
    mov     ecx, 5
    call    st_fwd_ok
    test    eax, eax
    CHK     z, 7
    mov     rdi, r12                    ; guest -> guest, one byte
    lea     rsi, [t_code]
    mov     rdx, r13
    mov     ecx, 1
    call    st_relay
    cmp     eax, 1
    CHK     e, 8
    xor     edi, edi
    call    cap_rec
    mov     rdi, rax
    mov     rsi, r13
    mov     rdx, r12
    mov     ecx, 1
    call    st_fwd_ok
    test    eax, eax
    CHK     z, 9
    mov     rdi, r12                    ; the code in lower case is the same room
    lea     rsi, [t_lower_abcdef]
    mov     rdx, rbx
    mov     ecx, 7
    call    st_relay
    cmp     eax, 1
    CHK     e, 10
    mov     edi, 50                     ; a stranger -> host
    call    st_ep
    mov     rdi, rax
    lea     rsi, [t_code]
    mov     rdx, rbx
    mov     ecx, 8
    call    st_relay
    test    eax, eax
    CHK     z, 11
    mov     ecx, 1                      ; the host's address on another port is a stranger too
    shl     rcx, 32
    mov     rdi, rbx
    xor     rdi, rcx
    lea     rsi, [t_code]
    mov     rdx, r12
    mov     ecx, 8
    call    st_relay
    test    eax, eax
    CHK     z, 12
    mov     edi, 50                     ; guest -> a stranger
    call    st_ep
    mov     rdx, rax
    mov     rdi, r12
    lea     rsi, [t_code]
    mov     ecx, 8
    call    st_relay
    test    eax, eax
    CHK     z, 13
    mov     rdi, r12                    ; guest -> itself
    lea     rsi, [t_code]
    mov     rdx, r12
    mov     ecx, 8
    call    st_relay
    test    eax, eax
    CHK     z, 14
    mov     rdi, r12                    ; guest -> nobody
    lea     rsi, [t_code]
    xor     edx, edx
    mov     ecx, 8
    call    st_relay
    test    eax, eax
    CHK     z, 15
    mov     rdi, r12                    ; guest -> host with a code no room has
    lea     rsi, [t_code_none]
    mov     rdx, rbx
    mov     ecx, 8
    call    st_relay
    test    eax, eax
    CHK     z, 16
    mov     rdi, r12                    ; no game packet at all
    lea     rsi, [t_code]
    mov     rdx, rbx
    xor     ecx, ecx
    call    st_relay
    test    eax, eax
    CHK     z, 17
    mov     rdi, r12                    ; NET_MTU bytes of game packet is the most
    lea     rsi, [t_code]
    mov     rdx, rbx
    mov     ecx, NET_MTU
    call    st_relay
    cmp     eax, 1
    CHK     e, 18
    mov     rdi, r12
    lea     rsi, [t_code]
    mov     rdx, rbx
    mov     ecx, NET_MTU + 1
    call    st_relay
    test    eax, eax
    CHK     z, 19
    lea     rdi, [t_exp_rs2]            ; "relay start" once for guest 2, never for guest 3 (silent) or the host
    lea     rsi, [t_code]
    call    st_patch
    lea     rdi, [t_exp_rs2]
    call    log_has
    cmp     eax, 1
    CHK     e, 20
    lea     rdi, [t_exp_rs3]
    lea     rsi, [t_code]
    call    st_patch
    lea     rdi, [t_exp_rs3]
    call    log_has
    test    eax, eax
    CHK     z, 21
    lea     rdi, [t_exp_rs1]
    lea     rsi, [t_code]
    call    st_patch
    lea     rdi, [t_exp_rs1]
    call    log_has
    test    eax, eax
    CHK     z, 22
    xor     eax, eax
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; --- join: RV_PEER to both sides, case-insensitive codes, RV_NOROOM, 7 guests ---
st_join:
    push    rbx
    push    r12
    lea     rdi, [s_script_abcdef]      ; the room's code is ABCDEF
    mov     esi, 6
    call    st_set_script
    mov     edi, 1
    mov     esi, 1
    lea     rdx, [t_code]
    call    st_host_ok
    test    eax, eax
    CHK     z, 1
    mov     qword [rng_script], 0
    mov     rax, [t_code]
    cmp     rax, [t_code_abcdef]
    CHK     e, 2
    mov     edi, 2                      ; guest 2 joins with the code in lower case
    lea     rsi, [t_lower_abcdef]
    call    st_join_send
    cmp     eax, 2
    CHK     e, 3
    mov     edi, 2                      ; RV_PEER to the guest: the host is the other side
    call    st_ep
    mov     rdi, rax
    call    cap_find
    test    rax, rax
    CHK     nz, 4
    mov     rbx, rax
    mov     rdi, rbx
    mov     esi, RV_PEER
    mov     edx, ACR_LEN_PEER
    call    st_hdr_ok
    test    eax, eax
    CHK     z, 5
    mov     rax, [rbx + 12 + 4]         ; the code, in the room's own case
    cmp     rax, [t_code_abcdef]
    CHK     e, 6
    mov     edi, 1
    call    st_ep
    cmp     [rbx + 12 + 12], rax        ; other_pub = host
    CHK     e, 7
    mov     edi, 1
    call    st_lan
    cmp     [rbx + 12 + 20], rax        ; other_lan = the host's lan
    CHK     e, 8
    mov     edi, 2
    call    st_ep
    cmp     [rbx + 12 + 28], rax        ; self_pub = the guest
    CHK     e, 9
    mov     edi, 1                      ; RV_PEER to the host: the guest is the other side
    call    st_ep
    mov     rdi, rax
    call    cap_find
    test    rax, rax
    CHK     nz, 10
    mov     rbx, rax
    mov     rdi, rbx
    mov     esi, RV_PEER
    mov     edx, ACR_LEN_PEER
    call    st_hdr_ok
    test    eax, eax
    CHK     z, 11
    mov     rax, [rbx + 12 + 4]
    cmp     rax, [t_code_abcdef]
    CHK     e, 12
    mov     edi, 2
    call    st_ep
    cmp     [rbx + 12 + 12], rax        ; other_pub = the guest
    CHK     e, 13
    mov     edi, 2
    call    st_lan
    cmp     [rbx + 12 + 20], rax        ; other_lan = the guest's lan
    CHK     e, 14
    mov     edi, 1
    call    st_ep
    cmp     [rbx + 12 + 28], rax        ; self_pub = the host
    CHK     e, 15
    lea     rdi, [t_exp_join2]          ; and the join is logged
    lea     rsi, [t_code]
    call    st_patch
    lea     rdi, [t_exp_join2]
    call    log_has
    cmp     eax, 1
    CHK     e, 16
    mov     edi, 11                     ; a code no room has: RV_NOROOM with the code as it came
    lea     rsi, [t_code_none]
    call    st_join_send
    cmp     eax, 1
    CHK     e, 17
    xor     edi, edi
    call    cap_rec
    mov     rbx, rax
    mov     rdi, rbx
    mov     esi, RV_NOROOM
    mov     edx, ACR_LEN_NOROOM
    call    st_hdr_ok
    test    eax, eax
    CHK     z, 18
    mov     edi, 11
    call    st_ep
    cmp     [rbx], rax                  ; to the asker
    CHK     e, 19
    mov     rax, [rbx + 12 + 4]
    cmp     rax, [t_code_none]
    CHK     e, 20
    mov     edi, 12                     ; a RV_JOIN one byte short is ignored, and no guest is recorded
    lea     rsi, [t_code_abcdef]
    call    st_lan
    mov     rdx, rax
    lea     rdi, [t_code_abcdef]
    mov     esi, 12
    call    tb_join
    mov     edi, 12
    call    st_ep
    mov     rdi, rax
    mov     esi, ACR_LEN_JOIN - 1
    call    st_send
    cmp     dword [cap_count], 0
    CHK     e, 21
    mov     edi, 1
    call    st_ep
    mov     rdi, rax
    call    st_room_of
    mov     rbx, rax                    ; the room
    mov     rdi, rbx
    call    st_count_guests
    cmp     eax, 1
    CHK     e, 22
    mov     r12d, 3                     ; guests 3..8 join at 1001..1006: seven guests fit
.fill:
    lea     eax, [r12 + 998]
    mov     [clock_val], rax
    mov     edi, r12d
    lea     rsi, [t_code_abcdef]
    call    st_join_send
    cmp     eax, 2
    CHK     e, 23
    inc     r12d
    cmp     r12d, 8
    jbe     .fill
    mov     rdi, rbx
    call    st_count_guests
    cmp     eax, 7
    CHK     e, 24
    mov     qword [clock_val], 1007     ; guest 9 at 1007: the oldest, guest 2 (1000), gives way
    mov     edi, 9
    lea     rsi, [t_code_abcdef]
    call    st_join_send
    cmp     eax, 2
    CHK     e, 25
    mov     edi, 2
    call    st_ep
    mov     rdi, rbx
    mov     rsi, rax
    call    guest_find
    test    rax, rax
    CHK     z, 26
    mov     edi, 9
    call    st_ep
    mov     rdi, rbx
    mov     rsi, rax
    call    guest_find
    test    rax, rax
    CHK     nz, 27
    mov     qword [clock_val], 1008     ; guest 3 again at 1008: refreshed in place, nobody replaced
    mov     edi, 3
    lea     rsi, [t_code_abcdef]
    call    st_join_send
    cmp     eax, 2
    CHK     e, 28
    mov     rdi, rbx
    call    st_count_guests
    cmp     eax, 7
    CHK     e, 29
    mov     qword [clock_val], 1009     ; guest 10 at 1009: the oldest is now guest 4 (1002), not the refreshed guest 3
    mov     edi, 10
    lea     rsi, [t_code_abcdef]
    call    st_join_send
    cmp     eax, 2
    CHK     e, 30
    mov     edi, 4
    call    st_ep
    mov     rdi, rbx
    mov     rsi, rax
    call    guest_find
    test    rax, rax
    CHK     z, 31
    mov     edi, 3
    call    st_ep
    mov     rdi, rbx
    mov     rsi, rax
    call    guest_find
    test    rax, rax
    CHK     nz, 32
    xor     eax, eax
.out:
    pop     r12
    pop     rbx
    ret

; --- relay_budget: 2 MiB per room per second, counted per room, renewed every second ---
st_relay_budget:
    push    rbx
    push    r12
    mov     qword [clock_val], 2000
    mov     edi, 1                      ; room A: host 1, guest 2.  room B: host 11, guest 12.
    mov     esi, 1
    lea     rdx, [t_code]
    call    st_host_ok
    test    eax, eax
    CHK     z, 1
    mov     edi, 2
    lea     rsi, [t_code]
    call    st_join_send
    cmp     eax, 2
    CHK     e, 2
    mov     edi, 11
    mov     esi, 11
    lea     rdx, [t_code2]
    call    st_host_ok
    test    eax, eax
    CHK     z, 3
    mov     edi, 12
    lea     rsi, [t_code2]
    call    st_join_send
    cmp     eax, 2
    CHK     e, 4
    mov     edi, 1
    call    st_ep
    mov     [t_k1], rax
    mov     edi, 2
    call    st_ep
    mov     [t_k2], rax
    xor     ebx, ebx                    ; forwarded
    xor     r12d, r12d                  ; sent
.flood:                                 ; full-size packets from guest 2 to host 1 in one second
    mov     rdi, [t_k2]
    lea     rsi, [t_code]
    mov     rdx, [t_k1]
    mov     ecx, NET_MTU
    call    st_relay
    add     ebx, eax
    inc     r12d
    cmp     r12d, 1800
    jb      .flood
    cmp     ebx, ACR_BUDGET / (ACR_RELAY_HDR + NET_MTU)
    CHK     e, 5
    mov     rdi, [t_k2]                 ; what is left of the budget fits exactly...
    lea     rsi, [t_code]
    mov     rdx, [t_k1]
    mov     ecx, ACR_BUDGET - (ACR_BUDGET / (ACR_RELAY_HDR + NET_MTU)) * (ACR_RELAY_HDR + NET_MTU) - ACR_RELAY_HDR
    call    st_relay
    cmp     eax, 1
    CHK     e, 6
    mov     rdi, [t_k2]                 ; ... and one more byte does not
    lea     rsi, [t_code]
    mov     rdx, [t_k1]
    mov     ecx, 1
    call    st_relay
    test    eax, eax
    CHK     z, 7
    mov     edi, 12                     ; room B has its own budget
    call    st_ep
    mov     r12, rax
    mov     edi, 11
    call    st_ep
    mov     rdx, rax
    mov     rdi, r12
    lea     rsi, [t_code2]
    mov     ecx, NET_MTU
    call    st_relay
    cmp     eax, 1
    CHK     e, 8
    mov     edi, 2001                   ; the next second starts a new budget
    call    st_tick
    mov     rdi, [t_k2]
    lea     rsi, [t_code]
    mov     rdx, [t_k1]
    mov     ecx, NET_MTU
    call    st_relay
    cmp     eax, 1
    CHK     e, 9
    xor     eax, eax
.out:
    pop     r12
    pop     rbx
    ret
