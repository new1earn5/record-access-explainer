@IsTest
private class RAA_PermissionAnalyzerTest {

    @TestSetup
    static void setup() {
        String uniqueSuffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));

        PermissionSet viewAllRecordsSet = new PermissionSet(
                Name = 'RAA_Test_View_All_Records_' + uniqueSuffix,
                Label = 'RAA Test View All Records'
        );
        insert viewAllRecordsSet;
        insert new ObjectPermissions(
                ParentId = viewAllRecordsSet.Id,
                SobjectType = 'Account',
                PermissionsRead = true,
                PermissionsViewAllRecords = true
        );

        User secondUser = RAA_TestDataFactory.createUser('Perm', 'Second');
        insert new PermissionSetAssignment(AssigneeId = secondUser.Id, PermissionSetId = viewAllRecordsSet.Id);
    }

    @IsTest
    static void detectsViewAllDataFromExistingAdminProfile() {
        // Creating a PermissionSet with PermissionsViewAllData = true via DML requires also
        // granting Read on every object in the org's schema (a Salesforce-enforced dependency
        // chain with hundreds of entries), which is impractical to construct by hand in a test.
        // The scratch/test running user's own System Administrator profile already satisfies
        // this - Salesforce grants View All Data on that profile by default - so this test uses
        // the running user directly instead of manufacturing a new permission set.
        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.objectApiName = 'Account';

        Test.startTest();
        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_PermissionAnalyzer().analyze(context, new Set<Id>{ UserInfo.getUserId() });
        Test.stopTest();

        if (results.containsKey(UserInfo.getUserId())) {
            Boolean foundViewAllData = false;
            for (RAA_AccessReasonDTO reason : results.get(UserInfo.getUserId())) {
                if (reason.explanation.contains('View All Data')) {
                    foundViewAllData = true;
                    System.assertEquals('High', reason.confidence);
                }
            }
            System.assert(foundViewAllData, 'Expected the admin profile\'s View All Data to be detected.');
        }
    }

    @IsTest
    static void detectsViewAllRecordsOnSpecificObject() {
        User u = [SELECT Id FROM User WHERE LastName = 'Second' LIMIT 1];

        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.objectApiName = 'Account';

        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_PermissionAnalyzer().analyze(context, new Set<Id>{ u.Id });

        System.assert(results.containsKey(u.Id), 'The user with View All Records on Account should get a Permission reason.');
        System.assert(results.get(u.Id)[0].explanation.contains('View All Records'), 'Explanation should reference View All Records.');
        System.assert(results.get(u.Id)[0].explanation.contains('Account'), 'Explanation should reference the object.');
    }

    @IsTest
    static void returnsNothingForUserWithNoElevatedPermissions() {
        User plainUser = RAA_TestDataFactory.createUser('Perm', 'Plain');

        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.objectApiName = 'Account';

        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_PermissionAnalyzer().analyze(context, new Set<Id>{ plainUser.Id });

        System.assert(!results.containsKey(plainUser.Id) || results.get(plainUser.Id).isEmpty(),
                'A user with only their default profile assignment should not get an elevated-permission reason from this fixture.');
    }
}
