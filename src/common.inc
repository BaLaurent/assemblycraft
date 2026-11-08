; common.inc - shared constants and struct layouts for every AssemblyCraft module.
; Every .asm file includes this first. It switches to .note.GNU-stack, so the
; including file MUST select its own section before emitting anything.

section .note.GNU-stack noalloc noexec nowrite progbits

; ---- world: infinite, streamed; 16x16 columns of 16 chunks, local = absolute - world_origin ----
%define WORLD_H        256
%define CHUNK          16
%define COL_CHUNKS     16
%define COL_GRID       64               ; toroidal column table: slot (acz & 63)*64 + (acx & 63)
%define MAX_COLUMNS    4096
%define CHUNK_BYTES    8192             ; 4096 block bytes, then 4096 packed-light bytes
%define POOL_CHUNKS    24576
%define REGION_COLS    32               ; 32x32 columns per region file
%define SEA_LEVEL      96
%define REBASE_AT      1024
%define REBASE_STEP    512
%define MAX_RENDER_DIST 16
%define COL_FREE       0                ; COLUMN.state
%define COL_PENDING    1
%define COL_BLOCKS     2
%define COL_LIT        3
%define CF_MODIFIED    1                ; COLUMN.flags
%define CF_CONTS       2
%define GEN_SLOTS      8                ; generator buffers
%define GB_FREE        0                ; GENBUF.state
%define GB_REQ         1
%define GB_BUSY        2
%define GB_DONE        3
%define MAX_GEN_CHESTS 16
%define MAX_COL_CONTS  64
%define BIOME_OCEAN    0
%define BIOME_PLAINS   1
%define BIOME_FOREST   2
%define BIOME_DESERT   3
%define BIOME_SNOW     4
%define BIOME_SWAMP    5
%define BIOME_MOUNTAINS 6
%define BIOME_RIVER    7
%define BIOME_TAIGA    8                ; 0.10.1 transition biomes of the climate ladder
%define BIOME_SAVANNA  9
%define BIOME_SHORE    10
%define BIOME_BIRCH    11
%define NUM_BIOMES     12
; the biomes the world spawn may stand in (land with a ground to build on)
%define SPAWN_BIOMES   ((1 << BIOME_PLAINS) | (1 << BIOME_FOREST) | (1 << BIOME_DESERT) | (1 << BIOME_SNOW) | (1 << BIOME_SWAMP) | (1 << BIOME_TAIGA) | (1 << BIOME_SAVANNA) | (1 << BIOME_BIRCH))

; ---- block ids ------------------------------------------------------------
%define AIR            0
%define STONE          1
%define GRASS          2
%define DIRT           3
%define COBBLE         4
%define PLANKS         5
%define LOG            6
%define LEAVES         7
%define SAND           8
%define GLASS          9
%define BRICK          10
%define BEDROCK        11
%define CRAFTING_TABLE 12
%define COAL_ORE       13
%define IRON_ORE       14
%define GOLD_ORE       15
%define DIAMOND_ORE    16
%define FURNACE        17
%define FURNACE_LIT    18
%define CHEST          19
%define GRAVEL         20
%define TNT            21
%define FIRE           22               ; not solid, drawn by fire.asm, not an item
%define STONE_BRICK    23
%define MOSSY_STONE_BRICK 24
%define SANDSTONE      25
%define SMOOTH_STONE   26
%define MOSSY_COBBLESTONE 27
%define CRACKED_STONE_BRICK 28
%define BOOKSHELF      29
%define WOOL           30
%define IRON_BLOCK     31
%define GOLD_BLOCK     32
%define DIAMOND_BLOCK  33
%define COAL_BLOCK     34
%define PLANK_SLAB     35               ; slabs 35..39: bottom half only
%define COBBLE_SLAB    36
%define STONE_BRICK_SLAB 37
%define BRICK_SLAB     38
%define SANDSTONE_SLAB 39
%define PLANK_STAIRS   40               ; stairs: 4 ids each, base + facing (DIR_*)
%define COBBLE_STAIRS  44
%define STONE_BRICK_STAIRS 48
%define BRICK_STAIRS   52
%define SANDSTONE_STAIRS 56
%define WOOD_DOOR      60               ; 16 ids: base + facing*4 + open*2 + upper
%define IRON_DOOR      76
%define TRAPDOOR       92               ; 8 ids: base + facing*2 + open
%define LADDER         100              ; 4 ids: base + support side (DIR_*)
%define TORCH          104              ; standing torch, param 0
%define TORCH_WALL     105              ; 105..108: param = 1 + support side
%define FENCE          109
%define GLASS_PANE     110
%define WATER          111              ; translucent, not solid, not an item
%define ICE            112
%define SNOW_LAYER     113              ; 2/16 high, replaceable
%define SNOW_BLOCK     114
%define MUD            115
%define TALL_GRASS     116              ; cross-shaped plant, replaceable
%define CACTUS         117
%define PINE_LOG       118
%define PINE_LEAVES    119
%define BIRCH_LOG      120
%define BIRCH_LEAVES   121
%define BED            122              ; 8 ids: base + head*4 + facing (DIR_*, foot -> head)
%define SHRINE         130              ; 5 ids: base + faction (FAC_*), unbreakable, no item form
%define DRY_GRASS      135              ; savanna and warm-edge grass; digs to dirt
%define LAVA           136              ; a liquid like WATER (SHAPE_LIQUID), light 15, burns
%define NUM_BLOCKS     137              ; ids 137..143 unused

