# VoidMark Market feed: copies the latest Market scan between your WoW accounts.
#
# Market (1.24.0+) writes VoidMarkMarketFeedOut into each account's
# WTF\Account\<name>\SavedVariables\VoidMarkMarket.lua on logout or /reload.
# This copies every account's copy into AddOns\VoidMarkMarket_Feed\Feed.lua,
# a tiny addon every account loads, so the other character gets the whole scan
# at its next login or /reload instead of waiting on the slow in-game sync.
# Read-only on WTF; the only thing written is the VoidMarkMarket_Feed folder.

$script:MarketFeedFolder='VoidMarkMarket_Feed'
$script:MarketFeedChunk=4000

function Find-MarketSavedFiles([string]$AddOns) {
    $clean=([string]$AddOns).Trim().TrimEnd('\','/')
    if($clean -notmatch '(?i)[\\/]Interface[\\/]AddOns$'){return @()}
    $accounts=Join-Path (Split-Path (Split-Path $clean -Parent) -Parent) 'WTF\Account'
    if(-not [IO.Directory]::Exists($accounts)){return @()}
    $found=@()
    foreach($acct in @(Get-ChildItem -LiteralPath $accounts -Directory -ErrorAction SilentlyContinue)) {
        $file=Join-Path (Join-Path $acct.FullName 'SavedVariables') 'VoidMarkMarket.lua'
        if([IO.File]::Exists($file)){$found+=$file}
    }
    $found
}

# Pull VoidMarkMarketFeedOut out of a saved-variables file without running it.
# Values are kept as the Lua literals WoW wrote, so they are copied unchanged.
function ConvertFrom-MarketFeedOut([string]$Text) {
    if(-not $Text){return $null}
    $m=[regex]::Match($Text,'(?m)^VoidMarkMarketFeedOut = \{\s*$')
    if(-not $m.Success){return $null}
    $end=[regex]::Match($Text.Substring($m.Index+$m.Length),'(?m)^\}\s*$')
    if(-not $end.Success){return $null}
    $body=$Text.Substring($m.Index+$m.Length,$end.Index)
    $str='"(?:[^"\\]|\\.)*"'
    $head=@{};$rows=New-Object System.Collections.Generic.List[string];$inRows=$false
    foreach($line in $body -split "`r?`n") {
        if($inRows) {
            if($line -match '^\s*\},?\s*$'){$inRows=$false;continue}
            $r=[regex]::Match($line,'^\s*('+$str+'),?\s*(--.*)?$')
            if($r.Success){$rows.Add($r.Groups[1].Value)}
            continue
        }
        if($line -match '^\s*\["rows"\] = \{\s*$'){$inRows=$true;continue}
        $h=[regex]::Match($line,'^\s*\["(\w+)"\] = ('+$str+'|-?\d+),?\s*$')
        if($h.Success){$head[$h.Groups[1].Value]=$h.Groups[2].Value}
    }
    foreach($k in 'version','economy','character','epoch','seq','savedAt'){if(-not $head.ContainsKey($k)){return $null}}
    if($head.version -ne '1' -or $rows.Count -eq 0){return $null}
    [pscustomobject]@{head=$head;rows=$rows;savedAt=[long]$head.savedAt}
}

function New-MarketFeedLua($Feeds) {
    $sb=New-Object Text.StringBuilder
    [void]$sb.Append("-- Made by VoidMark Warpath from your accounts' VoidMark Market data. Rebuilt automatically.`n")
    [void]$sb.Append("VoidMarkMarket_WarpathFeeds={}`n")
    foreach($f in @($Feeds)) {
        $h=$f.head;$fields=@()
        foreach($k in 'version','economy','character','epoch','seq','savedAt','scanAt','auctions'){if($h.ContainsKey($k)){$fields+=($k+'='+$h[$k])}}
        [void]$sb.Append('do local F={'+($fields -join ',')+",rows={}};table.insert(VoidMarkMarket_WarpathFeeds,F);local R=F.rows;`n")
        # Chunks keep each function well under Lua's limit on constants.
        for($i=0;$i -lt $f.rows.Count;$i+=$script:MarketFeedChunk) {
            $n=[Math]::Min($script:MarketFeedChunk,$f.rows.Count-$i)
            [void]$sb.Append('(function() local t={')
            [void]$sb.Append(($f.rows.GetRange($i,$n) -join ",`n"))
            [void]$sb.Append("};local n=#R;for i=1,#t do R[n+i]=t[i] end end)();`n")
        }
        [void]$sb.Append("end`n")
    }
    $sb.ToString()
}

function Write-MarketFeedFile([string]$Path,[string]$Text) {
    $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    [IO.File]::WriteAllText($temp,$Text,(New-Object Text.UTF8Encoding $false))
    if([IO.File]::Exists($Path)){[IO.File]::Replace($temp,$Path,[NullString]::Value)}else{[IO.File]::Move($temp,$Path)}
}

function Write-MarketFeedAddon([string]$AddOns,$Feeds) {
    $market=Join-Path $AddOns 'VoidMarkMarket\VoidMarkMarket.toc'
    $interface='16001'
    if([IO.File]::Exists($market)){$t=[regex]::Match([IO.File]::ReadAllText($market),'(?m)^## Interface:\s*(\d+)');if($t.Success){$interface=$t.Groups[1].Value}}
    $dir=Join-Path $AddOns $script:MarketFeedFolder
    [IO.Directory]::CreateDirectory($dir)|Out-Null
    $toc="## Interface: $interface`n## Title: VoidMark Market Feed`n## Notes: Latest Market scan from your other accounts, copied by VoidMark Warpath. Made automatically.`n## Author: VoidMark Warpath`nFeed.lua`n"
    $tocPath=Join-Path $dir ($script:MarketFeedFolder+'.toc')
    if(-not [IO.File]::Exists($tocPath) -or [IO.File]::ReadAllText($tocPath) -ne $toc){Write-MarketFeedFile $tocPath $toc}
    Write-MarketFeedFile (Join-Path $dir 'Feed.lua') (New-MarketFeedLua $Feeds)
}

# One check: rebuild the feed when any account's Market data changed.
# Returns the number of copies written, or -1 when nothing changed.
function Update-MarketFeed([string]$AddOns,[hashtable]$State) {
    if(-not [IO.Directory]::Exists((Join-Path $AddOns 'VoidMarkMarket'))){return -1}
    $files=@(Find-MarketSavedFiles $AddOns|Sort-Object)
    $sig=($files|ForEach-Object {$i=New-Object IO.FileInfo $_;$_+'|'+$i.LastWriteTimeUtc.Ticks+'|'+$i.Length}) -join ';'
    if($sig -eq $State.sig){return -1}
    # WoW may still be writing (large files): wait until a file is 2 seconds old.
    foreach($f in $files){if(([DateTime]::UtcNow-(New-Object IO.FileInfo $f).LastWriteTimeUtc).TotalSeconds -lt 2){return -1}}
    $feeds=@()
    foreach($f in $files) {
        try {$feed=ConvertFrom-MarketFeedOut ([IO.File]::ReadAllText($f,[Text.Encoding]::UTF8));if($feed){$feeds+=$feed}}
        catch {Write-WarpathLog ('Market feed read: '+$_)}
    }
    $State.sig=$sig
    if($feeds.Count -eq 0){return 0} # keep whatever was there before
    Write-MarketFeedAddon $AddOns ($feeds|Sort-Object savedAt)
    Write-WarpathLog ('Market feed: wrote '+$feeds.Count+' account copies ('+(($feeds|ForEach-Object {$_.rows.Count})|Measure-Object -Sum).Sum+' rows)')
    $feeds.Count
}

function Get-MarketFeedAddOns {
    $path=''
    $settings=Join-Path (Join-Path $env:APPDATA 'VoidMarkWarpath') 'settings.json'
    if([IO.File]::Exists($settings)){try{$cfg=[IO.File]::ReadAllText($settings)|ConvertFrom-Json;$path=[string]$cfg.paths.'WoW Forever'}catch{}}
    if(-not $path){
        foreach($base in @(${env:ProgramFiles(x86)},$env:ProgramFiles)){if($base){$c=Join-Path $base 'World of Warcraft\_forever_\Interface\AddOns';if([IO.Directory]::Exists($c)){$path=$c;break}}}
    }
    $path
}

# Start the background copier (one at a time) and have Windows start it at sign-in.
function Start-MarketFeedWatcher([string]$Root) {
    $addons=Get-MarketFeedAddOns
    if(-not $addons -or -not [IO.Directory]::Exists((Join-Path $addons 'VoidMarkMarket'))){return $false}
    $vbs=Join-Path $Root 'Launch-Market-Feed.vbs'
    if(-not [IO.File]::Exists($vbs)){return $false}
    $wscript=Join-Path $env:WINDIR 'System32\wscript.exe'
    try {
        $lnk=Join-Path ([Environment]::GetFolderPath('Startup')) 'VoidMark Market Feed.lnk'
        $shell=New-Object -ComObject WScript.Shell;$s=$shell.CreateShortcut($lnk)
        if($s.Arguments -ne ('"'+$vbs+'"')){
            $s.TargetPath=$wscript;$s.Arguments='"'+$vbs+'"';$s.WorkingDirectory=$Root
            $s.Description='VoidMark Warpath: copies the latest Market scan between your WoW accounts';$s.Save()
        }
    } catch {Write-WarpathLog ('Market feed startup shortcut: '+$_)}
    Start-Process -FilePath $wscript -ArgumentList ('"'+$vbs+'"') -WindowStyle Hidden
    $true
}
