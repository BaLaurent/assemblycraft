; test_survival.asm - survival rules and day/night cycle tests.
%include "common.inc"
default rel

global test_fall_damage, test_exhaustion_drains, test_regen_when_fed
global test_damage_invulnerability, test_starvation_floor, test_sky_day_cycle
global test_armor_reduces_damage
global test_breath_and_drowning, test_sleep_rules

extern surv, survival_reset, survival_damage, survival_land, survival_exhaust, survival_step
extern surv_max_health
extern sky_brightness, sky_is_night
extern game_mode, settings, world_clear
extern inv, inv_clear, armor_points
extern player, world_set, world_header, game_time
extern mobs_clear, mob_spawn
extern sleep_use_bed, sleep_step, sleep_cancel, sleep_active, sleep_fade
extern boats, boat_riding, boats_clear, boats_mount
extern banner_text, str_eq, hud_bubble_tiles

section .rodata
align 4
k_eps:   dd 0.0001
k_0_5:   dd 0.5
k_3_0:   dd 3.0
k_5_0:   dd 5.0
k_3_5:   dd 3.5
k_8_0:   dd 8.0
k_8_5:   dd 8.5
k_1_0:   dd 1.0
k_0_625: dd 0.625
k_0_25:  dd 0.25

section .bss
align 4
inp: resb INPUT_size                    ; zero input for survival_step

section .text

; fail unless |float at %1 - float constant %2| < 1e-4
%macro FNEAR 2
    movss   xmm0, %1
    subss   xmm0, [%2]
    andps   xmm0, [absmask]
    ucomiss xmm0, [k_eps]
    jae     .fail
%endmacro

section .rodata
align 16
absmask: dd 0x7FFFFFFF, 0, 0, 0
align 4
k_5_5:   dd 5.5
k_10_5625: dd 10.5625
k_10_0:  dd 10.0
k_4_5:   dd 4.5
k_6_5:   dd 6.5
s_b_day:   db "Respawn set. You can only sleep at night", 0
s_b_mobs:  db "Respawn set. Monsters are nearby", 0
s_b_sleep: db "Respawn set. Sleeping...", 0
s_b_blocked: db "Respawn set. The bed is obstructed", 0

%define TB TILE_BUBBLE
%define TP TILE_BUBBLE_POP
; hud_bubble_tiles cases: breath, then the ten tiles (bubble 0 is the rightmost), two pad bytes
%define BUBBLE_ROWS 8
bubble_rows:
    dd 600
    db TB, TB, TB, TB, TB, TB, TB, TB, TB, TB, 0, 0
    dd 330
    db TB, TB, TB, TB, TB, TP, 0, 0, 0, 0, 0, 0
    dd 599
    db TB, TB, TB, TB, TB, TB, TB, TB, TB, TP, 0, 0
    dd 540
    db TB, TB, TB, TB, TB, TB, TB, TB, TB, 0, 0, 0
    dd 60
    db TB, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    dd 59
    db TP, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    dd 1
    db TP, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    dd 0
    db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
section .text

; setup(): empty world, survival mode, normal difficulty, fresh state, zero input
setup:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    call    survival_reset
    lea     rdi, [inp]
    mov     ecx, INPUT_size
    xor     eax, eax
    rep     stosb
    pop     rbp
    ret

; steps(edi n): n times survival_step(&inp, 0.0, 0)
steps:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
.loop:
    lea     rdi, [inp]
    xorps   xmm0, xmm0
    xor     esi, esi
    call    survival_step
    dec     ebx
    jnz     .loop
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

test_fall_damage:
    push    rbp
    mov     rbp, rsp
    call    setup
    movss   xmm0, [k_5_0]
    call    survival_land
    cmp     dword [surv + SURVIVAL.health], 18
    jne     .fail
    mov     dword [surv + SURVIVAL.invuln], 0
    movss   xmm0, [k_3_0]
    call    survival_land
    cmp     dword [surv + SURVIVAL.health], 18
    jne     .fail
    mov     dword [surv + SURVIVAL.invuln], 0
    movss   xmm0, [k_3_5]
    call    survival_land
    cmp     dword [surv + SURVIVAL.health], 17
    jne     .fail
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret

