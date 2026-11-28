<#
.SYNOPSIS
    Builds BIOSVersions.rdl from BIOSVersions.sql, using tools\RdlBuilder.psm1.

.DESCRIPTION
    Run it after changing the query or anything below, then publish with tools\Install-Reports.ps1. Plain ASCII on
    purpose (see the module's notes).
#>
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\..\tools\RdlBuilder.psm1') -Force
$c = $RdlColor

# ---- Title, subtitle, tiles, explanation ----
$title = New-RdlTitle 'BIOS versions'
$subtitle = New-RdlSubtitle ('=Parameters!CollectionID.Label & "  ' + $RdlDot + '  " & CountRows("Devices") & " devices on " & CountDistinct(Fields!Model.Value, "Devices") & " models  ' + $RdlDot + '  newest means the newest seen in the site on each model, by release date  ' + $RdlDot + '  run " & Format(Globals!ExecutionTime, "g")')
$tiles = New-RdlTiles @(
    @{ Name = 'TileDevices'; Value = '=CountRows("Devices")';                                  Label = 'Devices';                        Accent = $c.Faint }
    @{ Name = 'TileNewest';  Value = '=Sum(Fields!IsNewest.Value, "Devices")';                 Label = 'On the newest seen';             Accent = $c.Green }
    @{ Name = 'TileBehind';  Value = '=Sum(Fields!IsBehind.Value, "Devices")';                 Label = 'Behind';                         Accent = $c.Amber }
    @{ Name = 'TileAge';     Value = '=Format(First(Fields!AllMedianAge.Value, "Devices"), "0.0")'; Label = 'Years since release, the median'; Accent = $c.Faint }
    @{ Name = 'TileNoData';  Value = '=Sum(Fields!IsNoData.Value, "Devices")';                 Label = 'No BIOS data';                   Accent = $c.Faint }
)
$note = New-RdlNote 'BiosNote' '1.45in' @(
    @('Newest', ': the newest BIOS seen on that exact model in the site, by its release date. No vendor catalog is used, so a model whose every device is behind the vendor''s latest still shows as on the newest: check its age.   '),
    @('Behind', ': older firmware than the newest seen on its model.   '),
    @('Age', ': years since the installed BIOS was released, not since the device was bought.   '),
    @('Versions', ': how many BIOS versions a model runs. More than one usually means updates didn''t reach every device.')
)

# ---- Versions by model, newest first ----
$versionsTitle = New-RdlSectionTitle 'VersionsTitle' 'Versions by model, newest first' '1.95in'
$versions = New-RdlSummaryTable -Name 'Versions' -Top '2.3in' -GroupName 'ModelVersion' -GroupExpression '=Fields!Model.Value & "|" & Fields!BiosVersion.Value' `
    -SortExpression '=Fields!VersionSortKey.Value' -SortDirection Ascending `
    -NoRowsMessage 'No devices with a ConfigMgr client in this collection.' `
    -Columns @(
        @{ HeadName = 'VerHeadModel';    Header = 'Model';    Width = '2.4in';  Align = 'Left' }
        @{ HeadName = 'VerHeadVersion';  Header = 'Version';  Width = '1.6in';  Align = 'Left' }
        @{ HeadName = 'VerHeadReleased'; Header = 'Released'; Width = '0.85in'; Align = 'Right' }
        @{ HeadName = 'VerHeadAge';      Header = 'Age';      Width = '0.6in';  Align = 'Right' }
        @{ HeadName = 'VerHeadDevices';  Header = 'Devices';  Width = '0.65in'; Align = 'Right' }
        @{ HeadName = 'VerHeadStatus';   Header = 'Status';   Width = '1.0in';  Align = 'Left' }
    ) `
    -GroupCells @(
        (New-RdlTablixCell (New-RdlCell -Name 'VerModel' -Value '=First(Fields!Model.Value)')),
        (New-RdlTablixCell (New-RdlCell -Name 'VerVersion' -Value '=IIf(IsNothing(First(Fields!BiosVersion.Value)), "No data", First(Fields!BiosVersion.Value))' -Weight '=IIf(Max(Fields!IsNewest.Value) = 1, "SemiBold", "Normal")')),
        (New-RdlTablixCell (New-RdlCell -Name 'VerReleased' -Value '=First(Fields!BiosDate.Value)' -Align Right -Format 'd' -Color $c.Muted)),
        (New-RdlTablixCell (New-RdlCell -Name 'VerAge' -Value '=First(Fields!AgeYears.Value)' -Align Right -Format '0.0' -Color $c.Muted)),
        (New-RdlTablixCell (New-RdlCell -Name 'VerDevices' -Value '=CountRows()' -Align Right -Format '#,0')),
        (New-RdlTablixCell (New-RdlCell -Name 'VerStatus' -Value '=First(Fields!Status.Value)' -Color ('=IIf(First(Fields!Status.Value) = "Newest", "' + $c.Green + '", IIf(First(Fields!Status.Value) = "Behind", "' + $c.Ink + '", "' + $c.Muted + '"))')))
    ) `
    -TotalCells @(
        (New-RdlTablixCell (New-RdlCell -Name 'VerTotalLabel' -Value '=CountDistinct(Fields!Model.Value) & " models"' -Weight 'SemiBold' -Bg $c.Band)),
        (New-RdlTablixCell (New-RdlCell -Name 'VerTotalVersions' -Value '=CountDistinct(Fields!Model.Value & "|" & Fields!BiosVersion.Value) & " versions"' -Weight 'SemiBold' -Bg $c.Band)),
        (New-RdlTablixCell (New-RdlCell -Name 'VerTotalReleased' -Value '' -Bg $c.Band)),
        (New-RdlTablixCell (New-RdlCell -Name 'VerTotalAge' -Value '' -Bg $c.Band)),
        (New-RdlTablixCell (New-RdlCell -Name 'VerTotalDevices' -Value '=CountRows()' -Align Right -Weight 'SemiBold' -Format '#,0' -Bg $c.Band)),
        (New-RdlTablixCell (New-RdlCell -Name 'VerTotalStatus' -Value '' -Bg $c.Band))
    )

# ---- By model: family, generation, device ----
$modelsTitle = New-RdlSectionTitle 'ModelsTitle' 'By model' '3.3in'
$columns = @(
    @{ Name = 'Name';       Header = 'Family / generation / device'; Width = '2.4in';  Align = 'Left' }
    @{ Name = 'Devices';    Header = 'Devices';                      Width = '0.55in'; Align = 'Right' }
    @{ Name = 'Newest';     Header = 'On newest';                    Width = '0.65in'; Align = 'Center' }
    @{ Name = 'Behind';     Header = 'Behind';                       Width = '0.55in'; Align = 'Center' }
    @{ Name = 'Versions';   Header = 'Versions';                     Width = '0.6in';  Align = 'Center' }
    @{ Name = 'Version';    Header = 'Version';                      Width = '1.5in';  Align = 'Left' }
    @{ Name = 'Released';   Header = 'Released';                     Width = '0.85in'; Align = 'Right' }
    @{ Name = 'Age';        Header = 'Age';                          Width = '0.6in';  Align = 'Right' }
    @{ Name = 'NewestSeen'; Header = 'Newest on its model';          Width = '1.95in'; Align = 'Left' }
    @{ Name = 'LastActive'; Header = 'Last active';                  Width = '0.85in'; Align = 'Right' }
)

function Get-GroupCells([string]$Prefix, [string]$NameCell, [string]$Weight, [string]$Bg, [string]$MedianField) {
    # A family or generation row: counts, how many versions, the median age, and the newest version when it's one model.
    @(
        (New-RdlTablixCell $NameCell),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'Devices') -Value '=CountRows()' -Align Right -Weight $Weight -Format '#,0' -Bg $Bg)),
        (New-RdlTablixCell (New-RdlCountCell ($Prefix + 'Newest') 'IsNewest' $Weight $Bg)),
        (New-RdlTablixCell (New-RdlCountCell ($Prefix + 'Behind') 'IsBehind' $Weight $Bg)),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'Versions') -Value '=CountDistinct(Fields!BiosVersion.Value)' -Align Center -Weight $Weight -Bg $Bg)),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'Version') -Value '' -Bg $Bg)),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'Released') -Value '' -Bg $Bg)),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'Age') -Value ('=First(Fields!' + $MedianField + '.Value)') -Align Right -Format '0.0' -Color $c.Muted -Bg $Bg -ToolTip 'Median years since the installed BIOS was released')),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'NewestSeen') -Value '=IIf(CountDistinct(Fields!Model.Value) = 1, First(Fields!NewestVersion.Value) & " (" & Format(First(Fields!NewestDate.Value), "d") & ")", CountDistinct(Fields!Model.Value) & " models")' -Color $c.Muted -Bg $Bg)),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'LastActive') -Value '=Max(Fields!LastActive.Value)' -Align Right -Format 'd' -Color $c.Muted -Bg $Bg))
    )
}
$familyCells = Get-GroupCells 'Family' (New-RdlFamilyNameCell) 'SemiBold' $c.Band 'FamilyMedianAge'
$generationCells = Get-GroupCells 'Gen' (New-RdlGenerationNameCell) $null $c.White 'GenMedianAge'
$deviceCells = @(
    (New-RdlTablixCell (New-RdlDeviceNameCell)),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceDevices' -Value '' -Align Right)),
    (New-RdlTablixCell (New-RdlDotCell 'DeviceNewest' 'IsNewest' $c.Green $null)),
    (New-RdlTablixCell (New-RdlDotCell 'DeviceBehind' 'IsBehind' $c.Amber $null)),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceVersions' -Value '' -Align Center)),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceVersion' -Value '=Fields!BiosVersion.Value')),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceReleased' -Value '=Fields!BiosDate.Value' -Align Right -Format 'd' -Color $c.Muted)),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceAge' -Value '=Fields!AgeYears.Value' -Align Right -Format '0.0' -Color $c.Muted)),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceNewestSeen' -Value '=IIf(Fields!IsBehind.Value = 1, Fields!NewestVersion.Value & " (" & Format(Fields!NewestDate.Value, "d") & ")", Nothing)' -Color $c.Muted)),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceLastActive' -Value '=Fields!LastActive.Value' -Align Right -Format 'd' -Color $c.Muted))
)
$byModel = New-RdlModelTable -Columns $columns -FamilyCells $familyCells -GenerationCells $generationCells -DeviceCells $deviceCells -Top '3.65in'

# ---- The query and the report ----
$devices = New-RdlDataSet -Name 'Devices' -SqlPath (Join-Path $PSScriptRoot 'BIOSVersions.sql') -Fields ([ordered]@{
    Device = 'String'; Manufacturer = 'String'; Family = 'String'; Generation = 'String'; Model = 'String'; BiosVersion = 'String'; BiosDate = 'DateTime'
    AgeYears = 'Decimal'; NewestVersion = 'String'; NewestDate = 'DateTime'; Status = 'String'; IsNewest = 'Int32'; IsBehind = 'Int32'; IsNoData = 'Int32'
    VersionSortKey = 'String'; LastActive = 'DateTime'; GenMedianAge = 'Decimal'; FamilyMedianAge = 'Decimal'; AllMedianAge = 'Decimal'
})

New-RdlReport -Path (Join-Path $PSScriptRoot 'BIOSVersions.rdl') -ReportId '27a63ecb-a06d-4061-afff-8d8ff9ee6c04' -BodyHeight '4.65in' `
    -Description "The BIOS versions in a collection by model family and generation: how many versions each model runs, how old the installed firmware is, and the devices behind the newest seen on their model. From layer8-reports." `
    -DataSets $devices `
    -Body ($title + $subtitle + $tiles + $note + "`n" + $versionsTitle + "`n" + $versions + "`n" + $modelsTitle + "`n" + $byModel)
