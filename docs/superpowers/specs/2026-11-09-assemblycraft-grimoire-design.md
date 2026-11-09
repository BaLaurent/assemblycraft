# AssemblyCraft 0.10.2 "Grimoire": whimsical grimoire UI with a character silhouette, and classes replaced by one shared skill web

## Context

**What the user asked for:**
- Every interface is ugly ("minimaliste beaucoup trop simple"): the HUD, inventory, menus and RPG screens are flat grey rectangles. The game is an RPG, so the UI must look whimsical, like a grimoire, with a character silhouette carrying the equipment slots.
- The class system goes away. One very large skill tree holds every passive and active skill of the former classes. The player's archetype comes from where he spends points, mixing archetypes is allowed, and new archetypes or passives are added as table rows, never as a class.

**Decisions the user made:**
- Style "Grimoire pixel": cream parchment, brown leather binding, gold corners and filigree, sepia ink, illuminated titles. Everything is 16 px pixel art in the atlas.
- A mockup is approved BEFORE any UI code is written (checkpoint in Wave 1).
- A drawn silhouette, not a 3D model, with the equipment slots around it.
- The tree is a central web: start in the centre, one quarter per archetype, hybrid nodes on the borders between neighbouring quarters, progress by adjacency. The page pans and zooms.
- Respec is paid in coins, from the grimoire: cost 10 × level gold coins, every point refunded.

**End state:**
- No class choice screen and no class byte in use.
- A 88-node web: 4 path nodes (one per archetype), the 72 former class nodes, and 12 bridge nodes.
- A freely bindable 4-slot ability bar.
- An archetype title ("Warrior", "Spellblade", ...) derived from the points spent.
- Every screen and the HUD drawn with textured 9-slice parchment, leather and gold frames, ink text, and the silhouette inventory book.
- `make test` green: 183 tests (178 today + 5 new), warning-free build. Old 0.10.1 worlds load with their skill points refunded.

**Repo:** `/run/media/octopusman/Games/Experiences/assemblycraft` (x86-64 NASM, HEAD `7c1b90d`, branch `master`, remote `origin` = private `BaLaurent/assemblycraft`).

## Conventions (all waves)

- Each `.asm` file: `%include "common.inc"`, `default rel`, explicit sections, own `extern`/`global` lines, SysV ABI (rsp 16-aligned at every call; rbx/rbp/r12–r15 callee-saved), a header comment with signature and contract on every function, byte ids loaded with `movzx`.
- A test is `test_<name>() → eax` (0 = pass), registered in `src/selftest.asm` (an `extern`, a `TEST` row and a `TESTNAME` row, appended in plan order). Every new assertion gets a negative control: break the code once in a scratch copy, see the test fail, restore.
- Workers work in scratch copies: `REPO=/run/media/octopusman/Games/Experiences/assemblycraft; rm -rf /tmp/ac102-<w> /tmp/ac102-<w>-base && mkdir -p /tmp/ac102-<w> && rsync -a --exclude build --exclude .git --exclude .omp $REPO/ /tmp/ac102-<w>/ && rsync -a $REPO/src/ /tmp/ac102-<w>-base/`. They never run git, edit only owned files, put fakes of sibling symbols in `src/zz_stub.asm` (never copied back), and report: owned files, `selftest.asm` lines, `make test` tail, stubs, deviations, negative controls, unowned call sites needing wiring. The integrator copies back owned files only, after a `cmp` against the base.
- Only the integrator runs git: one commit per step named below, `git push` at the end of each wave. Never add `.omp/` or `.asm-lsp.toml`.
- Live checks use omabox from `$HOME`: `omabox up --audio`; install with `H=$(omabox -b default path --home); cp build/assemblycraft "$H/.ac.new" && mv -f "$H/.ac.new" "$H/assemblycraft"`; launch with `omabox -b default run -d --wait -- /home/sbx/assemblycraft --data-dir /home/sbx/acv102 --play NAME [--creative --seed N]`; capture with `omabox -b default shot --window assemblycraft --fit 960`. Mouse look does not reach the game in a box; clicks do. The throwaway header patcher `/tmp/acpatch9.py` (if missing, rewrite it: `world.hdr` offsets come from `struc WORLDHDR` in `common.inc`) gains the op `level=N`, which writes the byte at `WORLDHDR.rpg + RPGSAVE.level` (offset 961).

## Contracts (Wave 0 writes these; every worker codes against them)

### `src/theme.inc` (new; `%include "theme.inc"` in every UI file after `common.inc`)

Colour tokens (`RGBA` macro of `common.inc`); the texgen art uses the same RGB values:

|Token|Value|Use|
|---|---|---|
|`C_INK`|`RGBA(58,38,24,255)`|text on parchment, no shadow|
|`C_INK_SOFT`|`RGBA(110,84,58,255)`|secondary and disabled text on parchment|
|`C_RUBRIC`|`RGBA(150,32,28,255)`|headings and highlights on parchment (red ink)|
|`C_GOLD`|`RGBA(214,170,70,255)`|gold leaf rules, lit web edges, reachable-node ring|
|`C_GOLD_TEXT`|`RGBA(255,214,110,255)`|gold text on dark surfaces|
|`C_CREAM`|`RGBA(244,232,200,255)`|light text on dark surfaces (HUD, tooltips, ribbons)|
|`C_UMBER`|`RGBA(46,30,20,235)`|flat dark surface (loading screen, spine)|
|`C_DIM`|`RGBA(20,12,6,140)`|screen dimmer behind books and pages|
|`C_HOVER`|`RGBA(255,236,170,70)`|hover wash on cells and rows|
|`C_LOCKED`|`RGBA(110,84,58,110)`|locked web edges|
|`C_MANA`|`RGBA(70,110,230,255)`|mana fill|
|`C_STAMINA`|`RGBA(226,184,60,255)`|stamina fill|
|`C_STAMINA_LOW`|`RGBA(200,60,40,255)`|stamina fill below 25|
|`C_XP`|`RGBA(120,200,70,255)`|XP fill|
|`C_BLOOD`|`RGBA(200,40,40,255)`|boss bar fill|

`WHITE` (`0xFFFFFFFF`) moves into `theme.inc`. Every per-file `%define` of `WHITE`, `GREY`, `RED`, `GOLD`, `LABEL_COL`, `PANEL_COL`, `EDGE_COL`, `DIM_COL`, `GREY_COL` is deleted in the wave that restyles that file.

**9-slice kinds** (`NINE_*`, index into `nine_tab` in `ui.asm`: one record per kind, `dw tile, db border, db 0`):

