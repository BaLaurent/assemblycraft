; selftest.asm - runs every registered test and prints a summary.
%include "common.inc"
default rel

global selftest_run

extern sys_print, i32_to_str, str_append
extern test_world_bounds, test_world_set_marks_dirty, test_world_save_load
extern test_world_load_v1_converts, test_world_load_v2_converts, test_world_load_v3_migrates_items
extern test_worldgen_deterministic, test_worldgen_shape, test_worldgen_ores
extern test_mesh_single_block, test_mesh_adjacent_opaque, test_mesh_adjacent_leaves
extern test_mesh_adjacent_glass, test_mesh_chunk_boundary
extern test_mesh_slab_half_height, test_mesh_stairs_quads, test_mesh_light_packed
extern test_raycast_hit_forward, test_raycast_miss_beyond_reach, test_raycast_hit_from_above
extern test_physics_land_on_floor, test_physics_wall_blocks
extern test_physics_jump_clears_one_block, test_body_intersects_block
extern test_inv_add_merges, test_inv_right_click_split, test_craft_planks_from_log
extern test_craft_tool_shapes, test_craft_shift_click_all, test_break_time_rules
extern test_fall_damage, test_exhaustion_drains, test_regen_when_fed
extern test_damage_invulnerability, test_starvation_floor, test_sky_day_cycle
extern test_armor_reduces_damage
extern test_saves_sanitize_name, test_saves_scan_rename_delete
extern test_settings_roundtrip, test_settings_clamps_bad_values, test_settings_reload_key
extern test_craft_advanced_recipes, test_break_tiers, test_inv_click_armor_containers
extern test_recipe_fill_and_sets, test_recipe_fits_grid, test_furnace_book_fill
extern test_furnace_smelts, test_chest_spills_on_break
extern test_mob_raycast_hits, test_mob_hurt_pig_drops_food, test_zombie_attacks_player
extern test_mob_spawn_rules, test_game_save_load_roundtrip, test_drops_fall_and_pickup
extern test_arrow_hits_mob, test_explosion_breaks_blocks, test_creeper_explodes
extern test_skeleton_shoots_player, test_mob_drops_by_type
extern test_gun_reload_fills_magazine, test_gun_fire_cooldown_and_dry
extern test_shotgun_spawns_six_pellets, test_bullet_hits_mob_and_stops
extern test_rocket_explodes_on_impact, test_rifle_kills_zombie_point_blank
extern test_aimed_shotgun_has_no_spread, test_tnt_thrown_by_blast, test_tnt_falls
extern test_fire_spreads_and_burns_wood, test_fire_ignites_tnt
extern test_fire_dies_on_stone, test_fire_hurts_player
extern test_fx_explosion_spawns_and_expires, test_fx_debris_falls_and_bounces
extern test_rpg_levels_and_points, test_rpg_skill_spend_rules, test_rpg_stats_from_class_and_ranks
extern test_rpg_save_load_validates, test_quest_chain_progress_and_rewards, test_trade_exchanges_items
extern test_guard_blocks_and_parries, test_dodge_iframes_and_stamina
extern test_melee_combo_crit_backstab, test_stamina_mana_regen_and_max_health
extern test_zombie_windup_can_be_parried, test_elite_saved_and_tougher, test_npc_immune_and_not_saved
extern test_boss_phases_slam_and_summons, test_mob_kill_awards_xp_and_coins
extern test_structure_sites_deterministic, test_dungeon_built_with_chests
extern test_village_built_with_npcs, test_dungeon_clears_after_kills, test_crypt_spawns_boss_once
extern test_world_to_ui_centres_forward, test_dmgnum_rises_and_expires
extern test_ability_cost_cooldown_and_unlock, test_fireball_explodes_without_breaking
extern test_blink_stops_before_wall, test_volley_and_arrow_rain_spawn
extern test_shapes_boxes
extern test_light_sky_and_shadow, test_torch_light_falloff, test_light_update_on_change, test_light_lut
extern test_step_up_slab_not_block, test_stairs_then_block, test_door_blocks_until_opened
extern test_ladder_climb, test_fence_cannot_jump, test_place_variants
extern test_door_break_removes_pair_and_support, test_raycast_shapes
extern test_world_load_v4_converts
extern test_rpg_attributes_and_respec, test_rpg_keystones_and_caps
extern test_gear_decode_deterministic, test_gear_stats_and_powers
extern test_gear_drops_and_chests, test_gear_jewelry_and_no_wear
extern test_damage_pipeline, test_status_effects, test_heavy_attack_and_speed
extern test_player_statuses_and_defenses, test_new_abilities
extern test_mob_levels_and_scaling, test_elite_affixes

