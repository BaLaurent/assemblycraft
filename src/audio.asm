; audio.asm - PulseAudio playback (libpulse-simple), 16-voice stereo chip mixer, positional play.
; The game calls audio_update(dt) once per frame: it mixes dt seconds of samples and writes them,
; so output stays in step with the frame clock (the blocking write is the throttle). Sounds are the
; int16 samples sfx_build renders into sfx_pool; every play call is a no-op until audio_init succeeds.
; audio_mix is the whole mixer and touches no PulseAudio: each voice is resampled linearly (32.32
; position and step, so a play can be pitch-jittered), panned into left, right and an echo send; two
; low-passed feedback delay lines (170 ms left, 190 ms right) add the room; a soft look-behind limiter
; keeps the sum under 29205. Per-play pitch jitter uses a private RNG so gameplay's stays untouched.
%include "common.inc"
default rel

global audio_init, audio_update, audio_play, audio_play_at, audio_play_local_at, audio_shutdown
global audio_mix, audio_reset, audio_enabled, voices

extern pa_simple_new, pa_simple_write, pa_simple_free
extern sfx_build, sfx_table, sfx_pool, sfx_info
extern exp2_ss, sincos_deg
extern settings, player, player_eye
extern net_role, net_applying, net_sound_out

%define MAX_FRAMES 2048                 ; most frames written per audio_update (46 ms)
%define ECHO_L     7497                 ; 170 ms
%define ECHO_R     8379                 ; 190 ms

section .rodata
s_app:      db "AssemblyCraft", 0
s_stream:   db "Game sounds", 0
align 4
pa_ss:                                  ; pa_sample_spec: S16LE, 44100 Hz, stereo
    dd 3
    dd 44100
    db 2, 0, 0, 0
pa_attr:                                ; pa_buffer_attr: 60 ms target length (stereo S16), the rest server default
    dd 0xFFFFFFFF, 10584, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF
c_one:       dd 1.0
c_100:       dd 100.0
c_rate:      dd 44100.0
c_frames:    dd 2048.0                  ; MAX_FRAMES
c_dt_max:    dd 0.1                     ; keeps an absurd dt from poisoning the carry
c_inv_range: dd 0.0625                  ; 1 / 16 blocks: positional sounds fade out by then
c_h_min:     dd 0.001                   ; closer than this a source has no side
c_pan_max:   dd 0.6                     ; hard-left or hard-right source keeps 40 % in the far ear
c_inv_255:   dd 0.00392156862745098     ; echo send byte -> 0..1
c_inv_1200:  dd 0.0008333333333333334   ; cents -> octaves
c_2p32:      dd 4294967296.0            ; 1.0 in the 32.32 voice step
c_2m32:      dd 2.3283064365386963e-10  ; low half of the 32.32 position -> fraction
c_echo_lp:   dd 0.45                    ; echo-line damping: one-pole low-pass per pass
c_echo_fb:   dd 0.35                    ; echo feedback
c_limit:     dd 29205.0                 ; limiter ceiling (-1 dBFS)
c_lim_rel:   dd 0.00023                 ; limiter release per frame, ~100 ms
c_absmask:   dd 0x7FFFFFFF

section .bss
alignb 16
accL:           resd MAX_FRAMES         ; per-frame sums: left, right, echo send
accR:           resd MAX_FRAMES
accE:           resd MAX_FRAMES
mix_buf:        resw 2 * MAX_FRAMES     ; final int16 output, interleaved L,R
echoL:          resd ECHO_L
echoR:          resd ECHO_R
voices:         resb VOICES * VOICE_size
pa_handle:      resq 1
pa_err:         resd 1
audio_enabled:  resd 1
audio_frac:     resd 1                  ; fractional sample carried between updates
audio_serial:   resd 1                  ; start order of the next voice
audio_rng_state: resd 1
echo_il:        resd 1                  ; ring write/read indices
echo_ir:        resd 1
echo_fl:        resd 1                  ; echo low-pass states
echo_fr:        resd 1
lim_g:          resd 1                  ; limiter gain, 1.0 = idle

section .text

