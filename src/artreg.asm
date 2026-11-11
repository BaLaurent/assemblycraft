; artreg.asm - the two registries of the 0.13 "looks" art.
;   skin_models   every skin model skin_build packs into the atlas and paints, 0-terminated. The registry order
;                 is the packing order. The models: skins_mobs.asm (the 7 mobs), skins_folk.asm (the folk, the
;                 elder, the merchant, the player avatar, the role extras and the hoods), skins_gear.asm (the
;                 guns and the rocket) and skins_vehicles.asm (the boat, the plane and its propeller).
;   item_icons32  the 32x32 icon bitmap (SKBMP*) of every item, in item id order from STICK to the last rune: what
;                 icons_build paints into the icon cells of the atlas. The bitmaps are iconart_a.asm (the 62
;                 equipment icons), iconart_b.asm (the 31 others) and iconart_runes.asm (the 16 Rune items), labelled
;                 ib_ + the lower-case item constant (ib_rune_<name> for the runes).
; render_init hands both tables to the engines; test_skin_models and test_icons_art prove them.
%include "common.inc"
default rel

global skin_models, item_icons32

extern m_zombie, m_skeleton, m_creeper, m_spider, m_pig, m_chicken, m_boss
extern m_folk_villagers, m_folk_bandits, m_folk_cult, m_folk_beastfolk, m_folk_stonekin, m_villager_elder, m_villager_merchant, m_avatar
extern m_extra_hat, m_extra_helmet, m_extra_pack, m_extra_crown, m_hood_villagers, m_hood_bandits, m_hood_cult, m_hood_beastfolk, m_hood_stonekin
extern m_gun_pistol, m_gun_musket, m_gun_shotgun, m_gun_rifle, m_gun_launcher, m_gun_warhead, m_gun_revolver, m_gun_hrifle
extern m_boat, m_plane, m_plane_prop
extern ib_stick, ib_wood_pickaxe, ib_wood_axe, ib_wood_shovel, ib_wood_sword, ib_stone_pickaxe, ib_stone_axe, ib_stone_shovel
extern ib_stone_sword, ib_apple, ib_porkchop, ib_coal, ib_iron_ingot, ib_gold_ingot, ib_diamond, ib_iron_pickaxe
extern ib_iron_axe, ib_iron_shovel, ib_iron_sword, ib_gold_pickaxe, ib_gold_axe, ib_gold_shovel, ib_gold_sword, ib_diamond_pickaxe
extern ib_diamond_axe, ib_diamond_shovel, ib_diamond_sword, ib_bow, ib_arrow, ib_string, ib_gunpowder, ib_flint
extern ib_flint_and_steel, ib_rotten_flesh, ib_cooked_porkchop, ib_feather, ib_raw_chicken, ib_cooked_chicken, ib_iron_helmet, ib_iron_chestplate
extern ib_iron_leggings, ib_iron_boots, ib_gold_helmet, ib_gold_chestplate, ib_gold_leggings, ib_gold_boots, ib_diamond_helmet, ib_diamond_chestplate
extern ib_diamond_leggings, ib_diamond_boots, ib_pistol, ib_musket, ib_shotgun, ib_kalashnikov, ib_rocket_launcher, ib_pistol_round
extern ib_musket_ball, ib_shotgun_shell, ib_rifle_round, ib_rocket, ib_staff, ib_archmage_staff, ib_iron_dagger, ib_diamond_dagger
extern ib_shadow_fang, ib_kings_blade, ib_celestial_bow, ib_health_potion, ib_mana_potion, ib_gold_coin, ib_ring, ib_amulet
extern ib_phoenix_ring, ib_storm_band, ib_ember_amulet, ib_viper_amulet, ib_iron_hammer, ib_diamond_hammer, ib_iron_spear, ib_diamond_spear
extern ib_boat, ib_revolver, ib_hunting_rifle, ib_scope, ib_extended_mag, ib_rifled_barrel, ib_compensator, ib_plane_engine
extern ib_plane_wing, ib_plane_fuselage, ib_plane_prop, ib_plane_tail, ib_plane
extern ib_rune_ball, ib_rune_laser, ib_rune_nova, ib_rune_phase, ib_rune_dash, ib_rune_fire, ib_rune_frost, ib_rune_shock
extern ib_rune_poison, ib_rune_burst, ib_rune_pierce, ib_rune_seek, ib_rune_chain, ib_rune_heal, ib_rune_haste, ib_rune_feather

