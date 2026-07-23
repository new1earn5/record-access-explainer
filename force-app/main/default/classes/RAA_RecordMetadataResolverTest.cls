@IsTest
private class RAA_RecordMetadataResolverTest {

    @IsTest
    static void resolvesStandardObjectRecord() {
        Account acct = new Account(Name = 'RAA Test Account');
        insert acct;

        Test.startTest();
        RAA_RecordMetadataResolver.ResolvedRecord resolved = new RAA_RecordMetadataResolver().resolve(acct.Id);
        Test.stopTest();

        System.assertEquals('Account', resolved.objectApiName, 'Should resolve to the Account object.');
        System.assertEquals('RAA Test Account', resolved.displayName, 'Should resolve the Name field as the display name.');
        System.assertNotEquals(null, resolved.objectDescribe, 'Describe result should be populated.');
    }

    @IsTest
    static void supportsUserRecordAccessForStandardObject() {
        Account acct = new Account(Name = 'RAA URA Account');
        insert acct;

        Test.startTest();
        Boolean supported = new RAA_RecordMetadataResolver().supportsUserRecordAccess(acct.Id);
        Test.stopTest();

        System.assertEquals(true, supported, 'Account should support UserRecordAccess.');
    }

    @IsTest
    static void resolvesDisplayNameForObjectWithoutALiteralNameField() {
        // Case has no field literally called "Name" - its name field is CaseNumber, discovered
        // via DescribeFieldResult.isNameField() rather than a hardcoded field name.
        Case c = new Case(Subject = 'RAA Test Case');
        insert c;

        RAA_RecordMetadataResolver.ResolvedRecord resolved = new RAA_RecordMetadataResolver().resolve(c.Id);

        System.assertEquals('Case', resolved.objectApiName);
        System.assertNotEquals(null, resolved.displayName);
    }

    @IsTest
    static void rejectsIdForRecordThatDoesNotExist() {
        Account acct = new Account(Name = 'RAA Temp Account');
        insert acct;
        Id deletedId = acct.Id;
        delete acct;

        try {
            new RAA_RecordMetadataResolver().resolve(deletedId);
            System.assert(false, 'Expected an exception for a record that no longer exists.');
        } catch (RAA_AppException e) {
            System.assert(e.getMessage().contains('No Account record was found'), 'Message should explain no record was found.');
        }
    }
}
