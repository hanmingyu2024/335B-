param(
    [string]$ManifestPath = (Join-Path $PSScriptRoot '..\standard_line_template\line_manifest.sample.json'),
    [string]$WorkspaceRoot = (Join-Path $PSScriptRoot '..\artifacts\standard_line_workspace'),
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot '..\artifacts\standard_line_tia'),
    [string]$WorkbookPath = '',
    [string]$PortalRoot = '',
    [string]$WarningPolicyPath = '',
    [ValidateSet('compare', 'upsert', 'sync')]
    [string]$TagSyncMode = 'upsert',
    [switch]$BuildTiaProject,
    [switch]$GenerateIoAssets = $true,
    [switch]$AllowIoMismatch,
    [switch]$SkipOpennessPrecheck,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'new_standard_line_project.ps1') `
    -ManifestPath $ManifestPath `
    -OutputRoot $WorkspaceRoot `
    -Force:$Force

if ($GenerateIoAssets) {
    $pythonArgs = @(
        (Join-Path $PSScriptRoot 'generate_io_assets_from_workbook.py'),
        '--workspace-root',
        $WorkspaceRoot
    )
    if (-not [string]::IsNullOrWhiteSpace($WorkbookPath)) {
        $pythonArgs += @('--workbook-path', $WorkbookPath)
    }
    if ($AllowIoMismatch) {
        $pythonArgs += '--allow-io-mismatch'
    }
    & python @pythonArgs
}

if ($BuildTiaProject) {
    if (-not $SkipOpennessPrecheck) {
        & (Join-Path $PSScriptRoot 'check_tia_openness_access.ps1') -PortalRoot $PortalRoot
    }

    $buildParams = @{
        SourceManifestPath = (Join-Path $WorkspaceRoot 'tia_sources\manifest.json')
        ArtifactRoot = $ArtifactRoot
        TagSyncMode = $TagSyncMode
        SkipOpennessPrecheck = $true
    }
    if (-not [string]::IsNullOrWhiteSpace($PortalRoot)) {
        $buildParams.PortalRoot = $PortalRoot
    }
    if (-not [string]::IsNullOrWhiteSpace($WarningPolicyPath)) {
        $buildParams.WarningPolicyPath = $WarningPolicyPath
    }

    & (Join-Path $PSScriptRoot 'build_tia_project_from_manifest_v17.ps1') @buildParams
}
