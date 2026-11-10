; test_evsites.asm - the geometry of events: ground cells, the camp site and its tent, routes, roads,
; the site a folk belongs to, and the hop of a stuck caravan. The site_of test reads the real folk the
; structures module spawns, so a change of its slot tables fails it.
%include "common.inc"
default rel

global test_evsites_camp_site, test_evsites_route, test_evsites_site_of, test_evsites_hop
global test_evsites_road_from

extern evs_ground, evs_find_camp_site, evs_build_tent, evs_remove_tent, evs_forget_tent
extern evs_tent_placed, evs_find_route, evs_road_from, evs_site_of, evs_hop_cell
extern world_clear, world_get, world_set, world_set_raw, world_origin_x, world_origin_z
extern worldgen_set_seed, gen_seed, gen_height, roads_edges
extern sites, site_count, structures_reset, structures_step
extern mobs, mobs_clear, player, world_header

%define PX 100                          ; the test player's cell (the arena is cells -16 .. 271)
%define PLAT_LO 30                      ; the plateau: x, z in 30 .. 170
%define PLAT_HI 170

section .rodata
align 4
k_100_5:    dd 100.5
k_150_5:    dd 150.5
k_11:       dd 11.0
k_10_5:     dd 10.5
k_20_5:     dd 20.5
k_25_5:     dd 25.5
k_5_5:      dd 5.5
k_40_5:     dd 40.5
k_one:      dd 1.0
k_mone:     dd -1.0
k_zero:     dd 0.0
k_160:      dd 160.0
k_240:      dd 240.0

section .bss
alignb 4
t_out:      resd 4
t_save:     resd 8                      ; player x, y, z; site_count; gen_seed
t_sites:    resb SITE_size * 2          ; the cached sites a test replaces
t_found:    resd 4                      ; the road a test found: ax, az, bx, bz
t_buf:      resd 6 * 12                 ; ROADEDGE records of one super-region

section .text

; ---- harness ---------------------------------------------------------------------------------------

%macro BEGIN 0
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
%endmacro
; SAVE_STATE / RESTORE_STATE: the player's position, site_count and gen_seed
%macro SAVE_STATE 0
    mov     eax, [player + BODY.x]
    mov     [t_save], eax
    mov     eax, [player + BODY.y]
    mov     [t_save + 4], eax
    mov     eax, [player + BODY.z]
    mov     [t_save + 8], eax
    mov     eax, [site_count]
    mov     [t_save + 12], eax
    mov     eax, [gen_seed]
    mov     [t_save + 16], eax
    lea     rsi, [sites]
    lea     rdi, [t_sites]
    mov     ecx, (SITE_size * 2) / 8
    rep     movsq
%endmacro
%macro RESTORE_STATE 0
    mov     eax, [t_save]
    mov     [player + BODY.x], eax
    mov     eax, [t_save + 4]
    mov     [player + BODY.y], eax
    mov     eax, [t_save + 8]
    mov     [player + BODY.z], eax
    mov     eax, [t_save + 12]
    mov     [site_count], eax
    mov     edi, [t_save + 16]
    call    worldgen_set_seed
    lea     rsi, [t_sites]
    lea     rdi, [sites]
    mov     ecx, (SITE_size * 2) / 8
    rep     movsq
    mov     dword [world_origin_x], 0
    mov     dword [world_origin_z], 0
%endmacro

; PLAYER_AT: the player stands at (100.5, 11, 100.5)
%macro PLAYER_AT 0
    mov     eax, [k_100_5]
    mov     [player + BODY.x], eax
    mov     [player + BODY.z], eax
    mov     eax, [k_11]
    mov     [player + BODY.y], eax
%endmacro

; GET x, y, z -> eax: world_get of those (registers or constants)
%macro GET 3
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    call    world_get
%endmacro

; fill_plateau(edi mode): x, z in PLAT_LO .. PLAT_HI of the arena, by mode
;   0 STONE at y = 10 (flat)         1 STONE up to y = 10 or 12 by the parity of x + z (a ground span of 2)
;   2 STONE at 9, WATER at 10        3 flat, TALL_GRASS at y = 11 on every cell
; (world_set_raw: no light queue)
fill_plateau:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r14d, edi
    mov     r12d, PLAT_LO               ; z
