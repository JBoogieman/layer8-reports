<#
.SYNOPSIS
    Builds a layer8-reports report (.rdl) from a few lines per table, in the reports' shared look.

.DESCRIPTION
    Each report that's built this way has a Build-Report.ps1 next to its .sql. That script imports this module, says
    what's specific to its report (title, tiles, columns, wording) and calls New-RdlReport, which writes the .rdl with
    everything the reports share:

      - the site's data source, and the two datasets that apply the reader's security scopes and list collections
      - the parameters: the reader's identity (hidden), the collection, and "Show every device"
      - the Freshness dataset (reports\DataFreshness.sql) and the page footer it feeds
      - the page: US Letter, landscape, quarter-inch margins

    Change a report by changing its .sql or its Build-Report.ps1, then run the build script and Install-Reports.ps1.
    Don't edit a built .rdl by hand: the next build replaces it. Fleet by model, Boot times and crashes and Hardware
    lifecycle came before the builder and are still edited as .rdl files.

    It was proven against a report built by the scratch script it grew out of: rebuilding that report with the module
    gave a byte-for-byte identical .rdl.

    The module is plain ASCII. Windows PowerShell reads a script without a byte order mark as ANSI, which would
    garble anything else, so the middle dot and the bullet are built from their character codes.

.EXAMPLE
    .\reports\<ReportName>\Build-Report.ps1

    A build script starts with Import-Module (Join-Path $PSScriptRoot '..\..\tools\RdlBuilder.psm1') -Force, builds
    its title, tiles, note and tables with the New-Rdl* functions, and ends with New-RdlReport.
#>

$ErrorActionPreference = 'Stop'

# The reports' colours.
$RdlColor = @{
    Ink   = '#0b0b0b'   # text
    Muted = '#52514e'   # secondary text, headers
    Faint = '#c3c2b7'   # zeros, header rule, neutral tiles
    Grey  = '#898781'   # footer, neutral markers
    Line  = '#e1e0d9'   # row rules, tile borders
    Band  = '#f9f9f7'   # family rows, total rows
    White = '#ffffff'
    Red   = '#d03b3b'
    Green = '#0ca30c'
    Amber = '#fab219'
}
$RdlDot    = [string][char]0x00B7   # the middle dot between subtitle parts
$RdlBullet = [string][char]0x25CF   # the marker in a device's status columns

$DataSourceName = 'AutoGen__5C6358F2_4BB6_4a1b_A16E_8D96795D8602_'

function ConvertTo-RdlText([string]$Text) {
    # Escapes text for an .rdl element: & < > " and '.
    [Security.SecurityElement]::Escape($Text)
}

function ConvertTo-RdlPlainText([string]$Text) {
    # Escapes only what element text must: & < and >. Used for messages, so quotes stay as typed.
    $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
}

function Get-RdlRunStyle([string]$Size, [string]$Weight, [string]$Format, [string]$Color) {
    '<Style><FontFamily>Segoe UI</FontFamily><FontSize>' + $Size + '</FontSize>' +
    $(if ($Weight) { '<FontWeight>' + (ConvertTo-RdlText $Weight) + '</FontWeight>' }) +
    $(if ($Format) { '<Format>' + (ConvertTo-RdlText $Format) + '</Format>' }) +
    '<Color>' + (ConvertTo-RdlText $Color) + '</Color></Style>'
}

# ---- Text in a table cell ----

