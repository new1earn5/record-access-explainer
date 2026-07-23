# Record Access Explainer

A Salesforce administrator/auditor application that answers one question in depth: **"Which
users have effective access to this record, and why?"**

Enter any record ID and Record Access Explainer runs a background scan against the org's user
population, reports Salesforce's own computed effective access for every user (via
`UserRecordAccess`), and then explains — separately, with a confidence rating on each claim — the
sharing mechanisms it can prove are responsible: ownership, role hierarchy, direct and group
shares, sharing rules, permission bypasses, teams, territories, and controlled-by-parent chains.

This project was built, deployed to a live scratch org, and test-verified (106/106 Apex tests
passing) during generation. Every SOQL/Schema behavior described below — including several
platform restrictions that are easy to get wrong — was confirmed against a real org, not assumed.

---

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
- **"Controlled by Parent" *is* reliably detectable**, just not through a sharing-model enum:
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

### Apex components

| Layer | Class | Responsibility |
|---|---|---|
| Controller | `RAA_RecordAccessExplainerController` | Sole `@AuraEnabled` surface. `with sharing`. Permission + visibility gate. |
| Orchestration | `RAA_AnalysisOrchestratorService` | Elevated (`without sharing`) service boundary; never Aura-enabled. |
| Async | `RAA_AccessScanBatch` | `Database.Batchable<Id>, Database.Stateful`. One chunk = one bulk pass. |
| Scheduling | `RAA_CleanupScheduler` | Optional `Schedulable` retention cleanup. |
| Effective access | `RAA_IEffectiveAccessProvider` / `RAA_UserRecordAccessProvider` | `UserRecordAccess` wrapper, swappable in tests. |
| Context | `RAA_ContextBuilder` / `RAA_AnalysisContext` | Bulk-loads record, owner, share object, share rows once. |
| Metadata | `RAA_RecordMetadataResolver`, `RAA_ShareObjectResolver` | Dynamic object/share-table discovery via `Schema`. |
| Reason engine | `RAA_IReasonAnalyzer` + 8 implementations | Strategy pattern; see §4. |
| Aggregation | `RAA_ReasonAggregator` | Confirms effective access, fans out to analyzers, dedupes, sorts. |
| Groups | `RAA_GroupGraphResolver` | Bulk BFS over `Group`/`GroupMember`, cycle-safe. |
| Persistence | `RAA_AnalysisRepository` | All DML/SOQL against the RAA data model; idempotent upserts. |
| Population | `RAA_UserPopulationBuilder` | Dynamic SOQL for the scan's candidate users. |
| Export | `RAA_CsvExportService` | RFC 4180 CSV formatting. |
| Settings | `RAA_SettingsService` | `RAA_Settings__mdt` reader with safe fallbacks. |
| Security | `RAA_PermissionChecker`, `RAA_IdValidationUtil` | Custom permission wrapper (test-overridable), ID validation. |
| DTOs | `RAA_Analysis*DTO`, `RAA_AccessResultDTO`, `RAA_AccessReasonDTO`, `RAA_SettingsDTO`, `RAA_GroupPathDTO` | No raw SObjects cross the Aura boundary. |
| Test support | `RAA_TestDataFactory`, `RAA_FakeEffectiveAccessProvider`, `RAA_FakeReasonAnalyzer` | `@IsTest` fakes for dependency injection. |

---

## 2. Data Model

All three objects are package-owned, **organization-wide default: Private**, and are not meant to
be seen by ordinary users.

### `RAA_Analysis__c` (one row per scan)
Auto-number `RAA-{0000}`. Fields: `RAA_Record_Id__c`, `RAA_Object_API_Name__c`,
`RAA_Record_Display_Name__c`, `RAA_Status__c` (picklist: Queued / Running / Completed / Completed
with Warnings / Failed / Cancelled), `RAA_Requested_By__c` (lookup User), `RAA_Requested_At__c`,
`RAA_Started_At__c`, `RAA_Completed_At__c`, `RAA_Async_Job_Id__c`, `RAA_Total_Users__c`,
`RAA_Processed_Users__c`, `RAA_Users_With_Access__c`, `RAA_Include_External_Users__c`,
`RAA_Include_Inactive_Users__c`, `RAA_Warnings__c`, `RAA_Error_Details__c`, `RAA_Is_Complete__c`.

