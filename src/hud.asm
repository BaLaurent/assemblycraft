; hud.asm - in-world overlay on top of the ui.asm toolkit: hurt flash, stealth tint, health bars,
; levels, status pips and name tags pinned to mobs, damage numbers, crosshair, hotbar, XP bar and
; level, ten hearts with the health number / armor / food, mana and stamina bars, player status pips,
; ability bar, held-item name, firearm ammunition and reload bar, boss bar, quest tracker, banner and
; the F3 debug lines. In a multiplayer session (net_role != OFF) also the other players' name plates
; (peerrender.asm), the chat log at the bottom left, the player list while Tab is held and a Net line
; on F3. GUI units; hud_draw runs after ui_begin. The hotbar sits at x0 = ui_w/2 - 91,
; y0 = ui_h - 22. The grimoire look (theme.inc): a leather hotbar with parchment cells and a gold
; selection, framed bars, carved ability runes with paper key tabs, a ribbon for the boss name and the
; banner, a pinned paper note for the quest.
%include "common.inc"
%include "theme.inc"
%include "gl.inc"
default rel

%define C_CHEAT         RGBA(255, 85, 85, 255)  ; the cheater mark: bright red on the dark world
%define CHAT_LIFE_MS    10000           ; a chat line shows this long (ms) ...
%define CHAT_FADE_MS    2000            ; ... and fades out over the last of it
%define CHAT_BASE       72              ; the newest chat line is drawn this far over the bottom edge
%define PL_W            240             ; the player list: panel width, top and row pitch
%define PL_Y            28
%define PL_ROW          11

global hud_draw, hud_dt, hud_banner, hud_banner_paint, hud_heart_level, hud_ability_pos
global hud_bubble_tiles, banner_text, hud_biome_name, bar_px

extern ui_w, ui_h, ui_rect, ui_frame, ui_text, ui_text_width, ui_text_centered
extern ui_item_icon, ui_icon9, ui_tile_icon, ui_text_ink, ui_nine, ui_nine_tint, ui_ribbon
extern game_mode, game_time, game_target, game_has_target
extern app_state, app_show_debug, app_fps
extern surv, surv_max_health, inv, inv_sel, player, mobs, mob_count_kind, mob_is_hostile
extern sky_brightness, world_get, settings, key_name, world_to_ui, dmgnum_draw, light_get
extern item_names, item_durability, armor_effective
extern gun_magazine, gun_ammo, gun_reload, gun_reload_total, inv_count
extern str_append, str_copy, i32_to_str, f32_to_str, fx_flash, atan2_deg
extern rpg_state, rpg_level, rpg_xp_need, rpg_stat, rpg_bar_ability, rpg_keystones
extern rpg_title, rpg_ability_info, rpg_ability_tile, quests_current, quests_progress
extern combat_mana, combat_stamina, combat_max_mana, combat_max_stamina, combat_stealth_t
extern abilities_cd, abilities_cd_total, structures_nearest
extern game_heavy_s, combat_burn_t, combat_chill_t, combat_poison_t
extern item_gear, gear_name, gear_rarity, gear_rarity_color, rpg_points, rpg_attr_points
extern mob_affix_name
extern folk_name, faction_tier_color, faction_standing, faction_names, faction_short
extern sleep_fade, world_biome_at, stream_stats, world_origin_x, world_origin_z
extern debug_is_cheater
extern frame_input, net_role, net_self, net_peers, net_cfg_name, net_room_code
extern net_ep, net_ep_rtt_ms, net_ep_is_relay, net_chat_line
extern net_stat_block_rx, net_stat_block_tx, peers_hud, peer_slot_rgba


section .rodata
align 4
f_one:      dd 1.0
f_two:      dd 2.0
f_255:      dd 255.0
f_200:      dd 200.0
f_100:      dd 100.0
f_25:       dd 25.0                     ; the stamina bar turns red below this
f_24sq:     dd 576.0                    ; health bars: hostile mobs within 24 blocks
f_10sq:     dd 100.0                    ; name plates: folk within 10 blocks
f_48sq:     dd 2304.0                   ; boss bar: a boss within 48 blocks
f_bar_up:   dd 0.35                     ; a mob's health bar floats this far over its head
f_tag_up:   dd 0.5                      ; and its name tag this far
f_22_5:     dd 22.5
f_45:       dd 45.0
f_360:      dd 360.0
f_2_5:      dd 2.5                      ; seconds a banner stays
f_half:     dd 0.5                      ; seconds LMB must be held for the gold heavy-attack crosshair
s_level_l:  db "Level ", 0
s_hint_l:   db " (", 0
; mob status pips under the health bar: MOB timer offset, colour
pip_tab:
    dd MOB.burn_t, RGBA(255, 120, 30, 255)
    dd MOB.chill_t, RGBA(120, 190, 255, 255)
    dd MOB.shock_t, RGBA(255, 240, 80, 255)
    dd MOB.poison_t, RGBA(110, 220, 70, 255)
    dd MOB.bleed_t, RGBA(210, 30, 30, 255)
f_feet_eps: dd 0.001                    ; the feet cell: a body resting on a floor may sit a hair under it
s_dbg_title: db "AssemblyCraft 0.11.0  ", 0
s_cheater:  db "CHEATER", 0
s_cheat_mark: db "[C]", 0
s_dbg_fps:  db " fps", 0
s_xyz:      db "XYZ: ", 0
s_sep:      db " / ", 0
s_facing:   db "Facing: yaw ", 0
s_pitch:    db " pitch ", 0
s_target:   db "Target: ", 0
s_none:     db "Target: none", 0
s_at:       db " at ", 0
s_space:    db " ", 0
s_gap:      db "  ", 0
s_mode:     db "Mode: ", 0
s_survival: db "Survival", 0
s_creative: db "Creative", 0
s_day:      db "  Day ", 0
s_colon:    db ":", 0
s_mobs:     db "Mobs: ", 0
s_hostile:  db " hostile, ", 0
s_passive:  db " passive", 0
s_light:    db "Light: sky ", 0
s_light_b:  db " block ", 0
s_light_d:  db " (", 0
s_light_e:  db "%)", 0
s_health:   db "Health ", 0
s_food:     db "  Food ", 0
s_sat:      db "/20  Sat ", 0
s_slash:    db "/", 0
s_comma:    db ",", 0
s_archetype: db "Archetype: ", 0
s_lv:       db " Lv ", 0
s_xp:       db "  XP ", 0
s_xp_max:   db "  XP max", 0
s_sites:    db "Sites: V ", 0
s_site_d:   db "  D ", 0
s_site_c:   db "  C ", 0
s_site_none: db "none", 0
s_ammo_l:   db "  [", 0
s_ammo_r:   db "]", 0
s_ammo_inf: db "  [inf]", 0
s_quest:    db "Quest: ", 0
s_metres:   db "m", 0
s_boss:     db "The Fallen King", 0
headings:   db "N", 0, 0, "NE", 0, "E", 0, 0, "SE", 0, "S", 0, 0, "SW", 0, "W", 0, 0, "NW", 0   ; 3 bytes each
s_biome:    db "Biome: ", 0
s_unknown:  db "unknown", 0
s_columns:  db "Columns: ", 0
s_col_lit:  db " lit ", 0
s_col_pend: db " pending ", 0
s_col_pool: db " pool ", 0
%defstr POOL_CHUNKS_STR POOL_CHUNKS
s_col_max:  db "/", POOL_CHUNKS_STR, 0
s_camp:     db "Camp: ", 0
s_asleep:   db " (asleep)", 0
s_standing: db "Standing:", 0
s_net_host: db "Net: host ", 0
s_net_peers: db " peers ", 0
s_net_rx:   db " rx ", 0
s_net_tx:   db " tx ", 0
s_net_guest: db "Net: guest slot ", 0
s_net_rtt:  db " rtt ", 0
s_net_ms:   db " ms ", 0
s_net_direct: db "direct", 0
s_net_relay: db "relay", 0
s_players:  db "Players", 0
s_host_tag: db "(host)", 0
s_lvp:      db "Lv ", 0
s_ms:       db " ms", 0
s_dash:     db "-", 0
s_b_ocean:  db "Ocean", 0
s_b_plains: db "Plains", 0
s_b_forest: db "Forest", 0
s_b_desert: db "Desert", 0
s_b_snow:   db "Snow", 0
s_b_swamp:  db "Swamp", 0
s_b_mount:  db "Mountains", 0
s_b_river:  db "River", 0
s_b_taiga:  db "Snowy Taiga", 0
s_b_savanna: db "Savanna", 0
s_b_shore:  db "Stony Shore", 0
s_b_birch:  db "Birch Forest", 0
align 8
biome_names:   dq s_b_ocean, s_b_plains, s_b_forest, s_b_desert, s_b_snow, s_b_swamp, s_b_mount, s_b_river
               dq s_b_taiga, s_b_savanna, s_b_shore, s_b_birch
%if $ - biome_names != NUM_BIOMES * 8
%error "hud.asm: biome_names needs one name per BIOME_*"
%endif

section .data
align 4
last_sel:   dd -1                       ; hotbar slot and held id of the last frame
last_id:    dd -1

section .bss
alignb 4
hud_dt:     resd 1                      ; frame time in seconds, written by the app before hud_draw
name_timer: resd 1                      ; seconds left to show the held item's name
banner_timer: resd 1                    ; seconds left to show the banner
banner_rgba: resd 1
banner_text: resb 64
dbg_buf:    resb 128
quest_buf:  resb 128
plate_buf:  resb 48                     ; a folk's name plate text

section .text

; hud_draw(): everything the player sees on top of the world
; ebx = x0, r12d = y0, r13d = y of the held item's name, r14d = y of the top of the left stack over the
; hotbar (the hearts, mana bar and armor row; the XP bar in creative)
hud_draw:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14                         ; five pushes and the return address: rsp stays 16-aligned
    mov     ebx, [ui_w]
    shr     ebx, 1
    sub     ebx, 91                     ; x0
    mov     r12d, [ui_h]
    sub     r12d, 22                    ; y0
    call    hud_flash
    call    hud_blast_flash
    call    hud_stealth
    cmp     dword [app_state], ST_PLAYING ; health bars, name tags and numbers stay out of screens
    jne     .no_overlays
    call    hud_mobs
    call    peers_hud
    call    dmgnum_draw
