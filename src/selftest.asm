; selftest.asm - runs every registered test and prints a summary.
%include "common.inc"
default rel

global selftest_run

extern sys_print, i32_to_str, str_append
extern test_world_bounds, test_world_set_marks_dirty, test_world_save_load
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
extern test_vehicleview_default_key, test_vehicleview_roundtrip
extern test_vehicleview_missing_key, test_vehicleview_labels
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
extern test_rpg_levels_and_points, test_rpg_skill_spend_rules, test_rpg_stats_from_paths_and_ranks
extern test_rpg_save_load_validates, test_quest_chain_progress_and_rewards, test_trade_exchanges_items
extern test_guard_blocks_and_parries, test_dodge_iframes_and_stamina
extern test_melee_combo_crit_backstab, test_stamina_mana_regen_and_max_health
extern test_zombie_windup_can_be_parried, test_elite_saved_and_tougher, test_npc_hurt_and_not_saved
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
extern test_rpg_attributes_and_respec, test_rpg_keystones_and_caps
extern test_gear_decode_deterministic, test_gear_stats_and_powers
extern test_gear_drops_and_chests, test_gear_jewelry_and_no_wear
extern test_damage_pipeline, test_status_effects, test_heavy_attack_and_speed
extern test_player_statuses_and_defenses, test_new_abilities
extern test_mob_levels_and_scaling, test_elite_affixes
extern test_world_rebase, test_region_roundtrip, test_light_column_order, test_light_water
extern test_stream_sync, test_stream_thread
extern test_mesher_water, test_mesher_cross, test_render_frustum
extern test_worldgen_biomes, test_worldgen_column_independence, test_worldgen_spawn
extern test_worldgen_water_ice
extern test_sitestate_eviction, test_region_plan_camps
extern test_entities_rebase, test_entities_remove_box, test_containers_signed, test_mob_water_ai
extern test_swim_physics, test_breath_and_drowning, test_bed_place_and_break
extern test_sleep_rules, test_bed_respawn, test_boats
extern test_new_blocks_tables, test_shapes_new
extern test_game_rebase_trigger, test_saves_old_world_incompatible
extern test_faction_tiers_and_caps, test_faction_kill_and_rivals, test_shrine_tribute, test_trade_tables
extern test_folk_spawn_and_weapons, test_folk_targets_and_standing, test_folk_rivals_fight
extern test_folk_kill_reputation_and_drops, test_folk_projectiles, test_folk_interact_gates
extern test_folk_travellers, test_camp_built_with_slots, test_camp_npcs_recreated
extern test_roads_stamped, test_patrol_spawns_on_road, test_faction_save_load
extern test_shrine_and_folk_dispatch, test_shrine_block_tables
extern test_terrain_blocks_tables, test_mesher_lava
extern test_biome_ladder
extern test_lava_burns, test_new_biome_consumers
extern test_caves_reworked
extern test_grimoire_tiles
extern test_ui_nine_layout
extern test_ability_bar_binding, test_archetype_titles, test_web_view_mapping
extern test_sheet_sections
extern test_sfx_clean_edges, test_audio_pan, test_audio_caps_jitter_limiter
extern test_marksman_path_and_dex, test_marksman_abilities, test_bullet_damage_pipeline
extern test_planes_view
extern test_gun_attachment_effects, test_new_guns_fire, test_attach_craft
extern test_skill_arrows_ignore_hurt_window, test_grenade_and_rocket_blasts
extern test_debug_f12_detector, test_debug_cheater_mark_roundtrip, test_debug_world_list_flag
extern test_debug_give_items, test_debug_item_filter, test_debug_levels_and_points
extern test_debug_spawn_and_kill, test_debug_time_and_teleport, test_debug_stat_bonus
extern test_debug_vitals_and_toggles, test_debug_step_clock, test_debug_to_spawn_and_bed
extern test_net_reliable_lossy, test_net_big_message, test_net_rid_wrap, test_net_timeout
extern test_net_handshake_deny
extern test_net_long_rtt, test_net_event_queue_full
extern test_net_accept_then_data_one_poll
extern test_world_column_hash, test_stream_extra_centres, test_region_encode_roundtrip
extern test_stream_guest_local_until_joined
extern test_stream_pending_edit_columns
extern test_net_pos_roundtrip, test_net_player_image_roundtrip
extern test_world_delete_with_players, test_net_ready_resync, test_net_host_close_boats
extern test_net_cli_join_cleared, test_net_rejoin_takeover, test_net_wait_ends_with_session
extern test_net_early_data_before_accepted, test_net_join_timeout, test_net_wait_host_lost
extern test_net_cli_join_done
extern test_net_edit_queue_replay, test_net_column_verdict, test_net_container_put_seq
extern test_net_stale_verdict, test_net_block_overflow, test_net_cont_close_retry, test_net_fire_in_column
extern test_net_boat_double_mount, test_net_fire_guest_step, test_net_column_expiry, test_net_boat_giveback
extern test_net_edit_columns, test_net_plane_seats, test_net_plane_msgs, test_net_plane_pose
extern test_net_plane_rec, test_net_plane_leave, test_net_plane_crash, test_net_plane_place
extern test_net_mob_snapshot_apply, test_net_mob_target_nearest, test_net_guest_hit_forward
extern test_net_kill_credit, test_net_pvp_toggle
extern test_net_drop_slot63, test_net_kill_authority, test_net_fang_kill_reset, test_net_folk_provoker_kept
extern test_net_quest_shared, test_net_sleep_all, test_net_ghost_projectile
extern test_net_pvp_spells, test_net_quest_refund, test_net_proj_owner, test_net_relay_limit
extern test_net_spawn_per_centre, test_net_spawn_rotation
extern test_evsites_camp_site, test_evsites_route, test_evsites_site_of, test_evsites_hop
extern test_evsites_road_from
extern test_folk_event_targets, test_folk_caravan, test_mobs_event_march, test_arrows_event_monster
extern test_folk_defender_immune
extern test_hud_heading_dist, test_net_event_state, test_net_event_accept
extern test_events_wave_size, test_events_camp_flow, test_events_night_wave, test_events_leader_dies
extern test_events_abandon, test_events_monster_strike, test_events_caravan_flow, test_events_threat_flags
extern test_events_net
extern test_plane_recipes, test_plane_item_tables
extern test_planes_place, test_planes_takeoff, test_planes_stall, test_planes_landing
extern test_planes_crashes, test_planes_governor, test_planes_save_load, test_planes_leave
extern test_planes_camera, test_planes_seats, test_planes_roles, test_planes_water
extern test_planes_hum
extern test_gatling_cone, test_gatling_fire, test_gatling_seats

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
    TEST vehicleview_default_key
    TEST vehicleview_roundtrip
    TEST vehicleview_missing_key
    TEST vehicleview_labels
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
    TEST rpg_stats_from_paths_and_ranks
    TEST rpg_save_load_validates
    TEST quest_chain_progress_and_rewards
    TEST trade_exchanges_items
    TEST guard_blocks_and_parries
    TEST dodge_iframes_and_stamina
    TEST melee_combo_crit_backstab
    TEST stamina_mana_regen_and_max_health
    TEST zombie_windup_can_be_parried
    TEST elite_saved_and_tougher
    TEST npc_hurt_and_not_saved
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
    TEST world_rebase
    TEST region_roundtrip
    TEST light_column_order
    TEST light_water
    TEST stream_sync
    TEST stream_thread
    TEST mesher_water
    TEST mesher_cross
    TEST render_frustum
    TEST worldgen_biomes
    TEST worldgen_column_independence
    TEST worldgen_spawn
    TEST worldgen_water_ice
    TEST sitestate_eviction
    TEST region_plan_camps
    TEST entities_rebase
    TEST entities_remove_box
    TEST containers_signed
    TEST mob_water_ai
    TEST swim_physics
    TEST breath_and_drowning
    TEST bed_place_and_break
    TEST sleep_rules
    TEST bed_respawn
    TEST boats
    TEST new_blocks_tables
    TEST shapes_new
    TEST game_rebase_trigger
    TEST saves_old_world_incompatible
    TEST faction_tiers_and_caps
    TEST faction_kill_and_rivals
    TEST shrine_tribute
    TEST trade_tables
    TEST folk_spawn_and_weapons
    TEST folk_targets_and_standing
    TEST folk_rivals_fight
    TEST folk_kill_reputation_and_drops
    TEST folk_projectiles
    TEST folk_interact_gates
    TEST folk_travellers
    TEST camp_built_with_slots
    TEST camp_npcs_recreated
    TEST roads_stamped
    TEST patrol_spawns_on_road
    TEST faction_save_load
    TEST shrine_and_folk_dispatch
    TEST shrine_block_tables
    TEST terrain_blocks_tables
    TEST mesher_lava
    TEST biome_ladder
    TEST lava_burns
    TEST new_biome_consumers
    TEST caves_reworked
    TEST grimoire_tiles
    TEST ui_nine_layout
    TEST ability_bar_binding
    TEST archetype_titles
    TEST web_view_mapping
    TEST sheet_sections
    TEST sfx_clean_edges
    TEST audio_pan
    TEST audio_caps_jitter_limiter
    TEST marksman_path_and_dex
    TEST marksman_abilities
    TEST planes_view
    TEST bullet_damage_pipeline
    TEST gun_attachment_effects
    TEST new_guns_fire
    TEST attach_craft
    TEST skill_arrows_ignore_hurt_window
    TEST grenade_and_rocket_blasts
    TEST debug_f12_detector
    TEST debug_cheater_mark_roundtrip
    TEST debug_world_list_flag
    TEST debug_give_items
    TEST debug_item_filter
    TEST debug_levels_and_points
    TEST debug_spawn_and_kill
    TEST debug_time_and_teleport
    TEST debug_stat_bonus
    TEST debug_vitals_and_toggles
    TEST debug_step_clock
    TEST debug_to_spawn_and_bed
    TEST net_reliable_lossy
    TEST net_big_message
    TEST net_rid_wrap
    TEST net_timeout
    TEST net_handshake_deny
    TEST net_long_rtt
    TEST net_event_queue_full
    TEST net_accept_then_data_one_poll
    TEST world_column_hash
    TEST stream_extra_centres
    TEST region_encode_roundtrip
    TEST stream_guest_local_until_joined
    TEST stream_pending_edit_columns
    TEST net_pos_roundtrip
    TEST net_player_image_roundtrip
    TEST world_delete_with_players
    TEST net_ready_resync
    TEST net_host_close_boats
    TEST net_cli_join_cleared
    TEST net_rejoin_takeover
    TEST net_wait_ends_with_session
    TEST net_early_data_before_accepted
    TEST net_join_timeout
    TEST net_wait_host_lost
    TEST net_cli_join_done
    TEST net_edit_queue_replay
    TEST net_column_verdict
    TEST net_container_put_seq
    TEST net_stale_verdict
    TEST net_block_overflow
    TEST net_cont_close_retry
    TEST net_fire_in_column
    TEST net_boat_double_mount
    TEST net_fire_guest_step
    TEST net_column_expiry
    TEST net_boat_giveback
    TEST net_edit_columns
    TEST net_plane_seats
    TEST net_plane_msgs
    TEST net_plane_pose
    TEST net_plane_rec
    TEST net_plane_leave
    TEST net_plane_crash
    TEST net_plane_place
    TEST net_mob_snapshot_apply
    TEST net_mob_target_nearest
    TEST net_guest_hit_forward
    TEST net_kill_credit
    TEST net_pvp_toggle
    TEST net_drop_slot63
    TEST net_kill_authority
    TEST net_fang_kill_reset
    TEST net_folk_provoker_kept
    TEST net_quest_shared
    TEST net_sleep_all
    TEST net_ghost_projectile
    TEST net_pvp_spells
    TEST net_quest_refund
    TEST net_proj_owner
    TEST net_relay_limit
    TEST net_spawn_per_centre
    TEST net_spawn_rotation
    TEST evsites_camp_site
    TEST evsites_route
    TEST evsites_site_of
    TEST evsites_hop
    TEST evsites_road_from
    TEST folk_event_targets
    TEST folk_caravan
    TEST mobs_event_march
    TEST arrows_event_monster
    TEST folk_defender_immune
    TEST hud_heading_dist
    TEST net_event_state
    TEST net_event_accept
    TEST events_wave_size
    TEST events_camp_flow
    TEST events_night_wave
    TEST events_leader_dies
    TEST events_abandon
    TEST events_monster_strike
    TEST events_caravan_flow
    TEST events_threat_flags
    TEST events_net
    TEST plane_recipes
    TEST plane_item_tables
    TEST planes_place
    TEST planes_takeoff
    TEST planes_stall
    TEST planes_landing
    TEST planes_crashes
    TEST planes_governor
    TEST planes_save_load
    TEST planes_leave
    TEST planes_camera
    TEST planes_hum
    TEST gatling_cone
    TEST gatling_fire
    TEST gatling_seats
    TEST planes_seats
    TEST planes_roles
    TEST planes_water
    dq 0

