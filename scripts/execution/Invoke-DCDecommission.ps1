[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\output'),
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
    [System.Management.Automation.PSCredential]$Credential,
    [System.Management.Automation.PSCredential]$DnsDelegationRemovalCredential,
    [SecureString]$LocalAdministratorPassword
)

$commonPath = Join-Path $PSScriptRoot 'lib\Decommission.Common.ps1'
. $commonPath

$context = New-DecommissionContext -ScriptName 'Invoke-DCDecommission' -OutputRoot $OutputRoot -RunId $RunId
$assessment = Get-DCDecommissionAssessment -DiscoveryRunRoot $DiscoveryRunRoot -DiscoveryIndexPath $DiscoveryIndexPath
$environment = Get-ExecutionEnvironmentSnapshot
$recentEvents = @(Get-RecentEventLogEntries)
$warnings = New-Object System.Collections.Generic.List[string]
foreach ($warning in @($assessment.Warnings)) {
    $warnings.Add($warning)
}

$executionSteps = New-Object System.Collections.Generic.List[object]
$preflightAttachments = @{}
$postflightAttachments = @{}
$failure = $null
$executed = $false
$rebootExpected = $false

function Add-StepRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [datetime]$StartTime,

        [Parameter(Mandatory = $true)]
        [datetime]$EndTime,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [object]$Details,

        [string]$ErrorMessage
    )

    $executionSteps.Add([pscustomobject]@{
        Name = $Name
        Status = $Status
        StartTime = $StartTime
        EndTime = $EndTime
        DurationSeconds = [math]::Round(($EndTime - $StartTime).TotalSeconds, 3)
        Details = $Details
        ErrorMessage = $ErrorMessage
    })
}

function Invoke-LoggedStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    $start = Get-Date
    Write-DecommissionLog -Path $context.LogPath -Message "START $Name"

    try {
        $result = & $Action
        $end = Get-Date
        Add-StepRecord -Name $Name -StartTime $start -EndTime $end -Status 'Succeeded' -Details $result
        Write-DecommissionLog -Path $context.LogPath -Message "END $Name succeeded"
        return $result
    }
    catch {
        $end = Get-Date
        Add-StepRecord -Name $Name -StartTime $start -EndTime $end -Status 'Failed' -ErrorMessage $_.Exception.Message -Details [pscustomobject]@{
            Exception = $_.Exception.Message
            FullyQualifiedErrorId = $_.FullyQualifiedErrorId
            ScriptStackTrace = $_.ScriptStackTrace
        }
        Write-DecommissionLog -Path $context.LogPath -Message "END $Name failed: $($_.Exception.Message)"
        throw
    }
}

Start-DecommissionTranscript -Context $context
Write-DecommissionLog -Path $context.LogPath -Message "Run started"
Write-DecommissionLog -Path $context.LogPath -Message "Discovery index: $($assessment.DiscoveryIndexPath)"
Write-DecommissionLog -Path $context.LogPath -Message "Discovery root: $($assessment.DiscoveryRunRoot)"
Write-DecommissionLog -Path $context.LogPath -Message "Execute requested: $Execute"

$currentState = [pscustomobject]@{
    Environment = $environment
    RecentEvents = @($recentEvents)
    DiscoverySummary = [pscustomobject]@{
        CurrentHost = $assessment.CurrentHost
        CanProceed = $assessment.CanProceed
        SyncClassification = $assessment.SyncClassification
        Blockers = @($assessment.Blockers)
        Recommendations = @($assessment.Recommendations)
    }
}