.no_overlays:
    call    hud_sleep_fade
    call    hud_crosshair
    mov     edi, ebx
    mov     esi, r12d
    call    hud_hotbar
    lea     r13d, [r12 - 15]            ; the held name sits over the hotbar; clear of the XP bar's frame
    lea     r14d, [r12 - 6]             ; without hearts the XP bar's frame is the top of the stack
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .progress
    mov     edi, ebx
    mov     esi, r12d
    call    hud_status_pips
    mov     edi, ebx
    mov     esi, r12d
    call    hud_bubbles
    mov     edi, ebx
    mov     esi, r12d
    call    hud_bars                    ; eax = top of the left stack
    mov     r14d, eax
    lea     edx, [r12 - 21]
    cmp     eax, edx
    cmovg   eax, edx                    ; or of the stamina bar, whichever is higher
    lea     r13d, [rax - 12]            ; over the bars in survival
.progress:
    mov     edi, ebx
    mov     esi, r12d
    call    hud_xp
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r14d
    call    hud_abilities               ; eax = top of its key labels when it is above the stack
    lea     ecx, [rax - 12]
    cmp     r13d, ecx
    cmovg   r13d, ecx                   ; the held name clears the ability bar
    mov     edi, r13d
    call    hud_held_name
    mov     edi, ebx
    mov     esi, r12d
    call    hud_gun
    call    hud_boss
    mov     edi, 4                      ; quest tracker: top left, under the boss bar when it is up,
    test    eax, eax
    jz      .tracker_y
    mov     edi, 26
.tracker_y:
    cmp     dword [app_show_debug], 0
    je      .tracker
    mov     edi, 142                    ; or under the F3 lines (one more when the CHEATER line is up)
    call    debug_is_cheater            ; (leaf: only eax changes)
    lea     ecx, [rdi + 10]
    test    eax, eax
    cmovnz  edi, ecx
    lea     ecx, [rdi + 10]
    cmp     byte [net_role], NET_ROLE_OFF
    cmovne  edi, ecx                    ; and one more for the Net line
.tracker:
    call    hud_quest
    call    hud_banner_draw
    cmp     byte [net_role], NET_ROLE_OFF
    je      .no_net
    call    hud_chat
    call    hud_players
.no_net:
    cmp     dword [app_show_debug], 0
    je      .ret
    call    hud_debug
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; hud_blast_flash(): a warm full-screen flash near an explosion, alpha 200 * fx_flash
hud_blast_flash:
    sub     rsp, 8
    movss   xmm0, [fx_flash]
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jbe     .ret
    minss   xmm0, [f_one]
    mulss   xmm0, [f_200]
    cvttss2si eax, xmm0
    shl     eax, 24
    or      eax, RGBA(255, 210, 150, 0)
    mov     r8d, eax
    xor     edi, edi
    xor     esi, esi
    mov     edx, [ui_w]
    mov     ecx, [ui_h]
    call    ui_rect
.ret:
    add     rsp, 8
    ret

; hud_flash(): red full-screen flash while the player is hurt (survival)
hud_flash:
    sub     rsp, 8
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .ret
    mov     eax, [surv + SURVIVAL.hurt_flash]
    test    eax, eax
    jle     .ret
    imul    eax, eax, 90
    xor     edx, edx
    mov     ecx, 20
    div     ecx                         ; alpha = hurt_flash * 90 / 20
    shl     eax, 24
    or      eax, 255                    ; RGBA(255, 0, 0, alpha)
    mov     r8d, eax
    xor     edi, edi
    xor     esi, esi
    mov     edx, [ui_w]
    mov     ecx, [ui_h]
    call    ui_rect
.ret:
    add     rsp, 8
    ret

%macro CROSS_COLOUR 0                   ; r8d = white, or gold while r13d is set
    mov     r8d, WHITE
    mov     eax, RGBA(255, 200, 60, 255)
    test    r13d, r13d
    cmovnz  r8d, eax
%endmacro

; hud_crosshair(): a colour-inverting cross at the screen centre while playing; a plain gold one
; once the left button has been held long enough for a heavy attack (game_heavy_s >= 0.5)
; ebx = cx, r12d = cy, r13d = 1 for the gold cross
hud_crosshair:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    cmp     dword [app_state], ST_PLAYING
    jne     .ret
    mov     ebx, [ui_w]
    shr     ebx, 1                      ; cx
    mov     r12d, [ui_h]
    shr     r12d, 1                     ; cy
    xor     r13d, r13d
    movss   xmm0, [game_heavy_s]
    comiss  xmm0, [f_half]
    jb      .invert
    mov     r13d, 1
    jmp     .draw
.invert:
    mov     edi, GL_ONE_MINUS_DST_COLOR
    mov     esi, GL_ZERO
    call    glBlendFunc
.draw:
    lea     edi, [rbx - 5]
    mov     esi, r12d
    mov     edx, 11
    mov     ecx, 1
    CROSS_COLOUR
    call    ui_rect
    mov     edi, ebx
    lea     esi, [r12 - 5]
    mov     edx, 1
    mov     ecx, 5
    CROSS_COLOUR
    call    ui_rect
    mov     edi, ebx
    lea     esi, [r12 + 1]
    mov     edx, 1
    mov     ecx, 5
    CROSS_COLOUR
    call    ui_rect
    test    r13d, r13d
    jnz     .ret
    mov     edi, GL_SRC_ALPHA
    mov     esi, GL_ONE_MINUS_SRC_ALPHA
    call    glBlendFunc
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; hud_durability(rdi stack, esi x, edx y): damage bar of a tool at the slot's icon (x, y)
hud_durability:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8                      ; [rsp] filled width
    movzx   eax, byte [rdi + ITEMSTACK.id]
    cmp     eax, NUM_ITEMS
    jae     .ret
    movzx   ecx, word [item_durability + rax*2]
    movzx   r8d, word [rdi + ITEMSTACK.dmg]
    test    ecx, ecx
    jz      .ret
    test    r8d, r8d
    jz      .ret
    cmp     r8d, ecx
    cmova   r8d, ecx                    ; damage never exceeds the durability
    lea     ebx, [rsi + 2]              ; bar x
    lea     r12d, [rdx + 14]            ; bar y
    mov     eax, ecx
    sub     eax, r8d
    imul    eax, 14
    xor     edx, edx
    div     ecx
    mov     [rsp], eax                  ; width = 14 * (dur - dmg) / dur
    mov     eax, r8d
    imul    eax, 255
    xor     edx, edx
    div     ecx
    mov     r13d, 255
    sub     r13d, eax
    shl     r13d, 8
    or      r13d, eax
    or      r13d, 0xFF000000            ; RGBA(255 * dmg / dur, 255 - that, 0, 255)
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, 14
    mov     ecx, 2
    mov     r8d, RGBA(0, 0, 0, 255)
    call    ui_rect
    mov     edx, [rsp]
    test    edx, edx
    jz      .ret
    mov     edi, ebx
    mov     esi, r12d
    mov     ecx, 2
    mov     r8d, r13d
    call    ui_rect
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; hud_hotbar(edi x0, esi y0): the leather backing, the nine slot cells with their items, the selection
; r12d = x0, r13d = y0, ebx = slot, r14 = stack, r15d = icon x; [rsp] count text
hud_hotbar:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     r12d, edi
    mov     r13d, esi
    mov     edi, NINE_LEATHER
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, 182
    mov     r8d, 22
    call    ui_nine
    xor     ebx, ebx
.slot:
    imul    r15d, ebx, 20
    lea     r15d, [r15 + r12 + 3]       ; icon x = x0 + 3 + 20 * slot
    mov     edi, NINE_SLOT              ; the cell is 18 x 18, one left of and one over the icon
    lea     esi, [r15 - 1]
    lea     edx, [r13 + 2]
    mov     ecx, 18
    mov     r8d, 18
    call    ui_nine
    lea     r14, [inv + rbx*4]
    cmp     byte [r14 + ITEMSTACK.count], 0
    je      .next
    movzx   edi, byte [r14 + ITEMSTACK.id]
    mov     esi, r15d
    lea     edx, [r13 + 3]
    mov     ecx, 16
    call    ui_item_icon
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .next
    mov     rdi, r14
    mov     esi, r15d
    lea     edx, [r13 + 3]
    call    hud_durability
    movzx   edi, byte [r14 + ITEMSTACK.count]
    cmp     edi, 1
    jbe     .next
    mov     rsi, rsp
    call    i32_to_str
    mov     byte [rax], 0
    mov     rdi, rsp
    mov     esi, 1
    call    ui_text_width
    lea     esi, [r15 + 17]
    sub     esi, eax                    ; right-aligned, ending at icon x + 17
    mov     rdi, rsp
    lea     edx, [r13 + 12]
    mov     ecx, WHITE
    mov     r8d, 1
    call    ui_text
.next:
    inc     ebx
    cmp     ebx, HOTBAR_SLOTS
    jb      .slot
    imul    esi, [inv_sel], 20
    add     esi, r12d
    mov     edi, NINE_SELECT
    mov     edx, r13d
    mov     ecx, 22
    mov     r8d, 22
    call    ui_nine
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; bar_tile(edi value, esi full tile) -> eax tile: full for >= 2, half for 1, else empty
bar_tile:
    mov     eax, esi
    cmp     edi, 2
    jge     .ret
    inc     eax
    cmp     edi, 1
    je      .ret
    inc     eax
.ret:
    ret

; hud_heart_level(edi i 0..9, esi health, edx max health) -> eax 2 full, 1 half, 0 empty: heart i is
; full when health >= (i + 1) * max / 10 and half when health >= (i + 0.5) * max / 10
hud_heart_level:
    lea     eax, [rdi + 1]
    imul    eax, edx
    imul    ecx, esi, 10
    cmp     ecx, eax
    jge     .full
    lea     eax, [rdi + rdi + 1]
    imul    eax, edx
    imul    ecx, esi, 20
    cmp     ecx, eax
    jge     .half
    xor     eax, eax
    ret
.half:
    mov     eax, 1
    ret
.full:
    mov     eax, 2
    ret

; hud_bars(edi x0, esi y0) -> eax y of the top of the left stack
; Ten hearts at the left (each full, half or empty by its tenth of the maximum health) with the
; "health/max" number right-aligned just left of them, food icons at the right, then stacked over the
; hearts the mana bar (when the character has mana) and the armor row (worn armor plus the skill-web
; bonus); the stamina bar sits over the food.
; r12d = x0, r13d = y0, ebx = icon, r15d = top of the stack; [rsp] armor points, [rsp+8] health text
hud_bars:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r15
    sub     rsp, 48
    mov     r12d, edi
    mov     r13d, esi
    xor     ebx, ebx
.heart:
    cmp     ebx, 10
    jge     .number
    mov     edi, ebx
    mov     esi, [surv + SURVIVAL.health]
    mov     edx, [surv_max_health]
    call    hud_heart_level
    mov     edi, eax
    mov     esi, TILE_HEART_FULL
    call    bar_tile
    mov     edi, eax
    lea     esi, [r12 + rbx*8]
    lea     edx, [r13 - 15]
    call    ui_icon9
    inc     ebx
    jmp     .heart
