; events.asm - 0.12 events: a faction camp's defence waves and merchant caravans' escorts. The host (or the offline game)
; runs ONE event at a time (events_step, once per simulation step from mobs_step); every client only keeps the EVHUD
; (ev_hud) the host sends (MT_EVENT_STATE) for its HUD, and answers the events (EV_EVENT_*) with a banner, a sound and XP.
; Kinds: EVK_CAMP (a temporary tent camp), EVK_SITE (an existing camp or village under threat), EVK_CARAVAN (a free
; caravan), EVK_ROAD (a road caravan from a camp's trader). The defenders carry MOB.patrol = key, the attackers
; key | EV_KEY_ATTACK (the folk and mobs hooks read those). Positions are LOCAL floats (events_shift follows the origin);
; the rings and the HUD hold absolute cells. Nothing is saved.
%include "common.inc"
default rel

global events_reset, events_step, events_shift, events_accept, events_offer_kind, events_on_ev
global events_net_apply, events_state_send, events_spawn_camp, events_spawn_caravan
global events_force_threat, events_skip, events_finish, events_status, ev_wave_size
global ev_hud, ev_kind_waves, ev_kind_rep, ev_loot, ev_gear

extern mobs, player, game_time, game_mode, settings, rpg_state, world_origin_x, world_origin_z
extern net_role, nm_ready_count, nm_centre, net_event_out, net_out, net_send_to
extern folk_spawn, folk_init, spawn_at_ground, mob_set_level, make_elite, folk_strike_mob, mob_coins
extern faction_standing, faction_add, faction_names, faction_rivals
extern sky_is_night, rng_next, sincos_deg, hash32
extern hud_banner, audio_play, rpg_add_xp, drops_spawn, gear_roll, gear_tier_for_level, item_gear
extern str_append, i32_to_str
extern evs_ground, evs_find_camp_site, evs_build_tent, evs_remove_tent, evs_forget_tent, evs_tent_placed
extern evs_find_route, evs_road_from, evs_site_of, evs_hop_cell

%define EV_OFFER_STEPS    18000         ; an offered camp or caravan stays this long
%define EV_COUNT_STEPS    600           ; the countdown after an accept
%define EV_BREAK_STEPS    1200          ; between two waves
%define EV_WINDOW         300           ; steps a wave or ambush has to spawn its attackers
%define EV_WAVE_LIMIT     7200          ; steps after the spawn window before far attackers are removed
%define EV_ABANDON_STEPS  3600          ; steps without a player within 96 blocks of the anchor
%define EV_CLEAN_STEPS    18000         ; the longest CLEANUP
%define EV_CYCLE          36000         ; the spontaneous offers: every 10 minutes
%define EV_MIN_FREE       7             ; mob slots an event needs free to begin
%define EV_SEEN_N         16            ; ev_seen ring entries
%define EV_PROVOKED       600           ; steps a raider keeps the players its targets
%define EV_STUCK          120           ; blocked steps of a merchant before the party hops
%define EV_STRIKE_CD      60            ; steps between two blows of a monster on a defender
%define EV_SLOT_NONE      255
%define ES_CAX            0             ; one ev_seen entry (16 bytes)
%define ES_CAZ            4
%define ES_DAY            8
%define ES_KIND           12            ; 0 = empty
%define ES_DONE           13
%define ES_SIZE           16

section .rodata
align 4
k_half:     dd 0.5
k_one:      dd 1.0
k_0_9:      dd 0.9
k_1_5:      dd 1.5
k_1_8_2:    dd 3.24                     ; 1.8 blocks, squared
k_tiny:     dd 0.001
k_16:       dd 16.0                     ; 4 blocks, squared; the road caravan's offset from the camp
k_24:       dd 24.0
k_30:       dd 30.0
k_6:        dd 6.0
k_24sq:     dd 576.0
k_48sq:     dd 2304.0
k_64sq:     dd 4096.0
k_96sq:     dd 9216.0
k_r_camp2:  dd 144.0                    ; a camp's folk: home within 12 blocks of its centre
k_r_vill2:  dd 289.0                    ; a village's: 17
k_side:     dd 0.0, 1.5, -1.5           ; a caravan party's perpendicular offsets: merchant, guard, guard
k_thresh:   dd 0.35, 0.70, 0.0, 0.25, 0.50, 0.75    ; ambush thresholds: EVK_CARAVAN, then EVK_ROAD
ev_kind_waves: db 0, 3, 4, 2, 3
ev_kind_rep:   db 0, 40, 60, 30, 50
ev_xp_base:    dw 0, 120, 200, 100, 180
ev_xp_lvl:     db 0, 12, 20, 10, 18
ev_coin_base:  db 0, 10, 20, 8, 16
ev_coin_shift: db 0, 1, 0, 1, 0          ; the level's share of the coins: L >> shift
ev_rolls_item: db 0, 2, 3, 2, 3
ev_rolls_gear: db 0, 1, 2, 1, 2
ev_strike_base: db 0, 4, 0, 0, 2, 3      ; by mob type: zombie, pig, creeper, skeleton, spider
role_tab:      db ROLE_CARAVAN, ROLE_GUARD, ROLE_GUARD
class_tab:     db FCLASS_NONE, FCLASS_BRUTE, FCLASS_ARCHER
; the loot of a won event by faction, 4 rows of 8 bytes: weight, item, min, max (the weights add up to 100)
align 2
ev_loot:
    dw 30, APPLE, 3, 6
    dw 25, COOKED_PORKCHOP, 2, 4
    dw 25, IRON_INGOT, 2, 4
    dw 20, HEALTH_POTION, 1, 2
    dw 30, GOLD_INGOT, 1, 3
    dw 30, ARROW, 8, 16
    dw 20, HEALTH_POTION, 1, 2
    dw 20, TNT, 1, 2
    dw 30, MANA_POTION, 2, 3
    dw 25, HEALTH_POTION, 1, 2
    dw 25, GOLD_INGOT, 1, 2
    dw 20, TNT, 1, 2
    dw 30, COOKED_PORKCHOP, 3, 6
    dw 25, ARROW, 8, 16
    dw 25, FEATHER, 4, 8
    dw 20, HEALTH_POTION, 1, 2
    dw 35, IRON_INGOT, 3, 6
    dw 25, GOLD_INGOT, 1, 3
    dw 25, TORCH, 8, 16
    dw 15, DIAMOND, 1, 1
ev_gear:                                 ; two gear items per faction
    dw IRON_SWORD, IRON_HELMET
    dw IRON_DAGGER, BOW
    dw STAFF, AMULET
    dw IRON_HAMMER, IRON_SPEAR
    dw IRON_PICKAXE, IRON_CHESTPLATE

section .rodata.str progbits alloc noexec nowrite align=1
s_none:      db "none", 0
s_unknown:   db "?", 0
s_k_camp:    db "Camp", 0
s_k_site:    db "Site", 0
s_k_van:     db "Caravan", 0
s_k_road:    db "Road", 0
s_st_none:   db "none", 0
s_st_offer:  db "offered", 0
s_st_count:  db "countdown", 0
s_st_wave:   db "wave", 0
s_st_break:  db "break", 0
s_st_travel: db "travel", 0
s_st_ambush: db "ambush", 0
s_st_clean:  db "cleanup", 0
s_a:         db "A ", 0
s_the:       db "The ", 0
s_camp_asks: db " camp asks for help nearby", 0
s_camp_thr:  db " camp is under threat!", 0
s_vil_thr:   db "The village is under threat!", 0
s_van_needs: db " caravan needs an escort", 0
s_defend:    db "Defend the camp! ", 0
s_waves:     db " waves", 0
s_escort:    db "Escort the caravan!", 0
s_wave:      db "Wave ", 0
s_raiders:   db ": raiders!", 0
s_monsters:  db ": monsters!", 0
s_ambush:    db "Ambush!", 0
s_camp_safe: db " camp is safe!", 0
s_vil_safe:  db "The village is safe!", 0
s_van_safe:  db "The caravan has arrived!", 0
s_camp_fell: db " camp has fallen", 0
s_vil_fell:  db "The village elder has fallen", 0
s_van_lost:  db "The caravan was lost", 0
s_abandoned: db "Event abandoned", 0
s_turned:    db "The caravan turned back", 0
s_left_a:    db " (", 0
s_left_b:    db " left)", 0

section .rodata
align 8
ev_kind_names:  dq s_unknown, s_k_camp, s_k_site, s_k_van, s_k_road
ev_state_names: dq s_st_none, s_st_offer, s_st_count, s_st_wave, s_st_break, s_st_travel, s_st_ambush, s_st_clean

section .bss
alignb 16
ev_block:
ev_hud:      resb EVHUD_size            ; what every client's HUD shows
ev_sent:     resb EVHUD_size            ; the last EVHUD the host sent
ev_kind:     resd 1
ev_state:    resd 1
ev_faction:  resd 1                     ; the defended faction
ev_rival:    resd 1                     ; the attackers' faction (raiders)
ev_wave:     resd 1                     ; current wave / ambush, 1-based; 0 before the first
ev_waves:    resd 1
ev_timer:    resd 1                     ; steps: offer expiry, countdown, break
ev_key:      resd 1
ev_serial:   resd 1
ev_protect:  resd 1                     ; slot of the protected NPC
ev_ax:       resd 1                     ; the anchor (local floats): a camp's centre, a caravan's merchant
ev_az:       resd 1
ev_sx:       resd 1                     ; a caravan's route: start, destination, unit direction, length
ev_sz:       resd 1
ev_dx:       resd 1
ev_dz:       resd 1
ev_ux:       resd 1
ev_uz:       resd 1
ev_len:      resd 1
ev_wpx:      resd 1                     ; the point a camp wave comes from
ev_wpz:      resd 1
ev_win_t:    resd 1                     ; steps since the wave began (the spawn window)
ev_size:     resd 1                     ; attackers this wave brings (0 until sized)
ev_spawned:  resd 1
ev_after_t:  resd 1                     ; steps since the spawn window closed
ev_aband:    resd 1                     ; consecutive steps without a player near the anchor
ev_clean_t:  resd 1
ev_level:    resd 1
ev_night:    resd 1                     ; this wave is monsters
ev_wait:     resd 1                     ; the caravan waits for a player
ev_tick:     resd 1
ev_cyc:      resd 1                     ; the last 10-minute cycle that was tried
ev_seen_head: resd 1
ev_fk_valid: resd 1                     ; events_force_threat: this site is threatened today
ev_fk_x:     resd 1
ev_fk_z:     resd 1
ev_fk_day:   resd 1
ev_strike_cd: resd MAX_MOBS
ev_seen:     resb EV_SEEN_N * ES_SIZE
ev_block_end:

; CATS lbl / CATN val / CATC chr / CATFAC val: append to the line whose end is in rbx
%macro CATS 1
    mov     rdi, rbx
    lea     rsi, [%1]
    call    str_append
    mov     rbx, rax
%endmacro
%macro CATN 1
    mov     esi, %1
    mov     rdi, rbx
    call    ev_cat_num
    mov     rbx, rax
%endmacro
%macro CATC 1
    mov     byte [rbx], %1
    inc     rbx
%endmacro
%macro CATFAC 1
    mov     eax, %1
    cmp     eax, NUM_FACTIONS
    jb      %%ok
    xor     eax, eax
%%ok:
    lea     rcx, [faction_names]
    mov     rsi, [rcx + rax * 8]
    mov     rdi, rbx
    call    str_append
    mov     rbx, rax
%endmacro

section .text

; ==== small helpers =============================================================================================

; ev_rnd(edi n) -> eax rng % n (n > 0). Clobbers ecx, edx.
ev_rnd:
    sub     rsp, 8
    call    rng_next
    xor     edx, edx
    div     edi
    mov     eax, edx
    add     rsp, 8
    ret

; ev_mob(edi slot) -> rax the MOB. Leaf: ecx.
ev_mob:
    imul    eax, edi, MOB_size
    lea     rcx, [mobs]
    add     rax, rcx
    ret

; ev_prot() -> rax the protected NPC (a folk still carrying the event's key), or 0. Leaf.
ev_prot:
    mov     edi, [ev_protect]
    cmp     edi, MAX_MOBS
    jae     .none
    imul    eax, edi, MOB_size
    lea     rcx, [mobs]
    add     rax, rcx
    cmp     dword [rax + MOB.type], MOB_FOLK
    jne     .none
    mov     ecx, [ev_key]
    cmp     [rax + MOB.patrol], ecx
    jne     .none
    ret
.none:
    xor     eax, eax
    ret

; ev_body_d2(rdi body, xmm0 x, xmm1 z) -> xmm0 the squared horizontal distance. Leaf: xmm2, xmm3.
ev_body_d2:
    movss   xmm2, [rdi + BODY.x]
    subss   xmm2, xmm0
    mulss   xmm2, xmm2
    movss   xmm3, [rdi + BODY.z]
    subss   xmm3, xmm1
    mulss   xmm3, xmm3
    addss   xmm2, xmm3
    movaps  xmm0, xmm2
    ret

; ev_players_near(xmm0 x, xmm1 z, xmm2 r2) -> eax the players (the local one and every other one who lives) whose squared
; distance to (x, z) is at most r2. Frame: [rsp] x, [rsp+4] z, [rsp+8] r2.
ev_players_near:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 8], xmm2
    xor     ebx, ebx
    lea     rdi, [player]
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    call    ev_body_d2
    comiss  xmm0, [rsp + 8]
    ja      .others
    inc     ebx
.others:
    xor     r12d, r12d
.k:
    mov     edi, r12d
    call    nm_centre
    test    rax, rax
    jz      .done
    mov     rdi, rax
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    call    ev_body_d2
    comiss  xmm0, [rsp + 8]
    ja      .next
    inc     ebx
.next:
    inc     r12d
    jmp     .k
.done:
    mov     eax, ebx
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ev_free_slots() -> eax the empty mob slots. Leaf.
ev_free_slots:
    lea     rcx, [mobs]
    mov     edx, MAX_MOBS
    xor     eax, eax
.l:
    cmp     dword [rcx + MOB.type], MOB_NONE
    jne     .n
    inc     eax
.n:
    add     rcx, MOB_size
    dec     edx
    jnz     .l
    ret

; ev_count_attackers() -> eax the live mobs carrying key | EV_KEY_ATTACK. Leaf.
ev_count_attackers:
    mov     esi, [ev_key]
    or      esi, EV_KEY_ATTACK
    lea     rcx, [mobs]
    mov     edx, MAX_MOBS
    xor     eax, eax
.l:
    cmp     dword [rcx + MOB.type], MOB_NONE
    je      .n
    cmp     [rcx + MOB.patrol], esi
    jne     .n
    inc     eax
.n:
    add     rcx, MOB_size
    dec     edx
    jnz     .l
    ret

; ev_target_pos() -> xmm0 x, xmm1 z: where the attackers head for: the protected NPC, else the anchor. Leaf (ev_prot).
ev_target_pos:
    call    ev_prot
    test    rax, rax
    jz      .anchor
    movss   xmm0, [rax + BODY.x]
    movss   xmm1, [rax + BODY.z]
    ret
.anchor:
    movss   xmm0, [ev_ax]
    movss   xmm1, [ev_az]
    ret

; ev_place(rdi mob, xmm0 x, xmm1 y, xmm2 z): the mob stands there, at rest. Leaf.
ev_place:
    movss   [rdi + BODY.x], xmm0
    movss   [rdi + BODY.y], xmm1
    movss   [rdi + BODY.z], xmm2
    xor     eax, eax
    mov     [rdi + BODY.vx], eax
    mov     [rdi + BODY.vy], eax
    mov     [rdi + BODY.vz], eax
    mov     [rdi + BODY.fall], eax
    ret

; ev_cat_num(rdi end, esi value) -> rax the end after the decimal
ev_cat_num:
    mov     rax, rdi
    mov     edi, esi
    mov     rsi, rax
    jmp     i32_to_str

; ev_ring_find(edi cax, esi caz, edx day, ecx kind) -> rax the ev_seen entry, or 0. Leaf.
ev_ring_find:
    lea     rax, [ev_seen]
    mov     r8d, EV_SEEN_N
.l:
    cmp     byte [rax + ES_KIND], cl
    jne     .n
    cmp     [rax + ES_CAX], edi
    jne     .n
    cmp     [rax + ES_CAZ], esi
    jne     .n
    cmp     [rax + ES_DAY], edx
    jne     .n
    ret
.n:
    add     rax, ES_SIZE
    dec     r8d
    jnz     .l
    xor     eax, eax
    ret

; ev_ring_add(edi cax, esi caz, edx day, ecx kind) -> rax the new entry (the oldest is replaced). Leaf.
ev_ring_add:
    mov     eax, [ev_seen_head]
    lea     r8d, [rax + 1]
    and     r8d, EV_SEEN_N - 1
    mov     [ev_seen_head], r8d
    shl     eax, 4
    lea     r9, [ev_seen]
    add     rax, r9
    mov     [rax + ES_CAX], edi
    mov     [rax + ES_CAZ], esi
    mov     [rax + ES_DAY], edx
    mov     byte [rax + ES_KIND], cl
    mov     byte [rax + ES_DONE], 0
    ret

; ev_mark_done(edi cax, esi caz, edx day, ecx kind): that offer is taken (recorded when it was not yet)
ev_mark_done:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    call    ev_ring_find
    test    rax, rax
    jnz     .set
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, r14d
    call    ev_ring_add
.set:
    mov     byte [rax + ES_DONE], 1
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ev_clear_all_help(): no folk offers an event any more
ev_clear_all_help:
    lea     rcx, [mobs]
    mov     edx, MAX_MOBS
.l:
    cmp     dword [rcx + MOB.type], MOB_FOLK
    jne     .n
    and     byte [rcx + MOB.fflags], ~FF_HELP
.n:
    add     rcx, MOB_size
    dec     edx
    jnz     .l
    ret

; ev_body_level(rdi body) -> eax the level of that player: the local one's, or the other's nm_centre reports
ev_body_level:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     r12, rdi
    xor     ebx, ebx
    lea     rax, [player]
    cmp     r12, rax
    je      .own
.k:
    mov     edi, ebx
    call    nm_centre
    test    rax, rax
    jz      .own
    cmp     rax, r12
    je      .found
    inc     ebx
    jmp     .k
.found:
    mov     eax, edx
    jmp     .ret
.own:
    movzx   eax, byte [rpg_state + RPGSAVE.level]
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ev_pick_faction() -> eax a random faction whose standing is 0 or better, or -1. Frame: [rsp] the list
ev_pick_faction:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    xor     ebx, ebx
    xor     r12d, r12d
.f:
    mov     edi, r12d
    call    faction_standing
    test    eax, eax
    js      .next
    mov     [rsp + rbx], r12b
    inc     ebx
.next:
    inc     r12d
    cmp     r12d, NUM_FACTIONS
    jb      .f
    mov     eax, -1
    test    ebx, ebx
    jz      .ret
    mov     edi, ebx
    call    ev_rnd
    movzx   eax, byte [rsp + rax]
.ret:
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ev_pick_rival(edi f) -> eax a random rival of faction f (a set bit of faction_rivals[f])
ev_pick_rival:
    push    rbx
    sub     rsp, 16
    lea     rax, [faction_rivals]
    movzx   ecx, byte [rax + rdi]
    xor     ebx, ebx
    xor     edx, edx
.b:
    bt      ecx, edx
    jnc     .skip
    mov     [rsp + rbx], dl
    inc     ebx
.skip:
    inc     edx
    cmp     edx, NUM_FACTIONS
    jb      .b
    xor     eax, eax
    test    ebx, ebx
    jz      .ret
    mov     edi, ebx
    call    ev_rnd
    movzx   eax, byte [rsp + rax]
.ret:
    add     rsp, 16
    pop     rbx
    ret

; ev_wave_size(edi n, esi players, edx free_slots) -> eax min(3 + n + players - 1, 8, free - 4), floored at 0
ev_wave_size:
    lea     eax, [rdi + rsi + 2]
    mov     ecx, 8
    cmp     eax, ecx
    cmovg   eax, ecx
    sub     edx, 4
    cmp     eax, edx
    cmovg   eax, edx
    xor     ecx, ecx
    test    eax, eax
    cmovs   eax, ecx
    ret

; ev_idle(): no event
ev_idle:
    xor     eax, eax
    mov     [ev_kind], eax
    mov     [ev_state], eax
    mov     [ev_key], eax
    mov     [ev_timer], eax
    mov     [ev_wave], eax
    mov     [ev_waves], eax
    mov     dword [ev_protect], EV_SLOT_NONE
    ret

; ev_begin(edi kind, esi faction, edx level): a new event's counters cleared, a fresh key, its attackers' faction picked
ev_begin:
    sub     rsp, 8
    mov     [ev_kind], edi
    mov     [ev_faction], esi
    mov     [ev_level], edx
    xor     eax, eax
    mov     [ev_wave], eax
    mov     [ev_win_t], eax
    mov     [ev_size], eax
    mov     [ev_spawned], eax
    mov     [ev_after_t], eax
    mov     [ev_aband], eax
    mov     [ev_clean_t], eax
    mov     [ev_timer], eax
    mov     [ev_night], eax
    mov     [ev_wait], eax
    mov     dword [ev_protect], EV_SLOT_NONE
    lea     rax, [ev_kind_waves]
    movzx   eax, byte [rax + rdi]
    mov     [ev_waves], eax
    inc     dword [ev_serial]
    mov     eax, [ev_serial]
    and     eax, 0x0FFFFFFF
    shl     eax, 2
    or      eax, EV_KEY_BASE
    mov     [ev_key], eax
    mov     edi, esi
    call    ev_pick_rival
    mov     [ev_rival], eax
    add     rsp, 8
    ret

; ev_route_setup(): the unit direction and the length of the route (ev_sx, ev_sz) -> (ev_dx, ev_dz)
ev_route_setup:
    movss   xmm0, [ev_dx]
    subss   xmm0, [ev_sx]
    movss   xmm1, [ev_dz]
    subss   xmm1, [ev_sz]
    movaps  xmm2, xmm0
    mulss   xmm2, xmm2
    movaps  xmm3, xmm1
    mulss   xmm3, xmm3
    addss   xmm2, xmm3
    sqrtss  xmm2, xmm2
    comiss  xmm2, [k_tiny]
    jb      .degenerate
    divss   xmm0, xmm2
    divss   xmm1, xmm2
    movss   [ev_ux], xmm0
    movss   [ev_uz], xmm1
    movss   [ev_len], xmm2
    ret
.degenerate:
    mov     dword [ev_ux], __float32__(1.0)
    mov     dword [ev_uz], 0
    mov     dword [ev_len], __float32__(1.0)
    ret

; ev_tag(edi slot, esi flags): the folk in that slot is a defender of this event: patrol = key, level, fflags |= flags
ev_tag:
    sub     rsp, 8
    imul    eax, edi, MOB_size
    lea     rcx, [mobs]
    add     rax, rcx
    mov     edx, [ev_key]
    mov     [rax + MOB.patrol], edx
    or      [rax + MOB.fflags], sil
    mov     esi, [ev_level]
    call    mob_set_level
    add     rsp, 8
    ret

; ev_send_start(): EV_EVENT_START for the event as it is
ev_send_start:
    sub     rsp, 8
    mov     esi, [ev_faction]
    shl     esi, 8
    or      esi, [ev_kind]
    mov     eax, [ev_waves]
    shl     eax, 16
    or      esi, eax
    mov     edi, EV_EVENT_START
    call    net_event_out
    add     rsp, 8
    ret

; ==== reset, shift, net =========================================================================================

; events_reset(): no event, no records, nothing sent
events_reset:
    lea     rdi, [ev_block]
    mov     ecx, ev_block_end - ev_block
    xor     eax, eax
    rep     stosb
    mov     dword [ev_cyc], -1
    mov     dword [ev_protect], EV_SLOT_NONE
    mov     byte [ev_hud + EVHUD.protect], EV_SLOT_NONE
    mov     byte [ev_sent + EVHUD.protect], EV_SLOT_NONE
    ret

; events_shift(edi dx, esi dz): the origin moved by (dx, dz) blocks: every stored local position drops by that much
events_shift:
    cvtsi2ss xmm0, edi
    cvtsi2ss xmm1, esi
    movss   xmm2, [ev_ax]
    subss   xmm2, xmm0
    movss   [ev_ax], xmm2
    movss   xmm2, [ev_az]
    subss   xmm2, xmm1
    movss   [ev_az], xmm2
    movss   xmm2, [ev_sx]
    subss   xmm2, xmm0
    movss   [ev_sx], xmm2
    movss   xmm2, [ev_sz]
    subss   xmm2, xmm1
    movss   [ev_sz], xmm2
    movss   xmm2, [ev_dx]
    subss   xmm2, xmm0
    movss   [ev_dx], xmm2
    movss   xmm2, [ev_dz]
    subss   xmm2, xmm1
    movss   [ev_dz], xmm2
    movss   xmm2, [ev_wpx]
    subss   xmm2, xmm0
    movss   [ev_wpx], xmm2
    movss   xmm2, [ev_wpz]
    subss   xmm2, xmm1
    movss   [ev_wpz], xmm2
    ret

; events_net_apply(rdi payload, esi len): a guest takes the host's EVHUD (a payload of at least 20 bytes)
events_net_apply:
    cmp     esi, EVHUD_size
    jb      .ret
    mov     rax, [rdi]
    mov     [ev_hud], rax
    mov     rax, [rdi + 8]
    mov     [ev_hud + 8], rax
    mov     eax, [rdi + 16]
    mov     [ev_hud + 16], eax
.ret:
    ret

; events_state_send(edi peer_slot): the host tells that peer the event as it is
events_state_send:
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    sub     rsp, 8
    mov     esi, MT_EVENT_STATE
    lea     rdx, [ev_hud]
    mov     ecx, EVHUD_size
    mov     r8d, 1
    call    net_send_to
    add     rsp, 8
.ret:
    ret

; ev_net_sync(): the host sends the EVHUD whenever it differs from the last one sent (retried while the queue is full)
ev_net_sync:
    sub     rsp, 8
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .ret
    lea     rsi, [ev_hud]
    lea     rdi, [ev_sent]
    mov     rax, [rsi]
    cmp     rax, [rdi]
    jne     .send
    mov     rax, [rsi + 8]
    cmp     rax, [rdi + 8]
    jne     .send
    mov     eax, [rsi + 16]
    cmp     eax, [rdi + 16]
    je      .ret
.send:
    mov     edi, MT_EVENT_STATE
    lea     rsi, [ev_hud]
    mov     edx, EVHUD_size
    mov     ecx, 1
    call    net_out
    test    eax, eax
    jz      .ret
    lea     rsi, [ev_hud]
    mov     rax, [rsi]
    mov     [ev_sent], rax
    mov     rax, [rsi + 8]
    mov     [ev_sent + 8], rax
    mov     eax, [rsi + 16]
    mov     [ev_sent + 16], eax
.ret:
    add     rsp, 8
    ret

; ev_hud_build(): ev_hud from the event as it is
ev_hud_build:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    lea     rbx, [ev_hud]
    xor     eax, eax
    mov     [rbx], rax
    mov     [rbx + 8], rax
    mov     [rbx + 16], eax
    mov     byte [rbx + EVHUD.protect], EV_SLOT_NONE
    mov     eax, [ev_state]
    test    eax, eax
    jz      .ret
    mov     [rbx + EVHUD.state], al
    mov     eax, [ev_kind]
    mov     [rbx + EVHUD.kind], al
    mov     eax, [ev_wave]
    mov     [rbx + EVHUD.wave], al
    mov     eax, [ev_waves]
    mov     [rbx + EVHUD.waves], al
    mov     eax, [ev_faction]
    mov     [rbx + EVHUD.faction], al
    mov     eax, [ev_protect]
    mov     [rbx + EVHUD.protect], al
    call    ev_count_attackers
    mov     ecx, 255
    cmp     eax, ecx
    cmova   eax, ecx
    mov     [rbx + EVHUD.left], al
    cmp     dword [ev_state], EVS_TRAVEL
    jne     .secs
    cmp     dword [ev_wait], 0
    je      .secs
    mov     byte [rbx + EVHUD.flags], EHF_WAIT
.secs:
    mov     eax, [ev_state]
    cmp     eax, EVS_COUNTDOWN
    je      .secs_do
    cmp     eax, EVS_BREAK
    jne     .pos
.secs_do:
    mov     eax, [ev_timer]
    add     eax, 59
    xor     edx, edx
    mov     ecx, 60
    div     ecx
    mov     [rbx + EVHUD.secs], ax
.pos:
    movss   xmm0, [ev_ax]               ; a camp: its centre; a caravan: where it goes
    movss   xmm1, [ev_az]
    cmp     dword [ev_kind], EVK_CARAVAN
    jb      .abs
    movss   xmm0, [ev_dx]
    movss   xmm1, [ev_dz]
.abs:
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    add     eax, [world_origin_x]
    mov     [rbx + EVHUD.ax], eax
    roundss xmm1, xmm1, 9
    cvttss2si eax, xmm1
    add     eax, [world_origin_z]
    mov     [rbx + EVHUD.az], eax
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; events_offer_kind(edi slot) -> eax EVK_*: the offer that folk makes. The running offer's kind when it is the offered
; NPC (every client knows it from ev_hud), else a leader a site's, a trader a road's; else 0
events_offer_kind:
    sub     rsp, 8
    cmp     byte [ev_hud + EVHUD.state], EVS_OFFERED
    jne     .folk
    movzx   eax, byte [ev_hud + EVHUD.protect]
    cmp     eax, edi
    jne     .folk
    movzx   eax, byte [ev_hud + EVHUD.kind]
    jmp     .ret
.folk:
    xor     eax, eax
    cmp     edi, MAX_MOBS
    jae     .ret
    call    ev_mob
    cmp     dword [rax + MOB.type], MOB_FOLK
    jne     .none
    movzx   ecx, byte [rax + MOB.role]
    mov     eax, EVK_SITE
    cmp     ecx, ROLE_LEADER
    je      .ret
    mov     eax, EVK_ROAD
    cmp     ecx, ROLE_TRADER
    je      .ret
.none:
    xor     eax, eax
.ret:
    add     rsp, 8
    ret

; ==== text: banners, sounds, XP =================================================================================

; ev_award_xp(edi kind): this client's share of a won event: the base + a share of its own level, when this player is
; within 96 blocks of the event's centre (ev_hud.ax / az, absolute)
ev_award_xp:
    push    rbx
    sub     rsp, 16
    cmp     edi, EVK_CAMP
    jb      .ret
    cmp     edi, EVK_ROAD
    ja      .ret
    mov     ebx, edi
    mov     eax, [ev_hud + EVHUD.ax]
    sub     eax, [world_origin_x]
    cvtsi2ss xmm0, eax
    subss   xmm0, [player + BODY.x]
    mulss   xmm0, xmm0
    mov     eax, [ev_hud + EVHUD.az]
    sub     eax, [world_origin_z]
    cvtsi2ss xmm1, eax
    subss   xmm1, [player + BODY.z]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [k_96sq]
    ja      .ret
    movzx   eax, byte [rpg_state + RPGSAVE.level]
    lea     rcx, [ev_xp_lvl]
    movzx   edx, byte [rcx + rbx]
    imul    eax, edx
    lea     rcx, [ev_xp_base]
    movzx   edx, word [rcx + rbx * 2]
    add     eax, edx
    mov     edi, eax
    call    rpg_add_xp
.ret:
    add     rsp, 16
    pop     rbx
    ret

; events_on_ev(edi code, esi arg): an EV_EVENT_* reaches this client: the banner, the sound and (WON) the XP.
; rbx = the end of the text, r12d = code, r13d = arg, r14d = kind, r15d = faction;
; frame: [rsp] text (80), [rsp+80] colour, [rsp+84] sound, [rsp+88] volume
events_on_ev:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 104
    lea     eax, [rdi - EV_EVENT_OFFER]
    cmp     eax, EV_EVENT_LOST - EV_EVENT_OFFER
    ja      .ret
    mov     r12d, edi
    mov     r13d, esi
    movzx   r14d, r13b
    mov     eax, r13d
    shr     eax, 8
    movzx   r15d, al
    lea     rbx, [rsp]
    mov     dword [rsp + 80], RGBA(255, 215, 60, 255)
    mov     dword [rsp + 88], __float32__(0.8)
    cmp     r12d, EV_EVENT_OFFER
    je      .offer
    cmp     r12d, EV_EVENT_START
    je      .start
    cmp     r12d, EV_EVENT_WAVE
    je      .wave
    cmp     r12d, EV_EVENT_WON
    je      .won
    jmp     .lost
.offer:
    mov     dword [rsp + 84], SND_VILLAGER
    cmp     r14d, EVK_CAMP
    jne     .o_site
    CATS    s_a
    CATFAC  r15d
    CATS    s_camp_asks
    jmp     .out
.o_site:
    cmp     r14d, EVK_SITE
    jne     .o_van
    test    r15d, r15d
    jnz     .o_camp
    CATS    s_vil_thr
    jmp     .out
.o_camp:
    CATS    s_the
    CATFAC  r15d
    CATS    s_camp_thr
    jmp     .out
.o_van:
    CATS    s_a
    CATFAC  r15d
    CATS    s_van_needs
    jmp     .out
.start:
    mov     dword [rsp + 84], SND_WARCRY
    cmp     r14d, EVK_SITE
    ja      .s_van
    CATS    s_defend
    mov     eax, r13d
    shr     eax, 16
    movzx   eax, al
    CATN    eax
    CATS    s_waves
    jmp     .out
.s_van:
    CATS    s_escort
    jmp     .out
.wave:
    mov     dword [rsp + 84], SND_WARCRY
    mov     dword [rsp + 80], RGBA(255, 120, 60, 255)
    cmp     r14d, EVK_CARAVAN
    jb      .w_camp
    CATS    s_ambush
    jmp     .out
.w_camp:
    CATS    s_wave
    mov     eax, r13d
    shr     eax, 8
    movzx   eax, al
    CATN    eax
    CATC    '/'
    mov     eax, r13d
    shr     eax, 16
    movzx   eax, al
    CATN    eax
    mov     eax, r13d
    shr     eax, 24
    test    eax, eax
    jnz     .w_mon
    CATS    s_raiders
    jmp     .out
.w_mon:
    CATS    s_monsters
    jmp     .out
.won:
    mov     dword [rsp + 84], SND_QUEST
    mov     dword [rsp + 80], RGBA(120, 255, 120, 255)
    mov     dword [rsp + 88], __float32__(1.0)
    mov     edi, r14d
    call    ev_award_xp
    cmp     r14d, EVK_SITE
    ja      .v_safe
    cmp     r14d, EVK_SITE
    jne     .c_safe
    test    r15d, r15d
    jnz     .c_safe
    CATS    s_vil_safe
    jmp     .out
.c_safe:
    CATS    s_the
    CATFAC  r15d
    CATS    s_camp_safe
    jmp     .out
.v_safe:
    CATS    s_van_safe
    jmp     .out
.lost:
    mov     dword [rsp + 84], SND_SLAM
    mov     dword [rsp + 80], RGBA(255, 85, 85, 255)
    mov     dword [rsp + 88], __float32__(0.7)
    mov     eax, r13d
    shr     eax, 16
    movzx   eax, al
    cmp     eax, EVL_ABANDONED
    jne     .l_not_ab
    CATS    s_abandoned
    jmp     .out
.l_not_ab:
    cmp     eax, EVL_BLOCKED
    jne     .l_died
    CATS    s_turned
    jmp     .out
.l_died:
    cmp     r14d, EVK_SITE
    ja      .l_van
    cmp     r14d, EVK_SITE
    jne     .l_camp
    test    r15d, r15d
    jnz     .l_camp
    CATS    s_vil_fell
    jmp     .out
.l_camp:
    CATS    s_the
    CATFAC  r15d
    CATS    s_camp_fell
    jmp     .out
.l_van:
    CATS    s_van_lost
.out:
    mov     byte [rbx], 0
    lea     rdi, [rsp]
    mov     esi, [rsp + 80]
    call    hud_banner
    mov     edi, [rsp + 84]
    movss   xmm0, [rsp + 88]
    call    audio_play
.ret:
    add     rsp, 104
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; events_status(rdi out) -> rax the end of the debug text (no NUL): "none" or "<Kind> <Faction> <state> w/n (k left)"
events_status:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     rbx, rdi
    movzx   r12d, byte [ev_hud + EVHUD.state]
    test    r12d, r12d
    jnz     .on
    CATS    s_none
    jmp     .done
.on:
    movzx   eax, byte [ev_hud + EVHUD.kind]
    cmp     eax, EVK_ROAD
    jbe     .k_ok
    xor     eax, eax
.k_ok:
    lea     rcx, [ev_kind_names]
    mov     rsi, [rcx + rax * 8]
    mov     rdi, rbx
    call    str_append
    mov     rbx, rax
    CATC    ' '
    movzx   edx, byte [ev_hud + EVHUD.faction]
    CATFAC  edx
    CATC    ' '
    cmp     r12d, EVS_CLEANUP
    jbe     .s_ok
    xor     r12d, r12d
.s_ok:
    lea     rcx, [ev_state_names]
    mov     rsi, [rcx + r12 * 8]
    mov     rdi, rbx
    call    str_append
    mov     rbx, rax
    movzx   eax, byte [ev_hud + EVHUD.wave]
    test    eax, eax
    jz      .left
    CATC    ' '
    movzx   eax, byte [ev_hud + EVHUD.wave]
    CATN    eax
    CATC    '/'
    movzx   eax, byte [ev_hud + EVHUD.waves]
    CATN    eax
.left:
    movzx   eax, byte [ev_hud + EVHUD.left]
    test    eax, eax
    jz      .done
    CATS    s_left_a
    movzx   eax, byte [ev_hud + EVHUD.left]
    CATN    eax
    CATS    s_left_b
.done:
    mov     rax, rbx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ==== the offers ================================================================================================

; ev_refresh() -> eax the NPCs that offer an event now. Every folk without a patrol that is a site's leader or camp's
; trader (evs_site_of) whose faction is at 0 or better, whose site is threatened today (hash, in Survival; or forced by
; events_force_threat), whose road exists (trader) and that has no "done" record, gets FF_HELP; the others lose it. The
; first time an offer is flagged it is recorded and announced (EV_EVENT_OFFER).
; rbx = the mob, r12d = slot, r13d = threatened, r15d = flagged; frame: [rsp] cax, caz, [rsp+8] day, [rsp+12] kind, [rsp+16] road end
ev_refresh:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     eax, [game_time]
    xor     edx, edx
    mov     ecx, DAY_LENGTH
    div     ecx
    mov     [rsp + 8], eax
    lea     rbx, [mobs]
    xor     r12d, r12d
    xor     r15d, r15d
.l:
    cmp     dword [rbx + MOB.type], MOB_FOLK
    jne     .n
    cmp     dword [rbx + MOB.patrol], 0
    jne     .n
    movzx   eax, byte [rbx + MOB.role]
    cmp     eax, ROLE_LEADER
    je      .cand
    cmp     eax, ROLE_TRADER
    jne     .n
.cand:
    mov     rdi, rbx
    lea     rsi, [rsp]
    call    evs_site_of
    test    eax, eax
    jz      .clear
    mov     [rsp + 12], eax
    movzx   edi, byte [rbx + MOB.faction]
    call    faction_standing
    test    eax, eax
    js      .clear
    xor     r13d, r13d
    cmp     dword [ev_fk_valid], 0
    je      .hash
    mov     eax, [rsp + 8]
    cmp     eax, [ev_fk_day]
    jne     .hash
    mov     eax, [rsp]
    cmp     eax, [ev_fk_x]
    jne     .hash
    mov     eax, [rsp + 4]
    cmp     eax, [ev_fk_z]
    jne     .hash
    mov     r13d, 1
    jmp     .thr
.hash:
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .thr
    mov     edx, [rsp + 8]
    lea     edx, [rdx * 2 + 4000]
    cmp     dword [rsp + 12], EVK_SITE
    je      .h
    inc     edx
.h:
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    call    hash32
    xor     edx, edx
    mov     ecx, 3
    div     ecx
    test    edx, edx
    sete    al
    movzx   r13d, al
.thr:
    test    r13d, r13d
    jz      .clear
    cmp     dword [rsp + 12], EVK_ROAD
    jne     .gates
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    lea     rdx, [rsp + 16]
    call    evs_road_from
    test    eax, eax
    jz      .clear
.gates:
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    mov     edx, [rsp + 8]
    mov     ecx, [rsp + 12]
    call    ev_ring_find
    test    rax, rax
    jz      .new
    cmp     byte [rax + ES_DONE], 0
    jne     .clear
    jmp     .flag
.new:
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    mov     edx, [rsp + 8]
    mov     ecx, [rsp + 12]
    call    ev_ring_add
    movzx   esi, byte [rbx + MOB.faction]
    shl     esi, 8
    or      esi, [rsp + 12]
    mov     edi, EV_EVENT_OFFER
    call    net_event_out
.flag:
    or      byte [rbx + MOB.fflags], FF_HELP
    inc     r15d
    jmp     .n
.clear:
    and     byte [rbx + MOB.fflags], ~FF_HELP
.n:
    add     rbx, MOB_size
    inc     r12d
    cmp     r12d, MAX_MOBS
    jb      .l
    mov     eax, r15d
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; events_force_threat() -> eax 1 when the leader of the nearest site within 96 blocks of the player (and that camp's
; trader) now offer an event: whatever the mode or the day's hash (the site's "done" records of today are forgotten)
; rbx = the mob, r12d = slot, r13d = found; frame: [rsp] out, [rsp+8] best d2, [rsp+12] day, [rsp+16] cax, [rsp+20] caz
events_force_threat:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 32
    xor     r13d, r13d
    cmp     dword [ev_state], EVS_NONE
    jne     .no
    mov     eax, [game_time]
    xor     edx, edx
    mov     ecx, DAY_LENGTH
    div     ecx
    mov     [rsp + 12], eax
    mov     dword [rsp + 8], __float32__(9216.0)
    lea     rbx, [mobs]
    xor     r12d, r12d
