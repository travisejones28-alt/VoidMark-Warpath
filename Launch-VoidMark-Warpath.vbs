Set shell = CreateObject("WScript.Shell")
Set fs = CreateObject("Scripting.FileSystemObject")
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & fs.GetParentFolderName(WScript.ScriptFullName) & "\VoidMarkWarpath.ps1""", 0, False
