; game.asm - hotbar, block interaction, fixed-step simulation, world file glue.
%include "common.inc"
default rel

global hotbar, hotbar_sel, game_target, game_has_target, game_mode, game_time
global game_new, game_load, game_save, game_frame

extern world_header, world_get, world_set, world_load, world_save, world_generate, world_top_y
extern player, player_spawn, body_step, player_look, player_eye, player_forward
extern body_intersects_block, raycast, frame_input

section .rodata
default_hotbar: db STONE, DIRT, GRASS, COBBLE, PLANKS, LOG, LEAVES, GLASS, BRICK
align 4
step_dt:    dd 0.016666668
repeat_dt:  dd 0.25
reach:      dd 5.0

section .data
align 4
game_mode: dd MODE_CREATIVE
game_time: dd NEW_WORLD_TIME

section .bss
hotbar:          resb HOTBAR_SLOTS
alignb 4
hotbar_sel:      resd 1
game_target:     resb RAYHIT_size
game_has_target: resd 1
step_accum:      resd 1
break_timer:     resd 1
place_timer:     resd 1

section .text

; reset_session(): default hotbar, slot 0, timers cleared
reset_session:
    mov     rax, [default_hotbar]
    mov     [hotbar], rax
    mov     al, [default_hotbar + 8]
    mov     [hotbar + 8], al
    xor     eax, eax
    mov     [hotbar_sel], eax
    mov     [step_accum], eax
    mov     [break_timer], eax
    mov     [place_timer], eax
    mov     [game_has_target], eax
    ret

; game_new(edi seed)
game_new:
    push    rbp
    mov     rbp, rsp
    call    world_generate
    mov     edi, 128
    mov     esi, 128
    call    world_top_y
    inc     eax
    mov     dword [world_header + WORLDHDR.spawn_x], 128
    mov     [world_header + WORLDHDR.spawn_y], eax
    mov     dword [world_header + WORLDHDR.spawn_z], 128
    mov     dword [world_header + WORLDHDR.mode], MODE_CREATIVE
    mov     dword [world_header + WORLDHDR.time], NEW_WORLD_TIME
    call    player_spawn
    call    reset_session
    pop     rbp
    ret

; game_load(rdi path) -> eax as world_load
game_load:
    push    rbp
    mov     rbp, rsp
    call    world_load
    test    eax, eax
    jnz     .ret
    call    reset_session
    lea     rsi, [world_header + WORLDHDR.player]
    lea     rdi, [player]
    mov     ecx, BODY_size
    rep     movsb
    xor     eax, eax
    mov     [player + BODY.vx], eax
    mov     [player + BODY.vy], eax
    mov     [player + BODY.vz], eax
    mov     [player + BODY.on_ground], eax
    mov     [player + BODY.kbx], eax
    mov     [player + BODY.kbz], eax
    mov     [player + BODY.fall], eax
    mov     [player + BODY.blocked], eax
    mov     dword [player + BODY.half_w], __float32__(0.3)
    mov     dword [player + BODY.height], __float32__(1.8)
    mov     dword [player + BODY.speed], __float32__(4.317)
    and     dword [player + BODY.flying], 1
    lea     rsi, [world_header]
    xor     ecx, ecx
.slot:
    movzx   eax, byte [rsi + WORLDHDR.inventory + rcx*4 + ITEMSTACK.id]
    test    eax, eax
    jz      .keep_default
    cmp     eax, NUM_BLOCKS
    jae     .keep_default
    mov     [hotbar + rcx], al
.keep_default:
    inc     ecx
    cmp     ecx, HOTBAR_SLOTS
    jb      .slot
    mov     eax, [rsi + WORLDHDR.sel]
    cmp     eax, HOTBAR_SLOTS
    jb      .sel_ok
    xor     eax, eax
.sel_ok:
    mov     [hotbar_sel], eax
    xor     eax, eax
.ret:
    pop     rbp
    ret

; game_save(rdi path) -> eax as world_save
game_save:
    push    rdi
    lea     rsi, [player]
    lea     rdi, [world_header + WORLDHDR.player]
    mov     ecx, BODY_size
    rep     movsb
    pop     rdi
    lea     rsi, [world_header]
    mov     eax, [hotbar_sel]
    mov     [rsi + WORLDHDR.sel], eax
    xor     ecx, ecx
.slot:
    movzx   eax, byte [hotbar + rcx]
    mov     [rsi + WORLDHDR.inventory + rcx*4 + ITEMSTACK.id], al
    mov     byte [rsi + WORLDHDR.inventory + rcx*4 + ITEMSTACK.count], 1
    mov     word [rsi + WORLDHDR.inventory + rcx*4 + ITEMSTACK.dmg], 0
    inc     ecx
    cmp     ecx, HOTBAR_SLOTS
    jb      .slot
    jmp     world_save

; repeat_fire(edi held, esi pressed, rdx float* timer, xmm0 dt) -> eax fire
; Fires on press, then every 0.25 s while held; the timer is zeroed on release.
repeat_fire:
    test    esi, esi
    jz      .not_pressed
    movss   xmm1, [repeat_dt]
    movss   [rdx], xmm1
    mov     eax, 1
    ret
.not_pressed:
    test    edi, edi
    jz      .released
    movss   xmm1, [rdx]
    subss   xmm1, xmm0
    xorps   xmm2, xmm2
    xor     eax, eax
    comiss  xmm1, xmm2
    ja      .store
    addss   xmm1, [repeat_dt]
    mov     eax, 1
