; test_structures.asm - the region plans, the built dungeons, villages and crypts (through gen_column),
; the loot of generated chests, the village NPCs, the per-site state (dungeon kills, cleared dungeons,
; the crypt's boss) and the sites cached around the player. Written as properties of the plan's
; rules, so they hold for any terrain: a site is looked up by planning regions, not by coordinates.
%include "common.inc"
default rel

global test_structure_sites_deterministic, test_dungeon_built_with_chests
global test_village_built_with_npcs, test_dungeon_clears_after_kills
global test_crypt_spawns_boss_once, test_sitestate_eviction, test_region_plan_camps

extern world_clear, world_header, worldgen_set_seed
extern region_plan, structures_fill_chest, structures_refresh, structures_shift
extern sites, site_count, site_state, structures_reset, structures_step, structures_nearest
extern structures_on_mob_killed, structures_on_boss_killed
extern gen_column, gen_height, gen_biome
extern world_origin_x, world_origin_z
extern mobs, mobs_clear, mob_spawn, mob_count_type
extern rpg_state, rpg_reset, rpg_xp_need
extern fx_clear, survival_reset, combat_reset
extern game_mode, settings, player
extern item_gear

%define TG_W 8                          ; the grid of generated columns: 8 x 4 (TG_W is a shift of 3 below)
%define TG_H 4
%define T_REGIONS 9
%define EXIT_SWEEP 6                    ; check_site_exits looks at the regions -6 .. 6

section .rodata
align 4
k_one:   dd 1.0
k_half:  dd 0.5
k_3_5:   dd 3.5
k_10:    dd 10.0
k_6:     dd 6.0
k_8_5:   dd 8.5
k_11:    dd 11.0
k_20:    dd 20.0
k_41:    dd 41.0
k_61:    dd 61.0
k_70:    dd 70.0
k_100_5: dd 100.5
k_270_5: dd 270.5
k_300_5: dd 300.5
k_m100_5: dd -100.5
k_512:   dd 512.0
k_106_5: dd 106.5
k_94_5:  dd 94.5

; the plan's trigger boxes relative to a site's (x, y, z): lo dx, dy, dz, hi dx, dy, dz, by kind - 1
t_box:
    dd -16,  0, -16,  16, 10,  16
    dd  -5, -1,  -5,  19,  5,  19
    dd  -7,  0,  -7,   7,  7,   7
    dd -10, -2, -10,  10,  8,  10
; the biomes each faction's camp may stand in: a bit per BIOME_*
t_homes:
    dd (1 << BIOME_PLAINS) | (1 << BIOME_FOREST)
    dd (1 << BIOME_FOREST) | (1 << BIOME_MOUNTAINS)
    dd (1 << BIOME_SWAMP)
    dd (1 << BIOME_SNOW) | (1 << BIOME_MOUNTAINS)
    dd (1 << BIOME_MOUNTAINS)
; the regions searched for a site and compared: (arx, arz) pairs, the origin's region first
t_regions:
    dd 0, 0,  1, 0,  0, 1,  1, 1,  -1, 0,  0, -1,  -1, -1,  2, 0,  0, 2
; the centres of a dungeon's three rooms relative to its site: (dx, dz)
room_cx:
    dd 0, 0,  14, 0,  14, 14

section .bss
alignb 64
tg_bufs: resb TG_W * TG_H * GENBUF_size
tg_done: resb TG_W * TG_H
tg_cx0:  resd 1
tg_cz0:  resd 1
alignb 16
tcont:   resb CONTAINER_size
tcont2:  resb CONTAINER_size
plan_a:  resb MAX_REGION_SITES * SITE_size
plan_b:  resb MAX_REGION_SITES * SITE_size
snap_a:  resb 4 * MAX_REGION_SITES * SITE_size  ; the plans of the first 4 regions, seed 42
snap_b:  resb 4 * MAX_REGION_SITES * SITE_size  ; ... seed 43
snap_na: resd 4
snap_nb: resd 4
fsite:   resb 3 * SITE_size                     ; fabricated sites
alignb 64
tg_spare: resb GENBUF_size                     ; a GENBUF outside the grid

section .text

; zero_sites(): empties the persistent site table in the world header
zero_sites:
    lea     rdi, [world_header + WORLDHDR.site_count]
    mov     ecx, (WORLDHDR.sites + MAX_SITESTATES * SITESTATE_size - WORLDHDR.site_count) / 4
    xor     eax, eax
    rep     stosd
    ret

; fab_site(rdi SITE* dst, esi kind, edx x, ecx y, r8d z, r9d slot): a site of region (0, 0) with the
; plan's trigger box of its kind (leaf)
fab_site:
    mov     [rdi + SITE.kind], esi
    mov     dword [rdi + SITE.index], 0
    mov     [rdi + SITE.x], edx
    mov     [rdi + SITE.y], ecx
    mov     [rdi + SITE.z], r8d
    mov     dword [rdi + SITE.rx], 0
    mov     dword [rdi + SITE.rz], 0
    mov     [rdi + SITE.slot], r9d
    lea     eax, [rsi - 1]
    imul    eax, eax, 24
    lea     r10, [t_box]
    add     r10, rax
    mov     eax, [r10]
    add     eax, edx
    mov     [rdi + SITE.lo_x], eax
    mov     eax, [r10 + 4]
    add     eax, ecx
    mov     [rdi + SITE.lo_y], eax
    mov     eax, [r10 + 8]
    add     eax, r8d
    mov     [rdi + SITE.lo_z], eax
    mov     eax, [r10 + 12]
    add     eax, edx
    mov     [rdi + SITE.hi_x], eax
    mov     eax, [r10 + 16]
    add     eax, ecx
    mov     [rdi + SITE.hi_y], eax
    mov     eax, [r10 + 20]
    add     eax, r8d
    mov     [rdi + SITE.hi_z], eax
    ret

; find_site(edi kind, esi index) -> rax the site of that kind and index in sites[], or 0 (leaf)
find_site:
    lea     rax, [sites]
    mov     ecx, [site_count]
    test    ecx, ecx
    jz      .none
.l:
    cmp     [rax + SITE.kind], edi
    jne     .n
    cmp     [rax + SITE.index], esi
    je      .ret
.n:
    add     rax, SITE_size
    dec     ecx
    jnz     .l
.none:
    xor     eax, eax
.ret:
    ret

; first_mob() -> rax the first live mob, 0 when there is none (leaf)
first_mob:
    lea     rax, [mobs]
    mov     ecx, MAX_MOBS
.l:
    cmp     dword [rax + MOB.type], MOB_NONE
    jne     .ret
    add     rax, MOB_size
    dec     ecx
    jnz     .l
    xor     eax, eax
.ret:
    ret

; origin_of(rdi SITESTATE*) -> eax the MOB.origin of that record: its index + 1 (leaf)
origin_of:
    lea     rax, [world_header + WORLDHDR.sites]
    sub     rdi, rax
    mov     eax, edi
    xor     edx, edx
    mov     ecx, SITESTATE_size
    div     ecx
    inc     eax
    ret

; pick_site(edi kind, rsi SITE* dst) -> eax 1 when one of the planned regions (t_regions order) has a
; site of that kind: the first one is copied to dst
pick_site:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r12d, edi
    mov     r13, rsi
    xor     ebx, ebx
.region:
    lea     rax, [t_regions]
    mov     edi, [rax + rbx*8]
    mov     esi, [rax + rbx*8 + 4]
    lea     rdx, [plan_a]
    call    region_plan
    mov     r14d, eax
    lea     r15, [plan_a]
.site:
    test    r14d, r14d
    jz      .next
    cmp     [r15 + SITE.kind], r12d
    je      .found
    add     r15, SITE_size
    dec     r14d
    jmp     .site
.found:
    mov     rsi, r15
    mov     rdi, r13
    mov     ecx, SITE_size / 8
    rep     movsq
    mov     eax, 1
    jmp     .ret
.next:
    inc     ebx
    cmp     ebx, T_REGIONS
    jb      .region
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- generated columns, a grid of GENBUFs filled on first use ----------------------------------

; tg_reset(edi cx0, esi cz0): the grid covers the columns cx0 .. cx0 + 7, cz0 .. cz0 + 3, none made yet
tg_reset:
    mov     [tg_cx0], edi
    mov     [tg_cz0], esi
    lea     rdi, [tg_done]
    mov     ecx, TG_W * TG_H
    xor     eax, eax
    rep     stosb
    ret

; tg_buf(edi acx, esi acz) -> rax the GENBUF of that column of the grid (gen_column on first use), 0
; outside the grid
tg_buf:
    push    rbx
    push    r12
    push    r13
    mov     r12d, edi
    mov     r13d, esi
    sub     edi, [tg_cx0]
    cmp     edi, TG_W
    jae     .none
    sub     esi, [tg_cz0]
    cmp     esi, TG_H
    jae     .none
    lea     eax, [rdi + rsi*8]          ; slot = iz * TG_W + ix
    mov     ebx, eax
    imul    eax, eax, GENBUF_size
    lea     rcx, [tg_bufs]
    add     rcx, rax
    lea     rdx, [tg_done]
    cmp     byte [rdx + rbx], 0
    jne     .have
    mov     byte [rdx + rbx], 1
    mov     [rcx + GENBUF.cx], r12d
    mov     [rcx + GENBUF.cz], r13d
    mov     rbx, rcx
    mov     rdi, rcx
    call    gen_column
    mov     rax, rbx
    jmp     .ret
.have:
    mov     rax, rcx
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; tg_blk(edi x, esi y, edx z) -> eax the generated block at that absolute cell, 0xFF outside the grid
tg_blk:
    push    rbx
    push    r12
    push    r13
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    sar     edi, 4
    mov     esi, edx
    sar     esi, 4
    call    tg_buf
    test    rax, rax
    jz      .out
    cmp     r12d, 255
    ja      .out
    and     ebx, 15
    mov     ecx, r13d
    and     ecx, 15
    shl     ecx, 4
    or      ecx, ebx
    shl     r12d, 8
    or      ecx, r12d
    movzx   eax, byte [rax + rcx + GENBUF.blocks]
    jmp     .ret
.out:
    mov     eax, 0xFF
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; tg_chest(edi x, esi y, edx z) -> rax the GENCHEST the generator recorded at that cell, or 0
tg_chest:
    push    rbx
    push    r12
    push    r13
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    sar     edi, 4
    mov     esi, edx
    sar     esi, 4
    call    tg_buf
    test    rax, rax
    jz      .none
    mov     ecx, [rax + GENBUF.nchests]
    lea     rdx, [rax + GENBUF.chests]
.l:
    test    ecx, ecx
    jz      .none
    cmp     [rdx + GENCHEST.x], ebx
    jne     .n
    cmp     [rdx + GENCHEST.y], r12d
    jne     .n
    cmp     [rdx + GENCHEST.z], r13d
    jne     .n
    mov     rax, rdx
    jmp     .ret
.n:
    add     rdx, GENCHEST_size
    dec     ecx
    jmp     .l
.none:
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; block_at(rdi SITE*, esi dx, edx dy, ecx dz) -> eax the generated block at (site x + dx, site y + dy,
; site z + dz)
block_at:
    mov     eax, [rdi + SITE.x]
    add     eax, esi
    mov     esi, [rdi + SITE.y]
    add     esi, edx
    mov     edx, [rdi + SITE.z]
    add     edx, ecx
    mov     edi, eax
    jmp     tg_blk

; is_open(eax id) -> eax 1 for a block a player walks through: air, tall grass, a snow layer (leaf)
is_open:
    test    eax, eax
    jz      .yes
    cmp     eax, TALL_GRASS
    je      .yes
    cmp     eax, SNOW_LAYER
    je      .yes
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; EXPECT_AIR dx, dy, dz: the generated block at that offset from the site in rbx is AIR
%macro EXPECT_AIR 3
    mov     rdi, rbx
    mov     esi, %1
    mov     edx, %2
    mov     ecx, %3
    call    block_at
    test    eax, eax
    jnz     .fail
%endmacro

; EXPECT_ID dx, dy, dz, id: the generated block at that offset from the site in rbx is `id`
%macro EXPECT_ID 4
    mov     rdi, rbx
    mov     esi, %1
    mov     edx, %2
    mov     ecx, %3
    call    block_at
    cmp     eax, %4
    jne     .fail
%endmacro

; chest_ok(rdi GENCHEST*, esi gears, edx tier, ecx min_rar) -> eax 0 when structures_fill_chest makes
; the generated chest a CONT_CHEST at its cell that holds loot and exactly `gears` rolled gear pieces
; (each with a seed, of that tier and at least that rarity), clearing the cells it is given, and
; makes the same chest on every call
; Frame: [rsp] gear pieces, [rsp+4] other items, [rsp+8] gears wanted, [rsp+12] tier, [rsp+16] lowest
; rarity.
chest_ok:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     [rsp + 8], esi
    mov     [rsp + 12], edx
    mov     [rsp + 16], ecx
    mov     rbx, rdi
    lea     rdi, [tcont]
    mov     ecx, CONTAINER_size
    mov     al, 0x5A
    rep     stosb                       ; garbage in the cells: the fill must clear them
    lea     rdi, [tcont]
    mov     rsi, rbx
    call    structures_fill_chest
    lea     rdi, [tcont2]
    mov     ecx, CONTAINER_size
    xor     eax, eax
    rep     stosb
    lea     rdi, [tcont2]
    mov     rsi, rbx
    call    structures_fill_chest
    lea     rsi, [tcont + CONTAINER.slots]
    lea     rdi, [tcont2 + CONTAINER.slots]
    mov     ecx, 27 * 4
    repe cmpsb
    jne     .bad                        ; not the same chest twice
    cmp     byte [tcont + CONTAINER.kind], CONT_CHEST
    jne     .bad
    mov     eax, [rbx + GENCHEST.x]
    cmp     eax, [tcont + CONTAINER.x]
    jne     .bad
    mov     eax, [rbx + GENCHEST.y]
    cmp     eax, [tcont + CONTAINER.y]
    jne     .bad
    mov     eax, [rbx + GENCHEST.z]
    cmp     eax, [tcont + CONTAINER.z]
    jne     .bad
    mov     qword [rsp], 0
    xor     r15d, r15d
.cell:
    movzx   eax, byte [tcont + CONTAINER.slots + r15*4 + ITEMSTACK.id]
    test    eax, eax
    jz      .cnext
    cmp     byte [tcont + CONTAINER.slots + r15*4 + ITEMSTACK.count], 0
    je      .cnext
    lea     rcx, [item_gear]
    cmp     byte [rcx + rax], 0
    jne     .gear
    inc     dword [rsp + 4]
    jmp     .cnext
.gear:
    inc     dword [rsp]
    movzx   eax, word [tcont + CONTAINER.slots + r15*4 + ITEMSTACK.dmg]
    test    eax, GEAR_SEED_MASK
    jz      .bad                        ; no seed: not a rolled piece
    mov     ecx, eax
    shr     ecx, GEAR_RARITY_SHIFT
    cmp     ecx, [rsp + 16]
    jb      .bad                        ; below the table's lowest rarity
    shr     eax, GEAR_TIER_SHIFT
    and     eax, 15
    cmp     eax, [rsp + 12]
    jne     .bad
.cnext:
    inc     r15d
    cmp     r15d, 27
    jb      .cell
    mov     eax, [rsp]
    cmp     eax, [rsp + 8]
    jne     .bad
    cmp     dword [rsp + 4], 0
    je      .bad                        ; a chest holding nothing but gear
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- test 1: the plans ------------------------------------------------------------------------

; check_plan(rdi SITE* base, esi count, edx arx, ecx arz) -> eax 0 when every site of the plan obeys
; the plan's rules: its slot, region, kind order, counts per kind (1 village, 2 dungeons, 1 crypt, a
; crypt only in regions with even arx and arz), position inside the region, trigger box (the plan's
; numbers, around the position) and y range by kind
; Frame: [rsp] villages, [rsp+4] dungeons, [rsp+8] crypts, [rsp+12] the previous kind.
check_plan:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     r12, rdi
    mov     r13d, esi
    mov     r14d, edx
    mov     r15d, ecx
    mov     qword [rsp], 0
    mov     qword [rsp + 8], 0
    xor     ebx, ebx
