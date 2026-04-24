param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\..\output'),
    [string]$RunId,
    [string]$TenantId,
    [switch]$UseDeviceCode,
    [string[]]$RequiredScopes = @(
        'Organization.Read.All',
        'Directory.Read.All',
        'Domain.Read.All',
        'Application.Read.All',
        'RoleManagement.Read.Directory',
        'User.Read.All',
        'Group.Read.All',
        'OnPremDirectorySynchronization.ReadWrite.All',
        'Organization.ReadWrite.All'
    )
)

$commonPath = Join-Path $PSScriptRoot '..\lib\EntraConnect.Common.ps1'
. $commonPath

$context = New-EntraConnectContext -ScriptName 'Test-EntraConnectGraphPrereqs' -OutputRoot $OutputRoot -RunId $RunId
$warnings = @()

$session = Connect-EntraGraphSession -Scopes $RequiredScopes -TenantId $TenantId -UseDeviceCode:$UseDeviceCode
$contextInfo = Get-MgContext

$org = $null
$domains = @()
$servicePrincipal = @()

try {
    $org = Get-GraphCollection -Uri 'https://graph.microsoft.com/v1.0/organization?$select=id,displayName,onPremisesSyncEnabled,onPremisesLastSyncDateTime' | Select-Object -First 1
}
catch {
    $warnings += "Failed to read organization object: $($_.Exception.Message)"
}

try {
    $domains = Get-GraphCollection -Uri 'https://graph.microsoft.com/v1.0/domains?$select=id,authenticationType,isDefault,isVerified,isAdminManaged'
}
catch {
    $warnings += "Failed to read domain inventory: $($_.Exception.Message)"
}

try {
    $servicePrincipal = Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '6bf85cfa-ac8a-4be5-b5de-425a0d0dc016'&`$select=id,appId,displayName,servicePrincipalType,accountEnabled"
}
catch {
    $warnings += "Failed to read sync service principal inventory: $($_.Exception.Message)"
}

$missingScopes = @()
foreach ($scope in $RequiredScopes) {
    if ($session.Scopes -notcontains $scope) {
        $missingScopes += $scope
    }
}

$canUseModuleCommands = [pscustomobject]@{
    SetEntraDirSyncEnabled = [bool](Get-Command Set-EntraDirSyncEnabled -ErrorAction SilentlyContinue)
    UpdateMgOrganization = [bool](Get-Command Update-MgOrganization -ErrorAction SilentlyContinue)
    GetEntraContext = [bool](Get-Command Get-EntraContext -ErrorAction SilentlyContinue)
    GetMgContext = [bool](Get-Command Get-MgContext -ErrorAction SilentlyContinue)
}

$ready = ($missingScopes.Count -eq 0) -and $org -and $domains

$data = [pscustomobject]@{
    Session = $session
    GraphContext = [pscustomobject]@{
        TenantId = $contextInfo.TenantId
        Account = $contextInfo.Account
        Scopes = @($contextInfo.Scopes)
        AuthType = $contextInfo.AuthType
        AppName = $contextInfo.AppName
    }
    Organization = $org
    Domains = @($domains)
    SyncServicePrincipal = @($servicePrincipal)
    MissingScopes = @($missingScopes)
    CommandAvailability = $canUseModuleCommands
    Ready = [bool]$ready
    Notes = @(
        'This is a dry-run precheck for the tenant-side Entra Connect change.',
        'It confirms the signed-in account has the requested Graph scopes and can read the required tenant objects.'
    )
}

$summary = @(
    "Tenant: $($session.TenantId)",
    "Account: $($session.Account)",
    "Missing scopes: $(@($missingScopes).Count)",
    "Domains discovered: $(@($domains).Count)",
    "Sync service principal matches: $(@($servicePrincipal).Count)",
    "Ready: $ready"
)

$artifact = Save-EntraArtifact -Context $context -Data $data -SummaryLines $summary -Warnings $warnings
[pscustomobject]@{
    ScriptName = $context.ScriptName
    TextPath = $artifact.TextPath
    JsonPath = $artifact.JsonPath
    RunRoot = $context.RunRoot
    Ready = [bool]$ready
    MissingScopes = @($missingScopes)
}
