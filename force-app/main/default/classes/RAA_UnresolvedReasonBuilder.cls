/**
 * Builds the fallback reason used when UserRecordAccess confirms a user has effective access
 * but no analyzer could conclusively explain why. Never guesses a specific mechanism.
 */
public without sharing class RAA_UnresolvedReasonBuilder {

    public RAA_AccessReasonDTO build(RAA_AnalysisContext context, List<String> attemptedAnalyzers) {
        RAA_AccessReasonDTO reason = new RAA_AccessReasonDTO();
        reason.category = 'Unresolved';
        reason.accessLevel = null;
        reason.confidence = 'Low';
        reason.isDirect = false;
        reason.sourceName = 'Salesforce-computed access - exact source not exposed';
        reason.sourceId = null;
        reason.sourceObject = null;
        reason.principalId = null;
        reason.principalType = null;
        reason.rowCause = null;
        reason.grantPath = context.prefixedPath('Unresolved -> User');
        reason.explanation = 'UserRecordAccess confirms this user has effective access to the record, but none of the '
                + 'available analyzers could conclusively prove the source. This can happen because of restriction rules '
                + '(which this package does not evaluate), recent sharing recalculation that has not yet completed, or a '
                + 'platform sharing mechanism that is not exposed through supported Apex, Schema, or SOQL APIs.';
        reason.evidence = 'Attempted analyzers: ' + String.join(attemptedAnalyzers, ', ')
                + '. Share rows evaluated: ' + (context.shareRows != null ? context.shareRows.size() : 0)
                + '. Share object: ' + (context.shareObjectApiName != null ? context.shareObjectApiName : 'none available');
        return reason;
    }
}
