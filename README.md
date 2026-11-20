# layer8-reports

ConfigMgr reports on how your Windows fleet treats the people using it: model generations, idle hardware, app usage, boot times, crashes and hardware health. A companion to [Layer8](https://github.com/JBoogieman/layer8).

The reports run in your own ConfigMgr report server, next to Microsoft's. They respect each reader's security scopes the same way Microsoft's reports do.

## Reports

### Fleet by model

Devices in a collection, grouped by model family and generation, so ThinkPad L14 Gen 1 through Gen 6 sit side by side. For each family, each model and each device:

- **In use:** someone signed in at it recently.
- **Unused:** it's on and checking in with the site, but nobody signs in. These are the ones to reclaim.
- **Not seen:** no contact with the site recently. It's in a drawer, or gone.
- **Unknown:** the site has no sign-in data for it.

You choose what counts as recent: 30 days by default. Beside the counts: the Windows release (by name, like 24H2), RAM, the lowest free space on C:, BIOS versions (a model running three different BIOS versions says so), last sign-in, top user and serial number. A chart shows the largest families by status.

Lenovo reports a machine type code (21C5...) as the model. The report uses the name people know instead ("ThinkPad L14 Gen 3"), from the same inventory.

Uses only ConfigMgr's default hardware inventory, so it works on any site without changing client settings. Its query is in [reports/FleetByModel/FleetByModel.sql](reports/FleetByModel/FleetByModel.sql).

## Install

You need a reporting services point (if Microsoft's reports show under **Monitoring > Reporting > Reports** in the console, you have one) and permission to publish reports on that report server. From a copy of this repository:

```powershell
.\tools\Install-Reports.ps1 -ReportServer http://<your report server>/ReportServer
```

The report server's address is in Report Server Configuration Manager, under **Web Service URL**. The script puts the reports in a Layer8 folder next to Microsoft's and connects them to the site's own data source. The console shows them under **Monitoring > Reporting > Reports**, in the category **Layer8**. Run it again after an update to replace them.

## Try a query without the report server

```powershell
.\tools\Invoke-ReportQuery.ps1 .\reports\FleetByModel\FleetByModel.sql -Server <site database server> -Database CM_<site code>
```

Shows the rows the report would use, read with your own Windows account. Add `-OutFile <file>.csv` to save them, or `-Parameters @{ CollectionID = '<collection ID>' }` for another collection (All Systems by default).

## Coming next

**Boot times and crashes:** how long devices take to start and how often they blue-screen, by model and BIOS version. Its collector, [collector/Layer8-BootAndCrash.ps1](collector/Layer8-BootAndCrash.ps1), reads each device's event logs into WMI for hardware inventory to pick up.

## License

[MIT](LICENSE)
