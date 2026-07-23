/**
 * Aura-enabled representation of an RAA_Scan_Subscription__c row.
 */
public class RAA_SubscriptionDTO {
    @AuraEnabled
    public String subscriptionId;
    @AuraEnabled
    public String recordId;
    @AuraEnabled
    public String objectApiName;
    @AuraEnabled
    public String recordDisplayName;
    @AuraEnabled
    public Boolean isActive;
    @AuraEnabled
    public Boolean includeExternalUsers;
    @AuraEnabled
    public Boolean includeInactiveUsers;
    @AuraEnabled
    public Boolean notifyOnChange;
    @AuraEnabled
    public Datetime lastRunAt;

    public RAA_SubscriptionDTO(RAA_Scan_Subscription__c subscription) {
        this.subscriptionId = subscription.Id;
        this.recordId = subscription.RAA_Record_Id__c;
        this.objectApiName = subscription.RAA_Object_API_Name__c;
        this.recordDisplayName = subscription.RAA_Record_Display_Name__c;
        this.isActive = subscription.RAA_Is_Active__c;
        this.includeExternalUsers = subscription.RAA_Include_External_Users__c;
        this.includeInactiveUsers = subscription.RAA_Include_Inactive_Users__c;
        this.notifyOnChange = subscription.RAA_Notify_On_Change__c;
        this.lastRunAt = subscription.RAA_Last_Run_At__c;
    }
}
