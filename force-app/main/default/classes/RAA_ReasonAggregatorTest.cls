@IsTest
private class RAA_ReasonAggregatorTest {

    private static RAA_ReasonAggregator buildAggregator(RAA_IEffectiveAccessProvider provider, List<RAA_IReasonAnalyzer> analyzers) {
        return new RAA_ReasonAggregator(provider, analyzers, new RAA_ContextBuilder(), new RAA_SettingsService());
    }

    @IsTest
    static void onlyIncludesUsersWithConfirmedEffectiveAccess() {
        Account acct = new Account(Name = 'RAA Aggregator Account');
        insert acct;

        User hasAccess = RAA_TestDataFactory.createUser('Agg', 'HasAccess');
        User noAccess = RAA_TestDataFactory.createUser('Agg', 'NoAccess');

        Map<Id, RAA_EffectiveAccessResult> canned = new Map<Id, RAA_EffectiveAccessResult>{
                hasAccess.Id => RAA_TestDataFactory.readOnlyAccess(hasAccess.Id),
                noAccess.Id => RAA_TestDataFactory.noAccess(noAccess.Id)
        };
        RAA_ReasonAggregator aggregator = buildAggregator(new RAA_FakeEffectiveAccessProvider(canned), new List<RAA_IReasonAnalyzer>());

        Test.startTest();
        List<RAA_ReasonAggregator.AggregatedUserResult> output = aggregator.analyzeBatch(
                acct.Id, new Set<Id>{ hasAccess.Id, noAccess.Id }, new List<String>());
        Test.stopTest();

        System.assertEquals(1, output.size(), 'Only the user with confirmed effective access should be included.');
        System.assertEquals(hasAccess.Id, output[0].userId);
    }

    @IsTest
    static void producesMultipleReasonsForOneUser() {
        Account acct = new Account(Name = 'RAA Aggregator Account 2');
        insert acct;
        User u = RAA_TestDataFactory.createUser('Agg', 'Multi');

        Map<Id, RAA_EffectiveAccessResult> canned = new Map<Id, RAA_EffectiveAccessResult>{ u.Id => RAA_TestDataFactory.fullAccess(u.Id) };
        Map<Id, List<RAA_AccessReasonDTO>> ownershipReasons = new Map<Id, List<RAA_AccessReasonDTO>>{
                u.Id => new List<RAA_AccessReasonDTO>{ RAA_TestDataFactory.buildReason('Ownership', 'High') }
        };
        Map<Id, List<RAA_AccessReasonDTO>> permissionReasons = new Map<Id, List<RAA_AccessReasonDTO>>{
                u.Id => new List<RAA_AccessReasonDTO>{ RAA_TestDataFactory.buildReason('Permission', 'High') }
        };

        RAA_ReasonAggregator aggregator = buildAggregator(new RAA_FakeEffectiveAccessProvider(canned), new List<RAA_IReasonAnalyzer>{
                new RAA_FakeReasonAnalyzer('FakeOwnership', ownershipReasons),
                new RAA_FakeReasonAnalyzer('FakePermission', permissionReasons)
        });

        List<RAA_ReasonAggregator.AggregatedUserResult> output = aggregator.analyzeBatch(acct.Id, new Set<Id>{ u.Id }, new List<String>());

        System.assertEquals(1, output.size());
        System.assertEquals(2, output[0].reasons.size(), 'Both analyzers\' reasons should be present.');
    }

    @IsTest
    static void fallsBackToUnresolvedWhenNoAnalyzerExplainsAccess() {
        Account acct = new Account(Name = 'RAA Aggregator Account 3');
        insert acct;
        User u = RAA_TestDataFactory.createUser('Agg', 'Unresolved');

        Map<Id, RAA_EffectiveAccessResult> canned = new Map<Id, RAA_EffectiveAccessResult>{ u.Id => RAA_TestDataFactory.readOnlyAccess(u.Id) };
        Map<Id, List<RAA_AccessReasonDTO>> emptyReasons = new Map<Id, List<RAA_AccessReasonDTO>>();

        RAA_ReasonAggregator aggregator = buildAggregator(new RAA_FakeEffectiveAccessProvider(canned), new List<RAA_IReasonAnalyzer>{
                new RAA_FakeReasonAnalyzer('FakeEmpty', emptyReasons)
        });

        List<RAA_ReasonAggregator.AggregatedUserResult> output = aggregator.analyzeBatch(acct.Id, new Set<Id>{ u.Id }, new List<String>());

        System.assertEquals(1, output.size());
        System.assertEquals(1, output[0].reasons.size());
        System.assertEquals('Unresolved', output[0].reasons[0].category);
        System.assertEquals('Low', output[0].reasons[0].confidence);
    }

