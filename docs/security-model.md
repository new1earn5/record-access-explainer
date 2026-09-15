[← Back to README](../README.md)

## 3. Security Model

- **Custom permission**: `RAA_Run_Record_Access_Analysis`. Every server-side entry point checks it
  via `RAA_PermissionChecker.hasRunPermission()` before doing anything else.
- **Permission set**: `RAA_Record_Access_Auditor` — grants the custom permission, access to the
  Apex controller, `RAA_ScanInvocable`, and `RAA_ScanRestResource` classes, CRUD on all five RAA
  objects (with field-level security on every non-required field, including the two new
  Slack-related fields on `RAA_Scan_Subscription__c`), the `RAA_Settings__mdt` type, and the
  tab/app. **It does not include View All Data, Modify All Data, or any object-wide bypass on
  business objects.**
- **Two-layer authorization on every read/write of a specific analysis**: the controller (1) checks
  the custom permission, then (2) re-queries the target `RAA_Analysis__c` row itself under normal
  `with sharing` semantics before delegating to the elevated orchestrator. Since the object's OWD is
  Private, this means a user can only see analyses they own (or that Salesforce's own role hierarchy
  / explicit sharing grants them) — an operator cannot read or cancel someone else's scan even
  though they hold the custom permission. This was verified with a dedicated test
  (`cannotReadAnalysisBelongingToAnotherUser`) using two independent Standard User accounts.
- **The scan itself runs in system mode** (see [§1](architecture.md#1-architecture-overview)), so
  **the operator does not need View All Data, View Setup and Configuration, or any broad object
  grants** for a complete scan — that is a deliberate, more secure design choice versus what a
  naive `with sharing` implementation would require. The `RAA_Run_Record_Access_Analysis` custom
  permission plus the packaged permission set is sufficient.
- `with sharing` / `without sharing` boundary: `RAA_RecordAccessExplainerController` and
  `RAA_CsvExportService` are `with sharing`. Every class in the elevated pipeline
  (`RAA_AnalysisOrchestratorService`, `RAA_AccessScanBatch`, `RAA_AnalysisRepository`,
  `RAA_ContextBuilder`, `RAA_RecordMetadataResolver`, `RAA_ShareObjectResolver`,
  `RAA_GroupGraphResolver`, and all `RAA_I ReasonAnalyzer` implementations) is `without sharing`
  and **none of them is directly `@AuraEnabled`** — the controller is the only door in.
- Client-supplied IDs are always routed through `RAA_IdValidationUtil` before use. Dynamic SOQL
  (`RAA_RecordMetadataResolver`, `RAA_ShareObjectResolver`, `RAA_ContextBuilder`,
  `RAA_ParentControlledAnalyzer`, `RAA_TeamAnalyzer`, `RAA_TerritoryAnalyzer`) builds object/field
  names **only** from `Schema` describe results and always binds record IDs as `:variables` —
  never string-concatenated user input.
- No raw exception messages or stack traces ever reach the client — every controller method
  catches `RAA_AppException` (sanitized, user-authored message) separately from any other
  `Exception` (generic message only).
- **`RAA_ScanRestResource`** (`global with sharing`, mapped to `/RecordAccessScan/*`) and
  **`RAA_ScanInvocable`** both reuse `RAA_PermissionChecker.hasRunPermission()` and
  `RAA_AnalysisOrchestratorService` exactly like the controller does — there is no separate,
  weaker authorization path for external/Flow-triggered scans. The REST resource returns a 404
  (not a generic error) for an analysis ID that exists but isn't visible to the calling user under
  `WITH USER_MODE`, so it never confirms or denies existence to an unauthorized caller.
- **The Slack webhook URL is stored `EncryptedText`** and validated by `RAA_SlackNotifier` to
  start with `https://hooks.slack.com/` before every callout; the callout itself is further scoped
  by a Remote Site Setting (`RAA_Slack_Webhooks`, `https://hooks.slack.com` only), so the org
  cannot be made to call out to an arbitrary attacker-controlled endpoint even if the stored URL
  were somehow altered.

---

## 6. Required Operator Permissions

To **run and view scans**: assign the `RAA_Record_Access_Auditor` permission set. Nothing else is
required — the scan executes as a system-mode background job (see
[§1](architecture.md#1-architecture-overview)), so the operator's own object/field permissions on
User, Group, PermissionSet, share objects, etc. are irrelevant to scan completeness.

To **install/administer the package**: System Administrator (or equivalent) is needed to deploy
metadata, create/assign the permission set, and optionally schedule `RAA_CleanupScheduler`.

There is intentionally **no scenario in this design where an operator needs View All Data, Modify
All Data, or View Setup and Configuration** just to use the app.