function New-RdlCell {
    # A table cell's text box. Value, Weight, Color and PadLeft can be expressions (starting with =).
    param([Parameter(Mandatory)][string]$Name, [string]$Value, [string]$Align = 'Left', [string]$Weight,
          [string]$Color = $RdlColor.Ink, [string]$Format, [ValidateSet('Head', 'Row')][string]$Kind = 'Row', [string]$Bg,
          [string]$PadLeft = '4pt', [string]$ToolTip, [string]$Toggle)
    $rule = if ($Kind -eq 'Head') { $RdlColor.Faint } else { $RdlColor.Line }
    '<Textbox Name="' + $Name + '"><CanGrow>true</CanGrow><KeepTogether>true</KeepTogether><Paragraphs><Paragraph><TextRuns><TextRun><Value>' +
    (ConvertTo-RdlText $Value) + '</Value>' + (Get-RdlRunStyle '8pt' $Weight $Format $Color) +
    '</TextRun></TextRuns><Style><TextAlign>' + $Align + '</TextAlign></Style></Paragraph></Paragraphs>' +
    $(if ($Toggle) { '<ToggleImage><InitialState>' + (ConvertTo-RdlText $Toggle) + '</InitialState></ToggleImage>' }) +
    $(if ($ToolTip) { '<ToolTip>' + (ConvertTo-RdlText $ToolTip) + '</ToolTip>' }) +
    '<Style><VerticalAlign>' + $(if ($Kind -eq 'Head') { 'Bottom' } else { 'Middle' }) + '</VerticalAlign><PaddingLeft>' +
    (ConvertTo-RdlText $PadLeft) + '</PaddingLeft><PaddingRight>3pt</PaddingRight><PaddingTop>2pt</PaddingTop><PaddingBottom>2pt</PaddingBottom><Border><Style>None</Style></Border><BottomBorder><Color>' +
    $rule + '</Color><Style>Solid</Style><Width>0.75pt</Width></BottomBorder>' +
    $(if ($Bg) { '<BackgroundColor>' + $Bg + '</BackgroundColor>' }) + '</Style></Textbox>'
}

function New-RdlHeadCell([string]$Name, [string]$Text, [string]$Align = 'Left') {
    # A column header.
    New-RdlCell -Name $Name -Value $Text -Align $Align -Weight 'SemiBold' -Color $RdlColor.Muted -Kind Head
}

function New-RdlCountCell([string]$Name, [string]$Field, [string]$Weight, [string]$Bg) {
    # A group's count of devices flagged 1 in Field, grey when it's zero.
    New-RdlCell -Name $Name -Value ('=Sum(Fields!' + $Field + '.Value)') -Align Center -Weight $Weight -Format '#,0' -Bg $Bg `
        -Color ('=IIf(Sum(Fields!' + $Field + '.Value) = 0, "' + $RdlColor.Faint + '", "' + $RdlColor.Ink + '")')
}

function New-RdlDotCell([string]$Name, [string]$Field, [string]$Color, [string]$ToolTip) {
    # A device's marker in a status column, shown when Field is 1.
    New-RdlCell -Name $Name -Value ('=IIf(Fields!' + $Field + '.Value = 1, "' + $RdlBullet + '", Nothing)') -Align Center -Color $Color -ToolTip $ToolTip
}

function New-RdlFamilyNameCell([string]$Bg = $RdlColor.Band) {
    New-RdlCell -Name 'FamilyName' -Value '=Fields!Family.Value' -Weight 'SemiBold' -Bg $Bg -PadLeft '2pt'
}

function New-RdlGenerationNameCell([string]$Bg = $RdlColor.White) {
    # A model without generations shows its family here instead, and its family row is hidden. Its toggle opens the
    # devices, and starts open when "Show every device" is on.
    New-RdlCell -Name 'GenName' -Value '=IIf(Fields!Generation.Value = "", Fields!Family.Value, Fields!Generation.Value)' `
        -Weight '=IIf(Fields!Generation.Value = "", "SemiBold", "Normal")' -Bg $Bg `
        -PadLeft '=IIf(Fields!Generation.Value = "", "2pt", "14pt")' -Toggle '=Parameters!ShowDevices.Value'
}

function New-RdlDeviceNameCell {
    New-RdlCell -Name 'DeviceName' -Value '=Fields!Device.Value' -PadLeft '26pt'
}

# ---- Table rows ----

function New-RdlTablixCell([string]$Box, [int]$Span = 1) {
    # Wraps a text box as a table cell. A cell that spans columns is followed by the empty cells it covers.
    '  <TablixCell><CellContents>' + $Box + $(if ($Span -gt 1) { '<ColSpan>' + $Span + '</ColSpan>' }) + '</CellContents></TablixCell>' +
    ("`n  <TablixCell />" * ($Span - 1))
}

