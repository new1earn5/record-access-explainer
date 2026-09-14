@IsTest
private class RAA_RiskInsightsServiceTest {
    @IsTest
    static void computesSignalsAndScoreForOneRecord() {
        Account acct = new Account(Name = 'RAA Risk Account');
        insert acct;

        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id analysisId = repo.createAnalysis(acct.Id, 'Account', 'RAA Risk Account', UserInfo.getUserId(), false, false);

        User internalUser = RAA_TestDataFactory.createUser('Risk', 'Internal');
        User externalUser = RAA_TestDataFactory.createUser('Risk', 'External');
        User unresolvedUser = RAA_TestDataFactory.createUser('Risk', 'Unresolved');
        User bypassUser = RAA_TestDataFactory.createUser('Risk', 'Bypass');

        Map<Id, User> userInfoMap = new Map<Id, User>(
            [
                SELECT Id, Name, Username, UserType, IsActive, Profile.Name
                FROM User
                WHERE Id IN (:internalUser.Id, :externalUser.Id, :unresolvedUser.Id, :bypassUser.Id)
            ]
        );

        RAA_ReasonAggregator.AggregatedUserResult internalResult = new RAA_ReasonAggregator.AggregatedUserResult();
        internalResult.userId = internalUser.Id;
        internalResult.effectiveAccess = RAA_TestDataFactory.readOnlyAccess(internalUser.Id);
        internalResult.reasons = new List<RAA_AccessReasonDTO>{ RAA_TestDataFactory.buildReason('Ownership', 'High') };

        RAA_ReasonAggregator.AggregatedUserResult externalResult = new RAA_ReasonAggregator.AggregatedUserResult();
        externalResult.userId = externalUser.Id;
        externalResult.effectiveAccess = RAA_TestDataFactory.readOnlyAccess(externalUser.Id);
        externalResult.reasons = new List<RAA_AccessReasonDTO>{
            RAA_TestDataFactory.buildReason('Group Share', 'High')
        };

        RAA_ReasonAggregator.AggregatedUserResult unresolvedResult = new RAA_ReasonAggregator.AggregatedUserResult();
        unresolvedResult.userId = unresolvedUser.Id;
        unresolvedResult.effectiveAccess = RAA_TestDataFactory.readOnlyAccess(unresolvedUser.Id);
        unresolvedResult.reasons = new List<RAA_AccessReasonDTO>{
            RAA_TestDataFactory.buildReason('Unresolved', 'Low')
        };

        RAA_ReasonAggregator.AggregatedUserResult bypassResult = new RAA_ReasonAggregator.AggregatedUserResult();
        bypassResult.userId = bypassUser.Id;
        bypassResult.effectiveAccess = RAA_TestDataFactory.fullAccess(bypassUser.Id);
        bypassResult.reasons = new List<RAA_AccessReasonDTO>{ RAA_TestDataFactory.buildReason('Permission', 'High') };

        repo.saveResults(
            analysisId,
            new List<RAA_ReasonAggregator.AggregatedUserResult>{
                internalResult,
                externalResult,
                unresolvedResult,
                bypassResult
            },
            userInfoMap
        );
        repo.markCompleted(analysisId, false, null, null);

        // RAA_Access_Result__c.RAA_User_Type__c is a denormalized snapshot, not a live lookup, so
        // this simulates an external/Experience Cloud user without needing a real one to exist in
        // the org - the same UserType != 'Standard' distinction RAA_UserPopulationBuilder uses.
        update new RAA_Access_Result__c(
            Id = [
                SELECT Id
                FROM RAA_Access_Result__c
                WHERE RAA_Analysis__c = :analysisId AND RAA_User__c = :externalUser.Id
                LIMIT 1
            ]
            .Id,
            RAA_User_Type__c = 'PowerCustomerSuccess'
        );

        Test.startTest();
        List<RAA_RiskInsightDTO> insights = new RAA_RiskInsightsService().getRiskInsights(UserInfo.getUserId());
        Test.stopTest();

        System.assertEquals(1, insights.size());
        RAA_RiskInsightDTO dto = insights[0];
        System.assertEquals(analysisId, dto.analysisId);
        System.assertEquals(1, dto.externalUserCount, 'One user was updated to a non-Standard UserType.');
        System.assertEquals(1, dto.unresolvedCount, 'One user has an Unresolved-category reason.');
        System.assertEquals(1, dto.bypassHolderCount, 'One user has a Permission-category reason.');
        System.assertEquals(
            3 + 2 + 1,
            dto.riskScore,
            'Score is externalUserCount*3 + bypassHolderCount*2 + unresolvedCount*1.'
        );
    }

