# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/); this project does not yet cut tagged
releases, so entries are grouped by date instead of version number.

## [Unreleased]

### Added

- GitHub repo description and topics (`salesforce`, `apex`, `lwc`, `security`, `sharing`, …) for
  discoverability.
- `.github/dependabot.yml` (npm + GitHub Actions, weekly).
- `.github/ISSUE_TEMPLATE/` (bug report, feature request, and a security-issue redirect to
  [SECURITY.md](SECURITY.md)).

### Fixed

- Suppressed false-positive `ApexCRUDViolation` findings on setup-metadata-only queries (
  `ObjectPermissions`, `PermissionSet`, `User`, `PermissionSetAssignment`, `CronTrigger`,
  `SetupAuditTrail`) in `RAA_OrgWideAccessService` and `RAA_SharingChangeMonitor` — both classes
  are `without sharing` specifically to see grants/changes the running user may not personally
  hold, so `WITH USER_MODE` would have defeated their purpose.

## 2026-09-14

### Added

- Standalone org-wide oversharing scan: Profiles/Permission Sets granting View All Records,
  Modify All Records, or full object-level CRUD, filtered to grants with active holders.
- Event-driven re-scan triggered by sharing-relevant Setup Audit Trail changes (role hierarchy,
  sharing rules, org-wide defaults).
- Invocable Apex action and REST resource to expose scans to Flow and external integrations.
- Guest User as a first-class, highest-weighted risk signal.
- Slack alert channel alongside the existing email/Chatter alerts.
- Dead sharing rule detection.
- Example Applications section, a native-Sharing-button comparison, and a one-command dev/demo
  setup script.
- LICENSE, CI/license badges, and screenshots.
- SECURITY.md, CONTRIBUTING.md, and a README Quick Start + table of contents.

### Fixed

- Broken CI.

## 2026-07-24

### Added

- Salesforce Code Analyzer (PMD) with a curated ruleset, running in CI.
- Chatter feed alerts alongside email for subscription changes.
- Platform Event-based scan status push, reducing reliance on polling.
- Risk Insights view ranking already-scanned records by risk signals.
- Deterministic plain-English scan summary.

## 2026-07-23

### Added

- Initial release: single-record access scan — ownership, role hierarchy, direct/group shares,
  sharing rules, permission bypasses, teams, territories, and controlled-by-parent chains — each
  explanation carrying its own confidence rating.
- Bulk/list scanning, a reverse "by user" mode, analysis history diffing, and field-level security
  tracing.
- Best-effort Restriction Rule detection and a live sharing-recalculation warning.
- Scheduled recurring scan subscriptions.
- ESLint, Prettier, and CI/CD tooling.
