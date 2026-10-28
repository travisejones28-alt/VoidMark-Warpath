# Warpath — Alpha 1.0

Standalone World PvP watchlist and manual exact-name targeting. Dark charcoal window, violet accents, no dependencies. The repository remains **VoidMark-Warpath**; the installed addon folder is **VoidMarkWarpath**; the in-game title is **Warpath**.

**Status:** implemented and validated with Lua 5.1 mock-client tests. No WoW client was available for in-game testing. Classic Era is the initial target; Forever 1.60.1/interface 16001 is a separate compatibility path requiring client validation. Alpha is not a claim of completed in-game acceptance.

## Install (Classic Era first)

1. Close WoW or return to character selection.
2. Remove the old `VoidMarkWarpath` addon folder to avoid leaving obsolete quest files behind. Do not remove other VoidMark addons.
3. Extract `Warpath-1.0.0-alpha.1.zip` into:
   `C:\Program Files (x86)\World of Warcraft\_classic_era_\Interface\AddOns`
4. Verify `AddOns\VoidMarkWarpath\VoidMarkWarpath.toc` exists directly, with no extra nested folder.
5. Enable **Warpath** and log in. Use `/warpath` or the violet **W** minimap button.

The source checkout convention is `C:\WoW Forever Addons\VoidMark-Warpath`. This is a source repository, not the installed addon folder. From PowerShell, install a local checkout to Era using:

```powershell
Set-Location 'C:\WoW Forever Addons\VoidMark-Warpath'
.\tools\Install-Era.ps1
```

The installer validates a WoW Era destination, replaces only `VoidMarkWarpath`, and copies only the addon package files. Forever: use the same release folder under your actual Forever client's `Interface\AddOns`; its `_Camelot.toc` selects interface 16001. This installer deliberately targets Era only.

## Arm a player and bind the macro

1. Enter an exact character name and click **Add**, or select the enemy and click **+ Current Target**.
2. Click an enabled watchlist row to arm that player. The first player is selected automatically. Selection persists through reload.
3. Click **Place Macro** outside combat, then click an action-bar slot to drop the native macro there.
4. Bind that action-bar slot in WoW's normal keybinding settings. Press the key yourself for every attempt.
5. Optional: enable **Res Watch** while waiting after a kill. It keeps the same player armed and labels the workflow; it adds no scanning or automatic actions.

**Arm** retries native macro creation/update. The macro is character-specific, normally named `Warpath`. If that name is occupied, a free name such as `Warpath2` is chosen. Existing unrelated macros are preserved. Ownership requires both the saved macro name and exact last-written body; editing/deleting the managed macro breaks ownership. Arming again creates a separate macro rather than overwriting your edited macro. Place the new macro on your bar when this happens.

If character macro slots are full, free one and click Arm. **Copy Macro** opens a selected text preview for Ctrl+C and manual creation in `/macro`. Copies are static: replace them yourself after switching players. The UI's Armed state refers to its managed native macro, not manually copied text. Warpath does not run the macro from addon Lua or bind over an existing key.

### Target Only (default)

```text
#showtooltip
/targetexact Ganktastic-realmname
```

Player macro names are realm-qualified to avoid same-name players on other realms. A name entered without a realm means your current realm. Realm spaces, hyphens and apostrophes are normalized for identity matching. No substring matches. Type the exact character spelling, particularly for accented characters; Unicode case folding is not promised.

Target Only does not clear the previous target on failure and does not cast or start autoattack. Normal targeting distance, visibility and server rules apply. The client must support realm-qualified exact targeting; verify on your client using the checklist below.

### Optional Target + Spell

Settings accepts a localized spell name, such as `Shadow Word: Pain`, `Mind Blast` or `Psychic Scream`. Click Apply (or Enter). Click Target Only to switch back. Spell lookup is advisory; correct spelling, a learned spell and applicable ranks remain your responsibility.

```text
#showtooltip Mind Blast
/cleartarget
/targetexact Ganktastic-realmname
/stopmacro [noexists]
/cast [@target,harm,nodead] Mind Blast
```

A failed exact-target attempt may leave an old target selected. **Spell mode clears the prior target on every keypress**, then stops if nothing was acquired. Explicit `@target` prevents self-cast, focus or mouseover fallback. There is no supported arbitrary character-name equality macro conditional that would safely preserve any previous target here. Do not remove the clear/stop/target conditions. Input cannot inject extra macro lines or macro conditionals; bodies above 255 bytes are rejected.

The safety sequence is statically checked and covered by an independent macro-semantics model. Actual client macro execution still requires in-game validation. Spells remain subject to range, line of sight, visibility, cooldown, resources, stance, global cooldown and server restrictions. Self-centered spells such as Psychic Scream still require a living hostile selected target in this deliberately conservative mode.

