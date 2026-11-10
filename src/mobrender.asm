; mobrender.asm - zombie, pig, creeper, skeleton, spider and chicken, the faction folk and the Fallen King boss,
; drawn as skin models (skin.asm: the models of skins_mobs.asm and skins_folk.asm) with the state render_world
; leaves set up: atlas on unit 0, light map on unit 1 (each mob binds the light at its body centre), fog, alpha
; test, face culling.
; Model space has the front at -Z; limbs swing about X at their pivot. A mob is tinted by what it
; is doing and suffering (hit red, wind-up red flicker, a raging folk red, frozen and chilled blue,
; burning orange flicker, poisoned green, stun yellow flicker, a champion its faction colour, a
; captive grey, elite gold; first one wins) and sized by what it is (elite 1.2 x, wind-up surge
; 1.05 x, creeper swell). A folk wears its faction's model (the Villagers' leader and trader their own
; robes) plus one more model for its role (crown, hat, helmet, hood or pack) and holds its weapon
; (MOB.wid) in the right hand; a skeleton and the boss hold the item their model carries by default.
%include "common.inc"
%include "gl.inc"
default rel

global mobs_render

extern mobs, sincos_deg, light_bind_at, light_bind_index, skin_model_draw
extern m_zombie, m_pig, m_creeper, m_skeleton, m_spider, m_chicken, m_boss
extern m_folk_villagers, m_folk_bandits, m_folk_cult, m_folk_beastfolk, m_folk_stonekin
extern m_villager_elder, m_villager_merchant
extern m_extra_hat, m_extra_helmet, m_extra_pack, m_extra_crown
extern m_hood_villagers, m_hood_bandits, m_hood_cult, m_hood_beastfolk, m_hood_stonekin

section .rodata
align 4
f_one:      dd 1.0
f_half:     dd 0.5
f_swing:    dd 30.0                     ; peak limb angle, degrees
f_swell:    dd 0.0022222222             ; creeper swell: 20 % over 90 fuse steps
f_elite_g:  dd 0.85                     ; elite tint (1, 0.85, 0.5)
f_elite_b:  dd 0.5
f_wind_g:   dd 0.45                     ; wind-up flicker (1, 0.45, 0.45)
f_wind_b:   dd 0.45
f_stun_b:   dd 0.4                      ; stun flicker (1, 1, 0.4)
f_elite_scale: dd 1.2
f_wind_scale: dd 1.05
f_pois_r:   dd 0.75                     ; poisoned tint (0.75, 1, 0.6)
f_pois_b:   dd 0.6
f_burn_g:   dd 0.6                      ; burning flicker (1, 0.6, 0.3)
f_burn_b:   dd 0.3
f_chill_r:  dd 0.7                      ; chilled tint (0.7, 0.85, 1)
f_chill_g:  dd 0.85
f_frozen_r: dd 0.5                      ; frozen tint (0.5, 0.7, 1)
f_frozen_g: dd 0.7
f_p6:       dd 0.6                      ; captive grey (0.6, 0.6, 0.6); raging folk (1, 0.6, 0.6)
champion_tint:                          ; per faction, in place of the elite gold
    dd 1.0, 0.95, 0.6                   ; Villagers
    dd 1.0, 0.6, 0.6                    ; Bandits
    dd 0.75, 0.6, 0.85                  ; Ashen Cult
    dd 1.0, 0.85, 0.5                   ; Beastfolk
    dd 0.7, 0.85, 1.0                   ; Stonekin

align 8
mob_models:                             ; the model of each mob type, indexed by type - 1
    dq m_zombie, m_pig, m_creeper, m_skeleton, m_spider, m_chicken, m_boss
    dq 0                                ; MOB_FOLK: folk_model picks its models
folk_models:                            ; the folk's body model by faction
    dq m_folk_villagers, m_folk_bandits, m_folk_cult, m_folk_beastfolk, m_folk_stonekin
