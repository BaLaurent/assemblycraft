; arrows.asm - projectiles: arrows, bullets, rockets, magic bolts, fireballs, knives and grenades. Spawn,
; flight, hits on mobs and the player, arrows sticking in blocks and the player picking his own back up,
; rockets, grenades and fireballs exploding on impact, drawing. Projectiles are not saved with the world; they
; live in local coordinates (arrows_shift follows the origin) and expire on their own, so nothing
; removes them when a column unloads.
; In multiplayer a player's projectile is also sent to the other peers (net_proj_out): they fly a ghost of it (AF_GHOST)
; that hits nothing, is never picked up and never explodes; the owner's machine decides all of that and says when the
; real one ended (PROJ_END). arrow_net pairs a projectile with its twin.
%include "common.inc"
%include "gl.inc"
default rel

global arrows, arrows_clear, arrows_spawn, arrows_step, arrows_render, arrows_shift, arrow_net

extern player, raycast, ray_aabb, mobs_raycast, explode_at, explode_magic, explode_mob_mult
extern mobs, folk_hit_by, faction_enemies, rpg_keystones, ab_flash_at
extern surv, game_mode, inv_add
extern audio_play, audio_play_at
extern render_box, atan2_deg, fx_burst
extern player_take_hit, combat_hit_mob, combat_calc, combat_player_status, combat_kb_mult
extern combat_hit_player, net_players_raycast, net_hurt_send, net_explosion_players
extern net_proj_out, net_proj_end_out, net_role, net_applying, net_peers, explode_pvp
extern glIsEnabled

%define STUCK_MOB_STEPS 60              ; a skeleton's arrow stays in the block 1 s
%define STUCK_OWN_STEPS 1200            ; the player's arrow stays 20 s
%define TRAIL_DELAY     3               ; steps of flight before a bolt or fireball leaves a trail

; arrows_step frame (rsp-relative)
%define S_SEG   0                       ; float seg[3]: this step's displacement
%define S_DIR   12                      ; float dir[3]: unit heading
%define S_HIT   24                      ; RAYHIT (24 bytes)
%define S_LO    48                      ; float lo[3] / hi[3] of the box under test
%define S_HI    60
%define S_LEN   72                      ; float |seg|
%define S_TMAX  76                      ; float nearest block distance, or len without a hit
%define S_T     80                      ; float distance of the hit that wins
%define S_HP    84                      ; float hit point[3]
%define S_H     96                      ; float unit horizontal heading (x, z)
%define S_IDX   104                     ; int mob index hit
%define S_BLK   108                     ; int 1 when raycast found a block
%define S_WHO   112                     ; int the player hit: 0 the local one (the host, or offline), 1..7 a remote one, -1 nobody
%define S_SRC   116                     ; float where a shot at a player comes from: x, z
%define S_RAD   124                     ; float blast radius of a powder grenade
%define S_APPLY 128                     ; int net_applying while the trail is drawn
%define S_FRAME 144

section .rodata
align 4
c_dt:        dd 0.016666668
c_gravity:   dd 0.33333334              ; arrows: 20 blocks/s^2 per step
c_tiny:      dd 0.000001
c_hdir_min:  dd 0.0001
c_embed:     dd 0.05                    ; an arrow stops this far short of the surface it hit
c_out_y:     dd -8.0
c_pick_r2:   dd 1.0                     ; horizontal pickup radius^2
c_pick_hi:   dd 2.0                     ; arrow y - player y window
c_pop_vol:   dd 0.35
c_hit_vol:   dd 0.8
c_stick_vol: dd 0.5
c_kb:        dd 4.0                     ; knockback speed of an arrow hit on the player
c_half_w:    dd 0.3                     ; player box
c_height:    dd 1.8
f_one:       dd 1.0
c_bullet_vol: dd 0.4
c_rocket_r:  dd 3.0                     ; rocket blast radius
c_grenade_r: dd 3.0                     ; powder grenade blast radius
c_keg:       dd 1.5                     ; Powder Keg: rocket and grenade blasts 50 % wider
c_magic_r:   dd 2.5                     ; fireball and explosive arrow blast radius
c_magic_big: dd 3.0                     ; AF_BIG fireballs (meteors)
c_src_t:     dd 0.1                     ; a mob's arrow "comes from" 0.1 s back along its path
c_trail_v:   dd 0.3                     ; speed of a trail particle
c_burst_v:   dd 1.0                     ; speed of the sparks where a bolt ends
; flying steps before a projectile is gone (a rocket, grenade or fireball explodes then), by kind
max_age:     dd 600, 120, 300, 90, 120, 20, 120 ; ARROW, BULLET, ROCKET, BOLT, FIREBALL, KNIFE, GRENADE

; arrow model: shaft, tip, fletching (box lo xyz, hi xyz); the tip points to -Z
arrow_shaft: dd -0.03, -0.03, -0.25,  0.03, 0.03, 0.25
arrow_tip:   dd -0.04, -0.04, -0.30,  0.04, 0.04, -0.22
arrow_fletch: dd -0.06, -0.01, 0.15,  0.06, 0.01, 0.27
tiles_shaft: db 5, 5, 5, 5, 5, 5, 0, 0
tiles_tip:   db 0, 0, 0, 0, 0, 0, 0, 0
tiles_fletch: db TILE_CHICKEN_BODY, TILE_CHICKEN_BODY, TILE_CHICKEN_BODY
             db TILE_CHICKEN_BODY, TILE_CHICKEN_BODY, TILE_CHICKEN_BODY, 0, 0
arrow_shades: dd 0.6, 0.6, 1.0, 0.5, 0.8, 0.8   ; +X -X +Y -Y +Z -Z

; bullet: a short brass slug; rocket: body, red warhead, fins (all point to -Z)
bullet_box:  dd -0.025, -0.025, -0.08,  0.025, 0.025, 0.08
rocket_body: dd -0.07, -0.07, -0.25,  0.07, 0.07, 0.2
rocket_head: dd -0.08, -0.08, -0.38,  0.08, 0.08, -0.25
rocket_fins: dd -0.15, -0.02, 0.12,  0.15, 0.02, 0.25
tiles_brass: times 6 db TILE_CHICKEN_LEG
             db 0, 0
tiles_steel: times 6 db TILE_SKELETON_BONE
             db 0, 0
tiles_head:  times 6 db TILE_TNT_SIDE
             db 0, 0
align 4
zero_tiles:  db 0, 0, 0, 0, 0, 0, 0, 0
shades_flat: dd 1.0, 1.0, 1.0, 1.0, 1.0, 1.0
; magic projectiles: half edge of the cube and its colour
c_bolt_half: dd 0.09                    ; 0.18 cube
c_bolt_col:  dd 0.75, 0.4, 1.0
c_fire_half: dd 0.15                    ; 0.3 cube
c_fire_col:  dd 1.0, 0.55, 0.15
; throwing knife: a 0.12 cube of steel, drawn in the world pass like an arrow
knife_box:   dd -0.06, -0.06, -0.06,  0.06, 0.06, 0.06
c_knife_col: dd 0.75, 0.75, 0.8
; powder grenade: a 0.2 cube of TNT
grenade_box: dd -0.1, -0.1, -0.1,  0.1, 0.1, 0.1