### Combat changes

All native macro writes and pickups are blocked during combat. Desired selection/mode/removal changes are saved and applied after `PLAYER_REGEN_ENABLED`. The existing action-bar macro continues to use its **previously applied target and mode** until then. The collapsed and expanded window both show `COMBAT QUEUED` with that prior player's name. `/warpath status` reports the applied configuration. **Copy Macro** previews the requested configuration, which may differ from the live macro during combat or after a write error.

Removing, disabling or clearing an active entry also waits to disarm the native macro until combat ends. Stopping the addon cannot deactivate an existing native macro; remove it from your action bar yourself if disabling Warpath.

## Watchlist, interface and alerts

- Per-character saved watchlist, selected player, enable/disable controls and individual removal; clear/reset requires confirmation.
- Compact 350 × 418 window, five rows per page; draggable header, saved position, collapse to an 81-pixel strip, saved visibility.
- Minimap button: left-click toggle, right-click settings, drag around minimap.
- Target/mouseover/nameplate evidence only. Visible-unit reconciliation every 0.25 seconds checks those exposed tokens, never arbitrary names.
- Optional hostile-only filter (default on). Optional NPC exact-name tracking is off by default; add NPCs with `/warpath npc Exact NPC Name` after enabling it in Settings. Identically named NPCs cannot be distinguished by a name-only macro.
- Seen, Armed and Target Acquired statuses; visible dead status; observed dead-to-alive transitions only when the same GUID remains continuously observable. Reacquisition after a gap is not proof of resurrection.
- Sound, acquired-target sound, brief border pulse and optional two-second center alert. No continuous flashing. Each alert type has a per-player cooldown, with an additional shared sound cooldown. Continuous visibility never retriggers Seen; a two-second disappearance grace avoids flicker alerts. Chat reports confirmed encounters.
- Settings: cooldown 1–120 seconds (default 10); history 0–200 entries (default 50). **Press Enter** to save either numeric field. History prints timestamped evidence to chat.

No detection claim implies “Nearby,” “Resurrected,” spell range, line of sight or ability to cast. Target Acquired means the player is actually selected, even if selected by another means. It is not proof that Warpath's macro caused it. Hostile-only filters detection; native targeting is by name, with a separate hostile/living condition for optional casting.

An account-wide watchlist and arbitrary resizing are deferred. Character separation and a fixed compact layout are intentional Alpha defaults.

## Commands

| Command | Action |
| --- | --- |
| `/warpath` | Toggle window |
| `/warpath add PlayerName` | Add a local-realm player, or `PlayerName-Realm` |
| `/warpath remove PlayerName` | Remove an exact entry |
| `/warpath target PlayerName` | Arm an existing enabled entry |
| `/warpath list` | Print saved watchlist/status |
| `/warpath reset` | Confirm clearing watchlist and history |
| `/warpath settings` | Toggle settings |
| `/warpath macro` | Copy requested macro text |
| `/warpath status` | Report applied macro or error/queue |
| `/warpath history` | Print retained detections |
| `/warpath npc Exact NPC Name` | Add optional NPC entry |

## Architecture and persistence

`Core.lua` owns the addon namespace; `Compat.lua` centralizes client identity and safe API reads; `Database.lua` owns `WarpathCharDB`; `Targeting.lua` handles user intent; `Macros.lua` owns native macro generation/ownership/lockdown; `Detection.lua` uses exposed units; `Alerts.lua` throttles alerts/history; `UI.lua` and `Minimap.lua` render controls; `Config.lua` boots and routes events/commands.

SavedVariables: **`WarpathCharDB`**, per character, schema 1. Old `VoidMarkWarpathDB`/`VoidMarkWarpathCharDB` quest intelligence is not read or migrated. The old project and its licensing remain recoverable on [archive/quest-warpath-0.2.15-20261028](https://github.com/travisejones28-alt/VoidMark-Warpath/tree/archive/quest-warpath-0.2.15-20261028), commit `786019cdef510e506e1e78fac0cec89f86c135e5`.

## Validation and release

See [API audit](docs/API-AUDIT.md), [test results and client checklist](docs/TESTING.md), [release instructions](docs/RELEASE.md), and [license/reference notice](NOTICE.md).

```sh
python tests/run.py  # native Lua 5.1 or Python lupa.lua51
python tools/package.py
```

The package builder creates and verifies a single top-level `VoidMarkWarpath/` folder. No quest databases, old UI, legacy UnitScan files, tests or repository metadata are included in the installation ZIP.
