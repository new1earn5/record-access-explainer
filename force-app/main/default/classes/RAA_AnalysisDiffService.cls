/**
 * Compares the persisted results of two analyses of the same record and reports which users
 * gained access, lost access, or had their effective access level or reason summary change.
 * Pure read/compare logic over already-persisted RAA_Access_Result__c rows - no new scanning.
 */
public without sharing class RAA_AnalysisDiffService {
    private final RAA_AnalysisRepository repository;

    public RAA_AnalysisDiffService() {
        this(new RAA_AnalysisRepository());
    }

    public RAA_AnalysisDiffService(RAA_AnalysisRepository repository) {
        this.repository = repository;
    }

    /** Compares the given analysis against the most recent earlier completed analysis of the same record, if any. */
    public RAA_AnalysisDiffDTO compareToPreviousAnalysis(Id analysisId) {
        RAA_Analysis__c current = repository.getAnalysis(analysisId);
        if (current == null) {
            throw new RAA_AppException('The requested analysis could not be found, or you do not have access to it.');
        }
        RAA_Analysis__c previous = repository.findPreviousCompletedAnalysis(current.RAA_Record_Id__c, analysisId);
        if (previous == null) {
            return null;
        }
        return compare(previous.Id, analysisId);
    }

    public RAA_AnalysisDiffDTO compare(Id fromAnalysisId, Id toAnalysisId) {
        RAA_Analysis__c fromAnalysis = repository.getAnalysis(fromAnalysisId);
        RAA_Analysis__c toAnalysis = repository.getAnalysis(toAnalysisId);
        if (fromAnalysis == null || toAnalysis == null) {
            throw new RAA_AppException(
                'One or both analyses to compare could not be found, or you do not have access to them.'
            );
        }

        Map<Id, RAA_Access_Result__c> fromResults = resultsByUser(repository.getResultsWithReasons(fromAnalysisId));
        Map<Id, RAA_Access_Result__c> toResults = resultsByUser(repository.getResultsWithReasons(toAnalysisId));

        RAA_AnalysisDiffDTO diff = new RAA_AnalysisDiffDTO();
        diff.fromAnalysisId = fromAnalysisId;
        diff.toAnalysisId = toAnalysisId;
        diff.fromCompletedAt = fromAnalysis.RAA_Completed_At__c;
        diff.toCompletedAt = toAnalysis.RAA_Completed_At__c;

        Set<Id> allUserIds = new Set<Id>();
        allUserIds.addAll(fromResults.keySet());
        allUserIds.addAll(toResults.keySet());

        List<Id> orderedUserIds = new List<Id>(allUserIds);
        orderedUserIds.sort();

        for (Id userId : orderedUserIds) {
            RAA_Access_Result__c fromRow = fromResults.get(userId);
            RAA_Access_Result__c toRow = toResults.get(userId);

            if (fromRow == null && toRow != null) {
                diff.changes.add(
                    buildChange(
                        userId,
                        toRow,
                        'Added',
                        null,
                        toRow.RAA_Max_Access_Level__c,
                        null,
                        toRow.RAA_Reason_Summary__c
                    )
                );
                diff.usersAdded++;
            } else if (fromRow != null && toRow == null) {
                diff.changes.add(
                    buildChange(
                        userId,
                        fromRow,
                        'Removed',
                        fromRow.RAA_Max_Access_Level__c,
                        null,
                        fromRow.RAA_Reason_Summary__c,
                        null
                    )
                );
                diff.usersRemoved++;
            } else if (fromRow != null && toRow != null) {
                Boolean accessLevelChanged = fromRow.RAA_Max_Access_Level__c != toRow.RAA_Max_Access_Level__c;
                Boolean reasonsChanged = fromRow.RAA_Reason_Summary__c != toRow.RAA_Reason_Summary__c;
                if (accessLevelChanged || reasonsChanged) {
                    diff.changes.add(
                        buildChange(
                            userId,
                            toRow,
                            'Changed',
                            fromRow.RAA_Max_Access_Level__c,
                            toRow.RAA_Max_Access_Level__c,
                            fromRow.RAA_Reason_Summary__c,
                            toRow.RAA_Reason_Summary__c
                        )
                    );
                    diff.usersChanged++;
                }
            }
        }

        return diff;
    }

    private RAA_UserAccessChangeDTO buildChange(
        Id userId,
        RAA_Access_Result__c source,
        String changeType,
        String previousAccessLevel,
        String currentAccessLevel,
        String previousReasons,
        String currentReasons
    ) {
        RAA_UserAccessChangeDTO change = new RAA_UserAccessChangeDTO();
        change.userId = userId;
        change.userFullName = source.RAA_User_Name__c;
        change.username = source.RAA_Username__c;
        change.changeType = changeType;
        change.previousMaxAccessLevel = previousAccessLevel;
        change.currentMaxAccessLevel = currentAccessLevel;
        change.previousReasonSummary = previousReasons;
        change.currentReasonSummary = currentReasons;
        return change;
    }

    private Map<Id, RAA_Access_Result__c> resultsByUser(List<RAA_Access_Result__c> results) {
        Map<Id, RAA_Access_Result__c> byUser = new Map<Id, RAA_Access_Result__c>();
        for (RAA_Access_Result__c result : results) {
            byUser.put(result.RAA_User__c, result);
        }
        return byUser;
    }
}
