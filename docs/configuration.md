[← Back to README](../README.md)

## 14. Configuring `RAA_Settings__mdt`

Setup → Custom Metadata Types → RAA Settings → Manage Records → **RAA_Default**. All fields are
editable in place; no deployment is required to change them:

| Field                     | Default       | Purpose                                                                                                                                       |
| ------------------------- | ------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Default Batch Scope       | 20            | Users processed per `execute()` chunk                                                                                                         |
| Max Group Depth           | 6             | Nested public-group traversal limit                                                                                                           |
| Max Parent Depth          | 5             | Controlled-by-parent recursion limit                                                                                                          |
| Retention Days            | 90            | Age (days) after which `RAA_CleanupScheduler` deletes a completed analysis; 0 disables cleanup                                                |
| Default Include External  | false         | Pre-fills the "Include external users" checkbox                                                                                               |
| Default Include Inactive  | false         | Pre-fills the "Include inactive users" checkbox                                                                                               |
| Max Users Per Scan        | 0 (unlimited) | Scans that would exceed this are rejected before any batch job starts                                                                         |
| Max Records Per Bulk Run  | 200           | A bulk scan submission ([§8](features.md#8-additional-capabilities)) larger than this is rejected before any queueable job starts             |
| Max Records Per User Scan | 200           | Reverse "by user" mode's ([§8](features.md#8-additional-capabilities)) implicit record-limit ceiling when no explicit record ID list is given |
