/**
 * Batch Apex entry point for a single scan. Iterates the pre-computed user population in
 * chunks (default scope from RAA_Settings__mdt) and, for each chunk, runs the full reason
 * aggregation pipeline and persists results.
 *
 * Batch, Queueable, Scheduled, and Future Apex all execute in system mode with respect to
 * object and field-level permissions - only record-level sharing is governed by the class's
 * with/without sharing keyword. Declaring this class without sharing means the scan itself
 * evaluates every user's access using Salesforce's full system-mode view, independent of the
 * requesting operator's own object/field permissions; the operator only needs the
 * RAA_Run_Record_Access_Analysis custom permission (checked before this batch is ever enqueued)
 * to trigger and view a scan.
 *
 * Database.Stateful is used deliberately (and only) to carry running progress counters
 * (processedCount, usersWithAccessCount) and accumulated non-fatal warnings across chunks, so
 * the analysis record can show accurate incremental progress without re-querying or re-summing
 * every previously saved result on each execute() call.
 */
public without sharing class RAA_AccessScanBatch implements Database.Batchable<Id>, Database.Stateful {
    private final Id analysisId;
    private final Id recordId;
    private final RAA_UserPopulationBuilder.PopulationFilter filter;

    private Integer processedCount = 0;
    private Integer usersWithAccessCount = 0;
    private List<String> warnings = new List<String>();
    private List<String> hygieneNotes = new List<String>();

    private final RAA_AnalysisRepository repository = new RAA_AnalysisRepository();
    private final RAA_ReasonAggregator aggregator = new RAA_ReasonAggregator();

    public RAA_AccessScanBatch(Id analysisId, Id recordId, RAA_UserPopulationBuilder.PopulationFilter filter) {
        this.analysisId = analysisId;
        this.recordId = recordId;
        this.filter = filter;
    }

    public Iterable<Id> start(Database.BatchableContext bc) {
        RAA_Analysis__c current = repository.getAnalysis(analysisId);
        if (current == null || current.RAA_Is_Complete__c) {
            // Cancelled (or otherwise already marked terminal by some other path) after being
            // enqueued but before the platform picked the job up; do no work.
            return new List<Id>();
        }

        RAA_SettingsService settings = new RAA_SettingsService();
        Set<Id> populationIds;
        try {
            populationIds = new RAA_UserPopulationBuilder().buildPopulation(filter, settings.maxUsersPerScan);
        } catch (RAA_AppException e) {
            repository.markFailed(analysisId, e.getMessage());
            return new List<Id>();
        }
        repository.markBatchStarted(analysisId, bc.getJobId(), populationIds.size());
        return new List<Id>(populationIds);
    }

    public void execute(Database.BatchableContext bc, List<Id> scope) {
        Set<Id> userIds = new Set<Id>(scope);
        List<String> chunkWarnings = new List<String>();
        List<String> chunkHygieneNotes = new List<String>();

        List<RAA_ReasonAggregator.AggregatedUserResult> aggregated;
        try {
            aggregated = aggregator.analyzeBatch(recordId, userIds, chunkWarnings, chunkHygieneNotes);
        } catch (Exception e) {
            warnings.add('A chunk of ' + scope.size() + ' user(s) could not be analyzed: ' + sanitize(e.getMessage()));
            processedCount += scope.size();
            repository.updateProgress(analysisId, processedCount, usersWithAccessCount);
            return;
        }

        Map<Id, User> userInfoMap = new Map<Id, User>(
            [
                SELECT Id, Name, Username, UserType, IsActive, Profile.Name
                FROM User
                WHERE Id IN :userIds
            ]
        );

        RAA_AnalysisRepository.SaveOutcome outcome = repository.saveResults(analysisId, aggregated, userInfoMap);
        usersWithAccessCount += outcome.usersWithAccessSaved;
        warnings.addAll(chunkWarnings);
        warnings.addAll(outcome.errors);
        hygieneNotes.addAll(chunkHygieneNotes);

        processedCount += scope.size();
        repository.updateProgress(analysisId, processedCount, usersWithAccessCount);
    }

    public void finish(Database.BatchableContext bc) {
        RAA_Analysis__c current = repository.getAnalysis(analysisId);
        if (current == null) {
            return;
        }
        if (current.RAA_Is_Complete__c) {
            // Already finalized before this job's own finish() ran - either cancelled, or
            // start() itself already marked this analysis Failed (for example, exceeding
            // RAA_Max_Users_Per_Scan__c) and returned before any chunks executed. Either way,
            // never overwrite an already-terminal status, but still let subscribers waiting on
            // this analysis know the terminal state has been reached.
            publishStatusEvent(current.RAA_Status__c, true);
            return;
        }

        Integer jobErrorCount = 0;
        for (AsyncApexJob job : [SELECT NumberOfErrors FROM AsyncApexJob WHERE Id = :bc.getJobId()]) {
            jobErrorCount = job.NumberOfErrors;
        }

        Boolean hasWarnings = !warnings.isEmpty() || jobErrorCount > 0;
        repository.markCompleted(
            analysisId,
            hasWarnings,
            String.join(new List<String>(new Set<String>(warnings)), '\n'),
            String.join(new List<String>(new Set<String>(hygieneNotes)), '\n')
        );
        publishStatusEvent(hasWarnings ? 'Completed with Warnings' : 'Completed', true);
    }

    private void publishStatusEvent(String status, Boolean isComplete) {
        EventBus.publish(
            new RAA_Scan_Status_Event__e(
                RAA_Analysis_Id__c = analysisId,
                RAA_Status__c = status,
                RAA_Is_Complete__c = isComplete
            )
        );
    }

    private String sanitize(String message) {
        if (message == null) {
            return '';
        }
        return message.length() > 500 ? message.substring(0, 500) : message;
    }
}
