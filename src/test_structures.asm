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

section .rodata
align 4
k_one:   dd 1.0
k_half:  dd 0.5
k_3_5:   dd 3.5
k_10:    dd 10.0

section .bss
alignb 16
snap:       resb MAX_SITES * SITE_size  ; the sites of the first plan
snap_count: resd 1

section .text

; zero_conts(): empties the container table in the world header
zero_conts:
    lea     rdi, [world_header + WORLDHDR.containers]
    mov     ecx, MAX_CONTAINERS * CONTAINER_size
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

; chests_in(rdi SITE*) -> eax number of CONT_CHEST containers inside the site's box, each on a
; CHEST block and holding at least one item; -1 when one of them is not
chests_in:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     rbx, rdi
    lea     r12, [world_header + WORLDHDR.containers]
    mov     r13d, MAX_CONTAINERS
    xor     r14d, r14d                  ; chests inside the box
.rec:
    cmp     byte [r12 + CONTAINER.kind], CONT_CHEST
    jne     .rnext
    movzx   eax, byte [r12 + CONTAINER.x]
    cmp     eax, [rbx + SITE.lo_x]
    jl      .rnext
    cmp     eax, [rbx + SITE.hi_x]
    jg      .rnext
    movzx   eax, byte [r12 + CONTAINER.y]
    cmp     eax, [rbx + SITE.lo_y]
    jl      .rnext
    cmp     eax, [rbx + SITE.hi_y]
    jg      .rnext
    movzx   eax, byte [r12 + CONTAINER.z]
    cmp     eax, [rbx + SITE.lo_z]
    jl      .rnext
    cmp     eax, [rbx + SITE.hi_z]
    jg      .rnext
    movzx   edi, byte [r12 + CONTAINER.x]
    movzx   esi, byte [r12 + CONTAINER.y]
    movzx   edx, byte [r12 + CONTAINER.z]
    call    world_get
    cmp     eax, CHEST
    jne     .bad
    xor     r15d, r15d                  ; the first non-empty cell
.cell:
    cmp     byte [r12 + CONTAINER.slots + r15*4 + ITEMSTACK.id], 0
    je      .cnext
    cmp     byte [r12 + CONTAINER.slots + r15*4 + ITEMSTACK.count], 0
    jne     .loot
.cnext:
    inc     r15d
    cmp     r15d, 27
    jb      .cell
    jmp     .bad                        ; an empty chest
.loot:
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
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
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

; world_generate(42): the first dungeon has open rooms, corridor and west opening, a brick west
; wall, four loaded chests, and a stair tunnel with brick floor and open passage that ends in the
; entrance frame; the crypt has an open hall, its pillars and two loaded chests
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
    call    chests_in
    cmp     eax, 4
    jne     .fail
    mov     r15d, 1                     ; tunnel column i: floor at y = 7 + i
.column:
    xor     esi, esi
    xor     ecx, ecx
    call    tun_at
    cmp     eax, STONE_BRICK
    je      .floor
    cmp     eax, MOSSY_STONE_BRICK
    je      .floor
    mov     esi, 4                      ; no floor block: the entrance frame stands here
    xor     ecx, ecx
    call    tun_at
    cmp     eax, MOSSY_STONE_BRICK      ; lintel
    jne     .fail
    mov     esi, 1
    mov     ecx, -2
    call    tun_at
    cmp     eax, MOSSY_STONE_BRICK      ; pillars
    jne     .fail
    mov     esi, 3
    mov     ecx, 2
    call    tun_at
    cmp     eax, MOSSY_STONE_BRICK
    jne     .fail
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
    inc     r15d
    cmp     r15d, 60
    jbe     .column
    jmp     .fail                       ; it never came out of the ground
.tunnel_done:
    mov     edi, SITE_CRYPT
    xor     esi, esi
    call    find_site
    test    rax, rax
    jz      .fail
    mov     rbx, rax
    EXPECT_AIR 0, 7, 0                  ; the hall
    EXPECT_AIR -8, 7, 0                 ; and its west opening
    mov     rdi, rbx                    ; a pillar
    mov     esi, 4
    mov     edx, 8
    mov     ecx, 4
    call    block_at
    cmp     eax, STONE_BRICK
    jne     .fail
    mov     rdi, rbx
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
; glass at the village's middle, and the first house with its cobble floor, plank roof, open door
; (west wall, facing the well) and plank wall opposite it
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
    mov     edi, [rbx + SITE.x]
    add     edi, 7
    mov     esi, [rbx + SITE.y]
    inc     esi
    mov     edx, [rbx + SITE.z]
    call    world_get
    test    eax, eax
    jnz     .fail
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
; sets bit 0 of the cleared mask and awards 150 XP once
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
    cmp     eax, 150
    jne     .fail
    mov     edi, 1                      ; a 9th death changes nothing
    call    structures_on_mob_killed
    call    total_xp
    cmp     eax, 150
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
; in Survival one step spawns a single boss (origin 99), more steps add none, and once the boss
; is marked defeated (rpg_state.flags bit 0) none comes back
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
