# Changelog

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
