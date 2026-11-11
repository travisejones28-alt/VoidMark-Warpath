# VoidMark Warpath

Windows addon installer and updater for WoW Forever and WoW Classic Era.
Requires **Windows PowerShell 5.1** and Windows Forms (included with Windows).

## Friends: three steps

1. Extract the entire ZIP into a normal folder outside WoW. Double-click **Launch-VoidMark-Warpath.vbs**.
2. Pick your game. Click **Browse** and choose that game's **Interface\AddOns** folder. Warpath remembers a different folder for each game.
3. Leave the addons you want checked and click the **big purple button**. When it says **DONE!**, start WoW. If WoW is open, type `/reload`; restart WoW if newly installed addons do not appear.

The updater checks GitHub automatically when it opens and when you switch games.
Use the small **Check for updates** link for another check. New addons and addons
needing an update start checked. Click anywhere on a row, or focus the list and
press Up/Down and Space, to change your choices. The big button installs checked
new addons and updates installed addons that need it, even if their boxes are
unchecked. It does not reinstall addons whose recorded hash is already current.

An empty list means the owner has not shared addons for this game. It does not
mean your computer is broken. Missing, invalid or empty catalogs share nothing.

## Owner notes

Click **Owner** in the footer and enter your password. Owner access lasts only
until you lock it or close the updater. The gold badge identifies owner mode.
Non-public addons carry an **OWNER** tag. **Lock** immediately hides them again.

Click **Edit public catalog** to select what friends see. **Save catalog + make
friends ZIP** writes `public-catalog.json` and creates
`VoidMarkWarpath-Friends-READY.zip` beside the updater. Send this ZIP to friends.
The export includes all shared runtime files and assets, and excludes the owner
editor, its launcher, and its implementation file. It never exports settings,
logs, install records, or backups. An empty selection is allowed and fail-closed.

`Launch-Owner-Editor.vbs` opens the same editor directly and always asks for the
password. Opening the editor from an already unlocked updater uses that session.
Only the supplied lowercase UTF-8 SHA-256 digest is in the code. The password is
never written to a file, settings or logs. Three failed attempts cause a 30-second
lockout in that process; cancelling and reopening the dialog in the same process
does not reset it. Closing/restarting the app resets this in-memory gate.

This password is a convenience gate for a local script, not a security boundary
against someone who can edit its source. Public GitHub repos remain public.
Hiding a repo in the catalog does not revoke GitHub access. Catalog changes are
local to each extracted package: commit them to GitHub and send a newly exported
friends ZIP when your shared list changes. No credentials are included or used
to access private repositories.

The original owner/repo list is unchanged: `travisejones28-alt`, with
VoidMark-Forever, VoidMark-Market, VoidMark-Nexus, VoidMark-Mini-Map and
VoidMark-Debug for Forever; VoidMark, VoidMark-Clapback and VoidLink for Classic
Era. Journey and the old Warpath WoW addon remain excluded. This repo now hosts
the updater itself; the old addon is recoverable from Git history.

## Artwork and file layout

The banner **assets\voidmark_forever_header_2048x512.png** is included. If it is
missing, the app uses a text header. On first run with the PNG, System.Drawing builds
the aspect-preserved fading banner, a softened right-side flame background with
55% RGB brightness and a dark vignette, and `assets\voidmark.ico` with
16/32/48/256 PNG-backed images. The background is built once per window, not on
each paint. Remove `voidmark.ico` if you replace the banner and want a new icon.
Use a writable extracted folder so first-run icon generation can succeed.

| File | Purpose |
| --- | --- |
| VoidMarkWarpath.ps1 | Main updater, remembered folders, UI events and worker polling |
| Warpath.Core.ps1 | Original repo list, checks, downloads, safe extraction and installs |
| Warpath.Theme.ps1 | WinForms initialization and themed messages |
| Warpath.UI.cs | Custom WinForms controls, artwork generation, password dialog |
| Owner-Catalog-Editor.ps1 | Password-gated direct owner entry point |
| Warpath.Editor.ps1 | Public-catalog editor and friends ZIP export |
| Launch-VoidMark-Warpath.vbs | Updater launcher with hidden PowerShell window |
| Launch-Owner-Editor.vbs | Editor launcher with hidden PowerShell window |
| public-catalog.json | Exact list of approved game/repo pairs; initially `[]` |
| assets/README.md | Where to put the original art |
| assets/voidmark_forever_header_2048x512.png | Your original PNG; add this file |
| assets/voidmark.ico | Generated on first run with art; no manual creation needed |
| README.md | These instructions |
| .gitignore | Excludes logs and the exported friends ZIP |

All code files are complete. Keep the additional shared files beside the two
entry scripts; do not copy just one `.ps1`. PowerShell and C# source use UTF-8
with BOM so Windows PowerShell 5.1 reads the symbols correctly.

## Addon folder names

