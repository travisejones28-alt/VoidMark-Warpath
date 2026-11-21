# VoidMark Warpath: automatic backups of WoW saved data (WTF SavedVariables).
# Read-only on the game folder except Restore-WtfBackup, which the player starts
# by hand with WoW closed and which always makes a safety backup first.
#
# What is saved, for every account on this PC (3.7.1: the whole setup, not only addon data):
#  - every SavedVariables\*.lua under WTF\Account (account-wide and per-character)
#  - macros, keybindings, chat settings, UI layout, enabled addons and settings
#    (the *-cache.wtf/txt, AddOns.txt and layout-local.txt files) and WTF\Config.wtf
# .bak/.old copies are skipped (WoW's own one-save-behind copies; our backups keep many).
# Where: %LOCALAPPDATA%\VoidMarkWarpath\WTF Backups\<game>\WTF-yyyyMMdd-HHmmss.zip
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$script:WtfBackupKeepRecent=20      # newest backups always kept
$script:WtfBackupKeepDays=30        # plus the newest backup of each of the last 30 days
$script:WtfBackupEveryHours=6       # automatic backup when Warpath opens, at most this often
$script:WtfShrinkMinBytes=100KB     # files this big that shrink a lot are flagged
$script:WtfShrinkRatio=0.5          # "a lot" = less than half the size of the last backup

