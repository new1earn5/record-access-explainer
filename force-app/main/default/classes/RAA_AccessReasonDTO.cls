/**
 * Aura-enabled representation of a single detected access reason (RAA_Access_Reason__c row).
 * Implements Comparable so the aggregator can sort reasons deterministically before persisting
 * or deduplicating them.
 */
public class RAA_AccessReasonDTO implements Comparable {
    @AuraEnabled
    public String recordId;
    @AuraEnabled
    public String category;
    @AuraEnabled
    public String accessLevel;
    @AuraEnabled
    public String confidence;
    @AuraEnabled
    public Boolean isDirect;
    @AuraEnabled
    public String sourceName;
    @AuraEnabled
    public String sourceId;
    @AuraEnabled
    public String sourceObject;
    @AuraEnabled
    public String principalId;
    @AuraEnabled
    public String principalType;
    @AuraEnabled
    public String rowCause;
    @AuraEnabled
    public String grantPath;
    @AuraEnabled
    public String explanation;
    @AuraEnabled
    public String evidence;

    public RAA_AccessReasonDTO() {
    }

    public RAA_AccessReasonDTO(RAA_Access_Reason__c reason) {
        this.recordId = reason.Id;
        this.category = reason.RAA_Category__c;
        this.accessLevel = reason.RAA_Access_Level__c;
        this.confidence = reason.RAA_Confidence__c;
        this.isDirect = reason.RAA_Is_Direct__c;
        this.sourceName = reason.RAA_Source_Name__c;
        this.sourceId = reason.RAA_Source_Id__c;
        this.sourceObject = reason.RAA_Source_Object__c;
        this.principalId = reason.RAA_Principal_Id__c;
        this.principalType = reason.RAA_Principal_Type__c;
        this.rowCause = reason.RAA_Row_Cause__c;
        this.grantPath = reason.RAA_Grant_Path__c;
        this.explanation = reason.RAA_Explanation__c;
        this.evidence = reason.RAA_Evidence__c;
    }

    public String sortKey() {
        return (category == null ? '' : category) +
            '|' +
            (grantPath == null ? '' : grantPath) +
            '|' +
            (sourceName == null ? '' : sourceName) +
            '|' +
            (rowCause == null ? '' : rowCause);
    }

    public String dedupeKey() {
        return sortKey() + '|' + (accessLevel == null ? '' : accessLevel) + '|' + (sourceId == null ? '' : sourceId);
    }

    public Integer compareTo(Object other) {
        RAA_AccessReasonDTO that = (RAA_AccessReasonDTO) other;
        return this.sortKey().compareTo(that.sortKey());
    }
}