folk_hoods:                             ; an acolyte's hood by faction
    dq m_hood_villagers, m_hood_bandits, m_hood_cult, m_hood_beastfolk, m_hood_stonekin
%if folk_models - mob_models != NUM_MOB_TYPES * 8
%error "mob_models needs one entry per mob type"
%endif
%if folk_hoods - folk_models != NUM_FACTIONS * 8 || $ - folk_hoods != NUM_FACTIONS * 8
%error "folk_models and folk_hoods need one model per faction"
%endif

section .text

; folk_model(rdi mob) -> rax = its body model, rdx = its role extra model or 0
; The Villagers' leader wears m_villager_elder and their trader m_villager_merchant; every other folk its
; faction's model. The extra: a champion's crown; else a hat for a leader of another faction; else a hood
; for an acolyte guard or patrol, a helmet for any other; else a pack for a traveller and a trader of
; another faction.
folk_model:
    movzx   ecx, byte [rdi + MOB.faction]
    movzx   r8d, byte [rdi + MOB.role]
    lea     rax, [folk_models]
    mov     rax, [rax + rcx * 8]
    test    ecx, ecx
    jnz     .extra
    lea     rsi, [m_villager_elder]
    cmp     r8d, ROLE_LEADER
    cmove   rax, rsi
    lea     rsi, [m_villager_merchant]
    cmp     r8d, ROLE_TRADER
    cmove   rax, rsi
.extra:
    lea     rdx, [m_extra_crown]
    cmp     r8d, ROLE_CHAMPION
    je      .done
    cmp     r8d, ROLE_LEADER
    jne     .not_leader
    lea     rdx, [m_extra_hat]
    test    ecx, ecx
    jnz     .done
    jmp     .none
.not_leader:
    cmp     r8d, ROLE_GUARD
    je      .fighter
    cmp     r8d, ROLE_PATROL
    jne     .not_fighter
.fighter:
    lea     rdx, [m_extra_helmet]
    cmp     byte [rdi + MOB.fclass], FCLASS_ACOLYTE
    jne     .done
    lea     rdx, [folk_hoods]
    mov     rdx, [rdx + rcx * 8]
    ret
.not_fighter:
    lea     rdx, [m_extra_pack]
    cmp     r8d, ROLE_TRAVELLER
    je      .done
    cmp     r8d, ROLE_CARAVAN
    je      .done                       ; an event's merchant carries the traveller's pack
    cmp     r8d, ROLE_TRADER
    jne     .none
    test    ecx, ecx
    jnz     .done
.none:
    xor     edx, edx
.done:
    ret

; mobs_render(): draw every live mob.
; rbx = mob, r12 = end of the table, r13d = model index
; stack: [rsp] swing angle, [rsp+4..12] tint rgb, [rsp+20] flash flag, [rsp+24] size factor,
; [rsp+32] the role extra model (0 none), [rsp+40] the body model's SKPOSE (24 bytes)
mobs_render:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 72
    lea     rbx, [mobs]
    lea     r12, [mobs + MAX_MOBS * MOB_size]
.mob:
    mov     r13d, [rbx + MOB.type]
    dec     r13d                        ; model index; a free slot (0) wraps and is skipped
    cmp     r13d, NUM_MOB_TYPES - 1
    ja      .next
    movss   xmm0, [rbx + MOB.walk]
    call    sincos_deg
    mulss   xmm0, [f_swing]
    movss   [rsp], xmm0                 ; swing = sin(walk) * 30 degrees
    movss   xmm0, [f_one]               ; tint, lowest priority first: elite gold, stun flicker,
    movss   xmm1, xmm0                  ; poison green, burning flicker, chill blue, freeze blue,
    movss   xmm2, xmm0                  ; wind-up flicker, then the hit's red over everything
    cmp     dword [rbx + MOB.elite], 0
    je      .not_elite
    movss   xmm1, [f_elite_g]
    movss   xmm2, [f_elite_b]
