/**
 * Bulk-loaded, per-scan context shared by the reason aggregator and every RAA_IReasonAnalyzer
 * implementation. Built once per analyzed record (and, for controlled-by-parent chains, once
 * per ancestor record) so analyzers never need to re-resolve the same describe or share data.
 */
public class RAA_AnalysisContext {
    public Id recordId;
    public String objectApiName;
    public Schema.DescribeSObjectResult objectDescribe;
    public SObject targetRecord;
    public Id ownerId;

    public String shareObjectApiName;
    public String shareParentField;
    public String shareUserOrGroupField;
    public String shareAccessLevelField;
    public String shareRowCauseField;
    public List<SObject> shareRows = new List<SObject>();

    public Integer maxGroupDepth;
    public Integer maxParentDepth;
    public Integer remainingParentDepth;
    public Set<Id> visitedParentRecordIds = new Set<Id>();
    public String controllingParentFieldApiName;

    /** Non-null only when this context represents a controlled-by-parent ancestor record. */
    public String grantPathPrefix;

    public List<String> warnings = new List<String>();

    // RAA_ContextBuilder constructs an instance empty, then sets every field directly.
    @SuppressWarnings('PMD.EmptyStatementBlock')
    public RAA_AnalysisContext() {
    }

    public String prefixedPath(String path) {
        if (String.isBlank(grantPathPrefix)) {
            return path;
        }
        return grantPathPrefix + ' -> ' + path;
    }
}