; audio_init() -> eax 1 connected / 0 sound disabled
audio_init:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32                     ; stack args 7..9
    xor     edi, edi                    ; server: default
    lea     rsi, [s_app]
    mov     edx, 1                      ; PA_STREAM_PLAYBACK
    xor     ecx, ecx                    ; device: default
    lea     r8, [s_stream]
    lea     r9, [pa_ss]
    mov     qword [rsp], 0              ; channel map: default
    lea     rax, [pa_attr]
    mov     [rsp + 8], rax
    lea     rax, [pa_err]
    mov     [rsp + 16], rax
    call    pa_simple_new
    test    rax, rax
    jz      .fail
    mov     [pa_handle], rax
    call    audio_reset
    mov     dword [audio_frac], 0
    mov     dword [audio_enabled], 1
    call    sfx_build
    mov     eax, 1
    leave
    ret
.fail:
    mov     dword [audio_enabled], 0
    xor     eax, eax
    leave
    ret

; audio_reset(): silence every voice and echo line, restart the serial counter, the limiter and the
; private RNG (so a mix is reproducible). Clobbers rax, rcx, rdi.
audio_reset:
    lea     rdi, [voices]
    mov     ecx, VOICES * VOICE_size / 4
    xor     eax, eax
    rep     stosd
    lea     rdi, [echoL]
    mov     ecx, ECHO_L
    rep     stosd
    lea     rdi, [echoR]
    mov     ecx, ECHO_R
    rep     stosd
    mov     [echo_il], eax
    mov     [echo_ir], eax
    mov     [echo_fl], eax
    mov     [echo_fr], eax
    mov     [audio_serial], eax
    mov     dword [lim_g], __float32__(1.0)
    mov     dword [audio_rng_state], 0xA5A5F00D
    ret

; audio_rng() -> eax: xorshift32 on audio_rng_state (the algorithm of rng_next, a private stream). Clobbers ecx.
audio_rng:
    mov     eax, [audio_rng_state]
    mov     ecx, eax
    shl     ecx, 13
    xor     eax, ecx
    mov     ecx, eax
    shr     ecx, 17
    xor     eax, ecx
    mov     ecx, eax
    shl     ecx, 5
    xor     eax, ecx
    mov     [audio_rng_state], eax
    ret

; audio_update(xmm0 dt): mix dt seconds of the active voices and write them to the stream
audio_update:
    cmp     dword [audio_enabled], 0
    je      .off
    push    rbx
    xorps   xmm1, xmm1
    maxss   xmm0, xmm1                  ; negative or NaN dt counts as 0
    minss   xmm0, [c_dt_max]
    mulss   xmm0, [c_rate]
    addss   xmm0, [audio_frac]
    roundss xmm1, xmm0, 9               ; whole samples due
    subss   xmm0, xmm1
    movss   [audio_frac], xmm0          ; carry the remainder
    minss   xmm1, [c_frames]            ; a long frame queues at most 2048, the rest is dropped
    cvttss2si ebx, xmm1                 ; ebx = frames to write
    test    ebx, ebx
    jz      .done
    lea     rdi, [mix_buf]
    mov     esi, ebx
    call    audio_mix
    mov     rdi, [pa_handle]
    lea     rsi, [mix_buf]
    lea     rdx, [rbx*4]                ; bytes: 2 channels * 2
    lea     rcx, [pa_err]
    call    pa_simple_write
.done:
    pop     rbx
.off:
    ret

; audio_mix(rdi int16 *out, esi frames <= MAX_FRAMES): mixes the voices into frames interleaved L,R
; samples. Pure: no PulseAudio, no audio_enabled check. Leaf.
audio_mix:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r15, rdi
    mov     ebx, esi
    test    ebx, ebx
    jz      .done
    xor     eax, eax
    lea     rdi, [accL]
    mov     ecx, ebx
    rep     stosd
    lea     rdi, [accR]
    mov     ecx, ebx
    rep     stosd
    lea     rdi, [accE]
    mov     ecx, ebx
    rep     stosd
    lea     r12, [voices]
    mov     r13d, VOICES
    lea     r11, [accL]
    lea     r14, [accR]
    lea     rdx, [accE]
.voice:
    mov     r10d, [r12 + VOICE.len]
    test    r10d, r10d
    jz      .next_voice
    mov     rsi, [r12 + VOICE.ptr]
    mov     r8, [r12 + VOICE.pos]
    mov     r9, [r12 + VOICE.step]
    movss   xmm4, [r12 + VOICE.gl]
    movss   xmm5, [r12 + VOICE.gr]
    movss   xmm6, [r12 + VOICE.send]
    xor     ecx, ecx
