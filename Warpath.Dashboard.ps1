# Windows PowerShell 5.1. Owner analytics dashboard.
# The window only opens in owner mode, but owner mode is a local convenience gate: every
# statistic comes from the server, which checks the owner's admin token on each request.
# The token is kept on this PC encrypted by Windows (DPAPI) and is never written to GitHub.

$script:WarpathAdminKeyFile=Join-Path (Join-Path $env:APPDATA 'VoidMarkWarpath') 'owner-analytics.key'
function Save-OwnerAnalyticsToken([string]$Token) {
    Add-Type -AssemblyName System.Security
    $bytes=[Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($Token.Trim()),[Text.Encoding]::UTF8.GetBytes('VoidMarkWarpath-analytics'),'CurrentUser')
    [IO.Directory]::CreateDirectory((Split-Path $script:WarpathAdminKeyFile -Parent))|Out-Null;[IO.File]::WriteAllBytes($script:WarpathAdminKeyFile,$bytes)
}
function Get-OwnerAnalyticsToken {
    try {
        if(-not [IO.File]::Exists($script:WarpathAdminKeyFile)){return ''}
        Add-Type -AssemblyName System.Security
        [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($script:WarpathAdminKeyFile),[Text.Encoding]::UTF8.GetBytes('VoidMarkWarpath-analytics'),'CurrentUser'))
    } catch {''}
}

