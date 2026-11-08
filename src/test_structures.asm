; test_structures.asm - site planning, the built dungeons, villages and crypt, the dungeon kill
; counter and the crypt's boss trigger.
%include "common.inc"
default rel

global test_structure_sites_deterministic, test_dungeon_built_with_chests
global test_village_built_with_npcs, test_dungeon_clears_after_kills
global test_crypt_spawns_boss_once

extern blocks, world_header, world_clear, world_generate, world_get
extern sites, site_count, structures_plan, structures_reset, structures_spawn_npcs
extern structures_step, structures_on_mob_killed
extern mobs, mobs_clear, mob_count_type
extern rpg_state, rpg_reset, rpg_xp_need
extern fx_clear, survival_reset, combat_reset
extern game_mode, settings, player
extern item_gear

section .rodata
align 4
k_one:   dd 1.0
k_half:  dd 0.5
k_3_5:   dd 3.5
k_10:    dd 10.0
k_6:     dd 6.0
k_20:    dd 20.0

section .bss
alignb 16
snap:       resb MAX_SITES * SITE_size  ; the sites of the first plan
snap_count: resd 1

section .text

; zero_conts(): empties the container table in the world header
zero_conts:
    lea     rdi, [world_header + WORLDHDR.containers_v5]
    mov     ecx, MAX_CONTAINERS_V5 * CONTAINER_size
    xor     eax, eax
    rep     stosb
    ret

; find_site(edi kind, esi index) -> rax SITE* or 0
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

; count_kind(edi kind) -> eax number of planned sites of that kind
count_kind:
    xor     eax, eax
    lea     rsi, [sites]
    mov     ecx, [site_count]
    test    ecx, ecx
    jz      .ret
.l:
    cmp     [rsi + SITE.kind], edi
    jne     .n
    inc     eax
.n:
    add     rsi, SITE_size
    dec     ecx
    jnz     .l
.ret:
    ret

; plan(42) twice gives identical sites without writing a block; they hold at least one village,
; six dungeons and the crypt, each with a sane trigger box; another seed plans other sites
test_structure_sites_deterministic:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    world_clear
    mov     edi, 42
    call    structures_plan
    lea     rdi, [blocks]               ; planning is pure: the world is still empty
    mov     ecx, WORLD_VOLUME / 8
    xor     eax, eax
    repe scasq
    jne     .fail
    mov     eax, [site_count]
    mov     [snap_count], eax
    lea     rsi, [sites]
    lea     rdi, [snap]
    mov     ecx, MAX_SITES * SITE_size
    rep movsb
    mov     edi, 42
    call    structures_plan
    mov     eax, [site_count]
    cmp     eax, [snap_count]
    jne     .fail
    lea     rsi, [sites]
    lea     rdi, [snap]
    mov     ecx, MAX_SITES * SITE_size
    repe cmpsb
    jne     .fail
    mov     edi, SITE_VILLAGE
    call    count_kind
    test    eax, eax
    jz      .fail
    mov     edi, SITE_DUNGEON
    call    count_kind
    cmp     eax, NUM_DUNGEONS
    jne     .fail
    mov     edi, SITE_CRYPT
    call    count_kind
    cmp     eax, 1
    jne     .fail
    ; every site: its position inside its box, the box within the world's x and z extent and
    ; above y 0 (a village on high ground reaches past the top), y by kind
    lea     rbx, [sites]
    mov     r12d, [site_count]
.site:
    mov     eax, [rbx + SITE.x]
    cmp     eax, [rbx + SITE.lo_x]
    jl      .fail
    cmp     eax, [rbx + SITE.hi_x]
    jg      .fail
    mov     eax, [rbx + SITE.y]
    cmp     eax, [rbx + SITE.lo_y]
    jl      .fail
    cmp     eax, [rbx + SITE.hi_y]
    jg      .fail
    mov     eax, [rbx + SITE.z]
    cmp     eax, [rbx + SITE.lo_z]
    jl      .fail
    cmp     eax, [rbx + SITE.hi_z]
    jg      .fail
    cmp     dword [rbx + SITE.lo_x], 0
    jl      .fail
    cmp     dword [rbx + SITE.hi_x], WORLD_X - 1
    jg      .fail
    cmp     dword [rbx + SITE.lo_z], 0
    jl      .fail
    cmp     dword [rbx + SITE.hi_z], WORLD_Z - 1
    jg      .fail
    cmp     dword [rbx + SITE.lo_y], 0
    jl      .fail
    cmp     dword [rbx + SITE.kind], SITE_DUNGEON
    jne     .not_dungeon
    cmp     dword [rbx + SITE.y], 8
    jne     .fail
