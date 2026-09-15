[← Back to README](../README.md)

## 15. Performance Guidance for Large Organizations

- Keep **Default Batch Scope** at or near 20–50. `UserRecordAccess` is queried once per user per
  chunk (the one unavoidable per-user query — see [§1](architecture.md#1-architecture-overview)),
  so a larger scope directly increases SOQL count per transaction; the batch framework simply runs
  more chunks if you keep it modest.
- **Max Users Per Scan** is unlimited by default. In orgs with tens of thousands of users, set this
  to a sane ceiling (for example 5,000) so an accidental "include everyone" scan fails fast with a
  clear message instead of running for a very long time.
- Group graph and controlled-by-parent recursion are both depth-bounded and reused across the whole
  batch chunk (never per user), so their cost scales with the record's own sharing complexity, not
  with population size.
- Enable the cleanup scheduler ([§18](#18-cleanup-scheduler-setup)) so completed analyses don't
  accumulate indefinitely.
- Bulk scans and the recurring-scan scheduler both fan out via the same chunk-of-5-then-chain
  `Queueable` pattern (`RAA_BulkScanQueueable`, `RAA_SubscriptionScanQueueable`) rather than one
  giant transaction, so a large submission spreads its `executeBatch` calls across multiple queue
  cycles instead of hitting the 5-per-transaction ceiling in one go.

---

## 16. Troubleshooting Guidance

| Symptom                                                                      | Likely cause                                                                                                                                                  | What to check                                                                                                                                                                |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| "You do not have permission to use Record Access Explainer"                  | Custom permission not assigned                                                                                                                                | Assign `RAA_Record_Access_Auditor` ([§11 in the README](../README.md#11-permission-set-assignment-instructions))                                                             |
| "The requested analysis could not be found, or you do not have access to it" | Either the ID is wrong, or (correctly) it belongs to another user under Private OWD                                                                           | Confirm you are the original requester, or have it shared/an admin can see it                                                                                                |
| Scan finishes as "Completed with Warnings"                                   | One or more analyzers hit a platform limitation (unsupported group type, feature not enabled, chunk failure)                                                  | Read `RAA_Warnings__c` on the analysis, or the warning banner in the UI                                                                                                      |
| Scan status stays "Queued" for a long time                                   | Org's async Apex queue is busy                                                                                                                                | Check **Setup → Apex Jobs**; this package does not control platform-wide async concurrency                                                                                   |
| "This scan would include more than N users..."                               | `RAA_Max_Users_Per_Scan__c` ceiling hit                                                                                                                       | Narrow filters, or raise/clear the ceiling in `RAA_Settings__mdt`                                                                                                            |
| Object not supported                                                         | `UserRecordAccess` does not expose data for that object type                                                                                                  | Confirmed via a live probe query in `RAA_RecordMetadataResolver.supportsUserRecordAccess` before a scan is even started                                                      |
| "Enter a record ID for each line" / bulk scan rejects the whole list         | One or more pasted IDs don't share the same object type as the rest                                                                                           | Bulk scan ([§8](features.md#8-additional-capabilities)) requires every record to be the same object; split mixed lists into separate submissions                             |
| A subscription never sends an email or Chatter post                          | `RAA_RecurringScanScheduler` isn't scheduled, both `RAA_Notify_On_Change__c` and `RAA_Post_To_Chatter__c` are off, or nothing actually changed between cycles | See [§19](#19-recurring-scan-scheduler-setup); check **Setup → Scheduled Jobs** for the job, and that the subscription's `RAA_Last_Analysis__c` is advancing between firings |
| Email arrives but no Chatter post appears (or vice versa)                    | Chatter Feed Tracking isn't enabled for the watched object, so the `FeedItem` insert fails and is caught silently                                             | **Setup → Feed Tracking**, enable it for that object; the two channels are independent and one failing never blocks the other                                                |

---

## 17. Scan Status Reference

| Status                      | Meaning                                                                                                                      |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| **Queued**                  | Accepted; waiting for a batch execution slot.                                                                                |
| **Running**                 | Actively evaluating the user population.                                                                                     |
| **Completed**               | Finished with no warnings.                                                                                                   |
| **Completed with Warnings** | Finished, but see [§16](#16-troubleshooting-guidance) — some reasons may be incomplete.                                      |
| **Failed**                  | Could not complete (see `RAA_Error_Details__c`, sanitized).                                                                  |
| **Cancelled**               | Cancelled by the requester before/while running; the batch will not overwrite this status even if it was already mid-flight. |

`RAA_Batch_Run__c.RAA_Status__c` ([§8](features.md#8-additional-capabilities) bulk scan mode) uses
this same set of values, computed from the aggregate status of its child `RAA_Analysis__c` rows
rather than stored independently.

---

## 18. Cleanup Scheduler Setup

`RAA_CleanupScheduler` is **not** scheduled automatically on install. To enable it:

```apex
System.schedule('RAA Nightly Cleanup', '0 0 2 * * ?', new RAA_CleanupScheduler());
```

Run once from **Setup → Apex → Execute Anonymous** (or via `sf apex run`). It deletes completed
analyses (cascading to their results and reasons) older than `RAA_Retention_Days__c`; set that
field to 0 to disable cleanup without unscheduling the job.

---

## 19. Recurring Scan Scheduler Setup

`RAA_RecurringScanScheduler` ([§8](features.md#8-additional-capabilities)) is **not** scheduled
automatically on install — subscriptions created via `raaSubscriptions` only register the request;
nothing runs until an admin schedules it:

```apex
System.schedule('RAA Recurring Scan Cycle', '0 0 * * * ?', new RAA_RecurringScanScheduler());
```

Run once from **Setup → Apex → Execute Anonymous** (or via `sf apex run`). The cron expression above
fires hourly; pick an interval that matches how promptly subscribers need to know about changes
versus the org's overall async Apex load. Every firing processes up to
`RAA_RecurringScanScheduler.MAX_SUBSCRIPTIONS_PER_RUN` (200) active subscriptions in one pass. See
[§8](features.md#8-additional-capabilities)'s "Scheduled recurring scans" entry for the two-cycle
start-then-diff design and why a notification always lags the scan that produced it by exactly one
firing.

---

## 20. Upgrade Considerations for an Unmanaged Package

Unmanaged packages have no upgrade path — a new version is a brand-new package install, and
existing customizations (list views, page layout placements, additional field permissions) are not
automatically carried forward. Before re-uploading a new version:

- Export/back up `RAA_Analysis__c` / `RAA_Access_Result__c` / `RAA_Access_Reason__c` /
  `RAA_Batch_Run__c` / `RAA_Scan_Subscription__c` data if it needs to survive, since reinstalling
  does not touch existing data but a full uninstall would.
- Re-verify field-level security on the permission set after any new fields are added upstream.
- `RAA_Settings__mdt.RAA_Default` values are metadata, not data — they will be reset to the
  package's shipped defaults on a fresh install of a new version.

---

## 21. Sharing Change Monitor Setup

`RAA_SharingChangeMonitor` ([§8](features.md#8-additional-capabilities)) is **not** scheduled
automatically on install — without scheduling it, subscriptions are only ever re-scanned on
`RAA_RecurringScanScheduler`'s own regular cadence ([§19](#19-recurring-scan-scheduler-setup)),
never in reaction to a sharing change:

```apex
System.schedule('RAA Sharing Change Monitor', '0 15 * * * ?', new RAA_SharingChangeMonitor());
```

Run once from **Setup → Apex → Execute Anonymous** (or via `sf apex run`). The cron expression above
fires hourly, offset 15 minutes from the top of the hour so it doesn't necessarily contend with
`RAA_RecurringScanScheduler`'s own job for the same execution slot; any interval is valid, since each
firing only looks back to its own previous firing (or a 60-minute default on the very first run) —
see [§1](architecture.md#1-architecture-overview) for exactly which `SetupAuditTrail` actions and
sections it treats as sharing-relevant. This job is independent of, and complementary to, §19:
scheduling only one of the two still gives you recurring scans, just without the
sharing-change-triggered immediate re-scan.
