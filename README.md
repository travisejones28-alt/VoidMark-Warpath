# VoidMark Warpath — Classic Era baseline

**Target for active development: WoW Classic Era, interface 11509.** Forever (interface 16001) adaptation is deferred until its quest dataset and map behavior can be checked. The same source tree and versioned SavedVariables architecture will be used; the addon is not a fully tested Forever build.

## Installation

Clone this repository into the Classic Era AddOns directory as `VoidMarkWarpath`, with `VoidMarkWarpath.toc` at the folder root. Reload the client and type `/warpath`. Do **not** overwrite the existing Forever installation to test this Era-specific build.

## Features available

- Standalone Warpath window, six-zone selector, persistent account observations and per-character settings.
- Two-zone preliminary Classic Era world-map pins for quest contacts in Redridge and Duskwood. Eight source-attributed contact references, not complete kill/collection objectives.
- Static cluster scores based only on nearby contact records; these **do not** claim actual or probable player sightings.
- World map layer commands `/warpath map`, `/warpath levels 18 30`, `/warpath toggle heat`, `/warpath toggle quests`; `/warpath toggle routes` saves a preference but corridor rendering remains unimplemented.
- Character settings and legacy observations preserved. Historical sightings are separate from quest-reference density.

## Data accuracy and limitations