test_exhaustion_drains:
    push    rbp
    mov     rbp, rsp
    call    setup
    movss   xmm0, [k_8_5]
    call    survival_exhaust
    mov     edi, 1
    call    steps
    FNEAR   [surv + SURVIVAL.exhaustion], k_0_5
    FNEAR   [surv + SURVIVAL.saturation], k_3_0
    cmp     dword [surv + SURVIVAL.food], 20
    jne     .fail
    mov     dword [surv + SURVIVAL.saturation], 0
    movss   xmm0, [k_8_0]
    call    survival_exhaust
    mov     edi, 1
    call    steps
    cmp     dword [surv + SURVIVAL.food], 18
    jne     .fail
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret

test_regen_when_fed:
    push    rbp
    mov     rbp, rsp
    call    setup
    mov     dword [surv + SURVIVAL.health], 10
    mov     edi, 240
    call    steps
    cmp     dword [surv + SURVIVAL.health], 11
    jne     .fail
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret

test_damage_invulnerability:
    push    rbp
    mov     rbp, rsp
    call    setup
    mov     edi, 4
    mov     esi, CAUSE_ZOMBIE
    call    survival_damage
    cmp     eax, 1
    jne     .fail
    cmp     dword [surv + SURVIVAL.health], 16
    jne     .fail
    mov     edi, 4
    mov     esi, CAUSE_ZOMBIE
    call    survival_damage
    test    eax, eax
    jnz     .fail
    cmp     dword [surv + SURVIVAL.health], 16
    jne     .fail
    mov     edi, 30
    call    steps
    mov     edi, 4
    mov     esi, CAUSE_ZOMBIE
    call    survival_damage
    cmp     dword [surv + SURVIVAL.health], 12
    jne     .fail
    mov     dword [game_mode], MODE_CREATIVE
    mov     dword [surv + SURVIVAL.invuln], 0
    mov     edi, 4
    mov     esi, CAUSE_ZOMBIE
    call    survival_damage
    test    eax, eax
    jnz     .fail
    cmp     dword [surv + SURVIVAL.health], 12
    jne     .fail
    mov     dword [game_mode], MODE_SURVIVAL
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     dword [game_mode], MODE_SURVIVAL
    mov     eax, 1
    pop     rbp
    ret

test_starvation_floor:
    push    rbp
    mov     rbp, rsp
    call    setup
    mov     dword [surv + SURVIVAL.food], 0
    mov     dword [surv + SURVIVAL.saturation], 0
    mov     dword [surv + SURVIVAL.health], 3
    mov     edi, 1200
    call    steps
    cmp     dword [surv + SURVIVAL.health], 1
    jne     .fail
    call    setup                       ; max 30: a tick is round(30/20) = 2 and must not cross the floor
    mov     dword [surv_max_health], 30
    mov     dword [surv + SURVIVAL.food], 0
    mov     dword [surv + SURVIVAL.saturation], 0
    mov     dword [surv + SURVIVAL.health], 2
    mov     edi, 1200
    call    steps
    cmp     dword [surv + SURVIVAL.health], 2
    jne     .fail
    cmp     dword [surv + SURVIVAL.dead], 0
    jne     .fail
    mov     dword [surv + SURVIVAL.health], 3
    mov     edi, 1200
    call    steps
    cmp     dword [surv + SURVIVAL.health], 1
    jne     .fail
    cmp     dword [surv + SURVIVAL.dead], 0
    jne     .fail
    mov     dword [surv_max_health], 20
    call    setup
    mov     dword [settings + SETTINGS.difficulty], DIFF_HARD
    mov     dword [surv + SURVIVAL.food], 0
    mov     dword [surv + SURVIVAL.saturation], 0
    mov     dword [surv + SURVIVAL.health], 2
    mov     edi, 480
    call    steps
    cmp     dword [surv + SURVIVAL.health], 0
    jne     .fail
    cmp     dword [surv + SURVIVAL.dead], 1
    jne     .fail
    cmp     dword [surv + SURVIVAL.death_cause], CAUSE_STARVE
    jne     .fail
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     dword [surv_max_health], 20
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    mov     eax, 1
    pop     rbp
    ret

