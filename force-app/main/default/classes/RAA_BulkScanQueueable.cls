/**
 * Dispatches one RAA_AccessScanBatch per record in a bulk scan request, in chunks of at most
 * CHUNK_SIZE per execute() - a single Apex transaction can call Database.executeBatch at most
 * 5 times, so this stays at that ceiling and chains itself via System.enqueueJob for the
 * remainder, a standard governor-safe pattern for fanning out more async work than one
 * transaction allows. Each record's own scan reuses RAA_AccessScanBatch completely unchanged.
 * A single record's failure (for example, an unsupported object or a deleted record) is caught
 * and recorded on that record's own analysis without aborting the rest of the run.
 */
public without sharing class RAA_BulkScanQueueable implements Queueable {
    @TestVisible
    private static final Integer CHUNK_SIZE = 5;

    private final List<Id> remainingRecordIds;
    private final Id batchRunId;
    private final Id requestingUserId;
    private final Boolean includeExternalUsers;
    private final Boolean includeInactiveUsers;

    public RAA_BulkScanQueueable(
        List<Id> remainingRecordIds,
        Id batchRunId,
        Id requestingUserId,
        Boolean includeExternalUsers,
        Boolean includeInactiveUsers
    ) {
        this.remainingRecordIds = remainingRecordIds;
        this.batchRunId = batchRunId;
        this.requestingUserId = requestingUserId;
        this.includeExternalUsers = includeExternalUsers;
        this.includeInactiveUsers = includeInactiveUsers;
    }

    public void execute(QueueableContext qc) {
        RAA_AnalysisRepository repository = new RAA_AnalysisRepository();
        RAA_SettingsService settings = new RAA_SettingsService();
        RAA_RecordMetadataResolver resolver = new RAA_RecordMetadataResolver();

        Integer stop = Math.min(CHUNK_SIZE, remainingRecordIds.size());
        for (Integer i = 0; i < stop; i++) {
            Id recordId = remainingRecordIds[i];
            try {
                RAA_RecordMetadataResolver.ResolvedRecord resolved = resolver.resolve(recordId);
                Id analysisId = repository.createAnalysis(
                    recordId,
                    resolved.objectApiName,
                    resolved.displayName,
                    requestingUserId,
                    includeExternalUsers,
                    includeInactiveUsers,
                    batchRunId
                );

                RAA_UserPopulationBuilder.PopulationFilter filter = new RAA_UserPopulationBuilder.PopulationFilter();
                filter.includeExternalUsers = includeExternalUsers;
                filter.includeInactiveUsers = includeInactiveUsers;

                Database.executeBatch(
                    new RAA_AccessScanBatch(analysisId, recordId, filter),
                    settings.defaultBatchScope
                );
            } catch (Exception e) {
                Id stubAnalysisId = repository.createAnalysis(
                    recordId,
                    'Unknown',
                    String.valueOf(recordId),
                    requestingUserId,
                    includeExternalUsers,
                    includeInactiveUsers,
                    batchRunId
                );
                repository.markFailed(stubAnalysisId, sanitize(e.getMessage()));
            }
        }

        List<Id> stillRemaining = new List<Id>();
        for (Integer i = stop; i < remainingRecordIds.size(); i++) {
            stillRemaining.add(remainingRecordIds[i]);
        }

        // Chaining a Queueable from within another Queueable's execute() always throws
        // "Maximum stack depth has been reached" when that execute() is itself running
        // synchronously inside a test's Test.stopTest() flush - so tests simulate the
        // remaining chunk by enqueueing it directly instead of relying on this chain.
        if (!stillRemaining.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(
                new RAA_BulkScanQueueable(
                    stillRemaining,
                    batchRunId,
                    requestingUserId,
                    includeExternalUsers,
                    includeInactiveUsers
                )
            );
        }
    }

    private String sanitize(String message) {
        if (message == null) {
            return '';
        }
        return message.length() > 500 ? message.substring(0, 500) : message;
    }
}
