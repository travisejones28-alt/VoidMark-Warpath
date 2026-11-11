# Windows PowerShell 5.1. Shared catalog, safe filesystem operations and worker.
Set-StrictMode -Version 2
$script:WarpathOwner = 'travisejones28-alt'
$script:WarpathAppRepo = 'VoidMark-Warpath'
$script:WarpathRawBase = 'https://raw.githubusercontent.com/travisejones28-alt/VoidMark-Warpath/main/'
# Files a friend's copy needs. Owner-only files are refreshed only if already present.
$script:WarpathAppFiles = @('VoidMarkWarpath.ps1','Warpath.Core.ps1','Warpath.Theme.ps1','Warpath.UI.cs','Launch-VoidMark-Warpath.vbs','README.md','version.txt')
$script:WarpathOwnerFiles = @('Owner-Catalog-Editor.ps1','Warpath.Editor.ps1','Launch-Owner-Editor.vbs')
function Get-WarpathEntries {
    @(
        @{game='WoW Forever';name='VoidMark Forever';repo='VoidMark-Forever';addon='VoidMarkForever';description='Your world PvP tools and history.'},
        @{game='WoW Forever';name='VoidMark Market';repo='VoidMark-Market';addon='VoidMarkMarket';description='Auction prices, shopping and selling.'},
        @{game='WoW Forever';name='VoidMark Nexus';repo='VoidMark-Nexus';addon='VoidMarkNexus';description='Gathering nodes, professions and routes.'},
        @{game='WoW Forever';name='VoidMark Mini-Map';repo='VoidMark-Mini-Map';addon='VoidMarkMiniMap';description='A cleaner map for your adventures.'},
        @{game='WoW Forever';name='VoidMark Debug';repo='VoidMark-Debug';addon='VoidMarkDebug';description='Keep addon errors in one place.'},
        @{game='WoW Classic Era';name='VoidMark';repo='VoidMark';addon='VoidMark';description='Your world PvP tools and history.'},
        @{game='WoW Classic Era';name='VoidMark Clapback';repo='VoidMark-Clapback';addon='VoidMarkClapback';description='A little personality for your PvP wins.'},
        @{game='WoW Classic Era';name='VoidLink';repo='VoidLink';addon='VoidLink';description='Your cross-faction communication relay.'}
    )
}
function Write-WarpathLog([string]$Message) {
    try {
        $dir=Join-Path $env:APPDATA 'VoidMarkWarpath'
        [IO.Directory]::CreateDirectory($dir) | Out-Null
        [IO.File]::AppendAllText((Join-Path $dir 'warpath.log'), ((Get-Date).ToString('o')+' '+$Message+[Environment]::NewLine))
    } catch { }
}
function Get-PublicCatalog([string]$Path) {
    try {
        if(-not [IO.File]::Exists($Path)){return}
        ConvertFrom-PublicCatalog ([IO.File]::ReadAllText($Path))
    } catch {Write-WarpathLog ('Catalog refused: '+$_); return}
}
function ConvertFrom-PublicCatalog([string]$Raw) {
    # Fail closed: anything unexpected shares nothing. Only known game/repo pairs pass.
    try {
        $raw=$Raw.TrimStart([char]0xFEFF)
        if(-not $raw.TrimStart().StartsWith('[')){throw 'Catalog must be an array.'}
        $items=@($raw | ConvertFrom-Json)
        foreach($a in @(Get-WarpathEntries)) {
            if(@($items | Where-Object {$_ -and $_.game -eq $a.game -and $_.repo -eq $a.repo}).Count -gt 0) {
                @{game=$a.game;repo=$a.repo}
            }
        }
    } catch {Write-WarpathLog ('Catalog refused: '+$_); return}
}
function Test-PublicEntry($Entry,$Catalog) {
    @($Catalog | Where-Object {$_.game -eq $Entry.game -and $_.repo -eq $Entry.repo}).Count -gt 0
}
function Get-AddonFolder($Entry) {
    if($Entry.addon){[string]$Entry.addon}else{[string]$Entry.repo}
}
function Test-LinkedPath([string]$Path) {
    if(-not (Test-Path -LiteralPath $Path)){return $false}
    ((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
}
function Get-RecordPath([string]$Destination,[string]$Repo) {
    Join-Path (Join-Path $Destination '.VoidMarkWarpath') ($Repo+'.json')
}
function Assert-SafePath([string]$Path,[switch]$Tree) {
    if([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path)){throw 'VMW_FOLDER'}
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    # A throwaway folder is allowed; an existing WoW data tree never is.
    if(@(($full -split '[\\/]') | Where-Object {$_.TrimEnd(' ','.') -in @('WTF','SavedVariables')}).Count){throw 'VMW_PROTECTED'}
    if($full -eq [IO.Path]::GetPathRoot($full).TrimEnd('\')){throw 'VMW_FOLDER'}
    $cursor=$full
    while($cursor) {
        if(Test-Path -LiteralPath $cursor) {
            $item=Get-Item -LiteralPath $cursor -Force
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'VMW_LINK'}
        }
        $parent=Split-Path -Path $cursor -Parent
        if($parent -eq $cursor){break}; $cursor=$parent
    }
    if($Tree -and (Test-Path -LiteralPath $full)) {
        # Walk explicitly: do not recurse into a junction while checking for one.
        $pending=New-Object 'Collections.Generic.Stack[string]';$pending.Push($full)
        while($pending.Count -gt 0) {
            foreach($item in @(Get-ChildItem -LiteralPath $pending.Pop() -Force)) {
                if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'VMW_LINK'}
                if($item.Name -in @('WTF','SavedVariables')){throw 'VMW_PROTECTED'}
                if($item.PSIsContainer){$pending.Push($item.FullName)}
            }
        }
    }
}
function Assert-ChildPath([string]$Parent,[string]$Child) {
    $prefix=[IO.Path]::GetFullPath($Parent).TrimEnd('\')+'\'
    if(-not [IO.Path]::GetFullPath($Child).StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'VMW_FOLDER'}
    Assert-SafePath $Child
}
function Remove-SafeStage([string]$Parent,[string]$Stage) {
    Assert-ChildPath $Parent $Stage
    if((Split-Path $Stage -Leaf) -notlike 'stage-*'){throw 'VMW_FOLDER'}
    if(Test-Path -LiteralPath $Stage){Assert-SafePath $Stage -Tree;Remove-Item -LiteralPath $Stage -Recurse -Force}
}
function Get-InstallState([string]$Destination,$Entry,[string]$RemoteSha) {
    $installed=$false;$sha=''
    try {
        if($Destination) {
            Assert-SafePath $Destination
            $target=Join-Path $Destination (Get-AddonFolder $Entry)
            # Developer junction/symlink: report it and leave it alone.
            if(Test-LinkedPath $target){return @{installed=$true;sha='';needs=$false;verified=$true;linked=$true}}
            Assert-SafePath $target -Tree
            $installed=[IO.Directory]::Exists($target)
            $record=Get-RecordPath $Destination $Entry.repo;Assert-SafePath $record
            if([IO.File]::Exists($record)){$sha=[string](([IO.File]::ReadAllText($record)|ConvertFrom-Json).sha)}
        }
    } catch {Write-WarpathLog ('State: '+$_)}
    $needs=(-not $installed) -or (-not $sha) -or ($RemoteSha -and $sha -ne $RemoteSha)
    @{installed=$installed;sha=$sha;needs=[bool]$needs;verified=[bool]($RemoteSha -and $sha -eq $RemoteSha -and $installed);linked=$false}
}
function Get-FriendlyError($ErrorRecord) {
    $e=$ErrorRecord.Exception; $detail=$ErrorRecord.ToString()
    while($e.InnerException){$e=$e.InnerException}
    switch -Regex ($detail+' '+$e.Message) {
        'VMW_LINK' {return "This folder uses a shortcut link. Pick a regular folder and try again."}
        'VMW_PROTECTED' {return 'That folder contains WoW settings. Choose your Interface\AddOns folder instead.'}
        'VMW_FOLDER' {return 'Choose a full AddOns folder path with Browse, then try again.'}
        'VMW_ARCHIVE' {return "This download isn't a valid WoW addon. Please tell the owner."}
        'VMW_CHANGED' {return 'An addon changed during download. Click again to get the newest copy.'}
        'VMW_ROLLBACK' {return "Couldn't finish restoring the old addon. Your backup is safe; see the owner for help."}
    }
    if($e -is [UnauthorizedAccessException]){return "Windows won't let us write there. Choose a folder you can edit, then try again."}
    if($e -is [Net.WebException]) {
        if($e.Response -and [int]$e.Response.StatusCode -eq 403){return 'GitHub is limiting checks right now. Wait a little and try again.'}
        if($e.Response -and [int]$e.Response.StatusCode -eq 404){return "Couldn't find that addon on GitHub. Please tell the owner."}
        return "Couldn't reach GitHub — check your internet and try again."
    }
    return "Couldn't finish. Check that the folder is available and has enough free space, then try again."
}
function Get-WarpathText([string]$Url) {
    $r=Invoke-WebRequest -Uri $Url -UseBasicParsing -Headers @{'User-Agent'='VoidMark-Warpath';'Cache-Control'='no-cache'} -TimeoutSec 20
    if($r.Content -is [byte[]]){[Text.Encoding]::UTF8.GetString($r.Content)}else{[string]$r.Content}
}
function ConvertTo-WarpathVersion([string]$Text) {
    $v=$null;$clean=([string]$Text).Trim().TrimStart('v','V')
    if([version]::TryParse($clean,[ref]$v)){$v}else{[version]'0.0'}
}
function Get-LocalAppVersion([string]$Root) {
    $f=Join-Path $Root 'version.txt'
    if([IO.File]::Exists($f)){([IO.File]::ReadAllText($f)).Trim()}else{'0.0.0'}
}
function Get-RemoteSha([string]$Repo) {
    $sha=[string](Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$script:WarpathOwner+'/'+$Repo+'/commits/main') -Headers @{'User-Agent'='VoidMark-Warpath'} -TimeoutSec 30).sha
    if($sha -notmatch '^[a-fA-F0-9]{40}$'){throw 'VMW_ARCHIVE'}
    $sha
}
function Send-WorkerEvent($Queue,[string]$Type,$Data) {
    $Queue.Enqueue(@{type=$Type;data=$Data})
}
function Get-WarpathZip([string]$Url,[string]$File,[string]$Name,$Queue,[int]$Index,[int]$Count) {
    $request=[Net.HttpWebRequest]::Create($Url);$request.UserAgent='VoidMark-Warpath'
    $request.Timeout=30000;$request.ReadWriteTimeout=30000
    $response=$null;$inputStream=$null;$outputStream=$null
    try {
        $response=$request.GetResponse();$total=[long]$response.ContentLength
        $inputStream=$response.GetResponseStream();$outputStream=[IO.File]::Create($File)
        $buffer=New-Object byte[] 65536;$received=[long]0;$clock=[Diagnostics.Stopwatch]::StartNew();$last=-1000
        while(($n=$inputStream.Read($buffer,0,$buffer.Length)) -gt 0) {
            $outputStream.Write($buffer,0,$n);$received+=$n
            if($clock.ElapsedMilliseconds-$last -ge 100) {
                $last=$clock.ElapsedMilliseconds
                $fraction=if($total -gt 0){[math]::Min(0.9,0.9*$received/$total)}else{0.4}
                $percent=[int](100*($Index+$fraction)/$Count)
                $text='{0}: {1:N1} MB • {2:N1} MB/s' -f $Name,($received/1MB),(($received/1MB)/[math]::Max(.1,$clock.Elapsed.TotalSeconds))
                Send-WorkerEvent $Queue progress @{percent=$percent;text=$text}
            }
        }
        if($total -ge 0 -and $received -ne $total){throw 'VMW_ARCHIVE'}
    } finally {
        if($outputStream){$outputStream.Dispose()};if($inputStream){$inputStream.Dispose()};if($response){$response.Close()}
    }
}
function Expand-SafeArchive([string]$Zip,[string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive=[IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        $roots=@{}
        foreach($entry in $archive.Entries) {
            $relative=$entry.FullName.Replace('/','\')
            $parts=@($relative.Split('\') | Where-Object {$_ -ne ''})
            if($parts.Count -eq 0){continue}
            if($relative.StartsWith('\') -or $relative.Contains(':') -or @($parts | Where-Object {$_ -in @('.','..') -or $_.TrimEnd(' ','.') -in @('WTF','SavedVariables')}).Count){throw 'VMW_ARCHIVE'}
            # Reject Unix symlink entries and Windows reparse attributes.
            $attr=[long]$entry.ExternalAttributes
            if((($attr -shr 16) -band 61440) -eq 40960 -or ($attr -band 1024) -ne 0){throw 'VMW_LINK'}
            $roots[$parts[0]]=$true
            $target=Join-Path $Destination $relative;Assert-ChildPath $Destination $target
        }
        if($roots.Count -ne 1){throw 'VMW_ARCHIVE'}
        [IO.Directory]::CreateDirectory($Destination)|Out-Null
        foreach($entry in $archive.Entries) {
            $target=Join-Path $Destination ($entry.FullName.Replace('/','\'))
            if($entry.FullName.EndsWith('/')){[IO.Directory]::CreateDirectory($target)|Out-Null;continue}
            [IO.Directory]::CreateDirectory((Split-Path $target -Parent))|Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$false)
        }
    } finally {$archive.Dispose()}
    $top=@(Get-ChildItem -LiteralPath $Destination -Directory)
    if($top.Count -ne 1){throw 'VMW_ARCHIVE'}
    $top[0]
}
function Expand-SafeAddon([string]$Zip,[string]$Destination,[string]$Addon) {
    $top=@(Expand-SafeArchive $Zip $Destination)
    $tocName=$Addon+'.toc'
    # GitHub names the top folder <repo>-main, so the top folder only needs the .toc.
    # Deeper folders (e.g. Clapback's VoidMarkClapback\) must also be named after the addon.
    $found=$null
    if([IO.File]::Exists((Join-Path $top[0].FullName $tocName))){$found=$top[0].FullName}
    else {
        $level=@($top[0])
        for($depth=1;$depth -le 2 -and -not $found;$depth++) {
            $level=@($level | ForEach-Object {Get-ChildItem -LiteralPath $_.FullName -Directory})
            $match=@($level | Where-Object {$_.Name -eq $Addon -and [IO.File]::Exists((Join-Path $_.FullName $tocName))})
            if($match.Count -ge 1){$found=$match[0].FullName}
        }
    }
    if(-not $found){throw 'VMW_ARCHIVE'}
    Assert-SafePath $found -Tree
    $found
}
function Install-WarpathEntry([string]$Destination,$Entry,$Queue,[int]$Index,[int]$Count) {
    $known=@(Get-WarpathEntries | Where-Object {$_.game -eq $Entry.game -and $_.repo -eq $Entry.repo})
    if($known.Count -ne 1){throw 'VMW_ARCHIVE'}
    Assert-SafePath $Destination
    [IO.Directory]::CreateDirectory($Destination)|Out-Null
    $root=Join-Path $Destination '.VoidMarkWarpath';Assert-SafePath $root
    [IO.Directory]::CreateDirectory($root)|Out-Null
    $addon=Get-AddonFolder $Entry
    $target=Join-Path $Destination $addon
    if(Test-LinkedPath $target) {
        Send-WorkerEvent $Queue progress @{percent=[int](100*($Index+1)/$Count);text=($Entry.name+' is a linked dev folder; skipped.')}
        return
    }
    Assert-SafePath $target -Tree
    $record=Get-RecordPath $Destination $Entry.repo;Assert-SafePath $record
    $stage=Join-Path $root ('stage-'+[guid]::NewGuid().ToString('N'))
    Assert-ChildPath $root $stage;[IO.Directory]::CreateDirectory($stage)|Out-Null
    $backup=$null;$movedOld=$false;$movedNew=$false
    try {
        $sha=Get-RemoteSha $Entry.repo
        $zip=Join-Path $stage 'source.zip'
        Get-WarpathZip ('https://github.com/'+$script:WarpathOwner+'/'+$Entry.repo+'/archive/refs/heads/main.zip') $zip $Entry.name $Queue $Index $Count
        $source=Expand-SafeAddon $zip (Join-Path $stage 'unpacked') $addon
        # main.zip must still correspond to the tracked commit.
        if((Get-RemoteSha $Entry.repo) -ne $sha){throw 'VMW_CHANGED'}
        $newRecord=Join-Path $stage 'record.json'
        @{sha=$sha;repo=$Entry.repo;installedAt=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath $newRecord -Encoding UTF8
        Assert-SafePath $Destination;Assert-SafePath $root;Assert-SafePath $target -Tree;Assert-SafePath $record
        if(Test-Path -LiteralPath $target) {
            $backup=Join-Path $root ('backup-'+$Entry.repo+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N'))
            Assert-ChildPath $root $backup
            Move-Item -LiteralPath $target -Destination $backup;$movedOld=$true
        }
        try {
            Move-Item -LiteralPath $source -Destination $target;$movedNew=$true
            if([IO.File]::Exists($record)){[IO.File]::Replace($newRecord,$record,[NullString]::Value)}else{[IO.File]::Move($newRecord,$record)}
        } catch {
            $original=$_
            try {
                if($movedNew){Assert-SafePath $target -Tree;Move-Item -LiteralPath $target -Destination (Join-Path $stage 'failed-new')}
                if($movedOld){Assert-SafePath $backup -Tree;Move-Item -LiteralPath $backup -Destination $target}
            } catch {Write-WarpathLog ('Rollback: '+$_);throw 'VMW_ROLLBACK'}
            throw $original
        }
        # One-time cleanup: earlier Warpath builds installed into a folder named after the repo.
        if($addon -ne $Entry.repo) {
            $legacy=Join-Path $Destination $Entry.repo
            try {
                if([IO.Directory]::Exists($legacy) -and -not (Test-LinkedPath $legacy)) {
                    Assert-SafePath $legacy -Tree
                    $legacyBackup=Join-Path $root ('backup-'+$Entry.repo+'-oldname-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N'))
                    Assert-ChildPath $root $legacyBackup
                    Move-Item -LiteralPath $legacy -Destination $legacyBackup
                }
            } catch {Write-WarpathLog ('Old-name cleanup: '+$_)}
        }
        Send-WorkerEvent $Queue installed @{repo=$Entry.repo;sha=$sha}
        Send-WorkerEvent $Queue progress @{percent=[int](100*($Index+1)/$Count);text=($Entry.name+' is ready.')}
    } finally {
        try {Remove-SafeStage $root $stage}catch{Write-WarpathLog ('Stage cleanup: '+$_)}
    }
}
function Update-WarpathApp([string]$Root,[string]$Expected,$Queue) {
    # Download the updater repo, verify it, back up the current app files, then copy over.
    $local=Join-Path $env:LOCALAPPDATA 'VoidMarkWarpath';[IO.Directory]::CreateDirectory($local)|Out-Null
    Assert-SafePath $Root
    $stage=Join-Path $local ('stage-app-'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($stage)|Out-Null
    try {
        $zip=Join-Path $stage 'app.zip'
        Get-WarpathZip ('https://github.com/'+$script:WarpathOwner+'/'+$script:WarpathAppRepo+'/archive/refs/heads/main.zip') $zip 'VoidMark Warpath' $Queue 0 1
        $source=(Expand-SafeArchive $zip (Join-Path $stage 'unpacked')).FullName
        foreach($name in $script:WarpathAppFiles){if(-not [IO.File]::Exists((Join-Path $source $name))){throw 'VMW_ARCHIVE'}}
        $got=([IO.File]::ReadAllText((Join-Path $source 'version.txt'))).Trim()
        if($Expected -and (ConvertTo-WarpathVersion $got) -lt (ConvertTo-WarpathVersion $Expected)){throw 'VMW_CHANGED'}
        # Take the file list from the download so future versions can add files.
        $files=@(Get-ChildItem -LiteralPath $source -File | Where-Object {$_.Extension -in @('.ps1','.cs','.vbs','.md','.txt') -and $_.Name -ne 'report-hook.txt'} |
            ForEach-Object {$_.Name} | Where-Object {($script:WarpathOwnerFiles -notcontains $_) -or [IO.File]::Exists((Join-Path $Root $_))})
        $assetSource=Join-Path $source 'assets'
        if([IO.Directory]::Exists($assetSource)){$files+=@(Get-ChildItem -LiteralPath $assetSource -File | ForEach-Object {'assets\'+$_.Name})}
        $backup=Join-Path $local ('app-backup-'+(Get-LocalAppVersion $Root)+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
        [IO.Directory]::CreateDirectory((Join-Path $backup 'assets'))|Out-Null
        foreach($name in $files){$cur=Join-Path $Root $name;if([IO.File]::Exists($cur)){Copy-Item -LiteralPath $cur -Destination (Join-Path $backup $name) -Force}}
        Send-WorkerEvent $Queue progress @{percent=95;text='Installing the new Warpath…'}
        $done=@()
        try {
            [IO.Directory]::CreateDirectory((Join-Path $Root 'assets'))|Out-Null
            foreach($name in $files) {
                $dest=Join-Path $Root $name;Assert-SafePath $dest
                [IO.File]::Copy((Join-Path $source $name),$dest,$true);$done+=$name
            }
        } catch {
            $original=$_
            foreach($name in $done){$b=Join-Path $backup $name;if([IO.File]::Exists($b)){try{[IO.File]::Copy($b,(Join-Path $Root $name),$true)}catch{Write-WarpathLog ('App rollback: '+$_)}}}
            throw $original
        }
        Send-WorkerEvent $Queue progress @{percent=100;text=('Warpath '+$got+' installed. Restarting…')}
    } finally {try{Remove-SafeStage $local $stage}catch{Write-WarpathLog ('App stage cleanup: '+$_)}}
}
function Invoke-WarpathWorker([string]$Action,$Entries,[string]$Destination,$Queue,[bool]$Owner=$false,$Catalog=@(),[string]$Root='',[string]$Expected='') {
    $ErrorActionPreference='Stop';[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    if($Action -eq 'selfupdate') {
        try {Update-WarpathApp $Root $Expected $Queue;Send-WorkerEvent $Queue complete @{action=$Action;success=$true}}
        catch {Write-WarpathLog ($_ | Out-String);Send-WorkerEvent $Queue error (Get-FriendlyError $_);Send-WorkerEvent $Queue complete @{action=$Action;success=$false}}
        return
    }
    if($Action -eq 'check') {
        $failed=$false;$i=0
        # Live addon list and app version from GitHub. Failures fall back to what we already have.
        try {
            $live=@(ConvertFrom-PublicCatalog (Get-WarpathText ($script:WarpathRawBase+'public-catalog.json')))
            Send-WorkerEvent $Queue catalog @{items=$live};$Catalog=$live
        } catch {Write-WarpathLog ('Live catalog: '+$_)}
        try {Send-WorkerEvent $Queue appversion @{version=(Get-WarpathText ($script:WarpathRawBase+'version.txt')).Trim()}}
        catch {Write-WarpathLog ('App version: '+$_)}
        if(-not $Owner){$Entries=@($Entries | Where-Object {Test-PublicEntry $_ $Catalog})}
        foreach($entry in $Entries) {
            Send-WorkerEvent $Queue progress @{percent=[int](100*$i/[math]::Max(1,$Entries.Count));text=('Checking '+$entry.name+'…')}
            try {Send-WorkerEvent $Queue remote @{repo=$entry.repo;sha=(Get-RemoteSha $entry.repo)}}
            catch {$failed=$true;Write-WarpathLog ($_ | Out-String);Send-WorkerEvent $Queue error (Get-FriendlyError $_)}
            $i++
        }
        Send-WorkerEvent $Queue complete @{action=$Action;success=(-not $failed)}
    } else {
        try {
            for($i=0;$i -lt $Entries.Count;$i++){Install-WarpathEntry $Destination $Entries[$i] $Queue $i $Entries.Count}
            Send-WorkerEvent $Queue complete @{action=$Action;success=$true}
        } catch {
            Write-WarpathLog ($_ | Out-String);Send-WorkerEvent $Queue error (Get-FriendlyError $_)
            Send-WorkerEvent $Queue complete @{action=$Action;success=$false}
        }
    }
}

# ---------------- Problem reports (Discord) ----------------
# The webhook is NOT in the repo. It lives in report-hook.txt beside the app (gitignored),
# set by the owner editor and shipped inside the friends ZIP.
function Get-WarpathReportUrl([string]$Root) {
    $f=Join-Path $Root 'report-hook.txt'
    if(-not [IO.File]::Exists($f)){return ''}
    $u=([IO.File]::ReadAllText($f)).Trim()
    if($u -match '^https://(discord\.com|discordapp\.com)/api/webhooks/\d+/[\w-]+$'){$u}else{''}
}
function Find-DebugSavedFiles([string]$AddOns,[string]$Game) {
    # Read-only: locate WTF\Account\*\SavedVariables\VoidMarkDebug.lua for this game.
    $roots=@()
    $clean=([string]$AddOns).Trim().TrimEnd('\','/')
    if($clean -match '(?i)[\\/]Interface[\\/]AddOns$'){$roots+=(Split-Path (Split-Path $clean -Parent) -Parent)}
    $client=if($Game -eq 'WoW Classic Era'){'_classic_era_'}else{'_forever_'}
    foreach($base in @(${env:ProgramFiles(x86)},$env:ProgramFiles)){if($base){$roots+=(Join-Path $base ('World of Warcraft\'+$client))}}
    $found=@();$seen=@{}
    foreach($root in $roots) {
        $accounts=Join-Path $root 'WTF\Account'
        if(-not [IO.Directory]::Exists($accounts)){continue}
        foreach($acct in @(Get-ChildItem -LiteralPath $accounts -Directory -ErrorAction SilentlyContinue)) {
            $file=Join-Path (Join-Path $acct.FullName 'SavedVariables') 'VoidMarkDebug.lua'
            $key=$file.ToLowerInvariant()
            if([IO.File]::Exists($file) -and -not $seen[$key]){$seen[$key]=$true;$found+=$file}
        }
    }
    $found
}
function Get-VoidMarkErrors([string[]]$Files) {
    # VoidMark/VoidLink error groups only. Account folder names become "Account N".
    $out=@();$n=0
    foreach($file in @($Files)) {
        $n++
        try {
            $g=[Warpath.LuaReader]::ReadGlobals([IO.File]::ReadAllText($file))
            $db=$g['VoidMarkDebugDB'];if(-not $db -or -not $db['entries']){continue}
            foreach($e in @($db['entries'])) {
                if($e -isnot [Collections.IDictionary]){continue}
                $addon=[string]$e['addon'];$msg=[string]$e['message']
                if(($addon -notmatch '^(VoidMark|VoidLink)') -and ($msg -notmatch 'VoidMark|VoidLink')){continue}
                $out+=[pscustomobject]@{account=('Account '+$n);addon=$addon;message=$msg;count=[int]([double]$e['count']);
                    last=[string]$e['last'];character=[string]$e['character'];key=('A'+$n+'|'+[string]$e['key'])}
            }
        } catch {Write-WarpathLog ('Read Debug errors: '+$_)}
    }
    @($out | Sort-Object last -Descending)
}
function Get-ReportedMap {
    $path=Join-Path (Join-Path $env:APPDATA 'VoidMarkWarpath') 'reported.json';$sent=@{}
    try{if([IO.File]::Exists($path)){$j=[IO.File]::ReadAllText($path)|ConvertFrom-Json;foreach($p in $j.PSObject.Properties){$sent[$p.Name]=[int]$p.Value}}}catch{}
    $sent
}
function Get-NewVoidMarkErrors($Errors) {
    $sent=Get-ReportedMap
    @(@($Errors) | Where-Object {-not $sent.ContainsKey($_.key) -or $_.count -gt $sent[$_.key]})
}
function Save-ReportedErrors($Errors) {
    $dir=Join-Path $env:APPDATA 'VoidMarkWarpath';$sent=Get-ReportedMap
    foreach($e in @($Errors)){$sent[$e.key]=$e.count}
    try{[IO.Directory]::CreateDirectory($dir)|Out-Null;[IO.File]::WriteAllText((Join-Path $dir 'reported.json'),($sent|ConvertTo-Json))}catch{Write-WarpathLog ('Save reported: '+$_)}
}
function Get-InstalledSummary([string]$AddOns,[string]$Game) {
    $lines=@()
    foreach($a in @(Get-WarpathEntries | Where-Object {$_.game -eq $Game})) {
        if(-not $AddOns){break}
        $name=Get-AddonFolder $a;$folder=Join-Path $AddOns $name;if(-not [IO.Directory]::Exists($folder)){continue}
        $ver='?';$toc=Join-Path $folder ($name+'.toc')
        try{if([IO.File]::Exists($toc)){$m=[regex]::Match([IO.File]::ReadAllText($toc),'(?m)^##\s*Version:\s*(.+)$');if($m.Success){$ver=$m.Groups[1].Value.Trim()}}}catch{}
        $sha='';try{$r=Get-RecordPath $AddOns $a.repo;if([IO.File]::Exists($r)){$sha=[string](([IO.File]::ReadAllText($r)|ConvertFrom-Json).sha)}}catch{}
        $tag=if(Test-LinkedPath $folder){' (linked dev)'}elseif($sha){' ('+$sha.Substring(0,[Math]::Min(7,$sha.Length))+')'}else{''}
        $lines+=('  '+$name+' '+$ver+$tag)
    }
    if($lines.Count){$lines}else{@('  (none found in this folder)')}
}
function New-WarpathReportText([string]$Problem,[string]$Contact,[string]$Game,[string]$AddOns,[string]$AppVersion,$Errors) {
    $t=New-Object Text.StringBuilder
    [void]$t.AppendLine('VoidMark problem report')
    [void]$t.AppendLine('Sent: '+(Get-Date).ToString('yyyy-MM-dd HH:mm')+' | Warpath v'+$AppVersion+' | '+$Game)
    [void]$t.AppendLine('Contact: '+$(if($Contact){$Contact}else{'(not given)'}))
    [void]$t.AppendLine('');[void]$t.AppendLine('What happened:');[void]$t.AppendLine($(if($Problem){$Problem}else{'(no description)'}))
    [void]$t.AppendLine('');[void]$t.AppendLine('Installed:')
    foreach($l in @(Get-InstalledSummary $AddOns $Game)){[void]$t.AppendLine($l)}
    [void]$t.AppendLine('');[void]$t.AppendLine('VoidMark errors attached: '+@($Errors).Count)
    $i=0
    foreach($e in @($Errors)) {
        $i++;[void]$t.AppendLine('-----')
        [void]$t.AppendLine(('[{0}] {1} | x{2} | last {3} | {4} | {5}' -f $i,$e.addon,$e.count,$e.last,$e.character,$e.account))
        [void]$t.AppendLine($e.message)
    }
    $text=$t.ToString();if($text.Length -gt 200000){$text=$text.Substring(0,200000)+"`n(truncated)"};$text
}
function Send-WarpathReport([string]$Url,[string]$Summary,[string]$Text) {
    Add-Type -AssemblyName System.Net.Http
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    if($Summary.Length -gt 1900){$Summary=$Summary.Substring(0,1900)+'…'}
    $payload=@{username='VoidMark Reports';content=$Summary;allowed_mentions=@{parse=@()}}|ConvertTo-Json -Depth 4 -Compress
    $client=New-Object Net.Http.HttpClient;$client.Timeout=[TimeSpan]::FromSeconds(30)
    $body=New-Object Net.Http.MultipartFormDataContent
    try {
        $body.Add((New-Object Net.Http.StringContent($payload,[Text.Encoding]::UTF8,'application/json')),'payload_json')
        $file=New-Object Net.Http.ByteArrayContent(,[Text.Encoding]::UTF8.GetBytes($Text))
        $file.Headers.ContentType=[Net.Http.Headers.MediaTypeHeaderValue]::Parse('text/plain')
        $body.Add($file,'files[0]','voidmark-report.txt')
        $resp=$client.PostAsync($Url,$body).GetAwaiter().GetResult()
        if(-not $resp.IsSuccessStatusCode){throw ('VMW_REPORT '+[int]$resp.StatusCode)}
    } finally {$body.Dispose();$client.Dispose()}
}