### `RAA_Access_Result__c` (one row per user per analysis)
Master-detail to `RAA_Analysis__c` (sharing follows the parent — this is *why* the object has no
generated `RAA_Access_Result__Share` table, verified against a live org). Fields:
`RAA_User__c`, `RAA_User_Name__c`, `RAA_Username__c`, `RAA_User_Type__c`, `RAA_Profile_Name__c`,
`RAA_Is_Active__c`, `RAA_Max_Access_Level__c`, `RAA_Has_Read_Access__c`, `RAA_Has_Edit_Access__c`,
`RAA_Has_Delete_Access__c`, `RAA_Has_Transfer_Access__c`, `RAA_Has_All_Access__c`,
`RAA_Reason_Summary__c`, `RAA_Overall_Confidence__c`, `RAA_Has_Unresolved_Reason__c`, and
`RAA_Unique_Key__c` — a Text(60) **External ID + Unique** field (`{AnalysisId}-{UserId}`) that the
batch upserts against, so a retried chunk can never create a duplicate result for the same user.

### `RAA_Access_Reason__c` (one row per detected access path)
Master-detail to `RAA_Access_Result__c`. Fields: `RAA_Category__c` (Ownership / Role Hierarchy /
Direct Share / Group Share / Sharing Rule / Permission / Team / Territory / Implicit / Parent
Controlled / Organization-Wide Default / Unresolved), `RAA_Access_Level__c`, `RAA_Confidence__c`
(High / Medium / Low), `RAA_Is_Direct__c`, `RAA_Source_Name__c`, `RAA_Source_Id__c`,
`RAA_Source_Object__c`, `RAA_Principal_Id__c`, `RAA_Principal_Type__c`, `RAA_Row_Cause__c`,
`RAA_Grant_Path__c`, `RAA_Explanation__c`, `RAA_Evidence__c`.

### `RAA_Settings__mdt` (custom metadata type, one packaged record: `RAA_Default`)
`RAA_Default_Batch_Scope__c` (20), `RAA_Max_Group_Depth__c` (6), `RAA_Max_Parent_Depth__c` (5),
`RAA_Retention_Days__c` (90), `RAA_Default_Include_External__c` (false),
`RAA_Default_Include_Inactive__c` (false), `RAA_Max_Users_Per_Scan__c` (0 = unlimited).

---

## 3. Security Model

- **Custom permission**: `RAA_Run_Record_Access_Analysis`. Every server-side entry point checks it
  via `RAA_PermissionChecker.hasRunPermission()` before doing anything else.
- **Permission set**: `RAA_Record_Access_Auditor` — grants the custom permission, access to the
  single Apex controller class, CRUD on the three RAA objects (with field-level security on every
  non-required field), the `RAA_Settings__mdt` type, and the tab/app. **It does not include View
  All Data, Modify All Data, or any object-wide bypass on business objects.**
- **Two-layer authorization on every read/write of a specific analysis**: the controller (1) checks
  the custom permission, then (2) re-queries the target `RAA_Analysis__c` row itself under normal
  `with sharing` semantics before delegating to the elevated orchestrator. Since the object's OWD is
  Private, this means a user can only see analyses they own (or that Salesforce's own role hierarchy
  / explicit sharing grants them) — an operator cannot read or cancel someone else's scan even
  though they hold the custom permission. This was verified with a dedicated test
  (`cannotReadAnalysisBelongingToAnotherUser`) using two independent Standard User accounts.
- **The scan itself runs in system mode** (see architecture notes above), so **the operator does
  not need View All Data, View Setup and Configuration, or any broad object grants** for a complete
  scan — that is a deliberate, more secure design choice versus what a naive `with sharing`
  implementation would require. The `RAA_Run_Record_Access_Analysis` custom permission plus the
  packaged permission set is sufficient.
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

