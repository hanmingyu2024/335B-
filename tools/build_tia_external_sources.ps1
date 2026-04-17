param(
    [string]$TemplateRoot = '',
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\artifacts\tia_v17\sources')
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

$stations = @(
    @{
        Key = 'Station01'
        SourcePattern = '01*'
        DeviceName = '3358B_Station01_Supply'
        DeviceItemName = 'PLC_01'
        TypeIdentifier = 'OrderNumber:6ES7 214-1BG40-0XB0/V4.5'
        HasLineControl = $true
    },
    @{
        Key = 'Station02'
        SourcePattern = '02*'
        DeviceName = '3358B_Station02_Process'
        DeviceItemName = 'PLC_02'
        TypeIdentifier = 'OrderNumber:6ES7 214-1BG40-0XB0/V4.5'
        HasLineControl = $false
    },
    @{
        Key = 'Station03'
        SourcePattern = '03*'
        DeviceName = '3358B_Station03_Transfer'
        DeviceItemName = 'PLC_03'
        TypeIdentifier = 'OrderNumber:6ES7 214-1AG40-0XB0/V4.5'
        HasLineControl = $false
    },
    @{
        Key = 'Station04'
        SourcePattern = '04*'
        DeviceName = '3358B_Station04_Assemble'
        DeviceItemName = 'PLC_04'
        TypeIdentifier = 'OrderNumber:6ES7 214-1BG40-0XB0/V4.5'
        HasLineControl = $false
    },
    @{
        Key = 'Station05'
        SourcePattern = '05*'
        DeviceName = '3358B_Station05_Sort'
        DeviceItemName = 'PLC_05'
        TypeIdentifier = 'OrderNumber:6ES7 214-1BG40-0XB0/V4.5'
        HasLineControl = $false
    }
)

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
    param([string]$Path)

    Assert-InsidePath -BasePath (Join-Path $PSScriptRoot '..\artifacts') -ChildPath $Path
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Read-SourceText {
    param([string]$Path)

    return [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path))
}

function Write-AsciiFile {
    param(
        [string]$Path,
        [string]$Content
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $normalized = $Content -replace "`r?`n", "`r`n"
    [System.IO.File]::WriteAllText($Path, $normalized, [System.Text.Encoding]::ASCII)
}

function Get-NetworkRoot {
    param([string]$Root)

    $match = @(Get-ChildItem -LiteralPath $Root -Directory | Where-Object { $_.Name -like '01_*' } | Sort-Object Name)
    if ($match.Count -eq 0) {
        throw "Could not find the device/network root under '$Root'."
    }
    return $match[0]
}

function Get-StationRoot {
    param(
        [string]$NetworkRoot,
        [string]$Pattern
    )

    $match = @(Get-ChildItem -LiteralPath $NetworkRoot -Directory | Where-Object { $_.Name -like $Pattern } | Sort-Object Name)
    if ($match.Count -eq 0) {
        throw "Could not resolve station folder for pattern '$Pattern'."
    }
    return $match[0]
}

function Get-UdtFolder {
    param([string]$StationRoot)

    $match = @(Get-ChildItem -LiteralPath $StationRoot -Directory | Where-Object {
        (Get-ChildItem -LiteralPath $_.FullName -File -Filter '*.udt' -ErrorAction SilentlyContinue).Count -gt 0
    } | Select-Object -First 1)

    if ($match.Count -eq 0) {
        throw "Could not resolve the UDT folder under '$StationRoot'."
    }

    return $match[0]
}

function Get-BlockContainer {
    param([string]$StationRoot)

    $match = @(Get-ChildItem -LiteralPath $StationRoot -Directory | Where-Object {
        (Get-ChildItem -LiteralPath $_.FullName -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '00*' }).Count -gt 0
    } | Select-Object -First 1)

    if ($match.Count -eq 0) {
        throw "Could not resolve the block folder under '$StationRoot'."
    }

    return $match[0]
}

function Wrap-OrganizationBlock {
    param(
        [string]$Name,
        [string]$Body
    )

    return @"
ORGANIZATION_BLOCK "$Name"
VERSION : 0.1
   VAR_TEMP
      Header : ARRAY[1..20] OF Byte;
   END_VAR
BEGIN
$Body
END_ORGANIZATION_BLOCK
"@
}

function Wrap-Function {
    param(
        [string]$Name,
        [string]$Body
    )

    return @"
FUNCTION "$Name" : Void
VERSION : 0.1
BEGIN
$Body
END_FUNCTION
"@
}

