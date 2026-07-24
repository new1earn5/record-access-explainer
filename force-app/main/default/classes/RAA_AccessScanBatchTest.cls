@IsTest
private class RAA_AccessScanBatchTest {
    @IsTest
    static void progressAccumulatesAcrossMultipleChunksAndCompletes() {
        Account acct = new Account(Name = 'RAA Batch Account');
        insert acct;

        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id analysisId = repo.createAnalysis(
            acct.Id,
            'Account',
            'RAA Batch Account',
            UserInfo.getUserId(),
            false,
            false
        );

        RAA_UserPopulationBuilder.PopulationFilter filter = new RAA_UserPopulationBuilder.PopulationFilter();

        Test.startTest();
        Database.executeBatch(new RAA_AccessScanBatch(analysisId, acct.Id, filter), 20);
        Test.stopTest();

        RAA_Analysis__c completed = repo.getAnalysis(analysisId);
        System.assert(
            completed.RAA_Status__c == 'Completed' || completed.RAA_Status__c == 'Completed with Warnings',
            'Batch should reach a terminal completed status, got: ' + completed.RAA_Status__c
        );
        System.assertEquals(
            completed.RAA_Total_Users__c,
            completed.RAA_Processed_Users__c,
            'All users in the population should have been processed.'
        );
        System.assertNotEquals(null, completed.RAA_Started_At__c);
        System.assertNotEquals(null, completed.RAA_Completed_At__c);
    }

    @IsTest
    static void executeRecordsAWarningWhenTheAnalyzedRecordDisappearsMidScan() {
        Account acct = new Account(Name = 'RAA Batch Vanishing Account');
        insert acct;
        Id acctId = acct.Id;

        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id analysisId = repo.createAnalysis(
            acctId,
            'Account',
            'RAA Batch Vanishing Account',
            UserInfo.getUserId(),
            false,
            false
        );

        RAA_UserPopulationBuilder.PopulationFilter filter = new RAA_UserPopulationBuilder.PopulationFilter();

        delete acct;

        Test.startTest();
        Database.executeBatch(new RAA_AccessScanBatch(analysisId, acctId, filter), 20);
        Test.stopTest();

        RAA_Analysis__c result = repo.getAnalysis(analysisId);
        System.assertEquals(
            'Completed with Warnings',
            result.RAA_Status__c,
            'A chunk failure should be recorded as a warning rather than crashing the whole scan.'
        );
        System.assert(result.RAA_Warnings__c != null && result.RAA_Warnings__c.contains('could not be analyzed'));
    }

    @IsTest
    static void finishDoesNotOverwriteACancelledAnalysis() {
        Account acct = new Account(Name = 'RAA Batch Cancel Account');
        insert acct;

        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id analysisId = repo.createAnalysis(
            acct.Id,
            'Account',
            'RAA Batch Cancel Account',
            UserInfo.getUserId(),
            false,
            false
        );

        RAA_UserPopulationBuilder.PopulationFilter filter = new RAA_UserPopulationBuilder.PopulationFilter();

        Test.startTest();
        Database.executeBatch(new RAA_AccessScanBatch(analysisId, acct.Id, filter), 20);
        repo.markCancelled(analysisId);
        Test.stopTest();

        System.assertEquals(
            'Cancelled',
            repo.getAnalysis(analysisId).RAA_Status__c,
            'finish() must not overwrite a status that was explicitly set to Cancelled.'
        );
    }

    @IsTest
    static void finishDoesNotOverwriteAnAnalysisThatFailedBeforeItRan() {
        Account acct = new Account(Name = 'RAA Batch Already Failed Account');
        insert acct;

        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id analysisId = repo.createAnalysis(
            acct.Id,
            'Account',
            'RAA Batch Already Failed Account',
            UserInfo.getUserId(),
            false,
            false
        );

        RAA_UserPopulationBuilder.PopulationFilter filter = new RAA_UserPopulationBuilder.PopulationFilter();

        Test.startTest();
        Database.executeBatch(new RAA_AccessScanBatch(analysisId, acct.Id, filter), 20);
        // Simulates start() itself already marking this Failed (for example, exceeding
        // RAA_Max_Users_Per_Scan__c) and returning before any chunk ran - finish() still fires
        // afterward regardless, and must not silently turn this back into "Completed".
        repo.markFailed(analysisId, 'simulated failure before any chunk ran');
        Test.stopTest();

        System.assertEquals(
            'Failed',
            repo.getAnalysis(analysisId).RAA_Status__c,
            'finish() must not overwrite a status that was already terminal when it ran.'
        );
    }

    @IsTest
    static void finishPublishesAScanStatusEventOnNormalCompletion() {
        Account acct = new Account(Name = 'RAA Batch Event Account');
        insert acct;

        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id analysisId = repo.createAnalysis(
            acct.Id,
            'Account',
            'RAA Batch Event Account',
            UserInfo.getUserId(),
            false,
            false
        );

        RAA_UserPopulationBuilder.PopulationFilter filter = new RAA_UserPopulationBuilder.PopulationFilter();

        Test.startTest();
        Database.executeBatch(new RAA_AccessScanBatch(analysisId, acct.Id, filter), 20);
        Test.stopTest();
        // EventBus.publish inside finish() queues the platform event for delivery; Test.getEventBus().deliver()
        // forces that delivery to run synchronously so a subscriber trigger would fire within this test - there
        // is no Apex-side subscriber here, so this only confirms publishing and delivery complete without error.
        Test.getEventBus().deliver();

        RAA_Analysis__c completed = repo.getAnalysis(analysisId);
        System.assert(
            completed.RAA_Status__c == 'Completed' || completed.RAA_Status__c == 'Completed with Warnings',
            'Sanity check that the batch actually completed, independent of the event.'
        );
    }
}
