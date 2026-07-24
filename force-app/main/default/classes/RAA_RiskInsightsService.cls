/**
 * Ranks the requesting user's own already-scanned records by risk signals already present in
 * their most recent completed scan of each - no new scanning happens here, this is purely a
 * read/aggregate over existing RAA_Access_Result__c / RAA_Access_Reason__c rows. Deliberately
 * scoped to RAA_Requested_By__c = the requesting user, mirroring listMySubscriptions: since
 * RAA_Analysis__c is Private OWD, this is the same set of analyses that user could already see
 * one at a time, just ranked instead of requiring them to know which record to check.
 *
 * Three signals feed the score, each independently exposed on the DTO so the ranking is never an
 * opaque number:
 *   - externalUserCount: users with UserType other than 'Standard' who have access - the same
 *     internal/external distinction RAA_UserPopulationBuilder already uses for scan population.
 *   - bypassHolderCount: distinct users whose access includes a reason in the "Permission"
 *     category (View/Modify All Data or View/Modify All Records) - a sharing-model bypass.
 *   - unresolvedCount: users whose access RAA_ReasonAggregator could not fully attribute to a
 *     specific mechanism (RAA_Has_Unresolved_Reason__c) - an audit blind spot, not itself a risk.
 */
// Deliberately without sharing and CRUD/FLS-unchecked: reads the elevated pipeline's own
// package-owned data (see README.md §1, "Batch Apex runs in system mode"), reached only through
// the with-sharing controller's permission gate; explicitly scoped to the requesting user's own
// analyses by RAA_Requested_By__c, not broadened by the lack of a sharing check.
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class RAA_RiskInsightsService {
    @TestVisible
    private static final Integer MAX_ANALYSES_CONSIDERED = 300;
    @TestVisible
    private static final Integer MAX_RESULTS_RETURNED = 50;

    private static final Integer EXTERNAL_USER_WEIGHT = 3;
    private static final Integer BYPASS_HOLDER_WEIGHT = 2;
    private static final Integer UNRESOLVED_WEIGHT = 1;

    public List<RAA_RiskInsightDTO> getRiskInsights(Id requestedById) {
        Map<String, RAA_Analysis__c> latestByRecord = latestCompletedAnalysisPerRecord(requestedById);
        if (latestByRecord.isEmpty()) {
            return new List<RAA_RiskInsightDTO>();
        }

        Set<Id> analysisIds = new Set<Id>();
        for (RAA_Analysis__c analysis : latestByRecord.values()) {
            analysisIds.add(analysis.Id);
        }

        Map<Id, Integer> externalCountByAnalysis = new Map<Id, Integer>();
        Map<Id, Integer> unresolvedCountByAnalysis = new Map<Id, Integer>();
        for (RAA_Access_Result__c result : [
            SELECT RAA_Analysis__c, RAA_User_Type__c, RAA_Has_Unresolved_Reason__c
            FROM RAA_Access_Result__c
            WHERE RAA_Analysis__c IN :analysisIds
        ]) {
            if (result.RAA_User_Type__c != 'Standard') {
                increment(externalCountByAnalysis, result.RAA_Analysis__c);
            }
            if (result.RAA_Has_Unresolved_Reason__c) {
                increment(unresolvedCountByAnalysis, result.RAA_Analysis__c);
            }
        }

        Map<Id, Set<Id>> bypassUsersByAnalysis = new Map<Id, Set<Id>>();
        for (RAA_Access_Reason__c reason : [
            SELECT RAA_Access_Result__r.RAA_Analysis__c, RAA_Access_Result__r.RAA_User__c
            FROM RAA_Access_Reason__c
            WHERE RAA_Category__c = 'Permission' AND RAA_Access_Result__r.RAA_Analysis__c IN :analysisIds
        ]) {
            Id analysisId = reason.RAA_Access_Result__r.RAA_Analysis__c;
            if (!bypassUsersByAnalysis.containsKey(analysisId)) {
                bypassUsersByAnalysis.put(analysisId, new Set<Id>());
            }
            bypassUsersByAnalysis.get(analysisId).add(reason.RAA_Access_Result__r.RAA_User__c);
        }

        List<RAA_RiskInsightDTO> insights = new List<RAA_RiskInsightDTO>();
        for (RAA_Analysis__c analysis : latestByRecord.values()) {
            RAA_RiskInsightDTO dto = new RAA_RiskInsightDTO();
            dto.analysisId = analysis.Id;
            dto.recordId = analysis.RAA_Record_Id__c;
            dto.objectApiName = analysis.RAA_Object_API_Name__c;
            dto.recordDisplayName = analysis.RAA_Record_Display_Name__c;
            dto.completedAt = analysis.RAA_Completed_At__c;
            dto.usersWithAccess = analysis.RAA_Users_With_Access__c == null
                ? 0
                : Integer.valueOf(analysis.RAA_Users_With_Access__c);
            dto.externalUserCount = countOf(externalCountByAnalysis, analysis.Id);
            dto.bypassHolderCount = bypassUsersByAnalysis.containsKey(analysis.Id)
                ? bypassUsersByAnalysis.get(analysis.Id).size()
                : 0;
            dto.unresolvedCount = countOf(unresolvedCountByAnalysis, analysis.Id);
            dto.riskScore =
                dto.externalUserCount * EXTERNAL_USER_WEIGHT +
                dto.bypassHolderCount * BYPASS_HOLDER_WEIGHT +
                dto.unresolvedCount * UNRESOLVED_WEIGHT;
            insights.add(dto);
        }

        insights.sort(new ByRiskScoreDescending());
        while (insights.size() > MAX_RESULTS_RETURNED) {
            insights.remove(insights.size() - 1);
        }
        return insights;
    }

    private Map<String, RAA_Analysis__c> latestCompletedAnalysisPerRecord(Id requestedById) {
        Map<String, RAA_Analysis__c> latestByRecord = new Map<String, RAA_Analysis__c>();
        for (RAA_Analysis__c analysis : [
            SELECT
                Id,
                RAA_Record_Id__c,
                RAA_Object_API_Name__c,
                RAA_Record_Display_Name__c,
                RAA_Completed_At__c,
                RAA_Users_With_Access__c
            FROM RAA_Analysis__c
            WHERE RAA_Requested_By__c = :requestedById AND RAA_Is_Complete__c = TRUE
            ORDER BY RAA_Completed_At__c DESC
            LIMIT :MAX_ANALYSES_CONSIDERED
        ]) {
            // Results are ordered most-recent-first, so the first analysis seen for a given
            // record is already its latest - later, older duplicates for the same record are
            // skipped rather than overwriting it.
            if (!latestByRecord.containsKey(analysis.RAA_Record_Id__c)) {
                latestByRecord.put(analysis.RAA_Record_Id__c, analysis);
            }
        }
        return latestByRecord;
    }

    private void increment(Map<Id, Integer> counts, Id key) {
        counts.put(key, countOf(counts, key) + 1);
    }

    private Integer countOf(Map<Id, Integer> counts, Id key) {
        return counts.containsKey(key) ? counts.get(key) : 0;
    }

    private class ByRiskScoreDescending implements Comparator<RAA_RiskInsightDTO> {
        public Integer compare(RAA_RiskInsightDTO a, RAA_RiskInsightDTO b) {
            return b.riskScore - a.riskScore;
        }
    }
}
