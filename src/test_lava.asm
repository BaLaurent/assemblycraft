; test_lava.asm - lava, and what consumes the four biomes of 0.10.1.
; test_lava_burns: body_in_liquid tells WATER from LAVA (water wins when both are touched); a Survival player in lava
; burns and takes the lava's strike (every 10th step of game_time, 30 steps apart), a Creative player does not (through
; game_frame, which only calls survival_step in Survival); a body in lava walks at 0.3 of its speed, rises at 1.5 (still at 7
; against a ledge) and lands softly; a zombie in lava burns and is struck, a pig that strolls toward a lava pool turns
; about at the shore; spawn_at_ground refuses lava as ground and as the cell a mob stands in; place_block puts a block into
; a lava cell.
; test_new_biome_consumers: the F3 names of the biomes, the home biomes of the factions' camps, a camp clearing built of the
; top block and filler it is given (DRY_GRASS over dirt, as in a savanna), a passive mob on DRY_GRASS.
%include "common.inc"
default rel

global test_lava_burns, test_new_biome_consumers

extern world_clear, world_set, world_get, world_locate
extern player, body_init, body_step, body_in_liquid
extern surv, surv_max_health, survival_reset, survival_step
extern combat_reset, combat_burn_t, combat_step, status_step
extern game_mode, game_time, settings, rpg_reset, rng_seed
extern mobs, mobs_clear, mob_spawn, mobs_step, spawn_at_ground, drops_clear
extern place_block
extern game_frame, frame_input, inv_clear, inv_sel, input_captured, game_open_screen
extern game_heavy_s, game_break_progress, brk_y
extern hud_biome_name, str_eq
extern camp_clearing, camp_homes, structures_stamp

section .rodata
align 4
k_half_w: dd 0.3                        ; the player's box and walking speed
k_height: dd 1.8
k_speed:  dd 4.317
k_0_5:    dd 0.5
k_4_5:    dd 4.5
k_lo:     dd 0.285                      ; lava / land displacement: 0.3 +- 5 %
k_hi:     dd 0.315
k_1_5:    dd 1.5
k_7_0:    dd 7.0
k_step:   dd 0.016666668                ; one fixed step: game_frame runs exactly one sim_step
k_11_0:   dd 11.0
k_12_0:   dd 12.0
k_8_5:    dd 8.5
k_10_5:   dd 10.5
k_12_5:   dd 12.5
k_27_5:   dd 27.5
k_28_5:   dd 28.5

s_ocean:   db "Ocean", 0
s_plains:  db "Plains", 0
s_forest:  db "Forest", 0
s_desert:  db "Desert", 0
s_snow:    db "Snow", 0
s_swamp:   db "Swamp", 0
s_mount:   db "Mountains", 0
s_river:   db "River", 0
s_taiga:   db "Snowy Taiga", 0
s_savanna: db "Savanna", 0
s_shore:   db "Stony Shore", 0
s_birch:   db "Birch Forest", 0
s_unknown: db "unknown", 0
align 8
biome_expect: dq s_ocean, s_plains, s_forest, s_desert, s_snow, s_swamp, s_mount, s_river
              dq s_taiga, s_savanna, s_shore, s_birch
%if $ - biome_expect != NUM_BIOMES * 8
%error "test_lava.asm: biome_expect needs one name per BIOME_*"
%endif
; the biomes each faction's camp may stand in, by faction (camp_homes): a bit per BIOME_*
homes_expect:
    dd (1 << BIOME_PLAINS) | (1 << BIOME_FOREST) | (1 << BIOME_BIRCH)           ; villagers
    dd (1 << BIOME_FOREST) | (1 << BIOME_MOUNTAINS) | (1 << BIOME_SAVANNA)      ; bandits
    dd (1 << BIOME_SWAMP)                                                       ; cult
    dd (1 << BIOME_SNOW) | (1 << BIOME_TAIGA) | (1 << BIOME_MOUNTAINS)          ; beastfolk
    dd (1 << BIOME_MOUNTAINS)                                                   ; stonekin