.not_dungeon:
    cmp     dword [rbx + SITE.kind], SITE_CRYPT
    jne     .next
    cmp     dword [rbx + SITE.y], 6
    jne     .fail
.next:
    add     rbx, SITE_size
    dec     r12d
    jnz     .site
    mov     edi, 43                     ; the seed matters
    call    structures_plan
    lea     rsi, [sites]
    lea     rdi, [snap]
    mov     ecx, MAX_SITES * SITE_size
    repe cmpsb
    je      .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     dword [site_count], 0
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; chests_in(rdi SITE*, esi gears, edx tier, ecx min_rar) -> eax number of CONT_CHEST containers
; inside the site's box, each on a CHEST block and holding loot plus exactly `gears` rolled gear
; pieces (item_gear != 0, a seed in the dmg word) of the given tier and at least that rarity;
; -1 when one of them does not
; Frame: [rsp] gear pieces of the chest, [rsp+4] other items, [rsp+8] gears, [rsp+12] tier,
; [rsp+16] lowest rarity.
chests_in:
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
    lea     r12, [world_header + WORLDHDR.containers_v5]
    mov     r13d, MAX_CONTAINERS_V5
    xor     r14d, r14d                  ; chests inside the box
.rec:
    cmp     byte [r12 + CONTAINER.kind], CONT_CHEST
    jne     .rnext
    mov     eax, [r12 + CONTAINER.x]
    cmp     eax, [rbx + SITE.lo_x]
    jl      .rnext
    cmp     eax, [rbx + SITE.hi_x]
    jg      .rnext
    mov     eax, [r12 + CONTAINER.y]
    cmp     eax, [rbx + SITE.lo_y]
    jl      .rnext
    cmp     eax, [rbx + SITE.hi_y]
    jg      .rnext
    mov     eax, [r12 + CONTAINER.z]
    cmp     eax, [rbx + SITE.lo_z]
    jl      .rnext
    cmp     eax, [rbx + SITE.hi_z]
    jg      .rnext
    mov     edi, [r12 + CONTAINER.x]
    mov     esi, [r12 + CONTAINER.y]
    mov     edx, [r12 + CONTAINER.z]
    call    world_get
    cmp     eax, CHEST
    jne     .bad
    mov     qword [rsp], 0
    xor     r15d, r15d
.cell:
    movzx   eax, byte [r12 + CONTAINER.slots + r15*4 + ITEMSTACK.id]
    test    eax, eax
    jz      .cnext
    cmp     byte [r12 + CONTAINER.slots + r15*4 + ITEMSTACK.count], 0
    je      .cnext
    lea     rcx, [item_gear]
    cmp     byte [rcx + rax], 0
    jne     .gear
    inc     dword [rsp + 4]
    jmp     .cnext
.gear:
    inc     dword [rsp]
    movzx   eax, word [r12 + CONTAINER.slots + r15*4 + ITEMSTACK.dmg]
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
    je      .bad                        ; an empty chest, or one holding nothing but gear
    inc     r14d
.rnext:
    add     r12, CONTAINER_size
    dec     r13d
    jnz     .rec
    mov     eax, r14d
    jmp     .ret
.bad:
    mov     eax, -1
.ret:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; first_mob() -> rax the first live mob, 0 when there is none
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

; block_at(rdi SITE*, esi dx, edx y, ecx dz) -> eax the block at (site x + dx, y, site z + dz)
block_at:
    mov     eax, [rdi + SITE.x]
    add     eax, esi
    mov     esi, edx
    mov     edx, [rdi + SITE.z]
    add     edx, ecx
    mov     edi, eax
    jmp     world_get

; tun_at(esi dy, ecx dz) -> eax the block of the dungeon in rbx at tunnel column r15d (x = ox - 5
; - r15d), y = floor + dy (the floor is 7 + r15d), z = oz + dz
tun_at:
    mov     edi, [rbx + SITE.x]
    sub     edi, 5
    sub     edi, r15d
    lea     eax, [rsi + 7]
    add     eax, r15d
    mov     edx, [rbx + SITE.z]
    add     edx, ecx
    mov     esi, eax
    jmp     world_get

; tun_frame() -> eax 1 when tunnel column r15d of the dungeon in rbx carries the entrance frame:
; mossy brick at dy 4 for dz -2..2 and at dy 1..3 for dz -2 and 2 (a shell column of random
; stone/mossy brick matches all 11 cells with odds of about 2e-6)
tun_frame:
    push    r12
    push    r13
    push    r14
    mov     r12d, -2
.lintel:
    mov     esi, 4
    mov     ecx, r12d
    call    tun_at
    cmp     eax, MOSSY_STONE_BRICK
    jne     .no
    inc     r12d
    cmp     r12d, 2
    jle     .lintel
    mov     r13d, 1
.pillar:
    mov     esi, r13d
    mov     ecx, -2
    call    tun_at
    cmp     eax, MOSSY_STONE_BRICK
    jne     .no
    mov     esi, r13d
    mov     ecx, 2
    call    tun_at
    cmp     eax, MOSSY_STONE_BRICK
    jne     .no
    inc     r13d
    cmp     r13d, 3
    jbe     .pillar
    mov     eax, 1
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    pop     r14
    pop     r13
    pop     r12
    ret

; EXPECT_AIR dx, y, dz: the block at that offset from the site in rbx is AIR
%macro EXPECT_AIR 3
    mov     rdi, rbx
    mov     esi, %1
    mov     edx, %2
    mov     ecx, %3
    call    block_at
    test    eax, eax
    jnz     .fail
%endmacro

; EXPECT_ID dx, y, dz, id: the block at that offset from the site in rbx is `id`
%macro EXPECT_ID 4
    mov     rdi, rbx
    mov     esi, %1
    mov     edx, %2
    mov     ecx, %3
    call    block_at
    cmp     eax, %4
    jne     .fail
%endmacro

; world_generate(42): the first dungeon has open rooms, corridor and west opening, a brick west
; wall, four loaded chests (each with one rolled piece of gear of tier 2 + 2 * dungeon, in every
; dungeon), and a stair tunnel with brick floor and open passage that ends in the entrance frame;
; the crypt has an open hall, its pillars and two loaded chests with two pieces of tier 13 each
test_dungeon_built_with_chests:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    call    world_clear
    call    zero_conts
    mov     edi, 42
    call    world_generate
    mov     edi, SITE_DUNGEON
    xor     esi, esi
    call    find_site
    test    rax, rax
    jz      .fail
    mov     rbx, rax
    EXPECT_AIR 0, 9, 0                  ; the middle of the first room, 1 above the floor
    EXPECT_AIR 14, 9, 0                 ; the second room
    EXPECT_AIR 14, 9, 14                ; the third
    EXPECT_AIR 7, 9, 0                  ; the corridor between the first two
    EXPECT_AIR 14, 9, 7                 ; and the one between the last two
    EXPECT_AIR -5, 10, 1                ; the opening in the west wall
    EXPECT_ID 0, 10, -4, TORCH_WALL + DIR_N     ; the torches of the rooms
    EXPECT_ID 14, 10, -4, TORCH_WALL + DIR_N
    EXPECT_ID 14, 10, 18, TORCH_WALL + DIR_S
    mov     rdi, rbx                    ; the west wall beside it is brick
    mov     esi, -5
    mov     edx, 9
    mov     ecx, 3
    call    block_at
    cmp     eax, STONE_BRICK
    je      .wall_ok
    cmp     eax, MOSSY_STONE_BRICK
    jne     .fail
.wall_ok:
    mov     rdi, rbx
    mov     esi, 1
    mov     edx, 2
    xor     ecx, ecx                    ; a dungeon's table may roll common
    call    chests_in
    cmp     eax, 4
    jne     .fail
    mov     r15d, 1                     ; tunnel column i: floor at y = 7 + i
