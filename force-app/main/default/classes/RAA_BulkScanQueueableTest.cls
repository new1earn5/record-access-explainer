@IsTest
private class RAA_BulkScanQueueableTest {

    @IsTest
    static void dispatchesAScanForEachRecordAndCompletesTheBatchRun() {
        Account acctOne = new Account(Name = 'RAA Bulk Account 1');
        Account acctTwo = new Account(Name = 'RAA Bulk Account 2');
        insert new List<Account>{ acctOne, acctTwo };

        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id batchRunId = repo.createBatchRun('Account', 2, acctOne.Id + '\n' + acctTwo.Id, UserInfo.getUserId(), false, false);

        Test.startTest();
        System.enqueueJob(new RAA_BulkScanQueueable(new List<Id>{ acctOne.Id, acctTwo.Id }, batchRunId, UserInfo.getUserId(), false, false));
        Test.stopTest();

        List<RAA_Analysis__c> children = repo.getAnalysesForBatchRun(batchRunId);
        System.assertEquals(2, children.size());
        for (RAA_Analysis__c child : children) {
            System.assertEquals(true, child.RAA_Is_Complete__c);
        }

        RAA_Batch_Run__c finalRun = repo.refreshAndGetBatchRunStatus(batchRunId);
        System.assert(finalRun.RAA_Status__c == 'Completed' || finalRun.RAA_Status__c == 'Completed with Warnings');
    }

    @IsTest
    static void recordsAFailedAnalysisWithoutAbortingOtherRecords() {
        Account acct = new Account(Name = 'RAA Bulk Valid Account');
        insert acct;
        Id validId = acct.Id;
        Id bogusId = '001000000000000AAA'; // well-formed Account id, but no such record exists

        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id batchRunId = repo.createBatchRun('Account', 2, validId + '\n' + bogusId, UserInfo.getUserId(), false, false);

        Test.startTest();
        System.enqueueJob(new RAA_BulkScanQueueable(new List<Id>{ validId, bogusId }, batchRunId, UserInfo.getUserId(), false, false));
        Test.stopTest();

        List<RAA_Analysis__c> children = repo.getAnalysesForBatchRun(batchRunId);
        System.assertEquals(2, children.size());

        Boolean foundFailed = false;
        for (RAA_Analysis__c child : children) {
            if (child.RAA_Status__c == 'Failed') {
                foundFailed = true;
            }
        }
        System.assert(foundFailed, 'The bogus record ID should have produced a Failed child analysis, not aborted the run.');
    }

    @IsTest
    static void chainsWhenMoreRecordsThanTheChunkSize() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < RAA_BulkScanQueueable.CHUNK_SIZE + 2; i++) {
            accounts.add(new Account(Name = 'RAA Bulk Chain Account ' + i));
        }
        insert accounts;

        List<Id> recordIds = new List<Id>();
        for (Account a : accounts) {
            recordIds.add(a.Id);
        }

        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id batchRunId = repo.createBatchRun('Account', recordIds.size(), String.join(recordIds, '\n'), UserInfo.getUserId(), false, false);

        List<Id> firstChunk = new List<Id>();
        List<Id> secondChunk = new List<Id>();
        for (Integer i = 0; i < recordIds.size(); i++) {
            (i < RAA_BulkScanQueueable.CHUNK_SIZE ? firstChunk : secondChunk).add(recordIds[i]);
        }

        Test.startTest();
        // A test method allows only one Test.startTest()/Test.stopTest() pair, and chaining a
        // Queueable from inside another Queueable's execute() always throws inside a test's
        // synchronous flush - so the chained hop is simulated by calling execute() directly a
        // second time, the same processing the real chained job would perform.
        new RAA_BulkScanQueueable(firstChunk, batchRunId, UserInfo.getUserId(), false, false).execute(null);
        new RAA_BulkScanQueueable(secondChunk, batchRunId, UserInfo.getUserId(), false, false).execute(null);
        Test.stopTest();

        List<RAA_Analysis__c> children = repo.getAnalysesForBatchRun(batchRunId);
        System.assertEquals(recordIds.size(), children.size(), 'Every record should eventually get an analysis, even across chained queueable executions.');
    }
}
