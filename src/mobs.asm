; mobs.asm - zombies, pigs, creepers, skeletons, spiders and chickens, faction folk (folk.asm
; holds their roles) and the Fallen King boss: slot storage, AI, spawning, ray/block queries,
; damage, drops, save records. Every mob has a level (the player's; a dungeon's two above, the
; crypt boss's at least 20) that scales its health and its blows on the player. Elites roll
; affixes: elemental parts in their blows, vampiric healing, speed, a juggernaut's stability.
; Mobs live in LOCAL coordinates: mobs_shift follows the origin, mobs_remove_box drops the mobs of
; a column that unloads, and a mob whose column is not ready stands frozen. Land mobs steer clear
; of water and lava and, once in a liquid, hold jump and float (in lava they burn too).
; A MOB starts with its BODY (MOB.body = 0), so a mob pointer is also a body pointer.
%include "common.inc"
default rel

global mobs, mob_count_type, mob_count_kind, mobs_clear, mobs_step, mobs_populate
global mob_spawn, mob_spawn_elite, mob_is_hostile, mobs_raycast
global mob_hurt, mob_strike, mobs_intersect_block, ray_aabb, mob_drops
global mobs_save, mobs_load, yaw_from, mobs_shift, mobs_remove_box, spawn_at_ground
global mob_level_for, mob_set_level, mob_dmg_mult, mob_resist, mob_affix_name
global make_elite, mob_scale, mob_blow, mob_blow_raw, mob_melee_hit, mob_arrow_flags, mob_index
global knock_player, mob_reel, mob_stunned_text, folk_strike_mob, mob_coins, mob_drop, spawn_near_player, mobs_spawn_tick
global mob_spawn_level, mob_tgt_slot, mob_tgt_body, mob_affix_status, mob_set_stun, mob_set_mark
global mob_launch, mob_replica_init

extern body_init, body_step, body_in_liquid, body_intersects_block, player
extern rng_next, sincos_deg, atan2_deg
extern world_top_y, world_get, world_column_ready, world_header, raycast, light_get, block_flags
extern world_origin_x, world_origin_z
extern sky_brightness, sky_is_night
extern drops_spawn, audio_play_at
extern settings, game_mode, game_time
extern arrows_spawn, explode_at, fx_explosion
extern combat_hit_flags
extern dmgnum_spawn, dmgnum_text, hud_banner
extern rpg_on_mob_killed, quests_on_boss_killed
extern structures_on_mob_killed, structures_on_boss_killed
extern rpg_level, rpg_stats
extern combat_player_status, combat_attacker, combat_kb_mult, status_speed_mult, explode_dmg_mult
extern gear_drop_from_mob
extern folk_ai, folk_hostile, folk_class_health, folk_base_speed, folk_is_fighter
extern folk_on_player_hit, folk_on_death, folk_drops, folk_scare, folk_travel_tick
extern events_step
extern status_apply
extern nm_ready_count, nm_centre, net_role, net_self, net_hit_peer, net_applying
extern net_nearest_target, net_nearest_dist2, net_mob_hit_player, net_mob_damage_out, net_kill_credit
extern net_stream_centres, net_event_out, net_mobfx_out, stream_rdist, structures_boss_reward

%define HOSTILE_CAP   12                ; hostile mobs the spawner keeps alive within 96 blocks of each player (c_far2)
%define HOSTILE_CAP_ALL 48              ; ...and over all the players together (MAX_MOBS is 64: the rest is for the animals and the folk)
%define SC_MAX        NET_MAX_PEERS     ; spawn centres: the local player and up to 7 guests
%define PIG_CAP       10                ; pigs the spawner keeps alive
%define CHICKEN_CAP   8                 ; chickens the spawner keeps alive
%define CHICKEN_START 6                 ; chickens a new world starts with
%define HURT_STEPS    10                ; mob_hurt invulnerability window
%define HIT_COOLDOWN  60                ; steps between zombie hits
%define PANIC_STEPS   180               ; a hurt pig or chicken runs this long
%define CREEPER_FUSE  90                ; steps from a lit fuse to the blast
%define ZOMBIE_WINDUP 20                ; steps a zombie's arm is up before the blow
%define ZOMBIE_WINDUP_ELITE 16
%define SPIDER_WINDUP 12                ; steps a spider rears up before the bite
%define SPIDER_WINDUP_ELITE 10
%define BAR_STEPS     180               ; a hit mob's health bar stays up this long
%define TAG_STEPS     200               ; a player hit counts for XP this long
%define BOSS_WINDUP   36                ; the Fallen King's slam wind-up (phase 3: 24)
%define BOSS_WINDUP_RAGE 24
%define BOSS_STUN     30                ; a parried slam stuns him this long
%define BOSS_COOLDOWN 70                ; steps between slams (phase 3: 45)
%define BOSS_COOLDOWN_RAGE 45
%define BOSS_SUMMON_STEPS 600           ; skeletons rise this often
%define BOSS_VOLLEY_STEPS 240           ; arrow volleys (phases 2 and 3) this often
%define BOSS_MAX_MINIONS 4              ; no summons while this many skeletons live
%define MOB_HP_STEP   0.15              ; health per level above 1, as a fraction of the base health
%define MOB_DMG_STEP  0.10              ; damage of a mob's blows per level above 1 (0.8 balance: 0.08 -> 0.10)
%define MOB_MAX_LEVEL 255               ; a save keeps the level in one byte
%define CRYPT_MIN_LEVEL 20              ; the crypt boss is at least this level
%define ELITE_TWO_AFFIXES 15            ; elites from this level on carry two affixes
%define NATURAL_ELITE_PCT 4             ; share of the night spawner's mobs that are elite
%define LAVA_STRIKE   4                 ; health a mob standing in lava loses ...
%define LAVA_PERIOD   10                ; ... every this many steps of game_time

; ELITE_DAMAGE reg32: damage x 1.5, rounded, when the mob at rbx is an elite (clobbers xmm7)
%macro ELITE_DAMAGE 1
    cmp     dword [rbx + MOB.elite], 0
    je      %%plain
    cvtsi2ss xmm7, %1
    mulss   xmm7, [c_1_5]
    cvtss2si %1, xmm7
%%plain:
%endmacro

; DEC_TIMER field: the step counter MOB.field of the mob at rbx counts down to 0 and stays there
%macro DEC_TIMER 1
    cmp     dword [rbx + %1], 0
    jle     %%zero
    dec     dword [rbx + %1]
%%zero:
%endmacro

; SWIFT_WINDUP reg32: a SWIFT elite (the mob at rbx) winds up in 3/4 of the steps
%macro SWIFT_WINDUP 1
    test    byte [rbx + MOB.affix], AFX_SWIFT
    jz      %%slow
    imul    %1, %1, 3
    shr     %1, 2
%%slow:
%endmacro

section .rodata
align 4
; per-type tables, index = type - 1 (zombie, pig, creeper, skeleton, spider, chicken, boss, folk)
t_half_w:   dd 0.3, 0.45, 0.3, 0.3, 0.7, 0.2, 0.6, 0.3
t_height:   dd 1.8, 0.9, 1.7, 1.8, 0.9, 0.7, 3.3, 1.95
t_speed:    dd 2.6, 1.6, 2.4, 2.5, 3.0, 1.4, 2.4, 1.0
t_run:      dd 0.0, 3.2, 0.0, 0.0, 0.0, 2.4, 0.0, 0.0     ; panic speed of the passive types
t_health:   dd 20, 10, 20, 20, 16, 4, 300, 20              ; (the boss's depends on the difficulty)
t_dmg:      dd 0, 2, 3, 4               ; zombie and skeleton hit by difficulty
t_dmg_spider: dd 0, 2, 2, 3
t_dmg_slam: dd 0, 6, 8, 12              ; the Fallen King's slam by difficulty
t_dmg_volley: dd 0, 3, 4, 5             ; ...and each arrow of his volley
t_boss_health: dd 200, 200, 300, 450
t_spread:   dd 0.0, 1.5, 1.0, 0.5       ; skeleton aim error in blocks/s by difficulty
t_hostile:  db 1, 0, 1, 1, 1, 0, 1, 0
t_burns:    db 1, 0, 0, 1, 0, 0, 0, 0   ; sunlight hurts the undead
t_say:      db SND_ZOMBIE_SAY, SND_PIG_SAY, 0xFF, SND_SKELETON_SAY, SND_SPIDER_SAY, SND_CHICKEN_SAY
            db SND_BOSS_ROAR, SND_VILLAGER
t_hurt:     db SND_ZOMBIE_HURT, SND_PIG_HURT, SND_CREEPER_HURT, SND_SKELETON_HURT
            db SND_SPIDER_HURT, SND_CHICKEN_HURT, SND_SKELETON_HURT, SND_VILLAGER
; death drops, 8 bytes per type: two (item, base, range) entries, count = base + rng % range;
; item 0 = unused entry. Folk and the boss have none here: mob_drops special-cases them (folk_drops).
t_drops:    db ROTTEN_FLESH, 0, 3, 0, 0, 0, 0, 0
            db PORKCHOP, 1, 3, 0, 0, 0, 0, 0
            db GUNPOWDER, 0, 3, 0, 0, 0, 0, 0
            db ARROW, 0, 3, 0, 0, 0, 0, 0
            db STRING, 0, 3, 0, 0, 0, 0, 0
            db FEATHER, 0, 3, RAW_CHICKEN, 1, 1, 0, 0
            db 0, 0, 0, 0, 0, 0, 0, 0
            db 0, 0, 0, 0, 0, 0, 0, 0
; an elite's affixes in its blows, by affix bit (MOLTEN, FROZEN, VENOMOUS, STORM): the element
; and its share of the physical damage
affix_elem:  db ELEM_FIRE, ELEM_FROST, ELEM_POISON, ELEM_SHOCK
align 4
affix_share: dd 0.5, 0.3, 0.3, 0.5
; the percent of each element's damage a type shrugs off (negative: it takes more, 100: immune),
; 5 bytes per type in the order of t_health, ELEM_PHYS..ELEM_POISON
t_resist:   db 0, -50, 0, 0, 25         ; zombie
            db 0, 0, 0, 0, 0            ; pig
            db 0, 0, -25, 50, 0         ; creeper
            db 0, 0, 25, 0, 100         ; skeleton
            db 0, -25, 0, 0, 100        ; spider
            db 0, 0, 0, 0, 0            ; chicken
            db 20, 20, 20, 20, 50       ; the Fallen King
            db 0, 0, 0, 0, 0            ; folk
; what the night spawner picks from
night_kinds: db MOB_ZOMBIE, MOB_SKELETON, MOB_CREEPER, MOB_SPIDER
align 8
hunt_ai:    dq 0, 0, ai_creeper, ai_skeleton, ai_spider, 0, ai_boss, 0   ; by type - 1; the zombie's AI is inline
align 4
c_360:      dd 360.0
c_180:      dd 180.0                    ; walk-cycle degrees per block walked
c_half:     dd 0.5
c_aggro2:   dd 576.0                    ; zombies notice the player within 24 blocks
c_hunt2:    dd 256.0                    ; creepers, skeletons and spiders within 16
c_reach2:   dd 2.89                     ; zombie hit range 1.7 blocks, squared
c_close2:   dd 1.21                     ; a zombie stops walking 1.1 blocks from the player, squared
c_bite2:    dd 1.96                     ; spider bite range 1.4 blocks, squared
c_far2:     dd 9216.0                   ; hostile mobs further than 96 blocks vanish
c_kb:       dd 6.0                      ; knockback speed
c_kb_spider: dd 5.0                     ; knockback of a spider's bite and leap
c_drop_dy:  dd 0.4                      ; porkchops pop out at mid-body height
c_tiny:     dd 0.0001
c_day:      dd 0.8                      ; brightness at which zombies burn
c_vol_say:  dd 0.7
c_vol_hurt: dd 1.0
c_glide:    dd -3.0                     ; slowest a chicken falls, blocks/s
c_load_xz:  dd 65536.0                  ; a saved mob lies within this many blocks of the origin...
c_load_y:   dd 256.0                    ; ...and below this height
c_water_dx: dd 0.7                      ; how far ahead a mob looks for water or lava
c_turn:     dd 180.0                    ; a mob that meets water or lava turns about
c_lava_burn: dd 24.0                    ; STS_BURN magnitude of a mob in lava (status_apply: a tick of 2 per 30 steps)
k_abs:      dd 0x7FFFFFFF               ; |x| mask (loaded with movss: andps needs a register here)
c_one:      dd 1.0
; creeper
c_ignite2:  dd 9.0                      ; the fuse lights within 3 blocks
c_stop2:    dd 4.0                      ; it stops walking within 2
c_march2:   dd 9.0                      ; an event's monster walks on until it is within 3 blocks of its dest
c_calm2:    dd 49.0                     ; the fuse burns on while the player is within 7
c_chest:    dd 0.9                      ; player centre above his feet
c_mid:      dd 0.85                     ; creeper centre above its feet
c_blast:    dd 3.0
c_vol_fuse: dd 1.0
; skeleton
c_near2:    dd 25.0                     ; backs away within 5 blocks
c_far_in2:  dd 100.0                    ; closes in beyond 10
c_shoot2:   dd 225.0                    ; shoots within 15
c_eye:      dd 1.62                     ; eye height above the feet
c_muzzle:   dd 0.6                      ; arrow starts this far along the aim
c_arrow_v:  dd 24.0                     ; arrow speed, blocks/s
c_lift:     dd 10.0                     ; upward aim per second of flight against gravity
c_cent:     dd 0.01
c_vol_bow:  dd 0.8
; spider
c_reach_y2: dd 2.25                     ; bite height window 1.5, squared
c_leap_lo2: dd 4.0                      ; leaps from 2 to 4 blocks away
c_leap_hi2: dd 16.0
c_climb:    dd 3.0
c_leap_vy:  dd 5.5
c_lift_vy:  dd 5.0
; elites and telegraphed attacks
c_1_5:      dd 1.5                      ; elite damage
c_1_15:     dd 1.15                     ; elite speed
c_2_5:      dd 2.5                      ; elite health
c_swift:    dd 1.3                      ; SWIFT elites are this much faster still
c_jugg_hp:  dd 1.5                      ; JUGGERNAUT elites have this much more health
c_hp_step:  dd MOB_HP_STEP
c_dmg_step: dd MOB_DMG_STEP
c_100:      dd 100.0
c_strike2:  dd 3.6                      ; a raised arm still connects within 1.9 blocks, squared
c_bite_end2: dd 2.45                    ; a rearing spider still bites within 1.56 blocks, squared
c_over_head: dd 0.2                     ; floating numbers start this far above the head
; the Fallen King
c_boss_aggro2: dd 2304.0                ; he hunts within 48 blocks
c_boss_stop2: dd 4.84                   ; he stops 2.2 blocks from the player (his fists reach 3.5)
c_boss_speed: dd 2.4
c_boss_rage: dd 1.4                     ; phase 3 speed factor
c_slam_start2: dd 9.0                   ; the fists go up within 3 blocks
c_slam2:    dd 12.25                    ; the slam reaches 3.5 blocks (phase 3: 5), squared
c_slam2_rage: dd 25.0
c_slam_dy2: dd 6.25                     ; ...and 2.5 blocks up or down, squared
c_slam_kb:  dd 10.0                     ; speed of the shove
c_slam_lift: dd 0.2                     ; the blast sits just above the floor
c_slam_fx:  dd 1.5
c_boss_kb:  dd 0.2                      ; he barely budges when hit
c_boss_eye: dd 2.6                      ; his arrows leave from his head
c_volley_v: dd 30.0
c_volley_muzzle: dd 0.8
c_fan_step: dd 10.0                     ; degrees between the 5 arrows of a volley
c_boss_death_r: dd 3.0
c_two:      dd 2.0
s_furious:  db "The Fallen King grows furious!", 0
s_empty:    db 0
s_afx_molten:     db "Molten", 0
s_afx_frozen:     db "Frozen", 0
s_afx_venomous:   db "Venomous", 0
s_afx_storm:      db "Storm", 0
s_afx_vampiric:   db "Vampiric", 0
s_afx_swift:      db "Swift", 0
s_afx_juggernaut: db "Juggernaut", 0
s_afx_armored:    db "Armored", 0
align 8
affix_names: dq s_afx_molten, s_afx_frozen, s_afx_venomous, s_afx_storm
             dq s_afx_vampiric, s_afx_swift, s_afx_juggernaut, s_afx_armored

section .bss
alignb 16
mobs:       resb MAX_MOBS * MOB_size
mobs_end:
mob_spawn_level: resd 1                 ; the level a spawn gets (mob_level_for) when it is around a remote player; 0: the local player's
mob_tgt_slot: resd 1                    ; the peer slot of the player the mob being updated hunts or strikes
spawn_rr:   resd 1                      ; the passive spawner's round-robin over the players
alignb 8
mob_tgt_body: resq 1                    ; ...and that player's BODY (the local player's, a remote player's proxy)
spawn_ctr:  resq 1                      ; spawn_near_player's centre BODY; 0: the local player's
spawn_rr_n: resd 1                      ; the night spawner's rotation: the centre it starts with
sc_n:       resd 1                      ; the spawn centres of this tick (spawn_gather) ...
sc_total:   resd 1                      ; ... the hostile mobs alive ...
sc_level:   resd SC_MAX                 ; ... the level a spawn around each gets (0: mob_level_for's own) ...
sc_cnt:     resd SC_MAX                 ; ... how many hostile mobs live within 96 blocks of each ...
alignb 8
sc_body:    resq SC_MAX                 ; ... and the BODY of each: the local player's first

section .text

; mobs_clear(): remove every mob
mobs_clear:
    lea     rdi, [mobs]
    mov     ecx, MAX_MOBS * MOB_size
    xor     eax, eax
    rep     stosb
    ret

; mob_count_type(edi type) -> eax number of live mobs of that type
mob_count_type:
    xor     eax, eax
    lea     rcx, [mobs]
    lea     rdx, [mobs_end]
.loop:
    cmp     [rcx + MOB.type], edi
    jne     .next
    inc     eax
.next:
    add     rcx, MOB_size
    cmp     rcx, rdx
    jb      .loop
    ret

; mob_count_kind(edi hostile 0/1) -> eax number of live mobs that are hostile (1) or passive (0)
mob_count_kind:
    xor     eax, eax
    lea     rcx, [mobs]
    lea     rdx, [mobs_end]
.loop:
    mov     esi, [rcx + MOB.type]
    test    esi, esi
    jz      .next
    movzx   esi, byte [t_hostile + rsi - 1]
    cmp     esi, edi
    jne     .next
    inc     eax
.next:
    add     rcx, MOB_size
    cmp     rcx, rdx
    jb      .loop
    ret

; mob_level_for(edi origin) -> eax the level of a mob born at that MOB.origin (a world_header.sites
; index + 1, 0 = no site): the player's (mob_spawn_level while a spawn is around a remote player,
; else the local player's), two above it in a dungeon, the player's + 3 but at least 20 for the Fallen
; King of a crypt. Any other origin (a village, a camp, an index no record backs) gives the player's level.
mob_level_for:
    push    rbx
    mov     ebx, edi
    mov     eax, [mob_spawn_level]      ; a spawn around a remote player: that player's level
    test    eax, eax
    jnz     .level
    call    rpg_level
.level:
    mov     ecx, 1
    cmp     eax, ecx
    cmovl   eax, ecx                    ; a blank character reads level 0: count it as 1
    lea     edx, [rbx - 1]
    cmp     edx, MAX_SITESTATES - 1
    ja      .ret                        ; no site (origin 0 wraps round to a huge index)
    imul    edx, edx, SITESTATE_size
    lea     rcx, [world_header + WORLDHDR.sites]
    movzx   edx, byte [rcx + rdx + SITESTATE.kind]
    cmp     edx, SITE_DUNGEON
    jne     .crypt
    add     eax, 2                      ; a dungeon: two levels above the player
    jmp     .ret
.crypt:
    cmp     edx, SITE_CRYPT
    jne     .ret
    add     eax, 3
    mov     ecx, CRYPT_MIN_LEVEL
    cmp     eax, ecx
    cmovl   eax, ecx
.ret:
    pop     rbx
    ret

; mob_dmg_mult(edi level) -> xmm0 1 + MOB_DMG_STEP * (level - 1): what a mob of that level
; multiplies its blows on the player by (levels below 1 count as 1)
mob_dmg_mult:
    lea     eax, [rdi - 1]
    xor     ecx, ecx
    test    eax, eax
    cmovs   eax, ecx
    cvtsi2ss xmm0, eax
    mulss   xmm0, [c_dmg_step]
    addss   xmm0, [c_one]
    ret

; mob_scale(rdi mob): max_health and health of the mob at rdi from its type, level, elite flag and
; affixes: round(base * (1 + MOB_HP_STEP * (level - 1)) * (elite ? 2.5 : 1) * (JUGGERNAUT ? 1.5 :
; 1)), single precision throughout and rounded once at the end. base is the type's health, the
; Fallen King's by difficulty, a folk's its class's (folk_class_health). Clobbers eax, ecx, edx,
; xmm0, xmm1.
mob_scale:
    mov     ecx, [rdi + MOB.type]
    lea     eax, [rcx - 1]
    cmp     eax, NUM_MOB_TYPES - 1
    ja      .ret                        ; no such type
    cvtsi2ss xmm0, dword [t_health + rax*4]
    cmp     ecx, MOB_FOLK
    je      .folk
    cmp     ecx, MOB_BOSS
    jne     .scale
    mov     eax, [settings + SETTINGS.difficulty]   ; the Fallen King: 200 / 200 / 300 / 450 by difficulty
    mov     edx, DIFF_HARD
    cmp     eax, edx
    cmova   eax, edx
    cvtsi2ss xmm0, dword [t_boss_health + rax*4]
.scale:
    mov     eax, [rdi + MOB.level]
    dec     eax
    xor     edx, edx
    test    eax, eax
    cmovs   eax, edx                    ; levels below 1 count as 1
    cvtsi2ss xmm1, eax
    mulss   xmm1, [c_hp_step]
    addss   xmm1, [c_one]
    mulss   xmm0, xmm1
    cmp     dword [rdi + MOB.elite], 0
    je      .not_elite
    mulss   xmm0, [c_2_5]
.not_elite:
    test    byte [rdi + MOB.affix], AFX_JUGGERNAUT
    jz      .round
    mulss   xmm0, [c_jugg_hp]
.round:
    cvtss2si eax, xmm0
    mov     [rdi + MOB.max_health], eax
    mov     [rdi + MOB.health], eax
.ret:
    ret
.folk:                                  ; a folk's health is its class's (20 for a non-fighter)
    sub     rsp, 8
    call    folk_class_health
    add     rsp, 8
    cvtsi2ss xmm0, eax
    jmp     .scale

; mob_set_level(edi idx, esi level): the mob in slot idx becomes level `level` (1..255) and gets
; that level's health, full (mob_scale); an empty or bad slot is left alone. An elite raised to
; ELITE_TWO_AFFIXES or more with a single affix rolls its second one (a distinct kind), as if it had
; spawned at that level (dungeon elites spawn at the player's level, then get the dungeon's).
mob_set_level:
    cmp     edi, MAX_MOBS
    jae     .ret
    imul    edi, edi, MOB_size
    lea     rax, [mobs]
    add     rdi, rax
    cmp     dword [rdi + MOB.type], MOB_NONE
    je      .ret
    mov     eax, 1
    cmp     esi, eax
    cmovl   esi, eax
    mov     eax, MOB_MAX_LEVEL
    cmp     esi, eax
    cmovg   esi, eax
    mov     [rdi + MOB.level], esi
    cmp     dword [rdi + MOB.elite], 0
    je      mob_scale
    cmp     esi, ELITE_TWO_AFFIXES
    jb      mob_scale
    mov     eax, [rdi + MOB.affix]
    test    eax, eax
    jz      mob_scale
    lea     ecx, [rax - 1]
    test    eax, ecx
    jnz     mob_scale                   ; already two (or more)
    push    rdi
.roll:
    call    rng_next                    ; a kind 0..7 the mob does not have yet
    and     eax, NUM_AFFIX_KINDS - 1
    mov     ecx, eax
    mov     eax, 1
    shl     eax, cl
    mov     rdi, [rsp]
    test    [rdi + MOB.affix], eax
    jnz     .roll
    or      [rdi + MOB.affix], eax
    call    elite_speed                 ; SWIFT may have been rolled
    pop     rdi
    jmp     mob_scale                   ; JUGGERNAUT may have been rolled
.ret:
    ret

; elite_speed(rdi mob): BODY.speed of an elite: its type's walking speed (a folk's: its class's,
; folk_base_speed) x 1.15, a SWIFT one x 1.3 more. Clobbers ecx, xmm0.
elite_speed:
    mov     ecx, [rdi + MOB.type]
    movss   xmm0, [t_speed + rcx*4 - 4]
    cmp     ecx, MOB_FOLK
    jne     .scale
    sub     rsp, 8
    call    folk_base_speed
    add     rsp, 8
.scale:
    mulss   xmm0, [c_1_15]
    test    byte [rdi + MOB.affix], AFX_SWIFT
    jz      .set
    mulss   xmm0, [c_swift]
.set:
    movss   [rdi + BODY.speed], xmm0
    ret

; mob_resist(edi type, esi elem) -> eax the percent of that element's damage the type shrugs off
; (negative: it takes more, 100: immune); 0 for an unknown type or element
mob_resist:
    xor     eax, eax
    lea     ecx, [rdi - 1]
    cmp     ecx, NUM_MOB_TYPES - 1
    ja      .ret
    cmp     esi, NUM_ELEMS - 1
    ja      .ret
    lea     ecx, [rcx + rcx*4]          ; 5 elements per type
    add     ecx, esi
    movsx   eax, byte [t_resist + rcx]
.ret:
    ret

; mob_affix_name(edi bit) -> rax the name of the elite affix 1 << bit (bit 0..7, the AFX_* order);
; an empty string for any other bit
mob_affix_name:
    lea     rax, [s_empty]
    cmp     edi, NUM_AFFIX_KINDS - 1
    ja      .ret
    mov     edi, edi
    lea     rax, [affix_names]
    mov     rax, [rax + rdi*8]
.ret:
    ret

; mob_spawn(edi type, xmm0 x, xmm1 y, xmm2 z) -> eax slot index, or -1 (bad type / no free slot).
; Every mob remembers its spawn point as its home (folk stroll around it). It starts at the
; player's level with the health of that level (mob_scale), the Fallen King's also by difficulty;
; his two timers start. Folk are spawned through folk_spawn (folk.asm), which gives them their class.
mob_spawn:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 24                     ; [rsp] x, [rsp+4] y, [rsp+8] z
    lea     eax, [rdi - 1]
    cmp     eax, NUM_MOB_TYPES - 1
    ja      .none                       ; not a mob type
    mov     ebx, edi
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 8], xmm2
    lea     r12, [mobs]
    xor     r13d, r13d
.find:
    cmp     dword [r12 + MOB.type], MOB_NONE
    je      .found
    add     r12, MOB_size
    inc     r13d
    cmp     r13d, MAX_MOBS
    jb      .find
.none:
    mov     eax, -1
    jmp     .ret
.found:
    lea     ecx, [rbx - 1]
    movss   xmm0, [t_half_w + rcx*4]
    movss   xmm1, [t_height + rcx*4]
    movss   xmm2, [t_speed + rcx*4]
    mov     rdi, r12
    call    body_init                   ; zeroes the body, then sets box and speed
    lea     rdi, [r12 + BODY_size]      ; clear everything after the body (stale after a removal)
    mov     ecx, MOB_size - BODY_size
    xor     eax, eax
    rep     stosb
    mov     [r12 + MOB.type], ebx
    cmp     ebx, MOB_BOSS
    jne     .level
    mov     dword [r12 + MOB.timer_a], BOSS_SUMMON_STEPS
    mov     dword [r12 + MOB.timer_b], BOSS_VOLLEY_STEPS
.level:
    xor     edi, edi
    call    mob_level_for               ; the player's level
    mov     [r12 + MOB.level], eax
    mov     rdi, r12
    call    mob_scale                   ; max_health and health of that level
    mov     eax, [rsp]
    mov     [r12 + BODY.x], eax
    mov     [r12 + MOB.home_x], eax
    mov     eax, [rsp + 4]
    mov     [r12 + BODY.y], eax
    mov     eax, [rsp + 8]
    mov     [r12 + BODY.z], eax
    mov     [r12 + MOB.home_z], eax
    call    rng_next                    ; yaw = rng % 360
    xor     edx, edx
    mov     ecx, 360
    div     ecx
    cvtsi2ss xmm0, edx
    movss   [r12 + BODY.yaw], xmm0
    mov     eax, r13d
.ret:
    add     rsp, 24
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mob_spawn_elite(edi type, xmm0 x, xmm1 y, xmm2 z) -> eax slot index, or -1: mob_spawn, then the
; elite upgrade (make_elite)
mob_spawn_elite:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    mob_spawn
    test    eax, eax
    js      .ret
    mov     ebx, eax
    imul    edx, eax, MOB_size
    lea     rcx, [mobs]
    add     rdx, rcx
    call    make_elite
    mov     eax, ebx
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; make_elite(rdx mob): the mob becomes an elite: it rolls its affixes (one, two from level 15 on;
; distinct kinds, each rng % 8), moves 1.15 x as fast (SWIFT 1.3 x more) and has 2.5 x the health
; (JUGGERNAUT 1.5 x more), and the AI hits with 1.5 x its damage (ELITE_DAMAGE); it is drawn gold
; and 1.2 x larger. Clobbers rax, rcx, rdx, rsi, rdi, r8-r11 and xmm0-1.
make_elite:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     rbx, rdx
    mov     dword [rbx + MOB.elite], 1
    mov     dword [rbx + MOB.affix], 0
    mov     r12d, 1                     ; affixes to roll
    cmp     dword [rbx + MOB.level], ELITE_TWO_AFFIXES
    jb      .roll
    inc     r12d
.roll:
    call    rng_next                    ; a kind 0..7; one the mob already has is rolled again
    and     eax, NUM_AFFIX_KINDS - 1
    mov     ecx, eax
    mov     eax, 1
    shl     eax, cl
    test    [rbx + MOB.affix], eax
    jnz     .roll
    or      [rbx + MOB.affix], eax
    dec     r12d
    jnz     .roll
    mov     rdi, rbx
    call    elite_speed
    mov     rdi, rbx
    call    mob_scale
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mob_is_hostile(edi idx) -> eax 1 when slot idx holds a live hostile mob (zombie, creeper, skeleton,
; spider, the boss, a folk fighter that counts as hostile to the player: folk_hostile), else 0 (empty
; slot, bad index, passive animal, any other folk)
mob_is_hostile:
    xor     eax, eax
    cmp     edi, MAX_MOBS
    jae     .ret
    imul    edi, edi, MOB_size
    lea     rcx, [mobs]
    add     rdi, rcx
    mov     edx, [rdi + MOB.type]
    test    edx, edx
    jz      .ret
    cmp     edx, MOB_FOLK
    je      folk_hostile
    movzx   eax, byte [t_hostile + rdx - 1]
.ret:
    ret

; yaw_from(xmm0 dx, xmm1 dz) -> xmm0 heading in [0, 360) whose forward vector (sin, -cos) runs along (dx, dz)
yaw_from:
    sub     rsp, 8
    xorps   xmm2, xmm2
    subss   xmm2, xmm1
    movaps  xmm1, xmm2                  ; atan2(dx, -dz)
    call    atan2_deg
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jae     .done
    addss   xmm0, [c_360]
    comiss  xmm0, [c_360]
    jb      .done                       ; a tiny negative angle can round up to exactly 360
    subss   xmm0, [c_360]
.done:
    add     rsp, 8
    ret

; mob_ai(rdi mob) -> eax 1 when the mob blew up and is gone, else 0.
; This step's input and heading. A stunned mob stands still and attacks nothing. Zombies hunt a
; living player within 24 blocks (Survival, difficulty > 0, not hidden in smoke) and, after raising
; an arm for 20 steps, hit through mob_melee_hit when he is still close; creepers, skeletons and
; spiders hunt within 16 blocks (ai_creeper, ai_skeleton, ai_spider); the Fallen King hunts within
; 48 blocks and sees through smoke (ai_boss); folk follow folk_ai (folk.asm: fighters hunt, patrol and
; guard, the rest stroll around home, turn to a player within 4 or run when scared); a panicking pig
; or chicken runs along its heading; a hostile monster with MOB.patrol != 0 (an event's) that has nobody to
; hunt walks to its dest until it is within 3 blocks of it (.march); everything else wanders in
; 1-4 s legs. At the end (.jump) a mob in a liquid holds jump (it floats up and drifts) and one in LAVA
; also burns (mob_lava_burn; a mob that burns to death is gone: eax 0 with MOB.type MOB_NONE); one that
; would step into water or lava (WATER or LAVA 0.7 blocks ahead at its feet or just below that) turns
; about when it wanders and stops when it is hunting or walking home; one that walks into an obstacle hops.
; Frame: [rsp] dx, [rsp+4] dz, [rsp+8] horizontal distance^2 to the player it hunts, [rsp+12] 1 while its
; heading is steered on purpose (hunting, walking home), else 0. The hunted player is the nearest one that
; lives (net_nearest_target): mob_tgt_body and mob_tgt_slot name his body and peer slot for the hunters' AI.
mob_ai:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 24
    mov     rbx, rdi
    mov     dword [rsp + 12], 0         ; no purposeful heading yet
    xor     eax, eax
    mov     [rbx + MOB.input + INPUT.strafe], eax
    mov     [rbx + MOB.input + INPUT.down], eax
    mov     [rbx + MOB.input + INPUT.sprint], eax
    cmp     dword [rbx + MOB.stun], 0
    jg      .stunned
    mov     ecx, [rbx + MOB.type]
    cmp     ecx, MOB_FOLK
    je      .folk
    cmp     byte [t_hostile + rcx - 1], 0
    je      .passive
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .idle
    cmp     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL
    je      .idle
    xor     edi, edi                    ; the Fallen King sees through smoke...
    cmp     ecx, MOB_BOSS
    je      .seen
    mov     edi, 1                      ; ...everyone else loses a player hidden in it
.seen:
    movss   xmm0, [rbx + BODY.x]        ; the nearest player that lives (and is not hidden)
    movss   xmm1, [rbx + BODY.z]
    call    net_nearest_target          ; rax = his body or 0, edx = his peer slot
    test    rax, rax
    jz      .idle                       ; nobody to hunt
    mov     [mob_tgt_body], rax
    mov     [mob_tgt_slot], edx
    movss   xmm0, [rax + BODY.x]
    subss   xmm0, [rbx + BODY.x]
    movss   [rsp], xmm0                 ; dx
    movss   xmm1, [rax + BODY.z]
    subss   xmm1, [rbx + BODY.z]
    movss   [rsp + 4], xmm1             ; dz
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    movss   [rsp + 8], xmm0
    mov     ecx, [rbx + MOB.type]       ; (the call clobbered it)
    movss   xmm1, [c_hunt2]
    cmp     ecx, MOB_ZOMBIE
    jne     .not_zombie
    movss   xmm1, [c_aggro2]
.not_zombie:
    cmp     ecx, MOB_BOSS
    jne     .range
    movss   xmm1, [c_boss_aggro2]
.range:
    comiss  xmm0, xmm1
    jae     .idle                       ; too far to notice
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    call    yaw_from
    movss   [rbx + BODY.yaw], xmm0
    mov     dword [rsp + 12], 1         ; hunting: the heading is on purpose
    mov     eax, [rbx + MOB.type]
    cmp     eax, MOB_ZOMBIE
    je      .zombie
    mov     rdi, rbx
    mov     rsi, rsp
    lea     rcx, [hunt_ai]
    call    [rcx + rax*8 - 8]
    test    eax, eax
    jnz     .ret                        ; it blew up
    jmp     .jump
.zombie:
    cmp     dword [rbx + MOB.windup], 0
    jg      .winding
    mov     dword [rbx + MOB.input + INPUT.fwd], 1
    movss   xmm0, [rsp + 8]
    comiss  xmm0, [c_close2]
    jae     .closing
    mov     dword [rbx + MOB.input + INPUT.fwd], 0 ; at arm's length: it stops rather than walk into him
.closing:
    cmp     dword [rbx + MOB.cooldown], 0
    jne     .jump
    mov     rax, [mob_tgt_body]
    movss   xmm0, [rax + BODY.y]        ; body centres are both feet + 0.9, so only the feet differ
    subss   xmm0, [rbx + BODY.y]
    mulss   xmm0, xmm0
    addss   xmm0, [rsp + 8]
    comiss  xmm0, [c_reach2]
    jae     .jump                       ; out of reach
    mov     eax, ZOMBIE_WINDUP          ; in reach: the arm goes up, and the zombie stands to swing
    mov     ecx, ZOMBIE_WINDUP_ELITE
    cmp     dword [rbx + MOB.elite], 0
    cmovne  eax, ecx
    SWIFT_WINDUP eax
    mov     [rbx + MOB.windup], eax
    mov     dword [rbx + MOB.input + INPUT.fwd], 0
    jmp     .jump
.winding:
    mov     dword [rbx + MOB.input + INPUT.fwd], 0
    dec     dword [rbx + MOB.windup]
    jnz     .jump                       ; the arm is still up
    mov     rax, [mob_tgt_body]
    movss   xmm0, [rax + BODY.y]        ; the blow lands only on a player still within reach
    subss   xmm0, [rbx + BODY.y]
    mulss   xmm0, xmm0                  ; dy^2
    comiss  xmm0, [c_reach_y2]          ; |dy| < 1.5
    jae     .whiff
    addss   xmm0, [rsp + 8]             ; distance^2 including the height difference, as at the start
    comiss  xmm0, [c_strike2]
    ja      .whiff                      ; more than 1.9 blocks away
    mov     eax, [settings + SETTINGS.difficulty]
    mov     ecx, DIFF_HARD
    cmp     eax, ecx
    cmova   eax, ecx
    mov     esi, [t_dmg + rax*4]
    mov     rdi, rbx
    mov     edx, CAUSE_ZOMBIE
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.z]
    movss   xmm2, [c_kb]
    call    mob_melee_hit
    cmp     eax, HIT_PARRIED
    je      .parried
    cmp     eax, HIT_TAKEN
    jne     .hit_done                   ; blocked or dodged: no knockback
    mov     rsi, rsp                    ; knock the player back along zombie -> player
    movss   xmm3, [c_kb]
    call    knock_player
.hit_done:
    mov     dword [rbx + MOB.cooldown], HIT_COOLDOWN
    jmp     .jump
.parried:                               ; the riposte stuns it: it reels back and stands dazed
    test    byte [rbx + MOB.affix], AFX_JUGGERNAUT
    jnz     .hit_done                   ; a juggernaut shrugs the riposte off
    mov     dword [rbx + MOB.stun], STUN_PARRIED
    mov     rdi, rbx
    mov     rsi, rsp
    call    mob_reel
    mov     rdi, rbx
    call    mob_stunned_text
    jmp     .hit_done
.whiff:                                 ; the player got away: it recovers sooner
    mov     dword [rbx + MOB.cooldown], 20
    jmp     .jump
.stunned:                               ; a stunned mob stands still; its telegraph is broken
    mov     dword [rbx + MOB.input + INPUT.fwd], 0
    mov     dword [rbx + MOB.windup], 0
    jmp     .jump
.idle:                                  ; not hunting: a lit fuse dies down while it wanders
    mov     dword [rbx + MOB.windup], 0 ; a lost target breaks the telegraph
    cmp     dword [rbx + MOB.patrol], 0
    jne     .march                      ; an event's monster: it walks to dest (the protected NPC) while it has nobody to hunt
    cmp     dword [rbx + MOB.type], MOB_BOSS
    je      .stand                      ; the Fallen King guards his crypt, he never strolls off
    cmp     dword [rbx + MOB.fuse], 0
    jle     .wander
    dec     dword [rbx + MOB.fuse]
    jmp     .wander
.march:                                 ; dest is a local float pair; within 3 blocks of it the monster stands and waits
    movss   xmm0, [rbx + MOB.dest_x]
    subss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + MOB.dest_z]
    subss   xmm1, [rbx + BODY.z]
    movaps  xmm2, xmm0
    mulss   xmm2, xmm2
    movaps  xmm3, xmm1
    mulss   xmm3, xmm3
    addss   xmm2, xmm3
    comiss  xmm2, [c_march2]
    jbe     .stand
    call    yaw_from
    movss   [rbx + BODY.yaw], xmm0
    mov     dword [rbx + MOB.input + INPUT.fwd], 1
    mov     dword [rsp + 12], 1         ; purposeful: it halts at a shore instead of turning about
    jmp     .jump