.column:
    xor     esi, esi
    xor     ecx, ecx
    call    tun_at
    cmp     eax, STONE_BRICK_STAIRS + DIR_W
    je      .floor
    cmp     r15d, 1                     ; column 1 must have the stair floor
    je      .fail
    call    tun_frame                   ; no stair floor: the entrance frame stands here
    test    eax, eax
    jz      .fail
    mov     esi, 1
    xor     ecx, ecx
    call    tun_at
    test    eax, eax                    ; and the way through it is open
    jnz     .fail
    jmp     .tunnel_done
.floor:
    mov     r14d, 1                     ; the passage above the floor is open
.pass:
    mov     esi, r14d
    xor     ecx, ecx
    call    tun_at
    test    eax, eax
    jnz     .fail
    inc     r14d
    cmp     r14d, 3
    jbe     .pass
    call    tun_frame                   ; stair floor under the entrance frame: the last column
    test    eax, eax
    jz      .next_column
    jmp     .tunnel_done
.next_column:
    inc     r15d
    cmp     r15d, 60
    jbe     .column
    jmp     .fail                       ; it never came out of the ground
.tunnel_done:
    ; every dungeon's tunnel exit: one column past the entrance frame, at the exit's feet
    ; level, is open, so walking out needs no jump
    xor     r12d, r12d                  ; dungeon index
.exit_site:
    mov     edi, SITE_DUNGEON
    mov     esi, r12d
    call    find_site
    test    rax, rax
    jz      .fail
    mov     rbx, rax
    mov     rdi, rbx
    mov     esi, 1
    lea     edx, [r12*2 + 2]
    xor     ecx, ecx
    call    chests_in
    cmp     eax, 4
    jne     .fail
    mov     r15d, 1
.exit_scan:
    call    tun_frame
    test    eax, eax
    jnz     .exit_found
    inc     r15d
    cmp     r15d, 60
    jbe     .exit_scan
    jmp     .fail
.exit_found:
    inc     r15d
    xor     esi, esi
    xor     ecx, ecx
    call    tun_at
    test    eax, eax
    jnz     .fail
    inc     r12d
    cmp     r12d, NUM_DUNGEONS
    jb      .exit_site
    mov     edi, SITE_CRYPT
    xor     esi, esi
    call    find_site
    test    rax, rax
    jz      .fail
    mov     rbx, rax
    EXPECT_AIR 0, 7, 0                  ; the hall
    EXPECT_AIR -8, 7, 0                 ; and its west opening
    EXPECT_ID 3, 9, -4, TORCH_WALL + DIR_E      ; its torches, on the pillars
    EXPECT_ID 3, 9, 4, TORCH_WALL + DIR_E
    EXPECT_ID -3, 9, -4, TORCH_WALL + DIR_W
    EXPECT_ID -3, 9, 4, TORCH_WALL + DIR_W
    mov     rdi, rbx                    ; a pillar
    mov     esi, 4
    mov     edx, 8
    mov     ecx, 4
    call    block_at
    cmp     eax, STONE_BRICK
    jne     .fail
    mov     rdi, rbx
    mov     esi, 2
    mov     edx, 13
    mov     ecx, RAR_MAGIC              ; the boss table never rolls common
    call    chests_in
    cmp     eax, 2
    jne     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    zero_conts
    call    world_clear
    mov     dword [site_count], 0
    mov     eax, ebx
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; world_generate(42) + structures_spawn_npcs: one merchant and one elder per village, the well's
; glass at the village's middle, and the first house with its cobble floor, plank roof, closed
; wooden door (west wall, facing the well), wall torch inside and plank wall opposite the door
test_village_built_with_npcs:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    call    world_clear
    call    zero_conts
    call    mobs_clear
    mov     edi, 42
    call    world_generate
    call    mobs_clear
    call    structures_spawn_npcs
    xor     r13d, r13d                  ; villages seen
    lea     rbx, [sites]
    mov     r12d, [site_count]
