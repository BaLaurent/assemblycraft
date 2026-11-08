; test_game.asm - a whole session through a 0.9 world directory (the header image keeps the character,
; the origin, the breath, the bed and the site records; a bad world.hdr changes nothing; a dead
; player comes back at the world spawn; a new world's player stands on the surface once the area is
; ready and its animals take the new character's level), the floating-origin rebase trigger, and the
; hook that clears out what stood in a column that unloads.
%include "common.inc"
default rel

global test_game_save_load_roundtrip, test_game_rebase_trigger

extern world_clear, world_header, world_set, rng_seed, game_new, game_save, game_load, game_rebase
extern game_on_area_ready, game_unload_box, game_time, game_mode, game_target, game_has_target
extern game_open_npc, app_state, input_captured
extern brk_x, brk_y, brk_z, world_origin_x, world_origin_z
extern surv, inv, player, mobs, mobs_clear, mob_count_type, mob_spawn, rpg_state
extern str_eq, str_copy, file_read, file_write_atomic, mkdir_p, dir_remove_tree

section .rodata
align 4
k_pig_x:  dd 10.5
k_pig_y:  dd 20.0
k_pig_z1: dd 10.5
k_pig_z2: dd 14.5
k_half:   dd 0.5
k_edge:   dd 63.5                       ; floor 63: the last column of the box 48..63
k_over:   dd 64.5                       ; one past it
k_row:    dd 48.5                       ; floor 48: its first row
d_world_str: db "/tmp/assemblycraft-selftest-game", 0
d_regions: db "/tmp/assemblycraft-selftest-game/regions", 0
d_missing: db "/tmp/assemblycraft-selftest-game-missing", 0
p_hdr:    db "/tmp/assemblycraft-selftest-game/world.hdr", 0
name_rt:  db "Round Trip", 0
name_x:   db "x", 0

section .bss
dir_buf:  resb 128
d_world:  resb 64
file_buf: resb WORLD_HDR_SIZE + 16

section .text

; spawn_pigs() -> eax pigs alive: two pigs at fixed spots (local cells well inside every bound)
spawn_pigs:
    push    rbp
    mov     rbp, rsp
    mov     edi, MOB_PIG
    movss   xmm0, [k_pig_x]
    movss   xmm1, [k_pig_y]
    movss   xmm2, [k_pig_z1]
    call    mob_spawn
    mov     edi, MOB_PIG
    movss   xmm0, [k_pig_x]
    movss   xmm1, [k_pig_y]
    movss   xmm2, [k_pig_z2]
    call    mob_spawn
    mov     edi, MOB_PIG
    call    mob_count_type
    pop     rbp
    ret

test_game_save_load_roundtrip:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    mov     edi, 7
    call    rng_seed
    lea     rdi, [d_world]              ; the world directory path, in memory a callee may write to
    lea     rsi, [d_world_str]
    mov     edx, 63
    call    str_copy
    lea     rdi, [d_world]              ; a clean world directory with its regions/
    call    dir_remove_tree
    lea     rdi, [dir_buf]
    lea     rsi, [d_regions]
    mov     edx, 127
    call    str_copy
    lea     rdi, [dir_buf]
    call    mkdir_p
    test    eax, eax
    jnz     .fail
    mov     edi, 42
    mov     esi, MODE_SURVIVAL
    lea     rdx, [name_rt]
    lea     rcx, [d_world]
    call    game_new
    mov     dword [surv + SURVIVAL.health], 45      ; above the bare 20: the amulet's +33 holds it
    mov     dword [surv + SURVIVAL.food], 9
    mov     dword [surv + SURVIVAL.breath], 321
    lea     rax, [inv + INVENTORY.slots + 3*4]
    mov     byte [rax + ITEMSTACK.id], STONE_PICKAXE
    mov     byte [rax + ITEMSTACK.count], 1
    mov     word [rax + ITEMSTACK.dmg], 7
    lea     rax, [inv + INVENTORY.armor + 1*4]
    mov     byte [rax + ITEMSTACK.id], IRON_CHESTPLATE
    mov     byte [rax + ITEMSTACK.count], 1
    mov     word [rax + ITEMSTACK.dmg], 3
    lea     rax, [inv + INVENTORY.jewelry + 0*4]    ; a rare ring (rarity 2, tier 3, seed 5) ...
    mov     byte [rax + ITEMSTACK.id], RING
    mov     byte [rax + ITEMSTACK.count], 1
    mov     word [rax + ITEMSTACK.dmg], 0x8C05
    lea     rax, [inv + INVENTORY.jewelry + 2*4]    ; ... an amulet in the third cell ...
    mov     byte [rax + ITEMSTACK.id], AMULET
    mov     byte [rax + ITEMSTACK.count], 1
    mov     word [rax + ITEMSTACK.dmg], 0xFC01      ; epic, tier 15, seed 1: +33 max health
    lea     rax, [inv + INVENTORY.jewelry + 1*4]    ; ... and a sword in the second, which a load must drop
    mov     byte [rax + ITEMSTACK.id], IRON_SWORD
    mov     byte [rax + ITEMSTACK.count], 1
    ; what the header image itself carries: a bed and two site records
    mov     dword [world_header + WORLDHDR.bed_x], 1234
    mov     dword [world_header + WORLDHDR.bed_y], 70
    mov     dword [world_header + WORLDHDR.bed_z], -567
    mov     dword [world_header + WORLDHDR.bed_set], 1
    mov     dword [world_header + WORLDHDR.site_count], 2
    mov     dword [world_header + WORLDHDR.sites + SITESTATE.rx], 5
    mov     dword [world_header + WORLDHDR.sites + SITESTATE.rz], -3
    mov     byte [world_header + WORLDHDR.sites + SITESTATE.slot], 1
    mov     byte [world_header + WORLDHDR.sites + SITESTATE.kind], SITE_DUNGEON
    mov     byte [world_header + WORLDHDR.sites + SITESTATE.kills], 3
    mov     byte [world_header + WORLDHDR.sites + SITESTATE.flags], 0
    mov     dword [world_header + WORLDHDR.sites + SITESTATE_size + SITESTATE.rx], -1
    mov     dword [world_header + WORLDHDR.sites + SITESTATE_size + SITESTATE.rz], 0
    mov     byte [world_header + WORLDHDR.sites + SITESTATE_size + SITESTATE.slot], 0
    mov     byte [world_header + WORLDHDR.sites + SITESTATE_size + SITESTATE.kind], SITE_CRYPT
    mov     byte [world_header + WORLDHDR.sites + SITESTATE_size + SITESTATE.kills], 0
    mov     byte [world_header + WORLDHDR.sites + SITESTATE_size + SITESTATE.flags], SS_CLEARED
    mov     dword [world_origin_x], 1024            ; the origin away from 0, the player in local cells
    mov     dword [world_origin_z], -512
    mov     dword [player + BODY.x], __float32__(100.5)
    mov     dword [player + BODY.y], __float32__(70.0)
    mov     dword [player + BODY.z], __float32__(-20.25)
    mov     dword [game_time], 12345
    call    spawn_pigs
    mov     ebx, eax
    lea     rdi, [d_world]
    call    game_save
    test    eax, eax
    jnz     .fail
    lea     rdi, [p_hdr]                            ; world.hdr is one whole v6 header
    lea     rsi, [file_buf]
    mov     edx, WORLD_HDR_SIZE + 16
    call    file_read
    cmp     rax, WORLD_HDR_SIZE
    jne     .fail
    mov     rax, "ACRAFT06"
    cmp     [file_buf], rax
    jne     .fail
    mov     byte [rpg_state + RPGSAVE.level], 30    ; a strong character in the session...
    mov     edi, 1
    mov     esi, MODE_CREATIVE
    lea     rdx, [name_x]
    xor     ecx, ecx
    call    game_new
    cmp     byte [rpg_state + RPGSAVE.level], 1     ; ...does not leak into a new world: the character
    jne     .fail                                   ; is fresh, and so are the animals that come with the area
    call    world_clear                             ; the terrain the area wait would have left: ground at (8, 30, 8)
    mov     edi, 8
    mov     esi, 30
    mov     edx, 8
    mov     ecx, STONE
    call    world_set
    mov     dword [player + BODY.x], __float32__(8.5)
    mov     dword [player + BODY.y], __float32__(99.0)
    mov     dword [player + BODY.z], __float32__(8.5)
    call    game_on_area_ready                      ; a new world: the player stands on the surface ...
    test    eax, eax
    jnz     .fail
    cmp     dword [player + BODY.y], __float32__(31.0)
    jne     .fail
    mov     dword [player + BODY.y], __float32__(99.0)
    call    game_on_area_ready                      ; ... once
    cmp     dword [player + BODY.y], __float32__(99.0)
    jne     .fail
    lea     rax, [mobs]
    mov     ecx, MAX_MOBS
.new_mob:
    cmp     dword [rax + MOB.type], MOB_NONE
    je      .new_next
    cmp     dword [rax + MOB.level], 1
    jne     .fail
.new_next:
    add     rax, MOB_size
    dec     ecx
    jnz     .new_mob
    cmp     dword [world_header + WORLDHDR.bed_set], 0      ; nor does the old world's bed or sites
    jne     .fail
    cmp     dword [world_header + WORLDHDR.site_count], 0
    jne     .fail
    lea     rdi, [d_world]
    call    game_load
    test    eax, eax
    jnz     .fail
    cmp     dword [surv + SURVIVAL.health], 45
    jne     .fail
    cmp     dword [surv + SURVIVAL.food], 9
    jne     .fail
    cmp     dword [surv + SURVIVAL.breath], 321
    jne     .fail
    lea     rax, [inv + INVENTORY.slots + 3*4]
    cmp     byte [rax + ITEMSTACK.id], STONE_PICKAXE
    jne     .fail
    cmp     byte [rax + ITEMSTACK.count], 1
    jne     .fail
    cmp     word [rax + ITEMSTACK.dmg], 7
    jne     .fail
    lea     rax, [inv + INVENTORY.armor + 1*4]
    cmp     byte [rax + ITEMSTACK.id], IRON_CHESTPLATE
    jne     .fail
    cmp     byte [rax + ITEMSTACK.count], 1
    jne     .fail
    cmp     word [rax + ITEMSTACK.dmg], 3
    jne     .fail
    lea     rax, [inv + INVENTORY.jewelry + 0*4]
    cmp     byte [rax + ITEMSTACK.id], RING
    jne     .fail
    cmp     byte [rax + ITEMSTACK.count], 1
    jne     .fail
    cmp     word [rax + ITEMSTACK.dmg], 0x8C05
    jne     .fail
    lea     rax, [inv + INVENTORY.jewelry + 2*4]
    cmp     byte [rax + ITEMSTACK.id], AMULET
    jne     .fail
    cmp     word [rax + ITEMSTACK.dmg], 0xFC01
    jne     .fail
    lea     rax, [inv + INVENTORY.jewelry + 1*4]
    cmp     byte [rax + ITEMSTACK.count], 0
    jne     .fail
    cmp     dword [world_header + WORLDHDR.bed_x], 1234     ; the header image came back whole
    jne     .fail
    cmp     dword [world_header + WORLDHDR.bed_y], 70
    jne     .fail
    cmp     dword [world_header + WORLDHDR.bed_z], -567
    jne     .fail
    cmp     dword [world_header + WORLDHDR.bed_set], 1
    jne     .fail
    cmp     dword [world_header + WORLDHDR.site_count], 2
    jne     .fail
    cmp     dword [world_header + WORLDHDR.sites + SITESTATE.rx], 5
    jne     .fail
    cmp     dword [world_header + WORLDHDR.sites + SITESTATE.rz], -3
    jne     .fail
    cmp     byte [world_header + WORLDHDR.sites + SITESTATE.kills], 3
    jne     .fail
    cmp     byte [world_header + WORLDHDR.sites + SITESTATE_size + SITESTATE.kind], SITE_CRYPT
    jne     .fail
    cmp     byte [world_header + WORLDHDR.sites + SITESTATE_size + SITESTATE.flags], SS_CLEARED
    jne     .fail
    cmp     dword [world_origin_x], 1024                    ; the origin and the local position
    jne     .fail
    cmp     dword [world_origin_z], -512
    jne     .fail
    cmp     dword [player + BODY.x], __float32__(100.5)
    jne     .fail
    cmp     dword [player + BODY.y], __float32__(70.0)
    jne     .fail
    cmp     dword [player + BODY.z], __float32__(-20.25)
    jne     .fail
    cmp     dword [game_time], 12345
    jne     .fail
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .fail
    mov     edi, MOB_PIG
    call    mob_count_type
    cmp     eax, ebx
    jne     .fail
    lea     rdi, [world_header + WORLDHDR.name]
    lea     rsi, [name_rt]
    call    str_eq
    test    eax, eax
    jz      .fail
    ; a bad world.hdr is refused and leaves the session alone
    mov     dword [game_time], 777
    lea     rdi, [d_missing]                        ; no such world: 1
    call    game_load
    cmp     eax, 1
    jne     .fail
    cmp     dword [game_time], 777
    jne     .fail
    lea     rdi, [file_buf]                         ; a header cut short: 2
    mov     ecx, WORLD_HDR_SIZE / 8
    xor     eax, eax
    rep     stosq
    lea     rdi, [p_hdr]
    lea     rsi, [file_buf]
    mov     edx, 100
    call    file_write_atomic
    lea     rdi, [d_world]
    call    game_load
    cmp     eax, 2
    jne     .fail
    mov     rax, "ACRAFT05"                         ; a whole header of another version: 2
    mov     [file_buf], rax
    lea     rdi, [p_hdr]
    lea     rsi, [file_buf]
    mov     edx, WORLD_HDR_SIZE
    call    file_write_atomic
    lea     rdi, [d_world]
    call    game_load
    cmp     eax, 2
    jne     .fail
    cmp     dword [game_time], 777
    jne     .fail
    ; the player died (health 0 saved): the next load brings him back at the world spawn, with the
    ; origin in the spawn's 512-block cell and the player in the middle of the spawn cell
    mov     dword [surv + SURVIVAL.health], 0
    mov     dword [world_header + WORLDHDR.bed_set], 0      ; no bed: the world spawn is the target
    lea     rdi, [d_world]
    call    game_save
    test    eax, eax
    jnz     .fail
    lea     rdi, [d_world]
    call    game_load
    test    eax, eax
    jnz     .fail
    cmp     dword [surv + SURVIVAL.health], 0
    je      .fail
    mov     eax, [world_header + WORLDHDR.spawn_x]
    and     eax, -REBASE_STEP
    cmp     [world_origin_x], eax
    jne     .fail
    mov     eax, [world_header + WORLDHDR.spawn_z]
    and     eax, -REBASE_STEP
    cmp     [world_origin_z], eax
    jne     .fail
    movss   xmm0, [player + BODY.x]
    subss   xmm0, [k_half]
    cvttss2si eax, xmm0
    add     eax, [world_origin_x]
    cmp     eax, [world_header + WORLDHDR.spawn_x]
    jne     .fail
    movss   xmm0, [player + BODY.z]
    subss   xmm0, [k_half]
    cvttss2si eax, xmm0
    add     eax, [world_origin_z]
    cmp     eax, [world_header + WORLDHDR.spawn_z]
    jne     .fail
    xor     ebx, ebx
    jmp     .done
.fail:
    mov     ebx, 1
.done:
    call    game_on_area_ready                      ; no pending respawn left behind
    lea     rdi, [d_world]
    call    dir_remove_tree
    mov     dword [world_origin_x], 0
    mov     dword [world_origin_z], 0
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; game_rebase: past 1024 blocks from the local origin on an axis, the origin moves by a multiple of
; 512 (the player's floored cell) and everything follows; an axis within bounds is left alone
test_game_rebase_trigger:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    mov     dword [world_origin_x], 0
    mov     dword [world_origin_z], 0
    mov     dword [player + BODY.x], __float32__(1030.25)
    mov     dword [player + BODY.y], __float32__(70.0)
    mov     dword [player + BODY.z], __float32__(-2050.5)
    mov     dword [game_has_target], 1
    mov     dword [game_target + RAYHIT.bx], 1040
    mov     dword [game_target + RAYHIT.by], 69
    mov     dword [game_target + RAYHIT.bz], -2040
    mov     dword [game_target + RAYHIT.px], 1041
    mov     dword [game_target + RAYHIT.py], 69
    mov     dword [game_target + RAYHIT.pz], -2041
    mov     dword [brk_x], 1040                     ; a block being dug
    mov     dword [brk_y], 69
    mov     dword [brk_z], -2040
    call    game_rebase
    cmp     dword [world_origin_x], 1024            ; floor(1030.25) sar 9 shl 9
    jne     .fail
    cmp     dword [world_origin_z], -2560           ; floor(-2050.5) = -2051: -5 * 512
    jne     .fail
    cmp     dword [player + BODY.x], __float32__(6.25)
    jne     .fail
    cmp     dword [player + BODY.y], __float32__(70.0)
    jne     .fail
    cmp     dword [player + BODY.z], __float32__(509.5)
    jne     .fail
    cmp     dword [game_target + RAYHIT.bx], 16
    jne     .fail
    cmp     dword [game_target + RAYHIT.by], 69
    jne     .fail
    cmp     dword [game_target + RAYHIT.bz], 520
    jne     .fail
    cmp     dword [game_target + RAYHIT.px], 17
    jne     .fail
    cmp     dword [game_target + RAYHIT.pz], 519
    jne     .fail
    cmp     dword [brk_x], 16
    jne     .fail
    cmp     dword [brk_z], 520
    jne     .fail
    call    game_rebase                             ; now within bounds on both axes: nothing moves
    cmp     dword [world_origin_x], 1024
    jne     .fail
    cmp     dword [world_origin_z], -2560
    jne     .fail
    cmp     dword [player + BODY.x], __float32__(6.25)
    jne     .fail
    cmp     dword [player + BODY.z], __float32__(509.5)
    jne     .fail
    mov     dword [player + BODY.x], __float32__(-1100.5)   ; one axis out, the other at 700: that one stays
    mov     dword [player + BODY.z], __float32__(700.25)
    mov     dword [brk_y], -1                       ; no dig under way: its cell is left alone
    mov     dword [brk_x], 5
    mov     dword [brk_z], 5
    call    game_rebase
    cmp     dword [world_origin_x], -512            ; 1024 + (floor(-1100.5) = -1101 -> -1536)
    jne     .fail
    cmp     dword [world_origin_z], -2560
    jne     .fail
    cmp     dword [player + BODY.x], __float32__(435.5)
    jne     .fail
    cmp     dword [player + BODY.z], __float32__(700.25)
    jne     .fail
    cmp     dword [brk_x], 5
    jne     .fail
    cmp     dword [brk_z], 5
    jne     .fail
    ; the hook for a column that goes away: what stands in the box leaves; an NPC screen open on a
    ; villager inside it closes first, one open on a villager outside stays
    call    mobs_clear
    mov     edi, MOB_PIG
    movss   xmm0, [k_edge]
    movss   xmm1, [k_pig_y]
    movss   xmm2, [k_row]
    call    mob_spawn                               ; inside, on the box's last column and first row
    test    eax, eax
    js      .fail
    mov     [rsp], eax
    mov     edi, MOB_PIG
    movss   xmm0, [k_over]
    movss   xmm1, [k_pig_y]
    movss   xmm2, [k_row]
    call    mob_spawn                               ; outside, one column further
    test    eax, eax
    js      .fail
    mov     [rsp + 4], eax
    mov     dword [input_captured], 1               ; the cursor is captured: app_goto leaves GLFW alone
    mov     dword [app_state], ST_TRADE
    mov     eax, [rsp + 4]
    mov     [game_open_npc], eax
    mov     edi, 48
    mov     esi, 48
    mov     edx, 63
    mov     ecx, 63
    call    game_unload_box
    cmp     dword [app_state], ST_TRADE             ; the screen's villager is outside: it stays open
    jne     .fail
    lea     rcx, [mobs]
    mov     eax, [rsp]
    imul    eax, eax, MOB_size
    cmp     dword [rcx + rax + MOB.type], MOB_NONE  ; the pig inside is gone
    jne     .fail
    mov     eax, [rsp + 4]
    imul    eax, eax, MOB_size
    cmp     dword [rcx + rax + MOB.type], MOB_PIG   ; the one outside is not
    jne     .fail
    mov     edi, MOB_PIG
    movss   xmm0, [k_edge]
    movss   xmm1, [k_pig_y]
    movss   xmm2, [k_row]
    call    mob_spawn                               ; a villager inside, with its screen open
    test    eax, eax
    js      .fail
    mov     [game_open_npc], eax
    mov     edi, 48
    mov     esi, 48
    mov     edx, 63
    mov     ecx, 63
    call    game_unload_box
    cmp     dword [app_state], ST_PLAYING           ; back in the game
    jne     .fail
    xor     ebx, ebx
    jmp     .done
.fail:
    mov     ebx, 1
.done:
    call    mobs_clear
    mov     dword [app_state], ST_TITLE
    mov     dword [input_captured], 0
    mov     dword [game_open_npc], 0
    mov     dword [world_origin_x], 0
    mov     dword [world_origin_z], 0
    mov     dword [game_has_target], 0
    mov     dword [brk_y], -1
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret
