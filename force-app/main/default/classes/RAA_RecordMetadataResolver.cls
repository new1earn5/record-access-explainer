/**
 * Resolves and validates the sObject type and basic display metadata for a candidate record ID.
 * Runs in system context (without sharing) because a Record Access Explainer auditor is
 * explicitly analyzing OTHER users' access and may not personally have record-level access
 * to the record under review; existence/type validation must not depend on the operator's
 * own sharing visibility. This class has no @AuraEnabled methods and is only ever invoked
 * through RAA_AnalysisOrchestratorService, which itself enforces the custom permission check
 * before calling in.
 */
public without sharing class RAA_RecordMetadataResolver {

    public class ResolvedRecord {
        public Id recordId;
        public Schema.SObjectType sObjectType;
        public Schema.DescribeSObjectResult objectDescribe;
        public String objectApiName;
        public String displayName;
        public SObject targetRecord;
    }

    public ResolvedRecord resolve(Id recordId) {
        Schema.SObjectType sObjectType = recordId.getSObjectType();
        if (sObjectType == null) {
            throw new RAA_AppException('The supplied ID does not correspond to a known Salesforce object.');
        }

        Schema.DescribeSObjectResult objectDescribe = sObjectType.getDescribe();

        if (objectDescribe.isCustomSetting()) {
            throw new RAA_AppException(objectDescribe.getLabel() + ' is a custom setting, not a data record, and is not supported.');
        }
        if (!objectDescribe.isQueryable()) {
            throw new RAA_AppException(objectDescribe.getLabel() + ' is not a queryable data object and is not supported.');
        }

        Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();
        Set<String> queryFields = new Set<String>{ 'Id' };
        if (fieldMap.containsKey('OwnerId')) {
            queryFields.add('OwnerId');
        }
        String nameFieldApi = findNameField(fieldMap);
        if (nameFieldApi != null) {
            queryFields.add(nameFieldApi);
        }

        String query = 'SELECT ' + String.join(new List<String>(queryFields), ', ')
                + ' FROM ' + String.escapeSingleQuotes(objectDescribe.getName())
                + ' WHERE Id = :recordId LIMIT 1';

        List<SObject> rows;
        try {
            rows = Database.query(query);
        } catch (System.QueryException e) {
            throw new RAA_AppException('Unable to query ' + objectDescribe.getLabel() + ' records in this org: ' + sanitize(e.getMessage()));
        }

        if (rows.isEmpty()) {
            throw new RAA_AppException('No ' + objectDescribe.getLabel() + ' record was found for the supplied ID.');
        }

        ResolvedRecord result = new ResolvedRecord();
        result.recordId = recordId;
        result.sObjectType = sObjectType;
        result.objectDescribe = objectDescribe;
        result.objectApiName = objectDescribe.getName();
        result.targetRecord = rows[0];
        result.displayName = nameFieldApi != null && rows[0].get(nameFieldApi) != null
                ? String.valueOf(rows[0].get(nameFieldApi))
                : (String) recordId;
        return result;
    }

    /** Confirms UserRecordAccess can be evaluated for this object by issuing a minimal probe query. */
    public Boolean supportsUserRecordAccess(Id recordId) {
        try {
            // UserRecordAccess requires at least one Has*Access field whenever RecordId is
            // selected without other columns, so this probe mirrors the real provider's shape.
            List<UserRecordAccess> probe = [
                SELECT RecordId, HasReadAccess, MaxAccessLevel
                FROM UserRecordAccess
                WHERE RecordId = :recordId
                AND UserId = :UserInfo.getUserId()
            ];
            return true;
        } catch (System.QueryException e) {
            return false;
        }
    }

    private String findNameField(Map<String, Schema.SObjectField> fieldMap) {
        if (fieldMap.containsKey('Name')) {
            return 'Name';
        }
        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
            if (fieldDescribe.isNameField()) {
                return fieldDescribe.getName();
            }
        }
        return null;
    }

    private String sanitize(String message) {
        if (message == null) {
            return '';
        }
        return message.length() > 255 ? message.substring(0, 255) : message;
    }
}
