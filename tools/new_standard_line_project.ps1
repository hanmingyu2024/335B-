param(
    [string]$ManifestPath = (Join-Path $PSScriptRoot '..\standard_line_template\line_manifest.sample.json'),
    [string]$SchemaPath = (Join-Path $PSScriptRoot '..\standard_line_template\line_manifest.schema.json'),
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\artifacts\standard_line_workspace'),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
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

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Write-Utf8File {
    param(
        [string]$Path,
        [string]$Content
    )

    $dir = Split-Path -Parent $Path
    Ensure-Directory -Path $dir
    $normalized = $Content -replace "`r?`n", "`r`n"
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $normalized, $utf8)
}

function New-SourceRecord {
    param(
        [string]$StationKey,
        [int]$Order,
        [string]$Category,
        [string]$RelativePath
    )

    return [ordered]@{
        StationKey = $StationKey
        Order = $Order
        Category = $Category
        RelativePath = $RelativePath
        FileName = [System.IO.Path]::GetFileName($RelativePath)
    }
}

function Get-StationStatusDbContent {
    return @'
DATA_BLOCK "DB_Station"
{ S7_Optimized_Access := 'TRUE' }
VERSION : 0.1
NON_RETAIN
   VAR
      ModeAuto : Bool := FALSE;
      RunCmd : Bool := FALSE;
      FaultActive : Bool := FALSE;
      CycleActive : Bool := FALSE;
      StationReady : Bool := FALSE;
      StationBusy : Bool := FALSE;
      StationDone : Bool := FALSE;
      Step : Int := 0;
      AlarmCode : Word := W#16#0000;
      LightGreen : Bool := FALSE;
      LightYellow : Bool := FALSE;
      LightRed : Bool := FALSE;
   END_VAR
BEGIN
END_DATA_BLOCK
'@
}

function Get-CommDbContent {
    return @'
DATA_BLOCK "DB_Comm"
{ S7_Optimized_Access := 'TRUE' }
VERSION : 0.1
NON_RETAIN
   VAR
      CmdAuto : Bool := FALSE;
      CmdStart : Bool := FALSE;
      CmdStop : Bool := FALSE;
      CmdReset : Bool := FALSE;
      HeartbeatTx : Bool := FALSE;
      HeartbeatRx : Bool := FALSE;
      StsReady : Bool := FALSE;
      StsBusy : Bool := FALSE;
      StsDone : Bool := FALSE;
      StsFault : Bool := FALSE;
      StepNo : Int := 0;
      ReqOut : Bool := FALSE;
      PartReady : Bool := FALSE;
      AllowTake : Bool := FALSE;
      TakeDone : Bool := FALSE;
      ReqIn : Bool := FALSE;
      AllowIn : Bool := FALSE;
      PlaceDone : Bool := FALSE;
      PartReceived : Bool := FALSE;
      ProcessDone : Bool := FALSE;
      DoneAck : Bool := FALSE;
      TransferJob : Bool := FALSE;
      ReadyForJob : Bool := FALSE;
      JobBusy : Bool := FALSE;
      JobDone : Bool := FALSE;
      JobAbort : Bool := FALSE;
      JobSource : Int := 0;
      JobTarget : Int := 0;
      PickAtLeft : Bool := FALSE;
      PlaceAtLeft : Bool := FALSE;
      PlaceRotateLeft : Bool := FALSE;
   END_VAR
BEGIN
END_DATA_BLOCK
'@
}

function Get-AlarmDbContent {
    return @'
DATA_BLOCK "DB_Alarm"
{ S7_Optimized_Access := 'TRUE' }
VERSION : 0.1
NON_RETAIN
   VAR
      Current : "UDT_AlarmItem";
   END_VAR
BEGIN
END_DATA_BLOCK
'@
}

function Get-ParmDbContent {
    return @'
DATA_BLOCK "DB_Parm"
{ S7_Optimized_Access := 'TRUE' }
VERSION : 0.1
NON_RETAIN
   VAR
      AutoStepTimeout : Time := T#5S;
      ManualJogTime : Time := T#500MS;
   END_VAR
BEGIN
END_DATA_BLOCK
'@
}

function Get-LineDbContent {
    return @'
DATA_BLOCK "DB_Line"
{ S7_Optimized_Access := 'TRUE' }
VERSION : 0.1
NON_RETAIN
   VAR
      CurrentStep : Int := 0;
      LineReady : Bool := FALSE;
      LineFault : Bool := FALSE;
      CurrentJobSource : Int := 0;
      CurrentJobTarget : Int := 0;
   END_VAR
BEGIN
END_DATA_BLOCK
'@
}

function Get-UdtAlarmItemContent {
    return @'
TYPE "UDT_AlarmItem"
VERSION : 0.1
   STRUCT
      Code : Word;
      Active : Bool;
      Acked : Bool;
   END_STRUCT;
END_TYPE
'@
}

function Get-UdtCommCmdContent {
    return @'
TYPE "UDT_CommCmd"
VERSION : 0.1
   STRUCT
      CmdAuto : Bool;
      CmdStart : Bool;
      CmdStop : Bool;
      CmdReset : Bool;
   END_STRUCT;
END_TYPE
'@
}

