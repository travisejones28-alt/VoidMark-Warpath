# Validation — Alpha 1.0

## Performed successfully

`python tests/run.py` using `lupa.lua51` / Lua 5.1: **82 assertions passed**, plus Python static TOC/security/structure checks. The harness loads every shipping Lua module, boots the real addon event dispatcher and constructs the UI using mocked WoW frames/APIs. It is not an emulator of Blizzard's secure execution engine.

Covered: manual add, duplicates/case/realm normalization, invalid names and macro injection; watchlist and selected-target persistence using the same SavedVariables table through reinitialization; restore of the last-owned native macro identity; switching armed target; exact default and spell macro text; conservative 255-byte limit; preserved user-edited macros; native macro name allocation/slot exhaustion; synchronous UPDATE_MACROS ownership callbacks; combat queuing, blocked pickups, removal/disarm after combat and prior-name warning; exact-name and realm matching; friendly/disabled filtering; mouseover/target/nameplate event detection; continuous visibility deduplication; cooldown after disappearance; dead display and continuous same-GUID dead-to-alive evidence; reacquisition not called resurrection; NPC opt-in; bounded/disabled history; restricted and secret unit reads; settings/copy dialogs; pulse/center expiry; collapsed/hidden state; reset confirmation; and distinct Era/Forever interface identity, namespaced macro limits and unrelated unit-event filtering.

The independent small macro interpreter verifies the **intended ordering and guard semantics** for failed acquisition with a prior hostile target, successful acquisition, dead and friendly targets. It does not verify Blizzard's runtime interpretation. SavedVariables testing reinitializes the table; actual disk writes and client reload are manual tests.

Static checks verify both TOCs, in-game title, SavedVariables declaration, exact module load order and files, removal of the quest data directory, and absence of insecure targeting/casting, secure attributes, direct keybinding mutation or the legacy forbidden-error scanner in shipping code. `tools/package.py` verifies all ZIP members, TOC presence and exact source bytes. CI repeats runtime/static checks on Lua 5.1 and packages an artifact.

## In-game acceptance: NOT RUN

No game client, account session, PvP opponent or actual WoW UI was available. No claim of in-game load success, taint freedom or addon coexistence is made. These remain release acceptance requirements, on **Era first**, then separately on **Forever 16001**.

| Test | Procedure / pass criterion |
| --- | --- |
| Clean load | Disable other addons. Enable Lua errors with `/console scriptErrors 1`, log in, toggle Warpath. No errors; correct title and no quest UI |
| Manual player / current target | Add an exact hostile player by text and by + Current Target. Duplicate rejected; invalid input explains why |
| Save/reload | Arm second entry, move/collapse/hide window, reposition minimap button, change settings, `/reload`. Verify all persisted and macro agrees |
| Bindable exact targeting | Place Macro on normal action bar; bind the slot. Verify local and explicit foreign realm names and accented names. Similar prefixes/same name on another realm must not be acquired |
| Failure safety | In Target + Spell with an absent named player, select a different hostile enemy, press the macro. Prior target clears; no spell/attack from macro hits that enemy. Repeat with auto self-cast on/off and focus/mouseover present |
| Spell success | Use a learned localized spell in range and line of sight; one hardware press targets and attempts that spell. Verify dead/friendly targets do not get cast on; normal cooldown/range failures remain normal game errors |
| Combat queue | Enter combat; change selection/mode, disable/remove active player, and try reset. Verify no macro edits or pickup; warning identifies prior macro player, including after removal. End combat and verify last requested state applies |
| Reload during combat | With existing managed macro, reload while fighting. Warning must preserve saved applied identity; update only after combat ends |
| Detection | Expose hostile tracked player through target, mouseover and enemy nameplate separately. Verify no similarly named/foreign realm/friendly false matches |
| Anti-spam | Keep nameplate/target visible longer than cooldown. One Seen/acquired edge alert, no repeated sound. Disappear/reappear after cooldown; verify new encounter. Toggle settings intentionally starts a new observation session |
| Dead/alive | Observe same tracked GUID dead and then alive without an observation gap. Alive message only on that transition. Disappear and reacquire alive: no resurrection claim |
| Res Watch | Arm enemy after killing them, enable Res Watch, repeatedly manually press bound macro while waiting. Selection retained; no automation; actual successful targeting confirmed by target token |
| Forever restrictions | Test world PvP and instanced restrictions separately. Secret/restricted name or GUID silently skipped; native macro remains a manual attempt. No identity bypass |
| UI | Header drag, 5-row pagination, 81-pixel collapse, settings, Ctrl+C macro copy, minimap movement, sound options and two-second center alert. Check screen resolutions, UI scale and long names |
| Macro ownership | Fill character macro slots; confirm useful error/copy fallback. Pre-create a different Warpath macro; ensure not overwritten. Edit managed macro manually; rearm creates a new one; replace old action-bar icon |
| Taint/coexistence | Repeat clean and with common UI/action-bar/nameplate addons. Enable `/console taintLog 1`; exercise all paths, inspect Logs/taint.log and Lua errors. Warpath must not cause forbidden-action spam. Restore logging preference afterward |

Spell failures can produce ordinary Blizzard range/cooldown errors when you press a native macro. Warpath does not suppress the game's errors. These are distinct from forbidden addon actions, which Warpath must never intentionally generate.
