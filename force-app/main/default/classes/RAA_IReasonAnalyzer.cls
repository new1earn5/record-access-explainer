/**
 * Strategy interface implemented by every access-reason analyzer (ownership, role hierarchy,
 * share rows, permissions, teams, territory, parent-controlled, org-wide default, and so on).
 * Each analyzer is called once per batch chunk with the full set of candidate user IDs so it
 * can bulk-query whatever data it needs instead of querying per user.
 */
public interface RAA_IReasonAnalyzer {
    /** Short, stable name used in warnings and unresolved-reason "attempted analyzers" lists. */
    String getAnalyzerName();

    /**
     * Returns candidate reasons per user. The aggregator is responsible for discarding any
     * reason for a user who UserRecordAccess does not confirm has effective access - analyzers
     * may return candidates for users who ultimately have no effective access, and those are
     * silently dropped rather than treated as an error.
     */
    Map<Id, List<RAA_AccessReasonDTO>> analyze(RAA_AnalysisContext context, Set<Id> userIds);
}
