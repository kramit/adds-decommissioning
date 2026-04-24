. (Join-Path $PSScriptRoot '..\lib\EntraConnect.Common.ps1')

function New-EntraConnectLocalContext {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName,

        [string]$OutputRoot = (Join-Path $PSScriptRoot '..\..\output'),

        [string]$RunId
    )

    if (-not $RunId) {
        $RunId = Get-Date -Format 'yyyyMMdd-HHmmss'
    }

    $safeScriptName = $ScriptName -replace '[^A-Za-z0-9._-]', '_'
    $runRoot = Join-Path (Join-Path $OutputRoot 'entra-connect-local') $RunId
    $artifactRoot = Join-Path $runRoot $safeScriptName

    New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null

    [pscustomobject]@{
        ScriptName   = $ScriptName
        SafeName     = $safeScriptName
        RunId        = $RunId
        OutputRoot   = $OutputRoot
        RunRoot      = $runRoot
        ArtifactRoot = $artifactRoot
        JsonPath     = Join-Path $artifactRoot "$safeScriptName.json"
        TextPath     = Join-Path $artifactRoot "$safeScriptName.txt"
    }
}

function Test-IsLocalAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-EntraConnectLocalInstallEntries {
    $roots = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $matches = New-Object System.Collections.Generic.List[object]

    foreach ($root in $roots) {
        try {
            $items = Get-ItemProperty $root -ErrorAction SilentlyContinue
            foreach ($item in @($items)) {
                if ($item.DisplayName -match 'Azure AD Connect|Microsoft Entra Connect|Microsoft Azure AD Sync|Entra Connect Sync|Azure AD Sync') {
                    $productCode = $null
                    if ($item.UninstallString -match '\{[0-9A-Fa-f-]{36}\}') {
                        $productCode = $Matches[0]
                    }

                    $matches.Add([pscustomobject]@{
                        DisplayName = $item.DisplayName
                        DisplayVersion = $item.DisplayVersion
                        Publisher = $item.Publisher
                        InstallLocation = $item.InstallLocation
                        UninstallString = $item.UninstallString
                        QuietUninstallString = $item.QuietUninstallString
                        ProductCode = $productCode
                        RegistryPath = $item.PSPath
                    })
                }
            }
        }
        catch {
        }
    }

    return @($matches)
}

function Get-EntraConnectLocalServices {
    param(
        [string[]]$Names = @(
            'ADSync',
            'AzureADConnectProvisioningAgent',
            'AzureADConnectAuthenticationAgent',
            'Microsoft Azure AD Sync',
            'Microsoft Entra Connect'
        )
    )

    $services = New-Object System.Collections.Generic.List[object]

    foreach ($name in $Names) {
        try {
            $service = Get-Service -Name $name -ErrorAction Stop
            $services.Add([pscustomobject]@{
                Name = $service.Name
                DisplayName = $service.DisplayName
                Status = $service.Status
                StartType = (Get-CimInstance Win32_Service -Filter "Name='$($service.Name)'" -ErrorAction SilentlyContinue).StartMode
            })
        }
        catch {
        }
    }

    return @($services)
}

function Get-EntraConnectLocalScheduledTasks {
    $matches = @()

    try {
        $matches = @(Get-ScheduledTask | Where-Object {
            $_.TaskName -match 'ADSync|Azure AD|Entra|Sync'
        } | Select-Object TaskName, TaskPath, State)
    }
    catch {
    }

    return @($matches)
}

function Convert-MsiUninstallString {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UninstallString
    )

    if ($UninstallString -notmatch 'msiexec(\.exe)?') {
        return $null
    }

    if ($UninstallString -match '\{[0-9A-Fa-f-]{36}\}') {
        $productCode = $Matches[0]
        return "msiexec.exe /x $productCode /qn /norestart"
    }

    return $null
}

function Invoke-UninstallCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandLine
    )

    $process = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $CommandLine) -Wait -PassThru -WindowStyle Hidden
    return [pscustomobject]@{
        CommandLine = $CommandLine
        ExitCode = $process.ExitCode
    }
}
