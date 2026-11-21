# VoidMark Warpath saved-data backup tests. Disposable folders under %TEMP% only.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\Backup-Tests.ps1
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'Warpath.Backup.ps1')
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('warpath-backup-tests-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($sandbox)|Out-Null
$script:passed=0;$script:failed=@()
function Assert-True($c,[string]$m){if(-not $c){throw ('Assert failed: '+$m)}}
function Assert-Equal($e,$a,[string]$m){if($e -ne $a){throw ('Assert failed: '+$m+' (expected '+$e+', got '+$a+')')}}
function J {param([string[]]$Parts) $p=$Parts[0];foreach($x in $Parts[1..($Parts.Count-1)]){$p=Join-Path $p $x};$p}
function Write-File([string]$Path,[string]$Text){[IO.Directory]::CreateDirectory((Split-Path $Path -Parent))|Out-Null;[IO.File]::WriteAllText($Path,$Text)}
function New-FakeGame {
    $g=J @($script:case,'World of Warcraft','_forever_')
    [IO.Directory]::CreateDirectory((J @($g,'Interface','AddOns')))|Out-Null
    $a1=J @($g,'WTF','Account','ACCOUNT1');$a2=J @($g,'WTF','Account','ACCOUNT2')
    Write-File (J @($a1,'SavedVariables','VoidMarkMarket.lua')) ('VoidMarkMarketDB = { big = "'+('x'*200000)+'" }')
    Write-File (J @($a1,'SavedVariables','VoidMarkMarket.lua.bak')) 'old'
    Write-File (J @($a1,'SavedVariables','VoidMarkNexus.lua')) 'VoidMarkNexusDB = {}'
    Write-File (J @($a1,'CAMWOW US2 Realm 8 PvP','Voidmark Soulreaver','SavedVariables','VoidMarkJourney.lua')) 'VoidMarkJourneyDB = { dings = 56 }'
    Write-File (J @($a1,'config-cache.wtf')) 'SET accountSetting "1"'
    Write-File (J @($a1,'CAMWOW US2 Realm 8 PvP','Voidmark Soulreaver','macros-cache.txt')) 'MACRO 1 "Fear"'
    Write-File (J @($a1,'CAMWOW US2 Realm 8 PvP','Voidmark Soulreaver','AddOns.txt')) 'VoidMarkMarket: enabled'
    Write-File (J @($a1,'CAMWOW US2 Realm 8 PvP','Voidmark Soulreaver','some-other.log')) 'not backed up'
    Write-File (J @($g,'WTF','Config.wtf')) 'SET gxWindow "1"'
    Write-File (J @($a2,'SavedVariables','VoidMarkMarket.lua')) 'VoidMarkMarketDB = { bank = true }'
    $g
}
function Test-Case([string]$Name,[scriptblock]$Body) {
    $script:case=Join-Path $sandbox ('case-'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($script:case)|Out-Null
    try {& $Body;$script:passed++;Write-Host ('  ok    '+$Name) -ForegroundColor Green}
    catch {$script:failed+=$Name;Write-Host ('  FAIL  '+$Name+"`n        "+$_.Exception.Message+' @ line '+$_.InvocationInfo.ScriptLineNumber) -ForegroundColor Red}
}
Write-Host 'VoidMark Warpath backup tests'

Test-Case 'finds the game; saved data plus setup files (macros, addons list, settings) for every account and character' {
    $g=New-FakeGame
    Assert-Equal $g (Get-WtfGameRoot (J @($g,'Interface','AddOns'))) 'game root'
    Assert-Equal $null (Get-WtfGameRoot (J @($g,'Interface'))) 'not an AddOns folder'
    $rel=@(Get-WtfSavedFiles $g|ForEach-Object {$_.rel})|Sort-Object
    Assert-Equal 8 $rel.Count ('eight files: '+($rel -join ', '))
    Assert-True ($rel -contains 'Config.wtf') 'client settings'
    Assert-True ($rel -contains 'Account/ACCOUNT1/config-cache.wtf') 'account settings'
    Assert-True ($rel -contains 'Account/ACCOUNT1/CAMWOW US2 Realm 8 PvP/Voidmark Soulreaver/macros-cache.txt') 'macros'
    Assert-True ($rel -contains 'Account/ACCOUNT1/CAMWOW US2 Realm 8 PvP/Voidmark Soulreaver/AddOns.txt') 'enabled addons'
    Assert-True (-not ($rel -like '*.log')) 'other files left out'
    Assert-True ($rel -contains 'Account/ACCOUNT2/SavedVariables/VoidMarkMarket.lua') 'second account'
    Assert-True ($rel -contains 'Account/ACCOUNT1/CAMWOW US2 Realm 8 PvP/Voidmark Soulreaver/SavedVariables/VoidMarkJourney.lua') 'per-character'
    Assert-True (-not ($rel -like '*.bak')) 'no .bak'
}

Test-Case 'backup zip holds every file byte-for-byte, is verified, and leaves the game folder untouched' {
    $g=New-FakeGame;$dir=Join-Path $script:case 'backups'
    $before=@(Get-ChildItem -LiteralPath $g -Recurse -File|ForEach-Object {$_.FullName+'|'+$_.Length+'|'+$_.LastWriteTimeUtc.Ticks})
    $r=New-WtfBackup $g $dir 'auto' ([datetime]'2026-11-21 10:00:00')
    Assert-True $r.ok ('backup ok: '+$r.error)
    Assert-Equal 8 $r.files 'files'
    Assert-True ($r.zipBytes -lt $r.bytes) 'compressed'
    Assert-Equal 'WTF-20261121-100000.zip' (Split-Path $r.path -Leaf) 'name'
    $z=[IO.Compression.ZipFile]::OpenRead($r.path)
    try {
        $e=$z.GetEntry('Account/ACCOUNT1/SavedVariables/VoidMarkMarket.lua');$rd=New-Object IO.StreamReader($e.Open())
        try{Assert-Equal ([IO.File]::ReadAllText((J @($g,'WTF','Account','ACCOUNT1','SavedVariables','VoidMarkMarket.lua')))) $rd.ReadToEnd() 'same content'}finally{$rd.Dispose()}
    } finally {$z.Dispose()}
    $after=@(Get-ChildItem -LiteralPath $g -Recurse -File|ForEach-Object {$_.FullName+'|'+$_.Length+'|'+$_.LastWriteTimeUtc.Ticks})
    Assert-Equal ($before -join ';') ($after -join ';') 'game folder unchanged'
    Assert-Equal 0 @(Get-ChildItem -LiteralPath $dir -Filter '.partial-*').Count 'no partial file left'
}

Test-Case 'reads a file WoW has open for writing' {
    $g=New-FakeGame;$dir=Join-Path $script:case 'backups'
    $f=J @($g,'WTF','Account','ACCOUNT1','SavedVariables','VoidMarkNexus.lua')
    $lock=New-Object IO.FileStream($f,'Open','ReadWrite','ReadWrite')
    try{$r=New-WtfBackup $g $dir}finally{$lock.Dispose()}
    Assert-True $r.ok ('backup with an open file: '+$r.error);Assert-Equal 8 $r.files 'all files'
}

Test-Case 'due only every 6 hours' {
    $g=New-FakeGame;$dir=Join-Path $script:case 'backups'
    Assert-True (Test-WtfBackupDue $dir ([datetime]'2026-11-21 10:00')) 'no backups yet'
    [void](New-WtfBackup $g $dir 'auto' ([datetime]'2026-11-21 10:00'))
    Assert-True (-not (Test-WtfBackupDue $dir ([datetime]'2026-11-21 15:59'))) 'not yet'
    Assert-True (Test-WtfBackupDue $dir ([datetime]'2026-11-21 16:00')) 'six hours later'
}

Test-Case 'a big file that shrinks or vanishes protects the last good backup from clean-up' {
    $g=New-FakeGame;$dir=Join-Path $script:case 'backups'
    $good=New-WtfBackup $g $dir 'auto' ([datetime]'2026-11-20 10:00')
    Write-File (J @($g,'WTF','Account','ACCOUNT1','SavedVariables','VoidMarkMarket.lua')) 'VoidMarkMarketDB = {}'
    $r=New-WtfBackup $g $dir 'auto' ([datetime]'2026-11-21 10:00')
    Assert-True $r.ok 'second backup'
    Assert-Equal 1 @($r.warnings).Count 'one warning'
    Assert-True ($r.warnings[0] -like '*VoidMarkMarket.lua shrank*') $r.warnings[0]
    Assert-True ([IO.File]::Exists((Join-Path $dir 'WTF-20261120-100000-keep.zip'))) 'last good backup marked keep'
    for($i=0;$i -lt 40;$i++){[void](New-WtfBackup $g $dir 'auto' ([datetime]'2026-11-21 11:00').AddMinutes($i))}
    [void](Remove-OldWtfBackups $dir ([datetime]'2027-03-01'))
    Assert-True ([IO.File]::Exists((Join-Path $dir 'WTF-20261120-100000-keep.zip'))) 'keep survives clean-up'
}

Test-Case 'clean-up keeps the newest 20 plus one per day for 30 days' {
    $g=New-FakeGame;$dir=Join-Path $script:case 'backups';$now=[datetime]'2026-11-21 12:00'
    for($d=0;$d -lt 40;$d++){for($h=0;$h -lt 3;$h++){[void](New-WtfBackup $g $dir 'auto' $now.AddDays(-$d).AddHours(-$h))}}
    [void](Remove-OldWtfBackups $dir $now)
    $left=@(Get-WtfBackups $dir)
    Assert-True ($left.Count -ge 20 -and $left.Count -le 20+31) ('count '+$left.Count)
    Assert-True (@($left|Where-Object {($now-$_.at).TotalDays -gt 31}).Count -eq 0) 'nothing older than 30 days'
    Assert-Equal $now @($left)[0].at 'newest kept'
}

Test-Case 'restore puts files back, makes a kept safety backup first, and ignores unsafe paths' {
    $g=New-FakeGame;$dir=Join-Path $script:case 'backups'
    $b=New-WtfBackup $g $dir 'auto' ([datetime]'2026-11-20 10:00')
    $journey=J @($g,'WTF','Account','ACCOUNT1','CAMWOW US2 Realm 8 PvP','Voidmark Soulreaver','SavedVariables','VoidMarkJourney.lua')
    Write-File $journey 'VoidMarkJourneyDB = { dings = 0 }'      # "lost" history
    # A hostile entry must never escape WTF\Account.
    $z=[IO.Compression.ZipFile]::Open($b.path,'Update');try{$e=$z.CreateEntry('Account/../../evil.lua');$w=New-Object IO.StreamWriter($e.Open());$w.Write('x');$w.Dispose()}finally{$z.Dispose()}
    $r=Restore-WtfBackup $b.path $g $dir
    Assert-True $r.ok ('restore: '+$r.error)
    Assert-Equal 8 $r.files 'all files restored'
    Assert-Equal 'VoidMarkJourneyDB = { dings = 56 }' ([IO.File]::ReadAllText($journey)) 'history back'
    Assert-True ($r.safety -like '*-keep.zip') 'safety backup kept'
    Assert-True (-not [IO.File]::Exists((J @($g,'evil.lua')))) 'unsafe path ignored'
    Assert-True (-not [IO.File]::Exists((J @($g,'WTF','evil.lua')))) 'unsafe path ignored (WTF)'
}

Test-Case 'Invoke-WtfBackups skips folders that are not set up and only runs when due' {
    $g=New-FakeGame;$base=Join-Path $script:case 'all'
    $t=@(@{game='WoW Forever';addOns=(J @($g,'Interface','AddOns'))},@{game='WoW Classic Era';addOns=''})
    $r=@(Invoke-WtfBackups $t 'auto' $true $base)
    Assert-Equal 1 $r.Count 'one game backed up';Assert-True $r[0].ok 'ok'
    Assert-Equal 0 @(Invoke-WtfBackups $t 'auto' $true $base 0).Count 'nothing changed: no new automatic backup'
    Start-Sleep -Milliseconds 1100
    Write-File (J @($g,'WTF','Account','ACCOUNT2','SavedVariables','VoidMarkMarket.lua')) 'VoidMarkMarketDB = { bank = false }'
    Assert-Equal 1 @(Invoke-WtfBackups $t 'auto' $true $base 0).Count 'changed: backed up'
    Assert-Equal 0 @(Invoke-WtfBackups $t 'auto' $true $base).Count 'not due again (6 h)'
    Assert-Equal 1 @(Invoke-WtfBackups $t 'manual' $false $base).Count 'manual always runs'
}

Test-Case 'restore only writes backup files inside WTF' {
    Assert-True (Test-WtfBackupPath 'Account/A/SavedVariables/X.lua') 'saved data'
    Assert-True (Test-WtfBackupPath 'Account/A/R/C/macros-cache.txt') 'macros'
    Assert-True (Test-WtfBackupPath 'Config.wtf') 'config'
    foreach($bad in @('Account/../x.lua','../Config.wtf','Account/A/SavedVariables/X.lua.bak','Account/A/evil.exe','Interface/AddOns/X/X.lua','/Account/A/SavedVariables/X.lua','C:/x/Account/A/SavedVariables/X.lua')) {
        Assert-True (-not (Test-WtfBackupPath $bad)) ('refused '+$bad)
    }
}

Test-Case 'hourly background backup: waits for WoW to close, skips when nothing changed, honours off and the chosen folder' {
    $g=New-FakeGame;$base=Join-Path $script:case 'chosen'
    $settings=Join-Path $script:case 'settings.json'
    [IO.File]::WriteAllText($settings,(@{paths=@{'WoW Forever'=(J @($g,'Interface','AddOns'));'WoW Classic Era'=''};backupFolder=$base}|ConvertTo-Json))
    Assert-Equal 'WoW is running' (Invoke-WtfScheduledBackup $settings {$true}) 'waits for WoW'
    $r=Invoke-WtfScheduledBackup $settings {$false}
    Assert-True ($r -like 'WoW Forever: 8 files*') $r
    Assert-Equal 1 @(Get-WtfBackups (Get-WtfBackupDir 'WoW Forever' $base)).Count 'in the chosen folder'
    Assert-Equal 'nothing new' (Invoke-WtfScheduledBackup $settings {$false}) 'unchanged'
    [IO.File]::WriteAllText($settings,(@{paths=@{'WoW Forever'=(J @($g,'Interface','AddOns'))};backupFolder=$base;backgroundBackup=$false}|ConvertTo-Json))
    Assert-Equal 'turned off' (Invoke-WtfScheduledBackup $settings {$false}) 'off'
    Assert-Equal 'no settings' (Invoke-WtfScheduledBackup (Join-Path $script:case 'missing.json') {$false}) 'no settings file'
}

try{[IO.Directory]::Delete($sandbox,$true)}catch{}
Write-Host ([string]$script:passed+' passed, '+$script:failed.Count+' failed')
if($script:failed.Count -gt 0){exit 1}
