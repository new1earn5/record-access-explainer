@IsTest
private class RAA_UserRecordAccessProviderTest {

    @IsTest
    static void ownerHasEffectiveAccessAccordingToUserRecordAccess() {
        Account acct = new Account(Name = 'RAA URA Provider Account');
        insert acct;

        Test.startTest();
        Map<Id, RAA_EffectiveAccessResult> results = new RAA_UserRecordAccessProvider()
                .getEffectiveAccess(acct.Id, new Set<Id>{ UserInfo.getUserId() });
        Test.stopTest();

        System.assert(results.containsKey(UserInfo.getUserId()), 'The owner should have a UserRecordAccess row.');
        System.assertEquals(true, results.get(UserInfo.getUserId()).hasReadAccess);
        System.assertEquals(true, results.get(UserInfo.getUserId()).hasAnyAccess());
    }

    @IsTest
    static void returnsEmptyMapForEmptyOrNullInput() {
        Account acct = new Account(Name = 'RAA URA Provider Account 2');
        insert acct;

        RAA_UserRecordAccessProvider provider = new RAA_UserRecordAccessProvider();
        System.assertEquals(0, provider.getEffectiveAccess(acct.Id, new Set<Id>()).size());
        System.assertEquals(0, provider.getEffectiveAccess(null, new Set<Id>{ UserInfo.getUserId() }).size());
    }
}
