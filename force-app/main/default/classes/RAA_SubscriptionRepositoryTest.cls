@IsTest
private class RAA_SubscriptionRepositoryTest {

    @IsTest
    static void createReadUpdateAndDeleteLifecycle() {
        RAA_SubscriptionRepository repo = new RAA_SubscriptionRepository();

        Test.startTest();
        Id subscriptionId = repo.createSubscription(UserInfo.getUserId(), 'User', 'Test Sub', UserInfo.getUserId(), false, false, true);
        Test.stopTest();

        RAA_Scan_Subscription__c fetched = repo.getSubscription(subscriptionId);
        System.assertNotEquals(null, fetched);
        System.assertEquals(true, fetched.RAA_Is_Active__c);
        System.assertEquals(true, fetched.RAA_Notify_On_Change__c);

        List<RAA_Scan_Subscription__c> forUser = repo.getSubscriptionsForUser(UserInfo.getUserId());
        System.assertEquals(1, forUser.size());

        List<RAA_Scan_Subscription__c> active = repo.getActiveSubscriptions(200);
        System.assert(!active.isEmpty());

        repo.setActive(subscriptionId, false);
        System.assertEquals(false, repo.getSubscription(subscriptionId).RAA_Is_Active__c);

        RAA_Analysis__c analysis = RAA_TestDataFactory.createAnalysis(UserInfo.getUserId(), 'User');
        repo.setPendingAnalysis(subscriptionId, analysis.Id);
        System.assertEquals(analysis.Id, repo.getSubscription(subscriptionId).RAA_Pending_Analysis__c);

        repo.advanceBaseline(subscriptionId, analysis.Id);
        RAA_Scan_Subscription__c afterAdvance = repo.getSubscription(subscriptionId);
        System.assertEquals(analysis.Id, afterAdvance.RAA_Last_Analysis__c);
        System.assertEquals(null, afterAdvance.RAA_Pending_Analysis__c);

        repo.deleteSubscription(subscriptionId);
        System.assertEquals(null, repo.getSubscription(subscriptionId));
    }
}
