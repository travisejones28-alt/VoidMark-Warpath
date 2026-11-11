# Windows PowerShell 5.1. Shared catalog, safe filesystem operations and worker.
Set-StrictMode -Version 2
$script:WarpathOwner = 'travisejones28-alt'
function Get-WarpathEntries {
    @(
        @{game='WoW Forever';name='VoidMark Forever';repo='VoidMark-Forever';description='Your world PvP tools and history.'},
        @{game='WoW Forever';name='VoidMark Market';repo='VoidMark-Market';description='Auction prices, shopping and selling.'},
        @{game='WoW Forever';name='VoidMark Nexus';repo='VoidMark-Nexus';description='Gathering nodes, professions and routes.'},
        @{game='WoW Forever';name='VoidMark Mini-Map';repo='VoidMark-Mini-Map';description='A cleaner map for your adventures.'},
        @{game='WoW Forever';name='VoidMark Debug';repo='VoidMark-Debug';description='Keep addon errors in one place.'},
        @{game='WoW Classic Era';name='VoidMark';repo='VoidMark';description='Your world PvP tools and history.'},
        @{game='WoW Classic Era';name='VoidMark Clapback';repo='VoidMark-Clapback';description='A little personality for your PvP wins.'},
        @{game='WoW Classic Era';name='VoidLink';repo='VoidLink';description='Your cross-faction communication relay.'}
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
        $raw=[IO.File]::ReadAllText($Path)
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
            $target=Join-Path $Destination $Entry.repo;Assert-SafePath $target -Tree
            $installed=[IO.Directory]::Exists($target)
            $record=Get-RecordPath $Destination $Entry.repo;Assert-SafePath $record
            if([IO.File]::Exists($record)){$sha=[string](([IO.File]::ReadAllText($record)|ConvertFrom-Json).sha)}
        }
    } catch {Write-WarpathLog ('State: '+$_)}
    $needs=(-not $installed) -or (-not $sha) -or ($RemoteSha -and $sha -ne $RemoteSha)
    @{installed=$installed;sha=$sha;needs=[bool]$needs;verified=[bool]($RemoteSha -and $sha -eq $RemoteSha -and $installed)}
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
function Expand-SafeAddon([string]$Zip,[string]$Destination) {
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
    $source=@(Get-ChildItem -LiteralPath $Destination -Directory)
    if($source.Count -ne 1 -or @(Get-ChildItem -LiteralPath $source[0].FullName -File -Filter '*.toc').Count -eq 0){throw 'VMW_ARCHIVE'}
    Assert-SafePath $source[0].FullName -Tree
    $source[0].FullName
}
function Install-WarpathEntry([string]$Destination,$Entry,$Queue,[int]$Index,[int]$Count) {
    $known=@(Get-WarpathEntries | Where-Object {$_.game -eq $Entry.game -and $_.repo -eq $Entry.repo})
    if($known.Count -ne 1){throw 'VMW_ARCHIVE'}
    Assert-SafePath $Destination
    [IO.Directory]::CreateDirectory($Destination)|Out-Null
    $root=Join-Path $Destination '.VoidMarkWarpath';Assert-SafePath $root
    [IO.Directory]::CreateDirectory($root)|Out-Null
    $target=Join-Path $Destination $Entry.repo;Assert-SafePath $target -Tree
    $record=Get-RecordPath $Destination $Entry.repo;Assert-SafePath $record
    $stage=Join-Path $root ('stage-'+[guid]::NewGuid().ToString('N'))
    Assert-ChildPath $root $stage;[IO.Directory]::CreateDirectory($stage)|Out-Null
    $backup=$null;$movedOld=$false;$movedNew=$false
    try {
        $sha=Get-RemoteSha $Entry.repo
        $zip=Join-Path $stage 'source.zip'
        Get-WarpathZip ('https://github.com/'+$script:WarpathOwner+'/'+$Entry.repo+'/archive/refs/heads/main.zip') $zip $Entry.name $Queue $Index $Count
        $source=Expand-SafeAddon $zip (Join-Path $stage 'unpacked')
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
        Send-WorkerEvent $Queue installed @{repo=$Entry.repo;sha=$sha}
        Send-WorkerEvent $Queue progress @{percent=[int](100*($Index+1)/$Count);text=($Entry.name+' is ready.')}
    } finally {
        try {Remove-SafeStage $root $stage}catch{Write-WarpathLog ('Stage cleanup: '+$_)}
    }
}
function Invoke-WarpathWorker([string]$Action,$Entries,[string]$Destination,$Queue) {
    $ErrorActionPreference='Stop';[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    if($Action -eq 'check') {
        $failed=$false;$i=0
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
