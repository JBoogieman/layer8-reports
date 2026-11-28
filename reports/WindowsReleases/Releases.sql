-- Layer8 Windows releases: the choices for the report's Target release. First "What Windows offers" (0, the default),
-- then each Windows client release in the collection, newest first. The release list is the same as in
-- WindowsReleases.sql: keep the two in step.
--
-- Parameters
--   @UserSIDs      The reader's, so only what their ConfigMgr security scopes allow is listed. 'disabled' skips the
--                  check (for testing outside SSRS).
--   @CollectionID  The report's collection.

WITH Names AS (
    -- Each release's build, branch (0: general availability, 2: LTSC) and name. Add a line when a release comes out.
    SELECT Build, Branch, Release FROM (VALUES
        (28000, 0, 'Windows 11 26H1'),
        (26300, 0, 'Windows 11 26H2'),
        (26200, 0, 'Windows 11 25H2'),
        (26100, 0, 'Windows 11 24H2'),
        (26100, 2, 'Windows 11 LTSC 2024'),
        (22631, 0, 'Windows 11 23H2'),
        (22621, 0, 'Windows 11 22H2'),
        (22000, 0, 'Windows 11 21H2'),
        (19045, 0, 'Windows 10 22H2'),
        (19044, 0, 'Windows 10 21H2'),
        (19044, 2, 'Windows 10 LTSC 2021'),
        (19043, 0, 'Windows 10 21H1'),
        (19042, 0, 'Windows 10 20H2'),
        (17763, 2, 'Windows 10 LTSC 2019')
    ) r (Build, Branch, Release)
),
Builds AS (
    -- Client releases only: servers and long-term servicing (LTSC) devices are never measured against a target.
    SELECT DISTINCT TRY_CAST(os.BuildNumber0 AS int) AS Build
    FROM fn_rbac_FullCollectionMembership(@UserSIDs) fcm
    JOIN fn_rbac_R_System(@UserSIDs) sys                ON sys.ResourceID = fcm.ResourceID
    JOIN fn_rbac_GS_OPERATING_SYSTEM(@UserSIDs) os      ON os.ResourceID = sys.ResourceID
    WHERE fcm.CollectionID = @CollectionID
      AND ISNULL(sys.Obsolete0, 0) = 0
      AND sys.Client0 = 1
      AND os.Caption0 NOT LIKE '%Server%'
      AND ISNULL(sys.OSBranch01, 0) <> 2
      AND TRY_CAST(os.BuildNumber0 AS int) IS NOT NULL
)
SELECT Build, Label
FROM (
    SELECT 0 AS Build, 'What Windows offers (the default)' AS Label, 0 AS Choice
    UNION ALL
    SELECT b.Build,
        ISNULL((SELECT TOP 1 nm.Release FROM Names nm WHERE nm.Build = b.Build AND nm.Branch = 0),
               CASE WHEN b.Build >= 22000 THEN 'Windows 11' ELSE 'Windows 10' END) + ' (build ' + CAST(b.Build AS varchar(10)) + ')',
        1
    FROM Builds b
) r
ORDER BY Choice, Build DESC;
