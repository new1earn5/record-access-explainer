/**
 * Owns all DML and query access to RAA_Scan_Subscription__c. Runs in system context for the
 * same reason as RAA_AnalysisRepository: the recurring scheduler and orchestrator need to
 * persist and read this package-owned audit data regardless of the running context's own
 * CRUD/FLS on it.
 */
// Deliberately without sharing and CRUD/FLS-unchecked: this is the persistence layer for the
// elevated scan pipeline (see README.md §1, "Batch Apex runs in system mode"), reached only
// through the with-sharing controller's permission and per-record visibility gate.
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class RAA_SubscriptionRepository {
    public Id createSubscription(
        Id recordId,
        String objectApiName,
        String displayName,
        Id subscriberId,
        Boolean includeExternalUsers,
        Boolean includeInactiveUsers,
        Boolean notifyOnChange,
        Boolean postToChatter
    ) {
        RAA_Scan_Subscription__c subscription = new RAA_Scan_Subscription__c(
            RAA_Record_Id__c = recordId,
            RAA_Object_API_Name__c = objectApiName,
            RAA_Record_Display_Name__c = displayName,
            RAA_Subscriber__c = subscriberId,
            RAA_Is_Active__c = true,
            RAA_Include_External_Users__c = includeExternalUsers,
            RAA_Include_Inactive_Users__c = includeInactiveUsers,
            RAA_Notify_On_Change__c = notifyOnChange,
            RAA_Post_To_Chatter__c = postToChatter
        );
        insert subscription;
        return subscription.Id;
    }

    public List<RAA_Scan_Subscription__c> getSubscriptionsForUser(Id subscriberId) {
        return [
            SELECT
                Id,
                RAA_Record_Id__c,
                RAA_Object_API_Name__c,
                RAA_Record_Display_Name__c,
                RAA_Is_Active__c,
                RAA_Include_External_Users__c,
                RAA_Include_Inactive_Users__c,
                RAA_Notify_On_Change__c,
                RAA_Post_To_Chatter__c,
                RAA_Last_Run_At__c,
                RAA_Last_Analysis__c
            FROM RAA_Scan_Subscription__c
            WHERE RAA_Subscriber__c = :subscriberId
            ORDER BY RAA_Record_Display_Name__c
        ];
    }

    public RAA_Scan_Subscription__c getSubscription(Id subscriptionId) {
        List<RAA_Scan_Subscription__c> rows = [
            SELECT
                Id,
                RAA_Record_Id__c,
                RAA_Object_API_Name__c,
                RAA_Record_Display_Name__c,
                RAA_Is_Active__c,
                RAA_Include_External_Users__c,
                RAA_Include_Inactive_Users__c,
                RAA_Notify_On_Change__c,
                RAA_Subscriber__c,
                RAA_Last_Run_At__c,
                RAA_Last_Analysis__c,
                RAA_Pending_Analysis__c
            FROM RAA_Scan_Subscription__c
            WHERE Id = :subscriptionId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    public List<RAA_Scan_Subscription__c> getActiveSubscriptions(Integer maxRows) {
        return [
            SELECT
                Id,
                RAA_Record_Id__c,
                RAA_Object_API_Name__c,
                RAA_Record_Display_Name__c,
                RAA_Include_External_Users__c,
                RAA_Include_Inactive_Users__c,
                RAA_Notify_On_Change__c,
                RAA_Post_To_Chatter__c,
                RAA_Subscriber__c,
                RAA_Last_Analysis__c,
                RAA_Pending_Analysis__c
            FROM RAA_Scan_Subscription__c
            WHERE RAA_Is_Active__c = TRUE
            LIMIT :maxRows
        ];
    }

    public void setActive(Id subscriptionId, Boolean isActive) {
        update new RAA_Scan_Subscription__c(Id = subscriptionId, RAA_Is_Active__c = isActive);
    }

    public void deleteSubscription(Id subscriptionId) {
        delete new RAA_Scan_Subscription__c(Id = subscriptionId);
    }

    public void setPendingAnalysis(Id subscriptionId, Id pendingAnalysisId) {
        update new RAA_Scan_Subscription__c(
            Id = subscriptionId,
            RAA_Pending_Analysis__c = pendingAnalysisId,
            RAA_Last_Run_At__c = System.now()
        );
    }

    public void advanceBaseline(Id subscriptionId, Id newLastAnalysisId) {
        update new RAA_Scan_Subscription__c(
            Id = subscriptionId,
            RAA_Last_Analysis__c = newLastAnalysisId,
            RAA_Pending_Analysis__c = null
        );
    }
}
