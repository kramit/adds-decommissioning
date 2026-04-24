param(
    [string]$OutputRoot,
    [string]$RunId,
    [string]$DiscoveryRunRoot,
    [string]$DiscoveryIndexPath,
    [switch]$Execute,
    [switch]$BypassBlockers,
    [switch]$SkipPreChecks,
    [switch]$NoRebootOnCompletion,
    [switch]$ForceRemoval,
    [switch]$LastDomainControllerInDomain,
    [switch]$IgnoreLastDCInDomainMismatch,
    [switch]$IgnoreLastDnsServerForZone,
    [switch]$RemoveApplicationPartitions,
    [switch]$RemoveDnsDelegation,
    [switch]$DemoteOperationMasterRole,
    [switch]$RetainDCMetadata,
    [switch]$WhatIf,
    [System.Management.Automation.PSCredential]$Credential,
    [System.Management.Automation.PSCredential]$DnsDelegationRemovalCredential,
    [SecureString]$LocalAdministratorPassword
)

$repoRoot = $PSScriptRoot
$buildScript = Join-Path $repoRoot 'scripts\execution\Build-DCDecommissionPlan.ps1'
$invokeScript = Join-Path $repoRoot 'scripts\execution\Invoke-DCDecommission.ps1'

foreach ($path in @($buildScript, $invokeScript)) {
    if (-not (Test-Path $path)) {
        throw "Missing script: $path"
    }
}

if ($Execute -and -not $PSBoundParameters.ContainsKey('RunId')) {
    $RunId = Get-Date -Format 'yyyyMMdd-HHmmss'
}

$sharedArgs = @{}
foreach ($name in 'OutputRoot', 'RunId', 'DiscoveryRunRoot', 'DiscoveryIndexPath') {
    if ($PSBoundParameters.ContainsKey($name)) {
        $sharedArgs[$name] = $PSBoundParameters[$name]
    }
}

if ($RunId) {
    $sharedArgs['RunId'] = $RunId
}

$plan = & $buildScript @sharedArgs

if (-not $Execute) {
    return $plan
}

if (-not $BypassBlockers -and $plan.CanProceed -eq $false) {
    throw "The DC decommission plan reported blockers. Review $($plan.TextPath) before running -Execute, or use -BypassBlockers only if you have explicitly accepted the risk."
}

$executeArgs = @{}
foreach ($name in 'OutputRoot', 'RunId', 'DiscoveryRunRoot', 'DiscoveryIndexPath', 'Execute', 'BypassBlockers', 'SkipPreChecks', 'NoRebootOnCompletion', 'ForceRemoval', 'LastDomainControllerInDomain', 'IgnoreLastDCInDomainMismatch', 'IgnoreLastDnsServerForZone', 'RemoveApplicationPartitions', 'RemoveDnsDelegation', 'DemoteOperationMasterRole', 'RetainDCMetadata', 'Credential', 'DnsDelegationRemovalCredential', 'LocalAdministratorPassword') {
    if ($PSBoundParameters.ContainsKey($name)) {
        $executeArgs[$name] = $PSBoundParameters[$name]
    }
}

if ($RunId) {
    $executeArgs['RunId'] = $RunId
}

$executeArgs.Execute = $true
if ($WhatIf) {
    $executeArgs['WhatIf'] = $true
}
& $invokeScript @executeArgs