.frame:
    mov     rdi, r8
    shr     rdi, 32                     ; idx
    cmp     edi, r10d
    jae     .voice_end
    movsx   eax, word [rsi + rdi*2]
    cvtsi2ss xmm0, eax                  ; a
    xorps   xmm1, xmm1                  ; b = 0 past the last sample
    inc     edi
    cmp     edi, r10d
    jae     .no_next
    movsx   eax, word [rsi + rdi*2]
    cvtsi2ss xmm1, eax
.no_next:
    mov     eax, r8d                    ; low half of pos = fraction * 2^32
    cvtsi2ss xmm2, rax
    mulss   xmm2, [c_2m32]
    subss   xmm1, xmm0
    mulss   xmm1, xmm2
    addss   xmm0, xmm1                  ; s = a + (b - a) * frac
    movaps  xmm1, xmm0
    mulss   xmm1, xmm4
    addss   xmm1, [r11 + rcx*4]
    movss   [r11 + rcx*4], xmm1
    movaps  xmm1, xmm0
    mulss   xmm1, xmm5
    addss   xmm1, [r14 + rcx*4]
    movss   [r14 + rcx*4], xmm1
    mulss   xmm0, xmm6
    addss   xmm0, [rdx + rcx*4]
    movss   [rdx + rcx*4], xmm0
    add     r8, r9
    inc     ecx
    cmp     ecx, ebx
    jb      .frame
    mov     [r12 + VOICE.pos], r8
    jmp     .next_voice
.voice_end:
    mov     dword [r12 + VOICE.len], 0
.next_voice:
    add     r12, VOICE_size
    dec     r13d
    jnz     .voice
    ; echo + master volume + limiter, one frame at a time
    lea     r12, [accL]
    lea     r13, [accR]
    lea     r14, [accE]
    lea     r10, [echoL]
    lea     r11, [echoR]
    mov     r8d, [echo_il]
    mov     r9d, [echo_ir]
    movss   xmm8, [echo_fl]
    movss   xmm9, [echo_fr]
    movss   xmm10, [lim_g]
    cvtsi2ss xmm11, dword [settings + SETTINGS.volume]
    divss   xmm11, [c_100]              ; m
    movss   xmm12, [c_limit]
    movss   xmm13, [c_absmask]
    mov     edx, 32767
    mov     esi, -32767
    xor     ecx, ecx
.out:
    movss   xmm0, [r10 + r8*4]          ; yl
    subss   xmm0, xmm8
    mulss   xmm0, [c_echo_lp]
    addss   xmm8, xmm0                  ; fl
    movss   xmm0, [r11 + r9*4]          ; yr
    subss   xmm0, xmm9
    mulss   xmm0, [c_echo_lp]
    addss   xmm9, xmm0                  ; fr
    movss   xmm2, [r14 + rcx*4]         ; send
    movaps  xmm3, xmm8
    mulss   xmm3, [c_echo_fb]
    addss   xmm3, xmm2
    movss   [r10 + r8*4], xmm3
    movaps  xmm3, xmm9
    mulss   xmm3, [c_echo_fb]
    addss   xmm3, xmm2
    movss   [r11 + r9*4], xmm3
    inc     r8d
    cmp     r8d, ECHO_L
    jb      .il_ok
    xor     r8d, r8d
.il_ok:
    inc     r9d
    cmp     r9d, ECHO_R
    jb      .ir_ok
    xor     r9d, r9d
.ir_ok:
    movss   xmm0, [r12 + rcx*4]
    addss   xmm0, xmm8
    mulss   xmm0, xmm11                 ; L
    movss   xmm1, [r13 + rcx*4]
    addss   xmm1, xmm9
    mulss   xmm1, xmm11                 ; R
    movaps  xmm2, xmm0
    andps   xmm2, xmm13
    movaps  xmm3, xmm1
    andps   xmm3, xmm13
    maxss   xmm2, xmm3                  ; pk
    movaps  xmm3, xmm2
    mulss   xmm3, xmm10
    ucomiss xmm3, xmm12
    jbe     .no_limit
    movaps  xmm10, xmm12
    divss   xmm10, xmm2                 ; gain that brings this frame to the ceiling
.no_limit:
    mulss   xmm0, xmm10
    mulss   xmm1, xmm10
    cvtss2si eax, xmm0
    cmp     eax, edx
    cmovg   eax, edx
    cmp     eax, esi
    cmovl   eax, esi
    mov     [r15], ax
    cvtss2si eax, xmm1
    cmp     eax, edx
    cmovg   eax, edx
    cmp     eax, esi
    cmovl   eax, esi
    mov     [r15 + 2], ax
    add     r15, 4
    movss   xmm2, [c_one]
    subss   xmm2, xmm10
    mulss   xmm2, [c_lim_rel]
    addss   xmm10, xmm2                 ; release toward 1.0
    inc     ecx
    cmp     ecx, ebx
    jb      .out
    mov     [echo_il], r8d
    mov     [echo_ir], r9d
    movss   [echo_fl], xmm8
    movss   [echo_fr], xmm9
    movss   [lim_g], xmm10
