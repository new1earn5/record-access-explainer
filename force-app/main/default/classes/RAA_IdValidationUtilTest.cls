@IsTest
private class RAA_IdValidationUtilTest {

    @IsTest
    static void normalizesValid15And18CharIds() {
        Id userId = UserInfo.getUserId();
        String id15 = String.valueOf(userId).left(15);

        Test.startTest();
        Id normalizedFrom15 = RAA_IdValidationUtil.normalizeRecordId(id15);
        Id normalizedFrom18 = RAA_IdValidationUtil.normalizeRecordId(String.valueOf(userId));
        Test.stopTest();

        System.assertEquals(userId, normalizedFrom15, 'A 15-character ID should normalize to the same record.');
        System.assertEquals(userId, normalizedFrom18, 'An 18-character ID should normalize unchanged.');
    }

    @IsTest
    static void rejectsBlankId() {
        try {
            RAA_IdValidationUtil.normalizeRecordId('   ');
            System.assert(false, 'Expected an exception for a blank ID.');
        } catch (RAA_AppException e) {
            System.assert(e.getMessage().contains('enter a record ID'), 'Message should explain a record ID is required.');
        }
    }

    @IsTest
    static void rejectsMalformedId() {
        try {
            RAA_IdValidationUtil.normalizeRecordId('not-a-valid-id!!');
            System.assert(false, 'Expected an exception for a malformed ID.');
        } catch (RAA_AppException e) {
            System.assert(e.getMessage().contains('not a valid Salesforce record ID'), 'Message should explain the format is invalid.');
        }
    }

    @IsTest
    static void rejectsWrongLengthId() {
        try {
            RAA_IdValidationUtil.normalizeRecordId('001ABC');
            System.assert(false, 'Expected an exception for a too-short ID.');
        } catch (RAA_AppException e) {
            System.assert(e.getMessage().contains('15 or 18'), 'Message should explain the required length.');
        }
    }

    @IsTest
    static void normalizeAnalysisIdRequiresAnalysisObject() {
        Id userId = UserInfo.getUserId();
        try {
            RAA_IdValidationUtil.normalizeAnalysisId(String.valueOf(userId));
            System.assert(false, 'Expected an exception when the ID is not an RAA_Analysis__c ID.');
        } catch (RAA_AppException e) {
            System.assert(e.getMessage().contains('RAA Analysis'), 'Message should explain the object type mismatch.');
        }
    }

    @IsTest
    static void rejectsWellFormedIdWithUnregisteredPrefix() {
        // Passes the length/alphanumeric regex but has no registered 3-character key prefix,
        // so Id.valueOf itself throws System.StringException, which must be wrapped.
        try {
            RAA_IdValidationUtil.normalizeRecordId('000AAAAAAAAAAAAAAA');
            System.assert(false, 'Expected an exception for an unregistered ID prefix.');
        } catch (RAA_AppException e) {
            System.assert(e.getMessage().contains('not a valid Salesforce record ID'));
        }
    }

    @IsTest
    static void normalizeAnalysisIdRejectsBlank() {
        try {
            RAA_IdValidationUtil.normalizeAnalysisId('   ');
            System.assert(false, 'Expected an exception for a blank analysis ID.');
        } catch (RAA_AppException e) {
            System.assert(e.getMessage().contains('analysis ID is required'));
        }
    }

    @IsTest
    static void normalizeAnalysisIdAcceptsAnalysisObject() {
        RAA_Analysis__c analysis = RAA_TestDataFactory.createAnalysis(UserInfo.getUserId(), 'User');
        Id normalized = RAA_IdValidationUtil.normalizeAnalysisId(String.valueOf(analysis.Id));
        System.assertEquals(analysis.Id, normalized, 'A valid RAA_Analysis__c ID should normalize successfully.');
    }
}
