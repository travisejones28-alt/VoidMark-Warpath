#requires -version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Warpath.Core.ps1')
try {
    . (Join-Path $PSScriptRoot 'Warpath.Theme.ps1')
    $script:root=$PSScriptRoot
    $script:catalog=@(Get-PublicCatalog (Join-Path $root 'public-catalog.json'))
    $script:appVersion=Get-LocalAppVersion $root;$script:remoteVersion='';$script:updateAsked=$false;$script:shortcutAsked=$false;$script:notesAsked=$false;$script:notesFailed=@{};$script:lastNotesScan=[datetime]::MinValue;$script:inDialog=$false
    $catalogCache=Join-Path (Join-Path $env:APPDATA 'VoidMarkWarpath') 'catalog-cache.json'
    if([IO.File]::Exists($catalogCache)){try{if([IO.File]::ReadAllText($catalogCache).Trim()){$script:catalog=@(Get-PublicCatalog $catalogCache)}}catch{}}
    $script:entries=@(Get-WarpathEntries)
    # Market feed: keep the background copier running (it starts itself at Windows
    # sign-in after the first time). Never blocks or breaks the installer.
    try{. (Join-Path $root 'Warpath.MarketFeed.ps1');[void](Start-MarketFeedWatcher $root)}catch{Write-WarpathLog ('Market feed start: '+$_)}
    # Anonymous statistics (opt-in). Loading makes the random installation id on this PC (also for
    # people updating from an older Warpath) but sends nothing until the player says yes.
    # Any failure here only leaves statistics off; installs and updates never depend on it.
    $script:analytics=$null;$script:analyticsJob=$null;$script:analyticsDeleteTried=$false;$script:preInstalled=@{};$script:workGame='';$script:workFolder=''
    $analyticsFile=Join-Path $root 'Warpath.Analytics.ps1'
    if([IO.File]::Exists($analyticsFile)){try{. $analyticsFile;$script:analytics=Initialize-WarpathAnalytics}catch{Write-WarpathLog ('Analytics load: '+$_);$script:analytics=$null}}
    # Owner access is remembered on this PC once unlocked (Windows-encrypted for this
    # Windows user, so the file is useless on another PC or account).
    $ownerKey=Join-Path (Join-Path $env:APPDATA 'VoidMarkWarpath') 'owner.key'
    function Get-OwnerKeyText {'VoidMark-owner|'+$env:USERNAME+'|'+$env:COMPUTERNAME}
    function Save-OwnerKey {
        try {
            Add-Type -AssemblyName System.Security
            $bytes=[Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes((Get-OwnerKeyText)),[Text.Encoding]::UTF8.GetBytes('VoidMarkWarpath'),'CurrentUser')
            [IO.Directory]::CreateDirectory((Split-Path $ownerKey -Parent))|Out-Null;[IO.File]::WriteAllBytes($ownerKey,$bytes)
        } catch {Write-WarpathLog ('Owner key: '+$_)}
    }
    function Test-OwnerKey {
        try {
            if(-not [IO.File]::Exists($ownerKey)){return $false}
            Add-Type -AssemblyName System.Security
            $plain=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($ownerKey),[Text.Encoding]::UTF8.GetBytes('VoidMarkWarpath'),'CurrentUser')
            [Text.Encoding]::UTF8.GetString($plain) -eq (Get-OwnerKeyText)
        } catch {$false}
    }
    $script:ownerUnlocked=Test-OwnerKey
    $script:ownerMode=$script:ownerUnlocked;$script:busy=$false;$script:remote=@{};$script:job=$null;$script:jobError=''
    $settingsDir=Join-Path $env:APPDATA 'VoidMarkWarpath';$settingsPath=Join-Path $settingsDir 'settings.json'
    $script:paths=@{'WoW Forever'='';'WoW Classic Era'=''};$script:lastGame='WoW Forever'
    if([IO.File]::Exists($settingsPath)) {
        try {
            $cfg=[IO.File]::ReadAllText($settingsPath)|ConvertFrom-Json
            foreach($key in @($paths.Keys)){if($cfg.paths.$key){$paths[$key]=[string]$cfg.paths.$key}}
            if($cfg.PSObject.Properties['game'] -and $paths.ContainsKey([string]$cfg.game)){$script:lastGame=[string]$cfg.game}
            if($cfg.PSObject.Properties['shortcutAsked']){$script:shortcutAsked=[bool]$cfg.shortcutAsked}
        } catch {Write-WarpathLog ('Settings: '+$_)}
    }
    foreach($key in @($paths.Keys)) {
        if(-not $paths[$key]) {
            $client=if($key -eq 'WoW Forever'){'_forever_'}else{'_classic_era_'}
            foreach($base in @(${env:ProgramFiles(x86)},$env:ProgramFiles)) {
                if(-not $base){continue}
                $candidate=Join-Path $base ('World of Warcraft\'+$client+'\Interface\AddOns')
                if([IO.Directory]::Exists($candidate)){$paths[$key]=$candidate;break}
            }
        }
    }
    $script:form=New-Object Warpath.MainWindow
    $script:form.ShowOwner([bool]$script:ownerUnlocked,[bool]$script:ownerMode)
    $art=Join-Path $root 'assets\voidmark_forever_header_2048x512.png'
    $icon=Join-Path $root 'assets\voidmark.ico'
    try{$form.ApplyArt($art,$icon)}catch{Write-WarpathLog ('Art: '+$_)}
    $form.VersionLabel.Text='Warpath v'+$script:appVersion;$form.VersionLabel.Width=120
    $updateLink=[Warpath.Theme]::Link('⬆ Update Warpath',148,885,180);$updateLink.LinkColor=[Warpath.Theme]::Warning;$updateLink.Visible=$false;$form.Controls.Add($updateLink);$updateLink.BringToFront()
    $shortcutLink=[Warpath.Theme]::Link('Desktop shortcut',340,885,140);$form.Controls.Add($shortcutLink);$shortcutLink.BringToFront()
    $reportLink=[Warpath.Theme]::Link('Report a problem',500,885,124);$reportLink.LinkColor=[Warpath.Theme]::Highlight;$form.Controls.Add($reportLink);$reportLink.BringToFront()
    $privacyLink=[Warpath.Theme]::Link('Privacy',626,885,52);$form.Controls.Add($privacyLink);$privacyLink.BringToFront()
    function Test-AddOnsPath([string]$Path){$Path.Trim().TrimEnd('\','/') -match '(?i)(^|[\\/])Interface[\\/]AddOns$'}
    function New-WarpathShortcut {
        try {
            $lnk=Join-Path ([Environment]::GetFolderPath('Desktop')) 'VoidMark Warpath.lnk'
            $shell=New-Object -ComObject WScript.Shell;$s=$shell.CreateShortcut($lnk)
            $s.TargetPath=Join-Path $env:WINDIR 'System32\wscript.exe'
            $s.Arguments='"'+(Join-Path $root 'Launch-VoidMark-Warpath.vbs')+'"'
            $s.WorkingDirectory=$root;$s.Description='VoidMark Warpath addon installer'
            if([IO.File]::Exists($icon)){$s.IconLocation=$icon+',0'}
            $s.Save();$form.Status.Text='Desktop shortcut created: VoidMark Warpath';$form.Status.ForeColor=[Warpath.Theme]::Success
        } catch {Write-WarpathLog ('Shortcut: '+$_);$form.Status.Text="Couldn't create the desktop shortcut.";$form.Status.ForeColor=[Warpath.Theme]::Error}
    }
    function Save-Settings {
        try {
            [IO.Directory]::CreateDirectory($settingsDir)|Out-Null
            $paths[[string]$form.Game.SelectedItem]=$form.Folder.Text.Trim()
            $json=@{paths=$paths;game=[string]$form.Game.SelectedItem;shortcutAsked=$script:shortcutAsked}|ConvertTo-Json -Depth 5
            $temp=Join-Path $settingsDir ('settings-'+[guid]::NewGuid().ToString('N')+'.tmp')
            [IO.File]::WriteAllText($temp,$json,(New-Object Text.UTF8Encoding($false)))
            if([IO.File]::Exists($settingsPath)){[IO.File]::Replace($temp,$settingsPath,[NullString]::Value)}else{[IO.File]::Move($temp,$settingsPath)}
        } catch {Write-WarpathLog ('Save settings: '+$_);$form.Status.Text="Couldn't remember your folder. You can still use it this time.";$form.Status.ForeColor=[Warpath.Theme]::Warning}
    }
    function Get-VisibleEntries {
        @($entries | Where-Object {$_.game -eq [string]$form.Game.SelectedItem -and ($script:ownerMode -or (Test-PublicEntry $_ $script:catalog))})
    }
    function Update-Action {
        if($script:busy){return}
        $rows=@($form.Addons.Rows)
        $installed=@($rows|Where-Object {$_.Installed})
        $updates=@($rows|Where-Object {$_.Installed -and $_.Needs})
        $pending=@($rows|Where-Object {$_.Checked -and $_.Needs})
        $form.Action.AllSet=$false;$form.Action.Enabled=$rows.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($form.Folder.Text)
        if($rows.Count -eq 0){$form.Action.Text='NO ADDONS SHARED YET';$form.Action.Enabled=$false}
        elseif($installed.Count -eq $rows.Count -and @($rows|Where-Object {-not $_.Verified}).Count -eq 0) {
            $form.Action.Text="✓  YOU'RE ALL SET";$form.Action.AllSet=$true;$form.Action.Enabled=$false
        } elseif($updates.Count -gt 0){$form.Action.Text='▶  CLICK HERE TO UPDATE ('+$updates.Count+')'}
        elseif($pending.Count -gt 0 -or $installed.Count -eq 0){$form.Action.Text='▶  CLICK HERE TO INSTALL'}
        elseif(@($rows|Where-Object {$_.Installed -and -not $_.Verified}).Count -gt 0){$form.Action.Text='▶  CLICK HERE TO CHECK'}
        else{$form.Action.Text='CHOOSE AN ADDON ABOVE';$form.Action.Enabled=$false}
        $form.Action.Invalidate()
    }
    function Refresh-Addons([bool]$Preserve=$false) {
        $selected=@{};if($Preserve){foreach($row in $form.Addons.Rows){$selected[$row.Repo]=$row.Checked}}
        $form.Addons.ClearRows()
        foreach($a in @(Get-VisibleEntries)) {
            $sha=if($remote.ContainsKey($a.repo)){$remote[$a.repo]}else{''}
            $state=Get-InstallState $form.Folder.Text.Trim() $a $sha
            $status=if($state.linked){'Linked (dev)'}elseif(-not $state.installed){'Not installed'}elseif($sha -and $state.needs){'Update ready'}else{'Installed'}
            # Only addons you already have are ticked for updates; new ones stay unticked until you choose them.
            $checked=[bool]$state.installed -and [bool]$state.needs;if($Preserve -and $selected.ContainsKey($a.repo)){$checked=[bool]$selected[$a.repo]}
            if($state.linked){$checked=$false}
            $row=New-Object Warpath.AddonRow($a.repo,$a.name,$a.description,$status,$checked,(-not (Test-PublicEntry $a $script:catalog)),[bool]$state.installed,[bool]$state.needs,[bool]$state.verified)
            $form.Addons.AddRow($row)
        }
        Update-Action
    }
    function Update-FolderCheck {
        if($form.Folder.Text.Trim().TrimEnd('\','/') -match '(?i)(^|[\\/])Interface[\\/]AddOns$') {
            $form.FolderCheck.Text='✓ Folder looks right';$form.FolderCheck.ForeColor=[Warpath.Theme]::Success
        }else{$form.FolderCheck.Text="⚠ This doesn't look like an AddOns folder (…\Interface\AddOns). You can still use it.";$form.FolderCheck.ForeColor=[Warpath.Theme]::Warning}
    }
    function Set-Busy([bool]$Value) {
        $script:busy=$Value
        foreach($c in @($form.Game,$form.Folder,$form.Browse,$form.Addons,$form.Check,$form.OwnerLink,$form.Lock,$form.EditCatalog)){$c.Enabled=-not $Value}
        $form.Action.Enabled=-not $Value
        if(-not $Value){Update-Action}
    }
    # ---------------- Anonymous statistics ----------------
    function Get-AnalyticsPaths {
        $p=@{};foreach($k in @($paths.Keys)){$p[$k]=[string]$paths[$k]}
        try{$p[[string]$form.Game.SelectedItem]=$form.Folder.Text.Trim()}catch{}
        $p
    }
    function Start-AnalyticsJob([string]$Action) {
        # Background only: the window never waits on the statistics server.
        if(-not $script:analytics -or $script:analyticsJob){return}
        try {
            $sources=@()
            if($Action -eq 'send') {
                if(-not (Test-WarpathAnalyticsOn $script:analytics) -or @($script:analytics.outbox).Count -eq 0){return}
                $sources=@(Get-WarpathInstalledAddons (Get-AnalyticsPaths)|ForEach-Object {@{game=$_.game;repo=$_.repo;addon=$_.addon;addOns=$_.addOns}})
            }
            $ps=[PowerShell]::Create()
            [void]$ps.AddScript('param($core,$an,$action,$root,$id,$ver,$outbox,$sources) . $core; . $an; Invoke-WarpathAnalyticsJob $action $root $id $ver $outbox $sources')
            [void]$ps.AddArgument((Join-Path $root 'Warpath.Core.ps1')).AddArgument($analyticsFile).AddArgument($Action).AddArgument($root)
            [void]$ps.AddArgument([string]$script:analytics.installId).AddArgument([string]$script:appVersion).AddArgument(@($script:analytics.outbox)).AddArgument($sources)
            $script:analyticsJob=@{ps=$ps;handle=$ps.BeginInvoke();action=$Action}
        } catch {Write-WarpathLog ('Analytics start: '+$_);$script:analyticsJob=$null}
    }
    function Complete-AnalyticsJob {
        $j=$script:analyticsJob;if(-not $j -or -not $j.handle.IsCompleted){return}
        $script:analyticsJob=$null
        try {
            $r=@($j.ps.EndInvoke($j.handle))|Select-Object -Last 1
            if($j.action -eq 'send') {
                Complete-WarpathAnalyticsSend $script:analytics $r
                if($r -and -not $r.ok -and $r.error -ne 'no-endpoint'){Write-WarpathLog ('Statistics not sent yet: '+$r.error)}
            } elseif($j.action -eq 'delete') {
                if($r -and $r.ok) {
                    $script:analytics.pendingDelete=$false;$script:analytics.known=@{};$script:analytics.lastCheckin='';$script:analytics.outbox=@()
                    Save-WarpathAnalytics $script:analytics
                    $form.Status.Text='Your anonymous statistics were deleted from the server.';$form.Status.ForeColor=[Warpath.Theme]::Success
                } else {
                    Write-WarpathLog ('Statistics delete: '+$(if($r){$r.error}else{'no result'}))
                    $form.Status.Text="Couldn't reach the statistics server to delete your data. Warpath will try again next time it opens.";$form.Status.ForeColor=[Warpath.Theme]::Warning
                }
            }
        } catch {Write-WarpathLog ('Analytics result: '+$_)}
        finally {try{$j.ps.Dispose()}catch{}}
        # A deletion asked for while a send was running goes right after it (once per session).
        if($script:analytics -and $script:analytics.pendingDelete -and -not $script:analyticsDeleteTried){$script:analyticsDeleteTried=$true;Start-AnalyticsJob 'delete'}
    }
    function Invoke-AnalyticsStartup {
        if(-not $script:analytics){return}
        try {
            if(Test-WarpathOwnerCopy $root){if(Set-WarpathOwnerExcluded $script:analytics){$script:analyticsDeleteTried=$true;Start-AnalyticsJob 'delete'};return}
            if($script:analytics.pendingDelete){$script:analyticsDeleteTried=$true;Start-AnalyticsJob 'delete';return}
            [void](Invoke-WarpathAnalyticsStartup $script:analytics (Get-AnalyticsPaths))
            Start-AnalyticsJob 'send'
        } catch {Write-WarpathLog ('Analytics startup: '+$_)}
    }
    function Register-AnalyticsInstall([string]$Repo) {
        # Called for each addon the worker finished installing. Never interrupts the install.
        if(-not $script:analytics){return}
        try {
            if(-not (Test-WarpathAnalyticsOn $script:analytics)){return}
            $entry=@($entries|Where-Object {$_.game -eq $script:workGame -and $_.repo -eq $Repo})
            if($entry.Count -ne 1){return}
            $name=Get-AddonFolder $entry[0]
            $version=Get-TocVersion (Join-Path $script:workFolder $name) $name
            $type=if($script:preInstalled.ContainsKey($Repo)){'update'}else{'install'}
            if(Register-WarpathAddonChange $script:analytics $type $script:workGame $Repo $version){Save-WarpathAnalytics $script:analytics}
        } catch {Write-WarpathLog ('Analytics install: '+$_)}
    }
    function Show-AnalyticsNotice {
        # Shown once. Statistics are always on; this only tells the player what is sent.
        $d=New-Object Warpath.DarkForm;$d.Text='Anonymous statistics';$d.ClientSize=New-Object Drawing.Size(580,380);$d.StartPosition='CenterParent'
        $t=[Warpath.Theme]::Label('ANONYMOUS STATISTICS',22,16,540,34);$t.Font=[Warpath.Theme]::Serif(16);$t.ForeColor=[Warpath.Theme]::Highlight;$d.Controls.Add($t)
        $body=[Warpath.Theme]::Label(("Warpath sends anonymous usage statistics to the VoidMark developer:`n"+
            "  • a random install number made on this PC`n  • Warpath's version`n"+
            "  • which VoidMark addons and versions you have, for Forever or Classic Era`n"+
            "  • when they were installed or updated, and (for addons that record it) when they were last used in game`n`n"+
            "Never sent: your name, characters, account, chat, gold, gameplay, IP address, PC or Windows user name, or file paths.`n`n"+
            "Details any time under Privacy at the bottom."),22,58,540,240)
        $d.Controls.Add($body)
        $ok=New-Object Warpath.PurpleButton;$ok.Text='OK';$ok.SetBounds(20,310,540,52);$ok.DialogResult='OK';$d.Controls.Add($ok)
        $d.AcceptButton=$ok;$d.CancelButton=$ok
        try{[void]$d.ShowDialog($form)}finally{$d.Dispose()}
    }
    function Show-PrivacyDialog {
        if(-not $script:analytics){Show-WarpathNote "Anonymous statistics aren't available in this copy of Warpath. Nothing is being sent." 'Privacy';return}
        Show-WarpathNote ("Warpath sends anonymous statistics: a random install number, its version, and which VoidMark addons and versions you have "+
            "(installs, updates, a daily check-in, and for addons that record it, when they were last used in game). "+
            "No names, characters, accounts, gameplay, IP addresses, PC names or file paths.`n`nYour install number: "+
            $script:analytics.installId.Substring(0,8)+"… (random, made on this PC)") 'Privacy'
    }
    function Start-Work([string]$Action,$WorkEntries) {
        if($script:busy){return}
        if($Action -eq 'install') {
            # Remember what was already installed so statistics can tell installs from updates.
            $script:preInstalled=@{};foreach($row in $form.Addons.Rows){if($row.Installed){$script:preInstalled[$row.Repo]=$true}}
            $script:workGame=[string]$form.Game.SelectedItem;$script:workFolder=$form.Folder.Text.Trim()
        }
        Save-Settings;$script:jobError='';$form.Done.Text='';$form.Status.ForeColor=[Warpath.Theme]::Text;$form.Progress.Value=0
        Set-Busy $true
        $form.Action.AllSet=$false;$form.Action.Text=if($Action -eq 'check'){'CHECKING FOR UPDATES…'}elseif($Action -eq 'selfupdate'){'UPDATING WARPATH…'}else{'INSTALLING… 0%'}
        $queue=New-Object 'Collections.Concurrent.ConcurrentQueue[object]'
        $ps=[PowerShell]::Create()
        [void]$ps.AddScript('param($core,$action,$entries,$destination,$queue,$owner,$catalog,$appRoot,$expected) . $core; Invoke-WarpathWorker $action $entries $destination $queue $owner $catalog $appRoot $expected')
        [void]$ps.AddArgument((Join-Path $root 'Warpath.Core.ps1')).AddArgument($Action).AddArgument(@($WorkEntries)).AddArgument($form.Folder.Text.Trim()).AddArgument($queue)
        [void]$ps.AddArgument([bool]$script:ownerMode).AddArgument(@($script:catalog)).AddArgument($root).AddArgument([string]$script:remoteVersion)
        try {$handle=$ps.BeginInvoke();$script:job=@{ps=$ps;handle=$handle;queue=$queue;action=$Action;complete=$false}}
        catch{$ps.Dispose();Write-WarpathLog ($_|Out-String);Set-Busy $false;$form.Status.Text=Get-FriendlyError $_;$form.Status.ForeColor=[Warpath.Theme]::Error}
    }
    function Check-Updates {Start-Work check @($entries | Where-Object {$_.game -eq [string]$form.Game.SelectedItem})}
    function Start-AppUpdate {
        if(Show-WarpathAsk ("A new VoidMark Warpath is ready (v"+$script:remoteVersion+").`n`nUpdate and restart now? Your folders and installed addons stay as they are.") 'Warpath update' 'Update now' 'Later' $form) {Start-Work selfupdate @()}
        else {$updateLink.Text='⬆ Update to v'+$script:remoteVersion;$updateLink.Visible=$true}
    }
    function Get-PendingReports {
        $files=@();try{$files=@(Find-DebugSavedFiles $form.Folder.Text.Trim() ([string]$form.Game.SelectedItem))}catch{Write-WarpathLog ('Report scan: '+$_)}
        $errs=@();$notes=@()
        try{$errs=@(Get-NewVoidMarkErrors @(Get-VoidMarkErrors $files))}catch{Write-WarpathLog ('Report errors: '+$_)}
        try{$notes=@(Get-NewVoidMarkErrors @(Get-VoidMarkNotes $files))}catch{Write-WarpathLog ('Report notes: '+$_)}
        @{errors=$errs;notes=$notes}
    }
    function Send-PendingReport([string]$Url,[string]$Problem,[string]$Contact,$Errors,$Notes) {
        $Errors=@(@($Errors) | Where-Object {$null -ne $_});$Notes=@(@($Notes) | Where-Object {$null -ne $_})
        $game=[string]$form.Game.SelectedItem
        $who=if($Contact){$Contact}elseif(@($Notes).Count){$Notes[0].character}elseif(@($Errors).Count){$Errors[0].character}else{'someone'}
        $summary='**Problem report** from '+$who+' | '+$game+' | Warpath v'+$script:appVersion+' | '+@($Errors).Count+' error(s)'
        if(@($Errors).Count){$summary+=' ('+((@($Errors|ForEach-Object {$_.addon}|Sort-Object -Unique)) -join ', ')+')'}
        $quote=@();if($Problem){$quote+=$Problem};foreach($x in @($Notes)){$quote+=('(in game) '+$x.text)}
        if($quote.Count){$q=$quote -join "`n";if($q.Length -gt 900){$q=$q.Substring(0,900)+'…'};$summary+="`n>>> "+$q}
        $text=New-WarpathReportText $Problem $Contact $game $form.Folder.Text.Trim() $script:appVersion $Errors $Notes
        Send-WarpathReport $Url $summary $text
        $sent=@(@($Errors)+@($Notes));if($sent.Count){Save-ReportedErrors $sent}
    }
    function Get-ReportError($ErrorRecord) {
        $d=($ErrorRecord|Out-String)
        if($d -match 'VMW_REPORT (\d+)') {
            $code=[int]$Matches[1]
            if($code -in 401,403,404){return "The report link was turned off or deleted (Discord $code). Tell the owner."}
            if($code -eq 429){return 'Too many reports right now. Wait a minute and try again.'}
            return "Discord rejected the report (error $code). Tell the owner."
        }
        "Couldn't reach Discord. Check your internet and try again."
    }
    function Invoke-InGameReportOffer {
        # Problems the player wrote and saved in VoidMark Debug are sent automatically (they already
        # chose to report them in game). Runs after the first check and when Warpath regains focus.
        $script:lastNotesScan=Get-Date
        $pending=Get-PendingReports
        $fresh=@(@($pending.notes) | Where-Object {$null -ne $_ -and -not $script:notesFailed.ContainsKey($_.key)})
        if(-not $fresh.Count){return}
        $url=Get-WarpathReportUrl $root;if(-not $url){return}
        try {
            Send-PendingReport $url '' '' @($pending.errors) $fresh
            $form.Status.Text=('Sent your '+$fresh.Count+' problem report(s) from WoW to the owner. Thanks!');$form.Status.ForeColor=[Warpath.Theme]::Success
        } catch {
            Write-WarpathLog ('Auto report: '+($_|Out-String))
            foreach($x in $fresh){$script:notesFailed[$x.key]=$true}   # don't retry every focus; next launch tries again
            $form.Status.Text=(Get-ReportError $_)+' (problem report from WoW)';$form.Status.ForeColor=[Warpath.Theme]::Error
        }
    }
    function Show-ReportDialog {
        # Opens right away; the report address is only fetched when you press Send.
        $form.Cursor='WaitCursor';[Windows.Forms.Application]::DoEvents()
        $game=[string]$form.Game.SelectedItem;$addOns=$form.Folder.Text.Trim()
        try{$pending=Get-PendingReports}finally{$form.Cursor='Default'}
        $newErrors=@($pending.errors);$newNotes=@($pending.notes)
        $d=New-Object Warpath.DarkForm;$d.Text='Report a problem';$d.ClientSize=New-Object Drawing.Size(620,560);$d.StartPosition='CenterParent'
        $t=[Warpath.Theme]::Label('REPORT A PROBLEM',22,16,580,34);$t.Font=[Warpath.Theme]::Serif(17);$t.ForeColor=[Warpath.Theme]::Highlight;$d.Controls.Add($t)
        $d.Controls.Add([Warpath.Theme]::Label('What went wrong? What were you doing when it happened?',22,58,580,24))
        $desc=[Warpath.Theme]::TextBox(22,84,576);$desc.Multiline=$true;$desc.Height=190;$desc.ScrollBars='Vertical';$desc.AcceptsReturn=$true;$d.Controls.Add($desc)
        if($newNotes.Count){$desc.Text=(@($newNotes|ForEach-Object {$_.text}) -join "`r`n")}
        $d.Controls.Add([Warpath.Theme]::Label('Your Discord name, so the owner can reply (optional):',22,286,580,24))
        $contact=[Warpath.Theme]::TextBox(22,312,576);$d.Controls.Add($contact)
        $attach=New-Object Windows.Forms.CheckBox;$attach.SetBounds(22,356,576,26);$attach.ForeColor=[Warpath.Theme]::Text;$attach.BackColor=[Drawing.Color]::Transparent;$attach.FlatStyle='Flat';$attach.Font=New-Object Drawing.Font('Segoe UI',10.5)
        $hint=[Warpath.Theme]::Label('',44,384,556,44);$hint.ForeColor=[Warpath.Theme]::Secondary
        if($newErrors.Count -gt 0) {
            $names=(@($newErrors|ForEach-Object {$_.addon}|Sort-Object -Unique)) -join ', '
            $attach.Text='Attach VoidMark error logs ('+$newErrors.Count+' new: '+$names+')';$attach.Checked=$true
            $hint.Text='Only VoidMark errors are sent, plus which VoidMark addons you have installed.'
        } else {
            $attach.Text='Attach VoidMark error logs (none new found)';$attach.Checked=$false;$attach.Enabled=$false
            $hint.Text='Tip: if you just got an error, type /reload in WoW (or log out) so it gets saved, then open this again.'
        }
        $d.Controls.Add($attach);$d.Controls.Add($hint)
        $msg=[Warpath.Theme]::Label('',22,432,576,26);$msg.ForeColor=[Warpath.Theme]::Error;$d.Controls.Add($msg)
        $send=New-Object Warpath.PurpleButton;$send.Text='SEND';$send.Font=[Warpath.Theme]::Serif(14);$send.SetBounds(20,470,370,58);$d.Controls.Add($send)
        $cancel=New-Object Warpath.PurpleButton;$cancel.Text='Cancel';$cancel.SetBounds(402,470,198,58);$cancel.DialogResult='Cancel';$d.Controls.Add($cancel);$d.CancelButton=$cancel
        $send.Add_Click({
            $problem=$desc.Text.Trim();$attached=@();if($attach.Checked){$attached=@($newErrors)}
            if(-not $problem -and $attached.Count -eq 0){$msg.Text='Please describe the problem first.';return}
            # In-game notes were pre-filled into the box; send the box text and mark the notes as sent.
            $notesSent=@();if($newNotes.Count -and $problem -eq ((@($newNotes|ForEach-Object {$_.text}) -join "`r`n").Trim())){$problem='';$notesSent=@($newNotes)}
            $send.Enabled=$false;$cancel.Enabled=$false;$msg.ForeColor=[Warpath.Theme]::Secondary;$msg.Text='Sending…';$d.Cursor='WaitCursor';[Windows.Forms.Application]::DoEvents()
            $url=Get-WarpathReportUrl $root
            if(-not $url){$msg.ForeColor=[Warpath.Theme]::Error;$msg.Text="Couldn't get the report link. Check your internet, or message the owner on Discord.";$send.Enabled=$true;$cancel.Enabled=$true;$d.Cursor='Default';return}
            try {
                Send-PendingReport $url $problem $contact.Text.Trim() $attached $notesSent
                # If they edited the pre-filled in-game text, their edit was sent instead; don't offer those notes again.
                if($newNotes.Count){Save-ReportedErrors $newNotes}
                $d.DialogResult='OK';$d.Close()
            } catch {
                Write-WarpathLog ('Report send: '+($_|Out-String))
                $msg.ForeColor=[Warpath.Theme]::Error;$msg.Text=Get-ReportError $_
                $send.Enabled=$true;$cancel.Enabled=$true;$d.Cursor='Default'
            }
        })
        try{$r=$d.ShowDialog($form)}finally{$d.Dispose()}
        if($r -eq [Windows.Forms.DialogResult]::OK){$form.Status.Text='Report sent. Thanks! The owner will take a look.';$form.Status.ForeColor=[Warpath.Theme]::Success}
    }
    $poll=New-Object Windows.Forms.Timer;$poll.Interval=80
    $poll.Add_Tick({
        if($script:analyticsJob){Complete-AnalyticsJob}
        if(-not $script:job){return}
        $event=$null
        while($script:job.queue.TryDequeue([ref]$event)) {
            switch($event.type) {
                progress {
                    $form.Progress.Value=[int]$event.data.percent;$form.Status.Text=[string]$event.data.text
                    if($script:job.action -eq 'install'){$form.Action.Text='INSTALLING… '+$form.Progress.Value+'%'}
                }
                remote {$script:remote[[string]$event.data.repo]=[string]$event.data.sha}
                installed {$script:remote[[string]$event.data.repo]=[string]$event.data.sha;Register-AnalyticsInstall ([string]$event.data.repo)}
                catalog {
                    $script:catalog=@($event.data.items)
                    try{[IO.Directory]::CreateDirectory((Split-Path $catalogCache -Parent))|Out-Null;[IO.File]::WriteAllText($catalogCache,(ConvertTo-Json -InputObject @($script:catalog) -Depth 4))}catch{Write-WarpathLog ('Catalog cache: '+$_)}
                }
                appversion {$script:remoteVersion=[string]$event.data.version}
                error {$script:jobError=[string]$event.data}
                complete {$script:job.complete=$true;$script:job.success=[bool]$event.data.success}
            }
        }
        if($script:job.handle.IsCompleted) {
            $ok=$false;$action=$script:job.action
            try {
                [void]$script:job.ps.EndInvoke($script:job.handle)
                if($script:job.ps.Streams.Error.Count -gt 0){throw $script:job.ps.Streams.Error[0]}
                $ok=$script:job.complete -and $script:job.success
            } catch {Write-WarpathLog ($_|Out-String);$script:jobError=Get-FriendlyError $_}
            finally{$script:job.ps.Dispose();$script:job=$null}
            Set-Busy $false;Refresh-Addons
            if($ok -and $action -eq 'selfupdate') {
                # New files are in place: relaunch through the normal launcher and close this window.
                try{Start-Process -FilePath (Join-Path $env:WINDIR 'System32\wscript.exe') -ArgumentList ('"'+(Join-Path $root 'Launch-VoidMark-Warpath.vbs')+'"')}catch{Write-WarpathLog ('Relaunch: '+$_)}
                $form.Close();return
            }
            if($action -eq 'install'){Start-AnalyticsJob 'send'}
            if($ok) {
                $form.Progress.Value=100;$form.Status.ForeColor=[Warpath.Theme]::Secondary
                if($action -eq 'install'){$form.Status.Text='Your selected addons are ready.';$form.Done.Text="DONE! Start WoW (or type /reload if it's already open)."}
                elseif($form.Addons.Rows.Count -eq 0){$form.Status.Text='No addons are shared for this game yet.'}
                else{$form.Status.Text='Checked! Choose addons above, then click the big purple button.'}
            }else{
                $form.Status.ForeColor=[Warpath.Theme]::Error
                $form.Status.Text=if($script:jobError){$script:jobError}else{"Couldn't finish. Please try again."}
            }
            if($action -eq 'check' -and -not $script:notesAsked){$script:notesAsked=$true;Invoke-InGameReportOffer}
            if($action -eq 'check' -and $script:remoteVersion -and -not $script:updateAsked -and
               (ConvertTo-WarpathVersion $script:remoteVersion) -gt (ConvertTo-WarpathVersion $script:appVersion)) {
                $script:updateAsked=$true;Start-AppUpdate
            }
        }
    })
    $folderDelay=New-Object Windows.Forms.Timer;$folderDelay.Interval=650
    $folderDelay.Add_Tick({$folderDelay.Stop();if(-not $script:busy){Save-Settings;Refresh-Addons}})
    $form.Folder.Add_TextChanged({Update-FolderCheck;$form.Done.Text='';$folderDelay.Stop();if(-not $script:busy){$folderDelay.Start()}})
    $form.Game.Add_SelectedIndexChanged({
        if($script:busy){return}
        $folderDelay.Stop()
        # The old game's folder has already been saved while typing/browsing.
        $paths[$script:lastGame]=$form.Folder.Text.Trim()
        $script:lastGame=[string]$form.Game.SelectedItem;$form.Folder.Text=[string]$paths[$script:lastGame]
        Save-Settings;Refresh-Addons
        if($form.Visible){Check-Updates}
    })
    $form.Browse.Add_Click({
        $d=New-Object Windows.Forms.FolderBrowserDialog;$d.Description='Choose Interface\AddOns, or a throwaway folder for testing.'
        $d.SelectedPath=$form.Folder.Text.Trim()
        try {
            if($d.ShowDialog($form) -eq 'OK') {
                $picked=$d.SelectedPath
                if(-not (Test-AddOnsPath $picked)) {
                    $msg="This folder doesn't look like a WoW AddOns folder:`n$picked`n`nWoW only loads addons from ...\Interface\AddOns. Use it anyway?"
                    if(-not (Show-WarpathAsk $msg 'Not an AddOns folder' 'Use it anyway' 'Pick again' $form)){return}
                }
                $form.Folder.Text=$picked;$folderDelay.Stop();Save-Settings;Refresh-Addons
            }
        }finally{$d.Dispose()}
    })
    $form.Addons.Add_SelectionChanged({Update-Action})
    $updateLink.Add_LinkClicked({if(-not $script:busy){Start-AppUpdate}})
    $shortcutLink.Add_LinkClicked({New-WarpathShortcut})
    $privacyLink.Add_LinkClicked({
        if($script:inDialog){return}
        $script:inDialog=$true
        try{Show-PrivacyDialog}catch{Write-WarpathLog ('Privacy dialog: '+($_|Out-String))}finally{$script:inDialog=$false}
    })
    # Opens even while Warpath is checking or installing (the click used to do
    # nothing then), and any failure is shown instead of silently ignored.
    $reportLink.Add_LinkClicked({
        if($script:inDialog){return}
        $script:inDialog=$true
        try{Show-ReportDialog}
        catch{Write-WarpathLog ('Report dialog: '+($_|Out-String));Show-WarpathNote ("Couldn't open the report window:`n"+$_.Exception.Message+"`n`nMessage the owner on Discord instead.") 'Report a problem'}
        finally{$script:inDialog=$false;$script:lastNotesScan=Get-Date}
    })
    $form.Add_Activated({
        if($script:busy -or $script:inDialog -or -not $script:notesAsked){return}
        if(((Get-Date)-$script:lastNotesScan).TotalSeconds -lt 15){return}
        $script:inDialog=$true;try{Invoke-InGameReportOffer}catch{Write-WarpathLog ('Focus report check: '+$_)}finally{$script:inDialog=$false;$script:lastNotesScan=Get-Date}
    })
    $form.Check.Add_LinkClicked({Check-Updates})
    $form.Action.Add_Click({
        if($script:busy){return};$folderDelay.Stop()
        try {Assert-SafePath $form.Folder.Text.Trim()}catch{$form.Status.Text=Get-FriendlyError $_;$form.Status.ForeColor=[Warpath.Theme]::Error;return}
        if(Get-Process -Name Wow,WowClassic,WowClassicT -ErrorAction SilentlyContinue){Show-WarpathNote 'WoW is running. You can continue, but close and reopen WoW if new addons do not appear.' 'WoW is open'}
        $wanted=@{}
        foreach($row in $form.Addons.Rows){if(($row.Checked -and $row.Needs) -or ($row.Installed -and $row.Needs)){$wanted[$row.Repo]=$true}}
        $workEntries=@(Get-VisibleEntries | Where-Object {$wanted.ContainsKey($_.repo)})
        if($workEntries.Count -eq 0){Check-Updates;return}
        Start-Work install $workEntries
    })
    $form.OwnerLink.Add_LinkClicked({
        if($script:ownerUnlocked -or [Warpath.OwnerGate]::Ask($form)){
            if(-not $script:ownerUnlocked){$script:ownerUnlocked=$true;Save-OwnerKey}
            $script:ownerMode=$true;$form.ShowOwner($true,$true);Refresh-Addons;Check-Updates
        }
    })
    # Switch between the owner view and exactly what friends see (public list, paused versions).
    $form.Lock.Add_LinkClicked({$script:ownerMode=-not $script:ownerMode;$form.ShowOwner($true,[bool]$script:ownerMode);Refresh-Addons;Check-Updates})
    $form.EditCatalog.Add_Click({
        $editor=Join-Path $root 'Owner-Catalog-Editor.ps1'
        if(-not [IO.File]::Exists($editor)){Show-WarpathNote 'The owner editor is not in this copy. Use your full owner package.';return}
        try {
            # Same process and already authenticated session; direct launch always gates.
            Show-WarpathCatalogEditor $form
            if([IO.File]::Exists($catalogCache)){$script:catalog=@(Get-PublicCatalog $catalogCache)}else{$script:catalog=@(Get-PublicCatalog (Join-Path $root 'public-catalog.json'))};Refresh-Addons
        } catch {Write-WarpathLog ($_|Out-String);Show-WarpathNote (Get-FriendlyError $_)}
    })
    $form.Analytics.Add_Click({
        if(-not (Get-Command Show-WarpathAnalyticsDashboard -ErrorAction SilentlyContinue)){Show-WarpathNote 'The analytics dashboard is not in this copy. Update Warpath.';return}
        try{Show-WarpathAnalyticsDashboard $form $root}catch{Write-WarpathLog ($_|Out-String);Show-WarpathNote "Couldn't open Analytics. Details are in warpath.log."}
    })
    $dashboardFunctions=Join-Path $root 'Warpath.Dashboard.ps1'
    if([IO.File]::Exists($dashboardFunctions)){try{. $dashboardFunctions}catch{Write-WarpathLog ('Dashboard load: '+$_)}}
    # Load only the editor function definitions. There is no command-line auth bypass.
    $editorFunctions=Join-Path $root 'Warpath.Editor.ps1'
    if([IO.File]::Exists($editorFunctions)){. $editorFunctions}
    $form.Add_FormClosing({param($sender,$eventArgs) if($script:busy){$eventArgs.Cancel=$true;$form.Status.Text='Please wait until the current step finishes before closing.'}else{Save-Settings}})
    $form.Add_Shown({
        $poll.Start()
        if(Get-Process -Name Wow,WowClassic,WowClassicT -ErrorAction SilentlyContinue){$form.WowWarning.Text='⚠ WoW is open. Restart it if new addons do not appear.'}
        if(-not $script:shortcutAsked) {
            $script:shortcutAsked=$true
            $lnk=Join-Path ([Environment]::GetFolderPath('Desktop')) 'VoidMark Warpath.lnk'
            if(-not [IO.File]::Exists($lnk) -and (Show-WarpathAsk 'Put a VoidMark Warpath icon on your desktop so you can open it with one click?' 'Desktop shortcut' 'Yes, add it' 'No thanks' $form)){New-WarpathShortcut}
            Save-Settings
        }
        # Statistics are always on. Tell the player once what is sent (also people who said No in 3.5.0).
        if($script:analytics -and $script:analytics.consent -ne 'on' -and -not (Test-WarpathOwnerCopy $root)) {
            try{Show-AnalyticsNotice;Set-WarpathAnalyticsConsent $script:analytics $true}catch{Write-WarpathLog ('Statistics notice: '+$_)}
        }
        Check-Updates
        Invoke-AnalyticsStartup
    })
    # Avoid overwriting the remembered selection with a blank folder on first bind.
    $initialGame=$script:lastGame;$form.Folder.Text=[string]$paths[$initialGame]
    $form.Game.SelectedItem=$initialGame;Update-FolderCheck;Refresh-Addons
    try{[void]$form.ShowDialog()}finally{$poll.Stop();$poll.Dispose();$folderDelay.Stop();$folderDelay.Dispose();$form.Dispose()}
} catch {
    Write-WarpathLog ($_|Out-String)
    if('Warpath.DarkForm' -as [type]){Show-WarpathNote "Couldn't open Warpath. Please extract all files again and try the launcher."}
    else {[Windows.Forms.MessageBox]::Show("Couldn't open Warpath. Please extract all files again and try the launcher.",'VoidMark Warpath')|Out-Null}
}