.passive:
    mov     eax, [rbx + MOB.type]
    cmp     dword [rbx + MOB.panic], 0
    jle     .wander
    mov     edx, [t_run + rax*4 - 4]    ; a hurt pig or chicken runs
    mov     [rbx + BODY.speed], edx
    mov     dword [rbx + MOB.input + INPUT.fwd], 1
    dec     dword [rbx + MOB.panic]
    jnz     .jump
    mov     edx, [t_speed + rax*4 - 4]  ; panic over: back to the stroll speed
    mov     [rbx + BODY.speed], edx
    jmp     .jump
.folk:                                  ; folk: folk_ai (folk.asm) decides this step's input and heading
    mov     rdi, rbx
    call    folk_ai                     ; 0 input set, 1 the heading is on purpose, 2 wander
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .gone                       ; a traveller that outstayed its welcome is gone
    cmp     eax, 2
    je      .wander
    mov     [rsp + 12], eax
    jmp     .jump
.gone:
    xor     eax, eax
    jmp     .ret
.wander:
    mov     eax, [rbx + MOB.ai_timer]
    dec     dword [rbx + MOB.ai_timer]
    test    eax, eax
    jg      .jump                       ; keep the current leg
    call    rng_next                    ; next leg lasts 60 + rng % 180 steps
    xor     edx, edx
    mov     ecx, 180
    div     ecx
    add     edx, 60
    mov     [rbx + MOB.ai_timer], edx
    call    rng_next
    test    al, 1
    jz      .stand
    call    rng_next                    ; walk off in a random direction
    xor     edx, edx
    mov     ecx, 360
    div     ecx
    cvtsi2ss xmm0, edx
    movss   [rbx + BODY.yaw], xmm0
    mov     dword [rbx + MOB.input + INPUT.fwd], 1
    jmp     .jump
