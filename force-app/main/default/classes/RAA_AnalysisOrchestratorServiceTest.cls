@IsTest
private class RAA_AnalysisOrchestratorServiceTest {
    private static RAA_AnalysisRequestDTO buildRequest(Id recordId) {
        RAA_AnalysisRequestDTO request = new RAA_AnalysisRequestDTO();
        request.recordId = String.valueOf(recordId);
        request.includeExternalUsers = false;
        request.includeInactiveUsers = false;
        return request;
    }

    @IsTest
    static void startAnalysisRunsBatchAndProducesResultsForTheOwner() {
        Account acct = new Account(Name = 'RAA Orchestrator Account');
        insert acct; // owned by the running (test) user

        RAA_AnalysisOrchestratorService service = new RAA_AnalysisOrchestratorService();

        Test.startTest();
        RAA_AnalysisSummaryDTO summary = service.startAnalysis(buildRequest(acct.Id), UserInfo.getUserId());
        Test.stopTest();

        RAA_AnalysisSummaryDTO finalStatus = service.getStatus(summary.analysisId);
        System.assert(
            finalStatus.status == 'Completed' || finalStatus.status == 'Completed with Warnings',
            'Expected the scan to finish in this synchronous test context, got: ' + finalStatus.status
        );

        List<RAA_AccessResultDTO> results = service.getResults(summary.analysisId);
        Boolean foundOwner = false;
        for (RAA_AccessResultDTO result : results) {
            if (result.userId == UserInfo.getUserId()) {
                foundOwner = true;
                System.assertEquals(true, result.hasReadAccess, 'The owner should have read access.');
                System.assert(!result.reasons.isEmpty(), 'The owner should have at least one detected reason.');
            }
        }
        System.assert(foundOwner, 'The record owner should appear in the results.');
    }

    @IsTest
    static void blocksDuplicateConcurrentScanUnlessConfirmed() {
        Account acct = new Account(Name = 'RAA Duplicate Account');
        insert acct;

        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        repo.createAnalysis(acct.Id, 'Account', 'RAA Duplicate Account', UserInfo.getUserId(), false, false);

        RAA_AnalysisOrchestratorService service = new RAA_AnalysisOrchestratorService();

        try {
            service.startAnalysis(buildRequest(acct.Id), UserInfo.getUserId());
            System.assert(false, 'Expected a duplicate-scan exception.');
        } catch (RAA_AppException e) {
            System.assert(e.getMessage().contains('already'), 'Message should explain a scan is already in progress.');
        }

        RAA_AnalysisRequestDTO confirmed = buildRequest(acct.Id);
        confirmed.confirmDuplicateScan = true;

        Test.startTest();
        RAA_AnalysisSummaryDTO summary = service.startAnalysis(confirmed, UserInfo.getUserId());
        Test.stopTest();

        System.assertNotEquals(null, summary.analysisId, 'Confirming the duplicate scan should allow it to proceed.');
    }

    // '707000000000002AAA' below is a well-formed but nonexistent AsyncApexJob id fixture.
    @IsTest
    @SuppressWarnings('PMD.AvoidHardcodingId')
    static void cancelBeforeCompletionMarksAnalysisCancelled() {
        Account acct = new Account(Name = 'RAA Cancel Account');
        insert acct;

        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id analysisId = repo.createAnalysis(
            acct.Id,
            'Account',
            'RAA Cancel Account',
            UserInfo.getUserId(),
            false,
            false
        );
        repo.markBatchStarted(analysisId, '707000000000002AAA', 1);

        RAA_AnalysisOrchestratorService service = new RAA_AnalysisOrchestratorService();

        Test.startTest();
        RAA_AnalysisSummaryDTO cancelled = service.cancelAnalysis(analysisId);
        Test.stopTest();

        System.assertEquals('Cancelled', cancelled.status);
        System.assertEquals(true, cancelled.isComplete);
    }

    @IsTest
    static void cancelAlreadyCompletedAnalysisThrows() {
        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id analysisId = repo.createAnalysis(
            UserInfo.getUserId(),
            'User',
            'Already Done',
            UserInfo.getUserId(),
            false,
            false
        );
        repo.markCompleted(analysisId, false, null);

        try {
            new RAA_AnalysisOrchestratorService().cancelAnalysis(analysisId);
            System.assert(false, 'Expected an exception when cancelling a completed analysis.');
        } catch (RAA_AppException e) {
            System.assert(e.getMessage().contains('already finished'));
        }
    }

    @IsTest
    static void deleteAnalysisRemovesRecord() {
        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id analysisId = repo.createAnalysis(
            UserInfo.getUserId(),
            'User',
            'Delete Me',
            UserInfo.getUserId(),
            false,
            false
        );

        Test.startTest();
        new RAA_AnalysisOrchestratorService().deleteAnalysis(analysisId);
        Test.stopTest();

        System.assertEquals(null, repo.getAnalysis(analysisId));
    }

