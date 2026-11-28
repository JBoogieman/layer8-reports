<#
.SYNOPSIS
    Builds DiskSpace.rdl from DiskSpace.sql, using tools\RdlBuilder.psm1.

.DESCRIPTION
    Run it after changing the query or anything below, then publish with tools\Install-Reports.ps1. Plain ASCII on
    purpose (see the module's notes).
#>
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\..\tools\RdlBuilder.psm1') -Force
$c = $RdlColor

# ---- Title, subtitle, tiles, explanation ----
$title = New-RdlTitle 'Disk space'
$subtitle = New-RdlSubtitle ('=Parameters!CollectionID.Label & "  ' + $RdlDot + '  " & CountRows("Devices") & " devices  ' + $RdlDot + '  low means under " & Parameters!LowGB.Value & " GB free on C:, running out means getting there within " & Parameters!Days.Value & " days  ' + $RdlDot + '  run " & Format(Globals!ExecutionTime, "g")')
$tiles = New-RdlTiles @(
    @{ Name = 'TileDevices';    Value = '=CountRows("Devices")';                          Label = 'Devices';                   Accent = $c.Faint }
    @{ Name = 'TileLow';        Value = '=Sum(Fields!IsLow.Value, "Devices")';            Label = 'Low on C:';                 Accent = $c.Red }
    @{ Name = 'TileRunningOut'; Value = '=Sum(Fields!IsRunningOut.Value, "Devices")';     Label = 'Running out';               Accent = $c.Amber }
    @{ Name = 'TileMedianFree'; Value = '=First(Fields!AllMedianFreeGB.Value, "Devices")'; Label = 'GB free on C:, the median'; Accent = $c.Faint }
    @{ Name = 'TileNoData';     Value = '=Sum(Fields!IsNoData.Value, "Devices")';         Label = 'No disk data';              Accent = $c.Faint }
)
$note = New-RdlNote 'DiskNote' '1.45in' @(
    @('Low', ': less than " & Parameters!LowGB.Value & " GB free on C:.   '),
    @('Running out', ': not low yet, but at its recent rate C: gets there within " & Parameters!Days.Value & " days. Low in says when.   '),
    @('Per week', ': the trend through every free-space figure hardware inventory recorded for C: in the last " & Parameters!Days.Value & " days. It needs at least 3 of them, spread over a week. Inventory history keeps them until Delete Aged Inventory History removes them.   '),
    @('Median', ': half the devices have less free.')
)

# ---- Running low, least free first ----
$riskTitle = New-RdlSectionTitle 'RiskTitle' 'Running low, least free first' '1.95in'
$risk = New-RdlSummaryTable -Name 'AtRisk' -Top '2.3in' -GroupName 'RiskDevice' -GroupExpression '=Fields!Device.Value' `
    -SortExpression '=Min(Fields!FreeGB.Value)' -SortDirection Ascending -Filter '=Fields!IsAtRisk.Value', '=1' `
    -NoRowsMessage 'No device is low on C: or running out.' `
    -Columns @(
        @{ HeadName = 'RiskHeadDevice';  Header = 'Device';   Width = '1.5in'; Align = 'Left' }
        @{ HeadName = 'RiskHeadModel';   Header = 'Model';    Width = '2.0in'; Align = 'Left' }
        @{ HeadName = 'RiskHeadFree';    Header = 'Free GB';  Width = '0.6in'; Align = 'Right' }
        @{ HeadName = 'RiskHeadSize';    Header = 'Size GB';  Width = '0.6in'; Align = 'Right' }
        @{ HeadName = 'RiskHeadPerWeek'; Header = 'Per week'; Width = '0.7in'; Align = 'Right' }
        @{ HeadName = 'RiskHeadLowIn';   Header = 'Low in';   Width = '0.7in'; Align = 'Right' }
        @{ HeadName = 'RiskHeadUser';    Header = 'Top user'; Width = '1.6in'; Align = 'Left' }
    ) `
    -GroupCells @(
        (New-RdlTablixCell (New-RdlCell -Name 'RiskDeviceName' -Value '=Fields!Device.Value')),
        (New-RdlTablixCell (New-RdlCell -Name 'RiskModel' -Value '=First(Fields!Model.Value)' -Color $c.Muted)),
        (New-RdlTablixCell (New-RdlCell -Name 'RiskFree' -Value '=Min(Fields!FreeGB.Value)' -Align Right -Format '0.0' -Color ('=IIf(Max(Fields!IsLow.Value) = 1, "' + $c.Red + '", "' + $c.Ink + '")'))),
        (New-RdlTablixCell (New-RdlCell -Name 'RiskSize' -Value '=Max(Fields!SizeGB.Value)' -Align Right -Format '#,0' -Color $c.Muted)),
        (New-RdlTablixCell (New-RdlCell -Name 'RiskPerWeek' -Value '=Min(Fields!GBPerWeek.Value)' -Align Right -Format '+0.0;-0.0;0.0' -Color $c.Muted)),
        (New-RdlTablixCell (New-RdlCell -Name 'RiskLowIn' -Value '=IIf(IsNothing(Min(Fields!DaysToLow.Value)), Nothing, IIf(Min(Fields!DaysToLow.Value) < 1, "under a day", IIf(Min(Fields!DaysToLow.Value) = 1, "1 day", Min(Fields!DaysToLow.Value) & " days")))' -Align Right)),
        (New-RdlTablixCell (New-RdlCell -Name 'RiskUser' -Value '=First(Fields!TopUser.Value)' -Color $c.Muted))
    ) `
    -TotalCells @(
        (New-RdlTablixCell (New-RdlCell -Name 'RiskTotalLabel' -Value 'All' -Weight 'SemiBold' -Bg $c.Band)),
        (New-RdlTablixCell (New-RdlCell -Name 'RiskTotalCount' -Value '=CountRows() & " devices low or running out"' -Weight 'SemiBold' -Bg $c.Band)),
        (New-RdlTablixCell (New-RdlCell -Name 'RiskTotalFree' -Value '' -Bg $c.Band)),
        (New-RdlTablixCell (New-RdlCell -Name 'RiskTotalSize' -Value '' -Bg $c.Band)),
        (New-RdlTablixCell (New-RdlCell -Name 'RiskTotalPerWeek' -Value '' -Bg $c.Band)),
        (New-RdlTablixCell (New-RdlCell -Name 'RiskTotalLowIn' -Value '' -Bg $c.Band)),
        (New-RdlTablixCell (New-RdlCell -Name 'RiskTotalUser' -Value '' -Bg $c.Band))
    )

# ---- By model: family, generation, device ----
$modelsTitle = New-RdlSectionTitle 'ModelsTitle' 'By model' '3.3in'
$columns = @(
    @{ Name = 'Name';       Header = 'Family / generation / device'; Width = '2.4in';  Align = 'Left' }
    @{ Name = 'Devices';    Header = 'Devices';                      Width = '0.55in'; Align = 'Right' }
    @{ Name = 'Low';        Header = 'Low';                          Width = '0.5in';  Align = 'Center' }
    @{ Name = 'RunningOut'; Header = 'Running out';                  Width = '0.6in';  Align = 'Center' }
    @{ Name = 'Median';     Header = 'Median free';                  Width = '0.65in'; Align = 'Right' }
    @{ Name = 'Size';       Header = 'Size GB';                      Width = '0.6in';  Align = 'Right' }
    @{ Name = 'Free';       Header = 'Free GB';                      Width = '0.6in';  Align = 'Right' }
    @{ Name = 'Share';      Header = 'Free';                         Width = '0.5in';  Align = 'Right' }
    @{ Name = 'PerWeek';    Header = 'Per week';                     Width = '0.7in';  Align = 'Right' }
    @{ Name = 'LowIn';      Header = 'Low in';                       Width = '0.7in';  Align = 'Right' }
    @{ Name = 'TopUser';    Header = 'Top user';                     Width = '1.85in'; Align = 'Left' }
    @{ Name = 'Inventory';  Header = 'Inventory';                    Width = '0.85in'; Align = 'Right' }
)

function Get-GroupCells([string]$Prefix, [string]$NameCell, [string]$Weight, [string]$Bg, [string]$MedianField) {
    # A family or generation row: counts, its median free space, and the least free on any of its devices.
    @(
        (New-RdlTablixCell $NameCell),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'Devices') -Value '=CountRows()' -Align Right -Weight $Weight -Format '#,0' -Bg $Bg)),
        (New-RdlTablixCell (New-RdlCountCell ($Prefix + 'Low') 'IsLow' $Weight $Bg)),
        (New-RdlTablixCell (New-RdlCountCell ($Prefix + 'RunningOut') 'IsRunningOut' $Weight $Bg)),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'Median') -Value ('=First(Fields!' + $MedianField + '.Value)') -Align Right -Weight $Weight -Format '0.0' -Bg $Bg)),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'Size') -Value '' -Bg $Bg)),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'Free') -Value '=Min(Fields!FreeGB.Value)' -Align Right -Format '0.0' -Color $c.Muted -Bg $Bg -ToolTip 'The least free on any of its devices')),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'Share') -Value '' -Bg $Bg)),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'PerWeek') -Value '' -Bg $Bg)),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'LowIn') -Value '' -Bg $Bg)),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'TopUser') -Value '' -Bg $Bg)),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'Inventory') -Value '=Max(Fields!InventoryAt.Value)' -Align Right -Format 'd' -Color $c.Muted -Bg $Bg))
    )
}
$familyCells = Get-GroupCells 'Family' (New-RdlFamilyNameCell) 'SemiBold' $c.Band 'FamilyMedianFreeGB'
$generationCells = Get-GroupCells 'Gen' (New-RdlGenerationNameCell) $null $c.White 'GenMedianFreeGB'
$deviceCells = @(
    (New-RdlTablixCell (New-RdlDeviceNameCell)),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceDevices' -Value '' -Align Right)),
    (New-RdlTablixCell (New-RdlDotCell 'DeviceLow' 'IsLow' $c.Red $null)),
    (New-RdlTablixCell (New-RdlDotCell 'DeviceRunningOut' 'IsRunningOut' $c.Amber $null)),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceMedian' -Value '' -Align Right)),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceSize' -Value '=Fields!SizeGB.Value' -Align Right -Format '#,0' -Color $c.Muted)),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceFree' -Value '=Fields!FreeGB.Value' -Align Right -Format '0.0' -Color ('=IIf(Fields!IsLow.Value = 1, "' + $c.Red + '", "' + $c.Ink + '")'))),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceShare' -Value '=Fields!FreeShare.Value' -Align Right -Format '0%' -Color $c.Muted)),
    (New-RdlTablixCell (New-RdlCell -Name 'DevicePerWeek' -Value '=Fields!GBPerWeek.Value' -Align Right -Format '+0.0;-0.0;0.0' -Color $c.Muted)),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceLowIn' -Value '=IIf(IsNothing(Fields!DaysToLow.Value), Nothing, IIf(Fields!DaysToLow.Value < 1, "under a day", IIf(Fields!DaysToLow.Value = 1, "1 day", Fields!DaysToLow.Value & " days")))' -Align Right -Color ('=IIf(Fields!IsRunningOut.Value = 1, "' + $c.Ink + '", "' + $c.Muted + '")'))),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceTopUser' -Value '=Fields!TopUser.Value' -Color $c.Muted)),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceInventory' -Value '=Fields!InventoryAt.Value' -Align Right -Format 'd' -Color $c.Muted))
)
$byModel = New-RdlModelTable -Columns $columns -FamilyCells $familyCells -GenerationCells $generationCells -DeviceCells $deviceCells -Top '3.65in'

# ---- The query and the report ----
$devices = New-RdlDataSet -Name 'Devices' -SqlPath (Join-Path $PSScriptRoot 'DiskSpace.sql') -Parameters 'UserSIDs', 'CollectionID', 'LowGB', 'Days' -Fields ([ordered]@{
    Device = 'String'; Manufacturer = 'String'; Family = 'String'; Generation = 'String'; Model = 'String'; TopUser = 'String'
    SizeGB = 'Decimal'; FreeGB = 'Decimal'; FreeShare = 'Decimal'; GBPerWeek = 'Decimal'; DaysToLow = 'Int32'; InventoryAt = 'DateTime'
    Status = 'String'; IsLow = 'Int32'; IsRunningOut = 'Int32'; IsAtRisk = 'Int32'; IsNoData = 'Int32'
    GenMedianFreeGB = 'Decimal'; FamilyMedianFreeGB = 'Decimal'; AllMedianFreeGB = 'Decimal'
})
$parameters = @(
    (New-RdlParameter -Name 'LowGB' -Type Integer -Default '10' -Prompt 'Low below (GB free on C:)'),
    (New-RdlParameter -Name 'Days' -Type Integer -Default '30' -Prompt 'Trend over, and look ahead (days)')
)

New-RdlReport -Path (Join-Path $PSScriptRoot 'DiskSpace.rdl') -ReportId '40d09012-74eb-4877-8382-e24e1091d8b0' -BodyHeight '4.65in' `
    -Description "Free space on C: for each device in a collection, which way it's heading from inventory history, and when it'll be low at that rate, grouped by model family and generation. From layer8-reports." `
    -DataSets $devices -Parameters $parameters `
    -Body ($title + $subtitle + $tiles + $note + "`n" + $riskTitle + "`n" + $risk + "`n" + $modelsTitle + "`n" + $byModel)
