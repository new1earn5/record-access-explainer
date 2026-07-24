/**
 * Checks whether an org-wide sharing recalculation job is currently queued or running, via the
 * standard (non-Tooling) AsyncApexJob object. Sharing recalculation is not scoped to a single
 * object in a way that's queryable, so this is an org-wide signal rather than an object-specific
 * one - still far more useful than the static "may not be reflected yet" disclaimer alone, since
 * it tells an auditor definitively when a scan's results might already be stale.
 */
// Deliberately without sharing and CRUD/FLS-unchecked: reads AsyncApexJob, a system object with
// no meaningful FLS concept, reached only through the with-sharing controller's permission gate.
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class RAA_SharingRecalculationChecker {
    public Boolean isRecalculationInProgress() {
        List<AggregateResult> results = [
            SELECT COUNT(Id) total
            FROM AsyncApexJob
            WHERE JobType = 'SharingRecalculation' AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
        ];
        if (results.isEmpty()) {
            return false;
        }
        Object total = results[0].get('total');
        return total != null && (Integer) total > 0;
    }
}