.site:
    cmp     dword [rbx + SITE.kind], SITE_VILLAGE
    jne     .next
    inc     r13d
    mov     edi, [rbx + SITE.x]         ; the well
    mov     esi, [rbx + SITE.y]
    mov     edx, [rbx + SITE.z]
    call    world_get
    cmp     eax, GLASS
    jne     .fail
    mov     edi, [rbx + SITE.x]         ; house 0 stands 9 east: floor, roof, door, wall
    add     edi, 9
    mov     esi, [rbx + SITE.y]
    mov     edx, [rbx + SITE.z]
    call    world_get
    cmp     eax, COBBLE
    jne     .fail
    mov     edi, [rbx + SITE.x]
    add     edi, 9
    mov     esi, [rbx + SITE.y]
    add     esi, 4
    mov     edx, [rbx + SITE.z]
    call    world_get
    cmp     eax, PLANKS
    jne     .fail
    mov     edi, [rbx + SITE.x]         ; the door: a closed wooden door facing west, both halves
    add     edi, 7
    mov     esi, [rbx + SITE.y]
    inc     esi
    mov     edx, [rbx + SITE.z]
    call    world_get
    cmp     eax, WOOD_DOOR + DIR_W * 4
    jne     .fail
    mov     edi, [rbx + SITE.x]
    add     edi, 7
    mov     esi, [rbx + SITE.y]
    add     esi, 2
    mov     edx, [rbx + SITE.z]
    call    world_get
    cmp     eax, WOOD_DOOR + DIR_W * 4 + 1
    jne     .fail
    mov     edi, [rbx + SITE.x]         ; the wall torch inside, leaning on the east wall
    add     edi, 10
    mov     esi, [rbx + SITE.y]
    add     esi, 2
    mov     edx, [rbx + SITE.z]
    inc     edx
    call    world_get
    cmp     eax, TORCH_WALL + DIR_E
    jne     .fail
    mov     edi, [rbx + SITE.x]
    add     edi, 11
    mov     esi, [rbx + SITE.y]
    inc     esi
    mov     edx, [rbx + SITE.z]
    call    world_get
    cmp     eax, PLANKS
    jne     .fail
.next:
    add     rbx, SITE_size
    dec     r12d
    jnz     .site
    test    r13d, r13d
    jz      .fail
    mov     edi, MOB_MERCHANT
    call    mob_count_type
    cmp     eax, r13d
    jne     .fail
    mov     edi, MOB_ELDER
    call    mob_count_type
    cmp     eax, r13d
    jne     .fail
    ; every merchant and elder stands on the village ground (path or grass), not on a roof
    lea     r14, [mobs]
    mov     r12d, MAX_MOBS
.npc:
    mov     eax, [r14 + MOB.type]
    cmp     eax, MOB_MERCHANT
    je      .npc_ground
    cmp     eax, MOB_ELDER
    jne     .npc_next
.npc_ground:
    cvttss2si edi, [r14 + BODY.x]
    cvttss2si esi, [r14 + BODY.y]
    dec     esi
    cvttss2si edx, [r14 + BODY.z]
    call    world_get
    cmp     eax, GRAVEL
    je      .npc_next
    cmp     eax, GRASS
    jne     .fail
.npc_next:
    add     r14, MOB_size
    dec     r12d
    jnz     .npc
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    mobs_clear
    call    zero_conts
    call    world_clear
    mov     dword [site_count], 0
    mov     eax, ebx
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; eight deaths of dungeon 0's mobs clear it: the 8th (not the 7th, not origin 0 or the crypt boss)
; sets bit 0 of the cleared mask and awards 150 XP + 15 per level (165 at level 1) once; the clear
; of dungeon 1 at level 10 pays 300
test_dungeon_clears_after_kills:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    world_clear
    call    structures_reset
    call    rpg_reset
    mov     byte [rpg_state + RPGSAVE.class], CLASS_WARRIOR
    mov     ebx, 7
.seven:
    mov     edi, 1
    call    structures_on_mob_killed
    dec     ebx
    jnz     .seven
    test    byte [rpg_state + RPGSAVE.cleared], 1
    jnz     .fail
    cmp     dword [rpg_state + RPGSAVE.xp], 0
    jne     .fail
    cmp     byte [rpg_state + RPGSAVE.level], 1
    jne     .fail
    xor     edi, edi                    ; not dungeon mobs: no count
    call    structures_on_mob_killed
    mov     edi, 99
    call    structures_on_mob_killed
    mov     edi, 7
    call    structures_on_mob_killed
    test    byte [rpg_state + RPGSAVE.cleared], 1
    jnz     .fail
    mov     edi, 1
    call    structures_on_mob_killed
    movzx   eax, byte [rpg_state + RPGSAVE.cleared]
    cmp     eax, 1                      ; dungeon 0 only
    jne     .fail
    call    total_xp
    cmp     eax, 165
    jne     .fail
    mov     edi, 1                      ; a 9th death changes nothing
    call    structures_on_mob_killed
    call    total_xp
    cmp     eax, 165
    jne     .fail
    mov     byte [rpg_state + RPGSAVE.level], 10
    mov     dword [rpg_state + RPGSAVE.xp], 0
    call    total_xp
    mov     r12d, eax
    mov     ebx, 8
