@IsTest
private class RAA_RecurringScanSchedulerTest {
    @IsTest
    static void firstCycleStartsScanSecondCycleAdvancesBaseline() {
        Account acct = new Account(Name = 'RAA Recurring Account');
        insert acct;

        RAA_SubscriptionRepository repo = new RAA_SubscriptionRepository();
        Id subscriptionId = repo.createSubscription(
            acct.Id,
            'Account',
            'RAA Recurring Account',
            UserInfo.getUserId(),
            false,
            false,
            true,
            false,
            false,
            null
        );

        Test.startTest();
        new RAA_RecurringScanScheduler().execute(null);
        Test.stopTest();

        RAA_Scan_Subscription__c afterFirstCycle = repo.getSubscription(subscriptionId);
        System.assertNotEquals(
            null,
            afterFirstCycle.RAA_Pending_Analysis__c,
            'The first cycle should have started a scan and recorded it as pending.'
        );
        System.assertEquals(
            null,
            afterFirstCycle.RAA_Last_Analysis__c,
            'No baseline should exist until a cycle completes and is diffed.'
        );

        // A test method supports only one Test.startTest()/Test.stopTest() pair, so the second
        // cycle is invoked directly - it needs no async flush, since with a pending analysis
        // already complete it only performs synchronous diff/update work, not a new scan.
        new RAA_RecurringScanScheduler().execute(null);

        RAA_Scan_Subscription__c afterSecondCycle = repo.getSubscription(subscriptionId);
        System.assertNotEquals(
            null,
            afterSecondCycle.RAA_Last_Analysis__c,
            'The second cycle should have diffed the completed scan and advanced the baseline.'
        );
        System.assertEquals(null, afterSecondCycle.RAA_Pending_Analysis__c, 'Pending should be cleared once diffed.');
    }

    @IsTest
    static void skipsSubscriptionWhosePendingScanIsStillRunning() {
        RAA_SubscriptionRepository repo = new RAA_SubscriptionRepository();
        Id subscriptionId = repo.createSubscription(
            UserInfo.getUserId(),
            'User',
            'Still Running',
            UserInfo.getUserId(),
            false,
            false,
            true,
            false,
            false,
            null
        );

        RAA_AnalysisRepository analysisRepo = new RAA_AnalysisRepository();
        Id incompleteAnalysisId = analysisRepo.createAnalysis(
            UserInfo.getUserId(),
            'User',
            'Incomplete',
            UserInfo.getUserId(),
            false,
            false
        );
        repo.setPendingAnalysis(subscriptionId, incompleteAnalysisId);

        Test.startTest();
        new RAA_RecurringScanScheduler().execute(null);
        Test.stopTest();

        RAA_Scan_Subscription__c afterCycle = repo.getSubscription(subscriptionId);
        System.assertEquals(
            incompleteAnalysisId,
            afterCycle.RAA_Pending_Analysis__c,
            'A still-running pending scan must not be replaced or cleared.'
        );
        System.assertEquals(null, afterCycle.RAA_Last_Analysis__c);
    }