.stand:
    mov     dword [rbx + MOB.input + INPUT.fwd], 0
.jump:                                  ; steer clear of water and lava, hop when walking into something
    mov     rdi, rbx
    call    body_in_liquid
    test    eax, eax
    jz      .dry
    cmp     eax, LAVA
    jne     .afloat
    mov     rdi, rbx
    call    mob_lava_burn               ; in lava it burns...
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .gone                       ; ...and may burn to death
.afloat:
    mov     eax, 1                      ; afloat: it holds jump, so it floats up and drifts
    jmp     .store_jump
.dry:
    cmp     dword [rbx + MOB.input + INPUT.fwd], 0
    je      .hop
    mov     rdi, rbx
    call    mob_water_ahead
    test    eax, eax
    jz      .hop
    cmp     dword [rsp + 12], 0
    jne     .halt
    mov     rdi, rbx                    ; a wanderer swings away from the water...
    call    mob_turn_about
    jmp     .hop
.halt:
    mov     dword [rbx + MOB.input + INPUT.fwd], 0  ; ...a purposeful walker stops at the shore
.hop:
    xor     eax, eax
    cmp     dword [rbx + MOB.input + INPUT.fwd], 0
    je      .store_jump
    cmp     dword [rbx + BODY.blocked], 0
    je      .store_jump
    cmp     dword [rbx + BODY.on_ground], 0
    je      .store_jump
    mov     eax, 1
.store_jump:
    mov     [rbx + MOB.input + INPUT.jump], eax
    xor     eax, eax
.ret:
    add     rsp, 24
    pop     rbx
    pop     rbp
    ret

; mob_lava_burn(rdi mob): the mob stands in lava. It catches fire (status_apply, STS_BURN, magnitude 24:
; 3 s of burn, a tick of 2 every 30 steps, renewed while it stays) and on every LAVA_PERIOD-th step of
; game_time takes a strike of LAVA_STRIKE health (mob_strike lands inside the hurt window, with no
; knockback). A mob the strike kills is gone (MOB.type = MOB_NONE, its loot dropped): look at the type again.
; Its burn is flagged FF_FOLKDOT: the player gets no XP and no standing change for a mob the lava kills.
; r12d = the mob's slot
mob_lava_burn:
    push    rbp
    mov     rbp, rsp
    push    r12
    sub     rsp, 8
    call    mob_index                   ; eax = the slot of rdi
    mov     r12d, eax
    mov     edi, eax
    mov     esi, STS_BURN
    movss   xmm0, [c_lava_burn]
    call    status_apply
    imul    eax, r12d, MOB_size
    lea     rcx, [mobs]
    or      byte [rcx + rax + MOB.fflags], FF_FOLKDOT
    mov     eax, [game_time]
    xor     edx, edx
    mov     ecx, LAVA_PERIOD
    div     ecx
    test    edx, edx
    jnz     .ret
    mov     edi, r12d
    mov     esi, LAVA_STRIKE
    xorps   xmm0, xmm0
    xorps   xmm1, xmm1
    call    mob_strike
.ret:
    add     rsp, 8
    pop     r12
    pop     rbp
    ret

; mob_water_ahead(rdi mob) -> eax 1 when WATER or LAVA lies 0.7 blocks ahead of the mob along its heading
; (behind it when it backs away: input.fwd < 0), in the cell of its feet or in the cell below that
; rbx = mob, r12d, r13d, r14d = x, z and feet y of the cell looked at
mob_water_ahead:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    movss   xmm0, [rbx + BODY.yaw]
    call    sincos_deg                  ; xmm0 = sin yaw, xmm1 = cos yaw
    cvtsi2ss xmm2, dword [rbx + MOB.input + INPUT.fwd]
    mulss   xmm2, [c_water_dx]          ; +-0.7 along the direction of travel
    mulss   xmm0, xmm2
    addss   xmm0, [rbx + BODY.x]        ; x + 0.7 sin yaw
    roundss xmm0, xmm0, 9
    cvttss2si r12d, xmm0
    mulss   xmm1, xmm2
    movss   xmm3, [rbx + BODY.z]
    subss   xmm3, xmm1                  ; z - 0.7 cos yaw
    roundss xmm3, xmm3, 9
    cvttss2si r13d, xmm3
    movss   xmm0, [rbx + BODY.y]
    roundss xmm0, xmm0, 9
    cvttss2si r14d, xmm0
    mov     edi, r12d
    mov     esi, r14d
    mov     edx, r13d
    call    world_get
    cmp     eax, WATER
    je      .yes
    cmp     eax, LAVA
    je      .yes
    mov     edi, r12d
    lea     esi, [r14 - 1]
    mov     edx, r13d
    call    world_get
    cmp     eax, WATER
    je      .yes
    cmp     eax, LAVA
    je      .yes
    xor     eax, eax
    jmp     .ret
.yes:
    mov     eax, 1
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mob_turn_about(rdi mob): the heading swings round to face away from what lies ahead: 180 degrees
; plus an offset of -45..+45 that is a fixed hash of the mob's slot (no rng: a slot always swings
; the same way), wrapped into [0, 360)
mob_turn_about:
    push    rbx
    mov     rbx, rdi
    call    mob_index
    imul    eax, eax, 0x9E3779B1
    shr     eax, 16
    xor     edx, edx
    mov     ecx, 91
    div     ecx                         ; edx = 0..90
    sub     edx, 45
    cvtsi2ss xmm0, edx
    addss   xmm0, [c_turn]
    addss   xmm0, [rbx + BODY.yaw]
    movss   xmm1, [c_360]
    comiss  xmm0, xmm1
    jb      .set
    subss   xmm0, xmm1
.set:
    movss   [rbx + BODY.yaw], xmm0
    pop     rbx
    ret

; mob_reel(rdi mob, rsi frame): knocks the mob away from the player at 6 blocks/s.
; frame = mob_ai's [dx, dz, horizontal distance^2], dx and dz running mob -> player.
mob_reel:
    movss   xmm2, [rsi + 8]
    sqrtss  xmm2, xmm2
    comiss  xmm2, [c_tiny]
    jb      .done                       ; standing on the player: no direction
    movss   xmm3, [c_kb]
    divss   xmm3, xmm2
    xorps   xmm4, xmm4
    movss   xmm0, [rsi]
    mulss   xmm0, xmm3
    subss   xmm4, xmm0
    movss   [rdi + BODY.kbx], xmm4
    xorps   xmm4, xmm4
    movss   xmm1, [rsi + 4]
    mulss   xmm1, xmm3
    subss   xmm4, xmm1
    movss   [rdi + BODY.kbz], xmm4
.done:
    ret

; mob_stunned_text(rdi mob): "STUNNED" floats up over the mob's head
mob_stunned_text:
    sub     rsp, 8
    movss   xmm0, [rdi + BODY.x]
    movss   xmm1, [rdi + BODY.y]
    addss   xmm1, [rdi + BODY.height]
    addss   xmm1, [c_over_head]
    movss   xmm2, [rdi + BODY.z]
    mov     edi, TXT_STUNNED
    call    dmgnum_text
    add     rsp, 8
    ret

