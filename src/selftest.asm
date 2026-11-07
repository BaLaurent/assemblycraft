; selftest.asm - runs every registered test and prints a summary.
%include "common.inc"
default rel

global selftest_run

extern sys_print, i32_to_str, str_append
extern test_world_bounds, test_world_set_marks_dirty, test_world_save_load
extern test_world_load_v1_converts, test_world_load_v2_converts
extern test_worldgen_deterministic, test_worldgen_shape, test_worldgen_ores
extern test_mesh_single_block, test_mesh_adjacent_opaque, test_mesh_adjacent_leaves
extern test_mesh_adjacent_glass, test_mesh_chunk_boundary
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
    TEST worldgen_deterministic
    TEST worldgen_shape
    TEST worldgen_ores
    TEST mesh_single_block
    TEST mesh_adjacent_opaque
    TEST mesh_adjacent_leaves
    TEST mesh_adjacent_glass
    TEST mesh_chunk_boundary
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
    dq 0

section .rodata
    TESTNAME world_bounds
    TESTNAME world_set_marks_dirty
    TESTNAME world_save_load
    TESTNAME world_load_v1_converts
    TESTNAME world_load_v2_converts
    TESTNAME worldgen_deterministic
    TESTNAME worldgen_shape
    TESTNAME worldgen_ores
    TESTNAME mesh_single_block
    TESTNAME mesh_adjacent_opaque
    TESTNAME mesh_adjacent_leaves
    TESTNAME mesh_adjacent_glass
    TESTNAME mesh_chunk_boundary
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
