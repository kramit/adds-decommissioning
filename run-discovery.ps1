param(
    [string]$OutputRoot,
    [string]$RunId
)

$exportScript = Join-Path $PSScriptRoot 'scripts\discovery\Export-DiscoveryPack.ps1'

if (-not (Test-Path $exportScript)) {
    throw "Missing discovery entrypoint: $exportScript"
}

& $exportScript @PSBoundParameters
