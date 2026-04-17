param(
    [string]$TemplateRoot = '',
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot '..\artifacts\tia_v17'),
    [string]$ProjectName = '3358B_FlexLine_V17',
    [string]$PortalRoot = ''
)

$ErrorActionPreference = 'Stop'

function Get-DefaultTemplateRoot {
    $parent = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $candidates = @(Get-ChildItem -LiteralPath $parent -Directory | Where-Object { $_.Name -like '3358B*' } | Sort-Object Name)
    if ($candidates.Count -eq 0) {
        throw "Could not find a template directory matching '3358B*' under '$parent'."
    }
    return $candidates[0].FullName
}

function Assert-InsidePath {
    param(
        [string]$BasePath,
        [string]$ChildPath
    )

    $base = [System.IO.Path]::GetFullPath($BasePath)
    $child = [System.IO.Path]::GetFullPath($ChildPath)
    if (-not $child.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to operate outside root. Root='$base' Child='$child'"
    }
}

function Reset-Directory {
    param(
        [string]$BasePath,
        [string]$Path
    )

    Assert-InsidePath -BasePath $BasePath -ChildPath $Path
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Get-ServiceByType {
    param(
        [object]$Target,
        [type]$ServiceType
    )

    $method = @(
        $Target.GetType().GetMethods() |
            Where-Object { $_.Name -eq 'GetService' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 0 }
    )[0]

    if ($null -eq $method) {
        throw "GetService<T>() not found on type '$($Target.GetType().FullName)'."
    }

    return $method.MakeGenericMethod($ServiceType).Invoke($Target, @())
}

function Get-PlcSoftware {
    param([object]$Device)

    $queue = New-Object 'System.Collections.Generic.Queue[object]'
    foreach ($item in $Device.DeviceItems) {
        $queue.Enqueue($item)
    }

    while ($queue.Count -gt 0) {
        $deviceItem = $queue.Dequeue()
        $container = Get-ServiceByType -Target $deviceItem -ServiceType ([Siemens.Engineering.HW.Features.SoftwareContainer])
        if ($null -ne $container -and $null -ne $container.Software -and $container.Software -is [Siemens.Engineering.SW.PlcSoftware]) {
            return [Siemens.Engineering.SW.PlcSoftware]$container.Software
        }

        foreach ($child in $deviceItem.DeviceItems) {
            $queue.Enqueue($child)
        }
    }

    throw "No PlcSoftware container found for device '$($Device.Name)'."
}

function Write-CompilerResult {
    param(
        [string]$Path,
        [object]$Result
    )

    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add("State: $($Result.State)")
    $lines.Add("WarningCount: $($Result.WarningCount)")
    $lines.Add("ErrorCount: $($Result.ErrorCount)")

    function Append-Messages {
        param(
            [object]$Messages,
            [string]$Indent,
            [System.Collections.Generic.List[string]]$Sink
        )

        foreach ($message in $Messages) {
            $Sink.Add("${Indent}Path: $($message.Path)")
            $Sink.Add("${Indent}State: $($message.State)")
            $Sink.Add("${Indent}Description: $($message.Description)")
            $Sink.Add("${Indent}WarningCount: $($message.WarningCount)")
            $Sink.Add("${Indent}ErrorCount: $($message.ErrorCount)")
            Append-Messages -Messages $message.Messages -Indent ($Indent + '  ') -Sink $Sink
        }
    }

    Append-Messages -Messages $Result.Messages -Indent '' -Sink $lines
    [System.IO.File]::WriteAllLines($Path, $lines, [System.Text.Encoding]::UTF8)
}

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

if (-not (Test-Path -LiteralPath $ArtifactRoot)) {
    New-Item -ItemType Directory -Path $ArtifactRoot -Force | Out-Null
}

if ([string]::IsNullOrWhiteSpace($TemplateRoot)) {
    $TemplateRoot = Get-DefaultTemplateRoot
}

$TemplateRoot = [System.IO.Path]::GetFullPath($TemplateRoot)
$ArtifactRoot = [System.IO.Path]::GetFullPath($ArtifactRoot)

$sourcesRoot = Join-Path $ArtifactRoot 'sources'
$projectRoot = Join-Path $ArtifactRoot 'project'
$logsRoot = Join-Path $ArtifactRoot 'logs'
$archivePath = Join-Path $ArtifactRoot ($ProjectName + '.zap17')

Reset-Directory -BasePath $ArtifactRoot -Path $projectRoot
Reset-Directory -BasePath $ArtifactRoot -Path $logsRoot

& (Join-Path $PSScriptRoot 'build_tia_external_sources.ps1') -TemplateRoot $TemplateRoot -OutputRoot $sourcesRoot

$manifestPath = Join-Path $sourcesRoot 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Manifest not found at '$manifestPath'."
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

$resolvedPortalRoot = Resolve-PortalRoot -ConfiguredPath $PortalRoot
Add-Type -Path (Join-Path $resolvedPortalRoot 'Bin\PublicAPI\Siemens.Engineering.Contract.dll')
Add-Type -Path (Join-Path $resolvedPortalRoot 'Bin\PublicAPI\Siemens.Engineering.ClientAdapter.Interfaces.dll')
Add-Type -Path (Join-Path $resolvedPortalRoot 'PublicAPI\V17\Siemens.Engineering.dll')

$tia = $null
$project = $null

try {
    $tia = New-Object Siemens.Engineering.TiaPortal([Siemens.Engineering.TiaPortalMode]::WithoutUserInterface)
    $project = $tia.Projects.Create((New-Object System.IO.DirectoryInfo($projectRoot)), $ProjectName)

    foreach ($station in $manifest.Stations) {
        $device = $project.Devices.CreateWithItem($station.TypeIdentifier, $station.DeviceItemName, $station.DeviceName)
        $plcSoftware = Get-PlcSoftware -Device $device

        $stationSources = @($manifest.Sources | Where-Object { $_.StationKey -eq $station.StationKey } | Sort-Object Order)
        foreach ($source in $stationSources) {
            $fullPath = Join-Path $sourcesRoot (Join-Path $station.StationKey $source.RelativePath)
            $externalSource = $plcSoftware.ExternalSourceGroup.ExternalSources.CreateFromFile($source.FileName, $fullPath)
            $externalSource.GenerateBlocksFromSource()
        }

        $compileResult = (Get-ServiceByType -Target $plcSoftware -ServiceType ([Siemens.Engineering.Compiler.ICompilable])).Compile()
        $compileLogPath = Join-Path $logsRoot ($station.StationKey + '_compile.txt')
        Write-CompilerResult -Path $compileLogPath -Result $compileResult

        if ([int]$compileResult.ErrorCount -gt 0) {
            throw "Compilation failed for $($station.StationKey). See '$compileLogPath'."
        }
    }

    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }

    $project.Save()
    $archiveDirectory = Split-Path -Parent $archivePath
    $archiveName = Split-Path -Leaf $archivePath
    $project.Archive(
        (New-Object System.IO.DirectoryInfo($archiveDirectory)),
        $archiveName,
        [Siemens.Engineering.ProjectArchivationMode]::Compressed
    )
    Write-Host "Project created: $projectRoot"
    Write-Host "Archive created: $archivePath"
}
finally {
    if ($null -ne $project -and $project.GetType().GetMethod('Close')) {
        $project.Close()
    }
    if ($null -ne $tia) {
        $tia.Dispose()
    }
}
