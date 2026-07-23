/**
 * Loads RAA_Settings__mdt with safe fallback defaults so the package still functions
 * (conservatively) even if the packaged default custom metadata record is somehow missing.
 */
public with sharing class RAA_SettingsService {
    private static final Integer FALLBACK_BATCH_SCOPE = 20;
    private static final Integer FALLBACK_GROUP_DEPTH = 6;
    private static final Integer FALLBACK_PARENT_DEPTH = 5;
    private static final Integer FALLBACK_RETENTION_DAYS = 90;
    private static final Integer FALLBACK_MAX_USERS = 0;
    private static final Integer FALLBACK_MAX_RECORDS_PER_BULK_RUN = 200;
    private static final Integer FALLBACK_MAX_RECORDS_PER_USER_SCAN = 200;

    private static RAA_Settings__mdt cachedSettings;

    public Integer defaultBatchScope { get; private set; }
    public Integer maxGroupDepth { get; private set; }
    public Integer maxParentDepth { get; private set; }
    public Integer retentionDays { get; private set; }
    public Boolean defaultIncludeExternal { get; private set; }
    public Boolean defaultIncludeInactive { get; private set; }
    public Integer maxUsersPerScan { get; private set; }
    public Integer maxRecordsPerBulkRun { get; private set; }
    public Integer maxRecordsPerUserScan { get; private set; }

    public RAA_SettingsService() {
        RAA_Settings__mdt settings = loadSettings();
        this.defaultBatchScope = coerce(settings?.RAA_Default_Batch_Scope__c, FALLBACK_BATCH_SCOPE);
        this.maxGroupDepth = coerce(settings?.RAA_Max_Group_Depth__c, FALLBACK_GROUP_DEPTH);
        this.maxParentDepth = coerce(settings?.RAA_Max_Parent_Depth__c, FALLBACK_PARENT_DEPTH);
        this.retentionDays = coerce(settings?.RAA_Retention_Days__c, FALLBACK_RETENTION_DAYS);
        this.defaultIncludeExternal = settings != null ? settings.RAA_Default_Include_External__c : false;
        this.defaultIncludeInactive = settings != null ? settings.RAA_Default_Include_Inactive__c : false;
        this.maxUsersPerScan = coerce(settings?.RAA_Max_Users_Per_Scan__c, FALLBACK_MAX_USERS);
        this.maxRecordsPerBulkRun = coerce(
            settings?.RAA_Max_Records_Per_Bulk_Run__c,
            FALLBACK_MAX_RECORDS_PER_BULK_RUN
        );
        this.maxRecordsPerUserScan = coerce(
            settings?.RAA_Max_Records_Per_User_Scan__c,
            FALLBACK_MAX_RECORDS_PER_USER_SCAN
        );
    }

    private static Integer coerce(Decimal value, Integer fallback) {
        return value == null ? fallback : Integer.valueOf(value);
    }

    private static RAA_Settings__mdt loadSettings() {
        if (cachedSettings == null) {
            List<RAA_Settings__mdt> rows = [
                SELECT
                    RAA_Default_Batch_Scope__c,
                    RAA_Max_Group_Depth__c,
                    RAA_Max_Parent_Depth__c,
                    RAA_Retention_Days__c,
                    RAA_Default_Include_External__c,
                    RAA_Default_Include_Inactive__c,
                    RAA_Max_Users_Per_Scan__c,
                    RAA_Max_Records_Per_Bulk_Run__c,
                    RAA_Max_Records_Per_User_Scan__c
                FROM RAA_Settings__mdt
                WHERE DeveloperName = 'RAA_Default'
                LIMIT 1
            ];
            if (!rows.isEmpty()) {
                cachedSettings = rows[0];
            }
        }
        return cachedSettings;
    }
}