|Kind|Id|Tile|Border|Look|
|---|---|---|---|---|
|`NINE_PAGE`|0|327|4|parchment page: 1 px ink rim, 1 px gold rule, 2 px darker parchment margin, gold dot in each corner, 8×8 parchment-noise centre|
|`NINE_LEATHER`|1|328|4|brown leather with a dashed cream stitch 2 px inside the rim|
|`NINE_SLOT`|2|329|2|recessed parchment cell: 1 px ink rim, darker parchment with a 1 px top-left inner shadow|
|`NINE_BUTTON`|3|330|3|light parchment plate, 1 px gold rim inside a 1 px ink rim|
|`NINE_BUTTON_HOT`|4|331|3|the same, brighter parchment and a 2 px gold rim|
|`NINE_BUTTON_OFF`|5|332|3|the same, greyed parchment, ink-soft rim|
|`NINE_TOOLTIP`|6|333|3|dark umber page with a 1 px gold rim|
|`NINE_RIBBON`|7|334|4|crimson ribbon; transparent swallowtail notches in the left and right corner texels|
|`NINE_BAR`|8|335|2|bar frame: 1 px ink, 1 px gold, transparent centre|
|`NINE_RUNE`|9|336|3|blue-grey carved stone (ability slot)|
|`NINE_SELECT`|10|337|3|ornate gold frame with a transparent centre (hotbar selection)|
|`NINE_NOTE`|11|338|3|small pinned paper note|
|`NINE_NODE_STAT`|12|339|5|round ink medallion on parchment|
|`NINE_NODE_ABIL`|13|340|5|gold-rimmed shield|
|`NINE_NODE_KEY`|14|341|5|crimson-and-gold star-cornered frame|
|`NINE_NODE_PATH`|15|342|5|double gold ring (archetype path)|

**Other tiles** (`common.inc`, after `TILE_LAVA`):
- `TILE_NINE0 327` (kinds above).
- `TILE_COMPASS 343`: the web centre ornament, a gold compass rose, drawn at 32×32.
- `TILE_SLOT_HEAD 344`, `TILE_SLOT_CHEST 345`, `TILE_SLOT_LEGS 346`, `TILE_SLOT_FEET 347`, `TILE_SLOT_RING 348`, `TILE_SLOT_AMULET 349`: empty-slot ink glyphs on transparency.
- `TILE_QUILL 351`: a quill drawn left of a hovered button label.
- `TILE_SIL0 365`: the silhouette, a 3 × 6 tile block (columns 13..15, rows 22..27). Sub-tile (r, c) is `TILE_SIL0 + 16r + c`, drawn as 48 × 96 GUI units.
- Tiles 48..56 (hearts, food, armor) are redrawn in place in the new palette. Their ids and 9×9 layout are unchanged.

### `ui.asm` API (Wave 2 step U0 implements; Wave 2 workers call it)

- `ui_nine(edi kind, esi x, edx y, ecx w, r8d h)` and `ui_nine_tint(edi kind, esi x, edx y, ecx w, r8d h, r9d rgba)`: draw the kind's tile as a 9-slice. 1 texel = 1 GUI unit.
  - Corners: b × b texels at 1:1.
  - Edges: the tile's middle strip (16 − 2b texels) repeated along the edge, the last piece cut short with its uv cut to match.
  - Centre: the inner (16 − 2b)² region repeated in both axes, cut at the far edges.
  - When w < 2b or h < 2b, b becomes min(w, h) / 2.
  - `ui_nine` is `ui_nine_tint` with `WHITE`.
- `ui_nine_layout(rdi out, esi w, edx h, ecx b) → eax n`: the pure geometry of the rule above. It writes n records `{x0, y0, x1, y1, u0, v0, u1, v1}` (8 int32: unit offsets in the rect, texel offsets in the tile, the record `quad_uv` already reads) and clamps at `NINE_MAX_QUADS 2048` records. `ui_nine_tint` draws from a `.bss` buffer of that size.
- `ui_text_ink(rdi s, esi x, edx y, ecx rgba, r8d scale) → eax advance`: `ui_text` without the shadow, for text on parchment.
- `ui_line(edi x0, esi y0, edx x1, ecx y1, r8d rgba, r9d width)`: an untextured quad of that width along the segment.
- `ui_clip(edi x, esi y, edx w, ecx h)` / `ui_unclip()`: `glScissor` in framebuffer pixels: x·s, `ui_fb_h` − (y + h)·s, w·s, h·s, with s = `ui_scale`. `ui_begin` stores the framebuffer height in a new `ui_fb_h`. Add `glScissor` to the externs and `GL_SCISSOR_TEST 0x0C11` to `gl.inc`.
- `ui_ribbon(rdi s, esi cx, edx y)`: a `NINE_RIBBON` (text width + 24) × 14 centred on cx, top y, with `s` in `C_CREAM` at y + 3.
- `ui_book(edi x, esi y, edx left_w, ecx right_w, r8d h)`: an open book.
  - Leather cover `(x − 6, y − 6, left_w + 4 + right_w + 12, h + 12)`.
  - Left page `NINE_PAGE (x, y, left_w, h)`; skipped when left_w is 0, and then the cover starts at the right page.
  - Spine: a 4-wide `C_UMBER` rect at `x + left_w`, with a 1 px `C_GOLD` stitch every 6 units down its middle.
  - Right page `NINE_PAGE (x + left_w + 4, y, right_w, h)`.
- Restyled, same signatures:
  - `ui_panel` → `NINE_PAGE`.
  - `ui_button`: `NINE_BUTTON` / `NINE_BUTTON_HOT` (hovered) / `NINE_BUTTON_OFF`, with the label in `C_INK` or `C_INK_SOFT` via `ui_text_ink`. A hovered button draws `TILE_QUILL` 12×12 at (label x − 14, y + 4).
  - `ui_slider`: a `NINE_BAR` track and a `NINE_BUTTON_HOT` 8×20 knob, label in `C_INK`.
  - `ui_textfield`: a `NINE_SLOT` background, `C_INK` text and caret.
  - `ui_slot`: a `NINE_SLOT` 18×18 cell and a `C_HOVER` wash on hover. Counts stay `ui_text` in `C_CREAM` with a shadow.
  - `ui_tooltip` / `ui_tooltip_lines`: a `NINE_TOOLTIP` background with a 4-unit pad. The existing light line colours stay, so rarity colours stay readable.

### Skill web (`common.inc` + `rpg.asm`; Wave 1 CORE implements)

- **Renames**, as a clean cutover (no aliases):
  - `CLASS_NONE/WARRIOR/MAGE/ARCHER/ROGUE` (0..4) → `ARCH_NONE/WARRIOR/MAGE/ARCHER/ROGUE` (0..4).
  - `NUM_CLASSES` → `NUM_ARCHETYPES 4`.
  - `RPGSAVE.class` → `RPGSAVE.legacy_class` (read only by the v1 migration, written 0).
  - `RPGEXT.ranks` → `RPGEXT.legacy` (32 bytes, always 0).
  - `FCLASS_*` (faction fighters) is a different system and is not touched.
