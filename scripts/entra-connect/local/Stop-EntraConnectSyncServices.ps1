 [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\..\output'),
    [string]$RunId,
    [switch]$DisableStartup
)

$commonPath = Join-Path $PSScriptRoot 'EntraConnect.Local.Common.ps1'
. $commonPath

$context = New-EntraConnectLocalContext -ScriptName 'Stop-EntraConnectSyncServices' -OutputRoot $OutputRoot -RunId $RunId
$warnings = @()

$services = @(Get-EntraConnectLocalServices)
$targets = @($services | Where-Object { $_.Name -in @('ADSync', 'AzureADConnectProvisioningAgent', 'AzureADConnectAuthenticationAgent') })
$results = New-Object System.Collections.Generic.List[object]

foreach ($service in $targets) {
    if ($PSCmdlet.ShouldProcess($service.Name, 'stop Entra Connect service')) {
        try {
            Stop-Service -Name $service.Name -Force -ErrorAction Stop
            if ($DisableStartup) {
                Set-Service -Name $service.Name -StartupType Disabled -ErrorAction Stop
            }
            $results.Add([pscustomobject]@{
                Name = $service.Name
                Status = (Get-Service -Name $service.Name).Status
                Disabled = [bool]$DisableStartup
            })
        }
        catch {
            $warnings += "Failed to stop service '$($service.Name)': $($_.Exception.Message)"
        }
    }
}

$data = [pscustomobject]@{
    ServicesBefore = @($services)
    ServicesStopped = @($results)
    DisableStartup = [bool]$DisableStartup
    Notes = @(
        'This script stops the local sync services before the uninstall step.',
        'It can also disable the service startup type if requested.'
    )
}

$summary = @(
    "Services targeted: $(@($targets).Count)",
    "Services stopped: $(@($results).Count)",
    "Startup disabled: $DisableStartup"
)

$artifact = Save-EntraArtifact -Context $context -Data $data -SummaryLines $summary -Warnings $warnings
[pscustomobject]@{
    ScriptName = $context.ScriptName
    TextPath = $artifact.TextPath
    JsonPath = $artifact.JsonPath
    RunRoot = $context.RunRoot
}
