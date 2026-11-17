Set shell = CreateObject("WScript.Shell")
Set fs = CreateObject("Scripting.FileSystemObject")
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & fs.GetParentFolderName(WScript.ScriptFullName) & "\Warpath.MarketFeedWatcher.ps1""", 0, False
