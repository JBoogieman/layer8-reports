<#
.SYNOPSIS
    Runs one of the reports' queries against a ConfigMgr site database and shows the rows, without SSRS.

.DESCRIPTION
    For trying a report's SQL before importing the report, or checking what it will show. Connects with your own
    Windows account, which needs read access to the site database. Changes nothing: the queries only read.

    The report fills in @UserSIDs with the reader's identity so ConfigMgr's security scopes apply. Here it's
    'disabled', which shows every device your account can read in the database.

.PARAMETER Path
    The .sql file to run.

.PARAMETER Server
    The site database server, as SQL Server knows it (add \INSTANCE for a named instance).

.PARAMETER Database
    The site database: CM_ followed by the site code.

.PARAMETER Parameters
    Values for the query's parameters, without the @. Defaults: CollectionID SMS00001 (All Systems), IdleDays 30.

.PARAMETER OutFile
    Save the rows to this CSV file instead of showing them.

.EXAMPLE
    .\tools\Invoke-ReportQuery.ps1 .\reports\FleetByModel\FleetByModel.sql -Server CM01 -Database CM_LAB
.EXAMPLE
    .\tools\Invoke-ReportQuery.ps1 .\reports\FleetByModel\FleetByModel.sql -Server CM01 -Database CM_LAB -Parameters @{ CollectionID = 'LAB00014' }
#>
param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Server,
    [Parameter(Mandatory)][string]$Database,
    [hashtable]$Parameters = @{},
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'

$values = @{ UserSIDs = 'disabled'; CollectionID = 'SMS00001'; IdleDays = 30 }
foreach ($name in $Parameters.Keys) { $values[$name] = $Parameters[$name] }

$sql = Get-Content -Path $Path -Raw
$connection = New-Object System.Data.SqlClient.SqlConnection "Server=$Server;Database=$Database;Integrated Security=True;Application Name=layer8-reports"
try {
    $command = $connection.CreateCommand()
    $command.CommandText = $sql
    $command.CommandTimeout = 300
    # Only the parameters the query uses: SQL Server rejects ones it doesn't declare.
    foreach ($name in $values.Keys) {
        if ($sql -match "@$name\b") { [void]$command.Parameters.AddWithValue("@$name", $values[$name]) }
    }
    $table = New-Object System.Data.DataTable
    $connection.Open()
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $reader = $command.ExecuteReader()
    $table.Load($reader)
    $watch.Stop()
} finally {
    $connection.Dispose()
}

$rows = @($table.Rows | Select-Object -Property ($table.Columns | ForEach-Object { $_.ColumnName }))
if ($OutFile) {
    $folder = Split-Path -Parent $OutFile
    if ($folder -and -not (Test-Path $folder)) { New-Item -ItemType Directory -Path $folder | Out-Null }
    $rows | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8
    "$($rows.Count) row(s) in $([int]$watch.Elapsed.TotalMilliseconds) ms, saved to $OutFile"
} else {
    $rows
    "$($rows.Count) row(s) in $([int]$watch.Elapsed.TotalMilliseconds) ms"
}
