-- Layer8 Hardware lifecycle: one row per device in a collection, with its age and where it is in its life, and its
-- generation's figures: how many left over the last few months, how many arrived, and how old they are. The report
-- groups the rows by model family and generation.
--
-- Parameters
--   @UserSIDs      The reader's, so the report shows only what their ConfigMgr security scopes allow. The report
--                  fills it in; 'disabled' skips the check (for testing outside SSRS).
--   @CollectionID  The collection to report on, e.g. SMS00001 (All Systems).
--   @IdleDays      How long without contact before a device counts as gone quiet. 30 by default.
--   @WindowDays    How far back to look for devices that left. Set it to the site's Delete Aged Discovery Data
--                  setting (90 by default): a device quiet for longer than that may already be deleted, and a
--                  deleted device can't be counted.
--
-- ConfigMgr deletes devices that stop checking in, so it can't say how many of a generation died over years. What it
-- can say is how many went quiet over the last few months, out of how many there were. That is the rate here.
--
-- A likely replacement: a device that was here when the window began and has gone quiet, and a device that arrived in
-- the window and is still active, with the same top console user. Each old device gets at most one, the new device
-- first seen closest to when the old one went quiet, and each new device replaces at most one. Someone with two laptops,
-- or a shared device, can be paired wrongly, so the report calls these likely replacements.
--
-- Group figures are worked out here because the report server has no median. Every device row carries its
-- generation's figures; the report shows them once a group.