.site:
    cmp     ebx, r13d
    jae     .counts
    imul    eax, ebx, SITE_size
    lea     rsi, [r12 + rax]
    cmp     [rsi + SITE.slot], ebx
    jne     .bad
    cmp     [rsi + SITE.rx], r14d
    jne     .bad
    cmp     [rsi + SITE.rz], r15d
    jne     .bad
    mov     eax, [rsi + SITE.kind]
    lea     ecx, [rax - 1]
    cmp     ecx, 3
    ja      .bad                        ; kinds 1..4
    cmp     eax, [rsp + 12]
    jb      .bad                        ; village, dungeons, crypt, camps in this order
    mov     [rsp + 12], eax
    cmp     eax, SITE_CAMP
    jae     .position
    inc     dword [rsp + rcx*4]
.position:
    mov     edi, r14d                   ; x within the region
    shl     edi, 9
    mov     eax, [rsi + SITE.x]
    sub     eax, edi
    cmp     eax, 511
    ja      .bad
    mov     edi, r15d
    shl     edi, 9
    mov     eax, [rsi + SITE.z]
    sub     eax, edi
    cmp     eax, 511
    ja      .bad
    mov     eax, [rsi + SITE.kind]      ; the trigger box = position + the plan's offsets
    dec     eax
    imul    eax, eax, 24
    lea     r8, [t_box]
    add     r8, rax
    mov     eax, [rsi + SITE.x]
    add     eax, [r8]
    cmp     eax, [rsi + SITE.lo_x]
    jne     .bad
    mov     eax, [rsi + SITE.y]
    add     eax, [r8 + 4]
    cmp     eax, [rsi + SITE.lo_y]
    jne     .bad
    mov     eax, [rsi + SITE.z]
    add     eax, [r8 + 8]
    cmp     eax, [rsi + SITE.lo_z]
    jne     .bad
    mov     eax, [rsi + SITE.x]
    add     eax, [r8 + 12]
    cmp     eax, [rsi + SITE.hi_x]
    jne     .bad
    mov     eax, [rsi + SITE.y]
    add     eax, [r8 + 16]
    cmp     eax, [rsi + SITE.hi_y]
    jne     .bad
    mov     eax, [rsi + SITE.z]
    add     eax, [r8 + 20]
    cmp     eax, [rsi + SITE.hi_z]
    jne     .bad
    mov     eax, [rsi + SITE.y]         ; y by kind
    mov     ecx, [rsi + SITE.kind]
    cmp     ecx, SITE_VILLAGE
    jne     .not_village
    cmp     eax, 98
    jl      .bad                        ; a village stands on ground at least 98 high
    jmp     .y_ok
.not_village:
    cmp     ecx, SITE_DUNGEON
    jne     .not_dungeon
    lea     edx, [rax - 20]
    cmp     edx, 60                     ; floor 20..80
    ja      .bad
    jmp     .y_ok
.not_dungeon:
    cmp     ecx, SITE_CRYPT
    jne     .camp
    lea     edx, [rax - 15]
    cmp     edx, 55                     ; floor 15..70
    ja      .bad
    jmp     .y_ok
.camp:
    cmp     dword [rsi + SITE.index], NUM_FACTIONS
    jae     .bad
    cmp     eax, 1
    jl      .bad
.y_ok:
    inc     ebx
    jmp     .site
.counts:
    cmp     dword [rsp], 1
    ja      .bad
    cmp     dword [rsp + 4], 2
    ja      .bad
    cmp     dword [rsp + 8], 1
    ja      .bad
    cmp     dword [rsp + 8], 0
    je      .ok
    test    r14d, 1                     ; a crypt only where arx and arz are even
    jnz     .bad
    test    r15d, 1
    jnz     .bad
.ok:
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; cmp_cache(rdi SITE* planned (absolute), rsi SITE* cached (local)) -> eax 0 when the cached record is
; the planned one with the world origin taken off its x and z fields (leaf)
cmp_cache:
    mov     eax, [world_origin_x]
    mov     edx, [world_origin_z]
    mov     r8d, [rdi + SITE.x]
    sub     r8d, eax
    cmp     r8d, [rsi + SITE.x]
    jne     .bad
    mov     r8d, [rdi + SITE.lo_x]
    sub     r8d, eax
    cmp     r8d, [rsi + SITE.lo_x]
    jne     .bad
    mov     r8d, [rdi + SITE.hi_x]
    sub     r8d, eax
    cmp     r8d, [rsi + SITE.hi_x]
    jne     .bad
    mov     r8d, [rdi + SITE.z]
    sub     r8d, edx
    cmp     r8d, [rsi + SITE.z]
    jne     .bad
    mov     r8d, [rdi + SITE.lo_z]
    sub     r8d, edx
    cmp     r8d, [rsi + SITE.lo_z]
    jne     .bad
    mov     r8d, [rdi + SITE.hi_z]
    sub     r8d, edx
    cmp     r8d, [rsi + SITE.hi_z]
    jne     .bad
    mov     eax, [rdi + SITE.kind]
    cmp     eax, [rsi + SITE.kind]
    jne     .bad
    mov     eax, [rdi + SITE.index]
    cmp     eax, [rsi + SITE.index]
    jne     .bad
    mov     eax, [rdi + SITE.y]
    cmp     eax, [rsi + SITE.y]
    jne     .bad
    mov     eax, [rdi + SITE.lo_y]
    cmp     eax, [rsi + SITE.lo_y]
    jne     .bad
    mov     eax, [rdi + SITE.hi_y]
    cmp     eax, [rsi + SITE.hi_y]
    jne     .bad
    mov     eax, [rdi + SITE.rx]
    cmp     eax, [rsi + SITE.rx]
    jne     .bad
    mov     eax, [rdi + SITE.rz]
    cmp     eax, [rsi + SITE.rz]
    jne     .bad
    mov     eax, [rdi + SITE.slot]
    cmp     eax, [rsi + SITE.slot]
    jne     .bad
    xor     eax, eax
    ret
.bad:
    mov     eax, 1
    ret

