; audio.asm - PulseAudio playback (libpulse-simple), 16-voice mixer, positional play.
; The game calls audio_update(dt) once per frame: it mixes dt seconds of samples and writes them,
; so output stays in step with the frame clock (the blocking write is the throttle). Sounds are
; the int16 samples sfx_build renders into sfx_pool; every call is a no-op until audio_init succeeds.
%include "common.inc"
default rel

global audio_init, audio_update, audio_play, audio_play_at, audio_shutdown

extern pa_simple_new, pa_simple_write, pa_simple_free
extern sfx_build, sfx_table, sfx_pool
extern settings, player_eye

%define VOICES     16
%define MAX_FRAMES 2048                 ; most samples written per audio_update (46 ms)

struc VOICE
    .ptr:       resq 1                  ; next int16 sample in sfx_pool
    .remaining: resd 1                  ; samples left, 0 = free
    .vol:       resd 1                  ; 0..256
endstruc

section .rodata
s_app:      db "AssemblyCraft", 0
s_stream:   db "Game sounds", 0
align 4
pa_ss:                                  ; pa_sample_spec: S16LE, 44100 Hz, mono
    dd 3
    dd 44100
    db 1, 0, 0, 0
pa_attr:                                ; pa_buffer_attr: 60 ms target length, the rest server default
    dd 0xFFFFFFFF, 5292, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF
c_one:       dd 1.0
c_256:       dd 256.0
c_rate:      dd 44100.0
c_frames:    dd 2048.0                  ; MAX_FRAMES
c_dt_max:    dd 0.1                     ; keeps an absurd dt from poisoning the carry
c_inv_range: dd 0.0625                  ; 1 / 16 blocks: positional sounds fade out by then

section .bss
alignb 16
mix_acc:        resd MAX_FRAMES         ; sum of sample * vol per output sample
mix_buf:        resw MAX_FRAMES         ; final int16 output
voices:         resb VOICES * VOICE_size
pa_handle:      resq 1
pa_err:         resd 1
audio_enabled:  resd 1
audio_frac:     resd 1                  ; fractional sample carried between updates

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
    lea     rdi, [voices]
    mov     ecx, VOICES * VOICE_size / 4
    xor     eax, eax
    rep     stosd
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

; audio_update(xmm0 dt): mix dt seconds of the active voices and write them to the stream
audio_update:
    cmp     dword [audio_enabled], 0
    je      .off
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    xorps   xmm1, xmm1
    maxss   xmm0, xmm1                  ; negative or NaN dt counts as 0
    minss   xmm0, [c_dt_max]
    mulss   xmm0, [c_rate]
    addss   xmm0, [audio_frac]
    roundss xmm1, xmm0, 9               ; whole samples due
    subss   xmm0, xmm1
    movss   [audio_frac], xmm0          ; carry the remainder
    minss   xmm1, [c_frames]            ; a long frame queues at most 2048, the rest is dropped
    cvttss2si ebx, xmm1                 ; ebx = samples to write
    test    ebx, ebx
    jz      .done
    lea     rdi, [mix_acc]
    mov     ecx, ebx
    xor     eax, eax
    rep     stosd
    lea     r12, [voices]
    mov     r13d, VOICES
.voice:
    mov     ecx, [r12 + VOICE.remaining]
    test    ecx, ecx
    jz      .next_voice
    cmp     ecx, ebx
    cmova   ecx, ebx                    ; m = min(remaining, samples)
    mov     r14d, ecx
    mov     rsi, [r12 + VOICE.ptr]
    mov     edx, [r12 + VOICE.vol]
    lea     rdi, [mix_acc]
.mix:
    movsx   eax, word [rsi]
    imul    eax, edx
    add     [rdi], eax
    add     rsi, 2
    add     rdi, 4
    dec     ecx
    jnz     .mix
    mov     [r12 + VOICE.ptr], rsi
    sub     [r12 + VOICE.remaining], r14d
