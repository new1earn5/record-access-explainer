/**
 * Aura-enabled effective-access summary for one record, from the perspective of a single user,
 * as used by the "by user" reverse-mode scan. Reasons are intentionally not included here - they
 * are computed lazily, one record at a time, to keep the synchronous reverse scan governor-safe
 * across potentially hundreds of candidate records (see RAA_UserAccessExplorerService).
 */
public class RAA_UserRecordAccessSummaryDTO {
    @AuraEnabled public String recordId;
    @AuraEnabled public String recordDisplayName;
    @AuraEnabled public Boolean hasAnyAccess;
    @AuraEnabled public String maxAccessLevel;
    @AuraEnabled public Boolean hasReadAccess;
    @AuraEnabled public Boolean hasEditAccess;
    @AuraEnabled public Boolean hasDeleteAccess;
    @AuraEnabled public Boolean hasTransferAccess;
    @AuraEnabled public Boolean hasAllAccess;
}
