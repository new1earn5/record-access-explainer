/**
 * Sole Aura-enabled entry point for the Record Access Explainer LWC. Declared with sharing:
 * every method first verifies the RAA_Run_Record_Access_Analysis custom permission, then - for
 * anything that reads or mutates a specific analysis - re-confirms the running user can see that
 * specific RAA_Analysis__c row under normal Salesforce record-level sharing (Private OWD, so by
 * default only the requester, an admin, or someone the record was explicitly shared with) before
 * delegating to the elevated RAA_AnalysisOrchestratorService. This two-layer check is what
 * prevents an operator from requesting or reading analyses that are not theirs, even though the
 * underlying scan and persistence layers run in system mode for completeness.
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

    private static void enforceRunPermission() {
        if (!RAA_PermissionChecker.hasRunPermission()) {
            throw toAuraException('You do not have permission to use Record Access Explainer. Ask your administrator to assign the RAA Record Access Auditor permission set.');
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

    private static String genericErrorMessage() {
        return 'An unexpected error occurred while processing your request. Please try again, and contact your administrator if the problem continues.';
    }

    private static AuraHandledException toAuraException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}