.next_voice:
    add     r12, VOICE_size
    dec     r13d
    jnz     .voice
    mov     eax, [settings + SETTINGS.volume]
    shl     eax, 8
    cdq
    mov     ecx, 100
    idiv    ecx
    mov     r8d, eax                    ; master = volume * 256 / 100
    mov     r9d, 32767
    mov     r10d, -32767
    lea     rsi, [mix_acc]
    lea     rdi, [mix_buf]
    mov     ecx, ebx
.out:
    mov     eax, [rsi]
    sar     eax, 8                      ; sum of s * vol, back to sample scale
    imul    eax, r8d
    sar     eax, 8                      ; master volume
    cmp     eax, r9d
    cmovg   eax, r9d
    cmp     eax, r10d
    cmovl   eax, r10d
    mov     [rdi], ax
    add     rsi, 4
    add     rdi, 2
    dec     ecx
    jnz     .out
    mov     rdi, [pa_handle]
    lea     rsi, [mix_buf]
    lea     rdx, [rbx*2]                ; bytes
    lea     rcx, [pa_err]
    call    pa_simple_write
.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
.off:
    ret

; audio_play(edi snd, xmm0 vol): vol clamped to 0..1, played on a free voice (else steals one)
audio_play:
    cmp     dword [audio_enabled], 0
    je      .off
    xorps   xmm1, xmm1
    maxss   xmm0, xmm1
    minss   xmm0, [c_one]
    mulss   xmm0, [c_256]
    cvttss2si esi, xmm0                 ; vol 0..256
    jmp     start_voice
.off:
    ret

; audio_play_at(edi snd, xmm0 x, xmm1 y, xmm2 z, xmm3 vol): audio_play, faded by the distance
; from the player's eye (silent at 16 blocks)
audio_play_at:
    cmp     dword [audio_enabled], 0
    je      .off
    push    rbp
    mov     rbp, rsp
    sub     rsp, 48                     ; [rsp] eye[3], then snd, x, y, z, vol
    mov     [rsp + 16], edi
    movss   [rsp + 20], xmm0
    movss   [rsp + 24], xmm1
    movss   [rsp + 28], xmm2
    movss   [rsp + 32], xmm3
    mov     rdi, rsp
    call    player_eye
    movss   xmm0, [rsp + 20]
    subss   xmm0, [rsp]
    movss   xmm1, [rsp + 24]
    subss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 28]
    subss   xmm2, [rsp + 8]
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    mulss   xmm2, xmm2
    addss   xmm0, xmm1
    addss   xmm0, xmm2
    sqrtss  xmm0, xmm0                  ; distance
    mulss   xmm0, [c_inv_range]
    movss   xmm1, [c_one]
    subss   xmm1, xmm0
    xorps   xmm2, xmm2
    maxss   xmm1, xmm2                  ; max(0, 1 - d / 16)
    mulss   xmm1, [rsp + 32]
    movaps  xmm0, xmm1
    mov     edi, [rsp + 16]
    leave
    jmp     audio_play                  ; a vol that comes to 0 starts nothing
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

; start_voice(edi snd, esi vol 0..256): leaf. Claims a free voice, else the one with the least
; samples remaining, for sfx_table[snd]. Out-of-range snd or a vol of 0 starts nothing.
start_voice:
    cmp     edi, NUM_SOUNDS
    jae     .ret
    test    esi, esi
    jle     .ret
    lea     r8, [voices]
    mov     r9, r8                      ; steal candidate
    mov     r10d, 0x7FFFFFFF            ; its remaining
    mov     ecx, VOICES
.scan:
    mov     eax, [r8 + VOICE.remaining]
    test    eax, eax
    jz      .claim                      ; free voice
    cmp     eax, r10d
    jge     .next
    mov     r10d, eax
    mov     r9, r8
.next:
    add     r8, VOICE_size
    dec     ecx
    jnz     .scan
    mov     r8, r9
.claim:
    mov     edi, edi
    lea     r11, [sfx_table]
    mov     edx, [r11 + rdi*8]          ; offset, samples
    mov     eax, [r11 + rdi*8 + 4]      ; length
    lea     r11, [sfx_pool]
    lea     rdx, [r11 + rdx*2]
    mov     [r8 + VOICE.ptr], rdx
    mov     [r8 + VOICE.remaining], eax
    mov     [r8 + VOICE.vol], esi
.ret:
    ret