# ---------------- Versions ----------------
# "1.23.38", "v0.11.1-beta", "1.3.3-forever" -> numbers + suffix. $null when not a version.
function ConvertTo-AddonVersion([string]$Text) {
    $m=[regex]::Match(([string]$Text).Trim(),'^[vV]?(\d+(?:\.\d+)*)(.*)$')
    if(-not $m.Success){return $null}
    $nums=@($m.Groups[1].Value.Split('.')|ForEach-Object {[long]$_})
    $suffix=$m.Groups[2].Value.Trim()
    @{nums=$nums;suffix=$suffix;pre=[bool]($suffix -match '(?i)(alpha|beta|rc|pre|dev|test)')}
}
# -1, 0 or 1; $null when either side can't be read as a version.
function Compare-AddonVersion([string]$A,[string]$B) {
    $x=ConvertTo-AddonVersion $A;$y=ConvertTo-AddonVersion $B
    if(-not $x -or -not $y){if($A -and $A -eq $B){return 0};return $null}
    $n=[Math]::Max($x.nums.Count,$y.nums.Count)
    for($i=0;$i -lt $n;$i++) {
        $p=if($i -lt $x.nums.Count){$x.nums[$i]}else{0};$q=if($i -lt $y.nums.Count){$y.nums[$i]}else{0}
        if($p -lt $q){return -1};if($p -gt $q){return 1}
    }
    # Same numbers: a release beats a pre-release (1.0 > 1.0-beta); other tags count as equal.
    if($x.pre -and -not $y.pre){return -1};if($y.pre -and -not $x.pre){return 1}
    0
}
# Version adoption for one addon. $Versions: @(@{version;installs}). $Pinned: the catalog's
# paused version label (friends are deliberately kept there), else ''. Installs on the pinned
# version (or newer) are up to date, never "outdated".
function Get-AddonAdoption($Versions,[string]$Latest,[string]$Pinned) {
    $target=if($Pinned){$Pinned}else{$Latest}
    $known=0;$current=0;$outdated=0;$unknown=0;$older=@();$most='';$mostCount=-1
    foreach($v in @($Versions)) {
        if(-not $v){continue}
        $count=[int]$v['installs'];$name=[string]$v['version']
        if($count -gt $mostCount -and $name){$most=$name;$mostCount=$count}
        if(-not $name -or -not $target){$unknown+=$count;continue}
        $c=Compare-AddonVersion $name $target
        if($null -eq $c){$unknown+=$count;continue}
        $known+=$count
        if($c -ge 0){$current+=$count}else{$outdated+=$count;$older+=$name}
    }
    $pct=if($known -gt 0){[Math]::Round(100.0*$current/$known)}else{$null}
    @{latest=$Latest;pinned=$Pinned;target=$target;mostCommon=$most;current=$current;outdated=$outdated;unknown=$unknown;known=$known;
      onTargetPct=$pct;olderVersions=@($older|Sort-Object -Unique {$_})}
}
function Get-CatalogPin($Catalog,[string]$Game,[string]$Repo) {
    foreach($c in @($Catalog)) {
        if((Get-WarpathField $c 'game') -eq $Game -and (Get-WarpathField $c 'repo') -eq $Repo) {
            $sha=[string](Get-WarpathField $c 'sha');if($sha -match '^[0-9a-fA-F]{40}$'){return [string](Get-WarpathField $c 'label')}
        }
    }
    ''
}
# Daily series -> one point per day from $From to $To (missing days = 0).
function Get-FilledSeries($Points,[string]$From,[string]$To) {
    $map=@{};foreach($p in @($Points)){if($p){$map[[string]$p['day']]=[double]$p['count']}}
    $start=[datetime]::ParseExact($From,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)
    if($From -eq '2000-01-01') {
        $days=@($map.Keys|Sort-Object);if($days.Count){$start=[datetime]::ParseExact($days[0],'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)}else{return @{labels=@();values=@()}}
    }
    $end=[datetime]::ParseExact($To,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)
    $labels=New-Object Collections.Generic.List[string];$values=New-Object Collections.Generic.List[double]
    for($d=$start;$d -le $end;$d=$d.AddDays(1)){$k=$d.ToString('yyyy-MM-dd');$labels.Add($k);$values.Add($(if($map.ContainsKey($k)){$map[$k]}else{0}))}
    @{labels=$labels.ToArray();values=$values.ToArray()}
}
function Get-AddonDisplayName([string]$Game,[string]$Repo) {
    foreach($a in @(Get-WarpathEntries)){if($a.game -eq $Game -and $a.repo -eq $Repo){return $a.name}}
    $Repo
}

# ---------------- Server requests (background runspace) ----------------
function Get-WarpathAnalyticsSummary([string]$Endpoint,[string]$Token,[hashtable]$Query,[scriptblock]$Transport=$null) {
    # Returns @{ok;data;error;status}. The token goes only in the Authorization header.
    if(-not $Endpoint){return @{ok=$false;error='Set the statistics server address in Settings first.';status=0}}
    if(-not $Token){return @{ok=$false;error='Paste your analytics admin token in Settings first.';status=0}}
    $qs=@();foreach($k in @($Query.Keys|Sort-Object)){if($Query[$k]){$qs+=($k+'='+[Uri]::EscapeDataString([string]$Query[$k]))}}
    $url=$Endpoint.TrimEnd('/')+'/v1/admin/summary'+$(if($qs.Count){'?'+($qs -join '&')}else{''})
    $headers=@{Authorization=('Bearer '+$Token);'User-Agent'='VoidMark-Warpath'}
    if($Transport){$reply=& $Transport $url $headers}
    else {
        try {
            [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
            $old=$ProgressPreference;$ProgressPreference='SilentlyContinue'
            try{$r=Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -TimeoutSec 25}finally{$ProgressPreference=$old}
            $reply=@{status=[int]$r.StatusCode;body=$(if($r.Content -is [byte[]]){[Text.Encoding]::UTF8.GetString($r.Content)}else{[string]$r.Content})}
        } catch {$code=0;try{$code=[int]$_.Exception.Response.StatusCode}catch{};$reply=@{status=$code;body=''}}
    }
    $status=[int]$reply.status
    switch($status) {
        401 {return @{ok=$false;status=401;error='The server refused the admin token. Paste the right token in Settings.'}}
        429 {return @{ok=$false;status=429;error='Too many tries. Wait a while (up to an hour after wrong tokens) and refresh.'}}
        503 {return @{ok=$false;status=503;error='The server has no admin token set yet (wrangler secret put ADMIN_TOKEN_SHA256).'}}
    }
    if($status -eq 0){return @{ok=$false;status=0;error="Couldn't reach the statistics server. Check your internet and the address in Settings."}}
    if($status -ne 200){return @{ok=$false;status=$status;error=('The statistics server answered with error '+$status+'.')}}
    try{$data=ConvertTo-WarpathPlain ($reply.body|ConvertFrom-Json)}catch{$data=$null}
    if($data -isnot [hashtable] -or $data['ok'] -ne $true -or $data['totals'] -isnot [hashtable]){return @{ok=$false;status=200;error='The statistics server sent something unexpected.'}}
    @{ok=$true;status=200;data=$data;error=''}
}
function Get-LatestAddonVersions($Entries) {
    # Newest version on GitHub main for each addon (read from its .toc), no API rate limit.
    $out=@{}
    foreach($a in @($Entries)) {
        try{$sha=(Get-RemoteSha $a.repo).ToLower();$out[$a.game+'|'+$a.repo]=@{sha=$sha;version=(Get-AddonVersionAt $a $sha)}}catch{}
    }
    $out
}
function Get-WarpathGitHubStats($Entries,[string]$Token) {
    # Separate from Warpath statistics. Clones/views/downloads are not people or active users.
    $rows=@();$seen=@{}
    foreach($a in @($Entries)) {
        if($seen.ContainsKey($a.repo)){continue};$seen[$a.repo]=$true
        $row=@{repo=$a.repo;releases='';downloads='';clones='';views=''}
        $h=@{'User-Agent'='VoidMark-Warpath';Accept='application/vnd.github+json'}
        try {
            $rel=@(Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$script:WarpathOwner+'/'+$a.repo+'/releases?per_page=100') -Headers $h -TimeoutSec 15)
            $n=0;$d=0;foreach($r in $rel){if($r){$n++;foreach($as in @($r.assets)){if($as){$d+=[int]$as.download_count}}}}
            $row.releases=[string]$n;$row.downloads=$(if($n){[string]$d}else{'no releases'})
        } catch {$row.releases='n/a';$row.downloads='n/a'}
        if($Token) {
            $ht=@{'User-Agent'='VoidMark-Warpath';Accept='application/vnd.github+json';Authorization=('Bearer '+$Token)}
            try{$c=Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$script:WarpathOwner+'/'+$a.repo+'/traffic/clones') -Headers $ht -TimeoutSec 15;$row.clones=([string]$c.count+' ('+[string]$c.uniques+' unique)')}catch{$row.clones='needs key access'}
            try{$v=Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$script:WarpathOwner+'/'+$a.repo+'/traffic/views') -Headers $ht -TimeoutSec 15;$row.views=([string]$v.count+' ('+[string]$v.uniques+' unique)')}catch{$row.views='needs key access'}
        } else {$row.clones='no GitHub key';$row.views='no GitHub key'}
        $rows+=$row
    }
    $rows
}

