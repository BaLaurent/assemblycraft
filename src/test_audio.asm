; test_audio.asm - the chip sound pool (every sound starts and ends without a click and fits the
; pool) and the stereo mixer (positional panning, per-sound voice caps, pitch jitter that leaves
; the game RNG alone, and the limiter ceiling).
%include "common.inc"
default rel

global test_sfx_clean_edges, test_audio_pan, test_audio_caps_jitter_limiter

extern sfx_build, sfx_table, sfx_pool
extern audio_mix, audio_reset, audio_enabled, audio_play, audio_play_at, voices
extern settings, player, rng_seed, rng_next

; SETF mem, float literal
%macro SETF 2
    mov     dword %1, __float32__(%2)
%endmacro

; IABS reg32, tmp32: reg = |reg|
%macro IABS 2
    mov     %2, %1
    sar     %2, 31
    xor     %1, %2
    sub     %1, %2
%endmacro

%define MIX_FRAMES 2048

section .rodata
align 4
k_one:    dd 1.0
k_eye_y:  dd 11.62                      ; eye height of a player standing at y 10
k_0_5:    dd 0.5
k_4_5:    dd 4.5                        ; 4 blocks to +x / +z of the player
k_m3_5:   dd -3.5                       ; 4 blocks to -x / -z
k_r_lo:   dd 0.37                       ; far ear / near ear at the full 0.6 pan: 0.4
k_r_hi:   dd 0.43
k_0_01:   dd 0.01
k_abs:    dd 0x7FFFFFFF
; the 16-voice stress scene, all within their sounds' caps
lim_set:
    db SND_EXPLODE, SND_EXPLODE, SND_EXPLODE, SND_SHOTGUN, SND_SHOTGUN, SND_MUSKET, SND_MUSKET
    db SND_PISTOL, SND_PISTOL, SND_PISTOL, SND_SLAM, SND_BOSS_ROAR, SND_LAUNCHER, SND_LAUNCHER
    db SND_HEAVY, SND_CRIT
align 2
flat_buf: times 64 dw 20000             ; negative control: starts at full level (onset click)
ramp_buf:                               ; negative control: ends at full level (tail click)
%assign i 0
%rep 64
    dw (i * 20000) / 63
%assign i i + 1
%endrep

section .bss
alignb 16
tbuf:      resw 2 * MIX_FRAMES          ; audio_mix output, interleaved L,R
saved_vol: resd 1

section .text

; edge_ok(rdi int16 *x, esi len) -> eax 0 when the sound peaks at 1000 or more, starts within
; peak / 64 and ends within peak / 32. Leaf.
edge_ok:
    xor     ecx, ecx
    xor     r8d, r8d                    ; peak |x|
.peak:
    cmp     ecx, esi
    jae     .edges
    movsx   eax, word [rdi + rcx*2]
    IABS    eax, edx
    cmp     eax, r8d
    cmova   r8d, eax
    inc     ecx
    jmp     .peak
.edges:
    mov     eax, 1
    cmp     r8d, 1000
    jb      .ret
    movsx   edx, word [rdi]
    IABS    edx, ecx
    shl     edx, 6
    cmp     edx, r8d
    ja      .ret                        ; |x[0]| > peak / 64
    lea     ecx, [rsi - 1]
    movsx   edx, word [rdi + rcx*2]
    IABS    edx, ecx
    shl     edx, 5
    cmp     edx, r8d
    ja      .ret                        ; |x[len - 1]| > peak / 32
    xor     eax, eax
.ret:
    ret

; test_sfx_clean_edges: every sound has 0 < len <= SOUND_MAX_SAMPLES and clean edges, the pool
; holds them all, and edge_ok rejects an onset click and a tail click
test_sfx_clean_edges:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    call    sfx_build
    mov     ebx, 1
    xor     r12d, r12d                  ; sound id
    xor     r13d, r13d                  ; total samples
.sound:
    lea     rax, [sfx_table]
    mov     ecx, [rax + r12*8]          ; offset
    mov     esi, [rax + r12*8 + 4]      ; length
    test    esi, esi
    jz      .out
    cmp     esi, SOUND_MAX_SAMPLES
    ja      .out
    add     r13d, esi
    lea     rdi, [sfx_pool]
    lea     rdi, [rdi + rcx*2]
    call    edge_ok
    test    eax, eax
    jnz     .out
    inc     r12d
    cmp     r12d, NUM_SOUNDS
    jb      .sound
    mov     ebx, 2
    cmp     r13d, POOL_SAMPLES
    ja      .out
    mov     ebx, 3
    lea     rdi, [flat_buf]
    mov     esi, 64
    call    edge_ok
    test    eax, eax
    jz      .out
    mov     ebx, 4
    lea     rdi, [ramp_buf]
    mov     esi, 64
    call    edge_ok
    test    eax, eax
    jz      .out
    xor     ebx, ebx
