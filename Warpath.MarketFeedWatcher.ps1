#requires -version 5.1
# Background copier for the VoidMark Market feed (see Warpath.MarketFeed.ps1).
# One copy runs at a time. It only checks file times every 3 seconds, and reads
# Market's saved data only after WoW writes it (logout or /reload).
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Warpath.Core.ps1')
. (Join-Path $PSScriptRoot 'Warpath.MarketFeed.ps1')
$mutex=New-Object Threading.Mutex($false,'Local\VoidMarkWarpathMarketFeed')
try{if(-not $mutex.WaitOne(0)){exit}}catch [Threading.AbandonedMutexException]{}
try {
    [Threading.Thread]::CurrentThread.Priority='BelowNormal'
    $state=@{sig=''};$addons='';$lookAt=[DateTime]::MinValue
    while($true) {
        try {
            if([DateTime]::UtcNow -ge $lookAt){$addons=Get-MarketFeedAddOns;$lookAt=[DateTime]::UtcNow.AddMinutes(1)}
            if($addons){[void](Update-MarketFeed $addons $state)}
        } catch {Write-WarpathLog ('Market feed: '+$_);$state.sig=''}
        Start-Sleep -Seconds 3
    }
} finally {$mutex.ReleaseMutex();$mutex.Dispose()}