.not_elite:
    cmp     dword [rbx + MOB.type], MOB_FOLK
    jne     .tint_status
    movzx   eax, byte [rbx + MOB.role]
    cmp     eax, ROLE_CAPTIVE
    jne     .not_captive
    movss   xmm0, [f_p6]                ; a captive is grey
    movaps  xmm1, xmm0
    movaps  xmm2, xmm0
    jmp     .tint_status
.not_captive:
    cmp     eax, ROLE_CHAMPION
    jne     .tint_status
    movzx   eax, byte [rbx + MOB.faction]
    lea     rax, [rax + rax * 2]
    lea     rcx, [champion_tint]
    movss   xmm0, [rcx + rax * 4]       ; a champion wears its faction's colour, not the elite gold
    movss   xmm1, [rcx + rax * 4 + 4]
    movss   xmm2, [rcx + rax * 4 + 8]
.tint_status:
    mov     eax, [rbx + MOB.stun]
    test    eax, eax
    jle     .not_stunned
    test    al, 4                       ; (stun >> 2) & 1: yellow flicker
    jz      .not_stunned
    movss   xmm1, [f_one]
    movss   xmm2, [f_stun_b]
.not_stunned:
    cmp     dword [rbx + MOB.poison_t], 0
    jle     .not_poisoned
    movss   xmm0, [f_pois_r]
    movss   xmm1, [f_one]
    movss   xmm2, [f_pois_b]
.not_poisoned:
    mov     eax, [rbx + MOB.burn_t]
    test    eax, eax
    jle     .not_burning
    test    al, 8                       ; (burn_t >> 3) & 1: orange flicker
    jz      .not_burning
    movss   xmm0, [f_one]
    movss   xmm1, [f_burn_g]
    movss   xmm2, [f_burn_b]
.not_burning:
    cmp     dword [rbx + MOB.chill_t], 0
    jle     .not_chilled
    movss   xmm0, [f_chill_r]
    movss   xmm1, [f_chill_g]
    movss   xmm2, [f_one]
.not_chilled:
    cmp     dword [rbx + MOB.freeze_cd], 0
    jle     .not_frozen
    cmp     dword [rbx + MOB.stun], 0
    jle     .not_frozen                 ; frozen: stunned by a freeze
    movss   xmm0, [f_frozen_r]
    movss   xmm1, [f_frozen_g]
    movss   xmm2, [f_one]
.not_frozen:
    cmp     dword [rbx + MOB.type], MOB_FOLK
    jne     .not_raging
    test    byte [rbx + MOB.fflags], FF_RAGE
    jz      .not_raging
    movss   xmm0, [f_one]               ; a raging berserker is red under the flickers
    movss   xmm1, [f_p6]
    movss   xmm2, [f_p6]
.not_raging:
    mov     eax, [rbx + MOB.windup]
    test    eax, eax
    jle     .not_winding
    test    al, 4                       ; (windup >> 2) & 1: red flicker
    jz      .not_winding
    movss   xmm0, [f_one]
    movss   xmm1, [f_wind_g]
    movss   xmm2, [f_wind_b]
.not_winding:
    cmp     dword [rbx + MOB.hurt], 0
    jle     .tinted
    movss   xmm0, [f_one]
    movss   xmm1, [f_half]              ; hit: red tint
    movss   xmm2, [f_half]
