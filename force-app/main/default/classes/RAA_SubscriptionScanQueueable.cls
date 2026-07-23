/**
 * Starts one scan per active subscription that isn't already waiting on a prior cycle's scan,
 * chunked at 5 per execute() and chained via System.enqueueJob for the same governor-limit
 * reason as RAA_BulkScanQueueable (a single transaction can call Database.executeBatch at most
 * 5 times). Records each subscription's newly started analysis as its "pending" analysis;
 * RAA_RecurringScanScheduler compares it against the previous baseline on the *next* scheduled
 * firing, once it has had time to complete.
 */
public without sharing class RAA_SubscriptionScanQueueable implements Queueable {

    @TestVisible
    private static final Integer CHUNK_SIZE = 5;

    private final List<Id> remainingSubscriptionIds;

    public RAA_SubscriptionScanQueueable(List<Id> remainingSubscriptionIds) {
        this.remainingSubscriptionIds = remainingSubscriptionIds;
    }

    public void execute(QueueableContext qc) {
        RAA_SubscriptionRepository subscriptionRepo = new RAA_SubscriptionRepository();
        RAA_AnalysisRepository analysisRepo = new RAA_AnalysisRepository();
        RAA_SettingsService settings = new RAA_SettingsService();

        Integer stop = Math.min(CHUNK_SIZE, remainingSubscriptionIds.size());
        for (Integer i = 0; i < stop; i++) {
            Id subscriptionId = remainingSubscriptionIds[i];
            RAA_Scan_Subscription__c subscription = subscriptionRepo.getSubscription(subscriptionId);
            if (subscription == null) {
                continue;
            }
            try {
                Id analysisId = analysisRepo.createAnalysis(subscription.RAA_Record_Id__c, subscription.RAA_Object_API_Name__c,
                        subscription.RAA_Record_Display_Name__c, subscription.RAA_Subscriber__c,
                        subscription.RAA_Include_External_Users__c, subscription.RAA_Include_Inactive_Users__c);

                RAA_UserPopulationBuilder.PopulationFilter filter = new RAA_UserPopulationBuilder.PopulationFilter();
                filter.includeExternalUsers = subscription.RAA_Include_External_Users__c;
                filter.includeInactiveUsers = subscription.RAA_Include_Inactive_Users__c;

                Database.executeBatch(new RAA_AccessScanBatch(analysisId, subscription.RAA_Record_Id__c, filter), settings.defaultBatchScope);
                subscriptionRepo.setPendingAnalysis(subscriptionId, analysisId);
            } catch (Exception e) {
                // A single subscription's failure should not block the rest of the cycle; it will
                // simply be retried on the next scheduled firing since RAA_Pending_Analysis__c stays null.
            }
        }

        List<Id> stillRemaining = new List<Id>();
        for (Integer i = stop; i < remainingSubscriptionIds.size(); i++) {
            stillRemaining.add(remainingSubscriptionIds[i]);
        }
        // See RAA_BulkScanQueueable for why chaining is skipped under Test.isRunningTest():
        // it always throws "Maximum stack depth has been reached" inside a synchronous test flush.
        if (!stillRemaining.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new RAA_SubscriptionScanQueueable(stillRemaining));
        }
    }
}
