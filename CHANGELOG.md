# Changelog

## 0.2.15 — Audited Classic Era quest-activity model
- Replaced legacy spawn-count scoring and six hardcoded area markers with a reproducible corrected Classic/Era import: 108 quest records, 2,487 objective references and 179 contacts.
- Scores distinct objective presence, conditional chain overlap and matching contact proximity; keeps single-target objectives and ignores duplicate spawn density.
- Added compact circular intensity markers, objective dots, clustered contacts, paged evidence tooltips and explicitly schematic optional connections.
- Added inclusive quest-level fields in the window; slash commands and controls refresh the map immediately.
- Preserved schema 1 observations and settings; bounded model caching, reused render pools, improved launcher drag handling and square resize behavior.
- Added Lua 5.1 behavioral tests, repeatable source import/checksums, geographic validation and DATA_AUDIT.md. In-game acceptance testing remains required.
- Phase 3 and Forever adaptation have not begun.

## 0.2.14 — Full-data level-aware hotspots
- Added 431 per-quest grid records sourced from 2,012 QuestieDB quest-associated coordinates.
- Purple heatmap now responds to quest level range in Redridge and Duskwood.
- No SavedVariables schema change; Classic Era remains the sole implementation target.


## 0.2.13 — Expanded Era hotspot coverage
- Derived 16x16 quest-associated spawn-density histogram from all 2,012 extracted Redridge and Duskwood QuestieDB reference coordinates.
- Replaced truncated three-coordinate hotspot scoring with full-coverage grid scoring.
- Disclosed that histogram scores combine all quest levels; level filtering awaits quest-resolved full data.
- Left existing reference point layer, user-marked zone layer, and SavedVariables intact.


## 0.2.12 — Expanded Redridge questing coverage correction
- Confirmed initial QuestieDB extractor incorrectly retained only the first three coordinates for each quest-associated NPC/object.
- Analyzed all 1,062 Redridge source rows and independently located six frequently quest-associated areas that were invisible or underweighted.
- Added six source-backed orange area indicators, separate from purple sampled-grid hotspots and live player sightings.
- Added Quest areas toggle; full expanded-coordinate import and model overhaul still pending.


## 0.2.11 — Minimap drag lifecycle fix
- Separates drag-frame OnUpdate from the minimap button's persistent resize watcher.
- Prevents drag release from disabling future ElvUI minimap resize repositioning.
- Maintains Classic Era target and all SavedVariables.


## 0.2.10 — Map overlay resource management
- Reuse quest contact connection line textures after map switches instead of allocating new lines repeatedly.
- Added dashboard checkbox for the optional connection overlay.
- No SavedVariables schema change; Classic Era only.


## 0.2.9 — Quest-contact connection overlay
- Added optional straight-line quest-contact connections for two existing Duskwood quest associations.
- Rendered with guarded CreateLine API and cleaned up on map switches/hide.
- Kept patrol routing separate; no invented traversable paths or PvP observations.


## 0.2.8 — Level metadata fix and offline regression validation
- Fixed missing quest levels being fabricated as level 60 (and hidden by filters).
- Clearly identify missing level metadata in map tooltips.
- Replaced stale Phase 2 tests with a deterministic packed-data validation covering 308 coordinates and 39 quests.
- Preserved SavedVariables schema and Era-only target.


## 0.2.7 — Square minimap and UI spacing
- Minimap launcher now follows the rectangular minimap edge using live frame width/height; drag position persists.
- Corrected overlapping controls/status footer, and display computed objective hotspot count.
- Classic Era remains the active target; runtime validation required.


## 0.2.6 — Fix Lua objective loader; add minimap launcher
- Fixed Lua multiple-return tonumber(gsub) error preventing objectives loading.
- Added independent draggable minimap button with left-click UI and right-click World Map.
- Persisted button angle per character without resetting existing data.


## 0.2.5 — Complete extracted 308-point import
- Embedded 308 QuestieDB Classic Era quest-associated spawn-reference records for Redridge and Duskwood.
- Switched clustering from quest-contact references to objective-linked spawn records.
- Deduplicated overlapping coordinates and entity IDs for scoring and rendering.
- Preserved standalone operation, schema and prior SavedVariables.
- Still awaiting Classic Era live map verification and QuestieDB correction reconciliation.


## 0.2.4 — QuestieDB-derived Classic Era objectives (incremental)
- Added 39 distinct quest-associated objective spawn samples from the uploaded QuestieDB Vanilla build.
- Rendered cyan objective pins separately from contact and contact-cluster markers.
- Extracted 308 associated spawn coordinate records offline; full set available in separately downloadable data patch.
- Preserved SavedVariables, standalone operation, and map cleanup behavior.
- Phase 2 remains incomplete until complete objective records, corrections, route visualization and in-game verification are finished.


## 0.2.3 — Phase 2 Classic Era controls
- Added in-window controls for quest contact and hotspot map layers plus an Open World Map button.
- Added level-filter readout and SavedVariables-backed scoring weights with bounded defaults.
- Maintained Classic Era target and existing account data.
- A real QuestieDB corrections-aware objective import is still required for complete Phase 2 coverage.

## 0.2.2 — Phase 2 Era overlay hardening (still incomplete)
- Recycled map markers instead of leaking detached frames every zone change.
- Added map-ID and canvas-size observation to handle clients without an OnMapChanged callback.
- Hid markers when closing the map and refreshed markers after switches.
- Corrected labels: contact clusters are NOT quest objectives, enemy sightings or calibrated player-activity probabilities.
- Maintained the same SavedVariables schema; no data resets.
- Added static lifecycle regression assertions.
- Full QuestieDB objectives and travel corridors remain pending, as does actual client validation.

## 0.2.1 — Classic Era target
- Set Era interface 11509; Forever adaptation deferred.
## 0.2.0 — Early map preview
- Redridge/Duskwood contact references and preliminary map pins.
## 0.1.0 — Foundation
- Modular loader, storage and standalone UI.