; check_cache(edi prx, esi prz) -> eax 0 when sites[] holds, in order, the plans of the 3 x 3
; regions around (prx, prz) (rows of constant arz first), in the local coordinates of the current
; world origin
; Frame: [rsp] k (sites checked), [rsp+4] arz, [rsp+8] arx.
check_cache:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     r12d, edi
    mov     r13d, esi
    mov     dword [rsp], 0
    lea     eax, [r13 - 1]
    mov     [rsp + 4], eax
.row:
    lea     eax, [r12 - 1]
    mov     [rsp + 8], eax
.col:
    mov     edi, [rsp + 8]
    mov     esi, [rsp + 4]
    lea     rdx, [plan_b]
    call    region_plan
    mov     ebx, eax
    lea     r14, [plan_b]
.rec:
    test    ebx, ebx
    jz      .next_col
    mov     eax, [rsp]
    cmp     eax, [site_count]
    jae     .bad
    imul    eax, eax, SITE_size
    lea     rsi, [sites]
    add     rsi, rax
    mov     rdi, r14
    call    cmp_cache
    test    eax, eax
    jnz     .bad
    inc     dword [rsp]
    add     r14, SITE_size
    dec     ebx
    jmp     .rec
.next_col:
    inc     dword [rsp + 8]
    lea     eax, [r12 + 1]
    cmp     [rsp + 8], eax
    jle     .col
    inc     dword [rsp + 4]
    lea     eax, [r13 + 1]
    cmp     [rsp + 4], eax
    jle     .row
    mov     eax, [rsp]
    cmp     eax, [site_count]
    jne     .bad
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; region_plan twice gives identical sites for 4 regions; each obeys the plan's rules; another seed
; plans other sites; sites[] (structures_refresh, after a rebase structures_shift) holds the 3 x 3
; regions around the player in local coordinates
; Frame: [rsp] saved player x, [rsp+4] z, [rsp+8] origin x, [rsp+12] origin z.
test_structure_sites_deterministic:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    call    world_clear
    mov     eax, [player + BODY.x]
    mov     [rsp], eax
    mov     eax, [player + BODY.z]
    mov     [rsp + 4], eax
    mov     eax, [world_origin_x]
    mov     [rsp + 8], eax
    mov     eax, [world_origin_z]
    mov     [rsp + 12], eax
    mov     edi, 42
    call    worldgen_set_seed
    xor     r12d, r12d                  ; region index 0..3
.region:
    lea     rax, [t_regions]
    mov     r13d, [rax + r12*8]         ; arx
    mov     r14d, [rax + r12*8 + 4]     ; arz
    mov     edi, r13d
    mov     esi, r14d
    lea     rdx, [plan_a]
    call    region_plan
    mov     ebx, eax
    mov     edi, r13d
    mov     esi, r14d
    lea     rdx, [plan_b]
    call    region_plan
    cmp     eax, ebx
    jne     .fail
    cmp     ebx, MAX_REGION_SITES
    ja      .fail
    imul    ecx, ebx, SITE_size
    lea     rsi, [plan_a]
    lea     rdi, [plan_b]
    test    ecx, ecx
    jz      .same
    repe cmpsb
    jne     .fail                       ; planning twice differs
.same:
    lea     rdi, [plan_a]
    mov     esi, ebx
    mov     edx, r13d
    mov     ecx, r14d
    call    check_plan
    test    eax, eax
    jnz     .fail
    lea     rax, [snap_na]
    mov     [rax + r12*4], ebx
    imul    eax, r12d, MAX_REGION_SITES * SITE_size
    lea     rdi, [snap_a]
    add     rdi, rax
    lea     rsi, [plan_a]
    mov     ecx, MAX_REGION_SITES * SITE_size
    rep movsb
    inc     r12d
    cmp     r12d, 4
    jb      .region
    mov     edi, 43                     ; the seed matters
    call    worldgen_set_seed
    xor     r12d, r12d
.region2:
    lea     rax, [t_regions]
    mov     edi, [rax + r12*8]
    mov     esi, [rax + r12*8 + 4]
    imul    ecx, r12d, MAX_REGION_SITES * SITE_size
    lea     rdx, [snap_b]
    add     rdx, rcx
    call    region_plan
    lea     rcx, [snap_nb]
    mov     [rcx + r12*4], eax
    inc     r12d
    cmp     r12d, 4
    jb      .region2
    lea     rsi, [snap_na]
    lea     rdi, [snap_nb]
    mov     ecx, 4
    repe cmpsd
    jne     .seed_differs               ; other counts: it differs
    xor     r12d, r12d                  ; same counts: some record must differ
.sum:
    lea     rax, [snap_na]
    mov     ecx, [rax + r12*4]
    imul    ecx, ecx, SITE_size
    imul    eax, r12d, MAX_REGION_SITES * SITE_size
    lea     rsi, [snap_a]
    add     rsi, rax
    lea     rdi, [snap_b]
    add     rdi, rax
    test    ecx, ecx
    jz      .sum_next
    repe cmpsb
    jne     .seed_differs
.sum_next:
    inc     r12d
    cmp     r12d, 4
    jb      .sum
    jmp     .fail                       ; both seeds planned the same sites
.seed_differs:
    ; ---- structures_refresh: the 3 x 3 regions around the player, local coordinates
    mov     edi, 42
    call    worldgen_set_seed
    mov     dword [world_origin_x], 512
    mov     dword [world_origin_z], -1024
    movss   xmm0, [k_m100_5]            ; local (-100.5, 300.5): absolute (411.5, -723.5): region (0, -2)
    movss   [player + BODY.x], xmm0
    movss   xmm0, [k_300_5]
    movss   [player + BODY.z], xmm0
    call    structures_refresh
    mov     edi, 0
    mov     esi, -2
    call    check_cache
    test    eax, eax
    jnz     .fail
    mov     dword [world_origin_x], 1024 ; a rebase by (512, 0): the same absolute place, local x - 512
    movss   xmm0, [k_m100_5]
    subss   xmm0, [k_512]
    movss   [player + BODY.x], xmm0
    mov     edi, 512
    xor     esi, esi
    call    structures_shift
    mov     edi, 0
    mov     esi, -2
    call    check_cache
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    mov     eax, [rsp]
    mov     [player + BODY.x], eax
    mov     eax, [rsp + 4]
    mov     [player + BODY.z], eax
    mov     eax, [rsp + 8]
    mov     [world_origin_x], eax
    mov     eax, [rsp + 12]
    mov     [world_origin_z], eax
    mov     dword [site_count], 0
    mov     eax, ebx
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- test 2: dungeon and crypt ------------------------------------------------------------------

; tunnel_expect(edi sx, esi sz, edx y0) -> eax the column i (1..60) where stair_tunnel's rule - dig
; while the terrain (gen_height) of the column is at or above the floor y0 + i + 1 - or of the next
; one west is, else exit - ends the tunnel, 0 when it digs all 60 columns
tunnel_expect:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, 1
.step:
    mov     edi, ebx
    sub     edi, r14d
    mov     esi, r12d
    call    gen_height
    lea     ecx, [r13 + r14 + 1]
    cmp     eax, ecx
    jge     .dig
    lea     edi, [rbx - 1]
    sub     edi, r14d
    mov     esi, r12d
    call    gen_height
    lea     ecx, [r13 + r14 + 1]
    cmp     eax, ecx
    jl      .exit
.dig:
    inc     r14d
    cmp     r14d, 60
    jbe     .step
    xor     eax, eax
    jmp     .ret
.exit:
    mov     eax, r14d
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; check_tunnel(rdi SITE*, esi back) -> eax 0 when the stair tunnel that leaves the site's west wall at
; x - back is what the rule says (tunnel_expect) and comes out - the planner accepts no other site:
; every dug column has its stair floor across the 3 wide passage (floor y0 + i, y0 = site y - 1) with
; 3 cells of air above, and the exit column carries the entrance frame (mossy brick lintel and
; pillars) with an open way through and out
; Frame: [rsp] sx, [rsp+4] sz, [rsp+8] y0, [rsp+12] exit column, [rsp+16] columns dug.
check_tunnel:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     rbx, rdi
    mov     eax, [rdi + SITE.x]
    sub     eax, esi
    mov     [rsp], eax
    mov     eax, [rdi + SITE.z]
    mov     [rsp + 4], eax
    mov     eax, [rdi + SITE.y]
    dec     eax
    mov     [rsp + 8], eax
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    mov     edx, [rsp + 8]
    call    tunnel_expect
    test    eax, eax
    jz      .bad                        ; a planned site's tunnel always comes out
    mov     [rsp + 12], eax
    dec     eax
    mov     [rsp + 16], eax             ; the columns dug before it
    mov     r12d, 1                     ; column i
.dug:
    cmp     r12d, [rsp + 16]
    ja      .frame
    mov     r13d, -1                    ; dz
.dz:
    mov     edi, [rsp]
    sub     edi, r12d
    mov     esi, [rsp + 8]
    add     esi, r12d
    mov     edx, [rsp + 4]
    add     edx, r13d
    call    tg_blk
    cmp     eax, STONE_BRICK_STAIRS + DIR_W
    jne     .bad
    mov     r14d, 1                     ; the passage above
.dy:
    mov     edi, [rsp]
    sub     edi, r12d
    mov     esi, [rsp + 8]
    add     esi, r12d
    add     esi, r14d
    mov     edx, [rsp + 4]
    add     edx, r13d
    call    tg_blk
    test    eax, eax
    jnz     .bad
    inc     r14d
    cmp     r14d, 3
    jbe     .dy
    inc     r13d
    cmp     r13d, 1
    jle     .dz
    inc     r12d
    jmp     .dug
.frame:
    mov     r12d, [rsp + 12]
    mov     r13d, -2                    ; the lintel: dy 4, dz -2..2
.lintel:
    mov     edi, [rsp]
    sub     edi, r12d
    mov     esi, [rsp + 8]
    add     esi, r12d
    add     esi, 4
    mov     edx, [rsp + 4]
    add     edx, r13d
    call    tg_blk
    cmp     eax, MOSSY_STONE_BRICK
    jne     .bad
    inc     r13d
    cmp     r13d, 2
    jle     .lintel
    mov     r14d, 1                     ; the pillars: dy 1..3, dz -2 and 2
.pillar:
    mov     edi, [rsp]
    sub     edi, r12d
    mov     esi, [rsp + 8]
    add     esi, r12d
    add     esi, r14d
    mov     edx, [rsp + 4]
    sub     edx, 2
    call    tg_blk
    cmp     eax, MOSSY_STONE_BRICK
    jne     .bad
    mov     edi, [rsp]
    sub     edi, r12d
    mov     esi, [rsp + 8]
    add     esi, r12d
    add     esi, r14d
    mov     edx, [rsp + 4]
    add     edx, 2
    call    tg_blk
    cmp     eax, MOSSY_STONE_BRICK
    jne     .bad
    inc     r14d
    cmp     r14d, 3
    jbe     .pillar
    mov     edi, [rsp]                  ; the way through the frame, and out beyond it at feet level
    sub     edi, r12d
    mov     esi, [rsp + 8]
    add     esi, r12d
    inc     esi
    mov     edx, [rsp + 4]
    call    tg_blk
    call    is_open
    test    eax, eax
    jz      .bad
    mov     edi, [rsp]
    sub     edi, r12d
    dec     edi
    mov     esi, [rsp + 8]
    add     esi, r12d
    add     esi, 1
    mov     edx, [rsp + 4]
    call    tg_blk
    call    is_open
    test    eax, eax
    jz      .bad