    @IsTest
    static void completedCycleWithChangesSendsNotificationAndAdvancesBaseline() {
        Account acct = new Account(Name = 'RAA Recurring Notify Account');
        insert acct;

        RAA_AnalysisRepository analysisRepo = new RAA_AnalysisRepository();
        Id baselineAnalysisId = analysisRepo.createAnalysis(
            acct.Id,
            'Account',
            'RAA Recurring Notify Account',
            UserInfo.getUserId(),
            false,
            false
        );
        Id pendingAnalysisId = analysisRepo.createAnalysis(
            acct.Id,
            'Account',
            'RAA Recurring Notify Account',
            UserInfo.getUserId(),
            false,
            false
        );

        User addedUser = RAA_TestDataFactory.createUser('Recurring', 'Added');
        Map<Id, User> userInfoMap = new Map<Id, User>(
            [SELECT Id, Name, Username, UserType, IsActive, Profile.Name FROM User WHERE Id = :addedUser.Id]
        );

        RAA_ReasonAggregator.AggregatedUserResult addedResult = new RAA_ReasonAggregator.AggregatedUserResult();
        addedResult.userId = addedUser.Id;
        addedResult.effectiveAccess = RAA_TestDataFactory.readOnlyAccess(addedUser.Id);
        addedResult.reasons = new List<RAA_AccessReasonDTO>{ RAA_TestDataFactory.buildReason('Ownership', 'High') };

        analysisRepo.saveResults(
            baselineAnalysisId,
            new List<RAA_ReasonAggregator.AggregatedUserResult>(),
            new Map<Id, User>()
        );
        analysisRepo.markCompleted(baselineAnalysisId, false, null, null);
        analysisRepo.saveResults(
            pendingAnalysisId,
            new List<RAA_ReasonAggregator.AggregatedUserResult>{ addedResult },
            userInfoMap
        );
        analysisRepo.markCompleted(pendingAnalysisId, false, null, null);

        RAA_SubscriptionRepository subscriptionRepo = new RAA_SubscriptionRepository();
        Id subscriptionId = subscriptionRepo.createSubscription(
            acct.Id,
            'Account',
            'RAA Recurring Notify Account',
            UserInfo.getUserId(),
            false,
            false,
            true,
            false,
            false,
            null
        );
        subscriptionRepo.setPendingAnalysis(subscriptionId, pendingAnalysisId);
        update new RAA_Scan_Subscription__c(Id = subscriptionId, RAA_Last_Analysis__c = baselineAnalysisId);

        Test.startTest();
        new RAA_RecurringScanScheduler().execute(null);
        Test.stopTest();

        RAA_Scan_Subscription__c afterCycle = subscriptionRepo.getSubscription(subscriptionId);
        System.assertEquals(
            pendingAnalysisId,
            afterCycle.RAA_Last_Analysis__c,
            'The baseline should advance to the analysis that was just diffed.'
        );
        System.assertEquals(
            null,
            afterCycle.RAA_Pending_Analysis__c,
            'Pending should be cleared once diffed and notified.'
        );
    }

    @IsTest
    static void completedCycleWithChangesPostsToChatterWhenEnabled() {
        Account acct = new Account(Name = 'RAA Recurring Chatter Account');
        insert acct;

        RAA_AnalysisRepository analysisRepo = new RAA_AnalysisRepository();
        Id baselineAnalysisId = analysisRepo.createAnalysis(
            acct.Id,
            'Account',
            'RAA Recurring Chatter Account',
            UserInfo.getUserId(),
            false,
            false
        );
        Id pendingAnalysisId = analysisRepo.createAnalysis(
            acct.Id,
            'Account',
            'RAA Recurring Chatter Account',
            UserInfo.getUserId(),
            false,
            false
        );

        User addedUser = RAA_TestDataFactory.createUser('Chatter', 'Added');
        Map<Id, User> userInfoMap = new Map<Id, User>(
            [SELECT Id, Name, Username, UserType, IsActive, Profile.Name FROM User WHERE Id = :addedUser.Id]
        );

        RAA_ReasonAggregator.AggregatedUserResult addedResult = new RAA_ReasonAggregator.AggregatedUserResult();
        addedResult.userId = addedUser.Id;
        addedResult.effectiveAccess = RAA_TestDataFactory.readOnlyAccess(addedUser.Id);
        addedResult.reasons = new List<RAA_AccessReasonDTO>{ RAA_TestDataFactory.buildReason('Ownership', 'High') };

        analysisRepo.saveResults(
            baselineAnalysisId,
            new List<RAA_ReasonAggregator.AggregatedUserResult>(),
            new Map<Id, User>()
        );
        analysisRepo.markCompleted(baselineAnalysisId, false, null, null);
        analysisRepo.saveResults(
            pendingAnalysisId,
            new List<RAA_ReasonAggregator.AggregatedUserResult>{ addedResult },
            userInfoMap
        );
        analysisRepo.markCompleted(pendingAnalysisId, false, null, null);

        RAA_SubscriptionRepository subscriptionRepo = new RAA_SubscriptionRepository();
        // notifyOnChange is deliberately false here, to isolate Chatter from the email path
        // already covered by completedCycleWithChangesSendsNotificationAndAdvancesBaseline.
        Id subscriptionId = subscriptionRepo.createSubscription(
            acct.Id,
            'Account',
            'RAA Recurring Chatter Account',
            UserInfo.getUserId(),
            false,
            false,
            false,
            true,
            false,
            null
        );
        subscriptionRepo.setPendingAnalysis(subscriptionId, pendingAnalysisId);
        update new RAA_Scan_Subscription__c(Id = subscriptionId, RAA_Last_Analysis__c = baselineAnalysisId);

        Test.startTest();
        new RAA_RecurringScanScheduler().execute(null);
        Test.stopTest();

        RAA_Scan_Subscription__c afterCycle = subscriptionRepo.getSubscription(subscriptionId);
        System.assertEquals(
            pendingAnalysisId,
            afterCycle.RAA_Last_Analysis__c,
            'The baseline should advance to the analysis that was just diffed, regardless of the Chatter post outcome.'
        );

        // Confirmed directly against a live scratch org: Chatter Feed Tracking on Account is
        // enabled by default, so this is a real assertion, not an assumption - the defensive
        // try/catch in postChatterUpdate exists for objects where that isn't true, not this one.
        List<FeedItem> posts = [SELECT Id, Body FROM FeedItem WHERE ParentId = :acct.Id];
        System.assertEquals(1, posts.size(), 'A Chatter post should have been created on the watched record.');
        System.assert(
            posts[0].Body.contains('access change'),
            'The Chatter post should summarize the detected change.'
        );
    }

