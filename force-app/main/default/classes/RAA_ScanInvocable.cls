/**
 * Flow-callable entry point for starting a Record Access Explainer scan. Mirrors
 * RAA_RecordAccessExplainerController.startAnalysis's permission check and delegation to
 * RAA_AnalysisOrchestratorService, but reports failures on the Result object instead of
 * throwing, since a faulted Flow interview is a heavier failure mode than a single bad input -
 * exactly the same reasoning that makes @InvocableMethod actions report errors this way instead
 * of raising exceptions. Starting a scan is inherently asynchronous (it enqueues a batch job),
 * so this returns Queued/Running status immediately - it cannot return final results in the same
 * transaction. Use RAA_ScanRestResource's GET endpoint, or a Flow polling pattern against
 * RAA_Analysis__c, to retrieve results once complete.
 */
public with sharing class RAA_ScanInvocable {
    public class Request {
        @InvocableVariable(
            required=true
            label='Record ID'
            description='The 15 or 18 character ID of the record to scan.'
        )
        public String recordId;
        @InvocableVariable(label='Include Active External / Experience Cloud Users')
        public Boolean includeExternalUsers;
        @InvocableVariable(label='Include Inactive Users')
        public Boolean includeInactiveUsers;
    }

    public class Result {
        @InvocableVariable(label='Analysis ID')
        public String analysisId;
        @InvocableVariable(label='Status')
        public String status;
        @InvocableVariable(label='Is Success')
        public Boolean isSuccess;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Start Record Access Scan'
        description='Starts a Record Access Explainer scan for a record and returns its analysis ID and initial status. Requires the RAA_Run_Record_Access_Analysis custom permission.'
        category='Record Access Explainer'
    )
    public static List<Result> startScan(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request request : requests) {
            results.add(startOne(request));
        }
        return results;
    }

    private static Result startOne(Request request) {
        Result result = new Result();
        try {
            if (!RAA_PermissionChecker.hasRunPermission()) {
                throw new RAA_AppException(
                    'You do not have permission to use Record Access Explainer. Ask your administrator to assign the RAA Record Access Auditor permission set.'
                );
            }
            RAA_AnalysisRequestDTO dto = new RAA_AnalysisRequestDTO();
            dto.recordId = request.recordId;
            dto.includeExternalUsers = request.includeExternalUsers;
            dto.includeInactiveUsers = request.includeInactiveUsers;

            RAA_AnalysisSummaryDTO summary = new RAA_AnalysisOrchestratorService()
                .startAnalysis(dto, UserInfo.getUserId());
            result.analysisId = summary.analysisId;
            result.status = summary.status;
            result.isSuccess = true;
        } catch (RAA_AppException e) {
            result.isSuccess = false;
            result.errorMessage = e.getMessage();
        } catch (Exception e) {
            result.isSuccess = false;
            result.errorMessage = 'An unexpected error occurred while starting the scan.';
        }
        return result;
    }
}
