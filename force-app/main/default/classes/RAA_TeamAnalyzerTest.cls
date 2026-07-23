@IsTest
private class RAA_TeamAnalyzerTest {

    @TestSetup
    static void setup() {
        RAA_TestDataFactory.createUser('Team', 'Member');
    }

    @IsTest
    static void detectsAccountTeamMembershipWhenFeatureIsEnabled() {
        Account acct = new Account(Name = 'RAA Team Account');
        insert acct;
        User member = [SELECT Id FROM User WHERE LastName = 'Member' LIMIT 1];

        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.recordId = acct.Id;
        context.objectApiName = 'Account';

        Test.startTest();
        Boolean accountTeamsEnabled = true;
        try {
            // Built dynamically because AccountTeamMember does not exist as a compile-time type
            // in orgs where Account Teams has never been enabled.
            SObject teamMember = Schema.getGlobalDescribe().get('AccountTeamMember').newSObject();
            teamMember.put('AccountId', acct.Id);
            teamMember.put('UserId', member.Id);
            teamMember.put('TeamMemberRole', 'RAA Test Role');
            teamMember.put('AccountAccessLevel', 'Edit');
            insert teamMember;
        } catch (Exception e) {
            // Account Teams is an opt-in feature (Setup > Account Teams). If it is not enabled in
            // this org, there is nothing further to assert here.
            accountTeamsEnabled = false;
        }

        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_TeamAnalyzer().analyze(context, new Set<Id>{ member.Id });
        Test.stopTest();

        if (accountTeamsEnabled) {
            System.assert(results.containsKey(member.Id), 'The account team member should get a Team reason.');
            System.assertEquals('Team', results.get(member.Id)[0].category);
            System.assertEquals('High', results.get(member.Id)[0].confidence);
        } else {
            System.assertEquals(0, results.size());
        }
    }

    @IsTest
    static void returnsEmptyMapForUnrelatedObject() {
        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.recordId = UserInfo.getUserId();
        context.objectApiName = 'User';

        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_TeamAnalyzer().analyze(context, new Set<Id>{ UserInfo.getUserId() });

        System.assertEquals(0, results.size(), 'Team analysis only applies to Account, Opportunity, and Case.');
    }

    @IsTest
    static void returnsEmptyMapForEmptyUserSet() {
        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.objectApiName = 'Account';
        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_TeamAnalyzer().analyze(context, new Set<Id>());
        System.assertEquals(0, results.size());
    }
}
