; peerrender.asm - the other players of a multiplayer session. peers_render draws their avatars in
; the world pass (right after mobs_render: atlas on unit 0, light map on unit 1, every avatar binds
; the light at its body centre), peers_hud their name plates and health bars in the 2D pass (after
; hud_mobs). An avatar is the skin model m_avatar, untinted (red while PS_HURT) with the colour of its
; slot (peer_colors) on the model's accent parts, its arms and legs swinging with the walk phase the
; netsync proxy keeps in PEER.walk, the right arm raised while PS_SWING is set and the item the player
; holds (PSTATE.held) in the right hand. No armour model. The local player (slot net_self), dead players
; and slots that are not PEER_READY are skipped. Proxy bodies are in local coordinates, like every body.
%include "common.inc"
%include "gl.inc"
default rel

global peers_render, peers_hud, peer_slot_rgba, peer_colors

extern net_role, net_self, net_peers, player
extern skin_model_draw, m_avatar
extern sincos_deg, light_bind_at, light_bind_index
extern world_to_ui, ui_text_centered, ui_text_width, ui_rect, bar_px


section .rodata
align 4
f_one:      dd 1.0
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

; peers_render(): the avatar of every other player; nothing offline
; rbx = slot, r12 = PEER*, r13d = its PS_* flags
; stack: [rsp] swing angle, [rsp+4..12] tint rgb, [rsp+16] the avatar's SKPOSE (24 bytes)
peers_render:
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
    movzx   r13d, word [r12 + PEER.ps + PSTATE.flags]
    test    r13d, PS_DEAD
    jnz     .next
    movss   xmm0, [r12 + PEER.walk]
    call    sincos_deg
    mulss   xmm0, [f_swing]
    movss   [rsp], xmm0                 ; swing = sin(walk) * 30 degrees
    cmp     byte [r12 + PEER.ps + PSTATE.seat], 0
    je      .swing_set
    mov     dword [rsp], 0              ; sitting in a plane: the limbs hang still
.swing_set:
    movss   xmm0, [f_one]               ; tint: white, red while hurt
    movaps  xmm1, xmm0
    movaps  xmm2, xmm0
    test    r13d, PS_HURT
    jz      .tinted
    movss   xmm1, [f_hurt_gb]
    movaps  xmm2, xmm1
.tinted:
    movss   [rsp + 4], xmm0
    movss   [rsp + 8], xmm1
    movss   [rsp + 12], xmm2
    xor     eax, eax                    ; the pose: the right arm raised while the player attacks,
    mov     ecx, SKP_ARM_UP
    test    r13d, PS_SWING
    cmovnz  eax, ecx
    mov     [rsp + 16 + SKPOSE.flags], eax
    movss   xmm0, [f_arm_up]
    movss   [rsp + 16 + SKPOSE.arm_deg], xmm0
    movzx   eax, byte [r12 + PEER.ps + PSTATE.held]
    mov     [rsp + 16 + SKPOSE.held], eax       ; the item in the right hand (0: a bare hand)
    lea     rax, [rbx + rbx*2]
    lea     rcx, [peer_colors]
    lea     rcx, [rcx + rax*4]
    mov     eax, [rcx]                  ; the slot colour on the accent parts
    mov     [rsp + 16 + SKPOSE.accent], eax
    mov     eax, [rcx + 4]
    mov     [rsp + 16 + SKPOSE.accent + 4], eax
    mov     eax, [rcx + 8]
    mov     [rsp + 16 + SKPOSE.accent + 8], eax
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
    lea     rdi, [m_avatar]
    lea     rsi, [rsp + 16]
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    movss   xmm3, [rsp + 12]
    call    skin_model_draw
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
