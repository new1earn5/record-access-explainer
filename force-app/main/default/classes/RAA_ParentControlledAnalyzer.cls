/**
 * Handles objects whose sharing is Controlled By Parent. RAA_ContextBuilder already located the
 * controlling master-detail field (context.controllingParentFieldApiName) using
 * DescribeFieldResult.isCascadeDelete(), the supported way to detect a master-detail relationship
 * (there is no Schema.SharingModel / getSharingModel() API). A non-null controlling parent field
 * is precisely Salesforce's rule for "sharing is controlled by parent". This analyzer recursively
 * re-runs the ownership, role-hierarchy, share-row, team, and territory analyzers against the
 * parent record. Recursion is bounded by RAA_Settings__mdt's max parent depth and guarded against
 * cycles via RAA_AnalysisContext.visitedParentRecordIds.
 *
 * Object-wide permission bypasses (View/Modify All Data or All Records) are intentionally NOT
 * re-evaluated against the parent: those permissions were already evaluated once, against the
 * child record's own object type, by RAA_PermissionAnalyzer at the top of the pipeline.
 */
public without sharing class RAA_ParentControlledAnalyzer implements RAA_IReasonAnalyzer {
    private final RAA_ContextBuilder contextBuilder;
    private final RAA_OwnershipAnalyzer ownershipAnalyzer;
    private final RAA_RoleHierarchyAnalyzer roleHierarchyAnalyzer;
    private final RAA_ShareRowAnalyzer shareRowAnalyzer;
    private final RAA_TeamAnalyzer teamAnalyzer;
    private final RAA_TerritoryAnalyzer territoryAnalyzer;

    public RAA_ParentControlledAnalyzer() {
        this.contextBuilder = new RAA_ContextBuilder();
        this.ownershipAnalyzer = new RAA_OwnershipAnalyzer();
        this.roleHierarchyAnalyzer = new RAA_RoleHierarchyAnalyzer();
        this.shareRowAnalyzer = new RAA_ShareRowAnalyzer();
        this.teamAnalyzer = new RAA_TeamAnalyzer();
        this.territoryAnalyzer = new RAA_TerritoryAnalyzer();
    }

    public String getAnalyzerName() {
        return 'Parent Controlled';
    }

    public Map<Id, List<RAA_AccessReasonDTO>> analyze(RAA_AnalysisContext context, Set<Id> userIds) {
        Map<Id, List<RAA_AccessReasonDTO>> results = new Map<Id, List<RAA_AccessReasonDTO>>();
        if (userIds == null || userIds.isEmpty()) {
            return results;
        }
        if (context.controllingParentFieldApiName == null) {
            return results;
        }
        if (context.remainingParentDepth == null || context.remainingParentDepth <= 0) {
            context.warnings.add(
                'Maximum controlled-by-parent recursion depth reached while analyzing ' + context.objectApiName + '.'
            );
            return results;
        }

        Id parentRecordId = resolveParentRecordId(context);
        if (parentRecordId == null) {
            return results;
        }
        if (context.visitedParentRecordIds.contains(parentRecordId)) {
            context.warnings.add(
                'A cycle was detected in the controlled-by-parent chain at ' + context.objectApiName + '.'
            );
            return results;
        }

        RAA_AnalysisContext parentContext;
        try {
            parentContext = contextBuilder.buildParentContext(parentRecordId, context, new RAA_SettingsService());
        } catch (RAA_AppException e) {
            context.warnings.add(
                'Could not analyze the controlling parent record for ' + context.objectApiName + ': ' + e.getMessage()
            );
            return results;
        }

        mergeInto(results, ownershipAnalyzer.analyze(parentContext, userIds));
        mergeInto(results, roleHierarchyAnalyzer.analyze(parentContext, userIds));
        mergeInto(results, shareRowAnalyzer.analyze(parentContext, userIds));
        mergeInto(results, teamAnalyzer.analyze(parentContext, userIds));
        mergeInto(results, territoryAnalyzer.analyze(parentContext, userIds));
        mergeInto(results, this.analyze(parentContext, userIds)); // recurse further up the chain if applicable

        context.warnings.addAll(parentContext.warnings);

        return results;
    }

    private Id resolveParentRecordId(RAA_AnalysisContext context) {
        Id recordId = context.recordId;
        String fieldName = context.controllingParentFieldApiName;
        List<SObject> rows = Database.query(
            'SELECT ' +
                String.escapeSingleQuotes(fieldName) +
                ' FROM ' +
                String.escapeSingleQuotes(context.objectApiName) +
                ' WHERE Id = :recordId LIMIT 1'
        );
        if (rows.isEmpty() || rows[0].get(fieldName) == null) {
            return null;
        }
        return (Id) rows[0].get(fieldName);
    }

    private void mergeInto(Map<Id, List<RAA_AccessReasonDTO>> target, Map<Id, List<RAA_AccessReasonDTO>> source) {
        for (Id userId : source.keySet()) {
            List<RAA_AccessReasonDTO> reasonList = target.get(userId);
            if (reasonList == null) {
                reasonList = new List<RAA_AccessReasonDTO>();
                target.put(userId, reasonList);
            }
            reasonList.addAll(source.get(userId));
        }
    }
}
