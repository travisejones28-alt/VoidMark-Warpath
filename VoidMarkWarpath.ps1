#requires -version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Warpath.Core.ps1')
try {
    . (Join-Path $PSScriptRoot 'Warpath.Theme.ps1')
    $script:root=$PSScriptRoot
    $script:catalog=@(Get-PublicCatalog (Join-Path $root 'public-catalog.json'))
    $script:entries=@(Get-WarpathEntries)
    $script:ownerMode=$false;$script:busy=$false;$script:remote=@{};$script:job=$null;$script:jobError=''
    $settingsDir=Join-Path $env:APPDATA 'VoidMarkWarpath';$settingsPath=Join-Path $settingsDir 'settings.json'
    $script:paths=@{'WoW Forever'='';'WoW Classic Era'=''};$script:lastGame='WoW Forever'
    if([IO.File]::Exists($settingsPath)) {
        try {
            $cfg=[IO.File]::ReadAllText($settingsPath)|ConvertFrom-Json
            foreach($key in @($paths.Keys)){if($cfg.paths.$key){$paths[$key]=[string]$cfg.paths.$key}}
            if($cfg.PSObject.Properties['game'] -and $paths.ContainsKey([string]$cfg.game)){$script:lastGame=[string]$cfg.game}
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
    $art=Join-Path $root 'assets\voidmark_forever_header_2048x512.png'
    $icon=Join-Path $root 'assets\voidmark.ico'
    try{$form.ApplyArt($art,$icon)}catch{Write-WarpathLog ('Art: '+$_)}
    function Save-Settings {
        try {
            [IO.Directory]::CreateDirectory($settingsDir)|Out-Null
            $paths[[string]$form.Game.SelectedItem]=$form.Folder.Text.Trim()
            $json=@{paths=$paths;game=[string]$form.Game.SelectedItem}|ConvertTo-Json -Depth 5
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
            $status=if(-not $state.installed){'Not installed'}elseif($sha -and $state.needs){'Update ready'}else{'Installed'}
            $checked=[bool]$state.needs;if($Preserve -and $selected.ContainsKey($a.repo)){$checked=[bool]$selected[$a.repo]}
            $row=New-Object Warpath.AddonRow($a.repo,$a.name,$a.description,$status,$checked,(-not (Test-PublicEntry $a $script:catalog)),[bool]$state.installed,[bool]$state.needs,[bool]$state.verified)
            $form.Addons.AddRow($row)
        }
        Update-Action
    }
    function Update-FolderCheck {
        if($form.Folder.Text.Trim().TrimEnd('\','/') -match '(?i)(^|[\\/])Interface[\\/]AddOns$') {
            $form.FolderCheck.Text='✓ Folder looks right';$form.FolderCheck.ForeColor=[Warpath.Theme]::Success
        }else{$form.FolderCheck.Text="⚠ This doesn't look like an AddOns folder";$form.FolderCheck.ForeColor=[Warpath.Theme]::Warning}
    }
    function Set-Busy([bool]$Value) {
        $script:busy=$Value
        foreach($c in @($form.Game,$form.Folder,$form.Browse,$form.Addons,$form.Check,$form.OwnerLink,$form.Lock,$form.EditCatalog)){$c.Enabled=-not $Value}
        $form.Action.Enabled=-not $Value
        if(-not $Value){Update-Action}
    }
    function Start-Work([string]$Action,$WorkEntries) {
        if($script:busy){return}
        Save-Settings;$script:jobError='';$form.Done.Text='';$form.Status.ForeColor=[Warpath.Theme]::Text;$form.Progress.Value=0
        Set-Busy $true
        $form.Action.AllSet=$false;$form.Action.Text=if($Action -eq 'check'){'CHECKING FOR UPDATES…'}else{'INSTALLING… 0%'}
        $queue=New-Object 'Collections.Concurrent.ConcurrentQueue[object]'
        $ps=[PowerShell]::Create()
        [void]$ps.AddScript('param($core,$action,$entries,$destination,$queue) . $core; Invoke-WarpathWorker $action $entries $destination $queue')
        [void]$ps.AddArgument((Join-Path $root 'Warpath.Core.ps1')).AddArgument($Action).AddArgument(@($WorkEntries)).AddArgument($form.Folder.Text.Trim()).AddArgument($queue)
        try {$handle=$ps.BeginInvoke();$script:job=@{ps=$ps;handle=$handle;queue=$queue;action=$Action;complete=$false}}
        catch{$ps.Dispose();Write-WarpathLog ($_|Out-String);Set-Busy $false;$form.Status.Text=Get-FriendlyError $_;$form.Status.ForeColor=[Warpath.Theme]::Error}
    }
    function Check-Updates {Start-Work check @(Get-VisibleEntries)}
    $poll=New-Object Windows.Forms.Timer;$poll.Interval=80
    $poll.Add_Tick({
        if(-not $script:job){return}
        $event=$null
        while($script:job.queue.TryDequeue([ref]$event)) {
            switch($event.type) {
                progress {
                    $form.Progress.Value=[int]$event.data.percent;$form.Status.Text=[string]$event.data.text
                    if($script:job.action -eq 'install'){$form.Action.Text='INSTALLING… '+$form.Progress.Value+'%'}
                }
                remote {$script:remote[[string]$event.data.repo]=[string]$event.data.sha}
                installed {$script:remote[[string]$event.data.repo]=[string]$event.data.sha}
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
            if($ok) {
                $form.Progress.Value=100;$form.Status.ForeColor=[Warpath.Theme]::Secondary
                if($action -eq 'install'){$form.Status.Text='Your selected addons are ready.';$form.Done.Text="DONE! Start WoW (or type /reload if it's already open)."}
                elseif($form.Addons.Rows.Count -eq 0){$form.Status.Text='No addons are shared for this game yet.'}
                else{$form.Status.Text='Checked! Choose addons above, then click the big purple button.'}
            }else{
                $form.Status.ForeColor=[Warpath.Theme]::Error
                $form.Status.Text=if($script:jobError){$script:jobError}else{"Couldn't finish. Please try again."}
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
        try {if($d.ShowDialog($form) -eq 'OK'){$form.Folder.Text=$d.SelectedPath;$folderDelay.Stop();Save-Settings;Refresh-Addons}}finally{$d.Dispose()}
    })
    $form.Addons.Add_SelectionChanged({Update-Action})
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
        if([Warpath.OwnerGate]::Ask($form)){$script:ownerMode=$true;$form.ShowOwner($true);Refresh-Addons;Check-Updates}
    })
    $form.Lock.Add_LinkClicked({$script:ownerMode=$false;$form.ShowOwner($false);$script:catalog=@(Get-PublicCatalog (Join-Path $root 'public-catalog.json'));Refresh-Addons;Check-Updates})
    $form.EditCatalog.Add_Click({
        $editor=Join-Path $root 'Owner-Catalog-Editor.ps1'
        if(-not [IO.File]::Exists($editor)){Show-WarpathNote 'The owner editor is not in this copy. Use your full owner package.';return}
        try {
            # Same process and already authenticated session; direct launch always gates.
            Show-WarpathCatalogEditor $form
            $script:catalog=@(Get-PublicCatalog (Join-Path $root 'public-catalog.json'));Refresh-Addons
        } catch {Write-WarpathLog ($_|Out-String);Show-WarpathNote (Get-FriendlyError $_)}
    })
    # Load only the editor function definitions. There is no command-line auth bypass.
    $editorFunctions=Join-Path $root 'Warpath.Editor.ps1'
    if([IO.File]::Exists($editorFunctions)){. $editorFunctions}
    $form.Add_FormClosing({param($sender,$eventArgs) if($script:busy){$eventArgs.Cancel=$true;$form.Status.Text='Please wait until the current step finishes before closing.'}else{Save-Settings}})
    $form.Add_Shown({
        $poll.Start()
        if(Get-Process -Name Wow,WowClassic,WowClassicT -ErrorAction SilentlyContinue){$form.WowWarning.Text='⚠ WoW is open. Restart it if new addons do not appear.'}
        Check-Updates
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
