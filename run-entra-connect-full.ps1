param(
    [string]$OutputRoot,
    [string]$RunId,
    [string]$TenantId,
    [switch]$UseDeviceCode,
    [switch]$IncludeFullList,
    [switch]$ExecuteLocalUninstall,
    [switch]$ExecuteTenantDisable
)

$repoRoot = $PSScriptRoot

$graphPrecheck = Join-Path $repoRoot 'scripts\entra-connect\precheck\Test-EntraConnectGraphPrereqs.ps1'
$tenantPack = Join-Path $repoRoot 'run-entra-connect.ps1'
$localPack = Join-Path $repoRoot 'scripts\entra-connect\local\Export-EntraConnectLocalPack.ps1'
$localPrereq = Join-Path $repoRoot 'scripts\entra-connect\local\Test-EntraConnectLocalPrereqs.ps1'
$localStop = Join-Path $repoRoot 'scripts\entra-connect\local\Stop-EntraConnectSyncServices.ps1'
$localUninstall = Join-Path $repoRoot 'scripts\entra-connect\local\Uninstall-EntraConnect.ps1'
$localVerify = Join-Path $repoRoot 'scripts\entra-connect\local\Verify-EntraConnectRemoval.ps1'
$tenantDisable = Join-Path $repoRoot 'scripts\entra-connect\change\Disable-EntraDirectorySync.ps1'
$tenantWait = Join-Path $repoRoot 'scripts\entra-connect\change\Wait-EntraDirectorySyncDisabled.ps1'

foreach ($path in @($graphPrecheck, $tenantPack, $localPack, $localPrereq, $localStop, $localUninstall, $localVerify, $tenantDisable, $tenantWait)) {
    if (-not (Test-Path $path)) {
        throw "Missing script: $path"
    }
}

$results = [ordered]@{}

$results.GraphPrecheck = & $graphPrecheck -OutputRoot $OutputRoot -RunId $RunId -TenantId $TenantId -UseDeviceCode:$UseDeviceCode
$results.TenantDiscovery = & $tenantPack -OutputRoot $OutputRoot -RunId $RunId -TenantId $TenantId -UseDeviceCode:$UseDeviceCode -IncludeFullList:$IncludeFullList
$results.LocalDiscovery = & $localPack -OutputRoot $OutputRoot -RunId $RunId
$results.LocalPrereqs = & $localPrereq -OutputRoot $OutputRoot -RunId $RunId

if ($ExecuteLocalUninstall) {
    $results.LocalStop = & $localStop -OutputRoot $OutputRoot -RunId $RunId -DisableStartup -Confirm
    $results.LocalUninstall = & $localUninstall -OutputRoot $OutputRoot -RunId $RunId -Execute -Confirm
    $results.LocalVerify = & $localVerify -OutputRoot $OutputRoot -RunId $RunId
}

if ($ExecuteTenantDisable) {
    $results.TenantDisable = & $tenantDisable -OutputRoot $OutputRoot -RunId $RunId -TenantId $TenantId -UseDeviceCode:$UseDeviceCode -Confirm
    $results.TenantWait = & $tenantWait -OutputRoot $OutputRoot -RunId $RunId -TenantId $TenantId -UseDeviceCode:$UseDeviceCode
}

[pscustomobject]@{
    RunId = $RunId
    TenantId = $TenantId
    ExecuteLocalUninstall = [bool]$ExecuteLocalUninstall
    ExecuteTenantDisable = [bool]$ExecuteTenantDisable
    Results = $results
}
