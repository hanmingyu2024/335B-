$ErrorActionPreference = 'Stop'

$root = "D:\智能体应用PLC博途\3358B柔性生产线"

$root = Join-Path $PSScriptRoot '3358B柔性生产线'

$root = Join-Path $PSScriptRoot ((Get-ChildItem -LiteralPath $PSScriptRoot -Directory | Where-Object { $_.Name -like '3358B*' } | Select-Object -First 1).Name)

function Ensure-Dir {
    param([string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Write-File {
    param(
        [string]$Path,
        [string]$Content
    )
    $dir = Split-Path -Parent $Path
    Ensure-Dir $dir
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    try {
        [System.IO.File]::WriteAllText($Path, $Content, $utf8)
    }
    catch {
        Write-Host "FAILED PATH: $Path"
        throw
    }
}

function Get-Placeholder {
    param(
        [string]$Extension,
        [string]$Name
    )

    switch ($Extension) {
        '.scl' { return "// $Name`r`n// Placeholder for SCL logic.`r`n" }
        '.db' { return "// $Name`r`n// Placeholder for DB definition.`r`n" }
        '.udt' { return "// $Name`r`n// Placeholder for UDT definition.`r`n" }
        '.md' { return "# $Name`r`n`r`nGenerated placeholder file.`r`n" }
        default { return "// $Name`r`n" }
    }
}

Ensure-Dir $root

$topFiles = @(
    'README.md',
    '00_项目说明\3358B产线说明.md',
    '00_项目说明\版本记录.md',
    '00_项目说明\工艺流程说明.md',
    '00_项目说明\网络拓扑说明.md',
    '02_HMI\HMI规划.md',
    '03_通信点表\站间通信点表.md',
    '04_IO点表\IO点表总表.md',
    '05_报警表\报警清单.md',
    '06_公共命名规范\命名规范.md'
)

foreach ($relativePath in $topFiles) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($relativePath)
    $ext = [System.IO.Path]::GetExtension($relativePath)
    Write-File -Path (Join-Path $root $relativePath) -Content (Get-Placeholder -Extension $ext -Name $name)
}

$commonUdts = @(
    'UDT_StationState.udt',
    'UDT_CommCmd.udt',
    'UDT_CommSts.udt',
    'UDT_AlarmItem.udt',
    'UDT_Parm.udt'
)

$stationTemplates = @(
    @{
        Name = '01站供料站 [CPU 1214C AC_DC_Rly]'
        DeviceFiles = @(
            'DB_Cyl_Stopper.db',
            'DB_Cyl_Pusher_1.db',
            'DB_Conv_Feed_1.db',
            'DB_Sensor_PartIn_1.db',
            'DB_Sensor_OutPos_1.db',
            'DB_Sensor_PusherFwd_1.db',
            'DB_Sensor_PusherBwd_1.db'
        )
    },
    @{
        Name = '02站加工站 [CPU 1214C AC_DC_Rly]'
        DeviceFiles = @(
            'DB_Cyl_Clamp_1.db',
            'DB_Cyl_Process_1.db',
            'DB_Motor_Process_1.db',
            'DB_Sensor_PartPos_1.db',
            'DB_Sensor_ClampFwd_1.db',
            'DB_Sensor_ClampBwd_1.db'
        )
    },
    @{
        Name = '03站输送站 [CPU 1214C DC_DC_DC]'
        DeviceFiles = @(
            'DB_Conv_Main_1.db',
            'DB_Motor_Transfer_1.db',
            'DB_Cyl_Stopper_1.db',
            'DB_Sensor_InPos_1.db',
            'DB_Sensor_MidPos_1.db',
            'DB_Sensor_OutPos_1.db'
        )
    },
    @{
        Name = '04站装配站 [CPU 1214C AC_DC_Rly]'
        DeviceFiles = @(
            'DB_Cyl_Locate_1.db',
            'DB_Cyl_Assemble_1.db',
            'DB_Motor_Assemble_1.db',
            'DB_Sensor_LocateFwd_1.db',
            'DB_Sensor_LocateBwd_1.db',
            'DB_Sensor_AssembleOK_1.db'
        )
    },
    @{
        Name = '05站分拣站 [CPU 1214C AC_DC_Rly]'
        DeviceFiles = @(
            'DB_Cyl_Sort_1.db',
            'DB_Cyl_Reject_1.db',
            'DB_Conv_Unload_1.db',
            'DB_Sensor_OKPos_1.db',
            'DB_Sensor_NGPos_1.db',
            'DB_Sensor_UnloadPos_1.db'
        )
    }
)

$commonBlockFiles = @(
    '程序块\00_OB\Main_OB1.scl',
    '程序块\00_OB\Startup_OB100.scl',
    '程序块\00_OB\OB123_说明.md',
    '程序块\10_IO\FC_IMap.scl',
    '程序块\10_IO\FC_QMap.scl',
    '程序块\20_站控\FB_StationCtrl.scl',
    '程序块\20_站控\DB_Station.db',
    '程序块\20_站控\FC_ModeCtrl.scl',
    '程序块\20_站控\FC_AutoSeq.scl',
    '程序块\20_站控\FC_ManualCtrl.scl',
    '程序块\20_站控\FC_Reset.scl',
    '程序块\20_站控\FC_Lights.scl',
    '程序块\30_通信\FB_Comm.scl',
    '程序块\30_通信\DB_Comm.db',
    '程序块\40_报警\FB_Alarm.scl',
    '程序块\40_报警\DB_Alarm.db',
    '程序块\50_设备\FB_Cylinder.scl',
    '程序块\50_设备\FB_Motor.scl',
    '程序块\50_设备\FB_Conveyor.scl',
    '程序块\50_设备\FB_Sensor.scl',
    '程序块\60_数据\DB_Parm.db',
    '设备组态\README.md',
    '在线和诊断\README.md'
)

foreach ($station in $stationTemplates) {
    $stationRoot = Join-Path $root ("01_设备和网络\" + $station.Name)

    foreach ($relativePath in $commonBlockFiles) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($relativePath)
        $ext = [System.IO.Path]::GetExtension($relativePath)
        Write-File -Path (Join-Path $stationRoot $relativePath) -Content (Get-Placeholder -Extension $ext -Name $name)
    }

    foreach ($deviceFile in $station.DeviceFiles) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($deviceFile)
        $ext = [System.IO.Path]::GetExtension($deviceFile)
        Write-File -Path (Join-Path $stationRoot ("程序块\50_设备\" + $deviceFile)) -Content (Get-Placeholder -Extension $ext -Name $name)
    }

    foreach ($udtFile in $commonUdts) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($udtFile)
        $ext = [System.IO.Path]::GetExtension($udtFile)
        Write-File -Path (Join-Path $stationRoot ("PLC数据类型\" + $udtFile)) -Content (Get-Placeholder -Extension $ext -Name $name)
    }
}

Write-Host "Generated structure at $root"