function New-RdlRow([string]$Height, [string[]]$Cells) {
    '<TablixRow><Height>' + $Height + '</Height><TablixCells>' + "`n" + ($Cells -join "`n") + "`n" + '</TablixCells></TablixRow>'
}

# ---- Text above the tables ----

function New-RdlRun([string]$Value, [string]$Size = '8pt', [string]$Weight, [string]$Color = $RdlColor.Muted) {
    '<TextRun><Value>' + (ConvertTo-RdlText $Value) + '</Value>' + (Get-RdlRunStyle $Size $Weight $null $Color) + '</TextRun>'
}

function New-RdlTextbox([string]$Name, [string]$Top, [string]$Width, [string]$Height, [string]$Runs, [string]$VAlign = 'Middle') {
    # A text box on the page, at the left margin, holding one paragraph of runs.
    '<Textbox Name="' + $Name + '"><Top>' + $Top + '</Top><Left>0in</Left><Height>' + $Height + '</Height><Width>' + $Width +
    '</Width><CanGrow>true</CanGrow><KeepTogether>true</KeepTogether><Paragraphs><Paragraph><TextRuns>' + $Runs +
    '</TextRuns><Style></Style></Paragraph></Paragraphs><Style><VerticalAlign>' + $VAlign +
    '</VerticalAlign><PaddingLeft>0pt</PaddingLeft><PaddingRight>3pt</PaddingRight><PaddingTop>2pt</PaddingTop><PaddingBottom>2pt</PaddingBottom><Border><Style>None</Style></Border></Style></Textbox>'
}

function New-RdlTitle([string]$Text) {
    New-RdlTextbox 'Title' '0in' '6in' '0.38in' (New-RdlRun $Text '16pt' 'SemiBold' $RdlColor.Ink)
}

function New-RdlSubtitle([string]$Expression) {
    # One line under the title: collection, counts, what the report measures, when it ran.
    New-RdlTextbox 'Subtitle' '0.38in' '10.5in' '0.25in' (New-RdlRun $Expression '9pt' $null $RdlColor.Muted)
}

function New-RdlSectionTitle([string]$Name, [string]$Text, [string]$Top) {
    New-RdlTextbox $Name $Top '6in' '0.3in' (New-RdlRun $Text '11pt' 'SemiBold' $RdlColor.Ink)
}

function New-RdlTile([string]$Name, [string]$Left, [string]$Value, [string]$Label, [string]$Accent) {
    # A figure and its label in a box with a coloured left edge.
    '<Textbox Name="' + $Name + '"><Top>0.75in</Top><Left>' + $Left + '</Left><Height>0.62in</Height><Width>1.896in</Width><CanGrow>true</CanGrow><KeepTogether>true</KeepTogether><Paragraphs>' +
    '<Paragraph><TextRuns><TextRun><Value>' + (ConvertTo-RdlText $Value) + '</Value>' + (Get-RdlRunStyle '18pt' 'SemiBold' '#,0' $RdlColor.Ink) + '</TextRun></TextRuns><Style></Style></Paragraph>' +
    '<Paragraph><TextRuns><TextRun><Value>' + (ConvertTo-RdlText $Label) + '</Value>' + (Get-RdlRunStyle '8pt' $null $null $RdlColor.Muted) + '</TextRun></TextRuns><Style></Style></Paragraph></Paragraphs>' +
    '<Style><VerticalAlign>Top</VerticalAlign><PaddingLeft>8pt</PaddingLeft><PaddingRight>3pt</PaddingRight><PaddingTop>2pt</PaddingTop><PaddingBottom>2pt</PaddingBottom><Border><Color>' +
    $RdlColor.Line + '</Color><Style>Solid</Style><Width>0.75pt</Width></Border><LeftBorder><Color>' + $Accent +
    '</Color><Style>Solid</Style><Width>3pt</Width></LeftBorder><BackgroundColor>' + $RdlColor.White + '</BackgroundColor></Style></Textbox>'
}