    @IsTest
    static void completedCycleWithChangesPostsToSlackWhenEnabled() {
        Account acct = new Account(Name = 'RAA Recurring Slack Account');
        insert acct;

        RAA_AnalysisRepository analysisRepo = new RAA_AnalysisRepository();
        Id baselineAnalysisId = analysisRepo.createAnalysis(
            acct.Id,
            'Account',
            'RAA Recurring Slack Account',
            UserInfo.getUserId(),
            false,
            false
        );
        Id pendingAnalysisId = analysisRepo.createAnalysis(
            acct.Id,
            'Account',
            'RAA Recurring Slack Account',
            UserInfo.getUserId(),
            false,
            false
        );

        User addedUser = RAA_TestDataFactory.createUser('Slack', 'Added');
        Map<Id, User> userInfoMap = new Map<Id, User>(
            [SELECT Id, Name, Username, UserType, IsActive, Profile.Name FROM User WHERE Id = :addedUser.Id]
        );

        RAA_ReasonAggregator.AggregatedUserResult addedResult = new RAA_ReasonAggregator.AggregatedUserResult();
        addedResult.userId = addedUser.Id;
        addedResult.effectiveAccess = RAA_TestDataFactory.readOnlyAccess(addedUser.Id);
        addedResult.reasons = new List<RAA_AccessReasonDTO>{ RAA_TestDataFactory.buildReason('Ownership', 'High') };

        analysisRepo.saveResults(
            baselineAnalysisId,
            new List<RAA_ReasonAggregator.AggregatedUserResult>(),
            new Map<Id, User>()
        );
        analysisRepo.markCompleted(baselineAnalysisId, false, null, null);
        analysisRepo.saveResults(
            pendingAnalysisId,
            new List<RAA_ReasonAggregator.AggregatedUserResult>{ addedResult },
            userInfoMap
        );
        analysisRepo.markCompleted(pendingAnalysisId, false, null, null);

        RAA_SubscriptionRepository subscriptionRepo = new RAA_SubscriptionRepository();
        // notifyOnChange/postToChatter are deliberately false here, to isolate Slack from the
        // paths already covered by the email and Chatter tests above.
        Id subscriptionId = subscriptionRepo.createSubscription(
            acct.Id,
            'Account',
            'RAA Recurring Slack Account',
            UserInfo.getUserId(),
            false,
            false,
            false,
            false,
            true,
            'https://hooks.slack.com/services/T000/B000/XXXX'
        );
        subscriptionRepo.setPendingAnalysis(subscriptionId, pendingAnalysisId);
        update new RAA_Scan_Subscription__c(Id = subscriptionId, RAA_Last_Analysis__c = baselineAnalysisId);

        SlackCalloutMock mock = new SlackCalloutMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new RAA_RecurringScanScheduler().execute(null);
        Test.stopTest();

        RAA_Scan_Subscription__c afterCycle = subscriptionRepo.getSubscription(subscriptionId);
        System.assertEquals(
            pendingAnalysisId,
            afterCycle.RAA_Last_Analysis__c,
            'The baseline should advance to the analysis that was just diffed, regardless of the Slack post outcome.'
        );

        System.assertEquals(1, mock.requestsReceived, 'The Slack webhook should have been called exactly once.');
        System.assertEquals('https://hooks.slack.com/services/T000/B000/XXXX', mock.lastEndpoint);
        System.assert(
            mock.lastBody.contains('access change'),
            'The Slack message body should summarize the detected change.'
        );
        System.assert(
            mock.lastBody.contains('RAA Recurring Slack Account'),
            'Unlike the Chatter post (which is already on the record), the Slack message must name the record.'
        );
    }

