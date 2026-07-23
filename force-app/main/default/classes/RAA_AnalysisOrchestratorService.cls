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
            throw new RAA_AppException('Salesforce does not expose UserRecordAccess for ' + resolved.objectApiName
                    + ' records in this org, so this object is not supported by Record Access Explainer.');
        }

        RAA_Analysis__c existing = repository.findActiveAnalysisForRecord(recordId);
        if (existing != null && request.confirmDuplicateScan != true) {
            throw new RAA_AppException('An analysis for this record is already ' + existing.RAA_Status__c.toLowerCase()
                    + ' (requested ' + existing.RAA_Requested_At__c.format() + '). Confirm to start a new scan anyway.');
        }

        Boolean includeExternal = request.includeExternalUsers != null ? request.includeExternalUsers : settings.defaultIncludeExternal;
        Boolean includeInactive = request.includeInactiveUsers != null ? request.includeInactiveUsers : settings.defaultIncludeInactive;

        Id analysisId = repository.createAnalysis(recordId, resolved.objectApiName, resolved.displayName,
                requestingUserId, includeExternal, includeInactive);

        RAA_UserPopulationBuilder.PopulationFilter filter = new RAA_UserPopulationBuilder.PopulationFilter();
        filter.includeExternalUsers = includeExternal;
        filter.includeInactiveUsers = includeInactive;
        filter.profileNames = request.profileNames != null ? request.profileNames : new List<String>();
        filter.userTypes = request.userTypes != null ? request.userTypes : new List<String>();
        filter.permissionSetNames = request.permissionSetNames != null ? request.permissionSetNames : new List<String>();

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
}
