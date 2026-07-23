@IsTest
private class RAA_OrgWideDefaultAnalyzerTest {

    @IsTest
    static void emitsLowConfidenceDisclaimerWhenNotControlledByParent() {
        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.objectApiName = 'Account';
        context.objectDescribe = Account.SObjectType.getDescribe();
        context.controllingParentFieldApiName = null;

        Test.startTest();
        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_OrgWideDefaultAnalyzer().analyze(context, new Set<Id>{ UserInfo.getUserId() });
        Test.stopTest();

        System.assert(results.containsKey(UserInfo.getUserId()), 'A non-parent-controlled object should get the OWD disclaimer reason.');
        System.assertEquals('Organization-Wide Default', results.get(UserInfo.getUserId())[0].category);
        System.assertEquals('Low', results.get(UserInfo.getUserId())[0].confidence);
        System.assert(results.get(UserInfo.getUserId())[0].explanation.contains('could not be conclusively retrieved'));
    }

    @IsTest
    static void controlledByParentObjectYieldsNoReason() {
        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.objectApiName = 'RAA_Access_Result__c';
        context.objectDescribe = RAA_Access_Result__c.SObjectType.getDescribe();
        context.controllingParentFieldApiName = 'RAA_Analysis__c';

        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_OrgWideDefaultAnalyzer().analyze(context, new Set<Id>{ UserInfo.getUserId() });

        System.assertEquals(0, results.size(), 'Controlled-by-parent objects defer to RAA_ParentControlledAnalyzer.');
    }

    @IsTest
    static void returnsEmptyForEmptyUserSet() {
        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.objectDescribe = Account.SObjectType.getDescribe();
        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_OrgWideDefaultAnalyzer().analyze(context, new Set<Id>());
        System.assertEquals(0, results.size());
    }
}