- **Removed:** `CLASSINFO`, `NUM_NODES`, `NODES_PER_BRANCH`, `ST_CLASS` (with the states after it renumbered down by one and the `screens` table in `app.asm:71-76` updated), `rpg_class`, `rpg_set_class`, `rpg_class_info`, `rpg_branch_name`, `rpg_node_info`, `rpg_ability_unlocked`, `screen_class`, `class_tab`, `CINFO`, `abil_node`.
- **New constants:**
  - `NUM_ABILITIES 16` (ability id = (arch − 1)·4 + former slot).
  - `ABIL_SHADOWSTEP 12`.
  - `NUM_KEYSTONES 12`.
  - `NODE_PATH 3`.
  - `NUM_WEB_NODES 88`, `WEB_MAX 128`.
  - `RPGX_VERSION 2`.
  - `KIT_COMMON_BIT 0x80`.
- **`struc RPGEXT`** (still 256 bytes):

  |Offset|Field|Content|
  |---|---|---|
  |+0|`.legacy` resb 32|always 0|
  |+32|`.attr` resw 4|unchanged|
  |+40|`.version` resb 1|2|
  |+41|`.kits` resb 1|bit a − 1: archetype a's kit given; `KIT_COMMON_BIT`: common kit given|
  |+42|`.bar` resb 4|ability id + 1 per slot, 0 = empty|
  |+46|`.pad1` resb 2||
  |+48|`.web` resb 128|rank of web node i|
  |+176|`.pad2` resb 80||

- **`struc WEBNODE`** (32 bytes, `%error` size check):

  |Field|Size|Content|
  |---|---|---|
  |`.name`|q|zstr|
  |`.desc`|q|zstr or 0|
  |`.kind`|b|`NODE_STAT`/`ABILITY`/`KEYSTONE`/`PATH`|
  |`.stat`|b|stat id / ability id / KS id / archetype 1..4|
  |`.max`|b|max rank|
  |`.arch`|b|owning archetype 1..4, or 0 for a bridge|
  |`.value`|d|per rank|
  |`.x`, `.y`|b each, signed|web cell, screen axes, y down|
  |`.level`|b|level required|
  |`.pad`|resb 5||

- **Node ids:**
  - Path of archetype a = a − 1 (0..3).
  - Former node n (= branch·6 + tier) of archetype a = 4 + (a − 1)·18 + n (4..75).
  - Bridge k (0..2) between archetype a and the next one clockwise = 76 + (a − 1)·3 + k (76..87).
- **`rpg.asm` exports:**
  - `rpg_web_node(edi node) → rax WEBNODE*` (0 out of range).
  - `rpg_rank(edi node) → eax`.
  - `rpg_can_spend(edi node) → eax`: 0 ok, 1 no points, 2 maxed or invalid, 3 level too low, 4 not connected.
  - `rpg_spend(edi node) → eax 1/0`.
  - `rpg_web_linked(edi a, esi b) → eax 0/1`.
  - `web_edges` (dw pairs) and `web_edge_count` (dd).
  - `rpg_ability_learned(edi ability) → eax 0/1`.
  - `rpg_ability_info(edi ability) → rax ABILINFO*`.
  - `rpg_ability_tile(edi ability) → eax tile`.
  - `rpg_bar_ability(edi slot) → eax ability id or −1`.
  - `rpg_bar_set(edi slot, esi ability) → eax 1/0`.
  - `rpg_archetype_ranks(edi arch) → eax`.
  - `rpg_archetype() → eax 0..4`.
  - `rpg_title() → rax zstr`.
  - `rpg_begin()`.
  - `rpg_respec_cost() → eax` (= 10 × level).
  - Unchanged: `rpg_level`, `rpg_points`, `rpg_respec`, `rpg_attr*`, `rpg_stat*`, `rpg_keystone`.
- **`abilities.asm`:** `abilities_cd` / `abilities_cd_total` become `resd NUM_ABILITIES`, indexed by ability id. `abilities_use(edi slot, ...)` keeps its signature.

## Design data

### Web layout (Wave 1 CORE builds the tables with `%rep` macros from these formulas, not by hand)

Archetypes go clockwise, each with its own frame: outward u, lateral v (+v towards the next archetype clockwise). Cell (x, y) on screen, y down:

|a|Archetype|Mapping|
|---|---|---|
|1|Warrior, north|x = v, y = −u|
|2|Mage, east|x = u, y = v|
|3|Archer, south|x = −v, y = u|
|4|Rogue, west|x = −u, y = −v|

Rows, in archetype-local (u, v):
- **Path node:** (2, 0). Name "Path of the Warrior/Mage/Archer/Rogue". The desc is the former class card's three lines joined by ". " plus ". Learns <slot-0 ability name>.". Kind `NODE_PATH`, `.stat` = a, max 1, level 1. Icon: `TILE_CLASS0 + a − 1`. Its rank adds `base_stats[a] − base_stats[0]` to every stat and teaches ability (a − 1)·4.
- **Former node branch b, tier t:** (3 + t, (b − 1)·(1 + t)), so branch 0 fans to −v, branch 1 runs straight, branch 2 fans to +v.
  - Name, stat, value and kind come from today's `node_tab` row of that class and node.
  - Max: stat nodes 5, others 1.
  - Level `tier_level[t]` (1, 4, 9, 15, 22, 30).
  - Former ability nodes (n = 7, 9, 15, slots 1, 2, 3) get `.stat` = ability id (a − 1)·4 + slot.
- **Bridge k between a and next(a) = a mod 4 + 1:** (2 + t, 2 + t) with t = 2k + 1, `.arch` 0, kind `NODE_STAT`, max 3, level `tier_level[t]` (4, 15, 30):

  |Between|k 0|k 1|k 2|
  |---|---|---|---|
  |Warrior–Mage|Runed Steel, `STAT_ADD_FIRE` 1|Warded Plate, `STAT_MAX_MANA` 10|Spellblade, `STAT_ALL_DMG` 4|
  |Mage–Archer|Charged Tips, `STAT_ADD_SHOCK` 1|Far Sight, `STAT_AREA` 6|Starshot, `STAT_ALL_DMG` 4|
  |Archer–Rogue|Barbed Shafts, `STAT_BLEED_CHANCE` 6|Light Step, `STAT_MOVE_SPEED` 3|Skirmisher, `STAT_ATTACK_SPEED` 4|
  |Rogue–Warrior|Riposte Edge, `STAT_CRIT_CHANCE` 2|Scarred Hide, `STAT_THORNS` 2|Duelist, `STAT_WEAPON_DMG` 5|

- **Edges (104):**
  - path(a) – (a, b, 0) for b = 0..2;
  - (a, b, t) – (a, b, t + 1);
  - bridge(a, k) – (a, 2, 2k + 1);
  - bridge(a, k) – (next(a), 0, 2k + 1);
  - bridge(a, k) – bridge(a, k + 1).
- **Invariant** (test-checked): no two nodes share a cell, and every cell lies in −8..8.

### Rules

- **Reachable:** a path node is always reachable; any other node is reachable when at least one linked node has rank ≥ 1.
- **Spend reasons** (`rpg_can_spend`, checked in this order):
  - 2: invalid id or already at max;
  - 3: level < `.level`;
  - 4: not reachable;
  - 1: `rpg_points` = 0.
