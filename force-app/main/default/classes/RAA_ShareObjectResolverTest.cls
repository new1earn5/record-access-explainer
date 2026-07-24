// Test fixture setup only - describe performance doesn't matter here.
@SuppressWarnings('PMD.EagerlyLoadedDescribeSObjectResult')
@IsTest
private class RAA_ShareObjectResolverTest {
    @IsTest
    static void resolvesStandardAccountShareWithAccountLevelPrimaryField() {
        Schema.DescribeSObjectResult accountDescribe = Account.SObjectType.getDescribe();

        Test.startTest();
        RAA_ShareObjectResolver.ShareObjectInfo info = new RAA_ShareObjectResolver().resolve(accountDescribe);
        Test.stopTest();

        System.assertNotEquals(null, info, 'AccountShare should be resolved.');
        System.assertEquals('AccountShare', info.shareObjectApiName);
        System.assertEquals('AccountId', info.parentField);
        System.assertEquals(
            'AccountAccessLevel',
            info.accessLevelField,
            'The Account-level access field should be preferred over child access-level fields.'
        );
        System.assertEquals('UserOrGroupId', info.userOrGroupField);
        System.assertEquals('RowCause', info.rowCauseField);
        System.assert(
            !info.secondaryAccessLevelFields.isEmpty(),
            'AccountShare exposes additional child access-level fields as secondary evidence.'
        );
    }

    @IsTest
    static void resolvesCustomObjectShareWithGenericAccessLevelField() {
        Schema.DescribeSObjectResult analysisDescribe = RAA_Analysis__c.SObjectType.getDescribe();

        Test.startTest();
        RAA_ShareObjectResolver.ShareObjectInfo info = new RAA_ShareObjectResolver().resolve(analysisDescribe);
        Test.stopTest();

        System.assertNotEquals(
            null,
            info,
            'RAA_Analysis__Share should be resolved because RAA_Analysis__c is Private.'
        );
        System.assertEquals('RAA_Analysis__Share', info.shareObjectApiName);
        System.assertEquals('ParentId', info.parentField);
        System.assertEquals('AccessLevel', info.accessLevelField);
    }

    @IsTest
    static void returnsNullWhenNoShareObjectExists() {
        // RAA_Access_Result__c is Controlled By Parent and has no generated Share object.
        Schema.DescribeSObjectResult resultDescribe = RAA_Access_Result__c.SObjectType.getDescribe();

        RAA_ShareObjectResolver.ShareObjectInfo info = new RAA_ShareObjectResolver().resolve(resultDescribe);

        System.assertEquals(null, info, 'Controlled-by-parent objects have no share table.');
    }
}
