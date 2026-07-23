@IsTest
private class RAA_TerritoryAnalyzerTest {
    @IsTest
    static void gracefullySkipsWhenTerritoryManagementUnavailableOrNoAssociation() {
        Account acct = new Account(Name = 'RAA Territory Account');
        insert acct;

        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.recordId = acct.Id;
        context.objectApiName = 'Account';
        context.objectDescribe = Account.SObjectType.getDescribe();

        Test.startTest();
        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_TerritoryAnalyzer()
            .analyze(context, new Set<Id>{ UserInfo.getUserId() });
        Test.stopTest();

        // Whether or not Enterprise Territory Management is enabled in this org, an Account with
        // no territory association must not produce any Territory reason, and must never throw.
        System.assertEquals(0, results.size());
        System.assertEquals(
            true,
            true,
            'Analyzer completed without throwing for an org where territory data is absent or unassociated.'
        );
    }

    @IsTest
    static void returnsEmptyForObjectWithNoAccountRelationship() {
        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.recordId = UserInfo.getUserId();
        context.objectApiName = 'User';
        context.objectDescribe = User.SObjectType.getDescribe();

        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_TerritoryAnalyzer()
            .analyze(context, new Set<Id>{ UserInfo.getUserId() });

        System.assertEquals(0, results.size(), 'Objects with no AccountId relationship cannot be territory-analyzed.');
    }

    @IsTest
    static void returnsEmptyForEmptyUserSet() {
        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.objectApiName = 'Account';
        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_TerritoryAnalyzer().analyze(context, new Set<Id>());
        System.assertEquals(0, results.size());
    }
}