function New-RdlTiles([hashtable[]]$Tiles) {
    # Up to five tiles across the page: each @{ Name; Value; Label; Accent }.
    $lefts = '0.000in', '2.146in', '4.292in', '6.438in', '8.584in'
    if ($Tiles.Count -gt $lefts.Count) { throw "At most $($lefts.Count) tiles fit across the page." }
    $i = 0
    ($Tiles | ForEach-Object { New-RdlTile $_.Name $lefts[$i++] $_.Value $_.Label $_.Accent }) -join ''
}

function New-RdlNote([string]$Name, [string]$Top, [object[]]$Parts) {
    # The explanation under the tiles: each part is @(term, text). The term is bold; the text follows it, and is
    # passed as an expression so its trailing spaces survive.
    $runs = ($Parts | ForEach-Object { (New-RdlRun $_[0] '8pt' 'SemiBold' $RdlColor.Ink) + (New-RdlRun ('="' + $_[1] + '"')) }) -join ''
    New-RdlTextbox $Name $Top '10.5in' '0.3in' $runs
}

# ---- Tables ----

function Test-RdlWidth([object[]]$Columns, [decimal]$Expected) {
    # Decimal, not Measure-Object: floating point makes 10.5 add up to 10.500000000000002.
    $sum = [decimal]0; foreach ($c in $Columns) { $sum += [decimal]($c.Width -replace 'in$', '') }
    if ($sum -ne $Expected) { throw "Columns add up to $sum in, not $Expected" }
}

function New-RdlModelTable {
    <#
    The table every by-model report has: a header row, then families, their generations, and their devices, the
    devices hidden until a generation is opened (or "Show every device" is on). Columns are @{ Name; Header; Width;
    Align } and add up to the page's 10.5in. Each row's cells come from New-RdlTablixCell, one per column, and the
    generation row must use New-RdlGenerationNameCell (its toggle opens the devices).
    #>
    param([string]$Name = 'ByModel', [Parameter(Mandatory)][object[]]$Columns, [Parameter(Mandatory)][string[]]$FamilyCells,
          [Parameter(Mandatory)][string[]]$GenerationCells, [Parameter(Mandatory)][string[]]$DeviceCells, [string]$Top = '1.95in',
          [string]$NoRowsMessage = 'No devices with a ConfigMgr client in this collection.')
    Test-RdlWidth $Columns 10.5
    foreach ($row in $FamilyCells, $GenerationCells, $DeviceCells) {
        if ($row.Count -ne $Columns.Count) { throw "A row has $($row.Count) cells for $($Columns.Count) columns." }
    }
    $head = $Columns | ForEach-Object { New-RdlTablixCell (New-RdlHeadCell ('Head' + $_.Name) $_.Header $_.Align) }
    '<Tablix Name="' + $Name + '"><TablixBody><TablixColumns>' + (($Columns | ForEach-Object { '<TablixColumn><Width>' + $_.Width + '</Width></TablixColumn>' }) -join '') + '</TablixColumns><TablixRows>' + "`n" +
    (New-RdlRow '0.3in' $head) + "`n" +
    (New-RdlRow '0.22in' $FamilyCells) + "`n" +
    (New-RdlRow '0.22in' $GenerationCells) + "`n" +
    (New-RdlRow '0.2in' $DeviceCells) + "`n" +
    '</TablixRows></TablixBody><TablixColumnHierarchy><TablixMembers>' + ('<TablixMember />' * $Columns.Count) + '</TablixMembers></TablixColumnHierarchy><TablixRowHierarchy><TablixMembers>
  <TablixMember><KeepWithGroup>After</KeepWithGroup><RepeatOnNewPage>true</RepeatOnNewPage></TablixMember>
  <TablixMember>
    <Group Name="Family"><GroupExpressions><GroupExpression>=Fields!Family.Value</GroupExpression></GroupExpressions><DocumentMapLabel>=Fields!Family.Value</DocumentMapLabel></Group>
    <SortExpressions><SortExpression><Value>=CountRows()</Value><Direction>Descending</Direction></SortExpression><SortExpression><Value>=Fields!Family.Value</Value></SortExpression></SortExpressions>
    <TablixMembers>
      <TablixMember><Visibility><Hidden>=Fields!Generation.Value = ""</Hidden></Visibility><KeepWithGroup>After</KeepWithGroup></TablixMember>
      <TablixMember>
        <Group Name="Generation"><GroupExpressions><GroupExpression>=Fields!Generation.Value</GroupExpression></GroupExpressions></Group>
        <SortExpressions><SortExpression><Value>=Val(Replace(Replace(Fields!Generation.Value, "Gen", ""), "G", ""))</Value></SortExpression><SortExpression><Value>=Fields!Generation.Value</Value></SortExpression></SortExpressions>
        <TablixMembers>
          <TablixMember><KeepWithGroup>After</KeepWithGroup></TablixMember>
          <TablixMember>
            <Group Name="Device" />
            <SortExpressions><SortExpression><Value>=Fields!Device.Value</Value></SortExpression></SortExpressions>
            <Visibility><Hidden>=Not Parameters!ShowDevices.Value</Hidden><ToggleItem>GenName</ToggleItem></Visibility>
          </TablixMember>
        </TablixMembers>
      </TablixMember>
    </TablixMembers>
  </TablixMember>
</TablixMembers></TablixRowHierarchy>
<NoRowsMessage>' + (ConvertTo-RdlPlainText $NoRowsMessage) + '</NoRowsMessage>
<DataSetName>Devices</DataSetName>
<Top>' + $Top + '</Top><Left>0in</Left><Height>0.94in</Height><Width>10.5in</Width>
<Style><Border><Style>None</Style></Border><FontFamily>Segoe UI</FontFamily><FontSize>8pt</FontSize><Color>' + $RdlColor.Muted + '</Color></Style>
</Tablix>'
}

