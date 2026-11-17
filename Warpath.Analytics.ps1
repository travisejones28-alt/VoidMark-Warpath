# Windows PowerShell 5.1. Anonymous, opt-in usage statistics for VoidMark Warpath.
#
# What is kept on this PC (%APPDATA%\VoidMarkWarpath\analytics.json):
#   a random installation id, the yes/no choice, the last check-in time, which addons were
#   already registered, and any statistics waiting to be sent.
# What is sent (always; a one-time notice tells the player): that random id, Warpath's version, and for
#   VoidMark addons only: game (Forever/Classic Era), repo name, version, install/update/
#   detected, the day, and (where the addon records it) when it was last loaded/used in game.
# Never sent: names, emails, characters, accounts, Windows user or PC names, file paths,
#   hardware ids, gameplay data. Nothing here can stop or slow an addon install or update.

$script:AnalyticsIdPattern='^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
$script:AnalyticsVersionPattern='^[0-9A-Za-z][0-9A-Za-z.+_-]{0,39}$'
$script:AnalyticsEndpointPattern='^https://[A-Za-z0-9.-]+(:\d{2,5})?(/[A-Za-z0-9._~/-]*)?$'
$script:AnalyticsMaxOutbox=200
$script:AnalyticsMaxAgeDays=30
$script:AnalyticsCheckinHours=24

function Get-WarpathAnalyticsPath {
    Join-Path (Join-Path $env:APPDATA 'VoidMarkWarpath') 'analytics.json'
}
function New-WarpathInstallId {
    # Guid.NewGuid() is a random (version 4) UUID: no MAC address, time or hardware in it.
    [guid]::NewGuid().ToString('D').ToLowerInvariant()
}
function Test-WarpathInstallId([string]$Id) {[bool]($Id -cmatch $script:AnalyticsIdPattern)}
function ConvertTo-WarpathPlain($Value) {
    # ConvertFrom-Json objects -> hashtables/arrays, so the state can be edited the same way
    # on Windows PowerShell 5.1 and newer versions.
    if($null -eq $Value){return $null}
    if($Value -is [string] -or $Value -is [ValueType]){return $Value}
    if($Value -is [Collections.IDictionary]){$h=@{};foreach($k in @($Value.Keys)){$h[[string]$k]=ConvertTo-WarpathPlain $Value[$k]};return $h}
    if($Value -is [Collections.IEnumerable]){$list=@();foreach($x in $Value){$list+=,(ConvertTo-WarpathPlain $x)};return ,$list}
    $h=@{};foreach($p in $Value.PSObject.Properties){$h[$p.Name]=ConvertTo-WarpathPlain $p.Value};$h
}
function New-WarpathAnalyticsState([string]$Id) {
    @{installId=$Id;consent='unset';consentAt='';lastCheckin='';known=@{};outbox=@();pendingDelete=$false;ownerExcluded=$false;created=(Get-Date).ToUniversalTime().ToString('o')}
}
# Reads (or creates) the local state. The installation id is made once and never replaced
# while a valid one exists, even if the rest of the file is damaged.
function Read-WarpathAnalytics([string]$Path=(Get-WarpathAnalyticsPath)) {
    $raw=$null;$data=$null
    if([IO.File]::Exists($Path)) {
        try {$raw=[IO.File]::ReadAllText($Path);$data=ConvertTo-WarpathPlain ($raw.TrimStart([char]0xFEFF)|ConvertFrom-Json)} catch {$data=$null}
    }
    $id=''
    if($data -is [hashtable]){$id=[string]$data['installId']}
    if(-not (Test-WarpathInstallId $id) -and $raw) {
        # Damaged file: keep the id if it can still be read.
        $m=[regex]::Match($raw,'[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}')
        if($m.Success){$id=$m.Value}
    }
    $isNew=$false
    if(-not (Test-WarpathInstallId $id)){$id=New-WarpathInstallId;$isNew=$true}
    $state=New-WarpathAnalyticsState $id
    if($data -is [hashtable]) {
        if(@('on','off','unset') -contains [string]$data['consent']){$state.consent=[string]$data['consent']}
        foreach($k in @('consentAt','lastCheckin','created')){if($data[$k]){$state[$k]=[string]$data[$k]}}
        if($data['known'] -is [hashtable]){foreach($k in @($data['known'].Keys)){$state.known[$k]=[string]$data['known'][$k]}}
        if($data['outbox']){$state.outbox=@(@($data['outbox'])|Where-Object {$_ -is [hashtable] -and $_['id'] -and $_['type']})}
        $state.pendingDelete=[bool]$data['pendingDelete'];$state.ownerExcluded=[bool]$data['ownerExcluded']
    } elseif($raw) {
        # Unreadable file: keep a copy for troubleshooting; statistics stay off until asked again.
        try{[IO.File]::Copy($Path,$Path+'.bad',$true)}catch{}
    }
    $state.isNew=$isNew -or ($null -eq $raw)
    $state
}
function Save-WarpathAnalytics($State,[string]$Path=(Get-WarpathAnalyticsPath)) {
    $dir=Split-Path $Path -Parent;[IO.Directory]::CreateDirectory($dir)|Out-Null
    $out=[ordered]@{installId=$State.installId;consent=$State.consent;consentAt=$State.consentAt;lastCheckin=$State.lastCheckin;
        created=$State.created;known=$State.known;outbox=@($State.outbox);pendingDelete=[bool]$State.pendingDelete;ownerExcluded=[bool]$State.ownerExcluded}
    $json=ConvertTo-Json -InputObject $out -Depth 8
    $temp=Join-Path $dir ('analytics-'+[guid]::NewGuid().ToString('N')+'.tmp')
    [IO.File]::WriteAllText($temp,$json,(New-Object Text.UTF8Encoding($false)))
    if([IO.File]::Exists($Path)){[IO.File]::Replace($temp,$Path,[NullString]::Value)}else{[IO.File]::Move($temp,$Path)}
}
# Startup: make sure this PC has an id (existing users get one on their first launch of this
# version, with no reinstall). Never sends anything. Returns $null if anything goes wrong.
function Initialize-WarpathAnalytics([string]$Path=(Get-WarpathAnalyticsPath)) {
    try {
        $state=Read-WarpathAnalytics $Path
        if($state.isNew -or -not [IO.File]::Exists($Path)){Save-WarpathAnalytics $state $Path}
        $state
    } catch {Write-WarpathLog ('Analytics init: '+$_);$null}
}
function Set-WarpathAnalyticsConsent($State,[bool]$Enabled,[string]$Path=(Get-WarpathAnalyticsPath)) {
    if($Enabled){$State.consent='on'}else{$State.consent='off';$State.outbox=@()}   # turning off drops anything not yet sent
    $State.consentAt=(Get-Date).ToUniversalTime().ToString('o')
    Save-WarpathAnalytics $State $Path
}
# Always on (no opt-out); only waits while an older deletion request is still being sent.
function Test-WarpathAnalyticsOn($State) {[bool]($State -and -not $State.pendingDelete -and -not $State.ownerExcluded)}
# The owner's own copy (it has the owner catalog editor) is left out of the statistics.
function Test-WarpathOwnerCopy([string]$Root) {[IO.File]::Exists((Join-Path $Root 'Owner-Catalog-Editor.ps1'))}
# Marks this PC as the owner's: nothing more is sent, and what was already sent gets deleted.
# Returns $true when a deletion still has to be sent.
function Set-WarpathOwnerExcluded($State,[string]$Path=(Get-WarpathAnalyticsPath)) {
    if(-not $State.ownerExcluded){$State.ownerExcluded=$true;$State.pendingDelete=$true;$State.outbox=@();Save-WarpathAnalytics $State $Path}
    [bool]$State.pendingDelete
}

function Get-WarpathSafeVersion([string]$Version) {
    $v=([string]$Version).Trim();if($v -cmatch $script:AnalyticsVersionPattern){$v}else{''}
}
function Get-TocVersion([string]$Folder,[string]$Addon) {
    try {
        $toc=Join-Path $Folder ($Addon+'.toc')
        if([IO.File]::Exists($toc)){$m=[regex]::Match([IO.File]::ReadAllText($toc),'(?m)^##\s*Version:\s*(\S+)');if($m.Success){return (Get-WarpathSafeVersion $m.Groups[1].Value)}}
    } catch {}
    ''
}
function New-WarpathAnalyticsEvent([string]$Type,[hashtable]$Fields=@{},[DateTime]$Now=[DateTime]::UtcNow) {
    $e=@{id=[guid]::NewGuid().ToString('D');type=$Type;ts=$Now.ToUniversalTime().ToString('o')}
    foreach($k in $Fields.Keys){$e[$k]=$Fields[$k]}
    $e
}
function Limit-WarpathOutbox($State,[DateTime]$Now=[DateTime]::UtcNow) {
    $cut=$Now.AddDays(-$script:AnalyticsMaxAgeDays)
    $keep=@(@($State.outbox)|Where-Object {$t=[DateTime]::MinValue;[DateTime]::TryParse([string]$_['ts'],[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$t) -and $t.ToUniversalTime() -ge $cut})
    if($keep.Count -gt $script:AnalyticsMaxOutbox){$keep=@($keep[($keep.Count-$script:AnalyticsMaxOutbox)..($keep.Count-1)])}
    $State.outbox=$keep
}
# Queues an event only while statistics are on. Returns $true when queued.
function Add-WarpathAnalyticsEvent($State,$Event,[DateTime]$Now=[DateTime]::UtcNow) {
    if(-not (Test-WarpathAnalyticsOn $State)){return $false}
    $State.outbox=@(@($State.outbox)+,$Event);Limit-WarpathOutbox $State $Now;$true
}
# Install or update done through Warpath. Type: 'install' or 'update'.
function Register-WarpathAddonChange($State,[string]$Type,[string]$Game,[string]$Repo,[string]$Version,[DateTime]$Now=[DateTime]::UtcNow) {
    if(-not (Test-WarpathAnalyticsOn $State)){return $false}
    if(@('install','update') -notcontains $Type){return $false}
    $v=Get-WarpathSafeVersion $Version
    $ok=Add-WarpathAnalyticsEvent $State (New-WarpathAnalyticsEvent $Type @{game=$Game;repo=$Repo;version=$v} $Now) $Now
    if($ok){$State.known[$Game+'|'+$Repo]=$v}
    $ok
}
# VoidMark addons in each remembered AddOns folder. Linked developer folders are skipped.
function Get-WarpathInstalledAddons([hashtable]$Paths) {
    $out=@()
    foreach($game in @($Paths.Keys)) {
        $path=[string]$Paths[$game]
        if(-not $path -or -not [IO.Directory]::Exists($path)){continue}
        foreach($a in @(Get-WarpathEntries | Where-Object {$_.game -eq $game})) {
            try {
                $name=Get-AddonFolder $a;$folder=Join-Path $path $name
                if(-not [IO.Directory]::Exists($folder) -or (Test-LinkedPath $folder)){continue}
                if(-not [IO.File]::Exists((Join-Path $folder ($name+'.toc')))){continue}
                $out+=@{game=$game;repo=$a.repo;addon=$name;version=(Get-TocVersion $folder $name);addOns=$path}
            } catch {Write-WarpathLog ('Analytics scan: '+$_)}
        }
    }
    $out
}
# On launch (statistics on): register addons that were already installed as "detected"
# (never as new installs), and queue at most one check-in per 24 hours.
function Invoke-WarpathAnalyticsStartup($State,[hashtable]$Paths,[DateTime]$Now=[DateTime]::UtcNow,[string]$Path=(Get-WarpathAnalyticsPath)) {
    if(-not (Test-WarpathAnalyticsOn $State)){return @{detected=0;checkin=$false}}
    $found=@(Get-WarpathInstalledAddons $Paths);$detected=0
    foreach($f in $found) {
        $key=$f.game+'|'+$f.repo
        if(-not $State.known.ContainsKey($key)) {
            [void](Add-WarpathAnalyticsEvent $State (New-WarpathAnalyticsEvent 'detected' @{game=$f.game;repo=$f.repo;version=$f.version} $Now) $Now)
            $State.known[$key]=$f.version;$detected++
        } else {$State.known[$key]=$f.version}
    }
    $due=$true;$last=[DateTime]::MinValue
    if($State.lastCheckin -and [DateTime]::TryParse([string]$State.lastCheckin,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$last)) {
        $due=($Now.ToUniversalTime()-$last.ToUniversalTime()).TotalHours -ge $script:AnalyticsCheckinHours
    }
    if($due) {
        $addons=@($found|ForEach-Object {@{game=$_.game;repo=$_.repo;version=$_.version}})
        [void](Add-WarpathAnalyticsEvent $State (New-WarpathAnalyticsEvent 'checkin' @{addons=$addons} $Now) $Now)
        $State.lastCheckin=$Now.ToUniversalTime().ToString('o')
    }
    Save-WarpathAnalytics $State $Path
    @{detected=$detected;checkin=$due}
}
# After a send: drop what the server accepted (or refused for good). Safe if new events were
# added meanwhile.
function Complete-WarpathAnalyticsSend($State,$Result,[string]$Path=(Get-WarpathAnalyticsPath)) {
    if(-not $Result){return}
    $done=@{};foreach($id in @($Result.sent)+@($Result.dropped)){if($id){$done[[string]$id]=$true}}
    if($done.Count){$State.outbox=@(@($State.outbox)|Where-Object {-not $done.ContainsKey([string]$_['id'])});Save-WarpathAnalytics $State $Path}
}

# ---------------- In-game usage (read-only, SavedVariables) ----------------
# Addons that support it keep a tiny table named <AddonFolder>Usage, e.g.
#   VoidMarkMarketUsage = { ["v"] = 1, ["init"] = 1763300000, ["active"] = 1763300100, ["version"] = "1.23.39" }
# init = the addon last loaded; active = a feature was really used. Times only.
function Get-WarpathUsageFromText([string]$Text,[string]$Global) {
    $m=[regex]::Match($Text,'(?ms)^'+[regex]::Escape($Global)+'\s*=\s*\{(.*?)^\}')
    if(-not $m.Success){return $null}
    $u=@{}
    foreach($k in @('init','active')) {
        $f=[regex]::Match($m.Groups[1].Value,'(?<![A-Za-z_])\[?"?'+$k+'"?\]?\s*=\s*(\d{9,11})')
        if($f.Success){$u[$k]=[long]$f.Groups[1].Value}
    }
    if($u.Count){$u}else{$null}
}
function Get-WarpathAddonUsage([string]$AddOns,[string]$Addon) {
    # Newest times across all WoW accounts on this PC for this game folder.
    $clean=([string]$AddOns).Trim().TrimEnd('\','/')
    if($clean -notmatch '(?i)[\\/]Interface[\\/]AddOns$'){return $null}
    $accounts=Join-Path (Split-Path (Split-Path $clean -Parent) -Parent) (Join-Path 'WTF' 'Account')
    if(-not [IO.Directory]::Exists($accounts)){return $null}
    $best=@{}
    foreach($acct in @(Get-ChildItem -LiteralPath $accounts -Directory -ErrorAction SilentlyContinue)) {
        $file=Join-Path (Join-Path $acct.FullName 'SavedVariables') ($Addon+'.lua')
        if(-not [IO.File]::Exists($file)){continue}
        try {
            $u=Get-WarpathUsageFromText ([IO.File]::ReadAllText($file)) ($Addon+'Usage')
            if($u){foreach($k in @($u.Keys)){if(-not $best.ContainsKey($k) -or $u[$k] -gt $best[$k]){$best[$k]=$u[$k]}}}
        } catch {}
    }
    if($best.Count){$best}else{$null}
}

# ---------------- Sending (runs in a background runspace) ----------------
function Get-WarpathAnalyticsEndpoint([string]$Root,[scriptblock]$Fetch=$null) {
    # GitHub's copy first (the owner can set or clear it without a Warpath update); the local
    # copy only when GitHub can't be reached. Empty means statistics are switched off.
    $url=$null
    try {
        if($Fetch){$url=[string](& $Fetch)}
        else {$url=Get-WarpathText ($script:WarpathRawBase+'analytics-endpoint.txt?v='+[DateTime]::UtcNow.Ticks)}
    } catch {
        $url=$null
        try{$f=Join-Path $Root 'analytics-endpoint.txt';if([IO.File]::Exists($f)){$url=[IO.File]::ReadAllText($f)}}catch{}
    }
    $url=([string]$url).Trim().TrimEnd('/')
    if($url -cmatch $script:AnalyticsEndpointPattern){$url}else{''}
}
function Invoke-WarpathAnalyticsHttp([string]$Url,[string]$Body) {
    # Returns @{status;body}. Never throws.
    try {
        [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
        $old=$ProgressPreference;$ProgressPreference='SilentlyContinue'
        try{$r=Invoke-WebRequest -Uri $Url -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($Body)) -ContentType 'application/json' -UseBasicParsing -Headers @{'User-Agent'='VoidMark-Warpath'} -TimeoutSec 15}
        finally{$ProgressPreference=$old}
        $text=if($r.Content -is [byte[]]){[Text.Encoding]::UTF8.GetString($r.Content)}else{[string]$r.Content}
        @{status=[int]$r.StatusCode;body=$text}
    } catch {
        $code=0;try{$code=[int]$_.Exception.Response.StatusCode}catch{}
        @{status=$code;body='';error=[string]$_.Exception.Message}
    }
}
function ConvertFrom-WarpathAnalyticsReply($Reply) {
    # Returns @{accepted;rejected} or $null when the answer isn't what the server sends.
    if(-not $Reply -or [int]$Reply.status -ne 200 -or -not $Reply.body){return $null}
    try {$j=ConvertTo-WarpathPlain ($Reply.body|ConvertFrom-Json)} catch {return $null}
    if($j -isnot [hashtable] -or $j['ok'] -ne $true -or -not $j.ContainsKey('accepted')){return $null}
    @{accepted=@(@($j['accepted'])|Where-Object {$_ -is [string]});rejected=@(@($j['rejected'])|Where-Object {$_ -is [string]})}
}
# Sends queued statistics. Usage times are read here, in the background, and only go into the
# request (they are never stored by Warpath). Returns @{sent;dropped;ok;error}.
function Send-WarpathAnalytics([string]$Endpoint,[string]$InstallId,[string]$AppVersion,$Outbox,$Usage=@(),[scriptblock]$Transport=$null) {
    $result=@{sent=@();dropped=@();ok=$true;error=''}
    if(-not $Endpoint){$result.ok=$false;$result.error='no-endpoint';return $result}
    $events=@(@($Outbox)|Where-Object {$_})
    if(-not $events.Count){return $result}
    $usageMap=@{};foreach($u in @($Usage)){if($u){$usageMap[[string]$u.game+'|'+[string]$u.repo]=$u.usage}}
    for($i=0;$i -lt $events.Count;$i+=50) {
        $chunk=@($events[$i..([Math]::Min($i+49,$events.Count-1))])
        $send=@()
        foreach($e in $chunk) {
            $copy=@{};foreach($k in @($e.Keys)){$copy[$k]=$e[$k]}
            if($copy['type'] -eq 'checkin') {
                $list=@()
                foreach($a in @($copy['addons'])) {
                    if(-not $a){continue}
                    $x=@{game=$a['game'];repo=$a['repo'];version=$a['version']}
                    $u=$usageMap[[string]$a['game']+'|'+[string]$a['repo']];if($u){$x.usage=$u}
                    $list+=,$x
                }
                $copy['addons']=$list
            }
            $send+=,$copy
        }
        $body=ConvertTo-Json -InputObject ([ordered]@{installId=$InstallId;appVersion=$AppVersion;events=$send}) -Depth 8 -Compress
        $reply=if($Transport){& $Transport ($Endpoint+'/v1/events') $body}else{Invoke-WarpathAnalyticsHttp ($Endpoint+'/v1/events') $body}
        $parsed=ConvertFrom-WarpathAnalyticsReply $reply
        if(-not $parsed) {
            $result.ok=$false
            $code=0;if($reply){$code=[int]$reply.status}
            $result.error=if($code -eq 200){'bad-reply'}elseif($code -eq 429){'rate-limited'}elseif($code -gt 0){'http-'+$code}else{'offline'}
            break
        }
        $ids=@{};foreach($e in $chunk){$ids[[string]$e['id']]=$true}
        $result.sent+=@($parsed.accepted|Where-Object {$ids.ContainsKey($_)})
        $result.dropped+=@($parsed.rejected|Where-Object {$ids.ContainsKey($_)})
    }
    $result
}
function Remove-WarpathAnalyticsData([string]$Endpoint,[string]$InstallId,[scriptblock]$Transport=$null) {
    if(-not $Endpoint){return @{ok=$false;error='no-endpoint'}}
    $body=ConvertTo-Json -InputObject @{installId=$InstallId} -Compress
    $reply=if($Transport){& $Transport ($Endpoint+'/v1/installations/delete') $body}else{Invoke-WarpathAnalyticsHttp ($Endpoint+'/v1/installations/delete') $body}
    $ok=$false
    try{if($reply -and [int]$reply.status -eq 200){$j=$reply.body|ConvertFrom-Json;$ok=[bool]($j.deleted -eq $true)}}catch{}
    @{ok=$ok;error=$(if($ok){''}elseif($reply -and [int]$reply.status){'http-'+[int]$reply.status}else{'offline'})}
}
# Entry point for the background runspace: one job, either 'send' or 'delete'.
function Invoke-WarpathAnalyticsJob([string]$Action,[string]$Root,[string]$InstallId,[string]$AppVersion,$Outbox,$Sources) {
    $ErrorActionPreference='Stop'
    try {
        $endpoint=Get-WarpathAnalyticsEndpoint $Root
        if($Action -eq 'delete'){return (Remove-WarpathAnalyticsData $endpoint $InstallId)}
        $usage=@()
        foreach($s in @($Sources)) {
            if(-not $s){continue}
            try{$u=Get-WarpathAddonUsage $s.addOns $s.addon;if($u){$usage+=@{game=$s.game;repo=$s.repo;usage=$u}}}catch{}
        }
        Send-WarpathAnalytics $endpoint $InstallId $AppVersion $Outbox $usage
    } catch {@{ok=$false;error=('job: '+$_.Exception.Message);sent=@();dropped=@()}}
}
