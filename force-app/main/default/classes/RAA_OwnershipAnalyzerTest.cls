@IsTest
private class RAA_OwnershipAnalyzerTest {

    @TestSetup
    static void setup() {
        RAA_TestDataFactory.createUser('Owner', 'Direct');
        User queueMember = RAA_TestDataFactory.createUser('Queue', 'Member');

        Group queue = new Group(Name = 'RAA Test Queue', Type = 'Queue');
        insert queue;
        insert new QueuesObject(QueueId = queue.Id, SobjectType = 'Case');
        insert new GroupMember(GroupId = queue.Id, UserOrGroupId = queueMember.Id);
    }

    @IsTest
    static void detectsDirectOwnership() {
        User owner = [SELECT Id FROM User WHERE LastName = 'Direct' LIMIT 1];

        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.ownerId = owner.Id;

        Test.startTest();
        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_OwnershipAnalyzer().analyze(context, new Set<Id>{ owner.Id });
        Test.stopTest();

        System.assert(results.containsKey(owner.Id), 'The owner should have an ownership reason.');
        System.assertEquals('Ownership', results.get(owner.Id)[0].category);
        System.assertEquals('High', results.get(owner.Id)[0].confidence);
        System.assertEquals(true, results.get(owner.Id)[0].isDirect);
    }

    @IsTest
    static void detectsQueueOwnership() {
        Group queue = [SELECT Id FROM Group WHERE Name = 'RAA Test Queue' LIMIT 1];
        User member = [SELECT Id FROM User WHERE LastName = 'Member' LIMIT 1];

        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.ownerId = queue.Id;
        context.maxGroupDepth = 6;

        Test.startTest();
        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_OwnershipAnalyzer().analyze(context, new Set<Id>{ member.Id });
        Test.stopTest();

        System.assert(results.containsKey(member.Id), 'The queue member should have an ownership reason.');
        System.assertEquals('Ownership', results.get(member.Id)[0].category);
        System.assert(results.get(member.Id)[0].explanation.contains('queue'), 'Explanation should mention the queue.');
    }

    @IsTest
    static void returnsNothingForUnrelatedUser() {
        User owner = [SELECT Id FROM User WHERE LastName = 'Direct' LIMIT 1];
        User other = [SELECT Id FROM User WHERE LastName = 'Member' LIMIT 1];

        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.ownerId = owner.Id;

        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_OwnershipAnalyzer().analyze(context, new Set<Id>{ other.Id });

        System.assert(!results.containsKey(other.Id), 'A user unrelated to ownership should not get an ownership reason.');
    }

    @IsTest
    static void returnsNothingWhenNoOwnerOnContext() {
        RAA_AnalysisContext context = new RAA_AnalysisContext();
        Map<Id, List<RAA_AccessReasonDTO>> results = new RAA_OwnershipAnalyzer().analyze(context, new Set<Id>{ UserInfo.getUserId() });
        System.assertEquals(0, results.size(), 'No owner on the context means no ownership reasons.');
    }
}