.l:
    cmp     dword [rbx + MOB.type], MOB_FOLK
    jne     .n
    cmp     dword [rbx + MOB.patrol], 0
    jne     .n
    cmp     byte [rbx + MOB.role], ROLE_LEADER
    jne     .n
    mov     rdi, rbx
    lea     rsi, [rsp]
    call    evs_site_of
    cmp     eax, EVK_SITE
    jne     .n
    movss   xmm0, [player + BODY.x]
    movss   xmm1, [player + BODY.z]
    mov     rdi, rbx
    call    ev_body_d2
    comiss  xmm0, [rsp + 8]
    ja      .n
    movss   [rsp + 8], xmm0
    mov     eax, [rsp]
    mov     [rsp + 16], eax
    mov     eax, [rsp + 4]
    mov     [rsp + 20], eax
    mov     r13d, 1
.n:
    add     rbx, MOB_size
    inc     r12d
    cmp     r12d, MAX_MOBS
    jb      .l
    test    r13d, r13d
    jz      .no
    mov     dword [ev_fk_valid], 1
    mov     eax, [rsp + 16]
    mov     [ev_fk_x], eax
    mov     eax, [rsp + 20]
    mov     [ev_fk_z], eax
    mov     eax, [rsp + 12]
    mov     [ev_fk_day], eax
    lea     rcx, [ev_seen]                  ; forget today's records of that site
    mov     edx, EV_SEEN_N
