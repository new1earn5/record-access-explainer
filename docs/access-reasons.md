[← Back to README](../README.md)

## 4. Supported Access Reasons

| Category                  | Mechanism                                                                                                                                                                                                         | Confidence                                                                                                                                                                                      |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ownership                 | Direct user ownership                                                                                                                                                                                             | High                                                                                                                                                                                            |
| Ownership                 | Queue ownership + queue membership (via group graph)                                                                                                                                                              | High                                                                                                                                                                                            |
| Role Hierarchy            | User's role is above the owner's role                                                                                                                                                                             | **High on standard objects** (hierarchy grant cannot be disabled there), **Medium on custom objects** (the "Grant Access Using Hierarchies" checkbox state is not exposed by any supported API) |
| Direct Share              | Manual (or other non-rule, non-team) share row directly to a user                                                                                                                                                 | High                                                                                                                                                                                            |
| Group Share               | Share row to a public group/queue/role group the user belongs to, including nested groups                                                                                                                         | High                                                                                                                                                                                            |
| Sharing Rule              | Share row with `RowCause = 'Rule'`                                                                                                                                                                                | High that access is real; the exact rule name is **never claimed** — the reason literally says "exact rule name unavailable from the share row" per the platform's own limitation               |
| Implicit                  | Share row with `RowCause = 'ImplicitChild'/'ImplicitParent'`                                                                                                                                                      | Medium                                                                                                                                                                                          |
| Permission                | View All Data / Modify All Data (profile or permission set)                                                                                                                                                       | High                                                                                                                                                                                            |
| Permission                | View All Records / Modify All Records on the specific object                                                                                                                                                      | High                                                                                                                                                                                            |
| Team                      | Account Team / Opportunity Team / Case Team membership, with role                                                                                                                                                 | High                                                                                                                                                                                            |
| Territory                 | Direct or ancestor (subordinate) territory assignment via `UserTerritory2Association`                                                                                                                             | High (direct) / Medium (via subordinate territory)                                                                                                                                              |
| Parent Controlled         | Recursive re-analysis of the controlling master-detail parent (Ownership, Role Hierarchy, Share Row, Team, Territory only — not Permission, which was already evaluated once against the child's own object type) | Inherited from the underlying reason                                                                                                                                                            |
| Organization-Wide Default | Always Low, honest disclaimer — see [§1](architecture.md#1-architecture-overview)                                                                                                                                 | Low                                                                                                                                                                                             |
| Unresolved                | `UserRecordAccess` confirms access but nothing above explains it                                                                                                                                                  | Low                                                                                                                                                                                             |

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

## 7. Effective Access vs. Reason Attribution

**Effective access** (Read / Edit / Delete / Transfer / All Access / Max Access Level) is
Salesforce's own computed answer, read from `UserRecordAccess` — authoritative and never guessed.

**Reason attribution** is this package's best-effort explanation of _why_ that access exists,
built by correlating share rows, groups, roles, permission sets, teams, territories, and parent
chains after the fact. It is inherently an approximation of the sharing engine's internal logic,
not the sharing engine itself. The UI and every reason record distinguish the two clearly, and a
reason's confidence level (High / Medium / Low) tells you how directly it was proven.

### vs. Salesforce's native Sharing button

Every Salesforce admin already has a built-in way to see _some_ of this: open a record, click
**Sharing**, then **Expand List**, and Salesforce shows a per-user reason label (Owner, Role,
Manual, a specific sharing rule, and so on). Record Access Explainer is not a replacement for
that — it's what it doesn't cover:

- It only lists users the object's **share table** actually names. Access coming purely from
  object/field permissions (a profile or permission set with "View All"/"Modify All" on the
  object), from an org-wide default of Public Read/Write, or from Controlled-by-Parent sharing
  isn't shown there at all — Record Access Explainer detects and attributes all of these.
- It's one record, one user population, no history. There's no bulk mode, no reverse "by user"
  lookup, no scan-to-scan diff, and nothing is persisted for later review or export.
- It gives a reason label, not a confidence rating, a grant path, or a plain-English summary — and
  there's no ranked view across every record you've looked at
  ([§8](features.md#8-additional-capabilities)'s Risk Insights).
