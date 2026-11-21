Set shell = CreateObject("WScript.Shell")
Set fs = CreateObject("Scripting.FileSystemObject")
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & fs.GetParentFolderName(WScript.ScriptFullName) & "\Warpath.BackupTask.ps1""", 0, False
