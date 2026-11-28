<#
.SYNOPSIS
    Builds ClientHealth.rdl from ClientHealth.sql, using tools\RdlBuilder.psm1.

.DESCRIPTION
    Run it after changing the query or anything below, then publish with tools\Install-Reports.ps1. Plain ASCII on
    purpose (see the module's notes).
#>
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\..\tools\RdlBuilder.psm1') -Force
$c = $RdlColor

# ---- Title, subtitle, tiles, explanation ----
$title = New-RdlTitle 'Client health'
$subtitle = New-RdlSubtitle ('=Parameters!CollectionID.Label & "  ' + $RdlDot + '  " & CountRows("Devices") & " devices" & IIf(Sum(Fields!IsNoStatus.Value, "Devices") > 0, ", " & Sum(Fields!IsNoStatus.Value, "Devices") & " with no client status", "") & "  ' + $RdlDot + '  judged by the site''s own client status settings  ' + $RdlDot + '  run " & Format(Globals!ExecutionTime, "g")')
$tiles = New-RdlTiles @(
    @{ Name = 'TileDevices';  Value = '=CountRows("Devices")';                  Label = 'Devices';              Accent = $c.Faint }
    @{ Name = 'TileHealthy';  Value = '=Sum(Fields!IsHealthy.Value, "Devices")';  Label = 'Healthy';              Accent = $c.Green }
    @{ Name = 'TileStale';    Value = '=Sum(Fields!IsStale.Value, "Devices")';    Label = 'Something stale';      Accent = $c.Amber }
    @{ Name = 'TileFailing';  Value = '=Sum(Fields!IsFailing.Value, "Devices")';  Label = 'Failing health check'; Accent = $c.Red }
    @{ Name = 'TileInactive'; Value = '=Sum(Fields!IsInactive.Value, "Devices")'; Label = 'Inactive';             Accent = $c.Red }
)
$note = New-RdlNote 'HealthNote' '1.45in' @(
    @('Inactive', ': the site counts the client inactive, by its Client Status Settings (7 days by default).   '),
    @('Failing health check', ': the client''s own health check failed, as the site reports it.   '),
    @('Stale', ': active, but its hardware inventory, policy requests or heartbeat discovery haven''t reached the site within those settings. What''s wrong says which.   '),
    @('Dates', ': the last of each that reached the site. On a model row, the oldest among its devices.')
)

# ---- What's wrong, most common first ----
$problemsTitle = New-RdlSectionTitle 'ProblemsTitle' 'What''s wrong, most common first' '1.95in'
$problems = New-RdlSummaryTable -Name 'Problems' -Top '2.3in' -GroupName 'Problem' -GroupExpression '=Fields!Problem.Value' `
    -Filter '=Fields!IsUnhealthy.Value', '=1' -NoRowsMessage 'Every client in this collection is healthy.' `
    -Columns @(
        @{ HeadName = 'ProbHeadProblem'; Header = 'What''s wrong'; Width = '2.6in'; Align = 'Left' }
        @{ HeadName = 'ProbHeadDevices'; Header = 'Devices';       Width = '0.7in'; Align = 'Right' }
        @{ HeadName = 'ProbHeadModels';  Header = 'Models';        Width = '0.7in'; Align = 'Right' }
    ) `
    -GroupCells @(
        (New-RdlTablixCell (New-RdlCell -Name 'ProbProblem' -Value '=Fields!Problem.Value' -Color ('=IIf(Max(Fields!IsStale.Value) = 1, "' + $c.Ink + '", "' + $c.Red + '")'))),
        (New-RdlTablixCell (New-RdlCell -Name 'ProbDevices' -Value '=CountRows()' -Align Right -Format '#,0')),
        (New-RdlTablixCell (New-RdlCell -Name 'ProbModels' -Value '=CountDistinct(Fields!Model.Value)' -Align Right -Format '#,0'))
    ) `
    -TotalCells @(
        (New-RdlTablixCell (New-RdlCell -Name 'ProbTotalLabel' -Value 'All that need a look' -Weight 'SemiBold' -Bg $c.Band)),
        (New-RdlTablixCell (New-RdlCell -Name 'ProbTotalDevices' -Value '=CountRows()' -Align Right -Weight 'SemiBold' -Format '#,0' -Bg $c.Band)),
        (New-RdlTablixCell (New-RdlCell -Name 'ProbTotalModels' -Value '=CountDistinct(Fields!Model.Value)' -Align Right -Weight 'SemiBold' -Format '#,0' -Bg $c.Band))
    )

# ---- By model: family, generation, device ----
$modelsTitle = New-RdlSectionTitle 'ModelsTitle' 'By model' '3.3in'
$columns = @(
    @{ Name = 'Name';      Header = 'Family / generation / device'; Width = '2.2in';  Align = 'Left' }
    @{ Name = 'Devices';   Header = 'Devices';                      Width = '0.55in'; Align = 'Right' }
    @{ Name = 'Healthy';   Header = 'Healthy';                      Width = '0.6in';  Align = 'Center' }
    @{ Name = 'Stale';     Header = 'Stale';                        Width = '0.55in'; Align = 'Center' }
    @{ Name = 'Failing';   Header = 'Failing';                      Width = '0.6in';  Align = 'Center' }
    @{ Name = 'Inactive';  Header = 'Inactive';                     Width = '0.6in';  Align = 'Center' }
    @{ Name = 'State';     Header = 'State';                        Width = '0.9in';  Align = 'Left' }
    @{ Name = 'Wrong';     Header = 'What''s wrong';                Width = '1.5in';  Align = 'Left' }
    @{ Name = 'Contact';   Header = 'Last contact';                 Width = '0.75in'; Align = 'Right' }
    @{ Name = 'Policy';    Header = 'Policy';                       Width = '0.75in'; Align = 'Right' }
    @{ Name = 'Inventory'; Header = 'Inventory';                    Width = '0.75in'; Align = 'Right' }
    @{ Name = 'Heartbeat'; Header = 'Heartbeat';                    Width = '0.75in'; Align = 'Right' }
)

function Get-GroupCells([string]$Prefix, [string]$NameCell, [string]$Weight, [string]$Bg) {
    # A family or generation row: counts, and the oldest of each date among its devices.
    $oldest = 'The oldest among its devices'
    @(
        (New-RdlTablixCell $NameCell),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'Devices') -Value '=CountRows()' -Align Right -Weight $Weight -Format '#,0' -Bg $Bg)),
        (New-RdlTablixCell (New-RdlCountCell ($Prefix + 'Healthy') 'IsHealthy' $Weight $Bg)),
        (New-RdlTablixCell (New-RdlCountCell ($Prefix + 'Stale') 'IsStale' $Weight $Bg)),
        (New-RdlTablixCell (New-RdlCountCell ($Prefix + 'Failing') 'IsFailing' $Weight $Bg)),
        (New-RdlTablixCell (New-RdlCountCell ($Prefix + 'Inactive') 'IsInactive' $Weight $Bg)),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'State') -Value '' -Bg $Bg)),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'Wrong') -Value '' -Bg $Bg)),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'Contact') -Value '=Min(Fields!LastContact.Value)' -Align Right -Format 'd' -Color $c.Muted -Bg $Bg -ToolTip $oldest)),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'Policy') -Value '=Min(Fields!LastPolicy.Value)' -Align Right -Format 'd' -Color $c.Muted -Bg $Bg -ToolTip $oldest)),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'Inventory') -Value '=Min(Fields!LastInventory.Value)' -Align Right -Format 'd' -Color $c.Muted -Bg $Bg -ToolTip $oldest)),
        (New-RdlTablixCell (New-RdlCell -Name ($Prefix + 'Heartbeat') -Value '=Min(Fields!LastHeartbeat.Value)' -Align Right -Format 'd' -Color $c.Muted -Bg $Bg -ToolTip $oldest))
    )
}
function Get-DateColor([string]$Flag) { '=IIf(Fields!' + $Flag + '.Value = 1, "' + $c.Red + '", "' + $c.Muted + '")' }
$familyCells = Get-GroupCells 'Family' (New-RdlFamilyNameCell) 'SemiBold' $c.Band
$generationCells = Get-GroupCells 'Gen' (New-RdlGenerationNameCell) $null $c.White
$deviceCells = @(
    (New-RdlTablixCell (New-RdlDeviceNameCell)),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceDevices' -Value '' -Align Right)),
    (New-RdlTablixCell (New-RdlDotCell 'DeviceHealthy' 'IsHealthy' $c.Green $null)),
    (New-RdlTablixCell (New-RdlDotCell 'DeviceStale' 'IsStale' $c.Amber $null)),
    (New-RdlTablixCell (New-RdlDotCell 'DeviceFailing' 'IsFailing' $c.Red $null)),
    (New-RdlTablixCell (New-RdlDotCell 'DeviceInactive' 'IsInactive' $c.Red $null)),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceState' -Value '=Fields!ClientState.Value' -Color ('=IIf(Fields!IsFailing.Value = 1 Or Fields!IsInactive.Value = 1, "' + $c.Red + '", "' + $c.Muted + '")') -ToolTip '=IIf(IsNothing(Fields!LastHealthCheck.Value), Nothing, "Last health check: " & Format(Fields!LastHealthCheck.Value, "d"))')),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceWrong' -Value '=Fields!Problem.Value' -Color ('=IIf(Fields!IsStale.Value = 1, "' + $c.Ink + '", "' + $c.Red + '")'))),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceContact' -Value '=Fields!LastContact.Value' -Align Right -Format 'd' -Color (Get-DateColor 'IsInactive'))),
    (New-RdlTablixCell (New-RdlCell -Name 'DevicePolicy' -Value '=Fields!LastPolicy.Value' -Align Right -Format 'd' -Color (Get-DateColor 'PolicyStale'))),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceInventory' -Value '=Fields!LastInventory.Value' -Align Right -Format 'd' -Color (Get-DateColor 'InventoryStale'))),
    (New-RdlTablixCell (New-RdlCell -Name 'DeviceHeartbeat' -Value '=Fields!LastHeartbeat.Value' -Align Right -Format 'd' -Color (Get-DateColor 'HeartbeatStale')))
)
$byModel = New-RdlModelTable -Columns $columns -FamilyCells $familyCells -GenerationCells $generationCells -DeviceCells $deviceCells -Top '3.65in'