; mob_blow(rdi mob, esi base, rdx parts) -> eax the damage of one blow of that mob on the player:
; base (an elite's x 1.5, rounded) x mob_dmg_mult(level), rounded, is the physical damage; each
; elemental affix adds a part -- MOLTEN .5 fire, FROZEN .3 frost, VENOMOUS .3 poison, STORM .5
; shock of it, rounded -- cut by the player's resistance to that element. When rdx is not 0 the
; int[5] there receives the physical damage and each element's part (by ELEM_*).
mob_blow:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 24                     ; a scratch int[5] for a caller that wants no parts
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13, rdx
    test    r13, r13
    jnz     .have_parts
    mov     r13, rsp
.have_parts:
    ELITE_DAMAGE r12d
    mov     edi, [rbx + MOB.level]
    call    mob_dmg_mult
    cvtsi2ss xmm1, r12d
    mulss   xmm0, xmm1
    cvtss2si r12d, xmm0                 ; the physical damage
    xor     eax, eax
    mov     [r13], r12d
    mov     [r13 + 4], eax
    mov     [r13 + 8], eax
    mov     [r13 + 12], eax
    mov     [r13 + 16], eax
    mov     eax, r12d                   ; the whole blow so far
    lea     r8, [rpg_stats]
    xor     ecx, ecx                    ; affix bit 0..3
.part:
    movzx   edx, byte [rbx + MOB.affix]
    bt      edx, ecx
    jnc     .next
    movzx   edx, byte [affix_elem + rcx]
    cvtsi2ss xmm0, r12d
    mulss   xmm0, [affix_share + rcx*4]
    cvtss2si esi, xmm0                  ; round(physical * share)
    mov     edi, 100
    sub     edi, [r8 + (STAT_RES_FIRE - 1)*4 + rdx*4]
    imul    esi, edi                    ; x (100 - the player's resistance to that element)
    cvtsi2ss xmm0, esi
    divss   xmm0, [c_100]
    cvtss2si esi, xmm0                  ; / 100, rounded
    mov     [r13 + rdx*4], esi
    add     eax, esi
.next:
    inc     ecx
    cmp     ecx, 4
    jb      .part
    add     rsp, 24
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mob_blow_raw(rdi mob, esi base) -> eax the damage of one blow of that mob on another mob: base (an
; elite's x 1.5, rounded) x mob_dmg_mult(level), rounded. Physical only: no affix parts, no armor.
mob_blow_raw:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12d, esi
    ELITE_DAMAGE r12d
    mov     edi, [rbx + MOB.level]
    call    mob_dmg_mult
    cvtsi2ss xmm1, r12d
    mulss   xmm0, xmm1
    cvtss2si eax, xmm0
    pop     r12
    pop     rbx
    pop     rbp
    ret

; folk_strike_mob(rdi attacker, esi target_idx, edx base): one melee blow of the folk `attacker` on the
; folk in slot target_idx, a rival: mob_blow_raw's damage along attacker -> target through mob_hurt. It
; counts for no player: combat_hit_flags is cleared, so no tag, no provocation, no reputation. When the
; attacker's weapon carries an element the target also takes that element's status, max(1, damage / 2),
; and its burning is flagged as a folk's (FF_FOLKDOT: its kill is nobody's). A sleeping champion that is
; struck wakes (no banner); a target that is no fighter runs (folk_scare); a fighter without a target
; takes the attacker for one (target = slot + 2). An empty slot, a bad one or a target still inside its
; hurt window changes nothing.
; rbx = attacker, r12d = target slot, r13 = target MOB*, r14d = damage; frame: [rsp] dirx, [rsp+4] dirz
folk_strike_mob:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 16
    mov     rbx, rdi
    mov     r12d, esi
    cmp     esi, MAX_MOBS
    jae     .ret
    imul    eax, esi, MOB_size
    lea     r13, [mobs]
    add     r13, rax
    cmp     dword [r13 + MOB.type], MOB_NONE
    je      .ret
    mov     esi, edx
    mov     rdi, rbx
    call    mob_blow_raw
    mov     r14d, eax
    movss   xmm0, [r13 + BODY.x]
    subss   xmm0, [rbx + BODY.x]
    movss   xmm1, [r13 + BODY.z]
    subss   xmm1, [rbx + BODY.z]
    movaps  xmm2, xmm0
    mulss   xmm2, xmm2
    movaps  xmm3, xmm1
    mulss   xmm3, xmm3
    addss   xmm2, xmm3
    sqrtss  xmm2, xmm2
    comiss  xmm2, [c_tiny]
    jb      .still
    divss   xmm0, xmm2                  ; the unit vector from the attacker to the target
    divss   xmm1, xmm2
    jmp     .hurt
.still:
    xorps   xmm0, xmm0
    xorps   xmm1, xmm1
.hurt:
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    mov     byte [combat_hit_flags], 0
    mov     edi, r12d
    mov     esi, r14d
    call    mob_hurt
    test    eax, eax
    jz      .ret                        ; still inside its hurt window
    cmp     dword [r13 + MOB.type], MOB_FOLK
    jne     .ret                        ; it fell
    mov     rdi, rbx
    call    mob_arrow_flags             ; the element of the attacker's first elemental affix, at AF_ELEM_SHIFT
    shr     eax, AF_ELEM_SHIFT
    jz      .react
    lea     esi, [rax - 1]              ; ELEM_* - 1 = STS_*
    mov     eax, r14d
    shr     eax, 1
    mov     ecx, 1
    cmp     eax, ecx
    cmovl   eax, ecx
    cvtsi2ss xmm0, eax
    mov     edi, r12d
    call    status_apply
    or      byte [r13 + MOB.fflags], FF_FOLKDOT
.react:
    and     byte [r13 + MOB.fflags], ~FF_ASLEEP
    mov     rdi, r13
    call    folk_is_fighter
    test    eax, eax
    jz      .scared
    cmp     dword [r13 + MOB.target], 0
    jne     .ret
    mov     rdi, rbx
    call    mob_index
    add     eax, 2
    mov     [r13 + MOB.target], eax     ; it hits back at whoever hit it
    jmp     .ret
.scared:
    mov     rdi, r13
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    call    folk_scare
.ret:
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mob_arrow_flags(rdi mob) -> eax the ARROWENT.flags of an arrow that mob shoots: the element of
; its first elemental affix (MOLTEN, FROZEN, VENOMOUS, STORM) at AF_ELEM_SHIFT, 0 without one.
; Touches only eax and ecx: the arrow's position and velocity wait in the xmm registers.
mob_arrow_flags:
    movzx   eax, byte [rdi + MOB.affix]
    and     eax, AFX_MOLTEN | AFX_FROZEN | AFX_VENOMOUS | AFX_STORM
    jz      .ret
    bsf     ecx, eax
    movzx   eax, byte [affix_elem + rcx]
    shl     eax, AF_ELEM_SHIFT
.ret:
    ret

; mob_index(rdi mob) -> eax the slot that mob lives in. Clobbers ecx, edx, rdi.
mob_index:
    lea     rax, [mobs]
    sub     rdi, rax
    mov     eax, edi
    xor     edx, edx
    mov     ecx, MOB_size
    div     ecx
    ret

; mob_affix_status(rdi mob, rsi parts int[5], edx n) -> eax STS_* of the n-th (from 0) status the elemental
; affixes of the mob's blow put on its target, edx its magnitude (that affix's part of the blow, parts as
; mob_blow filled them); eax -1 when there is no n-th. The order: burn (MOLTEN), chill (FROZEN), poison
; (VENOMOUS). Clobbers ecx.
mob_affix_status:
    xor     ecx, ecx                    ; statuses passed so far
    test    byte [rdi + MOB.affix], AFX_MOLTEN
    jz      .not_molten
    cmp     ecx, edx
    je      .burn
    inc     ecx
.not_molten:
    test    byte [rdi + MOB.affix], AFX_FROZEN
    jz      .not_frozen
    cmp     ecx, edx
    je      .chill
    inc     ecx
.not_frozen:
    test    byte [rdi + MOB.affix], AFX_VENOMOUS
    jz      .none
    cmp     ecx, edx
    je      .poison
.none:
    mov     eax, -1
    ret
.burn:
    mov     eax, STS_BURN
    mov     edx, [rsi + ELEM_FIRE*4]
    ret
.chill:
    mov     eax, STS_CHILL
    mov     edx, [rsi + ELEM_FROST*4]
    ret
.poison:
    mov     eax, STS_POISON
    mov     edx, [rsi + ELEM_POISON*4]
    ret

; mob_set_stun(edi idx, esi steps): the mob in slot idx is stunned for at least that many steps (a longer
; stun stays); an empty or bad slot changes nothing. On a guest the host owns the mob: a MOBFX message asks
; for the stun instead.
mob_set_stun:
    cmp     edi, MAX_MOBS
    jae     .ret
    cmp     byte [net_role], NET_ROLE_GUEST
    je      .ask
    imul    eax, edi, MOB_size
    lea     rcx, [mobs]
    add     rcx, rax
    cmp     dword [rcx + MOB.type], MOB_NONE
    je      .ret
    cmp     [rcx + MOB.stun], esi
    jge     .ret
    mov     [rcx + MOB.stun], esi
.ret:
    ret
.ask:
    test    esi, esi
    jle     .ret
    mov     edx, esi
    mov     esi, MFX_STUN
    jmp     net_mobfx_out               ; (edi idx, esi kind, edx ivalue, xmm0 fvalue)

; mob_set_mark(edi idx, esi steps): the mob in slot idx is Hunter's Marked for that many steps; an empty or
; bad slot changes nothing. On a guest a MOBFX message asks the host.
mob_set_mark:
    cmp     edi, MAX_MOBS
    jae     .ret
    cmp     byte [net_role], NET_ROLE_GUEST
    je      .ask
    imul    eax, edi, MOB_size
    lea     rcx, [mobs]
    add     rcx, rax
    cmp     dword [rcx + MOB.type], MOB_NONE
    je      .ret
    mov     [rcx + MOB.mark_t], esi
.ret:
    ret
.ask:
    mov     edx, esi
    mov     esi, MFX_MARK
    jmp     net_mobfx_out

; mob_launch(edi idx, xmm0 vy): the mob in slot idx is thrown up at vy blocks/s (BODY.vy = vy); an empty or
; bad slot changes nothing. On a guest a MOBFX message asks the host.
mob_launch:
    cmp     edi, MAX_MOBS
    jae     .ret
    cmp     byte [net_role], NET_ROLE_GUEST
    je      .ask
    imul    eax, edi, MOB_size
    lea     rcx, [mobs]
    add     rcx, rax
    cmp     dword [rcx + MOB.type], MOB_NONE
    je      .ret
    movss   [rcx + BODY.vy], xmm0
.ret:
    ret
.ask:
    mov     esi, MFX_LAUNCH
    xor     edx, edx
    jmp     net_mobfx_out

; mob_replica_init(rdi mob, esi type 1..8): a guest creates the copy of a host mob in the slot at rdi:
; everything cleared, the body given the type's box and speed (body_init as mob_spawn does) and the type set
mob_replica_init:
    push    rbx
    push    r12
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12d, esi
    lea     ecx, [rsi - 1]
    movss   xmm0, [t_half_w + rcx*4]
    movss   xmm1, [t_height + rcx*4]
    movss   xmm2, [t_speed + rcx*4]
    call    body_init                   ; zeroes the body, then sets box and speed
    lea     rdi, [rbx + BODY_size]      ; clear everything after the body
    mov     ecx, MOB_size - BODY_size
    xor     eax, eax
    rep     stosb
    mov     [rbx + MOB.type], r12d
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; mob_melee_hit(rdi mob, esi base, edx cause, xmm0 src_x, xmm1 src_z, xmm2 kb) -> eax HIT_*
; One melee blow of that mob on the player it hunts (mob_tgt_slot), from (src_x, src_z): mob_blow's damage
; through net_mob_hit_player. The local player takes it through player_take_hit, with combat_attacker naming
; the mob meanwhile (thorns strike back at it); another peer's game decides about its own player: HIT_REMOTE,
; the statuses and the shove (kb blocks/s, the caller's knockback speed) go with the HURT message. A blow
; that lands (HIT_TAKEN) also sets the player burning (MOLTEN), chilled (FROZEN) or poisoned
; (VENOMOUS) by that affix's part, and heals a VAMPIRIC mob by half the blow (at least 1, up to
; its maximum); a blow aimed at another peer heals it at once.
; Frame: [rsp] parts int[5], [rsp+20] src x, [rsp+24] src z, [rsp+28] kb, [rsp+32] status index
mob_melee_hit:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 40
    mov     rbx, rdi
    mov     r12d, edx
    movss   [rsp + 20], xmm0
    movss   [rsp + 24], xmm1
    movss   [rsp + 28], xmm2
    mov     rdx, rsp
    call    mob_blow                    ; rdi = the mob, esi = the base damage
    mov     r13d, eax                   ; the whole blow
    mov     rdi, rbx
    call    mob_index
    mov     [combat_attacker], eax
    mov     rdi, rbx
    mov     esi, r13d
    mov     edx, r12d
    mov     rcx, rsp
    movss   xmm0, [rsp + 20]
    movss   xmm1, [rsp + 24]
    movss   xmm2, [rsp + 28]
    movss   xmm3, [c_lift_vy]
    call    net_mob_hit_player
    mov     dword [combat_attacker], -1
    mov     r12d, eax                   ; HIT_*
    cmp     eax, HIT_REMOTE
    je      .vampiric
    cmp     eax, HIT_TAKEN
    jne     .ret
    mov     dword [rsp + 32], 0
.status:                                ; burn, chill, poison: the affixes' statuses in that order
    mov     rdi, rbx
    mov     rsi, rsp
    mov     edx, [rsp + 32]
    call    mob_affix_status
    test    eax, eax
    js      .vampiric
    mov     edi, eax
    mov     esi, edx
    call    combat_player_status
    inc     dword [rsp + 32]
    jmp     .status
.vampiric:
    test    byte [rbx + MOB.affix], AFX_VAMPIRIC
    jz      .ret
    mov     eax, r13d
    shr     eax, 1
    mov     ecx, 1
    cmp     eax, ecx
    cmovl   eax, ecx                    ; max(1, blow / 2)
    add     eax, [rbx + MOB.health]
    mov     ecx, [rbx + MOB.max_health]
    cmp     eax, ecx
    cmovg   eax, ecx
    mov     [rbx + MOB.health], eax
.ret:
    mov     eax, r12d
    add     rsp, 40
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; knock_player(rsi frame, xmm3 speed): shoves the player away along the frame's [dx, dz] (mob ->
; player on the ground plane, the horizontal distance^2 at [8]) at `speed` blocks/s and, when he
; stands on the ground, throws him up at 5 blocks/s; combat_kb_mult (0 with the Juggernaut
; keystone) scales both.
; Frame: [rsp] speed, [rsp+4] the multiplier
knock_player:
    push    rbx
    sub     rsp, 16
    mov     rbx, rsi
    movss   [rsp], xmm3
    call    combat_kb_mult
    movss   [rsp + 4], xmm0
    movss   xmm2, [rbx + 8]
    sqrtss  xmm2, xmm2                  ; horizontal distance
    comiss  xmm2, [c_tiny]
    jb      .lift                       ; standing exactly on the player: no direction
    movss   xmm3, [rsp]
    mulss   xmm3, [rsp + 4]
    divss   xmm3, xmm2
    movss   xmm0, [rbx]
    mulss   xmm0, xmm3
    movss   [player + BODY.kbx], xmm0
    movss   xmm1, [rbx + 4]
    mulss   xmm1, xmm3
    movss   [player + BODY.kbz], xmm1
.lift:
    cmp     dword [player + BODY.on_ground], 0
    je      .done
    movss   xmm0, [c_lift_vy]
    mulss   xmm0, [rsp + 4]
    movss   [player + BODY.vy], xmm0
.done:
    add     rsp, 16
    pop     rbx
    ret

; ai_creeper(rdi mob, rsi frame) -> eax 1 when it exploded (the mob is gone).
; frame = mob_ai's [dx, dz, horizontal distance^2]. A creeper walks up to the player; within 3
; blocks (between body centres) the fuse lights and keeps burning while the player stays
; within 7, else it dies down; once lit it stops walking within 2 blocks; at CREEPER_FUSE
; it blows up with radius 3 where it stands, hurting the player mob_dmg_mult(level) times harder.
ai_creeper:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdi
    mov     rax, [mob_tgt_body]
    movss   xmm0, [rax + BODY.y]
    addss   xmm0, [c_chest]
    movss   xmm1, [rbx + BODY.y]
    addss   xmm1, [c_mid]
    subss   xmm0, xmm1                  ; dy between the centres
    mulss   xmm0, xmm0
    addss   xmm0, [rsi + 8]             ; + horizontal distance^2
    cmp     dword [rbx + MOB.fuse], 0
    jne     .lit
    mov     dword [rbx + MOB.input + INPUT.fwd], 1
    comiss  xmm0, [c_ignite2]
    jae     .check
    mov     dword [rbx + MOB.fuse], 1   ; close enough: light the fuse
    mov     edi, SND_FUSE
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [c_vol_fuse]
    call    audio_play_at
    jmp     .check
.lit:
    xor     eax, eax
    comiss  xmm0, [c_stop2]
    seta    al
    mov     [rbx + MOB.input + INPUT.fwd], eax  ; walks on only while farther than 2 blocks
    comiss  xmm0, [c_calm2]
    jae     .dying
    inc     dword [rbx + MOB.fuse]
    jmp     .check
.dying:
    dec     dword [rbx + MOB.fuse]
.check:
    xor     eax, eax
    cmp     dword [rbx + MOB.fuse], CREEPER_FUSE
    jl      .ret
    mov     dword [rbx + MOB.type], MOB_NONE    ; gone before the blast looks for mobs to hurt
    mov     edi, [rbx + MOB.level]
    call    mob_dmg_mult
    movss   [explode_dmg_mult], xmm0
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    addss   xmm1, [c_mid]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [c_blast]
    call    explode_at
    mov     dword [explode_dmg_mult], 0 ; back to the environment's scaling
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ai_skeleton(rdi mob, rsi frame) -> eax 0.
; Keeps 5..10 blocks from the player (closes in beyond 10, backs off inside 5) and, every
; 40..69 steps, shoots an arrow when within 15 blocks with a clear line to the player's eye.
; The arrow leaves 0.6 blocks along the aim at 24 blocks/s, lifted against gravity and
; scattered by the difficulty; it carries the blow's damage (mob_blow) and the element of the
; shooter's first elemental affix.
; Frame: own eye o[3] @0, unit aim dir[3] @12, player eye[3] @24, distance @36,
; sx @44, sz @48, RAYHIT scratch @52 (24 bytes), the arrow's damage @72, clamped difficulty @76.
ai_skeleton:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 80
    mov     rbx, rdi
    mov     r12, rsi
    xor     eax, eax
    movss   xmm0, [r12 + 8]             ; horizontal distance^2
    comiss  xmm0, [c_far_in2]
    jbe     .not_far
    mov     eax, 1                      ; too far to shoot well: close in
    jmp     .set_fwd
.not_far:
    comiss  xmm0, [c_near2]
    jae     .set_fwd                    ; 5..10 blocks: stand and shoot
    mov     eax, -1                     ; too close: back away, still facing the player
.set_fwd:
    mov     [rbx + MOB.input + INPUT.fwd], eax
    cmp     dword [rbx + MOB.cooldown], 0
    jne     .done
    comiss  xmm0, [c_shoot2]
    jae     .done
    movss   xmm0, [rbx + BODY.x]        ; own eye
    movss   [rsp], xmm0
    movss   xmm0, [rbx + BODY.y]
    addss   xmm0, [c_eye]
    movss   [rsp + 4], xmm0
    movss   xmm0, [rbx + BODY.z]
    movss   [rsp + 8], xmm0
    mov     rax, [mob_tgt_body]         ; the hunted player's eye: feet + 1.62 up
    mov     ecx, [rax + BODY.x]
    mov     [rsp + 24], ecx
    movss   xmm0, [rax + BODY.y]
    addss   xmm0, [c_eye]
    movss   [rsp + 28], xmm0
    mov     ecx, [rax + BODY.z]
    mov     [rsp + 32], ecx
    xor     ecx, ecx
.aim:                                   ; dir = player eye - own eye
    movss   xmm0, [rsp + 24 + rcx*4]
    subss   xmm0, [rsp + rcx*4]
    movss   [rsp + 12 + rcx*4], xmm0
    inc     ecx
    cmp     ecx, 3
    jb      .aim
    movss   xmm0, [rsp + 12]
    mulss   xmm0, xmm0
    movss   xmm1, [rsp + 16]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    movss   xmm1, [rsp + 20]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    sqrtss  xmm0, xmm0                  ; distance
    comiss  xmm0, [c_tiny]
    jb      .done                       ; eye to eye: no direction to aim along
    movss   [rsp + 36], xmm0
    xor     ecx, ecx