%macro TEST 1
    dq test_%1, name_%1
%endmacro
%macro TESTNAME 1
    name_%1: db %str(%1), 0
%endmacro

section .data
align 8
tests:
    TEST world_bounds
    TEST world_set_marks_dirty
    TEST world_save_load
    TEST world_load_v1_converts
    TEST world_load_v2_converts
    TEST world_load_v3_migrates_items
    TEST worldgen_deterministic
    TEST worldgen_shape
    TEST worldgen_ores
    TEST mesh_single_block
    TEST mesh_adjacent_opaque
    TEST mesh_adjacent_leaves
    TEST mesh_adjacent_glass
    TEST mesh_chunk_boundary
    TEST mesh_slab_half_height
    TEST mesh_stairs_quads
    TEST mesh_light_packed
    TEST raycast_hit_forward
    TEST raycast_miss_beyond_reach
    TEST raycast_hit_from_above
    TEST physics_land_on_floor
    TEST physics_wall_blocks
    TEST physics_jump_clears_one_block
    TEST body_intersects_block
    TEST inv_add_merges
    TEST inv_right_click_split
    TEST craft_planks_from_log
    TEST craft_tool_shapes
    TEST craft_shift_click_all
    TEST break_time_rules
    TEST craft_advanced_recipes
    TEST break_tiers
    TEST inv_click_armor_containers
    TEST recipe_fill_and_sets
    TEST recipe_fits_grid
    TEST furnace_book_fill
    TEST fall_damage
    TEST exhaustion_drains
    TEST regen_when_fed
    TEST damage_invulnerability
    TEST starvation_floor
    TEST sky_day_cycle
    TEST armor_reduces_damage
    TEST saves_sanitize_name
    TEST saves_scan_rename_delete
    TEST settings_roundtrip
    TEST settings_clamps_bad_values
    TEST settings_reload_key
    TEST furnace_smelts
    TEST chest_spills_on_break
    TEST mob_raycast_hits
    TEST mob_hurt_pig_drops_food
    TEST zombie_attacks_player
    TEST mob_spawn_rules
    TEST arrow_hits_mob
    TEST explosion_breaks_blocks
    TEST creeper_explodes
    TEST skeleton_shoots_player
    TEST mob_drops_by_type
    TEST gun_reload_fills_magazine
    TEST gun_fire_cooldown_and_dry
    TEST shotgun_spawns_six_pellets
    TEST bullet_hits_mob_and_stops
    TEST rocket_explodes_on_impact
    TEST rifle_kills_zombie_point_blank
    TEST aimed_shotgun_has_no_spread
    TEST tnt_thrown_by_blast
    TEST tnt_falls
    TEST fire_spreads_and_burns_wood
    TEST fire_ignites_tnt
    TEST fire_dies_on_stone
    TEST fire_hurts_player
    TEST fx_explosion_spawns_and_expires
    TEST fx_debris_falls_and_bounces
    TEST game_save_load_roundtrip
    TEST drops_fall_and_pickup
    TEST rpg_levels_and_points
    TEST rpg_skill_spend_rules
    TEST rpg_stats_from_class_and_ranks
    TEST rpg_save_load_validates
    TEST quest_chain_progress_and_rewards
    TEST trade_exchanges_items
    TEST guard_blocks_and_parries
    TEST dodge_iframes_and_stamina
    TEST melee_combo_crit_backstab
    TEST stamina_mana_regen_and_max_health
    TEST zombie_windup_can_be_parried
    TEST elite_saved_and_tougher
    TEST npc_immune_and_not_saved
    TEST boss_phases_slam_and_summons
    TEST mob_kill_awards_xp_and_coins
    TEST structure_sites_deterministic
    TEST dungeon_built_with_chests
    TEST village_built_with_npcs
    TEST dungeon_clears_after_kills
    TEST crypt_spawns_boss_once
    TEST world_to_ui_centres_forward
    TEST dmgnum_rises_and_expires
    TEST ability_cost_cooldown_and_unlock
    TEST fireball_explodes_without_breaking
    TEST blink_stops_before_wall
    TEST volley_and_arrow_rain_spawn
    TEST shapes_boxes
    TEST light_sky_and_shadow
    TEST torch_light_falloff
    TEST light_update_on_change
    TEST light_lut
    TEST step_up_slab_not_block
    TEST stairs_then_block
    TEST door_blocks_until_opened
    TEST ladder_climb
    TEST fence_cannot_jump
    TEST place_variants
    TEST door_break_removes_pair_and_support
    TEST raycast_shapes
    TEST world_load_v4_converts
    TEST rpg_attributes_and_respec
    TEST rpg_keystones_and_caps
    TEST gear_decode_deterministic
    TEST gear_stats_and_powers
    TEST gear_drops_and_chests
    TEST gear_jewelry_and_no_wear
    TEST damage_pipeline
    TEST status_effects
    TEST heavy_attack_and_speed
    TEST player_statuses_and_defenses
    TEST new_abilities
    TEST mob_levels_and_scaling
    TEST elite_affixes
    dq 0

