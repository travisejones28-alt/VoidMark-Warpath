# VoidMark Warpath analytics tests. No dependencies: runs on Windows PowerShell 5.1 or PowerShell 7.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
# Everything uses disposable folders under %TEMP%; live game folders and the real
# %APPDATA%\VoidMarkWarpath are never touched (APPDATA is redirected for the run).
# Optional end-to-end check against the real Worker code: start `node backend/test/dev-server.mjs`
# and set WARPATH_TEST_SERVER=http://127.0.0.1:8787 before running.
param([string]$Only='')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('warpath-tests-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($sandbox)|Out-Null
$realAppData=$env:APPDATA
$env:APPDATA=Join-Path $sandbox 'AppData'
[IO.Directory]::CreateDirectory($env:APPDATA)|Out-Null
. (Join-Path $repo 'Warpath.Core.ps1')
. (Join-Path $repo 'Warpath.Analytics.ps1')
. (Join-Path $repo 'Warpath.Dashboard.ps1')

$script:passed=0;$script:failed=@()
function Assert-True($Condition,[string]$Message){if(-not $Condition){throw ('Assert failed: '+$Message)}}
function Assert-Equal($Expected,$Actual,[string]$Message){if($Expected -ne $Actual){throw ('Assert failed: '+$Message+' (expected '+$Expected+', got '+$Actual+')')}}
function Test-Case([string]$Name,[scriptblock]$Body) {
    if($Only -and $Name -notlike ('*'+$Only+'*')){return}
    $dir=Join-Path $sandbox ('case-'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($dir)|Out-Null
    $script:case=$dir;$script:statePath=Join-Path $dir 'analytics.json'
    try {& $Body;$script:passed++;Write-Host ('  ok    '+$Name) -ForegroundColor Green}
    catch {$script:failed+=$Name;Write-Host ('  FAIL  '+$Name+"`n        "+$_.Exception.Message+' @ line '+$_.InvocationInfo.ScriptLineNumber) -ForegroundColor Red}
}
# A disposable WoW layout: <dir>\<game>\Interface\AddOns\<Addon>\<Addon>.toc
function New-FakeAddOns([string]$Game,[hashtable]$Folders) {
    $dir=Join-Path (Join-Path (Join-Path $script:case $Game.Replace(' ','')) 'Interface') 'AddOns'
    [IO.Directory]::CreateDirectory($dir)|Out-Null
    foreach($name in $Folders.Keys) {
        $f=Join-Path $dir $name;[IO.Directory]::CreateDirectory($f)|Out-Null
        [IO.File]::WriteAllText((Join-Path $f ($name+'.toc')),("## Interface: 16001`n## Title: $name`n## Version: "+$Folders[$name]+"`n"))
    }
    $dir
}
function New-OnState {$s=Read-WarpathAnalytics $script:statePath;Set-WarpathAnalyticsConsent $s $true $script:statePath;$s}
function New-Transport([scriptblock]$Responder) {
    $calls=New-Object Collections.ArrayList;$script:calls=$calls
    {param($url,$body) [void]$calls.Add(@{url=$url;body=$body}); & $Responder $url $body}.GetNewClosure()
}
function Get-AcceptAll {{param($url,$body) $ids=@(($body|ConvertFrom-Json).events|ForEach-Object {$_.id});@{status=200;body=(ConvertTo-Json -InputObject @{ok=$true;accepted=$ids;rejected=@()} -Compress)}}}

Write-Host 'VoidMark Warpath analytics tests'

# 1. First run: always on, notice not yet shown
Test-Case 'first run makes an id and statistics are on without asking' {
    $s=Initialize-WarpathAnalytics $script:statePath
    Assert-True (Test-WarpathInstallId $s.installId) 'valid UUID v4'
    Assert-True ([IO.File]::Exists($script:statePath)) 'analytics.json written'
    Assert-Equal 'unset' $s.consent 'notice not shown yet'
    Assert-True (Test-WarpathAnalyticsOn $s) 'on from the start'
    Assert-True (Register-WarpathAddonChange $s 'install' 'WoW Forever' 'VoidMark-Market' '1.0') 'install queued'
    $r=Invoke-WarpathAnalyticsStartup $s @{'WoW Forever'=(New-FakeAddOns 'WoW Forever' @{VoidMarkMarket='1.0'})} ([DateTime]::UtcNow) $script:statePath
    Assert-True $r.checkin 'check-in queued'
}

# 2. No opt-out: people who said No in 3.5.0 are on too
Test-Case 'an earlier No does not stop statistics' {
    $s=Read-WarpathAnalytics $script:statePath
    Set-WarpathAnalyticsConsent $s $false $script:statePath
    $back=Read-WarpathAnalytics $script:statePath
    Assert-Equal 'off' $back.consent 'old answer read'
    Assert-True (Test-WarpathAnalyticsOn $back) 'still on'
    Assert-True (Register-WarpathAddonChange $back 'update' 'WoW Forever' 'VoidMark-Market' '1.23.39') 'queued'
}

# 3. Anonymous ID persistence (incl. people updating from an older Warpath)
Test-Case 'the id persists across restarts, survives a damaged file and is never regenerated' {
    $a=Initialize-WarpathAnalytics $script:statePath
    $b=Initialize-WarpathAnalytics $script:statePath
    Assert-Equal $a.installId $b.installId 'same id on restart'
    Set-WarpathAnalyticsConsent $b $true $script:statePath
    $raw=[IO.File]::ReadAllText($script:statePath);[IO.File]::WriteAllText($script:statePath,$raw.Substring(0,[Math]::Min(80,$raw.Length)))   # truncated / corrupt
    $c=Initialize-WarpathAnalytics $script:statePath
    Assert-Equal $a.installId $c.installId 'id recovered from a damaged file'
    $settings=Join-Path $script:case 'settings.json';[IO.File]::WriteAllText($settings,'{"paths":{"WoW Forever":"C:\\x"}}')
    $fresh=Join-Path $script:case 'upgrade\analytics.json'
    $u=Initialize-WarpathAnalytics $fresh
    Assert-True (Test-WarpathInstallId $u.installId) 'upgrading user gets an id automatically'
    Assert-Equal 'unset' $u.consent 'upgrading user gets the one-time notice'
    Assert-Equal '{"paths":{"WoW Forever":"C:\\x"}}' ([IO.File]::ReadAllText($settings)) 'settings untouched'
    $json=[IO.File]::ReadAllText($fresh)
    Assert-True ($json -notmatch [regex]::Escape([Environment]::UserName) -or [Environment]::UserName.Length -lt 3) 'no Windows user name stored'
}

# 4/5. Install and update events
Test-Case 'install and update events carry only the allowed fields' {
    $s=New-OnState
    Assert-True (Register-WarpathAddonChange $s 'install' 'WoW Forever' 'VoidMark-Journey' '0.1.5') 'install queued'
    Assert-True (Register-WarpathAddonChange $s 'update' 'WoW Forever' 'VoidMark-Journey' '0.1.6') 'update queued'
    Assert-Equal 2 @($s.outbox).Count 'two events'
    Assert-Equal 'install' $s.outbox[0].type 'first is install'
    Assert-Equal 'update' $s.outbox[1].type 'second is update'
    foreach($e in $s.outbox){Assert-Equal 'game,id,repo,ts,type,version' ((@($e.Keys)|Sort-Object) -join ',') 'event fields'}
    Assert-Equal '0.1.6' $s.known['WoW Forever|VoidMark-Journey'] 'known version updated'
    Assert-True (-not (Register-WarpathAddonChange $s 'hack' 'WoW Forever' 'VoidMark-Journey' '1')) 'unknown type refused'
    $bad=Register-WarpathAddonChange $s 'update' 'WoW Forever' 'VoidMark-Journey' 'C:\Users\Someone\x'
    Assert-Equal '' $s.outbox[-1].version 'path-like version text is dropped'
}

Test-Case 'existing installs are registered once as detected, never as new installs' {
    $s=New-OnState
    $fe=New-FakeAddOns 'WoW Forever' @{VoidMarkMarket='1.23.38';VoidMarkNexus='0.10.23-beta'}
    $ce=New-FakeAddOns 'WoW Classic Era' @{VoidMark='1.3.11'}
    $paths=@{'WoW Forever'=$fe;'WoW Classic Era'=$ce}
    $r=Invoke-WarpathAnalyticsStartup $s $paths ([DateTime]::UtcNow) $script:statePath
    Assert-Equal 3 $r.detected 'three detected'
    Assert-Equal 3 @($s.outbox|Where-Object {$_.type -eq 'detected'}).Count 'three detected events'
    Assert-Equal 0 @($s.outbox|Where-Object {$_.type -eq 'install'}).Count 'no install events'
    $again=Invoke-WarpathAnalyticsStartup (Read-WarpathAnalytics $script:statePath) $paths ([DateTime]::UtcNow) $script:statePath
    Assert-Equal 0 $again.detected 'not registered again on the next launch'
    $check=@($s.outbox|Where-Object {$_.type -eq 'checkin'})[0]
    Assert-Equal 3 @($check.addons).Count 'check-in lists the addons'
    $body=ConvertTo-Json -InputObject @{events=@($s.outbox)} -Depth 8
    Assert-True ($body -cnotmatch 'Interface' -and $body -notmatch [regex]::Escape($script:case)) 'no paths in what would be sent'
}

Test-Case 'linked developer folders and folders without a .toc are ignored' {
    $s=New-OnState
    $fe=New-FakeAddOns 'WoW Forever' @{VoidMarkDebug='1.3.3-forever'}
    [IO.Directory]::CreateDirectory((Join-Path $fe 'VoidMarkMarket'))|Out-Null   # no .toc
    $found=@(Get-WarpathInstalledAddons @{'WoW Forever'=$fe})
    Assert-Equal 1 $found.Count 'only the real addon'
    Assert-Equal '1.3.3-forever' $found[0].version 'version from .toc'
}

# 6. Duplicate suppression
Test-Case 'retries reuse the same event ids and sent events are not sent again' {
    $s=New-OnState
    [void](Register-WarpathAddonChange $s 'install' 'WoW Forever' 'VoidMark-Market' '1.23.38')
    $id=$s.outbox[0].id
    $lost=New-Transport {param($u,$b) @{status=0;body=''}}
    $r1=Send-WarpathAnalytics 'https://x.example' $s.installId '3.5.0' $s.outbox @() $lost
    Complete-WarpathAnalyticsSend $s $r1 $script:statePath
    Assert-Equal 1 @($s.outbox).Count 'kept after a lost request'
    Assert-Equal $id $s.outbox[0].id 'same id for the retry'
    $t=New-Transport (Get-AcceptAll)
    $r2=Send-WarpathAnalytics 'https://x.example' $s.installId '3.5.0' $s.outbox @() $t
    Complete-WarpathAnalyticsSend $s $r2 $script:statePath
    Assert-Equal 0 @($s.outbox).Count 'removed once accepted'
    Assert-Equal $id (($script:calls[0].body|ConvertFrom-Json).events[0].id) 'server saw the original id'
    $r3=Send-WarpathAnalytics 'https://x.example' $s.installId '3.5.0' $s.outbox @() $t
    Assert-Equal 1 $script:calls.Count 'nothing left to send'
}

# 7. Daily check-in frequency
Test-Case 'check-in at most once every 24 hours' {
    $s=New-OnState
    $paths=@{'WoW Forever'=(New-FakeAddOns 'WoW Forever' @{VoidMarkMarket='1.0'})}
    $t0=[DateTime]::UtcNow
    Assert-True (Invoke-WarpathAnalyticsStartup $s $paths $t0 $script:statePath).checkin 'first launch'
    Assert-True (-not (Invoke-WarpathAnalyticsStartup $s $paths $t0.AddHours(1) $script:statePath).checkin) '1 hour later'
    Assert-True (-not (Invoke-WarpathAnalyticsStartup $s $paths $t0.AddHours(23.9) $script:statePath).checkin) '23.9 hours later'
    Assert-True (Invoke-WarpathAnalyticsStartup $s $paths $t0.AddHours(24.1) $script:statePath).checkin '24.1 hours later'
    Assert-Equal 2 @($s.outbox|Where-Object {$_.type -eq 'checkin'}).Count 'two check-ins'
}

# 8/9/10. Offline, backend failures, malformed replies
Test-Case 'offline, server errors and odd replies keep events for later' {
    $s=New-OnState
    [void](Register-WarpathAddonChange $s 'update' 'WoW Forever' 'VoidMark-Market' '1.23.38')
    $cases=@(
        @{reply=@{status=0;body=''};error='offline'},
        @{reply=@{status=500;body='{"ok":false}'};error='http-500'},
        @{reply=@{status=429;body=''};error='rate-limited'},
        @{reply=@{status=200;body='<html>proxy</html>'};error='bad-reply'},
        @{reply=@{status=200;body='{"ok":false}'};error='bad-reply'},
        @{reply=@{status=200;body='{"ok":true}'};error='bad-reply'},
        @{reply=@{status=200;body='[1,2]'};error='bad-reply'}
    )
    foreach($c in $cases) {
        $reply=$c.reply
        $r=Send-WarpathAnalytics 'https://x.example' $s.installId '3.5.0' $s.outbox @() {param($u,$b) $reply}.GetNewClosure()
        Complete-WarpathAnalyticsSend $s $r $script:statePath
        Assert-Equal $c.error $r.error ('error for status '+$reply.status)
        Assert-Equal 1 @($s.outbox).Count ('kept after '+$c.error)
    }
    $r=Send-WarpathAnalytics '' $s.installId '3.5.0' $s.outbox @() $null
    Assert-Equal 'no-endpoint' $r.error 'no server configured'
    $throws=Send-WarpathAnalytics 'https://x.example' $s.installId '3.5.0' $s.outbox @() {param($u,$b) @{status=200;body='{"ok":true,"accepted":["not-ours"],"rejected":[]}'}}
    Complete-WarpathAnalyticsSend $s $throws $script:statePath
    Assert-Equal 1 @($s.outbox).Count 'ids the server did not acknowledge are kept'
}

Test-Case 'events the server refuses for good are dropped; the outbox is capped' {
    $s=New-OnState
    [void](Register-WarpathAddonChange $s 'update' 'WoW Forever' 'VoidMark-Market' '1')
    $id=$s.outbox[0].id
    $r=Send-WarpathAnalytics 'https://x.example' $s.installId '3.5.0' $s.outbox @() {param($u,$b) @{status=200;body=('{"ok":true,"accepted":[],"rejected":["'+$id+'"]}')}}.GetNewClosure()
    Complete-WarpathAnalyticsSend $s $r $script:statePath
    Assert-Equal 0 @($s.outbox).Count 'rejected event dropped'
    for($i=0;$i -lt 230;$i++){[void](Register-WarpathAddonChange $s 'update' 'WoW Forever' 'VoidMark-Market' ([string]$i))}
    Assert-Equal 200 @($s.outbox).Count 'capped at 200'
    Assert-Equal '229' $s.outbox[-1].version 'newest kept'
    $old=New-WarpathAnalyticsEvent 'update' @{game='WoW Forever';repo='VoidMark-Market';version='old'} ([DateTime]::UtcNow.AddDays(-40))
    $s.outbox=@($old);Limit-WarpathOutbox $s
    Assert-Equal 0 @($s.outbox).Count 'events older than 30 days expire'
}

Test-Case 'events are sent in batches of 50' {
    $s=New-OnState
    for($i=0;$i -lt 120;$i++){[void](Register-WarpathAddonChange $s 'update' 'WoW Forever' 'VoidMark-Market' ([string]$i))}
    $t=New-Transport (Get-AcceptAll)
    $r=Send-WarpathAnalytics 'https://x.example' $s.installId '3.5.0' $s.outbox @() $t
    Assert-Equal 3 $script:calls.Count 'three requests'
    Assert-Equal 120 @($r.sent).Count 'all acknowledged'
    $b=$script:calls[0].body|ConvertFrom-Json
    Assert-Equal 'installId,appVersion,events' (@($b.PSObject.Properties.Name) -join ',') 'request fields'
}

# In-game usage from SavedVariables (disposable WTF tree)
Test-Case 'in-game usage times are read from SavedVariables (newest across accounts) and sent with check-ins only' {
    $fe=New-FakeAddOns 'WoW Forever' @{VoidMarkMarket='1.23.39'}
    $wtf=Join-Path (Split-Path (Split-Path $fe -Parent) -Parent) 'WTF'
    foreach($acct in @(@('ACCOUNT1',1763300000,1763300100),@('ACCOUNT2',1763400000,$null))) {
        $sv=Join-Path (Join-Path (Join-Path $wtf 'Account') $acct[0]) 'SavedVariables';[IO.Directory]::CreateDirectory($sv)|Out-Null
        $active=if($acct[2]){"`t[`"active`"] = "+$acct[2]+",`n"}else{''}
        [IO.File]::WriteAllText((Join-Path $sv 'VoidMarkMarket.lua'),("VoidMarkMarketDB = {`n`t[`"reinit`"] = 1999999999,`n}`nVoidMarkMarketUsage = {`n`t[`"v`"] = 1,`n`t[`"init`"] = "+$acct[1]+",`n"+$active+"`t[`"version`"] = `"1.23.39`",`n}`n"))
    }
    $u=Get-WarpathAddonUsage $fe 'VoidMarkMarket'
    Assert-Equal 1763400000 $u.init 'newest init across accounts'
    Assert-Equal 1763300100 $u.active 'active from the account that has it'
    Assert-Equal $null (Get-WarpathAddonUsage $fe 'VoidMarkNexus') 'addon without usage data'
    Assert-Equal $null (Get-WarpathAddonUsage (Join-Path $script:case 'NotAddOns') 'VoidMarkMarket') 'only real AddOns folders'
    $s=New-OnState
    [void](Invoke-WarpathAnalyticsStartup $s @{'WoW Forever'=$fe} ([DateTime]::UtcNow) $script:statePath)
    $t=New-Transport (Get-AcceptAll)
    [void](Send-WarpathAnalytics 'https://x.example' $s.installId '3.5.0' $s.outbox @(@{game='WoW Forever';repo='VoidMark-Market';usage=$u}) $t)
    $sent=$script:calls[0].body|ConvertFrom-Json
    $ci=@($sent.events|Where-Object {$_.type -eq 'checkin'})[0]
    Assert-Equal 1763400000 $ci.addons[0].usage.init 'usage attached to the check-in'
    Assert-True (-not (Get-Content -Raw $script:statePath).Contains('1763400000')) 'usage is not stored by Warpath'
}

# 11. Version parsing
Test-Case 'version parsing and comparison' {
    Assert-Equal 0 (Compare-AddonVersion '1.23.38' '1.23.38') 'equal'
    Assert-Equal -1 (Compare-AddonVersion '1.23.9' '1.23.38') 'numeric, not text, order'
    Assert-Equal 1 (Compare-AddonVersion '1.3' '1.2.29') 'shorter but newer'
    Assert-Equal 0 (Compare-AddonVersion '1.2' '1.2.0') 'missing parts are zero'
    Assert-Equal -1 (Compare-AddonVersion '0.11.1-beta' '0.11.1') 'beta before release'
    Assert-Equal 1 (Compare-AddonVersion '0.11.1-beta' '0.10.23-beta') 'betas by number'
    Assert-Equal 0 (Compare-AddonVersion '1.3.3-forever' '1.3.3-forever') 'tag kept'
    Assert-Equal 0 (Compare-AddonVersion 'v2.0' '2.0') 'leading v'
    Assert-Equal $null (Compare-AddonVersion 'abc1234' '1.0') 'commit ids are not versions'
}

# 12. Pinned (paused) versions
Test-Case 'pinned versions count as up to date; unpinned addons compare with the latest' {
    $versions=@(@{version='0.10.23-beta';installs=6},@{version='0.10.20-beta';installs=2},@{version='0.11.1-beta';installs=2})
    $pinned=Get-AddonAdoption $versions '0.11.1-beta' '0.10.23-beta'
    Assert-Equal '0.10.23-beta' $pinned.target 'target is the pinned version'
    Assert-Equal 8 $pinned.current 'on pin (and the owner on newer) are current'
    Assert-Equal 2 $pinned.outdated 'only older than the pin are outdated'
    Assert-Equal 80 $pinned.onTargetPct 'percentage'
    Assert-Equal '0.10.23-beta' $pinned.mostCommon 'most installed'
    $free=Get-AddonAdoption $versions '0.11.1-beta' ''
    Assert-Equal 8 $free.outdated 'without a pin, everyone behind latest is outdated'
    Assert-Equal 20 $free.onTargetPct 'percentage on latest'
    $none=Get-AddonAdoption $versions '' ''
    Assert-Equal $null $none.onTargetPct 'unknown until the latest version is read'
    $catalog=@(@{game='WoW Forever';repo='VoidMark-Nexus';sha='d6b48527f3dc797107dc91e2a01c118cd30c3a51';label='0.10.23-beta'},@{game='WoW Forever';repo='VoidMark-Market'})
    Assert-Equal '0.10.23-beta' (Get-CatalogPin $catalog 'WoW Forever' 'VoidMark-Nexus') 'pin read from catalog'
    Assert-Equal '' (Get-CatalogPin $catalog 'WoW Forever' 'VoidMark-Market') 'no pin'
    $live=@(ConvertFrom-PublicCatalog ([IO.File]::ReadAllText((Join-Path $repo 'public-catalog.json'))))
    Assert-True ((Get-CatalogPin $live 'WoW Forever' 'VoidMark-Nexus') -ne '') 'the real public-catalog.json pin is recognised'
}

Test-Case 'daily series fill missing days' {
    $f=Get-FilledSeries @(@{day='2026-11-10';count=2},@{day='2026-11-12';count=5}) '2026-11-10' '2026-11-13'
    Assert-Equal 4 $f.labels.Count 'four days'
    Assert-Equal '0' ([string]$f.values[1]) 'gap is zero'
    $all=Get-FilledSeries @(@{day='2026-11-12';count=1}) '2000-01-01' '2026-11-13'
    Assert-Equal 2 $all.labels.Count 'all time starts at the first data day'
}

# 13. Owner authentication (client side; the server side is in backend/test)
Test-Case 'owner dashboard sends the token only as a bearer header and explains refusals' {
    $seen=New-Object Collections.ArrayList
    $t={param($url,$headers) [void]$seen.Add(@{url=$url;headers=$headers});@{status=401;body='{"ok":false}'}}.GetNewClosure()
    $r=Get-WarpathAnalyticsSummary 'https://x.example' 'tok_abcdefghijklmnopqrstuvwxyz012345' @{range='30';game='WoW Forever'} $t
    Assert-True (-not $r.ok) 'refused'
    Assert-Equal 401 $r.status 'status'
    Assert-Equal 'Bearer tok_abcdefghijklmnopqrstuvwxyz012345' $seen[0].headers.Authorization 'bearer header'
    Assert-True ($seen[0].url -notmatch 'tok_') 'token not in the URL'
    Assert-Equal 'https://x.example/v1/admin/summary?game=WoW%20Forever&range=30' $seen[0].url 'query'
    Assert-True (-not (Get-WarpathAnalyticsSummary 'https://x.example' '' @{} $t).ok) 'no token, no request'
    Assert-Equal 1 $seen.Count 'no request without a token'
    foreach($c in @(@(429,'Too many'),@(503,'no admin token'),@(0,"Couldn't reach"),@(500,'error 500'))) {
        $code=$c[0];$x=Get-WarpathAnalyticsSummary 'https://x.example' 'tok_abcdefghijklmnopqrstuvwxyz012345' @{} {param($u,$h) @{status=$code;body=''}}.GetNewClosure()
        Assert-True ($x.error -like ('*'+$c[1]+'*')) ('message for '+$code)
    }
    $bad=Get-WarpathAnalyticsSummary 'https://x.example' 'tok_abcdefghijklmnopqrstuvwxyz012345' @{} {param($u,$h) @{status=200;body='{"ok":true}'}}
    Assert-True (-not $bad.ok) 'malformed summary refused'
    $good=Get-WarpathAnalyticsSummary 'https://x.example' 'tok_abcdefghijklmnopqrstuvwxyz012345' @{} {param($u,$h) @{status=200;body='{"ok":true,"totals":{"warpathInstalls":3},"addons":[],"series":{}}'}}
    Assert-True $good.ok 'valid summary accepted'
    Assert-Equal 3 $good.data.totals.warpathInstalls 'parsed'
}

# 14. Rate limiting (client behaviour; server limits are in backend/test)
Test-Case 'a rate-limited send stops early and keeps everything' {
    $s=New-OnState
    for($i=0;$i -lt 60;$i++){[void](Register-WarpathAddonChange $s 'update' 'WoW Forever' 'VoidMark-Market' ([string]$i))}
    $t=New-Transport {param($u,$b) @{status=429;body=''}}
    $r=Send-WarpathAnalytics 'https://x.example' $s.installId '3.5.0' $s.outbox @() $t
    Assert-Equal 1 $script:calls.Count 'stopped after the first 429'
    Assert-Equal 'rate-limited' $r.error 'reported'
    Assert-Equal 0 @($r.sent).Count 'nothing marked sent'
}

# 15. Deletion
Test-Case 'deleting this installation sends only the id and reports the result' {
    $t=New-Transport {param($u,$b) @{status=200;body='{"ok":true,"deleted":true}'}}
    $r=Remove-WarpathAnalyticsData 'https://x.example' '3f0e8c7a-1b2c-4d5e-8f90-123456789abc' $t
    Assert-True $r.ok 'deleted'
    Assert-Equal 'https://x.example/v1/installations/delete' $script:calls[0].url 'endpoint'
    Assert-Equal '{"installId":"3f0e8c7a-1b2c-4d5e-8f90-123456789abc"}' $script:calls[0].body 'body'
    Assert-True (-not (Remove-WarpathAnalyticsData 'https://x.example' 'x' {param($u,$b) @{status=0;body=''}}).ok) 'offline'
    Assert-Equal 'no-endpoint' (Remove-WarpathAnalyticsData '' 'x').error 'no server'
    $s=New-OnState
    [void](Register-WarpathAddonChange $s 'install' 'WoW Forever' 'VoidMark-Market' '1')
    $s.pendingDelete=$true;Save-WarpathAnalytics $s $script:statePath
    $back=Read-WarpathAnalytics $script:statePath
    Assert-True $back.pendingDelete 'a pending deletion survives a restart'
    Assert-True (-not (Test-WarpathAnalyticsOn $back)) 'nothing is sent while a deletion is pending'
}

# 16. Failure recovery without affecting addon updates
Test-Case 'statistics failures never reach the install path' {
    # A broken analytics.json location (a folder in its place) must not throw out of Initialize.
    $blocked=Join-Path $script:case 'blocked.json';[IO.Directory]::CreateDirectory($blocked)|Out-Null
    $r=Initialize-WarpathAnalytics $blocked
    Assert-Equal $null $r 'returns nothing instead of throwing'
    # Install-WarpathEntry and the worker have no statistics code at all.
    $core=[IO.File]::ReadAllText((Join-Path $repo 'Warpath.Core.ps1'))
    $m=[regex]::Match($core,'(?s)function Install-WarpathEntry.*?\n}\r?\nfunction Update-WarpathApp')
    Assert-True ($m.Success -and $m.Value -notmatch '(?i)analytic|telemetry') 'installer untouched'
    $w=[regex]::Match($core,'(?s)function Invoke-WarpathWorker.*?\n}\r?\n')
    Assert-True ($w.Success -and $w.Value -notmatch '(?i)analytic|telemetry') 'worker untouched'
    # The window's hooks swallow errors: each analytics call site is inside try/catch.
    $main=[IO.File]::ReadAllText((Join-Path $repo 'VoidMarkWarpath.ps1'))
    foreach($fn in @('Register-AnalyticsInstall','Start-AnalyticsJob','Complete-AnalyticsJob','Invoke-AnalyticsStartup')) {
        $b=[regex]::Match($main,'(?s)function '+$fn+'\b[^{]*\{.*?\n    \}\r?\n')
        Assert-True ($b.Success -and $b.Value -match 'try \{' -and $b.Value -match 'catch') ($fn+' is guarded')
    }
    # With statistics off and nothing configured, the background job is a no-op.
    $job=Invoke-WarpathAnalyticsJob 'send' (Join-Path $script:case 'no-root') ([guid]::NewGuid().ToString()) '3.5.0' @() @()
    Assert-True ($null -ne $job) 'job returns a result'
}

Test-Case "the owner's own copy sends nothing and deletes what it already sent" {
    $root=Join-Path $script:case 'owner';[IO.Directory]::CreateDirectory($root)|Out-Null
    Assert-True (-not (Test-WarpathOwnerCopy $root)) 'friend copy'
    [IO.File]::WriteAllText((Join-Path $root 'Owner-Catalog-Editor.ps1'),'#')
    Assert-True (Test-WarpathOwnerCopy $root) 'owner copy'
    $s=New-OnState
    [void](Register-WarpathAddonChange $s 'install' 'WoW Forever' 'VoidMark-Market' '1')
    Assert-True (Set-WarpathOwnerExcluded $s $script:statePath) 'deletion needed once'
    Assert-Equal 0 @($s.outbox).Count 'queue cleared'
    $s.pendingDelete=$false;Save-WarpathAnalytics $s $script:statePath   # as after a successful delete
    $back=Read-WarpathAnalytics $script:statePath
    Assert-True $back.ownerExcluded 'remembered'
    Assert-True (-not (Test-WarpathAnalyticsOn $back)) 'stays off after the delete'
    Assert-True (-not (Set-WarpathOwnerExcluded $back $script:statePath)) 'no second deletion'
    Assert-True (-not (Register-WarpathAddonChange $back 'update' 'WoW Forever' 'VoidMark-Market' '2')) 'nothing queued'
    $r=Invoke-WarpathAnalyticsStartup $back @{'WoW Forever'=(New-FakeAddOns 'WoW Forever' @{VoidMarkMarket='1'})} ([DateTime]::UtcNow) $script:statePath
    Assert-True (-not $r.checkin) 'no check-in'
    # 3.7.3: a friend copy wrongly marked as the owner's goes back to sending.
    Assert-True (Reset-WarpathOwnerExcluded $back $script:statePath) 'reset wrong owner mark'
    $again=Read-WarpathAnalytics $script:statePath
    Assert-True (-not $again.ownerExcluded -and -not $again.pendingDelete) 'reset remembered'
    Assert-True (Test-WarpathAnalyticsOn $again) 'statistics on again'
    Assert-True (-not (Reset-WarpathOwnerExcluded $again $script:statePath)) 'no second reset'
}

Test-Case 'server address must be https and is read from the local copy when GitHub is unreachable' {
    $root=Join-Path $script:case 'app';[IO.Directory]::CreateDirectory($root)|Out-Null
    [IO.File]::WriteAllText((Join-Path $root 'analytics-endpoint.txt'),"https://voidmark-analytics.example.workers.dev/`n")
    Assert-Equal 'https://voidmark-analytics.example.workers.dev' (Get-WarpathAnalyticsEndpoint $root {throw 'offline'}) 'local fallback'
    Assert-Equal '' (Get-WarpathAnalyticsEndpoint $root {''}) 'GitHub copy empty = statistics off'
    Assert-Equal '' (Get-WarpathAnalyticsEndpoint $root {'http://plain.example'}) 'http refused'
    Assert-Equal '' (Get-WarpathAnalyticsEndpoint $root {'https://x.example/?a=<script>'}) 'odd characters refused'
    Assert-Equal 'https://a.b.workers.dev' (Get-WarpathAnalyticsEndpoint $root {'https://a.b.workers.dev'}) 'GitHub copy used first'
}

# Optional: real Worker code over HTTP (node backend/test/dev-server.mjs).
if($env:WARPATH_TEST_SERVER) {
    Test-Case 'end-to-end with the Worker: register, check in, retry, summary, delete' {
        $base=$env:WARPATH_TEST_SERVER.TrimEnd('/')
        $http={param($url,$body)
            try{$r=Invoke-WebRequest -Uri $url -Method Post -Body $body -ContentType 'application/json' -UseBasicParsing -TimeoutSec 10 -NoProxy;@{status=[int]$r.StatusCode;body=[string]$r.Content}}
            catch{$c=0;try{$c=[int]$_.Exception.Response.StatusCode}catch{};@{status=$c;body=''}}}
        $s=New-OnState
        $fe=New-FakeAddOns 'WoW Forever' @{VoidMarkMarket='1.23.38';VoidMarkNexus='0.10.23-beta'}
        [void](Invoke-WarpathAnalyticsStartup $s @{'WoW Forever'=$fe} ([DateTime]::UtcNow) $script:statePath)
        [void](Register-WarpathAddonChange $s 'install' 'WoW Forever' 'VoidMark-Journey' '0.1.5')
        $copy=@($s.outbox)
        $r=Send-WarpathAnalytics $base $s.installId '3.5.0' $s.outbox @(@{game='WoW Forever';repo='VoidMark-Market';usage=@{init=1763300000;active=1763300100}}) $http
        Assert-True $r.ok ('sent: '+$r.error)
        Assert-Equal 4 @($r.sent).Count 'detected x2, check-in, install'
        Complete-WarpathAnalyticsSend $s $r $script:statePath
        $again=Send-WarpathAnalytics $base $s.installId '3.5.0' $copy @() $http
        Assert-Equal 4 @($again.sent).Count 'retry acknowledged without double counting'
        $sum=Get-WarpathAnalyticsSummary $base $env:WARPATH_TEST_TOKEN @{range='30'} {param($u,$h)
            try{$x=Invoke-WebRequest -Uri $u -Headers $h -UseBasicParsing -NoProxy;@{status=[int]$x.StatusCode;body=[string]$x.Content}}catch{$c=0;try{$c=[int]$_.Exception.Response.StatusCode}catch{};@{status=$c;body=''}}}
        Assert-True $sum.ok ('summary: '+$sum.error)
        Assert-Equal 3 ([int]$sum.data.totals.addonInstalls) 'three addon installations'
        Assert-Equal 2 ([int]$sum.data.totals.detectedExisting) 'two detected'
        Assert-Equal 1 ([int]$sum.data.totals.newAddonInstallsWeek) 'one new install'
        $del=Remove-WarpathAnalyticsData $base $s.installId $http
        Assert-True $del.ok 'deleted'
    }
}

$env:APPDATA=$realAppData
try{Remove-Item -LiteralPath $sandbox -Recurse -Force}catch{}
Write-Host ('{0} passed, {1} failed' -f $script:passed,$script:failed.Count)
if($script:failed.Count){exit 1}
