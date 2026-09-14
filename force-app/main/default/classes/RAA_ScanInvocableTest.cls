@IsTest
private class RAA_ScanInvocableTest {
    @IsTest
    static void startsAScanAndReturnsAnalysisIdAndStatus() {
        Account acct = new Account(Name = 'RAA Invocable Account');
        insert acct;

        RAA_PermissionChecker.testOverride = true;

        RAA_ScanInvocable.Request request = new RAA_ScanInvocable.Request();
        request.recordId = acct.Id;
        request.includeExternalUsers = false;
        request.includeInactiveUsers = false;

        Test.startTest();
        List<RAA_ScanInvocable.Result> results = RAA_ScanInvocable.startScan(
            new List<RAA_ScanInvocable.Request>{ request }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        RAA_ScanInvocable.Result result = results[0];
        System.assertEquals(true, result.isSuccess);
        System.assertNotEquals(null, result.analysisId);
        System.assert(
            result.status == 'Queued' || result.status == 'Running' || result.status == 'Completed',
            'Expected a real in-flight or terminal status, got: ' + result.status
        );
        System.assertEquals(null, result.errorMessage);
    }

    @IsTest
    static void reportsFailureOnResultRatherThanThrowingWhenUnauthorized() {
        RAA_PermissionChecker.testOverride = false;

        RAA_ScanInvocable.Request request = new RAA_ScanInvocable.Request();
        request.recordId = UserInfo.getUserId();

        Test.startTest();
        List<RAA_ScanInvocable.Result> results = RAA_ScanInvocable.startScan(
            new List<RAA_ScanInvocable.Request>{ request }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        RAA_ScanInvocable.Result result = results[0];
        System.assertEquals(false, result.isSuccess);
        System.assert(result.errorMessage.contains('permission'));
        System.assertEquals(null, result.analysisId);
    }

    @IsTest
    static void reportsFailureOnResultForAnInvalidRecordId() {
        RAA_PermissionChecker.testOverride = true;

        RAA_ScanInvocable.Request request = new RAA_ScanInvocable.Request();
        request.recordId = 'not-a-real-id';

        Test.startTest();
        List<RAA_ScanInvocable.Result> results = RAA_ScanInvocable.startScan(
            new List<RAA_ScanInvocable.Request>{ request }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].isSuccess);
        System.assertNotEquals(null, results[0].errorMessage);
    }

    @IsTest
    static void processesMultipleRequestsIndependently() {
        Account acctOne = new Account(Name = 'RAA Invocable Bulk One');
        Account acctTwo = new Account(Name = 'RAA Invocable Bulk Two');
        insert new List<Account>{ acctOne, acctTwo };

        RAA_PermissionChecker.testOverride = true;

        RAA_ScanInvocable.Request requestOne = new RAA_ScanInvocable.Request();
        requestOne.recordId = acctOne.Id;
        RAA_ScanInvocable.Request requestTwo = new RAA_ScanInvocable.Request();
        requestTwo.recordId = acctTwo.Id;

        Test.startTest();
        List<RAA_ScanInvocable.Result> results = RAA_ScanInvocable.startScan(
            new List<RAA_ScanInvocable.Request>{ requestOne, requestTwo }
        );
        Test.stopTest();

        System.assertEquals(2, results.size());
        for (RAA_ScanInvocable.Result result : results) {
            System.assertEquals(true, result.isSuccess);
            System.assertNotEquals(null, result.analysisId);
        }
        System.assertNotEquals(
            results[0].analysisId,
            results[1].analysisId,
            'Each request should start its own independent analysis.'
        );
    }
}
