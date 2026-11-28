-- Layer8 data freshness: how current the hardware inventory behind a report is, for the report's page footer. Every
-- report runs this for its own collection, so the footer counts the same devices the report does.
--
-- Parameters
--   @UserSIDs      The reader's, so only devices their ConfigMgr security scopes allow are counted. The report fills
--                  it in; 'disabled' skips the check (for testing outside SSRS).
--   @CollectionID  The report's collection.
--
-- One row: the devices, how many have never sent hardware inventory, the newest inventory, and the median age of the
-- devices' latest inventory (half the devices sent theirs more recently than that). The median is worked out here
-- because the report server has none.

WITH Devices AS (
    SELECT ch.LastHW                                     -- the last hardware inventory, in UTC
    FROM fn_rbac_FullCollectionMembership(@UserSIDs) fcm
    JOIN fn_rbac_R_System(@UserSIDs) sys                 ON sys.ResourceID = fcm.ResourceID
    LEFT JOIN fn_rbac_CH_ClientSummary(@UserSIDs) ch     ON ch.ResourceID = sys.ResourceID
    WHERE fcm.CollectionID = @CollectionID
      AND ISNULL(sys.Obsolete0, 0) = 0
      AND sys.Client0 = 1
),
Aged AS (
    SELECT LastHW,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY DATEDIFF(minute, LastHW, GETUTCDATE()) / 1440.0) OVER () AS MedianAgeDays
    FROM Devices
)
SELECT
    COUNT(*) AS Devices,
    ISNULL(SUM(CASE WHEN LastHW IS NULL THEN 1 ELSE 0 END), 0) AS NoInventory,
    -- Shown in the site database server's time zone, like the reports' other times.
    DATEADD(minute, DATEDIFF(minute, GETUTCDATE(), GETDATE()), MAX(LastHW)) AS NewestInventory,
    CAST(MAX(MedianAgeDays) AS decimal(9, 1)) AS MedianAgeDays
FROM Aged;
