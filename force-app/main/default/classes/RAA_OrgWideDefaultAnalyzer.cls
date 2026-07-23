/**
 * Reports on baseline organization-wide default (OWD) sharing access.
 *
 * There is no supported Apex, Schema, or SOQL API that exposes the actual OWD value (Private,
 * Public Read Only, Public Read/Write, and so on) for an arbitrary object - this was verified
 * directly against a live org: Schema.DescribeSObjectResult has no getSharingModel() method,
 * Schema.SharingModel does not exist as an Apex type, and EntityDefinition (queried through
 * plain, non-Tooling SOQL) has no SharingModel column. Retrieving it would require either the
 * Tooling API or a Metadata API callout, both of which this package deliberately avoids per its
 * "no callouts, no hard-coded Tooling API URLs" design constraint.
 *
 * The one OWD-adjacent fact that *is* reliably determinable is "controlled by parent" (handled
 * separately by RAA_ParentControlledAnalyzer via RAA_ContextBuilder's master-detail detection).
 * For every other object, this analyzer honestly reports that baseline OWD access may be involved
 * but could not be conclusively retrieved, at Low confidence, rather than guessing a value.
 */
public without sharing class RAA_OrgWideDefaultAnalyzer implements RAA_IReasonAnalyzer {

    public String getAnalyzerName() {
        return 'Organization-Wide Default';
    }

    public Map<Id, List<RAA_AccessReasonDTO>> analyze(RAA_AnalysisContext context, Set<Id> userIds) {
        Map<Id, List<RAA_AccessReasonDTO>> results = new Map<Id, List<RAA_AccessReasonDTO>>();
        if (userIds == null || userIds.isEmpty()) {
            return results;
        }
        if (context.controllingParentFieldApiName != null) {
            // Controlled by parent: RAA_ParentControlledAnalyzer explains access instead.
            return results;
        }

        RAA_AccessReasonDTO template = buildUnresolvedOwdReason(context);
        for (Id userId : userIds) {
            results.put(userId, new List<RAA_AccessReasonDTO>{ cloneReason(template) });
        }
        return results;
    }

    private RAA_AccessReasonDTO buildUnresolvedOwdReason(RAA_AnalysisContext context) {
        RAA_AccessReasonDTO reason = new RAA_AccessReasonDTO();
        reason.category = 'Organization-Wide Default';
        reason.accessLevel = null;
        reason.confidence = 'Low';
        reason.isDirect = false;
        reason.sourceName = 'Organization-Wide Default: ' + context.objectApiName;
        reason.sourceId = null;
        reason.sourceObject = context.objectApiName;
        reason.principalId = null;
        reason.principalType = 'AllInternalUsers';
        reason.rowCause = null;
        reason.grantPath = context.prefixedPath('Organization-Wide Default (unknown) -> User');
        reason.explanation = 'Baseline sharing access may be involved, but the organization-wide default could not be '
                + 'conclusively retrieved through the supported Apex implementation.';
        reason.evidence = 'No supported Apex/Schema/SOQL API exposes the OWD value for ' + context.objectApiName + '.';
        return reason;
    }

    private RAA_AccessReasonDTO cloneReason(RAA_AccessReasonDTO source) {
        RAA_AccessReasonDTO copy = new RAA_AccessReasonDTO();
        copy.category = source.category;
        copy.accessLevel = source.accessLevel;
        copy.confidence = source.confidence;
        copy.isDirect = source.isDirect;
        copy.sourceName = source.sourceName;
        copy.sourceId = source.sourceId;
        copy.sourceObject = source.sourceObject;
        copy.principalId = source.principalId;
        copy.principalType = source.principalType;
        copy.rowCause = source.rowCause;
        copy.grantPath = source.grantPath;
        copy.explanation = source.explanation;
        copy.evidence = source.evidence;
        return copy;
    }
}
