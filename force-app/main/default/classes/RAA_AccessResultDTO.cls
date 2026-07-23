/**
 * Aura-enabled representation of a single user's access result (RAA_Access_Result__c row)
 * together with every detected reason for that user.
 */
public class RAA_AccessResultDTO {
    @AuraEnabled
    public String recordId;
    @AuraEnabled
    public String userId;
    @AuraEnabled
    public String userFullName;
    @AuraEnabled
    public String username;
    @AuraEnabled
    public String userType;
    @AuraEnabled
    public String profileName;
    @AuraEnabled
    public Boolean isActive;
    @AuraEnabled
    public String maxAccessLevel;
    @AuraEnabled
    public Boolean hasReadAccess;
    @AuraEnabled
    public Boolean hasEditAccess;
    @AuraEnabled
    public Boolean hasDeleteAccess;
    @AuraEnabled
    public Boolean hasTransferAccess;
    @AuraEnabled
    public Boolean hasAllAccess;
    @AuraEnabled
    public String reasonSummary;
    @AuraEnabled
    public String overallConfidence;
    @AuraEnabled
    public Boolean hasUnresolvedReason;
    @AuraEnabled
    public List<RAA_AccessReasonDTO> reasons;

    public RAA_AccessResultDTO() {
        this.reasons = new List<RAA_AccessReasonDTO>();
    }

    public RAA_AccessResultDTO(RAA_Access_Result__c result) {
        this.recordId = result.Id;
        this.userId = result.RAA_User__c;
        this.userFullName = result.RAA_User_Name__c;
        this.username = result.RAA_Username__c;
        this.userType = result.RAA_User_Type__c;
        this.profileName = result.RAA_Profile_Name__c;
        this.isActive = result.RAA_Is_Active__c;
        this.maxAccessLevel = result.RAA_Max_Access_Level__c;
        this.hasReadAccess = result.RAA_Has_Read_Access__c;
        this.hasEditAccess = result.RAA_Has_Edit_Access__c;
        this.hasDeleteAccess = result.RAA_Has_Delete_Access__c;
        this.hasTransferAccess = result.RAA_Has_Transfer_Access__c;
        this.hasAllAccess = result.RAA_Has_All_Access__c;
        this.reasonSummary = result.RAA_Reason_Summary__c;
        this.overallConfidence = result.RAA_Overall_Confidence__c;
        this.hasUnresolvedReason = result.RAA_Has_Unresolved_Reason__c;
        this.reasons = new List<RAA_AccessReasonDTO>();
    }
}
