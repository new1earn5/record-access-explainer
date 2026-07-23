/**
 * Sole Aura-enabled entry point for the Record Access Explainer LWC. Declared with sharing:
 * every method first verifies the RAA_Run_Record_Access_Analysis custom permission, then - for
 * anything that reads or mutates a specific package-owned record (analysis, bulk run,
 * subscription) - re-confirms the running user can see that specific row under normal Salesforce
 * record-level sharing (Private OWD, so by default only the requester, an admin, or someone the
 * record was explicitly shared with) before delegating to the elevated
 * RAA_AnalysisOrchestratorService. This two-layer check is what prevents an operator from
 * requesting or reading data that is not theirs, even though the underlying scan and persistence
 * layers run in system mode for completeness.
 *
 * No method here ever returns a raw exception message from an unexpected failure - only
 * sanitized, user-safe text.
 */
public with sharing class RAA_RecordAccessExplainerController {
    @AuraEnabled(cacheable=true)
    public static Boolean hasRunPermission() {
        return RAA_PermissionChecker.hasRunPermission();
    }

    @AuraEnabled(cacheable=true)
    public static RAA_SettingsDTO getDefaultSettings() {
        enforceRunPermission();
        return new RAA_SettingsDTO(new RAA_SettingsService());
    }

    @AuraEnabled
    public static RAA_AnalysisSummaryDTO startAnalysis(RAA_AnalysisRequestDTO request) {
        enforceRunPermission();
        try {
            return new RAA_AnalysisOrchestratorService().startAnalysis(request, UserInfo.getUserId());
        } catch (RAA_AppException e) {
            throw toAuraException(e.getMessage());
        } catch (Exception e) {
            throw toAuraException(genericErrorMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static RAA_AnalysisSummaryDTO getAnalysisStatus(String analysisId) {
        enforceRunPermission();
        Id normalizedId = normalizeAndCheckVisibility(analysisId);
        try {
            return new RAA_AnalysisOrchestratorService().getStatus(normalizedId);
        } catch (RAA_AppException e) {
            throw toAuraException(e.getMessage());
        } catch (Exception e) {
            throw toAuraException(genericErrorMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<RAA_AccessResultDTO> getResults(String analysisId) {
        enforceRunPermission();
        Id normalizedId = normalizeAndCheckVisibility(analysisId);
        try {
            return new RAA_AnalysisOrchestratorService().getResults(normalizedId);
        } catch (RAA_AppException e) {
            throw toAuraException(e.getMessage());
        } catch (Exception e) {
            throw toAuraException(genericErrorMessage());
        }
    }

    @AuraEnabled
    public static RAA_AnalysisSummaryDTO cancelAnalysis(String analysisId) {
        enforceRunPermission();
        Id normalizedId = normalizeAndCheckVisibility(analysisId);
        try {
            return new RAA_AnalysisOrchestratorService().cancelAnalysis(normalizedId);
        } catch (RAA_AppException e) {
            throw toAuraException(e.getMessage());
        } catch (Exception e) {
            throw toAuraException(genericErrorMessage());
        }
    }

    @AuraEnabled
    public static void deleteAnalysis(String analysisId) {
        enforceRunPermission();
        Id normalizedId = normalizeAndCheckVisibility(analysisId);
        try {
            new RAA_AnalysisOrchestratorService().deleteAnalysis(normalizedId);
        } catch (RAA_AppException e) {
            throw toAuraException(e.getMessage());
        } catch (Exception e) {
            throw toAuraException(genericErrorMessage());
        }
    }

    @AuraEnabled
    public static String exportResultsCsv(String analysisId) {
        enforceRunPermission();
        Id normalizedId = normalizeAndCheckVisibility(analysisId);
        try {
            List<RAA_AccessResultDTO> results = new RAA_AnalysisOrchestratorService().getResults(normalizedId);
            return new RAA_CsvExportService().buildResultsCsv(results);
        } catch (RAA_AppException e) {
            throw toAuraException(e.getMessage());
        } catch (Exception e) {
            throw toAuraException(genericErrorMessage());
        }
    }

    @AuraEnabled
    public static String exportReasonsCsv(String analysisId) {
        enforceRunPermission();
        Id normalizedId = normalizeAndCheckVisibility(analysisId);
        try {
            List<RAA_AccessResultDTO> results = new RAA_AnalysisOrchestratorService().getResults(normalizedId);
            return new RAA_CsvExportService().buildReasonsCsv(results);
        } catch (RAA_AppException e) {
            throw toAuraException(e.getMessage());
        } catch (Exception e) {
            throw toAuraException(genericErrorMessage());
        }
    }

    /** Feature: analysis history / diffing. */
    @AuraEnabled(cacheable=true)
    public static RAA_AnalysisDiffDTO getAnalysisDiff(String analysisId) {
        enforceRunPermission();
        Id normalizedId = normalizeAndCheckVisibility(analysisId);
        try {
            return new RAA_AnalysisOrchestratorService().getDiffAgainstPrevious(normalizedId);
        } catch (RAA_AppException e) {
            throw toAuraException(e.getMessage());
        } catch (Exception e) {
            throw toAuraException(genericErrorMessage());
        }
    }

    /** Feature: bulk scan mode. */
    @AuraEnabled
    public static RAA_BatchRunSummaryDTO startBulkAnalysis(
        List<String> recordIds,
        Boolean includeExternalUsers,
        Boolean includeInactiveUsers
    ) {
        enforceRunPermission();
        try {
            return new RAA_AnalysisOrchestratorService()
                .startBulkAnalysis(recordIds, includeExternalUsers, includeInactiveUsers, UserInfo.getUserId());
        } catch (RAA_AppException e) {
            throw toAuraException(e.getMessage());
        } catch (Exception e) {
            throw toAuraException(genericErrorMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static RAA_BatchRunSummaryDTO getBatchRunStatus(String batchRunId) {
        enforceRunPermission();
        Id normalizedId = normalizeAndCheckBatchRunVisibility(batchRunId);
        try {
            return new RAA_AnalysisOrchestratorService().getBatchRunStatus(normalizedId);
        } catch (RAA_AppException e) {
            throw toAuraException(e.getMessage());
        } catch (Exception e) {
            throw toAuraException(genericErrorMessage());
        }
    }

    /** Feature: field-level security tracing. */
    @AuraEnabled(cacheable=true)
    public static List<RAA_FieldAccessDTO> getFieldAccess(String userId, String objectApiName) {
        enforceRunPermission();
        Id normalizedUserId = normalizeUserId(userId);
        try {
            return new RAA_AnalysisOrchestratorService().getFieldAccess(normalizedUserId, objectApiName);
        } catch (RAA_AppException e) {
            throw toAuraException(e.getMessage());
        } catch (Exception e) {
            throw toAuraException(genericErrorMessage());
        }
    }

    /** Feature: reverse mode ("by user"). */
    @AuraEnabled
    public static List<RAA_UserRecordAccessSummaryDTO> scanUserAccess(
        String userId,
        String objectApiName,
        List<String> recordIds,
        Integer limitCount
    ) {
        enforceRunPermission();
        Id normalizedUserId = normalizeUserId(userId);
        try {
            return new RAA_AnalysisOrchestratorService()
                .scanUserAccess(normalizedUserId, objectApiName, recordIds, limitCount);
        } catch (RAA_AppException e) {
            throw toAuraException(e.getMessage());
        } catch (Exception e) {
            throw toAuraException(genericErrorMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<RAA_AccessReasonDTO> getUserAccessReasons(String userId, String recordId) {
        enforceRunPermission();
        Id normalizedUserId = normalizeUserId(userId);
        Id normalizedRecordId = RAA_IdValidationUtil.normalizeRecordId(recordId);
        try {
            return new RAA_AnalysisOrchestratorService().getUserAccessReasons(normalizedUserId, normalizedRecordId);
        } catch (RAA_AppException e) {
            throw toAuraException(e.getMessage());
        } catch (Exception e) {
            throw toAuraException(genericErrorMessage());
        }
    }

    /** Feature: recurring scans / change alerts. */
    @AuraEnabled
    public static String createSubscription(
        String recordId,
        Boolean includeExternalUsers,
        Boolean includeInactiveUsers,
        Boolean notifyOnChange
    ) {
        enforceRunPermission();
        try {
            return new RAA_AnalysisOrchestratorService()
                .createSubscription(
                    recordId,
                    includeExternalUsers,
                    includeInactiveUsers,
                    notifyOnChange,
                    UserInfo.getUserId()
                );
        } catch (RAA_AppException e) {
            throw toAuraException(e.getMessage());
        } catch (Exception e) {
            throw toAuraException(genericErrorMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<RAA_SubscriptionDTO> listMySubscriptions() {
        enforceRunPermission();
        try {
            return new RAA_AnalysisOrchestratorService().listMySubscriptions(UserInfo.getUserId());
        } catch (Exception e) {
            throw toAuraException(genericErrorMessage());
        }
    }

    @AuraEnabled
    public static void setSubscriptionActive(String subscriptionId, Boolean isActive) {
        enforceRunPermission();
        Id normalizedId = normalizeAndCheckSubscriptionVisibility(subscriptionId);
        try {
            new RAA_AnalysisOrchestratorService().setSubscriptionActive(normalizedId, isActive);
        } catch (Exception e) {
            throw toAuraException(genericErrorMessage());
        }
    }

    @AuraEnabled
    public static void deleteSubscription(String subscriptionId) {
        enforceRunPermission();
        Id normalizedId = normalizeAndCheckSubscriptionVisibility(subscriptionId);
        try {
            new RAA_AnalysisOrchestratorService().deleteSubscription(normalizedId);
        } catch (Exception e) {
            throw toAuraException(genericErrorMessage());
        }
    }

    private static void enforceRunPermission() {
        if (!RAA_PermissionChecker.hasRunPermission()) {
            throw toAuraException(
                'You do not have permission to use Record Access Explainer. Ask your administrator to assign the RAA Record Access Auditor permission set.'
            );
        }
    }

    /** Validates the ID shape and confirms the running user can see this specific analysis under normal record sharing. */
    private static Id normalizeAndCheckVisibility(String rawAnalysisId) {
        Id analysisId;
        try {
            analysisId = RAA_IdValidationUtil.normalizeAnalysisId(rawAnalysisId);
        } catch (RAA_AppException e) {
            throw toAuraException(e.getMessage());
        }
        List<RAA_Analysis__c> visible = [SELECT Id FROM RAA_Analysis__c WHERE Id = :analysisId LIMIT 1];
        if (visible.isEmpty()) {
            throw toAuraException('The requested analysis could not be found, or you do not have access to it.');
        }
        return analysisId;
    }

    private static Id normalizeAndCheckBatchRunVisibility(String rawBatchRunId) {
        Id batchRunId;
        try {
            batchRunId = RAA_IdValidationUtil.normalizeRecordId(rawBatchRunId);
        } catch (RAA_AppException e) {
            throw toAuraException(e.getMessage());
        }
        if (batchRunId.getSObjectType() != RAA_Batch_Run__c.SObjectType) {
            throw toAuraException('The supplied ID does not refer to an RAA Batch Run record.');
        }
        List<RAA_Batch_Run__c> visible = [SELECT Id FROM RAA_Batch_Run__c WHERE Id = :batchRunId LIMIT 1];
        if (visible.isEmpty()) {
            throw toAuraException('The requested bulk run could not be found, or you do not have access to it.');
        }
        return batchRunId;
    }

    private static Id normalizeAndCheckSubscriptionVisibility(String rawSubscriptionId) {
        Id subscriptionId;
        try {
            subscriptionId = RAA_IdValidationUtil.normalizeRecordId(rawSubscriptionId);
        } catch (RAA_AppException e) {
            throw toAuraException(e.getMessage());
        }
        if (subscriptionId.getSObjectType() != RAA_Scan_Subscription__c.SObjectType) {
            throw toAuraException('The supplied ID does not refer to an RAA Scan Subscription record.');
        }
        List<RAA_Scan_Subscription__c> visible = [
            SELECT Id
            FROM RAA_Scan_Subscription__c
            WHERE Id = :subscriptionId
            LIMIT 1
        ];
        if (visible.isEmpty()) {
            throw toAuraException('The requested subscription could not be found, or you do not have access to it.');
        }
        return subscriptionId;
    }

    private static Id normalizeUserId(String rawUserId) {
        Id userId;
        try {
            userId = RAA_IdValidationUtil.normalizeRecordId(rawUserId);
        } catch (RAA_AppException e) {
            throw toAuraException(e.getMessage());
        }
        if (userId.getSObjectType() != User.SObjectType) {
            throw toAuraException('The supplied ID does not refer to a User record.');
        }
        return userId;
    }

    private static String genericErrorMessage() {
        return 'An unexpected error occurred while processing your request. Please try again, and contact your administrator if the problem continues.';
    }

    private static AuraHandledException toAuraException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}