; the cells of the camp buffer (index (y << 8) | (z << 4) | x) check_clearing looks at: the top block at y = 40 (the centre
; and the four corners of the column, all within 10 of the camp's centre (8, 8)), then the filler at y = 39, 38 and 37 at the
; centre and at the corner (0, 0)
top_cells:
    dd (40 << 8) | (8 << 4) | 8
    dd (40 << 8) | (0 << 4) | 0
    dd (40 << 8) | (0 << 4) | 15
    dd (40 << 8) | (15 << 4) | 0
    dd (40 << 8) | (15 << 4) | 15
filler_cells:
    dd (39 << 8) | (8 << 4) | 8
    dd (38 << 8) | (8 << 4) | 8
    dd (37 << 8) | (8 << 4) | 8
    dd (39 << 8) | (0 << 4) | 0
    dd (38 << 8) | (0 << 4) | 0
    dd (37 << 8) | (0 << 4) | 0

section .bss
alignb 4
inp:      resb INPUT_size               ; the INPUT of body_step and survival_step
hit:      resb RAYHIT_size              ; the target handed to place_block
saved:    resd 4                        ; the caller's game_mode, game_time, difficulty and input_captured
dist:     resd 3                        ; the distances walked: land, lava, water
maxfall:  resd 1                        ; the largest fall distance body_step reported
alignb 64
cbuf:     resb GENBUF_size              ; the column a camp clearing is built into
site:     resb SITE_size                ; a fabricated camp site

section .text

; SETF mem, float literal
%macro SETF 2
    mov     dword %1, __float32__(%2)
%endmacro

; BLOCK x, y, z, id: world_set
%macro BLOCK 4
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    call    world_set
%endmacro

; FILL x0, y0, z0, x1, y1, z1, id: world_set over the inclusive box
%macro FILL 7
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    mov     r8d, %5
    mov     r9d, %6
    mov     r10d, %7
    call    fill_box
%endmacro

; POKE x, y, z, id: the block goes into its chunk without COLUMN.top hearing of it (a fabricated stale top)
%macro POKE 4
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    call    poke_raw
%endmacro

; PLAYER_AT x, y, z (float literals): the player's feet
%macro PLAYER_AT 3
    SETF    [player + BODY.x], %1
    SETF    [player + BODY.y], %2
    SETF    [player + BODY.z], %3
%endmacro

; fail unless the float at %1 equals the float constant at %2
%macro FEQ 2
    movss   xmm0, %1
    ucomiss xmm0, [%2]
    jne     .fail
    jp      .fail
%endmacro

; fail unless the world holds block id %4 at (%1, %2, %3)
%macro WORLD_IS 4
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    call    world_get
    cmp     eax, %4
    jne     .fail
%endmacro

; PROBE x, y, z, liquid: body_in_liquid of a player body with its feet there must be `liquid` (0, WATER, LAVA)
%macro PROBE 4
    PLAYER_AT %1, %2, %3
    lea     rdi, [player]
    call    body_in_liquid
    cmp     eax, %4
    jne     .fail
%endmacro

; SPAWN_CASE type, x, z, kind, expected: spawn_ok must come to `expected`
%macro SPAWN_CASE 5
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    call    spawn_ok
    cmp     eax, %5
    jne     .fail
%endmacro

; HIT bx, by, bz, px, py, pz: the target handed to place_block
%macro HIT 6
    mov     dword [hit + RAYHIT.bx], %1
    mov     dword [hit + RAYHIT.by], %2
    mov     dword [hit + RAYHIT.bz], %3
    mov     dword [hit + RAYHIT.px], %4
    mov     dword [hit + RAYHIT.py], %5
    mov     dword [hit + RAYHIT.pz], %6
%endmacro

; CELL x, y, z, id: the block of the camp buffer cbuf at that cell of its column must be `id`
%macro CELL 4
    cmp     byte [cbuf + GENBUF.blocks + (((%2) << 8) | ((%3) << 4) | (%1))], %4
    jne     .fail
%endmacro

; ---- helpers ---------------------------------------------------------------------

; fill_box(edi x0, esi y0, edx z0, ecx x1, r8d y1, r9d z1, r10d id): world_set `id` over the inclusive box
; rbx = x0, r12d = z0, r13d = x1, r14d = y1, r15d = z1; frame: [rsp] x, [rsp+4] y, [rsp+8] z (running),
; [rsp+12] y0, [rsp+16] id
fill_box:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     ebx, edi
    mov     [rsp + 12], esi
    mov     r12d, edx
    mov     r13d, ecx
    mov     r14d, r8d
    mov     r15d, r9d
    mov     [rsp + 16], r10d
    mov     [rsp + 4], esi
.y:
    mov     [rsp + 8], r12d
.z:
    mov     [rsp], ebx
.x:
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    mov     edx, [rsp + 8]
    mov     ecx, [rsp + 16]
    call    world_set
    inc     dword [rsp]
    cmp     [rsp], r13d
    jle     .x
    inc     dword [rsp + 8]
    cmp     [rsp + 8], r15d
    jle     .z
    inc     dword [rsp + 4]
    cmp     [rsp + 4], r14d
    jle     .y
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; poke_raw(edi x, esi y, edx z, ecx id): the byte of that cell in its chunk becomes `id`, behind the back of world_set:
; COLUMN.top, the light and the dirty marks are not told (the chunk must exist: a column with a block at or below
; that chunk's height). For the one state the world never produces on its own: a cell above the column's top.
poke_raw:
    sub     rsp, 8
    mov     r11d, ecx
    call    world_locate                ; r10 = the chunk, eax = the cell's index in it
    test    r10, r10
    jz      .ret
    mov     [r10 + rax], r11b
.ret:
    add     rsp, 8
    ret

; reset_body(): the standard body (0.3 x 1.8, walk 4.317) with its feet at (8.5, 11, 8.5), a zero input
reset_body:
    push    rbp
    mov     rbp, rsp
    lea     rdi, [player]
    movss   xmm0, [k_half_w]
    movss   xmm1, [k_height]
    movss   xmm2, [k_speed]
    call    body_init
    PLAYER_AT 8.5, 11.0, 8.5
    lea     rdi, [inp]
    mov     ecx, INPUT_size
    xor     eax, eax
    rep     stosb
    pop     rbp
    ret

; arena(): an empty world with a STONE floor at y = 10 over x, z 0..31 (its top is y = 11), no mobs, rng seed 1234, Survival at
; Normal difficulty at night (game_time 40000: a multiple of 10), a fresh character, survival and combat state (20
; health), the standard body at (8.5, 11, 8.5)
arena:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    mov     edi, 1234
    call    rng_seed
    call    mobs_clear
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    mov     dword [game_time], 40000
    call    rpg_reset                   ; (it publishes surv_max_health)
    mov     dword [surv_max_health], 20
    call    survival_reset
    call    combat_reset
    FILL    0, 10, 0, 31, 10, 31, STONE
    call    reset_body
    pop     rbp
    ret

; run_body(edi n >= 1): n times body_step(&player, &inp)
run_body:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
.l:
    lea     rdi, [player]
    lea     rsi, [inp]
    call    body_step
    dec     ebx
    jnz     .l
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; run_surv(edi n >= 1): n times survival_step(&inp, 0.0, 0) and combat_step(0) (which pays the burn's ticks), and game_time
; one step on after each, as sim_step does
run_surv:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
.l:
    lea     rdi, [inp]
    xorps   xmm0, xmm0
    xor     esi, esi
    call    survival_step
    xor     edi, edi
    call    combat_step
    inc     dword [game_time]
    dec     ebx
    jnz     .l
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; run_frames(edi n >= 1): n times game_frame(1/60 s), which runs exactly one sim_step
run_frames:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
.l:
    movss   xmm0, [k_step]
    call    game_frame
    dec     ebx
    jnz     .l
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; mob_ptr(edi idx) -> rax the mob in that slot
mob_ptr:
    imul    eax, edi, MOB_size
    lea     rcx, [mobs]
    add     rax, rcx
    ret

; spawn_ok(edi type, esi x, edx z, ecx kind) -> eax 1 when spawn_at_ground put a mob at (x + 0.5, 11, z + 0.5), 0 when it
; refused or put it anywhere else; no mob is left behind
spawn_ok:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, esi
    mov     r12d, edx
    call    spawn_at_ground
    test    eax, eax
    js      .no
    mov     edi, eax
    call    mob_ptr
    cvtsi2ss xmm0, ebx
    addss   xmm0, [k_0_5]
    ucomiss xmm0, [rax + BODY.x]
    jne     .no
    cvtsi2ss xmm0, r12d
    addss   xmm0, [k_0_5]
    ucomiss xmm0, [rax + BODY.z]
    jne     .no
    movss   xmm0, [k_11_0]
    ucomiss xmm0, [rax + BODY.y]
    jne     .no
    mov     ebx, 1
    jmp     .out
.no:
    xor     ebx, ebx
.out:
    call    mobs_clear
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- test_lava_burns ---------------------------------------------------------------

; check_probes() -> eax 0 when body_in_liquid names the liquid at the player's feet (feet + 0.05) or lower body (feet + 0.4):
; LAVA in a lava cell, WATER in a water cell, 0 in a dry one; WATER when one probe finds it and the other lava, in either
; order; LAVA when either probe finds it alone
check_probes:
    push    rbp
    mov     rbp, rsp
    call    arena
    BLOCK   8, 11, 8, LAVA
    BLOCK   10, 11, 8, WATER
    PROBE   8.5, 11.0, 8.5, LAVA
    PROBE   10.5, 11.0, 8.5, WATER
    PROBE   12.5, 11.0, 8.5, 0
    BLOCK   20, 10, 20, WATER           ; feet at 10.7: the probes look at the cells y = 10 (10.75) and y = 11 (11.1)
    BLOCK   20, 11, 20, LAVA
    PROBE   20.5, 10.7, 20.5, WATER
    BLOCK   20, 10, 20, LAVA
    BLOCK   20, 11, 20, WATER
    PROBE   20.5, 10.7, 20.5, WATER     ; water wins whichever probe sees it
    BLOCK   20, 11, 20, AIR
    PROBE   20.5, 10.7, 20.5, LAVA      ; the feet probe alone
    BLOCK   20, 10, 20, AIR
    BLOCK   20, 11, 20, LAVA
    PROBE   20.5, 10.7, 20.5, LAVA      ; the lower body alone
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    pop     rbp
    ret

; check_burn() -> eax 0 when a Survival player in lava burns and is struck: dry, 40 steps leave him unhurt and not
; burning; in a lava cell the first step sets the burn (combat_burn_t > 0) and, with game_time a multiple of 10, the
; lava's strike takes 4 of 20 health; the next strike is 30 steps later (the invulnerability) and the burn ticks for 4
; (STS_BURN magnitude 24 / 6) once, at step 29 (a period of 30 from the first), so 40 steps leave 20 - 3 * 4 = 8; a
; lethal strike kills by CAUSE_FIRE
check_burn:
    push    rbp
    mov     rbp, rsp
    call    arena
    BLOCK   8, 11, 8, LAVA
    PLAYER_AT 12.5, 11.0, 12.5
    mov     edi, 40
    call    run_surv
    cmp     dword [combat_burn_t], 0
    jne     .fail
    cmp     dword [surv + SURVIVAL.health], 20
    jne     .fail
    mov     dword [game_time], 40000
    PLAYER_AT 8.5, 11.0, 8.5
    mov     edi, 1
    call    run_surv
    cmp     dword [combat_burn_t], 0
    jle     .fail
    cmp     dword [surv + SURVIVAL.health], 16
    jne     .fail
    mov     edi, 39
    call    run_surv
    cmp     dword [surv + SURVIVAL.health], 8
    jne     .fail
    call    survival_reset              ; one strike from death
    call    combat_reset
    mov     dword [surv + SURVIVAL.health], 4
    mov     dword [game_time], 40000
    mov     edi, 1
    call    run_surv
    cmp     dword [surv + SURVIVAL.dead], 1
    jne     .fail
    cmp     dword [surv + SURVIVAL.death_cause], CAUSE_FIRE
    jne     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    pop     rbp
    ret

; check_frames() -> eax 0 when game_frame (the real step: body_step, survival_step only in Survival, combat_step) lets a
; Creative player stand in lava for 40 steps without burning or losing health, and a Survival player burn on the first
; step and lose health within 40. game_frame's state is that of test_game.asm's frame_arena: by day in Peaceful
; with nothing else about, the cursor captured, no screen open, no button down.
check_frames:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    arena
    mov     dword [game_time], 6007
    mov     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL
    call    inv_clear
    mov     dword [inv_sel], 0
    lea     rdi, [frame_input]
    mov     ecx, FRAMEINPUT_size
    xor     eax, eax
    rep     stosb
    mov     dword [frame_input + FRAMEINPUT.slot], -1
    mov     dword [input_captured], 1
    mov     dword [game_open_screen], 0
    mov     dword [game_heavy_s], __float32__(-1.0)
    mov     dword [game_break_progress], 0
    mov     dword [brk_y], -1
    BLOCK   8, 11, 8, LAVA
    mov     dword [game_mode], MODE_CREATIVE
    mov     edi, 40
    call    run_frames
    cmp     dword [combat_burn_t], 0
    jne     .fail
    mov     eax, [surv_max_health]      ; (every sim_step publishes it again)
    cmp     [surv + SURVIVAL.health], eax
    jne     .fail
    mov     dword [game_mode], MODE_SURVIVAL
    call    reset_body
    call    survival_reset
    call    combat_reset
    mov     edi, 1
    call    run_frames
    cmp     dword [combat_burn_t], 0
    jle     .fail
    mov     edi, 39
    call    run_frames
    mov     eax, [surv_max_health]
    cmp     [surv + SURVIVAL.health], eax
    jge     .fail
    xor     ebx, ebx
    jmp     .out
.fail:
    mov     ebx, 1
.out:
    call    mobs_clear                  ; what game_frame leaves behind
    call    inv_clear
    call    drops_clear
    lea     rdi, [frame_input]
    mov     ecx, FRAMEINPUT_size
    xor     eax, eax
    rep     stosb
    mov     dword [game_open_screen], 0
    mov     dword [game_heavy_s], __float32__(-1.0)
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; strip_run(edi z) -> xmm0 how far 30 steps east carry the standard body from (4.5, 11, z + 0.5)
strip_run:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
    call    reset_body
    SETF    [player + BODY.x], 4.5
    SETF    [player + BODY.yaw], 90.0
    cvtsi2ss xmm0, ebx
    addss   xmm0, [k_0_5]
    movss   [player + BODY.z], xmm0
    mov     dword [player + BODY.on_ground], 1
    mov     dword [inp + INPUT.fwd], 1
    mov     edi, 30
    call    run_body
    movss   xmm0, [player + BODY.x]
    subss   xmm0, [k_4_5]
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; fall_run(): 150 body_steps of the player with a zero input; maxfall = the largest fall distance any of them reported
fall_run:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     dword [maxfall], 0
    mov     ebx, 150
.l:
    lea     rdi, [player]
    lea     rsi, [inp]
    call    body_step
    maxss   xmm0, [maxfall]
    movss   [maxfall], xmm0
    dec     ebx
    jnz     .l
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; check_movement() -> eax 0 when a body walks in lava: 30 steps east cover 0.3 of what they cover on dry ground (+-5 %)
; and less than in water; jump held in lava sets vy to 1.5, against a ledge (blocked last step) to 7; a fall of 25
; blocks into 3-deep lava reports no fall distance (it lands softly), the same fall onto the floor reports it
; Lava strip z = 8 (x 4..15), water strip z = 16, dry strip z = 24, a 5 x 5 pool of 3-deep lava at x, z 24..28 for the fall.
check_movement:
    push    rbp
    mov     rbp, rsp
    call    arena
    FILL    4, 11, 8, 15, 11, 8, LAVA
    FILL    4, 11, 16, 15, 11, 16, WATER
    mov     edi, 24
    call    strip_run
    movss   [dist], xmm0
    mov     edi, 8
    call    strip_run
    movss   [dist + 4], xmm0
    mov     edi, 16
    call    strip_run
    movss   [dist + 8], xmm0
    movss   xmm0, [dist + 4]
    ucomiss xmm0, [dist + 8]
    jae     .fail                       ; lava slows more than water
    divss   xmm0, [dist]
    ucomiss xmm0, [k_lo]
    jb      .fail
    ucomiss xmm0, [k_hi]
    ja      .fail                       ; 0.3 of the land distance
    call    reset_body                  ; standing in the lava strip, jump held
    mov     dword [player + BODY.on_ground], 1
    mov     dword [inp + INPUT.jump], 1
    mov     edi, 1
    call    run_body
    FEQ     [player + BODY.vy], k_1_5
    call    reset_body                  ; ... against a ledge: 7 as in water
    mov     dword [player + BODY.blocked], 1
    mov     dword [inp + INPUT.jump], 1
    mov     edi, 1
    call    run_body
    FEQ     [player + BODY.vy], k_7_0
    FILL    24, 11, 24, 28, 13, 28, LAVA
    call    reset_body
    PLAYER_AT 26.5, 36.0, 26.5
    call    fall_run
    cmp     dword [maxfall], 0
    jne     .fail
    call    reset_body                  ; the control: the same fall onto the bare floor
    PLAYER_AT 20.5, 36.0, 20.5
    call    fall_run
    movss   xmm0, [maxfall]
    ucomiss xmm0, [k_1_5]
    jbe     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    pop     rbp
    ret

; check_zombie() -> eax 0 when a zombie standing in a 7 x 7 lava pool burns (burn_t > 0) and is struck (after 5 steps it
; has lost 6 health: the lava's strike of 4 and the first tick of the burn, 2; within 40 it has lost health or died), and
; a control zombie on the dry floor is untouched. The player is far away (nothing hunts him), it is night (no
; sunlight), and ai_timer is long, so the zombies stand where they were put.
; rbx = the zombie in lava, r12 = the control, r13d = steps to go
check_zombie:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    arena
    PLAYER_AT 2.5, 11.0, 2.5
    FILL    24, 11, 24, 30, 11, 30, LAVA
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_27_5]
    movss   xmm1, [k_11_0]
    movss   xmm2, [k_27_5]
    call    mob_spawn
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    mob_ptr
    mov     rbx, rax
    mov     dword [rbx + MOB.ai_timer], 100000
    mov     dword [rbx + MOB.input + INPUT.fwd], 0
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_12_5]
    movss   xmm1, [k_11_0]
    movss   xmm2, [k_28_5]
    call    mob_spawn
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax
    mov     dword [r12 + MOB.ai_timer], 100000
    mov     dword [r12 + MOB.input + INPUT.fwd], 0
    mov     r13d, 5
    call    mob_steps
    cmp     dword [rbx + MOB.type], MOB_ZOMBIE
    jne     .fail
    cmp     dword [rbx + MOB.burn_t], 0
    jle     .fail
    mov     eax, [rbx + MOB.max_health]
    sub     eax, 6
    cmp     [rbx + MOB.health], eax
    jne     .fail                       ; struck once (4) and burnt once (2)
    mov     r13d, 35
    call    mob_steps
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .control                    ; burnt to death
    mov     eax, [rbx + MOB.max_health]
    cmp     [rbx + MOB.health], eax
    jge     .fail
.control:
    cmp     dword [r12 + MOB.type], MOB_ZOMBIE
    jne     .fail
    cmp     dword [r12 + MOB.burn_t], 0
    jne     .fail
    mov     eax, [r12 + MOB.max_health]
    cmp     [r12 + MOB.health], eax
    jne     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    mobs_clear
    call    drops_clear
    mov     eax, ebx
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mob_steps(r13d n): n times mobs_step, status_step and game_time one step on (the order of sim_step); r13d is spent
mob_steps:
    sub     rsp, 8
.l:
    call    mobs_step
    call    status_step
    inc     dword [game_time]
    dec     r13d
    jnz     .l
    add     rsp, 8
    ret

; check_pig() -> eax 0 when pig_run passes for a lava pool flush with the floor (y = 10: the cell below the pig's feet
; level holds the lava ahead of it) and for one standing on it (y = 11: the cell at the feet level does)
check_pig:
    push    rbp
    mov     rbp, rsp
    mov     edi, 10
    call    pig_run
    test    eax, eax
    jnz     .out
    mov     edi, 11
    call    pig_run
.out:
    pop     rbp
    ret

; pig_run(edi y) -> eax 0 when a pig strolling east toward a lava pool (x 12..19, z 6..14, the layer y) 3 cells ahead of
; it never stands in lava in 300 steps: it walks up to the shore (x between 11 and 12) and turns about, as at water
; rbx = steps to go, r12 = the pig, r13d = y, [rsp] the highest x it reached
pig_run:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     r13d, edi
    call    arena
    mov     dword [game_time], NEW_WORLD_TIME
    PLAYER_AT 2.5, 11.0, 2.5
    mov     edi, 12
    mov     esi, r13d
    mov     edx, 6
    mov     ecx, 19
    mov     r8d, r13d
    mov     r9d, 14
    mov     r10d, LAVA
    call    fill_box
    mov     edi, MOB_PIG
    movss   xmm0, [k_8_5]
    movss   xmm1, [k_11_0]
    movss   xmm2, [k_10_5]
    call    mob_spawn
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax
    SETF    [r12 + BODY.yaw], 90.0
    mov     dword [r12 + MOB.ai_timer], 100000
    mov     dword [r12 + MOB.input + INPUT.fwd], 1
    mov     dword [rsp], 0
    mov     ebx, 300
.step:
    call    mobs_step
    movss   xmm0, [r12 + BODY.x]        ; the cell of its feet must not hold lava
    roundss xmm0, xmm0, 9
    cvttss2si edi, xmm0
    movss   xmm0, [r12 + BODY.y]
    roundss xmm0, xmm0, 9
    cvttss2si esi, xmm0
    movss   xmm0, [r12 + BODY.z]
    roundss xmm0, xmm0, 9
    cvttss2si edx, xmm0
    call    world_get
    cmp     eax, LAVA
    je      .fail
    movss   xmm0, [r12 + BODY.x]
    maxss   xmm0, [rsp]
    movss   [rsp], xmm0
    dec     ebx
    jnz     .step
    movss   xmm0, [rsp]
    ucomiss xmm0, [k_11_0]
    jbe     .fail                       ; it did walk up to the shore (x 11.3 is as far as it goes)
    ucomiss xmm0, [k_12_0]
    jae     .fail                       ; ...and no further
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    mobs_clear
    mov     eax, ebx
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; check_spawn() -> eax 0 when spawn_at_ground refuses lava: a lava top block is no ground (zombie and pig), and neither
; is a cell above a solid top that holds lava (the stand cell: POKE puts the lava there behind COLUMN.top's back, the one way
; to get it above the column's top), while a stone floor (zombie) and a grass top (pig) are still ground
check_spawn:
    push    rbp
    mov     rbp, rsp
    call    arena
    mov     dword [game_time], NEW_WORLD_TIME
    SPAWN_CASE MOB_ZOMBIE, 5, 5, GROUND_HOSTILE, 1
    BLOCK   7, 10, 5, GRASS
    SPAWN_CASE MOB_PIG, 7, 5, GROUND_PASSIVE, 1
    BLOCK   9, 10, 5, LAVA
    SPAWN_CASE MOB_ZOMBIE, 9, 5, GROUND_HOSTILE, 0
    SPAWN_CASE MOB_PIG, 9, 5, GROUND_PASSIVE, 0
    POKE    11, 11, 5, LAVA             ; stone below, lava in the cell above it
    SPAWN_CASE MOB_ZOMBIE, 11, 5, GROUND_HOSTILE, 0
    BLOCK   13, 10, 5, GRASS
    POKE    13, 11, 5, LAVA
    SPAWN_CASE MOB_PIG, 13, 5, GROUND_PASSIVE, 0
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    pop     rbp
    ret

; check_place() -> eax 0 when place_block puts a block into a lava cell (the cell in front of the face struck) and still
; refuses a solid one
check_place:
    push    rbp
    mov     rbp, rsp
    call    arena
    BLOCK   20, 11, 20, LAVA
    HIT     20, 10, 20, 20, 11, 20
    mov     edi, STONE
    lea     rsi, [hit]
    call    place_block
    cmp     eax, 1
    jne     .fail
    WORLD_IS 20, 11, 20, STONE
    HIT     22, 9, 22, 22, 10, 22       ; the floor cell itself is not free
    mov     edi, STONE
    lea     rsi, [hit]
    call    place_block
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    pop     rbp
    ret

; Lava. Each part is a check_* above; any failure fails the test. The caller's game_mode, game_time, difficulty and
; input_captured are restored.
test_lava_burns:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     eax, [game_mode]
    mov     [saved], eax
    mov     eax, [game_time]
    mov     [saved + 4], eax
    mov     eax, [settings + SETTINGS.difficulty]
    mov     [saved + 8], eax
    mov     eax, [input_captured]
    mov     [saved + 12], eax
    call    check_probes
    test    eax, eax
    jnz     .fail
    call    check_burn
    test    eax, eax
    jnz     .fail
    call    check_frames
    test    eax, eax
    jnz     .fail
    call    check_movement
    test    eax, eax
    jnz     .fail
    call    check_zombie
    test    eax, eax
    jnz     .fail
    call    check_pig
    test    eax, eax
    jnz     .fail
    call    check_spawn
    test    eax, eax
    jnz     .fail
    call    check_place
    test    eax, eax
    jnz     .fail
    xor     ebx, ebx
    jmp     .done
.fail:
    mov     ebx, 1
.done:
    call    mobs_clear
    call    combat_reset
    call    survival_reset
    mov     eax, [saved]
    mov     [game_mode], eax
    mov     eax, [saved + 4]
    mov     [game_time], eax
    mov     eax, [saved + 8]
    mov     [settings + SETTINGS.difficulty], eax
    mov     eax, [saved + 12]
    mov     [input_captured], eax
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- test_new_biome_consumers --------------------------------------------------------

; check_names() -> eax 0 when hud_biome_name names every BIOME_* (the F3 line) and says "unknown" for NUM_BIOMES and for -1
check_names:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    xor     ebx, ebx
.l:
    mov     edi, ebx
    call    hud_biome_name
    mov     rdi, rax
    lea     rcx, [biome_expect]
    mov     rsi, [rcx + rbx*8]
    call    str_eq
    test    eax, eax
    jz      .fail
    inc     ebx
    cmp     ebx, NUM_BIOMES
    jb      .l
    mov     edi, NUM_BIOMES
    call    hud_biome_name
    mov     rdi, rax
    lea     rsi, [s_unknown]
    call    str_eq
    test    eax, eax
    jz      .fail
    mov     edi, -1
    call    hud_biome_name
    mov     rdi, rax
    lea     rsi, [s_unknown]
    call    str_eq
    test    eax, eax
    jz      .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; check_homes() -> eax 0 when camp_homes holds the home biomes of the five factions
check_homes:
    push    rbp
    mov     rbp, rsp
    lea     rsi, [camp_homes]
    lea     rdi, [homes_expect]
    mov     ecx, 5
    repe cmpsd
    setne   al
    movzx   eax, al
    pop     rbp
    ret

; fill_cbuf(): the camp buffer is column (0, 0): STONE up to y = 36, AIR above. structures_stamp points the stamping
; statics (gb_buf, gb_x0, gb_z0) at it (whatever site it stamps there is wiped by the fill), camp_clearing writes to
; what they point at
fill_cbuf:
    push    rbp
    mov     rbp, rsp
    mov     dword [cbuf + GENBUF.cx], 0
    mov     dword [cbuf + GENBUF.cz], 0
    lea     rdi, [cbuf]
    call    structures_stamp
    lea     rdi, [cbuf + GENBUF.blocks]
    mov     ecx, 37 * 256
    mov     eax, STONE
    rep     stosb
    mov     ecx, 65536 - 37 * 256
    xor     eax, eax
    rep     stosb
    pop     rbp
    ret

; check_clearing(edi top, esi filler) -> eax 0 when camp_clearing(site (8, 40, 8), top, filler) clears and surfaces
; the camp's 21 x 21 clearing (here its part in the column 0..15): `top` at y = 40 over the whole of it (corners
; and the centre), `filler` at 37..39 where there was air (not over a block that was there: GRAVEL stays, and not under
; 37: a hole at y = 36 stays), the stone at 36 and below untouched, air from 41 to 52 (stone blocks at y = 45 and 52 are
; cleared), the stone at 53 left
; ebx = top, r12d = filler
check_clearing:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12d, esi
    call    fill_cbuf
    mov     byte [cbuf + GENBUF.blocks + ((45 << 8) | (8 << 4) | 8)], STONE
    mov     byte [cbuf + GENBUF.blocks + ((52 << 8) | (8 << 4) | 8)], STONE
    mov     byte [cbuf + GENBUF.blocks + ((53 << 8) | (8 << 4) | 8)], STONE
    mov     byte [cbuf + GENBUF.blocks + ((38 << 8) | (4 << 4) | 4)], GRAVEL
    mov     byte [cbuf + GENBUF.blocks + ((36 << 8) | (6 << 4) | 6)], AIR
    mov     dword [site + SITE.kind], SITE_CAMP
    mov     dword [site + SITE.x], 8
    mov     dword [site + SITE.y], 40
    mov     dword [site + SITE.z], 8
    lea     rdi, [site]
    mov     esi, ebx
    mov     edx, r12d
    call    camp_clearing
    xor     ecx, ecx                    ; (CELL takes immediates only: these loops compare against the registers)
    lea     rdx, [cbuf + GENBUF.blocks]
    lea     r8, [top_cells]
.top:                                   ; the top block: the centre and the four corners of the column
    mov     eax, [r8 + rcx*4]
    movzx   eax, byte [rdx + rax]
    cmp     eax, ebx
    jne     .fail
    inc     ecx
    cmp     ecx, 5
    jb      .top
    xor     ecx, ecx
    lea     r8, [filler_cells]
.filler:                                ; the filler: the three layers under it, at the centre and at a corner
    mov     eax, [r8 + rcx*4]
    movzx   eax, byte [rdx + rax]
    cmp     eax, r12d
    jne     .fail
    inc     ecx
    cmp     ecx, 6
    jb      .filler
    CELL    4, 38, 4, GRAVEL            ; something there already: not replaced
    CELL    6, 36, 6, AIR               ; the filler stops at h - 3
    CELL    8, 36, 8, STONE
    CELL    0, 0, 0, STONE
    CELL    8, 41, 8, AIR
    CELL    8, 45, 8, AIR               ; the blocks in the way are cleared...
    CELL    8, 52, 8, AIR
    CELL    8, 53, 8, STONE             ; ...up to 12 above the ground and no further
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; check_dry_grass() -> eax 0 when a pig can spawn on a DRY_GRASS top (GROUND_PASSIVE), as on GRASS and not on DIRT, and a zombie
; can on DRY_GRASS (solid, opaque)
check_dry_grass:
    push    rbp
    mov     rbp, rsp
    call    arena
    mov     dword [game_time], NEW_WORLD_TIME
    BLOCK   5, 10, 5, DRY_GRASS
    SPAWN_CASE MOB_PIG, 5, 5, GROUND_PASSIVE, 1
    SPAWN_CASE MOB_ZOMBIE, 5, 5, GROUND_HOSTILE, 1
    BLOCK   7, 10, 5, GRASS
    SPAWN_CASE MOB_PIG, 7, 5, GROUND_PASSIVE, 1
    BLOCK   9, 10, 5, DIRT
    SPAWN_CASE MOB_PIG, 9, 5, GROUND_PASSIVE, 0
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    pop     rbp
    ret

; The names of the biomes in the F3 line (the four new ones too), the factions' home biomes, a camp clearing built of
; DRY_GRASS over DIRT (a savanna's materials) and of SAND over SANDSTONE, and passive mobs on DRY_GRASS.
test_new_biome_consumers:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     eax, [game_mode]
    mov     [saved], eax
    mov     eax, [game_time]
    mov     [saved + 4], eax
    mov     eax, [settings + SETTINGS.difficulty]
    mov     [saved + 8], eax
    call    check_names
    test    eax, eax
    jnz     .fail
    call    check_homes
    test    eax, eax
    jnz     .fail
    mov     edi, DRY_GRASS
    mov     esi, DIRT
    call    check_clearing
    test    eax, eax
    jnz     .fail
    mov     edi, SAND
    mov     esi, SANDSTONE
    call    check_clearing
    test    eax, eax
    jnz     .fail
    call    check_dry_grass
    test    eax, eax
    jnz     .fail
    xor     ebx, ebx
    jmp     .done
.fail:
    mov     ebx, 1
.done:
    call    mobs_clear
    call    survival_reset
    mov     eax, [saved]
    mov     [game_mode], eax
    mov     eax, [saved + 4]
    mov     [game_time], eax
    mov     eax, [saved + 8]
    mov     [settings + SETTINGS.difficulty], eax
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret
