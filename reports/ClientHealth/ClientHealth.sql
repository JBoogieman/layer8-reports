-- Layer8 Client health: one row per device in a collection, with whether its ConfigMgr client is active, passing its
-- own health check, and keeping its inventory, policy requests and heartbeat current. The report groups the rows by
-- model family and generation, and counts what's wrong.
--
-- Parameters
--   @UserSIDs      The reader's, so the report shows only what their ConfigMgr security scopes allow. The report
--                  fills it in; 'disabled' skips the check (for testing outside SSRS).
--   @CollectionID  The collection to report on, e.g. SMS00001 (All Systems).
--
-- Every judgement is the site's own, from its client status summary: active or inactive, and each kind of activity
-- current or stale, by the site's Client Status Settings (7 days each by default); and the client's health check
-- result as the site labels it ("Active/Pass", "Active/Fail"). A device is the first of: no client status, inactive,
-- failing its health check, stale (with what's stale), or healthy.
--
-- The summary's times are UTC and are shown in the site database server's time zone. LastHealthEvaluation is taken to
-- be UTC like the rest of the summary; that one wasn't checked separately.

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
        CASE WHEN ch.ResourceID IS NULL THEN 0 ELSE 1 END AS HasStatus,
        ch.ClientActiveStatus,
        ch.ClientStateDescription AS ClientState,
        ch.IsActiveHW,
        ch.IsActivePolicyRequest,
        ch.IsActiveDDR,
        ch.LastActiveTime,          -- UTC, like the times below
        ch.LastPolicyRequest,
        ch.LastHW,
        ch.LastDDR,
        ch.LastHealthEvaluation
    FROM fn_rbac_FullCollectionMembership(@UserSIDs) fcm
    JOIN fn_rbac_R_System(@UserSIDs) sys ON sys.ResourceID = fcm.ResourceID
    LEFT JOIN fn_rbac_GS_COMPUTER_SYSTEM(@UserSIDs) cs           ON cs.ResourceID = sys.ResourceID
    LEFT JOIN fn_rbac_GS_COMPUTER_SYSTEM_PRODUCT(@UserSIDs) csp  ON csp.ResourceID = sys.ResourceID
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
        CASE WHEN b.IsActiveHW = 0 THEN 1 ELSE 0 END AS InventoryStale,
        CASE WHEN b.IsActivePolicyRequest = 0 THEN 1 ELSE 0 END AS PolicyStale,
        CASE WHEN b.IsActiveDDR = 0 THEN 1 ELSE 0 END AS HeartbeatStale,
        CASE
            WHEN b.HasStatus = 0                         THEN 'No client status'
            WHEN b.ClientActiveStatus = 0                THEN 'Inactive'
            WHEN b.ClientState LIKE '%/Fail%'            THEN 'Failing health check'
            WHEN b.IsActiveHW = 0 OR b.IsActivePolicyRequest = 0 OR b.IsActiveDDR = 0 THEN 'Stale'
            ELSE 'Healthy'
        END AS Status
    FROM Base b
)
SELECT
    d.Device,
    d.Manufacturer,
    d.Family,
    d.Generation,
    d.Model,
    d.ClientState,
    d.Status,
    -- What's wrong, in words, for the summary: "Stale: inventory, policy".
    CASE
        WHEN d.Status = 'Stale' THEN 'Stale: ' + STUFF(
              CASE WHEN d.InventoryStale = 1 THEN ', inventory' ELSE '' END
            + CASE WHEN d.PolicyStale = 1    THEN ', policy'    ELSE '' END
            + CASE WHEN d.HeartbeatStale = 1 THEN ', heartbeat' ELSE '' END, 1, 2, '')
        WHEN d.Status = 'Healthy' THEN NULL
        ELSE d.Status
    END AS Problem,
    CASE WHEN d.Status = 'Healthy' THEN 1 ELSE 0 END AS IsHealthy,
    CASE WHEN d.Status = 'Stale' THEN 1 ELSE 0 END AS IsStale,
    CASE WHEN d.Status = 'Failing health check' THEN 1 ELSE 0 END AS IsFailing,
    CASE WHEN d.Status = 'Inactive' THEN 1 ELSE 0 END AS IsInactive,
    CASE WHEN d.Status = 'No client status' THEN 1 ELSE 0 END AS IsNoStatus,
    CASE WHEN d.Status <> 'Healthy' THEN 1 ELSE 0 END AS IsUnhealthy,
    d.InventoryStale,
    d.PolicyStale,
    d.HeartbeatStale,
    -- UTC in the site; shown in the site database server's time zone, like the other reports' times.
    DATEADD(minute, DATEDIFF(minute, GETUTCDATE(), GETDATE()), d.LastActiveTime) AS LastContact,
    DATEADD(minute, DATEDIFF(minute, GETUTCDATE(), GETDATE()), d.LastPolicyRequest) AS LastPolicy,
    DATEADD(minute, DATEDIFF(minute, GETUTCDATE(), GETDATE()), d.LastHW) AS LastInventory,
    DATEADD(minute, DATEDIFF(minute, GETUTCDATE(), GETDATE()), d.LastDDR) AS LastHeartbeat,
    DATEADD(minute, DATEDIFF(minute, GETUTCDATE(), GETDATE()), d.LastHealthEvaluation) AS LastHealthCheck
FROM Devices d
ORDER BY d.Family, d.Generation, d.Device;