.z:
    mov     ebx, PLAT_LO                ; x
.x:
    cmp     r14d, 2
    je      .water
    mov     edi, ebx
    mov     esi, 10
    mov     edx, r12d
    mov     ecx, STONE
    call    world_set_raw
    cmp     r14d, 1
    jne     .grass
    lea     eax, [rbx + r12]
    test    eax, 1
    jz      .next
    mov     edi, ebx
    mov     esi, 11
    mov     edx, r12d
    mov     ecx, STONE
    call    world_set_raw
    mov     edi, ebx
    mov     esi, 12
    mov     edx, r12d
    mov     ecx, STONE
    call    world_set_raw
    jmp     .next
.grass:
    cmp     r14d, 3
    jne     .next
    mov     edi, ebx
    mov     esi, 11
    mov     edx, r12d
    mov     ecx, TALL_GRASS
    call    world_set_raw
    jmp     .next
.water:
    mov     edi, ebx
    mov     esi, 9
    mov     edx, r12d
    mov     ecx, STONE
    call    world_set_raw
    mov     edi, ebx
    mov     esi, 10
    mov     edx, r12d
    mov     ecx, WATER
    call    world_set_raw
.next:
    inc     ebx
    cmp     ebx, PLAT_HI
    jle     .x
    inc     r12d
    cmp     r12d, PLAT_HI
    jle     .z
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; raw(edi x, esi y, edx z, ecx id): world_set_raw (keeps the call sites short)
%macro RAW 4
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    call    world_set_raw
%endmacro

