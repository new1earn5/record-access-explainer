/**
 * Aura-enabled summary of one child analysis within a bulk run.
 */
public class RAA_BatchRunAnalysisSummaryDTO {
    @AuraEnabled public String analysisId;
    @AuraEnabled public String recordId;
    @AuraEnabled public String recordDisplayName;
    @AuraEnabled public String status;
    @AuraEnabled public Boolean isComplete;
    @AuraEnabled public Integer usersWithAccess;
    @AuraEnabled public String warnings;
    @AuraEnabled public String errorDetails;

    public RAA_BatchRunAnalysisSummaryDTO(RAA_Analysis__c analysis) {
        this.analysisId = analysis.Id;
        this.recordId = analysis.RAA_Record_Id__c;
        this.recordDisplayName = analysis.RAA_Record_Display_Name__c;
        this.status = analysis.RAA_Status__c;
        this.isComplete = analysis.RAA_Is_Complete__c;
        this.usersWithAccess = analysis.RAA_Users_With_Access__c == null ? 0 : Integer.valueOf(analysis.RAA_Users_With_Access__c);
        this.warnings = analysis.RAA_Warnings__c;
        this.errorDetails = analysis.RAA_Error_Details__c;
    }
}
