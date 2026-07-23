@IsTest
private class RAA_ShareRowAnalyzerTest {

    @TestSetup
    static void setup() {
        User u = RAA_TestDataFactory.createUser('Share', 'Target');
        Group sharedGroup = new Group(Name = 'RAA Share Group', Type = 'Regular');
        insert sharedGroup;
        insert new GroupMember(GroupId = sharedGroup.Id, UserOrGroupId = u.Id);
    }

    private static RAA_AnalysisContext buildContext(List<SObject> shareRows) {
        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.shareObjectApiName = 'AccountShare';
        context.shareParentField = 'AccountId';
        context.shareUserOrGroupField = 'UserOrGroupId';
        context.shareAccessLevelField = 'AccountAccessLevel';
        context.shareRowCauseField = 'RowCause';
        context.shareRows = shareRows;
        context.maxGroupDepth = 6;
        return context;
    }

    @IsTest
    static void detectsDirectManualUserShare() {
        User target = [SELECT Id FROM User WHERE LastName = 'Target' LIMIT 1];
        // Built in memory only - RowCause values other than Manual/custom Apex reasons cannot be
        // inserted for standard objects, and the analyzer only needs field values, not persistence.
        AccountShare shareRow = new AccountShare(UserOrGroupId = target.Id, AccountAccessLevel = 'Edit', RowCause = 'Manual');

        RAA_AnalysisContext context = buildContext(new List<SObject>{ shareRow });

        Test.startTest();
        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_ShareRowAnalyzer().analyze(context, new Set<Id>{ target.Id });
        Test.stopTest();

        System.assert(results.containsKey(target.Id), 'The directly shared user should get a Direct Share reason.');
        System.assertEquals('Direct Share', results.get(target.Id)[0].category);
        System.assertEquals('High', results.get(target.Id)[0].confidence);
        System.assertEquals(true, results.get(target.Id)[0].isDirect);
    }

    @IsTest
    static void detectsGroupShareThroughMembership() {
        Group sharedGroup = [SELECT Id FROM Group WHERE Name = 'RAA Share Group' LIMIT 1];
        User target = [SELECT Id FROM User WHERE LastName = 'Target' LIMIT 1];
        AccountShare shareRow = new AccountShare(UserOrGroupId = sharedGroup.Id, AccountAccessLevel = 'Read', RowCause = 'Manual');

        RAA_AnalysisContext context = buildContext(new List<SObject>{ shareRow });

        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_ShareRowAnalyzer().analyze(context, new Set<Id>{ target.Id });

        System.assert(results.containsKey(target.Id), 'A member of the shared group should get a Group Share reason.');
        System.assertEquals('Group Share', results.get(target.Id)[0].category);
        System.assert(results.get(target.Id)[0].grantPath.contains('RAA Share Group'), 'Grant path should include the group name.');
    }

    @IsTest
    static void detectsSharingRuleWithoutClaimingRuleName() {
        Group sharedGroup = [SELECT Id FROM Group WHERE Name = 'RAA Share Group' LIMIT 1];
        User target = [SELECT Id FROM User WHERE LastName = 'Target' LIMIT 1];
        AccountShare shareRow = new AccountShare(UserOrGroupId = sharedGroup.Id, AccountAccessLevel = 'Read', RowCause = 'Rule');

        RAA_AnalysisContext context = buildContext(new List<SObject>{ shareRow });

        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_ShareRowAnalyzer().analyze(context, new Set<Id>{ target.Id });

        System.assertEquals('Sharing Rule', results.get(target.Id)[0].category);
        System.assert(results.get(target.Id)[0].explanation.contains('exact rule name unavailable'),
                'Must not claim a specific rule name it cannot prove.');
    }

    @IsTest
    static void skipsTeamCausedShareRows() {
        User target = [SELECT Id FROM User WHERE LastName = 'Target' LIMIT 1];
        AccountShare shareRow = new AccountShare(UserOrGroupId = target.Id, AccountAccessLevel = 'Read', RowCause = 'Team');

        RAA_AnalysisContext context = buildContext(new List<SObject>{ shareRow });

        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_ShareRowAnalyzer().analyze(context, new Set<Id>{ target.Id });

        System.assert(!results.containsKey(target.Id), 'Team-caused rows are reported by RAA_TeamAnalyzer, not this analyzer.');
    }

    @IsTest
    static void returnsNothingWhenNoShareObjectAvailable() {
        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.shareObjectApiName = null;
        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_ShareRowAnalyzer().analyze(context, new Set<Id>{ UserInfo.getUserId() });
        System.assertEquals(0, results.size());
    }
}
