-- Layer8 Windows releases: one row per device in a collection, with the Windows release it runs, whether that's the
-- target release, and for a device that's behind, why: Windows' own check says whether its hardware stops the update.
-- The report groups the rows by release, and by model family and generation.
--
-- Parameters
--   @UserSIDs      The reader's, so the report shows only what their ConfigMgr security scopes allow. The report
--                  fills it in; 'disabled' skips the check (for testing outside SSRS).
--   @CollectionID  The collection to report on, e.g. SMS00001 (All Systems).
--   @TargetBuild   The target release's build number, e.g. 26300. 0 (the default) means the release Windows offers
--                  most of the collection's devices, from its own upgrade check; with no check results, the newest
--                  release in the collection.
--
-- A device is on target, behind (an older release), newer, LTSC (a long-term servicing release, which doesn't take
-- feature updates, so it's never behind), a server (left out of the counts), or has no data.
--
-- Release names are listed below. The site's Windows servicing data has them too, but in a view the report server's
-- account can't read (vSMS_WindowsServicingLocalizedNames), and its support states are stale: in the lab it still
-- showed Windows 11 21H2 as current. A release missing from the list shows as "Windows 11 (build N)".
--
-- Why behind: Windows' compatibility check (the appraiser) runs on each device and writes a verdict for the newest
-- release it offers, which hardware inventory collects (Upgrade Experience Indicators). Red means hardware stops the
-- update, with codes saying what; Green means nothing's in the way. Microsoft documents neither the other verdicts
-- (Yellow, Orange) nor the codes, so the codes are matched by keyword and unknown ones are shown as they are. The
-- check runs against the newest release Windows offers, which can be newer than the target.

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
Verdicts AS (
    -- Each device's verdict for the newest release it was checked against. The UNV key holds no verdict.
    SELECT ResourceID,
        LTRIM(RTRIM(UpgExU0)) AS Verdict,
        Version0 AS CheckedCode,
        NULLIF(LTRIM(RTRIM(Reason0)), '') AS ReasonCodes,
        ROW_NUMBER() OVER (PARTITION BY ResourceID ORDER BY RIGHT(Version0, 4) DESC, Version0 DESC) AS Newest
    FROM fn_rbac_GS_UPGRADE_EXPERIENCE_INDICATORS(@UserSIDs)
    WHERE Version0 <> 'UNV' AND NULLIF(LTRIM(RTRIM(UpgExU0)), '') IS NOT NULL
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
        os.Caption0 AS OSCaption,
        TRY_CAST(os.BuildNumber0 AS int) AS BuildNo,
        ISNULL(sys.OSBranch01, 0) AS Branch,          -- 0: general availability, 2: long-term servicing (LTSC)
        os.InstallDate0 AS OnItSince,                 -- the device's local time; every feature update resets it
        ch.LastActiveTime AS LastActiveUtc,           -- UTC
        v.Verdict,
        v.CheckedCode,
        v.ReasonCodes
    FROM fn_rbac_FullCollectionMembership(@UserSIDs) fcm
    JOIN fn_rbac_R_System(@UserSIDs) sys ON sys.ResourceID = fcm.ResourceID
    LEFT JOIN fn_rbac_GS_COMPUTER_SYSTEM(@UserSIDs) cs           ON cs.ResourceID = sys.ResourceID
    LEFT JOIN fn_rbac_GS_COMPUTER_SYSTEM_PRODUCT(@UserSIDs) csp  ON csp.ResourceID = sys.ResourceID
    LEFT JOIN fn_rbac_GS_OPERATING_SYSTEM(@UserSIDs) os          ON os.ResourceID = sys.ResourceID
    LEFT JOIN fn_rbac_CH_ClientSummary(@UserSIDs) ch             ON ch.ResourceID = sys.ResourceID
    LEFT JOIN Verdicts v                                         ON v.ResourceID = sys.ResourceID AND v.Newest = 1
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
        CASE WHEN b.OSCaption LIKE '%Server%' THEN 1 ELSE 0 END AS IsServer,
        -- The release's name: from the list for its build and branch, else from the caption or the build.
        COALESCE(
            n.Release,
            CASE WHEN b.OSCaption LIKE '%Server%' THEN REPLACE(b.OSCaption, 'Microsoft ', '') END,
            CASE WHEN b.BuildNo >= 22000 THEN 'Windows 11 (build ' WHEN b.BuildNo IS NOT NULL THEN 'Windows 10 (build ' END + CAST(b.BuildNo AS varchar(10)) + ')',
            'Unknown') AS Release,
        -- The release Windows checked it against: "26H2" from the appraiser's key "GE26H2".
        CASE WHEN b.CheckedCode LIKE '%[0-9][0-9]H[12]' THEN RIGHT(b.CheckedCode, 4) END AS CheckedVersion,
        -- The reason codes without the appraiser's trailing comma, and without "None".
        NULLIF(REPLACE(CASE WHEN b.ReasonCodes LIKE '%,' THEN LEFT(b.ReasonCodes, LEN(b.ReasonCodes) - 1) ELSE b.ReasonCodes END, 'None', ''), '') AS Reasons
    FROM Base b
    OUTER APPLY (SELECT TOP 1 nm.Release FROM Names nm WHERE nm.Build = b.BuildNo
                 ORDER BY CASE WHEN nm.Branch = b.Branch THEN 0 ELSE 1 END, nm.Branch) n
),
Offered AS (
    -- The release Windows offers most of the collection's devices.
    SELECT TOP 1 CheckedVersion FROM Devices
    WHERE CheckedVersion IS NOT NULL AND IsServer = 0
    GROUP BY CheckedVersion
    ORDER BY COUNT(*) DESC, CheckedVersion DESC
),
Target AS (
    -- The reader's target, else what Windows offers most of the devices, else the newest release in the collection.
    SELECT COALESCE(
        NULLIF(@TargetBuild, 0),
        (SELECT MAX(nm.Build) FROM Names nm JOIN Offered o ON nm.Release = 'Windows 11 ' + o.CheckedVersion WHERE nm.Branch = 0),
        (SELECT MAX(BuildNo) FROM Devices WHERE IsServer = 0 AND Branch <> 2)) AS Build
),
Classified AS (
    SELECT
        d.*,
        t.Build AS TargetBuildNo,
        CASE
            WHEN d.IsServer = 1        THEN 'Server'
            WHEN d.Branch = 2          THEN 'LTSC'
            WHEN d.BuildNo IS NULL     THEN 'No data'
            WHEN d.BuildNo = t.Build   THEN 'On target'
            WHEN d.BuildNo > t.Build   THEN 'Newer'
            ELSE 'Behind'
        END AS Status
    FROM Devices d
    CROSS JOIN Target t
)
SELECT
    c.Device,
    c.Manufacturer,
    c.Family,
    c.Generation,
    c.Model,
    c.Release,
    c.BuildNo,
    c.Status,
    CASE WHEN c.Status = 'On target' THEN 1 ELSE 0 END AS IsOnTarget,
    CASE WHEN c.Status = 'Behind' THEN 1 ELSE 0 END AS IsBehind,
    CASE WHEN c.Status = 'Behind' AND c.Verdict = 'Red' THEN 1 ELSE 0 END AS IsBlocked,
    CASE WHEN c.IsServer = 0 AND c.OSCaption LIKE '%Windows 10%' THEN 1 ELSE 0 END AS OnWindows10,
    c.OnItSince,
    -- UTC in the site; shown in the site database server's time zone, like the other reports' times.
    DATEADD(minute, DATEDIFF(minute, GETUTCDATE(), GETDATE()), c.LastActiveUtc) AS LastActive,
    -- Why a device that's behind is behind. A code is matched by its stem (CpuFms and CpuCores are both the processor).
    CASE
        WHEN c.Status <> 'Behind'  THEN NULL
        WHEN c.Verdict IS NULL     THEN 'Not checked'
        WHEN c.Verdict = 'Green'   THEN 'Nothing in the way'
        WHEN c.Verdict = 'Red'     THEN 'Hardware: ' + ISNULL(STUFF(
              CASE WHEN c.Reasons LIKE '%Cpu%' OR c.Reasons LIKE '%Processor%'                    THEN ', Processor'            ELSE '' END
            + CASE WHEN c.Reasons LIKE '%Tpm%'                                                     THEN ', TPM'                  ELSE '' END
            + CASE WHEN c.Reasons LIKE '%Uefi%' OR c.Reasons LIKE '%SecureBoot%'                   THEN ', UEFI and Secure Boot' ELSE '' END
            + CASE WHEN c.Reasons LIKE '%Memory%'                                                  THEN ', Memory'               ELSE '' END
            + CASE WHEN c.Reasons LIKE '%Storage%' OR c.Reasons LIKE '%DriveSize%' OR c.Reasons LIKE '%Disk%' THEN ', Disk space' ELSE '' END,
            1, 2, ''), ISNULL(c.Reasons, 'not stated'))
        ELSE 'Check first (' + c.Verdict + ')'
    END AS WhyBehind,
    c.CheckedVersion,
    c.Reasons AS ReasonCodes,
    -- The target, named, for the subtitle.
    COALESCE((SELECT TOP 1 nm.Release FROM Names nm WHERE nm.Build = c.TargetBuildNo ORDER BY nm.Branch), 'Windows (build ' + CAST(c.TargetBuildNo AS varchar(10)) + ')') AS TargetRelease,
    c.TargetBuildNo
FROM Classified c
ORDER BY c.Family, c.Generation, c.Device;
