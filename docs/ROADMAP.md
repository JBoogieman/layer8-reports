# Roadmap

The reports to build next, in order. Each one uses only what ConfigMgr already collects, or the Layer8 collector: no new databases, servers or purchases.

Done so far: Fleet by model, Boot times and crashes, Hardware lifecycle.

## How each item was checked

Before an item went on this list, its data was checked in a two-VM lab site with ConfigMgr's Default Client Settings. Two questions: does the site's hardware inventory collect the class (`v_InventoryReportClass` joined to `v_GroupMap`), and do devices actually have rows in its view? An item whose data isn't there says so, and sits at the end until it is. Checked on November 27, 2026.

## Data sources

Each item is tagged with where its data comes from.

| Tag | Where the data comes from | In the lab |
|---|---|---|
| Inventory | Hardware inventory classes in Default Client Settings (`v_GS_` views) | Every class used below is on and has data |
| History | Hardware inventory history (`v_HS_` views), kept until Delete Aged Inventory History removes it (90 days by default) | Yes |
| Discovery | System discovery (`v_R_System`) | Yes |
| Client health | The client's own status reports (`v_CH_ClientSummary`) | Yes |
| Servicing | The site's Windows servicing data (`v_WindowsServicingStates`) | Yes |
| BitLocker management | ConfigMgr's BitLocker management agent (`v_GS_BITLOCKER_DETAILS`) | The class is on, but no device has data: no BitLocker management policy is deployed |
| Endpoint Protection | The Endpoint Protection agent (`v_GS_AntimalwareHealthStatus`) | No data: client settings don't manage Endpoint Protection |
| Collector | [collector/Layer8-BootAndCrash.ps1](../collector/Layer8-BootAndCrash.ps1) | Yes |

## Backlog

### 0. README section and screenshot for Hardware lifecycle

**Data:** Inventory, Discovery, Client health. **Lab:** yes.

The report is done. It needs a section in the README and a screenshot, like the other two.

### 1. Fix the UTC date bugs

**Data:** Client health. **Lab:** yes.

ConfigMgr stores a client's last contact (`LastActiveTime`) in UTC. Fleet by model's Not seen check compares it with the database server's local time, so it's off by the server's UTC offset. Hardware lifecycle's Last active column shows the UTC date, so a device last seen in the evening shows tomorrow's date. Both are small. Fixing them first keeps the new reports from copying the mistake.

### 2. Data-freshness footer on every report

**Data:** Client health (last hardware inventory), Inventory (Workstation Status). **Lab:** yes.

A line at the foot of each report: the newest hardware inventory the site has for the collection, and how many of its devices have none. A reader can then see how current the figures are. This goes before the new reports so each one ships with it.

### 3. Windows 11 readiness by model

**Data:** Inventory: Upgrade Experience Indicators, TPM, TPM Status, Firmware, Processor, Memory, Logical Disk. **Lab:** yes.

For each model and device, Windows' own upgrade compatibility verdict and its reason (from the compatibility appraiser on the device), next to the raw requirements: TPM 2.0 ready, UEFI with Secure Boot, CPU, RAM and the size of C:. Shows which models block the upgrade, and why.

In the lab, one VM is Red for Memory (3 GB) and the other is Green, so a real failure can be tested.

### 4. Windows builds and feature-update spread

**Data:** Discovery, Inventory (Operating System), Servicing. **Lab:** yes, but a single build.

Devices per Windows release and build, by collection and model, with devices on releases older than the collection's newest, and releases near or past the end of servicing.

Both lab VMs run the same build, so testing a real spread needs a VM on an older release.

### 5. Disk space trouble

**Data:** Inventory (Logical Disk), History (Logical Disk). **Lab:** yes.

Devices low on free space on C:, by model, and which are heading that way, from the inventory history.

The lab has 18 history snapshots across both VMs, spread over three weeks.

### 6. BIOS age and version spread by model

**Data:** Inventory (PC BIOS: version and release date). **Lab:** yes, but one virtual BIOS.

For each model: how many BIOS versions are in use, how old the installed firmware is, and the devices behind the newest version seen on that model. "Newest" means newest seen in the site, since no vendor catalog is used.

Both lab VMs run the same virtual firmware, so the lab can't show a spread.

### 7. Client health

**Data:** Client health, Discovery. **Lab:** yes, both healthy.

Devices that have stopped reporting, and devices whose hardware inventory, policy requests or heartbeat discovery are stale, with the result of the client's own health check.

Both lab clients pass, so a failing case needs one VM's client stopped for a while.

### 8. BitLocker status by collection

**Data:** BitLocker management. **Lab:** no data yet.

Protection status, encryption method and compliance, per device and model. Never recovery keys: the report reads no table that holds them.

The class is on in the lab, but it stays empty until a BitLocker management policy is deployed. Building this waits on that.

### 9. Defender health

**Data:** Endpoint Protection. **Lab:** no data yet.

Devices whose antimalware signatures are out of date, or whose real-time protection is off.

The lab's client settings don't manage Endpoint Protection, so there's nothing to report yet. It needs that turned on, or Defender's own status class (`MSFT_MpComputerStatus`) added to hardware inventory.
