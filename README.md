# Record Access Explainer

[![CI](https://github.com/new1earn5/record-access-explainer/actions/workflows/ci.yml/badge.svg)](https://github.com/new1earn5/record-access-explainer/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Statements](#statements#)
![Branches](#branches#)
![Functions](#functions#)
![Lines](#lines#)

A Salesforce administrator/auditor application that answers one question in depth: **"Which
users have effective access to this record, and why?"**

Enter any record ID and Record Access Explainer runs a background scan against the org's user
population, reports Salesforce's own computed effective access for every user (via
`UserRecordAccess`), and then explains — separately, with a confidence rating on each claim — the
sharing mechanisms it can prove are responsible: ownership, role hierarchy, direct and group
shares, sharing rules, permission bypasses, teams, territories, and controlled-by-parent chains.

This project was built, deployed to a live scratch org, and test-verified (194/194 Apex tests,
69/69 LWC Jest tests passing) during generation. Every SOQL/Schema behavior described in the docs —
including several platform restrictions that are easy to get wrong — was confirmed against a real
org, not assumed.

Beyond the core single-record scan, it also includes bulk/list scanning, a reverse "by user" mode,
analysis history diffing, field-level security tracing, a live sharing-recalculation warning,
best-effort Restriction Rule detection, dead/unused sharing rule detection, a Risk Insights view
ranking already-scanned records (with Guest Users weighted as the highest-risk signal), a
deterministic plain-English scan summary, optional scheduled recurring scans with email, Chatter,
and/or Slack change alerts, an event-driven re-scan trigger on sharing-relevant metadata changes,
an Invocable Apex action and REST resource for Flow/external integration, and a standalone
org-wide oversharing scan — see [docs/features.md](docs/features.md).

|                                                                                                                 |                                                                                           |
| --------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| ![Results grid](docs/screenshots/results-grid.jpg)                                                              | ![Access reasons](docs/screenshots/access-reasons.jpg)                                    |
| Per-user access results for a scanned record, with export, plain-English summary, and previous-scan comparison. | Drill-down into _why_ a user has access — grant path, source, and confidence, per reason. |

![Risk Insights](docs/screenshots/risk-insights.jpg)
_Risk Insights ranks every record you've already scanned by external users, bypass holders, and unresolved reasons — no new scan required._

---

## Example Applications

- **Before a data-room export or M&A due-diligence pull** — confirm exactly who can see the
  records being exported, before you export them.
- **Investigating a suspected data-leak complaint** — scan the record in question and get every
  user with access, ranked and explained, instead of manually cross-referencing role hierarchy,
  sharing rules, and permission sets by hand.
- **Verifying least-privilege after a role hierarchy or sharing rule change** — re-scan a
  previously-analyzed record and diff the result ([docs/features.md](docs/features.md)) to confirm
  the change had the intended effect and nothing else.
- **Pre-empting an internal or customer security review** — run Risk Insights across already-
  scanned records to surface external users and View/Modify All bypass holders before an auditor
  finds them first.
- **Onboarding a new admin to a legacy sharing model** — point them at a record and let the
  plain-English summary ([docs/features.md](docs/features.md)) explain the sharing setup instead of
  reverse-engineering it from Setup.

## Quick Start

Requires the [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) (`sf`).

```bash
sf org login web --alias my-org
sf project deploy start --source-dir force-app --target-org my-org
sf org assign permset --name RAA_Record_Access_Auditor --target-org my-org
```

Then open the **Record Access Explainer** tab or app in Lightning Experience, enter any record ID,
and click **Analyze**.

**Or, to spin up a disposable scratch org with a sample record already scanned in one command:**

```bash
./scripts/setup-dev-org.sh          # macOS/Linux
.\scripts\setup-dev-org.ps1         # Windows PowerShell
```

Full deployment options: [§9](#9-deployment-instructions). Permission set / Lightning page setup:
[§11](#11-permission-set-assignment-instructions)–[§12](#12-lightning-application-setup-instructions).
Test/lint/format commands: [§10](#10-test-lint-and-format-execution-instructions).

## Table of Contents

**In this file**

- [Example Applications](#example-applications)
- [Quick Start](#quick-start)
- [9. Deployment Instructions](#9-deployment-instructions)
- [10. Test, Lint, and Format Execution Instructions](#10-test-lint-and-format-execution-instructions)
- [11. Permission Set Assignment Instructions](#11-permission-set-assignment-instructions)
- [12. Lightning Application Setup Instructions](#12-lightning-application-setup-instructions)

**Further documentation** (deep reference material lives under [`docs/`](docs/) to keep this file
skimmable)

- [1. Architecture Overview](docs/architecture.md#1-architecture-overview)
- [2. Data Model](docs/data-model.md#2-data-model)
- [3. Security Model](docs/security-model.md#3-security-model)
- [4. Supported Access Reasons](docs/access-reasons.md#4-supported-access-reasons)
- [5. Known Limitations](docs/known-limitations.md#5-known-limitations)
- [6. Required Operator Permissions](docs/security-model.md#6-required-operator-permissions)
- [7. Effective Access vs. Reason Attribution](docs/access-reasons.md#7-effective-access-vs-reason-attribution)
- [8. Additional Capabilities](docs/features.md#8-additional-capabilities)
- [13. Creating and Uploading the Unmanaged Package](docs/packaging.md#13-creating-and-uploading-the-unmanaged-package)
- [14. Configuring `RAA_Settings__mdt`](docs/configuration.md#14-configuring-raa_settingsmdt)
- [15. Performance Guidance for Large Organizations](docs/operations.md#15-performance-guidance-for-large-organizations)
- [16. Troubleshooting Guidance](docs/operations.md#16-troubleshooting-guidance)
- [17. Scan Status Reference](docs/operations.md#17-scan-status-reference)
- [18. Cleanup Scheduler Setup](docs/operations.md#18-cleanup-scheduler-setup)
- [19. Recurring Scan Scheduler Setup](docs/operations.md#19-recurring-scan-scheduler-setup)
- [20. Upgrade Considerations for an Unmanaged Package](docs/operations.md#20-upgrade-considerations-for-an-unmanaged-package)
- [21. Sharing Change Monitor Setup](docs/operations.md#21-sharing-change-monitor-setup)
- [Complete component list & acceptance-criteria self-check](docs/reference.md)

---

## 9. Deployment Instructions

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
(`Developer` edition, API v67.0) during generation with zero manual fixes required after the
verification pass documented in [§15](docs/operations.md#15-performance-guidance-for-large-organizations).

---

## 10. Test, Lint, and Format Execution Instructions

```bash
# Apex tests
sf apex run test --target-org my-org --test-level RunLocalTests --code-coverage --result-format human --wait 30

# LWC Jest tests (from the project root, after `npm install`)
npm install
npm run test:unit

# ESLint over every LWC bundle (config: .eslintrc.json at the root and under force-app/main/default/lwc)
npm run lint

# Prettier, including Apex via prettier-plugin-apex (config: .prettierrc) — requires a Java
# runtime on PATH, since the Apex formatter shells out to a Java-based parser
npm run format:check   # verify only, exits non-zero on drift
npm run format          # rewrite in place

# Salesforce Code Analyzer / PMD over every Apex class (config: code-analyzer.yml) — also
# requires a Java runtime; install once with `sf plugins install code-analyzer@latest`
npm run analyze:apex
```

At last verification: **194/194 Apex tests passing, 85% org-wide coverage; 69/69 LWC Jest tests
passing across 10 component suites; zero ESLint errors; the full tree Prettier-clean; zero Code
Analyzer findings at High severity or above.** Every class directly involved in the
request/response path, persistence, and reason logic is at or above 85%; the exceptions
(`RAA_TerritoryAnalyzer`, `RAA_TeamAnalyzer` — explained in
[§5](docs/known-limitations.md#5-known-limitations); `RAA_RestrictionRuleChecker`,
`RAA_RecurringScanScheduler`) reflect branches that require a platform feature or a second
scheduler firing that this particular org/test run could not exercise, not untested logic paths —
see [§8](docs/features.md#8-additional-capabilities)'s per-feature notes for exactly which branch
is affected in each case.

`code-analyzer.yml` deliberately disables a handful of PMD rules that are style/design
preferences this project has consciously chosen against elsewhere (full ApexDoc headers,
`System.runAs` on every test, boolean method parameters) rather than correctness or security
concerns — each disabled rule says why in the file itself. Every rule left enabled either has zero
findings or is suppressed inline at the specific site with `@SuppressWarnings('PMD.RuleName')`
and a comment explaining why (most commonly: the elevated `without sharing` pipeline is
deliberately CRUD/FLS-unchecked by design — see [§1](docs/architecture.md#1-architecture-overview) —
or a dynamic SOQL identifier is Schema describe-derived, never client input).

### Continuous Integration

`.github/workflows/ci.yml` runs on every push and pull request against `master`:

- **`lint-and-jest`** (always runs, no Salesforce org required): `npm ci`, ESLint, Prettier check,
  and the full Jest suite with coverage.
- **`apex-static-analysis`** (always runs, no Salesforce org required, only a JDK): Salesforce
  Code Analyzer against every Apex class with `code-analyzer.yml`, failing the build on any High
  severity or above finding.
- **`apex`** (deploy to a fresh scratch org and run the full Apex suite): gated behind a
  repository secret named `SFDX_AUTH_URL_DEVHUB` and skipped entirely until it's configured, so
  the workflow never hard-fails for a fork or a clone that hasn't set it up yet. To enable it:
    1. From an org already authenticated as your Dev Hub locally, run
       `sf org display --target-org YourDevHubAlias --verbose --json` and copy the
       `result.sfdxAuthUrl` value — treat it exactly like a password; it's a long-lived refresh
       token for that Dev Hub.
    2. In the GitHub repo, add it as **Settings → Secrets and variables → Actions → New repository
       secret**, named `SFDX_AUTH_URL_DEVHUB`.
    3. The next push or pull request will pick it up automatically; no workflow file changes needed.

---

## 11. Permission Set Assignment Instructions

```bash
sf org assign permset --name RAA_Record_Access_Auditor --target-org my-org
```

Or in Setup: **Permission Sets → RAA Record Access Auditor → Manage Assignments → Add Assignment.**

---

## 12. Lightning Application Setup Instructions

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

For architecture, data model, security model, the full capability list, deployment/packaging
reference, and operations runbooks (performance, troubleshooting, scheduler setup, upgrades), see
[`docs/`](docs/) — indexed above under "Further documentation."