.tinted:
    movss   [rsp + 4], xmm0
    movss   [rsp + 8], xmm1
    movss   [rsp + 12], xmm2
    movss   xmm0, [rbx + BODY.height]   ; lit by the cell at the middle of the body
    mulss   xmm0, [f_half]
    addss   xmm0, [rbx + BODY.y]
    movaps  xmm1, xmm0
    movss   xmm0, [rbx + BODY.x]
    movss   xmm2, [rbx + BODY.z]
    call    light_bind_at
    call    glPushMatrix
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    call    glTranslatef
    xorps   xmm0, xmm0
    subss   xmm0, [rbx + BODY.yaw]
    xorps   xmm1, xmm1
    movss   xmm2, [f_one]
    xorps   xmm3, xmm3
    call    glRotatef                   ; front (-Z) turns to the mob's heading
    mov     dword [rsp + 20], 0         ; flash flag: untextured parts
    movss   xmm0, [f_one]               ; size: creeper swell x elite x wind-up surge
    movss   [rsp + 24], xmm0
    cmp     dword [rbx + MOB.type], MOB_CREEPER
    jne     .size_elite
    mov     eax, [rbx + MOB.fuse]
    test    eax, eax
    jle     .size_elite
    mov     ecx, 90
    cmp     eax, ecx
    cmova   eax, ecx                    ; swells with the fuse: up to 20 % bigger
    cvtsi2ss xmm0, eax
    mulss   xmm0, [f_swell]
    addss   xmm0, [f_one]
    movss   [rsp + 24], xmm0
    mov     eax, [rbx + MOB.fuse]
    shr     eax, 2
    and     eax, 1                      ; white flash every other 4 steps
    mov     [rsp + 20], eax
.size_elite:
    cmp     dword [rbx + MOB.elite], 0
    je      .size_windup
    movss   xmm0, [rsp + 24]
    mulss   xmm0, [f_elite_scale]
    movss   [rsp + 24], xmm0
.size_windup:
    cmp     dword [rbx + MOB.windup], 0
    jle     .sized
    movss   xmm0, [rsp + 24]
    mulss   xmm0, [f_wind_scale]
    movss   [rsp + 24], xmm0
.sized:
    movss   xmm0, [rsp + 24]
    ucomiss xmm0, [f_one]
    je      .unscaled
    movaps  xmm1, xmm0
    movaps  xmm2, xmm0
    call    glScalef
.unscaled:
    cmp     dword [rsp + 20], 0
    je      .model
    mov     edi, GL_TEXTURE_2D
    call    glDisable
.model:
    lea     rax, [mob_models]
    mov     rdi, [rax + r13 * 8]        ; the type's model (none for a folk)
    mov     qword [rsp + 32], 0         ; no role extra model
    cmp     dword [rbx + MOB.type], MOB_FOLK
    jne     .draw
    mov     rdi, rbx
    call    folk_model                  ; rax = its body model, rdx = its role extra model or 0
    mov     rdi, rax
    mov     [rsp + 32], rdx
.draw:
    mov     dword [rsp + 40 + SKPOSE.flags], 0
    mov     dword [rsp + 40 + SKPOSE.arm_deg], 0
    movzx   eax, byte [rbx + MOB.wid]
    mov     [rsp + 40 + SKPOSE.held], eax           ; the weapon in the right hand, 0 = the model's own
    mov     eax, [f_one]
    mov     [rsp + 40 + SKPOSE.accent], eax         ; accent parts stay white
    mov     [rsp + 40 + SKPOSE.accent + 4], eax
    mov     [rsp + 40 + SKPOSE.accent + 8], eax
    lea     rsi, [rsp + 40]
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    movss   xmm3, [rsp + 12]
    call    skin_model_draw
    mov     rdi, [rsp + 32]             ; then the role extra model, if any, without a pose
    test    rdi, rdi
    jz      .parts_done
    xor     esi, esi
    xorps   xmm0, xmm0
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    movss   xmm3, [rsp + 12]
    call    skin_model_draw
.parts_done:
    cmp     dword [rsp + 20], 0
    je      .unflash
    mov     edi, GL_TEXTURE_2D
    call    glEnable
.unflash:
    call    glPopMatrix
.next:
    add     rbx, MOB_size
    cmp     rbx, r12
    jb      .mob
    mov     edi, LIGHT_SKY_FULL
    call    light_bind_index
    add     rsp, 72
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
