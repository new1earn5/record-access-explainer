@IsTest
private class RAA_FieldAccessServiceTest {

    @TestSetup
    static void setup() {
        User u = RAA_TestDataFactory.createUser('Field', 'Tester');
        String uniqueSuffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));

        PermissionSet ps = new PermissionSet(Name = 'RAA_Test_Field_Access_' + uniqueSuffix, Label = 'RAA Test Field Access');
        insert ps;
        insert new ObjectPermissions(ParentId = ps.Id, SobjectType = 'Account', PermissionsRead = true);
        insert new FieldPermissions(ParentId = ps.Id, SobjectType = 'Account', Field = 'Account.Website', PermissionsRead = true, PermissionsEdit = true);
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
    }

    @IsTest
    static void reportsGrantedFieldAndAlwaysAccessibleSystemField() {
        User u = [SELECT Id FROM User WHERE LastName = 'Tester' LIMIT 1];

        Test.startTest();
        List<RAA_FieldAccessDTO> results = new RAA_FieldAccessService().getFieldAccess(u.Id, 'Account');
        Test.stopTest();

        Map<String, RAA_FieldAccessDTO> byField = new Map<String, RAA_FieldAccessDTO>();
        for (RAA_FieldAccessDTO dto : results) {
            byField.put(dto.fieldApiName, dto);
        }

        System.assert(byField.containsKey('Website'));
        System.assertEquals(true, byField.get('Website').readable);
        System.assertEquals(true, byField.get('Website').editable);

        System.assert(byField.containsKey('Id'), 'Id should always be present.');
        System.assertEquals(true, byField.get('Id').readable, 'Non-permissionable fields like Id are always accessible.');
    }

    @IsTest
    static void throwsForUnknownObject() {
        try {
            new RAA_FieldAccessService().getFieldAccess(UserInfo.getUserId(), 'Not_A_Real_Object__x');
            System.assert(false, 'Expected an exception for an unknown object.');
        } catch (RAA_AppException e) {
            System.assert(e.getMessage().contains('not a recognized object'));
        }
    }

    @IsTest
    static void returnsAResultForEveryFieldOnTheObject() {
        User plainUser = RAA_TestDataFactory.createUser('Field', 'Plain');

        List<RAA_FieldAccessDTO> results = new RAA_FieldAccessService().getFieldAccess(plainUser.Id, 'Account');

        // Field-level access depends on the org's default profile FLS, which this test cannot
        // assume - it only asserts that every describe field produced a result, not the specific
        // readable/editable values for a profile-derived (not explicitly granted) field.
        System.assert(!results.isEmpty());
        Set<String> fieldNames = new Set<String>();
        for (RAA_FieldAccessDTO dto : results) {
            fieldNames.add(dto.fieldApiName);
        }
        System.assert(fieldNames.contains('Website'));
        System.assert(fieldNames.contains('Id'));
    }
}
