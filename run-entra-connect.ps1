param(
    [string]$OutputRoot,
    [string]$RunId,
    [string]$TenantId,
    [switch]$UseDeviceCode,
    [switch]$IncludeFullList
)

$entrypoint = Join-Path $PSScriptRoot 'scripts\entra-connect\Export-EntraConnectPack.ps1'

if (-not (Test-Path $entrypoint)) {
    throw "Missing EntraConnect entrypoint: $entrypoint"
}

& $entrypoint @PSBoundParameters
