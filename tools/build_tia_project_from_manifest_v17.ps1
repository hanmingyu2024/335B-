param(
    [string]$SourceManifestPath = (Join-Path $PSScriptRoot '..\artifacts\standard_line_workspace\tia_sources\manifest.json'),
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot '..\artifacts\standard_line_tia'),
    [string]$ProjectName = '',
    [string]$PortalRoot = '',
    [string]$IoPointsPath = '',
    [string]$WarningPolicyPath = '',
    [ValidateSet('compare', 'upsert', 'sync')]
    [string]$TagSyncMode = 'upsert',
    [switch]$SkipOpennessPrecheck
)

$ErrorActionPreference = 'Stop'

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

function Test-ObjectProperty {
    param(
        [object]$Object,
        [string]$Name
    )

    return ($null -ne $Object) -and ($null -ne $Object.PSObject.Properties[$Name])
}

function Resolve-TypeByName {
    param([string]$FullName)

    foreach ($assembly in [System.AppDomain]::CurrentDomain.GetAssemblies()) {
        $resolved = $assembly.GetType($FullName, $false)
        if ($null -ne $resolved) {
            return $resolved
        }
    }

    throw "Unable to resolve type '$FullName'."
}

function Get-EnumValue {
    param(
        [string]$TypeName,
        [string]$ValueName
    )

    $enumType = Resolve-TypeByName -FullName $TypeName
    return [System.Enum]::Parse($enumType, $ValueName, $true)
}

function Set-EngineeringAttribute {
    param(
        [object]$Target,
        [string]$Name,
        [object]$Value
    )

    ([Siemens.Engineering.IEngineeringObject]$Target).SetAttribute($Name, $Value)
}

function Try-SetEngineeringAttribute {
    param(
        [object]$Target,
        [string]$Name,
        [object]$Value,
        [switch]$Required
    )

    try {
        Set-EngineeringAttribute -Target $Target -Name $Name -Value $Value
    }
    catch {
        if ($Required) {
            throw
        }
        Write-Warning "Failed to set attribute '$Name' on '$($Target.GetType().FullName)': $($_.Exception.Message)"
    }
}

function Get-FirstNetworkInterface {
    param([object]$Device)

    $queue = New-Object 'System.Collections.Generic.Queue[object]'
    foreach ($item in $Device.DeviceItems) {
        $queue.Enqueue($item)
    }

    while ($queue.Count -gt 0) {
        $deviceItem = $queue.Dequeue()
        $interface = Get-ServiceByType -Target $deviceItem -ServiceType ([Siemens.Engineering.HW.Features.NetworkInterface])
        if ($null -ne $interface) {
            return $interface
        }

        foreach ($child in $deviceItem.DeviceItems) {
            $queue.Enqueue($child)
        }
    }

    return $null
}

function Get-FirstNode {
    param([object]$NetworkInterface)

    foreach ($node in $NetworkInterface.Nodes) {
        return $node
    }

    return $null
}

function Convert-InterfaceOperatingMode {
    param([string]$Value)

    $enumTypeName = 'Siemens.Engineering.HW.InterfaceOperatingModes'
    switch ($Value) {
        'None' {
            return Get-EnumValue -TypeName $enumTypeName -ValueName 'None'
        }
        'IoDevice' {
            return Get-EnumValue -TypeName $enumTypeName -ValueName 'IoDevice'
        }
        'IoController' {
            return Get-EnumValue -TypeName $enumTypeName -ValueName 'IoController'
        }
        'IoDeviceAndIoController' {
            $ioDevice = [int](Get-EnumValue -TypeName $enumTypeName -ValueName 'IoDevice')
            $ioController = [int](Get-EnumValue -TypeName $enumTypeName -ValueName 'IoController')
            $enumType = Resolve-TypeByName -FullName $enumTypeName
            return [System.Enum]::ToObject($enumType, ($ioDevice -bor $ioController))
        }
        'IoDevice, IoController' {
            return Convert-InterfaceOperatingMode -Value 'IoDeviceAndIoController'
        }
        'IoController, IoDevice' {
            return Convert-InterfaceOperatingMode -Value 'IoDeviceAndIoController'
        }
        default {
            throw "Unsupported interface operating mode '$Value'."
        }
    }
}