function New-RdlSummaryTable {
    <#
    A table of the devices grouped by one expression, most common first, with a total row. Columns are @{ HeadName;
    Header; Width; Align }. Filter, when given, is @(expression, value): only devices where they're equal are counted.
    #>
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][object[]]$Columns, [Parameter(Mandatory)][string]$GroupName,
          [Parameter(Mandatory)][string]$GroupExpression, [Parameter(Mandatory)][string[]]$GroupCells, [Parameter(Mandatory)][string[]]$TotalCells,
          [string[]]$Filter, [Parameter(Mandatory)][string]$NoRowsMessage, [Parameter(Mandatory)][string]$Top, [string]$DataSetName = 'Devices')
    foreach ($row in $GroupCells, $TotalCells) {
        if ($row.Count -ne $Columns.Count) { throw "A row has $($row.Count) cells for $($Columns.Count) columns." }
    }
    $width = [decimal]0; foreach ($c in $Columns) { $width += [decimal]($c.Width -replace 'in$', '') }
    $head = $Columns | ForEach-Object { New-RdlTablixCell (New-RdlHeadCell $_.HeadName $_.Header $_.Align) }
    '<Tablix Name="' + $Name + '"><TablixBody><TablixColumns>' + (($Columns | ForEach-Object { '<TablixColumn><Width>' + $_.Width + '</Width></TablixColumn>' }) -join '') + '</TablixColumns><TablixRows>' + "`n" +
    (New-RdlRow '0.3in' $head) + "`n" +
    (New-RdlRow '0.22in' $GroupCells) + "`n" +
    (New-RdlRow '0.22in' $TotalCells) + "`n" +
    '</TablixRows></TablixBody><TablixColumnHierarchy><TablixMembers>' + ('<TablixMember />' * $Columns.Count) + '</TablixMembers></TablixColumnHierarchy><TablixRowHierarchy><TablixMembers>
  <TablixMember><KeepWithGroup>After</KeepWithGroup><RepeatOnNewPage>true</RepeatOnNewPage></TablixMember>
  <TablixMember>
    <Group Name="' + $GroupName + '"><GroupExpressions><GroupExpression>' + (ConvertTo-RdlText $GroupExpression) + '</GroupExpression></GroupExpressions></Group>
    <SortExpressions><SortExpression><Value>=CountRows()</Value><Direction>Descending</Direction></SortExpression><SortExpression><Value>' + (ConvertTo-RdlText $GroupExpression) + '</Value></SortExpression></SortExpressions>
  </TablixMember>
  <TablixMember><KeepWithGroup>Before</KeepWithGroup></TablixMember>
