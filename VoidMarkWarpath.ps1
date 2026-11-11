Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$ErrorActionPreference='Stop'
$owner='travisejones28-alt'
$all=@(
 @{game='WoW Forever';name='VoidMark Forever';repo='VoidMark-Forever'},
 @{game='WoW Forever';name='VoidMark Market';repo='VoidMark-Market'},
 @{game='WoW Forever';name='VoidMark Nexus';repo='VoidMark-Nexus'},
 @{game='WoW Forever';name='VoidMark Mini-Map';repo='VoidMark-Mini-Map'},
 @{game='WoW Forever';name='VoidMark Debug';repo='VoidMark-Debug'},
 @{game='WoW Classic Era';name='VoidMark';repo='VoidMark'},
 @{game='WoW Classic Era';name='VoidMark Clapback';repo='VoidMark-Clapback'},
 @{game='WoW Classic Era';name='VoidLink';repo='VoidLink'}
)
$catalogPath=Join-Path $PSScriptRoot 'public-catalog.json'
$approved=@()
if(Test-Path -LiteralPath $catalogPath) { $approved=@(Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json) }
$all=@($all | Where-Object { $a=$_; @($approved | Where-Object {$_.game -eq $a.game -and $_.repo -eq $a.repo}).Count -gt 0 })
$settingsPath=Join-Path (Join-Path $env:APPDATA 'VoidMarkWarpath') 'settings.json'
$paths=@{'WoW Forever'=(Join-Path $env:USERPROFILE 'Documents\VoidMark Test\Forever');'WoW Classic Era'=(Join-Path $env:USERPROFILE 'Documents\VoidMark Test\Classic Era')}
if(Test-Path $settingsPath) { try { $cfg=Get-Content $settingsPath -Raw | ConvertFrom-Json; foreach($key in @($paths.Keys)) { if($cfg.paths.$key){$paths[$key]=[string]$cfg.paths.$key} } } catch {} }
function Save-Settings { $dir=Split-Path $settingsPath -Parent; [IO.Directory]::CreateDirectory($dir)|Out-Null; @{paths=$paths}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $settingsPath -Encoding UTF8 }
function Record([string]$dest,[string]$repo) { Join-Path (Join-Path $dest '.VoidMarkWarpath') ($repo+'.json') }
function Remote([string]$repo) { (Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$owner+'/'+$repo+'/commits/main') -Headers @{'User-Agent'='VoidMark-Warpath'} -TimeoutSec 30).sha }
function Set-Progress([int]$p,[string]$s) {
 $bar.Value=[Math]::Max(0,[Math]::Min(100,$p));$progressLabel.Text=$s;[Windows.Forms.Application]::DoEvents()
}
function Get-Zip([string]$url,[string]$file,[string]$name) {
 $req=[Net.HttpWebRequest]::Create($url);$req.UserAgent='VoidMark-Warpath';$req.Timeout=30000;$req.ReadWriteTimeout=30000
 $res=$null;$input=$null;$output=$null
 try {
  $res=$req.GetResponse();$total=[long]$res.ContentLength;$input=$res.GetResponseStream();$output=[IO.File]::Create($file)
  $buf=New-Object byte[] 65536;$got=[long]0;$sw=[Diagnostics.Stopwatch]::StartNew()
  while(($n=$input.Read($buf,0,$buf.Length)) -gt 0) {
   $output.Write($buf,0,$n);$got+=$n
   $pct=if($total -gt 0){[int](100*$got/$total)}else{0}
   Set-Progress $pct ($name+' '+[math]::Round($got/1MB,1)+' MB @ '+[math]::Round(($got/1MB)/[math]::Max(1,$sw.Elapsed.TotalSeconds),1)+' MB/s')
  }
 } finally { if($output){$output.Close()};if($input){$input.Close()};if($res){$res.Close()} }
}
$form=New-Object Windows.Forms.Form
$form.Text='VoidMark Warpath - Addon Updater';$form.Size=New-Object Drawing.Size(710,640);$form.StartPosition='CenterScreen';$form.Font=New-Object Drawing.Font('Segoe UI',10)
$heading=New-Object Windows.Forms.Label;$heading.Text='VOIDMARK WARPATH';$heading.Font=New-Object Drawing.Font('Segoe UI',18,[Drawing.FontStyle]::Bold);$heading.Location=New-Object Drawing.Point(18,16);$heading.AutoSize=$true;$form.Controls.Add($heading)
$game=New-Object Windows.Forms.ComboBox;$game.DropDownStyle='DropDownList';$game.Location=New-Object Drawing.Point(20,78);$game.Size=New-Object Drawing.Size(650,30);[void]$game.Items.Add('WoW Forever');[void]$game.Items.Add('WoW Classic Era');$form.Controls.Add($game)
$folder=New-Object Windows.Forms.TextBox;$folder.Location=New-Object Drawing.Point(20,125);$folder.Size=New-Object Drawing.Size(540,28);$form.Controls.Add($folder)
$browse=New-Object Windows.Forms.Button;$browse.Text='Browse';$browse.Location=New-Object Drawing.Point(575,124);$browse.Size=New-Object Drawing.Size(95,32);$form.Controls.Add($browse)
$list=New-Object Windows.Forms.ListView;$list.Location=New-Object Drawing.Point(20,175);$list.Size=New-Object Drawing.Size(650,280);$list.View='Details';$list.CheckBoxes=$true;$list.FullRowSelect=$true
[void]$list.Columns.Add('Addon',280);[void]$list.Columns.Add('Status',340);$form.Controls.Add($list)
$check=New-Object Windows.Forms.Button;$check.Text='Check for Updates';$check.Location=New-Object Drawing.Point(20,470);$check.Size=New-Object Drawing.Size(205,38);$form.Controls.Add($check)
$install=New-Object Windows.Forms.Button;$install.Text='Install Selected';$install.Location=New-Object Drawing.Point(244,470);$install.Size=New-Object Drawing.Size(205,38);$form.Controls.Add($install)
$update=New-Object Windows.Forms.Button;$update.Text='Update Installed';$update.Location=New-Object Drawing.Point(467,470);$update.Size=New-Object Drawing.Size(205,38);$form.Controls.Add($update)
$bar=New-Object Windows.Forms.ProgressBar;$bar.Location=New-Object Drawing.Point(20,526);$bar.Size=New-Object Drawing.Size(650,20);$form.Controls.Add($bar)
$progressLabel=New-Object Windows.Forms.Label;$progressLabel.Location=New-Object Drawing.Point(20,556);$progressLabel.Size=New-Object Drawing.Size(650,35);$progressLabel.Text='Select a game and folder, then check for updates.';$form.Controls.Add($progressLabel)
$busy=$false;$remote=@{}
function Target { $folder.Text.Trim() }
function Save-Folder { $paths[[string]$game.SelectedItem]=Target;Save-Settings }
function Refresh-List {
 $list.Items.Clear();$dest=Target
 foreach($a in @($all | Where-Object {$_.game -eq [string]$game.SelectedItem})) {
  $item=New-Object Windows.Forms.ListViewItem($a.name);$item.Tag=$a
  $record=Record $dest $a.repo;$status='Not installed'
  if(Test-Path $record) { $status='Installed - not checked';if($remote.ContainsKey($a.repo)){try { $old=(Get-Content $record -Raw|ConvertFrom-Json).sha;if($old -eq $remote[$a.repo]){$status='Up to date'}else{$status='Update available'} } catch {$status='Check required'} } }
  [void]$item.SubItems.Add($status);[void]$list.Items.Add($item)
 }
}
$game.Add_SelectedIndexChanged({$folder.Text=$paths[[string]$game.SelectedItem];$remote=@{};Refresh-List})
$folder.Add_Leave({Save-Folder;Refresh-List})
$browse.Add_Click({$dialog=New-Object Windows.Forms.FolderBrowserDialog;$dialog.SelectedPath=Target;if($dialog.ShowDialog() -eq 'OK'){$folder.Text=$dialog.SelectedPath;Save-Folder;Refresh-List}})
$check.Add_Click({
 if($busy){return};$busy=$true
 try { Save-Folder;$remote=@{};$entries=@($all|Where-Object {$_.game -eq [string]$game.SelectedItem});$i=0
 foreach($a in $entries){$i++;Set-Progress ([int](100*$i/[math]::Max(1,$entries.Count))) ('Checking '+$a.name);try{$remote[$a.repo]=Remote $a.repo}catch{$progressLabel.Text=('Check failed: '+$a.repo+' '+$_.Exception.Message)}}
 Refresh-List;Set-Progress 100 'Finished checking GitHub.'
 } finally {$busy=$false}
})
function Install-Entry($a) {
 $dest=Target
 if(-not $dest){throw 'Choose an installation folder first.'}
 [IO.Directory]::CreateDirectory($dest)|Out-Null
 $root=Join-Path $dest '.VoidMarkWarpath';[IO.Directory]::CreateDirectory($root)|Out-Null
 $sha=Remote $a.repo
 $target=Join-Path $dest $a.repo
 if((Test-Path $target) -and ((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw ('Refusing junction or symlink: '+$target)}
 $stage=Join-Path ([IO.Path]::GetTempPath()) ('vmw-'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($stage)|Out-Null
 try {
  $zip=Join-Path $stage 'source.zip';Get-Zip ('https://github.com/'+$owner+'/'+$a.repo+'/archive/refs/heads/main.zip') $zip $a.name
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $unpack=Join-Path $stage 'unpacked';[IO.Compression.ZipFile]::ExtractToDirectory($zip,$unpack)
  $source=Get-ChildItem -LiteralPath $unpack -Directory | Select-Object -First 1
  if(-not $source){throw 'GitHub archive had no source directory.'}
  $toc=Get-ChildItem -LiteralPath $source.FullName -Filter '*.toc' -File
  if($toc.Count -eq 0){throw 'No WoW addon .toc in repository root. Installation refused.'}
  if(Test-Path -LiteralPath $target){
   $backup=Join-Path $root ('backup-'+$a.repo+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N'))
   Move-Item -LiteralPath $target -Destination $backup
  }
  Copy-Item -LiteralPath $source.FullName -Destination $target -Recurse
  @{sha=$sha;repo=$a.repo;installedAt=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Record $dest $a.repo) -Encoding UTF8
  $remote[$a.repo]=$sha;Set-Progress 100 ($a.name+' installed at '+$target)
 } finally {if(Test-Path $stage){Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue}}
}
function Run-Install([bool]$allInstalled) {
 if($busy){return};$busy=$true;$check.Enabled=$false;$install.Enabled=$false;$update.Enabled=$false
 try {
  Save-Folder
  $entries=@()
  foreach($item in $list.Items){$a=$item.Tag;if(($allInstalled -and (Test-Path (Record (Target) $a.repo))) -or (-not $allInstalled -and $item.Checked)){$entries+=,$a}}
  if($entries.Count -eq 0){[Windows.Forms.MessageBox]::Show('No addons selected or previously installed.');return}
  foreach($a in $entries){Install-Entry $a}
  Refresh-List
 } catch {[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Update error')|Out-Null}
 finally {$busy=$false;$check.Enabled=$true;$install.Enabled=$true;$update.Enabled=$true}
}
$install.Add_Click({Run-Install $false});$update.Add_Click({Run-Install $true})
$game.SelectedIndex=0
[void]$form.ShowDialog()
