# Phase 2 data and acceptance audit — 0.2.15

## Sources and scope
QuestieDB commit `cb187dffa957157d3c93a4696000b62ea4539dd9`:
`data/Classic/classic{Quest,Npc,Object,Item}DB.lua`, the four corresponding
`src/corrections/Era` files, and zone/item/quest enums.
Exact file checksums are in [tools/source.json](tools/source.json).
This is the Classic base with Era corrections, not Forever, SoD, or expansion data.

Questie blacklist inspected at `ed1f4053f343ec574e2da140e6bf7a4a13bc465a`.
The imported quest IDs' blacklist entries are “removed with Cata” conditions,
which do not exclude them on Era. This is a pinned availability audit, not a claim
about observed player access or a complete emulator of Questie's live logic.

The importer selects zoneOrSort 44 and 10; filters race masks for Alliance or
neutral eligibility; preserves names, minimum/suggested/max levels, class/race
restrictions, prerequisite alternatives/groups, exclusivity, skill and reputation.
It imports actual quest objectives, objective-item NPC/object drops (including
nested item sources), kill-credit and explicit event coordinates, plus startedBy
and finishedBy contacts. It never treats an entity's arbitrary relatedQuests as
an objective. Coordinates must belong to the actual target zone and be in 0–100.
Exact duplicates are removed by quest, zone, role, entity and coordinate.

Correction extraction handles the pinned files' top-level row format, base then
Alliance overrides, including explicit nil deletions. Unsupported selected
expressions or absent entities fail generation. 49 referenced rows have corrections:
21 quests, 16 NPCs, 2 objects and 10 items. No unresolved corrections remained.
This scoped importer is not a general-purpose replacement for QuestieDB.

## Counts
| Measure | Redridge | Duskwood | Total |
|---|---:|---:|---:|
| Legacy coordinate references | 1,062 | 950 | 2,012 |
| Legacy quest-cell records | 186 | 245 | 431 |
| Legacy quest associations | 19 | 20 | 39 |
| New Alliance-eligible quest metadata | 36 | 72 | 108 |
| New objective coordinate references | 1,213 | 1,274 | 2,487 |
| Giver coordinate references | 30 | 60 | 90 |
| Turn-in coordinate references | 30 | 59 | 89 |
| All-level activity cells (12x12) | 78 | 73 | 151 |
| Cells at quest levels 15–20 | 56 | 39 | 95 |
| Cells at quest levels 21–30 | 45 | 72 | 117 |

The legacy totals were independently decoded from the checked-in packed data.
That verifies the old file's counts, not the full provenance of the unavailable
original uploaded 1.0.6 baked build. All 39 old quest names and level fields match
the new corrected metadata. New objective references are quest-associated
coordinates, **not distinct mobs**; one world spawn may serve several quests.

## Geographic evidence
Tests below count matching objective references in broad validation rectangles.
The rectangles live only in tests and never alter scores or generate map pins.
Other applicable quests also contribute.

| Validation area | Supported example | Matching references |
|---|---|---:|
| Northern Blackrock camps/mountain approaches | Blackrock Menace #20 | 65 |
| Gnolls northwest of Lakeshire | A Baying of Gnolls #124 | 39 |
| Northern/northeastern approaches | The Everstill Bridge #89 | 26 |
| Tower of Ilgalar | Morganth #249 | 1 |
| Stonewatch Keep | Tharil'zun #19 | 1 |
| Southern lake shore | Selling Fish #127 | 80 |
| Raven Hill cemetery | The Night Watch #58 | 22 |
| Rotting Orchard/worgen area | Worgen in the Woods #173 | 13 |
| Southern worgen area | Worgen in the Woods #222 | 13 |
| Ogre area | Look To The Stars #181 | 3 |

Darkshire passes a separate giver/turn-in coverage check. Quest chains include
source prerequisites such as the Night Watch steps; links are conditional,
schematic transitions between supported local endpoints. These findings support
quest activity near the named places, **not every road or every part of a region**.
A single named target is retained even when its cell has no other spawn.
The annotated screenshots were not located through Library search; direct visual
comparison against those exact annotations remains an acceptance task.

## Known coverage limits
- 97 of 108 quest metadata records have local spatial evidence. IDs
  70, 72, 74, 75, 178, 270, 321, 322, 324, 337 and 526 have no imported local
  points; no coordinates or hotspots are fabricated for them.
- ZoneOrSort selection omits quests categorized under other zones, classes,
  professions or events even if they can touch these zones. Cross-zone endpoints
  are intentionally absent from the two-zone overlay.
- Vendor purchases, fishing/crafting sources, source-item-only relationships and
  runtime special-objective behavior are not fully spatially expanded. Items may
  have alternative acquisition sources. Item-based evidence is downweighted.
- Theocritus' Retrieval #178 and An Old History Book #337 have conditional item starts.
  Prerequisite completion, exclusivity, class/race, profession and reputation state
  of enemy players are unknown. No claim of current availability is made.
- Suggested level is filtered inclusively; unknown levels are excluded. “21–30”
  does not mean players 21–30 cannot do lower-level quests.
- Source spawn precision is not ground-truth player traffic. Grid centers are
  approximate coverage locations, not navigable waypoints.
- Connections show nearest representative endpoints and at most 24 unique links,
  not an exhaustive route network. Straight lines can cross obstacles.

## Validation status and remaining Phase 2
PASS: Lua 5.1 syntax for all repository Lua; manifest ordering; standalone load;
historical packed-count audit; 108 metadata records; deduplicated coordinate and
quest references; level ranges 1–60, 15–20, 21–30, 31–40 and 60; duplicate-invariant
scores; singleton retention via geography checks; bounded caching; ten geographic
objective checks plus Darkshire contacts; mock UI creation and controls;
map refresh/cleanup/hide/reopen/zone/resize; frame pool reuse; square minimap
positioning and resize; drag-click suppression; preservation of existing sightings.

NOT RUN: actual Classic Era/ElvUI client rendering, combat interaction, other-addon
integration, exact screenshot comparison and walkable-route verification.
The code is ready for **Phase 2 user acceptance testing**, not declared in-game
verified. Remaining Phase 2 work is that acceptance pass and any resulting fixes.
The coverage limitations above remain explicit; complete quest coverage is not claimed.
No Phase 3, Hillsbrad/Wetlands data or Forever adaptation was added.
