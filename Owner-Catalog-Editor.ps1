Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$entries=@(
 @{game='WoW Forever';repo='VoidMark-Forever';name='VoidMark Forever'},
 @{game='WoW Forever';repo='VoidMark-Market';name='VoidMark Market'},
 @{game='WoW Forever';repo='VoidMark-Nexus';name='VoidMark Nexus'},
 @{game='WoW Forever';repo='VoidMark-Mini-Map';name='VoidMark Mini-Map'},
 @{game='WoW Forever';repo='VoidMark-Debug';name='VoidMark Debug'},
 @{game='WoW Classic Era';repo='VoidMark';name='VoidMark'},
 @{game='WoW Classic Era';repo='VoidMark-Clapback';name='VoidMark Clapback'},
 @{game='WoW Classic Era';repo='VoidLink';name='VoidLink'}
)
$path=Join-Path $PSScriptRoot 'public-catalog.json'
$existing=@();if(Test-Path $path){$existing=@(Get-Content $path -Raw|ConvertFrom-Json)}
$form=New-Object Windows.Forms.Form;$form.Text='VoidMark Warpath - Owner publishing';$form.Size=New-Object Drawing.Size(540,490);$form.StartPosition='CenterScreen'
$label=New-Object Windows.Forms.Label;$label.Location=New-Object Drawing.Point(15,10);$label.Size=New-Object Drawing.Size(490,50);$label.Text='Only selected addons appear for friends. Journey and old Warpath are intentionally excluded.';$form.Controls.Add($label)
$list=New-Object Windows.Forms.CheckedListBox;$list.CheckOnClick=$true;$list.Location=New-Object Drawing.Point(15,65);$list.Size=New-Object Drawing.Size(490,315);$form.Controls.Add($list)
foreach($a in $entries){$i=$list.Items.Add($a.game+'  |  '+$a.name);if(@($existing|Where-Object{$_.game -eq $a.game -and $_.repo -eq $a.repo}).Count -gt 0){$list.SetItemChecked($i,$true)}}
$save=New-Object Windows.Forms.Button;$save.Text='Save approved list';$save.Location=New-Object Drawing.Point(15,395);$save.Size=New-Object Drawing.Size(490,38);$form.Controls.Add($save)
$save.Add_Click({
 $selected=@();for($i=0;$i -lt $entries.Count;$i++){if($list.GetItemChecked($i)){$selected+=@{game=$entries[$i].game;repo=$entries[$i].repo}}}
 [IO.File]::WriteAllText($path,(ConvertTo-Json -InputObject @($selected) -Depth 4),(New-Object Text.UTF8Encoding($false)))
 [Windows.Forms.MessageBox]::Show('Saved. Distribute the updater files plus public-catalog.json. Never send the owner editor.','Saved')|Out-Null
})
[void]$form.ShowDialog()
