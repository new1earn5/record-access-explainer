/**
 * Validates and normalizes client-supplied record IDs before any SOQL touches them.
 * Every entry point that accepts an ID from the LWC layer must route it through here first.
 */
public with sharing class RAA_IdValidationUtil {

    public static Id normalizeRecordId(String rawValue) {
        if (String.isBlank(rawValue)) {
            throw new RAA_AppException('Please enter a record ID.');
        }
        String trimmed = rawValue.trim();
        if (!Pattern.matches('^[a-zA-Z0-9]{15}$|^[a-zA-Z0-9]{18}$', trimmed)) {
            throw new RAA_AppException('"' + trimmed + '" is not a valid Salesforce record ID. IDs must be 15 or 18 alphanumeric characters.');
        }
        try {
            return Id.valueOf(trimmed);
        } catch (System.StringException e) {
            throw new RAA_AppException('"' + trimmed + '" is not a valid Salesforce record ID.');
        }
    }

    public static Id normalizeAnalysisId(String rawValue) {
        if (String.isBlank(rawValue)) {
            throw new RAA_AppException('An analysis ID is required.');
        }
        Id normalized = normalizeRecordId(rawValue);
        if (normalized.getSObjectType() != RAA_Analysis__c.SObjectType) {
            throw new RAA_AppException('The supplied ID does not refer to an RAA Analysis record.');
        }
        return normalized;
    }
}