function Get-UdtCommStsContent {
    return @'
TYPE "UDT_CommSts"
VERSION : 0.1
   STRUCT
      StsReady : Bool;
      StsBusy : Bool;
      StsDone : Bool;
      StsFault : Bool;
      StepNo : Int;
   END_STRUCT;
END_TYPE
'@
}

function Get-UdtParmContent {
    return @'
TYPE "UDT_Parm"
VERSION : 0.1
   STRUCT
      AutoStepTimeout : Time;
      ManualJogTime : Time;
   END_STRUCT;
END_TYPE
'@
}

function Get-UdtStationStateContent {
    return @'
TYPE "UDT_StationState"
VERSION : 0.1
   STRUCT
      ModeAuto : Bool;
      RunCmd : Bool;
      FaultActive : Bool;
      CycleActive : Bool;
      StationReady : Bool;
      StationBusy : Bool;
      StationDone : Bool;
      Step : Int;
      AlarmCode : Word;
      LightGreen : Bool;
      LightYellow : Bool;
      LightRed : Bool;
   END_STRUCT;
END_TYPE
'@
}

function Get-UdtLineStateContent {
    return @'
TYPE "UDT_LineState"
VERSION : 0.1
   STRUCT
      CurrentStep : Int;
      LineReady : Bool;
      LineFault : Bool;
      CurrentJobSource : Int;
      CurrentJobTarget : Int;
   END_STRUCT;
END_TYPE
'@
}