.r:
    mov     eax, [rcx + ES_CAX]
    cmp     eax, [rsp + 16]
    jne     .rn
    mov     eax, [rcx + ES_CAZ]
    cmp     eax, [rsp + 20]
    jne     .rn
    mov     eax, [rcx + ES_DAY]
    cmp     eax, [rsp + 12]
    jne     .rn
    mov     byte [rcx + ES_DONE], 0
.rn:
    add     rcx, ES_SIZE
    dec     edx
    jnz     .r
    call    ev_refresh
    test    eax, eax
    jz      .no
    mov     eax, 1
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    add     rsp, 32
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ev_refresh_tick(): every 60 steps while there is no event, ev_refresh
ev_refresh_tick:
    sub     rsp, 8
    cmp     dword [ev_state], EVS_NONE
    jne     .ret
    mov     eax, [ev_tick]
    xor     edx, edx
    mov     ecx, 60
    div     ecx
    test    edx, edx
    jnz     .ret
    call    ev_refresh
.ret:
    add     rsp, 8
    ret

; ev_spontaneous(): on every 10th minute (game_time % 36000 == 0) in Survival with no event: an even cycle tries a
; temporary camp, an odd one a free caravan, around the players in turn
ev_spontaneous:
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .skip
    cmp     dword [ev_state], EVS_NONE
    jne     .skip
    mov     eax, [game_time]
    xor     edx, edx
    mov     ecx, EV_CYCLE
    div     ecx
    test    edx, edx
    jnz     .skip
    cmp     eax, [ev_cyc]
    je      .skip
    mov     [ev_cyc], eax
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, eax
    call    nm_ready_count
    inc     eax
    mov     ecx, eax
    mov     eax, ebx
    xor     edx, edx
    div     ecx
    lea     r12, [player]
    test    edx, edx
    jz      .go
    lea     edi, [rdx - 1]
    call    nm_centre
    test    rax, rax
    jz      .go
    mov     r12, rax
