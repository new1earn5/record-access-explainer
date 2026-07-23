/**
 * Small shared helper for bulk-loading a user's assigned permission sets (direct, profile-owned,
 * and via permission set groups). Used by both RAA_PermissionAnalyzer and RAA_FieldAccessService
 * so the same PermissionSetAssignment query shape exists in exactly one place.
 */
public without sharing class RAA_PermissionSetLookup {
    public List<PermissionSetAssignment> getAssignments(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return new List<PermissionSetAssignment>();
        }
        return [
            SELECT
                AssigneeId,
                PermissionSetId,
                PermissionSetGroupId,
                PermissionSet.Label,
                PermissionSet.IsOwnedByProfile,
                PermissionSet.Profile.Name,
                PermissionSetGroup.MasterLabel
            FROM PermissionSetAssignment
            WHERE AssigneeId IN :userIds
        ];
    }

    public Set<Id> permissionSetIds(List<PermissionSetAssignment> assignments) {
        Set<Id> ids = new Set<Id>();
        for (PermissionSetAssignment psa : assignments) {
            ids.add(psa.PermissionSetId);
        }
        return ids;
    }
}