- **Points:** `rpg_points` = level − Σ web ranks.
- **`rpg_spend` on a node going from rank 0 to 1:**
  - an ability node, or a path node (whose ability is (a − 1)·4), puts its ability into the first empty bar slot, if any;
  - a path node whose kit bit is clear gives `kit_tab[a − 1]` and sets the bit. The Warrior also wears `IRON_CHESTPLATE` into armor slot 1 when it is empty, as `rpg_set_class` does today;
  - then `rpg_recompute` and `combat_refill`.
- **`rpg_ability_learned(ab)`:** the rank of the path node (ab mod 4 = 0) or the ability node (slots 1..3) of archetype ab / 4 + 1 is > 0.
- **`rpg_bar_set(slot, ab)`:** fails unless slot is 0..3 and the ability is learned. If ab is already in another slot, the two slots swap. Then `.bar[slot]` = ab + 1. `rpg_bar_set(slot, −1)` empties the slot.
- **`rpg_recompute`:**
  - Base row `base_stats[0]`.
  - Then every path rank adds its delta row.
  - Then `NODE_STAT` ranks; `NODE_KEYSTONE` ranks set the keystone bits.
  - The rest (attributes, the `KS_STAT` effects, gear, clamps, Bloodrage, publishing) is unchanged.
- **Archetype:**
  - `rpg_archetype_ranks(a)` = Σ ranks of nodes with `.arch` = a.
  - `rpg_archetype` = the a with the largest sum (ties → lower a), or 0 when all are 0.
- **`rpg_title`:** with s1 ≥ s2 the two largest sums (a1, a2):
  - s1 = 0 → "Wanderer";
  - s2 > 0 and 2·s2 ≥ s1 → the pair title;
  - else the archetype name ("Warrior", "Mage", "Archer", "Rogue").
  - Pair titles: {1,2} "Spellblade", {2,3} "Arcane Archer", {3,4} "Skirmisher", {1,4} "Duelist", {1,3} "Warden", {2,4} "Nightblade".
- **`rpg_ability_tile(ab)`:** s = ab mod 4, c = ab / 4. Tile `TILE_ABILITY0 + 3c + s` for s < 3, `TILE_ABILITY3_0 + c` for s = 3.
- **Respec:** `rpg_respec_cost` = 10 × level. `rpg_respec` takes the coins, zeroes `.web`, `.attr` and `.bar` (kits stay), then recomputes.
- **`rpg_begin`** (called by `enter_world`):
  1. When the common bit is clear: give the common kit and set the bit.
  2. When Σ web ranks = 0 and the save was not migrated this session: `hud_banner` "Open your grimoire (<key>) to choose a path", where <key> is the name of the `BIND_SKILLS` key, built the way `hud_xp` builds its hint. The `.bss` flag `rpg_migrated` is set by the `rpg_load` migration and cleared here, so a migrated world keeps its refund banner.
- **XP:** `rpg_add_xp` always works; the class gate is gone.
- **Staff bolt:** `abilities_staff_bolt` and `combat_weapon_preview` require `rpg_rank(ARCH_MAGE − 1) > 0` (node 1, the Mage path) instead of class Mage. `game.asm:1531` keeps the melee swing without it.
- **Gear:** `gear_pick_base` and `gear_drop_from_mob` take `rpg_archetype()` where they took the class. 0 keeps today's "none" behaviour: sword family, warrior blade.
- **Shadow Fang:** `combat.asm:1614` zeroes `abilities_cd + ABIL_SHADOWSTEP*4`.
- **`rpg_load`:**
  - Level outside 1..50 → `rpg_reset`.
  - Version 0 or 1:
    - kits = `KIT_COMMON_BIT` | (`legacy_class` in 1..4 ? bit (legacy_class − 1) : 0);
    - zero `.legacy`, `.web` and `.bar`;
    - version 0 also zeroes `.attr`;
    - `legacy_class` = 0, version = 2;
    - banner "Classes became one grimoire: skill points refunded".
  - Version 2: zero `.web` and `.bar` (with the same banner) when any rank > its max, Σ ranks > level, a ranked node is under its level, or a ranked node is not connected to a ranked path node through ranked nodes. Clear any bar entry whose ability is not learned.
  - XP and quest clamps stay as today.
- **`rpg_reset`:** level 1, everything else 0, version 2.

## Approach

### Wave 0 — contracts (integrator, inline; commit "0.10.2 contracts: grimoire theme, nine-slice kinds, skill web layout")

1. `git status` must be clean apart from `.omp/` and `.asm-lsp.toml`; HEAD `7c1b90d` or later.
2. Copy this plan to `docs/superpowers/specs/2026-11-09-assemblycraft-grimoire-design.md`.
3. Add `src/theme.inc` and the new `common.inc` tile ids, `NINE_*`, `NODE_PATH`, `NUM_ABILITIES`, `ABIL_SHADOWSTEP`, `NUM_KEYSTONES`, `NUM_WEB_NODES`, `WEB_MAX`, `KIT_COMMON_BIT` and `struc WEBNODE` (additions only; removals and the `RPGEXT` change happen in Wave 1 so the tree builds).
4. Check: warning-free build, `make test` 178/178.

### Wave 1 — two parallel workers (one `task` batch)

**ART (owns `texgen.asm`, `test_items.asm`, and throwaway files under `/tmp/ac102-mock/`)**
1. Draw tiles 327..351 and the silhouette block, and redraw 48..56, in `texgen.asm` after tile 326 and before the font. Use `BMP` (draw-free) for line art and `NBMP` / `NOISE_PIXEL` for parchment and leather noise, so older tiles keep their pixels. Every 9-slice tile follows the border width of its kind; the corners hold the ornament and the middle strip must tile seamlessly.
2. The silhouette is drawn procedurally over the 48×96 block (local px 0..47, py 0..95, one `TILE_BEGIN` per sub-tile, pixel = local coordinates). Its shape is the union of:
   - head ellipse centre (24, 12), rx 8, ry 9;
   - neck x 21..26, y 20..23;
   - torso trapezoid, x 13..34 at y 23 narrowing linearly to x 16..31 at y 52;
   - arms: quads (12, 24)–(16, 24)–(11, 56)–(7, 56) and their mirror x → 47 − x;
   - hands: circles r 3 at (9, 58) and (38, 58);
   - legs x 16..22 and 25..31, y 52..88;
   - feet x 14..22 and 25..33, y 88..93.

   A shape pixel with a 4-neighbour outside the shape is `C_INK`. Other shape pixels are parchment shade RGB(214, 190, 146), with noise m = 224 + (rng & 31). Outside the shape is transparent.