try {
    $preflightAttachments['dcdiag-preflight'] = @()
    $preflightAttachments['repadmin-preflight'] = @()

    if (Get-Command dcdiag.exe -ErrorAction SilentlyContinue) {
        $dcdiag = Invoke-ExternalCommand -FilePath 'dcdiag.exe' -Arguments @('/test:advertising', '/test:replications', '/test:sysvolcheck', '/test:dns', '/v')
        $preflightAttachments['dcdiag-preflight'] = @($dcdiag.Output)
        $currentState | Add-Member -NotePropertyName DcDiagPreflight -NotePropertyValue $dcdiag -Force
    }
    else {
        $warnings.Add('dcdiag.exe was not available for preflight diagnostics.')
    }

    if (Get-Command repadmin.exe -ErrorAction SilentlyContinue) {
        $repadmin = Invoke-ExternalCommand -FilePath 'repadmin.exe' -Arguments @('/replsummary')
        $preflightAttachments['repadmin-preflight'] = @($repadmin.Output)
        $currentState | Add-Member -NotePropertyName RepAdminPreflight -NotePropertyValue $repadmin -Force
    }
    else {
        $warnings.Add('repadmin.exe was not available for preflight diagnostics.')
    }

    if (-not $Execute) {
        Write-DecommissionLog -Path $context.LogPath -Message 'Execute switch not supplied; plan-only run completed.'
    }
    else {
        if (-not $BypassBlockers -and -not $assessment.CanProceed) {
            $blockerText = @($assessment.Blockers | ForEach-Object { "$($_.Category): $($_.Finding)" }) -join '; '
            throw "Blocked by discovery assessment: $blockerText"
        }

        if ($PSCmdlet.ShouldProcess($assessment.CurrentHost, 'decommission domain controller')) {
            $executed = $true
            $cmdletParams = @{
                Force = $true
                ErrorAction = 'Stop'
            }

            if ($SkipPreChecks) {
                $cmdletParams.SkipPreChecks = $true
            }
            if ($NoRebootOnCompletion) {
                $cmdletParams.NoRebootOnCompletion = $true
            }
            else {
                $rebootExpected = $true
            }
            if ($ForceRemoval) {
                $cmdletParams.ForceRemoval = $true
            }
            if ($LastDomainControllerInDomain) {
                $cmdletParams.LastDomainControllerInDomain = $true
            }
            if ($IgnoreLastDCInDomainMismatch) {
                $cmdletParams.IgnoreLastDCInDomainMismatch = $true
            }
            if ($IgnoreLastDnsServerForZone) {
                $cmdletParams.IgnoreLastDnsServerForZone = $true
            }
            if ($RemoveApplicationPartitions) {
                $cmdletParams.RemoveApplicationPartitions = $true
            }
            if ($RemoveDnsDelegation) {
                $cmdletParams.RemoveDnsDelegation = $true
            }
            if ($DemoteOperationMasterRole) {
                $cmdletParams.DemoteOperationMasterRole = $true
            }
            if ($RetainDCMetadata) {
                $cmdletParams.RetainDCMetadata = $true
            }
            if ($Credential) {
                $cmdletParams.Credential = $Credential
            }
            if ($DnsDelegationRemovalCredential) {
                $cmdletParams.DnsDelegationRemovalCredential = $DnsDelegationRemovalCredential
            }
            if ($LocalAdministratorPassword) {
                $cmdletParams.LocalAdministratorPassword = $LocalAdministratorPassword
            }

            $demotionResult = Invoke-LoggedStep -Name 'Uninstall-ADDSDomainController' -Action {
                Uninstall-ADDSDomainController @cmdletParams
            }

            $currentState | Add-Member -NotePropertyName DemotionResult -NotePropertyValue $demotionResult -Force

            if ($ForceRemoval) {
                $warnings.Add('Force removal was used. Metadata cleanup on a healthy DC is still required.')
            }

            if ($NoRebootOnCompletion) {
                $postflightAttachments['dcdiag-postflight'] = @()
                $postflightAttachments['repadmin-postflight'] = @()
                if (Get-Command dcdiag.exe -ErrorAction SilentlyContinue) {
                    $dcdiagPost = Invoke-ExternalCommand -FilePath 'dcdiag.exe' -Arguments @('/test:advertising', '/test:replications', '/test:sysvolcheck', '/test:dns', '/v')
                    $postflightAttachments['dcdiag-postflight'] = @($dcdiagPost.Output)
                    $currentState | Add-Member -NotePropertyName DcDiagPostflight -NotePropertyValue $dcdiagPost -Force
                }
                if (Get-Command repadmin.exe -ErrorAction SilentlyContinue) {
                    $repadminPost = Invoke-ExternalCommand -FilePath 'repadmin.exe' -Arguments @('/replsummary')
                    $postflightAttachments['repadmin-postflight'] = @($repadminPost.Output)
                    $currentState | Add-Member -NotePropertyName RepAdminPostflight -NotePropertyValue $repadminPost -Force
                }

                $postflightState = [pscustomobject]@{
                    Environment = Get-ExecutionEnvironmentSnapshot
                    RecentEvents = @(Get-RecentEventLogEntries)
                }
                $currentState | Add-Member -NotePropertyName Postflight -NotePropertyValue $postflightState -Force
            }
        }
    }
}
catch {
    $failure = $_
    Write-DecommissionLog -Path $context.LogPath -Message "Run failed: $($_.Exception.Message)"
}
finally {
    $tables = @{}
    foreach ($entry in $assessment.Tables.GetEnumerator()) {
        $tables[$entry.Key] = @($entry.Value)
    }

    $tables['ExecutionEnvironmentModules'] = @($environment.Modules)
    $tables['ExecutionEnvironmentServices'] = @($environment.Services)
    $tables['RecentEvents'] = @($recentEvents)
    $tables['Blockers'] = @($assessment.Blockers)
    $tables['Recommendations'] = @($assessment.Recommendations)
    $tables['ExecutionSteps'] = @($executionSteps)

    if ($currentState.PSObject.Properties.Name -contains 'Postflight') {
        $tables['PostflightRecentEvents'] = @($currentState.Postflight.RecentEvents)
        $tables['PostflightModules'] = @($currentState.Postflight.Environment.Modules)
        $tables['PostflightServices'] = @($currentState.Postflight.Environment.Services)
    }

    $summary = @(
        "Discovery run root: $($assessment.DiscoveryRunRoot)",
        "Current host: $($assessment.CurrentHost)",
        "Execute requested: $Execute",
        "Executed: $executed",
        "Can proceed: $($assessment.CanProceed)",
        "Blockers: $(@($assessment.Blockers).Count)",
        "Recommendations: $(@($assessment.Recommendations).Count)",
        "Step records: $(@($executionSteps).Count)",
        "Reboot expected: $rebootExpected",
        "Failure: $([bool]$failure)"
    )

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
        Execution = [pscustomobject]@{
            ExecuteRequested = $Execute
            Executed = $executed
            RebootExpected = $rebootExpected
            StepResults = @($executionSteps)
            Failure = if ($failure) {
                [pscustomobject]@{
                    Exception = $failure.Exception.Message
                    FullyQualifiedErrorId = $failure.FullyQualifiedErrorId
                    ScriptStackTrace = $failure.ScriptStackTrace
                }
            } else { $null }
        }
        SourceArtifacts = [pscustomobject]@{
            Discovery = $assessment.SourceArtifacts
        }
        Notes = @(
            'This script uses the discovery pack as input for the decommission decision.',
            'A transcript and command-line diagnostics are captured to help troubleshoot failed demotions.',
            'If sync tooling is present on the host, finish the EntraConnect workflow before demotion.'
        )
    }

    $textAttachments = @{}
    foreach ($attachment in $preflightAttachments.GetEnumerator()) {
        $textAttachments[$attachment.Key] = @($attachment.Value)
    }
    foreach ($attachment in $postflightAttachments.GetEnumerator()) {
        $textAttachments[$attachment.Key] = @($attachment.Value)
    }

    $artifact = Save-DecommissionArtifact -Context $context -Data $data -SummaryLines $summary -Warnings @($warnings) -Tables $tables -TextAttachments $textAttachments

    Write-DecommissionLog -Path $context.LogPath -Message "Artifact JSON: $($artifact.JsonPath)"
    Write-DecommissionLog -Path $context.LogPath -Message "Artifact TXT: $($artifact.TextPath)"
    Stop-DecommissionTranscript
}

if ($failure) {
    throw $failure
}

[pscustomobject]@{
    ScriptName = $context.ScriptName
    TextPath = $artifact.TextPath
    JsonPath = $artifact.JsonPath
    CsvFiles = $artifact.CsvFiles
    TranscriptPath = $context.TranscriptPath
    RunRoot = $context.RunRoot
    Executed = $executed
    RebootExpected = $rebootExpected
    CanProceed = $assessment.CanProceed
    BlockerCount = @($assessment.Blockers).Count
}