.ok:
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; count_chests(rdi SITE*, esi back, edx fwd, ecx table) -> eax the GENCHESTs of that table the
; generator recorded within x - back .. x + fwd, z - back .. z + fwd of the site, at its floor y
; Frame: [rsp] x lo, [rsp+4] z lo, [rsp+8] x hi, [rsp+12] z hi, [rsp+16] floor, [rsp+20] table.
count_chests:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     eax, [rdi + SITE.x]
    sub     eax, esi
    mov     [rsp], eax
    mov     eax, [rdi + SITE.z]
    sub     eax, esi
    mov     [rsp + 4], eax
    mov     eax, [rdi + SITE.x]
    add     eax, edx
    mov     [rsp + 8], eax
    mov     eax, [rdi + SITE.z]
    add     eax, edx
    mov     [rsp + 12], eax
    mov     eax, [rdi + SITE.y]
    mov     [rsp + 16], eax
    mov     [rsp + 20], ecx
    xor     r15d, r15d                  ; chests counted
    mov     r12d, [rsp + 4]
    sar     r12d, 4                     ; acz
.cz:
    mov     r13d, [rsp]
    sar     r13d, 4                     ; acx
.cx:
    mov     edi, r13d
    mov     esi, r12d
    call    tg_buf
    test    rax, rax
    jz      .next
    mov     ecx, [rax + GENBUF.nchests]
    lea     rdx, [rax + GENBUF.chests]
.chest:
    test    ecx, ecx
    jz      .next
    mov     eax, [rdx + GENCHEST.table]
    cmp     eax, [rsp + 20]
    jne     .cnext
    mov     eax, [rdx + GENCHEST.y]
    cmp     eax, [rsp + 16]
    jne     .cnext
    mov     eax, [rdx + GENCHEST.x]
    cmp     eax, [rsp]
    jl      .cnext
    cmp     eax, [rsp + 8]
    jg      .cnext
    mov     eax, [rdx + GENCHEST.z]
    cmp     eax, [rsp + 4]
    jl      .cnext
    cmp     eax, [rsp + 12]
    jg      .cnext
    inc     r15d
.cnext:
    add     rdx, GENCHEST_size
    dec     ecx
    jmp     .chest
.next:
    inc     r13d
    mov     eax, [rsp + 8]
    sar     eax, 4
    cmp     r13d, eax
    jle     .cx
    inc     r12d
    mov     eax, [rsp + 12]
    sar     eax, 4
    cmp     r12d, eax
    jle     .cz
    mov     eax, r15d
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; chest_at(rdi SITE*, esi dx, edx dz, ecx gears, r8d tier, r9d min_rar) -> eax 0 when the generator put a
; CHEST block and a GENCHEST (of the table the tier says) at (site x + dx, floor, site z + dz) and the
; loot rolled for it is chest_ok
; Frame: [rsp] x, [rsp+4] y, [rsp+8] z, [rsp+12] gears, [rsp+16] tier, [rsp+20] min_rar.
chest_at:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 24
    mov     rbx, rdi
    mov     eax, [rdi + SITE.x]
    add     eax, esi
    mov     [rsp], eax
    mov     eax, [rdi + SITE.y]
    mov     [rsp + 4], eax
    mov     eax, [rdi + SITE.z]
    add     eax, edx
    mov     [rsp + 8], eax
    mov     [rsp + 12], ecx
    mov     [rsp + 16], r8d
    mov     [rsp + 20], r9d
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    mov     edx, [rsp + 8]
    call    tg_blk
    cmp     eax, CHEST
    jne     .bad
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    mov     edx, [rsp + 8]
    call    tg_chest
    test    rax, rax
    jz      .bad
    mov     rdi, rax
    mov     esi, [rsp + 12]
    mov     edx, [rsp + 16]
    mov     ecx, [rsp + 20]
    call    chest_ok
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    add     rsp, 24
    pop     rbx
    pop     rbp
    ret

; check_room(rdi SITE*, esi cx, edx cz, ecx half, r8d ytop, r9d pillars) -> eax 0 when the room built
; around (site x + cx, site z + cz) is what its boxes say, cell by cell over x, z within `half` and y
; from the floor - 1 to the floor + ytop: the shell (the outer faces) is brick but for an opening of
; air (at most 18 cells, 9 for the hall), the inside is air, a chest or a wall torch (and, with
; `pillars`, a brick pillar)
; Frame: [rsp] cx, [rsp+4] cz, [rsp+8] half, [rsp+12] ytop, [rsp+16] pillars, [rsp+20] opening cells.
check_room:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     rbx, rdi
    mov     [rsp], esi
    mov     [rsp + 4], edx
    mov     [rsp + 8], ecx
    mov     [rsp + 12], r8d
    mov     [rsp + 16], r9d
    mov     dword [rsp + 20], 0
    mov     r12d, -1                    ; dy
.dy:
    mov     r13d, [rsp + 8]             ; dz
    neg     r13d
.dz:
    mov     r14d, [rsp + 8]             ; dx
    neg     r14d
.dx:
    xor     r15d, r15d                  ; 1 on the shell
    cmp     r12d, -1
    je      .shell
    cmp     r12d, [rsp + 12]
    je      .shell
    mov     eax, r14d
    cdq
    xor     eax, edx
    sub     eax, edx
    cmp     eax, [rsp + 8]
    je      .shell
    mov     eax, r13d
    cdq
    xor     eax, edx
    sub     eax, edx
    cmp     eax, [rsp + 8]
    jne     .fetch
.shell:
    mov     r15d, 1
.fetch:
    mov     rdi, rbx
    mov     esi, [rsp]
    add     esi, r14d
    mov     edx, r12d
    mov     ecx, [rsp + 4]
    add     ecx, r13d
    call    block_at
    test    r15d, r15d
    jz      .inside
    test    eax, eax
    jz      .opening
    cmp     eax, STONE_BRICK
    je      .next
    cmp     eax, MOSSY_STONE_BRICK
    je      .next
    jmp     .bad
.opening:
    inc     dword [rsp + 20]
    jmp     .next
.inside:
    test    eax, eax
    jz      .next
    cmp     eax, CHEST
    je      .next
    lea     ecx, [rax - TORCH_WALL]
    cmp     ecx, 3
    jbe     .next
    cmp     dword [rsp + 16], 0
    je      .bad
    cmp     eax, STONE_BRICK
    jne     .bad
.next:
    inc     r14d
    mov     eax, [rsp + 8]
    cmp     r14d, eax
    jle     .dx
    inc     r13d
    cmp     r13d, eax
    jle     .dz
    inc     r12d
    mov     eax, [rsp + 12]
    cmp     r12d, eax
    jle     .dy
    mov     eax, 18
    cmp     dword [rsp + 16], 0
    je      .limit
    mov     eax, 9
.limit:
    cmp     [rsp + 20], eax
    ja      .bad
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; check_village_area(rdi SITE*) -> eax 0 when the village's 31 x 31 area is flattened: at its ground
; level every cell is grass, gravel, cobble or glass, one below is solid, and along the edge ring the
; air starts right above (3 cells)
check_village_area:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12d, -15                   ; dz
.dz:
    mov     r13d, -15                   ; dx
.dx:
    mov     rdi, rbx
    mov     esi, r13d
    xor     edx, edx
    mov     ecx, r12d
    call    block_at
    cmp     eax, GRASS
    je      .ground_ok
    cmp     eax, GRAVEL
    je      .ground_ok
    cmp     eax, COBBLE
    je      .ground_ok
    cmp     eax, GLASS
    jne     .bad
.ground_ok:
    mov     rdi, rbx
    mov     esi, r13d
    mov     edx, -1
    mov     ecx, r12d
    call    block_at
    test    eax, eax
    jz      .bad
    mov     eax, r13d                   ; the edge ring: |dx| or |dz| is 15
    cdq
    xor     eax, edx
    sub     eax, edx
    cmp     eax, 15
    je      .ring
    mov     eax, r12d
    cdq
    xor     eax, edx
    sub     eax, edx
    cmp     eax, 15
    jne     .next
.ring:
    mov     r14d, 1
.air:
    mov     rdi, rbx
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, r12d
    call    block_at
    test    eax, eax
    jnz     .bad
    inc     r14d
    cmp     r14d, 3
    jbe     .air
