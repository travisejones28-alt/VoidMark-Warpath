# Release Alpha 1.0

Original quest project recovery: branch `archive/quest-warpath-0.2.15-20261028`, SHA `786019cdef510e506e1e78fac0cec89f86c135e5`. This branch was created remotely before obsolete files were removed. The repository name and URL are unchanged.

## Build

1. Check out the desired main commit.
2. Run `python tests/run.py` with Lua 5.1 or `lupa.lua51` available.
3. Run `python tools/package.py`.
4. Install `dist/Warpath-1.0.0-alpha.1.zip` in Classic Era's `Interface\AddOns`. Archive has one top-level `VoidMarkWarpath` folder.
5. Run the manual checklist in TESTING.md. Test Forever separately; do not mark it in-game verified based on source inspection.

The PowerShell source installer is included in the repository as `tools/Install-Era.ps1`; it has been statically reviewed but was not run on Windows. It replaces only the previous installed Warpath directory. Run PowerShell with the permission needed to write into Program Files. No other addons are modified.

## Publish on GitHub

After client acceptance, create a prerelease on the existing repository with tag `v1.0.0-alpha.1`, targeting the tested main commit, title **Warpath Alpha 1.0**. Attach the installation ZIP, not GitHub's automatic source ZIP (the source repository folder has a different name). Summarize manual targeting, watchlist, supported detection and combat queue behavior. Include exact tested client builds and any untested scenarios.

This implementation delivery does not claim an uploaded GitHub Release or completed in-game acceptance. A release should remain a prerelease while client acceptance is pending. GitHub Actions also builds the structured installation ZIP as a workflow artifact.

## Troubleshooting

- No macro: `/warpath status`; free a character macro slot, leave combat and click Arm. Copy Macro is the fallback.
- Wrong target after changing in combat: existing native macro retains its old player until combat ends; check COMBAT QUEUED. Copied macros never update automatically.
- No detection: check entry enabled, exact name/realm, hostility option and whether the game exposes target/mouseover/nameplate identity. Nameplate settings and client range limits apply. Forever can hide identity from addons.
- No spell: learned/localized spell name, range, resources, cooldown, living hostile selected target and line of sight are required. The addon cannot override these.
- Edited macro: rearm, then replace the old action-bar macro with Place Macro. Your edited macro is preserved.
- Old quest data: old SavedVariables may remain on disk but are unused. No quest functionality or Questie dependency remains on main.