.unit:
    movss   xmm1, [rsp + 12 + rcx*4]
    divss   xmm1, xmm0
    movss   [rsp + 12 + rcx*4], xmm1
    inc     ecx
    cmp     ecx, 3
    jb      .unit
    lea     rdi, [rsp]                  ; line of sight: no block between the two eyes
    lea     rsi, [rsp + 12]
    lea     rdx, [rsp + 52]
    movss   xmm0, [rsp + 36]
    call    raycast
    test    eax, eax
    jnz     .done
    mov     eax, [settings + SETTINGS.difficulty]
    mov     ecx, DIFF_HARD
    cmp     eax, ecx
    cmova   eax, ecx
    mov     [rsp + 76], eax
    mov     rdi, rbx                    ; the arrow's damage: its level's blow with the elemental parts
    mov     esi, [t_dmg + rax*4]
    xor     edx, edx
    call    mob_blow
    mov     [rsp + 72], eax
    call    rng_next                    ; aim error: (rng % 201 - 100) / 100 * spread, per axis
    xor     edx, edx
    mov     ecx, 201
    div     ecx
    sub     edx, 100
    cvtsi2ss xmm0, edx
    mulss   xmm0, [c_cent]
    mov     eax, [rsp + 76]
    mulss   xmm0, [t_spread + rax*4]
    movss   [rsp + 44], xmm0
    call    rng_next
    xor     edx, edx
    mov     ecx, 201
    div     ecx
    sub     edx, 100
    cvtsi2ss xmm0, edx
    mulss   xmm0, [c_cent]
    mov     eax, [rsp + 76]
    mulss   xmm0, [t_spread + rax*4]
    movss   [rsp + 48], xmm0
    movss   xmm6, [rsp + 36]            ; flight time dist / 24: lift 10 t against gravity
    divss   xmm6, [c_arrow_v]
    mulss   xmm6, [c_lift]
    movss   xmm3, [rsp + 12]
    mulss   xmm3, [c_arrow_v]
    addss   xmm3, [rsp + 44]            ; vx
    movss   xmm4, [rsp + 16]
    mulss   xmm4, [c_arrow_v]
    addss   xmm4, xmm6                  ; vy
    movss   xmm5, [rsp + 20]
    mulss   xmm5, [c_arrow_v]
    addss   xmm5, [rsp + 48]            ; vz
    movss   xmm0, [rsp + 12]            ; starts 0.6 blocks along the aim
    mulss   xmm0, [c_muzzle]
    addss   xmm0, [rsp]
    movss   xmm1, [rsp + 16]
    mulss   xmm1, [c_muzzle]
    addss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 20]
    mulss   xmm2, [c_muzzle]
    addss   xmm2, [rsp + 8]
    mov     rdi, rbx                    ; an elemental elite's arrow carries its element
    call    mob_arrow_flags
    mov     r8d, eax
    mov     edi, OWNER_MONSTER          ; fired by a mob
    mov     esi, [rsp + 72]
    xor     edx, edx                    ; cannot be picked up
    mov     ecx, PROJ_ARROW
    call    arrows_spawn
    mov     edi, SND_BOW
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [c_vol_bow]
    call    audio_play_at
    call    rng_next                    ; reload: 40..69 steps
    xor     edx, edx
    mov     ecx, 30
    div     ecx
    add     edx, 40
    mov     [rbx + MOB.cooldown], edx
.done:
    xor     eax, eax
    add     rsp, 80
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ai_spider(rdi mob, rsi frame) -> eax 0.
; Always runs at the player and climbs what blocks it. Within 1.4 blocks it rears up (12 steps,
; elite 10, SWIFT 3/4 of that) standing still, then bites through mob_melee_hit (every 20 steps) if
; the player is still in reach; from 2..4 blocks away it leaps at him (every 30 steps, from the
; ground). A parried bite stuns it, unless it is a JUGGERNAUT.
ai_spider:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    mov     rbx, rdi
    mov     r12, rsi
    mov     dword [rbx + MOB.input + INPUT.fwd], 1
    cmp     dword [rbx + BODY.blocked], 0
    je      .free
    mov     eax, [c_climb]              ; against a wall: climb it
    mov     [rbx + BODY.vy], eax
.free:
    cmp     dword [rbx + MOB.windup], 0
    jg      .winding
    cmp     dword [rbx + MOB.cooldown], 0
    jne     .done
    movss   xmm0, [r12 + 8]             ; horizontal distance^2
    comiss  xmm0, [c_bite2]
    jae     .leap
    mov     rax, [mob_tgt_body]
    movss   xmm1, [rax + BODY.y]
    subss   xmm1, [rbx + BODY.y]
    mulss   xmm1, xmm1
    comiss  xmm1, [c_reach_y2]
    jae     .done                       ; above or below its reach
    mov     eax, SPIDER_WINDUP          ; in reach: rear up
    mov     ecx, SPIDER_WINDUP_ELITE
    cmp     dword [rbx + MOB.elite], 0
    cmovne  eax, ecx
    SWIFT_WINDUP eax
    mov     [rbx + MOB.windup], eax
    mov     dword [rbx + MOB.input + INPUT.fwd], 0
    jmp     .done
.winding:
    mov     dword [rbx + MOB.input + INPUT.fwd], 0
    dec     dword [rbx + MOB.windup]
    jnz     .done                       ; still rearing
    mov     rax, [mob_tgt_body]
    movss   xmm1, [rax + BODY.y]        ; the bite lands only on a player still in reach
    subss   xmm1, [rbx + BODY.y]
    mulss   xmm1, xmm1
    comiss  xmm1, [c_reach_y2]
    jae     .bitten
    movss   xmm0, [r12 + 8]
    comiss  xmm0, [c_bite_end2]
    ja      .bitten
    mov     eax, [settings + SETTINGS.difficulty]
    mov     ecx, DIFF_HARD
    cmp     eax, ecx
    cmova   eax, ecx
    mov     esi, [t_dmg_spider + rax*4]
    mov     rdi, rbx
    mov     edx, CAUSE_SPIDER
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.z]
    movss   xmm2, [c_kb_spider]
    call    mob_melee_hit
    cmp     eax, HIT_PARRIED
    je      .parried
    cmp     eax, HIT_TAKEN
    jne     .bitten                     ; blocked or dodged: no knockback
    mov     rsi, r12                    ; knock the player back along spider -> player
    movss   xmm3, [c_kb_spider]
    call    knock_player
.bitten:
    mov     dword [rbx + MOB.cooldown], 20
    jmp     .done
.parried:                               ; the riposte stuns it: it reels back and stands dazed
    test    byte [rbx + MOB.affix], AFX_JUGGERNAUT
    jnz     .bitten                     ; a juggernaut shrugs the riposte off
    mov     dword [rbx + MOB.stun], STUN_PARRIED
    mov     rdi, rbx
    mov     rsi, r12
    call    mob_reel
    mov     rdi, rbx
    call    mob_stunned_text
    jmp     .bitten
.leap:
    cmp     dword [rbx + BODY.on_ground], 0
    je      .done
    comiss  xmm0, [c_leap_lo2]
    jb      .done
    comiss  xmm0, [c_leap_hi2]
    ja      .done
    sqrtss  xmm2, xmm0
    movss   xmm3, [c_kb_spider]
    divss   xmm3, xmm2
    movss   xmm0, [r12]
    mulss   xmm0, xmm3
    movss   [rbx + BODY.kbx], xmm0      ; hurl itself at the player
    movss   xmm1, [r12 + 4]
    mulss   xmm1, xmm3
    movss   [rbx + BODY.kbz], xmm1
    mov     eax, [c_leap_vy]
    mov     [rbx + BODY.vy], eax
    mov     dword [rbx + MOB.cooldown], 30
.done:
    xor     eax, eax
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ai_boss(rdi mob, rsi frame) -> eax 0.  The Fallen King.
; frame = mob_ai's [dx, dz, horizontal distance^2]. Phase 1 above 66 % health, phase 2 above 33 %,
; phase 3 below. He walks at the player (phase 3: 1.4 x faster), stopping 1.6 blocks short. Within 3
; blocks, off cooldown, he raises his fists (36 steps, phase 3: 24) and slams the floor (boss_slam).
; Every 600 steps timer_a summons skeletons (boss_summon); every 240 steps timer_b looses a volley
; in phases 2 and 3 (boss_volley). mob_update counts both timers down before the AI runs.
ai_boss:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12, rsi
    mov     eax, [rbx + MOB.health]
    imul    eax, eax, 100
    mov     ecx, [rbx + MOB.max_health]
    imul    edx, ecx, 66
    mov     r13d, 1
    cmp     eax, edx
    jg      .phased
    imul    edx, ecx, 33
    mov     r13d, 2
    cmp     eax, edx
    jg      .phased
    mov     r13d, 3
.phased:
    movss   xmm0, [c_boss_speed]
    cmp     r13d, 3
    jne     .speed
    mulss   xmm0, [c_boss_rage]
.speed:
    movss   [rbx + BODY.speed], xmm0
    cmp     dword [rbx + MOB.windup], 0
    jg      .winding
    xor     eax, eax                    ; walk at the player until 1.6 blocks away
    movss   xmm0, [r12 + 8]
    comiss  xmm0, [c_boss_stop2]
    setae   al
    mov     [rbx + MOB.input + INPUT.fwd], eax
    cmp     dword [rbx + MOB.cooldown], 0
    jne     .timers
    mov     rax, [mob_tgt_body]
    movss   xmm1, [rax + BODY.y]
    subss   xmm1, [rbx + BODY.y]
    mulss   xmm1, xmm1
    addss   xmm1, xmm0                  ; distance^2 including the height difference
    comiss  xmm1, [c_slam_start2]
    jae     .timers
    mov     eax, BOSS_WINDUP            ; within 3 blocks: raise the fists, standing still
    mov     ecx, BOSS_WINDUP_RAGE
    cmp     r13d, 3
    cmove   eax, ecx
    mov     [rbx + MOB.windup], eax
    mov     dword [rbx + MOB.input + INPUT.fwd], 0
    jmp     .timers
.winding:
    mov     dword [rbx + MOB.input + INPUT.fwd], 0
    dec     dword [rbx + MOB.windup]
    jnz     .timers
    mov     rdi, rbx
    mov     rsi, r12
    mov     edx, r13d
    call    boss_slam
    cmp     dword [rbx + MOB.type], MOB_BOSS
    jne     .done                       ; Thorns killed it mid-slam: the slot is dead or reused
.timers:
    cmp     dword [rbx + MOB.timer_a], 0
    jne     .volley
    mov     dword [rbx + MOB.timer_a], BOSS_SUMMON_STEPS
    mov     rdi, rbx
    call    boss_summon
.volley:
    cmp     dword [rbx + MOB.timer_b], 0
    jne     .done
    mov     dword [rbx + MOB.timer_b], BOSS_VOLLEY_STEPS
    cmp     r13d, 2
    jb      .done                       ; phase 1 keeps to melee
    mov     rdi, rbx
    call    boss_volley
.done:
    xor     eax, eax
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; boss_slam(rdi mob, rsi frame, edx phase): the fists come down. A player within 3.5 blocks (phase 3:
; 5) horizontally and 2.5 vertically takes the hit through mob_melee_hit: a parry stuns the boss
; for 30 steps, a hit shoves the player away at 10 blocks/s and throws him up. Either way the floor
; shakes (fx_explosion, SND_SLAM) and the slam cools down for 70 steps (phase 3: 45).
boss_slam:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13d, edx
    mov     rax, [mob_tgt_body]
    movss   xmm0, [rax + BODY.y]
    subss   xmm0, [rbx + BODY.y]
    mulss   xmm0, xmm0
    comiss  xmm0, [c_slam_dy2]
    jae     .impact                     ; too far above or below
    movss   xmm0, [r12 + 8]
    movss   xmm1, [c_slam2]
    cmp     r13d, 3
    jne     .reach
    movss   xmm1, [c_slam2_rage]
.reach:
    comiss  xmm0, xmm1
    jae     .impact                     ; too far away
    mov     eax, [settings + SETTINGS.difficulty]
    mov     ecx, DIFF_HARD
    cmp     eax, ecx
    cmova   eax, ecx
    mov     esi, [t_dmg_slam + rax*4]
    mov     rdi, rbx
    mov     edx, CAUSE_BOSS
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.z]
    movss   xmm2, [c_slam_kb]
    call    mob_melee_hit
    cmp     eax, HIT_PARRIED
    je      .parried
    cmp     eax, HIT_TAKEN
    jne     .impact                     ; blocked or dodged
    mov     rsi, r12                    ; shove the player along boss -> player
    movss   xmm3, [c_slam_kb]
    call    knock_player
    jmp     .impact
.parried:
    mov     dword [rbx + MOB.stun], BOSS_STUN
    mov     rdi, rbx
    call    mob_stunned_text
.impact:
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    addss   xmm1, [c_slam_lift]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [c_slam_fx]
    call    fx_explosion
    mov     edi, SND_SLAM
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [c_vol_hurt]
    call    audio_play_at
    mov     eax, BOSS_COOLDOWN
    mov     ecx, BOSS_COOLDOWN_RAGE
    cmp     r13d, 3
    cmove   eax, ecx
    mov     [rbx + MOB.cooldown], eax
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; boss_summon(rdi mob): two skeletons rise 2 blocks to either side of him, unless 4 already live
boss_summon:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdi
    mov     edi, MOB_SKELETON
    call    mob_count_type
    cmp     eax, BOSS_MAX_MINIONS
    jae     .done
    mov     edi, MOB_SKELETON
    movss   xmm0, [rbx + BODY.x]
    subss   xmm0, [c_two]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    call    mob_spawn
    mov     edi, MOB_SKELETON
    movss   xmm0, [rbx + BODY.x]
    addss   xmm0, [c_two]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    call    mob_spawn
.done:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; boss_volley(rdi mob): 5 skeleton arrows fanned -20..+20 degrees (10 apart) around the aim at the
; player's eye, from his head, at 30 blocks/s, lifted against gravity like a skeleton's
; Frame: own head o[3] @0, unit aim dir[3] @12, player eye[3] @24, distance @36, lift @44... see
; the offsets below: lift @40, sin @44, cos @48, rotated dx @52 and dz @60, each arrow's damage @64.
boss_volley:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 80
    mov     rbx, rdi
    movss   xmm0, [rbx + BODY.x]
    movss   [rsp], xmm0
    movss   xmm0, [rbx + BODY.y]
    addss   xmm0, [c_boss_eye]
    movss   [rsp + 4], xmm0
    movss   xmm0, [rbx + BODY.z]
    movss   [rsp + 8], xmm0
    mov     rax, [mob_tgt_body]         ; the hunted player's eye: feet + 1.62 up
    mov     ecx, [rax + BODY.x]
    mov     [rsp + 24], ecx
    movss   xmm0, [rax + BODY.y]
    addss   xmm0, [c_eye]
    movss   [rsp + 28], xmm0
    mov     ecx, [rax + BODY.z]
    mov     [rsp + 32], ecx
    xor     ecx, ecx
.aim:                                   ; dir = player eye - own head
    movss   xmm0, [rsp + 24 + rcx*4]
    subss   xmm0, [rsp + rcx*4]
    movss   [rsp + 12 + rcx*4], xmm0
    inc     ecx
    cmp     ecx, 3
    jb      .aim
    movss   xmm0, [rsp + 12]
    mulss   xmm0, xmm0
    movss   xmm1, [rsp + 16]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    movss   xmm1, [rsp + 20]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    sqrtss  xmm0, xmm0                  ; distance
    comiss  xmm0, [c_tiny]
    jb      .done                       ; eye to eye: no direction to aim along
    movss   [rsp + 36], xmm0
    xor     ecx, ecx
.unit:
    movss   xmm1, [rsp + 12 + rcx*4]
    divss   xmm1, xmm0
    movss   [rsp + 12 + rcx*4], xmm1
    inc     ecx
    cmp     ecx, 3
    jb      .unit
    movss   xmm0, [rsp + 36]            ; flight time dist / 30: lift 10 t against gravity
    divss   xmm0, [c_volley_v]
    mulss   xmm0, [c_lift]
    movss   [rsp + 40], xmm0
    mov     eax, [settings + SETTINGS.difficulty]
    mov     ecx, DIFF_HARD
    cmp     eax, ecx
    cmova   eax, ecx
    mov     rdi, rbx                    ; each arrow's damage: his level's blow
    mov     esi, [t_dmg_volley + rax*4]
    xor     edx, edx
    call    mob_blow
    mov     [rsp + 64], eax
    mov     r12d, -2
.arrow:
    cvtsi2ss xmm0, r12d
    mulss   xmm0, [c_fan_step]
    call    sincos_deg                  ; xmm0 = sin, xmm1 = cos of the fan angle
    movss   xmm2, [rsp + 12]            ; turn the aim about the vertical axis
    movss   xmm3, [rsp + 20]
    movaps  xmm4, xmm2
    mulss   xmm4, xmm1                  ; dx cos
    movaps  xmm5, xmm3
    mulss   xmm5, xmm0                  ; dz sin
    subss   xmm4, xmm5
    movss   [rsp + 52], xmm4            ; dx' = dx cos - dz sin
    mulss   xmm2, xmm0                  ; dx sin
    mulss   xmm3, xmm1                  ; dz cos
    addss   xmm2, xmm3
    movss   [rsp + 60], xmm2            ; dz' = dx sin + dz cos
    movss   xmm3, [rsp + 52]
    mulss   xmm3, [c_volley_v]          ; vx
    movss   xmm4, [rsp + 16]
    mulss   xmm4, [c_volley_v]
    addss   xmm4, [rsp + 40]            ; vy
    movss   xmm5, [rsp + 60]
    mulss   xmm5, [c_volley_v]          ; vz
    movss   xmm0, [rsp + 52]            ; the arrow starts 0.8 blocks along its heading
    mulss   xmm0, [c_volley_muzzle]
    addss   xmm0, [rsp]
    movss   xmm1, [rsp + 16]
    mulss   xmm1, [c_volley_muzzle]
    addss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 60]
    mulss   xmm2, [c_volley_muzzle]
    addss   xmm2, [rsp + 8]
    mov     esi, [rsp + 64]
    mov     edi, OWNER_MONSTER          ; fired by a mob
    xor     edx, edx                    ; cannot be picked up
    mov     ecx, PROJ_ARROW
    xor     r8d, r8d
    call    arrows_spawn
    inc     r12d
    cmp     r12d, 2
    jle     .arrow
    mov     edi, SND_BOW
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [c_vol_bow]
    call    audio_play_at
