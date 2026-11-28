<#
.SYNOPSIS
    Builds WindowsReleases.rdl from WindowsReleases.sql and Releases.sql, using tools\RdlBuilder.psm1.

.DESCRIPTION
    Run it after changing either query or anything below, then publish with tools\Install-Reports.ps1. Plain ASCII on
    purpose (see the module's notes).
#>
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\..\tools\RdlBuilder.psm1') -Force
$c = $RdlColor

# ---- Title, subtitle, tiles, explanation ----
$title = New-RdlTitle 'Windows releases'
$subtitle = New-RdlSubtitle ('=Parameters!CollectionID.Label & "  ' + $RdlDot + '  " & CountRows("Devices") & " devices  ' + $RdlDot + '  target " & First(Fields!TargetRelease.Value, "Devices") & " (build " & First(Fields!TargetBuildNo.Value, "Devices") & ")" & IIf(Parameters!TargetBuild.Value = 0, ", the release Windows offers most of them", "") & "  ' + $RdlDot + '  run " & Format(Globals!ExecutionTime, "g")')
$tiles = New-RdlTiles @(
    @{ Name = 'TileDevices';   Value = '=CountRows("Devices")';                    Label = 'Devices';                      Accent = $c.Faint }
    @{ Name = 'TileOnTarget';  Value = '=Sum(Fields!IsOnTarget.Value, "Devices")';  Label = 'On the target release';        Accent = $c.Green }
    @{ Name = 'TileBehind';    Value = '=Sum(Fields!IsBehind.Value, "Devices")';    Label = 'Behind';                       Accent = $c.Amber }
    @{ Name = 'TileBlocked';   Value = '=Sum(Fields!IsBlocked.Value, "Devices")';   Label = 'Behind, blocked by hardware';  Accent = $c.Red }
    @{ Name = 'TileWindows10'; Value = '=Sum(Fields!OnWindows10.Value, "Devices")'; Label = 'Still on Windows 10';          Accent = $c.Faint }
)
$note = New-RdlNote 'ReleasesNote' '1.45in' @(
    @('On target', ': runs the target release. Unless you pick one, that''s the release Windows offers most of these devices.   '),
    @('Behind', ': runs an older release than the target.   '),
    @('Why behind', ': Windows'' own check on the device. Hardware: what stops the update (these are Blocked). Nothing in the way: it just hasn''t been updated. Check first: a verdict Microsoft doesn''t document (Yellow or Orange). Not checked: no result has reached the site. Windows checks against the newest release it offers, which can be newer than the target.   '),
    @('On it since', ': when the device got its current release. Every feature update resets it.   '),
    @('Not counted', ': servers, and LTSC releases, which don''t take feature updates.')
)

# ---- Releases, newest first ----
$releasesTitle = New-RdlSectionTitle 'ReleasesTitle' 'Releases, newest first' '1.95in'
$statusColor = '=IIf(First(Fields!Status.Value) = "On target", "' + $c.Green + '", IIf(First(Fields!Status.Value) = "Behind", "' + $c.Ink + '", "' + $c.Muted + '"))'
$releases = New-RdlSummaryTable -Name 'Releases' -Top '2.3in' -GroupName 'Release' -GroupExpression '=Fields!Release.Value' `
    -SortExpression '=Max(Fields!BuildNo.Value)' -SortDirection Descending `
    -NoRowsMessage 'No devices with a ConfigMgr client in this collection.' `
    -Columns @(
        @{ HeadName = 'RelHeadRelease'; Header = 'Release'; Width = '2.0in'; Align = 'Left' }
        @{ HeadName = 'RelHeadBuild';   Header = 'Build';   Width = '0.6in'; Align = 'Right' }
        @{ HeadName = 'RelHeadDevices'; Header = 'Devices'; Width = '0.7in'; Align = 'Right' }
        @{ HeadName = 'RelHeadShare';   Header = 'Share';   Width = '0.6in'; Align = 'Right' }
        @{ HeadName = 'RelHeadStatus';  Header = 'Status';  Width = '0.8in'; Align = 'Left' }
        @{ HeadName = 'RelHeadBlocked'; Header = 'Blocked'; Width = '0.7in'; Align = 'Right' }
        @{ HeadName = 'RelHeadModels';  Header = 'Models';  Width = '0.7in'; Align = 'Right' }
    ) `
    -GroupCells @(
        (New-RdlTablixCell (New-RdlCell -Name 'RelRelease' -Value '=Fields!Release.Value' -Weight '=IIf(Max(Fields!IsOnTarget.Value) = 1, "SemiBold", "Normal")')),
        (New-RdlTablixCell (New-RdlCell -Name 'RelBuild' -Value '=Max(Fields!BuildNo.Value)' -Align Right -Color $c.Muted)),
        (New-RdlTablixCell (New-RdlCell -Name 'RelDevices' -Value '=CountRows()' -Align Right -Format '#,0')),
        (New-RdlTablixCell (New-RdlCell -Name 'RelShare' -Value '=CountRows() / CountRows("Devices")' -Align Right -Format '0%' -Color $c.Muted)),
        (New-RdlTablixCell (New-RdlCell -Name 'RelStatus' -Value '=First(Fields!Status.Value)' -Color $statusColor)),
        (New-RdlTablixCell (New-RdlCell -Name 'RelBlocked' -Value '=Sum(Fields!IsBlocked.Value)' -Align Right -Format '#,0' -Color ('=IIf(Sum(Fields!IsBlocked.Value) = 0, "' + $c.Faint + '", "' + $c.Red + '")'))),
        (New-RdlTablixCell (New-RdlCell -Name 'RelModels' -Value '=CountDistinct(Fields!Model.Value)' -Align Right -Format '#,0'))
    ) `
    -TotalCells @(
        (New-RdlTablixCell (New-RdlCell -Name 'RelTotalLabel' -Value 'All devices' -Weight 'SemiBold' -Bg $c.Band)),
        (New-RdlTablixCell (New-RdlCell -Name 'RelTotalBuild' -Value '' -Bg $c.Band)),
        (New-RdlTablixCell (New-RdlCell -Name 'RelTotalDevices' -Value '=CountRows()' -Align Right -Weight 'SemiBold' -Format '#,0' -Bg $c.Band)),
        (New-RdlTablixCell (New-RdlCell -Name 'RelTotalShare' -Value '' -Bg $c.Band)),
        (New-RdlTablixCell (New-RdlCell -Name 'RelTotalStatus' -Value '' -Bg $c.Band)),
        (New-RdlTablixCell (New-RdlCell -Name 'RelTotalBlocked' -Value '=Sum(Fields!IsBlocked.Value)' -Align Right -Weight 'SemiBold' -Format '#,0' -Bg $c.Band)),
        (New-RdlTablixCell (New-RdlCell -Name 'RelTotalModels' -Value '=CountDistinct(Fields!Model.Value)' -Align Right -Weight 'SemiBold' -Format '#,0' -Bg $c.Band))
    )

# ---- By model: family, generation, device ----
$modelsTitle = New-RdlSectionTitle 'ModelsTitle' 'By model' '3.3in'
$columns = @(
    @{ Name = 'Name';       Header = 'Family / generation / device'; Width = '2.0in';  Align = 'Left' }
    @{ Name = 'Devices';    Header = 'Devices';                      Width = '0.55in'; Align = 'Right' }
    @{ Name = 'OnTarget';   Header = 'On target';                    Width = '0.6in';  Align = 'Center' }
    @{ Name = 'Behind';     Header = 'Behind';                       Width = '0.55in'; Align = 'Center' }
    @{ Name = 'Blocked';    Header = 'Blocked';                      Width = '0.55in'; Align = 'Center' }
    @{ Name = 'Win10';      Header = 'Windows 10';                   Width = '0.65in'; Align = 'Center' }
    @{ Name = 'Release';    Header = 'Release';                      Width = '1.25in'; Align = 'Left' }
    @{ Name = 'Build';      Header = 'Build';                        Width = '0.5in';  Align = 'Right' }
    @{ Name = 'Since';      Header = 'On it since';                  Width = '0.75in'; Align = 'Right' }
    @{ Name = 'WhyBehind';  Header = 'Why behind';                   Width = '2.35in'; Align = 'Left' }
    @{ Name = 'LastActive'; Header = 'Last active';                  Width = '0.75in'; Align = 'Right' }
)

function Get-GroupCells([string]$Prefix, [string]$NameCell, [string]$Weight, [string]$Bg) {
    # A family or generation row: counts in the status columns, its releases, and its latest contact.
    @(
        (New-RdlTablixCell $NameCell),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'Devices') -Value '=CountRows()' -Align Right -Weight $Weight -Format '#,0' -Bg $Bg)),
        (New-RdlTablixCell (New-RdlCountCell ($Prefix + 'OnTarget') 'IsOnTarget' $Weight $Bg)),
        (New-RdlTablixCell (New-RdlCountCell ($Prefix + 'Behind') 'IsBehind' $Weight $Bg)),
        (New-RdlTablixCell (New-RdlCountCell ($Prefix + 'Blocked') 'IsBlocked' $Weight $Bg)),
        (New-RdlTablixCell (New-RdlCountCell ($Prefix + 'Win10') 'OnWindows10' $Weight $Bg)),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'Release') -Value '=IIf(CountDistinct(Fields!Release.Value) = 1, First(Fields!Release.Value), CountDistinct(Fields!Release.Value) & " releases")' -Color $c.Muted -Bg $Bg)),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'Build') -Value '' -Bg $Bg)),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'Since') -Value '' -Bg $Bg)),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'WhyBehind') -Value '' -Bg $Bg)),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'LastActive') -Value '=Max(Fields!LastActive.Value)' -Align Right -Format 'd' -Color $c.Muted -Bg $Bg))
    )
}
$familyCells = Get-GroupCells 'Family' (New-RdlFamilyNameCell) 'SemiBold' $c.Band
$generationCells = Get-GroupCells 'Gen' (New-RdlGenerationNameCell) $null $c.White
$deviceCells = @(
    (New-RdlTablixCell (New-RdlDeviceNameCell)),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceDevices' -Value '' -Align Right)),
    (New-RdlTablixCell (New-RdlDotCell 'DeviceOnTarget' 'IsOnTarget' $c.Green $null)),
    (New-RdlTablixCell (New-RdlDotCell 'DeviceBehind' 'IsBehind' $c.Amber $null)),
    (New-RdlTablixCell (New-RdlDotCell 'DeviceBlocked' 'IsBlocked' $c.Red $null)),
    (New-RdlTablixCell (New-RdlDotCell 'DeviceWin10' 'OnWindows10' $c.Muted $null)),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceRelease' -Value '=Fields!Release.Value' -Color ('=IIf(Fields!IsBehind.Value = 1 Or Fields!IsOnTarget.Value = 1, "' + $c.Ink + '", "' + $c.Muted + '")') -ToolTip '=Fields!Status.Value')),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceBuild' -Value '=Fields!BuildNo.Value' -Align Right -Color $c.Muted)),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceSince' -Value '=Fields!OnItSince.Value' -Align Right -Format 'd' -Color $c.Muted)),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceWhyBehind' -Value '=Fields!WhyBehind.Value' -Color ('=IIf(Fields!IsBlocked.Value = 1, "' + $c.Red + '", "' + $c.Ink + '")') -ToolTip '=IIf(IsNothing(Fields!CheckedVersion.Value) Or Fields!IsBehind.Value = 0, Nothing, "Windows checked it against " & Fields!CheckedVersion.Value & IIf(IsNothing(Fields!ReasonCodes.Value), "", ". Its codes: " & Fields!ReasonCodes.Value))')),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceLastActive' -Value '=Fields!LastActive.Value' -Align Right -Format 'd' -Color $c.Muted))
)
$byModel = New-RdlModelTable -Columns $columns -FamilyCells $familyCells -GenerationCells $generationCells -DeviceCells $deviceCells -Top '3.65in'

# ---- The queries and the report ----
$devices = New-RdlDataSet -Name 'Devices' -SqlPath (Join-Path $PSScriptRoot 'WindowsReleases.sql') -Parameters 'UserSIDs', 'CollectionID', 'TargetBuild' -Fields ([ordered]@{
    Device = 'String'; Manufacturer = 'String'; Family = 'String'; Generation = 'String'; Model = 'String'; Release = 'String'; BuildNo = 'Int32'
    Status = 'String'; IsOnTarget = 'Int32'; IsBehind = 'Int32'; IsBlocked = 'Int32'; OnWindows10 = 'Int32'; OnItSince = 'DateTime'; LastActive = 'DateTime'
    WhyBehind = 'String'; CheckedVersion = 'String'; ReasonCodes = 'String'; TargetRelease = 'String'; TargetBuildNo = 'Int32'
})
$choices = New-RdlDataSet -Name 'TargetChoices' -SqlPath (Join-Path $PSScriptRoot 'Releases.sql') -Fields ([ordered]@{ Build = 'Int32'; Label = 'String' })
$target = New-RdlParameter -Name 'TargetBuild' -Type Integer -Prompt 'Target release' -DataSet 'TargetChoices' -ValueField 'Build' -LabelField 'Label'

New-RdlReport -Path (Join-Path $PSScriptRoot 'WindowsReleases.rdl') -ReportId '5de82480-b7ee-4829-842b-184420a392e1' -BodyHeight '4.65in' `
    -Description "The Windows release each device in a collection runs, against a target release (by default the one Windows offers): which devices are behind, and why, from Windows' own check on each device. By release, and by model family and generation. From layer8-reports." `
    -DataSets $devices, $choices -Parameters $target `
    -Body ($title + $subtitle + $tiles + $note + "`n" + $releasesTitle + "`n" + $releases + "`n" + $modelsTitle + "`n" + $byModel)