function Wrap-FunctionBlock {
    param(
        [string]$Name,
        [string]$Body,
        [string]$Interface
    )

    return @"
FUNCTION_BLOCK "$Name"
VERSION : 0.1
$Interface
BEGIN
$Body
END_FUNCTION_BLOCK
"@
}

function Get-InterfaceText {
    param([string]$BlockName)

    switch ($BlockName) {
        'FB_Cylinder' {
            return @"
   VAR_INPUT
      CmdExtend : Bool;
      FbExtend : Bool;
      FbRetract : Bool;
      tTimeout : Time;
   END_VAR
   VAR_OUTPUT
      OutValve : Bool;
      OkExtend : Bool;
      OkRetract : Bool;
      Fault : Bool;
   END_VAR
"@
        }
        'FB_Motor' {
            return @"
   VAR_INPUT
      CmdRun : Bool;
      FbRun : Bool;
      tStartTimeout : Time;
   END_VAR
   VAR_OUTPUT
      OutRun : Bool;
      Fault : Bool;
   END_VAR
"@
        }
        'FB_Conveyor' {
            return @"
   VAR_INPUT
      CmdRun : Bool;
      InPos : Bool;
      OutPos : Bool;
      tRunTimeout : Time;
   END_VAR
   VAR_OUTPUT
      OutRun : Bool;
      HasPart : Bool;
      TransferDone : Bool;
      Fault : Bool;
   END_VAR
"@
        }
        'FB_Sensor' {
            return @"
   VAR_INPUT
      RawIn : Bool;
      tOnDelay : Time;
      tOffDelay : Time;
   END_VAR
   VAR_OUTPUT
      Valid : Bool;
      Rising : Bool;
      Falling : Bool;
   END_VAR
   VAR_IN_OUT
      LastIn : Bool;
   END_VAR
"@
        }
        default {
            throw "No interface template defined for '$BlockName'."
        }
    }
}

function Rewrite-MainObBody {
    param([string]$Body)

    $body = $Body
    $body = [regex]::Replace($body, '(?m)^\s*"*DB_Line"*\(\);\s*$', '"FB_LineCtrl"();')
    $body = [regex]::Replace($body, '(?m)^\s*"*DB_Comm"*\(\);\s*$', '"FB_Comm"();')
    $body = [regex]::Replace($body, '(?m)^\s*"*DB_Station"*\(\);\s*$', '"FB_StationCtrl"();')
    $body = [regex]::Replace($body, '(?m)^\s*"*DB_Alarm"*\(\);\s*$', '"FB_Alarm"();')
    return $body
}

function Rewrite-DeviceBody {
    param(
        [string]$BlockName,
        [string]$Body
    )

    $body = $Body
    if ($BlockName -eq 'FB_Sensor') {
        $body = $body.Replace('#InSig', '#RawIn')
        $body = $body.Replace('#DelayOn', '#tOnDelay')
        $body = $body.Replace('#DelayOff', '#tOffDelay')
    }
    return $body
}

function New-SourceRecord {
    param(
        [hashtable]$Station,
        [int]$Order,
        [string]$Category,
        [string]$RelativePath
    )

    return [ordered]@{
        StationKey = $Station.Key
        Order = $Order
        Category = $Category
        RelativePath = $RelativePath
        FileName = [System.IO.Path]::GetFileName($RelativePath)
    }
}

$artifactsRoot = Join-Path $PSScriptRoot '..\artifacts'
if (-not (Test-Path -LiteralPath $artifactsRoot)) {
    New-Item -ItemType Directory -Path $artifactsRoot -Force | Out-Null
}

if ([string]::IsNullOrWhiteSpace($TemplateRoot)) {
    $TemplateRoot = Get-DefaultTemplateRoot
}

$TemplateRoot = [System.IO.Path]::GetFullPath($TemplateRoot)
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)

Reset-Directory -Path $OutputRoot

$manifestStations = @()
$manifestSources = @()
$networkRoot = Get-NetworkRoot -Root $TemplateRoot