; BRIGHT time, constant: fail unless sky_brightness(time) is within 1e-4 of it
%macro BRIGHT 2
    mov     edi, %1
    call    sky_brightness
    movss   [rsp], xmm0
    FNEAR   [rsp], %2
%endmacro

test_sky_day_cycle:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 16
    BRIGHT  0, k_1_0
    BRIGHT  36000, k_0_625
    BRIGHT  54000, k_0_25
    BRIGHT  70200, k_0_625
    BRIGHT  72000, k_1_0
    mov     edi, 54000
    call    sky_is_night
    cmp     eax, 1
    jne     .fail
    mov     edi, 6000
    call    sky_is_night
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    leave
    ret
.fail:
    mov     eax, 1
    leave
    ret

; set the four armor slots to ids %1..%1+3, count 1, dmg 0
%macro WEAR 1
    mov     dword [inv + INVENTORY.armor + 0], (%1) | (1 << 8)
    mov     dword [inv + INVENTORY.armor + 4], (%1 + 1) | (1 << 8)
    mov     dword [inv + INVENTORY.armor + 8], (%1 + 2) | (1 << 8)
    mov     dword [inv + INVENTORY.armor + 12], (%1 + 3) | (1 << 8)
%endmacro

; Full diamond (20 points) turns a 3-damage zombie hit into 1 and wears nothing (gear never wears);
; falls ignore armor; full iron (15 points) turns a 10-damage blast into 4.
test_armor_reduces_damage:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    setup
    call    inv_clear
    WEAR    DIAMOND_HELMET
    call    armor_points
    cmp     eax, 20
    jne     .fail
    mov     edi, 3
    mov     esi, CAUSE_ZOMBIE
    call    survival_damage
    cmp     dword [surv + SURVIVAL.health], 19
    jne     .fail
    xor     ebx, ebx
.wear:
    cmp     word [inv + INVENTORY.armor + rbx*4 + ITEMSTACK.dmg], 0     ; no piece took damage
    jne     .fail
    inc     ebx
    cmp     ebx, 4
    jb      .wear
    mov     dword [surv + SURVIVAL.invuln], 0
    mov     edi, 5
    mov     esi, CAUSE_FALL
    call    survival_damage
    cmp     dword [surv + SURVIVAL.health], 14
    jne     .fail
    WEAR    IRON_HELMET
    call    armor_points
    cmp     eax, 15
    jne     .fail
    mov     dword [surv + SURVIVAL.invuln], 0
    mov     edi, 10
    mov     esi, CAUSE_EXPLOSION
    call    survival_damage
    cmp     dword [surv + SURVIVAL.health], 10
    jne     .fail
    call    inv_clear
    xor     eax, eax
    jmp     .ret
.fail:
    call    inv_clear
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; SETF mem, float literal
%macro SETF 2
    mov     dword %1, __float32__(%2)
%endmacro

; ---- breath and drowning ---------------------------------------------------------

