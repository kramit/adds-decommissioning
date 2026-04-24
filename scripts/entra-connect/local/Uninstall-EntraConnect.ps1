 [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\..\output'),
    [string]$RunId,
    [string]$DisplayName,
    [string]$ProductCode,
    [switch]$Execute
)

$commonPath = Join-Path $PSScriptRoot 'EntraConnect.Local.Common.ps1'
. $commonPath

$context = New-EntraConnectLocalContext -ScriptName 'Uninstall-EntraConnect' -OutputRoot $OutputRoot -RunId $RunId
$warnings = @()

$entries = @(Get-EntraConnectLocalInstallEntries)
if (-not $entries) {
    throw 'No Entra Connect installation was detected on this host.'
}

$candidate = $entries
if ($DisplayName) {
    $candidate = @($candidate | Where-Object { $_.DisplayName -eq $DisplayName })
}
if ($ProductCode) {
    $candidate = @($candidate | Where-Object { $_.ProductCode -eq $ProductCode })
}

if ($candidate.Count -gt 1) {
    throw "More than one uninstall candidate was found. Specify -DisplayName or -ProductCode. Candidates: $(@($candidate.DisplayName) -join ', ')"
}

$selected = $candidate | Select-Object -First 1
if (-not $selected) {
    throw 'No matching uninstall candidate was found.'
}

$msiCommand = Convert-MsiUninstallString -UninstallString $selected.UninstallString
$plannedCommand = if ($msiCommand) {
    $msiCommand
}
elseif ($selected.UninstallString) {
    $selected.UninstallString
}
else {
    $null
}

$execution = $null
$executed = $false

if ($Execute) {
    if (-not $plannedCommand) {
        throw "No executable uninstall command could be derived for '$($selected.DisplayName)'."
    }

    if ($PSCmdlet.ShouldProcess($selected.DisplayName, 'uninstall Microsoft Entra Connect')) {
        $execution = Invoke-UninstallCommand -CommandLine $plannedCommand
        $executed = $true
    }
}

$data = [pscustomobject]@{
    Candidate = $selected
    PlannedCommand = $plannedCommand
    Executed = $executed
    Execution = $execution
    Notes = @(
        'This script finds the local Entra Connect uninstall candidate and can execute it when -Execute is supplied.',
        'If the uninstall string is not MSI-based, review the command before running it.'
    )
}

$summary = @(
    "Selected: $($selected.DisplayName)",
    "Product code: $($selected.ProductCode)",
    "Execute requested: $Execute",
    "Executed: $executed"
)

$artifact = Save-EntraArtifact -Context $context -Data $data -SummaryLines $summary -Warnings $warnings
[pscustomobject]@{
    ScriptName = $context.ScriptName
    TextPath = $artifact.TextPath
    JsonPath = $artifact.JsonPath
    RunRoot = $context.RunRoot
    Executed = $executed
}