# ---- The query and the report ----
$devices = New-RdlDataSet -Name 'Devices' -SqlPath (Join-Path $PSScriptRoot 'ClientHealth.sql') -Fields ([ordered]@{
    Device = 'String'; Manufacturer = 'String'; Family = 'String'; Generation = 'String'; Model = 'String'; ClientState = 'String'; Status = 'String'
    Problem = 'String'; IsHealthy = 'Int32'; IsStale = 'Int32'; IsFailing = 'Int32'; IsInactive = 'Int32'; IsNoStatus = 'Int32'; IsUnhealthy = 'Int32'
    InventoryStale = 'Int32'; PolicyStale = 'Int32'; HeartbeatStale = 'Int32'; LastContact = 'DateTime'; LastPolicy = 'DateTime'
    LastInventory = 'DateTime'; LastHeartbeat = 'DateTime'; LastHealthCheck = 'DateTime'
})

New-RdlReport -Path (Join-Path $PSScriptRoot 'ClientHealth.rdl') -ReportId 'a5e87efe-6563-4f91-9c7b-95bf92cfe9fa' -BodyHeight '4.65in' `
    -Description "Which ConfigMgr clients in a collection are inactive, failing their own health check, or behind on inventory, policy or heartbeat, by the site's own client status settings, grouped by model family and generation. From layer8-reports." `
    -DataSets $devices `
    -Body ($title + $subtitle + $tiles + $note + "`n" + $problemsTitle + "`n" + $problems + "`n" + $modelsTitle + "`n" + $byModel)
