@IsTest
private class RAA_PermissionSetLookupTest {
    @IsTest
    static void returnsEmptyForNullOrEmptyInput() {
        RAA_PermissionSetLookup lookup = new RAA_PermissionSetLookup();
        System.assertEquals(0, lookup.getAssignments(null).size());
        System.assertEquals(0, lookup.getAssignments(new Set<Id>()).size());
    }

    @IsTest
    static void returnsProfileOwnedAssignmentForARealUser() {
        Test.startTest();
        List<PermissionSetAssignment> assignments = new RAA_PermissionSetLookup()
            .getAssignments(new Set<Id>{ UserInfo.getUserId() });
        Test.stopTest();

        System.assert(!assignments.isEmpty(), 'Every user has at least their profile-owned permission set assignment.');
    }

    @IsTest
    static void permissionSetIdsExtractsUniqueIds() {
        List<PermissionSetAssignment> assignments = new RAA_PermissionSetLookup()
            .getAssignments(new Set<Id>{ UserInfo.getUserId() });
        Set<Id> ids = new RAA_PermissionSetLookup().permissionSetIds(assignments);
        System.assertEquals(assignments.size(), ids.size());
    }
}
