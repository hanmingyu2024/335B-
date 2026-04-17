param(
    [Parameter(Mandatory = $true)]
    [object]$PlcSoftware,
    [Parameter(Mandatory = $true)]
    [object[]]$IoPoints,
    [Parameter(Mandatory = $true)]
    [object]$Project,
    [ValidateSet('compare', 'upsert', 'sync')]
    [string]$Mode = 'upsert',
    [string]$TagTableName = 'IO_Tags',
    [string]$ReportPath = ''
)

$ErrorActionPreference = 'Stop'

function Get-ProjectLanguage {
    param(
        [object]$Project,
        [string[]]$PreferredCultures = @('zh-CN', 'en-US')
    )

    foreach ($cultureName in $PreferredCultures) {
        try {
            $culture = New-Object System.Globalization.CultureInfo($cultureName)
            $language = $Project.LanguageSettings.Languages.Find($culture)
            if ($null -ne $language) {
                return $language
            }
        }
        catch {
        }
    }

    return $null
}

function Set-TagComment {
    param(
        [object]$Tag,
        [object]$Project,
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return
    }

    try {
        $language = Get-ProjectLanguage -Project $Project
        if ($null -eq $language) {
            return
        }

        $comment = $Tag.Comment
        if ($null -eq $comment) {
            return
        }

        $item = $comment.Items.Find($language)
        if ($null -ne $item) {
            $item.Text = $Text
        }
    }
    catch {
        Write-Warning "Failed to set comment for tag '$($Tag.Name)': $($_.Exception.Message)"
    }
}

function Get-TagTable {
    param(
        [object]$PlcSoftware,
        [string]$TagTableName,
        [bool]$CreateIfMissing
    )

    $table = $PlcSoftware.TagTableGroup.TagTables.Find($TagTableName)
    if (($null -eq $table) -and $CreateIfMissing) {
        $table = $PlcSoftware.TagTableGroup.TagTables.Create($TagTableName)
    }
    return $table
}

function Get-TagPropertyValue {
    param(
        [object]$Tag,
        [string[]]$CandidateNames
    )

    foreach ($name in $CandidateNames) {
        $property = $Tag.PSObject.Properties[$name]
        if ($null -ne $property -and $null -ne $property.Value) {
            return [string]$property.Value
        }
    }
    return ''
}

function Remove-TagObject {
    param([object]$Tag)

    if ($null -eq $Tag) {
        return
    }

    $deleteMethod = $Tag.GetType().GetMethod('Delete', [Type[]]@())
    if ($null -ne $deleteMethod) {
        $deleteMethod.Invoke($Tag, @())
        return
    }

    if ($Tag.PSObject.Methods.Name -contains 'Delete') {
        $Tag.Delete()
        return
    }

    throw "Tag '$($Tag.Name)' cannot be deleted because Delete() method was not found."
}

function Ensure-TagState {
    param(
        [object]$Tag,
        [object]$Point,
        [object]$Project
    )

    $isOutput = ([string]$Point.direction -eq 'Output')
    $Tag.ExternalAccessible = $true
    $Tag.ExternalVisible = $true
    $Tag.ExternalWritable = $isOutput
    Set-TagComment -Tag $Tag -Project $Project -Text ([string]$Point.comment)
}

function New-TagReportSummary {
    return [ordered]@{
        added = 0
        updated = 0
        deleted = 0
        unchanged = 0
    }
}

$createIfMissing = ($Mode -ne 'compare')
$table = Get-TagTable -PlcSoftware $PlcSoftware -TagTableName $TagTableName -CreateIfMissing $createIfMissing

$existingTags = @()
if ($null -ne $table) {
    $existingTags = @($table.Tags)
}

$existingByName = @{}
foreach ($tag in $existingTags) {
    $existingByName[[string]$tag.Name] = $tag
}

$expectedByName = @{}
foreach ($point in $IoPoints) {
    $expectedByName[[string]$point.symbol_name] = $point
}

$report = [ordered]@{
    mode = $Mode
    tagTable = $TagTableName
    summary = New-TagReportSummary
    to_add = @()
    to_update = @()
    to_delete = @()
    unchanged = @()
}

foreach ($expectedName in $expectedByName.Keys) {
    $point = $expectedByName[$expectedName]
    $existing = $existingByName[$expectedName]

    if ($null -eq $existing) {
        $report.to_add += [ordered]@{
            name = $expectedName
            data_type = [string]$point.data_type
            address = [string]$point.address
        }

        if ($Mode -ne 'compare') {
            $newTag = $table.Tags.Create(
                [string]$point.symbol_name,
                [string]$point.data_type,
                [string]$point.address
            )
            Ensure-TagState -Tag $newTag -Point $point -Project $Project
        }
        continue
    }

    $existingDataType = Get-TagPropertyValue -Tag $existing -CandidateNames @('DataTypeName', 'DataType', 'Datatype')
    $existingAddress = Get-TagPropertyValue -Tag $existing -CandidateNames @('LogicalAddress', 'Address')
    $desiredDataType = [string]$point.data_type
    $desiredAddress = [string]$point.address
    $desiredWritable = ([string]$point.direction -eq 'Output')

    $needsRecreate = ($existingDataType -ne $desiredDataType) -or ($existingAddress -ne $desiredAddress)
    $needsWritableUpdate = $false
    if ($existing.PSObject.Properties['ExternalWritable']) {
        $needsWritableUpdate = ([bool]$existing.ExternalWritable -ne $desiredWritable)
    }

    if ($needsRecreate -or $needsWritableUpdate) {
        $report.to_update += [ordered]@{
            name = $expectedName
            from_data_type = $existingDataType
            to_data_type = $desiredDataType
            from_address = $existingAddress
            to_address = $desiredAddress
            reason = if ($needsRecreate) { 'datatype_or_address_changed' } else { 'writable_or_comment_changed' }
        }

        if ($Mode -ne 'compare') {
            if ($needsRecreate) {
                Remove-TagObject -Tag $existing
                $newTag = $table.Tags.Create(
                    [string]$point.symbol_name,
                    [string]$point.data_type,
                    [string]$point.address
                )
                Ensure-TagState -Tag $newTag -Point $point -Project $Project
            }
            else {
                Ensure-TagState -Tag $existing -Point $point -Project $Project
            }
        }
    }
    else {
        $report.unchanged += [ordered]@{
            name = $expectedName
            data_type = $desiredDataType
            address = $desiredAddress
        }
        if ($Mode -ne 'compare') {
            Ensure-TagState -Tag $existing -Point $point -Project $Project
        }
    }
}

foreach ($existingName in $existingByName.Keys) {
    if ($expectedByName.ContainsKey($existingName)) {
        continue
    }

    $existing = $existingByName[$existingName]
    $report.to_delete += [ordered]@{
        name = $existingName
        data_type = Get-TagPropertyValue -Tag $existing -CandidateNames @('DataTypeName', 'DataType', 'Datatype')
        address = Get-TagPropertyValue -Tag $existing -CandidateNames @('LogicalAddress', 'Address')
    }

    if ($Mode -eq 'sync') {
        Remove-TagObject -Tag $existing
    }
}

$report.summary.added = $report.to_add.Count
$report.summary.updated = $report.to_update.Count
$report.summary.deleted = if ($Mode -eq 'sync') { $report.to_delete.Count } else { 0 }
$report.summary.unchanged = $report.unchanged.Count

if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    $reportDir = Split-Path -Parent $ReportPath
    if (-not [string]::IsNullOrWhiteSpace($reportDir) -and -not (Test-Path -LiteralPath $reportDir)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
}

return $report
