@IsTest
private class RAA_ParentControlledAnalyzerTest {
    @IsTest
    static void detectsAccessThroughControllingParentChain() {
        RAA_Analysis__c analysis = RAA_TestDataFactory.createAnalysis(UserInfo.getUserId(), 'Account');
        RAA_Access_Result__c resultRow = new RAA_Access_Result__c(
            RAA_Analysis__c = analysis.Id,
            RAA_User__c = UserInfo.getUserId(),
            RAA_Unique_Key__c = analysis.Id + '-' + UserInfo.getUserId()
        );
        insert resultRow;

        RAA_SettingsService settings = new RAA_SettingsService();
        RAA_AnalysisContext context = new RAA_ContextBuilder().buildTopLevelContext(resultRow.Id, settings);

        Test.startTest();
        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_ParentControlledAnalyzer()
            .analyze(context, new Set<Id>{ UserInfo.getUserId() });
        Test.stopTest();

        System.assert(
            results.containsKey(UserInfo.getUserId()),
            'The owner of the parent Analysis should get an inherited reason.'
        );
        Boolean foundParentPath = false;
        for (RAA_AccessReasonDTO reason : results.get(UserInfo.getUserId())) {
            if (
                reason.grantPath != null &&
                reason.grantPath.contains('Controlled by parent through RAA_Access_Result__c.RAA_Analysis__c')
            ) {
                foundParentPath = true;
            }
        }
        System.assert(foundParentPath, 'Grant path should record the controlled-by-parent chain.');
    }

    @IsTest
    static void returnsNothingWhenObjectIsNotControlledByParent() {
        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.objectDescribe = Account.SObjectType.getDescribe();

        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_ParentControlledAnalyzer()
            .analyze(context, new Set<Id>{ UserInfo.getUserId() });

        System.assertEquals(0, results.size(), 'Account is not Controlled By Parent, so nothing should be produced.');
    }

    @IsTest
    static void stopsAtMaxDepthWithoutError() {
        RAA_Analysis__c analysis = RAA_TestDataFactory.createAnalysis(UserInfo.getUserId(), 'Account');
        RAA_Access_Result__c resultRow = new RAA_Access_Result__c(
            RAA_Analysis__c = analysis.Id,
            RAA_User__c = UserInfo.getUserId(),
            RAA_Unique_Key__c = analysis.Id + '-' + UserInfo.getUserId()
        );
        insert resultRow;

        RAA_SettingsService settings = new RAA_SettingsService();
        RAA_AnalysisContext context = new RAA_ContextBuilder().buildTopLevelContext(resultRow.Id, settings);
        context.remainingParentDepth = 0;

        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_ParentControlledAnalyzer()
            .analyze(context, new Set<Id>{ UserInfo.getUserId() });

        System.assertEquals(0, results.size(), 'Depth exhaustion should stop recursion cleanly rather than throwing.');
        System.assert(!context.warnings.isEmpty(), 'A warning should be recorded when max depth is reached.');
    }

    @IsTest
    static void returnsNothingForEmptyUserSet() {
        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.controllingParentFieldApiName = 'RAA_Analysis__c';
        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_ParentControlledAnalyzer().analyze(context, new Set<Id>());
        System.assertEquals(0, results.size());
    }

    @IsTest
    static void detectsCycleAndStopsWithoutError() {
        RAA_Analysis__c analysis = RAA_TestDataFactory.createAnalysis(UserInfo.getUserId(), 'Account');
        RAA_Access_Result__c resultRow = new RAA_Access_Result__c(
            RAA_Analysis__c = analysis.Id,
            RAA_User__c = UserInfo.getUserId(),
            RAA_Unique_Key__c = analysis.Id + '-' + UserInfo.getUserId()
        );
        insert resultRow;

        RAA_SettingsService settings = new RAA_SettingsService();
        RAA_AnalysisContext context = new RAA_ContextBuilder().buildTopLevelContext(resultRow.Id, settings);
        context.visitedParentRecordIds.add(analysis.Id); // pretend this parent was already visited

        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_ParentControlledAnalyzer()
            .analyze(context, new Set<Id>{ UserInfo.getUserId() });

        System.assertEquals(0, results.size(), 'A detected cycle should stop recursion without throwing.');
        System.assert(!context.warnings.isEmpty(), 'A warning should record the detected cycle.');
    }

    @IsTest
    static void gracefullyHandlesParentRecordDeletedMidAnalysis() {
        RAA_Analysis__c analysis = RAA_TestDataFactory.createAnalysis(UserInfo.getUserId(), 'Account');
        RAA_Access_Result__c resultRow = new RAA_Access_Result__c(
            RAA_Analysis__c = analysis.Id,
            RAA_User__c = UserInfo.getUserId(),
            RAA_Unique_Key__c = analysis.Id + '-' + UserInfo.getUserId()
        );
        insert resultRow;

        RAA_SettingsService settings = new RAA_SettingsService();
        RAA_AnalysisContext context = new RAA_ContextBuilder().buildTopLevelContext(resultRow.Id, settings);

        delete analysis;

        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_ParentControlledAnalyzer()
            .analyze(context, new Set<Id>{ UserInfo.getUserId() });

        System.assertEquals(0, results.size(), 'A parent that vanished mid-analysis should not throw.');
        System.assert(!context.warnings.isEmpty(), 'A warning should explain the parent could not be analyzed.');
    }
}