.done:
    add     rsp, 80
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mob_update(rdi mob): one fixed step for a live mob (timers, AI, physics, sound, sunlight, despawn).
; Frame: [rsp] x and [rsp+4] z before the move, [rsp+8] the speed before the chill.
mob_update:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 24
    mov     rbx, rdi
    DEC_TIMER MOB.stun                  ; counted down first, so the AI sees this step's values
    DEC_TIMER MOB.tagged
    DEC_TIMER MOB.bar
    DEC_TIMER MOB.timer_a
    DEC_TIMER MOB.timer_b
    call    mob_ai
    test    eax, eax
    jnz     .done                       ; blew up: nothing left to move
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .done                       ; a thorns blow killed it mid-attack
    movss   xmm0, [rbx + BODY.x]
    movss   [rsp], xmm0
    movss   xmm0, [rbx + BODY.z]
    movss   [rsp + 4], xmm0
    mov     eax, [rbx + BODY.speed]     ; a chilled mob walks slower for this step only
    mov     [rsp + 8], eax
    mov     rdi, rbx
    call    status_speed_mult
    mulss   xmm0, [rbx + BODY.speed]
    movss   [rbx + BODY.speed], xmm0
    mov     rdi, rbx
    lea     rsi, [rbx + MOB.input]
    call    body_step
    mov     eax, [rsp + 8]
    mov     [rbx + BODY.speed], eax
    cmp     dword [rbx + MOB.type], MOB_CHICKEN
    jne     .no_glide
    movss   xmm0, [rbx + BODY.vy]       ; chickens flutter down: they never fall faster than 3 blocks/s
    maxss   xmm0, [c_glide]
    movss   [rbx + BODY.vy], xmm0
.no_glide:
    movss   xmm0, [rbx + BODY.x]        ; walk cycle: 180 degrees per block walked
    subss   xmm0, [rsp]
    mulss   xmm0, xmm0
    movss   xmm1, [rbx + BODY.z]
    subss   xmm1, [rsp + 4]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    sqrtss  xmm0, xmm0
    mulss   xmm0, [c_180]
    addss   xmm0, [rbx + MOB.walk]
    movss   xmm1, [c_360]
    comiss  xmm0, xmm1
    jb      .walk_ok
    subss   xmm0, xmm1                  ; one wrap is enough: a step adds < 360 degrees (< 2 blocks)
.walk_ok:
    movss   [rbx + MOB.walk], xmm0
    cmp     dword [rbx + MOB.hurt], 0
    jle     .no_hurt
    dec     dword [rbx + MOB.hurt]
.no_hurt:
    cmp     dword [rbx + MOB.cooldown], 0
    jle     .no_cooldown
    dec     dword [rbx + MOB.cooldown]
.no_cooldown:
    call    rng_next                    ; ambient call about every 10 s
    xor     edx, edx
    mov     ecx, 600
    div     ecx
    test    edx, edx
    jnz     .quiet
    mov     eax, [rbx + MOB.type]
    movzx   edi, byte [t_say + rax - 1]
    cmp     edi, 0xFF
    je      .quiet                      ; creepers make no ambient sound
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [c_vol_say]
    call    audio_play_at
.quiet:
    mov     eax, [rbx + MOB.type]
    cmp     byte [t_hostile + rax - 1], 0
    je      .done                       ; passive mobs neither burn nor despawn
    cmp     byte [t_burns + rax - 1], 0
    je      .despawn                    ; hostile but sun-proof
    mov     eax, [game_time]            ; sunlight: -2 health every 20 steps in bright daylight
    xor     edx, edx
    mov     ecx, 20
    div     ecx
    test    edx, edx
    jnz     .despawn
    mov     edi, [game_time]
    call    sky_brightness
    comiss  xmm0, [c_day]
    jb      .despawn
    movss   xmm0, [rbx + BODY.x]
    roundss xmm0, xmm0, 9
    cvttss2si edi, xmm0
    movss   xmm0, [rbx + BODY.z]
    roundss xmm0, xmm0, 9
    cvttss2si esi, xmm0
    call    world_top_y
    movss   xmm0, [rbx + BODY.y]
    addss   xmm0, [rbx + BODY.height]
    roundss xmm0, xmm0, 9
    cvttss2si ecx, xmm0                 ; cell of the head top
    cmp     eax, ecx
    jge     .despawn                    ; roofed over: the sun cannot reach it
    sub     dword [rbx + MOB.health], 2
    jg      .despawn
    mov     dword [rbx + MOB.type], MOB_NONE
    jmp     .done
.despawn:
    cmp     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL
    je      .remove                     ; peaceful: no zombies at all
    cmp     byte [net_role], NET_ROLE_OFF
    je      .near_local
    movss   xmm0, [rbx + BODY.x]        ; online: it stays while any player is within 96 blocks
    movss   xmm1, [rbx + BODY.z]
    call    net_nearest_dist2
    jmp     .far
.near_local:
    movss   xmm0, [player + BODY.x]
    subss   xmm0, [rbx + BODY.x]
    mulss   xmm0, xmm0
    movss   xmm1, [player + BODY.z]
    subss   xmm1, [rbx + BODY.z]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
.far:
    comiss  xmm0, [c_far2]
    jbe     .done
.remove:
    mov     dword [rbx + MOB.type], MOB_NONE
.done:
    add     rsp, 24
    pop     rbx
    pop     rbp
    ret

; spawn_at_ground(edi type, esi x, edx z, ecx ground kind) -> eax slot index, or -1.
; (x, z) is a local cell. Its column must be ready and its top block at y <= 254. The mob stands on
; the top block, in the cell above it; when that block is TALL_GRASS or SNOW_LAYER it stands in that
; cell instead, on the block below. The cell it stands in is never WATER or LAVA. GROUND_HOSTILE wants a
; solid, opaque block that is not BEDROCK or foliage (LEAVES, PINE_LEAVES, BIRCH_LEAVES) under it,
; GROUND_PASSIVE wants GRASS or DRY_GRASS. A hostile type also needs block light < 8 in its cell (a torch keeps
; its surroundings clear); a spider (1.4 blocks wide) also needs the 3 x 3 cells around that cell
; free (air, TALL_GRASS or SNOW_LAYER).
; rbx = type, r12d, r13d = x, z, r14d = ground kind, r15d = y of the top block;
; frame: [rsp] y of the cell the mob stands in, [rsp+4] id of the block under it.
spawn_at_ground:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    mov     edi, r12d
    mov     esi, r13d
    call    world_column_ready
    test    eax, eax
    jz      .fail
    mov     edi, r12d
    mov     esi, r13d
    call    world_top_y
    test    eax, eax
    js      .fail                       ; empty column
    cmp     eax, 254
    jg      .fail                       ; no room above the top
    mov     r15d, eax
    mov     edi, r12d
    mov     esi, r15d
    mov     edx, r13d
    call    world_get                   ; the top block
    lea     ecx, [r15 + 1]
    mov     [rsp], ecx                  ; it is the ground: the mob stands in the cell above
    cmp     eax, TALL_GRASS
    je      .plant
    cmp     eax, SNOW_LAYER
    jne     .ground
.plant:                                 ; a plant or a snow layer: the mob stands in that very cell
    test    r15d, r15d
    jz      .fail
    mov     [rsp], r15d
    mov     edi, r12d
    lea     esi, [r15 - 1]
    mov     edx, r13d
    call    world_get                   ; ...on the block below it
.ground:
    mov     [rsp + 4], eax
    mov     edi, r12d                   ; the cell it stands in is never water or lava
    mov     esi, [rsp]
    mov     edx, r13d
    call    world_get
    cmp     eax, WATER
    je      .fail
    cmp     eax, LAVA
    je      .fail
    mov     eax, [rsp + 4]
    test    r14d, r14d
    jnz     .passive
    cmp     eax, BEDROCK
    je      .fail
    cmp     eax, LEAVES
    je      .fail
    cmp     eax, PINE_LEAVES
    je      .fail
    cmp     eax, BIRCH_LEAVES
    je      .fail
    lea     rcx, [block_flags]
    movzx   ecx, byte [rcx + rax]
    and     ecx, FLAG_SOLID | FLAG_OPAQUE
    cmp     ecx, FLAG_SOLID | FLAG_OPAQUE
    jne     .fail
    jmp     .ground_ok
.passive:
    cmp     eax, GRASS
    je      .ground_ok
    cmp     eax, DRY_GRASS
    jne     .fail
.ground_ok:
    lea     eax, [rbx - 1]
    cmp     eax, NUM_MOB_TYPES
    jae     .lit_ok
    cmp     byte [t_hostile + rax], 0
    je      .lit_ok
    mov     edi, r12d
    mov     esi, [rsp]
    mov     edx, r13d
    call    light_get
    and     eax, 15                     ; the block-light nibble
    cmp     eax, 8
    jae     .fail
.lit_ok:
    cmp     ebx, MOB_SPIDER
    jne     .place
    mov     edi, r12d
    mov     esi, [rsp]
    mov     edx, r13d
    call    area_clear
    test    eax, eax
    jz      .fail
.place:
    movss   xmm3, [c_half]
    cvtsi2ss xmm0, r12d
    addss   xmm0, xmm3                  ; x + 0.5
    cvtsi2ss xmm1, dword [rsp]          ; on top of the ground
    cvtsi2ss xmm2, r13d
    addss   xmm2, xmm3                  ; z + 0.5
    mov     edi, ebx
    call    mob_spawn
    jmp     .ret
.fail:
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

; spawn_near_player(edi type, esi min distance, edx distance range, ecx ground kind) -> eax slot or -1.
; Picks a random bearing and a distance in [min, min + range) around the player.
; Frame: [rsp] sin, [rsp+4] cos of the bearing.
spawn_near_player:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 16
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    call    rng_next                    ; bearing = rng % 360 degrees
    xor     edx, edx
    mov     ecx, 360
    div     ecx
    cvtsi2ss xmm0, edx
    call    sincos_deg
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    call    rng_next                    ; distance
    xor     edx, edx
    div     r13d
    add     edx, r12d
    cvtsi2ss xmm2, edx
    movss   xmm0, [rsp]
    mulss   xmm0, xmm2
    mov     rax, [spawn_ctr]            ; the centre: the local player, unless a spawn is around a remote one
    lea     rcx, [player]
    test    rax, rax
    cmovz   rax, rcx
    addss   xmm0, [rax + BODY.x]        ; x = px + sin * dist
    roundss xmm0, xmm0, 9
    cvttss2si esi, xmm0
    movss   xmm1, [rsp + 4]
    mulss   xmm1, xmm2
    movss   xmm3, [rax + BODY.z]
    subss   xmm3, xmm1                  ; z = pz - cos * dist
    roundss xmm3, xmm3, 9
    cvttss2si edx, xmm3
    mov     edi, ebx
    mov     ecx, r14d
    call    spawn_at_ground
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; area_clear(edi x, esi y, edx z) -> eax 1 when the 3 x 3 cells centred on (x, y, z) are all free:
; air, TALL_GRASS or SNOW_LAYER (nothing there stops a body)
area_clear:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edx
    mov     ebx, 9                      ; cell index 8..0: column = i % 3, row = i / 3
.cell:
    dec     ebx
    js      .clear
    mov     eax, ebx
    xor     edx, edx
    mov     ecx, 3
    div     ecx
    lea     edi, [r12 + rdx - 1]
    lea     edx, [r14 + rax - 1]
    mov     esi, r13d
    call    world_get
    test    eax, eax
    jz      .cell
    cmp     eax, TALL_GRASS
    je      .cell
    cmp     eax, SNOW_LAYER
    je      .cell
    xor     eax, eax
    jmp     .ret
.clear:
    mov     eax, 1
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; spawn_passive(edi type, esi cap): one more of that type around the player (24..48 blocks
; away, on grass) unless `cap` already live
spawn_passive:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12d, esi
    call    mob_count_type
    cmp     eax, r12d
    jae     .done
    mov     edi, ebx
    mov     esi, 24
    mov     edx, 25
    mov     ecx, GROUND_PASSIVE
    call    spawn_near_player
.done:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; spawn_gather() -> eax the number of centres the night spawner serves: the local player (sc_body[0], level 0) and, on a host,
; every remote player who lives (nm_centre: his body and level), at most SC_MAX. Fills sc_n, sc_body, sc_level, sc_total (every
; live hostile mob) and sc_cnt: with one centre sc_cnt[0] is sc_total (every hostile mob there is counts, as in an offline
; game), with more sc_cnt[c] is the number of hostile mobs within 96 blocks of centre c (spawn_tally).
; rbx = the mob, r12d = centres so far, r13d = the remote player asked for
spawn_gather:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    lea     rax, [player]
    mov     [sc_body], rax
    mov     dword [sc_level], 0
    mov     r12d, 1
    xor     r13d, r13d
    cmp     byte [net_role], NET_ROLE_OFF
    je      .count
.remote:
    cmp     r12d, SC_MAX
    jae     .count
    mov     edi, r13d
    call    nm_centre                   ; rax = the BODY of the r13d-th remote player who lives, edx = his level
    test    rax, rax
    jz      .count
    lea     rcx, [sc_body]
    mov     [rcx + r12*8], rax
    lea     rcx, [sc_level]
    mov     [rcx + r12*4], edx
    inc     r12d
    inc     r13d
    jmp     .remote
.count:
    mov     [sc_n], r12d
    mov     edi, 1
    call    mob_count_kind
    mov     [sc_total], eax
    mov     [sc_cnt], eax               ; (one centre: all of them)
    cmp     r12d, 1
    jbe     .ret
    lea     rdi, [sc_cnt]               ; several: each counts its own neighbourhood
    xor     eax, eax
    mov     ecx, SC_MAX
    rep     stosd
    lea     rbx, [mobs]
.mob:
    mov     eax, [rbx + MOB.type]
    test    eax, eax
    jz      .next
    movzx   eax, byte [t_hostile + rax - 1]
    cmp     eax, 1
    jne     .next
    mov     rdi, rbx
    call    spawn_tally
.next:
    add     rbx, MOB_size
    lea     rax, [mobs_end]
    cmp     rbx, rax
    jb      .mob
.ret:
    mov     eax, [sc_n]
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; spawn_tally(rdi mob): a hostile mob counts for every spawn centre within 96 blocks of it (c_far2: the distance past which a
; hostile mob vanishes): sc_cnt[c] goes up for each
spawn_tally:
    mov     ecx, [sc_n]
    lea     rsi, [sc_body]
    lea     rdx, [sc_cnt]
.centre:
    mov     rax, [rsi]
    movss   xmm0, [rdi + BODY.x]
    subss   xmm0, [rax + BODY.x]
    mulss   xmm0, xmm0
    movss   xmm1, [rdi + BODY.z]
    subss   xmm1, [rax + BODY.z]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [c_far2]
    jae     .next
    inc     dword [rdx]
.next:
    add     rsi, 8
    add     rdx, 4
    dec     ecx
    jnz     .centre
    ret

; mobs_spawn_tick(): the ambient spawner, once per fixed step.
; Every 60 steps at night in Survival (difficulty > 0): a zombie, skeleton, creeper or spider around each player, 4 % of them
; elite (make_elite). Every player is a centre of his own: the local one and, on a host, every remote player who lives
; (spawn_gather). A centre gets a spawn while fewer than 12 hostile mobs live within 96 blocks of it and fewer than 48 live in
; all, so each player meets what a game of his own would give him, whoever else plays and however far: a guest 5000 blocks away
; is not starved by the mobs that crowd the host. The centres take their turns from a start that rotates every tick, so that none
; is always first when it is the total that runs short. A game with one centre (offline, or a host nobody has joined) counts every
; hostile mob there is and has no total limit: the rule it always had. An attempt is at the level of the player it spawns
; around (mob_spawn_level). Every 1800 steps by day: a pig (at most 10) and a chicken (at most 8), around one player per tick,
; in turn.
; r12d = the centre being served, r13d = centres still to serve, ebx = the mob spawned
mobs_spawn_tick:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     eax, [game_time]
    xor     edx, edx
    mov     ecx, 60
    div     ecx
    test    edx, edx
    jnz     .passive
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .passive
    cmp     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL
    je      .passive
    mov     edi, [game_time]
    call    sky_is_night
    test    eax, eax
    jz      .passive
    call    spawn_gather                ; eax = the centres
    mov     ecx, eax
    mov     eax, [spawn_rr_n]           ; the centre to start with rotates: none is always first
    inc     dword [spawn_rr_n]
    xor     edx, edx
    div     ecx
    mov     r12d, edx
    mov     r13d, [sc_n]
.attempt:
    lea     rax, [sc_cnt]
    cmp     dword [rax + r12*4], HOSTILE_CAP
    jae     .next_centre                ; this player has his share
    cmp     dword [sc_n], 1
    je      .go                         ; one centre: every hostile mob is counted above, no total limit
    cmp     dword [sc_total], HOSTILE_CAP_ALL
    jae     .next_centre
.go:
    lea     rax, [sc_body]
    mov     rax, [rax + r12*8]
    mov     [spawn_ctr], rax
    lea     rax, [sc_level]
    mov     eax, [rax + r12*4]
    mov     [mob_spawn_level], eax
    call    rng_next                    ; which kind: night_kinds[rng % 4]
    and     eax, 3
    movzx   edi, byte [night_kinds + rax]
    mov     esi, 24
    mov     edx, 17
    mov     ecx, GROUND_HOSTILE
    call    spawn_near_player
    test    eax, eax
    js      .next_centre                ; no spot found: nothing spawned
    mov     ebx, eax
    cmp     dword [sc_n], 1
    je      .elite
    inc     dword [sc_total]            ; it counts for the total and for every centre within its reach
    imul    edi, ebx, MOB_size
    lea     rax, [mobs]
    add     rdi, rax
    call    spawn_tally
