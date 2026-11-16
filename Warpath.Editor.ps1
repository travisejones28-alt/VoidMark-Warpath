# Definitions only; called by an authenticated updater session or gated launcher.
function Show-WarpathCatalogEditor($ParentWindow) {
    $editorRoot=$PSScriptRoot
    $editorEntries=@(Get-WarpathEntries)
    $catalogFile=Join-Path $editorRoot 'public-catalog.json'
    # The live catalog (last downloaded or saved) beats the repo copy on disk, which only
    # changes when you pull. Saving no longer touches the repo folder.
    $catalogCache=Join-Path (Join-Path $env:APPDATA 'VoidMarkWarpath') 'catalog-cache.json'
    $approved=@()
    if([IO.File]::Exists($catalogCache)){$approved=@(Get-PublicCatalog $catalogCache)}
    if($approved.Count -eq 0){$approved=@(Get-PublicCatalog $catalogFile)}
    $window=New-Object Warpath.DarkForm;$window.Text='VoidMark Warpath — Public catalog';$window.ClientSize=New-Object Drawing.Size(710,716)
    $title=[Warpath.Theme]::Label('CHOOSE WHAT FRIENDS GET',22,18,660,35);$title.Font=[Warpath.Theme]::Serif(17);$title.ForeColor=[Warpath.Theme]::Highlight;$window.Controls.Add($title)
    $note=[Warpath.Theme]::Label('Checked = friends can install it. Tick Pause @ to keep friends on that version while you keep pushing.',22,56,660,40);$window.Controls.Add($note)
    $rows=New-Object Warpath.AddonList;$rows.RowHeight=54;$rows.SetBounds(22,102,666,360);$window.Controls.Add($rows)
    $hookFile=Join-Path $editorRoot 'report-hook.txt'
    $hookLabel=[Warpath.Theme]::Label('Problem reports go to this Discord webhook (saved scrambled so GitHub bots can''t spot it):',22,470,666,24);$hookLabel.ForeColor=[Warpath.Theme]::Secondary;$window.Controls.Add($hookLabel)
    $hookBox=[Warpath.Theme]::TextBox(22,496,666);$hookBox.UseSystemPasswordChar=$true;$window.Controls.Add($hookBox)
    if([IO.File]::Exists($hookFile)){$hookBox.Text=ConvertFrom-WarpathHook ([IO.File]::ReadAllText($hookFile))}
    $hookLoaded=$hookBox.Text.Trim()
    # GitHub key: lets Save publish to GitHub itself, no GitHub Desktop.
    $hasToken=[bool](Get-OwnerGitHubToken)
    $tokenLabel=[Warpath.Theme]::Label($(if($hasToken){'GitHub key saved on this PC: Save publishes straight to GitHub. Paste a new key only to replace it.'}else{'GitHub key (one time): paste it so Save publishes straight to GitHub, no GitHub Desktop.'}),22,530,666,24)
    $tokenLabel.ForeColor=$(if($hasToken){[Warpath.Theme]::Success}else{[Warpath.Theme]::Warning});$window.Controls.Add($tokenLabel)
    $tokenBox=[Warpath.Theme]::TextBox(22,556,666);$tokenBox.UseSystemPasswordChar=$true;$window.Controls.Add($tokenBox)
    # Paused addons: repo -> @{sha;label=version}. Friends get that version; you keep getting main.
    $held=@{}
    foreach($a in $editorEntries) {
        $pin=Get-PinnedSha $a $approved
        if($pin){
            $label='';foreach($c in $approved){if($c.repo -eq $a.repo -and $c.game -eq $a.game){$label=[string](Get-WarpathField $c 'label')}}
            if(-not $label){$label=$pin.Substring(0,7)}
            $held[$a.repo]=@{sha=$pin;label=$label}
        }
        $desc=if($pin){'Paused at '+$held[$a.repo].label}else{$a.game}
        $row=New-Object Warpath.AddonRow($a.repo,$a.name,$desc,$(if($pin){'Paused'}else{'Public'}),(Test-PublicEntry $a $approved),$false,$false,$false,$false)
        $row.ShowPause=$true;$row.Paused=[bool]$pin;if($pin){$row.PauseVersion=$held[$a.repo].label}
        $rows.AddRow($row)
    }
    # Pause @ version: tick on a row to keep friends on that version; click again to unpause.
    # repo -> @{sha;label} of the newest version on GitHub. Read in the background when
    # this window opens: doing it on the window's thread froze it (looked like a crash).
    $script:pauseFor=@{};$script:pauseLoaded=$false
    $loader=[PowerShell]::Create()
    [void]$loader.AddScript({
        param($core,$entries)
        . $core
        [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;$ProgressPreference='SilentlyContinue'
        foreach($a in $entries) {
            try {$sha=(Get-RemoteSha $a.repo).ToLower();[pscustomobject]@{repo=$a.repo;sha=$sha;label=(Get-AddonVersionAt $a $sha)}}
            catch {[pscustomobject]@{repo=$a.repo;sha='';label='';error=[string]$_}}
        }
    }.ToString()).AddArgument((Join-Path $editorRoot 'Warpath.Core.ps1')).AddArgument(@($editorEntries))
    $loadHandle=$loader.BeginInvoke()
    $loadTimer=New-Object Windows.Forms.Timer;$loadTimer.Interval=250
    $window.add_Shown({$loadTimer.Start()})
    $loadTimer.add_Tick({
        if(-not $loadHandle.IsCompleted){return}
        $loadTimer.Stop()
        try {
            foreach($r in @($loader.EndInvoke($loadHandle))) {
                if($r.sha){$script:pauseFor[[string]$r.repo]=@{sha=[string]$r.sha;label=[string]$r.label}}
                elseif($r.error){Write-WarpathLog ('Pause version '+$r.repo+': '+$r.error)}
            }
        } catch {Write-WarpathLog ('Pause versions: '+$_)}
        $script:pauseLoaded=$true
        # Unpaused rows show the version they'd pause at.
        for($k=0;$k -lt $editorEntries.Count;$k++){
            $rr=$rows.Rows[$k];$now=$script:pauseFor[$editorEntries[$k].repo]
            if(-not $rr.Paused){$rr.PauseVersion=$(if($now){$now.label}else{'?'})}
        }
        $rows.Invalidate()
    })
    $rows.add_PauseClick({
        param($index)
        $a=$editorEntries[$index];$row=$rows.Rows[$index]
        if($row.Paused) {
            $held.Remove($a.repo);$row.Paused=$false;$row.Status='Public';$row.Description=$a.game
            $now=$script:pauseFor[$a.repo];$row.PauseVersion=$(if($now){$now.label}elseif($script:pauseLoaded){'?'}else{''})
            $status.Text=$a.name+' unpaused: friends get the newest. Click Save, then push.'
        } else {
            $now=$script:pauseFor[$a.repo]
            if(-not $now){$status.Text=$(if($script:pauseLoaded){'Could not read '+$a.name+'''s version from GitHub. Reopen this window to try again.'}else{'Still reading versions from GitHub. Try again in a moment.'});return}
            $held[$a.repo]=@{sha=$now.sha;label=$now.label}
            $row.Paused=$true;$row.PauseVersion=$now.label;$row.Status='Paused';$row.Description='Paused at '+$now.label
            $status.Text=$a.name+' paused @ '+$now.label+'. Click Save, then push.'
        }
        $rows.Invalidate()
    })
    $window.add_FormClosed({$loadTimer.Stop();$loadTimer.Dispose();try{if(-not $loadHandle.IsCompleted){[void]$loader.BeginStop($null,$null)}else{$loader.Dispose()}}catch{}})
    $save=New-Object Warpath.PurpleButton;$save.Text='Save';$save.SetBounds(18,594,674,58);$window.Controls.Add($save)
    $status=[Warpath.Theme]::Label('Tick an addon and Save to share it.',22,660,666,48);$status.ForeColor=[Warpath.Theme]::Secondary;$window.Controls.Add($status)
    $save.Add_Click({
        $save.Enabled=$false;$rows.Enabled=$false
        $stage=$null
        try {
            $selected=@()
            for($i=0;$i -lt $editorEntries.Count;$i++) {
                if($rows.Rows[$i].Checked){
                    $o=[ordered]@{game=$editorEntries[$i].game;repo=$editorEntries[$i].repo}
                    $h=$held[$editorEntries[$i].repo];if($h){$o.sha=$h.sha;$o.label=$h.label}
                    $selected+=$o
                }
            }
            $hook=$hookBox.Text.Trim()
            if($hook -and $hook -notmatch '^https://(discord\.com|discordapp\.com)/api/webhooks/\d+/[\w-]+$'){throw 'VMW_HOOK'}
            $json=ConvertTo-Json -InputObject @($selected) -Depth 4
            $newToken=$tokenBox.Text.Trim()
            if($newToken){Save-OwnerGitHubToken $newToken;$tokenBox.Clear()}
            $token=Get-OwnerGitHubToken
            if(-not $token){throw 'VMW_NOKEY'}
            # Publish straight to GitHub. Your repo folder isn't touched, so GitHub
            # Desktop has nothing to commit; the next pull just brings it down.
            $status.ForeColor=[Warpath.Theme]::Secondary;$status.Text='Publishing to GitHub...';$window.Refresh()
            $paused=@($selected|Where-Object{$_.Contains('sha')}|ForEach-Object{($_.repo -replace '^VoidMark-','')+' @ '+$_.label})
            $msg='Catalog: '+$selected.Count+' shared'+$(if($paused.Count){'; paused '+($paused -join ', ')}else{''})
            try {
                Publish-WarpathRepoFile 'public-catalog.json' $json $token $msg
                if($hook -ne $hookLoaded){Publish-WarpathRepoFile 'report-hook.txt' $(if($hook){ConvertTo-WarpathHook $hook}else{$null}) $token 'Problem report link updated';$hookLoaded=$hook}
            } catch {
                $code=0;try{$code=[int]$_.Exception.Response.StatusCode}catch{}
                if($code -eq 401 -or $code -eq 403 -or $code -eq 404){throw 'VMW_BADKEY'}
                throw 'VMW_PUBLISH'
            }
            $tokenLabel.Text='GitHub key saved on this PC: Save publishes straight to GitHub. Paste a new key only to replace it.';$tokenLabel.ForeColor=[Warpath.Theme]::Success
            # Also refresh the cached copy, so this Warpath shows the change right away
            # instead of the older list it last downloaded.
            try{$cache=Join-Path (Join-Path $env:APPDATA 'VoidMarkWarpath') 'catalog-cache.json';[IO.Directory]::CreateDirectory((Split-Path $cache -Parent))|Out-Null;[IO.File]::WriteAllText($cache,$json,(New-Object Text.UTF8Encoding($false)))}catch{Write-WarpathLog ('Catalog cache: '+$_)}
            $stage=Join-Path ([IO.Path]::GetTempPath()) ('stage-warpath-friends-'+[guid]::NewGuid().ToString('N'))
            Assert-SafePath $stage
            $package=Join-Path $stage 'VoidMarkWarpath';[IO.Directory]::CreateDirectory($package)|Out-Null
            foreach($name in @('VoidMarkWarpath.ps1','Warpath.Core.ps1','Warpath.Theme.ps1','Warpath.UI.cs','Warpath.Analytics.ps1','Launch-VoidMark-Warpath.vbs','public-catalog.json','README.md','version.txt')) {
                $sourceFile=Join-Path $editorRoot $name;Assert-SafePath $sourceFile
                Copy-Item -LiteralPath $sourceFile -Destination $package
            }
            $endpointSource=Join-Path $editorRoot 'analytics-endpoint.txt';if([IO.File]::Exists($endpointSource)){Copy-Item -LiteralPath $endpointSource -Destination $package}
            # The package gets the catalog and report link just published, not the repo copies.
            [IO.File]::WriteAllText((Join-Path $package 'public-catalog.json'),$json,(New-Object Text.UTF8Encoding($false)))
            $pkgHook=Join-Path $package 'report-hook.txt'
            if($hook){[IO.File]::WriteAllText($pkgHook,(ConvertTo-WarpathHook $hook),(New-Object Text.UTF8Encoding($false)))}elseif([IO.File]::Exists($pkgHook)){[IO.File]::Delete($pkgHook)}
            $assets=Join-Path $editorRoot 'assets'
            if([IO.Directory]::Exists($assets)){Assert-SafePath $assets -Tree;Copy-Item -LiteralPath $assets -Destination $package -Recurse}
            $zip=Join-Path $editorRoot 'VoidMarkWarpath-Friends-READY.zip';Assert-SafePath $zip
            # Include the named root folder, matching the existing friends package.
            $outerZip=Join-Path $editorRoot ('friends-'+[guid]::NewGuid().ToString('N')+'.tmp')
            try {
                $archive=[IO.Compression.ZipFile]::Open($outerZip,[IO.Compression.ZipArchiveMode]::Create)
                try {
                    foreach($f in @(Get-ChildItem -LiteralPath $package -File -Recurse -Force)) {
                        $relative='VoidMarkWarpath/'+$f.FullName.Substring($package.Length+1).Replace('\','/')
                        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$f.FullName,$relative)|Out-Null
                    }
                }finally{$archive.Dispose()}
                if([IO.File]::Exists($zip)){[IO.File]::Replace($outerZip,$zip,[NullString]::Value)}else{[IO.File]::Move($outerZip,$zip)}
            }finally{if([IO.File]::Exists($outerZip)){[IO.File]::Delete($outerZip)}}
            $status.ForeColor=[Warpath.Theme]::Success;$status.Text='Saved and live on GitHub. Friends get it the next time Warpath opens. Nothing to do in GitHub Desktop.'
        } catch {
            Write-WarpathLog ($_|Out-String);$status.ForeColor=[Warpath.Theme]::Error
            $err=($_|Out-String)
            $status.Text=if($err -match 'VMW_HOOK'){'That webhook link looks wrong. Copy it again from Discord (Edit Channel > Integrations > Webhooks).'}
                elseif($err -match 'VMW_NOKEY'){'Paste your GitHub key above first (one time), then Save.'}
                elseif($err -match 'VMW_BADKEY'){'GitHub refused the key. Make a new one with Contents: Read and write on VoidMark-Warpath, paste it, and Save.'}
                elseif($err -match 'VMW_PUBLISH'){'Could not reach GitHub. Nothing changed. Try Save again.'}
                else{'Published, but the friends ZIP could not be made. Friends already get the change through Warpath.'}
        } finally {
            if($stage){try{Remove-SafeStage ([IO.Path]::GetTempPath()) $stage}catch{Write-WarpathLog ('Export cleanup: '+$_)}}
            $save.Enabled=$true;$rows.Enabled=$true
        }
    })
    try{if($ParentWindow){[void]$window.ShowDialog($ParentWindow)}else{[void]$window.ShowDialog()}}finally{$window.Dispose()}
}
