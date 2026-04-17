$ErrorActionPreference = 'Stop'
$out = Join-Path $PSScriptRoot 'codex_tia_smoketest.txt'
'BEGIN' | Out-File -FilePath $out -Encoding utf8
try {
  Add-Type -Path 'D:\Program Files\Siemens\Automation\Portal V17\Bin\PublicAPI\Siemens.Engineering.Contract.dll'
  Add-Type -Path 'D:\Program Files\Siemens\Automation\Portal V17\Bin\PublicAPI\Siemens.Engineering.ClientAdapter.Interfaces.dll'
  Add-Type -Path 'D:\Program Files\Siemens\Automation\Portal V17\PublicAPI\V17\Siemens.Engineering.dll'
  'ASSEMBLIES_OK' | Out-File -FilePath $out -Append -Encoding utf8
  $tia = New-Object Siemens.Engineering.TiaPortal([Siemens.Engineering.TiaPortalMode]::WithoutUserInterface)
  'TIA_OK' | Out-File -FilePath $out -Append -Encoding utf8
  $tia.Dispose()
  'DISPOSE_OK' | Out-File -FilePath $out -Append -Encoding utf8
}
catch {
  ('ERR|' + $_.Exception.ToString()) | Out-File -FilePath $out -Append -Encoding utf8
  exit 1
}
