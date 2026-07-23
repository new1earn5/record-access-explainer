/**
 * Test double for RAA_IEffectiveAccessProvider. Lets unit tests declare exactly which users
 * have which effective access to a record without depending on live UserRecordAccess data or
 * org sharing recalculation timing.
 */
@IsTest
public class RAA_FakeEffectiveAccessProvider implements RAA_IEffectiveAccessProvider {
    private final Map<Id, RAA_EffectiveAccessResult> canned;

    public RAA_FakeEffectiveAccessProvider(Map<Id, RAA_EffectiveAccessResult> canned) {
        this.canned = canned;
    }

    public Map<Id, RAA_EffectiveAccessResult> getEffectiveAccess(Id recordId, Set<Id> userIds) {
        Map<Id, RAA_EffectiveAccessResult> result = new Map<Id, RAA_EffectiveAccessResult>();
        for (Id userId : userIds) {
            if (canned.containsKey(userId)) {
                result.put(userId, canned.get(userId));
            }
        }
        return result;
    }
}