; Under water (the eye cell is WATER) the breath runs 600 -> 0 over 600 steps without harm; then 1
; drowning damage every 60 steps (the first on step 659). In the air it comes back 5 a step up to
; 600. Drowning is environmental damage (scaled to the maximum health: 2 at 40) and kills with
; CAUSE_DROWN. survival_reset fills the lung. hud_bubble_tiles: 330 -> 5 bubbles, 1 pop, 4 none.
test_breath_and_drowning:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 24                     ; [rsp] the ten tiles of hud_bubble_tiles
    call    setup
    SETF    [player + BODY.x], 8.5
    SETF    [player + BODY.y], 10.0
    SETF    [player + BODY.z], 8.5
    cmp     dword [surv + SURVIVAL.breath], MAX_BREATH
    jne     .fail
    mov     edi, 100                    ; dry: nothing changes
    call    steps
    cmp     dword [surv + SURVIVAL.breath], MAX_BREATH
    jne     .fail
    mov     edi, 8
    mov     esi, 11
    mov     edx, 8
    mov     ecx, WATER
    call    world_set                   ; the eye (y 11.62) is in water
    mov     edi, 599
    call    steps
    cmp     dword [surv + SURVIVAL.breath], 1
    jne     .fail
    cmp     dword [surv + SURVIVAL.health], 20
    jne     .fail
    mov     edi, 1
    call    steps
    cmp     dword [surv + SURVIVAL.breath], 0
    jne     .fail
    cmp     dword [surv + SURVIVAL.health], 20
    jne     .fail
    mov     edi, 60                     ; 660 steps: the first damage has landed
    call    steps
    cmp     dword [surv + SURVIVAL.health], 19
    jne     .fail
    cmp     dword [surv + SURVIVAL.dead], 0
    jne     .fail
    mov     edi, 60                     ; 720: the second
    call    steps
    cmp     dword [surv + SURVIVAL.health], 18
    jne     .fail
    mov     edi, 8
    mov     esi, 11
    mov     edx, 8
    xor     ecx, ecx
    call    world_set                   ; the head comes out: 5 a step, capped at 600
    mov     edi, 1
    call    steps
    cmp     dword [surv + SURVIVAL.breath], 5
    jne     .fail
    cmp     dword [surv + SURVIVAL.drown_timer], 0
    jne     .fail
    mov     edi, 10
    call    steps
    cmp     dword [surv + SURVIVAL.breath], 55
    jne     .fail
    mov     edi, 200
    call    steps
    cmp     dword [surv + SURVIVAL.breath], MAX_BREATH
    jne     .fail
    ; environmental damage: scaled to the maximum health (40: a tick is 2)
    mov     dword [surv_max_health], 40
    call    survival_reset
    mov     dword [surv + SURVIVAL.breath], 0
    mov     edi, 8
    mov     esi, 11
    mov     edx, 8
    mov     ecx, WATER
    call    world_set
    mov     edi, 59
    call    steps
    cmp     dword [surv + SURVIVAL.health], 40
    jne     .fail
    mov     edi, 1
    call    steps
    cmp     dword [surv + SURVIVAL.health], 38
    jne     .fail
    ; and it kills: with 1 health left the next tick is fatal, by drowning
    mov     dword [surv_max_health], 20
    call    survival_reset
    mov     dword [surv + SURVIVAL.health], 1
    mov     dword [surv + SURVIVAL.breath], 0
    mov     edi, 60
    call    steps
    cmp     dword [surv + SURVIVAL.dead], 1
    jne     .fail
    cmp     dword [surv + SURVIVAL.death_cause], CAUSE_DROWN
    jne     .fail
    call    survival_reset              ; a reset fills the lung again
    cmp     dword [surv + SURVIVAL.breath], MAX_BREATH
    jne     .fail
    cmp     dword [surv + SURVIVAL.drown_timer], 0
    jne     .fail
    xor     ebx, ebx                    ; the bubble tiles
.row:
    imul    eax, ebx, 16
    lea     rcx, [bubble_rows]
    add     rcx, rax
    mov     edi, [rcx]
    lea     rsi, [rsp]
    mov     [rsp + 16], rcx
    call    hud_bubble_tiles
    mov     rcx, [rsp + 16]
    lea     rsi, [rsp]
    lea     rdi, [rcx + 4]
    mov     ecx, 10
    repe cmpsb
    jne     .fail
    inc     ebx
    cmp     ebx, BUBBLE_ROWS
    jb      .row
    mov     dword [surv_max_health], 20
    xor     eax, eax
    jmp     .out
.fail:
    mov     dword [surv_max_health], 20
    mov     eax, 1
.out:
    add     rsp, 24
    pop     rbx
    pop     rbp
    ret

; ---- sleeping --------------------------------------------------------------------