---

## 4. Supported Access Reasons

| Category | Mechanism | Confidence |
|---|---|---|
| Ownership | Direct user ownership | High |
| Ownership | Queue ownership + queue membership (via group graph) | High |
| Role Hierarchy | User's role is above the owner's role | **High on standard objects** (hierarchy grant cannot be disabled there), **Medium on custom objects** (the "Grant Access Using Hierarchies" checkbox state is not exposed by any supported API) |
| Direct Share | Manual (or other non-rule, non-team) share row directly to a user | High |
| Group Share | Share row to a public group/queue/role group the user belongs to, including nested groups | High |
| Sharing Rule | Share row with `RowCause = 'Rule'` | High that access is real; the exact rule name is **never claimed** — the reason literally says "exact rule name unavailable from the share row" per the platform's own limitation |
| Implicit | Share row with `RowCause = 'ImplicitChild'/'ImplicitParent'` | Medium |
| Permission | View All Data / Modify All Data (profile or permission set) | High |
| Permission | View All Records / Modify All Records on the specific object | High |
| Team | Account Team / Opportunity Team / Case Team membership, with role | High |
| Territory | Direct or ancestor (subordinate) territory assignment via `UserTerritory2Association` | High (direct) / Medium (via subordinate territory) |
| Parent Controlled | Recursive re-analysis of the controlling master-detail parent (Ownership, Role Hierarchy, Share Row, Team, Territory only — not Permission, which was already evaluated once against the child's own object type) | Inherited from the underlying reason |
| Organization-Wide Default | Always Low, honest disclaimer — see §1 | Low |
| Unresolved | `UserRecordAccess` confirms access but nothing above explains it | Low |

**The golden rule, enforced in code (`RAA_ReasonAggregator`): a reason is only ever attached to a
user who `UserRecordAccess` has already confirmed has effective access.** Analyzer output for any
other user is silently discarded — reasons never grant access on their own, they only explain
access that Salesforce already confirmed.

Plain object-level CRUD (Read/Edit/Delete without a View/Modify-All bypass) is deliberately **not**
reported as a standalone reason — it is a prerequisite for record access, never sufficient by
itself to explain access to a Private record.

Object CRUD alone does not explain access to a private record; only the "all records" bypasses do,
and each such reason's explanation states in the record itself whether it bypasses sharing entirely
(View/Modify All Data) or only for that one object (View/Modify All Records).

---

## 5. Known Limitations

1. **Restriction rules are not evaluated.** `UserRecordAccess` reflects the record-level sharing
   model but does not account for restriction rules, which can further narrow what a user actually
   sees. The UI displays a persistent banner saying so.
2. **Sharing recalculation timing.** Recently changed roles, groups, or sharing rules may not be
   fully reflected in `UserRecordAccess` until Salesforce finishes its asynchronous recalculation.
   The UI banner discloses this too.
3. **Muting permission sets are not represented.** `MutingPermissionSet` does not expose a
   queryable field linking it back to a specific `PermissionSetGroup` or `PermissionSet` in the
   current API — this was verified directly against a live org's schema. Permission-set-group
   reasons should be read as the group's nominal (not muting-adjusted) permissions.
4. **The organization-wide default value itself cannot be retrieved.** See §1 — there is no
   supported non-callout API for it. `RAA_OrgWideDefaultAnalyzer` always reports this honestly
   rather than guessing.
5. **Account/Opportunity/Case Teams and Enterprise Territory Management are optional features.**
   `RAA_TeamAnalyzer` and `RAA_TerritoryAnalyzer` detect their availability dynamically and
   contribute nothing (not an error) when a feature was never enabled in the target org. This also
   means Apex code coverage for those two classes is necessarily lower in an org where the
   features are off (see §10) — the "feature unavailable" branch is fully tested; the "feature
   enabled" branches cannot be exercised without a licensed feature toggle.
6. **"Roles and Subordinates", "Territory", and "Territory and Subordinates" group principals**
   referenced by a share row are not backed by `GroupMember` rows at all (Salesforce computes their
   membership dynamically), so `RAA_GroupGraphResolver` cannot resolve through them; when a share
   row's principal is one of those types, the user still needs independent confirmation from
   `RAA_RoleHierarchyAnalyzer` or `RAA_TerritoryAnalyzer` to get a reason — otherwise it falls
   through to Unresolved, which is the honest outcome.
7. **Maximum group nesting depth and parent-chain depth are configurable but finite**
   (`RAA_Settings__mdt`). A path that would require exceeding either limit is not resolved and
   contributes to warnings.

---

## 6. Required Operator Permissions

To **run and view scans**: assign the `RAA_Record_Access_Auditor` permission set. Nothing else is
required — the scan executes as a system-mode background job (see §1), so the operator's own
object/field permissions on User, Group, PermissionSet, share objects, etc. are irrelevant to scan
completeness.

To **install/administer the package**: System Administrator (or equivalent) is needed to deploy
metadata, create/assign the permission set, and optionally schedule `RAA_CleanupScheduler`.

There is intentionally **no scenario in this design where an operator needs View All Data, Modify
All Data, or View Setup and Configuration** just to use the app.

---

## 7. Effective Access vs. Reason Attribution

**Effective access** (Read / Edit / Delete / Transfer / All Access / Max Access Level) is
Salesforce's own computed answer, read from `UserRecordAccess` — authoritative and never guessed.

**Reason attribution** is this package's best-effort explanation of *why* that access exists,
built by correlating share rows, groups, roles, permission sets, teams, territories, and parent
chains after the fact. It is inherently an approximation of the sharing engine's internal logic,
not the sharing engine itself. The UI and every reason record distinguish the two clearly, and a
reason's confidence level (High / Medium / Low) tells you how directly it was proven.

---

## 8. Deployment Instructions

Requires the [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) (`sf`).

```bash
# Authenticate to your target org (skip if already authenticated)
sf org login web --alias my-org

# Deploy the full package
sf project deploy start --source-dir force-app --target-org my-org
```

To deploy via an explicit manifest instead:

```bash
sf project deploy start --manifest manifest/package.xml --target-org my-org
```

This project was deployed to and verified against a live Salesforce scratch org
(`Developer` edition, API v62.0) during generation with zero manual fixes required after the
verification pass documented in §14.

---

## 9. Test Execution Instructions

```bash
# Apex tests
sf apex run test --target-org my-org --test-level RunLocalTests --code-coverage --result-format human --wait 30

# LWC Jest tests (from the project root, after `npm install`)
npm install
npm run test:unit
```

At last verification: **106/106 Apex tests passing, 84–85% org-wide coverage.** Every class
directly involved in the request/response path, persistence, and reason logic is at or above 90%;
the two exceptions (`RAA_TerritoryAnalyzer`, `RAA_TeamAnalyzer`) are explained in §5 and §10.

---

## 10. Permission Set Assignment Instructions

```bash
sf org assign permset --name RAA_Record_Access_Auditor --target-org my-org
```

Or in Setup: **Permission Sets → RAA Record Access Auditor → Manage Assignments → Add Assignment.**

---

## 11. Lightning Application Setup Instructions

The package deploys a Lightning app named **Record Access Explainer**
(`RAA_Record_Access_Explainer`) containing the **Record Access Explainer** tab
(`raaRecordAccessExplainer`), and a Lightning App Page (`RAA_Record_Access_Explainer_Home`) that
hosts the `raaRecordAccessExplainer` component. To make it available to auditors:

1. **Setup → App Manager**, confirm "Record Access Explainer" is present (it deploys automatically).
2. Assign the app to the relevant profiles/permission sets under **App Manager → Record Access
   Explainer → Edit → User Profiles**, or rely on users pinning it themselves from the App Launcher.
3. The `raaRecordAccessExplainer` LWC also declares `lightning__RecordPage`, `lightning__HomePage`,
   and `lightning__UtilityBar` targets, so an admin can optionally drop it onto an Account/Case/
   Opportunity/Contact/Lead record page, a Home page, or the utility bar via Lightning App Builder.

---

## 12. Creating and Uploading the Unmanaged Package

Source generation alone **cannot produce an installation URL** — that only exists once a package
version has been uploaded from inside a real Salesforce packaging org. To create one:

1. Deploy this project to your packaging org: `sf project deploy start --source-dir force-app --target-org my-packaging-org`.
2. In that org, open **Setup → Package Manager**.
3. Click **New** to create an unmanaged package named **Record Access Explainer**.
4. Click **Add** and add every component listed in `manifest/package.xml` (all Apex classes, the
   three custom objects, `RAA_Settings__mdt` and its `RAA_Default` record, the custom permission,
   the permission set, the tab, the application, the Lightning page, both Lightning web components,
   and the five custom labels).
5. Click **Verify Dependencies** to confirm nothing is missing.
6. Click **Upload**, choose a release type, and Salesforce will generate the installation URL.

---

## 13. Configuring `RAA_Settings__mdt`

Setup → Custom Metadata Types → RAA Settings → Manage Records → **RAA_Default**. All fields are
editable in place; no deployment is required to change them:

| Field | Default | Purpose |
|---|---|---|
| Default Batch Scope | 20 | Users processed per `execute()` chunk |
| Max Group Depth | 6 | Nested public-group traversal limit |
| Max Parent Depth | 5 | Controlled-by-parent recursion limit |
| Retention Days | 90 | Age (days) after which `RAA_CleanupScheduler` deletes a completed analysis; 0 disables cleanup |
| Default Include External | false | Pre-fills the "Include external users" checkbox |
| Default Include Inactive | false | Pre-fills the "Include inactive users" checkbox |
| Max Users Per Scan | 0 (unlimited) | Scans that would exceed this are rejected before any batch job starts |

---

## 14. Performance Guidance for Large Organizations

- Keep **Default Batch Scope** at or near 20–50. `UserRecordAccess` is queried once per user per
  chunk (the one unavoidable per-user query — see §1), so a larger scope directly increases SOQL
  count per transaction; the batch framework simply runs more chunks if you keep it modest.
- **Max Users Per Scan** is unlimited by default. In orgs with tens of thousands of users, set this
  to a sane ceiling (for example 5,000) so an accidental "include everyone" scan fails fast with a
  clear message instead of running for a very long time.
- Group graph and controlled-by-parent recursion are both depth-bounded and reused across the whole
  batch chunk (never per user), so their cost scales with the record's own sharing complexity, not
  with population size.
- Enable the cleanup scheduler (§16) so completed analyses don't accumulate indefinitely.

---

## 15. Troubleshooting Guidance

| Symptom | Likely cause | What to check |
|---|---|---|
| "You do not have permission to use Record Access Explainer" | Custom permission not assigned | Assign `RAA_Record_Access_Auditor` (§10) |
| "The requested analysis could not be found, or you do not have access to it" | Either the ID is wrong, or (correctly) it belongs to another user under Private OWD | Confirm you are the original requester, or have it shared/an admin can see it |
| Scan finishes as "Completed with Warnings" | One or more analyzers hit a platform limitation (unsupported group type, feature not enabled, chunk failure) | Read `RAA_Warnings__c` on the analysis, or the warning banner in the UI |
| Scan status stays "Queued" for a long time | Org's async Apex queue is busy | Check **Setup → Apex Jobs**; this package does not control platform-wide async concurrency |
| "This scan would include more than N users..." | `RAA_Max_Users_Per_Scan__c` ceiling hit | Narrow filters, or raise/clear the ceiling in `RAA_Settings__mdt` |
| Object not supported | `UserRecordAccess` does not expose data for that object type | Confirmed via a live probe query in `RAA_RecordMetadataResolver.supportsUserRecordAccess` before a scan is even started |

---

## 16. Scan Status Reference

| Status | Meaning |
|---|---|
| **Queued** | Accepted; waiting for a batch execution slot. |
| **Running** | Actively evaluating the user population. |
| **Completed** | Finished with no warnings. |
| **Completed with Warnings** | Finished, but see §15 — some reasons may be incomplete. |
| **Failed** | Could not complete (see `RAA_Error_Details__c`, sanitized). |
| **Cancelled** | Cancelled by the requester before/while running; the batch will not overwrite this status even if it was already mid-flight. |

---

## 17. Cleanup Scheduler Setup

`RAA_CleanupScheduler` is **not** scheduled automatically on install. To enable it:

```apex
System.schedule('RAA Nightly Cleanup', '0 0 2 * * ?', new RAA_CleanupScheduler());
```

Run once from **Setup → Apex → Execute Anonymous** (or via `sf apex run`). It deletes completed
analyses (cascading to their results and reasons) older than `RAA_Retention_Days__c`; set that
field to 0 to disable cleanup without unscheduling the job.

---

## 18. Upgrade Considerations for an Unmanaged Package

Unmanaged packages have no upgrade path — a new version is a brand-new package install, and
existing customizations (list views, page layout placements, additional field permissions) are not
automatically carried forward. Before re-uploading a new version:

- Export/back up `RAA_Analysis__c` / `RAA_Access_Result__c` / `RAA_Access_Reason__c` data if it
  needs to survive, since reinstalling does not touch existing data but a full uninstall would.
- Re-verify field-level security on the permission set after any new fields are added upstream.
- `RAA_Settings__mdt.RAA_Default` values are metadata, not data — they will be reset to the
  package's shipped defaults on a fresh install of a new version.

---

## Complete list of package components

See `manifest/package.xml` for the authoritative list. Summary: 64 Apex classes (33 production
classes + 3 test-support/fake classes + 28 test classes — see the class table in §1 and the
project file tree), 3 custom objects with 46 custom fields total, 1 custom metadata type with 7
fields and 1 default record, 1 custom permission, 1 permission set, 1 custom tab, 1 Lightning
application, 1 Lightning page, 2 Lightning web components, and 5 custom labels.

## Acceptance-criteria self-check

- Dynamic object resolution: `RAA_RecordMetadataResolver` (uses `Id.getSObjectType()`, never a
  hardcoded object list).
- Background scan via `Database.Batchable` + `Database.Stateful`: `RAA_AccessScanBatch`.
- Every user with confirmed effective access stored/displayed, read/edit/delete/transfer/all/max
  shown: `RAA_Access_Result__c` fields, `raaRecordAccessExplainer` datatable columns.
- Every detected access path shown separately, never guessed: `RAA_Access_Reason__c` rows, the
  Unresolved fallback, the Sharing Rule "name unavailable" disclosure.
- Nested groups handled safely: `RAA_GroupGraphResolver` (bulk BFS, visited-set cycle guard,
  tested against both a nested-group case and a diamond-shaped reconvergence case — Salesforce
  itself rejects literal circular `GroupMember` rows at the DML level, which was verified directly).
- Permission-derived access explained with its exact source and whether it bypasses sharing:
  `RAA_PermissionAnalyzer`.
- Progress and cancellation work, including the race where cancellation happens before the batch
  is picked up by the platform: `RAA_AccessScanBatch.start()`/`finish()` both check for `Cancelled`
  before doing anything, not just `finish()`.
- Filter/sort/paginate/export: `raaRecordAccessExplainer.js` client-side grid + `RAA_CsvExportService`.
- Unauthorized users cannot run or view analyses: custom permission gate + record-visibility gate,
  both covered by dedicated tests.
- Unsupported objects handled gracefully: `supportsUserRecordAccess` probe before a scan starts.
- Restriction-rule and attribution limitations disclosed in the UI and here.
- No `SeeAllData=true` anywhere; 106/106 tests passing against a live scratch org.
- Metadata deploys successfully to a clean org — verified live, not assumed (see §14 of this
  document's development history: multiple real defects were found and fixed this way, including
  an invalid `UserRecordAccess` bulk-query assumption, a `Schema.SharingModel` API that does not
  actually exist, several field-metadata rule violations, and a real production race condition in
  batch cancellation).
