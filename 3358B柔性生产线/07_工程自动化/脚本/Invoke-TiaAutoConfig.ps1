[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$LinksCsvPath,
    [switch]$PlanOnly,
    [switch]$SkipTemplateClone,
    [switch]$SkipOnlineValidation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host ("[TIA-AUTO] {0}" -f $Message)
}

function Get-RepoRoot {
    $scriptDir = Split-Path -Parent $PSCommandPath
    return (Resolve-Path (Join-Path $scriptDir "..\..")).Path
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "配置文件不存在: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Import-LinkCsv {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "通信点 CSV 不存在: $Path"
    }
    return Import-Csv -LiteralPath $Path -Encoding UTF8
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Test-UniqueValues {
    param(
        [array]$Items,
        [string]$PropertyName,
        [string]$Label
    )

    $duplicates = $Items |
        Group-Object -Property $PropertyName |
        Where-Object { $_.Count -gt 1 }

    if ($duplicates) {
        $names = ($duplicates | Select-Object -ExpandProperty Name) -join ", "
        throw "$Label 存在重复值: $names"
    }
}

function Test-IpAddressFormat {
    param([string]$IpAddress)
    $null = [System.Net.IPAddress]::Parse($IpAddress)
}

function Resolve-TiaAssemblyPath {
    param($Config)

    if ($Config.openness.assemblyPath) {
        if (Test-Path -LiteralPath $Config.openness.assemblyPath) {
            return (Resolve-Path $Config.openness.assemblyPath).Path
        }
        throw "指定的 Siemens.Engineering.dll 不存在: $($Config.openness.assemblyPath)"
    }

    $baseDirs = @(
        "C:\Program Files\Siemens\Automation",
        "C:\Program Files (x86)\Siemens\Automation",
        "D:\Program Files\Siemens\Automation",
        "D:\Program Files (x86)\Siemens\Automation",
        "E:\Program Files\Siemens\Automation",
        "E:\Program Files (x86)\Siemens\Automation"
    )

    $candidates = @()
    foreach ($version in $Config.openness.preferredVersions) {
        foreach ($baseDir in $baseDirs) {
            $candidates += (Join-Path $baseDir "Portal $version\PublicAPI\V$($version.TrimStart('V'))\Siemens.Engineering.dll")
            $candidates += (Join-Path $baseDir "Portal $version\PublicAPI\Siemens.Engineering.dll")
        }
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    return $null
}

function Test-AutomationConfig {
    param(
        $Config,
        [array]$Links
    )

    if (-not $Config.network.subnetName) {
        throw "network.subnetName 不能为空"
    }
    if (-not $Config.network.subnetTypeIdentifier) {
        throw "network.subnetTypeIdentifier 不能为空"
    }
    if (-not $Config.stations -or $Config.stations.Count -lt 2) {
        throw "stations 至少需要 2 个站点"
    }

    Test-UniqueValues -Items $Config.stations -PropertyName id -Label "stations.id"
    Test-UniqueValues -Items $Config.stations -PropertyName stationNo -Label "stations.stationNo"
    Test-UniqueValues -Items $Config.stations -PropertyName ipAddress -Label "stations.ipAddress"
    Test-UniqueValues -Items $Config.stations -PropertyName pnDeviceName -Label "stations.pnDeviceName"

    foreach ($station in $Config.stations) {
        if (-not $station.deviceName) {
            throw "站点 $($station.id) 缺少 deviceName"
        }
        Test-IpAddressFormat -IpAddress $station.ipAddress
    }

    if ($Config.network.routerAddress) {
        Test-IpAddressFormat -IpAddress $Config.network.routerAddress
    }

    $linkNamesInCsv = $Links | Group-Object -Property '链路' | Select-Object -ExpandProperty Name
    foreach ($putGet in $Config.putGetConnections) {
        if ($putGet.link -notin $linkNamesInCsv) {
            throw "putGetConnections 中的链路 $($putGet.link) 未出现在 PUT_GET最小集.csv"
        }
    }
}

function Get-LinkSummary {
    param([array]$Links)

    return $Links |
        Group-Object -Property '链路', '方向' |
        ForEach-Object {
            $first = $_.Group[0]
            [PSCustomObject]@{
                Link = $first.'链路'
                Direction = $first.'方向'
                FieldCount = $_.Count
                Categories = (($_.Group | Select-Object -ExpandProperty '类别' -Unique) -join ", ")
            }
        } |
        Sort-Object Link, Direction
}

function New-OperationPlan {
    param(
        $Config,
        [array]$Links,
        [string]$AssemblyPath,
        [string]$RepoRoot,
        [bool]$IsPlanOnly
    )

    $stationOps = foreach ($station in $Config.stations) {
        [PSCustomObject]@{
            StationId = $station.id
            DeviceName = $station.deviceName
            DeviceNameCandidates = @($station.deviceNameCandidates)
            InterfaceNameHint = $station.interfaceNameHint
            IpAddress = $station.ipAddress
            SubnetMask = $Config.network.subnetMask
            RouterAddress = $Config.network.routerAddress
            PnDeviceName = $station.pnDeviceName
            CreateIoSystem = [bool]$station.createIoSystem
        }
    }

    $connectionOps = foreach ($putGet in $Config.putGetConnections) {
        $rows = $Links | Where-Object { $_.'链路' -eq $putGet.link }
        [PSCustomObject]@{
            Link = $putGet.link
            ConnectionId = $putGet.connectionId
            LocalStation = $putGet.localStation
            RemoteStation = $putGet.remoteStation
            LocalShadowDb = $putGet.localShadowDb
            RemoteCommDb = $putGet.remoteCommDb
            FieldCount = $rows.Count
            Directions = (($rows | Select-Object -ExpandProperty '方向' -Unique) -join ", ")
        }
    }

    return [PSCustomObject]@{
        GeneratedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        RepoRoot = $RepoRoot
        PlanOnly = $IsPlanOnly
        TiaAssemblyDetected = [bool]$AssemblyPath
        TiaAssemblyPath = $AssemblyPath
        TemplateCloneEnabled = [bool]$Config.project.cloneTemplateBeforeOpen
        ProjectTemplatePath = $Config.project.templatePath
        ProjectTargetPath = $Config.project.targetPath
        Subnet = [PSCustomObject]@{
            Name = $Config.network.subnetName
            TypeIdentifier = $Config.network.subnetTypeIdentifier
            SubnetMask = $Config.network.subnetMask
            RouterAddress = $Config.network.routerAddress
        }
        ConnectionStrategy = $Config.connectionStrategy
        Stations = $stationOps
        PutGetConnections = $connectionOps
        LinkSummary = Get-LinkSummary -Links $Links
    }
}

function Save-OperationPlan {
    param(
        $Plan,
        [string]$OutputDir
    )

    Ensure-Directory -Path $OutputDir

    $jsonPath = Join-Path $OutputDir "automation-plan.json"
    $mdPath = Join-Path $OutputDir "automation-plan.md"

    $Plan | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $md = New-Object System.Collections.Generic.List[string]
    $md.Add("# 3358B 自动化执行计划")
    $md.Add("")
    $md.Add("- 生成时间: $($Plan.GeneratedAt)")
    $md.Add("- PlanOnly: $($Plan.PlanOnly)")
    $md.Add("- 检测到 TIA Openness: $($Plan.TiaAssemblyDetected)")
    $md.Add("- 子网: $($Plan.Subnet.Name)")
    $md.Add("- 模板工程: $($Plan.ProjectTemplatePath)")
    $md.Add("- 目标工程: $($Plan.ProjectTargetPath)")
    $md.Add("")
    $md.Add("## 站点网络")
    $md.Add("")
    $md.Add("| 站点 | 设备名 | IP | PN 名称 |")
    $md.Add("|---|---|---|---|")
    foreach ($station in $Plan.Stations) {
        $md.Add("| $($station.StationId) | $($station.DeviceName) | $($station.IpAddress) | $($station.PnDeviceName) |")
    }
    $md.Add("")
    $md.Add("## PUT/GET 链路")
    $md.Add("")
    $md.Add("| 链路 | 连接 ID | 本地站 | 远端站 | 字段数 |")
    $md.Add("|---|---|---|---|---|")
    foreach ($item in $Plan.PutGetConnections) {
        $md.Add("| $($item.Link) | $($item.ConnectionId) | $($item.LocalStation) | $($item.RemoteStation) | $($item.FieldCount) |")
    }
    $md.Add("")
    $md.Add("## 策略")
    $md.Add("")
    $md.Add("- 当前采用: $($Plan.ConnectionStrategy.mode)")
    $md.Add("- 说明: $($Plan.ConnectionStrategy.description)")

    Set-Content -LiteralPath $mdPath -Value $md -Encoding UTF8

    return [PSCustomObject]@{
        JsonPath = $jsonPath
        MarkdownPath = $mdPath
    }
}

function Copy-TemplateProject {
    param($Config)

    if (-not $Config.project.cloneTemplateBeforeOpen) {
        return
    }
    if ($SkipTemplateClone) {
        return
    }
    if (-not (Test-Path -LiteralPath $Config.project.templatePath)) {
        throw "模板工程不存在: $($Config.project.templatePath)"
    }

    $sourceProjectFile = (Resolve-Path $Config.project.templatePath).Path
    $sourceProjectDir = Split-Path -Parent $sourceProjectFile
    $sourceProjectFileName = Split-Path -Leaf $sourceProjectFile
    $targetProjectFile = $Config.project.targetPath
    $targetProjectDir = Split-Path -Parent $targetProjectFile
    $targetProjectFileName = Split-Path -Leaf $targetProjectFile

    if (-not $targetProjectDir) {
        throw "targetPath 必须包含目标目录: $targetProjectFile"
    }

    Ensure-Directory -Path $targetProjectDir

    Get-ChildItem -LiteralPath $targetProjectDir -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    Write-Step "克隆模板工程目录到目标路径"
    Get-ChildItem -LiteralPath $sourceProjectDir -Force |
        Copy-Item -Destination $targetProjectDir -Recurse -Force

    if ($sourceProjectFileName -ne $targetProjectFileName) {
        $copiedProjectFile = Join-Path $targetProjectDir $sourceProjectFileName
        if (-not (Test-Path -LiteralPath $copiedProjectFile)) {
            throw "复制后未找到目标工程文件: $copiedProjectFile"
        }
        Rename-Item -LiteralPath $copiedProjectFile -NewName $targetProjectFileName -Force
    }
}

function Add-TiaAssembly {
    param([string]$AssemblyPath)

    $assemblyDir = Split-Path -Parent $AssemblyPath
    $publicApiRoot = Split-Path -Parent $assemblyDir
    $portalRoot = Split-Path -Parent $publicApiRoot
    $binPublicApiDir = Join-Path $portalRoot "Bin\PublicAPI"

    $probeDirs = @($assemblyDir, $publicApiRoot, $binPublicApiDir) |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
        Select-Object -Unique

    foreach ($dir in $probeDirs) {
        if (($env:PATH -split ';') -notcontains $dir) {
            $env:PATH = "$dir;$env:PATH"
        }
    }

    foreach ($dependency in @(
        "Siemens.Engineering.Contract.dll",
        "Siemens.Engineering.ClientAdapter.Interfaces.dll"
    )) {
        foreach ($probeDir in $probeDirs) {
            $candidate = Join-Path $probeDir $dependency
            if (Test-Path -LiteralPath $candidate) {
                [System.Reflection.Assembly]::LoadFrom($candidate) | Out-Null
                break
            }
        }
    }

    Add-Type -LiteralPath $AssemblyPath
}

function Invoke-GenericMethod {
    param(
        [object]$Instance,
        [string]$MethodName,
        [Type[]]$GenericTypes,
        [object[]]$Arguments
    )

    $method = $Instance.GetType().GetMethods() |
        Where-Object { $_.Name -eq $MethodName -and $_.IsGenericMethodDefinition } |
        Select-Object -First 1

    if (-not $method) {
        throw "未找到泛型方法 $MethodName"
    }

    $concrete = $method.MakeGenericMethod($GenericTypes)
    return $concrete.Invoke($Instance, $Arguments)
}

function Set-OpennessAttribute {
    param(
        [object]$Target,
        [string]$Name,
        [object]$Value
    )

    if ($null -eq $Value -or $Value -eq "") {
        return
    }

    $method = $Target.GetType().GetMethod("SetAttribute", [Type[]]@([string], [object]))
    if (-not $method) {
        throw "对象 $($Target.GetType().FullName) 不支持 SetAttribute"
    }

    $method.Invoke($Target, @($Name, $Value)) | Out-Null
}

function Start-TiaPortalSession {
    param($Config, [string]$AssemblyPath)

    $modeValue = [System.Enum]::Parse([Siemens.Engineering.TiaPortalMode], [string]$Config.portalMode)
    return (New-Object Siemens.Engineering.TiaPortal($modeValue))
}

function Open-TiaProject {
    param(
        [object]$TiaPortal,
        [string]$ProjectPath
    )

    if (-not (Test-Path -LiteralPath $ProjectPath)) {
        throw "目标工程不存在: $ProjectPath"
    }

    $projectInfo = New-Object System.IO.FileInfo($ProjectPath)
    return $TiaPortal.Projects.Open($projectInfo)
}

function Get-DeviceRecursively {
    param([object]$Root)

    $items = New-Object System.Collections.Generic.List[object]
    $items.Add($Root)

    if ($Root.PSObject.Properties.Name -contains "DeviceItems") {
        foreach ($child in $Root.DeviceItems) {
            foreach ($nested in Get-DeviceRecursively -Root $child) {
                $items.Add($nested)
            }
        }
    }

    return $items
}

function Find-ProjectDevice {
    param(
        [object]$Project,
        $Station
    )

    foreach ($device in $Project.Devices) {
        if ($device.Name -eq $Station.deviceName) {
            return $device
        }
        foreach ($candidate in $Station.deviceNameCandidates) {
            if ($device.Name -eq $candidate) {
                return $device
            }
        }
    }

    throw "未在工程中找到站点 $($Station.id) 对应的设备: $($Station.deviceName)"
}

function Get-NetworkInterfaceService {
    param([object]$Device)

    foreach ($item in Get-DeviceRecursively -Root $Device) {
        try {
            $service = Invoke-GenericMethod -Instance $item -MethodName "GetService" -GenericTypes @([Siemens.Engineering.HW.Features.NetworkInterface]) -Arguments @()
            if ($service) {
                return $service
            }
        }
        catch {
        }
    }

    throw "设备 $($Device.Name) 未找到可用的 NetworkInterface"
}

function Find-OrCreate-Subnet {
    param(
        [object]$Project,
        $Config
    )

    foreach ($subnet in $Project.Subnets) {
        if ($subnet.Name -eq $Config.network.subnetName) {
            return $subnet
        }
    }

    $createMethod = $Project.Subnets.GetType().GetMethod("Create", [Type[]]@([string], [string]))
    if (-not $createMethod) {
        throw "Subnets.Create(string, string) 不可用，请在工程机上确认 TIA 版本"
    }

    return $createMethod.Invoke($Project.Subnets, @($Config.network.subnetTypeIdentifier, $Config.network.subnetName))
}

function Apply-StationNetworkConfig {
    param(
        [object]$Project,
        $Config,
        $Station
    )

    $device = Find-ProjectDevice -Project $Project -Station $Station
    $networkInterface = Get-NetworkInterfaceService -Device $device
    $subnet = Find-OrCreate-Subnet -Project $Project -Config $Config
    $node = $networkInterface.Nodes | Select-Object -First 1

    if (-not $node) {
        throw "设备 $($device.Name) 未找到网络节点"
    }

    try {
        $node.ConnectToSubnet($subnet)
    }
    catch {
        Write-Step "设备 $($device.Name) 可能已经在子网上，继续写地址"
    }

    Set-OpennessAttribute -Target $node -Name "Address" -Value $Station.ipAddress
    Set-OpennessAttribute -Target $node -Name "SubnetMask" -Value $Config.network.subnetMask

    try {
        Set-OpennessAttribute -Target $node -Name "PnDeviceNameSetDirectly" -Value $true
    }
    catch {
    }

    try {
        Set-OpennessAttribute -Target $node -Name "PnDeviceName" -Value $Station.pnDeviceName
    }
    catch {
        Write-Step ("跳过 PN 设备名写入: {0} -> {1}" -f $Station.id, $_.Exception.Message)
    }

    if ($Config.network.routerAddress) {
        Set-OpennessAttribute -Target $node -Name "RouterAddress" -Value $Config.network.routerAddress
    }
}

function Invoke-OnlineValidation {
    param(
        [object]$Project,
        $Config
    )

    if ($SkipOnlineValidation -or -not $Config.onlineValidation.enabled) {
        return
    }

    $station = $Config.stations | Where-Object { $_.id -eq $Config.onlineValidation.stationId } | Select-Object -First 1
    if (-not $station) {
        throw "onlineValidation.stationId 未匹配到任何站点"
    }

    $device = Find-ProjectDevice -Project $Project -Station $station
    Write-Step "检测到在线验证已开启，但当前脚本仅保留入口；请在工程机上补 PC 接口选择后执行 GoOnline"
    Write-Step "目标站点: $($device.Name)"
}

$repoRoot = Get-RepoRoot
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $repoRoot "07_工程自动化\配置\line-topology.json"
}
if (-not $LinksCsvPath) {
    $LinksCsvPath = Join-Path $repoRoot "03_通信点表\PUT_GET最小集.csv"
}

