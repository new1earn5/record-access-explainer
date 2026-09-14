/**
 * REST entry point for external systems (a SIEM, a scheduled compliance job, etc.) that need to
 * trigger or poll a Record Access Explainer scan without going through the LWC. Mirrors
 * RAA_RecordAccessExplainerController's permission check and per-record visibility check - an
 * external caller gets exactly the same two-layer guarantee the UI does, not less, even though
 * this bypasses Aura entirely.
 *
 * POST /services/apexrest/RecordAccessScan/            - body: {"recordId": "...", "includeExternalUsers": bool, "includeInactiveUsers": bool}
 * GET  /services/apexrest/RecordAccessScan/{analysisId} - returns current status/results summary
 */
@RestResource(urlMapping='/RecordAccessScan/*')
global with sharing class RAA_ScanRestResource {
    global class ScanRequestBody {
        public String recordId;
        public Boolean includeExternalUsers;
        public Boolean includeInactiveUsers;
    }

    global class ScanResponseBody {
        public String analysisId;
        public String status;
        public String errorMessage;
    }

    @HttpPost
    global static void startScan() {
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');
        ScanResponseBody body = new ScanResponseBody();
        try {
            if (!RAA_PermissionChecker.hasRunPermission()) {
                respond(response, 403, errorBody(body, 'You do not have permission to use Record Access Explainer.'));
                return;
            }

            ScanRequestBody requestBody = (ScanRequestBody) JSON.deserialize(
                RestContext.request.requestBody.toString(),
                ScanRequestBody.class
            );

            RAA_AnalysisRequestDTO dto = new RAA_AnalysisRequestDTO();
            dto.recordId = requestBody.recordId;
            dto.includeExternalUsers = requestBody.includeExternalUsers;
            dto.includeInactiveUsers = requestBody.includeInactiveUsers;

            RAA_AnalysisSummaryDTO summary = new RAA_AnalysisOrchestratorService()
                .startAnalysis(dto, UserInfo.getUserId());
            body.analysisId = summary.analysisId;
            body.status = summary.status;
            respond(response, 201, body);
        } catch (RAA_AppException e) {
            respond(response, 400, errorBody(body, e.getMessage()));
        } catch (Exception e) {
            respond(response, 500, errorBody(body, 'An unexpected error occurred while starting the scan.'));
        }
    }

    @HttpGet
    global static void getScanStatus() {
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');
        ScanResponseBody body = new ScanResponseBody();
        try {
            if (!RAA_PermissionChecker.hasRunPermission()) {
                respond(response, 403, errorBody(body, 'You do not have permission to use Record Access Explainer.'));
                return;
            }

            String rawAnalysisId = analysisIdFromUri(RestContext.request.requestURI);
            Id analysisId = RAA_IdValidationUtil.normalizeAnalysisId(rawAnalysisId);
            List<RAA_Analysis__c> visible = [
                SELECT Id
                FROM RAA_Analysis__c
                WHERE Id = :analysisId
                WITH USER_MODE
                LIMIT 1
            ];
            if (visible.isEmpty()) {
                respond(
                    response,
                    404,
                    errorBody(body, 'The requested analysis could not be found, or you do not have access to it.')
                );
                return;
            }

            RAA_AnalysisSummaryDTO summary = new RAA_AnalysisOrchestratorService().getStatus(analysisId);
            body.analysisId = summary.analysisId;
            body.status = summary.status;
            respond(response, 200, body);
        } catch (RAA_AppException e) {
            respond(response, 400, errorBody(body, e.getMessage()));
        } catch (Exception e) {
            respond(response, 500, errorBody(body, 'An unexpected error occurred while retrieving scan status.'));
        }
    }

    private static String analysisIdFromUri(String requestUri) {
        List<String> parts = requestUri.split('/');
        return parts.isEmpty() ? null : parts[parts.size() - 1];
    }

    private static ScanResponseBody errorBody(ScanResponseBody body, String message) {
        body.errorMessage = message;
        return body;
    }

    private static void respond(RestResponse response, Integer statusCode, ScanResponseBody body) {
        response.statusCode = statusCode;
        response.responseBody = Blob.valueOf(JSON.serialize(body));
    }
}