.elite:
    call    rng_next                    ; 4 % of the night's mobs are elite
    xor     edx, edx
    mov     ecx, 100
    div     ecx
    cmp     edx, NATURAL_ELITE_PCT
    jae     .next_centre
    imul    edx, ebx, MOB_size
    lea     rax, [mobs]
    add     rdx, rax
    call    make_elite
.next_centre:
    inc     r12d
    cmp     r12d, [sc_n]
    jb      .served
    xor     r12d, r12d
.served:
    dec     r13d
    jnz     .attempt
    mov     qword [spawn_ctr], 0
    mov     dword [mob_spawn_level], 0
.passive:
    mov     eax, [game_time]
    xor     edx, edx
    mov     ecx, 1800
    div     ecx
    test    edx, edx
    jnz     .done
    mov     edi, [game_time]
    call    sky_is_night
    test    eax, eax
    jnz     .done
    cmp     byte [net_role], NET_ROLE_OFF
    je      .animals
    call    nm_ready_count
    inc     eax                         ; the centres: the local player and the remote ones
    mov     ecx, eax
    mov     eax, [spawn_rr]
    inc     dword [spawn_rr]
    xor     edx, edx
    div     ecx
    mov     r12d, edx                   ; this tick's centre: 0 the local player, k the (k - 1)th remote one
    test    r12d, r12d
    jz      .animals
    lea     edi, [r12 - 1]
    call    nm_centre
    test    rax, rax
    jz      .animals                    ; (a remote player who is gone or dead: the local one)
    mov     [spawn_ctr], rax
    mov     [mob_spawn_level], edx
.animals:
    mov     edi, MOB_PIG
    mov     esi, PIG_CAP
    call    spawn_passive
    mov     edi, MOB_CHICKEN
    mov     esi, CHICKEN_CAP
    call    spawn_passive
    mov     qword [spawn_ctr], 0
    mov     dword [mob_spawn_level], 0
.done:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mob_forget_far(rdi mob): the mob stands in a column that is not ready. When that column lies more
; than R + 2 columns from the player's (Chebyshev, absolute chunk coordinates; R = stream_rdist(): the render
; distance clamped to 2..MAX_RENDER_DIST, and capped while hosting, so R + 2 is the radius beyond which the
; stream unloads) and, on a host, more than MP_SIM_R + 2 from the column of every remote player
; (net_stream_centres: the areas the stream keeps around them) nothing will ever load it: the mob is removed
; (MOB_NONE).
; rbx = the mob; frame: [rsp] its column's chunk x, [rsp+4] z, [rsp+8] its Chebyshev distance to the
; player's column, [rsp+16] the remote players' columns (7 x, z pairs)
mob_forget_far:
    push    rbx
    sub     rsp, 80
    mov     rbx, rdi
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [player + BODY.x]
    roundss xmm0, xmm0, 9
    roundss xmm1, xmm1, 9
    cvttss2si eax, xmm0
    cvttss2si ecx, xmm1
    add     eax, [world_origin_x]
    add     ecx, [world_origin_x]
    sar     eax, 4
    sar     ecx, 4
    mov     [rsp], eax
    sub     eax, ecx
    mov     ecx, eax
    sar     ecx, 31
    xor     eax, ecx
    sub     eax, ecx                    ; |columns apart on x|
    movss   xmm0, [rbx + BODY.z]
    movss   xmm1, [player + BODY.z]
    roundss xmm0, xmm0, 9
    roundss xmm1, xmm1, 9
    cvttss2si edx, xmm0
    cvttss2si ecx, xmm1
    add     edx, [world_origin_z]
    add     ecx, [world_origin_z]
    sar     edx, 4
    sar     ecx, 4
    mov     [rsp + 4], edx
    sub     edx, ecx
    mov     ecx, edx
    sar     ecx, 31
    xor     edx, ecx
    sub     edx, ecx                    ; |columns apart on z|
    cmp     eax, edx
    cmovb   eax, edx                    ; the larger one (unsigned: a wild coordinate counts as far)
    mov     [rsp + 8], eax
    call    stream_rdist
    add     eax, 2                      ; the keep radius K
    cmp     [rsp + 8], eax
    jbe     .keep
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .remove
    lea     rdi, [rsp + 16]
    call    net_stream_centres          ; eax = how many remote players
    xor     ecx, ecx
.centre:
    cmp     ecx, eax
    jae     .remove
    mov     edx, [rsp + 16 + rcx*8]     ; the column of remote player ecx: how far apart on x and z
    sub     edx, [rsp]
    mov     esi, edx
    sar     esi, 31
    xor     edx, esi
    sub     edx, esi
    mov     esi, [rsp + 20 + rcx*8]
    sub     esi, [rsp + 4]
    mov     edi, esi
    sar     edi, 31
    xor     esi, edi
    sub     esi, edi
    cmp     edx, esi
    cmovb   edx, esi
    cmp     edx, MP_SIM_R + 2           ; within the area the stream keeps around him
    jbe     .keep
    inc     ecx
    jmp     .centre
.remove:
    mov     dword [rbx + MOB.type], MOB_NONE
.keep:
    add     rsp, 80
    pop     rbx
    ret

; mobs_step(): one fixed 1/60 s step for every mob, then the spawner. A mob whose column is not
; ready (not generated yet, or not lit) stands frozen: no AI, no physics, no timers. A frozen mob
; more than render_dist + 2 columns from the player's column (on a host, and more than MP_SIM_R + 2 from
; every remote player's) is removed (mob_forget_far): that column will not load, and the mob would count
; against the spawn caps for good.
mobs_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    lea     rbx, [mobs]
    lea     r12, [mobs_end]
.loop:
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .next
    movss   xmm0, [rbx + BODY.x]
    roundss xmm0, xmm0, 9
    cvttss2si edi, xmm0
    movss   xmm0, [rbx + BODY.z]
    roundss xmm0, xmm0, 9
    cvttss2si esi, xmm0
    call    world_column_ready
    test    eax, eax
    jnz     .live
    mov     rdi, rbx
    call    mob_forget_far
    jmp     .next
.live:
    mov     rdi, rbx
    call    mob_update
.next:
    add     rbx, MOB_size
    cmp     rbx, r12
    jb      .loop
    call    mobs_spawn_tick
    call    folk_travel_tick            ; the travelling trader
    call    events_step                 ; the faction events' state machine (events.asm)
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mobs_populate(): scatter pigs, then chickens, around the player (up to 200 tries each, until
; 10 pigs / 6 chickens live)
mobs_populate:
    push    rbp
    mov     rbp, rsp
    mov     edi, MOB_PIG
    mov     esi, PIG_CAP
    call    populate
    mov     edi, MOB_CHICKEN
    mov     esi, CHICKEN_START
    call    populate
    pop     rbp
    ret

; populate(edi type, esi count): up to 200 tries at spawning that type on grass in the 97 x 97
; square around the player (floor of his x and z, +-48), until `count` of them live
populate:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r13d, edi
    mov     r14d, esi
    mov     ebx, 200
.try:
    mov     edi, r13d
    call    mob_count_type
    cmp     eax, r14d
    jae     .done
    call    rng_next                    ; x = player x + rng % 97 - 48
    xor     edx, edx
    mov     ecx, 97
    div     ecx
    movss   xmm0, [player + BODY.x]
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    lea     r12d, [rax + rdx - 48]
    call    rng_next
    xor     edx, edx
    mov     ecx, 97
    div     ecx
    movss   xmm0, [player + BODY.z]
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    lea     edx, [rax + rdx - 48]       ; z
    mov     edi, r13d
    mov     esi, r12d
    mov     ecx, GROUND_PASSIVE
    call    spawn_at_ground
    dec     ebx
    jnz     .try
.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ray_aabb(rdi origin[3], rsi dir[3], rdx lo[3], rcx hi[3], xmm0 tmax) -> eax 1 hit / 0 miss,
; xmm0 = entry distance t (0 when the origin is inside), 0 <= t <= tmax. Slab test.
ray_aabb:
    xorps   xmm1, xmm1                  ; tmin
    xorps   xmm6, xmm6
    xor     r8d, r8d                    ; byte offset of the axis
.axis:
    movss   xmm2, [rdi + r8]            ; o
    movss   xmm3, [rsi + r8]            ; d
    movss   xmm4, [rdx + r8]            ; lo
    movss   xmm5, [rcx + r8]            ; hi
    ucomiss xmm3, xmm6
    jp      .parallel
    jne     .slab
.parallel:                              ; no movement on this axis: the origin must be inside the slab
    ucomiss xmm2, xmm4
    jb      .miss
    ucomiss xmm2, xmm5
    ja      .miss
    jmp     .next
.slab:
    subss   xmm4, xmm2
    subss   xmm5, xmm2
    divss   xmm4, xmm3                  ; t at lo
    divss   xmm5, xmm3                  ; t at hi
    movaps  xmm7, xmm4
    minss   xmm7, xmm5                  ; entering the slab
    maxss   xmm4, xmm5                  ; leaving the slab
    maxss   xmm1, xmm7
    minss   xmm0, xmm4
.next:
    add     r8d, 4
    cmp     r8d, 12
    jb      .axis
    ucomiss xmm1, xmm0
    ja      .miss                       ; entry after exit or beyond tmax
    movaps  xmm0, xmm1
    mov     eax, 1
    ret
.miss:
    xor     eax, eax
    ret

; mobs_raycast(rdi origin[3], rsi dir[3], xmm0 max) -> eax index of the nearest mob hit within
; max (or -1), xmm0 = its distance t (max on a miss). Boxes: [x +- half_w] x [y, y + height] x [z +- half_w].
; Frame: lo[3] @0, hi[3] @16, best t @32.
mobs_raycast:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 56
    mov     r12, rdi
    mov     r13, rsi
    movss   [rsp + 32], xmm0
    mov     r15d, -1
    lea     rbx, [mobs]
    xor     r14d, r14d
.mob:
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .next
    movss   xmm3, [rbx + BODY.half_w]
    movss   xmm0, [rbx + BODY.x]
    movaps  xmm1, xmm0
    subss   xmm0, xmm3
    addss   xmm1, xmm3
    movss   [rsp], xmm0
    movss   [rsp + 16], xmm1
    movss   xmm0, [rbx + BODY.y]
    movss   [rsp + 4], xmm0
    addss   xmm0, [rbx + BODY.height]
    movss   [rsp + 20], xmm0
    movss   xmm0, [rbx + BODY.z]
    movaps  xmm1, xmm0
    subss   xmm0, xmm3
    addss   xmm1, xmm3
    movss   [rsp + 8], xmm0
    movss   [rsp + 24], xmm1
    mov     rdi, r12
    mov     rsi, r13
    lea     rdx, [rsp]
    lea     rcx, [rsp + 16]
    movss   xmm0, [rsp + 32]            ; only a hit nearer than the best so far counts
    call    ray_aabb
    test    eax, eax
    jz      .next
    movss   [rsp + 32], xmm0
    mov     r15d, r14d
.next:
    add     rbx, MOB_size
    inc     r14d
    cmp     r14d, MAX_MOBS
    jb      .mob
    movss   xmm0, [rsp + 32]
    mov     eax, r15d
    add     rsp, 56
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mob_drop(rdi mob, esi item, edx count): `count` of `item` pop out of the mob at mid-body height
; (a pig's a little lower)
mob_drop:
    movss   xmm0, [rdi + BODY.x]
    movss   xmm1, [rdi + BODY.height]
    mulss   xmm1, [c_half]
    cmp     dword [rdi + MOB.type], MOB_PIG
    jne     .height
    movss   xmm1, [c_drop_dy]
.height:
    addss   xmm1, [rdi + BODY.y]
    movss   xmm2, [rdi + BODY.z]
    mov     eax, esi
    mov     esi, edx
    mov     edi, eax
    xor     edx, edx
    jmp     drops_spawn

; mob_coins(rdi mob, edx count): `count` gold coins x (100 + GOLD_FIND) / 100 (whole coins, at
; most 255) pop out of the mob; none when that comes to 0
mob_coins:
    lea     rcx, [rpg_stats]
    xor     r8d, r8d
    mov     eax, [rcx + STAT_GOLD_FIND*4]
    add     eax, 100
    cmovs   eax, r8d                    ; never a negative multiplier
    imul    eax, edx
    xor     edx, edx
    mov     ecx, 100
    div     ecx
    mov     edx, eax
    mov     ecx, 255
    cmp     edx, ecx
    cmova   edx, ecx
    test    edx, edx
    jz      .ret
    mov     esi, GOLD_COIN
    jmp     mob_drop
.ret:
    ret

; mob_drops(rdi mob): the loot of a dead mob, popped out at mid-body height. Each of the type's two
; table entries (item, base, range) drops base + rng % range. A hostile mob also rolls its gear
; (gear_drop_from_mob) and drops gold coins (mob_coins): every other time 1 + level / 10; an elite
; 3 + rng % 3 + level / 5 and a health potion with 30 % chance; the Fallen King 30 + level coins
; and 4 diamonds. Last of all, a hostile mob drops a random Rune item with 2 % chance and the Fallen
; King always drops one. A folk's loot is its own (folk_drops): it rolls none of this.
mob_drops:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rdi
    mov     eax, [rbx + MOB.type]
    cmp     eax, MOB_FOLK
    je      .folk
    lea     r12, [t_drops + rax*8 - 8]
    mov     r13d, 2
.entry:
    cmp     byte [r12], 0
    je      .next
    call    rng_next
    movzx   ecx, byte [r12 + 2]
    xor     edx, edx
    div     ecx
    movzx   eax, byte [r12 + 1]
    add     edx, eax                    ; count
    jz      .next                       ; nothing this time
    movzx   esi, byte [r12]
    mov     rdi, rbx
    call    mob_drop
.next:
    add     r12, 3
    dec     r13d
    jnz     .entry
    mov     eax, [rbx + MOB.type]
    cmp     byte [t_hostile + rax - 1], 0
    je      .done                       ; passive mobs and folk carry nothing else
    mov     rdi, rbx
    call    gear_drop_from_mob          ; rolled gear, the Fallen King's legendary included
    cmp     dword [rbx + MOB.type], MOB_BOSS
    je      .boss
    cmp     dword [rbx + MOB.elite], 0
    jne     .elite
    call    rng_next                    ; a coin every other time
    test    al, 1
    jnz     .rune
    mov     eax, [rbx + MOB.level]
    xor     edx, edx
    mov     ecx, 10
    div     ecx
    lea     edx, [rax + 1]              ; 1 + level / 10
    mov     rdi, rbx
    call    mob_coins
    jmp     .rune
.elite:
    call    rng_next                    ; 3 + rng % 3 + level / 5 coins
    xor     edx, edx
    mov     ecx, 3
    div     ecx
    lea     r12d, [rdx + 3]
    mov     eax, [rbx + MOB.level]
    xor     edx, edx
    mov     ecx, 5
    div     ecx
    lea     edx, [rax + r12]
    mov     rdi, rbx
    call    mob_coins
    call    rng_next                    ; ...and a health potion with 30 % chance
    xor     edx, edx
    mov     ecx, 100
    div     ecx
    cmp     edx, 30
    jae     .rune
    mov     rdi, rbx
    mov     esi, HEALTH_POTION
    mov     edx, 1
    call    mob_drop
    jmp     .rune
.boss:
    mov     edx, [rbx + MOB.level]
    add     edx, 30                     ; 30 + level coins
    mov     rdi, rbx
    call    mob_coins
    mov     rdi, rbx
    mov     esi, DIAMOND
    mov     edx, 4
    call    mob_drop
    jmp     .rune_pick
.rune:                                  ; 2 % of the other hostile mobs
    call    rng_next
    xor     edx, edx
    mov     ecx, 100
    div     ecx
    cmp     edx, 2
    jae     .done
.rune_pick:
    call    rng_next
    xor     edx, edx
    mov     ecx, NUM_RUNES
    div     ecx
    mov     rdi, rbx
    lea     esi, [rdx + RUNE_FIRST]
    mov     edx, 1
    call    mob_drop
.done:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
.folk:                                  ; folk drop their own loot: no table, no hostile gear
    mov     rdi, rbx
    call    folk_drops
    jmp     .done

; boss_death(rdi mob): the Fallen King falls (his loot comes from mob_drops): the crypt he was born
; in (MOB.origin) is recorded as cleared (structures_on_boss_killed); 500 XP + 25 per level of his and the
; victory banner are every player's (structures_boss_reward; a host sends them as EV_BOSS_KILLED, which
; applies to itself too); the quest chain moves on and a blast shakes his heart
boss_death:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdi
    mov     edi, [rbx + MOB.origin]
    test    edi, edi
    jz      .xp                         ; not born at a site
    call    structures_on_boss_killed
.xp:
    mov     edi, [rbx + MOB.level]
    cmp     byte [net_role], NET_ROLE_HOST
    je      .event
    call    structures_boss_reward
    jmp     .quest
.event:
    mov     esi, edi
    mov     edi, EV_BOSS_KILLED
    call    net_event_out
