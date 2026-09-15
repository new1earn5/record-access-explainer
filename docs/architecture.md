[← Back to README](../README.md)

## 1. Architecture Overview

```
                        ┌─────────────────────────────┐
                        │  raaRecordAccessExplainer    │  LWC (tab / app page / utility bar)
                        │  raaReasonDetail (child)      │
                        └───────────────┬───────────────┘
                                        │ @AuraEnabled
                        ┌───────────────▼───────────────┐
                        │ RAA_RecordAccessExplainerController │  with sharing
                        │  - checks custom permission     │
                        │  - re-checks record visibility  │
                        └───────────────┬───────────────┘
                                        │
                        ┌───────────────▼───────────────┐
                        │ RAA_AnalysisOrchestratorService │  without sharing (elevated boundary)
                        │  - validates & resolves record  │
                        │  - starts/cancels/deletes scans │
                        └───────┬───────────────┬─────────┘
                                │               │
                  ┌─────────────▼───┐   ┌───────▼──────────┐
                  │ RAA_AccessScanBatch │   │ RAA_AnalysisRepository │
                  │  Database.Batchable  │   │  all DML/SOQL on RAA_* │
                  │  Database.Stateful   │   └───────────────────────┘
                  └─────────┬───────────┘
                            │ per chunk
                  ┌─────────▼───────────┐
                  │ RAA_ReasonAggregator  │  confirms effective access, then fans out
                  └─────────┬───────────┘
        ┌──────────┬────────┼────────┬───────────┬────────────┬──────────────┐
        ▼          ▼        ▼        ▼           ▼            ▼              ▼
   Ownership   RoleHier  ShareRow  Permission   Team      Territory   ParentControlled → OWD
```

Key design decisions, all verified empirically against a live org rather than assumed:

- **`UserRecordAccess` cannot be bulk-queried by a list of users for one record.** Its supported
  filter shapes are `UserId = [single] AND RecordId = [single or IN list]` — `UserId IN [list]` is
  rejected at compile time. Because a scan is always "one record, many users" (the inverse of what
  the object supports), `RAA_UserRecordAccessProvider` issues one query per user per batch chunk.
  This is the **one deliberate, documented exception** to "no SOQL in a loop"; every other data
  source (share rows, groups, permission sets, teams, territories) is bulk-queried once per chunk.
- **There is no supported API for the org-wide default value itself.** `Schema.DescribeSObjectResult`
  has no `getSharingModel()` method, `Schema.SharingModel` is not a real Apex type, and
  `EntityDefinition` (queried through plain SOQL) has no `SharingModel` column. `RAA_OrgWideDefaultAnalyzer`
  reports this honestly (Low confidence, "could not be conclusively retrieved") instead of guessing.
- **"Controlled by Parent" _is_ reliably detectable**, just not through a sharing-model enum:
  `DescribeFieldResult.isCascadeDelete()` is true only for master-detail fields, and Salesforce
  enforces Controlled-By-Parent sharing unconditionally for any object that has one.
  `RAA_ContextBuilder` uses this to locate the controlling parent field for `RAA_ParentControlledAnalyzer`.
- **Account Teams, Case Teams, and Enterprise Territory Management are optional, unlicensed-by-default
  features.** `AccountTeamMember`, `OpportunityTeamMember`, `CaseTeamMember`, `CaseTeamRole`,
  `Territory2`, `UserTerritory2Association`, and `ObjectTerritory2Association` are referenced only
  through fully dynamic SOQL (`Database.query` against a `List<SObject>`), never as compile-time
  types — a static reference would break deployment entirely in any org where the feature was never
  turned on. `RAA_TeamAnalyzer` and `RAA_TerritoryAnalyzer` check `Schema.getGlobalDescribe()` first
  and silently contribute nothing when the feature is absent.
- **Batch Apex runs in system mode for object/field permissions.** Only record-level sharing is
  governed by a class's `with`/`without sharing` keyword; Batch, Queueable, Scheduled, and Future
  Apex all ignore CRUD/FLS regardless. `RAA_AccessScanBatch` is declared `without sharing`
  deliberately so the scan itself sees the full picture, independent of the requesting operator's
  own object permissions — the operator only needs the custom permission to trigger it.
