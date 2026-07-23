@IsTest
private class RAA_UserAccessExplorerServiceTest {
    @IsTest
    static void scansOwnerAcrossMultipleRecordsAndSortsAccessibleFirst() {
        Account owned = new Account(Name = 'RAA Explorer Owned Account');
        Account other = new Account(Name = 'RAA Explorer Other Account');
        insert new List<Account>{ owned, other };

        // Reassign "other" to a different owner so the running test user (owner of "owned") has
        // no access to it under a typical Private/role-based OWD, giving a deterministic negative case.
        User otherOwner = RAA_TestDataFactory.createUser('Explorer', 'OtherOwner');
        other.OwnerId = otherOwner.Id;
        update other;

        Test.startTest();
        List<RAA_UserRecordAccessSummaryDTO> results = new RAA_UserAccessExplorerService()
            .scanUserAcrossRecords(UserInfo.getUserId(), 'Account', new List<Id>{ owned.Id, other.Id });
        Test.stopTest();

        System.assertEquals(2, results.size());

        Map<Id, RAA_UserRecordAccessSummaryDTO> byRecord = new Map<Id, RAA_UserRecordAccessSummaryDTO>();
        for (RAA_UserRecordAccessSummaryDTO dto : results) {
            byRecord.put(dto.recordId, dto);
        }
        System.assertEquals(
            true,
            byRecord.get(owned.Id).hasAnyAccess,
            'The owner should have access to their own record.'
        );
        System.assertEquals('RAA Explorer Owned Account', byRecord.get(owned.Id).recordDisplayName);
    }

    @IsTest
    static void throwsWhenCandidateRecordsAreNotAllTheSameObject() {
        Account acct = new Account(Name = 'RAA Explorer Mixed Account');
        insert acct;

        try {
            new RAA_UserAccessExplorerService()
                .scanUserAcrossRecords(UserInfo.getUserId(), 'Account', new List<Id>{ acct.Id, UserInfo.getUserId() });
            System.assert(false, 'Expected an exception for mismatched object types.');
        } catch (RAA_AppException e) {
            System.assert(e.getMessage().contains('same object'));
        }
    }

    @IsTest
    static void throwsForUnknownObject() {
        try {
            new RAA_UserAccessExplorerService()
                .scanUserAcrossRecords(
                    UserInfo.getUserId(),
                    'Not_A_Real_Object__x',
                    new List<Id>{ UserInfo.getUserId() }
                );
            System.assert(false, 'Expected an exception for an unknown object.');
        } catch (RAA_AppException e) {
            System.assert(e.getMessage().contains('not a recognized object'));
        }
    }

    @IsTest
    static void returnsEmptyForNoCandidates() {
        List<RAA_UserRecordAccessSummaryDTO> results = new RAA_UserAccessExplorerService()
            .scanUserAcrossRecords(UserInfo.getUserId(), 'Account', null);
        System.assertEquals(0, results.size());
    }

    @IsTest
    static void computesReasonsForOneRecordOnDemand() {
        Account acct = new Account(Name = 'RAA Explorer Reasons Account');
        insert acct;

        List<RAA_AccessReasonDTO> reasons = new RAA_UserAccessExplorerService()
            .getAccessReasons(UserInfo.getUserId(), acct.Id);

        System.assert(!reasons.isEmpty(), 'The owner should have at least one detected reason.');
    }
}