.store:
    movss   [rdx], xmm1
    ret
.released:
    mov     dword [rdx], 0
    xor     eax, eax
    ret

; game_frame(xmm0 float dt)
game_frame:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 48                     ; [rsp] eye[3], [rsp+12] dir[3], [rsp+32] dt
    movss   [rsp + 32], xmm0

    ; 1. hotbar slot: number key, then wheel (wheel up = previous slot)
    mov     eax, [frame_input + FRAMEINPUT.slot]
    test    eax, eax
    js      .no_slot
    mov     [hotbar_sel], eax
.no_slot:
    mov     eax, [hotbar_sel]
    sub     eax, [frame_input + FRAMEINPUT.scroll]
    cdq
    mov     ecx, HOTBAR_SLOTS
    idiv    ecx
    test    edx, edx
    jns     .sel_pos
    add     edx, HOTBAR_SLOTS
.sel_pos:
    mov     [hotbar_sel], edx

    ; 2. fly toggle
    cmp     dword [frame_input + FRAMEINPUT.toggle_fly], 0
    je      .no_fly
    xor     dword [player + BODY.flying], 1
    mov     dword [player + BODY.vy], 0
.no_fly:

    ; 3. look
    movss   xmm0, [frame_input + FRAMEINPUT.look_dx]
    movss   xmm1, [frame_input + FRAMEINPUT.look_dy]
    call    player_look

    ; 4. fixed 1/60 s steps, at most 5 per frame
    movss   xmm0, [step_accum]
    addss   xmm0, [rsp + 32]
    movss   [step_accum], xmm0
    xor     ebx, ebx
.step:
    movss   xmm0, [step_accum]
    comiss  xmm0, [step_dt]
    jb      .steps_done
    cmp     ebx, 5
    jae     .steps_capped
    lea     rdi, [player]
    lea     rsi, [frame_input + FRAMEINPUT.move]
    call    body_step
    movss   xmm0, [step_accum]
    subss   xmm0, [step_dt]
    movss   [step_accum], xmm0
    inc     ebx
    jmp     .step
.steps_capped:
    mov     dword [step_accum], 0
.steps_done:

    ; 5. target block
    mov     rdi, rsp
    call    player_eye
    lea     rdi, [rsp + 12]
    call    player_forward
    mov     rdi, rsp
    lea     rsi, [rsp + 12]
    lea     rdx, [game_target]
    movss   xmm0, [reach]
    call    raycast
    mov     [game_has_target], eax

    ; 6. break
    mov     edi, [frame_input + FRAMEINPUT.lmb_held]
    mov     esi, [frame_input + FRAMEINPUT.lmb_pressed]
    lea     rdx, [break_timer]
    movss   xmm0, [rsp + 32]
    call    repeat_fire
    test    eax, eax
    jz      .no_break
    cmp     dword [game_has_target], 0
    je      .no_break
    mov     edi, [game_target + RAYHIT.bx]
    mov     esi, [game_target + RAYHIT.by]
    mov     edx, [game_target + RAYHIT.bz]
    call    world_get
    cmp     eax, BEDROCK
    je      .no_break
    mov     edi, [game_target + RAYHIT.bx]
    mov     esi, [game_target + RAYHIT.by]
    mov     edx, [game_target + RAYHIT.bz]
    mov     ecx, AIR
    call    world_set
.no_break:

    ; 7. place
    mov     edi, [frame_input + FRAMEINPUT.rmb_held]
    mov     esi, [frame_input + FRAMEINPUT.rmb_pressed]
    lea     rdx, [place_timer]
    movss   xmm0, [rsp + 32]
    call    repeat_fire
    test    eax, eax
    jz      .no_place
    cmp     dword [game_has_target], 0
    je      .no_place
    cmp     dword [game_target + RAYHIT.px], WORLD_X - 1
    ja      .no_place
    cmp     dword [game_target + RAYHIT.py], WORLD_Y - 1
    ja      .no_place
    cmp     dword [game_target + RAYHIT.pz], WORLD_Z - 1
    ja      .no_place
    mov     edi, [game_target + RAYHIT.px]
    mov     esi, [game_target + RAYHIT.py]
    mov     edx, [game_target + RAYHIT.pz]
    call    world_get
    test    eax, eax
    jnz     .no_place
    lea     rdi, [player]
    mov     esi, [game_target + RAYHIT.px]
    mov     edx, [game_target + RAYHIT.py]
    mov     ecx, [game_target + RAYHIT.pz]
    call    body_intersects_block
    test    eax, eax
    jnz     .no_place
    mov     eax, [hotbar_sel]
    movzx   ecx, byte [hotbar + rax]
    mov     edi, [game_target + RAYHIT.px]
    mov     esi, [game_target + RAYHIT.py]
    mov     edx, [game_target + RAYHIT.pz]
    call    world_set
.no_place:

    ; 8. pick block
    cmp     dword [frame_input + FRAMEINPUT.mmb_pressed], 0
    je      .ret
    cmp     dword [game_has_target], 0
    je      .ret
    mov     edi, [game_target + RAYHIT.bx]
    mov     esi, [game_target + RAYHIT.by]
    mov     edx, [game_target + RAYHIT.bz]
    call    world_get
    test    eax, eax
    jz      .ret
    mov     ecx, [hotbar_sel]
    mov     [hotbar + rcx], al
.ret:
    add     rsp, 48
    pop     r12
    pop     rbx
    pop     rbp
    ret
