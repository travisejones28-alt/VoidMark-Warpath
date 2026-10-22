# VoidMark Warpath — Phase 1

Standalone WoW Classic Forever Horde PvP intelligence foundation. Uses interface **16001** as verified in the current VoidMark Nexus and VoidMark Mini Map Forever manifests. No libraries or other addons required.

## Installation
Extract the `VoidMarkWarpath` folder directly into `_forever_/Interface/AddOns/`. The TOC must be `VoidMarkWarpath/VoidMarkWarpath.toc`. Alternatively use the GitHub source directory as the addon folder. Reload the client and type `/warpath`.

Commands: `/warpath`, `/vmwarpath`, `/warpath help`, `/warpath status`, `/warpath zone duskwood`.

Six initial zone metadata entries, account-wide validated observation storage, per-character zone/window state, schema migration and future-data read-only guard, modular event loader, a themed draggable UI, guarded optional integration checks, and empty typed collections for future curated quest/hotspot/route data.

**Accuracy:** No quest objectives, hotspots, patrol routes, player locations, or scores are populated in Phase 1. Saved sightings require explicit observed/manual coordinates and times. There is no /who inference or claimed live tracking. Optional addons are not required or automatically interrogated.

**Validation:** Run `python tests/validate.py` from the repository root. This checks manifest ordering and files, data definitions, and prohibited APIs. Manual in-client tests: reload, both slash aliases, all selectors, drag and logout/login persistence, disabling optional addons, and migration with old SavedVariables. In-game execution was not available during development.

**Compatibility:** Interface 16001 is grounded in other Forever addon repositories; the server/client must be checked in-game for API behavior. Only standard frame APIs are called; no map or tracking APIs are assumed. No installed version of the client was available for live testing.

## Future schema
`WP.models` documents the contracts for objectives, hotspots, sightings, routes and zone metadata. Version 1 saved data is never reset during future migrations. New migrations must be additive and preserve unknown properties.

## Phase 2 early preview (0.2.0)

Map reference markers for Redridge Mountains (2 quest contacts) and Duskwood (6 quest contacts), sourced from Classic 1.12 quest records at theforeverera.com. They have NOT been verified against the Forever map or Forever quest changes. Purple clusters show a static quest-contact overlap score, not enemy probability. Gold markers show quest contact locations, not quest kill/collection areas. Clickable tooltips display source quest IDs, reference coordinates, confidence and limitations.

Commands: `/warpath map`, `/warpath levels 18 30`, `/warpath toggle heat`, `/warpath toggle quests`, `/warpath toggle routes` (routes not rendered yet). Changing displayed Blizzard map zones should clear previous pins, subject to in-client verification.

**Incomplete Phase 2 requirements:** complete objective and quest-chain imports, verified Forever coordinate conversion, actual quest density scoring, hub proximity, travel corridors and controls in the UI remain unimplemented. Actual world-map anchoring, event behavior, toggling and UI positions require live testing. No unsupported location claims.