    @IsTest
    static void usesOnlyTheLatestCompletedAnalysisPerRecord() {
        Account acct = new Account(Name = 'RAA Risk Latest Account');
        insert acct;

        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id olderAnalysisId = repo.createAnalysis(
            acct.Id,
            'Account',
            'RAA Risk Latest Account',
            UserInfo.getUserId(),
            false,
            false
        );
        repo.markCompleted(olderAnalysisId, false, null, null);
        // Force the older analysis's completion timestamp earlier than the one created next.
        update new RAA_Analysis__c(Id = olderAnalysisId, RAA_Completed_At__c = System.now().addDays(-1));

        Id newerAnalysisId = repo.createAnalysis(
            acct.Id,
            'Account',
            'RAA Risk Latest Account',
            UserInfo.getUserId(),
            false,
            false
        );
        repo.markCompleted(newerAnalysisId, false, null, null);

        Test.startTest();
        List<RAA_RiskInsightDTO> insights = new RAA_RiskInsightsService().getRiskInsights(UserInfo.getUserId());
        Test.stopTest();

        System.assertEquals(
            1,
            insights.size(),
            'The two analyses are for the same record, so only one row should appear.'
        );
        System.assertEquals(
            newerAnalysisId,
            insights[0].analysisId,
            'The most recently completed analysis for a record should win, not the older one.'
        );
    }

    @IsTest
    static void ordersByRiskScoreDescendingAndExcludesOtherUsersAnalyses() {
        Account lowRiskAcct = new Account(Name = 'RAA Risk Low Account');
        Account highRiskAcct = new Account(Name = 'RAA Risk High Account');
        insert new List<Account>{ lowRiskAcct, highRiskAcct };

        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id lowRiskAnalysisId = repo.createAnalysis(
            lowRiskAcct.Id,
            'Account',
            'RAA Risk Low Account',
            UserInfo.getUserId(),
            false,
            false
        );
        repo.markCompleted(lowRiskAnalysisId, false, null, null);

        Id highRiskAnalysisId = repo.createAnalysis(
            highRiskAcct.Id,
            'Account',
            'RAA Risk High Account',
            UserInfo.getUserId(),
            false,
            false
        );
        User bypassUser = RAA_TestDataFactory.createUser('Risk', 'Ordering');
        Map<Id, User> userInfoMap = new Map<Id, User>(
            [SELECT Id, Name, Username, UserType, IsActive, Profile.Name FROM User WHERE Id = :bypassUser.Id]
        );
        RAA_ReasonAggregator.AggregatedUserResult bypassResult = new RAA_ReasonAggregator.AggregatedUserResult();
        bypassResult.userId = bypassUser.Id;
        bypassResult.effectiveAccess = RAA_TestDataFactory.fullAccess(bypassUser.Id);
        bypassResult.reasons = new List<RAA_AccessReasonDTO>{ RAA_TestDataFactory.buildReason('Permission', 'High') };
        repo.saveResults(
            highRiskAnalysisId,
            new List<RAA_ReasonAggregator.AggregatedUserResult>{ bypassResult },
            userInfoMap
        );
        repo.markCompleted(highRiskAnalysisId, false, null, null);

        // Belongs to a different requester entirely - must never appear regardless of score.
        User otherUser = RAA_TestDataFactory.createUser('Risk', 'OtherOwner');
        Id otherUsersAnalysisId = repo.createAnalysis(
            UserInfo.getUserId(),
            'User',
            'Someone Elses Scan',
            otherUser.Id,
            false,
            false
        );
        repo.markCompleted(otherUsersAnalysisId, false, null, null);

        Test.startTest();
        List<RAA_RiskInsightDTO> insights = new RAA_RiskInsightsService().getRiskInsights(UserInfo.getUserId());
        Test.stopTest();

        System.assertEquals(2, insights.size(), 'Only the two analyses requested by the running user should appear.');
        System.assertEquals(
            highRiskAnalysisId,
            insights[0].analysisId,
            'The higher-scoring record should be ranked first.'
        );
        System.assertEquals(lowRiskAnalysisId, insights[1].analysisId);
        for (RAA_RiskInsightDTO dto : insights) {
            System.assertNotEquals(otherUsersAnalysisId, dto.analysisId);
        }
    }

    @IsTest
    static void returnsAnEmptyListWhenThereAreNoCompletedAnalyses() {
        Test.startTest();
        List<RAA_RiskInsightDTO> insights = new RAA_RiskInsightsService().getRiskInsights(UserInfo.getUserId());
        Test.stopTest();

        System.assertEquals(0, insights.size());
    }
}