Each addon installs into the folder WoW expects, matching its `.toc` name:
VoidMarkForever, VoidMarkMarket, VoidMarkNexus, VoidMarkMiniMap, VoidMarkDebug,
VoidMark, VoidMarkClapback (taken from the repo's `VoidMarkClapback` subfolder)
and VoidLink. If one of these is a junction/symlink (a linked dev folder), the row
shows **Linked (dev)** and Warpath skips it. Folders left by the earlier build
under repo names (e.g. `VoidMark-Forever`) are moved to a backup on the next install.

## Storage and safeguards

Settings: `%APPDATA%\VoidMarkWarpath\settings.json` (`paths` keys remain
`WoW Forever` and `WoW Classic Era`; existing remembered folders are preserved).
The last game is also remembered. On a new setup, an existing default WoW path
under Program Files (x86) or Program Files is filled in. Otherwise choose Browse.
The green folder check means the path ends in `Interface\AddOns`; it is a naming
check, not a guarantee that you selected the right game. A different test folder
gets an amber warning and remains usable.

Each install records the GitHub main commit in
`<chosen folder>\.VoidMarkWarpath\<repo>.json`, retaining `sha`, `repo`, and
`installedAt`. Downloads still use `archive/refs/heads/main.zip`. The main hash is
checked before and after download; if it changes, installation stops for a retry.
The window shows downloaded MB and average MB/s. With no Content-Length from
GitHub, the percentage is approximate until extraction completes.

Before replacement, old addon folders move to
`<chosen folder>\.VoidMarkWarpath\backup-<repo>-<timestamp>-<unique id>`.
Existing backups remain in place. Failed final installation/record writes attempt
to restore the previous folder. Stop WoW before manually restoring a backup:
move the current addon folder aside, then copy the wanted backup to the addon
folder named after the addon's .toc
(e.g. `VoidMarkForever`, not `VoidMark-Forever`). Recheck afterward because the backup may
be older than the recorded hash.

Warpath refuses junctions/symlinks in destination ancestry, metadata paths and
addon trees. It refuses protected WTF/SavedVariables paths and archive entries,
and never installs into or backs up those data folders. Archives must contain
one top-level folder and at least one root `.toc` file. ZIP traversal and symlink
entries are refused. WoW being open produces a warning, not a block.

Technical error details go to `%APPDATA%\VoidMarkWarpath\warpath.log`.
On-screen errors use plain language. GitHub/network/file work runs on a separate
PowerShell runspace so the progress display and window keep responding. Wait
for work to finish before closing the updater. A failed download does not modify
the old addon. Administrative access is not requested automatically.

## Test in a throwaway folder first

1. Extract this package somewhere outside the live AddOns folder, such as
   `Documents\VoidMark Warpath Test App`. Add the original PNG under `assets`.
2. Make two disposable folders, such as
   `Documents\Warpath-Test\Forever\Interface\AddOns` and
   `Documents\Warpath-Test\ClassicEra\Interface\AddOns`. Do not use live game
   folders for this test.
3. Launch the updater. Pick Forever, browse to its **test** AddOns folder, then
   pick Classic Era and browse to its **test** AddOns folder. Switch back and
   forth and restart the updater to confirm both folder choices persist.
4. The supplied catalog is empty. Confirm no friend addons appear. Click Owner,
   enter a wrong password three times, and verify the countdown. Cancel and
   reopen Owner to confirm the same-session lockout remains. After 30 seconds,
   use the correct password and confirm the gold badge and private addon tags.
5. In the editor, approve one addon for each game. Save and inspect the friends
   ZIP. Extract it to a separate folder and confirm only approved addons appear
   before unlocking. An empty catalog must show no addons. The direct owner
   launcher must request the password too.
6. In the owner/test copy, install one addon using the big button. Confirm that
   its folder and `.VoidMarkWarpath\<repo>.json` exist inside the **test** folder.
   Check again: it should be current. If other uninstalled choices remain, the
   whole app will not say "all set" until all displayed addons are installed.
7. To simulate an outdated install safely, close Warpath and replace only the
   `sha` value in that **test** record with 40 zeroes. Reopen and check: the row
   should say Update ready and start checked. Update it; verify the old test
   addon now exists in a `backup-*` directory and the new record has a real hash.
8. Try a folder name that does not end in Interface\AddOns: expect amber text,
   not a block. Try a path inside a disposable folder called WTF: it must refuse.
   Disconnect the internet and check updates: expect a friendly error and no
   live game file changes. Reconnect and check again.
9. Once satisfied, browse to the real AddOns folder **for each game**. The test
   paths stay remembered until you deliberately replace them. Never point the
   updater at a developer junction. Pick a regular physical folder instead.

## Commit and push with GitHub Desktop

1. Open GitHub Desktop and choose your **VoidMark-Warpath** repository. Click
   **Fetch origin**, then **Pull origin** if offered. Use **Repository → Show in
   Explorer** to locate its working folder.
2. Copy every file from this extracted package into that repository folder,
   preserving the folder layout and replacing the old scripts. Keep its `.git`
   directory. Add your original banner to `assets`; include the generated icon
   if desired. Do not copy your throwaway addon directories into the repo.
3. In Desktop's **Changes** tab, review the full file list and diffs. Confirm
   the new shared runtime files and original banner are included. Confirm logs,
   friends ZIP, settings, test addon records and backups are not staged. The
   supplied `.gitignore` excludes `*.log` and `VoidMarkWarpath-Friends-READY.zip`.
4. Enter **Redesign Warpath updater with single install button and owner mode**
   in Summary. Click **Commit to main**, then **Push origin**. If you prefer a
   review branch, choose **Branch → New branch** before committing and publish
   that branch instead.
5. Open the repo on GitHub and verify the files. Export a fresh friends ZIP from
   the owner editor after your final catalog changes; distribute that ZIP.