; ---- test_evsites_camp_site ------------------------------------------------------------------------
; A flat stone plateau around the player: evs_ground reads the cells (grass and snow on top count as the
; block below; leaves, bedrock, water, lava, a top above 250 and an unloaded column do not), evs_find_camp_site
; finds a site 32 .. 56 blocks away at the plateau's height and evs_build_tent puts 50 blocks on it (the
; leader's canopy, the supply canopy and the two torch posts), recorded; evs_remove_tent takes back
; exactly those that still hold their id and forgets the record, evs_forget_tent leaves the blocks. A
; ground span of 2, a water surface and a cached village or camp within 64 blocks (not a dungeon) each
; leave no site.
test_evsites_camp_site:
    BEGIN
    SAVE_STATE
    call    world_clear
    mov     dword [site_count], 0
    PLAYER_AT
    mov     edi, 0
    call    fill_plateau
    ; -- evs_ground
    mov     edi, 105
    mov     esi, 100
    call    evs_ground
    cmp     eax, 10
    jne     .fail
    RAW     101, 11, 100, SNOW_LAYER    ; a snow layer on top: the block below
    mov     edi, 101
    mov     esi, 100
    call    evs_ground
    cmp     eax, 10
    jne     .fail
    RAW     102, 11, 100, TALL_GRASS
    mov     edi, 102
    mov     esi, 100
    call    evs_ground
    cmp     eax, 10
    jne     .fail
    RAW     103, 11, 100, LEAVES        ; leaves: no ground
    mov     edi, 103
    mov     esi, 100
    call    evs_ground
    cmp     eax, -1
    jne     .fail
    RAW     103, 11, 100, PINE_LEAVES
    mov     edi, 103
    mov     esi, 100
    call    evs_ground
    cmp     eax, -1
    jne     .fail
    RAW     103, 11, 100, BIRCH_LEAVES
    mov     edi, 103
    mov     esi, 100
    call    evs_ground
    cmp     eax, -1
    jne     .fail
    RAW     104, 10, 100, BEDROCK
    mov     edi, 104
    mov     esi, 100
    call    evs_ground
    cmp     eax, -1
    jne     .fail
    RAW     106, 10, 100, WATER
    mov     edi, 106
    mov     esi, 100
    call    evs_ground
    cmp     eax, -1
    jne     .fail
    RAW     107, 10, 100, LAVA
    mov     edi, 107
    mov     esi, 100
    call    evs_ground
    cmp     eax, -1
    jne     .fail
    RAW     108, 11, 100, STONE         ; the top at 11: ground 11
    mov     edi, 108
    mov     esi, 100
    call    evs_ground
    cmp     eax, 11
    jne     .fail
    RAW     109, 251, 100, STONE        ; a column reaching above 250
    mov     edi, 109
    mov     esi, 100
    call    evs_ground
    cmp     eax, -1
    jne     .fail
    mov     edi, 400                    ; a column that is not loaded
    mov     esi, 100
    call    evs_ground
    cmp     eax, -1
    jne     .fail
    mov     edi, 110                    ; a column holding nothing
    mov     esi, 200
    call    evs_ground
    cmp     eax, -1
    jne     .fail
    ; -- a site and its tent (a fresh plateau: the probes above are gone)
    call    world_clear
    mov     edi, 0
    call    fill_plateau
    lea     rdi, [player]
    lea     rsi, [t_out]
    call    evs_find_camp_site
    cmp     eax, 1
    jne     .fail
    mov     eax, [t_out]
    sub     eax, PX
    imul    eax, eax
    mov     ecx, [t_out + 8]
    sub     ecx, PX
    imul    ecx, ecx
    add     eax, ecx                    ; the squared distance, within 32 .. 56 give or take the cell rounding
    cmp     eax, 30 * 30
    jl      .fail
    cmp     eax, 58 * 58
    jg      .fail
    cmp     dword [t_out + 4], 10
    jne     .fail
    mov     r12d, [t_out]               ; cx
    mov     r13d, [t_out + 4]           ; H
    mov     r14d, [t_out + 8]           ; cz
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, FAC_STONEKIN
    call    evs_build_tent
    cmp     eax, 50
    jne     .fail
    call    evs_tent_placed
    cmp     eax, 50
    jne     .fail
    lea     edi, [r12 - 2]
    lea     esi, [r13 + 3]
    lea     edx, [r14 - 2]
    call    world_get                   ; the leader's roof
    cmp     eax, SMOOTH_STONE
    jne     .fail
    lea     edi, [r12 - 4]
    lea     esi, [r13 + 2]
    lea     edx, [r14 - 4]
    call    world_get                   ; a corner post, up to H + 2
    cmp     eax, FENCE
    jne     .fail
    lea     edi, [r12 + 3]
    lea     esi, [r13 + 2]
    lea     edx, [r14 + 3]
    call    world_get                   ; the supply roof at H + 2
    cmp     eax, SMOOTH_STONE
    jne     .fail
    lea     edi, [r12 + 3]
    lea     esi, [r13 + 2]
    lea     edx, [r14 - 3]
    call    world_get                   ; a torch on its post
    cmp     eax, TORCH
    jne     .fail
    lea     edi, [r12 + 3]
    lea     esi, [r13 + 1]
    lea     edx, [r14 - 3]
    call    world_get
    cmp     eax, FENCE
    jne     .fail
    lea     edi, [r12 - 2]              ; a recorded cell changed since stays what it is
    lea     esi, [r13 + 3]
    lea     edx, [r14 - 2]
    mov     ecx, STONE
    call    world_set
    call    evs_remove_tent
    cmp     eax, 49
    jne     .fail
    call    evs_tent_placed
    test    eax, eax
    jnz     .fail
    lea     edi, [r12 - 2]
    lea     esi, [r13 + 3]
    lea     edx, [r14 - 2]
    call    world_get
    cmp     eax, STONE
    jne     .fail
    lea     edi, [r12 - 4]
    lea     esi, [r13 + 2]
    lea     edx, [r14 - 4]
    call    world_get                   ; the rest is AIR again
    test    eax, eax
    jnz     .fail
    lea     edi, [r12 + 3]
    lea     esi, [r13 + 2]
    lea     edx, [r14 - 3]
    call    world_get
    test    eax, eax
    jnz     .fail
    lea     edi, [r12 - 2]              ; the leftover cell cleared by hand: a Bandits tent has a PLANKS roof
    lea     esi, [r13 + 3]
    lea     edx, [r14 - 2]
    xor     ecx, ecx
    call    world_set
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, FAC_BANDITS
    call    evs_build_tent
    cmp     eax, 50
    jne     .fail
    lea     edi, [r12 - 2]
    lea     esi, [r13 + 3]
    lea     edx, [r14 - 2]
    call    world_get
    cmp     eax, PLANKS
    jne     .fail
    call    evs_forget_tent             ; forgotten: nothing to remove, the blocks stay
    call    evs_remove_tent
    test    eax, eax
    jnz     .fail
    lea     edi, [r12 - 2]
    lea     esi, [r13 + 3]
    lea     edx, [r14 - 2]
    call    world_get
    cmp     eax, PLANKS
    jne     .fail
    mov     edi, r12d                   ; over the tent still standing: every cell is taken, nothing changes
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, FAC_CULT
    call    evs_build_tent
    test    eax, eax
    jnz     .fail
    call    evs_tent_placed
    test    eax, eax
    jnz     .fail
    lea     edi, [r12 - 2]
    lea     esi, [r13 + 3]
    lea     edx, [r14 - 2]
    call    world_get
    cmp     eax, PLANKS
    jne     .fail
    ; -- grass on every cell: the site is found and the posts replace the grass
    call    world_clear
    mov     edi, 3
    call    fill_plateau
    lea     rdi, [player]
    lea     rsi, [t_out]
    call    evs_find_camp_site
    cmp     eax, 1
    jne     .fail
    cmp     dword [t_out + 4], 10
    jne     .fail
    mov     edi, [t_out]
    mov     esi, [t_out + 4]
    mov     edx, [t_out + 8]
    mov     ecx, FAC_CULT
    call    evs_build_tent
    cmp     eax, 50
    jne     .fail
    ; -- no site: a ground span of 2, a water surface
    call    world_clear
    mov     edi, 1
    call    fill_plateau
    lea     rdi, [player]
    lea     rsi, [t_out]
    call    evs_find_camp_site
    test    eax, eax
    jnz     .fail
    call    world_clear
    mov     edi, 2
    call    fill_plateau
    lea     rdi, [player]
    lea     rsi, [t_out]
    call    evs_find_camp_site
    test    eax, eax
    jnz     .fail
    ; -- a village or a camp within 64 blocks of every candidate blocks it; a dungeon does not
    call    world_clear
    mov     edi, 0
    call    fill_plateau
    lea     rbx, [sites]
    mov     dword [rbx + SITE.kind], SITE_DUNGEON
    mov     dword [rbx + SITE.x], PX
    mov     dword [rbx + SITE.z], PX
    mov     dword [site_count], 1
    lea     rdi, [player]
    lea     rsi, [t_out]
    call    evs_find_camp_site
    cmp     eax, 1
    jne     .fail
    mov     dword [rbx + SITE.kind], SITE_VILLAGE
    lea     rdi, [player]
    lea     rsi, [t_out]
    call    evs_find_camp_site
    test    eax, eax
    jnz     .fail
    mov     dword [rbx + SITE.kind], SITE_CAMP
    lea     rdi, [player]
    lea     rsi, [t_out]
    call    evs_find_camp_site
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    jmp     .done
.fail:
    mov     eax, 1
