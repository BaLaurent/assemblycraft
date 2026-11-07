; fire.asm - fire: burning cells that hurt, spread to flammable blocks, ignite TNT and burn out.
; The world holds a FIRE block in every burning cell; the fires table records its age and the
; steps to its next spread/burn roll. The table is not saved: fire_rebuild re-reads it from
; the world after a load.
%include "common.inc"
default rel

global fires, fire_clear, fire_place, fire_step, fire_render, fire_rebuild

extern world_get, world_set, blocks, rng_next, block_flammable
extern survival_damage, mobs, mob_hurt, player
extern tnt_prime, cont_block_removed
extern game_time, render_box

section .rodata
align 4
c_one:       dd 1.0
c_pw:        dd 0.3                     ; player box half width, height
c_ph:        dd 1.8
c_lo:        dd 0.48                    ; crossed slabs: 0.04 thick, centred in the cell
c_hi:        dd 0.52
tiles0:      times 6 db TILE_FIRE0
tiles1:      times 6 db TILE_FIRE1
shades:      times 6 dd 1.0
; the 6 neighbours: +x -x +y -y +z -z
dirs:        dd 1, 0, 0,  -1, 0, 0,  0, 1, 0,  0, -1, 0,  0, 0, 1,  0, 0, -1

section .data
align 16
fires:
    times MAX_FIRES dd -1, 0, 0, 0, 0   ; x = -1: free slot

section .text