    @IsTest
    static void completedCycleSkipsSlackWhenWebhookCalloutFails() {
        Account acct = new Account(Name = 'RAA Recurring Slack Failure Account');
        insert acct;

        RAA_AnalysisRepository analysisRepo = new RAA_AnalysisRepository();
        Id baselineAnalysisId = analysisRepo.createAnalysis(
            acct.Id,
            'Account',
            'RAA Recurring Slack Failure Account',
            UserInfo.getUserId(),
            false,
            false
        );
        Id pendingAnalysisId = analysisRepo.createAnalysis(
            acct.Id,
            'Account',
            'RAA Recurring Slack Failure Account',
            UserInfo.getUserId(),
            false,
            false
        );

        User addedUser = RAA_TestDataFactory.createUser('SlackFail', 'Added');
        Map<Id, User> userInfoMap = new Map<Id, User>(
            [SELECT Id, Name, Username, UserType, IsActive, Profile.Name FROM User WHERE Id = :addedUser.Id]
        );

        RAA_ReasonAggregator.AggregatedUserResult addedResult = new RAA_ReasonAggregator.AggregatedUserResult();
        addedResult.userId = addedUser.Id;
        addedResult.effectiveAccess = RAA_TestDataFactory.readOnlyAccess(addedUser.Id);
        addedResult.reasons = new List<RAA_AccessReasonDTO>{ RAA_TestDataFactory.buildReason('Ownership', 'High') };

        analysisRepo.saveResults(
            baselineAnalysisId,
            new List<RAA_ReasonAggregator.AggregatedUserResult>(),
            new Map<Id, User>()
        );
        analysisRepo.markCompleted(baselineAnalysisId, false, null, null);
        analysisRepo.saveResults(
            pendingAnalysisId,
            new List<RAA_ReasonAggregator.AggregatedUserResult>{ addedResult },
            userInfoMap
        );
        analysisRepo.markCompleted(pendingAnalysisId, false, null, null);

        RAA_SubscriptionRepository subscriptionRepo = new RAA_SubscriptionRepository();
        Id subscriptionId = subscriptionRepo.createSubscription(
            acct.Id,
            'Account',
            'RAA Recurring Slack Failure Account',
            UserInfo.getUserId(),
            false,
            false,
            false,
            false,
            true,
            'https://hooks.slack.com/services/T000/B000/XXXX'
        );
        subscriptionRepo.setPendingAnalysis(subscriptionId, pendingAnalysisId);
        update new RAA_Scan_Subscription__c(Id = subscriptionId, RAA_Last_Analysis__c = baselineAnalysisId);

        Test.setMock(HttpCalloutMock.class, new SlackCalloutMock(500));

        Test.startTest();
        new RAA_RecurringScanScheduler().execute(null);
        Test.stopTest();

        // A failed Slack callout must never prevent the baseline from advancing - same
        // contract as a failed email send or a failed Chatter post.
        RAA_Scan_Subscription__c afterCycle = subscriptionRepo.getSubscription(subscriptionId);
        System.assertEquals(
            pendingAnalysisId,
            afterCycle.RAA_Last_Analysis__c,
            'The baseline should still advance even though the Slack callout failed.'
        );
    }

    private class SlackCalloutMock implements HttpCalloutMock {
        Integer statusCode;
        Integer requestsReceived = 0;
        String lastEndpoint;
        String lastBody;

        SlackCalloutMock() {
            this(200);
        }

        SlackCalloutMock(Integer statusCode) {
            this.statusCode = statusCode;
        }

        public HttpResponse respond(HttpRequest request) {
            requestsReceived++;
            lastEndpoint = request.getEndpoint();
            lastBody = request.getBody();

            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody('{"ok":true}');
            return response;
        }
    }
}
