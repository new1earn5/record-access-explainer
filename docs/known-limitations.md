[← Back to README](../README.md)

## 5. Known Limitations

1. **Restriction rules are not evaluated by `UserRecordAccess`.** It reflects the record-level
   sharing model but does not account for restriction rules, which can further narrow what a user
   actually sees. `RAA_RestrictionRuleChecker` ([§8](features.md#8-additional-capabilities))
   best-effort detects _whether any are active_ on the scanned object and surfaces a count-aware
   warning when it can determine one — but this is a presence check, not an evaluation of which
   specific users are restricted, and it degrades to silence (not an error) in any org/API context
   where `RestrictionRule` isn't queryable via plain SOQL. The UI still displays a persistent
   banner regardless.
2. **Sharing recalculation timing.** Recently changed roles, groups, or sharing rules may not be
   fully reflected in `UserRecordAccess` until Salesforce finishes its asynchronous recalculation.
   `RAA_SharingRecalculationChecker` ([§8](features.md#8-additional-capabilities)) checks
   `AsyncApexJob` for an in-progress `SharingRecalculation` job at scan time and raises an active
   warning when one is running: a real, checked signal for that specific scan, not just a standing
   disclaimer. The UI banner discloses the general limitation regardless of whether one was
   detected running.
3. **Muting permission sets are not represented.** `MutingPermissionSet` does not expose a
   queryable field linking it back to a specific `PermissionSetGroup` or `PermissionSet` in the
   current API — this was verified directly against a live org's schema. Permission-set-group
   reasons should be read as the group's nominal (not muting-adjusted) permissions.
4. **The organization-wide default value itself cannot be retrieved.** See
   [§1](architecture.md#1-architecture-overview) — there is no supported non-callout API for it.
   `RAA_OrgWideDefaultAnalyzer` always reports this honestly rather than guessing.
5. **Account/Opportunity/Case Teams and Enterprise Territory Management are optional features.**
   `RAA_TeamAnalyzer` and `RAA_TerritoryAnalyzer` detect their availability dynamically and
   contribute nothing (not an error) when a feature was never enabled in the target org. This also
   means Apex code coverage for those two classes is necessarily lower in an org where the
   features are off (see [§10 in the README](../README.md#10-test-lint-and-format-execution-instructions))
   — the "feature unavailable" branch is fully tested; the "feature enabled" branches cannot be
   exercised without a licensed feature toggle.
6. **"Roles and Subordinates", "Territory", and "Territory and Subordinates" group principals**
   referenced by a share row are not backed by `GroupMember` rows at all (Salesforce computes their
   membership dynamically), so `RAA_GroupGraphResolver` cannot resolve through them; when a share
   row's principal is one of those types, the user still needs independent confirmation from
   `RAA_RoleHierarchyAnalyzer` or `RAA_TerritoryAnalyzer` to get a reason — otherwise it falls
   through to Unresolved, which is the honest outcome.
7. **Maximum group nesting depth and parent-chain depth are configurable but finite**
   (`RAA_Settings__mdt`). A path that would require exceeding either limit is not resolved and
   contributes to warnings.
