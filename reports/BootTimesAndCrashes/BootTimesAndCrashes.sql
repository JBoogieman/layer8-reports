-- Layer8 Boot times and crashes: one row per device in a collection, with its model and BIOS version, how long it
-- takes to start, and how often it stopped unexpectedly. The report groups the rows by model and BIOS version.
--
-- Parameters
--   @UserSIDs      The reader's, so the report shows only what their ConfigMgr security scopes allow. The report
--                  fills it in; 'disabled' skips the check (for testing outside SSRS).
--   @CollectionID  The collection to report on, e.g. SMS00001 (All Systems).
--   @Days          How far back to count boots and crashes. 30 by default, which is as far back as the collector
--                  keeps them unless it runs with -Days.
--
-- Needs the Layer8 boot and crash collector (collector\Layer8-BootAndCrash.ps1) running on the devices, and its
-- classes Layer8_Boot and Layer8_Crash in hardware inventory. Their views are read directly: the device list
-- above them already limits the rows to devices the reader may see.
--
-- Medians and 90th percentiles are worked out here, per device, per model and per model and BIOS version, because
-- the report server has no median. Every device row carries its model's figures; the report shows them once a group.

WITH Devices AS (
    -- The collection's devices with a client, as Fleet by model finds them, and the names it gives their models.
    SELECT
        sys.ResourceID,
        sys.Name0 AS Device,
        CASE
            WHEN cs.Manufacturer0 LIKE 'LENOVO%'                                 THEN 'Lenovo'
            WHEN cs.Manufacturer0 LIKE 'Dell%'                                   THEN 'Dell'
            WHEN cs.Manufacturer0 LIKE 'HP%' OR cs.Manufacturer0 LIKE 'Hewlett%' THEN 'HP'
            WHEN cs.Manufacturer0 LIKE 'Microsoft%'                              THEN 'Microsoft'
            WHEN cs.Manufacturer0 LIKE 'VMware%'                                 THEN 'VMware'
            ELSE ISNULL(NULLIF(LTRIM(RTRIM(cs.Manufacturer0)), ''), 'Unknown')
        END AS Manufacturer,
        -- Lenovo's Model is a machine type code (21C5...); the name people know ("ThinkPad L14 Gen 3") is the
        -- system product's Version. Everyone else puts the name in Model.
        CASE
            WHEN cs.Manufacturer0 LIKE 'LENOVO%' AND NULLIF(LTRIM(RTRIM(csp.Version0)), '') IS NOT NULL
                 AND csp.Version0 NOT LIKE 'Lenovo' THEN LTRIM(RTRIM(csp.Version0))
            ELSE ISNULL(NULLIF(LTRIM(RTRIM(cs.Model0)), ''), 'Unknown')
        END AS Model,
        bios.SMBIOSBIOSVersion0 AS BiosVersion,
        -- Windows by name and release, not just the build number.
        CASE
            WHEN os.Caption0 LIKE '%Server%' THEN REPLACE(os.Caption0, 'Microsoft ', '')
            WHEN os.BuildNumber0 = '26300' THEN 'Windows 11 26H2'
            WHEN os.BuildNumber0 = '26200' THEN 'Windows 11 25H2'
            WHEN os.BuildNumber0 = '26100' THEN 'Windows 11 24H2'
            WHEN os.BuildNumber0 = '22631' THEN 'Windows 11 23H2'
            WHEN os.BuildNumber0 = '22621' THEN 'Windows 11 22H2'
            WHEN os.BuildNumber0 = '22000' THEN 'Windows 11 21H2'
            WHEN os.BuildNumber0 = '19045' THEN 'Windows 10 22H2'
            WHEN os.BuildNumber0 = '19044' THEN 'Windows 10 21H2'
            WHEN os.BuildNumber0 IS NULL   THEN 'Unknown'
            WHEN TRY_CAST(os.BuildNumber0 AS int) >= 22000 THEN 'Windows 11 (build ' + os.BuildNumber0 + ')'
            ELSE 'Windows 10 (build ' + os.BuildNumber0 + ')'
        END AS Windows,
        os.BuildNumber0 AS Build
    FROM fn_rbac_FullCollectionMembership(@UserSIDs) fcm
    JOIN fn_rbac_R_System(@UserSIDs) sys ON sys.ResourceID = fcm.ResourceID
    LEFT JOIN fn_rbac_GS_COMPUTER_SYSTEM(@UserSIDs) cs           ON cs.ResourceID = sys.ResourceID
    LEFT JOIN fn_rbac_GS_COMPUTER_SYSTEM_PRODUCT(@UserSIDs) csp  ON csp.ResourceID = sys.ResourceID
    LEFT JOIN fn_rbac_GS_PC_BIOS(@UserSIDs) bios                 ON bios.ResourceID = sys.ResourceID
    LEFT JOIN fn_rbac_GS_OPERATING_SYSTEM(@UserSIDs) os          ON os.ResourceID = sys.ResourceID
    WHERE fcm.CollectionID = @CollectionID
      AND ISNULL(sys.Obsolete0, 0) = 0
      AND sys.Client0 = 1
),
Boots AS (
    SELECT d.ResourceID, d.Model, d.BiosVersion, b.BootStart0 AS BootStart, b.BootTimeMs0 / 1000.0 AS BootSeconds
    FROM Devices d
    JOIN v_GS_LAYER8_BOOT b ON b.ResourceID = d.ResourceID
    WHERE b.BootStart0 >= DATEADD(day, -@Days, GETUTCDATE())   -- the collector's times are UTC
),
Timed AS (
    -- Boot time is Windows' own figure (Diagnostics-Performance event 100): from power on until the desktop is ready
    -- and startup has settled. Windows doesn't time every boot, so these are the boots it did.
    SELECT ResourceID, BootSeconds,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY BootSeconds) OVER (PARTITION BY ResourceID)          AS DeviceMedian,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY BootSeconds) OVER (PARTITION BY Model)               AS ModelMedian,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY BootSeconds) OVER (PARTITION BY Model)               AS ModelP90,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY BootSeconds) OVER (PARTITION BY Model, BiosVersion)  AS BiosMedian,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY BootSeconds) OVER (PARTITION BY Model, BiosVersion)  AS BiosP90,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY BootSeconds) OVER ()                                 AS FleetMedian
    FROM Boots
    WHERE BootSeconds IS NOT NULL
),
TimedByDevice AS (
    SELECT ResourceID, COUNT(*) AS TimedBoots, MAX(DeviceMedian) AS MedianBoot, MAX(BootSeconds) AS SlowestBoot,
        MAX(ModelMedian) AS ModelMedian, MAX(ModelP90) AS ModelP90, MAX(BiosMedian) AS BiosMedian,
        MAX(BiosP90) AS BiosP90, MAX(FleetMedian) AS FleetMedian
    FROM Timed
    GROUP BY ResourceID
),
BootsByDevice AS (
    SELECT ResourceID, COUNT(*) AS Boots, MAX(BootStart) AS LastBoot
    FROM Boots
    GROUP BY ResourceID
),
Crashes AS (
    SELECT c.ResourceID, c.Kind0 AS Kind, c.BugcheckCode0 AS BugcheckCode, c.DetectedAt0 AS DetectedAt
    FROM Devices d
    JOIN v_GS_LAYER8_CRASH c ON c.ResourceID = d.ResourceID
    WHERE c.DetectedAt0 >= DATEADD(day, -@Days, GETUTCDATE())
),
CrashesByDevice AS (
    -- Blue screens, and stops with no blue screen: power lost, a hard reset, or the power button held down.
    SELECT ResourceID,
        SUM(CASE WHEN Kind = 'Bugcheck' THEN 1 ELSE 0 END)  AS BlueScreens,
        SUM(CASE WHEN Kind <> 'Bugcheck' THEN 1 ELSE 0 END) AS PowerLosses,
        MAX(DetectedAt) AS LastCrash
    FROM Crashes
    GROUP BY ResourceID
),
TopCode AS (
    -- Each device's most frequent blue screen code.
    SELECT ResourceID, BugcheckCode,
        ROW_NUMBER() OVER (PARTITION BY ResourceID ORDER BY COUNT(*) DESC, MAX(DetectedAt) DESC) AS Rank
    FROM Crashes
    WHERE Kind = 'Bugcheck' AND BugcheckCode IS NOT NULL
    GROUP BY ResourceID, BugcheckCode
),
Reported AS (
    -- When the site last got the device's boot data: from hardware inventory, after the collector ran.
    SELECT ResourceID, MAX(TimeStamp) AS BootDataFrom
    FROM v_GS_LAYER8_BOOT
    GROUP BY ResourceID
)
SELECT
    d.Device,
    d.Manufacturer,
    d.Model,
    ISNULL(d.BiosVersion, 'Unknown') AS BiosVersion,
    d.Windows,
    CASE WHEN r.ResourceID IS NULL THEN 'No boot data' ELSE 'Reporting' END AS DataStatus,
    ISNULL(bd.Boots, 0) AS Boots,
    ISNULL(td.TimedBoots, 0) AS TimedBoots,
    CAST(td.MedianBoot AS decimal(9, 1)) AS MedianBoot,
    CAST(td.SlowestBoot AS decimal(9, 1)) AS SlowestBoot,
    -- The collector's times are UTC; these show them in the site database server's time zone.
    DATEADD(minute, DATEDIFF(minute, GETUTCDATE(), GETDATE()), bd.LastBoot) AS LastBoot,
    ISNULL(cd.BlueScreens, 0) AS BlueScreens,
    ISNULL(cd.PowerLosses, 0) AS PowerLosses,
    DATEADD(minute, DATEDIFF(minute, GETUTCDATE(), GETDATE()), cd.LastCrash) AS LastCrash,
    tc.BugcheckCode AS TopBugcheck,
    CAST(td.ModelMedian AS decimal(9, 1)) AS ModelMedian,
    CAST(td.ModelP90 AS decimal(9, 1)) AS ModelP90,
    CAST(td.BiosMedian AS decimal(9, 1)) AS BiosMedian,
    CAST(td.BiosP90 AS decimal(9, 1)) AS BiosP90,
    CAST(td.FleetMedian AS decimal(9, 1)) AS FleetMedian,
    r.BootDataFrom
FROM Devices d
LEFT JOIN Reported r         ON r.ResourceID = d.ResourceID
LEFT JOIN BootsByDevice bd   ON bd.ResourceID = d.ResourceID
LEFT JOIN TimedByDevice td   ON td.ResourceID = d.ResourceID
LEFT JOIN CrashesByDevice cd ON cd.ResourceID = d.ResourceID
LEFT JOIN TopCode tc         ON tc.ResourceID = d.ResourceID AND tc.Rank = 1
ORDER BY d.Model, d.BiosVersion, d.Device;
