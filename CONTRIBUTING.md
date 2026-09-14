# Contributing

Thanks for considering a contribution to Record Access Explainer.

## Getting set up

1. Fork and clone the repo.
2. Authenticate the Salesforce CLI against a Dev Hub, then create a scratch org and deploy:
    ```
    sf org create scratch --definition-file config/project-scratch-def.json --alias rae-dev --set-default
    sf project deploy start --source-dir force-app --target-org rae-dev
    sf org assign permset --name RAA_Record_Access_Auditor --target-org rae-dev
    ```
3. Install Node dependencies for linting and LWC tests:
    ```
    npm install
    ```

See [README §10](README.md#10-test-lint-and-format-execution-instructions) for the full test/lint/format command reference.

## Before opening a PR

Run the same checks CI runs:

```
npm run lint
npm run format:check
npm run test:unit:coverage
sf apex run test --target-org rae-dev --test-level RunLocalTests --code-coverage --result-format human
```

- New Apex classes and LWCs should come with tests; this project keeps 100% Apex coverage and high
  LWC Jest coverage, and CI enforces the Apex side via `RunLocalTests`.
- Run `npm run format` (Prettier, including Apex via `prettier-plugin-apex`) before committing —
  `format:check` gates CI.
- Keep `with sharing` / `without sharing` boundaries intentional. If you're touching anything in
  the scan pipeline, re-read [README §3 "Security Model"](README.md#3-security-model) first — the
  system-mode/user-mode split there is load-bearing, not incidental.

## Reporting bugs / suggesting features

Open a GitHub issue. For anything you believe is a security issue (incorrect access reporting, a
permission bypass, etc.), see [SECURITY.md](SECURITY.md) instead — please don't file those
publicly.

## Scope note

This project deliberately does **not** try to account for Restriction Rules (best-effort detection
only — see [README §5 "Known Limitations"](README.md#5-known-limitations)) and does not claim to be
a replacement for Salesforce's own effective-access computation, only an explanation of it. PRs that
expand _detected reasons_ are welcome; PRs that make the tool claim more certainty than the
platform actually gives it will need a strong justification.
