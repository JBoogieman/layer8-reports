<#
.SYNOPSIS
    Puts the layer8-reports reports on a ConfigMgr report server, in a Layer8 folder next to Microsoft's reports.

.DESCRIPTION
    Uploads each .rdl under reports\ to ConfigMgr_<site code>\Layer8 on the report server, and points it at the site's
    own shared data source: the one Microsoft's reports use, which the reporting services point keeps up to date.
    The console then shows the reports under Monitoring > Reporting > Reports, in the category Layer8, and they
    respect each reader's ConfigMgr security scopes the same way Microsoft's do.

    Running it again replaces the reports with the files as they are now. Nothing else on the server changes.

    Your account needs to be allowed to publish reports in the ConfigMgr folder (Content Manager on the report
    server). Uses the report server's SOAP web service (ReportService2010), which every SQL Server Reporting
    Services and Power BI Report Server version since 2008 R2 has.

.PARAMETER ReportServer
    The report server's web service URL, as Report Server Configuration Manager shows it under Web Service URL.

.PARAMETER SiteCode
    Only needed when the report server holds reports for more than one site.

.PARAMETER Folder
    The folder under ConfigMgr_<site code>. Layer8 by default; the console shows it as the report category.

.PARAMETER Name
    Only these reports, by file name without .rdl. All of them by default.

.EXAMPLE
    .\tools\Install-Reports.ps1 -ReportServer http://CM01/ReportServer
#>
param(
    [Parameter(Mandatory)][string]$ReportServer,
    [string]$SiteCode,
    [string]$Folder = 'Layer8',
    [string[]]$Name
)

$ErrorActionPreference = 'Stop'

# The site's shared data source. Every ConfigMgr site gives it this name; Microsoft's reports use it too.
$SiteDataSource = '{5C6358F2-4BB6-4a1b-A16E-8D96795D8602}'

$proxy = New-WebServiceProxy -Uri ($ReportServer.TrimEnd('/') + '/ReportService2010.asmx?wsdl') -UseDefaultCredential
$types = $proxy.GetType().Namespace

# The ConfigMgr_<site code> folder the reporting services point made. (Reinstalling the role renames an old one
# to ConfigMgr_XXX.OLD.0, which this skips.)
$roots = @($proxy.ListChildren('/', $false) | Where-Object { $_.TypeName -eq 'Folder' -and $_.Name -match '^ConfigMgr_[A-Za-z0-9]{3}$' })
if ($SiteCode) { $roots = @($roots | Where-Object { $_.Name -eq "ConfigMgr_$SiteCode" }) }
if ($roots.Count -eq 0) { throw "No ConfigMgr_<site code> folder on $ReportServer. Is the reporting services point installed?" }
if ($roots.Count -gt 1) { throw "Reports for more than one site on $ReportServer ($(($roots | ForEach-Object { $_.Name }) -join ', ')). Choose one with -SiteCode." }
$root = $roots[0].Path

$dataSource = $proxy.ListChildren($root, $false) | Where-Object { $_.TypeName -eq 'DataSource' -and $_.Name -eq $SiteDataSource }
if (-not $dataSource) { throw "The site's shared data source isn't in $root." }

$target = "$root/$Folder"
if (-not ($proxy.ListChildren($root, $false) | Where-Object { $_.TypeName -eq 'Folder' -and $_.Name -eq $Folder })) {
    [void]$proxy.CreateFolder($Folder, $root, $null)
    "Created $target"
}

$files = @(Get-ChildItem -Path (Join-Path $PSScriptRoot '..\reports') -Filter *.rdl -Recurse)
if ($Name) { $files = @($files | Where-Object { $Name -contains $_.BaseName }) }
if ($files.Count -eq 0) { throw 'No reports to publish.' }

foreach ($file in $files) {
    # FleetByModel.rdl is published as "Fleet by model", the way Microsoft names its reports, and
    # Windows11Readiness.rdl as "Windows 11 readiness".
    $words = @([regex]::Split($file.BaseName, '(?<=[a-z])(?=[A-Z0-9])|(?<=[0-9])(?=[A-Z])'))
    $title = (@($words[0]) + @($words | Select-Object -Skip 1 | ForEach-Object { $_.ToLower() })) -join ' '

    $definition = New-Object System.Xml.XmlDocument
    $definition.Load($file.FullName)
    $description = New-Object "$types.Property"
    $description.Name = 'Description'
    $description.Value = [string]$definition.Report.Description

    $warnings = $null
    [void]$proxy.CreateCatalogItem('Report', $title, $target, $true, [IO.File]::ReadAllBytes($file.FullName), @($description), [ref]$warnings)

    # Point the report's data source at the site's shared one.
    $sources = foreach ($name in @($definition.Report.DataSources.DataSource | ForEach-Object { $_.Name })) {
        $reference = New-Object "$types.DataSourceReference"
        $reference.Reference = $dataSource.Path
        $source = New-Object "$types.DataSource"
        $source.Name = $name
        $source.Item = $reference
        $source
    }
    $proxy.SetItemDataSources("$target/$title", @($sources))

    "Published $target/$title"
    # Until the line above ran, the report's data source pointed nowhere; the server warns about that on upload.
    foreach ($warning in @($warnings | Where-Object { $_ -and $_.Code -ne 'rsDataSourceReferenceNotPublished' })) {
        "  Warning: $($warning.Message)"
    }
}
