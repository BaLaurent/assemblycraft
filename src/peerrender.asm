; peerrender.asm - the other players of a multiplayer session. peers_render draws their avatars in
; the world pass (right after mobs_render: atlas on unit 0, light map on unit 1, every avatar binds
; the light at its body centre), peers_hud their name plates and health bars in the 2D pass (after
; hud_mobs). An avatar is the Villagers' humanoid skin (folk_tables[FAC_VILLAGERS]) tinted half way
; from white to the colour of its slot (peer_colors; red while PS_HURT), its arms and legs swinging
; with the walk phase the netsync proxy keeps in PEER.walk, the right arm raised while PS_SWING is
; set. No held item and no armour model. The local player (slot net_self), dead players and slots
; that are not PEER_READY are skipped. Proxy bodies are in local coordinates, like every body.
%include "common.inc"
%include "gl.inc"
default rel

global peers_render, peers_hud, peer_slot_rgba

extern net_role, net_self, net_peers, player
extern folk_tables, mob_parts_draw
extern sincos_deg, light_bind_at, light_bind_index
extern world_to_ui, ui_text_centered, ui_text_width, ui_rect, bar_px

%define PART_SIZE       48              ; a part record of mobrender.asm
%define AVATAR_PARTS    6               ; the folk model: legs, body, left arm, right arm, head
%define PART_ARM_R      4
%define PART_HEAD       5

section .rodata
align 4
f_one:      dd 1.0
f_half:     dd 0.5
f_255:      dd 255.0
f_swing:    dd 30.0                     ; peak limb angle, degrees (as mobs_render)
f_arm_up:   dd 60.0                     ; the right arm's extra angle while the player attacks (a positive
                                        ; angle about X turns a hanging limb forward, toward -Z)
f_hurt_gb:  dd 0.4                      ; hurt tint (1, 0.4, 0.4)
f_chest:    dd 0.9                      ; the light is bound at the middle of the body
f_plate_up: dd 2.1                      ; the plate floats this high over the feet ...
f_plate_sq: dd 4096.0                   ; ... and shows within 64 blocks
; the colour of each slot (r, g, b): gold, blue, green, red, purple, orange, cyan, pink
peer_colors:
    dd 1.0, 0.85, 0.3
    dd 0.4, 0.7, 1.0
    dd 0.45, 0.9, 0.45
    dd 1.0, 0.45, 0.45
    dd 0.75, 0.5, 1.0
    dd 1.0, 0.65, 0.3
    dd 0.35, 0.95, 0.9
    dd 1.0, 0.55, 0.8

section .text

; peer_slot_rgba(edi slot) -> eax the colour of slot (mod 8) as an opaque packed RGBA (leaf)
peer_slot_rgba:
    and     edi, 7
    lea     eax, [rdi + rdi*2]
    lea     rcx, [peer_colors]
    lea     rcx, [rcx + rax*4]
    movss   xmm0, [rcx]
    mulss   xmm0, [f_255]
    cvtss2si eax, xmm0
    movss   xmm0, [rcx + 4]
    mulss   xmm0, [f_255]
    cvtss2si edx, xmm0
    shl     edx, 8
    or      eax, edx
    movss   xmm0, [rcx + 8]
    mulss   xmm0, [f_255]
    cvtss2si edx, xmm0
    shl     edx, 16
    or      eax, edx
    or      eax, 0xFF000000
    ret

; the arguments of mob_parts_draw after the parts, the extra part and the count: the swing angle
; and the tint, as peers_render keeps them on its stack
%macro PARTS_ARGS 0
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    movss   xmm3, [rsp + 12]
%endmacro

; peers_render(): the avatar of every other player; nothing offline
; rbx = slot, r12 = PEER*, r13d = its PS_* flags
; stack: [rsp] swing angle, [rsp+4..12] tint rgb, [rsp+16] the model's parts
peers_render:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 40
    cmp     byte [net_role], NET_ROLE_OFF
    je      .ret
    lea     rax, [folk_tables]
    mov     rax, [rax + FAC_VILLAGERS*8]
    mov     [rsp + 16], rax
    xor     ebx, ebx
    lea     r12, [net_peers]
