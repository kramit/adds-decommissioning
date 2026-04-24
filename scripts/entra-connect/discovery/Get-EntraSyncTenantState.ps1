param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\..\output'),
    [string]$RunId,
    [string]$TenantId,
    [switch]$UseDeviceCode
)

$commonPath = Join-Path $PSScriptRoot '..\lib\EntraConnect.Common.ps1'
. $commonPath

$context = New-EntraConnectContext -ScriptName 'Get-EntraSyncTenantState' -OutputRoot $OutputRoot -RunId $RunId
$warnings = @()

$session = Connect-EntraGraphSession -Scopes @(
    'Organization.Read.All',
    'Directory.Read.All',
    'Domain.Read.All',
    'Application.Read.All',
    'RoleManagement.Read.Directory'
) -TenantId $TenantId -UseDeviceCode:$UseDeviceCode

$tenantId = if ($TenantId) { $TenantId } else { $session.TenantId }
$headers = @{
    ConsistencyLevel = 'eventual'
}

$organization = $null
$domains = @()
$syncServicePrincipal = @()
$directoryRoles = @()

try {
    $organization = Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/organization?`$select=id,displayName,onPremisesSyncEnabled,onPremisesLastSyncDateTime" | Select-Object -First 1
}
catch {
    $warnings += "Unable to read organization state: $($_.Exception.Message)"
}

try {
    $domains = Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/domains?`$select=id,isVerified,isDefault,isInitial,isRoot,authenticationType,isAdminManaged"
}
catch {
    $warnings += "Unable to read tenant domains: $($_.Exception.Message)"
}

try {
    $syncServicePrincipal = Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '6bf85cfa-ac8a-4be5-b5de-425a0d0dc016'&`$select=id,appId,displayName,servicePrincipalType,accountEnabled"
}
catch {
    $warnings += "Unable to read the Entra AD Synchronization Service principal: $($_.Exception.Message)"
}

try {
    $directoryRoles = Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/directoryRoles?`$select=id,displayName"
}
catch {
    $warnings += "Unable to read directory roles: $($_.Exception.Message)"
}

$data = [pscustomobject]@{
    Session = $session
    Organization = $organization
    Domains = @($domains)
    SyncServicePrincipal = @($syncServicePrincipal)
    DirectoryRoles = @($directoryRoles)
    Notes = @(
        'This script requires a Microsoft Graph sign-in.',
        'Use it to baseline tenant sync state before disabling directory synchronization.'
    )
}

$summary = @(
    "Tenant: $tenantId",
    "Organization sync enabled: $($organization.onPremisesSyncEnabled)",
    "Domains discovered: $(@($domains).Count)",
    "Sync service principal matches: $(@($syncServicePrincipal).Count)",
    "Directory roles discovered: $(@($directoryRoles).Count)"
)

$artifact = Save-EntraArtifact -Context $context -Data $data -SummaryLines $summary -Warnings $warnings
[pscustomobject]@{
    ScriptName = $context.ScriptName
    TextPath = $artifact.TextPath
    JsonPath = $artifact.JsonPath
    RunRoot = $context.RunRoot
    SessionTenantId = $session.TenantId
}
