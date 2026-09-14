@IsTest
private class RAA_ScanRestResourceTest {
    private static RestResponse setupRequest(String method, String uri, String bodyJson) {
        RestRequest request = new RestRequest();
        request.requestUri = uri;
        request.httpMethod = method;
        if (bodyJson != null) {
            request.requestBody = Blob.valueOf(bodyJson);
        }
        RestContext.request = request;
        RestResponse response = new RestResponse();
        RestContext.response = response;
        return response;
    }

    @IsTest
    static void postStartsAScanAndReturns201WithAnalysisId() {
        Account acct = new Account(Name = 'RAA Rest Account');
        insert acct;

        RAA_PermissionChecker.testOverride = true;
        RestResponse response = setupRequest(
            'POST',
            '/services/apexrest/RecordAccessScan/',
            JSON.serialize(new Map<String, Object>{ 'recordId' => acct.Id })
        );

        Test.startTest();
        RAA_ScanRestResource.startScan();
        Test.stopTest();

        System.assertEquals(201, response.statusCode);
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(response.responseBody.toString());
        System.assertNotEquals(null, body.get('analysisId'));
        System.assertEquals(null, body.get('errorMessage'));
    }

    @IsTest
    static void postReturns403WhenUnauthorized() {
        RAA_PermissionChecker.testOverride = false;
        RestResponse response = setupRequest(
            'POST',
            '/services/apexrest/RecordAccessScan/',
            JSON.serialize(new Map<String, Object>{ 'recordId' => UserInfo.getUserId() })
        );

        Test.startTest();
        RAA_ScanRestResource.startScan();
        Test.stopTest();

        System.assertEquals(403, response.statusCode);
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(response.responseBody.toString());
        System.assert(((String) body.get('errorMessage')).contains('permission'));
    }

    @IsTest
    static void postReturns400ForAnInvalidRecordId() {
        RAA_PermissionChecker.testOverride = true;
        RestResponse response = setupRequest(
            'POST',
            '/services/apexrest/RecordAccessScan/',
            JSON.serialize(new Map<String, Object>{ 'recordId' => 'not-a-real-id' })
        );

        Test.startTest();
        RAA_ScanRestResource.startScan();
        Test.stopTest();

        System.assertEquals(400, response.statusCode);
    }

    @IsTest
    static void getReturnsCurrentStatusForAVisibleAnalysis() {
        Account acct = new Account(Name = 'RAA Rest Status Account');
        insert acct;
        RAA_AnalysisRepository repo = new RAA_AnalysisRepository();
        Id analysisId = repo.createAnalysis(
            acct.Id,
            'Account',
            'RAA Rest Status Account',
            UserInfo.getUserId(),
            false,
            false
        );
        repo.markCompleted(analysisId, false, null, null);

        RAA_PermissionChecker.testOverride = true;
        RestResponse response = setupRequest('GET', '/services/apexrest/RecordAccessScan/' + analysisId, null);

        Test.startTest();
        RAA_ScanRestResource.getScanStatus();
        Test.stopTest();

        System.assertEquals(200, response.statusCode);
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(response.responseBody.toString());
        System.assertEquals(String.valueOf(analysisId), body.get('analysisId'));
        System.assertEquals('Completed', body.get('status'));
    }

    @IsTest
    static void getReturns404ForAnUnknownAnalysisId() {
        RAA_Analysis__c analysis = RAA_TestDataFactory.createAnalysis(UserInfo.getUserId(), 'User');
        Id analysisId = analysis.Id;
        delete analysis;

        RAA_PermissionChecker.testOverride = true;
        RestResponse response = setupRequest('GET', '/services/apexrest/RecordAccessScan/' + analysisId, null);

        Test.startTest();
        RAA_ScanRestResource.getScanStatus();
        Test.stopTest();

        System.assertEquals(404, response.statusCode);
    }

    @IsTest
    static void getReturns403WhenUnauthorized() {
        RAA_PermissionChecker.testOverride = false;
        RestResponse response = setupRequest(
            'GET',
            '/services/apexrest/RecordAccessScan/' + UserInfo.getUserId(),
            null
        );

        Test.startTest();
        RAA_ScanRestResource.getScanStatus();
        Test.stopTest();

        System.assertEquals(403, response.statusCode);
    }
}