; ---- item ids -------------------------------------------------------------
%define FIRST_ITEM     144
%define STICK          (FIRST_ITEM + 0)
%define WOOD_PICKAXE   (FIRST_ITEM + 1)
%define WOOD_AXE       (FIRST_ITEM + 2)
%define WOOD_SHOVEL    (FIRST_ITEM + 3)
%define WOOD_SWORD     (FIRST_ITEM + 4)
%define STONE_PICKAXE  (FIRST_ITEM + 5)
%define STONE_AXE      (FIRST_ITEM + 6)
%define STONE_SHOVEL   (FIRST_ITEM + 7)
%define STONE_SWORD    (FIRST_ITEM + 8)
%define APPLE          (FIRST_ITEM + 9)
%define PORKCHOP       (FIRST_ITEM + 10)
%define COAL           (FIRST_ITEM + 11)
%define IRON_INGOT     (FIRST_ITEM + 12)
%define GOLD_INGOT     (FIRST_ITEM + 13)
%define DIAMOND        (FIRST_ITEM + 14)
%define IRON_PICKAXE   (FIRST_ITEM + 15)
%define IRON_AXE       (FIRST_ITEM + 16)
%define IRON_SHOVEL    (FIRST_ITEM + 17)
%define IRON_SWORD     (FIRST_ITEM + 18)
%define GOLD_PICKAXE   (FIRST_ITEM + 19)
%define GOLD_AXE       (FIRST_ITEM + 20)
%define GOLD_SHOVEL    (FIRST_ITEM + 21)
%define GOLD_SWORD     (FIRST_ITEM + 22)
%define DIAMOND_PICKAXE (FIRST_ITEM + 23)
%define DIAMOND_AXE    (FIRST_ITEM + 24)
%define DIAMOND_SHOVEL (FIRST_ITEM + 25)
%define DIAMOND_SWORD  (FIRST_ITEM + 26)
%define BOW            (FIRST_ITEM + 27)
%define ARROW          (FIRST_ITEM + 28)
%define STRING         (FIRST_ITEM + 29)
%define GUNPOWDER      (FIRST_ITEM + 30)
%define FLINT          (FIRST_ITEM + 31)
%define FLINT_AND_STEEL (FIRST_ITEM + 32)
%define ROTTEN_FLESH   (FIRST_ITEM + 33)
%define COOKED_PORKCHOP (FIRST_ITEM + 34)
%define FEATHER        (FIRST_ITEM + 35)
%define RAW_CHICKEN    (FIRST_ITEM + 36)
%define COOKED_CHICKEN (FIRST_ITEM + 37)
%define IRON_HELMET    (FIRST_ITEM + 38)
%define IRON_CHESTPLATE (FIRST_ITEM + 39)
%define IRON_LEGGINGS  (FIRST_ITEM + 40)
%define IRON_BOOTS     (FIRST_ITEM + 41)
%define GOLD_HELMET    (FIRST_ITEM + 42)
%define GOLD_CHESTPLATE (FIRST_ITEM + 43)
%define GOLD_LEGGINGS  (FIRST_ITEM + 44)
%define GOLD_BOOTS     (FIRST_ITEM + 45)
%define DIAMOND_HELMET (FIRST_ITEM + 46)
%define DIAMOND_CHESTPLATE (FIRST_ITEM + 47)
%define DIAMOND_LEGGINGS (FIRST_ITEM + 48)
%define DIAMOND_BOOTS  (FIRST_ITEM + 49)
%define PISTOL         (FIRST_ITEM + 50)
%define MUSKET         (FIRST_ITEM + 51)
%define SHOTGUN        (FIRST_ITEM + 52)
%define KALASHNIKOV    (FIRST_ITEM + 53)
%define ROCKET_LAUNCHER (FIRST_ITEM + 54)
%define PISTOL_ROUND   (FIRST_ITEM + 55)
%define MUSKET_BALL    (FIRST_ITEM + 56)
%define SHOTGUN_SHELL  (FIRST_ITEM + 57)
%define RIFLE_ROUND    (FIRST_ITEM + 58)
%define ROCKET         (FIRST_ITEM + 59)
%define STAFF          (FIRST_ITEM + 60)
%define ARCHMAGE_STAFF (FIRST_ITEM + 61)
%define IRON_DAGGER    (FIRST_ITEM + 62)
%define DIAMOND_DAGGER (FIRST_ITEM + 63)
%define SHADOW_FANG    (FIRST_ITEM + 64)
%define KINGS_BLADE    (FIRST_ITEM + 65)
%define CELESTIAL_BOW  (FIRST_ITEM + 66)
%define HEALTH_POTION  (FIRST_ITEM + 67)
%define MANA_POTION    (FIRST_ITEM + 68)
%define GOLD_COIN      (FIRST_ITEM + 69)
%define RING           (FIRST_ITEM + 70) ; jewelry: GK_RING / GK_AMULET, drops and shop only
%define AMULET         (FIRST_ITEM + 71)
%define PHOENIX_RING   (FIRST_ITEM + 72) ; legendary jewelry
%define STORM_BAND     (FIRST_ITEM + 73)
%define EMBER_AMULET   (FIRST_ITEM + 74)
%define VIPER_AMULET   (FIRST_ITEM + 75)
%define IRON_HAMMER    (FIRST_ITEM + 76)
%define DIAMOND_HAMMER (FIRST_ITEM + 77)
%define IRON_SPEAR     (FIRST_ITEM + 78)
%define DIAMOND_SPEAR  (FIRST_ITEM + 79)
%define BOAT           (FIRST_ITEM + 80)
%define NUM_ITEMS      (FIRST_ITEM + 81) ; 225

