/**
 * Aura-enabled summary of the difference between two analyses of the same record.
 */
public class RAA_AnalysisDiffDTO {
    @AuraEnabled
    public String fromAnalysisId;
    @AuraEnabled
    public String toAnalysisId;
    @AuraEnabled
    public Datetime fromCompletedAt;
    @AuraEnabled
    public Datetime toCompletedAt;
    @AuraEnabled
    public Integer usersAdded;
    @AuraEnabled
    public Integer usersRemoved;
    @AuraEnabled
    public Integer usersChanged;
    @AuraEnabled
    public List<RAA_UserAccessChangeDTO> changes;

    public RAA_AnalysisDiffDTO() {
        this.changes = new List<RAA_UserAccessChangeDTO>();
        this.usersAdded = 0;
        this.usersRemoved = 0;
        this.usersChanged = 0;
    }
}
