# Definitions only; called by an authenticated updater session or gated launcher.
function Show-WarpathCatalogEditor($ParentWindow) {
    $editorRoot=$PSScriptRoot
    $editorEntries=@(Get-WarpathEntries)
    $catalogFile=Join-Path $editorRoot 'public-catalog.json'
    $approved=@(Get-PublicCatalog $catalogFile)
    $window=New-Object Warpath.DarkForm;$window.Text='VoidMark Warpath — Public catalog';$window.ClientSize=New-Object Drawing.Size(710,680)
    $title=[Warpath.Theme]::Label('CHOOSE WHAT FRIENDS GET',22,18,660,35);$title.Font=[Warpath.Theme]::Serif(17);$title.ForeColor=[Warpath.Theme]::Highlight;$window.Controls.Add($title)
    $note=[Warpath.Theme]::Label('Checked = friends can install it. Pause an addon below: friends stay on that version while you keep pushing.',22,56,660,40);$window.Controls.Add($note)
    $rows=New-Object Warpath.AddonList;$rows.RowHeight=54;$rows.SetBounds(22,102,666,300);$window.Controls.Add($rows)
    $hookFile=Join-Path $editorRoot 'report-hook.txt'
    $hookLabel=[Warpath.Theme]::Label('Problem reports go to this Discord webhook (saved scrambled so GitHub bots can''t spot it):',22,470,666,24);$hookLabel.Top=478;$hookLabel.ForeColor=[Warpath.Theme]::Secondary;$window.Controls.Add($hookLabel)
    $hookBox=[Warpath.Theme]::TextBox(22,504,666);$hookBox.UseSystemPasswordChar=$true;$window.Controls.Add($hookBox)
    if([IO.File]::Exists($hookFile)){$hookBox.Text=ConvertFrom-WarpathHook ([IO.File]::ReadAllText($hookFile))}
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
        $rows.AddRow($row)
    }
    # Pause: pick an addon, tick the box. Unticked = friends get the newest from GitHub.
    $pick=New-Object Warpath.GamePicker;$pick.Location=New-Object Drawing.Point(22,412);$pick.Size=New-Object Drawing.Size(300,34)
    foreach($a in $editorEntries){[void]$pick.Items.Add($a.name)}
    $window.Controls.Add($pick)
    $pause=New-Object Windows.Forms.CheckBox;$pause.Text='Pause updates at the current version';$pause.SetBounds(338,416,350,26)
    $pause.ForeColor=[Warpath.Theme]::Text;$pause.BackColor=[Warpath.Theme]::Window;$pause.FlatStyle='Flat';$pause.Enabled=$false
    $window.Controls.Add($pause)
    $pausedAt=[Warpath.Theme]::Label('Pick an addon to pause.',22,450,666,22);$pausedAt.ForeColor=[Warpath.Theme]::Secondary;$window.Controls.Add($pausedAt)
    $script:pauseSync=$false
    $showPause={
        $i=$pick.SelectedIndex;if($i -lt 0){return}
        $a=$editorEntries[$i];$h=$held[$a.repo]
        $script:pauseSync=$true;$pause.Enabled=$true;$pause.Checked=[bool]$h;$script:pauseSync=$false
        if($h){$pausedAt.ForeColor=[Warpath.Theme]::Warning;$pausedAt.Text=($a.name+' is paused at '+$h.label+'. Friends get this version.')}
        else{$pausedAt.ForeColor=[Warpath.Theme]::Secondary;$pausedAt.Text=($a.name+' is live: friends get the newest from GitHub.')}
    }
    $pick.add_SelectedIndexChanged($showPause)
    $pause.add_CheckedChanged({
        if($script:pauseSync){return}
        $i=$pick.SelectedIndex;if($i -lt 0){return}
        $a=$editorEntries[$i];$row=$rows.Rows[$i]
        if($pause.Checked) {
            $pausedAt.Text='Reading the current version of '+$a.name+' from GitHub...';$window.Refresh()
            try {
                $sha=(Get-RemoteSha $a.repo).ToLower()
                $held[$a.repo]=@{sha=$sha;label=(Get-AddonVersionAt $a $sha)}
                $row.Status='Paused';$row.Description='Paused at '+$held[$a.repo].label
            } catch {
                Write-WarpathLog ('Pause: '+$_)
                $script:pauseSync=$true;$pause.Checked=$false;$script:pauseSync=$false
                $pausedAt.ForeColor=[Warpath.Theme]::Warning;$pausedAt.Text='Could not reach GitHub. Try again.';return
            }
        } else {
            $held.Remove($a.repo);$row.Status='Public';$row.Description=$a.game
        }
        $rows.Invalidate();& $showPause
        $pausedAt.Text+=' Click Save, then push.'
    })
    $save=New-Object Warpath.PurpleButton;$save.Text='Save';$save.SetBounds(18,551,674,58);$window.Controls.Add($save)
    $status=[Warpath.Theme]::Label('Tick an addon and Save to share it.',22,621,666,45);$status.ForeColor=[Warpath.Theme]::Secondary;$window.Controls.Add($status)
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
            if($hook){[IO.File]::WriteAllText($hookFile,(ConvertTo-WarpathHook $hook),(New-Object Text.UTF8Encoding($false)))}
            elseif([IO.File]::Exists($hookFile)){[IO.File]::Delete($hookFile)}
            Assert-SafePath $catalogFile
            $json=ConvertTo-Json -InputObject @($selected) -Depth 4
            $temporary=Join-Path $editorRoot ('catalog-'+[guid]::NewGuid().ToString('N')+'.tmp')
            [IO.File]::WriteAllText($temporary,$json,(New-Object Text.UTF8Encoding($false)))
            if([IO.File]::Exists($catalogFile)){[IO.File]::Replace($temporary,$catalogFile,[NullString]::Value)}else{[IO.File]::Move($temporary,$catalogFile)}
            # Also refresh the cached copy, so this Warpath shows the change right away
            # instead of the older list it last downloaded.
            try{$cache=Join-Path (Join-Path $env:APPDATA 'VoidMarkWarpath') 'catalog-cache.json';[IO.Directory]::CreateDirectory((Split-Path $cache -Parent))|Out-Null;[IO.File]::WriteAllText($cache,$json,(New-Object Text.UTF8Encoding($false)))}catch{Write-WarpathLog ('Catalog cache: '+$_)}
            $stage=Join-Path ([IO.Path]::GetTempPath()) ('stage-warpath-friends-'+[guid]::NewGuid().ToString('N'))
            Assert-SafePath $stage
            $package=Join-Path $stage 'VoidMarkWarpath';[IO.Directory]::CreateDirectory($package)|Out-Null
            foreach($name in @('VoidMarkWarpath.ps1','Warpath.Core.ps1','Warpath.Theme.ps1','Warpath.UI.cs','Launch-VoidMark-Warpath.vbs','public-catalog.json','README.md','version.txt')) {
                $sourceFile=Join-Path $editorRoot $name;Assert-SafePath $sourceFile
                Copy-Item -LiteralPath $sourceFile -Destination $package
            }
            if([IO.File]::Exists($hookFile)){Copy-Item -LiteralPath $hookFile -Destination $package}
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
            $status.ForeColor=[Warpath.Theme]::Success;$status.Text='Saved! Now commit + push public-catalog.json in GitHub Desktop. Everyone''s Warpath picks it up on next open. (First-time friends: send VoidMarkWarpath-Friends-READY.zip.)'
        } catch {
            Write-WarpathLog ($_|Out-String);$status.ForeColor=[Warpath.Theme]::Error
            $status.Text=if(($_|Out-String) -match 'VMW_HOOK'){'That webhook link looks wrong. Copy it again from Discord (Edit Channel > Integrations > Webhooks).'}else{"Couldn't create the friends ZIP. Make sure this folder is writable and try again."}
        } finally {
            if($stage){try{Remove-SafeStage ([IO.Path]::GetTempPath()) $stage}catch{Write-WarpathLog ('Export cleanup: '+$_)}}
            $save.Enabled=$true;$rows.Enabled=$true
        }
    })
    try{if($ParentWindow){[void]$window.ShowDialog($ParentWindow)}else{[void]$window.ShowDialog()}}finally{$window.Dispose()}
}
