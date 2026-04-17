$ErrorActionPreference = 'Stop'
$out = Join-Path $PSScriptRoot 'typeid_probe_v17.txt'
$candidates = @(
  'OrderNumber:6ES7 214-1BG40-0XB0',
  'OrderNumber:6ES7 214-1BG40-0XB0/V4.0',
  'OrderNumber:6ES7 214-1BG40-0XB0/V4.1',
  'OrderNumber:6ES7 214-1BG40-0XB0/V4.2',
  'OrderNumber:6ES7 214-1BG40-0XB0/V4.3',
  'OrderNumber:6ES7 214-1BG40-0XB0/V4.4',
  'OrderNumber:6ES7 214-1BG40-0XB0/V4.5',
  'OrderNumber:6ES7 214-1AG40-0XB0',
  'OrderNumber:6ES7 214-1AG40-0XB0/V4.0',
  'OrderNumber:6ES7 214-1AG40-0XB0/V4.1',
  'OrderNumber:6ES7 214-1AG40-0XB0/V4.2',
  'OrderNumber:6ES7 214-1AG40-0XB0/V4.3',
  'OrderNumber:6ES7 214-1AG40-0XB0/V4.4',
  'OrderNumber:6ES7 214-1AG40-0XB0/V4.5',
  'OrderNumber:6ES7 214-1BE30-0XB0',
  'OrderNumber:6ES7 214-1AE30-0XB0'
)
[System.IO.File]::WriteAllText($out, "BEGIN`r`n", [System.Text.Encoding]::UTF8)
Add-Type -Path 'D:\Program Files\Siemens\Automation\Portal V17\Bin\PublicAPI\Siemens.Engineering.Contract.dll'
Add-Type -Path 'D:\Program Files\Siemens\Automation\Portal V17\Bin\PublicAPI\Siemens.Engineering.ClientAdapter.Interfaces.dll'
Add-Type -Path 'D:\Program Files\Siemens\Automation\Portal V17\PublicAPI\V17\Siemens.Engineering.dll'
$tia = New-Object Siemens.Engineering.TiaPortal([Siemens.Engineering.TiaPortalMode]::WithoutUserInterface)
$root = Join-Path $PSScriptRoot 'artifacts\typeid_probe_v17'
if (Test-Path $root) { Remove-Item $root -Recurse -Force }
New-Item -ItemType Directory -Path $root | Out-Null
try {
  foreach ($candidate in $candidates) {
    $project = $null
    $projDir = Join-Path $root ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $projDir | Out-Null
    try {
      $project = $tia.Projects.Create((New-Object System.IO.DirectoryInfo($projDir)), 'Probe')
      try {
        $null = $project.Devices.CreateWithItem($candidate, 'PLC_1', 'ProbeDevice')
        Add-Content -LiteralPath $out -Value ('OK|' + $candidate) -Encoding UTF8
      }
      catch {
        Add-Content -LiteralPath $out -Value ('ERR|' + $candidate + '|' + $_.Exception.Message.Replace("`r",' ').Replace("`n",' ')) -Encoding UTF8
      }
    }
    finally {
      if ($project) { $project.Close() }
    }
  }
}
finally {
  $tia.Dispose()
}
