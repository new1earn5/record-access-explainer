@IsTest
private class RAA_AnalysisDiffServiceTest {
    @IsTest
    static void comparesTwoAnalysesAndDetectsAddedRemovedAndChangedUsers() {
        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id fromAnalysisId = repo.createAnalysis(
            UserInfo.getUserId(),
            'User',
            'From',
            UserInfo.getUserId(),
            false,
            false
        );
        Id toAnalysisId = repo.createAnalysis(UserInfo.getUserId(), 'User', 'To', UserInfo.getUserId(), false, false);

        User userA = RAA_TestDataFactory.createUser('Diff', 'Added');
        User userB = RAA_TestDataFactory.createUser('Diff', 'Removed');
        User userC = RAA_TestDataFactory.createUser('Diff', 'Changed');
        Map<Id, User> userInfoMap = new Map<Id, User>(
            [SELECT Id, Name, Username, UserType, IsActive, Profile.Name FROM User WHERE Id IN (:userB.Id, :userC.Id)]
        );

        RAA_ReasonAggregator.AggregatedUserResult removedResult = new RAA_ReasonAggregator.AggregatedUserResult();
        removedResult.userId = userB.Id;
        removedResult.effectiveAccess = RAA_TestDataFactory.readOnlyAccess(userB.Id);
        removedResult.reasons = new List<RAA_AccessReasonDTO>{ RAA_TestDataFactory.buildReason('Ownership', 'High') };

        RAA_ReasonAggregator.AggregatedUserResult changedFromResult = new RAA_ReasonAggregator.AggregatedUserResult();
        changedFromResult.userId = userC.Id;
        changedFromResult.effectiveAccess = RAA_TestDataFactory.readOnlyAccess(userC.Id);
        changedFromResult.reasons = new List<RAA_AccessReasonDTO>{
            RAA_TestDataFactory.buildReason('Ownership', 'High')
        };

        repo.saveResults(
            fromAnalysisId,
            new List<RAA_ReasonAggregator.AggregatedUserResult>{ removedResult, changedFromResult },
            userInfoMap
        );

        Map<Id, User> userInfoMap2 = new Map<Id, User>(
            [SELECT Id, Name, Username, UserType, IsActive, Profile.Name FROM User WHERE Id IN (:userA.Id, :userC.Id)]
        );
        RAA_ReasonAggregator.AggregatedUserResult addedResult = new RAA_ReasonAggregator.AggregatedUserResult();
        addedResult.userId = userA.Id;
        addedResult.effectiveAccess = RAA_TestDataFactory.readOnlyAccess(userA.Id);
        addedResult.reasons = new List<RAA_AccessReasonDTO>{ RAA_TestDataFactory.buildReason('Ownership', 'High') };

        RAA_ReasonAggregator.AggregatedUserResult changedToResult = new RAA_ReasonAggregator.AggregatedUserResult();
        changedToResult.userId = userC.Id;
        changedToResult.effectiveAccess = RAA_TestDataFactory.fullAccess(userC.Id);
        changedToResult.reasons = new List<RAA_AccessReasonDTO>{
            RAA_TestDataFactory.buildReason('Ownership', 'High'),
            RAA_TestDataFactory.buildReason('Permission', 'High')
        };

        repo.saveResults(
            toAnalysisId,
            new List<RAA_ReasonAggregator.AggregatedUserResult>{ addedResult, changedToResult },
            userInfoMap2
        );

        Test.startTest();
        RAA_AnalysisDiffDTO diff = new RAA_AnalysisDiffService().compare(fromAnalysisId, toAnalysisId);
        Test.stopTest();

        System.assertEquals(1, diff.usersAdded);
        System.assertEquals(1, diff.usersRemoved);
        System.assertEquals(1, diff.usersChanged);
        System.assertEquals(3, diff.changes.size());
    }

    @IsTest
    static void returnsNullWhenNoPreviousAnalysisExists() {
        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id analysisId = repo.createAnalysis(
            UserInfo.getUserId(),
            'User',
            'Only One',
            UserInfo.getUserId(),
            false,
            false
        );
        repo.markCompleted(analysisId, false, null);

        RAA_AnalysisDiffDTO diff = new RAA_AnalysisDiffService().compareToPreviousAnalysis(analysisId);

        System.assertEquals(null, diff);
    }

    @IsTest
    static void throwsForUnknownAnalysis() {
        RAA_Analysis__c analysis = RAA_TestDataFactory.createAnalysis(UserInfo.getUserId(), 'User');
        Id analysisId = analysis.Id;
        delete analysis;

        try {
            new RAA_AnalysisDiffService().compareToPreviousAnalysis(analysisId);
            System.assert(false, 'Expected an exception for a deleted analysis.');
        } catch (RAA_AppException e) {
            System.assert(e.getMessage().contains('could not be found'));
        }
    }
}
