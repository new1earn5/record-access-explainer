@IsTest
private class RAA_SubscriptionScanQueueableTest {
    @IsTest
    static void startsAScanAndRecordsThePendingAnalysis() {
        Account acct = new Account(Name = 'RAA Subscription Scan Account');
        insert acct;

        RAA_SubscriptionRepository repo = new RAA_SubscriptionRepository();
        Id subscriptionId = repo.createSubscription(
            acct.Id,
            'Account',
            'RAA Subscription Scan Account',
            UserInfo.getUserId(),
            false,
            false,
            true,
            false,
            false,
            null
        );

        Test.startTest();
        System.enqueueJob(new RAA_SubscriptionScanQueueable(new List<Id>{ subscriptionId }));
        Test.stopTest();

        RAA_Scan_Subscription__c updated = repo.getSubscription(subscriptionId);
        System.assertNotEquals(
            null,
            updated.RAA_Pending_Analysis__c,
            'A scan should have been started and linked as pending.'
        );
        System.assertNotEquals(null, updated.RAA_Last_Run_At__c);
    }

    @IsTest
    static void skipsDeletedSubscriptionsWithoutError() {
        RAA_SubscriptionRepository repo = new RAA_SubscriptionRepository();
        Id subscriptionId = repo.createSubscription(
            UserInfo.getUserId(),
            'User',
            'Vanishing',
            UserInfo.getUserId(),
            false,
            false,
            true,
            false,
            false,
            null
        );
        delete new RAA_Scan_Subscription__c(Id = subscriptionId);

        Test.startTest();
        System.enqueueJob(new RAA_SubscriptionScanQueueable(new List<Id>{ subscriptionId }));
        Test.stopTest();

        System.assert(true, 'Processing a deleted subscription should not throw.');
    }
}