3. Add `test_grimoire_tiles` to `test_items.asm`. It asserts that each of tiles 327..342 has an opaque rim pixel at texel (0, 7), except `NINE_RIBBON` (334), whose left notch is transparent there, which is checked at texel (7, 0) instead. It also asserts that `TILE_SIL0`'s block has a `C_INK`-coloured pixel at local (24, 3), the top of the head outline (sub-tile row 0, column 1, texel (8, 3)).
4. Build the mockup, mechanically, with no asm UI code:
   - Atlas dump: `/tmp/ac102-mock/dump.c` (copy of `/tmp/w5h/dump.c`: `texgen_build` into a 256×512 RGBA buffer, written to a file), linked as `gcc -O1 -no-pie -pthread -o dump dump.c $(ls build/*.o | grep -v '/main.o') -lglfw -lGL -lpulse-simple -lm`.
   - Compositor `mock.py` (Python 3 + PIL):
     - load the atlas;
     - implement `nine()` with exactly the 9-slice rule of the contract;
     - render text from the atlas font (rows 256..303, glyph g at x (g & 15)·8, y 256 + (g >> 4)·8), with advance = ink width + 1 and blank width 3, as `ui_init` measures;
     - draw web lines as quads;
     - compose each screen at GUI 426×240 and upscale ×3 nearest.
   - Screens, each with the exact layouts of Wave 2 below:
     1. `hud.png`: over `/tmp/omabox-default-224328-123.png` resized to 426×240 if present, else a two-tone sky and grass. Full hotbar with a selection, 7 of 10 hearts, food, armor row, mana and stamina bars, XP bar "Level 7", ability bar with Charge and Fireball bound plus 2 empty slots, the banner "You learned Fireball", a 2-line quest note, a boss bar "The Fallen King".
     2. `inventory.png`: the survival book, Character page and satchel with sample items (iron helmet, chestplate, leggings and boots worn, a ring, an amulet, an iron sword in hand, a mixed satchel).
     3. `grimoire.png`: zoom 1 centred on the compass. Sample build: Path of the Warrior + Blademaster tiers 0..2 + Path of the Mage; Charge in Q, Fireball in G.
     4. `grimoire_overview.png`: zoom 0, the same build.
     5. `menus.png`: four 213×120 quadrants, each a downscaled full screen: title, pause, a chest page, the death page.
   - Plus `sheet.png`, a contact sheet of all five.
   - The compositor computes web cells with the formulas of Design data (its own copy).
5. **CHECKPOINT (user):** the integrator shows the six PNGs to the user and asks with `ask`: "Valider la maquette" / "Modifier (décris)". On changes, ART edits the tiles or the integrator edits the layout numbers in this design doc, re-renders, and asks again. No Wave 2 work starts before "Valider". Then commit "0.10.2 art: grimoire tiles and silhouette" (texgen + test), with the approved PNGs copied to `docs/superpowers/specs/grimoire-mockup/`.

**CORE (owns `common.inc` RPG section, `rpg.asm`, `abilities.asm`, `combat.asm`, `gear.asm`, `game.asm`, `app.asm`, `hud.asm`, `rpgscreens.asm`, `options.asm`, and the tests `test_rpg.asm`, `test_abilities.asm`, `test_melee.asm`, `test_status.asm`, `test_mobs.asm`, `test_gear.asm`, `test_structures.asm`, `test_hud.asm`)**

CORE keeps the old look in this wave. Wave 2 restyles the same files.
1. Make the contract changes of "Skill web": renames, removals, `RPGEXT` v2, `WEBNODE` tables (`web_tab`, `web_edges`, `web_edge_count`, `bridge` names, the title strings). Implement every function and rule of "Rules" in `rpg.asm`. Move each class card's three lines into its path node desc and delete `class_tab`. `base_stats` stays (row 0 = classless base, rows 1..4 = path deltas source).
2. **`abilities.asm`:**
   - `abilities_use(slot)`: ability = `rpg_bar_ability(slot)`, fail (dry fire) when −1.
   - Effect index = ability id; `IDX_*` values are unchanged.
   - Cooldowns are per ability.
   - Delete the class checks.
   - Staff bolt per "Rules".
3. **Call sites:**
   - `combat.asm:1614` and `:1788-1790`;
   - `gear.asm:815-845` and `:1067-1111`;
   - `game.asm:1531-1533`;
   - `app.asm:379-392`: `enter_world` calls `rpg_begin` then `ST_PLAYING`. Drop `screen_class` from the `screens` table.
4. **`hud.asm`:**
   - `hud_draw` always draws the XP and ability bars (the `rpg_class` gate at `:202-214` goes).
   - `hud_abilities` reads `rpg_bar_ability`; an empty slot draws its backing and key label only. Icon, tint and cooldown come from the ability id.
   - The F3 line "Class: …" becomes "Archetype: <rpg_title> Lv N XP a/b".
5. **`rpgscreens.asm`:**
   - Delete `screen_class` and the class branches.
   - The elder's respec button (`screen_dialog`, `:1776-1800`) is removed.
   - `screen_header(label, points, width)` shows "<rpg_title> - Level N".
   - Rewrite `screen_skills` as the functional web, in today's flat colours, with the final geometry and input of "Grimoire screen" in Wave 2, so Wave 2 only swaps primitives and colours. It includes two pure helpers:
     - `web_node_xy(edi node, esi zoom) → eax dx, edx dy`: node centre minus web origin = cell · (zoom ? 28 : 13);
     - `web_pick(edi mx, esi my, edx ox, ecx oy, r8d zoom) → eax node or −1`: half-size zoom 1: 11, or 14 for a path node; zoom 0: 5, or 6 for a path node. Nodes are tested in id order and the first hit wins.
