/**
 * Standalone org-wide oversharing scan: for a chosen set of objects, finds every Profile or
 * Permission Set that grants View All Records, Modify All Records, or full object-level CRUD
 * (Create+Read+Edit+Delete all true), and reports how many currently active users hold it.
 * Entries with zero active users are dropped - a bypass nobody currently holds isn't exposure,
 * matching the same "only real, current beneficiaries matter" principle already used for the
 * per-record dead-sharing-rule-target hygiene note (see RAA_ShareRowAnalyzer).
 *
 * Unlike every other scan in this package, this is entirely schema/setup-metadata (Object
 * Permissions, Profiles, Permission Sets) - no record is read, no RAA_Analysis__c row is
 * created, and nothing here depends on UserRecordAccess or the reason-attribution pipeline.
 */
public without sharing class RAA_OrgWideAccessService {
    @TestVisible
    private static final Integer MAX_OBJECTS_PER_SCAN = 10;

    // ObjectPermissions and PermissionSet are setup metadata, not record data - this scan's
    // entire purpose is to see grants the running user may not personally hold, so WITH USER_MODE
    // would be actively wrong here (it would hide the very oversharing this method looks for).
    @SuppressWarnings('PMD.ApexCRUDViolation')
    public List<RAA_OrgWideAccessDTO> scanObjectPermissions(List<String> rawObjectApiNames) {
        List<String> objectApiNames = normalizeAndValidate(rawObjectApiNames);

        List<ObjectPermissions> riskyPermissions = [
            SELECT ParentId, SobjectType, PermissionsViewAllRecords, PermissionsModifyAllRecords
            FROM ObjectPermissions
            WHERE
                SobjectType IN :objectApiNames
                AND (PermissionsViewAllRecords = TRUE
                OR PermissionsModifyAllRecords = TRUE
                OR (PermissionsCreate = TRUE
                AND PermissionsRead = TRUE
                AND PermissionsEdit = TRUE
                AND PermissionsDelete = TRUE))
        ];
        if (riskyPermissions.isEmpty()) {
            return new List<RAA_OrgWideAccessDTO>();
        }

        Set<Id> parentIds = new Set<Id>();
        for (ObjectPermissions op : riskyPermissions) {
            parentIds.add(op.ParentId);
        }

        Map<Id, PermissionSet> permSetById = new Map<Id, PermissionSet>(
            [SELECT Id, Label, IsOwnedByProfile, ProfileId, Profile.Name FROM PermissionSet WHERE Id IN :parentIds]
        );

        Set<Id> profileIds = new Set<Id>();
        Set<Id> directPermSetIds = new Set<Id>();
        for (PermissionSet ps : permSetById.values()) {
            if (ps.IsOwnedByProfile) {
                profileIds.add(ps.ProfileId);
            } else {
                directPermSetIds.add(ps.Id);
            }
        }

        Map<Id, Integer> activeUserCountByProfile = activeUserCountsByProfile(profileIds);
        Map<Id, Integer> activeUserCountByPermSet = activeUserCountsByPermissionSet(directPermSetIds);

        List<RAA_OrgWideAccessDTO> results = new List<RAA_OrgWideAccessDTO>();
        for (ObjectPermissions op : riskyPermissions) {
            PermissionSet ps = permSetById.get(op.ParentId);
            if (ps == null) {
                continue;
            }
            Integer activeUserCount = ps.IsOwnedByProfile
                ? countOf(activeUserCountByProfile, ps.ProfileId)
                : countOf(activeUserCountByPermSet, ps.Id);
            if (activeUserCount == 0) {
                continue;
            }

            RAA_OrgWideAccessDTO dto = new RAA_OrgWideAccessDTO();
            dto.principalName = ps.IsOwnedByProfile ? ps.Profile.Name : ps.Label;
            dto.principalType = ps.IsOwnedByProfile ? 'Profile' : 'Permission Set';
            dto.objectApiName = op.SobjectType;
            dto.hasViewAllRecords = op.PermissionsViewAllRecords;
            dto.hasModifyAllRecords = op.PermissionsModifyAllRecords;
            dto.hasFullObjectCrud = !op.PermissionsViewAllRecords && !op.PermissionsModifyAllRecords;
            dto.activeUserCount = activeUserCount;
            results.add(dto);
        }

        results.sort(new ByRiskThenActiveUserCountDescending());
        return results;
    }

    private List<String> normalizeAndValidate(List<String> rawObjectApiNames) {
        if (rawObjectApiNames == null || rawObjectApiNames.isEmpty()) {
            throw new RAA_AppException('Enter at least one object API name to scan.');
        }
        Set<String> deduped = new Set<String>();
        List<String> normalized = new List<String>();
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        for (String raw : rawObjectApiNames) {
            String trimmed = raw == null ? '' : raw.trim();
            if (String.isBlank(trimmed)) {
                continue;
            }
            if (!globalDescribe.containsKey(trimmed.toLowerCase())) {
                throw new RAA_AppException('"' + trimmed + '" is not a recognized object API name.');
            }
            String canonical = globalDescribe.get(trimmed.toLowerCase()).getDescribe().getName();
            if (deduped.add(canonical)) {
                normalized.add(canonical);
            }
        }
        if (normalized.isEmpty()) {
            throw new RAA_AppException('Enter at least one object API name to scan.');
        }
        if (normalized.size() > MAX_OBJECTS_PER_SCAN) {
            throw new RAA_AppException('Scan at most ' + MAX_OBJECTS_PER_SCAN + ' objects at a time.');
        }
        return normalized;
    }

    // User and setup-metadata counts, not record data subject to FLS/CRUD; see the suppression
    // note on scanObjectPermissions above.
    @SuppressWarnings('PMD.ApexCRUDViolation')
    private Map<Id, Integer> activeUserCountsByProfile(Set<Id> profileIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (profileIds.isEmpty()) {
            return counts;
        }
        for (AggregateResult row : [
            SELECT ProfileId profileId, COUNT(Id) userCount
            FROM User
            WHERE ProfileId IN :profileIds AND IsActive = TRUE
            GROUP BY ProfileId
        ]) {
            counts.put((Id) row.get('profileId'), (Integer) row.get('userCount'));
        }
        return counts;
    }

    // PermissionSetAssignment is setup metadata, not record data; see the suppression note on
    // scanObjectPermissions above.
    @SuppressWarnings('PMD.ApexCRUDViolation')
    private Map<Id, Integer> activeUserCountsByPermissionSet(Set<Id> permSetIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (permSetIds.isEmpty()) {
            return counts;
        }
        for (AggregateResult row : [
            SELECT PermissionSetId permSetId, COUNT(Id) userCount
            FROM PermissionSetAssignment
            WHERE PermissionSetId IN :permSetIds AND Assignee.IsActive = TRUE
            GROUP BY PermissionSetId
        ]) {
            counts.put((Id) row.get('permSetId'), (Integer) row.get('userCount'));
        }
        return counts;
    }

    private Integer countOf(Map<Id, Integer> counts, Id key) {
        return counts.containsKey(key) ? counts.get(key) : 0;
    }

    private class ByRiskThenActiveUserCountDescending implements Comparator<RAA_OrgWideAccessDTO> {
        public Integer compare(RAA_OrgWideAccessDTO a, RAA_OrgWideAccessDTO b) {
            Integer rankA = riskRank(a);
            Integer rankB = riskRank(b);
            if (rankA != rankB) {
                return rankA - rankB;
            }
            return b.activeUserCount - a.activeUserCount;
        }

        private Integer riskRank(RAA_OrgWideAccessDTO dto) {
            if (dto.hasModifyAllRecords) {
                return 0;
            }
            if (dto.hasViewAllRecords) {
                return 1;
            }
            return 2;
        }
    }
}
