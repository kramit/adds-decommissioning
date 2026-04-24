param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\..\output'),
    [string]$RunId,
    [string]$TenantId,
    [switch]$UseDeviceCode,
    [switch]$IncludeFullList
)

$commonPath = Join-Path $PSScriptRoot '..\lib\EntraConnect.Common.ps1'
. $commonPath

$context = New-EntraConnectContext -ScriptName 'Get-EntraSyncObjectInventory' -OutputRoot $OutputRoot -RunId $RunId
$warnings = @()

$session = Connect-EntraGraphSession -Scopes @(
    'User.Read.All',
    'Group.Read.All',
    'Directory.Read.All'
) -TenantId $TenantId -UseDeviceCode:$UseDeviceCode

$headers = @{
    ConsistencyLevel = 'eventual'
}

$syncedUsers = @()
$syncedGroups = @()

try {
    $syncedUsers = Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/users?`$filter=onPremisesSyncEnabled eq true&`$select=id,displayName,userPrincipalName,onPremisesImmutableId,onPremisesSyncEnabled,onPremisesLastSyncDateTime&`$top=999" -Headers $headers
}
catch {
    $warnings += "Unable to enumerate synced users: $($_.Exception.Message)"
}

try {
    $syncedGroups = Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=onPremisesSyncEnabled eq true&`$select=id,displayName,mailEnabled,securityEnabled,onPremisesSyncEnabled&`$top=999" -Headers $headers
}
catch {
    $warnings += "Unable to enumerate synced groups: $($_.Exception.Message)"
}

$data = [pscustomobject]@{
    Session = $session
    SyncedUsersCount = @($syncedUsers).Count
    SyncedGroupsCount = @($syncedGroups).Count
    SyncedUsersSample = @($syncedUsers | Select-Object -First 25)
    SyncedGroupsSample = @($syncedGroups | Select-Object -First 25)
    SyncedUsers = if ($IncludeFullList) { @($syncedUsers) } else { @() }
    SyncedGroups = if ($IncludeFullList) { @($syncedGroups) } else { @() }
    Notes = @(
        'This script inventories synced users and groups in the tenant.',
        'Use -IncludeFullList if you want the complete object list instead of samples.'
    )
}

$summary = @(
    "Synced users: $(@($syncedUsers).Count)",
    "Synced groups: $(@($syncedGroups).Count)",
    "Full list exported: $IncludeFullList"
)

$artifact = Save-EntraArtifact -Context $context -Data $data -SummaryLines $summary -Warnings $warnings
[pscustomobject]@{
    ScriptName = $context.ScriptName
    TextPath = $artifact.TextPath
    JsonPath = $artifact.JsonPath
    RunRoot = $context.RunRoot
    SessionTenantId = $session.TenantId
}
