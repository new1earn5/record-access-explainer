---
name: Feature request
about: Suggest a new scan capability, detected access reason, or integration
title: ""
labels: enhancement
assignees: ""
---

## What's missing

<!-- What can't you do today, or what access reason/risk signal isn't being detected? -->

## Why it matters

<!-- What decision or investigation does this unblock? Concrete scenario helps more than "would
be nice to have". -->

## Proposed behavior

<!-- What should the scan report, or what should the new capability do? -->

## Scope check

This project deliberately does not try to account for Restriction Rules beyond best-effort
detection, and does not claim more certainty than Salesforce's own effective-access computation
actually gives it (see [§5 "Known Limitations"](../../docs/known-limitations.md#5-known-limitations)). If
this request would require claiming more certainty than the platform provides, say so here — it
doesn't rule the request out, but it changes how it'd need to be built.
