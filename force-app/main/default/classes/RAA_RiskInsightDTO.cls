/**
 * One row of the Risk Insights view: a record the current user has already scanned (directly, via
 * a bulk run, or via a subscription), ranked by risk signals already present in that scan's own
 * results - no new scanning happens to produce this view. See RAA_RiskInsightsService for exactly
 * how riskScore is computed; every contributing count is exposed here too so the ranking is never
 * an opaque number.
 */
public class RAA_RiskInsightDTO {
    @AuraEnabled
    public String analysisId;
    @AuraEnabled
    public String recordId;
    @AuraEnabled
    public String objectApiName;
    @AuraEnabled
    public String recordDisplayName;
    @AuraEnabled
    public Datetime completedAt;
    @AuraEnabled
    public Integer usersWithAccess;
    @AuraEnabled
    public Integer guestUserCount;
    @AuraEnabled
    public Integer externalUserCount;
    @AuraEnabled
    public Integer bypassHolderCount;
    @AuraEnabled
    public Integer unresolvedCount;
    @AuraEnabled
    public Integer riskScore;
}
