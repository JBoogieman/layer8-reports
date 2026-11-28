-- Layer8 Fleet by Model: one row per device in a collection, with the model's real name, how much the device is
-- used, and its hardware. The report groups these rows by model family and generation.
--
-- Parameters
--   @UserSIDs      The reader's, so the report shows only what their ConfigMgr security scopes allow. The report
--                  fills it in; 'disabled' skips the check (for testing outside SSRS).
--   @CollectionID  The collection to report on, e.g. SMS00001 (All Systems).
--   @IdleDays      How far back counts as recent, for "In use", "Unused" and "Not seen". 30 by default.
--
-- Only default hardware inventory classes are used, so it works on any site without changing client settings.

WITH Console AS (
    -- The most recent interactive sign-in at the device by anyone, from the security log (System Console User).
    SELECT ResourceID, MAX(LastConsoleUse0) AS LastConsoleUse
    FROM fn_rbac_GS_SYSTEM_CONSOLE_USER(@UserSIDs)
    GROUP BY ResourceID
),
Base AS (
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
        CASE WHEN cs.Manufacturer0 LIKE 'LENOVO%' THEN LEFT(cs.Model0, 4) END AS MachineType,
        ISNULL(NULLIF(LTRIM(RTRIM(csp.IdentifyingNumber0)), ''), bios.SerialNumber0) AS Serial,
        bios.SMBIOSBIOSVersion0 AS BiosVersion,
        bios.ReleaseDate0 AS BiosDate,
        os.Caption0 AS OSCaption,
        os.BuildNumber0 AS Build,
        CAST(ROUND(mem.TotalPhysicalMemory0 / 1048576.0, 0) AS int) AS RamGB,
        CAST(disk.FreeSpace0 / 1024.0 AS decimal(9, 1)) AS CFreeGB,
        CAST(disk.Size0 / 1024.0 AS decimal(9, 1)) AS CSizeGB,
        sys.Creation_Date0 AS FirstSeen,
        ch.LastActiveTime AS LastActive,     -- UTC, so it's compared with GETUTCDATE()
        con.LastConsoleUse AS LastSignIn,    -- the device's local time, so it's compared with GETDATE()
        cu.TopConsoleUser0 AS TopUser,
        ch.LastHW AS LastInventory,
        -- The site's own flag misses some hypervisors (Proxmox/KVM, for one), so the hardware's name counts too.
        CASE WHEN sys.Is_Virtual_Machine0 = 1
                  OR cs.Manufacturer0 LIKE 'QEMU%' OR cs.Manufacturer0 LIKE 'VMware%' OR cs.Manufacturer0 LIKE 'Xen%'
                  OR cs.Manufacturer0 LIKE 'innotek%' OR cs.Manufacturer0 LIKE 'Parallels%'
                  OR cs.Model0 LIKE 'Virtual Machine%' OR cs.Model0 LIKE 'VirtualBox%' OR cs.Model0 LIKE 'KVM%'
             THEN 'Yes' ELSE 'No' END AS Virtual,
        CASE WHEN cu.ResourceID IS NULL THEN 0 ELSE 1 END AS HasConsoleUsage
    FROM fn_rbac_FullCollectionMembership(@UserSIDs) fcm
    JOIN fn_rbac_R_System(@UserSIDs) sys ON sys.ResourceID = fcm.ResourceID
    LEFT JOIN fn_rbac_GS_COMPUTER_SYSTEM(@UserSIDs) cs           ON cs.ResourceID = sys.ResourceID
    LEFT JOIN fn_rbac_GS_COMPUTER_SYSTEM_PRODUCT(@UserSIDs) csp  ON csp.ResourceID = sys.ResourceID
    LEFT JOIN fn_rbac_GS_PC_BIOS(@UserSIDs) bios                 ON bios.ResourceID = sys.ResourceID
    LEFT JOIN fn_rbac_GS_OPERATING_SYSTEM(@UserSIDs) os          ON os.ResourceID = sys.ResourceID
    LEFT JOIN fn_rbac_GS_X86_PC_MEMORY(@UserSIDs) mem            ON mem.ResourceID = sys.ResourceID
    LEFT JOIN fn_rbac_GS_LOGICAL_DISK(@UserSIDs) disk            ON disk.ResourceID = sys.ResourceID AND disk.DeviceID0 = 'C:'
    LEFT JOIN fn_rbac_GS_SYSTEM_CONSOLE_USAGE(@UserSIDs) cu      ON cu.ResourceID = sys.ResourceID
    LEFT JOIN Console con                                        ON con.ResourceID = sys.ResourceID
    LEFT JOIN fn_rbac_CH_ClientSummary(@UserSIDs) ch             ON ch.ResourceID = sys.ResourceID
    WHERE fcm.CollectionID = @CollectionID
      AND ISNULL(sys.Obsolete0, 0) = 0
      AND sys.Client0 = 1
)
SELECT
    Device,
    Manufacturer,
    -- Family and generation, so generations of one model sit side by side: Lenovo "ThinkPad L14 Gen 3",
    -- HP "EliteBook 840 G8 Notebook PC". Others keep the whole model as the family.
    CASE
        WHEN Manufacturer = 'Lenovo' AND PATINDEX('% Gen [0-9]%', Model) > 0 THEN LEFT(Model, PATINDEX('% Gen [0-9]%', Model) - 1)
        WHEN Manufacturer = 'HP' AND PATINDEX('% G[0-9]%', Model) > 0       THEN LEFT(Model, PATINDEX('% G[0-9]%', Model) - 1)
        ELSE Model
    END AS Family,
    CASE
        WHEN Manufacturer = 'Lenovo' AND PATINDEX('% Gen [0-9]%', Model) > 0
            THEN LTRIM(SUBSTRING(Model, PATINDEX('% Gen [0-9]%', Model) + 1, 6))
        WHEN Manufacturer = 'HP' AND PATINDEX('% G[0-9]%', Model) > 0
            THEN LEFT(LTRIM(SUBSTRING(Model, PATINDEX('% G[0-9]%', Model) + 1, 4)) + ' ', CHARINDEX(' ', LTRIM(SUBSTRING(Model, PATINDEX('% G[0-9]%', Model) + 1, 4)) + ' ') - 1)
        ELSE ''
    END AS Generation,
    Model,
    MachineType,
    Serial,
    -- Windows by name and release, not just the build number.
    CASE
        WHEN OSCaption LIKE '%Server%' THEN REPLACE(OSCaption, 'Microsoft ', '')
        WHEN Build = '26300' THEN 'Windows 11 26H2'
        WHEN Build = '26200' THEN 'Windows 11 25H2'
        WHEN Build = '26100' THEN 'Windows 11 24H2'
        WHEN Build = '22631' THEN 'Windows 11 23H2'
        WHEN Build = '22621' THEN 'Windows 11 22H2'
        WHEN Build = '22000' THEN 'Windows 11 21H2'
        WHEN Build = '19045' THEN 'Windows 10 22H2'
        WHEN Build = '19044' THEN 'Windows 10 21H2'
        WHEN Build IS NULL   THEN 'Unknown'
        WHEN TRY_CAST(Build AS int) >= 22000 THEN 'Windows 11 (build ' + Build + ')'
        ELSE 'Windows 10 (build ' + Build + ')'
    END AS Windows,
    Build,
    RamGB,
    CFreeGB,
    CSizeGB,
    BiosVersion,
    BiosDate,
    -- In use: talked to the site and someone signed in at it recently. Unused: on and talking to the site, but nobody
    -- signed in (the one to reclaim). Not seen: hasn't talked to the site recently (in a drawer, or gone).
    CASE
        WHEN LastActive IS NULL OR LastActive < DATEADD(day, -@IdleDays, GETUTCDATE()) THEN 'Not seen'
        WHEN LastSignIn >= DATEADD(day, -@IdleDays, GETDATE())                       THEN 'In use'
        WHEN HasConsoleUsage = 0                                                     THEN 'Unknown'
        ELSE 'Unused'
    END AS Status,
    LastSignIn,
    TopUser,
    LastActive,
    FirstSeen,
    LastInventory,
    Virtual
FROM Base
ORDER BY Family, Generation, Device;
