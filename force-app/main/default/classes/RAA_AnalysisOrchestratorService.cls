/**
 * Elevated service boundary for Record Access Explainer. This is the only class the Aura-enabled
 * controller talks to for mutating or cross-user operations; it is never itself directly
 * Aura-enabled. Every public method assumes the caller (RAA_RecordAccessExplainerController) has
 * already verified the RAA_Run_Record_Access_Analysis custom permission.
 */
public without sharing class RAA_AnalysisOrchestratorService {
    private final RAA_AnalysisRepository repository;
    private final RAA_RecordMetadataResolver metadataResolver;
    private final RAA_SettingsService settings;

    public RAA_AnalysisOrchestratorService() {
        this.repository = new RAA_AnalysisRepository();
        this.metadataResolver = new RAA_RecordMetadataResolver();
        this.settings = new RAA_SettingsService();
    }

    public RAA_AnalysisSummaryDTO startAnalysis(RAA_AnalysisRequestDTO request, Id requestingUserId) {
        Id recordId = RAA_IdValidationUtil.normalizeRecordId(request.recordId);

        RAA_RecordMetadataResolver.ResolvedRecord resolved = metadataResolver.resolve(recordId);
        if (!metadataResolver.supportsUserRecordAccess(recordId)) {
            throw new RAA_AppException(
                'Salesforce does not expose UserRecordAccess for ' +
                    resolved.objectApiName +
                    ' records in this org, so this object is not supported by Record Access Explainer.'
            );
        }

        RAA_Analysis__c existing = repository.findActiveAnalysisForRecord(recordId);
        if (existing != null && request.confirmDuplicateScan != true) {
            throw new RAA_AppException(
                'An analysis for this record is already ' +
                    existing.RAA_Status__c.toLowerCase() +
                    ' (requested ' +
                    existing.RAA_Requested_At__c.format() +
                    '). Confirm to start a new scan anyway.'
            );
        }

        Boolean includeExternal = request.includeExternalUsers != null
            ? request.includeExternalUsers
            : settings.defaultIncludeExternal;
        Boolean includeInactive = request.includeInactiveUsers != null
            ? request.includeInactiveUsers
            : settings.defaultIncludeInactive;

        Id analysisId = repository.createAnalysis(
            recordId,
            resolved.objectApiName,
            resolved.displayName,
            requestingUserId,
            includeExternal,
            includeInactive
        );

        RAA_UserPopulationBuilder.PopulationFilter filter = new RAA_UserPopulationBuilder.PopulationFilter();
        filter.includeExternalUsers = includeExternal;
        filter.includeInactiveUsers = includeInactive;
        filter.profileNames = request.profileNames != null ? request.profileNames : new List<String>();
        filter.userTypes = request.userTypes != null ? request.userTypes : new List<String>();
        filter.permissionSetNames = request.permissionSetNames != null
            ? request.permissionSetNames
            : new List<String>();

        RAA_AccessScanBatch batch = new RAA_AccessScanBatch(analysisId, recordId, filter);
        Database.executeBatch(batch, settings.defaultBatchScope);

        return new RAA_AnalysisSummaryDTO(repository.getAnalysis(analysisId));
    }

    public RAA_AnalysisSummaryDTO getStatus(Id analysisId) {
        RAA_Analysis__c analysis = repository.getAnalysis(analysisId);
        if (analysis == null) {
            throw new RAA_AppException('The requested analysis could not be found, or you do not have access to it.');
        }
        return new RAA_AnalysisSummaryDTO(analysis);
    }

    public List<RAA_AccessResultDTO> getResults(Id analysisId) {
        if (repository.getAnalysis(analysisId) == null) {
            throw new RAA_AppException('The requested analysis could not be found, or you do not have access to it.');
        }
        List<RAA_AccessResultDTO> dtos = new List<RAA_AccessResultDTO>();
        for (RAA_Access_Result__c row : repository.getResultsWithReasons(analysisId)) {
            RAA_AccessResultDTO dto = new RAA_AccessResultDTO(row);
            for (RAA_Access_Reason__c reason : row.RAA_Access_Reasons__r) {
                dto.reasons.add(new RAA_AccessReasonDTO(reason));
            }
            dtos.add(dto);
        }
        return dtos;
    }

    // The empty catch below (System.abortJob) is deliberate: see its own inline comment.
    @SuppressWarnings('PMD.EmptyCatchBlock')
    public RAA_AnalysisSummaryDTO cancelAnalysis(Id analysisId) {
        RAA_Analysis__c analysis = repository.getAnalysis(analysisId);
        if (analysis == null) {
            throw new RAA_AppException('The requested analysis could not be found, or you do not have access to it.');
        }
        if (analysis.RAA_Is_Complete__c) {
            throw new RAA_AppException('This analysis has already finished and cannot be cancelled.');
        }
        if (String.isNotBlank(analysis.RAA_Async_Job_Id__c)) {
            try {
                System.abortJob(analysis.RAA_Async_Job_Id__c);
            } catch (Exception e) {
                // The job may already be complete or aborted; still mark the analysis cancelled below.
            }
        }
        repository.markCancelled(analysisId);
        return new RAA_AnalysisSummaryDTO(repository.getAnalysis(analysisId));
    }

    public void deleteAnalysis(Id analysisId) {
        if (repository.getAnalysis(analysisId) == null) {
            throw new RAA_AppException('The requested analysis could not be found, or you do not have access to it.');
        }
        repository.deleteAnalysis(analysisId);
    }

    /** Feature: analysis history / diffing. Compares an analysis against the previous completed run of the same record. */
    public RAA_AnalysisDiffDTO getDiffAgainstPrevious(Id analysisId) {
        return new RAA_AnalysisDiffService(repository).compareToPreviousAnalysis(analysisId);
    }

    /** Feature: bulk scan mode. Starts one scan per record, all of the same object type. */
    public RAA_BatchRunSummaryDTO startBulkAnalysis(
        List<String> rawRecordIds,
        Boolean includeExternalUsers,
        Boolean includeInactiveUsers,
        Id requestingUserId
    ) {
        if (rawRecordIds == null || rawRecordIds.isEmpty()) {
            throw new RAA_AppException('Enter at least one record ID for a bulk scan.');
        }

        List<Id> recordIds = new List<Id>();
        Schema.SObjectType sharedType;
        for (String raw : rawRecordIds) {
            Id normalized = RAA_IdValidationUtil.normalizeRecordId(raw);
            if (sharedType == null) {
                sharedType = normalized.getSObjectType();
            } else if (normalized.getSObjectType() != sharedType) {
                throw new RAA_AppException('All records in a bulk scan must be the same object type.');
            }
            recordIds.add(normalized);
        }

        if (recordIds.size() > settings.maxRecordsPerBulkRun && settings.maxRecordsPerBulkRun > 0) {
            throw new RAA_AppException(
                'This bulk scan would include ' +
                    recordIds.size() +
                    ' records, which exceeds the ' +
                    'configured maximum of ' +
                    settings.maxRecordsPerBulkRun +
                    ' in RAA Settings.'
            );
        }

        Boolean includeExternal = includeExternalUsers != null ? includeExternalUsers : settings.defaultIncludeExternal;
        Boolean includeInactive = includeInactiveUsers != null ? includeInactiveUsers : settings.defaultIncludeInactive;

        // DEFERRED skips eagerly loading child-relationship metadata, which nothing here reads.
        String objectApiName = sharedType.getDescribe(Schema.SObjectDescribeOptions.DEFERRED).getName();
        Id batchRunId = repository.createBatchRun(
            objectApiName,
            recordIds.size(),
            String.join(rawRecordIds, '\n'),
            requestingUserId,
            includeExternal,
            includeInactive
        );

        System.enqueueJob(
            new RAA_BulkScanQueueable(recordIds, batchRunId, requestingUserId, includeExternal, includeInactive)
        );

        return new RAA_BatchRunSummaryDTO(repository.getBatchRun(batchRunId), new List<RAA_Analysis__c>());
    }

    public RAA_BatchRunSummaryDTO getBatchRunStatus(Id batchRunId) {
        RAA_Batch_Run__c run = repository.refreshAndGetBatchRunStatus(batchRunId);
        if (run == null) {
            throw new RAA_AppException('The requested bulk run could not be found, or you do not have access to it.');
        }
        return new RAA_BatchRunSummaryDTO(run, repository.getAnalysesForBatchRun(batchRunId));
    }

    /** Feature: field-level security tracing. */
    public List<RAA_FieldAccessDTO> getFieldAccess(Id userId, String objectApiName) {
        return new RAA_FieldAccessService().getFieldAccess(userId, objectApiName);
    }

    /** Feature: reverse mode ("by user") - effective access for one user across a candidate set of records. */
    public List<RAA_UserRecordAccessSummaryDTO> scanUserAccess(
        Id userId,
        String objectApiName,
        List<String> rawRecordIds,
        Integer limitCount
    ) {
        RAA_UserAccessExplorerService explorer = new RAA_UserAccessExplorerService();
        List<Id> candidateIds = resolveCandidateRecordIds(objectApiName, rawRecordIds, limitCount);
        return explorer.scanUserAcrossRecords(userId, objectApiName, candidateIds);
    }

    public List<RAA_AccessReasonDTO> getUserAccessReasons(Id userId, Id recordId) {
        return new RAA_UserAccessExplorerService().getAccessReasons(userId, recordId);
    }

    // The object name concatenated into the dynamic query below is the resolved SObjectType's
    // own canonical getDescribe().getName() - never the raw client-supplied objectApiName
    // string directly - so an unrecognized object name is rejected by the null check above
    // before any query is built, not smuggled through. DEFERRED already skips eagerly loading
    // child-relationship metadata that nothing here reads.
    @SuppressWarnings('PMD.ApexSOQLInjection,PMD.EagerlyLoadedDescribeSObjectResult')
    private List<Id> resolveCandidateRecordIds(String objectApiName, List<String> rawRecordIds, Integer limitCount) {
        List<Id> candidateIds = new List<Id>();
        if (rawRecordIds != null && !rawRecordIds.isEmpty()) {
            for (String raw : rawRecordIds) {
                candidateIds.add(RAA_IdValidationUtil.normalizeRecordId(raw));
            }
        } else {
            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
            if (sObjectType == null) {
                throw new RAA_AppException('"' + objectApiName + '" is not a recognized object.');
            }
            Integer effectiveLimit = limitCount != null && limitCount > 0 ? limitCount : settings.maxRecordsPerUserScan;
            // DEFERRED skips eagerly loading child-relationship metadata, which nothing here reads.
            for (
                SObject record : Database.query(
                    'SELECT Id FROM ' +
                        String.escapeSingleQuotes(
                            sObjectType.getDescribe(Schema.SObjectDescribeOptions.DEFERRED).getName()
                        ) +
                        ' LIMIT :effectiveLimit'
                )
            ) {
                candidateIds.add(record.Id);
            }
        }

        if (settings.maxRecordsPerUserScan > 0 && candidateIds.size() > settings.maxRecordsPerUserScan) {
            throw new RAA_AppException(
                'This scan would check ' +
                    candidateIds.size() +
                    ' records, which exceeds the ' +
                    'configured maximum of ' +
                    settings.maxRecordsPerUserScan +
                    ' in RAA Settings.'
            );
        }
        return candidateIds;
    }

    /** Feature: recurring scans / change alerts. */
    public Id createSubscription(
        String rawRecordId,
        Boolean includeExternalUsers,
        Boolean includeInactiveUsers,
        Boolean notifyOnChange,
        Boolean postToChatter,
        Id subscriberId
    ) {
        Id recordId = RAA_IdValidationUtil.normalizeRecordId(rawRecordId);
        RAA_RecordMetadataResolver.ResolvedRecord resolved = metadataResolver.resolve(recordId);
        return new RAA_SubscriptionRepository()
            .createSubscription(
                recordId,
                resolved.objectApiName,
                resolved.displayName,
                subscriberId,
                includeExternalUsers == true,
                includeInactiveUsers == true,
                notifyOnChange != false,
                postToChatter == true
            );
    }

    public List<RAA_SubscriptionDTO> listMySubscriptions(Id subscriberId) {
        List<RAA_SubscriptionDTO> dtos = new List<RAA_SubscriptionDTO>();
        for (
            RAA_Scan_Subscription__c subscription : new RAA_SubscriptionRepository()
                .getSubscriptionsForUser(subscriberId)
        ) {
            dtos.add(new RAA_SubscriptionDTO(subscription));
        }
        return dtos;
    }

    public void setSubscriptionActive(Id subscriptionId, Boolean isActive) {
        new RAA_SubscriptionRepository().setActive(subscriptionId, isActive);
    }

    public void deleteSubscription(Id subscriptionId) {
        new RAA_SubscriptionRepository().deleteSubscription(subscriptionId);
    }

    /** Feature: Risk Insights - ranks the requesting user's own already-scanned records. */
    public List<RAA_RiskInsightDTO> getRiskInsights(Id requestedById) {
        return new RAA_RiskInsightsService().getRiskInsights(requestedById);
    }
}
