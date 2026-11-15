# Definitions only; called by an authenticated updater session or gated launcher.
function Show-WarpathCatalogEditor($ParentWindow) {
    $editorRoot=$PSScriptRoot
    $editorEntries=@(Get-WarpathEntries)
    $catalogFile=Join-Path $editorRoot 'public-catalog.json'
    $approved=@(Get-PublicCatalog $catalogFile)
    $window=New-Object Warpath.DarkForm;$window.Text='VoidMark Warpath — Public catalog';$window.ClientSize=New-Object Drawing.Size(710,680)
    $title=[Warpath.Theme]::Label('CHOOSE WHAT FRIENDS GET',22,18,660,35);$title.Font=[Warpath.Theme]::Serif(17);$title.ForeColor=[Warpath.Theme]::Highlight;$window.Controls.Add($title)
    $note=[Warpath.Theme]::Label('Checked = friends can install it. Click the Public pill to hold an addon at an older version while you keep pushing.',22,56,660,40);$window.Controls.Add($note)
    $rows=New-Object Warpath.AddonList;$rows.RowHeight=54;$rows.SetBounds(22,102,666,360);$window.Controls.Add($rows)
    $hookFile=Join-Path $editorRoot 'report-hook.txt'
    $hookLabel=[Warpath.Theme]::Label('Problem reports go to this Discord webhook (saved scrambled so GitHub bots can''t spot it):',22,470,666,24);$hookLabel.ForeColor=[Warpath.Theme]::Secondary;$window.Controls.Add($hookLabel)
    $hookBox=[Warpath.Theme]::TextBox(22,500,666);$hookBox.UseSystemPasswordChar=$true;$window.Controls.Add($hookBox)
    if([IO.File]::Exists($hookFile)){$hookBox.Text=ConvertFrom-WarpathHook ([IO.File]::ReadAllText($hookFile))}
    # Held addons: repo -> @{sha;label}. Friends get that commit; you keep getting main.
    $held=@{}
    foreach($a in $editorEntries) {
        $pin=Get-PinnedSha $a $approved
        if($pin){
            $label='';foreach($c in $approved){if($c.repo -eq $a.repo -and $c.game -eq $a.game){$label=[string](Get-WarpathField $c 'label')}}
            $held[$a.repo]=@{sha=$pin;label=$label}
        }
        $desc=if($pin){'Held: '+$(if($held[$a.repo].label){$held[$a.repo].label}else{$pin.Substring(0,7)})}else{$a.game}
        $row=New-Object Warpath.AddonRow($a.repo,$a.name,$desc,$(if($pin){'Held'}else{'Public'}),(Test-PublicEntry $a $approved),$false,$false,$false,$false)
        $rows.AddRow($row)
    }
    # Click the pill: choose Live (newest) or one of the recent versions.
    $rows.add_PillClick({
        param($index)
        $a=$editorEntries[$index];$row=$rows.Rows[$index]
        $menu=New-Object Windows.Forms.ContextMenuStrip
        $live=$menu.Items.Add('Live: friends get every update (newest)')
        $live.add_Click({$held.Remove($a.repo);$row.Status='Public';$row.Description=$a.game;$rows.Invalidate();$status.Text=($a.name+' is live again. Click Save, then push.')}.GetNewClosure())
        [void]$menu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
        $status.Text='Loading recent versions of '+$a.name+'...';$window.Refresh()
        try {
            $commits=@(Get-RecentCommits $a.repo 12)
            $status.Text='Pick the version friends should get. You still get every update.'
        } catch {$commits=@();$status.Text='Could not load versions from GitHub. Try again.';Write-WarpathLog ('Commits: '+$_)}
        foreach($c in $commits) {
            $text=$c.label;if($held.ContainsKey($a.repo) -and $held[$a.repo].sha -eq $c.sha){$text='(held) '+$text}
            $item=$menu.Items.Add($text)
            $item.add_Click({$held[$a.repo]=@{sha=$c.sha;label=$c.label};$row.Status='Held';$row.Description='Held: '+$c.label;$rows.Invalidate();$status.Text=($a.name+' held at: '+$c.label+'. Click Save, then push.')}.GetNewClosure())
        }
        $menu.Show([Windows.Forms.Cursor]::Position)
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