The initial points are Classic 1.12-derived contact coordinate references; do not mistake them for fully validated Era objective coordinates. Expand future data by resolving quest/object/item/NPC associations from [QuestieDB](https://github.com/Questie/QuestieDB), [Questie](https://github.com/Questie/Questie) or a licensed compatible Classic Era dataset, preserving quest IDs, NPC/object IDs, objective type, level/faction, the dataset revision and provenance. A data version/source field is needed before migrating large datasets. Nothing in the overlay implies enemy visibility.

**Phase 2 is incomplete:** full Redridge/Duskwood objective locations, turn-in and chain coverage, quest density plus proximity weighting, verified in-client canvas behavior, UI toggles and travel corridor rendering remain. Do not call these points verified until they have been cross-checked against Era source data.

## Validation

`python tests/validate.py` is a Phase 1 structure check whose interface assertion must reflect Era interface 11509. `python tests/phase2.py` checks load order and source labels but is not in-game proof. Manual map pin placement, changing map zones, filters and SavedVariables still require actual Classic Era testing.

## Future Forever port

Restore Forever interface 16001 in a separately packaged build, confirm the Blizzard map canvas and quest coordinate semantics, then reconcile differences with a per-client override dataset rather than replacing Era records or resetting SavedVariables.

## Phase 2 UI and scoring update (0.2.3)
The window includes contact/hotspot layer toggles, level range readout and an Open World Map button. Static contact reference scores use per-character `weights.density` (default 15) and `weights.contacts` (default 7); those scores must not be interpreted as observed PvP activity. Full QuestieDB quest-objective import remains pending. QuestieDB has separate Era and Forever datasets and correction layers, so raw source records alone are not sufficient to claim fully validated coordinates.

## QuestieDB upload extraction — v0.2.4
Imported 39 quest-associated Classic Era objective spawn samples (19 Redridge, 20 Duskwood) from uploaded QuestieDB Vanilla 1.0.6 baked records, build `36ca1ca86f6c1838de479c7c7452eb0a57d5c135`. Cyan objective markers differ from gold quest contacts and purple contact clusters. The complete offline extraction contains 308 spawn positions across these 39 quests; it is provided separately as an addon data patch. Sampling limits in the committed source are deliberate; a full versioned import and correction-layer review remain necessary. Map client execution and Forever coordinates are unverified. No Questie dependency is required at runtime.

## 0.2.5 — Full extracted Era spawn-reference import
All **308** extracted source records (152 Redridge, 156 Duskwood) across **39** quests are now embedded in `Data/ClassicEraObjectives.lua` and load without Questie installed. QuestieDB source: uploaded Vanilla 1.0.6 baked metadata, build `36ca1ca86f6c1838de479c7c7452eb0a57d5c135`. Records include quest ID, linked NPC/object entity, Era map-normalized coordinates, and available level metadata. Hotspot cells score unique quest IDs and distinct spawn entities (deduplicating same entity+coordinate cross-quest), not raw record counts. Cyan map pins also deduplicate repeated spawn entities. These are quest-associated spawn candidates, not necessarily all actual objective targets; corrections, complete giver/chain structure, actual routes, and in-game validation remain needed. No live player data is represented.

## 0.2.6 minimap launcher and objective fix
Fixed Lua `tonumber(gsub())` multiple-value base error. Draggable purple minimap launcher: left click opens Warpath, right click opens world map, drag repositions; angle saved per character. The button is standalone and does not require Mini Map or other addons. In-game minimap behavior still needs verification.

## 0.2.8 — Accuracy and regression checks
Quest records with no supplied level no longer silently become level 60. Unknown levels remain unknown and are included in level-filtered views until verified; map tooltips explicitly state when level data is missing. The updated offline test checks all 308 packed coordinates, 39 quest associations, load order, and marker lifecycle indicators. Run `python tests/phase2.py`; follow with Classic Era in-game checks. This is not a claim that every QuestieDB association is a true quest objective.

## 0.2.9 — Quest-contact connection layer
The saved `/warpath toggle routes` option now draws two **quest-contact connections** in Duskwood (quest IDs 148 and 225) when the Era map's `CreateLine` API is available. These are straight-line visual relationships between sourced contacts, not verified roads, enemy movements or navigable patrol routes. They disappear when changing map zones or closing the map. More sourced quest travel corridors are needed before Phase 2 can be declared complete.

## 0.2.10 — Map line pooling and connection controls
Added a dashboard checkbox for quest-contact connections and reusable map line objects to avoid allocating more line textures on each map refresh. This reduces UI allocation churn when changing map zones and repeatedly opening the map. The route lines remain straight-line **quest associations**, not actual navigation routes. In-game verification is still needed.

## 0.2.11 — Minimap drag resilience
The minimap launcher now runs dragging on a separate driver frame, preserving its automatic size-change watcher. This is important with ElvUI's resizable square minimap. Per-character angle remains unchanged; no settings reset. In-game verification remains necessary.

## 0.2.12 — Coverage correction in progress
The original importer truncated every quest-associated entity's coordinates to the first three records, producing biased purple hotspot coverage. A separate analysis of all 1,062 Redridge QuestieDB spawn associations supports six notable questing areas. Orange Quest areas show approximate centers, nearby row counts and associated quests, derived from full-source analysis. They do **not** measure real traffic, enemy locations, quest progress, or verified objectives. These markers are an interim quality correction; the full objective import and scoring replacement remain Phase 2 work.

## v0.2.13 — Expanded Era hotspot foundation
Purple hotspots now use all 1,062 Redridge and 950 Duskwood quest-associated spawn references summarized in a 16x16 grid, rather than only the first three spawn points per entity. Cell score uses distinct quest and entity counts and spawn density; it is **not** enemy probability or measured player activity. The histogram is combined across levels, so the level filter does not apply to purple hotspots yet; cyan sample points can still filter by quest level. Purple layer is marked "all levels" to avoid claiming filtered coverage. Player-marked quest areas remain a separate overlay. Source still requires correction-layer reconciliation and Era in-game verification.

## 0.2.14 — Quest-level filtered comprehensive heatmap
The 2,012 expanded QuestieDB quest-associated spawn records are now grouped by **quest ID and 16x16 map cell**, retaining all 39 quest level associations. The purple heatmap recomputes on level-range changes rather than using all-levels-only zone totals. Counts are quest-associated references (the same world spawn can be associated with multiple quests) and should not be interpreted as distinct mobs or player activity. Older all-levels histogram remains available as legacy reference data but no longer drives heatmap calculation. Classic Era verification pending.