section .rodata
    TESTNAME world_bounds
    TESTNAME world_set_marks_dirty
    TESTNAME world_save_load
    TESTNAME world_load_v1_converts
    TESTNAME world_load_v2_converts
    TESTNAME world_load_v3_migrates_items
    TESTNAME worldgen_deterministic
    TESTNAME worldgen_shape
    TESTNAME worldgen_ores
    TESTNAME mesh_single_block
    TESTNAME mesh_adjacent_opaque
    TESTNAME mesh_adjacent_leaves
    TESTNAME mesh_adjacent_glass
    TESTNAME mesh_chunk_boundary
    TESTNAME mesh_slab_half_height
    TESTNAME mesh_stairs_quads
    TESTNAME mesh_light_packed
    TESTNAME raycast_hit_forward
    TESTNAME raycast_miss_beyond_reach
    TESTNAME raycast_hit_from_above
    TESTNAME physics_land_on_floor
    TESTNAME physics_wall_blocks
    TESTNAME physics_jump_clears_one_block
    TESTNAME body_intersects_block
    TESTNAME inv_add_merges
    TESTNAME inv_right_click_split
    TESTNAME craft_planks_from_log
    TESTNAME craft_tool_shapes
    TESTNAME craft_shift_click_all
    TESTNAME break_time_rules
    TESTNAME craft_advanced_recipes
    TESTNAME break_tiers
    TESTNAME inv_click_armor_containers
    TESTNAME recipe_fill_and_sets
    TESTNAME recipe_fits_grid
    TESTNAME furnace_book_fill
    TESTNAME fall_damage
    TESTNAME exhaustion_drains
    TESTNAME regen_when_fed
    TESTNAME damage_invulnerability
    TESTNAME starvation_floor
    TESTNAME sky_day_cycle
    TESTNAME armor_reduces_damage
    TESTNAME saves_sanitize_name
    TESTNAME saves_scan_rename_delete
    TESTNAME settings_roundtrip
    TESTNAME settings_clamps_bad_values
    TESTNAME settings_reload_key
    TESTNAME furnace_smelts
    TESTNAME chest_spills_on_break
    TESTNAME mob_raycast_hits
    TESTNAME mob_hurt_pig_drops_food
    TESTNAME zombie_attacks_player
    TESTNAME mob_spawn_rules
    TESTNAME arrow_hits_mob
    TESTNAME explosion_breaks_blocks
    TESTNAME creeper_explodes
    TESTNAME skeleton_shoots_player
    TESTNAME mob_drops_by_type
    TESTNAME gun_reload_fills_magazine
    TESTNAME gun_fire_cooldown_and_dry
    TESTNAME shotgun_spawns_six_pellets
    TESTNAME bullet_hits_mob_and_stops
    TESTNAME rocket_explodes_on_impact
    TESTNAME rifle_kills_zombie_point_blank
    TESTNAME aimed_shotgun_has_no_spread
    TESTNAME tnt_thrown_by_blast
    TESTNAME tnt_falls
    TESTNAME fire_spreads_and_burns_wood
    TESTNAME fire_ignites_tnt
    TESTNAME fire_dies_on_stone
    TESTNAME fire_hurts_player
    TESTNAME fx_explosion_spawns_and_expires
    TESTNAME fx_debris_falls_and_bounces
    TESTNAME game_save_load_roundtrip
    TESTNAME drops_fall_and_pickup
    TESTNAME rpg_levels_and_points
    TESTNAME rpg_skill_spend_rules
    TESTNAME rpg_stats_from_class_and_ranks
    TESTNAME rpg_save_load_validates
    TESTNAME quest_chain_progress_and_rewards
    TESTNAME trade_exchanges_items
    TESTNAME guard_blocks_and_parries
    TESTNAME dodge_iframes_and_stamina
    TESTNAME melee_combo_crit_backstab
    TESTNAME stamina_mana_regen_and_max_health
    TESTNAME zombie_windup_can_be_parried
    TESTNAME elite_saved_and_tougher
    TESTNAME npc_immune_and_not_saved
    TESTNAME boss_phases_slam_and_summons
    TESTNAME mob_kill_awards_xp_and_coins
    TESTNAME structure_sites_deterministic
    TESTNAME dungeon_built_with_chests
    TESTNAME village_built_with_npcs
    TESTNAME dungeon_clears_after_kills
    TESTNAME crypt_spawns_boss_once
    TESTNAME world_to_ui_centres_forward
    TESTNAME dmgnum_rises_and_expires
    TESTNAME ability_cost_cooldown_and_unlock
    TESTNAME fireball_explodes_without_breaking
    TESTNAME blink_stops_before_wall
    TESTNAME volley_and_arrow_rain_spawn
    TESTNAME shapes_boxes
    TESTNAME light_sky_and_shadow
    TESTNAME torch_light_falloff
    TESTNAME light_update_on_change
    TESTNAME light_lut
    TESTNAME step_up_slab_not_block
    TESTNAME stairs_then_block
    TESTNAME door_blocks_until_opened
    TESTNAME ladder_climb
    TESTNAME fence_cannot_jump
    TESTNAME place_variants
    TESTNAME door_break_removes_pair_and_support
    TESTNAME raycast_shapes
    TESTNAME world_load_v4_converts
    TESTNAME rpg_attributes_and_respec
    TESTNAME rpg_keystones_and_caps
    TESTNAME gear_decode_deterministic
    TESTNAME gear_stats_and_powers
    TESTNAME gear_drops_and_chests
    TESTNAME gear_jewelry_and_no_wear
    TESTNAME damage_pipeline
    TESTNAME status_effects
    TESTNAME heavy_attack_and_speed
    TESTNAME player_statuses_and_defenses
    TESTNAME new_abilities
    TESTNAME mob_levels_and_scaling
    TESTNAME elite_affixes
