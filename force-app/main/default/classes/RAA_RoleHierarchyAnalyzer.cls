/**
 * Detects access granted because a candidate user sits above the record owner's role in the
 * role hierarchy. "Grant Access Using Hierarchies" cannot be disabled for standard objects
 * (Salesforce enforces it unconditionally), so hierarchy access is reported at High confidence
 * for standard objects. For custom objects the checkbox is optional and its current value is
 * not exposed through any supported Apex, Schema, or SOQL API, so hierarchy access on custom
 * objects is reported at Medium confidence with an explicit caveat rather than assumed true.
 * Only evaluated when the owner is a User with an assigned role; queue ownership and roleless
 * owners are handled by RAA_OwnershipAnalyzer instead.
 */
// Deliberately without sharing and CRUD/FLS-unchecked: part of the elevated scan pipeline (see
// docs/architecture.md §1, "Batch Apex runs in system mode"), reached only through the with-sharing
// controller's permission and per-record visibility gate.
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class RAA_RoleHierarchyAnalyzer implements RAA_IReasonAnalyzer {
    public String getAnalyzerName() {
        return 'Role Hierarchy';
    }

    // The UserRole query below has no WHERE/LIMIT because role-hierarchy ancestor/descendant
    // resolution fundamentally needs the full parent-chain graph - an arbitrary LIMIT would
    // silently produce wrong hierarchy answers in larger orgs, which is worse than this.
    @SuppressWarnings('PMD.AvoidNonRestrictiveQueries')
    public Map<Id, List<RAA_AccessReasonDTO>> analyze(RAA_AnalysisContext context, Set<Id> userIds) {
        Map<Id, List<RAA_AccessReasonDTO>> results = new Map<Id, List<RAA_AccessReasonDTO>>();

        if (context.ownerId == null || context.ownerId.getSObjectType() != User.SObjectType) {
            return results;
        }

        List<User> ownerRows = [SELECT Id, UserRoleId, UserRole.Name FROM User WHERE Id = :context.ownerId LIMIT 1];
        if (ownerRows.isEmpty() || ownerRows[0].UserRoleId == null) {
            return results;
        }
        Id ownerRoleId = ownerRows[0].UserRoleId;
        String ownerRoleName = ownerRows[0].UserRole.Name;

        Map<Id, Id> parentByRole = new Map<Id, Id>();
        for (UserRole role : [SELECT Id, ParentRoleId FROM UserRole]) {
            parentByRole.put(role.Id, role.ParentRoleId);
        }

        Set<Id> ancestorRoleIds = new Set<Id>();
        Id cursor = parentByRole.get(ownerRoleId);
        Integer guard = 0;
        while (cursor != null && guard < 200) {
            if (ancestorRoleIds.contains(cursor)) {
                break; // cycle guard - malformed role hierarchy data should never loop, but never trust it blindly
            }
            ancestorRoleIds.add(cursor);
            cursor = parentByRole.get(cursor);
            guard++;
        }

        if (ancestorRoleIds.isEmpty()) {
            return results;
        }

        Boolean isStandardObject = context.objectApiName != null && !context.objectApiName.endsWith('__c');
        String confidence = isStandardObject ? 'High' : 'Medium';
        String caveat = isStandardObject
            ? 'Grant Access Using Hierarchies cannot be disabled for standard objects, so this hierarchy access is enforced by the platform.'
            : 'This is a custom object; whether "Grant Access Using Hierarchies" is enabled cannot be confirmed through a supported Apex, Schema, or SOQL API, so this reason is reported at Medium confidence.';

        for (User candidate : [
            SELECT Id, UserRoleId, UserRole.Name
            FROM User
            WHERE Id IN :userIds AND UserRoleId IN :ancestorRoleIds
        ]) {
            RAA_AccessReasonDTO reason = new RAA_AccessReasonDTO();
            reason.category = 'Role Hierarchy';
            reason.accessLevel = 'Inherited from owner';
            reason.confidence = confidence;
            reason.isDirect = false;
            reason.sourceName = 'Role: ' + candidate.UserRole.Name;
            reason.sourceId = candidate.UserRoleId;
            reason.sourceObject = 'UserRole';
            reason.principalId = candidate.UserRoleId;
            reason.principalType = 'RoleAndSubordinates';
            reason.rowCause = null;
            reason.grantPath = context.prefixedPath(
                'Role Hierarchy: ' + candidate.UserRole.Name + ' (above owner role ' + ownerRoleName + ') -> User'
            );
            reason.explanation =
                'The user\'s role (' +
                candidate.UserRole.Name +
                ') is above the record owner\'s role (' +
                ownerRoleName +
                ') in the role hierarchy. ' +
                caveat;
            reason.evidence =
                'Owner role: ' +
                ownerRoleId +
                '; user role: ' +
                candidate.UserRoleId +
                '; ancestor role chain size: ' +
                ancestorRoleIds.size();

            List<RAA_AccessReasonDTO> reasonList = results.get(candidate.Id);
            if (reasonList == null) {
                reasonList = new List<RAA_AccessReasonDTO>();
                results.put(candidate.Id, reasonList);
            }
            reasonList.add(reason);
        }

        return results;
    }
}