.peer:
    movzx   eax, byte [net_self]
    cmp     ebx, eax
    je      .next
    cmp     dword [r12 + PEER.state], PEER_READY
    jne     .next
    movzx   r13d, word [r12 + PEER.ps + PSTATE.flags]
    test    r13d, PS_DEAD
    jnz     .next
    movss   xmm0, [r12 + PEER.walk]
    call    sincos_deg
    mulss   xmm0, [f_swing]
    movss   [rsp], xmm0                 ; swing = sin(walk) * 30 degrees
    lea     rax, [rbx + rbx*2]
    lea     rcx, [peer_colors]
    lea     rcx, [rcx + rax*4]
    movss   xmm0, [f_one]               ; tint = (1 + slot colour) / 2 per channel
    addss   xmm0, [rcx]
    mulss   xmm0, [f_half]
    movss   xmm1, [f_one]
    addss   xmm1, [rcx + 4]
    mulss   xmm1, [f_half]
    movss   xmm2, [f_one]
    addss   xmm2, [rcx + 8]
    mulss   xmm2, [f_half]
    test    r13d, PS_HURT
    jz      .tinted
    movss   xmm0, [f_one]               ; hurt: red
    movss   xmm1, [f_hurt_gb]
    movaps  xmm2, xmm1
.tinted:
    movss   [rsp + 4], xmm0
    movss   [rsp + 8], xmm1
    movss   [rsp + 12], xmm2
    movss   xmm1, [r12 + PEER.body + BODY.y]    ; lit by the cell at the middle of the body
    addss   xmm1, [f_chest]
    movss   xmm0, [r12 + PEER.body + BODY.x]
    movss   xmm2, [r12 + PEER.body + BODY.z]
    call    light_bind_at
    call    glPushMatrix
    movss   xmm0, [r12 + PEER.body + BODY.x]
    movss   xmm1, [r12 + PEER.body + BODY.y]
    movss   xmm2, [r12 + PEER.body + BODY.z]
    call    glTranslatef
    xorps   xmm0, xmm0
    subss   xmm0, [r12 + PEER.body + BODY.yaw]
    xorps   xmm1, xmm1
    movss   xmm2, [f_one]
    xorps   xmm3, xmm3
    call    glRotatef                   ; front (-Z) turns to the player's heading
    test    r13d, PS_SWING
    jnz     .attack
    mov     rdi, [rsp + 16]
    xor     esi, esi
    mov     edx, AVATAR_PARTS
    PARTS_ARGS
    call    mob_parts_draw
    jmp     .drawn
.attack:
    mov     rdi, [rsp + 16]             ; legs, body and left arm swing with the walk
    xor     esi, esi
    mov     edx, PART_ARM_R
    PARTS_ARGS
    call    mob_parts_draw
    mov     rdi, [rsp + 16]             ; the right arm alone, raised on top of its walk swing
    add     rdi, PART_ARM_R * PART_SIZE
    xor     esi, esi
    mov     edx, 1
    PARTS_ARGS
    addss   xmm0, [f_arm_up]
    call    mob_parts_draw
    mov     rdi, [rsp + 16]             ; and the head
    add     rdi, PART_HEAD * PART_SIZE
    xor     esi, esi
    mov     edx, 1
    PARTS_ARGS
    call    mob_parts_draw
.drawn:
    call    glPopMatrix
.next:
    add     r12, PEER_size
    inc     ebx
    cmp     ebx, NET_MAX_PEERS
    jb      .peer
    mov     edi, LIGHT_SKY_FULL
    call    light_bind_index
