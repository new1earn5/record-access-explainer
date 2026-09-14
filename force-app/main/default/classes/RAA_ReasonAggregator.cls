/**
 * Orchestrates the full reason-attribution pipeline for one batch chunk of users against one
 * record: builds the shared analysis context once, confirms effective access through the
 * injected RAA_IEffectiveAccessProvider, runs every injected RAA_IReasonAnalyzer, and merges,
 * deduplicates, and deterministically sorts the results. A user is never included in the output
 * unless UserRecordAccess (or the injected fake, in tests) confirms they have some effective
 * access - analyzer output for any other user is discarded rather than trusted on its own.
 *
 * Dependency injection (constructor overload) lets unit tests substitute fake analyzers and a
 * fake effective-access provider so reason-attribution logic can be verified deterministically
 * without depending on live org sharing recalculation.
 */
public without sharing class RAA_ReasonAggregator {
    public class AggregatedUserResult {
        public Id userId;
        public RAA_EffectiveAccessResult effectiveAccess;
        public List<RAA_AccessReasonDTO> reasons;
    }

    private final RAA_IEffectiveAccessProvider effectiveAccessProvider;
    private final List<RAA_IReasonAnalyzer> analyzers;
    private final RAA_ContextBuilder contextBuilder;
    private final RAA_UnresolvedReasonBuilder unresolvedBuilder;
    private final RAA_SettingsService settings;

    public RAA_ReasonAggregator() {
        this(
            new RAA_UserRecordAccessProvider(),
            defaultAnalyzers(),
            new RAA_ContextBuilder(),
            new RAA_SettingsService()
        );
    }

    public RAA_ReasonAggregator(
        RAA_IEffectiveAccessProvider effectiveAccessProvider,
        List<RAA_IReasonAnalyzer> analyzers,
        RAA_ContextBuilder contextBuilder,
        RAA_SettingsService settings
    ) {
        this.effectiveAccessProvider = effectiveAccessProvider;
        this.analyzers = analyzers;
        this.contextBuilder = contextBuilder;
        this.unresolvedBuilder = new RAA_UnresolvedReasonBuilder();
        this.settings = settings;
    }

    private static List<RAA_IReasonAnalyzer> defaultAnalyzers() {
        return new List<RAA_IReasonAnalyzer>{
            new RAA_OwnershipAnalyzer(),
            new RAA_RoleHierarchyAnalyzer(),
            new RAA_ShareRowAnalyzer(),
            new RAA_PermissionAnalyzer(),
            new RAA_TeamAnalyzer(),
            new RAA_TerritoryAnalyzer(),
            new RAA_ParentControlledAnalyzer(),
            new RAA_OrgWideDefaultAnalyzer()
        };
    }

    public List<AggregatedUserResult> analyzeBatch(
        Id recordId,
        Set<Id> userIds,
        List<String> warningsOut,
        List<String> hygieneNotesOut
    ) {
        List<AggregatedUserResult> output = new List<AggregatedUserResult>();
        if (userIds == null || userIds.isEmpty()) {
            return output;
        }

        RAA_AnalysisContext context = contextBuilder.buildTopLevelContext(recordId, settings);

        Map<Id, RAA_EffectiveAccessResult> effectiveAccessMap = effectiveAccessProvider.getEffectiveAccess(
            recordId,
            userIds
        );
        Set<Id> usersWithAccess = new Set<Id>();
        for (Id userId : effectiveAccessMap.keySet()) {
            if (effectiveAccessMap.get(userId).hasAnyAccess()) {
                usersWithAccess.add(userId);
            }
        }

        if (usersWithAccess.isEmpty()) {
            if (warningsOut != null) {
                warningsOut.addAll(context.warnings);
            }
            if (hygieneNotesOut != null) {
                hygieneNotesOut.addAll(context.hygieneNotes);
            }
            return output;
        }

        Map<Id, List<RAA_AccessReasonDTO>> reasonsByUser = new Map<Id, List<RAA_AccessReasonDTO>>();
        List<String> attemptedAnalyzerNames = new List<String>();

        for (RAA_IReasonAnalyzer analyzer : analyzers) {
            attemptedAnalyzerNames.add(analyzer.getAnalyzerName());
            Map<Id, List<RAA_AccessReasonDTO>> analyzerResults;
            try {
                analyzerResults = analyzer.analyze(context, usersWithAccess);
            } catch (Exception e) {
                context.warnings.add(analyzer.getAnalyzerName() + ' analyzer could not complete: ' + e.getMessage());
                continue;
            }
            if (analyzerResults == null) {
                continue;
            }
            for (Id userId : analyzerResults.keySet()) {
                if (!usersWithAccess.contains(userId)) {
                    continue; // never trust an analyzer-only claim without independent effective-access confirmation
                }
                List<RAA_AccessReasonDTO> reasonList = reasonsByUser.get(userId);
                if (reasonList == null) {
                    reasonList = new List<RAA_AccessReasonDTO>();
                    reasonsByUser.put(userId, reasonList);
                }
                reasonList.addAll(analyzerResults.get(userId));
            }
        }

        for (Id userId : usersWithAccess) {
            List<RAA_AccessReasonDTO> reasons = dedupeAndSort(reasonsByUser.get(userId));
            if (reasons.isEmpty()) {
                reasons.add(unresolvedBuilder.build(context, attemptedAnalyzerNames));
            }
            AggregatedUserResult result = new AggregatedUserResult();
            result.userId = userId;
            result.effectiveAccess = effectiveAccessMap.get(userId);
            result.reasons = reasons;
            output.add(result);
        }

        if (warningsOut != null) {
            warningsOut.addAll(context.warnings);
        }
        if (hygieneNotesOut != null) {
            hygieneNotesOut.addAll(context.hygieneNotes);
        }
        return output;
    }

    private List<RAA_AccessReasonDTO> dedupeAndSort(List<RAA_AccessReasonDTO> reasons) {
        List<RAA_AccessReasonDTO> result = new List<RAA_AccessReasonDTO>();
        if (reasons == null || reasons.isEmpty()) {
            return result;
        }
        Set<String> seenKeys = new Set<String>();
        for (RAA_AccessReasonDTO reason : reasons) {
            String key = reason.dedupeKey();
            if (seenKeys.contains(key)) {
                continue;
            }
            seenKeys.add(key);
            result.add(reason);
        }
        result.sort();
        return result;
    }
}
