-- Layer8 Boot times and crashes, the crash list: every unexpected stop in the period on a device in the collection,
-- newest first, with the blue screen code and its name when it was a blue screen.
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
)
SELECT
    d.Device,
    d.Model,
    ISNULL(d.BiosVersion, 'Unknown') AS BiosVersion,
    -- The collector's times are UTC; this shows them in the site database server's time zone.
    DATEADD(minute, DATEDIFF(minute, GETUTCDATE(), GETDATE()), c.DetectedAt0) AS DetectedAt,
    CASE WHEN c.Kind0 = 'Bugcheck' THEN 'Blue screen' ELSE c.Kind0 END AS Kind,
    c.BugcheckCode0 AS BugcheckCode,
    -- The names of the stop codes seen most often on desktops and laptops; others show the code alone.
    CASE c.BugcheckCode0
        WHEN '0x0000000A' THEN 'IRQL_NOT_LESS_OR_EQUAL'
        WHEN '0x00000019' THEN 'BAD_POOL_HEADER'
        WHEN '0x0000001A' THEN 'MEMORY_MANAGEMENT'
        WHEN '0x0000001E' THEN 'KMODE_EXCEPTION_NOT_HANDLED'
        WHEN '0x0000003B' THEN 'SYSTEM_SERVICE_EXCEPTION'
        WHEN '0x00000050' THEN 'PAGE_FAULT_IN_NONPAGED_AREA'
        WHEN '0x0000007A' THEN 'KERNEL_DATA_INPAGE_ERROR'
        WHEN '0x0000007E' THEN 'SYSTEM_THREAD_EXCEPTION_NOT_HANDLED'
        WHEN '0x0000009C' THEN 'MACHINE_CHECK_EXCEPTION'
        WHEN '0x0000009F' THEN 'DRIVER_POWER_STATE_FAILURE'
        WHEN '0x000000C2' THEN 'BAD_POOL_CALLER'
        WHEN '0x000000D1' THEN 'DRIVER_IRQL_NOT_LESS_OR_EQUAL'
        WHEN '0x000000E2' THEN 'MANUALLY_INITIATED_CRASH'
        WHEN '0x000000ED' THEN 'UNMOUNTABLE_BOOT_VOLUME'
        WHEN '0x000000EF' THEN 'CRITICAL_PROCESS_DIED'
        WHEN '0x000000F4' THEN 'CRITICAL_OBJECT_TERMINATION'
        WHEN '0x00000101' THEN 'CLOCK_WATCHDOG_TIMEOUT'
        WHEN '0x00000116' THEN 'VIDEO_TDR_FAILURE'
        WHEN '0x00000119' THEN 'VIDEO_SCHEDULER_INTERNAL_ERROR'
        WHEN '0x00000124' THEN 'WHEA_UNCORRECTABLE_ERROR'
        WHEN '0x00000133' THEN 'DPC_WATCHDOG_VIOLATION'
        WHEN '0x00000139' THEN 'KERNEL_SECURITY_CHECK_FAILURE'
        WHEN '0x00000154' THEN 'UNEXPECTED_STORE_EXCEPTION'
        WHEN '0x0000015F' THEN 'CONNECTED_STANDBY_WATCHDOG_TIMEOUT_LIVEDUMP'
    END AS BugcheckName,
    c.BugcheckParameters0 AS BugcheckParameters,
    c.DumpFile0 AS DumpFile
FROM Devices d
JOIN v_GS_LAYER8_CRASH c ON c.ResourceID = d.ResourceID
WHERE c.DetectedAt0 >= DATEADD(day, -@Days, GETUTCDATE())   -- the collector's times are UTC
ORDER BY c.DetectedAt0 DESC, d.Device;