; fire_clear(): every slot free (the world's FIRE blocks stay)
fire_clear:
    lea     rdi, [fires]
    mov     ecx, MAX_FIRES
.l:
    mov     dword [rdi + FIREENT.x], -1
    add     rdi, FIREENT_size
    dec     ecx
    jnz     .l
    ret

; rng_mod(edi n) -> eax rng % n
rng_mod:
    push    rbx
    mov     ebx, edi
    call    rng_next
    xor     edx, edx
    div     ebx
    mov     eax, edx
    pop     rbx
    ret

; fire_place(edi x, esi y, edx z) -> eax 1 when fire was placed: the cell must be in the
; world, air, and a slot must be free. The block becomes FIRE; its first roll comes in
; 20 + rng % 20 steps.
fire_place:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    cmp     edi, WORLD_X - 1
    ja      .no
    cmp     esi, WORLD_Y - 1
    ja      .no
    cmp     edx, WORLD_Z - 1
    ja      .no
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edx
    call    world_get
    test    eax, eax                    ; AIR
    jnz     .no
    lea     rbx, [fires]
    mov     ecx, MAX_FIRES
.find:
    cmp     dword [rbx + FIREENT.x], -1
    je      .got
    add     rbx, FIREENT_size
    dec     ecx
    jnz     .find
    jmp     .no
.got:
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, FIRE
    call    world_set
    mov     [rbx + FIREENT.x], r12d
    mov     [rbx + FIREENT.y], r13d
    mov     [rbx + FIREENT.z], r14d
    mov     dword [rbx + FIREENT.age], 0
    mov     edi, 20
    call    rng_mod
    add     eax, 20
    mov     [rbx + FIREENT.tick], eax
    mov     eax, 1
    jmp     .out
.no:
    xor     eax, eax
.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; body_in_cell(rdi body, esi cx, edx cy, ecx cz, xmm0 half width, xmm1 height) -> eax 1 when
; the body's box (centred on x and z, standing on y) overlaps the cell's unit cube
body_in_cell:
    movss   xmm2, [rdi + BODY.x]
    movaps  xmm3, xmm2
    subss   xmm3, xmm0                  ; lo
    addss   xmm2, xmm0                  ; hi
    cvtsi2ss xmm4, esi
    comiss  xmm2, xmm4
    jbe     .no
    addss   xmm4, [c_one]
    comiss  xmm3, xmm4
    jae     .no
    movss   xmm2, [rdi + BODY.z]
    movaps  xmm3, xmm2
    subss   xmm3, xmm0
    addss   xmm2, xmm0
    cvtsi2ss xmm4, ecx
    comiss  xmm2, xmm4
    jbe     .no
    addss   xmm4, [c_one]
    comiss  xmm3, xmm4
    jae     .no
    movss   xmm3, [rdi + BODY.y]
    movaps  xmm2, xmm3
    addss   xmm2, xmm1                  ; top
    cvtsi2ss xmm4, edx
    comiss  xmm2, xmm4
    jbe     .no
    addss   xmm4, [c_one]
    comiss  xmm3, xmm4
    jae     .no
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; has_fuel(edi x, esi y, edx z) -> eax 1 when one of the cell's 6 neighbours is flammable
has_fuel:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edx
    xor     ebx, ebx
.l:
    lea     rax, [dirs]
    lea     ecx, [rbx + rbx*2]
    lea     rax, [rax + rcx*4]
    mov     edi, [rax]
    add     edi, r12d
    mov     esi, [rax + 4]
    add     esi, r13d
    mov     edx, [rax + 8]
    add     edx, r14d
    call    world_get
    lea     rcx, [block_flammable]
    cmp     byte [rcx + rax], 0
    jne     .yes
    inc     ebx
    cmp     ebx, 6
    jb      .l
    xor     eax, eax
    jmp     .out
.yes:
    mov     eax, 1
.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; fire_step(): every fire hurts what stands in it; on its roll it burns neighbouring blocks,
; spreads and may burn out. See fire_one.
fire_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    lea     rbx, [fires]
    mov     r12d, MAX_FIRES
.l:
    cmp     dword [rbx + FIREENT.x], -1
    je      .next
    mov     rdi, rbx
    call    fire_one
.next:
    add     rbx, FIREENT_size
    dec     r12d
    jnz     .l
    pop     r12
    pop     rbx
    pop     rbp
    ret

; dir_cell(): edi, esi, edx = the cell neighbouring (r13d, r14d, r15d) in direction r12d
dir_cell:
    lea     rax, [dirs]
    lea     ecx, [r12 + r12*2]
    lea     rax, [rax + rcx*4]
    mov     edi, [rax]
    add     edi, r13d
    mov     esi, [rax + 4]
    add     esi, r14d
    mov     edx, [rax + 8]
    add     edx, r15d
    ret

; fire_one(rdi slot): one step of one fire.
;  1. the slot is freed when its block is no longer FIRE;
;  2. the player (survival) and every mob whose box overlaps the cell take 1 damage;
;  3. when the tick runs out (re-armed to 20 + rng % 20): each flammable neighbour burns with
;     its chance in % (TNT is primed with an 80 step fuse; other blocks vanish, and half of
;     the time leave fire behind); one random cell in x+-1, y-1..+2, z+-1 catches fire when
;     it is air next to a flammable block; and the fire burns out when it is older than
;     40 + rng % 40 steps (no flammable neighbour) or 400 + rng % 400 (some neighbour burns).
; r13d, r14d, r15d = cell, rbx = slot, r12d = neighbour direction / mob pointer.
; Frame: [rsp] mob index or neighbour chance, [rsp+4] neighbour id, [rsp+8..16] spread cell.
fire_one:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     rbx, rdi
    mov     r13d, [rbx + FIREENT.x]
    mov     r14d, [rbx + FIREENT.y]
    mov     r15d, [rbx + FIREENT.z]
    mov     edi, r13d
    mov     esi, r14d
    mov     edx, r15d
    call    world_get
    cmp     eax, FIRE
    jne     .free
    inc     dword [rbx + FIREENT.age]
    ; ---- damage ----
    lea     rdi, [player]
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, r15d
    movss   xmm0, [c_pw]
    movss   xmm1, [c_ph]
    call    body_in_cell
    test    eax, eax
    jz      .mobs
    mov     edi, 1
    mov     esi, CAUSE_FIRE
    call    survival_damage             ; creative, death and invulnerability decline
.mobs:
    lea     r12, [mobs]
    mov     dword [rsp], 0
.mob:
    cmp     dword [r12 + MOB.type], MOB_NONE
    je      .mob_next
    mov     rdi, r12                    ; MOB.body is the first field
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, r15d
    movss   xmm0, [r12 + BODY.half_w]
    movss   xmm1, [r12 + BODY.height]
    call    body_in_cell
    test    eax, eax
    jz      .mob_next
    mov     edi, [rsp]
    mov     esi, 1
    xorps   xmm0, xmm0
    xorps   xmm1, xmm1
    call    mob_hurt
.mob_next:
    add     r12, MOB_size
    inc     dword [rsp]
    cmp     dword [rsp], MAX_MOBS
    jb      .mob
    ; ---- the roll ----
    dec     dword [rbx + FIREENT.tick]
    jg      .done
    mov     edi, 20
    call    rng_mod
    add     eax, 20
    mov     [rbx + FIREENT.tick], eax
    xor     r12d, r12d
.nb:
    call    dir_cell
    call    world_get
    mov     [rsp + 4], eax
    lea     rcx, [block_flammable]
    movzx   eax, byte [rcx + rax]
    test    eax, eax
    jz      .nb_next
    mov     [rsp], eax
    mov     edi, 100
    call    rng_mod
    cmp     eax, [rsp]
    jae     .nb_next
    call    dir_cell
    cmp     dword [rsp + 4], TNT
    jne     .burn
    mov     ecx, 80
    call    tnt_prime
    jmp     .nb_next
.burn:
    call    cont_block_removed
    call    dir_cell
    xor     ecx, ecx
    call    world_set
    mov     edi, 2
    call    rng_mod
    test    eax, eax
    jnz     .nb_next
    call    dir_cell
    call    fire_place
.nb_next:
    inc     r12d
    cmp     r12d, 6
    jb      .nb
    ; ---- spread ----
    mov     edi, 3
    call    rng_mod
    lea     eax, [rax + r13 - 1]
    mov     [rsp + 8], eax
    mov     edi, 4
    call    rng_mod
    lea     eax, [rax + r14 - 1]
    mov     [rsp + 12], eax
    mov     edi, 3
    call    rng_mod
    lea     eax, [rax + r15 - 1]
    mov     [rsp + 16], eax
    mov     edi, [rsp + 8]
    mov     esi, [rsp + 12]
    mov     edx, [rsp + 16]
    call    world_get                   ; out of the world reads as air; fire_place refuses it
    test    eax, eax
    jnz     .burnout
    mov     edi, [rsp + 8]
    mov     esi, [rsp + 12]
    mov     edx, [rsp + 16]
    call    has_fuel
    test    eax, eax
    jz      .burnout
    mov     edi, [rsp + 8]
    mov     esi, [rsp + 12]
    mov     edx, [rsp + 16]
    call    fire_place
.burnout:
    mov     edi, r13d
    mov     esi, r14d
    mov     edx, r15d
    call    has_fuel
    test    eax, eax
    jnz     .fuel
    mov     edi, 40
    call    rng_mod
    add     eax, 40
    jmp     .age
.fuel:
    mov     edi, 400
    call    rng_mod
    add     eax, 400
.age:
    cmp     [rbx + FIREENT.age], eax
    jle     .done
    mov     edi, r13d
    mov     esi, r14d
    mov     edx, r15d
    xor     ecx, ecx
    call    world_set
.free:
    mov     dword [rbx + FIREENT.x], -1
.done:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; fire_render(): every fire as two crossed vertical slabs (0.04 thick), flame frame
; alternating with (game_time / 6 + slot index) & 1, full brightness. Called inside the world
; pass (atlas bound, alpha test on).
; Frame: [rsp] box float[6].
fire_render:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 24
    lea     rbx, [fires]
    xor     r12d, r12d
.l:
    cmp     dword [rbx + FIREENT.x], -1
    je      .next
    mov     eax, [game_time]
    xor     edx, edx
    mov     ecx, 6
    div     ecx
    add     eax, r12d
    and     eax, 1
    lea     r13, [tiles0]
    lea     rcx, [tiles1]
    test    eax, eax
    cmovnz  r13, rcx
    ; slab along x: x..x+1, z + 0.48..0.52
    cvtsi2ss xmm0, dword [rbx + FIREENT.x]
    cvtsi2ss xmm1, dword [rbx + FIREENT.y]
    cvtsi2ss xmm2, dword [rbx + FIREENT.z]
    movss   [rsp], xmm0
    addss   xmm0, [c_one]
    movss   [rsp + 12], xmm0
    movss   [rsp + 4], xmm1
    addss   xmm1, [c_one]
    movss   [rsp + 16], xmm1
    movaps  xmm3, xmm2
    addss   xmm3, [c_lo]
    movss   [rsp + 8], xmm3
    addss   xmm2, [c_hi]
    movss   [rsp + 20], xmm2
    call    draw_slab
    ; slab along z: x + 0.48..0.52, z..z+1
    cvtsi2ss xmm0, dword [rbx + FIREENT.x]
    cvtsi2ss xmm2, dword [rbx + FIREENT.z]
    movaps  xmm3, xmm0
    addss   xmm3, [c_lo]
    movss   [rsp], xmm3
    addss   xmm0, [c_hi]
    movss   [rsp + 12], xmm0
    movss   [rsp + 8], xmm2
    addss   xmm2, [c_one]
    movss   [rsp + 20], xmm2
    call    draw_slab
.next:
    add     rbx, FIREENT_size
    inc     r12d
    cmp     r12d, MAX_FIRES
    jb      .l
    add     rsp, 24
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; draw_slab(): the box at the caller's [rsp] (fire_render frame, +8 for the return address),
; tiles r13, full brightness, white
draw_slab:
    sub     rsp, 8
    lea     rdi, [rsp + 16]
    mov     rsi, r13
    lea     rdx, [shades]
    movss   xmm0, [c_one]
    movaps  xmm1, xmm0
    movaps  xmm2, xmm0
    call    render_box
    add     rsp, 8
    ret

; fire_rebuild(): after a world load, forget the table and record every FIRE block in the
; world (a full scan). FIRE blocks beyond MAX_FIRES become air.
; rbx = scan position, r12 = end, r13d = fires recorded, r14d = found cell index.
fire_rebuild:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    call    fire_clear
    lea     rbx, [blocks]
    lea     r12, [blocks + WORLD_VOLUME]
    xor     r13d, r13d
.scan:
    mov     rdi, rbx
    mov     rcx, r12
    sub     rcx, rbx
    jz      .done
    mov     al, FIRE
    repne scasb
    jne     .done
    mov     rbx, rdi                    ; one past the match
    lea     r14, [blocks]
    mov     rax, rdi
    sub     rax, r14
    dec     eax
    mov     r14d, eax                   ; index = y << 16 | z << 8 | x
    mov     edi, r14d
    and     edi, 255
    mov     esi, r14d
    shr     esi, 16
    mov     edx, r14d
    shr     edx, 8
    and     edx, 255
    cmp     r13d, MAX_FIRES
    jae     .overflow
    mov     r15d, r13d
    imul    r15d, FIREENT_size
    lea     rax, [fires]
    add     r15, rax
    mov     [r15 + FIREENT.x], edi
    mov     [r15 + FIREENT.y], esi
    mov     [r15 + FIREENT.z], edx
    mov     dword [r15 + FIREENT.age], 0
    mov     edi, 20
    call    rng_mod
    add     eax, 20
    mov     [r15 + FIREENT.tick], eax
    inc     r13d
    jmp     .scan
.overflow:
    xor     ecx, ecx
    call    world_set                   ; edi, esi, edx are the cell
    jmp     .scan
.done:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