- **Scan status reaches the UI by push, not just polling.** `RAA_AccessScanBatch.finish()`
  publishes a platform event (`RAA_Scan_Status_Event__e`) whenever an analysis reaches a terminal
  status; `raaRecordAccessExplainer` subscribes via `lightning/empApi` and refreshes immediately
  on a matching event instead of waiting for its next poll tick. Polling (every 10s) still runs
  as a fallback for a missed or not-yet-established subscription, so nothing depends on the push
  channel being reliable. Finding and fixing this also surfaced a real, previously-untested bug:
  both `start()` and `finish()` guarded only against a `Cancelled` status specifically, so an
  analysis that `start()` itself had already marked `Failed` (for example, exceeding
  `RAA_Max_Users_Per_Scan__c`) could be silently overwritten back to `Running`/`Completed` by the
  rest of the batch running anyway. Both methods now guard on `RAA_Is_Complete__c` instead of one
  named status, which covers every terminal state uniformly.
- **`SetupAuditTrail.Section` and `.Display` cannot be filtered in SOQL** — a genuine platform
  restriction caught at deploy time (`field 'Section' can not be filtered in a query call`), not
  assumed in advance. `RAA_SharingChangeMonitor` therefore filters only on `CreatedDate` in SOQL
  (capped at `MAX_ROWS_CHECKED`) and checks `Action`/`Section` in Apex afterward. There is also no
  trigger or Platform Event for sharing-rule, role, or org-wide-default changes, so this is
  documented honestly as frequent scheduled polling, not a true push event.

### Apex components

