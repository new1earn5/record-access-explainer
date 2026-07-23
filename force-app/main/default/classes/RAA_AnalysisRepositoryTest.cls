@IsTest
private class RAA_AnalysisRepositoryTest {

    @IsTest
    static void createFindUpdateAndMarkAnalysisLifecycle() {
        Account acct = new Account(Name = 'RAA Repo Account');
        insert acct;
        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();

        Test.startTest();
        Id analysisId = repo.createAnalysis(acct.Id, 'Account', 'RAA Repo Account', UserInfo.getUserId(), false, false);
        RAA_Analysis__c active = repo.findActiveAnalysisForRecord(acct.Id);
        repo.markBatchStarted(analysisId, '707000000000001AAA', 5);
        repo.updateProgress(analysisId, 3, 2);
        repo.markCompleted(analysisId, true, 'One warning occurred.');
        Test.stopTest();

        RAA_Analysis__c finalRow = repo.getAnalysis(analysisId);
        System.assertNotEquals(null, active, 'A queued analysis should be found as active.');
        System.assertEquals('Completed with Warnings', finalRow.RAA_Status__c);
        System.assertEquals(true, finalRow.RAA_Is_Complete__c);
        System.assertEquals(3, finalRow.RAA_Processed_Users__c);
        System.assertEquals(2, finalRow.RAA_Users_With_Access__c);
        System.assertEquals(5, finalRow.RAA_Total_Users__c);

        RAA_Analysis__c stillActive = repo.findActiveAnalysisForRecord(acct.Id);
        System.assertEquals(null, stillActive, 'A completed analysis should no longer be considered active.');
    }

    @IsTest
    static void markFailedAndMarkCancelledSetExpectedFields() {
        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id failedId = repo.createAnalysis(UserInfo.getUserId(), 'User', 'Failed Test', UserInfo.getUserId(), false, false);
        Id cancelledId = repo.createAnalysis(UserInfo.getUserId(), 'User', 'Cancelled Test', UserInfo.getUserId(), false, false);

        Test.startTest();
        repo.markFailed(failedId, 'Something went wrong.');
        repo.markCancelled(cancelledId);
        Test.stopTest();

        System.assertEquals('Failed', repo.getAnalysis(failedId).RAA_Status__c);
        System.assertEquals('Something went wrong.', repo.getAnalysis(failedId).RAA_Error_Details__c);
        System.assertEquals('Cancelled', repo.getAnalysis(cancelledId).RAA_Status__c);
    }

    @IsTest
    static void deleteAnalysisCascadesToChildren() {
        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id analysisId = repo.createAnalysis(UserInfo.getUserId(), 'User', 'Delete Test', UserInfo.getUserId(), false, false);

        List<RAA_ReasonAggregator.AggregatedUserResult> aggregated = new List<RAA_ReasonAggregator.AggregatedUserResult>();
        RAA_ReasonAggregator.AggregatedUserResult single = new RAA_ReasonAggregator.AggregatedUserResult();
        single.userId = UserInfo.getUserId();
        single.effectiveAccess = RAA_TestDataFactory.fullAccess(UserInfo.getUserId());
        single.reasons = new List<RAA_AccessReasonDTO>{ RAA_TestDataFactory.buildReason('Ownership', 'High') };
        aggregated.add(single);

        Map<Id, User> userInfoMap = new Map<Id, User>([SELECT Id, Name, Username, UserType, IsActive, Profile.Name FROM User WHERE Id = :UserInfo.getUserId()]);
        repo.saveResults(analysisId, aggregated, userInfoMap);

        Test.startTest();
        repo.deleteAnalysis(analysisId);
        Test.stopTest();

        System.assertEquals(null, repo.getAnalysis(analysisId), 'The analysis should no longer exist after deletion.');
        System.assertEquals(0, [SELECT COUNT() FROM RAA_Access_Result__c WHERE RAA_Analysis__c = :analysisId], 'Child results should cascade-delete.');
    }

    @IsTest
    static void savingResultsTwiceUpdatesRatherThanDuplicates() {
        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id analysisId = repo.createAnalysis(UserInfo.getUserId(), 'User', 'Dedupe Test', UserInfo.getUserId(), false, false);
        Map<Id, User> userInfoMap = new Map<Id, User>([SELECT Id, Name, Username, UserType, IsActive, Profile.Name FROM User WHERE Id = :UserInfo.getUserId()]);

        RAA_ReasonAggregator.AggregatedUserResult firstPass = new RAA_ReasonAggregator.AggregatedUserResult();
        firstPass.userId = UserInfo.getUserId();
        firstPass.effectiveAccess = RAA_TestDataFactory.readOnlyAccess(UserInfo.getUserId());
        firstPass.reasons = new List<RAA_AccessReasonDTO>{ RAA_TestDataFactory.buildReason('Ownership', 'High') };

        Test.startTest();
        repo.saveResults(analysisId, new List<RAA_ReasonAggregator.AggregatedUserResult>{ firstPass }, userInfoMap);

        RAA_ReasonAggregator.AggregatedUserResult secondPass = new RAA_ReasonAggregator.AggregatedUserResult();
        secondPass.userId = UserInfo.getUserId();
        secondPass.effectiveAccess = RAA_TestDataFactory.fullAccess(UserInfo.getUserId());
        secondPass.reasons = new List<RAA_AccessReasonDTO>{
                RAA_TestDataFactory.buildReason('Ownership', 'High'),
                RAA_TestDataFactory.buildReason('Permission', 'High')
        };
        repo.saveResults(analysisId, new List<RAA_ReasonAggregator.AggregatedUserResult>{ secondPass }, userInfoMap);
        Test.stopTest();

        List<RAA_Access_Result__c> resultRows = [SELECT Id, RAA_Max_Access_Level__c FROM RAA_Access_Result__c WHERE RAA_Analysis__c = :analysisId];
        System.assertEquals(1, resultRows.size(), 'Re-saving the same user should update the existing row, not create a duplicate.');
        System.assertEquals('All', resultRows[0].RAA_Max_Access_Level__c, 'The second save should have overwritten the first.');
        System.assertEquals(2, [SELECT COUNT() FROM RAA_Access_Reason__c WHERE RAA_Access_Result__c = :resultRows[0].Id], 'Reasons should reflect only the latest save, not accumulate.');
    }
}
