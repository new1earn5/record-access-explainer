@IsTest
private class RAA_CleanupSchedulerTest {

    @IsTest
    static void deletesOldCompletedAnalysesButKeepsRecentOnes() {
        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();

        Id oldAnalysisId = repo.createAnalysis(UserInfo.getUserId(), 'User', 'Old', UserInfo.getUserId(), false, false);
        repo.markCompleted(oldAnalysisId, false, null);
        update new RAA_Analysis__c(Id = oldAnalysisId, RAA_Completed_At__c = System.now().addDays(-100));

        Id recentAnalysisId = repo.createAnalysis(UserInfo.getUserId(), 'User', 'Recent', UserInfo.getUserId(), false, false);
        repo.markCompleted(recentAnalysisId, false, null);

        Id incompleteAnalysisId = repo.createAnalysis(UserInfo.getUserId(), 'User', 'Incomplete', UserInfo.getUserId(), false, false);

        Test.startTest();
        System.schedule('RAA Cleanup Test ' + Crypto.getRandomInteger(), '0 0 2 * * ?', new RAA_CleanupScheduler(90));
        Test.stopTest();

        System.assertEquals(null, repo.getAnalysis(oldAnalysisId), 'A completed analysis older than the retention window should be deleted.');
        System.assertNotEquals(null, repo.getAnalysis(recentAnalysisId), 'A recently completed analysis should be kept.');
        System.assertNotEquals(null, repo.getAnalysis(incompleteAnalysisId), 'An incomplete analysis should never be deleted regardless of age.');
    }

    @IsTest
    static void zeroRetentionDisablesCleanup() {
        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id oldAnalysisId = repo.createAnalysis(UserInfo.getUserId(), 'User', 'Old', UserInfo.getUserId(), false, false);
        repo.markCompleted(oldAnalysisId, false, null);
        update new RAA_Analysis__c(Id = oldAnalysisId, RAA_Completed_At__c = System.now().addDays(-500));

        Test.startTest();
        System.schedule('RAA Cleanup Disabled Test ' + Crypto.getRandomInteger(), '0 0 3 * * ?', new RAA_CleanupScheduler(0));
        Test.stopTest();

        System.assertNotEquals(null, repo.getAnalysis(oldAnalysisId), 'A retention of zero should disable cleanup entirely.');
    }

    @IsTest
    static void defaultConstructorUsesPackagedSettingsAndHandlesNothingToDelete() {
        // No completed analyses old enough to expire exist in this fresh test transaction, so
        // this also exercises the "nothing to delete" path using the real RAA_Settings__mdt
        // retention value (production scheduling always uses this no-argument constructor).
        Test.startTest();
        System.schedule('RAA Cleanup Default Test ' + Crypto.getRandomInteger(), '0 0 4 * * ?', new RAA_CleanupScheduler());
        Test.stopTest();

        System.assert(true, 'Scheduling and executing with the default constructor should not throw.');
    }
}