s_ok:     db "ok ", 0
s_fail:   db "FAIL ", 0
s_nl:     db 10, 0
s_head:   db "selftest: ", 0
s_passed: db " passed, ", 0
s_failed: db " failed", 10, 0

section .bss
line: resb 128

section .text

; selftest_run() -> eax 0 iff every test passed
selftest_run:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    lea     rbx, [tests]
    xor     r12d, r12d                  ; passed
    xor     r13d, r13d                  ; failed
.next:
    mov     rax, [rbx]
    test    rax, rax
    jz      .summary
    call    rax
    lea     rsi, [s_ok]
    test    eax, eax
    jz      .pass
    inc     r13d
    lea     rsi, [s_fail]
    jmp     .print
.pass:
    inc     r12d
.print:
    mov     edi, 1
    call    sys_print
    mov     edi, 1
    mov     rsi, [rbx + 8]
    call    sys_print
    mov     edi, 1
    lea     rsi, [s_nl]
    call    sys_print
    add     rbx, 16
    jmp     .next
.summary:
    lea     rdi, [line]
    lea     rsi, [s_head]
    call    str_append
    mov     edi, r12d
    mov     rsi, rax
    call    i32_to_str
    mov     rdi, rax
    lea     rsi, [s_passed]
    call    str_append
    mov     edi, r13d
    mov     rsi, rax
    call    i32_to_str
    mov     rdi, rax
    lea     rsi, [s_failed]
    call    str_append
    mov     byte [rax], 0
    mov     edi, 1
    lea     rsi, [line]
    call    sys_print
    xor     eax, eax
    test    r13d, r13d
    setnz   al
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
