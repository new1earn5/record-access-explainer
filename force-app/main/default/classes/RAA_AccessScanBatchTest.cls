@IsTest
private class RAA_AccessScanBatchTest {

    @IsTest
    static void progressAccumulatesAcrossMultipleChunksAndCompletes() {
        Account acct = new Account(Name = 'RAA Batch Account');
        insert acct;

        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id analysisId = repo.createAnalysis(acct.Id, 'Account', 'RAA Batch Account', UserInfo.getUserId(), false, false);

        RAA_UserPopulationBuilder.PopulationFilter filter = new RAA_UserPopulationBuilder.PopulationFilter();

        Test.startTest();
        Database.executeBatch(new RAA_AccessScanBatch(analysisId, acct.Id, filter), 20);
        Test.stopTest();

        RAA_Analysis__c completed = repo.getAnalysis(analysisId);
        System.assert(
                completed.RAA_Status__c == 'Completed' || completed.RAA_Status__c == 'Completed with Warnings',
                'Batch should reach a terminal completed status, got: ' + completed.RAA_Status__c);
        System.assertEquals(completed.RAA_Total_Users__c, completed.RAA_Processed_Users__c,
                'All users in the population should have been processed.');
        System.assertNotEquals(null, completed.RAA_Started_At__c);
        System.assertNotEquals(null, completed.RAA_Completed_At__c);
    }

    @IsTest
    static void executeRecordsAWarningWhenTheAnalyzedRecordDisappearsMidScan() {
        Account acct = new Account(Name = 'RAA Batch Vanishing Account');
        insert acct;
        Id acctId = acct.Id;

        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id analysisId = repo.createAnalysis(acctId, 'Account', 'RAA Batch Vanishing Account', UserInfo.getUserId(), false, false);

        RAA_UserPopulationBuilder.PopulationFilter filter = new RAA_UserPopulationBuilder.PopulationFilter();

        delete acct;

        Test.startTest();
        Database.executeBatch(new RAA_AccessScanBatch(analysisId, acctId, filter), 20);
        Test.stopTest();

        RAA_Analysis__c result = repo.getAnalysis(analysisId);
        System.assertEquals('Completed with Warnings', result.RAA_Status__c,
                'A chunk failure should be recorded as a warning rather than crashing the whole scan.');
        System.assert(result.RAA_Warnings__c != null && result.RAA_Warnings__c.contains('could not be analyzed'));
    }

    @IsTest
    static void finishDoesNotOverwriteACancelledAnalysis() {
        Account acct = new Account(Name = 'RAA Batch Cancel Account');
        insert acct;

        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id analysisId = repo.createAnalysis(acct.Id, 'Account', 'RAA Batch Cancel Account', UserInfo.getUserId(), false, false);

        RAA_UserPopulationBuilder.PopulationFilter filter = new RAA_UserPopulationBuilder.PopulationFilter();

        Test.startTest();
        Database.executeBatch(new RAA_AccessScanBatch(analysisId, acct.Id, filter), 20);
        repo.markCancelled(analysisId);
        Test.stopTest();

        System.assertEquals('Cancelled', repo.getAnalysis(analysisId).RAA_Status__c,
                'finish() must not overwrite a status that was explicitly set to Cancelled.');
    }
}