    @IsTest
    static void getStatusThrowsForUnknownAnalysis() {
        RAA_Analysis__c analysis = RAA_TestDataFactory.createAnalysis(UserInfo.getUserId(), 'User');
        Id analysisId = analysis.Id;
        delete analysis;

        try {
            new RAA_AnalysisOrchestratorService().getStatus(analysisId);
            System.assert(false, 'Expected an exception for a deleted/unknown analysis.');
        } catch (RAA_AppException e) {
            System.assert(e.getMessage().contains('could not be found'));
        }
    }

    @IsTest
    static void startBulkAnalysisDispatchesOneScanPerRecord() {
        Account acctOne = new Account(Name = 'RAA Orchestrator Bulk 1');
        Account acctTwo = new Account(Name = 'RAA Orchestrator Bulk 2');
        insert new List<Account>{ acctOne, acctTwo };

        RAA_AnalysisOrchestratorService service = new RAA_AnalysisOrchestratorService();

        Test.startTest();
        RAA_BatchRunSummaryDTO summary = service.startBulkAnalysis(
            new List<String>{ String.valueOf(acctOne.Id), String.valueOf(acctTwo.Id) },
            false,
            false,
            UserInfo.getUserId()
        );
        Test.stopTest();

        RAA_BatchRunSummaryDTO finalStatus = service.getBatchRunStatus(summary.batchRunId);
        System.assertEquals(2, finalStatus.analyses.size());
        System.assertEquals(2, finalStatus.completedRecords);
    }

    @IsTest
    static void startBulkAnalysisRejectsMixedObjectTypes() {
        Account acct = new Account(Name = 'RAA Orchestrator Mixed');
        insert acct;

        try {
            new RAA_AnalysisOrchestratorService()
                .startBulkAnalysis(
                    new List<String>{ String.valueOf(acct.Id), String.valueOf(UserInfo.getUserId()) },
                    false,
                    false,
                    UserInfo.getUserId()
                );
            System.assert(false, 'Expected an exception for mixed object types.');
        } catch (RAA_AppException e) {
            System.assert(e.getMessage().contains('same object type'));
        }
    }

    @IsTest
    static void getDiffAgainstPreviousReturnsNullForFirstScan() {
        Account acct = new Account(Name = 'RAA Orchestrator Diff Account');
        insert acct;

        RAA_AnalysisOrchestratorService service = new RAA_AnalysisOrchestratorService();

        Test.startTest();
        RAA_AnalysisSummaryDTO summary = service.startAnalysis(buildRequest(acct.Id), UserInfo.getUserId());
        Test.stopTest();

        RAA_AnalysisDiffDTO diff = service.getDiffAgainstPrevious(summary.analysisId);
        System.assertEquals(null, diff);
    }

    @IsTest
    static void subscriptionLifecycleCreateListToggleDelete() {
        Account acct = new Account(Name = 'RAA Orchestrator Subscription Account');
        insert acct;

        RAA_AnalysisOrchestratorService service = new RAA_AnalysisOrchestratorService();

        Test.startTest();
        Id subscriptionId = service.createSubscription(
            String.valueOf(acct.Id),
            false,
            false,
            true,
            UserInfo.getUserId()
        );
        Test.stopTest();

        List<RAA_SubscriptionDTO> mine = service.listMySubscriptions(UserInfo.getUserId());
        System.assertEquals(1, mine.size());
        System.assertEquals(true, mine[0].isActive);

        service.setSubscriptionActive(subscriptionId, false);
        List<RAA_SubscriptionDTO> afterPause = service.listMySubscriptions(UserInfo.getUserId());
        System.assertEquals(false, afterPause[0].isActive);

        service.deleteSubscription(subscriptionId);
        System.assertEquals(0, service.listMySubscriptions(UserInfo.getUserId()).size());
    }

    @IsTest
    static void scanUserAccessAndFieldAccessReturnData() {
        Account acct = new Account(Name = 'RAA Orchestrator User Access Account');
        insert acct;

        RAA_AnalysisOrchestratorService service = new RAA_AnalysisOrchestratorService();

        List<RAA_UserRecordAccessSummaryDTO> accessResults = service.scanUserAccess(
            UserInfo.getUserId(),
            'Account',
            new List<String>{ String.valueOf(acct.Id) },
            null
        );
        System.assertEquals(1, accessResults.size());
        System.assertEquals(true, accessResults[0].hasAnyAccess);

        List<RAA_AccessReasonDTO> reasons = service.getUserAccessReasons(UserInfo.getUserId(), acct.Id);
        System.assert(!reasons.isEmpty());

        List<RAA_FieldAccessDTO> fields = service.getFieldAccess(UserInfo.getUserId(), 'Account');
        System.assert(!fields.isEmpty());
    }
}
