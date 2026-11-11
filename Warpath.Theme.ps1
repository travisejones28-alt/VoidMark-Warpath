Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
if(-not ('Warpath.MainWindow' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'Warpath.UI.cs') -ReferencedAssemblies 'System.Windows.Forms','System.Drawing','System.Core'
}
[Windows.Forms.Application]::EnableVisualStyles()
function Show-WarpathNote([string]$Text,[string]$Title='VoidMark Warpath') {
    $dialog=New-Object Warpath.DarkForm;$dialog.Text=$Title;$dialog.ClientSize=New-Object Drawing.Size(500,180)
    $label=[Warpath.Theme]::Label($Text,20,18,460,96);$dialog.Controls.Add($label)
    $ok=New-Object Warpath.PurpleButton;$ok.Text='OK';$ok.SetBounds(330,120,150,42);$ok.DialogResult='OK';$dialog.Controls.Add($ok)
    $dialog.AcceptButton=$ok;$dialog.CancelButton=$ok
    try{[void]$dialog.ShowDialog()}finally{$dialog.Dispose()}
}
function Show-WarpathAsk([string]$Text,[string]$Title='VoidMark Warpath',[string]$Yes='Yes',[string]$No='No',$Owner=$null) {
    $dialog=New-Object Warpath.DarkForm;$dialog.Text=$Title;$dialog.ClientSize=New-Object Drawing.Size(520,210)
    if($Owner){$dialog.StartPosition='CenterParent'}
    $label=[Warpath.Theme]::Label($Text,20,18,480,120);$label.Font=New-Object Drawing.Font('Segoe UI',11);$dialog.Controls.Add($label)
    $yesButton=New-Object Warpath.PurpleButton;$yesButton.Text=$Yes;$yesButton.SetBounds(20,146,234,46);$yesButton.DialogResult='OK';$dialog.Controls.Add($yesButton)
    $noButton=New-Object Warpath.PurpleButton;$noButton.Text=$No;$noButton.SetBounds(266,146,234,46);$noButton.DialogResult='Cancel';$dialog.Controls.Add($noButton)
    $dialog.AcceptButton=$yesButton;$dialog.CancelButton=$noButton
    try{ if($Owner){$r=$dialog.ShowDialog($Owner)}else{$r=$dialog.ShowDialog()}; $r -eq [Windows.Forms.DialogResult]::OK }finally{$dialog.Dispose()}
}
