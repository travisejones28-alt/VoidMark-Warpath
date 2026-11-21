# VoidMark Warpath: live statistics check (owner diagnostic).
# Sends ONE test check-in to the real statistics server using Warpath's own sending code,
# shows exactly what was sent and what the server answered, then deletes the test entry.
# Uses a brand-new random id, so it is not your Warpath and it is removed at the end.
#   Right-click > Run with PowerShell   (must be Windows PowerShell 5.1, like Warpath)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
if(-not [IO.File]::Exists((Join-Path $root 'Warpath.Core.ps1'))){$root=Split-Path $PSScriptRoot -Parent}
try {
    . (Join-Path $root 'Warpath.Core.ps1')
    . (Join-Path $root 'Warpath.Analytics.ps1')
    Write-Host ('PowerShell '+$PSVersionTable.PSVersion+'   Warpath folder: '+$root)
    $endpoint=Get-WarpathAnalyticsEndpoint $root
    Write-Host ('Server address: '+$(if($endpoint){$endpoint}else{'(none - statistics are off)'}))
    if(-not $endpoint){throw 'No server address found (analytics-endpoint.txt on GitHub and in this folder).'}
    $id=New-WarpathInstallId
    $event=New-WarpathAnalyticsEvent 'checkin' @{addons=@(@{game='WoW Forever';repo='VoidMark-Market';version='1.0.0'})}
    $script:sent='';$script:reply=$null
    $transport={param($url,$body) $script:sent=$body;$script:reply=Invoke-WarpathAnalyticsHttp $url $body;$script:reply}
    $r=Send-WarpathAnalytics $endpoint $id (Get-LocalAppVersion $root) @($event) @() $transport
    Write-Host "`n--- Sent ---";Write-Host $script:sent
    Write-Host "`n--- Server answered ---"
    if($script:reply){Write-Host ('HTTP '+$script:reply.status+'  '+$script:reply.body);if($script:reply.ContainsKey('error')){Write-Host ('Error: '+$script:reply.error)}}
    if($r.ok -and @($r.sent).Count -eq 1){Write-Host "`nRESULT: WORKS - the server accepted the test check-in." -ForegroundColor Green}
    else{Write-Host ("`nRESULT: FAILED ("+$r.error+$(if(@($r.dropped).Count){', event refused'}else{''})+'). Copy everything above to Claude.') -ForegroundColor Red}
    $d=Remove-WarpathAnalyticsData $endpoint $id
    Write-Host ('Test entry deleted from the server: '+$(if($d.ok){'yes'}else{'no ('+$d.error+')'}))
} catch {
    $why=if(Get-Command Format-WarpathError -ErrorAction SilentlyContinue){Format-WarpathError $_}else{[string]$_}
    Write-Host ('RESULT: CRASHED - '+$why) -ForegroundColor Red
}
Read-Host "`nPress Enter to close"