section .rodata
    TESTNAME world_bounds
    TESTNAME world_set_marks_dirty
    TESTNAME world_save_load
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
    TESTNAME vehicleview_default_key
    TESTNAME vehicleview_roundtrip
    TESTNAME vehicleview_missing_key
    TESTNAME vehicleview_labels
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
    TESTNAME rpg_stats_from_paths_and_ranks
    TESTNAME rpg_save_load_validates
    TESTNAME quest_chain_progress_and_rewards
    TESTNAME trade_exchanges_items
    TESTNAME guard_blocks_and_parries
    TESTNAME dodge_iframes_and_stamina
    TESTNAME melee_combo_crit_backstab
    TESTNAME stamina_mana_regen_and_max_health
    TESTNAME zombie_windup_can_be_parried
    TESTNAME elite_saved_and_tougher
    TESTNAME npc_hurt_and_not_saved
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
    TESTNAME world_rebase
    TESTNAME region_roundtrip
    TESTNAME light_column_order
    TESTNAME light_water
    TESTNAME stream_sync
    TESTNAME stream_thread
    TESTNAME mesher_water
    TESTNAME mesher_cross
    TESTNAME render_frustum
    TESTNAME worldgen_biomes
    TESTNAME worldgen_column_independence
    TESTNAME worldgen_spawn
    TESTNAME worldgen_water_ice
    TESTNAME sitestate_eviction
    TESTNAME region_plan_camps
    TESTNAME entities_rebase
    TESTNAME entities_remove_box
    TESTNAME containers_signed
    TESTNAME mob_water_ai
    TESTNAME swim_physics
    TESTNAME breath_and_drowning
    TESTNAME bed_place_and_break
    TESTNAME sleep_rules
    TESTNAME bed_respawn
    TESTNAME boats
    TESTNAME new_blocks_tables
    TESTNAME shapes_new
    TESTNAME game_rebase_trigger
    TESTNAME saves_old_world_incompatible
    TESTNAME faction_tiers_and_caps
    TESTNAME faction_kill_and_rivals
    TESTNAME shrine_tribute
    TESTNAME trade_tables
    TESTNAME folk_spawn_and_weapons
    TESTNAME folk_targets_and_standing
    TESTNAME folk_rivals_fight
    TESTNAME folk_kill_reputation_and_drops
    TESTNAME folk_projectiles
    TESTNAME folk_interact_gates
    TESTNAME folk_travellers
    TESTNAME camp_built_with_slots
    TESTNAME camp_npcs_recreated
    TESTNAME roads_stamped
    TESTNAME patrol_spawns_on_road
    TESTNAME faction_save_load
    TESTNAME shrine_and_folk_dispatch
    TESTNAME shrine_block_tables
    TESTNAME terrain_blocks_tables
    TESTNAME mesher_lava
    TESTNAME biome_ladder
    TESTNAME lava_burns
    TESTNAME new_biome_consumers
    TESTNAME caves_reworked
    TESTNAME grimoire_tiles
    TESTNAME ui_nine_layout
    TESTNAME ability_bar_binding
    TESTNAME archetype_titles
    TESTNAME web_view_mapping
    TESTNAME sheet_sections
    TESTNAME sfx_clean_edges
    TESTNAME audio_pan
    TESTNAME audio_caps_jitter_limiter
    TESTNAME marksman_path_and_dex
    TESTNAME marksman_abilities
    TESTNAME planes_view
    TESTNAME bullet_damage_pipeline
    TESTNAME gun_attachment_effects
    TESTNAME new_guns_fire
    TESTNAME attach_craft
    TESTNAME skill_arrows_ignore_hurt_window
    TESTNAME grenade_and_rocket_blasts
    TESTNAME debug_f12_detector
    TESTNAME debug_cheater_mark_roundtrip
    TESTNAME debug_world_list_flag
    TESTNAME debug_give_items
    TESTNAME debug_item_filter
    TESTNAME debug_levels_and_points
    TESTNAME debug_spawn_and_kill
    TESTNAME debug_time_and_teleport
    TESTNAME debug_stat_bonus
    TESTNAME debug_vitals_and_toggles
    TESTNAME debug_step_clock
    TESTNAME debug_to_spawn_and_bed
    TESTNAME net_reliable_lossy
    TESTNAME net_big_message
    TESTNAME net_rid_wrap
    TESTNAME net_timeout
    TESTNAME net_handshake_deny
    TESTNAME net_long_rtt
    TESTNAME net_event_queue_full
    TESTNAME net_accept_then_data_one_poll
    TESTNAME world_column_hash
    TESTNAME stream_extra_centres
    TESTNAME region_encode_roundtrip
    TESTNAME stream_guest_local_until_joined
    TESTNAME stream_pending_edit_columns
    TESTNAME net_pos_roundtrip
    TESTNAME net_player_image_roundtrip
    TESTNAME world_delete_with_players
    TESTNAME net_ready_resync
    TESTNAME net_host_close_boats
    TESTNAME net_cli_join_cleared
    TESTNAME net_rejoin_takeover
    TESTNAME net_wait_ends_with_session
    TESTNAME net_early_data_before_accepted
    TESTNAME net_join_timeout
    TESTNAME net_wait_host_lost
    TESTNAME net_cli_join_done
    TESTNAME net_edit_queue_replay
    TESTNAME net_column_verdict
    TESTNAME net_container_put_seq
    TESTNAME net_stale_verdict
    TESTNAME net_block_overflow
    TESTNAME net_cont_close_retry
    TESTNAME net_fire_in_column
    TESTNAME net_boat_double_mount
    TESTNAME net_fire_guest_step
    TESTNAME net_column_expiry
    TESTNAME net_boat_giveback
    TESTNAME net_edit_columns
    TESTNAME net_plane_seats
    TESTNAME net_plane_msgs
    TESTNAME net_plane_pose
    TESTNAME net_plane_rec
    TESTNAME net_plane_leave
    TESTNAME net_plane_crash
    TESTNAME net_plane_place
    TESTNAME net_mob_snapshot_apply
    TESTNAME net_mob_target_nearest
    TESTNAME net_guest_hit_forward
    TESTNAME net_kill_credit
    TESTNAME net_pvp_toggle
    TESTNAME net_drop_slot63
    TESTNAME net_kill_authority
    TESTNAME net_fang_kill_reset
    TESTNAME net_folk_provoker_kept
    TESTNAME net_quest_shared
    TESTNAME net_sleep_all
    TESTNAME net_ghost_projectile
    TESTNAME net_pvp_spells
    TESTNAME net_quest_refund
    TESTNAME net_proj_owner
    TESTNAME net_relay_limit
    TESTNAME net_spawn_per_centre
    TESTNAME net_spawn_rotation
    TESTNAME evsites_camp_site
    TESTNAME evsites_route
    TESTNAME evsites_site_of
    TESTNAME evsites_hop
    TESTNAME evsites_road_from
    TESTNAME folk_event_targets
    TESTNAME folk_caravan
    TESTNAME mobs_event_march
    TESTNAME arrows_event_monster
    TESTNAME folk_defender_immune
    TESTNAME hud_heading_dist
    TESTNAME net_event_state
    TESTNAME net_event_accept
    TESTNAME events_wave_size
    TESTNAME events_camp_flow
    TESTNAME events_night_wave
    TESTNAME events_leader_dies
    TESTNAME events_abandon
    TESTNAME events_monster_strike
    TESTNAME events_caravan_flow
    TESTNAME events_threat_flags
    TESTNAME events_net
    TESTNAME plane_recipes
    TESTNAME plane_item_tables
    TESTNAME planes_place
    TESTNAME planes_takeoff
    TESTNAME planes_stall
    TESTNAME planes_landing
    TESTNAME planes_crashes
    TESTNAME planes_governor
    TESTNAME planes_save_load
    TESTNAME planes_leave
    TESTNAME planes_camera
    TESTNAME planes_hum
    TESTNAME gatling_cone
    TESTNAME gatling_fire
    TESTNAME gatling_seats
    TESTNAME planes_seats
    TESTNAME planes_roles
    TESTNAME planes_water
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
