[← Back to README](../README.md)

## 13. Creating and Uploading the Unmanaged Package

Source generation alone **cannot produce an installation URL** — that only exists once a package
version has been uploaded from inside a real Salesforce packaging org. To create one:

1. Deploy this project to your packaging org: `sf project deploy start --source-dir force-app --target-org my-packaging-org`.
2. In that org, open **Setup → Package Manager**.
3. Click **New** to create an unmanaged package named **Record Access Explainer**.
4. Click **Add** and add every component listed in `manifest/package.xml` (all Apex classes, all
   five custom objects, `RAA_Settings__mdt` and its `RAA_Default` record, the custom permission,
   the permission set, the tab, the application, the Lightning page, all seven Lightning web
   components, and the five custom labels).
5. Click **Verify Dependencies** to confirm nothing is missing.
6. Click **Upload**, choose a release type, and Salesforce will generate the installation URL.