.next:
    inc     r13d
    cmp     r13d, 15
    jle     .dx
    inc     r12d
    cmp     r12d, 15
    jle     .dz
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; the first dungeon the plans have, built through gen_column: open rooms and corridors, the west
; opening, torches, a brick west wall, exactly 4 generated chests (each loaded with loot and one
; piece of gear of tier max(2, tier of the player's level)) and a stair tunnel that comes out of
; the ground where the terrain says; the first crypt: an open hall, its torches and pillar, a tunnel,
; two chests with two pieces of tier 13 each
; Frame: [rsp .. +56) the site.
test_dungeon_built_with_chests:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 72
    call    world_clear
    call    rpg_reset
    mov     edi, 42
    call    worldgen_set_seed
    mov     edi, SITE_DUNGEON
    lea     rsi, [rsp]
    call    pick_site
    test    eax, eax
    jz      .fail
    lea     rbx, [rsp]
    mov     edi, [rbx + SITE.x]
    sub     edi, 66
    sar     edi, 4
    mov     esi, [rbx + SITE.z]
    sub     esi, 6
    sar     esi, 4
    call    tg_reset
    EXPECT_AIR 0, 1, 0                  ; the middle of the first room, 1 above the floor
    EXPECT_AIR 14, 1, 0                 ; the second room
    EXPECT_AIR 14, 1, 14                ; the third
    EXPECT_AIR 7, 1, 0                  ; the corridor between the first two
    EXPECT_AIR 14, 1, 7                 ; and the one between the last two
    EXPECT_AIR -5, 2, 1                 ; the opening in the west wall
    EXPECT_ID 0, 2, -4, TORCH_WALL + DIR_N      ; the torches of the rooms
    EXPECT_ID 14, 2, -4, TORCH_WALL + DIR_N
    EXPECT_ID 14, 2, 18, TORCH_WALL + DIR_S
    mov     rdi, rbx                    ; the west wall beside the opening is brick
    mov     esi, -5
    mov     edx, 1
    mov     ecx, 3
    call    block_at
    cmp     eax, STONE_BRICK
    je      .wall_ok
    cmp     eax, MOSSY_STONE_BRICK
    jne     .fail
.wall_ok:
    mov     rdi, rbx                    ; exactly 4 generated chests in the three rooms, each at its place
    mov     esi, 5
    mov     edx, 19
    xor     ecx, ecx
    call    count_chests
    cmp     eax, 4
    jne     .fail
    mov     rdi, rbx
    mov     esi, 3
    mov     edx, 3
    mov     ecx, 1
    mov     r8d, 2
    xor     r9d, r9d                    ; a dungeon's table may roll common
    call    chest_at
    test    eax, eax
    jnz     .fail
    mov     rdi, rbx
    mov     esi, 17
    mov     edx, -3
    mov     ecx, 1
    mov     r8d, 2
    xor     r9d, r9d
    call    chest_at
    test    eax, eax
    jnz     .fail
    mov     rdi, rbx
    mov     esi, 11
    mov     edx, 17
    mov     ecx, 1
    mov     r8d, 2
    xor     r9d, r9d
    call    chest_at
    test    eax, eax
    jnz     .fail
    mov     rdi, rbx
    mov     esi, 17
    mov     edx, 17
    mov     ecx, 1
    mov     r8d, 2
    xor     r9d, r9d
    call    chest_at
    test    eax, eax
    jnz     .fail
    mov     byte [rpg_state + RPGSAVE.level], 10    ; a level 10 player's dungeon chest holds tier 3
    mov     rdi, rbx
    mov     esi, 3
    mov     edx, 3
    mov     ecx, 1
    mov     r8d, 3
    xor     r9d, r9d
    call    chest_at
    test    eax, eax
    jnz     .fail
    call    rpg_reset
    mov     rdi, rbx                    ; the stair tunnel from the west wall
    mov     esi, 5
    call    check_tunnel
    test    eax, eax
    jnz     .fail
    xor     r12d, r12d                  ; the three rooms, cell by cell: (0, 0), (14, 0), (14, 14)
.rooms:
    mov     rdi, rbx
    lea     rax, [room_cx]
    mov     esi, [rax + r12*8]
    mov     edx, [rax + r12*8 + 4]
    mov     ecx, 5
    mov     r8d, 5
    xor     r9d, r9d
    call    check_room
    test    eax, eax
    jnz     .fail
    inc     r12d
    cmp     r12d, 3
    jb      .rooms
    mov     edi, [rbx + SITE.x]         ; the plan cache: far columns evict every plan around the
    sar     edi, 4                      ; dungeon, then its column comes out byte for byte the same
    mov     r12d, edi
    mov     esi, [rbx + SITE.z]
    sar     esi, 4
    mov     r13d, esi
    call    tg_buf
    mov     r14, rax
    mov     r15d, 10
.sweep:
    lea     rdi, [tg_spare]
    mov     eax, r15d
    shl     eax, 5
    add     eax, 3
    mov     [rdi + GENBUF.cx], eax
    mov     [rdi + GENBUF.cz], eax
    call    gen_column
    add     r15d, 3
    cmp     r15d, 17
    jb      .sweep
    lea     rdi, [tg_spare]
    mov     [rdi + GENBUF.cx], r12d
    mov     [rdi + GENBUF.cz], r13d
    call    gen_column
    lea     rsi, [tg_spare + GENBUF.blocks]
    lea     rdi, [r14 + GENBUF.blocks]
    mov     ecx, 65536 / 8
    repe cmpsq
    jne     .fail
    mov     eax, [r14 + GENBUF.nchests]
    cmp     eax, [tg_spare + GENBUF.nchests]
    jne     .fail
    lea     rsi, [tg_spare + GENBUF.chests]
    lea     rdi, [r14 + GENBUF.chests]
    mov     ecx, MAX_GEN_CHESTS * GENCHEST_size / 8
    repe cmpsq
    jne     .fail
    ; ---- the crypt
    mov     edi, SITE_CRYPT
    lea     rsi, [rsp]
    call    pick_site
    test    eax, eax
    jz      .fail
    mov     edi, [rbx + SITE.x]
    sub     edi, 69
    sar     edi, 4
    mov     esi, [rbx + SITE.z]
    sub     esi, 9
    sar     esi, 4
    call    tg_reset
    EXPECT_AIR 0, 1, 0                  ; the hall
    EXPECT_AIR -8, 1, 0                 ; and its west opening
    EXPECT_ID 3, 3, -4, TORCH_WALL + DIR_E      ; its torches, on the pillars
    EXPECT_ID 3, 3, 4, TORCH_WALL + DIR_E
    EXPECT_ID -3, 3, -4, TORCH_WALL + DIR_W
    EXPECT_ID -3, 3, 4, TORCH_WALL + DIR_W
    mov     rdi, rbx                    ; a pillar
    mov     esi, 4
    mov     edx, 2
    mov     ecx, 4
    call    block_at
    cmp     eax, STONE_BRICK
    jne     .fail
    mov     rdi, rbx                    ; exactly 2 chests, each with two pieces of tier 13
    mov     esi, 8
    mov     edx, 8
    mov     ecx, 1
    call    count_chests
    cmp     eax, 2
    jne     .fail
    mov     rdi, rbx
    mov     esi, 6
    mov     edx, -6
    mov     ecx, 2
    mov     r8d, 13
    mov     r9d, RAR_MAGIC              ; the boss table never rolls common
    call    chest_at
    test    eax, eax
    jnz     .fail
    mov     rdi, rbx
    mov     esi, 6
    mov     edx, 6
    mov     ecx, 2
    mov     r8d, 13
    mov     r9d, RAR_MAGIC
    call    chest_at
    test    eax, eax
    jnz     .fail
    mov     rdi, rbx
    mov     esi, 8
    call    check_tunnel
    test    eax, eax
    jnz     .fail
    mov     rdi, rbx                    ; the hall, cell by cell
    xor     esi, esi
    xor     edx, edx
    mov     ecx, 8
    mov     r8d, 8
    mov     r9d, 1
    call    check_room
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    rpg_reset
    call    world_clear
    mov     eax, ebx
    add     rsp, 72
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- test 3: the village ---------------------------------------------------------------------------

; count_role(edi role) -> eax the live MOB_FOLK mobs with that role (leaf)
count_role:
    xor     eax, eax
    lea     rcx, [mobs]
    mov     edx, MAX_MOBS
.mob:
    cmp     dword [rcx + MOB.type], MOB_FOLK
    jne     .next
    movzx   r8d, byte [rcx + MOB.role]
    cmp     r8d, edi
    jne     .next
    inc     eax
.next:
    add     rcx, MOB_size
    dec     edx
    jnz     .mob
    ret

; the first village the plans have, built through gen_column: the well's glass at its middle, the
; first house with its cobble floor, plank roof, closed wooden door (west wall, facing the well), wall
; torch inside and plank wall opposite the door, gravel paths where the merchant and the elder stand.
; Then a village in sites[] (any mode): its merchant and elder appear at their homes when its column
; is loaded, once, and again a check later when removed; none while the player is 96 or more blocks away
; Frame: [rsp .. +56) the site, [rsp+56] saved game_mode.
test_village_built_with_npcs:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 72
    mov     eax, [game_mode]
    mov     [rsp + 56], eax
    call    world_clear
    call    mobs_clear
    call    structures_reset
    mov     edi, 42
    call    worldgen_set_seed
    mov     edi, SITE_VILLAGE
    lea     rsi, [rsp]
    call    pick_site
    test    eax, eax
    jz      .fail
    lea     rbx, [rsp]
    mov     edi, [rbx + SITE.x]
    sub     edi, 16
    sar     edi, 4
    mov     esi, [rbx + SITE.z]
    sub     esi, 16
    sar     esi, 4
    call    tg_reset
    EXPECT_ID 0, 0, 0, GLASS            ; the well
    EXPECT_ID 9, 0, 0, COBBLE           ; house 0 stands 9 east: floor, roof, door, wall
    EXPECT_ID 9, 4, 0, PLANKS
    EXPECT_ID 7, 1, 0, WOOD_DOOR + DIR_W * 4    ; the door: closed, facing west, both halves
    EXPECT_ID 7, 2, 0, WOOD_DOOR + DIR_W * 4 + 1
    EXPECT_ID 10, 2, 1, TORCH_WALL + DIR_E      ; the wall torch inside, leaning on the east wall
    EXPECT_ID 11, 1, 0, PLANKS
    EXPECT_ID 6, 0, 0, GRAVEL           ; the merchant's cell and the elder's stand on the paths
    EXPECT_ID -6, 0, 0, GRAVEL
    mov     rdi, rbx                    ; the whole 31 x 31 area is flattened
    call    check_village_area
    test    eax, eax
    jnz     .fail
    ; ---- the NPCs
    lea     rdi, [sites]
    mov     esi, SITE_VILLAGE
    mov     edx, 100
    mov     ecx, 60
    mov     r8d, 100
    xor     r9d, r9d
    call    fab_site
    mov     dword [site_count], 1
    mov     dword [game_mode], MODE_CREATIVE    ; villagers do not depend on the mode
    movss   xmm0, [k_100_5]
    movss   [player + BODY.x], xmm0
    movss   [player + BODY.z], xmm0
    movss   xmm0, [k_41]
    movss   [player + BODY.y], xmm0
    call    structures_step
    mov     edi, ROLE_TRADER
    call    count_role
    cmp     eax, 1
    jne     .fail
    mov     edi, ROLE_LEADER
    call    count_role
    cmp     eax, 1
    jne     .fail
    lea     rax, [mobs]                 ; their homes: (x + 6.5, z + 0.5) and (x - 5.5, z + 0.5)
    mov     ecx, MAX_MOBS
.homes:
    cmp     dword [rax + MOB.type], MOB_FOLK
    jne     .home_next
    cmp     byte [rax + MOB.role], ROLE_TRADER
    jne     .elder
    movss   xmm0, [rax + MOB.home_x]
    comiss  xmm0, [k_106_5]
    jne     .fail
    jp      .fail
    jmp     .home_z
.elder:
    cmp     byte [rax + MOB.role], ROLE_LEADER
    jne     .home_next
    movss   xmm0, [rax + MOB.home_x]
    comiss  xmm0, [k_94_5]
    jne     .fail
    jp      .fail
.home_z:
    movss   xmm0, [rax + MOB.home_z]
    comiss  xmm0, [k_100_5]
    jne     .fail
    jp      .fail
    movss   xmm0, [rax + BODY.y]        ; feet on the village's ground + 1
    comiss  xmm0, [k_61]
    jne     .fail
    jp      .fail
.home_next:
    add     rax, MOB_size
    dec     ecx
    jnz     .homes
    mov     r12d, 60                    ; the next check, 60 steps on, finds them: no duplicates
.dup:
    call    structures_step
    dec     r12d
    jnz     .dup
    mov     edi, ROLE_TRADER
    call    count_role
    cmp     eax, 1
    jne     .fail
    mov     edi, ROLE_LEADER
    call    count_role
    cmp     eax, 1
    jne     .fail
    call    mobs_clear                  ; removed: the next check is due 60 steps after the last
    mov     r12d, 59
.wait:
    call    structures_step
    dec     r12d
    jnz     .wait
    mov     edi, ROLE_TRADER
    call    count_role
    test    eax, eax
    jnz     .fail
    call    structures_step             ; the 60th: they are back
    mov     edi, ROLE_TRADER
    call    count_role
    cmp     eax, 1
    jne     .fail
    mov     edi, ROLE_LEADER
    call    count_role
    cmp     eax, 1
    jne     .fail
    call    mobs_clear                  ; the player far away: nobody is created
    movss   xmm0, [k_270_5]
    movss   [player + BODY.x], xmm0
    movss   [player + BODY.z], xmm0
    mov     r12d, 61
.far:
    call    structures_step
    dec     r12d
    jnz     .far
    mov     edi, ROLE_TRADER
    call    count_role
    test    eax, eax
    jnz     .fail
    mov     edi, ROLE_LEADER
    call    count_role
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    mobs_clear
    call    structures_reset
    call    world_clear
    mov     eax, [rsp + 56]
    mov     [game_mode], eax
    mov     eax, ebx
    add     rsp, 72
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- test 4: the dungeon counter ---------------------------------------------------------------

; total_xp() -> eax experience earned: xp into the level plus the cost of every level below it
total_xp:
    push    rbx
    push    r12
    push    r13
    movzx   r12d, byte [rpg_state + RPGSAVE.level]
    mov     ebx, [rpg_state + RPGSAVE.xp]
    mov     r13d, 1
.l:
    cmp     r13d, r12d
    jae     .done
    mov     edi, r13d
    call    rpg_xp_need
    add     ebx, eax
    inc     r13d
    jmp     .l
.done:
    mov     eax, ebx
    pop     r13
    pop     r12
    pop     rbx
    ret

; eight deaths of a dungeon's mobs clear it: the 8th (not the 7th, not origin 0, an unknown origin or
; the origin of a village record) sets SS_CLEARED in its site state and awards 150 XP + 15 per level
; (165 at level 1) once; another dungeon's clear at level 10 pays 300 and its record is separate;
; structures_nearest skips a cleared dungeon when asked to
; Frame: [rsp] record 0, [rsp+8] record 1, [rsp+16] record 2 (a village).
test_dungeon_clears_after_kills:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40
    call    world_clear
    call    zero_sites
    call    structures_reset
    call    rpg_reset
    mov     byte [rpg_state + RPGSAVE.class], CLASS_WARRIOR
    lea     rdi, [fsite]                ; dungeon slot 1 and 2 of region (0, 0), a village slot 0
    mov     esi, SITE_DUNGEON
    mov     edx, 30
    mov     ecx, 40
    mov     r8d, 30
    mov     r9d, 1
    call    fab_site
    lea     rdi, [fsite + SITE_size]
    mov     esi, SITE_DUNGEON
    mov     edx, 200
    mov     ecx, 40
    mov     r8d, 200
    mov     r9d, 2
    call    fab_site
    lea     rdi, [fsite + 2 * SITE_size]
    mov     esi, SITE_VILLAGE
    mov     edx, 100
    mov     ecx, 60
    mov     r8d, 100
    xor     r9d, r9d
    call    fab_site
    lea     rdi, [fsite]
    call    site_state
    test    rax, rax
    jz      .fail
    mov     [rsp], rax
    lea     rdi, [fsite + SITE_size]
    call    site_state
    test    rax, rax
    jz      .fail
    mov     [rsp + 8], rax
    lea     rdi, [fsite + 2 * SITE_size]
    call    site_state
    test    rax, rax
    jz      .fail
    mov     [rsp + 16], rax
    lea     rdi, [fsite]                ; the same site again is the same record
    call    site_state
    cmp     rax, [rsp]
    jne     .fail
    cmp     dword [world_header + WORLDHDR.site_count], 3
    jne     .fail
    mov     rax, [rsp]
    cmp     byte [rax + SITESTATE.kind], SITE_DUNGEON
    jne     .fail
    cmp     byte [rax + SITESTATE.slot], 1
    jne     .fail
    mov     rdi, [rsp]
    call    origin_of
    mov     r13d, eax                   ; the origin of dungeon 1's mobs
    mov     rdi, [rsp + 8]
    call    origin_of
    mov     r14d, eax                   ; ... of the second dungeon
    mov     rdi, [rsp + 16]
    call    origin_of
    mov     r15d, eax                   ; ... a village's record
    cmp     r13d, 1
    jne     .fail
    cmp     r14d, 2
    jne     .fail
    mov     ebx, 7
.seven:
    mov     edi, r13d
    call    structures_on_mob_killed
    dec     ebx
    jnz     .seven
    mov     rax, [rsp]
    test    byte [rax + SITESTATE.flags], SS_CLEARED
    jnz     .fail
    cmp     byte [rax + SITESTATE.kills], 7
    jne     .fail
    cmp     dword [rpg_state + RPGSAVE.xp], 0
    jne     .fail
    cmp     byte [rpg_state + RPGSAVE.level], 1
    jne     .fail
    xor     edi, edi                    ; not a dungeon's mobs: no count
    call    structures_on_mob_killed
    mov     edi, 99
    call    structures_on_mob_killed
    mov     edi, 1000
    call    structures_on_mob_killed
    mov     edi, r15d
    call    structures_on_mob_killed
    mov     rax, [rsp]
    test    byte [rax + SITESTATE.flags], SS_CLEARED
    jnz     .fail
    mov     rax, [rsp + 16]
    cmp     byte [rax + SITESTATE.kills], 0
    jne     .fail
    mov     edi, r13d
    call    structures_on_mob_killed
    mov     rax, [rsp]
    test    byte [rax + SITESTATE.flags], SS_CLEARED
    jz      .fail
    mov     rax, [rsp + 8]
    test    byte [rax + SITESTATE.flags], SS_CLEARED
    jnz     .fail                       ; the other dungeon is untouched
    call    total_xp
    cmp     eax, 165
    jne     .fail
    mov     edi, r13d                   ; a 9th death changes nothing
    call    structures_on_mob_killed
    call    total_xp
    cmp     eax, 165
    jne     .fail
    ; structures_nearest: the player stands by dungeon 1; once it is cleared the other one is the
    ; nearest "uncleared" dungeon, a village is never skipped
    lea     rsi, [fsite]
    lea     rdi, [sites]
    mov     ecx, 3 * SITE_size / 8
    rep movsq
    mov     dword [site_count], 3
    movss   xmm0, [k_20]
    movss   [player + BODY.x], xmm0
    movss   [player + BODY.z], xmm0
    mov     edi, SITE_DUNGEON
    xor     esi, esi
    call    structures_nearest
    lea     rcx, [sites]
    cmp     rax, rcx
    jne     .fail
    mov     edi, SITE_DUNGEON
    mov     esi, 1
    call    structures_nearest
    lea     rcx, [sites + SITE_size]
    cmp     rax, rcx
    jne     .fail
    mov     edi, SITE_VILLAGE
    mov     esi, 1
    call    structures_nearest
    lea     rcx, [sites + 2 * SITE_size]
    cmp     rax, rcx
    jne     .fail
    mov     edi, SITE_CRYPT
    xor     esi, esi
    call    structures_nearest
    test    rax, rax
    jnz     .fail
    mov     byte [rpg_state + RPGSAVE.level], 10
    mov     dword [rpg_state + RPGSAVE.xp], 0
    call    total_xp
    mov     r12d, eax
    mov     ebx, 8
.eight:
    mov     edi, r14d                   ; the second dungeon's mobs
    call    structures_on_mob_killed
    dec     ebx
    jnz     .eight
    mov     rax, [rsp + 8]
    test    byte [rax + SITESTATE.flags], SS_CLEARED
    jz      .fail
    call    total_xp
    sub     eax, r12d
    cmp     eax, 300
    jne     .fail
    mov     edi, SITE_DUNGEON
    mov     esi, 1
    call    structures_nearest
    test    rax, rax
    jnz     .fail                       ; both are cleared
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    rpg_reset
    call    combat_reset
    call    survival_reset
    call    fx_clear
    call    structures_reset
    call    zero_sites
    call    mobs_clear
    mov     eax, ebx
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- test 5: the crypt's boss and the dungeon spawner ----------------------------------------------

; the crypt's boss: nothing wakes while the player is outside, in Creative or on Peaceful; inside in
; Survival one step spawns a single boss (origin = its site record's index + 1, level 20 for a level 1
; player), more steps add none, and once the boss is reported defeated none comes back (a dungeon's or
; an unknown origin does not count as the crypt's). Then a step inside the dungeon spawns one of its
; elites (origin = its record's index + 1) at the player's level + 2.
; Frame: [rsp] saved player body, [rsp+72] game_mode, [rsp+76] difficulty, [rsp+80] crypt record,
; [rsp+88] dungeon record, [rsp+96] crypt origin.
test_crypt_spawns_boss_once:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 104
    lea     rsi, [player]
    lea     rdi, [rsp]
    mov     ecx, BODY_size
    rep movsb
    mov     eax, [game_mode]
    mov     [rsp + 72], eax
    mov     eax, [settings + SETTINGS.difficulty]
    mov     [rsp + 76], eax
    call    world_clear
    call    mobs_clear
    call    zero_sites
    call    structures_reset
    call    rpg_reset
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    lea     rdi, [sites]                ; a crypt (floor 40) and a dungeon (floor 40) in the cache
    mov     esi, SITE_CRYPT
    mov     edx, 100
    mov     ecx, 40
    mov     r8d, 100
    xor     r9d, r9d
    call    fab_site
    lea     rdi, [sites + SITE_size]
    mov     esi, SITE_DUNGEON
    mov     edx, 30
    mov     ecx, 40
    mov     r8d, 30
    mov     r9d, 1
    call    fab_site
    mov     dword [site_count], 2
    lea     rbx, [sites]
    movss   xmm0, [k_half]              ; far from both
    movss   [player + BODY.x], xmm0
    movss   [player + BODY.z], xmm0
    movss   xmm0, [k_10]
    movss   [player + BODY.y], xmm0
    call    structures_step
    mov     edi, MOB_BOSS
    call    mob_count_type
    test    eax, eax
    jnz     .fail
    cmp     dword [world_header + WORLDHDR.site_count], 0
    jne     .fail                       ; no record for a site the player never entered
    cvtsi2ss xmm0, dword [rbx + SITE.x] ; inside: 3.5 east of the middle, 1 above the floor
    addss   xmm0, [k_3_5]
    movss   [player + BODY.x], xmm0
    cvtsi2ss xmm0, dword [rbx + SITE.y]
    addss   xmm0, [k_one]
    movss   [player + BODY.y], xmm0
    cvtsi2ss xmm0, dword [rbx + SITE.z]
    addss   xmm0, [k_half]
    movss   [player + BODY.z], xmm0
    mov     dword [game_mode], MODE_CREATIVE
    call    structures_step
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL
    call    structures_step
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    mov     edi, MOB_BOSS
    call    mob_count_type
    test    eax, eax
    jnz     .fail
    call    structures_step             ; the real thing
    mov     edi, MOB_BOSS
    call    mob_count_type
    cmp     eax, 1
    jne     .fail
    mov     rdi, rbx
    call    site_state                  ; its record exists now
    test    rax, rax
    jz      .fail
    mov     [rsp + 80], rax
    cmp     byte [rax + SITESTATE.kind], SITE_CRYPT
    jne     .fail
    mov     rdi, rax
    call    origin_of
    mov     [rsp + 96], eax
    lea     rax, [mobs]                 ; its slot carries the crypt's origin
    mov     ecx, MAX_MOBS
.find:
    cmp     dword [rax + MOB.type], MOB_BOSS
    je      .have
    add     rax, MOB_size
    dec     ecx
    jnz     .find
    jmp     .fail
.have:
    mov     edx, [rsp + 96]
    cmp     [rax + MOB.origin], edx
    jne     .fail
    cmp     dword [rax + MOB.level], 20
    jne     .fail
    call    structures_step             ; once only
    mov     edi, MOB_BOSS
    call    mob_count_type
    cmp     eax, 1
    jne     .fail
    call    mobs_clear                  ; his origin is the only one that counts as the crypt's
    xor     edi, edi
    call    structures_on_boss_killed
    mov     edi, 1000
    call    structures_on_boss_killed
    mov     rax, [rsp + 80]
    test    byte [rax + SITESTATE.flags], SS_CLEARED
    jnz     .fail
    mov     edi, [rsp + 96]
    call    structures_on_boss_killed   ; defeated: he stays dead
    mov     rax, [rsp + 80]
    test    byte [rax + SITESTATE.flags], SS_CLEARED
    jz      .fail
    call    structures_step
    mov     edi, MOB_BOSS
    call    mob_count_type
    test    eax, eax
    jnz     .fail
    call    mobs_clear                  ; a dungeon's spawner, with the player in the dungeon's far
    call    structures_reset            ; south-west corner, 6 or more blocks from every room's middle
    mov     dword [site_count], 2
    lea     rbx, [sites + SITE_size]
    mov     byte [rpg_state + RPGSAVE.level], 4
    cvtsi2ss xmm0, dword [rbx + SITE.x]
    subss   xmm0, [k_6]
    movss   [player + BODY.x], xmm0
    cvtsi2ss xmm0, dword [rbx + SITE.y]
    addss   xmm0, [k_one]
    movss   [player + BODY.y], xmm0
    cvtsi2ss xmm0, dword [rbx + SITE.z]
    addss   xmm0, [k_20]
    movss   [player + BODY.z], xmm0
    mov     rdi, rbx
    call    structures_step
    call    first_mob
    test    rax, rax
    jz      .fail
    mov     r12, rax
    mov     rdi, rbx
    call    site_state
    test    rax, rax
    jz      .fail
    mov     [rsp + 88], rax
    cmp     byte [rax + SITESTATE.kind], SITE_DUNGEON
    jne     .fail
    mov     rdi, rax
    call    origin_of
    cmp     [r12 + MOB.origin], eax
    jne     .fail
    cmp     eax, [rsp + 96]
    je      .fail                       ; not the crypt's record
    cmp     dword [r12 + MOB.elite], 1
    jne     .fail
    cmp     dword [r12 + MOB.level], 6
    jne     .fail
    mov     edi, eax                    ; a dungeon's origin is no boss kill
    call    structures_on_boss_killed
    mov     rax, [rsp + 88]
    test    byte [rax + SITESTATE.flags], SS_CLEARED
    jnz     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    mobs_clear
    call    rpg_reset
    call    structures_reset
    call    zero_sites
    lea     rsi, [rsp]
    lea     rdi, [player]
    mov     ecx, BODY_size
    rep movsb
    mov     eax, [rsp + 72]
    mov     [game_mode], eax
    mov     eax, [rsp + 76]
    mov     [settings + SETTINGS.difficulty], eax
    mov     eax, ebx
    add     rsp, 104
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- test 6: the camps and the plan's counts ----------------------------------------------------

; check_super(edi sx, esi sz) -> eax 0 when the camps of the super-region (sx, sz) obey the plan: each
; faction at most once, each in a biome of its home set, inside the region it is listed under and the
; super-region (64 blocks in from its border), 96 or more from the village of its region, 128 or more
; from every other camp
; Frame: [rsp] sx, [rsp+4] sz, [rsp+8] camps, [rsp+12] village x, [rsp+16] village z, [rsp+20] has a
; village, [rsp+24] camp x[5], [rsp+44] camp z[5], [rsp+64] faction seen[5], [rsp+84] ... (96 bytes).
check_super:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 104
    mov     [rsp], edi
    mov     [rsp + 4], esi
    mov     dword [rsp + 8], 0
    lea     rdi, [rsp + 64]
    xor     eax, eax
    mov     ecx, 5
    rep     stosd
    lea     eax, [rsi + rsi*2]          ; arz = 3 sz .. 3 sz + 2
    mov     r14d, eax
.row:
    mov     eax, [rsp]
    lea     r13d, [rax + rax*2]         ; arx = 3 sx .. 3 sx + 2
.col:
    mov     edi, r13d
    mov     esi, r14d
    lea     rdx, [plan_a]
    call    region_plan
    mov     r12d, eax
    mov     dword [rsp + 20], 0
    lea     rbx, [plan_a]
    mov     ecx, r12d
.find_village:
    test    ecx, ecx
    jz      .camps
    cmp     dword [rbx + SITE.kind], SITE_VILLAGE
    jne     .fv_next
    mov     eax, [rbx + SITE.x]
    mov     [rsp + 12], eax
    mov     eax, [rbx + SITE.z]
    mov     [rsp + 16], eax
    mov     dword [rsp + 20], 1
.fv_next:
    add     rbx, SITE_size
    dec     ecx
    jmp     .find_village
.camps:
    lea     rbx, [plan_a]
    mov     r15d, r12d
.camp:
    test    r15d, r15d
    jz      .next_region
    cmp     dword [rbx + SITE.kind], SITE_CAMP
    jne     .camp_next
    mov     eax, [rbx + SITE.index]
    cmp     eax, NUM_FACTIONS
    jae     .bad
    inc     dword [rsp + 64 + rax*4]
    cmp     dword [rsp + 64 + rax*4], 1
    ja      .bad                        ; a faction has one camp per super-region
    mov     ecx, [rbx + SITE.x]         ; inside the region it is listed under
    sar     ecx, 9
    cmp     ecx, r13d
    jne     .bad
    mov     ecx, [rbx + SITE.z]
    sar     ecx, 9
    cmp     ecx, r14d
    jne     .bad
    imul    ecx, [rsp], 1536            ; and 64 in from the super-region's border
    mov     edx, [rbx + SITE.x]
    sub     edx, ecx
    sub     edx, 64
    cmp     edx, 1407
    ja      .bad
    imul    ecx, [rsp + 4], 1536
    mov     edx, [rbx + SITE.z]
    sub     edx, ecx
    sub     edx, 64
    cmp     edx, 1407
    ja      .bad
    mov     edi, [rbx + SITE.x]         ; its biome is one of the faction's
    mov     esi, [rbx + SITE.z]
    call    gen_biome
    mov     ecx, [rbx + SITE.index]
    lea     rdx, [t_homes]
    mov     edx, [rdx + rcx*4]
    bt      edx, eax
    jnc     .bad
    cmp     dword [rsp + 20], 0
    je      .far_camps
    mov     eax, [rbx + SITE.x]         ; 96 from the village of its region
    sub     eax, [rsp + 12]
    imul    eax, eax
    mov     ecx, [rbx + SITE.z]
    sub     ecx, [rsp + 16]
    imul    ecx, ecx
    add     eax, ecx
    cmp     eax, 96 * 96
    jb      .bad
.far_camps:
    xor     ecx, ecx                    ; 128 from the camps listed before
.prev:
    cmp     ecx, [rsp + 8]
    jae     .store
    mov     eax, [rbx + SITE.x]
    sub     eax, [rsp + 24 + rcx*4]
    imul    eax, eax
    mov     edx, [rbx + SITE.z]
    sub     edx, [rsp + 44 + rcx*4]
    imul    edx, edx
    add     eax, edx
    cmp     eax, 128 * 128
    jb      .bad
    inc     ecx
    jmp     .prev
.store:
    mov     ecx, [rsp + 8]
    cmp     ecx, 5
    jae     .bad
    mov     eax, [rbx + SITE.x]
    mov     [rsp + 24 + rcx*4], eax
    mov     eax, [rbx + SITE.z]
    mov     [rsp + 44 + rcx*4], eax
    inc     dword [rsp + 8]
.camp_next:
    add     rbx, SITE_size
    dec     r15d
    jmp     .camp
.next_region:
    inc     r13d
    mov     eax, [rsp]
    lea     eax, [rax + rax*2 + 2]
    cmp     r13d, eax
    jle     .col
    inc     r14d
    mov     eax, [rsp + 4]
    lea     eax, [rax + rax*2 + 2]
    cmp     r14d, eax
    jle     .row
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    add     rsp, 104
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; check_site_exits() -> eax 0 when, over the 169 regions -6 .. 6 of the current seed, no crypt stands
; at an OCEAN or RIVER centre and the stair tunnel of every dungeon and crypt - it leaves the west
; wall at x - 5 or x - 8 with y0 = floor - 1, as stair_tunnel is called - comes out within 60
; columns with its feet y0 + i + 1 higher than SEA_LEVEL. Else the failures found, OR-ed: 2 a crypt
; under an ocean or a river, 4 a tunnel that never comes out, 8 an exit at or below the sea (the
; sweep goes on after a failure, so one run names every rule that fails).
; Frame: [rsp] arx, [rsp+4] arz.
check_site_exits:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    xor     r13d, r13d                  ; the failures found
    mov     dword [rsp + 4], -EXIT_SWEEP
.row:
    mov     dword [rsp], -EXIT_SWEEP
.col:
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    lea     rdx, [plan_b]
    call    region_plan
    mov     r14d, eax                   ; sites left
    lea     r15, [plan_b]
.site:
    test    r14d, r14d
    jz      .next
    mov     ebx, 5                      ; where the tunnel leaves the wall: x - 5 for a dungeon
    cmp     dword [r15 + SITE.kind], SITE_DUNGEON
    je      .tunnel
    cmp     dword [r15 + SITE.kind], SITE_CRYPT
    jne     .adv
    mov     ebx, 8                      ; x - 8 for a crypt, which must not stand under water
    mov     edi, [r15 + SITE.x]
    mov     esi, [r15 + SITE.z]
    call    gen_biome
    cmp     eax, BIOME_OCEAN
    je      .crypt_wet
    cmp     eax, BIOME_RIVER
    jne     .tunnel
.crypt_wet:
    or      r13d, 2
.tunnel:
    mov     edi, [r15 + SITE.x]
    sub     edi, ebx
    mov     esi, [r15 + SITE.z]
    mov     r12d, [r15 + SITE.y]
    dec     r12d                        ; y0
    mov     edx, r12d
    call    tunnel_expect
    test    eax, eax
    jnz     .exits
    or      r13d, 4
    jmp     .adv
.exits:
    lea     eax, [rax + r12 + 1]        ; the feet of the exit
    cmp     eax, SEA_LEVEL
    jg      .adv
    or      r13d, 8
.adv:
    add     r15, SITE_size
    dec     r14d
    jmp     .site
.next:
    inc     dword [rsp]
    cmp     dword [rsp], EXIT_SWEEP
    jle     .col
    inc     dword [rsp + 4]
    cmp     dword [rsp + 4], EXIT_SWEEP
    jle     .row
    mov     eax, r13d
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; check_camp_clearing() -> eax 0 when the first camp the plans have (regions -3..3) is built through
; gen_column as a clearing: one top block (grass, sand, stone or snow block) over the cells within 10 of
; its centre at its ground height, something solid under it, air above up to 12 blocks, and a fence
; post with a torch on it in the middle
; Frame: [rsp .. +56) the site, [rsp+56] the top block.
check_camp_clearing:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 72
    mov     r12d, -3                    ; arz
.rz:
    mov     r13d, -3                    ; arx
.rx:
    mov     edi, r13d
    mov     esi, r12d
    lea     rdx, [plan_a]
    call    region_plan
    mov     ecx, eax
    lea     rax, [plan_a]
.scan:
    test    ecx, ecx
    jz      .next_region
    cmp     dword [rax + SITE.kind], SITE_CAMP
    je      .found
    add     rax, SITE_size
    dec     ecx
    jmp     .scan
.found:
    mov     rsi, rax
    lea     rdi, [rsp]
    mov     ecx, SITE_size / 8
    rep movsq
    jmp     .have
.next_region:
    inc     r13d
    cmp     r13d, 3
    jle     .rx
    inc     r12d
    cmp     r12d, 3
    jle     .rz
    jmp     .bad                        ; no camp in 49 regions
.have:
    lea     rbx, [rsp]
    mov     edi, [rbx + SITE.x]
    sub     edi, 11
    sar     edi, 4
    mov     esi, [rbx + SITE.z]
    sub     esi, 11
    sar     esi, 4
    call    tg_reset
    mov     rdi, rbx
    xor     esi, esi
    xor     edx, edx
    xor     ecx, ecx
    call    block_at
    mov     [rsp + 56], eax
    cmp     eax, GRASS
    je      .top_ok
    cmp     eax, SAND
    je      .top_ok
    cmp     eax, STONE
    je      .top_ok
    cmp     eax, SNOW_BLOCK
    jne     .bad
.top_ok:
    mov     r14d, -10                   ; dz
.dz:
    mov     r15d, -10                   ; dx
.dx:
    mov     rdi, rbx                    ; the top block, the same all over the clearing
    mov     esi, r15d
    xor     edx, edx
    mov     ecx, r14d
    call    block_at
    cmp     eax, [rsp + 56]
    jne     .bad
    mov     rdi, rbx                    ; something solid under it
    mov     esi, r15d
    mov     edx, -3
    mov     ecx, r14d
    call    block_at
    test    eax, eax
    jz      .bad
    mov     r12d, 1                     ; dy 1, 2, 3 and 12 above it: air, but for the post
.dy:
    mov     rdi, rbx
    mov     esi, r15d
    mov     edx, r12d
    mov     ecx, r14d
    call    block_at
    mov     ecx, r15d
    or      ecx, r14d
    jnz     .air                        ; not the middle: air
    mov     edx, AIR
    cmp     r12d, 1
    jne     .not_post
    mov     edx, FENCE
.not_post:
    cmp     r12d, 2
    jne     .check
    mov     edx, TORCH
    jmp     .check
.air:
    xor     edx, edx
.check:
    cmp     eax, edx
    jne     .bad
    inc     r12d
    cmp     r12d, 4
    jne     .dy_more
    mov     r12d, 12                    ; and the top of the cleared volume
    jmp     .dy
.dy_more:
    cmp     r12d, 13
    jne     .dy
    add     r15d, 5
    cmp     r15d, 10
    jle     .dx
    add     r14d, 5
    cmp     r14d, 10
    jle     .dz
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    add     rsp, 72
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; seed 42: the camps of the super-regions (0, 0) and (-1, -1) obey the plan (check_super); over the 25
; regions -2..2 no region has more than 2 dungeons or 1 crypt, a crypt is only in regions with even
; arx and arz, at least 5 of the 9 such regions have one and at least 20 of the 25 regions have a
; dungeon; over the 169 regions -6..6 no crypt stands under an ocean or a river and the stair tunnel
; of every dungeon and crypt comes out above the sea (check_site_exits; its result, 2, 4 or 8 OR-ed,
; names the rules that fail); the first camp is a clearing (check_camp_clearing)
; Frame: [rsp] arx, [rsp+4] arz, [rsp+8] regions with a dungeon, [rsp+12] crypts.
test_region_plan_camps:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    call    world_clear
    mov     edi, 42
    call    worldgen_set_seed
    xor     edi, edi
    xor     esi, esi
    call    check_super
    test    eax, eax
    jnz     .fail
    mov     edi, -1
    mov     esi, -1
    call    check_super
    test    eax, eax
    jnz     .fail
    mov     qword [rsp + 8], 0
    mov     dword [rsp + 4], -2
.row:
    mov     dword [rsp], -2
.col:
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    lea     rdx, [plan_a]
    call    region_plan
    mov     ebx, eax
    xor     r12d, r12d                  ; dungeons
    xor     r13d, r13d                  ; crypts
    lea     rax, [plan_a]
.site:
    test    ebx, ebx
    jz      .counted
    cmp     dword [rax + SITE.kind], SITE_DUNGEON
    jne     .not_dungeon
    inc     r12d
.not_dungeon:
    cmp     dword [rax + SITE.kind], SITE_CRYPT
    jne     .not_crypt
    inc     r13d
.not_crypt:
    add     rax, SITE_size
    dec     ebx
    jmp     .site
.counted:
    cmp     r12d, 2
    ja      .fail
    test    r12d, r12d
    jz      .no_dungeon
    inc     dword [rsp + 8]
.no_dungeon:
    cmp     r13d, 1
    ja      .fail
    test    r13d, r13d
    jz      .next
    mov     eax, [rsp]
    or      eax, [rsp + 4]
    test    eax, 1
    jnz     .fail                       ; a crypt in a region with an odd coordinate
    inc     dword [rsp + 12]
.next:
    inc     dword [rsp]
    cmp     dword [rsp], 2
    jle     .col
    inc     dword [rsp + 4]
    cmp     dword [rsp + 4], 2
    jle     .row
    cmp     dword [rsp + 8], 20
    jb      .fail
    cmp     dword [rsp + 12], 5
    jb      .fail
    call    check_site_exits
    test    eax, eax
    jnz     .out
    call    check_camp_clearing
    jmp     .out
.fail:
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

; ---- test 7: the site table's eviction ----------------------------------------------------------

; with WORLDHDR.sites full (regions 100 + i, i = 0..1023) and the player in region (0, 0), a new site
; takes the place of the record of the farthest region (1123, 0), and keeps it for later calls;
; the next one takes the next farthest, skipping a record a live mob's origin points at
; Frame: [rsp .. +56) a site, [rsp+56] the record taken first.
test_sitestate_eviction:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 104
    lea     rdi, [rsp + 64]
    mov     eax, [player + BODY.x]
    mov     [rdi], eax
    mov     eax, [player + BODY.y]
    mov     [rdi + 4], eax
    mov     eax, [player + BODY.z]
    mov     [rdi + 8], eax
    mov     eax, [world_origin_x]
    mov     [rsp + 76], eax
    mov     eax, [world_origin_z]
    mov     [rsp + 80], eax
    call    world_clear
    call    mobs_clear
    call    zero_sites
    mov     dword [world_origin_x], 0
    mov     dword [world_origin_z], 0
    movss   xmm0, [k_half]
    movss   [player + BODY.x], xmm0
    movss   [player + BODY.z], xmm0
    movss   xmm0, [k_70]
    movss   [player + BODY.y], xmm0
    lea     rdi, [world_header + WORLDHDR.sites]
    xor     ebx, ebx
.fill:
    lea     eax, [rbx + 100]
    mov     [rdi + SITESTATE.rx], eax
    mov     dword [rdi + SITESTATE.rz], 0
    mov     byte [rdi + SITESTATE.slot], 0
    mov     byte [rdi + SITESTATE.kind], SITE_VILLAGE
    mov     byte [rdi + SITESTATE.kills], 0
    mov     byte [rdi + SITESTATE.flags], 0
    add     rdi, SITESTATE_size
    inc     ebx
    cmp     ebx, MAX_SITESTATES
    jb      .fill
    mov     dword [world_header + WORLDHDR.site_count], MAX_SITESTATES
    lea     rdi, [rsp]
    mov     esi, SITE_DUNGEON
    mov     edx, 10
    mov     ecx, 40
    mov     r8d, 10
    mov     r9d, 3
    call    fab_site
    lea     rdi, [rsp]
    call    site_state
    test    rax, rax
    jz      .fail
    mov     rbx, rax
    lea     rdi, [world_header + WORLDHDR.sites + (MAX_SITESTATES - 1) * SITESTATE_size]
    cmp     rbx, rdi
    jne     .fail                       ; the farthest region's record (1123, 0) went
    cmp     dword [rbx + SITESTATE.rx], 0
    jne     .fail
    cmp     dword [rbx + SITESTATE.rz], 0
    jne     .fail
    cmp     byte [rbx + SITESTATE.slot], 3
    jne     .fail
    cmp     byte [rbx + SITESTATE.kind], SITE_DUNGEON
    jne     .fail
    cmp     word [rbx + SITESTATE.kills], 0 ; kills and flags
    jne     .fail
    cmp     dword [world_header + WORLDHDR.site_count], MAX_SITESTATES
    jne     .fail
    cmp     dword [world_header + WORLDHDR.sites + SITESTATE.rx], 100
    jne     .fail                       ; the others are untouched
    lea     rdi, [rsp]
    call    site_state
    cmp     rax, rbx
    jne     .fail                       ; found again, nothing evicted
    cmp     dword [world_header + WORLDHDR.sites + (MAX_SITESTATES - 2) * SITESTATE_size + SITESTATE.rx], 1122
    jne     .fail
    mov     edi, MOB_ZOMBIE             ; a live mob born at the next farthest record (1122, 0)
    movss   xmm0, [k_8_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_8_5]
    call    mob_spawn
    test    eax, eax
    js      .fail
    imul    eax, eax, MOB_size
    lea     rcx, [mobs]
    mov     dword [rcx + rax + MOB.origin], MAX_SITESTATES - 1  ; record index 1022
    lea     rdi, [rsp]
    mov     dword [rdi + SITE.slot], 4
    call    site_state
    test    rax, rax
    jz      .fail
    lea     rdi, [world_header + WORLDHDR.sites + (MAX_SITESTATES - 3) * SITESTATE_size]
    cmp     rax, rdi
    jne     .fail                       ; (1121, 0) went, the referenced (1122, 0) stayed
    cmp     dword [world_header + WORLDHDR.sites + (MAX_SITESTATES - 2) * SITESTATE_size + SITESTATE.rx], 1122
    jne     .fail
    cmp     byte [rax + SITESTATE.slot], 4
    jne     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    mobs_clear
    call    zero_sites
    mov     eax, [rsp + 64]
    mov     [player + BODY.x], eax
    mov     eax, [rsp + 68]
    mov     [player + BODY.y], eax
    mov     eax, [rsp + 72]
    mov     [player + BODY.z], eax
    mov     eax, [rsp + 76]
    mov     [world_origin_x], eax
    mov     eax, [rsp + 80]
    mov     [world_origin_z], eax
    mov     eax, ebx
    add     rsp, 104
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
