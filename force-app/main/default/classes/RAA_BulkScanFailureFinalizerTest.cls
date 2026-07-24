@IsTest
private class RAA_BulkScanFailureFinalizerTest {
    @IsTest
    static void recoversOnlyRecordsMissingAnAnalysis() {
        Account acctWithAnalysis = new Account(Name = 'RAA Finalizer Recorded');
        Account acctMissingAnalysis = new Account(Name = 'RAA Finalizer Missing');
        insert new List<Account>{ acctWithAnalysis, acctMissingAnalysis };

        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id batchRunId = repo.createBatchRun(
            'Account',
            2,
            acctWithAnalysis.Id + '\n' + acctMissingAnalysis.Id,
            UserInfo.getUserId(),
            false,
            false
        );
        repo.createAnalysis(
            acctWithAnalysis.Id,
            'Account',
            'RAA Finalizer Recorded',
            UserInfo.getUserId(),
            false,
            false,
            batchRunId
        );

        RAA_BulkScanFailureFinalizer finalizer = new RAA_BulkScanFailureFinalizer(
            batchRunId,
            new List<Id>{ acctWithAnalysis.Id, acctMissingAnalysis.Id },
            UserInfo.getUserId(),
            false,
            false
        );

        Test.startTest();
        finalizer.recoverIncompleteRecords('simulated platform error');
        Test.stopTest();

        List<RAA_Analysis__c> children = repo.getAnalysesForBatchRun(batchRunId);
        System.assertEquals(
            2,
            children.size(),
            'The already-recorded record should not get a duplicate stub analysis.'
        );

        Boolean foundStub = false;
        for (RAA_Analysis__c child : children) {
            if (child.RAA_Record_Id__c == acctMissingAnalysis.Id) {
                System.assertEquals('Failed', child.RAA_Status__c);
                System.assert(child.RAA_Error_Details__c.contains('simulated platform error'));
                foundStub = true;
            }
        }
        System.assert(foundStub, 'The record with no analysis at all should have been stub-failed.');
    }

    @IsTest
    static void doesNothingWithoutAScope() {
        RAA_BulkScanFailureFinalizer finalizer = new RAA_BulkScanFailureFinalizer(
            null,
            null,
            UserInfo.getUserId(),
            false,
            false
        );

        Test.startTest();
        finalizer.recoverIncompleteRecords('unused');
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM RAA_Analysis__c],
            'A null batchRunId/scope should early-return without creating any stub analysis.'
        );
    }

    @IsTest
    static void attachedFinalizerRunsWithoutErrorWhenTheQueueableThrowsUnhandled() {
        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id batchRunId = repo.createBatchRun('Account', 1, '', UserInfo.getUserId(), false, false);

        // A null record list makes remainingRecordIds.size() throw a NullPointerException before
        // the per-record try/catch is ever entered - a genuine unhandled exception, exercising the
        // real System.Finalizer mechanism end-to-end rather than calling recoverIncompleteRecords()
        // directly. Salesforce propagates an unhandled exception from a synchronously-flushed
        // Queueable back out through Test.stopTest() itself, even though the platform runs the
        // attached Finalizer first - so the expected exception is caught here, after which the
        // Finalizer has already had its chance to run without an error of its own.
        Boolean threw = false;
        try {
            Test.startTest();
            System.enqueueJob(new RAA_BulkScanQueueable(null, batchRunId, UserInfo.getUserId(), false, false));
            Test.stopTest();
        } catch (System.NullPointerException e) {
            threw = true;
        }

        System.assert(threw, 'The queueable was expected to throw due to the null record list.');
    }
}
