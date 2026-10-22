# Changelog

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
