#requires -version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Warpath.Core.ps1')
try {
    . (Join-Path $PSScriptRoot 'Warpath.Theme.ps1')
    . (Join-Path $PSScriptRoot 'Warpath.Editor.ps1')
    if([Warpath.OwnerGate]::Ask($null)){Show-WarpathCatalogEditor $null}
}catch{
    Write-WarpathLog ($_|Out-String)
    if('Warpath.DarkForm' -as [type]){Show-WarpathNote "Couldn't open the owner editor. Please extract the full owner package again."}
}
