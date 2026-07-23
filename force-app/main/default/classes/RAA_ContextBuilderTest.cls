@IsTest
private class RAA_ContextBuilderTest {
    @IsTest
    static void buildsTopLevelContextWithOwnerAndShareInfo() {
        Account acct = new Account(Name = 'RAA Context Builder Account');
        insert acct;

        Test.startTest();
        RAA_AnalysisContext context = new RAA_ContextBuilder().buildTopLevelContext(acct.Id, new RAA_SettingsService());
        Test.stopTest();

        System.assertEquals('Account', context.objectApiName);
        System.assertEquals(UserInfo.getUserId(), context.ownerId);
        System.assertEquals('AccountShare', context.shareObjectApiName);
        System.assertEquals(6, context.maxGroupDepth);
        System.assertEquals(5, context.remainingParentDepth);
    }

    @IsTest
    static void addsWarningWhenNoShareObjectExists() {
        RAA_Analysis__c analysis = RAA_TestDataFactory.createAnalysis(UserInfo.getUserId(), 'User');
        RAA_Access_Result__c resultRow = new RAA_Access_Result__c(
            RAA_Analysis__c = analysis.Id,
            RAA_User__c = UserInfo.getUserId(),
            RAA_Unique_Key__c = analysis.Id + '-' + UserInfo.getUserId()
        );
        insert resultRow;

        RAA_AnalysisContext context = new RAA_ContextBuilder()
            .buildTopLevelContext(resultRow.Id, new RAA_SettingsService());

        System.assertEquals(null, context.shareObjectApiName, 'Controlled-by-parent objects have no share table.');
        System.assertEquals('RAA_Analysis__c', context.controllingParentFieldApiName);
    }
}