; fail unless the banner text is the string %1
%macro BANNER_IS 1
    lea     rdi, [banner_text]
    lea     rsi, [%1]
    call    str_eq
    test    eax, eax
    jz      .fail
%endmacro

; sleep_use_bed(%1, %2, %3) must answer 1
%macro USE_BED 3
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    call    sleep_use_bed
    cmp     eax, 1
    jne     .fail
%endmacro

; SETBLOCK x, y, z, id: world_set
%macro SETBLOCK 4
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    call    world_set
%endmacro

; mob_spawn(type %1) at (%2, %3, %4)
%macro SPAWN 4
    mov     edi, %1
    mov     eax, __float32__(%2)
    movd    xmm0, eax
    mov     eax, __float32__(%3)
    movd    xmm1, eax
    mov     eax, __float32__(%4)
    movd    xmm2, eax
    call    mob_spawn
%endmacro

; sleeps(edi n): n times sleep_step
sleeps:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
.loop:
    call    sleep_step
    dec     ebx
    jnz     .loop
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; make_bed(): a bed with its foot at (5, 10, 5) facing east, its head at (6, 10, 5)
make_bed:
    sub     rsp, 8
    mov     edi, 5
    mov     esi, 10
    mov     edx, 5
    mov     ecx, BED + DIR_E
    call    world_set
    mov     edi, 6
    mov     esi, 10
    mov     edx, 5
    mov     ecx, BED + 4 + DIR_E
    call    world_set
    add     rsp, 8
    ret

