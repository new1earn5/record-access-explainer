/**
 * Owns all DML and query access to the RAA_Analysis__c / RAA_Access_Result__c /
 * RAA_Access_Reason__c object graph. Runs in system context because the batch and orchestrator
 * layers must be able to persist audit data regardless of the operator's own CRUD/FLS on these
 * package-owned objects (their sharing model is Private / Controlled By Parent and is managed
 * entirely by the packaged permission set, not by the running-user context of an elevated
 * background job). Duplicate access results for the same analysis and user are prevented with
 * an upsert against the RAA_Unique_Key__c external ID field.
 */
public without sharing class RAA_AnalysisRepository {
    public class SaveOutcome {
        public Integer savedCount = 0;
        public Integer usersWithAccessSaved = 0;
        public List<String> errors = new List<String>();
    }

    public Id createAnalysis(
        Id recordId,
        String objectApiName,
        String displayName,
        Id requestedById,
        Boolean includeExternalUsers,
        Boolean includeInactiveUsers
    ) {
        return createAnalysis(
            recordId,
            objectApiName,
            displayName,
            requestedById,
            includeExternalUsers,
            includeInactiveUsers,
            null
        );
    }

    public Id createAnalysis(
        Id recordId,
        String objectApiName,
        String displayName,
        Id requestedById,
        Boolean includeExternalUsers,
        Boolean includeInactiveUsers,
        Id batchRunId
    ) {
        RAA_Analysis__c analysis = new RAA_Analysis__c(
            RAA_Record_Id__c = recordId,
            RAA_Object_API_Name__c = objectApiName,
            RAA_Record_Display_Name__c = displayName,
            RAA_Status__c = 'Queued',
            RAA_Requested_By__c = requestedById,
            RAA_Requested_At__c = System.now(),
            RAA_Include_External_Users__c = includeExternalUsers,
            RAA_Include_Inactive_Users__c = includeInactiveUsers,
            RAA_Total_Users__c = 0,
            RAA_Processed_Users__c = 0,
            RAA_Users_With_Access__c = 0,
            RAA_Is_Complete__c = false,
            RAA_Batch_Run__c = batchRunId
        );
        insert analysis;
        return analysis.Id;
    }

    public RAA_Analysis__c findActiveAnalysisForRecord(Id recordId) {
        List<RAA_Analysis__c> rows = [
            SELECT Id, RAA_Status__c, RAA_Requested_At__c, RAA_Requested_By__c
            FROM RAA_Analysis__c
            WHERE RAA_Record_Id__c = :recordId AND RAA_Is_Complete__c = FALSE
            ORDER BY RAA_Requested_At__c DESC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    public RAA_Analysis__c getAnalysis(Id analysisId) {
        List<RAA_Analysis__c> rows = [
            SELECT
                Id,
                RAA_Record_Id__c,
                RAA_Object_API_Name__c,
                RAA_Record_Display_Name__c,
                RAA_Status__c,
                RAA_Requested_By__c,
                RAA_Requested_At__c,
                RAA_Started_At__c,
                RAA_Completed_At__c,
                RAA_Async_Job_Id__c,
                RAA_Total_Users__c,
                RAA_Processed_Users__c,
                RAA_Users_With_Access__c,
                RAA_Include_External_Users__c,
                RAA_Include_Inactive_Users__c,
                RAA_Warnings__c,
                RAA_Error_Details__c,
                RAA_Is_Complete__c,
                RAA_Batch_Run__c
            FROM RAA_Analysis__c
            WHERE Id = :analysisId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    /** Most recently completed analysis of the same record, excluding the given analysis itself. */
    public RAA_Analysis__c findPreviousCompletedAnalysis(Id recordId, Id excludeAnalysisId) {
        List<RAA_Analysis__c> rows = [
            SELECT Id, RAA_Completed_At__c
            FROM RAA_Analysis__c
            WHERE RAA_Record_Id__c = :recordId AND RAA_Is_Complete__c = TRUE AND Id != :excludeAnalysisId
            ORDER BY RAA_Completed_At__c DESC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    public List<RAA_Analysis__c> getAnalysesForBatchRun(Id batchRunId) {
        return [
            SELECT
                Id,
                RAA_Record_Id__c,
                RAA_Record_Display_Name__c,
                RAA_Status__c,
                RAA_Is_Complete__c,
                RAA_Users_With_Access__c,
                RAA_Warnings__c,
                RAA_Error_Details__c
            FROM RAA_Analysis__c
            WHERE RAA_Batch_Run__c = :batchRunId
            ORDER BY RAA_Record_Display_Name__c
        ];
    }

    public List<RAA_Access_Result__c> getResultsWithReasons(Id analysisId) {
        return [
            SELECT
                Id,
                RAA_User__c,
                RAA_User_Name__c,
                RAA_Username__c,
                RAA_User_Type__c,
                RAA_Profile_Name__c,
                RAA_Is_Active__c,
                RAA_Max_Access_Level__c,
                RAA_Has_Read_Access__c,
                RAA_Has_Edit_Access__c,
                RAA_Has_Delete_Access__c,
                RAA_Has_Transfer_Access__c,
                RAA_Has_All_Access__c,
                RAA_Reason_Summary__c,
                RAA_Overall_Confidence__c,
                RAA_Has_Unresolved_Reason__c,
                (
                    SELECT
                        Id,
                        RAA_Category__c,
                        RAA_Access_Level__c,
                        RAA_Confidence__c,
                        RAA_Is_Direct__c,
                        RAA_Source_Name__c,
                        RAA_Source_Id__c,
                        RAA_Source_Object__c,
                        RAA_Principal_Id__c,
                        RAA_Principal_Type__c,
                        RAA_Row_Cause__c,
                        RAA_Grant_Path__c,
                        RAA_Explanation__c,
                        RAA_Evidence__c
                    FROM RAA_Access_Reasons__r
                    ORDER BY RAA_Category__c
                )
            FROM RAA_Access_Result__c
            WHERE RAA_Analysis__c = :analysisId
            ORDER BY RAA_User_Name__c
        ];
    }

    public void markBatchStarted(Id analysisId, Id asyncJobId, Integer totalUsers) {
        update new RAA_Analysis__c(
            Id = analysisId,
            RAA_Status__c = 'Running',
            RAA_Started_At__c = System.now(),
            RAA_Async_Job_Id__c = asyncJobId,
            RAA_Total_Users__c = totalUsers
        );
    }

    public void updateProgress(Id analysisId, Integer processedUsers, Integer usersWithAccess) {
        update new RAA_Analysis__c(
            Id = analysisId,
            RAA_Processed_Users__c = processedUsers,
            RAA_Users_With_Access__c = usersWithAccess
        );
    }

    public void markCompleted(Id analysisId, Boolean hasWarnings, String warningsText) {
        update new RAA_Analysis__c(
            Id = analysisId,
            RAA_Status__c = hasWarnings ? 'Completed with Warnings' : 'Completed',
            RAA_Completed_At__c = System.now(),
            RAA_Is_Complete__c = true,
            RAA_Warnings__c = truncate(warningsText, 32768)
        );
    }

    public void markFailed(Id analysisId, String sanitizedError) {
        update new RAA_Analysis__c(
            Id = analysisId,
            RAA_Status__c = 'Failed',
            RAA_Completed_At__c = System.now(),
            RAA_Is_Complete__c = true,
            RAA_Error_Details__c = truncate(sanitizedError, 32768)
        );
    }

    public void markCancelled(Id analysisId) {
        update new RAA_Analysis__c(
            Id = analysisId,
            RAA_Status__c = 'Cancelled',
            RAA_Completed_At__c = System.now(),
            RAA_Is_Complete__c = true
        );
    }

    public void deleteAnalysis(Id analysisId) {
        delete new RAA_Analysis__c(Id = analysisId);
    }

    public Id createBatchRun(
        String objectApiName,
        Integer totalRecords,
        String recordIdsText,
        Id requestedById,
        Boolean includeExternalUsers,
        Boolean includeInactiveUsers
    ) {
        RAA_Batch_Run__c run = new RAA_Batch_Run__c(
            RAA_Object_API_Name__c = objectApiName,
            RAA_Total_Records__c = totalRecords,
            RAA_Record_Ids__c = recordIdsText,
            RAA_Status__c = 'Queued',
            RAA_Requested_By__c = requestedById,
            RAA_Requested_At__c = System.now(),
            RAA_Include_External_Users__c = includeExternalUsers,
            RAA_Include_Inactive_Users__c = includeInactiveUsers
        );
        insert run;
        return run.Id;
    }

    public RAA_Batch_Run__c getBatchRun(Id batchRunId) {
        List<RAA_Batch_Run__c> rows = [
            SELECT
                Id,
                RAA_Object_API_Name__c,
                RAA_Total_Records__c,
                RAA_Status__c,
                RAA_Requested_By__c,
                RAA_Requested_At__c,
                RAA_Include_External_Users__c,
                RAA_Include_Inactive_Users__c
            FROM RAA_Batch_Run__c
            WHERE Id = :batchRunId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    /** Recomputes the batch run's status from its child analyses and persists it, then returns the fresh row. */
    public RAA_Batch_Run__c refreshAndGetBatchRunStatus(Id batchRunId) {
        RAA_Batch_Run__c run = getBatchRun(batchRunId);
        if (run == null) {
            return null;
        }

        List<RAA_Analysis__c> children = getAnalysesForBatchRun(batchRunId);
        Integer completedCount = 0;
        Integer failedCount = 0;
        Integer warningCount = 0;
        for (RAA_Analysis__c child : children) {
            if (child.RAA_Is_Complete__c) {
                completedCount++;
            }
            if (child.RAA_Status__c == 'Failed') {
                failedCount++;
            }
            if (child.RAA_Status__c == 'Completed with Warnings') {
                warningCount++;
            }
        }

        String status;
        Integer totalRecords = run.RAA_Total_Records__c != null
            ? Integer.valueOf(run.RAA_Total_Records__c)
            : children.size();
        if (children.isEmpty()) {
            status = 'Queued';
        } else if (completedCount < children.size() || completedCount < totalRecords) {
            status = 'Running';
        } else if (failedCount == children.size()) {
            status = 'Failed';
        } else if (failedCount > 0 || warningCount > 0) {
            status = 'Completed with Warnings';
        } else {
            status = 'Completed';
        }

        if (status != run.RAA_Status__c) {
            update new RAA_Batch_Run__c(Id = batchRunId, RAA_Status__c = status);
            run.RAA_Status__c = status;
        }
        return run;
    }

    public List<RAA_Analysis__c> findCompletedOlderThan(Datetime threshold, Integer maxRows) {
        return [
            SELECT Id
            FROM RAA_Analysis__c
            WHERE RAA_Is_Complete__c = TRUE AND RAA_Completed_At__c < :threshold
            LIMIT :maxRows
        ];
    }

    /**
     * Upserts one RAA_Access_Result__c per aggregated user (deduplicated via RAA_Unique_Key__c),
     * then replaces that result's child RAA_Access_Reason__c rows so a retried batch chunk never
     * produces duplicate reasons.
     */
    public SaveOutcome saveResults(
        Id analysisId,
        List<RAA_ReasonAggregator.AggregatedUserResult> aggregated,
        Map<Id, User> userInfoById
    ) {
        SaveOutcome outcome = new SaveOutcome();
        if (aggregated == null || aggregated.isEmpty()) {
            return outcome;
        }

        List<RAA_Access_Result__c> resultRows = new List<RAA_Access_Result__c>();
        for (RAA_ReasonAggregator.AggregatedUserResult aggregatedResult : aggregated) {
            User u = userInfoById.get(aggregatedResult.userId);
            resultRows.add(
                new RAA_Access_Result__c(
                    RAA_Analysis__c = analysisId,
                    RAA_User__c = aggregatedResult.userId,
                    RAA_User_Name__c = u != null ? u.Name : null,
                    RAA_Username__c = u != null ? u.Username : null,
                    RAA_User_Type__c = u != null ? u.UserType : null,
                    RAA_Profile_Name__c = u != null && u.Profile != null ? u.Profile.Name : null,
                    RAA_Is_Active__c = u != null ? u.IsActive : null,
                    RAA_Max_Access_Level__c = aggregatedResult.effectiveAccess.maxAccessLevel,
                    RAA_Has_Read_Access__c = aggregatedResult.effectiveAccess.hasReadAccess,
                    RAA_Has_Edit_Access__c = aggregatedResult.effectiveAccess.hasEditAccess,
                    RAA_Has_Delete_Access__c = aggregatedResult.effectiveAccess.hasDeleteAccess,
                    RAA_Has_Transfer_Access__c = aggregatedResult.effectiveAccess.hasTransferAccess,
                    RAA_Has_All_Access__c = aggregatedResult.effectiveAccess.hasAllAccess,
                    RAA_Reason_Summary__c = buildReasonSummary(aggregatedResult.reasons),
                    RAA_Overall_Confidence__c = buildOverallConfidence(aggregatedResult.reasons),
                    RAA_Has_Unresolved_Reason__c = hasUnresolvedReason(aggregatedResult.reasons),
                    RAA_Unique_Key__c = analysisId + '-' + aggregatedResult.userId
                )
            );
        }

        Database.UpsertResult[] upsertResults = Database.upsert(
            resultRows,
            RAA_Access_Result__c.RAA_Unique_Key__c,
            false
        );

        List<Id> savedResultIds = new List<Id>();
        List<RAA_ReasonAggregator.AggregatedUserResult> savedAggregates = new List<RAA_ReasonAggregator.AggregatedUserResult>();
        for (Integer i = 0; i < upsertResults.size(); i++) {
            if (upsertResults[i].isSuccess()) {
                savedResultIds.add(upsertResults[i].getId());
                savedAggregates.add(aggregated[i]);
                outcome.savedCount++;
                if (aggregated[i].effectiveAccess.hasAnyAccess()) {
                    outcome.usersWithAccessSaved++;
                }
            } else {
                for (Database.Error err : upsertResults[i].getErrors()) {
                    outcome.errors.add('User ' + aggregated[i].userId + ': ' + err.getMessage());
                }
            }
        }

        if (!savedResultIds.isEmpty()) {
            delete [SELECT Id FROM RAA_Access_Reason__c WHERE RAA_Access_Result__c IN :savedResultIds];

            List<RAA_Access_Reason__c> reasonRows = new List<RAA_Access_Reason__c>();
            for (Integer i = 0; i < savedResultIds.size(); i++) {
                for (RAA_AccessReasonDTO reasonDto : savedAggregates[i].reasons) {
                    reasonRows.add(
                        new RAA_Access_Reason__c(
                            RAA_Access_Result__c = savedResultIds[i],
                            RAA_Category__c = reasonDto.category,
                            RAA_Access_Level__c = reasonDto.accessLevel,
                            RAA_Confidence__c = reasonDto.confidence,
                            RAA_Is_Direct__c = reasonDto.isDirect,
                            RAA_Source_Name__c = reasonDto.sourceName,
                            RAA_Source_Id__c = reasonDto.sourceId,
                            RAA_Source_Object__c = reasonDto.sourceObject,
                            RAA_Principal_Id__c = reasonDto.principalId,
                            RAA_Principal_Type__c = reasonDto.principalType,
                            RAA_Row_Cause__c = reasonDto.rowCause,
                            RAA_Grant_Path__c = truncate(reasonDto.grantPath, 4000),
                            RAA_Explanation__c = truncate(reasonDto.explanation, 4000),
                            RAA_Evidence__c = truncate(reasonDto.evidence, 32768)
                        )
                    );
                }
            }
            if (!reasonRows.isEmpty()) {
                Database.insert(reasonRows, false);
            }
        }

        return outcome;
    }

    private String buildReasonSummary(List<RAA_AccessReasonDTO> reasons) {
        Set<String> categories = new Set<String>();
        for (RAA_AccessReasonDTO reason : reasons) {
            categories.add(reason.category);
        }
        List<String> sortedCategories = new List<String>(categories);
        sortedCategories.sort();
        return String.join(sortedCategories, '; ');
    }

    private String buildOverallConfidence(List<RAA_AccessReasonDTO> reasons) {
        Set<String> confidenceLevels = new Set<String>();
        for (RAA_AccessReasonDTO reason : reasons) {
            confidenceLevels.add(reason.confidence);
        }
        if (confidenceLevels.size() > 1) {
            return 'Mixed';
        }
        if (confidenceLevels.isEmpty()) {
            return 'Low';
        }
        return new List<String>(confidenceLevels)[0];
    }

    private Boolean hasUnresolvedReason(List<RAA_AccessReasonDTO> reasons) {
        for (RAA_AccessReasonDTO reason : reasons) {
            if (reason.category == 'Unresolved') {
                return true;
            }
        }
        return false;
    }

    private String truncate(String value, Integer maxLength) {
        if (value == null) {
            return null;
        }
        return value.length() > maxLength ? value.substring(0, maxLength) : value;
    }
}