.go:
    mov     rdi, r12
    test    bl, 1
    jnz     .van
    call    events_spawn_camp
    jmp     .done
.van:
    call    events_spawn_caravan
.done:
    pop     r12
    pop     rbx
    pop     rbp
.skip:
    ret

; ==== spawning the offers =======================================================================================

; events_spawn_camp(rdi BODY*) -> eax 1 when a temporary camp now asks that player for help: a tent 32..56 blocks away,
; its leader (FF_HELP) and two guards, all carrying the event's key. 0 when there is an event, too few free slots, no
; faction with standing >= 0 or no place.
; rbx = body, r12d = faction, r13d = level; frame: [rsp] cx, H, cz, [rsp+16] the three slots
events_spawn_camp:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40
    mov     rbx, rdi
    cmp     dword [ev_state], EVS_NONE
    jne     .fail
    call    ev_free_slots
    cmp     eax, EV_MIN_FREE
    jl      .fail
    call    ev_pick_faction
    test    eax, eax
    js      .fail
    mov     r12d, eax
    mov     rdi, rbx
    lea     rsi, [rsp]
    call    evs_find_camp_site
    test    eax, eax
    jz      .fail
    mov     rdi, rbx
    call    ev_body_level
    mov     r13d, eax
    mov     edi, EVK_CAMP
    mov     esi, r12d
    mov     edx, r13d
    call    ev_begin
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    mov     edx, [rsp + 8]
    mov     ecx, r12d
    call    evs_build_tent
    mov     dword [rsp + 16], -1
    mov     dword [rsp + 20], -1
    mov     dword [rsp + 24], -1
    xor     r14d, r14d                      ; 0 leader, 1 guard (archer), 2 guard (berserker)
.spawn:
    mov     eax, [rsp]
    cmp     r14d, 1
    jne     .dx_not1
    add     eax, 2
    jmp     .xset
.dx_not1:
    sub     eax, 2
.xset:
    cvtsi2ss xmm0, eax
    addss   xmm0, [k_half]
    mov     eax, [rsp + 4]
    inc     eax
    cvtsi2ss xmm1, eax
    mov     eax, [rsp + 8]
    cmp     r14d, 2
    jne     .dz_not2
    add     eax, 2
    jmp     .zset
.dz_not2:
    sub     eax, 2
.zset:
    cvtsi2ss xmm2, eax
    addss   xmm2, [k_half]
    mov     edi, r12d
    mov     esi, ROLE_GUARD
    mov     edx, FCLASS_ARCHER
    cmp     r14d, 1
    je      .cls
    mov     edx, FCLASS_BERSERKER
    cmp     r14d, 2
    je      .cls
    mov     esi, ROLE_LEADER
    xor     edx, edx
.cls:
    call    folk_spawn
    test    eax, eax
    js      .rollback
    mov     [rsp + r14 * 4 + 16], eax
    mov     edi, eax
    xor     esi, esi
    test    r14d, r14d
    jnz     .tag
    mov     esi, FF_HELP
.tag:
    call    ev_tag
    inc     r14d
    cmp     r14d, 3
    jb      .spawn
    mov     eax, [rsp + 16]
    mov     [ev_protect], eax
    mov     eax, [rsp]
    cvtsi2ss xmm0, eax
    addss   xmm0, [k_half]
    movss   [ev_ax], xmm0
    mov     eax, [rsp + 8]
    cvtsi2ss xmm0, eax
    addss   xmm0, [k_half]
    movss   [ev_az], xmm0
    mov     dword [ev_state], EVS_OFFERED
    mov     dword [ev_timer], EV_OFFER_STEPS
    mov     esi, r12d
    shl     esi, 8
    or      esi, EVK_CAMP
    mov     edi, EV_EVENT_OFFER
    call    net_event_out
    mov     eax, 1
    jmp     .ret
.rollback:
    xor     r14d, r14d
.rb:
    mov     edi, [rsp + r14 * 4 + 16]
    cmp     edi, MAX_MOBS
    jae     .rbn
    call    ev_mob
    mov     dword [rax + MOB.type], MOB_NONE
.rbn:
    inc     r14d
    cmp     r14d, 3
    jb      .rb
    call    evs_remove_tent
    call    ev_idle
.fail:
    xor     eax, eax