</TablixMembers></TablixRowHierarchy>
<NoRowsMessage>' + (ConvertTo-RdlPlainText $NoRowsMessage) + '</NoRowsMessage>
<DataSetName>' + $DataSetName + '</DataSetName>
' + $(if ($Filter) { '<Filters><Filter><FilterExpression>' + (ConvertTo-RdlText $Filter[0]) + '</FilterExpression><Operator>Equal</Operator><FilterValues><FilterValue>' + (ConvertTo-RdlText $Filter[1]) + '</FilterValue></FilterValues></Filter></Filters>' + "`n" }) +
    '<Top>' + $Top + '</Top><Left>0in</Left><Height>0.74in</Height><Width>' + $width + 'in</Width>
<Style><Border><Style>None</Style></Border><FontFamily>Segoe UI</FontFamily><FontSize>8pt</FontSize><Color>' + $RdlColor.Muted + '</Color></Style>
</Tablix>'
}

# ---- Datasets and the report ----

function New-RdlDataSet {
    # A dataset from a .sql file. Fields is an ordered hashtable of column name to .NET type (String, Int32, DateTime,
    # Decimal). Parameters are the report parameters the query uses, passed as @Name.
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$SqlPath, [Parameter(Mandatory)][System.Collections.IDictionary]$Fields,
          [string[]]$Parameters = @('UserSIDs', 'CollectionID'), [int]$Timeout = 600)
    $sql = [IO.File]::ReadAllText($SqlPath).TrimEnd()
    '<DataSet Name="' + $Name + '">
  <Query><DataSourceName>' + $DataSourceName + '</DataSourceName>
    <QueryParameters>
' + (($Parameters | ForEach-Object { '      <QueryParameter Name="@' + $_ + '"><Value>=Parameters!' + $_ + '.Value</Value></QueryParameter>' }) -join "`n") + '
    </QueryParameters>
    <CommandText>' + (ConvertTo-RdlText $sql) + '
</CommandText>' + $(if ($Timeout) { "`n    <Timeout>$Timeout</Timeout>" }) + '</Query>
  <Fields>' + (($Fields.Keys | ForEach-Object { '<Field Name="' + $_ + '"><DataField>' + $_ + '</DataField><rd:TypeName>System.' + $Fields[$_] + '</rd:TypeName></Field>' }) -join '') + '</Fields>
</DataSet>'
}

function Get-RdlFreshnessDataSet {
    # The footer's dataset, from reports\DataFreshness.sql, laid out as in every report.
    $sql = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\reports\DataFreshness.sql')).TrimEnd()
    '<DataSet Name="Freshness">
  <Query><DataSourceName>' + $DataSourceName + '</DataSourceName>
    <QueryParameters>
      <QueryParameter Name="@UserSIDs"><Value>=Parameters!UserSIDs.Value</Value></QueryParameter>
      <QueryParameter Name="@CollectionID"><Value>=Parameters!CollectionID.Value</Value></QueryParameter>
    </QueryParameters>
    <CommandText>' + (ConvertTo-RdlText $sql) + '
</CommandText></Query>
  <Fields>
    <Field Name="Devices"><DataField>Devices</DataField><rd:TypeName>System.Int32</rd:TypeName></Field>
    <Field Name="NoInventory"><DataField>NoInventory</DataField><rd:TypeName>System.Int32</rd:TypeName></Field>
    <Field Name="NewestInventory"><DataField>NewestInventory</DataField><rd:TypeName>System.DateTime</rd:TypeName></Field>
    <Field Name="MedianAgeDays"><DataField>MedianAgeDays</DataField><rd:TypeName>System.Decimal</rd:TypeName></Field>
  </Fields>
</DataSet>'
}