.out:
    mov     eax, ebx
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mix_setup: pool built, audio on at volume 100, mixer reset
mix_setup:
    sub     rsp, 8
    call    sfx_build
    mov     eax, [settings + SETTINGS.volume]
    mov     [saved_vol], eax
    mov     dword [settings + SETTINGS.volume], 100
    mov     dword [audio_enabled], 1
    call    audio_reset
    add     rsp, 8
    ret

; mix_teardown: volume restored, audio off, mixer silent
mix_teardown:
    sub     rsp, 8
    mov     eax, [saved_vol]
    mov     [settings + SETTINGS.volume], eax
    mov     dword [audio_enabled], 0
    call    audio_reset
    add     rsp, 8
    ret

; mix_sums(esi frames) -> xmm0 sum |L|, xmm1 sum |R| of audio_mix(tbuf, frames)
mix_sums:
    push    rbx
    mov     ebx, esi
    lea     rdi, [tbuf]
    call    audio_mix
    lea     rsi, [tbuf]
    xor     r8d, r8d
    xor     r9d, r9d
    xor     ecx, ecx
.frame:
    cmp     ecx, ebx
    jae     .done
    movsx   eax, word [rsi + rcx*4]
    IABS    eax, edx
    add     r8, rax
    movsx   eax, word [rsi + rcx*4 + 2]
    IABS    eax, edx
    add     r9, rax
    inc     ecx
    jmp     .frame
.done:
    cvtsi2ss xmm0, r8
    cvtsi2ss xmm1, r9
    pop     rbx
    ret

; pan_case(xmm0 x, xmm1 z) -> xmm0 sum |L|, xmm1 sum |R|: a CLICK at eye height, mixed alone
pan_case:
    sub     rsp, 24
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    call    audio_reset
    mov     edi, SND_CLICK
    movss   xmm0, [rsp]
    movss   xmm1, [k_eye_y]
    movss   xmm2, [rsp + 4]
    movss   xmm3, [k_one]
    call    audio_play_at
    mov     esi, 1102
    call    mix_sums
    add     rsp, 24
    ret

; ratio_ok(xmm0 a, xmm1 b) -> eax 0 when b > 0 and a / b lies in [0.37, 0.43]
ratio_ok:
    mov     eax, 1
    xorps   xmm2, xmm2
    ucomiss xmm1, xmm2
    jbe     .ret
    divss   xmm0, xmm1
    ucomiss xmm0, [k_r_lo]
    jb      .ret
    ucomiss xmm0, [k_r_hi]
    ja      .ret
    xor     eax, eax
.ret:
    ret

; test_audio_pan: a source 4 blocks to the player's right is louder on the right by the full pan,
; one to the left mirrors it, one straight ahead is centred, and turning 90 degrees moves the
; right side onto +z
test_audio_pan:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    mix_setup
    SETF    [player + BODY.x], 0.5
    SETF    [player + BODY.y], 10.0
    SETF    [player + BODY.z], 0.5
    SETF    [player + BODY.yaw], 0.0
    mov     ebx, 1                      ; +x at yaw 0: L / R
    movss   xmm0, [k_4_5]
    movss   xmm1, [k_0_5]
    call    pan_case
    call    ratio_ok
    test    eax, eax
    jnz     .out
    mov     ebx, 2                      ; -x: R / L
    movss   xmm0, [k_m3_5]
    movss   xmm1, [k_0_5]
    call    pan_case
    movaps  xmm2, xmm0
    movaps  xmm0, xmm1
    movaps  xmm1, xmm2
    call    ratio_ok
    test    eax, eax
    jnz     .out
    mov     ebx, 3                      ; -z, straight ahead: |L - R| <= 1 % of L
    movss   xmm0, [k_0_5]
    movss   xmm1, [k_m3_5]
    call    pan_case
    xorps   xmm2, xmm2
    ucomiss xmm0, xmm2
    jbe     .out                        ; heard at all
    movaps  xmm2, xmm0
    subss   xmm2, xmm1
    movss   xmm3, [k_abs]
    andps   xmm2, xmm3
    mulss   xmm0, [k_0_01]
    ucomiss xmm2, xmm0
    ja      .out
    mov     ebx, 4                      ; yaw 90, +z: L / R
    SETF    [player + BODY.yaw], 90.0
    movss   xmm0, [k_0_5]
    movss   xmm1, [k_4_5]
    call    pan_case
    call    ratio_ok
    test    eax, eax
    jnz     .out
    xor     ebx, ebx
.out:
    SETF    [player + BODY.yaw], 0.0
    call    mix_teardown
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; test_audio_caps_jitter_limiter: STEP_STONE x4 holds its cap of 2 voices with two different
; jittered steps within +-300 cents; LEVELUP (jitter 0) plays at exactly 1.0; playing a sound does
; not move the game RNG; 16 loud sounds at once stay under the limiter ceiling and reach 20000
test_audio_caps_jitter_limiter:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    call    mix_setup
    mov     r12d, 4
.steps:
    mov     edi, SND_STEP_STONE
    movss   xmm0, [k_one]
    call    audio_play
    dec     r12d
    jnz     .steps
    lea     r8, [voices]
    mov     ecx, VOICES
    xor     r9d, r9d                    ; voices holding STEP_STONE
    xor     r10d, r10d                  ; their steps
    xor     r11d, r11d
.scan:
    cmp     dword [r8 + VOICE.len], 0
    je      .scan_next
    cmp     dword [r8 + VOICE.snd], SND_STEP_STONE
    jne     .scan_next
    inc     r9d
    mov     rax, [r8 + VOICE.step]
    cmp     r9d, 1
    cmove   r10, rax
    cmovne  r11, rax
.scan_next:
    add     r8, VOICE_size
    dec     ecx
    jnz     .scan
    mov     ebx, 1
    cmp     r9d, 2
    jne     .out
    mov     ebx, 2
    cmp     r10, r11
    je      .out
    mov     ebx, 3                      ; 2^32 * 2^(+-300 / 1200), +-1024 for float precision
    mov     rax, 3611621578
    cmp     r10, rax
    jb      .out
    cmp     r11, rax
    jb      .out
    mov     rax, 5107606691
    cmp     r10, rax
    ja      .out
    cmp     r11, rax
    ja      .out
    mov     ebx, 4                      ; LEVELUP: no jitter
    mov     edi, SND_LEVELUP
    movss   xmm0, [k_one]
    call    audio_play
    lea     r8, [voices]
    mov     ecx, VOICES
    xor     r10d, r10d
.find:
    cmp     dword [r8 + VOICE.len], 0
    je      .find_next
    cmp     dword [r8 + VOICE.snd], SND_LEVELUP
    cmove   r10, r8
.find_next:
    add     r8, VOICE_size
    dec     ecx
    jnz     .find
    test    r10, r10
    jz      .out
    mov     rax, 1 << 32
    cmp     [r10 + VOICE.step], rax
    jne     .out
    mov     ebx, 5                      ; the game RNG does not move
    mov     edi, 1234
    call    rng_seed
    call    rng_next
    mov     r12d, eax
    mov     edi, 1234
    call    rng_seed
    mov     edi, SND_STEP_STONE
    movss   xmm0, [k_one]
    call    audio_play
    call    rng_next
    cmp     eax, r12d
    jne     .out
    mov     ebx, 6                      ; limiter: 16 loud voices
    call    audio_reset
    lea     r12, [lim_set]
    mov     r13d, 16
.loud:
    movzx   edi, byte [r12]
    movss   xmm0, [k_one]
    call    audio_play
    inc     r12
    dec     r13d
    jnz     .loud
    lea     r8, [voices]                ; control: all 16 really started
    mov     ecx, VOICES
    xor     r9d, r9d
.count:
    cmp     dword [r8 + VOICE.len], 0
    je      .count_next
    inc     r9d
.count_next:
    add     r8, VOICE_size
    dec     ecx
    jnz     .count
    cmp     r9d, 16
    jne     .out
    mov     ebx, 7
    lea     rdi, [tbuf]
    mov     esi, MIX_FRAMES
    call    audio_mix
    lea     rsi, [tbuf]
    xor     ecx, ecx
    xor     r8d, r8d                    ; max |sample|
.sample:
    movsx   eax, word [rsi + rcx*2]
    IABS    eax, edx
    cmp     eax, 29206
    ja      .out
    cmp     eax, r8d
    cmova   r8d, eax
    inc     ecx
    cmp     ecx, 2 * MIX_FRAMES
    jb      .sample
    mov     ebx, 8                      ; control: the scene really drives the limiter
    cmp     r8d, 20000
    jb      .out
    xor     ebx, ebx
.out:
    call    mix_teardown
    mov     eax, ebx
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