.eight:
    mov     edi, 2                      ; dungeon 1's mobs
    call    structures_on_mob_killed
    dec     ebx
    jnz     .eight
    test    byte [rpg_state + RPGSAVE.cleared], 2
    jz      .fail
    call    total_xp
    sub     eax, r12d
    cmp     eax, 300
    jne     .fail
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
    call    mobs_clear
    mov     eax, ebx
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

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

; the crypt's boss: nothing wakes while the player is outside, in Creative or on Peaceful; inside
; in Survival one step spawns a single boss (origin 99, level 20 for a level 1 player), more steps
; add none, and once the boss is marked defeated (rpg_state.flags bit 0) none comes back. Then a
; step inside the first dungeon spawns one of its elites (origin 1) at the player's level + 2.
; Frame: [rsp] saved player body, [rsp+72] game_mode, [rsp+76] difficulty.
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
    call    structures_reset
    call    rpg_reset
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    mov     edi, 42
    call    structures_plan
    mov     edi, SITE_CRYPT
    xor     esi, esi
    call    find_site
    test    rax, rax
    jz      .fail
    mov     rbx, rax
    movss   xmm0, [k_half]              ; far from the crypt
    movss   [player + BODY.x], xmm0
    movss   [player + BODY.z], xmm0
    movss   xmm0, [k_10]
    movss   [player + BODY.y], xmm0
    call    structures_step
    mov     edi, MOB_BOSS
    call    mob_count_type
    test    eax, eax
    jnz     .fail
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
    lea     rax, [mobs]                 ; its slot carries the crypt origin
    mov     ecx, MAX_MOBS
.find:
    cmp     dword [rax + MOB.type], MOB_BOSS
    je      .have
    add     rax, MOB_size
    dec     ecx
    jnz     .find
    jmp     .fail
.have:
    cmp     dword [rax + MOB.origin], 99
    jne     .fail
    cmp     dword [rax + MOB.level], 20
    jne     .fail
    call    structures_step             ; once only
    mov     edi, MOB_BOSS
    call    mob_count_type
    cmp     eax, 1
    jne     .fail
    call    mobs_clear                  ; defeated: it stays dead
    or      byte [rpg_state + RPGSAVE.flags], 1
    call    structures_step
    mov     edi, MOB_BOSS
    call    mob_count_type
    test    eax, eax
    jnz     .fail
    call    mobs_clear                  ; a dungeon's spawner, with the player in the dungeon's far
    call    structures_reset            ; south-west corner, 6 or more blocks from every room's middle
    mov     byte [rpg_state + RPGSAVE.level], 4
    mov     edi, SITE_DUNGEON
    xor     esi, esi
    call    find_site
    test    rax, rax
    jz      .fail
    mov     rbx, rax
    cvtsi2ss xmm0, dword [rbx + SITE.x]
    subss   xmm0, [k_6]
    movss   [player + BODY.x], xmm0
    cvtsi2ss xmm0, dword [rbx + SITE.y]
    addss   xmm0, [k_one]
    movss   [player + BODY.y], xmm0
    cvtsi2ss xmm0, dword [rbx + SITE.z]
    addss   xmm0, [k_20]
    movss   [player + BODY.z], xmm0
    call    structures_step
    call    first_mob
    test    rax, rax
    jz      .fail
    cmp     dword [rax + MOB.origin], 1
    jne     .fail
    cmp     dword [rax + MOB.elite], 1
    jne     .fail
    cmp     dword [rax + MOB.level], 6
    jne     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    mobs_clear
    call    rpg_reset
    call    structures_reset
    mov     dword [site_count], 0
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
