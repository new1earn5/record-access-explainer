/**
 * Production implementation of RAA_IEffectiveAccessProvider backed by UserRecordAccess,
 * the authoritative Salesforce-computed source of effective record access.
 *
 * UserRecordAccess's supported filter shapes were verified directly against a live org: the
 * WHERE clause may combine UserId = [a single ID] with either RecordId = [a single ID] or
 * RecordId IN [a list of IDs] (optionally with a Has*Access = true condition); "UserId IN
 * [list]" is rejected at compile time with "Can filter on only UserId = [single ID] ...". Since
 * a scan always targets exactly one record and many users, there is no supported multi-user
 * query shape available, so this is the one deliberate, documented exception to the "no SOQL in
 * a loop" rule: one UserRecordAccess query is issued per user in the batch chunk. The batch
 * scope (default 20, configurable via RAA_Settings__mdt) keeps this well within governor limits,
 * and every other data source used by the reason-attribution pipeline (share rows, groups,
 * permission sets, teams, territories) is bulk-queried once per chunk instead.
 *
 * Runs without sharing because it evaluates access on behalf of OTHER users, not the running
 * user, and is only ever invoked from the elevated batch/service layer - it has no
 * @AuraEnabled methods.
 */
// Deliberately without sharing and CRUD/FLS-unchecked: queries UserRecordAccess, a computed
// system object with no meaningful FLS concept, reached only through the with-sharing
// controller's permission gate.
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class RAA_UserRecordAccessProvider implements RAA_IEffectiveAccessProvider {
    // See class-level comment: UserRecordAccess cannot be bulk-queried by a list of users for a
    // single record, so this is the one deliberate, documented exception to bulk-querying every
    // other data source once per chunk (also disclosed in README.md §1).
    @SuppressWarnings('PMD.OperationWithLimitsInLoop')
    public Map<Id, RAA_EffectiveAccessResult> getEffectiveAccess(Id recordId, Set<Id> userIds) {
        Map<Id, RAA_EffectiveAccessResult> results = new Map<Id, RAA_EffectiveAccessResult>();
        if (recordId == null || userIds == null || userIds.isEmpty()) {
            return results;
        }

        for (Id userId : userIds) {
            // Intentional per-user query: see class-level comment for why UserRecordAccess
            // cannot be bulk-queried by a list of users for a single record.
            List<UserRecordAccess> rows = [
                SELECT
                    RecordId,
                    HasReadAccess,
                    HasEditAccess,
                    HasDeleteAccess,
                    HasTransferAccess,
                    HasAllAccess,
                    MaxAccessLevel
                FROM UserRecordAccess
                WHERE RecordId = :recordId AND UserId = :userId
            ];
            if (rows.isEmpty()) {
                continue;
            }
            UserRecordAccess access = rows[0];
            results.put(
                userId,
                new RAA_EffectiveAccessResult(
                    userId,
                    access.HasReadAccess,
                    access.HasEditAccess,
                    access.HasDeleteAccess,
                    access.HasTransferAccess,
                    access.HasAllAccess,
                    access.MaxAccessLevel
                )
            );
        }
        return results;
    }
}
