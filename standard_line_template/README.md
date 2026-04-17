# Standard Line Template

This folder contains the reusable manifest-driven template for generating and building a TIA V17 project.

## Files

- `line_manifest.sample.json`: sample project manifest.
- `line_manifest.schema.json`: strict schema used at scaffold entry.
- `io_automation.md`: I/O automation notes.
- `openness_capability_matrix.md`: Openness capability summary.
- `openness_stage_execution_map.md`: stage-to-script mapping.

## Current Validation Gates

1. `tools/new_standard_line_project.ps1`
   - Strict schema validation against `line_manifest.schema.json`.
   - Semantic validation (unique station key/number, line-control consistency, flow references, alarm-band references).
   - Auto-generates `config/warning_policy.json`.
2. `tools/generate_io_assets_from_workbook.py`
   - Validates manifest I/O count versus workbook I/O count.
   - Enforces axis-required points for Station03 and Station05.
   - Writes `config/io_consistency_report.json`.
3. `tools/build_tia_project_from_manifest_v17.ps1`
   - Applies warning policy and supports warning-level block on compile warnings.
   - Supports tag sync mode: `compare`, `upsert`, `sync`.
