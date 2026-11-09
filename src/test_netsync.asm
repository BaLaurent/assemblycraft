; test_netsync.asm - the multiplayer session layer's tests that need no network: a position on the wire is
; absolute (exact to 1/32768 under one origin, the same point under another origin), and a character's image
; (the first PLAYER_IMG_SIZE bytes of a header image) holds the whole character: inventory, armor, jewelry,
; RPG record, health, position, origin and bed.
%include "common.inc"
default rel

global test_net_pos_roundtrip, test_net_player_image_roundtrip

extern net_pos_out, net_pos_in, world_origin_x, world_origin_z
extern game_player_save, game_player_load, game_mode
extern world_header, player, surv, surv_max_health, inv, inv_sel
extern rpg_state, rpg_ext, rpg_reset, rpg_recompute, debug_stat_bonus

section .rodata
align 16
k_abs_mask:   dq 0x7FFFFFFFFFFFFFFF, 0
k_tol:        dq 0.000030517578125              ; 1/32768
k_ulp:        dq 5.9604644775390625e-08         ; 2^-24: half a float32 step is at most |value| times this
align 4
; local positions (x, y, z)
k_pos:
    dd 0.5, 70.0, 0.5
    dd -1000.25, 5.0, 12345.75
    dd 8191.9, 255.0, -8191.9
; origins (x, z)
k_org:
    dd 0, 0
    dd -1024, 512
    dd 1048576, -1048576
m_v6:         db "ACRAFT06"

section .bss
alignb 16
npos:         resb NPOS_size
alignb 16
img_buf:      resb WORLD_HDR_SIZE
bk_hdr:       resb WORLD_HDR_SIZE
bk_player:    resb BODY_size
bk_inv:       resb INVENTORY_size
bk_surv:      resb SURVIVAL_size
bk_rpg:       resb RPGSAVE_size
bk_rpgx:      resb RPGEXT_size
bk_dbg:       resb NUM_STATS * 2
bk_misc:      resd 6                            ; origin x, z, game_mode, inv_sel, surv_max_health

section .text

; rt_one(edi position index, esi origin a, edx origin b) -> eax 0 ok / 1 failed
; The position goes out under origin a and comes back in under origin b: y is exact, and the absolute x and z
; (local plus origin) are the same point to within 1/32768 - under another origin plus half a float32 step of
; the shifted value, the most a float position can hold there.
; r14 = the position, r12d = a, r13d = b
rt_one:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    imul    eax, edi, 12
    lea     r14, [k_pos]
    add     r14, rax
    mov     r12d, esi
    mov     r13d, edx
    lea     rax, [k_org]
    mov     ecx, [rax + r12*8]
    mov     [world_origin_x], ecx
    mov     ecx, [rax + r12*8 + 4]
    mov     [world_origin_z], ecx
    lea     rdi, [npos]
    movss   xmm0, [r14]
    movss   xmm1, [r14 + 4]
    movss   xmm2, [r14 + 8]
    call    net_pos_out
    lea     rax, [k_org]
    mov     ecx, [rax + r13*8]
    mov     [world_origin_x], ecx
    mov     ecx, [rax + r13*8 + 4]
    mov     [world_origin_z], ecx
    lea     rdi, [npos]
    call    net_pos_in                          ; xmm0 x, xmm1 y, xmm2 z
    ucomiss xmm1, [r14 + 4]
    jne     .fail
    jp      .fail
    lea     rax, [k_org]
    cvtss2sd xmm6, xmm0                         ; x2 and z2 as doubles
    cvtss2sd xmm7, xmm2
    movaps  xmm0, xmm6                          ; x: (x2 + origin b) - (x + origin a)
    cvtsi2sd xmm3, dword [rax + r13*8]
    addsd   xmm0, xmm3
    cvtss2sd xmm4, dword [r14]
    cvtsi2sd xmm3, dword [rax + r12*8]
    addsd   xmm4, xmm3
    subsd   xmm0, xmm4
    andpd   xmm0, [k_abs_mask]
    movsd   xmm5, [k_tol]
    cmp     r12d, r13d
    je      .x_tol
    movaps  xmm3, xmm6
    andpd   xmm3, [k_abs_mask]
    mulsd   xmm3, [k_ulp]
    addsd   xmm5, xmm3