# ---------------- Window ----------------
function Show-WarpathAnalyticsDashboard($ParentWindow,[string]$Root) {
    $entries=@(Get-WarpathEntries)
    $catalogCache=Join-Path (Join-Path $env:APPDATA 'VoidMarkWarpath') 'catalog-cache.json'
    $catalog=@();if([IO.File]::Exists($catalogCache)){$catalog=@(Get-PublicCatalog $catalogCache)};if(-not $catalog.Count){$catalog=@(Get-PublicCatalog (Join-Path $Root 'public-catalog.json'))}
    $endpointFile=Join-Path $Root 'analytics-endpoint.txt'
    $script:dash=@{data=$null;latest=$null;job=$null;gh=$null}

    $w=New-Object Warpath.DarkForm;$w.Text='VoidMark Warpath — Analytics';$w.ClientSize=New-Object Drawing.Size(1100,860)
    if($ParentWindow){$w.StartPosition='CenterParent'}
    $title=[Warpath.Theme]::Label('ANALYTICS',20,12,220,34);$title.Font=[Warpath.Theme]::Serif(18);$title.ForeColor=[Warpath.Theme]::Highlight;$w.Controls.Add($title)
    $w.Controls.Add(([Warpath.Theme]::Label('Game',238,20,44,22)))
    $game=New-Object Warpath.GamePicker;$game.SetBounds(284,14,170,34);[void]$game.Items.AddRange(@('All games','WoW Forever','WoW Classic Era'));$game.SelectedIndex=0;$w.Controls.Add($game)
    $w.Controls.Add(([Warpath.Theme]::Label('Addon',466,20,48,22)))
    $addon=New-Object Warpath.GamePicker;$addon.SetBounds(516,14,200,34);[void]$addon.Items.Add('All addons')
    $addonRepos=@('');foreach($a in $entries){if($addonRepos -notcontains $a.repo){$addonRepos+=$a.repo;[void]$addon.Items.Add($a.name)}};$addon.SelectedIndex=0;$w.Controls.Add($addon)
    $w.Controls.Add(([Warpath.Theme]::Label('Range',728,20,46,22)))
    $range=New-Object Warpath.GamePicker;$range.SetBounds(776,14,130,34);[void]$range.Items.AddRange(@('Last 7 days','Last 30 days','Last 90 days','All time'));$range.SelectedIndex=1;$w.Controls.Add($range)
    $rangeKeys=@('7','30','90','all')
    $refresh=New-Object Warpath.PurpleButton;$refresh.Text='Refresh';$refresh.SetBounds(914,12,86,38);$w.Controls.Add($refresh)
    $settings=New-Object Warpath.PurpleButton;$settings.Text='Settings';$settings.SetBounds(1004,12,86,38);$w.Controls.Add($settings)
    $status=[Warpath.Theme]::Label('',20,54,1060,22);$status.ForeColor=[Warpath.Theme]::Secondary;$w.Controls.Add($status)

    $tileNames=@('Warpath installations','Addon installations','Active Warpath — 7 days','Active Warpath — 30 days','Most popular addon',
                 'New installations — week','New installations — month','Addon updates','Awaiting an update','Used in game — 30 days')
    $tiles=@{}
    for($i=0;$i -lt $tileNames.Count;$i++) {
        $t=New-Object Warpath.StatTile;$t.Title=$tileNames[$i];$t.Location=New-Object Drawing.Point((20+($i%5)*214),(80+[Math]::Floor($i/5)*78));$w.Controls.Add($t);$tiles[$tileNames[$i]]=$t
    }
    $note=[Warpath.Theme]::Label(("An installation is one anonymous copy of Warpath on one PC, not necessarily one person. "+
        "Active = Warpath opened and found the addon installed; that does not prove it was used in game. "+
        "Used in game comes only from addons that record their own use (SavedVariables), and only after WoW saves (logout or /reload)."),20,236,1060,38)
    $note.ForeColor=[Warpath.Theme]::Secondary;$note.Font=New-Object Drawing.Font('Segoe UI',9);$w.Controls.Add($note)
    $chartPick=New-Object Warpath.GamePicker;$chartPick.SetBounds(20,278,300,32)
    [void]$chartPick.Items.AddRange(@('Daily new installations','Daily active installations','Weekly adoption','Updates over time','Addon popularity','Version distribution'));$chartPick.SelectedIndex=0;$w.Controls.Add($chartPick)
    $chart=New-Object Warpath.Chart;$chart.SetBounds(20,316,1060,236);$w.Controls.Add($chart)
    $grid=New-Object Windows.Forms.DataGridView;$grid.SetBounds(20,562,1060,236);[Warpath.GridStyle]::Apply($grid);$w.Controls.Add($grid)
    $ghButton=New-Object Warpath.PurpleButton;$ghButton.Text='GitHub stats';$ghButton.SetBounds(18,806,150,40);$w.Controls.Add($ghButton)
    $ghNote=[Warpath.Theme]::Label('GitHub numbers are separate: clones, page views and ZIP downloads are not people or active users. Warpath downloads source ZIPs, which GitHub does not count.',176,808,904,40)
    $ghNote.ForeColor=[Warpath.Theme]::Secondary;$ghNote.Font=New-Object Drawing.Font('Segoe UI',9);$w.Controls.Add($ghNote)

    $getQuery={
        $q=@{range=$rangeKeys[$range.SelectedIndex]}
        if($game.SelectedIndex -gt 0){$q.game=[string]$game.SelectedItem}
        if($addon.SelectedIndex -gt 0){$q.repo=$addonRepos[$addon.SelectedIndex]}
        $q
    }
    $renderChart={
        $d=$script:dash.data;if(-not $d){$chart.SetData($chartPick.SelectedItem,$null,$null,$null,$false,'','');return}
        $f=$d['filters'];$s=$d['series']
        switch($chartPick.SelectedIndex) {
            0 {
                $a=Get-FilledSeries $s['newInstalls'] $f['from'] $f['to'];$b=Get-FilledSeries $s['detected'] $f['from'] $f['to']
                if($b.values.Count -ne $a.values.Count){$b=@{values=$null}}
                $chart.SetData('Daily new installations through Warpath (line: already-installed addons registered)',$a.labels,$a.values,$b.values,$false,'New installs','Detected existing')
            }
            1 {$a=Get-FilledSeries $s['active'] $f['from'] $f['to'];$chart.SetData('Daily active installations (Warpath opened)',$a.labels,$a.values,$null,$true,'','')}
            2 {
                $wk=@($s['weekly']|Where-Object {$_})
                $chart.SetData('Weekly adoption: new installs (bars) and active installations (line), weeks from Monday',[string[]]@($wk|ForEach-Object {[string]$_['week']}),[double[]]@($wk|ForEach-Object {[double]$_['newInstalls']}),[double[]]@($wk|ForEach-Object {[double]$_['active']}),$false,'New installs','Active')
            }
            3 {$a=Get-FilledSeries $s['updates'] $f['from'] $f['to'];$chart.SetData('Addon updates completed through Warpath',$a.labels,$a.values,$null,$false,'Updates','')}
            4 {
                $rows=@($d['addons']|Where-Object {$_}|Sort-Object {[int]$_['total']} -Descending)
                $chart.SetData('Addon popularity: known installations (line: active in last 30 days)',[string[]]@($rows|ForEach-Object {Get-AddonDisplayName $_['game'] $_['repo']}),[double[]]@($rows|ForEach-Object {[double]$_['total']}),[double[]]@($rows|ForEach-Object {[double]$_['active30']}),$false,'Installations','Active 30d')
            }
            5 {
                $rows=@($d['addons']|Where-Object {$_}|Sort-Object {[int]$_['total']} -Descending)
                if($addon.SelectedIndex -gt 0){$rows=@($rows|Where-Object {$_['repo'] -eq $addonRepos[$addon.SelectedIndex]})}
                if(-not $rows.Count){$chart.SetData('Version distribution',$null,$null,$null,$false,'','');return}
                $r=$rows[0];$vs=@($r['versions']|Where-Object {$_}|Sort-Object {[int]$_['installs']} -Descending|Select-Object -First 14)
                $chart.SetData(('Version distribution: '+(Get-AddonDisplayName $r['game'] $r['repo'])+$(if($addon.SelectedIndex -eq 0){' (most popular; pick an addon above for another)'}else{''})),
                    [string[]]@($vs|ForEach-Object {$(if($_['version']){[string]$_['version']}else{'unknown'})}),[double[]]@($vs|ForEach-Object {[double]$_['installs']}),[double[]]@($vs|ForEach-Object {[double]$_['active30']}),$false,'Installations','Active 30d')
            }
        }
    }
    $render={
        $d=$script:dash.data;if(-not $d){return}
        $t=$d['totals']
        $tiles['Warpath installations'].Set([string]$t['warpathInstalls'],'anonymous copies of Warpath')
        $tiles['Addon installations'].Set([string]$t['addonInstalls'],([string]$t['detectedExisting']+' were already installed'))
        $tiles['Active Warpath — 7 days'].Set([string]$t['active7'],'Warpath opened (check-in)')
        $tiles['Active Warpath — 30 days'].Set([string]$t['active30'],'Warpath opened (check-in)')
        $mp=$t['mostPopular'];if($mp){$tiles['Most popular addon'].Set((Get-AddonDisplayName $mp['game'] $mp['repo']),([string]$mp['installs']+' installations'))}else{$tiles['Most popular addon'].Set('—','')}
        $tiles['New installations — week'].Set([string]$t['newWarpathWeek'],([string]$t['newAddonInstallsWeek']+' new addon installs'))
        $tiles['New installations — month'].Set([string]$t['newWarpathMonth'],([string]$t['newAddonInstallsMonth']+' new addon installs'))
        $tiles['Addon updates'].Set([string]$t['updatesAllTime'],([string]$t['updatesInRange']+' in this range'))
        $tiles['Used in game — 30 days'].Set([string]$t['inGameActive30'],'installations, where addons report it')
        # Per-addon table with version adoption (pinned versions count as up to date).
        $table=New-Object Data.DataTable
        foreach($c in @(@('Addon',[string]),@('Game',[string]),@('Installations',[int]),@('Active 7d',[int]),@('Active 30d',[int]),@('Used in game 30d',[string]),
                       @('Updates',[int]),@('Latest published',[string]),@('Friends get',[string]),@('Most installed',[string]),@('Latest-version adoption',[string]),@('Awaiting update',[int]),@('Older versions in use',[string]))){[void]$table.Columns.Add($c[0],$c[1])}
        $awaiting=0
        $rows=@{};foreach($r in @($d['addons']|Where-Object {$_})){$rows[$r['game']+'|'+$r['repo']]=$r}
        foreach($a in $entries) {
            if($game.SelectedIndex -gt 0 -and $a.game -ne [string]$game.SelectedItem){continue}
            if($addon.SelectedIndex -gt 0 -and $a.repo -ne $addonRepos[$addon.SelectedIndex]){continue}
            $key=$a.game+'|'+$a.repo;$r=$rows[$key]
            if(-not $r -and -not (Test-PublicEntry $a $catalog)){continue}   # private and never seen: skip
            if(-not $r){$r=@{total=0;active7=0;active30=0;updates=0;inGameUsed30=0;reportsUsage=0;versions=@()}}
            $latest='';if($script:dash.latest -and $script:dash.latest[$key]){$latest=[string]$script:dash.latest[$key].version}
            $pin=Get-CatalogPin $catalog $a.game $a.repo
            $ad=Get-AddonAdoption $r['versions'] $latest $pin
            $awaiting+=$ad.outdated
            $inGame=if([int]$r['reportsUsage'] -gt 0){[string]$r['inGameUsed30']}else{'not reported'}
            $adopt=if($null -ne $ad.onTargetPct){[string]$ad.onTargetPct+'%'}elseif(-not $ad.target){'checking…'}else{'—'}
            $friends=if($pin){$pin+' (paused)'}elseif($latest){$latest}else{'?'}
            [void]$table.Rows.Add($a.name,$(if($a.game -eq 'WoW Classic Era'){'Classic Era'}else{'Forever'}),[int]$r['total'],[int]$r['active7'],[int]$r['active30'],$inGame,[int]$r['updates'],
                $(if($latest){$latest}else{'?'}),$friends,$ad.mostCommon,$adopt,[int]$ad.outdated,($ad.olderVersions -join ', '))
        }
        # Addons reported by installs that Warpath doesn't list yet (new public repos) still show.
        foreach($r in @($d['addons']|Where-Object {$_})) {
            if(@($entries|Where-Object {$_.game -eq $r['game'] -and $_.repo -eq $r['repo']}).Count){continue}
            $ad=Get-AddonAdoption $r['versions'] '' ''
            [void]$table.Rows.Add($r['repo'],[string]$r['game'],[int]$r['total'],[int]$r['active7'],[int]$r['active30'],$(if([int]$r['reportsUsage']){[string]$r['inGameUsed30']}else{'not reported'}),[int]$r['updates'],'?','?',$ad.mostCommon,'—',0,'')
        }
        $tiles['Awaiting an update'].Set([string]$awaiting,$(if($script:dash.latest){'behind the version friends get'}else{'checking latest versions…'}))
        $grid.DataSource=$table
        foreach($col in $grid.Columns){$col.SortMode='Automatic'}
        & $renderChart
        $status.ForeColor=[Warpath.Theme]::Secondary
        $status.Text=('Updated '+([datetime]$d['generatedAt']).ToLocalTime().ToString('MMM d h:mm tt')+'  •  '+$range.SelectedItem+'  •  Click a column title to sort.')
    }
    $startJob={
        param([string]$Kind)
        if($script:dash.job){return}
        $endpoint='';try{if([IO.File]::Exists($endpointFile)){$endpoint=([IO.File]::ReadAllText($endpointFile)).Trim()}}catch{}
        $token=Get-OwnerAnalyticsToken
        if($Kind -eq 'summary' -and (-not $endpoint -or -not $token)){$status.ForeColor=[Warpath.Theme]::Warning;$status.Text='One-time setup: click Settings and enter the server address and admin token.';return}
        $ps=[PowerShell]::Create()
        [void]$ps.AddScript({
            param($core,$an,$dashFile,$kind,$endpoint,$token,$query,$entries,$needLatest,$ghToken)
            . $core; . $an; . $dashFile
            $ProgressPreference='SilentlyContinue';[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
            if($kind -eq 'github'){return @{kind='github';rows=@(Get-WarpathGitHubStats $entries $ghToken)}}
            $r=Get-WarpathAnalyticsSummary $endpoint $token $query
            $r.kind='summary';if($needLatest -and $r.ok){$r.latest=Get-LatestAddonVersions $entries}
            $r
        }.ToString())
        [void]$ps.AddArgument((Join-Path $Root 'Warpath.Core.ps1')).AddArgument((Join-Path $Root 'Warpath.Analytics.ps1')).AddArgument((Join-Path $Root 'Warpath.Dashboard.ps1'))
        [void]$ps.AddArgument($Kind).AddArgument($endpoint).AddArgument($token).AddArgument((& $getQuery)).AddArgument(@($entries)).AddArgument(-not $script:dash.latest).AddArgument($(if($Kind -eq 'github'){Get-OwnerGitHubToken}else{''}))
        $script:dash.job=@{ps=$ps;handle=$ps.BeginInvoke()}
        $refresh.Enabled=$false;$ghButton.Enabled=$false;$status.ForeColor=[Warpath.Theme]::Secondary
        $status.Text=$(if($Kind -eq 'github'){'Reading GitHub stats…'}else{'Loading statistics…'})
    }
    $timer=New-Object Windows.Forms.Timer;$timer.Interval=150
    $timer.Add_Tick({
        $j=$script:dash.job;if(-not $j -or -not $j.handle.IsCompleted){return}
        $script:dash.job=$null;$refresh.Enabled=$true;$ghButton.Enabled=$true
        try {
            $r=@($j.ps.EndInvoke($j.handle))|Select-Object -Last 1
            if($r.kind -eq 'github') {
                $lines=@($r.rows|ForEach-Object {('{0}: releases {1}, release downloads {2}, clones (14 days) {3}, views (14 days) {4}' -f $_.repo,$_.releases,$_.downloads,$_.clones,$_.views)})
                Show-WarpathNote (($lines -join "`n")+"`n`nNot people or active users. Traffic needs a GitHub key with Administration: Read on each repo.") 'GitHub stats (separate from Warpath)'
                $status.Text='GitHub stats loaded.'
            } elseif($r.ok) {
                $script:dash.data=$r.data;if($r.latest){$script:dash.latest=$r.latest};& $render
            } else {$status.ForeColor=[Warpath.Theme]::Error;$status.Text=[string]$r.error}
        } catch {Write-WarpathLog ('Dashboard: '+($_|Out-String));$status.ForeColor=[Warpath.Theme]::Error;$status.Text="Couldn't load statistics. Details are in warpath.log."}
        finally {$j.ps.Dispose()}
    })
    $showSettings={
        $d=New-Object Warpath.DarkForm;$d.Text='Analytics settings';$d.ClientSize=New-Object Drawing.Size(640,360);$d.StartPosition='CenterParent'
        $d.Controls.Add(([Warpath.Theme]::Label('Statistics server address (your Cloudflare Worker, https://…). Saving publishes it so every Warpath can send; empty turns statistics off for everyone.',20,14,600,44)))
        $ep=[Warpath.Theme]::TextBox(20,62,600);try{if([IO.File]::Exists($endpointFile)){$ep.Text=([IO.File]::ReadAllText($endpointFile)).Trim()}}catch{};$d.Controls.Add($ep)
        $hasTok=[bool](Get-OwnerAnalyticsToken)
        $d.Controls.Add(([Warpath.Theme]::Label($(if($hasTok){'Admin token saved on this PC (encrypted by Windows). Paste a new one only to replace it.'}else{'Admin token (from: npm run token in the backend folder). Kept only on this PC, encrypted.'}),20,108,600,40)))
        $tk=[Warpath.Theme]::TextBox(20,150,600);$tk.UseSystemPasswordChar=$true;$d.Controls.Add($tk)
        $msg=[Warpath.Theme]::Label('',20,194,600,70);$msg.ForeColor=[Warpath.Theme]::Secondary;$d.Controls.Add($msg)
        $ok=New-Object Warpath.PurpleButton;$ok.Text='Save';$ok.SetBounds(18,284,300,52);$d.Controls.Add($ok)
        $cancel=New-Object Warpath.PurpleButton;$cancel.Text='Close';$cancel.SetBounds(326,284,296,52);$cancel.DialogResult='Cancel';$d.Controls.Add($cancel);$d.CancelButton=$cancel
        $loaded=$ep.Text.Trim()
        $ok.Add_Click({
            $url=$ep.Text.Trim().TrimEnd('/')
            if($url -and $url -cnotmatch $script:AnalyticsEndpointPattern){$msg.ForeColor=[Warpath.Theme]::Error;$msg.Text='That address should look like https://voidmark-analytics.<you>.workers.dev';return}
            try {
                if($tk.Text.Trim()){if($tk.Text.Trim() -notmatch '^[A-Za-z0-9_-]{32,200}$'){throw 'VMW_TOKEN'};Save-OwnerAnalyticsToken $tk.Text.Trim();$tk.Clear()}
                if($url -ne $loaded) {
                    $gh=Get-OwnerGitHubToken;if(-not $gh){throw 'VMW_NOKEY'}
                    $msg.ForeColor=[Warpath.Theme]::Secondary;$msg.Text='Publishing the address to GitHub…';$d.Refresh()
                    Publish-WarpathRepoFile 'analytics-endpoint.txt' $(if($url){$url+"`n"}else{''}) $gh $(if($url){'Analytics server address set'}else{'Analytics turned off (no server address)'})
                    [IO.File]::WriteAllText($endpointFile,$(if($url){$url+"`n"}else{''}),(New-Object Text.UTF8Encoding($false)));$loaded=$url
                }
                $msg.ForeColor=[Warpath.Theme]::Success;$msg.Text='Saved.'
            } catch {
                Write-WarpathLog ('Analytics settings: '+($_|Out-String));$msg.ForeColor=[Warpath.Theme]::Error;$e=($_|Out-String)
                $msg.Text=if($e -match 'VMW_TOKEN'){'That token looks wrong. Copy the TOKEN line from npm run token.'}elseif($e -match 'VMW_NOKEY'){'Save your GitHub key once in Edit public catalog first; it publishes the address.'}else{"Couldn't publish to GitHub. Nothing changed online; try again."}
            }
        })
        try{[void]$d.ShowDialog($w)}finally{$d.Dispose()}
    }
    $refresh.Add_Click({& $startJob 'summary'})
    $ghButton.Add_Click({& $startJob 'github'})
    $settings.Add_Click({& $showSettings})
    foreach($c in @($game,$addon,$range)){$c.Add_SelectedIndexChanged({if($w.Visible){& $startJob 'summary'}})}
    $chartPick.Add_SelectedIndexChanged({& $renderChart})
    $w.Add_Shown({$timer.Start();& $renderChart;& $startJob 'summary'})
    $w.Add_FormClosed({$timer.Stop();$timer.Dispose();$j=$script:dash.job;if($j){try{[void]$j.ps.BeginStop($null,$null)}catch{}}})
    try{if($ParentWindow){[void]$w.ShowDialog($ParentWindow)}else{[void]$w.ShowDialog()}}finally{$w.Dispose()}
}