6. **`options.asm`:** `s_b_skills` (`options.asm:80`, today "Skill Tree") becomes "Grimoire".
7. **Tests:**
   - Replace every `RPGSAVE.class` poke and `set_class` helper with taking the path: `rpg_reset`; set `rpg_state + RPGSAVE.level` to the level the scene needs; `rpg_spend(path)`; and for an ability node, `rpg_spend` along its branch. Replace `test_rpg.asm`'s expected-table copy (`:40-206`) with 8 expected rows checked field by field through `rpg_web_node` (kind, stat, max, arch, value, cell, level):

     |Node|Expected|
     |---|---|
     |0|Path of the Warrior, `NODE_PATH`, stat 1, max 1, arch 1, cell (0, −2), level 1|
     |3|Path of the Rogue, `NODE_PATH`, stat 4, max 1, arch 4, cell (−2, 0), level 1|
     |4|Weapon Mastery, `NODE_STAT`, `STAT_MELEE_DMG`, max 5, arch 1, value 6, cell (−1, −3), level 1|
     |29|Blink, `NODE_ABILITY`, ability 5, max 1, arch 2, cell (4, 0), level 4|
     |55|Hunter's Mark, `NODE_ABILITY`, ability 11, max 1, arch 3, cell (−4, 6), level 15|
     |63|Assassinate, `NODE_KEYSTONE`, `KS_ASSASSINATE`, max 1, arch 4, cell (−8, 6), level 30|
     |76|Runed Steel, `NODE_STAT`, `STAT_ADD_FIRE`, max 3, arch 0, value 1, cell (3, −3), level 4|
     |87|Duelist, `NODE_STAT`, `STAT_WEAPON_DMG`, max 3, arch 0, value 5, cell (−7, −7), level 30|

     The web-graph checks of `test_rpg_skill_spend_rules` (below) cover every other row.
   - `test_rpg_stats_from_class_and_ranks` is renamed `test_rpg_stats_from_paths_and_ranks`.
   - Rewrite, keeping their names: `test_rpg_levels_and_points`; `test_rpg_skill_spend_rules`, which now also covers the web graph (unique cells within −8..8, 104 valid edges, every node reachable from the paths, each reason 1..4, crossing a bridge into the next archetype); `test_rpg_attributes_and_respec` (cost 10 × level, kits kept, bar cleared); `test_rpg_keystones_and_caps`; `test_rpg_save_load_validates`, which also covers the v1 → v2 migration of a v1 header with `legacy_class` Mage and ranks: web zero, `.attr` kept, kits = `KIT_COMMON_BIT` | bit 1, banner set, level and XP kept.
   - New `test_ability_bar_binding`:
     - learning Path of the Mage fills slot 0 with Fireball;
     - `rpg_bar_set` swaps;
     - a cast from slot 2 after rebinding uses the ability's own cooldown, so rebinding does not reset it;
     - an empty slot dry-fires at no cost;
     - an unlearned ability cannot be bound.
   - New `test_archetype_titles`: Wanderer; Warrior; Spellblade at 4/2; Warrior at 5/2; Warden for Warrior + Archer; ties go to the lower id.
   - New `test_web_view_mapping` (in `test_hud.asm`):
     - `web_node_xy` of node 0 (Path of the Warrior, cell (0, −2)) at zoom 1 = (0, −56);
     - `web_pick` hits node 0 at origin + (0, −56) and at ± 14 on each axis, and misses at ± 15 (path half-size 14);
     - zoom 0 = (0, −26);
     - the compass centre returns −1.
   - Register the 3 new tests (`ability_bar_binding`, `archetype_titles`, `web_view_mapping`) in the scratch `selftest.asm`. `grimoire_tiles` comes from ART.
8. **Acceptance:**
   - Warning-free build.
   - `make test` passes, 182 once ART is merged (178 + `grimoire_tiles` + `ability_bar_binding` + `archetype_titles` + `web_view_mapping`).
   - `grep -nP "(?<!F)CLASS_(NONE|WARRIOR|MAGE|ARCHER|ROGUE)\b|NUM_CLASSES|rpg_class|rpg_set_class|ST_CLASS|screen_class|CLASSINFO|rpg_branch_name|rpg_node_info|rpg_ability_unlocked" src/*.asm src/*.inc` prints nothing.

**Integration of Wave 1:**
1. Copy back CORE (it does not wait for the checkpoint) and register its tests.
2. Build, `make test`, then commit "0.10.2 core: classes become one skill web, bindable ability bar, archetype titles".
3. Run an omabox smoke: a new seed-42 world opens straight into play with the banner, K opens the flat web, and taking the Warrior path gives the sword and worn chestplate with Charge in Q.
4. ART is committed after the checkpoint.

### Wave 2 — the look (after "Valider")

**U0 (integrator, inline; commit "0.10.2 ui: nine-slice, ink text, lines, clipping, restyled widgets"):** implement the whole `ui.asm` API of the contract. New test `test_ui_nine_layout`:
- 18×18 with b 2 → 16 records: 4 corners, 8 edge pieces and 4 centre pieces, since the inner region 12 covers the 14-unit middle as 12 + 2 on each axis;
- 176×166 with b 4: the records tile the rect exactly once (a per-unit coverage count of 1 over all 29,216 units);
- 6×30 with b 4 → b is clamped to 3;
- uv stay inside 0..16.

The suite is then at 183. Live check: title and pause buttons render as parchment plates.

**Then four parallel workers** (one `task` batch, each in a scratch copy, against the merged U0):

|Worker|Owns|Delivers|
|---|---|---|
|HUD|`hud.asm`, `test_hud.asm`|HUD layout below; the `ability_rows` test rows stay valid (ability bar geometry unchanged)|
|BOOK|`invscreen.asm`, `recipebook.asm`|inventory book, crafting, furnace, chest|
|MENUS|`menus.asm`, `options.asm`|title, worlds, create, rename, delete, pause, death, loading, settings, controls|
|PAGES|`rpgscreens.asm`|grimoire look, character sheet, trade, dialog, leader, shrine|

Every worker replaces flat `ui_rect` / `ui_frame` panels with the kinds below, switches text on parchment to `ui_text_ink` + `C_INK` / `C_INK_SOFT` / `C_RUBRIC`, deletes its per-file colour defines in favour of `theme.inc`, and gives each page title a `ui_ribbon` hanging over the page top (ribbon y = page y − 7).

**HUD** (`hud_hotbar` `:415`, `hud_bars` `:526`, `hud_xp` `:1041`, `hud_abilities` `:1189`, `hud_boss` `:1579`, `hud_quest` `:1642`, `hud_banner_draw` `:1770`):
- Hotbar backing: `NINE_LEATHER` 182×22 at (x0, y0).
- Hotbar cells: `NINE_SLOT` 18×18 at (x0 + 2 + 20i, y0 + 2). Icons stay at x0 + 3 + 20i.
- Selection: `NINE_SELECT` over the current 22×22 selection rect.
- Mana and stamina bars: positions and sizes unchanged, `C_MANA` / `C_STAMINA` / `C_STAMINA_LOW` fills, and a `NINE_BAR` frame (w + 2) × (h + 2) around each.
- XP bar: `NINE_BAR` frame (x0, y0 − 6, 182, 5) around the 180×3 fill `C_XP`. "Level N" in `C_GOLD_TEXT`, shadowed.
- Ability slots: `NINE_RUNE` 20×20 at the unchanged `hud_ability_pos` positions. Each key label sits on a `NINE_NOTE` tab (text width + 4) × 9 centred above its slot, text `C_INK` via `ui_text_ink`.
- Banner: a `NINE_RIBBON` behind the text, (scaled text width + 20) × (8·scale + 8), text `C_CREAM`.
- Boss: the name on a `ui_ribbon`; the bar in a `NINE_BAR` frame with a `C_BLOOD` fill.
- Quest tracker: a `NINE_NOTE` behind the lines, (widest line + 8) × (10·lines + 6), text `C_INK`.
- Health text, held-item name and gun ammo in `C_CREAM`, shadowed.
- Out of scope: F3, crosshair, mob bars, name plates and damage numbers keep their look.

