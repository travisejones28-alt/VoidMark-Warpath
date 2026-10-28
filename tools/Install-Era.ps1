[CmdletBinding()]
param([string]$AddOnsPath = 'C:\Program Files (x86)\World of Warcraft\_classic_era_\Interface\AddOns')
$ErrorActionPreference = 'Stop'
$Source = Split-Path -Parent $PSScriptRoot
$Resolved = (Resolve-Path -LiteralPath $AddOnsPath).Path.TrimEnd('\')
if ($Resolved -notmatch '\\_classic_era_\\Interface\\AddOns$') {
    throw 'Destination must be the existing Classic Era Interface\AddOns folder.'
}
$Destination = Join-Path $Resolved 'VoidMarkWarpath'
if ((Test-Path -LiteralPath $Destination) -and ((Get-Item -LiteralPath $Destination).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'Refusing to replace a junction or symbolic link. Remove it manually first.'
}
$Files = @('VoidMarkWarpath.toc', 'VoidMarkWarpath_Camelot.toc')
$Files += Get-Content -LiteralPath (Join-Path $Source 'VoidMarkWarpath.toc') | Where-Object { $_ -and -not $_.StartsWith('#') }
$Files += @('README.md', 'NOTICE.md', 'docs/API-AUDIT.md', 'docs/TESTING.md', 'docs/RELEASE.md')
foreach ($File in $Files) {
    if (-not (Test-Path -LiteralPath (Join-Path $Source $File))) { throw "Missing source: $File" }
}
if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
New-Item -ItemType Directory -Path $Destination | Out-Null
foreach ($File in $Files) {
    $Target = Join-Path $Destination $File
    New-Item -ItemType Directory -Path (Split-Path -Parent $Target) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $Source $File) -Destination $Target
}
Write-Host "Warpath installed to $Destination. Enable Warpath and use /warpath."