.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; audio_play_at(edi snd, xmm0 x, xmm1 y, xmm2 z, xmm3 vol): start_voice, faded by the distance from the
; player's eye (silent at 16 blocks) and panned by which side of the player's facing it lies on
; In multiplayer the sound is also sent to the other peers (net_sound_out), whether this machine plays it or not, unless a
; message is being applied (net_applying): a sound heard from another peer is not sent on.
audio_play_at:
    cmp     byte [net_role], NET_ROLE_OFF
    je      audio_play_local_at
    cmp     byte [net_applying], 0
    jne     audio_play_local_at
    sub     rsp, 24
    mov     [rsp + 16], edi
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 8], xmm2
    movss   [rsp + 12], xmm3
    call    net_sound_out               ; the same registers: snd, position, volume
    mov     edi, [rsp + 16]
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    movss   xmm3, [rsp + 12]
    add     rsp, 24
; audio_play_local_at(edi snd, xmm0 x, xmm1 y, xmm2 z, xmm3 vol): audio_play_at for a sound every machine makes for itself
; (a plane's engine, heard from the plane each machine sees): it is not sent to the other peers
audio_play_local_at:
    cmp     dword [audio_enabled], 0
    je      .off
    push    rbp
    mov     rbp, rsp
    sub     rsp, 48                     ; [rsp] eye[3], dx, snd, x, y, z, vol, gain, dz, h
    mov     [rsp + 16], edi
    movss   [rsp + 20], xmm0
    movss   [rsp + 24], xmm1
    movss   [rsp + 28], xmm2
    movss   [rsp + 32], xmm3
    mov     rdi, rsp
    call    player_eye
    movss   xmm0, [rsp + 20]
    subss   xmm0, [rsp]
    movss   [rsp + 12], xmm0            ; dx
    movss   xmm1, [rsp + 24]
    subss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 28]
    subss   xmm2, [rsp + 8]
    movss   [rsp + 40], xmm2            ; dz
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    mulss   xmm2, xmm2
    addss   xmm1, xmm0
    addss   xmm0, xmm2                  ; dx^2 + dz^2
    addss   xmm1, xmm2                  ; + dy^2
    sqrtss  xmm1, xmm1                  ; distance
    sqrtss  xmm0, xmm0
    movss   [rsp + 44], xmm0            ; h
    mulss   xmm1, [c_inv_range]
    movss   xmm2, [c_one]
    subss   xmm2, xmm1
    xorps   xmm1, xmm1
    maxss   xmm2, xmm1                  ; max(0, 1 - d / 16)
    mulss   xmm2, [rsp + 32]
    movss   [rsp + 36], xmm2            ; gain
    ucomiss xmm0, [c_h_min]
    jb      .centred                    ; straight above or below: no side
    movss   xmm0, [player + BODY.yaw]
    call    sincos_deg                  ; xmm0 = sin yaw, xmm1 = cos yaw
    mulss   xmm1, [rsp + 12]
    mulss   xmm0, [rsp + 40]
    addss   xmm0, xmm1                  ; along the right vector (cos yaw, sin yaw)
    divss   xmm0, [rsp + 44]
    mulss   xmm0, [c_pan_max]
    movaps  xmm1, xmm0
    jmp     .go
.centred:
    xorps   xmm1, xmm1
.go:
    movss   xmm0, [rsp + 36]
    mov     edi, [rsp + 16]
    leave
    jmp     start_voice                 ; a gain that comes to 0 starts nothing
.off:
    ret

; audio_shutdown(): close the stream
audio_shutdown:
    cmp     dword [audio_enabled], 0
    je      .off
    mov     dword [audio_enabled], 0
    mov     rdi, [pa_handle]
    mov     qword [pa_handle], 0
    sub     rsp, 8
    call    pa_simple_free
    add     rsp, 8
.off:
    ret

; audio_play(edi snd, xmm0 vol): played centred, vol clamped to 0..1
audio_play:
    cmp     dword [audio_enabled], 0
    je      .off
    xorps   xmm1, xmm1                  ; pan 0
    jmp     start_voice