.x_tol:
    comisd  xmm0, xmm5
    jae     .fail
    movaps  xmm2, xmm7                          ; the same for z
    cvtsi2sd xmm3, dword [rax + r13*8 + 4]
    addsd   xmm2, xmm3
    cvtss2sd xmm4, dword [r14 + 8]
    cvtsi2sd xmm3, dword [rax + r12*8 + 4]
    addsd   xmm4, xmm3
    subsd   xmm2, xmm4
    andpd   xmm2, [k_abs_mask]
    movsd   xmm5, [k_tol]
    cmp     r12d, r13d
    je      .z_tol
    movaps  xmm3, xmm7
    andpd   xmm3, [k_abs_mask]
    mulsd   xmm3, [k_ulp]
    addsd   xmm5, xmm3
.z_tol:
    comisd  xmm2, xmm5
    jae     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; test_net_pos_roundtrip: every position goes out under every origin and comes in under the same or another one.
; Under the same origin the error stays below 1/32768; across origins the point is the same (rt_one); and the
; NPOS fields are what the wire format says
test_net_pos_roundtrip:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r14d, [world_origin_x]              ; r14 = the caller's origin x (z is on the stack below)
    push    qword [world_origin_z]
    sub     rsp, 8
    xor     ebx, ebx                            ; position
.p:
    xor     r12d, r12d                          ; origin out
.a:
    xor     r13d, r13d                          ; origin in
.b:
.run:
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    call    rt_one
    test    eax, eax
    jnz     .fail
.next:
    inc     r13d
    cmp     r13d, 3
    jb      .b
    inc     r12d
    cmp     r12d, 3
    jb      .a
    inc     ebx
    cmp     ebx, 3
    jb      .p
    ; the fields themselves: (0.5, 70, 0.5) under origin (0, 0)
    mov     dword [world_origin_x], 0
    mov     dword [world_origin_z], 0
    lea     rdi, [npos]
    movss   xmm0, [k_pos]
    movss   xmm1, [k_pos + 4]
    movss   xmm2, [k_pos + 8]
    call    net_pos_out
    cmp     dword [npos + NPOS.ax], 0
    jne     .fail
    cmp     dword [npos + NPOS.az], 0
    jne     .fail
    cmp     word [npos + NPOS.fx], 32768
    jne     .fail
    cmp     word [npos + NPOS.fz], 32768
    jne     .fail
    cmp     dword [npos + NPOS.y], __float32__(70.0)
    jne     .fail
    ; (-1000.25, 5, 12345.75) under origin (-1024, 512): x = -2024.25, z = 12857.75
    mov     dword [world_origin_x], -1024
    mov     dword [world_origin_z], 512
    lea     rdi, [npos]
    movss   xmm0, [k_pos + 12]
    movss   xmm1, [k_pos + 16]
    movss   xmm2, [k_pos + 20]
    call    net_pos_out
    cmp     dword [npos + NPOS.ax], -2025
    jne     .fail
    cmp     dword [npos + NPOS.az], 12857
    jne     .fail
    cmp     word [npos + NPOS.fx], 49152
    jne     .fail
    cmp     word [npos + NPOS.fz], 49152
    jne     .fail
    cmp     dword [npos + NPOS.y], __float32__(5.0)
    jne     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    add     rsp, 8
    pop     rcx
    mov     [world_origin_z], ecx
    mov     [world_origin_x], r14d
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

%macro COPY 3                                   ; COPY dst, src, bytes
    lea     rdi, [%1]
    lea     rsi, [%2]
    mov     ecx, %3
    rep     movsb
%endmacro

%macro WIPE 2                                   ; WIPE dst, bytes
    lea     rdi, [%1]
    mov     ecx, %2
    xor     eax, eax
    rep     stosb
%endmacro

; the character, saved into a header image and loaded back after everything was wiped: inventory, armor, a ring,
; the RPG record (level, XP, quest), health and food, position and angles, hotbar choice, origin and bed. The
; image must not reach past PLAYER_IMG_SIZE bytes.
test_net_player_image_roundtrip:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    COPY    bk_hdr, world_header, WORLD_HDR_SIZE        ; what the test touches, kept
    COPY    bk_player, player, BODY_size
    COPY    bk_inv, inv, INVENTORY_size
    COPY    bk_surv, surv, SURVIVAL_size
    COPY    bk_rpg, rpg_state, RPGSAVE_size
    COPY    bk_rpgx, rpg_ext, RPGEXT_size
    COPY    bk_dbg, debug_stat_bonus, NUM_STATS * 2
    mov     eax, [world_origin_x]
    mov     [bk_misc], eax
    mov     eax, [world_origin_z]
    mov     [bk_misc + 4], eax
    mov     eax, [game_mode]
    mov     [bk_misc + 8], eax
    mov     eax, [inv_sel]
    mov     [bk_misc + 12], eax
    mov     eax, [surv_max_health]
    mov     [bk_misc + 16], eax
    mov     dword [game_mode], MODE_SURVIVAL
    call    rpg_reset
    mov     byte [rpg_state + RPGSAVE.level], 12
    mov     dword [rpg_state + RPGSAVE.xp], 40
    mov     byte [rpg_state + RPGSAVE.quest], 3
    mov     byte [rpg_state + RPGSAVE.quest_state], 1
    mov     word [rpg_state + RPGSAVE.quest_progress], 2
    WIPE    inv, INVENTORY_size
    lea     rax, [inv + INVENTORY.slots + 3*4]
    mov     byte [rax + ITEMSTACK.id], STONE_PICKAXE
    mov     byte [rax + ITEMSTACK.count], 1
    mov     word [rax + ITEMSTACK.dmg], 7
    lea     rax, [inv + INVENTORY.slots + 10*4]
    mov     byte [rax + ITEMSTACK.id], APPLE
    mov     byte [rax + ITEMSTACK.count], 7
    lea     rax, [inv + INVENTORY.armor + 1*4]
    mov     byte [rax + ITEMSTACK.id], IRON_CHESTPLATE
    mov     byte [rax + ITEMSTACK.count], 1
    mov     word [rax + ITEMSTACK.dmg], 3
    lea     rax, [inv + INVENTORY.jewelry + 0*4]        ; a rare ring (rarity 2, tier 3, seed 5)
    mov     byte [rax + ITEMSTACK.id], RING
    mov     byte [rax + ITEMSTACK.count], 1
    mov     word [rax + ITEMSTACK.dmg], 0x8C05
    mov     dword [inv_sel], 4
    call    rpg_recompute
    mov     dword [surv + SURVIVAL.health], 13
    mov     dword [surv + SURVIVAL.food], 11
    mov     dword [surv + SURVIVAL.saturation], __float32__(3.5)
    mov     dword [surv + SURVIVAL.exhaustion], __float32__(0.25)
    mov     dword [surv + SURVIVAL.breath], 400
    mov     dword [world_origin_x], 1024
    mov     dword [world_origin_z], -512
    mov     dword [player + BODY.x], __float32__(12.5)
    mov     dword [player + BODY.y], __float32__(70.0)
    mov     dword [player + BODY.z], __float32__(-3.25)
    mov     dword [player + BODY.yaw], __float32__(90.0)
    mov     dword [player + BODY.pitch], __float32__(10.0)
    mov     dword [world_header + WORLDHDR.bed_x], 1234
    mov     dword [world_header + WORLDHDR.bed_y], 70
    mov     dword [world_header + WORLDHDR.bed_z], -567
    mov     dword [world_header + WORLDHDR.bed_set], 1
    WIPE    img_buf, WORLD_HDR_SIZE
    lea     rdi, [img_buf]
    call    game_player_save
    mov     rax, [m_v6]                                 ; the image is a header image ...
    cmp     [img_buf], rax
    jne     .fail
    xor     ebx, ebx                                    ; ... that ends at PLAYER_IMG_SIZE
