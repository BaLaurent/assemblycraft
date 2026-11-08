; sleep.asm - beds: a right click on a bed sets the respawn point and, at night with no monster
; near, puts the player to sleep (a black fade, then the next morning); the respawn helpers that
; stand the player next to his bed again. All cell coordinates are local unless marked absolute;
; WORLDHDR.bed_x/y/z is the absolute foot cell of the bed.
%include "common.inc"
default rel

global sleep_active, sleep_timer, sleep_fade
global sleep_use_bed, sleep_step, sleep_cancel, sleep_respawn_target, sleep_place_at_bed

extern world_header, world_origin_x, world_origin_z
extern world_get, world_is_solid
extern game_time, sky_is_night
extern mobs, mob_is_hostile
extern player, hud_banner
extern dir_dx, dir_dz

%define SLEEP_STEPS    120              ; steps in bed until the morning
%define BANNER_INFO    RGBA(255, 255, 255, 255)
%define BANNER_WARN    RGBA(255, 150, 90, 255)

section .rodata
align 4
c_half:     dd 0.5
c_bed_top:  dd 0.5625                   ; 9/16: the top of a bed
c_one:      dd 1.0
c_fade_in:  dd 0.011111111             ; 1 / 90: black after 90 steps in bed
c_fade_out: dd 0.033333335             ; 1 / 30: the fade lifts in half a second
c_range2:   dd 64.0                    ; a hostile mob within 8 blocks keeps the player awake
c_range_y:  dd 5.0                     ; ... and within 5 vertically
c_abs_mask: dd 0x7FFFFFFF
s_day:      db "Respawn set. You can only sleep at night", 0
s_mobs:     db "Respawn set. Monsters are nearby", 0
s_sleep:    db "Respawn set. Sleeping...", 0
s_gone:     db "Your bed was missing or obstructed", 0

section .bss
alignb 4
sleep_active: resd 1                    ; 1 while the player lies in a bed
sleep_timer:  resd 1                    ; steps asleep
sleep_fade:   resd 1                    ; float 0..1: how black the screen is

section .text

; stand_at(xmm0 x, xmm1 y, xmm2 z): the player at that feet position, at rest
stand_at:
    movss   [player + BODY.x], xmm0
    movss   [player + BODY.y], xmm1
    movss   [player + BODY.z], xmm2
    xor     eax, eax
    mov     [player + BODY.vx], eax
    mov     [player + BODY.vy], eax
    mov     [player + BODY.vz], eax
    mov     [player + BODY.kbx], eax
    mov     [player + BODY.kbz], eax
    mov     [player + BODY.fall], eax
    mov     dword [player + BODY.on_ground], 1
    ret

; sleep_use_bed(edi x, esi y, edx z) -> eax 1: the player right-clicked the bed cell (x, y, z)
; and block_use did not react (0 if the cell is no bed). The foot is the cell itself or, for a head,
; the cell one step back along its facing. Whatever happens next, the bed becomes the respawn point
; (WORLDHDR.bed_*, the absolute foot cell, bed_set 1). By day the banner says one can only sleep
; at night; at night with a hostile mob within 8 blocks (horizontally) and 5 (vertically) of the
; foot it says monsters are nearby; otherwise sleeping starts (sleep_active, the player lies on
; the bed). The rules are the same in Creative.
; ebx = x, then the mob slot; r12d = y; r13d = z. Frame: foot x @0, y @4, z @8.
sleep_use_bed:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 24
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    call    world_get                   ; edi, esi, edx are still x, y, z
    sub     eax, BED
    cmp     eax, 7
    ja      .not_bed
    mov     ecx, eax                    ; param: bit 2 = head, bits 0..1 = facing
    and     eax, 3
    xor     edx, edx
    xor     esi, esi
    test    ecx, 4
    jz      .have_foot
    movsx   edx, byte [dir_dx + rax]    ; a head: the foot is one cell back
    movsx   esi, byte [dir_dz + rax]
    neg     edx
    neg     esi
.have_foot:
    add     edx, ebx
    add     esi, r13d
    mov     [rsp], edx
    mov     [rsp + 4], r12d
    mov     [rsp + 8], esi
    add     edx, [world_origin_x]       ; the respawn point: the absolute foot cell
    mov     [world_header + WORLDHDR.bed_x], edx
    mov     [world_header + WORLDHDR.bed_y], r12d
    add     esi, [world_origin_z]
    mov     [world_header + WORLDHDR.bed_z], esi
    mov     dword [world_header + WORLDHDR.bed_set], 1
    mov     edi, [game_time]
    call    sky_is_night
    test    eax, eax
    jnz     .night
    lea     rdi, [s_day]
    jmp     .banner
.night:
    xor     ebx, ebx                    ; mob slot
.mob:
    mov     edi, ebx
    call    mob_is_hostile
    test    eax, eax
    jz      .next_mob
    imul    eax, ebx, MOB_size
    lea     rcx, [mobs]
    add     rcx, rax
    movss   xmm0, [rcx + BODY.x]
    cvtsi2ss xmm1, dword [rsp]
    addss   xmm1, [c_half]
    subss   xmm0, xmm1
    mulss   xmm0, xmm0                  ; dx^2
    movss   xmm2, [rcx + BODY.z]
    cvtsi2ss xmm1, dword [rsp + 8]
    addss   xmm1, [c_half]
    subss   xmm2, xmm1
    mulss   xmm2, xmm2                  ; dz^2
    addss   xmm0, xmm2
    ucomiss xmm0, [c_range2]
    ja      .next_mob
    movss   xmm0, [rcx + BODY.y]
    cvtsi2ss xmm1, dword [rsp + 4]
    subss   xmm0, xmm1
    movss   xmm1, [c_abs_mask]
    andps   xmm1, xmm0                  ; |dy|
    ucomiss xmm1, [c_range_y]
    jbe     .monsters
.next_mob:
    inc     ebx
    cmp     ebx, MAX_MOBS
    jb      .mob
    mov     dword [sleep_active], 1     ; nothing in the way: to bed
    mov     dword [sleep_timer], 0
    mov     dword [sleep_fade], 0
    cvtsi2ss xmm0, dword [rsp]
    addss   xmm0, [c_half]
    cvtsi2ss xmm1, dword [rsp + 4]
    addss   xmm1, [c_bed_top]
    cvtsi2ss xmm2, dword [rsp + 8]
    addss   xmm2, [c_half]
    call    stand_at
    lea     rdi, [s_sleep]
    jmp     .banner
.monsters:
    lea     rdi, [s_mobs]
.banner:
    mov     esi, BANNER_INFO
    call    hud_banner
    mov     eax, 1
    jmp     .out
.not_bed:
    xor     eax, eax
.out:
    add     rsp, 24
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; sleep_step(): one fixed step. While asleep the timer counts and the fade climbs to 1 over 90
; steps; at step 120 it is morning (game_time becomes the start of the next day, 06:00) and the
; player is awake; the fade then falls by 1/30 per step back to 0.
sleep_step:
    sub     rsp, 8
    cmp     dword [sleep_active], 0
    je      .awake
    inc     dword [sleep_timer]
    mov     eax, [sleep_timer]
    cvtsi2ss xmm0, eax
    mulss   xmm0, [c_fade_in]
    minss   xmm0, [c_one]
    movss   [sleep_fade], xmm0
    cmp     eax, SLEEP_STEPS
    jb      .ret
    mov     eax, [game_time]
    xor     edx, edx
    mov     ecx, DAY_LENGTH
    div     ecx
    inc     eax
    imul    eax, eax, DAY_LENGTH
    mov     [game_time], eax
    mov     dword [sleep_active], 0
    mov     dword [sleep_timer], 0
    jmp     .ret
.awake:
    movss   xmm0, [sleep_fade]
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jbe     .ret
    subss   xmm0, [c_fade_out]
    maxss   xmm0, xmm1
    movss   [sleep_fade], xmm0
.ret:
    add     rsp, 8
    ret

; sleep_cancel(): wake up now: no sleep, no fade; the time is left alone
sleep_cancel:
    mov     dword [sleep_active], 0
    mov     dword [sleep_timer], 0
    mov     dword [sleep_fade], 0
    ret

; sleep_respawn_target(rdi out dd[3]) -> eax 1 when a bed is set: out = its foot cell (local)
sleep_respawn_target:
    xor     eax, eax
    cmp     dword [world_header + WORLDHDR.bed_set], 0
    je      .ret
    mov     ecx, [world_header + WORLDHDR.bed_x]
    sub     ecx, [world_origin_x]
    mov     [rdi], ecx
    mov     ecx, [world_header + WORLDHDR.bed_y]
    mov     [rdi + 4], ecx
    mov     ecx, [world_header + WORLDHDR.bed_z]
    sub     ecx, [world_origin_z]
    mov     [rdi + 8], ecx
    mov     eax, 1