.ret:
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ev_party_spawn(edi faction, esi level, edx merchant flags) -> eax 1 when the caravan party stands at the route's start
; (ev_sx, ev_sz): a ROLE_CARAVAN merchant (dest = the route's end, protected) and a brute and an archer guard 1.5 blocks
; to its sides, all carrying the key. 0 (nothing left behind) when there is no ground.
; r12d = faction, r13d = i; frame: [rsp] x, y, z, [rsp+12] merchant ground, [rsp+16] the three slots, [rsp+28] flags, [rsp+32] level
ev_party_spawn:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40
    mov     r12d, edi
    mov     [rsp + 32], esi
    mov     [rsp + 28], edx
    mov     dword [rsp + 16], -1
    mov     dword [rsp + 20], -1
    mov     dword [rsp + 24], -1
    xor     r13d, r13d
.i:
    movss   xmm0, [ev_sx]
    movss   xmm1, [ev_sz]
    lea     rax, [k_side]
    movss   xmm2, [rax + r13 * 4]
    movss   xmm3, [ev_uz]
    mulss   xmm3, xmm2
    subss   xmm0, xmm3
    movss   xmm3, [ev_ux]
    mulss   xmm3, xmm2
    addss   xmm1, xmm3
    movss   [rsp], xmm0
    movss   [rsp + 8], xmm1
    roundss xmm0, xmm0, 9
    cvttss2si edi, xmm0
    roundss xmm1, xmm1, 9
    cvttss2si esi, xmm1
    call    evs_ground
    test    eax, eax
    jns     .g
    test    r13d, r13d
    jz      .fail
    mov     eax, [rsp + 12]
.g:
    test    r13d, r13d
    jnz     .gk
    mov     [rsp + 12], eax
.gk:
    inc     eax
    cvtsi2ss xmm1, eax
    movss   [rsp + 4], xmm1
    mov     edi, r12d
    lea     rcx, [role_tab]
    movzx   esi, byte [rcx + r13]
    lea     rcx, [class_tab]
    movzx   edx, byte [rcx + r13]
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    call    folk_spawn
    test    eax, eax
    js      .fail
    mov     [rsp + r13 * 4 + 16], eax
    mov     r14d, eax
    mov     edi, eax
    xor     esi, esi
    test    r13d, r13d
    jnz     .tag
    mov     esi, [rsp + 28]
.tag:
    call    ev_tag
    mov     edi, r14d
    call    ev_mob
    test    r13d, r13d
    jnz     .guard
    mov     ecx, [ev_dx]
    mov     [rax + MOB.dest_x], ecx
    mov     ecx, [ev_dz]
    mov     [rax + MOB.dest_z], ecx
    mov     [ev_protect], r14d
    jmp     .next
.guard:
    mov     ecx, [ev_sx]
    mov     [rax + MOB.home_x], ecx
    mov     ecx, [ev_sz]
    mov     [rax + MOB.home_z], ecx
.next:
    inc     r13d
    cmp     r13d, 3
    jb      .i
    mov     eax, 1
    jmp     .ret
.fail:
    xor     r13d, r13d
.rb:
    mov     edi, [rsp + r13 * 4 + 16]
    cmp     edi, MAX_MOBS
    jae     .rbn
    call    ev_mob
    mov     dword [rax + MOB.type], MOB_NONE
.rbn:
    inc     r13d
    cmp     r13d, 3
    jb      .rb
    mov     dword [ev_protect], EV_SLOT_NONE
    xor     eax, eax
.ret:
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; (the party takes the event's level: ev_tag reads ev_level)

; events_spawn_caravan(rdi BODY*) -> eax 1 when a free caravan now asks that player for an escort: its merchant (FF_HELP,
; halted) and two guards 20..32 blocks away, bound for a point 160..240 blocks off. 0 as events_spawn_camp.
; rbx = body, r12d = faction, r13d = tries, r14d = level; frame: [rsp] sin, cos, [rsp+8] cx, cz, [rsp+16] ground, [rsp+24] dest
events_spawn_caravan:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40
    mov     rbx, rdi
    cmp     dword [ev_state], EVS_NONE
    jne     .fail
    call    ev_free_slots
    cmp     eax, EV_MIN_FREE
    jl      .fail
    call    ev_pick_faction
    test    eax, eax
    js      .fail
    mov     r12d, eax
    mov     rdi, rbx
    call    ev_body_level
    mov     r14d, eax
    mov     r13d, 16
.try:
    call    rng_next
    xor     edx, edx
    mov     ecx, 360
    div     ecx
    cvtsi2ss xmm0, edx
    call    sincos_deg
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    mov     edi, 13
    call    ev_rnd
    add     eax, 20
    cvtsi2ss xmm2, eax
    movss   xmm0, [rsp]
    mulss   xmm0, xmm2
    addss   xmm0, [rbx + BODY.x]
    roundss xmm0, xmm0, 9
    cvttss2si edi, xmm0
    mov     [rsp + 8], edi
    movss   xmm1, [rsp + 4]
    mulss   xmm1, xmm2
    movss   xmm3, [rbx + BODY.z]
    subss   xmm3, xmm1
    roundss xmm3, xmm3, 9
    cvttss2si esi, xmm3
    mov     [rsp + 12], esi
    call    evs_ground
    test    eax, eax
    jns     .found
    dec     r13d
    jnz     .try
    jmp     .fail
.found:
    mov     [rsp + 16], eax
    mov     edi, [rsp + 8]
    add     edi, [world_origin_x]
    mov     esi, [rsp + 12]
    add     esi, [world_origin_z]
    lea     rdx, [rsp + 24]
    call    evs_find_route
    test    eax, eax
    jz      .fail
    mov     edi, EVK_CARAVAN
    mov     esi, r12d
    mov     edx, r14d
    call    ev_begin
    mov     eax, [rsp + 8]
    cvtsi2ss xmm0, eax
    addss   xmm0, [k_half]
    movss   [ev_sx], xmm0
    movss   [ev_ax], xmm0
    mov     eax, [rsp + 12]
    cvtsi2ss xmm0, eax
    addss   xmm0, [k_half]
    movss   [ev_sz], xmm0
    movss   [ev_az], xmm0
    mov     eax, [rsp + 24]
    sub     eax, [world_origin_x]
    cvtsi2ss xmm0, eax
    addss   xmm0, [k_half]
    movss   [ev_dx], xmm0
    mov     eax, [rsp + 28]
    sub     eax, [world_origin_z]
    cvtsi2ss xmm0, eax
    addss   xmm0, [k_half]
    movss   [ev_dz], xmm0
    call    ev_route_setup
    mov     edi, r12d
    mov     esi, r14d
    mov     edx, FF_HELP | FF_HALT
    call    ev_party_spawn
    test    eax, eax
    jnz     .ok
    call    ev_idle
    jmp     .fail
.ok:
    mov     dword [ev_state], EVS_OFFERED
    mov     dword [ev_timer], EV_OFFER_STEPS
    mov     esi, r12d
    shl     esi, 8
    or      esi, EVK_CARAVAN
    mov     edi, EV_EVENT_OFFER
    call    net_event_out
    mov     eax, 1
    jmp     .ret
.fail:
    xor     eax, eax
.ret:
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ==== accepting =================================================================================================

; events_accept(edi mob_slot) -> eax 1 when the event starts, 0 refused. The folk must offer one (FF_HELP):
; the offered camp's leader / caravan's merchant (OFFERED -> COUNTDOWN); with no event a site's leader (EVK_SITE: the site's
; folk become defenders) or a camp's trader (EVK_ROAD: a merchant and two guards appear on the road).
; rbx = the mob, r12d = slot, r13d = faction; frame: [rsp] cax, caz, [rsp+8] road end, [rsp+16] day, [rsp+20] float scratch (4)
events_accept:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 56
    cmp     edi, MAX_MOBS
    jae     .no
    mov     r12d, edi
    call    ev_mob
    mov     rbx, rax
    cmp     dword [rbx + MOB.type], MOB_FOLK
    jne     .no
    test    byte [rbx + MOB.fflags], FF_HELP
    jz      .no
    mov     eax, [ev_state]
    cmp     eax, EVS_OFFERED
    je      .offered
    test    eax, eax
    jnz     .no
    movzx   eax, byte [rbx + MOB.role]
    cmp     eax, ROLE_LEADER
    je      .site
    cmp     eax, ROLE_TRADER
    je      .road
    jmp     .no
.offered:
    cmp     r12d, [ev_protect]
    jne     .no
    and     byte [rbx + MOB.fflags], ~FF_HELP
    mov     dword [ev_state], EVS_COUNTDOWN
    mov     dword [ev_timer], EV_COUNT_STEPS
    call    ev_send_start
    jmp     .yes
.site:
    call    ev_free_slots
    cmp     eax, EV_MIN_FREE
    jl      .no
    cmp     dword [rbx + MOB.patrol], 0
    jne     .no
    mov     rdi, rbx
    lea     rsi, [rsp]
    call    evs_site_of
    cmp     eax, EVK_SITE
    jne     .no
    movzx   r13d, byte [rbx + MOB.faction]
    mov     edi, r13d
    call    faction_standing
    test    eax, eax
    js      .no
    mov     eax, [game_time]
    xor     edx, edx
    mov     ecx, DAY_LENGTH
    div     ecx
    mov     [rsp + 16], eax
    mov     edi, EVK_SITE
    mov     esi, r13d
    mov     edx, [rbx + MOB.level]
    call    ev_begin
    mov     [ev_protect], r12d
    mov     eax, [rsp]
    sub     eax, [world_origin_x]
    cvtsi2ss xmm0, eax
    addss   xmm0, [k_half]
    movss   [ev_ax], xmm0
    mov     eax, [rsp + 4]
    sub     eax, [world_origin_z]
    cvtsi2ss xmm0, eax
    addss   xmm0, [k_half]
    movss   [ev_az], xmm0
    mov     eax, [k_r_camp2]
    test    r13d, r13d
    jnz     .r2
    mov     eax, [k_r_vill2]
.r2:
    mov     [rsp + 20], eax
    lea     rcx, [mobs]
    mov     edx, MAX_MOBS
.mem:
    cmp     dword [rcx + MOB.type], MOB_FOLK
    jne     .memn
    cmp     [rcx + MOB.faction], r13b
    jne     .memn
    cmp     dword [rcx + MOB.patrol], 0
    jne     .memn
    cmp     byte [rcx + MOB.role], ROLE_CAPTIVE
    je      .memn
    movss   xmm0, [rcx + MOB.home_x]
    subss   xmm0, [ev_ax]
    mulss   xmm0, xmm0
    movss   xmm1, [rcx + MOB.home_z]
    subss   xmm1, [ev_az]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [rsp + 20]
    ja      .memn
    mov     eax, [ev_key]
    mov     [rcx + MOB.patrol], eax
.memn:
    add     rcx, MOB_size
    dec     edx
    jnz     .mem
    mov     eax, [ev_key]
    mov     [rbx + MOB.patrol], eax
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    mov     edx, [rsp + 16]
    mov     ecx, EVK_SITE
    call    ev_mark_done
    call    ev_clear_all_help
    mov     dword [ev_state], EVS_COUNTDOWN
    mov     dword [ev_timer], EV_COUNT_STEPS
    call    ev_send_start
    jmp     .yes
.road:
    call    ev_free_slots
    cmp     eax, EV_MIN_FREE
    jl      .no
    cmp     dword [rbx + MOB.patrol], 0
    jne     .no
    mov     rdi, rbx
    lea     rsi, [rsp]
    call    evs_site_of
    cmp     eax, EVK_ROAD
    jne     .no
    movzx   r13d, byte [rbx + MOB.faction]
    mov     edi, r13d
    call    faction_standing
    test    eax, eax
    js      .no
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    lea     rdx, [rsp + 8]
    call    evs_road_from
    test    eax, eax
    jz      .no
    mov     eax, [game_time]
    xor     edx, edx
    mov     ecx, DAY_LENGTH
    div     ecx
    mov     [rsp + 16], eax
    mov     edi, EVK_ROAD
    mov     esi, r13d
    mov     edx, [rbx + MOB.level]
    call    ev_begin
    ; C = the camp's centre, E = the road's other end (local floats); S = C + u * 16, D = E - u * 16
    mov     eax, [rsp]
    sub     eax, [world_origin_x]
    cvtsi2ss xmm4, eax
    addss   xmm4, [k_half]
    mov     eax, [rsp + 4]
    sub     eax, [world_origin_z]
    cvtsi2ss xmm5, eax
    addss   xmm5, [k_half]
    mov     eax, [rsp + 8]
    sub     eax, [world_origin_x]
    cvtsi2ss xmm6, eax
    addss   xmm6, [k_half]
    mov     eax, [rsp + 12]
    sub     eax, [world_origin_z]
    cvtsi2ss xmm7, eax
    addss   xmm7, [k_half]
    movaps  xmm0, xmm6
    subss   xmm0, xmm4
    movaps  xmm1, xmm7
    subss   xmm1, xmm5
    movaps  xmm2, xmm0
    mulss   xmm2, xmm2
    movaps  xmm3, xmm1
    mulss   xmm3, xmm3
    addss   xmm2, xmm3
    sqrtss  xmm2, xmm2
    comiss  xmm2, [k_16]
    jbe     .abort
    divss   xmm0, xmm2                  ; u
    divss   xmm1, xmm2
    mulss   xmm0, [k_16]                ; u * 16 (the camp's offset is its own 16 blocks)
    mulss   xmm1, [k_16]
    mulss   xmm0, [k_one]
    movaps  xmm2, xmm4
    addss   xmm2, xmm0
    movss   [ev_sx], xmm2
    movaps  xmm2, xmm5
    addss   xmm2, xmm1
    movss   [ev_sz], xmm2
    movaps  xmm2, xmm6
    subss   xmm2, xmm0
    movss   [ev_dx], xmm2
    movaps  xmm2, xmm7
    subss   xmm2, xmm1
    movss   [ev_dz], xmm2
    call    ev_route_setup
    mov     edi, r13d
    mov     esi, [rbx + MOB.level]
    mov     edx, FF_HALT
    call    ev_party_spawn
    test    eax, eax
    jz      .abort
    mov     eax, [ev_sx]
    mov     [ev_ax], eax
    mov     eax, [ev_sz]
    mov     [ev_az], eax
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    mov     edx, [rsp + 16]
    mov     ecx, EVK_ROAD
    call    ev_mark_done
    call    ev_clear_all_help
    mov     dword [ev_state], EVS_COUNTDOWN
    mov     dword [ev_timer], EV_COUNT_STEPS
    call    ev_send_start
    jmp     .yes
.abort:
    call    ev_idle
.no:
    xor     eax, eax
    jmp     .ret
.yes:
    mov     eax, 1
.ret:
    add     rsp, 56
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ==== the state machine =========================================================================================

; ev_to_cleanup(): the event is over without a result: nobody offers it any more, CLEANUP
ev_to_cleanup:
    mov     ecx, [ev_key]
    lea     rax, [mobs]
    mov     edx, MAX_MOBS
.l:
    cmp     dword [rax + MOB.type], MOB_FOLK
    jne     .n
    cmp     [rax + MOB.patrol], ecx
    jne     .n
    and     byte [rax + MOB.fflags], ~FF_HELP
.n:
    add     rax, MOB_size
    dec     edx
    jnz     .l
    mov     dword [ev_state], EVS_CLEANUP
    mov     dword [ev_clean_t], 0
    mov     dword [ev_aband], 0
    ret

; ev_item_roll(rdi pos float[3]): one weighted item of the faction's loot table, dropped at pos
; rbx = pos, r12d = the roll, r13 = the row
ev_item_roll:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rdi
    mov     edi, 100
    call    ev_rnd
    mov     r12d, eax
    mov     eax, [ev_faction]
    cmp     eax, NUM_FACTIONS
    jb      .f
    xor     eax, eax
.f:
    shl     eax, 5
    lea     r13, [ev_loot]
    add     r13, rax
    mov     ecx, 3
.walk:
    movzx   eax, word [r13]
    cmp     r12d, eax
    jb      .hit
    sub     r12d, eax
    add     r13, 8
    dec     ecx
    jnz     .walk
.hit:
    movzx   ecx, word [r13 + 4]         ; min
    movzx   eax, word [r13 + 6]         ; max
    mov     r12d, ecx
    sub     eax, ecx
    inc     eax
    mov     edi, eax
    call    ev_rnd
    add     eax, r12d
    mov     esi, eax                    ; count = min + rnd(max - min + 1)
    movzx   edi, word [r13 + 2]         ; item
    xor     edx, edx
    movss   xmm0, [rbx]
    movss   xmm1, [rbx + 4]
    movss   xmm2, [rbx + 8]
    call    drops_spawn
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ev_gear_roll(rdi pos float[3], esi level): one of the faction's two gear items, rolled for that level (LOOT_ELITE), dropped at pos
; rbx = pos, r12d = level, r13d = item
ev_gear_roll:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12d, esi
    mov     edi, 2
    call    ev_rnd
    mov     ecx, [ev_faction]
    cmp     ecx, NUM_FACTIONS
    jb      .f
    xor     ecx, ecx
.f:
    lea     eax, [rcx * 2 + rax]
    lea     rdx, [ev_gear]
    movzx   r13d, word [rdx + rax * 2]
    xor     edx, edx
    lea     rcx, [item_gear]
    cmp     byte [rcx + r13], 0
    je      .drop
    mov     edi, r12d
    call    gear_tier_for_level
    mov     edi, r13d
    mov     esi, eax
    mov     edx, LOOT_ELITE
    call    gear_roll
    movzx   edx, ax
.drop:
    mov     edi, r13d
    mov     esi, 1
    movss   xmm0, [rbx]
    movss   xmm1, [rbx + 4]
    movss   xmm2, [rbx + 8]
    call    drops_spawn
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ev_reward(): the loot of a won event, dropped at its protected NPC: one bundle (item rolls, gear rolls, coins) per
; player within 64 blocks of it, at least one
; rbx = the NPC, r12d = bundles left, r13d = rolls left, r14d = its level; frame: [rsp] drop position x, y, z
ev_reward:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 16
    call    ev_prot
    test    rax, rax
    jz      .ret
    mov     rbx, rax
    mov     r14d, [rbx + MOB.level]
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.z]
    movss   xmm2, [k_64sq]
    call    ev_players_near
    mov     r12d, eax
    test    r12d, r12d
    jnz     .pos
    mov     r12d, 1
.pos:
    movss   xmm0, [rbx + BODY.x]
    movss   [rsp], xmm0
    movss   xmm0, [rbx + BODY.y]
    addss   xmm0, [k_0_9]
    movss   [rsp + 4], xmm0
    movss   xmm0, [rbx + BODY.z]
    movss   [rsp + 8], xmm0
.bundle:
    mov     eax, [ev_kind]
    lea     rcx, [ev_rolls_item]
    movzx   r13d, byte [rcx + rax]
.items:
    test    r13d, r13d
    jz      .gear
    mov     rdi, rsp
    call    ev_item_roll
    dec     r13d
    jmp     .items
.gear:
    mov     eax, [ev_kind]
    lea     rcx, [ev_rolls_gear]
    movzx   r13d, byte [rcx + rax]
.gears:
    test    r13d, r13d
    jz      .coins
    mov     rdi, rsp
    mov     esi, r14d
    call    ev_gear_roll
    dec     r13d
    jmp     .gears
.coins:
    mov     eax, [ev_kind]
    lea     rcx, [ev_coin_shift]
    movzx   ecx, byte [rcx + rax]
    mov     edx, r14d
    shr     edx, cl
    lea     rcx, [ev_coin_base]
    movzx   eax, byte [rcx + rax]
    add     edx, eax
    mov     rdi, rbx
    call    mob_coins
    dec     r12d
    jnz     .bundle
.ret:
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ev_end(edi won, esi reason): the event is over: a win pays (standing, loot), nobody offers or halts any more (a winning
; merchant stays to trade), a site's folk stop being defenders; the banner goes out (every client); CLEANUP
; r12d = won, r13d = reason, r14d = key; frame: [rsp] mobs left
ev_end:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 16
    mov     r12d, edi
    mov     r13d, esi
    test    r12d, r12d
    jz      .flags
    mov     edi, [ev_faction]
    mov     eax, [ev_kind]
    lea     rcx, [ev_kind_rep]
    movzx   esi, byte [rcx + rax]
    call    faction_add
    call    ev_reward
.flags:
    mov     r14d, [ev_key]
    lea     rbx, [mobs]
    mov     dword [rsp], MAX_MOBS
.l:
    cmp     dword [rbx + MOB.type], MOB_FOLK
    jne     .n
    cmp     [rbx + MOB.patrol], r14d
    jne     .n
    and     byte [rbx + MOB.fflags], ~FF_HELP
    cmp     byte [rbx + MOB.role], ROLE_CARAVAN
    jne     .halt
    test    r12d, r12d
    jnz     .site
.halt:
    and     byte [rbx + MOB.fflags], ~FF_HALT
.site:
    cmp     dword [ev_kind], EVK_SITE
    jne     .n
    mov     dword [rbx + MOB.patrol], 0
.n:
    add     rbx, MOB_size
    dec     dword [rsp]
    jnz     .l
    mov     dword [ev_state], EVS_CLEANUP
    mov     dword [ev_clean_t], 0
    mov     dword [ev_aband], 0
    mov     esi, [ev_faction]
    shl     esi, 8
    or      esi, [ev_kind]
    test    r12d, r12d
    jz      .lost
    mov     edi, EV_EVENT_WON
    jmp     .send
.lost:
    shl     r13d, 16
    or      esi, r13d
    mov     edi, EV_EVENT_LOST
.send:
    call    net_event_out
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ev_wave_begin(edi state): a wave (WAVE) or an ambush (AMBUSH) starts: sized and spawned by ev_do_wave over the next steps
; ebx = night
ev_wave_begin:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    mov     [ev_state], edi
    inc     dword [ev_wave]
    xor     eax, eax
    mov     [ev_win_t], eax
    mov     [ev_size], eax
    mov     [ev_spawned], eax
    mov     [ev_after_t], eax
    xor     ebx, ebx
    cmp     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL
    je      .set
    mov     edi, [game_time]
    call    sky_is_night
    mov     ebx, eax
.set:
    mov     [ev_night], ebx
    cmp     dword [ev_kind], EVK_CARAVAN
    jae     .send
    call    rng_next                        ; a camp wave comes from one bearing, 30 blocks out
    xor     edx, edx
    mov     ecx, 360
    div     ecx
    cvtsi2ss xmm0, edx
    call    sincos_deg
    mulss   xmm0, [k_30]
    addss   xmm0, [ev_ax]
    movss   [ev_wpx], xmm0
    mulss   xmm1, [k_30]
    movss   xmm2, [ev_az]
    subss   xmm2, xmm1
    movss   [ev_wpz], xmm2
.send:
    mov     esi, [ev_kind]
    mov     eax, [ev_wave]
    shl     eax, 8
    or      esi, eax
    mov     eax, [ev_waves]
    shl     eax, 16
    or      esi, eax
    mov     eax, ebx
    shl     eax, 24
    or      esi, eax
    mov     edi, EV_EVENT_WAVE
    call    net_event_out
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ev_attack_cell(rdi out dd[2]): a cell to try for the next attacker: a camp wave's point +-6 blocks; a caravan's ambush 24
; blocks ahead of the merchant, 4..10 blocks to a random side. Frame: [rsp] x, [rsp+4] z
ev_attack_cell:
    push    rbx
    sub     rsp, 16
    mov     [rsp + 8], rdi
    mov     rbx, rdi
    cmp     dword [ev_kind], EVK_CARAVAN
    jae     .van
    mov     edi, 13
    call    ev_rnd
    sub     eax, 6
    cvtsi2ss xmm0, eax
    addss   xmm0, [ev_wpx]
    movss   [rsp], xmm0
    mov     edi, 13
    call    ev_rnd
    sub     eax, 6
    cvtsi2ss xmm0, eax
    addss   xmm0, [ev_wpz]
    movss   [rsp + 4], xmm0
    jmp     .out
.van:
    mov     edi, 7
    call    ev_rnd
    add     eax, 4
    mov     ebx, eax                        ; keep rbx's pointer in the frame instead
    mov     edi, 2
    call    ev_rnd
    test    eax, eax
    jnz     .pos
    neg     ebx
.pos:
    cvtsi2ss xmm2, ebx                      ; the signed perpendicular offset
    mov     rbx, [rsp + 8]
    movss   xmm0, [ev_ux]
    mulss   xmm0, [k_24]
    movss   xmm1, [ev_uz]
    mulss   xmm1, xmm2
    subss   xmm0, xmm1
    addss   xmm0, [ev_ax]
    movss   [rsp], xmm0
    movss   xmm0, [ev_uz]
    mulss   xmm0, [k_24]
    movss   xmm1, [ev_ux]
    mulss   xmm1, xmm2
    addss   xmm0, xmm1
    addss   xmm0, [ev_az]
    movss   [rsp + 4], xmm0
.out:
    movss   xmm0, [rsp]
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    mov     [rbx], eax
    movss   xmm0, [rsp + 4]
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    mov     [rbx + 4], eax
    add     rsp, 16
    pop     rbx
    ret

; ev_spawn_attacker(edi idx, esi last) -> eax the slot of a new attacker, or -1 (no cell took it in 8 tries). Monsters
; by night (and above Peaceful): zombie, skeleton or spider; else a raider of the rival faction, class 1..4. The first
; of the last wave / ambush is an elite. Order: spawn_at_ground, folk_init, mob_set_level, make_elite, patrol,
; dest = home = the protected NPC, provoked.
; ebx = idx, r12d = tries / the MOB, r13d = type, r14d = slot; frame: [rsp] cell x, z, [rsp+8] elite
ev_spawn_attacker:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 16
    mov     ebx, edi
    xor     eax, eax
    test    ebx, ebx
    jnz     .el
    mov     eax, esi
.el:
    mov     [rsp + 8], eax
    mov     r13d, MOB_FOLK
    cmp     dword [ev_night], 0
    je      .typed
    mov     edi, 10
    call    ev_rnd
    mov     r13d, MOB_ZOMBIE
    cmp     eax, 5
    jb      .typed
    mov     r13d, MOB_SKELETON
    cmp     eax, 8
    jb      .typed
    mov     r13d, MOB_SPIDER
.typed:
    mov     r12d, 8
.try:
    lea     rdi, [rsp]
    call    ev_attack_cell
    mov     edi, r13d
    mov     esi, [rsp]
    mov     edx, [rsp + 4]
    mov     ecx, GROUND_HOSTILE
    call    spawn_at_ground
    test    eax, eax
    jns     .got
    dec     r12d
    jnz     .try
    mov     eax, -1
    jmp     .ret
.got:
    mov     r14d, eax
    cmp     r13d, MOB_FOLK
    jne     .level
    mov     edi, 4
    call    ev_rnd
    lea     ecx, [rax + 1]
    mov     edi, r14d
    mov     esi, [ev_rival]
    mov     edx, ROLE_PATROL
    call    folk_init
.level:
    mov     edi, r14d
    mov     esi, [ev_level]
    call    mob_set_level
    mov     edi, r14d
    call    ev_mob
    mov     r12, rax
    cmp     dword [rsp + 8], 0
    je      .patrol
    mov     rdx, r12
    call    make_elite
.patrol:
    mov     eax, [ev_key]
    or      eax, EV_KEY_ATTACK
    mov     [r12 + MOB.patrol], eax
    call    ev_target_pos
    movss   [r12 + MOB.dest_x], xmm0
    movss   [r12 + MOB.dest_z], xmm1
    movss   [r12 + MOB.home_x], xmm0
    movss   [r12 + MOB.home_z], xmm1
    cmp     r13d, MOB_FOLK
    jne     .done
    mov     dword [r12 + MOB.provoked], EV_PROVOKED
.done:
    mov     eax, r14d
.ret:
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ev_remove_attackers(edi mode): every attacker of this event is removed (mode 0), or only those with no player within 24 blocks (1)
; r12d = mode, r13d = the attack key, r14d = slots left, rbx = the mob
ev_remove_attackers:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 16
    mov     r12d, edi
    mov     r13d, [ev_key]
    or      r13d, EV_KEY_ATTACK
    lea     rbx, [mobs]
    mov     r14d, MAX_MOBS
.l:
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .n
    cmp     [rbx + MOB.patrol], r13d
    jne     .n
    test    r12d, r12d
    jz      .kill
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.z]
    movss   xmm2, [k_24sq]
    call    ev_players_near
    test    eax, eax
    jnz     .n
