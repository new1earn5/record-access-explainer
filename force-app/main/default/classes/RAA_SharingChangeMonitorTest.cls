@IsTest
private class RAA_SharingChangeMonitorTest {
    @IsTest
    static void queuesARescanWhenARoleHierarchyChangeIsDetected() {
        Account acct = new Account(Name = 'RAA Monitor Role Change Account');
        insert acct;

        RAA_SubscriptionRepository subscriptionRepo = new RAA_SubscriptionRepository();
        Id subscriptionId = subscriptionRepo.createSubscription(
            acct.Id,
            'Account',
            'RAA Monitor Role Change Account',
            UserInfo.getUserId(),
            false,
            false,
            true,
            false,
            false,
            null
        );

        // Pin the lookback window before making the real change below, since Setup Audit Trail
        // is org-global and a fixed lookback would also pick up unrelated historical entries.
        RAA_SharingChangeMonitor.testSinceWhenOverride = System.now().addMinutes(-5);

        // A genuine role hierarchy change - not a fake/mocked row. Setup Audit Trail writes are
        // confirmed (against a live scratch org during development) to be visible in the same
        // transaction as the triggering DML. Wrapped in System.runAs: UserRole is a "setup
        // object," and Salesforce forbids mixing setup-object DML with the non-setup-object DML
        // (Account, RAA_Scan_Subscription__c) already done above in the same transaction.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new UserRole(Name = 'RAA Monitor Test Role', DeveloperName = 'RAA_Monitor_Test_Role');
        }

        Test.startTest();
        new RAA_SharingChangeMonitor().execute(null);
        Test.stopTest();

        RAA_Scan_Subscription__c afterExecute = subscriptionRepo.getSubscription(subscriptionId);
        System.assertNotEquals(
            null,
            afterExecute.RAA_Pending_Analysis__c,
            'A role hierarchy change should have triggered an immediate re-scan.'
        );
    }

    @IsTest
    static void doesNotQueueARescanWhenNoSharingRelevantChangeOccurred() {
        Account acct = new Account(Name = 'RAA Monitor No Change Account');
        insert acct;

        RAA_SubscriptionRepository subscriptionRepo = new RAA_SubscriptionRepository();
        Id subscriptionId = subscriptionRepo.createSubscription(
            acct.Id,
            'Account',
            'RAA Monitor No Change Account',
            UserInfo.getUserId(),
            false,
            false,
            true,
            false,
            false,
            null
        );

        // Pinned to this exact instant, with no further sharing-relevant DML below - only a
        // genuinely later real change would be picked up, so this isn't dependent on the rest of
        // this org's (real, ambient) Setup Audit Trail history staying clean.
        RAA_SharingChangeMonitor.testSinceWhenOverride = System.now();

        Test.startTest();
        new RAA_SharingChangeMonitor().execute(null);
        Test.stopTest();

        RAA_Scan_Subscription__c afterExecute = subscriptionRepo.getSubscription(subscriptionId);
        System.assertEquals(
            null,
            afterExecute.RAA_Pending_Analysis__c,
            'No sharing-relevant change occurred, so no re-scan should have been queued.'
        );
    }

    @IsTest
    static void skipsSubscriptionsThatAlreadyHaveAPendingAnalysis() {
        Account acct = new Account(Name = 'RAA Monitor Pending Account');
        insert acct;

        RAA_SubscriptionRepository subscriptionRepo = new RAA_SubscriptionRepository();
        Id subscriptionId = subscriptionRepo.createSubscription(
            acct.Id,
            'Account',
            'RAA Monitor Pending Account',
            UserInfo.getUserId(),
            false,
            false,
            true,
            false,
            false,
            null
        );
        RAA_AnalysisRepository analysisRepo = new RAA_AnalysisRepository();
        Id existingPendingId = analysisRepo.createAnalysis(
            acct.Id,
            'Account',
            'RAA Monitor Pending Account',
            UserInfo.getUserId(),
            false,
            false
        );
        subscriptionRepo.setPendingAnalysis(subscriptionId, existingPendingId);

        RAA_SharingChangeMonitor.testSinceWhenOverride = System.now().addMinutes(-5);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new UserRole(Name = 'RAA Monitor Pending Role', DeveloperName = 'RAA_Monitor_Pending_Role');
        }

        Test.startTest();
        new RAA_SharingChangeMonitor().execute(null);
        Test.stopTest();

        RAA_Scan_Subscription__c afterExecute = subscriptionRepo.getSubscription(subscriptionId);
        System.assertEquals(
            existingPendingId,
            afterExecute.RAA_Pending_Analysis__c,
            'A subscription already waiting on a scan must not be given a second, overlapping one.'
        );
    }

    @IsTest
    static void determineSinceWhenFallsBackToDefaultLookbackWithNoTriggerContext() {
        RAA_SharingChangeMonitor.testSinceWhenOverride = null;
        Datetime result = new RAA_SharingChangeMonitor().determineSinceWhen(null);

        System.assertNotEquals(null, result);
        System.assert(
            result <= System.now().addMinutes(-RAA_SharingChangeMonitor.DEFAULT_LOOKBACK_MINUTES + 1),
            'With no scheduled-job context, the lookback should default to roughly ' +
                RAA_SharingChangeMonitor.DEFAULT_LOOKBACK_MINUTES +
                ' minutes.'
        );
    }
}
