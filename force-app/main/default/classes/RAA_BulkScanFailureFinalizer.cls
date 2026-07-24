/**
 * Attached to RAA_BulkScanQueueable so a single catastrophic, uncaught exception (a heap or CPU
 * limit hit mid-loop, for example - something outside the per-record try/catch in execute()) can
 * never leave a batch run permanently stuck showing fewer child analyses than RAA_Total_Records__c
 * with no explanation. On an unhandled exception, every record in this queueable's chunk that
 * doesn't already have an analysis row is stub-failed, so the batch run's computed status (see
 * RAA_AnalysisRepository.refreshAndGetBatchRunStatus) always reaches a terminal state.
 *
 * The recovery logic is split into recoverIncompleteRecords() so it can be unit tested directly -
 * System.FinalizerContext has no public constructor, so execute() itself can only be exercised by
 * the real platform mechanism (a genuinely unhandled exception during a Queueable under test).
 */
public without sharing class RAA_BulkScanFailureFinalizer implements System.Finalizer {
    private final Id batchRunId;
    private final List<Id> recordIdsInScope;
    private final Id requestingUserId;
    private final Boolean includeExternalUsers;
    private final Boolean includeInactiveUsers;

    public RAA_BulkScanFailureFinalizer(
        Id batchRunId,
        List<Id> recordIdsInScope,
        Id requestingUserId,
        Boolean includeExternalUsers,
        Boolean includeInactiveUsers
    ) {
        this.batchRunId = batchRunId;
        this.recordIdsInScope = recordIdsInScope;
        this.requestingUserId = requestingUserId;
        this.includeExternalUsers = includeExternalUsers;
        this.includeInactiveUsers = includeInactiveUsers;
    }

    public void execute(System.FinalizerContext ctx) {
        if (ctx.getResult() != System.ParentJobResult.UNHANDLED_EXCEPTION) {
            return;
        }
        Exception unhandled = ctx.getException();
        recoverIncompleteRecords(unhandled != null ? unhandled.getMessage() : 'unknown error');
    }

    @TestVisible
    private void recoverIncompleteRecords(String errorDetail) {
        if (batchRunId == null || recordIdsInScope == null || recordIdsInScope.isEmpty()) {
            return;
        }

        RAA_AnalysisRepository repository = new RAA_AnalysisRepository();
        Set<Id> alreadyRecorded = new Set<Id>();
        for (RAA_Analysis__c analysis : repository.getAnalysesForBatchRun(batchRunId)) {
            alreadyRecorded.add((Id) analysis.RAA_Record_Id__c);
        }

        for (Id recordId : recordIdsInScope) {
            if (alreadyRecorded.contains(recordId)) {
                continue;
            }
            Id stubAnalysisId = repository.createAnalysis(
                recordId,
                'Unknown',
                String.valueOf(recordId),
                requestingUserId,
                includeExternalUsers,
                includeInactiveUsers,
                batchRunId
            );
            repository.markFailed(
                stubAnalysisId,
                'The scan for this record did not complete because the bulk run hit an unexpected platform error (' +
                    errorDetail +
                    ').'
            );
        }
    }
}
