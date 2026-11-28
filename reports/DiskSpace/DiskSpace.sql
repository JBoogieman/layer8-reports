-- Layer8 Disk space: one row per device in a collection, with how much is free on C:, which way it's heading, and when
-- it'll be low at that rate. The report groups the rows by model family and generation.
--
-- Parameters
--   @UserSIDs      The reader's, so the report shows only what their ConfigMgr security scopes allow. The report
--                  fills it in; 'disabled' skips the check (for testing outside SSRS).
--   @CollectionID  The collection to report on, e.g. SMS00001 (All Systems).
--   @LowGB         Free space on C: below which a device is low, in GB. 10 by default.
--   @Days          How much history the trend uses, and how far ahead it looks: a device that gets below @LowGB
--                  within @Days days at its recent rate is running out. 30 by default.
--
-- The trend is the least-squares slope through every free-space figure hardware inventory recorded for C: in the last
-- @Days days. Inventory history keeps each change with when inventory recorded it (TimeStamp, in local time), until
-- Delete Aged Inventory History removes it (90 days by default). A trend needs at least 3 figures spread over a week;
-- with fewer, a device has no trend, and is only low or not.
--
-- History is read from v_HS_LOGICAL_DISK for the collection's members, which the reader's scopes already limit.
-- fn_rbac_HS_LOGICAL_DISK would scope it too, but with 'disabled' it returns current data instead of history, so the
-- trend couldn't be tested outside the report.