function Get-RdlFooter {
    # The page footer: how current the hardware inventory is (from the Freshness dataset), then the project and page.
    $devices = 'First(Fields!Devices.Value, "Freshness")'
    $none = 'First(Fields!NoInventory.Value, "Freshness")'
    $expression = '="Hardware inventory: " & IIf(' + $devices + ' = 0, "no devices", IIf(' + $none + ' = ' + $devices +
        ', "none yet from any of the " & Format(' + $devices + ', "#,0") & " devices", "newest " & Format(First(Fields!NewestInventory.Value, "Freshness"), "d") & ", median age " & Format(First(Fields!MedianAgeDays.Value, "Freshness"), "0.#") & " days" & IIf(' +
        $none + ' > 0, ", none yet from " & Format(' + $none + ', "#,0") & " of " & Format(' + $devices + ', "#,0") & " devices", ""))) & "  ' +
        $RdlDot + '  Layer8 reports  ' + $RdlDot + '  github.com/JBoogieman/layer8-reports  ' + $RdlDot + '  page " & Globals!PageNumber & " of " & Globals!TotalPages'
    '<PageFooter><Height>0.3in</Height><PrintOnFirstPage>true</PrintOnFirstPage><PrintOnLastPage>true</PrintOnLastPage><ReportItems><Textbox Name="Footer"><Top>0.05in</Top><Left>0in</Left><Height>0.2in</Height><Width>10.5in</Width><CanGrow>true</CanGrow><KeepTogether>true</KeepTogether><Paragraphs><Paragraph><TextRuns><TextRun><Value>' +
    (ConvertTo-RdlText $expression) + '</Value><Style><FontFamily>Segoe UI</FontFamily><FontSize>7pt</FontSize><Color>' + $RdlColor.Grey +
    '</Color></Style></TextRun></TextRuns><Style></Style></Paragraph></Paragraphs><Style><VerticalAlign>Middle</VerticalAlign><PaddingLeft>0pt</PaddingLeft><PaddingRight>3pt</PaddingRight><PaddingTop>2pt</PaddingTop><PaddingBottom>2pt</PaddingBottom><Border><Style>None</Style></Border></Style></Textbox></ReportItems><Style /></PageFooter>'
}

function New-RdlParameter([string]$Name, [ValidateSet('String', 'Integer', 'Boolean')][string]$Type, [string]$Default, [string]$Prompt) {
    # A report parameter the reader sets, for New-RdlReport's -Parameters.
    '<ReportParameter Name="' + $Name + '"><DataType>' + $Type + '</DataType>
  <DefaultValue><Values><Value>' + (ConvertTo-RdlText $Default) + '</Value></Values></DefaultValue>
  <Prompt>' + (ConvertTo-RdlText $Prompt) + '</Prompt></ReportParameter>'
}

function New-RdlReport {
    <#
    Writes the .rdl: the shared parts around the report's own datasets and body. Body is the report items in order
    (title, subtitle, tiles, note, tables), and BodyHeight the height down to the last table's foot. ReportId is the
    report's own GUID: keep it the same from build to build. Parameters are any the report adds (New-RdlParameter),
    placed between the collection and "Show every device".
    #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Description, [Parameter(Mandatory)][string[]]$DataSets,
          [Parameter(Mandatory)][string]$Body, [Parameter(Mandatory)][string]$BodyHeight, [Parameter(Mandatory)][guid]$ReportId,
          [string[]]$Parameters = @())
    $rdl = '<?xml version="1.0" encoding="utf-8"?>
<Report xmlns="http://schemas.microsoft.com/sqlserver/reporting/2008/01/reportdefinition" xmlns:rd="http://schemas.microsoft.com/SQLServer/reporting/reportdesigner">
<Description>' + (ConvertTo-RdlText $Description) + '</Description>
<Author>layer8-reports</Author>
<AutoRefresh>0</AutoRefresh>
<DataSources><DataSource Name="' + $DataSourceName + '"><DataSourceReference>{5C6358F2-4BB6-4a1b-A16E-8D96795D8602}</DataSourceReference></DataSource></DataSources>
<DataSets>
<DataSet Name="AdminID">
  <Query><DataSourceName>' + $DataSourceName + '</DataSourceName>
    <QueryParameters><QueryParameter Name="@UserTokenSIDs"><Value>=Parameters!UserTokenSIDs.Value</Value></QueryParameter></QueryParameters>
    <CommandText>select dbo.fn_rbac_GetAdminIDsfromUserSIDs(@UserTokenSIDs) as UserSIDs</CommandText></Query>
  <Fields><Field Name="UserSIDs"><DataField>UserSIDs</DataField><rd:TypeName>System.String</rd:TypeName></Field></Fields>
