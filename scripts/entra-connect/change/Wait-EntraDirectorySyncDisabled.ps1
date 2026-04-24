param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\..\output'),
    [string]$RunId,
    [string]$TenantId,
    [switch]$UseDeviceCode,
    [int]$TimeoutMinutes = 60,
    [int]$PollSeconds = 300
)

$commonPath = Join-Path $PSScriptRoot '..\lib\EntraConnect.Common.ps1'
. $commonPath

$context = New-EntraConnectContext -ScriptName 'Wait-EntraDirectorySyncDisabled' -OutputRoot $OutputRoot -RunId $RunId
$warnings = @()

$session = Connect-EntraGraphSession -Scopes @(
    'Organization.Read.All',
    'Directory.Read.All'
) -TenantId $TenantId -UseDeviceCode:$UseDeviceCode

$tenantId = if ($TenantId) { $TenantId } else { $session.TenantId }
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$history = New-Object System.Collections.Generic.List[object]

do {
    try {
        $state = Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/organization?`$select=id,displayName,onPremisesSyncEnabled,onPremisesLastSyncDateTime" | Select-Object -First 1
        $history.Add([pscustomobject]@{
            Timestamp = Get-Date
            OnPremisesSyncEnabled = $state.onPremisesSyncEnabled
            LastSync = $state.onPremisesLastSyncDateTime
        })

        if ($state.onPremisesSyncEnabled -eq $false) {
            $data = [pscustomobject]@{
                Session = $session
                FinalState = $state
                PollHistory = @($history)
                Notes = @(
                    'The tenant reported directory synchronization as disabled.',
                    'If objects are still converging, continue to monitor until your change window is complete.'
                )
            }

            $summary = @(
                "Tenant: $tenantId",
                "Directory sync disabled: $($state.onPremisesSyncEnabled -eq $false)",
                "Poll count: $($history.Count)"
            )

            $artifact = Save-EntraArtifact -Context $context -Data $data -SummaryLines $summary -Warnings $warnings
            [pscustomobject]@{
                ScriptName = $context.ScriptName
                TextPath = $artifact.TextPath
                JsonPath = $artifact.JsonPath
                RunRoot = $context.RunRoot
                TenantId = $tenantId
                Disabled = $true
                PollCount = $history.Count
            }
            return
        }
    }
    catch {
        $warnings += "Polling error: $($_.Exception.Message)"
    }

    if ((Get-Date) -ge $deadline) {
        break
    }

    Start-Sleep -Seconds $PollSeconds
} while ($true)

$failureData = [pscustomobject]@{
    Session = $session
    PollHistory = @($history)
    Notes = @(
        'The verification loop timed out before the tenant reported directory sync as disabled.',
        'This is not necessarily a failure; Microsoft notes the tenant change can take up to 72 hours to finish.'
    )
}

$failureSummary = @(
    "Tenant: $tenantId",
    "Timed out after minutes: $TimeoutMinutes",
    "Poll count: $($history.Count)"
)

$artifact = Save-EntraArtifact -Context $context -Data $failureData -SummaryLines $failureSummary -Warnings $warnings
[pscustomobject]@{
    ScriptName = $context.ScriptName
    TextPath = $artifact.TextPath
    JsonPath = $artifact.JsonPath
    RunRoot = $context.RunRoot
    TenantId = $tenantId
    Disabled = $false
    PollCount = $history.Count
}
