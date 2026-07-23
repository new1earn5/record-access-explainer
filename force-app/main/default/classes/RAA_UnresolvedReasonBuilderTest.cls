@IsTest
private class RAA_UnresolvedReasonBuilderTest {
    @IsTest
    static void buildsLowConfidenceUnresolvedReason() {
        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.shareObjectApiName = 'AccountShare';
        context.shareRows = new List<SObject>();

        Test.startTest();
        RAA_AccessReasonDTO reason = new RAA_UnresolvedReasonBuilder()
            .build(context, new List<String>{ 'Ownership', 'Permissions' });
        Test.stopTest();

        System.assertEquals('Unresolved', reason.category);
        System.assertEquals('Low', reason.confidence);
        System.assertEquals('Salesforce-computed access - exact source not exposed', reason.sourceName);
        System.assert(reason.evidence.contains('Ownership'), 'Evidence should list attempted analyzers.');
        System.assert(reason.evidence.contains('Permissions'), 'Evidence should list attempted analyzers.');
    }
}
