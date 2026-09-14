/**
 * Optional, separately-scheduled companion to RAA_RecurringScanScheduler. Not scheduled
 * automatically on install (see README); an administrator opts in, typically at a much shorter
 * interval than the main recurring-scan cycle (for example every 5 minutes vs. every 30-60).
 *
 * Salesforce exposes no trigger or Platform Event for sharing rule, role hierarchy, or
 * organization-wide default changes - Setup Audit Trail is a queryable log, not a subscribable
 * event source. This is therefore frequent *polling* of that log, not a true push-based event -
 * it should never be described as more real-time than that. What it buys over the main
 * recurring-scan cycle alone: a subscribed record gets re-scanned within this job's own interval
 * of a relevant admin change, instead of waiting for the (typically much longer) main cycle.
 *
 * Sections/actions were verified two different ways against a live scratch org during
 * development:
 *   - Role hierarchy: confirmed empirically. Inserting/updating a UserRole produces
 *     SetupAuditTrail rows with Section = 'Manage Users' and Action = 'createdrole' / 'role'
 *     respectively (deleterole is inferred from the same naming pattern, not separately
 *     confirmed). Filtered on Action specifically, not the whole 'Manage Users' section, because
 *     that section also covers unrelated changes (e.g. permission set assignment) that would
 *     otherwise cause this to fire constantly.
 *   - Sharing rules and org-wide defaults: this scratch org's edition/config couldn't produce a
 *     real sharing-rule deploy to confirm the exact Action string, so these two are filtered by
 *     Section alone ('Sharing Rules', 'Company Profile') using Salesforce's own documented Setup
 *     Audit Trail category names - coarser than the role check, but real category names, not a
 *     guess at an unverified Action string.
 */
public without sharing class RAA_SharingChangeMonitor implements Schedulable {
    @TestVisible
    private static final Set<String> ROLE_ACTIONS = new Set<String>{ 'createdrole', 'role', 'deleterole' };
    @TestVisible
    private static final Set<String> SECTION_ONLY_SECTIONS = new Set<String>{ 'Sharing Rules', 'Company Profile' };
    @TestVisible
    private static final Integer DEFAULT_LOOKBACK_MINUTES = 60;

    // Setup Audit Trail is org-global and not reset between test runs, unlike normal sObject
    // data - a fixed lookback window would pick up real historical entries from this org's own
    // admin activity (including from manual verification during development) and make "no
    // relevant change" tests flaky. This lets tests pin the window to a precise instant instead,
    // the same way RAA_PermissionChecker.testOverride sidesteps a similar untestable platform
    // dependency; it only has any effect while Test.isRunningTest() is true.
    @TestVisible
    private static Datetime testSinceWhenOverride = null;

    public void execute(SchedulableContext sc) {
        Datetime sinceWhen = determineSinceWhen(sc);
        if (!hasSharingRelevantChange(sinceWhen)) {
            return;
        }

        List<Id> subscriptionIdsToRescan = new List<Id>();
        for (RAA_Scan_Subscription__c subscription : new RAA_SubscriptionRepository().getActiveSubscriptions(200)) {
            if (subscription.RAA_Pending_Analysis__c == null) {
                subscriptionIdsToRescan.add(subscription.Id);
            }
        }
        if (!subscriptionIdsToRescan.isEmpty()) {
            System.enqueueJob(new RAA_SubscriptionScanQueueable(subscriptionIdsToRescan));
        }
    }

    @TestVisible
    private Datetime determineSinceWhen(SchedulableContext sc) {
        if (Test.isRunningTest() && testSinceWhenOverride != null) {
            return testSinceWhenOverride;
        }
        if (sc != null) {
            List<CronTrigger> triggers = [SELECT PreviousFireTime FROM CronTrigger WHERE Id = :sc.getTriggerId()];
            if (!triggers.isEmpty() && triggers[0].PreviousFireTime != null) {
                return triggers[0].PreviousFireTime;
            }
        }
        return System.now().addMinutes(-DEFAULT_LOOKBACK_MINUTES);
    }

    // Section is not a filterable SOQL field on SetupAuditTrail (confirmed by deploy-time
    // compile error when attempting it directly), so the Section/Action check happens in Apex
    // after a CreatedDate-only query, capped at MAX_ROWS_CHECKED as a governor safeguard given
    // this runs on a short, frequent schedule against an org-wide, ever-growing log.
    @TestVisible
    private static final Integer MAX_ROWS_CHECKED = 200;

    private Boolean hasSharingRelevantChange(Datetime sinceWhen) {
        for (SetupAuditTrail entry : [
            SELECT Action, Section
            FROM SetupAuditTrail
            WHERE CreatedDate > :sinceWhen
            ORDER BY CreatedDate DESC
            LIMIT :MAX_ROWS_CHECKED
        ]) {
            if (SECTION_ONLY_SECTIONS.contains(entry.Section) || ROLE_ACTIONS.contains(entry.Action)) {
                return true;
            }
        }
        return false;
    }
}
