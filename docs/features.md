[← Back to README](../README.md)

## 8. Additional Capabilities

Further capabilities, all built on the same effective-access/reason-attribution foundation as
the core single-record scan described in the README.

### Bulk / list scan mode

Paste any number of record IDs of the _same_ object type and submit them as one batch
(`RAA_Batch_Run__c`, `raaBulkScan`). Each record still runs through the exact same single-record
pipeline (`RAA_AccessScanBatch`) unchanged — this mode only orchestrates submitting the list and
reporting aggregate progress. Because a single Apex transaction can call `Database.executeBatch` at
most 5 times, `RAA_BulkScanQueueable` processes records in chunks of 5 and chains itself via
`System.enqueueJob` for the remainder, a standard governor-safe fan-out pattern. A single record's
failure (deleted record, unsupported object) is caught and recorded as a `Failed` child analysis
without aborting the rest of the run. Capped by `RAA_Max_Records_Per_Bulk_Run__c`
([§14](configuration.md#14-configuring-raa_settingsmdt)).

### Reverse "by user" mode

Given one user and a candidate set of records of the same object (explicit IDs, or the first N
records if none are given), reports that user's effective access to each one in a single scan
(`RAA_UserAccessExplorerService`, `raaUserAccessExplorer`). This is the mirror image of the normal
"one record, many users" scan, so it hits the same `UserRecordAccess` filter-shape restriction from
the opposite side: the object supports `UserId = [single] AND RecordId IN [list]`, so this mode is
bulk-safe in a way the normal per-record scan is not (see
[§1](architecture.md#1-architecture-overview)). Reasons for a specific record are fetched lazily,
only when an admin clicks into that row, to stay governor-safe against even a few hundred
candidate records. Capped by `RAA_Max_Records_Per_User_Scan__c`
([§14](configuration.md#14-configuring-raa_settingsmdt)) when no explicit record list is supplied.

### Analysis history / diffing

Every completed scan of a record can be compared to the most recent earlier completed scan of that
_same_ record (`RAA_AnalysisDiffService`, `raaAnalysisDiff`), reporting which users gained access,
lost access, or had their max access level or reason summary change. "Compare to Previous Scan" is
available from any completed single-record analysis; the first scan of a record naturally has
nothing to compare against and says so plainly rather than erroring.

### Field-level security tracing

For any user in a scan's results, "View Field Access" (`RAA_FieldAccessService`, `raaFieldAccess`)
shows a permissive union of that user's field-level readable/editable state across every assigned
permission set and their profile — any single grant makes a field accessible, matching how
Salesforce itself resolves FLS. This is deliberately independent of the record-level reason list: a
user can have record access and still be denied specific fields, or vice versa.

### Live sharing-recalculation warning

`RAA_SharingRecalculationChecker` queries `AsyncApexJob WHERE JobType = 'SharingRecalculation' AND
Status IN (...)` at the top of every scan. If Salesforce's own asynchronous sharing recalculation is
currently in flight for the org, the scan surfaces a warning that its results may not yet reflect a
very recent role, group, or sharing-rule change.

### Restriction Rule detection

`RAA_RestrictionRuleChecker` best-effort probes for active Restriction Rules on the scanned object.
`RestrictionRule` is a Tooling/Metadata API type that is not guaranteed queryable through plain Apex
SOQL in every org or API context; the class checks `Schema.getGlobalDescribe()` first and wraps the
query itself in a `try`/`catch`, degrading to "unknown" (no warning) rather than guessing when the
probe isn't possible. This was deliberately built defensive-by-construction, and in the Developer
Edition scratch org used to validate this package, `RestrictionRule` was not present in the global
describe at all — so the guarded early-exit path, not the query itself, is what was actually
exercised during test validation; the query's own shape (`EntityDefinitionId`/`Active` filter)
remains empirically unverified against a live org where the object is reachable. Restriction rules
only ever narrow access, never grant it, so a detected count is always surfaced as a scan-level
warning, never as an access reason.

### Dead / unused sharing rule target detection

After a scan completes, `RAA_ShareRowAnalyzer.flagOrphanedRuleTargets` checks every share row with
`RowCause = 'Rule'` and compares its target group/role principal against the set of scanned users
who actually resolved a group-path match. A rule whose target currently matches **zero** scanned
users is written to a new field, `RAA_Analysis__c.RAA_Sharing_Hygiene_Notes__c`, and surfaced in its
own blue "info" panel in the UI — deliberately kept **separate from `RAA_Warnings__c`**, since an
orphaned rule target is a hygiene observation about the org's sharing configuration, not a defect in
this scan's own result, and folding the two together would make `potentiallyIncomplete`
([§16](operations.md#16-troubleshooting-guidance)) fire for a condition that has nothing to do with
scan completeness. Consistent with the platform's own limitation already documented in
[§4](access-reasons.md#4-supported-access-reasons), the note identifies the rule by its **target
group/role**, not by rule name — the exact rule name is genuinely unavailable from a share row.
This scan-population scope is a real caveat: a target with no match among the population actually
scanned in this run (for example, external users were excluded) is not necessarily unused for every
population, so the note should be read as "not currently doing anything, for the users the specific
scan looked at."

### Scheduled recurring scans with change alerts

An admin (or the requesting user) can subscribe to a record (`RAA_Scan_Subscription__c`,
`raaSubscriptions`) so that, once `RAA_RecurringScanScheduler` is scheduled
([§19](operations.md#19-recurring-scan-scheduler-setup)), it is periodically re-scanned
automatically and the subscriber is notified if anything changed since the last cycle — by email
(`RAA_Notify_On_Change__c`), a Chatter post on the watched record (`RAA_Post_To_Chatter__c`), a
Slack message (`RAA_Post_To_Slack__c`), or any combination independently; each can be on without
the others. Each firing does two things in one pass: (1) for any subscription whose _previous_
cycle's scan has now completed, diffs it against the prior baseline and sends whichever
notifications are enabled if something actually changed; (2) starts a new scan for every active
subscription that isn't already waiting on one. A notification is therefore sent on the firing
_after_ the one that started the scan, once that scan has had time to complete — a deliberate
two-cycle design so the scheduler never blocks on a long-running scan.
`RAA_Scan_Subscription__c.RAA_Pending_Analysis__c` tracks the in-flight scan between cycles;
`RAA_Last_Analysis__c` is the baseline. Email uses native `Messaging.SingleEmailMessage`; the
Chatter post is a plain `FeedItem` insert with `ParentId` set to the watched record; the Slack
message is an HTTP callout via `RAA_SlackNotifier` to the subscription's own stored webhook URL,
scoped by the `RAA_Slack_Webhooks` Remote Site Setting (see
[§3](security-model.md#3-security-model)). Chatter and Slack are both best-effort: if Chatter Feed
Tracking isn't enabled for the watched object, or the Slack callout fails for any reason, the
failure is caught and logged silently — the same defensive pattern used for Restriction Rule
detection above — and never blocks the other two channels or the baseline advance.

### Visual grant-path rendering

The reason detail modal renders each reason's grant path (for example `Owner -> Manager -> VP of
Sales`) as a sequence of chips with directional arrows between them, instead of a single text blob —
purely a presentational change (`raaReasonDetail`), with no effect on the underlying data.

### Risk Insights

A fifth mode (`raaRiskInsights`, `RAA_RiskInsightsService`) ranks records the current user has
already scanned — directly, in bulk, or via a subscription — by risk signals already present in
each record's own most recent completed scan. Nothing here triggers a new scan; it is purely a
read/aggregate over existing `RAA_Access_Result__c`/`RAA_Access_Reason__c` rows, scoped to
`RAA_Requested_By__c = ` the requesting user (the same self-scoping `listMySubscriptions` already
uses, appropriate given `RAA_Analysis__c`'s Private OWD). Four signals feed a transparent, weighted
Risk Score — never an opaque number, since every contributing count is shown alongside it:

| Signal         | Definition                                                                                                                                                                                                                                               | Weight |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| Guest users    | Users with access whose `UserType` is exactly `'Guest'` — broken out from the general external count below because an unauthenticated site visitor with access to a record is a materially higher-severity finding than a licensed external partner user | 5      |
| External users | Users with access whose `UserType` isn't `'Standard'` and isn't `'Guest'` (Guest is counted once, above, never double-counted here)                                                                                                                      | 3      |
| Bypass holders | Distinct users whose access includes a `Permission`-category reason (View/Modify All Data or View/Modify All Records)                                                                                                                                    | 2      |
| Unresolved     | Users whose access `RAA_ReasonAggregator` could not fully attribute to a specific mechanism — an audit blind spot, not itself a risk signal                                                                                                              | 1      |

The results table's "Guest Users" column renders in destructive red text whenever the count is
greater than zero, and the Plain-English Summary (below) leads with a dedicated sentence about
Guest User access — ahead of the access-level breakdown — whenever any are present.

Only the latest completed analysis per distinct record is considered (older re-scans of the same
record are superseded, not summed), and the view is capped at the top 50 by score. Clicking "View
Analysis" on any row jumps straight into the single-record view for that analysis, reusing the same
navigation the bulk scan view already uses for its own "View Details" action.

### Plain-English summary

A "Plain-English Summary" button on a completed single-record scan opens a modal
(`raaPlainEnglishSummary`) with a short paragraph describing the result — who has access, the
access-level breakdown, the dominant reason category, and any unresolved or low-confidence
attributions — built entirely from the same structured `RAA_Access_Result__c`/
`RAA_Access_Reason__c` data the results grid already shows. `RAA_PlainEnglishSummaryService`
assembles it from fixed sentence templates and real tallies; it is **not** a generative-AI call —
no callout, no LLM, no additional licensing, and fully covered by deterministic unit tests. The
modal discloses this explicitly so nobody mistakes the wording for an AI-generated summary.

### Invocable Apex action and REST resource

Two entry points expose a scan to Salesforce automation and to external systems, both re-checking
`RAA_Run_Record_Access_Analysis` and routing through `RAA_AnalysisOrchestratorService` exactly like
the LWC controller does (see [§3](security-model.md#3-security-model)) — there is no separate,
weaker authorization path for either:

- **`RAA_ScanInvocable`** (`@InvocableMethod`) lets a Flow start a scan for a record ID and report
  the resulting analysis ID (or a failure message) back into the Flow, using request/result inner
  classes so it composes with bulkified Flow invocations. Failures are reported on the `Result`
  object rather than thrown, since an uncaught exception from an invocable action surfaces poorly
  in Flow error handling.
- **`RAA_ScanRestResource`** (`global with sharing`, `@RestResource(urlMapping='/RecordAccessScan/*')`)
  exposes `POST /services/apexrest/RecordAccessScan/` to start a scan and
  `GET /services/apexrest/RecordAccessScan/{analysisId}` to check its status, for external systems
  (SIEM tooling, a GRC platform, a custom dashboard) that need to trigger or poll a scan over HTTP
  rather than through the UI. A status check for an analysis ID that exists but isn't visible to the
  calling user under `WITH USER_MODE` returns a 404, not a 200 with an empty body or a 403 that would
  confirm the record's existence to an unauthorized caller.

### Event-driven re-scan on sharing-relevant changes

`RAA_SharingChangeMonitor` (`Schedulable`, see [§21](operations.md#21-sharing-change-monitor-setup)
for setup) closes the gap between "a subscriber's scan is stale" and "someone actually changed
sharing since the last cycle." On each firing, it reads `SetupAuditTrail` for entries since the
previous firing (`CronTrigger.PreviousFireTime`, or a 60-minute lookback on the very first run) and
checks whether any of them are sharing-relevant: an `Action` of `createdrole`/`role`/`deleterole`,
or a `Section` of `Sharing Rules`/`Company Profile` (the org-wide defaults page). If — and only if —
it finds one, it enqueues an immediate re-scan (`RAA_SubscriptionScanQueueable`) of every active
subscription that isn't already waiting on one, independent of `RAA_RecurringScanScheduler`'s own
regular cadence. As documented in [§1](architecture.md#1-architecture-overview), Salesforce exposes
no trigger or Platform Event for these specific setup changes, so this is honestly a frequent
polling design, not a true push event — the value is reacting within one scheduled interval of a
real sharing change instead of waiting for the next regularly-scheduled recurring-scan cycle
regardless of whether anything changed.

### Standalone org-wide oversharing scan

A sixth mode (`raaOrgWideAccess`, `RAA_OrgWideAccessService`) answers a different question than
every other capability in this package: not "who can see this one record," but "which Profiles or
Permission Sets currently grant broad access to these objects, org-wide, and who actually holds
that access right now." Given a comma-separated list of object API names (capped at
`RAA_OrgWideAccessService.MAX_OBJECTS_PER_SCAN`, 10), it queries `ObjectPermissions` for every grant
of View All Records, Modify All Records, or full object-level CRUD (Create+Read+Edit+Delete all
true), resolves each back to a Profile or a directly-assigned Permission Set, and reports the
count of currently **active** users who hold it — entries with zero active users are dropped, since
a bypass nobody currently holds isn't live exposure. Results are sorted by risk (Modify All, then
View All, then full CRUD) and then by active user count descending. This is the only capability in
the package that reads schema/setup metadata exclusively: no record is read, no `RAA_Analysis__c`
row is created, and nothing here touches `UserRecordAccess` or the reason-attribution pipeline at
all — it is independent of, and can be used without ever running, a record-level scan.