.kill:
    mov     dword [rbx + MOB.type], MOB_NONE
.n:
    add     rbx, MOB_size
    dec     r14d
    jnz     .l
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ev_do_offered(): an offer that nobody takes lapses
ev_do_offered:
    sub     rsp, 8
    dec     dword [ev_timer]
    jnz     .ret
    call    ev_to_cleanup
.ret:
    add     rsp, 8
    ret

; ev_do_countdown(): at 0 a camp's first wave starts, a caravan sets off
ev_do_countdown:
    sub     rsp, 8
    dec     dword [ev_timer]
    jnz     .ret
    cmp     dword [ev_kind], EVK_CARAVAN
    jae     .van
    mov     edi, EVS_WAVE
    call    ev_wave_begin
    jmp     .ret
.van:
    mov     dword [ev_state], EVS_TRAVEL
.ret:
    add     rsp, 8
    ret

; ev_do_break(): at 0 the next wave starts
ev_do_break:
    sub     rsp, 8
    dec     dword [ev_timer]
    jnz     .ret
    mov     edi, EVS_WAVE
    call    ev_wave_begin
.ret:
    add     rsp, 8
    ret

; ev_wave_cleared(): the wave / ambush is over: the next break, TRAVEL again, or the win
ev_wave_cleared:
    sub     rsp, 8
    cmp     dword [ev_state], EVS_AMBUSH
    je      .amb
    mov     eax, [ev_wave]
    cmp     eax, [ev_waves]
    jae     .win
    mov     dword [ev_state], EVS_BREAK
    mov     dword [ev_timer], EV_BREAK_STEPS
    jmp     .ret
