/**
 * Optional scheduled cleanup job that deletes completed analyses (and, via master-detail
 * cascade, their child results and reasons) older than the retention period configured in
 * RAA_Settings__mdt. Not scheduled automatically on install; an administrator opts in by
 * scheduling it (see README). A retention of zero days disables cleanup entirely.
 *
 * The retention period can optionally be overridden at construction time (used by unit tests,
 * since custom metadata values cannot be changed at runtime); production scheduling always uses
 * the no-argument constructor, which reads RAA_Settings__mdt.
 */
// Deliberately without sharing and CRUD/FLS-unchecked: a scheduled job deleting the package's
// own data (see README.md §1, "Batch Apex runs in system mode"), not reachable from the client.
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class RAA_CleanupScheduler implements Schedulable {
    @TestVisible
    private static final Integer MAX_ROWS_PER_RUN = 200;

    private final Integer retentionDaysOverride;

    public RAA_CleanupScheduler() {
        this.retentionDaysOverride = null;
    }

    @TestVisible
    private RAA_CleanupScheduler(Integer retentionDaysOverride) {
        this.retentionDaysOverride = retentionDaysOverride;
    }

    public void execute(SchedulableContext sc) {
        Integer retentionDays = retentionDaysOverride != null
            ? retentionDaysOverride
            : new RAA_SettingsService().retentionDays;
        if (retentionDays <= 0) {
            return;
        }

        Datetime threshold = System.now().addDays(-retentionDays);
        RAA_AnalysisRepository repository = new RAA_AnalysisRepository();
        List<RAA_Analysis__c> expired = repository.findCompletedOlderThan(threshold, MAX_ROWS_PER_RUN);
        if (expired.isEmpty()) {
            return;
        }

        Database.delete(expired, false);
    }
}