WITH Console AS (
    SELECT ResourceID, MAX(LastConsoleUse0) AS LastConsoleUse
    FROM fn_rbac_GS_SYSTEM_CONSOLE_USER(@UserSIDs)
    GROUP BY ResourceID
),
-- A serial number names the hardware; a ConfigMgr record names one life of it in the site. A rebuild can give the same
-- laptop a new record (the old one turns obsolete until site maintenance deletes it), so the earliest record with this
-- serial is a better "first seen" than the current record's.
SerialRecords AS (
    SELECT
        ISNULL(NULLIF(LTRIM(RTRIM(p.IdentifyingNumber0)), ''), b.SerialNumber0) AS Serial,
        r.Creation_Date0
    FROM fn_rbac_GS_PC_BIOS(@UserSIDs) b
    JOIN fn_rbac_R_System(@UserSIDs) r                          ON r.ResourceID = b.ResourceID
    LEFT JOIN fn_rbac_GS_COMPUTER_SYSTEM_PRODUCT(@UserSIDs) p   ON p.ResourceID = b.ResourceID
),
SerialHistory AS (
    SELECT Serial, MIN(Creation_Date0) AS FirstSeenEver, COUNT(*) AS Records
    FROM SerialRecords
    -- Placeholder serials some vendors and hypervisors ship would lump unrelated devices together.
    WHERE Serial IS NOT NULL
      AND Serial NOT IN ('0', 'None', 'Default string', 'To be filled by O.E.M.', 'System Serial Number', 'Not Specified')
    GROUP BY Serial
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
        CASE
            WHEN cs.Manufacturer0 LIKE 'LENOVO%' AND NULLIF(LTRIM(RTRIM(csp.Version0)), '') IS NOT NULL
                 AND csp.Version0 NOT LIKE 'Lenovo' THEN LTRIM(RTRIM(csp.Version0))
            ELSE ISNULL(NULLIF(LTRIM(RTRIM(cs.Model0)), ''), 'Unknown')
        END AS Model,
        ISNULL(NULLIF(LTRIM(RTRIM(csp.IdentifyingNumber0)), ''), bios.SerialNumber0) AS Serial,
        sys.Creation_Date0 AS FirstSeen,     -- this record's creation: resets if a rebuild makes a new record
        os.InstallDate0 AS OSInstalled,      -- resets at every reimage
        bios.SMBIOSBIOSVersion0 AS BiosVersion,
        bios.ReleaseDate0 AS BiosDate,       -- the installed firmware's date: moves with every BIOS update
        ch.LastActiveTime AS LastActive,     -- UTC, so it's compared with GETUTCDATE()
        con.LastConsoleUse AS LastSignIn,
        NULLIF(LTRIM(RTRIM(cu.TopConsoleUser0)), '') AS TopUser,
        CASE WHEN cu.ResourceID IS NULL THEN 0 ELSE 1 END AS HasConsoleUsage
    FROM fn_rbac_FullCollectionMembership(@UserSIDs) fcm
    JOIN fn_rbac_R_System(@UserSIDs) sys ON sys.ResourceID = fcm.ResourceID
    LEFT JOIN fn_rbac_GS_COMPUTER_SYSTEM(@UserSIDs) cs           ON cs.ResourceID = sys.ResourceID
    LEFT JOIN fn_rbac_GS_COMPUTER_SYSTEM_PRODUCT(@UserSIDs) csp  ON csp.ResourceID = sys.ResourceID
    LEFT JOIN fn_rbac_GS_PC_BIOS(@UserSIDs) bios                 ON bios.ResourceID = sys.ResourceID
    LEFT JOIN fn_rbac_GS_OPERATING_SYSTEM(@UserSIDs) os          ON os.ResourceID = sys.ResourceID
    LEFT JOIN fn_rbac_GS_SYSTEM_CONSOLE_USAGE(@UserSIDs) cu      ON cu.ResourceID = sys.ResourceID
    LEFT JOIN Console con                                        ON con.ResourceID = sys.ResourceID
    LEFT JOIN fn_rbac_CH_ClientSummary(@UserSIDs) ch             ON ch.ResourceID = sys.ResourceID
    WHERE fcm.CollectionID = @CollectionID
      AND ISNULL(sys.Obsolete0, 0) = 0
      AND sys.Client0 = 1
),
Devices AS (
    SELECT
        b.*,
        -- Family and generation exactly as Fleet by model splits them, so the two reports agree.
        CASE
            WHEN b.Manufacturer = 'Lenovo' AND PATINDEX('% Gen [0-9]%', b.Model) > 0 THEN LEFT(b.Model, PATINDEX('% Gen [0-9]%', b.Model) - 1)
            WHEN b.Manufacturer = 'HP' AND PATINDEX('% G[0-9]%', b.Model) > 0       THEN LEFT(b.Model, PATINDEX('% G[0-9]%', b.Model) - 1)
            ELSE b.Model
        END AS Family,
        CASE
            WHEN b.Manufacturer = 'Lenovo' AND PATINDEX('% Gen [0-9]%', b.Model) > 0
                THEN LTRIM(SUBSTRING(b.Model, PATINDEX('% Gen [0-9]%', b.Model) + 1, 6))
            WHEN b.Manufacturer = 'HP' AND PATINDEX('% G[0-9]%', b.Model) > 0
                THEN LEFT(LTRIM(SUBSTRING(b.Model, PATINDEX('% G[0-9]%', b.Model) + 1, 4)) + ' ', CHARINDEX(' ', LTRIM(SUBSTRING(b.Model, PATINDEX('% G[0-9]%', b.Model) + 1, 4)) + ' ') - 1)
            ELSE ''
        END AS Generation,
        sh.Records,
        ISNULL(sh.FirstSeenEver, b.FirstSeen) AS FirstSeenEver,
        -- Active: in contact recently. Gone quiet: stopped within the window, so it still counts. Long gone: stopped
        -- before the window; the site still has it (usually because discovery keeps finding it in AD), but it left
        -- too long ago to count fairly against the others.
        CASE
            WHEN b.LastActive IS NULL                                     THEN 'No data'
            WHEN b.LastActive >= DATEADD(day, -@IdleDays, GETUTCDATE())   THEN 'Active'
            WHEN b.LastActive >= DATEADD(day, -@WindowDays, GETUTCDATE()) THEN 'Gone quiet'
            ELSE 'Long gone'
        END AS Lifecycle
    FROM Base b
    LEFT JOIN SerialHistory sh ON sh.Serial = b.Serial
),
Flagged AS (
    SELECT
        d.*,
        -- There at the start of the window: first seen before it, and still in contact when it began.
        CASE WHEN d.FirstSeenEver < DATEADD(day, -@WindowDays, GETDATE()) AND d.Lifecycle IN ('Active', 'Gone quiet')
             THEN 1 ELSE 0 END AS AtStart,
        CASE WHEN d.FirstSeenEver >= DATEADD(day, -@WindowDays, GETDATE()) THEN 1 ELSE 0 END AS Arrived,
        CASE WHEN d.Records > 1 THEN 1 ELSE 0 END AS Rebuilt,
        CAST(DATEDIFF(day, d.FirstSeenEver, GETDATE()) / 365.25 AS decimal(4, 1)) AS AgeYears
    FROM Devices d
),
Counted AS (
    SELECT
        f.*,
        -- Left during the window: there at its start, and has since gone quiet.
        CASE WHEN f.AtStart = 1 AND f.Lifecycle = 'Gone quiet' THEN 1 ELSE 0 END AS Departed
    FROM Flagged f
),
Candidates AS (
    SELECT
        o.ResourceID AS OldID,
        n.ResourceID AS NewID,
        n.Device, n.Model, n.Family, n.Generation,
        ROW_NUMBER() OVER (PARTITION BY o.ResourceID ORDER BY ABS(DATEDIFF(hour, n.FirstSeenEver, o.LastActive)), n.ResourceID) AS ForOld,
        ROW_NUMBER() OVER (PARTITION BY n.ResourceID ORDER BY ABS(DATEDIFF(hour, n.FirstSeenEver, o.LastActive)), o.ResourceID) AS ForNew
    FROM Counted o
    JOIN Counted n ON n.TopUser = o.TopUser AND n.ResourceID <> o.ResourceID
    -- Only devices that were here at the start. A loaner that came and went inside the window would otherwise be the
    -- closest match for the new device and take it, and the laptop it stood in for would show as not replaced.
    WHERE o.Departed = 1
      AND n.Arrived = 1 AND n.Lifecycle = 'Active'
),
Pairs AS (
    SELECT OldID, Device, Model, Family, Generation FROM Candidates WHERE ForOld = 1 AND ForNew = 1
)
SELECT
    c.Device,
    c.Manufacturer,
    c.Family,
    c.Generation,
    c.Model,
    c.Serial,
    c.Records,
    c.FirstSeenEver,
    c.FirstSeen,
    c.OSInstalled,
    c.BiosVersion,
    c.BiosDate,
    c.AgeYears,
    CASE
        WHEN c.LastActive IS NULL OR c.LastActive < DATEADD(day, -@IdleDays, GETUTCDATE()) THEN 'Not seen'
        WHEN c.LastSignIn >= DATEADD(day, -@IdleDays, GETDATE())                      THEN 'In use'
        WHEN c.HasConsoleUsage = 0                                                    THEN 'Unknown'
        ELSE 'Unused'
    END AS Status,
    c.Lifecycle,
    c.LastActive,
    c.TopUser,
    p.Device AS ReplacedBy,
    p.Model AS ReplacedByModel,
    p.Family AS ReplacedByFamily,
    p.Generation AS ReplacedByGeneration,
    c.AtStart,
    c.Departed,
    c.Arrived,
    c.Rebuilt,
    -- The generation's figures, on every one of its rows.
    COUNT(*) OVER (PARTITION BY c.Family, c.Generation)        AS GenDevices,
    SUM(c.AtStart) OVER (PARTITION BY c.Family, c.Generation)  AS GenAtStart,
    SUM(c.Departed) OVER (PARTITION BY c.Family, c.Generation) AS GenDeparted,
    SUM(c.Arrived) OVER (PARTITION BY c.Family, c.Generation)  AS GenArrived,
    SUM(c.Rebuilt) OVER (PARTITION BY c.Family, c.Generation)  AS GenRebuilt,
    SUM(CASE WHEN c.Departed = 1 AND p.OldID IS NOT NULL THEN 1 ELSE 0 END)
        OVER (PARTITION BY c.Family, c.Generation)             AS GenReplaced,
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY c.AgeYears)
        OVER (PARTITION BY c.Family, c.Generation) AS decimal(4, 1)) AS GenMedianAge,
    -- The share that left. A device counts as left once it's been quiet @IdleDays, so the departures seen are the ones
    -- that went quiet between the window's start and @IdleDays ago: (@WindowDays - @IdleDays) days' worth. Per year
    -- scales that span to 365 days.
    CAST(100.0 * SUM(c.Departed) OVER (PARTITION BY c.Family, c.Generation)
        / NULLIF(SUM(c.AtStart) OVER (PARTITION BY c.Family, c.Generation), 0) AS decimal(5, 1)) AS GenDepartedPct,
    CAST(100.0 * SUM(c.Departed) OVER (PARTITION BY c.Family, c.Generation)
        / NULLIF(SUM(c.AtStart) OVER (PARTITION BY c.Family, c.Generation), 0)
        * 365.0 / NULLIF(@WindowDays - @IdleDays, 0) AS decimal(7, 1))                         AS GenDepartedPerYear
FROM Counted c
LEFT JOIN Pairs p ON p.OldID = c.ResourceID
ORDER BY c.Family, c.Generation, c.Device;
