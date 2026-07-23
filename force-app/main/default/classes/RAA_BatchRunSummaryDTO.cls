/**
 * Aura-enabled summary of a bulk scan run.
 */
public class RAA_BatchRunSummaryDTO {
    @AuraEnabled public String batchRunId;
    @AuraEnabled public String objectApiName;
    @AuraEnabled public String status;
    @AuraEnabled public Integer totalRecords;
    @AuraEnabled public Integer completedRecords;
    @AuraEnabled public Datetime requestedAt;
    @AuraEnabled public List<RAA_BatchRunAnalysisSummaryDTO> analyses;

    public RAA_BatchRunSummaryDTO(RAA_Batch_Run__c run, List<RAA_Analysis__c> children) {
        this.batchRunId = run.Id;
        this.objectApiName = run.RAA_Object_API_Name__c;
        this.status = run.RAA_Status__c;
        this.totalRecords = run.RAA_Total_Records__c == null ? 0 : Integer.valueOf(run.RAA_Total_Records__c);
        this.requestedAt = run.RAA_Requested_At__c;
        this.analyses = new List<RAA_BatchRunAnalysisSummaryDTO>();
        Integer completed = 0;
        for (RAA_Analysis__c child : children) {
            this.analyses.add(new RAA_BatchRunAnalysisSummaryDTO(child));
            if (child.RAA_Is_Complete__c) {
                completed++;
            }
        }
        this.completedRecords = completed;
    }
}