**BOOK:**
- `screen_begin(show_counts, left)`: left 0 = no left page, 1 + `BOOK_CRAFT` / 1 + `BOOK_FURNACE` = recipe page, `LEFT_CHARACTER` (new, 3) = character page.
- Book geometry: right page = today's panel (`PANEL_W 176` × `PANEL_H 166` at px, py, so every inner `px+…` coordinate stays); left page 124 wide at px − 128; `ui_book(px − 128, py, 124 or 0, 176, 166)`. px = (ui_w − 316) / 2 + 128 with a left page, else (ui_w − 176) / 2. Dimmer `C_DIM`.
- Survival inventory:
  - The left page defaults to Character. Two tabs stand above the left page: "Character" at (lx + 4, py − 20) and "Recipes" at (lx + 64, py − 20), each 56×16, drawn `NINE_BUTTON_HOT` when selected and `NINE_BUTTON` otherwise, with the label in `C_INK` via `ui_text_ink`. A click switches the left page. The choice lives in `.bss` `inv_left` for the session. The left page has no ribbon title: the tabs name it.
  - Character page, with lx = px − 128:
    - `rpg_title` + " - Level N" in `C_RUBRIC`, centred at (lx + 62, py + 10);
    - silhouette at (lx + 38, py + 26);
    - armor refs 47..50 at (lx + 10, py + {28, 52, 76, 100});
    - amulet ref 80 at (lx + 96, py + 36), rings 78, 79 at (lx + 96, py + {60, 84});
    - the held item, display only, in a `NINE_SLOT` at (lx + 96, py + 108), with tooltip "In hand";
    - empty armor and jewelry cells show their `TILE_SLOT_*` glyph tinted `C_INK_SOFT`;
    - below: `TILE_HEART_FULL` via `ui_icon9` + "Health n/m" at (lx + 10, py + 128) and `TILE_ARMOR_FULL` + "Armor n" at (lx + 10, py + 140), `C_INK`.
  - Right page:
    - "Crafting" at (px + 48, py + 6), 2×2 grid at (px + 50, py + 18), arrow at (px + 92, py + 32), result at (px + 110, py + 28);
    - "Satchel" at (px + 8, py + 72); main grid and hotbar stay where they are (`py + 84`, `py + 142`).
- Creative: Character left page; the palette stays on the right page.
- Crafting table and furnace: recipe left page (as today). Chest: no left page.
- Recipe book (`recipebook.asm`):
  - background → the left page (it no longer draws its own panel);
  - cells → `NINE_SLOT`;
  - "cannot make" overlay `RGBA(150,32,28,90)`; "does not fit" `C_DIM`; hover frame `C_GOLD`.

**MENUS:**
- Title: "ASSEMBLYCRAFT" at scale 4 in `C_GOLD_TEXT` (shadowed); the subtitle on a `ui_ribbon`; version bottom-left in `C_CREAM`; buttons via `ui_button`.
- Worlds list: a `NINE_PAGE` instead of `ui_panel`. The selected row gets a `C_HOVER` wash and a `C_GOLD` frame. Text `C_INK` / `C_INK_SOFT`.
- Create, rename, delete: one `NINE_PAGE` (cx − 160, 30, 320, ui_h − 66) behind the widgets, with a `ui_ribbon` title.
- Pause: `C_DIM`, then a page (cx − 110, ui_h/4 − 20, 220, 116) with the ribbon "Game Menu".
- Death: `RGBA(80,0,0,120)` over the screen, then a page (cx − 110, ui_h/4 − 20, 220, 118); "You died!" scale 2 `C_RUBRIC`, cause `C_INK`.
- Loading: `C_UMBER` with `C_CREAM` text.
- Settings and controls: a page (cx − 165, 8, 330, ui_h − 16) behind the rows.