.ret:
    ret

; sleep_place_at_bed() -> eax 1 placed / 0: the player stands next to his bed (the area around it
; is loaded). The foot cell must hold BED..BED+3. He stands on the first of the four horizontal
; neighbours of the foot (N, E, S, W), then of the head, whose cell and the cell above are not
; solid and whose cell below is; else on top of the foot when the two cells above it are free.
; Otherwise (and with the bed gone) bed_set is cleared, the banner says so and the result is 0.
; ebx = candidate 0..7 (bit 2: around the head, bits 0..1: direction), r12d/r13d = its x / z.
; Frame: foot x @0, y @4, z @8, facing @12, head x @16, z @20.
sleep_place_at_bed:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 40
    xor     eax, eax
    cmp     dword [world_header + WORLDHDR.bed_set], 0
    je      .out
    mov     eax, [world_header + WORLDHDR.bed_x]
    sub     eax, [world_origin_x]
    mov     [rsp], eax
    mov     eax, [world_header + WORLDHDR.bed_y]
    mov     [rsp + 4], eax
    mov     eax, [world_header + WORLDHDR.bed_z]
    sub     eax, [world_origin_z]
    mov     [rsp + 8], eax
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    mov     edx, [rsp + 8]
    call    world_get
    sub     eax, BED
    cmp     eax, 3
    ja      .gone                       ; the foot must hold BED..BED+3
    mov     [rsp + 12], eax
    movsx   ecx, byte [dir_dx + rax]
    add     ecx, [rsp]
    mov     [rsp + 16], ecx
    movsx   ecx, byte [dir_dz + rax]
    add     ecx, [rsp + 8]
    mov     [rsp + 20], ecx
    xor     ebx, ebx
.cand:
    mov     eax, ebx
    and     eax, 3
    movsx   r12d, byte [dir_dx + rax]
    movsx   r13d, byte [dir_dz + rax]
    mov     ecx, [rsp]
    mov     edx, [rsp + 8]
    test    ebx, 4
    jz      .around
    mov     ecx, [rsp + 16]
    mov     edx, [rsp + 20]
.around:
    add     r12d, ecx
    add     r13d, edx
    mov     edi, r12d
    mov     esi, [rsp + 4]
    mov     edx, r13d
    call    world_is_solid
    test    eax, eax
    jnz     .next                       ; the cell itself must be free ...
    mov     edi, r12d
    mov     esi, [rsp + 4]
    inc     esi
    mov     edx, r13d
    call    world_is_solid
    test    eax, eax
    jnz     .next                       ; ... and the one above ...
    mov     edi, r12d
    mov     esi, [rsp + 4]
    dec     esi
    mov     edx, r13d
    call    world_is_solid
    test    eax, eax
    jz      .next                       ; ... and the floor solid
    cvtsi2ss xmm0, r12d
    addss   xmm0, [c_half]
    cvtsi2ss xmm1, dword [rsp + 4]
    cvtsi2ss xmm2, r13d
    addss   xmm2, [c_half]
    call    stand_at
    jmp     .placed
.next:
    inc     ebx
    cmp     ebx, 8
    jb      .cand
    mov     edi, [rsp]                  ; on top of the bed: two free cells above the foot
    mov     esi, [rsp + 4]
    inc     esi
    mov     edx, [rsp + 8]
    call    world_is_solid
    test    eax, eax
    jnz     .gone
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    add     esi, 2
    mov     edx, [rsp + 8]
    call    world_is_solid
    test    eax, eax
    jnz     .gone
    cvtsi2ss xmm0, dword [rsp]
    addss   xmm0, [c_half]
    cvtsi2ss xmm1, dword [rsp + 4]
    addss   xmm1, [c_bed_top]
    cvtsi2ss xmm2, dword [rsp + 8]
    addss   xmm2, [c_half]
    call    stand_at
.placed:
    mov     eax, 1
    jmp     .out
.gone:
    mov     dword [world_header + WORLDHDR.bed_set], 0
    lea     rdi, [s_gone]
    mov     esi, BANNER_WARN
    call    hud_banner
    xor     eax, eax
.out:
    add     rsp, 40
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