WITH Members AS (
    SELECT ResourceID FROM fn_rbac_FullCollectionMembership(@UserSIDs) WHERE CollectionID = @CollectionID
),
Points AS (
    -- Free space on C: over the window: each change inventory recorded, the value held when the window began (the
    -- last change before it), and now. x is days since the window began.
    SELECT ResourceID, FreeGB, DATEDIFF(minute, DATEADD(day, -@Days, GETDATE()), At) / 1440.0 AS x
    FROM (
        SELECT h.ResourceID, h.TimeStamp AS At, h.FreeSpace0 / 1024.0 AS FreeGB
        FROM v_HS_LOGICAL_DISK h
        WHERE h.DeviceID0 = 'C:' AND h.TimeStamp >= DATEADD(day, -@Days, GETDATE())
          AND h.ResourceID IN (SELECT ResourceID FROM Members)
        UNION ALL
        SELECT b.ResourceID, DATEADD(day, -@Days, GETDATE()), b.FreeSpace0 / 1024.0
        FROM (SELECT ResourceID, FreeSpace0, ROW_NUMBER() OVER (PARTITION BY ResourceID ORDER BY TimeStamp DESC) AS Latest
              FROM v_HS_LOGICAL_DISK
              WHERE DeviceID0 = 'C:' AND TimeStamp < DATEADD(day, -@Days, GETDATE())
                AND ResourceID IN (SELECT ResourceID FROM Members)) b
        WHERE b.Latest = 1
        UNION ALL
        SELECT d.ResourceID, d.TimeStamp, d.FreeSpace0 / 1024.0
        FROM fn_rbac_GS_LOGICAL_DISK(@UserSIDs) d
        WHERE d.DeviceID0 = 'C:' AND d.TimeStamp >= DATEADD(day, -@Days, GETDATE())
    ) p
),
Trend AS (
    -- GB per day, negative when C: is filling up. Only with 3 or more figures spread over at least a week.
    SELECT ResourceID,
        CASE WHEN COUNT(*) >= 3 AND MAX(x) - MIN(x) >= 7
             THEN (COUNT(*) * SUM(x * FreeGB) - SUM(x) * SUM(FreeGB)) / NULLIF(COUNT(*) * SUM(x * x) - SUM(x) * SUM(x), 0)
        END AS GBPerDay
    FROM Points
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
        CASE
            WHEN cs.Manufacturer0 LIKE 'LENOVO%' AND NULLIF(LTRIM(RTRIM(csp.Version0)), '') IS NOT NULL
                 AND csp.Version0 NOT LIKE 'Lenovo' THEN LTRIM(RTRIM(csp.Version0))
            ELSE ISNULL(NULLIF(LTRIM(RTRIM(cs.Model0)), ''), 'Unknown')
        END AS Model,
        NULLIF(LTRIM(RTRIM(cu.TopConsoleUser0)), '') AS TopUser,
        disk.Size0 / 1024.0 AS SizeGB,
        disk.FreeSpace0 / 1024.0 AS FreeGB,
        disk.TimeStamp AS InventoryAt,                 -- when inventory recorded it, in local time
        t.GBPerDay
    FROM fn_rbac_FullCollectionMembership(@UserSIDs) fcm
    JOIN fn_rbac_R_System(@UserSIDs) sys ON sys.ResourceID = fcm.ResourceID
    LEFT JOIN fn_rbac_GS_COMPUTER_SYSTEM(@UserSIDs) cs           ON cs.ResourceID = sys.ResourceID
    LEFT JOIN fn_rbac_GS_COMPUTER_SYSTEM_PRODUCT(@UserSIDs) csp  ON csp.ResourceID = sys.ResourceID
    LEFT JOIN fn_rbac_GS_LOGICAL_DISK(@UserSIDs) disk            ON disk.ResourceID = sys.ResourceID AND disk.DeviceID0 = 'C:'
    LEFT JOIN fn_rbac_GS_SYSTEM_CONSOLE_USAGE(@UserSIDs) cu      ON cu.ResourceID = sys.ResourceID
    LEFT JOIN Trend t                                            ON t.ResourceID = sys.ResourceID
    WHERE fcm.CollectionID = @CollectionID
      AND ISNULL(sys.Obsolete0, 0) = 0
      AND sys.Client0 = 1
),
Devices AS (
    SELECT
        b.*,
        -- Family and generation exactly as Fleet by model splits them, so the reports agree.
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
        -- Days until it's below @LowGB at its recent rate, for a device that isn't there yet and is filling up.
        CASE WHEN b.FreeGB >= @LowGB AND b.GBPerDay < 0 THEN (b.FreeGB - @LowGB) / -b.GBPerDay END AS DaysToLow
    FROM Base b
),
Classified AS (
    SELECT d.*,
        CASE
            WHEN d.FreeGB IS NULL      THEN 'No data'
            WHEN d.FreeGB < @LowGB     THEN 'Low'
            WHEN d.DaysToLow <= @Days  THEN 'Running out'
            ELSE 'OK'
        END AS Status
    FROM Devices d
)
SELECT
    c.Device,
    c.Manufacturer,
    c.Family,
    c.Generation,
    c.Model,
    c.TopUser,
    CAST(c.SizeGB AS decimal(9, 1)) AS SizeGB,
    CAST(c.FreeGB AS decimal(9, 1)) AS FreeGB,
    CAST(c.FreeGB / NULLIF(c.SizeGB, 0) AS decimal(5, 3)) AS FreeShare,
    CAST(c.GBPerDay * 7 AS decimal(9, 1)) AS GBPerWeek,
    CAST(FLOOR(c.DaysToLow) AS int) AS DaysToLow,
    c.InventoryAt,
    c.Status,
    CASE WHEN c.Status = 'Low' THEN 1 ELSE 0 END AS IsLow,
    CASE WHEN c.Status = 'Running out' THEN 1 ELSE 0 END AS IsRunningOut,
    CASE WHEN c.Status IN ('Low', 'Running out') THEN 1 ELSE 0 END AS IsAtRisk,
    CASE WHEN c.Status = 'No data' THEN 1 ELSE 0 END AS IsNoData,
    -- Medians, because the report server has none: for the generation, the family, and the whole collection.
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY c.FreeGB) OVER (PARTITION BY c.Family, c.Generation) AS decimal(9, 1)) AS GenMedianFreeGB,
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY c.FreeGB) OVER (PARTITION BY c.Family) AS decimal(9, 1)) AS FamilyMedianFreeGB,
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY c.FreeGB) OVER () AS decimal(9, 1)) AS AllMedianFreeGB
FROM Classified c
ORDER BY c.Family, c.Generation, c.Device;