**PAGES — grimoire screen (`screen_skills`; geometry already built by CORE):**
- Spread: `ui_book(14, 14, (ui_w − 28 − 4) / 2, (ui_w − 28 − 4) / 2, ui_h − 28)`.
- Header: ribbon "Grimoire"; `rpg_title` + " - Level N" in `C_RUBRIC` at (24, 22); "Points: N" right-aligned at ui_w − 24, y 22.
- Web viewport (20, 34, ui_w − 40, ui_h − 76), clipped with `ui_clip`. Origin (ox, oy) in `.bss`, set to the viewport centre on first open each session. Zoom 1 at first open.
- Edges: `ui_line`, width 2 at zoom 1 and 1 at zoom 0. `C_GOLD` when both ends are ranked, `C_INK` when one is, `C_LOCKED` otherwise.
- Compass: `TILE_COMPASS` 32×32 (16 at zoom 0) on the origin. The archetype names are in `C_RUBRIC` beside their path node on the outward side (above Warrior, right of Mage, below Archer, left of Rogue).
- Nodes:
  - Frame by kind: stat, ability (also used for the path node's ability), keystone, path. Zoom 1: 22×22, path 28×28, icon 16×16 centred. Zoom 0: 9×9, path 12×12, no icon.
  - Unreachable nodes are drawn with `ui_nine_tint(…, RGBA(255,255,255,110))`. Reachable unranked nodes get a 1-unit `C_GOLD` `ui_frame` ring 1 unit outside.
  - Rank text "r/m" in `C_INK` at (node right − 4, node bottom − 2), zoom 1 only.
  - Icons: stat → `STATINFO.icon`; ability → `rpg_ability_tile`; keystone → `TILE_KEYSTONE`; path → `TILE_CLASS0 + a − 1`.
- Input:
  - Wheel up → zoom 1, down → zoom 0, keeping the cell under the mouse fixed.
  - LMB drag outside nodes pans; the origin is clamped so the 17×17-cell web keeps at least one cell inside the viewport.
  - LMB press-and-release on a node with under 3 units of travel → `rpg_spend`.
  - While hovering a learned ability or path node, an ability key (`UIINPUT.key_pressed` equal to the settings key of `BIND_ABILITY1/2/3/4`) → `rpg_bar_set(slot, ability)`.
  - The tooltip (`tooltip_wrapped`) gains, for learned actives, the line "Press Q/G/V/X to place it on your bar", built from the bound keys.
  - Tab → character sheet; close keys as today.
- Footer at y = ui_h − 38:
  - "Unlearn all: N coins" `ui_button` 120 wide at x 24, enabled when coins ≥ cost and Σ ranks > 0; on click `rpg_respec`.
  - 4 `NINE_RUNE` 20×20 slots centred at ui_w / 2 (step 23) with key notes and icons as on the HUD; RMB on a slot → `rpg_bar_set(slot, −1)`.
  - "Wheel: zoom  Drag: move" in `C_INK_SOFT`, right-aligned at ui_w − 24.
- Character sheet, trade, dialog, leader and shrine keep their geometry; `panel_begin` draws a page, and their text switches to ink.

**Integration of Wave 2:**
1. Copy back the four workers.
2. Set `menus.asm t_version` and `hud.asm s_dbg_title` to "AssemblyCraft 0.10.2".
3. Build warning-free and run `make test` (183 = 182 + `ui_nine_layout`).
4. Commit "0.10.2 grimoire look: HUD, inventory book with silhouette, menus, grimoire web".

### Wave 3 — live checks, sweep, docs (integrator)

1. **Live checks in omabox** on a new world `v102a` (seed 42), each with a screenshot placed side by side with its mockup PNG (`magick a.png b.png +append cmp.png`), then looked at:
   - a. HUD in Survival: hotbar, hearts, bars, XP, ability bar with keys, a banner.
   - b. Inventory book: Character page with armor equipped by clicks, the Recipes tab switching the left page, crafting a plank.
   - c. Grimoire: zoom 1 and zoom 0; pan by drag; learn Path of the Warrior (kit, Charge in Q); patch `level=20`, cross the Warrior–Mage bridge, learn Fireball, rebind Fireball to V with the V key; respec with coins (patch a stack of 200 `GOLD_COIN` via the patcher's `slot=` op).
   - d. Title, worlds, settings, pause, death.
   - e. Chest, furnace, crafting table, trade, shrine.
   - f. An old world copied from `acv101` (or any 0.10.1 world): opens, the refund banner shows, the ability bar is empty, the kit is not given twice.
2. Fix what the checks find, with a regression assertion where a unit test can catch it; commit "0.10.2 tuning from live checks".
3. Spawn 2 read-only `reviewer` subagents:
   - R1: `rpg.asm`, `abilities.asm`, `combat.asm`, `gear.asm`, `game.asm`, `app.asm`. Focus: migration, web rules, cooldown indexing, bar swaps, kit-once, stack alignment.
   - R2: `ui.asm`, `hud.asm`, `invscreen.asm`, `recipebook.asm`, `menus.asm`, `options.asm`, `rpgscreens.asm`, `texgen.asm`. Focus: `ui_nine_layout` bounds, the scissor reset on every exit path, hit boxes matching drawn boxes, no `GL_SCISSOR_TEST` left enabled after the grimoire, text colours readable on their backgrounds.

   Fix crash, corruption and broken-feature findings with regression assertions. Append "As built" and "Deferred" to the design doc. File every deferred item as a GitHub issue (`gh issue create -R BaLaurent/assemblycraft --label need-triage --label ready-for-human`) and list the numbers in the doc. Commit "0.10.2 sweep" and `git push`.

## Critical files & anchors

- `src/rpg.asm`: `base_stats` (`:46-57`), `tier_level` (`:61`), `abil_node` (`:62`, deleted), `kit_tab` (`:99-105`), `abil_tab` (`:235-251`, kept, now indexed by ability id), `node_tab` (`:284-360`, the source rows the web macros copy), `rpg_recompute` (`:746`), `rpg_set_class` (`:930`, its kit and chestplate logic moves into `rpg_spend`), `rpg_load` (`:1307`, the version-0 refund at `:1329-1337` is the migration pattern).
- `src/abilities.asm`: `abilities_use` (`:205-303`), `ab_effects` (`:138-142`), `abilities_cd` (`:147-148`), the staff-bolt class check (`:343-345`).
- `src/invscreen.asm`: `screen_begin` (`:97-157`, today it always puts the recipe book left in survival), `screen_inventory` (`:612-779`), the slot refs 47..50 and 78..80 (`common.inc:722-728`).
- `src/ui.asm`: `ui_begin` (`:85-206`, texture matrix and GL state; store `ui_fb_h` here), `quad_uv` (`:285`, the record `ui_nine_layout` emits), `ui_button` (`:576`), `ui_slot` (`:1054`).
- `src/texgen.asm`: the tile order rule (header `:1-27`, font last at `:1110-1141`); new tiles go between tile 326 and the font.

## Verification

1. Build and suite: `cd /run/media/octopusman/Games/Experiences/assemblycraft && make clean && make 2>&1 | grep -iE "warn|error"` prints nothing, and `make test` ends with `selftest: 183 passed, 0 failed`, three runs in a row.
2. The class grep from Wave 1 CORE's acceptance prints nothing. `grep -nE "PANEL_COL|EDGE_COL|LABEL_COL|DIM_COL|GREY_COL" src/*.asm` prints nothing.
3. New behaviour, headless (from the tests):
   - Path of the Mage at level 1 → slot 0 = Fireball (id 4), `rpg_points` = 0, the kit's `STAFF` in the inventory.
   - At level 15, from an empty web: `rpg_spend` 0 (Path of the Warrior), 16 (Endurance tier 0), 17 (Endurance tier 1), 76 (bridge Runed Steel) all return 1, and `rpg_can_spend(76)` returned 4 before node 17 was learned. Then `rpg_can_spend(23)` (Mage Fire tier 1 = 4 + 18 + 1) returns 0 although node 1 (Path of the Mage) has rank 0.
   - A v1 header with `legacy_class` 2 → `.kits` = `0x82` and an empty web.
4. Live: Wave 3 checks a–f, each with a mockup/screenshot pair.

## Assumptions & contingencies

- **Version:** this ships as "0.10.2"; the roadmap's 0.11 stays Quests. The user may rename it.
- **Font:** the existing 8×8 font is kept. If the mockup is judged "still too plain" because of the lettering, the checkpoint loop may add a serif title font as an extra atlas block (rows 28..31) used only by `ui_ribbon` and the title screen. That is decided at the checkpoint, not by a worker.
- **Old worlds:** they keep level, XP, attributes, gear and quest progress; skill points are refunded; the old class's kit is never given again.
- **Bridge node stats and pair titles** (tables above) are content the user may rename. The rules do not depend on them.
- **omabox:** if `omabox up` dies again (Hyprland exit status 1, as on 2026-11-08), run `omabox down default` once and retry once. If it still dies, the live checks are reported as blocked, the mockup PNGs stay the visual reference, and a GitHub issue is filed for the missing live checks.
- **GUI width:** if `ui_w` < 316 (only with a forced GUI scale on a small window), the inventory book drops its left page (as with `left` 0) and the tabs are hidden.
- **Wave 1 CORE slip:** if CORE is not finished when the user validates the mockup, U0 still starts (it only needs `ui.asm`), and the four Wave 2 workers start from the merged CORE.

## Mockup-approved adjustments (supersede the numbers above where they differ)

Approved by the user on 2026-11-09 from `docs/superpowers/specs/grimoire-mockup/`. The exact coordinates live in the mockup compositor (`/tmp/ac102-mock/mock.py`).

- Inventory left-page tabs: "Character" 70 wide at lx + 2, "Recipes" 52 wide at lx + 74. Title line is two lines (title, then "Level N").
- Grimoire footer button reads "Respec: N coins" (124 wide); hint "Wheel: zoom  Drag: move" right-aligned at ui_w - 20.
- Archetype labels: pinwheel (Warrior right of its node, Mage below, Archer left, Rogue above).
- Zoom 0 uses pitch 9 with 7/10-unit nodes so the whole web fits (`grimoire_overview_fit.png`); zoom 1 stays pitch 28.
- Rank "r/m" only on ranked multi-rank nodes.
- `TILE_COMPASS` is one 16x16 tile drawn at 32x32 units. Slot glyph tiles are white/grey, tinted `C_INK_SOFT`. `NINE_BAR` ring is translucent. `TILE_QUILL` is drawn by `ui_tile_icon` at size 12.
- Title screen gets a full-screen `NINE_LEATHER` backdrop (menus mockup).
- `ui_book(x, y, 0, right_w, h)` puts the right page at x (no spine); `ui_text_ink_centered` is an extra ui API.