.ret:
    add     rsp, 40
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; peers_hud(): over every other player within 64 blocks (world_to_ui, 2.1 blocks over the feet) its
; name centred in its slot colour on a faint backing and, once it is hurt, a 20 px health bar under
; the name in the colours of hud_mobs; nothing offline
; rbx = slot, r12 = PEER*, r13d = the name's width, then the bar's fill
; stack: [rsp] the anchor in the world (x, y, z), [rsp+16] its screen x, y
peers_hud:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 40
    cmp     byte [net_role], NET_ROLE_OFF
    je      .ret
    xor     ebx, ebx
    lea     r12, [net_peers]
.peer:
    movzx   eax, byte [net_self]
    cmp     ebx, eax
    je      .next
    cmp     dword [r12 + PEER.state], PEER_READY
    jne     .next
    test    word [r12 + PEER.ps + PSTATE.flags], PS_DEAD
    jnz     .next
    movss   xmm0, [r12 + PEER.body + BODY.x]
    subss   xmm0, [player + BODY.x]
    movss   xmm1, [r12 + PEER.body + BODY.y]
    subss   xmm1, [player + BODY.y]
    movss   xmm2, [r12 + PEER.body + BODY.z]
    subss   xmm2, [player + BODY.z]
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    mulss   xmm2, xmm2
    addss   xmm0, xmm1
    addss   xmm0, xmm2
    comiss  xmm0, [f_plate_sq]
    ja      .next
    mov     eax, [r12 + PEER.body + BODY.x]
    mov     [rsp], eax
    movss   xmm0, [r12 + PEER.body + BODY.y]
    addss   xmm0, [f_plate_up]
    movss   [rsp + 4], xmm0
    mov     eax, [r12 + PEER.body + BODY.z]
    mov     [rsp + 8], eax
    mov     rdi, rsp
    lea     rsi, [rsp + 16]
    call    world_to_ui
    test    eax, eax
    jz      .next
    lea     rdi, [r12 + PEER.name]
    mov     esi, 1
    call    ui_text_width
    mov     r13d, eax
    shr     eax, 1
    mov     edi, [rsp + 16]
    sub     edi, eax
    sub     edi, 2                      ; the backing: the name's width + 4, 10 high, centred
    mov     esi, [rsp + 20]
    sub     esi, 12
    lea     edx, [r13 + 4]
    mov     ecx, 10
    mov     r8d, RGBA(0, 0, 0, 100)
    call    ui_rect
    mov     edi, ebx
    call    peer_slot_rgba
    mov     ecx, eax
    lea     rdi, [r12 + PEER.name]
    mov     esi, [rsp + 16]
    mov     edx, [rsp + 20]
    sub     edx, 11
    mov     r8d, 1
    call    ui_text_centered
    movzx   eax, word [r12 + PEER.ps + PSTATE.health]
    movzx   ecx, word [r12 + PEER.ps + PSTATE.max_health]
    cmp     eax, ecx
    jae     .next                       ; unhurt: no bar
    cvtsi2ss xmm0, eax
    cvtsi2ss xmm1, ecx
    mov     edi, 20
    call    bar_px                      ; 0 when max_health is 0
    mov     r13d, eax
    mov     edi, [rsp + 16]
    sub     edi, 11                     ; 22 x 4 backing, centred on the anchor
    mov     esi, [rsp + 20]
    sub     esi, 2
    mov     edx, 22
    mov     ecx, 4
    mov     r8d, RGBA(0, 0, 0, 160)
    call    ui_rect
    test    r13d, r13d
    jz      .next
    mov     edi, [rsp + 16]
    sub     edi, 10
    mov     esi, [rsp + 20]
    dec     esi
    mov     edx, r13d
    mov     ecx, 2
    mov     r8d, RGBA(230, 40, 40, 255)
    call    ui_rect
.next:
    add     r12, PEER_size
    inc     ebx
    cmp     ebx, NET_MAX_PEERS
    jb      .peer
.ret:
    add     rsp, 40
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