.number:
    mov     edi, [surv + SURVIVAL.health]
    lea     rsi, [rsp + 8]
    call    i32_to_str
    mov     rdi, rax
    lea     rsi, [s_slash]
    call    str_append
    mov     edi, [surv_max_health]
    mov     rsi, rax
    call    i32_to_str
    mov     byte [rax], 0
    lea     rdi, [rsp + 8]
    mov     esi, 1
    call    ui_text_width
    mov     esi, r12d
    sub     esi, 3
    sub     esi, eax                    ; right-aligned, ending 3 left of the first heart
    lea     rdi, [rsp + 8]
    lea     edx, [r13 - 15]
    mov     ecx, C_CREAM
    mov     r8d, 1
    call    ui_text
    xor     ebx, ebx
.food_icon:
    mov     edi, [surv + SURVIVAL.food]
    lea     eax, [rbx + rbx]
    sub     edi, eax
    mov     esi, TILE_FOOD_FULL
    call    bar_tile
    mov     edi, eax
    mov     esi, 173                    ; x0 + 182 - 9 - 8 * i
    lea     eax, [rbx*8]
    sub     esi, eax
    add     esi, r12d
    lea     edx, [r13 - 15]
    call    ui_icon9
    inc     ebx
    cmp     ebx, 10
    jb      .food_icon
    lea     r15d, [r13 - 15]            ; the top of the hearts
    call    combat_max_mana
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jbe     .armor
    movss   xmm1, xmm0
    movss   xmm0, [combat_mana]
    mov     edi, 80
    call    bar_px
    mov     r8d, eax
    mov     edi, r12d
    lea     esi, [r15 - 6]
    mov     edx, 80
    mov     ecx, 4
    mov     r9d, C_MANA
    call    bar_draw
    sub     r15d, 6
.armor:
    call    armor_effective
    test    eax, eax
    jz      .stamina
    mov     [rsp], eax
    xor     ebx, ebx
.armor_icon:
    mov     edi, [rsp]
    lea     eax, [rbx + rbx]
    sub     edi, eax
    mov     esi, TILE_ARMOR_FULL
    call    bar_tile
    mov     edi, eax
    lea     esi, [r12 + rbx*8]
    lea     edx, [r15 - 10]
    call    ui_icon9
    inc     ebx
    cmp     ebx, 10
    jb      .armor_icon
    sub     r15d, 10
.stamina:
    call    combat_max_stamina
    movss   xmm1, xmm0
    movss   xmm0, [combat_stamina]
    mov     edi, 80
    call    bar_px
    mov     r8d, eax
    mov     r9d, C_STAMINA
    mov     ecx, C_STAMINA_LOW
    movss   xmm0, [combat_stamina]
    comiss  xmm0, [f_25]
    cmovb   r9d, ecx                    ; red once it runs low
    lea     edi, [r12 + 102]
    lea     esi, [r13 - 21]
    mov     edx, 80
    mov     ecx, 4
    call    bar_draw
    mov     eax, r15d
    add     rsp, 48
    pop     r15
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

%macro PIP 2                            ; a 6 x 6 pip for the player timer %1 in colour %2, next slot
    cmp     dword [%1], 0
    jle     %%skip
    lea     edi, [rbx + r13*8 + 102]
    mov     esi, r14d
    mov     edx, 6
    mov     ecx, 6
    mov     r8d, %2
    call    ui_rect
    inc     r13d
%%skip:
%endmacro

; hud_status_pips(edi x0, esi y0): over the stamina bar, one 6 x 6 square, 8 px apart, for each
; active player status: burn (orange), chill (blue), poison (green); 10 px higher while the breath
; bubbles are shown
; ebx = x0, r12d = y0, r13d = pips drawn, r14d = their y
hud_status_pips:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     ebx, edi
    mov     r12d, esi
    xor     r13d, r13d
    lea     r14d, [r12 - 29]
    cmp     dword [surv + SURVIVAL.breath], MAX_BREATH
    jge     .pips
    sub     r14d, 10                    ; the bubbles take the row under them
.pips:
    PIP     combat_burn_t, RGBA(255, 120, 30, 255)
    PIP     combat_chill_t, RGBA(120, 190, 255, 255)
    PIP     combat_poison_t, RGBA(110, 220, 70, 255)
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; hud_sleep_fade(): a full-screen black rect, alpha 255 * sleep_fade (nothing while awake)
hud_sleep_fade:
    sub     rsp, 8
    movss   xmm0, [sleep_fade]
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jbe     .ret
    minss   xmm0, [f_one]
    mulss   xmm0, [f_255]
    cvttss2si eax, xmm0
    shl     eax, 24                     ; RGBA(0, 0, 0, alpha)
    mov     r8d, eax
    xor     edi, edi
    xor     esi, esi
    mov     edx, [ui_w]
    mov     ecx, [ui_h]
    call    ui_rect
.ret:
    add     rsp, 8
    ret

; hud_bubble_tiles(edi breath, rsi out byte[10]): the ten air bubbles of the HUD, bubble i from the
; right: TILE_BUBBLE when breath >= 60 (i + 1), TILE_BUBBLE_POP when 60 i < breath < 60 (i + 1),
; else 0 (not drawn)
hud_bubble_tiles:
    xor     ecx, ecx
.bubble:
    lea     eax, [rcx + 1]
    imul    eax, eax, 60
    xor     edx, edx
    cmp     edi, eax
    jge     .full
    imul    eax, ecx, 60
    cmp     edi, eax
    jle     .store
    mov     edx, TILE_BUBBLE_POP
    jmp     .store
.full:
    mov     edx, TILE_BUBBLE
.store:
    mov     [rsi + rcx], dl
    inc     ecx
    cmp     ecx, 10
    jb      .bubble
    ret

; hud_bubbles(edi x0, esi y0): the air bubbles over the food icons (bubble i at x0 + 173 - 8 i,
; y0 - 31) while the breath is below MAX_BREATH
; ebx = x0, r12d = y0, r13d = bubble; [rsp] the ten tiles
hud_bubbles:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 24
    mov     ebx, edi
    mov     r12d, esi
    mov     edi, [surv + SURVIVAL.breath]
    cmp     edi, MAX_BREATH
    jge     .ret
    lea     rsi, [rsp]
    call    hud_bubble_tiles
    xor     r13d, r13d
.bubble:
    movzx   edi, byte [rsp + r13]
    test    edi, edi
    jz      .next
    mov     esi, 173
    lea     eax, [r13*8]
    sub     esi, eax
    add     esi, ebx
    lea     edx, [r12 - 31]
    call    ui_icon9
.next:
    inc     r13d
    cmp     r13d, 10
    jb      .bubble
.ret:
    add     rsp, 24
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; hud_held_name(edi y): the held item's name centred above the hotbar at y, fading out; a gear item
; shows its rolled name (gear_name) in its rarity colour
; r12d = y, ebx = id, r13d = alpha << 24; [rsp] gear name (48), [rsp+48] dmg of the held stack
hud_held_name:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 56
    mov     r12d, edi
    mov     eax, [inv_sel]
    lea     rcx, [inv + rax*4]
    movzx   ebx, byte [rcx + ITEMSTACK.id]
    cmp     byte [rcx + ITEMSTACK.count], 0
    jne     .have
    xor     ebx, ebx                    ; an empty stack holds nothing
.have:
    cmp     eax, [last_sel]
    jne     .changed
    cmp     ebx, [last_id]
    je      .shown
.changed:
    mov     [last_sel], eax
    mov     [last_id], ebx
    movss   xmm0, [f_two]
    movss   [name_timer], xmm0
.shown:
    movss   xmm0, [name_timer]
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jbe     .ret
    subss   xmm0, [hud_dt]
    movss   [name_timer], xmm0
    comiss  xmm0, xmm1
    jbe     .ret
    test    ebx, ebx
    jz      .ret
    cmp     ebx, NUM_ITEMS
    jae     .ret
    mulss   xmm0, [f_two]               ; timer / 0.5
    minss   xmm0, [f_one]
    mulss   xmm0, [f_255]
    cvttss2si r13d, xmm0                ; alpha = min(1, timer / 0.5) * 255
    shl     r13d, 24
    lea     rax, [item_gear]
    cmp     byte [rax + rbx], 0
    je      .plain
    mov     eax, [inv_sel]
    lea     rcx, [inv + rax*4]
    movzx   esi, word [rcx + ITEMSTACK.dmg]
    mov     [rsp + 48], esi
    mov     edi, ebx
    mov     rdx, rsp
    call    gear_name
    mov     edi, ebx
    mov     esi, [rsp + 48]
    call    gear_rarity
    mov     edi, eax
    call    gear_rarity_color
    and     eax, 0x00FFFFFF
    or      eax, r13d
    mov     ecx, eax
    mov     rdi, rsp
    jmp     .draw
.plain:
    lea     rax, [item_names]
    mov     rdi, [rax + rbx*8]
    mov     ecx, r13d
    or      ecx, C_CREAM & 0x00FFFFFF
.draw:
    mov     edx, r12d
    mov     esi, [ui_w]
    shr     esi, 1
    mov     r8d, 1
    call    ui_text_centered
