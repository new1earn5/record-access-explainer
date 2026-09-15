[← Back to README](../README.md)

## 2. Data Model

All five objects are package-owned, **organization-wide default: Private**, and are not meant to
be seen by ordinary users.

### `RAA_Analysis__c` (one row per scan)

Auto-number `RAA-{0000}`. Fields: `RAA_Record_Id__c`, `RAA_Object_API_Name__c`,
`RAA_Record_Display_Name__c`, `RAA_Status__c` (picklist: Queued / Running / Completed / Completed
with Warnings / Failed / Cancelled), `RAA_Requested_By__c` (lookup User), `RAA_Requested_At__c`,
`RAA_Started_At__c`, `RAA_Completed_At__c`, `RAA_Async_Job_Id__c`, `RAA_Total_Users__c`,
`RAA_Processed_Users__c`, `RAA_Users_With_Access__c`, `RAA_Include_External_Users__c`,
`RAA_Include_Inactive_Users__c`, `RAA_Warnings__c`, `RAA_Error_Details__c`, `RAA_Is_Complete__c`,
`RAA_Sharing_Hygiene_Notes__c` (LongTextArea — deliberately separate from `RAA_Warnings__c`; see
[§8](features.md#8-additional-capabilities)'s dead-sharing-rule-target detection).

### `RAA_Access_Result__c` (one row per user per analysis)

Master-detail to `RAA_Analysis__c` (sharing follows the parent — this is _why_ the object has no
generated `RAA_Access_Result__Share` table, verified against a live org). Fields:
`RAA_User__c`, `RAA_User_Name__c`, `RAA_Username__c`, `RAA_User_Type__c`, `RAA_Profile_Name__c`,
`RAA_Is_Active__c`, `RAA_Max_Access_Level__c`, `RAA_Has_Read_Access__c`, `RAA_Has_Edit_Access__c`,
`RAA_Has_Delete_Access__c`, `RAA_Has_Transfer_Access__c`, `RAA_Has_All_Access__c`,
`RAA_Reason_Summary__c`, `RAA_Overall_Confidence__c`, `RAA_Has_Unresolved_Reason__c`, and
`RAA_Unique_Key__c` — a Text(60) **External ID + Unique** field (`{AnalysisId}-{UserId}`) that the
batch upserts against, so a retried chunk can never create a duplicate result for the same user.

### `RAA_Access_Reason__c` (one row per detected access path)

Master-detail to `RAA_Access_Result__c`. Fields: `RAA_Category__c` (Ownership / Role Hierarchy /
Direct Share / Group Share / Sharing Rule / Permission / Team / Territory / Implicit / Parent
Controlled / Organization-Wide Default / Unresolved), `RAA_Access_Level__c`, `RAA_Confidence__c`
(High / Medium / Low), `RAA_Is_Direct__c`, `RAA_Source_Name__c`, `RAA_Source_Id__c`,
`RAA_Source_Object__c`, `RAA_Principal_Id__c`, `RAA_Principal_Type__c`, `RAA_Row_Cause__c`,
`RAA_Grant_Path__c`, `RAA_Explanation__c`, `RAA_Evidence__c`.

### `RAA_Batch_Run__c` (one row per bulk scan submission — [§8](features.md#8-additional-capabilities))

Fields: `RAA_Requested_By__c` (lookup User), `RAA_Requested_At__c`, `RAA_Object_API_Name__c`,
`RAA_Total_Records__c`, `RAA_Status__c` (picklist: Queued / Running / Completed / Completed with
Warnings / Failed / Cancelled — computed from the status of its child analyses, not stored
independently), `RAA_Include_External_Users__c`, `RAA_Include_Inactive_Users__c`,
`RAA_Record_Ids__c` (LongTextArea 32768, the originally submitted list). Each individual record's
scan is a normal `RAA_Analysis__c` row, linked back via `RAA_Analysis__c.RAA_Batch_Run__c`.

### `RAA_Scan_Subscription__c` (one row per "watch this record" subscription — [§8](features.md#8-additional-capabilities))

Fields: `RAA_Record_Id__c`, `RAA_Object_API_Name__c`, `RAA_Record_Display_Name__c`,
`RAA_Subscriber__c` (lookup User), `RAA_Is_Active__c` (default true),
`RAA_Include_External_Users__c`, `RAA_Include_Inactive_Users__c`, `RAA_Last_Analysis__c` (lookup
`RAA_Analysis__c` — the baseline used for diffing), `RAA_Last_Run_At__c`,
`RAA_Notify_On_Change__c` (default true), `RAA_Post_To_Chatter__c` (default false),
`RAA_Post_To_Slack__c` (default false), `RAA_Slack_Webhook_URL__c` (EncryptedText(175), masked —
required only when `RAA_Post_To_Slack__c` is true; validated by `RAA_SlackNotifier` to start with
`https://hooks.slack.com/` before any callout is attempted; see [§8](features.md#8-additional-capabilities)),
`RAA_Pending_Analysis__c` (lookup `RAA_Analysis__c` — the scan started this cycle, diffed against
the baseline on the _next_ scheduler firing).

### `RAA_Settings__mdt` (custom metadata type, one packaged record: `RAA_Default`)

`RAA_Default_Batch_Scope__c` (20), `RAA_Max_Group_Depth__c` (6), `RAA_Max_Parent_Depth__c` (5),
`RAA_Retention_Days__c` (90), `RAA_Default_Include_External__c` (false),
`RAA_Default_Include_Inactive__c` (false), `RAA_Max_Users_Per_Scan__c` (0 = unlimited),
`RAA_Max_Records_Per_Bulk_Run__c` (200), `RAA_Max_Records_Per_User_Scan__c` (200).
