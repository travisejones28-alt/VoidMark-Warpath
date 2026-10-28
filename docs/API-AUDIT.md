# API audit — 2026-10-28

## Evidence and scope

The attached `unitscan-v1.2.9.zip` was inventoried in full: `unitscan.lua` (8,729 bytes), TOC, README, CHANGES, three OGG files and three BLP textures. All text was read. The binary asset names, formats, sizes and intended roles were inspected; none was reused, decoded into replacement assets or shipped. There is no license grant in this archive. Author: Simon Hirsig/shirsig; changelog identifies tag/commit `52e6a9ea1da48ffef95f8c8b8d31472586634da1`, July 9, 2025. Warpath is an independent implementation using no UnitScan source or bundled assets.

Blizzard's extracted client UI source was independently inspected via the [Gethe mirror](https://github.com/Gethe/wow-ui-source). This is client source evidence, not an in-game test and not an implementation of the proprietary C targeting engine. Versions retrieved: Classic Era `1.15.9.70576`; Forever `1.60.1.70532`. Source branches can move; the inspected file Git blob IDs below identify the exact text reviewed.

| Source | Inspected blob / finding |
| --- | --- |
| [Era SecureTemplates.lua](https://github.com/Gethe/wow-ui-source/blob/classic_era/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua) | `31ea34c7dc3995bac10adcd2ce57b02f06db13e2`: native macro action and secure target action; both named macro and macrotext paths exist in this snapshot |
| [Era SlashCommands.lua](https://github.com/Gethe/wow-ui-source/blob/classic_era/Interface/AddOns/Blizzard_ChatFrameBase/Shared/SlashCommands.lua) | `a894894b48ffc64cfa5cdf0105c1604545fffad5`: TARGET_EXACT uses SecureCmdOptionParse and TargetUnit(target, true); CLEARTARGET calls ClearTarget; STOPMACRO calls StopMacro conditionally |
| [Era UnitDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/classic_era/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua) | `cf3944af3635324125c3aaa3c8845b0a069e1237`: PLAYER_TARGET_CHANGED is a supported synchronous event |
| [Forever SecureTemplates.lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua) | `66f203e31a819f383ea3c6920be8d4f6556848eb`: native macro and macrotext dispatch present here too; Warpath uses native macros rather than depending on attribute execution |
| [Forever SlashCommands.lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ChatFrameBase/Shared/SlashCommands.lua) | `0799acd4509c6b2b701a55afb4efcc76438f73eb`: secure command/category filtering; CAST parses an explicit target before CastSpellByName; actions remain in Blizzard's secure command path |
| [Forever MacroUI.lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_MacroUI/Blizzard_MacroUI.lua) | `71ab97a8de443e22085a10866a8c2dbeadf23b82`: native macro info/edit/pickup globals remain; limits use Constants.MacroConsts, which Warpath prefers over legacy constants |
| [Forever UnitDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua) | `b0a71557cf7f4bf758ccc9194b04c146d0df91c5`: UnitGUID has SecretWhenUnitIdentityRestricted; UnitName has SecretWhenUnitNameIdentityRestricted; UnitCanAttack, UnitExists and UnitIsDeadOrGhost declarations inspected |

## Legacy framework findings

The old scanner rotates saved names through `TargetUnit(name, true)` every frame. It sets a local flag in `ADDON_ACTION_FORBIDDEN` and assumes the flag means a unit is present. It temporarily unregisters UIParent's error event, then restores it. This is an error side channel, not a supported detection result. Warpath has no equivalent call, event subscription, UIParent event manipulation or error suppression.

The original READMЕ refers to Vanilla's TargetByName and says targets are removed on detection. The attached Classic Lua actually calls TargetUnit, retains the saved entry, and uses a found latch that resets when the error flag is absent. The README is stale. Source behavior takes precedence over that description.

The old secure alert button waits until out of combat to assign `macrotext`, while other visual/sound work runs from frame updates. It uses a fixed global frame, one account-wide saved target set, uppercase name-only matching, no realm identity, three animation update frames, copied alert assets and automatic raid-marker behavior on target change. Those components are all replaced. Warpath never changes raid markers, Blizzard event registration or unrelated addon frames.

## Recoverability

| Capability | Result |
| --- | --- |
| Manually target a named player with a key | Recovered via native `/targetexact` macro; normal client restrictions apply; actual realm-qualified acquisition remains a client test |
| Optional spell on same hardware press | Implemented with clear → exact target → stop if absent → explicit living hostile `@target` cast; client behavior must be verified |
| Add/save/disable/remove/arm names | Reimplemented per character with validation and exact realm-aware matching |
| Alert when target/mouseover/nameplate exposes identity | Implemented; no unit token means no observation |
| Identify current tracked target | Implemented via actual target token and GUID; does not attribute causality to the macro |
| Observe dead → alive | Implemented only across continuous observations of the same GUID; not inferred across gaps |
| Hidden-unit detection through protected-call errors | Not recovered. Forbidden-action errors do not establish unit presence and cannot be a reliable API contract |
| Original claimed scan radius/reliability | Cannot reproduce or promise; event/nameplate and manual targeting ranges differ and remain client-controlled |
| Background arbitrary-name targeting/casting | Restricted. Requires Blizzard's secure execution and hardware input; no addon timer can legally perform it |
| Automatic resurrection detection outside visible unit data | Unavailable; disappearance/reappearance is insufficient evidence |
| Secure configuration changes during combat | Deferred; existing macro retains prior configuration until combat ends |
| Error suppression / automatic raid markers / copied assets | Deliberately removed |

The old protected-call inference is unusable as a supported method. This audit does **not** claim to experimentally reproduce the historical patch regression or name a definitive engine patch: the C behavior is not present in the extracted UI source and no live client was available. In particular, “TargetUnit was completely removed” would be inaccurate for the inspected secure FrameXML, which still calls it inside Blizzard's secure path. The capability that is unavailable is using insecure protected-call failures as reliable presence evidence. We will not probe that side channel.

It is also inaccurate to categorically claim all old macrotext secure buttons no longer work on every client: both inspected snapshots contain macrotext branches. API availability and execution restrictions can still differ; native action-bar macros avoid that dependency. No “permanently restricted” statement can predict future Blizzard policy, but the unsupported capabilities above are not offered in this version.

## Forever compatibility

Interface 16001 is detected directly, independently of WOW_PROJECT_ID. `_Camelot.toc` carries the separate Forever interface declaration. Compatibility reads use pcall and reject secret values before comparison, concatenation, table lookup or branching. Exposed name, GUID and player identity are required; hostile-only detection also requires readable positive hostility evidence. Restricted identity produces no alert, no inferred target status and no history record. Dead state is allowed to be unknown and never then generates an alive-transition claim.

No combat-log alias, private namespace, hidden token enumeration or secret-value bypass is used. Only target, mouseover and public nameplate tokens are read. Spell lookup prefers C_Spell and falls back to the Era global. Unsupported event registration is guarded. The manual native macro preview is the fallback if macro management fails; it cannot bypass server targeting or secret-unit restrictions.

Forever is source-reviewed and mock-tested, **not certified functional in the beta client**. Classic Era also needs the acceptance run. Native macro secure execution, targeting reach, realm syntax and visual appearance are controlled by the client and remain unverified here.
