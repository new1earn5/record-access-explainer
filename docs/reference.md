[← Back to README](../README.md)

## Complete list of package components

See `manifest/package.xml` for the authoritative list. Summary: 108 Apex classes (production,
test-support/fake, and test classes — see the class tables in
[§1](architecture.md#1-architecture-overview) and [§8](features.md#8-additional-capabilities) and
the project file tree), 5 custom objects (`RAA_Analysis__c`, `RAA_Access_Result__c`,
`RAA_Access_Reason__c`, `RAA_Batch_Run__c`, `RAA_Scan_Subscription__c`), 1 platform event
(`RAA_Scan_Status_Event__e`), 1 custom metadata type with 9 fields and 1 default record, 1 custom
permission, 1 permission set, 1 remote site setting (`RAA_Slack_Webhooks`), 1 custom tab, 1
Lightning application, 1 Lightning page, 10 Lightning web components, and 5 custom labels.

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
- Restriction-rule and attribution limitations disclosed in the UI and in
  [Known Limitations](known-limitations.md), and ([§8](features.md#8-additional-capabilities))
  actively checked at scan time where the platform allows it, rather than only stated as a standing
  caveat.
- No `SeeAllData=true` anywhere; 194/194 Apex tests and 69/69 LWC Jest tests passing against a live
  scratch org.
- Metadata deploys successfully to a clean org — verified live, not assumed: multiple real defects
  were found and fixed this way across both the original build and the §8 additions, including an
  invalid `UserRecordAccess` bulk-query assumption, a `Schema.SharingModel` API that does not
  actually exist, several field-metadata rule violations, a real production race condition in batch
  cancellation, a permission set referencing FLS on required fields (rejected by the platform), and
  the test-only `System.AsyncException: Maximum stack depth has been reached` restriction on
  chaining Queueable Apex jobs inside `Test.startTest()`/`Test.stopTest()`.