; put_floor(): a STONE floor at y = 9 under x 3..8, z 3..7 (the bed's surroundings)
put_floor:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     r12d, 3
.z:
    mov     ebx, 3
.x:
    mov     edi, ebx
    mov     esi, 9
    mov     edx, r12d
    mov     ecx, STONE
    call    world_set
    inc     ebx
    cmp     ebx, 8
    jle     .x
    inc     r12d
    cmp     r12d, 7
    jle     .z
    pop     r12
    pop     rbx
    pop     rbp
    ret

; Sleep rules. By day a click on the bed (foot or head) sets the respawn point (the absolute foot
; cell) and only says so. At night a hostile mob within 8 blocks horizontally (and 5 vertically) says
; "Monsters are nearby"; a zombie 12 blocks away, a pig beside the bed and a zombie 7 blocks above do
; not stop the sleep: the player lies on the bed (5.5, 10.5625, 5.5). After 120 steps it is morning
; (time -> the next 06:00: 54000 -> 72000, 126000 -> 144000), the fade climbs to 1 over 90 steps and
; falls over the 30 after waking. Damage on step 60 wakes the sleeper with the time unchanged. The
; rules are the same in Creative. A solid block in either of the two cells above the foot (where the
; sleeper's head would be) refuses the sleep ("The bed is obstructed", the respawn point is still set);
; one three cells up, or over the head cell only, does not. At the morning the player gets up beside
; the bed: on the first of the foot's N, E, S, W neighbours (then the head's) with room and a floor, or
; on the bed when there is none. Going to bed takes him out of the boat he rides; refused (by day, or
; obstructed) he stays in it.
; Frame: [rsp] the caller's game_time.
test_sleep_rules:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 24
    mov     eax, [game_time]
    mov     [rsp], eax
    call    setup
    call    mobs_clear
    call    sleep_cancel
    mov     dword [world_header + WORLDHDR.bed_set], 0
    call    make_bed
    SETF    [player + BODY.x], 20.5
    SETF    [player + BODY.y], 10.0
    SETF    [player + BODY.z], 20.5
    ; 1. by day: the respawn point only
    mov     dword [game_time], 6000
    USE_BED 5, 10, 5
    cmp     dword [sleep_active], 0
    jne     .fail
    cmp     dword [world_header + WORLDHDR.bed_set], 1
    jne     .fail
    cmp     dword [world_header + WORLDHDR.bed_x], 5
    jne     .fail
    cmp     dword [world_header + WORLDHDR.bed_y], 10
    jne     .fail
    cmp     dword [world_header + WORLDHDR.bed_z], 5
    jne     .fail
    BANNER_IS s_b_day
    mov     dword [world_header + WORLDHDR.bed_x], 0
    mov     dword [world_header + WORLDHDR.bed_z], 0
    USE_BED 6, 10, 5                    ; the head resolves to the foot
    cmp     dword [world_header + WORLDHDR.bed_x], 5
    jne     .fail
    cmp     dword [world_header + WORLDHDR.bed_z], 5
    jne     .fail
    ; 2. at night with a zombie 5 blocks away
    mov     dword [game_time], 54000
    SPAWN   MOB_ZOMBIE, 10.5, 10.0, 5.5
    USE_BED 5, 10, 5
    cmp     dword [sleep_active], 0
    jne     .fail
    BANNER_IS s_b_mobs
    ; 3. a zombie 12 blocks away, a pig beside the bed, a zombie 7 blocks above: asleep
    call    mobs_clear
    SPAWN   MOB_ZOMBIE, 17.5, 10.0, 5.5
    SPAWN   MOB_PIG, 6.5, 10.0, 6.5
    SPAWN   MOB_ZOMBIE, 7.5, 17.0, 5.5
    USE_BED 5, 10, 5
    cmp     dword [sleep_active], 1
    jne     .fail
    BANNER_IS s_b_sleep
    FNEAR   [player + BODY.x], k_5_5
    FNEAR   [player + BODY.y], k_10_5625
    FNEAR   [player + BODY.z], k_5_5
    ; 4. the night passes in 120 steps
    mov     edi, 45
    call    sleeps
    FNEAR   [sleep_fade], k_0_5         ; 45 / 90
    mov     edi, 74
    call    sleeps                      ; step 119: still asleep, time as before
    cmp     dword [sleep_active], 1
    jne     .fail
    cmp     dword [game_time], 54000
    jne     .fail
    mov     edi, 1
    call    sleeps                      ; step 120: the morning
    cmp     dword [sleep_active], 0
    jne     .fail
    cmp     dword [game_time], 72000
    jne     .fail
    FNEAR   [player + BODY.x], k_5_5        ; no floor anywhere: nowhere to get up to, he stays on the bed
    FNEAR   [player + BODY.y], k_10_5625
    FNEAR   [player + BODY.z], k_5_5
    FNEAR   [sleep_fade], k_1_0
    mov     edi, 30
    call    sleeps                      ; the fade lifts again
    cmp     dword [sleep_fade], 0
    jne     .fail
    mov     dword [game_time], 126000   ; and the second night
    USE_BED 5, 10, 5
    mov     edi, 120
    call    sleeps
    cmp     dword [game_time], 144000
    jne     .fail
    ; 5. damage on step 60 wakes the sleeper; the time stays
    mov     dword [game_time], 54000
    USE_BED 5, 10, 5
    cmp     dword [sleep_active], 1
    jne     .fail
    mov     edi, 60
    call    sleeps
    mov     edi, 2
    mov     esi, CAUSE_ZOMBIE
    call    survival_damage
    cmp     eax, 1
    jne     .fail
    cmp     dword [sleep_active], 0
    jne     .fail
    cmp     dword [sleep_fade], 0
    jne     .fail
    mov     edi, 120
    call    sleeps
    cmp     dword [game_time], 54000
    jne     .fail
    ; 6. the same rules in Creative; sleep_cancel leaves the time alone
    mov     dword [game_mode], MODE_CREATIVE
    USE_BED 5, 10, 5
    cmp     dword [sleep_active], 1
    jne     .fail
    mov     edi, 20
    call    sleeps
    call    sleep_cancel
    cmp     dword [sleep_active], 0
    jne     .fail
    cmp     dword [game_time], 54000
    jne     .fail
    mov     dword [game_mode], MODE_SURVIVAL
    ; 7. a solid block in one of the two cells above the foot: obstructed, but the respawn is set
    call    mobs_clear
    mov     dword [game_time], 54000
    mov     dword [world_header + WORLDHDR.bed_set], 0
    mov     dword [world_header + WORLDHDR.bed_x], 0
    SETBLOCK 5, 12, 5, STONE            ; two above the foot
    USE_BED 5, 10, 5
    cmp     dword [sleep_active], 0
    jne     .fail
    BANNER_IS s_b_blocked
    cmp     dword [world_header + WORLDHDR.bed_set], 1
    jne     .fail
    cmp     dword [world_header + WORLDHDR.bed_x], 5
    jne     .fail
    SETBLOCK 5, 12, 5, AIR
    SETBLOCK 5, 11, 5, STONE            ; one above it, clicked on the head
    USE_BED 6, 10, 5
    cmp     dword [sleep_active], 0
    jne     .fail
    BANNER_IS s_b_blocked
    SETBLOCK 5, 11, 5, AIR
    SETBLOCK 5, 13, 5, STONE            ; three above the foot, and over the head cell: no problem
    SETBLOCK 6, 12, 5, STONE
    USE_BED 5, 10, 5
    cmp     dword [sleep_active], 1
    jne     .fail
    BANNER_IS s_b_sleep
    call    sleep_cancel
    SETBLOCK 5, 13, 5, AIR
    SETBLOCK 6, 12, 5, AIR
    ; 8. at the morning he gets up beside the bed: north of the foot, else (east is the head) south
    call    put_floor
    mov     dword [game_time], 54000
    USE_BED 5, 10, 5
    mov     edi, 120
    call    sleeps
    cmp     dword [sleep_active], 0
    jne     .fail
    cmp     dword [game_time], 72000
    jne     .fail
    FNEAR   [player + BODY.x], k_5_5
    FNEAR   [player + BODY.y], k_10_0
    FNEAR   [player + BODY.z], k_4_5
    cmp     dword [player + BODY.on_ground], 1
    jne     .fail
    SETBLOCK 5, 10, 4, STONE
    mov     dword [game_time], 54000
    USE_BED 5, 10, 5
    mov     edi, 120
    call    sleeps
    FNEAR   [player + BODY.x], k_5_5
    FNEAR   [player + BODY.y], k_10_0
    FNEAR   [player + BODY.z], k_6_5
    SETBLOCK 5, 10, 4, AIR
    ; 9. out of a boat to bed; by day, or with the bed obstructed, he stays seated
    call    boats_clear
    mov     dword [boats + BOATENT.used], 1
    SETF    [boats + BODY.x], 12.5
    SETF    [boats + BODY.y], 10.625
    SETF    [boats + BODY.z], 12.5
    xor     edi, edi
    call    boats_mount
    cmp     dword [boat_riding], 1
    jne     .fail
    mov     dword [game_time], 6000
    USE_BED 5, 10, 5
    cmp     dword [sleep_active], 0
    jne     .fail
    cmp     dword [boat_riding], 1
    jne     .fail
    mov     dword [game_time], 54000
    SETBLOCK 5, 12, 5, STONE
    USE_BED 5, 10, 5
    cmp     dword [sleep_active], 0
    jne     .fail
    cmp     dword [boat_riding], 1
    jne     .fail
    SETBLOCK 5, 12, 5, AIR
    USE_BED 5, 10, 5
    cmp     dword [sleep_active], 1
    jne     .fail
    cmp     dword [boat_riding], 0              ; asleep he is no longer in the boat, but on the bed
    jne     .fail
    FNEAR   [player + BODY.x], k_5_5
    FNEAR   [player + BODY.y], k_10_5625
    call    sleep_cancel
    xor     ebx, ebx
    jmp     .out
.fail:
    mov     ebx, 1
.out:
    call    sleep_cancel
    call    boats_clear
    call    mobs_clear
    mov     dword [world_header + WORLDHDR.bed_set], 0
    mov     dword [game_mode], MODE_SURVIVAL
    mov     eax, [rsp]
    mov     [game_time], eax
    mov     eax, ebx
    add     rsp, 24
    pop     rbx
    pop     rbp
    ret
