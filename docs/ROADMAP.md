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

### 4. Windows builds and feature-update spread

**Data:** Discovery, Inventory (Operating System, Upgrade Experience Indicators), Servicing. **Lab:** yes, but a single build.

Devices per Windows release and build, by collection and model, with devices on releases older than the collection's newest, and releases near or past the end of servicing. For a device that's behind, Windows' own verdict on whether it can take the newest release says why it's stuck: the compatibility check Windows runs on each device names the hardware that stops it (processor, TPM, UEFI and Secure Boot, memory, disk space).

Both lab VMs run the same build, the newest, so testing a spread, and a device stuck behind it, needs a VM on an older release.

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

## Done

Items keep their numbers once done.

- **0. README section and screenshot for Hardware lifecycle** (November 27, 2026).
- **1. The UTC date bugs** (November 27, 2026). Every date is now compared with the clock it was stored in. A client's last contact, record creation dates and the collector's boot and crash times are UTC. Last sign-in is the device's own local time. UTC times are shown in the database server's time zone.
- **2. Data-freshness footer** (November 27, 2026). Every report's page footer gives three things for its collection: the newest hardware inventory, the median age of the devices' latest inventory, and how many devices haven't sent any. The median says how current the figures are, where the newest alone wouldn't. All reports share one query, [reports/DataFreshness.sql](../reports/DataFreshness.sql).

## Dropped

- **3. Windows 11 readiness by model** (dropped November 27, 2026). Most fleets are on Windows 11 already. Windows also checks each device against the newest release, so for a device that's up to date, "ready for the next release" says nothing. The useful part, Windows' own verdict on hardware the newest release won't accept, moves into item 4.