$outputDir = Join-Path $repoRoot "07_工程自动化\输出"
Ensure-Directory -Path $outputDir

Write-Step "读取配置文件"
$config = Read-JsonFile -Path $ConfigPath
Write-Step "读取通信 CSV"
$links = Import-LinkCsv -Path $LinksCsvPath
Write-Step "校验配置"
Test-AutomationConfig -Config $config -Links $links

$assemblyPath = Resolve-TiaAssemblyPath -Config $config
$plan = New-OperationPlan -Config $config -Links $links -AssemblyPath $assemblyPath -RepoRoot $repoRoot -IsPlanOnly ([bool]$PlanOnly)
$savedPlan = Save-OperationPlan -Plan $plan -OutputDir $outputDir
Write-Step "计划文件已输出: $($savedPlan.JsonPath)"
Write-Step "计划文件已输出: $($savedPlan.MarkdownPath)"

if ($PlanOnly) {
    Write-Step "PlanOnly 模式结束，不连接 TIA"
    return
}

if (-not $assemblyPath) {
    throw "未找到 Siemens.Engineering.dll。请在安装了 TIA Portal Openness 的工程机上运行，或在 line-topology.json 里显式指定 openness.assemblyPath。"
}

Copy-TemplateProject -Config $config

$tiaPortal = $null
$project = $null
try {
    Write-Step "加载 TIA Openness 程序集"
    Add-TiaAssembly -AssemblyPath $assemblyPath

    Write-Step "启动 TIA Portal"
    $tiaPortal = Start-TiaPortalSession -Config $config -AssemblyPath $assemblyPath

    Write-Step "打开目标工程"
    $project = Open-TiaProject -TiaPortal $tiaPortal -ProjectPath $config.project.targetPath

    foreach ($station in $config.stations) {
        Write-Step ("应用站点网络参数: {0}" -f $station.id)
        Apply-StationNetworkConfig -Project $project -Config $config -Station $station
    }

    Invoke-OnlineValidation -Project $project -Config $config

    Write-Step "保存工程"
    $project.Save()
    Write-Step "自动化执行完成"
}
finally {
    if ($project) {
        $project.Close()
    }
    if ($tiaPortal) {
        $tiaPortal.Dispose()
    }
}










