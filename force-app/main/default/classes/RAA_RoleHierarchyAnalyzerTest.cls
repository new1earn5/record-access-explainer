@IsTest
private class RAA_RoleHierarchyAnalyzerTest {
    @TestSetup
    static void setup() {
        String uniqueSuffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        UserRole parentRole = new UserRole(Name = 'RAA Parent Role', DeveloperName = 'RAA_Parent_Role_' + uniqueSuffix);
        insert parentRole;
        UserRole childRole = new UserRole(
            Name = 'RAA Child Role',
            ParentRoleId = parentRole.Id,
            DeveloperName = 'RAA_Child_Role_' + uniqueSuffix
        );
        insert childRole;

        User owner = RAA_TestDataFactory.createUser('Role', 'Owner');
        owner.UserRoleId = childRole.Id;
        update owner;

        User manager = RAA_TestDataFactory.createUser('Role', 'Manager');
        manager.UserRoleId = parentRole.Id;
        update manager;

        User peer = RAA_TestDataFactory.createUser('Role', 'Peer');
        peer.UserRoleId = childRole.Id;
        update peer;

        User roleless = RAA_TestDataFactory.createUser('Role', 'None');
        update roleless;
    }

    @IsTest
    static void detectsHighConfidenceForStandardObject() {
        User owner = [SELECT Id FROM User WHERE LastName = 'Owner' LIMIT 1];
        User manager = [SELECT Id FROM User WHERE LastName = 'Manager' LIMIT 1];

        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.ownerId = owner.Id;
        context.objectApiName = 'Account';

        Test.startTest();
        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_RoleHierarchyAnalyzer()
            .analyze(context, new Set<Id>{ manager.Id });
        Test.stopTest();

        System.assert(
            results.containsKey(manager.Id),
            'The manager above the owner\'s role should get a hierarchy reason.'
        );
        System.assertEquals(
            'High',
            results.get(manager.Id)[0].confidence,
            'Standard objects cannot disable grant-using-hierarchies.'
        );
    }

    @IsTest
    static void detectsMediumConfidenceForCustomObject() {
        User owner = [SELECT Id FROM User WHERE LastName = 'Owner' LIMIT 1];
        User manager = [SELECT Id FROM User WHERE LastName = 'Manager' LIMIT 1];

        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.ownerId = owner.Id;
        context.objectApiName = 'RAA_Analysis__c';

        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_RoleHierarchyAnalyzer()
            .analyze(context, new Set<Id>{ manager.Id });

        System.assertEquals(
            'Medium',
            results.get(manager.Id)[0].confidence,
            'Custom objects cannot confirm the hierarchy grant checkbox, so confidence is Medium.'
        );
    }

    @IsTest
    static void doesNotGrantAccessToPeerInSameRole() {
        User owner = [SELECT Id FROM User WHERE LastName = 'Owner' LIMIT 1];
        User peer = [SELECT Id FROM User WHERE LastName = 'Peer' LIMIT 1];

        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.ownerId = owner.Id;
        context.objectApiName = 'Account';

        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_RoleHierarchyAnalyzer()
            .analyze(context, new Set<Id>{ peer.Id });

        System.assert(
            !results.containsKey(peer.Id),
            'A peer in the same role (not above) should not get a hierarchy reason.'
        );
    }

    @IsTest
    static void returnsNothingWhenOwnerHasNoRole() {
        User roleless = [SELECT Id FROM User WHERE LastName = 'None' LIMIT 1];
        User manager = [SELECT Id FROM User WHERE LastName = 'Manager' LIMIT 1];

        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.ownerId = roleless.Id;
        context.objectApiName = 'Account';

        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_RoleHierarchyAnalyzer()
            .analyze(context, new Set<Id>{ manager.Id });

        System.assertEquals(0, results.size(), 'An owner with no role means no hierarchy-based reasons.');
    }

    @IsTest
    static void returnsNothingWhenOwnerIsNotAUser() {
        Group queue = new Group(Name = 'RAA Role Test Queue', Type = 'Queue');
        insert queue;

        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.ownerId = queue.Id;
        context.objectApiName = 'Account';

        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_RoleHierarchyAnalyzer()
            .analyze(context, new Set<Id>{ UserInfo.getUserId() });

        System.assertEquals(
            0,
            results.size(),
            'Queue-owned records are handled by ownership analysis, not role hierarchy.'
        );
    }
}
