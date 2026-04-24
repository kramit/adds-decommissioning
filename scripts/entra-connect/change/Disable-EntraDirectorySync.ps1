 [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\..\output'),
    [string]$RunId,
    [string]$TenantId,
    [switch]$UseDeviceCode,
    [switch]$SkipPostCheck
)

$commonPath = Join-Path $PSScriptRoot '..\lib\EntraConnect.Common.ps1'
. $commonPath

$context = New-EntraConnectContext -ScriptName 'Disable-EntraDirectorySync' -OutputRoot $OutputRoot -RunId $RunId
$warnings = @()

$session = Connect-EntraGraphSession -Scopes @(
    'OnPremDirectorySynchronization.ReadWrite.All',
    'Organization.ReadWrite.All',
    'Organization.Read.All',
    'Directory.Read.All'
) -TenantId $TenantId -UseDeviceCode:$UseDeviceCode

$tenantId = if ($TenantId) { $TenantId } else { $session.TenantId }

try {
    $before = Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/organization?`$select=id,displayName,onPremisesSyncEnabled,onPremisesLastSyncDateTime" | Select-Object -First 1
}
catch {
    throw "Unable to read tenant state before change: $($_.Exception.Message)"
}

$changeResult = $null
$actionDescription = 'disable directory synchronization'

if ($PSCmdlet.ShouldProcess("tenant $tenantId", $actionDescription)) {
    try {
        if (Get-Command Set-EntraDirSyncEnabled -ErrorAction SilentlyContinue) {
            Set-EntraDirSyncEnabled -EnableDirSync $false -TenantId $tenantId -Force -ErrorAction Stop
            $changeResult = [pscustomobject]@{
                Method = 'Set-EntraDirSyncEnabled'
                TenantId = $tenantId
            }
        }
        elseif (Get-Command Update-MgOrganization -ErrorAction SilentlyContinue) {
            Update-MgOrganization -OrganizationId $tenantId -OnPremisesSyncEnabled:$false -ErrorAction Stop
            $changeResult = [pscustomobject]@{
                Method = 'Update-MgOrganization'
                TenantId = $tenantId
            }
        }
        else {
            Invoke-GraphPatch -Uri "https://graph.microsoft.com/v1.0/organization/$tenantId" -Body @{
                onPremisesSyncEnabled = $false
            } | Out-Null
            $changeResult = [pscustomobject]@{
                Method = 'Invoke-MgGraphRequest PATCH'
                TenantId = $tenantId
            }
        }
    }
    catch {
        throw "Failed to disable directory synchronization: $($_.Exception.Message)"
    }
}

$after = $null
if (-not $SkipPostCheck) {
    try {
        Start-Sleep -Seconds 5
        $after = Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/organization?`$select=id,displayName,onPremisesSyncEnabled,onPremisesLastSyncDateTime" | Select-Object -First 1
    }
    catch {
        $warnings += "Unable to read tenant state after change: $($_.Exception.Message)"
    }
}

$data = [pscustomobject]@{
    Session = $session
    Before = $before
    After = $after
    ChangeResult = $changeResult
    Notes = @(
        'This script makes the tenant-level directory sync change.',
        'Microsoft notes this change can take up to 72 hours to fully complete.'
    )
}

$summary = @(
    "Tenant: $tenantId",
    "Before sync enabled: $($before.onPremisesSyncEnabled)",
    "After sync enabled: $($after.onPremisesSyncEnabled)",
    "Change method: $($changeResult.Method)"
)

$artifact = Save-EntraArtifact -Context $context -Data $data -SummaryLines $summary -Warnings $warnings
[pscustomobject]@{
    ScriptName = $context.ScriptName
    TextPath = $artifact.TextPath
    JsonPath = $artifact.JsonPath
    RunRoot = $context.RunRoot
    SessionTenantId = $session.TenantId
    ChangeMethod = $changeResult.Method
}