foreach ($station in $stations) {
    $stationRoot = Get-StationRoot -NetworkRoot $networkRoot.FullName -Pattern $station.SourcePattern
    $udtFolder = Get-UdtFolder -StationRoot $stationRoot.FullName
    $blockContainer = Get-BlockContainer -StationRoot $stationRoot.FullName

    $outputStationRoot = Join-Path $OutputRoot $station.Key
    New-Item -ItemType Directory -Path $outputStationRoot -Force | Out-Null

    $manifestStations += [ordered]@{
        StationKey = $station.Key
        SourceFolder = $stationRoot.Name
        DeviceName = $station.DeviceName
        DeviceItemName = $station.DeviceItemName
        TypeIdentifier = $station.TypeIdentifier
        HasLineControl = $station.HasLineControl
    }

    $order = 10

    foreach ($file in (Get-ChildItem -LiteralPath $udtFolder.FullName -File | Sort-Object Name)) {
        $relative = Join-Path 'Types' $file.Name
        Write-AsciiFile -Path (Join-Path $outputStationRoot $relative) -Content (Read-SourceText -Path $file.FullName)
        $manifestSources += New-SourceRecord -Station $station -Order $order -Category 'Type' -RelativePath $relative
        $order += 10
    }

    $dbPatterns = @('20*', '30*', '40*', '50*', '60*', '70*')
    $dbDirectories = Get-ChildItem -LiteralPath $blockContainer.FullName -Directory | Where-Object {
        $name = $_.Name
        ($dbPatterns | Where-Object { $name -like $_ }).Count -gt 0
    } | Sort-Object Name

    foreach ($dbDir in $dbDirectories) {
        foreach ($file in (Get-ChildItem -LiteralPath $dbDir.FullName -File -Filter '*.db' | Sort-Object Name)) {
            $relative = Join-Path 'DB' $file.Name
            Write-AsciiFile -Path (Join-Path $outputStationRoot $relative) -Content (Read-SourceText -Path $file.FullName)
            $manifestSources += New-SourceRecord -Station $station -Order $order -Category 'DB' -RelativePath $relative
            $order += 10
        }
    }

    foreach ($file in (Get-ChildItem -LiteralPath $blockContainer.FullName -Recurse -File -Filter '*.scl' | Sort-Object FullName)) {
        $body = (Read-SourceText -Path $file.FullName).Trim()
        $name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $relativeDir = Split-Path -Parent ($file.FullName.Substring($blockContainer.FullName.Length).TrimStart('\'))
        $blockGroup = if ([string]::IsNullOrWhiteSpace($relativeDir)) { '' } else { $relativeDir }
        $relative = if ([string]::IsNullOrWhiteSpace($blockGroup)) {
            Join-Path 'Blocks' $file.Name
        } else {
            Join-Path (Join-Path 'Blocks' $blockGroup) $file.Name
        }

        switch ($name) {
            'Main_OB1' { $wrapped = Wrap-OrganizationBlock -Name 'Main' -Body (Rewrite-MainObBody -Body $body) }
            'Startup_OB100' { $wrapped = Wrap-OrganizationBlock -Name 'Startup' -Body $body }
            'FB_Cylinder' { $wrapped = Wrap-FunctionBlock -Name $name -Body (Rewrite-DeviceBody -BlockName $name -Body $body) -Interface (Get-InterfaceText -BlockName $name) }
            'FB_Motor' { $wrapped = Wrap-FunctionBlock -Name $name -Body (Rewrite-DeviceBody -BlockName $name -Body $body) -Interface (Get-InterfaceText -BlockName $name) }
            'FB_Conveyor' { $wrapped = Wrap-FunctionBlock -Name $name -Body (Rewrite-DeviceBody -BlockName $name -Body $body) -Interface (Get-InterfaceText -BlockName $name) }
            'FB_Sensor' { $wrapped = Wrap-FunctionBlock -Name $name -Body (Rewrite-DeviceBody -BlockName $name -Body $body) -Interface (Get-InterfaceText -BlockName $name) }
            'FB_StationCtrl' { $wrapped = Wrap-Function -Name $name -Body $body }
            'FB_Comm' { $wrapped = Wrap-Function -Name $name -Body $body }
            'FB_Alarm' { $wrapped = Wrap-Function -Name $name -Body $body }
            'FB_LineCtrl' { $wrapped = Wrap-Function -Name $name -Body $body }
            default { $wrapped = Wrap-Function -Name $name -Body $body }
        }

        Write-AsciiFile -Path (Join-Path $outputStationRoot $relative) -Content $wrapped
        $manifestSources += New-SourceRecord -Station $station -Order $order -Category 'Block' -RelativePath $relative
        $order += 10
    }
}

$manifest = [ordered]@{
    GeneratedAt = (Get-Date).ToString('s')
    TemplateRoot = [System.IO.Path]::GetFullPath($TemplateRoot)
    OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
    Stations = $manifestStations
    Sources = $manifestSources
}

$manifestPath = Join-Path $OutputRoot 'manifest.json'
($manifest | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host "Generated external sources under: $OutputRoot"
Write-Host "Manifest: $manifestPath"
