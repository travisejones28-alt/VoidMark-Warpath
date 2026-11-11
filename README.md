# VoidMark Warpath — Addon Updater

This repository now hosts **VoidMark Warpath**, the Windows updater/installer for VoidMark addons on **WoW Forever** and **WoW Classic Era**. The old Warpath WoW addon has been removed from the current branch; it remains recoverable from Git history.

## Running

Extract the files into a folder outside the WoW AddOns directories. Double-click `Launch-VoidMark-Warpath.vbs`. Use the dropdown to select Forever or Classic Era, choose a custom installation folder, check the addons you want, and click Install Selected or Update Installed.

**Owner:** Open `Launch-Owner-Editor.vbs` to approve exactly which public addons friends can see. Save the approved list, then distribute the app and `public-catalog.json` to your friends. **Never distribute the owner editor.** The catalog starts empty (fail-closed), and old public repo visibility is not revoked by hiding it from the app. Catalog changes are not automatically published.

The app tracks installed GitHub commit hashes, checks for updates, provides a download progress bar in the GUI, remembers separate folders per game, and backs up old addon folders. The program does not edit WTF/SavedVariables and refuses junctions or symlinks. Requires Windows PowerShell 5.1+. Test in a separate folder before modifying live WoW files.

**Note:** The old `VoidMark-Warpath` WoW addon is intentionally **not** available through this updater because this repository is now the updater itself.