.off:
    ret

; start_voice(edi snd, xmm0 vol, xmm1 pan -1..1): starts sfx_table[snd] with gains from vol (clamped to
; 0..1) and pan. Out-of-range snd or a vol of 0 starts nothing. A sound already at its cap of voices
; restarts its oldest one; else a free voice is taken, else the one with the least samples left.
; The pitch is jittered by up to sfx_info[snd].jitter cents (no RNG draw for a jitter of 0).
start_voice:
    cmp     edi, NUM_SOUNDS
    jae     .none
    xorps   xmm2, xmm2
    maxss   xmm0, xmm2
    minss   xmm0, [c_one]
    ucomiss xmm0, xmm2
    jbe     .none
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 16                     ; [rsp] vol, [rsp + 4] pan
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    mov     ebx, edi                    ; snd
    lea     r12, [sfx_info]
    lea     r12, [r12 + rbx*8]
    lea     r8, [voices]
    mov     ecx, VOICES
    xor     r9d, r9d                    ; voices already playing snd
    xor     r10d, r10d                  ; the oldest of them
    mov     r11d, 0xFFFFFFFF            ; its serial
    xor     esi, esi                    ; first free voice
    mov     r13d, 0x7FFFFFFF            ; least samples remaining
    xor     r14d, r14d                  ; and its voice
.scan:
    mov     eax, [r8 + VOICE.len]
    test    eax, eax
    jz      .free
    mov     rdx, [r8 + VOICE.pos]
    shr     rdx, 32
    sub     eax, edx                    ; remaining
    cmp     eax, r13d
    jge     .same
    mov     r13d, eax
    mov     r14, r8
.same:
    cmp     [r8 + VOICE.snd], ebx
    jne     .next
    inc     r9d
    mov     eax, [r8 + VOICE.serial]
    cmp     eax, r11d
    jae     .next
    mov     r11d, eax
    mov     r10, r8
    jmp     .next
.free:
    test    rsi, rsi
    jnz     .next
    mov     rsi, r8
.next:
    add     r8, VOICE_size
    dec     ecx
    jnz     .scan
    movzx   eax, byte [r12 + SFXINFO.cap]
    cmp     r9d, eax
    jb      .uncapped
    test    r10, r10
    jz      .uncapped
    mov     r14, r10                    ; at the cap: restart the oldest of its own
    jmp     .claim
.uncapped:
    test    rsi, rsi
    cmovnz  r14, rsi                    ; else a free voice, else the least-remaining one
.claim:
    mov     r10d, 1
    shl     r10, 32                     ; step 1.0
    movzx   r13d, word [r12 + SFXINFO.jitter]
    test    r13d, r13d
    jz      .store
    call    audio_rng
    lea     ecx, [r13*2 + 1]
    xor     edx, edx
    div     ecx
    sub     edx, r13d                   ; cents in -J..J
    cvtsi2ss xmm0, edx
    mulss   xmm0, [c_inv_1200]
    call    exp2_ss
    mulss   xmm0, [c_2p32]
    cvtss2si r10, xmm0
.store:
    mov     [r14 + VOICE.step], r10
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [c_one]
    subss   xmm2, xmm1
    minss   xmm2, [c_one]
    mulss   xmm2, xmm0
    movss   [r14 + VOICE.gl], xmm2      ; vol * min(1, 1 - pan)
    movss   xmm2, [c_one]
    addss   xmm2, xmm1
    minss   xmm2, [c_one]
    mulss   xmm2, xmm0
    movss   [r14 + VOICE.gr], xmm2      ; vol * min(1, 1 + pan)
    movzx   eax, byte [r12 + SFXINFO.send]
    cvtsi2ss xmm2, eax
    mulss   xmm2, [c_inv_255]
    mulss   xmm2, xmm0
    movss   [r14 + VOICE.send], xmm2
    mov     qword [r14 + VOICE.pos], 0
    lea     rax, [sfx_table]
    mov     ecx, [rax + rbx*8]          ; offset, samples
    mov     edx, [rax + rbx*8 + 4]      ; length
    lea     rax, [sfx_pool]
    lea     rax, [rax + rcx*2]
    mov     [r14 + VOICE.ptr], rax
    mov     [r14 + VOICE.snd], ebx
    mov     eax, [audio_serial]
    mov     [r14 + VOICE.serial], eax
    inc     eax
    mov     [audio_serial], eax
    mov     [r14 + VOICE.len], edx
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
.none:
    ret
