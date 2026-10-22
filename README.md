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
