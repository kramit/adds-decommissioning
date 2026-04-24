[CmdletBinding()]
param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\output'),
    [string]$RunId,
    [string]$DiscoveryRunRoot,
    [string]$DiscoveryIndexPath
)

$commonPath = Join-Path $PSScriptRoot 'lib\Decommission.Common.ps1'
. $commonPath

$context = New-DecommissionContext -ScriptName 'Build-DCDecommissionPlan' -OutputRoot $OutputRoot -RunId $RunId
$assessment = Get-DCDecommissionAssessment -DiscoveryRunRoot $DiscoveryRunRoot -DiscoveryIndexPath $DiscoveryIndexPath
$environment = Get-ExecutionEnvironmentSnapshot
$recentEvents = @(Get-RecentEventLogEntries)
$warnings = @($assessment.Warnings)

Start-DecommissionTranscript -Context $context
Write-DecommissionLog -Path $context.LogPath -Message 'Plan build started'
Write-DecommissionLog -Path $context.LogPath -Message "Discovery index: $($assessment.DiscoveryIndexPath)"
Write-DecommissionLog -Path $context.LogPath -Message "Discovery root: $($assessment.DiscoveryRunRoot)"

try {
    $tables = @{}
    foreach ($entry in $assessment.Tables.GetEnumerator()) {
        $tables[$entry.Key] = @($entry.Value)
    }

    $tables['ExecutionEnvironmentModules'] = @($environment.Modules)
    $tables['ExecutionEnvironmentServices'] = @($environment.Services)
    $tables['RecentEvents'] = @($recentEvents)

    $data = [pscustomobject]@{
        RunId = $context.RunId
        DiscoveryIndexPath = $assessment.DiscoveryIndexPath
        DiscoveryRunRoot = $assessment.DiscoveryRunRoot
        CurrentHost = $assessment.CurrentHost
        Environment = $environment
        Assessment = [pscustomobject]@{
            CanProceed = $assessment.CanProceed
            SyncClassification = $assessment.SyncClassification
            Blockers = @($assessment.Blockers)
            Recommendations = @($assessment.Recommendations)
            HeldRoles = @($assessment.HeldRoles)
            ReplicationFailures = @($assessment.ReplicationFailures)
            SummaryLines = @($assessment.SummaryLines)
        }
        SourceArtifacts = [pscustomobject]@{
            Discovery = $assessment.SourceArtifacts
        }
        Notes = @(
            'This script builds a human-reviewable decommission plan from the discovery artifacts.',
            'If the plan reports blockers, resolve them or explicitly choose a bypass path before running the execution script.'
        )
    }

    $summary = @(
        "Discovery run root: $($assessment.DiscoveryRunRoot)",
        "Current host: $($assessment.CurrentHost)",
        "Can proceed: $($assessment.CanProceed)",
        "Blockers: $(@($assessment.Blockers).Count)",
        "Recommendations: $(@($assessment.Recommendations).Count)",
        "Sync footprint: $($assessment.SyncClassification)"
    )

    $artifact = Save-DecommissionArtifact -Context $context -Data $data -SummaryLines $summary -Warnings $warnings -Tables $tables
    Write-DecommissionLog -Path $context.LogPath -Message "Artifact JSON: $($artifact.JsonPath)"
    Write-DecommissionLog -Path $context.LogPath -Message "Artifact TXT: $($artifact.TextPath)"
}
finally {
    Stop-DecommissionTranscript
}

[pscustomobject]@{
    ScriptName = $context.ScriptName
    TextPath = $artifact.TextPath
    JsonPath = $artifact.JsonPath
    CsvFiles = $artifact.CsvFiles
    RunRoot = $context.RunRoot
    CanProceed = $assessment.CanProceed
    BlockerCount = @($assessment.Blockers).Count
    RecommendationCount = @($assessment.Recommendations).Count
}