function Get-MainObContent {
    param([bool]$HasLineControl)

    $bodyLines = @(
        '   "FC_IMap"();'
    )
    if ($HasLineControl) {
        $bodyLines += '   "FB_LineCtrl"();'
    }
    $bodyLines += @(
        '   "FB_Comm"();'
        '   "FB_StationCtrl"();'
        '   "FB_Alarm"();'
        '   "FC_QMap"();'
    )

    return "ORGANIZATION_BLOCK `"Main`"`r`nVERSION : 0.1`r`n   VAR_TEMP`r`n      Header : ARRAY[1..20] OF Byte;`r`n   END_VAR`r`nBEGIN`r`n" +
        (($bodyLines -join "`r`n") + "`r`n") +
        "END_ORGANIZATION_BLOCK`r`n"
}

function Get-StartupObContent {
    return @'
ORGANIZATION_BLOCK "Startup"
VERSION : 0.1
   VAR_TEMP
      Header : ARRAY[1..20] OF Byte;
   END_VAR
BEGIN
   "DB_Station".ModeAuto := FALSE;
   "DB_Station".RunCmd := FALSE;
   "DB_Station".FaultActive := FALSE;
   "DB_Station".CycleActive := FALSE;
   "DB_Station".StationDone := FALSE;
   "DB_Station".Step := 0;
END_ORGANIZATION_BLOCK
'@
}

function Get-IMapContent {
    return @'
FUNCTION "FC_IMap" : Void
VERSION : 0.1
BEGIN
   // Map physical inputs to DB_Station here.
END_FUNCTION
'@
}

function Get-QMapContent {
    return @'
FUNCTION "FC_QMap" : Void
VERSION : 0.1
BEGIN
   // Map DB_Station outputs to physical outputs here.
END_FUNCTION
'@
}

function Get-ModeCtrlContent {
    return @'
FUNCTION "FC_ModeCtrl" : Void
VERSION : 0.1
BEGIN
   "DB_Station".ModeAuto := "DB_Comm".CmdAuto;

   IF "DB_Comm".CmdStop THEN
      "DB_Station".RunCmd := FALSE;
   END_IF;

   IF "DB_Comm".CmdStart AND "DB_Station".ModeAuto AND NOT "DB_Station".FaultActive THEN
      "DB_Station".RunCmd := TRUE;
   END_IF;
END_FUNCTION
'@
}

function Get-ResetContent {
    return @'
FUNCTION "FC_Reset" : Void
VERSION : 0.1
BEGIN
   IF "DB_Comm".CmdReset THEN
      "DB_Station".FaultActive := FALSE;
      "DB_Station".CycleActive := FALSE;
      "DB_Station".StationDone := FALSE;
      "DB_Station".AlarmCode := W#16#0000;
      "DB_Station".Step := 0;
   END_IF;
END_FUNCTION
'@
}

function Get-ManualCtrlContent {
    return @'
FUNCTION "FC_ManualCtrl" : Void
VERSION : 0.1
BEGIN
   "DB_Station".CycleActive := FALSE;
END_FUNCTION
'@
}

function Get-AutoSeqContent {
    return @'
FUNCTION "FC_AutoSeq" : Void
VERSION : 0.1
BEGIN
   IF NOT "DB_Station".RunCmd THEN
      "DB_Station".CycleActive := FALSE;
      RETURN;
   END_IF;

   CASE "DB_Station".Step OF
      0:
         "DB_Station".CycleActive := FALSE;
         "DB_Station".StationDone := FALSE;
         "DB_Station".Step := 10;
      10:
         "DB_Station".CycleActive := TRUE;
         "DB_Station".StationDone := TRUE;
         "DB_Station".Step := 20;
      20:
         IF NOT "DB_Comm".CmdStart THEN
            "DB_Station".CycleActive := FALSE;
            "DB_Station".StationDone := FALSE;
            "DB_Station".Step := 0;
         END_IF;
   ELSE
      "DB_Station".Step := 0;
   END_CASE;
END_FUNCTION
'@
}

function Get-LightsContent {
    return @'
FUNCTION "FC_Lights" : Void
VERSION : 0.1
BEGIN
   "DB_Station".LightRed := "DB_Station".FaultActive;
   "DB_Station".LightYellow := "DB_Station".CycleActive;
   "DB_Station".LightGreen := "DB_Station".StationReady AND NOT "DB_Station".FaultActive;
END_FUNCTION
'@
}

function Get-StationCtrlContent {
    return @'
FUNCTION "FB_StationCtrl" : Void
VERSION : 0.1
BEGIN
   "FC_ModeCtrl"();
   "FC_Reset"();

   IF "DB_Station".ModeAuto THEN
      "FC_AutoSeq"();
   ELSE
      "FC_ManualCtrl"();
   END_IF;

   "FC_Lights"();

   "DB_Station".StationReady := NOT "DB_Station".FaultActive;
   "DB_Station".StationBusy := "DB_Station".CycleActive;
END_FUNCTION
'@
}

function Get-CommContent {
    return @'
FUNCTION "FB_Comm" : Void
VERSION : 0.1
BEGIN
   "DB_Comm".StsReady := "DB_Station".StationReady;
   "DB_Comm".StsBusy := "DB_Station".StationBusy;
   "DB_Comm".StsDone := "DB_Station".StationDone;
   "DB_Comm".StsFault := "DB_Station".FaultActive;
   "DB_Comm".StepNo := "DB_Station".Step;
END_FUNCTION
'@
}

function Get-AlarmContent {
    return @'
FUNCTION "FB_Alarm" : Void
VERSION : 0.1
BEGIN
   "DB_Alarm".Current.Code := "DB_Station".AlarmCode;
   "DB_Alarm".Current.Active := "DB_Station".FaultActive;
END_FUNCTION
'@
}

function Get-LineCtrlContent {
    return @'
FUNCTION "FB_LineCtrl" : Void
VERSION : 0.1
BEGIN
   "DB_Line".CurrentStep := "DB_Station".Step;
   "DB_Line".LineReady := "DB_Station".StationReady;
   "DB_Line".LineFault := "DB_Station".FaultActive;
END_FUNCTION
'@
}

function Get-CylinderContent {
    return @'
FUNCTION_BLOCK "FB_Cylinder"
VERSION : 0.1
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
BEGIN
   OutValve := CmdExtend;
   OkExtend := CmdExtend AND FbExtend;
   OkRetract := (NOT CmdExtend) AND FbRetract;
   Fault := FALSE;
END_FUNCTION_BLOCK
'@
}

function Get-MotorContent {
    return @'
FUNCTION_BLOCK "FB_Motor"
VERSION : 0.1
   VAR_INPUT
      CmdRun : Bool;
      FbRun : Bool;
      tStartTimeout : Time;
   END_VAR
   VAR_OUTPUT
      OutRun : Bool;
      Fault : Bool;
   END_VAR
BEGIN
   OutRun := CmdRun;
   Fault := FALSE;
END_FUNCTION_BLOCK
'@
}

function Get-ConveyorContent {
    return @'
FUNCTION_BLOCK "FB_Conveyor"
VERSION : 0.1
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
BEGIN
   OutRun := CmdRun;
   HasPart := InPos OR OutPos;
   TransferDone := OutPos;
   Fault := FALSE;
END_FUNCTION_BLOCK
'@
}

function Get-SensorContent {
    return @'
FUNCTION_BLOCK "FB_Sensor"
VERSION : 0.1
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
BEGIN
   Rising := RawIn AND NOT LastIn;
   Falling := (NOT RawIn) AND LastIn;
   Valid := RawIn;
   LastIn := RawIn;
END_FUNCTION_BLOCK
'@
}

function Test-IsIntegerValue {
    param([object]$Value)

    return (
        ($Value -is [byte]) -or
        ($Value -is [int16]) -or
        ($Value -is [int32]) -or
        ($Value -is [int64]) -or
        ($Value -is [uint16]) -or
        ($Value -is [uint32]) -or
        ($Value -is [uint64])
    )
}

function Test-IsJsonArray {
    param([object]$Value)

    if ($null -eq $Value) {
        return $false
    }
    if ($Value -is [string]) {
        return $false
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        return $false
    }
    return ($Value -is [System.Collections.IEnumerable])
}

function Test-IsJsonObject {
    param([object]$Value)

    if ($null -eq $Value) {
        return $false
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        return $true
    }
    return $false
}

function Test-ManifestAgainstSchema {
    param(
        [object]$Node,
        [object]$Schema,
        [string]$Path = '$'
    )

    $schemaType = ''
    if ($null -ne $Schema.PSObject.Properties['type']) {
        $schemaType = [string]$Schema.type
    }
    if ($null -ne $Schema.PSObject.Properties['enum']) {
        $allowedValues = @($Schema.enum)
        if ($allowedValues -notcontains $Node) {
            throw "Schema validation failed at '$Path': value '$Node' is not in enum set [$($allowedValues -join ', ')]."
        }
    }

    switch ($schemaType) {
        'object' {
            if (-not (Test-IsJsonObject -Value $Node)) {
                throw "Schema validation failed at '$Path': expected object."
            }

            $required = @()
            if ($null -ne $Schema.PSObject.Properties['required']) {
                $required = @($Schema.required)
            }

            foreach ($requiredName in $required) {
                if ($null -eq $Node.PSObject.Properties[[string]$requiredName]) {
                    throw "Schema validation failed at '$Path': missing required property '$requiredName'."
                }
            }

            $schemaProperties = @{}
            if ($null -ne $Schema.PSObject.Properties['properties']) {
                foreach ($property in $Schema.properties.PSObject.Properties) {
                    $schemaProperties[[string]$property.Name] = $property.Value
                }
            }

            $allowAdditional = $true
            if ($null -ne $Schema.PSObject.Properties['additionalProperties']) {
                $allowAdditional = [bool]$Schema.additionalProperties
            }

            foreach ($property in $Node.PSObject.Properties) {
                $propertyName = [string]$property.Name
                if (-not $schemaProperties.ContainsKey($propertyName)) {
                    if (-not $allowAdditional) {
                        throw "Schema validation failed at '$Path': unexpected property '$propertyName'."
                    }
                    continue
                }

                Test-ManifestAgainstSchema -Node $property.Value -Schema $schemaProperties[$propertyName] -Path ($Path + '.' + $propertyName)
            }
        }
        'array' {
            if (-not (Test-IsJsonArray -Value $Node)) {
                throw "Schema validation failed at '$Path': expected array."
            }

            $items = @($Node)
            if ($null -ne $Schema.PSObject.Properties['minItems']) {
                $minItems = [int]$Schema.minItems
                if ($items.Count -lt $minItems) {
                    throw "Schema validation failed at '$Path': expected at least $minItems item(s), got $($items.Count)."
                }
            }

            if ($null -ne $Schema.PSObject.Properties['maxItems']) {
                $maxItems = [int]$Schema.maxItems
                if ($items.Count -gt $maxItems) {
                    throw "Schema validation failed at '$Path': expected at most $maxItems item(s), got $($items.Count)."
                }
            }

            if ($null -ne $Schema.PSObject.Properties['items']) {
                for ($index = 0; $index -lt $items.Count; $index++) {
                    Test-ManifestAgainstSchema -Node $items[$index] -Schema $Schema.items -Path ($Path + '[' + $index + ']')
                }
            }
        }
        'string' {
            if (-not ($Node -is [string])) {
                throw "Schema validation failed at '$Path': expected string."
            }

            $text = [string]$Node
            if ($null -ne $Schema.PSObject.Properties['minLength']) {
                $minLength = [int]$Schema.minLength
                if ($text.Length -lt $minLength) {
                    throw "Schema validation failed at '$Path': expected length >= $minLength."
                }
            }
            if ($null -ne $Schema.PSObject.Properties['maxLength']) {
                $maxLength = [int]$Schema.maxLength
                if ($text.Length -gt $maxLength) {
                    throw "Schema validation failed at '$Path': expected length <= $maxLength."
                }
            }
            if ($null -ne $Schema.PSObject.Properties['pattern']) {
                $pattern = [string]$Schema.pattern
                if (-not [System.Text.RegularExpressions.Regex]::IsMatch($text, $pattern)) {
                    throw "Schema validation failed at '$Path': '$text' does not match pattern '$pattern'."
                }
            }
        }
        'integer' {
            if (-not (Test-IsIntegerValue -Value $Node)) {
                throw "Schema validation failed at '$Path': expected integer."
            }

            $number = [int64]$Node
            if ($null -ne $Schema.PSObject.Properties['minimum']) {
                $minimum = [int64]$Schema.minimum
                if ($number -lt $minimum) {
                    throw "Schema validation failed at '$Path': expected value >= $minimum."
                }
            }
            if ($null -ne $Schema.PSObject.Properties['maximum']) {
                $maximum = [int64]$Schema.maximum
                if ($number -gt $maximum) {
                    throw "Schema validation failed at '$Path': expected value <= $maximum."
                }
            }
        }
        'boolean' {
            if (-not ($Node -is [bool])) {
                throw "Schema validation failed at '$Path': expected boolean."
            }
        }
    }
}

function Validate-ManifestSemantics {
    param([object]$Manifest)

    $stations = @($Manifest.stations)
    if ($stations.Count -eq 0) {
        throw 'Manifest semantic validation failed: stations cannot be empty.'
    }

    function Test-Ipv4Address {
        param([string]$Value)

        if ([string]::IsNullOrWhiteSpace($Value)) {
            return $false
        }

        $parsed = $null
        return (
            [System.Net.IPAddress]::TryParse($Value, [ref]$parsed) -and
            $parsed.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork
        )
    }

    $projectNetwork = $Manifest.network
    if ([bool]$projectNetwork.useRouter -and [string]::IsNullOrWhiteSpace([string]$projectNetwork.routerAddress)) {
        throw 'Manifest semantic validation failed: network.useRouter=true requires network.routerAddress.'
    }
    if ((-not [string]::IsNullOrWhiteSpace([string]$projectNetwork.routerAddress)) -and (-not (Test-Ipv4Address -Value ([string]$projectNetwork.routerAddress)))) {
        throw "Manifest semantic validation failed: network.routerAddress '$($projectNetwork.routerAddress)' is not a valid IPv4 address."
    }
    if (-not ([string]$projectNetwork.subnetTypeIdentifier).StartsWith('System:Subnet.')) {
        throw "Manifest semantic validation failed: network.subnetTypeIdentifier '$($projectNetwork.subnetTypeIdentifier)' must start with 'System:Subnet.'."
    }

    $stationKeys = @{}
    $stationNumbers = @{}
    $deviceNames = @{}
    $deviceItemNames = @{}
    $folderNames = @{}
    $stationIpAddresses = @{}
    $pnDeviceNames = @{}
    foreach ($station in $stations) {
        $stationKey = [string]$station.key
        $stationNumber = [int]$station.stationNumber
        $deviceName = [string]$station.deviceName
        $deviceItemName = [string]$station.deviceItemName
        $folderName = [string]$station.folderName
        $ipAddress = [string]$station.network.ipAddress
        $pnDeviceName = [string]$station.network.pnDeviceName

        if ($stationKeys.ContainsKey($stationKey)) {
            throw "Manifest semantic validation failed: duplicated station key '$stationKey'."
        }
        if ($stationNumbers.ContainsKey($stationNumber)) {
            throw "Manifest semantic validation failed: duplicated station number '$stationNumber'."
        }
        if ($deviceNames.ContainsKey($deviceName)) {
            throw "Manifest semantic validation failed: duplicated deviceName '$deviceName'."
        }
        if ($deviceItemNames.ContainsKey($deviceItemName)) {
            throw "Manifest semantic validation failed: duplicated deviceItemName '$deviceItemName'."
        }
        if ($folderNames.ContainsKey($folderName)) {
            throw "Manifest semantic validation failed: duplicated folderName '$folderName'."
        }
        if ($stationIpAddresses.ContainsKey($ipAddress)) {
            throw "Manifest semantic validation failed: duplicated station network.ipAddress '$ipAddress'."
        }
        if ($pnDeviceNames.ContainsKey($pnDeviceName)) {
            throw "Manifest semantic validation failed: duplicated station network.pnDeviceName '$pnDeviceName'."
        }
        if (-not (Test-Ipv4Address -Value $ipAddress)) {
            throw "Manifest semantic validation failed: station '$stationKey' network.ipAddress '$ipAddress' is not a valid IPv4 address."
        }

        $stationKeys[$stationKey] = $true
        $stationNumbers[$stationNumber] = $true
        $deviceNames[$deviceName] = $true
        $deviceItemNames[$deviceItemName] = $true
        $folderNames[$folderName] = $true
        $stationIpAddresses[$ipAddress] = $true
        $pnDeviceNames[$pnDeviceName] = $true
    }

    $lineControlStation = [string]$Manifest.project.lineControlStation
    if (-not $stationKeys.ContainsKey($lineControlStation)) {
        throw "Manifest semantic validation failed: project.lineControlStation '$lineControlStation' not found in stations."
    }

    $lineControlStations = @($stations | Where-Object { [bool]$_.hasLineControl })
    if ($lineControlStations.Count -ne 1) {
        throw "Manifest semantic validation failed: exactly one station must have hasLineControl=true, found $($lineControlStations.Count)."
    }
    if ([string]$lineControlStations[0].key -ne $lineControlStation) {
        throw "Manifest semantic validation failed: lineControlStation '$lineControlStation' does not match station marked hasLineControl."
    }

    $stageIds = @{}
    foreach ($stage in @($Manifest.projectStages)) {
        $stageId = [int]$stage.id
        if ($stageIds.ContainsKey($stageId)) {
            throw "Manifest semantic validation failed: duplicated project stage id '$stageId'."
        }
        $stageIds[$stageId] = $true
    }

    foreach ($link in @($Manifest.processFlow)) {
        $fromStation = [string]$link.from
        $toStation = [string]$link.to
        if (-not $stationKeys.ContainsKey($fromStation)) {
            throw "Manifest semantic validation failed: processFlow.from '$fromStation' not found in stations."
        }
        if (-not $stationKeys.ContainsKey($toStation)) {
            throw "Manifest semantic validation failed: processFlow.to '$toStation' not found in stations."
        }
    }

    $signalNames = @{}
    foreach ($signal in @($Manifest.commSignals)) {
        $signalName = [string]$signal.name
        if ($signalNames.ContainsKey($signalName)) {
            throw "Manifest semantic validation failed: duplicated commSignals.name '$signalName'."
        }
        $signalNames[$signalName] = $true
    }

    foreach ($band in @($Manifest.alarmBands)) {
        $bandStation = [string]$band.station
        if (($bandStation -ne 'LineCommon') -and (-not $stationKeys.ContainsKey($bandStation))) {
            throw "Manifest semantic validation failed: alarmBands.station '$bandStation' must be existing station key or 'LineCommon'."
        }

        if ([int]$band.end -lt [int]$band.start) {
            throw "Manifest semantic validation failed: alarm band '$bandStation' has end < start."
        }
    }
}

function Get-DefaultWarningPolicyContent {
    return @'
{
  "version": "1.0",
  "defaultWarningAction": "allow",
  "rules": [
    {
      "id": "hardware_address_out_of_range",
      "enabled": true,
      "action": "block",
      "description": "Block compile warning when I/O address is outside configured hardware."
    },
    {
      "id": "generic_warning",
      "enabled": true,
      "action": "allow",
      "description": "Allow warning by default but keep it in warning reports."
    }
  ]
}
'@
}

$repoRoot = Get-RepoRoot
$ManifestPath = [System.IO.Path]::GetFullPath($ManifestPath)
$SchemaPath = [System.IO.Path]::GetFullPath($SchemaPath)
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)

Assert-InsidePath -BasePath $repoRoot -ChildPath $ManifestPath
Assert-InsidePath -BasePath $repoRoot -ChildPath $SchemaPath
Assert-InsidePath -BasePath $repoRoot -ChildPath $OutputRoot

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "Manifest not found at '$ManifestPath'."
}
if (-not (Test-Path -LiteralPath $SchemaPath)) {
    throw "Schema not found at '$SchemaPath'."
}

if ((Test-Path -LiteralPath $OutputRoot) -and (-not $Force)) {
    throw "Output path already exists. Re-run with -Force to overwrite: '$OutputRoot'"
}

Reset-Directory -BasePath $repoRoot -Path $OutputRoot

$manifestText = [System.IO.File]::ReadAllText($ManifestPath, [System.Text.Encoding]::UTF8)
$schemaText = [System.IO.File]::ReadAllText($SchemaPath, [System.Text.Encoding]::UTF8)
$manifest = $manifestText | ConvertFrom-Json
$schema = $schemaText | ConvertFrom-Json

Test-ManifestAgainstSchema -Node $manifest -Schema $schema
Validate-ManifestSemantics -Manifest $manifest

if ($manifest.stations.Count -eq 0) {
    throw 'Manifest must define at least one station.'
}

$workspaceDirs = @(
    '00_ProjectInfo',
    '01_DevicesAndNetwork',
    '02_HMI',
    '03_CommTable',
    '04_IOList',
    '05_AlarmList',
    '06_Naming',
    'config',
    'tia_sources'
)

foreach ($dir in $workspaceDirs) {
    Ensure-Directory -Path (Join-Path $OutputRoot $dir)
}

$stationLines = @()
$stationNetworkLines = @()
foreach ($station in $manifest.stations) {
    $lineControlText = if ($station.hasLineControl) { 'Line control' } else { 'Standard station' }
    $stationLines += ('- {0} | {1} | {2} | DI {3} / DO {4} | {5}' -f $station.key, $station.displayName, $station.cpuTypeIdentifier, $station.io.inputs, $station.io.outputs, $lineControlText)
    $stationNetworkLines += ('- {0} | {1} | {2} | {3}' -f $station.key, $station.network.ipAddress, $station.network.pnDeviceName, $station.network.interfaceOperatingMode)
}

$stageLines = @()
foreach ($stage in $manifest.projectStages) {
    $stageLines += ('{0}. {1} -> {2}' -f $stage.id, $stage.name, $stage.deliverable)
}

$flowLines = @()
foreach ($link in $manifest.processFlow) {
    $flowLines += ('1. {0} -> {1} : {2}' -f $link.from, $link.to, $link.description)
}

$commLines = @()
foreach ($signal in $manifest.commSignals) {
    $commLines += ('- {0} | {1} | {2}' -f $signal.name, $signal.direction, $signal.description)
}

$alarmLines = @()
foreach ($band in $manifest.alarmBands) {
    $alarmLines += ('- {0} : {1} - {2}' -f $band.station, $band.start, $band.end)
}

$projectName = [string]$manifest.project.name
$projectCode = [string]$manifest.project.code
$projectVersion = [string]$manifest.project.version
$tiaVersion = [string]$manifest.project.tiaVersion
$lineControlStation = [string]$manifest.project.lineControlStation
$projectSubnetName = [string]$manifest.network.subnetName
$projectSubnetMask = [string]$manifest.network.subnetMask
$projectIpProtocolSelection = [string]$manifest.network.ipProtocolSelection

Write-Utf8File -Path (Join-Path $OutputRoot 'README.md') -Content (
    "# $projectName`r`n`r`n" +
    "- Project code: $projectCode`r`n" +
    "- Version: $projectVersion`r`n" +
    "- TIA version: $tiaVersion`r`n" +
    "- Line control station: $lineControlStation`r`n" +
    "- Subnet: $projectSubnetName`r`n" +
    "- Subnet mask: $projectSubnetMask`r`n" +
    "- IP mode: $projectIpProtocolSelection`r`n`r`n" +
    "## Stations`r`n`r`n" +
    (($stationLines -join "`r`n") + "`r`n`r`n") +
    "## Network Plan`r`n`r`n" +
    (($stationNetworkLines -join "`r`n") + "`r`n`r`n") +
    "## Project stages`r`n`r`n" +
    (($stageLines -join "`r`n") + "`r`n`r`n") +
    "## Reuse workflow`r`n`r`n" +
    "1. Edit config/line_manifest.json.`r`n" +
    "2. Confirm subnet, IP and PROFINET device names.`r`n" +
    "3. Fill 04_IOList, 03_CommTable, 05_AlarmList.`r`n" +
    "4. Replace placeholder logic under tia_sources.`r`n" +
    "5. Run tools/build_tia_project_from_manifest_v17.ps1.`r`n"
)

Write-Utf8File -Path (Join-Path $OutputRoot 'config\line_manifest.json') -Content $manifestText
Write-Utf8File -Path (Join-Path $OutputRoot 'config\warning_policy.json') -Content (Get-DefaultWarningPolicyContent)
Write-Utf8File -Path (Join-Path $OutputRoot '00_ProjectInfo\01_project_overview.md') -Content (
    "# Project Overview`r`n`r`n" +
    "- Name: $projectName`r`n" +
    "- Code: $projectCode`r`n" +
    "- Version: $projectVersion`r`n" +
    "- TIA version: $tiaVersion`r`n" +
    "- Subnet: $projectSubnetName`r`n" +
    "- Subnet mask: $projectSubnetMask`r`n" +
    "- IP mode: $projectIpProtocolSelection`r`n`r`n" +
    "## Stations`r`n`r`n" +
    (($stationLines -join "`r`n") + "`r`n")
)

Write-Utf8File -Path (Join-Path $OutputRoot '01_DevicesAndNetwork\00_network_plan.md') -Content (
    "# Network Plan`r`n`r`n" +
    "- Subnet: $projectSubnetName`r`n" +
    "- Type identifier: $($manifest.network.subnetTypeIdentifier)`r`n" +
    "- Subnet mask: $projectSubnetMask`r`n" +
    "- IP protocol selection: $projectIpProtocolSelection`r`n" +
    "- Use router: $($manifest.network.useRouter)`r`n" +
    "- Router address: $($manifest.network.routerAddress)`r`n`r`n" +
    "## Station Addresses`r`n`r`n" +
    (($stationNetworkLines -join "`r`n") + "`r`n")
)

Write-Utf8File -Path (Join-Path $OutputRoot '00_ProjectInfo\02_process_flow.md') -Content (
    "# Process Flow`r`n`r`n" +
    (($flowLines -join "`r`n") + "`r`n")
)

Write-Utf8File -Path (Join-Path $OutputRoot '00_ProjectInfo\03_project_lifecycle.md') -Content (
    "# Project Lifecycle`r`n`r`n" +
    (($stageLines -join "`r`n") + "`r`n")
)

Write-Utf8File -Path (Join-Path $OutputRoot '03_CommTable\station_comm_signals.md') -Content (
    "# Station Communication Signals`r`n`r`n" +
    (($commLines -join "`r`n") + "`r`n")
)

Write-Utf8File -Path (Join-Path $OutputRoot '04_IOList\io_summary.md') -Content (
    "# IO Summary`r`n`r`n" +
    (($stationLines -join "`r`n") + "`r`n")
)

Write-Utf8File -Path (Join-Path $OutputRoot '05_AlarmList\alarm_bands.md') -Content (
    "# Alarm Bands`r`n`r`n" +
    (($alarmLines -join "`r`n") + "`r`n")
)

Write-Utf8File -Path (Join-Path $OutputRoot '06_Naming\naming_rules.md') -Content (@"
# Naming Rules

- Directory names may remain Chinese plus station number.
- PLC block file names stay ASCII and semantic.
- PLC variables use semantic English names.
- Alarm text can stay Chinese, but alarm code must be numeric and segmented.
- HMI object names stay ASCII and carry page prefix.
"@)

$generatedStations = @()
$generatedSources = @()
$tiaSourceRoot = Join-Path $OutputRoot 'tia_sources'

foreach ($station in $manifest.stations) {
    $stationDocRoot = Join-Path (Join-Path $OutputRoot '01_DevicesAndNetwork') $station.folderName
    Ensure-Directory -Path $stationDocRoot
    Write-Utf8File -Path (Join-Path $stationDocRoot 'README.md') -Content (
        ("# {0}`r`n`r`n" -f $station.displayName) +
        ("- Key: {0}`r`n" -f $station.key) +
        ("- Role: {0}`r`n" -f $station.role) +
        ("- CPU: {0}`r`n" -f $station.cpuTypeIdentifier) +
        ("- Device name: {0}`r`n" -f $station.deviceName) +
        ("- Device item name: {0}`r`n" -f $station.deviceItemName) +
        ("- Subnet: {0}`r`n" -f $manifest.network.subnetName) +
        ("- IP address: {0}`r`n" -f $station.network.ipAddress) +
        ("- PROFINET device name: {0}`r`n" -f $station.network.pnDeviceName) +
        ("- Interface mode: {0}`r`n" -f $station.network.interfaceOperatingMode) +
        ("- DI / DO: {0} / {1}`r`n" -f $station.io.inputs, $station.io.outputs) +
        ("- Device templates: {0}`r`n" -f ($station.deviceTemplates -join ', '))
    )

    $outputStationRoot = Join-Path $tiaSourceRoot $station.key
    Ensure-Directory -Path $outputStationRoot

    $generatedStations += [ordered]@{
        StationKey = $station.key
        DisplayName = $station.displayName
        DeviceName = $station.deviceName
        DeviceItemName = $station.deviceItemName
        TypeIdentifier = $station.cpuTypeIdentifier
        HasLineControl = [bool]$station.hasLineControl
        Network = $station.network
    }

    $order = 10
    $typeFiles = [ordered]@{
        'Types\UDT_AlarmItem.udt' = (Get-UdtAlarmItemContent)
        'Types\UDT_CommCmd.udt' = (Get-UdtCommCmdContent)
        'Types\UDT_CommSts.udt' = (Get-UdtCommStsContent)
        'Types\UDT_Parm.udt' = (Get-UdtParmContent)
        'Types\UDT_StationState.udt' = (Get-UdtStationStateContent)
    }
    if ($station.hasLineControl) {
        $typeFiles['Types\UDT_LineState.udt'] = Get-UdtLineStateContent
    }

    foreach ($entry in $typeFiles.GetEnumerator()) {
        Write-Utf8File -Path (Join-Path $outputStationRoot $entry.Key) -Content $entry.Value
        $generatedSources += New-SourceRecord -StationKey $station.key -Order $order -Category 'Type' -RelativePath $entry.Key
        $order += 10
    }

    $dbFiles = [ordered]@{
        'DB\DB_Station.db' = (Get-StationStatusDbContent)
        'DB\DB_Comm.db' = (Get-CommDbContent)
        'DB\DB_Alarm.db' = (Get-AlarmDbContent)
        'DB\DB_Parm.db' = (Get-ParmDbContent)
    }
    if ($station.hasLineControl) {
        $dbFiles['DB\DB_Line.db'] = Get-LineDbContent
    }

    foreach ($entry in $dbFiles.GetEnumerator()) {
        Write-Utf8File -Path (Join-Path $outputStationRoot $entry.Key) -Content $entry.Value
        $generatedSources += New-SourceRecord -StationKey $station.key -Order $order -Category 'DB' -RelativePath $entry.Key
        $order += 10
    }

    $blockFiles = [ordered]@{
        'Blocks\00_OB\Main.scl' = (Get-MainObContent -HasLineControl ([bool]$station.hasLineControl))
        'Blocks\00_OB\Startup.scl' = (Get-StartupObContent)
        'Blocks\10_IO\FC_IMap.scl' = (Get-IMapContent)
        'Blocks\10_IO\FC_QMap.scl' = (Get-QMapContent)
        'Blocks\20_Station\FC_ModeCtrl.scl' = (Get-ModeCtrlContent)
        'Blocks\20_Station\FC_Reset.scl' = (Get-ResetContent)
        'Blocks\20_Station\FC_ManualCtrl.scl' = (Get-ManualCtrlContent)
        'Blocks\20_Station\FC_AutoSeq.scl' = (Get-AutoSeqContent)
        'Blocks\20_Station\FC_Lights.scl' = (Get-LightsContent)
        'Blocks\20_Station\FB_StationCtrl.scl' = (Get-StationCtrlContent)
        'Blocks\30_Comm\FB_Comm.scl' = (Get-CommContent)
        'Blocks\40_Alarm\FB_Alarm.scl' = (Get-AlarmContent)
        'Blocks\50_Device\FB_Cylinder.scl' = (Get-CylinderContent)
        'Blocks\50_Device\FB_Motor.scl' = (Get-MotorContent)
        'Blocks\50_Device\FB_Conveyor.scl' = (Get-ConveyorContent)
        'Blocks\50_Device\FB_Sensor.scl' = (Get-SensorContent)
    }
    if ($station.hasLineControl) {
        $blockFiles['Blocks\70_Line\FB_LineCtrl.scl'] = Get-LineCtrlContent
    }

    foreach ($entry in $blockFiles.GetEnumerator()) {
        Write-Utf8File -Path (Join-Path $outputStationRoot $entry.Key) -Content $entry.Value
        $generatedSources += New-SourceRecord -StationKey $station.key -Order $order -Category 'Block' -RelativePath $entry.Key
        $order += 10
    }
}

$sourceManifest = [ordered]@{
    GeneratedAt = (Get-Date).ToString('s')
    WorkspaceRoot = $OutputRoot
    Project = [ordered]@{
        Code = $manifest.project.code
        Name = $manifest.project.name
        Version = $manifest.project.version
        TiaVersion = $manifest.project.tiaVersion
        LineControlStation = $manifest.project.lineControlStation
        Network = $manifest.network
    }
    Stations = $generatedStations
    Sources = $generatedSources
}

Write-Utf8File -Path (Join-Path $tiaSourceRoot 'manifest.json') -Content (($sourceManifest | ConvertTo-Json -Depth 8))
Write-Host "Generated standard line workspace at: $OutputRoot"
