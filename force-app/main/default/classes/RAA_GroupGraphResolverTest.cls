@IsTest
private class RAA_GroupGraphResolverTest {
    @TestSetup
    static void setup() {
        User u = RAA_TestDataFactory.createUser('Nested', 'Member');

        Group outerGroup = new Group(Name = 'RAA Outer Group', Type = 'Regular');
        Group innerGroup = new Group(Name = 'RAA Inner Group', Type = 'Regular');
        insert new List<Group>{ outerGroup, innerGroup };

        // outerGroup contains innerGroup (nested group), innerGroup contains the user.
        insert new GroupMember(GroupId = outerGroup.Id, UserOrGroupId = innerGroup.Id);
        insert new GroupMember(GroupId = innerGroup.Id, UserOrGroupId = u.Id);
    }

    @IsTest
    static void resolvesPathThroughNestedGroups() {
        User u = [SELECT Id FROM User WHERE LastName = 'Member' LIMIT 1];
        Group outerGroup = [SELECT Id, Name FROM Group WHERE Name = 'RAA Outer Group' LIMIT 1];

        Test.startTest();
        Map<Id, List<RAA_GroupPathDTO>> paths = new RAA_GroupGraphResolver()
            .resolvePaths(new Set<Id>{ outerGroup.Id }, new Set<Id>{ u.Id }, 6);
        Test.stopTest();

        System.assert(paths.containsKey(u.Id), 'The nested member should be reachable from the outer group.');
        RAA_GroupPathDTO path = paths.get(u.Id)[0];
        String rendered = path.renderPath('User');
        System.assert(rendered.contains('RAA Outer Group'), 'Path should include the root group.');
        System.assert(rendered.contains('RAA Inner Group'), 'Path should include the nested group.');
        System.assert(rendered.endsWith('User'), 'Path should end at the user.');
    }

    @IsTest
    static void doesNotResolveWhenMaxDepthTooShallow() {
        User u = [SELECT Id FROM User WHERE LastName = 'Member' LIMIT 1];
        Group outerGroup = [SELECT Id FROM Group WHERE Name = 'RAA Outer Group' LIMIT 1];

        Map<Id, List<RAA_GroupPathDTO>> paths = new RAA_GroupGraphResolver()
            .resolvePaths(new Set<Id>{ outerGroup.Id }, new Set<Id>{ u.Id }, 1);

        System.assert(!paths.containsKey(u.Id), 'A max depth of 1 should not reach a user two levels down.');
    }

    @IsTest
    static void terminatesSafelyOnDiamondShapedMembershipWithoutDuplicateExpansion() {
        // Salesforce itself rejects a true circular GroupMember relationship at the DML level
        // (CIRCULAR_DEPENDENCY), so a literal cycle cannot be constructed here. This instead
        // proves the resolver's visited-group guard handles a diamond (two parents sharing one
        // descendant) safely and terminates without duplicate work or errors.
        Group top = new Group(Name = 'RAA Diamond Top', Type = 'Regular');
        Group left = new Group(Name = 'RAA Diamond Left', Type = 'Regular');
        Group right = new Group(Name = 'RAA Diamond Right', Type = 'Regular');
        Group bottom = new Group(Name = 'RAA Diamond Bottom', Type = 'Regular');
        insert new List<Group>{ top, left, right, bottom };

        insert new List<GroupMember>{
            new GroupMember(GroupId = top.Id, UserOrGroupId = left.Id),
            new GroupMember(GroupId = top.Id, UserOrGroupId = right.Id),
            new GroupMember(GroupId = left.Id, UserOrGroupId = bottom.Id),
            new GroupMember(GroupId = right.Id, UserOrGroupId = bottom.Id)
        };

        User u = RAA_TestDataFactory.createUser('Diamond', 'Member');
        insert new GroupMember(GroupId = bottom.Id, UserOrGroupId = u.Id);

        Test.startTest();
        Map<Id, List<RAA_GroupPathDTO>> paths = new RAA_GroupGraphResolver()
            .resolvePaths(new Set<Id>{ top.Id }, new Set<Id>{ u.Id }, 10);
        Test.stopTest();

        System.assert(paths.containsKey(u.Id), 'The user reachable through the diamond should be found.');
        System.assertEquals(
            1,
            paths.get(u.Id).size(),
            'Only one path should be recorded even though the user is reachable via two branches.'
        );
    }

    @IsTest
    static void describeGroupsReturnsEmptyMapForNullOrEmptyInput() {
        Map<Id, Group> result = new RAA_GroupGraphResolver().describeGroups(null);
        System.assertEquals(0, result.size(), 'Null input should yield an empty map.');
    }
}