function Get-WtfGameRoot([string]$AddOns) {
    # <game>\Interface\AddOns -> <game> when <game>\WTF\Account exists.
    $clean=([string]$AddOns).Trim().TrimEnd('\','/')
    if($clean -notmatch '(?i)(^|[\\/])Interface[\\/]AddOns$'){return $null}
    $root=Split-Path (Split-Path $clean -Parent) -Parent
    if(-not $root -or -not [IO.Directory]::Exists((Join-Path (Join-Path $root 'WTF') 'Account'))){return $null}
    $root
}
function Get-WtfBackupDir([string]$Game,[string]$Base='') {
    if(-not $Base){$Base=Join-Path (Join-Path $env:LOCALAPPDATA 'VoidMarkWarpath') 'WTF Backups'}
    $name=if($Game -eq 'WoW Classic Era'){'Classic Era'}else{'Forever'}
    Join-Path $Base $name
}
$script:WtfSetupFiles=@('macros-cache.txt','bindings-cache.wtf','chat-cache.txt','config-cache.wtf','AddOns.txt','layout-local.txt','cache.md5')
# The one rule for what a backup holds and a restore may write (relative to WTF, '/' separated).
function Test-WtfBackupPath([string]$Rel) {
    if(-not $Rel -or $Rel -match '(^|/)\.\.(/|$)' -or $Rel -match '^[/\\]' -or $Rel -match ':'){return $false}
    if($Rel -ieq 'Config.wtf'){return $true}
    if($Rel -notmatch '^Account/'){return $false}
    if($Rel -match '/SavedVariables/[^/]+\.lua$'){return $true}
    $leaf=$Rel.Substring($Rel.LastIndexOf('/')+1)
    foreach($n in $script:WtfSetupFiles){if($leaf -ieq $n -and $n -ne 'cache.md5'){return $true}}
    $false
}
function Get-WtfSavedFiles([string]$GameRoot) {
    $wtf=Join-Path $GameRoot 'WTF'
    $accounts=Join-Path $wtf 'Account'
    if(-not [IO.Directory]::Exists($accounts)){return @()}
    $prefix=$wtf.TrimEnd('\','/').Length+1
    $sep=[string][IO.Path]::DirectorySeparatorChar
    $all=@(Get-ChildItem -LiteralPath $accounts -Recurse -File -ErrorAction SilentlyContinue)
    $config=Join-Path $wtf 'Config.wtf'
    if([IO.File]::Exists($config)){$all+=Get-Item -LiteralPath $config}
    @($all | ForEach-Object {[pscustomobject]@{full=$_.FullName;rel=$_.FullName.Substring($prefix).Replace($sep,'/');size=$_.Length;at=$_.LastWriteTime}} |
        Where-Object {Test-WtfBackupPath $_.rel})
}
# Anything saved since the last backup? (Skips identical automatic backups.)
function Test-WtfChanged([string]$GameRoot,[string]$Dir) {
    $last=@(Get-WtfBackups $Dir)|Select-Object -First 1
    if(-not $last){return $true}
    $newest=@(Get-WtfSavedFiles $GameRoot)|Sort-Object at -Descending|Select-Object -First 1
    # Backup names have whole seconds: compare at that precision.
    $newest -and $newest.at.AddTicks(-($newest.at.Ticks % [TimeSpan]::TicksPerSecond)) -gt $last.at
}
function Read-WtfManifest([string]$Zip) {
    try {
        $z=[IO.Compression.ZipFile]::OpenRead($Zip)
        try {
            $e=$z.GetEntry('warpath-backup.json');if(-not $e){return $null}
            $r=New-Object IO.StreamReader($e.Open());try{$r.ReadToEnd()|ConvertFrom-Json}finally{$r.Dispose()}
        } finally {$z.Dispose()}
    } catch {$null}
}
function Get-WtfBackups([string]$Dir) {
    if(-not [IO.Directory]::Exists($Dir)){return @()}
    @(Get-ChildItem -LiteralPath $Dir -File -Filter 'WTF-*.zip' | ForEach-Object {
        $m=[regex]::Match($_.Name,'^WTF-(\d{8}-\d{6})')
        if($m.Success){
            [pscustomobject]@{path=$_.FullName;name=$_.Name;bytes=$_.Length;keep=($_.Name -match '-keep');
                at=[datetime]::ParseExact($m.Groups[1].Value,'yyyyMMdd-HHmmss',[Globalization.CultureInfo]::InvariantCulture)}
        }
    } | Sort-Object at -Descending)
}
function Test-WtfBackupDue([string]$Dir,[datetime]$Now,[double]$Hours=$script:WtfBackupEveryHours) {
    $last=@(Get-WtfBackups $Dir)|Select-Object -First 1
    (-not $last) -or (($Now-$last.at).TotalHours -ge $Hours)
}
function New-WtfBackup([string]$GameRoot,[string]$Dir,[string]$Reason='auto',[datetime]$Now=(Get-Date)) {
    # Returns @{ok;path;files;bytes;warnings;error}. Never changes anything in the game folder.
    $files=@(Get-WtfSavedFiles $GameRoot)
    if($files.Count -eq 0){return @{ok=$false;error='No saved data found in '+(Join-Path $GameRoot 'WTF')}}
    [IO.Directory]::CreateDirectory($Dir)|Out-Null
    $previous=@(Get-WtfBackups $Dir)|Select-Object -First 1
    $tmp=Join-Path $Dir ('.partial-'+[guid]::NewGuid().ToString('N')+'.zip')
    $copied=@{};$manifest=@()
    try {
        $fs=[IO.File]::Open($tmp,'CreateNew','ReadWrite','None')
        $zip=New-Object IO.Compression.ZipArchive($fs,[IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach($f in $files) {
                # WoW may be running: read without locking the file.
                try{$src=New-Object IO.FileStream($f.full,'Open','Read',([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))}catch{continue}
                try {
                    $entry=$zip.CreateEntry($f.rel,[IO.Compression.CompressionLevel]::Optimal)
                    $out=$entry.Open();try{$src.CopyTo($out)}finally{$out.Dispose()}
                    $copied[$f.rel]=$src.Length;$manifest+=@{path=$f.rel;size=$src.Length}
                } finally {$src.Dispose()}
            }
            $info=@{format=1;created=$Now.ToString('o');reason=$Reason;files=$manifest}
            $e=$zip.CreateEntry('warpath-backup.json');$w=New-Object IO.StreamWriter($e.Open())
            try{$w.Write((ConvertTo-Json -InputObject $info -Depth 4 -Compress))}finally{$w.Dispose()}
        } finally {$zip.Dispose();$fs.Dispose()}
        if($copied.Count -eq 0){throw 'Could not read any saved-data files'}
        # Verify before keeping it: every file is in the zip at the size that was read.
        $check=[IO.Compression.ZipFile]::OpenRead($tmp)
        try {foreach($rel in $copied.Keys){$e=$check.GetEntry($rel);if(-not $e -or $e.Length -ne $copied[$rel]){throw ('Backup check failed for '+$rel)}}}
        finally {$check.Dispose()}
        # Something big got much smaller or vanished since the last backup: never auto-delete that one.
        $warnings=@()
        if($previous) {
            $old=Read-WtfManifest $previous.path
            if($old) {
                foreach($p in @($old.files)) {
                    if([double]$p.size -lt $script:WtfShrinkMinBytes){continue}
                    $cur=$copied[[string]$p.path]   # (not $now: PowerShell names ignore case, $Now is the clock)
                    if($null -eq $cur){$warnings+=([string]$p.path+' is missing')}
                    elseif($cur -lt [double]$p.size*$script:WtfShrinkRatio){$warnings+=([string]$p.path+' shrank from '+[math]::Round($p.size/1KB)+' KB to '+[math]::Round($cur/1KB)+' KB')}
                }
            }
            if($warnings.Count -gt 0 -and -not $previous.keep) {
                $kept=Join-Path $Dir ([IO.Path]::GetFileNameWithoutExtension($previous.name)+'-keep.zip')
                try{[IO.File]::Move($previous.path,$kept)}catch{}
            }
        }
        $stamp=$Now.ToString('yyyyMMdd-HHmmss')
        $tag=if($Reason -and $Reason -ne 'auto'){'-'+($Reason -replace '[^A-Za-z0-9]','')}else{''}
        if($Reason -eq 'before-restore'){$tag+='-keep'}
        $final=Join-Path $Dir ('WTF-'+$stamp+$tag+'.zip');$n=1
        while([IO.File]::Exists($final)){$n++;$final=Join-Path $Dir ('WTF-'+$stamp+$tag+'-'+$n+'.zip')}
        [IO.File]::Move($tmp,$final)
        $bytes=0;foreach($v in $copied.Values){$bytes+=$v}
        @{ok=$true;path=$final;files=$copied.Count;bytes=$bytes;zipBytes=(New-Object IO.FileInfo $final).Length;warnings=$warnings}
    } catch {
        try{if([IO.File]::Exists($tmp)){[IO.File]::Delete($tmp)}}catch{}
        @{ok=$false;error=[string]$_}
    }
}
function Remove-OldWtfBackups([string]$Dir,[datetime]$Now=(Get-Date),[int]$KeepRecent=$script:WtfBackupKeepRecent,[int]$KeepDays=$script:WtfBackupKeepDays) {
    # Keeps: the newest $KeepRecent, the newest of each of the last $KeepDays days, and every "-keep" backup.
    $all=@(Get-WtfBackups $Dir);$keep=@{};$days=@{};$removed=0
    foreach($b in ($all|Select-Object -First $KeepRecent)){$keep[$b.path]=$true}
    foreach($b in $all) {
        if($b.keep){$keep[$b.path]=$true;continue}
        $day=$b.at.ToString('yyyyMMdd')
        if(($Now-$b.at).TotalDays -le $KeepDays -and -not $days[$day]){$days[$day]=$true;$keep[$b.path]=$true}
    }
    foreach($b in $all){if(-not $keep[$b.path]){try{[IO.File]::Delete($b.path);$removed++}catch{}}}
    # Leftovers from an interrupted backup.
    foreach($p in @(Get-ChildItem -LiteralPath $Dir -File -Filter '.partial-*.zip' -ErrorAction SilentlyContinue)){if(($Now-$p.LastWriteTime).TotalHours -gt 1){try{$p.Delete()}catch{}}}
    $removed
}
function Invoke-WtfBackups($Targets,[string]$Reason='auto',[bool]$OnlyIfDue=$true,[string]$Base='',[double]$DueHours=$script:WtfBackupEveryHours) {
    # Targets: @{game=;addOns=} list. One backup per game folder; used by the window's background job.
    $results=@()
    foreach($t in @($Targets)) {
        $root=Get-WtfGameRoot ([string]$t.addOns)
        if(-not $root){continue}
        $dir=Get-WtfBackupDir ([string]$t.game) $Base
        if($OnlyIfDue -and -not (Test-WtfBackupDue $dir (Get-Date) $DueHours)){continue}
        if($OnlyIfDue -and -not (Test-WtfChanged $root $dir)){continue}   # nothing new since the last one
        $r=New-WtfBackup $root $dir $Reason
        $r.game=[string]$t.game
        if($r.ok){try{[void](Remove-OldWtfBackups $dir)}catch{}}
        $results+=$r
    }
    $results
}
function Restore-WtfBackup([string]$Zip,[string]$GameRoot,[string]$Dir) {
    # WoW must be closed (checked by the window). A safety backup of the current
    # files is made first and kept. Only the files a backup may hold (see
    # Test-WtfBackupPath) are written, inside WTF; nothing is deleted.
    $safety=New-WtfBackup $GameRoot $Dir 'before-restore'
    if(-not $safety.ok -and $safety.error -notlike 'No saved data*'){return @{ok=$false;error='Safety backup failed: '+$safety.error}}
    $wtf=[IO.Path]::GetFullPath((Join-Path $GameRoot 'WTF'))
    $written=0
    $z=[IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        foreach($e in $z.Entries) {
            $rel=$e.FullName
            if($rel -eq 'warpath-backup.json' -or -not $rel){continue}
            if(-not (Test-WtfBackupPath $rel)){continue}
            $target=[IO.Path]::GetFullPath((Join-Path $wtf ($rel.Replace('/',[string][IO.Path]::DirectorySeparatorChar))))
            if(-not $target.StartsWith($wtf+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){continue}
            [IO.Directory]::CreateDirectory((Split-Path $target -Parent))|Out-Null
            $tmp=$target+'.warpath-restore'
            $in=$e.Open();try{$out=[IO.File]::Create($tmp);try{$in.CopyTo($out)}finally{$out.Dispose()}}finally{$in.Dispose()}
            if([IO.File]::Exists($target)){[IO.File]::Copy($tmp,$target,$true);[IO.File]::Delete($tmp)}else{[IO.File]::Move($tmp,$target)}
            $written++
        }
    } finally {$z.Dispose()}
    @{ok=$true;files=$written;safety=$safety.path}
}

# ---------------- Background backups (3.7.1) ----------------
# A Windows scheduled task (this Windows user, no admin) runs Launch-Warpath-Backup.vbs
# every hour. It starts, backs up only if WoW is closed and something was saved since the
# last backup, then exits. Nothing stays running in the background.
$script:WtfTaskName='VoidMark Warpath Backup'
function Read-WarpathSettingsFile([string]$Path='') {
    if(-not $Path){$Path=Join-Path (Join-Path $env:APPDATA 'VoidMarkWarpath') 'settings.json'}
    if(-not [IO.File]::Exists($Path)){return $null}
    try{[IO.File]::ReadAllText($Path)|ConvertFrom-Json}catch{$null}
}
function Get-WtfTargetsFromSettings($Cfg) {
    $t=@()
    if($Cfg -and $Cfg.paths){foreach($p in $Cfg.paths.PSObject.Properties){if([string]$p.Value){$t+=@{game=[string]$p.Name;addOns=[string]$p.Value}}}}
    $t
}
function Test-WowRunning {[bool](Get-Process -Name Wow,WowClassic,WowClassicT -ErrorAction SilentlyContinue)}
function Invoke-WtfScheduledBackup([string]$SettingsPath='',[scriptblock]$WowRunning={Test-WowRunning}) {
    # Entry point for the hourly task. Returns what it did (for the log and tests).
    $cfg=Read-WarpathSettingsFile $SettingsPath
    if(-not $cfg){return 'no settings'}
    if($cfg.PSObject.Properties['backgroundBackup'] -and -not [bool]$cfg.backgroundBackup){return 'turned off'}
    if(& $WowRunning){return 'WoW is running'}      # WoW writes saved data when it exits; wait for that
    $base=if($cfg.PSObject.Properties['backupFolder']){[string]$cfg.backupFolder}else{''}
    # Hourly: at most one backup per game per 30 minutes, and only when something changed.
    $r=@(Invoke-WtfBackups (Get-WtfTargetsFromSettings $cfg) 'auto' $true $base 0.5)
    if($r.Count -eq 0){return 'nothing new'}
    ($r|ForEach-Object {if($_.ok){$_.game+': '+$_.files+' files'}else{$_.game+': '+$_.error}}) -join '; '
}
function Set-WtfBackupTask([string]$AppRoot,[bool]$On,[scriptblock]$Run={param($exe,$a) Invoke-WarpathNative $exe $a}) {
    # Creates/replaces or removes the hourly task for the current Windows user.
    # schtasks runs through Invoke-WarpathNative: its "task not found" message must not crash Warpath.
    $vbs=Join-Path $AppRoot 'Launch-Warpath-Backup.vbs'
    $exe=Join-Path $env:WINDIR 'System32\schtasks.exe'
    if(-not [IO.File]::Exists($exe)){return $false}
    if(-not $On){[void](& $Run $exe @('/Delete','/TN',$script:WtfTaskName,'/F'));return $true}
    if(-not [IO.File]::Exists($vbs)){return $false}
    $tr='"'+(Join-Path $env:WINDIR 'System32\wscript.exe')+'" "'+$vbs+'"'
    $r=& $Run $exe @('/Create','/TN',$script:WtfTaskName,'/TR',$tr,'/SC','HOURLY','/MO','1','/F')
    if($r.code -ne 0){Write-WarpathLog ('Backup task create failed ('+$r.code+'): '+([string]$r.err).Trim())}
    $r.code -eq 0
}
function Test-WtfBackupTask([string]$AppRoot,[scriptblock]$Run={param($exe,$a) Invoke-WarpathNative $exe $a}) {
    # True when the task exists and points at this copy of Warpath. Missing task = $false, no error.
    $exe=Join-Path $env:WINDIR 'System32\schtasks.exe'
    if(-not [IO.File]::Exists($exe)){return $false}
    $r=& $Run $exe @('/Query','/TN',$script:WtfTaskName,'/XML')
    if($r.code -ne 0 -or -not $r.out){return $false}
    $xml=([string]$r.out) -replace "`0",''   # in case the XML arrives as UTF-16
    $vbs=Join-Path $AppRoot 'Launch-Warpath-Backup.vbs'
    foreach($want in @($vbs,[Security.SecurityElement]::Escape($vbs))){if($xml.IndexOf($want,[StringComparison]::OrdinalIgnoreCase) -ge 0){return $true}}
    $false
}