section .bss
alignb 16
arrows:      resb MAX_ARROWS * ARROWENT_size
arrows_end:
arrow_net:   resd MAX_ARROWS            ; per projectile: ((owner peer + 1) << 8) | owner slot (owner peer 255 = the world's), the
                                        ; tag that pairs it with its twin on the other peers; 0 = not mirrored

section .text

; arrows_clear(): remove every arrow
arrows_clear:
    lea     rdi, [arrows]
    mov     ecx, MAX_ARROWS * ARROWENT_size
    xor     eax, eax
    rep     stosb
    lea     rdi, [arrow_net]
    mov     ecx, MAX_ARROWS * 4
    rep     stosb
    ret

; arrows_spawn(xmm0 x, xmm1 y, xmm2 z, xmm3 vx, xmm4 vy, xmm5 vz, edi owner, esi damage,
;              edx pickup, ecx kind, r8d flags) -> eax slot index, or -1 when every slot is in use
; owner: OWNER_PLAYER, OWNER_MONSTER or OWNER_FOLK + the faction of the folk that shot. kind:
; PROJ_ARROW .. PROJ_GRENADE. flags: AF_* (a player's weapon projectile carries its element in bits
; AF_ELEM_SHIFT.. and AF_ATTACK, AF_CRIT, AF_BLEED; AF_NOWIN: a bow arrow that ignores the mob hurt
; window; AF_FLASH: a grenade that flashes instead of burning). damage is the base the damage pipeline
; scales when it lands (a bullet's, a bolt's, a grenade's blast). Velocities are blocks per second.
; In multiplayer a player's projectile (on the host a monster's or a folk's too) is sent to the other peers (net_proj_out)
; unless it is a ghost (AF_GHOST) or a message is being applied; arrow_net[slot] stays 0 for a projectile that is not.
arrows_spawn:
    lea     r9, [arrows]
    xor     eax, eax
.find:
    cmp     dword [r9 + ARROWENT.live], 0
    je      .found
    add     r9, ARROWENT_size
    inc     eax
    cmp     eax, MAX_ARROWS
    jb      .find
    mov     eax, -1
    ret
.found:
    movss   [r9 + ARROWENT.x], xmm0
    movss   [r9 + ARROWENT.y], xmm1
    movss   [r9 + ARROWENT.z], xmm2
    movss   [r9 + ARROWENT.vx], xmm3
    movss   [r9 + ARROWENT.vy], xmm4
    movss   [r9 + ARROWENT.vz], xmm5
    mov     dword [r9 + ARROWENT.age], 0
    mov     dword [r9 + ARROWENT.stuck], 0
    mov     [r9 + ARROWENT.owner], edi
    mov     [r9 + ARROWENT.damage], esi
    mov     [r9 + ARROWENT.pickup], edx
    mov     [r9 + ARROWENT.kind], ecx
    mov     [r9 + ARROWENT.flags], r8d
    mov     dword [r9 + ARROWENT.live], 1
    lea     rcx, [arrow_net]
    mov     dword [rcx + rax*4], 0      ; not mirrored (net_proj_out tags the ones that are)
    cmp     byte [net_role], NET_ROLE_OFF
    je      .done
    cmp     byte [net_applying], 0
    jne     .done                       ; a ghost, or anything else a message made, is not sent back
    test    r8d, AF_GHOST
    jnz     .done
    test    edi, edi
    jz      .mirror                     ; the player's projectile: every peer shows it
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .done                       ; a monster's or a folk's exists only on the host
.mirror:
    push    rax
    mov     edi, eax
    call    net_proj_out
    pop     rax
.done:
    ret

; arrow_advance(rdi arrow, rsi dir[3], xmm0 t, rdx out[3]): out = arrow position + dir * t.
; out may be the arrow itself.
arrow_advance:
    movss   xmm1, [rsi]
    mulss   xmm1, xmm0
    addss   xmm1, [rdi + ARROWENT.x]
    movss   [rdx], xmm1
    movss   xmm1, [rsi + 4]
    mulss   xmm1, xmm0
    addss   xmm1, [rdi + ARROWENT.y]
    movss   [rdx + 4], xmm1
    movss   xmm1, [rsi + 8]
    mulss   xmm1, xmm0
    addss   xmm1, [rdi + ARROWENT.z]
    movss   [rdx + 8], xmm1
    ret

; arrow_hdir(rdi arrow, rsi out[2]): the arrow's horizontal heading as a unit vector (x, z);
; (0, 0) when it is flying straight up or down
arrow_hdir:
    movss   xmm0, [rdi + ARROWENT.vx]
    movss   xmm1, [rdi + ARROWENT.vz]
    movaps  xmm2, xmm0
    mulss   xmm2, xmm2
    movaps  xmm3, xmm1
    mulss   xmm3, xmm3
    addss   xmm2, xmm3
    sqrtss  xmm2, xmm2
    comiss  xmm2, [c_hdir_min]
    jae     .unit
    xorps   xmm0, xmm0
    xorps   xmm1, xmm1
    jmp     .store
.unit:
    divss   xmm0, xmm2
    divss   xmm1, xmm2
.store:
    movss   [rsi], xmm0
    movss   [rsi + 4], xmm1
    ret

; HIT_POINT: S_HP = arrow position + dir * S_T, S_H = unit horizontal heading
%macro HIT_POINT 0
    mov     rdi, rbx
    lea     rsi, [rsp + S_DIR]
    movss   xmm0, [rsp + S_T]
    lea     rdx, [rsp + S_HP]
    call    arrow_advance
    mov     rdi, rbx
    lea     rsi, [rsp + S_H]
    call    arrow_hdir
%endmacro

; arrows_step(): one fixed 1/60 s step for every arrow.
; Flying arrows and grenades fall under gravity along the segment they travel this step; the nearest of
; the first block, the first mob (the player's projectiles) or the player (a mob's arrows) on that
; segment ends the flight: a creature is hurt and the arrow vanishes, a block holds it (a knife,
; bullet or bolt just vanishes). Everything a player's projectile does to a mob goes through
; combat_hit_mob: a bullet as SRC_GUN, every bullet counts; a bow shot (AF_ATTACK) waits out the mob's
; hurt window unless it is AF_NOWIN (the Barrage's extra arrows), and a skill's arrows (Volley, Arrow
; Rain) never wait. A rocket goes off on a mob, on a block or when its time is up: explode_at, hurting
; mobs by the gun family (explode_mob_mult) in a radius Powder Keg widens by half. A grenade does so
; too: a fire blast (explode_magic, SRC_GUN_SKILL, the same widening), or with AF_FLASH ab_flash_at.
; An elemental mob arrow also afflicts the player. A folk's shot (owner >= OWNER_FOLK)
; also meets the folk of a rival faction nearer than the block (folk_hit_by); friends and monsters let
; it pass, and the player takes the rest with a death cause of its faction (CAUSE_FOLK + faction).
; Stuck arrows time out; the player walks over its own to pick it up again.
; Multiplayer: a ghost (AF_GHOST, the twin of another peer's projectile) only flies and meets blocks: a plain arrow sticks
; for a second, anything else ends there; it never hits, explodes, sounds or is picked up. A player's own projectile also
; meets the other players when PvP is on (net_players_raycast; the nearest of mob, player and block wins; the blow is
; combat_hit_player's: a fireball or an explosive arrow that meets one burns him with SRC_SPELL / SRC_RANGED_SKILL and then
; bursts as ever, the blast sparing players). On the host the shots of monsters and folk meet the remote players too
; (net_hurt_send). A step ends by telling the others which real projectiles ended (arrows_net_sweep).
; rbx = arrow, r12 = end of the table
arrows_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, S_FRAME
    lea     rbx, [arrows]
    lea     r12, [arrows_end]
.loop:
    cmp     dword [rbx + ARROWENT.live], 0
    je      .next
    cmp     dword [rbx + ARROWENT.stuck], 0
    jne     .stuck

    ; ---- flying: lifetime, gravity (arrows and grenades), then the segment v / 60 ----------
    inc     dword [rbx + ARROWENT.age]
    mov     eax, [rbx + ARROWENT.age]
    mov     ecx, [rbx + ARROWENT.kind]
    lea     rdx, [max_age]
    cmp     eax, [rdx + rcx*4]
    ja      .expired
    cmp     ecx, PROJ_ARROW
    je      .gravity
    cmp     ecx, PROJ_GRENADE
    jne     .no_gravity
.gravity:
    movss   xmm0, [rbx + ARROWENT.vy]
    subss   xmm0, [c_gravity]
    movss   [rbx + ARROWENT.vy], xmm0
.no_gravity:
    movss   xmm4, [c_dt]
    movss   xmm0, [rbx + ARROWENT.vx]
    mulss   xmm0, xmm4
    movss   [rsp + S_SEG], xmm0
    movss   xmm1, [rbx + ARROWENT.vy]
    mulss   xmm1, xmm4
    movss   [rsp + S_SEG + 4], xmm1
    movss   xmm2, [rbx + ARROWENT.vz]
    mulss   xmm2, xmm4
    movss   [rsp + S_SEG + 8], xmm2
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    mulss   xmm2, xmm2
    addss   xmm0, xmm1
    addss   xmm0, xmm2
    sqrtss  xmm0, xmm0
    movss   [rsp + S_LEN], xmm0
    comiss  xmm0, [c_tiny]
    jbe     .next                       ; not moving (or NaN): nothing to sweep
    movaps  xmm1, xmm0
    movss   xmm0, [rsp + S_SEG]
    divss   xmm0, xmm1
    movss   [rsp + S_DIR], xmm0
    movss   xmm0, [rsp + S_SEG + 4]
    divss   xmm0, xmm1
    movss   [rsp + S_DIR + 4], xmm0
    movss   xmm0, [rsp + S_SEG + 8]
    divss   xmm0, xmm1
    movss   [rsp + S_DIR + 8], xmm0

    ; ---- the first block on the segment ---------------------------------------
    mov     rdi, rbx                    ; x, y, z lead the record: a float[3] origin
    lea     rsi, [rsp + S_DIR]
    lea     rdx, [rsp + S_HIT]
    movss   xmm0, [rsp + S_LEN]
    call    raycast
    mov     [rsp + S_BLK], eax
    movss   [rsp + S_TMAX], xmm0        ; where the segment meets a block (its whole length: none)

    ; ---- a creature nearer than the block ----------------------------------------
.creature:
    test    dword [rbx + ARROWENT.flags], AF_GHOST
    jnz     .settle                     ; a ghost hits nothing: its owner's machine decides
    mov     eax, [rbx + ARROWENT.owner]
    test    eax, eax
    jnz     .mob_shot
    mov     dword [rsp + S_WHO], -1
    mov     rdi, rbx
    lea     rsi, [rsp + S_DIR]
    movss   xmm0, [rsp + S_TMAX]
    call    mobs_raycast
    mov     [rsp + S_IDX], eax
    cmp     byte [net_role], NET_ROLE_OFF
    je      .mob_only
    movss   xmm1, [rsp + S_TMAX]        ; another player (PvP) counts when nearer than the mob, else than the block
    test    eax, eax
    js      .player_ray
    movaps  xmm1, xmm0
.player_ray:
    movss   [rsp + S_T], xmm1
    movaps  xmm0, xmm1
    mov     rdi, rbx
    lea     rsi, [rsp + S_DIR]
    call    net_players_raycast         ; eax = slot or -1 (always -1 with PvP off), xmm0 = his distance
    test    eax, eax
    js      .no_player
    mov     [rsp + S_WHO], eax
    movss   [rsp + S_T], xmm0
    jmp     .target
.no_player:
    cmp     dword [rsp + S_IDX], 0
    jl      .settle                     ; nobody in front of the block
    jmp     .target                     ; the mob (S_T is its distance)
.mob_only:
    test    eax, eax
    js      .settle                     ; no mob in front of the block
    movss   [rsp + S_T], xmm0
.target:
    HIT_POINT
    mov     eax, [rbx + ARROWENT.kind]
    cmp     eax, PROJ_ROCKET
    je      .rocket_burst               ; a rocket goes off on the mob
    cmp     eax, PROJ_FIREBALL
    je      .magic_target               ; so does a fireball...
    test    dword [rbx + ARROWENT.flags], AF_EXPLOSIVE
    jnz     .magic_target               ; ...and an explosive arrow
    cmp     eax, PROJ_GRENADE
    je      .grenade_burst              ; ...and a grenade
    mov     r8d, [rbx + ARROWENT.flags] ; the player's weapon projectile: the damage pipeline decides
    mov     edx, r8d
    shr     edx, AF_ELEM_SHIFT
    and     edx, HITF_ELEM_MASK         ; its element
    test    r8d, AF_CRIT
    jz      .no_crit
    or      edx, HITF_CRIT
.no_crit:
    test    r8d, AF_BLEED
    jz      .no_bleed
    or      edx, HITF_BLEED
.no_bleed:
    mov     esi, SRC_MELEE_SKILL        ; a knife
    cmp     eax, PROJ_KNIFE
    je      .hit
    mov     esi, SRC_GUN                ; a bullet: never inside the hurt window, every bullet counts
    cmp     eax, PROJ_BULLET
    je      .hit
    cmp     eax, PROJ_ARROW
    je      .arrow
    mov     esi, SRC_SPELL              ; a bolt: a staff's (an attack) or a skill's
    test    r8d, AF_ATTACK
    jz      .hit
    mov     esi, SRC_BOLT
    jmp     .hit
.arrow:
    mov     esi, SRC_RANGED_SKILL       ; a skill's arrow (Volley, Arrow Rain) always lands
    test    r8d, AF_ATTACK
    jz      .hit
    mov     esi, SRC_BOW                ; a bow shot cannot hit again inside the hurt window, but
    test    r8d, AF_NOWIN               ; the Barrage's extra arrows (AF_NOWIN) land anyway
    jnz     .hit
    or      edx, HITF_HURTWIN
.hit:
    mov     edi, [rsp + S_IDX]
    cvtsi2ss xmm0, dword [rbx + ARROWENT.damage]
    movss   xmm1, [rsp + S_H]
    movss   xmm2, [rsp + S_H + 4]
    mov     eax, [rsp + S_WHO]
    test    eax, eax
    js      .hit_mob
    mov     edi, eax                    ; a player (PvP): the shooter's damage pipeline, the blow goes through the host
    and     edx, ~HITF_HURTWIN          ; (his hurt window is the invulnerability after a hit)
    call    combat_hit_player
    jmp     .impact
.hit_mob:
    call    combat_hit_mob
    jmp     .impact
.magic_target:                          ; a fireball or an explosive arrow met a creature: a player (PvP) takes the hit itself,
    mov     edi, [rsp + S_WHO]          ; as a bow arrow would (the blast that follows, like every spell's, spares players)
    test    edi, edi
    js      .magic_burst
    mov     esi, SRC_SPELL              ; a fireball is a spell...
    cmp     dword [rbx + ARROWENT.kind], PROJ_FIREBALL
    je      .magic_hit
    mov     esi, SRC_RANGED_SKILL       ; ...an explosive arrow a ranged skill
.magic_hit:
    mov     edx, ELEM_FIRE              ; both burn
    test    dword [rbx + ARROWENT.flags], AF_CRIT
    jz      .magic_hit_go
    or      edx, HITF_CRIT
.magic_hit_go:
    cvtsi2ss xmm0, dword [rbx + ARROWENT.damage]
    movss   xmm1, [rsp + S_H]
    movss   xmm2, [rsp + S_H + 4]
    call    combat_hit_player
    jmp     .magic_burst
.mob_shot:
    cmp     eax, OWNER_FOLK
    jb      .player_arrow               ; a monster's shot: only the player is in its way
    mov     rdi, rbx                    ; a folk's: a rival folk before the block takes it
    lea     rsi, [rsp + S_DIR]
    movss   xmm0, [rsp + S_TMAX]
    call    mobs_raycast
    test    eax, eax
    js      .player_arrow
    mov     [rsp + S_IDX], eax
    movss   [rsp + S_T], xmm0
    imul    ecx, eax, MOB_size
    lea     rdx, [mobs]
    add     rdx, rcx                    ; the nearest mob
    cmp     dword [rdx + MOB.type], MOB_FOLK
    je      .folk_target
    mov     ecx, [rdx + MOB.patrol]     ; a monster: only an event's attacker (patrol & 3 == 2) is an enemy of a folk's arrow
    and     ecx, 3
    cmp     ecx, 2
    je      .hit_folk_shot
    jmp     .player_arrow
.folk_target:
    mov     edi, [rbx + ARROWENT.owner]
    sub     edi, OWNER_FOLK             ; the shooter's faction
    movzx   esi, byte [rdx + MOB.faction]
    call    faction_enemies
    test    eax, eax
    jz      .player_arrow               ; a friend: the shot flies on
.hit_folk_shot:
    HIT_POINT
    mov     edi, [rsp + S_IDX]
    mov     esi, [rbx + ARROWENT.damage]
    mov     edx, [rbx + ARROWENT.flags]
    shr     edx, AF_ELEM_SHIFT
    and     edx, HITF_ELEM_MASK         ; its element
    movss   xmm0, [rsp + S_H]
    movss   xmm1, [rsp + S_H + 4]
    call    folk_hit_by
    jmp     .impact

.player_arrow:
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .settle                     ; nobody to hit in Creative
    mov     dword [rsp + S_WHO], -1
    movss   xmm0, [rsp + S_TMAX]
    movss   [rsp + S_T], xmm0           ; the nearest hit so far: the block (or the whole step)
    cmp     dword [surv + SURVIVAL.dead], 0
    jne     .others
    movss   xmm0, [player + BODY.x]     ; the player's box
    movss   xmm1, [c_half_w]
    movaps  xmm2, xmm0
    subss   xmm0, xmm1
    addss   xmm2, xmm1
    movss   [rsp + S_LO], xmm0
    movss   [rsp + S_HI], xmm2
    movss   xmm0, [player + BODY.z]
    movaps  xmm2, xmm0
    subss   xmm0, xmm1
    addss   xmm2, xmm1
    movss   [rsp + S_LO + 8], xmm0
    movss   [rsp + S_HI + 8], xmm2
    movss   xmm0, [player + BODY.y]
    movss   [rsp + S_LO + 4], xmm0
    addss   xmm0, [c_height]
    movss   [rsp + S_HI + 4], xmm0
    mov     rdi, rbx
    lea     rsi, [rsp + S_DIR]
    lea     rdx, [rsp + S_LO]
    lea     rcx, [rsp + S_HI]
    movss   xmm0, [rsp + S_T]
    call    ray_aabb
    test    eax, eax
    jz      .others
    movss   [rsp + S_T], xmm0
    mov     dword [rsp + S_WHO], 0      ; the local player: slot 0 (the host, or offline)
.others:                                ; the host also meets the other players
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .victim
    mov     rdi, rbx
    lea     rsi, [rsp + S_DIR]
    movss   xmm0, [rsp + S_T]
    call    arrow_peer_hit              ; eax = slot or -1, xmm0 = his distance
    test    eax, eax
    js      .victim
    mov     [rsp + S_WHO], eax
    movss   [rsp + S_T], xmm0
.victim:
    cmp     dword [rsp + S_WHO], 0
    jl      .settle                     ; nobody in the way
    HIT_POINT
    movss   xmm2, [c_src_t]             ; the shot's source: 0.1 s back along its path
    movss   xmm0, [rbx + ARROWENT.vx]
    mulss   xmm0, xmm2
    movss   xmm3, [rbx + ARROWENT.x]
    subss   xmm3, xmm0
    movss   xmm1, [rbx + ARROWENT.vz]
    mulss   xmm1, xmm2
    movss   xmm4, [rbx + ARROWENT.z]
    subss   xmm4, xmm1
    movss   [rsp + S_SRC], xmm3         ; where the shot comes from (a remote player's blow needs it too)
    movss   [rsp + S_SRC + 4], xmm4
    cmp     dword [rsp + S_WHO], 0
    jne     .peer_hit
    movaps  xmm0, xmm3
    movaps  xmm1, xmm4
    mov     edi, [rbx + ARROWENT.damage]
    mov     esi, [rbx + ARROWENT.owner]
    add     esi, CAUSE_FOLK - OWNER_FOLK ; a folk's shot names its faction in the death cause...
    cmp     dword [rbx + ARROWENT.owner], OWNER_FOLK
    mov     eax, CAUSE_SKELETON
    cmovb   esi, eax                    ; ...a monster's is a skeleton's
    call    player_take_hit
    cmp     eax, HIT_TAKEN
    jne     .impact                     ; parried, blocked, dodged or invulnerable: spent anyway
    mov     eax, [rbx + ARROWENT.flags] ; an elemental arrow (an elite skeleton's) afflicts what it hits
    shr     eax, AF_ELEM_SHIFT
    and     eax, HITF_ELEM_MASK
    mov     edi, STS_BURN
    cmp     eax, ELEM_FIRE
    je      .afflict
    mov     edi, STS_CHILL
    cmp     eax, ELEM_FROST
    je      .afflict
    mov     edi, STS_POISON
    cmp     eax, ELEM_POISON
    jne     .shove
.afflict:
    mov     eax, [rbx + ARROWENT.damage]
    xor     edx, edx
    mov     ecx, 3
    div     ecx
    mov     esi, 1
    cmp     eax, esi
    cmovae  esi, eax                    ; max(1, damage / 3)
    call    combat_player_status
.shove:
    call    combat_kb_mult              ; Juggernaut takes no knockback
    movss   xmm1, [rsp + S_H]           ; shoved along the arrow's heading
    mulss   xmm1, [c_kb]
    mulss   xmm1, xmm0
    movss   [player + BODY.kbx], xmm1
    movss   xmm1, [rsp + S_H + 4]
    mulss   xmm1, [c_kb]
    mulss   xmm1, xmm0
    movss   [player + BODY.kbz], xmm1

    ; ---- a creature was hit: sound at the hit point, the arrow is gone ----------------
.impact:
    mov     edi, SND_ARROW_HIT
    movss   xmm0, [rsp + S_HP]
    movss   xmm1, [rsp + S_HP + 4]
    movss   xmm2, [rsp + S_HP + 8]
    movss   xmm3, [c_hit_vol]
    call    audio_play_at
    jmp     .remove

    ; ---- a remote player was hit (the host: a monster's or a folk's shot): the blow goes to his machine --------------
.peer_hit:
    mov     r8d, 255                    ; no status...
    xor     r9d, r9d
    mov     eax, [rbx + ARROWENT.flags] ; ...unless an elemental arrow (an elite skeleton's) afflicts him, as it would
    shr     eax, AF_ELEM_SHIFT          ; the local player
    and     eax, HITF_ELEM_MASK
    mov     edi, STS_BURN
    cmp     eax, ELEM_FIRE
    je      .peer_afflict
    mov     edi, STS_CHILL
    cmp     eax, ELEM_FROST
    je      .peer_afflict
    mov     edi, STS_POISON
    cmp     eax, ELEM_POISON
    jne     .peer_send
.peer_afflict:
    mov     r8d, edi
    mov     eax, [rbx + ARROWENT.damage]
    xor     edx, edx
    mov     ecx, 3
    div     ecx
    mov     r9d, 1
    cmp     eax, r9d
    cmovae  r9d, eax                    ; max(1, damage / 3)
.peer_send:
    mov     edi, [rsp + S_WHO]          ; slot
    mov     esi, [rbx + ARROWENT.damage]
    mov     edx, [rbx + ARROWENT.owner]
    add     edx, CAUSE_FOLK - OWNER_FOLK ; the death cause as for the local player: a folk's faction, else a skeleton
    cmp     dword [rbx + ARROWENT.owner], OWNER_FOLK
    mov     eax, CAUSE_SKELETON
    cmovb   edx, eax
    mov     ecx, 255                    ; no mob to stun when he parries
    movss   xmm0, [rsp + S_SRC]
    movss   xmm1, [rsp + S_SRC + 4]
    movss   xmm2, [c_kb]
    xorps   xmm3, xmm3
    call    net_hurt_send
    jmp     .impact

    ; ---- no creature: the block holds an arrow, stops a bullet, sets off a rocket; else
    ; the projectile flies on --------------------------------------------------------
.settle:
    cmp     dword [rsp + S_BLK], 0
    je      .fly
    test    dword [rbx + ARROWENT.flags], AF_GHOST
    jnz     .ghost_block
    mov     eax, [rbx + ARROWENT.kind]
    cmp     eax, PROJ_BULLET
    je      .bullet_block
    cmp     eax, PROJ_KNIFE
    je      .bullet_block               ; a knife is spent on the surface, too
    cmp     eax, PROJ_ROCKET
    je      .rocket_block
    cmp     eax, PROJ_GRENADE
    je      .grenade_block
    cmp     eax, PROJ_FIREBALL
    je      .magic_block
    cmp     eax, PROJ_BOLT
    je      .bolt_block
    test    dword [rbx + ARROWENT.flags], AF_EXPLOSIVE
    jnz     .magic_block                ; an explosive arrow never sticks
    mov     rdi, rbx
    lea     rsi, [rsp + S_DIR]
    movss   xmm0, [rsp + S_TMAX]
    subss   xmm0, [c_embed]
    mov     rdx, rbx
    call    arrow_advance               ; stops just short of the surface
    mov     dword [rbx + ARROWENT.stuck], 1
    mov     edi, SND_ARROW_HIT
    movss   xmm0, [rbx + ARROWENT.x]
    movss   xmm1, [rbx + ARROWENT.y]
    movss   xmm2, [rbx + ARROWENT.z]
    movss   xmm3, [c_stick_vol]
    call    audio_play_at
    jmp     .next
.ghost_block:                           ; a ghost: a plain arrow sticks (quietly), everything else just ends
    cmp     dword [rbx + ARROWENT.kind], PROJ_ARROW
    jne     .remove
    test    dword [rbx + ARROWENT.flags], AF_EXPLOSIVE
    jnz     .remove
    mov     rdi, rbx
    lea     rsi, [rsp + S_DIR]
    movss   xmm0, [rsp + S_TMAX]
    subss   xmm0, [c_embed]
    mov     rdx, rbx
    call    arrow_advance               ; stops just short of the surface
    mov     dword [rbx + ARROWENT.stuck], 1
    jmp     .next
.bullet_block:                          ; the bullet is spent on the surface
    movss   xmm0, [rsp + S_TMAX]
    movss   [rsp + S_T], xmm0
    HIT_POINT
    mov     edi, SND_ARROW_HIT
    movss   xmm0, [rsp + S_HP]
    movss   xmm1, [rsp + S_HP + 4]
    movss   xmm2, [rsp + S_HP + 8]
    movss   xmm3, [c_bullet_vol]
    call    audio_play_at
    jmp     .remove
.rocket_block:                          ; just short of the surface it hit
    movss   xmm0, [rsp + S_TMAX]
    subss   xmm0, [c_embed]
    movss   [rsp + S_T], xmm0
    HIT_POINT
.rocket_burst:                          ; S_HP = where it goes off; freed before the blast
    mov     dword [rbx + ARROWENT.live], 0
    mov     edi, -1                     ; the blast hurts mobs by what a bullet's base 1 would do:
    mov     esi, SRC_GUN                ; GUN_DMG and ALL_DMG scale it (explode_mob_mult)
    xor     edx, edx
    movss   xmm0, [f_one]
    call    combat_calc
    movss   [explode_mob_mult], xmm0
    movss   xmm3, [c_rocket_r]
    test    dword [rpg_keystones], 1 << KS_POWDER_KEG
    jz      .rocket_go
    mulss   xmm3, [c_keg]               ; Powder Keg: 50 % wider
.rocket_go:
    movss   xmm0, [rsp + S_HP]
    movss   xmm1, [rsp + S_HP + 4]
    movss   xmm2, [rsp + S_HP + 8]
    mov     byte [explode_pvp], 1       ; a player's rocket: the other players feel the blast when PvP is on
    call    explode_at
    mov     byte [explode_pvp], 0
    mov     dword [explode_mob_mult], __float32__(1.0)
    jmp     .next
.grenade_block:                         ; just short of the surface it hit, like a rocket
    movss   xmm0, [rsp + S_TMAX]
    subss   xmm0, [c_embed]
    movss   [rsp + S_T], xmm0
    HIT_POINT
.grenade_burst:                         ; S_HP = where it goes off; freed before the burst
    mov     dword [rbx + ARROWENT.live], 0
    test    dword [rbx + ARROWENT.flags], AF_FLASH
    jz      .grenade_fire
    movss   xmm0, [rsp + S_HP]          ; a flashbang: no damage, the foes around the point are stunned
    movss   xmm1, [rsp + S_HP + 4]
    movss   xmm2, [rsp + S_HP + 8]
    call    ab_flash_at
    jmp     .next
.grenade_fire:                          ; a powder grenade: a fire blast with the damage it was thrown with
    mov     edi, [rbx + ARROWENT.damage]
    movss   xmm3, [c_grenade_r]
    test    dword [rpg_keystones], 1 << KS_POWDER_KEG
    jz      .grenade_go
    mulss   xmm3, [c_keg]               ; Powder Keg: 50 % wider
.grenade_go:
    movss   [rsp + S_RAD], xmm3
    mov     esi, SRC_GUN_SKILL
    mov     edx, ELEM_FIRE
    test    dword [rbx + ARROWENT.flags], AF_CRIT
    jz      .grenade_fx
    or      edx, HITF_CRIT
.grenade_fx:
    movss   xmm0, [rsp + S_HP]
    movss   xmm1, [rsp + S_HP + 4]
    movss   xmm2, [rsp + S_HP + 8]
    call    explode_magic
    cmp     byte [net_role], NET_ROLE_OFF
    je      .next
    movss   xmm0, [rsp + S_HP]          ; in multiplayer the grenade's blast also hurts the other players (PvP only)
    movss   xmm1, [rsp + S_HP + 4]
    movss   xmm2, [rsp + S_HP + 8]
    movss   xmm3, [rsp + S_RAD]
    mov     byte [explode_pvp], 1
    call    net_explosion_players
    mov     byte [explode_pvp], 0
    jmp     .next
.magic_block:                           ; a fireball or explosive arrow: just short of the surface
    movss   xmm0, [rsp + S_TMAX]
    subss   xmm0, [c_embed]
    movss   [rsp + S_T], xmm0
    HIT_POINT
.magic_burst:                           ; S_HP = where it goes off; freed before the blast
    mov     dword [rbx + ARROWENT.live], 0
    mov     edi, [rbx + ARROWENT.damage]
    movss   xmm3, [c_magic_r]
    test    dword [rbx + ARROWENT.flags], AF_BIG
    jz      .magic_go
    movss   xmm3, [c_magic_big]
.magic_go:
    mov     esi, SRC_SPELL              ; a fireball is a spell...
    cmp     dword [rbx + ARROWENT.kind], PROJ_FIREBALL
    je      .magic_src
    mov     esi, SRC_RANGED_SKILL       ; ...an explosive arrow a ranged skill
.magic_src:
    mov     edx, ELEM_FIRE              ; both burn
    test    dword [rbx + ARROWENT.flags], AF_CRIT
    jz      .magic_fire
    or      edx, HITF_CRIT
.magic_fire:
    movss   xmm0, [rsp + S_HP]
    movss   xmm1, [rsp + S_HP + 4]
    movss   xmm2, [rsp + S_HP + 8]
    call    explode_magic
    jmp     .next
.bolt_block:                            ; a bolt bursts into sparks just short of the surface
    movss   xmm0, [rsp + S_TMAX]
    subss   xmm0, [c_embed]
    movss   [rsp + S_T], xmm0
    HIT_POINT
    movss   xmm0, [rsp + S_HP]
    movss   xmm1, [rsp + S_HP + 4]
    movss   xmm2, [rsp + S_HP + 8]
    movss   xmm3, [c_burst_v]
    mov     edi, FX_MAGIC
    mov     esi, 6
    call    fx_burst
    jmp     .remove
.expired:                               ; out of time: an arrow, bullet or bolt vanishes,
    test    dword [rbx + ARROWENT.flags], AF_GHOST
    jnz     .remove                     ; a ghost never goes off: the real one did, where it was
    mov     eax, [rbx + ARROWENT.kind]
    cmp     eax, PROJ_ROCKET
    je      .go_off
    cmp     eax, PROJ_GRENADE
    je      .go_off
    cmp     eax, PROJ_FIREBALL
    jne     .remove
.go_off:                                ; a rocket, grenade or fireball goes off where it is
    mov     eax, [rbx + ARROWENT.x]
    mov     [rsp + S_HP], eax
    mov     eax, [rbx + ARROWENT.y]
    mov     [rsp + S_HP + 4], eax
    mov     eax, [rbx + ARROWENT.z]
    mov     [rsp + S_HP + 8], eax
    cmp     dword [rbx + ARROWENT.kind], PROJ_ROCKET
    je      .rocket_burst
    cmp     dword [rbx + ARROWENT.kind], PROJ_GRENADE
    je      .grenade_burst
    jmp     .magic_burst
.fly:
    movss   xmm0, [rbx + ARROWENT.x]
    addss   xmm0, [rsp + S_SEG]
    movss   [rbx + ARROWENT.x], xmm0
    movss   xmm0, [rbx + ARROWENT.y]
    addss   xmm0, [rsp + S_SEG + 4]
    movss   [rbx + ARROWENT.y], xmm0
    movss   xmm1, [c_out_y]
    comiss  xmm1, xmm0
    ja      .remove                     ; fell out of the world
    movss   xmm0, [rbx + ARROWENT.z]
    addss   xmm0, [rsp + S_SEG + 8]
    movss   [rbx + ARROWENT.z], xmm0
    mov     eax, [rbx + ARROWENT.kind]  ; magic leaves a trail: one mote or ember per step, from
    cmp     dword [rbx + ARROWENT.age], TRAIL_DELAY ; a few steps out so none hangs before the eye
    jbe     .next
    mov     edi, FX_MAGIC
    cmp     eax, PROJ_BOLT
    je      .trail
    mov     edi, FX_FIRE
    cmp     eax, PROJ_FIREBALL
    jne     .next
.trail:
    cmp     byte [net_role], NET_ROLE_OFF
    je      .trail_fx
    movzx   eax, byte [net_applying]
    mov     [rsp + S_APPLY], eax
    mov     byte [net_applying], 1      ; every peer draws the trail of the ghost he sees: it is not sent
.trail_fx:
    movss   xmm0, [rbx + ARROWENT.x]
    movss   xmm1, [rbx + ARROWENT.y]
    movss   xmm2, [rbx + ARROWENT.z]
    movss   xmm3, [c_trail_v]
    mov     esi, 1
    call    fx_burst
    cmp     byte [net_role], NET_ROLE_OFF
    je      .next
    mov     eax, [rsp + S_APPLY]
    mov     [net_applying], al
    jmp     .next

    ; ---- stuck in a block -----------------------------------------------------------
.stuck:
    inc     dword [rbx + ARROWENT.stuck]
    mov     eax, [rbx + ARROWENT.stuck]
    test    dword [rbx + ARROWENT.flags], AF_GHOST
    jnz     .stuck_mob                  ; a ghost stays a second and is never picked up
    cmp     dword [rbx + ARROWENT.owner], 0
    jne     .stuck_mob
    cmp     eax, STUCK_OWN_STEPS
    ja      .remove
    cmp     dword [rbx + ARROWENT.pickup], 0
    je      .next
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .next
    cmp     dword [surv + SURVIVAL.dead], 0
    jne     .next
    movss   xmm0, [rbx + ARROWENT.x]
    subss   xmm0, [player + BODY.x]
    mulss   xmm0, xmm0
    movss   xmm1, [rbx + ARROWENT.z]
    subss   xmm1, [player + BODY.z]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [c_pick_r2]
    jae     .next
    movss   xmm0, [rbx + ARROWENT.y]
    subss   xmm0, [player + BODY.y]
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jb      .next                       ; below the player's feet
    comiss  xmm0, [c_pick_hi]
    ja      .next
    mov     edi, ARROW
    mov     esi, 1
    call    inv_add
    test    eax, eax
    jnz     .next                       ; inventory full: it stays in the block
    mov     edi, SND_POP
    movss   xmm0, [c_pop_vol]
    call    audio_play
    jmp     .remove
.stuck_mob:
    cmp     eax, STUCK_MOB_STEPS
    jbe     .next
.remove:
    mov     dword [rbx + ARROWENT.live], 0
.next:
    add     rbx, ARROWENT_size
    cmp     rbx, r12
    jb      .loop
    cmp     byte [net_role], NET_ROLE_OFF
    je      .done
    call    arrows_net_sweep
.done:
    add     rsp, S_FRAME
    pop     r12
    pop     rbx
    pop     rbp
    ret

; arrow_peer_hit(rdi arrow, rsi dir float[3], xmm0 max) -> eax the nearest remote player (slot 1..7) the arrow's step meets
; within max blocks, -1 for none; xmm0 = his distance. Host only: a peer's proxy body (net_peers) is his box, 0.6 x 1.8.
; rbx = peer record, r12d = slot, r13 = arrow, r14 = dir; frame: lo[3] @0, hi[3] @12, nearest distance @24, its slot @28
arrow_peer_hit:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 32
    mov     r13, rdi
    mov     r14, rsi
    movss   [rsp + 24], xmm0
    mov     dword [rsp + 28], -1
    mov     r12d, 1                     ; slot 0 is the host's own player: the caller's
.slot:
    imul    eax, r12d, PEER_size
    lea     rbx, [net_peers]
    add     rbx, rax
    cmp     dword [rbx + PEER.state], PEER_READY
    jne     .next
    test    word [rbx + PEER.ps + PSTATE.flags], PS_DEAD
    jnz     .next
    movss   xmm1, [c_half_w]
    movss   xmm0, [rbx + PEER.body + BODY.x]
    movaps  xmm2, xmm0
    subss   xmm0, xmm1
    addss   xmm2, xmm1
    movss   [rsp], xmm0
    movss   [rsp + 12], xmm2
    movss   xmm0, [rbx + PEER.body + BODY.z]
    movaps  xmm2, xmm0
    subss   xmm0, xmm1
    addss   xmm2, xmm1
    movss   [rsp + 8], xmm0
    movss   [rsp + 20], xmm2
    movss   xmm0, [rbx + PEER.body + BODY.y]
    movss   [rsp + 4], xmm0
    addss   xmm0, [c_height]
    movss   [rsp + 16], xmm0
    mov     rdi, r13
    mov     rsi, r14
    lea     rdx, [rsp]
    lea     rcx, [rsp + 12]
    movss   xmm0, [rsp + 24]
    call    ray_aabb
    test    eax, eax
    jz      .next
    movss   [rsp + 24], xmm0
    mov     [rsp + 28], r12d
.next:
    inc     r12d
    cmp     r12d, NET_MAX_PEERS
    jb      .slot
    mov     eax, [rsp + 28]
    movss   xmm0, [rsp + 24]
    add     rsp, 32
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; arrows_net_sweep(): at the end of a step, in multiplayer: a projectile that ended (live = 0) while it carried a network tag
; is announced to the others when it was the real one (net_proj_end_out clears the tag); a ghost just forgets its tag.
; rbx = the projectile, r12d = its slot
arrows_net_sweep:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    lea     rbx, [arrows]
    xor     r12d, r12d
.l:
    lea     rax, [arrow_net]
    cmp     dword [rax + r12*4], 0
    je      .next
    cmp     dword [rbx + ARROWENT.live], 0
    jne     .next
    test    dword [rbx + ARROWENT.flags], AF_GHOST
    jz      .real
    mov     dword [rax + r12*4], 0
    jmp     .next
.real:
    mov     edi, r12d
    call    net_proj_end_out
.next:
    add     rbx, ARROWENT_size
    inc     r12d
    cmp     r12d, MAX_ARROWS
    jb      .l
    pop     r12
    pop     rbx
    pop     rbp
    ret

; arrows_render(): every projectile, aimed along its velocity, with its kind's model. Arrows,
; bullets, rockets, knives and grenades are textured; bolts and fireballs are untextured cubes drawn in a second
; pass with texturing off on unit 0 and on unit 1, so they glow regardless of the hour (the
; texture state is restored). Called inside the world pass (atlas bound, alpha test on, night
; darkening active).
; rbx = arrow, r12 = end of the table, r13d = magic projectiles seen;
; [rsp] unit 0 was textured, [rsp + 4] unit 1 was, [rsp + 8] the cube's box float[6]
arrows_render:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 40
    xor     r13d, r13d
    lea     rbx, [arrows]
    lea     r12, [arrows_end]
.loop:
    cmp     dword [rbx + ARROWENT.live], 0
    je      .next
    cmp     dword [rbx + ARROWENT.kind], PROJ_KNIFE
    je      .model                      ; a knife is drawn with the arrows
    cmp     dword [rbx + ARROWENT.kind], PROJ_GRENADE
    je      .model                      ; and so is a grenade
    cmp     dword [rbx + ARROWENT.kind], PROJ_BOLT
    jb      .model
    inc     r13d                        ; magic: the second pass
    jmp     .next
.model:
    call    glPushMatrix
    movss   xmm0, [rbx + ARROWENT.x]
    movss   xmm1, [rbx + ARROWENT.y]
    movss   xmm2, [rbx + ARROWENT.z]
    call    glTranslatef
    movss   xmm0, [rbx + ARROWENT.vx]   ; heading: yaw = atan2(vx, -vz)
    xorps   xmm1, xmm1
    subss   xmm1, [rbx + ARROWENT.vz]
    call    atan2_deg
    xorps   xmm1, xmm1
    subss   xmm1, xmm0                  ; glRotatef(-yaw, 0, 1, 0)
    movaps  xmm0, xmm1
    xorps   xmm1, xmm1
    movss   xmm2, [f_one]
    xorps   xmm3, xmm3
    call    glRotatef
    movss   xmm0, [rbx + ARROWENT.vx]   ; pitch = atan2(vy, horizontal speed)
    mulss   xmm0, xmm0
    movss   xmm1, [rbx + ARROWENT.vz]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    sqrtss  xmm1, xmm0
    movss   xmm0, [rbx + ARROWENT.vy]
    call    atan2_deg
    movss   xmm1, [f_one]
    xorps   xmm2, xmm2
    xorps   xmm3, xmm3
    call    glRotatef                   ; glRotatef(pitch, 1, 0, 0)
    mov     eax, [rbx + ARROWENT.kind]
    cmp     eax, PROJ_BULLET
    je      .bullet
    cmp     eax, PROJ_ROCKET
    je      .rocket
    cmp     eax, PROJ_KNIFE
    je      .knife
    cmp     eax, PROJ_GRENADE
    je      .grenade
    lea     rdi, [arrow_shaft]
    lea     rsi, [tiles_shaft]
    call    draw_box
    lea     rdi, [arrow_tip]
    lea     rsi, [tiles_tip]
    call    draw_box
    lea     rdi, [arrow_fletch]
    lea     rsi, [tiles_fletch]
    call    draw_box
    jmp     .drawn
.bullet:
    lea     rdi, [bullet_box]
    lea     rsi, [tiles_brass]
    call    draw_box
    jmp     .drawn
.rocket:
    lea     rdi, [rocket_body]
    lea     rsi, [tiles_steel]
    call    draw_box
    lea     rdi, [rocket_head]
    lea     rsi, [tiles_head]
    call    draw_box
    lea     rdi, [rocket_fins]
    lea     rsi, [tiles_steel]
    call    draw_box
    jmp     .drawn
.knife:
    lea     rdi, [knife_box]
    lea     rsi, [tiles_steel]
    lea     rdx, [arrow_shades]
    movss   xmm0, [c_knife_col]
    movss   xmm1, [c_knife_col + 4]
    movss   xmm2, [c_knife_col + 8]
    call    render_box
    jmp     .drawn
.grenade:                               ; a cube of powder
    lea     rdi, [grenade_box]
    lea     rsi, [tiles_head]
    call    draw_box
.drawn:
    call    glPopMatrix
.next:
    add     rbx, ARROWENT_size
    cmp     rbx, r12
    jb      .loop
    test    r13d, r13d
    jz      .ret
    mov     edi, GL_TEXTURE_2D          ; ---- bolts and fireballs: flat and fullbright --------
    call    glIsEnabled
    movzx   eax, al
    mov     [rsp], eax
    mov     edi, GL_TEXTURE1
    call    glActiveTexture
    mov     edi, GL_TEXTURE_2D
    call    glIsEnabled
    movzx   eax, al
    mov     [rsp + 4], eax
    mov     edi, GL_TEXTURE_2D
    call    glDisable
    mov     edi, GL_TEXTURE0
    call    glActiveTexture
    mov     edi, GL_TEXTURE_2D
    call    glDisable
    lea     rbx, [arrows]
.magic:
    cmp     dword [rbx + ARROWENT.live], 0
    je      .magic_next
    mov     eax, [rbx + ARROWENT.kind]
    cmp     eax, PROJ_BOLT
    je      .bolt
    cmp     eax, PROJ_FIREBALL
    jne     .magic_next
    movss   xmm4, [c_fire_half]
    movss   xmm0, [c_fire_col]
    movss   xmm1, [c_fire_col + 4]
    movss   xmm2, [c_fire_col + 8]
    jmp     .cube
.bolt:
    movss   xmm4, [c_bolt_half]
    movss   xmm0, [c_bolt_col]
    movss   xmm1, [c_bolt_col + 4]
    movss   xmm2, [c_bolt_col + 8]
.cube:                                  ; the cube centred on the projectile, colour in xmm0..2
%assign i 0
%rep 3
    movss   xmm3, [rbx + ARROWENT.x + i]
    movaps  xmm5, xmm3
    subss   xmm3, xmm4
    addss   xmm5, xmm4
    movss   [rsp + 8 + i], xmm3
    movss   [rsp + 20 + i], xmm5
%assign i i + 4
%endrep
    lea     rdi, [rsp + 8]
    lea     rsi, [zero_tiles]
    lea     rdx, [shades_flat]
    call    render_box
.magic_next:
    add     rbx, ARROWENT_size
    cmp     rbx, r12
    jb      .magic
    cmp     dword [rsp], 0
    je      .unit1
    mov     edi, GL_TEXTURE_2D
    call    glEnable
.unit1:
    cmp     dword [rsp + 4], 0
    je      .ret
    mov     edi, GL_TEXTURE1
    call    glActiveTexture
    mov     edi, GL_TEXTURE_2D
    call    glEnable
    mov     edi, GL_TEXTURE0
    call    glActiveTexture
.ret:
    add     rsp, 40
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; draw_box(rdi box float[6], rsi tiles byte[6]): render_box with the arrow shades, untinted
draw_box:
    sub     rsp, 8
    lea     rdx, [arrow_shades]
    movss   xmm0, [f_one]
    movaps  xmm1, xmm0
    movaps  xmm2, xmm0
    call    render_box
    add     rsp, 8
    ret

; arrows_shift(edi dx, esi dz): the origin moved by (dx, dz) blocks: every live projectile's local x
; and z drop by that much (exact: dx and dz are multiples of 512)
arrows_shift:
    cvtsi2ss xmm0, edi
    cvtsi2ss xmm1, esi
    lea     rax, [arrows]
    lea     rcx, [arrows_end]
.l:
    cmp     dword [rax + ARROWENT.live], 0
    je      .next
    movss   xmm2, [rax + ARROWENT.x]
    subss   xmm2, xmm0
    movss   [rax + ARROWENT.x], xmm2
    movss   xmm2, [rax + ARROWENT.z]
    subss   xmm2, xmm1
    movss   [rax + ARROWENT.z], xmm2
.next:
    add     rax, ARROWENT_size
    cmp     rax, rcx
    jb      .l
    ret
