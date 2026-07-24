@IsTest
private class RAA_PlainEnglishSummaryServiceTest {
    @IsTest
    static void reportsNoAccessWhenThereAreNoResults() {
        RAA_AnalysisSummaryDTO summary = new RAA_AnalysisSummaryDTO();
        summary.recordDisplayName = 'Acme Corp';
        summary.objectApiName = 'Account';

        String text = new RAA_PlainEnglishSummaryService().buildSummary(summary, new List<RAA_AccessResultDTO>());

        System.assert(text.contains('No users currently have access to Acme Corp (Account)'));
    }

    @IsTest
    static void summarizesCountsAccessLevelsReasonsAndCaveats() {
        RAA_AnalysisSummaryDTO summary = new RAA_AnalysisSummaryDTO();
        summary.recordDisplayName = 'Acme Corp';
        summary.objectApiName = 'Account';
        summary.potentiallyIncomplete = true;

        RAA_AccessResultDTO owner = new RAA_AccessResultDTO();
        owner.userFullName = 'Owner User';
        owner.maxAccessLevel = 'Full Access';
        owner.overallConfidence = 'High';
        owner.hasUnresolvedReason = false;
        owner.reasons = new List<RAA_AccessReasonDTO>{ RAA_TestDataFactory.buildReason('Ownership', 'High') };

        RAA_AccessResultDTO roleOne = new RAA_AccessResultDTO();
        roleOne.userFullName = 'Role User One';
        roleOne.maxAccessLevel = 'Edit';
        roleOne.overallConfidence = 'High';
        roleOne.hasUnresolvedReason = false;
        roleOne.reasons = new List<RAA_AccessReasonDTO>{ RAA_TestDataFactory.buildReason('Role Hierarchy', 'High') };

        RAA_AccessResultDTO roleTwo = new RAA_AccessResultDTO();
        roleTwo.userFullName = 'Role User Two';
        roleTwo.maxAccessLevel = 'Edit';
        roleTwo.overallConfidence = 'Low';
        roleTwo.hasUnresolvedReason = false;
        roleTwo.reasons = new List<RAA_AccessReasonDTO>{ RAA_TestDataFactory.buildReason('Role Hierarchy', 'Low') };

        RAA_AccessResultDTO unresolved = new RAA_AccessResultDTO();
        unresolved.userFullName = 'Unresolved User';
        unresolved.maxAccessLevel = 'Read';
        unresolved.overallConfidence = 'Low';
        unresolved.hasUnresolvedReason = true;
        unresolved.reasons = new List<RAA_AccessReasonDTO>{ RAA_TestDataFactory.buildReason('Unresolved', 'Low') };

        String text = new RAA_PlainEnglishSummaryService()
            .buildSummary(summary, new List<RAA_AccessResultDTO>{ owner, roleOne, roleTwo, unresolved });

        System.assert(text.contains('4 users have access to Acme Corp (Account)'), text);
        System.assert(text.contains('By access level'), text);
        System.assert(text.contains('2 users have Edit access'), text);
        System.assert(text.contains('1 user has Full Access access'), text);
        System.assert(text.contains('Access is primarily explained by Role Hierarchy (2 users)'), text);
        System.assert(text.contains('For 1 user, access could not be fully attributed'), text);
        System.assert(text.contains('Low or Mixed confidence'), text);
        System.assert(text.contains('potentially incomplete'), text);
    }

    @IsTest
    static void usesSingularPhrasingForOneUser() {
        RAA_AnalysisSummaryDTO summary = new RAA_AnalysisSummaryDTO();
        summary.recordDisplayName = 'Solo Account';
        summary.objectApiName = 'Account';

        RAA_AccessResultDTO owner = new RAA_AccessResultDTO();
        owner.userFullName = 'Only User';
        owner.maxAccessLevel = 'Full Access';
        owner.overallConfidence = 'High';
        owner.hasUnresolvedReason = false;
        owner.reasons = new List<RAA_AccessReasonDTO>{ RAA_TestDataFactory.buildReason('Ownership', 'High') };

        String text = new RAA_PlainEnglishSummaryService()
            .buildSummary(summary, new List<RAA_AccessResultDTO>{ owner });

        System.assert(text.contains('1 user has access to Solo Account (Account)'), text);
        System.assert(!text.contains('For'), 'No unresolved/low-confidence caveats should appear.');
    }
}
