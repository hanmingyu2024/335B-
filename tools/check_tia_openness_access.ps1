param(
    [string]$PortalRoot = ''
)

$ErrorActionPreference = 'Stop'

function Resolve-PortalRoot {
    param([string]$ConfiguredPath)

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        $candidates += $ConfiguredPath
    }
    if (-not [string]::IsNullOrWhiteSpace($env:TIA_PORTAL_ROOT)) {
        $candidates += $env:TIA_PORTAL_ROOT
    }
    $candidates += @(
        'D:\Program Files\Siemens\Automation\Portal V17',
        'C:\Program Files\Siemens\Automation\Portal V17'
    )

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        $resolved = [System.IO.Path]::GetFullPath($candidate)
        $dllPath = Join-Path $resolved 'PublicAPI\V17\Siemens.Engineering.dll'
        if (Test-Path -LiteralPath $dllPath) {
            return $resolved
        }
    }

    throw "TIA Portal V17 PublicAPI not found. Set -PortalRoot or TIA_PORTAL_ROOT."
}

function Assert-TokenHasOpennessGroup {
    $groups = (whoami /groups) | Out-String
    if ($groups -notmatch 'Siemens TIA Openness') {
        throw @"
Current logon token does not include 'Siemens TIA Openness'.
If you have just been added to this Windows group, sign out of Windows and sign in again.
"@
    }
}

$resolvedPortalRoot = Resolve-PortalRoot -ConfiguredPath $PortalRoot
Assert-TokenHasOpennessGroup

Add-Type -Path (Join-Path $resolvedPortalRoot 'Bin\PublicAPI\Siemens.Engineering.Contract.dll')
Add-Type -Path (Join-Path $resolvedPortalRoot 'Bin\PublicAPI\Siemens.Engineering.ClientAdapter.Interfaces.dll')
Add-Type -Path (Join-Path $resolvedPortalRoot 'PublicAPI\V17\Siemens.Engineering.dll')

$tia = $null
try {
    $tia = New-Object Siemens.Engineering.TiaPortal([Siemens.Engineering.TiaPortalMode]::WithoutUserInterface)
    Write-Host "Openness access OK. PortalRoot=$resolvedPortalRoot"
}
catch {
    throw @"
TIA Openness session probe failed.
Root cause: $($_.Exception.Message)
Action: verify group membership and re-login, then re-run this check.
"@
}
finally {
    if ($null -ne $tia) {
        $tia.Dispose()
    }
}
