/**
 * "Reverse mode": given one user and a candidate set of records (all of the same object type),
 * reports effective access to each via a single bulk UserRecordAccess query. This is the
 * confirmed-supported bulk shape (UserId = a single ID, RecordId IN a list) - the mirror image of
 * the primary "one record, many users" scan, which is why that one has to query per user instead.
 *
 * Reasons for a specific record are fetched separately and lazily (see getAccessReasons) rather
 * than computed for every candidate up front, because running the full reason-attribution
 * pipeline (multiple SOQL queries per record) for potentially hundreds of records in one
 * synchronous Apex transaction would risk the governor limits that make this feature intentionally
 * synchronous and fast in the first place.
 */
// Deliberately without sharing and CRUD/FLS-unchecked: part of the elevated scan pipeline (see
// docs/architecture.md §1, "Batch Apex runs in system mode"), reached only through the with-sharing
// controller's permission gate.
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class RAA_UserAccessExplorerService {
    private static final Integer CHUNK_SIZE = 200;

    // The UserRecordAccess query below runs once per CHUNK_SIZE-bounded chunk, not once per
    // record - the standard bulk-chunking pattern, not an unbounded per-record query.
    @SuppressWarnings('PMD.OperationWithLimitsInLoop')
    public List<RAA_UserRecordAccessSummaryDTO> scanUserAcrossRecords(
        Id userId,
        String objectApiName,
        List<Id> candidateRecordIds
    ) {
        List<RAA_UserRecordAccessSummaryDTO> results = new List<RAA_UserRecordAccessSummaryDTO>();
        if (candidateRecordIds == null || candidateRecordIds.isEmpty()) {
            return results;
        }

        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
        if (sObjectType == null) {
            throw new RAA_AppException('"' + objectApiName + '" is not a recognized object.');
        }
        for (Id recordId : candidateRecordIds) {
            if (recordId.getSObjectType() != sObjectType) {
                throw new RAA_AppException(
                    'All candidate records must belong to the same object (' + objectApiName + ').'
                );
            }
        }

        Map<Id, String> displayNames = resolveDisplayNames(sObjectType, candidateRecordIds);
        Map<Id, UserRecordAccess> accessByRecord = new Map<Id, UserRecordAccess>();

        for (Integer start = 0; start < candidateRecordIds.size(); start += CHUNK_SIZE) {
            Integer stop = Math.min(start + CHUNK_SIZE, candidateRecordIds.size());
            List<Id> chunk = new List<Id>();
            for (Integer i = start; i < stop; i++) {
                chunk.add(candidateRecordIds[i]);
            }
            for (UserRecordAccess access : [
                SELECT
                    RecordId,
                    HasReadAccess,
                    HasEditAccess,
                    HasDeleteAccess,
                    HasTransferAccess,
                    HasAllAccess,
                    MaxAccessLevel
                FROM UserRecordAccess
                WHERE UserId = :userId AND RecordId IN :chunk
            ]) {
                accessByRecord.put(access.RecordId, access);
            }
        }

        for (Id recordId : candidateRecordIds) {
            UserRecordAccess access = accessByRecord.get(recordId);
            RAA_UserRecordAccessSummaryDTO dto = new RAA_UserRecordAccessSummaryDTO();
            dto.recordId = recordId;
            dto.recordDisplayName = displayNames.containsKey(recordId)
                ? displayNames.get(recordId)
                : String.valueOf(recordId);
            dto.hasReadAccess = access != null && access.HasReadAccess;
            dto.hasEditAccess = access != null && access.HasEditAccess;
            dto.hasDeleteAccess = access != null && access.HasDeleteAccess;
            dto.hasTransferAccess = access != null && access.HasTransferAccess;
            dto.hasAllAccess = access != null && access.HasAllAccess;
            dto.maxAccessLevel = access != null ? access.MaxAccessLevel : 'None';
            dto.hasAnyAccess =
                dto.hasReadAccess ||
                dto.hasEditAccess ||
                dto.hasDeleteAccess ||
                dto.hasTransferAccess ||
                dto.hasAllAccess;
            results.add(dto);
        }

        results.sort(new ByHasAccessThenName());
        return results;
    }

    /** Computes the full reason breakdown for one user against one record, on demand. */
    public List<RAA_AccessReasonDTO> getAccessReasons(Id userId, Id recordId) {
        RAA_ReasonAggregator aggregator = new RAA_ReasonAggregator();
        List<String> warnings = new List<String>();
        // hygieneNotesOut is deliberately null here: that signal means "no member of the
        // scanned population," which is meaningless noise against a population of exactly one.
        List<RAA_ReasonAggregator.AggregatedUserResult> results = aggregator.analyzeBatch(
            recordId,
            new Set<Id>{ userId },
            warnings,
            null
        );
        if (results.isEmpty()) {
            return new List<RAA_AccessReasonDTO>();
        }
        return results[0].reasons;
    }

    // describe.getName() and nameField below come from Schema describes, never client input,
    // so this is not an injection risk; the query itself runs once per CHUNK_SIZE-bounded chunk.
    // DEFERRED below already skips eagerly loading child-relationship metadata, which nothing
    // here reads - PMD's rule doesn't recognize that argument as a mitigation.
    @SuppressWarnings('PMD.ApexSOQLInjection,PMD.OperationWithLimitsInLoop,PMD.EagerlyLoadedDescribeSObjectResult')
    private Map<Id, String> resolveDisplayNames(Schema.SObjectType sObjectType, List<Id> recordIds) {
        Map<Id, String> names = new Map<Id, String>();
        // DEFERRED skips eagerly loading child-relationship metadata, which nothing here reads.
        Schema.DescribeSObjectResult describe = sObjectType.getDescribe(Schema.SObjectDescribeOptions.DEFERRED);
        Map<String, Schema.SObjectField> fieldMap = describe.fields.getMap();

        String nameField;
        if (fieldMap.containsKey('Name')) {
            nameField = 'Name';
        } else {
            for (String fieldName : fieldMap.keySet()) {
                if (fieldMap.get(fieldName).getDescribe().isNameField()) {
                    nameField = fieldMap.get(fieldName).getDescribe().getName();
                    break;
                }
            }
        }
        if (nameField == null) {
            return names;
        }

        for (Integer start = 0; start < recordIds.size(); start += CHUNK_SIZE) {
            Integer stop = Math.min(start + CHUNK_SIZE, recordIds.size());
            List<Id> chunk = new List<Id>();
            for (Integer i = start; i < stop; i++) {
                chunk.add(recordIds[i]);
            }
            String query =
                'SELECT Id, ' +
                nameField +
                ' FROM ' +
                String.escapeSingleQuotes(describe.getName()) +
                ' WHERE Id IN :chunk';
            for (SObject record : Database.query(query)) {
                Object nameValue = record.get(nameField);
                names.put(record.Id, nameValue != null ? String.valueOf(nameValue) : String.valueOf(record.Id));
            }
        }
        return names;
    }

    private class ByHasAccessThenName implements Comparator<RAA_UserRecordAccessSummaryDTO> {
        public Integer compare(RAA_UserRecordAccessSummaryDTO a, RAA_UserRecordAccessSummaryDTO b) {
            if (a.hasAnyAccess != b.hasAnyAccess) {
                return a.hasAnyAccess ? -1 : 1;
            }
            return String.valueOf(a.recordDisplayName).compareTo(String.valueOf(b.recordDisplayName));
        }
    }
}