.ret:
    add     rsp, 56
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; hud_gun(edi x0, esi y0): with a firearm held, "loaded/magazine  [rounds in the inventory]" (the
; magazine counts the stack's attachments and Quartermaster) right of the hotbar (Creative: "[inf]"),
; and the reload progress under the crosshair
hud_gun:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 40                     ; [rsp] text (32)
    mov     r12d, edi
    mov     r13d, esi
    mov     eax, [inv_sel]
    lea     rbx, [inv + rax*4]
    cmp     byte [rbx + ITEMSTACK.count], 0
    je      .ret
    movzx   edi, byte [rbx + ITEMSTACK.id]
    movzx   esi, word [rbx + ITEMSTACK.dmg]
    call    gun_magazine
    test    eax, eax
    jz      .ret
    mov     [rsp + 32], eax             ; magazine
    movzx   edi, word [rbx + ITEMSTACK.dmg]
    and     edi, GUN_ROUNDS_MASK        ; the high byte holds the attachments
    mov     rsi, rsp
    call    i32_to_str
    mov     rdi, rax
    lea     rsi, [s_slash]
    call    str_append
    mov     edi, [rsp + 32]
    mov     rsi, rax
    call    i32_to_str
    mov     rdi, rax
    lea     rsi, [s_ammo_inf]
    cmp     dword [game_mode], MODE_CREATIVE
    je      .tail
    mov     [rsp + 32], rax             ; write cursor (the magazine is no longer needed)
    movzx   edi, byte [rbx + ITEMSTACK.id]
    call    gun_ammo
    mov     edi, eax
    call    inv_count
    mov     ebx, eax
    mov     rdi, [rsp + 32]
    lea     rsi, [s_ammo_l]
    call    str_append
    mov     edi, ebx
    mov     rsi, rax
    call    i32_to_str
    mov     rdi, rax
    lea     rsi, [s_ammo_r]
.tail:
    call    str_append
    mov     byte [rax], 0
    mov     rdi, rsp
    lea     esi, [r12 + 186]
    lea     edx, [r13 + 13]             ; under the level text
    mov     ecx, C_CREAM
    mov     r8d, 1
    call    ui_text
    mov     ecx, [gun_reload_total]
    test    ecx, ecx
    jz      .ret
    cmp     dword [gun_reload], 0
    je      .ret
    mov     ebx, [ui_w]
    shr     ebx, 1
    sub     ebx, 20                     ; bar x
    mov     r12d, [ui_h]
    shr     r12d, 1
    add     r12d, 10                    ; bar y
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, 40
    mov     ecx, 3
    mov     r8d, RGBA(0, 0, 0, 140)
    call    ui_rect
    mov     ecx, [gun_reload_total]
    mov     eax, ecx
    sub     eax, [gun_reload]
    imul    eax, eax, 40
    xor     edx, edx
    div     ecx                         ; filled = 40 * (total - left) / total
    test    eax, eax
    jz      .ret
    mov     edx, eax
    mov     edi, ebx
    mov     esi, r12d
    mov     ecx, 3
    mov     r8d, RGBA(255, 255, 255, 220)
    call    ui_rect
.ret:
    add     rsp, 40
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; bar_px(xmm0 value, xmm1 max, edi width) -> eax filled pixels: width * value / max clamped to
; 0..width, at least 1 while value > 0, 0 when max <= 0
bar_px:
    xorps   xmm2, xmm2
    comiss  xmm1, xmm2
    jbe     .zero
    movss   xmm3, xmm0                  ; value
    divss   xmm0, xmm1
    maxss   xmm0, xmm2
    minss   xmm0, [f_one]
    cvtsi2ss xmm4, edi
    mulss   xmm0, xmm4
    cvttss2si eax, xmm0
    test    eax, eax
    jnz     .ret
    comiss  xmm3, xmm2                  ; a sliver stays visible while there is any value
    jbe     .ret
    mov     eax, 1
.ret:
    ret
.zero:
    xor     eax, eax
    ret

; bar_draw(edi x, esi y, edx w, ecx h, r8d fill_w, r9d fill_rgba): a translucent black backing, the fill
; from the left edge, then the NINE_BAR frame around them, (w + 2) x (h + 2) at (x - 1, y - 1)
; ebx = x, r12d = y, r13d = h, r14d = fill width, r15d = fill colour; [rsp] w
bar_draw:
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
    mov     [rsp], edx
    mov     r13d, ecx
    mov     r14d, r8d
    mov     r15d, r9d
    mov     r8d, RGBA(0, 0, 0, 160)
    call    ui_rect                     ; edi, esi, edx, ecx are still x, y, w, h
    test    r14d, r14d
    jle     .frame
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r14d
    mov     ecx, r13d
    mov     r8d, r15d
    call    ui_rect
.frame:
    mov     edi, NINE_BAR
    lea     esi, [rbx - 1]
    lea     edx, [r12 - 1]
    mov     ecx, [rsp]
    add     ecx, 2
    lea     r8d, [r13 + 2]
    call    ui_nine
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; hud_xp(edi x0, esi y0): the XP bar just over the hotbar and "Level N" right of the hotbar, followed
; by " (<skills key>)" while skill or attribute points are unspent
; ebx = x0, r12d = y0, r13d = level, then the x right of the hotbar; r14 = end of the level text, where
; the hint starts; [rsp] level text (64)
hud_xp:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 64
    mov     ebx, edi
    mov     r12d, esi
    call    rpg_level
    mov     r13d, eax
    mov     edi, eax
    call    rpg_xp_need
    mov     r8d, 180                    ; the last level shows a full bar
    test    eax, eax
    jz      .have_fill
    mov     ecx, eax
    mov     eax, [rpg_state + RPGSAVE.xp]
    imul    eax, eax, 180
    xor     edx, edx
    div     ecx
    cmp     eax, r8d
    cmovb   r8d, eax                    ; min(180, 180 * xp / need)
.have_fill:
    lea     edi, [rbx + 1]
    lea     esi, [r12 - 5]
    mov     edx, 180
    mov     ecx, 3
    mov     r9d, C_XP
    call    bar_draw
    mov     rdi, rsp
    lea     rsi, [s_level_l]
    call    str_append
    mov     edi, r13d
    mov     rsi, rax
    call    i32_to_str
    mov     r14, rax
    call    rpg_points
    test    eax, eax
    jnz     .hint
    call    rpg_attr_points
    test    eax, eax
    jz      .plain
.hint:
    mov     rdi, r14
    lea     rsi, [s_hint_l]
    call    str_append
    mov     edi, [settings + SETTINGS.keys + 4*BIND_SKILLS]
    mov     rsi, rax
    call    key_name
    mov     word [rax], ')'             ; ')' and the NUL
    jmp     .draw
.plain:
    mov     byte [r14], 0
.draw:
    lea     r13d, [rbx + 186]           ; the level is spent: r13d = x right of the hotbar
    call    debug_is_cheater            ; a world the debug menu was opened in: a red [C] first, the level follows
    test    eax, eax
    jz      .no_mark
    lea     rdi, [s_cheat_mark]
    mov     esi, r13d
    lea     edx, [r12 + 2]
    mov     ecx, C_CHEAT
    mov     r8d, 1
    call    ui_text
    lea     r13d, [r13 + rax + 3]
.no_mark:
    mov     rdi, rsp
    mov     esi, 1
    call    ui_text_width
    lea     eax, [rax + r13 + 2]
    cmp     eax, [ui_w]
    jle     .whole                      ; fits right of the hotbar
    cmp     byte [r14], 0
    je      .whole
    mov     byte [r14], 0               ; too narrow: "Level N" and the hint "(K)" on two lines
    mov     rdi, rsp
    mov     esi, r13d
    lea     edx, [r12 + 2]
    mov     ecx, C_GOLD_TEXT
    call    hud_text_clamped
    lea     rdi, [r14 + 1]
    mov     esi, r13d
    lea     edx, [r12 + 12]
    mov     ecx, C_GOLD_TEXT
    call    hud_text_clamped
    jmp     .done
.whole:
    mov     rdi, rsp
    mov     esi, r13d
    lea     edx, [r12 + 2]
    mov     ecx, C_GOLD_TEXT
    call    hud_text_clamped
.done:
    add     rsp, 64
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; hud_text_clamped(rdi s, esi x, edx y, ecx rgba): s at scale 1, its x pulled left so that it ends at
; most 2 units inside the right edge
; rbx = s, r12d = x, r13d = y, r14d = rgba
hud_text_clamped:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    mov     esi, 1
    call    ui_text_width
    mov     esi, [ui_w]
    sub     esi, eax
    sub     esi, 2
    cmp     r12d, esi
    cmovg   r12d, esi
    mov     rdi, rbx
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, r14d
    mov     r8d, 1
    call    ui_text
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; hud_ability_pos(edi x0, esi y0, edx top) -> eax x, edx y of the first ability slot (20 x 20), ecx 1 when
; the bar sits above the left stack. The slots go left of the hotbar at (x0 - 93, y0 + 1) unless that
; starts under 2 (a narrow GUI), then in a row above the left stack of hearts, mana and armor (top =
; y of its top; the XP bar when there is none) with their key labels 9 above: (x0, top - 22)
hud_ability_pos:
    lea     eax, [rdi - 93]
    cmp     eax, 2
    jl      .above
    lea     edx, [rsi + 1]
    xor     ecx, ecx
    ret
.above:
    mov     eax, edi
    sub     edx, 22
    mov     ecx, 1
    ret

; hud_abilities(edi x0, esi y0, edx top) -> eax y of the top of the key tabs when the bar is above the
; left stack (see hud_ability_pos), else 0x7FFFFFFF: the four ability bar slots, carved runes 20 x 20:
; the icon of the bound ability (red while the resource is short: stamina or mana, or with Blood Magic
; the health it would take), the cooldown of that ability sweeping down from the top, and the key on a
; paper tab 9 above; an empty slot shows its rune and its key only
; ebx = x of slot 0, r12d = slot 0 y - 1, r13d = slot, r14d = its ability id (-1: empty), then the width
; of the key tab, r15d = slot x
; [rsp] icon tint, [rsp+4] sweep height, [rsp+8] above the stack, [rsp+16] key label
hud_abilities:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 56
    call    hud_ability_pos
    mov     ebx, eax
    lea     r12d, [rdx - 1]
    mov     [rsp + 8], ecx
    xor     r13d, r13d
.slot:
    imul    r15d, r13d, 23
    add     r15d, ebx                   ; slot x = x of slot 0 + 23 * slot
    mov     edi, NINE_RUNE
    mov     esi, r15d
    lea     edx, [r12 + 1]              ; slot y = y0 + 1
    mov     ecx, 20
    mov     r8d, 20
    call    ui_nine
    mov     dword [rsp], WHITE
    mov     dword [rsp + 4], 0
    mov     edi, r13d
    call    rpg_bar_ability
    mov     r14d, eax
    test    eax, eax
    js      .label                      ; nothing bound: the backing and the key only
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .sweep                      ; creative pays nothing
    mov     edi, r14d
    call    rpg_ability_info
    cvtsi2ss xmm1, dword [rax + ABILINFO.cost]
    movss   xmm0, [combat_stamina]
    cmp     dword [rax + ABILINFO.resource], RES_MANA
    jne     .have
    test    dword [rpg_keystones], 1 << KS_BLOOD_MAGIC
    jnz     .blood
    movss   xmm0, [combat_mana]
.have:
    comiss  xmm0, xmm1
    jae     .sweep
.short:
    mov     dword [rsp], RGBA(255, 90, 90, 255)         ; the resource is short: red
    jmp     .sweep
.blood:
    mov     eax, [rax + ABILINFO.cost]  ; Blood Magic pays ceil(cost / 5) health, leaving at least 1
    add     eax, 4
    xor     edx, edx
    mov     ecx, 5
    div     ecx
    cmp     [surv + SURVIVAL.health], eax
    jle     .short
.sweep:
    lea     rcx, [abilities_cd]
    mov     eax, [rcx + r14*4]          ; steps left
    lea     rcx, [abilities_cd_total]
    mov     ecx, [rcx + r14*4]          ; steps of the whole cooldown
    test    eax, eax
    jle     .icon
    test    ecx, ecx
    jle     .icon
    imul    eax, eax, 20
    xor     edx, edx
    div     ecx
    mov     edx, 20
    cmp     eax, edx
    cmova   eax, edx
    mov     [rsp + 4], eax              ; 20 * left / total
.icon:
    mov     edi, r14d
    call    rpg_ability_tile
    mov     edi, eax
    lea     esi, [r15 + 2]
    lea     edx, [r12 + 3]
    mov     ecx, 16
    mov     r8d, [rsp]
    call    ui_tile_icon
    mov     ecx, [rsp + 4]
    test    ecx, ecx
    jz      .label
    mov     edi, r15d
    lea     esi, [r12 + 1]
    mov     edx, 20
    mov     r8d, RGBA(0, 0, 0, 170)
    call    ui_rect                     ; ecx = the swept height
.label:
    lea     eax, [r13 + BIND_ABILITY1]  ; binds 11, 12, 13 and 15
    mov     ecx, BIND_ABILITY4
    cmp     r13d, 3
    cmove   eax, ecx
    lea     rcx, [settings + SETTINGS.keys]
    mov     edi, [rcx + rax*4]
    lea     rsi, [rsp + 16]
    call    key_name
    mov     byte [rsp + 19], 0          ; at most three characters fit over a slot
    lea     rdi, [rsp + 16]
    mov     esi, 1
    call    ui_text_width
    add     eax, 3                      ; the tab: ink width + 4 (the advance counts a trailing gap)
    mov     r14d, eax
    shr     eax, 1
    neg     eax
    lea     esi, [r15 + rax + 10]       ; centred over the slot
    mov     edi, NINE_NOTE
    lea     edx, [r12 - 8]              ; 9 above the slot
    mov     ecx, r14d
    mov     r8d, 9
    call    ui_nine
    shr     r14d, 1
    neg     r14d
    lea     esi, [r15 + r14 + 12]       ; the key sits 2 inside the tab
    lea     rdi, [rsp + 16]
    lea     edx, [r12 - 7]
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
    inc     r13d
    cmp     r13d, NUM_ABILITY_SLOTS
    jb      .slot
    mov     eax, 0x7FFFFFFF             ; beside the hotbar nothing needs clearing
    mov     ecx, r12d
    sub     ecx, 8                      ; the top of the key labels
    cmp     dword [rsp + 8], 0
    cmovne  eax, ecx
    add     rsp, 56
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; hud_stealth(): a violet tint over the whole screen while stealth lasts
hud_stealth:
    sub     rsp, 8
    cmp     dword [combat_stealth_t], 0
    jle     .ret
    xor     edi, edi
    xor     esi, esi
    mov     edx, [ui_w]
    mov     ecx, [ui_h]
    mov     r8d, RGBA(20, 0, 40, 60)
    call    ui_rect
.ret:
    add     rsp, 8
    ret

; ANCHOR above: project the point that high over the head of mob rbx into [rsp+16] (x, y); eax = visible.
; [rsp] is scratch for the world position
%macro ANCHOR 1
    mov     eax, [rbx + BODY.x]
    mov     [rsp], eax
    movss   xmm0, [rbx + BODY.y]
    addss   xmm0, [rbx + BODY.height]
    addss   xmm0, [%1]
    movss   [rsp + 4], xmm0
    mov     eax, [rbx + BODY.z]
    mov     [rsp + 8], eax
    mov     rdi, rsp
    lea     rsi, [rsp + 16]
    call    world_to_ui
%endmacro

; mob_dist_sq(rdi MOB*) -> xmm0 the squared distance from the player to that mob (leaf)
mob_dist_sq:
    movss   xmm0, [rdi + BODY.x]
    subss   xmm0, [player + BODY.x]
    movss   xmm1, [rdi + BODY.y]
    subss   xmm1, [player + BODY.y]
    movss   xmm2, [rdi + BODY.z]
    subss   xmm2, [player + BODY.z]
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    mulss   xmm2, xmm2
    addss   xmm0, xmm1
    addss   xmm0, xmm2
    ret

; hud_mobs(): things pinned to mobs with world_to_ui: over every hostile mob (a folk fighter that
; counts as hostile too: mob_is_hostile) that was hurt lately (MOB.bar) or is elite, within 24
; blocks, a health bar (elites get a gold frame, a marked mob a red one around it), "Lv N" over the
; bar, an elite's affix names over that, and a 3 x 3 pip under the bar for each status; and over
; every folk within 10 blocks its name plate (folk_name in the colour of its faction's tier, a
; champion's in gold, " (asleep)" after it while it sleeps), over its bar and the lines above it
; when it has one
; rbx = mob, r12d = index, r13d = type, r14d = bar fill / bit / pips / the plate's height over its
; anchor; [rsp] anchor, [rsp+16] out x, y, [rsp+24] pip index / affix cursor, [rsp+32] "Lv N" text
; (16), [rsp+48] affix text (80), [rsp+128] how far over the bar's anchor the plate goes (0: no bar)
hud_mobs:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 144
    lea     rbx, [mobs]
    xor     r12d, r12d
.mob:
    mov     r13d, [rbx + MOB.type]
    test    r13d, r13d
    jz      .next
    mov     dword [rsp + 128], 0        ; no bar drawn yet
    mov     rdi, rbx
    call    mob_dist_sq                 ; xmm0 = squared distance to the player
    cmp     dword [rbx + MOB.bar], 0
    jg      .bar
    cmp     dword [rbx + MOB.elite], 0
    jne     .bar
    cmp     dword [rbx + MOB.mark_t], 0 ; a marked foe keeps its plate for the whole mark
    jle     .next
.bar:
    comiss  xmm0, [f_24sq]
    ja      .next
    mov     edi, r12d
    call    mob_is_hostile
    test    eax, eax
    jz      .next
    ANCHOR  f_bar_up
    test    eax, eax
    jz      .next
    cvtsi2ss xmm0, dword [rbx + MOB.health]
    cvtsi2ss xmm1, dword [rbx + MOB.max_health]
    maxss   xmm1, xmm0                  ; never more than full
    mov     edi, 20
    call    bar_px
    mov     r14d, eax
    mov     edi, [rsp + 16]
    sub     edi, 11                     ; 22 x 4 backing, centred on the anchor
    mov     esi, [rsp + 20]
    sub     esi, 2
    mov     edx, 22
    mov     ecx, 4
    mov     r8d, RGBA(0, 0, 0, 160)
    call    ui_rect
    test    r14d, r14d
    jz      .frame
    mov     edi, [rsp + 16]
    sub     edi, 10
    mov     esi, [rsp + 20]
    dec     esi
    mov     edx, r14d
    mov     ecx, 2
    mov     r8d, RGBA(230, 40, 40, 255)
    call    ui_rect
.frame:
    cmp     dword [rbx + MOB.elite], 0
    je      .mark
    mov     edi, [rsp + 16]
    sub     edi, 11
    mov     esi, [rsp + 20]
    sub     esi, 2
    mov     edx, 22
    mov     ecx, 4
    mov     r8d, RGBA(255, 200, 60, 255)
    call    ui_frame
.mark:
    cmp     dword [rbx + MOB.mark_t], 0
    jle     .level
    mov     edi, [rsp + 16]
    sub     edi, 12
    mov     esi, [rsp + 20]
    sub     esi, 3
    mov     edx, 24
    mov     ecx, 6
    mov     r8d, RGBA(230, 40, 40, 255)
    call    ui_frame                    ; 1 px outside the bar's backing
.level:
    mov     dword [rsp + 32], 0x0020764C ; "Lv " and the NUL
    mov     edi, [rbx + MOB.level]
    lea     rsi, [rsp + 35]
    call    i32_to_str
    mov     byte [rax], 0
    mov     ecx, RGBA(200, 200, 200, 255)
    mov     eax, RGBA(255, 200, 80, 255)
    cmp     dword [rbx + MOB.elite], 0
    cmovne  ecx, eax
    lea     rdi, [rsp + 32]
    mov     esi, [rsp + 16]
    mov     edx, [rsp + 20]
    sub     edx, 11                     ; 9 above the top of the bar
    mov     r8d, 1
    call    ui_text_centered
    mov     dword [rsp + 128], 20       ; a plate goes over the level line
    cmp     dword [rbx + MOB.elite], 0
    je      .pips
    cmp     dword [rbx + MOB.affix], 0
    je      .pips
    lea     rax, [rsp + 48]
    mov     [rsp + 24], rax             ; write cursor
    xor     r14d, r14d
.affix:
    bt      dword [rbx + MOB.affix], r14d
    jnc     .affix_next
    mov     edi, r14d
    call    mob_affix_name
    mov     rsi, rax
    mov     rdi, [rsp + 24]
    lea     rcx, [rsp + 48]
    cmp     rdi, rcx
    je      .first
    mov     byte [rdi], ' '
    inc     rdi
.first:
    call    str_append
    mov     [rsp + 24], rax
.affix_next:
    inc     r14d
    cmp     r14d, NUM_AFFIX_KINDS
    jb      .affix
    mov     rax, [rsp + 24]
    mov     byte [rax], 0
    lea     rdi, [rsp + 48]
    mov     esi, [rsp + 16]
    mov     edx, [rsp + 20]
    sub     edx, 20                     ; 9 above "Lv N"
    mov     ecx, RGBA(255, 140, 60, 255)
    mov     r8d, 1
    call    ui_text_centered
    mov     dword [rsp + 128], 29       ; ... or over the affix line
.pips:
    xor     r14d, r14d                  ; pips drawn
    mov     dword [rsp + 24], 0         ; pip_tab row
.pip:
    mov     eax, [rsp + 24]
    cmp     eax, 5
    jae     .next
    lea     rcx, [pip_tab]
    mov     edx, [rcx + rax*8]          ; offset of the timer in the MOB
    cmp     dword [rbx + rdx], 0
    jle     .pip_next
    mov     r8d, [rcx + rax*8 + 4]
    mov     edi, r14d
    shl     edi, 2
    add     edi, [rsp + 16]
    sub     edi, 11                     ; 4 px apart from the left edge of the bar
    mov     esi, [rsp + 20]
    add     esi, 3                      ; just under the bar
    mov     edx, 3
    mov     ecx, 3
    call    ui_rect
    inc     r14d
.pip_next:
    inc     dword [rsp + 24]
    jmp     .pip
.next:
    cmp     r13d, MOB_FOLK              ; a folk's name plate
    jne     .advance
    mov     rdi, rbx
    call    mob_dist_sq
    comiss  xmm0, [f_10sq]
    ja      .advance
    mov     r14d, [rsp + 128]           ; over the bar's lines (its anchor is still in [rsp+16]) ...
    test    r14d, r14d
    jnz     .plate
    mov     r14d, 8                     ; ... or on a name tag's anchor
    ANCHOR  f_tag_up
    test    eax, eax
    jz      .advance
.plate:
    mov     rdi, rbx
    lea     rsi, [plate_buf]
    call    folk_name                   ; rax = the end of the name
    test    byte [rbx + MOB.fflags], FF_ASLEEP
    jz      .named
    mov     rdi, rax
    lea     rsi, [s_asleep]
    call    str_append
.named:
    mov     byte [rax], 0
    movzx   edi, byte [rbx + MOB.faction]
    call    faction_tier_color
    mov     ecx, RGBA(255, 215, 60, 255) ; a champion's name is gold whatever the standing
    cmp     byte [rbx + MOB.role], ROLE_CHAMPION
    cmovne  ecx, eax
    lea     rdi, [plate_buf]
    mov     esi, [rsp + 16]
    mov     edx, [rsp + 20]
    sub     edx, r14d
    mov     r8d, 1
    call    ui_text_centered
.advance:
    add     rbx, MOB_size
    inc     r12d
    cmp     r12d, MAX_MOBS
    jb      .mob
    add     rsp, 144
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; hud_boss() -> eax 1 when the boss bar is up: a living boss within 48 blocks, its name on a ribbon over
; a framed red bar across the top of the screen
hud_boss:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    lea     rbx, [mobs]
.scan:
    cmp     dword [rbx + MOB.type], MOB_BOSS
    jne     .next
    cmp     dword [rbx + MOB.health], 0
    jle     .next
    movss   xmm0, [rbx + BODY.x]
    subss   xmm0, [player + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    subss   xmm1, [player + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    subss   xmm2, [player + BODY.z]
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    mulss   xmm2, xmm2
    addss   xmm0, xmm1
    addss   xmm0, xmm2
    comiss  xmm0, [f_48sq]
    jbe     .found
.next:
    add     rbx, MOB_size
    lea     rax, [mobs + MAX_MOBS * MOB_size]
    cmp     rbx, rax
    jb      .scan
    xor     eax, eax
    jmp     .ret
.found:
    lea     rdi, [s_boss]
    mov     esi, [ui_w]
    shr     esi, 1
    xor     edx, edx                    ; the ribbon hangs from the top edge
    call    ui_ribbon
    cvtsi2ss xmm0, dword [rbx + MOB.health]
    cvtsi2ss xmm1, dword [rbx + MOB.max_health]
    maxss   xmm1, xmm0
    mov     edi, 182
    call    bar_px
    mov     r8d, eax
    mov     edi, [ui_w]
    shr     edi, 1
    sub     edi, 91
    mov     esi, 15                     ; the frame starts under the 14-high ribbon
    mov     edx, 182
    mov     ecx, 5
    mov     r9d, C_BLOOD
    call    bar_draw
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; hud_peer_rows() -> eax how many players the session lists: yourself and every other slot that is
; not PEER_FREE (leaf)
hud_peer_rows:
    xor     eax, eax
    xor     ecx, ecx
    lea     rdx, [net_peers]
.slot:
    movzx   r8d, byte [net_self]
    cmp     ecx, r8d
    je      .count
    cmp     dword [rdx + PEER.state], PEER_FREE
    je      .next
.count:
    inc     eax
.next:
    add     rdx, PEER_size
    inc     ecx
    cmp     ecx, NET_MAX_PEERS
    jb      .slot
    ret

; hud_chat(): the chat log at the bottom left, the newest line at the bottom: up to 6 lines in play,
; 8 while the chat bar is open (ST_CHAT). A line is white on a faint backing, shows for 10 seconds
; and fades out over the last 2; with the chat bar open every line shows at full strength.
; rbx = line (0 = newest), r12d = its y, r13d = lines to show, r14d = alpha, r15 = its text
hud_chat:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r13d, 6
    cmp     dword [app_state], ST_CHAT
    jne     .lines
    mov     r13d, 8
.lines:
    xor     ebx, ebx
.line:
    cmp     ebx, r13d
    jge     .ret
    mov     edi, ebx
    call    net_chat_line               ; rax = the text or 0, edx = its age in ms
    test    rax, rax
    jz      .ret
    mov     r15, rax
    mov     r14d, 255
    cmp     dword [app_state], ST_CHAT
    je      .alpha_known
    cmp     edx, CHAT_LIFE_MS
    jae     .ret                        ; this line and every older one are gone
    cmp     edx, CHAT_LIFE_MS - CHAT_FADE_MS
    jbe     .alpha_known
    mov     eax, CHAT_LIFE_MS
    sub     eax, edx
    imul    eax, eax, 255
    xor     edx, edx
    mov     ecx, CHAT_FADE_MS
    div     ecx
    mov     r14d, eax                   ; alpha = 255 * (life - age) / fade
.alpha_known:
    mov     r12d, [ui_h]
    sub     r12d, CHAT_BASE
    imul    eax, ebx, 10
    sub     r12d, eax                   ; ten units a line, going up
    mov     rdi, r15
    mov     esi, 1
    call    ui_text_width
    lea     edx, [rax + 4]
    mov     edi, 2
    lea     esi, [r12 - 1]
    mov     ecx, 10
    imul    r8d, r14d, 100
    shr     r8d, 8
    shl     r8d, 24                     ; RGBA(0, 0, 0, alpha * 100 / 256)
    call    ui_rect
    mov     rdi, r15
    mov     esi, 4
    mov     edx, r12d
    mov     ecx, r14d
    shl     ecx, 24
    or      ecx, 0x00FFFFFF
    mov     r8d, 1
    call    ui_text
    inc     ebx
    jmp     .line
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; hud_players(): while the player-list binding is held in play, a leather panel centred under the
; top edge with a row for every player of the session: the name in its slot colour ("(host)" after
; the host's), "Lv N", and the round-trip time right aligned ("-" where nothing is measured:
; yourself, and for a guest everyone but the host)
; rbx = slot, r12 = PEER*, r13d = panel x, r14d = row y, r15d = rows
; stack: [rsp] text (16), [rsp+24] name, [rsp+32] level (-1: unknown), [rsp+36] round-trip time
hud_players:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40
    cmp     byte [net_role], NET_ROLE_OFF
    je      .ret
    cmp     dword [app_state], ST_PLAYING
    jne     .ret
    cmp     dword [frame_input + FRAMEINPUT.players], 0
    je      .ret
    call    hud_peer_rows
    mov     r15d, eax
    mov     r13d, [ui_w]
    sub     r13d, PL_W
    sar     r13d, 1
    xor     eax, eax
    test    r13d, r13d
    cmovs   r13d, eax
    mov     edi, NINE_LEATHER
    mov     esi, r13d
    mov     edx, PL_Y
    mov     ecx, PL_W
    imul    r8d, r15d, PL_ROW
    add     r8d, 24
    call    ui_nine
    lea     rdi, [s_players]
    lea     esi, [r13 + PL_W / 2]
    mov     edx, PL_Y + 6
    mov     ecx, C_GOLD_TEXT
    mov     r8d, 1
    call    ui_text_centered
    lea     edi, [r13 + 8]
    mov     esi, PL_Y + 17
    mov     edx, PL_W - 16
    mov     ecx, 1
    mov     r8d, C_GOLD
    call    ui_rect
    mov     r14d, PL_Y + 21
    xor     ebx, ebx
    lea     r12, [net_peers]
.row:
    movzx   eax, byte [net_self]
    cmp     ebx, eax
    je      .listed
    cmp     dword [r12 + PEER.state], PEER_FREE
    je      .next
.listed:
    lea     rdi, [r12 + PEER.name]      ; your own row shows the name you chose
    lea     rdx, [net_cfg_name]
    cmp     ebx, eax
    cmove   rdi, rdx
    mov     [rsp + 24], rdi
    mov     edi, ebx
    call    peer_slot_rgba
    mov     ecx, eax
    mov     rdi, [rsp + 24]
    lea     esi, [r13 + 8]
    mov     edx, r14d
    mov     r8d, 1
    call    ui_text                     ; eax = the name's advance
    test    ebx, ebx
    jnz     .level
    lea     esi, [r13 + rax + 12]
    lea     rdi, [s_host_tag]
    mov     edx, r14d
    mov     ecx, C_CREAM
    mov     r8d, 1
    call    ui_text
.level:
    mov     dword [rsp + 32], -1
    movzx   eax, byte [net_self]
    cmp     ebx, eax
    jne     .level_peer
    call    rpg_level                   ; yourself
    mov     [rsp + 32], eax
    jmp     .level_text
.level_peer:
    cmp     dword [r12 + PEER.state], PEER_READY
    jne     .level_text                 ; no PSTATE yet
    movzx   eax, byte [r12 + PEER.ps + PSTATE.level]
    mov     [rsp + 32], eax
.level_text:
    mov     rdi, rsp
    lea     rsi, [s_lvp]
    call    str_append
    mov     edi, [rsp + 32]
    test    edi, edi
    js      .level_none
    mov     rsi, rax
    call    i32_to_str
    jmp     .level_end
.level_none:
    mov     rdi, rax
    lea     rsi, [s_dash]
    call    str_append
.level_end:
    mov     byte [rax], 0
    mov     rdi, rsp
    lea     esi, [r13 + 158]
    mov     edx, r14d
    mov     ecx, C_CREAM
    mov     r8d, 1
    call    ui_text
    mov     dword [rsp + 36], 0
    cmp     byte [net_role], NET_ROLE_HOST
    sete    al
    movzx   eax, al
    test    ebx, ebx
    setz    cl
    movzx   ecx, cl
    cmp     eax, ecx
    je      .rtt_text                   ; the host's own row, or a guest's view of another guest
    lea     rdi, [net_ep]
    mov     esi, ebx
    call    net_ep_rtt_ms
    mov     [rsp + 36], eax
.rtt_text:
    mov     edi, [rsp + 36]
    test    edi, edi
    jz      .rtt_none
    mov     rsi, rsp
    call    i32_to_str
    mov     rdi, rax
    lea     rsi, [s_ms]
    call    str_append
    jmp     .rtt_end
.rtt_none:
    mov     rdi, rsp
    lea     rsi, [s_dash]
    call    str_append
.rtt_end:
    mov     byte [rax], 0
    mov     rdi, rsp
    mov     esi, 1
    call    ui_text_width
    mov     esi, PL_W - 8
    sub     esi, eax
    add     esi, r13d                   ; right aligned, 8 from the panel's edge
    mov     rdi, rsp
    mov     edx, r14d
    mov     ecx, C_CREAM
    mov     r8d, 1
    call    ui_text
    add     r14d, PL_ROW
.next:
    add     r12, PEER_size
    inc     ebx
    cmp     ebx, NET_MAX_PEERS
    jb      .row
.ret:
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; hud_quest(edi y): the accepted quest on a pinned paper note at (4, y): "Quest: <title>" and under it
; "p/c"; for the dungeon and boss quests also the compass heading and distance to the nearest site left
; to clear, "p/c  NE 120m"
; rbx = QUESTINFO*, r12 = write cursor into quest_buf, r13d = y, r14 = heading name, then the width of
; line one; [rsp] dx, dz, [rsp+8] line two (the second string in quest_buf)
hud_quest:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 16
    mov     r13d, edi
    cmp     byte [rpg_state + RPGSAVE.quest_state], 1
    jne     .ret
    call    quests_current
    test    rax, rax
    jz      .ret
    mov     rbx, rax
    lea     rdi, [quest_buf]
    lea     rsi, [s_quest]
    call    str_append
    mov     rdi, rax
    mov     rsi, [rbx + QUESTINFO.title]
    call    str_append
    mov     byte [rax], 0               ; line one is done: "Quest: <title>"
    lea     r12, [rax + 1]              ; line two goes after its NUL
    mov     [rsp + 8], r12
    call    quests_progress
    mov     ecx, [rbx + QUESTINFO.count]
    cmp     eax, ecx
    cmova   eax, ecx                    ; never past the goal
    mov     edi, eax
    mov     rsi, r12
    call    i32_to_str
    mov     rdi, rax
    lea     rsi, [s_slash]
    call    str_append
    mov     edi, [rbx + QUESTINFO.count]
    mov     rsi, rax
    call    i32_to_str
    mov     r12, rax
    mov     eax, [rbx + QUESTINFO.type]
    mov     edi, SITE_DUNGEON
    cmp     eax, Q_CLEAR
    je      .site
    mov     edi, SITE_CRYPT
    cmp     eax, Q_BOSS
    jne     .draw
.site:
    mov     esi, 1
    call    structures_nearest
    test    rax, rax
    jz      .draw
    cvtsi2ss xmm0, dword [rax + SITE.x]
    subss   xmm0, [player + BODY.x]
    cvtsi2ss xmm1, dword [rax + SITE.z]
    subss   xmm1, [player + BODY.z]
    movss   [rsp], xmm0                 ; dx
    movss   [rsp + 4], xmm1             ; dz
    xorps   xmm2, xmm2
    subss   xmm2, xmm1
    movss   xmm1, xmm2                  ; north is -z
    call    atan2_deg                   ; xmm0 = atan2(dx, -dz): degrees clockwise from north
    addss   xmm0, [f_22_5]              ; headings are 45 degrees wide, centred on the compass points
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jae     .sector
    addss   xmm0, [f_360]
.sector:
    divss   xmm0, [f_45]
    cvttss2si eax, xmm0
    and     eax, 7
    lea     eax, [rax + rax*2]          ; 3 bytes per heading name
    lea     r14, [headings]
    add     r14, rax
    mov     rdi, r12
    lea     rsi, [s_gap]
    call    str_append
    mov     rdi, rax
    mov     rsi, r14
    call    str_append
    mov     rdi, rax
    lea     rsi, [s_space]
    call    str_append
    movss   xmm0, [rsp]
    mulss   xmm0, xmm0
    movss   xmm1, [rsp + 4]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    sqrtss  xmm0, xmm0
    cvttss2si edi, xmm0
    mov     rsi, rax
    call    i32_to_str
    mov     rdi, rax
    lea     rsi, [s_metres]
    call    str_append
    mov     r12, rax
.draw:
    mov     byte [r12], 0
    lea     rdi, [quest_buf]
    mov     esi, 1
    call    ui_text_width
    mov     r14d, eax
    mov     rdi, [rsp + 8]
    mov     esi, 1
    call    ui_text_width
    cmp     eax, r14d
    cmovl   eax, r14d                   ; the wider of the two lines
    lea     ecx, [rax + 7]              ; the note is the ink width + 8 (the advance counts a trailing gap)
    mov     edi, NINE_NOTE
    mov     esi, 4
    mov     edx, r13d
    mov     r8d, 26                     ; two lines of 10, and 6 for the margins
    call    ui_nine
    lea     rdi, [quest_buf]
    mov     esi, 8
    lea     edx, [r13 + 3]
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
    mov     rdi, [rsp + 8]
    mov     esi, 8
    lea     edx, [r13 + 13]
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
.ret:
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; hud_banner(rdi zstr, esi rgba): show a message in the middle of the screen for 2.5 s, fading over
; the last half second; the text is copied, at most 63 characters. Only the alpha of rgba counts: the
; banner is a crimson ribbon with cream text whatever the message
hud_banner:
    sub     rsp, 8
    mov     [banner_rgba], esi
    mov     rsi, rdi
    lea     rdi, [banner_text]
    mov     edx, 63
    call    str_copy
    movss   xmm0, [f_2_5]
    movss   [banner_timer], xmm0
    add     rsp, 8
    ret

; hud_banner_draw(): count the banner down (hud_dt) and paint it in the middle of the screen,
; ui_h/2 - 50; under the shrine screen, which paints it above its panel itself, it only counts down
hud_banner_draw:
    movss   xmm0, [banner_timer]
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jbe     .ret
    subss   xmm0, [hud_dt]
    movss   [banner_timer], xmm0
    cmp     dword [app_state], ST_SHRINE
    je      .ret
    mov     edi, [ui_h]
    shr     edi, 1
    sub     edi, 50
    jmp     hud_banner_paint
.ret:
    ret

; hud_banner_paint(edi y): the banner, while one is up: a crimson ribbon (ink width + 20) x (8 scale + 8)
; centred on ui_w/2, top y - 4, with the text in cream centred on it at height y; scale 2, or the
; largest smaller scale whose ribbon fits in ui_w - 16 (never below 1). Both fade with the timer. It
; does not count down: a screen that hides the banner's usual place paints it again where it shows.
; ebx = alpha << 24, r12d = scale, r13d = y, r14d = ink width
hud_banner_paint:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 8
    mov     r13d, edi
    movss   xmm0, [banner_timer]
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jbe     .ret
    mulss   xmm0, [f_two]               ; timer / 0.5
    minss   xmm0, [f_one]
    movzx   eax, byte [banner_rgba + 3]
    cvtsi2ss xmm1, eax
    mulss   xmm0, xmm1
    cvttss2si ebx, xmm0                 ; alpha = min(1, timer / 0.5) * the banner's own alpha
    shl     ebx, 24
    mov     r12d, 2
.fit:
    lea     rdi, [banner_text]
    mov     esi, r12d
    call    ui_text_width
    test    eax, eax
    jz      .ret                        ; no text, no ribbon
    sub     eax, r12d                   ; the ink: the advance less its trailing 1-unit gap
    mov     r14d, eax
    mov     ecx, [ui_w]
    sub     ecx, 36                     ; the ribbon is 20 wider and keeps 8 clear on each side
    cmp     eax, ecx
    jbe     .fits
    cmp     r12d, 1
    jbe     .fits
    dec     r12d
    jmp     .fit
.fits:
    lea     ecx, [r14 + 20]             ; ribbon width
    mov     esi, [ui_w]
    shr     esi, 1
    mov     eax, ecx
    shr     eax, 1
    sub     esi, eax                    ; x = ui_w / 2 - width / 2
    lea     edx, [r13 - 4]
    lea     r8d, [r12*8 + 8]
    mov     r9d, ebx
    or      r9d, 0x00FFFFFF             ; white at the banner's alpha
    mov     edi, NINE_RIBBON
    call    ui_nine_tint
    lea     rdi, [banner_text]
    mov     esi, [ui_w]
    shr     esi, 1
    mov     edx, r13d
    mov     ecx, ebx
    or      ecx, C_CREAM & 0x00FFFFFF
    mov     r8d, r12d
    call    ui_text_centered
.ret:
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; put2(edi value 0..99, rsi buf) -> rax past the two digits
put2:
    mov     eax, edi
    xor     edx, edx
    mov     ecx, 10
    div     ecx
    add     al, '0'
    add     dl, '0'
    mov     [rsi], al
    mov     [rsi + 1], dl
    lea     rax, [rsi + 2]
    ret

; debug_emit(rdi end of the text in dbg_buf, esi line, edx rgba): draw dbg_buf as line number esi
debug_emit:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     [rsp], edx
    mov     byte [rdi], 0
    mov     r12d, esi
    lea     rbx, [dbg_buf]
    mov     rdi, rbx
    mov     esi, 1
    call    ui_text_width
    mov     r13d, eax
    lea     esi, [r12 + r12*4]
    add     esi, esi
    inc     esi                         ; background y = 1 + 10 * line
    mov     edi, 1
    lea     edx, [r13 + 2]
    mov     ecx, 10
    mov     r8d, RGBA(0, 0, 0, 96)
    call    ui_rect
    mov     rdi, rbx
    mov     esi, 2
    lea     edx, [r12 + r12*4]
    add     edx, edx
    add     edx, 2                      ; text y = 2 + 10 * line
    mov     ecx, [rsp]
    mov     r8d, 1
    call    ui_text
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; text builders: rbx is the write cursor into dbg_buf
%macro APPEND_STR 1
    mov     rdi, rbx
    lea     rsi, [%1]
    call    str_append
    mov     rbx, rax
%endmacro
%macro APPEND_INT 1                     ; 32-bit memory operand
    mov     edi, %1
    mov     rsi, rbx
    call    i32_to_str
    mov     rbx, rax
%endmacro
%macro APPEND_EAX 0
    mov     edi, eax
    mov     rsi, rbx
    call    i32_to_str
    mov     rbx, rax
%endmacro
%macro APPEND_F32 2                     ; float memory operand, decimals
    movss   xmm0, %1
    mov     rdi, rbx
    mov     esi, %2
    call    f32_to_str
    mov     rbx, rax
%endmacro
%macro APPEND_ABS 2                     ; a float local coordinate and its int32 origin (memory operands): the
    cvtss2sd xmm0, dword %1             ; absolute coordinate, 2 decimals (summed in double precision)
    cvtsi2sd xmm1, dword %2
    addsd   xmm0, xmm1
    cvtsd2ss xmm0, xmm0
    mov     rdi, rbx
    mov     esi, 2
    call    f32_to_str
    mov     rbx, rax
%endmacro
%macro EMIT_RGBA 1                      ; draw the finished line in the colour %1, start the next one
    mov     rdi, rbx
    mov     esi, r12d
    mov     edx, %1
    call    debug_emit
    inc     r12d
    lea     rbx, [dbg_buf]
%endmacro
%macro EMIT 0                           ; ... in white
    EMIT_RGBA WHITE
%endmacro

; hud_biome_name(edi biome) -> rax the name of that BIOME_* as a C string; "unknown" for any other value
; (-1 from world_biome_at: the column is not loaded) (leaf)
hud_biome_name:
    lea     rax, [s_unknown]
    cmp     edi, NUM_BIOMES
    jae     .ret
    lea     rcx, [biome_names]
    mov     rax, [rcx + rdi*8]
.ret:
    ret

; hud_debug(): the F3 lines (coordinates are absolute: local + world origin). rbx = write cursor,
; r12d = line; stack: [rsp] day, [rsp+4] hour, [rsp+8] minute, [rsp+12] xp to next level,
; [rsp+16] stream_stats: loaded, pending, lit, pool chunks
hud_debug:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 40
    xor     r12d, r12d
    lea     rbx, [dbg_buf]

    APPEND_STR s_dbg_title
    APPEND_INT [app_fps]
    APPEND_STR s_dbg_fps
    EMIT
    call    debug_is_cheater            ; the CHEATER line right under the title
    test    eax, eax
    jz      .not_cheater
    APPEND_STR s_cheater
    EMIT_RGBA C_CHEAT
.not_cheater:

    APPEND_STR s_xyz
    APPEND_ABS [player + BODY.x], [world_origin_x]
    APPEND_STR s_sep
    APPEND_F32 [player + BODY.y], 2
    APPEND_STR s_sep
    APPEND_ABS [player + BODY.z], [world_origin_z]
    EMIT

    APPEND_STR s_biome
    roundss xmm0, [player + BODY.x], 9
    cvttss2si edi, xmm0
    roundss xmm0, [player + BODY.z], 9
    cvttss2si esi, xmm0
    call    world_biome_at
    mov     edi, eax
    call    hud_biome_name              ; -1: the column is not loaded
    mov     rsi, rax
    mov     rdi, rbx
    call    str_append
    mov     rbx, rax
    EMIT

    lea     rdi, [rsp + 16]
    call    stream_stats
    APPEND_STR s_columns
    APPEND_INT [rsp + 16]
    APPEND_STR s_col_lit
    APPEND_INT [rsp + 24]
    APPEND_STR s_col_pend
    APPEND_INT [rsp + 20]
    APPEND_STR s_col_pool
    APPEND_INT [rsp + 28]
    APPEND_STR s_col_max
    EMIT

    APPEND_STR s_facing
    cvttss2si eax, [player + BODY.yaw]
    APPEND_EAX
    APPEND_STR s_pitch
    cvttss2si eax, [player + BODY.pitch]
    APPEND_EAX
    EMIT

    cmp     dword [game_has_target], 0
    jne     .has_target
    APPEND_STR s_none
    jmp     .target_done
.has_target:
    APPEND_STR s_target
    mov     edi, [game_target + RAYHIT.bx]
    mov     esi, [game_target + RAYHIT.by]
    mov     edx, [game_target + RAYHIT.bz]
    call    world_get
    cmp     eax, NUM_ITEMS
    jb      .named
    xor     eax, eax
.named:
    lea     rcx, [item_names]
    mov     rsi, [rcx + rax*8]
    mov     rdi, rbx
    call    str_append
    mov     rbx, rax
    APPEND_STR s_at
    mov     eax, [game_target + RAYHIT.bx]
    add     eax, [world_origin_x]
    APPEND_EAX
    APPEND_STR s_space
    APPEND_INT [game_target + RAYHIT.by]
    APPEND_STR s_space
    mov     eax, [game_target + RAYHIT.bz]
    add     eax, [world_origin_z]
    APPEND_EAX
.target_done:
    EMIT

    mov     eax, [game_time]            ; day number, and the clock: the day starts at 06:00
    xor     edx, edx
    mov     ecx, DAY_LENGTH
    div     ecx
    inc     eax
    mov     [rsp], eax
    mov     eax, edx
    xor     edx, edx
    mov     ecx, 50                     ; 72000 steps = 1440 minutes
    div     ecx
    xor     edx, edx
    mov     ecx, 60
    div     ecx
    mov     [rsp + 8], edx              ; minute
    add     eax, 6
    cmp     eax, 24
    jb      .hour_ok
    sub     eax, 24
.hour_ok:
    mov     [rsp + 4], eax              ; hour
    APPEND_STR s_mode
    lea     rsi, [s_survival]
    lea     rax, [s_creative]
    cmp     dword [game_mode], MODE_SURVIVAL
    cmovne  rsi, rax
    mov     rdi, rbx
    call    str_append
    mov     rbx, rax
    APPEND_STR s_day
    APPEND_INT [rsp]
    APPEND_STR s_space
    mov     edi, [rsp + 4]
    mov     rsi, rbx
    call    put2
    mov     rbx, rax
    APPEND_STR s_colon
    mov     edi, [rsp + 8]
    mov     rsi, rbx
    call    put2
    mov     rbx, rax
    EMIT

    APPEND_STR s_mobs
    mov     edi, 1
    call    mob_count_kind
    APPEND_EAX
    APPEND_STR s_hostile
    xor     edi, edi
    call    mob_count_kind
    APPEND_EAX
    APPEND_STR s_passive
    EMIT

    APPEND_STR s_light
    roundss xmm0, [player + BODY.x], 9  ; light of the cell the feet are in
    cvttss2si edi, xmm0
    movss   xmm1, [player + BODY.y]
    addss   xmm1, [f_feet_eps]
    roundss xmm1, xmm1, 9
    cvttss2si esi, xmm1
    roundss xmm2, [player + BODY.z], 9
    cvttss2si edx, xmm2
    call    light_get
    mov     r13d, eax
    shr     eax, 4
    APPEND_EAX                          ; sky
    APPEND_STR s_light_b
    mov     eax, r13d
    and     eax, 15
    APPEND_EAX                          ; block
    APPEND_STR s_light_d
    mov     edi, [game_time]
    call    sky_brightness
    mulss   xmm0, [f_100]
    cvttss2si eax, xmm0
    APPEND_EAX                          ; day brightness in percent
    APPEND_STR s_light_e
    EMIT

    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .archetype
    APPEND_STR s_health
    APPEND_INT [surv + SURVIVAL.health]
    APPEND_STR s_slash
    APPEND_INT [surv_max_health]
    APPEND_STR s_food
    APPEND_INT [surv + SURVIVAL.food]
    APPEND_STR s_sat
    APPEND_F32 [surv + SURVIVAL.saturation], 1
    EMIT

.archetype:
    APPEND_STR s_archetype
    call    rpg_title
    mov     rsi, rax
    mov     rdi, rbx
    call    str_append
    mov     rbx, rax
    APPEND_STR s_lv
    call    rpg_level
    mov     r13d, eax
    APPEND_EAX
    mov     edi, r13d
    call    rpg_xp_need
    test    eax, eax
    jz      .xp_max
    mov     [rsp + 12], eax
    APPEND_STR s_xp
    APPEND_INT [rpg_state + RPGSAVE.xp]
    APPEND_STR s_slash
    APPEND_INT [rsp + 12]
    jmp     .archetype_done
.xp_max:
    APPEND_STR s_xp_max
.archetype_done:
    EMIT

    APPEND_STR s_sites
    mov     edi, SITE_VILLAGE
    call    debug_site
    APPEND_STR s_site_d
    mov     edi, SITE_DUNGEON
    call    debug_site
    APPEND_STR s_site_c
    mov     edi, SITE_CRYPT
    call    debug_site
    EMIT

    APPEND_STR s_camp
    mov     edi, SITE_CAMP
    xor     esi, esi
    call    structures_nearest
    test    rax, rax
    jnz     .camp
    APPEND_STR s_site_none
    jmp     .camp_done
.camp:
    mov     r13, rax
    mov     eax, [r13 + SITE.index]
    cmp     eax, NUM_FACTIONS
    lea     rsi, [s_unknown]
    jae     .faction_named
    lea     rcx, [faction_names]
    mov     rsi, [rcx + rax*8]
.faction_named:
    mov     rdi, rbx
    call    str_append
    mov     rbx, rax
    APPEND_STR s_space
    mov     eax, [r13 + SITE.x]
    add     eax, [world_origin_x]
    APPEND_EAX
    APPEND_STR s_space
    mov     eax, [r13 + SITE.z]
    add     eax, [world_origin_z]
    APPEND_EAX
.camp_done:
    EMIT

    APPEND_STR s_standing
    xor     r13d, r13d
.standing:
    APPEND_STR s_space
    lea     rcx, [faction_short]
    mov     rsi, [rcx + r13*8]
    mov     rdi, rbx
    call    str_append
    mov     rbx, rax
    APPEND_STR s_space
    mov     edi, r13d
    call    faction_standing
    APPEND_EAX
    inc     r13d
    cmp     r13d, NUM_FACTIONS
    jb      .standing
    EMIT

    cmp     byte [net_role], NET_ROLE_OFF
    je      .no_net
    cmp     byte [net_role], NET_ROLE_HOST
    jne     .net_guest
    APPEND_STR s_net_host
    lea     rsi, [net_room_code]
    lea     rax, [s_dash]
    cmp     byte [rsi], 0
    cmove   rsi, rax                    ; "-" until the rendezvous server has given a code
    mov     rdi, rbx
    call    str_append
    mov     rbx, rax
    APPEND_STR s_net_peers
    call    hud_peer_rows
    dec     eax                         ; the guests: everyone but yourself
    APPEND_EAX
    APPEND_STR s_net_rx
    APPEND_INT [net_stat_block_rx]
    APPEND_STR s_net_tx
    APPEND_INT [net_stat_block_tx]
    jmp     .net_done
.net_guest:
    APPEND_STR s_net_guest
    movzx   eax, byte [net_self]
    APPEND_EAX
    APPEND_STR s_net_rtt
    lea     rdi, [net_ep]
    xor     esi, esi
    call    net_ep_rtt_ms               ; the link to the host
    APPEND_EAX
    APPEND_STR s_net_ms
    lea     rdi, [net_ep]
    xor     esi, esi
    call    net_ep_is_relay
    lea     rsi, [s_net_direct]
    lea     rcx, [s_net_relay]
    test    eax, eax
    cmovnz  rsi, rcx
    mov     rdi, rbx
    call    str_append
    mov     rbx, rax
.net_done:
    EMIT
.no_net:
    add     rsp, 40
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; debug_site(edi kind): "x,z" (absolute) of the nearest site of that kind (cleared or not) or
; "none", appended at the cursor rbx (updated)
debug_site:
    push    rbp
    mov     rbp, rsp
    push    r12
    sub     rsp, 8
    xor     esi, esi
    call    structures_nearest
    test    rax, rax
    jnz     .site
    APPEND_STR s_site_none
    jmp     .ret
.site:
    mov     r12, rax
    mov     eax, [r12 + SITE.x]
    add     eax, [world_origin_x]
    APPEND_EAX
    APPEND_STR s_comma
    mov     eax, [r12 + SITE.z]
    add     eax, [world_origin_z]
    APPEND_EAX
.ret:
    add     rsp, 8
    pop     r12
    pop     rbp
    ret