.tail:
    cmp     qword [img_buf + PLAYER_IMG_SIZE + rbx*8], 0
    jne     .fail
    inc     ebx
    cmp     ebx, 16
    jb      .tail
    WIPE    player, BODY_size                           ; everything gone
    WIPE    inv, INVENTORY_size
    WIPE    surv, SURVIVAL_size
    WIPE    rpg_state, RPGSAVE_size
    WIPE    rpg_ext, RPGEXT_size
    WIPE    world_header, WORLD_HDR_SIZE
    mov     dword [inv_sel], 0
    mov     dword [world_origin_x], 0
    mov     dword [world_origin_z], 0
    lea     rdi, [img_buf]
    call    game_player_load
    test    eax, eax
    jnz     .fail                                       ; (a live player at a good position: no respawn)
    cmp     dword [world_origin_x], 1024
    jne     .fail
    cmp     dword [world_origin_z], -512
    jne     .fail
    cmp     dword [player + BODY.x], __float32__(12.5)
    jne     .fail
    cmp     dword [player + BODY.y], __float32__(70.0)
    jne     .fail
    cmp     dword [player + BODY.z], __float32__(-3.25)
    jne     .fail
    cmp     dword [player + BODY.yaw], __float32__(90.0)
    jne     .fail
    cmp     dword [player + BODY.pitch], __float32__(10.0)
    jne     .fail
    cmp     dword [inv_sel], 4
    jne     .fail
    lea     rax, [inv + INVENTORY.slots + 3*4]
    cmp     byte [rax + ITEMSTACK.id], STONE_PICKAXE
    jne     .fail
    cmp     byte [rax + ITEMSTACK.count], 1
    jne     .fail
    cmp     word [rax + ITEMSTACK.dmg], 7
    jne     .fail
    lea     rax, [inv + INVENTORY.slots + 10*4]
    cmp     byte [rax + ITEMSTACK.id], APPLE
    jne     .fail
    cmp     byte [rax + ITEMSTACK.count], 7
    jne     .fail
    lea     rax, [inv + INVENTORY.armor + 1*4]
    cmp     byte [rax + ITEMSTACK.id], IRON_CHESTPLATE
    jne     .fail
    cmp     word [rax + ITEMSTACK.dmg], 3
    jne     .fail
    lea     rax, [inv + INVENTORY.jewelry + 0*4]
    cmp     byte [rax + ITEMSTACK.id], RING
    jne     .fail
    cmp     word [rax + ITEMSTACK.dmg], 0x8C05
    jne     .fail
    cmp     byte [rpg_state + RPGSAVE.level], 12
    jne     .fail
    cmp     dword [rpg_state + RPGSAVE.xp], 40
    jne     .fail
    cmp     byte [rpg_state + RPGSAVE.quest], 3
    jne     .fail
    cmp     byte [rpg_state + RPGSAVE.quest_state], 1
    jne     .fail
    cmp     word [rpg_state + RPGSAVE.quest_progress], 2
    jne     .fail
    cmp     dword [surv + SURVIVAL.health], 13
    jne     .fail
    cmp     dword [surv + SURVIVAL.food], 11
    jne     .fail
    cmp     dword [surv + SURVIVAL.breath], 400
    jne     .fail
    cmp     dword [world_header + WORLDHDR.bed_x], 1234
    jne     .fail
    cmp     dword [world_header + WORLDHDR.bed_y], 70
    jne     .fail
    cmp     dword [world_header + WORLDHDR.bed_z], -567
    jne     .fail
    cmp     dword [world_header + WORLDHDR.bed_set], 1
    jne     .fail
    xor     ebx, ebx
    jmp     .restore
.fail:
    mov     ebx, 1
.restore:
    COPY    world_header, bk_hdr, WORLD_HDR_SIZE
    COPY    player, bk_player, BODY_size
    COPY    inv, bk_inv, INVENTORY_size
    COPY    surv, bk_surv, SURVIVAL_size
    COPY    rpg_state, bk_rpg, RPGSAVE_size
    COPY    rpg_ext, bk_rpgx, RPGEXT_size
    COPY    debug_stat_bonus, bk_dbg, NUM_STATS * 2
    mov     eax, [bk_misc]
    mov     [world_origin_x], eax
    mov     eax, [bk_misc + 4]
    mov     [world_origin_z], eax
    mov     eax, [bk_misc + 8]
    mov     [game_mode], eax
    mov     eax, [bk_misc + 12]
    mov     [inv_sel], eax
    call    rpg_recompute                               ; the derived stats follow the restored record
    mov     eax, [bk_misc + 16]
    mov     [surv_max_health], eax
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret
