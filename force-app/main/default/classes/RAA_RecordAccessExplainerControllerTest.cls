@IsTest
private class RAA_RecordAccessExplainerControllerTest {
    @TestSetup
    static void setup() {
        User owner = RAA_TestDataFactory.createUser('Ctrl', 'Owner');
        User otherReader = RAA_TestDataFactory.createUser('Ctrl', 'OtherReader');

        PermissionSet auditorSet = [SELECT Id FROM PermissionSet WHERE Name = 'RAA_Record_Access_Auditor' LIMIT 1];
        insert new List<PermissionSetAssignment>{
            new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = auditorSet.Id),
            new PermissionSetAssignment(AssigneeId = owner.Id, PermissionSetId = auditorSet.Id),
            new PermissionSetAssignment(AssigneeId = otherReader.Id, PermissionSetId = auditorSet.Id)
        };
    }

    @IsTest
    static void authorizedUserCanRunFullLifecycle() {
        RAA_PermissionChecker.testOverride = true;

        Account acct = new Account(Name = 'RAA Controller Account');
        insert acct;

        RAA_AnalysisRequestDTO request = new RAA_AnalysisRequestDTO();
        request.recordId = String.valueOf(acct.Id);

        Test.startTest();
        RAA_AnalysisSummaryDTO summary = RAA_RecordAccessExplainerController.startAnalysis(request);
        Test.stopTest();

        RAA_AnalysisSummaryDTO status = RAA_RecordAccessExplainerController.getAnalysisStatus(summary.analysisId);
        System.assert(
            status.status == 'Completed' || status.status == 'Completed with Warnings',
            'Expected a terminal completed status, got: ' + status.status
        );

        List<RAA_AccessResultDTO> results = RAA_RecordAccessExplainerController.getResults(summary.analysisId);
        System.assert(!results.isEmpty(), 'Expected at least one result (the owner).');

        String resultsCsv = RAA_RecordAccessExplainerController.exportResultsCsv(summary.analysisId);
        System.assert(resultsCsv.startsWith('User,Username'));

        String reasonsCsv = RAA_RecordAccessExplainerController.exportReasonsCsv(summary.analysisId);
        System.assert(reasonsCsv.startsWith('User,Username,Category'));

        RAA_RecordAccessExplainerController.deleteAnalysis(summary.analysisId);
    }

    @IsTest
    static void getDefaultSettingsReturnsPackagedDefaults() {
        RAA_PermissionChecker.testOverride = true;

        Test.startTest();
        RAA_SettingsDTO settings = RAA_RecordAccessExplainerController.getDefaultSettings();
        Test.stopTest();

        System.assertEquals(false, settings.defaultIncludeExternalUsers);
        System.assertEquals(false, settings.defaultIncludeInactiveUsers);
        System.assertEquals(0, settings.maxUsersPerScan);
    }

    @IsTest
    static void hasRunPermissionReflectsOverride() {
        RAA_PermissionChecker.testOverride = true;

        Test.startTest();
        Boolean result = RAA_RecordAccessExplainerController.hasRunPermission();
        Test.stopTest();

        System.assertEquals(true, result);
    }

    @IsTest
    static void unauthorizedUserCannotStartAnalysis() {
        RAA_PermissionChecker.testOverride = false;

        RAA_AnalysisRequestDTO request = new RAA_AnalysisRequestDTO();
        request.recordId = String.valueOf(UserInfo.getUserId());

        try {
            RAA_RecordAccessExplainerController.startAnalysis(request);
            System.assert(false, 'Expected an AuraHandledException for a user without the custom permission.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('permission'), 'Message should explain the permission requirement.');
        }
    }

    @IsTest
    static void invalidRecordIdProducesFriendlyValidationError() {
        RAA_PermissionChecker.testOverride = true;

        RAA_AnalysisRequestDTO request = new RAA_AnalysisRequestDTO();
        request.recordId = 'not-an-id';

        try {
            RAA_RecordAccessExplainerController.startAnalysis(request);
            System.assert(false, 'Expected a friendly validation error for a malformed record ID.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('not a valid Salesforce record ID'));
        }
    }

    @IsTest
    static void cannotReadAnalysisBelongingToAnotherUser() {
        RAA_PermissionChecker.testOverride = true;

        User owner = [SELECT Id FROM User WHERE LastName = 'Owner' LIMIT 1];
        User otherReader = [SELECT Id FROM User WHERE LastName = 'OtherReader' LIMIT 1];

        Id analysisId;
        System.runAs(owner) {
            RAA_Analysis__c analysis = new RAA_Analysis__c(
                RAA_Record_Id__c = owner.Id,
                RAA_Object_API_Name__c = 'User',
                RAA_Status__c = 'Completed',
                RAA_Requested_By__c = owner.Id,
                RAA_Requested_At__c = System.now(),
                RAA_Is_Complete__c = true
            );
            insert analysis;
            analysisId = analysis.Id;
        }

        Test.startTest();
        System.runAs(otherReader) {
            try {
                RAA_RecordAccessExplainerController.getAnalysisStatus(String.valueOf(analysisId));
                System.assert(false, 'A Private-OWD analysis owned by another standard user should not be visible.');
            } catch (AuraHandledException e) {
                System.assert(
                    e.getMessage().contains('could not be found'),
                    'Should not reveal that the record exists.'
                );
            }
        }
        Test.stopTest();
    }

    // '707000000000003AAA' below is a well-formed but nonexistent AsyncApexJob id fixture.
    @IsTest
    @SuppressWarnings('PMD.AvoidHardcodingId')
    static void cancelAnalysisSucceedsForRunningScan() {
        RAA_PermissionChecker.testOverride = true;

        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id analysisId = repo.createAnalysis(
            UserInfo.getUserId(),
            'User',
            'Cancel Me',
            UserInfo.getUserId(),
            false,
            false
        );
        repo.markBatchStarted(analysisId, '707000000000003AAA', 1);

        Test.startTest();
        RAA_AnalysisSummaryDTO summary = RAA_RecordAccessExplainerController.cancelAnalysis(String.valueOf(analysisId));
        Test.stopTest();

        System.assertEquals('Cancelled', summary.status);
    }

    @IsTest
    static void cancelAnalysisWrapsOrchestratorAppExceptionForAlreadyCompletedScan() {
        RAA_PermissionChecker.testOverride = true;

        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id analysisId = repo.createAnalysis(
            UserInfo.getUserId(),
            'User',
            'Already Done',
            UserInfo.getUserId(),
            false,
            false
        );
        repo.markCompleted(analysisId, false, null, null);

        try {
            RAA_RecordAccessExplainerController.cancelAnalysis(String.valueOf(analysisId));
            System.assert(false, 'Expected an AuraHandledException for cancelling a completed analysis.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('already finished'));
        }
    }

    @IsTest
    static void deleteAnalysisRequiresValidId() {
        RAA_PermissionChecker.testOverride = true;

        try {
            RAA_RecordAccessExplainerController.deleteAnalysis('bogus');
            System.assert(false, 'Expected a validation error.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().length() > 0);
        }
    }

    @IsTest
    static void bulkScanLifecycleAndVisibility() {
        RAA_PermissionChecker.testOverride = true;

        Account acctOne = new Account(Name = 'RAA Ctrl Bulk 1');
        Account acctTwo = new Account(Name = 'RAA Ctrl Bulk 2');
        insert new List<Account>{ acctOne, acctTwo };

        Test.startTest();
        RAA_BatchRunSummaryDTO summary = RAA_RecordAccessExplainerController.startBulkAnalysis(
            new List<String>{ String.valueOf(acctOne.Id), String.valueOf(acctTwo.Id) },
            false,
            false
        );
        Test.stopTest();

        RAA_BatchRunSummaryDTO status = RAA_RecordAccessExplainerController.getBatchRunStatus(summary.batchRunId);
        System.assertEquals(2, status.analyses.size());
    }

    @IsTest
    static void cannotViewBatchRunBelongingToAnotherUser() {
        RAA_PermissionChecker.testOverride = true;

        User owner = [SELECT Id FROM User WHERE LastName = 'Owner' LIMIT 1];
        User otherReader = [SELECT Id FROM User WHERE LastName = 'OtherReader' LIMIT 1];

        Id batchRunId;
        System.runAs(owner) {
            RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
            batchRunId = repo.createBatchRun('User', 1, String.valueOf(owner.Id), owner.Id, false, false);
        }

        Test.startTest();
        System.runAs(otherReader) {
            try {
                RAA_RecordAccessExplainerController.getBatchRunStatus(String.valueOf(batchRunId));
                System.assert(false, 'A Private-OWD batch run owned by another user should not be visible.');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('could not be found'));
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void diffFieldAccessAndUserAccessEndpointsWork() {
        RAA_PermissionChecker.testOverride = true;

        Account acct = new Account(Name = 'RAA Ctrl Diff Account');
        insert acct;

        RAA_AnalysisRequestDTO request = new RAA_AnalysisRequestDTO();
        request.recordId = String.valueOf(acct.Id);

        Test.startTest();
        RAA_AnalysisSummaryDTO summary = RAA_RecordAccessExplainerController.startAnalysis(request);
        Test.stopTest();

        RAA_AnalysisDiffDTO diff = RAA_RecordAccessExplainerController.getAnalysisDiff(summary.analysisId);
        System.assertEquals(null, diff, 'No previous scan exists yet.');

        List<RAA_FieldAccessDTO> fields = RAA_RecordAccessExplainerController.getFieldAccess(
            String.valueOf(UserInfo.getUserId()),
            'Account'
        );
        System.assert(!fields.isEmpty());

        List<RAA_UserRecordAccessSummaryDTO> accessResults = RAA_RecordAccessExplainerController.scanUserAccess(
            String.valueOf(UserInfo.getUserId()),
            'Account',
            new List<String>{ String.valueOf(acct.Id) },
            null
        );
        System.assertEquals(1, accessResults.size());

        List<RAA_AccessReasonDTO> reasons = RAA_RecordAccessExplainerController.getUserAccessReasons(
            String.valueOf(UserInfo.getUserId()),
            String.valueOf(acct.Id)
        );
        System.assert(!reasons.isEmpty());
    }

    @IsTest
    static void fieldAccessRequiresAValidUserId() {
        RAA_PermissionChecker.testOverride = true;

        try {
            RAA_RecordAccessExplainerController.getFieldAccess('bogus', 'Account');
            System.assert(false, 'Expected a validation error for a malformed user ID.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().length() > 0);
        }
    }

    @IsTest
    static void fieldAccessRejectsIdThatIsNotAUser() {
        RAA_PermissionChecker.testOverride = true;

        Account acct = new Account(Name = 'RAA Ctrl Not A User Account');
        insert acct;

        try {
            RAA_RecordAccessExplainerController.getFieldAccess(String.valueOf(acct.Id), 'Account');
            System.assert(false, 'Expected a validation error for a non-User ID.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('User record'));
        }
    }

    @IsTest
    static void subscriptionEndpointsEnforceVisibility() {
        RAA_PermissionChecker.testOverride = true;

        User owner = [SELECT Id FROM User WHERE LastName = 'Owner' LIMIT 1];
        User otherReader = [SELECT Id FROM User WHERE LastName = 'OtherReader' LIMIT 1];

        Id subscriptionId;
        System.runAs(owner) {
            subscriptionId = RAA_RecordAccessExplainerController.createSubscription(
                String.valueOf(owner.Id),
                false,
                false,
                true,
                false,
                false,
                null
            );
        }

        System.runAs(owner) {
            List<RAA_SubscriptionDTO> mine = RAA_RecordAccessExplainerController.listMySubscriptions();
            System.assertEquals(1, mine.size());
        }

        Test.startTest();
        System.runAs(otherReader) {
            try {
                RAA_RecordAccessExplainerController.setSubscriptionActive(String.valueOf(subscriptionId), false);
                System.assert(false, 'A subscription owned by another user should not be visible.');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('could not be found'));
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void getRiskInsightsRequiresPermissionAndReturnsOnlyOwnAnalyses() {
        RAA_PermissionChecker.testOverride = true;
        Account acct = new Account(Name = 'RAA Controller Risk Account');
        insert acct;

        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id analysisId = repo.createAnalysis(
            acct.Id,
            'Account',
            'RAA Controller Risk Account',
            UserInfo.getUserId(),
            false,
            false
        );
        repo.markCompleted(analysisId, false, null, null);

        Test.startTest();
        List<RAA_RiskInsightDTO> insights = RAA_RecordAccessExplainerController.getRiskInsights();
        Test.stopTest();

        System.assertEquals(1, insights.size());
        System.assertEquals(analysisId, insights[0].analysisId);
    }

    @IsTest
    static void scanOrgWideAccessRequiresPermissionAndDelegatesToTheService() {
        RAA_PermissionChecker.testOverride = true;

        Test.startTest();
        List<RAA_OrgWideAccessDTO> results = RAA_RecordAccessExplainerController.scanOrgWideAccess(
            new List<String>{ 'Account' }
        );
        Test.stopTest();

        Boolean foundAdminModifyAll = false;
        for (RAA_OrgWideAccessDTO dto : results) {
            if (dto.principalType == 'Profile' && dto.hasModifyAllRecords == true) {
                foundAdminModifyAll = true;
            }
        }
        System.assert(foundAdminModifyAll, 'Should delegate to RAA_OrgWideAccessService and return real results.');
    }

    @IsTest
    static void scanOrgWideAccessBlocksUnauthorizedUsers() {
        RAA_PermissionChecker.testOverride = false;

        try {
            RAA_RecordAccessExplainerController.scanOrgWideAccess(new List<String>{ 'Account' });
            System.assert(false, 'Expected an exception for a user without the run permission.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('permission'));
        }
    }

    @IsTest
    static void getPlainEnglishSummaryRequiresPermissionAndVisibility() {
        RAA_PermissionChecker.testOverride = true;
        Account acct = new Account(Name = 'RAA Controller Summary Account');
        insert acct;

        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id analysisId = repo.createAnalysis(
            acct.Id,
            'Account',
            'RAA Controller Summary Account',
            UserInfo.getUserId(),
            false,
            false
        );
        repo.markCompleted(analysisId, false, null, null);

        Test.startTest();
        String summaryText = RAA_RecordAccessExplainerController.getPlainEnglishSummary(String.valueOf(analysisId));
        Test.stopTest();

        System.assert(summaryText.contains('RAA Controller Summary Account'), summaryText);
    }
}