.done:
    mov     ebx, eax
    call    evs_forget_tent
    RESTORE_STATE
    call    world_clear
    mov     eax, ebx
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- test_evsites_route ----------------------------------------------------------------------------
; With seed 42, over 300 starts: a route found ends 160 .. 240 blocks away and re-checks (the samples
; of its N = (floor(L) + 7) / 8 equal steps are at least 98 and within 3 of the one before, the first of
; the start's own height); no start found is a start under 90 that got one, and at least one start is on
; land with a route and at least one in the sea (height < 90) with none.
; r12d = routes verified, r13d = sea starts, r14d = start index, r15d = the start's height, [rsp] ax, [rsp+4] az.
test_evsites_route:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    SAVE_STATE
    mov     edi, 42
    call    worldgen_set_seed
    xor     r12d, r12d
    xor     r13d, r13d
    xor     r14d, r14d
.start:
    imul    eax, r14d, 61
    sub     eax, 9000
    mov     [rsp], eax
    imul    eax, r14d, 83
    sub     eax, 12000
    mov     [rsp + 4], eax
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    call    gen_height
    mov     r15d, eax
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    lea     rdx, [t_out]
    call    evs_find_route
    test    eax, eax
    jz      .none
    cmp     r15d, 90
    jl      .fail                       ; nothing leaves the sea
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    call    check_route
    test    eax, eax
    jnz     .fail
    inc     r12d
    jmp     .next
.none:
    cmp     r15d, 90
    jge     .next
    inc     r13d
.next:
    inc     r14d
    cmp     r14d, 300
    jb      .start
    test    r12d, r12d
    jz      .fail
    test    r13d, r13d
    jz      .fail
    xor     eax, eax
    jmp     .done
.fail:
    mov     eax, 1
.done:
    mov     ebx, eax
    RESTORE_STATE
    mov     eax, ebx
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; check_route(edi ax, esi az) -> eax 0 when t_out is a route from that start that holds the rules of
; evs_find_route (leaf apart from gen_height)
; Frame: [rsp] ax, [rsp+4] az, [rsp+8] dx, [rsp+12] dz, [rsp+16] N, [rsp+20] the previous height.
check_route:
    push    rbx
    sub     rsp, 32
    mov     [rsp], edi
    mov     [rsp + 4], esi
    mov     eax, [t_out]
    sub     eax, edi
    mov     [rsp + 8], eax
    mov     eax, [t_out + 4]
    sub     eax, esi
    mov     [rsp + 12], eax
    mov     eax, [rsp + 8]
    imul    eax, eax
    mov     ecx, [rsp + 12]
    imul    ecx, ecx
    add     eax, ecx
    cvtsi2ss xmm0, eax
    sqrtss  xmm0, xmm0
    comiss  xmm0, [k_160]
    jb      .bad
    comiss  xmm0, [k_240]
    ja      .bad
    cvttss2si eax, xmm0
    add     eax, 7
    shr     eax, 3
    mov     [rsp + 16], eax
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    call    gen_height
    mov     [rsp + 20], eax
    mov     ebx, 1
.k:
    cmp     ebx, [rsp + 16]
    jg      .ok
    mov     eax, [rsp + 8]
    imul    eax, ebx
    cdq
    idiv    dword [rsp + 16]
    add     eax, [rsp]
    mov     edi, eax
    mov     eax, [rsp + 12]
    imul    eax, ebx
    cdq
    idiv    dword [rsp + 16]
    add     eax, [rsp + 4]
    mov     esi, eax
    call    gen_height
    cmp     eax, 98
    jl      .bad
    mov     ecx, eax
    sub     ecx, [rsp + 20]
    cmp     ecx, 3
    jg      .bad
    cmp     ecx, -3
    jl      .bad
    mov     [rsp + 20], eax
    inc     ebx
    jmp     .k
.ok:
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    add     rsp, 32
    pop     rbx
    ret

; ---- test_evsites_site_of --------------------------------------------------------------------------
; A Stonekin camp at (100, 100) and a village at (200, 200) populated by structures_step with the player
; 70 blocks from both: the camp's leader gives EVK_SITE and the trader EVK_ROAD with the camp's centre,
; the village elder EVK_SITE with the village's, a village trader, a guard, a worker, a champion and a
; captive give 0 (so the slot tables of structures.asm are the plan's). With the origin moved the centre
; is absolute; a folk with patrol != 0 or a mob that is not a folk gives 0.
; r12d = the found-folk bits, r13 = the camp leader, r14 = the mob scanned, r15d = the mobs left.
test_evsites_site_of:
    BEGIN
    SAVE_STATE
    call    world_clear
    call    mobs_clear
    call    structures_reset
    lea     rdi, [world_header + WORLDHDR.site_count]
    mov     ecx, (WORLDHDR.sites + MAX_SITESTATES * SITESTATE_size - WORLDHDR.site_count) / 4
    xor     eax, eax
    rep     stosd
    mov     eax, [k_150_5]
    mov     [player + BODY.x], eax
    mov     [player + BODY.z], eax
    mov     eax, [k_11]
    mov     [player + BODY.y], eax
    lea     rdi, [sites]
    mov     ecx, (SITE_size * 2) / 4
    xor     eax, eax
    rep     stosd
    lea     rbx, [sites]
    mov     dword [rbx + SITE.kind], SITE_CAMP
    mov     dword [rbx + SITE.index], FAC_STONEKIN
    mov     dword [rbx + SITE.x], 100
    mov     dword [rbx + SITE.y], 10
    mov     dword [rbx + SITE.z], 100
    mov     dword [rbx + SITE.lo_x], 84
    mov     dword [rbx + SITE.lo_y], 0
    mov     dword [rbx + SITE.lo_z], 84
    mov     dword [rbx + SITE.hi_x], 116
    mov     dword [rbx + SITE.hi_y], 20
    mov     dword [rbx + SITE.hi_z], 116
    mov     dword [rbx + SITE_size + SITE.kind], SITE_VILLAGE
    mov     dword [rbx + SITE_size + SITE.index], 0
    mov     dword [rbx + SITE_size + SITE.x], 200
    mov     dword [rbx + SITE_size + SITE.y], 10
    mov     dword [rbx + SITE_size + SITE.z], 200
    mov     dword [rbx + SITE_size + SITE.slot], 1
    mov     dword [rbx + SITE_size + SITE.lo_x], 190
    mov     dword [rbx + SITE_size + SITE.lo_z], 190
    mov     dword [rbx + SITE_size + SITE.hi_x], 210
    mov     dword [rbx + SITE_size + SITE.hi_y], 20
    mov     dword [rbx + SITE_size + SITE.hi_z], 210
    mov     dword [site_count], 2
    mov     r15d, 61
.step:
    call    structures_step
    dec     r15d
    jnz     .step
    xor     r12d, r12d
    xor     r13d, r13d
    lea     r14, [mobs]
    mov     r15d, MAX_MOBS
.mob:
    cmp     dword [r14 + MOB.type], MOB_FOLK
    jne     .next
    cmp     dword [r14 + MOB.patrol], 0
    jne     .next
    mov     rdi, r14
    lea     rsi, [t_out]
    mov     dword [t_out], -7
    call    evs_site_of
    movzx   ecx, byte [r14 + MOB.role]
    movzx   edx, byte [r14 + MOB.faction]
    cmp     ecx, ROLE_LEADER
    je      .leader
    cmp     ecx, ROLE_TRADER
    je      .trader
    test    eax, eax                    ; every other role: nobody's site
    jnz     .fail
    cmp     dword [t_out], -7
    jne     .fail
    cmp     ecx, ROLE_GUARD
    jne     .next
    or      r12d, 16
    jmp     .next
.leader:
    test    edx, edx
    jz      .elder
    cmp     edx, FAC_STONEKIN
    jne     .fail
    cmp     eax, EVK_SITE
    jne     .fail
    cmp     dword [t_out], 100
    jne     .fail
    cmp     dword [t_out + 4], 100
    jne     .fail
    or      r12d, 1
    mov     r13, r14
    jmp     .next
.elder:
    cmp     eax, EVK_SITE
    jne     .fail
    cmp     dword [t_out], 200
    jne     .fail
    cmp     dword [t_out + 4], 200
    jne     .fail
    or      r12d, 4
    jmp     .next
.trader:
    test    edx, edx
    jz      .vtrader
    cmp     edx, FAC_STONEKIN
    jne     .fail
    cmp     eax, EVK_ROAD
    jne     .fail
    cmp     dword [t_out], 100
    jne     .fail
    cmp     dword [t_out + 4], 100
    jne     .fail
    or      r12d, 2
    jmp     .next
.vtrader:
    test    eax, eax
    jnz     .fail
    or      r12d, 8
.next:
    add     r14, MOB_size
    dec     r15d
    jnz     .mob
    cmp     r12d, 31
    jne     .fail
    ; the origin moved: absolute cells
    add     dword [world_origin_x], 512
    sub     dword [world_origin_z], 512
    mov     rdi, r13
    lea     rsi, [t_out]
    call    evs_site_of
    cmp     eax, EVK_SITE
    jne     .fail
    cmp     dword [t_out], 612
    jne     .fail
    cmp     dword [t_out + 4], -412
    jne     .fail
    mov     dword [world_origin_x], 0
    mov     dword [world_origin_z], 0
    ; a folk of an event or a patrol (patrol != 0) belongs to no site
    mov     dword [r13 + MOB.patrol], 5
    mov     rdi, r13
    lea     rsi, [t_out]
    call    evs_site_of
    test    eax, eax
    jnz     .fail
    mov     dword [r13 + MOB.patrol], 0
    mov     dword [r13 + MOB.type], MOB_ZOMBIE
    mov     rdi, r13
    lea     rsi, [t_out]
    call    evs_site_of
    test    eax, eax
    jnz     .fail
    mov     dword [r13 + MOB.type], MOB_FOLK
    mov     rdi, r13                    ; and back: the leader is a site's again
    lea     rsi, [t_out]
    call    evs_site_of
    cmp     eax, EVK_SITE
    jne     .fail
    xor     eax, eax
    jmp     .done
.fail:
    mov     eax, 1
.done:
    mov     ebx, eax
    call    mobs_clear
    call    structures_reset
    lea     rdi, [world_header + WORLDHDR.site_count]
    mov     ecx, (WORLDHDR.sites + MAX_SITESTATES * SITESTATE_size - WORLDHDR.site_count) / 4
    xor     eax, eax
    rep     stosd
    RESTORE_STATE
    call    world_clear
    mov     eax, ebx
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- test_evsites_hop ------------------------------------------------------------------------------
; Along +x from (10.5, 20.5): stone at cells 10 .. 13 (nearer than 4 blocks: ignored), water over 14 .. 24,
; stone from 25 -> the cell 25 at ground 10. The same row read along +z from (25.5, 5.5) and along -x from
; (40.5, 20.5) gives (25, 20) and (36, 20). The farthest cell is 48 blocks: stone only at cell 58 is found,
; only at 59 (and all water) gives -1 and leaves out alone.
test_evsites_hop:
    BEGIN
    SAVE_STATE
    call    world_clear
    mov     ebx, 10
.near:
    RAW     ebx, 10, 20, STONE
    inc     ebx
    cmp     ebx, 13
    jle     .near
    mov     ebx, 14
.water:
    RAW     ebx, 9, 20, STONE
    RAW     ebx, 10, 20, WATER
    inc     ebx
    cmp     ebx, 24
    jle     .water
    mov     ebx, 25
.far:
    RAW     ebx, 10, 20, STONE
    inc     ebx
    cmp     ebx, 40
    jle     .far
    movss   xmm0, [k_10_5]
    movss   xmm1, [k_20_5]
    movss   xmm2, [k_one]
    movss   xmm3, [k_zero]
    lea     rdi, [t_out]
    call    evs_hop_cell
    cmp     eax, 10
    jne     .fail
    cmp     dword [t_out], 25
    jne     .fail
    cmp     dword [t_out + 4], 20
    jne     .fail
    movss   xmm0, [k_25_5]
    movss   xmm1, [k_5_5]
    movss   xmm2, [k_zero]
    movss   xmm3, [k_one]
    lea     rdi, [t_out]
    call    evs_hop_cell
    cmp     eax, 10
    jne     .fail
    cmp     dword [t_out], 25
    jne     .fail
    cmp     dword [t_out + 4], 20
    jne     .fail
    movss   xmm0, [k_40_5]
    movss   xmm1, [k_20_5]
    movss   xmm2, [k_mone]
    movss   xmm3, [k_zero]
    lea     rdi, [t_out]
    call    evs_hop_cell
    cmp     eax, 10
    jne     .fail
    cmp     dword [t_out], 36
    jne     .fail
    cmp     dword [t_out + 4], 20
    jne     .fail
    call    world_clear                 ; the farthest cell: 10.5 + 48 = 58.5
    RAW     58, 10, 20, STONE
    movss   xmm0, [k_10_5]
    movss   xmm1, [k_20_5]
    movss   xmm2, [k_one]
    movss   xmm3, [k_zero]
    lea     rdi, [t_out]
    call    evs_hop_cell
    cmp     eax, 10
    jne     .fail
    cmp     dword [t_out], 58
    jne     .fail
    call    world_clear
    RAW     59, 10, 20, STONE
    mov     dword [t_out], -7
    mov     dword [t_out + 4], -7
    movss   xmm0, [k_10_5]
    movss   xmm1, [k_20_5]
    movss   xmm2, [k_one]
    movss   xmm3, [k_zero]
    lea     rdi, [t_out]
    call    evs_hop_cell
    cmp     eax, -1
    jne     .fail
    cmp     dword [t_out], -7
    jne     .fail
    call    world_clear                 ; water all the way
    mov     ebx, 14
.sea:
    RAW     ebx, 9, 20, STONE
    RAW     ebx, 10, 20, WATER
    inc     ebx
    cmp     ebx, 70
    jle     .sea
    movss   xmm0, [k_10_5]
    movss   xmm1, [k_20_5]
    movss   xmm2, [k_one]
    movss   xmm3, [k_zero]
    lea     rdi, [t_out]
    call    evs_hop_cell
    cmp     eax, -1
    jne     .fail
    xor     eax, eax
    jmp     .done
.fail:
    mov     eax, 1
.done:
    mov     ebx, eax
    RESTORE_STATE
    call    world_clear
    mov     eax, ebx
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- test_evsites_road_from ------------------------------------------------------------------------
; With seed 42 the first super-region of (0 .. 3)^2 whose first road is 64 .. 900 blocks long: from its
; A end evs_road_from gives its B end and from B its A end (the first road in order); a cell next to a
; camp's centre gives none and leaves out alone.
; r12d = sx, r13d = sz
test_evsites_road_from:
    BEGIN
    SAVE_STATE
    mov     edi, 42
    call    worldgen_set_seed
    xor     r13d, r13d
.sz:
    xor     r12d, r12d
.sx:
    mov     edi, r12d
    mov     esi, r13d
    lea     rdx, [t_buf]
    call    roads_edges
    test    eax, eax
    jz      .next
    mov     eax, [t_buf + ROADEDGE.bx]
    sub     eax, [t_buf + ROADEDGE.ax]
    imul    eax, eax
    mov     ecx, [t_buf + ROADEDGE.bz]
    sub     ecx, [t_buf + ROADEDGE.az]
    imul    ecx, ecx
    add     eax, ecx
    cmp     eax, 64 * 64
    jb      .next
    cmp     eax, 900 * 900
    jbe     .found
.next:
    inc     r12d
    cmp     r12d, 3
    jle     .sx
    inc     r13d
    cmp     r13d, 3
    jle     .sz
    jmp     .fail                       ; no such road in 16 super-regions
.found:
    mov     eax, [t_buf + ROADEDGE.ax]
    mov     [t_found], eax
    mov     eax, [t_buf + ROADEDGE.az]
    mov     [t_found + 4], eax
    mov     eax, [t_buf + ROADEDGE.bx]
    mov     [t_found + 8], eax
    mov     eax, [t_buf + ROADEDGE.bz]
    mov     [t_found + 12], eax
    mov     edi, [t_found]
    mov     esi, [t_found + 4]
    lea     rdx, [t_out]
    call    evs_road_from
    cmp     eax, 1
    jne     .fail
    mov     eax, [t_out]
    cmp     eax, [t_found + 8]
    jne     .fail
    mov     eax, [t_out + 4]
    cmp     eax, [t_found + 12]
    jne     .fail
    mov     edi, [t_found + 8]
    mov     esi, [t_found + 12]
    lea     rdx, [t_out]
    call    evs_road_from
    cmp     eax, 1
    jne     .fail
    mov     eax, [t_out]
    cmp     eax, [t_found]
    jne     .fail
    mov     eax, [t_out + 4]
    cmp     eax, [t_found + 4]
    jne     .fail
    mov     dword [t_out], -7
    mov     edi, [t_found]
    add     edi, 3
    mov     esi, [t_found + 4]
    lea     rdx, [t_out]
    call    evs_road_from
    test    eax, eax
    jnz     .fail
    mov     edi, [t_found]
    mov     esi, [t_found + 4]
    inc     esi
    lea     rdx, [t_out]
    call    evs_road_from
    test    eax, eax
    jnz     .fail
    cmp     dword [t_out], -7
    jne     .fail
    xor     eax, eax
    jmp     .done
.fail:
    mov     eax, 1
.done:
    mov     ebx, eax
    RESTORE_STATE
    mov     eax, ebx
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