.win:
    mov     edi, 1
    xor     esi, esi
    call    ev_end
    jmp     .ret
.amb:
    mov     dword [ev_state], EVS_TRAVEL
.ret:
    add     rsp, 8
    ret

; ev_do_wave(): WAVE / AMBUSH. Within the 300-step spawn window the wave is sized (retried every 60 steps while it
; comes to 0) and up to 2 attackers spawn per step; after it, no attacker alive clears it, and 7200 steps later the ones
; far from every player are removed
ev_do_wave:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    mov     eax, [ev_win_t]
    cmp     eax, EV_WINDOW
    jae     .closed
    mov     ecx, [ev_size]
    test    ecx, ecx
    jz      .open
    cmp     [ev_spawned], ecx
    jae     .closed
.open:
    cmp     dword [ev_size], 0
    jne     .spawn
    mov     eax, [ev_win_t]
    xor     edx, edx
    mov     ecx, 60
    div     ecx
    test    edx, edx
    jnz     .spawn
    movss   xmm0, [ev_ax]
    movss   xmm1, [ev_az]
    movss   xmm2, [k_64sq]
    call    ev_players_near
    mov     r12d, eax
    call    ev_free_slots
    mov     edx, eax
    mov     edi, [ev_wave]
    mov     esi, r12d
    call    ev_wave_size
    mov     [ev_size], eax
.spawn:
    mov     ebx, 2
.sp:
    mov     eax, [ev_size]
    cmp     [ev_spawned], eax
    jae     .tick
    mov     edi, [ev_spawned]
    xor     esi, esi
    mov     eax, [ev_wave]
    cmp     eax, [ev_waves]
    sete    sil
    call    ev_spawn_attacker
    test    eax, eax
    js      .tick
    inc     dword [ev_spawned]
    dec     ebx
    jnz     .sp
.tick:
    inc     dword [ev_win_t]
    jmp     .ret
.closed:
    call    ev_count_attackers
    test    eax, eax
    jnz     .alive
    call    ev_wave_cleared
    jmp     .ret
.alive:
    inc     dword [ev_after_t]
    cmp     dword [ev_after_t], EV_WAVE_LIMIT
    jb      .ret
    mov     eax, [ev_tick]
    xor     edx, edx
    mov     ecx, 60
    div     ecx
    test    edx, edx
    jnz     .ret
    mov     edi, 1
    call    ev_remove_attackers
.ret:
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ev_party_to(xmm0 x, xmm1 y, xmm2 z): the merchant and its guards (1.5 blocks to its sides) stand there
; rbx = the merchant, r12d = side counter, r13 = the mob; frame: [rsp] x, y, z
ev_party_to:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 16
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 8], xmm2
    call    ev_prot
    test    rax, rax
    jz      .ret
    mov     rbx, rax
    mov     rdi, rbx
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    call    ev_place
    xor     r12d, r12d
    lea     r13, [mobs]
    mov     r14d, MAX_MOBS
.l:
    cmp     r13, rbx
    je      .n
    cmp     dword [r13 + MOB.type], MOB_FOLK
    jne     .n
    mov     eax, [ev_key]
    cmp     [r13 + MOB.patrol], eax
    jne     .n
    inc     r12d
    mov     eax, r12d
    and     eax, 1
    lea     rcx, [k_side]
    movss   xmm2, [rcx + rax * 4 + 4]       ; +1.5 for an odd guard, -1.5 for an even one
    movss   xmm0, [ev_uz]
    mulss   xmm0, xmm2
    movss   xmm3, [rsp]
    subss   xmm3, xmm0
    movss   xmm0, [ev_ux]
    mulss   xmm0, xmm2
    movss   xmm4, [rsp + 8]
    addss   xmm4, xmm0
    movss   [r13 + MOB.home_x], xmm3
    movss   [r13 + MOB.home_z], xmm4
    mov     rdi, r13
    movaps  xmm0, xmm3
    movss   xmm1, [rsp + 4]
    movaps  xmm2, xmm4
    call    ev_place
.n:
    add     r13, MOB_size
    dec     r14d
    jnz     .l
.ret:
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ev_do_travel(): the caravan on its way. The merchant walks only while a player is within 24 blocks and no attacker lives;
; past the next ambush threshold the ambush starts; within 4 blocks of the destination the event is won; 120 blocked
; steps hop the party ahead (none found: lost)
; rbx = the merchant, r12d = players near; frame: [rsp] dirx, dirz, [rsp+8] hop cell, [rsp+16] progress
ev_do_travel:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 32
    call    ev_prot
    test    rax, rax
    jz      .ret
    mov     rbx, rax
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.z]
    movss   xmm2, [k_24sq]
    call    ev_players_near
    mov     r12d, eax
    xor     edx, edx
    test    r12d, r12d
    setz    dl
    mov     [ev_wait], edx
    test    r12d, r12d
    jz      .halt
    call    ev_count_attackers
    test    eax, eax
    jnz     .halt
    and     byte [rbx + MOB.fflags], ~FF_HALT
    jmp     .moved
.halt:
    or      byte [rbx + MOB.fflags], FF_HALT
.moved:
    mov     eax, [ev_wave]
    cmp     eax, [ev_waves]
    jae     .arrive
    movss   xmm0, [rbx + BODY.x]
    subss   xmm0, [ev_sx]
    mulss   xmm0, [ev_ux]
    movss   xmm1, [rbx + BODY.z]
    subss   xmm1, [ev_sz]
    mulss   xmm1, [ev_uz]
    addss   xmm0, xmm1
    divss   xmm0, [ev_len]
    mov     ecx, [ev_kind]
    sub     ecx, EVK_CARAVAN
    lea     ecx, [rcx + rcx * 2]
    add     ecx, eax
    lea     rdx, [k_thresh]
    comiss  xmm0, [rdx + rcx * 4]
    jb      .arrive
    or      byte [rbx + MOB.fflags], FF_HALT
    mov     dword [ev_wait], 0
    mov     edi, EVS_AMBUSH
    call    ev_wave_begin
    jmp     .ret
.arrive:
    movss   xmm0, [ev_dx]
    subss   xmm0, [rbx + BODY.x]
    movss   xmm1, [ev_dz]
    subss   xmm1, [rbx + BODY.z]
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [k_16]
    ja      .stuck
    mov     edi, 1
    xor     esi, esi
    call    ev_end
    jmp     .ret
.stuck:
    test    byte [rbx + MOB.fflags], FF_HALT
    jnz     .ret
    cmp     dword [rbx + MOB.ai_timer], EV_STUCK
    jb      .ret
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movaps  xmm2, xmm0
    mulss   xmm2, xmm2
    movaps  xmm3, xmm1
    mulss   xmm3, xmm3
    addss   xmm2, xmm3
    sqrtss  xmm2, xmm2
    divss   xmm0, xmm2
    divss   xmm1, xmm2
    movaps  xmm2, xmm0
    movaps  xmm3, xmm1
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.z]
    lea     rdi, [rsp + 8]
    call    evs_hop_cell
    test    eax, eax
    js      .blocked
    inc     eax
    cvtsi2ss xmm1, eax
    mov     eax, [rsp + 8]
    cvtsi2ss xmm0, eax
    addss   xmm0, [k_half]
    mov     eax, [rsp + 12]
    cvtsi2ss xmm2, eax
    addss   xmm2, [k_half]
    call    ev_party_to
    mov     dword [rbx + MOB.ai_timer], 0
    jmp     .ret
.blocked:
    xor     edi, edi
    mov     esi, EVL_BLOCKED
    call    ev_end
.ret:
    add     rsp, 32
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ev_do_cleanup(): every 60 steps the event's mobs with no player within 24 blocks go, and the tent once no player is within
; 48; then no event. After 18000 steps the rest is removed whatever is near, and the tent forgotten
; r12d = the key, r14d = what is left, rbx = the mob, r13d = slots left
ev_do_cleanup:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 16
    inc     dword [ev_clean_t]
    mov     r12d, [ev_key]
    cmp     dword [ev_clean_t], EV_CLEAN_STEPS
    jae     .force
    mov     eax, [ev_tick]
    xor     edx, edx
    mov     ecx, 60
    div     ecx
    test    edx, edx
    jnz     .ret
    xor     r14d, r14d
    lea     rbx, [mobs]
    mov     r13d, MAX_MOBS
.l:
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .n
    mov     eax, [rbx + MOB.patrol]
    and     eax, ~EV_KEY_ATTACK
    cmp     eax, r12d
    jne     .n
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.z]
    movss   xmm2, [k_24sq]
    call    ev_players_near
    test    eax, eax
    jz      .kill
    inc     r14d
    jmp     .n
.kill:
    mov     dword [rbx + MOB.type], MOB_NONE
.n:
    add     rbx, MOB_size
    dec     r13d
    jnz     .l
    call    evs_tent_placed
    test    eax, eax
    jz      .tent_done
    movss   xmm0, [ev_ax]
    movss   xmm1, [ev_az]
    movss   xmm2, [k_48sq]
    call    ev_players_near
    test    eax, eax
    jnz     .tent_left
    call    evs_remove_tent
    jmp     .tent_done
.tent_left:
    inc     r14d
.tent_done:
    test    r14d, r14d
    jnz     .ret
    call    ev_idle
    jmp     .ret
.force:
    lea     rbx, [mobs]
    mov     r13d, MAX_MOBS
.f:
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .fn
    mov     eax, [rbx + MOB.patrol]
    and     eax, ~EV_KEY_ATTACK
    cmp     eax, r12d
    jne     .fn
    mov     dword [rbx + MOB.type], MOB_NONE
.fn:
    add     rbx, MOB_size
    dec     r13d
    jnz     .f
    call    evs_forget_tent
    call    ev_idle
.ret:
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ev_state_step(): the protected NPC's check, the anchor, the abandon counter, then the state's handler
; rbx = the protected NPC
ev_state_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     eax, [ev_state]
    test    eax, eax
    jz      .ret
    cmp     eax, EVS_CLEANUP
    je      .cleanup
    call    ev_prot
    mov     rbx, rax
    test    rbx, rbx
    jnz     .alive
    cmp     dword [ev_state], EVS_OFFERED
    jne     .died
    call    ev_to_cleanup
    jmp     .ret
.died:
    xor     edi, edi
    mov     esi, EVL_DIED
    call    ev_end
    jmp     .ret
