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
- **4. Windows releases** (November 27, 2026). The release each device runs against a target (by default the release Windows offers most of the devices), and for each device that's behind, Windows' own verdict on why. Two things changed from the plan. Support status is left out: the site's servicing data is stale, and still showed Windows 11 21H2 as current. And release names come from a list in the query, because the servicing data's names are in a view the report server's account can't read. The first report built with tools/RdlBuilder.psm1.
- **5. Disk space** (November 28, 2026). Low and running out on C:, by model, with when each device will be low at its recent rate. The rate is a best-fit line through every free-space figure inventory history recorded, so one clean-up or one big download doesn't swing it. The history is read from v_HS_LOGICAL_DISK for the collection's members: fn_rbac_HS_LOGICAL_DISK returns current data, not history, when tested outside the report.
- **6. BIOS versions** (November 28, 2026). The versions each model runs, newest first, how old the installed firmware is, and the devices behind the newest seen on their model, judged by release date because version strings don't compare across vendors.
- **7. Client health** (November 28, 2026). Clients that are inactive, failing their own health check, or stale on inventory, policy or heartbeat, judged by the site's own client status settings rather than new thresholds, with what's wrong counted, most common first.

## Dropped

- **3. Windows 11 readiness by model** (dropped November 27, 2026). Most fleets are on Windows 11 already. Windows also checks each device against the newest release, so for a device that's up to date, "ready for the next release" says nothing. The useful part, Windows' own verdict on hardware the newest release won't accept, moves into item 4.
