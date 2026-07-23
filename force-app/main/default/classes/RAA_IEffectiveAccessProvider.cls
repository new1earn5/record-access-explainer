/**
 * Abstraction over "what access does this user actually have to this record".
 * The production implementation (RAA_UserRecordAccessProvider) queries UserRecordAccess.
 * Unit tests inject a fake implementation so reason-attribution logic can be tested
 * deterministically without depending on org sharing recalculation.
 */
public interface RAA_IEffectiveAccessProvider {
    /**
     * Returns effective access for every requested user against a single record.
     * Implementations must return one entry per user that has a resolvable UserRecordAccess
     * row; users with no row (no access at all) are simply omitted from the map.
     */
    Map<Id, RAA_EffectiveAccessResult> getEffectiveAccess(Id recordId, Set<Id> userIds);
}