function Get-OrCreateSubnet {
    param(
        [object]$Project,
        [object]$ProjectNetwork
    )

    if ($null -eq $ProjectNetwork) {
        return $null
    }

    $subnetName = [string]$ProjectNetwork.SubnetName
    $subnet = $Project.Subnets.Find($subnetName)
    if ($null -eq $subnet) {
        $subnet = $Project.Subnets.Create([string]$ProjectNetwork.SubnetTypeIdentifier, $subnetName)
    }

    return $subnet
}

function Find-StationDefinition {
    param(
        [object[]]$Stations,
        [string]$StationKey
    )

    foreach ($station in $Stations) {
        if ((Test-ObjectProperty -Object $station -Name 'StationKey') -and ([string]$station.StationKey -eq $StationKey)) {
            return $station
        }
        if ((Test-ObjectProperty -Object $station -Name 'key') -and ([string]$station.key -eq $StationKey)) {
            return $station
        }
    }

    return $null
}

function Get-ProjectNetworkConfig {
    param(
        [object]$SourceManifest,
        [object]$LineManifest
    )

    if ((Test-ObjectProperty -Object $SourceManifest.Project -Name 'Network') -and ($null -ne $SourceManifest.Project.Network)) {
        return $SourceManifest.Project.Network
    }
    if (($null -ne $LineManifest) -and (Test-ObjectProperty -Object $LineManifest -Name 'network')) {
        return $LineManifest.network
    }

    return $null
}

function Get-StationNetworkConfig {
    param(
        [object]$SourceManifest,
        [object]$LineManifest,
        [string]$StationKey
    )

    $station = Find-StationDefinition -Stations @($SourceManifest.Stations) -StationKey $StationKey
    if (($null -ne $station) -and (Test-ObjectProperty -Object $station -Name 'Network')) {
        return $station.Network
    }

    if (($null -ne $LineManifest) -and (Test-ObjectProperty -Object $LineManifest -Name 'stations')) {
        $lineStation = Find-StationDefinition -Stations @($LineManifest.stations) -StationKey $StationKey
        if (($null -ne $lineStation) -and (Test-ObjectProperty -Object $lineStation -Name 'network')) {
            return $lineStation.network
        }
    }

    return $null
}