| Layer            | Class                                                                                                                                                                                                                                       | Responsibility                                                                                                                                                                    |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Controller       | `RAA_RecordAccessExplainerController`                                                                                                                                                                                                       | Sole `@AuraEnabled` surface. `with sharing`. Permission + visibility gate.                                                                                                        |
| Orchestration    | `RAA_AnalysisOrchestratorService`                                                                                                                                                                                                           | Elevated (`without sharing`) service boundary; never Aura-enabled.                                                                                                                |
| Async            | `RAA_AccessScanBatch`                                                                                                                                                                                                                       | `Database.Batchable<Id>, Database.Stateful`. One chunk = one bulk pass.                                                                                                           |
| Scheduling       | `RAA_CleanupScheduler`                                                                                                                                                                                                                      | Optional `Schedulable` retention cleanup.                                                                                                                                         |
| Effective access | `RAA_IEffectiveAccessProvider` / `RAA_UserRecordAccessProvider`                                                                                                                                                                             | `UserRecordAccess` wrapper, swappable in tests.                                                                                                                                   |
| Context          | `RAA_ContextBuilder` / `RAA_AnalysisContext`                                                                                                                                                                                                | Bulk-loads record, owner, share object, share rows once.                                                                                                                          |
| Metadata         | `RAA_RecordMetadataResolver`, `RAA_ShareObjectResolver`                                                                                                                                                                                     | Dynamic object/share-table discovery via `Schema`.                                                                                                                                |
| Reason engine    | `RAA_IReasonAnalyzer` + 8 implementations                                                                                                                                                                                                   | Strategy pattern; see [§4](access-reasons.md#4-supported-access-reasons).                                                                                                         |
| Aggregation      | `RAA_ReasonAggregator`                                                                                                                                                                                                                      | Confirms effective access, fans out to analyzers, dedupes, sorts.                                                                                                                 |
| Groups           | `RAA_GroupGraphResolver`                                                                                                                                                                                                                    | Bulk BFS over `Group`/`GroupMember`, cycle-safe.                                                                                                                                  |
| Persistence      | `RAA_AnalysisRepository`                                                                                                                                                                                                                    | All DML/SOQL against the RAA data model; idempotent upserts.                                                                                                                      |
| Population       | `RAA_UserPopulationBuilder`                                                                                                                                                                                                                 | Dynamic SOQL for the scan's candidate users.                                                                                                                                      |
| Export           | `RAA_CsvExportService`                                                                                                                                                                                                                      | RFC 4180 CSV formatting.                                                                                                                                                          |
| Settings         | `RAA_SettingsService`                                                                                                                                                                                                                       | `RAA_Settings__mdt` reader with safe fallbacks.                                                                                                                                   |
| Security         | `RAA_PermissionChecker`, `RAA_IdValidationUtil`                                                                                                                                                                                             | Custom permission wrapper (test-overridable), ID validation.                                                                                                                      |
| DTOs             | `RAA_Analysis*DTO`, `RAA_AccessResultDTO`, `RAA_AccessReasonDTO`, `RAA_SettingsDTO`, `RAA_GroupPathDTO`, `RAA_FieldAccessDTO`, `RAA_UserRecordAccessSummaryDTO`, `RAA_BatchRunSummaryDTO`, `RAA_SubscriptionDTO`, `RAA_UserAccessChangeDTO` | No raw SObjects cross the Aura boundary.                                                                                                                                          |
| Test support     | `RAA_TestDataFactory`, `RAA_FakeEffectiveAccessProvider`, `RAA_FakeReasonAnalyzer`                                                                                                                                                          | `@IsTest` fakes for dependency injection.                                                                                                                                         |
| Bulk scan        | `RAA_BulkScanQueueable`                                                                                                                                                                                                                     | Governor-safe 5-at-a-time fan-out over `Database.executeBatch`, self-chained; see [§8](features.md#8-additional-capabilities).                                                    |
| By-user scan     | `RAA_UserAccessExplorerService`                                                                                                                                                                                                             | Reverse-mode bulk `UserRecordAccess` query (`UserId = single, RecordId IN list`); see [§8](features.md#8-additional-capabilities).                                                |
| Field access     | `RAA_FieldAccessService`, `RAA_PermissionSetLookup`                                                                                                                                                                                         | Permissive-union FLS computation across a user's assigned permission sets and profile; see [§8](features.md#8-additional-capabilities).                                           |
| Diffing          | `RAA_AnalysisDiffService`                                                                                                                                                                                                                   | Compares two completed analyses of the same record; see [§8](features.md#8-additional-capabilities).                                                                              |
| Live warnings    | `RAA_SharingRecalculationChecker`, `RAA_RestrictionRuleChecker`                                                                                                                                                                             | Best-effort, defensively-guarded scan-time signals; see [§8](features.md#8-additional-capabilities).                                                                              |
| Recurring scans  | `RAA_RecurringScanScheduler`, `RAA_SubscriptionScanQueueable`, `RAA_SubscriptionRepository`                                                                                                                                                 | Optional two-phase scheduled re-scan + email/Chatter/Slack change alert; see [§8](features.md#8-additional-capabilities), [§19](operations.md#19-recurring-scan-scheduler-setup). |
| Notifications    | `RAA_SlackNotifier`                                                                                                                                                                                                                         | Validates and posts to a Slack Incoming Webhook URL; see [§8](features.md#8-additional-capabilities).                                                                             |
| Sharing hygiene  | `RAA_ShareRowAnalyzer` (`flagOrphanedRuleTargets`)                                                                                                                                                                                          | Flags sharing-rule target groups/roles matching zero scanned users; see [§8](features.md#8-additional-capabilities).                                                              |
| Change monitor   | `RAA_SharingChangeMonitor`                                                                                                                                                                                                                  | `Schedulable`; polls `SetupAuditTrail` and triggers re-scans on sharing-relevant changes; see [§8](features.md#8-additional-capabilities).                                        |
| Integration      | `RAA_ScanInvocable`, `RAA_ScanRestResource`                                                                                                                                                                                                 | Flow-invocable action and `@RestResource` for starting/checking scans externally; see [§8](features.md#8-additional-capabilities).                                                |
| Org-wide scan    | `RAA_OrgWideAccessDTO`, `RAA_OrgWideAccessService`                                                                                                                                                                                          | Standalone schema-level scan for View/Modify All and full-CRUD grants org-wide; see [§8](features.md#8-additional-capabilities).                                                  |