.quest:
    call    quests_on_boss_killed
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.height]
    mulss   xmm1, [c_half]
    addss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [c_boss_death_r]
    call    fx_explosion
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; mob_hurt(edi idx, esi dmg, xmm0 dirx, xmm1 dirz) -> eax 1 applied / 0 (no such mob, or
; still in its hurt window). Knocks the mob along (dirx, dirz) -- not a JUGGERNAUT elite, which
; stands firm; a passive mob panics and flees that way, a dead mob drops its loot (mob_drops).
; mob_strike(...): the same, but it lands even inside the hurt window, so rapid fire, shotgun
; pellets, spells and melee strikes all count.
; Both consume combat_hit_flags (cleared on return): HF_PLAYER tags the mob, so a kill within 200
; steps pays XP; HF_CRIT and the element bits (HF_ELEM_*) shape the floating damage number. HF_DOT
; (a tick of burn, bleed or poison) only tags the mob, raises its bar, shows the number and settles
; a kill: no hurt window, shove, lift, sound or panic. A kill reports to the RPG
; (rpg_on_mob_killed when tagged, with the mob's level), to the site the mob was born at
; (structures_on_mob_killed, MOB.origin = site state index + 1) and, for the Fallen King, to boss_death.
; The Fallen King barely budges
; when hit and roars when he drops to a third of his health.
; A folk answers a player's blow (HF_PLAYER, no HF_DOT) with folk_on_player_hit instead of bolting like
; an animal, and its death with folk_on_death before its loot; burning that another folk's weapon set
; (FF_FOLKDOT) does not tag it as the player's.
; Frame: [rsp] dirx, [rsp+4] dirz, [rsp+8] health before the hit.
mob_strike:
    mov     r8d, 1
    jmp     mob_damage
mob_hurt:
    xor     r8d, r8d
mob_damage:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    cmp     edi, MAX_MOBS
    jae     .no
    imul    ebx, edi, MOB_size
    lea     rax, [mobs]
    add     rbx, rax
    mov     eax, [rbx + MOB.type]
    test    eax, eax
    jz      .no
    test    byte [combat_hit_flags], HF_PLAYER
    jz      .unguarded
    cmp     eax, MOB_FOLK
    jne     .unguarded
    mov     ecx, [rbx + MOB.patrol]
    test    ecx, ecx
    jz      .unguarded
    test    ecx, EV_KEY_ATTACK | 1
    jz      .no                         ; an event's defender (key with the low bits clear): the player's blow neither hurts nor provokes it
.unguarded:
    test    r8d, r8d
    jnz     .apply
    cmp     dword [rbx + MOB.hurt], 0
    jg      .no
.apply:
    mov     r12d, esi                   ; damage
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    cmp     byte [net_role], NET_ROLE_GUEST
    je      .guest                      ; a guest only asks: the host applies the blow
    mov     eax, [rbx + MOB.health]
    mov     [rsp + 8], eax
    sub     [rbx + MOB.health], esi
    mov     dword [rbx + MOB.bar], BAR_STEPS
    test    byte [combat_hit_flags], HF_PLAYER
    jz      .tag_done
    test    byte [combat_hit_flags], HF_DOT
    jz      .tag
    test    byte [rbx + MOB.fflags], FF_FOLKDOT
    jnz     .tag_done                   ; the tick of a burn another folk set is no blow of the player's
.tag:
    mov     dword [rbx + MOB.tagged], TAG_STEPS
    cmp     byte [net_role], NET_ROLE_OFF
    je      .tag_done
    test    byte [combat_hit_flags], HF_DOT
    jnz     .tag_done                   ; a tick of damage over time keeps the credit of whoever hit it last
    mov     eax, [net_hit_peer]         ; the peer whose blow this is (0: the host's own)
    mov     [rbx + MOB.peer], eax
.tag_done:
    test    byte [combat_hit_flags], HF_DOT
    jnz     .number                     ; a tick of damage over time is no blow
    mov     dword [rbx + MOB.hurt], HURT_STEPS
    movss   xmm2, [c_kb]
    cmp     dword [rbx + MOB.type], MOB_BOSS
    jne     .shove
    mulss   xmm2, [c_boss_kb]           ; the Fallen King barely budges...
.shove:
    test    byte [rbx + MOB.affix], AFX_JUGGERNAUT
    jnz     .sound                      ; ...and a juggernaut not at all, nor is it thrown up
    movss   xmm0, [rsp]
    mulss   xmm0, xmm2
    movss   [rbx + BODY.kbx], xmm0
    movss   xmm1, [rsp + 4]
    mulss   xmm1, xmm2
    movss   [rbx + BODY.kbz], xmm1
    cmp     dword [rbx + MOB.type], MOB_BOSS
    je      .sound                      ; ...and is never thrown into the air
    cmp     dword [rbx + BODY.on_ground], 0
    je      .sound
    mov     dword [rbx + BODY.vy], __float32__(4.0)
.sound:
    cmp     byte [net_applying], 0
    jne     .number                     ; a guest's blow being applied (HIT): it made this sound itself and sent it on (SOUND)
    mov     eax, [rbx + MOB.type]
    movzx   edi, byte [t_hurt + rax - 1]
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [c_vol_hurt]
    call    audio_play_at
.number:
    movss   xmm0, [rbx + BODY.x]        ; the damage number floats up from above the head; over
    movss   xmm1, [rbx + BODY.height]   ; the Fallen King it starts at 2 blocks, in view up close
    minss   xmm1, [c_two]
    addss   xmm1, [rbx + BODY.y]
    addss   xmm1, [c_over_head]
    movss   xmm2, [rbx + BODY.z]
    mov     edi, r12d
    movzx   esi, byte [combat_hit_flags]
    and     esi, HF_CRIT | HF_DOT | HF_ELEM_MASK
    call    dmgnum_spawn
    test    byte [combat_hit_flags], HF_DOT
    jnz     .check_dead                 ; a burning animal does not bolt either
    mov     eax, [rbx + MOB.type]
    cmp     eax, MOB_FOLK
    je      .folk_hit
    cmp     byte [t_hostile + rax - 1], 0
    jne     .check_dead                 ; hostile mobs stand and fight
    mov     dword [rbx + MOB.panic], PANIC_STEPS
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    call    yaw_from                    ; passive mobs run away from the attacker
    movss   [rbx + BODY.yaw], xmm0
    jmp     .check_dead
.folk_hit:                              ; folk answer a player's blow: provoked, woken or scared
    test    byte [combat_hit_flags], HF_PLAYER
    jz      .check_dead
    mov     rdi, rbx
    call    folk_on_player_hit
.check_dead:
    cmp     dword [rbx + MOB.health], 0
    jg      .alive
    cmp     dword [rbx + MOB.tagged], 0
    jle     .origin
    cmp     byte [net_role], NET_ROLE_OFF
    je      .xp_here
    movzx   eax, byte [net_self]
    cmp     [rbx + MOB.peer], eax
    je      .xp_here
    mov     rdi, rbx                    ; another peer had a hand in it: the XP is his (a KILL message, with this mob's slot)
    call    mob_index
    mov     r8d, eax
    mov     edi, [rbx + MOB.peer]
    mov     esi, [rbx + MOB.type]
    mov     edx, [rbx + MOB.elite]
    mov     ecx, [rbx + MOB.level]
    call    net_kill_credit
    jmp     .origin
.xp_here:
    mov     edi, [rbx + MOB.type]       ; the player had a hand in it: XP
    mov     esi, [rbx + MOB.elite]
    mov     edx, [rbx + MOB.level]
    call    rpg_on_mob_killed
.origin:
    mov     edi, [rbx + MOB.origin]
    test    edi, edi
    jz      .loot                       ; not born at a site
    call    structures_on_mob_killed
.loot:
    mov     eax, [rbx + MOB.type]
    cmp     eax, MOB_FOLK
    je      .folk_dead
    cmp     eax, MOB_BOSS
    jne     .drops
    mov     rdi, rbx
    call    boss_death
.drops:
    mov     rdi, rbx
    call    mob_drops
    mov     dword [rbx + MOB.type], MOB_NONE
    jmp     .yes
.folk_dead:                             ; its faction pays for it when the player did it
    mov     rdi, rbx
    call    folk_on_death
    jmp     .drops
.alive:
    cmp     dword [rbx + MOB.type], MOB_BOSS
    jne     .yes
    imul    ecx, [rbx + MOB.max_health], 33
    mov     eax, [rbx + MOB.health]
    imul    eax, eax, 100
    cmp     eax, ecx
    jg      .yes                        ; still above a third of his health
    mov     eax, [rsp + 8]
    imul    eax, eax, 100
    cmp     eax, ecx
    jle     .yes                        ; was already enraged
    mov     edi, SND_BOSS_ROAR          ; this hit drove him into phase 3
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [c_vol_hurt]
    call    audio_play_at
    lea     rdi, [s_furious]
    mov     esi, RGBA(255, 80, 60, 255)
    call    hud_banner
.yes:
    mov     eax, 1
    jmp     .ret
.guest:                                 ; the host owns the mob: it gets the blow (HIT), the guest feels it at once
    mov     [rsp + 12], r8d             ; strike (1) or hurt (0)
    test    byte [combat_hit_flags], HF_DOT
    jnz     .ask                        ; a tick of damage over time makes no sound
    mov     eax, [rbx + MOB.type]
    movzx   edi, byte [t_hurt + rax - 1]
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [c_vol_hurt]
    call    audio_play_at
.ask:
    mov     rdi, rbx
    call    mob_index
    mov     edi, eax
    mov     esi, r12d
    mov     edx, [rsp + 12]
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    call    net_mob_damage_out          ; the HIT message, the number over the mob; spends combat_hit_flags
    jmp     .yes
.no:
    xor     eax, eax
.ret:
    mov     byte [combat_hit_flags], 0
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mobs_intersect_block(edi x, esi y, edx z, ecx id) -> eax 1 if any live mob's box strictly overlaps
; the collision boxes block `id` would have in that cell
mobs_intersect_block:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r13d, edi
    mov     r14d, esi
    mov     r15d, edx
    mov     [rsp], ecx
    lea     rbx, [mobs]
    lea     r12, [mobs_end]
.loop:
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .next
    mov     rdi, rbx
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, r15d
    mov     r8d, [rsp]
    call    body_intersects_block
    test    eax, eax
    jnz     .ret
.next:
    add     rbx, MOB_size
    cmp     rbx, r12
    jb      .loop
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mobs_save(rdi WORLDHDR*): the live mobs as compact MOBSAVE records, mob_count set. A record's
; type carries MOB_ELITE_BIT for an elite, the level at MS_LEVEL_SHIFT and the affixes at
; MS_AFFIX_SHIFT; folk and the boss are skipped (the sites re-create them).
mobs_save:
    mov     r8, rdi
    lea     rdi, [r8 + WORLDHDR.mobs]
    mov     ecx, MAX_MOBS * MOBSAVE_size
    xor     eax, eax
    rep     stosb                       ; unused records read back as zero
    lea     rdi, [r8 + WORLDHDR.mobs]
    lea     rsi, [mobs]
    lea     rdx, [mobs_end]
    xor     ecx, ecx                    ; records written
.loop:
    mov     eax, [rsi + MOB.type]
    test    eax, eax
    jz      .next
    cmp     eax, MOB_BOSS
    jae     .next                       ; folk and the boss are re-created from the sites
    cmp     dword [rsi + MOB.elite], 0
    je      .plain
    or      eax, MOB_ELITE_BIT
.plain:
    movzx   r9d, byte [rsi + MOB.level]
    shl     r9d, MS_LEVEL_SHIFT
    or      eax, r9d
    movzx   r9d, byte [rsi + MOB.affix]
    shl     r9d, MS_AFFIX_SHIFT
    or      eax, r9d
    mov     [rdi + MOBSAVE.type], eax
    mov     eax, [rsi + MOB.health]
    mov     [rdi + MOBSAVE.health], eax
    mov     eax, [rsi + BODY.x]
    mov     [rdi + MOBSAVE.x], eax
    mov     eax, [rsi + BODY.y]
    mov     [rdi + MOBSAVE.y], eax
    mov     eax, [rsi + BODY.z]
    mov     [rdi + MOBSAVE.z], eax
    add     rdi, MOBSAVE_size
    inc     ecx
.next:
    add     rsi, MOB_size
    cmp     rsi, rdx
    jb      .loop
    mov     [r8 + WORLDHDR.mob_count], ecx
    ret

; IN_RANGE mem, bound: jump to .skip unless 0 <= float at mem < constant bound (NaN skips)
%macro IN_RANGE 2
    movss   xmm0, %1
    xorps   xmm3, xmm3
    ucomiss xmm0, xmm3
    jb      .skip
    ucomiss xmm0, [%2]
    jae     .skip
%endmacro

; IN_ABS mem, bound: jump to .skip unless |float at mem| < constant bound (NaN and infinities skip)
%macro IN_ABS 2
    movss   xmm0, %1
    movss   xmm1, [k_abs]
    andps   xmm0, xmm1
    movss   xmm1, [%2]
    ucomiss xmm1, xmm0
    jbe     .skip
%endmacro

; mobs_load(rdi WORLDHDR*): clear, then respawn every saved record that describes a known mob
; type (low byte 1..6, bit 8 = elite, bits 16..23 = level, bits 24..31 = affixes) at a finite
; position within 65536 blocks of the origin in x and z and 0 <= y < 256. A level of 0 (an older save)
; leaves the player's level mob_spawn gave; an elite takes
; its saved affixes (an elite saved before 0.8 has none: it rolls them, make_elite); the saved
; health clamps to 1..the maximum of that level, elite state and affixes.
mobs_load:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    call    mobs_clear
    mov     r12d, [rbx + WORLDHDR.mob_count]
    cmp     r12d, MAX_MOBS
    jbe     .count_ok
    mov     r12d, MAX_MOBS              ; garbage count: validate every record we can reach
.count_ok:
    lea     r13, [rbx + WORLDHDR.mobs]
.rec:
    test    r12d, r12d
    jz      .done
    dec     r12d
    movzx   eax, byte [r13 + MOBSAVE.type]
    dec     eax
    cmp     eax, 5
    ja      .skip                       ; not a saved mob type (1..6)
    IN_ABS  [r13 + MOBSAVE.x], c_load_xz
    IN_RANGE [r13 + MOBSAVE.y], c_load_y
    IN_ABS  [r13 + MOBSAVE.z], c_load_xz
    movzx   edi, byte [r13 + MOBSAVE.type]  ; the low byte is the type, bit 8 marks an elite
    movss   xmm0, [r13 + MOBSAVE.x]
    movss   xmm1, [r13 + MOBSAVE.y]
    movss   xmm2, [r13 + MOBSAVE.z]
    call    mob_spawn
    test    eax, eax
    js      .done
    imul    eax, eax, MOB_size
    lea     r14, [mobs]
    add     r14, rax                    ; the new mob
    mov     eax, [r13 + MOBSAVE.type]
    mov     ecx, eax
    shr     ecx, MS_LEVEL_SHIFT
    and     ecx, 0xFF                   ; the saved level
    jz      .level_kept                 ; 0: an older save, the level mob_spawn gave it stands
    mov     [r14 + MOB.level], ecx
.level_kept:
    test    eax, MOB_ELITE_BIT
    jz      .plain
    mov     dword [r14 + MOB.elite], 1
    shr     eax, MS_AFFIX_SHIFT
    mov     [r14 + MOB.affix], eax
    test    eax, eax
    jnz     .affixed
    mov     rdx, r14                    ; a pre-0.8 elite: roll its affixes now
    call    make_elite
    jmp     .plain
.affixed:
    mov     rdi, r14
    call    elite_speed
.plain:
    mov     rdi, r14
    call    mob_scale                   ; the maximum of its level, elite state and affixes
    mov     esi, [r14 + MOB.max_health] ; saved health clamps to 1..max
    mov     eax, [r13 + MOBSAVE.health]
    mov     ecx, 1
    cmp     eax, ecx
    cmovl   eax, ecx
    cmp     eax, esi
    cmovg   eax, esi
    mov     [r14 + MOB.health], eax
.skip:
    add     r13, MOBSAVE_size
    jmp     .rec
.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mobs_shift(edi dx, esi dz): the origin moved by (dx, dz) blocks: every mob's local x and z, and
; its home, drop by that much (exact: dx and dz are multiples of 512); so does the dest of a patrol
mobs_shift:
    cvtsi2ss xmm0, edi
    cvtsi2ss xmm1, esi
    lea     rax, [mobs]
    lea     rcx, [mobs_end]
.l:
    cmp     dword [rax + MOB.type], MOB_NONE
    je      .next
    movss   xmm2, [rax + BODY.x]
    subss   xmm2, xmm0
    movss   [rax + BODY.x], xmm2
    movss   xmm2, [rax + BODY.z]
    subss   xmm2, xmm1
    movss   [rax + BODY.z], xmm2
    movss   xmm2, [rax + MOB.home_x]
    subss   xmm2, xmm0
    movss   [rax + MOB.home_x], xmm2
    movss   xmm2, [rax + MOB.home_z]
    subss   xmm2, xmm1
    movss   [rax + MOB.home_z], xmm2
    cmp     dword [rax + MOB.patrol], 0
    je      .next
    movss   xmm2, [rax + MOB.dest_x]
    subss   xmm2, xmm0
    movss   [rax + MOB.dest_x], xmm2
    movss   xmm2, [rax + MOB.dest_z]
    subss   xmm2, xmm1
    movss   [rax + MOB.dest_z], xmm2
.next:
    add     rax, MOB_size
    cmp     rax, rcx
    jb      .l
    ret

; mobs_remove_box(edi x0, esi z0, edx x1, ecx z1): every mob whose cell (the floor of its x and z)
; lies in the inclusive local box x0..x1, z0..z1 is removed
mobs_remove_box:
    lea     r8, [mobs]
    lea     r9, [mobs_end]
.l:
    cmp     dword [r8 + MOB.type], MOB_NONE
    je      .next
    movss   xmm0, [r8 + BODY.x]
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    cmp     eax, edi
    jl      .next
    cmp     eax, edx
    jg      .next
    movss   xmm0, [r8 + BODY.z]
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    cmp     eax, esi
    jl      .next
    cmp     eax, ecx
    jg      .next
    mov     dword [r8 + MOB.type], MOB_NONE
.next:
    add     r8, MOB_size
    cmp     r8, r9
    jb      .l
    ret