section .rodata
align 8
skin_models:
    dq m_zombie, m_skeleton, m_creeper, m_spider, m_pig, m_chicken, m_boss
    dq m_folk_villagers, m_folk_bandits, m_folk_cult, m_folk_beastfolk, m_folk_stonekin
    dq m_villager_elder, m_villager_merchant, m_avatar
    dq m_extra_hat, m_extra_helmet, m_extra_pack, m_extra_crown
    dq m_hood_villagers, m_hood_bandits, m_hood_cult, m_hood_beastfolk, m_hood_stonekin
    dq m_gun_pistol, m_gun_musket, m_gun_shotgun, m_gun_rifle, m_gun_launcher, m_gun_warhead, m_gun_revolver, m_gun_hrifle
    dq m_boat, m_plane, m_plane_prop
    dq 0

item_icons32:
    dq ib_stick, ib_wood_pickaxe, ib_wood_axe, ib_wood_shovel
    dq ib_wood_sword, ib_stone_pickaxe, ib_stone_axe, ib_stone_shovel
    dq ib_stone_sword, ib_apple, ib_porkchop, ib_coal
    dq ib_iron_ingot, ib_gold_ingot, ib_diamond, ib_iron_pickaxe
    dq ib_iron_axe, ib_iron_shovel, ib_iron_sword, ib_gold_pickaxe
    dq ib_gold_axe, ib_gold_shovel, ib_gold_sword, ib_diamond_pickaxe
    dq ib_diamond_axe, ib_diamond_shovel, ib_diamond_sword, ib_bow
    dq ib_arrow, ib_string, ib_gunpowder, ib_flint
    dq ib_flint_and_steel, ib_rotten_flesh, ib_cooked_porkchop, ib_feather
    dq ib_raw_chicken, ib_cooked_chicken, ib_iron_helmet, ib_iron_chestplate
    dq ib_iron_leggings, ib_iron_boots, ib_gold_helmet, ib_gold_chestplate
    dq ib_gold_leggings, ib_gold_boots, ib_diamond_helmet, ib_diamond_chestplate
    dq ib_diamond_leggings, ib_diamond_boots, ib_pistol, ib_musket
    dq ib_shotgun, ib_kalashnikov, ib_rocket_launcher, ib_pistol_round
    dq ib_musket_ball, ib_shotgun_shell, ib_rifle_round, ib_rocket
    dq ib_staff, ib_archmage_staff, ib_iron_dagger, ib_diamond_dagger
    dq ib_shadow_fang, ib_kings_blade, ib_celestial_bow, ib_health_potion
    dq ib_mana_potion, ib_gold_coin, ib_ring, ib_amulet
    dq ib_phoenix_ring, ib_storm_band, ib_ember_amulet, ib_viper_amulet
    dq ib_iron_hammer, ib_diamond_hammer, ib_iron_spear, ib_diamond_spear
    dq ib_boat, ib_revolver, ib_hunting_rifle, ib_scope
    dq ib_extended_mag, ib_rifled_barrel, ib_compensator, ib_plane_engine
    dq ib_plane_wing, ib_plane_fuselage, ib_plane_prop, ib_plane_tail
    dq ib_plane
    dq ib_rune_ball, ib_rune_laser, ib_rune_nova, ib_rune_phase
    dq ib_rune_dash, ib_rune_fire, ib_rune_frost, ib_rune_shock
    dq ib_rune_poison, ib_rune_burst, ib_rune_pierce, ib_rune_seek
    dq ib_rune_chain, ib_rune_heal, ib_rune_haste, ib_rune_feather
%if $ - item_icons32 != ICON32_COUNT * 8
%error "item_icons32 needs one SKBMP per item id from STICK to the last rune"
%endif
