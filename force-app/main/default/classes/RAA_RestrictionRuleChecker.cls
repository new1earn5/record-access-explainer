/**
 * Best-effort detection of active Restriction Rules on the analyzed object. RestrictionRule is
 * exposed through the Tooling API / Metadata API, not necessarily through plain Apex SOQL in
 * every org - this class probes it dynamically (never a compile-time sObject type, since a
 * static reference would break deployment in any org/API context where the object cannot be
 * queried this way) and degrades to "unknown" rather than guessing when the probe fails.
 *
 * Restriction rules only ever narrow access, never grant it, so this is never treated as an
 * access reason - it is surfaced purely as a scan-level warning (see RAA_ContextBuilder) that
 * the results may overstate access for some users.
 */
public without sharing class RAA_RestrictionRuleChecker {

    /** Returns the count of active restriction rules on the object, or null if it could not be determined. */
    public Integer countActiveRestrictionRules(String objectApiName) {
        if (!Schema.getGlobalDescribe().containsKey('RestrictionRule')) {
            return null;
        }
        try {
            List<SObject> rows = Database.query(
                    'SELECT Id FROM RestrictionRule WHERE EntityDefinitionId = :objectApiName AND Active = true');
            return rows.size();
        } catch (System.QueryException e) {
            return null;
        }
    }
}
