/**
 * Test double for RAA_IReasonAnalyzer. Returns a canned set of reasons per user, and can
 * optionally throw to exercise the aggregator's per-analyzer partial-failure handling.
 */
@IsTest
public class RAA_FakeReasonAnalyzer implements RAA_IReasonAnalyzer {

    private final String name;
    private final Map<Id, List<RAA_AccessReasonDTO>> canned;
    private final Boolean shouldThrow;

    public RAA_FakeReasonAnalyzer(String name, Map<Id, List<RAA_AccessReasonDTO>> canned) {
        this(name, canned, false);
    }

    public RAA_FakeReasonAnalyzer(String name, Map<Id, List<RAA_AccessReasonDTO>> canned, Boolean shouldThrow) {
        this.name = name;
        this.canned = canned;
        this.shouldThrow = shouldThrow;
    }

    public String getAnalyzerName() {
        return name;
    }

    public Map<Id, List<RAA_AccessReasonDTO>> analyze(RAA_AnalysisContext context, Set<Id> userIds) {
        if (shouldThrow) {
            throw new RAA_AppException('Simulated analyzer failure for ' + name);
        }
        Map<Id, List<RAA_AccessReasonDTO>> result = new Map<Id, List<RAA_AccessReasonDTO>>();
        for (Id userId : userIds) {
            if (canned.containsKey(userId)) {
                result.put(userId, canned.get(userId));
            }
        }
        return result;
    }
}