.alive:
    cmp     dword [ev_kind], EVK_CARAVAN
    jb      .anch
    mov     eax, [rbx + BODY.x]
    mov     [ev_ax], eax
    mov     eax, [rbx + BODY.z]
    mov     [ev_az], eax
.anch:
    cmp     dword [ev_state], EVS_OFFERED
    je      .offered
    movss   xmm0, [ev_ax]
    movss   xmm1, [ev_az]
    movss   xmm2, [k_96sq]
    call    ev_players_near
    test    eax, eax
    jz      .away
    mov     dword [ev_aband], 0
    jmp     .dispatch
.away:
    inc     dword [ev_aband]
    cmp     dword [ev_aband], EV_ABANDON_STEPS
    jb      .dispatch
    xor     edi, edi
    mov     esi, EVL_ABANDONED
    call    ev_end
    jmp     .ret
.dispatch:
    mov     eax, [ev_state]
    cmp     eax, EVS_COUNTDOWN
    je      .count
    cmp     eax, EVS_WAVE
    je      .wave
    cmp     eax, EVS_AMBUSH
    je      .wave
    cmp     eax, EVS_BREAK
    je      .break
    cmp     eax, EVS_TRAVEL
    je      .travel
    jmp     .ret
.offered:
    call    ev_do_offered
    jmp     .ret
.count:
    call    ev_do_countdown
    jmp     .ret
.wave:
    call    ev_do_wave
    jmp     .ret
.break:
    call    ev_do_break
    jmp     .ret
.travel:
    call    ev_do_travel
    jmp     .ret
.cleanup:
    call    ev_do_cleanup
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ev_cd_tick(): the strike cooldowns run down
ev_cd_tick:
    lea     rax, [ev_strike_cd]
    mov     ecx, MAX_MOBS
.l:
    mov     edx, [rax]
    test    edx, edx
    jle     .n
    dec     edx
    mov     [rax], edx
.n:
    add     rax, 4
    dec     ecx
    jnz     .l
    ret

; ev_maint(): every 60 steps nobody offers an event but the offered NPC; every 20 steps (COUNTDOWN..AMBUSH) the attackers head
; for the protected NPC (dest, and home for a raider) and are removed beyond 64 blocks of the anchor, a caravan's guards follow
; the merchant (home), and every 60 steps a raider's provocation is refreshed
; rbx = the mob, r12d = do20, r13d = do60, r14d = slots left, r15d = the slot; frame: [rsp] target x, z, [rsp+8] has target, [rsp+12] attack key
ev_maint:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    cmp     dword [ev_state], EVS_NONE
    je      .ret
    mov     eax, [ev_tick]
    xor     edx, edx
    mov     ecx, 60
    div     ecx
    xor     r13d, r13d
    test    edx, edx
    sete    r13b
    mov     eax, [ev_tick]
    xor     edx, edx
    mov     ecx, 20
    div     ecx
    xor     r12d, r12d
    test    edx, edx
    sete    r12b
    mov     eax, [ev_state]
    sub     eax, EVS_COUNTDOWN
    cmp     eax, EVS_AMBUSH - EVS_COUNTDOWN
    jbe     .st
    xor     r12d, r12d
.st:
    mov     eax, r12d
    or      eax, r13d
    jz      .ret
    mov     eax, [ev_key]
    or      eax, EV_KEY_ATTACK
    mov     [rsp + 12], eax
    mov     dword [rsp + 8], 0
    call    ev_prot
    test    rax, rax
    jz      .scan
    mov     ecx, [rax + BODY.x]
    mov     [rsp], ecx
    mov     ecx, [rax + BODY.z]
    mov     [rsp + 4], ecx
    mov     dword [rsp + 8], 1
.scan:
    lea     rbx, [mobs]
    mov     r14d, MAX_MOBS
    xor     r15d, r15d
.l:
    mov     eax, [rbx + MOB.type]
    test    eax, eax
    jz      .n
    test    r13d, r13d
    jz      .attack
    cmp     eax, MOB_FOLK
    jne     .attack
    test    byte [rbx + MOB.fflags], FF_HELP
    jz      .attack
    cmp     dword [ev_state], EVS_OFFERED
    jne     .strip
    cmp     r15d, [ev_protect]
    je      .attack
.strip:
    and     byte [rbx + MOB.fflags], ~FF_HELP
.attack:
    test    r12d, r12d
    jz      .refresh
    mov     eax, [rbx + MOB.patrol]
    cmp     eax, [rsp + 12]
    jne     .guard
    movss   xmm0, [rbx + BODY.x]
    subss   xmm0, [ev_ax]
    mulss   xmm0, xmm0
    movss   xmm1, [rbx + BODY.z]
    subss   xmm1, [ev_az]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [k_64sq]
    jbe     .keep
    mov     dword [rbx + MOB.type], MOB_NONE
    jmp     .n
.keep:
    cmp     dword [rsp + 8], 0
    je      .refresh
    mov     eax, [rsp]
    mov     [rbx + MOB.dest_x], eax
    mov     eax, [rsp + 4]
    mov     [rbx + MOB.dest_z], eax
    cmp     dword [rbx + MOB.type], MOB_FOLK
    jne     .refresh
    mov     eax, [rsp]
    mov     [rbx + MOB.home_x], eax
    mov     eax, [rsp + 4]
    mov     [rbx + MOB.home_z], eax
    jmp     .refresh
.guard:
    cmp     dword [ev_kind], EVK_CARAVAN
    jb      .refresh
    cmp     dword [rsp + 8], 0
    je      .refresh
    cmp     dword [rbx + MOB.type], MOB_FOLK
    jne     .refresh
    cmp     byte [rbx + MOB.role], ROLE_GUARD
    jne     .refresh
    mov     eax, [ev_key]
    cmp     [rbx + MOB.patrol], eax
    jne     .refresh
    mov     eax, [rsp]
    mov     [rbx + MOB.home_x], eax
    mov     eax, [rsp + 4]
    mov     [rbx + MOB.home_z], eax
.refresh:
    test    r13d, r13d
    jz      .n
    cmp     dword [rbx + MOB.type], MOB_FOLK
    jne     .n
    mov     eax, [rbx + MOB.patrol]
    cmp     eax, [rsp + 12]
    jne     .n
    mov     dword [rbx + MOB.provoked], EV_PROVOKED
.n:
    add     rbx, MOB_size
    inc     r15d
    dec     r14d
    jnz     .l
.ret:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ev_strikes(): an attacker monster within 1.8 blocks (and 1.5 in height) of a defender folk strikes it (folk_strike_mob, the
; monster's base: zombie 4, spider 3, skeleton 2), then waits 60 steps
; rbx = the monster, r12d = its slot, r13 = the defender, r14d = base, r15d = the defender's slot; frame: [rsp] slots left
ev_strikes:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    cmp     dword [ev_state], EVS_NONE
    je      .ret
    lea     rbx, [mobs]
    xor     r12d, r12d
.m:
    mov     eax, [rbx + MOB.type]
    cmp     eax, 5
    ja      .mn
    lea     rcx, [ev_strike_base]
    movzx   r14d, byte [rcx + rax]
    test    r14d, r14d
    jz      .mn
    mov     eax, [ev_key]
    or      eax, EV_KEY_ATTACK
    cmp     [rbx + MOB.patrol], eax
    jne     .mn
    cmp     dword [rbx + MOB.health], 0
    jle     .mn
    cmp     dword [ev_strike_cd + r12 * 4], 0
    jg      .mn
    lea     r13, [mobs]
    xor     r15d, r15d
.d:
    cmp     dword [r13 + MOB.type], MOB_FOLK
    jne     .dn
    mov     eax, [ev_key]
    cmp     [r13 + MOB.patrol], eax
    jne     .dn
    cmp     dword [r13 + MOB.health], 0
    jle     .dn
    movss   xmm0, [r13 + BODY.y]
    subss   xmm0, [rbx + BODY.y]
    andps   xmm0, [k_abs]
    comiss  xmm0, [k_1_5]
    jae     .dn
    movss   xmm0, [r13 + BODY.x]
    movss   xmm1, [r13 + BODY.z]
    mov     rdi, rbx
    call    ev_body_d2
    comiss  xmm0, [k_1_8_2]
    ja      .dn
    mov     rdi, rbx
    mov     esi, r15d
    mov     edx, r14d
    call    folk_strike_mob
    mov     dword [ev_strike_cd + r12 * 4], EV_STRIKE_CD
    jmp     .mn
.dn:
    add     r13, MOB_size
    inc     r15d
    cmp     r15d, MAX_MOBS
    jb      .d
.mn:
    add     rbx, MOB_size
    inc     r12d
    cmp     r12d, MAX_MOBS
    jb      .m
.ret:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; events_step(): the host's (or the offline game's) event, once per simulation step. Order: strike cooldowns, the spontaneous
; offers, the flag refresh, the state, the 20/60-step upkeep, the monsters' blows, the EVHUD, its send
events_step:
    sub     rsp, 8
    cmp     byte [net_role], NET_ROLE_GUEST
    je      .ret
    inc     dword [ev_tick]
    call    ev_cd_tick
    call    ev_spontaneous
    call    ev_refresh_tick
    call    ev_state_step
    call    ev_maint
    call    ev_strikes
    call    ev_hud_build
    call    ev_net_sync
.ret:
    add     rsp, 8
    ret

; ==== debug =====================================================================================================

; events_skip() -> eax 1 when something moved on: WAVE / AMBUSH lose their attackers, COUNTDOWN / BREAK run out their
; timer, TRAVEL hops the party to just past the next threshold (or 6 blocks short of the destination)
; frame: [rsp] progress length / x, [rsp+4] y, [rsp+8] z, [rsp+12] hop cell
events_skip:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 32
    mov     eax, [ev_state]
    cmp     eax, EVS_WAVE
    je      .wave
    cmp     eax, EVS_AMBUSH
    je      .wave
    cmp     eax, EVS_COUNTDOWN
    je      .timer
    cmp     eax, EVS_BREAK
    je      .timer
    cmp     eax, EVS_TRAVEL
    je      .travel
    jmp     .no
.wave:
    xor     edi, edi
    call    ev_remove_attackers
    mov     dword [ev_win_t], EV_WINDOW
    jmp     .yes
.timer:
    mov     dword [ev_timer], 1
    jmp     .yes
.travel:
    call    ev_prot
    test    rax, rax
    jz      .no
    mov     eax, [ev_wave]
    movss   xmm0, [ev_len]
    subss   xmm0, [k_6]
    cmp     eax, [ev_waves]
    jae     .at
    mov     ecx, [ev_kind]
    sub     ecx, EVK_CARAVAN
    lea     ecx, [rcx + rcx * 2]
    add     ecx, eax
    lea     rdx, [k_thresh]
    movss   xmm0, [rdx + rcx * 4]
    mulss   xmm0, [ev_len]
    addss   xmm0, [k_one]
.at:
    movss   xmm1, [ev_ux]
    mulss   xmm1, xmm0
    addss   xmm1, [ev_sx]
    movss   [rsp + 16], xmm1                ; x
    mulss   xmm0, [ev_uz]
    addss   xmm0, [ev_sz]
    movss   [rsp + 20], xmm0                ; z
    roundss xmm1, xmm1, 9
    cvttss2si edi, xmm1
    roundss xmm0, xmm0, 9
    cvttss2si esi, xmm0
    call    evs_ground
    test    eax, eax
    jns     .place
    movss   xmm0, [rsp + 16]
    movss   xmm1, [rsp + 20]
    movss   xmm2, [ev_ux]
    movss   xmm3, [ev_uz]
    lea     rdi, [rsp + 8]
    call    evs_hop_cell
    test    eax, eax
    js      .no
    mov     ecx, [rsp + 8]
    cvtsi2ss xmm0, ecx
    addss   xmm0, [k_half]
    movss   [rsp + 16], xmm0
    mov     ecx, [rsp + 12]
    cvtsi2ss xmm0, ecx
    addss   xmm0, [k_half]
    movss   [rsp + 20], xmm0
.place:
    inc     eax
    cvtsi2ss xmm1, eax
    movss   xmm0, [rsp + 16]
    movss   xmm2, [rsp + 20]
    call    ev_party_to
.yes:
    mov     eax, 1
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    add     rsp, 32
    pop     r12
    pop     rbx
    pop     rbp
    ret

; events_finish(edi win) -> eax 1 when an event in COUNTDOWN..AMBUSH ended: won now (1), or lost as abandoned (0)
events_finish:
    sub     rsp, 8
    mov     eax, [ev_state]
    sub     eax, EVS_COUNTDOWN
    cmp     eax, EVS_AMBUSH - EVS_COUNTDOWN
    ja      .no
    xor     esi, esi
    test    edi, edi
    jnz     .go
    mov     esi, EVL_ABANDONED
.go:
    call    ev_end
    mov     eax, 1
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    add     rsp, 8
    ret

section .rodata
align 16
k_abs: dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF
