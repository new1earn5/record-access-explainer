/**
 * Builds a fully populated RAA_AnalysisContext for a single record: resolves the object type,
 * owner, dynamic share object, and share rows exactly once. Used both for the top-level
 * analyzed record and, recursively, by RAA_ParentControlledAnalyzer for each controlling
 * ancestor record, so context-building logic exists in exactly one place.
 */
public without sharing class RAA_ContextBuilder {
    private final RAA_RecordMetadataResolver metadataResolver;
    private final RAA_ShareObjectResolver shareResolver;
    private final RAA_SharingRecalculationChecker recalculationChecker;
    private final RAA_RestrictionRuleChecker restrictionRuleChecker;

    public RAA_ContextBuilder() {
        this(
            new RAA_RecordMetadataResolver(),
            new RAA_ShareObjectResolver(),
            new RAA_SharingRecalculationChecker(),
            new RAA_RestrictionRuleChecker()
        );
    }

    public RAA_ContextBuilder(RAA_RecordMetadataResolver metadataResolver, RAA_ShareObjectResolver shareResolver) {
        this(metadataResolver, shareResolver, new RAA_SharingRecalculationChecker(), new RAA_RestrictionRuleChecker());
    }

    public RAA_ContextBuilder(
        RAA_RecordMetadataResolver metadataResolver,
        RAA_ShareObjectResolver shareResolver,
        RAA_SharingRecalculationChecker recalculationChecker,
        RAA_RestrictionRuleChecker restrictionRuleChecker
    ) {
        this.metadataResolver = metadataResolver;
        this.shareResolver = shareResolver;
        this.recalculationChecker = recalculationChecker;
        this.restrictionRuleChecker = restrictionRuleChecker;
    }

    public RAA_AnalysisContext buildTopLevelContext(Id recordId, RAA_SettingsService settings) {
        RAA_AnalysisContext context = buildContext(recordId, settings);
        context.remainingParentDepth = settings.maxParentDepth;

        if (recalculationChecker.isRecalculationInProgress()) {
            context.warnings.add(
                'A sharing recalculation job is currently queued or running for this org; ' +
                'results may not reflect very recent role, group, or sharing-rule changes until it finishes.'
            );
        }

        Integer restrictionRuleCount = restrictionRuleChecker.countActiveRestrictionRules(context.objectApiName);
        if (restrictionRuleCount != null && restrictionRuleCount > 0) {
            context.warnings.add(
                restrictionRuleCount +
                    ' active restriction rule(s) exist on ' +
                    context.objectApiName +
                    '. Restriction rules can only narrow visibility further and are not evaluated by this scan, ' +
                    'so some users shown here with access may actually be restricted from seeing this record.'
            );
        }

        return context;
    }

    public RAA_AnalysisContext buildParentContext(
        Id parentRecordId,
        RAA_AnalysisContext childContext,
        RAA_SettingsService settings
    ) {
        RAA_AnalysisContext parentContext = buildContext(parentRecordId, settings);
        parentContext.visitedParentRecordIds = new Set<Id>(childContext.visitedParentRecordIds);
        parentContext.visitedParentRecordIds.add(childContext.recordId);
        parentContext.remainingParentDepth = childContext.remainingParentDepth - 1;
        parentContext.grantPathPrefix = childContext.prefixedPath(
            'Controlled by parent through ' +
                childContext.objectApiName +
                '.' +
                childContext.controllingParentFieldApiName
        );
        return parentContext;
    }

    private RAA_AnalysisContext buildContext(Id recordId, RAA_SettingsService settings) {
        RAA_RecordMetadataResolver.ResolvedRecord resolved = metadataResolver.resolve(recordId);

        RAA_AnalysisContext context = new RAA_AnalysisContext();
        context.recordId = recordId;
        context.objectApiName = resolved.objectApiName;
        context.objectDescribe = resolved.objectDescribe;
        context.targetRecord = resolved.targetRecord;
        context.maxGroupDepth = settings.maxGroupDepth;
        context.maxParentDepth = settings.maxParentDepth;

        Map<String, Schema.SObjectField> fieldMap = resolved.objectDescribe.fields.getMap();
        if (fieldMap.containsKey('OwnerId') && resolved.targetRecord.isSet('OwnerId')) {
            context.ownerId = (Id) resolved.targetRecord.get('OwnerId');
        }

        RAA_ShareObjectResolver.ShareObjectInfo shareInfo = shareResolver.resolve(resolved.objectDescribe);
        if (shareInfo != null) {
            context.shareObjectApiName = shareInfo.shareObjectApiName;
            context.shareParentField = shareInfo.parentField;
            context.shareUserOrGroupField = shareInfo.userOrGroupField;
            context.shareAccessLevelField = shareInfo.accessLevelField;
            context.shareRowCauseField = shareInfo.rowCauseField;
            context.shareRows = queryShareRows(shareInfo, recordId);
        } else {
            context.warnings.add(
                'No sharing table could be located for ' +
                    resolved.objectApiName +
                    '; direct share, sharing-rule, and group-share analysis is unavailable for this object.'
            );
        }

        context.controllingParentFieldApiName = findControllingParentField(fieldMap);

        return context;
    }

    // All identifiers concatenated into the query below (object/field API names) come from
    // RAA_ShareObjectResolver, which derives them from Schema describes - never from client
    // input - so this dynamic SOQL is not an injection risk despite the static pattern match.
    @SuppressWarnings('PMD.ApexSOQLInjection')
    private List<SObject> queryShareRows(RAA_ShareObjectResolver.ShareObjectInfo shareInfo, Id recordId) {
        Set<String> fields = new Set<String>{
            'Id',
            shareInfo.userOrGroupField,
            shareInfo.rowCauseField,
            shareInfo.accessLevelField
        };
        fields.addAll(shareInfo.secondaryAccessLevelFields);

        String query =
            'SELECT ' +
            String.join(new List<String>(fields), ', ') +
            ' FROM ' +
            String.escapeSingleQuotes(shareInfo.shareObjectApiName) +
            ' WHERE ' +
            String.escapeSingleQuotes(shareInfo.parentField) +
            ' = :recordId';
        try {
            return Database.query(query);
        } catch (System.QueryException e) {
            return new List<SObject>();
        }
    }

    /**
     * There is no supported Schema.SharingModel / getSharingModel() API (verified against a live
     * org: no such method exists on DescribeSObjectResult), so "controlled by parent" is instead
     * detected the officially documented way: a master-detail relationship is any reference field
     * where DescribeFieldResult.isCascadeDelete() is true - Salesforce enforces ControlledByParent
     * sharing unconditionally for any object that has one. When an object has two master-detail
     * fields (a many-to-many junction), the field with relationshipOrder 0 is the sharing-controlling
     * one; relationshipOrder is not populated for a single master-detail field, so it is only used
     * as a tie-breaker, never as the primary signal.
     */
    private String findControllingParentField(Map<String, Schema.SObjectField> fieldMap) {
        String firstCascadeField;
        for (Schema.SObjectField field : fieldMap.values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            if (fieldDescribe.getType() != Schema.DisplayType.REFERENCE || !fieldDescribe.isCascadeDelete()) {
                continue;
            }
            if (fieldDescribe.getRelationshipOrder() != null && fieldDescribe.getRelationshipOrder() == 0) {
                return fieldDescribe.getName();
            }
            if (firstCascadeField == null) {
                firstCascadeField = fieldDescribe.getName();
            }
        }
        return firstCascadeField;
    }
}