    @IsTest
    static void oneAnalyzerFailingDoesNotDiscardOtherAnalyzersResults() {
        Account acct = new Account(Name = 'RAA Aggregator Account 4');
        insert acct;
        User u = RAA_TestDataFactory.createUser('Agg', 'Partial');

        Map<Id, RAA_EffectiveAccessResult> canned = new Map<Id, RAA_EffectiveAccessResult>{ u.Id => RAA_TestDataFactory.fullAccess(u.Id) };
        Map<Id, List<RAA_AccessReasonDTO>> workingReasons = new Map<Id, List<RAA_AccessReasonDTO>>{
                u.Id => new List<RAA_AccessReasonDTO>{ RAA_TestDataFactory.buildReason('Ownership', 'High') }
        };

        RAA_ReasonAggregator aggregator = buildAggregator(new RAA_FakeEffectiveAccessProvider(canned), new List<RAA_IReasonAnalyzer>{
                new RAA_FakeReasonAnalyzer('FakeFailing', new Map<Id, List<RAA_AccessReasonDTO>>(), true),
                new RAA_FakeReasonAnalyzer('FakeWorking', workingReasons)
        });

        List<String> warnings = new List<String>();
        List<RAA_ReasonAggregator.AggregatedUserResult> output = aggregator.analyzeBatch(acct.Id, new Set<Id>{ u.Id }, warnings);

        System.assertEquals(1, output.size());
        System.assertEquals(1, output[0].reasons.size(), 'The working analyzer\'s reason should still be present.');
        System.assert(!warnings.isEmpty(), 'A warning should be recorded for the failing analyzer.');
    }

    @IsTest
    static void deduplicatesIdenticalReasonsFromDifferentAnalyzers() {
        Account acct = new Account(Name = 'RAA Aggregator Account 5');
        insert acct;
        User u = RAA_TestDataFactory.createUser('Agg', 'Dedupe');

        Map<Id, RAA_EffectiveAccessResult> canned = new Map<Id, RAA_EffectiveAccessResult>{ u.Id => RAA_TestDataFactory.fullAccess(u.Id) };
        Map<Id, List<RAA_AccessReasonDTO>> duplicateReasons = new Map<Id, List<RAA_AccessReasonDTO>>{
                u.Id => new List<RAA_AccessReasonDTO>{ RAA_TestDataFactory.buildReason('Ownership', 'High') }
        };

        RAA_ReasonAggregator aggregator = buildAggregator(new RAA_FakeEffectiveAccessProvider(canned), new List<RAA_IReasonAnalyzer>{
                new RAA_FakeReasonAnalyzer('FakeOne', duplicateReasons),
                new RAA_FakeReasonAnalyzer('FakeTwo', duplicateReasons)
        });

        List<RAA_ReasonAggregator.AggregatedUserResult> output = aggregator.analyzeBatch(acct.Id, new Set<Id>{ u.Id }, new List<String>());

        System.assertEquals(1, output.size());
        System.assertEquals(1, output[0].reasons.size(), 'Identical reasons from two analyzers should be deduplicated to one.');
    }

    @IsTest
    static void returnsEmptyListForEmptyUserSet() {
        RAA_ReasonAggregator aggregator = buildAggregator(
                new RAA_FakeEffectiveAccessProvider(new Map<Id, RAA_EffectiveAccessResult>()), new List<RAA_IReasonAnalyzer>());
        List<RAA_ReasonAggregator.AggregatedUserResult> output = aggregator.analyzeBatch(UserInfo.getUserId(), new Set<Id>(), new List<String>());
        System.assertEquals(0, output.size());
    }
}
