/**
 * Aura-enabled summary of an RAA_Analysis__c record, used for the scan progress panel.
 */
public class RAA_AnalysisSummaryDTO {
    @AuraEnabled
    public String analysisId;
    @AuraEnabled
    public String recordId;
    @AuraEnabled
    public String objectApiName;
    @AuraEnabled
    public String recordDisplayName;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Boolean isComplete;
    @AuraEnabled
    public Datetime requestedAt;
    @AuraEnabled
    public Datetime startedAt;
    @AuraEnabled
    public Datetime completedAt;
    @AuraEnabled
    public Integer totalUsers;
    @AuraEnabled
    public Integer processedUsers;
    @AuraEnabled
    public Integer usersWithAccess;
    @AuraEnabled
    public Boolean includeExternalUsers;
    @AuraEnabled
    public Boolean includeInactiveUsers;
    @AuraEnabled
    public String warnings;
    @AuraEnabled
    public String errorDetails;
    @AuraEnabled
    public Boolean potentiallyIncomplete;

    public RAA_AnalysisSummaryDTO(RAA_Analysis__c analysis) {
        this.analysisId = analysis.Id;
        this.recordId = analysis.RAA_Record_Id__c;
        this.objectApiName = analysis.RAA_Object_API_Name__c;
        this.recordDisplayName = analysis.RAA_Record_Display_Name__c;
        this.status = analysis.RAA_Status__c;
        this.isComplete = analysis.RAA_Is_Complete__c;
        this.requestedAt = analysis.RAA_Requested_At__c;
        this.startedAt = analysis.RAA_Started_At__c;
        this.completedAt = analysis.RAA_Completed_At__c;
        this.totalUsers = analysis.RAA_Total_Users__c == null ? 0 : Integer.valueOf(analysis.RAA_Total_Users__c);
        this.processedUsers = analysis.RAA_Processed_Users__c == null
            ? 0
            : Integer.valueOf(analysis.RAA_Processed_Users__c);
        this.usersWithAccess = analysis.RAA_Users_With_Access__c == null
            ? 0
            : Integer.valueOf(analysis.RAA_Users_With_Access__c);
        this.includeExternalUsers = analysis.RAA_Include_External_Users__c;
        this.includeInactiveUsers = analysis.RAA_Include_Inactive_Users__c;
        this.warnings = analysis.RAA_Warnings__c;
        this.errorDetails = analysis.RAA_Error_Details__c;
        this.potentiallyIncomplete = String.isNotBlank(analysis.RAA_Warnings__c);
    }
}
