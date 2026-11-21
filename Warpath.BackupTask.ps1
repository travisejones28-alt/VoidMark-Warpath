# Run by the hourly "VoidMark Warpath Backup" task (via Launch-Warpath-Backup.vbs). No window.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Warpath.Core.ps1')
try {
    . (Join-Path $PSScriptRoot 'Warpath.Backup.ps1')
    $result=Invoke-WtfScheduledBackup
    if($result -notin @('nothing new','WoW is running','turned off')){Write-WarpathLog ('Background backup: '+$result)}
} catch {Write-WarpathLog ('Background backup failed: '+$_)}