</DataSet>
<DataSet Name="Collections">
  <Query><DataSourceName>' + $DataSourceName + '</DataSourceName>
    <QueryParameters><QueryParameter Name="@UserSIDs"><Value>=Parameters!UserSIDs.Value</Value></QueryParameter></QueryParameters>
    <CommandText>SELECT CollectionID, Name FROM fn_rbac_Collection(@UserSIDs) WHERE CollectionType = 2 ORDER BY Name</CommandText></Query>
  <Fields>
    <Field Name="CollectionID"><DataField>CollectionID</DataField><rd:TypeName>System.String</rd:TypeName></Field>
    <Field Name="Name"><DataField>Name</DataField><rd:TypeName>System.String</rd:TypeName></Field>
    <Field Name="LocCollectionName"><Value>=SrsResources.Localization.GetDBString(Fields!Name.Value, User!Language, "SMS_Collection-Name")</Value></Field>
  </Fields>
</DataSet>
' + ($DataSets -join "`n") + '
' + (Get-RdlFreshnessDataSet) + '
</DataSets>
<Body><ReportItems>' + $Body + '</ReportItems><Height>' + $BodyHeight + '</Height><Style><BackgroundColor>' + $RdlColor.White + '</BackgroundColor></Style></Body>
<ReportParameters>
<ReportParameter Name="UserTokenSIDs"><DataType>String</DataType>
  <DefaultValue><Values><Value>=SrsResources.UserIdentity.GetUserSIDs(User!UserID)</Value></Values></DefaultValue>
  <Prompt>UserTokenSIDs</Prompt><Hidden>true</Hidden></ReportParameter>
<ReportParameter Name="UserSIDs"><DataType>String</DataType>
  <DefaultValue><DataSetReference><DataSetName>AdminID</DataSetName><ValueField>UserSIDs</ValueField></DataSetReference></DefaultValue>
  <Prompt>UserSIDs</Prompt><Hidden>true</Hidden></ReportParameter>
<ReportParameter Name="CollectionID"><DataType>String</DataType>
  <DefaultValue><Values><Value>SMS00001</Value></Values></DefaultValue>
  <Prompt>Collection</Prompt>
  <ValidValues><DataSetReference><DataSetName>Collections</DataSetName><ValueField>CollectionID</ValueField><LabelField>LocCollectionName</LabelField></DataSetReference></ValidValues></ReportParameter>
' + $(if ($Parameters) { ($Parameters -join "`n") + "`n" }) + '<ReportParameter Name="ShowDevices"><DataType>Boolean</DataType>
  <DefaultValue><Values><Value>false</Value></Values></DefaultValue>
  <Prompt>Show every device</Prompt></ReportParameter>
</ReportParameters>
<Width>10.5in</Width>
<Page>
  ' + (Get-RdlFooter) + '
  <PageHeight>8.5in</PageHeight><PageWidth>11in</PageWidth>
  <LeftMargin>0.25in</LeftMargin><RightMargin>0.25in</RightMargin><TopMargin>0.3in</TopMargin><BottomMargin>0.3in</BottomMargin>
  <Style />
</Page>
<Language>=User!Language</Language>
<CodeModules><CodeModule>SrsResources, culture=neutral</CodeModule></CodeModules>
<ConsumeContainerWhitespace>true</ConsumeContainerWhitespace>
<rd:ReportID>' + $ReportId.ToString() + '</rd:ReportID>
<rd:ReportUnitType>Inch</rd:ReportUnitType>
</Report>
'
    $rdl = [regex]::Replace($rdl, "(?<!`r)`n", "`r`n")
    [IO.File]::WriteAllText($Path, $rdl, (New-Object System.Text.UTF8Encoding $false))
    "Wrote $Path ($((Get-Item $Path).Length) bytes)"
}

Export-ModuleMember -Function New-Rdl*, ConvertTo-RdlText -Variable RdlColor, RdlDot, RdlBullet
