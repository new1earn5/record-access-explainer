# Security Policy

Record Access Explainer runs in system mode (`without sharing`) over Salesforce's own access-control
data — `UserRecordAccess`, sharing rows, permission sets, role hierarchy, and related objects — so a
flaw here has an outsized impact: it could leak who has access to what, or misreport it. Reports are
taken seriously and triaged promptly.

## Reporting a Vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Instead, use GitHub's private vulnerability reporting for this repository:

1. Go to the [Security tab](https://github.com/new1earn5/record-access-explainer/security)
2. Click **Report a vulnerability**

This opens a private advisory visible only to the maintainer, so the issue can be discussed and fixed
before any public disclosure.

Please include, where relevant:

- The affected component (Apex class, LWC, or object/permission set)
- Steps to reproduce, including org type (scratch/dev/sandbox) and any non-default configuration
- The potential impact — e.g., incorrect access reporting, unintended data exposure, or a permission
  check bypass

## Scope

In scope: the Apex, LWC, and metadata in `force-app/`, and the permission model they rely on
(custom permission gating, `with`/`without sharing` boundaries, and the object/field-level security
declared in `RAA_Record_Access_Auditor.permissionset-meta.xml`).

Out of scope: vulnerabilities in Salesforce's own platform (`UserRecordAccess`, sharing engine,
etc.) — please report those directly to [Salesforce Security](https://help.salesforce.com/s/articleView?id=xcloud.security_pub_disclosure.htm).

## Supported Versions

This project does not follow a formal release/patch-branch policy yet; security fixes are applied
to `master` and covered by the latest tagged release.
