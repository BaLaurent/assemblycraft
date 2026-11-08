; test_game.asm - whole-session save/load round trip (gear-granted health survives a load; a new
; world's animals take the new character's level, not the previous one's).
%include "common.inc"
default rel

global test_game_save_load_roundtrip

extern world_clear, world_header, rng_seed, game_new, game_save, game_load
extern game_time, game_mode, surv, inv, mob_count_type, str_eq, file_unlink
extern world_set, cont_create, cont_at, rpg_state, mobs

section .rodata
path:     db "/tmp/assemblycraft-selftest-game.acw", 0
name_rt:  db "Round Trip", 0
name_x:   db "x", 0

section .text

test_game_save_load_roundtrip:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    mov     edi, 7
    call    rng_seed
    mov     edi, 42
    mov     esi, MODE_SURVIVAL
    lea     rdx, [name_rt]
    call    game_new
    mov     dword [surv + SURVIVAL.health], 45      ; above the bare 20: the amulet's +33 holds it
    mov     dword [surv + SURVIVAL.food], 9
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
    mov     edi, 128
    mov     esi, 60
    mov     edx, 128
    mov     ecx, CHEST
    call    world_set
    mov     edi, 128
    mov     esi, 60
    mov     edx, 128
    mov     ecx, CONT_CHEST
    call    cont_create
    test    rax, rax
    jz      .fail
    mov     byte [rax + CONTAINER.slots + 5*4 + ITEMSTACK.id], COAL
    mov     byte [rax + CONTAINER.slots + 5*4 + ITEMSTACK.count], 7
    mov     dword [game_time], 12345
    mov     edi, MOB_PIG
    call    mob_count_type
    mov     ebx, eax
    lea     rdi, [path]
    call    game_save
    test    eax, eax
    jnz     .fail
    mov     byte [rpg_state + RPGSAVE.level], 30    ; a strong character in the session...
    mov     edi, 1
    mov     esi, MODE_CREATIVE
    lea     rdx, [name_x]
    call    game_new
    lea     rax, [mobs]                             ; ...does not leak its level into a new world
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
    lea     rdi, [path]
    call    game_load
    test    eax, eax
    jnz     .fail
    cmp     dword [surv + SURVIVAL.health], 45
    jne     .fail
    cmp     dword [surv + SURVIVAL.food], 9
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
    mov     edi, 128
    mov     esi, 60
    mov     edx, 128
    call    cont_at
    test    rax, rax
    jz      .fail
    cmp     byte [rax + CONTAINER.slots + 5*4 + ITEMSTACK.id], COAL
    jne     .fail
    cmp     byte [rax + CONTAINER.slots + 5*4 + ITEMSTACK.count], 7
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
    lea     rdi, [path]
    call    file_unlink
    xor     eax, eax
    jmp     .ret
.fail:
    lea     rdi, [path]
    call    file_unlink
    mov     eax, 1
.ret:
    mov     ebx, eax                    ; leave no container records to later tests
    lea     rdi, [world_header + WORLDHDR.containers_v5]
    mov     ecx, MAX_CONTAINERS_V5 * CONTAINER_size
    xor     eax, eax
    rep     stosb
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret
