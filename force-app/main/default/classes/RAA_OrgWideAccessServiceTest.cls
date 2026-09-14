@IsTest
private class RAA_OrgWideAccessServiceTest {
    // Uses the real running test user's own System Administrator profile rather than fabricated
    // ObjectPermissions rows - that object isn't practically insertable via simple test DML, and
    // System Administrator genuinely carries Modify All Records on standard objects by default,
    // so this is real org state, not an assumption.
    @IsTest
    static void findsAProfileWithModifyAllRecordsOnAccount() {
        Test.startTest();
        List<RAA_OrgWideAccessDTO> results = new RAA_OrgWideAccessService()
            .scanObjectPermissions(new List<String>{ 'Account' });
        Test.stopTest();

        Boolean foundAdminModifyAll = false;
        for (RAA_OrgWideAccessDTO dto : results) {
            System.assertEquals('Account', dto.objectApiName);
            System.assert(dto.activeUserCount > 0, 'Every returned row must have at least one active user.');
            if (dto.principalType == 'Profile' && dto.hasModifyAllRecords == true) {
                foundAdminModifyAll = true;
            }
        }
        System.assert(
            foundAdminModifyAll,
            'The running test user\'s own System Administrator profile should appear with Modify All Records on Account.'
        );
    }

    @IsTest
    static void throwsForABlankObjectList() {
        try {
            new RAA_OrgWideAccessService().scanObjectPermissions(new List<String>());
            System.assert(false, 'Expected an exception for an empty object list.');
        } catch (RAA_AppException e) {
            System.assert(e.getMessage().contains('at least one'));
        }
    }

    @IsTest
    static void throwsForNullObjectList() {
        try {
            new RAA_OrgWideAccessService().scanObjectPermissions(null);
            System.assert(false, 'Expected an exception for a null object list.');
        } catch (RAA_AppException e) {
            System.assert(e.getMessage().contains('at least one'));
        }
    }

    @IsTest
    static void throwsForAnUnrecognizedObjectApiName() {
        try {
            new RAA_OrgWideAccessService().scanObjectPermissions(new List<String>{ 'NotARealObject__x' });
            System.assert(false, 'Expected an exception for an unrecognized object API name.');
        } catch (RAA_AppException e) {
            System.assert(e.getMessage().contains('not a recognized object'));
        }
    }

    @IsTest
    static void throwsWhenTooManyObjectsAreRequested() {
        List<String> tooMany = new List<String>();
        for (Integer i = 0; i < RAA_OrgWideAccessService.MAX_OBJECTS_PER_SCAN + 1; i++) {
            tooMany.add('Account');
        }
        // Account would dedupe to one anyway, so use a mix of real standard objects to force a
        // genuinely distinct count past the limit.
        tooMany = new List<String>{
            'Account',
            'Contact',
            'Lead',
            'Opportunity',
            'Case',
            'Task',
            'Event',
            'Campaign',
            'Contract',
            'Order',
            'Asset'
        };

        try {
            new RAA_OrgWideAccessService().scanObjectPermissions(tooMany);
            System.assert(
                false,
                'Expected an exception for more than ' + RAA_OrgWideAccessService.MAX_OBJECTS_PER_SCAN + ' objects.'
            );
        } catch (RAA_AppException e) {
            System.assert(e.getMessage().contains('at most'));
        }
    }

    @IsTest
    static void dedupesCaseInsensitiveDuplicateObjectNames() {
        Test.startTest();
        List<RAA_OrgWideAccessDTO> results = new RAA_OrgWideAccessService()
            .scanObjectPermissions(new List<String>{ 'Account', 'account', ' ACCOUNT ' });
        Test.stopTest();

        Set<String> seenPrincipalObjectPairs = new Set<String>();
        for (RAA_OrgWideAccessDTO dto : results) {
            String key = dto.principalType + ':' + dto.principalName + ':' + dto.objectApiName;
            System.assert(
                seenPrincipalObjectPairs.add(key),
                'The same principal/object combination should not appear twice from duplicate input.'
            );
        }
    }
}
