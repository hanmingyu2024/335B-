# PLC TIA V17 Automation Workspace

This repository automates a manifest-driven workflow for Siemens TIA Portal V17:

1. scaffold workspace from manifest,
2. generate I/O assets from Excel workbook,
3. build/archive TIA project through Openness.

## Environment

- OS: Windows 10/11.
- PowerShell: Windows PowerShell 5.1 or newer.
- Python: 3.10+.
- TIA Portal: V17 with Openness PublicAPI installed.
- Account: current Windows user must be in local group `Siemens TIA Openness`.

Recommended environment variable:

```powershell
$env:TIA_PORTAL_ROOT = "D:\Program Files\Siemens\Automation\Portal V17"
```

Python dependency:

```powershell
python -m pip install --upgrade openpyxl
```

## Standard Run Order

1. Run scaffold + I/O generation:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\invoke_standard_line_pipeline.ps1 `
  -ManifestPath .\standard_line_template\line_manifest.sample.json `
  -WorkspaceRoot .\artifacts\standard_line_workspace `
  -Force
```

2. Optional: compare tags only (no write):

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\invoke_standard_line_pipeline.ps1 `
  -ManifestPath .\standard_line_template\line_manifest.sample.json `
  -WorkspaceRoot .\artifacts\standard_line_workspace `
  -ArtifactRoot .\artifacts\standard_line_tia `
  -BuildTiaProject `
  -TagSyncMode compare
```

3. Full chain (recommended):

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\invoke_standard_line_pipeline.ps1 `
  -ManifestPath .\standard_line_template\line_manifest.sample.json `
  -WorkspaceRoot .\artifacts\standard_line_workspace `
  -ArtifactRoot .\artifacts\standard_line_tia `
  -BuildTiaProject `
  -TagSyncMode upsert `
  -Force
```

4. Drift-clean mode (delete unmanaged tags):

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\invoke_standard_line_pipeline.ps1 `
  -BuildTiaProject `
  -TagSyncMode sync
```

## Validation and Gate Behavior

- Manifest gate:
  - strict schema validation (`line_manifest.schema.json`),
  - semantic checks (station uniqueness, line-control consistency, flow/alarm references).
- I/O gate:
  - manifest I/O counts must match workbook counts per station,
  - Station03 axis required points,
  - Station05 axis required points,
  - report output: `artifacts\standard_line_workspace\config\io_consistency_report.json`.
- Compile warning gate:
  - controlled by `config\warning_policy.json`,
  - hardware address out-of-range warning can block build.

## Warning Policy

Workspace scaffold writes default policy:

`artifacts\standard_line_workspace\config\warning_policy.json`

Default behavior:

- `hardware_address_out_of_range`: `block`
- `generic_warning`: `allow`

## Outputs

- Workspace: `artifacts\standard_line_workspace`
- Build artifacts: `artifacts\standard_line_tia`
- Compile logs: `artifacts\standard_line_tia\logs\*_compile.txt`
- Warning summary: `artifacts\standard_line_tia\logs\warning_summary.json`
- Tag sync summary: `artifacts\standard_line_tia\logs\tag_sync_summary.json`

## Common Errors

- `Current logon token does not include 'Siemens TIA Openness'`:
  - User has been added to group but session token not refreshed.
  - Action: sign out Windows and sign in again, then rerun.
- `Inputs or outputs are used that do not exist in the configured hardware.`:
  - PLC addresses exceed configured hardware channels.
  - Action: fix workbook/IO mapping or adjust warning policy intentionally.
- `I/O consistency validation failed`:
  - Manifest I/O count or Station03/Station05 axis points do not match workbook.
  - Action: align Excel and manifest, then rerun.
