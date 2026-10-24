# VoidMark Warpath — Classic Era Phase 2

Version **0.2.15**, Interface **11509**. Standalone; no mandatory addons.
Redridge and Duskwood only. Existing later-zone buttons are disabled placeholders.

Warpath displays **static Alliance quest-activity estimates**, not player counts,
enemy encounter probabilities, or live movement. Account-wide saved sightings
remain separate and are never used to manufacture quest scores.

## Using it
- Left-click the draggable square-perimeter minimap launcher to open Warpath.
- Right-click it to toggle the world map.
- Set inclusive **suggested quest levels** in the window and click Apply (or Enter).
  `/warpath levels 15 20` and `/warpath levels 21 30` use the same validation.
  This is a quest-level filter, not an enemy player-level filter.
- Purple circles show low/medium/high relative intensity. Cyan dots show objective
  coverage cells; gold quest icons show clustered giver/turn-in contacts.
- Hover for quest names, IDs, minimum and suggested levels, prerequisite IDs,
  score components and limitations. Mouse-wheel longer tooltips to page through all entries.
- Connections are optional. Purple solid lines join source-backed quest endpoints;
  cyan dashed lines represent inferred prerequisite transitions. **Neither is a
  verified walkable road.** Up to 24 deduplicated connections are shown.

## What changed
The old 39-quest, 431-cell extraction is archived but no longer loaded.
The new reproducible Classic/Era import contains 108 Alliance-eligible quest
records, 2,487 deduplicated objective coordinate references and 179 contact
references. It applies relevant Era and Alliance corrections and uses explicit
quest objectives / objective-item sources instead of reverse incidental associations.

A 12x12 grid groups evidence without deleting singleton objectives. Each quest
contributes at most once per objective cell: 1 unit for direct objectives, 0.8
for item-source objectives. A prerequisite-linked successor sharing the cell
contributes half weight. Score is capped at 100:
`20 * objective units + 5 * min(contact quests,4) + 3 * min(matching nearby contacts,3)`.
Nearby means within 7% of normalized map coordinates. High >=60; medium >=30;
low <30. These are transparent heuristic weights, not calibrated traffic.
Raw spawn counts do not increase scores. Travel links do not add artificial
activity along a straight line.

## Validation and limits
See [DATA_AUDIT.md](DATA_AUDIT.md) for pinned sources, geographic evidence,
missing coverage and exact counts. Lua 5.1 tests use a WoW API mock; **no in-game
testing has occurred**. Test ElvUI drag/reload/resize, map zoom/reopen, tooltip paging,
layer controls, levels 15–20 and 21–30, and actual terrain readability in Classic Era.

Existing observations, schema 1, window position, minimap angle and layer settings
are retained. No SavedVariables reset is required. The former “Quest areas” setting
now controls source-derived cyan objective cells; the six hardcoded circles are retired.

## Development
Run `LUA=<Lua 5.1 executable> python tests/validate.py` (or set the LUA environment
variable in your shell). `lua tests/runtime.lua` runs the behavioral tests directly.
No external Python packages are required.

To reproduce source data, from the repository root run:
`node tools/download_source.mjs ../reference`, then
`lua tools/import_era.lua ../reference` and `lua tools/audit.lua`.
The source downloader verifies SHA-256 checksums. Import uses only pinned Classic
tables plus Era/Alliance corrections; it fails on unresolved corrections. Generated
data is checked in; these tools and reference downloads are not needed in WoW.

Source attribution: [QuestieDB](https://github.com/Questie/QuestieDB) and
[Questie](https://github.com/Questie/Questie). See
[upstream licensing notice](docs/QuestieDB-LICENSE.md).
Phase 3 and additional-zone coverage have not started.