function Configure-StationNetwork {
    param(
        [object]$Device,
        [object]$Subnet,
        [object]$ProjectNetwork,
        [object]$StationNetwork
    )

    if (($null -eq $ProjectNetwork) -or ($null -eq $StationNetwork)) {
        return
    }

    $networkInterface = Get-FirstNetworkInterface -Device $Device
    if ($null -eq $networkInterface) {
        Write-Warning "Device '$($Device.Name)' has no network interface exposed through Openness."
        return
    }

    if (Test-ObjectProperty -Object $StationNetwork -Name 'interfaceOperatingMode') {
        $networkInterface.InterfaceOperatingMode = Convert-InterfaceOperatingMode -Value ([string]$StationNetwork.interfaceOperatingMode)
    }

    $node = Get-FirstNode -NetworkInterface $networkInterface
    if ($null -eq $node) {
        Write-Warning "Device '$($Device.Name)' has no network node exposed through Openness."
        return
    }

    if ($null -ne $Subnet) {
        try {
            $node.ConnectToSubnet($Subnet)
        }
        catch {
            if ($_.Exception.Message -notmatch 'connected') {
                throw
            }
        }
    }

    Try-SetEngineeringAttribute -Target $node -Name 'UseIpProtocol' -Value $true

    if (Test-ObjectProperty -Object $ProjectNetwork -Name 'ipProtocolSelection') {
        $ipSelection = Get-EnumValue -TypeName 'Siemens.Engineering.HW.IpProtocolSelection' -ValueName ([string]$ProjectNetwork.ipProtocolSelection)
        Try-SetEngineeringAttribute -Target $node -Name 'IpProtocolSelection' -Value $ipSelection -Required
    }
    if (Test-ObjectProperty -Object $ProjectNetwork -Name 'useRouter') {
        Try-SetEngineeringAttribute -Target $node -Name 'UseRouter' -Value ([bool]$ProjectNetwork.useRouter)
    }
    if ((Test-ObjectProperty -Object $ProjectNetwork -Name 'routerAddress') -and (-not [string]::IsNullOrWhiteSpace([string]$ProjectNetwork.routerAddress))) {
        Try-SetEngineeringAttribute -Target $node -Name 'RouterAddress' -Value ([string]$ProjectNetwork.routerAddress)
    }
    if ((Test-ObjectProperty -Object $ProjectNetwork -Name 'subnetMask') -and (-not [string]::IsNullOrWhiteSpace([string]$ProjectNetwork.subnetMask))) {
        Try-SetEngineeringAttribute -Target $node -Name 'SubnetMask' -Value ([string]$ProjectNetwork.subnetMask) -Required
    }
    if ((Test-ObjectProperty -Object $StationNetwork -Name 'ipAddress') -and (-not [string]::IsNullOrWhiteSpace([string]$StationNetwork.ipAddress))) {
        Try-SetEngineeringAttribute -Target $node -Name 'Address' -Value ([string]$StationNetwork.ipAddress) -Required
    }
    if (Test-ObjectProperty -Object $StationNetwork -Name 'autoGeneratePnDeviceName') {
        Try-SetEngineeringAttribute -Target $node -Name 'PnDeviceNameAutoGeneration' -Value ([bool]$StationNetwork.autoGeneratePnDeviceName)
    }
    if (
        (Test-ObjectProperty -Object $StationNetwork -Name 'pnDeviceName') -and
        (-not [bool]$StationNetwork.autoGeneratePnDeviceName) -and
        (-not [string]::IsNullOrWhiteSpace([string]$StationNetwork.pnDeviceName))
    ) {
        Try-SetEngineeringAttribute -Target $node -Name 'PnDeviceName' -Value ([string]$StationNetwork.pnDeviceName) -Required
    }
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

function Get-CompilerMessages {
    param([object]$Result)

    $sink = New-Object 'System.Collections.Generic.List[object]'

    function Append-Messages {
        param(
            [object]$Messages,
            [System.Collections.Generic.List[object]]$Target
        )

        foreach ($message in $Messages) {
            $Target.Add([ordered]@{
                    path = [string]$message.Path
                    state = [string]$message.State
                    description = [string]$message.Description
                    warning_count = [int]$message.WarningCount
                    error_count = [int]$message.ErrorCount
                })
            Append-Messages -Messages $message.Messages -Target $Target
        }
    }

    Append-Messages -Messages $Result.Messages -Target $sink
    return $sink.ToArray()
}

function Get-WarningCategory {
    param([string]$Description)

    $text = [string]$Description
    if ([string]::IsNullOrWhiteSpace($text)) {
        return 'generic_warning'
    }

    if ($text -match 'Inputs or outputs are used that do not exist in the configured hardware') {
        return 'hardware_address_out_of_range'
    }
    if ($text -match 'configured hardware') {
        return 'hardware_address_out_of_range'
    }
    if ($text -match '硬件') {
        return 'hardware_address_out_of_range'
    }

    return 'generic_warning'
}

function Get-DefaultWarningPolicy {
    return [ordered]@{
        version = '1.0'
        defaultWarningAction = 'allow'
        rules = @(
            [ordered]@{
                id = 'hardware_address_out_of_range'
                enabled = $true
                action = 'block'
            },
            [ordered]@{
                id = 'generic_warning'
                enabled = $true
                action = 'allow'
            }
        )
    }
}

function Get-WarningAction {
    param(
        [object]$Policy,
        [string]$Category
    )

    $defaultAction = 'allow'
    if ($null -ne $Policy.PSObject.Properties['defaultWarningAction']) {
        $defaultAction = [string]$Policy.defaultWarningAction
    }

    foreach ($rule in @($Policy.rules)) {
        if (-not [bool]$rule.enabled) {
            continue
        }
        if ([string]$rule.id -eq $Category) {
            return [string]$rule.action
        }
    }

    return $defaultAction
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Payload
    )

    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $Payload | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$SourceManifestPath = [System.IO.Path]::GetFullPath($SourceManifestPath)
$ArtifactRoot = [System.IO.Path]::GetFullPath($ArtifactRoot)
$manifestRoot = Split-Path -Parent $SourceManifestPath
$workspaceRoot = Split-Path -Parent $manifestRoot
$lineManifestPath = Join-Path $workspaceRoot 'config\line_manifest.json'

if ([string]::IsNullOrWhiteSpace($IoPointsPath)) {
    $IoPointsPath = Join-Path $workspaceRoot 'config\io_points.generated.json'
}
if ([string]::IsNullOrWhiteSpace($WarningPolicyPath)) {
    $WarningPolicyPath = Join-Path $workspaceRoot 'config\warning_policy.json'
}

if (Test-Path -LiteralPath $IoPointsPath) {
    $IoPointsPath = [System.IO.Path]::GetFullPath($IoPointsPath)
}
if (Test-Path -LiteralPath $WarningPolicyPath) {
    $WarningPolicyPath = [System.IO.Path]::GetFullPath($WarningPolicyPath)
}

Assert-InsidePath -BasePath $repoRoot -ChildPath $SourceManifestPath
Assert-InsidePath -BasePath $repoRoot -ChildPath $ArtifactRoot
if (Test-Path -LiteralPath $IoPointsPath) {
    Assert-InsidePath -BasePath $repoRoot -ChildPath $IoPointsPath
}
if (Test-Path -LiteralPath $WarningPolicyPath) {
    Assert-InsidePath -BasePath $repoRoot -ChildPath $WarningPolicyPath
}
if (Test-Path -LiteralPath $lineManifestPath) {
    Assert-InsidePath -BasePath $repoRoot -ChildPath $lineManifestPath
}

if (-not (Test-Path -LiteralPath $SourceManifestPath)) {
    throw "Source manifest not found at '$SourceManifestPath'."
}

$manifestText = [System.IO.File]::ReadAllText($SourceManifestPath, [System.Text.Encoding]::UTF8)
$manifest = $manifestText | ConvertFrom-Json
$ioPoints = @()
$lineManifest = $null
if (Test-Path -LiteralPath $IoPointsPath) {
    $ioPointsText = [System.IO.File]::ReadAllText($IoPointsPath, [System.Text.Encoding]::UTF8)
    $ioPoints = @($ioPointsText | ConvertFrom-Json)
}
if (Test-Path -LiteralPath $lineManifestPath) {
    $lineManifestText = [System.IO.File]::ReadAllText($lineManifestPath, [System.Text.Encoding]::UTF8)
    $lineManifest = $lineManifestText | ConvertFrom-Json
}

$warningPolicy = Get-DefaultWarningPolicy
if (Test-Path -LiteralPath $WarningPolicyPath) {
    $policyText = [System.IO.File]::ReadAllText($WarningPolicyPath, [System.Text.Encoding]::UTF8)
    $warningPolicy = $policyText | ConvertFrom-Json
}

if ([string]::IsNullOrWhiteSpace($ProjectName)) {
    $ProjectName = [string]$manifest.Project.Code
}

$resolvedPortalRoot = Resolve-PortalRoot -ConfiguredPath $PortalRoot
if (-not $SkipOpennessPrecheck) {
    & (Join-Path $PSScriptRoot 'check_tia_openness_access.ps1') -PortalRoot $resolvedPortalRoot
}

$projectRoot = Join-Path $ArtifactRoot 'project'
$logsRoot = Join-Path $ArtifactRoot 'logs'
$archivePath = Join-Path $ArtifactRoot ($ProjectName + '.zap17')

Reset-Directory -BasePath $ArtifactRoot -Path $projectRoot
Reset-Directory -BasePath $ArtifactRoot -Path $logsRoot

Add-Type -Path (Join-Path $resolvedPortalRoot 'Bin\PublicAPI\Siemens.Engineering.Contract.dll')
Add-Type -Path (Join-Path $resolvedPortalRoot 'Bin\PublicAPI\Siemens.Engineering.ClientAdapter.Interfaces.dll')
Add-Type -Path (Join-Path $resolvedPortalRoot 'PublicAPI\V17\Siemens.Engineering.dll')

$tia = $null
$project = $null
$warningSummary = @()
$tagSyncSummary = @()

try {
    $tia = New-Object Siemens.Engineering.TiaPortal([Siemens.Engineering.TiaPortalMode]::WithoutUserInterface)
    $project = $tia.Projects.Create((New-Object System.IO.DirectoryInfo($projectRoot)), $ProjectName)
    $projectNetwork = Get-ProjectNetworkConfig -SourceManifest $manifest -LineManifest $lineManifest
    $projectSubnet = Get-OrCreateSubnet -Project $project -ProjectNetwork $projectNetwork

    foreach ($station in $manifest.Stations) {
        $device = $project.Devices.CreateWithItem($station.TypeIdentifier, $station.DeviceItemName, $station.DeviceName)
        $plcSoftware = Get-PlcSoftware -Device $device
        $stationNetwork = Get-StationNetworkConfig -SourceManifest $manifest -LineManifest $lineManifest -StationKey ([string]$station.StationKey)

        Configure-StationNetwork `
            -Device $device `
            -Subnet $projectSubnet `
            -ProjectNetwork $projectNetwork `
            -StationNetwork $stationNetwork

        $stationSources = @($manifest.Sources | Where-Object { $_.StationKey -eq $station.StationKey } | Sort-Object Order)
        foreach ($source in $stationSources) {
            $fullPath = Join-Path $manifestRoot (Join-Path $station.StationKey $source.RelativePath)
            $externalSource = $plcSoftware.ExternalSourceGroup.ExternalSources.CreateFromFile($source.FileName, $fullPath)
            $externalSource.GenerateBlocksFromSource()
        }

        $stationIoPoints = @($ioPoints | Where-Object { $_.station_key -eq $station.StationKey })
        if ($stationIoPoints.Count -gt 0) {
            $tagReportPath = Join-Path $logsRoot ($station.StationKey + '_tag_sync.json')
            $stationTagReport = & (Join-Path $PSScriptRoot 'import_plc_tags_from_io_json_v17.ps1') `
                -PlcSoftware $plcSoftware `
                -IoPoints $stationIoPoints `
                -Project $project `
                -Mode $TagSyncMode `
                -ReportPath $tagReportPath
            $tagSyncSummary += [ordered]@{
                station = $station.StationKey
                report = $stationTagReport
            }
        }

        $compileResult = (Get-ServiceByType -Target $plcSoftware -ServiceType ([Siemens.Engineering.Compiler.ICompilable])).Compile()
        $compileLogPath = Join-Path $logsRoot ($station.StationKey + '_compile.txt')
        Write-CompilerResult -Path $compileLogPath -Result $compileResult

        if ([int]$compileResult.ErrorCount -gt 0) {
            throw "Compilation failed for $($station.StationKey). See '$compileLogPath'."
        }

        $messages = Get-CompilerMessages -Result $compileResult
        $stationWarnings = @()
        foreach ($message in $messages) {
            if ([string]$message.state -ne 'Warning') {
                continue
            }
            if ([string]::IsNullOrWhiteSpace([string]$message.description)) {
                continue
            }

            $category = Get-WarningCategory -Description ([string]$message.description)
            $action = Get-WarningAction -Policy $warningPolicy -Category $category
            $stationWarnings += [ordered]@{
                category = $category
                action = $action
                path = [string]$message.path
                description = [string]$message.description
            }
        }

        $blockedWarnings = @($stationWarnings | Where-Object { [string]$_.action -eq 'block' })
        $stationWarningPayload = [ordered]@{
            station = $station.StationKey
            compile_warning_count = [int]$compileResult.WarningCount
            warnings = $stationWarnings
            blocked_warnings = $blockedWarnings
        }

        $stationWarningPath = Join-Path $logsRoot ($station.StationKey + '_warning_summary.json')
        Write-JsonFile -Path $stationWarningPath -Payload $stationWarningPayload
        $warningSummary += $stationWarningPayload

        if ($blockedWarnings.Count -gt 0) {
            $firstBlocked = $blockedWarnings[0]
            throw "Compilation warning blocked by policy for $($station.StationKey): [$($firstBlocked.category)] $($firstBlocked.description). See '$stationWarningPath'."
        }
    }

    Write-JsonFile -Path (Join-Path $logsRoot 'warning_summary.json') -Payload $warningSummary
    Write-JsonFile -Path (Join-Path $logsRoot 'tag_sync_summary.json') -Payload $tagSyncSummary

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
    Write-Host "Warnings summary: $(Join-Path $logsRoot 'warning_summary.json')"
    Write-Host "Tag sync summary: $(Join-Path $logsRoot 'tag_sync_summary.json')"
}
finally {
    if ($null -ne $project -and $project.GetType().GetMethod('Close')) {
        $project.Close()
    }
    if ($null -ne $tia) {
        $tia.Dispose()
    }
}