; ---- directions / block shapes ---------------------------------------------
%define DIR_N          0                ; -z
%define DIR_E          1                ; +x
%define DIR_S          2                ; +z
%define DIR_W          3                ; -x
%define SHAPE_NONE     0
%define SHAPE_CUBE     1
%define SHAPE_SLAB     2
%define SHAPE_STAIRS   3
%define SHAPE_DOOR     4
%define SHAPE_TRAPDOOR 5
%define SHAPE_LADDER   6
%define SHAPE_TORCH    7
%define SHAPE_FENCE    8
%define SHAPE_PANE     9
%define SHAPE_BED      10               ; one 9/16 high box
%define SHAPE_CROSS    11               ; two diagonal quads (drawn by the mesher)
%define SHAPE_LIQUID   12               ; no boxes (drawn by the mesher's water path)
%define SHAPE_SNOW     13               ; a 2/16 layer, no collision
%define SHAPE_CACTUS   14               ; inset 1/16 on x and z
%define BOXES_RENDER   0                ; shape_boxes purposes
%define BOXES_COLLIDE  1
%define BOXES_SELECT   2
%define MAX_SHAPE_BOXES 9
%define RECIPE_SIZE    13               ; w, h, out id, out count, cells[9] (row-major in w x h)
%define LIGHT_SKY_FULL 0xF0             ; packed light: sky<<4 | block
%define NUM_GUNS       5                ; PISTOL..ROCKET_LAUNCHER

; ---- tools ----------------------------------------------------------------
%define TOOL_NONE      0
%define TOOL_PICKAXE   1
%define TOOL_AXE       2
%define TOOL_SHOVEL    3
%define TOOL_SWORD     4
%define TOOL_DAGGER    5
%define TOOL_HAMMER    6
%define TOOL_SPEAR     7
%define TIER_WOOD      1
%define TIER_STONE     2
%define TIER_IRON      3
%define TIER_DIAMOND   4
%define TIER_GOLD      5

%define ARMOR_HEAD     1                ; item_armor_slot values
%define ARMOR_CHEST    2
%define ARMOR_LEGS     3
%define ARMOR_FEET     4

%define FLAG_SOLID     1
%define FLAG_OPAQUE    2
%define FLAG_CULL_SAME 4
%define FLAG_TRANSLUCENT 8              ; drawn in the blended pass (WATER, ICE)

; ---- mesh / texture -------------------------------------------------------
%define MAX_CHUNK_VERTS    196608       ; cubes need <= 98304; shaped blocks use the rest
%define VERTEX_SIZE        16
%define ATLAS_W            256
%define ATLAS_H            512
%define TILE_PX            16
%define TEX_UNITS_PER_TILE 256          ; texcoords in 1/16 px; atlas = 4096 x 8192 units

; atlas tiles beyond the 0.1 block tiles 0..12
%define TILE_TABLE_TOP     13
%define TILE_TABLE_SIDE    14
%define TILE_CRACK0        16           ; crack stages 16..25
%define TILE_COAL_ORE      26
%define TILE_IRON_ORE      27
%define TILE_GOLD_ORE      28
%define TILE_DIAMOND_ORE   29
%define TILE_FURNACE_FRONT 30
%define TILE_FURNACE_LIT   31
%define TILE_CHEST_TOP     43
%define TILE_CHEST_SIDE    44
%define TILE_GRAVEL        45
%define TILE_TNT_SIDE      46
%define TILE_TNT_TOP       47
%define TILE_HEART_FULL    48
%define TILE_HEART_HALF    49
%define TILE_HEART_EMPTY   50
%define TILE_FOOD_FULL     51
%define TILE_FOOD_HALF     52
%define TILE_FOOD_EMPTY    53
%define TILE_ARMOR_FULL    54
%define TILE_ARMOR_HALF    55
%define TILE_ARMOR_EMPTY   56
%define TILE_FIRE0         57           ; two flame frames, transparent around the flames
%define TILE_FIRE1         58
%define TILE_STONE_BRICK   59
%define TILE_MOSSY_BRICK   60
%define TILE_ZOMBIE_SKIN   64
%define TILE_ZOMBIE_FACE   65
%define TILE_ZOMBIE_SHIRT  66
%define TILE_ZOMBIE_PANTS  67
%define TILE_PIG_SKIN      68
%define TILE_PIG_FACE      69
%define TILE_PLAYER_SKIN   70
%define TILE_CREEPER_SKIN  71
%define TILE_CREEPER_FACE  72
%define TILE_SKELETON_BONE 73
%define TILE_SKELETON_FACE 74
%define TILE_SPIDER_BODY   75
%define TILE_SPIDER_FACE   76
%define TILE_CHICKEN_BODY  77
%define TILE_CHICKEN_FACE  78
%define TILE_CHICKEN_LEG   79
%define TILE_ITEM0         80           ; icon of item id i >= COAL is TILE_ITEM0 + i - COAL (80..138);
                                        ; STICK..PORKCHOP use tiles 32 + i - STICK
%define TILE_ABILITY0      139          ; 139 + (class-1)*3 + slot
%define TILE_CLASS0        151          ; 151..154, class-1
%define TILE_STAT0         155          ; 155 + stat id
%define TILE_VILLAGER_SKIN 173
%define TILE_VILLAGER_FACE 174
%define TILE_MERCHANT_ROBE 175
%define TILE_ELDER_ROBE    176
%define TILE_BOSS_ROBE     177
%define TILE_BOSS_FACE     178
%define TILE_BOSS_CROWN    179
%define TILE_DOOR_IRON_UPPER 15
%define TILE_SANDSTONE_TOP 61
%define TILE_SANDSTONE_SIDE 62
%define TILE_SANDSTONE_BOTTOM 63
%define TILE_SMOOTH_STONE  180
%define TILE_MOSSY_COBBLE  181
%define TILE_CRACKED_BRICK 182
%define TILE_BOOKSHELF     183
%define TILE_WOOL          184
%define TILE_IRON_BLOCK    185
%define TILE_GOLD_BLOCK    186
%define TILE_DIAMOND_BLOCK 187
%define TILE_COAL_BLOCK    188
%define TILE_DOOR_WOOD_LOWER 189
%define TILE_DOOR_WOOD_UPPER 190
%define TILE_DOOR_IRON_LOWER 191
%define TILE_TRAPDOOR      200
%define TILE_LADDER        201
%define TILE_TORCH         202
%define TILE_ICON_STAIRS0  240          ; 240..244: planks, cobble, stone brick, brick, sandstone
%define TILE_ICON_SLAB0    245          ; 245..249, same order
%define TILE_ICON_WOOD_DOOR 250
%define TILE_ICON_IRON_DOOR 251
%define TILE_ICON_FENCE    252
%define TILE_ICON_GLASS_PANE 253
; 0.8 tiles: the only 23 free atlas tiles (203..207, 216..223, 232..239, 254, 255)
%define TILE_RING          203
%define TILE_AMULET        204
%define TILE_IRON_HAMMER   205
%define TILE_DIAMOND_HAMMER 206
%define TILE_IRON_SPEAR    207
%define TILE_DIAMOND_SPEAR 216
%define TILE_ABILITY3_0    217          ; 217..220: slot-3 icon, class-1
%define TILE_ATTR_STR      221
%define TILE_ATTR_DEX      222
%define TILE_ATTR_INT      223
%define TILE_ATTR_VIT      232
%define TILE_ELEM_FIRE     233          ; 233..236: fire, frost, shock, poison
%define TILE_ELEM_FROST    234
%define TILE_ELEM_SHOCK    235
%define TILE_ELEM_POISON   236
%define TILE_STAT_ASPD     237
%define TILE_STAT_BLEED    238
%define TILE_STAT_AREA     239
%define TILE_STAT_ELITE    254
%define TILE_KEYSTONE      255
; 0.9 tiles: the 24 tiles the font left at y 192..239 (192..199, 208..215, 224..231)
%define TILE_WATER         192
%define TILE_ICE           193
%define TILE_SNOW          194
%define TILE_MUD           195
%define TILE_TALL_GRASS    196
%define TILE_CACTUS_SIDE   197
%define TILE_CACTUS_TOP    198
%define TILE_PINE_LOG      199
%define TILE_PINE_LOG_TOP  208
%define TILE_PINE_LEAVES   209
%define TILE_BIRCH_LOG     210
%define TILE_BIRCH_LEAVES  211
%define TILE_BED_HEAD_TOP  212
%define TILE_BED_FOOT_TOP  213
%define TILE_BED_HEAD_SIDE 214
%define TILE_BED_FOOT_SIDE 215
%define TILE_ICON_BED      224
%define TILE_ICON_BOAT     225
%define TILE_BUBBLE        226
%define TILE_BUBBLE_POP    227
%define TILE_SHRINE_TOP    228          ; 0.10: the last free byte tiles
%define TILE_SHRINE_SIDE   229
%define FONT_Y             256          ; glyph rows at atlas y 256..303, x 0..127
; 0.10 faction skins, 16-bit tile ids past the font: faction f's tile k = TILE_FOLK0 + 4f + k
%define TILE_FOLK0         304          ; 304..323
%define TILE_FOLK_HEAD     0
%define TILE_FOLK_FACE     1
%define TILE_FOLK_TUNIC    2
%define TILE_FOLK_PANTS    3
; 0.10.1 block tiles, 16-bit ids past the faction skins
%define TILE_DRY_GRASS_TOP  324
%define TILE_DRY_GRASS_SIDE 325
%define TILE_LAVA           326
; 0.10.2 grimoire UI tiles (9-slice kinds NINE_*, one tile each, see theme.inc palette)
%define TILE_NINE0          327         ; 327..342: NINE_* kind k is tile 327 + k
%define TILE_COMPASS        343         ; web centre ornament, drawn at 32x32
%define TILE_SLOT_HEAD      344         ; empty-slot glyphs, ink on transparency
%define TILE_SLOT_CHEST     345
%define TILE_SLOT_LEGS      346
%define TILE_SLOT_FEET      347
%define TILE_SLOT_RING      348
%define TILE_SLOT_AMULET    349
%define TILE_QUILL          351         ; quill left of a hovered button label
%define TILE_SIL0           365         ; character silhouette: 3x6 tile block, sub-tile (r,c) = 365+16r+c
%define NINE_PAGE           0           ; ui_nine kinds
%define NINE_LEATHER        1
%define NINE_SLOT           2
%define NINE_BUTTON         3
%define NINE_BUTTON_HOT     4
%define NINE_BUTTON_OFF     5
%define NINE_TOOLTIP        6
%define NINE_RIBBON         7
%define NINE_BAR            8
%define NINE_RUNE           9
%define NINE_SELECT         10
%define NINE_NOTE           11
%define NINE_NODE_STAT      12
%define NINE_NODE_ABIL      13
%define NINE_NODE_KEY       14
%define NINE_NODE_PATH      15
%define NINE_MAX_QUADS      2048
; cave column flags (caves.asm cave_flags)
%define CF_RAVINE      1
%define CF_PILLAR      2
%define CF_CAVERN      4
%define CF_MOUTH       8

; ---- save file ------------------------------------------------------------
%define WORLD_HDR_SIZE  32768
%define HOTBAR_SLOTS    9

; ---- game -----------------------------------------------------------------
%define MODE_SURVIVAL   0
%define MODE_CREATIVE   1
%define DAY_LENGTH      72000           ; fixed 1/60 s steps (20 minutes)
%define NEW_WORLD_TIME  6000
%define PANORAMA_SEED   20261107

%define DIFF_PEACEFUL   0
%define DIFF_EASY       1
%define DIFF_NORMAL     2
%define DIFF_HARD       3

%define CAUSE_FALL      1
%define CAUSE_ZOMBIE    2
%define CAUSE_STARVE    3
%define CAUSE_SUFFOCATE 4
%define CAUSE_SKELETON  5
%define CAUSE_EXPLOSION 6
%define CAUSE_SPIDER    7
%define CAUSE_FIRE      8
%define CAUSE_BOSS      9
%define CAUSE_POISON    10
%define CAUSE_DROWN     11
%define CAUSE_FOLK      12              ; + faction: slain by a faction's folk (12..16)
%define CAUSE_LAST      16
%define MAX_BREATH      600             ; steps of air under water
%define MAX_BOATS       16

%define MOB_NONE        0
%define MOB_ZOMBIE      1
%define MOB_PIG         2
%define MOB_CREEPER     3
%define MOB_SKELETON    4
%define MOB_SPIDER      5
%define MOB_CHICKEN     6
%define MOB_BOSS        7
%define MOB_FOLK        8               ; a faction member: MOB.faction/.role/.fclass (folk.asm)
%define NUM_MOB_TYPES   8
%define ROLE_NONE       0               ; MOB.role of a MOB_FOLK
%define ROLE_LEADER     1
%define ROLE_TRADER     2
%define ROLE_GUARD      3               ; fighters: GUARD, CHAMPION, PATROL
%define ROLE_WORKER     4
%define ROLE_CAPTIVE    5
%define ROLE_CHAMPION   6
%define ROLE_PATROL     7
%define ROLE_TRAVELLER  8
%define NUM_ROLES       9
%define FCLASS_NONE     0               ; MOB.fclass of a fighter
%define FCLASS_ARCHER   1
%define FCLASS_BRUTE    2
%define FCLASS_ACOLYTE  3
%define FCLASS_BERSERKER 4
%define NUM_FCLASSES    5
%define FF_ASLEEP       1               ; MOB.fflags
%define FF_RAGE         2
%define FF_FOLKDOT      4               ; the burn or poison it suffers came from a folk: nobody's kill
%define TIER_HATED      0               ; faction_tier
%define TIER_HOSTILE    1
%define TIER_NEUTRAL    2
%define TIER_FRIENDLY   3
%define TIER_ALLIED     4
%define STANDING_HOSTILE  -200          ; the lowest standing of each tier above Hated
%define STANDING_NEUTRAL  0
%define STANDING_FRIENDLY 200
%define STANDING_ALLIED   500
%define STANDING_MIN    -1000
%define STANDING_MAX    1000
%define CULT_MAX        199             ; the Ashen Cult never becomes Friendly
%define MOB_ELITE_BIT   0x100           ; MOBSAVE.type flag
%define MS_LEVEL_SHIFT  16              ; MOBSAVE.type bits 16..23 = level (0 = derive on load)
%define MS_AFFIX_SHIFT  24              ; MOBSAVE.type bits 24..31 = elite affixes (AFX_*)
%define AFX_MOLTEN      1               ; MOB.affix bits
%define AFX_FROZEN      2
%define AFX_VENOMOUS    4
%define AFX_STORM       8
%define AFX_VAMPIRIC    16
%define AFX_SWIFT       32
%define AFX_JUGGERNAUT  64
%define AFX_ARMORED     128
%define NUM_AFFIX_KINDS 8
%define MAX_MOBS        64
%define GROUND_HOSTILE  0               ; spawn_at_ground / spawn_near_player: solid, opaque, not bedrock or foliage
%define GROUND_PASSIVE  1               ; ...grass
%define STUN_PARRIED    50              ; a parried zombie, spider or folk is dazed this long
%define MAX_DROPS       64              ; item entities lying in the world
%define MAX_ARROWS      96

%define OWNER_PLAYER    0               ; ARROWENT.owner
%define OWNER_MONSTER   1
%define OWNER_FOLK      2               ; + faction
%define PROJ_ARROW      0               ; ARROWENT.kind
%define PROJ_BULLET     1
%define PROJ_ROCKET     2
%define PROJ_BOLT       3
%define PROJ_FIREBALL   4
%define AF_CRIT         1               ; ARROWENT.flags
%define AF_EXPLOSIVE    2
%define AF_BIG          4
%define AF_BLEED        8
%define AF_ATTACK       16              ; a weapon attack (bow shot, staff bolt), not a skill
%define AF_ELEM_SHIFT   8               ; ARROWENT.flags bits 8..10 = element (ELEM_*)
%define PROJ_KNIFE      5
%define MAX_PRIMED      32              ; primed TNT
%define MAX_FIRES       1024
%define MAX_PARTICLES   768
%define FX_FIRE         1               ; PARTICLE.kind (0 = free)
%define FX_SMOKE        2
%define FX_DEBRIS       3
%define FX_SPARK        4
%define FX_MAGIC        5
%define FX_GOLD         6
%define FX_FROST        7

; ---- RPG ------------------------------------------------------------------
%define CLASS_NONE      0
%define CLASS_WARRIOR   1
%define CLASS_MAGE      2
%define CLASS_ARCHER    3
%define CLASS_ROGUE     4
%define NUM_CLASSES     4
%define MAX_LEVEL       50
%define NUM_NODES       18              ; node = branch*6 + tier
%define NODES_PER_BRANCH 6
%define NUM_ABILITY_SLOTS 4
%define RPGX_VERSION    1
%define NODE_STAT       0               ; NODEINFO.kind
%define NODE_ABILITY    1
%define NODE_KEYSTONE   2
%define NODE_PATH       3               ; archetype path node (WEBNODE.kind)
%define NUM_ABILITIES   16              ; ability id = (archetype-1)*4 + slot
%define ABIL_SHADOWSTEP 12
%define NUM_KEYSTONES   12
%define NUM_WEB_NODES   88
%define WEB_MAX         128
%define KIT_COMMON_BIT  0x80

%define ATTR_STR        0
%define ATTR_DEX        1
%define ATTR_INT        2
%define ATTR_VIT        3
%define NUM_ATTRS       4
%define ATTR_PER_LEVEL  3

%define KS_EXECUTIONER  0               ; keystone id = (class-1)*3 + branch
%define KS_JUGGERNAUT   1
%define KS_BLOODRAGE    2
%define KS_INFERNO      3
%define KS_BLOOD_MAGIC  4
%define KS_MANA_SHIELD  5
%define KS_DEADEYE      6
%define KS_BARRAGE      7
%define KS_WIND_RUNNER  8
%define KS_ASSASSINATE  9
%define KS_SHADOW_DANCE 10
%define KS_VENOM_BLADES 11

%define ELEM_PHYS       0
%define ELEM_FIRE       1
%define ELEM_FROST      2
%define ELEM_SHOCK      3
%define ELEM_POISON     4
%define NUM_ELEMS       5

%define STS_BURN        0               ; status kinds
%define STS_CHILL       1
%define STS_SHOCK       2
%define STS_POISON      3
%define STS_BLEED       4

%define SRC_MELEE       0               ; damage sources (combat_hit_mob / combat_calc)
%define SRC_BOW         1
%define SRC_BOLT        2
%define SRC_MELEE_SKILL 3
%define SRC_RANGED_SKILL 4
%define SRC_SPELL       5
%define SRC_THORNS      6

%define HITF_ELEM_MASK  7               ; combat_hit_mob flags: bits 0..2 element
%define HITF_CRIT       0x100
%define HITF_BLEED      0x200
%define HITF_HURTWIN    0x400           ; respect the mob hurt window (mob_hurt)
%define HITF_CHILL3     0x800
%define HITF_EXECUTE    0x1000
%define HITF_NOSTATUS   0x2000
%define HITF_CHAIN      0x4000

%define GK_NONE         0               ; item_gear kinds
%define GK_MELEE        1
%define GK_BOW          2
%define GK_STAFF        3
%define GK_HEAD         4
%define GK_CHEST        5
%define GK_LEGS         6
%define GK_FEET         7
%define GK_RING         8
%define GK_AMULET       9
%define GEAR_RARITY_SHIFT 14            ; gear dmg word: rarity<<14 | tier<<10 | seed
%define GEAR_TIER_SHIFT 10
%define GEAR_SEED_MASK  1023
%define RAR_COMMON      0
%define RAR_MAGIC       1
%define RAR_RARE        2
%define RAR_EPIC        3
%define RAR_LEGENDARY   4               ; display only (legendary items carry RAR_RARE bits)
%define MAX_AFFIXES     5
%define LOOT_MOB        0
%define LOOT_ELITE      1
%define LOOT_BOSS       2
%define LOOT_CHEST      3
%define LOOT_SHOP       4
%define LP_NONE         0               ; legendary powers; gear_powers bit = 1 << lp
%define LP_KINGSLAYER   1
%define LP_ARCHMAGE     2
%define LP_CELESTIAL    3
%define LP_SHADOW_FANG  4
%define LP_PHOENIX      5
%define LP_STORMS       6
%define LP_EMBERS       7
%define LP_VIPER        8

%define FMT_PCT         0               ; STATINFO.fmt: "+N%"
%define FMT_FLAT        1               ; "+N"
%define FMT_TENTH       2               ; "+N.N"
%define FMT_NEGPCT      3               ; "-N%" (stored positive)

%define STAT_MAX_HEALTH    0
%define STAT_MELEE_DMG     1
%define STAT_RANGED_DMG    2
%define STAT_SPELL_DMG     3
%define STAT_CRIT_CHANCE   4
%define STAT_CRIT_DMG      5
%define STAT_MAX_MANA      6
%define STAT_MANA_REGEN    7
%define STAT_MAX_STAMINA   8
%define STAT_STAMINA_REGEN 9
%define STAT_ARMOR_BONUS   10
%define STAT_MOVE_SPEED    11
%define STAT_BACKSTAB      12
%define STAT_PARRY_WINDOW  13
%define STAT_LIFESTEAL     14
%define STAT_COOLDOWN_RED  15
%define STAT_ARROW_SAVE    16
%define STAT_DODGE_COST    17
%define STAT_ATTACK_SPEED  18
%define STAT_FIRE_DMG      19           ; 19..22: % damage of element (elem-1)
%define STAT_FROST_DMG     20
%define STAT_SHOCK_DMG     21
%define STAT_POISON_DMG    22
%define STAT_ADD_FIRE      23           ; 23..26: flat element damage added to weapon attacks
%define STAT_ADD_FROST     24
%define STAT_ADD_SHOCK     25
%define STAT_ADD_POISON    26
%define STAT_RES_FIRE      27           ; 27..30: % element damage taken reduction
%define STAT_RES_FROST     28
%define STAT_RES_SHOCK     29
%define STAT_RES_POISON    30
%define STAT_BLEED_CHANCE  31
%define STAT_DOT_DMG       32
%define STAT_ELITE_DMG     33
%define STAT_AREA          34
%define STAT_LIFE_REGEN    35           ; tenths of health per second
%define STAT_LIFE_ON_KILL  36
%define STAT_THORNS        37
%define STAT_BLOCK_COST    38
%define STAT_XP_BONUS      39
%define STAT_GOLD_FIND     40
%define STAT_MAGIC_FIND    41
%define STAT_ALL_DMG       42
%define STAT_WEAPON_DMG    43
%define NUM_STATS          44

%define RES_STAMINA     0
%define RES_MANA        1

%define HIT_NONE        0               ; player_take_hit results
%define HIT_TAKEN       1
%define HIT_BLOCKED     2
%define HIT_PARRIED     3

%define HF_CRIT         1               ; combat_hit_flags bits
%define HF_PLAYER       2
%define HF_DOT          4
%define HF_ELEM_SHIFT   4
%define HF_ELEM_MASK    0x70

%define TXT_PARRY       0               ; dmgnum_text ids
%define TXT_BLOCKED     1
%define TXT_DODGED      2
%define TXT_STUNNED     3
%define TXT_FROZEN      4
%define TXT_IMMUNE      5

%define SITE_VILLAGE    1
%define SITE_DUNGEON    2
%define SITE_CRYPT      3
%define SITE_CAMP       4               ; a faction camp clearing (index = FAC_*)
%define MAX_REGION_SITES 9              ; region_plan output
%define MAX_SITES       81              ; runtime cache: the 3x3 regions around the player
%define MAX_SITESTATES  1024            ; WORLDHDR.sites
%define SS_CLEARED      1               ; SITESTATE.flags
%define SS_FREED        2               ; a camp's captive was freed
%define FAC_VILLAGERS   0
%define FAC_BANDITS     1
%define FAC_CULT        2
%define FAC_BEASTFOLK   3
%define FAC_STONEKIN    4
%define NUM_FACTIONS    5
%define DUNGEON_KILLS   8

%define Q_KILL          1
%define Q_BRING         2
%define Q_CLEAR         3
%define Q_ELITE         4
%define Q_BOSS          5
%define NUM_QUESTS      8

%define INV_SLOTS       36              ; 0..8 hotbar, 9..35 main
%define SLOTREF_GRID    36              ; grid cell c = 36 + c (c 0..8, 3 wide)
%define SLOTREF_RESULT  45
                                        ; 46 = cursor (never clickable)
%define SLOTREF_ARMOR   47              ; 47..50: head, chest, legs, feet
%define SLOTREF_CONTAINER 51            ; 51..77: open container cells
%define SLOTREF_JEWELRY 78              ; 78, 79 rings, 80 amulet

%define CONT_FURNACE    1
%define CONT_CHEST      2
%define MAX_CONTAINERS  256             ; runtime table conts[]
%define SMELT_STEPS     200

; ---- app states -----------------------------------------------------------
%define ST_TITLE        0
%define ST_WORLDS       1
%define ST_CREATE       2
%define ST_RENAME       3
%define ST_DELETE       4
%define ST_SETTINGS     5
%define ST_CONTROLS     6
%define ST_PLAYING      7
%define ST_PAUSED       8
%define ST_INVENTORY    9
%define ST_CRAFTING     10
%define ST_DEATH        11
%define ST_QUIT         12
%define ST_FURNACE      13
%define ST_CHEST        14
%define ST_TRADE        15
%define ST_DIALOG       16
%define ST_CLASS        17
%define ST_SKILLS       18
%define ST_CHARACTER    19
%define ST_SHRINE       20
%define ST_LEADER       21

; ---- key bindings (index into SETTINGS.keys) -----------------------------
%define BIND_FORWARD    0
%define BIND_BACK       1
%define BIND_LEFT       2
%define BIND_RIGHT      3
%define BIND_JUMP       4
%define BIND_SNEAK      5
%define BIND_SPRINT     6
%define BIND_INVENTORY  7
%define BIND_FLY        8
%define BIND_RELOAD     9
%define BIND_DODGE      10
%define BIND_ABILITY1   11
%define BIND_ABILITY2   12
%define BIND_ABILITY3   13
%define BIND_SKILLS     14
%define BIND_ABILITY4   15
%define NUM_BINDINGS    16

; ---- sounds ---------------------------------------------------------------
%define SND_CLICK       0
%define SND_DIG_STONE   1
%define SND_DIG_WOOD    2
%define SND_DIG_SOFT    3
%define SND_DIG_GLASS   4
%define SND_STEP_STONE  5
%define SND_STEP_WOOD   6
%define SND_STEP_SOFT   7
%define SND_HURT        8
%define SND_EAT         9
%define SND_BURP        10
%define SND_ZOMBIE_SAY  11
%define SND_ZOMBIE_HURT 12
%define SND_PIG_SAY     13
%define SND_PIG_HURT    14
%define SND_TOOL_BREAK  15
%define SND_POP         16
%define SND_EXPLODE     17
%define SND_FUSE        18
%define SND_BOW         19
%define SND_ARROW_HIT   20
%define SND_SKELETON_SAY 21
%define SND_SKELETON_HURT 22
%define SND_SPIDER_SAY  23
%define SND_SPIDER_HURT 24
%define SND_CREEPER_HURT 25
%define SND_CHICKEN_SAY 26
%define SND_CHICKEN_HURT 27
%define SND_PISTOL      28
%define SND_MUSKET      29
%define SND_SHOTGUN     30
%define SND_RIFLE       31
%define SND_LAUNCHER    32
%define SND_RELOAD      33
%define SND_DRY_FIRE    34
%define SND_SWING       35
%define SND_PARRY       36
%define SND_BLOCK       37
%define SND_DODGE       38
%define SND_CRIT        39
%define SND_LEVELUP     40
%define SND_SPELL       41
%define SND_FIREBALL    42
%define SND_BLINK       43
%define SND_WARCRY      44
%define SND_WHIRL       45
%define SND_SMOKE       46
%define SND_COIN        47
%define SND_QUEST       48
%define SND_BOSS_ROAR   49
%define SND_SLAM        50
%define SND_VILLAGER    51
%define SND_DRINK       52
%define SND_DOOR_OPEN   53
%define SND_DOOR_CLOSE  54
%define SND_FREEZE      55
%define SND_HEAVY       56
%define SND_KNIVES      57
%define SND_LOOT_RARE   58
%define SND_LEGENDARY   59
%define NUM_SOUNDS      60

; ---- colours: packed for glColor4ub as four bytes r,g,b,a -----------------
%define RGBA(r,g,b,a) ((r)|((g)<<8)|((b)<<16)|((a)<<24))

; ---- syscalls -------------------------------------------------------------
%define SYS_READ    0
%define SYS_WRITE   1
%define SYS_OPEN    2
%define SYS_CLOSE   3
%define SYS_STAT    4
%define SYS_LSEEK   8
%define SYS_FSTAT   5
%define SYS_PREAD64 17
%define SYS_PWRITE64 18
%define SYS_RENAME  82
%define SYS_MKDIR   83
%define SYS_UNLINK  87
%define SYS_RMDIR   84
%define SYS_TIME    201
%define SYS_GETDENTS64 217
%define SYS_CLOCK_GETTIME 228
%define CLOCK_MONOTONIC 1
%define O_RDONLY    0
%define O_WRONLY    1
%define O_RDWR      2
%define O_CREAT     0x40
%define O_WCT       0x241               ; O_WRONLY|O_CREAT|O_TRUNC
%define SEEK_END    2
%define DT_DIR      4
%define DT_REG      8
%define O_DIRECTORY 0x10000
%define MODE_644    420
%define ENOENT      2
%define EINTR       4
%define EEXIST      17
%define ENAMETOOLONG 36

; ---- structs --------------------------------------------------------------
struc INPUT
    .fwd:    resd 1                     ; W=+1 S=-1
    .strafe: resd 1                     ; D=+1 A=-1
    .jump:   resd 1
    .down:   resd 1
    .sprint: resd 1
endstruc

struc FRAMEINPUT
    .move:        resb INPUT_size
    .look_dx:     resd 1                ; float pixels
    .look_dy:     resd 1                ; float pixels
    .lmb_held:    resd 1
    .lmb_pressed: resd 1
    .rmb_held:    resd 1
    .rmb_pressed: resd 1
    .mmb_pressed: resd 1
    .slot:        resd 1                ; -1 or 0..8
    .scroll:      resd 1                ; +1 = wheel up
    .toggle_fly:  resd 1
    .inventory:   resd 1                ; edge of the inventory binding
    .debug:       resd 1                ; F3 edge
    .fullscreen:  resd 1                ; F11 edge
    .reload:      resd 1                ; edge of the Reload binding (every state)
    .skills:      resd 1                ; edge of the Skill Tree binding (every state)
    .dodge:       resd 1                ; edges below: only while the cursor is captured
    .ability:     resd 4
endstruc

struc UIINPUT
    .mouse_px:     resd 1               ; int framebuffer pixels
    .mouse_py:     resd 1
    .lmb_pressed:  resd 1
    .lmb_held:     resd 1
    .rmb_pressed:  resd 1
    .shift:        resd 1
    .scroll:       resd 1
    .double_click: resd 1
    .enter:        resd 1
    .escape:       resd 1
    .backspace:    resd 1               ; presses + repeats this frame
    .key_pressed:  resd 1               ; last key code pressed this frame, or -1
    .typed_len:    resd 1
    .typed:        resb 32
endstruc

struc BODY
    .x:         resd 1                  ; floats; .y = feet
    .y:         resd 1
    .z:         resd 1
    .vx:        resd 1
    .vy:        resd 1
    .vz:        resd 1
    .yaw:       resd 1
    .pitch:     resd 1
    .on_ground: resd 1                  ; int32
    .flying:    resd 1                  ; int32
    .half_w:    resd 1                  ; float box half width
    .height:    resd 1                  ; float box height
    .speed:     resd 1                  ; float walk speed
    .kbx:       resd 1                  ; float knockback velocity (decays)
    .kbz:       resd 1
    .fall:      resd 1                  ; float distance fallen since last on ground
    .blocked:   resd 1                  ; int32: 1 if an X or Z collision happened this step
endstruc                                ; 68 bytes

struc RAYHIT
    .bx: resd 1                         ; block hit
    .by: resd 1
    .bz: resd 1
    .px: resd 1                         ; cell entered just before it
    .py: resd 1
    .pz: resd 1
endstruc

struc ITEMSTACK
    .id:    resb 1
    .count: resb 1
    .dmg:   resw 1                      ; tool damage taken
endstruc

struc INVENTORY
    .slots:  resb INV_SLOTS * 4
    .grid:   resb 9 * 4
    .result: resb 4
    .cursor: resb 4
    .armor:  resb 4 * 4                 ; head, chest, legs, feet (refs 47..50)
    .jewelry: resb 3 * 4                ; ring, ring, amulet (refs 78..80)
endstruc

struc SURVIVAL
    .health:          resd 1
    .food:            resd 1
    .saturation:      resd 1            ; float
    .exhaustion:      resd 1            ; float
    .regen_timer:     resd 1
    .starve_timer:    resd 1
    .invuln:          resd 1
    .hurt_flash:      resd 1
    .suffocate_timer: resd 1
    .eat_timer:       resd 1
    .eat_sound:       resd 1
    .dead:            resd 1
    .death_cause:     resd 1
    .breath:          resd 1            ; steps of air, 0..MAX_BREATH
    .drown_timer:     resd 1            ; steps at 0 breath
endstruc

struc MOB
    .body:     resb BODY_size
    .type:     resd 1
    .health:   resd 1
    .hurt:     resd 1                   ; steps
    .cooldown: resd 1                   ; steps
    .ai_timer: resd 1                   ; steps
    .panic:    resd 1                   ; steps
    .fuse:     resd 1                   ; creeper fuse, steps
    .walk:     resd 1                   ; float, degrees of walk-cycle phase
    .input:    resb INPUT_size
    .windup:   resd 1                   ; steps left in a telegraphed attack, 0 = none
    .stun:     resd 1                   ; steps
    .elite:    resd 1                   ; 0/1
    .tagged:   resd 1                   ; steps; > 0 = a player hit counts for XP
    .origin:   resd 1                   ; 0 none, else WORLDHDR.sites index + 1 (dungeon, crypt)
    .bar:      resd 1                   ; steps the health bar stays visible
    .max_health: resd 1
    .timer_a:  resd 1                   ; boss timers, steps
    .timer_b:  resd 1
    .home_x:   resd 1                   ; floats, NPC home
    .home_z:   resd 1
    .level:    resd 1                   ; 1..
    .affix:    resd 1                   ; AFX_* bits (elites)
    .burn_t:   resd 1                   ; steps
    .burn_dmg: resd 1                   ; float per tick
    .bleed_t:  resd 1
    .bleed_dmg: resd 1                  ; float per tick
    .poison_t: resd 1
    .poison:   resd 1                   ; stacks
    .poison_dmg: resd 1                 ; float per stack per tick
    .chill_t:  resd 1
    .chill:    resd 1                   ; stacks 0..2
    .freeze_cd: resd 1
    .shock_t:  resd 1
    .shock:    resd 1                   ; stacks 0..3
    .mark_t:   resd 1                   ; Hunter's Mark steps
    .dot_tick: resd 1                   ; steps to the next DoT tick
    .faction:  resb 1                   ; MOB_FOLK: FAC_*
    .role:     resb 1                   ; ROLE_*
    .fclass:   resb 1                   ; FCLASS_* of a fighter, else 0
    .fflags:   resb 1                   ; FF_ASLEEP, FF_RAGE
    .wid:      resb 1                   ; weapon item id, 0 = none
    .captor:   resb 1                   ; ROLE_CAPTIVE: the faction holding it
    .wdmg:     resw 1                   ; weapon dmg word (gear roll)
    .target:   resd 1                   ; 0 none, 1 the player, 2 + slot: another mob
    .provoked: resd 1                   ; steps the player stays a target whatever the standing
    .patrol:   resd 1                   ; road key of a patrol member, else 0
    .dest_x:   resd 1                   ; patrol: the end it walks to (local float); home_x/home_z hold the other end
    .dest_z:   resd 1
    .greet:    resd 1                   ; steps before this guard greets again
endstruc

struc MOBSAVE
    .type:   resd 1
    .health: resd 1
    .x:      resd 1                     ; floats
    .y:      resd 1
    .z:      resd 1
endstruc

; a furnace or chest (runtime table conts[], absolute cell coordinates)
struc CONTAINER
    .x:        resd 1
    .y:        resd 1
    .z:        resd 1
    .kind:     resb 1                   ; 0 free, CONT_FURNACE, CONT_CHEST
    .pad0:     resb 3
    .slots:    resb 27 * 4              ; furnace: 0 input, 1 fuel, 2 output
    .burn:     resw 1                   ; steps of fuel left
    .burn_max: resw 1
    .cook:     resw 1
    .pad:      resb 6
endstruc                                ; 136 bytes

; RPG progression, stored in WORLDHDR.rpg; skill points are derived (level - sum of ranks)
struc RPGSAVE
    .class:          resb 1
    .level:          resb 1             ; 1..30
    .quest:          resb 1             ; next quest index 0..8 (8 = chain finished)
    .quest_state:    resb 1             ; 0 not accepted, 1 accepted
    .xp:             resd 1             ; into the current level
    .ranks_v4:       resb 12            ; 0.7 ranks, unused since 0.8 (RPGEXT.ranks)
    .retired:        resb 2             ; 0.8 dungeon/boss flags, unused since 0.9 (WORLDHDR.sites)
    .quest_progress: resw 1
    .pad:            resb 40
endstruc
%if RPGSAVE_size != 64
%error "RPGSAVE must be 64 bytes"
%endif

; rpg_class_info record: class card texts (dq zstr)
struc CLASSINFO
    .name:  resq 1
    .line1: resq 1
    .line2: resq 1
    .line3: resq 1
endstruc
%if CLASSINFO_size != 32
%error "CLASSINFO must be 32 bytes"
%endif

; rpg_node_info record: one skill-tree node
struc NODEINFO
    .name:  resq 1
    .desc:  resq 1
    .kind:  resb 1                      ; NODE_STAT, NODE_ABILITY, NODE_KEYSTONE
    .stat:  resb 1                      ; stat id; ability slot (ability); KS_* id (keystone)
    .max:   resb 1                      ; max rank
    .pad:   resb 1
    .value: resd 1                      ; per rank, 0 for abilities
endstruc
%if NODEINFO_size != 24
%error "NODEINFO must be 24 bytes"
%endif

; one node of the shared skill web (rpg_web_node)
struc WEBNODE
    .name:  resq 1
    .desc:  resq 1                      ; zstr or 0
    .kind:  resb 1                      ; NODE_STAT / ABILITY / KEYSTONE / PATH
    .stat:  resb 1                      ; stat id / ability id / KS id / archetype 1..4
    .max:   resb 1                      ; max rank
    .arch:  resb 1                      ; owning archetype 1..4, 0 = bridge
    .value: resd 1                      ; per rank
    .x:     resb 1                      ; web cell, signed, screen axes (y down)
    .y:     resb 1
    .level: resb 1                      ; level required
    .pad:   resb 5
endstruc
%if WEBNODE_size != 32
%error "WEBNODE must be 32 bytes"
%endif

; rpg_ability_info record: one class ability
struc ABILINFO
    .name:     resq 1
    .desc:     resq 1
    .resource: resd 1                   ; RES_*
    .cost:     resd 1
    .cooldown: resd 1                   ; seconds
    .pad:      resd 1
endstruc
%if ABILINFO_size != 32
%error "ABILINFO must be 32 bytes"
%endif

; RPG extension, stored in WORLDHDR.rpgx (v5)
struc RPGEXT
    .ranks:   resb 32                   ; rank of node branch*6 + tier (0..17)
    .attr:    resw NUM_ATTRS            ; attribute points spent
    .version: resb 1                    ; RPGX_VERSION; 0 = refund on load
    .pad:     resb 215
endstruc
%if RPGEXT_size != 256
%error "RPGEXT must be 256 bytes"
%endif

; rpg_stat_info record: display data of one stat
struc STATINFO
    .label:  resq 1                     ; zstr "Melee damage"
    .suffix: resq 1                     ; zstr "% melee damage"
    .fmt:    resb 1                     ; FMT_*
    .icon:   resb 1                     ; atlas tile
    .pad:    resb 6
endstruc
%if STATINFO_size != 24
%error "STATINFO must be 24 bytes"
%endif

; gear.asm affix table record
struc AFFIXDEF
    .stat:  resb 1
    .lo:    resb 1
    .hi:    resb 1
    .tlo:   resb 1                      ; per tier
    .thi:   resb 1
    .pad:   resb 1
    .kinds: resw 1                      ; bit 1 << GK_*
    .word:  resq 1                      ; zstr name prefix
endstruc
%if AFFIXDEF_size != 16
%error "AFFIXDEF must be 16 bytes"
%endif

; one decoded gear affix
struc GEARAFFIX
    .stat:  resd 1
    .value: resd 1
endstruc

; quests_current record: one quest of the chain
struc QUESTINFO
    .type:       resd 1                 ; Q_*
    .target:     resd 1                 ; mob type (Q_KILL) or item id (Q_BRING), else 0
    .count:      resd 1
    .xp:         resd 1
    .coins:      resd 1
    .item:       resd 1
    .item_count: resd 1
    .pad:        resd 1
    .title:      resq 1
    .line1:      resq 1
    .line2:      resq 1
endstruc
%if QUESTINFO_size != 56
%error "QUESTINFO must be 56 bytes"
%endif

; trade_offer record: give give_n items for get get_n items
struc TRADEOFFER
    .give:   resd 1
    .give_n: resd 1
    .get:    resd 1
    .get_n:  resd 1
endstruc
%if TRADEOFFER_size != 16
%error "TRADEOFFER must be 16 bytes"
%endif

; a site (village, dungeon, crypt, camp); lo/hi = inclusive trigger box. Absolute coordinates in
; region_plan's output, local ones in the runtime cache sites[]
struc SITE
    .kind:  resd 1
    .index: resd 1                      ; FAC_* for camps
    .x:     resd 1
    .y:     resd 1                      ; ground level (village, camp) or floor y (dungeon, crypt)
    .z:     resd 1
    .lo_x:  resd 1
    .lo_y:  resd 1
    .lo_z:  resd 1
    .hi_x:  resd 1
    .hi_y:  resd 1
    .hi_z:  resd 1
    .rx:    resd 1                      ; its region
    .rz:    resd 1
    .slot:  resd 1                      ; its index in region_plan's output
endstruc                                ; 56 bytes

; persistent state of one site, WORLDHDR.sites, keyed by (rx, rz, slot)
struc SITESTATE
    .rx:    resd 1
    .rz:    resd 1
    .slot:  resb 1
    .kind:  resb 1
    .kills: resb 1
    .flags: resb 1                      ; SS_CLEARED, SS_FREED
endstruc                                ; 12 bytes

; one loaded 16 x 256 x 16 column of the streamed world
struc COLUMN
    .cx:     resd 1                     ; absolute chunk coordinates
    .cz:     resd 1
    .state:  resd 1                     ; COL_*
    .flags:  resd 1                     ; CF_*
    .dirty:  resd 1                     ; bit cy = chunk cy needs a remesh
    .top:    resd 1                     ; highest non-AIR y, -1 if none
    .chunks: resq COL_CHUNKS            ; CHUNK_BYTES each; 0 = all AIR, light 0xF0
    .biome:  resb 256                   ; BIOME_* at (lz<<4)|lx
endstruc                                ; 408 bytes

; a chest the generator placed; its loot is rolled on install
struc GENCHEST
    .x:     resd 1                      ; absolute cell
    .y:     resd 1
    .z:     resd 1
    .table: resd 1                      ; 0 dungeon, 1 crypt, 2 camp
endstruc                                ; 16 bytes

; a column being generated (worker thread) or decoded from a region file
struc GENBUF
    .cx:      resd 1                    ; absolute chunk coordinates
    .cz:      resd 1
    .state:   resd 1                    ; GB_*
    .session: resd 1
    .top:     resd 1
    .nchests: resd 1
    .nconts:  resd 1                    ; containers decoded from a region blob
    .pad:     resd 1
    .blocks:  resb 65536                ; (y<<8)|(lz<<4)|lx
    .biome:   resb 256
    .chests:  resb MAX_GEN_CHESTS * GENCHEST_size
    .conts:   resb MAX_COL_CONTS * CONTAINER_size
endstruc

; the terrain of one block column (worldgen.asm terrain_cell's output)
struc TCELL
    .h:      resd 1                     ; surface height in 8..240
    .biome:  resd 1                     ; BIOME_*
    .top:    resd 1                     ; block at y = h
    .f1:     resd 1                     ; blocks at h - 1, h - 2, h - 3 (the filler)
    .f2:     resd 1
    .f3:     resd 1
    .deep:   resd 1                     ; blocks at h - 4 .. h - 6 (STONE, or SANDSTONE in deserts)
    .cover:  resd 1                     ; block placed at h + 1 when the column is above water (0 = none)
    .cold:   resd 1                     ; 1 when the temperature is below the snow line (water freezes)
endstruc
; terrain cells around a column being generated: the column plus a 3 cell margin (trees that cross its
; border, cave pools), index (lz + 3) * TC_W + lx + 3
%define TC_W        22
%define TC_CELLS    484

; a road between two camps of one super-region (structures.asm roads_edges), absolute cells
struc ROADEDGE
    .ax:      resd 1                    ; camp centres: A = the start, B = the end
    .az:      resd 1
    .bx:      resd 1
    .bz:      resd 1
    .faction: resd 1                    ; A's faction
    .key:     resd 1                    ; hash32(sx, sz, 900 + i) | 1
endstruc                                ; 24 bytes

; a boat: boats[MAX_BOATS] in boats.asm, local coordinates; named BOATENT because BOAT is the item id
struc BOATENT
    .body:  resb BODY_size              ; y = bottom; yaw = heading
    .used:  resd 1
    .speed: resd 1                      ; float, blocks/s along yaw
endstruc                                ; 76 bytes

struc BOATSAVE
    .x:   resd 1                        ; floats, local
    .y:   resd 1
    .z:   resd 1
    .yaw: resd 1
endstruc                                ; 16 bytes

; v6 world header (world.hdr); offsets are load-bearing (save files, verification patches)
struc WORLDHDR
    .magic:      resb 8                 ; "ACRAFT06"
    .seed:       resd 1
    .mode:       resd 1
    .time:       resd 1
    .name:       resb 33                ; NUL-terminated, <= 32 chars
    .pad0:       resb 3
    .spawn_x:    resd 1                 ; world spawn cell, absolute
    .spawn_y:    resd 1
    .spawn_z:    resd 1
    .player:     resb BODY_size         ; @68, local
    .health:     resd 1                 ; @136
    .food:       resd 1
    .saturation: resd 1                 ; float
    .exhaustion: resd 1                 ; float
    .sel:        resd 1                 ; @152
    .inventory:  resb INV_SLOTS * 4     ; @156
    .origin_x:   resd 1                 ; @300
    .origin_z:   resd 1                 ; @304
    .bed_x:      resd 1                 ; @308: absolute foot cell
    .bed_y:      resd 1
    .bed_z:      resd 1
    .bed_set:    resd 1                 ; @320
    .breath:     resd 1                 ; @324
    .boat_count: resd 1                 ; @328
    .boats:      resb MAX_BOATS * BOATSAVE_size ; @332
    .standing:   resw 8                 ; @588: int16 per faction (FAC_*), 5 used
    .champions:  resb 1                 ; @604: bit f = faction f's champion is defeated
    .pad_a:      resb 944 - 605
    .armor:      resb 16                ; @944
    .rpg:        resb RPGSAVE_size      ; @960
    .mob_count:  resd 1                 ; @1024
    .mobs:       resb MAX_MOBS * MOBSAVE_size ; @1028, local floats
    .site_count: resd 1                 ; @2308
    .sites:      resb MAX_SITESTATES * SITESTATE_size ; @2312
    .pad1:       resb 16384 - 14600
    .jewelry:    resb 16                ; @16384: 3 ITEMSTACKs + 4 spare
    .rpgx:       resb RPGEXT_size       ; @16400
    .pad2:       resb WORLD_HDR_SIZE - 16656
endstruc                                ; 32768 bytes
%if WORLDHDR_size != WORLD_HDR_SIZE
%error "WORLDHDR must be WORLD_HDR_SIZE bytes"
%endif
%if WORLDHDR.boats + MAX_BOATS * BOATSAVE_size != 588 || WORLDHDR.mobs + MAX_MOBS * MOBSAVE_size != 2308 || WORLDHDR.sites + MAX_SITESTATES * SITESTATE_size != 14600 || WORLDHDR.rpgx + RPGEXT_size != 16656
%error "WORLDHDR v6 layout drifted"
%endif

struc SETTINGS
    .fov:          resd 1               ; 50..110, default 70
    .sensitivity:  resd 1               ; 10..300 %, 100
    .render_dist:  resd 1               ; 2..16 chunks, 8
    .volume:       resd 1               ; 0..100, 100
    .difficulty:   resd 1               ; 0..3, 2
    .invert_mouse: resd 1               ; 0/1, 0
    .vsync:        resd 1               ; 0/1, 1
    .fullscreen:   resd 1               ; 0/1, 0
    .gui_scale:    resd 1               ; 0 = auto, 1..4
    .keys:         resd NUM_BINDINGS    ; GLFW key codes, 32..348
endstruc

struc TEXTFIELD
    .buf: resb 33
    .pad: resb 3
    .len: resd 1
    .max: resd 1
endstruc

struc SLIDERDEF
    .value:  resq 1                     ; int32*
    .prefix: resq 1                     ; zstr
    .suffix: resq 1                     ; zstr
    .min:    resd 1
    .max:    resd 1
endstruc

struc WORLDENTRY
    .file:  resb 64                     ; file name only
    .name:  resb 33
    .pad:   resb 7
    .mtime: resq 1
    .mode:  resd 1                      ; MODE_*
    .seed:  resd 1
    .valid: resd 1                      ; 0 unreadable, 1 ok, 2 old version (pre-0.9)
    .pad2:  resd 1
endstruc                                ; 128 bytes

struc SFXLAYER
    .sound:  resd 1
    .wave:   resd 1                     ; 0 noise, 1 square, 2 saw
    .f0:     resd 1                     ; floats
    .f1:     resd 1
    .lp:     resd 1
    .hp:     resd 1                     ; int32
    .env:    resd 1                     ; int32: 0 exp, 1 linear
    .half:   resd 1                     ; floats
    .attack: resd 1
    .start:  resd 1
    .dur:    resd 1
    .amp:    resd 1
    .vdepth: resd 1
    .vrate:  resd 1
endstruc

; an item entity lying in the world (not saved with the world)
struc DROP
    .x:     resd 1                      ; floats, .y = bottom
    .y:     resd 1
    .z:     resd 1
    .vx:    resd 1
    .vy:    resd 1
    .vz:    resd 1
    .age:   resd 1                      ; steps since spawn
    .delay: resd 1                      ; steps before it can be picked up
    .id:    resb 1                      ; 0 = free slot
    .count: resb 1
    .dmg:   resw 1
endstruc

; a flying or stuck arrow (not saved with the world); named ARROWENT because ARROW is the item id
struc ARROWENT
    .x:      resd 1                     ; floats
    .y:      resd 1
    .z:      resd 1
    .vx:     resd 1
    .vy:     resd 1
    .vz:     resd 1
    .age:    resd 1                     ; steps
    .stuck:  resd 1                     ; 0 flying, else steps stuck
    .owner:  resd 1                     ; OWNER_PLAYER, OWNER_MONSTER, OWNER_FOLK + faction
    .damage: resd 1
    .pickup: resd 1                     ; 0/1
    .live:   resd 1                     ; 0/1
    .kind:   resd 1                     ; PROJ_ARROW, PROJ_BULLET, PROJ_ROCKET, PROJ_BOLT, PROJ_FIREBALL
    .flags:  resd 1                     ; AF_CRIT, AF_EXPLOSIVE, AF_BIG, AF_BLEED, AF_ATTACK; bits 8..10 element
endstruc                                ; 56 bytes

; a primed TNT block: a physics body (y = bottom of the 0.98 cube) burning down (not saved)
struc PRIMED
    .body: resb BODY_size
    .fuse: resd 1                       ; steps; 0 = free
endstruc

; a burning cell (the world holds FIRE there)
struc FIREENT
    .x:    resd 1
    .y:    resd 1                       ; -1 = free slot
    .z:    resd 1
    .age:  resd 1                       ; steps
    .tick: resd 1                       ; steps to the next spread / burn roll
endstruc

; an effect particle: explosion fire, smoke, block debris (not saved)
struc PARTICLE
    .x:    resd 1                       ; floats, centre
    .y:    resd 1
    .z:    resd 1
    .vx:   resd 1
    .vy:   resd 1
    .vz:   resd 1
    .age:  resd 1                       ; steps
    .life: resd 1                       ; steps
    .size: resd 1                       ; float edge length
    .kind: resd 1                       ; 0 free, FX_FIRE .. FX_GOLD
    .tile: resd 1                       ; atlas tile of a debris cube
endstruc

struc VERTEX
    .x:   resw 1
    .y:   resw 1
    .z:   resw 1
    .pad: resw 1
    .u:   resw 1
    .v:   resw 1
    .r:   resb 1
    .g:   resb 1
    .b:   resb 1
    .a:   resb 1
endstruc
