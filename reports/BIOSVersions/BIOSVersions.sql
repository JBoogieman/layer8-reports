-- Layer8 BIOS versions: one row per device in a collection, with its BIOS version and when that version was released,
-- the newest seen on its exact model, and whether it's behind. The report groups the rows by model family and
-- generation, and lists each model's versions.
--
-- Parameters
--   @UserSIDs      The reader's, so the report shows only what their ConfigMgr security scopes allow. The report
--                  fills it in; 'disabled' skips the check (for testing outside SSRS).
--   @CollectionID  The collection to report on, e.g. SMS00001 (All Systems).
--
-- Newest means the newest seen in the site on that exact model, by release date: vendors' version strings don't
-- compare, and no vendor catalog is used. A model whose every device is behind the vendor's latest still shows as on
-- the newest. The release date is the installed firmware's, so it moves with every BIOS update; it says nothing about
-- when the device was bought.

WITH Base AS (
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
        NULLIF(LTRIM(RTRIM(bios.SMBIOSBIOSVersion0)), '') AS BiosVersion,
        CAST(bios.ReleaseDate0 AS date) AS BiosDate,
        ch.LastActiveTime AS LastActiveUtc            -- UTC
    FROM fn_rbac_FullCollectionMembership(@UserSIDs) fcm
    JOIN fn_rbac_R_System(@UserSIDs) sys ON sys.ResourceID = fcm.ResourceID
    LEFT JOIN fn_rbac_GS_COMPUTER_SYSTEM(@UserSIDs) cs           ON cs.ResourceID = sys.ResourceID
    LEFT JOIN fn_rbac_GS_COMPUTER_SYSTEM_PRODUCT(@UserSIDs) csp  ON csp.ResourceID = sys.ResourceID
    LEFT JOIN fn_rbac_GS_PC_BIOS(@UserSIDs) bios                 ON bios.ResourceID = sys.ResourceID
    LEFT JOIN fn_rbac_CH_ClientSummary(@UserSIDs) ch             ON ch.ResourceID = sys.ResourceID
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
        -- The newest BIOS seen on this exact model, and its version.
        MAX(b.BiosDate) OVER (PARTITION BY b.Model) AS NewestDate,
        FIRST_VALUE(b.BiosVersion) OVER (PARTITION BY b.Model ORDER BY CASE WHEN b.BiosDate IS NULL THEN 1 ELSE 0 END, b.BiosDate DESC, b.BiosVersion DESC
                                         ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS NewestVersion,
        CAST(DATEDIFF(day, b.BiosDate, GETDATE()) / 365.25 AS decimal(4, 1)) AS AgeYears
    FROM Base b
)
SELECT
    d.Device,
    d.Manufacturer,
    d.Family,
    d.Generation,
    d.Model,
    d.BiosVersion,
    d.BiosDate,
    d.AgeYears,
    d.NewestVersion,
    d.NewestDate,
    CASE WHEN d.BiosDate IS NULL THEN 'No data' WHEN d.BiosDate < d.NewestDate THEN 'Behind' ELSE 'Newest' END AS Status,
    CASE WHEN d.BiosDate IS NOT NULL AND d.BiosDate = d.NewestDate THEN 1 ELSE 0 END AS IsNewest,
    CASE WHEN d.BiosDate < d.NewestDate THEN 1 ELSE 0 END AS IsBehind,
    CASE WHEN d.BiosDate IS NULL THEN 1 ELSE 0 END AS IsNoData,
    -- Sorts a model's versions newest first: the model, then the release date counted down.
    d.Model + '|' + ISNULL(RIGHT('0000000' + CAST(99999999 - CAST(CONVERT(char(8), d.BiosDate, 112) AS int) AS varchar(8)), 8), '99999999') AS VersionSortKey,
    -- UTC in the site; shown in the site database server's time zone, like the other reports' times.
    DATEADD(minute, DATEDIFF(minute, GETUTCDATE(), GETDATE()), d.LastActiveUtc) AS LastActive,
    -- Medians, because the report server has none: for the generation, the family, and the whole collection.
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY d.AgeYears) OVER (PARTITION BY d.Family, d.Generation) AS decimal(4, 1)) AS GenMedianAge,
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY d.AgeYears) OVER (PARTITION BY d.Family) AS decimal(4, 1)) AS FamilyMedianAge,
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY d.AgeYears) OVER () AS decimal(4, 1)) AS AllMedianAge
FROM Devices d
ORDER BY d.Family, d.Generation, d.Device;
